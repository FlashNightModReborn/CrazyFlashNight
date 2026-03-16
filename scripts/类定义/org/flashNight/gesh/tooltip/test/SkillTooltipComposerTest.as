import org.flashNight.gesh.tooltip.SkillTooltipComposer;
import org.flashNight.gesh.tooltip.TooltipLayout;
import org.flashNight.gesh.tooltip.TooltipConstants;
import org.flashNight.gesh.tooltip.TooltipBridge;
import org.flashNight.gesh.tooltip.test.MockTooltipContainer;
import org.flashNight.gesh.string.StringUtils;

/**
 * SkillTooltipComposerTest - 技能注释组合器测试
 *
 * 重点验证 P1 修复：split 分支补齐 balanceWidth 高度约束
 */
class org.flashNight.gesh.tooltip.test.SkillTooltipComposerTest {

    public static var testsRun:Number = 0;
    public static var testsPassed:Number = 0;
    public static var testsFailed:Number = 0;

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
        trace("--- SkillTooltipComposerTest ---");

        test_split_balanceWidth_constrains_height();
        test_split_width_respects_screen_budget();
        test_merge_path_unchanged();
        test_split_uses_sqrt_estimator();
        test_scores_reuse_no_repeat_scan();

        trace("--- SkillTooltipComposerTest: " + testsPassed + "/" + testsRun + " passed, " + testsFailed + " failed ---");
    }

    /**
     * 核心 P1 测试：长技能描述渲染后行数必须 ≤ MAX_RENDERED_LINES
     * 利用 MockTooltipContainer 的真实 TextField 进行行数测量
     */
    private static function test_split_balanceWidth_constrains_height():Void {
        MockTooltipContainer.install();

        var desc:String = "";
        for (var i:Number = 0; i < 15; i++) {
            desc += "这是技能的第" + i + "行详细描述文本内容用来测试高度约束效果<BR>";
        }
        var intro:String = "<B>火球术</B><BR>技能    主动<BR>$0<BR>冷却30秒";

        SkillTooltipComposer.renderSkillTooltipSmart("火球术", intro, desc);

        var mainBg:MovieClip = TooltipBridge.getMainBackground();
        assert(mainBg._visible == true, "split_balanceWidth: mainBg visible (split triggered)");

        var tf:Object = TooltipBridge.getMainTextBox();
        if (tf != null) {
            var lines:Number = TooltipBridge.measureRenderedLines(tf._width, false);
            assert(lines > 0 && lines <= TooltipConstants.MAX_RENDERED_LINES,
                "split_balanceWidth: lines=" + lines + " <= " + TooltipConstants.MAX_RENDERED_LINES);
        }

        TooltipLayout.hideTooltip();
        MockTooltipContainer.teardown();
    }

    private static function test_split_width_respects_screen_budget():Void {
        MockTooltipContainer.install();

        var desc:String = "";
        for (var i:Number = 0; i < 20; i++) {
            desc += "超长技能描述文本第" + i + "行，包含大量详细的技能机制说明和数值参数<BR>";
        }
        var intro:String = "<B>终极技能</B><BR>技能    主动<BR>$0<BR>";

        SkillTooltipComposer.renderSkillTooltipSmart("终极技能", intro, desc);

        var tf:Object = TooltipBridge.getMainTextBox();
        if (tf != null) {
            var screenMax:Number = Stage.width - TooltipConstants.BASE_NUM - TooltipConstants.DUAL_PANEL_MARGIN;
            var effectiveMax:Number = (screenMax > TooltipConstants.MIN_W)
                ? Math.min(TooltipConstants.MAX_W, screenMax)
                : TooltipConstants.MAX_W;
            assert(tf._width <= effectiveMax + 1,
                "split_screen_budget: W=" + Math.round(tf._width) + " <= effectiveMax=" + Math.round(effectiveMax));
        }

        TooltipLayout.hideTooltip();
        MockTooltipContainer.teardown();
    }

    private static function test_merge_path_unchanged():Void {
        MockTooltipContainer.install();

        var intro:String = "<B>小火球</B><BR>技能    主动<BR>$0<BR>";
        var desc:String = "发射一个小火球";

        SkillTooltipComposer.renderSkillTooltipSmart("小火球", intro, desc);

        var mainBg:MovieClip = TooltipBridge.getMainBackground();
        assert(mainBg._visible == false, "merge_path: mainBg hidden");

        TooltipLayout.hideTooltip();
        MockTooltipContainer.teardown();
    }

    private static function test_split_uses_sqrt_estimator():Void {
        var desc:String = "";
        for (var i:Number = 0; i < 10; i++) {
            desc += "技能描述第" + i + "行内容<BR>";
        }
        var scores:Object = StringUtils.htmlScoresBoth(desc, null);
        var sqrtW:Number = TooltipLayout.estimateMainWidthFromMetrics(
            scores.total, scores.maxLine, scores.lineCount, undefined, undefined);

        assert(sqrtW >= TooltipConstants.MIN_W, "sqrt_estimator: sqrtW=" + Math.round(sqrtW) + " >= MIN_W");
        assert(sqrtW <= TooltipConstants.MAX_W, "sqrt_estimator: sqrtW=" + Math.round(sqrtW) + " <= MAX_W");
    }

    private static function test_scores_reuse_no_repeat_scan():Void {
        var desc:String = "";
        for (var i:Number = 0; i < 12; i++) {
            desc += "技能描述第" + i + "行<BR>";
        }
        var intro:String = "<B>测试技能</B><BR>技能    主动<BR>";

        var scores:Object = StringUtils.htmlScoresBoth(desc, null);
        var manualW:Number = TooltipLayout.estimateMainWidthFromMetrics(
            scores.total, scores.maxLine, scores.lineCount, undefined, undefined);

        var splitInfo:Object = TooltipLayout.shouldSplitSmartWithScores(desc, intro, null, null);
        var reusedW:Number = TooltipLayout.estimateMainWidthFromMetrics(
            splitInfo.descTotal, splitInfo.descMaxLine, splitInfo.descLineCount, undefined, undefined);

        assertEq(manualW, reusedW, "scores_reuse: manualW=" + Math.round(manualW) + " == reusedW=" + Math.round(reusedW));
    }
}
