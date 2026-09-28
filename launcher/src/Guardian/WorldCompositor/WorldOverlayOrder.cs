using System;
using System.Collections.Generic;
using System.Linq;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using CF7Launcher.Diagnostic;

namespace CF7Launcher.Guardian.WorldCompositor
{
    // Restore only the world/HUD boundary. Each HUD still owns its internal order.
    internal sealed class WorldOverlayOrder : IDisposable
    {
        private readonly Form _owner, _world;
        private readonly OverlayBase[] _overlays;
        private readonly Func<bool> _canPresent;
        private readonly Func<IntPtr> _foreground;
        private bool _queued, _disposed;

        internal WorldOverlayOrder(Form owner, Form world, IEnumerable<OverlayBase> overlays,
            Func<bool> canPresent, Func<IntPtr> foreground = null)
        {
            _owner = owner; _world = world; _canPresent = canPresent;
            _foreground = foreground ?? GetForegroundWindow;
            _overlays = overlays.Where(o => o != null && o.Owner == owner).Distinct().ToArray();
            foreach (var overlay in _overlays) overlay.PresentationChanged += OnOverlayPresented;
            _owner.Activated += OnOwnerActivated;
            _world.VisibleChanged += OnWorldVisibilityChanged;
        }

        private void OnOverlayPresented() => QueueRestore("hud_presented");
        private void OnOwnerActivated(object sender, EventArgs e) => QueueRestore("owner_activate");
        private void OnWorldVisibilityChanged(object sender, EventArgs e) => QueueRestore("world_visibility");

        private void QueueRestore(string reason)
        {
            if (_disposed || _queued || !_owner.IsHandleCreated || _owner.IsDisposed) return;
            _queued = true;
            try
            {
                // Owner activation and PlayerHudRuntime.RestoreStack can nest. Run once
                // after their synchronous show/reorder work and recheck actual foreground.
                _owner.BeginInvoke(new Action(() =>
                {
                    _queued = false;
                    if (!_disposed) RestoreNow(reason);
                }));
            }
            catch (InvalidOperationException) { _queued = false; }
        }

        internal bool RestoreNow(string reason)
        {
            if (_disposed || _owner.IsDisposed || !_owner.IsHandleCreated || !_owner.Visible
                || _owner.WindowState == FormWindowState.Minimized || !_canPresent()
                || _world.IsDisposed || !_world.IsHandleCreated || !_world.Visible
                || !IsOwnerForeground(_owner.Handle, _foreground())) return false;

            var visible = new HashSet<IntPtr>(_overlays.Where(o => !o.IsDisposed
                && o.IsHandleCreated && IsWindowVisible(o.Handle)).Select(o => o.Handle));
            IntPtr world = _world.Handle;
            IntPtr[] covered = CoveredOverlays(world, _owner.Handle, visible);
            if (covered == null) return false; // Unknown chain: never move below the owner.
            if (covered.Length == 0) return true;

            IntPtr after = covered[covered.Length - 1];
            bool succeeded = SetWindowPos(world, after, 0, 0, 0, 0,
                0x0001 | 0x0002 | 0x0010 | 0x0200); // NOSIZE, NOMOVE, NOACTIVATE, NOOWNERZORDER
            int error = succeeded ? 0 : Marshal.GetLastWin32Error();
            IntPtr[] remaining = CoveredOverlays(world, _owner.Handle, visible);
            bool restored = succeeded && remaining != null && remaining.Length == 0;
            if (FocusTrace.Enabled) FocusTrace.Record("world.overlay_order", new
            {
                reason, world = world.ToInt64(), insertAfter = after.ToInt64(),
                covered = covered.Select(h => h.ToInt64()).ToArray(),
                remaining = remaining?.Select(h => h.ToInt64()).ToArray(), succeeded, restored, error
            });
            return restored;
        }

        internal static bool IsOwnerForeground(IntPtr owner, IntPtr foreground)
            => owner != IntPtr.Zero && foreground != IntPtr.Zero
                && (foreground == owner || GetAncestor(foreground, 2) == owner);

        private static IntPtr[] CoveredOverlays(IntPtr world, IntPtr owner, HashSet<IntPtr> visible)
        {
            var covered = new List<IntPtr>();
            var visited = new HashSet<IntPtr>();
            for (IntPtr next = GetWindow(world, 2); next != IntPtr.Zero && visited.Count < 512;
                next = GetWindow(next, 2))
            {
                if (next == owner) return covered.ToArray();
                if (!visited.Add(next)) return null;
                if (visible.Contains(next)) covered.Add(next);
            }
            return null;
        }

        public void Dispose()
        {
            if (_disposed) return;
            _disposed = true;
            foreach (var overlay in _overlays) overlay.PresentationChanged -= OnOverlayPresented;
            _owner.Activated -= OnOwnerActivated;
            _world.VisibleChanged -= OnWorldVisibilityChanged;
        }

        [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] private static extern IntPtr GetAncestor(IntPtr hwnd, uint flags);
        [DllImport("user32.dll")] private static extern IntPtr GetWindow(IntPtr hwnd, uint command);
        [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr hwnd);
        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool SetWindowPos(IntPtr hwnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
    }
}
