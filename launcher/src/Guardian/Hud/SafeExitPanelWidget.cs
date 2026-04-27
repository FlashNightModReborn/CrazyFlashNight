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
    /// 替代 web overlay.html #safe-exit-panel。
    ///
    /// 关键约束：sv 是通用存盘事件（SaveManager.saveAll 在商店关闭、升级、自动存盘等场景都会推 sv:1/2），
    /// **不能**单凭 sv 决定面板可见性，否则普通自动存盘也会弹"取消/退出"——这是 web 老路径的隐式正确行为
    /// （web openSafeExitPanel 仅在 SAFEEXIT 按钮 click 路径里 display:block；UiData 'sv' 只更新状态文本）。
    ///
    /// 此 widget 模仿该语义：必须由 SAFEEXIT click 显式 Arm() 才允许显示；sv:1/2 仅更新内部状态机。
    /// 路径：玩家点 SAFEEXIT → router.SAFEEXIT case → widget.Arm() + SendGameCommand("safeExit") →
    ///       AS2 存盘 → UiData "sv:1" → "sv:2"（显示 取消/退出 按钮）→ 取消（本地 disarm）/ 退出（EXIT_CONFIRM）。
    ///
    /// 位置：贴 RightHudLayout 定义的右侧 cluster 正下方（viewport 右上 right:80px），letterbox 黑边内。
    /// </summary>
    public class SafeExitPanelWidget : INativeHudWidget, IUiDataConsumer
    {
        private const int STATUS_H_BASE = 28;
        private const int BUTTON_H_BASE = 30;
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
        private volatile bool _armed;        // 仅由 SAFEEXIT click 路径置 true；通用 sv 推送不会显示面板
        private volatile bool _dismissed;
        private int _hoverIndex = -1;
        private int _downIndex = -1;         // Down 命中按钮 idx；Click 时若 idx 不匹配则忽略（destructive 操作必需）

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
        private int StatusH { get { return WidgetScaler.Px(STATUS_H_BASE, Scale); } }
        private int ButtonH { get { return WidgetScaler.Px(BUTTON_H_BASE, Scale); } }

        public bool Visible
        {
            // 必须 _armed：通用 sv:1/2 推送（自动存盘 / 商店关闭 / 升级）不会拉起面板
            get { return _gameReady && _armed && !_dismissed; }
        }

        /// <summary>
        /// 由 LauncherCommandRouter SAFEEXIT case 调用：玩家显式点 SAFEEXIT 时进入"待存盘+待确认"状态。
        /// 此后 sv:1 显示状态条，sv:2 显示按钮。复位条件：取消按钮 / s:0（游戏未就绪） / EXIT_CONFIRM 后。
        /// </summary>
        public void Arm()
        {
            _armed = true;
            _dismissed = false;
            _hoverIndex = -1;
            _downIndex = -1;
            // 无条件强制 Saving：sv 是通用存盘事件，普通自动存盘/商店关闭/升级会先把 unarmed widget 推到 Done。
            // 若不复位，玩家随后点 SAFEEXIT 时 Visible 看到旧 Done → 直接显示「取消/退出」按钮，
            // 早于本次 safeExit 真正的 sv:1/2，玩家可能在存盘还没完成时点退出（数据丢失风险）。
            // 每次 Arm 都视作开新 session，重新等本轮 sv:1 → sv:2 推达。
            _state = SaveState.Saving;
            FireBounds();
        }

        private void Disarm()
        {
            _armed = false;
            _dismissed = false;
            _state = SaveState.Idle;
            _hoverIndex = -1;
            _downIndex = -1;
        }

        // ── 测试钩子（InternalsVisibleTo("Launcher.Tests")） ──
        internal bool IsArmed { get { return _armed; } }
        internal bool IsDismissed { get { return _dismissed; } }
        internal bool IsDoneState { get { return _state == SaveState.Done; } }
        internal bool IsSavingState { get { return _state == SaveState.Saving; } }
        internal int  InternalDownIndex { get { return _downIndex; } set { _downIndex = value; } }
        internal void ForceGameReady(bool ready) { _gameReady = ready; }

        /// <summary>
        /// 提取 Click 分支供测试（绕过 ScreenBounds 依赖）。返回是否真正触发了 dispatch（true=EXIT_CONFIRM 或 dismiss 路径执行了）。
        /// 与 OnMouseEvent.Click 分支语义同步——任何修改都要两边一起改。
        /// </summary>
        internal ClickOutcome TryFireButtonClick(int upIdx)
        {
            int down = _downIndex;
            _downIndex = -1;
            if (upIdx < 0 || upIdx >= DONE_KEYS.Length) return ClickOutcome.OutOfRange;
            if (upIdx != down) return ClickOutcome.MismatchedDownUp;
            string key = DONE_KEYS[upIdx];
            if (key == "EXIT_CANCEL")
            {
                _armed = false;
                _dismissed = true;
                _hoverIndex = -1;
                FireBounds();
                return ClickOutcome.Cancelled;
            }
            _armed = false;
            try { _router.Dispatch(key); }
            catch (Exception ex) { LogManager.Log("[SafeExitPanel] dispatch failed key=" + key + " ex=" + ex.Message); }
            return ClickOutcome.Confirmed;
        }

        internal enum ClickOutcome { OutOfRange, MismatchedDownUp, Cancelled, Confirmed }

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
                    int totalH = StatusH + (_state == SaveState.Done ? ButtonH : 0);
                    Rectangle viewport = RightHudLayout.GetViewportRect(_anchor, _mapper);
                    return RightHudLayout.SafeExitRectFromViewport(viewport, RightHudLayout.ScaleForViewport(viewport), totalH);
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
                case MouseEventKind.Down:
                    // 只在左键 down 命中按钮才记录 anchor；其他情况 reset 防 stale 状态。
                    _downIndex = (e.Button == MouseButtons.Left) ? idx : -1;
                    break;
                case MouseEventKind.Up:
                    // Up 不触发动作；逻辑发生在 Click。这里只在左键 up 时清除 down anchor。
                    if (e.Button == MouseButtons.Left)
                    {
                        // 不要在这里清 _downIndex——下面 Click 还要用；改在 Click 末尾清。
                    }
                    break;
                case MouseEventKind.Click:
                    // button-level Down/Up 匹配 + 取消/退出分发，全部走 TryFireButtonClick 这一份逻辑（测试覆盖）
                    TryFireButtonClick(idx);
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
            bool repaintDirty = false;
            string piece;
            if (changedKeys.Contains("s") && snapshot.TryGetValue("s", out piece))
            {
                bool ready = TopRightToolsWidget.ParseUiBoolValue(piece);
                if (ready != _gameReady)
                {
                    _gameReady = ready;
                    if (!ready) Disarm(); // 游戏未就绪：彻底复位
                    boundsDirty = true;
                }
            }
            if (changedKeys.Contains("sv") && snapshot.TryGetValue("sv", out piece))
            {
                // sv 是通用存盘事件（自动存盘 / 商店关闭 / 升级），仅更新内部状态。
                // 不在这里自动 _armed=true，否则普通存盘也会拉起面板（见 class doc）。
                int sv = NotchToolbarWidget.ParseUiIntValue(piece);
                SaveState next = _state;
                if (sv == 1) next = SaveState.Saving;
                else if (sv == 2) next = SaveState.Done;
                else next = SaveState.Idle;
                if (next != _state)
                {
                    _state = next;
                    // 已 armed 时状态推进影响显示内容（状态条 vs 按钮行 → 高度变化）
                    if (_armed) boundsDirty = true;
                    else repaintDirty = false; // 未 armed：不可见，无需 repaint
                }
            }
            if (boundsDirty) FireBounds();
            else if (repaintDirty) FireRepaint();
        }

        private void FireBounds() { EventHandler h = BoundsOrVisibilityChanged; if (h != null) h(this, EventArgs.Empty); }
        private void FireRepaint() { EventHandler h = RepaintRequested; if (h != null) h(this, EventArgs.Empty); }
    }
}
