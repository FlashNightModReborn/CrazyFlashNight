"""CF6 reinforcement entrances and staggered queues; never changes encounter budgets.

Call after interactive/transport assembly and the A20 finale merge. Environment
elements are the same normalized elements used to emit the chapter's XML.
"""
from __future__ import annotations

import copy
import hashlib
import json
import math
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "cf6-roguelike-content"))
import difficulty_plan

INTERVAL_MS = 400
PHASE_MS = 200
MARKER = 'reinforcementSpawnAssembly'


def digest(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True,
                                     separators=(',', ':')).encode('utf-8')).hexdigest()


def finite(value):
    return type(value) in (int, float) and math.isfinite(value)


def polygons(environment):
    result = []
    for collision in environment.findall('Collision'):
        points = [tuple(map(float, point.text.split(','))) for point in collision.findall('Point')]
        if len(points) < 3 or any(len(p) != 2 or not all(map(finite, p)) for p in points):
            raise ValueError('invalid normalized collision polygon')
        turns = []
        for a, b, c in zip(points, points[1:] + points[:1], points[2:] + points[:2]):
            cross = (b[0]-a[0])*(c[1]-b[1]) - (b[1]-a[1])*(c[0]-b[0])
            if abs(cross) > 0.000001:
                turns.append(cross > 0)
        if not turns or any(t != turns[0] for t in turns):
            raise ValueError('collision input must contain normalized convex polygons')
        result.append(points)
    return result


def overlaps(box, polygon):
    """Separating-axis test for the generator's convex collision trapezoids."""
    corners = [(box[0], box[1]), (box[2], box[1]), (box[2], box[3]), (box[0], box[3])]
    axes = [(1, 0), (0, 1)]
    for a, b in zip(polygon, polygon[1:] + polygon[:1]):
        axes.append((a[1] - b[1], b[0] - a[0]))
    for nx, ny in axes:
        if nx == ny == 0:
            continue
        first = [x * nx + y * ny for x, y in corners]
        second = [x * nx + y * ny for x, y in polygon]
        if max(first) < min(second) or max(second) < min(first):
            return False
    return True


def safe_box(environment, box):
    walk = [float(environment.findtext(k)) for k in ('Xmin', 'Ymin', 'Xmax', 'Ymax')]
    if not all(map(finite, box + walk)) or not (walk[0] < box[0] <= box[2] < walk[2]
                                                and walk[1] < box[1] <= box[3] < walk[3]):
        return False
    return not any(overlaps(box, p) for p in polygons(environment))


def edge_anchor(environment, side, preferred_y=None):
    line = environment.find('LeftSpawnLine' if side == 'left' else 'RightSpawnLine')
    if line is None:
        raise ValueError('explicit normalized side spawn line required: ' + side)
    x0, y0, x1, y1 = [float(line.findtext(k)) for k in ('x0', 'y0', 'x1', 'y1')]
    if not all(map(finite, [x0, y0, x1, y1])) or x0 > x1 or y0 > y1:
        raise ValueError('invalid explicit side spawn line')
    x = (x0 + x1) / 2
    preferred = preferred_y if finite(preferred_y) else (y0 + y1) / 2
    candidates = {max(y0, min(y1, preferred)), (y0 + y1) / 2}
    candidates.update(y0 + i * 4 for i in range(int((y1 - y0) / 4) + 1))
    for y in sorted(candidates, key=lambda v: (abs(v - preferred), v)):
        # A finite 24x12 logical-pixel foot envelope, not only a point-in-wall check.
        box = [x - 12, y - 6, x + 12, y + 6]
        if safe_box(environment, box):
            anchor = [round(x, 4), round(y, 4)]
            box = [anchor[0]-12, anchor[1]-6, anchor[0]+12, anchor[1]+6]
            if safe_box(environment, box):
                return anchor, {'line': [x0, y0, x1, y1], 'footEnvelope': box}
    raise ValueError('no collision-free edge entrance: ' + side)


def protected(entry, allowed):
    return {k: v for k, v in entry.items() if k not in allowed}


def adapt(chapter, environments):
    """Mutate only approved placement/timing fields and return a self-contained audit."""
    audit = {'schema': 'cf6-spawn-assembly.v1', 'intervalMs': INTERVAL_MS,
             'phaseMs': PHASE_MS, 'wheelQuantumMs': 100,
             'recurringEffectiveMs': 500, 'waveQueues': [], 'spawnPoints': [], 'bossEntries': [], 'observationFlags': []}
    before_authority, after_authority, initial, pods = [], [], [], []
    for node in chapter['maps']:
        if not node['id'].startswith('A'):
            continue
        if MARKER in node.get('sourceNote', {}):
            raise ValueError('spawn assembly already applied: ' + node['id'])
        mid = node['id']
        environment = environments[node['background'].split('/')[-1]]
        stage = node['stage']
        points = stage.get('SpawnPoint', {}).get('Point', [])
        difficulty = difficulty_plan.metadata(node)
        point_roles = {r['index']:r['side'] for r in difficulty['spawnPointRoles']} if difficulty else {}
        doors = [p for p in node['mechanism'].get('layers', []) if p.get('role') == 'door-spawn-sequence']
        used_points = set()
        observed_points = set()
        queue_authority_index = {}
        for wi, wave in enumerate(stage['Wave']['SubWave']):
            queue_index = 0
            for ei, enemy in enumerate(wave['EnemyGroup']['Enemy']):
                key = [mid, wi, ei]
                original = copy.deepcopy(enemy)
                is_pod = enemy.get('TriggerEvent', {}).get('EventName') == 'Cf6PodReady'
                is_static = enemy.get('Quantity') == 1 and 'SpawnIndex' not in enemy and 'TriggerEvent' not in enemy
                designed_queue = difficulty is not None and difficulty['waveKinds'][wi] == 'combat'
                if is_pod:
                    pods.append([key, original])
                elif is_static:
                    initial.append([key, original])
                elif enemy.get('Quantity', 0) > 1 or designed_queue:
                    spawn = enemy.get('SpawnIndex')
                    if type(spawn) is not int or not 0 <= spawn < len(points):
                        raise ValueError('unreviewed ordinary reinforcement entrance: ' + str(key))
                    if 'x' in enemy or 'y' in enemy:
                        raise ValueError('numeric reinforcement point overridden by explicit coordinates: ' + str(key))
                    event = enemy.get('TriggerEvent', {}).get('EventName')
                    allowed_intervals = (100, INTERVAL_MS) if event == 'Cf6TransportReady' else (100,)
                    if enemy.get('Interval') not in allowed_intervals or event not in (None, 'Cf6TransportReady'):
                        raise ValueError('unreviewed reinforcement timing/event: ' + str(key))
                    if queue_index >= (16 if designed_queue else 2) or enemy.get('Delay', 0) != 0:
                        raise ValueError('unreviewed same-wave phase inventory: ' + str(key))
                    enemy['Interval'] = INTERVAL_MS
                    if queue_index:
                        enemy['Delay'] = PHASE_MS * queue_index
                    used_points.add(spawn)
                    queue_index += 1
                    audit['waveQueues'].append({'mapId': mid, 'waveIndex': wi, 'entryIndex': ei,
                        'spawnIndex': spawn, 'oldIntervalMs': original['Interval'],
                        'intervalMs': INTERVAL_MS, 'delayMs': enemy.get('Delay', 0),
                        'quantity': enemy['Quantity'], 'event': copy.deepcopy(enemy.get('TriggerEvent'))})
                before_authority.append([key, protected(original, {'Interval', 'Delay'})])
                after_authority.append([key, protected(copy.deepcopy(enemy), {'Interval', 'Delay'})])
                queue_authority_index[(wi,ei)] = len(after_authority)-1
                if is_pod or is_static:
                    if enemy != original:
                        raise AssertionError('preplaced/pod entry changed')
        for pi in sorted(used_points):
            point = points[pi]
            original = copy.deepcopy(point)
            x, y = point['x'], point['y']
            reviewed_entrance = None
            if pi in point_roles:
                side = point_roles[pi]
                middle = (float(environment.findtext('Xmin')) + float(environment.findtext('Xmax'))) / 2
                candidates = [d for d in doors if (d['spawnX'] < middle) == (side == 'left')
                              and safe_box(environment,[d['spawnX']-12,d['spawnY']-6,d['spawnX']+12,d['spawnY']+6])]
                if candidates:
                    door = sorted(candidates,key=lambda d:d['spawnX'],reverse=side=='right')[0]
                    x,y=door['spawnX'],door['spawnY'];reviewed_entrance=door['id']
                else:
                    (x,y), proof = edge_anchor(environment,side,y)
                    reviewed_entrance='difficulty-'+side+'-validated-edge'
                point['x'],point['y']=x,y
            matches = [door for door in doors if abs(door['spawnX'] - x) < 0.001 and abs(door['spawnY'] - y) < 0.001]
            vehicle = node['mechanism'].get('transport')
            if reviewed_entrance is not None:
                entrance = reviewed_entrance
                if reviewed_entrance in {d['id'] for d in doors}: observed_points.add(pi)
            elif matches:
                entrance = matches[0]['id']
            elif vehicle and abs(vehicle['x'] - x) <= 150 and abs(vehicle['y'] - y) <= 32:
                entrance = vehicle['id']
            elif mid == 'A01' and abs(float(environment.findtext('Xmax')) - x) <= 32:
                entrance = 'existing-right-edge-with-original-cap'
            else:
                raise ValueError('reinforcement point has no visible door, vehicle or reviewed edge: ' + str([mid, pi]))
            if 'BiasX' in point or 'BiasY' in point:
                raise ValueError('unreviewed existing point jitter: ' + str([mid, pi]))
            bias = [0, 0]
            for bx, by in [(12, 6), (8, 4), (4, 2)]:
                if safe_box(environment, [x - bx - 12, y - by - 6, x + bx + 12, y + by + 6]):
                    point.update(BiasX=bx, BiasY=by)
                    bias = [bx, by]
                    break
            allowed_point_fields = {'BiasX','BiasY','x','y'} if pi in point_roles else {'BiasX','BiasY'}
            if protected(point, allowed_point_fields) != protected(original, allowed_point_fields):
                raise AssertionError('spawn point position/cap changed')
            audit['spawnPoints'].append({'mapId': mid, 'index': pi, 'entrance': entrance,
                'position': [x, y], 'quantityMax': point.get('QuantityMax'), 'bias': bias,
                'footEnvelope': [12, 6], 'reason': 'collision-safe jitter' if any(bias) else 'cadence only; jitter envelope not proven safe'})
        # These reviewed points acquire their actual door binding after scene assembly.
        # Add only the existing observation event, preserving every authoritative field.
        for wi,wave in enumerate(stage['Wave']['SubWave']):
            for ei,enemy in enumerate(wave['EnemyGroup']['Enemy']):
                if enemy.get('SpawnIndex') not in observed_points: continue
                params=enemy.setdefault('Parameters',{})
                if params.get('publishStageEvent') is True: continue
                if 'publishStageEvent' in params: raise ValueError('difficulty cannot override an explicit observation policy')
                params['publishStageEvent']=True
                index=queue_authority_index[(wi,ei)]
                projected=copy.deepcopy(enemy);projected['Parameters'].pop('publishStageEvent')
                if not projected['Parameters'] and 'Parameters' not in before_authority[index][1]: del projected['Parameters']
                projected=protected(projected,{'Interval','Delay'})
                if projected!=before_authority[index][1]: raise AssertionError('door observation changed enemy authority')
                after_authority[index][1]=projected
                audit['observationFlags'].append({'mapId':mid,'waveIndex':wi,'entryIndex':ei,
                    'spawnIndex':enemy['SpawnIndex'],'field':'Parameters.publishStageEvent','value':True})
        plan = node.get('bossEncounter')
        phase_index = 0
        while plan:
            if mid not in ('A06', 'A17', 'A20'):
                raise ValueError('unreviewed boss reinforcement room ' + mid)
            preferred = {}
            if mid == 'A20':
                if len(doors) != 4 or any('1862' not in d['url'] for d in doors):
                    raise ValueError('A20 requires all four original 1862 doors')
                for enemy in plan['groups'][0]['enemies']:
                    if 'x' in enemy and 'y' in enemy:
                        match = [d for d in doors if abs(d['spawnX'] - enemy['x']) < 0.001 and abs(d['spawnY'] - enemy['y']) < 0.001]
                        if len(match) != 1:
                            raise ValueError('A20 authored support no longer matches one source door')
                        preferred[(enemy['Type'], enemy['SpawnIndex'])] = match[0]
            for gi, group in enumerate(plan['groups']):
                for ei, enemy in enumerate(group['enemies']):
                    key = [mid, 'boss', phase_index, gi, ei]
                    original = copy.deepcopy(enemy)
                    if 'podId' in enemy:
                        pods.append([key, original])
                        continue
                    side = enemy.get('SpawnIndex')
                    if side not in ('left', 'right'):
                        raise ValueError('unreviewed boss support side ' + str(key))
                    if mid == 'A20':
                        if 'x' in enemy and 'y' in enemy:
                            door = preferred[(enemy['Type'], side)]
                        else:
                            middle = (float(environment.findtext('Xmin')) + float(environment.findtext('Xmax'))) / 2
                            candidates = sorted([d for d in doors if (d['spawnX'] < middle) == (side == 'left')], key=lambda d: d['spawnX'])
                            if not candidates:
                                raise ValueError('no existing A20 door on requested side')
                            door = preferred.get((enemy['Type'], side), candidates[ei % len(candidates)])
                            enemy['x'], enemy['y'] = door['spawnX'], door['spawnY']
                        proof = {'entrance': door['id'], 'sourceDoorPosition': [door['spawnX'], door['spawnY']]}
                    else:
                        anchor, proof = edge_anchor(environment, side, enemy.get('y'))
                        enemy['x'], enemy['y'] = anchor
                        proof['entrance'] = side + '-validated-edge'
                    before_authority.append([key, protected(original, {'x', 'y'})])
                    after_authority.append([key, protected(enemy, {'x', 'y'})])
                    audit['bossEntries'].append({'mapId': mid, 'phase': phase_index, 'group': gi, 'entry': ei,
                        'side': side, 'before': [original.get('x'), original.get('y')], 'after': [enemy['x'], enemy['y']],
                        'quantity': enemy['Quantity'], **proof})
            plan = plan.get('nextPhase')
            phase_index += 1
        node.setdefault('sourceNote', {})[MARKER] = 'cf6-spawn-assembly.v1'
    if before_authority != after_authority:
        raise AssertionError('reinforcement budgets, levels, parameters or authority changed')
    audit.update(authorityBeforeSha256=digest(before_authority), authorityAfterSha256=digest(after_authority),
                 preservedInitialEntries=len(initial), preservedInitialSha256=digest(initial),
                 preservedPodEntries=len(pods), preservedPodSha256=digest(pods))
    return audit
