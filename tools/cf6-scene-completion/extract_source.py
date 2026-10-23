"""Read original CF6 evidence. Never executes legacy AS or starts Flash.

The small captured facts are reproducible from the pinned original SWF and the
existing FFDec text export. They are not a runtime or an editable asset source.
"""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import re

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
ORIGINAL_SHA = 'b52af10e2dda43332e0b2ffb9549d2fad474f298b9f6c67d848ffc33ff589b01'
ROOTS = [1430, 1587, 1714, 1720, 1729, 1750, 1791, 1800, 1801, 1803,
         1805, 1810, 1813, 1816, 1832, 1862, 1876, 1885, 1920]
SCRIPT_ROOTS = ROOTS + [361, 612, 627, 629, 1869, 1917]
WORLDS = {'A03': 1723, 'A04': 1737, 'A05': 1752, 'A07': 1816,
          'A09': 1869, 'A10': 1885, 'A11': 1910, 'A12': 1917,
          'A13': 1920, 'A14': 1927}


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


def encoded(value):
    return (json.dumps(value, ensure_ascii=False, indent=2) + '\n').encode('utf-8')


def sha(data):
    return hashlib.sha256(data).hexdigest()


def long_path(path):
    resolved = path.resolve()
    return Path('\\\\?\\' + str(resolved)) if resolved.drive else resolved


def foot_anchor(frame, shapes):
    """Derived geometric foot anchor; keeps reference geometry separate from CF7 poses."""
    feet = []
    for row in frame:
        if row.get('id') != 1021:
            continue
        a, b, c, d, x, y = row['matrix']
        lo_x, lo_y, hi_x, hi_y = shapes[1021]['bounds']
        points = [(a*u+c*v+x, b*u+d*v+y)
                  for u in (lo_x, hi_x) for v in (lo_y, hi_y)]
        feet.append([(min(p[0] for p in points)+max(p[0] for p in points))/2,
                     max(p[1] for p in points)])
    if not feet:
        return None
    return [round(sum(p[0] for p in feet)/len(feet), 5),
            round(max(p[1] for p in feet), 5)]


def extract(swf_path, scripts, check=False):
    geom = module('cf6_completion_geometry', ROOT/'tools/cf6-map-runtime/extract-geometry.py')
    digest, frames, sprites, shapes = geom.parse(swf_path)
    if digest != ORIGINAL_SHA:
        raise ValueError('Original SWF identity mismatch')
    scripts = long_path(scripts)
    outputs = {}
    actions = []
    paths = set()
    for sprite in SCRIPT_ROOTS:
        paths.update(scripts.glob('DefineSprite_' + str(sprite) + '/**/*.as'))
        paths.update(scripts.glob('DefineSprite_' + str(sprite) + '_*/**/*.as'))
    for frame in [12, 104, 131, 148]:
        paths.update(scripts.glob('frame_' + str(frame) + '/**/*.as'))
    for path in sorted(paths):
        raw = path.read_bytes()
        text = raw.decode('utf-8-sig')
        relative = path.relative_to(scripts).as_posix()
        # Keep exact bytes in a hash-addressed non-executable text record.
        key = sha(raw)
        target = 'source-evidence/actions/' + key + '.as.txt'
        outputs[target] = raw
        actions.append({'originalPath': relative, 'sha256': key,
                        'capture': target, 'bytes': len(raw),
                        'timelineFrame': int(re.search(r'frame_(\d+)', relative).group(1)),
                        'businessCues': [line.strip() for line in text.splitlines()
                                         if any(word in line for word in ['man1.goto', '目标帧', '需要杀死数',
                                             '主角hp', 'hp = ', '电梯死亡敌人计数', '汽车_子弹', 'setInterval',
                                             '战车手雷', 'gotoAndPlay(', 'gotoAndStop('])]})
    timelines = {}
    for sprite in ROOTS:
        source = sprites[sprite]
        timeline = []
        for number, frame in enumerate(source, 1):
            actor = [r for r in frame if 1013 <= r.get('id', -1) <= 1025]
            timeline.append({'frame': number, 'placements': frame,
                             'actorFootAnchor': foot_anchor(frame, shapes),
                             'actorDepth': [min(r['depth'] for r in actor), max(r['depth'] for r in actor)] if actor else None})
        timelines[str(sprite)] = {'frameCount': len(source), 'frames': timeline}
    placements = {}
    for name, sprite in WORLDS.items():
        placements[name] = {'worldSprite': sprite, 'placements': sprites[sprite][0]}
    result = {'schema': 'cf6-scene-original-evidence.v1', 'swfSha256': digest,
              'fps': 30, 'mainFrameCount': len(frames),
              'extractorSha256': sha(Path(__file__).read_bytes()),
              'geometryParserSha256': sha((ROOT/'tools/cf6-map-runtime/extract-geometry.py').read_bytes()),
              'shapeParserSha256': sha((ROOT/'tools/swf-audit/swfscan.py').read_bytes()),
              'scope': 'static original matrices and action text; not executed AVM1; color/masks are supplied by archived visual nodes',
              'footAnchorBasis': 'derived from transformed bounds of original shoe shape 1021; reference trajectory only, not CF7 actor collision or exact foot contact',
              'worlds': placements, 'timelines': timelines, 'actions': actions}
    outputs['source-evidence/original.json'] = encoded(result)
    for name, content in outputs.items():
        target = HERE/name
        if check:
            if not target.is_file() or target.read_bytes() != content:
                raise ValueError('stale source capture: ' + name)
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(content)
    actual = {p.relative_to(HERE).as_posix() for p in (HERE/'source-evidence').rglob('*') if p.is_file()}
    if actual != set(outputs):
        raise ValueError('Unexpected source capture files; preserve and inspect before rebuilding')
    print(json.dumps({'state': 'source_captured', 'timelines': len(timelines),
                      'actionFiles': len(actions), 'uniqueActionFiles': len(outputs)-1,
                      'bytes': sum(len(v) for v in outputs.values())}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--swf', type=Path, required=True)
    parser.add_argument('--scripts', type=Path, required=True)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    extract(args.swf, args.scripts, args.check)
