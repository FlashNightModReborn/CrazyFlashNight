using System.Drawing;
using CF7Launcher.Guardian;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public class NativePanelBackdropClickRoutingTests
    {
        [Fact]
        public void NoPanelRectSet_AllClicksRouteToOutside()
        {
            // panel rect 未设：早期 panel 打开过程的防御性默认——所有 click 视为外部
            Assert.True(NativePanelBackdrop.ShouldFireOutsidePanelClick(null, new Point(100, 100)));
            Assert.True(NativePanelBackdrop.ShouldFireOutsidePanelClick(null, new Point(0, 0)));
        }

        [Fact]
        public void ClickInsidePanelRect_Swallowed()
        {
            // panel rect = (200,150,400,300)；click 在中心
            var rect = new Rectangle(200, 150, 400, 300);
            Assert.False(NativePanelBackdrop.ShouldFireOutsidePanelClick(rect, new Point(400, 300)));
            Assert.False(NativePanelBackdrop.ShouldFireOutsidePanelClick(rect, new Point(200, 150))); // 左上角
            Assert.False(NativePanelBackdrop.ShouldFireOutsidePanelClick(rect, new Point(599, 449))); // 右下角内 1px
        }

        [Fact]
        public void ClickOutsidePanelRect_RoutesToOutside()
        {
            var rect = new Rectangle(200, 150, 400, 300);
            // 各方向外
            Assert.True(NativePanelBackdrop.ShouldFireOutsidePanelClick(rect, new Point(50, 200)));   // 左
            Assert.True(NativePanelBackdrop.ShouldFireOutsidePanelClick(rect, new Point(700, 200))); // 右
            Assert.True(NativePanelBackdrop.ShouldFireOutsidePanelClick(rect, new Point(300, 50)));  // 上
            Assert.True(NativePanelBackdrop.ShouldFireOutsidePanelClick(rect, new Point(300, 500))); // 下
        }

        [Fact]
        public void ClickOnPanelRectBoundary_OutsideEdgeIsExclusive()
        {
            // Rectangle.Contains 把右/下边界视为外部（半开区间）。验证此契约不被未来重构破坏
            var rect = new Rectangle(0, 0, 100, 100);
            Assert.False(NativePanelBackdrop.ShouldFireOutsidePanelClick(rect, new Point(50, 50))); // 内
            Assert.True(NativePanelBackdrop.ShouldFireOutsidePanelClick(rect, new Point(100, 50))); // 右边界 = 外
            Assert.True(NativePanelBackdrop.ShouldFireOutsidePanelClick(rect, new Point(50, 100))); // 下边界 = 外
        }
    }
}
