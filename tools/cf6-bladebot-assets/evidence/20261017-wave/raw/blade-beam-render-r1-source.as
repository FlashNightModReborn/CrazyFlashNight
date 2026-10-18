import flash.display.BitmapData;
import flash.geom.Matrix;

/** Every source frame is drawn by Flash; isolated fixture, no save or combat writes. */
class org.flashNight.arki.unit.Action.Melee.Cf6BladebotBeamRenderTest {
    private static var library:MovieClip,driver:MovieClip,actor:MovieClip,loader:MovieClipLoader;
    private static var listener:Object,bitmap:BitmapData,points:Array;
    private static var tickCount:Number,index:Number,passed:Number,failed:Number,settle:Number;
    private static var loaded:Boolean,done:Boolean;
    private static var activeState:String;
    private static var actors:Array;
    private static function check(value:Boolean,label:String):Void {
        if(value)passed++;else{failed++;trace("[TEST_FAIL] Cf6BladebotBeamRenderTest: "+label);}
    }
    public static function runAllTests():Void {
        tickCount=index=passed=failed=settle=0;loaded=done=false;points=[];activeState="";
        var forms:Array=[{form:0,states:["激光束"],counts:[31],tags:["beam"]}];
        var selected:Object={},keys:Array=[];
        for(var keyIndex:Number=0;keyIndex<keys.length;keyIndex++)selected[keys[keyIndex]]=true;
        for(var g:Number=0;g<forms.length;g++){
            var entry:Object=forms[g];
            for(var st:Number=0;st<entry.states.length;st++)for(var f:Number=1;f<=entry.counts[st];f++){
                var key:String=entry.tags[st]+"-"+f;
                points.push({form:0,state:"激光束",frame:11,key:"beam-left-11",side:1,capture:false});
        library=_root.createEmptyMovieClip("__bladeBeamRenderLibrary",_root.getNextHighestDepth());
        driver=_root.createEmptyMovieClip("__bladeBeamRenderDriver",_root.getNextHighestDepth());
        library._visible=false;_root.gameworld=library;
        _root.暂停=true;_root.是否阴影=true;_root.控制目标="__none";_root.控制目标全自动=false;
        _root.播放音效=function():Void {};_root.发布消息=function():Void {};_root.效果=function():Void {};
        _root.敌人函数={配置音效:function():Void {}};
        _root.初始化思考标签=function(mc:MovieClip):Void {mc.stop();mc._visible=false;};
        _root.初始化敌人模板=function():Void {
            this.hp=this.hp满血值=1000;this.等级=40;this.名字="原生绘制隔离大刀光束";
            this.状态="空手站立";this.方向="右";this.攻击目标="无";this.是否为敌人=true;
            this._x=this._y=this.Z轴坐标=0;this.myxscale=100;
            this.方向改变=function(direction:String):Void {this.方向=direction;this._xscale=direction=="左"?-100:100;};
            this.状态改变=function(state:String):Void {this.状态=state;this.gotoAndStop(state);};
            this.动画完毕=function():Void {};this.死亡检测=function():Void {};
            this.swapDepths=function():Void {};this.stop();
        };
        listener={onLoadInit:function(mc:MovieClip):Void {
            mc.stop();mc._visible=false;Cf6BladebotBeamRenderTest.actors=[mc.attachMovie("敌人-CF6大刀机器人","bladebot",mc.getNextHighestDepth())];
            Cf6BladebotBeamRenderTest.loaded=true;Cf6BladebotBeamRenderTest.tickCount=0;
        },onLoadError:function(mc:MovieClip,error:String):Void {Cf6BladebotBeamRenderTest.check(false,"load "+error);Cf6BladebotBeamRenderTest.finish();}};
        loader=new MovieClipLoader();loader.addListener(listener);bitmap=new BitmapData(1100,500,true,0);
        check(loader.loadClip("../flashswf/arts/new/Codex大刀机器人素材.swf",library),"load published SWF");
        driver.onEnterFrame=function():Void {Cf6BladebotBeamRenderTest.tick();};
    }
    private static function tick():Void {
        if(done)return;tickCount++;
        if(!loaded){if(tickCount>300){check(false,"load timeout");finish();}return;}
        if(tickCount==3){
            for(var form:Number=0;form<1;form++){
                var body:MovieClip=actors[form].man;
                check(body._width>50 && body._height>100,"native body geometry ready "+form);
                var box:Object=body.getBounds(actors[form]);
                trace("[BLADEBEAM_NATIVE_BOUNDS] form="+form+" x="+box.xMin+","+box.xMax+" y="+box.yMin+","+box.yMax);
            }
            if(failed>0){finish();return;}
        }
        if(tickCount<4)return;
        if(index>=points.length){finish();return;}
        var point:Object=points[index];
        if(activeState!=point.form+"|"+point.state){
            activeState=point.form+"|"+point.state;actor=actors[point.form];actor.hp=1000;
            actor.状态改变(point.state);
            settle=2;return;
        }
        if(settle>0){settle--;return;}
        index++;actor.方向改变(point.side==0?"右":"左");actor.man.gotoAndStop(point.frame);
        check(actor.man._currentframe==point.frame,"actual body frame "+point.key);
        var matrix:Matrix=actor.man.transform.matrix,sign:Number=point.side==0?1:-1;
        matrix.a*=1.2*sign;matrix.c*=1.2*sign;matrix.b*=1.2;matrix.d*=1.2;
        matrix.tx=matrix.tx*1.2*sign+(point.side==0?180:920);matrix.ty=matrix.ty*1.2+330;
        bitmap.fillRect(bitmap.rectangle,0);var start:Number=getTimer();bitmap.draw(actor.man,matrix);
        var first:Number=getTimer()-start,durations:Array=[];
        for(var i:Number=0;i<3;i++) {
            bitmap.fillRect(bitmap.rectangle,0);start=getTimer();bitmap.draw(actor.man,matrix);durations.push(getTimer()-start);
        }
        var drawn:Object=bitmap.getColorBoundsRect(0xffffffff,0,false);
        var visible:Number=drawn.width*drawn.height;
        check(visible>0,"nonempty native drawing "+point.key);
        trace("[BLADEBEAM_RENDER_SAMPLE] key="+point.key+" firstMs="+first+" repeatMs="+durations.join(",")+" boundsArea="+visible);
    }
    private static function finish():Void {
        if(done)return;done=true;delete driver.onEnterFrame;
        loader.removeListener(listener);bitmap.dispose();library.removeMovieClip();driver.removeMovieClip();
        trace("Cf6BladebotBeamRenderTest: "+passed+" passed, "+failed+" failed; "+index+" draw points");
        _root.cf6BladebotBeamRenderComplete();
    }
}