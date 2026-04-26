using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Linq;
using System.Windows.Forms;
using CF7Launcher.Guardian.Hud;

namespace CF7Launcher.Guardian
{
    /// <summary>
    /// 原生 HUD 容器。承载 NotchWidget / ToastWidget / 各 Status widget。
    ///
    /// 关键设计（与 WebView2 layered overlay 对比）：
    /// - 动态 bounds：窗口大小 = 所有 Visible widget 的 ScreenBounds union（+padding）；空 → SW_HIDE
    /// - request-frame：仅在有 widget WantsAnimationTick 时启 16ms timer；池为空 → Stop
    /// - 单帧重绘：RepaintRequested 触发单次 invalidate，不强行启 tick
    /// - DWM α 成本：只占被 widget 实际覆盖的矩形，避免全屏 layered window 的 per-pixel α traversal
    ///
    /// Phase 1 范围：
    /// - 实现 widget 容器、bounds union、request-frame timer、UiData 派发与 WM_NCHITTEST 路由
    /// - INotchSink/IToastSink 接口签名先 silent no-op（Phase 3 由 NotchWidget/ToastWidget 接管）
    /// </summary>
    public class NativeHudOverlay : OverlayBase, INotchSink, IToastSink
    {
        protected override bool IsClickThrough { get { return false; } }

        private readonly List<INativeHudWidget> _widgets = new List<INativeHudWidget>();
        private readonly object _widgetsLock = new object();
        // IUiDataConsumer widget 计数：HandleUiData fast path 检查，无 consumer 直接早 return
        // 避免 Phase 1 无 widget 时 socket 高频 UiData 流污染 perf baseline（解析 + lock + BeginInvoke 全部跳过）
        private volatile int _uiDataConsumerCount;

        private readonly Dictionary<string, string> _uiDataSnapshot = new Dictionary<string, string>();
        private readonly object _uiDataLock = new object();

        private Bitmap _composedBitmap;
        private int _composedW;
        private int _composedH;

        private Timer _animTick;
        private int _padding = 6;
        private bool _suspendedForPanel;
        private bool _ready;

        // 上一帧 hud 屏幕原点；用于决定是否需要 SetWindowPos
        private Point _hudOrigin;
        private Size _hudSize;

        // z-order 锚点：NativeHud 必须沉到 HitNumber/Cursor 之下，否则 widget 区域会遮挡伤害数字与鼠标
        // 默认 IntPtr.Zero → 退回 HWND_TOP（仅 widget 未注册前的过渡态使用）
        private IntPtr _zOrderInsertAfter;

        public NativeHudOverlay(Form owner, Control anchor)
            : base(owner, anchor, 1024f, 576f)
        {
            _animTick = new Timer();
            _animTick.Interval = 16;
            _animTick.Tick += OnAnimTick;
            // 默认 stopped；MaybeStartTick 在 widget enroll 时启
        }

        #region Lifecycle

        /// <summary>由 Program.cs 在所有 widget 注册完毕后调用。</summary>
        public void SetReady()
        {
            _ready = true;
            RecomputeBounds();
        }

        /// <summary>
        /// Program.cs 在 HitNumberOverlay 实例化后调用，把 NativeHud 沉到 HitNumber 之下。
        /// 不调则退回 HWND_TOP（widget 区域会遮挡伤害数字 + Cursor）。
        /// </summary>
        public void SetZOrderInsertAfter(IntPtr insertAfter)
        {
            _zOrderInsertAfter = insertAfter;
            if (_ready) RecomputeBounds();
        }

        /// <summary>Panel 态调用：SW_HIDE + 停 tick。</summary>
        public void Suspend()
        {
            _suspendedForPanel = true;
            if (_animTick != null) _animTick.Stop();
            DismissOverlay();
        }

        /// <summary>Panel 关闭后调用：重新评估 widget union 决定可见性。</summary>
        public void Resume()
        {
            _suspendedForPanel = false;
            RecomputeBounds();
        }

        public bool IsSuspended { get { return _suspendedForPanel; } }

        #endregion

        #region Widget 容器

        public void AddWidget(INativeHudWidget widget)
        {
            if (widget == null) return;
            lock (_widgetsLock)
            {
                _widgets.Add(widget);
                if (widget is IUiDataConsumer) _uiDataConsumerCount++;
            }
            widget.BoundsOrVisibilityChanged += OnWidgetBoundsChanged;
            widget.RepaintRequested += OnWidgetRepaintRequested;
            widget.AnimationStateChanged += OnWidgetAnimationStateChanged;
            if (_ready) RecomputeBounds();
        }

        public void RemoveWidget(INativeHudWidget widget)
        {
            if (widget == null) return;
            lock (_widgetsLock)
            {
                if (_widgets.Remove(widget) && widget is IUiDataConsumer)
                    _uiDataConsumerCount--;
            }
            widget.BoundsOrVisibilityChanged -= OnWidgetBoundsChanged;
            widget.RepaintRequested -= OnWidgetRepaintRequested;
            widget.AnimationStateChanged -= OnWidgetAnimationStateChanged;
            if (_ready) RecomputeBounds();
        }

        private void OnWidgetBoundsChanged(object sender, EventArgs e)
        {
            if (this.IsHandleCreated && this.InvokeRequired)
            {
                try { this.BeginInvoke(new Action(RecomputeBounds)); } catch { }
                return;
            }
            RecomputeBounds();
        }

        private void OnWidgetRepaintRequested(object sender, EventArgs e)
        {
            if (this.IsHandleCreated && this.InvokeRequired)
            {
                try { this.BeginInvoke(new Action(RenderToBitmapAndCommit)); } catch { }
                return;
            }
            RenderToBitmapAndCommit();
        }

        private void OnWidgetAnimationStateChanged(object sender, EventArgs e)
        {
            if (this.IsHandleCreated && this.InvokeRequired)
            {
                try { this.BeginInvoke(new Action(MaybeStartTick)); } catch { }
                return;
            }
            MaybeStartTick();
        }

        #endregion

        #region Bounds 计算 + 渲染

        /// <summary>
        /// 计算 widget 集合的 bounds union（含 padding）。internal static 便于单测。
        /// 返回 null 表示无 visible widget（NativeHud 应 SW_HIDE）。
        /// 跳过非 Visible widget 与零宽高 ScreenBounds（widget 可能在 collapsing 中段返回零矩形）。
        /// </summary>
        internal static Rectangle? ComputeBoundsUnion(IEnumerable<INativeHudWidget> widgets, int padding)
        {
            if (widgets == null) return null;
            Rectangle? union = null;
            foreach (INativeHudWidget w in widgets)
            {
                if (w == null || !w.Visible) continue;
                Rectangle r = w.ScreenBounds;
                if (r.Width <= 0 || r.Height <= 0) continue;
                union = union.HasValue ? Rectangle.Union(union.Value, r) : r;
            }
            if (!union.HasValue) return null;
            return Rectangle.Inflate(union.Value, padding, padding);
        }

        /// <summary>
        /// 判断是否需要启动 animation tick：任一 visible widget 声明 WantsAnimationTick。
        /// internal static 便于单测。
        /// </summary>
        internal static bool ShouldRunAnimationTick(IEnumerable<INativeHudWidget> widgets)
        {
            if (widgets == null) return false;
            foreach (INativeHudWidget w in widgets)
            {
                if (w == null || !w.Visible) continue;
                if (w.WantsAnimationTick) return true;
            }
            return false;
        }

        private void RecomputeBounds()
        {
            if (!_ready || _suspendedForPanel) return;

            INativeHudWidget[] snapshot;
            lock (_widgetsLock) { snapshot = _widgets.ToArray(); }

            Rectangle? padded = ComputeBoundsUnion(snapshot, _padding);
            if (!padded.HasValue)
            {
                if (_animTick != null) _animTick.Stop();
                DismissOverlay();
                return;
            }
            Rectangle hudRect = padded.Value;
            _hudOrigin = new Point(hudRect.X, hudRect.Y);
            _hudSize = new Size(hudRect.Width, hudRect.Height);

            EnsureComposedBitmap(hudRect.Width, hudRect.Height);
            // z-order：插在 _zOrderInsertAfter（HitNumber.Handle）之后，让 NativeHud 沉到
            // HitNumber/Cursor 之下，保持架构链 Cursor → HitNumber → NativeHud → (Backdrop → WebOverlay) → Flash。
            // 未注册（_zOrderInsertAfter == Zero）时退回 HWND_TOP 仅作过渡态兜底。
            // 架构约束见 plans/expressive-leaping-galaxy.md §硬约束 #5
            IntPtr insertAfter = _zOrderInsertAfter == IntPtr.Zero ? HWND_TOP : _zOrderInsertAfter;
            SetWindowPos(this.Handle, insertAfter, hudRect.X, hudRect.Y, hudRect.Width, hudRect.Height,
                SWP_NOACTIVATE);
            // 用 ShowOverlayBelow 而非 ShowOverlay：后者会把 z-order 拉到 HWND_TOP，覆盖上面的 insertAfter。
            ShowOverlayBelow(insertAfter);
            // 兜底：ShowOverlayBelow 受 _ownerVisible 闸门控制，
            // panel 关闭时焦点常在 Flash 子窗口 → owner 仍 deactivated → ShowWindow 被跳过。
            // 直接 SW_SHOWNOACTIVATE 强制显示；ShowWindow 不改 z-order，上面 insertAfter 排序保留。
            try { ShowWindow(this.Handle, SW_SHOWNOACTIVATE); } catch { }
            RenderToBitmapAndCommit();
            MaybeStartTick();
        }

        private void EnsureComposedBitmap(int w, int h)
        {
            if (_composedBitmap != null && _composedW == w && _composedH == h) return;
            if (_composedBitmap != null) _composedBitmap.Dispose();
            _composedBitmap = new Bitmap(Math.Max(1, w), Math.Max(1, h),
                System.Drawing.Imaging.PixelFormat.Format32bppPArgb);
            _composedW = w;
            _composedH = h;
        }

        private void RenderToBitmapAndCommit()
        {
            if (!_ready || _suspendedForPanel) return;
            if (_composedBitmap == null) return;

            INativeHudWidget[] snapshot;
            lock (_widgetsLock) { snapshot = _widgets.ToArray(); }

            using (Graphics g = Graphics.FromImage(_composedBitmap))
            {
                g.CompositingMode = CompositingMode.SourceCopy;
                g.Clear(Color.FromArgb(0, 0, 0, 0));
                g.CompositingMode = CompositingMode.SourceOver;
                g.SmoothingMode = SmoothingMode.AntiAlias;
                g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;

                for (int i = 0; i < snapshot.Length; i++)
                {
                    INativeHudWidget w = snapshot[i];
                    if (!w.Visible) continue;
                    try { w.Paint(g, 1.0f, _hudOrigin); }
                    catch (Exception ex) { LogManager.Log("[NativeHud] widget Paint throw: " + ex.Message); }
                }
            }

            CommitBitmap(_composedBitmap, _hudOrigin.X, _hudOrigin.Y, 255);
        }

        private void MaybeStartTick()
        {
            if (!_ready || _suspendedForPanel) return;
            if (_animTick == null) return;

            INativeHudWidget[] snapshot;
            lock (_widgetsLock) { snapshot = _widgets.ToArray(); }

            bool wantsTick = ShouldRunAnimationTick(snapshot);
            if (wantsTick && !_animTick.Enabled) _animTick.Start();
            else if (!wantsTick && _animTick.Enabled) _animTick.Stop();
        }

        private int _lastTickMs;
        private void OnAnimTick(object sender, EventArgs e)
        {
            int now = Environment.TickCount;
            int delta = _lastTickMs == 0 ? 16 : Math.Max(1, now - _lastTickMs);
            _lastTickMs = now;

            INativeHudWidget[] snapshot;
            lock (_widgetsLock) { snapshot = _widgets.ToArray(); }

            for (int i = 0; i < snapshot.Length; i++)
            {
                INativeHudWidget w = snapshot[i];
                if (!w.Visible || !w.WantsAnimationTick) continue;
                try { w.Tick(delta); }
                catch (Exception ex) { LogManager.Log("[NativeHud] widget Tick throw: " + ex.Message); }
            }
            RenderToBitmapAndCommit();
        }

        #endregion

        #region UiData 派发

        /// <summary>
        /// XmlSocketServer / FrameTask 入口。解析合批包 → 更新 snapshot → 通知 IUiDataConsumer widget。
        /// 调用线程不固定（socket worker / UI 线程都可能），内部 BeginInvoke 切回 UI 线程。
        /// </summary>
        public void HandleUiData(string rawData)
        {
            if (string.IsNullOrEmpty(rawData)) return;
            // Fast path：无 IUiDataConsumer widget 时整条路径都没意义（snapshot 无消费者，Phase 3+ widget
            // 注册时会一次性接到当时的 UiData 流，不需要 backfill 历史）。
            // 这是 Phase 1 的 perf baseline 保护：tee 路径在 useNativeHud=true 时被 socket worker 高频调用，
            // 不能因解析 + lock + BeginInvoke 污染 GPU/CPU 对比数据。
            if (_uiDataConsumerCount == 0) return;

            HashSet<string> changedKeys = new HashSet<string>();
            Dictionary<string, string> snapshotCopy;
            lock (_uiDataLock)
            {
                foreach (KeyValuePair<string, string> kv in UiDataPacketParser.Parse(rawData))
                {
                    string key = kv.Key;
                    string fullPiece = kv.Value;
                    string prev;
                    if (!_uiDataSnapshot.TryGetValue(key, out prev) || prev != fullPiece)
                    {
                        _uiDataSnapshot[key] = fullPiece;
                        changedKeys.Add(key);
                    }
                }
                if (changedKeys.Count == 0) return;
                // 拷贝快照传给 UI 线程，避免 socket 线程后续修改时 widget 读到并发状态
                snapshotCopy = new Dictionary<string, string>(_uiDataSnapshot);
            }

            if (!this.IsHandleCreated) return;
            try
            {
                this.BeginInvoke(new Action(delegate
                {
                    DispatchUiDataToWidgets(snapshotCopy, changedKeys);
                }));
            }
            catch { }
        }

        private void DispatchUiDataToWidgets(Dictionary<string, string> snapshot, HashSet<string> changedKeys)
        {
            INativeHudWidget[] widgetSnapshot;
            lock (_widgetsLock) { widgetSnapshot = _widgets.ToArray(); }

            for (int i = 0; i < widgetSnapshot.Length; i++)
            {
                IUiDataConsumer consumer = widgetSnapshot[i] as IUiDataConsumer;
                if (consumer == null) continue;
                try { consumer.OnUiDataChanged(snapshot, changedKeys); }
                catch (Exception ex) { LogManager.Log("[NativeHud] widget UiData throw: " + ex.Message); }
            }
        }

        #endregion

        #region 命中测试 + 鼠标路由

        // Win32: 防止点击 NativeHud 转移激活状态（否则 GuardianForm.Deactivate → OverlayBase.HideOverlay → SW_HIDE）
        private const int WM_MOUSEACTIVATE = 0x0021;
        private const int MA_NOACTIVATE = 3;

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == WM_MOUSEACTIVATE)
            {
                // 关键：返回 MA_NOACTIVATE 让点击不抢前台。
                // WS_EX_NOACTIVATE 只阻止"自动"激活（show/click），不阻止系统在某些路径下重排 z-order；
                // 显式拦 WM_MOUSEACTIVATE 才能保证 GuardianForm 永远不 Deactivate，widget 可被反复点击。
                m.Result = (IntPtr)MA_NOACTIVATE;
                return;
            }
            if (m.Msg == WM_NCHITTEST)
            {
                long lp = m.LParam.ToInt64();
                int sx = (short)(lp & 0xFFFF);
                int sy = (short)((lp >> 16) & 0xFFFF);
                Point screenPt = new Point(sx, sy);

                INativeHudWidget[] snapshot;
                lock (_widgetsLock) { snapshot = _widgets.ToArray(); }
                for (int i = 0; i < snapshot.Length; i++)
                {
                    INativeHudWidget w = snapshot[i];
                    if (!w.Visible) continue;
                    if (w.TryHitTest(screenPt))
                    {
                        m.Result = (IntPtr)1; // HTCLIENT
                        return;
                    }
                }
                m.Result = (IntPtr)HTTRANSPARENT;
                return;
            }
            base.WndProc(ref m);
        }

        // Phase 4：鼠标事件路由。命中 widget → 转屏幕坐标 → OnMouseEvent。
        // 仅向当前命中 widget 派发；hover 切换通过 Move 事件 + widget 自身 idx 比对处理。
        private INativeHudWidget _lastHoverWidget;

        private INativeHudWidget HitTestScreen(Point screenPt)
        {
            INativeHudWidget[] snapshot;
            lock (_widgetsLock) { snapshot = _widgets.ToArray(); }
            for (int i = snapshot.Length - 1; i >= 0; i--)
            {
                INativeHudWidget w = snapshot[i];
                if (w == null || !w.Visible) continue;
                if (w.TryHitTest(screenPt)) return w;
            }
            return null;
        }

        protected override void OnMouseMove(MouseEventArgs e)
        {
            base.OnMouseMove(e);
            Point screenPt = this.PointToScreen(e.Location);
            INativeHudWidget hit = HitTestScreen(screenPt);
            MouseEventArgs screenArgs = new MouseEventArgs(e.Button, e.Clicks, screenPt.X, screenPt.Y, e.Delta);
            if (hit != _lastHoverWidget)
            {
                if (_lastHoverWidget != null)
                    try { _lastHoverWidget.OnMouseEvent(screenArgs, MouseEventKind.Leave); }
                    catch (Exception ex) { LogManager.Log("[NativeHud] widget Leave throw: " + ex.Message); }
                if (hit != null)
                    try { hit.OnMouseEvent(screenArgs, MouseEventKind.Enter); }
                    catch (Exception ex) { LogManager.Log("[NativeHud] widget Enter throw: " + ex.Message); }
                _lastHoverWidget = hit;
            }
            if (hit != null)
                try { hit.OnMouseEvent(screenArgs, MouseEventKind.Move); }
                catch (Exception ex) { LogManager.Log("[NativeHud] widget Move throw: " + ex.Message); }
        }

        protected override void OnMouseLeave(EventArgs e)
        {
            base.OnMouseLeave(e);
            if (_lastHoverWidget != null)
            {
                try { _lastHoverWidget.OnMouseEvent(new MouseEventArgs(MouseButtons.None, 0, 0, 0, 0), MouseEventKind.Leave); }
                catch (Exception ex) { LogManager.Log("[NativeHud] widget Leave throw: " + ex.Message); }
                _lastHoverWidget = null;
            }
        }

        protected override void OnMouseDown(MouseEventArgs e)
        {
            base.OnMouseDown(e);
            Point screenPt = this.PointToScreen(e.Location);
            INativeHudWidget hit = HitTestScreen(screenPt);
            if (hit == null) return;
            try { hit.OnMouseEvent(new MouseEventArgs(e.Button, e.Clicks, screenPt.X, screenPt.Y, e.Delta), MouseEventKind.Down); }
            catch (Exception ex) { LogManager.Log("[NativeHud] widget Down throw: " + ex.Message); }
        }

        protected override void OnMouseUp(MouseEventArgs e)
        {
            base.OnMouseUp(e);
            Point screenPt = this.PointToScreen(e.Location);
            INativeHudWidget hit = HitTestScreen(screenPt);
            if (hit == null) return;
            MouseEventArgs sArgs = new MouseEventArgs(e.Button, e.Clicks, screenPt.X, screenPt.Y, e.Delta);
            try { hit.OnMouseEvent(sArgs, MouseEventKind.Up); }
            catch (Exception ex) { LogManager.Log("[NativeHud] widget Up throw: " + ex.Message); }
            // Form 的 OnMouseClick 在 Down/Up 同一控件时也会 fire；为简化路由直接在 Up 内派发 Click。
            if (e.Button == MouseButtons.Left)
            {
                try { hit.OnMouseEvent(sArgs, MouseEventKind.Click); }
                catch (Exception ex) { LogManager.Log("[NativeHud] widget Click throw: " + ex.Message); }
            }
        }

        #endregion

        #region INotchSink / IToastSink — Phase 1 silent stub

        // Phase 3 由 NotchWidget / ToastWidget 接管这些方法（widget 持状态、NativeHud 仅做调度）。
        // Phase 1 silent no-op，避免 socket worker 调用时抛异常。

        public void AddNotice(string category, string text, Color accentColor)
        {
            // Phase 3 → notchWidget.AddNotice(...)
        }

        public void SetStatusItem(string id, string label, string subLabel, Color accentColor)
        {
            // Phase 3 → notchWidget.SetStatusItem(...)
        }

        public void ClearStatusItem(string id)
        {
            // Phase 3 → notchWidget.ClearStatusItem(...)
        }

        void INotchSink.SetReady()
        {
            // Phase 1：复用 Lifecycle.SetReady()
            this.SetReady();
        }

        public void AddMessage(string text)
        {
            // Phase 3 → toastWidget.AddMessage(...)
        }

        void IToastSink.SetReady()
        {
            this.SetReady();
        }

        #endregion

        protected override void OnPositionChanged()
        {
            // Owner / anchor 移动时，widget 的 ScreenBounds 通常通过 BoundsOrVisibilityChanged 已 fire；
            // 但 anchor resize 也可能不触发 widget event（widget 可能基于绝对 anchor 锚点计算），
            // 故主动重算一次 union 与窗口位置。
            RecomputeBounds();
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                if (_animTick != null) { _animTick.Stop(); _animTick.Dispose(); _animTick = null; }
                if (_composedBitmap != null) { _composedBitmap.Dispose(); _composedBitmap = null; }
            }
            base.Dispose(disposing);
        }
    }
}
