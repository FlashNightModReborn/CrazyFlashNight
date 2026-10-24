"""Bind original interactive props and migrate the ten existing clone budgets.

The chapter has already crossed the viewport boundary. Original source placement
origins are transformed exactly once; local visual size remains one. This module
does not execute original actions or add enemies, rewards or collision walls.
"""
from __future__ import annotations

import copy
import hashlib
import json
import math
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / 'tools/cf6-scene-completion/interactive-art-manifest.json'
EXPLOSION_SOURCE = ROOT / 'flashswf/arts/原版素材库-子弹/LIBRARY/手雷/地瓜手雷/地瓜手雷.xml'
PROJECTION_SHA = 'da8403d2135566583ef7baf6a1351c820f5bcb78a31c633a95066e239aa04e01'
PROJECTION_SOURCE = ROOT / f'tools/cf6-scene-completion/source-evidence/actions/{PROJECTION_SHA}.as.txt'
ORIGINAL_SHA = 'b52af10e2dda43332e0b2ffb9549d2fad474f298b9f6c67d848ffc33ff589b01'
COUNTS = {'A04':3,'A08':3,'A11':1,'A12':3,'A15':5,'A17':5,'A18':1,'A20':3}


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def finite(value):
    return type(value) in (int, float) and math.isfinite(value)


def original_projectile_projection():
    source = PROJECTION_SOURCE.read_bytes()
    if hashlib.sha256(source).hexdigest() != PROJECTION_SHA:
        raise ValueError('original projectile projection evidence changed')
    offsets = re.findall(r'_root\.gameworld\.效果\[效果名\]\._y\s*=\s*myY\s*-\s*([0-9]+)\s*;',source.decode('utf-8-sig'))
    if offsets != ['90']:
        raise ValueError('original projectile visual offset is not the reviewed contract')
    return float(offsets[0])


def transformed_bounds(bounds, linear):
    if (not isinstance(bounds, list) or len(bounds) != 4
            or any(not finite(v) for v in bounds)
            or bounds[0] >= bounds[2] or bounds[1] >= bounds[3]):
        raise ValueError('invalid original interactive bounds')
    a,b,c,d = linear
    points = [(a*x+c*y,b*x+d*y) for x,y in
              ((bounds[0],bounds[1]),(bounds[2],bounds[1]),
               (bounds[2],bounds[3]),(bounds[0],bounds[3]))]
    return [round(min(p[0] for p in points),4),round(min(p[1] for p in points),4),
            round(max(p[0] for p in points),4),round(max(p[1] for p in points),4)]


def migrate_pod_budget(stage, props):
    """Replace the existing five-unit producer with one precise entry per pod."""
    identity = stage['id']
    if len(props) != 5 or len({p['id'] for p in props}) != 5:
        raise ValueError('clone pod migration requires five distinct original instances')
    if identity == 'A15':
        waves = stage['stage']['Wave']['SubWave']
        import sys
        sys.path.insert(0, str(ROOT / 'tools/cf6-roguelike-content'))
        import difficulty_plan
        difficulty = difficulty_plan.metadata(stage)
        if len(waves) != (len(difficulty['waveKinds']) if difficulty else 1) or difficulty is not None and difficulty['waveKinds'][0] != 'pods':
            raise ValueError('unexpected A15 wave structure')
        entries = waves[0]['EnemyGroup']['Enemy']
    elif identity == 'A17':
        plan = stage['bossEncounter']
        if plan['maxAlive'] != 4 or plan['intervalFrames'] != 45 or plan['groups'][0]['hpRatio'] != 1:
            raise ValueError('A17 finite support policy changed')
        entries = plan['groups'][0]['enemies']
    else:
        raise ValueError('unreviewed clone pod budget')
    selected = [entry for entry in entries if entry['Type'] == '兵种460']
    if (len(selected) != 1 or selected[0]['Quantity'] != 5
            or selected[0]['Level'] != (50 if identity == 'A15' else 55)
            or any(key in selected[0] for key in ('TriggerEvent','podId'))):
        raise ValueError('existing five-unit clone budget changed or was already migrated')
    source = selected[0]
    replacements = []
    for prop in props:
        enemy = copy.deepcopy(source)
        enemy.update(Quantity=1, x=prop['x'], y=prop['y'])
        if identity == 'A15':
            # Single-use pods have no repeat cadence. The shared wheel otherwise adds
            # inherited Interval300 to the first dispatch, leaving 9-12 blank frames.
            enemy['Interval'] = 0
            enemy['Delay'] = 0
            enemy['TriggerEvent'] = {'EventName':'Cf6PodReady','Parameters':[prop['id']]}
            params = enemy.setdefault('Parameters', {})
            if any(key in params for key in ('cf6PodId','cf6BossOwnerToken','cf6SupportIdentity')):
                raise ValueError('clone pod source already has private ownership')
            params.update(cf6PodId=prop['id'], publishStageEvent=True)
        else:
            enemy['podId'] = prop['id']
        replacements.append(enemy)
    at = entries.index(source)
    entries[at:at+1] = replacements
    stage.setdefault('sourceNote', {})['interactivePodAdaptation'] = {
        'sourceSprite':1939, 'existingQuantity':5, 'finalQuantity':5,
        'type':'兵种460', 'level':source['Level'],
        'authority':'counted wave TriggerEvent' if identity == 'A15' else 'existing finite boss support controller',
        'basis':'original rectangular proximity trigger, logical animation frame 24; last visible birth pose held until real initialized actor; existing clone type retained',
        'firstSpawnDelayMs':0 if identity == 'A15' else None,
    }


def adapt(chapter, require_swfs=True):
    manifest = read(MANIFEST)
    if manifest.get('schema') != 'cf6-interactive-native-source.v1' or manifest.get('originalSha256') != ORIGINAL_SHA:
        raise ValueError('unreviewed interactive art source')
    assets = {a['sourceSprite']:a for a in manifest['assets']}
    if len(assets) != 4 or set(assets) != {1736,1838,1976,1939}:
        raise ValueError('interactive source inventory mismatch')
    maps = {m['id']:m for m in chapter['maps']}
    if not set(COUNTS) <= set(maps): raise ValueError('interactive route incomplete')
    if any('interactiveProps' in m.get('mechanism', {}) for m in maps.values()):
        raise ValueError('interactive props already assembled')
    groups = {key:[] for key in COUNTS}
    audit = []
    gun_projection = original_projectile_projection()
    for source in manifest['placements']:
        identity, sprite = source['mapId'], source['sourceSprite']
        if identity not in groups or sprite not in assets:
            raise ValueError('unreviewed interactive placement')
        if source['coordinateSpace'] != 'original gameworld; transform once in scene assembly':
            raise ValueError('interactive source coordinate space mismatch')
        asset, stage = assets[sprite], maps[identity]
        kind = 'pod' if sprite == 1939 else 'barrel'
        suffix = 'Pod' if kind == 'pod' else 'Barrel'
        name = f'CF6_Interactive{suffix}{sprite}'
        expected_url = f'flashswf/backgrounds/cf6/preparation/{name}.swf'
        if (asset['name'] != name or asset['swf'] != expected_url
                or asset['frames'] != (25 if kind == 'pod' else 16)
                or asset['localOrigin'] != [0,0] or asset['localCompensation'] != [0,0]
                or asset['visualScale'] != 1
                or (asset['damageFrame'],asset['spawnFrame']) != ((None,24) if kind == 'pod' else (7,None))):
            raise ValueError('interactive source geometry or event timing changed')
        if not (ROOT / asset['xfl']).is_file():
            raise ValueError('missing native interactive source: '+name)
        if require_swfs:
            runtime = ROOT / expected_url
            if not runtime.is_file() or runtime.read_bytes()[:3] not in (b'FWS',b'CWS',b'ZWS'):
                raise ValueError('fresh CS6 interactive resource required: '+name)
        matrix = source['nativeMatrix']
        if not isinstance(matrix, list) or len(matrix) != 6 or any(not finite(v) for v in matrix):
            raise ValueError('invalid native interactive placement')
        scale = stage['presentation']['scale']
        if not finite(scale) or scale <= 0: raise ValueError('missing final viewport transform')
        linear = matrix[:4]
        local = manifest['triggers'][str(sprite)]['localAabb']
        hit_scale = scale if kind == 'pod' else 1
        bounds = transformed_bounds(local, [v*hit_scale for v in linear])
        # Pods retain the original birth registration. Barrels retain their original
        # world foot edge while local art stays unscaled: resizing around the centre
        # registration would otherwise lift every barrel off its authored floor.
        visual_bounds = transformed_bounds(asset['frame1VisualBounds'], linear)
        if kind == 'barrel':
            # Original gun logic used the foot marker together with a separate
            # -90px impact/tracer projection. Restore its shootable band in CF7
            # world collision alongside the resting body/foot marker. This is
            # a barrel-only adapter; it does not enlarge art or debris bounds.
            bounds = [min(bounds[0],visual_bounds[0]),min(bounds[1]-gun_projection,visual_bounds[1]),
                      max(bounds[2],visual_bounds[2]),max(bounds[3],visual_bounds[3])]
        x,y = [round(v*scale,4) for v in matrix[4:]]
        if kind == 'barrel':
            y = round((matrix[5]+visual_bounds[3])*scale-visual_bounds[3],4)
        prop = {'id':f'{identity}-{kind}-{source["sourceDepth"]}', 'kind':kind,
                'sourceSprite':sprite, 'url':expected_url, 'x':x, 'y':y,
                'sortY':round(y+visual_bounds[3],4),
                'artMatrix':[round(v,9) for v in linear]+[0,0],
                'hitBounds':bounds, 'frames':asset['frames']}
        if kind == 'pod': prop['spawnAuthority'] = 'wave' if identity == 'A15' else 'boss'
        else: prop['groundY'] = round(y+visual_bounds[3],4)
        groups[identity].append(prop)
        audit.append({'id':prop['id'],'sourceSprite':sprite,'sourceDepth':source['sourceDepth'],
                      'registrationWorld':[x,y],'sortY':prop['sortY'],
                      'visualScale':1,'hitBounds':bounds,
                      'basis':('original world footpoint retained; unscaled art registration derived from its resting floor edge' if kind=='barrel' else 'world birth registration transformed once; original clone handoff unchanged'),
                      'triggerSpace':'original map area scaled once' if kind == 'pod' else 'CF7 resting body plus original foot/90px-projected gun band; no art or debris enlargement'})
    for identity, props in groups.items():
        if len(props) != COUNTS[identity] or len({p['id'] for p in props}) != len(props):
            raise ValueError('authored interactive instance count changed: '+identity)
        stage = maps[identity]
        stage['mechanism']['interactiveProps'] = {'schema':'cf6-interactive-props.v1','props':props}
        if identity in ('A15','A17'): migrate_pod_budget(stage,props)
    return audit
