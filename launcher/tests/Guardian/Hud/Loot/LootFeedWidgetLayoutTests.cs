using Xunit;
using CF7Launcher.Guardian.Hud.Loot;

namespace CF7Launcher.Tests.Guardian.Hud.Loot
{
    public class LootFeedWidgetLayoutTests
    {
        [Theory]
        [InlineData(1L, "")]
        [InlineData(2L, "×9")]
        [InlineData(9L, "×9")]
        [InlineData(10L, "×99")]
        [InlineData(99L, "×99")]
        [InlineData(100L, "×999")]
        [InlineData(long.MaxValue, "×9999999999999999999")]
        public void CountColumnSample_ReservesOnlyTheCurrentDigitBucket(long count, string expected)
        {
            Assert.Equal(expected, LootFeedWidget.CountColumnSample(count));
        }

        [Theory]
        [InlineData(80, 96, 220, 8, 96)]
        [InlineData(97, 96, 220, 8, 104)]
        [InlineData(104, 96, 220, 8, 104)]
        [InlineData(105, 96, 220, 8, 112)]
        [InlineData(219, 96, 220, 8, 220)]
        [InlineData(260, 96, 220, 8, 220)]
        public void QuantizeWidthPx_UsesSmallStableStepsAndClamps(
            int required, int minimum, int maximum, int quantum, int expected)
        {
            Assert.Equal(expected,
                LootFeedWidget.QuantizeWidthPx(required, minimum, maximum, quantum));
        }

        [Theory]
        [InlineData(1L, 0)]
        [InlineData(2L, 1)]
        [InlineData(3L, 1)]
        [InlineData(4L, 2)]
        [InlineData(7L, 2)]
        [InlineData(8L, 3)]
        [InlineData(100L, 3)]
        public void CountImpactLevel_IsBoundedAndRewardsLargerBatches(long delta, int expected)
        {
            Assert.Equal(expected, LootFeedWidget.CountImpactLevel(delta));
        }

        [Theory]
        [InlineData("gain", "item", 1L, "")]
        [InlineData("gain", "item", 2L, "×2")]
        [InlineData("loss", "item", 1L, "−1")]
        [InlineData("loss", "item", 25L, "−25")]
        [InlineData("neutral", "kill", 1L, "")]
        [InlineData("neutral", "kill", 3L, "×3")]
        public void CountText_ShowsExplicitSignedLoss(
            string direction, string kind, long count, string expected)
        {
            Assert.Equal(expected,
                LootFeedWidget.CountTextForTest(direction, kind, count));
        }
    }
}
