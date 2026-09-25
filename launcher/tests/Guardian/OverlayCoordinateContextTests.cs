using System;
using System.Drawing;
using CF7Launcher.Guardian;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public class OverlayCoordinateContextTests
    {
        [Fact]
        public void CssRectToPhysicalUsesWebViewportMetrics()
        {
            OverlayCoordinateContext ctx = new OverlayCoordinateContext();
            ctx.UpdateOverlay(new Rectangle(100, 200, 1500, 900), 0, 0, 1500, 900,
                IntPtr.Zero, 1.0, "test");
            ctx.UpdateWebMetrics(1000, 600, 1000, 600, 1.0, 1000, 600, "test");

            Rectangle r = ctx.CssRectToPhysical(10, 20, 30, 40);

            Assert.Equal(new Rectangle(15, 30, 45, 60), r);
        }

        [Fact]
        public void PhysicalPointToCssRoundTripsNonUniformScale()
        {
            OverlayCoordinateContext ctx = new OverlayCoordinateContext();
            ctx.UpdateOverlay(new Rectangle(0, 0, 1200, 900), 0, 0, 1200, 900,
                IntPtr.Zero, 1.0, "test");
            ctx.UpdateWebMetrics(800, 600, 800, 600, 1.5, 800, 600, "test");

            Point css = ctx.PhysicalPointToCss(300, 450);

            Assert.Equal(new Point(200, 300), css);
        }

        [Fact]
        public void CssRectToPhysicalSupportsDifferentXAndYScale()
        {
            OverlayCoordinateContext ctx = new OverlayCoordinateContext();
            ctx.UpdateOverlay(new Rectangle(0, 0, 1600, 900), 0, 0, 1600, 900,
                IntPtr.Zero, 1.0, "test");
            ctx.UpdateWebMetrics(800, 600, 800, 600, 1.0, 800, 600, "test");

            Rectangle r = ctx.CssRectToPhysical(100, 100, 50, 60);

            Assert.Equal(new Rectangle(200, 150, 100, 90), r);
        }

        [Fact]
        public void MissingWebMetricsFallsBackToZoomFactor()
        {
            OverlayCoordinateContext ctx = new OverlayCoordinateContext();
            ctx.UpdateOverlay(new Rectangle(0, 0, 1750, 980), 0, 0, 1750, 980,
                IntPtr.Zero, 1.75, "test");

            Rectangle r = ctx.CssRectToPhysical(10, 10, 20, 20);
            Point p = ctx.PhysicalPointToCss(175, 350);

            Assert.Equal(new Rectangle(17, 17, 36, 36), r);
            Assert.Equal(new Point(100, 200), p);
            Assert.False(ctx.LastDpiResolved);
            Assert.Equal(96, ctx.WindowDpiY);
        }

        [Fact]
        public void NegativeOffscreenPointIsPreservedForMouseLeave()
        {
            OverlayCoordinateContext ctx = new OverlayCoordinateContext();

            Assert.Equal(new Point(-1, -1), ctx.PhysicalPointToCss(-1, -1));
        }

        [Fact]
        public void WebViewZoomMatchesPhysicalScaleAtOneHundredPercentDpi()
        {
            double physicalScale = WebOverlayForm.CalculateCssPhysicalScale(900);
            double webZoom = WebOverlayForm.CalculateWebViewZoomFactor(900, 96);

            Assert.Equal(1.5625, physicalScale, 4);
            Assert.Equal(physicalScale, webZoom, 4);
        }

        [Fact]
        public void WebViewZoomIsDpiNormalized()
        {
            double physicalScale = WebOverlayForm.CalculateCssPhysicalScale(900);
            double webZoom = WebOverlayForm.CalculateWebViewZoomFactor(900, 144);

            Assert.Equal(1.5625, physicalScale, 4);
            Assert.Equal(1.0417, webZoom, 4);
        }

        // 2026-09-24 真机问题 2：idle 冻结后 OverlayPhysicalBounds 陈旧（1600×900），
        // panel_resume 必须刷新为本次 panelRect（2560×1440）——否则 CSS→physical
        // 命中换算按陈旧 bounds 计算（0.976 而非 1.5625）。本测试锁定刷新后的正确语义。
        [Fact]
        public void PanelResumeRefreshReplacesStaleBoundsForHitMapping()
        {
            OverlayCoordinateContext ctx = new OverlayCoordinateContext();
            ctx.UpdateOverlay(new Rectangle(480, 331, 1600, 900), 0, 0, 1600, 900,
                IntPtr.Zero, 1.0, "anchor_resize");
            ctx.UpdateWebMetrics(1024, 576, 1024, 576, 1.5625, 1024, 576, "web_ready");
            Assert.Equal(new Rectangle(480, 331, 1600, 900), ctx.OverlayPhysicalBounds);

            // ResumeForPanel 语义：bounds 换成 panel rect，视口为整个 panel（0,0,W,H），zoom 1.0
            ctx.UpdateOverlay(new Rectangle(0, 61, 2560, 1440), 0, 0, 2560, 1440,
                IntPtr.Zero, 1.0, "panel_resume");
            ctx.UpdateWebMetrics(1639, 921, 1639, 921, 1.5625, 1639, 921, "panel_viewport_set");

            Assert.Equal(new Rectangle(0, 61, 2560, 1440), ctx.OverlayPhysicalBounds);
            Assert.Equal(2560.0 / 1639.0, ctx.CssToPhysicalX, 4);
            Assert.Equal(1440.0 / 921.0, ctx.CssToPhysicalY, 4);
            // 命中换算为 overlay 相对物理像素（调用方自行加 bounds 原点）：
            // 修复前按陈旧 1600×900 得 0.976 倍；现按本次 panelRect 得 ≈1.5625 倍。
            Rectangle rect = ctx.CssRectToPhysical(100, 100, 10, 10);
            Assert.Equal((int)(100 * 2560.0 / 1639.0), rect.X);
            Assert.Equal((int)(100 * 1440.0 / 921.0), rect.Y);
        }
    }
}
