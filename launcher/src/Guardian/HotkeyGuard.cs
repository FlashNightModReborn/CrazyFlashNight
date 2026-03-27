// 独立进程编译：csc /target:winexe /out:hotkey_guard.exe HotkeyGuard.cs
// Guardian 启动时作为子进程运行，传入 Guardian PID 参数。
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
        static volatile bool _ctrlHeld;
        static uint _guardianPid;

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

        static int Main(string[] args)
        {
            if (args.Length < 1)
                return 1;

            // 参数：Guardian 进程 PID
            if (!uint.TryParse(args[0], out _guardianPid))
                return 1;

            // 监控 Guardian 进程——Guardian 退出时本进程也退出
            Process guardian;
            try
            {
                guardian = Process.GetProcessById((int)_guardianPid);
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

                // 追踪 Ctrl
                if (vk == VK_CONTROL || vk == VK_LCONTROL || vk == VK_RCONTROL)
                {
                    _ctrlHeld = (msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN);
                }

                // Ctrl + 被保护键 + Guardian 在前台 → 拦截
                if ((msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN)
                    && _ctrlHeld
                    && BlockedVks.Contains(vk))
                {
                    IntPtr fg = GetForegroundWindow();
                    if (fg != IntPtr.Zero)
                    {
                        uint pid;
                        GetWindowThreadProcessId(fg, out pid);
                        if (pid == _guardianPid)
                            return new IntPtr(1);
                    }
                }
            }

            return CallNextHookEx(_hookId, nCode, wParam, lParam);
        }
    }
}
