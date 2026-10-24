import flash.display.BitmapData;
import flash.geom.Matrix;
class org.flashNight.arki.scene.Cf6VehicleSharedConsumerTest {
    public static function runAllTests():Void {
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
    _root.cf6VehicleSharedComplete();
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

    }
}
