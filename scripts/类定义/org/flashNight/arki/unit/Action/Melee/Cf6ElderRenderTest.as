import flash.display.BitmapData;
import flash.geom.Matrix;

/** Every source frame is drawn by Flash; isolated fixture, no save or combat writes. */
class org.flashNight.arki.unit.Action.Melee.Cf6ElderRenderTest {
    private static var library:MovieClip,driver:MovieClip,actor:MovieClip,loader:MovieClipLoader;
    private static var listener:Object,bitmap:BitmapData,points:Array;
    private static var tickCount:Number,index:Number,passed:Number,failed:Number,settle:Number;
    private static var loaded:Boolean,done:Boolean;
    private static var activeState:String;
    private static var pendingPoint:Object,lastDrawFrame:Number;
    private static var actors:Array;
    private static function check(value:Boolean,label:String):Void {
        if(value)passed++;else{failed++;trace("[TEST_FAIL] Cf6ElderRenderTest: "+label);}
    }
    public static function runAllTests():Void {
        tickCount=index=passed=failed=settle=0;loaded=done=false;points=[];activeState="";pendingPoint=null;lastDrawFrame=0;
        var forms:Array=[
            {form:0,states:["空手站立","空手行走","空手攻击","近战","被击","倒地"],counts:[19,25,53,34,25,89],tags:["human-stand","human-walk","burst","stab","human-hit","human-fall"]},
            {form:1,states:["空手站立","空手行走","空手攻击","近战","重击","蓄能重束","被击","血腥死"],counts:[39,36,44,40,62,106,25,111],tags:["robot-stand","robot-walk","beam","kicks","slam","heavy-beam","robot-hit","robot-death"]},
            {form:0,states:["变身"],counts:[93],tags:["phase"]}];
        var selected:Object={},keys:Array=["human-stand-1","burst-13","stab-7","human-fall-31","robot-stand-1","beam-29","kicks-9","slam-37","robot-death-32","robot-death-111","phase-1","phase-18","phase-49","phase-55","phase-80","phase-93","heavy-beam-1","heavy-beam-24","heavy-beam-34","heavy-beam-35","heavy-beam-106"];
        for(var keyIndex:Number=0;keyIndex<keys.length;keyIndex++)selected[keys[keyIndex]]=true;
        for(var g:Number=0;g<forms.length;g++){
            var entry:Object=forms[g];
            for(var st:Number=0;st<entry.states.length;st++)for(var f:Number=1;f<=entry.counts[st];f++){
                var key:String=entry.tags[st]+"-"+f;
                points.push({form:entry.form,state:entry.states[st],frame:f,key:key,side:0,capture:selected[key]===true});
            }
        }
        points.push({form:0,state:"空手攻击",frame:13,key:"burst-left-13",side:1,capture:true});
        points.push({form:1,state:"空手攻击",frame:29,key:"beam-left-29",side:1,capture:true});
        points.push({form:0,state:"变身",frame:55,key:"phase-left-55",side:1,capture:true});
        points.push({form:1,state:"蓄能重束",frame:35,key:"heavy-beam-left-35",side:1,capture:true});
        if(_root.elderRenderFrames!=undefined){
            var keys:Array=_root.elderRenderFrames,wanted:Object={},selectedPoints:Array=[];
            for(var keyIndex:Number=0;keyIndex<keys.length;keyIndex++)wanted[keys[keyIndex]]=true;
            for(var pointIndex:Number=0;pointIndex<points.length;pointIndex++)if(wanted[points[pointIndex].key]===true){
                points[pointIndex].capture=true;selectedPoints.push(points[pointIndex]);
            }
            check(selectedPoints.length==keys.length,"selected frame keys exist exactly once");
            points=selectedPoints;
        }
        library=_root.createEmptyMovieClip("__elderRenderLibrary",_root.getNextHighestDepth());
        driver=_root.createEmptyMovieClip("__elderRenderDriver",_root.getNextHighestDepth());
        library._visible=false;_root.gameworld=library;
        _root.暂停=true;_root.是否阴影=true;_root.控制目标="__none";_root.控制目标全自动=false;
        _root.播放音效=function():Void {};_root.发布消息=function():Void {};_root.效果=function():Void {};
        _root.敌人函数={配置音效:function():Void {}};
        _root.初始化思考标签=function(mc:MovieClip):Void {mc.stop();mc._visible=false;};
        _root.初始化敌人模板=function():Void {
            this.hp=this.hp满血值=1000;this.等级=40;this.名字="原生绘制隔离老头";
            this.状态="空手站立";this.方向="右";this.攻击目标="无";this.是否为敌人=true;
            this._x=this._y=this.Z轴坐标=0;this.myxscale=100;
            this.方向改变=function(direction:String):Void {this.方向=direction;this._xscale=direction=="左"?-100:100;};
            this.动画完毕=function():Void {};this.死亡检测=function():Void {};
            this.swapDepths=function():Void {};this.stop();
        };
        listener={onLoadInit:function(mc:MovieClip):Void {
            mc.stop();mc._visible=false;Cf6ElderRenderTest.actors=[mc.attachMovie("敌人-CF6老头人形","human",mc.getNextHighestDepth(),{老头变身:false}),
                mc.attachMovie("敌人-CF6老头机器人","robot",mc.getNextHighestDepth())];
            Cf6ElderRenderTest.loaded=true;Cf6ElderRenderTest.tickCount=0;
        },onLoadError:function(mc:MovieClip,error:String):Void {Cf6ElderRenderTest.check(false,"load "+error);Cf6ElderRenderTest.finish();}};
        loader=new MovieClipLoader();loader.addListener(listener);bitmap=new BitmapData(1100,500,true,0);
        check(loader.loadClip("../flashswf/arts/new/Codex老头素材.swf",library),"load published SWF");
        driver.onEnterFrame=function():Void {Cf6ElderRenderTest.tick();};
    }
    private static function tick():Void {
        if(done)return;tickCount++;
        if(!loaded){if(tickCount>300){check(false,"load timeout");finish();}return;}
        if(tickCount==3){
            for(var form:Number=0;form<2;form++){
                var body:MovieClip=actors[form].man;
                check(body._width>50 && body._height>100,"both forms contain native body geometry before capture "+form);
                var box:Object=body.getBounds(actors[form]);
                trace("[ELDER_NATIVE_BOUNDS] form="+form+" x="+box.xMin+","+box.xMax+" y="+box.yMin+","+box.yMax);
            }
            if(failed>0){finish();return;}
        }
        if(tickCount<4)return;
        if(index>=points.length){finish();return;}
        var point:Object=points[index];
        if(pendingPoint!==point){
        if(activeState!=point.form+"|"+point.state){
            activeState=point.form+"|"+point.state;lastDrawFrame=0;actor=actors[point.form];actor.elderTransform=null;actor.hp=1000;
            if(point.state=="变身"){actor.老头变身=true;actor.hp=0;actor.elderStartTransform();}
            else actor.状态改变(point.state);
            settle=2;return;
        }
        if(settle>0){settle--;return;}
        if(point.state=="血腥死" && point.frame<lastDrawFrame){actor.man.gotoAndStop(1);lastDrawFrame=0;settle=1;return;}
        actor.方向改变(point.side==0?"右":"左");actor.man.gotoAndStop(point.frame);
        pendingPoint=point;return;
        }
        pendingPoint=null;index++;lastDrawFrame=point.frame;
        var debris:MovieClip=actor.man.尸体碎片;
        if(debris!=null){
            var needed:Number=point.frame-32+1;
            if(debris.cf6RenderSteps==undefined)debris.cf6RenderSteps=0;
            while(debris.cf6RenderSteps<needed && typeof debris.cf6EngineStep=="function"){
                debris.cf6EngineStep.call(debris);debris.cf6RenderSteps++;
                if(!_root.地图元件.地图元件破碎动画运行中(debris.cf6AnimationId)){debris.cf6Settled=true;delete debris.cf6EngineStep;}
            }
        }
        check(actor.man._currentframe==point.frame,"actual body frame "+point.key);
        var matrix:Matrix=actor.man.transform.matrix,sign:Number=point.side==0?1:-1;
        matrix.a*=1.2*sign;matrix.c*=1.2*sign;matrix.b*=1.2;matrix.d*=1.2;
        var beamFraming:Boolean=point.form==1 && (point.state=="空手攻击" || point.state=="蓄能重束");
        matrix.tx=matrix.tx*1.2*sign+(point.side==0?(beamFraming?200:300):(beamFraming?900:800));matrix.ty=matrix.ty*1.2+330;
        bitmap.fillRect(bitmap.rectangle,0);var start:Number=getTimer();bitmap.draw(actor.man,matrix);
        var first:Number=getTimer()-start,durations:Array=[];
        for(var i:Number=0;i<3;i++) {
            bitmap.fillRect(bitmap.rectangle,0);start=getTimer();bitmap.draw(actor.man,matrix);durations.push(getTimer()-start);
        }
        var drawn:Object=bitmap.getColorBoundsRect(0xffffffff,0,false);
        var visible:Number=drawn.width*drawn.height;
        check(visible>0,"nonempty native drawing "+point.key);
        var fullBounds:Object=bitmap.getColorBoundsRect(0xffffffff,0,false);
        check(fullBounds.x>0 && fullBounds.y>0 && fullBounds.x+fullBounds.width<1100 && fullBounds.y+fullBounds.height<500,"native frame fits full capture "+point.key);
        if(_root.elderRenderCapture===true && point.capture)capture(point.key);
        trace("[ELDER_RENDER_SAMPLE] key="+point.key+" firstMs="+first+" repeatMs="+durations.join(",")+" boundsArea="+visible);
    }
    private static function capture(key:String):Void {
        trace("[ELDER_IMAGE_BEGIN] "+key+" 1100 500");
        // A declared native rectangle makes omitted rows explicitly transparent.
        // Pack several complete rows per trace to avoid Output Panel line overhead.
        var bounds:Object=bitmap.getColorBoundsRect(0xffffffff,0,false);
        var left:Number=bounds.x,right:Number=bounds.x+bounds.width;
        trace("[ELDER_IMAGE_RECT] "+key+" "+left+" "+bounds.y+" "+bounds.width+" "+bounds.height);
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
            if(chunk.length>0 && chunk.length+encoded.length>8192){trace("[ELDER_IMAGE_DATA] "+key+" "+chunk);chunk="";}
            chunk+=encoded;
        }
        if(chunk.length>0)trace("[ELDER_IMAGE_DATA] "+key+" "+chunk);
        trace("[ELDER_IMAGE_END] "+key);
    }
    private static function pixelHex(value:Number):String {
        var digits:String="0123456789abcdef",text:String="";
        for(var shift:Number=28;shift>=0;shift-=4)text+=digits.charAt((value>>>shift)&15);
        return text;
    }
    private static function finish():Void {
        if(done)return;done=true;delete driver.onEnterFrame;
        loader.removeListener(listener);bitmap.dispose();library.removeMovieClip();driver.removeMovieClip();
        trace("Cf6ElderRenderTest: "+passed+" passed, "+failed+" failed; "+index+" draw points");
        _root.cf6ElderRenderComplete();
    }
}