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


def shape_fill_colors(data, code, scanner):
    """Read native fill styles, rather than searching compressed drawing bytes."""
    bits=scanner.Bits(data,2)
    def rect():
        size=bits.u(5)
        for _ in range(4):bits.u(size)
        bits.align()
    rect()
    if code==83:rect();bits.byte+=1
    colors=set();width=4 if code in (32,83) else 3
    def color():
        colors.add(data[bits.byte:bits.byte+3].hex().upper());bits.byte+=width
    def fill():
        kind=data[bits.byte];bits.byte+=1
        if kind==0:color()
        elif kind in (16,18,19):
            scanner.skip_matrix(bits)
            stops=data[bits.byte]&15;bits.byte+=1
            for _ in range(stops):bits.byte+=1;color()
            if kind==19:bits.byte+=2
        elif kind in (64,65,66,67):bits.byte+=2;scanner.skip_matrix(bits)
        else:raise ValueError('Unexpected native fill style '+str(kind))
    def count():
        value=data[bits.byte];bits.byte+=1
        if value==255:
            value=struct.unpack_from('<H',data,bits.byte)[0];bits.byte+=2
        return value
    def styles():
        for _ in range(count()):fill()
        for _ in range(count()):
            bits.byte+=2
            if code!=83:color();continue
            bits.u(2);join=bits.u(2);has_fill=bits.u(1)
            bits.u(1);bits.u(1);bits.u(1);bits.u(5);bits.u(1);bits.u(2)
            if join==2:bits.byte+=2
            if has_fill:fill()
            else:color()
    styles()
    fill_bits,line_bits=bits.u(4),bits.u(4)
    while True:
        if bits.u(1):
            straight=bits.u(1);size=bits.u(4)+2
            if not straight:
                for _ in range(4):bits.u(size)
            elif bits.u(1):bits.u(size);bits.u(size)
            else:bits.u(1);bits.u(size)
            continue
        flags=bits.u(5)
        if flags==0:break
        if flags&1:
            size=bits.u(5);bits.u(size);bits.u(size)
        if flags&2:bits.u(fill_bits)
        if flags&4:bits.u(fill_bits)
        if flags&8:bits.u(line_bits)
        if flags&16:
            bits.align();styles();fill_bits,line_bits=bits.u(4),bits.u(4)
    return colors


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
    sprites,exports,shapes={},{},set()
    shape_colors={}
    for code,data in tags(body,(5+(body[0]>>3)*4+7)//8+4):
        if code==39:sprites[struct.unpack_from('<H',data)[0]]=data
        elif code in (2,22,32,83):
            cid=struct.unpack_from('<H',data)[0];shapes.add(cid)
            shape_colors[cid]=shape_fill_colors(data,code,scanner)
        elif code==56:
            pos=2
            for _ in range(struct.unpack_from('<H',data)[0]):
                cid=struct.unpack_from('<H',data,pos)[0]
                name,pos=scanner.read_string(data,pos+2);exports[name]=cid
    checked={};appearances={}
    def drawing_colors(cid,seen):
        if cid in seen:return set()
        seen.add(cid)
        colors=set(shape_colors.get(cid,()))
        if cid in sprites:
            for code,data in tags(sprites[cid],4):
                if code not in (26,70):continue
                bits=scanner.Bits(data);flags=bits.u(8);flags2=bits.u(8) if code==70 else 0
                bits.byte+=2
                if code==70 and (flags2&8 or flags2&16 and flags&2):
                    _,bits.byte=scanner.read_string(data,bits.byte)
                if flags&2:colors.update(drawing_colors(struct.unpack_from('<H',data,bits.byte)[0],seen))
        return colors
    for link in (build.LINKAGE,build.SHIELD_LINKAGE,*build.elite.LINKAGES,*build.tactics.LINKAGES):
        prefix=build.tactics.PREFIX if link in build.tactics.LINKAGES else build.PREFIX
        xml=E.parse(str(build.OWNER/'LIBRARY'/(prefix+link+'.xml')))
        expected={}
        for frame in xml.findall('.//x:DOMLayer[@name="动作"]/x:frames/x:DOMFrame',build.NS):
            item=frame.find('x:elements/x:DOMSymbolInstance[@name="man"]',build.NS)
            if item is None:continue
            child=E.parse(str(build.OWNER/'LIBRARY'/(item.get('libraryItemName')+'.xml')))
            expected[int(frame.get('index'))+1]=max(int(f.get('index'))+int(f.get('duration','1'))
                for f in child.findall('.//x:DOMFrame',build.NS))
        active,actual,body_ids={},{},{};number=1
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
                    body_ids[number]=bodies[0]['id']
                number+=1
        assert all(actual.get(frame)==count for frame,count in expected.items()), (link,expected,actual)
        if link in (*build.elite.LINKAGES,*build.tactics.LINKAGES):
            # Complete frame counts alone miss CS6 exports containing only guns
            # and waist MovieClips. The combined action must retain native body
            # Shapes on every one of its 365 frames; pixel tests also check this
            # independently with the guns, waist and shadow hidden.
            drawing={};visible=[]
            for code,data in tags(sprites[body_ids[42]],4):
                if code==28:drawing.pop(struct.unpack_from('<H',data)[0],None)
                elif code in (26,70):
                    bits=scanner.Bits(data);flags=bits.u(8);flags2=bits.u(8) if code==70 else 0
                    depth=struct.unpack_from('<H',data,bits.byte)[0];bits.byte+=2
                    if code==70 and (flags2&8 or flags2&16 and flags&2):
                        _,bits.byte=scanner.read_string(data,bits.byte)
                    if not flags&1:drawing.pop(depth,None)
                    if flags&2:drawing[depth]=struct.unpack_from('<H',data,bits.byte)[0]
                elif code==1:visible.append(sum(cid in shapes for cid in drawing.values()))
            assert len(visible)==365 and all(visible), (link,'Missing combined-action body drawings',visible)
        checked[link]=len(expected)
        body_id=body_ids[min(body_ids)]
        colors=drawing_colors(body_id,set())
        gold={'D6A14A','C68E39','9B682B'}
        instructor=link in build.tactics.LINKAGES
        assert (not colors&gold) if instructor else gold<=colors, (link,'Wrong role material',sorted(colors&gold))
        appearances[link]={'standingBodyId':body_id,'material':'instructor-black' if instructor else 'soldier-yellow-black'}
    ordinary_ids={v['standingBodyId'] for k,v in appearances.items() if k not in build.tactics.LINKAGES}
    instructor_ids={appearances[k]['standingBodyId'] for k in build.tactics.LINKAGES}
    assert not ordinary_ids&instructor_ids, 'CS6 merged instructor and soldier body timelines'
    return checked,appearances


def verify_elite_sidearm():
    owner = build.OWNER/'LIBRARY'
    motion = E.parse(str(owner/'Codex/特种兵/精英/动作/CF6战术长枪.xml'))
    instances = []
    for frame in motion.findall('.//x:DOMLayer/x:frames/x:DOMFrame', build.NS):
        sidearms = frame.findall('x:elements/x:DOMSymbolInstance[@name="枪2"]', build.NS)
        assert len(sidearms) <= 1, 'Duplicate sidearm holder at frame '+frame.get('index')
        for item in sidearms:
            assert item.get('libraryItemName') == 'Codex/特种兵/精英/武器/可配置副手枪'
            instances.append(int(frame.get('index'))+1)
    assert sorted(instances) == list(range(2,45)), instances
    root = E.parse(str(owner/'Codex/特种兵/敌人-CF6特种精英.xml'))
    text = '\n'.join(node.text or '' for node in root.findall('.//x:script', build.NS))
    for marker in ('eliteMotionConfig', '初始化混合双枪', '开始混合手枪换弹', 'eliteReloadGate', '手枪射击=function', '手枪2射击=function'):
        assert marker in text, 'Missing mixed weapon marker: '+marker
    ordinary = E.parse(str(owner/'Codex/特种兵/敌人-CF6特种兵.xml'))
    ordinary_text = '\n'.join(node.text or '' for node in ordinary.findall('.//x:script', build.NS))
    assert 'eliteMotionConfig' not in ordinary_text and '初始化混合双枪' not in ordinary_text
    assert motion.find('.//x:DOMFrame[@index="295"][@name="双枪换弹匣"]',build.NS) is not None
    primary = motion.findall('.//x:DOMSymbolInstance[@libraryItemName="Codex/特种兵/精英/武器/可配置主手枪"]',build.NS)
    assert primary, 'Retreat must use the primary pistol instead of the long gun'
    for path in (owner/'Codex/特种兵/动作').glob('*.xml'):
        tree = E.parse(str(path))
        for waist in tree.findall('.//x:DOMSymbolInstance[@libraryItemName="Codex/特种兵/分件/489"]',build.NS):
            assert waist.get('name') == '腰挂' and waist.get('symbolType', 'movie clip') == 'movie clip', str(path)
    waist = E.parse(str(owner/'Codex/特种兵/分件/489.xml'))
    waist_script = '\n'.join(node.text or '' for node in waist.findall('.//x:script',build.NS))
    assert 'slot+"_装扮_引用"' in waist_script and 'soldierIsElite===true' in waist_script
    assert len(waist.findall('.//x:DOMLayer[@layerType="mask"]',build.NS)) == 2
    for item in motion.findall('.//x:DOMSymbolInstance[@libraryItemName="Codex/特种兵/分件/489"]',build.NS):
        assert item.get('name') == '腰挂' and item.get('symbolType', 'movie clip') == 'movie clip'
    return {'sidearmFrames': len(instances)}


def verify_library_index():
    entries=E.parse(str(build.OWNER/'DOMDocument.xml')).findall('x:symbols/x:Include',build.NS)
    position={entry.get('href'):i for i,entry in enumerate(entries)}
    for i,entry in enumerate(entries):
        name=entry.get('href')
        root=E.parse(str(build.OWNER/'LIBRARY'/name)).getroot()
        identity=root.get('itemID',build.native.item_id(name[:-4]))
        assert entry.get('itemID')==identity, ('Library identity mismatch',name)
        assert entry.get('loadImmediate')=='false', ('Unexpected eager loading',name)
        for instance in root.findall('.//x:DOMSymbolInstance',build.NS):
            child=instance.get('libraryItemName')+'.xml'
            assert position[child]<i, ('Library dependency order',name,child)
    return len(entries)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--runtime-root', type=Path, default=build.ROOT,
        help='Owned frozen combat checkout; the tested Soldier SWF must match the editable source checkout')
    args = parser.parse_args()
    build.check()
    library_index_checks=verify_library_index()
    subprocess.run([sys.executable, '-X', 'utf8', '-B', str(build.HERE / 'balance.py')], check=True)
    relative = 'flashswf/arts/new/' + build.ANCHOR + '.swf'
    swf = build.ROOT / relative
    exports, imports = linkage_records(swf)
    assert set(exports) == {build.LINKAGE, build.SHIELD_LINKAGE, build.ANCHOR,*build.elite.LINKAGES,*build.tactics.LINKAGES,'CF6战术烟雾'} and len(exports) == 8
    assert not imports, 'Independent Soldier library unexpectedly imports another RSL'
    _, shared = linkage_records(build.ROOT / 'flashswf/arts/things-new.swf')
    matching = [r for r in shared if build.ANCHOR in r['names']]
    assert len(matching) == 1 and matching[0]['url'] == relative
    source_map = E.parse(str(build.ROOT / 'data/items/asset_source_map.xml')).getroot()
    matching = [r for r in source_map if r.get('id') == build.LINKAGE]
    assert len(matching) == 1 and matching[0].get('swf') == relative
    shield_matching = [r for r in source_map if r.get('id') == build.SHIELD_LINKAGE]
    assert len(shield_matching) == 1 and shield_matching[0].get('swf') == relative
    with zipfile.ZipFile(build.ROOT / 'flashswf/arts/things-new.fla') as archive:
        declaration = E.fromstring(archive.read('LIBRARY/' + build.ANCHOR + '.xml'))
        assert declaration.get('linkageImportForRS') == 'true'
        assert declaration.get('linkageURL') == relative
        entry = E.fromstring(archive.read('LIBRARY/things-new.xml'))
        instances = entry.findall('.//x:DOMFrame[@index="3"]//x:DOMSymbolInstance', build.NS)
        assert sum(r.get('libraryItemName') == build.ANCHOR for r in instances) == 1
    for path in [build.HERE / 'SoldierAI.as', build.HERE / 'EliteAI.as',
            build.ROOT / 'scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6SoldierAssetTest.as',
            build.ROOT / 'scripts/逻辑/单位函数/单位函数_lsy_主角射击函数.as']:
        assert path.read_bytes().startswith(b'\xef\xbb\xbf'), 'AS2 file must retain UTF-8 BOM: ' + str(path)
    scanner = build.module('manman_swfscan', build.ROOT / 'tools/swf-audit/swfscan.py')
    pixels = scanner.scan(swf)
    body_checks,appearance_checks = verify_body_timelines(swf,scanner)
    sidearm_checks = verify_elite_sidearm()
    assert pixels['bitmaps'] == 0 and pixels['shapes'] > 0
    runtime_root = args.runtime_root.resolve()
    assert build.sha(runtime_root / relative) == build.sha(swf), 'Frozen combat asset differs from the source checkout'
    subprocess.run(['node', str(build.ROOT / 'tools/audit-as2-class-embedding.js'), '--root', str(runtime_root),
        '--swf', relative], cwd=build.ROOT, check=True)
    print(json.dumps({'ok': True, 'sourceSwf': relative, 'sha256': build.sha(swf),
        'bytes': pixels['bytes'], 'shapes': pixels['shapes'], 'sprites': pixels['sprites'],
        'bitmaps': pixels['bitmaps'], 'exports': exports, 'sharedImport': matching[0].get('swf'),
        'runtimeOwnershipRoot': str(runtime_root),'bodyTimelineChecks':body_checks,
        'sidearm':sidearm_checks,'libraryIndexChecks':library_index_checks,
        'roleAppearanceChecks':appearance_checks}, ensure_ascii=False))


if __name__ == '__main__':
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf8')
    main()
