"""Explicit chapter-only wave adaptation. Original facts and unit panels stay immutable."""
from pathlib import Path
import collections
import copy
import hashlib
import json
import statistics
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from unit_registry import UnitRegistry
REGISTRY = UnitRegistry.load(Path(__file__).resolve().parents[2])

HERE = Path(__file__).resolve().parent
SOURCE = HERE / 'difficulty.source.json'
FACTS = HERE.parents[1] / 'data/stages/books/cf6-sting-source/encounter-facts.v1.json'
SCHEMA = 'cf6-difficulty-source.v1'
META = 'chapterDifficulty'
TRANSPORT = {'A09': ('cf6.特种兵.持盾一阶段', 45, 5), 'A14': ('cf6.光头保安.变身型', 50, 7), 'A18': ('cf6.蛮斧刽子手', 59, 5)}
QUOTAS = {'E1':'A09','E2':'A13','E3':'A14','E4':'A17','E5':'A19'}
PRIVATE = {'cf6BossOwnerToken','cf6SupportIdentity','cf6PodId','产生源','老头变身','MapNoCount','NoCount'}
PLAN_IDS = {'A01','A02','A03','A04','A05','A06','A09','A10','A11','A12','A13','A14','A15','A17','A18','A19','A20','A22'}


def _canonical(value):
    if isinstance(value, dict):
        return {k: _canonical(v) for k, v in value.items()}
    if isinstance(value, list):
        return [_canonical(v) for v in value]
    if isinstance(value, str) and value in REGISTRY.by_key:
        return '兵种' + str(REGISTRY.by_key[value])
    return value


def digest(value):
    return hashlib.sha256(json.dumps(_canonical(value), ensure_ascii=False, sort_keys=True,
                                     separators=(',', ':')).encode('utf-8')).hexdigest()


def load():
    return json.loads(SOURCE.read_text('utf-8'))


def original_progression():
    """Only proven original spawns unlock an enemy; dormant templates do not.

    Preserve a boss's first encounter separately from its later ordinary copies.
    A10's guard transformation reveals an alien successor, but direct alien
    placements still start at A15's five pods.
    """
    facts = json.loads(FACTS.read_text('utf-8'))
    if facts['source']['swfSha256'] != 'b52af10e2dda43332e0b2ffb9549d2fad474f298b9f6c67d848ffc33ff589b01':
        raise ValueError('original encounter source identity changed')
    result = {}
    def remember(unit, mid, role, evidence):
        row = result.setdefault(unit, {})
        row.setdefault(role, dict(mapId=mid, evidence=evidence))
    for node in facts['maps']:
        mid = node['id']
        if not mid.startswith('A'): continue
        boss = node.get('boss')
        triggers = {t['target'] for t in node['triggerZones']}
        for index, enemy in enumerate(node['statics']):
            unit = 'thug_tf' if enemy.get('unitKey') == 'thug' and enemy.get('transform') == 1 else enemy['unitKey']
            role = 'boss' if boss and enemy['depth'] == boss['depth'] else 'ordinary'
            remember(unit, mid, role, 'statics/' + str(index))
        for index, enemy in enumerate(node['generators']):
            if enemy['initialState'] != 'free' and enemy['instance'] not in triggers: continue
            unit = 'thug_tf' if enemy.get('unitKey') == 'thug' and enemy.get('transform') == 1 else enemy['unitKey']
            remember(unit, mid, 'ordinary', 'generators/' + str(index))
        if node['alienEggs']:
            remember('alien', mid, 'ordinary', 'alienEggs')
    return result


def require_original_unit(unit, mid, progression, role='ordinary'):
    first = progression.get(unit, {}).get(role)
    if first is None or mid < first['mapId']:
        raise ValueError('enemy precedes original ' + role + ' appearance: ' + mid + '/' + unit)


def waves(node):
    return node['stage']['Wave']['SubWave']


def wave_enemies(node):
    return [enemy for wave in waves(node) for enemy in wave['EnemyGroup']['Enemy']]


def supports(node):
    return [enemy for group in node.get('bossEncounter', {}).get('groups', []) for enemy in group['enemies']]


def quota_rows(nodes):
    result = {}
    for node in nodes:
        for enemy in wave_enemies(node) + supports(node):
            quota = enemy.get('Parameters', {}).get('cf6EliteQuota')
            if quota is None: continue
            if quota not in QUOTAS or QUOTAS[quota] != node['id'] or quota in result or enemy['Quantity'] != 1:
                raise ValueError('difficulty elite quota is duplicate, misplaced or multiplied')
            result[quota] = copy.deepcopy(enemy)
    if set(result) != set(QUOTAS): raise ValueError('difficulty requires all five original elite carriers')
    return result


def quota_authority(row):
    return {key: copy.deepcopy(row[key]) for key in ('Type','Level','Quantity','Parameters')}


def wave_bound(wave, points):
    """WaveSpawner caps each distinct point, not each enemy entry using that point."""
    assigned, unbounded = collections.Counter(), 0
    for enemy in wave['EnemyGroup']['Enemy']:
        index = enemy.get('SpawnIndex')
        if type(index) is int and 0 <= index < len(points): assigned[index] += enemy['Quantity']
        else: unbounded += enemy['Quantity']
    bounded = []
    for index, quantity in sorted(assigned.items()):
        point = points[index]
        cap = point.get('QuantityMax')
        if type(cap) is not int or cap < 1 or point.get('NoCount') is True:
            raise ValueError('difficulty indexed producer must have a positive counted capacity')
        bounded.append(dict(index=index, quantity=quantity, capacity=cap, possibleAlive=min(cap,quantity)))
    return dict(indexedPoints=bounded, mapBucketOrStatic=unbounded,
                upperBound=unbounded + sum(row['possibleAlive'] for row in bounded))


def metadata(node):
    value = node.get('sourceNote',{}).get(META)
    if value is None: return None
    config=load();spec=config['maps'].get(node['id'])
    if (spec is None or value.get('schema')!=SCHEMA or value.get('sourceSha256')!=digest(config)
            or value.get('waveKinds')!=[w['kind'] for w in spec['waves']]
            or len(waves(node))!=len(spec['waves']) or value.get('screenLimit')!=spec['screenLimit']):
        raise ValueError('unreviewed difficulty assembly metadata')
    roles=value.get('spawnPointRoles');points=node['stage'].get('SpawnPoint',{}).get('Point',[])
    expected=['left','right'] if any(w['kind']=='combat' for w in spec['waves']) else []
    if type(roles) is not list or [r.get('side') for r in roles]!=expected or len({r.get('index') for r in roles})!=len(roles):
        raise ValueError('invalid difficulty point role inventory')
    for role in roles:
        index=role.get('index')
        if type(index) is not int or not 0<=index<len(points) or points[index].get('QuantityMax')!=spec['screenLimit']//2 or points[index].get('NoCount') is True:
            raise ValueError('difficulty point capacity or ownership drift')
    return value


def _support_policy(node, policy):
    old = node['bossEncounter']
    initial = copy.deepcopy(old['groups'][0])
    if initial['hpRatio'] != 1: raise ValueError('difficulty requires the original initial support group')
    if policy == 'retain-initial-group':
        old['groups'] = [initial]
    elif policy == 'pods-and-small-escort':
        if node['id'] != 'A17' or old['maxAlive'] != 4 or old['intervalFrames'] != 45:
            raise ValueError('A17 original pod controller contract changed')
        pods = [e for e in initial['enemies'] if REGISTRY.resolve_id(e['Type']) == 460]
        guards = [e for e in initial['enemies'] if REGISTRY.resolve_id(e['Type']) == 469][:2]
        zombies = [e for e in initial['enemies'] if REGISTRY.resolve_id(e['Type']) == 461]
        if len(pods) != 1 or pods[0]['Quantity'] != 5 or len(guards) != 2 or len(zombies) != 1:
            raise ValueError('A17 five original pods and three escorts changed')
        old['groups'] = [dict(hpRatio=1.0, enemies=pods + guards + zombies)]
    else: raise ValueError('unreviewed difficulty support policy')


def adapt(document, factory, config=None):
    config = load() if config is None else copy.deepcopy(config)
    if (config.get('schema') != SCHEMA or set(config['maps']) != PLAN_IDS or set(config['maps']) != set(config['sourceCounts'])
            or config['preserveMaps'] != ['TUTORIAL','A08','A16']):
        raise ValueError('invalid difficulty source inventory')
    if {k:REGISTRY.resolve_id(v) for k,v in config['unitTypes'].items()} != {k:v['id'] for k,v in factory['UNIT_MAP'].items()}:
        raise ValueError('difficulty unit mapping diverges from existing source authority')
    original = copy.deepcopy(document)
    result = copy.deepcopy(document)
    nodes = {node['id']:node for node in result['maps']}
    before_quotas = quota_rows(result['maps'])
    preserved = {mid:digest(nodes[mid]) for mid in config['preserveMaps']}
    baseline = {}
    progression = original_progression()
    for mid, spec in config['maps'].items():
        node = nodes[mid]
        if META in node['sourceNote']: raise ValueError('difficulty adaptation already applied')
        count = [sum(e['Quantity'] for e in wave_enemies(node)),sum(e['Quantity'] for e in supports(node))]
        if count != config['sourceCounts'][mid]: raise ValueError('unreviewed original difficulty budget: ' + mid)
        baseline[mid] = dict(primaryWave=count[0], optionalSupport=count[1],
                             enemyAuthoritySha256=digest(wave_enemies(node)+supports(node)))
        if not 1 <= len(spec['waves']) <= 6 or type(spec['screenLimit']) is not int or not 1 <= spec['screenLimit'] <= 14:
            raise ValueError('difficulty waves or screen limit exceeded')
        old_waves = copy.deepcopy(waves(node))
        points = node['stage'].setdefault('SpawnPoint', {}).setdefault('Point', [])
        roles = []
        if any(w['kind'] == 'combat' for w in spec['waves']):
            old_y = [e['y'] for e in wave_enemies(node) if type(e.get('y')) in (int,float)]
            preferred_y = statistics.median(old_y) if old_y else node['stage']['BasicInformation']['PlayerY']
            for side in ('left','right'):
                index = len(points)
                points.append(dict(x=-50 if side=='left' else 5000, y=preferred_y,
                                   QuantityMax=spec['screenLimit']//2))
                roles.append(dict(index=index, side=side))
        point_ids = {row['side']:row['index'] for row in roles}
        new_waves = []
        for wi, recipe in enumerate(spec['waves']):
            kind = recipe['kind']
            if kind == 'boss':
                if wi != len(spec['waves'])-1 or len(old_waves)!=1 or len(old_waves[0]['EnemyGroup']['Enemy'])!=1:
                    raise ValueError('difficulty boss must remain the final unique native boss')
                new_waves.append(copy.deepcopy(old_waves[0]));continue
            if kind == 'transport':
                if mid not in TRANSPORT or wi != 1 or len(old_waves)!=2:
                    raise ValueError('difficulty transport must retain its original second-wave ownership')
                source = old_waves[1]['EnemyGroup']['Enemy']
                if len(source)!=1 or (REGISTRY.resolve_id(source[0]['Type']),source[0]['Level'],source[0]['Quantity']) != (REGISTRY.resolve_id(TRANSPORT[mid][0]),TRANSPORT[mid][1],TRANSPORT[mid][2]):
                    raise ValueError('difficulty transport budget changed')
                new_waves.append(copy.deepcopy(old_waves[1]));continue
            if kind == 'pods':
                if mid!='A15' or wi!=0 or len(old_waves)!=1:
                    raise ValueError('A15 original five-pod wave must remain first')
                source=old_waves[0]['EnemyGroup']['Enemy']
                if len(source)!=1 or (REGISTRY.resolve_id(source[0]['Type']),source[0]['Level'],source[0]['Quantity'])!=(460,50,5):
                    raise ValueError('difficulty pod source changed')
                new_waves.append(copy.deepcopy(old_waves[0]));continue
            if kind not in ('combat', 'elevator') or not 1 <= len(recipe.get('groups',[])) <= 8:
                raise ValueError('unknown or unbounded difficulty wave')
            if kind == 'elevator' and (mid not in ('A10','A13') or len(spec['waves']) != 1
                    or len(recipe.get('positions', [])) != sum(g['count'] for g in recipe['groups'])
                    or len({tuple(p) for p in recipe['positions']}) != len(recipe['positions'])):
                raise ValueError('elevator requires one fully preplaced encounter')
            entries, side_load = [], {'left':0,'right':0}
            for group in recipe['groups']:
                unit, quantity = group['unit'], group['count']
                if type(quantity) is not int or not 1 <= quantity <= 32: raise ValueError('invalid difficulty group quantity')
                if unit == 'elite':
                    quota=group['quota']
                    if QUOTAS.get(quota)!=mid or quantity!=1: raise ValueError('difficulty quota moved to another room')
                    source=copy.deepcopy(before_quotas[quota])
                    for key in ('InstanceName','x','y','SpawnIndex','ranged','podId'): source.pop(key,None)
                    require_original_unit('specop' if REGISTRY.resolve_id(source['Type'])==466 else 'specop_shield', mid, progression)
                else:
                    if unit not in factory['UNIT_MAP']: raise ValueError('unknown difficulty unit')
                    require_original_unit(unit, mid, progression)
                    parameters=factory['gun_params'](unit,'g36') or {}
                    if group.get('turretEligible'):
                        if mid!='A01' or unit!='zombie': raise ValueError('turret tag widened beyond original compatible unit')
                        parameters['目标标记']=factory['TURRET_FILTER_MARKER']
                    source=factory['enemy'](unit,factory['level_for'](mid,unit),quantity,params=parameters)
                if kind == 'elevator':
                    for _ in range(quantity):
                        x,y = recipe['positions'][len(entries)]
                        if type(x) not in (int,float) or type(y) not in (int,float) or not 260 <= x <= 480 or not 260 <= y <= 300:
                            raise ValueError('elevator placement outside reviewed platform interior')
                        entry=copy.deepcopy(source);entry.update(Quantity=1,x=x,y=y)
                        entries.append(entry)
                    continue
                if 'side' in group:
                    if group['side'] not in point_ids: raise ValueError('invalid difficulty side')
                    allocation={group['side']:quantity}
                else:
                    allocation={'left':quantity//2,'right':quantity//2}
                    if quantity%2: allocation[min(side_load,key=side_load.get)]+=1
                for side,count in allocation.items():
                    if count<1: continue
                    entry=copy.deepcopy(source);entry.update(Quantity=count,SpawnIndex=point_ids[side],Interval=100)
                    entries.append(entry);side_load[side]+=count
            if not entries or len(entries)>16: raise ValueError('difficulty queue entry count exceeded')
            new_waves.append(dict(WaveInformation=dict(Duration=0,FinishRequirement=0),EnemyGroup=dict(Enemy=entries)))
        node['stage']['Wave']['SubWave']=new_waves
        if 'supportPolicy' in spec: _support_policy(node,spec['supportPolicy'])
        node['sourceNote'][META]=dict(schema=SCHEMA,source=SOURCE.relative_to(HERE.parents[1]).as_posix(),
            sourceSha256=digest(config),waveKinds=[w['kind'] for w in spec['waves']],
            spawnPointRoles=roles,screenLimit=spec['screenLimit'],baseline=baseline[mid],
            authority='chapter design adaptation; original source facts retained; no global unit/player edits')
        node['sourceNote']['notes'].append('2026-10-24章节难度适配：遵循原作首次登场，以已登场敌人数量承载难度；两段电梯为一波预置敌人，原生Boss转换与可选旁支取消保持。')
    if any(digest(nodes[mid]) != pin for mid,pin in preserved.items()): raise AssertionError('breathing/tutorial map changed')
    after_quotas=quota_rows(result['maps'])
    if {q:quota_authority(e) for q,e in before_quotas.items()} != {q:quota_authority(e) for q,e in after_quotas.items()}:
        raise AssertionError('elite gun/quantity/level authority changed')
    audit=validate(result,config)
    audit.update(baseline=baseline,preservedMaps=preserved,
                 originalDocumentSha256=digest(original),adaptedDocumentSha256=digest(result))
    return result,audit


def validate(document,config=None):
    config=load() if config is None else config
    progression=original_progression()
    unit_for_type={REGISTRY.resolve_id(v):k for k,v in config['unitTypes'].items() if k!='zombie_turret'}
    rows=[]
    for node in document['maps']:
        mid=node['id']
        if mid not in config['maps']: continue
        spec=config['maps'][mid];meta=node['sourceNote'][META];points=node['stage'].get('SpawnPoint',{}).get('Point',[])
        if meta['sourceSha256']!=digest(config) or len(waves(node))!=len(spec['waves']): raise ValueError('difficulty plan identity or wave count drift')
        if node['stage'].get('BasicInformation',{}).get('MapNoCount') is True: raise ValueError('difficulty map budget cannot bypass counts')
        counts=[];bounds=[];types=collections.Counter()
        for wi,(wave,recipe) in enumerate(zip(waves(node),spec['waves'])):
            if wave['WaveInformation'].get('Duration')!=0 or wave['WaveInformation'].get('FinishRequirement')!=0:
                raise ValueError('difficulty wave is not sequential and mandatory')
            enemies=wave['EnemyGroup']['Enemy']
            if not enemies: raise ValueError('empty difficulty combat wave')
            if recipe['kind'] in ('combat','elevator'):
                if sum(e['Quantity'] for e in enemies)!=sum(g['count'] for g in recipe['groups']): raise ValueError('difficulty wave budget drift')
                expected_types=collections.Counter()
                for group in recipe['groups']:
                    if group['unit']=='elite':
                        kind=config['unitTypes']['specop' if group['quota'] in ('E1','E3') else 'specop_shield']
                    else: kind=config['unitTypes'][group['unit']]
                    expected_types[kind]+=group['count']
                actual_types=collections.Counter()
                for enemy in enemies: actual_types[enemy['Type']]+=enemy['Quantity']
                if actual_types!=expected_types: raise ValueError('difficulty unit composition drift')
                if recipe['kind']=='elevator' and [[e.get('x'),e.get('y')] for e in enemies] != recipe['positions']:
                    raise ValueError('elevator preplaced formation drift')
                for enemy in enemies:
                    require_original_unit(unit_for_type[REGISTRY.resolve_id(enemy['Type'])],mid,progression)
                    if 'InstanceName' in enemy or PRIVATE & set(enemy.get('Parameters',{})) or 'TriggerEvent' in enemy:
                        raise ValueError('ordinary mandatory wave acquired private identity or trigger')
                    if recipe['kind']=='elevator' and (len(waves(node))!=1 or enemy['Quantity']!=1
                            or any(k in enemy for k in ('SpawnIndex','Delay','Interval'))
                            or [enemy.get('x'),enemy.get('y')] not in recipe['positions']):
                        raise ValueError('elevator cannot add delayed or queued reinforcements')
            if recipe['kind']=='transport':
                if wi!=1 or len(enemies)!=1 or (REGISTRY.resolve_id(enemies[0]['Type']),enemies[0]['Level'],enemies[0]['Quantity'])!=(REGISTRY.resolve_id(TRANSPORT[mid][0]),TRANSPORT[mid][1],TRANSPORT[mid][2]):
                    raise ValueError('difficulty transport ledger drift')
            if recipe['kind']=='pods':
                if mid!='A15' or wi!=0 or sum(e['Quantity'] for e in enemies)!=5 or any(REGISTRY.resolve_id(e['Type'])!=460 or e['Level']!=50 for e in enemies):
                    raise ValueError('difficulty original A15 five-pod ledger drift')
            if recipe['kind']=='boss':
                boss=node.get('bossEncounter');expected={'A06':463,'A17':472,'A20':473,'A22':474}
                if wi!=len(waves(node))-1 or len(enemies)!=1 or enemies[0]['Quantity']!=1 or boss is None or enemies[0].get('InstanceName')!=boss['instanceName'] or REGISTRY.resolve_id(enemies[0]['Type'])!=expected[mid]:
                    raise ValueError('difficulty terminal boss identity drift')
            bound=wave_bound(wave,points)
            if bound['upperBound']>spec['screenLimit']: raise ValueError('distinct spawn point capacities exceed room limit')
            counts.append(sum(e['Quantity'] for e in enemies));bounds.append(bound)
            for enemy in enemies:types[enemy['Type']]+=enemy['Quantity']
        optional=sum(e['Quantity'] for e in supports(node))
        for enemy in supports(node): require_original_unit(unit_for_type[REGISTRY.resolve_id(enemy['Type'])],mid,progression)
        if optional!=spec.get('optionalSupportBudget',0): raise ValueError('difficulty optional support ledger drift')
        if mid=='A17' and (sum(e['Quantity'] for e in supports(node) if REGISTRY.resolve_id(e['Type'])==460)!=5 or any(e['Level']!=55 for e in supports(node) if REGISTRY.resolve_id(e['Type'])==460)):
            raise ValueError('difficulty original A17 five-pod ledger drift')
        boss=node.get('bossEncounter')
        peak=max(row['upperBound'] for row in bounds)
        if boss: peak=max(peak,1+min(optional,boss['maxAlive']))
        if peak>spec['screenLimit']: raise ValueError('boss plus optional support exceeds room limit')
        rows.append(dict(mapId=mid,waveCounts=counts,waveKinds=meta['waveKinds'],mandatoryPrimary=sum(counts),
                         optionalSupport=optional,totalPrimary=sum(counts)+optional,peakAliveUpperBound=peak,
                         configuredRoomLimit=spec['screenLimit'],perWaveConcurrency=bounds,mandatoryTypes=dict(types),
                         possible469Successors=sum(e['Quantity'] for e in wave_enemies(node)+supports(node) if REGISTRY.resolve_id(e['Type'])==469)))
    marked=sum(e['Quantity'] for n in document['maps'] for e in wave_enemies(n)
               if e.get('Parameters',{}).get('目标标记')=='cf6-a01-turret-zombie')
    if marked!=20: raise ValueError('A01 original turret-compatible twenty-unit budget changed')
    quota_rows(document['maps'])
    by_id={r['mapId']:r for r in rows};human,robot=by_id['A20'],by_id['A22']
    merged=dict(mapId='A20',mandatoryPrimary=human['mandatoryPrimary']+robot['mandatoryPrimary'],
                optionalSupport=human['optionalSupport']+robot['optionalSupport'],
                totalPrimary=human['totalPrimary']+robot['totalPrimary'],peakAliveUpperBound=max(human['peakAliveUpperBound'],robot['peakAliveUpperBound']))
    return dict(schema='cf6-difficulty-audit.v1',sourceSha256=digest(config),originalProgression=progression,maps=rows,mergedFinale=merged,
                boundary='Deterministic authored quantities and structural upper bounds, not measured difficulty, timing, EHP or gameplay acceptance.')
