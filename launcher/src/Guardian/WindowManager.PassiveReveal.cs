using System;
using System.Diagnostics;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;
using CF7Launcher.Guardian.InputOwnership;

namespace CF7Launcher.Guardian
{
    public partial class WindowManager
    {
        private const int WS_VISIBLE = 0x10000000;
        private sealed record PassiveReveal(IntPtr Source, uint Pid, uint SourceThread, long Epoch,
            Panel Host, IntPtr HostHandle, Form Root, IntPtr RootHandle, uint HostThread,
            SessionInputAuthority Authority, CancellationToken Cancellation, Action<EmbedResult> Completed,
            WindowsFormsSynchronizationContext Ui, Size Size, IntPtr DpiContext);

        private PassiveReveal _preparingPassiveReveal;

        [DllImport("user32.dll")] private static extern IntPtr GetThreadDpiAwarenessContext();
        [DllImport("user32.dll")] private static extern IntPtr SetThreadDpiAwarenessContext(IntPtr dpiContext);

        // The ordinary Web front door keeps the actual parent hidden until the
        // accepted scene is revealed. Full embed and visible hosts keep their existing path.
        private bool TryStartPassiveReveal(IntPtr source, uint pid, long epoch, Panel host, Form root,
            SessionInputAuthority authority, CancellationToken cancellation, Action<EmbedResult> completed,
            long uiPostedAt)
        {
            if (_passiveBootstrapUi == null || !HasLiveHandle(root) || !cancellation.CanBeCanceled
                || _flashHwnd != source || IsWindowEnabled(source) || HasVisibleStyle(host.Handle)) return false;
            IntPtr hostHandle = host.Handle, rootHandle = root.Handle;
            var work = new PassiveReveal(source, pid, GetWindowThreadProcessId(source, out _), epoch,
                host, hostHandle, root, rootHandle, GetWindowThreadProcessId(rootHandle, out _),
                authority, cancellation, completed, _passiveBootstrapUi, ResolveFlashRenderSize(),
                GetThreadDpiAwarenessContext());
            bool admitted;
            lock (_embedClaimLock)
            {
                if (_preparingPassiveReveal?.Cancellation == cancellation) return true;
                admitted = MatchesPassiveReveal(work) && HasPassiveRevealWindows(work);
                if (admitted) Volatile.Write(ref _preparingPassiveReveal, work);
            }
            if (!admitted)
            {
                if (!cancellation.IsCancellationRequested) FireEmbedResult(completed, EmbedResult.Superseded);
                return true;
            }
            LogManager.Log(FormattableString.Invariant($"event=passive_reveal_prepare stage=ui_thread source=0x{source:X} pid={pid} epoch={epoch} postToUiMs={Stopwatch.GetElapsedTime(uiPostedAt).TotalMilliseconds:F3}"));
            QueuePassiveReveal(work);
            return true;
        }

        private static bool HasVisibleStyle(IntPtr window) => (GetWindowLong(window, GWL_STYLE) & WS_VISIBLE) != 0;

        private bool MatchesPassiveReveal(PassiveReveal work) => !work.Cancellation.IsCancellationRequested
            && _flashHwnd == work.Source && _flashProcessId == work.Pid && EmbedEpoch == work.Epoch
            && ReferenceEquals(_hostPanel, work.Host) && ReferenceEquals(_sessionRoot, work.Root)
            && ReferenceEquals(PassiveInput, work.Authority) && _passiveRoot == work.RootHandle;

        private bool HasPassiveRevealWindows(PassiveReveal work) => work.SourceThread != 0 && work.HostThread != 0
            && GetWindowThreadProcessId(work.Source, out uint sourcePid) == work.SourceThread && sourcePid == work.Pid
            && GetWindowThreadProcessId(work.HostHandle, out uint hostPid) == work.HostThread && hostPid == _guardianProcessId
            && GetWindowThreadProcessId(work.RootHandle, out uint rootPid) == work.HostThread && rootPid == hostPid
            && GetParent(work.Source) == work.HostHandle && GetAncestor(work.HostHandle, 2) == work.RootHandle
            && !HasVisibleStyle(work.HostHandle);

        private bool CanPreparePassiveReveal(PassiveReveal work) =>
            ReferenceEquals(Volatile.Read(ref _preparingPassiveReveal), work) && MatchesPassiveReveal(work)
            && HasPassiveRevealWindows(work) && !IsWindowEnabled(work.Source);

        private bool IsPreparingPassiveReveal => Volatile.Read(ref _preparingPassiveReveal) is { } pending
            && pending.Source == _flashHwnd && pending.Epoch == EmbedEpoch;

        private bool TryGetPreparingPassiveRevealCloseTarget(CancellationToken ticket, uint pid,
            out UnpublishedBootstrapCloseTarget target)
        {
            target = default;
            PassiveReveal work = Volatile.Read(ref _preparingPassiveReveal);
            if (work == null || work.Cancellation != ticket || work.Pid != pid || !CanPreparePassiveReveal(work)) return false;
            target = new(work.Source, work.HostHandle);
            return true;
        }

        private void QueuePassiveReveal(PassiveReveal work)
        {
            if (!ThreadPool.QueueUserWorkItem(_ => PreparePassiveReveal(work)))
                CompletePassiveReveal(work, moved: false);
        }

        private void PreparePassiveReveal(PassiveReveal work)
        {
            bool moved = false;
            IntPtr previousDpi = IntPtr.Zero;
            try
            {
                if (work.DpiContext != IntPtr.Zero)
                {
                    previousDpi = SetThreadDpiAwarenessContext(work.DpiContext);
                    if (previousDpi == IntPtr.Zero) return;
                }
                if (!CanPreparePassiveReveal(work)) return;
#if CF7_TEST_SEAMS
                BeforePassiveRevealNativeForTests?.Invoke();
                if (!CanPreparePassiveReveal(work)) return;
#endif
                long nativeStart = Stopwatch.GetTimestamp();
                int cloakOff = 0;
                try { DwmSetWindowAttribute(work.Source, DWMWA_CLOAK, ref cloakOff, sizeof(int)); }
                catch { }
                long uncloaked = Stopwatch.GetTimestamp();
                if (!CanPreparePassiveReveal(work)) return;
                long showStart = Stopwatch.GetTimestamp();
                ShowWindow(work.Source, SW_SHOWNOACTIVATE);
                long shown = Stopwatch.GetTimestamp();
                if (!CanPreparePassiveReveal(work)) return;
                long moveStart = Stopwatch.GetTimestamp();
                moved = MoveWindow(work.Source, 0, 0, work.Size.Width, work.Size.Height, true);
                long movedAt = Stopwatch.GetTimestamp();
                if (!moved) LogWin32Failure("MoveWindow(passive reveal)", work.Source);
                LogManager.Log(FormattableString.Invariant($"event=passive_reveal_prepare stage=native_done source=0x{work.Source:X} pid={work.Pid} epoch={work.Epoch} uncloakMs={Stopwatch.GetElapsedTime(nativeStart, uncloaked).TotalMilliseconds:F3} showMs={Stopwatch.GetElapsedTime(showStart, shown).TotalMilliseconds:F3} resizeMs={Stopwatch.GetElapsedTime(moveStart, movedAt).TotalMilliseconds:F3}"));
            }
            catch (Exception error)
            {
                LogManager.Log("[WindowManager] Passive reveal preparation failed: " + error.GetType().Name);
            }
            finally
            {
                if (previousDpi != IntPtr.Zero) SetThreadDpiAwarenessContext(previousDpi);
                try { work.Ui.Post(_ => CompletePassiveReveal(work, moved), null); }
                catch (InvalidOperationException) { Interlocked.CompareExchange(ref _preparingPassiveReveal, null, work); }
                catch (System.ComponentModel.InvalidAsynchronousStateException)
                { Interlocked.CompareExchange(ref _preparingPassiveReveal, null, work); }
            }
        }

        private void CompletePassiveReveal(PassiveReveal work, bool moved)
        {
            PassiveReveal resized = null;
            bool ready = false;
            var failure = EmbedResult.Superseded;
            lock (_embedClaimLock)
            {
                if (!ReferenceEquals(Volatile.Read(ref _preparingPassiveReveal), work)) return;
                if (CanPreparePassiveReveal(work) && HasLiveHandle(work.Root) && work.Root.Handle == work.RootHandle
                    && HasLiveHandle(work.Host) && work.Host.Handle == work.HostHandle)
                {
                    failure = EmbedResult.Failed;
                    if (moved && HasVisibleStyle(work.Source))
                    {
                        Size latest = ResolveFlashRenderSize();
                        if (latest != work.Size)
                        {
                            // Only one native preparation is in flight. Use the latest bounds
                            // before publishing if the host resized during the previous call.
                            resized = work with { Size = latest, DpiContext = GetThreadDpiAwarenessContext() };
                        }
                        else if (UpdateFlashRenderSize() && CanPreparePassiveReveal(work))
                        {
                            Size actual = ActualFlashSourceSize, expected = SourcePixels(latest);
                            ready = Math.Abs(actual.Width - expected.Width) <= 1
                                && Math.Abs(actual.Height - expected.Height) <= 1;
                        }
                    }
                    if (ready) CompleteEmbedBindings(needFullEmbed: false);
                }
                Volatile.Write(ref _preparingPassiveReveal, resized);
            }
            if (resized != null) QueuePassiveReveal(resized);
            else if (ready) StagePassiveBootstrapPublication(work.Source, work.Pid, work.Epoch,
                work.Host, work.Cancellation, work.Completed);
            else if (!work.Cancellation.IsCancellationRequested) FireEmbedResult(work.Completed, failure);
        }

        private bool KeepPreparingPassiveRevealUnderHiddenHost(IntPtr source)
        {
            PassiveReveal work = Volatile.Read(ref _preparingPassiveReveal);
            return work != null && work.Source == source && HasPassiveRevealWindows(work);
        }

#if CF7_TEST_SEAMS
        internal Action BeforePassiveRevealNativeForTests { get; set; }
        internal bool PassiveRevealInFlightForTests => Volatile.Read(ref _preparingPassiveReveal) != null;
        internal bool PreparePassiveRevealForTests(Panel host, Form root, CancellationToken cancellation,
            Action<EmbedResult> completed)
        {
            _hostPanel = host;
            return TryStartPassiveReveal(_flashHwnd, _flashProcessId, EmbedEpoch, host, root,
                PassiveInput, cancellation, completed, Stopwatch.GetTimestamp());
        }
#endif
    }
}
