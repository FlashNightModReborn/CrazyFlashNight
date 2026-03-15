import org.flashNight.gesh.tooltip.TooltipLayout;
import org.flashNight.gesh.tooltip.TooltipConstants;
import org.flashNight.gesh.tooltip.ItemUseTypes;
import org.flashNight.gesh.tooltip.test.MockTooltipContainer;
import org.flashNight.gesh.tooltip.TooltipBridge;
import org.flashNight.gesh.string.StringUtils;

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

        // W/H ratio 红灯测试（当前算法应 FAIL，sqrt 公式应 PASS）
        test_ratio_dominator();
        test_ratio_sparseContent();
        test_ratio_longUniform();
        test_ratio_heavyGun();

        // 边界回归守卫
        test_estimateMainWidth_empty();
        test_estimateMainWidth_maxClamp();
        test_fromMetrics_matches_fromScores();

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

    // ══════════════════════════════════════════════════════════════
    // 宽度红灯测试
    // 当前算法对重内容物品输出过大的宽度（接近 MAX_W=650），
    // 导致 W/H > 2.5（过扁平）。
    // 断言宽度应显著小于 MAX_W，当前算法 FAIL，sqrt 公式 PASS。
    //
    // 真实物品诊断数据（Phase 5 输出）：
    //   dominator:    total=1087, maxLine=209, lines=16 → 当前W=650, sqrtW≈383
    //   MACSIII:      total=1047, maxLine=117, lines=15 → 当前W=650, sqrtW≈376
    //   吉他喷火器:   total=750,  maxLine=116, lines=11 → 当前W=623, sqrtW≈318
    //   混凝土切割机: total=672,  maxLine=90,  lines=10 → 当前W=513, sqrtW≈301
    // ══════════════════════════════════════════════════════════════

    // dominator: total=1087, maxLine=209, lines=16
    // 当前算法: W=650 (MAX_W clamp)
    // sqrt 公式: W≈383
    // 断言: W < 450 → 当前 FAIL (650>450), sqrt PASS (383<450)
    private static function test_ratio_dominator():Void {
        var w:Number = TooltipLayout.estimateMainWidthFromMetrics(1087, 209, 16, undefined, undefined);
        assert(w < 450, "ratio_dominator: W=" + Math.round(w) + " < 450 (should not hit MAX_W)");
    }

    // 稀疏内容：9短行+1超长行 (类似聚束射线弹/稀疏描述)
    // total=208, maxLine=190, lines=10
    // 当前算法: 偏向 totalBased (uniformity→0), W≈156 → 但受 lineBased 影响可能更大
    // 用更极端的数据: total=400, maxLine=350, lines=12
    // 当前算法: 偏 totalBased=300, lineBased=1945 → uniformity 低, 但仍偏大
    // 直接验证: 宽度不应超过 maxLine 对应的像素宽 + 合理边距
    private static function test_ratio_sparseContent():Void {
        // maxLine=350 → 最长行像素宽 ≈ 350*6 + 20 = 2120 (远超 MAX_W)
        // 但 total 只有 400，sqrt 公式: W ≈ sqrt(1.5*400*6*15) ≈ 328
        // 当前算法: totalBased=300, lineBased=1945, uniformity 很低 → W≈300~400
        // 用 maxLine=180, total=250 更贴近实际
        // 当前: totalBased=187.5, lineBased=1010, mean=250/12≈21, t=21/180≈0.12, ss≈0.02
        //   → W ≈ 1010*0.02 + 187.5*0.98 ≈ 204
        // sqrt: W = sqrt(0.83*250*6*15) ≈ 137 → clamp 150
        // 用 total=600, maxLine=350, lines=15 → 当前偏大
        var w:Number = TooltipLayout.estimateMainWidthFromMetrics(600, 350, 15, undefined, undefined);
        // 当前: totalBased=450, lineBased=1945, mean=40, t=40/350=0.11, ss≈0.02
        //   → W ≈ 1945*0.02 + 450*0.98 ≈ 479 → 实际可能被 MAX_W clamp
        // sqrt: W = sqrt(1.32*600*6*15) ≈ 268
        assert(w < 350, "ratio_sparse: W=" + Math.round(w) + " < 350");
    }

    // 15 行均匀中等: total=300, maxLine=20, lines=15
    // 当前算法: totalBased=225, lineBased=130, mean=20, t=20/20=1, ss=1
    //   → W = 130*1 + 225*0 = 130 → clamp MIN_W=150
    // sqrt: W = sqrt(1.16*300*6*15) ≈ 178
    // 用更重的数据: total=500, maxLine=35, lines=18
    // 当前: totalBased=375, lineBased=212.5, mean=27.8, t=27.8/35=0.79, ss=0.71
    //   → W ≈ 212.5*0.71 + 375*0.29 ≈ 260
    // sqrt: W = sqrt(1.4*500*6*15) ≈ 251
    // 这两个接近。用更大的: total=800, maxLine=40, lines=22
    // 当前: totalBased=600, lineBased=240, mean=36.4, t=36.4/40=0.91, ss=0.87
    //   → W ≈ 240*0.87 + 600*0.13 ≈ 287
    // sqrt: W = sqrt(1.5*800*6*15) ≈ 329 → 但 maxLineW = 260, clamp 到 260
    // 两者方向相反！用 total=800, maxLine=50, lines=25 (如诊断数据)
    // 当前: totalBased=600, lineBased=295, mean=32, t=32/50=0.64, ss=0.52
    //   → W ≈ 295*0.52 + 600*0.48 ≈ 441
    // sqrt: W = sqrt(1.5*800*6*15) ≈ 329
    private static function test_ratio_longUniform():Void {
        var w:Number = TooltipLayout.estimateMainWidthFromMetrics(800, 50, 25, undefined, undefined);
        assert(w < 370, "ratio_longUniform: W=" + Math.round(w) + " < 370");
    }

    // MACSIII: total=1047, maxLine=117, lines=15
    // 当前算法: totalBased=785, lineBased=663.5, mean=69.8, t=69.8/117=0.60, ss=0.47
    //   → W ≈ 663.5*0.47 + 785*0.53 ≈ 728 → clamp MAX_W=650
    // sqrt: W = sqrt(1.5*1047*6*15) ≈ 376
    private static function test_ratio_heavyGun():Void {
        var w:Number = TooltipLayout.estimateMainWidthFromMetrics(1047, 117, 15, undefined, undefined);
        assert(w < 450, "ratio_heavyGun: W=" + Math.round(w) + " < 450 (should not hit MAX_W)");
    }

    // ══════════════════════════════════════════════════════════════
    // 边界回归守卫（当前应 PASS，保持 PASS）
    // ══════════════════════════════════════════════════════════════

    private static function test_estimateMainWidth_empty():Void {
        var w:Number = TooltipLayout.estimateMainWidthFromMetrics(0, 0, 1, undefined, undefined);
        assertEq(TooltipConstants.MIN_W, w, "estimateMainWidth_empty = MIN_W");
    }

    private static function test_estimateMainWidth_maxClamp():Void {
        // sqrt(1.5 * 4000 * 6 * 15) = 735 → 超过 MAX_W=650 → clamp
        // maxLine=200 → maxLineW = 1220 → 不约束
        var w:Number = TooltipLayout.estimateMainWidthFromMetrics(4000, 200, 40, undefined, undefined);
        assertEq(TooltipConstants.MAX_W, w, "estimateMainWidth_maxClamp = MAX_W");
    }

    private static function test_fromMetrics_matches_fromScores():Void {
        var html:String = "短<BR>短<BR>这是很长很长很长的一行描述文本";
        var scores:Object = StringUtils.htmlScoresBoth(html, null);
        var fromScores:Number = TooltipLayout.estimateMainWidthFromScores(scores.total, scores.maxLine, html, undefined, undefined);
        var fromMetrics:Number = TooltipLayout.estimateMainWidthFromMetrics(scores.total, scores.maxLine, scores.lineCount, undefined, undefined);
        assertEq(fromScores, fromMetrics, "fromMetrics matches fromScores");
    }
}
