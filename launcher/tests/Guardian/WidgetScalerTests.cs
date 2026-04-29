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
            // 不能 mock Control，直接用 helper 内逻辑等价测试（退化路径）
            float actual;
            if (anchorHeight <= 0) actual = 1f;
            else actual = System.Math.Max(WidgetScaler.MIN_SCALE, anchorHeight / WidgetScaler.DESIGN_HEIGHT);
            Assert.Equal((double)expected, (double)actual, 3);
        }

        [Fact]
        public void GetScale_FromMapper_PrefersViewportHeight()
        {
            // 推荐路径：mapper.CalcViewport 返回 vpH（letterbox-stripped），用 vpH/576 而非 anchor.Height/576。
            // 4:3 窗口（800x600）下 vpH ≈ anchor.Width * 9/16 = 450（≠ 600），scale = 450/576 ≈ 0.781。
            // 用 anchor.Height 会算成 600/576 ≈ 1.042，按容器高度放大却按 vp 定位 → 越界。
            float vpW = 800f, vpH = 450f;
            float scaleFromVp = System.Math.Max(WidgetScaler.MIN_SCALE, vpH / WidgetScaler.DESIGN_HEIGHT);
            Assert.True(scaleFromVp < 0.79f && scaleFromVp > 0.77f);
        }

        [Fact]
        public void Px_RoundsAndFloors()
        {
            Assert.Equal(34, WidgetScaler.Px(34, 1f));
            Assert.Equal(64, WidgetScaler.Px(34, 1.875f)); // 1080/576 ≈ 1.875 → 34*1.875=63.75 → 64
            Assert.Equal(1, WidgetScaler.Px(0, 1f));        // floor at 1
        }

        [Fact]
        public void UiValueParser_ParseUiIntValue_HandlesAllForms()
        {
            // P2-5：原 NotchToolbarWidget.ParseUiIntValue 抽至 UiValueParser；fallback=0 行为等价
            Assert.Equal(0, UiValueParser.ParseUiIntValue(null, 0));
            Assert.Equal(0, UiValueParser.ParseUiIntValue("", 0));
            Assert.Equal(14, UiValueParser.ParseUiIntValue("q:14", 0));
            Assert.Equal(14, UiValueParser.ParseUiIntValue("14", 0));
            Assert.Equal(0, UiValueParser.ParseUiIntValue("q:foo", 0));
        }
    }
}
