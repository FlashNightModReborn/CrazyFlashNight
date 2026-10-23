"""Read-only preparation audit; it does not compile, run a game or write a save."""
from pathlib import Path
import argparse
import hashlib
import json
import xml.etree.ElementTree as ET

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
NS={'x':'http://ns.adobe.com/xfl/2008/'}


def read(path):return json.loads(path.read_text(encoding='utf-8-sig'))
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def require(value,message):
    if not value:raise ValueError(message)


def verify(compiled=False):
    facts=read(HERE/'source-evidence/original.json')
    require(facts['swfSha256']=='b52af10e2dda43332e0b2ffb9549d2fad474f298b9f6c67d848ffc33ff589b01','original identity')
    require(facts['extractorSha256']==sha(HERE/'extract_source.py'),'source extractor drift')
    require(facts['geometryParserSha256']==sha(ROOT/'tools/cf6-map-runtime/extract-geometry.py'),'geometry parser drift')
    require(facts['shapeParserSha256']==sha(ROOT/'tools/swf-audit/swfscan.py'),'shape parser drift')
    captured=set()
    for action in facts['actions']:
        p=HERE/action['capture'];require(sha(p)==action['sha256'],'action changed: '+str(p));captured.add(p.resolve())
    require({p.resolve() for p in (HERE/'source-evidence/actions').glob('*')}==captured,'unexpected action captures')
    plan=read(HERE/'completion-plan.json')
    require(plan['evidenceSha256']==sha(HERE/'source-evidence/original.json'),'plan evidence drift')
    require(plan['productionChapterSha256']==sha(ROOT/'data/stages/books/cf6-sting.json'),'production chapter changed; rebase plan before use')
    chapter=read(ROOT/'data/stages/books/cf6-sting.json')
    require('A07' not in [m['id'] for m in chapter['maps']],'preparation must not activate A07')
    require({t['id'] for t in plan['traversals']}=={'A03-depart','A04-arrive','A04-depart','A05-arrive','A05-depart'},'door route closure')
    require(plan['vehicle']['economy']['relocateGold']==40000,'existing transition allowance changed')
    for p in plan['reuse']:require(sha(ROOT/p['path'])==p['sha256'],'reuse source drift')
    art=read(HERE/'traversal-art-manifest.json');vehicle=read(HERE/'vehicle-art-manifest.json')
    auxiliary_path=HERE/'auxiliary-art-manifest.json'
    auxiliary=read(auxiliary_path) if auxiliary_path.is_file() else None
    if auxiliary is not None:
        require(auxiliary['schema']=='cf6-auxiliary-native-source.v1','auxiliary source schema')
    interactive_path=HERE/'interactive-art-manifest.json'
    interactive=read(interactive_path) if interactive_path.is_file() else None
    if interactive is not None:
        require(interactive['schema']=='cf6-interactive-native-source.v1','interactive source schema')
        require(interactive['originalSha256']==facts['swfSha256'],'interactive original identity')
    transport_path=HERE/'transport-art-manifest.json'
    transport=read(transport_path) if transport_path.is_file() else None
    if transport is not None:
        require(transport['schema']=='cf6-transport-native-source.v1','transport source schema')
        require(transport['originalSha256']==facts['swfSha256'],'transport original identity')
        require(transport['textureSeed']=='flashswf/backgrounds/cf6/preparation/CF6_TransportTextureSeed/CF6_TransportTextureSeed.xfl',
                'transport texture seed identity')
        require([(a['name'],a['sourceSprite'],a['frames'],a['xfl'],a['swf']) for a in transport['assets']]==[
            ('CF6_Transport1868',1868,29,
             'flashswf/backgrounds/cf6/preparation/CF6_Transport1868/CF6_Transport1868.xfl',
             'flashswf/backgrounds/cf6/preparation/CF6_Transport1868.swf')], 'transport asset identity')
    output_files=set();output_bytes=0
    for manifest in [art,vehicle]+[m for m in (auxiliary,interactive,transport) if m is not None]:
        for path,identity in manifest['inputs'].items():require(sha(ROOT/path)==identity,'art input changed: '+path)
        for path,identity in manifest['outputs'].items():
            p=ROOT/path;require(sha(p)==identity['sha256'] and p.stat().st_size==identity['bytes'],'art output changed: '+path)
            output_files.add(path);output_bytes+=identity['bytes']
    for asset in art['assets']:
        xfl=ROOT/asset['xfl'];doc=ET.parse(xfl.parent/'DOMDocument.xml')
        frames=doc.findall('.//x:DOMTimeline/x:layers/x:DOMLayer/x:frames/x:DOMFrame',NS)
        require(len(frames)==asset['frames'],'incomplete authored door timeline')
        require([int(f.get('index')) for f in frames]==list(range(asset['frames'])),'door frame order')
        definitions={}
        for inc in doc.findall('./x:symbols/x:Include',NS):
            p=xfl.parent/'LIBRARY'/inc.get('href');tree=ET.parse(p)
            name=tree.getroot().get('name');require(name not in definitions,'duplicate symbol');definitions[name]=tree
        for tree in [doc]+list(definitions.values()):
            for script in tree.findall('.//x:Actionscript/x:script',NS):
                require((script.text or '').strip() in ('stop();','stop();content.setMask(maskShape);'),
                        'unexpected action outside generated stop/native-mask initialization')
            for node in tree.findall('.//x:DOMSymbolInstance',NS):require(node.get('libraryItemName') in definitions,'unresolved symbol')
            require(not tree.findall('.//x:DOMBitmapInstance',NS),'door art unexpectedly flattened')
    mask={a['sourceSprite']:a['maskActiveFrames'] for a in art['assets'] if a['role']=='Mask'}
    require(mask[1720]==list(range(136,175)) and mask[1729]==list(range(1,40)),'actor mask source range drift')
    require(mask[1750]==[],'grand door must not acquire invented actor mask')
    for asset in vehicle['assets']:
        require(asset['state'].startswith('vector-fragments-ready'),'unsupported vehicle art remains')
        fragment=HERE/'vehicle-art'/asset['role']
        definitions={ET.parse(p).getroot().get('name') for p in (fragment/'LIBRARY').rglob('*.xml')}
        textures={Path(t['path']).name for t in asset['intrinsicTextures']}
        for p in [fragment/'timeline.xml']+list((fragment/'LIBRARY').rglob('*.xml')):
            tree=ET.parse(p)
            for node in tree.findall('.//x:DOMSymbolInstance',NS):require(node.get('libraryItemName') in definitions,'vehicle symbol missing')
            for node in tree.iter():
                if node.get('bitmapPath') is not None:require(node.get('bitmapPath') in textures,'vehicle texture missing')
        require((fragment/'import-textures.jsfl').is_file(),'missing native import recipe')
    present = {p.relative_to(ROOT).as_posix() for p in
               (ROOT/'flashswf/backgrounds/cf6/preparation').rglob('*.swf')}
    resources = {}
    if compiled:
        allowed = {str(Path(a['xfl']).parent.parent/(a['name']+'.swf')).replace('\\','/')
                   for a in art['assets'] if a['name']!='CF6_Traversal1750_Mask'}
        required = {p for p in allowed if not p.endswith('CF6_Traversal1750_Front.swf')}
        if auxiliary is not None:
            auxiliary_swfs = {str(Path(a['xfl']).parent.parent/(a['name']+'.swf')).replace('\\','/')
                              for a in auxiliary['assets']}
            allowed.update(auxiliary_swfs);required.update(auxiliary_swfs)
        if interactive is not None:
            interactive_swfs={a['swf'] for a in interactive['assets']}
            allowed.update(interactive_swfs);required.update(interactive_swfs)
        if transport is not None:
            transport_swfs={a['swf'] for a in transport['assets']}
            allowed.update(transport_swfs);required.update(transport_swfs)
        require(required <= present,'compiled traversal resource is missing')
        require(present <= allowed,'unregistered preparation SWF')
        require(not any(p.endswith('CF6_Traversal1750_Mask.swf') for p in present),
                'empty grand-door mask cannot be a runtime resource')
        for p in sorted(allowed & present):
            raw=(ROOT/p).read_bytes()
            require(raw[:3] in (b'FWS',b'CWS',b'ZWS') and len(raw)>8,'invalid SWF resource: '+p)
            resources[p]={'bytes':len(raw),'sha256':sha(ROOT/p)}
    else:
        require(not present,'source-only preparation contains SWF; use --compiled after the owned CS6 stage')
    print(json.dumps({'state':'source_resource_identity_verified','actionRecords':len(facts['actions']),
                      'nativeDoorSources':len(art['assets']),'vehicleArtInputs':len(vehicle['assets']),
                      'derivedFiles':len(output_files),'derivedBytes':output_bytes,
                      'compiledResourcesPresent':resources,
                      'limits':'source/resource identity audit only; fresh compiler, actor behavior and game acceptance need their own receipts'}))


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--compiled',action='store_true')
    verify(parser.parse_args().compiled)
