using System.Drawing;
using System.Drawing.Imaging;
using CF7Launcher.Guardian;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public class FlashSnapshotBlackFrameTests
    {
        [Fact]
        public void NullBitmap_TreatedAsBlack()
        {
            Assert.True(FlashSnapshot.IsLikelyBlackFrame(null, null));
        }

        [Fact]
        public void AllBlack_ReturnsTrue()
        {
            using (Bitmap b = new Bitmap(100, 100, PixelFormat.Format32bppArgb))
            {
                using (Graphics g = Graphics.FromImage(b))
                using (SolidBrush br = new SolidBrush(Color.Black))
                    g.FillRectangle(br, 0, 0, 100, 100);
                Assert.True(FlashSnapshot.IsLikelyBlackFrame(b, null));
            }
        }

        [Fact]
        public void AllWhite_ReturnsFalse()
        {
            using (Bitmap b = new Bitmap(100, 100, PixelFormat.Format32bppArgb))
            {
                using (Graphics g = Graphics.FromImage(b))
                using (SolidBrush br = new SolidBrush(Color.White))
                    g.FillRectangle(br, 0, 0, 100, 100);
                Assert.False(FlashSnapshot.IsLikelyBlackFrame(b, null));
            }
        }

        [Fact]
        public void MidGray_ReturnsFalse()
        {
            using (Bitmap b = new Bitmap(100, 100, PixelFormat.Format32bppArgb))
            {
                using (Graphics g = Graphics.FromImage(b))
                using (SolidBrush br = new SolidBrush(Color.FromArgb(128, 128, 128)))
                    g.FillRectangle(br, 0, 0, 100, 100);
                Assert.False(FlashSnapshot.IsLikelyBlackFrame(b, null));
            }
        }

        [Fact]
        public void NearBlack_BelowThreshold_ReturnsTrue()
        {
            // 低亮且完全均匀，没有任何画面细节 → black frame
            using (Bitmap b = new Bitmap(100, 100, PixelFormat.Format32bppArgb))
            {
                using (Graphics g = Graphics.FromImage(b))
                using (SolidBrush br = new SolidBrush(Color.FromArgb(20, 20, 20)))
                    g.FillRectangle(br, 0, 0, 100, 100);
                Assert.True(FlashSnapshot.IsLikelyBlackFrame(b, null));
            }
        }

        [Fact]
        public void DarkStructuredScene_IsNotDiscardedAsBlack()
        {
            // CF7 基地等场景整体很暗，但仍有墙体、人物和 UI 高光；这些细节必须保留给设置预览。
            using (Bitmap b = new Bitmap(160, 160, PixelFormat.Format32bppArgb))
            {
                using (Graphics g = Graphics.FromImage(b))
                {
                    g.Clear(Color.FromArgb(8, 10, 12));
                    using (SolidBrush wall = new SolidBrush(Color.FromArgb(26, 31, 34)))
                        g.FillRectangle(wall, 0, 48, 160, 112);
                    using (SolidBrush actor = new SolidBrush(Color.FromArgb(63, 44, 28)))
                        g.FillRectangle(actor, 58, 40, 44, 92);
                    using (SolidBrush ui = new SolidBrush(Color.FromArgb(78, 116, 126)))
                        g.FillRectangle(ui, 16, 16, 112, 8);
                }
                FlashSnapshot.FrameSampleStats stats = FlashSnapshot.AnalyzeFrame(b, null);
                Assert.True(stats.AverageLuminance < 30);
                Assert.True(stats.HighlightCount >= 2 || stats.MaximumLuminance - stats.MinimumLuminance >= 18);
                Assert.False(stats.IsLikelyBlack);
            }
        }

        [Fact]
        public void InvalidContentRect_IsTreatedAsUnavailableWithoutThrowing()
        {
            using (Bitmap b = new Bitmap(100, 100, PixelFormat.Format32bppArgb))
            {
                Assert.True(FlashSnapshot.IsLikelyBlackFrame(
                    b,
                    new Rectangle(200, 200, 50, 50)));
            }
        }

        [Fact]
        public void OnlySamplesContentRect_LetterboxBlackBordersIgnored()
        {
            // 200x200，contentRect=居中 100x100 灰色，外围全黑（letterbox）
            using (Bitmap b = new Bitmap(200, 200, PixelFormat.Format32bppArgb))
            {
                using (Graphics g = Graphics.FromImage(b))
                {
                    using (SolidBrush bk = new SolidBrush(Color.Black))
                        g.FillRectangle(bk, 0, 0, 200, 200);
                    using (SolidBrush gr = new SolidBrush(Color.FromArgb(180, 180, 180)))
                        g.FillRectangle(gr, 50, 50, 100, 100);
                }
                Rectangle content = new Rectangle(50, 50, 100, 100);
                Assert.False(FlashSnapshot.IsLikelyBlackFrame(b, content));
            }
        }
    }
}
