using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Threading;

namespace CF7Launcher.Guardian
{
    /// <summary>
    /// 低级键盘钩子——运行在专用线程上，永不超时。
    /// 拦截 Ctrl+W/R/P/O（Flash SA 原生快捷键）和 Ctrl+F/Q（Guardian 动作键）。
    /// 仅当 Guardian 进程在前台时拦截，不影响其他应用程序。
    /// </summary>
    public class KeyboardHook : IDisposable, IPanelEscapeSource
    {
        [DllImport("user32.dll", SetLastError = true)]
        private static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc lpfn, IntPtr hMod, uint dwThreadId);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool UnhookWindowsHookEx(IntPtr hhk);

        [DllImport("user32.dll")]
        private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

        [DllImport("kernel32.dll")]
        private static extern IntPtr GetModuleHandle(string lpModuleName);

        [DllImport("user32.dll")]
        private static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll")]
        private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetMessage(out MSG lpMsg, IntPtr hWnd, uint wMsgFilterMin, uint wMsgFilterMax);

        [DllImport("user32.dll")]
        private static extern bool TranslateMessage(ref MSG lpMsg);

        [DllImport("user32.dll")]
        private static extern IntPtr DispatchMessage(ref MSG lpMsg);

        [DllImport("user32.dll")]
        private static extern bool PostThreadMessage(uint idThread, uint Msg, IntPtr wParam, IntPtr lParam);

        [DllImport("kernel32.dll")]
        private static extern uint GetCurrentThreadId();

        [StructLayout(LayoutKind.Sequential)]
        private struct MSG
        {
            public IntPtr hwnd;
            public uint message;
            public IntPtr wParam;
            public IntPtr lParam;
            public uint time;
            public int pt_x;
            public int pt_y;
        }

        private delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);

        private const int WH_KEYBOARD_LL = 13;
        private const int WM_KEYDOWN = 0x0100;
        private const int WM_KEYUP = 0x0101;
        private const int WM_SYSKEYDOWN = 0x0104;
        private const int WM_SYSKEYUP = 0x0105;
        private const int WM_QUIT = 0x0012;

        private const uint VK_CONTROL = 0x11;
        private const uint VK_LCONTROL = 0xA2;
        private const uint VK_RCONTROL = 0xA3;
        private const uint VK_ESCAPE = 0x1B;

        private IntPtr _hookId = IntPtr.Zero;
        private LowLevelKeyboardProc _proc;
        private Thread _thread;
        private uint _threadId;
        private volatile bool _running;

        // 仅拦截的键（Ctrl+ 组合）
        private readonly HashSet<uint> _blockedVks;
        // 拦截后需要触发动作的键 → action 回调
        private readonly Dictionary<uint, Action> _actionVks;
        private readonly uint _myPid;
        private volatile uint _flashPid; // Flash 进程 PID（嵌入前前台是 Flash 而非 Guardian）
        private volatile bool _ctrlHeld;

        // Escape 拦截（全屏时动态启用）
        private volatile bool _escEnabled;
        // 面板 ESC 拦截（与 _escEnabled 独立）
        private volatile bool _panelEscEnabled;
        public bool PanelEscEnabled { get { return _panelEscEnabled; } }
        public void SetPanelEscapeEnabled(bool enabled) { _panelEscEnabled = enabled; }

        public KeyboardHook()
        {
            _myPid = (uint)System.Diagnostics.Process.GetCurrentProcess().Id;
            _proc = HookCallback;

            _blockedVks = new HashSet<uint>();
            _blockedVks.Add(0x57); // W
            _blockedVks.Add(0x52); // R
            _blockedVks.Add(0x50); // P
            _blockedVks.Add(0x4F); // O
            _blockedVks.Add(0x46); // F — 原 RegisterHotKey，现迁入此处
            _blockedVks.Add(0x51); // Q — 原 RegisterHotKey，现迁入此处
            // 0x47 (G) 由 GuardianForm 按 config.devGpuProbeHotkey 动态启用，玩家版不注入

            _actionVks = new Dictionary<uint, Action>();
        }

        /// <summary>
        /// 注册拦截后的动作回调（UI 线程安全：回调在专用线程触发，调用方需自行 BeginInvoke）
        /// </summary>
        public void RegisterAction(uint vk, Action callback)
        {
            _actionVks[vk] = callback;
        }

        /// <summary>
        /// 运行时把 vk 加入 Ctrl+&lt;vk&gt; 拦截列表。
        /// 用于按 config 决定是否启用某些开发用快捷键（如 Ctrl+G GPU probe）。
        /// </summary>
        public void EnableBlockedVk(uint vk)
        {
            _blockedVks.Add(vk);
        }

        /// <summary>
        /// 设置 Flash 进程 PID（嵌入前前台窗口是 Flash PID，嵌入后是 Guardian PID）
        /// </summary>
        public void SetFlashPid(uint pid) { _flashPid = pid; }

        /// <summary>
        /// 动态启用/禁用 Escape 键拦截（全屏时启用）
        /// </summary>
        public void SetEscapeEnabled(bool enabled)
        {
            _escEnabled = enabled;
        }

        public bool Install()
        {
            _running = true;
            ManualResetEvent ready = new ManualResetEvent(false);

            _thread = new Thread(delegate()
            {
                _threadId = GetCurrentThreadId();

                using (var proc = System.Diagnostics.Process.GetCurrentProcess())
                using (var mod = proc.MainModule)
                {
                    IntPtr hMod = GetModuleHandle(mod.ModuleName);
                    _hookId = SetWindowsHookEx(WH_KEYBOARD_LL, _proc, hMod, 0);
                }

                ready.Set();

                if (_hookId == IntPtr.Zero)
                    return;

                // 专用消息泵——此线程永远不会忙，钩子永远不会超时
                MSG msg;
                while (_running && GetMessage(out msg, IntPtr.Zero, 0, 0))
                {
                    TranslateMessage(ref msg);
                    DispatchMessage(ref msg);
                }
            });
            _thread.IsBackground = true;
            _thread.Start();

            ready.WaitOne(2000);
            bool ok = _hookId != IntPtr.Zero;
            Guardian.LogManager.Log("[KeyboardHook] Install " + (ok ? "OK" : "FAILED")
                + " (dedicated thread, blocks: W/R/P/O/F/Q [+G if dev])");
            return ok;
        }

        /// <summary>
        /// 钩子回调——在专用线程上运行，极轻量。
        /// 拦截逻辑 + 动作触发分离：拦截在微秒级返回，动作通过 ThreadPool 异步执行。
        /// </summary>
        private IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
        {
            if (nCode >= 0)
            {
                int msg = wParam.ToInt32();
                uint vk = (uint)Marshal.ReadInt32(lParam);

                // 追踪 Ctrl 物理状态
                if (vk == VK_CONTROL || vk == VK_LCONTROL || vk == VK_RCONTROL)
                {
                    _ctrlHeld = (msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN);
                }

                if (msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN)
                {
                    bool shouldBlock = false;

                    // Ctrl + 被保护键
                    if (_ctrlHeld && _blockedVks.Contains(vk))
                        shouldBlock = true;

                    // Escape（全屏时 或 面板打开时）
                    if (vk == VK_ESCAPE && (_escEnabled || _panelEscEnabled))
                        shouldBlock = true;

                    if (shouldBlock)
                    {
                        // 快速前台检查：Guardian 或 Flash 在前台时拦截
                        IntPtr fg = GetForegroundWindow();
                        if (fg != IntPtr.Zero)
                        {
                            uint pid;
                            GetWindowThreadProcessId(fg, out pid);
                            if (pid == _myPid || (_flashPid != 0 && pid == _flashPid))
                            {
                                // 触发动作回调（异步，不阻塞钩子线程）
                                Action action;
                                if (_actionVks.TryGetValue(vk, out action) && action != null)
                                {
                                    ThreadPool.QueueUserWorkItem(delegate { action(); });
                                }
                                return new IntPtr(1); // 拦截
                            }
                        }
                    }
                }
            }

            return CallNextHookEx(_hookId, nCode, wParam, lParam);
        }

        public void Dispose()
        {
            _running = false;

            if (_hookId != IntPtr.Zero)
            {
                UnhookWindowsHookEx(_hookId);
                _hookId = IntPtr.Zero;
            }

            if (_threadId != 0)
                PostThreadMessage(_threadId, WM_QUIT, IntPtr.Zero, IntPtr.Zero);

            if (_thread != null && _thread.IsAlive)
                _thread.Join(1000);

            Guardian.LogManager.Log("[KeyboardHook] Disposed");
        }
    }
}
