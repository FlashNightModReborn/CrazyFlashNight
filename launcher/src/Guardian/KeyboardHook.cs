using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Threading;

namespace CF7Launcher.Guardian
{
    /// <summary>
    /// 低级键盘钩子——运行在专用线程上，永不超时。
    /// 仅负责拦截 Ctrl+W/R/P/O（Flash SA 原生快捷键），不做任何 UI 操作。
    /// Ctrl+F/Q 由 RegisterHotKey 处理（GuardianForm 负责）。
    /// </summary>
    public class KeyboardHook : IDisposable
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

        private IntPtr _hookId = IntPtr.Zero;
        private LowLevelKeyboardProc _proc;
        private Thread _thread;
        private uint _threadId;
        private volatile bool _running;

        // 仅拦截这些键（Ctrl+ 组合）。F/Q 由 RegisterHotKey 处理。
        private readonly HashSet<uint> _blockedVks;
        private readonly uint _myPid;
        private volatile bool _ctrlHeld;

        public KeyboardHook()
        {
            _myPid = (uint)System.Diagnostics.Process.GetCurrentProcess().Id;
            _proc = HookCallback;

            _blockedVks = new HashSet<uint>();
            _blockedVks.Add(0x57); // W
            _blockedVks.Add(0x52); // R
            _blockedVks.Add(0x50); // P
            _blockedVks.Add(0x4F); // O
        }

        public bool Install()
        {
            _running = true;
            ManualResetEvent ready = new ManualResetEvent(false);

            _thread = new Thread(delegate()
            {
                // 获取此线程 ID 用于退出时发 WM_QUIT
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
                + " (dedicated thread)");
            return ok;
        }

        /// <summary>
        /// 钩子回调——在专用线程上运行，极轻量。
        /// 不做 BeginInvoke、不写日志、不触发事件。只判断 + 返回。
        /// </summary>
        private IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
        {
            if (nCode >= 0)
            {
                int msg = wParam.ToInt32();

                // 直接从 lParam 读 vkCode（KBDLLHOOKSTRUCT 第一个字段，偏移 0）
                uint vk = (uint)Marshal.ReadInt32(lParam);

                // 追踪 Ctrl 物理状态
                if (vk == VK_CONTROL || vk == VK_LCONTROL || vk == VK_RCONTROL)
                {
                    _ctrlHeld = (msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN);
                }

                // 仅在 keydown 时拦截
                if ((msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN)
                    && _ctrlHeld
                    && _blockedVks.Contains(vk))
                {
                    // 快速前台检查：仅当本进程在前台时拦截
                    IntPtr fg = GetForegroundWindow();
                    if (fg != IntPtr.Zero)
                    {
                        uint pid;
                        GetWindowThreadProcessId(fg, out pid);
                        if (pid == _myPid)
                            return new IntPtr(1); // 拦截
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

            // 向专用线程发 WM_QUIT 使 GetMessage 返回 false
            if (_threadId != 0)
                PostThreadMessage(_threadId, WM_QUIT, IntPtr.Zero, IntPtr.Zero);

            if (_thread != null && _thread.IsAlive)
                _thread.Join(1000);

            Guardian.LogManager.Log("[KeyboardHook] Disposed");
        }
    }
}
