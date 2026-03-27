using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
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
        private static extern IntPtr SetParent(IntPtr hWndChild, IntPtr hWndNewParent);

        [DllImport("user32.dll")]
        private static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);

        [DllImport("user32.dll")]
        private static extern int GetWindowLong(IntPtr hWnd, int nIndex);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);

        private const int GWL_STYLE = -16;
        private const int WS_CAPTION = 0x00C00000;
        private const int WS_THICKFRAME = 0x00040000;
        private const int WS_BORDER = 0x00800000;
        private const int WS_CHILD = 0x40000000;

        private uint _flashProcessId;
        private IntPtr _flashHwnd;
        private Panel _hostPanel;

        public IntPtr FlashHwnd { get { return _flashHwnd; } }

        public void TrackProcess(Process flashProcess)
        {
            if (flashProcess != null)
                _flashProcessId = (uint)flashProcess.Id;
        }

        /// <summary>
        /// 等待 Flash 窗口出现，然后嵌入到宿主 Panel。
        /// 在后台线程调用。
        /// </summary>
        public void EmbedFlashWindow(Process flashProcess, Panel hostPanel)
        {
            _hostPanel = hostPanel;

            // 等 Flash 创建主窗口（最多 10 秒）
            IntPtr hwnd = IntPtr.Zero;
            for (int i = 0; i < 100; i++)
            {
                try
                {
                    flashProcess.WaitForInputIdle(100);
                    flashProcess.Refresh();
                    hwnd = flashProcess.MainWindowHandle;
                }
                catch { }

                if (hwnd != IntPtr.Zero)
                    break;

                Thread.Sleep(100);
            }

            if (hwnd == IntPtr.Zero)
            {
                LogManager.Log("[WindowManager] Flash window not found, embedding skipped");
                return;
            }

            _flashHwnd = hwnd;
            LogManager.Log("[WindowManager] Flash window found: 0x" + hwnd.ToString("X"));

            // 在 UI 线程执行嵌入
            if (_hostPanel.InvokeRequired)
            {
                _hostPanel.BeginInvoke(new Action(delegate { DoEmbed(); }));
            }
            else
            {
                DoEmbed();
            }
        }

        private void DoEmbed()
        {
            if (_flashHwnd == IntPtr.Zero || _hostPanel == null)
                return;

            // 去掉 Flash 窗口的标题栏和边框
            int style = GetWindowLong(_flashHwnd, GWL_STYLE);
            style = style & ~WS_CAPTION & ~WS_THICKFRAME & ~WS_BORDER;
            style = style | WS_CHILD;
            SetWindowLong(_flashHwnd, GWL_STYLE, style);

            // 设置父窗口
            SetParent(_flashHwnd, _hostPanel.Handle);

            // 填满 Panel
            ResizeFlashToPanel();

            // Panel 大小变化时自动调整
            _hostPanel.Resize += delegate { ResizeFlashToPanel(); };

            LogManager.Log("[WindowManager] Flash window embedded");
        }

        public void ResizeFlashToPanel()
        {
            if (_flashHwnd == IntPtr.Zero || _hostPanel == null)
                return;

            MoveWindow(_flashHwnd, 0, 0, _hostPanel.Width, _hostPanel.Height, true);
        }

        public bool IsFlashForeground()
        {
            if (_flashProcessId == 0)
                return false;

            IntPtr hwnd = GetForegroundWindow();
            if (hwnd == IntPtr.Zero)
                return false;

            uint pid;
            GetWindowThreadProcessId(hwnd, out pid);
            return pid == _flashProcessId;
        }
    }
}
