using System;
using System.Drawing;
using System.Windows.Forms;
using CF7Launcher.Guardian;

namespace CF7Launcher.Guardian.Hud
{
    /// <summary>
    /// 右上角常驻 HUD 的共享布局模型。
    ///
    /// 这些数值复刻 web overlay.css / notch.js 的右侧 cluster 常量：
    /// right:80px, width:170px, tool unit:34px, toolbar:32px,
    /// map:86px, quest row:32px, notice:32px, jukebox titlebar:24px。
    /// </summary>
    public static class RightHudLayout
    {
        public const int RightOffsetBase = 80;
        public const int ClusterWidthBase = 170;
        public const int ToolButtonWidthBase = 34;
        public const int ToolButtonCount = 5;
        public const int ToolBarHeightBase = 32;
        public const int MapHeightBase = 86;
        public const int QuestRowHeightBase = 32;
        public const int QuestNoticeHeightBase = 32;
        public const int JukeboxHeightBase = 24;

        public const int SafeExitContentWidthBase = 120;
        public const int SafeExitPaddingXBase = 10;
        public const int SafeExitPaddingYBase = 8;
        public const int SafeExitTotalWidthBase = SafeExitContentWidthBase + SafeExitPaddingXBase * 2;

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

        public static Rectangle GetTopToolsRect(Control anchor, FlashCoordinateMapper mapper)
        {
            Rectangle viewport = GetViewportRect(anchor, mapper);
            return TopToolsRectFromViewport(viewport, ScaleForViewport(viewport));
        }

        public static Rectangle GetContextPanelRect(Control anchor, FlashCoordinateMapper mapper, bool showMap, bool showNotice)
        {
            Rectangle viewport = GetViewportRect(anchor, mapper);
            return ContextPanelRectFromViewport(viewport, ScaleForViewport(viewport), showMap, showNotice);
        }

        public static Rectangle GetMapRect(Control anchor, FlashCoordinateMapper mapper, bool showMap, bool showNotice)
        {
            Rectangle context = GetContextPanelRect(anchor, mapper, showMap, showNotice);
            Rectangle viewport = GetViewportRect(anchor, mapper);
            return MapRectFromContext(context, ScaleForViewport(viewport), showMap);
        }

        public static Rectangle GetQuestRowRect(Control anchor, FlashCoordinateMapper mapper, bool showMap, bool showNotice)
        {
            Rectangle context = GetContextPanelRect(anchor, mapper, showMap, showNotice);
            Rectangle viewport = GetViewportRect(anchor, mapper);
            return QuestRowRectFromContext(context, ScaleForViewport(viewport), showMap);
        }

        public static Rectangle GetQuestNoticeRect(Control anchor, FlashCoordinateMapper mapper, bool showMap, bool showNotice)
        {
            Rectangle context = GetContextPanelRect(anchor, mapper, showMap, showNotice);
            Rectangle viewport = GetViewportRect(anchor, mapper);
            return QuestNoticeRectFromContext(context, ScaleForViewport(viewport), showMap, showNotice);
        }

        public static Rectangle GetJukeboxRect(Control anchor, FlashCoordinateMapper mapper, bool showMap, bool showNotice)
        {
            Rectangle viewport = GetViewportRect(anchor, mapper);
            return JukeboxRectFromViewport(viewport, ScaleForViewport(viewport), showMap, showNotice);
        }

        public static Rectangle GetClusterRect(Control anchor, FlashCoordinateMapper mapper, bool showMap, bool showNotice, bool showJukebox)
        {
            Rectangle viewport = GetViewportRect(anchor, mapper);
            return ClusterRectFromViewport(viewport, ScaleForViewport(viewport), showMap, showNotice, showJukebox);
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

        internal static Rectangle ContextPanelRectFromViewport(Rectangle viewport, float scale, bool showMap, bool showNotice)
        {
            Rectangle tools = TopToolsRectFromViewport(viewport, scale);
            if (tools.Width <= 0 || tools.Height <= 0) return Rectangle.Empty;
            int h = WidgetScaler.Px(QuestRowHeightBase, scale);
            if (showMap) h += WidgetScaler.Px(MapHeightBase, scale);
            if (showNotice) h += WidgetScaler.Px(QuestNoticeHeightBase, scale);
            return new Rectangle(tools.X, tools.Bottom, tools.Width, h);
        }

        internal static Rectangle MapRectFromContext(Rectangle context, float scale, bool showMap)
        {
            if (!showMap || context.Width <= 0 || context.Height <= 0) return Rectangle.Empty;
            return new Rectangle(context.X, context.Y, context.Width, WidgetScaler.Px(MapHeightBase, scale));
        }

        internal static Rectangle QuestRowRectFromContext(Rectangle context, float scale, bool showMap)
        {
            if (context.Width <= 0 || context.Height <= 0) return Rectangle.Empty;
            int y = context.Y + (showMap ? WidgetScaler.Px(MapHeightBase, scale) : 0);
            return new Rectangle(context.X, y, context.Width, WidgetScaler.Px(QuestRowHeightBase, scale));
        }

        internal static Rectangle QuestNoticeRectFromContext(Rectangle context, float scale, bool showMap, bool showNotice)
        {
            if (!showNotice || context.Width <= 0 || context.Height <= 0) return Rectangle.Empty;
            Rectangle row = QuestRowRectFromContext(context, scale, showMap);
            return new Rectangle(context.X, row.Bottom, context.Width, WidgetScaler.Px(QuestNoticeHeightBase, scale));
        }

        internal static Rectangle JukeboxRectFromViewport(Rectangle viewport, float scale, bool showMap, bool showNotice)
        {
            Rectangle context = ContextPanelRectFromViewport(viewport, scale, showMap, showNotice);
            if (context.Width <= 0 || context.Height <= 0) return Rectangle.Empty;
            return new Rectangle(context.X, context.Bottom, context.Width, WidgetScaler.Px(JukeboxHeightBase, scale));
        }

        internal static Rectangle ClusterRectFromViewport(Rectangle viewport, float scale, bool showMap, bool showNotice, bool showJukebox)
        {
            Rectangle tools = TopToolsRectFromViewport(viewport, scale);
            if (tools.Width <= 0 || tools.Height <= 0) return Rectangle.Empty;
            Rectangle context = ContextPanelRectFromViewport(viewport, scale, showMap, showNotice);
            Rectangle union = Rectangle.Union(tools, context);
            if (showJukebox)
            {
                Rectangle jukebox = JukeboxRectFromViewport(viewport, scale, showMap, showNotice);
                if (jukebox.Width > 0 && jukebox.Height > 0) union = Rectangle.Union(union, jukebox);
            }
            return union;
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
