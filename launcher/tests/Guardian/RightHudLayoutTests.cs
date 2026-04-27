using System.Drawing;
using CF7Launcher.Guardian.Hud;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public class RightHudLayoutTests
    {
        [Theory]
        [InlineData(1024, 576)]
        [InlineData(1600, 900)]
        [InlineData(1920, 1080)]
        public void TopTools_UsesWebRightOffsetAndWidth(int width, int height)
        {
            Rectangle viewport = new Rectangle(0, 0, width, height);
            float scale = RightHudLayout.ScaleForViewport(viewport);
            Rectangle tools = RightHudLayout.TopToolsRectFromViewport(viewport, scale);

            int expectedW = WidgetScaler.Px(RightHudLayout.ClusterWidthBase, scale);
            int expectedH = WidgetScaler.Px(RightHudLayout.ToolBarHeightBase, scale);
            int expectedRightOffset = WidgetScaler.Px(RightHudLayout.RightOffsetBase, scale);

            Assert.Equal(expectedW, tools.Width);
            Assert.Equal(expectedH, tools.Height);
            Assert.Equal(width - expectedRightOffset, tools.Right);
            Assert.Equal(width - expectedW - expectedRightOffset, tools.X);
            Assert.Equal(0, tools.Y);
        }

        [Theory]
        [InlineData(1024, 576, true, true)]
        [InlineData(1600, 900, true, false)]
        [InlineData(1920, 1080, false, true)]
        public void ContextHeight_IsMapPlusQuestRowPlusNotice(int width, int height, bool showMap, bool showNotice)
        {
            Rectangle viewport = new Rectangle(0, 0, width, height);
            float scale = RightHudLayout.ScaleForViewport(viewport);
            Rectangle context = RightHudLayout.ContextPanelRectFromViewport(viewport, scale, showMap, showNotice);

            int expectedH = WidgetScaler.Px(RightHudLayout.QuestRowHeightBase, scale);
            if (showMap) expectedH += WidgetScaler.Px(RightHudLayout.MapHeightBase, scale);
            if (showNotice) expectedH += WidgetScaler.Px(RightHudLayout.QuestNoticeHeightBase, scale);

            Assert.Equal(WidgetScaler.Px(RightHudLayout.ClusterWidthBase, scale), context.Width);
            Assert.Equal(WidgetScaler.Px(RightHudLayout.ToolBarHeightBase, scale), context.Y);
            Assert.Equal(expectedH, context.Height);
        }

        [Theory]
        [InlineData(1024, 576, true, true)]
        [InlineData(1600, 900, true, false)]
        [InlineData(1920, 1080, false, true)]
        public void Jukebox_FollowsContextPanelBottom(int width, int height, bool showMap, bool showNotice)
        {
            Rectangle viewport = new Rectangle(0, 0, width, height);
            float scale = RightHudLayout.ScaleForViewport(viewport);
            Rectangle context = RightHudLayout.ContextPanelRectFromViewport(viewport, scale, showMap, showNotice);
            Rectangle jukebox = RightHudLayout.JukeboxRectFromViewport(viewport, scale, showMap, showNotice);

            Assert.Equal(context.X, jukebox.X);
            Assert.Equal(context.Bottom, jukebox.Y);
            Assert.Equal(context.Width, jukebox.Width);
            Assert.Equal(WidgetScaler.Px(RightHudLayout.JukeboxHeightBase, scale), jukebox.Height);
        }

        [Fact]
        public void SafeExit_UsesSameRightOffset()
        {
            Rectangle viewport = new Rectangle(0, 0, 1024, 576);
            float scale = RightHudLayout.ScaleForViewport(viewport);
            Rectangle safe = RightHudLayout.SafeExitRectFromViewport(viewport, scale, 58);

            Assert.Equal(WidgetScaler.Px(RightHudLayout.SafeExitTotalWidthBase, scale), safe.Width);
            Assert.Equal(1024 - WidgetScaler.Px(RightHudLayout.RightOffsetBase, scale), safe.Right);
            Assert.Equal(WidgetScaler.Px(RightHudLayout.ToolBarHeightBase, scale), safe.Y);
        }
    }
}
