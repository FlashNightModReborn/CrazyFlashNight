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
        public void Phase5_Jukebox_AtDesignAnchor_Returns880xClampedHeight()
        {
            // anchor 1024×576（design viewport，scale=1）→ 请求 880×620，高度被 Centered clamp 到 576
            Rectangle design = new Rectangle(0, 0, 1024, 576);
            Rectangle r = PanelLayoutCatalog.GetRect("jukebox", design);
            Assert.Equal(880, r.Width);
            Assert.Equal(576, r.Height);
        }

        [Fact]
        public void Phase5_Jukebox_AtLargeAnchor_ScalesByViewportHeight()
        {
            // anchor 1920×1080 → scale=1080/576=1.875；请求 1650×1163；高度 Centered clamp 到 1080
            Rectangle r = PanelLayoutCatalog.GetRect("jukebox", Anchor1080p);
            Assert.Equal(1650, r.Width);
            Assert.Equal(1080, r.Height);
            Assert.Equal(100 + (1920 - 1650) / 2, r.X);
            Assert.Equal(50, r.Y);
        }

        [Fact]
        public void Phase5_Jukebox_AtTinyAnchor_FloorAtMinScale()
        {
            // 极小 anchor 触发 MIN_SCALE=0.5 floor，保证按钮仍可点击
            Rectangle tiny = new Rectangle(0, 0, 200, 100);
            Rectangle r = PanelLayoutCatalog.GetRect("jukebox", tiny);
            // scale = max(0.5, 100/576) = 0.5；请求 440×310；Centered clamp 到 200×100
            Assert.Equal(200, r.Width);
            Assert.Equal(100, r.Height);
        }

        [Fact]
        public void Phase5_Jukebox_CaseInsensitive()
        {
            Rectangle r = PanelLayoutCatalog.GetRect("JUKEBOX", Anchor1080p);
            // 仅断言走了 jukebox 分支（被缩放），不是 default 全 anchor
            Assert.NotEqual(Anchor1080p, r);
            Assert.Equal(1650, r.Width);
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
