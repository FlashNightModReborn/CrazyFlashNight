using System;
using System.Drawing;
using System.Runtime.InteropServices;

namespace CF7Launcher.Diagnostic
{
    // WindowFromPoint 是候选命中窗口；只有本进程 WndProc/OnMouse* 能证明实际收消息。
    internal static class FocusWindowSnapshot
    {
        internal static IntPtr Hud, Owner;
        internal static Func<IntPtr> FlashWindow;

        internal static object At(Point point)
        {
            try
            {
                IntPtr foreground = GetForegroundWindow();
                IntPtr candidate = WindowFromPoint(point);
                return new { foreground = Describe(foreground), hitCandidate = Describe(candidate),
                    hud = Describe(Hud), owner = Describe(Owner),
                    flash = Describe(FlashWindow == null ? IntPtr.Zero : FlashWindow()),
                    actualExternalReceiver = "unknown" };
            }
            catch { return new { snapshot = "unavailable" }; }
        }

        internal static object Describe(IntPtr hwnd)
        {
            uint pid;
            uint tid = GetWindowThreadProcessId(hwnd, out pid);
            var gui = new GuiThreadInfo { size = Marshal.SizeOf<GuiThreadInfo>() };
            bool available = hwnd != IntPtr.Zero && tid != 0 && GetGUIThreadInfo(tid, ref gui);
            Rect bounds;
            bool rectAvailable = GetWindowRect(hwnd, out bounds);
            return new { hwnd = hwnd.ToInt64(), pid, tid, visible = IsWindowVisible(hwnd),
                parent = GetParent(hwnd).ToInt64(), rootOwner = GetAncestor(hwnd, 3).ToInt64(),
                previous = GetWindow(hwnd, 3).ToInt64(), next = GetWindow(hwnd, 2).ToInt64(),
                style = GetWindowLongW(hwnd, -16), exStyle = GetWindowLongW(hwnd, -20),
                rectAvailable, bounds, guiAvailable = available,
                focus = available ? (long?)gui.focus.ToInt64() : null,
                capture = available ? (long?)gui.capture.ToInt64() : null,
                active = available ? (long?)gui.active.ToInt64() : null };
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct Rect { public int left, top, right, bottom; }
        [StructLayout(LayoutKind.Sequential)]
        private struct GuiThreadInfo
        {
            public int size, flags;
            public IntPtr active, focus, capture, menuOwner, moveSize, caret;
            public Rect caretRect;
        }
        [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] private static extern IntPtr WindowFromPoint(Point point);
        [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
        [DllImport("user32.dll")] private static extern bool GetGUIThreadInfo(uint tid, ref GuiThreadInfo info);
        [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr h, out Rect rect);
        [DllImport("user32.dll")] internal static extern bool IsWindowVisible(IntPtr h);
        [DllImport("user32.dll")] private static extern IntPtr GetParent(IntPtr h);
        [DllImport("user32.dll")] private static extern IntPtr GetAncestor(IntPtr h, uint flag);
        [DllImport("user32.dll")] private static extern IntPtr GetWindow(IntPtr h, uint command);
        [DllImport("user32.dll")] private static extern int GetWindowLongW(IntPtr h, int index);
    }
}
