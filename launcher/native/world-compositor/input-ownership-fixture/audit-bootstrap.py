"""Inspect compiled bootstrap/link identity, not C1 interaction acceptance."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import zlib

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]

def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()

def tags(path):
    raw = path.read_bytes()
    if raw[:3] == b'CWS': body = zlib.decompress(raw[8:])
    elif raw[:3] == b'FWS': body = raw[8:]
    else: raise ValueError('Unsupported bootstrap SWF')
    if len(body) + 8 != struct.unpack_from('<I',raw,4)[0]: raise ValueError('SWF length mismatch')
    position = (5 + (body[0] >> 3) * 4 + 7) // 8 + 4
    result = []
    while position < len(body):
        header, = struct.unpack_from('<H', body, position); position += 2
        code, size = header >> 6, header & 63
        if size == 63: size, = struct.unpack_from('<I', body, position); position += 4
        if position + size > len(body): raise ValueError('Truncated SWF tag')
        result.append(code); position += size
        if code == 0: break
    return result

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('module_index', type=Path, help='fresh FFDec -dumpAS2 output for C1Island.swf')
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    bootstrap = HERE / 'C1Bootstrap.swf'; module = HERE / 'C1Island.swf'
    codes = tags(bootstrap)
    assert codes.count(12) == 1 and not set(codes).intersection({39,57,59,71,76,82}), 'Bootstrap contains a class/import/sprite before its policy frame'
    entry = (HERE / 'bootstrap/C1Bootstrap.as').read_text(encoding='utf-8-sig')
    assert entry.index('ASSetPropFlags(_global,') < entry.index('island.loadMovie("C1Island.swf")')
    assert entry.count('.loadMovie(') == 1 and '_lockroot = true' in entry
    classes = sorted(set(re.findall(r'exp: __Packages\.([^)]*)\)', args.module_index.read_text(encoding='utf-8-sig'))))
    assert 'org.flashNight.arki.input.IsolatedInputPolicy' in classes
    rows = []
    for name in classes:
        source = ROOT / 'scripts/类定义' / (name.replace('.', '/') + '.as')
        rows.append({'class':name,'source':source.relative_to(ROOT).as_posix() if source.is_file() else None,
                     'sha256':digest(source) if source.is_file() else None})
    drivers = {
        'arki/key/KeyManager.as': 'if (_root.keyPollMC == undefined)',
        'neur/Timer/FrameTimer.as': 'var insName:String',
        'neur/ScheduleTimer/CooldownWheel.as': 'var depth:Number = _root.getNextHighestDepth()',
        'arki/render/VectorAfterimageRenderer.as': 'initCanvasPool();',
    }
    checks = []
    for relative, construction in drivers.items():
        source = ROOT / 'scripts/类定义/org/flashNight' / relative
        text = source.read_text(encoding='utf-8-sig')
        guarded = text.index('IsolatedInputPolicy.forbidsLegacyDrivers()') < text.index(construction)
        assert guarded, relative
        checks.append({'source':source.relative_to(ROOT).as_posix(),'sha256':digest(source),'guardPrecedesConstruction':True})
    output = {'kind':'compiled bootstrap and known driver-constructor audit; not full cancellation/input acceptance',
              'bootstrapSha256':digest(bootstrap),'moduleSha256':digest(module),'bootstrapDoAction':codes.count(12),
              'bootstrapDoInitAction':codes.count(59),'classCount':len(rows),'classes':rows,'knownDriverGuards':checks,
              'C1Acceptance':False,'physicalInputHandoffVerified':False}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, ensure_ascii=False, indent=2)+'\n',encoding='utf-8')
    print(f'Bootstrap has no class initializers; {len(rows)} linked module classes indexed; {len(checks)} constructor guards checked')

if __name__ == '__main__': main()
