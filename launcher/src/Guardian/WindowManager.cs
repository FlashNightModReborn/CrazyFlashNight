using System;
using CF7Launcher.Guardian.InputOwnership;
using System.Diagnostics;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;

namespace CF7Launcher.Guardian
{
    /// <summary>前台采样归属分类（Null=前台真空，Session=本会话窗口，External=外部进程窗口）。</summary>
    internal enum SessionForegroundOwnership
    {
        Null,
        Session,
        External
    }

    internal interface IFlashFocusWindowApi
    {
        IntPtr GetForegroundWindow();
        bool SetForegroundWindow(IntPtr windowHandle);
        bool IsWindow(IntPtr windowHandle);
    }

    /// <summary>
    /// 窗口管理：追踪 Flash 窗口句柄 + 嵌入到宿主 Panel。
    /// </summary>
    public partial class WindowManager
    {
        [DllImport("user32.dll")]
        private static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll")]
        private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetForegroundWindow(IntPtr hWnd);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern void SetLastError(uint dwErrCode);

        [DllImport("user32.dll", CharSet = CharSet.Auto)]
        private static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);

        [DllImport("user32.dll", CharSet = CharSet.Auto)]
        private static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetGUIThreadInfo(uint idThread, ref GUITHREADINFO lpgui);

        [StructLayout(LayoutKind.Sequential)]
        private struct RECT { public int left, top, right, bottom; }

        [StructLayout(LayoutKind.Sequential)]
        private struct GUITHREADINFO
        {
            public int cbSize;
            public int flags;
            public IntPtr hwndActive;
            public IntPtr hwndFocus;
            public IntPtr hwndCapture;
            public IntPtr hwndMenuOwner;
            public IntPtr hwndMoveSize;
            public IntPtr hwndCaret;
            public RECT rcCaret;
        }

        [DllImport("user32.dll", SetLastError = true)]
        private static extern IntPtr SetParent(IntPtr hWndChild, IntPtr hWndNewParent);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);

        [DllImport("user32.dll")]
        private static extern int GetWindowLong(IntPtr hWnd, int nIndex);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);

        [DllImport("user32.dll")]
        private static extern IntPtr GetParent(IntPtr hWnd);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter,
            int X, int Y, int cx, int cy, uint uFlags);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool IsWindow(IntPtr hWnd);

        [DllImport("user32.dll")]
        private static extern IntPtr GetAncestor(
            IntPtr hWnd,
            uint gaFlags);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool IsChild(
            IntPtr hWndParent,
            IntPtr hWnd);

        [DllImport("user32.dll")]
        private static extern IntPtr GetMenu(IntPtr hWnd);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool SetMenu(IntPtr hWnd, IntPtr hMenu);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool DestroyMenu(IntPtr hMenu);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

        // DWMWA_CLOAK：合成器层把 hwnd 从 DWM 合成树挪掉，比 SW_HIDE 走 WM_SHOWWINDOW 那条路快一拍。
        // 仅对顶层窗口生效；SetParent 成 child 之后此状态不再起作用，所以 reveal 时 uncloak 是兜底操作。
        [DllImport("dwmapi.dll")]
        private static extern int DwmSetWindowAttribute(IntPtr hwnd, uint dwAttribute,
            ref int pvAttribute, int cbAttribute);

        private const uint DWMWA_CLOAK = 13;

        private const int SW_HIDE = 0;
        private const int SW_SHOWNOACTIVATE = 4;

        private const int GWL_STYLE = -16;
        private const int WS_CAPTION = 0x00C00000;
        private const int WS_THICKFRAME = 0x00040000;
        private const int WS_BORDER = 0x00800000;
        private const int WS_CHILD = 0x40000000;

        // SetWindowPos flags
        private const uint SWP_NOMOVE = 0x0002;
        private const uint SWP_NOSIZE = 0x0001;
        private const uint SWP_NOZORDER = 0x0004;
        private const uint SWP_FRAMECHANGED = 0x0020;
        private const uint SWP_NOACTIVATE = 0x0010;

        private readonly IFlashFocusWindowApi _focusApi;
        private uint _flashProcessId;
        private uint _guardianProcessId;
        private IntPtr _flashHwnd;
        private Panel _hostPanel;

        // ==================== Phase C: EmbedPhase 单一 owner 协议 ====================
        // ArmEarlyReparent（background poller，hidden reparent）和 EmbedFlashWindow（embedding 阶段，reveal 或 full embed）
        // 两条路径都可能先发现 hwnd；靠 CAS `_embedPhase` 决定谁 own 本 attempt 的 reparent/reveal 流程。
        //
        // 状态转换（仅在 _embedClaimLock 内读写）：
        //   None → EarlyHiddenClaimed → EarlyHiddenDone → RevealedOrFullEmbedded   (正常 early path)
        //   None → RevealedOrFullEmbedded                                            (EmbedFlashWindow 先到：全量路径)
        //
        // ResetEmbedState() 在每次 attempt 结束（Reset/OnFlashExitedExternal/DegradePrewarm）时调用，
        // 清 _currentFlashPid / _embedPhase / _flashHwnd；保证下一个 attempt 从 None 开始、不吃脏句柄。
        private enum EmbedPhase { None, EarlyHiddenClaimed, EarlyHiddenDone, RevealedOrFullEmbedded }
        private readonly object _embedClaimLock = new object();
        private EmbedPhase _embedPhase;
        private int _currentFlashPid;

        private readonly bool _allowForeground = true;
        public WindowManager(bool allowForeground = true)
            : this(new Win32FlashFocusWindowApi(), IntPtr.Zero)
        {
            _allowForeground = allowForeground;
        }

        internal WindowManager(
            IFlashFocusWindowApi focusApi,
            IntPtr initialFlashWindow)
        {
            _focusApi = focusApi
                ?? throw new ArgumentNullException(nameof(focusApi));
            SetTrackedFlashWindow(initialFlashWindow);
        }

        internal SessionInputAuthority PassiveInput {get; private set;}
        private volatile IntPtr _passiveRoot;
        private (bool Known,bool Focused,bool Enabled,IntPtr Focus,IntPtr Source)? _lastAudit;
        private IntPtr _revealedPassiveSource;
        private long _focusSampleCount, _failedFocusQueries, _startupRawFocus, _runtimeRawFocus;
        private long _startupCorrections, _runtimeStyleViolations, _runtimeFocusNotifications;
        private long _lastAuditLog;
        private WinEventCallback _focusEvent;
        private IntPtr _hostFocusHook,_flashFocusHook,_foregroundHook;
        internal event Action PassiveForegroundChanged;
        private uint _auditedPid;
        private delegate void WinEventCallback(IntPtr hook,uint evt,IntPtr hwnd,int obj,int child,uint thread,uint time);
        [DllImport("user32.dll")] private static extern IntPtr SetWinEventHook(uint first,uint last,IntPtr module,
            WinEventCallback callback,uint pid,uint thread,uint flags);
        [DllImport("user32.dll")] private static extern bool UnhookWinEvent(IntPtr hook);
        [DllImport("user32.dll")] private static extern bool IsWindowEnabled(IntPtr hwnd);
        [DllImport("user32.dll")] private static extern bool IsIconic(IntPtr hwnd);
        [DllImport("user32.dll")] private static extern bool EnableWindow(IntPtr hwnd,bool enabled);
        [DllImport("user32.dll")] private static extern short GetAsyncKeyState(int vk);
        internal static bool PassiveKeyHeld(int vk)=>(GetAsyncKeyState(vk)&0x8000)!=0;
        internal bool FlashIsEnabled => _flashHwnd!=IntPtr.Zero && IsWindowEnabled(_flashHwnd);
        internal bool PassiveSessionForeground() => IsPassiveInputWindow(GetForegroundWindow());
        internal bool PassiveShortcutForeground() => IsPassiveInputWindow(GetForegroundWindow(), includeConfig: false);

        internal bool IsPassiveInputWindow(IntPtr window, bool includeConfig = true)
        {
            if (window == IntPtr.Zero || _passiveRoot == IntPtr.Zero || !IsWindowEnabled(_passiveRoot) || IsIconic(_passiveRoot))
                return false;
            if (window == _passiveRoot) return true;
            if (!IsWindowEnabled(window) || !IsSessionOwnedSource(window, _passiveRoot)) return false;
            // Resolve the live top-level HWND. An owned picker, Wings window or other
            // dialog never qualifies merely by sharing the process or root owner.
            var surface = Control.FromHandle(window);
            if (surface is Hud.Dialogue.DialogueInterjectConfigWindow config)
                return includeConfig && config.IsRevealed;
            return surface is WorldCompositor.WorldCompositionSurface or WebOverlayForm or CompositionHelpSurface
                or SceneTransitionBackingForm or ModifierNativeSurface or ModifierInputOverlay
                or NativeHudOverlay or Hud.Dialogue.DialogueInterjectInputOverlay;
        }
        internal void ConfigurePassiveInput(SessionInputAuthority input, Form root)
        {
            ArgumentNullException.ThrowIfNull(input);
            ArgumentNullException.ThrowIfNull(root);
            if (ReferenceEquals(input, PassiveInput) && ReferenceEquals(root, _sessionRoot)
                && _foregroundHook != IntPtr.Zero && _hostFocusHook != IntPtr.Zero) return;
            StopPassiveFocusAudit();
            if (PassiveInput != null && !ReferenceEquals(PassiveInput, input)) {
                PassiveInput.SetForeground(false);
                PassiveInput.SetBusinessEligible(false, "session_rebound");
            }
            ConfigureSessionRoot(root);
            PassiveInput = input;
            ApplyPassiveStyle(_flashHwnd);
            const uint foregroundEvent = 0x0003; // EVENT_SYSTEM_FOREGROUND
            _focusEvent=(_,evt,window,_,_,_,eventTime)=> {
                if (evt != foregroundEvent) {
                    IntPtr flash = _flashHwnd;
                    if (flash != IntPtr.Zero && flash == _revealedPassiveSource && InsideFlash(flash, window)) {
                        Interlocked.Increment(ref _runtimeFocusNotifications);
                        PassiveInput.SetForeground(false);
                        LogManager.Log($"event=passive_focus_notification stage=runtime hwnd=0x{window:X} flash=0x{flash:X} eventTime={eventTime}");
                    }
                    if (_flashHwnd != IntPtr.Zero && AuditPassiveFocus(out _)) QueuePassiveBootstrapRecovery();
                    return;
                }
                // Even a short excursion between two UI ticks invalidates the old
                // observation generation. Only a fresh sample may requalify input.
                if (!IsPassiveInputWindow(window)) PassiveInput.SetForeground(false);
                if (!IsPassiveInputWindow(window, includeConfig: false))
                    PassiveInput.SetBusinessEligible(false, "foreground_lost");
                if (window == _passiveRoot) QueuePassiveBootstrapRecovery();
                PassiveForegroundChanged?.Invoke();
            };
            _foregroundHook=SetWinEventHook(foregroundEvent,foregroundEvent,IntPtr.Zero,_focusEvent,0,0,0);
            _hostFocusHook=SetWinEventHook(0x8005,0x8005,IntPtr.Zero,_focusEvent,(uint)Environment.ProcessId,0,0);
        }
        internal void StopPassiveFocusAudit()
        {
            CancelPassiveBootstrapPublication();
            if(_hostFocusHook!=IntPtr.Zero)UnhookWinEvent(_hostFocusHook);
            if(_flashFocusHook!=IntPtr.Zero)UnhookWinEvent(_flashFocusHook);
            if(_foregroundHook!=IntPtr.Zero)UnhookWinEvent(_foregroundHook);
            _hostFocusHook=_flashFocusHook=_foregroundHook=IntPtr.Zero; _auditedPid=0;
        }
        private void ApplyPassiveStyle(IntPtr flash)
        {
            if(flash!=IntPtr.Zero && IsWindowEnabled(flash))
                EnableWindow(flash,false);
        }
        private static bool InsideFlash(IntPtr flash, IntPtr window)
        {
            return flash != IntPtr.Zero && (window == flash || (window != IntPtr.Zero && IsChild(flash, window)));
        }

        private bool SettleBootstrapFocus(IntPtr flash, string stage)
        {
            if (PassiveInput == null || flash == IntPtr.Zero || flash != _flashHwnd || flash == _revealedPassiveSource)
                return false;
            AuditPassiveFocus(out bool before, stage + "_before");
            bool attempted = false;
            if (before && _sessionRoot != null && !_sessionRoot.IsDisposed && !_sessionRoot.InvokeRequired
                && GetParent(flash) != IntPtr.Zero)
            {
                IntPtr foreground = ReadCloseForeground();
                if (InsideFlash(flash, foreground) || IsPassiveInputWindow(foreground))
                {
                    Control target = _hostPanel?.CanFocus == true ? _hostPanel : _sessionRoot.CanFocus ? _sessionRoot : null;
                    if (target != null && ReadCloseForeground() == foreground && flash == _flashHwnd)
                    {
                        attempted = true;
                        Interlocked.Increment(ref _startupCorrections);
                        target.Focus();
                    }
                }
            }
            bool valid = AuditPassiveFocus(out bool after, stage + "_after");
            LogManager.Log($"event=passive_bootstrap_focus stage={stage} flash=0x{flash:X} before={before} attempted={attempted} after={after} valid={valid}");
            return valid;
        }

        internal object PassiveFocusCounts() => new {
            samples = Interlocked.Read(ref _focusSampleCount), failedQueries = Interlocked.Read(ref _failedFocusQueries),
            startupRawFocus = Interlocked.Read(ref _startupRawFocus), startupCorrections = Interlocked.Read(ref _startupCorrections),
            runtimeRawFocus = Interlocked.Read(ref _runtimeRawFocus), runtimeFocusNotifications = Interlocked.Read(ref _runtimeFocusNotifications),
            runtimeStyleViolations = Interlocked.Read(ref _runtimeStyleViolations),
            sourceHook = _flashFocusHook != IntPtr.Zero, hostHook = _hostFocusHook != IntPtr.Zero
        };

        internal bool RefreshPassiveFocusAdmission()
        {
            if (AuditPassiveFocus(out _))
            {
                PassiveBootstrapPublication pending = Volatile.Read(ref _pendingPassiveBootstrap);
                return pending == null || TryPublishPassiveBootstrap(pending, "passive_focus_available");
            }
            IntPtr flash = _flashHwnd;
            if (flash != IntPtr.Zero && IsWindowEnabled(flash))
            {
                // A foreign re-enable closes admission on this sample. Enforce the disabled
                // style, then require a later observation before any new grant.
                Interlocked.Increment(ref _runtimeStyleViolations);
                ApplyPassiveStyle(flash);
                LogManager.Log($"event=passive_source_style_violation flash=0x{flash:X} enabledAfter={IsWindowEnabled(flash)}");
            }
            return false;
        }
        private readonly record struct PassiveFocusSample(bool Known, bool Focused, bool Enabled, IntPtr Focus,
            IntPtr SourceThreadFocus, IntPtr RootThreadFocus);

        private PassiveFocusSample ReadPassiveFocusSample(IntPtr flash, IntPtr root, uint sourceThread, bool matchingSource)
        {
#if CF7_TEST_SEAMS
            if (PassiveBootstrapFocusForTests != null)
            {
                var sample = PassiveBootstrapFocusForTests();
                IntPtr focusWindow = sample.Focused ? flash : root;
                return new(sample.Known, sample.Focused, sample.Enabled, focusWindow, focusWindow, focusWindow);
            }
#endif
            var info=new GUITHREADINFO{cbSize=Marshal.SizeOf<GUITHREADINFO>()};
            uint rootThread = root == IntPtr.Zero ? 0 : GetWindowThreadProcessId(root, out _);
            var rootInfo=info;
            bool known = matchingSource && sourceThread != 0 && rootThread != 0
                && GetGUIThreadInfo(sourceThread, ref info) && GetGUIThreadInfo(rootThread, ref rootInfo);
            bool focused = known && (InsideFlash(flash, info.hwndFocus) || InsideFlash(flash, rootInfo.hwndFocus));
            IntPtr focus=InsideFlash(flash,info.hwndFocus) || rootInfo.hwndFocus==IntPtr.Zero ? info.hwndFocus : rootInfo.hwndFocus;
            bool enabled=flash!=IntPtr.Zero && IsWindowEnabled(flash);
            return new(known, focused, enabled, focus, info.hwndFocus, rootInfo.hwndFocus);
        }

        internal bool ReadPassiveFocus(out bool flashFocused)
        {
            flashFocused = false;
            if (PassiveInput == null) return false;
            IntPtr flash = _flashHwnd, root = _passiveRoot;
            if (flash == IntPtr.Zero || root == IntPtr.Zero) return false;
            uint tid = GetWindowThreadProcessId(flash, out uint sourcePid);
            var sample = ReadPassiveFocusSample(flash, root, tid, sourcePid == _flashProcessId);
            if (flash != _flashHwnd || root != _passiveRoot || sourcePid != _flashProcessId) return false;
            flashFocused = sample.Focused;
            return sample.Known;
        }

        internal bool AuditPassiveFocus(out bool flashFocused, string stimulus = null)
        {
            flashFocused = false;
            if (PassiveInput == null) return false;
            IntPtr flash = _flashHwnd, root = _passiveRoot;
            uint pid = 0, tid = flash == IntPtr.Zero ? 0 : GetWindowThreadProcessId(flash, out pid);
            if (pid != _auditedPid) {
                if (_flashFocusHook != IntPtr.Zero) UnhookWinEvent(_flashFocusHook);
                _auditedPid = pid;
                _flashFocusHook = pid == 0 ? IntPtr.Zero : SetWinEventHook(0x8005, 0x8005, IntPtr.Zero, _focusEvent, pid, 0, 0);
            }
            var sample = ReadPassiveFocusSample(flash, root, tid, pid == _flashProcessId);
            bool known = sample.Known;
            bool runtime = flash != IntPtr.Zero && flash == _revealedPassiveSource;
            flashFocused = sample.Focused;
            Interlocked.Increment(ref _focusSampleCount);
            if(!known)Interlocked.Increment(ref _failedFocusQueries);
            if(flashFocused) {
                if(runtime)Interlocked.Increment(ref _runtimeRawFocus);
                else Interlocked.Increment(ref _startupRawFocus);
            }
            bool valid = known && !flashFocused && !sample.Enabled && flash == _flashHwnd && root == _passiveRoot
                && pid == _flashProcessId;
            if(!valid)PassiveInput.SetForeground(false);
            var state=(known,flashFocused,sample.Enabled,sample.Focus,flash);
            if(state!=_lastAudit || stimulus!=null || Environment.TickCount64-_lastAuditLog>=1000) {
                _lastAudit=state; _lastAuditLog=Environment.TickCount64;
                LogManager.Log($"event=r1_passive_focus_audit mode={PassiveInput.Mode} flashFocused={flashFocused} root=0x{root:X} focus=0x{sample.Focus:X} flash=0x{flash:X} queried={known} enabled={sample.Enabled} stage={(runtime?"runtime":"bootstrap")} sourceThreadFocus=0x{sample.SourceThreadFocus:X} rootThreadFocus=0x{sample.RootThreadFocus:X}"+(stimulus==null?"":" stimulus="+stimulus));
            }
            return valid;
        }
        public IntPtr FlashHwnd { get { return _flashHwnd; } }

        private sealed class Win32FlashFocusWindowApi
            : IFlashFocusWindowApi
        {
            public IntPtr GetForegroundWindow()
            {
                return WindowManager.GetForegroundWindow();
            }

            public bool SetForegroundWindow(
                IntPtr windowHandle)
            {
                return WindowManager.SetForegroundWindow(
                    windowHandle);
            }

            public bool IsWindow(IntPtr windowHandle)
            {
                return WindowManager.IsWindow(windowHandle);
            }
        }

        /// <summary>
        /// Phase 1c：嵌入结果事件。true = 成功嵌入；false = 10s 内未找到 Flash 窗口或外部主动通知失败。
        /// 触发封送到 _hostPanel 所在的 UI 线程（不变式 #5）。
        /// </summary>
        private void FireEmbedResult(Action<bool> handler, bool success)
        {
            if (handler == null) return;

            Control target = _hostPanel;
            if (target != null && target.IsHandleCreated && target.InvokeRequired)
            {
                try { target.BeginInvoke(new Action(delegate { handler(success); })); }
                catch { handler(success); }
            }
            else
            {
                handler(success);
            }
        }

        private static void LogWin32Failure(string action, IntPtr hwnd)
        {
            int err = Marshal.GetLastWin32Error();
            LogWin32Failure(action, hwnd, err);
        }

        private static void LogWin32Failure(string action, IntPtr hwnd, int err)
        {
            LogManager.Log("[WindowManager] " + action + " failed hwnd=0x" + hwnd.ToString("X")
                + " err=" + err.ToString(CultureInfo.InvariantCulture));
            StartupDiagnostics.Warn("window_manager.win32_failed",
                action + " hwnd=0x" + hwnd.ToString("X") + " err=" + err.ToString(CultureInfo.InvariantCulture));
        }

        private static void SetParentLogged(IntPtr hwnd, IntPtr parent, string action)
        {
            SetLastError(0);
            IntPtr previous = SetParent(hwnd, parent);
            int err = Marshal.GetLastWin32Error();
            if (previous == IntPtr.Zero && err != 0)
                LogWin32Failure(action, hwnd, err);
        }

        private static void SetWindowLongLogged(IntPtr hwnd, int index, int value, string action)
        {
            SetLastError(0);
            int previous = SetWindowLong(hwnd, index, value);
            int err = Marshal.GetLastWin32Error();
            if (previous == 0 && err != 0)
                LogWin32Failure(action, hwnd, err);
        }

        private sealed class Win32FlashMenuApi : IFlashMenuWindowApi
        {
            public IntPtr GetMenu(IntPtr window) => WindowManager.GetMenu(window);
            public bool DetachMenu(IntPtr window) => SetMenu(window, IntPtr.Zero);
            public bool DestroyMenu(IntPtr menu) => WindowManager.DestroyMenu(menu);
        }

        private static readonly IFlashMenuWindowApi FlashMenuApi = new Win32FlashMenuApi();

        internal static void ApplyFlashChildStyle(IntPtr hwnd, string phase)
        {
            int style = GetWindowLong(hwnd, GWL_STYLE);
            // 普通菜单必须在 WS_CHILD 之前摘除；已有 child 的重嵌入只规范化样式。
            if (!FlashWindowMenuPolicy.RemoveMenuBeforeChildStyle(hwnd, style, FlashMenuApi))
                LogWin32Failure("RemoveMenu(" + phase + ")", hwnd);

            SetWindowLongLogged(hwnd, GWL_STYLE, FlashWindowMenuPolicy.EmbeddedStyle(style),
                "SetWindowLong(" + phase + " WS_CHILD)");
        }

        private static void LogHResultFailure(string action, IntPtr hwnd, int hr)
        {
            LogManager.Log("[WindowManager] " + action + " failed hwnd=0x" + hwnd.ToString("X")
                + " hr=0x" + hr.ToString("X8", CultureInfo.InvariantCulture));
            StartupDiagnostics.Warn("window_manager.hresult_failed",
                action + " hwnd=0x" + hwnd.ToString("X") + " hr=0x" + hr.ToString("X8", CultureInfo.InvariantCulture));
        }

        /// <summary>
        /// Phase 1c：外部（如 GameLaunchFlow 检测异常）主动通知嵌入失败。
        /// </summary>
        internal void NotifyEmbedFailure(Action<bool> completed)
        {
            FireEmbedResult(completed, false);
        }

        public void TrackProcess(Process flashProcess)
        {
            if (flashProcess != null)
                _flashProcessId = (uint)flashProcess.Id;
            _guardianProcessId = (uint)Process.GetCurrentProcess().Id;
        }

        /// <summary>
        /// Phase C: 清除 embed 状态机字段，为下一个 attempt 归零.
        /// 调用点：Reset / OnFlashExitedExternal 非退出分支 / DegradePrewarmFailureLocked（Phase D）.
        /// 整进程退出路径不需要调（DetachFlash + GC 自动带走）.
        /// </summary>
        public void ResetEmbedState()
        {
            lock (_embedClaimLock)
            {
                _currentFlashPid = 0;
                _embedPhase = EmbedPhase.None;
                SetTrackedFlashWindow(IntPtr.Zero);
            }
            LogManager.Log("[WindowManager] EmbedState reset");
        }

        /// <summary>
        /// Phase C: poll Flash 主窗口句柄.
        /// 关键：MainWindowHandle 走 .NET IsMainWindow 启发式（owner==0 + IsWindowVisible），
        /// Flash SA spawn 早期建的辅助/loader 窗口会被自动过滤；只在真主窗口出现后返回非零.
        /// 不要换成 EnumWindows 自己挑（splash 窗口同样满足 WS_CAPTION + 非空标题，会选错）.
        ///
        /// 调度：WaitForInputIdle 仅在外层调一次（process 进入消息循环空闲就结束阻塞），
        /// 之后 5ms 紧凑轮询直到 hwnd 出现或超时. 原版 100ms 轮询的"flash 200ms"主因是这.
        /// </summary>
        private static IntPtr PollMainWindowHandle(Process flashProcess, int timeoutMs)
        {
            try { flashProcess.WaitForInputIdle(2000); } catch { }

            long deadline = DateTime.UtcNow.Ticks + TimeSpan.FromMilliseconds(timeoutMs).Ticks;
            while (DateTime.UtcNow.Ticks < deadline)
            {
                try
                {
                    flashProcess.Refresh();
                    IntPtr hwnd = flashProcess.MainWindowHandle;
                    if (hwnd != IntPtr.Zero) return hwnd;
                }
                catch { }
                Thread.Sleep(5);
            }
            return IntPtr.Zero;
        }

        /// <summary>
        /// Phase C: 把 Flash 窗口 SW_HIDE + 去边框 + SetParent 到隐藏宿主 Panel.
        /// 不触发 FireEmbedResult（那由 EmbedFlashWindow reveal 路径终点负责），不绑 resize，不启 watchdog.
        /// 后台线程调用.
        /// </summary>
        private void ReparentToHidden(IntPtr hwnd, Panel hiddenHost)
        {
            // 0) DWM cloak — 合成器层先把 hwnd 摘出去，争取在下一次 vsync 之前生效，
            //    与 SW_HIDE 配合压低"被合成 1 帧"的概率. 失败/不支持安静吞掉.
            int cloakOn = 1;
            try
            {
                DwmSetWindowAttribute(hwnd, DWMWA_CLOAK, ref cloakOn, sizeof(int));
            }
            catch { }

            // 1) 立即 SW_HIDE 减少首帧 top-level 可见窗口时间
            ShowWindow(hwnd, SW_HIDE);

            // 2-3) 先摘除普通菜单，再去边框 / 系统菜单并设为 WS_CHILD。
            ApplyFlashChildStyle(hwnd, "hidden");

            // 4) SWP_FRAMECHANGED 强制非客户区重算
            if (!SetWindowPos(hwnd, IntPtr.Zero, 0, 0, 0, 0,
                SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED | SWP_NOACTIVATE))
                LogWin32Failure("SetWindowPos(hidden framechanged)", hwnd);

            // 5) SetParent 到隐藏宿主
            SetParentLogged(hwnd, hiddenHost.Handle, "SetParent(hidden host)");

            // 6) MoveWindow(..., repaint=false) — hidden 状态不请求重绘
            int w = hiddenHost.Width;
            int h = hiddenHost.Height;
            if (w < 1) w = 1;
            if (h < 1) h = 1;
            if (!MoveWindow(hwnd, 0, 0, w, h, false))
                LogWin32Failure("MoveWindow(hidden host)", hwnd);

            LogManager.Log("[WindowManager] Flash reparented to hidden host hwnd=0x" + hwnd.ToString("X"));
        }

        /// <summary>
        /// Phase C Step C1: 在 Flash spawn 后立即 arm 的后台 poller.
        /// 10s 内找到 Flash 主窗口 → SW_HIDE + SetParent 到 hiddenHost（不 Show，不 Fire）.
        /// 若 EmbedFlashWindow 抢先 claim（None→RevealedOrFullEmbedded），本 poller 降级放弃.
        /// 内部 ThreadPool.QueueUserWorkItem 派发 — 调用方直接调，不阻塞 UI.
        ///
        /// 历史教训：尝试过 SetWinEventHook 事件驱动 + WS_CAPTION/title 过滤替代轮询，
        /// 实测 hook 在 spawn 后 ~57ms 命中，但 Flash SA 早期会先建一个带标题的辅助/loader 窗口
        /// （短命；满足 owner==0+WS_CAPTION+非空标题），hook 在它上面命中后真主窗口反而漏处理.
        /// MainWindowHandle 走的是 .NET IsMainWindow 启发式（owner==0+IsWindowVisible），
        /// 自带"等真主窗口"的隐式时序，唯一可靠源.
        /// </summary>
        public void ArmEarlyReparent(Process flashProc, Panel hiddenHost, Action<IntPtr> afterFlashHides = null)
        {
            if (flashProc == null || hiddenHost == null) return;
            int pid = flashProc.Id;

            // 立即记录 pid，EmbedFlashWindow 据此做身份校验（attempt 换一轮时清零）
            lock (_embedClaimLock)
            {
                _currentFlashPid = pid;
                // _embedPhase 已由 ResetEmbedState() 归零为 None
            }
            _hostPanel = hiddenHost;  // 早期绑定，供后续 reveal 读 Width/Height

            System.Threading.ThreadPool.QueueUserWorkItem(delegate
            {
                try
                {
                    IntPtr hwnd = PollMainWindowHandle(flashProc, 10000);
                    if (hwnd == IntPtr.Zero)
                    {
                        LogManager.Log("[WindowManager] ArmEarlyReparent: hwnd not found in 10s, surrendering to EmbedFlashWindow");
                        return;
                    }

                    bool claimed = false;
                    lock (_embedClaimLock)
                    {
                        if (_currentFlashPid != pid) return;                         // attempt 已换
                        if (_embedPhase != EmbedPhase.None) return;                  // EmbedFlashWindow 抢先 → 它全权处理
                        _embedPhase = EmbedPhase.EarlyHiddenClaimed;
                        claimed = true;
                    }

                    if (!claimed) return;
                    ApplyPassiveStyle(hwnd);

                    try
                    {
                        bool flashTookForeground = afterFlashHides != null && HoldsForeground(hwnd);
                        ReparentToHidden(hwnd, hiddenHost);
                        lock (_embedClaimLock)
                        {
                            if (_currentFlashPid == pid && _flashHwnd == IntPtr.Zero)
                                SetTrackedFlashWindow(hwnd);
                        }
                        if (flashTookForeground && hiddenHost.IsHandleCreated)
                            hiddenHost.BeginInvoke(afterFlashHides, hwnd);
                        if (PassiveInput != null && hiddenHost.IsHandleCreated)
                            hiddenHost.BeginInvoke(new Action(() => SettleBootstrapFocus(hwnd, "early_reparent")));
                    }
                    finally
                    {
                        lock (_embedClaimLock)
                        {
                            if (_currentFlashPid == pid && _flashHwnd == IntPtr.Zero)
                                SetTrackedFlashWindow(hwnd);
                            // 若期间 EmbedFlashWindow 覆盖为 Revealed（理论上不应该，因为 Claimed 状态会阻止它），
                            // 保留 Revealed；正常完成 Claimed → Done
                            if (_embedPhase == EmbedPhase.EarlyHiddenClaimed)
                                _embedPhase = EmbedPhase.EarlyHiddenDone;
                        }
                    }
                }
                catch (Exception ex)
                {
                    LogManager.Log("[WindowManager] ArmEarlyReparent worker error: " + ex.Message);
                }
            });
        }

        /// <summary>
        /// Phase C: Embedding 态的 reveal/全量 embed 驱动.
        /// 通过 _embedPhase CAS 与 ArmEarlyReparent 单一 owner 协调:
        ///   - EarlyHiddenDone → Reveal only (SW_SHOW + MoveWindow + resize binding + watchdog)
        ///   - EarlyHiddenClaimed → spin 等 Done（1s 上限），超时降级为 needFullEmbed 幂等兜底
        ///   - None → 全量路径（自己 poll hwnd + style + SetParent + MoveWindow + Show + resize + watchdog）
        /// The matching attempt advances from Embedding only after this source is safe to publish.
        /// </summary>
        internal void EmbedFlashWindow(Process flashProcess, Panel hostPanel, Action<bool> completed)
        {
            int pid = (flashProcess != null) ? flashProcess.Id : 0;

            IntPtr hwnd = IntPtr.Zero;
            bool needFullEmbed = false;
            bool mustWaitForEarlyDone = false;

            lock (_embedClaimLock)
            {
                if (pid == 0 || _flashProcessId != (uint)pid) return;
                _hostPanel = hostPanel;
                if (_currentFlashPid != pid)
                {
                    // attempt 已换，脏句柄清零，走全量路径
                    _currentFlashPid = pid;
                    _embedPhase = EmbedPhase.None;
                    SetTrackedFlashWindow(IntPtr.Zero);
                }

                if (_embedPhase == EmbedPhase.EarlyHiddenDone)
                {
                    hwnd = _flashHwnd;
                    needFullEmbed = false;
                }
                else if (_embedPhase == EmbedPhase.EarlyHiddenClaimed)
                {
                    // ArmEarlyReparent 正在 reparent；spin 等到 EarlyHiddenDone 再读 hwnd
                    mustWaitForEarlyDone = true;
                    needFullEmbed = false;
                }
                else  // None（EmbedFlashWindow 抢先；或 ArmEarlyReparent 已放弃 10s timeout）
                {
                    _embedPhase = EmbedPhase.RevealedOrFullEmbedded;  // 占位阻止 ArmEarlyReparent 晚到覆盖
                    needFullEmbed = true;
                }
            }

            if (needFullEmbed)
            {
                hwnd = PollMainWindowHandle(flashProcess, 10000);
                if (hwnd == IntPtr.Zero)
                {
                    LogManager.Log("[WindowManager] Flash window not found (full-embed path), embedding skipped");
                    FireEmbedResult(completed, false);
                    return;
                }
                ApplyPassiveStyle(hwnd);
                LogManager.Log("[WindowManager] Flash window found (full-embed path): 0x" + hwnd.ToString("X"));
            }
            else if (mustWaitForEarlyDone)
            {
                // 最多 1s（20 × 50ms）等 ArmEarlyReparent 的 finally 块推到 EarlyHiddenDone
                for (int i = 0; i < 20; i++)
                {
                    lock (_embedClaimLock)
                    {
                        if (_embedPhase == EmbedPhase.EarlyHiddenDone)
                        {
                            hwnd = _flashHwnd;
                            break;
                        }
                    }
                    if (hwnd != IntPtr.Zero) break;
                    Thread.Sleep(50);
                }

                if (hwnd == IntPtr.Zero)
                {
                    // 异常降级：ArmEarlyReparent 卡死/异常；兜底自己重做完整 reparent（幂等）
                    lock (_embedClaimLock)
                    {
                        IntPtr late = _flashHwnd;
                        if (late != IntPtr.Zero)
                        {
                            hwnd = late;
                            needFullEmbed = true;
                            _embedPhase = EmbedPhase.RevealedOrFullEmbedded;
                        }
                    }
                    if (hwnd == IntPtr.Zero)
                    {
                        IntPtr polled = PollMainWindowHandle(flashProcess, 2000);
                        if (polled != IntPtr.Zero)
                        {
                            lock (_embedClaimLock)
                            {
                                hwnd = polled;
                                needFullEmbed = true;
                                _embedPhase = EmbedPhase.RevealedOrFullEmbedded;
                            }
                        }
                    }
                    if (hwnd == IntPtr.Zero)
                    {
                        LogManager.Log("[WindowManager] EmbedFlashWindow: early-reparent spin timeout, no hwnd, fail");
                        FireEmbedResult(completed, false);
                        return;
                    }
                    LogManager.Log("[WindowManager] EmbedFlashWindow: spin timeout, degrading to full-embed");
                }
                else
                {
                    LogManager.Log("[WindowManager] Flash window found (reveal path): 0x" + hwnd.ToString("X"));
                }
            }
            else
            {
                // EarlyHiddenDone 路径，hwnd 已读
                LogManager.Log("[WindowManager] Flash window found (reveal path): 0x" + hwnd.ToString("X"));
            }

            // Prepare the source on the UI thread. Publishing success also
            // requires the exact passive source to pass its focus audit.
            IntPtr hwndSnap = hwnd;
            bool fullSnap = needFullEmbed;
            void CompleteOnUi()
            {
                if (_currentFlashPid != pid || _flashProcessId != (uint)pid || !ReferenceEquals(_hostPanel, hostPanel))
                    return;
                if (hostPanel.IsDisposed || hostPanel.Disposing || !hostPanel.IsHandleCreated
                    || GetWindowThreadProcessId(hwndSnap, out uint sourcePid) == 0 || sourcePid != (uint)pid)
                {
                    FireEmbedResult(completed, false);
                    return;
                }
                DoEmbedOrReveal(hwndSnap, fullSnap);
                if (PassiveInput == null) FireEmbedResult(completed, true);
                else StagePassiveBootstrapPublication(hwndSnap, sourcePid, hostPanel, completed);
            }
            if (hostPanel.InvokeRequired)
            {
                hostPanel.BeginInvoke(new Action(CompleteOnUi));
            }
            else
            {
                CompleteOnUi();
            }
        }

        /// <summary>
        /// Phase C: UI 线程终点. needFullEmbed=true 走完整 style+SetParent+Show；false 仅 Show+MoveWindow.
        /// 两条路径都 bind resize + 启动 watchdog + 推 _embedPhase 到 RevealedOrFullEmbedded.
        /// </summary>
        private void DoEmbedOrReveal(IntPtr hwnd, bool needFullEmbed)
        {
            if (hwnd == IntPtr.Zero || _hostPanel == null)
                return;

            ApplyPassiveStyle(hwnd);
            if (needFullEmbed)
            {
                // 完整路径与启动 hidden 路径共用菜单 / 子窗口样式处理。
                ApplyFlashChildStyle(hwnd, "embed");

                if (!SetWindowPos(hwnd, IntPtr.Zero, 0, 0, 0, 0,
                    SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED | SWP_NOACTIVATE))
                    LogWin32Failure("SetWindowPos(embed framechanged)", hwnd);
                SetParentLogged(hwnd, _hostPanel.Handle, "SetParent(embed host)");
                lock (_embedClaimLock)
                {
                    if (_flashHwnd == IntPtr.Zero) SetTrackedFlashWindow(hwnd);
                }
            }

            // 两路径公用：先 uncloak（早 path 在 ReparentToHidden 时打过 DWMWA_CLOAK；child 化后理论无效，
            // 但有些路径下 cloak 状态会被 DWM 留存，uncloak 是兜底），再 SW_SHOW.
            int cloakOff = 0;
            try
            {
                DwmSetWindowAttribute(hwnd, DWMWA_CLOAK, ref cloakOff, sizeof(int));
            }
            catch { }
            ShowWindow(hwnd, SW_SHOWNOACTIVATE);
            ResizeFlashToPanel();
            ApplyPassiveStyle(hwnd);

            _hostPanel.Resize -= OnHostPanelResize;
            _hostPanel.Resize += OnHostPanelResize;

            StartEmbedWatchdog();

            lock (_embedClaimLock) { _embedPhase = EmbedPhase.RevealedOrFullEmbedded; }

            LogManager.Log("[WindowManager] Flash window embedded (path=" + (needFullEmbed ? "full" : "reveal") + ")");
        }

        private void OnHostPanelResize(object sender, EventArgs e)
        {
            ResizeFlashToPanel();
        }

        private System.Windows.Forms.Timer _watchdog;

        /// <summary>
        /// 每 500ms 检测 Flash 窗口是否脱离嵌入（全屏切换会破坏 SetParent 关系），
        /// 发现脱离后自动重新嵌入。
        /// </summary>
        private void StartEmbedWatchdog()
        {
            if (_watchdog != null) return;

            _watchdog = new System.Windows.Forms.Timer();
            _watchdog.Interval = 500;
            _watchdog.Tick += delegate
            {
                if (_flashHwnd == IntPtr.Zero || _hostPanel == null)
                    return;

                // Flash 窗口已销毁（进程退出），停止监控.
                // 必须 Dispose + null，否则下一 attempt 的 StartEmbedWatchdog 会因 _watchdog != null
                // 直接 return（见该方法的早退守卫），导致第二次及之后的嵌入失去脱嵌恢复保护.
                if (!IsWindow(_flashHwnd))
                {
                    PassiveBootstrapPublication pending = Volatile.Read(ref _pendingPassiveBootstrap);
                    SetTrackedFlashWindow(IntPtr.Zero);
                    System.Windows.Forms.Timer dying = _watchdog;
                    _watchdog = null;
                    try { dying.Stop(); dying.Dispose(); } catch { }
                    LogManager.Log("[WindowManager] Flash window destroyed, watchdog stopped+disposed");
                    if (pending != null) FireEmbedResult(pending.Completed, false);
                    return;
                }

                IntPtr currentParent = GetParent(_flashHwnd);
                if (currentParent != _hostPanel.Handle)
                {
                    // Flash 窗口脱离了嵌入（全屏切换等），重新嵌入（走完整路径重建 WS_CHILD + SetParent）
                    LogManager.Log("[WindowManager] Flash window detached, re-embedding...");
                    DoEmbedOrReveal(_flashHwnd, /*needFullEmbed*/ true);
                }
            };
            _watchdog.Start();
        }

        public void ResizeFlashToPanel()
        {
            ResizeFlashToPanelCore();
        }

        private bool ResizeFlashToPanelCore()
        {
            if (_flashHwnd == IntPtr.Zero || _hostPanel == null)
                return false;
            ApplyPassiveStyle(_flashHwnd);
            var physical = ResolveFlashRenderSize();
            if (!MoveWindow(_flashHwnd, 0, 0, physical.Width, physical.Height, true)) {
                LogWin32Failure("MoveWindow(resize)", _flashHwnd);
                return false;
            }
            return UpdateFlashRenderSize();
        }

        /// <summary>停止嵌入看门狗定时器。退出时在 DetachFlash 前调用。</summary>
        public void StopWatchdog()
        {
            if (_watchdog != null)
            {
                _watchdog.Stop();
                _watchdog.Dispose();
                _watchdog = null;
            }
        }

        /// <summary>
        /// 解除 Flash 窗口嵌入（去 WS_CHILD、SetParent 回桌面）。
        /// 退出时在 KillFlash 前调用，避免窗口层面的孤儿句柄问题。
        /// </summary>
        public void DetachFlash()
        {
            StopWatchdog();
            if (_flashHwnd == IntPtr.Zero) return;
            if (_hostPanel != null)
                _hostPanel.Resize -= OnHostPanelResize;
            try
            {
                if (IsWindow(_flashHwnd))
                {
                    // 先 SW_HIDE: 不然 SetParent(null) 后 Flash 立刻成为顶层窗口,
                    // 在 KillFlash 的 WaitForExit 期间会闪现 projector 默认 chrome (灰白底).
                    ShowWindow(_flashHwnd, SW_HIDE);
                    int style = GetWindowLong(_flashHwnd, GWL_STYLE);
                    style = style & ~WS_CHILD;
                    SetWindowLongLogged(_flashHwnd, GWL_STYLE, style, "SetWindowLong(detach remove WS_CHILD)");
                    if (!SetWindowPos(_flashHwnd, IntPtr.Zero, 0, 0, 0, 0,
                        SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED | SWP_NOACTIVATE))
                        LogWin32Failure("SetWindowPos(detach framechanged)", _flashHwnd);
                    SetParentLogged(_flashHwnd, IntPtr.Zero, "SetParent(detach desktop)");
                }
            }
            catch (Exception ex) { LogManager.Log("[WindowManager] DetachFlash error: " + ex.Message); }
            SetTrackedFlashWindow(IntPtr.Zero);
        }

        /// <summary>
        /// 诊断采样：当前桌面前台是否为空。
        /// </summary>
        public bool IsForegroundVacuum()
        {
            return GetForegroundOwnership() == SessionForegroundOwnership.Null;
        }

        /// <summary>
        /// A0.2 看门狗资格采样：当前系统前台窗口的会话归属。
        /// Null = 前台真空；Session = 前台属本会话（Flash/Guardian 进程窗口，
        /// 含面板/宿主交接途经的自己窗口）；External = 真实外部进程窗口。
        /// </summary>
        internal SessionForegroundOwnership GetForegroundOwnership()
        {
            IntPtr foreground = GetForegroundWindow();
            if (foreground == IntPtr.Zero)
                return SessionForegroundOwnership.Null;
            return IsWindowInFlashSession(foreground)
                ? SessionForegroundOwnership.Session
                : SessionForegroundOwnership.External;
        }

        /// <summary>
        /// 诊断用：返回当前系统前台窗口的可读描述（hwnd/pid/class/title）。
        /// 主要给 [Activation] / [FgWatchdog] 日志做"是谁抢的焦"归因——WM_ACTIVATEAPP(false)
        /// 那一瞬采集到的前台窗口就是肇事者，此后窗口可能消失，再查就晚了。
        /// </summary>
        public string DescribeForeground()
        {
            return DescribeWindow(GetForegroundWindow());
        }

        /// <summary>
        /// 判断 hwnd 是否属于 Flash 进程或 Guardian 进程。
        /// 此进程归属用于诊断采样；输入准入由会话窗口身份决定。
        /// </summary>
        internal bool IsWindowInFlashSession(IntPtr hwnd)
        {
            if (hwnd == IntPtr.Zero) return false;
            uint pid;
            GetWindowThreadProcessId(hwnd, out pid);
            return (pid == _flashProcessId && _flashProcessId != 0)
                || (pid == _guardianProcessId && _guardianProcessId != 0);
        }

        /// <summary>诊断用：把 hwnd 渲染成可读字符串 "0xHANDLE pid=N class=NAME title=TITLE"。</summary>
        internal static string DescribeWindow(IntPtr hwnd)
        {
            if (hwnd == IntPtr.Zero) return "0x0";
            uint pid;
            GetWindowThreadProcessId(hwnd, out pid);
            var cls = new StringBuilder(128);
            try { GetClassName(hwnd, cls, cls.Capacity); } catch { }
            var title = new StringBuilder(256);
            try { GetWindowText(hwnd, title, title.Capacity); } catch { }
            return "0x" + hwnd.ToString("X") + " pid=" + pid + " class=" + cls.ToString() + " title=\"" + title.ToString() + "\"";
        }

        internal bool HoldsForeground(IntPtr window)
        {
            return window != IntPtr.Zero && _focusApi.GetForegroundWindow() == window;
        }

        internal bool ReturnBootstrapForeground(IntPtr flash, IntPtr bootstrap)
        {
            if (bootstrap != _passiveRoot || !IsCurrentFlashWindow(flash)) return false;
            IntPtr current = ReadCloseForeground();
            return (current == bootstrap || current == flash) && ActivateSessionRootBeforeHide(current);
        }

        private bool IsCurrentFlashWindow(
            IntPtr expectedFlashHwnd)
        {
            if (expectedFlashHwnd == IntPtr.Zero)
                return false;
            lock (_embedClaimLock)
            {
                return _flashHwnd == expectedFlashHwnd
                    && _focusApi.IsWindow(
                        expectedFlashHwnd);
            }
        }

    }
}
