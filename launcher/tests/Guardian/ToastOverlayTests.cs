using CF7Launcher.Guardian;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public class ToastOverlayTests
    {
        [Theory]
        [InlineData(1.0f, 11.0f)]
        [InlineData(1.875f, 20.625f)]
        public void ToastFontPx_FollowsViewportScale(float scale, float expected)
        {
            float actual = ToastOverlay.ToastFontPxForScale(scale);
            Assert.True(System.Math.Abs(actual - expected) < 0.001f,
                "expected " + expected + ", got " + actual);
        }
    }
}
