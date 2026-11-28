using System;
using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;
using CF7Launcher.Bus;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.WorldCompositor;
using Xunit;

namespace CF7Launcher.Tests.Guardian;

public sealed class GameLaunchFlowFrontdoorStartupCloseTests
{
    [Fact]
    public void ReadyBeforeAnyEntryUsesStartupCloseAndStillHonorsPersistenceFence() => R1UiAdapterTests.Sta(() =>
    {
        using var launch = new LaunchFixture();
        Assert.Equal((1, 0, true), launch.RefuseAtPersistenceFence());
        Assert.False(launch.Guardian.IsDisposed);
        Assert.False(launch.Guardian.IsShutdownAdmissionClosed);
        Assert.Equal(nameof(GameLaunchFlow.State.Ready), launch.Flow.CurrentState);
    });

    [Fact]
    public void AcceptedFencePostsOnlyToTheExactChildAndRetiresOnlyItsConnection() => R1UiAdapterTests.Sta(() =>
    {
        using var launch = new LaunchFixture();
        using var posted = new ManualResetEventSlim();
        bool saved = false;
        var posts = new System.Collections.Concurrent.ConcurrentQueue<(Process, WindowManager.UnpublishedBootstrapCloseTarget, string, bool, bool)>();
        launch.Manager.CloseStartupFlashForTests = (process, target, phase) =>
        {
            bool accepted = ProcessManager.TryPostUnpublishedBootstrapClose(target, (uint)process.Id);
            posts.Enqueue((process, target, phase, saved, accepted));
            posted.Set();
            return accepted;
        };
        launch.Guardian.OnShutdownFence = () =>
        {
            Assert.True(launch.Guardian.IsShutdownAdmissionClosed);
            launch.SendTitle();
            Assert.False(launch.EntryDispatched);
            saved = true;
            return true;
        };
        launch.CloseFromSystemMenu();
        Assert.True(posted.Wait(TimeSpan.FromSeconds(2)));
        var actual = Assert.Single(posts);
        Assert.Same(launch.WindowOwner, actual.Item1);
        Assert.Equal(launch.FlashWindow, actual.Item2.Window);
        Assert.Equal(launch.Guardian.FlashHostPanel.Handle, actual.Item2.Host);
        Assert.Equal("unentered", actual.Item3);
        Assert.True(actual.Item4);
        Assert.True(actual.Item5);
        Assert.True(SpinWait.SpinUntil(() => !launch.ConnectionReady, TimeSpan.FromSeconds(2)));
        Assert.False(launch.EntryDispatched);
        Assert.NotNull(launch.Flow.CommittedStartupClose);
        Assert.NotEqual(nameof(GameLaunchFlow.State.Error), launch.Flow.CurrentState);

        using var compositor = WorldCompositorTests.RenderController(launch.Guardian);
        compositor.PerformanceUnavailable += () => throw new InvalidOperationException("Unexpected runtime fault route");
        Call(compositor, "EnterRenderFault", "fault queued before child exit", new InvalidOperationException("child closing"));
        Assert.False(Get<bool>(compositor, "_faulted"));
    });

    [Fact]
    public void ConnectionReplacementDuringPersistenceKeepsFenceAndDoesNotCloseNewGeneration() => R1UiAdapterTests.Sta(() =>
    {
        using var launch = new LaunchFixture();
        Func<bool> persistence = () =>
        {
            launch.ReplaceConnection();
            return true;
        };
        launch.Guardian.OnShutdownFence = persistence;
        launch.CloseFromSystemMenu();
        Assert.Same(persistence, launch.Guardian.OnShutdownFence);
        Assert.False(launch.Guardian.IsShutdownAdmissionClosed);
        Assert.Null(launch.Flow.CommittedStartupClose);
        Assert.True(launch.ConnectionReady);
        Assert.Equal(nameof(GameLaunchFlow.State.Ready), launch.Flow.CurrentState);
    });

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void RenderFaultStillUsesRuntimeReportingWithoutCommittedClose(bool fenceRefused) => R1UiAdapterTests.Sta(() =>
    {
        using var launch = new LaunchFixture();
        if (fenceRefused) Assert.Equal((1, 0, true), launch.RefuseAtPersistenceFence());
        using var compositor = WorldCompositorTests.RenderController(launch.Guardian);
        var sentinel = new InvalidOperationException("Report path reached before the modal");
        compositor.PerformanceUnavailable += () => throw sentinel;
        var reported = Assert.Throws<TargetInvocationException>(() =>
            Call(compositor, "EnterRenderFault", "real fault", new InvalidOperationException("render unavailable")));
        Assert.Same(sentinel, reported.InnerException);
        Assert.True(Get<bool>(compositor, "_faulted"));
    });

    [Theory]
    [InlineData("entry-sent")]
    [InlineData("scene-accepted")]
    [InlineData("already-revealed")]
    [InlineData("replacement-window")]
    [InlineData("replacement-connection")]
    [InlineData("another-attempt")]
    public void ReadyWithEntryOrMissingCurrentProofUsesTheExistingPersistencePath(string condition) => R1UiAdapterTests.Sta(() =>
    {
        using var launch = new LaunchFixture();
        switch (condition)
        {
            case "entry-sent": launch.DispatchRealEntry(); break;
            case "scene-accepted": Set(launch.Flow, "_revealWaitingScene", false); break;
            case "already-revealed": Set(launch.Flow, "_revealPerformed", true); break;
            case "replacement-window": launch.Window.RetrackBootstrapSourceForTests(); break;
            case "replacement-connection": launch.ReplaceConnection(); break;
            case "another-attempt": Set(launch.Flow, "_currentAttemptId", "superseding-attempt"); break;
        }

        Assert.Equal((1, 1, true), launch.RefuseAtPersistenceFence());
        Assert.False(launch.Guardian.IsDisposed);
        Assert.False(launch.Guardian.IsShutdownAdmissionClosed);
    });

    private sealed class LaunchFixture : IDisposable
    {
        private const string Attempt = "ordinary-preworld-close";
        private readonly MessageRouter _router = new();
        private readonly XmlSocketServer _server;
        private readonly ProcessManager _processManager = new("unused-flash.exe", "unused.swf");
        private readonly Process _windowOwner = Process.GetCurrentProcess();
        private readonly Panel _source = new();
        private readonly int _port;
        private TcpClient _client;
        public GuardianForm Guardian { get; } = new();
        public WindowManager Window { get; }
        public GameLaunchFlow Flow { get; }
        public ProcessManager Manager => _processManager;
        public Process WindowOwner => _windowOwner;
        public IntPtr FlashWindow => _source.Handle;
        public bool ConnectionReady => _server.IsClientReady;
        public bool EntryDispatched => Get<bool>(Flow, "_frontdoorEntryDispatched");

        public LaunchFixture()
        {
            IntPtr host = Guardian.FlashHostPanel.Handle;
            IntPtr flash = _source.Handle;
            SetParent(flash, host);
            Assert.Equal(host, GetParent(flash));
            EnableWindow(flash, false);
            Guardian.FlashHostPanel.Hide();
            Assert.False(Guardian.FlashHostPanel.Visible);

            Window = new WindowManager();
            Call(Window, "SetTrackedFlashWindow", flash);
            Window.TrackProcess(_windowOwner);
            Window.ConfigurePassiveInput(R1UiAdapterTests.StartGameAuthority(), Guardian);
            Window.PassiveBootstrapFocusForTests = () => (true, false, false);

            var listener = new TcpListener(IPAddress.Loopback, 0);
            listener.Start();
            _port = ((IPEndPoint)listener.LocalEndpoint).Port;
            listener.Stop();
            _server = new XmlSocketServer(_router, AllowLoopbackXmlSocketPeerAuthority.Instance);
            Assert.True(_server.Start(_port));
            _client = Connect();
            Flow = new GameLaunchFlow(_server, _router, _processManager, Window, Guardian, null, null, null, null);
            Guardian.InitializeLaunchFlow(Flow);

            var cancellation = new CancellationTokenSource();
            CancellationToken ticket = cancellation.Token;
            int generation = _server.CurrentGeneration;
            Set(Flow, "_state", GameLaunchFlow.State.Embedding);
            Set(Flow, "_currentAttemptId", Attempt);
            Set(Flow, "_pendingSlot", "ordinary-qa");
            Set(Flow, "_currentFlashProcess", _windowOwner);
            Set(Flow, "_passiveLaunchConnection", generation);
            Set(Flow, "_passiveEmbeddingCancellation", cancellation);
            Call(Flow, "ConfigureFrontdoorAttemptLocked", "load", null);
            Set(Flow, "_revealWaitingFlash", true);

            Assert.Null(_router.ProcessMessage(BootstrapRequest("bootstrap_ready"), generation, null));
            int offers = 0;
            Window.StageBootstrapOfferForTests(Guardian.FlashHostPanel, ticket, result =>
            {
                Assert.Equal(WindowManager.EmbedResult.Prepared, result);
                ++offers;
                Call(Flow, "OnPassiveEmbedResult", _windowOwner, Attempt, generation, ticket, result);
            });
            Assert.Equal(1, offers);
            Assert.True(ticket.IsCancellationRequested);
            Assert.Equal(nameof(GameLaunchFlow.State.Ready), Flow.CurrentState);
            Assert.False(Get<bool>(Flow, "_frontdoorEntryDispatched"));
            Assert.False(Flow.RevealPerformed);
        }

        public void SendTitle() =>
            _router.ProcessMessage(BootstrapRequest("bootstrap_reveal_ready"), _server.CurrentGeneration, null);

        public void DispatchRealEntry()
        {
            SendTitle();
            Assert.True(EntryDispatched);
        }

        public void ReplaceConnection()
        {
            int oldGeneration = _server.CurrentGeneration;
            using var prior = _client;
            _client = Connect(oldGeneration);
            Assert.True(_server.CurrentGeneration > oldGeneration);
        }

        public (int FenceCalls, int LegacyCloseCommitted, bool AdmissionClosed) RefuseAtPersistenceFence()
        {
            int calls = 0;
            int committed = -1;
            bool closed = false;
            Guardian.OnShutdownFence = () =>
            {
                ++calls;
                committed = Get<int>(Guardian, "_closeTerminated");
                closed = Guardian.IsShutdownAdmissionClosed;
                return false;
            };
            CloseFromSystemMenu();
            Guardian.OnShutdownFence = null;
            return (calls, committed, closed);
        }

        public void CloseFromSystemMenu() => SendMessage(Guardian.Handle, 0x0112, new IntPtr(0xF060), IntPtr.Zero);

        private static string BootstrapRequest(string task) =>
            "{\"task\":\"" + task + "\",\"payload\":{\"attemptId\":\"" + Attempt + "\"}}";

        private TcpClient Connect(int priorGeneration = -1)
        {
            var client = new TcpClient(AddressFamily.InterNetwork);
            client.Connect(IPAddress.Loopback, _port);
            client.GetStream().Write(Encoding.UTF8.GetBytes("{\"task\":\"frontdoor_close_probe\"}\0"));
            Assert.True(SpinWait.SpinUntil(() => _server.IsClientReady && _server.CurrentGeneration > priorGeneration, TimeSpan.FromSeconds(2)));
            return client;
        }

        public void Dispose()
        {
            Set(Flow, "_state", GameLaunchFlow.State.Idle);
            _client.Dispose();
            _server.Dispose();
            _processManager.Dispose();
            Window.StopWatchdog();
            Window.StopPassiveFocusAudit();
            _source.Dispose();
            Guardian.Dispose();
            _windowOwner.Dispose();
        }
    }

    private const BindingFlags InstancePrivate = BindingFlags.Instance | BindingFlags.NonPublic;
    private static void Set(object target, string field, object value) => target.GetType().GetField(field, InstancePrivate)!.SetValue(target, value);
    private static T Get<T>(object target, string field) => (T)target.GetType().GetField(field, InstancePrivate)!.GetValue(target);
    private static void Call(object target, string method, params object[] arguments) => target.GetType().GetMethod(method, InstancePrivate)!.Invoke(target, arguments);

    [DllImport("user32.dll")]
    private static extern IntPtr SetParent(IntPtr child, IntPtr parent);
    [DllImport("user32.dll")]
    private static extern IntPtr GetParent(IntPtr child);
    [DllImport("user32.dll")]
    private static extern bool EnableWindow(IntPtr window, bool enabled);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr SendMessage(IntPtr target, uint message, IntPtr wParam, IntPtr lParam);
}
