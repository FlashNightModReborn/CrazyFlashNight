using System.Drawing;
using System.Linq;
using CF7Launcher.Guardian.Hud.Dialogue;
using Xunit;

namespace Launcher.Tests.Guardian.Dialogue
{
    public sealed class NativeDialogueMarkupTests
    {
        [Fact]
        public void PlayerTitleUsesGoldTextInsteadOfLiteralFontTags()
        {
            var plan = NativeDialogueTextLayout.Build(
                "<FONT COLOR='#FFCC00'>永恒强者</FONT>", 1000, _ => 10);
            var run = Assert.Single(Assert.Single(plan.Lines).Runs);
            Assert.Equal("永恒强者", run.Text);
            Assert.Equal(Color.FromArgb(255, 204, 0).ToArgb(), run.Color.ToArgb());
            Assert.Equal(4, plan.TotalGlyphs);
        }

        [Fact]
        public void MultipleFontAttributesAndNestedColorsShareTooltipParsing()
        {
            var plan = NativeDialogueTextLayout.Build(
                "<FONT FACE='Microsoft YaHei' SIZE='18' COLOR='#fc0'>甲<font color='#f00'>乙</font>丙</FONT>丁",
                1000, _ => 10, Color.Black);
            var runs = Assert.Single(plan.Lines).Runs;
            Assert.Equal(new[] { "甲", "乙", "丙", "丁" }, runs.Select(r => r.Text));
            Assert.Equal(new[] { 0xffffcc00u, 0xffff0000u, 0xffffcc00u, 0xff000000u },
                runs.Select(r => unchecked((uint)r.Color.ToArgb())));
        }

        [Fact]
        public void ExplicitWhiteRemainsWhiteOnDefaultBlackBody()
        {
            var plan = NativeDialogueTextLayout.Build("甲<font color='#FFFFFF'>乙</font>丙",
                1000, _ => 10, Color.Black);
            Assert.Equal(new[] { Color.Black.ToArgb(), Color.White.ToArgb(), Color.Black.ToArgb() },
                Assert.Single(plan.Lines).Runs.Select(r => r.Color.ToArgb()));
        }

        [Fact]
        public void EntitiesAreDecodedOnceAndBreaksPreserveColor()
        {
            var plan = NativeDialogueTextLayout.Build("<font color='#fc0'>&lt;FONT&gt;<BR>甲&amp;乙</font>",
                1000, _ => 10, Color.Black);
            Assert.Equal(2, plan.Lines.Count);
            Assert.Equal("<FONT>", Assert.Single(plan.Lines[0].Runs).Text);
            Assert.Equal("甲&乙", Assert.Single(plan.Lines[1].Runs).Text);
            Assert.All(plan.Lines.SelectMany(l => l.Runs), r =>
                Assert.Equal(Color.FromArgb(255, 204, 0).ToArgb(), r.Color.ToArgb()));
        }
    }
}
