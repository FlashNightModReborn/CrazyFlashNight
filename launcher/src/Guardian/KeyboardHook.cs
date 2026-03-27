using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace CF7Launcher.Guardian
{
    public class KeyboardHook : IDisposable
    {
        private const int WH_KEYBOARD_LL = 13;
        private const int WM_KEYDOWN = 0x0100;
        private const int WM_SYSKEYDOWN = 0x0104;

        private delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc lpfn, IntPtr hMod, uint dwThreadId);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool UnhookWindowsHookEx(IntPtr hhk);

        [DllImport("user32.dll")]
        private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

        [DllImport("kernel32.dll")]
        private static extern IntPtr GetModuleHandle(string lpModuleName);

        [StructLayout(LayoutKind.Sequential)]
        private struct KBDLLHOOKSTRUCT
        {
            public uint vkCode;
            public uint scanCode;
            public uint flags;
            public uint time;
            public IntPtr dwExtraInfo;
        }

        private IntPtr _hookId = IntPtr.Zero;
        private LowLevelKeyboardProc _proc;
        private WindowManager _windowManager;
        private HashSet<Keys> _blockedKeys;

        /// <summary>
        /// 外部可通过此方法动态切换单个键的拦截状态
        /// </summary>
        public bool IsBlocked(Keys key)
        {
            return _blockedKeys.Contains(key);
        }

        public void SetBlocked(Keys key, bool blocked)
        {
            if (blocked)
                _blockedKeys.Add(key);
            else
                _blockedKeys.Remove(key);
        }

        public KeyboardHook(WindowManager windowManager)
        {
            _windowManager = windowManager;
            _proc = HookCallback;

            _blockedKeys = new HashSet<Keys>();
            _blockedKeys.Add(Keys.Q);
            _blockedKeys.Add(Keys.W);
            _blockedKeys.Add(Keys.R);
            _blockedKeys.Add(Keys.F);
            _blockedKeys.Add(Keys.P);
            _blockedKeys.Add(Keys.O);
        }

        public bool Install()
        {
            using (Process curProcess = Process.GetCurrentProcess())
            using (ProcessModule curModule = curProcess.MainModule)
            {
                IntPtr hMod = GetModuleHandle(curModule.ModuleName);
                _hookId = SetWindowsHookEx(WH_KEYBOARD_LL, _proc, hMod, 0);
            }

            if (_hookId == IntPtr.Zero)
            {
                LogManager.Log("[KeyboardHook] Failed, error=" + Marshal.GetLastWin32Error());
                return false;
            }

            LogManager.Log("[KeyboardHook] Installed");
            return true;
        }

        private IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
        {
            if (nCode >= 0)
            {
                int msg = wParam.ToInt32();
                if (msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN)
                {
                    KBDLLHOOKSTRUCT kbd = (KBDLLHOOKSTRUCT)Marshal.PtrToStructure(
                        lParam, typeof(KBDLLHOOKSTRUCT));

                    bool ctrlDown = (Control.ModifierKeys & Keys.Control) != 0;

                    if (ctrlDown && _blockedKeys.Contains((Keys)kbd.vkCode))
                    {
                        if (_windowManager.IsFlashForeground())
                        {
                            return new IntPtr(1);
                        }
                    }
                }
            }

            return CallNextHookEx(_hookId, nCode, wParam, lParam);
        }

        public void Dispose()
        {
            if (_hookId != IntPtr.Zero)
            {
                UnhookWindowsHookEx(_hookId);
                _hookId = IntPtr.Zero;
                LogManager.Log("[KeyboardHook] Uninstalled");
            }
        }
    }
}
