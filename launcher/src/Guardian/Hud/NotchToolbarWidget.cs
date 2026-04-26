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
    /// 替代 web overlay.html #notch-toolbar：5 键 PETS/MERCS/TABLET/WAREHOUSE/SHOP。
    /// 位置：anchor 顶部居中靠右（避开 NotchOverlay 居中 pill）。
    /// WAREHOUSE 仅在 UiData "q" > 13 时可见（与 web 同步）。
    /// 解决 useNativeHud=true 下 SHOP 入口不可达。
    /// </summary>
    public class NotchToolbarWidget : INativeHudWidget, IUiDataConsumer
    {
        private const int BTN_W_BASE = 80;
        private const int BTN_H_BASE = 26;
        // 与 NotchOverlay pill 视觉契合：高度 28 + 紧贴下边
        private const int NOTCH_PILL_H = 28;
        private const int CARD_PAD_X_BASE = 8;
        private const int CARD_PAD_Y_BASE = 4;
        private const float FONT_BASE_PX = 13f;

        private static readonly string[] KEYS    = { "PETS", "MERCS", "TABLET", "WAREHOUSE", "SHOP" };
        private static readonly string[] LABELS  = { "🐾 战宠", "⚔ 佣兵", "💻 平板", "📦 战备箱", "🛒 商城" };
        private const int IDX_WAREHOUSE = 3;

        private readonly Control _anchor;
        private readonly LauncherCommandRouter _router;
        private readonly FlashCoordinateMapper _mapper;
        private volatile bool _gameReady;
        private volatile bool _warehouseVisible;
        private int _hoverIndex = -1;

        public event EventHandler BoundsOrVisibilityChanged;
        public event EventHandler RepaintRequested;
        public event EventHandler AnimationStateChanged;

        public NotchToolbarWidget(Control anchor, LauncherCommandRouter router)
        {
            if (anchor == null) throw new ArgumentNullException("anchor");
            if (router == null) throw new ArgumentNullException("router");
            _anchor = anchor;
            _router = router;
            _mapper = new FlashCoordinateMapper(anchor, 1024f, 576f);
            _anchor.Resize += delegate { FireBounds(); };
        }

        private float Scale { get { return WidgetScaler.GetScale(_mapper); } }
        private int BtnW { get { return WidgetScaler.Px(BTN_W_BASE, Scale); } }
        private int BtnH { get { return WidgetScaler.Px(BTN_H_BASE, Scale); } }

        private bool IsKeyVisible(int idx)
        {
            if (idx == IDX_WAREHOUSE) return _warehouseVisible;
            return true;
        }

        private int VisibleCount()
        {
            int n = 0;
            for (int i = 0; i < KEYS.Length; i++) if (IsKeyVisible(i)) n++;
            return n;
        }

        public Rectangle ScreenBounds
        {
            get
            {
                if (!_gameReady || _anchor == null || !_anchor.IsHandleCreated) return Rectangle.Empty;
                int n = VisibleCount();
                if (n <= 0) return Rectangle.Empty;
                try
                {
                    Point origin = _anchor.PointToScreen(Point.Empty);
                    float vpX, vpY, vpW, vpH;
                    _mapper.CalcViewport(out vpX, out vpY, out vpW, out vpH);
                    int btnW = BtnW;
                    int btnH = BtnH;
                    int padX = WidgetScaler.Px(CARD_PAD_X_BASE, Scale);
                    int padY = WidgetScaler.Px(CARD_PAD_Y_BASE, Scale);
                    int totalW = btnW * n + padX * 2;
                    int totalH = btnH + padY * 2;
                    int pillH = WidgetScaler.Px(NOTCH_PILL_H, Scale);
                    // 紧贴 NotchOverlay pill 下方，与 viewport 顶部居中
                    int x = origin.X + (int)vpX + Math.Max(0, ((int)vpW - totalW) / 2);
                    int y = origin.Y + (int)vpY + pillH;
                    return new Rectangle(x, y, totalW, totalH);
                }
                catch { return Rectangle.Empty; }
            }
        }

        public bool Visible { get { return _gameReady && VisibleCount() > 0; } }
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
            int padX = WidgetScaler.Px(CARD_PAD_X_BASE, Scale);
            int padY = WidgetScaler.Px(CARD_PAD_Y_BASE, Scale);
            float fontPx = WidgetScaler.Pxf(FONT_BASE_PX, Scale);

            // notch 卡片 fill：与 NotchOverlay pill (rgba 0,0,0,0.85) 同款，仅下半圆角延续视觉
            Rectangle card = new Rectangle(localX, localY, r.Width, r.Height);
            int radius = WidgetScaler.Px(6, Scale);
            using (SolidBrush cardBg = new SolidBrush(Color.FromArgb(217, 0, 0, 0)))
                FillBottomRoundedRect(g, card, radius, cardBg);

            using (SolidBrush bgHover = new SolidBrush(Color.FromArgb(64, 255, 255, 255)))
            using (SolidBrush fg      = new SolidBrush(Color.FromArgb(217, 255, 255, 255)))
            using (SolidBrush fgHover = new SolidBrush(Color.White))
            using (Font font          = new Font("Microsoft YaHei", fontPx, FontStyle.Regular, GraphicsUnit.Pixel))
            using (StringFormat fmt   = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center })
            {
                TextRenderingHint prevHint = g.TextRenderingHint;
                g.TextRenderingHint = TextRenderingHint.AntiAlias;
                try
                {
                    int slot = 0;
                    for (int i = 0; i < KEYS.Length; i++)
                    {
                        if (!IsKeyVisible(i)) continue;
                        Rectangle btn = new Rectangle(localX + padX + slot * btnW, localY + padY, btnW - 2, btnH);
                        bool hover = (slot == _hoverIndex);
                        if (hover)
                        {
                            int br = WidgetScaler.Px(3, Scale);
                            using (GraphicsPath p = MakeRoundedRect(btn, br))
                                g.FillPath(bgHover, p);
                        }
                        g.DrawString(LABELS[i], font, hover ? fgHover : (Brush)fg, btn, fmt);
                        slot++;
                    }
                }
                finally { g.TextRenderingHint = prevHint; }
            }
        }

        private static void FillBottomRoundedRect(Graphics g, Rectangle r, int radius, Brush brush)
        {
            if (radius <= 0) { g.FillRectangle(brush, r); return; }
            using (GraphicsPath p = new GraphicsPath())
            {
                int d = radius * 2;
                p.AddLine(r.X, r.Y, r.Right, r.Y);
                p.AddLine(r.Right, r.Y, r.Right, r.Bottom - radius);
                p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
                p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
                p.AddLine(r.X, r.Bottom - radius, r.X, r.Y);
                p.CloseFigure();
                g.FillPath(brush, p);
            }
        }

        private static GraphicsPath MakeRoundedRect(Rectangle r, int radius)
        {
            GraphicsPath p = new GraphicsPath();
            int d = radius * 2;
            p.AddArc(r.X, r.Y, d, d, 180, 90);
            p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
            p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
            p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
            p.CloseFigure();
            return p;
        }

        public bool TryHitTest(Point screenPt) { return ScreenBounds.Contains(screenPt); }

        public void OnMouseEvent(MouseEventArgs e, MouseEventKind kind)
        {
            Rectangle r = ScreenBounds;
            if (r.Width <= 0) return;
            int btnW = BtnW;
            int padX = WidgetScaler.Px(CARD_PAD_X_BASE, Scale);
            int relX = e.X - r.X - padX;
            int slot = (btnW <= 0 || relX < 0) ? -1 : relX / btnW;
            int n = VisibleCount();
            if (slot < 0 || slot >= n) slot = -1;

            switch (kind)
            {
                case MouseEventKind.Move:
                case MouseEventKind.Enter:
                    if (slot != _hoverIndex) { _hoverIndex = slot; FireRepaint(); }
                    break;
                case MouseEventKind.Leave:
                    if (_hoverIndex != -1) { _hoverIndex = -1; FireRepaint(); }
                    break;
                case MouseEventKind.Click:
                    if (slot >= 0)
                    {
                        // slot index → 实际 KEYS index（跳过隐藏项）
                        int seen = 0;
                        for (int i = 0; i < KEYS.Length; i++)
                        {
                            if (!IsKeyVisible(i)) continue;
                            if (seen == slot)
                            {
                                try { _router.Dispatch(KEYS[i]); }
                                catch (Exception ex) { LogManager.Log("[NotchToolbar] dispatch failed key=" + KEYS[i] + " ex=" + ex.Message); }
                                break;
                            }
                            seen++;
                        }
                    }
                    break;
            }
        }

        public void OnUiDataChanged(IReadOnlyDictionary<string, string> snapshot, ISet<string> changedKeys)
        {
            bool boundsDirty = false;
            string piece;
            if (changedKeys.Contains("s") && snapshot.TryGetValue("s", out piece))
            {
                bool ready = TopRightToolsWidget.ParseUiBoolValue(piece);
                if (ready != _gameReady) { _gameReady = ready; boundsDirty = true; }
            }
            if (changedKeys.Contains("q") && snapshot.TryGetValue("q", out piece))
            {
                int q = ParseUiIntValue(piece);
                bool warehouse = q > 13;
                if (warehouse != _warehouseVisible) { _warehouseVisible = warehouse; boundsDirty = true; }
            }
            if (boundsDirty) FireBounds();
        }

        internal static int ParseUiIntValue(string fullPiece)
        {
            if (string.IsNullOrEmpty(fullPiece)) return 0;
            int colon = fullPiece.IndexOf(':');
            string val = (colon >= 0 && colon < fullPiece.Length - 1) ? fullPiece.Substring(colon + 1) : fullPiece;
            int n;
            return int.TryParse(val, out n) ? n : 0;
        }

        private void FireBounds() { EventHandler h = BoundsOrVisibilityChanged; if (h != null) h(this, EventArgs.Empty); }
        private void FireRepaint() { EventHandler h = RepaintRequested; if (h != null) h(this, EventArgs.Empty); }
    }
}
