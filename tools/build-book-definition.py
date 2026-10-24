"""Validate editable book data and generate its AS2 definition. --check is read-only."""
import argparse
import copy
import importlib.util
import json
import math
import re
from pathlib import Path
import shutil
import xml.etree.ElementTree as ET
from choice_reward_catalog import resolve_book_choices, validate_loadout, loadout_entries

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'data/stages/books/repair-campus.json'
OUTPUT = ROOT / 'scripts/类定义/org/flashNight/arki/scene/BookDefinition.as'
PACK_OUTPUT = ROOT / 'data/items/消耗品_书中配给.xml'
RECIPE_OUTPUT = ROOT / 'data/crafting/书中配给.json'
CF6_SOURCE = ROOT / 'data/stages/books/cf6-sting.json'


def validate_cf6(data, items, skills, units, require_backgrounds=True):
    """CF6 uses authored native stages; campus random loot and boss rules do not apply."""
    if (data.get('schema'), data.get('id'), data.get('routeId'), data.get('stageName')) != (
            'playable-book.v1', 'cf6-sting', 'historical', '书中历险-毒刺行动'):
        raise ValueError('unsupported CF6 chapter/route identity')
    def tree(value, depth=0):
        if depth > 24: raise ValueError('CF6 data nesting exceeds limit')
        if isinstance(value, dict):
            if any(k in ('__proto__', 'constructor', 'prototype') for k in value): raise ValueError('unsafe CF6 key')
            for child in value.values(): tree(child, depth+1)
        elif isinstance(value, list):
            if len(value) > 512: raise ValueError('oversized CF6 array')
            for child in value: tree(child, depth+1)
        elif isinstance(value, (int, float)) and not isinstance(value, bool):
            if not math.isfinite(value) or abs(value) > 1000000000: raise ValueError('invalid CF6 numeric value')
        elif isinstance(value, str):
            if len(value) > 4096: raise ValueError('oversized CF6 text')
        elif value is not None and not isinstance(value, bool): raise ValueError('invalid CF6 value')
    tree(data)
    if not isinstance(data.get('title'), str) or not data['title']: raise ValueError('missing CF6 title')
    bounded_integer(data['startingMoney'], 0, 10000000, 'CF6 starting money')
    bounded_integer(data['startingSkillPoints'], 0, 10000, 'CF6 spendable SP')
    actor = data['actor']
    if actor['level'] != 60 or actor['experience'] != 157526193 or actor['gender'] != '男':
        raise ValueError('historical actor must start at level 60 with matching XP')
    bounded_integer(actor['height'],100,250,'actor height')
    if any(not isinstance(actor[k], str) or not actor[k] for k in ('name','face')) or not isinstance(actor['hair'],str): raise ValueError('invalid actor appearance')
    slots = {'头部装备','上装装备','下装装备','手部装备','脚部装备','颈部装备','刀','长枪','手枪','手枪2'}
    used = set()
    if not 1 <= len(actor['equipment']) <= 10: raise ValueError('invalid initial equipment')
    for entry in actor['equipment']:
        if set(entry) != {'slot','name','enhancement'} or entry['slot'] not in slots or entry['slot'] in used:
            raise ValueError('invalid initial equipment slot')
        used.add(entry['slot'])
        item = items.get(entry['name'])
        expected_use = '手枪' if entry['slot'] == '手枪2' else entry['slot']
        if item is None or item.findtext('use') != expected_use or entry['enhancement'] != 11:
            raise ValueError('initial equipment identity/slot/enhancement mismatch')
        if int(item.findtext('data/level','0')) > 60: raise ValueError('initial equipment level too high')
    skill_catalog = {s.findtext('Name'):s for s in skills}
    used = set()
    if not 1 <= len(actor['skills']) <= 80: raise ValueError('invalid fixed skill list')
    for entry in actor['skills']:
        meta = skill_catalog.get(entry['name'])
        if set(entry) != {'name','level'} or meta is None or entry['name'] in used or not meta.findtext('Type'):
            raise ValueError('unknown/duplicate fixed skill')
        if entry['name'] == '驾驶' or entry['level'] != int(meta.findtext('MaxLevel','0')):
            raise ValueError('historical fixed skills must be max level and exclude driving')
        used.add(entry['name'])
    maps = data['maps']
    if not isinstance(maps,list) or not 1 <= len(maps) <= 32: raise ValueError('invalid CF6 map count')
    ids = set()
    map_order = ['TUTORIAL'] + ['A%02d'%n for n in range(1,23) if n != 21]
    previous_position = -1
    for stage in maps:
        identity = stage['id']
        if identity in ids or identity == 'A21' or not re.fullmatch(r'(TUTORIAL|A(?:0[1-9]|1[0-9]|20|22))',identity):
            raise ValueError('duplicate/unsupported CF6 map identity')
        ids.add(identity)
        position = map_order.index(identity)
        if position <= previous_position: raise ValueError('CF6 maps must follow historical route order')
        previous_position = position
        background = stage['background']
        expected_background = 'cf6/CF6_Tutorial_BG.swf' if identity == 'TUTORIAL' else 'cf6/CF6_' + identity + '_BG.swf'
        if (not isinstance(background,str) or background != expected_background
                or (identity != 'TUTORIAL' and not re.fullmatch(r'cf6/CF6_A(?:0[1-9]|1[0-9]|20|22)_BG\.swf',background))):
            raise ValueError('CF6 background must match the exact registered map identity')
        if require_backgrounds and not (ROOT/'flashswf/backgrounds'/background).is_file(): raise ValueError('missing CF6 background '+background)
        presentation = stage.get('presentation')
        if (not isinstance(presentation, dict) or set(presentation) != {'scale','backgroundX','backgroundY'}
                or any(type(v) not in (int,float) or not math.isfinite(v) for v in presentation.values())
                or not 0 < presentation['scale'] < 4
                or abs(presentation['backgroundX']) >= 4000 or abs(presentation['backgroundY']) >= 4000
                or stage.get('mechanism',{}).get('assetScale') != presentation['scale']):
            raise ValueError('CF6 map presentation transform missing or inconsistent')
        if not isinstance(stage['title'],str) or not isinstance(stage['dialogue'],list) or len(stage['dialogue']) > 32:
            raise ValueError('invalid CF6 map title/dialogue')
        for line in stage['dialogue']:
            if set(line) not in ({'speaker','text'}, {'speaker','text','char'}) or not isinstance(line['speaker'],str) or len(line['speaker']) > 40 or not isinstance(line['text'],str) or not 1 <= len(line['text']) <= 160:
                raise ValueError('invalid CF6 dialogue')
            if 'char' in line:
                if line['speaker'] not in ('Andy','Andy Law') or line['char'] not in {
                        'Andy Law#普通','Andy Law#微笑','Andy Law#挑战','Andy Law#惊讶','Andy Law#侦察',
                        'Andy Law#严肃','Andy Law#愤怒'}:
                    raise ValueError('invalid CF6 dialogue portrait')
        native = stage['stage']
        validate_cf6_vehicle(stage)
        waves = native['Wave']['SubWave']
        if not isinstance(waves,list) or not 1 <= len(waves) <= 64: raise ValueError('invalid authored CF6 waves')
        for wave in waves:
            enemies = wave['EnemyGroup']['Enemy']
            if not isinstance(enemies,list) or len(enemies) > 128: raise ValueError('invalid authored CF6 enemies')
            for enemy in enemies:
                kind = enemy['Type']
                if not isinstance(kind,str) or not kind.startswith('兵种') or int(kind[2:]) not in units:
                    raise ValueError('unknown CF6 enemy '+str(kind))
                bounded_integer(enemy['Level'],1,60,'CF6 enemy level')
                bounded_integer(enemy['Quantity'],1,100,'CF6 authored count')
                for drop in enemy.get('Parameters',{}).get('掉落物',[]):
                    if drop['名字'] not in items: raise ValueError('unknown CF6 drop '+drop['名字'])
        if native.get('BasicInformation',{}).get('BookBoss') is not None:
            raise ValueError('CF6 must not use campus reinforcement controller')
        validate_cf6_turrets(stage)
        validate_cf6_transport(stage)
        validate_cf6_boss(stage, units, items)
    if any(m.get('mechanism',{}).get('elderFinale') is True for m in maps):
        if maps[-1]['id'] != 'A20' or 'A22' in ids:
            raise ValueError('merged elder finale must be the only final room')
    validate_cf6_interactive_props(data)
    from cf6_economy import validate_economy
    validate_economy(data, items)


def validate_cf6_vehicle(stage):
    mechanism = stage.get('mechanism', {})
    if stage['id'] != 'A07':
        if 'vehicle' in mechanism:
            raise ValueError('vehicle encounter is only supported in A07')
        return
    path = ROOT / 'tools/cf6-vehicle/chapter_fragment.py'
    spec = importlib.util.spec_from_file_location('cf6_vehicle_validation', path)
    vehicle = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(vehicle)
    expected, _, _ = vehicle.build(False)
    if (mechanism.get('vehicle') != expected['mechanism']['vehicle']
            or mechanism.get('kind') != 'plain' or mechanism.get('layers') != expected['mechanism']['layers']
            or stage['presentation'] != expected['presentation']
            or stage['stage'].get('Wave') != expected['stage']['Wave']
            or stage.get('bossEncounter') is not None):
        raise ValueError('A07 requires its exact authored vehicle encounter and empty ordinary wave')


def validate_cf6_transport(stage):
    """A transport gates exactly one existing second-wave budget and adds no units."""
    spec = stage.get('mechanism', {}).get('transport')
    waves = stage['stage']['Wave']['SubWave']
    events = [(wi, ei, enemy) for wi, wave in enumerate(waves)
              for ei, enemy in enumerate(wave['EnemyGroup']['Enemy'])
              if enemy.get('TriggerEvent', {}).get('EventName') == 'Cf6TransportReady']
    if spec is None:
        if events: raise ValueError('transport event has no owning presentation')
        return
    expected = {'A09':(112,'兵种467',45,5), 'A14':(505,'兵种469',50,7), 'A18':(147,'兵种463',59,5)}
    fields = {'schema','id','sourceSprite','url','x','y','sortY','artMatrix','hitBounds','frames','dispatchFrame','subWaveIndex'}
    if stage['id'] not in expected or not isinstance(spec, dict) or set(spec) != fields:
        raise ValueError('unreviewed transport map or fields')
    depth, kind, level, quantity = expected[stage['id']]
    token = stage['id']+'-transport-'+str(depth)
    if (spec['schema'] != 'cf6-transport.v1' or spec['id'] != token
            or spec['sourceSprite'] != 1868 or type(spec['sourceSprite']) is not int
            or spec['url'] != 'flashswf/backgrounds/cf6/preparation/CF6_Transport1868.swf'
            or any(type(spec[k]) is not int or spec[k] != v for k,v in [('frames',29),('dispatchFrame',29),('subWaveIndex',1)])):
        raise ValueError('transport native identity or timeline changed')
    def finite(v): return type(v) in (int,float) and math.isfinite(v) and abs(v)<1000000
    if any(not finite(spec[k]) for k in ('x','y','sortY')):
        raise ValueError('invalid transport world coordinate')
    for key, size in [('artMatrix',6),('hitBounds',4)]:
        if not isinstance(spec[key],list) or len(spec[key]) != size or any(not finite(v) for v in spec[key]):
            raise ValueError('invalid transport geometry')
    m, b = spec['artMatrix'], spec['hitBounds']
    if abs(m[0]*m[3]-m[1]*m[2])<=0.000001 or b[0]>=b[2] or b[1]>=b[3]:
        raise ValueError('degenerate transport geometry')
    if not 2 <= len(waves) <= 6 or len(waves[1]['EnemyGroup']['Enemy'])!=1 or [(w,e) for w,e,_ in events]!=[(1,0)]:
        raise ValueError('transport must gate only its existing second-wave entry')
    enemy = events[0][2]
    if (type(enemy.get('SpawnIndex')) is not int
            or tuple(enemy.get(k) for k in ('Type','Level','Quantity','Interval','SpawnIndex')) != (kind,level,quantity,400,0)
            or enemy['TriggerEvent'] != {'EventName':'Cf6TransportReady','Parameters':[token]}):
        raise ValueError('transport budget or event ownership changed')


def validate_cf6_interactive_props(data):
    """Bind the authored interactive instances to existing enemy budgets."""
    maps = {stage['id']: stage for stage in data['maps']}
    if not any('interactiveProps' in stage.get('mechanism', {}) for stage in maps.values()):
        return
    placements = {
        'A04': (1736, [336,343,350]), 'A08': (1838, [137,144,151]),
        'A11': (1838, [262]), 'A12': (1838, [200,207,214]),
        'A15': (1939, [759,828,897,966,1035]),
        'A17': (1939, [516,595,664,733,802]),
        'A18': (1976, [617]), 'A20': (1976, [239,246,253]),
    }
    def finite(value):
        return type(value) in (int, float) and math.isfinite(value)
    for identity, stage in maps.items():
        spec = stage.get('mechanism', {}).get('interactiveProps')
        if identity not in placements:
            if spec is not None: raise ValueError('interactive props on an unreviewed map')
            continue
        sprite, depths = placements[identity]
        kind = 'pod' if sprite == 1939 else 'barrel'
        expected = {f'{identity}-{kind}-{depth}' for depth in depths}
        if (not isinstance(spec, dict) or set(spec) != {'schema','props'}
                or spec['schema'] != 'cf6-interactive-props.v1'
                or not isinstance(spec['props'], list) or len(spec['props']) != len(expected)):
            raise ValueError('incomplete authored interactive props: '+identity)
        actual = {}
        for prop in spec['props']:
            fields = {'id','kind','sourceSprite','url','x','y','sortY','artMatrix','hitBounds','frames'}
            if kind == 'pod': fields.add('spawnAuthority')
            else: fields.add('groundY')
            if (not isinstance(prop, dict) or set(prop) != fields
                    or prop['id'] not in expected or prop['id'] in actual
                    or prop['kind'] != kind or prop['sourceSprite'] != sprite
                    or prop['frames'] != (25 if kind == 'pod' else 16)):
                raise ValueError('interactive prop identity or frame contract mismatch')
            asset_kind = 'Pod' if kind == 'pod' else 'Barrel'
            if prop['url'] != f'flashswf/backgrounds/cf6/preparation/CF6_Interactive{asset_kind}{sprite}.swf':
                raise ValueError('interactive prop source resource mismatch')
            if any(not finite(prop[key]) or abs(prop[key]) >= 10000 for key in ('x','y','sortY')):
                raise ValueError('interactive prop position must be finite world coordinates')
            if kind == 'barrel' and (not finite(prop['groundY']) or abs(prop['groundY']) >= 10000):
                raise ValueError('barrel ground axis must be explicit and finite')
            matrix, bounds = prop['artMatrix'], prop['hitBounds']
            if (not isinstance(matrix, list) or len(matrix) != 6
                    or any(not finite(v) or abs(v) >= 10000 for v in matrix)
                    or any(abs(v) > 4 for v in matrix[:4])
                    or abs(matrix[0]*matrix[3]-matrix[1]*matrix[2]) < 0.000001):
                raise ValueError('interactive prop art matrix is invalid')
            if (not isinstance(bounds, list) or len(bounds) != 4
                    or any(not finite(v) or abs(v) >= 2000 for v in bounds)
                    or bounds[0] >= bounds[2] or bounds[1] >= bounds[3]):
                raise ValueError('interactive prop hit area is invalid')
            if kind == 'pod' and prop['spawnAuthority'] != ('wave' if identity == 'A15' else 'boss'):
                raise ValueError('clone pod spawn authority mismatch')
            actual[prop['id']] = prop
        if set(actual) != expected: raise ValueError('interactive instance inventory mismatch')
        if kind != 'pod': continue
        if identity == 'A15':
            waves = stage['stage']['Wave']['SubWave']
            if not 1 <= len(waves) <= 6: raise ValueError('A15 requires its counted pod wave and bounded later waves')
            enemies = waves[0]['EnemyGroup']['Enemy']
            if len(enemies) != 5: raise ValueError('A15 pod budget must remain five')
            for later in waves[1:]:
                for enemy in later['EnemyGroup']['Enemy']:
                    if ('podId' in enemy or 'cf6PodId' in enemy.get('Parameters', {})
                            or enemy.get('TriggerEvent', {}).get('EventName') == 'Cf6PodReady'):
                        raise ValueError('A15 later waves cannot repeat the original pod budget')
        else:
            plan = stage['bossEncounter']
            if plan['maxAlive'] != 4 or plan['intervalFrames'] != 45:
                raise ValueError('A17 existing support cadence or cap changed')
            enemies = [enemy for group in plan['groups'] for enemy in group['enemies']
                       if enemy['Type'] == '兵种460' or 'podId' in enemy]
            if len(enemies) != 5: raise ValueError('A17 pod budget must remain five')
            if any('podId' in enemy for group in plan['groups'][1:] for enemy in group['enemies']):
                raise ValueError('A17 pods must stay in the original initial support group')
        seen = set()
        for enemy in enemies:
            if enemy['Type'] != '兵种460' or enemy['Level'] != (50 if identity == 'A15' else 55) or enemy['Quantity'] != 1:
                raise ValueError('clone pod must consume one existing clone of the same level')
            if identity == 'A15':
                event = enemy.get('TriggerEvent')
                if (not isinstance(event, dict) or set(event) != {'EventName','Parameters'}
                        or event['EventName'] != 'Cf6PodReady' or not isinstance(event['Parameters'], list)
                        or len(event['Parameters']) != 1):
                    raise ValueError('A15 pod event must be exact and counted')
                pod_id = event['Parameters'][0]
                parameters = enemy.get('Parameters', {})
                if parameters.get('cf6PodId') != pod_id or parameters.get('publishStageEvent') is not True:
                    raise ValueError('A15 pod needs its actual birth acknowledgement')
            else:
                pod_id = enemy.get('podId')
                if enemy['ranged'] is not False: raise ValueError('A17 clone pod cannot consume ranged quota')
            if pod_id not in actual or pod_id in seen:
                raise ValueError('clone pod budget is duplicate or unbound')
            seen.add(pod_id)
            if any(not finite(enemy.get(axis)) or abs(enemy[axis]-actual[pod_id][axis]) > 0.0001 for axis in ('x','y')):
                raise ValueError('clone pod spawn must use its exact world registration point')
        if seen != expected: raise ValueError('clone pod budget is not one per authored instance')


def validate_cf6_turrets(stage):
    """Assembled-chapter gate for the A01 tutorial turret wiring (r15).

    The mechanism.turrets spec feeds Cf6MapMechanism.beginRoom directly, so the
    identity fields are pinned exactly; world coordinates must already carry the
    single viewport transform (native x 128/75). The asset-existence gate lives
    in build-chapter.py strict mode and is not duplicated here."""
    spec = stage.get('mechanism', {}).get('turrets')
    if stage['id'] != 'A01':
        if spec is not None:
            raise ValueError('non-A01 CF6 map carries turret wiring')
        return
    if not isinstance(spec, dict) or set(spec) != {
            'assetUrl', 'linkage', 'filterMarker', 'fireIntervalFrames', 'fireFrameOffset', 'turrets'}:
        raise ValueError('A01 turret spec fields mismatch')
    if (spec['assetUrl'] != 'flashswf/backgrounds/cf6/CF6_A01_Turret.swf'
            or spec['linkage'] != 'CF6教学炮塔-A01自动炮'
            or spec['filterMarker'] != 'cf6-a01-turret-zombie'):
        raise ValueError('A01 turret identity fields mismatch')
    if spec['fireIntervalFrames'] != 18 or spec['fireFrameOffset'] != 11:
        raise ValueError('A01 turret fire cadence mismatch (original frame 12 of 18)')
    rows = spec['turrets']
    if not isinstance(rows, list) or len(rows) != 2:
        raise ValueError('A01 must carry exactly two tutorial turrets')
    for row in rows:
        if set(row) != {'x', 'y', 'facing', 'ownFootprint'} or row['facing'] != 'right':
            raise ValueError('invalid A01 turret row')
        rect = row['ownFootprint']
        if (not isinstance(rect, list) or len(rect) != 4
                or any(type(v) not in (int,float) or not math.isfinite(v) for v in rect)
                or not rect[0] < row['x'] < rect[2] or not rect[1] < row['y'] < rect[3]):
            raise ValueError('A01 turret own footprint must contain the emitter holder')
        for axis in ('x', 'y'):
            if type(row[axis]) not in (int, float) or not math.isfinite(row[axis]) \
                    or not 0 <= row[axis] <= 5000:
                raise ValueError('invalid A01 turret coordinate')


def validate_cf6_boss_prelude(stage, waves, primary_type):
    """Required standard waves carry the authored threat before the unique boss."""
    def zero(value): return type(value) in (int, float) and value == 0
    def counted(value): return value is False or zero(value)
    if not 1 <= len(waves) <= 6:
        raise ValueError('CF6 boss encounter requires one to six standard waves')
    points = stage['stage'].get('SpawnPoint', {}).get('Point', [])
    if not isinstance(points, list):
        raise ValueError('CF6 boss prelude spawn points must be an array')
    if len(waves) > 1 and any(not isinstance(point, dict) or not counted(point.get('NoCount', False)) for point in points):
        raise ValueError('CF6 boss prelude cannot use uncounted spawn points')
    reserved = {'cf6BossOwnerToken', 'cf6SupportIdentity', 'InstanceName', '产生源', '老头变身'}
    for wave in waves[:-1]:
        info = wave.get('WaveInformation', {})
        enemies = wave.get('EnemyGroup', {}).get('Enemy', [])
        if (not zero(info.get('Duration')) or not zero(info.get('FinishRequirement'))
                or not counted(info.get('MapNoCount', False))
                or not isinstance(enemies, list) or not 1 <= len(enemies) <= 32):
            raise ValueError('CF6 boss prelude must be a nonempty mandatory clear wave')
        for enemy in enemies:
            parameters = enemy.get('Parameters', {})
            if ('InstanceName' in enemy or enemy['Type'] in (primary_type, '兵种473', '兵种474')
                    or not isinstance(parameters, dict) or reserved.intersection(parameters)):
                raise ValueError('CF6 boss prelude cannot duplicate the boss or controller ownership')


def validate_cf6_boss(stage, units, items, successor=False):
    flag = stage.get('mechanism',{}).get('elderFinale')
    if 'elderFinale' in stage.get('mechanism',{}) and type(flag) is not bool:
        raise ValueError('elder finale switch must be boolean')
    if flag is True and stage['id'] != 'A20' and not successor:
        raise ValueError('elder finale switch belongs only to A20')
    plan = stage.get('bossEncounter')
    if plan is None:
        if flag is True: raise ValueError('elder finale requires its two-phase controller plan')
        return
    bosses = {'A06':463, 'A17':472, 'A20':473, 'A22':474}
    identity = stage['id']
    fields = {'instanceName','maxAlive','maxRanged','intervalFrames','groups'}
    phased = identity == 'A20' and not successor and stage.get('mechanism',{}).get('elderFinale') is True
    if phased: fields.add('nextPhase')
    if identity not in bosses or set(plan) != fields:
        raise ValueError('invalid CF6 boss map/plan')
    expected_name = 'cf6Boss_A20__elderbot' if successor else 'cf6Boss_'+identity
    if plan['instanceName'] != expected_name: raise ValueError('invalid CF6 boss instance identity')
    bounded_integer(plan['maxAlive'],1,8,'CF6 boss support cap')
    bounded_integer(plan['maxRanged'],0,plan['maxAlive'],'CF6 ranged cap')
    bounded_integer(plan['intervalFrames'],1,1800,'CF6 support interval')
    waves = stage['stage']['Wave']['SubWave']
    validate_cf6_boss_prelude(stage, waves, '兵种'+str(bosses[identity]))
    if len(waves[-1]['EnemyGroup']['Enemy']) != 1:
        raise ValueError('CF6 boss final wave contains only one boss')
    boss = waves[-1]['EnemyGroup']['Enemy'][0]
    if boss['Type'] != '兵种'+str(bosses[identity]) or boss['Quantity'] != 1 or boss.get('InstanceName') != plan['instanceName']:
        raise ValueError('CF6 boss main wave identity mismatch')
    if identity == 'A20' and boss.get('Parameters',{}).get('老头变身') is not phased:
        raise ValueError('A20 human elder transform must match its two-phase plan')
    if phased:
        next_stage = copy.deepcopy(stage)
        next_stage['id'] = 'A22'
        next_stage['bossEncounter'] = plan['nextPhase']
        next_stage['stage']['Wave']['SubWave'] = [{
            'WaveInformation':{'Duration':0, 'FinishRequirement':0},
            'EnemyGroup':{'Enemy':[{'Type':'兵种474', 'Level':boss['Level'], 'Quantity':1,
                                  'InstanceName':'cf6Boss_A20__elderbot'}]}}]
        validate_cf6_boss(next_stage, units, items, successor=True)
    if not isinstance(plan['groups'],list) or not 1 <= len(plan['groups']) <= 16:
        raise ValueError('invalid CF6 finite support groups')
    previous, total = 2, 0
    for group in plan['groups']:
        ratio = group['hpRatio']
        if set(group) != {'hpRatio','enemies'} or type(ratio) not in (int,float) or not 0 < ratio <= 1 or not ratio < previous:
            raise ValueError('CF6 support thresholds must descend')
        previous = ratio
        if not isinstance(group['enemies'],list) or not 1 <= len(group['enemies']) <= 32:
            raise ValueError('invalid CF6 support entries')
        for enemy in group['enemies']:
            if set(enemy) - {'Type','Level','Quantity','ranged','SpawnIndex','x','y','Parameters','podId'}:
                raise ValueError('CF6 support names and ownership are controller-owned')
            if 'podId' in enemy and (identity != 'A17' or enemy['Type'] != '兵种460'
                    or enemy['Quantity'] != 1 or not isinstance(enemy['podId'], str)):
                raise ValueError('unreviewed CF6 boss pod binding')
            if not re.fullmatch(r'兵种[0-9]+',enemy['Type']) or int(enemy['Type'][2:]) not in units:
                raise ValueError('unknown CF6 support type')
            bounded_integer(enemy['Level'],1,60,'CF6 support level')
            bounded_integer(enemy['Quantity'],1,128,'CF6 support quantity')
            if type(enemy['ranged']) is not bool: raise ValueError('CF6 support requires ranged boolean')
            if enemy['ranged'] and plan['maxRanged'] == 0: raise ValueError('CF6 ranged queue cannot make progress')
            spawn = enemy.get('SpawnIndex')
            points = stage['stage'].get('SpawnPoint',{}).get('Point',[])
            if spawn not in ('left','right') and not (type(spawn) is int and 0 <= spawn < len(points)):
                raise ValueError('invalid CF6 support spawn point')
            for axis in ('x','y'):
                if axis in enemy and (type(enemy[axis]) not in (int,float) or not math.isfinite(enemy[axis])):
                    raise ValueError('invalid CF6 support coordinate')
            parameters = enemy.get('Parameters',{})
            if not isinstance(parameters,dict) or any(k in parameters for k in ('cf6BossOwnerToken','cf6SupportIdentity','publishStageEvent','产生源','InstanceName')):
                raise ValueError('CF6 support ownership parameters are reserved')
            for drop in parameters.get('掉落物',[]):
                if drop['名字'] not in items: raise ValueError('unknown CF6 support drop')
            total += enemy['Quantity']
    if total > 128: raise ValueError('CF6 support finite budget exceeds 128')


def generated_cf6(data):
    return {ROOT/'data/stages/books/cf6-sting.runtime.json': (json.dumps(data,ensure_ascii=False,indent=2)+'\n').encode('utf-8')}


def load_mods():
    directory = ROOT / 'data/items/equipment_mods'
    return {mod.findtext('name'): mod
            for entry in ET.parse(directory / 'list.xml').findall('items')
            for mod in ET.parse(directory / entry.text).findall('mod')}


def validate_choices(data, items):
    """Validate complete starter sets, not merely the existence of each component."""
    mods = load_mods()
    choices = data['buildChoices']
    if not isinstance(choices, list) or [c['afterMap'] for c in choices] != [1, 3]:
        raise ValueError('build choices must follow maps two and four')
    names = [data['ammoBundle']['name']]
    for checkpoint in choices:
        names.append(checkpoint['voucher'])
        bounded_integer(checkpoint['levelCeiling'], 1, 15, 'choice level ceiling')
        if len(checkpoint['options']) != 4:
            raise ValueError('each voucher must offer four loadouts')
        uses = set()
        for option in checkpoint['options']:
            names.append(option['name'])
            weapon = items.get(option['weapon'])
            if (weapon is None or weapon.findtext('type') != '武器'
                    or option['weapon'] not in data['equipment']
                    or not 1 <= int(weapon.findtext('data/level', '999')) <= checkpoint['levelCeiling']):
                raise ValueError('choice weapon must be usable at its checkpoint')
            uses.add(weapon.findtext('use'))
            validate_loadout(option, checkpoint['levelCeiling'], items, mods)
        if '刀' not in uses or not uses & {'手枪', '长枪'}:
            raise ValueError('each checkpoint must retain melee and gun pivots')
    if len(names) != len(set(names)) or any(not n.startswith('书中') for n in names):
        raise ValueError('book delivery identities must be unique and scoped')
    supply = data['ammoBundle']['contents']
    required_ammo = {items[n].findtext('data/clipname') for n in data['equipment']
                     if n in items} - {None, ''}
    actual_ammo = set()
    for entry in supply:
        meta = items.get(entry['name'])
        if meta is None or meta.findtext('use') != '弹夹':
            raise ValueError('ammo bundle must only contain ammunition')
        bounded_integer(entry['count'], 1, 30, 'ammo bundle count')
        if entry['name'] in actual_ammo: raise ValueError('duplicate ammo bundle entry')
        actual_ammo.add(entry['name'])
    if not required_ammo <= actual_ammo:
        raise ValueError('recurring ammunition must cover all book weapons')


def generated_deliveries(data):
    """Pure data: finite vouchers -> ordinary crafting -> durable fixed reward packs."""
    root = ET.Element('root')
    root.append(ET.Comment(' Generated by tools/build-book-definition.py; edit data/stages/books/repair-campus.json. '))
    recipes = []

    def item(name, kind, use, icon, description):
        element = ET.SubElement(root, 'item')
        for key, value in [('name', name), ('displayname', name), ('icon', icon),
                           ('type', kind), ('use', use), ('price', '0'), ('description', description)]:
            ET.SubElement(element, key).text = value
        return element

    def pack(name, description, entries):
        element = item(name, '消耗品', '礼包', '材料盒子', description + ' 打开后在待领取中领取；插件需自行安装。仅供本次书中历险使用。')
        detail = ET.SubElement(element, 'data')
        ET.SubElement(detail, 'level').text = '0'
        ET.SubElement(detail, 'weight').text = '0'
        reward = ET.SubElement(detail, 'rewardPack')
        ET.SubElement(reward, 'mode').text = 'fixed'
        output = ET.SubElement(reward, 'entries')
        for name, count in entries:
            entry = ET.SubElement(output, 'entry')
            for key, value in [('itemName', name), ('quantityMin', count), ('quantityMax', count)]:
                ET.SubElement(entry, key).text = str(value)

    for checkpoint in data['buildChoices']:
        voucher = checkpoint['voucher']
        item(voucher, '收集品', '材料', '强化石', '从装备菜单进入材料，选中本凭证前往合成，在“书中配给”分类兑换一套配给包。每张凭证四选一，兑换后打开包并领取装备、插件和补给。仅供本次书中历险使用。')
        for option in checkpoint['options']:
            entries = [(entry['itemName'], entry['quantity']) for entry in loadout_entries(option)]
            pack(option['name'], option['description'], entries)
            recipes.append(dict(recipeId='craft.book-supply.%03d' % (len(recipes) + 1),
                                title=option['title'], name=option['name'], value=1,
                                price=0, kprice=0, materials=[voucher + '#1']))
    pack(data['ammoBundle']['name'], '内含' + '、'.join(entry['name'] + '×' + str(entry['count']) for entry in data['ammoBundle']['contents']) + '。',
         [(entry['name'], entry['count']) for entry in data['ammoBundle']['contents']])
    ET.indent(root, space='    ')
    xml = b'<?xml version="1.0" encoding="UTF-8"?>\n' + ET.tostring(root, encoding='utf-8') + b'\n'
    return {PACK_OUTPUT: xml, RECIPE_OUTPUT: (json.dumps(recipes, ensure_ascii=False, indent=2) + '\n').encode('utf-8')}


def validate_boss(data, units, items):
    c = data['bossEncounter']
    if set(c) != {'mapIndex','instanceName','intervalFrames','maxAlive','maxRanged','groups','rangedTypes','supplies'}:
        raise ValueError('invalid boss encounter fields')
    if c['mapIndex'] != len(data['maps']) - 1 or c['instanceName'] != 'bookCampusTeacher':
        raise ValueError('boss must own final map')
    final_map = data['maps'][c['mapIndex']]
    if final_map['waves'] != 1 or final_map['count'] != [1,1] or len(final_map['enemies']) != 1:
        raise ValueError('boss encounter requires one unambiguous boss actor')
    bounded_integer(c['intervalFrames'], 60, 300, 'reinforcement interval')
    bounded_integer(c['maxAlive'], 1, 3, 'reinforcement live cap')
    bounded_integer(c['maxRanged'], 1, c['maxAlive'], 'ranged live cap')
    if len(c['groups']) != 3 or len(c['supplies']) != 4: raise ValueError('finite three-phase boss required')
    seen, previous, count = set(), 1, 0
    for group in c['groups']:
        if set(group) != {'hpRatio','level','pools'}: raise ValueError('invalid reinforcement group')
        ratio = group['hpRatio']
        if type(ratio) not in (float,int) or not 0 < ratio < previous: raise ValueError('descending HP phases required')
        previous = ratio
        bounded_integer(group['level'], 1, 15, 'reinforcement level')
        if not 1 <= len(group['pools']) <= 4: raise ValueError('oversized group')
        for pool in group['pools']:
            if not isinstance(pool,list) or not 1 <= len(pool) <= 4: raise ValueError('invalid enemy pool')
            for enemy in pool:
                if type(enemy) is not int or enemy not in units or enemy in seen: raise ValueError('duplicate or unknown reinforcement')
                seen.add(enemy)
            count += 1
    if count > 8 or set(c['rangedTypes']) - seen: raise ValueError('invalid reinforcement budget')
    for supply in c['supplies']:
        if set(supply) != {'name','count'} or supply['name'] not in items: raise ValueError('invalid reinforcement supply')
        bounded_integer(supply['count'], 1, 3, 'reinforcement supply count')
        if supply['name'] != data['ammoBundle']['name'] and items[supply['name']].findtext('use') not in ('药剂','手雷','战场补给'):
            raise ValueError('reinforcements only grant tactical supplies')


def bounded_integer(value, low, high, label):
    if type(value) is not int or not low <= value <= high:
        raise ValueError('invalid ' + label)


def validate_skills(data, skills):
    bounded_integer(data['skillMaxUnlockLevel'], 1, 15, 'book skill level ceiling')
    eligible = {s.findtext('Name') for s in skills if s.findtext('Name')
                and s.findtext('Type') and int(s.findtext('MaxLevel', '0')) > 0
                and 1 <= int(s.findtext('UnlockLevel', '999')) <= data['skillMaxUnlockLevel']}
    selected = data['skills']
    if (not isinstance(selected, list) or not selected
            or any(type(name) is not str for name in selected)
            or len(selected) != len(set(selected)) or not set(selected) <= eligible):
        raise ValueError('book skills must be a nonempty unique selection of learnable skills within the level ceiling')


def validate_medicine(name, items, stat):
    if name not in items or items[name].findtext('use') != '药剂':
        raise ValueError('map medicine must be a storable potion')
    if not any(e.get('type') == 'heal' and e.get('target') == 'self'
               and float(e.get(stat, '0').rstrip('%')) > 0
               for e in items[name].findall('data/effects/effect')):
        raise ValueError('map medicine must restore ' + stat)


def validate_loot(data, items):
    bounded_integer(data['startingMoney'], 0, 100000, 'starting money')
    bounded_integer(data['startingSkillPoints'], 0, 200, 'starting skill points')
    loot = data['loot']
    for key in ('equipmentChance', 'supplyChance'):
        bounded_integer(loot[key], 0, 100, key)
    # Enemy drops look up the canonical item name before creating a pickup.
    # Display aliases such as 金钱 / 经验 silently disappear in that consumer.
    if (loot['moneyItem'] != '金币' or loot['experienceItem'] != '经验值'
            or loot['skillPointItem'] != '技能点'):
        raise ValueError('currency drops require canonical item names')
    for key in ('moneyItem', 'experienceItem', 'skillPointItem', 'medicalItem'):
        if loot[key] not in items:
            raise ValueError('unknown loot item ' + loot[key])
    medical = items[loot['medicalItem']]
    if medical.findtext('use') != '战场补给' or not any(
            e.get('type') == 'heal' and e.get('target') == 'self'
            and e.get('hp', '').endswith('%') and float(e.get('hp')[:-1]) > 0
            for e in medical.findall('data/effects/effect')):
        raise ValueError('medical pickup must restore a proportion of health')
    bounded_integer(loot['healingCount'], 1, 20, 'healing count')
    bounded_integer(loot['armorWaves'], 1, 2, 'armor waves')
    support = loot['support']
    if not isinstance(support, list) or not 1 <= len(support) <= 8:
        raise ValueError('invalid support cycle')
    for entry in support:
        bundle = entry['kind'] == 'ammo' and entry['name'] == data['ammoBundle']['name'] and entry['count'] == 1
        if entry['name'] not in items or (not bundle and items[entry['name']].findtext('use') not in ('药剂', '弹夹', '手雷')):
            raise ValueError('support must be an existing potion, ammunition or grenade')
        bounded_integer(entry['count'], 1, 20, 'support count')
        if entry['kind'] not in ('mana', 'ammo', 'grenade'):
            raise ValueError('invalid support kind')
    if sum(entry['kind'] == 'mana' for entry in support) != 1:
        raise ValueError('support cycle needs exactly one mana entry')
    mod_dir = ROOT / 'data/items/equipment_mods'
    mods = {mod.findtext('name'): mod
            for entry in ET.parse(mod_dir / 'list.xml').findall('items')
            for mod in ET.parse(mod_dir / entry.text).findall('mod')}
    tier_system = ET.parse(ROOT / 'data/equipment/equipment_config.xml').find('EquipmentConfig/TierSystem')
    tiers = {entry.get('material'): entry for entry in tier_system.findall('TierMapping')}
    available_equipment = set()
    for stage in data['maps']:
        pool = stage['equipment']
        if not isinstance(pool, list) or not pool or any(name not in data['equipment'] for name in pool):
            raise ValueError('invalid map equipment pool')
        armor = stage['armor']
        if (not isinstance(armor, list) or len(armor) < loot['armorWaves']
                or len(armor) != len(set(armor)) or any(
                    name not in data['equipment'] or name not in items
                    or items[name].findtext('type') != '防具'
                    or not 1 <= int(items[name].findtext('data/level', '999')) <= 15 for name in armor)):
            raise ValueError('map armor pool must contain distinct registered armor')
        if set(armor) & set(pool):
            raise ValueError('armor and weapon choices need independent drop slots')
        validate_medicine(stage['healingItem'], items, 'hp')
        validate_medicine(stage['manaItem'], items, 'mp')
        bounded_integer(stage['waves'], 1, 10, 'wave count')
        bounded_integer(stage['skillPoints'], 0, 100, 'map skill point budget')
        available_equipment.update(pool + armor)
        materials = stage['materials']
        if not isinstance(materials, list) or len(materials) > stage['waves']:
            raise ValueError('materials allow at most one stack per wave')
        for entry in materials:
            name = entry['name']
            if name not in items or items[name].findtext('use') != '材料':
                raise ValueError('growth pickup must be a registered material')
            bounded_integer(entry['count'], 1, 100, 'material stack count')
            if name in mods:
                uses = set(mods[name].findtext('use', '').split(','))
                if not any(items[n].findtext('use') in uses for n in available_equipment):
                    raise ValueError('mod has no matching equipment in reached map pools')
            elif name in tiers:
                tier = tiers[name]
                default = tier_system.find("DefaultTierData/Tier[@name='" + tier.get('name') + "']")
                eligible = False
                for n in available_equipment:
                    item = items[n]
                    target = item.find(tier.get('key'))
                    if target is None and item.findtext('type') == '防具' and item.findtext('use') != '颈部装备' and int(item.findtext('data/level', '999')) < 10:
                        target = default
                    if target is not None and 1 <= int(target.findtext('level', '999')) <= data['skillMaxUnlockLevel']:
                        eligible = True
                if not eligible:
                    raise ValueError('tier material has no usable upgrade within book level ceiling')
            elif name != '强化石':
                raise ValueError('growth material must support equipment tuning')
        bounded_integer(stage['experience'], 1, 1000000, 'map experience budget')
        money = stage['money']
        if not isinstance(money, list) or len(money) != 2:
            raise ValueError('invalid money range')
        bounded_integer(money[0], 1, 100000, 'minimum money')
        bounded_integer(money[1], money[0], 100000, 'maximum money')


def main():
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    data = resolve_book_choices(json.loads(SOURCE.read_text(encoding='utf-8')))
    if data['schema'] != 'playable-book.v1' or data['id'] != 'repair-campus':
        raise ValueError('unsupported book identity')
    if any(type(data[k]) is not int or not 0 <= data[k] <= 100 for k in ('regularSp', 'firstClearSp', 'recordSpPerTier')):
        raise ValueError('invalid SP configuration')
    if data['recordMinutes'] != sorted(set(data['recordMinutes']), reverse=True) or not all(type(v) is int and 1 <= v <= 60 for v in data['recordMinutes']):
        raise ValueError('record tiers must be finite descending minutes')
    validate_skills(data, ET.parse(ROOT / 'data/skills/skills.xml').findall('Skill'))
    units = {u['id'] for u in json.loads((ROOT / 'data/units/units.json').read_text(encoding='utf-8-sig'))}
    items = {}
    for path in (ROOT / 'data/items').glob('*.xml'):
        if path == PACK_OUTPUT: continue
        items.update((item.findtext('name'), item) for item in ET.parse(path).findall('.//item'))
    validate_choices(data, items)
    if [c['afterMap'] for c in data['minorChoices']] != [0, 2, 4, 5]: raise ValueError('four minor deliveries must complement the two loadout checkpoints')
    if data['kBudget'] != {'mapCount': 6, 'guaranteed': 200, 'randomMax': 100}: raise ValueError('invalid run K budget')
    if data['optionalLoot'] != {'firstMap': 2, 'lastMap': 5, 'percent': 75}: raise ValueError('invalid optional loot transfer')
    bounded_integer(data['recordSp'], 0, 100, 'personal best SP')
    outputs = generated_deliveries(data)
    items.update((item.findtext('name'), item) for item in ET.fromstring(outputs[PACK_OUTPUT]).findall('item'))
    if not 6 <= len(data['maps']) <= 8:
        raise ValueError('book requires 6-8 maps')
    for stage in data['maps']:
        if not isinstance(stage.get('dialogue'), list) or len(stage['dialogue']) > 32:
            raise ValueError('dialogue must contain at most 32 lines')
        for line in stage['dialogue']:
            if (set(line) != {'speaker', 'text'} or not isinstance(line['speaker'], str) or len(line['speaker']) > 40
                    or not isinstance(line['text'], str) or not 1 <= len(line['text']) <= 160):
                raise ValueError('invalid dialogue speaker/text')
        if not (ROOT / 'flashswf/backgrounds' / stage['background']).is_file():
            raise ValueError('missing background ' + stage['background'])
        if any(enemy not in units for enemy in stage['enemies']):
            raise ValueError('unknown enemy')
        if not 1 <= stage['level'][0] <= stage['level'][1] <= 60:
            raise ValueError('invalid levels')
        if not 1 <= stage['count'][0] <= stage['count'][1] <= 8:
            raise ValueError('invalid spawn count')
    missing = set(data['equipment'] + data['supplies']) - items.keys()
    if missing:
        raise ValueError('unknown items: ' + ', '.join(sorted(missing)))
    validate_loot(data, items)
    validate_boss(data, units, items)
    literal = json.dumps(data, ensure_ascii=False, indent=4)
    # AS2 object literals require identifier keys, unlike JSON / JavaScript.
    literal = re.sub(r'"([A-Za-z_][A-Za-z0-9_]*)"(?=\s*:)', r'\1', literal)
    text = '// Generated by tools/build-book-definition.py from data/stages/books/repair-campus.json.\n'
    runtime = (ROOT / 'tools/book-definition-runtime.as.inc').read_text(encoding='utf-8')
    text += 'class org.flashNight.arki.scene.BookDefinition {\n' + runtime + '\n    private static function fallback():Object {\n        return ' + literal + ';\n    }\n}\n'
    outputs[ROOT / 'data/stages/books/repair-campus.runtime.json'] = (json.dumps(data, ensure_ascii=False, indent=2) + '\n').encode('utf-8')
    content = b'\xef\xbb\xbf' + text.replace('\n', '\r\n').encode('utf-8')
    outputs[OUTPUT] = content
    if CF6_SOURCE.is_file():
        cf6 = json.loads(CF6_SOURCE.read_text(encoding='utf-8-sig'))
        validate_cf6(cf6, items, ET.parse(ROOT/'data/skills/skills.xml').findall('Skill'), units)
        outputs.update(generated_cf6(cf6))
    for path, content in outputs.items():
        if args.check:
            if not path.is_file() or path.read_bytes() != content:
                raise ValueError(str(path.relative_to(ROOT)) + ' is stale')
        else:
            if path == OUTPUT and not path.exists():
                shutil.copyfile(ROOT / 'scripts/类定义/org/flashNight/arki/scene/StageReturnFlow.as', OUTPUT)
            path.write_bytes(content)
    print('book definition: campus verified; CF6 ' + ('authored chapter verified' if CF6_SOURCE.is_file() else 'not installed'))


if __name__ == '__main__':
    main()
