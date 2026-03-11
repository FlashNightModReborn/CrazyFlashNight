import org.flashNight.gesh.string.StringUtils;
import org.flashNight.gesh.tooltip.TooltipLayout;
import org.flashNight.gesh.tooltip.TooltipConstants;
import org.flashNight.gesh.tooltip.TooltipComposer;
import org.flashNight.gesh.tooltip.test.TestDataBootstrap;
import org.flashNight.gesh.tooltip.test.MockTooltipContainer;
import org.flashNight.gesh.tooltip.test.MockItemFactory;
import org.flashNight.arki.item.ItemUtil;

/**
 * TooltipPerfBenchmark - 性能基准测试
 *
 * 对 tooltip 渲染热路径的关键函数进行计时，
 * 用于量化优化效果和回归检测。
 *
 * 输出格式与 RayVfxManagerTest bench 段一致：
 *   funcName xN = Xms (Y ms/call)
 */
class org.flashNight.gesh.tooltip.test.TooltipPerfBenchmark {

    private static var testsRun:Number = 0;
    private static var testsPassed:Number = 0;
    private static var testsFailed:Number = 0;

    private static function assert(cond:Boolean, msg:String):Void {
        testsRun++;
        if (cond) { testsPassed++; trace("[PASS] " + msg); }
        else { testsFailed++; trace("[FAIL] " + msg); }
    }

    // 构建测试用 HTML 字符串（模拟真实装备 tooltip）
    private static function buildShortHtml():String {
        return "<B>测试军刀</B><BR>武器    刀<BR>$15200<BR>" +
               "<FONT COLOR='#FFCC00'>力度：</FONT>10<BR>" +
               "<FONT COLOR='#FFCC00'>防御：</FONT>5<BR>" +
               "测试用近战武器<BR>";
    }

    private static function buildLongHtml():String {
        var buf:Array = [];
        buf.push("<B>测试超级长描述装备</B><BR>武器    刀<BR>$99999<BR>");
        for (var i:Number = 0; i < 30; i++) {
            buf.push("<FONT COLOR='#FFCC00'>属性" + i + "：</FONT>" + (i * 10 + 50) + "<BR>");
        }
        buf.push("这是一段非常非常长的描述文本，包含了大量的中文字符和一些English words混合在一起。");
        buf.push("用于测试在极端长文本下的HTML解析性能。<BR>");
        buf.push("<FONT COLOR='#DD4455'>暴击：10%暴击几率</FONT><BR>");
        buf.push("<FONT COLOR='#0099FF'>伤害属性：热</FONT><BR>");
        for (var j:Number = 0; j < 10; j++) {
            buf.push("额外描述行" + j + "：这里是更多的内容来模拟复杂物品的tooltip。<BR>");
        }
        return buf.join("");
    }

    public static function runAllTests():Void {
        testsRun = testsPassed = testsFailed = 0;
        trace("--- TooltipPerfBenchmark ---");

        TestDataBootstrap.init();

        bench_htmlScoresBoth_short();
        bench_htmlScoresBoth_long();
        bench_htmlScoresBoth_vs_separate();
        bench_shouldSplitSmartWithScores();
        bench_estimateMainWidth();
        bench_renderItemTooltipSmart();

        trace("--- TooltipPerfBenchmark: " + testsPassed + "/" + testsRun + " passed, " + testsFailed + " failed ---");
    }

    // === htmlScoresBoth 短文本 ===
    private static function bench_htmlScoresBoth_short():Void {
        var html:String = buildShortHtml();
        var N:Number = 500;

        var t0:Number = getTimer();
        for (var i:Number = 0; i < N; i++) {
            StringUtils.htmlScoresBoth(html, null);
        }
        var elapsed:Number = getTimer() - t0;
        trace("  htmlScoresBoth(short) x" + N + " = " + elapsed + "ms (" + (elapsed / N) + " ms/call)");

        // 正确性验证
        var r:Object = StringUtils.htmlScoresBoth(html, null);
        assert(r.total > 0, "bench short: total > 0");
        assert(r.maxLine > 0, "bench short: maxLine > 0");
        assert(r.total >= r.maxLine, "bench short: total >= maxLine");
    }

    // === htmlScoresBoth 长文本 ===
    private static function bench_htmlScoresBoth_long():Void {
        var html:String = buildLongHtml();
        var N:Number = 200;

        var t0:Number = getTimer();
        for (var i:Number = 0; i < N; i++) {
            StringUtils.htmlScoresBoth(html, null);
        }
        var elapsed:Number = getTimer() - t0;
        trace("  htmlScoresBoth(long) x" + N + " = " + elapsed + "ms (" + (elapsed / N) + " ms/call)");

        var r:Object = StringUtils.htmlScoresBoth(html, null);
        assert(r.total > 100, "bench long: total > 100");
        assert(r.maxLine > 0, "bench long: maxLine > 0");
    }

    // === 合并 vs 分开调用对比 ===
    private static function bench_htmlScoresBoth_vs_separate():Void {
        var html:String = buildLongHtml();
        var N:Number = 200;

        // 合并调用
        var t0:Number = getTimer();
        for (var i:Number = 0; i < N; i++) {
            StringUtils.htmlScoresBoth(html, null);
        }
        var combinedMs:Number = getTimer() - t0;

        // 分开调用（旧路径：2 次独立扫描）
        var t1:Number = getTimer();
        for (var j:Number = 0; j < N; j++) {
            StringUtils.htmlLengthScore(html, null);
            StringUtils.htmlMaxLineScore(html, null);
        }
        var separateMs:Number = getTimer() - t1;

        trace("  combined x" + N + " = " + combinedMs + "ms vs separate x" + N + " = " + separateMs + "ms");

        // 合并路径现在是委托调用，不应明显更慢
        // （旧的 separate 其实每次调用 htmlScoresBoth 再取一个字段，overhead 约 2x）
        // 验证一致性
        var combined:Object = StringUtils.htmlScoresBoth(html, null);
        var sepTotal:Number = StringUtils.htmlLengthScore(html, null);
        var sepMaxLine:Number = StringUtils.htmlMaxLineScore(html, null);
        assert(combined.total == sepTotal, "bench consistency: total matches");
        assert(combined.maxLine == sepMaxLine, "bench consistency: maxLine matches");
    }

    // === shouldSplitSmartWithScores 基准 ===
    private static function bench_shouldSplitSmartWithScores():Void {
        var desc:String = buildLongHtml();
        var intro:String = buildShortHtml();
        var N:Number = 200;

        // 新路径：WithScores
        var t0:Number = getTimer();
        for (var i:Number = 0; i < N; i++) {
            TooltipLayout.shouldSplitSmartWithScores(desc, intro, null);
        }
        var newMs:Number = getTimer() - t0;

        // 旧路径：shouldSplitSmart（不返回评分，后续需重新扫描）
        var t1:Number = getTimer();
        for (var j:Number = 0; j < N; j++) {
            TooltipLayout.shouldSplitSmart(desc, intro, null);
        }
        var oldMs:Number = getTimer() - t1;

        trace("  shouldSplitSmartWithScores x" + N + " = " + newMs + "ms vs shouldSplitSmart x" + N + " = " + oldMs + "ms");

        // 验证结果一致
        var newResult:Object = TooltipLayout.shouldSplitSmartWithScores(desc, intro, null);
        var oldResult:Boolean = TooltipLayout.shouldSplitSmart(desc, intro, null);
        assert(newResult.needSplit == oldResult, "bench split: results consistent");
    }

    // === estimateMainWidth 基准 ===
    private static function bench_estimateMainWidth():Void {
        var html:String = buildLongHtml();
        var N:Number = 200;

        // 旧路径：estimateMainWidth（内部重新扫描）
        var t0:Number = getTimer();
        for (var i:Number = 0; i < N; i++) {
            TooltipLayout.estimateMainWidth(html, undefined, undefined);
        }
        var oldMs:Number = getTimer() - t0;

        // 新路径：预计算评分 + estimateMainWidthFromScores
        var scores:Object = StringUtils.htmlScoresBoth(html, null);
        var st:Number = scores.total;
        var sm:Number = scores.maxLine;
        var t1:Number = getTimer();
        for (var j:Number = 0; j < N; j++) {
            TooltipLayout.estimateMainWidthFromScores(st, sm, html, undefined, undefined);
        }
        var newMs:Number = getTimer() - t1;

        trace("  estimateMainWidth x" + N + " = " + oldMs + "ms vs fromScores x" + N + " = " + newMs + "ms");

        // 结果一致
        var oldW:Number = TooltipLayout.estimateMainWidth(html, undefined, undefined);
        var newW:Number = TooltipLayout.estimateMainWidthFromScores(st, sm, html, undefined, undefined);
        assert(oldW == newW, "bench mainWidth: results match");
    }

    // === 端到端：renderItemTooltipSmart 基准 ===
    private static function bench_renderItemTooltipSmart():Void {
        MockTooltipContainer.install();

        var item:Object = ItemUtil.getItemData("测试军刀");
        var bi = MockItemFactory.mockBaseItem();
        var desc:String = TooltipComposer.generateItemDescriptionText(item, bi);
        var intro:String = TooltipComposer.generateIntroPanelContent(bi, item, bi.value);

        var N:Number = 100;
        var t0:Number = getTimer();
        for (var i:Number = 0; i < N; i++) {
            TooltipComposer.renderItemTooltipSmart("测试军刀", {level: 1}, desc, intro, null, null);
        }
        var elapsed:Number = getTimer() - t0;
        trace("  renderItemTooltipSmart x" + N + " = " + elapsed + "ms (" + (elapsed / N) + " ms/call)");

        assert(elapsed < N * 50, "bench renderSmart: < 50ms/call");

        MockTooltipContainer.teardown();
    }
}
