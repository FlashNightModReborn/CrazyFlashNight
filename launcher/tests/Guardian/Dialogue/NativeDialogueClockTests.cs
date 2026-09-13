using System.Drawing;
using System.Windows.Forms;
using CF7Launcher.Guardian.Hud.Dialogue;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class NativeDialogueClockTests
    {
        [Fact]
        public void PaintCatchesUpWhenTimerCallbacksAreStarved()
        {
            long now = 1000;
            using var anchor = new Control();
            using var widget = new NativeDialogueWidget(anchor, () => new Rectangle(0, 0, 1024, 576));
            widget.TypingClock = () => now;
            widget.ShowFrame(new NativeDialogueFrame { RequestId = "nd:1", SceneId = "scene",
                Revision = 1, LineCount = 1, Text = "低帧率下正文仍按实际时间出现。" });
            now += 5000;
            using var bitmap = new Bitmap(1024, 576);
            using var graphics = Graphics.FromImage(bitmap);
            widget.Paint(graphics, 1, Point.Empty);
            Assert.True(widget.TypingCompleteForTest);
            Assert.False(widget.WantsAnimationTick);
        }

        [Fact]
        public void HiddenTimeDoesNotAdvanceTypingAndTickDoesNotDoubleCountPaint()
        {
            long now = 1000;
            using var anchor = new Control();
            using var widget = new NativeDialogueWidget(anchor, () => new Rectangle(0, 0, 1024, 576));
            widget.TypingClock = () => now;
            widget.TypingIntervalMs = 100;
            widget.ShowFrame(new NativeDialogueFrame { RequestId = "nd:1", SceneId = "scene",
                Revision = 1, LineCount = 1, Text = "一二三四五六七八九十" });
            now += 100;
            using var bitmap = new Bitmap(1024, 576);
            using var graphics = Graphics.FromImage(bitmap);
            widget.Paint(graphics, 1, Point.Empty);
            Assert.Equal(1, widget.VisibleCharsForTest);
            widget.Tick(100);
            Assert.Equal(1, widget.VisibleCharsForTest);
            widget.SetHostSuppressed(true);
            now += 10000;
            widget.SetHostSuppressed(false);
            widget.Paint(graphics, 1, Point.Empty);
            Assert.Equal(1, widget.VisibleCharsForTest);
            now += 100;
            widget.Paint(graphics, 1, Point.Empty);
            Assert.Equal(2, widget.VisibleCharsForTest);
        }
    }
}
