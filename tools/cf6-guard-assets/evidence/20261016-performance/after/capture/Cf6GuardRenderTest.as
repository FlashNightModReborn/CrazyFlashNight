import flash.display.BitmapData;
import flash.geom.Matrix;

/** Isolated native draw-cost probe. No save, combat, rewards or real game state. */
class org.flashNight.arki.unit.Action.Melee.Cf6GuardRenderTest {
    private static var library:MovieClip,driver:MovieClip,actor:MovieClip,loader:MovieClipLoader;
    private static var listener:Object,bitmap:BitmapData,points:Array;
    private static var tickCount:Number,index:Number,passed:Number,failed:Number;
    private static var loaded:Boolean,done:Boolean;
    private static function check(value:Boolean,label:String):Void {
        if(value)passed++;else{failed++;trace("[TEST_FAIL] Cf6GuardRenderTest: "+label);}
    }
    public static function runAllTests():Void {
        tickCount=index=passed=failed=0;loaded=done=false;
        points=[1,40,43,46,49,52,55,58,61,70];
        library=_root.createEmptyMovieClip("__guardRenderLibrary",_root.getNextHighestDepth());
        driver=_root.createEmptyMovieClip("__guardRenderDriver",_root.getNextHighestDepth());
        library._visible=false;_root.gameworld=library;
        _root.暂停=true;_root.是否阴影=true;_root.控制目标="__none";_root.控制目标全自动=false;
        _root.播放音效=function():Void {};_root.发布消息=function():Void {};
        _root.敌人函数={配置音效:function():Void {}};
        _root.初始化思考标签=function(mc:MovieClip):Void {mc.stop();mc._visible=false;};
        _root.初始化敌人模板=function():Void {
            this.hp=this.hp满血值=1000;this.mp=100;this.等级=30;this.名字="性能隔离保安";
            this.状态="空手站立";this.方向="右";this.攻击目标="无";this.是否为敌人=true;
            this._x=this._y=this.Z轴坐标=0;this.myxscale=100;
            this.方向改变=function(direction:String):Void {this.方向=direction;this._xscale=direction=="左"?-100:100;};
            this.swapDepths=function():Void {};this.stop();
        };
        listener={onLoadInit:function(mc:MovieClip):Void {
            mc.stop();Cf6GuardRenderTest.actor=mc.attachMovie("敌人-CF6光头保安","probe",mc.getNextHighestDepth(),{光头保安变身:false});
            Cf6GuardRenderTest.loaded=true;Cf6GuardRenderTest.tickCount=0;
        },onLoadError:function(mc:MovieClip,error:String):Void {Cf6GuardRenderTest.check(false,"load "+error);Cf6GuardRenderTest.finish();}};
        loader=new MovieClipLoader();loader.addListener(listener);
        bitmap=new BitmapData(480,360,true,0);
        check(loader.loadClip(_root.guardRenderSwf,library),"load bound SWF");
        driver.onEnterFrame=function():Void {Cf6GuardRenderTest.tick();};
    }
    private static function tick():Void {
        if(done)return;tickCount++;
        if(!loaded){if(tickCount>300){check(false,"load timeout");finish();}return;}
        if(tickCount==3){actor.状态="变身";actor.gotoAndStop("变身");}
        if(tickCount<6)return;
        if(index>=points.length){finish();return;}
        var frame:Number=points[index++];actor.man.gotoAndStop(frame);
        check(actor.man._currentframe==frame,"actual body frame "+frame);
        var matrix:Matrix=actor.man.transform.matrix;matrix.tx+=240;matrix.ty+=295;
        var start:Number=getTimer();bitmap.draw(actor.man,matrix);
        var first:Number=getTimer()-start;
        var durations:Array=[];
        for(var i:Number=0;i<5;i++) {
            bitmap.fillRect(bitmap.rectangle,0);start=getTimer();bitmap.draw(actor.man,matrix);durations.push(getTimer()-start);
        }
        var visible:Number=0;
        for(var y:Number=0;y<360;y+=5)for(var x:Number=0;x<480;x+=5)if((bitmap.getPixel32(x,y)>>>24)>0)visible++;
        check(visible>60,"visible native art "+frame);
        if(_root.guardRenderCapture===true)capture(frame);
        trace("[GUARD_RENDER_SAMPLE] tag="+_root.guardRenderTag+" frame="+frame+" firstMs="+first+" repeatMs="+durations.join(",")+" pixels="+visible);
    }
    private static function capture(frame:Number):Void {
        var key:String=_root.guardRenderTag+"-"+frame;
        trace("[GUARD_IMAGE_BEGIN] "+key+" 480 360");
        for(var row:Number=0;row<360;row++) {
            var parts:Array=[],last:Number=bitmap.getPixel32(0,row),count:Number=1;
            for(var col:Number=1;col<480;col++) {
                var value:Number=bitmap.getPixel32(col,row);
                if(value==last)count++;else{parts.push(pixelHex(last)+":"+count);last=value;count=1;}
            }
            parts.push(pixelHex(last)+":"+count);
            trace("[GUARD_IMAGE_ROW] "+key+" "+row+" "+parts.join(","));
        }
        trace("[GUARD_IMAGE_END] "+key);
    }
    private static function pixelHex(value:Number):String {
        var digits:String="0123456789abcdef",text:String="";
        for(var shift:Number=28;shift>=0;shift-=4)text+=digits.charAt((value>>>shift)&15);
        return text;
    }
    private static function finish():Void {
        if(done)return;done=true;delete driver.onEnterFrame;
        loader.removeListener(listener);bitmap.dispose();library.removeMovieClip();driver.removeMovieClip();
        trace("Cf6GuardRenderTest: "+passed+" passed, "+failed+" failed; "+index+" draw points");
        _root.cf6GuardRenderComplete();
    }
}
