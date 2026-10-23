import flash.display.BitmapData;
import flash.geom.Matrix;

/** Loads the actual CS6 door SWFs and verifies native frame/mask pixel contracts. */
class org.flashNight.arki.scene.Cf6TraversalAssetsTest {
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
        if(ok) passed++;else {failed++;trace("[FAIL] Cf6TraversalAssets: "+label);}
    }
    public static function runAllTests():Void {
        passed=failed=0;index=-1;done=false;
        rows=[{sprite:1720,part:"Back",frames:174,first:1,last:174},
            {sprite:1720,part:"Front",frames:174,first:74,last:174},
            {sprite:1720,part:"Mask",frames:174,first:136,last:174},
            {sprite:1729,part:"Back",frames:174,first:1,last:174},
            {sprite:1729,part:"Front",frames:174,first:1,last:101},
            {sprite:1729,part:"Mask",frames:174,first:1,last:39},
            {sprite:1750,part:"Back",frames:40,first:1,last:40},
            {sprite:1750,part:"Front",frames:40,first:1,last:0}];
        fixture=_root.createEmptyMovieClip("__cf6TraversalAssets",_root.getNextHighestDepth());
        fixture._visible=false;
        driver=_root.createEmptyMovieClip("__cf6TraversalAssetsWatch",_root.getNextHighestDepth());
        driver.onEnterFrame=function():Void {org.flashNight.arki.scene.Cf6TraversalAssetsTest.tick();};
        bitmap=new BitmapData(800,800,true,0);
        next();
    }
    private static function next():Void {
        if(entry!=null) {entry.loader.removeListener(entry.listener);entry.clip.removeMovieClip();}
        index++;
        if(index==rows.length) {finish();return;}
        entry=rows[index];entry.tick=0;entry.frame=1;entry.correct=true;entry.visibleFrames=0;
        entry.clip=fixture.createEmptyMovieClip("asset"+index,index);
        entry.name="CF6_Traversal"+entry.sprite+"_"+entry.part;
        entry.loader=new MovieClipLoader();entry.listener={row:entry,
            onLoadInit:function(mc:MovieClip):Void {org.flashNight.arki.scene.Cf6TraversalAssetsTest.loaded(this.row,mc);},
            onLoadError:function(mc:MovieClip,error:String):Void {org.flashNight.arki.scene.Cf6TraversalAssetsTest.loadError(this.row,error);}};
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
            trace("Cf6TraversalAssets FrameMismatch: "+entry.name+" frame="+f+" visible="+visible+" expected="+expected);
        }
        if(f<entry.frames) return;
        check(entry.correct,"all actual visible/empty frames "+entry.name);
        trace("Cf6TraversalAssets NativeFrames: "+entry.name+" checked="+entry.frames+" visible="+entry.visibleFrames);
        if(entry.part=="Mask") verifyMask();
        if(entry.part=="Back" && entry.sprite!=1750) verifyBack();
        next();
    }
    private static function verifyMask():Void {
        entry.clip.gotoAndStop(entry.first);draw(entry.clip);
        var y:Number=entry.sprite==1720 ? 0 : -114;
        var inside:Boolean=(bitmap.getPixel32(400,400+y)>>>24)>0;
        var left:Boolean=(bitmap.getPixel32(350,400+y)>>>24)==0;
        var right:Boolean=(bitmap.getPixel32(450,400+y)>>>24)==0;
        var top:Number=entry.sprite==1720 ? -88.4 : -202.4;
        var bottom:Number=entry.sprite==1720 ? 87.55 : -26.45;
        check(inside && left && right && (bitmap.getPixel32(400,Math.floor(400+top)-2)>>>24)==0
            && (bitmap.getPixel32(400,Math.ceil(400+bottom)+2)>>>24)==0,
            "native source mask retains fixed window "+entry.name);
    }
    private static function verifyBack():Void {
        var baseline:BitmapData=new BitmapData(800,800,true,0);
        entry.clip.gotoAndStop(entry.sprite==1720 ? 135 : 40);
        baseline.draw(entry.clip,new Matrix(1,0,0,1,400,400));
        var frames:Array=entry.sprite==1720 ? [136,150,174] : [1,20,39];
        var top:Number=entry.sprite==1720 ? -88.4 : -202.4;
        var bottom:Number=entry.sprite==1720 ? 87.55 : -26.45;
        var outsideChanges:Number=0,insideChanges:Number=0;
        for(var i:Number=0;i<frames.length;i++) {
            entry.clip.gotoAndStop(frames[i]);draw(entry.clip);
            for(var y:Number=-240;y<220;y+=4) for(var x:Number=-80;x<80;x+=4) {
                if(bitmap.getPixel32(x+400,y+400)===baseline.getPixel32(x+400,y+400)) continue;
                if(x>-44 && x<44 && y>top+2 && y<bottom-2) insideChanges++;
                else if(x<-49 || x>49 || y<top-2 || y>bottom+2) outsideChanges++;
            }
        }
        check(outsideChanges==0,"moving background cannot spill outside original clipDepth window "+entry.name);
        check(insideChanges>0,"clipped native background actually moves inside window "+entry.name);
        trace("Cf6TraversalAssets BackClip: "+entry.name+" outsideChanges="+outsideChanges+" insideChanges="+insideChanges);
        baseline.dispose();
    }
    private static function finish():Void {
        if(done) return;done=true;
        if(entry!=null) entry.loader.removeListener(entry.listener);
        delete driver.onEnterFrame;driver.removeMovieClip();fixture.removeMovieClip();bitmap.dispose();
        trace("Cf6TraversalAssetsTest Tests Passed: "+passed);
        trace("Cf6TraversalAssetsTest Tests Failed: "+failed);
        _root.cf6TraversalAssetsComplete();
    }
}
