using System.Drawing;
using CF7Launcher.Guardian;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    /// <summary>
    /// 沉浸全屏化（2026-06-12）后：所有运行时 panel（含 jukebox / arena，原走 Centered 小矩形）一律返回全 anchor，
    /// 因为各自 web 端已改固定 1024×576 画布 + .panel-scale-shell 整体等比缩放铺满全 16:9。
    ///
    /// Centered / ScalePanelSize 仅作「未来 panel 重新走子矩形」的工具，下方 Centered_* 独立测试作回归保护。
    /// </summary>
    public class PanelLayoutCatalogTests
    {
        private static readonly Rectangle Anchor1080p = new Rectangle(100, 50, 1920, 1080);

        [Fact]
        public void AllRuntimePanels_ReturnFullAnchor()
        {
            // 沉浸全屏化后 jukebox / arena 也回全 anchor（原 Centered 子矩形已退役）
            string[] names = { "map", "kshop", "help", "lockbox", "pinalign", "gobang", "team", "arena",
                               "jukebox", "intelligence", "stage-select", "tasks", "unknown", null };
            foreach (string n in names)
            {
                Rectangle r = PanelLayoutCatalog.GetRect(n, Anchor1080p);
                Assert.Equal(Anchor1080p, r);
            }
        }

        [Fact]
        public void Jukebox_CaseInsensitive_ReturnsFullAnchor()
        {
            Rectangle r = PanelLayoutCatalog.GetRect("JUKEBOX", Anchor1080p);
            Assert.Equal(Anchor1080p, r);
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
