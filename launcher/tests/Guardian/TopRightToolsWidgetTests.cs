using System.Collections.Generic;
using CF7Launcher.Guardian.Hud;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    /// <summary>
    /// TopRightToolsWidget 状态机 + UiData 解析回归。
    /// 不覆盖 Paint / 鼠标命中（依赖 Form 实例 + GDI Graphics，跑在 xUnit 内不实际）。
    /// </summary>
    public class TopRightToolsWidgetTests
    {
        [Theory]
        [InlineData("p:1", true)]
        [InlineData("p:0", false)]
        [InlineData("s:1", true)]
        [InlineData("s:0", false)]
        [InlineData("1", true)]
        [InlineData("0", false)]
        [InlineData("", false)]
        [InlineData(null, false)]
        public void ParseUiBoolValue_HandlesPrefixedAndBareValues(string input, bool expected)
        {
            Assert.Equal(expected, TopRightToolsWidget.ParseUiBoolValue(input));
        }

        [Fact]
        public void ParseUiBoolValue_StripsKeyPrefix()
        {
            // "key:val" 形式：仅取 ":" 后第一段；非 "1" 视为 false
            Assert.False(TopRightToolsWidget.ParseUiBoolValue("p:foo"));
            Assert.False(TopRightToolsWidget.ParseUiBoolValue("p:"));
            Assert.True(TopRightToolsWidget.ParseUiBoolValue("p:1"));
        }
    }
}
