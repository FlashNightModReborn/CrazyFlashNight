using System;
using System.Threading;
using System.Windows.Forms;
using CF7Launcher.Guardian.InputOwnership;

namespace CF7Launcher.Guardian
{
    public partial class WindowManager
    {
        private sealed record PassiveBootstrapPublication(IntPtr Source, uint Pid, long Epoch,
            Panel Host, IntPtr HostHandle, Form Root, IntPtr RootHandle, SessionInputAuthority Authority,
            Action<bool> Completed);

        private PassiveBootstrapPublication _pendingPassiveBootstrap;

#if CF7_TEST_SEAMS
        internal Func<(bool Known, bool Focused, bool Enabled)> PassiveBootstrapFocusForTests { get; set; }

        internal void StagePassiveBootstrapForTests(Panel host, Action<bool> completed)
        {
            _hostPanel = host;
            StagePassiveBootstrapPublication(_flashHwnd, _flashProcessId, host, completed);
        }

        internal bool RecoverPassiveBootstrapForTests()
        {
            var pending = Volatile.Read(ref _pendingPassiveBootstrap);
            return pending != null && TryPublishPassiveBootstrap(pending, "guardian_activation",
                useStartupCorrection: true, requireGuardianForeground: true);
        }
#endif

        private void CancelPassiveBootstrapPublication() => Interlocked.Exchange(ref _pendingPassiveBootstrap, null);

        private void StagePassiveBootstrapPublication(IntPtr source, uint pid, Panel host, Action<bool> completed)
        {
            Form root = _sessionRoot;
            if (root == null || root.IsDisposed || root.Disposing || !root.IsHandleCreated)
            {
                FireEmbedResult(completed, false);
                return;
            }
            var pending = new PassiveBootstrapPublication(source, pid, EmbedEpoch, host, host.Handle, root,
                _passiveRoot, PassiveInput, completed);
            bool valid;
            lock (_embedClaimLock)
            {
                valid = IsCurrentBootstrapSource(pending);
                if (valid) Volatile.Write(ref _pendingPassiveBootstrap, pending);
            }
            if (!valid)
            {
                FireEmbedResult(completed, false);
                return;
            }
            if (!TryPublishPassiveBootstrap(pending, "embed_reveal", useStartupCorrection: true))
                LogManager.Log($"event=passive_bootstrap_publication stage=pending flash=0x{source:X} pid={pid} epoch={pending.Epoch}");
        }

        private bool IsCurrentBootstrapSource(PassiveBootstrapPublication pending)
        {
            return pending.Authority != null && ReferenceEquals(PassiveInput, pending.Authority)
                && pending.Source != IntPtr.Zero && _flashHwnd == pending.Source && _flashProcessId == pending.Pid
                && EmbedEpoch == pending.Epoch && ReferenceEquals(_sessionRoot, pending.Root)
                && !pending.Root.IsDisposed && !pending.Root.Disposing && pending.Root.IsHandleCreated
                && pending.RootHandle != IntPtr.Zero && _passiveRoot == pending.RootHandle
                && pending.Root.Handle == pending.RootHandle
                && ReferenceEquals(_hostPanel, pending.Host) && !pending.Host.IsDisposed && !pending.Host.Disposing
                && pending.Host.IsHandleCreated && pending.Host.Handle == pending.HostHandle
                && GetParent(pending.Source) == pending.HostHandle
                && GetWindowThreadProcessId(pending.Source, out uint sourcePid) != 0 && sourcePid == pending.Pid;
        }

        private void QueuePassiveBootstrapRecovery()
        {
            PassiveBootstrapPublication pending = Volatile.Read(ref _pendingPassiveBootstrap);
            if (pending == null || ReadCloseForeground() != pending.RootHandle
                || pending.Root.IsDisposed || pending.Root.Disposing || !pending.Root.IsHandleCreated)
                return;
            try
            {
                pending.Root.BeginInvoke(new Action(() => TryPublishPassiveBootstrap(pending,
                    "guardian_activation", useStartupCorrection: true, requireGuardianForeground: true)));
            }
            catch (InvalidOperationException) { }
        }

        private bool TryPublishPassiveBootstrap(PassiveBootstrapPublication pending, string stage,
            bool useStartupCorrection = false, bool requireGuardianForeground = false)
        {
            bool Current() => ReferenceEquals(Volatile.Read(ref _pendingPassiveBootstrap), pending)
                && IsCurrentBootstrapSource(pending)
                && (!requireGuardianForeground || ReadCloseForeground() == pending.RootHandle);
            if (!Current()) return false;
            bool valid = useStartupCorrection ? SettleBootstrapFocus(pending.Source, stage)
                : AuditPassiveFocus(out _, stage);
            if (!valid) return false;
            lock (_embedClaimLock)
            {
                if (!Current()) return false;
                _revealedPassiveSource = pending.Source;
                Volatile.Write(ref _pendingPassiveBootstrap, null);
            }
            LogManager.Log($"event=passive_bootstrap_publication stage=published source={stage} flash=0x{pending.Source:X} pid={pending.Pid} epoch={pending.Epoch}");
            FireEmbedResult(pending.Completed, true);
            return true;
        }
    }
}
