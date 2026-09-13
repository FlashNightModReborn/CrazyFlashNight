// 编入 Core，通过同一 apphost 的 --hotkey-guard 子模式运行独立进程。
// 父 PID、可执行路径和 Core MVID 必须一致；不再加载根目录历史 EXE。
// 本进程只做一件事：低级键盘钩子 + 消息泵。
// 不做 GUI、不做 IO、不做网络，钩子回调微秒级返回，永不超时。

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;

namespace CF7Launcher.Guardian
{
    static class HotkeyGuard
    {
        // ── Win32 P/Invoke ──

        delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);

        [DllImport("user32.dll", SetLastError = true)]
        static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc lpfn, IntPtr hMod, uint dwThreadId);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        static extern bool UnhookWindowsHookEx(IntPtr hhk);

        [DllImport("user32.dll")]
        static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

        [DllImport("kernel32.dll")]
        static extern IntPtr GetModuleHandle(string lpModuleName);

        [DllImport("user32.dll")]
        static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll")]
        static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        static extern bool GetMessage(out MSG lpMsg, IntPtr hWnd, uint wMsgFilterMin, uint wMsgFilterMax);

        [DllImport("user32.dll")]
        static extern bool TranslateMessage(ref MSG lpMsg);

        [DllImport("user32.dll")]
        static extern IntPtr DispatchMessage(ref MSG lpMsg);

        [StructLayout(LayoutKind.Sequential)]
        struct MSG
        {
            public IntPtr hwnd;
            public uint message;
            public IntPtr wParam;
            public IntPtr lParam;
            public uint time;
            public int pt_x;
            public int pt_y;
        }

        const int WH_KEYBOARD_LL = 13;
        const int WM_KEYDOWN = 0x0100;
        const int WM_KEYUP = 0x0101;
        const int WM_SYSKEYDOWN = 0x0104;

        const uint VK_CONTROL = 0x11;
        const uint VK_LCONTROL = 0xA2;
        const uint VK_RCONTROL = 0xA3;

        // ── 状态 ──

        static IntPtr _hookId = IntPtr.Zero;
        static LowLevelKeyboardProc _proc;
        [DllImport("user32.dll")] static extern short GetAsyncKeyState(int vk);
        static bool _leftCtrlHeld, _rightCtrlHeld;
        static bool _ctrlHeld { get { return _leftCtrlHeld || _rightCtrlHeld; } }
        static uint _guardianPid;
        static bool _diagnostic;
        static readonly Queue<string> _trace = new Queue<string>();
        static readonly HashSet<uint> _consumed = new HashSet<uint>();
        static int _traceLost;
        static Timer _traceTimer;

        static void TraceKey(uint vk, int message, IntPtr data, bool blocked, IntPtr foreground)
        {
            if (!_diagnostic || !(vk == 0x57 || vk == 0x41 || vk == 0x53 || vk == 0x44
                || vk == 0x52 || vk == VK_LCONTROL || vk == VK_RCONTROL)) return;
            lock (_trace)
            {
                if (_trace.Count == 128) { _trace.Dequeue(); _traceLost++; }
                _trace.Enqueue("vk=" + vk + " message=" + message + " blocked=" + blocked
                    + " leftCtrl=" + _leftCtrlHeld + " rightCtrl=" + _rightCtrlHeld
                    + " hookTime=" + unchecked((uint)Marshal.ReadInt32(data, 12))
                    + " flags=" + Marshal.ReadInt32(data, 8) + " foreground=" + foreground.ToInt64());
            }
        }

        static void FlushTrace(object ignored)
        {
            string[] lines;
            int lost;
            lock (_trace) { lines = _trace.ToArray(); _trace.Clear(); lost = _traceLost; _traceLost = 0; }
            try
            {
                if (lost > 0) Console.WriteLine("[HotkeyGuardInput] dropped=" + lost);
                foreach (string line in lines) Console.WriteLine("[HotkeyGuardInput] " + line);
            }
            catch { /* 宿主退出或管道失败不干扰输入。 */ }
        }

        // 要拦截的 VK 码（Ctrl+这些键在 Flash SA 前台时被吞掉）
        static readonly HashSet<uint> BlockedVks = new HashSet<uint> {
            0x51, // Q
            0x57, // W
            0x52, // R
            0x46, // F
            0x50, // P
            0x4F  // O
        };

        // ── 入口 ──

        internal static bool IsInvocation(string[] args)
        {
            return args != null && args.Length > 0 && args[0] == "--hotkey-guard";
        }

        internal static bool IsMatchingParent(string parentPath, string ownPath, string expectedMvid)
        {
            return !string.IsNullOrEmpty(parentPath) && string.Equals(parentPath, ownPath, StringComparison.OrdinalIgnoreCase)
                && string.Equals(expectedMvid, typeof(HotkeyGuard).Assembly.ManifestModule.ModuleVersionId.ToString("D"), StringComparison.Ordinal);
        }

        internal static int Run(string[] args)
        {
            if (args == null || args.Length < 2 || args.Length > 3 || (args.Length == 3 && args[2] != "--diag-input"))
                return 1;

            // 参数：Guardian 进程 PID
            if (!uint.TryParse(args[0], out _guardianPid))
                return 1;

            _diagnostic = args.Length == 3;
            if (_diagnostic) _traceTimer = new Timer(FlushTrace, null, 500, 500);

            // 监控 Guardian 进程——Guardian 退出时本进程也退出
            Process guardian;
            try
            {
                guardian = Process.GetProcessById((int)_guardianPid);
                if (guardian.Id == Environment.ProcessId
                    || !IsMatchingParent(guardian.MainModule.FileName, Environment.ProcessPath, args[1]))
                {
                    guardian.Dispose();
                    return 1;
                }
            }
            catch
            {
                return 1; // Guardian 不存在
            }

            // 后台线程监控 Guardian 存活
            Thread watchdog = new Thread(delegate()
            {
                try { guardian.WaitForExit(); } catch { }
                Environment.Exit(0);
            });
            watchdog.IsBackground = true;
            watchdog.Start();

            // 安装钩子
            _proc = HookCallback;
            using (Process curProcess = Process.GetCurrentProcess())
            using (ProcessModule curModule = curProcess.MainModule)
            {
                IntPtr hMod = GetModuleHandle(curModule.ModuleName);
                _hookId = SetWindowsHookEx(WH_KEYBOARD_LL, _proc, hMod, 0);
            }

            if (_hookId == IntPtr.Zero)
                return 2;

            // 消息泵——此进程的唯一工作
            MSG msg;
            while (GetMessage(out msg, IntPtr.Zero, 0, 0))
            {
                TranslateMessage(ref msg);
                DispatchMessage(ref msg);
            }

            UnhookWindowsHookEx(_hookId);
            return 0;
        }

        // ── 钩子回调：极轻量，微秒级 ──

        static IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
        {
            if (nCode >= 0)
            {
                int msg = wParam.ToInt32();
                uint vk = (uint)Marshal.ReadInt32(lParam);
                if (vk == VK_CONTROL) vk = (Marshal.ReadInt32(lParam, 8) & 1) != 0 ? VK_RCONTROL : VK_LCONTROL;

                // 当前边沿以回调为准；另一侧及非 Ctrl 事件校准漏掉的释放。
                bool down = msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN;
                _leftCtrlHeld = vk == VK_LCONTROL ? down : (GetAsyncKeyState((int)VK_LCONTROL) & 0x8000) != 0;
                _rightCtrlHeld = vk == VK_RCONTROL ? down : (GetAsyncKeyState((int)VK_RCONTROL) & 0x8000) != 0;

                IntPtr fg = GetForegroundWindow();
                uint pid = 0;
                if (fg != IntPtr.Zero) GetWindowThreadProcessId(fg, out pid);
                bool up = msg == WM_KEYUP || msg == 0x0105;
                if (pid != _guardianPid && fg != IntPtr.Zero)
                    _consumed.RemoveWhere(key => (key != vk || down) && (GetAsyncKeyState((int)key) & 0x8000) == 0);
                bool consumed = _consumed.Contains(vk);
                if (up) _consumed.Remove(vk);
                bool blocked = pid == _guardianPid && ((consumed && (down || up))
                    || (down && _ctrlHeld && BlockedVks.Contains(vk)));
                if (blocked && down) _consumed.Add(vk);
                TraceKey(vk, msg, lParam, blocked, fg);
                if (blocked) return new IntPtr(1);
            }

            return CallNextHookEx(_hookId, nCode, wParam, lParam);
        }
    }
}
