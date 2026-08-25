using System;
using System.Collections.Generic;
using System.Drawing;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using CF7Launcher.Bus;
using CF7Launcher.Guardian;
using Xunit;

namespace CF7Launcher.Tests.Bus
{
    public class XmlSocketStageTimerTests
    {
        [Fact]
        public void StageTimerFastLane_ProjectsIndependentKeyedRowsAndCleanup()
        {
            var sink = new RecordingNotchSink();
            using var server = CreateServer(sink);

            Assert.True(server.HandleStageTimerFastLane("T+|rescue|600|救出键盘"));
            Assert.True(server.HandleStageTimerFastLane("T+|escape|65|撤离核电站"));

            Assert.Equal("⏱ 救出键盘 · 剩余 10:00", sink.Get("stage_timer:rescue").Label);
            Assert.Equal(Color.FromArgb(100, 200, 255),
                sink.Get("stage_timer:escape").Accent);

            Assert.True(server.HandleStageTimerFastLane("T-|rescue"));
            Assert.False(sink.Contains("stage_timer:rescue"));
            Assert.True(sink.Contains("stage_timer:escape"));

            Assert.True(server.HandleStageTimerFastLane("T!"));
            Assert.Empty(sink.Snapshot());
        }

        [Theory]
        [InlineData(61, 100, 200, 255)]
        [InlineData(60, 255, 200, 80)]
        [InlineData(10, 255, 96, 96)]
        [InlineData(0, 255, 96, 96)]
        public void StageTimerFastLane_FormatsSecondsAndUrgencyColor(
            int remaining, int red, int green, int blue)
        {
            var sink = new RecordingNotchSink();
            using var server = CreateServer(sink);

            Assert.True(server.HandleStageTimerFastLane(
                "T+|pilot|" + remaining + "|章节计时"));

            StatusItem item = sink.Get("stage_timer:pilot");
            Assert.EndsWith((remaining / 60).ToString("00") + ":"
                + (remaining % 60).ToString("00"), item.Label);
            Assert.Equal(Color.FromArgb(red, green, blue), item.Accent);
        }

        [Theory]
        [InlineData("T+")]
        [InlineData("T+|Upper|10|章节")]
        [InlineData("T+|valid|01|章节")]
        [InlineData("T+|valid|3601|章节")]
        [InlineData("T+|valid|-1|章节")]
        [InlineData("T+|valid|10| 章节")]
        [InlineData("T+|valid|10|章节 ")]
        [InlineData("T+|valid|10|章节|注入")]
        [InlineData("T-|valid|extra")]
        [InlineData("T!extra")]
        public void StageTimerFastLane_RejectsMalformedMessages(string message)
        {
            var sink = new RecordingNotchSink();
            using var server = CreateServer(sink);

            Assert.False(server.HandleStageTimerFastLane(message));
            Assert.Empty(sink.Snapshot());
        }

        [Fact]
        public void StageTimerFastLane_SocketDispatchesAndDisconnectClearsRows()
        {
            var sink = new RecordingNotchSink();
            using var server = CreateServer(sink);
            int port = ProbeFreePort();
            Assert.True(server.Start(port));

            using (var client = new TcpClient(AddressFamily.InterNetwork))
            {
                client.Connect(IPAddress.Loopback, port);
                byte[] bytes = Encoding.UTF8.GetBytes("T+|jk_job|300|任务时限\0");
                NetworkStream stream = client.GetStream();
                stream.Write(bytes, 0, bytes.Length);
                stream.Flush();
                Assert.True(SpinWait.SpinUntil(
                    () => sink.Contains("stage_timer:jk_job"),
                    TimeSpan.FromSeconds(3)));
            }

            Assert.True(SpinWait.SpinUntil(
                () => !sink.Contains("stage_timer:jk_job"),
                TimeSpan.FromSeconds(3)));
        }

        private static XmlSocketServer CreateServer(INotchSink sink)
        {
            var server = new XmlSocketServer(
                new MessageRouter(),
                AllowLoopbackXmlSocketPeerAuthority.Instance);
            server.SetNotchHandler(sink);
            return server;
        }

        private static int ProbeFreePort()
        {
            var listener = new TcpListener(IPAddress.Loopback, 0);
            listener.Start();
            int port = ((IPEndPoint)listener.LocalEndpoint).Port;
            listener.Stop();
            return port;
        }

        private sealed class StatusItem
        {
            public string Label;
            public Color Accent;
        }

        private sealed class RecordingNotchSink : INotchSink
        {
            private readonly object _gate = new object();
            private readonly Dictionary<string, StatusItem> _items =
                new Dictionary<string, StatusItem>(StringComparer.Ordinal);

            public void AddNotice(string category, string text, Color accentColor)
            {
            }

            public void SetStatusItem(
                string id, string label, string subLabel, Color accentColor)
            {
                lock (_gate)
                {
                    _items[id] = new StatusItem
                    {
                        Label = label,
                        Accent = accentColor
                    };
                }
            }

            public void ClearStatusItem(string id)
            {
                lock (_gate) _items.Remove(id);
            }

            public void SetReady()
            {
            }

            public bool Contains(string id)
            {
                lock (_gate) return _items.ContainsKey(id);
            }

            public StatusItem Get(string id)
            {
                lock (_gate) return _items[id];
            }

            public StatusItem[] Snapshot()
            {
                lock (_gate)
                {
                    var result = new StatusItem[_items.Count];
                    _items.Values.CopyTo(result, 0);
                    return result;
                }
            }
        }
    }
}
