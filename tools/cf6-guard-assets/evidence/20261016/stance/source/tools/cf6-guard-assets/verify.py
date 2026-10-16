"""Read-only registration, native identity and published RSL verification."""
from pathlib import Path
import argparse
import json
import struct
import subprocess
import sys
import zipfile
import zlib
from lxml import etree as E
import build


def linkage_records(path):
    raw = path.read_bytes()
    if raw[:3] not in (b'CWS', b'FWS'):
        raise ValueError('Expected AVM1 Flash SWF: ' + str(path))
    body = zlib.decompress(raw[8:]) if raw[:3] == b'CWS' else raw[8:]
    if len(body) + 8 != struct.unpack_from('<I', raw, 4)[0]:
        raise ValueError('SWF length mismatch')
    pos = (5 + (body[0] >> 3) * 4 + 7) // 8 + 4
    exports, imports = [], []
    while pos + 2 <= len(body):
        header = struct.unpack_from('<H', body, pos)[0]
        pos += 2
        code, size = header >> 6, header & 63
        if size == 63:
            size = struct.unpack_from('<I', body, pos)[0]
            pos += 4
        payload = body[pos:pos + size]
        if len(payload) != size:
            raise ValueError('Truncated SWF tag')
        pos += size
        if code == 0:
            return exports, imports
        if code not in (56, 57, 71):
            continue
        offset, url = 0, None
        if code != 56:
            end = payload.index(0)
            url = payload[:end].decode('utf8')
            offset = end + 1 + (2 if code == 71 else 0)
        count = struct.unpack_from('<H', payload, offset)[0]
        offset += 2
        names = []
        for _ in range(count):
            offset += 2
            end = payload.index(0, offset)
            names.append(payload[offset:end].decode('utf8'))
            offset = end + 1
        if offset != len(payload):
            raise ValueError('Invalid RSL record length')
        if code == 56:
            exports.extend(names)
        else:
            imports.append({'url': url, 'names': names})
    raise ValueError('SWF End tag missing')


def verify_body_timelines(path, scanner):
    """Reject CS6's one-frame placeholders in either exported actor root."""
    raw = path.read_bytes()
    body = zlib.decompress(raw[8:]) if raw[:3]==b'CWS' else raw[8:]
    def tags(data,start):
        pos=start
        while pos+2<=len(data):
            header=struct.unpack_from('<H',data,pos)[0];pos+=2
            code,size=header>>6,header&63
            if size==63:
                size=struct.unpack_from('<I',data,pos)[0];pos+=4
            payload=data[pos:pos+size];pos+=size
            assert len(payload)==size
            if code==0:return
            yield code,payload
    sprites,exports={},{}
    for code,data in tags(body,(5+(body[0]>>3)*4+7)//8+4):
        if code==39:sprites[struct.unpack_from('<H',data)[0]]=data
        elif code==56:
            pos=2
            for _ in range(struct.unpack_from('<H',data)[0]):
                cid=struct.unpack_from('<H',data,pos)[0]
                name,pos=scanner.read_string(data,pos+2);exports[name]=cid
    checked={}
    for link in (build.LINKAGE,):
        xml=E.parse(str(build.OWNER/'LIBRARY'/(build.PREFIX+link+'.xml')))
        expected={}
        for frame in xml.findall('.//x:DOMLayer[@name="动作"]/x:frames/x:DOMFrame',build.NS):
            item=frame.find('x:elements/x:DOMSymbolInstance[@name="man"]',build.NS)
            if item is None:continue
            child=E.parse(str(build.OWNER/'LIBRARY'/(item.get('libraryItemName')+'.xml')))
            expected[int(frame.get('index'))+1]=max(int(f.get('index'))+int(f.get('duration','1'))
                for f in child.findall('.//x:DOMFrame',build.NS))
        active,actual={},{};number=1
        for code,data in tags(sprites[exports[link]],4):
            if code==28:active.pop(struct.unpack_from('<H',data)[0],None)
            elif code in (26,70):
                bits=scanner.Bits(data);flags=bits.u(8);flags2=bits.u(8) if code==70 else 0
                depth=struct.unpack_from('<H',data,bits.byte)[0];bits.byte+=2
                if code==70 and (flags2&8 or flags2&16 and flags&2):
                    _,bits.byte=scanner.read_string(data,bits.byte)
                state=dict(active.get(depth,{})) if flags&1 else {}
                if flags&2:
                    state['id']=struct.unpack_from('<H',data,bits.byte)[0];bits.byte+=2
                if flags&4:scanner.skip_matrix(bits)
                if flags&8:scanner.skip_cxform(bits,True)
                if flags&16:bits.byte+=2
                if flags&32:state['name'],bits.byte=scanner.read_string(data,bits.byte)
                active[depth]=state
            elif code==1:
                bodies=[v for v in active.values() if v.get('name')=='man']
                if bodies:
                    assert len(bodies)==1
                    actual[number]=struct.unpack_from('<H',sprites[bodies[0]['id']],2)[0]
                number+=1
        assert all(actual.get(frame)==count for frame,count in expected.items()), (link,expected,actual)
        checked[link]=len(expected)
    return checked


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--runtime-root', type=Path, default=build.ROOT,
        help='Owned frozen combat checkout; the tested Guard SWF must match the editable source checkout')
    args = parser.parse_args()
    build.check()
    subprocess.run([sys.executable, '-X', 'utf8', '-B', str(build.HERE / 'balance.py')], check=True)
    relative = 'flashswf/arts/new/' + build.ANCHOR + '.swf'
    swf = build.ROOT / relative
    exports, imports = linkage_records(swf)
    assert set(exports) == {build.LINKAGE, build.ANCHOR} and len(exports) == 2
    assert not imports, 'Independent Guard library unexpectedly imports another RSL'
    _, shared = linkage_records(build.ROOT / 'flashswf/arts/things-new.swf')
    matching = [r for r in shared if build.ANCHOR in r['names']]
    assert len(matching) == 1 and matching[0]['url'] == relative
    source_map = E.parse(str(build.ROOT / 'data/items/asset_source_map.xml')).getroot()
    matching = [r for r in source_map if r.get('id') == build.LINKAGE]
    assert len(matching) == 1 and matching[0].get('swf') == relative
    with zipfile.ZipFile(build.ROOT / 'flashswf/arts/things-new.fla') as archive:
        declaration = E.fromstring(archive.read('LIBRARY/' + build.ANCHOR + '.xml'))
        assert declaration.get('linkageImportForRS') == 'true'
        assert declaration.get('linkageURL') == relative
        entry = E.fromstring(archive.read('LIBRARY/things-new.xml'))
        instances = entry.findall('.//x:DOMFrame[@index="3"]//x:DOMSymbolInstance', build.NS)
        assert sum(r.get('libraryItemName') == build.ANCHOR for r in instances) == 1
    for path in [build.HERE / 'GuardAI.as', build.ROOT / 'scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6GuardAssetTest.as']:
        assert path.read_bytes().startswith(b'\xef\xbb\xbf'), 'AS2 file must retain UTF-8 BOM: ' + str(path)
    scanner = build.module('manman_swfscan', build.ROOT / 'tools/swf-audit/swfscan.py')
    pixels = scanner.scan(swf)
    body_checks = verify_body_timelines(swf,scanner)
    assert pixels['bitmaps'] == 0 and pixels['shapes'] > 0
    runtime_root = args.runtime_root.resolve()
    assert build.sha(runtime_root / relative) == build.sha(swf), 'Frozen combat asset differs from the source checkout'
    subprocess.run(['node', str(build.ROOT / 'tools/audit-as2-class-embedding.js'), '--root', str(runtime_root),
        '--swf', relative], cwd=build.ROOT, check=True)
    print(json.dumps({'ok': True, 'sourceSwf': relative, 'sha256': build.sha(swf),
        'bytes': pixels['bytes'], 'shapes': pixels['shapes'], 'sprites': pixels['sprites'],
        'bitmaps': pixels['bitmaps'], 'exports': exports, 'sharedImport': matching[0].get('swf'),
        'runtimeOwnershipRoot': str(runtime_root),'bodyTimelineChecks':body_checks}, ensure_ascii=False))


if __name__ == '__main__':
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf8')
    main()
