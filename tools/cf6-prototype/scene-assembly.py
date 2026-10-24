"""Bind original door choreography to CF7 world coordinates and standard exits.

The viewport boundary has already run. Every world coordinate is final here;
local art, its mask and its actor track share one authored door-threshold pivot.
No source animation is executed and no next-stage or reward authority is added.
"""
from __future__ import annotations

import copy
import hashlib
import json
import math
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
PREP = ROOT / 'tools/cf6-scene-completion'
PLAN = PREP / 'completion-plan.json'
ART = PREP / 'traversal-art-manifest.json'
DEPTH_PROPS = ROOT / 'tools/cf6-prop-layout/generated/depth-props.fragment.json'
AUX = PREP / 'auxiliary-art-manifest.json'
SCENIC_WINGS = PREP / 'scenic-wings-manifest.json'
NATIVE_MAPS = ROOT / 'tools/cf6-map-source/generated/map-input.json'
ELEVATOR_EXIT_SOURCE = ROOT / 'flashswf/arts/new/Codex素材源稿/CF6地图/A11-R2/cf6-stage11-redraw-r2/reference/environment-original-nodes.json'
ELEVATOR_EXIT_GEOMETRY = ROOT / 'tools/cf6-map-runtime/generated/A11-original-geometry.json'
PROFILES = {
    1720: {'pivot': [0, 87.55], 'visualScale': 1},
    1729: {'pivot': [0, -26.45], 'visualScale': 1},
    1750: {'pivot': [2.5, 89.5], 'visualScale': 1.12},
}


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def rounded(value):
    return round(value, 4)


def apply_point(matrix, point):
    a, b, c, d, tx, ty = matrix
    return [a * point[0] + c * point[1] + tx,
            b * point[0] + d * point[1] + ty]


def art_url(asset):
    xfl = Path(asset['xfl'])
    return (xfl.parent.parent / (asset['name'] + '.swf')).as_posix()


def require_asset(asset, require_swfs):
    if not (ROOT / asset['xfl']).is_file():
        raise ValueError('missing native traversal source: ' + asset['name'])
    url = art_url(asset)
    if require_swfs and not (ROOT / url).is_file():
        raise ValueError('fresh CS6 traversal resource is required: ' + url)
    return url


def align_exit(environment, gate):
    """Place the existing standard door at the real authored gate, not a remote edge."""
    door = environment.find('Door')
    if door is None:
        raise ValueError('standard exit missing')
    values = {'Direction': '上', 'x0': gate['x'] - 24, 'x1': gate['x'] + 24,
              'y0': gate['z'] - 12, 'y1': gate['z'] + 12}
    for key, value in values.items():
        target = door.find(key)
        if target is None:
            raise ValueError('standard exit field missing: ' + key)
        target.text = value if isinstance(value, str) else str(rounded(value))


def align_post_elevator_exit(maps, envs, audit):
    """A11's source1617 exit is left; A14's same trigger is genuinely right.

    Source1617 waits for its required count, then tests man1.area; its A11 load
    targets a12. Only the standard CF7 door is relocated, with no auto clear.
    """
    if hashlib.sha256(ELEVATOR_EXIT_SOURCE.read_bytes()).hexdigest() != '133fd7aa4e2a84802ff4e7723a7da5d1fa0e0634f897ffa9abe3562888c80202':
        raise ValueError('post-elevator original marker source changed')
    source = read(ELEVATOR_EXIT_SOURCE)['nodes']
    geometry = read(ELEVATOR_EXIT_GEOMETRY)
    if (geometry['originalSwfSha256'] != 'b52af10e2dda43332e0b2ffb9549d2fad474f298b9f6c67d848ffc33ff589b01'
            or geometry['map'] != 'A11' or geometry['geometry']['worldSprite'] != 1910):
        raise ValueError('post-elevator world identity changed')
    placements = [p for p in geometry['geometry']['display'] if p.get('id') == 1617]
    if len(placements) != 1 or placements[0]['depth'] != 129:
        raise ValueError('post-elevator source exit inventory changed')
    trigger = source['1617']['frames'][0]['1']
    shape = source['1616']['frames'][0]['1']
    if trigger['id'] != 1616 or trigger['name'] != 'area' or shape['id'] != 277:
        raise ValueError('post-elevator source hit-test chain changed')
    x,y,width,height = source['277']['viewBox']
    points = [apply_point(placements[0]['matrix'], apply_point(trigger['matrix'], apply_point(shape['matrix'], p)))
              for p in ((x,y),(x+width,y),(x+width,y+height),(x,y+height))]
    raw = [min(p[0] for p in points), min(p[1] for p in points),
           max(p[0] for p in points), max(p[1] for p in points)]
    stage = maps['A11'];scale = stage['presentation']['scale']
    env = envs[Path(stage['background']).name]
    walk = [float(env.findtext(k)) for k in ('Xmin','Ymin','Xmax','Ymax')]
    rect = [max(raw[0]*scale,walk[0]),max(raw[1]*scale,walk[1]),
            min(raw[2]*scale,walk[2]),min(raw[3]*scale,walk[3])]
    if not (rect[0] < rect[2] < walk[0]+100*scale and rect[1] < rect[3]):
        raise ValueError('original left exit does not intersect the current walk bounds')
    door = env.find('Door')
    if door is None: raise ValueError('post-elevator standard exit missing')
    door.find('Direction').text = '左'
    for key,value in zip(('x0','y0','x1','y1'),rect): door.find(key).text = str(rounded(value))
    audit.append({'id':'A11','sourceSprite':1617,'sourceDepth':129,'sourceWorld':1910,
                  'sourceTriggerBounds':raw,'standardExitDirection':'左','standardExitBounds':[rounded(v) for v in rect],
                  'nextMap':'A12','basis':'original1617->1616->277 hit-test area intersected with final walk bounds; standard clear/navigation authority unchanged'})


def elevator_track(mode, start, end, frames=30):
    """Explicit CF7 staging around an original room cut, not recovered CF6 motion."""
    samples = []
    for frame in range(1, frames + 1):
        t = (frame - 1) / (frames - 1)
        samples.append({'frame': frame, 'x': rounded(start[0] + (end[0]-start[0])*t),
                        'z': rounded(start[1] + (end[1]-start[1])*t),
                        'visible': True, 'action': 'walk'})
    spec = {'mode': mode, 'fps': 30, 'durationFrames': frames,
            'actorReleaseFrame': None, 'samples': samples,
            'basis': 'CF7 continuous platform boarding/alighting adaptation; original cuts do not supply this track'}
    if mode == 'depart':
        spec['gate'] = {'x': start[0], 'z': start[1], 'radius': 35}
        spec['exit'] = {'x': end[0], 'z': end[1]}
    return spec


def auxiliary_layers(maps, envs, audit, require_swfs):
    source = read(AUX)
    if source['schema'] != 'cf6-auxiliary-native-source.v1':
        raise ValueError('unreviewed auxiliary source')
    assets = {a['sourceSprite']: a for a in source['assets']}
    native = read(NATIVE_MAPS)['maps']
    profiles = {1430: ([-12.74568138, 88], 1.12), 1862: ([-7.075, 80.5], 1.3),
                1832: ([0, 0], 1)}
    for placement in source['placements']:
        map_id, sprite = placement['mapId'], placement['sourceSprite']
        node, asset = maps[map_id], assets[sprite]
        if placement['coordinateSpace'] != 'original gameworld; transform once in scene-assembly':
            raise ValueError('auxiliary placement is not original world space')
        matrix = placement['nativeMatrix']
        if len(matrix) != 6 or any(not math.isfinite(v) for v in matrix):
            raise ValueError('invalid auxiliary placement matrix')
        pivot, visual = profiles[sprite]
        scale = node['presentation']['scale']
        anchor = [rounded(v*scale) for v in apply_point(matrix,pivot)]
        a,b,c,d = [v*visual for v in matrix[:4]]
        art_matrix = [round(v,9) for v in (a,b,c,d,-a*pivot[0]-c*pivot[1],-b*pivot[0]-d*pivot[1])]
        layer = {'id': f'{map_id}-aux-{sprite}-{placement["sourceDepth"]}',
                 'role': 'ambient-loop' if sprite==1832 else 'depth-prop',
                 'url': require_asset(asset,require_swfs), 'x': anchor[0], 'y': anchor[1],
                 'width': 1, 'height': 1, 'depth': placement['sourceDepth'],
                 'frames': asset['frames'], 'visualScale': 1, 'artMatrix': art_matrix,
                 'sortY': anchor[1]}
        # The shared door art does not bake a map instance's original tint.
        for prop in native[map_id].get('props',[]):
            for instance in prop.get('instances',[]):
                if instance['depth'] == placement['sourceDepth'] and 'colorMult' in instance:
                    layer['colorMult'] = instance['colorMult']
        if sprite == 1430:
            x,z = [rounded(v*scale) for v in apply_point(matrix,placement['gateLocal'])]
            gate = {'x':x,'z':z,'radius':42}
            samples = [{'frame':frame,'x':x,'z':z,'visible':True,'action':'stand'} for frame in range(1,59)]
            node['mechanism']['kind'] = 'door'
            node['mechanism']['traversal'] = {'depart': {
                'mode':'depart','fps':30,'durationFrames':58,'actorReleaseFrame':None,
                'samples':samples,'gate':gate,'exit':{'x':x,'z':z},'preserveActorPosition':True,
                'sourceSprite':1430,'coordinateSpace':'CF7 world; viewport already applied once',
                'basis':'original door cuts at frame 58 of 59; CF7 holds the live actor at its actual entry footpoint'}}
            layer.update(role='traversal-layer',traversalMode='depart')
            align_exit(envs[Path(node['background']).name],gate)
        elif sprite == 1862 and map_id in ('A12','A19','A20','A22'):
            stage_points = node['stage'].get('SpawnPoint',{}).get('Point',[])
            boss_points = [e for g in node.get('bossEncounter',{}).get('groups',[])
                           for e in g['enemies'] if 'x' in e and 'y' in e]
            candidates = stage_points + boss_points
            if not candidates:
                raise ValueError('spawn door has no actual declared spawn point: '+layer['id'])
            nearest = min(candidates,key=lambda p:math.hypot(p['x']-anchor[0],p['y']-anchor[1]))
            distance = math.hypot(nearest['x']-anchor[0],nearest['y']-anchor[1])
            if distance > 100:
                raise ValueError('actual spawn is not at the declared door: '+layer['id'])
            layer.update(role='door-spawn-sequence',spawnX=nearest['x'],spawnY=nearest['y'],spawnRadius=96)
            # Emit an existing observation event only; budgets, timing, positions and deaths are unchanged.
            for wave in node['stage']['Wave']['SubWave']:
                for enemy in wave['EnemyGroup']['Enemy']:
                    if type(enemy.get('SpawnIndex')) is int and stage_points[enemy['SpawnIndex']] is nearest:
                        enemy.setdefault('Parameters',{})['publishStageEvent'] = True
            # Boss support ownership already emits UnitSpawn in Cf6BossEncounter;
            # its reserved publishStageEvent parameter must remain controller-owned.
        node['mechanism']['layers'].append(layer)
        audit.append({'id':layer['id'],'mapId':map_id,'sourceSprite':sprite,
                      'sourceDepth':placement['sourceDepth'],'groundPivot':pivot,'worldPivot':anchor,
                      'visualScale':visual,'nativeMatrix':matrix,'role':layer['role'],
                      'basis':'complete source timeline and native shear retained; source area gate separate from visual floor pivot'})


def scenic_wings(maps, audit, require_swfs):
    source=read(SCENIC_WINGS)
    if source['schema']!='cf6-scenic-wings.v1' or source['frames']!=15 or source['sourceSprite']!=1777:
        raise ValueError('unreviewed scenic actor source')
    asset=ROOT/source['xfl'];runtime=ROOT/source['swf']
    if not asset.is_file() or require_swfs and not runtime.is_file():
        raise ValueError('fresh CS6 scenic Wings resource required')
    for place in source['placements']:
        node=maps[place['mapId']];scale=node['presentation']['scale'];matrix=place['nativeMatrix']
        body=source['bodyScale'];x,y=[rounded(v*scale) for v in matrix[4:]]
        layer={'id':place['mapId']+'-scenic-wings','role':'scenic-actor','url':source['swf'],
               'x':x,'y':y,'sortY':y,'width':1,'height':1,'depth':place['sourceDepth'],'frames':15,
               'visualScale':1,'artMatrix':[round(v*body,9) for v in matrix[:4]]+[0,0]}
        if place.get('speech'):layer['speech']=place['speech']
        node['mechanism']['layers'].append(layer)
        audit.append({'id':layer['id'],'sourceSprite':1777,'sourceDepth':place['sourceDepth'],
                      'worldFootpoint':[x,y],'bodyScale':body,
                      'basis':'original visual-only actor; current native 190cm standing art; no combat or protection authority'})


def adapt(chapter, environment_bytes, require_swfs=True):
    plan, art = read(PLAN), read(ART)
    if plan['schema'] != 'cf6-scene-completion-plan.v1' or art['schema'] != 'cf6-traversal-native-source.v1':
        raise ValueError('unreviewed scene inputs')
    environment = ET.fromstring(environment_bytes)
    envs = {n.findtext('BackgroundURL'): n for n in environment}
    maps = {m['id']: m for m in chapter['maps']}
    if any('traversal' in m['mechanism'] for m in chapter['maps']):
        raise ValueError('scene choreography already assembled; refusing a second coordinate transform')
    assets = {(a['sourceSprite'], a['role']): a for a in art['assets']}
    audit = []
    for source in plan['traversals']:
        node = maps[source['mapId']]
        mechanism = node['mechanism']
        mode, sprite = source['mode'], source['sourceSprite']
        if source['coordinateSpace'] != 'original symbol local; no viewport multiplier applied':
            raise ValueError('traversal must enter assembly in original local coordinates')
        matrix = source['sourcePlacement']
        if matrix[:4] != [1, 0, 0, 1]:
            raise ValueError('nonuniform door transform requires a reviewed art-matrix consumer')
        scale = node['presentation']['scale']
        profile = PROFILES[sprite]
        pivot, visual = profile['pivot'], profile['visualScale']
        anchor = [rounded(v*scale) for v in apply_point(matrix, pivot)]
        def world_point(x, z):
            return [rounded(anchor[0] + (x-pivot[0])*visual),
                    rounded(anchor[1] + (z-pivot[1])*visual)]
        samples = []
        for row in source['samples']:
            x, z = world_point(row['x'], row['z'])
            samples.append({**row, 'x': x, 'z': z})
        visible = [r for r in samples if r['visible']]
        if not visible:
            raise ValueError('empty actor track')
        gate = {'x': visible[0]['x'], 'z': visible[0]['z'], 'radius': 42}
        spec = {k: copy.deepcopy(source[k]) for k in ('mode', 'fps', 'durationFrames', 'actorReleaseFrame')}
        spec.update(samples=samples, coordinateSpace='CF7 world; viewport already applied once',
                    sourceSprite=sprite, actorSortY=anchor[1])
        if mode == 'depart':
            spec.update(gate=gate, exit={'x': gate['x'], 'z': gate['z']})
            align_exit(envs[Path(node['background']).name], gate)
            # Supersede only the old cut-down departure animation, preserving enemy spawn doors.
            mechanism['layers'] = [r for r in mechanism['layers'] if r['role'] != 'door-exit-sequence']
        else:
            node['stage']['BasicInformation'].update(PlayerX=samples[0]['x'], PlayerY=samples[0]['z'])
        mechanism.setdefault('traversal', {})[mode] = spec
        for role, offset in (('Back', -1), ('Front', 1), ('Mask', 0)):
            asset = assets[sprite, role]
            if sprite == 1750 and role == 'Front':
                # The complete source timeline is empty; keep its source, omit the runtime load.
                continue
            if role == 'Mask' and not asset['maskActiveFrames']:
                continue
            url = require_asset(asset, require_swfs)
            layer = {'id': source['id'] + '-' + role.lower(),
                     'role': 'actor-mask' if role == 'Mask' else 'traversal-layer',
                     'url': url, 'x': anchor[0], 'y': anchor[1], 'width': 1, 'height': 1,
                     'depth': source['sourceDepth'] * 4 + offset,
                     'frames': source['durationFrames'], 'visualScale': visual,
                     'pivot': {'x': pivot[0], 'y': pivot[1]}, 'traversalMode': mode,
                     'sortY': anchor[1] + offset}
            if role == 'Mask':
                layer['maskActiveFrames'] = asset['maskActiveFrames']
                spec['maskLayerId'] = layer['id']
            mechanism['layers'].append(layer)
        audit.append({'id': source['id'], 'sourceSprite': sprite, 'thresholdLocal': pivot,
                      'thresholdWorld': anchor, 'visualScale': visual, 'gate': gate,
                      'sourceFrames': source['durationFrames'], 'actorReleaseFrame': source['actorReleaseFrame'],
                      'basis': 'source local track and art share fixed world threshold; standard exit aligned to authored gate'})
    for node in chapter['maps']:
        scale = node['presentation']['scale']
        for layer in node['mechanism']['layers']:
            if layer['role'] != 'door-spawn-sequence':
                continue
            # The old native door export normalized viewBox [-85,-100,170,240].
            layer['x'] = rounded(layer['x'] + 85*scale)
            layer['y'] = rounded(layer['y'] + 185*scale)
            layer.update(pivot={'x': 85, 'y': 185}, visualScale=1, sortY=layer['y'])
    align_post_elevator_exit(maps, envs, audit)
    for map_id in ('A10', 'A13'):
        node = maps[map_id]
        basic, mechanism = node['stage']['BasicInformation'], node['mechanism']
        scale = node['presentation']['scale']
        door = envs[Path(node['background']).name].find('Door')
        exit_point = [rounded((float(door.findtext(a))+float(door.findtext(b)))/2)
                      for a, b in (('x0','x1'), ('y0','y1'))]
        spawn = [basic['PlayerX'], basic['PlayerY']]
        board = [rounded(spawn[0]+45*scale), spawn[1]]
        approach = [rounded(exit_point[0]-40*scale), exit_point[1]]
        mechanism['traversal'] = {'arrive': elevator_track('arrive', spawn, board),
                                  'depart': elevator_track('depart', approach, exit_point)}
        audit.append({'id': map_id, 'platformBoarding': [spawn, board],
                      'platformAlighting': [approach, exit_point],
                      'basis': 'CF7 continuous staging; existing shaft/foreground retained; no fabricated gate leaf'})
    auxiliary_layers(maps, envs, audit, require_swfs)
    scenic_wings(maps, audit, require_swfs)
    props = read(DEPTH_PROPS)
    if props['schema'] != 'cf6-depth-props-fragment.v1' or set(props['maps']) != {'A06'}:
        raise ValueError('unreviewed depth-prop route')
    for map_id, entry in props['maps'].items():
        for layer in entry['layers']:
            if layer['role'] != 'depth-prop' or layer['visualScale'] != 1 or layer['pivot'] != {'x': 0, 'y': 0}:
                raise ValueError('depth props must use their final holder-local matrix')
            if require_swfs and not (ROOT / layer['url']).is_file():
                raise ValueError('fresh CS6 depth-prop resource is required: ' + layer['url'])
            maps[map_id]['mechanism']['layers'].append(dict(layer, width=1, height=1, depth=0))
            audit.append({'id':layer['id'], 'mapId':map_id, 'sortY':layer['sortY'],
                          'basis':'background duplicate removed; native grouped art uses final world footpoint'})
    return ET.tostring(environment, encoding='utf-8', xml_declaration=True), audit
