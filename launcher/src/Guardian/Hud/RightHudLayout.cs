using System;
using System.Drawing;
using System.Windows.Forms;
using CF7Launcher.Guardian;

namespace CF7Launcher.Guardian.Hud
{
    /// <summary>
    /// 右上角常驻 HUD 的共享布局模型。
    ///
    /// Native HUD 右侧动作行与居中刘海共用的几何契约。
    /// 右侧保留 right:48px；前三个双字入口各 50px、后三个图标入口各 34px，总宽 252px；
    /// 刘海与动作行之间至少保留 12px。所有值均以 1024×576 设计坐标为基准。
    /// </summary>
    public static class RightHudLayout
    {
        public const int RightOffsetBase = 48;
        public const int RightActionButtonCount = 6;
        public const int PrimaryActionButtonCount = 3;
        public const int PrimaryActionButtonWidthBase = 50;
        public const int UtilityActionButtonWidthBase = 34;
        public const int RightActionRowWidthBase =
            PrimaryActionButtonCount * PrimaryActionButtonWidthBase
            + (RightActionButtonCount - PrimaryActionButtonCount) * UtilityActionButtonWidthBase;
        public const int ClusterWidthBase = RightActionRowWidthBase;
        public const int ToolButtonCount = RightActionButtonCount;
        public const int ToolBarHeightBase = NativeHudTheme.TopBarHeightBase;
        public const int NotchRightGapBase = 12;
        public const int PreferredNotchMaxWidthBase = 400;
        public const int CompactMapHeightBase = 64;
        public const int ExpandedMapHeightBase = 112;
        public const int StatusSlotHeightBase = 32;

        public const int SafeExitContentWidthBase = RightActionRowWidthBase - SafeExitPaddingXBase * 2;
        public const int SafeExitPaddingXBase = 10;
        public const int SafeExitPaddingYBase = 8;
        public const int SafeExitTotalWidthBase = RightActionRowWidthBase;

        public static float ScaleForViewport(Rectangle viewport)
        {
            if (viewport.Height <= 0) return 1f;
            return Math.Max(WidgetScaler.MIN_SCALE, viewport.Height / WidgetScaler.DESIGN_HEIGHT);
        }

        public static Rectangle GetViewportRect(Control anchor, FlashCoordinateMapper mapper)
        {
            if (anchor == null || mapper == null) return Rectangle.Empty;
            try
            {
                Point origin = anchor.PointToScreen(Point.Empty);
                float vpX, vpY, vpW, vpH;
                mapper.CalcViewport(out vpX, out vpY, out vpW, out vpH);
                return new Rectangle(
                    origin.X + (int)vpX,
                    origin.Y + (int)vpY,
                    Math.Max(0, (int)vpW),
                    Math.Max(0, (int)vpH));
            }
            catch { return Rectangle.Empty; }
        }

        internal static Rectangle ViewportFromPanelSize(int width, int height)
        {
            if (width <= 0 || height <= 0) return Rectangle.Empty;
            float stageAspect = 1024f / 576f;
            float panelAspect = (float)width / height;
            float vpX, vpY, vpW, vpH;
            if (panelAspect > stageAspect)
            {
                vpH = height;
                vpW = height * stageAspect;
                vpX = (width - vpW) / 2f;
                vpY = 0;
            }
            else
            {
                vpW = width;
                vpH = width / stageAspect;
                vpX = 0;
                vpY = (height - vpH) / 2f;
            }
            return new Rectangle((int)vpX, (int)vpY, (int)vpW, (int)vpH);
        }

        /// <summary>
        /// 计算居中刘海在不侵入右侧动作行最小间隙时的最大宽度。
        /// safe = 2 × (rightRowLeft - gap - viewportCenterX)，再与首选 400px clamp。
        /// 极窄视口下至少返回 collapsedWidth；调用方可据此切换响应式降级布局。
        /// </summary>
        internal static int SafeNotchMaxWidthFromViewport(Rectangle viewport, float scale, int collapsedWidth)
        {
            int collapsed = Math.Max(1, collapsedWidth);
            if (viewport.Width <= 0 || viewport.Height <= 0) return collapsed;
            int rightOffset = WidgetScaler.Px(RightOffsetBase, scale);
            int actionWidth = WidgetScaler.Px(RightActionRowWidthBase, scale);
            int gap = WidgetScaler.Px(NotchRightGapBase, scale);
            int rightRowLeft = viewport.Right - rightOffset - actionWidth;
            double centerX = viewport.Left + viewport.Width / 2.0;
            int safe = (int)Math.Floor(2.0 * (rightRowLeft - gap - centerX));
            int preferred = WidgetScaler.Px(PreferredNotchMaxWidthBase, scale);
            if (safe < collapsed) return collapsed;
            return Math.Max(collapsed, Math.Min(preferred, safe));
        }

        public static Rectangle GetTopToolsRect(Control anchor, FlashCoordinateMapper mapper)
        {
            Rectangle viewport = GetViewportRect(anchor, mapper);
            return TopToolsRectFromViewport(viewport, ScaleForViewport(viewport));
        }

        public static Rectangle GetContextPanelRect(Control anchor, FlashCoordinateMapper mapper, EffectiveMapDisplayMode mapMode, bool showNotice)
        {
            Rectangle viewport = GetViewportRect(anchor, mapper);
            return ContextPanelRectFromViewport(viewport, ScaleForViewport(viewport), mapMode, showNotice);
        }

        public static Rectangle GetMapRect(Control anchor, FlashCoordinateMapper mapper, EffectiveMapDisplayMode mapMode, bool showNotice)
        {
            Rectangle context = GetContextPanelRect(anchor, mapper, mapMode, showNotice);
            Rectangle viewport = GetViewportRect(anchor, mapper);
            return MapRectFromContext(context, ScaleForViewport(viewport), mapMode, showNotice);
        }

        public static Rectangle GetStatusSlotRect(Control anchor, FlashCoordinateMapper mapper, EffectiveMapDisplayMode mapMode, bool showNotice)
        {
            Rectangle context = GetContextPanelRect(anchor, mapper, mapMode, showNotice);
            Rectangle viewport = GetViewportRect(anchor, mapper);
            return StatusSlotRectFromContext(context, ScaleForViewport(viewport), showNotice);
        }

        public static Rectangle GetClusterRect(Control anchor, FlashCoordinateMapper mapper, EffectiveMapDisplayMode mapMode, bool showNotice)
        {
            Rectangle viewport = GetViewportRect(anchor, mapper);
            return ClusterRectFromViewport(viewport, ScaleForViewport(viewport), mapMode, showNotice);
        }

        public static Rectangle GetSafeExitRect(Control anchor, FlashCoordinateMapper mapper, int totalHeight)
        {
            Rectangle viewport = GetViewportRect(anchor, mapper);
            return SafeExitRectFromViewport(viewport, ScaleForViewport(viewport), totalHeight);
        }

        internal static Rectangle TopToolsRectFromViewport(Rectangle viewport, float scale)
        {
            if (viewport.Width <= 0 || viewport.Height <= 0) return Rectangle.Empty;
            int w = WidgetScaler.Px(ClusterWidthBase, scale);
            int h = WidgetScaler.Px(ToolBarHeightBase, scale);
            int rightOffset = WidgetScaler.Px(RightOffsetBase, scale);
            int x = viewport.X + Math.Max(0, viewport.Width - w - rightOffset);
            return new Rectangle(x, viewport.Y, w, h);
        }

        internal static int ActionButtonWidth(float scale, int index)
        {
            int baseWidth = index < PrimaryActionButtonCount
                ? PrimaryActionButtonWidthBase
                : UtilityActionButtonWidthBase;
            return WidgetScaler.Px(baseWidth, scale);
        }

        internal static Rectangle ActionButtonRectFromTools(Rectangle tools, float scale, int index)
        {
            if (tools.Width <= 0 || tools.Height <= 0 || index < 0 || index >= RightActionButtonCount)
                return Rectangle.Empty;
            int x = tools.X;
            for (int i = 0; i < index; i++) x += ActionButtonWidth(scale, i);
            int w = index == RightActionButtonCount - 1
                ? Math.Max(1, tools.Right - x)
                : ActionButtonWidth(scale, index);
            return new Rectangle(x, tools.Y, w, tools.Height);
        }

        internal static int ActionButtonIndexAt(Rectangle tools, float scale, int screenX)
        {
            if (screenX < tools.Left || screenX >= tools.Right) return -1;
            for (int i = 0; i < RightActionButtonCount; i++)
            {
                if (ActionButtonRectFromTools(tools, scale, i).Contains(screenX, tools.Top)) return i;
            }
            return -1;
        }

        internal static Rectangle ContextPanelRectFromViewport(Rectangle viewport, float scale, EffectiveMapDisplayMode mapMode, bool showNotice)
        {
            Rectangle tools = TopToolsRectFromViewport(viewport, scale);
            if (tools.Width <= 0 || tools.Height <= 0) return Rectangle.Empty;
            int h = 0;
            if (showNotice) h += WidgetScaler.Px(StatusSlotHeightBase, scale);
            if (mapMode == EffectiveMapDisplayMode.Compact)
                h += WidgetScaler.Px(CompactMapHeightBase, scale);
            else if (mapMode == EffectiveMapDisplayMode.Expanded)
                h += WidgetScaler.Px(ExpandedMapHeightBase, scale);
            if (h <= 0) return Rectangle.Empty;
            return new Rectangle(tools.X, tools.Bottom, tools.Width, h);
        }

        internal static Rectangle MapRectFromContext(Rectangle context, float scale, EffectiveMapDisplayMode mapMode, bool showNotice)
        {
            if (mapMode == EffectiveMapDisplayMode.Hidden || context.Width <= 0 || context.Height <= 0) return Rectangle.Empty;
            int y = context.Y + (showNotice ? WidgetScaler.Px(StatusSlotHeightBase, scale) : 0);
            int h = WidgetScaler.Px(
                mapMode == EffectiveMapDisplayMode.Expanded ? ExpandedMapHeightBase : CompactMapHeightBase,
                scale);
            return new Rectangle(context.X, y, context.Width, h);
        }

        internal static Rectangle StatusSlotRectFromContext(Rectangle context, float scale, bool showNotice)
        {
            if (!showNotice || context.Width <= 0 || context.Height <= 0) return Rectangle.Empty;
            return new Rectangle(context.X, context.Y, context.Width, WidgetScaler.Px(StatusSlotHeightBase, scale));
        }

        internal static Rectangle ClusterRectFromViewport(Rectangle viewport, float scale, EffectiveMapDisplayMode mapMode, bool showNotice)
        {
            Rectangle tools = TopToolsRectFromViewport(viewport, scale);
            if (tools.Width <= 0 || tools.Height <= 0) return Rectangle.Empty;
            Rectangle context = ContextPanelRectFromViewport(viewport, scale, mapMode, showNotice);
            return context.Width > 0 && context.Height > 0 ? Rectangle.Union(tools, context) : tools;
        }

        internal static Rectangle SafeExitRectFromViewport(Rectangle viewport, float scale, int totalHeight)
        {
            if (viewport.Width <= 0 || viewport.Height <= 0 || totalHeight <= 0) return Rectangle.Empty;
            int w = WidgetScaler.Px(SafeExitTotalWidthBase, scale);
            int rightOffset = WidgetScaler.Px(RightOffsetBase, scale);
            int x = viewport.X + Math.Max(0, viewport.Width - w - rightOffset);
            int y = viewport.Y + WidgetScaler.Px(ToolBarHeightBase, scale);
            return new Rectangle(x, y, w, totalHeight);
        }
    }
}
