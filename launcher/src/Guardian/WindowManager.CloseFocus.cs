using System;
using System.Threading;
using System.Windows.Forms;

namespace CF7Launcher.Guardian
{
    public partial class WindowManager
    {
        private long _embedEpoch = 1;
        private Form _sessionRoot;

        internal long EmbedEpoch => Interlocked.Read(ref _embedEpoch);

        private void SetTrackedFlashWindow(IntPtr window)
        {
            lock (_embedClaimLock)
            {
                RetirePassiveBootstrapLocked(EmbedResult.Superseded, "source_tracking_changed");
                Volatile.Write(ref _publishedPassiveBootstrap, null);
                _flashHwnd = window;
                Interlocked.Increment(ref _embedEpoch);
            }
        }

        internal void ConfigureSessionRoot(Form root)
        {
            ArgumentNullException.ThrowIfNull(root);
            if (ReferenceEquals(_sessionRoot, root)) return;
            if (_sessionRoot != null)
            {
                _sessionRoot.HandleCreated -= SessionRootCreated;
                _sessionRoot.HandleDestroyed -= SessionRootDestroyed;
                SessionRootDestroyed(_sessionRoot, EventArgs.Empty);
            }
            _sessionRoot = root;
            root.HandleCreated += SessionRootCreated;
            root.HandleDestroyed += SessionRootDestroyed;
            _passiveRoot = root.Handle;
        }

        private void SessionRootCreated(object sender, EventArgs args)
        {
            lock (_embedClaimLock) _passiveRoot = _sessionRoot.Handle;
        }

        private void SessionRootDestroyed(object sender, EventArgs args)
        {
            // WinForms can recreate this Form's HWND without replacing the
            // session. Keep the pending attempt until the watchdog checks the
            // current managed owner and the restored window relationship.
            lock (_embedClaimLock) _passiveRoot = IntPtr.Zero;
            PassiveInput?.SetForeground(false);
            PassiveInput?.SetBusinessEligible(false, "guardian_handle_destroyed");
        }

        internal IntPtr ReadCloseForeground() => _focusApi.GetForegroundWindow();

        internal static bool IsSessionOwnedSource(IntPtr window, IntPtr root)
        {
            if (window == IntPtr.Zero || root == IntPtr.Zero) return false;
            if (window == root) return true;
            if (GetAncestor(window, 3 /* GA_ROOTOWNER */) == root) return true;
            // An owned top-level WinForms tool window may be its own GA_ROOTOWNER.
            // The actual managed owner chain also identifies nested editing surfaces.
            for (var form = Control.FromChildHandle(window)?.FindForm(); form != null; form = form.Owner)
                if (form.IsHandleCreated && form.Handle == root) return true;
            return false;
        }

        internal bool ActivateSessionRootBeforeHide(IntPtr expectedForeground)
        {
            IntPtr root = _passiveRoot;
            if (!_allowForeground || root == IntPtr.Zero || expectedForeground == IntPtr.Zero
                || !_focusApi.IsWindow(root) || IsIconic(root) || !IsWindowEnabled(root)
                || !IsSessionOwnedSource(expectedForeground, root)
                || ReadCloseForeground() != expectedForeground)
                return false;
            if (expectedForeground != root) _focusApi.SetForegroundWindow(root);
            return _passiveRoot == root && ReadCloseForeground() == root;
        }

        internal bool ReturnPassiveRoot(IntPtr expectedForeground) => ActivateSessionRootBeforeHide(expectedForeground);
    }
}
