using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;

namespace CF7Launcher.Guardian
{
    /// <summary>
    /// 窗口管理：追踪 Flash 窗口句柄 + 嵌入到宿主 Panel。
    /// </summary>
    public class WindowManager
    {
        [DllImport("user32.dll")]
        private static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll")]
        private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetForegroundWindow(IntPtr hWnd);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);

        [DllImport("user32.dll")]
        private static extern IntPtr SetFocus(IntPtr hWnd);

        [DllImport("kernel32.dll")]
        private static extern uint GetCurrentThreadId();

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

        [DllImport("user32.dll")]
        private static extern IntPtr SetParent(IntPtr hWndChild, IntPtr hWndNewParent);

        [DllImport("user32.dll")]
        private static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);

        [DllImport("user32.dll")]
        private static extern int GetWindowLong(IntPtr hWnd, int nIndex);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);

        [DllImport("user32.dll")]
        private static extern IntPtr GetParent(IntPtr hWnd);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter,
            int X, int Y, int cx, int cy, uint uFlags);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool IsWindow(IntPtr hWnd);

        [DllImport("user32.dll")]
        private static extern IntPtr GetMenu(IntPtr hWnd);

        [DllImport("user32.dll")]
        private static extern bool SetMenu(IntPtr hWnd, IntPtr hMenu);

        [DllImport("user32.dll")]
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
        private const int SW_SHOW = 5;

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

        private uint _flashProcessId;
        private uint _guardianProcessId;
        private IntPtr _flashHwnd;
        private Panel _hostPanel;

        // GPU 模式：锁定 Flash 尺寸，不跟随 Panel resize
        private bool _gpuMode;
        private int _fixedWidth;
        private int _fixedHeight;

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

        public IntPtr FlashHwnd { get { return _flashHwnd; } }

        /// <summary>
        /// Phase 1c：嵌入结果事件。true = 成功嵌入；false = 10s 内未找到 Flash 窗口或外部主动通知失败。
        /// 触发封送到 _hostPanel 所在的 UI 线程（不变式 #5）。
        /// </summary>
        public event Action<bool> OnEmbedResult;

        private void FireEmbedResult(bool success)
        {
            Action<bool> handler = OnEmbedResult;
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

        /// <summary>
        /// Phase 1c：外部（如 GameLaunchFlow 检测异常）主动通知嵌入失败。
        /// </summary>
        public void NotifyEmbedFailure()
        {
            FireEmbedResult(false);
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
                _flashHwnd = IntPtr.Zero;
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
            try { DwmSetWindowAttribute(hwnd, DWMWA_CLOAK, ref cloakOn, sizeof(int)); } catch { }

            // 1) 立即 SW_HIDE 减少首帧 top-level 可见窗口时间
            ShowWindow(hwnd, SW_HIDE);

            // 2) 去边框 + WS_CHILD
            int style = GetWindowLong(hwnd, GWL_STYLE);
            style = style & ~WS_CAPTION & ~WS_THICKFRAME & ~WS_BORDER;
            style = style | WS_CHILD;
            SetWindowLong(hwnd, GWL_STYLE, style);

            // 3) 移除 Flash SA 菜单（釜底抽薪阻断加速器）
            IntPtr hMenu = GetMenu(hwnd);
            if (hMenu != IntPtr.Zero)
            {
                SetMenu(hwnd, IntPtr.Zero);
                DestroyMenu(hMenu);
                LogManager.Log("[WindowManager] Flash menu removed (accelerators disabled)");
            }

            // 4) SWP_FRAMECHANGED 强制非客户区重算
            SetWindowPos(hwnd, IntPtr.Zero, 0, 0, 0, 0,
                SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED);

            // 5) SetParent 到隐藏宿主
            SetParent(hwnd, hiddenHost.Handle);

            // 6) MoveWindow(..., repaint=false) — hidden 状态不请求重绘
            int w = hiddenHost.Width;
            int h = hiddenHost.Height;
            if (w < 1) w = 1;
            if (h < 1) h = 1;
            MoveWindow(hwnd, 0, 0, w, h, false);

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
        public void ArmEarlyReparent(Process flashProc, Panel hiddenHost)
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
                        _flashHwnd = hwnd;
                        claimed = true;
                    }

                    if (!claimed) return;

                    try
                    {
                        ReparentToHidden(hwnd, hiddenHost);
                    }
                    finally
                    {
                        lock (_embedClaimLock)
                        {
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
        /// 终点统一 FireEmbedResult(true) — 状态机 Embedding→WaitingGameReady 推进信号零改动.
        /// </summary>
        public void EmbedFlashWindow(Process flashProcess, Panel hostPanel)
        {
            _hostPanel = hostPanel;
            int pid = (flashProcess != null) ? flashProcess.Id : 0;

            IntPtr hwnd = IntPtr.Zero;
            bool needFullEmbed = false;
            bool mustWaitForEarlyDone = false;

            lock (_embedClaimLock)
            {
                if (_currentFlashPid != pid)
                {
                    // attempt 已换，脏句柄清零，走全量路径
                    _currentFlashPid = pid;
                    _embedPhase = EmbedPhase.None;
                    _flashHwnd = IntPtr.Zero;
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
                    FireEmbedResult(false);
                    return;
                }
                lock (_embedClaimLock) { _flashHwnd = hwnd; }
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
                        LogManager.Log("[WindowManager] EmbedFlashWindow: early-reparent spin timeout, no hwnd, fail");
                        FireEmbedResult(false);
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

            // 终点统一：UI 线程 DoEmbedOrReveal + FireEmbedResult(true)
            IntPtr hwndSnap = hwnd;
            bool fullSnap = needFullEmbed;
            if (_hostPanel != null && _hostPanel.InvokeRequired)
            {
                _hostPanel.BeginInvoke(new Action(delegate { DoEmbedOrReveal(hwndSnap, fullSnap); FireEmbedResult(true); }));
            }
            else
            {
                DoEmbedOrReveal(hwndSnap, fullSnap);
                FireEmbedResult(true);
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

            if (needFullEmbed)
            {
                // 完整路径：style + menu + SetParent + Show + MoveWindow
                int style = GetWindowLong(hwnd, GWL_STYLE);
                style = style & ~WS_CAPTION & ~WS_THICKFRAME & ~WS_BORDER;
                style = style | WS_CHILD;
                SetWindowLong(hwnd, GWL_STYLE, style);

                IntPtr hMenu = GetMenu(hwnd);
                if (hMenu != IntPtr.Zero)
                {
                    SetMenu(hwnd, IntPtr.Zero);
                    DestroyMenu(hMenu);
                    LogManager.Log("[WindowManager] Flash menu removed (accelerators disabled)");
                }

                SetWindowPos(hwnd, IntPtr.Zero, 0, 0, 0, 0,
                    SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED);
                SetParent(hwnd, _hostPanel.Handle);
            }

            // 两路径公用：先 uncloak（早 path 在 ReparentToHidden 时打过 DWMWA_CLOAK；child 化后理论无效，
            // 但有些路径下 cloak 状态会被 DWM 留存，uncloak 是兜底），再 SW_SHOW.
            int cloakOff = 0;
            try { DwmSetWindowAttribute(hwnd, DWMWA_CLOAK, ref cloakOff, sizeof(int)); } catch { }
            ShowWindow(hwnd, SW_SHOW);
            ResizeFlashToPanel();

            _hostPanel.Resize -= OnHostPanelResize;
            _hostPanel.Resize += OnHostPanelResize;

            StartEmbedWatchdog();

            lock (_embedClaimLock) { _embedPhase = EmbedPhase.RevealedOrFullEmbedded; }

            LogManager.Log("[WindowManager] Flash window embedded (path=" + (needFullEmbed ? "full" : "reveal") + ")");
        }

        private void OnHostPanelResize(object sender, EventArgs e)
        {
            if (!_gpuMode)
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
                    _flashHwnd = IntPtr.Zero;
                    System.Windows.Forms.Timer dying = _watchdog;
                    _watchdog = null;
                    try { dying.Stop(); dying.Dispose(); } catch { }
                    LogManager.Log("[WindowManager] Flash window destroyed, watchdog stopped+disposed");
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
            if (_flashHwnd == IntPtr.Zero || _hostPanel == null)
                return;

            if (_gpuMode)
                MoveWindow(_flashHwnd, 0, 0, _fixedWidth, _fixedHeight, true);
            else
                MoveWindow(_flashHwnd, 0, 0, _hostPanel.Width, _hostPanel.Height, true);
        }

        /// <summary>GPU 模式：锁定 Flash 到固定捕获分辨率。</summary>
        public void EnableGpuMode(int captureWidth, int captureHeight)
        {
            _gpuMode = true;
            _fixedWidth = captureWidth;
            _fixedHeight = captureHeight;
            if (_flashHwnd != IntPtr.Zero)
                MoveWindow(_flashHwnd, 0, 0, _fixedWidth, _fixedHeight, true);
            LogManager.Log("[WindowManager] GPU mode: fixed " + captureWidth + "x" + captureHeight);
        }

        /// <summary>退出 GPU 模式，恢复跟随 Panel 尺寸。</summary>
        public void DisableGpuMode()
        {
            _gpuMode = false;
            ResizeFlashToPanel();
            LogManager.Log("[WindowManager] GPU mode disabled");
        }

        /// <summary>将 Flash 窗口移到新的宿主 Panel（回退时使用）。</summary>
        public void ReparentFlash(Panel newHost)
        {
            if (_flashHwnd == IntPtr.Zero || newHost == null)
                return;

            // 解除旧 Panel 的 resize 事件
            if (_hostPanel != null)
                _hostPanel.Resize -= OnHostPanelResize;

            _hostPanel = newHost;
            int style = GetWindowLong(_flashHwnd, GWL_STYLE);
            style = style & ~WS_CAPTION & ~WS_THICKFRAME & ~WS_BORDER;
            style = style | WS_CHILD;
            SetWindowLong(_flashHwnd, GWL_STYLE, style);
            SetWindowPos(_flashHwnd, IntPtr.Zero, 0, 0, 0, 0,
                SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED);
            SetParent(_flashHwnd, _hostPanel.Handle);

            // 重新绑定 resize 事件
            _hostPanel.Resize += OnHostPanelResize;

            ResizeFlashToPanel();
            StartEmbedWatchdog();
            LogManager.Log("[WindowManager] Flash reparented to new host");
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
                    SetWindowLong(_flashHwnd, GWL_STYLE, style);
                    SetWindowPos(_flashHwnd, IntPtr.Zero, 0, 0, 0, 0,
                        SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED);
                    SetParent(_flashHwnd, IntPtr.Zero);
                }
            }
            catch { }
            _flashHwnd = IntPtr.Zero;
        }

        /// <summary>
        /// 前台看门狗判定：当前是否处于"焦点真空"——没有任何窗口持有系统前台
        /// （GetForegroundWindow() 返回 NULL）。后台程序抢焦后未归还前台时会留下此态。
        /// GuardianForm 的前台看门狗据此把前台回收给 Flash。
        /// </summary>
        public bool IsForegroundVacuum()
        {
            return GetForegroundWindow() == IntPtr.Zero;
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
        /// 嵌入后 Flash 子窗口 pid 归 Guardian；独立运行时 pid 归 Flash。
        /// </summary>
        private bool IsWindowInFlashSession(IntPtr hwnd)
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

        /// <summary>
        /// 统一 Flash 焦点恢复 primitive。所有想把输入焦点拉回 Flash 子窗口的路径都走这里：
        /// panel close（idle / soft idle）、forwardCtrlCombo 前置、未来 navigate heartbeat 等。
        ///
        /// 实现两遍尝试：
        ///   Pass 1：直接 SetForegroundWindow + SetFocus + 校验 GetForegroundWindow 落点
        ///   Pass 2：pass 1 失败 → AttachThreadInput 把前台线程的输入队列接到当前线程再 SetForegroundWindow，
        ///           try/finally 严格配对 detach（输入队列泄露是进程级 bug）。
        ///
        /// 全程打 [FocusRestore] 日志：reason + fgBefore（hwnd/pid/class/title）+ 各 pass 结果 + final 状态。
        /// 这条日志是排查"谁偷的焦点"和"primitive 是否生效"的唯一权威源；不要随意删。
        ///
        /// 本方法不抛异常；调用方拿 bool 返回值决定是否重试 / 启 heartbeat。
        /// </summary>
        public bool RestoreFlashInputFocus(string reason)
        {
            IntPtr flashHwnd = _flashHwnd;
            if (flashHwnd == IntPtr.Zero || !IsWindow(flashHwnd))
            {
                LogManager.Log("[FocusRestore] " + reason + ": no flash hwnd, skip");
                return false;
            }

            IntPtr fgBefore = GetForegroundWindow();
            string fgBeforeDesc = DescribeWindow(fgBefore);

            // Pass 1：直接 SetForegroundWindow
            bool sfwOk1 = false;
            try { sfwOk1 = SetForegroundWindow(flashHwnd); }
            catch (Exception ex)
            {
                LogManager.Log("[FocusRestore] " + reason + " pass1 SetForegroundWindow threw: " + ex.Message);
            }
            try { SetFocus(flashHwnd); } catch { }

            IntPtr fgAfter1 = GetForegroundWindow();
            if (IsWindowInFlashSession(fgAfter1))
            {
                LogManager.Log("[FocusRestore] " + reason + " pass1=ok sfwReturn=" + sfwOk1
                    + " fgBefore=" + fgBeforeDesc
                    + " fgAfter=" + DescribeWindow(fgAfter1)
                    + " innerFocus=" + DescribeInnerFocus(flashHwnd));
                return true;
            }

            // Pass 2：AttachThreadInput hack
            uint myTid = GetCurrentThreadId();
            uint fgPid2;
            uint fgTid = GetWindowThreadProcessId(fgAfter1, out fgPid2);
            bool attached = false;
            if (fgTid != 0 && fgTid != myTid)
            {
                try { attached = AttachThreadInput(myTid, fgTid, true); }
                catch (Exception ex)
                {
                    LogManager.Log("[FocusRestore] " + reason + " pass2 AttachThreadInput attach threw: " + ex.Message);
                }
            }
            try
            {
                try { SetForegroundWindow(flashHwnd); } catch { }
                try { SetFocus(flashHwnd); } catch { }
            }
            finally
            {
                if (attached)
                {
                    try { AttachThreadInput(myTid, fgTid, false); }
                    catch (Exception ex)
                    {
                        // 这条若失败必须立刻报：输入队列绑死是进程级 bug，不会自愈
                        LogManager.Log("[FocusRestore] " + reason + " pass2 AttachThreadInput DETACH FAILED: " + ex.Message
                            + " (myTid=" + myTid + " fgTid=" + fgTid + ")");
                    }
                }
            }

            IntPtr fgAfter2 = GetForegroundWindow();
            bool finalOk = IsWindowInFlashSession(fgAfter2);
            LogManager.Log("[FocusRestore] " + reason + " pass1=fail pass2=" + (finalOk ? "ok" : "fail")
                + " attached=" + attached
                + " fgBefore=" + fgBeforeDesc
                + " fgAfter1=" + DescribeWindow(fgAfter1)
                + " fgAfter2=" + DescribeWindow(fgAfter2)
                + " innerFocus=" + DescribeInnerFocus(flashHwnd));
            return finalOk;
        }

        /// <summary>
        /// 诊断用：查 Flash 主窗口所属线程的 GUI focus 状态，看 inner focus 是否真的落在 flashHwnd。
        /// GetGUIThreadInfo 跨线程安全（无需 AttachThreadInput），返回的 hwndFocus 是该线程当前持有焦点的子窗口。
        ///
        /// 输出格式：
        ///   "matches"       → hwndFocus == flashHwnd（最理想，AS2 能收键）
        ///   "child=0x..."   → hwndFocus 是 flashHwnd 的子（也算 AS2 能收键的范围）
        ///   "other=0x..."   → 焦点在 Flash 线程的其他窗口（应该不会出现，Flash SA 一般只有主窗口持焦）
        ///   "none"          → 该线程当前无 GUI 焦点（SetFocus 没生效或被剥）
        ///   "gti_fail"      → GetGUIThreadInfo 调用失败
        /// </summary>
        private static string DescribeInnerFocus(IntPtr flashHwnd)
        {
            if (flashHwnd == IntPtr.Zero) return "no_flash_hwnd";
            uint flashPid;
            uint flashTid = GetWindowThreadProcessId(flashHwnd, out flashPid);
            if (flashTid == 0) return "no_flash_tid";

            GUITHREADINFO gti = new GUITHREADINFO();
            gti.cbSize = Marshal.SizeOf(typeof(GUITHREADINFO));
            bool ok = false;
            try { ok = GetGUIThreadInfo(flashTid, ref gti); }
            catch { ok = false; }
            if (!ok) return "gti_fail";
            if (gti.hwndFocus == IntPtr.Zero) return "none";
            if (gti.hwndFocus == flashHwnd) return "matches";
            // 是不是 Flash 主窗口的子？快速检查 GetAncestor(GA_ROOT) 是 flashHwnd
            // 这里不另引 P/Invoke 了，直接报 hwnd + 类名让人肉判断
            return "other=" + DescribeWindow(gti.hwndFocus);
        }
    }
}
