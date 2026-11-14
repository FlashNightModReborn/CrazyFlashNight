"""Round-trip only the owned artwork through CS6, then copy those XMLs back."""
import argparse
from pathlib import Path
import re
import xml.etree.ElementTree as ET
from build import ROOT, OWNED, PREFIX, NS, E, CONFIG, item_id, instance, layer, frame, xml_bytes, generate

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--apply', action='store_true')
args = parser.parse_args()
project = ROOT/'tmp/ak47-fire-kylin/NativeInput'
owned = sorted((OWNED/'LIBRARY'/PREFIX).rglob('*.xml'))
expected, _ = generate()
assert {str(p.relative_to(OWNED/'LIBRARY')).replace('\\','/')[:-4] for p in owned} == set(expected)

if args.apply:
    document = OWNED/'DOMDocument.xml'
    text = document.read_text('utf-8-sig')
    for path in owned:
        relative = path.relative_to(OWNED)
        source = project/relative
        root = ET.parse(source).getroot()
        assert root.get('name').startswith(PREFIX+'/')
        suffix = int(root.get('itemID').split('-')[1], 16)
        assert 0 <= suffix < 0x100000
        path.write_bytes(source.read_bytes())
        href = root.get('name')+'.xml'
        pattern = r'(<Include\b[^>]*\bhref="'+re.escape(href)+r'"[^>]*\bitemID=")[^"]+("[^>]*/>)'
        text, count = re.subn(pattern, lambda m:m[1]+root.get('itemID')+m[2], text)
        assert count == 1, href
    document.write_text(text, encoding='utf-8', newline='\n')
    print('Applied '+str(len(owned))+' native-saved owned symbols; other source files untouched.')
else:
    project.mkdir(parents=True, exist_ok=True)
    closure = {}
    pending = [str(p.relative_to(OWNED/'LIBRARY'))[:-4].replace('\\','/') for p in owned]
    while pending:
        name = pending.pop()
        if name in closure: continue
        path = OWNED/'LIBRARY'/(name+'.xml')
        root = ET.parse(path).getroot()
        assert root.get('name') == name
        closure[name] = root
        pending.extend(e.get('libraryItemName') for e in root.findall('.//x:DOMSymbolInstance',NS))
    assert len(closure) < 40
    doc = E('DOMDocument',{'width':'1200','height':'450','frameRate':'30','backgroundColor':'#263344',
                          'xflVersion':'2.2','creatorInfo':'Adobe Flash Professional CS6',
                          'platform':'Windows','versionInfo':'Saved by Adobe Flash Windows 12.0 build 481',
                          'majorVersion':'12','buildNumber':'481','currentTimeline':'1'})
    folders = E('folders',parent=doc)
    folder_names = sorted({name.rsplit('/',1)[0] for name in closure} | {'Codex',PREFIX})
    for name in folder_names: E('DOMFolderItem',{'name':name,'itemID':item_id('folder/'+name)},folders)
    includes = E('symbols',parent=doc)
    for name,root in sorted(closure.items()):
        path=project/'LIBRARY'/(name+'.xml');path.parent.mkdir(parents=True,exist_ok=True)
        path.write_bytes((OWNED/'LIBRARY'/(name+'.xml')).read_bytes())
        E('Include',{'href':name+'.xml','itemID':root.get('itemID')},includes)
    elements=[instance(PREFIX+'/'+CONFIG['linkage'],(1,0,0,1,180,220),graphic=False),
              instance(PREFIX+'/'+CONFIG['icon'],(5,0,0,5,900,210),graphic=False)]
    E('layers',parent=E('DOMTimeline',{'name':'NativeInput'},E('timelines',parent=doc))).append(layer('火麒麟原生核对',[frame(0,elements,stop=True)]))
    (project/'DOMDocument.xml').write_bytes(xml_bytes(doc))
    (project/'NativeInput.xfl').write_bytes(b'PROXY-CS5')
    settings=ET.parse(OWNED/'PublishSettings.xml').getroot()
    for e in settings.iter():
        if e.tag in ('defaultNames','flashDefaultName'):e.text='0'
        if e.tag=='flashFileName':e.text=str(project.parent/'NativeInput.swf')
    (project/'PublishSettings.xml').write_bytes(ET.tostring(settings,encoding='utf-8',xml_declaration=True))
    print('Prepared isolated native project: '+str(len(closure))+' symbols.')
