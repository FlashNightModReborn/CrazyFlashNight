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

        internal static bool RaiseIfCovered(Form window, Form owner, IntPtr keepAbove = default,
            bool preserveForeignOrder = false)
        {
            using var latency = InputLatencyProbe.Measure("transition_raise");
            if (!IsPresented(window) || window.Owner != owner
                || owner.IsDisposed || !owner.IsHandleCreated || !owner.Visible
                || owner.WindowState == FormWindowState.Minimized) return false;

            IntPtr handle = window.Handle, ownerHandle = owner.Handle;
            if (preserveForeignOrder) return RaiseWithinOwnerBand(handle,ownerHandle,keepAbove);
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

        // ShowWithoutActivation prevents activation, but does not pin the first
        // Show() below a foreign foreground window. Constrain the native show
        // before it takes effect, while preserving WinForms' managed visibility.
        // NOACTIVATE/NOOWNERZORDER cannot be added here: Win32 ignores those flag
        // edits in WM_WINDOWPOSCHANGING. The Worker forms own their no-activation
        // style, and explicit repairs pass both flags at the original call.
        internal static void ConstrainBackgroundShow(ref Message message, Form window, Form owner)
        {
            if (message.Msg!=0x0046 || message.LParam==IntPtr.Zero || owner==null || owner.IsDisposed
                || !owner.IsHandleCreated || window.Owner!=owner || !owner.Visible
                || owner.WindowState==FormWindowState.Minimized) return;
            var position=Marshal.PtrToStructure<WindowPosition>(message.LParam);
            if ((position.Flags & 0x0040)==0) return;
            position.InsertAfter=OwnerBandBoundary(owner.Handle,position.Window);
            position.Flags &= ~0x0004u; // The captured insertion point must not be ignored.
            Marshal.StructureToPtr(position,message.LParam,false);
        }

        private static IntPtr OwnerBandBoundary(IntPtr owner, IntPtr target)
        {
            int visited=0;
            IntPtr above=GetWindow(owner,3);
            for (;above!=IntPtr.Zero && visited++<512;above=GetWindow(above,3)) {
                if (above==target || !IsWindowVisible(above)) continue;
                // HWND_TOP keeps this non-topmost Worker window below the
                // topmost band. NOTOPMOST alone would not move an already
                // non-topmost window above an ordinary sibling.
                if ((GetWindowLong(above,-20)&0x00000008)!=0) return IntPtr.Zero;
                if (GetWindow(above,4)!=owner) return above;
            }
            return above; // HWND_TOP is safe only when no visible foreign boundary exists.
        }

        private static bool RaiseWithinOwnerBand(IntPtr handle, IntPtr owner, IntPtr keepAbove)
        {
            IntPtr covered=IntPtr.Zero;
            int visited=0;
            for (IntPtr above=GetWindow(handle,3);above!=IntPtr.Zero && visited++<512;above=GetWindow(above,3)) {
                if (above==handle) return false;
                if (!IsWindowVisible(above)) continue;
                if (above==keepAbove || (GetWindowLong(above,-20)&0x00000008)!=0 || GetWindow(above,4)!=owner) break;
                covered=above;
            }
            if (covered==IntPtr.Zero) return false;
            IntPtr insertAfter=GetWindow(covered,3);
            if (insertAfter!=IntPtr.Zero && (GetWindowLong(insertAfter,-20)&0x00000008)!=0) insertAfter=IntPtr.Zero;
            return SetWindowPos(handle,insertAfter,0,0,0,0,0x0001|0x0002|0x0010|0x0200);
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct WindowPosition
        {
            internal IntPtr Window, InsertAfter;
            internal int X, Y, Width, Height;
            internal uint Flags;
        }

        [DllImport("user32.dll")] private static extern IntPtr GetWindow(IntPtr hwnd, uint command);
        [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr hwnd);
        [DllImport("user32.dll", EntryPoint = "GetWindowLongW")] private static extern int GetWindowLong(IntPtr hwnd, int index);
        [DllImport("user32.dll")] private static extern bool SetWindowPos(IntPtr hwnd, IntPtr after,
            int x, int y, int width, int height, uint flags);
    }
}
