using System.Drawing;
using CF7Launcher.Guardian;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public class FlashSnapshotLetterboxTests
    {
        // 16:9 = 1.7777...，tolerance 0.005

        [Fact]
        public void Native_16x9_NoLetterbox()
        {
            // 1024x576 完美 16:9
            Rectangle r = FlashSnapshot.ComputeContentRectByAspectRatio(1024, 576);
            Assert.Equal(0, r.X);
            Assert.Equal(0, r.Y);
            Assert.Equal(1024, r.Width);
            Assert.Equal(576, r.Height);
        }

        [Fact]
        public void TooWide_LeftRightLetterbox()
        {
            // 2000x576：宽于 16:9，左右黑边
            Rectangle r = FlashSnapshot.ComputeContentRectByAspectRatio(2000, 576);
            int expectedW = (int)(576f * 1024f / 576f); // = 1024
            Assert.Equal(expectedW, r.Width);
            Assert.Equal(576, r.Height);
            int expectedX = (2000 - expectedW) / 2;
            Assert.Equal(expectedX, r.X);
            Assert.Equal(0, r.Y);
        }

        [Fact]
        public void TooTall_TopBottomLetterbox()
        {
            // 1024x800：窄于 16:9，上下黑边
            Rectangle r = FlashSnapshot.ComputeContentRectByAspectRatio(1024, 800);
            int expectedH = (int)(1024f / (1024f / 576f)); // = 576
            Assert.Equal(1024, r.Width);
            Assert.Equal(expectedH, r.Height);
            Assert.Equal(0, r.X);
            int expectedY = (800 - expectedH) / 2;
            Assert.Equal(expectedY, r.Y);
        }

        [Fact]
        public void Within_Tolerance_TreatedAsNative()
        {
            // 1920x1080 也是 16:9
            Rectangle r = FlashSnapshot.ComputeContentRectByAspectRatio(1920, 1080);
            Assert.Equal(0, r.X);
            Assert.Equal(0, r.Y);
            Assert.Equal(1920, r.Width);
            Assert.Equal(1080, r.Height);
        }

        [Fact]
        public void DegenerateInput_ReturnsAsIs()
        {
            Rectangle r = FlashSnapshot.ComputeContentRectByAspectRatio(0, 0);
            Assert.Equal(0, r.Width);
            Assert.Equal(0, r.Height);
        }
    }
}
