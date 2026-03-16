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
    private static var _scoreScratch:Object = {total: 0, maxLine: 0, lineCount: 0};
    private static var _splitScratch:Object = {
        needSplit: false,
        descTotal: 0,
        descMaxLine: 0,
        descLineCount: 0,
        introTotal: 0
    };

    // 缓存 HTML 字符串，避免每个 bench 函数重复构建
    private static var _shortHtml:String = null;
    private static var _longHtml:String = null;

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

    private static function getShortHtml():String {
        if (_shortHtml == null) _shortHtml = buildShortHtml();
        return _shortHtml;
    }

    private static function getLongHtml():String {
        if (_longHtml == null) _longHtml = buildLongHtml();
        return _longHtml;
    }

    /** 预热：触发所有被测函数的首次调用，消除类加载/初始化开销 */
    private static function warmup():Void {
        var s:String = getShortHtml();
        var l:String = getLongHtml();
        StringUtils.htmlScoresBoth(s, null);
        StringUtils.htmlScoresBoth(l, null);
        StringUtils.htmlScoresBoth(l, null, _scoreScratch);
        TooltipLayout.shouldSplitSmartWithScores(l, s, null);
        TooltipLayout.shouldSplitSmartWithScores(l, s, null, _splitScratch);
        TooltipLayout.estimateMainWidth(l, undefined, undefined);
        var sc:Object = StringUtils.htmlScoresBoth(l, null);
        TooltipLayout.estimateMainWidthFromScores(sc.total, sc.maxLine, l, undefined, undefined);
        TooltipLayout.estimateMainWidthFromMetrics(sc.total, sc.maxLine, sc.lineCount, undefined, undefined);
    }

    public static function runAllTests():Void {
        testsRun = testsPassed = testsFailed = 0;
        trace("--- TooltipPerfBenchmark ---");

        TestDataBootstrap.init();
        warmup();

        bench_htmlScoresBoth_short();
        bench_htmlScoresBoth_long();
        bench_htmlScoresBoth_new_vs_scratch();
        bench_shouldSplitSmartWithScores();
        bench_estimateMainWidth();
        bench_balanceWidth();
        bench_renderItemTooltipSmart();

        trace("--- TooltipPerfBenchmark: " + testsPassed + "/" + testsRun + " passed, " + testsFailed + " failed ---");
    }

    // === htmlScoresBoth 短文本 ===
    private static function bench_htmlScoresBoth_short():Void {
        var html:String = getShortHtml();
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
        var html:String = getLongHtml();
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

    // === 默认返回对象 vs 热路径 scratch 复用 ===
    private static function bench_htmlScoresBoth_new_vs_scratch():Void {
        var html:String = getLongHtml();
        var N:Number = 200;

        // 默认路径：返回独立结果对象
        var t0:Number = getTimer();
        for (var i:Number = 0; i < N; i++) {
            StringUtils.htmlScoresBoth(html, null);
        }
        var newObjectMs:Number = getTimer() - t0;

        // 热路径：复用输出对象，避免额外分配
        var t1:Number = getTimer();
        for (var j:Number = 0; j < N; j++) {
            StringUtils.htmlScoresBoth(html, null, _scoreScratch);
        }
        var scratchMs:Number = getTimer() - t1;

        trace("  htmlScoresBoth new x" + N + " = " + newObjectMs + "ms vs scratch x" + N + " = " + scratchMs + "ms");

        var fresh:Object = StringUtils.htmlScoresBoth(html, null);
        var scratch:Object = StringUtils.htmlScoresBoth(html, null, _scoreScratch);
        assert(fresh.total == scratch.total, "bench htmlScoresBoth: total matches scratch");
        assert(fresh.maxLine == scratch.maxLine, "bench htmlScoresBoth: maxLine matches scratch");
        assert(fresh.lineCount == scratch.lineCount, "bench htmlScoresBoth: lineCount matches scratch");
    }

    // === shouldSplitSmartWithScores 基准 ===
    private static function bench_shouldSplitSmartWithScores():Void {
        var desc:String = getLongHtml();
        var intro:String = getShortHtml();
        var N:Number = 200;

        // 默认快照路径
        var t0:Number = getTimer();
        for (var i:Number = 0; i < N; i++) {
            TooltipLayout.shouldSplitSmartWithScores(desc, intro, null);
        }
        var newMs:Number = getTimer() - t0;

        // 热路径：复用输出对象
        var t1:Number = getTimer();
        for (var j:Number = 0; j < N; j++) {
            TooltipLayout.shouldSplitSmartWithScores(desc, intro, null, _splitScratch);
        }
        var scratchMs:Number = getTimer() - t1;

        trace("  shouldSplitSmartWithScores new x" + N + " = " + newMs + "ms vs scratch x" + N + " = " + scratchMs + "ms");

        var newResult:Object = TooltipLayout.shouldSplitSmartWithScores(desc, intro, null);
        var scratchResult:Object = TooltipLayout.shouldSplitSmartWithScores(desc, intro, null, _splitScratch);
        assert(newResult.needSplit == scratchResult.needSplit, "bench split: needSplit consistent");
        assert(newResult.descLineCount == scratchResult.descLineCount, "bench split: lineCount consistent");
    }

    // === estimateMainWidth 基准 ===
    private static function bench_estimateMainWidth():Void {
        var html:String = getLongHtml();
        var N:Number = 200;

        // 旧路径：estimateMainWidth（内部重新扫描）
        var t0:Number = getTimer();
        for (var i:Number = 0; i < N; i++) {
            TooltipLayout.estimateMainWidth(html, undefined, undefined);
        }
        var oldMs:Number = getTimer() - t0;

        // 兼容路径：预计算评分 + HTML 行数扫描
        var scores:Object = StringUtils.htmlScoresBoth(html, null);
        var st:Number = scores.total;
        var sm:Number = scores.maxLine;
        var t1:Number = getTimer();
        for (var j:Number = 0; j < N; j++) {
            TooltipLayout.estimateMainWidthFromScores(st, sm, html, undefined, undefined);
        }
        var compatMs:Number = getTimer() - t1;

        // 最优路径：total/maxLine/lineCount 全部预计算
        var lineCount:Number = scores.lineCount;
        var t2:Number = getTimer();
        for (var k:Number = 0; k < N; k++) {
            TooltipLayout.estimateMainWidthFromMetrics(st, sm, lineCount, undefined, undefined);
        }
        var metricsMs:Number = getTimer() - t2;

        trace("  estimateMainWidth x" + N + " = " + oldMs + "ms vs fromScores x" + N + " = " + compatMs + "ms vs fromMetrics x" + N + " = " + metricsMs + "ms");

        var oldW:Number = TooltipLayout.estimateMainWidth(html, undefined, undefined);
        var compatW:Number = TooltipLayout.estimateMainWidthFromScores(st, sm, html, undefined, undefined);
        var metricsW:Number = TooltipLayout.estimateMainWidthFromMetrics(st, sm, lineCount, undefined, undefined);
        assert(oldW == compatW, "bench mainWidth: compat matches");
        assert(oldW == metricsW, "bench mainWidth: metrics matches");
        assert(metricsMs < 50, "bench fromMetrics: < 50ms for " + N + " iterations");
    }

    // === balanceWidth 基准 ===
    private static function bench_balanceWidth():Void {
        MockTooltipContainer.install();

        var html:String = getLongHtml();
        var sc:Object = StringUtils.htmlScoresBoth(html, null);
        var initW:Number = TooltipLayout.estimateMainWidthFromMetrics(
            sc.total, sc.maxLine, sc.lineCount, undefined, undefined);

        // 使用与运行时一致的 effectiveMax
        var screenMax:Number = Stage.width - TooltipConstants.BASE_NUM - TooltipConstants.DUAL_PANEL_MARGIN;
        var effectiveMax:Number = (screenMax > TooltipConstants.MIN_W)
            ? Math.min(TooltipConstants.MAX_W, screenMax)
            : TooltipConstants.MAX_W;

        // 预热
        TooltipLayout.balanceWidth(initW, html, effectiveMax);

        var N:Number = 50;
        var t0:Number = getTimer();
        for (var i:Number = 0; i < N; i++) {
            TooltipLayout.balanceWidth(initW, html, effectiveMax);
        }
        var elapsed:Number = getTimer() - t0;
        trace("  balanceWidth x" + N + " = " + elapsed + "ms (" + (Math.round(elapsed / N * 100) / 100) + " ms/call)");

        // 性能守卫：每次 balanceWidth 应 < 50ms
        //
        // getLongHtml() 含 43 个 <BR> 硬换行 → 必走不可解熔断路径（2 次 relayout）。
        // 主要耗时来自 htmlText 赋值触发 Flash 样式树重建（含大量 <font> 标签），
        // 而非二分搜索本身。实际游戏物品通常 15-26 行，走 modeB O(1) 快路径。
        // 基准机（9代i7）实测 ~22ms/call，开发机（13代i9）按 CPU 差距预估 ~12ms/call。
        assert(elapsed / N < 50, "bench balanceWidth: < 50ms/call (" + (Math.round(elapsed / N * 100) / 100) + "ms)");

        MockTooltipContainer.teardown();
    }

    // === 端到端：renderItemTooltipSmart 基准 ===
    private static function bench_renderItemTooltipSmart():Void {
        MockTooltipContainer.install();

        var item:Object = ItemUtil.getItemData("测试军刀");
        var bi = MockItemFactory.mockBaseItem();
        var desc:String = TooltipComposer.generateItemDescriptionText(item, bi);
        var intro:String = TooltipComposer.generateIntroPanelContent(bi, item, bi.value);

        // 预热渲染路径
        TooltipComposer.renderItemTooltipSmart("测试军刀", {level: 1}, desc, intro, null, null);

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
