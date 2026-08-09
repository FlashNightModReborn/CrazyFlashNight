using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using Xunit;
using CF7Launcher.Audio;
using CF7Launcher.Bus;
using CF7Launcher.Tasks;

namespace CF7Launcher.Tests.Bus
{
    public class XmlSocketAudioV2Tests
    {
        private const string SessionId =
            "01234567-89ab-4cde-8f01-23456789abcd";

        [Fact]
        public void S2FastLane_ReachesRouterBoundFacadeWithoutTransportGeneration()
        {
            var facade = new SocketRecordingFacade();
            var router = new MessageRouter();
            var audio = new AudioTask(facade);
            TaskRegistry.RegisterAudioV2(router, audio);

            using var server = new XmlSocketServer(
                router,
                AllowLoopbackXmlSocketPeerAuthority.Instance);
            int port = ProbeFreePort();
            try
            {
                Assert.True(server.Start(port));
                using var client = Connect(port);
                SendFrame(
                    client,
                    "S2|" + SessionId + "|42|7|gun.wav|gun.wav");

                Assert.True(
                    facade.SfxAvailable.Wait(TimeSpan.FromSeconds(3)),
                    "S2 batch was not dispatched");
                AudioSfxBatchV2 batch = facade.LastSfx;
                Assert.NotNull(batch);
                Assert.Equal(SessionId, batch.AudioSessionId);
                Assert.Equal(42UL, batch.AudioReadyGeneration);
                Assert.Equal(7UL, batch.BatchSequence);
                Assert.Equal(new[] { "gun.wav", "gun.wav" }, batch.LinkageIds);
            }
            finally
            {
                AudioTask.ResetProcessFacadeForTests();
            }
        }

        [Fact]
        public void DelayedBgmResultFromOldConnection_IsDroppedAfterReplacement()
        {
            var facade = new SocketRecordingFacade();
            var router = new MessageRouter();
            router.RegisterSync("ping", delegate(JObject message)
            {
                return "{\"ok\":true}";
            });
            var audio = new AudioTask(facade);
            TaskRegistry.RegisterAudioV2(router, audio);

            using var server = new XmlSocketServer(
                router,
                AllowLoopbackXmlSocketPeerAuthority.Instance);
            int port = ProbeFreePort();
            try
            {
                Assert.True(server.Start(port));
                using var first = Connect(port);
                SendFrame(first, PlayEnvelope().ToString(Formatting.None));
                Assert.True(
                    facade.BgmAvailable.Wait(TimeSpan.FromSeconds(3)),
                    "BGM request was not dispatched");

                using var replacement = Connect(port);
                SendFrame(replacement, "{\"task\":\"ping\"}");
                JObject ping = JObject.Parse(ReadFrame(replacement, 3000));
                Assert.True((bool)ping["ok"]);

                facade.RespondStarted();

                replacement.ReceiveTimeout = 500;
                Assert.Throws<IOException>(() =>
                    replacement.GetStream().ReadByte());
                Assert.True(replacement.Connected);
            }
            finally
            {
                AudioTask.ResetProcessFacadeForTests();
            }
        }

        private static JObject PlayEnvelope()
        {
            return new JObject
            {
                ["task"] = "audio",
                ["wireRevision"] = AudioWireV2.WireRevision,
                ["requestId"] = "bgm.request.socket.1",
                ["audioSessionId"] = SessionId,
                ["audioReadyGeneration"] = "42",
                ["operation"] = AudioWireV2.BgmPlay,
                ["path"] = "sounds/music/test.mp3",
                ["loop"] = true,
                ["volume"] = 0.75d,
                ["fadeSeconds"] = 1.25d
            };
        }

        private static TcpClient Connect(int port)
        {
            var client = new TcpClient(AddressFamily.InterNetwork);
            client.Connect(IPAddress.Loopback, port);
            return client;
        }

        private static void SendFrame(TcpClient client, string message)
        {
            byte[] bytes = Encoding.UTF8.GetBytes(message + "\0");
            NetworkStream stream = client.GetStream();
            stream.Write(bytes, 0, bytes.Length);
            stream.Flush();
        }

        private static string ReadFrame(TcpClient client, int timeoutMs)
        {
            client.ReceiveTimeout = timeoutMs;
            var bytes = new MemoryStream();
            NetworkStream stream = client.GetStream();
            while (true)
            {
                int value = stream.ReadByte();
                if (value < 0) throw new EndOfStreamException();
                if (value == 0) break;
                bytes.WriteByte((byte)value);
            }
            return Encoding.UTF8.GetString(bytes.ToArray());
        }

        private static int ProbeFreePort()
        {
            var listener = new TcpListener(IPAddress.Loopback, 0);
            listener.Start();
            int port = ((IPEndPoint)listener.LocalEndpoint).Port;
            listener.Stop();
            return port;
        }

        private sealed class SocketRecordingFacade : IAudioCommandFacadeV2
        {
            private readonly object _gate = new object();
            private AudioBgmRequestV2 _request;
            private Action<AudioBgmResultV2> _respond;
            private AudioSfxBatchV2 _lastSfx;

            public readonly ManualResetEventSlim BgmAvailable =
                new ManualResetEventSlim(false);
            public readonly ManualResetEventSlim SfxAvailable =
                new ManualResetEventSlim(false);

            public AudioSfxBatchV2 LastSfx
            {
                get
                {
                    lock (_gate) return _lastSfx;
                }
            }

            public void DispatchBgm(
                AudioBgmRequestV2 request,
                Action<AudioBgmResultV2> respond)
            {
                lock (_gate)
                {
                    _request = request;
                    _respond = respond;
                }
                BgmAvailable.Set();
            }

            public void RespondStarted()
            {
                AudioBgmRequestV2 request;
                Action<AudioBgmResultV2> respond;
                lock (_gate)
                {
                    request = _request;
                    respond = _respond;
                }
                Assert.NotNull(request);
                Assert.NotNull(respond);
                respond(new AudioBgmResultV2(
                    request.RequestId,
                    request.AudioSessionId,
                    request.AudioReadyGeneration,
                    5,
                    request.Operation,
                    "started",
                    "ok",
                    "native_start",
                    0,
                    0,
                    "builtin",
                    "audio.bgm.started"));
            }

            public void RejectBgm(string protocolError)
            {
            }

            public void DispatchSfx(AudioSfxBatchV2 batch)
            {
                lock (_gate) _lastSfx = batch;
                SfxAvailable.Set();
            }

            public void RejectSfx(string protocolError)
            {
            }

            public void ArmBootstrapBgmGate()
            {
            }

            public void CancelBootstrapBgmGate()
            {
            }

            public void ReleaseBootstrapBgmGate()
            {
            }
        }
    }
}
