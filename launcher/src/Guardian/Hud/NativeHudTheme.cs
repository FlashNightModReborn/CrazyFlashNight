using System;
using System.Drawing;
using System.Drawing.Drawing2D;

namespace CF7Launcher.Guardian.Hud
{
    /// <summary>
    /// Native HUD 的共享视觉语言 v2：以底部玩家信息界面（PlayerInfo SVG 原稿）为唯一锚点。
    ///
    /// 依据 docs/上层HUD风格锚定与分区仲裁-ADR-2026-11-05.md（D1–D3）：
    /// 切角双层金属板（银色描边 + 炭黑渐变 + 顶部高光/底部压暗）、技能槽式四角角标、
    /// 12.5° 斜切标签与分隔线、`////` 斜纹装饰；状态色只表达语义。
    /// 上层组件只调用本类原语，不各自发明渐变与边框。
    ///
    /// 07-10 白框语言保留为 <c>DrawLegacy*</c>，仅供本轮范围外的 NPC 菜单继续使用。
    /// </summary>
    internal static class NativeHudTheme
    {
        public const int TopBarHeightBase = 32;
        public const int ToolbarButtonHeightBase = 24;
        // v2 外框采用锚点切角；CornerCutBase 仍为 0，仅供 Combo 旧路径的直角裁切 path 使用。
        public const int CornerCutBase = 0;
        public const int SlotCornerArmBase = 7;

        /// <summary>锚点斜切角 12.5°（mp/rim.svg 分隔线与 skill-label 字形竖笔）的正切值。</summary>
        public const float SlantTan = 0.2217f;
        public const int PlateChamferBase = 7;
        public const int ButtonChamferBase = 4;
        public const int NotchChamferBase = 10;

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

        // ---- v2 锚点 token（ADR D2） ----
        public static readonly Color AnchorRim = Color.FromArgb(232, 214, 217, 215);
        public static readonly Color AnchorRimMuted = Color.FromArgb(168, 150, 154, 152);
        public static readonly Color AnchorRimFaint = Color.FromArgb(96, 150, 154, 152);
        public static readonly Color AnchorCyan = Color.FromArgb(255, 0x5E, 0xEF, 0xFB);
        public static readonly Color AnchorAmber = Color.FromArgb(255, 241, 201, 112);
        public static readonly Color AnchorCoral = Color.FromArgb(255, 255, 102, 86);
        public static readonly Color AnchorTagFill = Color.FromArgb(240, 5, 6, 6);

        [Flags]
        internal enum PlateCorners
        {
            None = 0,
            TopLeft = 1,
            TopRight = 2,
            BottomRight = 4,
            BottomLeft = 8,
        }

        internal static int Px(int basePx, float scale)
        {
            return Math.Max(1, (int)Math.Round(basePx * Math.Max(0.5f, scale)));
        }

        internal static int StrokePx(float scale)
        {
            // 结构线接近 device-pixel hairline；常见 1.0～1.875x viewport 保持 1px，超高缩放才进 2px。
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

        /// <summary>按角掩码生成切角板轮廓（浮点，半像素对齐由调用方决定）。</summary>
        internal static GraphicsPath CreatePlatePath(RectangleF r, float cut, PlateCorners corners)
        {
            GraphicsPath path = new GraphicsPath();
            if (r.Width <= 0 || r.Height <= 0) return path;
            float c = Math.Max(0f, Math.Min(cut, Math.Min(r.Width, r.Height) / 2f));
            float tl = (corners & PlateCorners.TopLeft) != 0 ? c : 0f;
            float tr = (corners & PlateCorners.TopRight) != 0 ? c : 0f;
            float br = (corners & PlateCorners.BottomRight) != 0 ? c : 0f;
            float bl = (corners & PlateCorners.BottomLeft) != 0 ? c : 0f;
            var pts = new System.Collections.Generic.List<PointF>(8);
            pts.Add(new PointF(r.Left + tl, r.Top));
            pts.Add(new PointF(r.Right - tr, r.Top));
            if (tr > 0) pts.Add(new PointF(r.Right, r.Top + tr));
            pts.Add(new PointF(r.Right, r.Bottom - br));
            if (br > 0) pts.Add(new PointF(r.Right - br, r.Bottom));
            pts.Add(new PointF(r.Left + bl, r.Bottom));
            if (bl > 0) pts.Add(new PointF(r.Left, r.Bottom - bl));
            pts.Add(new PointF(r.Left, r.Top + tl));
            path.AddPolygon(pts.ToArray());
            return path;
        }

        /// <summary>
        /// 锚点切角双层金属板。fill 决定基色（保留调用方的语义染色），
        /// 由其派生上亮下暗的纵向渐变；rim 为外框，顶部内高光与底部压暗模拟原稿定向明暗边。
        /// alpha 统一乘到所有层（供淡入淡出卡片使用）。
        /// </summary>
        internal static void DrawPlate(Graphics g, Rectangle rect, float scale, Color fill, Color rim,
            PlateCorners corners, int chamferBase, float alpha = 1f)
        {
            if (g == null || rect.Width <= 2 || rect.Height <= 2) return;
            float a = Math.Max(0f, Math.Min(1f, alpha));
            if (a <= 0.003f) return;
            float cut = Math.Min(Px(chamferBase, scale), Math.Max(0, Math.Min(rect.Width, rect.Height) / 3));
            if (chamferBase <= 0) cut = 0f;
            RectangleF outer = new RectangleF(rect.X + 0.5f, rect.Y + 0.5f, rect.Width - 1f, rect.Height - 1f);
            GraphicsState state = g.Save();
            try
            {
                g.SmoothingMode = SmoothingMode.AntiAlias;
                g.PixelOffsetMode = PixelOffsetMode.Default;
                Color top = Blend(fill, Color.White, 0.13f, Scale(fill.A, a));
                Color bottom = Blend(fill, Color.Black, 0.42f, Scale(Math.Min(255, fill.A + 10), a));
                using (GraphicsPath path = CreatePlatePath(outer, cut, corners))
                {
                    RectangleF gradRect = new RectangleF(rect.X, rect.Y - 1, Math.Max(1, rect.Width), rect.Height + 2);
                    using (LinearGradientBrush bg = new LinearGradientBrush(gradRect, top, bottom, LinearGradientMode.Vertical))
                    {
                        bg.Blend = new Blend { Positions = new[] { 0f, 0.78f, 1f }, Factors = new[] { 0f, 1f, 1f } };
                        g.FillPath(bg, path);
                    }
                    if (rim.A > 0)
                    {
                        using (Pen frame = new Pen(Color.FromArgb(Scale(rim.A, a), rim), StrokePx(scale)))
                        {
                            frame.LineJoin = LineJoin.Miter;
                            g.DrawPath(frame, path);
                        }
                    }
                }
                if (rect.Height >= 8 && rect.Width >= 8)
                {
                    float tl = (corners & PlateCorners.TopLeft) != 0 ? cut : 0f;
                    float tr = (corners & PlateCorners.TopRight) != 0 ? cut : 0f;
                    float bl = (corners & PlateCorners.BottomLeft) != 0 ? cut : 0f;
                    float br = (corners & PlateCorners.BottomRight) != 0 ? cut : 0f;
                    using (Pen hi = new Pen(Color.FromArgb(Scale(54, a), 255, 255, 255), 1f))
                        g.DrawLine(hi, outer.Left + 1.5f + tl, outer.Top + 1.5f, outer.Right - 1.5f - tr, outer.Top + 1.5f);
                    using (Pen lo = new Pen(Color.FromArgb(Scale(150, a), 0, 0, 0), 1f))
                        g.DrawLine(lo, outer.Left + 1.5f + bl, outer.Bottom - 1.5f, outer.Right - 1.5f - br, outer.Bottom - 1.5f);
                }
            }
            finally { g.Restore(state); }
        }

        internal static void DrawPanel(Graphics g, Rectangle rect, float scale, Color fill)
        {
            DrawPanel(g, rect, scale, fill, Color.Empty, true);
        }

        /// <summary>v2 面板：右上切角金属板；accent 以左侧 2px 语义轨表达，不再整圈染色。</summary>
        internal static void DrawPanel(Graphics g, Rectangle rect, float scale, Color fill, Color accent, bool strongFrame)
        {
            if (g == null || rect.Width <= 1 || rect.Height <= 1) return;
            DrawPlate(g, rect, scale, fill, strongFrame ? AnchorRim : AnchorRimMuted,
                PlateCorners.TopRight, PlateChamferBase);
            if (accent != Color.Empty && rect.Height > 6)
            {
                int railW = Math.Max(2, Px(2, scale));
                int inset = StrokePx(scale) + 1;
                using (SolidBrush rail = new SolidBrush(WithAlpha(accent, Math.Min(230, Math.Max((int)accent.A, 200)))))
                    g.FillRectangle(rail, rect.X + inset, rect.Y + inset, railW, Math.Max(1, rect.Height - inset * 2));
            }
        }

        /// <summary>v2 按钮：小切角板 + 技能槽四角角标；激活态底部锚点青色短轨，危险态红底。</summary>
        internal static void DrawButton(Graphics g, Rectangle rect, float scale,
            bool hover, bool pressed, bool active, bool danger)
        {
            if (g == null || rect.Width <= 0 || rect.Height <= 0) return;
            Color fill = pressed ? ButtonPressed : (hover ? ButtonHover : (active ? ButtonActive : ButtonFill));
            Color rim = hover || pressed || active ? AnchorRim : AnchorRimMuted;
            if (danger && (hover || active)) fill = Color.FromArgb(238, 68, 18, 22);
            if (danger && hover) rim = WithAlpha(Danger, 190);
            DrawPlate(g, rect, scale, fill, rim, PlateCorners.TopRight, ButtonChamferBase);
            Color bracket = hover || pressed ? FrameStrong : (active ? FrameNormal : WithAlpha(FrameNormal, 80));
            int inset = StrokePx(scale) + 2;
            DrawSlotBrackets(g, RectangleF.FromLTRB(rect.Left + inset, rect.Top + inset, rect.Right - inset - 1, rect.Bottom - inset - 1),
                bracket, Px(5, scale));
            if (active)
            {
                Color activeAccent = danger ? Danger : AnchorCyan;
                int arm = Math.Min(Px(18, scale), Math.Max(2, rect.Width / 2));
                int barH = Math.Max(2, Px(2, scale));
                int x0 = rect.Left + (rect.Width - arm) / 2;
                using (SolidBrush b = new SolidBrush(activeAccent))
                    g.FillRectangle(b, x0, rect.Bottom - barH - StrokePx(scale) - 1, arm, barH);
            }
        }

        /// <summary>v2 分隔线：沿锚点 12.5° 斜切。</summary>
        internal static void DrawSeparator(Graphics g, int x, int top, int bottom, float scale)
        {
            if (g == null || bottom <= top) return;
            DrawSlantLine(g, x, top, bottom, Separator, StrokePx(scale));
        }

        internal static void DrawSlantLine(Graphics g, float x, float top, float bottom, Color color, float width)
        {
            if (g == null || bottom <= top) return;
            float dx = (bottom - top) * SlantTan / 2f;
            GraphicsState state = g.Save();
            try
            {
                g.SmoothingMode = SmoothingMode.AntiAlias;
                using (Pen p = new Pen(color, width))
                    g.DrawLine(p, x + dx, top, x - dx, bottom);
            }
            finally { g.Restore(state); }
        }

        /// <summary>
        /// 锚点斜切标签（取自 SP. 铭牌）：平行四边形底 + 细框；返回内容矩形供调用方居中绘字。
        /// </summary>
        internal static RectangleF DrawSlantTag(Graphics g, RectangleF r, Color fill, Color border, float alpha = 1f)
        {
            if (g == null || r.Width <= 2 || r.Height <= 2) return r;
            float a = Math.Max(0f, Math.Min(1f, alpha));
            float s = r.Height * SlantTan;
            PointF[] pts =
            {
                new PointF(r.Left + s, r.Top), new PointF(r.Right, r.Top),
                new PointF(r.Right - s, r.Bottom), new PointF(r.Left, r.Bottom),
            };
            GraphicsState state = g.Save();
            try
            {
                g.SmoothingMode = SmoothingMode.AntiAlias;
                using (SolidBrush b = new SolidBrush(Color.FromArgb(Scale(fill.A, a), fill)))
                    g.FillPolygon(b, pts);
                if (border.A > 0)
                    using (Pen p = new Pen(Color.FromArgb(Scale(border.A, a), border), 1f))
                        g.DrawPolygon(p, pts);
            }
            finally { g.Restore(state); }
            return new RectangleF(r.Left + s * 0.5f, r.Top, Math.Max(1f, r.Width - s), r.Height);
        }

        /// <summary>技能槽式四角 L 形角标。</summary>
        internal static void DrawSlotBrackets(Graphics g, RectangleF r, Color color, float arm, float width = 1f)
        {
            if (g == null || r.Width <= 2 || r.Height <= 2 || color.A == 0) return;
            float a = Math.Min(arm, Math.Min(r.Width, r.Height) / 2f);
            if (a < 1.5f) return;
            GraphicsState state = g.Save();
            try
            {
                g.SmoothingMode = SmoothingMode.None;
                using (Pen p = new Pen(color, width))
                {
                    g.DrawLine(p, r.Left, r.Top, r.Left + a, r.Top);
                    g.DrawLine(p, r.Left, r.Top, r.Left, r.Top + a);
                    g.DrawLine(p, r.Right - a, r.Top, r.Right, r.Top);
                    g.DrawLine(p, r.Right, r.Top, r.Right, r.Top + a);
                    g.DrawLine(p, r.Left, r.Bottom, r.Left + a, r.Bottom);
                    g.DrawLine(p, r.Left, r.Bottom - a, r.Left, r.Bottom);
                    g.DrawLine(p, r.Right - a, r.Bottom, r.Right, r.Bottom);
                    g.DrawLine(p, r.Right, r.Bottom - a, r.Right, r.Bottom);
                }
            }
            finally { g.Restore(state); }
        }

        /// <summary>技能栏右上 `////` 斜纹装饰。</summary>
        internal static void DrawHatch(Graphics g, RectangleF area, Color color, float scale)
        {
            if (g == null || area.Width <= 2 || area.Height <= 1 || color.A == 0) return;
            float pitch = Math.Max(3f, 5f * Math.Max(0.5f, scale));
            float stroke = Math.Max(1f, 1.6f * Math.Max(0.5f, scale));
            float dx = area.Height * SlantTan * 2.2f;
            GraphicsState state = g.Save();
            try
            {
                g.SmoothingMode = SmoothingMode.AntiAlias;
                g.SetClip(area, CombineMode.Intersect);
                using (Pen p = new Pen(color, stroke))
                {
                    for (float x = area.Left; x < area.Right + dx; x += pitch)
                        g.DrawLine(p, x, area.Top, x - dx, area.Bottom);
                }
            }
            finally { g.Restore(state); }
        }

        /// <summary>刘海板：下沿双切角，呼应刘海轮廓；底部中段斜纹。</summary>
        internal static void DrawNotchPlate(Graphics g, Rectangle rect, float scale, Color fill, bool hatch)
        {
            if (g == null || rect.Width <= 2 || rect.Height <= 2) return;
            DrawPlate(g, rect, scale, fill, AnchorRim,
                PlateCorners.BottomLeft | PlateCorners.BottomRight, NotchChamferBase);
            if (hatch && rect.Width > Px(160, scale))
            {
                float w = Math.Min(Px(96, scale), rect.Width / 4f);
                float h = Math.Max(2f, Px(3, scale));
                DrawHatch(g, new RectangleF(rect.Left + (rect.Width - w) / 2f, rect.Bottom - h - Px(3, scale), w, h),
                    WithAlpha(AnchorRim, 70), scale);
            }
        }

        // ---------------- 07-10 白框（Legacy，仅 NPC 菜单） ----------------

        internal static void DrawLegacyPanel(Graphics g, Rectangle rect, float scale, Color fill, Color accent, bool strongFrame)
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

        internal static void DrawLegacyButton(Graphics g, Rectangle rect, float scale,
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

        internal static void DrawLegacySeparator(Graphics g, int x, int top, int bottom, float scale)
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

        private static int Scale(int alpha, float factor)
        {
            return Math.Max(0, Math.Min(255, (int)Math.Round(alpha * factor)));
        }
    }
}
