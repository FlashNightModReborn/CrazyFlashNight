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
    }
}
