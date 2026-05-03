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
using CF7Launcher.Guardian.Hud;
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

        [DllImport("user32.dll")]
        private static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);

        [DllImport("user32.dll")]
        private static extern int GetWindowLong(IntPtr hWnd, int nIndex);

        [DllImport("user32.dll")]
        private static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern IntPtr SetWindowsHookEx(int idHook, LowLevelMouseProc lpfn, IntPtr hMod, uint dwThreadId);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool UnhookWindowsHookEx(IntPtr hhk);

        [DllImport("user32.dll")]
        private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

        [DllImport("kernel32.dll", CharSet = CharSet.Auto)]
        private static extern IntPtr GetModuleHandle(string lpModuleName);

        [DllImport("user32.dll")]
        private static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll", SetLastError = true)]
        private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool IsChild(IntPtr hWndParent, IntPtr hWnd);

        private delegate IntPtr LowLevelMouseProc(int nCode, IntPtr wParam, IntPtr lParam);

        private static readonly uint _ourPid = (uint)System.Diagnostics.Process.GetCurrentProcess().Id;

        // Desktop cursor 的前台判定要覆盖两种同一游戏会话状态：
        // 1. Guardian/overlay/native cursor 等同进程窗口成为 foreground。
        // 2. 嵌入后的 Flash 子窗口仍短暂保留 foreground，PID 可能仍是 Flash 进程。
        // alt-tab 到外部程序时，PID 和 owner 子窗口树都会不匹配，cursor 应退场。
        private static bool IsDesktopCursorSessionForeground(IntPtr ownerHwnd)
        {
            IntPtr fg = GetForegroundWindow();
            if (fg == IntPtr.Zero) return false;
            uint pid;
            GetWindowThreadProcessId(fg, out pid);

            bool foregroundInOwnerTree = ownerHwnd != IntPtr.Zero
                && (fg == ownerHwnd || IsChild(ownerHwnd, fg));

            return IsDesktopCursorForegroundAccepted(pid, _ourPid, foregroundInOwnerTree);
        }

        internal static bool IsDesktopCursorForegroundAccepted(uint foregroundPid, uint ourPid, bool foregroundInOwnerTree)
        {
            if (foregroundPid != 0 && foregroundPid == ourPid)
                return true;

            return foregroundInOwnerTree;
        }

        internal static string ResolvePanelCloseGameCommand(string panel)
        {
            if (panel == "kshop") return "shopPanelClose";
            if (panel == "map") return "mapPanelClose";
            if (panel == "stage-select") return "stageSelectPanelClose";
            return null;
        }

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

        private const int SW_HIDE = 0;
        private const int SW_SHOWNA = 8;
        private const int SW_SHOWNOACTIVATE = 4;
        private static readonly IntPtr HWND_TOP = new IntPtr(0);
        private const uint SWP_NOMOVE = 0x0002;
        private const uint SWP_NOSIZE = 0x0001;
        private const uint SWP_NOACTIVATE = 0x0010;

        private const int WS_EX_TOOLWINDOW = 0x00000080;
        private const int WS_EX_NOACTIVATE = 0x08000000;
        private const int WS_EX_TRANSPARENT = 0x00000020;
        private const int WS_EX_LAYERED = 0x00080000;
        private const int GWL_EXSTYLE = -20;
        private const uint SWP_FRAMECHANGED = 0x0020;
        private const uint SWP_SHOWWINDOW = 0x0040;
        private const uint SWP_NOZORDER = 0x0004;
        private static readonly IntPtr HWND_NOTOPMOST = new IntPtr(-2);
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
        private static readonly System.Reflection.FieldInfo WebViewControllerField =
            typeof(WebView2).GetField("_coreWebView2Controller",
                System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic);
        private bool _webReady;
        private bool _shown;
        private bool _disposed;
        private bool _devMode;
        private readonly bool _lowEffectsMode;
        private readonly bool _disableCssAnimations;
        private readonly bool _disableVisualizers;
        private readonly int _frameRateLimit;
        private readonly bool _webView2DisableGpu;
        private readonly string _webView2AdditionalArgs;

        // GDI+ fallback：WebView2 未就绪或初始化失败时，消息转发到 GDI+ overlay
        private IToastSink _toastFallback;
        private INotchSink _notchFallback;
        private bool _webFailed; // 初始化永久失败，所有后续消息走 fallback
        // Phase 3: useNativeHud=true 时让 NotchOverlay/ToastOverlay 一直当常驻 HUD，不再调 SuspendFallback
        private volatile bool _useNativeHud;

        // IToastSink: 早期消息缓冲（WebView2 初始化前）
        private readonly List<string> _toastEarlyBuffer = new List<string>();
        private bool _toastReady;

        // UI 数据早期缓冲：WebView2 就绪前收到的状态数据，就绪后 flush
        private readonly List<string> _uiDataEarlyBuffer = new List<string>();
        // UI 数据最新值快照：按 type 去重，热重载后恢复完整状态
        private readonly Dictionary<string, string> _uiDataSnapshot = new Dictionary<string, string>();

        // InputShieldForm 引用（CDP 输入注入 + hitRects 转发）
        private InputShieldForm _inputShield;
        private INativeCursor _cursorOverlay;
        private bool _nativeHudIdleSuspendPending;
        private bool _webViewControllerReflectionWarned;
        private int _panelViewportRepairAttempts;

        // 面板系统
        private ShopTask _shopTask;
        private MapTask _mapTask;
        private StageSelectTask _stageSelectTask;
        private IntelligenceTask _intelligenceTask;
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

        // 探针：合成成本 toggle。Ctrl+G 切换 opaque WebView2 + 隐藏 Flash 子窗口，
        // 观察任务管理器 GPU 占用变化。结果决定是否推进"panel 态切 opaque + 隐 Flash"方案。
        private bool _compositionProbeActive;
        private Color _probeOriginalWebBackColor = Color.Transparent;

        // 字体包目录：cfn-fonts.local 虚拟主机优先映射 %LOCALAPPDATA%/CF7FlashNight/fonts/，
        // launcher/web/assets/fonts/ 作为 shipped fallback。SetFontsDir 由 Program.cs 在 FontPackTask 构造后注入。
        private string _fontsDirPrimary;
        private string _fontsDirFallback;

        // Web→C# 任务桥：JS 端 Bridge.send({type:'task', task:'font_pack', callId, payload}) 透传到 MessageRouter，
        // 异步响应通过 PostToWeb 回送，前端按 callId 匹配。
        private CF7Launcher.Bus.MessageRouter _taskRouter;

        public WebOverlayForm(Form owner, Control anchor, string webDir,
            bool lowEffectsMode, bool disableCssAnimations, bool disableVisualizers,
            int frameRateLimit,
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
            _frameRateLimit = NormalizeFrameRateLimit(frameRateLimit);
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
            ApplyHiddenWarmupBounds("ctor_warmup");

            // WebView2 控件
            _webView = new WebView2();
            _webView.Dock = DockStyle.Fill;
            this.Controls.Add(_webView);
            SyncWebViewViewportBounds(this.ClientSize.Width, this.ClientSize.Height, 1.0, "ctor_warmup", false);

            // Owner 跟随：Move/Resize → 同步位置
            owner.Move += delegate { ScheduleSyncPosition("owner_move"); };
            owner.Resize += delegate
            {
                ScheduleSyncPosition("owner_resize");
                // 从最小化恢复时重新显示（Win32 owned 窗口最小化时自动隐藏，
                // 但 ShowWindow(SW_SHOWNOACTIVATE) 创建的窗口可能不自动恢复）
                // 关键守卫：panel 态 / idle 冻结态不能重显——会把 SW_HIDE 的 WebView 拉回
                // 上次 panelRect 位置，导致 web HUD（#quest-row 等）漂浮在过时坐标。
                // Panel 态由 PanelHostController.ApplyOwnerLayoutChange 接管，全屏切换的真实
                // viewport 跟随走 FlashHostPanel.SizeChanged 路径。
                if (owner.WindowState != FormWindowState.Minimized && _shown && _webReady
                    && !_panelMode && !_frozenForIdle)
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

        /// <summary>
        /// 注入字体包目录（FontPackTask 构造后调用）。primary = %LOCALAPPDATA% 下载目录，
        /// fallback = launcher/web/assets/fonts/。两者都映射到 cfn-fonts.local 虚拟主机
        /// （WebView2 一个虚拟主机只能映射一个目录，所以靠 manifest 提供 sha + 双路径回退由
        /// FontPackTask 解析；此处只暴露 primary，shipped fallback 由 FontPackTask 复制兜底）。
        /// 如果 CoreWebView2 已就绪则立即建映射，否则 InitWebView2Async 末尾会补建。
        /// </summary>
        public void SetFontsDir(string primaryDir, string fallbackDir)
        {
            _fontsDirPrimary = primaryDir;
            _fontsDirFallback = fallbackDir;
            TryRegisterFontsVirtualHost("set_fonts_dir");
        }

        /// <summary>注入 MessageRouter，开放 Web→C# 通用 task 桥。</summary>
        public void SetTaskRouter(CF7Launcher.Bus.MessageRouter router)
        {
            _taskRouter = router;
        }

        private void TryRegisterFontsVirtualHost(string trigger)
        {
            try
            {
                if (_webView == null || _webView.CoreWebView2 == null) return;
                string dir = !string.IsNullOrEmpty(_fontsDirPrimary) && Directory.Exists(_fontsDirPrimary)
                    ? _fontsDirPrimary
                    : _fontsDirFallback;
                if (string.IsNullOrEmpty(dir) || !Directory.Exists(dir)) return;
                _webView.CoreWebView2.SetVirtualHostNameToFolderMapping(
                    "cfn-fonts.local", dir,
                    CoreWebView2HostResourceAccessKind.Allow);
                LogManager.Log("[WebOverlay] cfn-fonts.local → " + dir + " (" + trigger + ")");
            }
            catch (Exception ex)
            {
                LogManager.Log("[WebOverlay] cfn-fonts.local mapping failed (" + trigger + "): " + ex.Message);
            }
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
                SyncWebViewViewportBounds(this.ClientSize.Width, this.ClientSize.Height,
                    1.0, "core_ready_pre_nav", true);

                // 透明背景：WebView2 透明区域显示 Form BackColor (=TransparencyKey) → 视觉穿透
                _webView.DefaultBackgroundColor = Color.Transparent;

                // 虚拟主机映射：https://overlay.local/ → webDir/
                _webView.CoreWebView2.SetVirtualHostNameToFolderMapping(
                    "overlay.local", webDir,
                    CoreWebView2HostResourceAccessKind.Allow);

                // 字体包虚拟主机：https://cfn-fonts.local/ → %LOCALAPPDATA%/CF7FlashNight/fonts/（FontPackTask 注入）
                // 若 SetFontsDir 已先于 CoreWebView2 ready 调用，此处补建映射；反之 SetFontsDir 立即建。
                TryRegisterFontsVirtualHost("init_webview2");

                // JS→C# 消息
                _webView.CoreWebView2.WebMessageReceived += OnWebMessageReceived;
                await _webView.CoreWebView2.AddScriptToExecuteOnDocumentCreatedAsync(
                    "window.CF7_FRAME_RATE_LIMIT=" + _frameRateLimit.ToString(CultureInfo.InvariantCulture) + ";");

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
            // Phase 3: useNativeHud=true 时不挂起——让 NotchOverlay/ToastOverlay 一直作为常驻 HUD
            // panel 打开/关闭由 PanelHostController 显式 Suspend/Resume
            if (_useNativeHud)
            {
                LogManager.Log("[WebOverlay] SuspendFallback skipped (useNativeHud active; companions stay live)");
                return;
            }
            var notch = _notchFallback as NotchOverlay;
            if (notch != null) notch.Suspend();
            var toast = _toastFallback as ToastOverlay;
            if (toast != null) toast.Suspend();
        }

        /// <summary>Phase 3: 由 Program.cs 在 useNativeHud=true 时调用。</summary>
        public void SetUseNativeHud(bool active)
        {
            _useNativeHud = active;
        }

        /// <summary>useNativeHud 模式下隐藏 web 端 #notch / #toast-container DOM，避免与 NotchOverlay/ToastOverlay 重叠。</summary>
        private void HideWebHudDomForNativeHud()
        {
            if (!_useNativeHud) return;
            // 注入 CSS 让 #notch、#toast-container 隐藏；保留其他 web UI（cursor 反馈、tooltip、panel 容器等）
            // 用 CSS 而不删 DOM，便于切回 useNativeHud=false 时不需重建
            const string css =
                "(function(){var s=document.getElementById('cf7-native-hud-css');if(s)return;" +
                "s=document.createElement('style');s.id='cf7-native-hud-css';" +
                "s.textContent='#notch,#toast-container,#top-right-tools,#safe-exit-panel,#quest-notice-bar,#combo-status,#jukebox-panel,#map-hud,#context-panel{display:none!important;}';" +
                // 注：currency-gold/kpoint 与 notch-toolbar 当前都在 #notch 内，
                // 隐藏 #notch 已自动隐藏；C# NotchOverlay 接管刘海栏货币、FPS、row1-right 与 hover toolbar。
                // #quest-notice-bar 由 C# RightContextWidget 接管 td/tdh/tdn/mm 持久态 + task/announce 一次性事件。
                // #combo-status 由 C# ComboWidget 接管 combo|... 输入态 + N combo|... 命中态。
                // #jukebox-panel 折叠标题栏由 C# RightContextWidget 接管；展开 panel 走 JUKEBOX_EXPAND -> PanelHost。
                "document.head.appendChild(s);})();";
            try { ExecScript(css); }
            catch (Exception ex) { LogManager.Log("[WebOverlay] HideWebHudDomForNativeHud failed: " + ex.Message); }
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

        private Rectangle GetHiddenWarmupScreenRect()
        {
            try
            {
                if (_owner != null && !_owner.IsDisposed)
                {
                    Size ownerSize = _owner.ClientSize;
                    if (ownerSize.Width >= 320 && ownerSize.Height >= 180)
                    {
                        Point ownerOrigin = _owner.PointToScreen(Point.Empty);
                        return new Rectangle(ownerOrigin, ownerSize);
                    }
                }
            }
            catch { }

            try
            {
                if (_anchor != null && !_anchor.IsDisposed)
                {
                    Size anchorSize = _anchor.Size;
                    if (anchorSize.Width >= 320 && anchorSize.Height >= 180)
                    {
                        Point anchorOrigin = _anchor.PointToScreen(Point.Empty);
                        return new Rectangle(anchorOrigin, anchorSize);
                    }
                }
            }
            catch { }

            try
            {
                Control screenControl = _owner as Control;
                if (screenControl == null) screenControl = _anchor;
                Rectangle screen = Screen.FromControl(screenControl).Bounds;
                int width = Math.Max(320, Math.Min(1600, screen.Width));
                int height = Math.Max(180, Math.Min(900, screen.Height));
                return new Rectangle(screen.X, screen.Y, width, height);
            }
            catch
            {
                return new Rectangle(0, 0, 1600, 900);
            }
        }

        private void ApplyHiddenWarmupBounds(string reason)
        {
            Rectangle rect = GetHiddenWarmupScreenRect();
            try
            {
                this.Bounds = rect;
                this.ClientSize = new Size(rect.Width, rect.Height);
                SetWindowPos(this.Handle, HWND_TOP, rect.X, rect.Y, rect.Width, rect.Height,
                    SWP_NOACTIVATE | SWP_NOZORDER);
                _coordinateContext.UpdateOverlay(rect, 0, 0, rect.Width, rect.Height,
                    this.Handle, 1.0, reason);
                SyncWebViewViewportBounds(rect.Width, rect.Height, 1.0, reason, true);
                LogManager.Log("[WebOverlay] hidden warmup bounds applied: reason=" + reason
                    + " form=" + this.Bounds
                    + " client=" + this.ClientSize.Width + "x" + this.ClientSize.Height);
            }
            catch (Exception ex)
            {
                LogManager.Log("[WebOverlay] hidden warmup bounds failed: " + ex.Message);
            }
        }

        private CoreWebView2Controller TryGetWebViewController()
        {
            if (_webView == null)
                return null;
            try
            {
                if (WebViewControllerField == null)
                {
                    if (!_webViewControllerReflectionWarned)
                    {
                        _webViewControllerReflectionWarned = true;
                        LogManager.Log("[WebOverlay] WebView2 controller field unavailable; falling back to WinForms bounds only");
                    }
                    return null;
                }
                return WebViewControllerField.GetValue(_webView) as CoreWebView2Controller;
            }
            catch (Exception ex)
            {
                if (!_webViewControllerReflectionWarned)
                {
                    _webViewControllerReflectionWarned = true;
                    LogManager.Log("[WebOverlay] WebView2 controller reflection failed: " + ex.Message);
                }
                return null;
            }
        }

        private string DescribeWebViewController()
        {
            CoreWebView2Controller controller = TryGetWebViewController();
            if (controller == null)
                return "controller=<null>";
            try
            {
                return "controller=" + controller.Bounds
                    + " zoom=" + controller.ZoomFactor.ToString("0.###", CultureInfo.InvariantCulture)
                    + " raster=" + controller.RasterizationScale.ToString("0.###", CultureInfo.InvariantCulture)
                    + " mode=" + controller.BoundsMode
                    + " visible=" + controller.IsVisible;
            }
            catch (Exception ex)
            {
                return "controller=<error:" + ex.Message + ">";
            }
        }

        private void SyncWebViewViewportBounds(int width, int height, double zoom, string reason, bool forceLog)
        {
            if (_webView == null)
                return;

            int w = Math.Max(1, width);
            int h = Math.Max(1, height);
            if (double.IsNaN(zoom) || double.IsInfinity(zoom) || zoom <= 0)
                zoom = 1.0;

            Rectangle localBounds = new Rectangle(0, 0, w, h);
            try
            {
                _webView.Dock = DockStyle.None;
                _webView.Location = Point.Empty;
                _webView.Size = new Size(w, h);
                _webView.Bounds = localBounds;
                _webView.Dock = DockStyle.Fill;
                if (_webView.CoreWebView2 != null && Math.Abs(_webView.ZoomFactor - zoom) > 0.001)
                    _webView.ZoomFactor = zoom;
                if (_webView.IsHandleCreated)
                {
                    MoveWindow(_webView.Handle, 0, 0, w, h, true);
                    SetWindowPos(_webView.Handle, IntPtr.Zero, 0, 0, w, h,
                        SWP_NOACTIVATE | SWP_NOZORDER);
                }
            }
            catch (Exception ex)
            {
                LogManager.Log("[WebOverlay] WebView2 WinForms bounds sync failed: reason="
                    + reason + " error=" + ex.Message);
            }

            CoreWebView2Controller controller = TryGetWebViewController();
            if (controller == null)
                return;
            try
            {
                controller.BoundsMode = CoreWebView2BoundsMode.UseRawPixels;
                controller.SetBoundsAndZoomFactor(localBounds, zoom);
                controller.NotifyParentWindowPositionChanged();
                PerfTrace.Counter("webOverlay.controllerBoundsSync");
                if (_panelMode)
                    controller.IsVisible = true;
                if (forceLog || IsPanelMetricsReason(reason))
                    LogManager.Log("[WebOverlay] controller bounds sync: reason=" + reason
                        + " bounds=" + localBounds
                        + " zoom=" + zoom.ToString("0.###", CultureInfo.InvariantCulture)
                        + " " + DescribeWebViewController());
            }
            catch (Exception ex)
            {
                LogManager.Log("[WebOverlay] WebView2 controller bounds sync failed: reason="
                    + reason + " error=" + ex.Message);
            }
        }

        private void SyncPosition(string reason)
        {
            // Phase 2 panel-mode/idle 不变量：
            // - panel 态：窗口位置/大小由 PanelHostController 锁定为 panelRect，禁止 owner-resize 拉回 anchor
            // - idle 态：窗口已 SW_HIDE+suspend，任何 SetWindowPos/ExecScript 都可能唤醒 WebView2，破坏 DWM α traversal 撤除
            if (_panelMode || _frozenForIdle) return;
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
                {
                    if (CursorDiagEnabled)
                        LogManager.Log("[Cursor] callsite=UpdateOverlay reason=" + (reason ?? "")
                            + " vpW=" + vpW + " vpH=" + vpH + " physBoundsH=" + h
                            + " ctxFlashVpH=" + _coordinateContext.FlashViewportHeight
                            + " ctxViewportScale=" + _coordinateContext.ViewportScale.ToString("0.###", System.Globalization.CultureInfo.InvariantCulture));
                    _cursorOverlay.SetScale(_coordinateContext.ViewportScale, _coordinateContext.WindowDpiX, _coordinateContext.WindowDpiY);
                }

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
                if (_webReady)
                    SyncWebViewViewportBounds(w, h, newWebViewZoom, reason, false);

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
            string frameRateLimit = _frameRateLimit.ToString(CultureInfo.InvariantCulture);
            string frameRateCapped = _frameRateLimit > 0 ? "true" : "false";
            ExecScript("document.documentElement.classList.toggle('perf-low-effects'," + lowEffects + ");"
                + "document.documentElement.classList.toggle('perf-no-css-animations'," + noCssAnimations + ");"
                + "document.documentElement.classList.toggle('perf-frame-capped'," + frameRateCapped + ");"
                + "document.documentElement.classList.toggle('perf-no-visualizers'," + noVisualizers + ");"
                + "window.CF7_LOW_EFFECTS=" + lowEffects + ";"
                + "window.CF7_DISABLE_CSS_ANIMATIONS=" + noCssAnimations + ";"
                + "window.CF7_DISABLE_VISUALIZERS=" + noVisualizers + ";"
                + "window.CF7_FRAME_RATE_LIMIT=" + frameRateLimit + ";"
                + "document.documentElement.style.setProperty('--overlay-frame-rate-limit','" + frameRateLimit + "');"
                + "if(window.CF7FrameLimiter&&window.CF7FrameLimiter.setLimit){window.CF7FrameLimiter.setLimit(" + frameRateLimit + ");}");
            if (_lowEffectsMode || _disableCssAnimations || _disableVisualizers || _frameRateLimit > 0)
                LogManager.Log("[WebOverlay] perf mode applied: " + reason
                    + " lowEffects=" + _lowEffectsMode
                    + " noCssAnimations=" + _disableCssAnimations
                    + " noVisualizers=" + _disableVisualizers
                    + " frameRateLimit=" + _frameRateLimit);
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
                else if (type == "task")
                {
                    // 通用 Web→C# task 桥：把 message 透传给 MessageRouter，异步响应回 PostToWeb。
                    // JS 端格式：{ type:'task', task:'font_pack', callId, payload:{op,...} }
                    // C# 响应回到 JS：{ type:'taskResult', task, callId, ...原响应 }
                    HandleWebTaskMessage(parsed, json);
                }
                else if (type == "panel")
                {
                    // 先匹配 type=="panel"——避免下面 jukebox 子串 fallback 把含 "panel":"jukebox" 字段的
                    // panel-close 消息错路由进 HandleJukeboxMessage。
                    HandlePanelMessage(json);
                }
                else if (type == "jukebox" || json.Contains("\"jukebox\""))
                {
                    HandleJukeboxMessage(json);
                }
                else if (json.Contains("\"panel\""))
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

                    // flush 早期缓冲；native HUD idle 下不把消息推给隐藏 Web HUD
                    if (_toastReady && !_useNativeHud)
                        FlushToastBuffer();
                    if (!_useNativeHud || _panelMode)
                        FlushUiDataBuffer();

                    // 显示 overlay（如果 SetReady 已先调用）
                    if (_shown && (!_useNativeHud || _panelMode))
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
                        if (_useNativeHud && !_shown && !_panelMode)
                            ApplyHiddenWarmupBounds("ready_hidden_native");
                        else
                            SyncPosition("ready_hidden");
                        if (_shown && _cursorOverlay != null)
                            _cursorOverlay.SetReady();
                    }

                    // 非开发环境：隐藏"其他"菜单中的开发工具
                    if (!_devMode)
                        ExecScript("document.getElementById('notch').classList.add('hide-other')");

                    // 一次性推送光照等级静态数据
                    if (!_useNativeHud || _panelMode)
                        PushLightLevels();

                    // 推送音乐目录到 WebView
                    if (_musicCatalog != null && (!_useNativeHud || _panelMode))
                        PostToWeb(_musicCatalog.GetFullCatalogJson());

                    // Web 通道恢复：useNativeHud=true 时让 NotchOverlay/ToastOverlay 一直显示作为常驻 HUD；
                    // 否则挂起 GDI+ fallback 避免双重 UI
                    if (_useNativeHud)
                    {
                        // 让 NotchOverlay/ToastOverlay 显示（与 ActivateFallback 等价但语义清晰）
                        ActivateFallback();
                        // 隐藏 web 端 #notch / #toast-container DOM 避免视觉重叠
                        HideWebHudDomForNativeHud();
                        EnsureCursorTimer();
                        ScheduleNativeHudIdleSuspend("web_ready");
                    }
                    else
                    {
                        SuspendFallback();
                        RequestViewportMetrics("ready");
                        ExecScript("if(window.Notch&&Notch.reportRect){Notch.reportRect();}");
                        EnsureCursorTimer();
                    }
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
            string reason = parsed.Value<string>("reason") ?? "web_metrics";
            double innerWidth = ReadDouble(parsed, "innerWidth");
            double innerHeight = ReadDouble(parsed, "innerHeight");
            double clientWidth = ReadDouble(parsed, "clientWidth");
            double clientHeight = ReadDouble(parsed, "clientHeight");
            double devicePixelRatio = ReadDouble(parsed, "devicePixelRatio");
            double visualViewportWidth = ReadDouble(parsed, "visualViewportWidth");
            double visualViewportHeight = ReadDouble(parsed, "visualViewportHeight");

            _coordinateContext.UpdateWebMetrics(
                innerWidth,
                innerHeight,
                clientWidth,
                clientHeight,
                devicePixelRatio,
                visualViewportWidth,
                visualViewportHeight,
                reason);

            _missingMetricsWarned = false;
            if (_inputShield != null)
            {
                _inputShield.SetCoordinateContext(_coordinateContext);
                _inputShield.RequestPositionSync();
            }
            if (_cursorOverlay != null)
            {
                if (CursorDiagEnabled)
                    LogManager.Log("[Cursor] callsite=UpdateWebMetrics reason=" + (reason ?? "")
                        + " ctxFlashVpH=" + _coordinateContext.FlashViewportHeight
                        + " ctxPhysicalBoundsH=" + _coordinateContext.OverlayPhysicalBounds.Height
                        + " ctxViewportScale=" + _coordinateContext.ViewportScale.ToString("0.###", System.Globalization.CultureInfo.InvariantCulture));
                _cursorOverlay.SetScale(_coordinateContext.ViewportScale, _coordinateContext.WindowDpiX, _coordinateContext.WindowDpiY);
            }

            bool panelMetrics = IsPanelMetricsReason(reason);
            if (panelMetrics)
            {
                LogManager.Log("[Panel] viewport raw: reason=" + reason
                    + " inner=" + innerWidth.ToString("0.##", CultureInfo.InvariantCulture)
                    + "x" + innerHeight.ToString("0.##", CultureInfo.InvariantCulture)
                    + " client=" + clientWidth.ToString("0.##", CultureInfo.InvariantCulture)
                    + "x" + clientHeight.ToString("0.##", CultureInfo.InvariantCulture)
                    + " visual=" + visualViewportWidth.ToString("0.##", CultureInfo.InvariantCulture)
                    + "x" + visualViewportHeight.ToString("0.##", CultureInfo.InvariantCulture)
                    + " dpr=" + devicePixelRatio.ToString("0.###", CultureInfo.InvariantCulture)
                    + " web=" + (_webView != null ? _webView.Bounds.ToString() : "<null>")
                    + " zoom=" + (_webView != null ? _webView.ZoomFactor.ToString("0.###", CultureInfo.InvariantCulture) : "<null>")
                    + " " + DescribeWebViewController());
            }

            if (ShouldLogOverlayContext(false) || panelMetrics)
                DpiDiagnostics.LogOverlayContext("WebOverlay.viewportMetrics", _coordinateContext);
            if (ShouldRepairPanelViewport(reason))
                SchedulePanelViewportRepair(reason);
            ForceCursorSample("metrics:" + reason);
        }

        private bool ShouldRepairPanelViewport(string reason)
        {
            if (!_panelMode || _disposed || _webView == null)
                return false;
            if (_panelViewportRepairAttempts >= 3)
                return false;
            if (_coordinateContext.OverlayPhysicalBounds.Width < 800 ||
                _coordinateContext.OverlayPhysicalBounds.Height < 450)
                return false;
            if (_coordinateContext.WebCssWidth <= 0 || _coordinateContext.WebCssHeight <= 0)
                return false;
            if (_coordinateContext.WebCssWidth < 400 || _coordinateContext.WebCssHeight < 225)
                return true;
            if (IsPanelMetricsReason(reason) &&
                (_coordinateContext.CssToPhysicalX > 4.0 || _coordinateContext.CssToPhysicalY > 4.0))
                return true;
            return false;
        }

        private void SchedulePanelViewportRepair(string reason)
        {
            PerfTrace.Counter("webOverlay.panelViewportRepair");
            _panelViewportRepairAttempts++;
            int attempt = _panelViewportRepairAttempts;
            try
            {
                BeginInvoke(new Action(delegate()
                {
                    if (_disposed || !_panelMode || _webView == null)
                        return;
                    SyncWebViewViewportBounds(this.ClientSize.Width, this.ClientSize.Height,
                        1.0, "panel_viewport_repair:" + reason + ":" + attempt, true);
                    try
                    {
                        ExecScript("window.dispatchEvent(new Event('resize'));"
                            + "if(window.OverlayViewportMetrics&&window.OverlayViewportMetrics.report){"
                            + "window.OverlayViewportMetrics.report('panel_viewport_repair');}");
                    }
                    catch (Exception ex) { LogManager.Log("[Panel] viewport repair metrics request failed: " + ex.Message); }
                }));
            }
            catch (Exception ex)
            {
                LogManager.Log("[Panel] viewport repair schedule failed: " + ex.Message);
            }
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
                    + " frameRateLimit=" + _frameRateLimit
                    + " disableGpu=false");
                return null;
            }

            string joined = string.Join(" ", args.ToArray());
            LogManager.Log("[WebOverlay] WebView2 perf options: lowEffects="
                + _lowEffectsMode
                + " noCssAnimations=" + _disableCssAnimations
                + " noVisualizers=" + _disableVisualizers
                + " frameRateLimit=" + _frameRateLimit
                + " disableGpu=" + _webView2DisableGpu
                + " args=" + joined);

            CoreWebView2EnvironmentOptions options = new CoreWebView2EnvironmentOptions();
            options.AdditionalBrowserArguments = joined;
            return options;
        }

        private static int NormalizeFrameRateLimit(int value)
        {
            if (value <= 0) return 0;
            if (value < 15) return 15;
            if (value > 240) return 240;
            return value;
        }

        public void SetCursorOverlay(INativeCursor cursorOverlay)
        {
            _cursorOverlay = cursorOverlay;
            if (_cursorOverlay != null)
            {
                _nativeCursorMissingLogged = false;
                if (CursorDiagEnabled)
                    LogManager.Log("[Cursor] callsite=SetCursorOverlay ctxFlashVpH=" + _coordinateContext.FlashViewportHeight
                        + " ctxViewportScale=" + _coordinateContext.ViewportScale.ToString("0.###", System.Globalization.CultureInfo.InvariantCulture));
                _cursorOverlay.SetScale(_coordinateContext.ViewportScale, _coordinateContext.WindowDpiX, _coordinateContext.WindowDpiY);
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

        private static bool IsPanelMetricsReason(string reason)
        {
            return !string.IsNullOrEmpty(reason)
                && reason.IndexOf("panel", StringComparison.OrdinalIgnoreCase) >= 0;
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
            if (_disposed) return;
            if (this.IsHandleCreated && this.InvokeRequired)
            {
                try { this.BeginInvoke(new Action<string>(PostToWebCore), json); }
                catch { }
                return;
            }
            PostToWebCore(json);
        }

        private void PostToWebCore(string json)
        {
            if (!_webReady || _disposed || _webView == null || _webView.CoreWebView2 == null) return;
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

        private bool CursorUsesDesktopCoordinates()
        {
            return _cursorOverlay != null && _cursorOverlay.UsesDesktopCoordinates;
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
            if (_frozenForIdle) return; // idle 态不重新 start，避免 unsuspend WebView2
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

            bool desktopCursor = CursorUsesDesktopCoordinates();
            Rectangle bounds = _coordinateContext.OverlayPhysicalBounds;
            if (bounds.Width <= 0 || bounds.Height <= 0)
                bounds = this.Bounds;

            bool inside = bounds.Contains(screenX, screenY);
            if (!desktopCursor && !inside && !_cursorLastVisible)
                return;

            long now = Environment.TickCount;
            int minInterval = 8;
            if ((desktopCursor || inside) && now - _lastCursorHookPostTick >= 0 && now - _lastCursorHookPostTick < minInterval)
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
            if (CursorUsesDesktopCoordinates())
            {
                UpdateCursorFromScreenPoint(screen, "hook");
                return;
            }

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
            if (CursorUsesDesktopCoordinates())
            {
                SendDesktopCursorPosition(screen, "send", force);
                return;
            }

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

            bool wasVisible = _cursorLastVisible;
            _cursorLastVisible = true;
            HideSystemCursor();
            _cursorLastX = css.X;
            _cursorLastY = css.Y;
            _cursorLastScreenX = screen.X;
            _cursorLastScreenY = screen.Y;

            if (_cursorOverlay != null)
            {
                if (!wasVisible)
                    _cursorOverlay.SetCursorVisible(true);
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
            if (CursorUsesDesktopCoordinates())
            {
                SendDesktopCursorPosition(screen, kind, false);
                return;
            }

            Point css = _coordinateContext.PhysicalPointToCss(px, py);

            bool wasVisible = _cursorLastVisible;
            _cursorLastVisible = true;
            HideSystemCursor();
            _cursorLastX = css.X;
            _cursorLastY = css.Y;
            _cursorLastScreenX = screen.X;
            _cursorLastScreenY = screen.Y;

            if (_cursorOverlay != null)
            {
                if (!wasVisible)
                    _cursorOverlay.SetCursorVisible(true);
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

            if (CursorUsesDesktopCoordinates())
            {
                SendDesktopCursorPosition(screen, kind, true);
                return;
            }

            Rectangle bounds = _coordinateContext.OverlayPhysicalBounds;
            if (bounds.Width <= 0 || bounds.Height <= 0)
                bounds = this.Bounds;
            if (!bounds.Contains(screen))
                return;

            UpdateCursorFromOverlayPoint(screen.X - bounds.Left, screen.Y - bounds.Top, kind);
        }

        private void SendDesktopCursorPosition(Point screen, string kind, bool force)
        {
            if (_cursorOverlay == null)
            {
                RestoreSystemCursorForMissingNativeOverlay();
                return;
            }

            // Desktop cursor 不再受 anchor bounds 裁剪，但仍必须随主窗口生命周期。
            // WH_MOUSE_LL 是全局 hook，alt-tab 到资源管理器/记事本后仍在跑，不挡住会让 topmost
            // 自定义光标在桌面跟着玩家鼠标到处跑。
            // 三道守卫：
            //   - _owner null / !Visible / Minimized：常规生命周期门
            //   - foreground 既非 launcher 进程，也不在 owner 子窗口树内 = 用户切走了 → cursor 退场
            //     （嵌入 Flash HWND 曾成为 foreground 时，owner 子窗口树才是更准确的会话边界）
            if (_owner == null || !_owner.Visible
                || _owner.WindowState == FormWindowState.Minimized)
            {
                if (_cursorLastVisible)
                    PostCursorVisibility(false);
                return;
            }

            IntPtr ownerHwnd = _owner.IsHandleCreated ? _owner.Handle : IntPtr.Zero;
            if (!IsDesktopCursorSessionForeground(ownerHwnd))
            {
                if (_cursorLastVisible)
                    PostCursorVisibility(false);
                return;
            }

            if (!force && _cursorLastVisible
                && screen.X == _cursorLastScreenX && screen.Y == _cursorLastScreenY)
                return;

            bool wasVisible = _cursorLastVisible;
            _cursorLastVisible = true;
            _cursorLastX = Int32.MinValue;
            _cursorLastY = Int32.MinValue;
            _cursorLastScreenX = screen.X;
            _cursorLastScreenY = screen.Y;

            if (!wasVisible)
                _cursorOverlay.SetCursorVisible(true);
            _cursorOverlay.UpdateCursorPosition(screen);

            Rectangle bounds = _coordinateContext.OverlayPhysicalBounds;
            if (bounds.Width <= 0 || bounds.Height <= 0)
                bounds = this.Bounds;
            LogCursorSample(kind, screen, bounds,
                new Point(Int32.MinValue, Int32.MinValue),
                new Point(Int32.MinValue, Int32.MinValue), true, force);
            EnsureCursorTimer();
        }

        private void PostCursorVisibility(bool visible)
        {
            bool desktopCursor = CursorUsesDesktopCoordinates();
            if (_cursorLastVisible == visible && !(desktopCursor && !visible)) return;
            _cursorLastVisible = visible;
            _cursorLastX = Int32.MinValue;
            _cursorLastY = Int32.MinValue;
            _cursorLastScreenX = Int32.MinValue;
            _cursorLastScreenY = Int32.MinValue;
            if (!desktopCursor)
            {
                if (visible) HideSystemCursor();
                else ShowSystemCursor();
            }
            if (_cursorOverlay != null)
            {
                _cursorOverlay.SetCursorVisible(visible);
            }
            else
            {
                RestoreSystemCursorForMissingNativeOverlay();
            }
            if (CursorDiagEnabled)
            {
                LogManager.Log("[Cursor] visible=" + visible
                    + " state=" + _cursorState
                    + " dragging=" + _cursorDragging
                    + " reason=" + _cursorDiagReason);
            }
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

        // Cursor 采样日志默认关闭，避免污染调试。需要时把 CursorDiagEnabled 临时改 true。
        private static readonly bool CursorDiagEnabled = false;

        private void LogCursorSample(string kind, Point screen, Rectangle bounds, Point local,
            Point css, bool visible, bool force)
        {
            if (!CursorDiagEnabled) { _cursorDiagForce = false; return; }

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
            if (CursorUsesDesktopCoordinates())
            {
                ShowSystemCursor();
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
                if (_webReady && (!_useNativeHud || _panelMode)) PostToWeb(updateJson);
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
            if (_frozenForIdle) return;
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
            if (_frozenForIdle) return;
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

        /// <summary>
        /// JukeboxTitlebarWidget 暂停按钮入口：翻转 _bgmPaused 镜像（HandleAudioTrackState 用它抑制 jukeboxTrackEnd）
        /// 并直接调 AudioEngine pause/resume。返回最新 paused 状态。
        ///
        /// 与 HandleJukeboxMessage 的 "pause"/"resume" 分支等价（两条入口共享同一权威源）。
        /// </summary>
        public bool ToggleBgmPause()
        {
            if (_bgmPaused)
            {
                _bgmPaused = false;
                try { Audio.AudioEngine.ma_bridge_bgm_resume(); }
                catch (Exception ex) { LogManager.Log("[Jukebox] ToggleBgmPause resume failed: " + ex.Message); }
            }
            else
            {
                _bgmPaused = true;
                try { Audio.AudioEngine.ma_bridge_bgm_pause(); }
                catch (Exception ex) { LogManager.Log("[Jukebox] ToggleBgmPause pause failed: " + ex.Message); }
            }
            return _bgmPaused;
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
            HandleUiData(new CF7Launcher.Guardian.Hud.UiDataPacket(payload));
        }

        /// <summary>
        /// P1 perf：tee 路径已解析的 packet 入口；webOverlay / notchOverlay / nativeHud 三方共享同一份 Pairs。
        /// 与 string 入口语义等价（snapshot 更新 + ExecScript / buffer），仅省一次 Split('|')。
        /// </summary>
        public void HandleUiData(CF7Launcher.Guardian.Hud.UiDataPacket pkt)
        {
            if (pkt == null) return;
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action<CF7Launcher.Guardian.Hud.UiDataPacket>(HandleUiData), pkt);
                return;
            }
            if (_disposed) return;

            // 维护最新值快照：payload 是 "key:val|key:val|..." 合批 KV 格式
            string[] pairs = pkt.Pairs;
            for (int i = 0; i < pairs.Length; i++)
            {
                if (pairs[i] == null) continue;
                int colon = pairs[i].IndexOf(':');
                if (colon > 0)
                    _uiDataSnapshot[pairs[i].Substring(0, colon)] = pairs[i];
                // 无冒号的段（旧格式）不进快照，由 buffer 兜底
            }

            bool nativeHudIdle = _useNativeHud && !_panelMode;
            if (_webFailed || !_webReady || _frozenForIdle || nativeHudIdle)
            {
                // WebView2 未就绪/降级/native idle SW_HIDE+suspend：仅维护快照，不 ExecScript
                if (_uiDataEarlyBuffer.Count < 200)
                    _uiDataEarlyBuffer.Add(pkt.Raw);
                return;
            }
            string escaped = pkt.Raw.Replace("\\", "\\\\").Replace("'", "\\'");
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
            // useNativeHud=true 时始终走 NotchOverlay（web 端 #notch DOM 已隐藏）
            if (_useNativeHud || _webFailed || !_webReady || _disposed) { if (_notchFallback != null) _notchFallback.AddNotice(category, text, accentColor); return; }
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
            if (_useNativeHud || _webFailed || !_webReady || _disposed) { if (_notchFallback != null) _notchFallback.SetStatusItem(id, label, subLabel, accentColor); return; }
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
            if (_useNativeHud || _webFailed || !_webReady || _disposed) { if (_notchFallback != null) _notchFallback.ClearStatusItem(id); return; }
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
            // useNativeHud=true 或 WebView2 失败 → 永久走 GDI+ fallback（ToastOverlay）
            if (_useNativeHud || _webFailed)
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
            if (_useNativeHud)
            {
                PerfTrace.Mark("webOverlay.set_ready_native");
                ActivateFallback();
                if (_cursorOverlay != null)
                    _cursorOverlay.SetReady();
                if (_webReady)
                {
                    HideWebHudDomForNativeHud();
                    EnsureCursorTimer();
                    ScheduleNativeHudIdleSuspend("set_ready");
                }
                return;
            }
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

        /// <summary>
        /// 探针：toggle 合成成本快路径。
        /// ON: WebView2 背景切 opaque（消除逐像素 alpha blend）+ 隐藏 Flash hwnd（底层不出图）
        /// OFF: 恢复 transparent + 显示 Flash。
        /// 对比 toggle 前后任务管理器 iGPU 占用，验证"panel 态切 opaque"是否值得推进。
        /// </summary>
        public void ToggleCompositionProbe(IntPtr flashHwnd)
        {
            if (InvokeRequired)
            {
                try { BeginInvoke(new Action<IntPtr>(ToggleCompositionProbe), flashHwnd); }
                catch { }
                return;
            }

            if (_disposed || _webView == null) return;

            long tick = Environment.TickCount;
            bool nextActive = !_compositionProbeActive;

            try
            {
                if (nextActive)
                {
                    _probeOriginalWebBackColor = _webView.DefaultBackgroundColor;
                    _webView.DefaultBackgroundColor = Color.Black;
                    if (flashHwnd != IntPtr.Zero)
                        ShowWindow(flashHwnd, SW_HIDE);
                    LogManager.Log("[GpuProbe] ON  tick=" + tick
                        + " flashHwnd=" + flashHwnd.ToInt64().ToString("X")
                        + " (WebView2 opaque + Flash hidden)");
                }
                else
                {
                    _webView.DefaultBackgroundColor = _probeOriginalWebBackColor;
                    if (flashHwnd != IntPtr.Zero)
                        ShowWindow(flashHwnd, SW_SHOWNA);
                    LogManager.Log("[GpuProbe] OFF tick=" + tick
                        + " flashHwnd=" + flashHwnd.ToInt64().ToString("X")
                        + " (restored transparent + Flash visible)");
                }
                _compositionProbeActive = nextActive;
            }
            catch (Exception ex)
            {
                LogManager.Log("[GpuProbe] toggle threw: " + ex.Message);
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

        public void SetStageSelectTask(StageSelectTask task)
        {
            _stageSelectTask = task;
            task.SetPostToWeb(PostToWeb);
            task.SetInvoker(delegate(Action a) { try { this.BeginInvoke(a); } catch {} });
        }

        public void SetIntelligenceTask(IntelligenceTask task)
        {
            _intelligenceTask = task;
            task.SetPostToWeb(PostToWeb);
            task.SetInvoker(delegate(Action a) { try { this.BeginInvoke(a); } catch {} });
        }

        public void SetPanelStateCallback(Action<bool> cb) { _onPanelStateChanged = cb; }

        #region PanelHost 集成（Phase 2 应急版）
        // ⚠️ 设计修正（2026-04-26）：原计划"panel 关闭后 SW_HIDE+TrySuspend WebView2"假设 NativeHud
        // 能接管 HUD 渲染，但 Phase 3 NotchWidget 还没上线。实测 panel 关闭后 web 端 UI 全消失
        // （cursor / close 按钮 / notch 浮层 / 触发 panel 的按钮）→ 系统不可用 + TrySuspendAsync 失败
        // 时 WebView2 后台继续跑 → 核显满载。
        //
        // 应急方案：
        // - 不变量（panel 态）：WebView 在 panelRect、opaque、direct-hit（去 LAYERED+TRANSPARENT）
        // - 不变量（idle 态）：WebView 回到 anchor、transparent、click-through（同 Phase 0 行为）
        //   * 不 SW_HIDE、不冻结 timer、不 TrySuspendAsync —— Web HUD 完整可见
        //   * Phase 2 收益：仅 panel 打开期 α blend 成本下降（panelRect 小 + opaque）
        //   * 完整 idle SW_HIDE 留给 Phase 3+：NotchWidget 等 widget 上线接管 HUD 后再做
        // Native HUD idle 会在 panel 关闭或启动 ready 后 SW_HIDE/suspend WebView2。
        // _frozenForIdle 负责拦截 UIData JS dispatch、timer 与位置同步，ResumeForPanel 再解冻。

        private PanelHostController _panelHost;
        private volatile bool _panelMode;
        private volatile bool _frozenForIdle;

        public bool IsPanelMode { get { return _panelMode; } }

        /// <summary>二阶段注入：Program.cs 先 new WebOverlayForm，再 new PanelHostController(this,...)，最后调本方法回注。</summary>
        public void SetPanelHost(PanelHostController host)
        {
            _panelHost = host;
        }

        /// <summary>
        /// idle → panel 切换。
        /// Step：解冻 → ResumeWebTimers → 去 EX_LAYERED+TRANSPARENT → TransparencyKey/Empty → opaque BG →
        ///       SetWindowPos HWND_TOP+SWP_FRAMECHANGED → PostToWeb panel_viewport_set → flush snapshot
        /// 注：用 HWND_TOP 而非 backdropHwnd（MSDN: hWndInsertAfter 是 "precede"，反而把 web 放到 backdrop 之下）。
        /// </summary>
        public void ResumeForPanel(Rectangle panelRectScreen)
        {
            if (_disposed) return;
            PerfTrace.Mark("webOverlay.panel_resume",
                panelRectScreen.Width + "x" + panelRectScreen.Height);
            _panelMode = true;
            _frozenForIdle = false;
            _nativeHudIdleSuspendPending = false;
            _panelViewportRepairAttempts = 0;

            ResumeWebTimers();

            // 唤醒 CoreWebView2（如果之前 DoFullIdleSuspend 调过 TrySuspendAsync）
            // SDK 1.0.3856.49 有 Resume()；suspend 状态下未 Resume 调 ExecScript 可能丢弃
            try
            {
                if (_webView != null && _webView.CoreWebView2 != null)
                    _webView.CoreWebView2.Resume();
            }
            catch (Exception ex) { LogManager.Log("[Panel] CoreWebView2.Resume failed: " + ex.Message); }

            // EX_STYLE：去 WS_EX_LAYERED 与 WS_EX_TRANSPARENT；DWM 不再做 α traversal
            try
            {
                int ex = GetWindowLong(this.Handle, GWL_EXSTYLE);
                int newEx = ex & ~(WS_EX_TRANSPARENT | WS_EX_LAYERED);
                SetWindowLong(this.Handle, GWL_EXSTYLE, newEx);
            }
            catch (Exception ex) { LogManager.Log("[Panel] ResumeForPanel SetWindowLong failed: " + ex.Message); }

            // TransparencyKey 复位（设为 Empty 同时也会让 WinForms 移除 LAYERED——已经手动移除，幂等）
            try { this.TransparencyKey = Color.Empty; } catch { }
            try { if (_webView != null) _webView.DefaultBackgroundColor = Color.Black; } catch { }

            // Panel 是普通 Web app 视口，不应沿用 Flash HUD 的 576 设计缩放。
            // 从 SW_HIDE/TrySuspendAsync 恢复时 WebView2 子窗口可能保留 idle 小尺寸；
            // 显式同步 Form/child bounds，避免出现 bounds=1600x900 但 CSS viewport 仍是 118x67 的黑屏。
            try
            {
                this.Bounds = panelRectScreen;
                this.ClientSize = new Size(panelRectScreen.Width, panelRectScreen.Height);
                if (_webView != null)
                {
                    _webView.Visible = true;
                    SyncWebViewViewportBounds(this.ClientSize.Width, this.ClientSize.Height,
                        1.0, "panel_resume_pre_show", true);
                }
                _webViewZoomFactor = 1.0;
                _lastViewportZoom = -1.0;
                this.PerformLayout();
            }
            catch (Exception ex) { LogManager.Log("[Panel] ResumeForPanel bounds/zoom sync failed: " + ex.Message); }

            SetWindowPos(this.Handle, HWND_TOP,
                panelRectScreen.X, panelRectScreen.Y,
                panelRectScreen.Width, panelRectScreen.Height,
                SWP_NOACTIVATE | SWP_SHOWWINDOW | SWP_FRAMECHANGED);

            try
            {
                if (_webView != null && _webView.IsHandleCreated)
                {
                    SyncWebViewViewportBounds(this.ClientSize.Width, this.ClientSize.Height,
                        1.0, "panel_resume_post_show", true);
                    SetWindowPos(_webView.Handle, HWND_TOP, 0, 0,
                        Math.Max(1, this.ClientSize.Width),
                        Math.Max(1, this.ClientSize.Height),
                        SWP_NOACTIVATE | SWP_SHOWWINDOW);
                }
                LogManager.Log("[Panel] ResumeForPanel applied form=" + this.Bounds
                    + " client=" + this.ClientSize.Width + "x" + this.ClientSize.Height
                    + " web=" + (_webView != null ? _webView.Bounds.ToString() : "<null>")
                    + " zoom=" + (_webView != null ? _webView.ZoomFactor.ToString("0.###", CultureInfo.InvariantCulture) : "<null>")
                    + " " + DescribeWebViewController());
            }
            catch (Exception ex) { LogManager.Log("[Panel] ResumeForPanel post-show child sync failed: " + ex.Message); }

            // 通知 web 端 panel viewport（CSS 用 var(--panel-w/-h) 自适应）
            // 必须在 TrySuspendAsync 之前；ResumeForPanel 不 suspend，时序天然成立
            try
            {
                PostToWeb("{\"type\":\"panel_viewport_set\",\"w\":"
                    + panelRectScreen.Width + ",\"h\":" + panelRectScreen.Height + "}");
            }
            catch (Exception ex) { LogManager.Log("[Panel] panel_viewport_set post failed: " + ex.Message); }

            try
            {
                ExecScript("window.dispatchEvent(new Event('resize'));"
                    + "if(window.OverlayViewportMetrics&&OverlayViewportMetrics.schedule){"
                    + "OverlayViewportMetrics.schedule('panel_resume');"
                    + "}else if(window.OverlayViewportMetrics&&OverlayViewportMetrics.report){"
                    + "OverlayViewportMetrics.report('panel_resume');}");
            }
            catch (Exception ex) { LogManager.Log("[Panel] panel resume resize post failed: " + ex.Message); }

            // idle 期间累积的 UiData 一次性补回（FlushUiDataBuffer 已合并 snapshot + buffer）
            try { FlushUiDataBuffer(); } catch (Exception ex) { LogManager.Log("[Panel] FlushUiDataBuffer failed: " + ex.Message); }
        }

        /// <summary>
        /// owner 移动/大小变化时由 PanelHostController 调用——仅重定位 webview 至新 panelRect，不动 EX_STYLE/timer 等。
        /// SWP_NOZORDER 避免拖窗时 z-order 重排闪烁；不加 SWP_FRAMECHANGED 跳过 NCPAINT。
        /// </summary>
        public void RepositionForPanel(Rectangle panelRectScreen)
        {
            if (_disposed) return;
            if (!_panelMode) return;
            try
            {
                this.Bounds = panelRectScreen;
                this.ClientSize = new Size(panelRectScreen.Width, panelRectScreen.Height);
                SetWindowPos(this.Handle, IntPtr.Zero,
                    panelRectScreen.X, panelRectScreen.Y,
                    panelRectScreen.Width, panelRectScreen.Height,
                    SWP_NOACTIVATE | SWP_NOZORDER);
                if (_webView != null)
                {
                    SyncWebViewViewportBounds(this.ClientSize.Width, this.ClientSize.Height,
                        1.0, "panel_reposition", false);
                }
            }
            catch (Exception ex) { LogManager.Log("[Panel] RepositionForPanel SetWindowPos failed: " + ex.Message); }
        }

        /// <summary>
        /// 计算当前 viewport 屏幕矩形（与 SyncPosition 同算法），不应用、不受 _panelMode 早 return 限制。
        /// PanelHostController 在 owner 移动时用此重算 anchor + panelRect。失败返回 Rectangle.Empty。
        /// </summary>
        public Rectangle GetCurrentAnchorScreenRect()
        {
            try
            {
                if (_mapper == null || _anchor == null) return Rectangle.Empty;
                float vpX, vpY, vpW, vpH;
                _mapper.CalcViewport(out vpX, out vpY, out vpW, out vpH);
                Point origin = _anchor.PointToScreen(Point.Empty);
                return new Rectangle(origin.X + (int)vpX, origin.Y + (int)vpY,
                    Math.Max(1, (int)vpW), Math.Max(1, (int)vpH));
            }
            catch { return Rectangle.Empty; }
        }

        /// <summary>
        /// panel → idle 切换（正常路径，幂等：非 panel 态直接 return）。
        /// Step：SuspendWebTimers → 冻结 HandleUiData → SW_HIDE → 恢复 EX_LAYERED+TRANSPARENT →
        ///       HWND_NOTOPMOST → TransparencyKey 复原 → DefaultBackgroundColor=Transparent → TrySuspendAsync fire-and-forget
        /// </summary>
        public void SuspendAfterPanel()
        {
            if (_disposed) return;
            if (!_panelMode) return; // 幂等
            DoForceIdleSequence();
        }

        /// <summary>
        /// 异常恢复路径专用：不查 _panelMode，强制把窗口拨回 idle 不变量。
        /// 即便是从未 ResumeForPanel 的中间状态也走完整序列，确保 ResetToClosedState 生效。
        /// </summary>
        public void ForceIdleState()
        {
            if (_disposed) return;
            DoForceIdleSequence();
        }

        private void ScheduleNativeHudIdleSuspend(string reason)
        {
            if (!_useNativeHud || !_webReady || !_shown || _disposed || _panelMode || _frozenForIdle)
                return;
            if (_nativeHudIdleSuspendPending)
                return;

            _nativeHudIdleSuspendPending = true;
            try
            {
                BeginInvoke(new Action(delegate()
                {
                    _nativeHudIdleSuspendPending = false;
                    if (_disposed || !_useNativeHud || !_webReady || !_shown || _panelMode || _frozenForIdle)
                        return;

                    ForceIdleState();
                    LogManager.Log("[WebOverlay] NativeHud idle suspend applied: " + (reason ?? "unspecified"));
                }));
            }
            catch (Exception ex)
            {
                _nativeHudIdleSuspendPending = false;
                LogManager.Log("[WebOverlay] NativeHud idle suspend schedule failed: " + ex.Message);
            }
        }

        private void DoForceIdleSequence()
        {
            PerfTrace.Mark("webOverlay.idle_sequence", _useNativeHud ? "full" : "soft");
            _panelMode = false;

            // Phase 4 收尾：useNativeHud=true 时所有常驻 HUD 已迁到 C# widget
            // (Notch/Toast/Currency/Combo/QuestNotice/SafeExitPanel/TopRightTools/JukeboxTitlebar/MapHud)，
            // 整个 SW_HIDE WebView2 + TrySuspendAsync 安全 → 拿回 ~15pp DWM α 地板成本。
            // useNativeHud=false 仍走 SoftIdleRestore（保留 web HUD 显示）。
            if (_useNativeHud)
                DoFullIdleSuspend();
            else
                DoSoftIdleRestore();
        }

        /// <summary>
        /// 完整 idle 冻结：SW_HIDE + 恢复 EX_STYLE + 停 timer + 冻结 HandleUiData + TrySuspendAsync。
        /// 仅 useNativeHud=true 时启用——前提是 NotchOverlay/ToastOverlay 接管 HUD 渲染，
        /// 玩家在 panel 关闭期间仍能看到 notch/toolbar/退出按钮。
        /// </summary>
        private void DoFullIdleSuspend()
        {
            // 1) 停所有 web-side timer（_cursorTimer 例外，见 SuspendWebTimers 注释）
            try { SuspendWebTimers(); } catch (Exception ex) { LogManager.Log("[Panel] SuspendWebTimers failed: " + ex.Message); }

            // 2) HandleUiData 进入冻结模式（仅缓存到 snapshot，不 ExecScript）
            _frozenForIdle = true;

            // 3) SW_HIDE
            try { ShowWindow(this.Handle, SW_HIDE); } catch { }

            // 4) 恢复 EX_STYLE：加回 WS_EX_LAYERED + WS_EX_TRANSPARENT
            try
            {
                int ex = GetWindowLong(this.Handle, GWL_EXSTYLE);
                int newEx = ex | WS_EX_TRANSPARENT | WS_EX_LAYERED;
                SetWindowLong(this.Handle, GWL_EXSTYLE, newEx);
            }
            catch (Exception ex) { LogManager.Log("[Panel] DoFullIdleSuspend SetWindowLong failed: " + ex.Message); }

            // 5) HWND_NOTOPMOST 防御：意外被唤醒也不浮到 NotchOverlay/HitNumber 之上
            try
            {
                SetWindowPos(this.Handle, HWND_NOTOPMOST, 0, 0, 0, 0,
                    SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_FRAMECHANGED);
            }
            catch { }

            // 6) 恢复 TransparencyKey + transparent BG
            try { this.TransparencyKey = TRANSPARENT_COLOR; } catch { }
            try { if (_webView != null) _webView.DefaultBackgroundColor = Color.Transparent; } catch { }

            // 7) 不再调用 TrySuspendAsync：实测 WebView2 从 suspend 恢复后可能保留 hidden
            // 小视口，导致 panel 只剩黑底。SW_HIDE + timer freeze 已足够移除 idle 合成成本。
        }

        /// <summary>
        /// 应急 idle restore：仅恢复样式拉回 anchor 矩形，保持 web 可见 + 不冻结。
        /// useNativeHud=false 时使用（无 NotchOverlay 接管，必须保留 web HUD）。
        /// </summary>
        private void DoSoftIdleRestore()
        {
            // 恢复 EX_STYLE：加回 WS_EX_LAYERED + WS_EX_TRANSPARENT
            try
            {
                int ex = GetWindowLong(this.Handle, GWL_EXSTYLE);
                int newEx = ex | WS_EX_TRANSPARENT | WS_EX_LAYERED;
                SetWindowLong(this.Handle, GWL_EXSTYLE, newEx);
            }
            catch (Exception ex) { LogManager.Log("[Panel] DoSoftIdleRestore SetWindowLong failed: " + ex.Message); }

            try { this.TransparencyKey = TRANSPARENT_COLOR; } catch { }
            try { if (_webView != null) _webView.DefaultBackgroundColor = Color.Transparent; } catch { }

            try
            {
                SetWindowPos(this.Handle, HWND_TOP, 0, 0, 0, 0,
                    SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_FRAMECHANGED);
            }
            catch { }

            try { ScheduleSyncPosition("panel_close"); } catch { }
        }

        /// <summary>停所有 web-side timer。新增 timer 字段必须加入此方法 + WebOverlayTimerFreezeAuditTests 清单。
        /// 例外：_cursorTimer 不停——cursor 数据流是纯 C# 鼠标 hook → CursorOverlayForm，与 web frozen 状态无关，
        /// 玩家在 panel 关闭/web SW_HIDE 时仍需要看到 cursor 移动。</summary>
        private void SuspendWebTimers()
        {
            if (_fpsTimer != null) _fpsTimer.Stop();
            if (_audioTimer != null) _audioTimer.Stop();
            // _cursorTimer 不停（cursor 渲染独立于 web）
            if (_positionSettleTimer != null) _positionSettleTimer.Stop();
            if (_positionLongSettleTimer != null) _positionLongSettleTimer.Stop();
            // System.Threading.Timer 用 Change(Timeout.Infinite, ...) 暂停
            if (_reloadDebounce != null)
                try { _reloadDebounce.Change(System.Threading.Timeout.Infinite, System.Threading.Timeout.Infinite); } catch { }
            if (_reloadTimeout != null)
                try { _reloadTimeout.Change(System.Threading.Timeout.Infinite, System.Threading.Timeout.Infinite); } catch { }
        }

        /// <summary>恢复 web-side timer（panel 态）。仅启 fps/audio；cursor/reload 按需 start 由各自 EnsureXxx 入口。</summary>
        private void ResumeWebTimers()
        {
            if (!_panelMode) return;
            if (_fpsTimer != null) _fpsTimer.Start();
            if (_audioTimer != null) _audioTimer.Start();
        }

        #endregion

        /// <summary>
        /// Web→C# 通用 task 桥。把 message 透传到 MessageRouter，
        /// 异步响应通过 PostToWeb 回送到 JS（前端按 callId 匹配）。
        /// </summary>
        private void HandleWebTaskMessage(JObject parsed, string json)
        {
            if (_taskRouter == null)
            {
                LogManager.Log("[WebTask] no router injected, dropping: " + json);
                return;
            }
            JToken callIdToken = parsed != null ? parsed["callId"] : null;
            string taskName = parsed != null ? parsed.Value<string>("task") : null;
            if (string.IsNullOrEmpty(taskName))
            {
                LogManager.Log("[WebTask] missing task field");
                return;
            }
            try
            {
                string syncResult = _taskRouter.ProcessMessage(json, delegate(string asyncResp)
                {
                    PostTaskResultToWeb(taskName, callIdToken, asyncResp);
                });
                if (syncResult != null)
                    PostTaskResultToWeb(taskName, callIdToken, syncResult);
            }
            catch (Exception ex)
            {
                LogManager.Log("[WebTask] " + taskName + " threw: " + ex.Message);
            }
        }

        private void PostTaskResultToWeb(string taskName, JToken callIdToken, string resultJson)
        {
            try
            {
                JObject wrap;
                if (string.IsNullOrEmpty(resultJson))
                {
                    wrap = new JObject();
                    wrap["success"] = true;
                }
                else
                {
                    try { wrap = JObject.Parse(resultJson); }
                    catch { wrap = new JObject(); wrap["raw"] = resultJson; }
                }
                wrap["type"] = "taskResult";
                wrap["task"] = taskName;
                if (callIdToken != null) wrap["callId"] = callIdToken;
                PostToWeb(wrap.ToString(Newtonsoft.Json.Formatting.None));
            }
            catch (Exception ex)
            {
                LogManager.Log("[WebTask] post result failed: " + ex.Message);
            }
        }

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
                        string closeAction = ResolvePanelCloseGameCommand(panel);
                        if (closeAction == "shopPanelClose")
                        {
                            if (!TrySendGameCommand(closeAction))
                                _pauseNeedsRestore = true;
                        }
                        else if (closeAction != null)
                        {
                            TrySendGameCommand(closeAction);
                        }
                        // help 等纯 web 面板无需通知 Flash
                        _activePanel = null;
                        if (_onPanelStateChanged != null) _onPanelStateChanged(false);
                        // panel close 回流：让 PanelHostController 把 backdrop/HUD/shield 拨回 idle 不变量
                        // Phase 1 _panelHost._activePanel 始终为 null（PanelHost 未接管打开路径）→ ClosePanel 走 ExecuteCommand 内
                        // "if (_activePanel == null) return;" 早 return，无副作用
                        // Phase 2+ PanelHost 真接管打开后，此回流防止 backdrop/HUD 残留半状态
                        if (_panelHost != null) _panelHost.ClosePanel();
                    }
                    break;
                case "bulkQuery":
                case "checkout":
                case "claim":
                case "saveCart":
                    LogManager.Log("[Panel] Routing cmd=" + cmd + " to ShopTask, _shopTask=" + (_shopTask != null ? "ok" : "NULL"));
                    if (_shopTask != null) _shopTask.HandleWebRequest(cmd, parsed);
                    break;
                case "tooltip":
                    {
                        string panel = parsed.Value<string>("panel") ?? "";
                        if (panel == "intelligence")
                        {
                            LogManager.Log("[Panel] Routing cmd=tooltip to IntelligenceTask, _intelligenceTask=" + (_intelligenceTask != null ? "ok" : "NULL"));
                            if (_intelligenceTask != null) _intelligenceTask.HandleWebRequest(cmd, parsed);
                        }
                        else
                        {
                            LogManager.Log("[Panel] Routing cmd=tooltip to ShopTask, _shopTask=" + (_shopTask != null ? "ok" : "NULL"));
                            if (_shopTask != null) _shopTask.HandleWebRequest(cmd, parsed);
                        }
                    }
                    break;
                case "snapshot":
                case "navigate":
                case "refresh":
                case "open_stage_select":
                case "enter":
                case "jump_frame":
                case "return_frame":
                case "catalog":
                case "state":
                case "bundle":
                    {
                        string panel = parsed.Value<string>("panel") ?? "";
                        if (panel == "stage-select")
                        {
                            LogManager.Log("[Panel] Routing cmd=" + cmd + " to StageSelectTask, _stageSelectTask=" + (_stageSelectTask != null ? "ok" : "NULL"));
                            if (_stageSelectTask != null) _stageSelectTask.HandleWebRequest(cmd, parsed);
                        }
                        else if (panel == "map" && cmd == "open_stage_select")
                        {
                            HandleMapOpenStageSelectRequest(parsed);
                        }
                        else if (panel == "intelligence")
                        {
                            LogManager.Log("[Panel] Routing cmd=" + cmd + " to IntelligenceTask, _intelligenceTask=" + (_intelligenceTask != null ? "ok" : "NULL"));
                            if (_intelligenceTask != null) _intelligenceTask.HandleWebRequest(cmd, parsed);
                        }
                        else if (cmd == "enter" || cmd == "jump_frame" || cmd == "return_frame" || cmd == "open_stage_select")
                        {
                            LogManager.Log("[Panel] Dropping cmd=" + cmd + " for unsupported panel=" + panel);
                        }
                        else
                        {
                            LogManager.Log("[Panel] Routing cmd=" + cmd + " to MapTask, _mapTask=" + (_mapTask != null ? "ok" : "NULL"));
                            if (_mapTask != null) _mapTask.HandleWebRequest(cmd, parsed);
                        }
                    }
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

        private void HandleMapOpenStageSelectRequest(JObject parsed)
        {
            string webCallId = parsed.Value<string>("callId");
            if (string.IsNullOrEmpty(webCallId))
            {
                LogManager.Log("[Panel] open_stage_select callId is empty");
                return;
            }

            string frameLabel = parsed.Value<string>("frameLabel") ?? "";
            string returnFrameLabel = parsed.Value<string>("returnFrameLabel") ?? "";
            string source = parsed.Value<string>("source") ?? "map_panel";
            if (!IsLikelyValidFrameLabel(frameLabel))
            {
                PostMapOpenStageSelectResponse(webCallId, false, "invalid_frame", frameLabel, returnFrameLabel);
                return;
            }
            if (!string.IsNullOrEmpty(returnFrameLabel) && !IsLikelyValidFrameLabel(returnFrameLabel))
            {
                returnFrameLabel = "";
            }

            RequestOpenPanel("stage-select", source, null, frameLabel, returnFrameLabel);
            PostMapOpenStageSelectResponse(webCallId, true, null, frameLabel, returnFrameLabel);
        }

        private static bool IsLikelyValidFrameLabel(string label)
        {
            if (string.IsNullOrEmpty(label)) return false;
            if (label.Length > 64) return false;
            for (int i = 0; i < label.Length; i++)
            {
                char c = label[i];
                if (c < 0x20 || c == 0x7F) return false;
            }
            return true;
        }

        private void PostMapOpenStageSelectResponse(string webCallId, bool success, string error, string frameLabel, string returnFrameLabel)
        {
            var msg = new JObject();
            msg["type"] = "panel_resp";
            msg["panel"] = "map";
            msg["cmd"] = "open_stage_select";
            msg["callId"] = webCallId;
            msg["success"] = success;
            if (!string.IsNullOrEmpty(error)) msg["error"] = error;
            if (!string.IsNullOrEmpty(frameLabel)) msg["frameLabel"] = frameLabel;
            if (!string.IsNullOrEmpty(returnFrameLabel)) msg["returnFrameLabel"] = returnFrameLabel;
            PostToWeb(msg.ToString(Newtonsoft.Json.Formatting.None));
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

            // 旧路径（_activePanel != null）仅追踪 web fallback 模式打开的 panel。
            // PanelHostController 接管的 panel 状态在 PanelHost 内（_panelHost.IsPanelOpen），
            // 必须独立联动——否则 backdrop / NativeHud Suspend / InputShield telemetry 会残留。
            if (_activePanel != null)
            {
                PostToWeb("{\"type\":\"panel_cmd\",\"cmd\":\"force_close\",\"reason\":\"disconnected\"}");
                // 只有需要 Flash 交互的面板才需要恢复暂停状态
                if (_activePanel == "kshop")
                    _pauseNeedsRestore = true;
                _activePanel = null;
                if (_onPanelStateChanged != null) _onPanelStateChanged(false);
            }
            // PanelHost 接管路径：联动关闭，确保 backdrop/HUD/Shield 都拨回 idle
            if (_panelHost != null && _panelHost.IsPanelOpen)
            {
                if (_panelHost.ActivePanelName == "kshop") _pauseNeedsRestore = true;
                PostToWeb("{\"type\":\"panel_cmd\",\"cmd\":\"force_close\",\"reason\":\"disconnected\"}");
                _panelHost.ClosePanel();
            }
            if (_shopTask != null) _shopTask.ClearPending();
            if (_mapTask != null) _mapTask.ClearPending();
            if (_stageSelectTask != null) _stageSelectTask.ClearPending();
            if (_intelligenceTask != null) _intelligenceTask.ClearPending();
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

        private LauncherCommandRouter _commandRouter;

        /// <summary>
        /// 二阶段注入：Program.cs 装配后调本方法绑定 router。
        /// 未注入时 HandleButtonClick 走旧 inline switch（仅过渡期；Phase 2 装配完成后所有路径都进 router）。
        /// </summary>
        public void SetCommandRouter(LauncherCommandRouter router) { _commandRouter = router; }

        /// <summary>Router fallback 路径（Flag OFF）专用：把 _activePanel 状态从 router 注回 WebOverlay。</summary>
        public void SetActivePanel(string panelName) { _activePanel = panelName; }

        private void HandleButtonClick(string key)
        {
            HandleButtonClick(key, null);
        }

        /// <summary>
        /// 按钮点击入口（薄包装）。Phase 2 起所有命令分发交给 LauncherCommandRouter。
        /// </summary>
        private void HandleButtonClick(string key, string rawJson)
        {
            if (_commandRouter != null)
            {
                _commandRouter.Dispatch(key, rawJson);
                return;
            }
            // Fallback：router 未注入（启动早期/单测）→ 不处理，写日志便于排查
            LogManager.Log("[Panel] HandleButtonClick before router wired, key=" + key);
        }

        /// <summary>
        /// AS2 → C# 面板打开请求 (旧版 Flash UI 按钮接入 WebView 面板)。
        /// 通过 TaskRegistry 注册的 "panel_request" task 驱动。
        /// 路由到 LauncherCommandRouter 走统一 panel 打开通道（Flag ON → PanelHostController；Flag OFF → PostToWeb 旧路径）。
        /// </summary>
        public void RequestOpenPanel(string panelName, string source)
        {
            RequestOpenPanel(panelName, source, null, null, null);
        }

        public void RequestOpenPanel(string panelName, string source, string pageId)
        {
            RequestOpenPanel(panelName, source, pageId, null, null);
        }

        public void RequestOpenPanel(string panelName, string source, string pageId, string frameLabel)
        {
            RequestOpenPanel(panelName, source, pageId, frameLabel, null);
        }

        public void RequestOpenPanel(string panelName, string source, string pageId, string frameLabel, string returnFrameLabel)
        {
            if (_disposed) return;
            if (this.IsHandleCreated && this.InvokeRequired)
            {
                try
                {
                    this.BeginInvoke(new Action(delegate()
                    {
                        RequestOpenPanel(panelName, source, pageId, frameLabel, returnFrameLabel);
                    }));
                }
                catch { }
                return;
            }

            if (_commandRouter != null)
            {
                _commandRouter.RequestOpenPanel(panelName, source, pageId, frameLabel, returnFrameLabel);
                return;
            }
            LogManager.Log("[Panel] RequestOpenPanel before router wired, panel=" + (panelName ?? "<null>"));
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
            // 用 JObject 结构化解析，避免曲名 / 设置 value 含 " 或 \ 时 ExtractString 截断错发。
            JObject parsed;
            try { parsed = JObject.Parse(json); }
            catch (Exception ex)
            {
                LogManager.Log("[Jukebox] JSON parse failed: " + ex.Message + " json=" + json);
                return;
            }
            string cmd = parsed.Value<string>("cmd");
            if (string.IsNullOrEmpty(cmd)) return;

            switch (cmd)
            {
                case "play":
                    {
                        string title = parsed.Value<string>("title");
                        if (!string.IsNullOrEmpty(title))
                            SendGameCommandWithData("jukeboxPlay",
                                "\"title\":\"" + EscapeJsonString(title) + "\"");
                    }
                    break;
                case "override":
                    {
                        bool over = parsed.Value<bool?>("value") ?? false;
                        SendGameCommandWithData("jukeboxOverride",
                            "\"value\":" + (over ? "true" : "false"));
                    }
                    break;
                case "trueRandom":
                    {
                        bool tr = parsed.Value<bool?>("value") ?? false;
                        SendGameCommandWithData("jukeboxTrueRandom",
                            "\"value\":" + (tr ? "true" : "false"));
                    }
                    break;
                case "playMode":
                    {
                        string mode = parsed.Value<string>("value");
                        if (!string.IsNullOrEmpty(mode))
                            SendGameCommandWithData("jukeboxPlayMode",
                                "\"value\":\"" + EscapeJsonString(mode) + "\"");
                    }
                    break;
                case "seek":
                    {
                        float sec = parsed.Value<float?>("sec") ?? 0f;
                        Audio.AudioEngine.ma_bridge_bgm_seek(sec);
                    }
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
                    {
                        int vg = parsed.Value<int?>("value") ?? 0;
                        SendGameCommandWithData("setGlobalVolume", "\"value\":" + vg);
                    }
                    break;
                case "volBgm":
                    {
                        int vb = parsed.Value<int?>("value") ?? 0;
                        SendGameCommandWithData("setBGMVolume", "\"value\":" + vb);
                    }
                    break;
                case "loadHelp":
                    LoadAndPushHelp();
                    break;
                case "requestCatalog":
                    // Phase 5 jukebox panel 在 onOpen 时请求当前 catalog——
                    // 因 MusicCatalog.CatalogChanged 是一次性增量推送（启动期 / 文件变更），
                    // 后续打开的 panel 错过推送，需主动 pull。
                    if (_musicCatalog != null && _webReady)
                    {
                        try { PostToWeb(_musicCatalog.GetFullCatalogJson()); }
                        catch (Exception ex) { LogManager.Log("[Jukebox] requestCatalog failed: " + ex.Message); }
                    }
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
