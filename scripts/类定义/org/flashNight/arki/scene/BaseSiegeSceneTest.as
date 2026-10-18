import org.flashNight.arki.scene.*;
import org.flashNight.gesh.depth.DepthManager;
import org.flashNight.gesh.path.PathManager;
import org.flashNight.neur.Event.EventBus;
import flash.geom.Matrix;
import flash.display.BitmapData;

/** Native world/art/guard timelines and production input/clear routes; no saves. */
class org.flashNight.arki.scene.BaseSiegeSceneTest {
    public static var stages:Array;
    private static var world:MovieClip;
    private static var watch:MovieClip;
    private static var actor:MovieClip;
    private static var ticks:Number;
    private static var phase:Number;
    private static var sceneIndex:Number;
    private static var activation:Number;
    private static var counter:Number;
    private static var baked:Boolean;
    private static var saved:Object;
    private static var passed:Number;
    private static var failed:Number;
    private static var library:MovieClip;
    private static var units:MovieClip;
    private static var levelLoader:MovieClipLoader;
    private static var unitLoader:MovieClipLoader;
    public static function runAllTests():Void {
        passed=0;failed=0;ticks=0;phase=0;activation=0;counter=0;baked=false;
        saved={world:_root.gameworld,clock:_root.帧计时器,hero:_root.控制目标,
            ymin:_root.Ymin,ymax:_root.Ymax,pause:_root.暂停,transition:_root.场景转换中,
            init:_root.初始化敌人模板,spawn:_root.加载游戏世界人物,sound:_root.播放音效,
            types:_root.兵种库,bake:_root.贴背景图};
        _root.帧计时器={eventBus:EventBus.getInstance()};
        _root.Ymin=274;_root.Ymax=640;_root.暂停=false;_root.场景转换中=false;
        _root.播放音效=function(name:String):Void {};
        _root.兵种库={};
        // HP/collider infrastructure is a fixture. Area/man/state frames are native.
        _root.初始化敌人模板=function():Void {
            this.hp=this.hp_max;this.aabbCollider={updateFromUnitArea:function(mc:MovieClip):Void {}};
        };
        _root.加载游戏世界人物=function(id:String,name:String,depth:Number,init:Object):MovieClip {
            var loaded:MovieClip=_root.gameworld.attachMovie(id,name,depth,init);
            trace("BaseSiegeSceneTest NativeSpawn: id="+id+" name="+name+" result="+loaded);
            return loaded;
        };
        setupWorld();
    }
    public static function loadUnits():Void {
        units=_root.createEmptyMovieClip("__siegeNativeUnits",_root.getNextHighestDepth());
        unitLoader=new MovieClipLoader();
        unitLoader.addListener({onLoadInit:function(mc:MovieClip):Void {org.flashNight.arki.scene.BaseSiegeSceneTest.setupWorld();}});
        unitLoader.loadClip("../flashswf/arts/new/素材库-诺亚新敌人.swf",units);
    }
    public static function setupWorld():Void {
        world=_root.__siegeNativeWorld;world._x=0;world._y=0;
        _root.gameworld=world;
        check(world._name!=undefined && world.门1._name!=undefined,"actual native battle-world template attaches");
        SceneManager.getInstance().initGameWorld(world);
        DepthManager.instance.calibrate(274,640);
        var scene:SceneManager=SceneManager.getInstance();
        scene.addInstance({x:170,y:430},"door0");scene.addInstance({x:1460,y:550},"door1");
        scene.addBodyLayers(1688,640);
        _root.贴背景图=function():Void {org.flashNight.arki.scene.BaseSiegeSceneTest.bakeBackground();};
        world.背景._x=0;world.背景._y=0;
        world.背景.createEmptyMovieClip("native",world.背景.getNextHighestDepth()).loadMovie("../flashswf/backgrounds/gk1_3_BG_围攻.swf");
        actor=world.createEmptyMovieClip("hero",world.getNextHighestDepth());
        actor.hp=100;_root.控制目标="hero";
        world.dispatcher.subscribe("SiegeRelayActivated",recordActivation,BaseSiegeSceneTest);
        world.dispatcher.subscribe("SiegeCounterattack",recordCounter,BaseSiegeSceneTest);
        var manager:Object=StageManager.getInstance();
        manager.isActive=true;manager.isFailed=false;manager.isFinished=false;manager.isCleared=false;
        manager.gameworld=world;manager.currentStage=1;manager.stageInfoList=[{},{},{},{},{},{},{},{}];
        manager.currentStageInfo={basicInfo:{Animation:{}}};manager.stageMode="legacy";
        manager.spawner=WaveSpawner.getInstance();
        beginRoom(1);
        watch=_root.createEmptyMovieClip("__siegeSceneTestWatch",_root.getNextHighestDepth());
        watch.onEnterFrame=function():Void {org.flashNight.arki.scene.BaseSiegeSceneTest.tick();};
    }
    private static function beginRoom(index:Number):Void {
        sceneIndex=index;ticks=0;
        var rows:Array=StageInfo.parseInstanceInfo(stages[index]);
        for(var i:Number=0;i<2;i++){
            var name:String="stageInstance"+i;
            DepthManager.instance.removeMovieClip(world[name]);world[name].removeMovieClip();
            SceneManager.instance.addInstance({url:PathManager.resolvePath(rows[i].url),x:rows[i].x,y:rows[i].y,Parameters:rows[i].Parameters},name);
        }
        _global.ASSetPropFlags(world,["stageInstance0","stageInstance1"],1,false);
        DepthManager.instance.removeMovieClip(world.siege_relay_guard);world.siege_relay_guard.removeMovieClip();
        var spawner:Object=WaveSpawner.instance;
        spawner.gameworld=world;spawner.spawnPoints=[];spawner.isActive=true;spawner.isFinished=false;spawner.totalWave=2;
        var manager:Object=StageManager.instance;manager.isCleared=false;manager.isFailed=false;manager.isFinished=false;
        setHero(index==1?1610:555,index==1?455:600);
        BaseSiegeController.start(index==1?"rhino":index==2?"tigr":"roof");
        if(index!=7)BaseSiegeController.signal("enable");
    }
    private static function setHero(x:Number,y:Number):Void {
        actor._x=x;actor._y=y;actor.Z轴坐标=y;DepthManager.instance.updateDepth(actor,y);
    }
    public static function recordActivation():Void {
        activation++;
        var events:Array=stages[sceneIndex].Event;
        trace("BaseSiegeSceneTest Activation: scene="+sceneIndex+" eventCount="+events.length);
        for(var i:Number=0;i<events.length;i++)if(events[i].EventName=="SiegeRelayActivated"){
            var stageEvent:StageEvent=new StageEvent({EventName:"SiegeRelayActivated",Enemy:events[i].Enemy});stageEvent.execute();
        }
    }
    public static function recordCounter():Void {counter++;}
    public static function bakeBackground():Void {
        var mat:Matrix=world.背景.transform.matrix.clone();
        world.deadbody.layers[0].draw(world.背景,mat);world.背景.unloadMovie();baked=true;
    }
    public static function tick():Void {
        ticks++;
        var a:MovieClip=world.stageInstance0;var b:MovieClip=world.stageInstance1;
        var state:Object=BaseSiegeController.snapshot();
        if(ticks>210){trace("BaseSiegeSceneTest Timeout: phase="+phase+" guard="+world.siege_relay_guard+" hp="+world.siege_relay_guard.hp+" area="+world.siege_relay_guard.area+" state="+typeof world.siege_relay_guard.状态改变);check(false,"native scene phase "+phase+" timed out");finish();return;}
        if(phase==0){
            if(ticks<30)return;
            check(a.__siegeReady===true && b.__siegeReady===true,"actual parallel external devices initialize");
            check(state.assetsReady===true && !state.observerActive,"loading receipt removes the temporary observer");
            check(a._width>50 && a._height>100 && baked,"coil remains visible with a baked native background");
            check(a._xscale==40 && b._xscale==60 && a.getDepth()==DepthManager.instance.getDepth(a),"native scene scale and sorting survive load");
            check(SceneInteractionManager.instance.currentMC===world.__siegeOperation,"rhino birth position is inside the device interaction range");
            check(probeCoilOcclusion(),"coil hides a character behind it and reveals a character in front");
            var fixedBodyPixel:Number=world.deadbody.layers[0].getPixel(1104,336);
            a.removeMovieClip();
            check(fixedBodyPixel<=0x707070 && world.deadbody.layers[0].getPixel(1104,336)==fixedBodyPixel,"no duplicate coil remains in the baked background after state movie removal");
            world.dispatcher.publish("HeroMoved",actor._x,actor.Z轴坐标);
            check(BaseSiegeController.snapshot().assetsReady===false,"prop removal starts event-driven recovery");
            EventBus.instance.publish("interactionKeyDown");
            check(activation==0,"input while art is recovering cannot consume activation");
            phase=1;ticks=0;return;
        }
        if(phase==1){
            if(ticks<3 || state.assetsReady!==true)return;
            check(a._name!=undefined && a._width>50 && a.getDepth()==DepthManager.instance.getDepth(a),"removed native coil reloads with correct depth ownership");
            check(SceneInteractionManager.instance.currentMC===world.__siegeOperation,"loading completion refreshes interaction for an unmoved hero");
            EventBus.instance.publish("interactionKeyDown");
            check(BaseSiegeController.snapshot().deployed===true && activation==1,"real global interaction event activates at rhino birth position");
            phase=2;ticks=0;return;
        }
        if(phase==2){
            if(ticks<3 || state.guardReady!==true || state.coilAnimation!="none")return;
            check(counter==1 && world.siege_relay_guard.hp==5000,"native protection-unit initialization releases the counterattack once");
            check(world.siege_relay_guard.man._visible===false && world.siege_relay_guard.area._width==50,"actual guard timeline uses the map art and resized hitbox");
            check(a.interferenceMC._currentframe==49 && a.interferenceMC._visible===true && a.shieldMC._visible===false && a.effectPowered._visible===true && a._width>50 && a._height>100,"R5 interference endpoint remains visible after the transition");
            EventBus.instance.publish("interactionKeyDown");check(activation==1,"repeat global input cannot duplicate the guard");
            check(BaseSiegeController.interceptClear(StageManager.instance,world),"normal clear still requires finishing the defense");
            testDebugClear();beginRoom(2);phase=3;return;
        }
        if(phase==3){
            if(ticks<3 || state.assetsReady!==true)return;
            EventBus.instance.publish("interactionKeyDown");
            check(BaseSiegeController.snapshot().deployed===true && activation==2,"tigr uses the same real interaction event at its device");
            phase=4;ticks=0;return;
        }
        if(phase==4){
            if(ticks<3 || state.guardReady!==true)return;
            check(counter==2 && world.siege_relay_guard._x==580,"tigr counterattack binds its own native guard target");
            testDebugClear();beginRoom(7);phase=5;return;
        }
        if(phase==5){
            if(ticks<3 || state.assetsReady!==true)return;
            check(a._width>100 && b._totalframes==3,"roof native props load in the real scene container");
            testDebugClear();
            var manager:Object=StageManager.instance;manager.isCleared=false;manager.isFailed=true;
            check(!_root.调试_完成当前地图() && manager.isFailed && !manager.isCleared,"debug cannot rewrite an already finalized failure as victory");
            finish();
        }
    }
    private static function probeCoilOcclusion():Boolean {
        var probe:MovieClip=world.createEmptyMovieClip("__siegeDepthProbe",world.getNextHighestDepth());
        probe._x=1096;probe._y=318;
        probe.beginFill(0xFF00FF,100);probe.moveTo(0,0);probe.lineTo(20,0);probe.lineTo(20,30);probe.lineTo(0,30);probe.lineTo(0,0);probe.endFill();
        var bitmap:BitmapData=new BitmapData(64,64,true,0);
        var mat:Matrix=new Matrix(1,0,0,1,-1090,-310);
        DepthManager.instance.updateDepth(probe,330);bitmap.draw(world,mat);var rear:Number=bitmap.getPixel(14,26);
        DepthManager.instance.updateDepth(probe,420);bitmap.fillRect(bitmap.rectangle,0);bitmap.draw(world,mat);var front:Number=bitmap.getPixel(14,26);
        bitmap.dispose();DepthManager.instance.removeMovieClip(probe);probe.removeMovieClip();
        return rear!=0xFF00FF && front==0xFF00FF;
    }
    private static function testDebugClear():Void {
        var manager:StageManager=StageManager.instance;
        check(_root.调试_完成当前地图() && manager.isCleared && world.允许通行,"explicit modifier action opens the native exit in scene "+sceneIndex);
        check(WaveSpawner.instance.isFinished && !WaveSpawner.instance.isActive && !BaseSiegeController.snapshot().observerActive,"debug completion stops queued spawns and load observers in scene "+sceneIndex);
    }
    private static function finish():Void {
        delete watch.onEnterFrame;watch.removeMovieClip();
        BaseSiegeController.start("lobby");DepthManager.instance.dispose();DepthManager.instance=null;
        world.deadbody.layers[0].dispose();world.deadbody.layers[1].dispose();world.deadbody.layers[2].dispose();
        world.removeMovieClip();library.removeMovieClip();units.removeMovieClip();_root.gameworld=saved.world;_root.帧计时器=saved.clock;_root.控制目标=saved.hero;
        _root.Ymin=saved.ymin;_root.Ymax=saved.ymax;_root.暂停=saved.pause;_root.场景转换中=saved.transition;
        _root.初始化敌人模板=saved.init;_root.加载游戏世界人物=saved.spawn;_root.播放音效=saved.sound;
        _root.兵种库=saved.types;_root.贴背景图=saved.bake;StageManager.instance.isActive=false;
        trace("BaseSiegeSceneTest Tests Passed: "+passed);trace("BaseSiegeSceneTest Tests Failed: "+failed);
        trace("FocusedTestRunId base-siege Complete: "+_root.__baseSiegeFocusedRunId);
    }
    private static function check(value:Boolean,label:String):Void {
        if(value)passed++;else {failed++;trace("BaseSiegeSceneTest FAIL: "+label);}
    }
}
