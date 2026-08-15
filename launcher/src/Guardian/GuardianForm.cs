using System;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;
using System.Diagnostics;
using Microsoft.Win32;
using CF7Launcher.Config;
using CF7Launcher.Diagnostic;

namespace CF7Launcher.Guardian
{
    public class GuardianForm : Form
    {
        /// <summary>
        /// Closed allowlist for destructive exits that may discard CharacterBuild state.
        /// Unknown enum values fail closed through the normal persistence-fenced path.
        /// </summary>
        public enum EmergencyExitReason
        {
            CtrlQ,
            HardExitKeyQ,
            FlashExitedReady,
            FlashZombieWatchdog
        }

        [DllImport("user32.dll")]
        private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

        [DllImport("user32.dll")]
        private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

        [DllImport("user32.dll")]
        private static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

        [DllImport("user32.dll")]
        private static extern bool SetForegroundWindow(IntPtr hWnd);

        [DllImport("user32.dll")]
        private static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter,
            int X, int Y, int cx, int cy, uint uFlags);

        private const uint MOD_CONTROL = 0x0002;
        private const int WM_HOTKEY = 0x0312;
        private const uint KEYEVENTF_KEYUP = 0x0002;
        private const int WM_DPICHANGED = 0x02E0;
        private const int WM_SIZE = 0x0005;
        private const int WM_ACTIVATEAPP = 0x001C;
        private const int SIZE_RESTORED = 0;
        private const int SIZE_MINIMIZED = 1;
        private const int SIZE_MAXIMIZED = 2;
        private const uint SWP_NOZORDER = 0x0004;
        private const uint SWP_NOACTIVATE = 0x0010;

        private const int DesiredBootstrapClientWidth = 1600;
        private const int DesiredBootstrapClientHeight = 900;
        private const int MinimumBootstrapClientWidth = 1120;
        private const int MinimumBootstrapClientHeight = 640;

        // RegisterHotKey ID（仅 Guardian 自身动作）
        private const int HK_CTRL_F = 0xCF01;
        private const int HK_CTRL_Q = 0xCF02;
        private const int HK_ESC = 0xCF10;

        // 工具栏按钮键
        private static readonly Keys[] AllHotkeyKeys = { Keys.Q, Keys.W, Keys.R, Keys.F, Keys.P, Keys.O };

        private NotifyIcon _trayIcon;
        private ContextMenuStrip _trayMenu;
        private ToolStripMenuItem _wingsTrayItem;
        private ToolStripMenuItem _agentEnrollmentTrayItem;
        private Action _showWingsAction;
        private Action _showAgentEnrollmentAction;
        private TextBox _logBox;
        private Panel _flashPanel;
        private BootstrapPanel _bootstrapPanel;  // Phase A: 启动期 UI（WebView2）
        private GameLaunchFlow _launchFlow;      // Phase A: 两段式 InitializeLaunchFlow 注入
        private Panel _logBar;
        private TextBox _searchBox;
        private int _searchPos;
        private bool _logVisible;
        private int _logBarH = 180;

        private bool _isFullscreen;
        private Rectangle _savedBounds;
        private FormBorderStyle _savedBorderStyle;
        private System.Windows.Forms.Timer _viewportSettleTimer;
        private System.Windows.Forms.Timer _viewportLongSettleTimer;
        private string _viewportSettleReason = "viewport_refresh";
        private bool _runtimeViewportWasMaximized;
        private int _runtimeViewportLastSizeCode = -1;

        private bool _hotkeysRegistered;
        private KeyboardHook _kbHook; // 前台感知低级钩子，替代 RegisterHotKey
        private WebOverlayForm _webOverlay; // 面板系统：ESC→PostToWeb

        // 应用激活状态的权威源：WM_ACTIVATEAPP/WM_SIZE 喂入，KeyboardHook 与
        // PerfDecisionEngine 据此判定前台/最小化，取代散落的 GetForegroundWindow() 轮询。
        private readonly AppActivationState _activationState = new AppActivationState();
        // 前台看门狗：检测"焦点真空"并自动回收 Flash 前台（详见 SetupForegroundWatchdog）。
        private System.Windows.Forms.Timer _foregroundWatchdog;
        private int _lastWatchdogActionTick;
        private volatile int _lastWatchdogTickTick;
        private long _guardianHwndForProbe;
        private UiFreezeProbe _uiFreezeProbe;
        // 焦点真空连续命中的 tick 计数：要求 ≥2 次（≈800ms）才动作，规避用户焦点
        // 交接瞬间穿过 GetForegroundWindow()==NULL 的竞态（详见 OnForegroundWatchdogTick）。
        private int _vacuumStreak;
        // 工作站锁定 / 安全桌面 / 快速用户切换：此期间默认桌面侧前台恒为 NULL，看门狗须停。
        private volatile bool _sessionLocked;
        // [Activation] lost 日志时间戳，gained 时输出 gapMs 用于区分 toast 抢焦 vs 用户切走。
        private int _lastDeactivateLogTick;

        private Process _flashProcess;

        private WindowManager _windowManager;

        /// <summary>Flash 嵌入目标：始终是 _flashPanel。</summary>
        public Panel FlashHostPanel { get { return _flashPanel; } }

        /// <summary>Phase A: 启动期 BootstrapPanel。bus-only 模式下可能为 null。</summary>
        public BootstrapPanel BootstrapPanel { get { return _bootstrapPanel; } }

        /// <summary>
        /// Phase A: 构造函数接受 bootstrapWebDir.
        /// - bootstrapWebDir != null：正常模式。创建 BootstrapPanel 启动期可见，FlashHostPanel 隐藏.
        /// - bootstrapWebDir == null：bus-only 模式。无 BootstrapPanel，FlashHostPanel 直接可见.
        /// </summary>
        public GuardianForm() : this(null, false, "", false, false) { }

        public GuardianForm(string bootstrapWebDir)
            : this(bootstrapWebDir, false, "", false, false)
        {
        }

        public GuardianForm(string bootstrapWebDir, bool bootstrapWebView2DisableGpu, string bootstrapWebView2AdditionalArgs)
            : this(bootstrapWebDir, bootstrapWebView2DisableGpu, bootstrapWebView2AdditionalArgs, false, false)
        {
        }

        public GuardianForm(string bootstrapWebDir, bool bootstrapWebView2DisableGpu,
            string bootstrapWebView2AdditionalArgs, bool isolatedRuntimeCandidate)
            : this(
                bootstrapWebDir,
                bootstrapWebView2DisableGpu,
                bootstrapWebView2AdditionalArgs,
                false,
                isolatedRuntimeCandidate)
        {
        }

        public GuardianForm(
            string bootstrapWebDir,
            bool bootstrapWebView2DisableGpu,
            string bootstrapWebView2AdditionalArgs,
            bool bootstrapWebView2DeveloperMode,
            bool isolatedRuntimeCandidate)
        {
            InitializeComponent(
                bootstrapWebDir,
                bootstrapWebView2DisableGpu,
                bootstrapWebView2AdditionalArgs,
                bootstrapWebView2DeveloperMode,
                isolatedRuntimeCandidate);
            SetupTrayIcon();
            SetupHotkeys();
            SetupForegroundWatchdog();
            LogManager.Init(this, _logBox);
        }

        public void BindWindowManager(WindowManager wm)
        {
            _windowManager = wm;
            StartUiFreezeProbe();
        }

        /// <summary>应用激活状态的权威源。Program.cs 注入给 PerfDecisionEngine。</summary>
        public AppActivationState ActivationState { get { return _activationState; } }

        /// <summary>Phase 2 PanelHostController FlashSnapshot.Capture 用。SA 进程重启时返回 IntPtr.Zero。</summary>
        public IntPtr GetFlashHwnd()
        {
            return (_windowManager != null) ? _windowManager.FlashHwnd : IntPtr.Zero;
        }

        private void StartUiFreezeProbe()
        {
            if (_uiFreezeProbe != null || _windowManager == null) return;

            _uiFreezeProbe = new UiFreezeProbe(
                delegate { return new IntPtr(Interlocked.Read(ref _guardianHwndForProbe)); },
                delegate { return (_windowManager != null) ? _windowManager.FlashHwnd : IntPtr.Zero; },
                delegate { return _lastWatchdogTickTick; },
                delegate { return _sessionLocked || _exitStarted != 0; });
            _uiFreezeProbe.Start();
        }

        private void StopUiFreezeProbe()
        {
            UiFreezeProbe probe = _uiFreezeProbe;
            _uiFreezeProbe = null;
            if (probe != null)
            {
                try { probe.Dispose(); } catch { }
            }
        }

        /// <summary>
        /// Phase A Step A2: 两段式初始化第二步。
        /// GameLaunchFlow ctor 依赖 GuardianForm + BootstrapPanel，因此 launchFlow 必须在 GuardianForm 之后构造；
        /// 调此方法补 wire：保存引用供 OnFormClosing 状态分流 + Ctrl+F/Esc state-aware guard 使用。
        /// 若 launchFlow 为 null 或 InitializeLaunchFlow 未调（极早期关窗），OnFormClosing 走 Idle 同路径。
        /// </summary>
        public void InitializeLaunchFlow(GameLaunchFlow launchFlow)
        {
            _launchFlow = launchFlow;
        }



        /// <summary>
        /// Phase B Step B1: watchdog 去 ForceExit，只做 PID 追踪.
        /// 原 500ms poll 检测 HasExited → ForceExit 的行为已移除;
        /// Flash 退出唯一真源是 ProcessManager.OnFlashExited（GameLaunchFlow 订阅，按 state 分流）.
        /// 本方法仅用于:
        ///   - 把 Flash PID 传给 KeyboardHook，让热键在 Flash 前台时也能拦截
        ///   - 为将来可能的 UI 侧 PID 匹配保留追踪字段
        /// </summary>
        public void TrackFlashProcess(Process p)
        {
            _flashProcess = p;
            if (_kbHook != null && p != null)
                _kbHook.SetFlashPid((uint)p.Id);
        }

        // ============================================================
        //  布局
        // ============================================================

        internal static string SelectWindowTitle(bool isolatedRuntimeCandidate)
        {
            return isolatedRuntimeCandidate
                ? "CF7:FlashNight — 隔离候选 / 未部署"
                : "CF7:FlashNight";
        }

        private void InitializeComponent(
            string bootstrapWebDir,
            bool bootstrapWebView2DisableGpu,
            string bootstrapWebView2AdditionalArgs,
            bool bootstrapWebView2DeveloperMode,
            bool isolatedRuntimeCandidate)
        {
            this.Text = SelectWindowTitle(isolatedRuntimeCandidate);
            this.StartPosition = FormStartPosition.CenterScreen;
            this.FormBorderStyle = FormBorderStyle.Sizable;
            this.AutoScaleMode = AutoScaleMode.None;
            this.MinimumSize = SizeFromClientSize(new Size(MinimumBootstrapClientWidth, MinimumBootstrapClientHeight));
            this.ClientSize = CalculateInitialBootstrapClientSize();
            this.BackColor = Color.Black;

            // 窗口图标：从 exe 自身资源提取（app.ico 已嵌入为 ApplicationIcon）
            // 发布布局不依赖 Assembly.Location，改用当前进程 exe 路径
            try { this.Icon = Icon.ExtractAssociatedIcon(Environment.ProcessPath); }
            catch { /* fallback: 使用系统默认 */ }

            Font uiFont = new Font("Microsoft YaHei UI", 8.25f);

            // ── 底部日志控制台 ──
            _logBar = new Panel();
            _logBar.Dock = DockStyle.Bottom;
            _logBar.Height = 0;
            _logBar.Visible = false;
            _logBar.BackColor = Color.FromArgb(20, 20, 22);

            // 拖拽手柄
            Panel dragHandle = new Panel();
            dragHandle.Dock = DockStyle.Top;
            dragHandle.Height = 4;
            dragHandle.BackColor = Color.FromArgb(56, 56, 60);
            dragHandle.Cursor = Cursors.HSplit;

            bool dragging = false;
            int dragStartY = 0;
            int dragStartH = 0;

            dragHandle.MouseDown += delegate(object s, MouseEventArgs e)
            {
                if (e.Button == MouseButtons.Left)
                {
                    dragging = true;
                    dragStartY = Cursor.Position.Y;
                    dragStartH = _logBar.Height;
                    dragHandle.Capture = true;
                }
            };
            dragHandle.MouseMove += delegate(object s, MouseEventArgs e)
            {
                if (!dragging) return;
                int delta = dragStartY - Cursor.Position.Y;
                int newH = dragStartH + delta;
                newH = Math.Max(60, Math.Min(newH, this.ClientSize.Height - 100));
                _logBar.Height = newH;
            };
            dragHandle.MouseUp += delegate
            {
                dragging = false;
                dragHandle.Capture = false;
            };

            // 搜索栏
            Panel searchBar = new Panel();
            searchBar.Dock = DockStyle.Top;
            searchBar.Height = 24;
            searchBar.BackColor = Color.FromArgb(28, 28, 30);
            searchBar.Padding = new Padding(4, 2, 4, 2);

            _searchBox = new TextBox();
            _searchBox.Dock = DockStyle.Fill;
            _searchBox.Font = new Font("Consolas", 8);
            _searchBox.BackColor = Color.FromArgb(36, 36, 40);
            _searchBox.ForeColor = Color.FromArgb(200, 200, 200);
            _searchBox.BorderStyle = BorderStyle.FixedSingle;
            _searchBox.KeyDown += OnSearchKeyDown;
            searchBar.Controls.Add(_searchBox);

            Label searchHint = new Label();
            searchHint.Text = "搜索";
            searchHint.Dock = DockStyle.Left;
            searchHint.Width = 36;
            searchHint.Font = uiFont;
            searchHint.ForeColor = Color.FromArgb(100, 100, 100);
            searchHint.TextAlign = ContentAlignment.MiddleLeft;
            searchBar.Controls.Add(searchHint);

            _logBox = new TextBox();
            _logBox.Multiline = true;
            _logBox.ReadOnly = true;
            _logBox.ScrollBars = ScrollBars.Both;
            _logBox.Dock = DockStyle.Fill;
            _logBox.Font = new Font("Consolas", 8);
            _logBox.BackColor = Color.FromArgb(16, 16, 18);
            _logBox.ForeColor = Color.FromArgb(160, 160, 160);
            _logBox.BorderStyle = BorderStyle.None;
            _logBox.WordWrap = false;
            _logBox.HideSelection = false;

            // Fill 先加（最高 z-order → 最后布局）
            _logBar.Controls.Add(_logBox);
            _logBar.Controls.Add(searchBar);
            _logBar.Controls.Add(dragHandle);

            this.Controls.Add(_logBar);

            // ── Flash 宿主 ──
            // Flash 通过 Win32 SetParent 嵌入 _flashPanel。
            // Phase A: 启动期 _flashPanel.Visible=false（避免 BootstrapPanel 层级冲突/黑屏），
            // 但通过 Form.Load 后访问 _flashPanel.Handle 强制句柄创建，
            // 保证 WindowManager.EmbedFlashWindow 的 BeginInvoke 路径在 Embedding 阶段可用.
            _flashPanel = new Panel();
            _flashPanel.Dock = DockStyle.Fill;
            _flashPanel.BackColor = Color.Black;
            _flashPanel.Visible = (bootstrapWebDir == null);  // bus-only: 直接可见
            this.Controls.Add(_flashPanel);

            // Phase A: BootstrapPanel（仅正常模式；后加 = 更高 z-order 显示在 Flash 之上）
            if (bootstrapWebDir != null)
            {
                _bootstrapPanel = new BootstrapPanel(
                    bootstrapWebDir,
                    bootstrapWebView2DisableGpu,
                    bootstrapWebView2AdditionalArgs,
                    bootstrapWebView2DeveloperMode);
                _bootstrapPanel.Dock = DockStyle.Fill;
                _bootstrapPanel.Visible = true;
                this.Controls.Add(_bootstrapPanel);
                _bootstrapPanel.BootstrapInitFailed += OnBootstrapInitFailed;
            }

            this.FormClosing += OnFormClosing;

            // Phase A: _flashPanel.Visible=false 会阻止 Handle 创建，
            // 但 WindowManager.EmbedFlashWindow 终点需要 BeginInvoke 到 _hostPanel.Handle 才能
            // 在 UI 线程调 StartEmbedWatchdog/ResizeFlashToPanel/FireEmbedResult.
            // Form.Load 后显式访问 .Handle 强制创建（此时 form 自身 Handle 已就绪）.
            // 对 bus-only 模式无害（Visible=true 的 Handle 早已创建）.
            this.Load += delegate
            {
                if (_flashPanel != null && !_flashPanel.IsHandleCreated)
                {
                    IntPtr _ = _flashPanel.Handle;  // 访问 getter 强制创建
                    LogManager.Log("[Guardian] _flashPanel handle force-created (Visible=" + _flashPanel.Visible + ")");
                }
            };
        }

        /// <summary>
        /// Phase A Step A1/A3: WebView2 初始化失败 fatal 兜底.
        /// 原 BootstrapForm.InitWebView2Async 的 this.Close() + GuardianContext FormClosed 桥的替代通道.
        /// </summary>
        private void OnBootstrapInitFailed(string reason)
        {
            LogManager.Log("[Guardian] BootstrapPanel init FATAL: " + reason + " → ForceExit");
            try
            {
                if (this.IsHandleCreated && !this.IsDisposed)
                    this.BeginInvoke(new Action(ForceExit));
                else
                    ForceExit();
            }
            catch
            {
                try { ForceExit(); } catch { }
            }
        }

        // ============================================================
        //  热键：仅注册 Guardian 自身动作（Ctrl+F 全屏、Ctrl+Q 退出）
        //  Flash SA 的原生快捷键由 WindowManager.SetMenu(null) 从源头禁用
        // ============================================================

        private void SetupHotkeys()
        {
            // 用前台感知的低级钩子替代 RegisterHotKey（后者是系统全局的，
            // 会吞掉其他应用的 Ctrl+F 等快捷键，影响开发效率）
            _kbHook = new KeyboardHook();

            // 钩子的前台判定改读去抖后的进程级激活状态（WM_ACTIVATEAPP 驱动），
            // 不再在钩子回调里裸轮询 GetForegroundWindow()——后者会被后台程序瞬时抢焦打翻。
            _kbHook.SetActivationProbe(delegate { return _activationState.IsAppActive; });

            // Ctrl+F → 全屏（回调在钩子线程，需 BeginInvoke 回 UI 线程）
            // Phase A Step A3b: 非 Ready 态 no-op（bootstrap 期 Flash 未 embed，全屏切换无意义）
            _kbHook.RegisterAction(0x46, delegate {
                if (!IsReadyForHotkey()) return;
                ToggleFullscreen();
            });
            // Ctrl+Q → 明示放弃未保存改动并强退（bootstrap / Ready 均可用）
            _kbHook.RegisterAction(0x51, delegate {
                EmergencyExit(EmergencyExitReason.CtrlQ);
            });
            // Ctrl+G GPU 探针在 EnableDevGpuProbeHotkey() 中按 config 启用，玩家版不注入
            // Escape：固定回调，按 volatile 标志分支（避免 Dictionary 并发竞态）
            _kbHook.RegisterAction(0x1B, delegate {
                if (_kbHook.PanelEscEnabled)
                {
                    try { this.BeginInvoke(new Action(delegate {
                        if (_webOverlay != null) _webOverlay.PostToWeb(
                            "{\"type\":\"panel_esc\",\"reason\":\"escape\"}");
                    })); } catch {}
                }
                else
                {
                    // Phase A Step A3b: 非 Ready 态 no-op
                    if (!IsReadyForHotkey()) return;
                    ToggleFullscreen();
                }
            });

            if (_kbHook.Install())
            {
                _hotkeysRegistered = true;
            }
            else
            {
                // 钩子安装失败 → fallback 到 RegisterHotKey（全局但至少能用）
                LogManager.Log("[Hotkey] KeyboardHook failed, falling back to RegisterHotKey");
                _kbHook.Dispose();
                _kbHook = null;
                FallbackRegisterHotkeys();
            }
        }

        /// <summary>
        /// Phase A Step A3b: bootstrap 期热键 no-op 判定.
        /// Ctrl+F / Esc ToggleFullscreen 仅 Ready 态有效; Ctrl+Q 硬退出不经此 guard.
        /// </summary>
        private bool IsReadyForHotkey()
        {
            if (_launchFlow == null) return false;
            try { return _launchFlow.CurrentState == "Ready"; }
            catch { return false; }
        }

        /// <summary>
        /// 启用开发用 Ctrl+G GPU 合成探针（toggle WebView2 opaque + Flash 隐藏）。
        /// 由 Program.cs 在 config.devGpuProbeHotkey=true 时调用；玩家版默认不开。
        /// 必须在 SetupHotkeys 之后调用（_kbHook 已就绪），重复调用安全。
        /// </summary>
        public void EnableDevGpuProbeHotkey()
        {
            if (_kbHook == null) { LogManager.Log("[GpuProbe] hotkey unavailable: kb hook not installed"); return; }
            _kbHook.EnableBlockedVk(0x47); // G
            _kbHook.RegisterAction(0x47, delegate {
                if (!IsReadyForHotkey()) return;
                try { this.BeginInvoke(new Action(delegate {
                    if (_webOverlay == null || _windowManager == null) return;
                    _webOverlay.ToggleCompositionProbe(_windowManager.FlashHwnd);
                })); } catch {}
            });
            LogManager.Log("[GpuProbe] Ctrl+G enabled (dev-only)");
        }

        /// <summary>Fallback：KeyboardHook 安装失败时退化为 RegisterHotKey</summary>
        private void FallbackRegisterHotkeys()
        {
            // 延迟到窗口句柄就绪
            System.Windows.Forms.Timer t = new System.Windows.Forms.Timer();
            t.Interval = 200;
            t.Tick += delegate
            {
                if (!this.IsHandleCreated) return;
                t.Stop();
                t.Dispose();
                bool f = RegisterHotKey(this.Handle, HK_CTRL_F, MOD_CONTROL, (uint)Keys.F);
                bool q = RegisterHotKey(this.Handle, HK_CTRL_Q, MOD_CONTROL, (uint)Keys.Q);
                _hotkeysRegistered = true;
                LogManager.Log("[Hotkey] Fallback RegisterHotKey Ctrl+F=" + f + " Ctrl+Q=" + q);
            };
            t.Start();
        }

        private void DoUnregisterHotkeys()
        {
            StopUiFreezeProbe();
            // 前台看门狗与热键同属输入/前台子系统，一并拆除（独立于 _hotkeysRegistered）。
            if (_foregroundWatchdog != null)
            {
                _foregroundWatchdog.Stop();
                _foregroundWatchdog.Dispose();
                _foregroundWatchdog = null;
                // SystemEvents 持静态引用，不退订会泄漏 GuardianForm。
                SystemEvents.SessionSwitch -= OnSessionSwitch;
            }
            if (!_hotkeysRegistered) return;
            if (_kbHook != null) { _kbHook.Dispose(); _kbHook = null; }
            // fallback 清理（无论是否实际注册过，调用 Unregister 是安全的）
            if (this.IsHandleCreated)
            {
                UnregisterHotKey(this.Handle, HK_CTRL_F);
                UnregisterHotKey(this.Handle, HK_CTRL_Q);
                UnregisterHotKey(this.Handle, HK_ESC);
            }
            _hotkeysRegistered = false;
        }

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == WM_DPICHANGED)
            {
                ApplySuggestedDpiBounds(m.LParam);
                DpiDiagnostics.LogWindow("GuardianForm.WM_DPICHANGED", this.Handle);
                ScheduleViewportRefresh("guardian_dpi_changed");
                base.WndProc(ref m);
                return;
            }

            // fallback 模式下处理 RegisterHotKey 的 WM_HOTKEY
            if (m.Msg == WM_HOTKEY && _kbHook == null)
            {
                int id = m.WParam.ToInt32();
                if (id == HK_ESC || id == HK_CTRL_F)
                {
                    // Phase A Step A3b: 非 Ready 态 no-op
                    if (!IsReadyForHotkey()) return;
                    ToggleFullscreen();
                    return;
                }
                if (id == HK_CTRL_Q)
                {
                    EmergencyExit(
                        EmergencyExitReason.CtrlQ);
                    return;
                }
            }

            // 应用激活状态：WM_ACTIVATEAPP 是进程级信号（同进程窗口间切换不触发），
            // WM_SIZE/SIZE_MINIMIZED 给出最小化态。喂入 _activationState 后照常下传。
            if (m.Msg == WM_ACTIVATEAPP)
            {
                bool active = m.WParam != IntPtr.Zero;
                // 抢焦归因日志：WM_ACTIVATEAPP(false) 这一瞬 GetForegroundWindow() 还能抓到
                // 抢焦的窗口（pid/class/title），之后窗口可能消失。lost→gained 配对的时间差
                // 用来区分"toast 瞬时抢焦"（<200ms，被 AppActivationState 去抖吃掉）vs
                // "用户切走又切回"（秒级）。AppActivationState 自己不打日志（无锁路径），
                // 这里是唯一归因点。
                int nowTick = Environment.TickCount;
                if (active)
                {
                    int gapMs = (_lastDeactivateLogTick != 0)
                        ? unchecked(nowTick - _lastDeactivateLogTick) : -1;
                    LogManager.Log("[Activation] gained gapMs=" + gapMs);
                    _lastDeactivateLogTick = 0;
                }
                else
                {
                    string fgDesc = (_windowManager != null)
                        ? _windowManager.DescribeForeground() : "(no wm)";
                    LogManager.Log("[Activation] lost fg=" + fgDesc);
                    _lastDeactivateLogTick = nowTick;
                }
                _activationState.OnActivateApp(active);
                if (active && _webOverlay != null)
                    _webOverlay.RequestPanelFocusRestoreAfterAppActivation();
            }
            else if (m.Msg == WM_SIZE)
            {
                int sizeCode = m.WParam.ToInt32();
                int previousSizeCode = _runtimeViewportLastSizeCode;
                bool windowStateReportedMaximized = this.WindowState == FormWindowState.Maximized;
                _activationState.OnMinimizeChanged(sizeCode == SIZE_MINIMIZED);

                // Manual window maximize/restore does not pass through ToggleFullscreen().
                // Reuse the same settled viewport refresh so Flash, WebOverlay and WebView2
                // are measured again after WinForms and DWM finish applying the new bounds.
                if (sizeCode == SIZE_MAXIMIZED)
                {
                    _runtimeViewportWasMaximized = true;
                    ScheduleViewportRefresh("guardian_wm_size_maximized");
                }
                else if (sizeCode == SIZE_RESTORED)
                {
                    // Do not rely only on our own flag: WM_SIZE ordering can report a restore
                    // after state was already set externally, or while WindowState still reflects
                    // the old maximized state before base.WndProc processes the message.
                    if (_runtimeViewportWasMaximized
                        || previousSizeCode == SIZE_MAXIMIZED
                        || windowStateReportedMaximized)
                        ScheduleViewportRefresh("guardian_wm_size_restored");
                    else if (previousSizeCode == SIZE_MINIMIZED)
                    {
                        // minimize→restore 同样穿越 DWM 窗口状态切换，Flash 与 WebOverlay
                        // 需要在落定后重测——此前只覆盖 maximize→restore，minimize 恢复
                        // 零补偿，叠加 owned overlay 被 OS 隐藏/重显，WebView2 合成链可能
                        // 停在 wedge（panel 黑屏但 JS 正常）。ResumeForPanel 的 compositor
                        // kick 负责下一次 panel 打开的强制重合成。
                        ScheduleViewportRefresh("guardian_wm_size_restored_from_minimized");
                    }
                    _runtimeViewportWasMaximized = false;
                }
                else if (sizeCode != SIZE_MINIMIZED)
                {
                    _runtimeViewportWasMaximized = false;
                }
                _runtimeViewportLastSizeCode = sizeCode;
            }

            base.WndProc(ref m);
        }

        // ============================================================
        // 前台看门狗：业界标准的"兜底"层。
        //
        // 后台程序（QQ/Telegram 的通知窗）抢走系统前台后，有时不会把前台归还给游戏
        // 窗口，留下"焦点真空"——GetForegroundWindow() 返回 NULL，没有任何窗口持有
        // 系统前台。此状态下：
        //   • KeyboardHook 的前台判定落空 → 快捷键失灵（玩家反馈"触发不了 UI"）；
        //   • Flash SA 因非前台自行降帧 → 帧数大降。
        // 玩家原本的解法是"点窗口外面再点回来"手动制造一次激活。本看门狗把这个动作
        // 自动化：检测到焦点真空就调 RestoreFlashInputFocus 把前台拉回 Flash。
        //
        // 【保守】只在真空（fg==NULL）时动作——真空绝不会是用户的主动选择。若前台是
        // 某个真实的其他程序（用户自己切过去的），一律不抢，避免与用户对抗。
        // ============================================================

        private void SetupForegroundWatchdog()
        {
            _foregroundWatchdog = new System.Windows.Forms.Timer();
            _foregroundWatchdog.Interval = 400;
            _foregroundWatchdog.Tick += OnForegroundWatchdogTick;
            _foregroundWatchdog.Start();
            // 锁屏 / 安全桌面 / 快速用户切换期间，默认桌面侧 GetForegroundWindow() 恒为
            // NULL，会被误判为焦点真空——订阅会话切换，断开态直接停看门狗。
            SystemEvents.SessionSwitch += OnSessionSwitch;
        }

        private void OnSessionSwitch(object sender, SessionSwitchEventArgs e)
        {
            switch (e.Reason)
            {
                case SessionSwitchReason.SessionLock:
                case SessionSwitchReason.ConsoleDisconnect:
                case SessionSwitchReason.RemoteDisconnect:
                    _sessionLocked = true;
                    break;
                case SessionSwitchReason.SessionUnlock:
                case SessionSwitchReason.ConsoleConnect:
                case SessionSwitchReason.RemoteConnect:
                    _sessionLocked = false;
                    break;
            }
        }

        private void OnForegroundWatchdogTick(object sender, EventArgs e)
        {
            _lastWatchdogTickTick = Environment.TickCount;
            if (this.IsHandleCreated)
                Interlocked.Exchange(ref _guardianHwndForProbe, this.Handle.ToInt64());

            // System.Windows.Forms.Timer.Tick 抛异常会冒到消息循环——本文件其余热键
            // 回调均包 try/catch，此处保持一致（RestoreFlashInputFocus 文档承诺不抛，
            // 但 IsReadyForHotkey 等仍可能在边界态抛）。
            try
            {
                if (this.IsDisposed || !this.IsHandleCreated) return;
                // 锁屏 / 安全桌面 / 快速用户切换期间，默认桌面侧前台恒为 NULL，看门狗须停
                // ——否则整夜锁屏会刷上千条无效 [FgWatchdog] / [FocusRestore] 日志。
                if (_sessionLocked) { _vacuumStreak = 0; return; }
                // 仅 Ready 态介入：bootstrap 期 Flash 未嵌入，谈不上前台回收。
                if (!IsReadyForHotkey()) { _vacuumStreak = 0; return; }
                // 最小化是用户的主动选择，不打扰。
                if (_activationState.IsMinimized) { _vacuumStreak = 0; return; }
                // 面板打开时前台合法地属于 WebOverlay（同进程），不在此处理。
                if (_webOverlay != null && _webOverlay.IsPanelMode) { _vacuumStreak = 0; return; }
                if (_windowManager == null) { _vacuumStreak = 0; return; }

                // 焦点真空须【连续】命中：GetForegroundWindow()==NULL 在正常的前台交接
                // 过程中会瞬时出现（MSDN：a window is losing activation 时即为 NULL），
                // 单帧采样会与用户主动切换竞态——误把交接瞬间当真空，把前台抢回 Flash。
                // 要求连续 ≥2 次 tick（≈800ms）确认是【持续】真空，才视作"后台程序
                // 抢焦未归还"，再动作。
                if (!_windowManager.IsForegroundVacuum()) { _vacuumStreak = 0; return; }
                _vacuumStreak++;
                if (_vacuumStreak < 2) return;

                // 节流：真空若持续且回收失败，避免每 400ms 刷一条 [FocusRestore] 日志。
                int now = Environment.TickCount;
                if (_lastWatchdogActionTick != 0
                    && unchecked(now - _lastWatchdogActionTick) < 2000)
                    return;
                _lastWatchdogActionTick = now;

                LogManager.Log("[FgWatchdog] foreground vacuum detected, reclaiming Flash foreground");
                _windowManager.RestoreFlashInputFocus("fg_watchdog:vacuum");
            }
            catch (Exception ex)
            {
                LogManager.Log("[FgWatchdog] tick error: " + ex.Message);
            }
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct NativeRect
        {
            public int Left;
            public int Top;
            public int Right;
            public int Bottom;
        }

        private void ApplySuggestedDpiBounds(IntPtr lParam)
        {
            if (lParam == IntPtr.Zero)
                return;
            try
            {
                NativeRect r = (NativeRect)Marshal.PtrToStructure(lParam, typeof(NativeRect));
                int w = Math.Max(1, r.Right - r.Left);
                int h = Math.Max(1, r.Bottom - r.Top);
                SetWindowPos(this.Handle, IntPtr.Zero, r.Left, r.Top, w, h,
                    SWP_NOZORDER | SWP_NOACTIVATE);
            }
            catch { }
        }

        // ============================================================
        //  工具栏按钮
        // ============================================================

        public void HandleButtonClick(Keys key)
        {
            switch (key)
            {
                case Keys.F: ToggleFullscreen(); break;
                case Keys.Q:
                    EmergencyExit(
                        EmergencyExitReason.HardExitKeyQ);
                    break;
                default: SendKeyToFlash(key); break;
            }
        }

        public void SendKeyToFlash(Keys key)
        {
            // 经 RestoreFlashInputFocus primitive 拉回前台 + 焦点（带 AttachThreadInput 兜底 + verify + 日志）；
            // ctrl_combo 路径 keybd_event 是全局注入，必须先确认 Flash 真的在前台——否则按键命中
            // 当前 fg（可能是 launcher 主窗口 / 用户切走的其他应用），引发误操作。
            // primitive 内部已打 [FocusRestore] 详细日志，此处失败时只补一条 skip 摘要。
            bool focusOk = (_windowManager != null) && _windowManager.RestoreFlashInputFocus("ctrl_combo:" + key);
            if (!focusOk)
            {
                LogManager.Log("[Input] Skip Ctrl+" + key + " injection: focus restore failed");
                return;
            }

            keybd_event((byte)Keys.ControlKey, 0, 0, UIntPtr.Zero);
            keybd_event((byte)key, 0, 0, UIntPtr.Zero);
            keybd_event((byte)key, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
            keybd_event((byte)Keys.ControlKey, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);

            LogManager.Log("[Input] Sent Ctrl+" + key + " to Flash");
        }

        // ============================================================
        //  面板系统
        // ============================================================

        public void SetWebOverlay(WebOverlayForm overlay) { _webOverlay = overlay; }

        /// <summary>
        /// 暴露 IPanelEscapeSource 给 PanelHostController 使用。
        /// fallback 模式（_kbHook==null，RegisterHotKey 兜底）下 panel ESC 不支持，返回 null；
        /// PanelHostController 已对 null escSource 做 null-check（panel ESC 不可用，但其它路径不阻塞）。
        /// </summary>
        public IPanelEscapeSource GetPanelEscapeSource()
        {
            return _kbHook;
        }

        /// <summary>
        /// 面板状态变化回调（由 WebOverlayForm 调用，可能来自任意线程）。
        /// 仅切换 _panelEscEnabled 标志，不动态改绑 ESC 回调。
        /// </summary>
        public void HandlePanelStateChanged(bool open)
        {
            if (this.InvokeRequired) { try { this.BeginInvoke(new Action<bool>(HandlePanelStateChanged), open); } catch {} return; }

            if (_kbHook != null)
                _kbHook.SetPanelEscapeEnabled(open);
        }

        // ============================================================
        //  全屏
        // ============================================================

        public void ToggleFullscreen()
        {
            if (this.InvokeRequired)
            {
                try { this.BeginInvoke(new Action(ToggleFullscreen)); } catch { }
                return;
            }

            _isFullscreen = !_isFullscreen;
            this.SuspendLayout();

            if (_isFullscreen)
            {
                _savedBounds = this.Bounds;
                _savedBorderStyle = this.FormBorderStyle;
                this.WindowState = FormWindowState.Normal;
                this.FormBorderStyle = FormBorderStyle.None;
                this.WindowState = FormWindowState.Maximized;

                // 全屏时启用 Escape 退出
                if (_kbHook != null) _kbHook.SetEscapeEnabled(true);
                else if (this.IsHandleCreated) RegisterHotKey(this.Handle, HK_ESC, 0, (uint)Keys.Escape);
            }
            else
            {
                this.WindowState = FormWindowState.Normal;
                this.FormBorderStyle = _savedBorderStyle;
                this.Bounds = _savedBounds;

                if (_kbHook != null) _kbHook.SetEscapeEnabled(false);
                else if (this.IsHandleCreated) UnregisterHotKey(this.Handle, HK_ESC);
            }

            this.ResumeLayout(true);

            _flashPanel.Invalidate();
            ScheduleViewportRefresh("toggle_fullscreen");
            LogManager.Log("[Guardian] Fullscreen=" + _isFullscreen);
        }

        private void ScheduleViewportRefresh(string reason)
        {
            _viewportSettleReason = reason;
            RefreshRuntimeViewport(reason + ":immediate");

            if (this.IsHandleCreated)
            {
                try
                {
                    this.BeginInvoke(new Action(delegate()
                    {
                        RefreshRuntimeViewport(reason + ":deferred");
                    }));
                }
                catch { }
            }

            if (_viewportSettleTimer == null)
            {
                _viewportSettleTimer = new System.Windows.Forms.Timer();
                _viewportSettleTimer.Interval = 120;
                _viewportSettleTimer.Tick += delegate
                {
                    if (_viewportSettleTimer != null)
                        _viewportSettleTimer.Stop();
                    RefreshRuntimeViewport(_viewportSettleReason + ":settled_120ms");
                };
            }

            _viewportSettleTimer.Stop();
            _viewportSettleTimer.Start();

            if (!IsDpiRelatedReason(reason))
            {
                if (_viewportLongSettleTimer != null)
                    _viewportLongSettleTimer.Stop();
                return;
            }

            if (_viewportLongSettleTimer == null)
            {
                _viewportLongSettleTimer = new System.Windows.Forms.Timer();
                _viewportLongSettleTimer.Interval = 500;
                _viewportLongSettleTimer.Tick += delegate
                {
                    if (_viewportLongSettleTimer != null)
                        _viewportLongSettleTimer.Stop();
                    RefreshRuntimeViewport(_viewportSettleReason + ":settled_500ms");
                };
            }

            _viewportLongSettleTimer.Stop();
            _viewportLongSettleTimer.Start();
        }

        private static bool IsDpiRelatedReason(string reason)
        {
            return !string.IsNullOrEmpty(reason)
                && reason.IndexOf("dpi", StringComparison.OrdinalIgnoreCase) >= 0;
        }

        private void RefreshRuntimeViewport(string reason)
        {
            if (_windowManager != null)
                _windowManager.ResizeFlashToPanel();
            if (_webOverlay != null)
                _webOverlay.RequestLayoutSync(reason);
        }

        private static Size CalculateInitialBootstrapClientSize()
        {
            Rectangle work = Screen.FromPoint(Cursor.Position).WorkingArea;
            int maxW = Math.Max(800, (int)Math.Floor(work.Width * 0.92));
            int maxH = Math.Max(480, (int)Math.Floor(work.Height * 0.92));

            int w = Math.Min(DesiredBootstrapClientWidth, maxW);
            int h = Math.Min(DesiredBootstrapClientHeight, maxH);
            const double aspect = 16.0 / 9.0;

            if (w / aspect > h)
                w = Math.Max(1, (int)Math.Round(h * aspect));
            else
                h = Math.Max(1, (int)Math.Round(w / aspect));

            if (w < MinimumBootstrapClientWidth && maxW >= MinimumBootstrapClientWidth)
            {
                w = MinimumBootstrapClientWidth;
                h = Math.Min(maxH, Math.Max(1, (int)Math.Round(w / aspect)));
            }
            if (h < MinimumBootstrapClientHeight && maxH >= MinimumBootstrapClientHeight)
            {
                h = MinimumBootstrapClientHeight;
                w = Math.Min(maxW, Math.Max(1, (int)Math.Round(h * aspect)));
            }

            return new Size(Math.Max(800, w), Math.Max(480, h));
        }

        // ============================================================
        //  日志
        // ============================================================

        public void ToggleLog()
        {
            _logVisible = !_logVisible;
            this.SuspendLayout();
            if (_logVisible)
            {
                _logBar.Visible = true;
                _logBar.Height = _logBarH;
            }
            else
            {
                _logBarH = _logBar.Height;
                _logBar.Height = 0;
                _logBar.Visible = false;
            }
            this.ResumeLayout(true);
        }

        private void OnSearchKeyDown(object sender, KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Enter)
            {
                e.SuppressKeyPress = true;
                string query = _searchBox.Text;
                if (string.IsNullOrEmpty(query)) return;

                int idx = _logBox.Text.IndexOf(query, _searchPos, StringComparison.OrdinalIgnoreCase);
                if (idx < 0 && _searchPos > 0)
                    idx = _logBox.Text.IndexOf(query, 0, StringComparison.OrdinalIgnoreCase);

                if (idx >= 0)
                {
                    _logBox.SelectionStart = idx;
                    _logBox.SelectionLength = query.Length;
                    _logBox.ScrollToCaret();
                    _searchPos = idx + query.Length;
                }
                else
                {
                    _searchPos = 0;
                }
            }
            else if (e.KeyCode == Keys.Escape)
            {
                e.SuppressKeyPress = true;
                _searchPos = 0;
                _logBox.SelectionLength = 0;
            }
        }

        // ============================================================
        //  托盘
        // ============================================================

        private void SetupTrayIcon()
        {
            _trayMenu = new ContextMenuStrip();
            _trayMenu.Items.Add("显示", null, delegate { ShowMainWindow(); });
            _trayMenu.Items.Add("日志", null, delegate { ShowMainWindow(); if (!_logVisible) ToggleLog(); });
            _wingsTrayItem = new ToolStripMenuItem(
                "Wings 助手",
                null,
                delegate
                {
                    InvokeAgentRuntimeTrayAction(
                        _showWingsAction,
                        "wings");
                });
            _wingsTrayItem.Visible = false;
            _trayMenu.Items.Add(_wingsTrayItem);
            _agentEnrollmentTrayItem = new ToolStripMenuItem(
                "Agent 开发者授权…",
                null,
                delegate
                {
                    InvokeAgentRuntimeTrayAction(
                        _showAgentEnrollmentAction,
                        "developer_enrollment");
                });
            _agentEnrollmentTrayItem.Visible = false;
            _trayMenu.Items.Add(_agentEnrollmentTrayItem);
            _trayMenu.Items.Add("-");
            _trayMenu.Items.Add("退出", null, delegate { ForceExit(); });

            _trayIcon = new NotifyIcon();
            _trayIcon.Text = "CF7:ME";
            _trayIcon.ContextMenuStrip = _trayMenu;
            // Phase 1 (11b-β): 托盘图标延到 Ready 后可见, 避免 Bootstrap 期"假就绪"印象
            _trayIcon.Visible = false;
            // 发布布局不依赖 Assembly.Location，改用当前进程 exe 路径
            try { _trayIcon.Icon = Icon.ExtractAssociatedIcon(Environment.ProcessPath); }
            catch { _trayIcon.Icon = SystemIcons.Application; }
            _trayIcon.DoubleClick += delegate { ShowMainWindow(); };
        }

        /// <summary>
        /// 注入 Launcher-owned Agent Runtime 入口。菜单仅在对应中立 UI
        /// 已真实装配后可见；null 会立即撤下入口，避免退出竞态调用已释放宿主。
        /// </summary>
        public void SetAgentRuntimeTrayActions(
            Action showWings,
            Action showDeveloperEnrollment)
        {
            if (this.InvokeRequired)
            {
                try
                {
                    this.BeginInvoke(
                        new Action(
                            delegate
                            {
                                SetAgentRuntimeTrayActions(
                                    showWings,
                                    showDeveloperEnrollment);
                            }));
                }
                catch { }
                return;
            }

            _showWingsAction = showWings;
            _showAgentEnrollmentAction =
                showDeveloperEnrollment;
            if (_wingsTrayItem != null)
            {
                _wingsTrayItem.Enabled =
                    showWings != null;
                _wingsTrayItem.Visible =
                    showWings != null;
            }
            if (_agentEnrollmentTrayItem != null)
            {
                _agentEnrollmentTrayItem.Enabled =
                    showDeveloperEnrollment != null;
                _agentEnrollmentTrayItem.Visible =
                    showDeveloperEnrollment != null;
            }
        }

        private static void InvokeAgentRuntimeTrayAction(
            Action action,
            string actionName)
        {
            if (action == null)
                return;
            try
            {
                action();
            }
            catch (Exception ex)
            {
                LogManager.Log(
                    "[Guardian] Agent Runtime tray action "
                    + actionName
                    + " failed: "
                    + ex.GetType().Name);
            }
        }

        /// <summary>Phase 1 (11b-β): Ready 时由 GameLaunchFlow.readyWiring 调用, 显示托盘图标。</summary>
        public void ShowTrayIcon()
        {
            if (_trayIcon == null) return;
            if (this.InvokeRequired)
            {
                try { this.BeginInvoke(new Action(delegate { _trayIcon.Visible = true; })); } catch { }
            }
            else
            {
                _trayIcon.Visible = true;
            }
        }

        private void ShowMainWindow()
        {
            this.Show();
            this.WindowState = FormWindowState.Normal;
            this.BringToFront();
            this.Activate();
        }

        // ============================================================
        //  退出
        // ============================================================

        // Phase A Step A2: OnFormClosing 状态分流 + one-shot latch
        // - Ready / Idle / Error → 直接 ForceExit（legacy 行为，8s ExitGuard 兜底）
        // - 启动中 / Resetting → 异步 Reset(null) + 订阅 OnStateChanged；Idle/Error 终态或 8s 超时 → ForceExit
        // - 三条终态路径共用 _closeTerminated 门闩，只有第一条命中的路径真正调 ForceExit
        private int _closeTerminated;
        private int _exitStarted;
        private volatile bool _closeAlreadyInProgress;
        private string _agentRuntimeExitPreparationToken;
        // Phase D Step D11: OnStateChanged 扩三元 (silentAtEmit), close watcher 签名同步.
        private Action<string, string, bool> _closeStateWatcher;
        private System.Windows.Forms.Timer _closeTimeoutTimer;

        /// <summary>
        /// True from the first controlled-close admission decision until that close either
        /// aborts at the persistence fence or terminates the process. Background HTTP/socket
        /// ingress uses this narrow gate while the UI thread is waiting for Reset/KillFlash.
        /// </summary>
        public bool IsShutdownAdmissionClosed
        {
            get
            {
                return _closeAlreadyInProgress
                    || System.Threading.Interlocked.CompareExchange(
                        ref _exitStarted, 0, 0) != 0;
            }
        }

        private void OnFormClosing(object sender, FormClosingEventArgs e)
        {
            string state = "Idle";
            if (_launchFlow != null)
            {
                try { state = _launchFlow.CurrentState; } catch { }
            }

            // 闪退诊断: 把 CloseReason 写进所有分支, 区分 X-按钮 / Alt+F4 / Application.Exit / WM_QUERYENDSESSION / TaskKill
            string closeReason = e.CloseReason.ToString();

            if (_closeAlreadyInProgress)
            {
                LogManager.Log(
                    "[Guardian] OnFormClosing state=" + state
                    + " reason=" + closeReason
                    + " → close already in progress, suppress");
                e.Cancel = true;
                return;
            }

            // Ready / Idle / Error → legacy 硬退出路径
            if (state == "Ready" || state == "Idle" || state == "Error")
            {
                LogManager.Log("[Guardian] OnFormClosing state=" + state + " reason=" + closeReason + " → DoExit (legacy hard exit)");
                _closeAlreadyInProgress = true;
                System.Threading.Interlocked.Exchange(ref _closeTerminated, 1);
                e.Cancel =
                    !DoExit();
                return;
            }

            // 启动中/Resetting：cancel + 异步等待 Idle/Error
            // 若已被其他路径（重入）终结，阻止 form 默认关闭即可
            if (System.Threading.Interlocked.CompareExchange(ref _closeTerminated, 0, 0) != 0)
            {
                LogManager.Log("[Guardian] OnFormClosing state=" + state + " reason=" + closeReason + " → already terminating, suppress");
                e.Cancel = true;
                return;
            }

            e.Cancel = true;
            _closeAlreadyInProgress = true;
            LogManager.Log("[Guardian] OnFormClosing state=" + state + " reason=" + closeReason + " → async cancel + wait terminal");

            // CharacterBuild admission is Ready-gated, but an external cancel may already have
            // moved a previously Ready session into Resetting. Obtain the same persistence proof
            // before this close path initiates (or joins) Reset; otherwise Reset can kill the only
            // Flash process capable of answering recoverDetach.
            if (!TryPassShutdownFence())
            {
                _closeAlreadyInProgress = false;
                LogManager.Log(
                    "[Guardian] async close cancelled before launch reset by persistence fence");
                return;
            }

            // 订阅 OnStateChanged 等待 Idle/Error (close watcher 不受 silentAtEmit 过滤, 无论静默与否都要反应终态)
            _closeStateWatcher = delegate(string nextState, string msg, bool silentAtEmit)
            {
                if (nextState == "Idle" || nextState == "Error")
                    TerminateCloseOnce("state_" + nextState);
            };
            try { _launchFlow.OnStateChanged += _closeStateWatcher; } catch { }

            // 8s 兜底（语义与 Ready 态 ExitGuard 一致）
            _closeTimeoutTimer = new System.Windows.Forms.Timer();
            _closeTimeoutTimer.Interval = 8000;
            _closeTimeoutTimer.Tick += delegate { TerminateCloseOnce("close_timeout"); };
            _closeTimeoutTimer.Start();

            // 触发异步 Reset（Phase B Step B3: reason 参数已落地）
            try { _launchFlow.Reset(null, "user_close"); }
            catch (Exception ex)
            {
                LogManager.Log("[Guardian] Reset during close failed: " + ex.Message);
                TerminateCloseOnce("reset_exception");
            }
        }

        private void TerminateCloseOnce(string reason)
        {
            if (System.Threading.Interlocked.CompareExchange(ref _closeTerminated, 1, 0) != 0) return;
            LogManager.Log("[Guardian] close terminator fired reason=" + reason);

            try
            {
                if (_closeTimeoutTimer != null)
                {
                    _closeTimeoutTimer.Stop();
                    _closeTimeoutTimer.Dispose();
                    _closeTimeoutTimer = null;
                }
            } catch { }

            try
            {
                if (_closeStateWatcher != null && _launchFlow != null)
                    _launchFlow.OnStateChanged -= _closeStateWatcher;
                _closeStateWatcher = null;
            } catch { }

            // 在 UI 线程上调 ForceExit
            if (this.InvokeRequired)
            {
                try { this.BeginInvoke(new Action(ForceExit)); } catch { try { ForceExit(); } catch { } }
            }
            else
            {
                ForceExit();
            }
        }

        /// <summary>
        /// Phase one of Agent Runtime shutdown. The UI thread closes mutation
        /// admission and proves the persistence fence, but deliberately keeps
        /// the Runtime transport and process alive until every frame in the
        /// success response has been written.
        /// </summary>
        public bool TryPrepareAgentRuntimeExit(string actionId)
        {
            if (string.IsNullOrWhiteSpace(actionId)
                || this.InvokeRequired
                || _closeAlreadyInProgress
                || System.Threading.Interlocked.CompareExchange(
                    ref _exitStarted,
                    0,
                    0) != 0
                || _agentRuntimeExitPreparationToken != null)
            {
                return false;
            }

            _agentRuntimeExitPreparationToken = actionId;
            _closeAlreadyInProgress = true;
            System.Threading.Interlocked.Exchange(
                ref _closeTerminated,
                1);
            if (!TryPassShutdownFence(
                    consumeOnSuccess: false))
            {
                _agentRuntimeExitPreparationToken = null;
                _closeAlreadyInProgress = false;
                System.Threading.Interlocked.Exchange(
                    ref _closeTerminated,
                    0);
                return false;
            }

            LogManager.Log(
                "[Guardian] agent runtime shutdown prepared"
                + " actionId=" + actionId);
            return true;
        }

        /// <summary>
        /// Phase two of Agent Runtime shutdown. The gateway calls this only
        /// after every frame in the terminal success response has been
        /// written.
        /// </summary>
        public void CompleteAgentRuntimeExit(string actionId)
        {
            if (this.InvokeRequired)
            {
                try
                {
                    if (this.IsHandleCreated && !this.IsDisposed)
                    {
                        this.BeginInvoke(
                            new Action(
                                delegate
                                {
                                    CompleteAgentRuntimeExit(
                                        actionId);
                                }));
                    }
                }
                catch { }
                return;
            }
            if (!IsExactAgentRuntimeExitPreparation(actionId))
                return;

            ClearAgentRuntimeExitPreparation();
            LogManager.Log(
                "[Guardian] agent runtime shutdown receipt written"
                + " actionId=" + actionId);
            DoExit(
                false,
                null,
                shutdownFenceAlreadyPassed: true);
        }

        /// <summary>
        /// A response write failure rolls the prepared shutdown back.
        /// The persistence callback remains installed so a later fresh action
        /// must prove the fence again.
        /// </summary>
        public void AbortAgentRuntimeExit(string actionId)
        {
            if (this.InvokeRequired)
            {
                try
                {
                    if (this.IsHandleCreated && !this.IsDisposed)
                    {
                        this.BeginInvoke(
                            new Action(
                                delegate
                                {
                                    AbortAgentRuntimeExit(
                                        actionId);
                                }));
                    }
                }
                catch { }
                return;
            }
            if (!IsExactAgentRuntimeExitPreparation(actionId))
                return;

            ClearAgentRuntimeExitPreparation();
            _closeAlreadyInProgress = false;
            System.Threading.Interlocked.Exchange(
                ref _closeTerminated,
                0);
            LogManager.Log(
                "[Guardian] agent runtime shutdown preparation aborted"
                + " actionId=" + actionId);
        }

        private bool IsExactAgentRuntimeExitPreparation(
            string actionId)
        {
            return !string.IsNullOrWhiteSpace(actionId)
                && string.Equals(
                    _agentRuntimeExitPreparationToken,
                    actionId,
                    StringComparison.Ordinal);
        }

        private void ClearAgentRuntimeExitPreparation()
        {
            _agentRuntimeExitPreparationToken = null;
        }

        public void ForceExit()
        {
            if (this.InvokeRequired)
            {
                bool invoked = false;
                try
                {
                    if (this.IsHandleCreated && !this.IsDisposed)
                    {
                        this.BeginInvoke(
                            new Action(
                                delegate { DoExit(); }));
                        invoked = true;
                    }
                }
                catch { }

                if (!invoked) { CleanupTrayIcon(); Environment.Exit(0); }

                // DoExit 内部已有 exitGuard 前台线程保底，此处无需额外计时
                return;
            }
            DoExit();
        }

        /// <summary>
        /// Explicit destructive exit. Only the closed reason enum may bypass the persistence
        /// fence; invalid enum values fall back to ForceExit and therefore remain fenced.
        /// </summary>
        public void EmergencyExit(
            EmergencyExitReason reason)
        {
            string reasonCode =
                EmergencyExitReasonCodeForTest(
                    reason);
            if (reasonCode == null)
            {
                LogManager.Log(
                    "[Guardian] event=emergency_exit_rejected reason=unknown");
                ForceExit();
                return;
            }

            if (this.InvokeRequired)
            {
                bool invoked = false;
                try
                {
                    if (this.IsHandleCreated
                        && !this.IsDisposed)
                    {
                        this.BeginInvoke(
                            new Action(
                                delegate
                                {
                                    DoExit(
                                        true,
                                        reasonCode);
                                }));
                        invoked = true;
                    }
                }
                catch { }

                if (!invoked)
                {
                    LogManager.Log(
                        "[Guardian] event=emergency_exit reason="
                        + reasonCode
                        + " shutdown_fence=skipped ui_dispatch=unavailable");
                    CleanupTrayIcon();
                    Environment.Exit(0);
                }
                return;
            }

            DoExit(
                true,
                reasonCode);
        }

        internal static string EmergencyExitReasonCodeForTest(
            EmergencyExitReason reason)
        {
            switch (reason)
            {
                case EmergencyExitReason.CtrlQ:
                    return "ctrl_q";
                case EmergencyExitReason.HardExitKeyQ:
                    return "hard_exit_key_q";
                case EmergencyExitReason.FlashExitedReady:
                    return "flash_exited_ready";
                case EmergencyExitReason.FlashZombieWatchdog:
                    return "flash_zombie_watchdog";
                default:
                    return null;
            }
        }

        /// <summary>退出前回调。Program.cs 注入，在 Form dispose 之前断开快车道。</summary>
        public Action OnShutdownEarly;

        /// <summary>
        /// 可取消的退出持久化栅栏。必须在 MarkShuttingDown、8 秒 exit guard 和任何资源清理前
        /// 成功；false 保持进程与 Flash 存活，让玩家稍后重试。
        /// </summary>
        public Func<bool> OnShutdownFence;

        /// <summary>退出前杀 Flash + 停音频。Program.cs 注入，在 ExitThread 之前执行。</summary>
        public Action OnKillFlash;

        private bool TryPassShutdownFence()
        {
            return TryPassShutdownFence(
                consumeOnSuccess: true);
        }

        private bool TryPassShutdownFence(
            bool consumeOnSuccess)
        {
            bool fencePassed = true;
            if (OnShutdownFence != null)
            {
                try
                {
                    fencePassed =
                        OnShutdownFence();
                }
                catch (Exception ex)
                {
                    fencePassed = false;
                    LogManager.Log(
                        "[Guardian] shutdown fence threw "
                        + ex.GetType().Name);
                }
            }
            if (!fencePassed)
            {
                LogManager.Log(
                    "[Guardian] shutdown cancelled by persistence fence");
                return false;
            }
            if (consumeOnSuccess)
                OnShutdownFence = null;
            return true;
        }

        private bool DoExit()
        {
            return DoExit(
                false,
                null);
        }

        private bool DoExit(
            bool skipShutdownFence,
            string emergencyReason)
        {
            return DoExit(
                skipShutdownFence,
                emergencyReason,
                shutdownFenceAlreadyPassed: false);
        }

        private bool DoExit(
            bool skipShutdownFence,
            string emergencyReason,
            bool shutdownFenceAlreadyPassed)
        {
            if (!skipShutdownFence
                && !shutdownFenceAlreadyPassed
                && _agentRuntimeExitPreparationToken != null)
            {
                LogManager.Log(
                    "[Guardian] exit deferred until agent runtime"
                    + " shutdown receipt flush");
                return false;
            }
            if (System.Threading.Interlocked.CompareExchange(
                    ref _exitStarted, 1, 0) != 0)
            {
                return true;
            }

            if (skipShutdownFence)
            {
                ClearAgentRuntimeExitPreparation();
                LogManager.Log(
                    "[Guardian] event=emergency_exit reason="
                    + emergencyReason
                    + " shutdown_fence=skipped");
            }

            if (!skipShutdownFence
                && !shutdownFenceAlreadyPassed
                && !TryPassShutdownFence())
            {
                _closeAlreadyInProgress = false;
                System.Threading.Interlocked.Exchange(
                    ref _closeTerminated, 0);
                System.Threading.Interlocked.Exchange(
                    ref _exitStarted, 0);
                return false;
            }
            // Emergency and prepared exits intentionally consume the callback
            // without invoking it here.
            OnShutdownFence = null;
            GuardianLifecycle.MarkShuttingDown();

            // 最先启动绝对保底线程：独立前台线程，不依赖 ThreadPool/消息循环/任何锁
            // 无论后续清理如何卡死，8 秒后强制终结进程
            Thread exitGuard = new Thread(delegate()
            {
                Thread.Sleep(8000);
                try { LogManager.Log("[Guardian] Exit guard fired — forcing process termination"); } catch { }
                Environment.Exit(1);
            });
            exitGuard.IsBackground = true; // 后台线程：正常退出时随主线程结束；卡死时主线程仍活着，8s 后强杀
            exitGuard.Name = "ExitGuard";
            exitGuard.Start();

            // 最早期断开快车道，防止 dispose 后 FrameTask 推到已释放的 overlay
            if (OnShutdownEarly != null)
            {
                try { OnShutdownEarly(); } catch { }
                OnShutdownEarly = null;
            }
            this.FormClosing -= OnFormClosing;
            DoUnregisterHotkeys();
            CleanupTrayIcon();
            // 在退出消息循环前终结 Flash + 停音频，不依赖 post-Run 清理
            if (OnKillFlash != null)
            {
                try { OnKillFlash(); } catch { }
                OnKillFlash = null;
            }

            if (!_closeAlreadyInProgress)
            {
                try
                {
                    if (!this.IsDisposed && this.IsHandleCreated)
                        this.Close();
                }
                catch { }
            }

            Application.ExitThread();
            return true;
        }

        private void CleanupTrayIcon()
        {
            _showWingsAction = null;
            _showAgentEnrollmentAction = null;
            if (_trayIcon != null)
            {
                try { _trayIcon.Visible = false; _trayIcon.Dispose(); } catch { }
                _trayIcon = null;
            }
            if (_trayMenu != null)
            {
                try { _trayMenu.Dispose(); } catch { }
                _trayMenu = null;
            }
            _wingsTrayItem = null;
            _agentEnrollmentTrayItem = null;
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                ClearAgentRuntimeExitPreparation();
                if (_viewportSettleTimer != null)
                {
                    _viewportSettleTimer.Stop();
                    _viewportSettleTimer.Dispose();
                    _viewportSettleTimer = null;
                }
                if (_viewportLongSettleTimer != null)
                {
                    _viewportLongSettleTimer.Stop();
                    _viewportLongSettleTimer.Dispose();
                    _viewportLongSettleTimer = null;
                }
                StopUiFreezeProbe();
                CleanupTrayIcon();
            }
            base.Dispose(disposing);
        }
    }
}
