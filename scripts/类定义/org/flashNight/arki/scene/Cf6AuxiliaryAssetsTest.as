import flash.display.BitmapData;
import flash.geom.Matrix;

/** Loads the actual CS6 door SWFs and verifies every auxiliary source frame and real pixel motion. */
class org.flashNight.arki.scene.Cf6AuxiliaryAssetsTest {
    private static var fixture:MovieClip;
    private static var driver:MovieClip;
    private static var rows:Array;
    private static var entry:Object;
    private static var index:Number;
    private static var passed:Number;
    private static var failed:Number;
    private static var done:Boolean;
    private static var bitmap:BitmapData;
    private static function check(ok:Boolean,label:String):Void {
        if(ok) passed++;else {failed++;trace("[FAIL] Cf6AuxiliaryAssets: "+label);}
    }
    public static function runAllTests():Void {
        passed=failed=0;index=-1;done=false;
        rows=[{name:"CF6_AuxDoor1430",sprite:1430,part:"Door",frames:59,first:1,last:59},
            {name:"CF6_AuxDoor1862",sprite:1862,part:"Door",frames:18,first:1,last:18},
            {name:"CF6_AuxCamera1832",sprite:1832,part:"Camera",frames:147,first:1,last:147}];
        fixture=_root.createEmptyMovieClip("__cf6TraversalAssets",_root.getNextHighestDepth());
        fixture._visible=false;
        driver=_root.createEmptyMovieClip("__cf6TraversalAssetsWatch",_root.getNextHighestDepth());
        driver.onEnterFrame=function():Void {org.flashNight.arki.scene.Cf6AuxiliaryAssetsTest.tick();};
        bitmap=new BitmapData(800,800,true,0);
        next();
    }
    private static function next():Void {
        if(entry!=null) {entry.loader.removeListener(entry.listener);entry.clip.removeMovieClip();}
        index++;
        if(index==rows.length) {finish();return;}
        entry=rows[index];entry.tick=0;entry.frame=1;entry.correct=true;entry.visibleFrames=0;
        entry.clip=fixture.createEmptyMovieClip("asset"+index,index);
        entry.reference=null;entry.moving=false;
        entry.loader=new MovieClipLoader();entry.listener={row:entry,
            onLoadInit:function(mc:MovieClip):Void {org.flashNight.arki.scene.Cf6AuxiliaryAssetsTest.loaded(this.row,mc);},
            onLoadError:function(mc:MovieClip,error:String):Void {org.flashNight.arki.scene.Cf6AuxiliaryAssetsTest.loadError(this.row,error);}};
        entry.loader.addListener(entry.listener);
        check(entry.loader.loadClip("../flashswf/backgrounds/cf6/preparation/"+entry.name+".swf",entry.clip),
            "request actual "+entry.name);
    }
    public static function loaded(row:Object,mc:MovieClip):Void {
        if(done || row!==entry || mc!==row.clip || row.ready===true) return;
        mc.stop();row.ready=true;
        check(mc._totalframes===row.frames,"native frame count "+row.name);
    }
    public static function loadError(row:Object,error:String):Void {
        if(done || row!==entry) return;
        check(false,"load "+row.name+" "+error);finish();
    }
    private static function draw(mc:MovieClip):Object {
        bitmap.fillRect(bitmap.rectangle,0);
        bitmap.draw(mc,new Matrix(1,0,0,1,400,400));
        return bitmap.getColorBoundsRect(0xFF000000,0,false);
    }
    private static function tick():Void {
        if(done) return;
        if(entry.ready!==true) {
            entry.tick++;if(entry.tick>300) {check(false,"asset timeout "+entry.name);finish();}return;
        }
        var f:Number=entry.frame++;
        entry.clip.gotoAndStop(f);
        var occupied:Object=draw(entry.clip);
        var visible:Boolean=occupied.width>0 && occupied.height>0;
        var expected:Boolean=f>=entry.first && f<=entry.last;
        if(visible) entry.visibleFrames++;
        if(visible!==expected || entry.clip._currentframe!==f) {
            entry.correct=false;
            trace("Cf6AuxiliaryAssets FrameMismatch: "+entry.name+" frame="+f+" visible="+visible+" expected="+expected);
        }
        var current:Array=[];
        var extent:Number=entry.part=="Camera" ? 70 : 180;
        var step:Number=entry.part=="Camera" ? 2 : 8;
        for(var py:Number=-extent;py<=extent;py+=step)
            for(var px:Number=-extent;px<=extent;px+=step) current.push(bitmap.getPixel32(px+400,py+400));
        if(entry.reference==null) entry.reference=current;
        else for(var n:Number=0;n<current.length;n++) if(current[n]!==entry.reference[n]) {entry.moving=true;break;}
        if(f<entry.frames) return;
        check(entry.correct,"all actual visible/empty frames "+entry.name);
        trace("Cf6AuxiliaryAssets NativeFrames: "+entry.name+" checked="+entry.frames+" visible="+entry.visibleFrames);
        check(entry.moving,"actual timeline changes pixels "+entry.name);
        next();
    }
    private static function finish():Void {
        if(done) return;done=true;
        if(entry!=null) entry.loader.removeListener(entry.listener);
        delete driver.onEnterFrame;driver.removeMovieClip();fixture.removeMovieClip();bitmap.dispose();
        trace("Cf6AuxiliaryAssetsTest Tests Passed: "+passed);
        trace("Cf6AuxiliaryAssetsTest Tests Failed: "+failed);
        _root.cf6AuxiliaryAssetsComplete();
    }
}
