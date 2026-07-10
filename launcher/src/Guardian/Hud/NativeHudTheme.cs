using System;
using System.Drawing;
using System.Drawing.Drawing2D;

namespace CF7Launcher.Guardian.Hud
{
    /// <summary>
    /// Native HUD 的共享 Flash 白框视觉语言。
    ///
    /// 原则：黑色高密度底、直角发丝结构线、槽内角标；状态色只表达语义，
    /// 不再让每个 widget 各自发明圆角、透明度和边框强度。
    /// </summary>
    internal static class NativeHudTheme
    {
        public const int TopBarHeightBase = 32;
        public const int ToolbarButtonHeightBase = 24;
        // 外层容器与原版物品/技能栏一致使用直角；细节由槽内角标承担。
        public const int CornerCutBase = 0;
        public const int SlotCornerArmBase = 7;

        public static readonly Color PanelFill = Color.FromArgb(224, 7, 9, 11);
        public static readonly Color PanelFillDense = Color.FromArgb(238, 5, 7, 9);
        public static readonly Color PanelFillSoft = Color.FromArgb(204, 12, 14, 16);
        public static readonly Color ButtonFill = Color.FromArgb(218, 13, 15, 17);
        public static readonly Color ButtonHover = Color.FromArgb(235, 46, 48, 50);
        public static readonly Color ButtonPressed = Color.FromArgb(244, 70, 72, 74);
        public static readonly Color ButtonActive = Color.FromArgb(236, 31, 35, 39);

        public static readonly Color FrameStrong = Color.FromArgb(210, 246, 246, 242);
        public static readonly Color FrameNormal = Color.FromArgb(124, 232, 234, 232);
        public static readonly Color FrameMuted = Color.FromArgb(62, 220, 224, 224);
        public static readonly Color PanelFrameStrong = Color.FromArgb(136, 238, 240, 238);
        public static readonly Color PanelFrameMuted = Color.FromArgb(72, 224, 228, 226);
        public static readonly Color FrameHighlight = Color.FromArgb(44, 252, 252, 248);
        public static readonly Color FrameShadow = Color.FromArgb(150, 0, 0, 0);
        public static readonly Color Separator = Color.FromArgb(92, 228, 232, 232);

        public static readonly Color TextPrimary = Color.FromArgb(244, 248, 248, 244);
        public static readonly Color TextSecondary = Color.FromArgb(196, 218, 222, 222);
        public static readonly Color TextDisabled = Color.FromArgb(118, 184, 188, 188);
        public static readonly Color Gold = Color.FromArgb(255, 215, 0);
        public static readonly Color Cyan = Color.FromArgb(102, 204, 255);
        public static readonly Color Danger = Color.FromArgb(255, 102, 102);
        public static readonly Color Success = Color.FromArgb(126, 224, 146);
        public static readonly Color Warning = Color.FromArgb(255, 205, 92);

        internal static int Px(int basePx, float scale)
        {
            return Math.Max(1, (int)Math.Round(basePx * Math.Max(0.5f, scale)));
        }

        internal static int StrokePx(float scale)
        {
            // 原版技能/物品槽的结构线接近 device-pixel hairline；常见 1.0～1.875x
            // viewport 下始终保持 1px，只在超高缩放时进到 2px，避免 1600×900 出现粗重双框。
            return Math.Max(1, (int)Math.Round(Math.Max(0.5f, scale) * 0.60f));
        }

        internal static int CornerCutPx(float scale)
        {
            return CornerCutBase <= 0 ? 0 : Px(CornerCutBase, scale);
        }

        internal static GraphicsPath CreateCutCornerPath(Rectangle rect, int cut)
        {
            GraphicsPath path = new GraphicsPath();
            if (rect.Width <= 0 || rect.Height <= 0) return path;
            int c = Math.Max(0, Math.Min(cut, Math.Min(rect.Width, rect.Height) / 2));
            if (c <= 0)
            {
                path.AddRectangle(rect);
                return path;
            }
            path.StartFigure();
            path.AddLine(rect.Left + c, rect.Top, rect.Right - c, rect.Top);
            path.AddLine(rect.Right - c, rect.Top, rect.Right, rect.Top + c);
            path.AddLine(rect.Right, rect.Top + c, rect.Right, rect.Bottom - c);
            path.AddLine(rect.Right, rect.Bottom - c, rect.Right - c, rect.Bottom);
            path.AddLine(rect.Right - c, rect.Bottom, rect.Left + c, rect.Bottom);
            path.AddLine(rect.Left + c, rect.Bottom, rect.Left, rect.Bottom - c);
            path.AddLine(rect.Left, rect.Bottom - c, rect.Left, rect.Top + c);
            path.AddLine(rect.Left, rect.Top + c, rect.Left + c, rect.Top);
            path.CloseFigure();
            return path;
        }

        internal static void DrawPanel(Graphics g, Rectangle rect, float scale, Color fill)
        {
            DrawPanel(g, rect, scale, fill, Color.Empty, true);
        }

        internal static void DrawPanel(Graphics g, Rectangle rect, float scale, Color fill, Color accent, bool strongFrame)
        {
            if (g == null || rect.Width <= 1 || rect.Height <= 1) return;
            int stroke = StrokePx(scale);
            int inset = Math.Max(0, stroke / 2);
            Rectangle outer = new Rectangle(
                rect.X + inset,
                rect.Y + inset,
                Math.Max(1, rect.Width - stroke),
                Math.Max(1, rect.Height - stroke));
            int cut = CornerCutPx(scale);
            GraphicsState state = g.Save();
            try
            {
                // 结构线禁用抗锯齿，保留 Flash 栅格 UI 的利落像素边，不污染后续文本设置。
                g.SmoothingMode = SmoothingMode.None;
                using (GraphicsPath path = CreateCutCornerPath(outer, cut))
                using (SolidBrush bg = new SolidBrush(fill))
                using (Pen frame = new Pen(strongFrame ? PanelFrameStrong : PanelFrameMuted, stroke))
                {
                    g.FillPath(bg, path);
                    g.DrawPath(frame, path);
                }

                DrawCornerBrackets(g, outer, scale,
                    strongFrame ? FrameNormal : FrameMuted, stroke + 3);

                if (accent != Color.Empty)
                {
                    int railTop = outer.Top + cut;
                    int railBottom = outer.Bottom - cut;
                    int accentArm = Math.Min(Px(18, scale), Math.Max(2, outer.Width / 3));
                    using (Pen accentPen = new Pen(WithAlpha(accent, 210), stroke))
                    {
                        if (railBottom > railTop)
                            g.DrawLine(accentPen, outer.Left, railTop, outer.Left, railBottom);
                        g.DrawLine(accentPen, outer.Left + cut, outer.Top,
                            Math.Min(outer.Right - cut, outer.Left + cut + accentArm), outer.Top);
                    }
                }
            }
            finally { g.Restore(state); }
        }

        internal static void DrawButton(Graphics g, Rectangle rect, float scale,
            bool hover, bool pressed, bool active, bool danger)
        {
            if (g == null || rect.Width <= 0 || rect.Height <= 0) return;
            Color fill = pressed ? ButtonPressed : (hover ? ButtonHover : (active ? ButtonActive : ButtonFill));
            // hover/pressed 不再把整圈提成高亮粗框；底色与内部角标承担状态反馈。
            Color frame = hover || pressed || active ? FrameNormal : FrameMuted;
            if (danger && (hover || active)) fill = Color.FromArgb(238, 68, 18, 22);
            if (danger && hover) frame = WithAlpha(Danger, 150);
            int stroke = StrokePx(scale);
            int inset = Math.Max(0, stroke / 2);
            Rectangle rr = new Rectangle(rect.X + inset, rect.Y + inset,
                Math.Max(1, rect.Width - stroke), Math.Max(1, rect.Height - stroke));
            GraphicsState state = g.Save();
            try
            {
                g.SmoothingMode = SmoothingMode.None;
                using (SolidBrush bg = new SolidBrush(fill))
                using (Pen border = new Pen(frame, stroke))
                {
                    g.FillRectangle(bg, rr);
                    g.DrawRectangle(border, rr.X, rr.Y, Math.Max(0, rr.Width - 1), Math.Max(0, rr.Height - 1));
                }

                DrawInsetBevel(g, rr, 0);
                Color bracket = hover || pressed ? FrameStrong : (active ? FrameNormal : WithAlpha(FrameNormal, 86));
                DrawCornerBrackets(g, rr, scale, bracket, stroke + 2);

                if (active)
                {
                    Color activeAccent = danger ? Danger : FrameStrong;
                    int arm = Math.Min(Px(18, scale), Math.Max(2, rr.Width / 2));
                    using (Pen p = new Pen(activeAccent, stroke))
                        g.DrawLine(p, rr.Left + 2, rr.Bottom - 1,
                            Math.Min(rr.Right - 2, rr.Left + 2 + arm), rr.Bottom - 1);
                }
            }
            finally { g.Restore(state); }
        }

        internal static void DrawSeparator(Graphics g, int x, int top, int bottom, float scale)
        {
            if (g == null || bottom <= top) return;
            using (Pen p = new Pen(Separator, StrokePx(scale)))
                g.DrawLine(p, x, top, x, bottom);
        }

        private static void DrawInsetBevel(Graphics g, Rectangle rect, int cut)
        {
            if (rect.Width <= 7 || rect.Height <= 7) return;
            // 与外框隔开 1px，避免两条相邻亮线被读成 2px 粗边。
            int left = rect.Left + 2;
            int top = rect.Top + 2;
            int right = rect.Right - 3;
            int bottom = rect.Bottom - 3;
            int corner = Math.Max(0, cut - 1);
            using (Pen light = new Pen(FrameHighlight, 1f))
            using (Pen shadow = new Pen(FrameShadow, 1f))
            {
                if (right - left > corner * 2)
                {
                    g.DrawLine(light, left + corner, top, right - corner, top);
                    g.DrawLine(shadow, left + corner, bottom, right - corner, bottom);
                }
                if (bottom - top > corner * 2)
                {
                    g.DrawLine(light, left, top + corner, left, bottom - corner);
                    g.DrawLine(shadow, right, top + corner, right, bottom - corner);
                }
            }
        }

        private static void DrawCornerBrackets(Graphics g, Rectangle rect, float scale, Color color, int inset)
        {
            int left = rect.Left + inset;
            int top = rect.Top + inset;
            int right = rect.Right - inset - 1;
            int bottom = rect.Bottom - inset - 1;
            if (right <= left || bottom <= top) return;
            int arm = Math.Min(Px(SlotCornerArmBase, scale), Math.Min(right - left, bottom - top) / 2);
            if (arm < 2) return;
            using (Pen p = new Pen(color, 1f))
            {
                g.DrawLine(p, left, top, left + arm, top);
                g.DrawLine(p, left, top, left, top + arm);
                g.DrawLine(p, right - arm, bottom, right, bottom);
                g.DrawLine(p, right, bottom - arm, right, bottom);
            }
        }

        internal static Color WithAlpha(Color color, int alpha)
        {
            return Color.FromArgb(Math.Max(0, Math.Min(255, alpha)), color.R, color.G, color.B);
        }

        internal static Color Blend(Color baseColor, Color tint, float amount, int alpha)
        {
            float t = Math.Max(0f, Math.Min(1f, amount));
            int r = (int)Math.Round(baseColor.R + (tint.R - baseColor.R) * t);
            int g = (int)Math.Round(baseColor.G + (tint.G - baseColor.G) * t);
            int b = (int)Math.Round(baseColor.B + (tint.B - baseColor.B) * t);
            return Color.FromArgb(Math.Max(0, Math.Min(255, alpha)), r, g, b);
        }
    }
}
