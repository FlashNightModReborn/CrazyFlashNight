"""Assemble the historical chapter from reviewed content and native map outputs.

The source fragments retain original CF6 coordinates. This boundary transforms
actor placements exactly once; the map runtime's spawn/layers are already in
CF7 world coordinates. The sky-parallax fragment contributes root-stage layers,
merged without any further conversion. Missing maps or SWFs fail before shared
files are written.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
TOOLS = ROOT / "tools"
HERE = Path(__file__).resolve().parent
ROUTE = [f"A{i:02}" for i in range(1, 23) if i not in (7, 21)]
SOURCE = ROOT / "data/stages/books/cf6-sting-source"
OUTPUT = ROOT / "data/stages/books/cf6-sting.json"
ENVIRONMENT = ROOT / "data/environment/stage_environment.xml"
BEGIN = "    <!-- BEGIN GENERATED CF6 HISTORICAL MAPS -->"
END = "    <!-- END GENERATED CF6 HISTORICAL MAPS -->"
SHOP_LIST = ROOT / "data/shops/list.xml"
SHOP_BEGIN = "  <!-- BEGIN GENERATED CF6 HISTORICAL SHOPS -->"
SHOP_END = "  <!-- END GENERATED CF6 HISTORICAL SHOPS -->"
SKY_PARALLAX = TOOLS / 'cf6-map-runtime/sky-parallax.fragment.json'
SKY_SCHEMA = 'cf6-sky-parallax-fragment.v1'
SKY_MAPS = ('A02', 'A06')
SKY_ROLES = ('screen-fixed', 'city-parallax')
TURRET_FRAGMENT = TOOLS / 'cf6-tutorial-turrets/tutorial-turrets.fragment.json'
TURRET_MAP = 'A01'


def read(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def encoded(value):
    return (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode("utf-8")


def transform_placement(value, origin, scale):
    """Only placement fields belong to world space; Parameters are untouched."""
    for axis, keys in enumerate((('x', 'Xmin', 'Xmax', 'x0', 'x1'),
                                 ('y', 'Ymin', 'Ymax', 'y0', 'y1'))):
        for key in keys:
            if key not in value:
                continue
            n = value[key]
            if type(n) not in (int, float):
                raise ValueError("non-numeric authored placement " + key)
            value[key] = round((n - origin[axis]) * scale, 4)


def convert_map(authored, runtime, native):
    result = copy.deepcopy(authored)
    origin = native['nativeBounds'][:2]
    scale = native['worldScale']
    if scale != 1:
        raise ValueError("CF6 body/geometry scale must be explicitly reviewed")
    stage = result['stage']
    for outer, inner in (('Instances', 'Instance'), ('Pickups', 'Pickup'),
                         ('SpawnPoint', 'Point')):
        for placement in stage.get(outer, {}).get(inner, []):
            transform_placement(placement, origin, scale)
    for wave in stage['Wave']['SubWave']:
        for enemy in wave['EnemyGroup']['Enemy']:
            transform_placement(enemy, origin, scale)
            if result['id'] in ('A03', 'A04'):
                enemy.setdefault('Parameters', {})['publishStageEvent'] = True
    for group in result.get('bossEncounter', {}).get('groups', []):
        for enemy in group['enemies']:
            transform_placement(enemy, origin, scale)
    result['background'] = runtime['background']
    result['mechanism'] = copy.deepcopy(runtime['mechanism'])
    basic = stage.setdefault('BasicInformation', {})
    basic.update(Background='flashswf/backgrounds/' + runtime['background'],
                 PlayerX=runtime['spawn'][0], PlayerY=runtime['spawn'][1],
                 EndFrame='房间')
    basic.setdefault('BGM', {'Command': 'play', 'Title': 'Bulletproof', 'Loop': True})
    result['geometryBasis'] = copy.deepcopy(runtime['geometryBasis'])
    result['sourceCoordinateSpace'] = 'native-original converted once to CF7 world'
    return result


def validate_sky_layer(map_id, layer):
    if not isinstance(layer, dict) or set(layer) != {
            'id', 'role', 'coordinateSpace', 'url', 'x', 'y', 'width', 'height', 'depth'}:
        raise ValueError('invalid sky-parallax layer fields for ' + map_id)
    if type(layer['id']) is not str or not layer['id']:
        raise ValueError('invalid sky-parallax layer id for ' + map_id)
    if layer['role'] not in SKY_ROLES:
        raise ValueError('invalid sky-parallax layer role for ' + map_id)
    if layer['coordinateSpace'] != 'root-stage':
        raise ValueError('sky-parallax layer must keep root-stage coordinate space')
    url = layer['url']
    if type(url) is not str or not re.fullmatch(
            r'flashswf/backgrounds/cf6/CF6_' + map_id + r'_[A-Za-z0-9][A-Za-z0-9-]*\.swf', url):
        raise ValueError('unsafe sky-parallax layer url for ' + map_id)
    for key in ('x', 'y'):
        if type(layer[key]) not in (int, float) or not math.isfinite(layer[key]):
            raise ValueError('non-finite sky-parallax placement for ' + map_id)
    for key in ('width', 'height'):
        if (type(layer[key]) not in (int, float) or not math.isfinite(layer[key])
                or layer[key] <= 0):
            raise ValueError('sky-parallax layer size must be finite and positive for ' + map_id)
    if type(layer['depth']) is not int or not 0 <= layer['depth'] <= 999:
        raise ValueError('invalid sky-parallax layer depth for ' + map_id)


def validate_sky_fragment(fragment):
    """The fragment is the only source of these layer fields; validate it strictly."""
    if not isinstance(fragment, dict) or fragment.get('schema') != SKY_SCHEMA:
        raise ValueError('unexpected sky-parallax fragment schema')
    if fragment.get('coordinateSpace') != 'root-stage':
        raise ValueError('sky-parallax layers must stay in root-stage coordinates')
    maps = fragment.get('maps')
    if not isinstance(maps, dict) or not maps or set(maps) - set(SKY_MAPS):
        raise ValueError('sky-parallax fragment covers unknown maps')
    for map_id, entry in maps.items():
        if not isinstance(entry, dict) or set(entry) != {'replaceLayerIds', 'layers'}:
            raise ValueError('invalid sky-parallax entry for ' + map_id)
        replaced = entry['replaceLayerIds']
        if (not isinstance(replaced, list)
                or not all(type(i) is str and i for i in replaced)
                or len(set(replaced)) != len(replaced)):
            raise ValueError('invalid sky-parallax replaceLayerIds for ' + map_id)
        layers = entry['layers']
        if not isinstance(layers, list) or not 1 <= len(layers) <= 8:
            raise ValueError('invalid sky-parallax layer list for ' + map_id)
        ids, roles = set(), set()
        for layer in layers:
            validate_sky_layer(map_id, layer)
            if layer['id'] in ids or layer['role'] in roles:
                raise ValueError('duplicate sky-parallax layer id/role for ' + map_id)
            ids.add(layer['id'])
            roles.add(layer['role'])
    return fragment


def load_sky_parallax(path):
    return validate_sky_fragment(read(path))


def apply_sky_parallax(chapter, fragment, require_swfs):
    """Remove replaceLayerIds matches, then append declared layers in order.

    These layers are root-stage coordinates: no map-origin subtraction and no
    world scale is ever applied to them, here or downstream. Other layers, the
    base background URL, spawn and all content coordinates stay untouched.
    """
    maps = {m['id']: m for m in chapter['maps']}
    audit = {}
    for map_id, entry in fragment['maps'].items():
        stage = maps.get(map_id)
        if stage is None:
            raise ValueError('sky-parallax map missing from assembled chapter: ' + map_id)
        mechanism = stage['mechanism']
        kept = [l for l in mechanism.get('layers', [])
                if l.get('id') not in entry['replaceLayerIds']]
        merged = kept + [copy.deepcopy(l) for l in entry['layers']]
        ids = [l.get('id') for l in merged]
        if len(set(ids)) != len(ids):
            raise ValueError('duplicate mechanism layer id after sky-parallax merge on ' + map_id)
        for role in SKY_ROLES:
            if sum(1 for l in merged if l.get('role') == role) > 1:
                raise ValueError('duplicate ' + role + ' layer after merge on ' + map_id)
        if require_swfs:
            for layer in entry['layers']:
                if not (ROOT / layer['url']).is_file():
                    raise ValueError('missing sky-parallax layer SWF ' + layer['url'])
        mechanism['layers'] = merged
        audit[map_id] = {'replaced': list(entry['replaceLayerIds']),
                         'layers': [l['id'] for l in entry['layers']]}
    return audit


def apply_turrets(chapter, fragment, require_swfs):
    """A01 tutorial turrets: native-original points scaled by the SAME viewport
    factor exactly once (net native x 128/75, identical to enemy placements),
    then moved into mechanism.turrets for Cf6MapMechanism.beginRoom.
    Turret body, actors and the base camera stay at scale 1. Instance names only
    enter the audit: the runtime spec omits them so the service stays in
    load mode and names its own holders."""
    symbol = fragment['turretSymbol']
    asset = symbol['assetSwf']
    audit = {}
    for node in chapter['maps']:
        block = node.pop('turrets', None)
        if block is None:
            continue
        if node['id'] != TURRET_MAP:
            raise ValueError('turret config on non-A01 map: ' + node['id'])
        presentation = node.get('presentation')
        if presentation is None:
            raise ValueError('turret transform must run after viewport assembly')
        scale = presentation['scale']
        if block.get('coordinateSpace') != 'native-original':
            raise ValueError('turret coordinates must be native-original; refusing a second transform')
        if block.get('source') != 'tools/cf6-tutorial-turrets/tutorial-turrets.fragment.json':
            raise ValueError('turret block provenance mismatch')
        for key in ('assetUrl', 'linkage', 'filterMarker'):
            if type(block.get(key)) is not str or not block[key] or '..' in block[key]:
                raise ValueError('unsafe turret ' + key)
        if not block['assetUrl'].endswith('.swf'):
            raise ValueError('turret assetUrl must be a swf')
        if (block['assetUrl'] != asset['assetUrl'] or block['linkage'] != asset['linkage']
                or block['fireIntervalFrames'] != symbol['fireCycleFrames']
                or block['fireFrameOffset'] != symbol['fireFrame'] - 1):
            raise ValueError('turret block disagrees with tutorial-turrets fragment')
        if (type(block['fireIntervalFrames']) is not int or not 2 <= block['fireIntervalFrames'] <= 120
                or type(block['fireFrameOffset']) is not int
                or not 0 <= block['fireFrameOffset'] < block['fireIntervalFrames']):
            raise ValueError('invalid turret fire cadence')
        instances = block.get('instances')
        source_instances = {i['id']: i for i in fragment['instances']}
        if (not isinstance(instances, list) or not 1 <= len(instances) <= 8
                or [i.get('name') for i in instances] != [i['id'] for i in fragment['instances']]):
            raise ValueError('turret instances diverge from tutorial-turrets fragment')
        rows = []
        for inst in instances:
            if (set(inst) != {'name', 'x', 'y', 'facing'} or inst['facing'] != 'right'
                    or any(type(inst[a]) not in (int, float) or not math.isfinite(inst[a])
                           or abs(inst[a]) > 5000 for a in ('x', 'y'))):
                raise ValueError('invalid turret instance: ' + repr(inst))
            native_src = source_instances[inst['name']]
            if [inst['x'], inst['y']] != [native_src['x'], native_src['y']]:
                raise ValueError('turret native coordinate drift: ' + inst['name'])
            rows.append({'x': round(inst['x'] * scale, 4), 'y': round(inst['y'] * scale, 4),
                         'facing': inst['facing']})
        if require_swfs and not (ROOT / block['assetUrl']).is_file():
            raise ValueError('missing turret asset SWF ' + block['assetUrl']
                             + ' (run the tools/cf6-tutorial-turrets CS6 chain first)')
        node['mechanism']['turrets'] = {
            'assetUrl': block['assetUrl'], 'linkage': block['linkage'],
            'filterMarker': block['filterMarker'],
            'fireIntervalFrames': block['fireIntervalFrames'],
            'fireFrameOffset': block['fireFrameOffset'],
            'turrets': rows}
        audit[node['id']] = {'scale': scale, 'assetUrl': block['assetUrl'],
                             'filterMarker': block['filterMarker'],
                             'instances': [{'name': i['name'], 'native': [i['x'], i['y']],
                                            'world': [r['x'], r['y']]}
                                           for i, r in zip(instances, rows)],
                             'assetPresent': (ROOT / block['assetUrl']).is_file()}
    return audit


def inside(point, polygon):
    x, y = point
    odd = False
    for a, b in zip(polygon, polygon[1:] + polygon[:1]):
        if (a[1] > y) != (b[1] > y):
            edge_x = a[0] + (y-a[1]) * (b[0]-a[0]) / (b[1]-a[1])
            if x < edge_x:
                odd = not odd
    return odd


def merchant_anchor(stage, environment):
    """Choose a nearby free point, including a clear foot area and approach."""
    basic = stage['stage']['BasicInformation']
    spawn = (basic['PlayerX'], basic['PlayerY'])
    bounds = [float(environment.findtext(k)) for k in ('Xmin','Ymin','Xmax','Ymax')]
    polygons = [[tuple(float(v) for v in p.text.split(',')) for p in c.findall('Point')]
                for c in environment.findall('Collision')]

    def free(point, margin):
        for dx in (-margin, 0, margin):
            for dy in (-margin/2, 0, margin/2):
                p = (point[0]+dx, point[1]+dy)
                if not bounds[0] < p[0] < bounds[2] or not bounds[1] < p[1] < bounds[3]:
                    return False
                if any(inside(p, poly) for poly in polygons):
                    return False
        return True

    for dx, dy in ((80,0),(-80,0),(0,45),(0,-45),(60,30),(-60,30),(60,-30),(-60,-30)):
        point = (spawn[0]+dx, spawn[1]+dy)
        if free(point, 18) and all(free((spawn[0]+dx*t/12, spawn[1]+dy*t/12), 8)
                                   for t in range(13)):
            return [round(v, 4) for v in point]
    raise ValueError('no free nearby merchant anchor for ' + stage['id'])


def shop_manifest_bytes(existing, shops):
    bom = existing.startswith(b'\xef\xbb\xbf')
    text = existing.decode('utf-8-sig')
    newline = '\r\n' if '\r\n' in text else '\n'
    if text.count(SHOP_BEGIN) != text.count(SHOP_END) or text.count(SHOP_BEGIN) > 1:
        raise ValueError('ambiguous generated shop block')
    paths = ['npcs/' + shop['shopId'] + '.json' for shop in shops]
    if SHOP_BEGIN in text:
        a = text.index(SHOP_BEGIN)
        b = text.index(SHOP_END, a) + len(SHOP_END)
        retained = text[:a] + text[b:]
    else:
        retained = text
    if set(paths).intersection(node.text for node in ET.fromstring(retained).findall('shops')):
        raise ValueError('CF6 shop already exists outside the generated block')
    block = SHOP_BEGIN + newline + newline.join('  <shops>' + p + '</shops>' for p in paths) + newline + SHOP_END
    result = text[:a] + block + text[b:] if SHOP_BEGIN in text else text.replace('</root>', block + newline + '</root>')
    ET.fromstring(result)
    return (b'\xef\xbb\xbf' if bom else b'') + result.encode('utf-8')


def install_economy(chapter, economy, budget, shop_source, items, skills, environments):
    if budget['bookId'] != chapter['id'] or budget['routeId'] != chapter['routeId']:
        raise ValueError('budget identity mismatch')
    if budget['startingMoney'] != chapter['startingMoney']:
        raise ValueError('budget and content initial money disagree')
    chapter['economy'] = copy.deepcopy(economy['chapterEconomy'])
    maps = {m['id']: m for m in chapter['maps']}
    gold = budget['goldPlans'][budget['goldPlanForAssembly']]
    if [row['mapId'] for row in gold] != ROUTE:
        raise ValueError('gold plan must match the complete route')
    if any(type(row['value']) is not int or not 0 <= row['value'] <= 180050 for row in gold):
        raise ValueError('gold pickup exceeds the reviewed native count range')
    if sum(row['value'] for row in gold) != budget['goldPickupContract']['nominalTotal']:
        raise ValueError('nominal gold budget mismatch')
    removed = []
    for row in chapter['economy']['randomWeapons']:
        stage = maps[row['mapId']]['stage']
        names = {entry[key] for entry in row['choices'] for key in ('weapon','ammo')}
        fixed = stage.setdefault('Pickups', {}).setdefault('Pickup', [])
        removed.extend({'mapId': row['mapId'], 'pickup': p} for p in fixed if p['Name'] in names)
        stage['Pickups']['Pickup'] = [p for p in fixed if p['Name'] not in names]
    for row in gold:
        stage = maps[row['mapId']]['stage']
        if any(p['Name'] == '金币' for p in stage.get('Pickups', {}).get('Pickup', [])):
            raise ValueError('duplicate authored map-entry gold')
        if row['value']:
            basic = stage['BasicInformation']
            stage.setdefault('Pickups', {}).setdefault('Pickup', []).append({
                'Name': '金币', 'Value': row['value'], 'x': basic['PlayerX'], 'y': basic['PlayerY']})

    skill_catalog = {s.findtext('Name'):s for s in skills}
    maxed = {s['name'] for s in chapter['actor']['skills']}
    candidates = list(dict.fromkeys(s for placement in shop_source['placement'] for s in placement['skills']))
    for name in candidates:
        meta = skill_catalog.get(name)
        if meta is None or name in maxed or name == '驾驶' or not meta.findtext('Type'):
            raise ValueError('invalid historical merchant skill ' + name)
    from choice_reward_catalog import load as choice_catalog
    choices = choice_catalog()
    pools = {p['id']: p for p in choices['pools']}
    bundles = {b['id']: b for b in choices['bundles']}
    position = {name:i for i,name in enumerate(maps)}
    free_guns = []
    for entry in chapter['actor']['equipment']:
        if items[entry['name']].findtext('use') in ('长枪','手枪'):
            free_guns.append((-1, entry['name']))
    for section in ('randomWeapons','eliteWeapons'):
        for row in chapter['economy'][section]:
            free_guns.extend((position[row['mapId']], e['weapon']) for e in row['choices'])
    for m in chapter['maps']:
        for p in m['stage'].get('Pickups', {}).get('Pickup', []):
            meta = items.get(p['Name'])
            if meta is not None and meta.findtext('use') in ('长枪','手枪'):
                free_guns.append((position[m['id']], p['Name']))
    for row in chapter['economy']['choices']:
        for group in pools[row['poolId']]['groups']:
            for entry in group['entries']:
                bundle = bundles[entry['bundleId']]
                names = ([bundle['weapon']] if 'weapon' in bundle else []) + [e['itemName'] for e in bundle.get('items', [])]
                free_guns.extend((position[row['mapId']], name) for name in names
                                 if items[name].findtext('use') in ('长枪','手枪'))
    goods = list(budget['commonShopItems'])
    shops, placement_audit = [], []
    for node in budget['merchantNodes']:
        cap = node['maxItemLevel']
        for name in node['addWeapons']:
            meta = items.get(name)
            if meta is None or meta.findtext('use') not in ('长枪','手枪') or not 1 <= int(meta.findtext('data/level','999')) <= cap:
                raise ValueError('merchant weapon exceeds chapter tier: ' + name)
            if name not in goods:
                goods.append(name)
        gun_names = goods + [name for at,name in free_guns if at <= position[node['mapId']]]
        for name in list(gun_names):
            meta = items.get(name)
            if meta is None:
                raise ValueError('unknown merchant item ' + name)
            if meta.findtext('use') in ('长枪','手枪'):
                ammo = meta.findtext('data/clipname')
                if not ammo or ammo not in items or items[ammo].findtext('use') != '弹夹':
                    raise ValueError('missing exact ammunition for ' + name)
                if ammo not in goods:
                    goods.append(ammo)
        shop = dict(schema='npc-shop.v2', shopId=node['shopId'], title=node['title'],
                    catalog={str(i): name for i,name in enumerate(goods)})
        shops.append(shop)
        map_data = maps[node['mapId']]
        anchor = merchant_anchor(map_data, environments['CF6_' + node['mapId'] + '_BG.swf'])
        learnable = [name for name in candidates if int(skill_catalog[name].findtext('UnlockLevel','999')) <= cap]
        parameters = {'商店检索名':node['shopId'], '技能检索名':node['shopId'],
                      '可学的技能':{str(i):name for i,name in enumerate(learnable)},
                      '任务名':node['shopId'], '默认对话':[]}
        map_data['stage'].setdefault('Instances', {}).setdefault('Instance', []).append({
            'Identifier':'生存战-迷之盔甲君', 'x':anchor[0], 'y':anchor[1],
            'InitializeParametersBeforeAttach':True, 'Parameters':parameters})
        placement_audit.append({'mapId':node['mapId'], 'shopId':node['shopId'], 'anchor':anchor,
                                'maxItemLevel':cap, 'goods':len(goods), 'skills':learnable})
    return shops, {'goldPlan':budget['goldPlanForAssembly'], 'nominalGold':sum(r['value'] for r in gold),
                   'actualGoldReceipt':'requires real pickup observation', 'merchants':placement_audit,
                   'fixedPickupsReplacedBySeededSources':removed}


def merge_environment_fragments(map_fragment, tutorial_fragment):
    maps = ET.fromstring(map_fragment)
    tutorial = ET.fromstring(tutorial_fragment)
    if maps.tag != 'EnvironmentSettings' or tutorial.tag != 'EnvironmentSettings':
        raise ValueError('unexpected environment fragment root')
    if [node.findtext('BackgroundURL') for node in maps.findall('Environment')] != ['CF6_' + name + '_BG.swf' for name in ROUTE]:
        raise ValueError('map environment fragment must contain the exact complete route')
    if [node.findtext('BackgroundURL') for node in tutorial.findall('Environment')] != ['CF6_Tutorial_BG.swf']:
        raise ValueError('tutorial environment must contain only its independent background')
    if len(maps) != len(ROUTE) or len(tutorial) != 1:
        raise ValueError('unexpected environment fragment members')
    merged = ET.Element('EnvironmentSettings')
    for node in list(tutorial) + list(maps):
        merged.append(copy.deepcopy(node))
    return ET.tostring(merged, encoding='utf-8', xml_declaration=True)


def environment_bytes(existing, fragment):
    """Replace only the owned generated block, retaining unrelated XML bytes."""
    bom = existing.startswith(b'\xef\xbb\xbf')
    text = existing.decode('utf-8-sig')
    newline = '\r\n' if '\r\n' in text else '\n'
    generated = ET.fromstring(fragment)
    names = [node.findtext('BackgroundURL') for node in generated.findall('Environment')]
    if names != ['CF6_Tutorial_BG.swf'] + ['CF6_' + name + '_BG.swf' for name in ROUTE]:
        raise ValueError('environment fragment must contain the exact complete route')
    if text.count(BEGIN) != text.count(END) or text.count(BEGIN) > 1:
        raise ValueError('ambiguous generated environment block')
    if BEGIN in text:
        a = text.index(BEGIN)
        b = text.index(END, a) + len(END)
        retained = text[:a] + text[b:]
    else:
        retained = text
    outside_names = [node.findtext('BackgroundURL')
                     for node in ET.fromstring(retained).findall('Environment')]
    if set(names).intersection(outside_names):
        raise ValueError('CF6 environment already exists outside the owned block')
    nodes = []
    for node in generated.findall('Environment'):
        node.tail = None
        nodes.append('    ' + ET.tostring(node, encoding='unicode').replace('\n', newline))
    block = BEGIN + newline + newline.join(nodes) + newline + END
    if BEGIN in text:
        result = text[:a] + block + text[b:]
    else:
        result = text.replace('</EnvironmentSettings>', block + newline + '</EnvironmentSettings>')
    ET.fromstring(result)
    return (b'\xef\xbb\xbf' if bom else b'') + result.encode('utf-8')


def build(require_swfs=True):
    inputs = [SOURCE / 'maps.fragment.json', SOURCE / 'economy.fragment.json',
              TOOLS / 'cf6-actor-template/actor.fragment.json',
              TOOLS / 'cf6-tutorial/tutorial-map.fragment.json',
              TOOLS / 'cf6-map-runtime/generated/runtime-index.json',
              TOOLS / 'cf6-map-source/generated/map-input.json',
              TOOLS / 'cf6-map-runtime/generated/environment.fragment.xml',
              HERE / 'balance-input.json', SOURCE / 'shops.fragment.json',
              SKY_PARALLAX, TOOLS / 'cf6-tutorial/environment.fragment.xml',
              TOOLS / 'cf6-tutorial/provenance.json', TOOLS / 'cf6-tutorial/layout.json',
              TOOLS / 'cf6-tutorial/assemble.py', HERE / 'viewport-policy.json',
              HERE / 'viewport-assembly.py', HERE / 'generated/original-camera-layout.json']
    authored, economy, actor, tutorial, runtime, native = map(read, inputs[:6])
    by_id = {m['id']: m for m in authored['maps']}
    ready = {m['id']: m for m in runtime['maps']}
    native_maps = native['maps']
    if isinstance(native_maps, list):
        native_maps = {m['id']: m for m in native_maps}
    if list(ready) != ROUTE or set(by_id) != set(ROUTE + ['TUTORIAL']):
        raise ValueError('complete content/runtime route required; missing runtime maps: '
                         + ','.join(m for m in ROUTE if m not in ready))
    chapter = dict(schema='playable-book.v1', id='cf6-sting', routeId='historical',
                   title='闪客快打6：毒刺行动', stageName='书中历险-毒刺行动',
                   startingMoney=economy['startingMoney']['value'],
                   startingSkillPoints=economy['startingSkillPoints']['value'],
                   externalRewards=0, actor=actor['actor'],
                   maps=[copy.deepcopy(tutorial)] + [convert_map(by_id[m], ready[m], native_maps[m]) for m in ROUTE])
    sys.path.insert(0, str(TOOLS))
    spec = importlib.util.spec_from_file_location('book_builder', TOOLS / 'build-book-definition.py')
    validator = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(validator)
    from choice_reward_catalog import item_catalog
    items = item_catalog()
    skills = ET.parse(ROOT / 'data/skills/skills.xml').findall('Skill')
    environment_fragment = merge_environment_fragments(inputs[6].read_bytes(), inputs[10].read_bytes())
    viewport_spec = importlib.util.spec_from_file_location('cf6_viewport', HERE / 'viewport-assembly.py')
    viewport = importlib.util.module_from_spec(viewport_spec)
    viewport_spec.loader.exec_module(viewport)
    environment_fragment, viewport_audit = viewport.adapt(chapter, environment_fragment, native_maps)
    turret_audit = apply_turrets(chapter, read(TURRET_FRAGMENT), require_swfs=require_swfs)
    inputs.extend(viewport.geometry_path(map_id) for map_id in ['TUTORIAL'] + ROUTE)
    inputs.append(viewport.REFERENCES)
    inputs.extend(ROOT / row['decodedLoad'] for row in viewport.load()[1].values())
    environments = {node.findtext('BackgroundURL'):node for node in ET.fromstring(environment_fragment).findall('Environment')}
    shops, economy_audit = install_economy(chapter, economy, read(inputs[7]), read(inputs[8]), items, skills, environments)
    sky_audit = apply_sky_parallax(chapter, load_sky_parallax(inputs[9]), require_swfs=require_swfs)
    units = {int(row['id']) for row in read(ROOT / 'data/units/units.json')}
    validator.validate_cf6(chapter, items, skills, units,
                           require_backgrounds=require_swfs)
    inputs.extend([ROOT / 'data/skills/skills.xml', ROOT / 'data/items/list.xml',
                   ROOT / 'data/rewards/choice-rewards.json', SOURCE / 'choice-rewards.fragment.json',
                   TURRET_FRAGMENT])
    inputs.extend(ROOT / 'data/items' / node.text for node in ET.parse(ROOT / 'data/items/list.xml').findall('items'))
    manifest = {'schema': 'cf6-chapter-assembly.v1', 'bookId': chapter['id'],
                'routeId': chapter['routeId'], 'maps': ['TUTORIAL'] + ROUTE,
                'inputs': [{'path': str(p.relative_to(ROOT)).replace('\\', '/'),
                            'sha256': hashlib.sha256(p.read_bytes()).hexdigest()} for p in inputs],
                'scope': 'authored playable prototype; no full-route gameplay acceptance',
                'economyAssembly': economy_audit,
                'skyParallaxLayers': sky_audit,
                'viewportAssembly': viewport_audit,
                'turretAssembly': turret_audit,
                'pendingPresentation': {m: {key: ready[m].get(key, []) for key in
                                           ('pendingDynamics', 'deferredLayers', 'runtimeProps')}
                                        for m in ROUTE}}
    outputs = {OUTPUT: encoded(chapter), HERE / 'generated/assembly.json': encoded(manifest),
               ENVIRONMENT: environment_bytes(ENVIRONMENT.read_bytes(), environment_fragment),
               SHOP_LIST: shop_manifest_bytes(SHOP_LIST.read_bytes(), shops)}
    outputs.update({ROOT / 'data/shops/npcs' / (shop['shopId'] + '.json'):encoded(shop) for shop in shops})
    return outputs


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--allow-missing-swfs', action='store_true',
                        help='Authoring only; runtime generation still requires compiled resources')
    args = parser.parse_args()
    outputs = build(require_swfs=not args.allow_missing_swfs)
    for path, data in outputs.items():
        if args.check:
            if not path.is_file() or path.read_bytes() != data:
                raise SystemExit('stale: ' + str(path.relative_to(ROOT)))
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        print(str(path.relative_to(ROOT)))


if __name__ == '__main__':
    main()
