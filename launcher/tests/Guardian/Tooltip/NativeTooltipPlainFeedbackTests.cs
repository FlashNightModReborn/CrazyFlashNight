using System;
using CF7Launcher.Guardian.Hud.Tooltip;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian.Tooltip
{
    /// <summary>
    /// feedback2-plain 定向回归：plain 短提示（profile=simple 且无 icon）的
    /// shrink-to-fit 宽度。冻结基线 = 迁移前 Web #panel-tooltip 原生样式
    /// （foundation-rest.css）：padding:10px 14px / font-size:12px /
    /// line-height:1.5 / max-width:480px；position:fixed + width:auto →
    /// 内容收缩贴合，max-width 仅为上限；overlay.css 全局
    /// box-sizing:border-box → 480 已含 padding。
    /// 旧 bug：ComputePlain 把 480×scale 上限直接当实际宽，'经济' 铺 ~500px。
    /// </summary>
    public class NativeTooltipPlainFeedbackTests
    {
        // scale=1 时 plain 几何常量（物理 px，与 CSS 本地 px 同值）
        private static readonly int PadX = NativeTooltipLayout.PlainPadXBase;   // 14
        private static readonly int PadY = NativeTooltipLayout.PlainPadYBase;   // 10
        private static readonly int CapW = NativeTooltipLayout.PlainMaxWBase;   // 480
        private const int LineH = 18;                                           // 12×1.5

        /// <summary>确定性测量（与 NativeTooltipTests.FixedMeasure 同约）：
        /// 宽字符 12px，ASCII 6px，空白 3px；bold 不改变宽度。</summary>
        private static int FixedMeasure(string text, bool bold)
        {
            int w = 0;
            foreach (char c in text)
                w += (c == ' ' || c == '\t') ? 3
                    : (NativeTooltipLayout.IsWideChar(c) ? 12 : 6);
            return w;
        }

        /// <summary>run 级样式参与测量的版本：fontSize 相对 12px 线性放大基准宽、
        /// bold ×1.5——验证 styled runs 计入自然宽与行高（CSS line box）。</summary>
        private static int StyledMeasure(string text, NativeTooltipLayout.RunFont font)
        {
            double mul = (font.FontSize.HasValue ? font.FontSize.Value
                : NativeTooltipLayout.FontPxBase)
                / (double)NativeTooltipLayout.FontPxBase;
            if (font.Bold) mul *= 1.5;
            double w = 0;
            foreach (char c in text)
                w += ((c == ' ' || c == '\t') ? 3
                    : (NativeTooltipLayout.IsWideChar(c) ? 12 : 6)) * mul;
            return (int)Math.Ceiling(w);
        }

        private static NativeTooltipLayout.Plan PlainPlan(string docJson,
            int vpW = 1024, int vpH = 576, float scale = 1f, float dpi = 1f,
            Func<string, NativeTooltipLayout.RunFont, int> measure = null)
        {
            NativeTooltipDocument doc = NativeTooltipDocument.FromDocument(
                JObject.Parse(docJson));
            Assert.NotNull(doc);
            NativeTooltipLayout.Plan plan = NativeTooltipLayout.ComputePlan(
                doc,
                measure ?? delegate (string t, NativeTooltipLayout.RunFont f)
                    { return FixedMeasure(t, f.Bold); },
                15f, scale, vpW, vpH, null, dpi);
            Assert.True(plan.Plain, "用例必须走 plain 路径（simple + 无 icon）");
            return plan;
        }

        private static string LineText(NativeTooltipLayout.VisualLine line)
        {
            var sb = new System.Text.StringBuilder();
            foreach (var s in line.Slices) sb.Append(s.Text);
            return sb.ToString();
        }

        private static int LineWidth(NativeTooltipLayout.VisualLine line)
        {
            return FixedMeasure(LineText(line), false);
        }

        [Fact]
        public void Plain_ShortChinese_ShrinksToContentWidth()
        {
            var plan = PlainPlan(@"{'version':1,'sections':[
                {'role':'body','runs':[{'text':'经济'}]}]}");
            // '经济' = 2×12=24 内容宽 + 左右 padding 28 → 52，而非旧 bug 的 480。
            Assert.Equal(24 + PadX * 2, plan.TipSize.Width);
            Assert.Equal(LineH + PadY * 2, plan.TipSize.Height);
            Assert.Equal(plan.TipSize.Width, plan.IntroPanel.Width);
            Assert.Equal(PadX, plan.IntroContentLeftPx);
            Assert.Equal(PadY, plan.IntroContentTopPx);
            Assert.Single(plan.IntroLines);
            Assert.Equal("经济", LineText(plan.IntroLines[0]));
        }

        [Fact]
        public void Plain_EdgeWhitespace_CollapsesOutOfWidth()
        {
            // CSS white-space:normal：行首空白塌陷、行尾可塌陷空白不计入行宽。
            var plan = PlainPlan(@"{'version':1,'sections':[
                {'role':'body','runs':[{'text':'  经济  '}]}]}");
            Assert.Equal(24 + PadX * 2, plan.TipSize.Width);
            Assert.Single(plan.IntroLines);
        }

        [Fact]
        public void Plain_Multiline_WidestLogicalLineDecides()
        {
            var plan = PlainPlan(@"{'version':1,'sections':[
                {'role':'body','runs':[{'text':'经济\n增长数据'}]}]}");
            // '经济'(24) / '增长数据'(48) → 取最宽逻辑行，无软折行。
            Assert.Equal(2, plan.IntroLines.Count);
            Assert.Equal("经济", LineText(plan.IntroLines[0]));
            Assert.Equal("增长数据", LineText(plan.IntroLines[1]));
            Assert.Equal(48 + PadX * 2, plan.TipSize.Width);
            Assert.Equal(2 * LineH + PadY * 2, plan.TipSize.Height);
        }

        [Fact]
        public void Plain_TitleThenSection_TitleOccupiesOwnLine()
        {
            var plan = PlainPlan(@"{'version':1,'title':'属性','sections':[
                {'role':'body','runs':[{'text':'数值 +12'}]}]}");
            // title 独占一行；最宽行 '数值 +12' = 12+12+3+6+6+6 = 45。
            Assert.Equal(2, plan.IntroLines.Count);
            Assert.Equal("属性", LineText(plan.IntroLines[0]));
            Assert.Equal(45 + PadX * 2, plan.TipSize.Width);
            Assert.Equal(2 * LineH + PadY * 2, plan.TipSize.Height);
        }

        [Fact]
        public void Plain_BlankOnly_PaddingWidth()
        {
            var plan = PlainPlan(@"{'version':1,'sections':[
                {'role':'body','runs':[{'text':'\n'}]}]}");
            // 仅一个空行：max-content=0 → 宽=纯 padding，高=padding+一行空行高。
            Assert.Single(plan.IntroLines);
            Assert.True(plan.IntroLines[0].IsBlank);
            Assert.Equal(PadX * 2, plan.TipSize.Width);
            Assert.Equal(LineH + PadY * 2, plan.TipSize.Height);
        }

        [Fact]
        public void Plain_JustUnderCap_NotPinnedToCap()
        {
            // 75×6=450 ≤ 452（480−2×14）：shrink-to-fit 得 478，证明不是贴死上限。
            string t = new string('a', 75);
            var plan = PlainPlan(@"{'version':1,'sections':[
                {'role':'body','runs':[{'text':'" + t + @"'}]}]}");
            Assert.Single(plan.IntroLines);
            Assert.Equal(450 + PadX * 2, plan.TipSize.Width);
        }

        [Fact]
        public void Plain_LongText_WrapsAtCapAndStaysAtCap()
        {
            string t = new string('字', 60);
            var plan = PlainPlan(@"{'version':1,'sections':[
                {'role':'body','runs':[{'text':'" + t + @"'}]}]}");
            // 60×12=720 > 452 → 面板锁 480（CSS：max-content 超上限后 used=cap，
            // 不回收折行余白）；文本在 452 处折行，37 字/行 → 2 行。
            Assert.Equal(CapW, plan.TipSize.Width);
            Assert.Equal(2, plan.IntroLines.Count);
            Assert.Equal(37, LineText(plan.IntroLines[0]).Length);
            Assert.Equal(23, LineText(plan.IntroLines[1]).Length);
            foreach (var l in plan.IntroLines)
                Assert.True(LineWidth(l) <= CapW - PadX * 2);
            Assert.Equal(2 * LineH + PadY * 2, plan.TipSize.Height);
        }

        [Fact]
        public void Plain_StyledRuns_CountWithOwnFont()
        {
            var plan = PlainPlan(@"{'version':1,'sections':[
                {'role':'body','runs':[
                    {'text':'攻击','fontSize':24},
                    {'text':' +12'}]}]}",
                measure: StyledMeasure);
            // '攻击' fontSize 24 → 2×24=48；' +12' 默认 → 21；自然宽 69 → 面板 97。
            Assert.Equal(69 + PadX * 2, plan.TipSize.Width);
            // 行内最大字号 24 → CSS line box = 18×2=36 → 高 = 20+36。
            Assert.Equal(2 * LineH + PadY * 2, plan.TipSize.Height);

            var boldPlan = PlainPlan(@"{'version':1,'sections':[
                {'role':'body','runs':[{'text':'经济','bold':true}]}]}",
                measure: StyledMeasure);
            // bold ×1.5 → 2×12×1.5=36 → 面板 64：styled run 计入宽度。
            Assert.Equal(36 + PadX * 2, boldPlan.TipSize.Width);
        }

        [Fact]
        public void Plain_DpiViewportCap_AppliesAsCapOnly()
        {
            // 小视口 + 高 DPI：cap = min(480, max(60, 400 − 2×8×2)) = 368。
            string t = new string('字', 40); // 40×12=480 > 340(=368−28)
            var longPlan = PlainPlan(@"{'version':1,'sections':[
                {'role':'body','runs':[{'text':'" + t + @"'}]}]}",
                vpW: 400, dpi: 2f);
            Assert.Equal(368, longPlan.TipSize.Width);
            Assert.True(longPlan.IntroLines.Count > 1);

            // 同视口下短文本仍 shrink-to-fit，不吃满 cap。
            var shortPlan = PlainPlan(@"{'version':1,'sections':[
                {'role':'body','runs':[{'text':'经济'}]}]}",
                vpW: 400, dpi: 2f);
            Assert.Equal(24 + PadX * 2, shortPlan.TipSize.Width);
        }

        [Fact]
        public void Plain_LongUnbrokenText_KeepsIndividualMeasurementsBounded()
        {
            int longestMeasured = 0;
            var plan = PlainPlan(@"{'version':1,'sections':[
                {'role':'body','runs':[{'text':'" + new string('a', 10000) + @"'}]}]}",
                measure: (text, font) => {
                    longestMeasured = Math.Max(longestMeasured, text.Length);
                    return FixedMeasure(text, font.Bold);
                });
            Assert.Equal(CapW, plan.TipSize.Width);
            Assert.InRange(longestMeasured, 1, 100);
            Assert.True(plan.IntroLines.Count > 1);
        }
    }
}
