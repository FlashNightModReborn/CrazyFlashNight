using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
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
    ///   2. body：visuals PNG alpha 剪影（优先）或 fallback 圆角矩形 blocks + beacon 高亮 currentRect
    ///   3. label pill（左上角，pageLabel + label）
    ///
    /// click → LauncherCommandRouter.Dispatch("TASK_MAP")（与 web button 同入口）
    ///
    /// PNG silhouette mask 与 web map-hud-svg-silhouette 对齐：assetUrl 以 webDir 为安全根解析，
    /// 使用 PNG alpha 作为 mask 并按 HUD theme tint。visuals 缺失或加载失败时回退 blocks。
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
        // 折叠态：tiny pin badge，作为常驻"展开"入口（与 web map-hud.js toggleCollapsed 对齐）
        private const int PIN_W_BASE = 28;
        private const int PIN_H_BASE = 28;
        private const int CLOSE_BTN_W_BASE = 16;

        private readonly Control _anchor;
        private readonly LauncherCommandRouter _router;
        private readonly MapHudDataCatalog _catalog;
        private readonly FlashCoordinateMapper _mapper;

        private volatile bool _gameReady;
        private string _mode = "0";
        private string _hotspotId = "";
        private MapHudHotspotEntry _entry;
        private bool _hover;
        // collapsed：与 web map-hud.js _state.collapsed 同义。true → 仅渲染 pin badge，仍可见 + 可点击展开。
        // 不影响 _gameReady/mode/catalog 门控；折叠后玩家仍能用左下角 pin 重新展开。
        private bool _collapsed;
        private bool _hoverCloseBtn;

        private static readonly object AssetCacheLock = new object();
        private static readonly Dictionary<string, Image> AssetCache = new Dictionary<string, Image>(StringComparer.OrdinalIgnoreCase);
        private static readonly Dictionary<string, Bitmap> TintedAssetCache = new Dictionary<string, Bitmap>(StringComparer.OrdinalIgnoreCase);
        private static readonly HashSet<string> MissingAssetWarnings = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        private const int MAX_TINTED_CACHE = 128;

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
                    int w = _collapsed ? WidgetScaler.Px(PIN_W_BASE, Scale) : CardW;
                    int h = _collapsed ? WidgetScaler.Px(PIN_H_BASE, Scale) : CardH;
                    int margin = WidgetScaler.Px(8, Scale);
                    // 贴 viewport 左下：避开 NotchOverlay 顶部 + QuestNotice 底部居中
                    int x = origin.X + (int)vpX + margin;
                    int y = origin.Y + (int)vpY + Math.Max(0, (int)vpH - h - margin);
                    return new Rectangle(x, y, w, h);
                }
                catch { return Rectangle.Empty; }
            }
        }

        // ── 折叠 API（与 web MapHud.toggleCollapsed / setCollapsed / isCollapsed 镜像）──

        public bool IsCollapsed { get { return _collapsed; } }

        public void SetCollapsed(bool collapsed)
        {
            if (_collapsed == collapsed) return;
            _collapsed = collapsed;
            _hoverCloseBtn = false;
            FireBounds();  // ScreenBounds 大小变 → NativeHud 重算 union
        }

        public void ToggleCollapsed() { SetCollapsed(!_collapsed); }

        // close × button 的局部矩形（相对 card 左上）。仅在展开态有效。
        private Rectangle ComputeCloseBtnLocal(Rectangle card)
        {
            int sz = WidgetScaler.Px(CLOSE_BTN_W_BASE, Scale);
            int pad = WidgetScaler.Px(4, Scale);
            return new Rectangle(card.Right - sz - pad, card.Y + pad, sz, sz);
        }

        public void Paint(Graphics g, float dpr, Point hudOrigin)
        {
            Rectangle r = ScreenBounds;
            if (r.Width <= 0 || r.Height <= 0) return;
            if (_entry == null || _entry.Outline == null || !_entry.Outline.ViewportRect.HasValue) return;

            int localX = r.X - hudOrigin.X;
            int localY = r.Y - hudOrigin.Y;
            Rectangle card = new Rectangle(localX, localY, r.Width, r.Height);
            ThemeColors theme = ResolveTheme(_entry.Meta != null ? _entry.Meta.Group : null);

            SmoothingMode prevSmooth = g.SmoothingMode;
            TextRenderingHint prevHint = g.TextRenderingHint;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = TextRenderingHint.AntiAlias;

            try
            {
                if (_collapsed) PaintCollapsedPin(g, card, theme);
                else PaintExpandedCard(g, card, theme);
            }
            finally
            {
                g.SmoothingMode = prevSmooth;
                g.TextRenderingHint = prevHint;
            }
        }

        private void PaintExpandedCard(Graphics g, Rectangle card, ThemeColors theme)
        {
            int radius = WidgetScaler.Px(CARD_RADIUS_BASE, Scale);

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

            // 4. close × button（右上角，hover 时高亮）。click → ToggleCollapsed
            PaintCloseButton(g, card, theme);
        }

        private void PaintCollapsedPin(Graphics g, Rectangle card, ThemeColors theme)
        {
            // 圆形 pin badge：group 主题色环 + 中心填充。click → 展开（与 web map-hud.js toggleCollapsed 对齐）
            // 折叠态不显示文字（28px 圆里挤），仅靠主题色 dot 区分。
            using (SolidBrush bg  = new SolidBrush(Color.FromArgb(_hover ? 240 : 220, theme.StageA)))
            using (Pen ring       = new Pen(Color.FromArgb(_hover ? 200 : 130, theme.Accent), 1.6f))
            using (SolidBrush dot = new SolidBrush(Color.FromArgb(232, theme.Current)))
            {
                g.FillEllipse(bg, card);
                g.DrawEllipse(ring, card);
                int dotSz = Math.Max(3, card.Width / 4);
                Rectangle dotRect = new Rectangle(
                    card.X + (card.Width - dotSz) / 2,
                    card.Y + (card.Height - dotSz) / 2,
                    dotSz, dotSz);
                g.FillEllipse(dot, dotRect);
            }
        }

        private void PaintCloseButton(Graphics g, Rectangle card, ThemeColors theme)
        {
            Rectangle btn = ComputeCloseBtnLocal(card);
            using (SolidBrush bg = new SolidBrush(Color.FromArgb(_hoverCloseBtn ? 200 : 80, theme.StageA)))
            using (Pen ring     = new Pen(Color.FromArgb(_hoverCloseBtn ? 200 : 110, theme.Accent)))
            using (Pen xPen     = new Pen(Color.FromArgb(_hoverCloseBtn ? 248 : 200, 246, 248, 250), 1.4f))
            {
                g.FillEllipse(bg, btn);
                g.DrawEllipse(ring, btn);
                int pad = Math.Max(2, btn.Width / 4);
                g.DrawLine(xPen, btn.X + pad, btn.Y + pad, btn.Right - pad, btn.Bottom - pad);
                g.DrawLine(xPen, btn.Right - pad, btn.Y + pad, btn.X + pad, btn.Bottom - pad);
            }
        }

        private void PaintBody(Graphics g, Rectangle body, ThemeColors theme)
        {
            MapHudOutline outline = _entry.Outline;
            PaintHudOutline(g, body, outline, _entry.Meta, theme, Scale, MIN_BLOCK_PX, WidgetScaler.Pxf(BEACON_R_BASE, Scale));
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

        // 把 screen point 转回 card 局部坐标做 close-btn 命中
        private bool IsPointInCloseBtn(Point screenPt)
        {
            if (_collapsed) return false;
            Rectangle r = ScreenBounds;
            if (r.Width <= 0) return false;
            // ScreenBounds == card 屏幕矩形；ComputeCloseBtnLocal 输入用 0 偏移版本然后再加屏幕原点
            Rectangle cardLocalAtZero = new Rectangle(0, 0, r.Width, r.Height);
            Rectangle btnLocal = ComputeCloseBtnLocal(cardLocalAtZero);
            Rectangle btnScreen = new Rectangle(r.X + btnLocal.X, r.Y + btnLocal.Y, btnLocal.Width, btnLocal.Height);
            return btnScreen.Contains(screenPt);
        }

        public void OnMouseEvent(MouseEventArgs e, MouseEventKind kind)
        {
            switch (kind)
            {
                case MouseEventKind.Enter:
                case MouseEventKind.Move:
                {
                    bool hover = true;
                    bool overClose = IsPointInCloseBtn(new Point(e.X, e.Y));
                    if (hover != _hover || overClose != _hoverCloseBtn)
                    {
                        _hover = hover;
                        _hoverCloseBtn = overClose;
                        FireRepaint();
                    }
                    break;
                }
                case MouseEventKind.Leave:
                    if (_hover || _hoverCloseBtn) { _hover = false; _hoverCloseBtn = false; FireRepaint(); }
                    break;
                case MouseEventKind.Click:
                    if (_collapsed)
                    {
                        // pin badge → 展开（不开 panel）
                        SetCollapsed(false);
                    }
                    else if (IsPointInCloseBtn(new Point(e.X, e.Y)))
                    {
                        // × → 折叠
                        SetCollapsed(true);
                    }
                    else
                    {
                        // card 主体 → 打开地图 panel
                        try { _router.Dispatch("TASK_MAP"); }
                        catch (Exception ex) { LogManager.Log("[MapHud] TASK_MAP dispatch failed: " + ex.Message); }
                    }
                    break;
            }
        }

        public void OnUiDataChanged(IReadOnlyDictionary<string, string> snapshot, ISet<string> changedKeys)
        {
            bool dirty = false;
            string piece;
            if (changedKeys.Contains("s") && snapshot.TryGetValue("s", out piece))
            {
                bool ready = UiValueParser.ParseUiBoolValue(piece);
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

        // ── shared renderer (MapHudWidget + RightContextWidget) ──

        internal static void PaintHudOutline(Graphics g, Rectangle body, MapHudOutline outline, MapHudMeta meta,
            ThemeColors theme, float scale, float minBlockPx, float beaconRadius)
        {
            if (g == null || body.Width <= 0 || body.Height <= 0) return;
            if (outline == null || !outline.ViewportRect.HasValue) return;
            RectF vp = outline.ViewportRect.Value;
            if (vp.W <= 0 || vp.H <= 0) return;

            float s = Math.Min(body.Width / vp.W, body.Height / vp.H);
            float drawW = vp.W * s;
            float drawH = vp.H * s;
            float originX = body.X + (body.Width - drawW) / 2f;
            float originY = body.Y + (body.Height - drawH) / 2f;
            string currentId = meta != null ? (meta.HotspotId ?? "") : "";

            GraphicsState state = g.Save();
            try
            {
                g.SetClip(body);
                bool paintedVisuals = PaintVisuals(g, outline, currentId, theme, vp, originX, originY, s, scale);
                if (!paintedVisuals)
                    PaintFallbackBlocks(g, outline, currentId, theme, vp, originX, originY, s, minBlockPx);
                PaintBeacon(g, outline, theme, vp, originX, originY, s, beaconRadius);
            }
            finally
            {
                g.Restore(state);
            }
        }

        private static bool PaintVisuals(Graphics g, MapHudOutline outline, string currentId, ThemeColors theme,
            RectF vp, float originX, float originY, float s, float scale)
        {
            if (outline.Visuals == null || outline.Visuals.Count == 0) return false;

            bool painted = false;
            for (int i = 0; i < outline.Visuals.Count; i++)
            {
                MapHudVisual visual = outline.Visuals[i];
                if (visual == null || !visual.SourceRect.HasValue || string.IsNullOrEmpty(visual.AssetUrl)) continue;
                Image img = GetAssetImage(visual.AssetUrl);
                if (img == null) continue;
                RectangleF dest = MapSourceRect(visual.SourceRect.Value, vp, originX, originY, s, 1f);
                DrawTintedImage(g, img, visual.AssetUrl, dest, theme.Silhouette, 47);
                painted = true;
            }

            for (int i = 0; i < outline.Visuals.Count; i++)
            {
                MapHudVisual visual = outline.Visuals[i];
                if (visual == null || !visual.SourceRect.HasValue || string.IsNullOrEmpty(visual.AssetUrl)) continue;
                if (!IsCurrentVisual(visual, currentId)) continue;
                Image img = GetAssetImage(visual.AssetUrl);
                if (img == null) continue;
                RectangleF dest = MapSourceRect(visual.SourceRect.Value, vp, originX, originY, s, 1f);
                RectangleF glow = dest;
                float inflate = Math.Max(1.5f, 2.2f * scale);
                glow.Inflate(inflate, inflate);
                DrawTintedImage(g, img, visual.AssetUrl, glow, theme.Current, 82);
                DrawTintedImage(g, img, visual.AssetUrl, dest, theme.Current, 245);
            }

            return painted;
        }

        private static void PaintFallbackBlocks(Graphics g, MapHudOutline outline, string currentId, ThemeColors theme,
            RectF vp, float originX, float originY, float s, float minBlockPx)
        {
            using (SolidBrush blockFill = new SolidBrush(Color.FromArgb(36, theme.Silhouette)))
            using (SolidBrush blockFillCur = new SolidBrush(Color.FromArgb(76, theme.Current)))
            using (Pen blockEdge = new Pen(Color.FromArgb(72, theme.Accent)))
            using (Pen blockEdgeCur = new Pen(Color.FromArgb(168, theme.Current), 1.4f))
            {
                if (outline.Blocks == null) return;
                for (int i = 0; i < outline.Blocks.Count; i++)
                {
                    MapHudBlock blk = outline.Blocks[i];
                    if (blk == null || !blk.SourceRect.HasValue) continue;
                    RectangleF r = MapSourceRect(blk.SourceRect.Value, vp, originX, originY, s, minBlockPx);
                    bool isCurrent = !string.IsNullOrEmpty(blk.HotspotId) && blk.HotspotId == currentId;
                    float br = Math.Max(2f, Math.Min(6f, Math.Min(r.Width, r.Height) * 0.18f));
                    using (GraphicsPath bp = MakeRoundedRectF(r.X, r.Y, r.Width, r.Height, br))
                    {
                        g.FillPath(isCurrent ? blockFillCur : blockFill, bp);
                        g.DrawPath(isCurrent ? blockEdgeCur : blockEdge, bp);
                    }
                }
            }
        }

        private static void PaintBeacon(Graphics g, MapHudOutline outline, ThemeColors theme,
            RectF vp, float originX, float originY, float s, float beaconRadius)
        {
            if (!outline.CurrentRect.HasValue) return;
            RectF cr = outline.CurrentRect.Value;
            float cx = originX + (cr.X + cr.W / 2f - vp.X) * s;
            float cy = originY + (cr.Y + cr.H / 2f - vp.Y) * s;
            float br = Math.Max(2f, beaconRadius);
            using (Pen ringPen = new Pen(Color.FromArgb(198, theme.Current), Math.Max(1f, s * 0.035f)))
            using (SolidBrush coreBrush = new SolidBrush(Color.FromArgb(255, theme.Current)))
            {
                g.DrawEllipse(ringPen, cx - br, cy - br, br * 2, br * 2);
                float cr2 = br * 0.46f;
                g.FillEllipse(coreBrush, cx - cr2, cy - cr2, cr2 * 2, cr2 * 2);
            }
        }

        private static RectangleF MapSourceRect(RectF src, RectF vp, float originX, float originY, float s, float minPx)
        {
            float x = originX + (src.X - vp.X) * s;
            float y = originY + (src.Y - vp.Y) * s;
            float w = Math.Max(minPx, src.W * s);
            float h = Math.Max(minPx, src.H * s);
            return new RectangleF(x, y, w, h);
        }

        private static bool IsCurrentVisual(MapHudVisual visual, string currentId)
        {
            if (visual == null) return false;
            if (visual.IsCurrent) return true;
            if (string.IsNullOrEmpty(currentId) || visual.HotspotIds == null) return false;
            for (int i = 0; i < visual.HotspotIds.Count; i++)
                if (visual.HotspotIds[i] == currentId) return true;
            return false;
        }

        /// <summary>
        /// P2-1 prewarm 入口：后台线程预加载 silhouette PNG 进 AssetCache。
        /// 同步路径 GetAssetImage 走相同 lock；预加载后玩家首次打开 map 时直接命中。
        /// </summary>
        public static void PrewarmAsset(string assetUrl)
        {
            try { GetAssetImage(assetUrl); }
            catch (Exception ex) { LogManager.Log("[MapHud] PrewarmAsset failed: " + (assetUrl ?? "<null>") + " ex=" + ex.Message); }
        }

        private static Image GetAssetImage(string assetUrl)
        {
            string webDir;
            if (!TryFindDefaultWebDir(out webDir)) return null;
            string path;
            if (!TryResolveAssetPath(webDir, assetUrl, out path)) return null;

            lock (AssetCacheLock)
            {
                Image cached;
                if (AssetCache.TryGetValue(path, out cached)) return cached;
                if (!File.Exists(path))
                {
                    WarnMissingAsset(path, "[MapHud] silhouette asset not found: " + path);
                    return null;
                }
                try
                {
                    using (Image src = Image.FromFile(path))
                    {
                        Bitmap copy = new Bitmap(src);
                        AssetCache[path] = copy;
                        return copy;
                    }
                }
                catch (Exception ex)
                {
                    WarnMissingAsset(path, "[MapHud] silhouette asset load failed: " + path + " ex=" + ex.Message);
                    return null;
                }
            }
        }

        private static void WarnMissingAsset(string key, string message)
        {
            if (MissingAssetWarnings.Contains(key)) return;
            MissingAssetWarnings.Add(key);
            LogManager.Log(message);
        }

        private static bool TryFindDefaultWebDir(out string webDir)
        {
            webDir = null;
            string cwd = Environment.CurrentDirectory;
            string baseDir = AppDomain.CurrentDomain.BaseDirectory;
            string[] candidates = {
                Path.Combine(cwd ?? "", "launcher", "web"),
                Path.Combine(cwd ?? "", "web"),
                Path.Combine(baseDir ?? "", "launcher", "web"),
                Path.Combine(baseDir ?? "", "web"),
                Path.Combine(baseDir ?? "", "..", "..", "web"),
                Path.Combine(baseDir ?? "", "..", "..", "..", "web")
            };
            for (int i = 0; i < candidates.Length; i++)
            {
                try
                {
                    string full = Path.GetFullPath(candidates[i]);
                    if (Directory.Exists(full))
                    {
                        webDir = full;
                        return true;
                    }
                }
                catch { }
            }
            return false;
        }

        private static void DrawTintedImage(Graphics g, Image img, string assetKey, RectangleF dest, Color color, int alpha)
        {
            if (img == null || dest.Width <= 0 || dest.Height <= 0 || alpha <= 0) return;
            int dw = Math.Max(1, (int)Math.Round(dest.Width));
            int dh = Math.Max(1, (int)Math.Round(dest.Height));
            Bitmap tinted = GetTintedBitmap(img, assetKey, dw, dh, color, alpha);
            if (tinted == null) return;
            Rectangle destRect = new Rectangle((int)Math.Round(dest.X), (int)Math.Round(dest.Y), dw, dh);
            g.DrawImageUnscaled(tinted, destRect);
        }

        private static Bitmap GetTintedBitmap(Image img, string assetKey, int width, int height, Color color, int alpha)
        {
            string key = (assetKey ?? "") + "|" + width + "x" + height + "|" + color.ToArgb().ToString("X8") + "|" + alpha.ToString();
            lock (AssetCacheLock)
            {
                Bitmap cached;
                if (TintedAssetCache.TryGetValue(key, out cached)) return cached;
                if (TintedAssetCache.Count >= MAX_TINTED_CACHE)
                {
                    foreach (Bitmap b in TintedAssetCache.Values)
                    {
                        try { b.Dispose(); } catch { }
                    }
                    TintedAssetCache.Clear();
                }

                Bitmap bmp = new Bitmap(width, height, PixelFormat.Format32bppPArgb);
                using (Graphics g = Graphics.FromImage(bmp))
                {
                    g.Clear(Color.Transparent);
                    g.InterpolationMode = InterpolationMode.HighQualityBilinear;
                    g.PixelOffsetMode = PixelOffsetMode.Half;
                    DrawTintedImageUncached(g, img, new Rectangle(0, 0, width, height), color, alpha);
                }
                TintedAssetCache[key] = bmp;
                return bmp;
            }
        }

        private static void DrawTintedImageUncached(Graphics g, Image img, Rectangle dest, Color color, int alpha)
        {
            float r = color.R / 255f;
            float gg = color.G / 255f;
            float b = color.B / 255f;
            float a = Math.Max(0f, Math.Min(1f, alpha / 255f));
            ColorMatrix matrix = new ColorMatrix(new float[][]
            {
                new float[] { 0f, 0f, 0f, 0f, 0f },
                new float[] { 0f, 0f, 0f, 0f, 0f },
                new float[] { 0f, 0f, 0f, 0f, 0f },
                new float[] { 0f, 0f, 0f, a,  0f },
                new float[] { r,  gg, b,  0f, 1f }
            });
            using (ImageAttributes attrs = new ImageAttributes())
            {
                attrs.SetColorMatrix(matrix, ColorMatrixFlag.Default, ColorAdjustType.Bitmap);
                g.DrawImage(img, dest, 0, 0, img.Width, img.Height, GraphicsUnit.Pixel, attrs);
            }
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
        internal bool HoverCloseBtnForTest { get { return _hoverCloseBtn; } }
        internal void SimulateClick() { OnMouseEvent(new MouseEventArgs(MouseButtons.Left, 1, 0, 0, 0), MouseEventKind.Click); }
        /// <summary>测试用：模拟 close-btn click。直接打到 close-btn 屏幕坐标，避免依赖 ScreenBounds（anchor 未在屏幕上时 ScreenBounds=Empty）。</summary>
        internal void SimulateCloseBtnClick()
        {
            // 走 ToggleCollapsed 路径：直接调 API（OnMouseEvent 命中需要 anchor 在屏幕坐标系，单测里不一定可达）
            if (!_collapsed) SetCollapsed(true);
        }
    }
}
