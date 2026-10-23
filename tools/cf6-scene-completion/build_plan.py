"""Candidate traversal and A07 inputs. Does not activate a production chapter."""
from pathlib import Path
import argparse
import hashlib
import json

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def build():
    original = read(HERE/'source-evidence/original.json')
    chapter = read(ROOT/'data/stages/books/cf6-sting.json')
    maps = {row['id']: row for row in chapter['maps']}
    records = []
    for map_id, sprite, depth, mode, next_map in [
            ('A03', 1720, 28, 'depart', 'A04'),
            ('A04', 1729, 96, 'arrive', None),
            ('A04', 1720, 28, 'depart', 'A05'),
            ('A05', 1729, 26, 'arrive', None),
            ('A05', 1750, 88, 'depart', 'A06')]:
        place = next(p for p in original['worlds'][map_id]['placements'] if p['depth'] == depth)
        assert place['id'] == sprite and place['matrix'][:4] == [1, 0, 0, 1]
        # Existing assembler owns the actual native origin/viewport policy.
        # Keep source-local motion here; the future adapter must transform once.
        timeline = original['timelines'][str(sprite)]
        actor_frames = [r for r in timeline['frames'] if r['actorFootAnchor']]
        first = actor_frames[0]['actorFootAnchor']
        samples = []
        previous = first
        for row in timeline['frames']:
            anchor = row['actorFootAnchor']
            moving = anchor is not None and abs(anchor[0]-previous[0])+abs(anchor[1]-previous[1]) > .05
            samples.append({'frame': row['frame'], 'visible': anchor is not None,
                            'x': anchor[0] if anchor else previous[0],
                            'z': anchor[1] if anchor else previous[1],
                            'action': 'walk' if moving else 'stand'})
            if anchor:
                previous = anchor
        records.append({'id': f'{map_id}-{mode}', 'mapId': map_id, 'mode': mode,
                        'sourceSprite': sprite, 'sourceDepth': depth,
                        'sourcePlacement': place['matrix'],
                        'coordinateSpace': 'original symbol local; no viewport multiplier applied',
                        'durationFrames': timeline['frameCount'], 'fps': 30,
                        'actorReleaseFrame': 122 if sprite == 1729 else None,
                        'trigger': 'scene-ready' if mode == 'arrive' else 'cleared-and-player-at-authored-gate',
                        'terminal': 'restore-control' if mode == 'arrive' else 'request-standard-next-stage',
                        'nextMap': next_map, 'samples': samples,
                        'actorPolicy': 'reuse live CF7 appearance and walk/stand; original body shapes are reference only',
                        'art': {'back': f'CF6_Traversal{sprite}_Back', 'front': f'CF6_Traversal{sprite}_Front',
                                'mask': f'CF6_Traversal{sprite}_Mask' if sprite in (1720,1729) else None},
                        'status': 'candidate; foot anchor/depth/collision and frame pacing require native validation'})
    lifts = []
    for before, lift, after in [('A09', 'A10', 'A11'), ('A12', 'A13', 'A14')]:
        lifts.append({'id': lift, 'beforeMap': before, 'afterMap': after,
                      'rules': {'mapId':lift, 'closeFrames':24, 'stopFrames':30, 'openFrames':24, 'scrollFrames':37},
                      'timingBasis': 'gate/stop timing inherited from existing CF7 mechanism; not claimed as original boarding animation timing',
                      'existingLayers': maps[lift]['mechanism']['layers'],
                      'originalScrollSprite': 1876, 'originalScrollFrames': 37,
                      'originalClearMonitor': 1587, 'originalExitFrames': 59,
                      'sequence': ['walk-onto-platform', 'close-gate', 'combat-travel',
                                   'stop-at-floor', 'open-gate', 'walk-off-platform', 'restore-control'],
                      'adaptation': 'continuous actor boarding/alighting is new CF7 staging around the original room cut; not claimed as recovered original choreography',
                      'needs': ['platform/gate anchor and clipping against actual scaled map',
                                'direction and loop seam in actual Flash', 'original encounter completion authority retained'],
                      'completion': 'actual existing StageManager clear; never elapsed-time victory'})
    vehicle = {
        'mapId': 'A07', 'fps': 30, 'originalWorld': 1816,
        'playerSprite': 1803, 'playerFrames': 29,
        'roadSprite': 1791, 'roadFrames': 49,
        'bossSprite': 1813, 'bossFrames': 209, 'bossLoopFrames': 120,
        'bossThrowFrame': 19, 'bossDeathFirstFrame': 121, 'bossExitFrame': 208,
        'roadKillThreshold': 30, 'roadToBossFrames': 59,
        'fireIntervalMs': 150, 'barrels': 2, 'originalProjectilePower': 20,
        'originalProjectileSpeed': 20, 'originalBossHp': 5000,
        'hazardStepPerFrame': 20,
        'roadSpawnBudgets': [200, 15, 200], 'roadSpawnConcurrency': [1, 1, 1],
        'budgetNote': 'original remaining-death generator budgets; not a promise of 415 kills; progress uses 30 final deaths',
        'tail': {'guard612': 2, 'shield629': 5, 'obstacle627': 2,
                 'completion': 'actual tail trigger reached; no timed auto-clear'},
        'phases': ['road', 'boss-intro', 'boss', 'boss-death', 'tail', 'complete'],
        'route': ['A06', 'cf6-s4', 'A07', 'cf6-s5', 'A08'],
        'economy': {'relocateGold': 40000, 'from': 'A08', 'to': 'A07',
                    'policy': 'one existing chapter allowance; no direct legacy kill-money writes',
                    'currentProductionUnchanged': True},
        'healthPolicy': 'adapter receives current chapter actor health; separate vehicle durability is not invented',
        'balance': 'original constants are reference inputs, not accepted CF7 difficulty',
        'needs': ['player wheel/gun/fire/death animation assembly from A08 art',
                  'damage/death authority adapter, dedicated collision variants',
                  'stage/actor input takeover and exact scene/run cancellation',
                  'route ID compatibility and all shifted story indices', 'actual CS6/game validation']}
    source = ROOT/'flashswf/arts/new/Codex素材源稿/CF6地图'
    art_paths = [source/'A07-R2/cf6-stage7-redraw-r2/source/armored_vehicle.py',
                 source/'A07-R2/cf6-stage7-redraw-r2/reference/environment-original-nodes.json',
                 source/'A08-R5/parts/bitmap-1823.svg']
    manifest = {'schema': 'cf6-scene-completion-plan.v1',
                'status': 'source reference plan; production bindings live in scene-assembly.py; A07 remains preparation-only',
                'originalSha256': original['swfSha256'],
                'evidenceSha256': hashlib.sha256((HERE/'source-evidence/original.json').read_bytes()).hexdigest(),
                'productionChapterSha256': hashlib.sha256((ROOT/'data/stages/books/cf6-sting.json').read_bytes()).hexdigest(),
                'traversals': records, 'elevators': lifts, 'vehicle': vehicle,
                'reuse': [{'path': p.relative_to(ROOT).as_posix(), 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()} for p in art_paths]}
    return (json.dumps(manifest, ensure_ascii=False, indent=2)+'\n').encode('utf-8')


if __name__ == '__main__':
    p = argparse.ArgumentParser();p.add_argument('--check', action='store_true');args = p.parse_args()
    path = HERE/'completion-plan.json';data = build()
    if args.check:
        if path.read_bytes() != data: raise ValueError('stale completion plan')
    else:
        path.write_bytes(data)
    print('checked' if args.check else 'built', '5 authored door references, 2 elevators, A07 preparation; this tool does not write the production chapter')
