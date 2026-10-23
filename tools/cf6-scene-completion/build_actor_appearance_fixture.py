"""Reproducible native appearance test host; never edits production assets or writes SWF."""
from pathlib import Path
import argparse, hashlib, json, xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[2]
DEST=ROOT/'scripts/Cf6ActorAppearanceNativeHost'
N='{http://ns.adobe.com/xfl/2008/}'
ET.register_namespace('',N[1:-1])
def digest(data): return hashlib.sha256(data).hexdigest()
def element(tag,attrs=None,parent=None):
    node=ET.Element(N+tag,attrs or {})
    if parent is not None: parent.append(node)
    return node
def xml(root): return ET.tostring(root,encoding='utf-8',xml_declaration=True)
def build():
    outputs={};inputs={}
    def read(path):
        data=path.read_bytes();inputs[path.relative_to(ROOT).as_posix()]=digest(data);return data
    read(Path(__file__))
    seed=ROOT/'scripts/ShootReloadNativeHost'
    document=ET.fromstring(read(seed/'DOMDocument.xml'))
    document.set('width','600');document.set('height','600')
    document.find('.//'+N+'DOMTimeline').set('name','CF6 Native Appearance')
    symbols=document.find(N+'symbols')
    outputs[DEST/'LIBRARY/Import0.xml']=read(seed/'LIBRARY/Import0.xml')
    import1=ET.fromstring(outputs[DEST/'LIBRARY/Import0.xml'])
    import1.set('name','Import1');import1.set('itemID','6af00000-16400002')
    import1.set('linkageIdentifier','加载MC库0');import1.set('linkageURL','flashswf/arts/things.swf')
    import1.find('.//'+N+'DOMTimeline').set('name','Import1')
    outputs[DEST/'LIBRARY/Import1.xml']=xml(import1)
    element('Include',{'href':'Import1.xml','loadImmediate':'false'},symbols)
    stage_elements=document.find('.//'+N+'DOMFrame/'+N+'elements')
    element('DOMSymbolInstance',{'libraryItemName':'Import1','name':'__appearanceEquipmentRsl'},stage_elements)
    # Recompile these exact production XML bytes, with their authored mask intact.
    original=ROOT/'flashswf/arts/things0/LIBRARY'
    for name in ['特效与子弹/目镜特效','特效与子弹/战术目镜特效']:
        data=read(original/(name+'.xml'));tree=ET.fromstring(data)
        if any((s.text or '').strip() for s in tree.iter(N+'script')):
            raise ValueError('native mask fixture closure acquired executable behavior')
        outputs[DEST/'LIBRARY'/(name+'.xml')]=data
        element('Include',{'href':name+'.xml','loadImmediate':'false'},symbols)
    wrapper=element('DOMSymbolItem',{'name':'Cf6NativeAuthoredMask','symbolType':'movie clip',
        'linkageExportForAS':'true','linkageExportInFirstFrame':'true','linkageIdentifier':'Cf6NativeAuthoredMask'})
    timeline=element('DOMTimeline',{'name':'Cf6NativeAuthoredMask'},element('timeline',parent=wrapper))
    frame=element('DOMFrame',{'index':'0','duration':'1','keyMode':'9728'},element('frames',parent=element('DOMLayer',{'name':'Original'},element('layers',parent=timeline))))
    element('script',parent=element('Actionscript',parent=frame)).text='stop();'
    element('DOMSymbolInstance',{'libraryItemName':'特效与子弹/目镜特效','name':'nativeShape','symbolType':'movie clip'},element('elements',parent=frame))
    outputs[DEST/'LIBRARY/Cf6NativeAuthoredMask.xml']=xml(wrapper)
    element('Include',{'href':'Cf6NativeAuthoredMask.xml','loadImmediate':'false'},symbols)
    outputs[DEST/'DOMDocument.xml']=xml(document)
    settings=ET.fromstring(read(seed/'PublishSettings.xml'))
    settings.find('.//PublishFormatProperties/flashFileName').text='Cf6ActorAppearanceNativeHost.swf'
    outputs[DEST/'PublishSettings.xml']=xml(settings)
    outputs[DEST/'Cf6ActorAppearanceNativeHost.xfl']=read(seed/'ShootReloadNativeHost.xfl')
    manifest={'schema':'cf6-native-appearance-fixture.v1','state':'source-only','inputs':inputs,
        'limits':'Native hero and declared XML fixture equipment; no real slot, game bootstrap or complete-game claim.',
        'outputs':{p.relative_to(ROOT).as_posix():{'sha256':digest(d),'bytes':len(d)} for p,d in outputs.items()}}
    return outputs,manifest
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args()
    outputs,manifest=build();path=DEST/'source-manifest.json'
    if not args.check:
        previous=json.loads(path.read_text(encoding='utf-8'))['outputs'] if path.exists() else {}
        for target in outputs:
            if target.exists():
                owned=previous.get(target.relative_to(ROOT).as_posix())
                if not owned or digest(target.read_bytes())!=owned['sha256']:
                    raise ValueError('changed or unowned fixture source: '+str(target))
    outputs[path]=(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n').encode('utf-8')
    for target,data in outputs.items():
        if args.check:
            if not target.exists() or target.read_bytes()!=data:raise ValueError('stale fixture: '+str(target))
        else:
            target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(data)
    print('native appearance fixture: '+str(len(outputs))+' source files '+('checked' if args.check else 'built'))