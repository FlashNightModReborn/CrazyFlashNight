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
    /// 替代 web overlay.html #safe-exit-panel + notch.js UiData "sv" 状态机。
    /// 路径：玩家点 SAFEEXIT → router 发 safe_exit_show + safeExit → AS2 存盘 →
    /// UiData "sv:1"（存盘中，仅显示状态文本）→ "sv:2"（存盘完成，显示 取消/退出 按钮）。
    /// 取消按钮纯本地隐藏（_dismissed=true），下次 sv:1 时复位；退出按钮调 router EXIT_CONFIRM。
    /// 位置：贴 TopRightToolsWidget 正下方（viewport 右上），letterbox 黑边内。
    /// </summary>
    public class SafeExitPanelWidget : INativeHudWidget, IUiDataConsumer
    {
        // 与 TopRightToolsWidget 同基准 letterbox + 同 design 1024x576。
        private const int PANEL_W_BASE = 200;
        private const int STATUS_H_BASE = 28;
        private const int BUTTON_H_BASE = 30;
        private const int TOP_RIGHT_TOOL_H_BASE = 32; // = TopRightToolsWidget.BTN_H_BASE
        private const float STATUS_FONT_BASE_PX = 13f;
        private const float BUTTON_FONT_BASE_PX = 13f;

        private enum SaveState { Idle, Saving, Done }

        private static readonly string[] DONE_KEYS   = { "EXIT_CANCEL", "EXIT_CONFIRM" };
        private static readonly string[] DONE_LABELS = { "取消",        "退出游戏"     };

        private readonly Control _anchor;
        private readonly LauncherCommandRouter _router;
        private readonly FlashCoordinateMapper _mapper;
        private volatile bool _gameReady;
        private volatile SaveState _state = SaveState.Idle;
        private volatile bool _dismissed;
        private int _hoverIndex = -1;

        public event EventHandler BoundsOrVisibilityChanged;
        public event EventHandler RepaintRequested;
        public event EventHandler AnimationStateChanged;

        public SafeExitPanelWidget(Control anchor, LauncherCommandRouter router)
        {
            if (anchor == null) throw new ArgumentNullException("anchor");
            if (router == null) throw new ArgumentNullException("router");
            _anchor = anchor;
            _router = router;
            _mapper = new FlashCoordinateMapper(anchor, 1024f, 576f);
            _anchor.Resize += delegate { FireBounds(); };
        }

        private float Scale { get { return WidgetScaler.GetScale(_mapper); } }
        private int PanelW { get { return WidgetScaler.Px(PANEL_W_BASE, Scale); } }
        private int StatusH { get { return WidgetScaler.Px(STATUS_H_BASE, Scale); } }
        private int ButtonH { get { return WidgetScaler.Px(BUTTON_H_BASE, Scale); } }
        private int TopRightToolH { get { return WidgetScaler.Px(TOP_RIGHT_TOOL_H_BASE, Scale); } }

        public bool Visible
        {
            get { return _gameReady && !_dismissed && _state != SaveState.Idle; }
        }

        public bool WantsAnimationTick { get { return false; } }
        public void Tick(int deltaMs) { }

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
                    int panelW = PanelW;
                    int totalH = StatusH + (_state == SaveState.Done ? ButtonH : 0);
                    int x = origin.X + (int)vpX + Math.Max(0, (int)vpW - panelW);
                    int y = origin.Y + (int)vpY + TopRightToolH;
                    return new Rectangle(x, y, panelW, totalH);
                }
                catch { return Rectangle.Empty; }
            }
        }

        public void Paint(Graphics g, float dpr, Point hudOrigin)
        {
            Rectangle r = ScreenBounds;
            if (r.Width <= 0 || r.Height <= 0) return;
            int localX = r.X - hudOrigin.X;
            int localY = r.Y - hudOrigin.Y;
            int statusH = StatusH;
            int buttonH = ButtonH;
            float statusFontPx = WidgetScaler.Pxf(STATUS_FONT_BASE_PX, Scale);
            float buttonFontPx = WidgetScaler.Pxf(BUTTON_FONT_BASE_PX, Scale);

            using (SolidBrush bg          = new SolidBrush(Color.FromArgb(229, 24, 24, 26)))
            using (SolidBrush bgSavingTop = new SolidBrush(Color.FromArgb(229, 80, 60, 20)))
            using (SolidBrush bgDoneTop   = new SolidBrush(Color.FromArgb(229, 30, 70, 30)))
            using (SolidBrush bgBtnHover  = new SolidBrush(Color.FromArgb(229, 60, 60, 64)))
            using (SolidBrush fg          = new SolidBrush(Color.FromArgb(229, 255, 255, 255)))
            using (SolidBrush fgHover     = new SolidBrush(Color.White))
            using (Pen border             = new Pen(Color.FromArgb(64, 255, 255, 255)))
            using (Font statusFont        = new Font("Microsoft YaHei", statusFontPx, FontStyle.Bold, GraphicsUnit.Pixel))
            using (Font buttonFont        = new Font("Microsoft YaHei", buttonFontPx, FontStyle.Regular, GraphicsUnit.Pixel))
            using (StringFormat fmt       = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center })
            {
                TextRenderingHint prevHint = g.TextRenderingHint;
                g.TextRenderingHint = TextRenderingHint.AntiAlias;
                try
                {
                    Rectangle statusRect = new Rectangle(localX, localY, r.Width, statusH);
                    Brush topBg = _state == SaveState.Saving ? bgSavingTop : bgDoneTop;
                    g.FillRectangle(topBg, statusRect);
                    g.DrawRectangle(border, statusRect.X, statusRect.Y, statusRect.Width - 1, statusRect.Height - 1);
                    string statusText = _state == SaveState.Saving ? "存盘中…" : "存盘成功";
                    g.DrawString(statusText, statusFont, fg, statusRect, fmt);

                    if (_state == SaveState.Done)
                    {
                        int btnW = r.Width / DONE_KEYS.Length;
                        for (int i = 0; i < DONE_KEYS.Length; i++)
                        {
                            int bx = localX + i * btnW;
                            int bw = (i == DONE_KEYS.Length - 1) ? (r.Width - i * btnW) : btnW;
                            Rectangle btn = new Rectangle(bx, localY + statusH, bw, buttonH);
                            bool hover = (i == _hoverIndex);
                            g.FillRectangle(hover ? bgBtnHover : (Brush)bg, btn);
                            g.DrawRectangle(border, btn.X, btn.Y, btn.Width - 1, btn.Height - 1);
                            g.DrawString(DONE_LABELS[i], buttonFont, hover ? fgHover : (Brush)fg, btn, fmt);
                        }
                    }
                }
                finally { g.TextRenderingHint = prevHint; }
            }
        }

        public bool TryHitTest(Point screenPt) { return ScreenBounds.Contains(screenPt); }

        public void OnMouseEvent(MouseEventArgs e, MouseEventKind kind)
        {
            Rectangle r = ScreenBounds;
            if (r.Width <= 0 || r.Height <= 0) return;

            int idx = HitButton(e.X, e.Y, r);
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
                    if (idx < 0) break;
                    string key = DONE_KEYS[idx];
                    if (key == "EXIT_CANCEL")
                    {
                        _dismissed = true;
                        _hoverIndex = -1;
                        FireBounds();
                    }
                    else
                    {
                        try { _router.Dispatch(key); }
                        catch (Exception ex) { LogManager.Log("[SafeExitPanel] dispatch failed key=" + key + " ex=" + ex.Message); }
                    }
                    break;
            }
        }

        private int HitButton(int sx, int sy, Rectangle r)
        {
            if (_state != SaveState.Done) return -1;
            int statusH = StatusH;
            int buttonH = ButtonH;
            int by = r.Y + statusH;
            if (sy < by || sy >= by + buttonH) return -1;
            int btnW = r.Width / DONE_KEYS.Length;
            if (btnW <= 0) return -1;
            int relX = sx - r.X;
            int idx = relX / btnW;
            if (idx < 0 || idx >= DONE_KEYS.Length) return -1;
            return idx;
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
            string piece;
            if (changedKeys.Contains("s") && snapshot.TryGetValue("s", out piece))
            {
                bool ready = TopRightToolsWidget.ParseUiBoolValue(piece);
                if (ready != _gameReady)
                {
                    _gameReady = ready;
                    if (!ready)
                    {
                        _state = SaveState.Idle;
                        _dismissed = false;
                        _hoverIndex = -1;
                    }
                    boundsDirty = true;
                }
            }
            if (changedKeys.Contains("sv") && snapshot.TryGetValue("sv", out piece))
            {
                int sv = NotchToolbarWidget.ParseUiIntValue(piece);
                SaveState next = _state;
                if (sv == 1) { next = SaveState.Saving; _dismissed = false; _hoverIndex = -1; }
                else if (sv == 2) next = SaveState.Done;
                else next = SaveState.Idle;
                if (next != _state) { _state = next; boundsDirty = true; }
            }
            if (boundsDirty) FireBounds();
        }

        private void FireBounds() { EventHandler h = BoundsOrVisibilityChanged; if (h != null) h(this, EventArgs.Empty); }
        private void FireRepaint() { EventHandler h = RepaintRequested; if (h != null) h(this, EventArgs.Empty); }
    }
}
