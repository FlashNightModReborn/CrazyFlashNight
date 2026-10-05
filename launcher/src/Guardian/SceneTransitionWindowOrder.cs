using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using CF7Launcher.Diagnostic;

namespace CF7Launcher.Guardian
{
    // Call only after the transition's foreground/admission gate. A correct stack
    // must not submit SetWindowPos again: even an unchanged HWND_TOP request can
    // synchronously wait on the owner's embedded Flash window while it is loading.
    internal static class SceneTransitionWindowOrder
    {
        // WebOverlayForm presents its HWND with SWP_SHOWWINDOW. That does not
        // update WinForms' managed Visible state, so read the actual window.
        internal static bool IsPresented(Form window) => window != null && !window.IsDisposed
            && window.IsHandleCreated && IsWindowVisible(window.Handle);

        internal static bool RaiseIfCovered(Form window, Form owner, IntPtr keepAbove = default)
        {
            using var latency = InputLatencyProbe.Measure("transition_raise");
            if (!IsPresented(window) || window.Owner != owner
                || owner.IsDisposed || !owner.IsHandleCreated || !owner.Visible
                || owner.WindowState == FormWindowState.Minimized) return false;

            IntPtr handle = window.Handle, ownerHandle = owner.Handle;
            // Bounded native reads also catch world/HUD windows that have no
            // PresentationChanged event. Ignore desktop/foreign/topmost windows;
            // an ordinary curtain cannot cover those by repeatedly raising itself.
            int visited = 0;
            for (IntPtr above = GetWindow(handle, 3); above != IntPtr.Zero && visited++ < 512;
                above = GetWindow(above, 3))
            {
                if (above == handle) return false;
                if (above == keepAbove || GetWindow(above, 4) != ownerHandle || !IsWindowVisible(above)
                    || (GetWindowLong(above, -20) & 0x00000008) != 0) continue;

                // Keep the owner/embedded child out of this order repair.
                return SetWindowPos(handle, IntPtr.Zero, 0, 0, 0, 0,
                    0x0001 | 0x0002 | 0x0010 | 0x0200); // NOSIZE, NOMOVE, NOACTIVATE, NOOWNERZORDER
            }
            return false;
        }

        [DllImport("user32.dll")] private static extern IntPtr GetWindow(IntPtr hwnd, uint command);
        [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr hwnd);
        [DllImport("user32.dll", EntryPoint = "GetWindowLongW")] private static extern int GetWindowLong(IntPtr hwnd, int index);
        [DllImport("user32.dll")] private static extern bool SetWindowPos(IntPtr hwnd, IntPtr after,
            int x, int y, int width, int height, uint flags);
    }
}
