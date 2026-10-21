"""Check dog-only source, library closure, data scope and compiled export."""
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import xml.etree.ElementTree as E
import zlib

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
OWNER=ROOT/'flashswf/arts/new/Codex专用素材'
N={'x':'http://ns.adobe.com/xfl/2008/'}


def check(value,label):
    if not value:raise AssertionError(label)


def exports(path):
    raw=path.read_bytes()
    body=zlib.decompress(raw[8:]) if raw[:3]==b'CWS' else raw[8:]
    offset=(5+4*(body[0]>>3)+7)//8+4
    result={};counts={};sprites={};shapes=set()
    def references(start,end):
        found=set()
        while start<end:
            h=struct.unpack_from('<H',body,start)[0];start+=2
            code,size=h>>6,h&63
            if size==63:size=struct.unpack_from('<I',body,start)[0];start+=4
            if code==4:found.add(struct.unpack_from('<H',body,start)[0])
            if code==26 and body[start]&2:found.add(struct.unpack_from('<H',body,start+3)[0])
            if code==70 and body[start]&2:
                at=start+4
                if body[start+1]&8:at=body.index(b'\0',at)+1
                found.add(struct.unpack_from('<H',body,at)[0])
            start+=size
            if code==0:break
        return found
    while offset<len(body):
        header=struct.unpack_from('<H',body,offset)[0];offset+=2
        code,size=header>>6,header&63
        if size==63:size=struct.unpack_from('<I',body,offset)[0];offset+=4
        counts[code]=counts.get(code,0)+1
        if code in (2,22,32,83):shapes.add(struct.unpack_from('<H',body,offset)[0])
        if code==39:sprites[struct.unpack_from('<H',body,offset)[0]]=references(offset+4,offset+size)
        if code==56:
            count=struct.unpack_from('<H',body,offset)[0];cursor=offset+2
            for _ in range(count):
                cid=struct.unpack_from('<H',body,cursor)[0];cursor+=2
                end=body.index(b'\0',cursor);result[body[cursor:end].decode('utf-8')]=cid;cursor=end+1
        offset+=size
        if code==0:break
    return result,counts,sprites,shapes


def main():
    manifest=json.loads((HERE/'native-manifest.json').read_text(encoding='utf-8'))
    for row in manifest.get('biteSupport',{}).get('inputs',[]):
        check(hashlib.sha256((ROOT/row['path']).read_bytes()).hexdigest()==row['sha256'],row['path'])
    for row in manifest['outputs']:
        check(hashlib.sha256((ROOT/row['path']).read_bytes()).hexdigest()==row['sha256'],row['path'])
    doc=E.parse(OWNER/'DOMDocument.xml').getroot()
    files={p.get('href') for p in doc.findall('./x:symbols/x:Include',N)}
    names=set()
    for relative in files:
        tree=E.parse(OWNER/'LIBRARY'/relative).getroot()
        names.add(tree.get('name'))
    names.update(x.get('name') for x in doc.findall('.//x:DOMBitmapItem',N))
    owned=[p for p in (OWNER/'LIBRARY/Codex/铁卫犬').rglob('*.xml')]
    broken=[]
    for p in owned:
        tree=E.parse(p).getroot()
        broken += [x.get('libraryItemName') for x in tree.findall('.//x:DOMSymbolInstance',N)
                   if x.get('libraryItemName') not in names]
        check(not tree.findall('.//x:DOMBitmapInstance',N) and not tree.findall('.//x:BitmapFill',N),'dog must stay vector')
    check(not broken,'broken dog library references: '+str(broken))
    check(len(owned)==73,'native symbol closure')
    root=E.parse(OWNER/'LIBRARY/Codex/铁卫犬/敌人-军阀铁卫犬.xml').getroot()
    check(root.get('linkageIdentifier')=='敌人-军阀铁卫犬','unique linkage')
    for p in (ROOT/'scripts/类定义/org/flashNight/arki/unit/UnitAI/Custom').glob('WarlordDog*.as'):
        check(p.read_bytes().startswith(b'\xef\xbb\xbf'),'AS2 BOM '+str(p))
    units=json.loads((ROOT/'data/units/units.json').read_text(encoding='utf-8-sig'))
    unit_id=json.loads((HERE/'balance-inputs.json').read_text(encoding='utf-8'))['unitId']
    check(len({u['id'] for u in units})==len(units),'all unit ids unique')
    check(len([u for u in units if u['id']==unit_id and u['spritename']=='敌人-军阀铁卫犬'])==1,'unique iron guard id/linkage')
    check(next(u for u in units if u['id']==13)['spritename']=='敌人-僵尸1-狗','ordinary dog remains unchanged')
    xml=E.parse(ROOT/'data/enemy_properties/军阀新人物.xml').getroot().find('敌人-军阀铁卫犬')
    check(xml.findtext('标识/阶段')=='3' and xml.findtext('标识/档次系数')=='2.5','stage/tier')
    check(xml.find('魔法抗性/装甲') is not None and xml.find('魔法抗性/人类') is None
          and xml.find('魔法抗性/机械') is None,'armored biological dog')
    level20={k:int(float(xml.findtext(a))+(float(xml.findtext(b))-float(xml.findtext(a)))*20/59)
             for k,a,b in [('hp','hp_min','hp_max'),('attack','空手攻击力_min','空手攻击力_max'),('defense','基本防御力_min','基本防御力_max')]}
    check(level20=={'hp':847,'attack':116,'defense':344},'actual level20 profile')
    stage=E.parse(ROOT/'data/stages/地下2层/禁区边缘.xml').getroot()
    types=[x.findtext('Type') for x in stage.find("SubStage[@id='1']").findall('.//Enemy')]
    check(types.count('兵种56')==2 and types.count('兵种'+str(unit_id))==1 and types.count('兵种25')==2,'showcase composition')
    check(stage.find("SubStage[@id='0']").find('.//Enemy[Type="兵种13"]') is not None,'opening wild dog preserved')
    swf=ROOT/'flashswf/arts/new/Codex专用素材.swf'
    linkage,counts,sprites,shapes=exports(swf)
    check('敌人-军阀铁卫犬' in linkage,'compiled export present')
    pending=[linkage['敌人-军阀铁卫犬']];seen=set()
    while pending:
        cid=pending.pop()
        if cid in seen:continue
        seen.add(cid);pending.extend(sprites.get(cid,()))
    reachable=len(seen&shapes)
    shape_codes=(2,22,32,83)
    check(reachable>=38,'compiled dog export must reach its actual body and death geometry')
    print(json.dumps({'status':'pass','ownedSymbols':len(owned),'brokenReferences':len(broken),
        'level20':level20,'compiledBytes':swf.stat().st_size,'nativeShapes':sum(counts.get(k,0) for k in shape_codes),
        'dogReachableShapes':reachable},ensure_ascii=False))


if __name__=='__main__':main()
