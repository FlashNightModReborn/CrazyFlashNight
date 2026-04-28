using CF7Launcher.Guardian;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public class NotchOverlayTests
    {
        [Theory]
        [InlineData(false, 1.0f, 12.0f)]
        [InlineData(false, 1.875f, 22.5f)]
        [InlineData(true, 1.0f, 13.0f)]
        [InlineData(true, 1.875f, 24.375f)]
        public void InfoRowFontPx_FollowsViewportScale(bool isGame, float scale, float expected)
        {
            float actual = NotchOverlay.InfoRowFontPxForTest(isGame, scale);
            Assert.True(System.Math.Abs(actual - expected) < 0.001f,
                "expected " + expected + ", got " + actual);
        }
    }
}
