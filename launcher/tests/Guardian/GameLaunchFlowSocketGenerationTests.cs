using System;
using System.Net;
using System.Net.Sockets;
using System.Reflection;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.Bus;
using CF7Launcher.Guardian;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class GameLaunchFlowSocketGenerationTests
    {
        [Theory]
        [InlineData(GameLaunchFlow.State.Spawning)]
        [InlineData(GameLaunchFlow.State.WaitingConnect)]
        [InlineData(GameLaunchFlow.State.WaitingHandshake)]
        public void PrewarmReplacementDisconnect_PreservesAttempt(
            GameLaunchFlow.State state)
        {
            Assert.Equal(GameLaunchFlow.SocketDisconnectDisposition.Ignore,
                GameLaunchFlow.ClassifySocketDisconnect(4, 5, state,
                    pendingSlotIsNull: true, prewarmAborting: false));
        }

        [Fact]
        public void PrewarmHeldReplacement_RestartsGenerationBoundHandshake()
        {
            Assert.Equal(GameLaunchFlow.SocketDisconnectDisposition.RestartPrewarmHandshake,
                GameLaunchFlow.ClassifySocketDisconnect(4, 5,
                    GameLaunchFlow.State.PrewarmHandshakeHeld,
                    pendingSlotIsNull: true, prewarmAborting: false));
        }

        [Theory]
        [InlineData(GameLaunchFlow.State.Spawning)]
        [InlineData(GameLaunchFlow.State.WaitingConnect)]
        [InlineData(GameLaunchFlow.State.WaitingHandshake)]
        [InlineData(GameLaunchFlow.State.PrewarmHandshakeHeld)]
        public void PrewarmCurrentGenerationEof_StillDegrades(
            GameLaunchFlow.State state)
        {
            Assert.Equal(GameLaunchFlow.SocketDisconnectDisposition.DegradePrewarm,
                GameLaunchFlow.ClassifySocketDisconnect(5, 5, state,
                    pendingSlotIsNull: true, prewarmAborting: false));
        }

        [Fact]
        public void ReadyReplacementDisconnect_ArmsUntilBusinessReady()
        {
            Assert.Equal(GameLaunchFlow.SocketDisconnectDisposition.ArmReadyZombie,
                GameLaunchFlow.ClassifySocketDisconnect(8, 9,
                    GameLaunchFlow.State.Ready, pendingSlotIsNull: false,
                    prewarmAborting: false));
        }

        [Fact]
        public void ReadyCurrentGenerationEof_StillArmsZombie()
        {
            Assert.Equal(GameLaunchFlow.SocketDisconnectDisposition.ArmReadyZombie,
                GameLaunchFlow.ClassifySocketDisconnect(9, 9,
                    GameLaunchFlow.State.Ready, pendingSlotIsNull: false,
                    prewarmAborting: false));
        }


        [Fact]
        public void HeldGenerationReplacement_NewReadyAndHandshakeCanComplete()
        {
            int port = GetFreePort();
            var router = new MessageRouter();
            using var server = new XmlSocketServer(
                router,
                AllowLoopbackXmlSocketPeerAuthority.Instance);
            using var processManager = new ProcessManager("unused-flash.exe", "unused.swf");
            var flow = new GameLaunchFlow(server, router, processManager,
                new WindowManager(), null, null, null, null, null);
            SetPrivateField(flow, "_state", GameLaunchFlow.State.WaitingConnect);
            SetPrivateField(flow, "_currentAttemptId", "attempt-held-replacement");
            Assert.True(server.Start(port));

            using var first = new TcpClient(AddressFamily.InterNetwork);
            first.Connect(IPAddress.Loopback, port);
            Assert.True(SpinWait.SpinUntil(() => server.HasClient,
                TimeSpan.FromSeconds(2)));
            int firstGeneration = server.CurrentGeneration;
            Send(first, "{\"task\":\"bootstrap_handshake\",\"callId\":1}");
            Assert.True(SpinWait.SpinUntil(
                () => flow.CurrentState == GameLaunchFlow.State.PrewarmHandshakeHeld.ToString(),
                TimeSpan.FromSeconds(2)));

            using var replacement = new TcpClient(AddressFamily.InterNetwork);
            replacement.Connect(IPAddress.Loopback, port);
            Assert.True(SpinWait.SpinUntil(
                () => server.CurrentGeneration > firstGeneration && server.HasClient,
                TimeSpan.FromSeconds(2)));
            Assert.Equal(GameLaunchFlow.State.WaitingConnect.ToString(), flow.CurrentState);

            Send(replacement, "{\"task\":\"bootstrap_handshake\",\"callId\":2}");
            Assert.True(SpinWait.SpinUntil(
                () => flow.CurrentState == GameLaunchFlow.State.PrewarmHandshakeHeld.ToString(),
                TimeSpan.FromSeconds(2)));

            flow.StartGame("slot-test");
            JObject response = ReadJsonFrame(replacement);
            Assert.True(response.Value<bool>("success"));
            Assert.Equal(2, response.Value<int>("callId"));
            Assert.Equal("attempt-held-replacement", response.Value<string>("attemptId"));
            Assert.Equal(GameLaunchFlow.State.WaitingGameReady.ToString(), flow.CurrentState);
        }

        [Fact]
        public async Task HeldStartGame_WhenReplacementReservesFirst_CompletesOnReplacementHandshake()
        {
            int port = GetFreePort();
            var router = new MessageRouter();
            using var server = new XmlSocketServer(
                router,
                AllowLoopbackXmlSocketPeerAuthority.Instance);
            using var processManager = new ProcessManager("unused-flash.exe", "unused.swf");
            var flow = new GameLaunchFlow(server, router, processManager,
                new WindowManager(), null, null, null, null, null);
            SetPrivateField(flow, "_state", GameLaunchFlow.State.WaitingConnect);
            SetPrivateField(flow, "_currentAttemptId", "attempt-replacement-wins");
            Assert.True(server.Start(port));

            using var first = new TcpClient(AddressFamily.InterNetwork);
            first.Connect(IPAddress.Loopback, port);
            Assert.True(SpinWait.SpinUntil(() => server.HasClient,
                TimeSpan.FromSeconds(2)));
            int firstGeneration = server.CurrentGeneration;
            Send(first, "{\"task\":\"bootstrap_handshake\",\"callId\":11}");
            Assert.True(SpinWait.SpinUntil(
                () => flow.CurrentState == GameLaunchFlow.State.PrewarmHandshakeHeld.ToString(),
                TimeSpan.FromSeconds(2)));

            using var beforeFence = new ManualResetEventSlim(false);
            using var releaseStart = new ManualResetEventSlim(false);
            using var replacementReserved = new ManualResetEventSlim(false);
            using var releaseReplacement = new ManualResetEventSlim(false);
            Task startTask = null;
            flow.BeforeHeldTransitionFenceForTests = delegate
            {
                beforeFence.Set();
                if (!releaseStart.Wait(TimeSpan.FromSeconds(5)))
                    throw new TimeoutException("test did not release StartGame before transition fence");
            };
            server.AfterReplacementGenerationReservedForTests = delegate(int oldGeneration,
                int newGeneration)
            {
                if (oldGeneration != firstGeneration) return;
                replacementReserved.Set();
                releaseReplacement.Wait(TimeSpan.FromSeconds(5));
            };

            using var replacement = new TcpClient(AddressFamily.InterNetwork);
            try
            {
                startTask = Task.Run(() => flow.StartGame("slot-replacement-wins"));
                Assert.True(beforeFence.Wait(TimeSpan.FromSeconds(2)));

                replacement.Connect(IPAddress.Loopback, port);
                Assert.True(replacementReserved.Wait(TimeSpan.FromSeconds(2)));
                Assert.True(server.CurrentGeneration > firstGeneration);

                // StartGame already passed its optimistic Held check.  Let it contend for the
                // transition fence while accept still owns the new generation reservation.
                releaseStart.Set();
                await Task.Delay(100);
                Assert.False(startTask.IsCompleted);
                releaseReplacement.Set();
                await startTask.WaitAsync(TimeSpan.FromSeconds(5));
                Assert.True(SpinWait.SpinUntil(
                    () => server.HasClient
                        && flow.CurrentState == GameLaunchFlow.State.WaitingConnect.ToString(),
                    TimeSpan.FromSeconds(2)));

                Send(replacement, "{\"task\":\"bootstrap_handshake\",\"callId\":12}");
                JObject response = ReadJsonFrame(replacement);
                Assert.True(response.Value<bool>("success"));
                Assert.Equal(12, response.Value<int>("callId"));
                Assert.Equal("attempt-replacement-wins", response.Value<string>("attemptId"));
                Assert.Equal(GameLaunchFlow.State.WaitingGameReady.ToString(), flow.CurrentState);
            }
            finally
            {
                releaseStart.Set();
                releaseReplacement.Set();
                flow.BeforeHeldTransitionFenceForTests = null;
                server.AfterReplacementGenerationReservedForTests = null;
                if (startTask != null && !startTask.IsCompleted)
                {
                    try { await startTask.WaitAsync(TimeSpan.FromSeconds(5)); }
                    catch { }
                }
            }
        }

        [Fact]
        public async Task HeldStartGame_WhenFlushOwnsFence_SendsOldResponseBeforeReplacement()
        {
            int port = GetFreePort();
            var router = new MessageRouter();
            using var server = new XmlSocketServer(
                router,
                AllowLoopbackXmlSocketPeerAuthority.Instance);
            using var processManager = new ProcessManager("unused-flash.exe", "unused.swf");
            var flow = new GameLaunchFlow(server, router, processManager,
                new WindowManager(), null, null, null, null, null);
            SetPrivateField(flow, "_state", GameLaunchFlow.State.WaitingConnect);
            SetPrivateField(flow, "_currentAttemptId", "attempt-flush-wins");
            Assert.True(server.Start(port));

            using var first = new TcpClient(AddressFamily.InterNetwork);
            first.Connect(IPAddress.Loopback, port);
            Assert.True(SpinWait.SpinUntil(() => server.HasClient,
                TimeSpan.FromSeconds(2)));
            int firstGeneration = server.CurrentGeneration;
            Send(first, "{\"task\":\"bootstrap_handshake\",\"callId\":21}");
            Assert.True(SpinWait.SpinUntil(
                () => flow.CurrentState == GameLaunchFlow.State.PrewarmHandshakeHeld.ToString(),
                TimeSpan.FromSeconds(2)));

            using var beforeSend = new ManualResetEventSlim(false);
            using var releaseSend = new ManualResetEventSlim(false);
            using var acceptReachedFence = new ManualResetEventSlim(false);
            using var releaseAccept = new ManualResetEventSlim(false);
            Task startTask = null;
            Task<JObject> responseTask = null;
            flow.BeforeHeldCallbackSendForTests = delegate
            {
                beforeSend.Set();
                if (!releaseSend.Wait(TimeSpan.FromSeconds(5)))
                    throw new TimeoutException("test did not release held callback send");
            };
            server.BeforeAcceptTransitionForTests = delegate
            {
                acceptReachedFence.Set();
                releaseAccept.Wait(TimeSpan.FromSeconds(5));
            };

            using var replacement = new TcpClient(AddressFamily.InterNetwork);
            try
            {
                responseTask = Task.Run(() => ReadJsonFrame(first));
                startTask = Task.Run(() => flow.StartGame("slot-flush-wins"));
                Assert.True(beforeSend.Wait(TimeSpan.FromSeconds(2)));

                replacement.Connect(IPAddress.Loopback, port);
                Assert.True(acceptReachedFence.Wait(TimeSpan.FromSeconds(2)));
                releaseAccept.Set();

                // StartGame owns the transition fence through the actual gen-bound write, so
                // replacement cannot advance ownership or close the old stream before this send.
                Assert.Equal(firstGeneration, server.CurrentGeneration);
                releaseSend.Set();
                await startTask.WaitAsync(TimeSpan.FromSeconds(5));
                JObject response = await responseTask.WaitAsync(TimeSpan.FromSeconds(5));
                Assert.True(response.Value<bool>("success"));
                Assert.Equal(21, response.Value<int>("callId"));
                Assert.Equal("attempt-flush-wins", response.Value<string>("attemptId"));
                Assert.True(SpinWait.SpinUntil(
                    () => server.CurrentGeneration > firstGeneration && server.HasClient,
                    TimeSpan.FromSeconds(2)));
                Assert.Equal(GameLaunchFlow.State.WaitingGameReady.ToString(), flow.CurrentState);
            }
            finally
            {
                releaseAccept.Set();
                releaseSend.Set();
                flow.BeforeHeldCallbackSendForTests = null;
                server.BeforeAcceptTransitionForTests = null;
                if (startTask != null && !startTask.IsCompleted)
                {
                    try { await startTask.WaitAsync(TimeSpan.FromSeconds(5)); }
                    catch { }
                }
                if (responseTask != null && !responseTask.IsCompleted)
                {
                    try { first.Close(); } catch { }
                    try { await responseTask.WaitAsync(TimeSpan.FromSeconds(1)); }
                    catch { }
                }
            }
        }

        [Fact]
        public void ReadyReplacement_WatchdogStaysArmedUntilBusinessReady()
        {
            int port = GetFreePort();
            var router = new MessageRouter();
            using var server = new XmlSocketServer(
                router,
                AllowLoopbackXmlSocketPeerAuthority.Instance);
            using var processManager = new ProcessManager("unused-flash.exe", "unused.swf");
            var flow = new GameLaunchFlow(server, router, processManager,
                new WindowManager(), null, null, null, null, null);
            SetPrivateField(flow, "_state", GameLaunchFlow.State.Ready);
            SetPrivateField(flow, "_currentAttemptId", "attempt-ready-replacement");
            Assert.True(server.Start(port));

            using var first = new TcpClient(AddressFamily.InterNetwork);
            first.Connect(IPAddress.Loopback, port);
            Assert.True(SpinWait.SpinUntil(() => server.HasClient,
                TimeSpan.FromSeconds(2)));
            int firstGeneration = server.CurrentGeneration;
            Send(first, "{\"task\":\"unknown_first\"}");
            Assert.True(SpinWait.SpinUntil(() => server.IsClientReady,
                TimeSpan.FromSeconds(2)));

            using var replacement = new TcpClient(AddressFamily.InterNetwork);
            replacement.Connect(IPAddress.Loopback, port);
            Assert.True(SpinWait.SpinUntil(
                () => server.CurrentGeneration > firstGeneration && server.HasClient,
                TimeSpan.FromSeconds(2)));
            Assert.False(server.IsClientReady);
            Assert.True(SpinWait.SpinUntil(
                () => GetPrivateField<System.Threading.Timer>(flow, "_zombieTimer") != null,
                TimeSpan.FromSeconds(2)));

            Send(replacement, "{\"task\":\"unknown_replacement\"}");
            Assert.True(SpinWait.SpinUntil(() => server.IsClientReady,
                TimeSpan.FromSeconds(2)));
            Assert.True(SpinWait.SpinUntil(
                () => GetPrivateField<System.Threading.Timer>(flow, "_zombieTimer") == null,
                TimeSpan.FromSeconds(2)));

            // Keep socket disposal from exercising the production Ready-state shutdown watchdog
            // after this assertion-only fixture has already completed.
            SetPrivateField(flow, "_state", GameLaunchFlow.State.Idle);
        }

        private static void Send(TcpClient client, string json)
        {
            byte[] bytes = Encoding.UTF8.GetBytes(json + "\0");
            NetworkStream stream = client.GetStream();
            stream.Write(bytes, 0, bytes.Length);
            stream.Flush();
        }

        private static JObject ReadJsonFrame(TcpClient client)
        {
            NetworkStream stream = client.GetStream();
            stream.ReadTimeout = 5000;
            var bytes = new System.Collections.Generic.List<byte>();
            while (true)
            {
                int next = stream.ReadByte();
                if (next < 0) throw new InvalidOperationException("socket closed before response");
                if (next == 0) break;
                bytes.Add((byte)next);
            }
            return JObject.Parse(Encoding.UTF8.GetString(bytes.ToArray()));
        }

        private static int GetFreePort()
        {
            var probe = new TcpListener(IPAddress.Loopback, 0);
            probe.Start();
            int port = ((IPEndPoint)probe.LocalEndpoint).Port;
            probe.Stop();
            return port;
        }

        private static void SetPrivateField<T>(GameLaunchFlow flow, string name, T value)
        {
            FieldInfo field = typeof(GameLaunchFlow).GetField(name,
                BindingFlags.Instance | BindingFlags.NonPublic);
            Assert.NotNull(field);
            field.SetValue(flow, value);
        }

        private static T GetPrivateField<T>(GameLaunchFlow flow, string name)
        {
            FieldInfo field = typeof(GameLaunchFlow).GetField(name,
                BindingFlags.Instance | BindingFlags.NonPublic);
            Assert.NotNull(field);
            return (T)field.GetValue(flow);
        }
    }
}
