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
    /// 关键约束：sv 是通用存盘事件（SaveManager.saveAll 在商店关闭、升级、自动存盘等场景都会推 sv:1/2/3），
    /// **不能**单凭 sv 决定面板可见性，否则普通自动存盘也会弹"取消/退出"——这是 web 老路径的隐式正确行为
    /// （web openSafeExitPanel 仅在 SAFEEXIT 按钮 click 路径里 display:block；UiData 'sv' 只更新状态文本）。
    ///
    /// 此 widget 模仿该语义：必须由 SAFEEXIT click 显式 Arm() 才允许显示；sv:1/2/3 仅更新内部状态机。
    /// 路径：玩家点 SAFEEXIT → router.SAFEEXIT case → widget.Arm() + SendGameCommand("safeExit") →
    ///       AS2 存盘 → "sv:1" → 成功 "sv:2"（取消/退出）或失败 "sv:3"（取消/重试）。
    ///
    /// 位置：与 RightHudLayout 的条件状态槽共用锚点（viewport 右上 right:48px），
    /// Done 状态在同一 252×32 行内展开为“状态 / 取消 / 退出”，不向下新增一行；
    /// 无操作 5 秒后按安全取消语义自动收起，悬停任一确认按钮时暂停倒计时。
    /// </summary>
    public class SafeExitPanelWidget : INativeHudWidget, IUiDataConsumer
    {
        private const int STATUS_H_BASE = RightHudLayout.StatusSlotHeightBase;
        private const int DONE_AUTO_DISMISS_MS = 5000;
        private const float STATUS_FONT_BASE_PX = 13f;
        private const float BUTTON_FONT_BASE_PX = 13f;

        private enum SaveState { Idle, Saving, Done, Failed }

        private static readonly string[] DONE_KEYS   = { "EXIT_CANCEL", "EXIT_CONFIRM" };
        private static readonly string[] DONE_LABELS = { "取消",        "退出游戏"     };
        private static readonly string[] FAILED_KEYS   = { "EXIT_CANCEL", "SAFEEXIT" };
        private static readonly string[] FAILED_LABELS = { "取消",        "重试"     };

        private readonly Control _anchor;
        private readonly LauncherCommandRouter _router;
        private readonly FlashCoordinateMapper _mapper;
        private volatile bool _gameReady;
        private volatile SaveState _state = SaveState.Idle;
        private volatile bool _armed;        // 仅由 SAFEEXIT click 路径置 true；通用 sv 推送不会显示面板
        private volatile bool _sawSv1AfterArm; // Arm 后本轮是否已见 sv:1；sv:2 置 Done 的机械门（防背景存盘迟到完成事件提前授权退出）
        private volatile bool _dismissed;
        private volatile RightContextSlotOwner _slotOwner = RightContextSlotOwner.Hidden;
        private readonly object _exitAuthorizationGate =
            new object();
        private int _hoverIndex = -1;
        private int _downIndex = -1;         // Down 命中按钮 idx；Click 时若 idx 不匹配则忽略（destructive 操作必需）
        private int _doneAutoDismissRemainingMs;

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

        internal bool RequestsTransactionDecision
        {
            get { return _gameReady && _armed && !_dismissed; }
        }

        public bool Visible
        {
            // 事务状态只是 demand；只有组合 owner 把 exact transactionDecision 投影回来才可绘制/命中。
            get
            {
                return RequestsTransactionDecision
                    && _slotOwner == RightContextSlotOwner.TransactionDecision;
            }
        }

        internal void ApplySlotOwner(RightContextSlotOwner owner)
        {
            _slotOwner = owner;
        }

        /// <summary>
        /// 由 LauncherCommandRouter SAFEEXIT case 调用：玩家显式点 SAFEEXIT 时进入"待存盘+待确认"状态。
        /// 此后 sv:1 显示状态条，且只有本轮 sv:1 → sv:2 顺序推达才显示按钮（机械门见 _sawSv1AfterArm）。
        /// 复位条件：取消按钮 / s:0（游戏未就绪） / EXIT_CONFIRM 后。
        /// </summary>
        public void Arm()
        {
            _armed = true;
            _sawSv1AfterArm = false;
            _dismissed = false;
            _hoverIndex = -1;
            _downIndex = -1;
            _doneAutoDismissRemainingMs = 0;
            // 无条件强制 Saving：sv 是通用存盘事件，普通自动存盘/商店关闭/升级会先把 unarmed widget 推到 Done。
            // 若不复位，玩家随后点 SAFEEXIT 时 Visible 看到旧 Done → 直接显示「取消/退出」按钮，
            // 早于本次 safeExit 真正的 sv:1/2，玩家可能在存盘还没完成时点退出（数据丢失风险）。
            // 每次 Arm 都视作开新 session（上面已复位 _sawSv1AfterArm），重新等本轮 sv:1 → sv:2 推达；
            // Arm 后未见 sv:1 的 sv:2 会被 OnUiDataChanged 的门挡下，不能置 Done。
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
            _doneAutoDismissRemainingMs = 0;
        }

        /// <summary>
        /// safeExit 命令未送达时立即结束 Saving。只允许当前显式 armed session
        /// 进入 Failed；普通后台存盘或过期失败回调不能自行拉起面板。
        /// </summary>
        public void FailAttempt()
        {
            bool wasTicking = WantsAnimationTick;
            lock (_exitAuthorizationGate)
            {
                if (!_armed) return;
                _state = SaveState.Failed;
                _hoverIndex = -1;
                _downIndex = -1;
                _doneAutoDismissRemainingMs = 0;
            }
            FireBounds();
            if (wasTicking) FireAnimationStateChanged();
        }

        /// <summary>
        /// Consumes the exact armed+Done confirmation once. Raw/replayed EXIT_CONFIRM
        /// commands therefore cannot exit while unarmed, Saving or Failed.
        /// </summary>
        public bool TryAuthorizeExitConfirm()
        {
            bool wasTicking = WantsAnimationTick;
            lock (_exitAuthorizationGate)
            {
                if (!_armed || _state != SaveState.Done)
                    return false;
                Disarm();
            }
            FireBounds();
            if (wasTicking) FireAnimationStateChanged();
            return true;
        }

        // ── 测试钩子（InternalsVisibleTo("Launcher.Tests")） ──
        internal bool IsArmed { get { return _armed; } }
        internal bool SawSv1AfterArmForTest { get { return _sawSv1AfterArm; } }
        internal bool IsDismissed { get { return _dismissed; } }
        internal bool IsDoneState { get { return _state == SaveState.Done; } }
        internal bool IsSavingState { get { return _state == SaveState.Saving; } }
        internal bool IsFailedState { get { return _state == SaveState.Failed; } }
        internal RightContextSlotOwner SlotOwnerForTest { get { return _slotOwner; } }
        internal bool PaintsTransactionDecisionForTest { get { return Visible; } }
        internal bool SlotHitBoxActiveForTest { get { return Visible; } }
        internal int  InternalDownIndex { get { return _downIndex; } set { _downIndex = value; } }
        internal int DoneAutoDismissRemainingMsForTest { get { return _doneAutoDismissRemainingMs; } }
        internal static int DoneAutoDismissMsForTest { get { return DONE_AUTO_DISMISS_MS; } }
        internal void ForceGameReady(bool ready) { _gameReady = ready; }
        internal int HitButtonForTest(int sx, int sy, Rectangle bounds) { return HitButton(sx, sy, bounds); }
        internal void SetHoverForTest(int index) { SetHover(index); }

        /// <summary>
        /// 本 widget 是 Host 权威但不自渲染；UiData tee 只把 packet delta 转发到这里；
        /// 本 consumer 只读变化键，因此不需要第二份进程级快照。
        /// </summary>
        internal void HandleUiData(UiDataPacket packet)
        {
            if (packet == null || packet.IsLegacy) return;
            var delta =
                new Dictionary<string, string>();
            var changed =
                new HashSet<string>();
            foreach (KeyValuePair<string, string> pair
                in UiDataPacketParser.ParseFrom(packet))
            {
                delta[pair.Key] = pair.Value;
                changed.Add(pair.Key);
            }
            if (changed.Count != 0)
                OnUiDataChanged(delta, changed);
        }

        /// <summary>
        /// 提取 Click 分支供测试（绕过 ScreenBounds 依赖）。返回是否真正触发了 dispatch（true=EXIT_CONFIRM 或 dismiss 路径执行了）。
        /// 与 OnMouseEvent.Click 分支语义同步——任何修改都要两边一起改。
        /// </summary>
        internal ClickOutcome TryFireButtonClick(int upIdx)
        {
            bool wasTicking = WantsAnimationTick;
            int down = _downIndex;
            _downIndex = -1;
            string[] keys = _state == SaveState.Done
                ? DONE_KEYS
                : (_state == SaveState.Failed ? FAILED_KEYS : null);
            if (keys == null || upIdx < 0 || upIdx >= keys.Length) return ClickOutcome.OutOfRange;
            if (upIdx != down) return ClickOutcome.MismatchedDownUp;
            string key = keys[upIdx];
            if (key == "EXIT_CANCEL")
            {
                _armed = false;
                _dismissed = true;
                _hoverIndex = -1;
                _doneAutoDismissRemainingMs = 0;
                FireBounds();
                if (wasTicking) FireAnimationStateChanged();
                return ClickOutcome.Cancelled;
            }
            if (key == "SAFEEXIT")
            {
                _doneAutoDismissRemainingMs = 0;
                try { _router.Dispatch(key); }
                catch (Exception ex) { LogManager.Log("[SafeExitPanel] retry dispatch failed ex=" + ex.Message); }
                return ClickOutcome.Retried;
            }
            try { _router.Dispatch(key); }
            catch (Exception ex) { LogManager.Log("[SafeExitPanel] dispatch failed key=" + key + " ex=" + ex.Message); }
            return ClickOutcome.Confirmed;
        }

        internal enum ClickOutcome { OutOfRange, MismatchedDownUp, Cancelled, Confirmed, Retried }

        public bool WantsAnimationTick
        {
            get
            {
                return Visible && _state == SaveState.Done
                    && _doneAutoDismissRemainingMs > 0 && _hoverIndex < 0;
            }
        }

        public void Tick(int deltaMs)
        {
            if (!WantsAnimationTick || deltaMs <= 0) return;
            _doneAutoDismissRemainingMs -= deltaMs;
            if (_doneAutoDismissRemainingMs > 0) return;

            // 超时等价于安全取消：只收起二级确认，不执行退出。玩家仍可再次点 × 重开。
            _doneAutoDismissRemainingMs = 0;
            _armed = false;
            _dismissed = true;
            _state = SaveState.Idle;
            _hoverIndex = -1;
            _downIndex = -1;
            FireBounds();
            FireAnimationStateChanged();
        }

        public Rectangle ScreenBounds
        {
            get
            {
                if (!Visible) return Rectangle.Empty;
                if (_anchor == null || !_anchor.IsHandleCreated) return Rectangle.Empty;
                try
                {
                    int totalH = StatusH;
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
            float scale = Scale;
            float statusFontPx = WidgetScaler.Pxf(STATUS_FONT_BASE_PX, scale);
            float buttonFontPx = WidgetScaler.Pxf(BUTTON_FONT_BASE_PX, scale);

            using (SolidBrush fg          = new SolidBrush(NativeHudTheme.TextPrimary))
            using (SolidBrush fgHover     = new SolidBrush(NativeHudTheme.TextPrimary))
            using (Font statusFont        = NativeHudFonts.CreateUiFont(statusFontPx, FontStyle.Bold, GraphicsUnit.Pixel))
            using (Font buttonFont        = NativeHudFonts.CreateUiFont(buttonFontPx, FontStyle.Regular, GraphicsUnit.Pixel))
            using (StringFormat fmt       = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center })
            {
                TextRenderingHint prevHint = g.TextRenderingHint;
                g.TextRenderingHint = TextRenderingHint.AntiAlias;
                try
                {
                    bool hasActions = _state == SaveState.Done || _state == SaveState.Failed;
                    int statusW = hasActions ? Math.Max(1, (int)Math.Round(r.Width * 0.4)) : r.Width;
                    Rectangle statusRect = new Rectangle(localX, localY, statusW, statusH);
                    bool saving = _state == SaveState.Saving;
                    bool failed = _state == SaveState.Failed;
                    Color accent = failed
                        ? NativeHudTheme.Danger
                        : (saving ? NativeHudTheme.Warning : NativeHudTheme.Success);
                    Color statusFill = NativeHudTheme.Blend(NativeHudTheme.PanelFillDense,
                        accent, 0.14f, 238);
                    NativeHudTheme.DrawPanel(g, statusRect, scale, statusFill,
                        accent, true);
                    string statusText = saving ? "存盘中…" : (failed ? "存盘失败" : "存盘成功");
                    g.DrawString(statusText, statusFont, fg, statusRect, fmt);

                    if (hasActions)
                    {
                        string[] labels = failed ? FAILED_LABELS : DONE_LABELS;
                        int buttonAreaX = statusRect.Right;
                        int buttonAreaW = Math.Max(1, r.Right - hudOrigin.X - buttonAreaX);
                        int btnW = buttonAreaW / labels.Length;
                        for (int i = 0; i < labels.Length; i++)
                        {
                            int bx = buttonAreaX + i * btnW;
                            int bw = (i == labels.Length - 1) ? (buttonAreaW - i * btnW) : btnW;
                            Rectangle btn = new Rectangle(bx, localY, bw, statusH);
                            bool hover = (i == _hoverIndex);
                            NativeHudTheme.DrawButton(g, btn, scale, hover, false, false, !failed && i == 1);
                            g.DrawString(labels[i], buttonFont, hover ? fgHover : (Brush)fg, btn, fmt);
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
                case MouseEventKind.Cancel:
                    bool hadDown = _downIndex >= 0;
                    _downIndex = -1;
                    if (_hoverIndex >= 0) SetHover(-1);
                    else if (hadDown) FireRepaint();
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
            if (_state != SaveState.Done && _state != SaveState.Failed) return -1;
            if (sy < r.Y || sy >= r.Bottom) return -1;
            int statusW = Math.Max(1, (int)Math.Round(r.Width * 0.4));
            int buttonAreaX = r.X + statusW;
            if (sx < buttonAreaX || sx >= r.Right) return -1;
            int buttonAreaW = r.Right - buttonAreaX;
            int buttonCount = 2;
            int btnW = buttonAreaW / buttonCount;
            if (btnW <= 0) return -1;
            int relX = sx - buttonAreaX;
            int idx = relX / btnW;
            if (idx >= buttonCount) idx = buttonCount - 1;
            if (idx < 0 || idx >= buttonCount) return -1;
            return idx;
        }

        private void SetHover(int idx)
        {
            if (_hoverIndex == idx) return;
            bool wasTicking = WantsAnimationTick;
            _hoverIndex = idx;
            FireRepaint();
            if (wasTicking != WantsAnimationTick) FireAnimationStateChanged();
        }

        public void OnUiDataChanged(IReadOnlyDictionary<string, string> snapshot, ISet<string> changedKeys)
        {
            bool wasTicking = WantsAnimationTick;
            bool boundsDirty = false;
            bool repaintDirty = false;
            string piece;
            if (changedKeys.Contains("s") && snapshot.TryGetValue("s", out piece))
            {
                bool ready = UiValueParser.ParseUiBoolValue(piece);
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
                int sv = UiValueParser.ParseUiIntValue(piece, 0);
                SaveState next = _state;
                if (sv == 1)
                {
                    _sawSv1AfterArm = true;
                    next = SaveState.Saving;
                }
                else if (sv == 2)
                {
                    // armed session 里只有本轮 sv:1 → sv:2 顺序推达才允许置 Done：
                    // Arm 后尚未见过 sv:1 的 sv:2 是先前的通用 requestSave 迟到的完成事件，
                    // 若照样置 Done 会在 AS2 safeExit 尚未开始执行时提前授权 EXIT_CONFIRM。
                    // 未 armed 时保持旧的内部状态推进语义（面板不可见，Arm 会强制复位 Saving）。
                    if (!_armed || _sawSv1AfterArm) next = SaveState.Done;
                }
                else if (sv == 3) next = SaveState.Failed;
                else next = SaveState.Idle;
                if (next != _state)
                {
                    _state = next;
                    _downIndex = -1;
                    _hoverIndex = -1;
                    _doneAutoDismissRemainingMs = next == SaveState.Done && _armed
                        ? DONE_AUTO_DISMISS_MS
                        : 0;
                    // 已 armed 时状态推进影响显示内容（状态条 vs 按钮行 → 高度变化）
                    if (_armed) boundsDirty = true;
                    else repaintDirty = false; // 未 armed：不可见，无需 repaint
                }
            }
            if (boundsDirty) FireBounds();
            else if (repaintDirty) FireRepaint();
            if (wasTicking != WantsAnimationTick) FireAnimationStateChanged();
        }

        private void FireBounds() { EventHandler h = BoundsOrVisibilityChanged; if (h != null) h(this, EventArgs.Empty); }
        private void FireRepaint() { EventHandler h = RepaintRequested; if (h != null) h(this, EventArgs.Empty); }
        private void FireAnimationStateChanged() { EventHandler h = AnimationStateChanged; if (h != null) h(this, EventArgs.Empty); }
    }
}
