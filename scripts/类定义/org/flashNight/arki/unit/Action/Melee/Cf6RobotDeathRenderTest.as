import flash.display.BitmapData;
import flash.geom.Matrix;

/** Every source frame is drawn by Flash; isolated fixture, no save or combat writes. */
class org.flashNight.arki.unit.Action.Melee.Cf6RobotDeathRenderTest {
    private static var library:MovieClip,driver:MovieClip,actor:MovieClip,loader:MovieClipLoader;
    private static var listener:Object,bitmap:BitmapData,points:Array;
    private static var tickCount:Number,index:Number,passed:Number,failed:Number,settle:Number;
    private static var loaded:Boolean,done:Boolean;
    private static var activeState:String;
    private static var pendingPoint:Object,lastDrawFrame:Number;
    private static function check(value:Boolean,label:String):Void {
        if(value)passed++;else{failed++;trace("[TEST_FAIL] Cf6RobotDeathRenderTest: "+label);}
    }
    public static function runAllTests():Void {
        tickCount=index=passed=failed=settle=0;loaded=done=false;points=[];activeState="";pendingPoint=null;lastDrawFrame=0;
        var states:Array=["血腥死"];
        var counts:Array=[_root.robotRenderConfig.total],tags:Array=["death"];
        var selected:Object={},keys:Array=["stand-1","stand-22","beam-1","beam-12","beam-18","beam-21","beam-29","thrust-3","thrust-12","hit-1","hit-7","death-1","death-15","death-30","death-45","death-58"];
        for(var keyIndex:Number=0;keyIndex<keys.length;keyIndex++)selected[keys[keyIndex]]=true;
        for(var s:Number=0;s<states.length;s++)for(var f:Number=1;f<=counts[s];f++) {
            var key:String=tags[s]+"-"+f;
            points.push({state:states[s],frame:f,key:key,side:0,capture:selected[key]===true});
        }
        points.push({state:"血腥死",frame:_root.robotRenderConfig.mirrorFrame,key:"death-left-"+_root.robotRenderConfig.mirrorFrame,side:1,capture:true});
        if(_root.robotRenderConfig.frames!=undefined){
            var keys:Array=_root.robotRenderConfig.frames,wanted:Object={},selectedPoints:Array=[];
            for(var keyIndex:Number=0;keyIndex<keys.length;keyIndex++)wanted[keys[keyIndex]]=true;
            for(var pointIndex:Number=0;pointIndex<points.length;pointIndex++)if(wanted[points[pointIndex].key]===true){
                points[pointIndex].capture=true;selectedPoints.push(points[pointIndex]);
            }
            check(selectedPoints.length==keys.length,"selected frame keys exist exactly once");
            points=selectedPoints;
        }
        library=_root.createEmptyMovieClip("__headbotRenderLibrary",_root.getNextHighestDepth());
        driver=_root.createEmptyMovieClip("__headbotRenderDriver",_root.getNextHighestDepth());
        library._visible=false;_root.gameworld=library;
        _root.暂停=true;_root.是否阴影=true;_root.控制目标="__none";_root.控制目标全自动=false;
        _root.播放音效=function():Void {};_root.发布消息=function():Void {};_root.效果=function():Void {};
        _root.敌人函数={配置音效:function():Void {}};
        _root.初始化思考标签=function(mc:MovieClip):Void {mc.stop();mc._visible=false;};
        _root.初始化敌人模板=function():Void {
            this.hp=this.hp满血值=1000;this.等级=40;this.名字="机器人死亡素材采样";
            this.状态="空手站立";this.方向="右";this.攻击目标="无";this.是否为敌人=true;
            this._x=this._y=this.Z轴坐标=0;this.myxscale=100;
            this.方向改变=function(direction:String):Void {this.方向=direction;this._xscale=direction=="左"?-100:100;};
            this.状态改变=function(state:String):Void {this.状态=state;this.gotoAndStop(state);};
            this.动画完毕=function():Void {};this.死亡检测=function():Void {};
            this.swapDepths=function():Void {};this.stop();
        };
        listener={onLoadInit:function(mc:MovieClip):Void {
            mc.stop();mc._visible=false;Cf6RobotDeathRenderTest.actor=mc.attachMovie(_root.robotRenderConfig.linkage,"probe",mc.getNextHighestDepth());
            Cf6RobotDeathRenderTest.loaded=true;Cf6RobotDeathRenderTest.tickCount=0;
        },onLoadError:function(mc:MovieClip,error:String):Void {Cf6RobotDeathRenderTest.check(false,"load "+error);Cf6RobotDeathRenderTest.finish();}};
        loader=new MovieClipLoader();loader.addListener(listener);bitmap=new BitmapData(1100,500,true,0);
        check(loader.loadClip(_root.robotRenderConfig.swf,library),"load published SWF");
        driver.onEnterFrame=function():Void {try{Cf6RobotDeathRenderTest.tick();}catch(error){Cf6RobotDeathRenderTest.check(false,"native capture exception "+error);Cf6RobotDeathRenderTest.finish();}};
    }
    private static function tick():Void {
        if(done)return;tickCount++;
        if(!loaded){if(tickCount>300){check(false,"load timeout");finish();}return;}
        if(tickCount<4)return;
        if(index>=points.length){finish();return;}
        var point:Object=points[index];
        if(pendingPoint!==point){
        if(activeState!=point.state){
            activeState=point.state;lastDrawFrame=0;actor.状态改变(point.state);settle=2;return;
        }
        if(settle>0){settle--;return;}
        if(point.state=="血腥死" && point.frame<lastDrawFrame){actor.man.gotoAndStop(1);lastDrawFrame=0;settle=1;return;}
        actor.方向改变(point.side==0?"右":"左");actor.man.gotoAndStop(point.frame);
        pendingPoint=point;return;
        }
        pendingPoint=null;index++;lastDrawFrame=point.frame;
        var debris:MovieClip=actor.man.尸体碎片;
        if(debris!=null){
            if(point.frame==58 && _root.robotRenderConfig.fragmentStart==19){
                for(var fragmentIndex:Number=1;fragmentIndex<=14;fragmentIndex++){
                    var fragment:MovieClip=debris["碎片"+fragmentIndex];
                    var partBounds:Object=fragment.getBounds(fragment),partMatrix:Matrix=new Matrix();
                    partMatrix.tx=550-(partBounds.xMin+partBounds.xMax)/2;
                    partMatrix.ty=250-(partBounds.yMin+partBounds.yMax)/2;
                    bitmap.fillRect(bitmap.rectangle,0);bitmap.draw(fragment,partMatrix);
                    var partPixels:Object=bitmap.getColorBoundsRect(0xffffffff,0,false);
                    check(partPixels.width>0 && partPixels.height>0,"fragment has native pixels "+fragmentIndex);
                    trace("[ROBOT_FRAGMENT_PIXELS] part="+fragmentIndex+" size="+fragment._width+","+fragment._height+" bounds="+partBounds.xMin+","+partBounds.yMin+","+partBounds.xMax+","+partBounds.yMax+" pixels="+partPixels.width+","+partPixels.height);
                }
            }
            var needed:Number=point.frame-_root.robotRenderConfig.fragmentStart+1;
            if(debris.cf6RenderSteps==undefined)debris.cf6RenderSteps=0;
            while(debris.cf6RenderSteps<needed && typeof debris.cf6EngineStep=="function"){
                debris.cf6EngineStep.call(debris);debris.cf6RenderSteps++;
                if(!_root.地图元件.地图元件破碎动画运行中(debris.cf6AnimationId)){debris.cf6Settled=true;delete debris.cf6EngineStep;}
            }
        }
        if(typeof actor.man.headbotShadow.updateHeadbotShadow=="function")actor.man.headbotShadow.updateHeadbotShadow();
        if(typeof actor.bladebotShadow.updateBladebotShadow=="function")actor.bladebotShadow.updateBladebotShadow();
        check(actor.man._totalframes==_root.robotRenderConfig.total,"actual death body timeline "+point.key);
        check(actor.man._currentframe==point.frame,"actual body frame "+point.key);
        var matrix:Matrix=actor.man.transform.matrix,sign:Number=point.side==0?1:-1;
        matrix.a*=1.2*sign;matrix.c*=1.2*sign;matrix.b*=1.2;matrix.d*=1.2;
        matrix.tx=matrix.tx*1.2*sign+(point.side==0?(point.state=="空手攻击"?285:300):800);matrix.ty=matrix.ty*1.2+330;
        bitmap.fillRect(bitmap.rectangle,0);var start:Number=getTimer();bitmap.draw(actor.man,matrix);
        var first:Number=getTimer()-start,durations:Array=[];
        for(var i:Number=0;i<3;i++) {
            bitmap.fillRect(bitmap.rectangle,0);start=getTimer();bitmap.draw(actor.man,matrix);durations.push(getTimer()-start);
        }
        var drawn:Object=bitmap.getColorBoundsRect(0xffffffff,0,false);
        var visible:Number=drawn.width*drawn.height;
        check(visible>0,"nonempty native drawing "+point.key);
        var fullBounds:Object=drawn;
        check(fullBounds.x>0 && fullBounds.y>0 && fullBounds.x+fullBounds.width<1100 && fullBounds.y+fullBounds.height<500,"native frame fits full capture "+point.key);
        if(_root.robotRenderCapture===true && point.capture)capture(point.key);
        trace("[ROBOT_RENDER_SAMPLE] key="+point.key+" firstMs="+first+" repeatMs="+durations.join(",")+" boundsArea="+visible);
    }
    private static function capture(key:String):Void {
        trace("[ROBOT_IMAGE_BEGIN] "+key+" 1100 500");
        // A declared native rectangle makes omitted rows explicitly transparent.
        // Pack several complete rows per trace to avoid Output Panel line overhead.
        var bounds:Object=bitmap.getColorBoundsRect(0xffffffff,0,false);
        var left:Number=bounds.x,right:Number=bounds.x+bounds.width;
        trace("[ROBOT_IMAGE_RECT] "+key+" "+left+" "+bounds.y+" "+bounds.width+" "+bounds.height);
        var chunk:String="";
        for(var row:Number=bounds.y;row<bounds.y+bounds.height;row++) {
            var parts:Array=[];
            if(left>0)parts.push("00000000:"+left);
            var last:Number=bitmap.getPixel32(left,row),count:Number=1;
            for(var col:Number=left+1;col<right;col++) {
                var value:Number=bitmap.getPixel32(col,row);
                if(value==last)count++;else{parts.push(pixelHex(last)+":"+count);last=value;count=1;}
            }
            parts.push(pixelHex(last)+":"+count);
            if(right<1100)parts.push("00000000:"+(1100-right));
            var encoded:String=row+"="+parts.join(",")+";";
            if(chunk.length>0 && chunk.length+encoded.length>8192){trace("[ROBOT_IMAGE_DATA] "+key+" "+chunk);chunk="";}
            chunk+=encoded;
        }
        if(chunk.length>0)trace("[ROBOT_IMAGE_DATA] "+key+" "+chunk);
        trace("[ROBOT_IMAGE_END] "+key);
    }
    private static function pixelHex(value:Number):String {
        var digits:String="0123456789abcdef",text:String="";
        for(var shift:Number=28;shift>=0;shift-=4)text+=digits.charAt((value>>>shift)&15);
        return text;
    }
    private static function finish():Void {
        if(done)return;done=true;delete driver.onEnterFrame;
        loader.removeListener(listener);bitmap.dispose();library.removeMovieClip();driver.removeMovieClip();
        trace("Cf6RobotDeathRenderTest: "+passed+" passed, "+failed+" failed; "+index+" draw points");
        _root.cf6RobotDeathRenderComplete();
    }
}
