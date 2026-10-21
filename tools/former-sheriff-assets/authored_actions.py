"""Read the frozen artist timelines without importing Animate/AS3 settings.

Only explicit run-cycle and knife keys are consumed. Runtime gear, callbacks,
light ports, hit shapes and entry/return contracts remain owned by our builders.
"""
import copy
import hashlib
import json
from functools import lru_cache
from pathlib import Path
from lxml import etree as E

SOURCE = Path(__file__).resolve().parents[2] / 'flashswf/arts/new/Codex素材源稿/前治安官动作优化-20261020'
NS = {'x': 'http://ns.adobe.com/xfl/2008/'}


@lru_cache(maxsize=1)
def sources():
    manifest = json.loads((SOURCE / 'manifest.json').read_text('utf8'))
    assert hashlib.sha256((SOURCE / manifest['archive']).read_bytes()).hexdigest() == manifest['archiveSha256']
    result = {}
    for entry in manifest['actions']:
        path = SOURCE / entry['file']
        assert hashlib.sha256(path.read_bytes()).hexdigest() == entry['sha256'], path
        result[path.stem] = E.parse(str(path))
    return result


def pose(action, frame, api):
    """One-based source key -> matrices in unit space, using the owning rig."""
    result = {'parts': {}}
    for layer in sources()[action].findall('./x:timeline/x:DOMTimeline/x:layers/x:DOMLayer', NS):
        key = next((f for f in layer.findall('x:frames/x:DOMFrame', NS)
                    if int(f.get('index', '0')) <= frame - 1 < int(f.get('index', '0')) + int(f.get('duration', '1'))), None)
        if key is None:
            continue
        assert not key.get('tweenType') or int(key.get('index', '0')) == frame - 1, 'Only explicit authored keys are accepted'
        for inst in key.findall('x:elements/x:DOMSymbolInstance', NS):
            name = inst.get('name', '')
            if name != '盾具' and not name.startswith('肢体'):
                continue
            matrix = inst.find('x:matrix/x:Matrix', NS)
            local = tuple(float(matrix.get(k, str(v))) if matrix is not None else v
                          for k, v in zip(['a', 'b', 'c', 'd', 'tx', 'ty'], api.b.I))
            unit = api.b.writer.mul(api.CONTAINER, local)
            if name == '盾具':
                result['weapon'] = unit
            else:
                result['parts'][int(name[2:])] = unit
    assert len(result['parts']) == 15 and 'weapon' in result, (action, frame)
    return result


def run(base, source, api):
    """Retarget fixed source limbs to player holders, retaining accessory slots."""
    result = copy.deepcopy(base)
    shift = api.b.writer.mul(source['parts'][10], api.inverse(base['parts'][10]))
    result['parts'] = [source['parts'].get(i, api.b.writer.mul(shift, m))
                       for i, m in enumerate(base['parts'])]
    result['weapon'] = source['weapon']
    # Close rounded native registrations while preserving the artist's elbows.
    for ui, fi, hi in [(5, 6, 7), (14, 15, 16)]:
        grip = (36.346794, 158.801671) if hi == 7 else (13, 183)
        target = api.point(result['weapon'], grip)
        hand = result['parts'][hi]
        result['parts'][hi] = (*hand[:4], *target)
        shoulder = api.point(result['parts'][ui], (0, -47))
        elbow = api.point(result['parts'][ui], (0, 47))
        wrist = (target[0] - 2.6, target[1] + .5)
        result['parts'][ui] = api.limb(shoulder, elbow, -47, 47, .234)
        result['parts'][fi] = api.limb(elbow, wrist, -47, 47, .234)
    return result


def stab(frames, api):
    """Keep draw/stow ownership and exact blade/palm registration in AS2."""
    keys = [pose('持盾刺击', f + 1, api.s) for f in range(len(frames))]
    for f in range(8, 68):
        current = frames[f]
        source = keys[f]
        for i in [14, 15, 16]:
            if i == 16 and f in [8, 67]:
                continue  # Exact existing waist socket at weapon handoff.
            current['parts'][i] = source['parts'][i]
        hand = current['parts'][16]
        shoulder = api.s.point(current['parts'][14], (0, -47))
        elbow = api.s.point(current['parts'][14], (0, 47))
        if 10 <= f <= 20:
            # The source draw has a 30-unit one-frame reversal. Smooth only
            # this transfer, leaving all three authored strike keys intact.
            total = 0
            elbow = [0., 0.]
            for offset, weight in [(-2, 1), (-1, 2), (0, 3), (1, 2), (2, 1)]:
                key = keys[f + offset]['parts']
                hand = key[16] if total == 0 else api.s.tween(hand, key[16], weight / (total + weight))
                at = api.s.point(key[14], (0, 47))
                elbow = [elbow[i] + at[i] * weight for i in range(2)]
                total += weight
            elbow = tuple(x / total for x in elbow)
            current['parts'][16] = hand
        wrist = api.s.point(hand, api.KNIFE_WRIST)
        current['parts'][14] = api.s.limb(shoulder, elbow, -47, 47, .234)
        current['parts'][15] = api.s.limb(elbow, wrist, -47, 47, .234)
        current['right'] = hand[4:]
        current['prop'] = api.b.writer.mul(hand, (1, 0, 0, 1, *api.KNIFE_GRIP))
