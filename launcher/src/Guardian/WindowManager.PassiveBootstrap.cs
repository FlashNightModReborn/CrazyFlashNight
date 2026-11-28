using System;
using System.Threading;
using System.Windows.Forms;
using CF7Launcher.Guardian.InputOwnership;

namespace CF7Launcher.Guardian
{
    public partial class WindowManager
    {
        internal enum EmbedResult { Prepared, Failed, Cancelled, Superseded }

        private sealed record PassiveBootstrapPublication(IntPtr Source, uint Pid, long Epoch,
            Panel Host, Form Root, SessionInputAuthority Authority, Action<EmbedResult> Completed,
            CancellationToken Cancellation)
        {
            // Only the UI lane updates the continuous return-to-Guardian observation.
            public IntPtr ForegroundRoot;
            public long? ForegroundSince;
            public PassiveBootstrapWindows? OfferedWindows;
            public string OfferStage;
        }

        private readonly record struct PassiveBootstrapWindows(IntPtr Host, IntPtr Root);
        internal readonly record struct UnpublishedBootstrapCloseTarget(IntPtr Window, IntPtr Host);

        internal const int PassiveBootstrapForegroundGraceMs = 6000;
        private PassiveBootstrapPublication _pendingPassiveBootstrap;
        private PassiveBootstrapPublication _publishedPassiveBootstrap;
        private WindowsFormsSynchronizationContext _passiveBootstrapUi;

#if CF7_TEST_SEAMS
        internal Func<(bool Known, bool Focused, bool Enabled)> PassiveBootstrapFocusForTests { get; set; }

        internal void StagePassiveBootstrapForTests(Panel host, Action<bool> completed,
            CancellationToken cancellation = default)
        {
            _hostPanel = host;
            StagePassiveBootstrapPublication(_flashHwnd, _flashProcessId, EmbedEpoch, host, cancellation,
                result => completed(result == EmbedResult.Prepared
                    && TryAcceptPassiveBootstrap(cancellation, static () => { })));
        }

        internal void StageBootstrapOfferForTests(Panel host, CancellationToken ticket, Action<EmbedResult> outcome)
        {
            _hostPanel = host;
            StagePassiveBootstrapPublication(_flashHwnd, _flashProcessId, EmbedEpoch, host, ticket, outcome);
        }

        internal void RetrackBootstrapSourceForTests() => SetTrackedFlashWindow(_flashHwnd);

        internal void RunEmbedWatchdogForTests(long now = 0) => CheckEmbedWatchdog(now);
        internal void ObserveBootstrapForegroundForTests(IntPtr foreground) => ObserveBootstrapForeground(foreground);

        internal bool RecoverPassiveBootstrapForTests()
        {
            var pending = Volatile.Read(ref _pendingPassiveBootstrap);
            return pending != null && TryReadBootstrapWindows(pending, out var windows)
                && TryPreparePassiveBootstrap(pending, "guardian_activation", useStartupCorrection: true,
                    expectedForeground: windows.Root);
        }
#endif

        internal void CancelPassiveBootstrapPublication(CancellationToken ticket, string reason)
        {
            lock (_embedClaimLock)
                if (_pendingPassiveBootstrap?.Cancellation == ticket)
                    RetirePassiveBootstrapLocked(EmbedResult.Cancelled, reason);
        }

        internal bool TryGetUnpublishedBootstrapCloseTarget(CancellationToken ticket, uint pid,
            out UnpublishedBootstrapCloseTarget target)
        {
            target = default;
            lock (_embedClaimLock)
            {
                PassiveBootstrapPublication pending = _pendingPassiveBootstrap;
                if (pending == null)
                    return TryGetPreparingPassiveRevealCloseTarget(ticket, pid, out target);
                if (!ticket.CanBeCanceled || pending.Cancellation != ticket || pending.Pid != pid
                    || !IsCurrentBootstrapAttempt(pending) || !IsBootstrapSourceAlive(pending)
                    || !TryReadBootstrapWindows(pending, out PassiveBootstrapWindows windows)
                    || GetParent(pending.Source) != windows.Host || IsWindowEnabled(pending.Source)) return false;
                target = new(pending.Source, windows.Host);
                return true;
            }
        }

        internal bool TryGetPublishedBootstrapCloseTarget(CancellationToken ticket, uint pid,
            out UnpublishedBootstrapCloseTarget target)
        {
            target = default;
            lock (_embedClaimLock)
            {
                PassiveBootstrapPublication published = _publishedPassiveBootstrap;
                // Embedding retires its token after Host accepts publication. The original
                // token still identifies that publication without making it pending again.
                if (published == null || !ticket.CanBeCanceled || published.Cancellation != ticket || published.Pid != pid
                    || !HasCurrentBootstrapSource(published) || !IsBootstrapSourceAlive(published)
                    || published.OfferedWindows is not PassiveBootstrapWindows offered
                    || !TryReadBootstrapWindows(published, out var windows) || windows != offered
                    || GetParent(published.Source) != windows.Host || IsWindowEnabled(published.Source)) return false;
                target = new(published.Source, windows.Host);
                return true;
            }
        }

        private void RetirePassiveBootstrapLocked(EmbedResult result, string reason)
        {
            Action<EmbedResult> completion = TakePassiveBootstrapLocked(result, reason);
            if (completion != null)
                ThreadPool.QueueUserWorkItem(_ => FireEmbedResult(completion, result));
        }

        private Action<EmbedResult> TakePassiveBootstrapLocked(EmbedResult result, string reason)
        {
            PassiveBootstrapPublication pending = _pendingPassiveBootstrap;
            if (pending == null) return null;
            Volatile.Write(ref _pendingPassiveBootstrap, null);
            LogPassiveBootstrapTerminal(pending, result, reason);
            // An offer owns the one callback already. Its Host consumer will reject
            // the retired ticket. The caller invokes any new callback outside the lock.
            return pending.OfferedWindows == null ? pending.Completed : null;
        }

        private static void LogPassiveBootstrapTerminal(PassiveBootstrapPublication pending, EmbedResult result, string reason)
        {
            LogManager.Log($"event=passive_bootstrap_publication stage={result.ToString().ToLowerInvariant()} reason={reason} flash=0x{pending.Source:X} pid={pending.Pid} epoch={pending.Epoch}");
        }

        private bool WasPassiveBootstrapPublished(IntPtr source)
        {
            var published = Volatile.Read(ref _publishedPassiveBootstrap);
            return published != null && source == published.Source && _flashProcessId == published.Pid
                && EmbedEpoch == published.Epoch && ReferenceEquals(PassiveInput, published.Authority);
        }

        private void StagePassiveBootstrapPublication(IntPtr source, uint pid, long epoch, Panel host,
            CancellationToken cancellation, Action<EmbedResult> completed)
        {
            var pending = new PassiveBootstrapPublication(source, pid, epoch, host, _sessionRoot,
                PassiveInput, completed, cancellation);
            EmbedResult? rejected = null;
            lock (_embedClaimLock)
            {
                if (cancellation.IsCancellationRequested) rejected = EmbedResult.Cancelled;
                else if (!IsCurrentBootstrapAttempt(pending)) rejected = EmbedResult.Superseded;
                else if (_pendingPassiveBootstrap?.Cancellation == cancellation
                    || _publishedPassiveBootstrap?.Cancellation == cancellation) return;
                else if (_pendingPassiveBootstrap != null && IsCurrentBootstrapAttempt(_pendingPassiveBootstrap))
                    rejected = EmbedResult.Superseded;
                else
                {
                    RetirePassiveBootstrapLocked(EmbedResult.Superseded, "replacement_stage");
                    Volatile.Write(ref _pendingPassiveBootstrap, pending);
                }
            }
            if (rejected is EmbedResult result)
            {
                LogPassiveBootstrapTerminal(pending, result, "stage_rejected");
                FireEmbedResult(completed, result);
                return;
            }

            if (!TryReadBootstrapWindows(pending, out var windows) || !IsBootstrapSourceAlive(pending))
            {
                FailPassiveBootstrap(pending, "invalid_window");
                return;
            }
            if (GetParent(source) != windows.Host)
            {
                FailPassiveBootstrap(pending, "source_parent_mismatch");
                return;
            }

            if (!TryPreparePassiveBootstrap(pending, "embed_reveal", useStartupCorrection: true)
                && ReferenceEquals(Volatile.Read(ref _pendingPassiveBootstrap), pending))
                LogManager.Log($"event=passive_bootstrap_publication stage=pending flash=0x{source:X} pid={pid} epoch={pending.Epoch}");
        }

        private bool IsCurrentBootstrapAttempt(PassiveBootstrapPublication pending)
        {
            return !pending.Cancellation.IsCancellationRequested && HasCurrentBootstrapSource(pending);
        }

        private bool HasCurrentBootstrapSource(PassiveBootstrapPublication publication) =>
            publication.Authority != null && ReferenceEquals(PassiveInput, publication.Authority)
            && publication.Source != IntPtr.Zero && _flashHwnd == publication.Source && _flashProcessId == publication.Pid
            && EmbedEpoch == publication.Epoch;

        private static bool IsBootstrapSourceAlive(PassiveBootstrapPublication pending) =>
            GetWindowThreadProcessId(pending.Source, out uint sourcePid) != 0 && sourcePid == pending.Pid;

        private static bool HasLiveHandle(Control control) => control != null && !control.IsDisposed
            && !control.Disposing && control.IsHandleCreated;

        private bool TryReadBootstrapWindows(PassiveBootstrapPublication pending, out PassiveBootstrapWindows windows)
        {
            windows = default;
            if (!ReferenceEquals(_sessionRoot, pending.Root) || !ReferenceEquals(_hostPanel, pending.Host)
                || !HasLiveHandle(pending.Root) || !HasLiveHandle(pending.Host)) return false;
            IntPtr root = pending.Root.Handle, host = pending.Host.Handle;
            if (root == IntPtr.Zero || root != _passiveRoot || host == IntPtr.Zero) return false;
            windows = new PassiveBootstrapWindows(host, root);
            return true;
        }

        private bool StillHasBootstrapWindows(PassiveBootstrapPublication pending, PassiveBootstrapWindows expected)
        {
            return ReferenceEquals(Volatile.Read(ref _pendingPassiveBootstrap), pending)
                && IsCurrentBootstrapAttempt(pending) && IsBootstrapSourceAlive(pending)
                && TryReadBootstrapWindows(pending, out var windows) && windows == expected
                && GetParent(pending.Source) == windows.Host;
        }

        private bool IsExactBootstrapForeground(IntPtr root) => root != IntPtr.Zero
            && ReadCloseForeground() == root && IsWindowEnabled(root) && !IsIconic(root);

        private bool ReadSafeBootstrapFocus(PassiveBootstrapPublication pending, PassiveBootstrapWindows windows)
        {
            uint thread = GetWindowThreadProcessId(pending.Source, out uint pid);
            if (thread == 0 || pid != pending.Pid) return false;
            var sample = ReadPassiveFocusSample(pending.Source, windows.Root, thread, matchingSource: true);
            return sample.Known && !sample.Focused && !sample.Enabled;
        }

        private void FailPassiveBootstrap(PassiveBootstrapPublication pending, string reason,
            PassiveBootstrapWindows? afterForegroundGrace = null)
        {
            Action<EmbedResult> completion;
            lock (_embedClaimLock)
            {
                if (!ReferenceEquals(Volatile.Read(ref _pendingPassiveBootstrap), pending)
                    || !IsCurrentBootstrapAttempt(pending)) return;
                if (afterForegroundGrace is PassiveBootstrapWindows windows
                    && (!StillHasBootstrapWindows(pending, windows) || !IsExactBootstrapForeground(windows.Root)
                        || ReadSafeBootstrapFocus(pending, windows)
                        || !StillHasBootstrapWindows(pending, windows) || !IsExactBootstrapForeground(windows.Root))) return;
                completion = TakePassiveBootstrapLocked(EmbedResult.Failed, reason);
                if (!IsBootstrapSourceAlive(pending)) SetTrackedFlashWindow(IntPtr.Zero);
            }
            FireEmbedResult(completion, EmbedResult.Failed);
        }

        private void ObserveBootstrapForeground(IntPtr foreground)
        {
            PassiveBootstrapPublication pending = Volatile.Read(ref _pendingPassiveBootstrap);
            if (pending?.ForegroundSince == null || foreground == IntPtr.Zero
                || foreground == pending.ForegroundRoot || foreground == _passiveRoot
                || !_focusApi.IsWindow(foreground) || ReadCloseForeground() != foreground
                || pending.Root.RecreatingHandle || pending.Host.RecreatingHandle
                || !TryReadBootstrapWindows(pending, out var windows)
                || InsideFlash(pending.Source, foreground) || IsSessionOwnedSource(foreground, windows.Root)
                || IsSessionOwnedSource(foreground, pending.ForegroundRoot)) return;
            // A native handle/lane change is not a new user wait. Reset only after
            // positively observing an unrelated window actually holding foreground.
            pending.ForegroundSince = null;
        }

        private void CheckPendingPassiveBootstrap(PassiveBootstrapPublication pending, long now)
        {
            if (!IsCurrentBootstrapAttempt(pending))
            {
                Action<EmbedResult> completion = null;
                EmbedResult result;
                lock (_embedClaimLock)
                {
                    result = pending.Cancellation.IsCancellationRequested ? EmbedResult.Cancelled : EmbedResult.Superseded;
                    if (ReferenceEquals(Volatile.Read(ref _pendingPassiveBootstrap), pending)
                        && !IsCurrentBootstrapAttempt(pending))
                        completion = TakePassiveBootstrapLocked(result, "attempt_retired");
                }
                FireEmbedResult(completion, result);
                return;
            }
            if (pending.OfferedWindows != null) return;
            if (!IsBootstrapSourceAlive(pending))
            {
                FailPassiveBootstrap(pending, "source_lost");
                return;
            }
            // RecreateHandle is synchronous on this UI thread. A nested native callback
            // can observe the in-between state. The next watchdog turn checks again.
            if (pending.Root?.RecreatingHandle == true || pending.Host.RecreatingHandle) return;
            if (!TryReadBootstrapWindows(pending, out var windows))
            {
                FailPassiveBootstrap(pending, "host_lost");
                return;
            }
            if (GetParent(pending.Source) != windows.Host)
            {
                try { DoEmbedOrReveal(pending.Source, needFullEmbed: true); }
                catch (Exception ex)
                {
                    LogManager.Log("[WindowManager] Embed recovery failed: " + ex.Message);
                    FailPassiveBootstrap(pending, "source_parent_unrecoverable");
                    return;
                }
                if (!TryReadBootstrapWindows(pending, out windows) || GetParent(pending.Source) != windows.Host)
                {
                    FailPassiveBootstrap(pending, "source_parent_unrecoverable");
                    return;
                }
            }
            // Retry a lost/transient correction only after this Guardian has genuinely
            // regained the foreground. The ordinary passive audit can publish anywhere.
            if (TryPreparePassiveBootstrap(pending, "embed_watchdog", useStartupCorrection: true,
                expectedForeground: windows.Root)) return;

            if (!StillHasBootstrapWindows(pending, windows) || !IsExactBootstrapForeground(windows.Root))
            {
                ObserveBootstrapForeground(ReadCloseForeground());
                return;
            }
            pending.ForegroundRoot = windows.Root;
            if (pending.ForegroundSince is not long since)
            {
                pending.ForegroundSince = now;
                return;
            }
            if (now - since >= PassiveBootstrapForegroundGraceMs)
                FailPassiveBootstrap(pending, "foreground_focus_unavailable", windows);
        }

        private void QueuePassiveBootstrapRecovery()
        {
            PassiveBootstrapPublication pending = Volatile.Read(ref _pendingPassiveBootstrap);
            if (pending == null || !TryReadBootstrapWindows(pending, out var windows)
                || ReadCloseForeground() != windows.Root)
                return;
            try
            {
                _passiveBootstrapUi?.Post(_ => TryPreparePassiveBootstrap(pending,
                    "guardian_activation", useStartupCorrection: true, expectedForeground: windows.Root), null);
            }
            catch (InvalidOperationException) { }
        }

        private bool TryPreparePassiveBootstrap(PassiveBootstrapPublication pending, string stage,
            bool useStartupCorrection = false, IntPtr expectedForeground = default)
        {
            if (!TryReadBootstrapWindows(pending, out var windows)) return false;
            bool Current() => StillHasBootstrapWindows(pending, windows)
                && pending.OfferedWindows == null
                && (expectedForeground == IntPtr.Zero || (expectedForeground == windows.Root
                    && IsExactBootstrapForeground(expectedForeground)));
            if (!Current()) return false;
            bool valid = useStartupCorrection ? SettleBootstrapFocus(pending.Source, stage)
                : AuditPassiveFocus(out _, stage);
            if (!valid) return false;
            lock (_embedClaimLock)
            {
                // The earlier observation can become stale before the commit lock.
                // Read both GUI threads and the disabled style again without side effects.
                if (!Current() || !ReadSafeBootstrapFocus(pending, windows) || !Current()) return false;
                pending.OfferedWindows = windows;
                pending.OfferStage = stage;
            }
            FireEmbedResult(pending.Completed, EmbedResult.Prepared);
            return true;
        }

        internal bool TryAcceptPassiveBootstrap(CancellationToken ticket, Action acceptHost)
        {
            lock (_embedClaimLock)
            {
                PassiveBootstrapPublication pending = _pendingPassiveBootstrap;
                if (pending == null || pending.Cancellation != ticket
                    || pending.OfferedWindows is not PassiveBootstrapWindows windows) return false;
                if (!StillHasBootstrapWindows(pending, windows) || !ReadSafeBootstrapFocus(pending, windows)
                    || !StillHasBootstrapWindows(pending, windows))
                {
                    RetirePassiveBootstrapLocked(EmbedResult.Failed, "host_commit_invalidated");
                    return false;
                }
                Volatile.Write(ref _pendingPassiveBootstrap, null);
                Volatile.Write(ref _publishedPassiveBootstrap, pending);
                LogManager.Log($"event=passive_bootstrap_publication stage=published source={pending.OfferStage} flash=0x{pending.Source:X} pid={pending.Pid} epoch={pending.Epoch} root=0x{windows.Root:X} host=0x{windows.Host:X} commitQueried=true commitRaw=false commitEnabled=false");
                acceptHost();
                return true;
            }
        }
    }
}
