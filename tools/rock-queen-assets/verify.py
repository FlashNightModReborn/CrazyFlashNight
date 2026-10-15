"""只读核对摇滚女皇导出与实际打包依赖，不接管旧库的无关孤儿文件。"""
import json
import argparse
import hashlib
import struct
import zlib
import math
from pathlib import Path
from collections import defaultdict
from lxml import etree as E
import build as b
import timing

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--swf', action='store_true', help='同时回读原生 SWF 导出与帧数')
    args = parser.parse_args()
    dom = E.parse(str(b.DEST / 'DOMDocument.xml'))
    included = {}
    exports = defaultdict(list)
    for include in dom.findall('./x:symbols/x:Include', b.NS):
        path = b.DEST / 'LIBRARY' / include.get('href')
        assert path.exists(), path
        node = E.parse(str(path)).getroot()
        included[node.get('name')] = node
        if node.get('linkageExportForAS') == 'true':
            exports[node.get('linkageIdentifier')].append(node.get('name'))
    manifest = json.loads((Path(__file__).parent / 'manifest.json').read_text('utf-8'))
    own = {n for n in included if n.startswith(b.PREFIX)}
    assert len(own) == manifest['symbols'] == 125
    assert len(manifest['clips']) == 14 and manifest['totalFrames'] == 1097
    seen = set()
    def visit(name):
        if name in seen: return
        seen.add(name)
        assert name in included, 'missing packed dependency: ' + name
        node = included[name]
        for inst in node.findall('.//x:DOMSymbolInstance', b.NS):
            visit(inst.get('libraryItemName'))
    for clip in manifest['clips']:
        name = b.PREFIX + clip['linkage']
        assert exports[clip['linkage']] == [name], 'ambiguous export: ' + clip['linkage']
        node = included[name]
        visit(name)
        protocol = node.find('.//x:DOMLayer[@name="战技协议"]/x:frames', b.NS)
        assert len(protocol) == clip['frames']
        for at, fr in enumerate(protocol):
            assert int(fr.get('index')) == at
            code = fr.findtext('./x:Actionscript/x:script', namespaces=b.NS)
            assert '"%s", %d, %d,' % (clip['id'], at+1, clip['sourceFrames'][at]) in code
        assert len(node.findall('.//x:DOMSymbolInstance[@name="rockWeapon"]', b.NS)) == clip['frames']
        shadow = node.find('.//x:DOMSymbolInstance[@name="rockShadow"]', b.NS)
        assert shadow is not None and shadow.get('libraryItemName') == '主角肢体素材/Symbol 3'
        assert '_root.是否阴影' in shadow.findtext('./x:Actionscript/x:script', namespaces=b.NS)
        assert int(shadow.getparent().getparent().get('duration')) == clip['frames']
        if clip['timing']:
            pose_roles=timing.roles(clip['id'])
            neutral=timing.neutral_pose(b.DEST/'LIBRARY',clip['id'])
            for role,slot in pose_roles.items():
                nodes=node.findall('.//x:DOMSymbolInstance[@name="'+slot+'"]',b.NS)
                assert len(nodes)==clip['frames'], (clip['id'],slot)
                for endpoint in (nodes[0],nodes[-1]):
                    assert max(abs(a-c) for a,c in zip(timing.mat(endpoint),neutral[role]))<1e-6
                if role.endswith(('Upper','Lower')):
                    for part in nodes:
                        m=timing.mat(part)
                        assert math.hypot(m[2],m[3])<.9, ('stretched transition arm',clip['id'],slot)
            for weapon in node.findall('.//x:DOMSymbolInstance[@name="rockWeapon"]',b.NS):
                a,c1,c2,d,_,_=timing.mat(weapon)
                assert abs(a*d-c1*c2)>.1, ('collapsed mirrored weapon',clip['id'])
    for name in own:
        node = included[name]
        if '/特效/' in name:
            assert not node.findall('.//x:Actionscript', b.NS), name
        assert not node.xpath('.//x:DOMSymbolInstance[contains(@libraryItemName,"移植参考")]', namespaces=b.NS), name
    report = {'clips':14,'frames':manifest['totalFrames'],'ownedSymbols':len(own),'packedDependencies':len(seen),
              'missingDependencies':0,'newLinkageCollisions':0,'bossScripts':0}
    if args.swf:
        path = b.ROOT / 'flashswf/arts/things0.swf'
        raw = path.read_bytes()
        assert raw[:3] in (b'CWS', b'FWS')
        body = zlib.decompress(raw[8:]) if raw[:3] == b'CWS' else raw[8:]
        assert len(body) + 8 == struct.unpack_from('<I', raw, 4)[0], 'truncated SWF'
        offset = (5 + (body[0] >> 3)*4 + 7)//8 + 4
        native_exports, sprites = {}, {}
        while offset < len(body):
            tag = struct.unpack_from('<H', body, offset)[0]
            offset += 2
            code, length = tag >> 6, tag & 63
            if length == 63:
                length = struct.unpack_from('<I', body, offset)[0]
                offset += 4
            payload = body[offset:offset+length]
            assert len(payload) == length
            offset += length
            if code == 39:
                sid, frames = struct.unpack_from('<HH', payload)
                sprites[sid] = frames
            elif code == 56:
                count = struct.unpack_from('<H', payload)[0]
                p = 2
                for _ in range(count):
                    sid = struct.unpack_from('<H', payload, p)[0]
                    end = payload.index(0, p+2)
                    native_exports[payload[p+2:end].decode('utf-8')] = sid
                    p = end + 1
            if code == 0: break
        for clip in manifest['clips']:
            assert sprites[native_exports[clip['linkage']]] == clip['frames'], clip['linkage']
        report['native'] = {'sha256':hashlib.sha256(raw).hexdigest(), 'bytes':len(raw),
                            'exportedClips':14, 'exportedFrames':manifest['totalFrames']}
    print(json.dumps(report, ensure_ascii=False))

if __name__ == '__main__': main()
