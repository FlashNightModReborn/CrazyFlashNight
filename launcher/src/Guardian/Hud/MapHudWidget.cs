using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.IO;
using System.Windows.Forms;
using CF7Launcher.Guardian;

namespace CF7Launcher.Guardian.Hud
{
    /// <summary>
    /// 替代 web overlay.html #map-hud：当前位置 HUD 缩略图。
    ///
    /// 数据通路：
    ///   AS2 → UiData "mm:N" (mode 0/1/2/3) + "mh:hotspotId"
    ///   → MapHudWidget.OnUiDataChanged → MapHudDataCatalog.GetEntry → render
    ///
    /// Visible 门控（与 web map-hud.js 一致）：
    ///   gameReady && mode in {1,2} && hotspotId != "" && catalog 命中
    ///
    /// 渲染层级（自底向上）：
    ///   1. 圆角卡片背景（按 group 主题色染）
    ///   2. body：fallback 圆角矩形 blocks（mvp）+ beacon 高亮 currentRect
    ///   3. label pill（左上角，pageLabel + label）
    ///
    /// click → LauncherCommandRouter.Dispatch("TASK_MAP")（与 web button 同入口）
    ///
    /// 不渲染 PNG silhouette mask（web map-hud-svg-silhouette via SVG mask）：
    /// PNG alpha-mask + tint 在 GDI+ 下成本与维护代价大；fallback 圆角矩形已能传递"有几个区域、哪个是当前"的核心信息。
    /// 后续若需要可加 LRU 缓存版本（plan 4.7.4）。
    /// </summary>
    public class MapHudWidget : INativeHudWidget, IUiDataConsumer
    {
        // 设计基准：86px 高（与 web overlay.css #map-hud 一致），稍宽以装下 label
        private const int CARD_W_BASE = 168;
        private const int CARD_H_BASE = 86;
        private const int CARD_RADIUS_BASE = 8;
        private const int LABEL_PAD_X_BASE = 6;
        private const int LABEL_PAD_Y_BASE = 2;
        private const int BODY_INSET_BASE = 8;
        private const int BEACON_R_BASE = 5;
        private const float FONT_BASE_PX = 11.5f;
        private const float MIN_BLOCK_PX = 4f;

        private readonly Control _anchor;
        private readonly LauncherCommandRouter _router;
        private readonly MapHudDataCatalog _catalog;
        private readonly FlashCoordinateMapper _mapper;

        private volatile bool _gameReady;
        private string _mode = "0";
        private string _hotspotId = "";
        private MapHudHotspotEntry _entry;
        private bool _hover;

        public event EventHandler BoundsOrVisibilityChanged;
        public event EventHandler RepaintRequested;
        public event EventHandler AnimationStateChanged;

        public MapHudWidget(Control anchor, LauncherCommandRouter router, MapHudDataCatalog catalog)
        {
            if (anchor == null) throw new ArgumentNullException("anchor");
            if (router == null) throw new ArgumentNullException("router");
            if (catalog == null) throw new ArgumentNullException("catalog");
            _anchor = anchor;
            _router = router;
            _catalog = catalog;
            _mapper = new FlashCoordinateMapper(anchor, 1024f, 576f);
            _anchor.Resize += delegate { FireBounds(); };
        }

        private float Scale { get { return WidgetScaler.GetScale(_mapper); } }
        private int CardW { get { return WidgetScaler.Px(CARD_W_BASE, Scale); } }
        private int CardH { get { return WidgetScaler.Px(CARD_H_BASE, Scale); } }

        // mode 1=base / 2=外部 → renderable；其它 → 隐藏（与 map-hud.js sanitizeMode + applyState 同步）
        private bool IsModeRenderable
        {
            get { return _mode == "1" || _mode == "2"; }
        }

        public bool Visible
        {
            get
            {
                if (!_gameReady) return false;
                if (!_catalog.IsAvailable) return false;
                if (!IsModeRenderable) return false;
                if (string.IsNullOrEmpty(_hotspotId)) return false;
                return _entry != null && _entry.Outline != null && _entry.Outline.ViewportRect.HasValue;
            }
        }

        public bool WantsAnimationTick { get { return false; } }
        public void Tick(int deltaMs) { }

        public Rectangle ScreenBounds
        {
            get
            {
                if (!Visible || _anchor == null || !_anchor.IsHandleCreated) return Rectangle.Empty;
                try
                {
                    Point origin = _anchor.PointToScreen(Point.Empty);
                    float vpX, vpY, vpW, vpH;
                    _mapper.CalcViewport(out vpX, out vpY, out vpW, out vpH);
                    int cardW = CardW;
                    int cardH = CardH;
                    int margin = WidgetScaler.Px(8, Scale);
                    // 贴 viewport 左下：避开 NotchOverlay 顶部 + QuestNotice 底部居中
                    int x = origin.X + (int)vpX + margin;
                    int y = origin.Y + (int)vpY + Math.Max(0, (int)vpH - cardH - margin);
                    return new Rectangle(x, y, cardW, cardH);
                }
                catch { return Rectangle.Empty; }
            }
        }

        public void Paint(Graphics g, float dpr, Point hudOrigin)
        {
            Rectangle r = ScreenBounds;
            if (r.Width <= 0 || r.Height <= 0) return;
            if (_entry == null || _entry.Outline == null || !_entry.Outline.ViewportRect.HasValue) return;

            int localX = r.X - hudOrigin.X;
            int localY = r.Y - hudOrigin.Y;
            Rectangle card = new Rectangle(localX, localY, r.Width, r.Height);
            int radius = WidgetScaler.Px(CARD_RADIUS_BASE, Scale);

            ThemeColors theme = ResolveTheme(_entry.Meta != null ? _entry.Meta.Group : null);

            SmoothingMode prevSmooth = g.SmoothingMode;
            TextRenderingHint prevHint = g.TextRenderingHint;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = TextRenderingHint.AntiAlias;

            try
            {
                // 1. 圆角卡片背景 + 边框
                using (GraphicsPath cardPath = MakeRoundedRect(card, radius))
                using (LinearGradientBrush bgBrush = new LinearGradientBrush(
                    new Rectangle(card.X, card.Y, card.Width, card.Height + 1),
                    Color.FromArgb(_hover ? 250 : 240, theme.StageA),
                    Color.FromArgb(_hover ? 250 : 250, theme.StageB),
                    LinearGradientMode.Vertical))
                using (Pen border = new Pen(Color.FromArgb(_hover ? 96 : 56, theme.Accent)))
                {
                    g.FillPath(bgBrush, cardPath);
                    g.DrawPath(border, cardPath);
                }

                // 2. body：把 viewportRect 等比映射到内框
                Rectangle body = Rectangle.Inflate(card, -WidgetScaler.Px(BODY_INSET_BASE, Scale), -WidgetScaler.Px(BODY_INSET_BASE, Scale));
                if (body.Width > 0 && body.Height > 0)
                {
                    PaintBody(g, body, theme);
                }

                // 3. label pill（左上角，pageLabel · label）
                PaintLabel(g, card, theme);
            }
            finally
            {
                g.SmoothingMode = prevSmooth;
                g.TextRenderingHint = prevHint;
            }
        }

        private void PaintBody(Graphics g, Rectangle body, ThemeColors theme)
        {
            MapHudOutline outline = _entry.Outline;
            RectF vp = outline.ViewportRect.Value;
            if (vp.W <= 0 || vp.H <= 0) return;

            // 等比缩放：HUD body 内适配 viewport 矩形（preserveAspectRatio xMidYMid meet）
            float sx = body.Width / vp.W;
            float sy = body.Height / vp.H;
            float s = Math.Min(sx, sy);
            float drawW = vp.W * s;
            float drawH = vp.H * s;
            float originX = body.X + (body.Width - drawW) / 2f;
            float originY = body.Y + (body.Height - drawH) / 2f;

            // fallback 矩形 blocks（与 web buildFallbackRectLayer 等效；不渲染 PNG silhouette mask）
            string currentId = _entry.Meta != null ? _entry.Meta.HotspotId : "";
            using (SolidBrush blockFill    = new SolidBrush(Color.FromArgb(36, theme.Silhouette)))
            using (SolidBrush blockFillCur = new SolidBrush(Color.FromArgb(76, theme.Current)))
            using (Pen blockEdge           = new Pen(Color.FromArgb(72, theme.Accent)))
            using (Pen blockEdgeCur        = new Pen(Color.FromArgb(168, theme.Current), 1.4f))
            {
                if (outline.Blocks != null)
                {
                    for (int i = 0; i < outline.Blocks.Count; i++)
                    {
                        MapHudBlock blk = outline.Blocks[i];
                        if (blk == null || !blk.SourceRect.HasValue) continue;
                        RectF src = blk.SourceRect.Value;
                        float bx = originX + (src.X - vp.X) * s;
                        float by = originY + (src.Y - vp.Y) * s;
                        float bw = Math.Max(MIN_BLOCK_PX, src.W * s);
                        float bh = Math.Max(MIN_BLOCK_PX, src.H * s);
                        bool isCurrent = !string.IsNullOrEmpty(blk.HotspotId) && blk.HotspotId == currentId;
                        float br = Math.Max(2f, Math.Min(6f, Math.Min(bw, bh) * 0.18f));
                        using (GraphicsPath bp = MakeRoundedRectF(bx, by, bw, bh, br))
                        {
                            g.FillPath(isCurrent ? blockFillCur : blockFill, bp);
                            g.DrawPath(isCurrent ? blockEdgeCur : blockEdge, bp);
                        }
                    }
                }

                // beacon on currentRect（与 web map-hud-svg-beacon 等效）
                if (outline.CurrentRect.HasValue)
                {
                    RectF cr = outline.CurrentRect.Value;
                    float cx = originX + (cr.X + cr.W / 2f - vp.X) * s;
                    float cy = originY + (cr.Y + cr.H / 2f - vp.Y) * s;
                    float br = WidgetScaler.Pxf(BEACON_R_BASE, Scale);
                    using (SolidBrush ringBrush = new SolidBrush(Color.FromArgb(120, theme.Current)))
                    using (SolidBrush coreBrush = new SolidBrush(Color.FromArgb(232, theme.Current)))
                    {
                        g.FillEllipse(ringBrush, cx - br, cy - br, br * 2, br * 2);
                        float cr2 = br * 0.55f;
                        g.FillEllipse(coreBrush, cx - cr2, cy - cr2, cr2 * 2, cr2 * 2);
                    }
                }
            }
        }

        private void PaintLabel(Graphics g, Rectangle card, ThemeColors theme)
        {
            string pageLabel = _entry.Meta != null ? (_entry.Meta.PageLabel ?? "") : "";
            string spotLabel = _entry.Meta != null ? (_entry.Meta.Label ?? "") : "";
            string text;
            if (string.IsNullOrEmpty(pageLabel)) text = spotLabel;
            else if (string.IsNullOrEmpty(spotLabel)) text = pageLabel;
            else text = pageLabel + " · " + spotLabel;
            if (string.IsNullOrEmpty(text)) return;

            float fontPx = WidgetScaler.Pxf(FONT_BASE_PX, Scale);
            int padX = WidgetScaler.Px(LABEL_PAD_X_BASE, Scale);
            int padY = WidgetScaler.Px(LABEL_PAD_Y_BASE, Scale);
            int marginX = WidgetScaler.Px(6, Scale);
            int marginY = WidgetScaler.Px(6, Scale);
            int maxLabelW = card.Width - marginX * 2;

            using (Font font = new Font("Microsoft YaHei", fontPx, FontStyle.Bold, GraphicsUnit.Pixel))
            using (StringFormat fmt = new StringFormat(StringFormatFlags.NoWrap)
                   { Alignment = StringAlignment.Near, LineAlignment = StringAlignment.Center, Trimming = StringTrimming.EllipsisCharacter })
            {
                SizeF measured = g.MeasureString(text, font, maxLabelW, fmt);
                int pillW = Math.Min(maxLabelW, (int)Math.Ceiling(measured.Width) + padX * 2);
                int pillH = (int)Math.Ceiling(measured.Height) + padY * 2;
                Rectangle pill = new Rectangle(card.X + marginX, card.Y + marginY, pillW, pillH);
                int pr = pillH / 2;
                using (GraphicsPath pp = MakeRoundedRect(pill, pr))
                using (LinearGradientBrush pb = new LinearGradientBrush(pill,
                    Color.FromArgb(196, theme.StageA), Color.FromArgb(232, theme.StageB), LinearGradientMode.Vertical))
                using (Pen pe = new Pen(Color.FromArgb(96, theme.Accent)))
                using (SolidBrush textBrush = new SolidBrush(Color.FromArgb(238, 246, 248, 250)))
                {
                    g.FillPath(pb, pp);
                    g.DrawPath(pe, pp);
                    Rectangle textRect = new Rectangle(pill.X + padX, pill.Y, pill.Width - padX * 2, pill.Height);
                    g.DrawString(text, font, textBrush, textRect, fmt);
                }
            }
        }

        public bool TryHitTest(Point screenPt) { return ScreenBounds.Contains(screenPt); }

        public void OnMouseEvent(MouseEventArgs e, MouseEventKind kind)
        {
            switch (kind)
            {
                case MouseEventKind.Enter:
                case MouseEventKind.Move:
                    if (!_hover) { _hover = true; FireRepaint(); }
                    break;
                case MouseEventKind.Leave:
                    if (_hover) { _hover = false; FireRepaint(); }
                    break;
                case MouseEventKind.Click:
                    try { _router.Dispatch("TASK_MAP"); }
                    catch (Exception ex) { LogManager.Log("[MapHud] TASK_MAP dispatch failed: " + ex.Message); }
                    break;
            }
        }

        public void OnUiDataChanged(IReadOnlyDictionary<string, string> snapshot, ISet<string> changedKeys)
        {
            bool dirty = false;
            string piece;
            if (changedKeys.Contains("s") && snapshot.TryGetValue("s", out piece))
            {
                bool ready = TopRightToolsWidget.ParseUiBoolValue(piece);
                if (ready != _gameReady) { _gameReady = ready; dirty = true; }
            }
            if (changedKeys.Contains("mm") && snapshot.TryGetValue("mm", out piece))
            {
                string nextMode = SanitizeMode(StripPrefix(piece, "mm"));
                if (nextMode != _mode) { _mode = nextMode; dirty = true; }
            }
            if (changedKeys.Contains("mh") && snapshot.TryGetValue("mh", out piece))
            {
                string nextHotspot = StripPrefix(piece, "mh") ?? "";
                if (nextHotspot != _hotspotId)
                {
                    _hotspotId = nextHotspot;
                    _entry = string.IsNullOrEmpty(_hotspotId) ? null : _catalog.GetEntry(_hotspotId);
                    if (_entry == null && !string.IsNullOrEmpty(_hotspotId))
                    {
                        LogManager.Log("[MapHud] hotspot not in catalog: " + _hotspotId);
                    }
                    dirty = true;
                }
            }
            if (dirty) FireBounds();
        }

        // ── theme ──

        internal struct ThemeColors
        {
            public Color Accent;
            public Color Silhouette;
            public Color Current;
            public Color StageA;
            public Color StageB;
        }

        // 与 web overlay.css #map-hud[data-group=...] 主题块对齐（去掉 alpha）
        // base 组在 catalog 中可能 group 为空（只有 base 的 hotspot 不归 unlock group）；空串 fallback 到 base 主题。
        internal static ThemeColors ResolveTheme(string group)
        {
            switch (group)
            {
                case "warlord":      return Theme(255, 184, 130,  255, 200, 148,  255, 140,  80,   22, 14, 10,  10,  7,  6);
                case "rock":         return Theme(230, 170, 255,  220, 180, 240,  220, 130, 255,   18, 12, 22,  10,  7, 14);
                case "blackiron":    return Theme(255, 140, 140,  230, 170, 170,  255, 110, 110,   20, 10, 10,  10,  6,  6);
                case "fallen":       return Theme(180, 200, 220,  190, 205, 222,  140, 180, 220,   12, 14, 18,   6,  8, 10);
                case "defense":      return Theme(140, 220, 240,  170, 220, 238,  110, 225, 255,    8, 14, 18,   5,  9, 11);
                case "restricted":   return Theme(255, 220, 120,  255, 225, 150,  255, 210,  90,   20, 16,  8,  10,  8,  5);
                case "schoolOutside":return Theme(170, 220, 200,  186, 228, 208,  140, 220, 190,   10, 16, 14,   6, 10,  9);
                case "schoolInside": return Theme(180, 210, 255,  196, 218, 250,  140, 180, 255,   10, 13, 20,   6,  8, 12);
                default:             return Theme(190, 255, 220,  188, 236, 212,  110, 225, 255,   11, 16, 14,   6,  9, 10); // base
            }
        }

        private static ThemeColors Theme(int ar, int ag, int ab, int sr, int sg, int sb, int cr, int cg, int cb,
                                         int saR, int saG, int saB, int sbR, int sbG, int sbB)
        {
            ThemeColors t;
            t.Accent     = Color.FromArgb(ar, ag, ab);
            t.Silhouette = Color.FromArgb(sr, sg, sb);
            t.Current    = Color.FromArgb(cr, cg, cb);
            t.StageA     = Color.FromArgb(saR, saG, saB);
            t.StageB     = Color.FromArgb(sbR, sbG, sbB);
            return t;
        }

        // ── helpers (internal for testing) ──

        internal static string SanitizeMode(string raw)
        {
            if (string.IsNullOrEmpty(raw)) return "0";
            switch (raw)
            {
                case "0": case "1": case "2": case "3": return raw;
                default: return "0";
            }
        }

        internal static string StripPrefix(string fullPiece, string key)
        {
            if (string.IsNullOrEmpty(fullPiece)) return "";
            string prefix = key + ":";
            if (fullPiece.StartsWith(prefix, StringComparison.Ordinal)) return fullPiece.Substring(prefix.Length);
            return fullPiece;
        }

        /// <summary>
        /// 路径安全归一化：要求 assetUrl 是 webDir 之内的相对路径。
        /// 拒绝绝对路径 / URL / query / fragment / 通过 .. 逃出 webDir。
        ///
        /// 关键：webDir 比较前 trim 末尾分隔符并补一个，避免 "C:\x\web" StartsWith 误中 "C:\x\web2"。
        /// </summary>
        internal static bool TryResolveAssetPath(string webDir, string assetUrl, out string resolved)
        {
            resolved = null;
            if (string.IsNullOrEmpty(webDir) || string.IsNullOrEmpty(assetUrl)) return false;
            if (Path.IsPathRooted(assetUrl)) return false;
            if (assetUrl.IndexOf("://", StringComparison.Ordinal) >= 0) return false;
            if (assetUrl.IndexOf('?') >= 0 || assetUrl.IndexOf('#') >= 0) return false;
            try
            {
                string webDirFull = Path.GetFullPath(webDir)
                    .TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)
                    + Path.DirectorySeparatorChar;
                string combined = Path.Combine(webDirFull, assetUrl);
                string fullPath = Path.GetFullPath(combined);
                if (!fullPath.StartsWith(webDirFull, StringComparison.OrdinalIgnoreCase)) return false;
                resolved = fullPath;
                return true;
            }
            catch { return false; }
        }

        // ── geometry ──

        private static GraphicsPath MakeRoundedRect(Rectangle r, int radius)
        {
            return MakeRoundedRectF(r.X, r.Y, r.Width, r.Height, radius);
        }

        private static GraphicsPath MakeRoundedRectF(float x, float y, float w, float h, float radius)
        {
            GraphicsPath p = new GraphicsPath();
            if (radius <= 0)
            {
                p.AddRectangle(new RectangleF(x, y, w, h));
                return p;
            }
            float d = radius * 2f;
            if (d > w) d = w;
            if (d > h) d = h;
            p.AddArc(x, y, d, d, 180, 90);
            p.AddArc(x + w - d, y, d, d, 270, 90);
            p.AddArc(x + w - d, y + h - d, d, d, 0, 90);
            p.AddArc(x, y + h - d, d, d, 90, 90);
            p.CloseFigure();
            return p;
        }

        private void FireBounds() { EventHandler h = BoundsOrVisibilityChanged; if (h != null) h(this, EventArgs.Empty); }
        private void FireRepaint() { EventHandler h = RepaintRequested; if (h != null) h(this, EventArgs.Empty); }

        // ── test seams ──

        internal void ForceGameReady(bool ready) { _gameReady = ready; FireBounds(); }
        internal void ForceMode(string mode) { _mode = SanitizeMode(mode); FireBounds(); }
        internal void ForceHotspot(string hotspotId)
        {
            _hotspotId = hotspotId ?? "";
            _entry = string.IsNullOrEmpty(_hotspotId) ? null : _catalog.GetEntry(_hotspotId);
            FireBounds();
        }
        internal bool VisibleForTest { get { return Visible; } }
        internal MapHudHotspotEntry EntryForTest { get { return _entry; } }
        internal bool HoverForTest { get { return _hover; } }
        internal void SimulateClick() { OnMouseEvent(new MouseEventArgs(MouseButtons.Left, 1, 0, 0, 0), MouseEventKind.Click); }
    }
}
