import org.flashNight.arki.scene.SceneCollisionManager;

import org.flashNight.arki.unit.UnitComponent.Initializer.ElementComponent.ObstacleRenderer;

/** SceneCollisionManager 聚合、完整重绘与卸载回归。 */
class org.flashNight.arki.scene.SceneCollisionManagerTest {
    private static var _passed:Number = 0;
    private static var _failed:Number = 0;
    private static var _caseCount:Number = 0;

    private static var _oldGameworld:Object;
    private static var _oldCollisionLayer:Object;
    private static var _oldXmin:Object;
    private static var _oldXmax:Object;
    private static var _oldYmin:Object;
    private static var _oldYmax:Object;
    private static var _oldDebugMode:Object;
    private static var _hadGameworld:Boolean;
    private static var _hadCollisionLayer:Boolean;
    private static var _hadXmin:Boolean;
    private static var _hadXmax:Boolean;
    private static var _hadYmin:Boolean;
    private static var _hadYmax:Boolean;
    private static var _hadDebugMode:Boolean;

    private static var _world:MovieClip;
    private static var _layer:MovieClip;
    private static var _replacementLayer:MovieClip;
    private static var _manager:SceneCollisionManager;

    public static function runAllTests():Void {
        _passed = 0;
        _failed = 0;
        _caseCount = 0;
        trace("=== SceneCollisionManagerTest start ===");
        snapshotRootState();
        try {
            setupScene();
            testCollisionSourcesAppendAndClone();
            _caseCount++;
            testMovieClipRegistrationIsStable();
            _caseCount++;
            testRedrawRetainsAllProductionSources();
            _caseCount++;
            testDisposeReleasesExactOldState();
            _caseCount++;

            trace("SceneCollisionManagerTest Tests Passed: " + _passed);
            trace("SceneCollisionManagerTest Tests Failed: " + _failed);
            if (_failed > 0 || _caseCount != 4) {
                throw new Error("SceneCollisionManagerTest failed: "
                    + _failed + " checks, " + _caseCount + "/4 cases");
            }
            trace("SceneCollisionManagerTest Cases Passed: 4/4");
        } finally {
            try {
                cleanupScene();
            } finally {
                // cleanup 自身异常也不得把 TestLoader 的 _root 指向测试 MC。
                restoreRootState();
            }
        }
        trace("=== SceneCollisionManagerTest end ===");
    }

    private static function testCollisionSourcesAppendAndClone():Void {
        check(_manager.collisions.length == 0
                && _manager.movieClipCollisions.length == 0,
            "C01 init starts with two empty replay collections");

        var first:Array = [{Point:["40,40", "80,40", "80,80", "40,80"]}];
        _manager.addCollisions(first);
        check(_manager.collisions.length == 1,
            "C01 first polygon source is registered");
        first[0].Point[0] = "999,999";
        check(_manager.collisions[0].Point[0] == "40,40",
            "C01 polygon source is deep-cloned from the caller");

        var second:Object = {
            Point:["120,40", "160,40", "160,80", "120,80"]
        };
        _manager.addCollisions(second);
        check(_manager.collisions.length == 2
                && _manager.collisions[0].Point[0] == "40,40"
                && _manager.collisions[1].Point[0] == "120,40",
            "C01 later addCollisions appends without replacing earlier sources");
        second.Point[0] = "888,888";
        check(_manager.collisions[1].Point[0] == "120,40",
            "C01 single-object source is also deep-cloned");
    }

    private static function testMovieClipRegistrationIsStable():Void {
        var dynamicMC:MovieClip = _world.createEmptyMovieClip(
            "__sceneCollisionDynamic", _world.getNextHighestDepth());
        var firstRect:Object = {xMin:240, yMin:40, xMax:270, yMax:70};
        var updatedRect:Object = {xMin:280, yMin:40, xMax:320, yMax:80};

        _manager.addMovieClipCollision(dynamicMC, firstRect);
        _manager.addMovieClipCollision(dynamicMC, updatedRect);
        check(_manager.movieClipCollisions.length == 1,
            "C02 re-registering one MC updates instead of duplicating it");
        check(_manager.movieClipCollisions[0].rect.xMin == 280,
            "C02 re-registration stores the latest bounds");
        updatedRect.xMin = 777;
        check(_manager.movieClipCollisions[0].rect.xMin == 280,
            "C02 MovieClip bounds are cloned from the caller");
    }

    private static function testRedrawRetainsAllProductionSources():Void {
        var obstacle:MovieClip = _world.createEmptyMovieClip(
            "__sceneCollisionOrdinaryObstacle", _world.getNextHighestDepth());
        obstacle.obstacle = true;
        obstacle.area = obstacle.createEmptyMovieClip("area", obstacle.getNextHighestDepth());
        obstacle.area.beginFill(0x000000);
        obstacle.area.moveTo(360, 40);
        obstacle.area.lineTo(400, 40);
        obstacle.area.lineTo(400, 80);
        obstacle.area.lineTo(360, 80);
        obstacle.area.lineTo(360, 40);
        obstacle.area.endFill();
        // TestLoader 动态空 MC 的原生 getRect 在 AVM1 testMovie 下可能返回 undefined；
        // 固定生产 API 的返回值，专项只验证 renderer→authority→redraw 生命周期。
        obstacle.area.getRect = function(referenceClip:MovieClip):Object {
            return {xMin:360, yMin:40, xMax:400, yMax:80};
        };
        ObstacleRenderer.renderObstacle(obstacle);

        _manager.redraw();
        _layer._visible = true;
        check(_layer.hitTest(60, 60, true),
            "C03 redraw restores the first polygon source");
        check(_layer.hitTest(140, 60, true),
            "C03 redraw restores the second polygon source");
        check(_layer.hitTest(300, 60, true),
            "C03 redraw restores a registered MovieClip collision");
        check(_manager.movieClipCollisions.length == 2
                && _manager.movieClipCollisions[1].mc === obstacle
                && _layer.hitTest(380, 60, true),
            "C03 production ObstacleRenderer registers and redraw restores the ordinary obstacle");

        var dynamicMC:MovieClip = _manager.movieClipCollisions[0].mc;
        dynamicMC.removeMovieClip();
        for (var i:Number = 0; i < 24; i++) _manager.update();
        _layer._visible = true;
        check(_manager.movieClipCollisions.length == 1
                && _manager.movieClipCollisions[0].mc === obstacle,
            "C03 unloaded dynamic MC is pruned without dropping the ordinary obstacle record");
        check(!_layer.hitTest(300, 60, true),
            "C03 pruned MovieClip geometry is absent after throttled redraw");
        check(_layer.hitTest(380, 60, true),
            "C03 ordinary obstacles survive the unload-triggered clear/redraw");
        check(_layer.hitTest(60, 60, true) && _layer.hitTest(140, 60, true),
            "C03 all appended polygon sources survive the unload-triggered redraw");
    }

    private static function testDisposeReleasesExactOldState():Void {
        var retained:MovieClip = _world.createEmptyMovieClip(
            "__sceneCollisionRetained", _world.getNextHighestDepth());
        _manager.addMovieClipCollision(
            retained, {xMin:440, yMin:40, xMax:470, yMax:70});
        var retainedRecord:Object =
            _manager.movieClipCollisions[_manager.movieClipCollisions.length - 1];

        _replacementLayer = _root.createEmptyMovieClip(
            "__sceneCollisionReplacement" + getTimer(), _root.getNextHighestDepth());
        _replacementLayer.beginFill(0x000000);
        _replacementLayer.moveTo(500, 40);
        _replacementLayer.lineTo(540, 40);
        _replacementLayer.lineTo(540, 80);
        _replacementLayer.lineTo(500, 80);
        _replacementLayer.lineTo(500, 40);
        _replacementLayer.endFill();
        _root.collisionLayer = _replacementLayer;

        _manager.dispose();
        _layer._visible = true;
        _replacementLayer._visible = true;
        check(_manager.collisionLayer == null
                && _manager.collisions == null
                && _manager.movieClipCollisions == null,
            "C04 dispose clears layer and both replay collections");
        check(retainedRecord.mc == null && retainedRecord.rect == null,
            "C04 dispose severs retained old MovieClip/rect references");
        check(!_layer.hitTest(60, 60, true) && !_layer.hitTest(380, 60, true),
            "C04 dispose clears the exact old collision layer");
        check(_replacementLayer.hitTest(520, 60, true),
            "C04 dispose never clears a replacement root collision layer");

        _manager.dispose();
        check(_manager.collisionLayer == null
                && _manager.collisions == null
                && _manager.movieClipCollisions == null,
            "C04 dispose is idempotent");
    }

    private static function setupScene():Void {
        _world = _root.createEmptyMovieClip(
            "__sceneCollisionWorld" + getTimer(), _root.getNextHighestDepth());
        _world.createEmptyMovieClip("地图", _world.getNextHighestDepth());
        _layer = _root.createEmptyMovieClip(
            "__sceneCollisionLayer" + getTimer(), _root.getNextHighestDepth());
        _root.gameworld = _world;
        _root.collisionLayer = _layer;
        _root.Xmin = 0;
        _root.Xmax = 600;
        _root.Ymin = 0;
        _root.Ymax = 300;
        _root.调试模式 = false;
        _manager = SceneCollisionManager.getInstance();
        _manager.init();
    }

    private static function cleanupScene():Void {
        if (_manager != null) _manager.dispose();
        if (_replacementLayer != null) _replacementLayer.removeMovieClip();
        if (_layer != null) _layer.removeMovieClip();
        if (_world != null) _world.removeMovieClip();
        _replacementLayer = null;
        _layer = null;
        _world = null;
    }

    private static function snapshotRootState():Void {
        _hadGameworld = _root.hasOwnProperty("gameworld");
        _hadCollisionLayer = _root.hasOwnProperty("collisionLayer");
        _hadXmin = _root.hasOwnProperty("Xmin");
        _hadXmax = _root.hasOwnProperty("Xmax");
        _hadYmin = _root.hasOwnProperty("Ymin");
        _hadYmax = _root.hasOwnProperty("Ymax");
        _hadDebugMode = _root.hasOwnProperty("调试模式");
        _oldGameworld = _root.gameworld;
        _oldCollisionLayer = _root.collisionLayer;
        _oldXmin = _root.Xmin;
        _oldXmax = _root.Xmax;
        _oldYmin = _root.Ymin;
        _oldYmax = _root.Ymax;
        _oldDebugMode = _root.调试模式;
    }

    private static function restoreRootState():Void {
        if (_hadGameworld) _root.gameworld = _oldGameworld;
        else delete _root.gameworld;
        if (_hadCollisionLayer) _root.collisionLayer = _oldCollisionLayer;
        else delete _root.collisionLayer;
        if (_hadXmin) _root.Xmin = _oldXmin;
        else delete _root.Xmin;
        if (_hadXmax) _root.Xmax = _oldXmax;
        else delete _root.Xmax;
        if (_hadYmin) _root.Ymin = _oldYmin;
        else delete _root.Ymin;
        if (_hadYmax) _root.Ymax = _oldYmax;
        else delete _root.Ymax;
        if (_hadDebugMode) _root.调试模式 = _oldDebugMode;
        else delete _root.调试模式;
    }

    private static function check(condition:Boolean, message:String):Void {
        if (condition) {
            _passed++;
            trace("PASS: " + message);
        } else {
            _failed++;
            trace("FAIL: " + message);
        }
    }
}
