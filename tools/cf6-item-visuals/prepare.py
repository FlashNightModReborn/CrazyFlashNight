"""Independent source-only native item consumer; never touches shared test hosts or SWFs."""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
HOST = ROOT / 'tmp-cf6-item-visuals-host'
TEST = ROOT / 'scripts/类定义/org/flashNight/arki/scene/Cf6ItemVisualTest.as'
N = '{http://ns.adobe.com/xfl/2008/}'
ET.register_namespace('', N[1:-1])


def sha(data):
    return hashlib.sha256(data).hexdigest()


def build(check=False):
    inputs = {}
    def read(path):
        data = path.read_bytes()
        inputs[path.relative_to(ROOT).as_posix()] = {'sha256': sha(data), 'bytes': len(data)}
        return data
    read(Path(__file__))
    read(HERE/'run-tests.ps1')
    read(HERE/'check-fixture.py')
    rifles = ROOT / 'data/items/武器_长枪_突击步枪.xml'
    items = ET.fromstring(read(rifles)).findall('item')
    matches = [item for item in items if item.findtext('name') == 'SAI GRY 幽灵']
    if len(matches) != 1 or matches[0].findtext('icon') != 'CAR' or matches[0].findtext('data/dressup') != '枪-长枪-CAR':
        raise ValueError('expected the single existing SAI compatibility mapping; do not change it in this fixture')
    source_map = ET.fromstring(read(ROOT / 'data/items/asset_source_map.xml'))
    library = 'flashswf/arts/new/3102&Leave.swf'
    for linkage in ['图标-CAR', '枪-长枪-CAR']:
        found = [row for row in source_map.iter('asset') if row.get('id') == linkage]
        if len(found) != 1 or found[0].get('swf') != library:
            raise ValueError('CAR linkage no longer has its exact original library: ' + linkage)
    parser = ROOT / 'tools/cf6-story-migration/cf6swf.py'
    read(parser)
    sys.path.insert(0, str(parser.parent))
    from cf6swf import Swf
    data = read(ROOT / library)
    swf = Swf(str(ROOT / library))
    exports = {name: cid for cid, name in swf.exports.items()}
    for linkage in ['图标-CAR', '枪-长枪-CAR']:
        if linkage not in exports:
            raise ValueError('actual published RSL lacks ' + linkage)
    read(ROOT / 'flashswf/arts/things0.swf')
    read(ROOT / 'flashswf/arts/things.swf')
    hero_source = ET.fromstring(read(ROOT/'flashswf/arts/things0/LIBRARY/主角-男.xml'))
    leg_sources = ['移动射击动画层/长枪-手枪2行走右腿', '移动射击动画层/长枪-手枪行走左腿']
    native_legs = {}
    for name in leg_sources:
        authored = ET.fromstring(read(ROOT/('flashswf/arts/things0/LIBRARY/'+name+'.xml')))
        total = max(int(f.get('index'))+int(f.get('duration','1')) for f in authored.iter(N+'DOMFrame'))
        active = [instance for layer in hero_source.iter(N+'DOMLayer')
            for f in layer.findall('./'+N+'frames/'+N+'DOMFrame')
            if int(f.get('index'))<=151<int(f.get('index'))+int(f.get('duration','1'))
            for instance in f.findall('./'+N+'elements/'+N+'DOMSymbolInstance')
            if instance.get('libraryItemName')==name]
        if total!=22 or len(active)!=1 or 'play();' not in ''.join(active[0].itertext()):
            raise ValueError('native walking-leg discovery assumptions changed: '+name)
        native_legs[name]={'authoredFrames':total,'heroFrameIndex':151,'runtimeIdentity':'direct unnamed child, exact frame count; require exactly two'}
    read(ROOT / 'scripts/类定义/org/flashNight/arki/unit/UnitComponent/Dressup/DressupReferenceManager.as')
    seed = ROOT / 'scripts/Cf6ActorAppearanceNativeHost'
    document = ET.Element(N + 'DOMDocument', {'width':'600','height':'600','frameRate':'30',
        'xflVersion':'2.2','creatorInfo':'Adobe Flash Professional CS6','platform':'Windows'})
    symbols = ET.SubElement(document, N + 'symbols')
    timeline = ET.SubElement(ET.SubElement(document, N + 'timelines'), N + 'DOMTimeline', {'name':'CF6 Item Visuals'})
    frame = ET.SubElement(ET.SubElement(ET.SubElement(ET.SubElement(timeline,N+'layers'),N+'DOMLayer',{'name':'Original RSL'}),N+'frames'),N+'DOMFrame',{'index':'0','keyMode':'9728'})
    ET.SubElement(ET.SubElement(frame,N+'Actionscript'),N+'script').text = 'stop();\n#include "../scripts/TestLoader.as"\n'
    elements = ET.SubElement(frame,N+'elements')
    outputs = {}
    imports = [('Hero','加载MC库-00','flashswf/arts/things0.swf'),
               ('Base','加载MC库0','flashswf/arts/things.swf'),
               ('CarGun','枪-长枪-CAR',library), ('CarIcon','图标-CAR',library)]
    for label, linkage, url in imports:
        name = 'ItemImport' + label
        ET.SubElement(symbols,N+'Include',{'href':name+'.xml','loadImmediate':'false'})
        ET.SubElement(elements,N+'DOMSymbolInstance',{'libraryItemName':name,'name':'__item'+label+'Rsl'})
        symbol = ET.Element(N+'DOMSymbolItem',{'name':name,'linkageImportForRS':'true',
            'linkageIdentifier':linkage,'linkageURL':url,'linkageExportInFirstFrame':'true'})
        inner = ET.SubElement(ET.SubElement(symbol,N+'timeline'),N+'DOMTimeline',{'name':name})
        inner_frame=ET.SubElement(ET.SubElement(ET.SubElement(ET.SubElement(inner,N+'layers'),N+'DOMLayer',{'name':'RSL'}),N+'frames'),N+'DOMFrame',{'index':'0','keyMode':'9728'})
        ET.SubElement(inner_frame,N+'elements')
        outputs[HOST/'LIBRARY'/(name+'.xml')] = ET.tostring(symbol,encoding='utf-8',xml_declaration=True)
    outputs[HOST/'DOMDocument.xml'] = ET.tostring(document,encoding='utf-8',xml_declaration=True)
    outputs[HOST/'Cf6ItemVisualNativeHost.xfl'] = read(seed/'Cf6ActorAppearanceNativeHost.xfl')
    settings = ET.fromstring(read(seed/'PublishSettings.xml'))
    settings.find('.//PublishFormatProperties/defaultNames').text = '0'
    settings.find('.//PublishFormatProperties/flashDefaultName').text = '0'
    # Root-level XFL testMovie resolves this name from the document's parent root.
    # A ../ prefix escapes CrazyFlashNight and also rebases the real RSL URLs.
    settings.find('.//PublishFormatProperties/flashFileName').text = 'Cf6ItemVisualNativeHost.swf'
    outputs[HOST/'PublishSettings.xml'] = ET.tostring(settings,encoding='utf-8',xml_declaration=True)
    test = read(HERE/'Cf6ItemVisualTest.as.txt')
    outputs[TEST] = b'\xef\xbb\xbf' + test
    template = 'trace("FocusedTestRunId cf6-item-visuals Start: __FOCUSED_RUN_ID__");\n'
    template += '_root.cf6ItemVisualComplete=function():Void {trace("FocusedTestRunId cf6-item-visuals Complete: __FOCUSED_RUN_ID__");};\n'
    template += 'org.flashNight.arki.scene.Cf6ItemVisualTest.runAllTests();\n'
    outputs[HERE/'TestLoader.as.template'] = b'\xef\xbb\xbf' + template.encode('utf-8')
    manifest = {'schema':'cf6-item-visual-native-fixture.v1','state':'source-prepared-not-executed',
        'expectedAssertions':54,'inputs':inputs,'nativeWalkingLegs':native_legs,
        'actualRslExports':{name:exports[name] for name in ['图标-CAR','枪-长枪-CAR']},
        'target':'tmp-cf6-item-visuals-host/Cf6ItemVisualNativeHost.xfl',
        'swf':'Cf6ItemVisualNativeHost.swf',
        'boundary':'Actual production XMLParser and native hero gun rack; does not certify full soldier initialization, combat, physical drops or player acceptance.',
        'outputs':{path.relative_to(ROOT).as_posix():{'sha256':sha(raw),'bytes':len(raw)} for path,raw in outputs.items()}}
    manifest_path = HERE/'source-manifest.json'
    previous = json.loads(manifest_path.read_text(encoding='utf-8')) if manifest_path.exists() else None
    if not check and previous:
        for ref,identity in previous['outputs'].items():
            path=ROOT/ref
            if path.exists() and sha(path.read_bytes())!=identity['sha256']:
                raise ValueError('preserve externally changed fixture source: '+ref)
    outputs[manifest_path] = (json.dumps(manifest,ensure_ascii=False,indent=2)+'\n').encode('utf-8')
    for path,raw in outputs.items():
        if path.exists() and path.read_bytes()==raw:
            continue
        if check:
            raise ValueError('stale native item fixture: '+path.relative_to(ROOT).as_posix())
        if path==TEST and not path.exists():
            path.parent.mkdir(parents=True,exist_ok=True)
            shutil.copyfile(ROOT/'scripts/类定义/org/flashNight/arki/scene/Cf6ActorAppearanceTest.as',path)
        path.parent.mkdir(parents=True,exist_ok=True)
        path.write_bytes(raw)
    print(json.dumps({'state':'checked' if check else 'source-prepared','outputs':len(outputs),
        'assertions':54,'CAR_RSL_bytes':len(data),'CAR_RSL_sha256':sha(data)},ensure_ascii=False))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--check',action='store_true')
    build(parser.parse_args().check)
