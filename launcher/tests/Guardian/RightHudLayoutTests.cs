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
        [InlineData(1024, 576, EffectiveMapDisplayMode.Compact, true)]
        [InlineData(1600, 900, EffectiveMapDisplayMode.Expanded, false)]
        [InlineData(1920, 1080, EffectiveMapDisplayMode.Hidden, true)]
        public void ContextHeight_IsOptionalStatusPlusMap(int width, int height, EffectiveMapDisplayMode mapMode, bool showNotice)
        {
            Rectangle viewport = new Rectangle(0, 0, width, height);
            float scale = RightHudLayout.ScaleForViewport(viewport);
            Rectangle context = RightHudLayout.ContextPanelRectFromViewport(viewport, scale, mapMode, showNotice);

            int expectedH = showNotice ? WidgetScaler.Px(RightHudLayout.StatusSlotHeightBase, scale) : 0;
            if (mapMode == EffectiveMapDisplayMode.Compact) expectedH += WidgetScaler.Px(RightHudLayout.CompactMapHeightBase, scale);
            if (mapMode == EffectiveMapDisplayMode.Expanded) expectedH += WidgetScaler.Px(RightHudLayout.ExpandedMapHeightBase, scale);

            Assert.Equal(WidgetScaler.Px(RightHudLayout.ClusterWidthBase, scale), context.Width);
            Assert.Equal(WidgetScaler.Px(RightHudLayout.ToolBarHeightBase, scale), context.Y);
            Assert.Equal(expectedH, context.Height);
        }

        [Fact]
        public void NoticePrecedesExpandedMapInSecondRow()
        {
            Rectangle viewport = new Rectangle(0, 0, 1024, 576);
            float scale = RightHudLayout.ScaleForViewport(viewport);
            Rectangle context = RightHudLayout.ContextPanelRectFromViewport(viewport, scale, EffectiveMapDisplayMode.Expanded, true);
            Rectangle status = RightHudLayout.StatusSlotRectFromContext(context, scale, true);
            Rectangle map = RightHudLayout.MapRectFromContext(context, scale, EffectiveMapDisplayMode.Expanded, true);

            Assert.Equal(context.Top, status.Top);
            Assert.Equal(status.Bottom, map.Top);
            Assert.Equal(WidgetScaler.Px(RightHudLayout.ExpandedMapHeightBase, scale), map.Height);
        }

        [Fact]
        public void MapWithoutNotice_StartsImmediatelyBelowActionRow()
        {
            Rectangle viewport = new Rectangle(0, 0, 1024, 576);
            float scale = RightHudLayout.ScaleForViewport(viewport);
            Rectangle tools = RightHudLayout.TopToolsRectFromViewport(viewport, scale);
            Rectangle context = RightHudLayout.ContextPanelRectFromViewport(
                viewport, scale, EffectiveMapDisplayMode.Expanded, false);
            Rectangle map = RightHudLayout.MapRectFromContext(
                context, scale, EffectiveMapDisplayMode.Expanded, false);
            Rectangle status = RightHudLayout.StatusSlotRectFromContext(context, scale, false);

            Assert.True(status.IsEmpty);
            Assert.Equal(tools.Bottom, map.Top);
            Assert.Equal(context, map);
        }

        [Fact]
        public void SafeExit_UsesSameRightOffset()
        {
            Rectangle viewport = new Rectangle(0, 0, 1024, 576);
            float scale = RightHudLayout.ScaleForViewport(viewport);
            int statusHeight = WidgetScaler.Px(RightHudLayout.StatusSlotHeightBase, scale);
            Rectangle safe = RightHudLayout.SafeExitRectFromViewport(viewport, scale, statusHeight);

            Assert.Equal(WidgetScaler.Px(RightHudLayout.SafeExitTotalWidthBase, scale), safe.Width);
            Assert.Equal(1024 - WidgetScaler.Px(RightHudLayout.RightOffsetBase, scale), safe.Right);
            Assert.Equal(WidgetScaler.Px(RightHudLayout.ToolBarHeightBase, scale), safe.Y);
            Assert.Equal(statusHeight, safe.Height);
            Assert.Equal(RightHudLayout.TopToolsRectFromViewport(viewport, scale).Left, safe.Left);
        }

        [Fact]
        public void DesignWidth_NotchAndRightActionRowKeepTwelvePixelGap()
        {
            Rectangle viewport = new Rectangle(0, 0, 1024, 576);
            float scale = RightHudLayout.ScaleForViewport(viewport);
            Rectangle actions = RightHudLayout.TopToolsRectFromViewport(viewport, scale);
            int notchWidth = RightHudLayout.SafeNotchMaxWidthFromViewport(viewport, scale, 280);
            int notchRight = viewport.Left + (viewport.Width + notchWidth) / 2;

            Assert.Equal(252, actions.Width);
            Assert.Equal(724, actions.Left);
            Assert.Equal(400, notchWidth);
            Assert.True(actions.Left - notchRight >= WidgetScaler.Px(RightHudLayout.NotchRightGapBase, scale));
        }

        [Fact]
        public void ActionRow_UsesWideTextButtonsThenCompactIconButtons()
        {
            Rectangle tools = new Rectangle(724, 0, 252, 32);
            float scale = 1f;

            Assert.Equal(50, RightHudLayout.ActionButtonRectFromTools(tools, scale, 0).Width);
            Assert.Equal(50, RightHudLayout.ActionButtonRectFromTools(tools, scale, 2).Width);
            Assert.Equal(34, RightHudLayout.ActionButtonRectFromTools(tools, scale, 3).Width);
            Assert.Equal(34, RightHudLayout.ActionButtonRectFromTools(tools, scale, 5).Width);
            Assert.Equal(0, RightHudLayout.ActionButtonIndexAt(tools, scale, 724));
            Assert.Equal(2, RightHudLayout.ActionButtonIndexAt(tools, scale, 824));
            Assert.Equal(3, RightHudLayout.ActionButtonIndexAt(tools, scale, 874));
            Assert.Equal(5, RightHudLayout.ActionButtonIndexAt(tools, scale, 975));
        }

        [Theory]
        [InlineData(1024, 576)]
        [InlineData(1600, 900)]
        [InlineData(1920, 1080)]
        public void SafeNotchWidth_NeverCrossesRightActionGap(int width, int height)
        {
            Rectangle viewport = new Rectangle(0, 0, width, height);
            float scale = RightHudLayout.ScaleForViewport(viewport);
            Rectangle actions = RightHudLayout.TopToolsRectFromViewport(viewport, scale);
            int collapsed = WidgetScaler.Px(280, scale);
            int notchWidth = RightHudLayout.SafeNotchMaxWidthFromViewport(viewport, scale, collapsed);
            int notchRight = viewport.Left + (viewport.Width + notchWidth) / 2;

            Assert.True(actions.Left - notchRight >= WidgetScaler.Px(RightHudLayout.NotchRightGapBase, scale));
        }
    }
}
