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
            // 平均亮度 < 30 → black frame
            using (Bitmap b = new Bitmap(100, 100, PixelFormat.Format32bppArgb))
            {
                using (Graphics g = Graphics.FromImage(b))
                using (SolidBrush br = new SolidBrush(Color.FromArgb(20, 20, 20)))
                    g.FillRectangle(br, 0, 0, 100, 100);
                Assert.True(FlashSnapshot.IsLikelyBlackFrame(b, null));
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
