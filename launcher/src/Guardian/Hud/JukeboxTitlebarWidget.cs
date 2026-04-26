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
    /// 替代 web modules/jukebox.js 的标题栏（#jukebox-panel.collapsed 部分）。
    ///
    /// 渲染：
    /// - 暂停/播放按钮 + 当前曲名（marquee 滚动）+ 展开按钮
    /// - mini 波形作为标题区背景：实时读 ma_bridge_bgm_get_peak 维护 100 点 ring buffer，
    ///   ~100ms 一次重绘（与 web jukebox.js MINI_RENDER_MS 一致）
    ///
    /// 数据通路：
    /// - IUiDataConsumer 消费 bgm（曲名）/ s（gameReady）
    /// - 直接调 AudioEngine.ma_bridge_bgm_get_peak / is_playing 拉峰值与播放态（AudioEngine 是 internal，同程集）
    /// - pause/expand 走构造期注入的 Action，不在 widget 内调 AudioEngine 写状态——保留 WebOverlayForm._bgmPaused
    ///   单一权威源（HandleAudioTrackState 用它决定是否广播 jukeboxTrackEnd）
    ///
    /// request-frame：has-bgm AND playing AND !disableVisualizers → 16ms tick；否则只有 marquee 滚动时 enroll。
    /// </summary>
    public class JukeboxTitlebarWidget : INativeHudWidget, IUiDataConsumer
    {
        // 设计基准：web overlay.css #jukebox-panel
        //   top:138px right:80px width:170px (5*34) height:24px(header)
        // C# 实现略加 padding 让按钮区/文字区视觉松弛
        private const int BAR_W_BASE = 170;
        private const int BAR_H_BASE = 24;
        private const int BAR_TOP_OFFSET_BASE = 138;       // 紧贴 quest-notice-bar 下方
        private const int BAR_RIGHT_OFFSET_BASE = 0;
        private const int PAUSE_BTN_W_BASE = 28;           // 左侧 ▶/‖ 按钮
        private const int EXPAND_BTN_W_BASE = 22;          // 右侧展开 ▼
        private const int TITLE_PAD_BASE = 6;
        private const float TITLE_FONT_BASE_PX = 11f;
        private const float ICON_FONT_BASE_PX = 12f;

        private const int MINI_RENDER_MS = 100;             // 与 web jukebox.js 一致
        private const int MARQUEE_PX_PER_SEC = 50;
        private const int MARQUEE_DWELL_MS = 800;
        private const int HISTORY = 100;

        private readonly Control _anchor;
        private readonly FlashCoordinateMapper _mapper;
        private readonly Action _onTogglePause;
        private readonly Action _onExpand;

        private volatile bool _gameReady;
        private string _bgmTitle = "";
        private bool _disableVisualizers;        // 由 UiData "pl"（perf level）推导：>=2 关 visualizer

        // mini wave ring buffer
        private readonly float[] _peakL = new float[HISTORY];
        private readonly float[] _peakR = new float[HISTORY];
        private int _peakIdx;
        private int _peakLen;

        // 播放态（每 tick 从 AudioEngine 拉，缓存供 Paint 用）
        private volatile bool _isPlaying;
        private volatile bool _isPaused;        // 用户态本地镜像（点暂停按钮即翻转，AudioEngine 真值仍是 IsPlaying=0）

        // tick 节流
        private int _peakAccumMs;

        // 标题 marquee
        private float _marqueePhasePx;
        private bool _marqueeActive;
        private int _marqueeDwellMs;
        private float _measuredTitleW;          // 上次 paint 测得的宽（px，已经 scaled）；负数=未测过

        // hover
        private int _hoverButton = -1;          // 0=pause, 1=expand, -1=none

        public event EventHandler BoundsOrVisibilityChanged;
        public event EventHandler RepaintRequested;
        public event EventHandler AnimationStateChanged;

        public JukeboxTitlebarWidget(Control anchor, Action onTogglePause, Action onExpand)
        {
            if (anchor == null) throw new ArgumentNullException("anchor");
            _anchor = anchor;
            _onTogglePause = onTogglePause;
            _onExpand = onExpand;
            _mapper = new FlashCoordinateMapper(anchor, 1024f, 576f);
            _anchor.Resize += delegate { FireBounds(); };
            _measuredTitleW = -1f;
        }

        private float Scale { get { return WidgetScaler.GetScale(_mapper); } }
        private int BarW { get { return WidgetScaler.Px(BAR_W_BASE, Scale); } }
        private int BarH { get { return WidgetScaler.Px(BAR_H_BASE, Scale); } }

        public bool Visible { get { return _gameReady; } }

        public Rectangle ScreenBounds
        {
            get
            {
                if (!Visible) return Rectangle.Empty;
                if (_anchor == null || !_anchor.IsHandleCreated) return Rectangle.Empty;
                try
                {
                    Point origin = _anchor.PointToScreen(Point.Empty);
                    float vpX, vpY, vpW, vpH;
                    _mapper.CalcViewport(out vpX, out vpY, out vpW, out vpH);
                    int barW = BarW;
                    int barH = BarH;
                    int rightOffset = WidgetScaler.Px(BAR_RIGHT_OFFSET_BASE, Scale);
                    int topOffset = WidgetScaler.Px(BAR_TOP_OFFSET_BASE, Scale);
                    int x = origin.X + (int)vpX + Math.Max(0, (int)vpW - barW - rightOffset);
                    int y = origin.Y + (int)vpY + topOffset;
                    return new Rectangle(x, y, barW, barH);
                }
                catch { return Rectangle.Empty; }
            }
        }

        public bool WantsAnimationTick
        {
            get
            {
                if (!Visible) return false;
                if (_marqueeActive) return true;
                if (_isPlaying && !_isPaused && !_disableVisualizers) return true;
                return false;
            }
        }

        public void Tick(int deltaMs)
        {
            if (!Visible) return;
            bool repaint = false;

            // 1) 拉播放态（即使不展开也要更新，pause 按钮图标依赖 _isPlaying）
            int playingFlag = SafeIsPlaying();
            bool nowPlaying = playingFlag == 1;
            if (nowPlaying != _isPlaying)
            {
                _isPlaying = nowPlaying;
                if (nowPlaying) _isPaused = false; // 真正在响 → 解除暂停镜像
                repaint = true;
            }

            // 2) 节流读 peak
            if (_isPlaying && !_isPaused && !_disableVisualizers)
            {
                _peakAccumMs += deltaMs;
                if (_peakAccumMs >= MINI_RENDER_MS)
                {
                    _peakAccumMs = 0;
                    float l, r;
                    SafeGetPeak(out l, out r);
                    _peakL[_peakIdx] = ClampPeak(l);
                    _peakR[_peakIdx] = ClampPeak(r);
                    _peakIdx = (_peakIdx + 1) % HISTORY;
                    if (_peakLen < HISTORY) _peakLen++;
                    repaint = true;
                }
            }
            else
            {
                _peakAccumMs = 0;
            }

            // 3) marquee 推进
            if (_marqueeActive)
            {
                if (_marqueeDwellMs > 0)
                {
                    _marqueeDwellMs -= deltaMs;
                    if (_marqueeDwellMs < 0) _marqueeDwellMs = 0;
                }
                else
                {
                    _marqueePhasePx += MARQUEE_PX_PER_SEC * (deltaMs / 1000f);
                }
                repaint = true;
            }

            if (repaint) FireRepaint();
            // WantsAnimationTick 切换由 OnUiDataChanged / Click 主动 fire
        }

        public void Paint(Graphics g, float dpr, Point hudOrigin)
        {
            Rectangle r = ScreenBounds;
            if (r.Width <= 0 || r.Height <= 0) return;
            int localX = r.X - hudOrigin.X;
            int localY = r.Y - hudOrigin.Y;

            int pauseW = WidgetScaler.Px(PAUSE_BTN_W_BASE, Scale);
            int expandW = WidgetScaler.Px(EXPAND_BTN_W_BASE, Scale);
            int titlePad = WidgetScaler.Px(TITLE_PAD_BASE, Scale);

            // 区域划分：[pauseBtn][titleArea (mini wave 背景 + title)][expandBtn]
            Rectangle pauseRect = new Rectangle(localX, localY, pauseW, r.Height);
            Rectangle expandRect = new Rectangle(localX + r.Width - expandW, localY, expandW, r.Height);
            Rectangle titleRect = new Rectangle(pauseRect.Right, localY,
                Math.Max(1, r.Width - pauseW - expandW), r.Height);

            // 背景
            using (SolidBrush bg = new SolidBrush(Color.FromArgb(209, 24, 24, 26)))
                g.FillRectangle(bg, localX, localY, r.Width, r.Height);

            // mini wave 背景（仅在 has-bgm 时绘制）
            if (!string.IsNullOrEmpty(_bgmTitle) && _peakLen > 0 && !_disableVisualizers)
            {
                DrawMiniWave(g, titleRect);
            }

            // pause 按钮
            DrawPauseButton(g, pauseRect, dpr);

            // 标题文字
            DrawTitle(g, titleRect, titlePad);

            // expand 按钮
            DrawExpandButton(g, expandRect);

            // 边框
            using (Pen border = new Pen(Color.FromArgb(31, 255, 255, 255)))
            {
                g.DrawLine(border, pauseRect.Right, localY + 2, pauseRect.Right, localY + r.Height - 3);
                g.DrawLine(border, expandRect.X, localY + 2, expandRect.X, localY + r.Height - 3);
                g.DrawLine(border, localX, localY + r.Height - 1, localX + r.Width - 1, localY + r.Height - 1);
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
                int aL = (int)Math.Round(alpha * 255);
                int aR = (int)Math.Round(alpha * 0.7f * 255);
                if (aL < 0) aL = 0; if (aL > 255) aL = 255;
                if (aR < 0) aR = 0; if (aR > 255) aR = 255;
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

        private void DrawPauseButton(Graphics g, Rectangle rect, float dpr)
        {
            bool hover = _hoverButton == 0;
            bool hasBgm = !string.IsNullOrEmpty(_bgmTitle);
            // 有 BGM 时高亮（点了能用）；否则灰
            Color bg = hover && hasBgm
                ? Color.FromArgb(229, 60, 60, 64)
                : Color.FromArgb(209, 16, 16, 18);
            Color fg = hasBgm
                ? (hover ? Color.White : Color.FromArgb(229, 102, 204, 255))
                : Color.FromArgb(102, 255, 255, 255);
            using (SolidBrush bgBrush = new SolidBrush(bg))
                g.FillRectangle(bgBrush, rect);

            // 图标：playing && !paused → 暂停符号 ‖；否则 → 播放符号 ▶
            string icon = (_isPlaying && !_isPaused) ? "‖" : "▶";
            float iconPx = WidgetScaler.Pxf(ICON_FONT_BASE_PX, Scale);
            using (Font font = new Font("Segoe UI Symbol", iconPx, FontStyle.Regular, GraphicsUnit.Pixel))
            using (SolidBrush brush = new SolidBrush(fg))
            using (StringFormat fmt = new StringFormat
                { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center })
            {
                TextRenderingHint prevHint = g.TextRenderingHint;
                g.TextRenderingHint = TextRenderingHint.AntiAlias;
                try { g.DrawString(icon, font, brush, rect, fmt); }
                finally { g.TextRenderingHint = prevHint; }
            }
        }

        private void DrawExpandButton(Graphics g, Rectangle rect)
        {
            bool hover = _hoverButton == 1;
            Color bg = hover
                ? Color.FromArgb(229, 60, 60, 64)
                : Color.FromArgb(209, 16, 16, 18);
            Color fg = hover ? Color.White : Color.FromArgb(178, 255, 255, 255);
            using (SolidBrush bgBrush = new SolidBrush(bg))
                g.FillRectangle(bgBrush, rect);
            float iconPx = WidgetScaler.Pxf(ICON_FONT_BASE_PX, Scale);
            using (Font font = new Font("Segoe UI Symbol", iconPx, FontStyle.Regular, GraphicsUnit.Pixel))
            using (SolidBrush brush = new SolidBrush(fg))
            using (StringFormat fmt = new StringFormat
                { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center })
            {
                TextRenderingHint prevHint = g.TextRenderingHint;
                g.TextRenderingHint = TextRenderingHint.AntiAlias;
                try { g.DrawString("▼", font, brush, rect, fmt); }
                finally { g.TextRenderingHint = prevHint; }
            }
        }

        private void DrawTitle(Graphics g, Rectangle area, int titlePad)
        {
            string text = string.IsNullOrEmpty(_bgmTitle) ? "未播放" : _bgmTitle;
            Color textColor = string.IsNullOrEmpty(_bgmTitle)
                ? Color.FromArgb(76, 255, 255, 255)
                : Color.FromArgb(178, 255, 255, 255);

            float fontPx = WidgetScaler.Pxf(TITLE_FONT_BASE_PX, Scale);
            using (Font font = new Font("Microsoft YaHei", fontPx, FontStyle.Regular, GraphicsUnit.Pixel))
            using (SolidBrush brush = new SolidBrush(textColor))
            {
                Rectangle textRect = new Rectangle(area.X + titlePad, area.Y,
                    Math.Max(1, area.Width - 2 * titlePad), area.Height);

                TextRenderingHint prevHint = g.TextRenderingHint;
                g.TextRenderingHint = TextRenderingHint.AntiAlias;
                try
                {
                    SizeF measured = g.MeasureString(text, font);
                    _measuredTitleW = measured.Width;
                    if (measured.Width <= textRect.Width)
                    {
                        using (StringFormat fmt = new StringFormat
                            { Alignment = StringAlignment.Near, LineAlignment = StringAlignment.Center, FormatFlags = StringFormatFlags.NoWrap })
                            g.DrawString(text, font, brush, textRect, fmt);
                        EnsureMarqueeState(false);
                    }
                    else
                    {
                        float scrollDist = measured.Width - textRect.Width + WidgetScaler.Pxf(8f, Scale);
                        if (_marqueePhasePx > scrollDist)
                        {
                            _marqueePhasePx = 0;
                            _marqueeDwellMs = MARQUEE_DWELL_MS;
                        }
                        Region prevClip = g.Clip;
                        g.SetClip(textRect);
                        try
                        {
                            using (StringFormat fmt = new StringFormat
                                { Alignment = StringAlignment.Near, LineAlignment = StringAlignment.Center, FormatFlags = StringFormatFlags.NoWrap })
                                g.DrawString(text, font, brush,
                                    new RectangleF(textRect.X - _marqueePhasePx, textRect.Y, measured.Width + 4, textRect.Height), fmt);
                        }
                        finally { g.Clip = prevClip; }
                        EnsureMarqueeState(true);
                    }
                }
                finally { g.TextRenderingHint = prevHint; }
            }
        }

        private void EnsureMarqueeState(bool wantActive)
        {
            if (wantActive == _marqueeActive) return;
            _marqueeActive = wantActive;
            if (wantActive)
            {
                _marqueePhasePx = 0;
                _marqueeDwellMs = MARQUEE_DWELL_MS;
            }
            else
            {
                _marqueePhasePx = 0;
                _marqueeDwellMs = 0;
            }
            FireAnimState();
        }

        public bool TryHitTest(Point screenPt)
        {
            return ScreenBounds.Contains(screenPt);
        }

        public void OnMouseEvent(MouseEventArgs e, MouseEventKind kind)
        {
            Rectangle r = ScreenBounds;
            if (r.Width <= 0 || r.Height <= 0) return;
            int pauseW = WidgetScaler.Px(PAUSE_BTN_W_BASE, Scale);
            int expandW = WidgetScaler.Px(EXPAND_BTN_W_BASE, Scale);
            int relX = e.X - r.X;
            int idx;
            if (relX < 0) idx = -1;
            else if (relX < pauseW) idx = 0;
            else if (relX >= r.Width - expandW) idx = 1;
            else idx = -1;

            switch (kind)
            {
                case MouseEventKind.Move:
                case MouseEventKind.Enter:
                    SetHover(idx);
                    break;
                case MouseEventKind.Leave:
                    SetHover(-1);
                    break;
                case MouseEventKind.Click:
                    if (idx == 0) HandlePauseClick();
                    else if (idx == 1) HandleExpandClick();
                    break;
            }
        }

        private void SetHover(int idx)
        {
            if (_hoverButton == idx) return;
            _hoverButton = idx;
            FireRepaint();
        }

        private void HandlePauseClick()
        {
            // 仅在有 BGM 时有效；无 BGM 静默忽略（与 web 行为一致）
            if (string.IsNullOrEmpty(_bgmTitle)) return;
            // 翻转本地镜像，让 paint 立即看到新图标；AudioEngine 真实 pause/resume 由 _onTogglePause 完成
            _isPaused = !_isPaused;
            try { if (_onTogglePause != null) _onTogglePause(); }
            catch (Exception ex) { LogManager.Log("[JukeboxTitlebar] togglePause failed ex=" + ex.Message); }
            FireRepaint();
            FireAnimState(); // playing/pause 改变 → tick 需求可能变化
        }

        private void HandleExpandClick()
        {
            try { if (_onExpand != null) _onExpand(); }
            catch (Exception ex) { LogManager.Log("[JukeboxTitlebar] expand failed ex=" + ex.Message); }
        }

        public void OnUiDataChanged(IReadOnlyDictionary<string, string> snapshot, ISet<string> changedKeys)
        {
            bool boundsDirty = false;
            bool repaintDirty = false;
            bool tickDirty = false;
            string piece;

            if (changedKeys.Contains("s") && snapshot.TryGetValue("s", out piece))
            {
                bool ready = TopRightToolsWidget.ParseUiBoolValue(piece);
                if (ready != _gameReady)
                {
                    _gameReady = ready;
                    if (!ready)
                    {
                        // 复位
                        _hoverButton = -1;
                        _peakLen = 0;
                        _peakIdx = 0;
                        _bgmTitle = "";
                        _isPlaying = false;
                        _isPaused = false;
                        EnsureMarqueeState(false);
                    }
                    boundsDirty = true;
                    tickDirty = true;
                }
            }

            if (changedKeys.Contains("bgm") && snapshot.TryGetValue("bgm", out piece))
            {
                string next = StripPrefix(piece, "bgm");
                if (!string.Equals(next, _bgmTitle, StringComparison.Ordinal))
                {
                    _bgmTitle = next ?? "";
                    // 切歌：清 ring buffer + 重启 marquee dwell
                    _peakLen = 0;
                    _peakIdx = 0;
                    _marqueePhasePx = 0;
                    _marqueeDwellMs = MARQUEE_DWELL_MS;
                    _measuredTitleW = -1f;
                    repaintDirty = true;
                }
            }

            if (changedKeys.Contains("pl") && snapshot.TryGetValue("pl", out piece))
            {
                int level = ParseIntPiece(piece, "pl", 0);
                bool nextDisable = level >= 2;
                if (nextDisable != _disableVisualizers)
                {
                    _disableVisualizers = nextDisable;
                    repaintDirty = true;
                    tickDirty = true;
                }
            }

            if (boundsDirty) FireBounds();
            else if (repaintDirty) FireRepaint();
            if (tickDirty) FireAnimState();
        }

        // ── helpers ──

        internal static string StripPrefix(string fullPiece, string key)
        {
            if (string.IsNullOrEmpty(fullPiece)) return "";
            string prefix = key + ":";
            if (fullPiece.StartsWith(prefix, StringComparison.Ordinal))
                return fullPiece.Substring(prefix.Length);
            return fullPiece;
        }

        internal static int ParseIntPiece(string fullPiece, string key, int fallback)
        {
            string val = StripPrefix(fullPiece, key);
            int parsed;
            if (int.TryParse(val, out parsed)) return parsed;
            return fallback;
        }

        private static float ClampPeak(float v)
        {
            if (float.IsNaN(v) || float.IsInfinity(v) || v < 0f) return 0f;
            if (v > 1f) return 1f;
            return v;
        }

        // AudioEngine 调用包成 try/catch：DLL 失联时 widget 退化为静默不动
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

        private void FireBounds() { EventHandler h = BoundsOrVisibilityChanged; if (h != null) h(this, EventArgs.Empty); }
        private void FireRepaint() { EventHandler h = RepaintRequested; if (h != null) h(this, EventArgs.Empty); }
        private void FireAnimState() { EventHandler h = AnimationStateChanged; if (h != null) h(this, EventArgs.Empty); }

        // ── 单测可见 ──
        internal void ForceGameReady(bool ready) { _gameReady = ready; }
        internal void ForceIsPlaying(bool playing) { _isPlaying = playing; }
        internal void ForceIsPaused(bool paused) { _isPaused = paused; }
        internal void ForceBgmTitle(string title) { _bgmTitle = title ?? ""; }
        internal void ForceDisableVisualizers(bool d) { _disableVisualizers = d; }
        internal void InjectPeakSample(float l, float r)
        {
            _peakL[_peakIdx] = ClampPeak(l);
            _peakR[_peakIdx] = ClampPeak(r);
            _peakIdx = (_peakIdx + 1) % HISTORY;
            if (_peakLen < HISTORY) _peakLen++;
        }
        internal int PeakHistoryLen { get { return _peakLen; } }
        internal string CurrentTitle { get { return _bgmTitle; } }
        internal bool IsPlayingForTest { get { return _isPlaying; } }
        internal bool IsPausedForTest { get { return _isPaused; } }
        internal bool DisableVisualizersForTest { get { return _disableVisualizers; } }
        internal int HoverButtonForTest { get { return _hoverButton; } }
        internal bool MarqueeActiveForTest { get { return _marqueeActive; } }
        internal void SimulatePauseClick() { HandlePauseClick(); }
        internal void SimulateExpandClick() { HandleExpandClick(); }
    }
}
