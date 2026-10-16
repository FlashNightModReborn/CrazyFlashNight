/** 真实EnterFrame接续测试：晚到世界、同路径重建、换槽。 */
class org.flashNight.arki.scene.SceneTransitionGuardHandoffTest {
    private static var passed:Number;
    private static var failed:Number;
    private static var fixture:MovieClip;
    private static var controller:MovieClip;
    private static var manager:Object;
    private static var ticks:Number;
    private static var worldDepth:Number;
    private static var saved:Object;
    private static var targetFrame:Number;
    private static function check(value:Boolean, label:String):Void {
        if (value) passed++; else { failed++; trace("[TEST_FAIL] SceneTransitionGuardHandoff " + label); }
    }
    public static function runAllTests():Void {
        passed = 0; failed = 0; ticks = 0;
        backgroundPaths();
        fixture = _root.createEmptyMovieClip("__leeHandoffAsyncFixture", _root.getNextHighestDepth());
        saved = {slot:_root.savePath, ext:_root._saveExt, fade:_root.淡出动画,
            world:_root.gameworld, battle:_root.当前为战斗地图, navigation:_root.__leeStageNavigationIdentity, changing:_root.场景转换中};
        targetFrame = Number(_root._currentframe);
        _root.savePath = "bookrun.async.fixture";
        _root._saveExt = {bookRun:{bookId:"lee-trial", slot:_root.savePath, outcome:"active"}};
        _root.淡出动画 = {__transitionProjectionIdentity:{}};
        _root.当前为战斗地图 = false;
        _root.场景转换中 = false;
        _root.gameworld = undefined;
        manager = {isActive:true, isFailed:false, isFinished:false, currentStage:-1, calls:0, rejected:0, root:_root,
            initStage:function():Void {
                if (this.root.淡出动画.__returnFadeActive === true || this.root.场景转换中 === true) {
                    this.rejected++; this.isActive = false; return;
                }
                this.calls++; this.currentStage++; this.root.当前为战斗地图 = true;
            }};
        org.flashNight.arki.scene.SceneTransitionGuard.watchLeeStageNavigation(_root,manager,targetFrame);
        worldDepth = fixture.getNextHighestDepth();
        controller = _root.createEmptyMovieClip("__leeHandoffAsyncController", _root.getNextHighestDepth());
        controller.onEnterFrame = org.flashNight.arki.scene.SceneTransitionGuardHandoffTest.tick;
    }
    private static function backgroundPaths():Void {
        var paths:Object = org.flashNight.arki.ui.SceneTransitionService;
        var name:String = "hthhltnb_3_BG.swf";
        check(paths.resolveBackgroundUrl("flashswf/backgrounds/" + name) == "flashswf/backgrounds/" + name,
            "existing canonical flat background route is unchanged");
        check(paths.resolveBackgroundUrl("flashswf/backgrounds/black-dragon-original/" + name)
                == "flashswf/backgrounds/black-dragon-original/" + name,
            "original assault background directory survives real resource URL resolution");
        check(paths.resolveBackgroundUrl("flashswf/" + name) == "flashswf/backgrounds/" + name,
            "legacy pre-relocation background path retains the existing flat route");
        check(paths.resolveBackgroundUrl(name) == "flashswf/backgrounds/" + name,
            "bare legacy background name retains the existing flat route");
        check(paths.resolveBackgroundUrl("flashswf/backgrounds/../" + name) == "flashswf/backgrounds/" + name,
            "parent-directory input is not granted a new full-path route");
    }

    private static function makeWorld():Void {
        var world:MovieClip = fixture.createEmptyMovieClip("gameworld",worldDepth);
        world.场景名 = "wuxianguotu_1";
        world.dispatcher = {};
        _root.gameworld = world;
    }
    private static function clearWorld():Void {
        fixture.gameworld.removeMovieClip();
        _root.gameworld = undefined;
        _root.当前为战斗地图 = false;
    }
    public static function tick():Void {
        ticks++;
        if (ticks == 6 || ticks == 12 || ticks == 18)
            trace("[LeeHandoffAsyncProbe] tick=" + ticks + " calls=" + manager.calls
                + " stage=" + manager.currentStage + " rootFrame=" + _root._currentframe
                + " state=" + _root.__leeStageLoadHandoff.__leeStageLoadState
                + " world=" + fixture.gameworld.场景名 + " dispatcher=" + typeof fixture.gameworld.dispatcher);
        if (ticks == 1) {
            _root.淡出动画 = {__transitionProjectionIdentity:{}};
            makeWorld();
        }
        if (ticks == 6) {
            check(manager.calls == 1 && manager.currentStage == 0,
                "world arriving after registration initializes once through real EnterFrame");
            check(_root.__leeStageLoadHandoff.__leeStageLoadState == "initialized",
                "persistent method records the completed initialization");
            clearWorld();
            org.flashNight.arki.scene.SceneTransitionGuard.watchLeeStageNavigation(_root,manager,targetFrame);
        }
        if (ticks == 7) makeWorld();
        if (ticks == 8) { clearWorld(); makeWorld(); }
        if (ticks == 12) {
            check(manager.calls == 1, "same-path world replacement cannot initialize a different world");
            check(_root.__leeStageLoadHandoff.__leeStageLoadState == "world_replaced",
                "world replacement retires its callback before another initialization");
            clearWorld();
            org.flashNight.arki.scene.SceneTransitionGuard.watchLeeStageNavigation(_root,manager,targetFrame);
            _root.savePath = "bookrun.other.fixture";
        }
        if (ticks == 13) makeWorld();
        if (ticks == 18) {
            check(manager.calls == 1, "slot switch cancels a waiting real EnterFrame continuation");
            check(_root.__leeStageLoadHandoff.__leeStageLoadState == "context_changed",
                "slot cancellation leaves no live retry");
            clearWorld();
            _root.savePath = "bookrun.async.fixture";
            org.flashNight.arki.scene.SceneTransitionGuard.watchLeeStageNavigation(_root,manager,targetFrame);
            org.flashNight.arki.scene.SceneTransitionGuard.beginNavigation(_root);
        }
        if (ticks == 19) makeWorld();
        if (ticks == 24) {
            check(manager.calls == 1, "a new accepted navigation cancels the old real-frame initializer");
            check(_root.__leeStageLoadHandoff.__leeStageLoadState == "navigation_replaced",
                "business navigation replacement retires its callback independently of the visual fade");
            _root.淡出动画.__returnFadeActive = true;
            _root.场景转换中 = true;
            org.flashNight.arki.scene.SceneTransitionGuard.initializeStage(_root,manager);
            check(manager.calls == 1 && manager.rejected == 0 && manager.isActive === true,
                "native load before fade frame17 keeps the stage-start reservation untouched");
        }
        if (ticks == 28) {
            check(manager.calls == 1 && manager.rejected == 0,
                "real EnterFrame does not initialize while the original cover owns admission");
            _root.淡出动画.__returnFadeActive = false;
        }
        if (ticks == 30) {
            check(manager.calls == 1 && manager.rejected == 0,
                "scene-changing authority also delays initialization without clearing its flag");
            _root.场景转换中 = false;
        }
        if (ticks == 36) {
            check(manager.calls == 2 && manager.rejected == 0 && manager.currentStage == 1
                    && _root.__leeStageLoadHandoff.__leeStageLoadState == "initialized",
                "normal admission release initializes the existing world exactly once");
            _root.当前为战斗地图 = false;
            _root.淡出动画.__returnFadeActive = true;
            org.flashNight.arki.scene.SceneTransitionGuard.initializeStage(_root,manager);
            org.flashNight.arki.scene.SceneTransitionGuard.beginNavigation(_root);
        }
        if (ticks == 42) {
            _root.淡出动画.__returnFadeActive = false;
        }
        if (ticks == 48) {
            check(manager.calls == 2 && _root.__leeStageLoadHandoff.__leeStageLoadState == "navigation_replaced",
                "a cancelled cover wait cannot resume a different accepted navigation");
            _root._saveExt.bookRun.bookId = "another-stage";
            org.flashNight.arki.scene.SceneTransitionGuard.initializeStage(_root,manager);
            check(manager.calls == 3,"other stage initialization keeps its original immediate path");
            _root._saveExt.bookRun.bookId = "lee-trial";
            org.flashNight.arki.scene.SceneTransitionGuard.initializeStage(_root,manager);
            check(manager.calls == 4,"Lee native initialization remains immediate after admission is ready");
            delete controller.onEnterFrame;
            _root.场景转换中 = saved.changing;
            _root.savePath = saved.slot; _root._saveExt = saved.ext; _root.淡出动画 = saved.fade;
            _root.gameworld = saved.world; _root.当前为战斗地图 = saved.battle;
            _root.__leeStageNavigationIdentity = saved.navigation;
            fixture.removeMovieClip();
            trace("SceneTransitionGuardHandoffTest Tests Passed: " + passed);
            trace("SceneTransitionGuardHandoffTest Tests Failed: " + failed);
            _root.__leeHandoffTestsComplete();
            controller.removeMovieClip();
        }
    }
}
