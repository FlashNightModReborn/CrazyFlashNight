"""Generate an isolated, source-bound native art fixture; never a second editor source."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import uuid
from lxml import etree as E

ROOT = Path(__file__).resolve().parents[2]
HOST = ROOT / 'scripts/WarlordDogBiteHost'
SOURCE = ROOT / 'flashswf/arts/things1/LIBRARY'
OWNER = ROOT / 'flashswf/arts/new/Codex专用素材/LIBRARY'
N = {'x':'http://ns.adobe.com/xfl/2008/'}
X = '{'+N['x']+'}'
PARSER = E.XMLParser(strip_cdata=False)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--output', type=Path, required=True)
    ap.add_argument('--guard-source', type=Path)
    args = ap.parse_args()
    evidence = args.output.resolve()
    evidence.mkdir(parents=True, exist_ok=False)
    nonce = uuid.uuid4().hex
    generated, inputs = {}, []
    seen = {}

    def clone(name):
        if name in seen:
            return
        p = SOURCE/(name+'.xml')
        tree = E.parse(str(p), PARSER)
        seen[name] = tree
        inputs.append({'path':p.relative_to(ROOT).as_posix(), 'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
        for inst in tree.findall('.//x:DOMSymbolInstance', N):
            clone(inst.get('libraryItemName'))

    clone('敌人-僵尸1-狗')
    for old, tree in seen.items():
        el = tree.getroot()
        el.set('name', 'BiteReference/'+old)
        for k in list(el.attrib):
            if k.startswith('linkage'):
                del el.attrib[k]
        if old == '敌人-僵尸1-狗':
            el.set('linkageExportForAS', 'true')
            el.set('linkageExportInFirstFrame', 'true')
            el.set('linkageIdentifier', 'Reference-OriginalZombieDog')
        for inst in el.findall('.//x:DOMSymbolInstance', N):
            inst.set('libraryItemName', 'BiteReference/'+inst.get('libraryItemName'))
        generated['BiteReference/'+old+'.xml'] = (E.tostring(tree, encoding='utf-8', xml_declaration=True), el.get('itemID'))
    guard_source = args.guard_source.resolve() if args.guard_source else OWNER
    guard_count = 0
    for p in sorted((guard_source/'Codex/铁卫犬').rglob('*.xml')):
        inputs.append({'path':p.relative_to(ROOT).as_posix(), 'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
        guard_count += 1
        if args.guard_source:
            generated[p.relative_to(guard_source).as_posix()] = (p.read_bytes(), E.parse(str(p)).getroot().get('itemID'))
    assert guard_count==73, 'Incomplete guarded native namespace'
    if not args.guard_source:
        for name in ('FormerSheriffLibrary.xml','FormerSheriffNameplate.xml'):
            p=ROOT/'scripts/WarlordDogHost/LIBRARY'/name
            generated[name]=(p.read_bytes(),None)
        imported=E.Element(X+'DOMSymbolItem',nsmap={None:N['x']}, name='IronGuardImport',
            linkageImportForRS='true',linkageIdentifier='敌人-军阀铁卫犬',
            linkageURL='../flashswf/arts/new/Codex专用素材.swf',linkageExportInFirstFrame='true')
        timeline=E.SubElement(E.SubElement(imported,X+'timeline'),X+'DOMTimeline',name='IronGuardImport')
        ilayer=E.SubElement(E.SubElement(timeline,X+'layers'),X+'DOMLayer',name='Import')
        E.SubElement(E.SubElement(E.SubElement(ilayer,X+'frames'),X+'DOMFrame',index='0'),X+'elements')
        generated['IronGuardImport.xml']=(E.tostring(imported,encoding='utf-8',xml_declaration=True),None)
    doc = E.Element(X+'DOMDocument', nsmap={None:N['x']}, width='640', height='480', frameRate='30',
                    xflVersion='2.2', creatorInfo='Adobe Flash Professional CS6', platform='Windows')
    symbols = E.SubElement(doc, X+'symbols')
    for name, (data, item_id) in sorted(generated.items()):
        p = HOST/'LIBRARY'/name
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(data)
        attrs = {'href':name}
        if item_id:
            attrs['itemID'] = item_id
        E.SubElement(symbols, X+'Include', **attrs)
    timeline = E.SubElement(E.SubElement(doc, X+'timelines'), X+'DOMTimeline', name='Bite native art fixture')
    layer = E.SubElement(E.SubElement(timeline, X+'layers'), X+'DOMLayer', name='Isolated read-only probe')
    frame = E.SubElement(E.SubElement(layer, X+'frames'), X+'DOMFrame', index='0')
    script = E.SubElement(E.SubElement(frame, X+'Actionscript'), X+'script')
    script.text = E.CDATA('stop();\n#include "Entry.as"')
    frame_elements=E.SubElement(frame, X+'elements')
    if not args.guard_source:
        for name in ('FormerSheriffLibrary','FormerSheriffNameplate'):
            inst=E.SubElement(frame_elements,X+'DOMSymbolInstance',libraryItemName=name)
            E.SubElement(E.SubElement(inst,X+'matrix'),X+'Matrix',tx='-2000',ty='-2000')
    hidden=E.SubElement(layer.find('./x:frames',N),X+'DOMFrame',index='1')
    hidden_elements=E.SubElement(hidden,X+'elements')
    if not args.guard_source:
        E.SubElement(hidden_elements,X+'DOMSymbolInstance',libraryItemName='IronGuardImport')
    (HOST/'DOMDocument.xml').write_bytes(E.tostring(doc, encoding='utf-8', xml_declaration=True))
    entry_xfl=HOST/'WarlordDogBiteHost.xfl'
    source_xfl=ROOT/'scripts/WarlordDogHost/WarlordDogHost.xfl'
    if not entry_xfl.exists():
        shutil.copy2(source_xfl,entry_xfl)
    else:
        assert entry_xfl.read_bytes()==source_xfl.read_bytes(), 'Unexpected XFL entry content'
    settings = (ROOT/'scripts/WarlordDogHost/PublishSettings.xml').read_text(encoding='utf-8')
    (HOST/'PublishSettings.xml').write_text(settings.replace('WarlordDogHost','WarlordDogBiteHost'), encoding='utf-8')
    entry = HOST/'Entry.as'
    template = ROOT/'scripts/test-runners/warlord-dog-bite/TestLoader.as.template'
    shutil.copy2(template, entry)
    entry.write_text(template.read_text(encoding='utf-8-sig').replace('__FOCUSED_RUN_ID__',nonce), encoding='utf-8-sig')
    suite = ROOT/'scripts/类定义/org/flashNight/arki/unit/UnitAI/Custom/WarlordDogBiteArtTest.as'
    inputs += [{'path':p.relative_to(ROOT).as_posix(), 'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
               for p in (suite, template)]
    binding = {'nonce':nonce, 'evidence':str(evidence), 'target':'scripts/WarlordDogBiteHost/WarlordDogBiteHost.xfl',
               'swf':'scripts/WarlordDogBiteHost.swf', 'canonicalSnapshots':inputs, 'referenceSymbols':len(seen),
               'scope':'Real CS6 native art; motion/damage stubs, fixed 2x origin; not a combat result'}
    binding['guardMode']='source-bound preserved snapshot' if args.guard_source else 'actual published resource via RSL'
    if not args.guard_source:
        p=ROOT/'flashswf/arts/new/Codex专用素材.swf'
        binding['publishedResource']={'path':p.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
    (evidence/'binding.json').write_text(json.dumps(binding,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(binding,ensure_ascii=False))


if __name__ == '__main__':
    main()
