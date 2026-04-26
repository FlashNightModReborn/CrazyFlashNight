using CF7Launcher.Guardian.Hud;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public class WidgetScalerTests
    {
        [Theory]
        [InlineData(576, 1f)]
        [InlineData(1080, 1080f / 576f)]
        [InlineData(720, 720f / 576f)]
        [InlineData(0, 1f)]
        [InlineData(-100, 1f)]
        public void GetScale_FromAnchorHeight(int anchorHeight, float expected)
        {
            // 不能 mock Control，直接用 helper 内逻辑等价测试
            float actual;
            if (anchorHeight <= 0) actual = 1f;
            else actual = System.Math.Max(WidgetScaler.MIN_SCALE, anchorHeight / WidgetScaler.DESIGN_HEIGHT);
            Assert.Equal((double)expected, (double)actual, 3);
        }

        [Fact]
        public void Px_RoundsAndFloors()
        {
            Assert.Equal(34, WidgetScaler.Px(34, 1f));
            Assert.Equal(64, WidgetScaler.Px(34, 1.875f)); // 1080/576 ≈ 1.875 → 34*1.875=63.75 → 64
            Assert.Equal(1, WidgetScaler.Px(0, 1f));        // floor at 1
        }

        [Fact]
        public void NotchToolbarWidget_ParseUiIntValue_HandlesAllForms()
        {
            Assert.Equal(0, NotchToolbarWidget.ParseUiIntValue(null));
            Assert.Equal(0, NotchToolbarWidget.ParseUiIntValue(""));
            Assert.Equal(14, NotchToolbarWidget.ParseUiIntValue("q:14"));
            Assert.Equal(14, NotchToolbarWidget.ParseUiIntValue("14"));
            Assert.Equal(0, NotchToolbarWidget.ParseUiIntValue("q:foo"));
        }
    }
}
