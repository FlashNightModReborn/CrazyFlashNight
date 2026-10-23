import flash.display.BitmapData;
import flash.geom.Matrix;

/** Actual 73-frame native asset probe; geometry alpha bounds are measured pixels. */
class org.flashNight.arki.scene.Cf6InteractiveAssetsTest {
    private static var fixture:MovieClip;
    private static var driver:MovieClip;
    private static var rows:Array;
    private static var entry:Object;
    private static var index:Number;
    private static var passed:Number;
    private static var failed:Number;
    private static var visited:Number;
    private static var done:Boolean;
    private static var bitmap:BitmapData;
    private static var first:BitmapData;
    private static var previousAttach:Function;
    private static var previousShoot:Object;
    private static var businessCalls:Number;
    private static function check(ok:Boolean,label:String):Void {
        if(ok) passed++;else {failed++;trace("[FAIL] Cf6InteractiveAssets: "+label);}
    }
    public static function runAllTests():Void {
        passed=failed=visited=businessCalls=0;index=-1;done=false;
        rows=[{name:"CF6_InteractiveBarrel1736",frames:16,emptyFrom:16},
            {name:"CF6_InteractiveBarrel1838",frames:16,emptyFrom:16},
            {name:"CF6_InteractiveBarrel1976",frames:16,emptyFrom:16},
            {name:"CF6_InteractivePod1939",frames:25,emptyFrom:24}];
        previousAttach=_root.attachMovie;previousShoot=_root.shoot;
        _root.attachMovie=function():MovieClip {org.flashNight.arki.scene.Cf6InteractiveAssetsTest.businessCall();return null;};
        _root.shoot=function():Void {org.flashNight.arki.scene.Cf6InteractiveAssetsTest.businessCall();};
        fixture=_root.createEmptyMovieClip("__cf6InteractiveAssets",_root.getNextHighestDepth());
        fixture._visible=false;
        driver=_root.createEmptyMovieClip("__cf6InteractiveAssetsWatch",_root.getNextHighestDepth());
        driver.onEnterFrame=function():Void {org.flashNight.arki.scene.Cf6InteractiveAssetsTest.tick();};
        bitmap=new BitmapData(1024,1024,true,0);
        next();
    }
    public static function businessCall():Void {businessCalls++;}
    private static function next():Void {
        if(entry!=null) {entry.loader.removeListener(entry.listener);entry.clip.removeMovieClip();}
        if(first!=null) {first.dispose();first=null;}
        index++;
        if(index==rows.length) {check(visited==73,"73 actual native frames visited");finish();return;}
        entry=rows[index];entry.tick=0;entry.frame=1;entry.settle=0;entry.correct=true;
        entry.nonempty=0;entry.changed=0;entry.unclipped=true;entry.stopped=true;entry.businessStart=businessCalls;
        entry.clip=fixture.createEmptyMovieClip("asset"+index,index);
        entry.loader=new MovieClipLoader();entry.listener={row:entry,
            onLoadInit:function(mc:MovieClip):Void {org.flashNight.arki.scene.Cf6InteractiveAssetsTest.loaded(this.row,mc);},
            onLoadError:function(mc:MovieClip,error:String):Void {org.flashNight.arki.scene.Cf6InteractiveAssetsTest.loadError(this.row,error);}};
        entry.loader.addListener(entry.listener);
        check(entry.loader.loadClip("../flashswf/backgrounds/cf6/preparation/"+entry.name+".swf",entry.clip),"request actual "+entry.name);
    }
    public static function loaded(row:Object,mc:MovieClip):Void {
        if(done || row!==entry || mc!==row.clip || row.ready===true) return;
        row.ready=true;check(mc._totalframes===row.frames,"native frame count "+row.name);
        mc.gotoAndStop(1);
    }
    public static function loadError(row:Object,error:String):Void {
        if(done || row!==entry) return;
        check(false,"load "+row.name+" "+error);finish();
    }
    private static function tick():Void {
        if(done) return;
        if(entry.ready!==true) {entry.tick++;if(entry.tick>300) {check(false,"asset timeout "+entry.name);finish();}return;}
        // Give nested native bitmap masks three real AVM1 frame turns to initialize.
        entry.settle++;
        if(entry.clip._currentframe!==entry.frame) entry.stopped=false;
        if(entry.settle<3) return;
        var f:Number=entry.frame;
        bitmap.fillRect(bitmap.rectangle,0);
        bitmap.draw(entry.clip,new Matrix(1,0,0,1,512,768));
        var box:Object=bitmap.getColorBoundsRect(0xFF000000,0,false);
        var visible:Boolean=box.width>0 && box.height>0;
        if(visible) {
            entry.nonempty++;
            if(box.x<=0 || box.y<=0 || box.right>=1024 || box.bottom>=1024) entry.unclipped=false;
        }
        if(visible!==(f<entry.emptyFrom) || entry.clip._currentframe!==f) entry.correct=false;
        if(f==1) {
            check(visible,"first frame has actual alpha "+entry.name);
            first=bitmap.clone();
            trace("Cf6InteractiveAssets AlphaBounds: "+entry.name+" frame=1 left="+(box.x-512)+" top="+(box.y-768)+" right="+(box.right-512)+" bottom="+(box.bottom-768)+" width="+box.width+" height="+box.height+" pixelScale=1 canvas=[-512,-768,512,256]");
        } else if(f<entry.emptyFrom) {
            var delta:Object=bitmap.compare(first);
            if(delta instanceof BitmapData) {entry.changed++;delta.dispose();}
        }
        visited++;
        if(f<entry.frames) {entry.frame++;entry.settle=0;entry.clip.gotoAndStop(entry.frame);return;}
        check(entry.correct,"all native visible/empty frame contracts "+entry.name);
        check(!visible,"original terminal frame is empty "+entry.name);
        check(entry.changed>0,"nonempty演出 frames change pixels "+entry.name);
        check(entry.unclipped,"alpha never touches capture boundary "+entry.name);
        check(entry.stopped,"root frames do not autoplay "+entry.name);
        check(businessCalls==entry.businessStart && entry.clip.hp==undefined && entry.clip.onEnterFrame==undefined,
            "root business probes unchanged and no legacy hp/onEnterFrame "+entry.name);
        trace("Cf6InteractiveAssets NativeFrames: "+entry.name+" checked="+entry.frames+" nonempty="+entry.nonempty+" changedNonempty="+entry.changed+" businessCalls="+(businessCalls-entry.businessStart));
        next();
    }
    private static function finish():Void {
        if(done) return;done=true;
        if(entry!=null) entry.loader.removeListener(entry.listener);
        delete driver.onEnterFrame;driver.removeMovieClip();fixture.removeMovieClip();bitmap.dispose();
        if(first!=null) {first.dispose();first=null;}
        _root.attachMovie=previousAttach;
        if(previousShoot==undefined) delete _root.shoot;else _root.shoot=previousShoot;
        trace("Cf6InteractiveAssetsTest Tests Passed: "+passed);
        trace("Cf6InteractiveAssetsTest Tests Failed: "+failed);
        _root.cf6InteractiveAssetsComplete();
    }
}
