import org.flashNight.gesh.tooltip.TooltipLayout;
import org.flashNight.gesh.tooltip.TooltipConstants;
import org.flashNight.gesh.string.StringUtils;

/**
 * SkillTooltipComposerTest - 历史技能布局评分对照
 *
 * 保留估算器与评分复用对照；生产技能注释已由 NativeTooltip 呈现
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

        test_split_uses_sqrt_estimator();
        test_scores_reuse_no_repeat_scan();

        trace("--- SkillTooltipComposerTest: " + testsPassed + "/" + testsRun + " passed, " + testsFailed + " failed ---");
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
