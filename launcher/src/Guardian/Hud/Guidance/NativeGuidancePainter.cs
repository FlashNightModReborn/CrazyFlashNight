using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;

namespace CF7Launcher.Guardian.Hud.Guidance
{
    /// <summary>White scene diagrams and the original light tutorial board, on the Flash logical canvas.</summary>
    internal static class NativeGuidancePainter
    {
        internal static readonly RectangleF CardBounds = new(200, 120, 617, 328);
        internal static RectangleF Button(int index) => index == 0
            ? new RectangleF(CardBounds.Right - 112, CardBounds.Bottom - 40, 96, 26)
            : new RectangleF(CardBounds.Right - 36, CardBounds.Top + 7, 26, 26);

        internal static RectangleF SceneBounds(GuidanceCatalog.Page page)
        {
            if (page.Visual.Count == 0) return new RectangleF(260, 380, 500, 86);
            RectangleF bounds = page.Visual[0].Bounds;
            for (int i = 1; i < page.Visual.Count; i++) bounds = RectangleF.Union(bounds, page.Visual[i].Bounds);
            bounds.Inflate(4, 4);
            return bounds;
        }
        private static Color Alpha(float opacity, int r, int g, int b, int alpha = 255)
            => Color.FromArgb((int)(Math.Clamp(opacity, 0, 1) * alpha), r, g, b);
        private static Font Font(float size, FontStyle style = FontStyle.Regular)
            => NativeHudFonts.CreateRoleFont("native.combat.label", size, style, GraphicsUnit.Pixel);

        internal static void Paint(Graphics g, GuidanceCatalog.Guide guide, int pageIndex,
            IReadOnlyDictionary<string, string> keys, IReadOnlyDictionary<string, string> labels, Bitmap image, float opacity)
        {
            GraphicsState state = g.Save();
            try
            {
                g.SmoothingMode = SmoothingMode.AntiAlias;
                g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
                GuidanceCatalog.Page page = guide.Pages[pageIndex];
                if (guide.Tutorial) PaintCard(g, guide, pageIndex, keys, image, opacity);
                else if (page.Visual.Count == 0)
                    DrawText(g, GuidanceCatalog.Bind(page.Text, keys), SceneBounds(page), 18, opacity, true);
                PaintVisual(g, page.Visual, keys, labels, opacity, !guide.Tutorial);
            }
            finally { g.Restore(state); }
        }
        private static void PaintCard(Graphics g, GuidanceCatalog.Guide guide, int pageIndex,
            IReadOnlyDictionary<string, string> keys, Bitmap image, float opacity)
        {
            RectangleF box = CardBounds;
            using var shadow = new SolidBrush(Alpha(opacity, 0, 0, 0, 75));
            g.FillRectangle(shadow, box.X + 2, box.Y + 3, box.Width, box.Height);
            using var paper = new LinearGradientBrush(box, Alpha(opacity, 255, 255, 255), Alpha(opacity, 204, 204, 204), 90);
            using var edge = new Pen(Alpha(opacity, 102, 102, 102), 1);
            using var rim = new Pen(Alpha(opacity, 255, 255, 255), 1);
            g.FillRectangle(paper, box);
            g.DrawRectangle(edge, box.X, box.Y, box.Width, box.Height);
            g.DrawLine(rim, box.Left, box.Top, box.Right - 1, box.Top);
            g.DrawLine(rim, box.Left, box.Top, box.Left, box.Bottom - 1);
            PaintNotice(g, new RectangleF(box.X + 11, box.Y + 7, 27, 25), opacity);
            GuidanceCatalog.Page page = guide.Pages[pageIndex];
            DrawText(g, "新手指引 · " + page.Title, new RectangleF(box.X + 48, box.Y + 9, box.Width - 98, 27), 15, opacity, false);

            RectangleF body = new(box.X + 16, box.Y + 45, box.Width - 32, box.Height - 96);
            if (page.Visual.Count > 0)
            {
                float top = body.Bottom;
                foreach (var node in page.Visual) top = Math.Min(top, node.Bounds.Top);
                body.Height = Math.Max(0, top - body.Top - 8);
            }
            if (image != null)
            {
                float height = Math.Min(130, body.Height / 2);
                GuidanceImageLayout.DrawContained(g, image, new RectangleF(body.X, body.Y, body.Width, height), opacity);
                body.Y += height + 8; body.Height -= height + 8;
            }
            // Author long tutorials as pages. Do not silently shrink body text to unreadable sizes.
            DrawText(g, GuidanceCatalog.Bind(page.Text, keys), body, 14, opacity, false);
            DrawText(g, $"{pageIndex + 1} / {guide.Pages.Count}", new RectangleF(box.X + 16, box.Bottom - 37, 120, 24), 12, opacity, false);

            RectangleF next = Button(0);
            using var buttonFill = new LinearGradientBrush(next, Alpha(opacity, 252, 252, 252), Alpha(opacity, 216, 216, 216), 90);
            using var buttonEdge = new Pen(Alpha(opacity, 116, 116, 116), 1);
            g.FillRectangle(buttonFill, next); g.DrawRectangle(buttonEdge, next.X, next.Y, next.Width, next.Height);
            DrawText(g, pageIndex + 1 < guide.Pages.Count ? "下一页" : "知道了", next, 13, opacity, false, true);

            RectangleF close = Button(1);
            using var closeFill = new SolidBrush(Alpha(opacity, 18, 18, 18));
            using var cross = new Pen(Alpha(opacity, 245, 245, 245), 2.5f);
            g.FillEllipse(closeFill, close);
            g.DrawLine(cross, close.Left + 7, close.Top + 7, close.Right - 7, close.Bottom - 7);
            g.DrawLine(cross, close.Right - 7, close.Top + 7, close.Left + 7, close.Bottom - 7);
        }
        private static void PaintNotice(Graphics g, RectangleF bounds, float opacity)
        {
            PointF[] points = { new(bounds.Left + bounds.Width / 2, bounds.Top), new(bounds.Right, bounds.Bottom), new(bounds.Left, bounds.Bottom) };
            using var red = new SolidBrush(Alpha(opacity, 197, 13, 22));
            using var light = new Pen(Alpha(opacity, 244, 114, 104), 2);
            using var gold = new Pen(Alpha(opacity, 255, 225, 47), 3);
            using var dot = new SolidBrush(Alpha(opacity, 255, 225, 47));
            g.FillPolygon(red, points); g.DrawPolygon(light, points);
            float x = bounds.Left + bounds.Width / 2;
            g.DrawLine(gold, x, bounds.Top + 8, x, bounds.Bottom - 8);
            g.FillEllipse(dot, x - 1.5f, bounds.Bottom - 5, 3, 3);
        }
        private static void PaintVisual(Graphics g, IReadOnlyList<GuidanceCatalog.VisualElement> nodes,
            IReadOnlyDictionary<string, string> keys, IReadOnlyDictionary<string, string> labels, float opacity, bool scene)
        {
            foreach (var node in nodes)
            {
                if (node.Type == "text") DrawText(g, GuidanceCatalog.Bind(node.Text, keys), node.Bounds, node.FontSize, opacity, scene);
                else if (node.Type == "key")
                {
                    string text = GuidanceCatalog.Bind(node.Text, keys);
                    PaintKey(g, labels.TryGetValue(text, out string label) ? label : text, node.Bounds, node.FontSize, opacity, scene);
                }
                else PaintMouse(g, node.Bounds, opacity, scene);
            }
        }
        private static GraphicsPath Rounded(RectangleF r, float radius)
        {
            float d = radius * 2;
            var path = new GraphicsPath();
            path.AddArc(r.Left, r.Top, d, d, 180, 90); path.AddArc(r.Right - d, r.Top, d, d, 270, 90);
            path.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90); path.AddArc(r.Left, r.Bottom - d, d, d, 90, 90);
            path.CloseFigure(); return path;
        }
        private static void PaintKey(Graphics g, string text, RectangleF bounds, float size, float opacity, bool scene)
        {
            using var path = Rounded(bounds, 5);
            using var edge = new Pen(scene ? Alpha(opacity, 255, 255, 255) : Alpha(opacity, 64, 64, 64), 3);
            if (scene)
            {
                using var shade = new Pen(Alpha(opacity, 0, 0, 0, 145), 5);
                g.DrawPath(shade, path);
            }
            g.DrawPath(edge, path);
            RectangleF label = bounds; label.Inflate(-2, -1);
            FontStyle style = FontStyle.Bold;
            while (size > 10)
            {
                using var font = Font(size, FontStyle.Bold);
                if (g.MeasureString(text, font).Width <= label.Width) break;
                size--;
            }
            using (var probe = Font(size, style))
                if (g.MeasureString(text, probe).Width > label.Width) style = FontStyle.Regular;
            DrawText(g, text, label, size, opacity, scene, true, style);
        }
        private static void PaintMouse(Graphics g, RectangleF r, float opacity, bool scene)
        {
            Color color = scene ? Alpha(opacity, 255, 255, 255) : Alpha(opacity, 64, 64, 64);
            using var outline = new Pen(color, 2.5f);
            using var fill = new SolidBrush(color);
            if (scene)
            {
                using var shade = new Pen(Alpha(opacity, 0, 0, 0, 145), 5);
                g.DrawEllipse(shade, r);
            }
            g.DrawEllipse(outline, r);
            // The filled upper-left quarter indicates the left mouse button, as in the original FLA.
            var state = g.Save();
            g.SetClip(new RectangleF(r.Left, r.Top, r.Width / 2, r.Height * .36f));
            g.FillEllipse(fill, r); g.Restore(state);
            g.DrawLine(outline, r.Left, r.Top + r.Height * .36f, r.Right, r.Top + r.Height * .36f);
            g.DrawLine(outline, r.Left + r.Width / 2, r.Top, r.Left + r.Width / 2, r.Top + r.Height * .36f);
        }
        private static void DrawText(Graphics g, string text, RectangleF bounds, float size, float opacity,
            bool scene, bool center = false, FontStyle style = FontStyle.Regular)
        {
            if (bounds.Width <= 0 || bounds.Height <= 0) return;
            using var font = Font(size, style);
            using var format = new StringFormat { Alignment = center ? StringAlignment.Center : StringAlignment.Near,
                LineAlignment = center ? StringAlignment.Center : StringAlignment.Near,
                Trimming = StringTrimming.EllipsisCharacter };
            if (center) format.FormatFlags |= StringFormatFlags.NoWrap;
            using var ink = new SolidBrush(scene ? Alpha(opacity, 255, 255, 255) : Alpha(opacity, 51, 51, 51));
            if (scene)
            {
                using var path = new GraphicsPath();
                path.AddString(text, font.FontFamily, (int)style, size, bounds, format);
                using var shade = new Pen(Alpha(opacity, 0, 0, 0, 175), 2) { LineJoin = LineJoin.Round };
                g.DrawPath(shade, path); g.FillPath(ink, path);
            }
            else g.DrawString(text, font, ink, bounds, format);
        }
    }
}
