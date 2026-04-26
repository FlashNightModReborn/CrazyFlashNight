using Xunit;
using CF7Launcher.Guardian.Hud;

namespace CF7Launcher.Tests.Guardian
{
    /// <summary>
    /// SafeExitPanelWidget 状态机：sv:1 → Saving，sv:2 → Done，s:0 → 复位 Idle。
    /// 不实际构造 widget（依赖 Control + FlashCoordinateMapper）；只验证 sv 解析路径
    /// 通过 NotchToolbarWidget.ParseUiIntValue（widget 实际调用）行为正确。
    /// </summary>
    public class SafeExitPanelWidgetTests
    {
        [Theory]
        [InlineData("sv:1", 1)]
        [InlineData("sv:2", 2)]
        [InlineData("sv:0", 0)]
        [InlineData("1", 1)]
        [InlineData("2", 2)]
        [InlineData("", 0)]
        [InlineData(null, 0)]
        [InlineData("sv:foo", 0)]
        public void ParseSv_PrefixedAndBare(string input, int expected)
        {
            Assert.Equal(expected, NotchToolbarWidget.ParseUiIntValue(input));
        }

        [Theory]
        [InlineData("s:1", true)]
        [InlineData("s:0", false)]
        [InlineData("1", true)]
        [InlineData("0", false)]
        public void ParseGameReady_PrefixedAndBare(string input, bool expected)
        {
            Assert.Equal(expected, TopRightToolsWidget.ParseUiBoolValue(input));
        }
    }
}
