/** Actual compiled actor/body frames must call the native-SFX root route exactly once. */
class org.flashNight.arki.unit.Action.Melee.Cf6AudioTest {
    private static var library:MovieClip,actor:MovieClip,driver:MovieClip,loader:MovieClipLoader,listener:Object;
    private static var batches:Array,calls:Array,rows:Array,batch:Number,index:Number,phase:Number,age:Number;
    private static var passed:Number,failed:Number,visited:Number;
    private static var loaded:Boolean,done:Boolean,recording:Boolean;
    private static function check(ok:Boolean,label:String):Void {
        if(ok)passed++;else{failed++;trace("[TEST_FAIL] Cf6AudioTest: "+label);}
    }
    public static function runAllTests():Void {
        batches=_root.cf6AudioBatches;passed=failed=visited=batch=0;done=false;recording=false;calls=[];
        _root.暂停=false;_root.是否阴影=false;_root.控制目标全自动=false;
        _root.播放音效=function(name:String):Void {if(Cf6AudioTest.recording)Cf6AudioTest.calls.push(name);};
        _root.效果=_root.发布消息=_root.子弹区域shoot=_root.子弹区域shoot传递=function():Void {};
        _root.初始化思考标签=function(mc:MovieClip):Void {mc.stop();mc._visible=false;};
        _root.子弹属性初始化=function():Object {return {};};
        _root.敌人函数={配置音效:function():Void {},行走:function():Void {},大学军校学员随机兵器表:["M16"]};
        _root.主角函数={};
        _root.护盾函数={添加临时护盾:function():Number {return 1;},移除护盾:function():Boolean {return true;}};
        _root.地图元件={停止地图元件破碎动画:function():Void {},地图元件破碎动画运行中:function():Boolean {return false;}};
        _root.初始化敌人模板=function():Void {
            this.hp=this.hp满血值=1000;this.空手攻击力=100;this.等级=50;this._x=300;this._y=this.Z轴坐标=250;
            this.状态="空手站立";this.方向="右";this.攻击目标="无";this.攻击模式="空手";this.unitAI={data:{}};
            this.硬直中=this.倒地=this.浮空=false;this.myxscale=100;this.长枪="M16";
            this.动画完毕=this.行走=this.移动=this.swapDepths=this.死亡检测=this.攻击呐喊=this.中招呐喊=this.击倒呐喊=this.击飞浮空=this.击飞倒地=function():Void {};
            this.状态改变=function(s:String):Void {this.状态=s;};this.方向改变=function():Void {};this.stop();
        };
        driver=_root.createEmptyMovieClip("__cf6AudioDriver",_root.getNextHighestDepth());
        driver.onEnterFrame=function():Void {
            try{Cf6AudioTest.tick();}
            catch(error){Cf6AudioTest.check(false,"native fixture exception "+error);Cf6AudioTest.finish();}
        };loadBatch();
    }
    private static function loadBatch():Void {
        loaded=false;age=0;index=0;phase=0;rows=batches[batch].cases;
        library=_root.createEmptyMovieClip("__cf6AudioLibrary"+batch,_root.getNextHighestDepth());
        library._visible=false;_root.gameworld=library;
        listener={onLoadInit:function(mc:MovieClip):Void {mc.stop();Cf6AudioTest.loaded=true;Cf6AudioTest.nextCase();},
            onLoadError:function(mc:MovieClip,error:String):Void {Cf6AudioTest.check(false,"library load "+error);Cf6AudioTest.finish();}};
        loader=new MovieClipLoader();loader.addListener(listener);
        check(loader.loadClip(batches[batch].swf,library),"load actual library "+batches[batch].owner);
    }
    private static function nextCase():Void {
        recording=false;_root.暂停=false;
        if(actor!=null)actor.removeMovieClip();
        if(index>=rows.length){
            loader.removeListener(listener);library.removeMovieClip();batch++;
            if(batch>=batches.length){finish();return;}loadBatch();return;
        }
        var row:Object=rows[index];
        actor=library.attachMovie(row.linkage,"audioActor"+index,library.getNextHighestDepth(),{老头变身:false,光头保安变身:false,特种兵初始阶段:2});
        check(actor!=null,"actual actor "+batch+"/"+index);_root.控制目标=actor._name;phase=0;age=0;
    }
    private static function tick():Void {
        if(done)return;age++;
        if(!loaded){if(age>300){check(false,"library timeout");finish();}return;}
        var row:Object=rows[index],body:MovieClip=actor.man;
        if(phase==0 && age>=2){
            var idle:Function=function():Void {};
            actor.动画完毕=actor.行走=actor.移动=actor.manmanTick=actor.wingsTick=actor.guardTick=actor.soldierTick=actor.elderTick=actor.headbotTick=actor.bladebotTick=idle;
            actor.headbotBodyTick=actor.elderBodyTick=actor.bladebotBodyTick=actor.guardBodyTick=actor.guardTransformTick=idle;
            actor.状态改变=function(s:String):Void {this.状态=s;};actor.状态=row.state;
            calls=[];recording=row.onLoad;actor.gotoAndStop(row.rootFrame);phase=1;age=0;return;
        }
        if(phase==1 && age>=2){
            body=actor.man;check(body!=null && body._totalframes>=row.frame,"real body/frame "+batch+"/"+index);
            if(body==null){index++;nextCase();return;}body.stop();
            if(row.onLoad){verify(row);return;}
            recording=false;body.gotoAndStop(row.quiet);if(row.once)body.cf6DeathVoicePlayed=false;
            calls=[];_root.暂停=row.pause;recording=true;body.gotoAndStop(row.frame);phase=2;age=0;return;
        }
        if(phase==2 && age>=1){
            body.stop();
            if(!row.pause){verify(row);return;}
            check(calls.length==0,"paused native cue is silent "+batch+"/"+index);
            recording=false;_root.暂停=false;body.gotoAndStop(row.quiet);if(row.once)body.cf6DeathVoicePlayed=false;
            calls=[];recording=true;body.gotoAndStop(row.frame);phase=3;age=0;return;
        }
        if(phase==3 && age>=1){body.stop();verify(row);}
    }
    private static function verify(row:Object):Void {
        if(row.once){
            var before:Number=calls.length;
            for(var branch:Number=0;branch<row.branches.length;branch++)actor.man.gotoAndStop(row.branches[branch]);
            check(calls.length==before,"death branch changes cannot repeat the voice "+batch+"/"+index);
        }
        recording=false;var matched:Boolean=false;
        for(var i:Number=0;i<row.sounds.length;i++)if(calls[0]==row.sounds[i])matched=true;
        check(calls.length==1 && matched,"one native route call "+batch+"/"+index+" expected="+row.sounds+" got="+calls);
        trace("[CF6_AUDIO_CALL] owner="+batches[batch].owner+" actor="+row.linkage+" rootFrame="+row.rootFrame+" bodyFrame="+row.frame+" calls="+calls);
        visited++;index++;nextCase();
    }
    private static function finish():Void {
        if(done)return;done=true;recording=false;_root.暂停=false;delete driver.onEnterFrame;
        var expected:Number=0;for(var b:Number=0;b<batches.length;b++)expected+=batches[b].cases.length;
        check(visited==expected,"all "+expected+" sound routes exercised");
        if(actor!=null)actor.removeMovieClip();if(library!=null)library.removeMovieClip();driver.removeMovieClip();
        trace("Cf6AudioTest: "+passed+" passed, "+failed+" failed; "+visited+" actual sound routes; libraries="+batches.length);
        _root.cf6AudioComplete();
    }
}
