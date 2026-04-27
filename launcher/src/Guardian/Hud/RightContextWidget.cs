using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.Windows.Forms;
using CF7Launcher.Audio;
using CF7Launcher.Guardian;

namespace CF7Launcher.Guardian.Hud
{
    /// <summary>
    /// Phase 5.7 右侧组合 HUD。
    ///
    /// 复刻旧 Web 右上 cluster：top-right-tools + context-panel + jukebox collapsed titlebar。
    /// 业务命令仍全部通过 LauncherCommandRouter.Dispatch，不在 widget 内复制业务分支。
    /// </summary>
    public class RightContextWidget : INativeHudWidget, IUiDataConsumer, IUiDataLegacyConsumer
    {
        private const int NOTICE_MS = 5000;
        private const int MINI_RENDER_MS = 100;
        private const int PLAY_POLL_MS = 250;
        private const int HISTORY = 100;
        private const int ICON_W_BASE = 28;
        private const int NOTICE_TEXT_PAD_BASE = 8;
        private const int NOTICE_ARROW_W_BASE = 24;
        private const int JUKE_PAUSE_W_BASE = 28;
        private const int JUKE_EXPAND_W_BASE = 22;
        private const int TITLE_PAD_BASE = 6;
        private const int MAP_BODY_INSET_BASE = 8;
        private const int MAP_LABEL_PAD_X_BASE = 6;
        private const int MAP_LABEL_PAD_Y_BASE = 2;
        private const int MAP_BEACON_R_BASE = 5;
        private const float MIN_BLOCK_PX = 4f;

        private const string ICON_TASK_DONE = "!";
        private const string ICON_PLACEHOLDER = "*";

        private static readonly string[] TOOL_KEYS = { "GAMESETTINGS", "SETTINGS", "PAUSE", "HELP", "SAFEEXIT" };
        private static readonly string[] TOOL_LABELS_DEFAULT = { "⚙", "\U0001F527", "Ⅱ", "?", "×" };
        private static readonly string[] TOOL_LABELS_PAUSED = { "⚙", "\U0001F527", "▶", "?", "×" };
        private const int IDX_PAUSE = 2;

        private static readonly string[] LEGACY_TYPES = { "task", "announce" };

        private enum HitKind
        {
            None,
            Tool,
            MapCard,
            QuestMap,
            QuestEquip,
            QuestTask,
            Notice,
            JukeboxPause,
            JukeboxExpand
        }

        private struct HitInfo
        {
            public HitKind Kind;
            public int Index;
        }

        private enum NoticeMode { Idle, Flash, TaskDone }

        private class FlashItem
        {
            public string Text;
            public string Icon;
        }

        private readonly Control _anchor;
        private readonly LauncherCommandRouter _router;
        private readonly MapHudDataCatalog _catalog;
        private readonly FlashCoordinateMapper _mapper;
        private readonly Action _onTogglePause;
        private readonly Action _onExpand;

        private volatile bool _gameReady;
        private volatile bool _paused;

        private string _mapMode = "0";
        private string _mapHotspotId = "";
        private MapHudHotspotEntry _mapEntry;
        private bool _mapCollapsed;

        private volatile bool _taskDone;
        private volatile bool _navigable;
        private string _deliverHotspotId = "";

        private readonly Queue<FlashItem> _flashQueue = new Queue<FlashItem>();
        private readonly object _flashLock = new object();
        private FlashItem _activeFlash;
        private int _flashElapsedMs;
        private string _noticeText = "";
        private string _noticeIcon = ICON_PLACEHOLDER;

        private string _bgmTitle = "";
        private bool _disableVisualizers;
        private readonly float[] _peakL = new float[HISTORY];
        private readonly float[] _peakR = new float[HISTORY];
        private int _peakIdx;
        private int _peakLen;
        private int _peakAccumMs;
        private int _playPollAccumMs;
        private volatile bool _isPlaying;
        private volatile bool _isPaused;

        private HitInfo _hover;
        private HitInfo _down;

        public event EventHandler BoundsOrVisibilityChanged;
        public event EventHandler RepaintRequested;
        public event EventHandler AnimationStateChanged;

        public RightContextWidget(
            Control anchor,
            LauncherCommandRouter router,
            MapHudDataCatalog catalog,
            Action onTogglePause,
            Action onExpand)
        {
            if (anchor == null) throw new ArgumentNullException("anchor");
            if (router == null) throw new ArgumentNullException("router");
            _anchor = anchor;
            _router = router;
            _catalog = catalog;
            _onTogglePause = onTogglePause;
            _onExpand = onExpand;
            _mapper = new FlashCoordinateMapper(anchor, 1024f, 576f);
            _hover.Kind = HitKind.None;
            _down.Kind = HitKind.None;
            _anchor.Resize += delegate { FireBounds(); };
            RebuildNoticeText();
        }

        private float Scale { get { return WidgetScaler.GetScale(_mapper); } }

        private bool IsMapModeRenderable
        {
            get { return _mapMode == "1" || _mapMode == "2"; }
        }

        private bool MapAvailable
        {
            get
            {
                if (_catalog == null || !_catalog.IsAvailable) return false;
                if (!IsMapModeRenderable) return false;
                if (string.IsNullOrEmpty(_mapHotspotId)) return false;
                return _mapEntry != null && _mapEntry.Outline != null && _mapEntry.Outline.ViewportRect.HasValue;
            }
        }

        private bool ShowMapSection
        {
            get { return _gameReady && !_mapCollapsed && MapAvailable; }
        }

        private NoticeMode CurrentNoticeMode
        {
            get
            {
                if (!_gameReady) return NoticeMode.Idle;
                if (_activeFlash != null) return NoticeMode.Flash;
                if (_taskDone) return NoticeMode.TaskDone;
                return NoticeMode.Idle;
            }
        }

        private bool ShowNotice
        {
            get { return CurrentNoticeMode != NoticeMode.Idle; }
        }

        public bool Visible { get { return _gameReady; } }

        public Rectangle ScreenBounds
        {
            get
            {
                if (!Visible) return Rectangle.Empty;
                if (_anchor == null || !_anchor.IsHandleCreated) return Rectangle.Empty;
                return RightHudLayout.GetClusterRect(_anchor, _mapper, ShowMapSection, ShowNotice, true);
            }
        }

        public bool WantsAnimationTick
        {
            get
            {
                if (!Visible) return false;
                if (_activeFlash != null) return true;
                if (!string.IsNullOrEmpty(_bgmTitle) && !_isPaused && !_disableVisualizers) return true;
                return false;
            }
        }

        public void Tick(int deltaMs)
        {
            if (!Visible) return;
            bool repaint = false;
            bool tickDirty = false;

            if (_activeFlash != null)
            {
                _flashElapsedMs += deltaMs;
                if (_flashElapsedMs >= NOTICE_MS)
                {
                    _activeFlash = null;
                    _flashElapsedMs = 0;
                    PumpFlashOrFallback();
                    FireBounds();
                    tickDirty = true;
                }
                repaint = true;
            }

            if (!string.IsNullOrEmpty(_bgmTitle) && !_isPaused)
            {
                _playPollAccumMs += deltaMs;
                if (_playPollAccumMs >= PLAY_POLL_MS)
                {
                    _playPollAccumMs = 0;
                    int playingFlag = SafeIsPlaying();
                    bool nowPlaying = playingFlag == 1;
                    if (nowPlaying != _isPlaying)
                    {
                        _isPlaying = nowPlaying;
                        if (nowPlaying) _isPaused = false;
                        repaint = true;
                    }
                }

                if (_isPlaying && !_disableVisualizers)
                {
                    _peakAccumMs += deltaMs;
                    if (_peakAccumMs >= MINI_RENDER_MS)
                    {
                        _peakAccumMs = 0;
                        float l, r;
                        SafeGetPeak(out l, out r);
                        InjectPeakSample(l, r);
                        repaint = true;
                    }
                }
            }
            else
            {
                _peakAccumMs = 0;
                _playPollAccumMs = 0;
            }

            if (repaint) FireRepaint();
            if (tickDirty || !WantsAnimationTick) FireAnimState();
        }

        public void Paint(Graphics g, float dpr, Point hudOrigin)
        {
            if (!Visible) return;
            Rectangle viewport = RightHudLayout.GetViewportRect(_anchor, _mapper);
            if (viewport.Width <= 0 || viewport.Height <= 0) return;
            float scale = RightHudLayout.ScaleForViewport(viewport);
            bool showMap = ShowMapSection;
            bool showNotice = ShowNotice;

            Rectangle tools = RightHudLayout.TopToolsRectFromViewport(viewport, scale);
            Rectangle context = RightHudLayout.ContextPanelRectFromViewport(viewport, scale, showMap, showNotice);
            Rectangle map = RightHudLayout.MapRectFromContext(context, scale, showMap);
            Rectangle row = RightHudLayout.QuestRowRectFromContext(context, scale, showMap);
            Rectangle notice = RightHudLayout.QuestNoticeRectFromContext(context, scale, showMap, showNotice);
            Rectangle jukebox = RightHudLayout.JukeboxRectFromViewport(viewport, scale, showMap, showNotice);

            tools.Offset(-hudOrigin.X, -hudOrigin.Y);
            context.Offset(-hudOrigin.X, -hudOrigin.Y);
            map.Offset(-hudOrigin.X, -hudOrigin.Y);
            row.Offset(-hudOrigin.X, -hudOrigin.Y);
            notice.Offset(-hudOrigin.X, -hudOrigin.Y);
            jukebox.Offset(-hudOrigin.X, -hudOrigin.Y);

            SmoothingMode prevSmooth = g.SmoothingMode;
            TextRenderingHint prevHint = g.TextRenderingHint;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = TextRenderingHint.AntiAlias;
            try
            {
                PaintTools(g, tools, scale);
                PaintContextBackground(g, context);
                if (showMap) PaintMapCard(g, map, scale);
                PaintQuestRow(g, row, scale);
                if (showNotice) PaintNotice(g, notice, scale);
                PaintJukebox(g, jukebox, scale);
            }
            finally
            {
                g.SmoothingMode = prevSmooth;
                g.TextRenderingHint = prevHint;
            }
        }

        private void PaintTools(Graphics g, Rectangle r, float scale)
        {
            if (r.Width <= 0 || r.Height <= 0) return;
            int btnW = WidgetScaler.Px(RightHudLayout.ToolButtonWidthBase, scale);
            string[] labels = _paused ? TOOL_LABELS_PAUSED : TOOL_LABELS_DEFAULT;
            using (SolidBrush bg = new SolidBrush(Color.FromArgb(209, 24, 24, 26)))
            using (SolidBrush bgHover = new SolidBrush(Color.FromArgb(229, 60, 60, 64)))
            using (SolidBrush bgPaused = new SolidBrush(Color.FromArgb(229, 80, 20, 20)))
            using (SolidBrush fg = new SolidBrush(Color.FromArgb(178, 255, 255, 255)))
            using (SolidBrush fgHover = new SolidBrush(Color.White))
            using (SolidBrush fgPaused = new SolidBrush(Color.FromArgb(255, 255, 102, 102)))
            using (Pen border = new Pen(Color.FromArgb(31, 255, 255, 255)))
            using (Font font = new Font("Segoe UI Symbol", WidgetScaler.Pxf(15f, scale), FontStyle.Regular, GraphicsUnit.Pixel))
            using (StringFormat fmt = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center })
            {
                for (int i = 0; i < TOOL_KEYS.Length; i++)
                {
                    int x = r.X + i * btnW;
                    int w = (i == TOOL_KEYS.Length - 1) ? r.Right - x : btnW;
                    Rectangle btn = new Rectangle(x, r.Y, w, r.Height);
                    bool hover = _hover.Kind == HitKind.Tool && _hover.Index == i;
                    bool paused = _paused && i == IDX_PAUSE;
                    Brush bgBrush = paused ? bgPaused : (hover ? bgHover : (Brush)bg);
                    Brush fgBrush = paused ? fgPaused : (hover ? fgHover : (Brush)fg);
                    g.FillRectangle(bgBrush, btn);
                    g.DrawLine(border, btn.X, btn.Bottom - 1, btn.Right - 1, btn.Bottom - 1);
                    if (i == 0) g.DrawLine(border, btn.X, btn.Y, btn.X, btn.Bottom - 1);
                    if (i == TOOL_KEYS.Length - 1) g.DrawLine(border, btn.Right - 1, btn.Y, btn.Right - 1, btn.Bottom - 1);
                    g.DrawString(labels[i], font, fgBrush, btn, fmt);
                }
            }
        }

        private void PaintContextBackground(Graphics g, Rectangle r)
        {
            if (r.Width <= 0 || r.Height <= 0) return;
            using (SolidBrush bg = new SolidBrush(Color.FromArgb(196, 20, 22, 24)))
            using (Pen border = new Pen(Color.FromArgb(36, 255, 255, 255)))
            {
                g.FillRectangle(bg, r);
                g.DrawRectangle(border, r.X, r.Y, r.Width - 1, r.Height - 1);
            }
        }

        private void PaintMapCard(Graphics g, Rectangle card, float scale)
        {
            if (card.Width <= 0 || card.Height <= 0 || _mapEntry == null || _mapEntry.Outline == null) return;
            MapHudWidget.ThemeColors theme = MapHudWidget.ResolveTheme(_mapEntry.Meta != null ? _mapEntry.Meta.Group : null);
            int radius = WidgetScaler.Px(8, scale);
            bool hover = _hover.Kind == HitKind.MapCard;
            using (GraphicsPath p = MakeRoundedRect(card, radius))
            using (LinearGradientBrush bg = new LinearGradientBrush(
                new Rectangle(card.X, card.Y, card.Width, card.Height + 1),
                Color.FromArgb(hover ? 245 : 228, theme.StageA),
                Color.FromArgb(hover ? 245 : 236, theme.StageB),
                LinearGradientMode.Vertical))
            using (Pen border = new Pen(Color.FromArgb(hover ? 104 : 58, theme.Accent)))
            {
                g.FillPath(bg, p);
                g.DrawPath(border, p);
            }

            Rectangle body = Rectangle.Inflate(card, -WidgetScaler.Px(MAP_BODY_INSET_BASE, scale), -WidgetScaler.Px(MAP_BODY_INSET_BASE, scale));
            PaintMapBody(g, body, theme, scale);
            PaintMapLabel(g, card, theme, scale);
        }

        private void PaintMapBody(Graphics g, Rectangle body, MapHudWidget.ThemeColors theme, float scale)
        {
            MapHudOutline outline = _mapEntry != null ? _mapEntry.Outline : null;
            MapHudWidget.PaintHudOutline(g, body, outline,
                _mapEntry != null ? _mapEntry.Meta : null,
                theme, scale, MIN_BLOCK_PX, WidgetScaler.Pxf(MAP_BEACON_R_BASE, scale));
        }

        private void PaintMapLabel(Graphics g, Rectangle card, MapHudWidget.ThemeColors theme, float scale)
        {
            string pageLabel = _mapEntry.Meta != null ? (_mapEntry.Meta.PageLabel ?? "") : "";
            string spotLabel = _mapEntry.Meta != null ? (_mapEntry.Meta.Label ?? "") : "";
            string text;
            if (string.IsNullOrEmpty(pageLabel)) text = spotLabel;
            else if (string.IsNullOrEmpty(spotLabel)) text = pageLabel;
            else text = pageLabel + " · " + spotLabel;
            if (string.IsNullOrEmpty(text)) return;

            int padX = WidgetScaler.Px(MAP_LABEL_PAD_X_BASE, scale);
            int padY = WidgetScaler.Px(MAP_LABEL_PAD_Y_BASE, scale);
            int margin = WidgetScaler.Px(6, scale);
            int maxW = Math.Max(1, card.Width - margin * 2);
            using (Font font = new Font("Microsoft YaHei", WidgetScaler.Pxf(11.5f, scale), FontStyle.Bold, GraphicsUnit.Pixel))
            using (StringFormat fmt = new StringFormat(StringFormatFlags.NoWrap)
                   { Alignment = StringAlignment.Near, LineAlignment = StringAlignment.Center, Trimming = StringTrimming.EllipsisCharacter })
            {
                SizeF measured = g.MeasureString(text, font, maxW, fmt);
                int pillW = Math.Min(maxW, (int)Math.Ceiling(measured.Width) + padX * 2);
                int pillH = (int)Math.Ceiling(measured.Height) + padY * 2;
                Rectangle pill = new Rectangle(card.X + margin, card.Y + margin, pillW, pillH);
                using (GraphicsPath pp = MakeRoundedRect(pill, pillH / 2))
                using (LinearGradientBrush pb = new LinearGradientBrush(pill,
                    Color.FromArgb(196, theme.StageA), Color.FromArgb(232, theme.StageB), LinearGradientMode.Vertical))
                using (Pen pe = new Pen(Color.FromArgb(96, theme.Accent)))
                using (SolidBrush textBrush = new SolidBrush(Color.FromArgb(238, 246, 248, 250)))
                {
                    g.FillPath(pb, pp);
                    g.DrawPath(pe, pp);
                    Rectangle textRect = new Rectangle(pill.X + padX, pill.Y, Math.Max(1, pill.Width - padX * 2), pill.Height);
                    g.DrawString(text, font, textBrush, textRect, fmt);
                }
            }
        }

        private void PaintQuestRow(Graphics g, Rectangle r, float scale)
        {
            if (r.Width <= 0 || r.Height <= 0) return;
            string[] labels = { (_mapCollapsed ? "▸ 地图" : "▾ 地图"), "☰ 装备", "☰ 任务" };
            HitKind[] kinds = { HitKind.QuestMap, HitKind.QuestEquip, HitKind.QuestTask };
            int colW = r.Width / 3;
            using (SolidBrush bg = new SolidBrush(Color.FromArgb(214, 24, 24, 26)))
            using (SolidBrush bgHover = new SolidBrush(Color.FromArgb(232, 44, 48, 52)))
            using (SolidBrush fg = new SolidBrush(Color.FromArgb(205, 235, 238, 240)))
            using (SolidBrush fgDisabled = new SolidBrush(Color.FromArgb(105, 235, 238, 240)))
            using (Pen border = new Pen(Color.FromArgb(31, 255, 255, 255)))
            using (Font font = new Font("Microsoft YaHei", WidgetScaler.Pxf(12f, scale), FontStyle.Regular, GraphicsUnit.Pixel))
            using (StringFormat fmt = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center, Trimming = StringTrimming.EllipsisCharacter })
            {
                for (int i = 0; i < labels.Length; i++)
                {
                    int x = r.X + i * colW;
                    int w = (i == labels.Length - 1) ? r.Right - x : colW;
                    Rectangle cell = new Rectangle(x, r.Y, w, r.Height);
                    bool hover = _hover.Kind == kinds[i];
                    g.FillRectangle(hover ? bgHover : bg, cell);
                    if (i > 0) g.DrawLine(border, cell.X, cell.Y + 3, cell.X, cell.Bottom - 4);
                    bool dimMap = i == 0 && !MapAvailable;
                    g.DrawString(labels[i], font, dimMap ? fgDisabled : (Brush)fg, cell, fmt);
                }
                g.DrawLine(border, r.X, r.Y, r.Right - 1, r.Y);
                g.DrawLine(border, r.X, r.Bottom - 1, r.Right - 1, r.Bottom - 1);
            }
        }

        private void PaintNotice(Graphics g, Rectangle r, float scale)
        {
            if (r.Width <= 0 || r.Height <= 0) return;
            NoticeMode mode = CurrentNoticeMode;
            int iconW = WidgetScaler.Px(ICON_W_BASE, scale);
            int pad = WidgetScaler.Px(NOTICE_TEXT_PAD_BASE, scale);
            int arrowW = WidgetScaler.Px(NOTICE_ARROW_W_BASE, scale);
            bool showArrow = mode == NoticeMode.TaskDone && CanDeliver();
            bool hover = _hover.Kind == HitKind.Notice;

            Color bgTop;
            Color bgBottom;
            if (mode == NoticeMode.Flash)
            {
                bgTop = Color.FromArgb(235, 60, 44, 20);
                bgBottom = Color.FromArgb(229, 28, 22, 14);
            }
            else
            {
                bgTop = hover ? Color.FromArgb(240, 48, 28, 28) : Color.FromArgb(235, 34, 22, 22);
                bgBottom = hover ? Color.FromArgb(235, 26, 18, 20) : Color.FromArgb(229, 20, 14, 16);
            }
            using (LinearGradientBrush bg = new LinearGradientBrush(r, bgTop, bgBottom, LinearGradientMode.Vertical))
                g.FillRectangle(bg, r);

            Rectangle iconRect = new Rectangle(r.X, r.Y, iconW, r.Height);
            Rectangle textRect = new Rectangle(iconRect.Right + pad, r.Y,
                Math.Max(1, r.Width - iconW - pad * 2 - (showArrow ? arrowW : 0)), r.Height);
            Color iconColor = mode == NoticeMode.Flash
                ? Color.FromArgb(255, 255, 220, 130)
                : (hover ? Color.FromArgb(255, 255, 200, 80) : Color.FromArgb(255, 255, 175, 50));
            Color textColor = mode == NoticeMode.Flash
                ? Color.FromArgb(229, 255, 220, 150)
                : (hover ? Color.FromArgb(255, 255, 215, 110) : Color.FromArgb(229, 255, 200, 80));

            using (Pen sep = new Pen(Color.FromArgb(31, 255, 255, 255)))
            using (Font font = new Font("Microsoft YaHei", WidgetScaler.Pxf(11f, scale), FontStyle.Regular, GraphicsUnit.Pixel))
            using (SolidBrush iconBrush = new SolidBrush(iconColor))
            using (SolidBrush textBrush = new SolidBrush(textColor))
            using (StringFormat center = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center })
            using (StringFormat textFmt = new StringFormat(StringFormatFlags.NoWrap)
                   { Alignment = StringAlignment.Near, LineAlignment = StringAlignment.Center, Trimming = StringTrimming.EllipsisCharacter })
            {
                g.DrawLine(sep, iconRect.Right, r.Y + 2, iconRect.Right, r.Bottom - 3);
                g.DrawString(_noticeIcon, font, iconBrush, iconRect, center);
                g.DrawString(_noticeText, font, textBrush, textRect, textFmt);
                if (showArrow)
                {
                    Rectangle arrowRect = new Rectangle(r.Right - arrowW, r.Y, arrowW, r.Height);
                    using (SolidBrush arrowBg = new SolidBrush(Color.FromArgb(48, 24, 36, 44)))
                    using (SolidBrush arrowBrush = new SolidBrush(hover ? Color.FromArgb(255, 223, 246, 255) : Color.FromArgb(229, 160, 226, 255)))
                    {
                        g.FillRectangle(arrowBg, arrowRect);
                        g.DrawLine(sep, arrowRect.X, r.Y + 2, arrowRect.X, r.Bottom - 3);
                        g.DrawString("➤", font, arrowBrush, arrowRect, center);
                    }
                }
            }
        }

        private void PaintJukebox(Graphics g, Rectangle r, float scale)
        {
            if (r.Width <= 0 || r.Height <= 0) return;
            int pauseW = WidgetScaler.Px(JUKE_PAUSE_W_BASE, scale);
            int expandW = WidgetScaler.Px(JUKE_EXPAND_W_BASE, scale);
            int titlePad = WidgetScaler.Px(TITLE_PAD_BASE, scale);
            Rectangle pause = new Rectangle(r.X, r.Y, pauseW, r.Height);
            Rectangle expand = new Rectangle(r.Right - expandW, r.Y, expandW, r.Height);
            Rectangle title = new Rectangle(pause.Right, r.Y, Math.Max(1, r.Width - pauseW - expandW), r.Height);

            using (SolidBrush bg = new SolidBrush(Color.FromArgb(209, 24, 24, 26)))
                g.FillRectangle(bg, r);
            if (!string.IsNullOrEmpty(_bgmTitle) && _peakLen > 0 && !_disableVisualizers)
                DrawMiniWave(g, title);
            DrawJukeboxPause(g, pause, scale);
            DrawJukeboxTitle(g, title, titlePad, scale);
            DrawJukeboxExpand(g, expand, scale);
            using (Pen border = new Pen(Color.FromArgb(31, 255, 255, 255)))
            {
                g.DrawLine(border, pause.Right, r.Y + 2, pause.Right, r.Bottom - 3);
                g.DrawLine(border, expand.X, r.Y + 2, expand.X, r.Bottom - 3);
                g.DrawLine(border, r.X, r.Bottom - 1, r.Right - 1, r.Bottom - 1);
            }
        }

        private void DrawMiniWave(Graphics g, Rectangle area)
        {
            if (area.Width <= 0 || area.Height <= 0) return;
            float midY = area.Y + area.Height / 2f;
            float maxH = area.Height / 2f - 1f;
            float barW = (float)area.Width / HISTORY;
            for (int i = 0; i < _peakLen; i++)
            {
                int idx = (_peakIdx - _peakLen + i + HISTORY) % HISTORY;
                float lv = _peakL[idx];
                float rv = _peakR[idx];
                float age = (_peakLen - 1 - i) / (float)Math.Max(_peakLen - 1, 1);
                float alpha = (_isPlaying && !_isPaused) ? (0.2f + 0.5f * (1 - age)) : 0.1f;
                int aL = ClampByte(alpha * 255f);
                int aR = ClampByte(alpha * 0.7f * 255f);
                float x = area.X + i * barW;
                float hL = Math.Max(1f, lv * maxH);
                float hR = Math.Max(1f, rv * maxH);
                using (SolidBrush bL = new SolidBrush(Color.FromArgb(aL, 102, 204, 255)))
                using (SolidBrush bR = new SolidBrush(Color.FromArgb(aR, 150, 220, 255)))
                {
                    g.FillRectangle(bL, x, midY - hL, Math.Max(barW - 0.5f, 1f), hL);
                    g.FillRectangle(bR, x, midY, Math.Max(barW - 0.5f, 1f), hR);
                }
            }
        }

        private void DrawJukeboxPause(Graphics g, Rectangle r, float scale)
        {
            bool hover = _hover.Kind == HitKind.JukeboxPause;
            bool hasBgm = !string.IsNullOrEmpty(_bgmTitle);
            Color bg = hover && hasBgm ? Color.FromArgb(229, 60, 60, 64) : Color.FromArgb(209, 16, 16, 18);
            Color fg = hasBgm ? (hover ? Color.White : Color.FromArgb(229, 102, 204, 255)) : Color.FromArgb(102, 255, 255, 255);
            string icon = (_isPlaying && !_isPaused) ? "Ⅱ" : "▶";
            using (SolidBrush bgBrush = new SolidBrush(bg))
            using (SolidBrush fgBrush = new SolidBrush(fg))
            using (Font font = new Font("Segoe UI Symbol", WidgetScaler.Pxf(12f, scale), FontStyle.Regular, GraphicsUnit.Pixel))
            using (StringFormat fmt = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center })
            {
                g.FillRectangle(bgBrush, r);
                g.DrawString(icon, font, fgBrush, r, fmt);
            }
        }

        private void DrawJukeboxTitle(Graphics g, Rectangle r, int pad, float scale)
        {
            string text = string.IsNullOrEmpty(_bgmTitle) ? "未播放" : _bgmTitle;
            Color color = string.IsNullOrEmpty(_bgmTitle) ? Color.FromArgb(76, 255, 255, 255) : Color.FromArgb(178, 255, 255, 255);
            Rectangle textRect = new Rectangle(r.X + pad, r.Y, Math.Max(1, r.Width - pad * 2), r.Height);
            using (SolidBrush brush = new SolidBrush(color))
            using (Font font = new Font("Microsoft YaHei", WidgetScaler.Pxf(11f, scale), FontStyle.Regular, GraphicsUnit.Pixel))
            using (StringFormat fmt = new StringFormat(StringFormatFlags.NoWrap)
                   { Alignment = StringAlignment.Near, LineAlignment = StringAlignment.Center, Trimming = StringTrimming.EllipsisCharacter })
            {
                g.DrawString(text, font, brush, textRect, fmt);
            }
        }

        private void DrawJukeboxExpand(Graphics g, Rectangle r, float scale)
        {
            bool hover = _hover.Kind == HitKind.JukeboxExpand;
            using (SolidBrush bg = new SolidBrush(hover ? Color.FromArgb(229, 60, 60, 64) : Color.FromArgb(209, 16, 16, 18)))
            using (SolidBrush fg = new SolidBrush(hover ? Color.White : Color.FromArgb(178, 255, 255, 255)))
            using (Font font = new Font("Segoe UI Symbol", WidgetScaler.Pxf(12f, scale), FontStyle.Regular, GraphicsUnit.Pixel))
            using (StringFormat fmt = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center })
            {
                g.FillRectangle(bg, r);
                g.DrawString("▼", font, fg, r, fmt);
            }
        }

        public bool TryHitTest(Point screenPt)
        {
            return Visible && ScreenBounds.Contains(screenPt);
        }

        public void OnMouseEvent(MouseEventArgs e, MouseEventKind kind)
        {
            Point pt = new Point(e.X, e.Y);
            HitInfo hit = HitTest(pt);
            switch (kind)
            {
                case MouseEventKind.Enter:
                case MouseEventKind.Move:
                    SetHover(hit);
                    break;
                case MouseEventKind.Leave:
                    SetHover(NoHit());
                    break;
                case MouseEventKind.Down:
                    _down = (e.Button == MouseButtons.Left) ? hit : NoHit();
                    break;
                case MouseEventKind.Up:
                    break;
                case MouseEventKind.Click:
                    if (SameHit(_down, hit) || _down.Kind == HitKind.None) DispatchHit(hit);
                    _down = NoHit();
                    break;
            }
        }

        private HitInfo HitTest(Point pt)
        {
            if (!Visible) return NoHit();
            Rectangle viewport = RightHudLayout.GetViewportRect(_anchor, _mapper);
            float scale = RightHudLayout.ScaleForViewport(viewport);
            bool showMap = ShowMapSection;
            bool showNotice = ShowNotice;
            Rectangle tools = RightHudLayout.TopToolsRectFromViewport(viewport, scale);
            if (tools.Contains(pt))
            {
                int btnW = WidgetScaler.Px(RightHudLayout.ToolButtonWidthBase, scale);
                int idx = (pt.X - tools.X) / Math.Max(1, btnW);
                if (idx < 0) idx = 0;
                if (idx >= TOOL_KEYS.Length) idx = TOOL_KEYS.Length - 1;
                return Hit(HitKind.Tool, idx);
            }

            Rectangle context = RightHudLayout.ContextPanelRectFromViewport(viewport, scale, showMap, showNotice);
            Rectangle map = RightHudLayout.MapRectFromContext(context, scale, showMap);
            if (map.Contains(pt)) return Hit(HitKind.MapCard, 0);
            Rectangle row = RightHudLayout.QuestRowRectFromContext(context, scale, showMap);
            if (row.Contains(pt))
            {
                int colW = Math.Max(1, row.Width / 3);
                int idx = (pt.X - row.X) / colW;
                if (idx <= 0) return Hit(HitKind.QuestMap, 0);
                if (idx == 1) return Hit(HitKind.QuestEquip, 0);
                return Hit(HitKind.QuestTask, 0);
            }
            Rectangle notice = RightHudLayout.QuestNoticeRectFromContext(context, scale, showMap, showNotice);
            if (notice.Contains(pt)) return Hit(HitKind.Notice, 0);
            Rectangle jukebox = RightHudLayout.JukeboxRectFromViewport(viewport, scale, showMap, showNotice);
            if (jukebox.Contains(pt))
            {
                int pauseW = WidgetScaler.Px(JUKE_PAUSE_W_BASE, scale);
                int expandW = WidgetScaler.Px(JUKE_EXPAND_W_BASE, scale);
                if (pt.X < jukebox.X + pauseW) return Hit(HitKind.JukeboxPause, 0);
                if (pt.X >= jukebox.Right - expandW) return Hit(HitKind.JukeboxExpand, 0);
            }
            return NoHit();
        }

        private void DispatchHit(HitInfo hit)
        {
            try
            {
                switch (hit.Kind)
                {
                    case HitKind.Tool:
                        if (hit.Index >= 0 && hit.Index < TOOL_KEYS.Length) _router.Dispatch(TOOL_KEYS[hit.Index]);
                        break;
                    case HitKind.MapCard:
                        _router.Dispatch("TASK_MAP");
                        break;
                    case HitKind.QuestMap:
                        _router.Dispatch("MAPHUD_TOGGLE");
                        break;
                    case HitKind.QuestEquip:
                        _router.Dispatch("EQUIP_UI");
                        break;
                    case HitKind.QuestTask:
                        _router.Dispatch("TASK_UI");
                        break;
                    case HitKind.Notice:
                        DispatchNoticeClick();
                        break;
                    case HitKind.JukeboxPause:
                        HandlePauseClick();
                        break;
                    case HitKind.JukeboxExpand:
                        HandleExpandClick();
                        break;
                }
            }
            catch (Exception ex)
            {
                LogManager.Log("[RightContextWidget] dispatch failed kind=" + hit.Kind + " ex=" + ex.Message);
            }
        }

        private void DispatchNoticeClick()
        {
            if (CanDeliver())
            {
                string raw = "{\"hotspotId\":\"" + EscapeJson(_deliverHotspotId) + "\"}";
                _router.Dispatch("TASK_DELIVER", raw);
            }
            else
            {
                _router.Dispatch("TASK_UI");
            }
        }

        private void HandlePauseClick()
        {
            if (string.IsNullOrEmpty(_bgmTitle)) return;
            _isPaused = !_isPaused;
            try { if (_onTogglePause != null) _onTogglePause(); }
            catch (Exception ex) { LogManager.Log("[RightContextWidget] togglePause failed ex=" + ex.Message); }
            FireRepaint();
            FireAnimState();
        }

        private void HandleExpandClick()
        {
            try { if (_onExpand != null) _onExpand(); }
            catch (Exception ex) { LogManager.Log("[RightContextWidget] expand failed ex=" + ex.Message); }
        }

        private void SetHover(HitInfo hit)
        {
            if (SameHit(_hover, hit)) return;
            _hover = hit;
            FireRepaint();
        }

        public void OnUiDataChanged(IReadOnlyDictionary<string, string> snapshot, ISet<string> changedKeys)
        {
            bool boundsDirty = false;
            bool repaintDirty = false;
            bool tickDirty = false;
            bool textDirty = false;
            string piece;

            if (changedKeys.Contains("s") && snapshot.TryGetValue("s", out piece))
            {
                bool ready = TopRightToolsWidget.ParseUiBoolValue(piece);
                if (ready != _gameReady)
                {
                    _gameReady = ready;
                    if (!ready) ResetForNotReady();
                    boundsDirty = true;
                    tickDirty = true;
                    textDirty = true;
                }
            }
            if (changedKeys.Contains("p") && snapshot.TryGetValue("p", out piece))
            {
                bool paused = TopRightToolsWidget.ParseUiBoolValue(piece);
                if (paused != _paused) { _paused = paused; repaintDirty = true; }
            }
            if (changedKeys.Contains("mm") && snapshot.TryGetValue("mm", out piece))
            {
                string nextMode = MapHudWidget.SanitizeMode(MapHudWidget.StripPrefix(piece, "mm"));
                if (nextMode != _mapMode)
                {
                    _mapMode = nextMode;
                    boundsDirty = true;
                    textDirty = true;
                }
            }
            if (changedKeys.Contains("mh") && snapshot.TryGetValue("mh", out piece))
            {
                string nextHotspot = MapHudWidget.StripPrefix(piece, "mh") ?? "";
                if (nextHotspot != _mapHotspotId)
                {
                    _mapHotspotId = nextHotspot;
                    _mapEntry = string.IsNullOrEmpty(_mapHotspotId) || _catalog == null ? null : _catalog.GetEntry(_mapHotspotId);
                    if (_mapEntry == null && !string.IsNullOrEmpty(_mapHotspotId))
                        LogManager.Log("[RightContextWidget] map hotspot not in catalog: " + _mapHotspotId);
                    boundsDirty = true;
                }
            }
            if (changedKeys.Contains("td") && snapshot.TryGetValue("td", out piece))
            {
                bool nextDone = TopRightToolsWidget.ParseUiBoolValue(piece);
                if (nextDone != _taskDone)
                {
                    _taskDone = nextDone;
                    boundsDirty = true;
                    textDirty = true;
                }
            }
            if (changedKeys.Contains("tdh") && snapshot.TryGetValue("tdh", out piece))
            {
                string next = StripPrefix(piece, "tdh");
                if (next != _deliverHotspotId)
                {
                    _deliverHotspotId = next ?? "";
                    repaintDirty = true;
                    textDirty = true;
                }
            }
            if (changedKeys.Contains("tdn") && snapshot.TryGetValue("tdn", out piece))
            {
                bool nextNav = TopRightToolsWidget.ParseUiBoolValue(piece);
                if (nextNav != _navigable)
                {
                    _navigable = nextNav;
                    repaintDirty = true;
                    textDirty = true;
                }
            }
            if (changedKeys.Contains("bgm") && snapshot.TryGetValue("bgm", out piece))
            {
                string next = StripPrefix(piece, "bgm");
                if (!string.Equals(next, _bgmTitle, StringComparison.Ordinal))
                {
                    bool wasEmpty = string.IsNullOrEmpty(_bgmTitle);
                    bool nowEmpty = string.IsNullOrEmpty(next);
                    _bgmTitle = next ?? "";
                    _peakLen = 0;
                    _peakIdx = 0;
                    repaintDirty = true;
                    if (wasEmpty != nowEmpty || !nowEmpty) tickDirty = true;
                }
            }
            if (changedKeys.Contains("pl") && snapshot.TryGetValue("pl", out piece))
            {
                int level = ParseIntPiece(piece, "pl", 0);
                bool disable = level >= 2;
                if (disable != _disableVisualizers)
                {
                    _disableVisualizers = disable;
                    repaintDirty = true;
                    tickDirty = true;
                }
            }

            if (textDirty) RebuildNoticeText();
            if (boundsDirty) FireBounds();
            else if (repaintDirty) FireRepaint();
            if (tickDirty) FireAnimState();
        }

        private void ResetForNotReady()
        {
            lock (_flashLock) { _flashQueue.Clear(); }
            _activeFlash = null;
            _flashElapsedMs = 0;
            _hover = NoHit();
            _down = NoHit();
            _peakLen = 0;
            _peakIdx = 0;
            _playPollAccumMs = 0;
            _bgmTitle = "";
            _isPlaying = false;
            _isPaused = false;
        }

        public IEnumerable<string> LegacyTypes { get { return LEGACY_TYPES; } }

        public void OnLegacyUiData(string type, string[] fields)
        {
            if (string.IsNullOrEmpty(type)) return;
            if (type == "task")
            {
                string name = (fields != null && fields.Length > 0) ? fields[0] : "";
                EnqueueFlash("新任务: " + name, ICON_PLACEHOLDER);
            }
            else if (type == "announce")
            {
                string text = (fields != null && fields.Length > 0) ? fields[0] : "";
                EnqueueFlash(text, ICON_PLACEHOLDER);
            }
        }

        private void EnqueueFlash(string text, string icon)
        {
            if (string.IsNullOrEmpty(text)) return;
            FlashItem item = new FlashItem { Text = text, Icon = icon };
            lock (_flashLock) { _flashQueue.Enqueue(item); }
            if (_activeFlash == null)
            {
                PumpFlashOrFallback();
                FireBounds();
            }
            FireAnimState();
        }

        private void PumpFlashOrFallback()
        {
            FlashItem next = null;
            lock (_flashLock) { if (_flashQueue.Count > 0) next = _flashQueue.Dequeue(); }
            if (next != null)
            {
                _activeFlash = next;
                _flashElapsedMs = 0;
                _noticeText = next.Text;
                _noticeIcon = next.Icon ?? ICON_PLACEHOLDER;
            }
            else
            {
                _activeFlash = null;
                _flashElapsedMs = 0;
                RebuildNoticeText();
            }
        }

        private void RebuildNoticeText()
        {
            if (_activeFlash != null) return;
            if (_taskDone)
            {
                _noticeIcon = ICON_TASK_DONE;
                _noticeText = BuildTaskDoneText();
            }
            else
            {
                _noticeIcon = ICON_PLACEHOLDER;
                _noticeText = "";
            }
        }

        internal bool CanDeliver()
        {
            if (_activeFlash != null) return false;
            if (!_taskDone) return false;
            if (!_navigable) return false;
            if (string.IsNullOrEmpty(_deliverHotspotId)) return false;
            if (_mapMode == "3") return false;
            return true;
        }

        internal string BuildTaskDoneText()
        {
            if (CanDeliver()) return "任务已达成 · 可交付";
            if (_mapMode == "3") return "任务已达成 · 战后交付";
            if (string.IsNullOrEmpty(_deliverHotspotId)) return "任务已达成 · 暂无交付目标";
            if (!_navigable) return "任务已达成 · 交付点未解锁";
            return "任务已达成";
        }

        public void SetMapCollapsed(bool collapsed)
        {
            if (_mapCollapsed == collapsed) return;
            _mapCollapsed = collapsed;
            FireBounds();
        }

        public void ToggleMapCollapsed()
        {
            SetMapCollapsed(!_mapCollapsed);
        }

        private static string StripPrefix(string fullPiece, string key)
        {
            if (string.IsNullOrEmpty(fullPiece)) return "";
            string prefix = key + ":";
            if (fullPiece.StartsWith(prefix, StringComparison.Ordinal))
                return fullPiece.Substring(prefix.Length);
            return fullPiece;
        }

        private static int ParseIntPiece(string fullPiece, string key, int fallback)
        {
            string val = StripPrefix(fullPiece, key);
            int parsed;
            if (int.TryParse(val, out parsed)) return parsed;
            return fallback;
        }

        private static string EscapeJson(string s)
        {
            if (string.IsNullOrEmpty(s)) return "";
            return s.Replace("\\", "\\\\").Replace("\"", "\\\"");
        }

        private static float ClampPeak(float v)
        {
            if (float.IsNaN(v) || float.IsInfinity(v) || v < 0f) return 0f;
            if (v > 1f) return 1f;
            return v;
        }

        private static int ClampByte(float v)
        {
            if (float.IsNaN(v) || float.IsInfinity(v)) return 0;
            if (v < 0f) return 0;
            if (v > 255f) return 255;
            return (int)Math.Round(v);
        }

        private static int SafeIsPlaying()
        {
            try { return AudioEngine.ma_bridge_bgm_is_playing(); }
            catch { return 0; }
        }

        private static void SafeGetPeak(out float l, out float r)
        {
            try { AudioEngine.ma_bridge_bgm_get_peak(out l, out r); }
            catch { l = 0f; r = 0f; }
        }

        private void InjectPeakSample(float l, float r)
        {
            _peakL[_peakIdx] = ClampPeak(l);
            _peakR[_peakIdx] = ClampPeak(r);
            _peakIdx = (_peakIdx + 1) % HISTORY;
            if (_peakLen < HISTORY) _peakLen++;
        }

        private static HitInfo Hit(HitKind kind, int index)
        {
            HitInfo h;
            h.Kind = kind;
            h.Index = index;
            return h;
        }

        private static HitInfo NoHit()
        {
            return Hit(HitKind.None, -1);
        }

        private static bool SameHit(HitInfo a, HitInfo b)
        {
            return a.Kind == b.Kind && a.Index == b.Index;
        }

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

        private void FireBounds()
        {
            EventHandler h = BoundsOrVisibilityChanged;
            if (h != null) h(this, EventArgs.Empty);
        }

        private void FireRepaint()
        {
            EventHandler h = RepaintRequested;
            if (h != null) h(this, EventArgs.Empty);
        }

        private void FireAnimState()
        {
            EventHandler h = AnimationStateChanged;
            if (h != null) h(this, EventArgs.Empty);
        }

        // ── test seams ──
        internal bool IsMapCollapsed { get { return _mapCollapsed; } }
        internal bool MapSectionVisibleForTest { get { return ShowMapSection; } }
        internal bool QuestNoticeVisibleForTest { get { return ShowNotice; } }
        internal bool HasActiveFlash { get { return _activeFlash != null; } }
        internal int FlashQueueCount { get { lock (_flashLock) { return _flashQueue.Count; } } }
        internal bool IsTaskDone { get { return _taskDone; } }
        internal bool IsNavigable { get { return _navigable; } }
        internal string DeliverHotspotId { get { return _deliverHotspotId; } }
        internal string MapMode { get { return _mapMode; } }
        internal string DisplayText { get { return _noticeText; } }
        internal string CurrentTitle { get { return _bgmTitle; } }
        internal bool IsPausedForTest { get { return _isPaused; } }
        internal bool DisableVisualizersForTest { get { return _disableVisualizers; } }
        internal int PeakHistoryLen { get { return _peakLen; } }
        internal void ForceGameReady(bool ready) { _gameReady = ready; }
        internal void ForceTaskDone(bool done) { _taskDone = done; RebuildNoticeText(); }
        internal void ForceMapMode(string mode) { _mapMode = MapHudWidget.SanitizeMode(mode); }
        internal void ForceMapHotspot(string hotspot)
        {
            _mapHotspotId = hotspot ?? "";
            _mapEntry = string.IsNullOrEmpty(_mapHotspotId) || _catalog == null ? null : _catalog.GetEntry(_mapHotspotId);
        }
        internal void ForceDeliverState(bool done, string hotspot, bool navigable, string mapMode)
        {
            _taskDone = done;
            _deliverHotspotId = hotspot ?? "";
            _navigable = navigable;
            _mapMode = MapHudWidget.SanitizeMode(mapMode);
            RebuildNoticeText();
        }
        internal void ForceBgmTitle(string title) { _bgmTitle = title ?? ""; }
        internal void ForceIsPlaying(bool playing) { _isPlaying = playing; }
        internal void ForceIsPaused(bool paused) { _isPaused = paused; }
        internal void ForceDisableVisualizers(bool disabled) { _disableVisualizers = disabled; }
        internal void InjectPeakSampleForTest(float l, float r) { InjectPeakSample(l, r); }
        internal void SimulatePauseClick() { HandlePauseClick(); }
        internal void SimulateExpandClick() { HandleExpandClick(); }
        internal void AdvanceFlashMs(int ms)
        {
            if (_activeFlash == null) return;
            _flashElapsedMs += ms;
            if (_flashElapsedMs >= NOTICE_MS)
            {
                _activeFlash = null;
                _flashElapsedMs = 0;
                PumpFlashOrFallback();
            }
        }
        internal enum ClickRoute { TaskDeliver, TaskUi }
        internal ClickRoute ResolveNoticeClickRoute()
        {
            return CanDeliver() ? ClickRoute.TaskDeliver : ClickRoute.TaskUi;
        }
        internal string ResolveQuestRowRoute(int index)
        {
            if (index == 0) return "MAPHUD_TOGGLE";
            if (index == 1) return "EQUIP_UI";
            if (index == 2) return "TASK_UI";
            return null;
        }
    }
}
