"""Pinned CF6 vehicle display closure; never executes legacy AS or writes a SWF."""
from pathlib import Path
import argparse
import copy
import hashlib
import importlib.util
import json
import re
import struct
import subprocess
import zlib

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
ORIGINAL = ROOT / 'flashswf/arts/new/Codex素材源稿/CF6地图/原作参考/crazyflasher6-cn.swf'
EXPECTED = 'b52af10e2dda43332e0b2ffb9549d2fad474f298b9f6c67d848ffc33ff589b01'
ROOTS = {'world': 1816, 'sky': 1754, 'road': 1791, 'player': 1803, 'boss': 1813,
         'grenade': 361, 'raider': 612, 'obstacle': 627, 'shield': 629,
         'bullet':356,'spark':115,'explosion':391}
JAVA = Path('C:/Program Files/Adobe/Adobe Animate 2024/jre/bin/java.exe')


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def encoded(value):
    return (json.dumps(value, ensure_ascii=False, indent=2) + '\n').encode('utf-8')


def parse():
    geometry = module('vehicle_geometry', ROOT / 'tools/cf6-map-runtime/extract-geometry.py')
    raw = ORIGINAL.read_bytes()
    if sha(raw) != EXPECTED:
        raise ValueError('original vehicle evidence identity mismatch')
    data = zlib.decompress(raw[8:]) if raw[:3] == b'CWS' else raw[8:]
    _, pos = geometry.rect(data, 0)
    nodes = {}

    def place(at, code, display, frame):
        flags = data[at]
        at += 1
        flags2 = 0
        if code == 70:
            flags2 = data[at]
            at += 1
        depth = struct.unpack_from('<H', data, at)[0]
        at += 2
        if code == 70 and (flags2 & 8 or flags2 & 16 and flags & 2):
            _, at = geometry.swf.read_string(data, at)
        row = copy.deepcopy(display.get(depth, {})) if flags & 1 else {}
        if flags & 2:
            cid = struct.unpack_from('<H', data, at)[0]
            at += 2
            if row.get('id') != cid:
                row['placedAt'] = frame
            row['id'] = cid
        row.setdefault('placedAt', frame)
        if flags & 4:
            row['matrix'], at = geometry.matrix(data, at)
        row.setdefault('matrix', [1, 0, 0, 1, 0, 0])
        if flags & 8:
            bits = geometry.swf.Bits(data, at)
            has_add, has_mult, length = bits.u(1), bits.u(1), bits.u(4)
            row['colorMult'] = [bits.s(length) for _ in range(4)] if has_mult else [256] * 4
            row['colorAdd'] = [bits.s(length) for _ in range(4)] if has_add else [0] * 4
            bits.align()
            at = bits.byte
        if flags & 16:
            row['ratio'] = struct.unpack_from('<H', data, at)[0]
            at += 2
        if flags & 32:
            row['name'], at = geometry.swf.read_string(data, at)
        if flags & 64:
            row['clipDepth'] = struct.unpack_from('<H', data, at)[0]
        display[depth] = row

    def timeline(start, end):
        frames, labels, display = [], {}, {}
        at = start
        while at < end:
            tag = struct.unpack_from('<H', data, at)[0]
            at += 2
            code, size = tag >> 6, tag & 63
            if size == 63:
                size = struct.unpack_from('<I', data, at)[0]
                at += 4
            payload, at = at, at + size
            if code == 0:
                break
            if code == 39:
                cid, declared = struct.unpack_from('<HH', data, payload)
                nested, nested_labels = timeline(payload + 4, at)
                if len(nested) != declared:
                    raise ValueError('original sprite frame count mismatch ' + str(cid))
                nodes[cid] = {'id': cid, 'code': code, 'frames': nested, 'labels': nested_labels}
            elif code in (2, 22, 32, 83, 46, 84, 11, 33, 37):
                cid = struct.unpack_from('<H', data, payload)[0]
                bounds, _ = geometry.rect(data, payload + 2)
                nodes[cid] = {'id': cid, 'code': code, 'bounds': bounds}
            elif code in (26, 70):
                place(payload, code, display, len(frames) + 1)
            elif code == 28:
                display.pop(struct.unpack_from('<H', data, payload)[0], None)
            elif code == 5:
                display.pop(struct.unpack_from('<H', data, payload + 2)[0], None)
            elif code == 43:
                label, _ = geometry.swf.read_string(data, payload)
                labels[label] = len(frames) + 1
            elif code == 1:
                frames.append(copy.deepcopy(display))
        return frames, labels

    timeline(pos + 4, len(data))
    closure = set()

    def visit(cid):
        if cid in closure:
            return
        if cid not in nodes:
            raise ValueError('unsupported source display node ' + str(cid))
        closure.add(cid)
        for frame in nodes[cid].get('frames', []):
            for row in frame.values():
                visit(row['id'])

    for cid in ROOTS.values():
        visit(cid)
    return {'schema': 'cf6-vehicle-source.v1', 'originalSha256': EXPECTED, 'roots': ROOTS,
            'nodes': {str(cid): nodes[cid] for cid in sorted(closure)}}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--export', action='store_true')
    parser.add_argument('--scripts', action='store_true')
    parser.add_argument('--capture-scripts', action='store_true')
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    source = parse()
    target = HERE / 'source/original-nodes.json'
    if args.check:
        if target.read_bytes() != encoded(source):
            raise ValueError('stale original vehicle closure')
    else:
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(encoded(source))
    leaves = [cid for cid, node in source['nodes'].items() if node['code'] in (2, 22, 32, 83)]
    if args.export:
        if args.check:
            raise ValueError('--check cannot export')
        output = HERE / 'source/ffdec'
        subprocess.run([str(JAVA), '-Djava.awt.headless=true', '-jar', str(ROOT/'tools/ffdec/ffdec.jar'),
            '-onerror', 'abort', '-selectid', ','.join(leaves), '-format', 'shape:svg',
            '-export', 'shape', str(output), str(ORIGINAL)], check=True)
    if args.scripts or args.capture_scripts:
        if args.check:
            raise ValueError('--check cannot export scripts')
        output = ROOT / 'tmp/cf6-fieldfix4-20261024/vehicle/readable-script-export'
        if args.scripts:
            subprocess.run([str(JAVA), '-Djava.awt.headless=true', '-jar', str(ROOT/'tools/ffdec/ffdec.jar'),
                '-onerror', 'abort', '-config', 'autoDeobfuscate=true',
                '-selectid', ','.join(source['nodes']), '-format', 'script:as',
                '-export', 'script', str(output), str(ORIGINAL)], check=True)
        output = Path('\\\\?\\' + str(output.resolve())) if output.resolve().drive else output.resolve()
        records = []
        script_root = HERE / 'source/actions'
        script_root.mkdir(parents=True, exist_ok=True)
        for path in sorted(output.rglob('*.as')):
            relative = path.relative_to(output).as_posix()
            match = re.search(r'(?:^|/)DefineSprite_(\d+)(?:/|_)', relative)
            if not match or match.group(1) not in source['nodes']:
                continue
            raw = path.read_bytes()
            target = script_root / (sha(raw) + '.as.txt')
            target.write_bytes(raw)
            records.append({'originalPath': relative,
                            'capture': target.relative_to(HERE).as_posix(), 'sha256': sha(raw)})
        (HERE / 'source/actions.json').write_bytes(encoded(records))
    print(json.dumps({'nodes': len(source['nodes']), 'shapes': len(leaves),
                      'rootFrames': {key: len(source['nodes'][str(cid)].get('frames', [{}])) for key, cid in ROOTS.items()}}))


if __name__ == '__main__':
    main()
