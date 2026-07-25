import flash.display.BitmapData;
import flash.geom.Rectangle;
import org.flashNight.arki.corpse.DeathEffectRenderer;
import org.flashNight.gesh.object.ObjectUtil;

/**
 * 屏外尸体保留参数与 DeathEffectRenderer 实际位图写入回归。
 */
class org.flashNight.arki.corpse.DeathEffectRendererTest {
    private static var _passed:Number = 0;
    private static var _failed:Number = 0;
    private static var _caseCount:Number = 0;

    private static var _oldGameworld:Object;
    private static var _hadGameworld:Boolean;
    private static var _oldIsEnabled:Boolean;
    private static var _oldEnableCulling:Boolean;

    private static var _world:MovieClip;
    private static var _deadbody:MovieClip;
    private static var _bitmap:BitmapData;
    private static var _clearRect:Rectangle;
    private static var _screenWidth:Number;

    public static function runAllTests():Void {
        _passed = 0;
        _failed = 0;
        _caseCount = 0;
        trace("=== DeathEffectRendererTest start ===");

        snapshotState();
        try {
            setupScene();
            testParameterParsing();
            _caseCount++;
            testUnmarkedOffscreenIsCulled();
            _caseCount++;
            testMarkedOffscreenIsStampedAndRestored();
            _caseCount++;
            testExplicitFalseRemainsCulled();
            _caseCount++;
            testMarkedRotatedCorpseIsStampedAndRestored();
            _caseCount++;
            testUnmarkedOnscreenBehaviorIsUnchanged();
            _caseCount++;
            testGlobalDisableStillWins();
            _caseCount++;

            trace("DeathEffectRendererTest Tests Passed: " + _passed);
            trace("DeathEffectRendererTest Tests Failed: " + _failed);
            if (_failed > 0 || _caseCount != 7) {
                throw new Error("DeathEffectRendererTest failed: "
                    + _failed + " checks, " + _caseCount + "/7 cases");
            }
            trace("DeathEffectRendererTest Cases Passed: 7/7");
        } finally {
            cleanupScene();
            restoreState();
        }

        trace("=== DeathEffectRendererTest end ===");
    }

    private static function testParameterParsing():Void {
        var enabled:Object = {};
        var disabled:Object = {};
        ObjectUtil.cloneParameters(
            enabled, "称号:火凤堂赤旌,保留屏外尸体:true");
        ObjectUtil.cloneParameters(disabled, "保留屏外尸体:false");

        check(enabled.保留屏外尸体 === true,
            "C01 关卡 Parameters 将 true 解析为严格布尔值");
        check(disabled.保留屏外尸体 === false,
            "C01 false 不会误开启屏外尸体保留");
    }

    private static function testUnmarkedOffscreenIsCulled():Void {
        clearLayer();
        var target:MovieClip = makeTarget(
            "__corpseUnmarkedOffscreen", _screenWidth + 120, 80, true, undefined);

        DeathEffectRenderer.renderCorpse(target, 2);

        check(!isStampedAt(target),
            "C02 未标记屏外单位仍被离屏裁剪");
        check(target._visible === true,
            "C02 未标记单位的可见度不被渲染器改写");
        target.removeMovieClip();
    }

    private static function testMarkedOffscreenIsStampedAndRestored():Void {
        clearLayer();
        var target:MovieClip = makeTarget(
            "__corpseMarkedOffscreen", _screenWidth + 120, 100, false, true);

        DeathEffectRenderer.renderCorpse(target, 2);

        check(isStampedAt(target),
            "C03 已标记屏外单位写入尸体位图");
        check(target._visible === false,
            "C03 draw 后恢复单位原有隐藏状态");
        check(DeathEffectRenderer.enableCulling === true,
            "C03 特殊实例不会关闭全局离屏裁剪");
        target.removeMovieClip();
    }

    private static function testExplicitFalseRemainsCulled():Void {
        clearLayer();
        var target:MovieClip = makeTarget(
            "__corpseFalseOffscreen", _screenWidth + 120, 120, false, false);

        DeathEffectRenderer.renderCorpse(target, 2);

        check(!isStampedAt(target),
            "C04 显式 false 的屏外单位仍被裁剪");
        check(target._visible === false,
            "C04 显式 false 不触发临时可见");
        target.removeMovieClip();
    }

    private static function testMarkedRotatedCorpseIsStampedAndRestored():Void {
        clearLayer();
        var target:MovieClip = makeTarget(
            "__corpseMarkedRotated", _screenWidth + 120, 140, false, true);
        target._rotation = 90;

        DeathEffectRenderer.renderRotatedCorpse(target, 2);

        check(isStampedAt(target),
            "C05 旋转尸体入口同样支持屏外保留");
        check(target._visible === false,
            "C05 旋转尸体 draw 后恢复隐藏状态");
        target.removeMovieClip();
    }

    private static function testUnmarkedOnscreenBehaviorIsUnchanged():Void {
        clearLayer();
        var target:MovieClip = makeTarget(
            "__corpseUnmarkedOnscreen", 80, 160, true, undefined);

        DeathEffectRenderer.renderCorpse(target, 2);

        check(isStampedAt(target),
            "C06 未标记屏内单位继续正常贴尸体");
        check(target._visible === true,
            "C06 未标记屏内单位保持原有可见状态");
        target.removeMovieClip();
    }

    private static function testGlobalDisableStillWins():Void {
        clearLayer();
        var target:MovieClip = makeTarget(
            "__corpseMarkedDisabled", _screenWidth + 120, 180, false, true);
        DeathEffectRenderer.isEnabled = false;

        DeathEffectRenderer.renderCorpse(target, 2);

        check(!isStampedAt(target),
            "C07 全局尸体开关关闭时特殊标记不越权");
        check(target._visible === false,
            "C07 全局关闭时不会触碰单位可见度");
        DeathEffectRenderer.isEnabled = true;
        target.removeMovieClip();
    }

    private static function makeTarget(
        name:String,
        x:Number,
        y:Number,
        visible:Boolean,
        retainFlag:Object
    ):MovieClip {
        var target:MovieClip = _world.createEmptyMovieClip(
            name, _world.getNextHighestDepth());
        target._x = x;
        target._y = y;
        target.beginFill(0xFF3333, 100);
        target.moveTo(-6, -6);
        target.lineTo(6, -6);
        target.lineTo(6, 6);
        target.lineTo(-6, 6);
        target.lineTo(-6, -6);
        target.endFill();
        if (retainFlag !== undefined) {
            target.保留屏外尸体 = retainFlag;
        }
        target._visible = visible;
        return target;
    }

    private static function isStampedAt(target:MovieClip):Boolean {
        return _bitmap.getPixel32(
            Math.round(target._x), Math.round(target._y)) != 0;
    }

    private static function clearLayer():Void {
        _bitmap.fillRect(_clearRect, 0x00000000);
    }

    private static function setupScene():Void {
        _screenWidth = Math.max(Stage.width, 550);
        var bitmapWidth:Number = _screenWidth + 300;
        var bitmapHeight:Number = Math.max(Stage.height, 400) + 100;

        _world = _root.createEmptyMovieClip(
            "__deathEffectRendererTestWorld", _root.getNextHighestDepth());
        _root.gameworld = _world;
        _world._x = 0;
        _world._y = 0;
        _world._xscale = 100;
        _world._yscale = 100;

        _deadbody = _world.createEmptyMovieClip(
            "deadbody", _world.getNextHighestDepth());
        _deadbody.layers = new Array(3);
        _bitmap = new BitmapData(bitmapWidth, bitmapHeight, true, 0x00000000);
        _deadbody.layers[2] = _bitmap;
        _clearRect = new Rectangle(0, 0, bitmapWidth, bitmapHeight);

        DeathEffectRenderer.isEnabled = true;
        DeathEffectRenderer.enableCulling = true;
    }

    private static function cleanupScene():Void {
        if (_bitmap != null) {
            _bitmap.dispose();
            _bitmap = null;
        }
        _clearRect = null;
        if (_world != null) {
            _world.removeMovieClip();
            _world = null;
        }
        _deadbody = null;
    }

    private static function snapshotState():Void {
        _oldGameworld = _root.gameworld;
        _hadGameworld = _oldGameworld != undefined;
        _oldIsEnabled = DeathEffectRenderer.isEnabled;
        _oldEnableCulling = DeathEffectRenderer.enableCulling;
    }

    private static function restoreState():Void {
        if (_hadGameworld) {
            _root.gameworld = _oldGameworld;
        } else {
            delete _root.gameworld;
        }
        DeathEffectRenderer.isEnabled = _oldIsEnabled;
        DeathEffectRenderer.enableCulling = _oldEnableCulling;
        _oldGameworld = null;
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
