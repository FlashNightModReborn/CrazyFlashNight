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
        // IUiDataLegacyConsumer widget 计数：legacy（task/announce/...）入口同样走 fast path
        private volatile int _uiDataLegacyConsumerCount;
        // 已订阅的 legacy type 名集合（小写）。HandleUiData 用其门控：FrameTask 每帧推 combo|...，
        // 但 NotchToolbar/Currency/QuestNotice 都不订阅 combo → 整包早 return，不再 BeginInvoke。
        // 写时 lock _widgetsLock；读 HandleUiData 仅用于 Contains 命中检测，DCAS 风险可接受
        // （wait-and-go：若 widget 注册期间错过几帧 legacy 包，下一帧补到，不影响 task/announce 这种瞬时通知语义）
        private readonly HashSet<string> _registeredLegacyTypes = new HashSet<string>(StringComparer.Ordinal);
        // INotchNoticeConsumer 计数 + category 门控，与 legacy 同形式。
        // socket worker 每次 N 前缀都会调 AddNotice；无 widget 订阅时整条早 return，不污染 UI 线程。
        private volatile int _notchNoticeConsumerCount;
        private readonly HashSet<string> _registeredNoticeCategories = new HashSet<string>(StringComparer.Ordinal);

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
                IUiDataLegacyConsumer legacy = widget as IUiDataLegacyConsumer;
                if (legacy != null)
                {
                    _uiDataLegacyConsumerCount++;
                    IEnumerable<string> types = legacy.LegacyTypes;
                    if (types != null)
                    {
                        foreach (string t in types)
                        {
                            if (!string.IsNullOrEmpty(t)) _registeredLegacyTypes.Add(t);
                        }
                    }
                }
                INotchNoticeConsumer notice = widget as INotchNoticeConsumer;
                if (notice != null)
                {
                    _notchNoticeConsumerCount++;
                    IEnumerable<string> cats = notice.NoticeCategories;
                    if (cats != null)
                    {
                        foreach (string c in cats)
                        {
                            if (!string.IsNullOrEmpty(c)) _registeredNoticeCategories.Add(c);
                        }
                    }
                }
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
                if (_widgets.Remove(widget))
                {
                    if (widget is IUiDataConsumer) _uiDataConsumerCount--;
                    if (widget is IUiDataLegacyConsumer)
                    {
                        _uiDataLegacyConsumerCount--;
                        // 重建 _registeredLegacyTypes（依赖 widget 集合的 union，按需而不是每次 Add 维护单独 ref count）
                        _registeredLegacyTypes.Clear();
                        for (int i = 0; i < _widgets.Count; i++)
                        {
                            IUiDataLegacyConsumer remain = _widgets[i] as IUiDataLegacyConsumer;
                            if (remain == null) continue;
                            IEnumerable<string> types = remain.LegacyTypes;
                            if (types == null) continue;
                            foreach (string t in types)
                            {
                                if (!string.IsNullOrEmpty(t)) _registeredLegacyTypes.Add(t);
                            }
                        }
                    }
                    if (widget is INotchNoticeConsumer)
                    {
                        _notchNoticeConsumerCount--;
                        // 同样按需重建：Remove 不频繁，简单 union 重算比维护 per-category ref count 更稳
                        _registeredNoticeCategories.Clear();
                        for (int i = 0; i < _widgets.Count; i++)
                        {
                            INotchNoticeConsumer remain = _widgets[i] as INotchNoticeConsumer;
                            if (remain == null) continue;
                            IEnumerable<string> cats = remain.NoticeCategories;
                            if (cats == null) continue;
                            foreach (string c in cats)
                            {
                                if (!string.IsNullOrEmpty(c)) _registeredNoticeCategories.Add(c);
                            }
                        }
                    }
                }
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
        /// 计算 widget 集合声明的 legacy type union。internal static 便于单测覆盖
        /// "QuestNotice 注册 → 含 task/announce 不含 combo" 这种关键门控不变量。
        /// </summary>
        internal static HashSet<string> BuildLegacyTypeSet(IEnumerable<INativeHudWidget> widgets)
        {
            HashSet<string> result = new HashSet<string>(StringComparer.Ordinal);
            if (widgets == null) return result;
            foreach (INativeHudWidget w in widgets)
            {
                IUiDataLegacyConsumer legacy = w as IUiDataLegacyConsumer;
                if (legacy == null) continue;
                IEnumerable<string> types = legacy.LegacyTypes;
                if (types == null) continue;
                foreach (string t in types)
                {
                    if (!string.IsNullOrEmpty(t)) result.Add(t);
                }
            }
            return result;
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
            // Fast path：无任何 UiData 消费者（KV / legacy）时整条路径都没意义。
            // 这是 Phase 1 的 perf baseline 保护：tee 路径在 useNativeHud=true 时被 socket worker 高频调用，
            // 不能因解析 + lock + BeginInvoke 污染 GPU/CPU 对比数据。
            if (_uiDataConsumerCount == 0 && _uiDataLegacyConsumerCount == 0) return;

            // 旧版 (type|f1|f2) 格式优先探测：第一段无 ":" 且总段数 ≥ 2 → 走 legacy 路径，不写 snapshot
            string legacyType;
            string[] legacyFields;
            if (UiDataPacketParser.TryParseLegacy(rawData, out legacyType, out legacyFields))
            {
                if (_uiDataLegacyConsumerCount == 0) return;
                // 类型门控：仅有 widget 声明 LegacyTypes 包含此 type 时才 BeginInvoke。
                // FrameTask 每帧推 combo|...，但 QuestNotice 只关心 task/announce → combo 包整段早 return，
                // 不污染 UI 线程派发预算。
                bool typeRegistered;
                lock (_widgetsLock) { typeRegistered = _registeredLegacyTypes.Contains(legacyType); }
                if (!typeRegistered) return;
                if (!this.IsHandleCreated) return;
                string capturedType = legacyType;
                string[] capturedFields = legacyFields;
                try
                {
                    this.BeginInvoke(new Action(delegate
                    {
                        DispatchLegacyUiDataToWidgets(capturedType, capturedFields);
                    }));
                }
                catch { }
                return;
            }

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

        private void DispatchLegacyUiDataToWidgets(string type, string[] fields)
        {
            INativeHudWidget[] widgetSnapshot;
            lock (_widgetsLock) { widgetSnapshot = _widgets.ToArray(); }

            for (int i = 0; i < widgetSnapshot.Length; i++)
            {
                IUiDataLegacyConsumer consumer = widgetSnapshot[i] as IUiDataLegacyConsumer;
                if (consumer == null) continue;
                try { consumer.OnLegacyUiData(type, fields); }
                catch (Exception ex) { LogManager.Log("[NativeHud] widget LegacyUiData throw: " + ex.Message); }
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

        // 跟踪 left-button down 命中的 widget，只在 Up 命中同 widget 时合成 Click。
        // 这样防止"按下 widget A 拖到 widget B 松开 → A 或 B 误触发 Click"——
        // 尤其是退出确认这种 destructive 操作必须按下/松开匹配。
        private INativeHudWidget _leftDownWidget;

        protected override void OnMouseDown(MouseEventArgs e)
        {
            base.OnMouseDown(e);
            Point screenPt = this.PointToScreen(e.Location);
            INativeHudWidget hit = HitTestScreen(screenPt);
            if (e.Button == MouseButtons.Left) _leftDownWidget = hit;
            if (hit == null) return;
            try { hit.OnMouseEvent(new MouseEventArgs(e.Button, e.Clicks, screenPt.X, screenPt.Y, e.Delta), MouseEventKind.Down); }
            catch (Exception ex) { LogManager.Log("[NativeHud] widget Down throw: " + ex.Message); }
        }

        protected override void OnMouseUp(MouseEventArgs e)
        {
            base.OnMouseUp(e);
            Point screenPt = this.PointToScreen(e.Location);
            INativeHudWidget hit = HitTestScreen(screenPt);
            INativeHudWidget downWidget = _leftDownWidget;
            if (e.Button == MouseButtons.Left) _leftDownWidget = null;
            if (hit == null) return;
            MouseEventArgs sArgs = new MouseEventArgs(e.Button, e.Clicks, screenPt.X, screenPt.Y, e.Delta);
            try { hit.OnMouseEvent(sArgs, MouseEventKind.Up); }
            catch (Exception ex) { LogManager.Log("[NativeHud] widget Up throw: " + ex.Message); }
            // Form 的 OnMouseClick 在 Down/Up 同一控件时才 fire。仿此语义：仅当 Up widget == Down widget 才派发 Click。
            // widget 内部如需 button-level 匹配（e.g. SafeExitPanel 的取消/退出），自行用 Down/Up 跟踪 _downIndex。
            if (e.Button == MouseButtons.Left && hit == downWidget)
            {
                try { hit.OnMouseEvent(sArgs, MouseEventKind.Click); }
                catch (Exception ex) { LogManager.Log("[NativeHud] widget Click throw: " + ex.Message); }
            }
        }

        #endregion

        #region INotchSink / IToastSink — Phase 1 silent stub

        // Phase 3 由 NotchWidget / ToastWidget 接管这些方法（widget 持状态、NativeHud 仅做调度）。
        // Phase 1 silent no-op，避免 socket worker 调用时抛异常。

        /// <summary>
        /// 已有 native consumer 订阅此 category？供 CompositeNotchSink 路由：native 处理的 category
        /// 不再 forward 给 webOverlay/NotchOverlay，避免双重显示（如 N combo|... 同时弹 ComboWidget 命中条 + NotchOverlay 通知行）。
        /// </summary>
        public bool HasNoticeConsumerFor(string category)
        {
            if (_notchNoticeConsumerCount == 0) return false;
            if (string.IsNullOrEmpty(category)) return false;
            lock (_widgetsLock) { return _registeredNoticeCategories.Contains(category); }
        }

        public void AddNotice(string category, string text, Color accentColor)
        {
            // Phase 4: fan out 到 INotchNoticeConsumer widget（如 ComboWidget 处理 N combo|...）。
            // Fast path：无 consumer / category 未订阅 → 整条早 return，不污染 UI 线程预算。
            if (_notchNoticeConsumerCount == 0) return;
            if (string.IsNullOrEmpty(category)) return;
            bool registered;
            lock (_widgetsLock) { registered = _registeredNoticeCategories.Contains(category); }
            if (!registered) return;
            if (!this.IsHandleCreated) return;
            string capCategory = category;
            string capText = text ?? "";
            Color capColor = accentColor;
            try
            {
                this.BeginInvoke(new Action(delegate
                {
                    DispatchNotchNoticeToWidgets(capCategory, capText, capColor);
                }));
            }
            catch { }
        }

        private void DispatchNotchNoticeToWidgets(string category, string text, Color accentColor)
        {
            INativeHudWidget[] widgetSnapshot;
            lock (_widgetsLock) { widgetSnapshot = _widgets.ToArray(); }
            for (int i = 0; i < widgetSnapshot.Length; i++)
            {
                INotchNoticeConsumer consumer = widgetSnapshot[i] as INotchNoticeConsumer;
                if (consumer == null) continue;
                IEnumerable<string> cats = consumer.NoticeCategories;
                if (cats == null) continue;
                bool match = false;
                foreach (string c in cats)
                {
                    if (string.Equals(c, category, StringComparison.Ordinal)) { match = true; break; }
                }
                if (!match) continue;
                try { consumer.OnNotchNotice(category, text, accentColor); }
                catch (Exception ex) { LogManager.Log("[NativeHud] widget Notice throw: " + ex.Message); }
            }
        }

        /// <summary>
        /// 测试钩子（InternalsVisibleTo("Launcher.Tests")）：从 widget 集合构造 category union；
        /// 与 Add/RemoveWidget 内重建逻辑共享语义，独立可测。
        /// </summary>
        internal static HashSet<string> BuildNoticeCategorySet(IEnumerable<INativeHudWidget> widgets)
        {
            HashSet<string> result = new HashSet<string>(StringComparer.Ordinal);
            if (widgets == null) return result;
            foreach (INativeHudWidget w in widgets)
            {
                INotchNoticeConsumer notice = w as INotchNoticeConsumer;
                if (notice == null) continue;
                IEnumerable<string> cats = notice.NoticeCategories;
                if (cats == null) continue;
                foreach (string c in cats)
                {
                    if (!string.IsNullOrEmpty(c)) result.Add(c);
                }
            }
            return result;
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
