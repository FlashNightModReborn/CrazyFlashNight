using System;
using System.Runtime.InteropServices;

namespace CF7Launcher.Guardian
{
    public static class DpiDiagnostics
    {
        private const uint MONITOR_DEFAULTTONEAREST = 2;
        private const int MDT_EFFECTIVE_DPI = 0;

        [DllImport("user32.dll")]
        private static extern uint GetDpiForWindow(IntPtr hwnd);

        [DllImport("user32.dll")]
        private static extern IntPtr MonitorFromWindow(IntPtr hwnd, uint dwFlags);

        [DllImport("shcore.dll")]
        private static extern int GetDpiForMonitor(IntPtr hmonitor, int dpiType, out uint dpiX, out uint dpiY);

        public static bool TryGetWindowDpi(IntPtr hwnd, out uint dpiX, out uint dpiY)
        {
            dpiX = 96;
            dpiY = 96;
            if (hwnd == IntPtr.Zero)
                return false;

            try
            {
                uint dpi = GetDpiForWindow(hwnd);
                if (dpi > 0)
                {
                    dpiX = dpi;
                    dpiY = dpi;
                    return true;
                }
            }
            catch { }

            IntPtr monitor = GetMonitorFromWindow(hwnd);
            return TryGetMonitorDpi(monitor, out dpiX, out dpiY);
        }

        public static IntPtr GetMonitorFromWindow(IntPtr hwnd)
        {
            if (hwnd == IntPtr.Zero)
                return IntPtr.Zero;
            try { return MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST); }
            catch { return IntPtr.Zero; }
        }

        public static bool TryGetMonitorDpi(IntPtr monitor, out uint dpiX, out uint dpiY)
        {
            dpiX = 96;
            dpiY = 96;
            if (monitor == IntPtr.Zero)
                return false;

            try
            {
                uint x, y;
                int hr = GetDpiForMonitor(monitor, MDT_EFFECTIVE_DPI, out x, out y);
                if (hr == 0 && x > 0 && y > 0)
                {
                    dpiX = x;
                    dpiY = y;
                    return true;
                }
            }
            catch { }
            return false;
        }

        public static void LogProcessStartup(DpiAwarenessInitResult init, HighDpiCompatibilityResult compat)
        {
            try
            {
                LogManager.Log("[DPI] Awareness init: " + (init != null ? init.Describe() : "(not initialized)"));
                LogManager.Log("[DPI] Compatibility override: " + (compat != null ? compat.Describe() : "(not checked)"));
            }
            catch { }
        }

        public static void LogWindow(string label, IntPtr hwnd)
        {
            uint dpiX, dpiY;
            TryGetWindowDpi(hwnd, out dpiX, out dpiY);
            IntPtr monitor = GetMonitorFromWindow(hwnd);
            LogManager.Log("[DPI] " + label + " hwnd=0x" + hwnd.ToString("X")
                + " dpi=" + dpiX + "x" + dpiY
                + " monitor=0x" + monitor.ToString("X"));
        }

        public static void LogOverlayContext(string label, OverlayCoordinateContext context)
        {
            if (context == null)
                return;
            LogManager.Log("[DPI] " + label + " " + context.Describe());
        }
    }
}
