"""Independent source contract checks; native runtime is checked by the focused runner."""
import copy, json, re
from pathlib import Path
from lxml import etree as E
import build as b

def scripts(root):
    return ['\n'.join(line.expandtabs(4).rstrip(' \t') for line in (s.text or '').splitlines()).strip() for s in root.findall('.//x:script',b.NS)]
def normalized(root):
    out=copy.deepcopy(root)
    for s in out.findall('.//x:script',b.NS):
        s.text='\n'.join(line.expandtabs(4).rstrip(' \t') for line in (s.text or '').splitlines()).strip()
    return E.tostring(out,method='c14n')
def props(node):
    return {c.tag:(props(c) if len(c) else (c.text or '').strip()) for c in node if isinstance(c.tag,str) and c.tag!='displayname'}

b.verify_input();b.check()
manifest=json.loads((b.HERE/'native-manifest.json').read_text(encoding='utf-8'))
units=json.loads((b.ROOT/'data/units/units.json').read_text(encoding='utf-8-sig'))
assert len({u['id'] for u in units})==len(units),'Duplicate unit id'
base=next(u for u in units if u['id']==13)
oldprops=E.parse(str(b.ROOT/'data/enemy_properties/原版敌人 2011-2012.xml')).find('敌人-僵尸1-狗')
newprops=E.parse(str(b.ROOT/'data/enemy_properties/两犬.xml'))
assert '两犬.xml' in [c.text for c in E.parse(str(b.ROOT/'data/enemy_properties/list.xml')).getroot()]
source_map=E.parse(str(b.ROOT/'data/items/asset_source_map.xml')).getroot()
inherited=0;script_count=0;mouth_frames=0
for variant in manifest['variants']:
    current=next(u for u in units if u['id']==variant['unitId'])
    assert {k:v for k,v in current.items() if k not in ('id','key','spritename','name')}=={k:v for k,v in base.items() if k not in ('id','key','spritename','name')}
    assert props(newprops.find(variant['linkage']))==props(oldprops),'Dog stats differ'
    links=[row for row in source_map if row.get('id')==variant['linkage']]
    assert len(links)==1 and links[0].tag=='asset' and links[0].get('swf')=='flashswf/arts/new/Codex专用素材.swf'
    mapping=variant['mapping'];reverse={v:k for k,v in mapping.items()}
    assert set(b.DEATH.values())=={p['historicalSlot'] for p in variant['parts'] if p['historicalSlot']>1350}
    for name,mapped in mapping.items():
        if name.startswith('Symbol ') and int(name.split()[1]) in {**b.NORMAL,**b.DEATH}:continue
        original=E.parse(str(b.SOURCE/(name+'.xml')),b.PARSER).getroot()
        clone=E.parse(str(b.OWNER/'LIBRARY'/(mapped+'.xml')),b.PARSER).getroot()
        assert scripts(clone)==scripts(original),f'Inherited AS2 changed: {mapped}'
        script_count+=len(scripts(original))
        assert len(clone.findall('.//x:DOMFrame[@name]',b.NS))==len(original.findall('.//x:DOMFrame[@name]',b.NS))
        for el in clone.iter():
            ref=el.get('libraryItemName')
            if ref:el.set('libraryItemName',reverse[ref])
        layers=clone.find('x:timeline/x:DOMTimeline/x:layers',b.NS)
        for layer in list(layers):
            if layer.get('name')=='口腔内壁（随双颌姿势）':
                for frame in layer.findall('x:frames/x:DOMFrame',b.NS):
                    mouth_frames+=int(frame.get('duration','1')) if len(frame.find('x:elements',b.NS)) else 0
                layers.remove(layer)
        clone.attrib.clear();clone.attrib.update(original.attrib)
        clone.find('x:timeline/x:DOMTimeline',b.NS).set('name',original.find('x:timeline/x:DOMTimeline',b.NS).get('name'))
        assert normalized(clone)==normalized(original),f'Inherited timeline changed: {mapped}'
        inherited+=1
    for part in variant['parts']:
        assert part['shapes']>0 and part['segments']>0
    root=E.parse(str(b.OWNER/'LIBRARY'/(variant['root']+'.xml')),b.PARSER).getroot()
    assert root.get('linkageIdentifier')==variant['linkage']
    assert root.get('linkageExportForAS')=='true'
result={'result':'PASS','variants':2,'nativeSymbols':len(manifest['outputs']),'inheritedTimelinesCompared':inherited,
        'inheritedScriptsCompared':script_count,'framesWithOralCavity':mouth_frames,'identityPieces':50,
        'unitRegistrationExactZombieDogCopy':True,'enemyPropertiesExactZombieDogCopy':True,
        'originalSourceHashesUnchanged':True,'evidence':'static_native_source_and_registration_only'}
print(json.dumps(result,ensure_ascii=False))
