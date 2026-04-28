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

        [Theory]
        [InlineData(1.0f, 144)]
        [InlineData(1.875f, 270)]
        public void ExpandedChartHeight_FollowsWebPanelGeometry(float scale, int expected)
        {
            Assert.Equal(expected, NotchOverlay.ExpandedChartHeightForTest(scale));
        }

        [Fact]
        public void ExpandedChartScale_AddsMinimumRangeForFlatSamples()
        {
            float[] points = { 30f, 30f, 30f };

            NotchOverlay.FpsChartScale scale = NotchOverlay.ComputeFpsChartScaleForTest(points);

            Assert.True(System.Math.Abs(scale.MinV - 27.5f) < 0.001f);
            Assert.True(System.Math.Abs(scale.MaxV - 32.5f) < 0.001f);
            Assert.True(System.Math.Abs(scale.Range - 5f) < 0.001f);
        }

        [Fact]
        public void ExpandedChartStats_UsesWebLowPercentileDefinition()
        {
            float[] points = new float[100];
            for (int i = 0; i < points.Length; i++) points[i] = 30f;
            points[0] = 10f;
            points[1] = 20f;
            points[2] = 22f;
            points[3] = 24f;
            points[4] = 26f;

            NotchOverlay.FpsChartStats stats = NotchOverlay.ComputeFpsStatsForTest(points);

            Assert.True(System.Math.Abs(stats.P1Low - 10f) < 0.001f);
            Assert.True(System.Math.Abs(stats.P5Low - 20.4f) < 0.001f);
            Assert.Equal(10f, stats.Lo);
            Assert.Equal(30f, stats.Hi);
        }

        [Fact]
        public void HoverExpandGate_RespectsManualCollapseCooldown()
        {
            Assert.Equal(600, NotchOverlay.ExpandClickCooldownMsForTest());
            Assert.True(NotchOverlay.ShouldStartHoverExpandForTest(true, 0));
            Assert.False(NotchOverlay.ShouldStartHoverExpandForTest(true, 1));
            Assert.False(NotchOverlay.ShouldStartHoverExpandForTest(false, 0));
        }
    }
}
