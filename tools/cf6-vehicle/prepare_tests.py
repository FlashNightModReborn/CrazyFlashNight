"""Isolated real-RSL vehicle host; does not launch or compile Flash."""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import re
import xml.etree.ElementTree as ET
from prepare_runtime import literal

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
NS='http://ns.adobe.com/xfl/2008/'
N='{'+NS+'}'
ET.register_namespace('',NS)


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');parser.add_argument('--bind-native',action='store_true');args=parser.parse_args()
    service=(HERE/'Cf6VehicleService.as.txt').read_text(encoding='utf-8-sig')
    default_input=service.split('private static function readInput():Object {',1)[1].split('\n    }',1)[0]
    expected_input='return {x:(Key.isDown(_root.右键)?1:0)-(Key.isDown(_root.左键)?1:0),z:(Key.isDown(_root.下键)?1:0)-(Key.isDown(_root.上键)?1:0),fire:Key.isDown(_root.A键)};'
    if re.sub(r'\s+','',default_input)!=re.sub(r'\s+','',expected_input):
        raise ValueError('native key mapping source fixture changed; review the production input contract')
    source=ROOT/'scripts/Cf6ActorAppearanceNativeHost';dest=ROOT/'scripts/tmp-cf6-vehicle-host'
    doc=ET.parse(source/'DOMDocument.xml').getroot()
    for node in list(doc):doc.remove(node)
    doc.set('width','1024');doc.set('height','768')
    symbols=ET.SubElement(doc,N+'symbols');outputs={}
    names=['CF6Vehicle','CF6VehiclePlayer','CF6VehicleArmoredBoss','CF6VehicleRoad','CF6VehicleRaider','CF6VehicleShield','CF6VehicleRoadblock','CF6VehicleGrenade','CF6VehicleBullet','CF6VehicleSpark','CF6VehicleExplosion']
    for index,name in enumerate(names):
        library='ImportVehicle'+str(index)
        ET.SubElement(symbols,N+'Include',{'href':library+'.xml','loadImmediate':'false'})
        node=ET.Element(N+'DOMSymbolItem',{'name':library,'linkageImportForRS':'true','linkageIdentifier':name,
            'linkageURL':'flashswf/arts/new/CF6Vehicle.swf','linkageExportInFirstFrame':'true'})
        timeline=ET.SubElement(ET.SubElement(node,N+'timeline'),N+'DOMTimeline',{'name':library})
        frame=ET.SubElement(ET.SubElement(ET.SubElement(ET.SubElement(timeline,N+'layers'),N+'DOMLayer',{'name':'RSL'}),N+'frames'),N+'DOMFrame',{'index':'0'})
        ET.SubElement(frame,N+'elements');outputs[dest/'LIBRARY'/(library+'.xml')]=ET.tostring(node,encoding='utf-8',xml_declaration=True)
    # Source helper 1805 has 59 frames, stop() at 1/59, and play() is triggered
    # while resting on 1. This actual AVM1 timeline is independent of the rules counter.
    reference=ET.Element(N+'DOMSymbolItem',{'name':'VehicleIntroClockReference','symbolType':'movie clip'})
    t=ET.SubElement(ET.SubElement(reference,N+'timeline'),N+'DOMTimeline',{'name':'Source1805Clock'})
    frames=ET.SubElement(ET.SubElement(ET.SubElement(t,N+'layers'),N+'DOMLayer',{'name':'original_frame_clock'}),N+'frames')
    for index in range(59):
        f=ET.SubElement(frames,N+'DOMFrame',{'index':str(index),'duration':'1','keyMode':'9728'});ET.SubElement(f,N+'elements')
        if index in (0,58):ET.SubElement(ET.SubElement(f,N+'Actionscript'),N+'script').text='stop();'
    outputs[dest/'LIBRARY/VehicleIntroClockReference.xml']=ET.tostring(reference,encoding='utf-8',xml_declaration=True)
    ET.SubElement(symbols,N+'Include',{'href':'VehicleIntroClockReference.xml','loadImmediate':'false'})
    timeline=ET.SubElement(ET.SubElement(doc,N+'timelines'),N+'DOMTimeline',{'name':'CF6 Vehicle Native'})
    frame=ET.SubElement(ET.SubElement(ET.SubElement(ET.SubElement(timeline,N+'layers'),N+'DOMLayer',{'name':'Fixture'}),N+'frames'),N+'DOMFrame',{'index':'0','keyMode':'9728'})
    ET.SubElement(ET.SubElement(frame,N+'Actionscript'),N+'script').text='stop();\n#include "../TestLoader.as"\n'
    elements=ET.SubElement(frame,N+'elements')
    for index in range(len(names)):
        instance=ET.SubElement(elements,N+'DOMSymbolInstance',{'libraryItemName':'ImportVehicle'+str(index),'name':'__vehicleRsl'+str(index)})
        ET.SubElement(ET.SubElement(instance,N+'color'),N+'Color',{'alphaMultiplier':'0'})
    ET.SubElement(elements,N+'DOMSymbolInstance',{'libraryItemName':'VehicleIntroClockReference','name':'__vehicleIntroClock'})
    outputs[dest/'DOMDocument.xml']=ET.tostring(doc,encoding='utf-8',xml_declaration=True)
    outputs[dest/'Cf6VehicleNativeHost.xfl']=(source/'Cf6ActorAppearanceNativeHost.xfl').read_bytes()
    settings=(source/'PublishSettings.xml').read_text(encoding='utf-8')
    for a,b in [('<PackagePaths>scripts/类定义;scripts;</PackagePaths>','<PackagePaths>类定义;</PackagePaths>'),('<defaultNames>1</defaultNames>','<defaultNames>0</defaultNames>'),('<flashDefaultName>1</flashDefaultName>','<flashDefaultName>0</flashDefaultName>'),('Cf6ActorAppearanceNativeHost.swf','../Cf6VehicleNativeHost.swf')]:
        if settings.count(a)!=1:raise ValueError('native fixture template changed '+a)
        settings=settings.replace(a,b)
    outputs[dest/'PublishSettings.xml']=settings.encode('utf-8')
    boot='trace("FocusedTestRunId cf6-vehicle Start: __FOCUSED_RUN_ID__");\n_root.cf6VehicleTestComplete=function():Void {trace("FocusedTestRunId cf6-vehicle Complete: __FOCUSED_RUN_ID__");};\norg.flashNight.arki.scene.Cf6VehicleTest.runAllTests();\n'
    outputs[HERE/'TestLoader.as.template']=boot.encode('utf-8-sig')
    spec=importlib.util.spec_from_file_location('vehicle_fixture_chapter',HERE/'chapter_fragment.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    node,_,_=module.build()
    data='class org.flashNight.arki.scene.Cf6VehicleTestData {public static function spec():Object {return '+literal(node['mechanism']['vehicle'])+';}}\n'
    outputs[ROOT/'scripts/类定义/org/flashNight/arki/scene/Cf6VehicleTestData.as']=data.encode('utf-8-sig')
    if args.bind_native:
        reader=importlib.util.spec_from_file_location('vehicle_native_identity',ROOT/'tools/cf6-audio/source.py')
        native_reader=importlib.util.module_from_spec(reader);reader.loader.exec_module(native_reader)
        swf=ROOT/'flashswf/arts/new/CF6Vehicle.swf';native=native_reader.Source(swf)
        if set(native.exports.values())!=set(names) or native.sounds or native.events:
            raise ValueError('native vehicle RSL must export exactly eleven names with no embedded audio')
        graph_spec=importlib.util.spec_from_file_location('vehicle_native_graph',HERE/'native_graph.py')
        graph=importlib.util.module_from_spec(graph_spec);graph_spec.loader.exec_module(graph)
        structure=graph.validate(native,native_reader.scan)
        manifest={'schema':'cf6-vehicle-native-fixture.v1','nativeSwf':swf.relative_to(ROOT).as_posix(),'nativeSha256':native.sha256,
            'nativeStructure':structure,
            'exports':sorted(native.exports.values()),'resourceSourceManifestSha256':hashlib.sha256((HERE/'art-manifest.json').read_bytes()).hexdigest(),
            'runtimeManifestSha256':hashlib.sha256((HERE/'runtime-manifest.json').read_bytes()).hexdigest(),
            'fixtureInputs':{p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in [Path(__file__),HERE/'native_graph.py',HERE/'Cf6VehicleTest.as.txt',HERE/'chapter_fragment.py']},
            'generated':{p.relative_to(ROOT).as_posix():hashlib.sha256(raw).hexdigest() for p,raw in outputs.items()},
            'boundary':'direct real-RSL fixture; production things-new import chain and actual player initialization are separate gates'}
        outputs[HERE/'native-fixture-manifest.json']=(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n').encode('utf-8')
    for path,raw in outputs.items():
        if args.check:
            if not path.is_file() or path.read_bytes()!=raw:raise ValueError('stale vehicle fixture '+str(path))
        elif not path.is_file() or path.read_bytes()!=raw:path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(raw)
    print(json.dumps({'state':'checked' if args.check else 'prepared','files':len(outputs)}))


if __name__=='__main__':main()
