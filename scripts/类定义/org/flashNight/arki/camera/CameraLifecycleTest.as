import flash.display.BitmapData;
import org.flashNight.arki.camera.HorizontalScroller;
import org.flashNight.arki.camera.ZoomController;
import org.flashNight.arki.scene.SharedScenePlacement;
import org.flashNight.arki.scene.SceneManager;
import org.flashNight.arki.item.LootContainerService;
/** 无存档、无业务写的真实 MovieClip / authored 多帧相机夹具。 */
class org.flashNight.arki.camera.CameraLifecycleTest {
    private static var passed:Number;
    private static var failed:Number;
    private static var runId:String;
    private static var phase:Number;
    private static var waitFrames:Number;
    private static var cycles:Number;
    private static var world:MovieClip;
    private static var identity:Object;
    private static var scope:Object;
    private static var lowDepth:Number;
    private static var priorDriver:Number;
    public static var nativeDriverCount:Number;

    private static function check(value:Boolean, label:String):Void {
        if (value) passed++; else { failed++; trace("[CAMERA_FAIL] " + label); }
    }
    private static function closeWorld():Void {
        var w:MovieClip = _root.gameworld;
        if (w == undefined) return;
        var id:Object = w.__stageReturnWorldIdentity;
        HorizontalScroller.releaseScene(w,id,HorizontalScroller.sceneScope(w,id));
        w.swapDepths(_root.getNextHighestDepth()); w.removeMovieClip();
    }
    private static function fixture(width:Number):MovieClip {
        closeWorld();
        _root.cameraZoomToggle = false; _root.basicZoomScale = 1; _root.启用后景 = false;
        _root.控制目标 = "hero";
        _root.帧计时器 = {当前帧数:0,offsetTolerance:0};
        var w:MovieClip = _root.createEmptyMovieClip("gameworld",_root.getNextHighestDepth());
        w.__stageReturnWorldIdentity = {}; w.背景长 = width; w.背景高 = 800;
        var h:MovieClip = w.createEmptyMovieClip("hero",1); h._x = 1200; h._y = 400;
        HorizontalScroller.onSceneChanged(w,undefined,w.__stageReturnWorldIdentity);
        return w;
    }
    private static function info():Object { return HorizontalScroller.getInstance().getDebugInfo(); }
    private static function step():Void { _root.帧计时器.当前帧数++; HorizontalScroller.update(); }

    public static function start(id:String):Void {
        runId=id;passed=failed=0;phase=0;cycles=0;nativeDriverCount=0;
        _root.__cameraSuite = true; _root.__cameraAutoDriver = false;
        _root.createEmptyMovieClip("天空盒",_root.getNextHighestDepth());
        _root.天空盒.地平线高度 = 240;
        trace("CameraLifecycleRun Start: " + runId);
        semanticTests();
        framingTests();
        closeWorld();
        lowDepth = _root.gameworld层级定位器.getDepth();
        check(lowDepth < 0,"authored anchor begins in negative timeline slot");
        check(_root.修改工具界面.getDepth() > lowDepth,"authored menu is above world slot");
        beginShared();
        _root.__cameraAutoDriver = true;
        var pump:MovieClip = _root.createEmptyMovieClip("__cameraTestPump",_root.getNextHighestDepth());
        pump.onEnterFrame = function():Void { CameraLifecycleTest.pulse(); };
    }
    private static function semanticTests():Void {
        var w:MovieClip = fixture(2400);
        var id:Object = w.__stageReturnWorldIdentity;
        var s:Object = HorizontalScroller.sceneScope(w,id);
        check(!HorizontalScroller.hasInitialPose(w,id,s),"Ready alone cannot satisfy initial pose fence");
        step();
        var expected:Number = Stage.width*0.5-100-w.hero._x;
        check(w._x == expected,"first pose uses direction-aware composition without long pan");
        check(HorizontalScroller.hasInitialPose(w,id,s),"first successful commit opens exact pose fence");
        w.hero._x += 4;
        for (var i:Number=0;i<12;i++) step();
        check(w._x < expected-2,"low-tolerance fractional progress is accumulated");
        check(w._x == Math.round(w._x),"world presentation remains integer");

        var target:MovieClip = w.createEmptyMovieClip("focus",2);target._x=1500;target._y=400;
        var f:Object=HorizontalScroller.pushFocus(target,10,true,5,0,0,0,3,{});
        step();
        check(info().focus.offsetTolerance === 0,"tol=0 survives public facade");
        check(info().focus.easeFactor === 5,"snap preserves authored follow ease");
        check(f.snapPending === false,"snap consumed by first legal commit");
        var before:Number=w._x;target._x+=20;step();
        check(Math.abs(w._x-before)<10 && Math.abs(w._x-before)>0,"later focus frames ease rather than snap");
        var count:Number=info().focusDepth;
        HorizontalScroller.onSceneChanged(w,undefined,id);
        check(HorizontalScroller.sceneScope(w,id)===s && info().focusDepth===count,"duplicate Ready preserves scope and active focus");
        check(HorizontalScroller.releaseFocus(f),"exact current focus handle can release");step();
        check(info().focusDepth===0,"released focus removed");
        var bottom:Object=HorizontalScroller.pushFocus(target,1,false,5,0,0,0,0,{});
        var top:Object=HorizontalScroller.pushFocus(target,0,false,5,0,0,0,0,{});
        step();
        check(info().focusDepth===1,"expired finite focus cleared beneath permanent top");
        HorizontalScroller.releaseFocus(top);step();
        check(info().focusDepth===0,"expiry cleanup does not revive expired lower entry");

        var oldHero:MovieClip=w.hero; var oldToken:Object=w.hero.__cameraTargetIdentity;
        w.hero.removeMovieClip();var replacement:MovieClip=w.createEmptyMovieClip("hero",1);
        replacement._x=1300;replacement._y=400;step();
        check(info().state==="WAIT_TARGET","same-path replacement cannot inherit old player binding");
        step();check(info().state==="WAIT_TARGET","valid coordinates do not clear hard binding fault");
        check(HorizontalScroller.onPlayerBound(w,id,replacement),"explicit player notification accepts new incarnation");step();
        check(info().state==="ACTIVE" && replacement.__cameraTargetIdentity!==oldToken,"new player identity unlocks binding");
        trace("CameraNativeAlias heroRebound=" + (oldHero===replacement));

        var cam:MovieClip=w.createEmptyMovieClip("virtual",3);cam._x=1000;cam._y=400;
        var owner:Object={};
        s=HorizontalScroller.bindExplicitScene(w,id,cam,owner,true);step();
        HorizontalScroller.onPlayerBound(w,id,replacement);step();
        check(info().mode==="EXPLICIT" && info().selected===cam,"player notification does not steal virtual camera");
        cam.removeMovieClip();step();
        check(info().state==="WAIT_TARGET" && info().mode==="EXPLICIT","deleted explicit base waits for owner");
        HorizontalScroller.followPlayer(false);step();
        check(info().state==="ACTIVE" && info().selected===replacement,"explicit followPlayer returns to latest player");

        target=w.createEmptyMovieClip("focus2",4);target._x=1600;target._y=400;
        f=HorizontalScroller.pushFocus(target,0,true,5,0,37,9,0,{});step();
        var composed:Number=w._x;
        var api:Object=HorizontalScroller.getInstance();api.stageWidth=17;
        HorizontalScroller.onFullScreenChanged();step();
        check(w._x===composed,"viewport refresh retains direction and focus bias composition");
        var oldWorld:MovieClip=w;var oldId:Object=id;var oldScope:Object=HorizontalScroller.sceneScope(w,id);
        var cacheApi:Object=org.flashNight.arki.camera.ZoomController;
        cacheApi.cachedFarthestEnemy=target;
        HorizontalScroller.releaseScene(w,id,oldScope);
        check(cacheApi.cachedFarthestEnemy==null,"scope release clears the zoom enemy MovieClip cache");
        HorizontalScroller.onSceneChanged(w,undefined,id);
        check(HorizontalScroller.sceneScope(w,id)==undefined,"late Ready cannot revive a retired camera before physical removal");
        oldScope=HorizontalScroller.bindExplicitScene(w,id,target,{},true);step();
        check(oldScope!=undefined,"new explicit owner may bind a fresh camera epoch within the same live world");
        oldWorld.__stageReturnWorldIdentity={};
        check(!HorizontalScroller.hasInitialPose(oldWorld,oldId,oldScope),"old pose cannot attest a replacement identity before its Ready");
        oldWorld.__stageReturnWorldIdentity=oldId;
        w=fixture(2400);id=w.__stageReturnWorldIdentity;step();
        s=HorizontalScroller.sceneScope(w,id);
        check(info().focusDepth===0,"new world clears old focus stack");
        check(!HorizontalScroller.releaseFocus(f),"old focus handle cannot affect new scope");
        check(!HorizontalScroller.releaseScene(oldWorld,oldId,oldScope),"late old teardown cannot release rebound world");
        HorizontalScroller.onSceneChanged(oldWorld,undefined,oldId);
        check(HorizontalScroller.sceneScope(w,id)===s,"late old Ready cannot reset current scope");

        var zoomApi:Object=ZoomController;var originalZoom:Function=zoomApi.updateScale;
        zoomApi.updateScale=function(t:MovieClip,g:MovieClip,b:MovieClip,e:Number,bs:Number,m:Number):Object {
            _root.__cameraSampledTarget=t;return {newScale:1,offsetX:0,offsetY:0};
        };
        _root.cameraZoomToggle=true;HorizontalScroller.refreshConfiguration();
        target=w.createEmptyMovieClip("expiry",5);target._x=1900;target._y=400;
        f=HorizontalScroller.pushFocus(target,1,false,5,0,0,0,3,{});step();
        check(_root.__cameraSampledTarget===w.hero && info().selected===w.hero,"expiry selects same target before zoom and scrolling");
        zoomApi.updateScale=originalZoom;
        _root.cameraZoomToggle=false;HorizontalScroller.refreshConfiguration();
        check(info().enableCameraZoom===false,"current-world camera toggle refreshes without scene reset");
        _root.basicZoomScale=1.25;step();
        check(w._xscale===125 && info().scale===1.25,"basic zoom applies in current scene");
        w=fixture(100);target=w.createEmptyMovieClip("tinyFocus",6);target._x=20;target._y=20;
        HorizontalScroller.pushFocus(target,1,false,5,0,0,0,0,{});step();
        check(info().focusDepth===0,"small-map early return cannot prevent focus expiry");
        check(w._x===0,"small map X axis is pinned to origin");
        closeWorld();
    }
    private static function framingTests():Void {
        var w:MovieClip=fixture(2400);w.hero._x=500;w.hero._y=450;
        var f:Object=HorizontalScroller.pushFocus(w.hero,0,true,5,0,0,0,0,{});
        var forged:Object={target:f.target,identity:f.identity,scope:f.scope,released:false};
        check(!HorizontalScroller.setFocusViewport(forged,0.25,0.8,[-550,-100,0,0]),"matching fields cannot fabricate a focus capability");
        check(HorizontalScroller.setFocusViewport(f,0.25,0.8,[-550,-100,0,0]),"authored framing accepts its exact live focus");
        step();
        check(Math.abs(w._x-(Stage.width*0.25-500))<0.6,"authored target uses viewport quarter rather than ordinary direction bias");
        check(Math.abs(w._y-((Stage.height-64)*0.8-450))<0.6,"authored vertical framing respects the playable viewport");
        var viewport:Object=f.viewport;
        check(!HorizontalScroller.setFocusViewport(f,-1,0.8,[-550,-100,0,0]) && f.viewport===viewport,"invalid screen fraction preserves current framing");
        check(!HorizontalScroller.setFocusViewport(f,0.25,0.8,[NaN,-100,0,0]) && f.viewport===viewport,"NaN camera boundary is rejected atomically");
        check(!HorizontalScroller.setFocusViewport(f,0.25,0.8,[10,-100,0,0]),"inverted authored boundary is rejected");
        var before:Number=w._x;w.hero._x+=20;step();
        check(Math.abs(w._x-before+4)<0.6,"authored focus follows with the original divide-by-five easing");
        w.hero._x=w.hero._y=4000;f.snapPending=true;step();
        check(w._x===-550 && w._y===-100,"authored world limits clamp both axes");
        _root.basicZoomScale=2;f.snapPending=true;step();
        check(w._x===-1100 && w._y===-200,"authored boundaries scale once with the live camera zoom");
        check(HorizontalScroller.releaseFocus(f),"authored framing releases through its existing focus handle");
        check(!HorizontalScroller.setFocusViewport(f,0.25,0.8,[-550,-100,0,0]),"released framing cannot be resurrected");
        w=fixture(100);w.hero._x=20;w.hero._y=400;
        var tiny:Object=HorizontalScroller.pushFocus(w.hero,0,true,5,0,0,0,0,{});
        HorizontalScroller.setFocusViewport(tiny,0.25,0.8,[-550,-100,0,0]);step();
        check(w._x===0,"authored bounds cannot reveal space beyond a smaller background");
        check(!HorizontalScroller.setFocusViewport(f,0.25,0.8,[-550,-100,0,0]),"old-world framing cannot alter a new scene");
        closeWorld();
    }
    private static function menuPixels(occluded:Boolean):Void {
        var pixels:BitmapData=new BitmapData(1024,576,false,0);
        pixels.draw(_root);
        check(pixels.getPixel(500,100)===0xDD3344,"native menu upper area is visible");
        check(pixels.getPixel(500,300)===(occluded ? 0x229966 : 0xDD3344),
            occluded ? "native world really covers menu lower half" : "native menu lower half stays above world");
        pixels.dispose();
    }
    private static function beginShared():Void {
        identity={};
        world=SharedScenePlacement.attach(_root,"CameraWorldFixture",{__stageReturnWorldIdentity:identity});
        check(world!=undefined,"shared world attaches with live authored anchor");
        check(world.getDepth()===lowDepth,"world receives original stable low slot");
        check(_root.修改工具界面.getDepth()>world.getDepth(),"visible menu stays above world");
        world.背景长=2400;world.背景高=800;
        var h:MovieClip=world.createEmptyMovieClip("hero",1);h._x=1200;h._y=400;
        _root.basicZoomScale=1;_root.cameraZoomToggle=false;
        _root.控制目标="hero";_root.修改工具界面._visible=true;
        HorizontalScroller.onSceneChanged(world,undefined,identity);
        scope=HorizontalScroller.sceneScope(world,identity);
        waitFrames=0;priorDriver=nativeDriverCount;
    }
    private static function detachShared():Void {
        check(SharedScenePlacement.preflightDetach(world,identity),"detach preflight accepts exact pairing");
        check(SharedScenePlacement.returnSlot(world,identity),"world returns original authored anchor slot");
        check(_root.gameworld层级定位器.getDepth()===lowDepth,"anchor restored before world removal");
        check(HorizontalScroller.releaseScene(world,identity,scope),"exact camera scope released");
        world.removeMovieClip();SharedScenePlacement.detached(world,identity);
        check(SharedScenePlacement.canReuse(_root,_root._currentframe),"successful teardown admits exact same-frame reuse");
    }
    public static function nativeDriver():Void {
        if (!_root.__cameraAutoDriver) return;
        nativeDriverCount++;
        _root.帧计时器.当前帧数++;
        HorizontalScroller.update();
    }
    public static function pulse():Void {
        waitFrames++;
        if (waitFrames>600) {check(false,"native phase watchdog");finish();return;}
        if (phase===0) {
            if (waitFrames<4) return;
            check(nativeDriverCount-priorDriver>1 && nativeDriverCount-priorDriver<6,"authored driver survives shared exchange");
            check(HorizontalScroller.hasInitialPose(world,identity,scope),"authored driver commits first pose");
            if (cycles===0) {
                menuPixels(false);
                var lootApi:Object=LootContainerService;var expire:Function=lootApi.expireScene;
                lootApi.expireScene=function(reason:String):Object{return {success:false};};
                var manager:Object=SceneManager.getInstance();manager.gameworld=world;manager.cleanupWorldIdentity=identity;
                check(manager.removeGameWorld()===false,"production loot barrier blocks teardown");
                check(world._parent===_root && world.getDepth()===lowDepth && HorizontalScroller.sceneScope(world,identity)===scope,
                    "blocked loot preserves world, pairing and camera scope");
                lootApi.expireScene=expire;manager.gameworld=null;manager.cleanupWorldIdentity=undefined;
                var savedDepth:Number=world.getDepth();world.swapDepths(_root.getNextHighestDepth());
                check(!SharedScenePlacement.preflightDetach(world,identity),"structural depth error rejected before disposal");
                world.swapDepths(savedDepth);
            }
            detachShared();cycles++;
            if (cycles<10) {beginShared();return;}
            check(SharedScenePlacement.retireIdle(_root),"forward navigation explicitly retires idle anchor");
            phase=1;waitFrames=0;_root.gotoAndPlay(2);return;
        }
        if (phase===1) {
            if (waitFrames<14) return;
            check(_root._currentframe===13 && _root.gameworld层级定位器._parent===_root,"forward play traverses loading frames and establishes new authored anchor");
            lowDepth=_root.gameworld层级定位器.getDepth();beginShared();phase=2;return;
        }
        if (phase===2) {
            if (waitFrames<4) return;
            check(nativeDriverCount-priorDriver>1 && nativeDriverCount-priorDriver<6,"forward scene has one live authored driver");
            detachShared();check(SharedScenePlacement.retireIdle(_root),"rewind retires exact anchor");
            phase=3;waitFrames=0;_root.gotoAndStop(1);return;
        }
        if (phase===3) {
            if (waitFrames<3) return;
            check(_root._currentframe===1 && _root.gameworld层级定位器._parent===_root,"rewind recreates authored anchor without stale duplicate");
            lowDepth=_root.gameworld层级定位器.getDepth();beginShared();phase=4;return;
        }
        if (phase===4) {
            if (waitFrames<4) return;
            check(nativeDriverCount-priorDriver>1 && nativeDriverCount-priorDriver<6,"rewound scene driver remains unique");
            // 重放修复前已核对的三个原生操作，实测 undefined swap 的继续执行与层级后果。
            HorizontalScroller.releaseScene(world,identity,scope);
            world.swapDepths(_root.getNextHighestDepth());world.removeMovieClip();
            _root.gameworld层级定位器.removeMovieClip();
            identity={};world=_root.attachMovie("CameraWorldFixture","gameworld",_root.getNextHighestDepth(),{__stageReturnWorldIdentity:identity});
            var beforeDepth:Number=world.getDepth();world.swapDepths(_root.gameworld层级定位器);
            trace("CameraNativeUndefinedSwap before="+beforeDepth+" after="+world.getDepth()+" menu="+_root.修改工具界面.getDepth());
            check(world._parent===_root,"undefined native swap does not abort world creation");
            check(world.getDepth()>_root.修改工具界面.getDepth(),"legacy missing-anchor world covers authored menu");
            var h:MovieClip=world.createEmptyMovieClip("hero",1);h._x=1200;h._y=400;world.背景长=2400;world.背景高=800;
            HorizontalScroller.onSceneChanged(world,undefined,identity);
            scope=HorizontalScroller.sceneScope(world,identity);priorDriver=nativeDriverCount;
            phase=5;waitFrames=0;return;
        }
        if (phase===5) {
            if (waitFrames<4) return;
            menuPixels(true);
            check(nativeDriverCount===priorDriver,"legacy cleanup removes actual authored camera driver");
            check(!HorizontalScroller.hasInitialPose(world,identity,scope),"Ready cannot hide missing-driver initial-pose failure");
            check(SharedScenePlacement.attach(_root,"CameraWorldFixture",{__stageReturnWorldIdentity:{}})==undefined,
                "new attach rejects broken placement before creating another visible world");
            finish();
        }
    }
    private static function finish():Void {
        _root.__cameraTestPump.onEnterFrame=undefined;_root.__cameraAutoDriver=false;
        closeWorld();
        trace("CameraLifecycleTest Tests Passed: "+passed);
        trace("CameraLifecycleTest Tests Failed: "+failed);
        trace("CameraLifecycleRun Complete: "+runId);
    }
}
