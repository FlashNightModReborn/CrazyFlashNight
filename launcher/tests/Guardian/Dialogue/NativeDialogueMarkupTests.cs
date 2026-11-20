using System.Drawing;
using System.Linq;
using CF7Launcher.Guardian.Hud.Dialogue;
using Xunit;

namespace Launcher.Tests.Guardian.Dialogue
{
    public sealed class NativeDialogueMarkupTests
    {
        [Fact]
        public void SegmentsAfterFlattening_AndHonorsFirstStyleAcrossMarkup()
        {
            string text = "A<font color='#f00'>e</font>́𠊎👩‍🚀<br>\uD840B";
            var plan = NativeDialogueTextLayout.Build(text, 2,
                run => System.Globalization.StringInfo.ParseCombiningCharacters(run).Length);
            Assert.Equal(7, plan.TotalElements);
            Assert.Equal(new[] { "Aé", "𠊎👩‍🚀", "�B" },
                plan.Lines.Select(line => string.Concat(line.Runs.Select(run => run.Text))));
            var red = plan.Lines[0].Runs[1];
            Assert.Equal(Color.Red.ToArgb(), red.Color.ToArgb());
            Assert.Equal(new[] { 0, 2 }, red.Offsets);
            Assert.Equal(new[] { 0, 2, 7 }, Assert.Single(plan.Lines[1].Runs).Offsets);
        }

        [Fact]
        public void DeferredPlanKeepsSkippedLinesAndHardBreakTimingAlignedWithFullLayout()
        {
            string text = "甲<br><br>𠊎é👩‍🚀<br>末行" + new string('x', 32740);
            float Measure(string run) => System.Globalization.StringInfo.ParseCombiningCharacters(run).Length;
            var eager = NativeDialogueTextLayout.Build(text, 37, Measure);
            var lazy = NativeDialogueTextLayout.Build(text, 37, Measure, deferLines: true);
            Assert.Empty(lazy.Lines);
            Assert.Equal(0, NativeDialogueTextLayout.LastNeededLine(lazy, 1));
            Assert.Single(lazy.Lines);
            Assert.Equal(1, NativeDialogueTextLayout.LastNeededLine(lazy, 3));
            foreach (int visible in new[] { 8, lazy.TotalElements, 5, 0 })
                Assert.Equal(NativeDialogueTextLayout.LastNeededLine(eager, visible),
                    NativeDialogueTextLayout.LastNeededLine(lazy, visible));
            Assert.Equal(eager.Lines.Count, lazy.Lines.Count);
            Assert.Null(lazy.Lines[8].Runs); // 跳过区间保留断点，暂不分配绘制片段。
            foreach (int line in new[] { 0, 1, 2, 8, eager.Lines.Count - 1 })
            {
                Assert.Equal(eager.Lines[line].FirstElement, lazy.Lines[line].FirstElement);
                Assert.Equal(eager.Lines[line].Runs.Select(r => r.Text), lazy.GetDrawableLine(line).Runs.Select(r => r.Text));
            }
        }

        [Fact]
        public void RendererRefusalPreservesUnsupportedElementAndNeighbors()
        {
            string unsupported = "a" + new string('\u0301', 64);
            var plan = NativeDialogueTextLayout.Build("甲" + unsupported + "乙", 1000,
                run => run.Contains(unsupported) ? float.PositiveInfinity : 10 * run.Length);
            Assert.Equal(3, plan.TotalElements);
            var runs = plan.Lines.SelectMany(l => l.Runs).ToArray();
            Assert.Equal(new[] { "甲", unsupported, "乙" }, runs.Select(r => r.Text));
            Assert.Equal(new[] { "甲", "□", "乙" }, runs.Select(r => r.PaintText));
            Assert.True(runs[1].GdiRefused);
            Assert.Equal(new[] { 0, unsupported.Length }, runs[1].Offsets);
        }

        [Fact]
        public void WrapAndFinalPositionsUseMeasuredWholeStyleRuns()
        {
            // “fi” 在测试字体中共享宽度；拆成单字再相加会错误折行。
            var plan = NativeDialogueTextLayout.Build("fi<font color='#f00'>x</font>y", 2,
                run => run == "fi" ? 1 : run.Length);
            Assert.Equal(2, plan.Lines.Count);
            Assert.Equal("fi", plan.Lines[0].Runs[0].Text);
            Assert.Equal("x", plan.Lines[0].Runs[1].Text);
            Assert.Equal(1f, plan.Lines[0].Runs[1].X);
            Assert.Equal(2f, plan.Lines[0].WidthF);
        }

        [Fact]
        public void PlayerTitleUsesGoldTextInsteadOfLiteralFontTags()
        {
            var plan = NativeDialogueTextLayout.Build(
                "<FONT COLOR='#FFCC00'>永恒强者</FONT>", 1000, run => 10 * run.Length);
            var run = Assert.Single(Assert.Single(plan.Lines).Runs);
            Assert.Equal("永恒强者", run.Text);
            Assert.Equal(Color.FromArgb(255, 204, 0).ToArgb(), run.Color.ToArgb());
            Assert.Equal(4, plan.TotalElements);
        }

        [Fact]
        public void MultipleFontAttributesAndNestedColorsShareTooltipParsing()
        {
            var plan = NativeDialogueTextLayout.Build(
                "<FONT FACE='Microsoft YaHei' SIZE='18' COLOR='#fc0'>甲<font color='#f00'>乙</font>丙</FONT>丁",
                1000, run => 10 * run.Length, Color.Black);
            var runs = Assert.Single(plan.Lines).Runs;
            Assert.Equal(new[] { "甲", "乙", "丙", "丁" }, runs.Select(r => r.Text));
            Assert.Equal(new[] { 0xffffcc00u, 0xffff0000u, 0xffffcc00u, 0xff000000u },
                runs.Select(r => unchecked((uint)r.Color.ToArgb())));
        }

        [Fact]
        public void ExplicitWhiteRemainsWhiteOnDefaultBlackBody()
        {
            var plan = NativeDialogueTextLayout.Build("甲<font color='#FFFFFF'>乙</font>丙",
                1000, run => 10 * run.Length, Color.Black);
            Assert.Equal(new[] { Color.Black.ToArgb(), Color.White.ToArgb(), Color.Black.ToArgb() },
                Assert.Single(plan.Lines).Runs.Select(r => r.Color.ToArgb()));
        }

        [Fact]
        public void EntitiesAreDecodedOnceAndBreaksPreserveColor()
        {
            var plan = NativeDialogueTextLayout.Build("<font color='#fc0'>&lt;FONT&gt;<BR>甲&amp;乙</font>",
                1000, run => 10 * run.Length, Color.Black);
            Assert.Equal(2, plan.Lines.Count);
            Assert.Equal("<FONT>", Assert.Single(plan.Lines[0].Runs).Text);
            Assert.Equal("甲&乙", Assert.Single(plan.Lines[1].Runs).Text);
            Assert.All(plan.Lines.SelectMany(l => l.Runs), r =>
                Assert.Equal(Color.FromArgb(255, 204, 0).ToArgb(), r.Color.ToArgb()));
        }
    }
}
