using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.Windows.Forms;
using CF7Launcher.Guardian;

namespace CF7Launcher.Guardian.Hud
{
    /// <summary>
    /// 右上角工具条：GAMESETTINGS / SETTINGS / PAUSE / HELP / SAFEEXIT 五键。
    ///
    /// 替代 web overlay.html 的 #top-right-tools；click 直发 LauncherCommandRouter.Dispatch。
    /// 不持业务状态机：暂停字符切换由 UiData "p" 推送，game-ready 由 "s" 推送；
    /// SAFEEXIT 的存盘动画态留待 SafeExitPanelWidget（Phase 4.2）接管。
    /// </summary>
    public class TopRightToolsWidget : INativeHudWidget, IUiDataConsumer
    {
        // 设计基准：Flash 设计高度 576 时对应 web CSS 34×32 px。
        // 缩放 helper 统一到 WidgetScaler（与 WebView2 ZoomFactor 同源）。
        // 字号基数 16（web CSS 14）补 emoji 字体在 Pixel 单位下渲染偏小。
        private const int BTN_W_BASE = 38;
        private const int BTN_H_BASE = 32;
        private const float FONT_BASE_PX = 16f;

        private static readonly string[] KEYS = { "GAMESETTINGS", "SETTINGS", "PAUSE", "HELP", "SAFEEXIT" };
        private static readonly string[] LABELS_DEFAULT = { "⚙", "\U0001F527", "⏸", "?", "✕" };
        private static readonly string[] LABELS_PAUSED  = { "⚙", "\U0001F527", "▶", "?", "✕" };
        private const int IDX_PAUSE = 2;

        private readonly Control _anchor;
        private readonly LauncherCommandRouter _router;
        private readonly FlashCoordinateMapper _mapper;
        private volatile bool _gameReady;
        private volatile bool _paused;
        private int _hoverIndex = -1;

        public event EventHandler BoundsOrVisibilityChanged;
        public event EventHandler RepaintRequested;
        public event EventHandler AnimationStateChanged;

        public TopRightToolsWidget(Control anchor, LauncherCommandRouter router)
        {
            if (anchor == null) throw new ArgumentNullException("anchor");
            if (router == null) throw new ArgumentNullException("router");
            _anchor = anchor;
            _router = router;
            // 与 NotchOverlay/WebView2 viewport 同源（设计 1024x576），用于 letterbox 内对齐
            _mapper = new FlashCoordinateMapper(anchor, 1024f, 576f);
            _anchor.Resize += delegate { FireBounds(); };
        }

        private float Scale { get { return WidgetScaler.GetScale(_anchor); } }
        private int BtnW { get { return WidgetScaler.Px(BTN_W_BASE, Scale); } }
        private int BtnH { get { return WidgetScaler.Px(BTN_H_BASE, Scale); } }

        public Rectangle ScreenBounds
        {
            get
            {
                if (!_gameReady) return Rectangle.Empty;
                if (_anchor == null || !_anchor.IsHandleCreated) return Rectangle.Empty;
                try
                {
                    Point origin = _anchor.PointToScreen(Point.Empty);
                    float vpX, vpY, vpW, vpH;
                    _mapper.CalcViewport(out vpX, out vpY, out vpW, out vpH);
                    int btnW = BtnW;
                    int btnH = BtnH;
                    int totalW = btnW * KEYS.Length;
                    // 贴 viewport 右边缘（letterbox 黑边内），与 NotchOverlay 同坐标系
                    int x = origin.X + (int)vpX + Math.Max(0, (int)vpW - totalW);
                    int y = origin.Y + (int)vpY;
                    return new Rectangle(x, y, totalW, btnH);
                }
                catch { return Rectangle.Empty; }
            }
        }

        public bool Visible { get { return _gameReady; } }
        public bool WantsAnimationTick { get { return false; } }
        public void Tick(int deltaMs) { }

        public void Paint(Graphics g, float dpr, Point hudOrigin)
        {
            Rectangle r = ScreenBounds;
            if (r.Width <= 0 || r.Height <= 0) return;
            int localX = r.X - hudOrigin.X;
            int localY = r.Y - hudOrigin.Y;
            int btnW = BtnW;
            int btnH = BtnH;
            float fontPx = WidgetScaler.Pxf(FONT_BASE_PX, Scale);
            string[] labels = _paused ? LABELS_PAUSED : LABELS_DEFAULT;

            // 颜色取自 web overlay.css #top-right-tools / #notch-pause.paused 规则
            using (SolidBrush bg        = new SolidBrush(Color.FromArgb(209, 24, 24, 26)))
            using (SolidBrush bgHover   = new SolidBrush(Color.FromArgb(229, 60, 60, 64)))
            using (SolidBrush bgPaused  = new SolidBrush(Color.FromArgb(229, 80, 20, 20)))
            using (SolidBrush fg        = new SolidBrush(Color.FromArgb(178, 255, 255, 255)))
            using (SolidBrush fgHover   = new SolidBrush(Color.White))
            using (SolidBrush fgPaused  = new SolidBrush(Color.FromArgb(255, 255, 102, 102)))
            using (Pen border           = new Pen(Color.FromArgb(31, 255, 255, 255)))
            using (Font font            = new Font("Segoe UI Symbol", fontPx, FontStyle.Regular, GraphicsUnit.Pixel))
            using (StringFormat fmt     = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center })
            {
                TextRenderingHint prevHint = g.TextRenderingHint;
                g.TextRenderingHint = TextRenderingHint.AntiAlias;
                try
                {
                    for (int i = 0; i < KEYS.Length; i++)
                    {
                        Rectangle btn = new Rectangle(localX + i * btnW, localY, btnW, btnH);
                        bool hover = (i == _hoverIndex);
                        bool paused = (_paused && i == IDX_PAUSE);

                        Brush bgBrush = paused ? bgPaused : (hover ? bgHover : (Brush)bg);
                        Brush fgBrush = paused ? fgPaused : (hover ? fgHover : (Brush)fg);

                        g.FillRectangle(bgBrush, btn);
                        g.DrawLine(border, btn.X, btn.Bottom - 1, btn.Right - 1, btn.Bottom - 1);
                        if (i == 0) g.DrawLine(border, btn.X, btn.Y, btn.X, btn.Bottom - 1);
                        if (i == KEYS.Length - 1) g.DrawLine(border, btn.Right - 1, btn.Y, btn.Right - 1, btn.Bottom - 1);

                        g.DrawString(labels[i], font, fgBrush, btn, fmt);
                    }
                }
                finally { g.TextRenderingHint = prevHint; }
            }
        }

        public bool TryHitTest(Point screenPt)
        {
            return ScreenBounds.Contains(screenPt);
        }

        public void OnMouseEvent(MouseEventArgs e, MouseEventKind kind)
        {
            Rectangle r = ScreenBounds;
            if (r.Width <= 0 || r.Height <= 0) return;
            int btnW = BtnW;
            int localX = e.X - r.X;
            int idx = (localX < 0 || btnW <= 0) ? -1 : Math.Min(KEYS.Length - 1, localX / btnW);
            if (idx < 0 || idx >= KEYS.Length) idx = -1;

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
                    if (idx >= 0)
                    {
                        try { _router.Dispatch(KEYS[idx]); }
                        catch (Exception ex) { LogManager.Log("[TopRightTools] dispatch failed key=" + KEYS[idx] + " ex=" + ex.Message); }
                    }
                    break;
            }
        }

        private void SetHover(int idx)
        {
            if (_hoverIndex == idx) return;
            _hoverIndex = idx;
            FireRepaint();
        }

        public void OnUiDataChanged(IReadOnlyDictionary<string, string> snapshot, ISet<string> changedKeys)
        {
            bool boundsDirty = false;
            bool repaintDirty = false;
            string piece;

            if (changedKeys.Contains("s") && snapshot.TryGetValue("s", out piece))
            {
                bool ready = ParseUiBoolValue(piece);
                if (ready != _gameReady)
                {
                    _gameReady = ready;
                    if (!ready) _hoverIndex = -1;
                    boundsDirty = true;
                }
            }
            if (changedKeys.Contains("p") && snapshot.TryGetValue("p", out piece))
            {
                bool paused = ParseUiBoolValue(piece);
                if (paused != _paused)
                {
                    _paused = paused;
                    repaintDirty = true;
                }
            }

            if (boundsDirty) FireBounds();
            else if (repaintDirty) FireRepaint();
        }

        /// <summary>
        /// UiData fullPiece 形如 "p:1" / "s:0"；提取 ":" 后第一段并判等 "1"。
        /// 容忍纯值（无 "key:" 前缀）的兜底，避免 parser 漂移时 widget 静默失效。
        /// </summary>
        internal static bool ParseUiBoolValue(string fullPiece)
        {
            if (string.IsNullOrEmpty(fullPiece)) return false;
            int colon = fullPiece.IndexOf(':');
            string val = (colon >= 0 && colon < fullPiece.Length - 1) ? fullPiece.Substring(colon + 1) : fullPiece;
            return val == "1";
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
    }
}
