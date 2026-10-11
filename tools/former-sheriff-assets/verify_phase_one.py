"""Read back compiled sheriff contracts; never rewrites SWFs."""
import json, struct
from pathlib import Path
from lxml import etree as E
from verify import ROOT, exports, swf_tags


def child_tags(buf, pos=4):
    while pos < len(buf):
        header=struct.unpack_from('<H',buf,pos)[0]; pos+=2
        code,size=header>>6,header&63
        if size==63: size=struct.unpack_from('<I',buf,pos)[0];pos+=4
        yield code,buf[pos:pos+size]
        pos+=size


def main():
    path=ROOT/'flashswf/arts/new/Codex专用素材.swf'
    names,sprites=exports(path)
    expected=['容器','空手站立','长枪站立','长枪行走','长枪跑','手枪站立','手枪行走','手枪跑','兵器站立','兵器行走','兵器跑','被击','击倒','倒地','血腥死','转阶段击倒','转阶段落地','转阶段起身']
    sprite=sprites[names['敌人-前治安官']]
    assert struct.unpack_from('<H',sprite,2)[0]==19
    frame=1;labels={}
    for code,payload in child_tags(sprite):
        if code==43:labels[payload.split(b'\0')[0].decode('utf8')]=frame
        elif code==1:frame+=1
    assert labels==dict(zip(expected,range(2,20))),labels
    for export in ['特勤飞盔']+['前治安官动作-'+x for x in ['小跳','翻滚换弹','兴奋剂','铁布衫','棍棒','盾冲']]:
        assert export in names,export
    assert struct.unpack_from('<H',sprites[names['战技容器-特勤盾冲']],2)[0]==152
    assert struct.unpack_from('<H',sprites[names['前治安官动作-盾冲']],2)[0]==152
    assert names['前治安官动作-盾冲']!=names['战技容器-特勤盾冲']
    # A declared XFL instance is insufficient: CS6 previously exported the
    # NPC's forward/shared reference as an empty sprite (getBounds sentinel).
    # Inspect each compiled linkage's actual named child before runtime tests.
    for export in ['战技容器-特勤盾冲','前治安官动作-盾冲']:
        hits=[payload for tag,payload in child_tags(sprites[names[export]])
              if tag==26 and '冲撞区域'.encode('utf8') in payload]
        assert len(hits)==1 and hits[0][0]&2,export
        child=struct.unpack_from('<H',hits[0],3)[0]
        assert any(tag==26 for tag,payload in child_tags(sprites[child])),(export,'empty impact geometry',child)
    ns={'x':'http://ns.adobe.com/xfl/2008/'}
    npc=ROOT/'flashswf/arts/new/Codex专用素材/LIBRARY/Codex/前治安官'
    for file in npc.rglob('*.xml'):
        xml=E.parse(str(file))
        for script in xml.findall('.//x:script',ns):
            assert '配置装扮' not in (script.text or ''),file
        for el in xml.iter():
            assert '/重装特勤/战技/挂点/' not in el.get('libraryItemName',''),file
    units=json.loads((ROOT/'data/units/units.json').read_text('utf-8-sig'))
    selected=[u for u in units if u['spritename']=='敌人-前治安官']
    assert len(selected)==1 and selected[0]['id']==458
    source=E.parse(str(ROOT/'data/items/asset_source_map.xml'))
    assert len(source.xpath('asset[@id="敌人-前治安官"]'))==1
    # Existing shared-library anchor must make this already-loaded owner reachable.
    imports=[]
    for tag,payload in swf_tags(ROOT/'flashswf/arts/things-new.swf'):
        if tag in (57,71):imports.append(payload.split(b'\0')[0].decode('utf8'))
    assert any('Codex专用素材.swf' in s for s in imports),imports
    # The isolated host needs explicit dynamic-action imports as well as the
    # library anchor; loading a sibling SWF does not grant its linkage scope.
    host_imports=[]
    for tag,payload in swf_tags(ROOT/'scripts/FormerSheriffNativeHost.swf'):
        if tag not in (57,71):continue
        offset=payload.index(b'\0')+1+(2 if tag==71 else 0)
        count=struct.unpack_from('<H',payload,offset)[0];offset+=2
        for _ in range(count):
            offset+=2;end=payload.index(b'\0',offset)
            host_imports.append(payload[offset:end].decode('utf8'));offset=end+1
    required=['敌人-前治安官','特勤飞盔','新版人物文字信息']+['前治安官动作-'+a for a in ['小跳','翻滚换弹','兴奋剂','铁布衫','棍棒','盾冲']]
    assert set(required).issubset(host_imports),host_imports
    result={'unitId':458,'linkage':'敌人-前治安官','compiledRootFrames':19,'labels':labels,'ownActionExports':6,'shieldRushFrames':152,'runtimeDressup':False,'separateFixedRush':True,'sharedLibraryImport':next(s for s in imports if 'Codex专用素材.swf' in s)}
    result['fixtureImports']=host_imports
    out=ROOT/'tmp/former-sheriff-phase-one/native-contract.json';out.parent.mkdir(parents=True,exist_ok=True);out.write_text(json.dumps(result,ensure_ascii=False,indent=2),'utf8')
    print(json.dumps(result,ensure_ascii=False))

if __name__=='__main__':main()
