using System.Drawing;
using System.Drawing.Imaging;
using CF7Launcher.Guardian;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    /// <summary>
    /// letterbox 截图合成回归：ComposeBackdrop 输出尺寸必须 = contentRect 尺寸（与 WebOverlay.Bounds 一致），
    /// 而不是 fullSnapshot 全 client 尺寸——否则 DrawImageUnscaled 会把 letterbox 黑边带进 backdrop 导致错位。
    /// </summary>
    public class FlashSnapshotComposeBackdropTests
    {
        private static Bitmap MakeFilled(int w, int h, Color c)
        {
            Bitmap b = new Bitmap(w, h, PixelFormat.Format32bppArgb);
            using (Graphics g = Graphics.FromImage(b))
            using (SolidBrush br = new SolidBrush(c))
                g.FillRectangle(br, 0, 0, w, h);
            return b;
        }

        [Fact]
        public void Letterbox_OutputDimensions_MatchContentRect()
        {
            // flash full client = 1920x1080，contentRect = 16:9 缩到 1600x900 居中
            using (Bitmap full = MakeFilled(1920, 1080, Color.Red))
            {
                Rectangle content = new Rectangle(160, 90, 1600, 900);
                using (Bitmap result = FlashSnapshot.ComposeBackdrop(full, content, 0))
                {
                    Assert.Equal(1600, result.Width);
                    Assert.Equal(900, result.Height);
                }
            }
        }

        [Fact]
        public void NoLetterbox_OutputDimensions_MatchFullSnapshot()
        {
            using (Bitmap full = MakeFilled(1024, 576, Color.Blue))
            {
                Rectangle content = new Rectangle(0, 0, 1024, 576);
                using (Bitmap result = FlashSnapshot.ComposeBackdrop(full, content, 0))
                {
                    Assert.Equal(1024, result.Width);
                    Assert.Equal(576, result.Height);
                }
            }
        }

        [Fact]
        public void DegenerateContentRect_FallsBackToFullSize()
        {
            // 防御：contentRect 退化（0x0）时不应输出空 bitmap
            using (Bitmap full = MakeFilled(800, 600, Color.Green))
            {
                Rectangle content = new Rectangle(0, 0, 0, 0);
                using (Bitmap result = FlashSnapshot.ComposeBackdrop(full, content, 0))
                {
                    Assert.Equal(800, result.Width);
                    Assert.Equal(600, result.Height);
                }
            }
        }

        [Fact]
        public void DimAlpha_AppliedToContentRectArea()
        {
            // 输出尺寸 = contentRect；dim 覆盖整个输出（即整个 contentRect 区域）
            using (Bitmap full = MakeFilled(400, 300, Color.White))
            {
                Rectangle content = new Rectangle(50, 30, 200, 150);
                using (Bitmap result = FlashSnapshot.ComposeBackdrop(full, content, 200))
                {
                    Assert.Equal(200, result.Width);
                    Assert.Equal(150, result.Height);
                    // 中心像素应当变暗（白色 + alpha=200 黑覆盖）
                    Color centerPixel = result.GetPixel(100, 75);
                    Assert.True(centerPixel.R < 100, "Center pixel should be dimmed: R=" + centerPixel.R);
                }
            }
        }
    }
}
