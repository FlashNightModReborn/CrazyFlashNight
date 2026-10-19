"""Verify Phoenix source/RSL identities and an optional fresh focused trace."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import struct
import subprocess
import sys
import zlib
from lxml import etree as E
import build


def swf(path):
    raw = path.read_bytes()
    assert raw[:3] in (b'FWS', b'CWS'), 'Unsupported or incomplete SWF'
    data = raw[:8] + zlib.decompress(raw[8:]) if raw[:3] == b'CWS' else raw
    assert len(data) == struct.unpack_from('<I', data, 4)[0], 'Incomplete SWF length'
    pos = 8 + (5 + 4*(data[8] >> 3) + 7)//8 + 4
    exports, sprites = {}, {}
    while pos < len(data)-1:
        header = struct.unpack_from('<H', data, pos)[0]
        pos += 2
        code, size = header >> 6, header & 63
        if size == 63:
            size = struct.unpack_from('<I', data, pos)[0]
            pos += 4
        body = data[pos:pos+size]
        assert len(body) == size, 'Truncated SWF tag'
        pos += size
        if code == 39:
            ident, frames = struct.unpack_from('<HH', body)
            sprites[ident] = frames
        elif code == 56:
            at = 2
            for _ in range(struct.unpack_from('<H', body)[0]):
                ident = struct.unpack_from('<H', body, at)[0]
                end = body.index(0, at+2)
                name = body[at+2:end].decode('utf-8')
                assert name not in exports, 'Duplicate linkage: '+name
                exports[name] = ident
                at = end+1
        elif code == 69:
            assert not (struct.unpack_from('<I', body)[0] & 8), 'AS3 resource in AS2 path'
        elif code == 0:
            break
    return data, exports, sprites


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--trace', type=Path)
    ap.add_argument('--report', type=Path)
    args = ap.parse_args()
    subprocess.run([sys.executable, str(build.HERE/'build.py'), '--check'], check=True)
    actor = build.ROOT/'flashswf/arts/things5/LIBRARY/敌人-粉红头发御姐.xml'
    tree = E.parse(str(actor))
    assert not tree.findall('.//x:DOMLayer[@name="变身图层"]', build.NS)
    scripts = '\n'.join(el.text or '' for el in tree.findall('.//x:script', build.NS))
    assert '_root.火凤阶段初始化(this)' in scripts
    assert '(_parent.hp <= 1500' not in scripts
    mapping = E.parse(str(build.ROOT/'data/items/asset_source_map.xml'))
    entries = mapping.findall('asset[@id="'+build.LINKAGE+'"]')
    assert len(entries) == 1 and entries[0].get('swf') == 'flashswf/arts/new/Codex专用素材.swf'
    paths = [actor, build.HERE/'build.py', build.HERE/'manifest.json', build.ARCHIVE,
             build.ROOT/'scripts/类定义/org/flashNight/arki/unit/UnitAI/Custom/PhoenixPhaseController.as',
             build.ROOT/'scripts/逻辑/单位函数/单位函数_lsy_敌人模板迁移.as',
             build.ROOT/'scripts/类定义/org/flashNight/arki/unit/UnitAI/Custom/PhoenixPhaseTest.as',
             build.ROOT/'scripts/run-phoenix-phase-tests.ps1',
             build.ROOT/'scripts/test-runners/phoenix-phase/TestLoader.as.template']
    report = {'scope': 'AS2 Phoenix phases and authored transitions; no native rendering', 'files': {}}
    report['evidenceBoundary'] = {
        'resources': 'real RSL imports in the focused Flash host',
        'controller': 'compiled into the focused host; production provider compiled separately',
        'asLoader': 'compiled and provider markers checked; not executed by the focused host',
        'standardEntryVerified': False, 'continuousStageRasterization': False}
    for relative in ['flashswf/arts/new/Codex专用素材.swf', 'flashswf/arts/things5.swf', 'scripts/asLoader.swf']:
        path = build.ROOT/relative
        data, exports, sprites = swf(path)
        if relative == 'scripts/asLoader.swf':
            assert b'PhoenixPhaseController' in data, 'Production asLoader lacks the controller'
            assert b'visualHeight' in data, 'Production asLoader lacks the restored vertical presentation'
            assert b'Missing Phoenix charge layer' in data, 'Production asLoader lacks the flame-led gentle lift'
            assert '火凤阶段初始化'.encode('utf-8') in data, 'Production boot lacks the facade'
        elif 'Codex专用素材' in exports:
            assert build.LINKAGE in exports and sprites[exports[build.LINKAGE]] == 182
        else:
            assert '敌人-粉红头发御姐' in exports
            assert '火凤阶段初始化'.encode('utf-8') in data
        paths.append(path)
    for path in paths:
        report['files'][path.relative_to(build.ROOT).as_posix()] = {
            'bytes': path.stat().st_size, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
    generated = list((build.OWNER/'LIBRARY/Codex/火凤转阶段').rglob('*.xml'))
    report['assembledArt'] = {'symbols': len(generated), 'xmlBytes': sum(p.stat().st_size for p in generated)}
    if args.trace:
        trace = args.trace.read_text(encoding='utf-8-sig')
        starts = re.findall(r'^FocusedTestRunId phoenix-phase Start: (\w+)\s*$', trace, re.M)
        ends = re.findall(r'^FocusedTestRunId phoenix-phase Complete: (\w+)\s*$', trace, re.M)
        assert len(starts) == 1 and starts == ends, 'Trace is not one complete run'
        assert re.findall(r'^PhoenixPhaseTest Tests Failed: (\d+)\s*$', trace, re.M) == ['0']
        passed = re.findall(r'^PhoenixPhaseTest Tests Passed: (\d+)\s*$', trace, re.M)
        assert len(passed) == 1 and int(passed[0]) > 0
        assert 'PhoenixPhaseTest Complete Transitions: 3' in trace
        for phase in ['phase-one', 'phase-two', 'phase-three', 'nirvana']:
            pattern = r'^PhoenixPhaseTest Behavior: '+phase+r' real chase both directions, depth, attacks, finish;[^\r\n]*\r?$'
            assert len(re.findall(pattern, trace, re.M)) == 1, 'Missing real combat regression: '+phase
        report['focusedRun'] = {'runId': starts[0], 'passed': int(passed[0]), 'failed': 0,
                                'traceSha256': hashlib.sha256(args.trace.read_bytes()).hexdigest()}
        motion = re.findall(r'^PhoenixPhaseTest Motion Captures: (\d+)\s*$', trace, re.M)
        if motion:
            assert motion == ['28'], 'Incomplete or duplicated motion capture'
            image_frames = [int(value) for value in re.findall(r'^\[ASSET_BITMAP_BEGIN\] phoenix-motion-(\d+) 180 240\s*$', trace, re.M)]
            assert image_frames == list(range(82, 137, 2)), 'Motion frames are not one complete ordered sequence'
            report['focusedRun']['motionFrames'] = image_frames
            report['focusedRun']['motionPreviewFps'] = 15
        test_swf = args.trace.parent/'PhoenixPhaseHost.swf'
        assert test_swf.is_file(), 'Keep the actual test SWF alongside the trace'
        report['focusedRun']['testSwfSha256'] = hashlib.sha256(test_swf.read_bytes()).hexdigest()
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print(json.dumps({'verified': True, 'art': report['assembledArt'], 'focusedRun': report.get('focusedRun')}, ensure_ascii=False))


if __name__ == '__main__':
    main()
