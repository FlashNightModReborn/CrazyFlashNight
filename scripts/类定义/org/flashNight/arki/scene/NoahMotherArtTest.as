import flash.display.BitmapData;
import flash.geom.Matrix;
/** 渲染范围故意超过 SWF 原画布，捕捉井口以下的穿帮。旧产物为负对照。 */
class org.flashNight.arki.scene.NoahMotherArtTest {
    private static var loader:MovieClipLoader;
    private static var holder:MovieClip;
    private static var passed:Number=0;
    private static var failed:Number=0;
    public static function runAllTests():Void {
        holder=_root.createEmptyMovieClip("noahArt",_root.getNextHighestDepth());
        loader=new MovieClipLoader();var listener:Object={};
        listener.onLoadInit=function(mc:MovieClip):Void {org.flashNight.arki.scene.NoahMotherArtTest.loaded(mc);};
        listener.onLoadError=function(mc:MovieClip,code:String):Void {trace("[FAIL] noah native art "+code);};
        loader.addListener(listener);loader.loadClip("../flashswf/movies/尸母巢穴巨型尸母.swf",holder);
    }
    private static function check(ok:Boolean,label:String):Void {if(ok)passed++;else {failed++;trace("[FAIL] NoahMotherArtTest "+label);}}
    public static function loaded(mc:MovieClip):Void {
        check(mc.noahAssetVersion===1 && mc.noahPresentationVersion===3,"published presentation version");
        mc.noahPose("空闲",1,0,"",0);var a:Object=capture(mc,"wounded",true);
        check(mc.noahMotion._totalframes==80,"authored idle frames");
        var entrance:Array=[65,80,110];
        for(var e:Number=0;e<entrance.length;e++){
            mc.noahPose("登场",entrance[e],0,"",entrance[e]);
            var entry:Object=capture(mc,"entrance-"+entrance[e],entrance[e]==80);
            check(entry.below==0,"entrance hidden below pit lip at "+entrance[e]);
        }
        mc.noahPose("空闲",1,0,"",200);
        mc.noahPose("空闲",1,1,"acid",210);
        mc.noahPose("空闲",9,1,"acid",218);var b:Object=capture(mc,"burst-onset",false);
        check(a.sum!=b.sum,"first exhaustion redraw");
        check(mc.noahMotion.noahHead.noahPhaseBurst._visible && mc.noahPhaseBurstAt==210,"phase change starts one acid rupture");
        mc.noahPose("喷吐",25,1,"acid",220);
        check(mc.noahPhaseBurstAt==210 && mc.noahMotion.noahOpen.noahPhaseBurst._visible!==true,"mouth occludes phase burst without resetting its clock");
        check(mc.noahMotion.noahOpen.noahEye0._visible===false && mc.noahMotion.noahOpen.noahEye1._visible===false,"open mouth hides both displaced flames");
        capture(mc,"mouth-open",true);
        mc.noahPose("空闲",26,1,"acid",235);capture(mc,"phase-burst",true);
        check(mc.noahMotion.noahHead.noahEye0._visible && mc.noahMotion.noahHead.noahPhaseBurst._visible,"eyes and remaining phase burst return when mouth closes");
        mc.noahPose("空闲",1,1,"",253);
        check(mc.noahMotion.noahHead.noahPhaseBurst._visible!==true,"phase burst ends without repeating");
        capture(mc,"failing",true);
        mc.noahPose("结束",1,2,"",260);var c:Object=capture(mc,"death-1",true);
        var anchors:Array=[];
        for(var ci:Number=0;ci<15;ci++){
            var strand:MovieClip=mc.noahMotion.noahChainHead["noahChain"+ci];anchors.push({x:strand._x,y:strand._y,rotation:strand._rotation});
        }
        check(b.sum!=c.sum,"terminal exhaustion redraw");
        check(mc.noahMotion.noahBody.noahHead.noahEye0._visible===false,"terminal eyes extinguish");
        mc.noahPose("结束",12,2,"",271);capture(mc,"death-12",true);
        check(mc.noahMotion.noahBody.noahRupture2._visible,"death uses staggered recycled acid jets");
        mc.noahPose("结束",28,2,"",287);capture(mc,"death-28",true);
        check(mc.noahMotion.noahBody._y>0 && Math.abs(mc.noahMotion.noahChainHead.noahChain0._rotation-anchors[0].rotation)>1,"body falls while individual upper strands swing");
        mc.noahPose("结束",42,2,"",301);var falling:Object=capture(mc,"death-42",true);
        check(falling.below==0,"fall is clipped by same pit lip");
        mc.noahPose("结束",90,2,"",349);capture(mc,"death-90",true);
        check(mc.noahMotion.noahBody._visible===false,"exhausted body disappears into pit");
        var fixed:Boolean=true;var vertical:Boolean=true;
        for(ci=0;ci<15;ci++){
            strand=mc.noahMotion.noahChainHead["noahChain"+ci];
            fixed=fixed && Math.abs(strand._x-anchors[ci].x)<0.05 && Math.abs(strand._y-anchors[ci].y)<0.05;
            vertical=vertical && Math.abs(strand._rotation)<0.05;
        }
        check(fixed,"all ceiling endpoints remain fixed during break and fall");
        check(vertical,"broken upper strands settle vertically instead of floating taut");
        mc.noahPose("喷吐",25,0,"serum",360);
        check(mc.noahMotion._totalframes==66 && mc.noahMotion._currentframe==25,"original large-larva spit preserved");
        var names:Array=["acidDrop","serumDrop","acidSplash","serumSplash","acidFlame","serumFlame","acidRupture"];
        for(var i:Number=0;i<names.length;i++){
            var fx:MovieClip=mc.attachMovie("Noah_"+names[i],"liquid"+i,500+i);
            check(fx._width>10 && fx._height>10,"native export "+names[i]);fx.removeMovieClip();
        }
        var gallery:MovieClip=mc.createEmptyMovieClip("liquidGallery",20000);
        for(var j:Number=0;j<2;j++){
            var pool:MovieClip=gallery.attachMovie(j==0?"Noah_acidSplash":"Noah_serumSplash","pool"+j,100+j);
            pool.gotoAndStop(2);
            check(Math.abs(pool._width-312)<3 && Math.abs(pool._height-146)<3,"ground art matches footprint "+j);
            pool._x=325;pool._y=j==0?158:475;pool._xscale=pool._yscale=160;
            check(Math.abs(pool._width-499.2)<4 && Math.abs(pool._height-233.6)<4,"surface uses reduced 80-percent diameter "+j);
        }
        capture(gallery,"pools",true);gallery.removeMovieClip();
        if(_root.__noahVerifyLegacyMask!==true){finish();return;}
        var old:MovieClip=_root.createEmptyMovieClip("noahOldArt",_root.getNextHighestDepth());
        loader=new MovieClipLoader();var listener:Object={};
        listener.onLoadInit=function(mc:MovieClip):Void {org.flashNight.arki.scene.NoahMotherArtTest.oldLoaded(mc);};
        listener.onLoadError=function(mc:MovieClip,code:String):Void {trace("[FAIL] negative control load "+code);};
        loader.addListener(listener);loader.loadClip("../tmp/noah-mother-v2/giant-v1.swf",old);
    }
    public static function oldLoaded(mc:MovieClip):Void {
        mc.noahPose("登场",80,0,"",80);var old:Object=capture(mc,"old-mask-leak",true);
        check(old.below>100,"negative control detects old entrance leak outside original canvas");
        trace("NoahMotherArtTest Old Mask Leaked Pixels: "+old.below);mc.removeMovieClip();
        finish();
    }
    private static function finish():Void {
        trace("NoahMotherArtTest Tests Passed: "+passed);trace("NoahMotherArtTest Tests Failed: "+failed);
        trace("FocusedTestRunId noah-mother-art Complete: "+_root.__noahArtRunId);
    }
    private static function hexByte(n:Number):String {var s:String=n.toString(16);return s.length<2?"0"+s:s;}
    private static function argb(n:Number):String {return hexByte((n>>>24)&255)+hexByte((n>>>16)&255)+hexByte((n>>>8)&255)+hexByte(n&255);}
    private static function capture(mc:MovieClip,label:String,dump:Boolean):Object {
        var b:BitmapData=new BitmapData(650,650,true,0);b.draw(mc,new Matrix());var sum:Number=0;var below:Number=0;
        for(var y:Number=0;y<650;y++){
            var line:String="";var last:Number=b.getPixel32(0,y);var count:Number=0;
            for(var x:Number=0;x<=650;x++){
                var value:Number=x<650?b.getPixel32(x,y):-1;
                if(x<650 && y>=351 && (value>>>24)>0)below++;
                if(x<650 && value==last){count++;continue;}
                if(count>0)line+=count.toString(16)+":"+argb(last)+",";
                sum=(sum+(last>>>0)*count)%1000000007;last=value;count=1;
            }
            if(dump)trace("NOAH_V3_BITMAP|"+label+"|650|650|"+y+"|"+line);
        }
        b.dispose();return {sum:sum,below:below};
    }
}
