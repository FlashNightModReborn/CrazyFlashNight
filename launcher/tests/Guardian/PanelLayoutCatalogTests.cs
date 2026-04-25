using System.Drawing;
using CF7Launcher.Guardian;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    /// <summary>
    /// Phase 3 临时行为：所有 panel 都返回全 anchor（web 端 panels.js 还没 handle panel_viewport_set）。
    /// Phase 3+ web CSS 适配后再恢复"按 panel 名分配小矩形"的测试断言（参考 GetRect 内 unreachable switch）。
    ///
    /// Centered helper 仍可独立测试，作为 Phase 3+ 切回小矩形时的回归保护。
    /// </summary>
    public class PanelLayoutCatalogTests
    {
        private static readonly Rectangle Anchor1080p = new Rectangle(100, 50, 1920, 1080);

        [Fact]
        public void Phase3_AllPanels_ReturnFullAnchor()
        {
            string[] names = { "map", "kshop", "help", "lockbox", "pinalign", "gobang", "jukebox", "unknown", null };
            foreach (string n in names)
            {
                Rectangle r = PanelLayoutCatalog.GetRect(n, Anchor1080p);
                Assert.Equal(Anchor1080p, r);
            }
        }

        [Fact]
        public void Centered_RequestedSize_LargerThanAnchor_ClampsToAnchor()
        {
            // anchor 600x400; 请求 1024x720
            Rectangle small = new Rectangle(0, 0, 600, 400);
            Rectangle r = PanelLayoutCatalog.Centered(small, 1024, 720);
            Assert.Equal(600, r.Width);
            Assert.Equal(400, r.Height);
            Assert.Equal(0, r.X);
            Assert.Equal(0, r.Y);
        }

        [Fact]
        public void Centered_NormalCase_CentersInAnchor()
        {
            Rectangle r = PanelLayoutCatalog.Centered(Anchor1080p, 1024, 720);
            Assert.Equal(1024, r.Width);
            Assert.Equal(720, r.Height);
            Assert.Equal(100 + (1920 - 1024) / 2, r.X);
            Assert.Equal(50 + (1080 - 720) / 2, r.Y);
        }
    }
}
