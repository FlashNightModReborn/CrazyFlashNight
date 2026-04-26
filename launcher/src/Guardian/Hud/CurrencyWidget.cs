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
    /// 替代 web modules/currency.js：金币 + KP 双面板，含 600ms ease-out 数值滚动 + 1.2s delta 浮动。
    /// 单 widget 渲染两栏（节省 widget 数）：左侧 gold（金色），右侧 kpoint（蓝色）。
    /// 位置：anchor 顶部左右，避开中央 NotchOverlay pill。
    /// 监听 UiData "g" / "k" / "s"（game-ready）。
    /// </summary>
    public class CurrencyWidget : INativeHudWidget, IUiDataConsumer
    {
        private const int PANEL_W_BASE = 110;
        private const int PANEL_H_BASE = 22;
        // 与 NotchOverlay pill 协调：notch pill = 160x28，居中视口顶部；
        // currency 紧贴 pill 左右两侧，同行同高
        private const int NOTCH_PILL_W = 160;
        private const int NOTCH_PILL_H = 28;
        private const int GAP_BASE = 6;
        private const int VALUE_ANIM_MS = 600;
        private const int DELTA_LIFE_MS = 1200;

        private class Slot
        {
            public int Current;
            public int Target;
            public int From;
            public int AnimElapsedMs;
            public bool Animating;
            public int LastDelta;
            public int DeltaElapsedMs;
        }
        private readonly Slot _gold = new Slot();
        private readonly Slot _kp   = new Slot();

        private readonly Control _anchor;
        private readonly FlashCoordinateMapper _mapper;
        private volatile bool _gameReady;

        public event EventHandler BoundsOrVisibilityChanged;
        public event EventHandler RepaintRequested;
        public event EventHandler AnimationStateChanged;

        public CurrencyWidget(Control anchor)
        {
            if (anchor == null) throw new ArgumentNullException("anchor");
            _anchor = anchor;
            _mapper = new FlashCoordinateMapper(anchor, 1024f, 576f);
            _anchor.Resize += delegate { FireBounds(); };
        }

        private float Scale { get { return WidgetScaler.GetScale(_mapper); } }
        private int PanelW { get { return WidgetScaler.Px(PANEL_W_BASE, Scale); } }
        private int PanelH { get { return WidgetScaler.Px(PANEL_H_BASE, Scale); } }

        public Rectangle ScreenBounds
        {
            get
            {
                if (!_gameReady || _anchor == null || !_anchor.IsHandleCreated) return Rectangle.Empty;
                try
                {
                    Point origin = _anchor.PointToScreen(Point.Empty);
                    float vpX, vpY, vpW, vpH;
                    _mapper.CalcViewport(out vpX, out vpY, out vpW, out vpH);
                    int panelW = PanelW;
                    int panelH = PanelH;
                    int gap = WidgetScaler.Px(GAP_BASE, Scale);
                    int pillW = WidgetScaler.Px(NOTCH_PILL_W, Scale);
                    // 占据 pill 两侧：左金币 [pillCenterX - pillW/2 - gap - panelW, ...]
                    //                右 KP   [pillCenterX + pillW/2 + gap, ...]
                    int pillCenterX = origin.X + (int)vpX + (int)vpW / 2;
                    int leftX = pillCenterX - pillW / 2 - gap - panelW;
                    int rightEnd = pillCenterX + pillW / 2 + gap + panelW;
                    int y = origin.Y + (int)vpY + WidgetScaler.Px(3, Scale);
                    int totalH = panelH + WidgetScaler.Px(18, Scale); // +delta float 区域
                    return new Rectangle(leftX, y, rightEnd - leftX, totalH);
                }
                catch { return Rectangle.Empty; }
            }
        }

        public bool Visible { get { return _gameReady; } }

        public bool WantsAnimationTick
        {
            get { return _gold.Animating || _kp.Animating || _gold.DeltaElapsedMs < DELTA_LIFE_MS || _kp.DeltaElapsedMs < DELTA_LIFE_MS; }
        }

        public void Tick(int deltaMs)
        {
            bool changed = false;
            changed |= TickSlot(_gold, deltaMs);
            changed |= TickSlot(_kp, deltaMs);
            if (changed) FireRepaint();
            if (!WantsAnimationTick) FireAnimState();
        }

        private static bool TickSlot(Slot s, int deltaMs)
        {
            bool changed = false;
            if (s.Animating)
            {
                s.AnimElapsedMs += deltaMs;
                float t = Math.Min(1f, s.AnimElapsedMs / (float)VALUE_ANIM_MS);
                float eased = 1f - (float)Math.Pow(1 - t, 3);
                int next = s.From + (int)Math.Round((s.Target - s.From) * eased);
                if (next != s.Current) { s.Current = next; changed = true; }
                if (t >= 1f) { s.Animating = false; s.Current = s.Target; }
            }
            if (s.DeltaElapsedMs < DELTA_LIFE_MS)
            {
                s.DeltaElapsedMs += deltaMs;
                changed = true;
            }
            return changed;
        }

        private void StartUpdate(Slot s, int newValue)
        {
            int old = s.Target;
            if (newValue == old && !s.Animating) return;
            s.From = s.Animating ? s.Current : old;
            s.Target = newValue;
            s.AnimElapsedMs = 0;
            s.Animating = true;
            int delta = newValue - old;
            if (delta != 0) { s.LastDelta = delta; s.DeltaElapsedMs = 0; }
            FireAnimState();
            FireRepaint();
        }

        public void Paint(Graphics g, float dpr, Point hudOrigin)
        {
            Rectangle r = ScreenBounds;
            if (r.Width <= 0) return;
            int localX = r.X - hudOrigin.X;
            int localY = r.Y - hudOrigin.Y;
            int panelW = PanelW;
            int panelH = PanelH;
            float fontPx = WidgetScaler.Pxf(12f, Scale);

            using (Font font = new Font("Consolas", fontPx, FontStyle.Bold, GraphicsUnit.Pixel))
            using (Font deltaFont = new Font("Consolas", WidgetScaler.Pxf(10f, Scale), FontStyle.Bold, GraphicsUnit.Pixel))
            using (StringFormat fmtL = new StringFormat { Alignment = StringAlignment.Near, LineAlignment = StringAlignment.Center })
            using (StringFormat fmtR = new StringFormat { Alignment = StringAlignment.Far, LineAlignment = StringAlignment.Center })
            {
                TextRenderingHint prevHint = g.TextRenderingHint;
                g.TextRenderingHint = TextRenderingHint.AntiAlias;
                try
                {
                    // 金币贴最左、KP 贴最右；中间留 pill 空白让 NotchOverlay 渲染
                    Rectangle goldRect = new Rectangle(localX, localY, panelW, panelH);
                    Rectangle kpRect = new Rectangle(localX + r.Width - panelW, localY, panelW, panelH);
                    DrawPanel(g, goldRect, "$", _gold, Color.FromArgb(255, 215, 0), font, deltaFont, fmtL, true);
                    DrawPanel(g, kpRect, "K", _kp, Color.FromArgb(102, 204, 255), font, deltaFont, fmtR, false);
                }
                finally { g.TextRenderingHint = prevHint; }
            }
        }

        private static void DrawPanel(Graphics g, Rectangle rect, string icon, Slot s, Color iconColor,
                                      Font font, Font deltaFont, StringFormat fmt, bool leftAlign)
        {
            using (SolidBrush iconBg = new SolidBrush(Color.FromArgb(38, iconColor.R, iconColor.G, iconColor.B)))
            using (SolidBrush iconFg = new SolidBrush(iconColor))
            using (SolidBrush valFg = new SolidBrush(Color.FromArgb(229, 255, 255, 255)))
            {
                int iconW = rect.Height + 4;
                Rectangle iconR = leftAlign
                    ? new Rectangle(rect.X, rect.Y, iconW, rect.Height)
                    : new Rectangle(rect.Right - iconW, rect.Y, iconW, rect.Height);
                Rectangle valR = leftAlign
                    ? new Rectangle(rect.X + iconW + 2, rect.Y, rect.Width - iconW - 2, rect.Height)
                    : new Rectangle(rect.X, rect.Y, rect.Width - iconW - 2, rect.Height);
                g.FillRectangle(iconBg, iconR);
                using (StringFormat icf = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center })
                    g.DrawString(icon, font, iconFg, iconR, icf);
                g.DrawString(FormatNumber(s.Current), font, valFg, valR, fmt);
            }
            if (s.DeltaElapsedMs < DELTA_LIFE_MS && s.LastDelta != 0)
            {
                float t = s.DeltaElapsedMs / (float)DELTA_LIFE_MS;
                int alpha = t < 0.7f ? 255 : Math.Max(0, (int)(255 * (1 - (t - 0.7f) / 0.3f)));
                int yOff = (int)(8 * t);
                Color dColor = s.LastDelta > 0 ? Color.FromArgb(alpha, 102, 255, 102) : Color.FromArgb(alpha, 255, 102, 102);
                using (SolidBrush dBrush = new SolidBrush(dColor))
                {
                    string txt = (s.LastDelta > 0 ? "+" : "") + FormatNumber(s.LastDelta);
                    Rectangle dRect = new Rectangle(rect.X, rect.Bottom + yOff, rect.Width, 14);
                    g.DrawString(txt, deltaFont, dBrush, dRect, fmt);
                }
            }
        }

        private static string FormatNumber(int n)
        {
            string s = Math.Abs(n).ToString("N0", System.Globalization.CultureInfo.InvariantCulture);
            return n < 0 ? "-" + s : s;
        }

        public bool TryHitTest(Point screenPt) { return false; }
        public void OnMouseEvent(MouseEventArgs e, MouseEventKind kind) { }

        public void OnUiDataChanged(IReadOnlyDictionary<string, string> snapshot, ISet<string> changedKeys)
        {
            string piece;
            if (changedKeys.Contains("s") && snapshot.TryGetValue("s", out piece))
            {
                bool ready = TopRightToolsWidget.ParseUiBoolValue(piece);
                if (ready != _gameReady) { _gameReady = ready; FireBounds(); }
            }
            if (changedKeys.Contains("g") && snapshot.TryGetValue("g", out piece))
                StartUpdate(_gold, NotchToolbarWidget.ParseUiIntValue(piece));
            if (changedKeys.Contains("k") && snapshot.TryGetValue("k", out piece))
                StartUpdate(_kp, NotchToolbarWidget.ParseUiIntValue(piece));
        }

        private void FireBounds() { EventHandler h = BoundsOrVisibilityChanged; if (h != null) h(this, EventArgs.Empty); }
        private void FireRepaint() { EventHandler h = RepaintRequested; if (h != null) h(this, EventArgs.Empty); }
        private void FireAnimState() { EventHandler h = AnimationStateChanged; if (h != null) h(this, EventArgs.Empty); }
    }
}
