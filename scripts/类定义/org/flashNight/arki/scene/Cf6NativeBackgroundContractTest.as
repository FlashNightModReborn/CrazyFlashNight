import org.flashNight.arki.scene.*;
import org.flashNight.arki.weather.WeatherSystem;
import org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;
import flash.display.BitmapData;

/** Native background SWFs + the actual production bake function. No save or game command is issued. */
class org.flashNight.arki.scene.Cf6NativeBackgroundContractTest {
    private static var passed:Number,failed:Number,index:Number,frames:Number,bakes:Number,turretCalls:Number;
    private static var before:Object,stageBefore:Object,sceneBefore:Object,definitionBefore:Object;
    private static var weatherGetter:Function,findHero:Function,turretBegin:Function,productionBake:Function;
    private static var world:MovieClip,driver:MovieClip,loader:MovieClipLoader,listener:Object;
    private static var ids:Array=["A01"];
    private static var ready:Boolean,started:Boolean,finished:Boolean;
    private static var intervalId:Number;
    public static function captureRoot():Void {
        before={};
        var keys:Array=["gameworld","_saveExt","savePath","当前关卡名","暂停","控制目标","贴背景图","发布消息","collisionLayer","add2map","add2map2","add2map3","调试模式"];
        for(var i:Number=0;i<keys.length;i++) before[keys[i]]=_root[keys[i]];
    }
    private static function check(value:Boolean,message:String):Void {
        if(value) passed++;else {failed++;trace("[FAIL] Cf6NativeBackground: "+message);}
    }
    public static function runAllTests():Void {
        trace("NativeBackground.RunStart");passed=0;failed=0;index=-1;finished=false;
        var stage:Object=org.flashNight.arki.scene.StageManager;
        var scene:Object=org.flashNight.arki.scene.SceneManager;
        var definition:Object=org.flashNight.arki.scene.BookDefinition;
        var weather:Object=org.flashNight.arki.weather.WeatherSystem;
        var target:Object=org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;
        var turret:Object=org.flashNight.arki.scene.Cf6TutorialTurretService;
        stageBefore=stage.instance;sceneBefore=scene.instance;definitionBefore=definition._type61;
        weatherGetter=weather.getInstance;findHero=target.findHero;turretBegin=turret.beginRoom;
        productionBake=_root.贴背景图;
        weather.getInstance=function():Object {return {};};
        target.findHero=function():MovieClip {return _root.gameworld.hero;};
        turret.beginRoom=function():Boolean {org.flashNight.arki.scene.Cf6NativeBackgroundContractTest.turretObserved();return true;};
        _root.贴背景图=function(force:Boolean) {return org.flashNight.arki.scene.Cf6NativeBackgroundContractTest.recordBake(force);};
        _root.发布消息=function(message:String):Void {trace("[CF6_NATIVE_BACKGROUND_MESSAGE] "+message);};
        _root.暂停=false;_root.控制目标="hero";_root.调试模式=false;
        driver=_root.createEmptyMovieClip("__cf6NativeBackgroundContract",_root.getNextHighestDepth());
        intervalId=setInterval(function():Void {org.flashNight.arki.scene.Cf6NativeBackgroundContractTest.tick();},50);
        trace("NativeBackground.Timer id="+intervalId+" root="+_root._target+" driver="+driver._target+" depth="+driver.getDepth());
        org.flashNight.arki.scene.Cf6NativeBackgroundContractTest.advanceCase();
    }
    public static function turretObserved():Void {turretCalls++;}
    public static function recordBake(force:Boolean) {
        trace("NativeBackground.BakeEnter");bakes++;
        trace("NativeBackground.BakeTarget timer="+getTimer()+" world="+world._target+" bg="+world.背景._target+" size="+world.背景._width+"x"+world.背景._height+" fn="+typeof productionBake);
        var result;
        try {result=productionBake.call(_root,force);}
        catch(error) {trace("NativeBackground.BakeException "+error);return false;}
        var bg:MovieClip=world.背景;
        trace("[CF6_NATIVE_BACKGROUND_BAKE] map="+ids[index]+" result="+result+" width="+bg._width+" height="+bg._height
            +" drawn="+world.__cf6BackgroundBake.drawCompleted+" matrix="+Cf6MapPresentation.matchesBake(world,StageReturnFlow.worldIdentity(world),bg,world.__cf6BackgroundBake));
        return result;
    }
    private static function advanceCase():Void {
        trace("NativeBackground.AdvanceCase");cleanWorld();index++;
        if(index==ids.length) {finish();return;}
        frames=0;bakes=0;turretCalls=0;ready=false;started=false;
        world=_root.createEmptyMovieClip("__cf6NativeBackgroundWorld",_root.getNextHighestDepth());
        _root.gameworld=world;
        var hero:MovieClip=world.createEmptyMovieClip("hero",20);hero.hp=100;hero._x=200;hero._y=600;
        world.createEmptyMovieClip("效果",30);
        var body:MovieClip=world.createEmptyMovieClip("deadbody",0);
        body.layers=[new BitmapData(2048,1024,true,0)];body.layerOriginX=body.layerOriginY=0;body.attachBitmap(body.layers[0],0);
        var bg:MovieClip=world.createEmptyMovieClip("背景",1);
        bg.已更新环境配置=true;
        var child:MovieClip=bg.createEmptyMovieClip("外部动画加载壳mc",0);
        _root.savePath="cf6.native.background.fixture";
        _root.当前关卡名="书中历险-毒刺行动";
        _root._saveExt={bookRun:{bookId:"cf6-sting",routeId:"type61",outcome:"active",slot:String(_root.savePath),seed:17,startedAt:1793100000000}};
        var filename:String=ids[index]=="TUTORIAL" ? "CF6_Tutorial_BG.swf" : "CF6_"+ids[index]+"_BG.swf";
        world.场景背景url="flashswf/backgrounds/cf6/"+filename;
        var definition:Object=org.flashNight.arki.scene.BookDefinition;
        definition._type61={maps:[{id:ids[index],background:"cf6/"+filename,presentation:{scale:128/75,backgroundX:0,backgroundY:0}}]};
        var stage:Object=org.flashNight.arki.scene.StageManager;
        stage.instance={currentStage:0,gameworld:world,isActive:true,isFailed:false,isFinished:false};
        var scene:Object=org.flashNight.arki.scene.SceneManager;
        scene.instance=null;var manager:Object=SceneManager.getInstance();manager.gameworld=world;
        StageReturnFlow.worldIdentity(world);
        trace("NativeBackground.Load "+world.场景背景url+" world="+world._target+" bg="+bg._target+" child="+child._target+" depth="+world.getDepth());
        if(world._parent!==_root || bg._parent!==world || child._parent!==bg) {loadFailed("fixture target hierarchy invalid");return;}
        loader=new MovieClipLoader();listener={};
        listener.onLoadComplete=function(target:MovieClip):Void {trace("NativeBackground.LoadComplete target="+target._target);org.flashNight.arki.scene.Cf6NativeBackgroundContractTest.loaded();};
        listener.onLoadError=function(target:MovieClip,error:String):Void {org.flashNight.arki.scene.Cf6NativeBackgroundContractTest.loadFailed(error);};
        loader.addListener(listener);
        if(!loader.loadClip("../"+world.场景背景url,child)) loadFailed("loadClip rejected");
    }
    public static function loaded():Void {ready=true;frames=0;}
    public static function loadFailed(message:String):Void {check(false,ids[index]+" actual SWF failed to load: "+message);finish();}
    public static function tick():Void {
        if(finished) return;
        if(frames<6) trace("NativeBackground.Tick frames="+frames+" ready="+ready+" started="+started+" driver="+driver._name+" world="+world._name);
        frames++;
        if(!ready) {if(frames>900) loadFailed("watchdog");return;}
        if(!started) {
            if(frames<4) return;
            started=true;frames=0;
            var config:Object={layers:[],assetScale:128/75};
            if(ids[index]=="A01") config.turrets={nativeContractProbe:true};
            trace("NativeBackground.BeforeMechanism");
            try {Cf6MapMechanism.beginRoom(world,StageReturnFlow.worldIdentity(world),ids[index],config);}
            catch(error) {check(false,"begin exception "+error);}
            trace("NativeBackground.AfterMechanism");
            return;
        }
        if(frames<12) return;
        var state:Object=world.__cf6Mechanism,bg:MovieClip=world.背景;
        trace("[CF6_NATIVE_BACKGROUND_AFTER] map="+ids[index]+" width="+bg._width+" height="+bg._height+" failed="+state.failed
            +" phase="+state.phase+" prepared="+state.backgroundPrepared+" bakes="+bakes+" bitmap="+world.deadbody.layers[0].width+"x"+world.deadbody.layers[0].height);
        check(state.failed!==true && state.backgroundPrepared===true,ids[index]+" native background permits room initialization");
        check(bakes==1,ids[index]+" real bake is never replayed");
        check(Cf6MapPresentation.matchesBake(world,StageReturnFlow.worldIdentity(world),bg,world.__cf6BackgroundBake),ids[index]+" actual draw stores exact world/matrix identity");
        check(world._xscale==100 && world.hero._xscale==100,ids[index]+" bake does not scale actors or physics world");
        var pixels:BitmapData=world.deadbody.layers[0],visible:Number=0;
        for(var x:Number=100;x<1700;x+=100) for(var y:Number=100;y<800;y+=100) if((pixels.getPixel32(x,y)>>>24)>0) visible++;
        check(visible>5,ids[index]+" the actual background contributes colored pixels");
        if(ids[index]=="A01") check(turretCalls==1 && state.turretBound===true,"A01 reaches the production turret delegate exactly once");
        org.flashNight.arki.scene.Cf6NativeBackgroundContractTest.advanceCase();
    }
    private static function cleanWorld():Void {
        if(loader!=null) loader.removeListener(listener);loader=null;listener=null;
        Cf6MapMechanism.teardown();
        if(world!=undefined && world._parent===_root) {
            var layers:Array=world.deadbody.layers;
            for(var i:Number=0;i<layers.length;i++) if(layers[i] instanceof BitmapData) layers[i].dispose();
            world.removeMovieClip();
        }
        world=null;
    }
    private static function finish():Void {
        if(finished) return;finished=true;cleanWorld();
        clearInterval(intervalId);delete driver.onEnterFrame;driver.removeMovieClip();driver=null;
        var stage:Object=org.flashNight.arki.scene.StageManager;stage.instance=stageBefore;
        var scene:Object=org.flashNight.arki.scene.SceneManager;scene.instance=sceneBefore;
        var definition:Object=org.flashNight.arki.scene.BookDefinition;definition._type61=definitionBefore;
        var weather:Object=org.flashNight.arki.weather.WeatherSystem;weather.getInstance=weatherGetter;
        var target:Object=org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;target.findHero=findHero;
        var turret:Object=org.flashNight.arki.scene.Cf6TutorialTurretService;turret.beginRoom=turretBegin;
        if(_root.collisionLayer!==before.collisionLayer) _root.collisionLayer.removeMovieClip();
        for(var key:String in before) _root[key]=before[key];
        trace("Cf6NativeBackgroundContractTest Tests Passed: "+passed);
        trace("Cf6NativeBackgroundContractTest Tests Failed: "+failed);
        _root.cf6NativeBackgroundComplete();
    }
}
