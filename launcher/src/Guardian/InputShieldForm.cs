using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using Microsoft.Web.WebView2.Core;

namespace CF7Launcher.Guardian
{
    /// <summary>
    /// Legacy WebOverlay hit regions and full-screen panel telemetry.
    /// With session pointer authority bound, the shield is transparent to hit testing
    /// and only observes panel telemetry shared by WebOverlay's mouse hook.
    /// </summary>
    public class InputShieldForm : OverlayBase
    {
        #region Win32 (TrackMouseEvent + Foreground)

        [DllImport("user32.dll")]
        private static extern bool TrackMouseEvent(ref TRACKMOUSEEVENT lpEventTrack);

        [DllImport("user32.dll")]
        private static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll")]
        private static extern bool IsChild(IntPtr hWndParent, IntPtr hWnd);

        [StructLayout(LayoutKind.Sequential)]
        private struct TRACKMOUSEEVENT
        {
            public int cbSize;
            public uint dwFlags;
            public IntPtr hwndTrack;
            public int dwHoverTime;
        }

        private const uint TME_LEAVE = 0x00000002;

        #endregion

        private const int HTCLIENT = 1;
        private const int WM_MOUSEMOVE = 0x0200;
        private const int WM_LBUTTONDOWN = 0x0201;
        private const int WM_LBUTTONUP = 0x0202;
        private const int WM_RBUTTONDOWN = 0x0204;
        private const int WM_RBUTTONUP = 0x0205;
        private const int WM_MOUSELEAVE = 0x02A3;
        private const int WM_MOUSEWHEEL = 0x020A;
        private const int WM_CAPTURECHANGED = 0x0215;

        private const int WM_MOUSEACTIVATE = 0x0021;
        private const int MA_NOACTIVATE = 3;

        /// <summary>不穿透——本层需要在命中区域接收鼠标。</summary>
        protected override bool IsClickThrough { get { return false; } }

        /// <summary>JS 上报的交互区域（相对于本 Form 客户区）。</summary>
        private readonly List<Rectangle> _hitRects = new List<Rectangle>();

        /// <summary>当前 alpha 位图（缓存避免每帧重建）。</summary>
        private Bitmap _maskBitmap;
        private int _maskW;
        private int _maskH;

        /// <summary>WebOverlayForm 的 CoreWebView2 引用，用于 CDP 注入。</summary>
        private CoreWebView2 _targetWebView;

        /// <summary>当前 overlay 的屏幕坐标（CommitBitmap 需要）。</summary>
        private int _screenX;
        private int _screenY;

        /// <summary>mask 未初始化时暂存的 raw rects，OnPositionChanged 后重新应用。</summary>
        private List<Rectangle> _pendingRawRects;

        /// <summary>鼠标是否在命中区域内（用于 leave 检测）。</summary>
        private bool _mouseTracking;
        private bool _mouseInside;

        private int _pressedButtons;
        private bool _pointerAuthorityBound;
        private bool LegacyHitRegionsEnabled => !_pointerAuthorityBound && ShouldApplyInteractiveRects(_telemetryActive);

        /// <summary>Overlay/WebView2 坐标上下文；缺失 Web metrics 时使用 fallback zoom。</summary>
        private OverlayCoordinateContext _coordinateContext;
        private double _fallbackZoom = 1.0;
        private Action<int, int> _cursorSampleSink;

        /// <summary>收起冷却：hitRect 缩小后短暂禁止 CDP mouseMoved，防振荡。</summary>
        private int _lastHitWidth;
        private long _collapseTick;

        public InputShieldForm(Form owner, Control anchor)
            : base(owner, anchor, 1024f, 576f)
        {
        }

        /// <summary>
        /// 注入 WebView2 引用。在 WebOverlayForm 初始化完成后调用。
        /// </summary>
        public void SetTargetWebView(CoreWebView2 webView)
        {
            if (ReferenceEquals(_targetWebView, webView)) return;
            CancelActivePointerGesture();
            _targetWebView = webView;
        }

        internal void SetPointerAuthorityBound(bool bound)
        {
            if (_pointerAuthorityBound == bound || IsDisposed || Disposing) return;
            _pointerAuthorityBound = bound;
            CancelActivePointerGesture();
            ClearInteractiveRects();
        }

        /// <summary>更新缩放比。WebOverlayForm 在 SyncPosition 时调用。</summary>
        public void SetZoomFactor(double zoom)
        {
            _fallbackZoom = Math.Max(0.25, zoom);
        }

        public void SetCoordinateContext(OverlayCoordinateContext context)
        {
            _coordinateContext = context;
        }

        public void SetCursorSampleSink(Action<int, int> sink)
        {
            _cursorSampleSink = sink;
        }

        #region Telemetry-only 模式（Phase 2 实化）
        // Phase 2：α 蒙版清空（全 0 → HTTRANSPARENT），复用 WebOverlay mouse hook 观察 panel 矩形外 click。
        // 过滤条件（必须全部满足才计数到 _clicksOutsidePanel）：
        //   1) 前台窗口 = guardianHwnd 或其子窗口（排除桌面/其他窗口的无关 click）
        //   2) click 屏幕坐标在 anchorScreenRect 内（排除 Flash 区域外的 click）
        //   3) click 屏幕坐标 NOT 在 panelRect 内
        // 满足 1 但不满足 3 → 玩家正常点 panel 内部，不计数（避免噪声）。
        // 不满足 1 → 玩家点桌面/其他应用，记 _filteredExternal。
        // 用途：Phase 6 Soak 期收集"clicks_outside_panel 是否有异常聚集"作为 InputShield 删除前的安全证据。

        private bool _telemetryActive;
        [DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
        public bool TelemetryActive { get { return _telemetryActive; } }

        private Rectangle _telemetryPanelRect;
        private Rectangle _telemetryAnchorRect;
        private IntPtr _telemetryGuardianHwnd;
        // panel 接管前台后 foreground = WebOverlay HWND（owned top-level，不是 IsChild）；纳入白名单避免污染数据
        private IntPtr _telemetryWebOverlayHwnd;
        private int _clicksOutsidePanel;
        private int _sessionTotalClicks;
        private int _filteredExternalClicks;

        public void EnterTelemetryMode(Rectangle panelRect, IntPtr guardianHwnd, Rectangle anchorScreenRect,
                                       IntPtr webOverlayHwnd)
        {
            if (IsDisposed || Disposing) return;
            if (_telemetryActive)
            {
                // 同 panel A → B 切换：刷新矩形与 owner，保留本轮统计。
                _telemetryPanelRect = panelRect;
                _telemetryAnchorRect = anchorScreenRect;
                _telemetryGuardianHwnd = guardianHwnd;
                _telemetryWebOverlayHwnd = webOverlayHwnd;
                ClearInteractiveRects();
                LogManager.Log("[InputShield] telemetry refresh source=shared_cursor_hook panel=" + panelRect.Width + "x" + panelRect.Height);
                return;
            }
            _telemetryActive = true;
            _telemetryPanelRect = panelRect;
            _telemetryAnchorRect = anchorScreenRect;
            _telemetryGuardianHwnd = guardianHwnd;
            _telemetryWebOverlayHwnd = webOverlayHwnd;
            _clicksOutsidePanel = 0;
            _sessionTotalClicks = 0;
            _filteredExternalClicks = 0;

            // Telemetry 只观测，不参与 panel 输入。先释放旧 capture，再把 mask 归零；
            // 后续 Web 上报的 panel interactiveRect 也必须在 UpdateHitRects 中被忽略。
            CancelActivePointerGesture();
            ClearInteractiveRects();

            LogManager.Log("[InputShield] EnterTelemetryMode source=shared_cursor_hook panel=" + panelRect.Width + "x" + panelRect.Height
                + " anchor=" + anchorScreenRect.Width + "x" + anchorScreenRect.Height);
        }

        public void ExitTelemetryMode()
        {
            bool wasActive = _telemetryActive;
            _telemetryActive = false;

            // Close 的输入不变量必须幂等：即便调用时 telemetry 已结束，也不能让最后一次
            // full-panel interactiveRect 或未配对 capture 留在常驻透明 shield 上吞掉 Flash 点击。
            CancelActivePointerGesture();
            ClearInteractiveRects();

            if (!wasActive) return;

            LogManager.Log("[InputShield] ExitTelemetryMode source=shared_cursor_hook session_total=" + _sessionTotalClicks
                + " clicks_outside_panel=" + _clicksOutsidePanel
                + " filtered_external=" + _filteredExternalClicks);
        }

        /// <summary>
        /// Decide if a click at given screen pt should be counted as clicks_outside_panel.
        /// Pure function for unit tests. internal static so InternalsVisibleTo can reach it.
        /// 返回 1 = clicks_outside_panel; 0 = inside panel (no count); -1 = filtered (external/foreground).
        /// </summary>
        internal static int ClassifyTelemetryClick(Point screenPt, Rectangle panelRect, Rectangle anchorRect,
                                                   bool foregroundIsGuardian)
        {
            if (!foregroundIsGuardian) return -1;
            if (!anchorRect.Contains(screenPt)) return -1;
            if (panelRect.Contains(screenPt)) return 0;
            return 1;
        }

        // Called by the associated WebOverlay hook on the same UI thread.
        // Observation has no consumption result and never forwards input.
        internal void ObserveTelemetryButtonDown(int screenX, int screenY, int message)
        {
            if (!_telemetryActive || IsDisposed || Disposing) return;
            if (message != 0x0201 && message != 0x0204 && message != 0x0207 && message != 0x020B) return;
            bool fgIsGuardian = false;
            try
            {
                IntPtr fg = GetForegroundWindow();
                // WebOverlay is owned top-level, not an IsChild descendant.
                fgIsGuardian = (fg == _telemetryGuardianHwnd)
                    || (fg == _telemetryWebOverlayHwnd && _telemetryWebOverlayHwnd != IntPtr.Zero)
                    || (fg != IntPtr.Zero && IsChild(_telemetryGuardianHwnd, fg));
            }
            catch { }
            int kind = ClassifyTelemetryClick(new Point(screenX, screenY), _telemetryPanelRect, _telemetryAnchorRect, fgIsGuardian);
            _sessionTotalClicks++;
            if (kind == 1) _clicksOutsidePanel++;
            else if (kind == -1) _filteredExternalClicks++;
        }

        #endregion

        #region 命中区域管理

        /// <summary>
        /// 更新交互区域矩形列表。由 WebOverlayForm 在收到 JS hitRects 消息后调用。
        /// 物理像素坐标，已由 WebOverlayForm 通过 OverlayCoordinateContext 转换。
        /// </summary>
        public void UpdateHitRects(List<Rectangle> rects)
        {
            if (!LegacyHitRegionsEnabled)
            {
                // The mode switch already cleared the mask, including any deferred hit regions.
                return;
            }

            // mask 未初始化时暂存，等 OnPositionChanged 填充 _maskW/_maskH 后重新应用
            if (_maskW <= 0 || _maskH <= 0)
            {
                _pendingRawRects = new List<Rectangle>(rects);
                return;
            }

            _hitRects.Clear();
            // Clamp 到位图边界，防止超出导致鼠标永远命中
            foreach (Rectangle r in rects)
            {
                int cx = Math.Max(0, r.X);
                int cy = Math.Max(0, r.Y);
                int cw = Math.Min(r.Width, _maskW - cx);
                int ch = Math.Min(r.Height, _maskH - cy);
                if (cw > 0 && ch > 0)
                    _hitRects.Add(new Rectangle(cx, cy, cw, ch));
            }
            // 检测收起（宽度缩小）→ 进入冷却期
            int newWidth = (_hitRects.Count > 0) ? _hitRects[0].Width : 0;
            if (newWidth < _lastHitWidth && _lastHitWidth > 0)
                _collapseTick = Environment.TickCount;
            _lastHitWidth = newWidth;

            RebuildMask();

            if (_mouseInside && _pressedButtons == 0)
                CleanupIfMouseOutside();
        }

        internal static bool ShouldApplyInteractiveRects(bool telemetryActive)
        {
            return !telemetryActive;
        }

        private void ClearInteractiveRects()
        {
            _pendingRawRects = null;
            _hitRects.Clear();
            _lastHitWidth = 0;
            _collapseTick = 0;
            RebuildMask();
        }

        /// <summary>
        /// 检查鼠标是否仍在命中区域内。移出区域时清理 hover。
        /// </summary>
        private void CleanupIfMouseOutside()
        {
            Point cursor = Cursor.Position;
            int lx = cursor.X - _screenX;
            int ly = cursor.Y - _screenY;

            bool still = false;
            foreach (Rectangle r in _hitRects)
            {
                if (r.Contains(lx, ly)) { still = true; break; }
            }

            if (!still)
            {
                _mouseInside = false;
                // 发送到视口外触发 CSS mouseleave
                DispatchCdpMouseAt("mouseMoved", -1, -1, "none");
            }
        }

        /// <summary>
        /// 重建 alpha 位图：命中区域 α=1，其余 α=0。
        /// </summary>
        private void RebuildMask()
        {
            if (_maskW <= 0 || _maskH <= 0) return;

            if (_maskBitmap == null || _maskBitmap.Width != _maskW || _maskBitmap.Height != _maskH)
            {
                if (_maskBitmap != null) _maskBitmap.Dispose();
                _maskBitmap = new Bitmap(_maskW, _maskH, PixelFormat.Format32bppPArgb);
            }

            using (Graphics g = Graphics.FromImage(_maskBitmap))
            {
                g.Clear(Color.FromArgb(0, 0, 0, 0));

                // 命中区域填充 α=1（肉眼不可见，但命中测试视为实心）
                using (SolidBrush b = new SolidBrush(Color.FromArgb(1, 0, 0, 0)))
                {
                    foreach (Rectangle r in _hitRects)
                    {
                        if (r.Width > 0 && r.Height > 0)
                            g.FillRectangle(b, r);
                    }
                }
            }

            CommitBitmap(_maskBitmap, _screenX, _screenY, 255);
        }

        #endregion

        #region 位置同步

        protected override void OnPositionChanged()
        {
            if (_coordinateContext != null && _coordinateContext.OverlayPhysicalBounds.Width > 0 &&
                _coordinateContext.OverlayPhysicalBounds.Height > 0)
            {
                Rectangle bounds = _coordinateContext.OverlayPhysicalBounds;
                _screenX = bounds.X;
                _screenY = bounds.Y;
                _maskW = Math.Max(1, bounds.Width);
                _maskH = Math.Max(1, bounds.Height);
            }
            else
            {
                float vpX, vpY, vpW, vpH;
                _mapper.CalcViewport(out vpX, out vpY, out vpW, out vpH);

                Point origin;
                if (!GetAnchorScreenOrigin(out origin)) return;

                _screenX = origin.X + (int)vpX;
                _screenY = origin.Y + (int)vpY;
                _maskW = Math.Max(1, (int)vpW);
                _maskH = Math.Max(1, (int)vpH);
            }

            // mask 就绪后，重新应用启动期暂存的 hitRects
            if (_pendingRawRects != null)
            {
                List<Rectangle> pending = _pendingRawRects;
                _pendingRawRects = null;
                UpdateHitRects(pending);
            }

            if (_shown)
                RebuildMask();
        }

        #endregion

        #region 命中测试 + 鼠标事件

        protected override void WndProc(ref Message m)
        {
            if (!LegacyHitRegionsEnabled && m.Msg is (WM_NCHITTEST or WM_MOUSEMOVE or WM_MOUSELEAVE
                or WM_LBUTTONDOWN or WM_LBUTTONUP or WM_RBUTTONDOWN or WM_RBUTTONUP or WM_MOUSEWHEEL))
            {
                m.Result = m.Msg == WM_NCHITTEST ? (IntPtr)HTTRANSPARENT : IntPtr.Zero;
                return;
            }

            switch (m.Msg)
            {
                case WM_NCHITTEST:
                {
                    long lp = m.LParam.ToInt64();
                    int sx = (short)(lp & 0xFFFF);
                    int sy = (short)((lp >> 16) & 0xFFFF);
                    Point pt = new Point(sx - _screenX, sy - _screenY);

                    foreach (Rectangle r in _hitRects)
                    {
                        if (r.Contains(pt))
                        {
                            m.Result = (IntPtr)HTCLIENT;
                            return;
                        }
                    }
                    m.Result = (IntPtr)HTTRANSPARENT;
                    return;
                }

                case WM_MOUSEACTIVATE:
                    m.Result = (IntPtr)MA_NOACTIVATE;
                    return;

                case WM_MOUSEMOVE:
                {
                    if (!_mouseTracking)
                    {
                        TRACKMOUSEEVENT tme = new TRACKMOUSEEVENT();
                        tme.cbSize = Marshal.SizeOf(typeof(TRACKMOUSEEVENT));
                        tme.dwFlags = TME_LEAVE;
                        tme.hwndTrack = this.Handle;
                        tme.dwHoverTime = 0;
                        TrackMouseEvent(ref tme);
                        _mouseTracking = true;
                    }
                    _mouseInside = true;

                    // 收起冷却期内不发 CDP mouseMoved，防止 JS mouseenter → 重新展开
                    long elapsed = Environment.TickCount - _collapseTick;
                    if (_collapseTick > 0 && elapsed >= 0 && elapsed < 800)
                        return;

                    DispatchCdpMouse("mouseMoved", m.LParam, "none");
                    return;
                }

                case WM_MOUSELEAVE:
                {
                    _mouseTracking = false;
                    _mouseInside = false;
                    if (_pressedButtons == 0) DispatchCdpMouseAt("mouseMoved", -1, -1, "none");
                    return;
                }

                case WM_CAPTURECHANGED:
                    if (_pressedButtons != 0 && !Capture) CancelActivePointerGesture();
                    break;

                case WM_LBUTTONDOWN:
                case WM_RBUTTONDOWN:
                    bool left = m.Msg == WM_LBUTTONDOWN;
                    _pressedButtons |= left ? 1 : 2;
                    Capture = true;
                    DispatchCdpMouse("mousePressed", m.LParam, left ? "left" : "right");
                    return;

                case WM_LBUTTONUP:
                case WM_RBUTTONUP:
                    int released = m.Msg == WM_LBUTTONUP ? 1 : 2;
                    if ((_pressedButtons & released) == 0) return;
                    _pressedButtons &= ~released;
                    if (_pressedButtons == 0 && Capture) Capture = false;
                    DispatchCdpMouse("mouseReleased", m.LParam, released == 1 ? "left" : "right");
                    return;

                case WM_MOUSEWHEEL:
                    DispatchCdpMouseWheel(m.WParam, m.LParam);
                    return;
            }

            base.WndProc(ref m);
        }

        /// <summary>滚轮事件注入 CDP。WM_MOUSEWHEEL 的 lParam 是屏幕坐标。</summary>
        private void DispatchCdpMouseWheel(IntPtr wParam, IntPtr lParam)
        {
            if (!LegacyHitRegionsEnabled || _targetWebView == null) return;

            // 64 位安全：用 ToInt64 避免 OverflowException
            long wp = wParam.ToInt64();
            int delta = (short)((wp >> 16) & 0xFFFF);

            long lp = lParam.ToInt64();
            int sx = (short)(lp & 0xFFFF);
            int sy = (short)((lp >> 16) & 0xFFFF);
            Point clientPt = this.PointToClient(new Point(sx, sy));

            Point css = PhysicalPointToCss(clientPt.X, clientPt.Y);

            string json = "{\"type\":\"mouseWheel\""
                + ",\"x\":" + css.X
                + ",\"y\":" + css.Y
                + ",\"deltaX\":0"
                + ",\"deltaY\":" + (-delta)
                + ",\"button\":\"none\"}";

            _cdpQueue.Enqueue(json);
            DrainQueue();
        }

        #endregion

        #region CDP 注入（串行队列）

        // CDP 事件严格串行：前一个 await 完成后才发下一个，防止乱序
        private readonly Queue<string> _cdpQueue = new Queue<string>();
        private bool _cdpBusy;

        /// <summary>从 WM_xxx 的 lParam 提取客户区坐标并注入 CDP。</summary>
        private void DispatchCdpMouse(string type, IntPtr lParam, string button)
        {
            if (!LegacyHitRegionsEnabled || _targetWebView == null) return;

            long lp = lParam.ToInt64();
            int x = (short)(lp & 0xFFFF);
            int y = (short)((lp >> 16) & 0xFFFF);

            DispatchCdpMouseAt(type, x, y, button);
        }

        /// <summary>向 WebView2 注入 CDP 鼠标事件。坐标为物理像素，内部转为 CSS 像素。</summary>
        private void DispatchCdpMouseAt(string type, int physX, int physY, string button)
        {
            if (!LegacyHitRegionsEnabled || _targetWebView == null) return;

            // 物理像素 → CSS 像素（CDP 坐标空间）
            Point css = PhysicalPointToCss(physX, physY);
            if (physX >= 0 && physY >= 0 && _cursorSampleSink != null)
                _cursorSampleSink(physX, physY);

            string clickCount = (type == "mousePressed") ? ",\"clickCount\":1" : "";
            string json = "{\"type\":\"" + type + "\""
                + ",\"x\":" + css.X
                + ",\"y\":" + css.Y
                + ",\"button\":\"" + button + "\""
                + clickCount + "}";

            if (type == "mouseMoved" && _cdpQueue.Count > 0)
            {
                // 队列尾部替换优化（Queue 不支持直接替换尾部，用标记跳过旧的）
                // 简化处理：直接入队，DrainQueue 中连续 mouseMoved 只发最后一个
            }

            _cdpQueue.Enqueue(json);
            DrainQueue();
        }

        private async void DrainQueue()
        {
            if (_cdpBusy || !LegacyHitRegionsEnabled || _targetWebView == null) return;
            _cdpBusy = true;

            try
            {
                while (LegacyHitRegionsEnabled && _targetWebView != null && _cdpQueue.Count > 0)
                {
                    string json = _cdpQueue.Dequeue();

                    // 合并连续 mouseMoved：如果队列前面还有 mouseMoved，跳过当前这条
                    if (json.Contains("\"mouseMoved\"") && _cdpQueue.Count > 0)
                    {
                        // peek 下一条，如果也是 mouseMoved 就跳过当前
                        string next = _cdpQueue.Peek();
                        if (next.Contains("\"mouseMoved\""))
                            continue;
                    }

                    await _targetWebView.CallDevToolsProtocolMethodAsync(
                        "Input.dispatchMouseEvent", json);
                }
            }
            catch
            {
                // WebView2 可能已 disposed，清空队列
                _cdpQueue.Clear();
            }
            finally
            {
                _cdpBusy = false;
            }
        }

        private Point PhysicalPointToCss(int physicalX, int physicalY)
        {
            if (_coordinateContext != null)
                return _coordinateContext.PhysicalPointToCss(physicalX, physicalY);

            if (physicalX < 0 || physicalY < 0)
                return new Point(physicalX, physicalY);

            return new Point(
                (int)Math.Round(physicalX / _fallbackZoom),
                (int)Math.Round(physicalY / _fallbackZoom));
        }

        #endregion

        #region 生命周期 + 自愈 watchdog

        /// <summary>
        /// 激活 shield 层。在 WebOverlayForm.SetReady() 之后调用。
        /// </summary>
        public void SetReady()
        {
            OnPositionChanged();
            ShowOverlay();
        }

        /// <summary>
        /// Owner 失焦/最小化时强制重置所有输入状态。
        /// OverlayBase 会在 Deactivate 时调用 HideOverlay，这里额外清理 CDP 状态。
        /// </summary>
        protected override void OnOwnerBecameHidden()
        {
            CancelActivePointerGesture();
        }

        /// <summary>Cancel the shield's capture and queued CDP events. Only a real up can be dispatched.</summary>
        internal void CancelActivePointerGesture()
        {
            bool clearHover = _mouseInside || _pressedButtons != 0;
            _pressedButtons = 0;
            _mouseTracking = false;
            _mouseInside = false;
            _cdpQueue.Clear();
            if (IsHandleCreated && Capture) Capture = false;
            if (clearHover && !IsDisposed && !Disposing)
                DispatchCdpMouseAt("mouseMoved", -1, -1, "none");
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                _telemetryActive = false;
                _targetWebView = null;
                CancelActivePointerGesture();
                if (_maskBitmap != null)
                {
                    _maskBitmap.Dispose();
                    _maskBitmap = null;
                }
            }
            base.Dispose(disposing);
        }

        #endregion
    }
}
