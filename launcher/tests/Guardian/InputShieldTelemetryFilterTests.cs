using System.Drawing;
using CF7Launcher.Guardian;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    /// <summary>
    /// 过滤逻辑单测：覆盖 ClassifyTelemetryClick 的全部路径。
    /// 返回值：1 = clicks_outside_panel; 0 = inside panel; -1 = filtered (external).
    /// </summary>
    public class InputShieldTelemetryFilterTests
    {
        private static readonly Rectangle Anchor = new Rectangle(100, 50, 1920, 1080);
        private static readonly Rectangle PanelInside = new Rectangle(500, 300, 800, 600); // 完全在 anchor 内

        [Fact]
        public void ClickOutsideAnchor_FilteredAsExternal()
        {
            // anchor 之外，应过滤
            int kind = InputShieldForm.ClassifyTelemetryClick(new Point(50, 25), PanelInside, Anchor, true);
            Assert.Equal(-1, kind);
        }

        [Fact]
        public void ClickInsidePanel_NotCounted()
        {
            int kind = InputShieldForm.ClassifyTelemetryClick(new Point(700, 500), PanelInside, Anchor, true);
            Assert.Equal(0, kind);
        }

        [Fact]
        public void ClickInsideAnchorOutsidePanel_Counted()
        {
            // (200,100) 在 anchor 内但不在 panel 内
            int kind = InputShieldForm.ClassifyTelemetryClick(new Point(200, 100), PanelInside, Anchor, true);
            Assert.Equal(1, kind);
        }

        [Fact]
        public void ForegroundNotGuardian_AlwaysFiltered()
        {
            // 即使 click 在 anchor+outside-panel，前台不是 Guardian → 不计
            int kind = InputShieldForm.ClassifyTelemetryClick(new Point(200, 100), PanelInside, Anchor, false);
            Assert.Equal(-1, kind);
        }

        [Fact]
        public void ClickAtPanelBoundary_Inside()
        {
            // Rectangle.Contains 包含左/上边、不包含右/下边
            int kindAtTopLeft = InputShieldForm.ClassifyTelemetryClick(
                new Point(PanelInside.Left, PanelInside.Top), PanelInside, Anchor, true);
            Assert.Equal(0, kindAtTopLeft);
        }

        [Fact]
        public void ClickAtAnchorBoundary_FilteredOnRightEdge()
        {
            // anchor.Right 不在 anchor 内 → 过滤
            int kind = InputShieldForm.ClassifyTelemetryClick(
                new Point(Anchor.Right, Anchor.Top + 10), PanelInside, Anchor, true);
            Assert.Equal(-1, kind);
        }
    }
}
