using System;
using System.Collections.Generic;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;
using CF7Launcher.Bus;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Guardian
{
    /// <summary>
    /// WebView2 透明覆盖层窗口。
    /// 作为独立顶层窗口悬浮于 Flash HWND 之上，承载 HTML/CSS/JS 渲染的 UI。
    ///
    /// 透明度架构：
    /// - Form.TransparencyKey + WS_EX_LAYERED 实现像素级透明
    /// - TransparencyKey 颜色像素：视觉透明 + 点击穿透（无需轮询切换）
    /// - 非 TransparencyKey 像素（notch/toast）：可见 + 可点击
    /// </summary>
    public class WebOverlayForm : Form, IToastSink, INotchSink, IDisposable
    {
        #region Win32

        [DllImport("user32.dll")]
        private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

        [DllImport("user32.dll")]
        private static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter,
            int X, int Y, int cx, int cy, uint uFlags);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern IntPtr SetWindowsHookEx(int idHook, LowLevelMouseProc lpfn, IntPtr hMod, uint dwThreadId);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool UnhookWindowsHookEx(IntPtr hhk);

        [DllImport("user32.dll")]
        private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

        [DllImport("kernel32.dll", CharSet = CharSet.Auto)]
        private static extern IntPtr GetModuleHandle(string lpModuleName);

        private delegate IntPtr LowLevelMouseProc(int nCode, IntPtr wParam, IntPtr lParam);

        [StructLayout(LayoutKind.Sequential)]
        private struct POINT
        {
            public int X;
            public int Y;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct MSLLHOOKSTRUCT
        {
            public POINT pt;
            public uint mouseData;
            public uint flags;
            public uint time;
            public IntPtr dwExtraInfo;
        }

        private const int SW_SHOWNOACTIVATE = 4;
        private static readonly IntPtr HWND_TOP = new IntPtr(0);
        private const uint SWP_NOMOVE = 0x0002;
        private const uint SWP_NOSIZE = 0x0001;
        private const uint SWP_NOACTIVATE = 0x0010;

        private const int WS_EX_TOOLWINDOW = 0x00000080;
        private const int WS_EX_NOACTIVATE = 0x08000000;
        private const int WS_EX_TRANSPARENT = 0x00000020;
        private const int WM_DPICHANGED = 0x02E0;
        private const int WH_MOUSE_LL = 14;
        private const int HC_ACTION = 0;
        private const int WM_MOUSEMOVE = 0x0200;
        private const int WM_LBUTTONDOWN = 0x0201;
        private const int WM_LBUTTONUP = 0x0202;
        private const int WM_RBUTTONDOWN = 0x0204;
        private const int WM_RBUTTONUP = 0x0205;
        private const int WM_MBUTTONDOWN = 0x0207;
        private const int WM_MBUTTONUP = 0x0208;
        private const int WM_MOUSEWHEEL = 0x020A;
        private const int WM_XBUTTONDOWN = 0x020B;
        private const int WM_XBUTTONUP = 0x020C;

        #endregion

        /// <summary>
        /// TransparencyKey 颜色。选择极暗色 (1,1,1)：
        /// - 与 HTML 暗色背景 rgba(24,24,26) 反差小，抗锯齿边缘几乎无色差
        /// - 几乎不可能与实际内容颜色冲突
        /// </summary>
        private static readonly Color TRANSPARENT_COLOR = Color.FromArgb(1, 1, 1);

        private readonly Form _owner;
        private readonly Control _anchor;
        private readonly FlashCoordinateMapper _mapper;
        private WebView2 _webView;
        private bool _webReady;
        private bool _shown;
        private bool _disposed;
        private bool _devMode;
        private readonly bool _lowEffectsMode;
        private readonly bool _disableCssAnimations;
        private readonly bool _disableVisualizers;
        private readonly bool _webView2DisableGpu;
        private readonly string _webView2AdditionalArgs;

        // GDI+ fallback：WebView2 未就绪或初始化失败时，消息转发到 GDI+ overlay
        private IToastSink _toastFallback;
        private INotchSink _notchFallback;
        private bool _webFailed; // 初始化永久失败，所有后续消息走 fallback

        // IToastSink: 早期消息缓冲（WebView2 初始化前）
        private readonly List<string> _toastEarlyBuffer = new List<string>();
        private bool _toastReady;

        // UI 数据早期缓冲：WebView2 就绪前收到的状态数据，就绪后 flush
        private readonly List<string> _uiDataEarlyBuffer = new List<string>();
        // UI 数据最新值快照：按 type 去重，热重载后恢复完整状态
        private readonly Dictionary<string, string> _uiDataSnapshot = new Dictionary<string, string>();

        // InputShieldForm 引用（CDP 输入注入 + hitRects 转发）
        private InputShieldForm _inputShield;
        private CursorOverlayForm _cursorOverlay;

        // 面板系统
        private ShopTask _shopTask;
        private MapTask _mapTask;
        private GomokuTask _gomokuTask;
        private Action<bool> _onPanelStateChanged;
        private string _activePanel;  // null = 无面板, "kshop"/"help"/...
        private bool _pauseNeedsRestore;

        // 光照等级（静态 24h 数组，初始化后一次性推送给 JS）
        private int[] _lightLevels;

        // INotchSink: FPS 推送 + 按钮委托
        private FpsRingBuffer _fpsBuffer;
        private System.Windows.Forms.Timer _fpsTimer;
        private Action _onToggleFullscreen;
        private Action _onToggleLog;
        private Action _onForceExit;
        private Action<Keys> _onSendKey;

        // 游戏命令通道
        private XmlSocketServer _socketServer;

        // BGM 音频可视化轮询
        private System.Windows.Forms.Timer _audioTimer;
        private System.Windows.Forms.Timer _cursorTimer;
        private System.Windows.Forms.Timer _positionSettleTimer;
        private System.Windows.Forms.Timer _positionLongSettleTimer;
        private bool _syncPositionDeferredPending;
        private int _lastViewportWidth;
        private int _lastViewportHeight;
        private double _lastViewportZoom = -1.0;
        private string _pendingSyncReason = "unspecified";
        private string _cursorState = "normal";
        private bool _cursorDragging;
        private string _webCursorState = "normal";
        private bool _webCursorActive;
        private bool _cursorLastVisible;
        private bool _systemCursorHidden;
        private int _cursorLastX = Int32.MinValue;
        private int _cursorLastY = Int32.MinValue;
        private int _cursorLastScreenX = Int32.MinValue;
        private int _cursorLastScreenY = Int32.MinValue;
        private long _lastCursorDiagTick;
        private bool _cursorDiagForce;
        private string _cursorDiagReason = "init";
        private bool _nativeCursorMissingLogged;
        private IntPtr _cursorHook = IntPtr.Zero;
        private LowLevelMouseProc _cursorHookProc;
        private bool _cursorHookPostPending;
        private int _cursorHookPendingX;
        private int _cursorHookPendingY;
        private int _cursorHookLastX = Int32.MinValue;
        private int _cursorHookLastY = Int32.MinValue;
        private long _lastCursorHookPostTick;
        private string _bgmTitle = ""; // 当前曲目标题（由 UiData bgm: 设置）
        private bool _wasPlaying;       // 上一 tick 的 playing 状态（trackEnd 检测）
        private bool _manualStop;       // 手动 stop 标记（防 trackEnd 误判）
        private bool _bgmPaused;        // 暂停标记（暂停期间不触发 trackEnd）

        // 音乐目录
        private CF7Launcher.Audio.MusicCatalog _musicCatalog;

        // Web 资源热重载：监听 webDir 文件变化，去抖后自动 Reload
        private FileSystemWatcher _webWatcher;
        private System.Threading.Timer _reloadDebounce;
        private System.Threading.Timer _reloadTimeout;

        private readonly OverlayCoordinateContext _coordinateContext = new OverlayCoordinateContext();
        private bool _missingMetricsWarned;
        private bool _dpiResolveWarned;
        private bool _interactiveRectShapeWarned;
        private long _lastHitRectLogTick;
        private long _lastOverlayContextLogTick;
        private int _lastLoggedDpiX = -1;
        private int _lastLoggedDpiY = -1;
        private IntPtr _lastLoggedMonitor = IntPtr.Zero;
        private double _lastLoggedScaleX = -1.0;
        private double _lastLoggedScaleY = -1.0;

        public WebOverlayForm(Form owner, Control anchor, string webDir,
            bool lowEffectsMode, bool disableCssAnimations, bool disableVisualizers,
            bool webView2DisableGpu, string webView2AdditionalArgs)
        {
            _owner = owner;
            _anchor = anchor;
            _mapper = new FlashCoordinateMapper(anchor, 1024f, 576f);
            _webReady = false;
            _shown = false;
            _lowEffectsMode = lowEffectsMode;
            _disableCssAnimations = disableCssAnimations || lowEffectsMode;
            _disableVisualizers = disableVisualizers || lowEffectsMode;
            _webView2DisableGpu = webView2DisableGpu;
            _webView2AdditionalArgs = webView2AdditionalArgs ?? "";

            this.FormBorderStyle = FormBorderStyle.None;
            this.ShowInTaskbar = false;
            this.StartPosition = FormStartPosition.Manual;
            this.AutoScaleMode = AutoScaleMode.None;

            // 像素级透明：BackColor = TransparencyKey → 匹配像素视觉透明 + 点击穿透
            this.BackColor = TRANSPARENT_COLOR;
            this.TransparencyKey = TRANSPARENT_COLOR;

            this.Owner = owner;

            CreateHandle();

            // WebView2 控件
            _webView = new WebView2();
            _webView.Dock = DockStyle.Fill;
            this.Controls.Add(_webView);

            // Owner 跟随：Move/Resize → 同步位置
            owner.Move += delegate { ScheduleSyncPosition("owner_move"); };
            owner.Resize += delegate
            {
                ScheduleSyncPosition("owner_resize");
                // 从最小化恢复时重新显示（Win32 owned 窗口最小化时自动隐藏，
                // 但 ShowWindow(SW_SHOWNOACTIVATE) 创建的窗口可能不自动恢复）
                if (owner.WindowState != FormWindowState.Minimized && _shown && _webReady)
                {
                    ShowWindow(this.Handle, SW_SHOWNOACTIVATE);
                }
            };
            anchor.Resize += delegate { ScheduleSyncPosition("anchor_resize"); };

            // 异步初始化 WebView2
            InitWebView2Async(webDir);
        }

        /// <summary>注入 GDI+ fallback。WebView2 未就绪或失败时消息走这里。</summary>
        public void SetFallback(IToastSink toastFallback, INotchSink notchFallback)
        {
            _toastFallback = toastFallback;
            _notchFallback = notchFallback;
        }

        /// <summary>注入 InputShieldForm 引用。若 WebView2 已就绪，立即补调 SetTargetWebView。</summary>
        public void SetInputShield(InputShieldForm shield)
        {
            _inputShield = shield;
            if (_inputShield != null)
            {
                _inputShield.SetCoordinateContext(_coordinateContext);
                _inputShield.SetZoomFactor(_zoomFactor);
                _inputShield.SetCursorSampleSink(UpdateCursorFromOverlayPoint);
            }
            // 防时序漏洞：如果 WebView2 已经 ready（先于 shield 注入），补调
            if (_webReady && _inputShield != null && _webView != null && _webView.CoreWebView2 != null)
                _inputShield.SetTargetWebView(_webView.CoreWebView2);
        }

        protected override CreateParams CreateParams
        {
            get
            {
                CreateParams cp = base.CreateParams;
                // WS_EX_TOOLWINDOW: 不出现在任务栏和 Alt-Tab 列表
                // WS_EX_NOACTIVATE: 顶层窗口点击时不变前台
                // WS_EX_TRANSPARENT: 永久点击穿透，所有鼠标事件直达 Flash
                //   Phase 0: overlay 纯视觉层，交互走键盘快捷键
                //   Phase 1: 可探索 cursor polling 或 InputHost 方案恢复 notch 鼠标交互
                cp.ExStyle |= WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_TRANSPARENT;
                return cp;
            }
        }

        protected override bool ShowWithoutActivation
        {
            get { return true; }
        }

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == WM_DPICHANGED)
            {
                ScheduleSyncPosition("web_overlay_dpi_changed");
                RequestViewportMetrics("web_overlay_dpi_changed");
                DpiDiagnostics.LogWindow("WebOverlay.WM_DPICHANGED", this.Handle);
            }
            base.WndProc(ref m);
        }

        #region WebView2 初始化

        private async void InitWebView2Async(string webDir)
        {
            try
            {
                // UserData 目录放在 webDir 旁边，避免污染项目目录
                string userDataDir = Path.Combine(
                    Path.GetDirectoryName(webDir), "webview2_overlay_userdata");

                CoreWebView2EnvironmentOptions options = CreateWebView2EnvironmentOptions();
                CoreWebView2Environment env =
                    await CoreWebView2Environment.CreateAsync(null, userDataDir, options);
                await _webView.EnsureCoreWebView2Async(env);

                // 透明背景：WebView2 透明区域显示 Form BackColor (=TransparencyKey) → 视觉穿透
                _webView.DefaultBackgroundColor = Color.Transparent;

                // 虚拟主机映射：https://overlay.local/ → webDir/
                _webView.CoreWebView2.SetVirtualHostNameToFolderMapping(
                    "overlay.local", webDir,
                    CoreWebView2HostResourceAccessKind.Allow);

                // JS→C# 消息
                _webView.CoreWebView2.WebMessageReceived += OnWebMessageReceived;

                // 调试阶段保留开发者工具
                _webView.CoreWebView2.Settings.AreDevToolsEnabled = true;
                _webView.CoreWebView2.Settings.AreDefaultContextMenusEnabled = true;

                // 导航到 overlay 页面
                // _webReady 延迟到 JS "ready" 消息到达时才置真（OnWebMessageReceived）
                _webView.CoreWebView2.Navigate("https://overlay.local/overlay.html");

                // 把 CoreWebView2 传给 InputShieldForm 供 CDP 注入（不依赖 _webReady）
                if (_inputShield != null)
                    _inputShield.SetTargetWebView(_webView.CoreWebView2);

                // 热重载：监听 webDir 文件变化，去抖 500ms 后自动 Reload
                StartWebWatcher(webDir);

                LogManager.Log("[WebOverlay] WebView2 engine ready, waiting for JS ready...");
            }
            catch (Exception ex)
            {
                LogManager.Log("[WebOverlay] WebView2 init failed, falling back to GDI+: " + ex.Message);
                _webFailed = true;
                // 激活 GDI+ fallback 并 flush 早期缓冲
                ActivateFallback();
            }
        }

        /// <summary>监听 webDir 文件变化，去抖后自动 Reload WebView2。</summary>
        private void StartWebWatcher(string webDir)
        {
            _webWatcher = new FileSystemWatcher(webDir);
            _webWatcher.IncludeSubdirectories = true;
            _webWatcher.NotifyFilter = NotifyFilters.LastWrite | NotifyFilters.FileName | NotifyFilters.CreationTime;
            _webWatcher.Filter = "*.*";

            FileSystemEventHandler handler = (s, e) => ScheduleReload();
            RenamedEventHandler renHandler = (s, e) => ScheduleReload();
            _webWatcher.Changed += handler;
            _webWatcher.Created += handler;
            _webWatcher.Deleted += handler;
            _webWatcher.Renamed += renHandler;
            _webWatcher.EnableRaisingEvents = true;

            LogManager.Log("[WebOverlay] Hot-reload watcher started: " + webDir);
        }

        /// <summary>去抖 500ms：多次文件变化只触发一次 Reload。</summary>
        private void ScheduleReload()
        {
            if (_disposed) return;
            var newTimer = new System.Threading.Timer(_ =>
            {
                if (_disposed) return;
                try
                {
                    this.BeginInvoke(new Action(() =>
                    {
                        if (_disposed || _webView == null || _webView.CoreWebView2 == null) return;

                        // 重置就绪状态，使消息进入缓冲/fallback 通道
                        _webReady = false;
                        _webView.CoreWebView2.Reload();
                        LogManager.Log("[WebOverlay] Hot-reload triggered, _webReady reset to false");

                        // 超时保护：10s 后若 JS 未重新发出 ready，降级到 fallback
                        var timeout = new System.Threading.Timer(__ =>
                        {
                            if (_disposed || _webReady) return;
                            try
                            {
                                this.BeginInvoke(new Action(() =>
                                {
                                    if (_disposed || _webReady) return;
                                    LogManager.Log("[WebOverlay] Hot-reload timeout: JS did not send ready within 10s, activating fallback");
                                    _webFailed = true;
                                    ActivateFallback();
                                }));
                            }
                            catch (Exception ex) { LogManager.Log("[WebOverlay] Hot-reload timeout error: " + ex.Message); }
                        }, null, 10000, System.Threading.Timeout.Infinite);
                        var oldTimeout = System.Threading.Interlocked.Exchange(ref _reloadTimeout, timeout);
                        if (oldTimeout != null) oldTimeout.Dispose();
                    }));
                }
                catch (Exception ex) { LogManager.Log("[WebOverlay] Hot-reload invoke error: " + ex.Message); }
            }, null, 500, System.Threading.Timeout.Infinite);
            var old = System.Threading.Interlocked.Exchange(ref _reloadDebounce, newTimer);
            if (old != null) old.Dispose();
        }

        /// <summary>WebView2 初始化失败时，激活 GDI+ fallback 并 flush 早期消息。</summary>
        private void ActivateFallback()
        {
            if (_toastFallback != null)
            {
                // 先 SetReady fallback（如果还没 ready）
                _toastFallback.SetReady();
                // flush 早期缓冲到 GDI+
                foreach (string msg in _toastEarlyBuffer)
                    _toastFallback.AddMessage(msg);
                _toastEarlyBuffer.Clear();
            }
            if (_notchFallback != null)
                _notchFallback.SetReady();
        }

        /// <summary>Web 通道恢复后，挂起 GDI+ fallback（隐藏 + 停 timer），避免双重 UI。</summary>
        private void SuspendFallback()
        {
            var notch = _notchFallback as NotchOverlay;
            if (notch != null) notch.Suspend();
            var toast = _toastFallback as ToastOverlay;
            if (toast != null) toast.Suspend();
        }

        #endregion

        #region Owner 跟随

        private const double FlashDesignHeight = 576.0;

        /// <summary>
        /// 当前 CSS → 物理像素兜底缩放比（viewport 物理高度 / Flash 设计高度 576）。
        /// 注意：这不是直接写入 WebView2 的 ZoomFactor；高 DPI 下 WebView2 还会乘 DPR。
        /// </summary>
        private double _zoomFactor = 1.0;
        private double _webViewZoomFactor = 1.0;

        private void ScheduleSyncPosition()
        {
            ScheduleSyncPosition("unspecified");
        }

        private void ScheduleSyncPosition(string reason)
        {
            if (_disposed) return;

            _pendingSyncReason = reason;
            SyncPosition(reason + ":immediate");

            if (!_syncPositionDeferredPending && this.IsHandleCreated)
            {
                _syncPositionDeferredPending = true;
                try
                {
                    this.BeginInvoke(new Action(delegate()
                    {
                        _syncPositionDeferredPending = false;
                        if (_disposed) return;
                        SyncPosition(reason + ":deferred");
                    }));
                }
                catch
                {
                    _syncPositionDeferredPending = false;
                }
            }

            if (_positionSettleTimer == null)
            {
                _positionSettleTimer = new System.Windows.Forms.Timer();
                _positionSettleTimer.Interval = 120;
                _positionSettleTimer.Tick += delegate
                {
                    if (_positionSettleTimer != null)
                        _positionSettleTimer.Stop();
                    if (_disposed) return;
                    SyncPosition(_pendingSyncReason + ":settled_120ms");
                };
            }

            _positionSettleTimer.Stop();
            _positionSettleTimer.Start();

            if (!IsDpiRelatedReason(reason))
            {
                if (_positionLongSettleTimer != null)
                    _positionLongSettleTimer.Stop();
                return;
            }

            if (_positionLongSettleTimer == null)
            {
                _positionLongSettleTimer = new System.Windows.Forms.Timer();
                _positionLongSettleTimer.Interval = 500;
                _positionLongSettleTimer.Tick += delegate
                {
                    if (_positionLongSettleTimer != null)
                        _positionLongSettleTimer.Stop();
                    if (_disposed) return;
                    SyncPosition(_pendingSyncReason + ":settled_500ms");
                };
            }

            _positionLongSettleTimer.Stop();
            _positionLongSettleTimer.Start();
        }

        public void RequestLayoutSync()
        {
            RequestLayoutSync("external_request");
        }

        public void RequestLayoutSync(string reason)
        {
            if (_disposed) return;
            if (this.InvokeRequired)
            {
                try
                {
                    this.BeginInvoke(new Action(delegate()
                    {
                        RequestLayoutSync(reason);
                    }));
                }
                catch { }
                return;
            }
            ScheduleSyncPosition(reason);
        }

        private void SyncPosition()
        {
            SyncPosition("direct");
        }

        private void SyncPosition(string reason)
        {
            try
            {
                float vpX, vpY, vpW, vpH;
                _mapper.CalcViewport(out vpX, out vpY, out vpW, out vpH);
                Point origin = _anchor.PointToScreen(Point.Empty);

                int x = origin.X + (int)vpX;
                int y = origin.Y + (int)vpY;
                int w = Math.Max(1, (int)vpW);
                int h = Math.Max(1, (int)vpH);

                bool viewportChanged = (w != _lastViewportWidth) ||
                    (h != _lastViewportHeight);
                IntPtr previousMonitor = _coordinateContext.MonitorHandle;
                int previousDpiX = _coordinateContext.WindowDpiX;
                int previousDpiY = _coordinateContext.WindowDpiY;

                SetWindowPos(this.Handle, HWND_TOP, x, y, w, h, SWP_NOACTIVATE);

                // CSS→物理命中比例仍按 Flash 设计高度计算。
                double cssPhysicalScale = CalculateCssPhysicalScale(vpH);
                _zoomFactor = cssPhysicalScale;

                _coordinateContext.UpdateOverlay(new Rectangle(x, y, w, h),
                    vpX, vpY, vpW, vpH, this.Handle, _zoomFactor, reason);

                if (_cursorOverlay != null)
                    _cursorOverlay.SetDpiScale(_coordinateContext.WindowDpiX, _coordinateContext.WindowDpiY);

                // WebView2 视觉 ZoomFactor 需要除以当前 DPI scale，避免 125%/150%
                // 系统缩放下视觉层被 DPR 二次放大。DPI 统一使用 UpdateOverlay 已采样
                // 并带 monitor fallback 的值，避免 handle 初建/跨屏时首帧读到 96。
                double newWebViewZoom = CalculateWebViewZoomFactor(vpH, _coordinateContext.WindowDpiY);
                bool zoomChanged = Math.Abs(newWebViewZoom - _lastViewportZoom) > 0.001;
                _webViewZoomFactor = newWebViewZoom;
                if (!_coordinateContext.LastDpiResolved && !_dpiResolveWarned)
                {
                    _dpiResolveWarned = true;
                    LogManager.Log("[DPI] WebOverlay DPI query failed; using cached/default dpi="
                        + _coordinateContext.WindowDpiY + " for WebView2 zoom normalization");
                }

                bool monitorChanged = previousMonitor != _coordinateContext.MonitorHandle;
                bool dpiChanged = previousDpiX != _coordinateContext.WindowDpiX ||
                    previousDpiY != _coordinateContext.WindowDpiY;

                if (_inputShield != null)
                {
                    _inputShield.SetCoordinateContext(_coordinateContext);
                    _inputShield.SetZoomFactor(_zoomFactor);
                    _inputShield.RequestPositionSync();
                }

                if (_webReady && _webView != null && Math.Abs(newWebViewZoom - _webView.ZoomFactor) > 0.001)
                {
                    _webView.ZoomFactor = _webViewZoomFactor;
                }

                _lastViewportWidth = w;
                _lastViewportHeight = h;
                _lastViewportZoom = newWebViewZoom;

                if (_webReady && (viewportChanged || zoomChanged || monitorChanged || dpiChanged))
                {
                    ExecScript("window.dispatchEvent(new Event('resize'));");
                    RequestViewportMetrics(reason);
                    ExecScript("if(window.Notch&&Notch.reportRect){Notch.reportRect();}");
                    ForceCursorSample("sync:" + reason);
                    if (ShouldLogOverlayContext(dpiChanged || monitorChanged))
                        DpiDiagnostics.LogOverlayContext("WebOverlay.SyncPosition", _coordinateContext);
                }

            }
            catch
            {
                // anchor 可能已 disposed
            }
        }

        private void RequestViewportMetrics(string reason)
        {
            if (!_webReady || _disposed)
                return;
            string safeReason = EscapeForJs(string.IsNullOrEmpty(reason) ? "csharp_request" : reason);
            ExecScript("if(window.OverlayViewportMetrics&&OverlayViewportMetrics.report){"
                + "OverlayViewportMetrics.report('" + safeReason + "');}");
        }

        private void ApplyWebPerfMode(string reason)
        {
            if (!_webReady || _disposed)
                return;

            string lowEffects = _lowEffectsMode ? "true" : "false";
            string noCssAnimations = _disableCssAnimations ? "true" : "false";
            string noVisualizers = _disableVisualizers ? "true" : "false";
            ExecScript("document.documentElement.classList.toggle('perf-low-effects'," + lowEffects + ");"
                + "document.documentElement.classList.toggle('perf-no-css-animations'," + noCssAnimations + ");"
                + "document.documentElement.classList.toggle('perf-no-visualizers'," + noVisualizers + ");"
                + "window.CF7_LOW_EFFECTS=" + lowEffects + ";"
                + "window.CF7_DISABLE_CSS_ANIMATIONS=" + noCssAnimations + ";"
                + "window.CF7_DISABLE_VISUALIZERS=" + noVisualizers + ";");
            if (_lowEffectsMode || _disableCssAnimations || _disableVisualizers)
                LogManager.Log("[WebOverlay] perf mode applied: " + reason
                    + " lowEffects=" + _lowEffectsMode
                    + " noCssAnimations=" + _disableCssAnimations
                    + " noVisualizers=" + _disableVisualizers);
        }

        #endregion

        #region JS ↔ C# 消息

        private void OnWebMessageReceived(object sender,
            CoreWebView2WebMessageReceivedEventArgs args)
        {
            try
            {
                string json = args.WebMessageAsJson;
                JObject parsed = null;
                string type = null;
                try
                {
                    parsed = JObject.Parse(json);
                    type = parsed.Value<string>("type");
                }
                catch { }

                if (type == "viewportMetrics")
                {
                    HandleViewportMetrics(parsed);
                }
                else if (type == "cursorFeedback" || json.Contains("\"cursorFeedback\""))
                {
                    HandleWebCursorFeedback(parsed);
                }
                else if (type == "interactiveRect" || json.Contains("\"interactiveRect\""))
                {
                    HandleInteractiveRects(parsed, json);
                }
                else if (type == "jukebox" || json.Contains("\"jukebox\""))
                {
                    HandleJukeboxMessage(json);
                }
                else if (type == "panel" || json.Contains("\"panel\""))
                {
                    HandlePanelMessage(json);
                }
                else if (type == "debug" || json.Contains("\"type\":\"debug\""))
                {
                    HandleDebugMessage(json);
                }
                else if (type == "gpuInfo")
                {
                    // overlay 启动探针：从 WebGL renderer 字符串判断 WebView2 实际落在哪块 GPU 上，
                    // 用于事后验证 gpuPreference=auto/on 是否真的生效（写 reg 不等于 Windows 一定遵从）。
                    string vendor = parsed != null ? parsed.Value<string>("vendor") : null;
                    string renderer = parsed != null ? parsed.Value<string>("renderer") : null;
                    LogManager.Log("[GpuPref] WebView2 WebGL renderer: " + (renderer ?? "(null)")
                        + " | vendor: " + (vendor ?? "(null)"));
                }
                else if (type == "click" || json.Contains("\"click\""))
                {
                    string key = ExtractString(json, "\"key\":\"");
                    if (key != null)
                        HandleButtonClick(key, json);
                }
                else if (type == "ready" || json.Contains("\"ready\""))
                {
                    LogManager.Log("[WebOverlay] JS side ready → activating web channel");
                    _webReady = true;
                    _webFailed = false; // 热重载恢复时清除降级标记
                    ApplyWebPerfMode("ready");

                    // 取消热重载超时 Timer
                    var oldTimeout = System.Threading.Interlocked.Exchange(ref _reloadTimeout, null);
                    if (oldTimeout != null) oldTimeout.Dispose();

                    // flush 早期缓冲
                    if (_toastReady)
                        FlushToastBuffer();
                    FlushUiDataBuffer();

                    // 显示 overlay（如果 SetReady 已先调用）
                    if (_shown)
                    {
                        SyncPosition();
                        ShowWindow(this.Handle, SW_SHOWNOACTIVATE);
                        SetWindowPos(this.Handle, HWND_TOP, 0, 0, 0, 0,
                            SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
                        if (_cursorOverlay != null)
                            _cursorOverlay.SetReady();
                    }
                    else
                    {
                        SyncPosition("ready_hidden");
                    }

                    // 非开发环境：隐藏"其他"菜单中的开发工具
                    if (!_devMode)
                        ExecScript("document.getElementById('notch').classList.add('hide-other')");

                    // 一次性推送光照等级静态数据
                    PushLightLevels();

                    // 推送音乐目录到 WebView
                    if (_musicCatalog != null)
                        PostToWeb(_musicCatalog.GetFullCatalogJson());

                    // Web 通道恢复，挂起 GDI+ fallback 避免双重 UI
                    SuspendFallback();
                    RequestViewportMetrics("ready");
                    ExecScript("if(window.Notch&&Notch.reportRect){Notch.reportRect();}");
                    EnsureCursorTimer();
                }
            }
            catch (Exception ex)
            {
                LogManager.Log("[WebOverlay] WebMessage error: " + ex.Message);
            }
        }

        private void HandleViewportMetrics(JObject parsed)
        {
            if (parsed == null)
                return;

            _coordinateContext.UpdateWebMetrics(
                ReadDouble(parsed, "innerWidth"),
                ReadDouble(parsed, "innerHeight"),
                ReadDouble(parsed, "clientWidth"),
                ReadDouble(parsed, "clientHeight"),
                ReadDouble(parsed, "devicePixelRatio"),
                ReadDouble(parsed, "visualViewportWidth"),
                ReadDouble(parsed, "visualViewportHeight"),
                parsed.Value<string>("reason") ?? "web_metrics");

            _missingMetricsWarned = false;
            if (_inputShield != null)
            {
                _inputShield.SetCoordinateContext(_coordinateContext);
                _inputShield.RequestPositionSync();
            }
            if (_cursorOverlay != null)
                _cursorOverlay.SetDpiScale(_coordinateContext.WindowDpiX, _coordinateContext.WindowDpiY);

            if (ShouldLogOverlayContext(false))
                DpiDiagnostics.LogOverlayContext("WebOverlay.viewportMetrics", _coordinateContext);
            ForceCursorSample("metrics:" + (parsed.Value<string>("reason") ?? "web_metrics"));
        }

        private CoreWebView2EnvironmentOptions CreateWebView2EnvironmentOptions()
        {
            List<string> args = new List<string>();
            if (_webView2DisableGpu)
            {
                args.Add("--disable-gpu");
                args.Add("--disable-gpu-rasterization");
                args.Add("--disable-accelerated-2d-canvas");
            }
            if (!string.IsNullOrEmpty(_webView2AdditionalArgs))
                args.Add(_webView2AdditionalArgs);

            if (args.Count == 0)
            {
                LogManager.Log("[WebOverlay] WebView2 perf options: lowEffects="
                    + _lowEffectsMode
                    + " noCssAnimations=" + _disableCssAnimations
                    + " noVisualizers=" + _disableVisualizers
                    + " disableGpu=false");
                return null;
            }

            string joined = string.Join(" ", args.ToArray());
            LogManager.Log("[WebOverlay] WebView2 perf options: lowEffects="
                + _lowEffectsMode
                + " noCssAnimations=" + _disableCssAnimations
                + " noVisualizers=" + _disableVisualizers
                + " disableGpu=" + _webView2DisableGpu
                + " args=" + joined);

            CoreWebView2EnvironmentOptions options = new CoreWebView2EnvironmentOptions();
            options.AdditionalBrowserArguments = joined;
            return options;
        }

        public void SetCursorOverlay(CursorOverlayForm cursorOverlay)
        {
            _cursorOverlay = cursorOverlay;
            if (_cursorOverlay != null)
            {
                _nativeCursorMissingLogged = false;
                _cursorOverlay.SetDpiScale(_coordinateContext.WindowDpiX, _coordinateContext.WindowDpiY);
            }
            else
            {
                RestoreSystemCursorForMissingNativeOverlay();
            }
            if (_shown && _cursorOverlay != null)
                _cursorOverlay.SetReady();
        }

        private void HandleInteractiveRects(JObject parsed, string rawJson)
        {
            if (!_coordinateContext.HasWebMetrics && !_missingMetricsWarned)
            {
                _missingMetricsWarned = true;
                LogManager.Log("[DPI] interactiveRect arrived before viewportMetrics; using fallback physicalScale=" + _zoomFactor.ToString("0.###"));
            }

            List<Rectangle> rects = new List<Rectangle>();
            if (parsed != null)
            {
                JArray arr = parsed["r"] as JArray;
                if (arr != null)
                {
                    for (int i = 0; i + 3 < arr.Count; i += 4)
                    {
                        double rx = ToDouble(arr[i]);
                        double ry = ToDouble(arr[i + 1]);
                        double rw = ToDouble(arr[i + 2]);
                        double rh = ToDouble(arr[i + 3]);
                        Rectangle r = _coordinateContext.CssRectToPhysical(rx, ry, rw, rh);
                        if (r.Width > 0 && r.Height > 0)
                            rects.Add(r);
                    }
                }
                else
                {
                    ReadInteractiveRectsFallback(rawJson, rects);
                    if (rects.Count == 0)
                    {
                        if (!_interactiveRectShapeWarned)
                        {
                            _interactiveRectShapeWarned = true;
                            LogManager.Log("[DPI] interactiveRect JSON missing r array; preserving previous hitRects");
                        }
                        return;
                    }
                }
            }
            else
            {
                ReadInteractiveRectsFallback(rawJson, rects);
            }

            if (_inputShield != null)
                _inputShield.UpdateHitRects(rects);

            long now = Environment.TickCount;
            if (rects.Count > 0 && (now - _lastHitRectLogTick > 2000 || _lastHitRectLogTick == 0))
            {
                _lastHitRectLogTick = now;
                LogManager.Log("[DPI] interactiveRect sample count=" + rects.Count
                    + " first=" + rects[0] + " " + _coordinateContext.Describe());
            }
        }

        private void ReadInteractiveRectsFallback(string json, List<Rectangle> rects)
        {
            int arrStart = json.IndexOf('[');
            int arrEnd = json.IndexOf(']');
            if (arrStart < 0 || arrEnd <= arrStart)
                return;

            string nums = json.Substring(arrStart + 1, arrEnd - arrStart - 1);
            string[] parts = nums.Split(',');
            for (int pi = 0; pi + 3 < parts.Length; pi += 4)
            {
                double rx, ry, rw, rh;
                if (double.TryParse(parts[pi].Trim(), NumberStyles.Float, CultureInfo.InvariantCulture, out rx) &&
                    double.TryParse(parts[pi + 1].Trim(), NumberStyles.Float, CultureInfo.InvariantCulture, out ry) &&
                    double.TryParse(parts[pi + 2].Trim(), NumberStyles.Float, CultureInfo.InvariantCulture, out rw) &&
                    double.TryParse(parts[pi + 3].Trim(), NumberStyles.Float, CultureInfo.InvariantCulture, out rh))
                {
                    Rectangle r = _coordinateContext.CssRectToPhysical(rx, ry, rw, rh);
                    if (r.Width > 0 && r.Height > 0)
                        rects.Add(r);
                }
            }
        }

        private static double ReadDouble(JObject obj, string key)
        {
            JToken token = obj[key];
            if (token == null)
                return 0;
            return ToDouble(token);
        }

        private static double ToDouble(JToken token)
        {
            if (token == null)
                return 0;
            try { return token.Value<double>(); }
            catch { return 0; }
        }

        public static double CalculateCssPhysicalScale(double viewportPhysicalHeight)
        {
            if (double.IsNaN(viewportPhysicalHeight) || double.IsInfinity(viewportPhysicalHeight))
                return 1.0;
            return Math.Max(0.25, viewportPhysicalHeight / FlashDesignHeight);
        }

        public static double CalculateWebViewZoomFactor(double viewportPhysicalHeight, double dpiY)
        {
            double dpiScale = (dpiY > 0 && !double.IsNaN(dpiY) && !double.IsInfinity(dpiY))
                ? dpiY / 96.0
                : 1.0;
            if (dpiScale <= 0)
                dpiScale = 1.0;
            return Math.Max(0.25, CalculateCssPhysicalScale(viewportPhysicalHeight) / dpiScale);
        }

        private static bool IsDpiRelatedReason(string reason)
        {
            return !string.IsNullOrEmpty(reason)
                && reason.IndexOf("dpi", StringComparison.OrdinalIgnoreCase) >= 0;
        }

        private bool ShouldLogOverlayContext(bool force)
        {
            double sx = _coordinateContext.CssToPhysicalX;
            double sy = _coordinateContext.CssToPhysicalY;
            bool changed = _lastOverlayContextLogTick == 0
                || force
                || _lastLoggedDpiX != _coordinateContext.WindowDpiX
                || _lastLoggedDpiY != _coordinateContext.WindowDpiY
                || _lastLoggedMonitor != _coordinateContext.MonitorHandle
                || Math.Abs(sx - _lastLoggedScaleX) > 0.05
                || Math.Abs(sy - _lastLoggedScaleY) > 0.05;

            if (!changed)
                return false;

            _lastOverlayContextLogTick = Environment.TickCount;
            _lastLoggedDpiX = _coordinateContext.WindowDpiX;
            _lastLoggedDpiY = _coordinateContext.WindowDpiY;
            _lastLoggedMonitor = _coordinateContext.MonitorHandle;
            _lastLoggedScaleX = sx;
            _lastLoggedScaleY = sy;
            return true;
        }

        /// <summary>向 JS 发送结构化消息。</summary>
        public void PostToWeb(string json)
        {
            if (!_webReady || _disposed) return;
            try
            {
                _webView.CoreWebView2.PostWebMessageAsJson(json);
            }
            catch { }
        }

        /// <summary>执行 JS 代码。</summary>
        public void ExecScript(string js)
        {
            if (!_webReady || _disposed) return;
            try
            {
                _webView.CoreWebView2.ExecuteScriptAsync(js);
            }
            catch { }
        }

        #endregion

        #region Cursor overlay

        public string HandleCursorControl(JObject msg)
        {
            JObject payload = msg["payload"] as JObject;
            string state = (payload != null ? payload.Value<string>("state") : null) ?? msg.Value<string>("state") ?? "normal";
            bool dragging = (payload != null ? payload.Value<bool?>("dragging") : null) ?? msg.Value<bool?>("dragging") ?? false;

            bool wasDragging = _cursorDragging;
            _cursorState = NormalizeCursorState(state);
            _cursorDragging = dragging;
            bool draggingChanged = wasDragging != _cursorDragging;

            ApplyCursorVisualState();
            EnsureCursorTimer();
            if (draggingChanged || !_cursorLastVisible)
                SendCursorPosition(true);

            return "{\"success\":true}";
        }

        private void HandleWebCursorFeedback(JObject parsed)
        {
            if (parsed == null)
                return;

            _webCursorState = NormalizeCursorState(parsed.Value<string>("state") ?? "normal");
            _webCursorActive = parsed.Value<bool?>("active") ?? (_webCursorState != "normal");
            ApplyCursorVisualState();
        }

        private void ApplyCursorVisualState()
        {
            if (_cursorOverlay == null)
                return;

            string visualState = _cursorState;
            bool visualDragging = _cursorDragging;
            if (!_cursorDragging && _webCursorActive)
            {
                visualState = _webCursorState;
                visualDragging = false;
            }

            _cursorOverlay.SetCursorState(visualState, visualDragging);
        }

        private static string NormalizeCursorState(string state)
        {
            if (string.IsNullOrEmpty(state)) return "normal";
            switch (state)
            {
                case "click":
                case "hoverGrab":
                case "grab":
                case "attack":
                case "openDoor":
                    return state;
                default:
                    return "normal";
            }
        }

        private void EnsureCursorTimer()
        {
            if (_disposed) return;
            EnsureCursorHook();
            if (_cursorTimer == null)
            {
                _cursorTimer = new System.Windows.Forms.Timer();
                _cursorTimer.Tick += delegate { SendCursorPosition(false); };
            }

            int interval = 16;
            if (_cursorTimer.Interval != interval)
                _cursorTimer.Interval = interval;
            if (!_cursorTimer.Enabled)
                _cursorTimer.Start();
        }

        private void EnsureCursorHook()
        {
            if (_cursorHook != IntPtr.Zero || _disposed)
                return;

            _cursorHookProc = CursorHookCallback;
            _cursorHook = SetWindowsHookEx(WH_MOUSE_LL, _cursorHookProc, GetModuleHandle(null), 0);
            if (_cursorHook == IntPtr.Zero)
                LogManager.Log("[Cursor] WH_MOUSE_LL hook install failed: " + Marshal.GetLastWin32Error());
            else
                LogManager.Log("[Cursor] WH_MOUSE_LL hook installed");
        }

        private void ReleaseCursorHook()
        {
            if (_cursorHook == IntPtr.Zero)
                return;

            try { UnhookWindowsHookEx(_cursorHook); }
            catch { }
            _cursorHook = IntPtr.Zero;
            _cursorHookProc = null;
            _cursorHookPostPending = false;
        }

        private IntPtr CursorHookCallback(int nCode, IntPtr wParam, IntPtr lParam)
        {
            if (nCode == HC_ACTION)
            {
                int message = wParam.ToInt32();
                if (IsCursorHookMessage(message))
                {
                    MSLLHOOKSTRUCT info = (MSLLHOOKSTRUCT)Marshal.PtrToStructure(lParam, typeof(MSLLHOOKSTRUCT));
                    QueueHookCursorSample(info.pt.X, info.pt.Y);
                    if (message == WM_LBUTTONUP)
                        QueuePhysicalCursorRelease();
                }
            }

            return CallNextHookEx(_cursorHook, nCode, wParam, lParam);
        }

        private static bool IsCursorHookMessage(int message)
        {
            return message == WM_MOUSEMOVE
                || message == WM_LBUTTONDOWN
                || message == WM_LBUTTONUP
                || message == WM_RBUTTONDOWN
                || message == WM_RBUTTONUP
                || message == WM_MBUTTONDOWN
                || message == WM_MBUTTONUP
                || message == WM_MOUSEWHEEL
                || message == WM_XBUTTONDOWN
                || message == WM_XBUTTONUP;
        }

        private void QueueHookCursorSample(int screenX, int screenY)
        {
            if (_disposed || !_shown || !_webReady)
                return;

            if (screenX == _cursorHookLastX && screenY == _cursorHookLastY)
                return;

            Rectangle bounds = _coordinateContext.OverlayPhysicalBounds;
            if (bounds.Width <= 0 || bounds.Height <= 0)
                bounds = this.Bounds;

            bool inside = bounds.Contains(screenX, screenY);
            if (!inside && !_cursorLastVisible)
                return;

            long now = Environment.TickCount;
            int minInterval = 8;
            if (inside && now - _lastCursorHookPostTick >= 0 && now - _lastCursorHookPostTick < minInterval)
            {
                _cursorHookPendingX = screenX;
                _cursorHookPendingY = screenY;
                return;
            }

            _lastCursorHookPostTick = now;
            _cursorHookLastX = screenX;
            _cursorHookLastY = screenY;
            _cursorHookPendingX = screenX;
            _cursorHookPendingY = screenY;
            if (!_cursorHookPostPending)
            {
                try
                {
                    if (IsHandleCreated)
                    {
                        _cursorHookPostPending = true;
                        BeginInvoke(new Action(FlushHookCursorSample));
                    }
                }
                catch { _cursorHookPostPending = false; }
            }
        }

        private void FlushHookCursorSample()
        {
            _cursorHookPostPending = false;
            if (_disposed)
                return;

            Point screen = new Point(_cursorHookPendingX, _cursorHookPendingY);
            Rectangle bounds = _coordinateContext.OverlayPhysicalBounds;
            if (bounds.Width <= 0 || bounds.Height <= 0)
                bounds = this.Bounds;

            if (!bounds.Contains(screen))
            {
                PostCursorVisibility(false);
                return;
            }

            UpdateCursorFromScreenPoint(screen, "hook");
        }

        private void QueuePhysicalCursorRelease()
        {
            if (!_cursorDragging && _cursorState != "grab")
                return;

            try
            {
                if (IsHandleCreated)
                    BeginInvoke(new Action(HandlePhysicalCursorRelease));
            }
            catch { }
        }

        private void HandlePhysicalCursorRelease()
        {
            if (_disposed)
                return;

            _cursorDragging = false;
            if (_cursorState == "grab")
                _cursorState = "hoverGrab";

            ApplyCursorVisualState();
            EnsureCursorTimer();
        }

        private void StopCursorTimer()
        {
            if (_cursorTimer != null)
                _cursorTimer.Stop();
            if (_cursorLastVisible)
                PostCursorVisibility(false);
        }

        private void SendCursorPosition(bool force)
        {
            if (_disposed || !_shown || !_webReady || !_owner.Visible || _owner.WindowState == FormWindowState.Minimized)
            {
                PostCursorVisibility(false);
                return;
            }

            Point screen = Control.MousePosition;
            Rectangle bounds = _coordinateContext.OverlayPhysicalBounds;
            if (bounds.Width <= 0 || bounds.Height <= 0)
                bounds = this.Bounds;

            bool visible = bounds.Contains(screen);
            if (!visible)
            {
                LogCursorSample("outside", screen, bounds, new Point(Int32.MinValue, Int32.MinValue),
                    new Point(Int32.MinValue, Int32.MinValue), false, force);
                PostCursorVisibility(false);
                if (_cursorTimer != null && _cursorTimer.Interval != 150)
                    _cursorTimer.Interval = 150;
                return;
            }

            int px = screen.X - bounds.Left;
            int py = screen.Y - bounds.Top;
            Point css = _coordinateContext.PhysicalPointToCss(px, py);

            if (!force && _cursorLastVisible && _cursorOverlay != null &&
                screen.X == _cursorLastScreenX && screen.Y == _cursorLastScreenY)
                return;
            if (!force && _cursorLastVisible && _cursorOverlay == null &&
                css.X == _cursorLastX && css.Y == _cursorLastY)
                return;

            _cursorLastVisible = true;
            HideSystemCursor();
            _cursorLastX = css.X;
            _cursorLastY = css.Y;
            _cursorLastScreenX = screen.X;
            _cursorLastScreenY = screen.Y;

            if (_cursorOverlay != null)
            {
                _cursorOverlay.UpdateCursorPosition(screen);
            }
            else
            {
                RestoreSystemCursorForMissingNativeOverlay();
            }
            LogCursorSample("send", screen, bounds, new Point(px, py), css, true, force);
            EnsureCursorTimer();
        }

        private void UpdateCursorFromOverlayPoint(int px, int py)
        {
            UpdateCursorFromOverlayPoint(px, py, "input");
        }

        private void UpdateCursorFromOverlayPoint(int px, int py, string kind)
        {
            if (_disposed || !_shown || !_webReady || px < 0 || py < 0)
                return;

            Rectangle bounds = _coordinateContext.OverlayPhysicalBounds;
            if (bounds.Width <= 0 || bounds.Height <= 0)
                bounds = this.Bounds;
            if (px > bounds.Width || py > bounds.Height)
                return;

            Point screen = new Point(bounds.Left + px, bounds.Top + py);
            Point css = _coordinateContext.PhysicalPointToCss(px, py);

            _cursorLastVisible = true;
            HideSystemCursor();
            _cursorLastX = css.X;
            _cursorLastY = css.Y;
            _cursorLastScreenX = screen.X;
            _cursorLastScreenY = screen.Y;

            if (_cursorOverlay != null)
            {
                _cursorOverlay.UpdateCursorPosition(screen);
            }
            else
            {
                RestoreSystemCursorForMissingNativeOverlay();
            }
            LogCursorSample(kind, screen, bounds, new Point(px, py), css, true, false);
            EnsureCursorTimer();
        }

        public void UpdateCursorFromScreenPoint(Point screen)
        {
            UpdateCursorFromScreenPoint(screen, "screen");
        }

        private void UpdateCursorFromScreenPoint(Point screen, string kind)
        {
            if (_disposed || !_shown || !_webReady)
                return;

            Rectangle bounds = _coordinateContext.OverlayPhysicalBounds;
            if (bounds.Width <= 0 || bounds.Height <= 0)
                bounds = this.Bounds;
            if (!bounds.Contains(screen))
                return;

            UpdateCursorFromOverlayPoint(screen.X - bounds.Left, screen.Y - bounds.Top, kind);
        }

        private void PostCursorVisibility(bool visible)
        {
            if (_cursorLastVisible == visible) return;
            _cursorLastVisible = visible;
            _cursorLastX = Int32.MinValue;
            _cursorLastY = Int32.MinValue;
            _cursorLastScreenX = Int32.MinValue;
            _cursorLastScreenY = Int32.MinValue;
            if (visible) HideSystemCursor();
            else ShowSystemCursor();
            if (_cursorOverlay != null)
            {
                _cursorOverlay.SetCursorVisible(visible);
            }
            else
            {
                RestoreSystemCursorForMissingNativeOverlay();
            }
            LogManager.Log("[Cursor] visible=" + visible
                + " state=" + _cursorState
                + " dragging=" + _cursorDragging
                + " reason=" + _cursorDiagReason);
        }

        private void ForceCursorSample(string reason)
        {
            _cursorDiagForce = true;
            _cursorDiagReason = reason ?? "force";
            _cursorLastX = Int32.MinValue;
            _cursorLastY = Int32.MinValue;
            _cursorLastScreenX = Int32.MinValue;
            _cursorLastScreenY = Int32.MinValue;
            if (_webReady && !_disposed)
                SendCursorPosition(true);
        }

        private void LogCursorSample(string kind, Point screen, Rectangle bounds, Point local,
            Point css, bool visible, bool force)
        {
            long now = Environment.TickCount;
            bool shouldLog = _cursorDiagForce || force || now - _lastCursorDiagTick > 1000;
            if (!shouldLog) return;

            _lastCursorDiagTick = now;
            _cursorDiagForce = false;
            LogManager.Log("[Cursor] " + kind
                + " visible=" + visible
                + " state=" + _cursorState
                + " dragging=" + _cursorDragging
                + " force=" + force
                + " interval=" + (_cursorTimer != null ? _cursorTimer.Interval.ToString(CultureInfo.InvariantCulture) : "none")
                + " screen=" + screen.X + "," + screen.Y
                + " local=" + local.X + "," + local.Y
                + " css=" + css.X + "," + css.Y
                + " bounds=" + bounds
                + " scale=" + _coordinateContext.CssToPhysicalX.ToString("0.###", CultureInfo.InvariantCulture)
                + "x" + _coordinateContext.CssToPhysicalY.ToString("0.###", CultureInfo.InvariantCulture)
                + " webCss=" + _coordinateContext.WebCssWidth.ToString("0.##", CultureInfo.InvariantCulture)
                + "x" + _coordinateContext.WebCssHeight.ToString("0.##", CultureInfo.InvariantCulture)
                + " dpr=" + _coordinateContext.DevicePixelRatio.ToString("0.###", CultureInfo.InvariantCulture)
                + " reason=" + _cursorDiagReason);
        }

        private void HideSystemCursor()
        {
            if (_cursorOverlay == null)
            {
                RestoreSystemCursorForMissingNativeOverlay();
                return;
            }
            if (_systemCursorHidden) return;
            Cursor.Hide();
            _systemCursorHidden = true;
        }

        private void ShowSystemCursor()
        {
            if (!_systemCursorHidden) return;
            Cursor.Show();
            _systemCursorHidden = false;
        }

        private void RestoreSystemCursorForMissingNativeOverlay()
        {
            ShowSystemCursor();
            if (_nativeCursorMissingLogged)
                return;

            _nativeCursorMissingLogged = true;
            LogManager.Log("[Cursor] native overlay unavailable; web visual fallback is disabled; using system cursor");
        }

        #endregion

        private void HandleDebugMessage(string json)
        {
            try
            {
                JObject parsed = JObject.Parse(json);
                string scope = parsed.Value<string>("scope") ?? "";
                if (scope != "map_layout")
                    LogManager.Log("[WebDebug] " + json);
            }
            catch (Exception ex)
            {
                LogManager.Log("[WebDebug] parse failed: " + ex.Message);
            }
        }

        #region Notch 注入

        /// <summary>注入光照等级数据（24 元素数组）。</summary>
        public void SetLightLevels(int[] levels)
        {
            _lightLevels = levels;
        }

        /// <summary>将光照等级数组一次性推送给 JS。</summary>
        private void PushLightLevels()
        {
            if (_lightLevels == null || _lightLevels.Length < 24) return;
            System.Text.StringBuilder sb = new System.Text.StringBuilder(128);
            sb.Append("{\"type\":\"lightLevels\",\"levels\":[");
            for (int i = 0; i < 24; i++)
            {
                if (i > 0) sb.Append(',');
                sb.Append(_lightLevels[i]);
            }
            sb.Append("]}");
            PostToWeb(sb.ToString());
        }

        /// <summary>注入 XmlSocketServer 用于发送游戏命令（pause 等）。</summary>
        public void SetSocketServer(XmlSocketServer server)
        {
            _socketServer = server;
        }

        /// <summary>设置开发模式标志。非开发环境下隐藏"其他"菜单中的开发工具。</summary>
        public void SetDevMode(bool isDev)
        {
            _devMode = isDev;
        }

        internal void SetMusicCatalog(CF7Launcher.Audio.MusicCatalog catalog)
        {
            _musicCatalog = catalog;
            catalog.CatalogChanged += delegate(string updateJson) {
                if (_webReady) PostToWeb(updateJson);
            };
        }

        /// <summary>
        /// 注入 Notch 所需的依赖。在 FrameTask 创建后调用。
        /// </summary>
        public void SetNotchDependencies(FpsRingBuffer fpsBuffer,
            Action onToggleFullscreen, Action onToggleLog,
            Action onForceExit, Action<Keys> onSendKey)
        {
            _fpsBuffer = fpsBuffer;
            _onToggleFullscreen = onToggleFullscreen;
            _onToggleLog = onToggleLog;
            _onForceExit = onForceExit;
            _onSendKey = onSendKey;

            // FPS 推送 timer (1Hz)
            _fpsTimer = new System.Windows.Forms.Timer();
            _fpsTimer.Interval = 1000;
            _fpsTimer.Tick += OnFpsTick;

            // BGM 音频可视化 timer (60ms ≈ 16.7Hz)
            _audioTimer = new System.Windows.Forms.Timer();
            _audioTimer.Interval = _disableVisualizers ? 250 : 60;
            _audioTimer.Tick += OnAudioTick;
        }

        private void OnFpsTick(object sender, EventArgs e)
        {
            if (!_webReady || _disposed || _fpsBuffer == null) return;
            if (!_fpsBuffer.HasData) return;

            // 构建 JSON: {type:"fps", value:N, hour:N, points:[...]}
            System.Text.StringBuilder sb = new System.Text.StringBuilder(256);
            sb.Append("{\"type\":\"fps\",\"value\":");
            sb.Append(Math.Round(_fpsBuffer.Latest * 10) / 10.0); // 1 位小数
            sb.Append(",\"hour\":");
            sb.Append(_fpsBuffer.GameHour);
            sb.Append(",\"level\":");
            sb.Append(_fpsBuffer.PerfLevel);
            sb.Append(",\"points\":[");
            int count = _fpsBuffer.Count;
            int start = Math.Max(0, count - 30);
            for (int i = start; i < count; i++)
            {
                if (i > start) sb.Append(',');
                sb.Append(Math.Round(_fpsBuffer.GetAt(i) * 10) / 10.0);
            }
            sb.Append("]}");
            PostToWeb(sb.ToString());
        }

        private void OnAudioTick(object sender, EventArgs e)
        {
            if (!_webReady || _disposed) return;

            try
            {
                if (_disableVisualizers)
                {
                    int lowEffectsPlaying = Audio.AudioEngine.ma_bridge_bgm_is_playing();
                    HandleAudioTrackState(lowEffectsPlaying);
                    return;
                }

                float peakL, peakR;
                Audio.AudioEngine.ma_bridge_bgm_get_peak(out peakL, out peakR);
                int playing = Audio.AudioEngine.ma_bridge_bgm_is_playing();
                float cursor = Audio.AudioEngine.ma_bridge_bgm_get_cursor();
                float length = Audio.AudioEngine.ma_bridge_bgm_get_length();

                // 紧凑 JSON: {type:"audio",l:0.5,r:0.4,p:1,c:12.3,d:180.0}
                System.Text.StringBuilder sb = new System.Text.StringBuilder(128);
                sb.Append("{\"type\":\"audio\",\"l\":");
                sb.Append(Math.Round(peakL * 1000) / 1000.0);
                sb.Append(",\"r\":");
                sb.Append(Math.Round(peakR * 1000) / 1000.0);
                sb.Append(",\"p\":");
                sb.Append(playing);
                sb.Append(",\"c\":");
                sb.Append(Math.Round(cursor * 10) / 10.0);
                sb.Append(",\"d\":");
                sb.Append(Math.Round(length * 10) / 10.0);
                sb.Append('}');
                PostToWeb(sb.ToString());

                // 曲目自然结束检测（排除暂停和手动 stop）
                bool isPlaying = playing == 1;
                // Flash 侧 bgm_play/bgm_stop 同样视为 manual stop，防换歌间隙误触 trackEnd
                if (CF7Launcher.Tasks.AudioTask.FlashBgmChange)
                {
                    _manualStop = true;
                    CF7Launcher.Tasks.AudioTask.FlashBgmChange = false;
                }
                if (_wasPlaying && !isPlaying && !_manualStop && !_bgmPaused)
                {
                    SendGameCommand("jukeboxTrackEnd");
                }
                _wasPlaying = isPlaying;
                if (isPlaying) { _manualStop = false; _bgmPaused = false; }
            }
            catch { }
        }

        /// <summary>设置当前 BGM 标题（由 UiData bgm: 推送）。</summary>
        private void HandleAudioTrackState(int playing)
        {
            bool isPlaying = playing == 1;
            if (CF7Launcher.Tasks.AudioTask.FlashBgmChange)
            {
                _manualStop = true;
                CF7Launcher.Tasks.AudioTask.FlashBgmChange = false;
            }
            if (_wasPlaying && !isPlaying && !_manualStop && !_bgmPaused)
            {
                SendGameCommand("jukeboxTrackEnd");
            }
            _wasPlaying = isPlaying;
            if (isPlaying) { _manualStop = false; _bgmPaused = false; }
        }

        public void SetBgmTitle(string title)
        {
            _bgmTitle = title ?? "";
        }

        #endregion

        #region UI 数据快车道 (U 前缀)

        /// <summary>
        /// 处理 U 前缀 payload，零解析转发到 JS。
        /// 格式：{type}|{field1}|{field2}|...
        /// JS 端 UiData.dispatch(type, fields[]) 负责分发。
        /// </summary>
        public void HandleUiData(string payload)
        {
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action<string>(HandleUiData), payload);
                return;
            }
            if (_disposed) return;

            // 维护最新值快照：payload 是 "key:val|key:val|..." 合批 KV 格式
            // 按每个 KV 对的 key 独立存储最新值，热重载后可恢复完整状态
            {
                string[] pairs = payload.Split('|');
                for (int i = 0; i < pairs.Length; i++)
                {
                    int colon = pairs[i].IndexOf(':');
                    if (colon > 0)
                        _uiDataSnapshot[pairs[i].Substring(0, colon)] = pairs[i];
                    // 无冒号的段（旧格式）不进快照，由 buffer 兜底
                }
            }

            if (_webFailed || !_webReady)
            {
                // WebView2 未就绪或降级中，缓冲等待恢复（上限 200 条防止内存泄漏）
                if (_uiDataEarlyBuffer.Count < 200)
                    _uiDataEarlyBuffer.Add(payload);
                return;
            }
            string escaped = payload.Replace("\\", "\\\\").Replace("'", "\\'");
            ExecScript("typeof UiData!=='undefined'&&UiData.dispatch('" + escaped + "')");
        }

        private void FlushUiDataBuffer()
        {
            // 1) 先回放快照：将所有已知 KV 最新值合并成一条 payload 推送
            //    快照格式: key → "key:val"，拼接为 "s:1|k:1303750|p:0|..."
            if (_uiDataSnapshot.Count > 0)
            {
                var sb = new System.Text.StringBuilder();
                foreach (var kv in _uiDataSnapshot)
                {
                    if (sb.Length > 0) sb.Append('|');
                    sb.Append(kv.Value); // kv.Value 已是 "key:val" 格式
                }
                string snapshotPayload = sb.ToString().Replace("\\", "\\\\").Replace("'", "\\'");
                ExecScript("typeof UiData!=='undefined'&&UiData.dispatch('" + snapshotPayload + "')");
            }

            // 2) 再回放 buffer 中快照未覆盖的条目
            //    buffer 中的合批 payload 拆分后逐 key 检查，只推送快照未含的 key
            foreach (string p in _uiDataEarlyBuffer)
            {
                string[] pairs = p.Split('|');
                var remaining = new System.Text.StringBuilder();
                for (int i = 0; i < pairs.Length; i++)
                {
                    int colon = pairs[i].IndexOf(':');
                    string key = colon > 0 ? pairs[i].Substring(0, colon) : null;
                    if (key != null && _uiDataSnapshot.ContainsKey(key)) continue; // 快照已有最新值
                    if (remaining.Length > 0) remaining.Append('|');
                    remaining.Append(pairs[i]);
                }
                if (remaining.Length > 0)
                    HandleUiData(remaining.ToString());
            }
            _uiDataEarlyBuffer.Clear();
        }

        #endregion

        #region INotchSink

        public void AddNotice(string category, string text, Color accentColor)
        {
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action<string, string, Color>(AddNotice),
                    category, text, accentColor);
                return;
            }
            if (_webFailed || !_webReady || _disposed) { if (_notchFallback != null) _notchFallback.AddNotice(category, text, accentColor); return; }
            string hex = accentColor.R.ToString("x2") + accentColor.G.ToString("x2") + accentColor.B.ToString("x2");
            string escaped = text.Replace("\\", "\\\\").Replace("'", "\\'");
            ExecScript("typeof Notch!=='undefined'&&Notch.addNotice('" + category + "','" + escaped + "','#" + hex + "')");
        }

        public void SetStatusItem(string id, string label, string subLabel, Color accentColor)
        {
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action<string, string, string, Color>(SetStatusItem),
                    id, label, subLabel, accentColor);
                return;
            }
            if (_webFailed || !_webReady || _disposed) { if (_notchFallback != null) _notchFallback.SetStatusItem(id, label, subLabel, accentColor); return; }
            string text = label;
            if (!string.IsNullOrEmpty(subLabel)) text += "  " + subLabel;
            string hex = accentColor.R.ToString("x2") + accentColor.G.ToString("x2") + accentColor.B.ToString("x2");
            string escaped = text.Replace("\\", "\\\\").Replace("'", "\\'");
            ExecScript("typeof Notch!=='undefined'&&Notch.setStatus('" + id + "','" + escaped + "','#" + hex + "')");
        }

        public void ClearStatusItem(string id)
        {
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action<string>(ClearStatusItem), id);
                return;
            }
            if (_webFailed || !_webReady || _disposed) { if (_notchFallback != null) _notchFallback.ClearStatusItem(id); return; }
            ExecScript("typeof Notch!=='undefined'&&Notch.clearStatus('" + id + "')");
        }

        #endregion

        #region IToastSink

        public void AddMessage(string text)
        {
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action<string>(AddMessage), text);
                return;
            }
            // WebView2 初始化失败 → 永久走 GDI+ fallback
            if (_webFailed)
            {
                if (_toastFallback != null) _toastFallback.AddMessage(text);
                return;
            }
            if (!_toastReady)
            {
                _toastEarlyBuffer.Add(text);
                return;
            }
            SendToast(text);
        }

        private void SendToast(string text)
        {
            if (!_webReady || _disposed)
            {
                // JS 还没 ready → 走 GDI+ fallback，不丢弃
                if (_toastFallback != null) _toastFallback.AddMessage(text);
                return;
            }
            string escaped = EscapeForJs(text);
            ExecScript("typeof Toast!=='undefined'&&Toast.add('" + escaped + "')");
        }

        private void FlushToastBuffer()
        {
            foreach (string msg in _toastEarlyBuffer)
                SendToast(msg);
            _toastEarlyBuffer.Clear();
        }

        #endregion

        #region 生命周期

        /// <summary>
        /// 激活 overlay 显示。在 Flash 窗口嵌入完成后调用。
        /// </summary>
        public void SetReady()
        {
            if (_disposed) return;
            _shown = true;
            _toastReady = true;
            if (_webReady)
                FlushToastBuffer();
            if (_fpsTimer != null)
                _fpsTimer.Start();
            if (_audioTimer != null)
                _audioTimer.Start();
            if (_webReady)
            {
                SyncPosition();
                ShowWindow(this.Handle, SW_SHOWNOACTIVATE);
                SetWindowPos(this.Handle, HWND_TOP, 0, 0, 0, 0,
                    SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
                if (_cursorOverlay != null)
                    _cursorOverlay.SetReady();
                RequestViewportMetrics("set_ready");
                ExecScript("if(window.Notch&&Notch.reportRect){Notch.reportRect();}");
                EnsureCursorTimer();
            }
        }

        protected override void Dispose(bool disposing)
        {
            if (_disposed) return;
            _disposed = true;

            if (disposing)
            {
                ShowSystemCursor();
                if (_fpsTimer != null)
                {
                    _fpsTimer.Stop();
                    _fpsTimer.Dispose();
                    _fpsTimer = null;
                }
                if (_audioTimer != null)
                {
                    _audioTimer.Stop();
                    _audioTimer.Dispose();
                    _audioTimer = null;
                }
                if (_cursorTimer != null)
                {
                    _cursorTimer.Stop();
                    _cursorTimer.Dispose();
                    _cursorTimer = null;
                }
                if (_cursorOverlay != null)
                {
                    _cursorOverlay.Dispose();
                    _cursorOverlay = null;
                }
                ReleaseCursorHook();
                if (_positionSettleTimer != null)
                {
                    _positionSettleTimer.Stop();
                    _positionSettleTimer.Dispose();
                    _positionSettleTimer = null;
                }
                if (_positionLongSettleTimer != null)
                {
                    _positionLongSettleTimer.Stop();
                    _positionLongSettleTimer.Dispose();
                    _positionLongSettleTimer = null;
                }
                if (_webWatcher != null)
                {
                    _webWatcher.EnableRaisingEvents = false;
                    _webWatcher.Dispose();
                    _webWatcher = null;
                }
                if (_reloadDebounce != null)
                {
                    _reloadDebounce.Dispose();
                    _reloadDebounce = null;
                }
                if (_reloadTimeout != null)
                {
                    _reloadTimeout.Dispose();
                    _reloadTimeout = null;
                }
                if (_webView != null)
                {
                    _webView.Dispose();
                    _webView = null;
                }
            }

            base.Dispose(disposing);
            LogManager.Log("[WebOverlay] Disposed");
        }

        #endregion

        #region 面板系统

        public void SetShopTask(ShopTask task)
        {
            _shopTask = task;
            task.SetPostToWeb(PostToWeb);
            task.SetInvoker(delegate(Action a) { try { this.BeginInvoke(a); } catch {} });
        }

        public void SetGomokuTask(GomokuTask task)
        {
            _gomokuTask = task;
        }

        public void SetMapTask(MapTask task)
        {
            _mapTask = task;
            task.SetPostToWeb(PostToWeb);
            task.SetInvoker(delegate(Action a) { try { this.BeginInvoke(a); } catch {} });
        }

        public void SetPanelStateCallback(Action<bool> cb) { _onPanelStateChanged = cb; }

        private void HandlePanelMessage(string json)
        {
            LogManager.Log("[Panel] HandlePanelMessage: " + json);
            JObject parsed;
            try { parsed = JObject.Parse(json); } catch { LogManager.Log("[Panel] JSON parse failed"); return; }
            string cmd = parsed.Value<string>("cmd");
            if (cmd == null) { LogManager.Log("[Panel] cmd is null"); return; }
            switch (cmd)
            {
                case "close":
                    {
                        string panel = parsed.Value<string>("panel") ?? "";
                        if (panel == "kshop")
                        {
                            if (!TrySendGameCommand("shopPanelClose"))
                                _pauseNeedsRestore = true;
                        }
                        else if (panel == "map")
                        {
                            TrySendGameCommand("mapPanelClose");
                        }
                        // help 等纯 web 面板无需通知 Flash
                        _activePanel = null;
                        if (_onPanelStateChanged != null) _onPanelStateChanged(false);
                    }
                    break;
                case "bulkQuery":
                case "checkout":
                case "claim":
                case "saveCart":
                case "tooltip":
                    LogManager.Log("[Panel] Routing cmd=" + cmd + " to ShopTask, _shopTask=" + (_shopTask != null ? "ok" : "NULL"));
                    if (_shopTask != null) _shopTask.HandleWebRequest(cmd, parsed);
                    break;
                case "snapshot":
                case "navigate":
                case "refresh":
                    LogManager.Log("[Panel] Routing cmd=" + cmd + " to MapTask, _mapTask=" + (_mapTask != null ? "ok" : "NULL"));
                    if (_mapTask != null) _mapTask.HandleWebRequest(cmd, parsed);
                    break;
                case "gomoku_eval":
                    LogManager.Log("[Panel] Routing cmd=gomoku_eval to GomokuTask, _gomokuTask=" + (_gomokuTask != null ? "ok" : "NULL"));
                    HandleGobangEvalRequest(parsed);
                    break;
                case "minigame_session":
                    {
                        JToken payload = parsed["payload"];
                        if (payload == null) break;

                        string game = (string)payload["game"];

                        string prefix;
                        if (string.Equals(game, "lockbox", StringComparison.OrdinalIgnoreCase)) prefix = "Lockbox";
                        else if (string.Equals(game, "pinalign", StringComparison.OrdinalIgnoreCase)) prefix = "PinAlign";
                        else if (string.Equals(game, "gobang", StringComparison.OrdinalIgnoreCase)) prefix = "Gobang";
                        else prefix = "Minigame";

                        LogManager.Log("[" + prefix + "] " + payload.ToString(Newtonsoft.Json.Formatting.None));
                    }
                    break;
            }
        }

        private void HandleGobangEvalRequest(JObject parsed)
        {
            string webCallId = parsed.Value<string>("callId");
            if (string.IsNullOrEmpty(webCallId))
            {
                LogManager.Log("[Gobang] webCallId is empty");
                return;
            }

            if (_gomokuTask == null)
            {
                PostGobangEvalResponse(webCallId, "{\"success\":false,\"error\":\"gomoku_task_unavailable\"}");
                return;
            }

            _gomokuTask.HandleAsync(parsed, delegate(string response)
            {
                if (_disposed) return;
                Action post = delegate { PostGobangEvalResponse(webCallId, response); };
                try
                {
                    if (this.IsHandleCreated && this.InvokeRequired) this.BeginInvoke(post);
                    else post();
                }
                catch { }
            });
        }

        private void PostGobangEvalResponse(string webCallId, string response)
        {
            JObject msg;
            try
            {
                msg = string.IsNullOrEmpty(response)
                    ? new JObject()
                    : JObject.Parse(response);
            }
            catch
            {
                msg = new JObject();
                msg["success"] = false;
                msg["error"] = "invalid_gomoku_response";
            }

            if (msg["success"] == null) msg["success"] = false;
            msg.Remove("task");
            msg["type"] = "panel_resp";
            msg["panel"] = "gobang";
            msg["cmd"] = "gomoku_eval";
            msg["callId"] = webCallId;
            PostToWeb(msg.ToString(Newtonsoft.Json.Formatting.None));
        }

        private bool TrySendGameCommand(string action)
        {
            if (_socketServer == null || !_socketServer.IsClientReady) return false;
            return _socketServer.TrySend("{\"task\":\"cmd\",\"action\":\"" + action + "\"}\0");
        }

        public void OnSocketDisconnected()
        {
            if (this.InvokeRequired) { try { this.BeginInvoke(new Action(OnSocketDisconnected)); } catch {} return; }

            if (_activePanel != null)
            {
                PostToWeb("{\"type\":\"panel_cmd\",\"cmd\":\"force_close\",\"reason\":\"disconnected\"}");
                // 只有需要 Flash 交互的面板才需要恢复暂停状态
                if (_activePanel == "kshop")
                    _pauseNeedsRestore = true;
                _activePanel = null;
                if (_onPanelStateChanged != null) _onPanelStateChanged(false);
            }
            if (_shopTask != null) _shopTask.ClearPending();
            if (_mapTask != null) _mapTask.ClearPending();
        }

        public void OnSocketReconnected()
        {
            if (this.InvokeRequired) { try { this.BeginInvoke(new Action(OnSocketReconnected)); } catch {} return; }

            if (_pauseNeedsRestore)
            {
                if (TrySendGameCommand("shopPanelClose"))
                    _pauseNeedsRestore = false;
            }
        }

        #endregion

        #region 辅助方法

        private void HandleButtonClick(string key)
        {
            HandleButtonClick(key, null);
        }

        private void HandleButtonClick(string key, string rawJson)
        {
            switch (key)
            {
                case "Q": if (_onSendKey != null) _onSendKey(Keys.Q); break;
                case "W": if (_onSendKey != null) _onSendKey(Keys.W); break;
                case "R": if (_onSendKey != null) _onSendKey(Keys.R); break;
                case "F": if (_onToggleFullscreen != null) _onToggleFullscreen(); break;
                case "P": if (_onSendKey != null) _onSendKey(Keys.P); break;
                case "O": if (_onSendKey != null) _onSendKey(Keys.O); break;
                case "LOG": if (_onToggleLog != null) _onToggleLog(); break;
                case "EXIT": if (_onForceExit != null) _onForceExit(); break;
                case "PAUSE": SendGameCommand("togglePause"); break;
                case "WAREHOUSE": SendGameCommand("warehouse"); break;
                case "SETTINGS": SendGameCommand("toggleSettings"); break;
                case "SHOP":
                    LogManager.Log("[Panel] SHOP clicked, _webFailed=" + _webFailed);
                    if (_webFailed)
                    {
                        LogManager.Log("[Panel] SHOP → fallback openShop");
                        SendGameCommand("openShop");
                    }
                    else if (!TrySendGameCommand("shopPanelOpen"))
                    {
                        LogManager.Log("[Panel] SHOP → TrySend failed");
                        PostToWeb("{\"type\":\"toast\",\"text\":\"商城暂时不可用\"}");
                    }
                    else
                    {
                        LogManager.Log("[Panel] SHOP → opening panel via PostToWeb");
                        PostToWeb("{\"type\":\"panel_cmd\",\"cmd\":\"open\",\"panel\":\"kshop\"}");
                        _activePanel = "kshop";
                        if (_onPanelStateChanged != null) _onPanelStateChanged(true);
                        LogManager.Log("[Panel] SHOP → _activePanel=kshop, state callback fired");
                    }
                    break;
                case "HELP":
                    PostToWeb("{\"type\":\"panel_cmd\",\"cmd\":\"open\",\"panel\":\"help\"}");
                    _activePanel = "help";
                    if (_onPanelStateChanged != null) _onPanelStateChanged(true);
                    break;
                case "SAFEEXIT": SendGameCommand("safeExit"); break;
                case "PETS": SendGameCommand("togglePets"); break;
                case "MERCS": SendGameCommand("toggleMercs"); break;
                case "TABLET": SendGameCommand("toggleTablet"); break;
                case "GAMESETTINGS": SendGameCommand("openSettings"); break;
                case "JUKEBOX": SendGameCommand("openJukebox"); break;
                case "TASK_MAP":
                    OpenMapPanel("task_map", false);
                    break;
                case "TASK_DELIVER":
                    {
                        string hotspotId = rawJson != null ? ExtractString(rawJson, "\"hotspotId\":\"") : null;
                        if (string.IsNullOrEmpty(hotspotId))
                        {
                            LogManager.Log("[Panel] TASK_DELIVER missing hotspotId");
                            break;
                        }
                        SendGameCommand("navigateToHotspot",
                            "\"targetId\":\"" + EscapeJsonString(hotspotId) + "\"");
                    }
                    break;
                case "TASK_UI": SendGameCommand("openTaskUI"); break;
                case "EQUIP_UI": SendGameCommand("openEquipUI"); break;
                case "BAKE": SendGameCommand("bakeIcons"); break;
                case "BAKE10": SendGameCommand("bakeIcons", "\"maxCount\":10"); break;
                case "LOCKBOX_TEST":
                    {
                        uint familySeed = unchecked((uint)Environment.TickCount);
                        PostToWeb("{\"type\":\"panel_cmd\",\"cmd\":\"open\",\"panel\":\"lockbox\",\"initData\":{\"mode\":\"dev\",\"profile\":\"standard\",\"source\":\"runtime\",\"familySeed\":" + familySeed + ",\"variantIndex\":0,\"debug\":true}}");
                        _activePanel = "lockbox";
                        if (_onPanelStateChanged != null) _onPanelStateChanged(true);
                    }
                    break;
                case "PINALIGN_TEST":
                    PostToWeb("{\"type\":\"panel_cmd\",\"cmd\":\"open\",\"panel\":\"pinalign\",\"initData\":{\"mode\":\"dev\",\"specId\":\"mvp-3pin-v1\",\"masterSeed\":\"dev-default\",\"debug\":true}}");
                    _activePanel = "pinalign";
                    if (_onPanelStateChanged != null) _onPanelStateChanged(true);
                    break;
                case "GOBANG_TEST":
                    PostToWeb("{\"type\":\"panel_cmd\",\"cmd\":\"open\",\"panel\":\"gobang\",\"initData\":{\"mode\":\"dev\",\"source\":\"runtime\",\"ruleset\":\"casual\",\"difficulty\":\"normal\",\"playerRole\":1,\"aiEnabled\":true,\"debug\":true}}");
                    _activePanel = "gobang";
                    if (_onPanelStateChanged != null) _onPanelStateChanged(true);
                    break;
                case "EXIT_CONFIRM": if (_onForceExit != null) _onForceExit(); break;
            }
        }

        private void OpenMapPanel(string source, bool dev)
        {
            OpenMapPanel(source, dev, null);
        }

        private void OpenMapPanel(string source, bool dev, string pageId)
        {
            string initData = "{\"source\":\"" + EscapeJsonString(source) + "\",\"dev\":" + (dev ? "true" : "false");
            if (!string.IsNullOrEmpty(pageId))
                initData += ",\"page\":\"" + EscapeJsonString(pageId) + "\"";
            initData += "}";
            PostToWeb("{\"type\":\"panel_cmd\",\"cmd\":\"open\",\"panel\":\"map\",\"initData\":" + initData + "}");
            _activePanel = "map";
            if (_onPanelStateChanged != null) _onPanelStateChanged(true);
        }

        /// <summary>
        /// AS2 → C# 面板打开请求 (旧版 Flash UI 按钮接入 WebView 面板).
        /// 通过 TaskRegistry 注册的 "panel_request" task 驱动.
        /// 当前仅支持 panel=="map"; 其它 panel 留待后续 (help / shop 已有各自入口).
        /// </summary>
        public void RequestOpenPanel(string panelName, string source)
        {
            RequestOpenPanel(panelName, source, null);
        }

        public void RequestOpenPanel(string panelName, string source, string pageId)
        {
            if (_disposed) return;
            if (this.IsHandleCreated && this.InvokeRequired)
            {
                try
                {
                    this.BeginInvoke(new Action(delegate()
                    {
                        RequestOpenPanel(panelName, source, pageId);
                    }));
                }
                catch { }
                return;
            }

            string safeSource = string.IsNullOrEmpty(source) ? "as2_request" : source;
            if (string.Equals(panelName, "map", StringComparison.OrdinalIgnoreCase))
            {
                LogManager.Log("[Panel] RequestOpenPanel map source=" + safeSource + " pageId=" + (pageId ?? ""));
                OpenMapPanel(safeSource, false, pageId);
            }
            else
            {
                LogManager.Log("[Panel] RequestOpenPanel unsupported panel=" + (panelName ?? "<null>"));
            }
        }

        /// <summary>通过 XmlSocket 向 AS2 发送游戏命令。</summary>
        private void SendGameCommand(string action)
        {
            if (_socketServer == null) return;
            _socketServer.Send("{\"task\":\"cmd\",\"action\":\"" + action + "\"}\0");
        }

        /// <summary>通过 XmlSocket 向 AS2 发送带参数的游戏命令。</summary>
        private void SendGameCommand(string action, string extraJsonFields)
        {
            if (_socketServer == null) return;
            _socketServer.Send("{\"task\":\"cmd\",\"action\":\"" + action + "\"," + extraJsonFields + "}\0");
        }

        private static int ExtractInt(string json, string key)
        {
            int idx = json.IndexOf(key);
            if (idx < 0) return 0;
            idx += key.Length;
            int end = idx;
            while (end < json.Length && (char.IsDigit(json[end]) || json[end] == '-'))
                end++;
            int val;
            if (int.TryParse(json.Substring(idx, end - idx), out val))
                return val;
            return 0;
        }

        private static string ExtractString(string json, string key)
        {
            int idx = json.IndexOf(key);
            if (idx < 0) return null;
            idx += key.Length;
            int end = json.IndexOf('"', idx);
            if (end < 0) return null;
            return json.Substring(idx, end - idx);
        }

        /// <summary>转义字符串供 JS 单引号字面量使用。</summary>
        private static string EscapeForJs(string text)
        {
            return text.Replace("\\", "\\\\").Replace("'", "\\'").Replace("\n", "\\n").Replace("\r", "");
        }

        // ── Jukebox 消息处理 ──

        private void HandleJukeboxMessage(string json)
        {
            string cmd = ExtractString(json, "\"cmd\":\"");
            if (cmd == null) return;

            switch (cmd)
            {
                case "play":
                    string title = ExtractString(json, "\"title\":\"");
                    if (title != null)
                        SendGameCommandWithData("jukeboxPlay",
                            "\"title\":\"" + EscapeJsonString(title) + "\"");
                    break;
                case "override":
                    bool over = json.Contains("\"value\":true");
                    SendGameCommandWithData("jukeboxOverride",
                        "\"value\":" + (over ? "true" : "false"));
                    break;
                case "trueRandom":
                    bool tr = json.Contains("\"value\":true");
                    SendGameCommandWithData("jukeboxTrueRandom",
                        "\"value\":" + (tr ? "true" : "false"));
                    break;
                case "playMode":
                    string mode = ExtractString(json, "\"value\":\"");
                    if (mode != null)
                        SendGameCommandWithData("jukeboxPlayMode",
                            "\"value\":\"" + EscapeJsonString(mode) + "\"");
                    break;
                case "seek":
                    float sec = ExtractFloat(json, "\"sec\":");
                    Audio.AudioEngine.ma_bridge_bgm_seek(sec);
                    break;
                case "pause":
                    _bgmPaused = true;
                    Audio.AudioEngine.ma_bridge_bgm_pause();
                    break;
                case "resume":
                    _bgmPaused = false;
                    Audio.AudioEngine.ma_bridge_bgm_resume();
                    break;
                case "stop":
                    _manualStop = true;
                    _bgmPaused = false;
                    // 不 resume — 直接让 Flash 侧 stopBGM 处理
                    // （native 层 bgm_stop 对已暂停的 sound 同样有效）
                    SendGameCommand("jukeboxStop");
                    break;
                case "volGlobal":
                    int vg = ExtractInt(json, "\"value\":");
                    SendGameCommandWithData("setGlobalVolume", "\"value\":" + vg);
                    break;
                case "volBgm":
                    int vb = ExtractInt(json, "\"value\":");
                    SendGameCommandWithData("setBGMVolume", "\"value\":" + vb);
                    break;
                case "loadHelp":
                    LoadAndPushHelp();
                    break;
            }
        }

        private void LoadAndPushHelp()
        {
            try
            {
                // 读取 sounds/README.md
                string readmePath = System.IO.Path.Combine(
                    System.IO.Path.GetDirectoryName(typeof(Program).Assembly.Location),
                    "sounds", "README.md");
                if (!System.IO.File.Exists(readmePath))
                {
                    PostToWeb("{\"type\":\"helpText\",\"text\":\"帮助文件未找到\"}");
                    return;
                }
                string text = System.IO.File.ReadAllText(readmePath, System.Text.Encoding.UTF8);
                // 转义为 JSON 字符串
                System.Text.StringBuilder sb = new System.Text.StringBuilder(text.Length + 64);
                sb.Append("{\"type\":\"helpText\",\"text\":\"");
                for (int i = 0; i < text.Length; i++)
                {
                    char c = text[i];
                    switch (c)
                    {
                        case '\\': sb.Append("\\\\"); break;
                        case '"': sb.Append("\\\""); break;
                        case '\n': sb.Append("\\n"); break;
                        case '\r': break; // skip
                        case '\t': sb.Append("\\t"); break;
                        default: sb.Append(c); break;
                    }
                }
                sb.Append("\"}");
                PostToWeb(sb.ToString());
            }
            catch (Exception ex)
            {
                LogManager.Log("[Jukebox] LoadHelp error: " + ex.Message);
            }
        }

        private void SendGameCommandWithData(string action, string extraFields)
        {
            if (_socketServer == null) return;
            _socketServer.Send("{\"task\":\"cmd\",\"action\":\"" + action + "\"," + extraFields + "}\0");
        }

        private static float ExtractFloat(string json, string key)
        {
            int idx = json.IndexOf(key);
            if (idx < 0) return 0f;
            idx += key.Length;
            int end = idx;
            while (end < json.Length && (char.IsDigit(json[end]) || json[end] == '.' || json[end] == '-'))
                end++;
            float val;
            if (float.TryParse(json.Substring(idx, end - idx),
                System.Globalization.NumberStyles.Float,
                System.Globalization.CultureInfo.InvariantCulture, out val))
                return val;
            return 0f;
        }

        private static string EscapeJsonString(string s)
        {
            if (s == null) return "";
            return s.Replace("\\", "\\\\").Replace("\"", "\\\"");
        }

        #endregion
    }
}
