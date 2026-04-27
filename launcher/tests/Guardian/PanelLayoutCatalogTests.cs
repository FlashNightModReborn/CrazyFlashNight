using System.Drawing;
using CF7Launcher.Guardian;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    /// <summary>
    /// Phase 5 当前行为：jukebox 走 880×620 小矩形（jukebox-panel.js 用 inset 百分比布局，与 panelRect 大小解耦）；
    /// 其他 panel（kshop / help / map / lockbox / pinalign / gobang / unknown / null）仍按全 anchor 打开——
    /// 它们的 web CSS 假设全 anchor viewport，缩到小矩形会物理裁切。Phase 3+ web CSS 适配 panel_viewport_set 后再切回小矩形。
    ///
    /// Centered helper 独立测试作为切回小矩形时的回归保护。
    /// </summary>
    public class PanelLayoutCatalogTests
    {
        private static readonly Rectangle Anchor1080p = new Rectangle(100, 50, 1920, 1080);

        [Fact]
        public void Phase5_NonJukeboxPanels_ReturnFullAnchor()
        {
            string[] names = { "map", "kshop", "help", "lockbox", "pinalign", "gobang", "unknown", null };
            foreach (string n in names)
            {
                Rectangle r = PanelLayoutCatalog.GetRect(n, Anchor1080p);
                Assert.Equal(Anchor1080p, r);
            }
        }

        [Fact]
        public void Phase5_Jukebox_Returns880x620CenteredInAnchor()
        {
            Rectangle r = PanelLayoutCatalog.GetRect("jukebox", Anchor1080p);
            Assert.Equal(880, r.Width);
            Assert.Equal(620, r.Height);
            Assert.Equal(100 + (1920 - 880) / 2, r.X);
            Assert.Equal(50 + (1080 - 620) / 2, r.Y);
        }

        [Fact]
        public void Phase5_Jukebox_CaseInsensitive()
        {
            Rectangle r = PanelLayoutCatalog.GetRect("JUKEBOX", Anchor1080p);
            Assert.Equal(880, r.Width);
            Assert.Equal(620, r.Height);
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
