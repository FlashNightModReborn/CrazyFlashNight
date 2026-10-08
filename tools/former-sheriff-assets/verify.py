"""Check the registered items, NPC closure and fresh published library exports."""
from pathlib import Path
import hashlib, json, struct, subprocess, zlib
from lxml import etree as E
import register_items as data

ROOT = data.ROOT
NS = {'x': 'http://ns.adobe.com/xfl/2008/'}
OUT = ROOT/'tmp/former-sheriff-integration'

def swf_tags(path):
    raw=path.read_bytes()
    assert raw[:3] in [b'CWS',b'FWS'], path
    buf=zlib.decompress(raw[8:]) if raw[:3]==b'CWS' else raw[8:]
    pos=(5+4*(buf[0]>>3)+7)//8+4
    tags=[]
    while pos<len(buf):
        h=struct.unpack_from('<H',buf,pos)[0];pos+=2
        code,length=h>>6,h&63
        if length==63:
            length=struct.unpack_from('<I',buf,pos)[0];pos+=4
        tags.append((code,buf[pos:pos+length]));pos+=length
    return tags

def exports(path):
    result={};sprites={}
    for tag,payload in swf_tags(path):
        if tag==39:
            sprites[struct.unpack_from('<H',payload)[0]]=payload
        elif tag==56:
            count=struct.unpack_from('<H',payload)[0];pos=2
            for _ in range(count):
                id=struct.unpack_from('<H',payload,pos)[0];pos+=2
                end=payload.index(0,pos);name=payload[pos:end].decode('utf8');pos=end+1
                assert name not in result
                result[name]=id
    return result,sprites

def main():
    build=json.loads((OUT/'build-report.json').read_text('utf8'))
    report={'itemCount':8,'hairstyle':77,'checks':[]}
    source_map=E.parse(str(ROOT/'data/items/asset_source_map.xml')).getroot()
    for name,filename,donor,dressup,_ in data.SPECS:
        roots=E.parse(str(ROOT/'data/items'/filename)).getroot()
        matches=[e for e in roots.findall('item') if e.findtext('name')==name]
        assert len(matches)==1,name
        item=matches[0]
        assert item.findtext('data/dressup')==dressup
        assert item.findtext('icon')=='Codex-'+name
        assert not item.findall('skill')
        if name == '特勤霰弹枪':
            light = item.find('lifecycle/attr_equipmentLight')
            assert light is not None and light.findtext('skillInteraction') == 'independent'
            assert light.findtext('init/initParam/anchor') == '手电口'
            assert light.findtext('init/initParam/beamPath') == '装备光束'
            assert light.findtext('init/initParam/builtinDefense') == 'true'
            assert light.findtext('init/initParam/evasionBonus') == '20'
            assert item.findtext('data/modslot') == '0'
            assert item.findtext('data/bullet') == '镇暴射线'
        elif name == '特勤警棍':
            baton = item.find('lifecycle/attr_sheriffBaton')
            assert baton is not None and baton.findtext('skillInteraction') == 'independent'
            assert baton.findtext('init/initRoutines') == '特勤警棍初始化'
            assert baton.findtext('cycle/cycleRoutines') == '特勤警棍周期'
            assert baton.findtext('init/initParam/frameMax') == '15'
            assert baton.findtext('init/initParam/batonPower') == '220'
            assert baton.findtext('init/initParam/batonDefence') == '165'
            assert item.findtext('data/defence') == '0'
        else:
            assert not item.findall('lifecycle')
        assert not any(str(e.tag).startswith('data_') for e in item)
    for key in build['exports']:
        mapped=[e for e in source_map if e.get('id')==key]
        assert len(mapped)==1 and mapped[0].tag=='asset',key
        assert mapped[0].get('swf')=='flashswf/arts/new/Codex专用素材.swf',key
        assert mapped[0].get('orphan')!='true',key
    swf=ROOT/'flashswf/arts/new/Codex专用素材.swf'
    public,sprites=exports(swf)
    for key in build['exports']:
        assert key in public and public[key] in sprites,key
    for key in ['枪-长枪-Codex-特勤霰弹枪','枪-手枪-Codex-特勤沙鹰']:
        raw=sprites[public[key]]
        assert '枪口位置'.encode() in raw and '动画'.encode() in raw,key
        if key == '枪-长枪-Codex-特勤霰弹枪':
            assert '手电口'.encode() in raw and '装备光束'.encode() in raw
    raw=sprites[public['刀-Codex-特勤警棍']]
    assert struct.unpack_from('<H',raw,2)[0] == 15, 'published Q animation frame count'
    for key in ['刀口位置1','刀口位置2','刀口位置3']:
        assert key.encode() in raw,key
    for name,*_ in data.SPECS:
        raw=sprites[public['图标-Codex-'+name]]
        assert struct.unpack_from('<H',raw,2)[0]==2,name
    report['checks'].append('32 new exports exist in actual CS6 SWF; gun/melee interfaces and 2-frame icons present')
    report['librarySha256']=hashlib.sha256(swf.read_bytes()).hexdigest()
    owned=ROOT/'flashswf/arts/new/Codex专用素材'
    inputs=[owned/'DOMDocument.xml',owned/'LIBRARY/Codex专用素材.xml']
    inputs += list((owned/'LIBRARY/Codex/重装特勤').rglob('*.xml'))
    newer=[p.relative_to(ROOT).as_posix() for p in inputs if p.stat().st_mtime_ns>swf.stat().st_mtime_ns]
    report['librarySourceNewerThanSwf']=newer
    report['mapPublication']={}
    for mapname in ['基地场景合集','地图-第一防线防区']:
        base=ROOT/'flashswf/levels'/mapname
        rel=(base/'LIBRARY/NPC/前治安官/前治安官-NPC.xml').relative_to(ROOT).as_posix()
        before=subprocess.check_output(['git','show','HEAD:'+rel],cwd=ROOT)
        assert (ROOT/rel).read_bytes()==before,'NPC interaction changed: '+mapname
        visual=E.parse(str(base/'LIBRARY/NPC/前治安官/图形/Symbol 2703.xml'))
        frames=visual.findall('.//x:DOMFrame',NS)
        assert [(int(f.get('index')),int(f.get('duration'))) for f in frames]==[(0,24),(24,11),(35,11),(46,13)]
        for f,expected in zip(frames,build['npcSymbols']):
            assert f.find('x:elements/x:DOMSymbolInstance',NS).get('libraryItemName')==expected
        report['checks'].append(mapname+': original dialogue/hit area wrapper byte-identical; four visual poses and frame durations preserved')
        published=base.with_suffix('.swf')
        inputs=[base/'DOMDocument.xml',base/'LIBRARY/NPC/前治安官/图形/Symbol 2703.xml']
        inputs+=list((base/'LIBRARY/Codex/重装特勤').rglob('*.xml'))
        fresh=published.exists() and all(p.stat().st_mtime_ns<=published.stat().st_mtime_ns for p in inputs)
        report['mapPublication'][mapname]={'fresh':fresh,'swf':published.relative_to(ROOT).as_posix()}
    report['runtimePlaytest']=False
    report['publicationComplete']=not newer and all(x['fresh'] for x in report['mapPublication'].values())
    (OUT/'verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),'utf8')
    print('PASS:',len(build['exports']),'SWF exports; 8 items; unchanged NPC interaction wrappers')
    if not report['publicationComplete']:
        print('INCOMPLETE: latest source is not fully published; see verification.json')
        raise SystemExit(1)

if __name__=='__main__':
    main()
