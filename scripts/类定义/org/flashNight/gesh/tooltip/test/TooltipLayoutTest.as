import org.flashNight.gesh.tooltip.TooltipLayout;
import org.flashNight.gesh.tooltip.TooltipConstants;
import org.flashNight.gesh.tooltip.ItemUseTypes;
import org.flashNight.gesh.tooltip.test.MockTooltipContainer;
import org.flashNight.gesh.tooltip.TooltipBridge;

/**
 * TooltipLayoutTest - 布局计算 + 分栏判定测试
 */
class org.flashNight.gesh.tooltip.test.TooltipLayoutTest {

    private static var testsRun:Number = 0;
    private static var testsPassed:Number = 0;
    private static var testsFailed:Number = 0;

    private static function assert(cond:Boolean, msg:String):Void {
        testsRun++;
        if (cond) { testsPassed++; trace("[PASS] " + msg); }
        else { testsFailed++; trace("[FAIL] " + msg); }
    }

    private static function assertEq(expected:Number, actual:Number, msg:String):Void {
        testsRun++;
        var diff:Number = expected - actual;
        if (diff < 0) diff = -diff;
        if (diff < 0.0001) { testsPassed++; trace("[PASS] " + msg); }
        else { testsFailed++; trace("[FAIL] " + msg + " expected=" + expected + " actual=" + actual); }
    }

    public static function runAllTests():Void {
        testsRun = testsPassed = testsFailed = 0;
        trace("--- TooltipLayoutTest ---");

        test_shouldSplitSmart_empty();
        test_shouldSplitSmart_long();
        test_shouldSplitSmart_threshold();
        test_estimateWidth_empty();
        test_estimateWidth_long();
        test_estimateWidth_mid();
        test_estimateMainWidth();
        test_applyIntroLayout_weapon();
        test_applyIntroLayout_default();
        test_positionTooltip();

        trace("--- TooltipLayoutTest: " + testsPassed + "/" + testsRun + " passed, " + testsFailed + " failed ---");
    }

    private static function test_shouldSplitSmart_empty():Void {
        assert(TooltipLayout.shouldSplitSmart("", "", null) == false, "shouldSplit empty+empty = false");
    }

    private static function test_shouldSplitSmart_long():Void {
        var longStr:String = "";
        for (var i:Number = 0; i < 100; i++) longStr += "测试描述内容";
        assert(TooltipLayout.shouldSplitSmart(longStr, "短简介", null) == true, "shouldSplit long = true");
    }

    private static function test_shouldSplitSmart_threshold():Void {
        // threshold=1 → 更容易触发
        var medStr:String = "";
        for (var i:Number = 0; i < 10; i++) medStr += "测试内容";
        assert(TooltipLayout.shouldSplitSmart(medStr, medStr, {threshold: 1}) == true, "shouldSplit low threshold = true");
    }

    private static function test_estimateWidth_empty():Void {
        var w:Number = TooltipLayout.estimateWidth("", undefined, undefined);
        assertEq(TooltipConstants.MIN_W, w, "estimateWidth empty = MIN_W");
    }

    private static function test_estimateWidth_long():Void {
        var longStr:String = "";
        for (var i:Number = 0; i < 200; i++) longStr += "测试超长文本内容";
        var w:Number = TooltipLayout.estimateWidth(longStr, undefined, undefined);
        assertEq(TooltipConstants.MAX_W, w, "estimateWidth long = MAX_W");
    }

    private static function test_estimateWidth_mid():Void {
        var midStr:String = "中等长度的测试文本";
        var w:Number = TooltipLayout.estimateWidth(midStr, undefined, undefined);
        assert(w >= TooltipConstants.MIN_W, "estimateWidth mid >= MIN_W");
        assert(w <= TooltipConstants.MAX_W, "estimateWidth mid <= MAX_W");
    }

    private static function test_estimateMainWidth():Void {
        var str1:String = "均匀内容行<BR>均匀内容行<BR>均匀内容行";
        var w1:Number = TooltipLayout.estimateMainWidth(str1, undefined, undefined);
        assert(w1 >= TooltipConstants.MIN_W, "estimateMainWidth uniform >= MIN_W");

        var str2:String = "短<BR>短<BR>短<BR>短<BR>短<BR>这是一行非常非常非常非常非常非常非常非常非常长的描述文本";
        var w2:Number = TooltipLayout.estimateMainWidth(str2, undefined, undefined);
        // 稀疏内容宽度应与均匀内容不同
        assert(w2 >= TooltipConstants.MIN_W, "estimateMainWidth sparse >= MIN_W");
    }

    private static function test_applyIntroLayout_weapon():Void {
        MockTooltipContainer.install();
        var bg:MovieClip = TooltipBridge.getIntroBackground();
        var text:MovieClip = TooltipBridge.getIntroTextBox();
        var icon:MovieClip = TooltipBridge.getIconTarget();

        var result:Object = TooltipLayout.applyIntroLayout(ItemUseTypes.TYPE_WEAPON, icon, bg, text, undefined);

        assertEq(TooltipConstants.TEXT_Y_EQUIPMENT, text._y, "applyIntroLayout weapon text._y=210");
        assert(bg._x < 0, "applyIntroLayout weapon bg._x < 0");
        assertEq(TooltipConstants.BASE_NUM + TooltipConstants.BG_HEIGHT_OFFSET, result.heightOffset, "applyIntroLayout weapon heightOffset");
        MockTooltipContainer.teardown();
    }

    private static function test_applyIntroLayout_default():Void {
        MockTooltipContainer.install();
        var bg:MovieClip = TooltipBridge.getIntroBackground();
        var text:MovieClip = TooltipBridge.getIntroTextBox();
        var icon:MovieClip = TooltipBridge.getIconTarget();

        var result:Object = TooltipLayout.applyIntroLayout("其他类型", icon, bg, text, undefined);
        var scaledWidth:Number = TooltipConstants.BASE_NUM * TooltipConstants.RATE;
        assertEq(scaledWidth, result.width, "applyIntroLayout default width");
        MockTooltipContainer.teardown();
    }

    private static function test_positionTooltip():Void {
        MockTooltipContainer.install();
        var tips:MovieClip = TooltipBridge.getTooltipContainer();
        var bg:MovieClip = TooltipBridge.getMainBackground();
        bg._width = 200;
        bg._height = 100;
        // 设置简介背景可见
        TooltipBridge.setVisibility("introBg", false);

        TooltipLayout.positionTooltip(tips, bg, 300, 200);

        // 在合理范围内（不超出屏幕）
        assert(tips._x >= 0, "positionTooltip x >= 0");
        assert(tips._y >= 0, "positionTooltip y >= 0");
        MockTooltipContainer.teardown();
    }
}
