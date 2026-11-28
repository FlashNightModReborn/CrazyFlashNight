using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;
using CF7Launcher.Guardian;
using Xunit;

namespace CF7Launcher.Tests.Guardian;

public sealed class WindowManagerPassiveRevealTests
{
    [Fact]
    public void NormalCloseDispatchesWhilePassiveRevealIsBlockedAndRetiresTheExactSource() =>
        R1UiAdapterTests.Sta(() =>
        {
            using var fixture = new Fixture();
            using var ticket = new CancellationTokenSource();
            using var other = new CancellationTokenSource();
            using var entered = new ManualResetEventSlim();
            using var resume = new ManualResetEventSlim();
            fixture.Manager.BeforePassiveRevealNativeForTests = () =>
            {
                entered.Set();
                resume.Wait(TimeSpan.FromSeconds(6));
            };
            uint pid = (uint)Environment.ProcessId;
            int hostThread = Environment.CurrentManagedThreadId;
            int closeThread = 0;
            fixture.Guardian.NormalClose = () =>
            {
                closeThread = Environment.CurrentManagedThreadId;
                ticket.Cancel();
            };
            try
            {
                Assert.True(fixture.Start(ticket.Token));
                PumpUntil(() => entered.IsSet);
                Assert.True(fixture.Manager.TryGetUnpublishedBootstrapCloseTarget(ticket.Token, pid, out var target));
                Assert.Equal(fixture.Source.Handle, target.Window);
                Assert.Equal(fixture.Host.Handle, target.Host);
                Assert.False(fixture.Manager.TryGetUnpublishedBootstrapCloseTarget(other.Token, pid, out _));
                Assert.False(fixture.Manager.TryGetUnpublishedBootstrapCloseTarget(ticket.Token, pid + 1, out _));

                Assert.True(PostMessage(fixture.Guardian.Handle, 0x0112, new IntPtr(0xf060), IntPtr.Zero));
                PumpUntil(() => ticket.IsCancellationRequested);
                Assert.Equal(hostThread, closeThread);
                Assert.True(fixture.Manager.PassiveRevealInFlightForTests);
                Assert.False(fixture.Manager.TryGetUnpublishedBootstrapCloseTarget(ticket.Token, pid, out _));
                Assert.Empty(fixture.Results);
                // Legacy emergency cleanup also keeps an in-flight source inside the hidden host.
                fixture.Manager.DetachFlash();
                Assert.Equal(fixture.Host.Handle, GetParent(fixture.Source.Handle));
            }
            finally
            {
                resume.Set();
                PumpUntil(() => !fixture.Manager.PassiveRevealInFlightForTests);
            }
            Assert.Empty(fixture.Results);
            Assert.False(HasVisibleStyle(fixture.Source));
            Assert.False(HasVisibleStyle(fixture.Host));
            Assert.Empty(fixture.Focus.ForegroundWrites);
        });

    [Fact]
    public void PassiveRevealPublishesOnlyAfterTheLatestGeometryIsObserved() =>
        R1UiAdapterTests.Sta(() =>
        {
            using var fixture = new Fixture();
            using var ticket = new CancellationTokenSource();
            using var entered = new ManualResetEventSlim();
            using var resume = new ManualResetEventSlim();
            int nativeCalls = 0;
            fixture.Manager.BeforePassiveRevealNativeForTests = () =>
            {
                Interlocked.Increment(ref nativeCalls);
                entered.Set();
                resume.Wait(TimeSpan.FromSeconds(6));
            };
            var latest = new Size(704, 392);
            try
            {
                Assert.True(fixture.Start(ticket.Token));
                PumpUntil(() => entered.IsSet);
                fixture.Host.Size = latest;
                fixture.Manager.ResizeFlashToPanel();
                Assert.NotEqual(latest, fixture.Source.ClientSize);
                Assert.Empty(fixture.Results);
            }
            finally
            {
                resume.Set();
                PumpUntil(() => !fixture.Manager.PassiveRevealInFlightForTests);
            }
            Assert.Equal(2, Volatile.Read(ref nativeCalls));
            Assert.Equal(WindowManager.EmbedResult.Prepared, Assert.Single(fixture.Results));
            Assert.Equal(latest, fixture.Source.ClientSize);
            IntPtr source = fixture.Source.Handle;
            DpiDiagnostics.TryGetWindowDpi(source, out uint dpi, out _);
            DpiDiagnostics.TryGetMonitorDpi(DpiDiagnostics.GetMonitorFromWindow(source), out uint monitorX, out uint monitorY);
            FlashSnapshot.ComputeCaptureSourceSize(latest.Width, latest.Height,
                DpiAwarenessBootstrap.GetEffectiveAwarenessForWindow(source), dpi, monitorX, monitorY,
                out int captureWidth, out int captureHeight);
            Assert.Equal(new Size(captureWidth, captureHeight), fixture.Manager.ActualFlashSourceSize);
            Assert.False(fixture.Manager.FlashIsEnabled);
            Assert.True(HasVisibleStyle(fixture.Source));
            Assert.False(HasVisibleStyle(fixture.Host));
            Assert.True(fixture.Manager.TryAcceptPassiveBootstrap(ticket.Token, static () => { }));
            Assert.Empty(fixture.Focus.ForegroundWrites);
        });

    private static void PumpUntil(Func<bool> condition)
    {
        var deadline = Stopwatch.StartNew();
        while (!condition() && deadline.Elapsed < TimeSpan.FromSeconds(4))
        {
            Application.DoEvents();
            Thread.Sleep(1);
        }
        Assert.True(condition(), "The local STA did not reach its expected state.");
    }

    private static bool HasVisibleStyle(Control window) => (GetWindowLong(window.Handle, -16) & 0x10000000) != 0;

    private sealed class Fixture : IDisposable
    {
        public CloseRecordingForm Guardian { get; } = new();
        public Panel Host { get; } = new() { Visible = false, Size = new Size(500, 280) };
        public Panel Source { get; } = new() { Size = new Size(250, 140) };
        public RootFocusApi Focus { get; } = new() { Foreground = new IntPtr(0x9ab) };
        public WindowManager Manager { get; }
        public List<WindowManager.EmbedResult> Results { get; } = new();

        public Fixture()
        {
            _ = Guardian.Handle;
            Guardian.Controls.Add(Host);
            if (GetParent(Host.Handle) != Guardian.Handle) SetParent(Host.Handle, Guardian.Handle);
            Assert.Equal(Guardian.Handle, GetParent(Host.Handle));
            IntPtr source = Source.Handle;
            if (GetParent(source) != Host.Handle) SetParent(source, Host.Handle);
            ShowWindow(source, 0);
            Manager = new WindowManager(Focus, source);
            using var process = Process.GetCurrentProcess();
            Manager.TrackProcess(process);
            Manager.ConfigurePassiveInput(R1UiAdapterTests.StartGameAuthority(), Guardian);
            Manager.PassiveBootstrapFocusForTests = () => (true, false, false);
        }

        public bool Start(CancellationToken ticket) =>
            Manager.PreparePassiveRevealForTests(Host, Guardian, ticket, Results.Add);

        public void Dispose()
        {
            Manager.StopWatchdog();
            Manager.StopPassiveFocusAudit();
            Source.Dispose();
            Guardian.Dispose();
        }
    }

    private sealed class CloseRecordingForm : Form
    {
        internal Action NormalClose;

        protected override void WndProc(ref Message message)
        {
            if (message.Msg == 0x0112 && (message.WParam.ToInt64() & 0xfff0) == 0xf060 && NormalClose != null)
            {
                NormalClose();
                return;
            }
            base.WndProc(ref message);
        }
    }

    [DllImport("user32.dll", EntryPoint = "PostMessageW")] private static extern bool PostMessage(IntPtr window, int message, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongW")] private static extern int GetWindowLong(IntPtr window, int index);
    [DllImport("user32.dll")] private static extern IntPtr GetParent(IntPtr window);
    [DllImport("user32.dll")] private static extern IntPtr SetParent(IntPtr window, IntPtr parent);
    [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr window, int show);
}
