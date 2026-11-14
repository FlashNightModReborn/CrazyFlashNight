"""Create a disposable, memory-only Flash preview of the actual published library."""
import json
import hashlib
import argparse
import uuid
import xml.etree.ElementTree as ET
from pathlib import Path
from build import ROOT, CONFIG, E, layer, frame, xml_bytes

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output-dir', default='tmp/ak47-fire-kylin/NativePreview')
args = parser.parse_args()
out = (ROOT / args.output_dir).resolve()
assert out.is_relative_to((ROOT/'tmp/ak47-fire-kylin').resolve())
out.mkdir(parents=True, exist_ok=True)
nonce = uuid.uuid4().hex
swf_uri = (ROOT / 'flashswf/arts/new/Codex专用素材.swf').as_uri()
code = r'''
import flash.display.*;
import flash.geom.*;
stop();
Stage.scaleMode = "noScale";
Stage.align = "TL";
var prefix:String = "[AK47_NATIVE __NONCE__] ";
var failures:Number = 0;
function check(ok:Boolean, label:String):Void {
    trace(prefix + (ok ? "PASS " : "FAIL ") + label);
    if (!ok) failures++;
}
function label(name:String, text:String, x:Number, y:Number, size:Number):Void {
    _root.createTextField(name, _root.getNextHighestDepth(), x, y, 950, 45);
    var field:TextField = _root[name];
    field.textColor = 0xffffff;
    field.text = text;
    field.setTextFormat(new TextFormat("Arial",size,0xffffff));
}
label("heading","AK47 Fire Kylin - native asset preview",24,14,24);
label("gunLabel","Published vector artwork / __FRAMES__ frames / __SECONDS__s eye flame",24,58,17);
label("iconLabel","24x24 inventory icon",700,245,16);
label("dropLabel","Frame 2: full weapon / drop scale",580,410,16);
label("heldLabel","0.45 character-holder scale",30,405,16);
var loader:MovieClipLoader = new MovieClipLoader();
var listener:Object = {};
listener.onLoadError = function(target:MovieClip, error:String):Void {
    check(false,"library load " + error);
    trace(prefix + "COMPLETE failures=" + failures);
};
listener.onLoadInit = function(lib:MovieClip):Void {
    for (var k:String in lib) {
        if (typeof lib[k] == "movieclip") lib[k]._visible = false;
    }
    var gun:MovieClip = lib.attachMovie("枪-长枪-Codex-AK47火麒麟","newGun",10000);
    check(gun != undefined,"published weapon linkage");
    gun._x = 200; gun._y = 255; gun._xscale = gun._yscale = 150;
    var icon:MovieClip = lib.attachMovie("图标-Codex-AK47火麒麟","newIcon",10001);
    check(icon != undefined && icon._totalframes == 2,"published two-frame icon");
    icon._x = 810; icon._y = 155; icon._xscale = icon._yscale = 700;
    var drop:MovieClip = lib.attachMovie("图标-Codex-AK47火麒麟","newDrop",10002);
    drop.gotoAndStop(2); drop._x=765; drop._y=375;
    var held:MovieClip = lib.attachMovie("枪-长枪-Codex-AK47火麒麟","heldGun",10003);
    held._x=180; held._y=480; held._xscale=held._yscale=45;
    check(gun.动画 != undefined,"named animation MovieClip");
    check(Math.abs(gun.枪口位置._x - 257.65)<0.06 && Math.abs(gun.枪口位置._y +35.1)<0.06,"muzzle interface at barrel mouth");
    var eye:MovieClip = gun.动画.眼焰;
    var cycleFrames:Number=__FRAMES__;
    check(eye != undefined && eye._totalframes == cycleFrames,"8-frame native eye MovieClip");
    var iconEye:MovieClip=icon.眼焰;
    var dropEye:MovieClip=drop.眼焰;
    check(iconEye != undefined && iconEye._totalframes == cycleFrames,"inventory icon has live eye MovieClip");
    check(dropEye != undefined && dropEye._totalframes == cycleFrames,"drop frame has live eye MovieClip");
    var point:Object={x:0,y:0};gun.枪口位置.localToGlobal(point);_root.globalToLocal(point);
    _root.createEmptyMovieClip("muzzleCross",90000);
    var cross:MovieClip=_root.muzzleCross;cross.lineStyle(1,0x33ff55,100);
    cross.moveTo(point.x-10,point.y);cross.lineTo(point.x+10,point.y);
    cross.moveTo(point.x,point.y-10);cross.lineTo(point.x,point.y+10);
    function sample():Number {
        var bitmap:BitmapData=new BitmapData(1200,450,true,0);
        bitmap.draw(eye);
        var value:Number=0;
        for(var yy:Number=85; yy<185; yy+=3) {
            for(var xx:Number=600; xx<755; xx+=3) value=(value+bitmap.getPixel(xx,yy))%2147483629;
        }
        bitmap.dispose(); return value;
    }
    function iconSample():Number {
        var bitmap:BitmapData=new BitmapData(80,80,true,0);
        bitmap.draw(icon,new Matrix(1,0,0,1,40,40));
        var value:Number=0;
        for(var yy:Number=26;yy<55;yy++) {
            for(var xx:Number=26;xx<55;xx++) value=(value+bitmap.getPixel(xx,yy))%2147483629;
        }
        bitmap.dispose();return value;
    }
    var count:Number=-1;var warmup:Number=cycleFrames;
    var firstFrame:Number;var firstIconFrame:Number;var first:Number;var firstIcon:Number;
    var startedAt:Number;var eyeSamples:Object={};var iconSamples:Object={};
    // Establish a baseline from a steady frame callback, after a full warmup.
    // onLoadInit runs before the first descendant timeline advance.
    _root.onEnterFrame=function():Void {
        if(warmup>0) {warmup--;return;}
        count++;
        var gunPixels:Number=sample();var iconPixels:Number=iconSample();
        eyeSamples["v"+gunPixels]=true;iconSamples["v"+iconPixels]=true;
        trace(prefix+"SAMPLE tick="+count+" eye="+eye._currentframe+" iconEye="+iconEye._currentframe+" eyePixels="+gunPixels+" iconPixels="+iconPixels);
        if(count==0) {
            firstFrame=eye._currentframe;firstIconFrame=iconEye._currentframe;
            first=gunPixels;firstIcon=iconPixels;startedAt=getTimer();
            trace(prefix+"START eyeFrame="+firstFrame+" iconEyeFrame="+firstIconFrame);
        }
        if(count==cycleFrames) {
            check(eye._currentframe==firstFrame,"eye returns after exactly 8 steady frame ticks");
            check(sample()==first,"eye loop closes in actual Flash Player pixels");
            check(iconEye._currentframe==firstIconFrame && iconSample()==firstIcon,"inventory icon loop closes with parent stopped");
            trace(prefix+"CYCLE_ELAPSED_MS "+(getTimer()-startedAt));
        }
        if(count==cycleFrames*2) {
            var eyeDistinct:Number=0;var iconDistinct:Number=0;
            for(var eyeKey:String in eyeSamples) eyeDistinct++;
            for(var iconKey:String in iconSamples) iconDistinct++;
            check(eyeDistinct>=4,"multiple visible weapon-eye phases");
            check(iconDistinct>=2,"inventory icon changes actual visible pixels");
            check(eye._currentframe==firstFrame && sample()==first,"second eye cycle closes");
            check(iconEye._currentframe==firstIconFrame && iconSample()==firstIcon,"second icon cycle closes");
            check(gun._currentframe==1 && icon._currentframe==1 && drop._currentframe==2,"parent stop preserves eye motion and semantic icon frames");
            trace(prefix+"DISTINCT weapon="+eyeDistinct+" icon="+iconDistinct);
            trace(prefix+"COMPLETE failures="+failures);
            label("result",failures==0 ? "Native checks PASS - eye flame keeps playing" : "CHECK FAILED",24,535,18);
            delete _root.onEnterFrame;
        }
    };
};
loader.addListener(listener);
var libraryRoot:MovieClip=_root.createEmptyMovieClip("actualLibrary",1);
loader.loadClip("__SWF__",libraryRoot);
'''.replace('__NONCE__', nonce).replace('__SWF__', swf_uri).replace('__FRAMES__',str(CONFIG['cycleFrames'])).replace('__SECONDS__',str(round(CONFIG['cycleFrames']/CONFIG['fps'],3)))

document = E('DOMDocument', {'width': '1000', 'height': '580', 'frameRate': '30',
                            'backgroundColor': '#222B38', 'xflVersion': '2.2',
                            'creatorInfo': 'Adobe Flash Professional CS6',
                            'platform': 'Windows', 'versionInfo': 'Saved by Adobe Flash Windows 12.0 build 481',
                            'majorVersion': '12', 'buildNumber': '481', 'currentTimeline': '1'})
stage = frame(0)
actions = E('Actionscript')
E('script', parent=actions).text = code
stage.insert(0, actions)
E('layers', parent=E('DOMTimeline', {'name': 'NativePreview'}, E('timelines', parent=document))).append(layer('只读内存预览', [stage]))
(out/'DOMDocument.xml').write_bytes(xml_bytes(document))
proxy = out/'NativePreview.xfl'
if not proxy.exists():
    proxy.write_bytes(b'PROXY-CS5')
else:
    assert proxy.read_bytes() == b'PROXY-CS5'
settings = ET.parse(ROOT/'flashswf/arts/new/Codex专用素材/PublishSettings.xml').getroot()
for e in settings.iter():
    if e.tag == 'defaultNames': e.text = '0'
    if e.tag == 'flashFileName': e.text = str(out.parent/'NativePreview.swf')
    if e.tag == 'AS2PackagePaths': e.text = '.'
(out/'PublishSettings.xml').write_bytes(ET.tostring(settings, encoding='utf-8', xml_declaration=True))
(out/'LIBRARY').mkdir(exist_ok=True)
(out/'run.json').write_text(json.dumps({'nonce':nonce,'sourceSWF':swf_uri,
    'sourceSHA256':hashlib.sha256((ROOT/'flashswf/arts/new/Codex专用素材.swf').read_bytes()).hexdigest(),
    'cycleFrames':CONFIG['cycleFrames'],'fps':CONFIG['fps']},ensure_ascii=False),encoding='utf-8')
print(str(out/'NativePreview.xfl'))
