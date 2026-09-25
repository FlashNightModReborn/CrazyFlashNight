#nullable enable
using System;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using CF7Launcher.Guardian.WorldCompositor;
using Microsoft.Web.WebView2.Core;
using Newtonsoft.Json.Linq;

// 真实游戏 help 面板的局部 composition 端点（只读试点）。
// 复用 WorldCompositor.CompositionSceneHost 与
// CoreWebView2CompositionController；不使用 WinForms WebView2、CDP 或私有反射。
// 本类不是 C1 虚拟世界宿主，不持有游戏存档/业务通道。
namespace CF7Launcher.Guardian
{
    internal sealed class CompositionHelpSurface : Form
    {
        internal const string HostName = "cf7-help.local";
        internal const string PageUrl = "https://cf7-help.local/composition-help.html";
        private const int WmMouseActivate = 0x0021;
        private const int WmMouseMove = 0x0200;
        private const int WmLButtonDown = 0x0201;
        private const int WmLButtonUp = 0x0202;
        private const int WmLButtonDoubleClick = 0x0203;
        private const int WmRButtonDown = 0x0204;
        private const int WmRButtonUp = 0x0205;
        private const int WmRButtonDoubleClick = 0x0206;
        private const int WmMouseWheel = 0x020A;
        private const int WmMouseLeave = 0x02A3;
        private const int WmCaptureChanged = 0x0215;
        private const int MaActivateAndEat = 2;
        private const int VkEscape = 0x1B;

        private readonly Form _owner;
        private readonly string _webRoot;
        private readonly string _profileRoot;
        private CoreWebView2Environment? _environment;
        private CompositionSceneHost? _scene;
        private CoreWebView2CompositionController? _web;
        private object? _webVisual;
        private TaskCompletionSource<bool>? _readyTcs;
        private int _prepareVersion;
        private bool _ready, _active, _disposed, _closePending, _trackingLeave, _capturedButton;
        private Rectangle _committed = Rectangle.Empty;
        private string _panelInstance = "";
        private string _closeReason = "page_close";
        private int _pressedButtons;
        private readonly System.Windows.Forms.Timer _closeTimer = new() { Interval = 25 };

        internal event Action<string>? CloseRequested;

        internal CompositionHelpSurface(Form owner, string webRoot, string profileRoot)
        {
            _owner = owner ?? throw new ArgumentNullException(nameof(owner));
            _webRoot = webRoot ?? throw new ArgumentNullException(nameof(webRoot));
            _profileRoot = profileRoot ?? throw new ArgumentNullException(nameof(profileRoot));
            FormBorderStyle = FormBorderStyle.None;
            ShowInTaskbar = false;
            StartPosition = FormStartPosition.Manual;
            BackColor = Color.Black;
            ClientSizeChanged += (_, _) => SyncViewport();
            VisibleChanged += (_, _) => SyncViewport();
            _closeTimer.Tick += (_, _) => TryDeliverClose();
        }

        protected override bool ShowWithoutActivation => true;

        internal bool Ready { get { return _ready && !_disposed; } }
        internal bool Active { get { return _active && Ready; } }
        internal int SessionGeneration { get; private set; }

        private bool Stale(int version) => _disposed || version != _prepareVersion || IsDisposed;

        // 必须在 UI 线程调用。失败记录日志并抛出；Retire/Dispose 后晚到的
        // await 完成不得复活旧 controller。
        internal async Task PrepareAsync()
        {
            if (_disposed) throw new ObjectDisposedException(nameof(CompositionHelpSurface));
            if (InvokeRequired) throw new InvalidOperationException("PrepareAsync must run on the surface UI thread.");
            int version = unchecked(++_prepareVersion);
            _ready = false; _active = false; _closePending = false;
            TearDownEndpoint();
            try {
                var environment = await CoreWebView2Environment.CreateAsync(null, _profileRoot);
                if (Stale(version)) { throw new ObjectDisposedException(nameof(CompositionHelpSurface)); }
                _environment = environment;
                _scene = CompositionSceneHost.Create(Handle);
                var controller = await environment.CreateCoreWebView2CompositionControllerAsync(Handle);
                if (Stale(version)) { controller.Close(); throw new ObjectDisposedException(nameof(CompositionHelpSurface)); }
                _web = controller;
                _web.IsVisible = false; // Hidden preheat never grants presentation.
                _web.Bounds = DeviceClientRectangle();
                _web.DefaultBackgroundColor = Color.Transparent;
                _web.ShouldDetectMonitorScaleChanges = false;
                _web.RasterizationScale = 1;
                _web.BoundsMode = CoreWebView2BoundsMode.UseRawPixels;
                var core = _web.CoreWebView2;
                core.Settings.AreDevToolsEnabled = false;
                core.Settings.AreDefaultContextMenusEnabled = false;
                core.Settings.IsZoomControlEnabled = false;
                core.Settings.AreBrowserAcceleratorKeysEnabled = false;
                IntPtr visual = _scene.AcquireVisual(2);
                try { _webVisual = Marshal.GetObjectForIUnknown(visual); _web.RootVisualTarget = _webVisual; }
                finally { Marshal.Release(visual); }
                core.SetVirtualHostNameToFolderMapping(HostName, _webRoot, CoreWebView2HostResourceAccessKind.DenyCors);
                core.NavigationStarting += OnNavigationStarting;
                core.NewWindowRequested += (_, args) => args.Handled = true;
                core.DownloadStarting += (_, args) => args.Cancel = true;
                core.AddWebResourceRequestedFilter("*", CoreWebView2WebResourceContext.All);
                core.WebResourceRequested += OnWebResourceRequested;
                core.ProcessFailed += OnWebProcessFailed;
                core.WebMessageReceived += OnWebMessage;
                _web.AcceleratorKeyPressed += OnAcceleratorKey;
                _readyTcs = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
                core.Navigate(PageUrl);
                var ready = _readyTcs.Task;
                var timeout = Task.Delay(15000);
                if (await Task.WhenAny(ready, timeout) != ready)
                    throw new TimeoutException("composition_help_ready not received within 15s");
                await ready;
                if (Stale(version)) throw new ObjectDisposedException(nameof(CompositionHelpSurface));
                _ready = true;
                SyncViewport();
                LogManager.Log("[HelpSurface] prepare ready gen=" + SessionGeneration);
            } catch (Exception error) {
                if (!Stale(version)) LogManager.Log("[HelpSurface] prepare failed: " + error);
                throw;
            }
        }

        internal bool ResumePanel(Rectangle rect)
        {
            if (!Ready || _web == null) return false;
            SessionGeneration++;
            Owner = _owner;
            Bounds = rect;
            _active = true;
            _closePending = false;
            if (!Visible) Show();
            SyncViewport();
            // 仅当前台已属本进程窗口（游戏/owner 同进程）才允许激活；
            // 外部前台窗口时不抢焦点。
            if (ForegroundIsSameProcess()) {
                Activate();
                _web.MoveFocus(CoreWebView2MoveFocusReason.Programmatic);
            }
            LogManager.Log("[HelpSurface] resume gen=" + SessionGeneration + " rect=" + rect);
            return true;
        }

        internal bool TryPost(string json)
        {
            if (!Active || _web == null) return false;
            var message = JObject.Parse(json);
            string? type = message.Value<string>("type");
            if (type == "panel_cmd")
            {
                if (message.Value<string>("panel") != "help") return false;
                if (message.Value<string>("cmd") == "open")
                {
                    string? instance = message["initData"]?.Value<string>("panelInstanceId");
                    if (string.IsNullOrEmpty(instance)) return false;
                    _panelInstance = instance;
                }
            }
            else if (type != "panel_viewport_set" && type != "panel_esc") return false;
            _web.CoreWebView2.PostWebMessageAsJson(json);
            return true;
        }

        internal void RepositionPanel(Rectangle rect, bool ensureVisible)
        {
            if (_disposed) return;
            Bounds = rect;
            if (ensureVisible && !Visible) Show();
            SyncViewport();
        }

        internal bool CommitGeometry(Rectangle rect, int generation)
        {
            if (!Active || generation != SessionGeneration || _scene == null) return false;
            Bounds = rect;
            _committed = rect;
            SyncViewport();
            return true;
        }

        internal void ClearGeometry(string reason)
        {
            _committed = Rectangle.Empty;
            if (!_disposed && _scene != null) SyncViewport();
            LogManager.Log("[HelpSurface] geometry cleared: " + reason);
        }

        internal bool Replay(Rectangle rect, int generation, string reason)
        {
            if (!Active || generation != SessionGeneration || _scene == null || _committed != rect) return false;
            Bounds = _committed;
            if (!Visible) Show();
            SyncViewport();
            LogManager.Log("[HelpSurface] geometry replayed: " + reason);
            return true;
        }

        internal void Retire()
        {
            if (_disposed) return;
            unchecked { _prepareVersion++; }
            _ready = false; _active = false; _closePending = false; _committed = Rectangle.Empty;
            _closeTimer.Stop(); _panelInstance = ""; _pressedButtons = 0;
            _capturedButton = false; Capture = false;
            TearDownEndpoint();
            if (Visible) Hide();
            LogManager.Log("[HelpSurface] retired gen=" + SessionGeneration);
        }

        // 当前前台是本窗（含 WebView 内部子窗口）或 owner 及其同进程窗口；
        // 不按进程名猜测。
        internal bool CanRestoreGameFocus
        {
            get {
                IntPtr foreground = GetForegroundWindow();
                if (foreground == IntPtr.Zero) return false;
                if (foreground == Handle || GetAncestor(foreground, 2) == Handle) return true;
                if (_owner != null && !_owner.IsDisposed
                    && (foreground == _owner.Handle || GetAncestor(foreground, 2) == _owner.Handle)) return true;
                GetWindowThreadProcessId(foreground, out uint pid);
                return pid == Environment.ProcessId;
            }
        }

        private bool ForegroundIsSameProcess()
        {
            IntPtr foreground = GetForegroundWindow();
            if (foreground == IntPtr.Zero) return false;
            GetWindowThreadProcessId(foreground, out uint pid);
            return pid == Environment.ProcessId;
        }

        private Rectangle DeviceClientRectangle()
        {
            // PerMonitorV2 下 ClientSize 即设备像素。
            return new Rectangle(0, 0, Math.Max(1, ClientSize.Width), Math.Max(1, ClientSize.Height));
        }

        private void SyncViewport()
        {
            if (_disposed || IsDisposed) return;
            var bounds = DeviceClientRectangle();
            if (_web != null && _web.Bounds != bounds) _web.Bounds = bounds;
            // Showing a WinForms host does not show a composition controller that
            // was created while hidden. Pair browser visibility with the live surface.
            if (_web != null)
            {
                bool visible = Active && Visible && _owner.Visible
                    && _owner.WindowState != FormWindowState.Minimized;
                if (_web.IsVisible != visible)
                {
                    _web.IsVisible = visible;
                    LogManager.Log("[HelpSurface] controller visible=" + visible
                        + " gen=" + SessionGeneration);
                }
            }
            if (Active && _web != null)
                _web.CoreWebView2.PostWebMessageAsJson(new JObject {
                    ["type"] = "panel_viewport_set", ["w"] = bounds.Width, ["h"] = bounds.Height
                }.ToString(Newtonsoft.Json.Formatting.None));
            if (_scene != null) {
                _scene.Presentation(false, false, bounds.Width, bounds.Height);
                _scene.Commit();
            }
        }

        private void OnNavigationStarting(object? sender, CoreWebView2NavigationStartingEventArgs args)
        {
            if (args.Uri != PageUrl) args.Cancel = true;
        }

        private void OnWebResourceRequested(object? sender, CoreWebView2WebResourceRequestedEventArgs args)
        {
            // 仅放行同 origin 文件；不读游戏 save，不响应外链/下载。
            if (_environment == null
                || !args.Request.Uri.StartsWith("https://" + HostName + "/", StringComparison.Ordinal)) {
                args.Response = _environment?.CreateWebResourceResponse(
                    Stream.Null, 403, "help origin only", "Content-Type: text/plain");
                return;
            }
        }

        private void OnWebMessage(object? sender, CoreWebView2WebMessageReceivedEventArgs args)
        {
            if (_disposed || _web == null || !ReferenceEquals(sender, _web.CoreWebView2)
                || args.Source != PageUrl) return;
            JObject message;
            try { message = JObject.Parse(args.WebMessageAsJson); }
            catch { return; }
            string? type = message.Value<string>("type");
            if (type == "composition_help_ready") {
                _readyTcs?.TrySetResult(true);
                return;
            }
            // 页面关闭请求：等物理鼠标键与 ESC 全部释放后才上抛 CloseRequested，
            // 避免在按下手势中途触发关闭重入。
            if (type == "panel" && message.Value<string>("cmd") == "close"
                && message.Value<string>("panel") == "help"
                && Active && _panelInstance.Length > 0
                && message.Value<string>("panelInstanceId") == _panelInstance) {
                RequestClose("page_close");
            }
        }

        private void OnWebProcessFailed(object? sender, CoreWebView2ProcessFailedEventArgs args)
        {
            if (_web == null || !ReferenceEquals(sender, _web.CoreWebView2)) return;
            LogManager.Log("[HelpSurface] web process failed: " + args.ProcessFailedKind);
            RequestClose("process_failed:" + args.ProcessFailedKind);
        }

        private void OnAcceleratorKey(object? sender, CoreWebView2AcceleratorKeyPressedEventArgs args)
        {
            if (args.VirtualKey == VkEscape)
            {
                args.Handled = true;
                if (args.KeyEventKind == CoreWebView2KeyEventKind.KeyUp)
                    RequestClose("esc");
            }
        }

        protected override void OnActivated(EventArgs e)
        {
            base.OnActivated(e);
            if (Active && _web != null)
                _web.MoveFocus(CoreWebView2MoveFocusReason.Programmatic);
        }

        protected override void OnDeactivate(EventArgs e)
        {
            base.OnDeactivate(e);
            // 不用同步 close：Deactivate 期间焦点归属仍在迁移，直接关闭会重入
            // 激活路径。延迟到消息循环空闲再判定；WebView 内部子窗口取得前台
            // （其进程不同但 HWND 是本窗后代）不算离开。
            if (_disposed || IsDisposed || !IsHandleCreated) return;
            BeginInvoke((Action)(() => {
                if (_disposed || !_active || IsDisposed) return;
                if (!ForegroundIsOurs()) RequestClose("deactivated");
            }));
        }

        private bool ForegroundIsOurs()
        {
            IntPtr foreground = GetForegroundWindow();
            if (foreground == IntPtr.Zero) return false;
            if (foreground == Handle || GetAncestor(foreground, 2) == Handle) return true;
            if (_owner != null && !_owner.IsDisposed
                && (foreground == _owner.Handle || GetAncestor(foreground, 2) == _owner.Handle)) return true;
            GetWindowThreadProcessId(foreground, out uint pid);
            return pid == Environment.ProcessId;
        }

        private void RequestClose(string reason)
        {
            if (_disposed || !_active || _closePending) return;
            _closePending = true;
            _closeReason = reason;
            _closeTimer.Start();
            // Never dispose a controller from inside its synchronous COM callback.
            BeginInvoke((Action)TryDeliverClose);
        }

        private void TryDeliverClose()
        {
            if (!_closePending || _disposed) return;
            bool held = (GetAsyncKeyState(0x01) | GetAsyncKeyState(0x02)
                | GetAsyncKeyState(0x04) | GetAsyncKeyState(VkEscape)) < 0;
            if (held) return;
            _closeTimer.Stop();
            _closePending = false;
            CloseRequested?.Invoke(_closeReason);
        }

        protected override void WndProc(ref Message m)
        {
            bool input = m.Msg is WmMouseMove or WmMouseLeave or WmLButtonDown
                or WmLButtonUp or WmRButtonDown or WmRButtonUp or WmMouseWheel
                or WmLButtonDoubleClick or WmRButtonDoubleClick;
            if (input && (!Active || _committed.IsEmpty || _closePending))
            { base.WndProc(ref m); return; }
            switch (m.Msg) {
                case WmMouseActivate:
                    // 外部首击只激活并吞掉；不向页面伪造 click/up。
                    if (GetAncestor(GetForegroundWindow(), 2) != Handle) {
                        m.Result = new IntPtr(MaActivateAndEat);
                        return;
                    }
                    break;
                case WmMouseMove:
                    if (_web != null) _web.SendMouseInput(CoreWebView2MouseEventKind.Move, MouseKeys(m.WParam), 0, MousePoint(m.LParam));
                    EnsureLeaveTracking();
                    break;
                case WmMouseLeave:
                    _trackingLeave = false;
                    if (_web != null) _web.SendMouseInput(CoreWebView2MouseEventKind.Leave, CoreWebView2MouseEventVirtualKeys.None, 0, Point.Empty);
                    break;
                case WmLButtonDown:
                case WmRButtonDown:
                case WmLButtonDoubleClick:
                case WmRButtonDoubleClick:
                    bool left = m.Msg is WmLButtonDown or WmLButtonDoubleClick;
                    _pressedButtons |= left ? 1 : 2;
                    _capturedButton = true;
                    Capture = true;
                    if (_web != null) _web.SendMouseInput(
                        left ? CoreWebView2MouseEventKind.LeftButtonDown : CoreWebView2MouseEventKind.RightButtonDown,
                        MouseKeys(m.WParam), 0, MousePoint(m.LParam));
                    break;
                case WmLButtonUp:
                case WmRButtonUp:
                    int released = m.Msg == WmLButtonUp ? 1 : 2;
                    if ((_pressedButtons & released) == 0) break;
                    _pressedButtons &= ~released;
                    if (_web != null) _web.SendMouseInput(
                        m.Msg == WmLButtonUp ? CoreWebView2MouseEventKind.LeftButtonUp : CoreWebView2MouseEventKind.RightButtonUp,
                        MouseKeys(m.WParam), 0, MousePoint(m.LParam));
                    _capturedButton = _pressedButtons != 0;
                    if (!_capturedButton) Capture = false;
                    if (_closePending) BeginInvoke((Action)TryDeliverClose);
                    break;
                case WmMouseWheel:
                    if (_web != null) _web.SendMouseInput(CoreWebView2MouseEventKind.Wheel,
                        MouseKeys(m.WParam), WheelDelta(m.WParam), PointToClient(MousePosition));
                    break;
                case WmCaptureChanged:
                    if (_capturedButton && !Capture) {
                        // 捕获被外部夺走：不合成 up，直接请求关闭。
                        _capturedButton = false;
                        RequestClose("capture_lost");
                    }
                    break;
            }
            // Composition owns these messages. Do not also dispatch WinForms mouse
            // focus/parent-wheel handling after delivery to the Web endpoint.
            if (input) { m.Result = IntPtr.Zero; return; }
            base.WndProc(ref m);
        }

        private void EnsureLeaveTracking()
        {
            if (_trackingLeave) return;
            var track = new TRACKMOUSEEVENT {
                Size = (uint)Marshal.SizeOf<TRACKMOUSEEVENT>(),
                Flags = 0x00000002, // TME_LEAVE
                Track = Handle
            };
            _trackingLeave = TrackMouseEvent(ref track);
        }

        private static Point MousePoint(IntPtr lParam)
        {
            int value = lParam.ToInt32();
            return new Point((short)(value & 0xFFFF), (short)((value >> 16) & 0xFFFF));
        }

        private static uint WheelDelta(IntPtr wParam) => unchecked((uint)(int)(short)((wParam.ToInt64() >> 16) & 0xFFFF));

        private static CoreWebView2MouseEventVirtualKeys MouseKeys(IntPtr wParam)
        {
            int mk = (int)(wParam.ToInt64() & 0xFFFF);
            var keys = CoreWebView2MouseEventVirtualKeys.None;
            if ((mk & 0x01) != 0) keys |= CoreWebView2MouseEventVirtualKeys.LeftButton;
            if ((mk & 0x02) != 0) keys |= CoreWebView2MouseEventVirtualKeys.RightButton;
            if ((mk & 0x04) != 0) keys |= CoreWebView2MouseEventVirtualKeys.Shift;
            if ((mk & 0x08) != 0) keys |= CoreWebView2MouseEventVirtualKeys.Control;
            if ((mk & 0x10) != 0) keys |= CoreWebView2MouseEventVirtualKeys.MiddleButton;
            return keys;
        }

        private void TearDownEndpoint()
        {
            if (_web != null) {
                var core = _web.CoreWebView2;
                core.NavigationStarting -= OnNavigationStarting;
                core.WebResourceRequested -= OnWebResourceRequested;
                core.ProcessFailed -= OnWebProcessFailed;
                core.WebMessageReceived -= OnWebMessage;
                _web.AcceleratorKeyPressed -= OnAcceleratorKey;
                _web.RootVisualTarget = null;
                _web.Close();
                _web = null;
            }
            if (_webVisual != null && Marshal.IsComObject(_webVisual)) Marshal.ReleaseComObject(_webVisual);
            _webVisual = null;
            _scene?.Dispose();
            _scene = null;
            _environment = null;
            _readyTcs?.TrySetCanceled();
            _readyTcs = null;
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing && !_disposed) {
                _disposed = true;
                _closeTimer.Dispose();
                unchecked { _prepareVersion++; }
                // Dispose 必须落在 UI 线程；跨线程且句柄已建时同步封送。
                // 句柄未建说明从未 Prepare，无线程关联资源可清。
                if (IsHandleCreated && InvokeRequired)
                    Invoke((Action)TearDownEndpoint);
                else if (!InvokeRequired)
                    TearDownEndpoint();
            }
            base.Dispose(disposing);
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct TRACKMOUSEEVENT
        {
            public uint Size;
            public uint Flags;
            public IntPtr Track;
            public uint HoverTime;
        }

        [DllImport("user32.dll")] private static extern bool TrackMouseEvent(ref TRACKMOUSEEVENT value);
        [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] private static extern IntPtr GetAncestor(IntPtr hwnd, uint flags);
        [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
        [DllImport("user32.dll")] private static extern short GetAsyncKeyState(int key);
    }
}
