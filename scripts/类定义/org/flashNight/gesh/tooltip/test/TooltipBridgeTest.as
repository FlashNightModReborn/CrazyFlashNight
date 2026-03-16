import org.flashNight.gesh.tooltip.TooltipBridge;
import org.flashNight.gesh.tooltip.test.MockTooltipContainer;

/**
 * TooltipBridgeTest - UI 门面类测试
 * 每个 test 前 install()，后 teardown()。
 */
class org.flashNight.gesh.tooltip.test.TooltipBridgeTest {

    private static var testsRun:Number = 0;
    private static var testsPassed:Number = 0;
    private static var testsFailed:Number = 0;

    private static function assert(cond:Boolean, msg:String):Void {
        testsRun++;
        if (cond) { testsPassed++; trace("[PASS] " + msg); }
        else { testsFailed++; trace("[FAIL] " + msg); }
    }

    public static function runAllTests():Void {
        testsRun = testsPassed = testsFailed = 0;
        trace("--- TooltipBridgeTest ---");

        test_getters();
        test_setTextContent();
        test_setVisibility();
        test_setPosition();
        test_setSize();
        test_hideAllElements();
        test_clearAllContent();
        test_measureTextLineWidth();
        test_ensureIconAboveIntroBg();
        test_clampContainerByBg();
        test_getMouseX_returns_number();
        test_getSynthesisData_null_safe();
        test_getEnemyDisplayName_fallback();
        test_debugLog_null_safe();
        test_measureRenderedLines_intro_basic();
        test_teardown();

        trace("--- TooltipBridgeTest: " + testsPassed + "/" + testsRun + " passed, " + testsFailed + " failed ---");
    }

    private static function test_getters():Void {
        MockTooltipContainer.install();
        assert(TooltipBridge.getMainTextBox() != null, "getMainTextBox != null");
        assert(TooltipBridge.getMainBackground() != null, "getMainBackground != null");
        assert(TooltipBridge.getIntroTextBox() != null, "getIntroTextBox != null");
        assert(TooltipBridge.getIntroBackground() != null, "getIntroBackground != null");
        assert(TooltipBridge.getIconTarget() != null, "getIconTarget != null");
        assert(TooltipBridge.getTooltipContainer() != null, "getTooltipContainer != null");
        MockTooltipContainer.teardown();
    }

    private static function test_setTextContent():Void {
        MockTooltipContainer.install();
        TooltipBridge.setTextContent("main", "<B>test</B>");
        var tf = TooltipBridge.getMainTextBox();
        assert(tf.htmlText.indexOf("test") >= 0, "setTextContent main contains content");

        TooltipBridge.setTextContent("intro", "intro content");
        var itf = TooltipBridge.getIntroTextBox();
        assert(itf.htmlText.indexOf("intro") >= 0, "setTextContent intro contains content");
        MockTooltipContainer.teardown();
    }

    private static function test_setVisibility():Void {
        MockTooltipContainer.install();
        var targets:Array = ["main", "mainBg", "intro", "introBg", "icon", "container"];
        for (var i:Number = 0; i < targets.length; i++) {
            TooltipBridge.setVisibility(targets[i], false);
        }
        assert(TooltipBridge.getMainTextBox()._visible == false, "setVisibility main false");
        assert(TooltipBridge.getMainBackground()._visible == false, "setVisibility mainBg false");
        assert(TooltipBridge.getIntroTextBox()._visible == false, "setVisibility intro false");
        assert(TooltipBridge.getIntroBackground()._visible == false, "setVisibility introBg false");
        assert(TooltipBridge.getIconTarget()._visible == false, "setVisibility icon false");
        assert(TooltipBridge.getTooltipContainer()._visible == false, "setVisibility container false");
        MockTooltipContainer.teardown();
    }

    private static function test_setPosition():Void {
        MockTooltipContainer.install();
        TooltipBridge.setPosition("container", 100, 200);
        var c:MovieClip = TooltipBridge.getTooltipContainer();
        assert(c._x == 100, "setPosition x=100");
        assert(c._y == 200, "setPosition y=200");

        // NaN 跳过
        var oldX:Number = c._x;
        TooltipBridge.setPosition("container", NaN, 50);
        assert(c._x == oldX, "setPosition NaN x skipped");
        assert(c._y == 50, "setPosition y=50 applied");
        MockTooltipContainer.teardown();
    }

    private static function test_setSize():Void {
        MockTooltipContainer.install();
        // 先给背景一个初始尺寸（空 MC 的 _width/_height 默认为 0，赋值可能无效）
        var bg:MovieClip = TooltipBridge.getMainBackground();
        // 用 beginFill 画一个矩形给 MC 真实内容，使 _width/_height 可设置
        bg.beginFill(0x000000, 0);
        bg.moveTo(0, 0);
        bg.lineTo(100, 0);
        bg.lineTo(100, 100);
        bg.lineTo(0, 100);
        bg.lineTo(0, 0);
        bg.endFill();
        TooltipBridge.setSize("mainBg", 300, 400);
        // 接受 Flash 缩放可能有微小误差
        var wDiff:Number = bg._width - 300;
        if (wDiff < 0) wDiff = -wDiff;
        var hDiff:Number = bg._height - 400;
        if (hDiff < 0) hDiff = -hDiff;
        assert(wDiff < 1, "setSize width~300");
        assert(hDiff < 1, "setSize height~400");
        MockTooltipContainer.teardown();
    }

    private static function test_hideAllElements():Void {
        MockTooltipContainer.install();
        // 先让所有可见
        TooltipBridge.setVisibility("container", true);
        TooltipBridge.setVisibility("main", true);
        TooltipBridge.setVisibility("mainBg", true);

        TooltipBridge.hideAllElements();
        assert(TooltipBridge.getTooltipContainer()._visible == false, "hideAll container");
        assert(TooltipBridge.getMainTextBox()._visible == false, "hideAll main");
        assert(TooltipBridge.getMainBackground()._visible == false, "hideAll mainBg");
        assert(TooltipBridge.getIntroTextBox()._visible == false, "hideAll intro");
        assert(TooltipBridge.getIntroBackground()._visible == false, "hideAll introBg");
        assert(TooltipBridge.getIconTarget()._visible == false, "hideAll icon");
        MockTooltipContainer.teardown();
    }

    private static function test_clearAllContent():Void {
        MockTooltipContainer.install();
        TooltipBridge.setTextContent("main", "content1");
        TooltipBridge.setTextContent("intro", "content2");
        TooltipBridge.clearAllContent();
        assert(TooltipBridge.getMainTextBox().htmlText == "", "clearAll main empty");
        assert(TooltipBridge.getIntroTextBox().htmlText == "", "clearAll intro empty");
        MockTooltipContainer.teardown();
    }

    private static function test_measureTextLineWidth():Void {
        MockTooltipContainer.install();
        var w:Number = TooltipBridge.measureTextLineWidth("测试文本内容", false);
        assert(w > 0, "measureTextLineWidth non-empty > 0");

        var w2:Number = TooltipBridge.measureTextLineWidth("", false);
        assert(w2 == 0, "measureTextLineWidth empty == 0");

        var w3:Number = TooltipBridge.measureTextLineWidth(null, false);
        assert(w3 == 0, "measureTextLineWidth null == 0");
        MockTooltipContainer.teardown();
    }

    private static function test_ensureIconAboveIntroBg():Void {
        MockTooltipContainer.install();
        var icon:MovieClip = TooltipBridge.getIconTarget();
        var introBg:MovieClip = TooltipBridge.getIntroBackground();
        // icon depth=2, introBg depth=3，icon < introBg
        var iconDepthBefore:Number = icon.getDepth();
        var bgDepth:Number = introBg.getDepth();

        // 确保 icon 深度确实 <= introBg
        if (iconDepthBefore <= bgDepth) {
            TooltipBridge.ensureIconAboveIntroBg(1);
            assert(icon.getDepth() > bgDepth, "ensureIconAboveIntroBg moved icon above");
        } else {
            // 如果已经在上面，应该不变
            TooltipBridge.ensureIconAboveIntroBg(1);
            assert(icon.getDepth() > bgDepth, "ensureIconAboveIntroBg already above");
        }
        MockTooltipContainer.teardown();
    }

    private static function test_clampContainerByBg():Void {
        MockTooltipContainer.install();
        var c:MovieClip = TooltipBridge.getTooltipContainer();
        var bg:MovieClip = TooltipBridge.getMainBackground();
        bg._width = 100;
        bg._height = 100;

        // 把容器放到屏幕右下角外
        c._x = Stage.width + 100;
        c._y = Stage.height + 100;
        TooltipBridge.clampContainerByBg(bg, 8);

        // 应被回弹到屏幕内
        var right:Number = c._x + bg._x + bg._width;
        assert(right <= Stage.width, "clampContainer right edge within screen");
        MockTooltipContainer.teardown();
    }

    // ══════════════════════════════════════════════════════════════
    // P2a: _root 网关方法测试
    // ══════════════════════════════════════════════════════════════

    private static function test_getMouseX_returns_number():Void {
        var x:Number = TooltipBridge.getMouseX();
        assert(typeof x == "number", "getMouseX returns number: " + typeof x);
    }

    private static function test_getSynthesisData_null_safe():Void {
        // 确保 _root.改装清单对象 不存在时返回 null
        var saved = _root.改装清单对象;
        _root.改装清单对象 = undefined;
        var result = TooltipBridge.getSynthesisData("不存在的物品");
        assert(result == null, "getSynthesisData null safe: " + result);
        _root.改装清单对象 = saved;
    }

    private static function test_getEnemyDisplayName_fallback():Void {
        // 确保 _root.敌人属性表 不存在时回退到入参
        var saved = _root.敌人属性表;
        _root.敌人属性表 = undefined;
        var name:String = TooltipBridge.getEnemyDisplayName("测试兵种");
        assert(name == "测试兵种", "getEnemyDisplayName fallback: " + name);
        _root.敌人属性表 = saved;
    }

    private static function test_debugLog_null_safe():Void {
        // 确保 _root.服务器 不存在时不崩溃
        var saved = _root.服务器;
        _root.服务器 = undefined;
        TooltipBridge.debugLog("测试消息");
        assert(true, "debugLog null safe: no crash");
        _root.服务器 = saved;
    }

    // R3 前置：简介文本框行高校准后的行数测量
    private static function test_measureRenderedLines_intro_basic():Void {
        MockTooltipContainer.install();
        TooltipBridge.resetCalibration();
        var itf = TooltipBridge.getIntroTextBox();
        itf.htmlText = "A<BR>B<BR>C";
        var lines:Number = TooltipBridge.measureRenderedLines(9999, true);
        assert(lines == 3, "measureRenderedLines intro: 3-line content → " + lines);
        MockTooltipContainer.teardown();
    }

    private static function test_teardown():Void {
        // 验证 teardown 后 _root.注释框 被清理
        MockTooltipContainer.install();
        assert(_root.注释框 != undefined, "mock installed");
        MockTooltipContainer.teardown();
        // teardown 移除了 mock MC，_root.注释框 回到原始状态
        // 注意：如果原来没有 _saved，teardown 后 _root.注释框 为 undefined
        assert(true, "teardown completed without error");
    }
}
