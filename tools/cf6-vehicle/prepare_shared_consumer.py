"""A native consumer fixture imports only the production things-new entry."""
from pathlib import Path
import argparse
import xml.etree.ElementTree as ET

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
NS='http://ns.adobe.com/xfl/2008/'
N='{'+NS+'}'
ET.register_namespace('',NS)


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--check',action='store_true');args=parser.parse_args()
    source=ROOT/'scripts/Cf6ActorAppearanceNativeHost';dest=ROOT/'scripts/tmp-cf6-vehicle-shared-host'
    doc=ET.parse(source/'DOMDocument.xml').getroot()
    for node in list(doc):doc.remove(node)
    doc.set('width','1024');doc.set('height','768')
    symbols=ET.SubElement(doc,N+'symbols')
    ET.SubElement(symbols,N+'Include',{'href':'ImportThingsNew.xml','loadImmediate':'false'})
    imported=ET.Element(N+'DOMSymbolItem',{'name':'ImportThingsNew','linkageImportForRS':'true',
        'linkageIdentifier':'things-new','linkageURL':'flashswf/arts/things-new.swf','linkageExportInFirstFrame':'true'})
    timeline=ET.SubElement(ET.SubElement(imported,N+'timeline'),N+'DOMTimeline',{'name':'ImportThingsNew'})
    frame=ET.SubElement(ET.SubElement(ET.SubElement(ET.SubElement(timeline,N+'layers'),N+'DOMLayer',{'name':'RSL'}),N+'frames'),N+'DOMFrame',{'index':'0'})
    ET.SubElement(frame,N+'elements')
    timeline=ET.SubElement(ET.SubElement(doc,N+'timelines'),N+'DOMTimeline',{'name':'CF6 Vehicle Shared Consumer'})
    frame=ET.SubElement(ET.SubElement(ET.SubElement(ET.SubElement(timeline,N+'layers'),N+'DOMLayer',{'name':'Fixture'}),N+'frames'),N+'DOMFrame',{'index':'0','keyMode':'9728'})
    ET.SubElement(ET.SubElement(frame,N+'Actionscript'),N+'script').text='stop();\n#include "../TestLoader.as"\n'
    instance=ET.SubElement(ET.SubElement(frame,N+'elements'),N+'DOMSymbolInstance',{'libraryItemName':'ImportThingsNew','name':'__cf6SharedRoot'})
    ET.SubElement(ET.SubElement(instance,N+'color'),N+'Color',{'alphaMultiplier':'0'})
    settings=(source/'PublishSettings.xml').read_text(encoding='utf-8')
    for a,b in [('<PackagePaths>scripts/类定义;scripts;</PackagePaths>','<PackagePaths>类定义;</PackagePaths>'),
                ('<defaultNames>1</defaultNames>','<defaultNames>0</defaultNames>'),
                ('<flashDefaultName>1</flashDefaultName>','<flashDefaultName>0</flashDefaultName>'),
                ('Cf6ActorAppearanceNativeHost.swf','../Cf6VehicleSharedConsumerHost.swf')]:
        if settings.count(a)!=1:raise ValueError('Shared fixture donor changed '+a)
        settings=settings.replace(a,b)
    outputs={dest/'DOMDocument.xml':ET.tostring(doc,encoding='utf-8',xml_declaration=True),
        dest/'LIBRARY/ImportThingsNew.xml':ET.tostring(imported,encoding='utf-8',xml_declaration=True),
        dest/'Cf6VehicleSharedConsumerHost.xfl':(source/'Cf6ActorAppearanceNativeHost.xfl').read_bytes(),
        dest/'PublishSettings.xml':settings.encode('utf-8')}
    boot='''import flash.display.*;
import flash.geom.*;
trace("FocusedTestRunId cf6-vehicle-shared Start: __FOCUSED_RUN_ID__");
_root.__cf6SharedPassed=0;_root.__cf6SharedFailed=0;
_root.__cf6SharedCheck=function(value:Boolean,message:String):Void {
    if(value) _root.__cf6SharedPassed++;else {_root.__cf6SharedFailed++;trace("[FAIL] CF6VehicleShared: "+message);}
};
_root.__cf6SharedFinish=function():Void {
    delete _root.__cf6SharedPump.onEnterFrame;
    if(_root.__cf6SharedFailed==0 && _root.__cf6SharedPassed==31) {
        // Leave a read-only native display sheet after the behavior terminal, so
        // the actual shared-library pixels can also be inspected in Test Movie.
        var gallery:MovieClip=_root.__cf6SharedWorld;
        gallery.beginFill(0x26313C);gallery.moveTo(0,0);gallery.lineTo(1024,0);gallery.lineTo(1024,768);gallery.lineTo(0,768);gallery.endFill();
        for(var i:Number=0;i<_root.__cf6SharedPump.clips.length;i++) {
            var clip:MovieClip=_root.__cf6SharedPump.clips[i];
            var bounds:Object=clip.getBounds(clip);
            var ratio:Number=Math.min(220/(bounds.xMax-bounds.xMin),180/(bounds.yMax-bounds.yMin));
            clip._xscale=clip._yscale=ratio*100;
            clip._x=14+(i%4)*252-bounds.xMin*ratio;
            clip._y=42+Math.floor(i/4)*244-bounds.yMin*ratio;
            gallery.createTextField("label"+i,100+i,14+(i%4)*252,14+Math.floor(i/4)*244,240,22);
            var label:TextField=gallery["label"+i];label.textColor=0xFFFFFF;
            label.text=_root.__cf6SharedPump.names[i]+" / native frame "+(i>=8?2:1);
        }
    } else _root.__cf6SharedWorld.removeMovieClip();
    trace("Cf6VehicleSharedConsumerTest Tests Passed: "+_root.__cf6SharedPassed);
    trace("Cf6VehicleSharedConsumerTest Tests Failed: "+_root.__cf6SharedFailed);
    trace("FocusedTestRunId cf6-vehicle-shared Complete: __FOCUSED_RUN_ID__");
};
_root.__cf6SharedRoot.gotoAndStop(4);
var sharedPump:MovieClip=_root.createEmptyMovieClip("__cf6SharedPump",_root.getNextHighestDepth());
sharedPump.age=0;sharedPump.phase=0;
sharedPump.onEnterFrame=function():Void {
    if(++this.age>360) {_root.__cf6SharedCheck(false,"production shared entry did not become ready");_root.__cf6SharedFinish();return;}
    if(this.phase==0) {
        if(_root.__cf6SharedRoot._currentframe!=4) return;
        _root.__cf6SharedCheck(true,"production things-new frame4 loaded");
        this.names=["Player","ArmoredBoss","Road","Raider","Shield","Roadblock","Grenade","Bullet","Spark","Explosion"];
        this.ids=[1803,1813,1791,612,629,627,361,356,115,391];
        var world:MovieClip=_root.createEmptyMovieClip("__cf6SharedWorld",_root.getNextHighestDepth());
        this.clips=[];
        for(var i:Number=0;i<this.names.length;i++) {
            var clip:MovieClip=world.attachMovie("CF6Vehicle"+this.names[i],"actor"+i,i+1);
            _root.__cf6SharedCheck(typeof clip=="movieclip","dynamic attach through production shared entry: "+this.names[i]);
            this.clips.push(clip);
        }
        this.phase=1;this.age=0;return;
    }
    if(this.age<2) return;
    if(this.phase==1) {
        for(var i:Number=0;i<this.names.length;i++) {
            var clip:MovieClip=this.clips[i];
            _root.__cf6SharedCheck(clip.__cf6SourceId==this.ids[i],"actual exported source identity: "+this.names[i]);
            clip._visible=true;clip._alpha=100;
            // The original spark/explosion frame 1 is intentionally empty.
            clip.gotoAndStop(i>=8?2:1);
        }
        this.phase=2;this.age=0;return;
    }
    for(var i:Number=0;i<this.names.length;i++) {
        var clip:MovieClip=this.clips[i];
        var visible:Boolean=false;
        if(clip._width>0 && clip._height>0) {
            var rect:Object=clip.getBounds(clip);
            var scale:Number=Math.min(60/(rect.xMax-rect.xMin),60/(rect.yMax-rect.yMin));
            var matrix:Matrix=new Matrix(scale,0,0,scale,2-rect.xMin*scale,2-rect.yMin*scale);
            var pixels:BitmapData=new BitmapData(64,64,true,0);pixels.draw(clip,matrix);
            for(var y:Number=0;y<64 && !visible;y++) for(var x:Number=0;x<64;x++) if((pixels.getPixel32(x,y)>>>24)>0) {visible=true;break;}
            pixels.dispose();
        }
        _root.__cf6SharedCheck(visible,"production shared consumer has real native pixels: "+this.names[i]);
    }
    _root.__cf6SharedFinish();
};
'''
    class_body=boot.replace('import flash.display.*;\nimport flash.geom.*;\n','',1)
    class_body=class_body.replace('trace("FocusedTestRunId cf6-vehicle-shared Start: __FOCUSED_RUN_ID__");\n','',1)
    class_body=class_body.replace('trace("FocusedTestRunId cf6-vehicle-shared Complete: __FOCUSED_RUN_ID__");','_root.cf6VehicleSharedComplete();',1)
    class_source='import flash.display.BitmapData;\nimport flash.geom.Matrix;\nclass org.flashNight.arki.scene.Cf6VehicleSharedConsumerTest {\n    public static function runAllTests():Void {\n'+class_body+'\n    }\n}\n'
    outputs[ROOT/'scripts/类定义/org/flashNight/arki/scene/Cf6VehicleSharedConsumerTest.as']=class_source.encode('utf-8-sig')
    entry='trace("FocusedTestRunId cf6-vehicle-shared Start: __FOCUSED_RUN_ID__");\n_root.cf6VehicleSharedComplete=function():Void {trace("FocusedTestRunId cf6-vehicle-shared Complete: __FOCUSED_RUN_ID__");};\norg.flashNight.arki.scene.Cf6VehicleSharedConsumerTest.runAllTests();\n'
    outputs[HERE/'SharedConsumer.TestLoader.as.template']=entry.encode('utf-8-sig')
    for path,data in outputs.items():
        if args.check:
            if not path.is_file() or path.read_bytes()!=data:raise ValueError('stale shared consumer fixture '+str(path))
        elif not path.is_file() or path.read_bytes()!=data:
            path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data)
    print('Shared consumer fixture '+('checked' if args.check else 'prepared')+'; direct RSL imports are absent')


if __name__=='__main__':main()
