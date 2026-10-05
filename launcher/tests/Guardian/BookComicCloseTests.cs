using System;
using System.Collections.Generic;
using System.Net;
using System.Net.Sockets;
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Text;
using CF7Launcher.Bus;
using CF7Launcher.Guardian;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public class BookComicCloseTests
    {
        private sealed class Harness : IDisposable
        {
            internal readonly Queue<Action> Pumps = new Queue<Action>();
            internal readonly List<JObject> Commands = new List<JObject>();
            internal readonly PanelHostController Host;
            internal readonly BookComicTask Task;
            internal readonly WebOverlayForm Form;
            internal readonly JObject Data = new JObject
            {
                ["v"] = 1, ["presentationId"] = "bookcomic:1",
                ["slot"] = "bookrun_fixture", ["sceneId"] = "scene:1",
                ["pageId"] = "prologue"
            };
            private readonly TcpClient sender;
            private readonly TcpClient receiver;
            internal int Settled;

            internal Harness()
            {
                // Exercise the production exact-close callback and actual unpause wire.
                // Only transport readiness and native surfaces are fixtures; no game is attached.
                var listener = new TcpListener(IPAddress.Loopback, 0);
                listener.Start();
                sender = new TcpClient();
                sender.Connect((IPEndPoint)listener.LocalEndpoint);
                receiver = listener.AcceptTcpClient();
                listener.Stop();
                receiver.GetStream().ReadTimeout = 2000;
                var socket = (XmlSocketServer)RuntimeHelpers.GetUninitializedObject(typeof(XmlSocketServer));
                Set(socket, "_clientLock", new object());
                Set(socket, "_client", sender);
                Set(socket, "_stream", sender.GetStream());
                Set(socket, "_clientReady", true);
                Form = (WebOverlayForm)RuntimeHelpers.GetUninitializedObject(typeof(WebOverlayForm));
                GC.SuppressFinalize(Form);
                Host = new PanelHostController(a => Pumps.Enqueue(a), a => a());
                Set(Form, "_panelHost", Host);
                Set(Form, "_socketServer", socket);
                Form.SetPanelStateCallback(open =>
                {
                    Assert.False(open);
                    Assert.Null(Host.ActivePanelName);
                    Settled++;
                });
                Task = new BookComicTask(() => true, wire =>
                {
                    Commands.Add(JObject.Parse(wire.TrimEnd('\0')));
                    return true;
                });
                Task.SetPostToWeb(_ => { }, null, Form.CloseBookComicPresentation);
                Host.SetBookComicTask(Task);
                Host.SetPanelCloseObserver((panel, instance) =>
                {
                    if (panel == "book-comic") Task.OnHostClosed(instance);
                });
            }

            internal string Open()
            {
                Assert.True(Task.Reserve(Data));
                Assert.True(Host.TryOpenPanel("book-comic", Data.ToString(), null, null));
                Pump();
                return Host.ActivePanelInstanceId;
            }

            internal void Pump()
            {
                while (Pumps.Count > 0) Pumps.Dequeue()();
            }

            internal JObject Finish(string command)
            {
                Task.HandleWebRequest(command, new JObject
                {
                    ["panel"] = "book-comic", ["domain"] = "book-comic",
                    ["cmd"] = command, ["callId"] = "web:finish",
                    ["panelInstanceId"] = Host.ActivePanelInstanceId,
                    ["payload"] = Data.DeepClone()
                });
                var reply = (JObject)Assert.Single(Commands).DeepClone();
                reply["operation"] = "finish";
                reply["success"] = true;
                reply["phase"] = command == "failed" ? "expired" : "finished";
                reply["error"] = "";
                Task.HandleFlashResponse(reply, null);
                return reply;
            }

            internal void AssertNoUnpause()
            {
                Assert.Equal(0, receiver.Available);
                Assert.Equal(0, Settled);
            }

            internal void AssertSingleUnpause()
            {
                var bytes = new List<byte>();
                int next;
                while ((next = receiver.GetStream().ReadByte()) > 0) bytes.Add((byte)next);
                Assert.Equal(0, next);
                var command = JObject.Parse(Encoding.UTF8.GetString(bytes.ToArray()));
                Assert.Equal("cmd", (string)command["task"]);
                Assert.Equal("webPanelUnpause", (string)command["action"]);
                Assert.Equal(2, command.Count);
                Assert.Equal(0, receiver.Available);
                Assert.Equal(1, Settled);
            }

            public void Dispose()
            {
                Host.Dispose();
                Task.Dispose();
                sender.Dispose();
                receiver.Dispose();
            }
        }

        private static void Set(object target, string name, object value) =>
            target.GetType().GetField(name, BindingFlags.Instance | BindingFlags.NonPublic)
                .SetValue(target, value);

        [Theory]
        [InlineData("continue")]
        [InlineData("skip")]
        [InlineData("failed")]
        public void TerminalReplyReleasesWebPauseOnlyAfterExactVisualClose(string command)
        {
            using var h = new Harness();
            h.Open();
            var reply = h.Finish(command);
            h.AssertNoUnpause();
            Assert.Equal("book-comic", h.Host.ActivePanelName);
            h.Pump();
            h.Task.HandleFlashResponse(reply, null);
            h.Pump();
            Assert.Null(h.Host.ActivePanelName);
            h.AssertSingleUnpause();
        }

        [Fact]
        public void GameExpiryAlsoReleasesTheClosedPanelClaim()
        {
            using var h = new Harness();
            string instance = h.Open();
            var expired = (JObject)h.Data.DeepClone();
            expired["callId"] = 0;
            expired["panelInstanceId"] = instance;
            expired["operation"] = "finish";
            expired["phase"] = "expired";
            expired["success"] = true;
            h.Task.HandleFlashResponse(expired, null);
            h.AssertNoUnpause();
            h.Pump();
            h.AssertSingleUnpause();
        }

        [Fact]
        public void QueuedOldCloseCannotReleaseReplacementPanelPause()
        {
            using var h = new Harness();
            h.Open();
            Assert.True(h.Host.TryOpenPanel("settings", "{}", null, null));
            h.Finish("continue");
            h.Pump();
            Assert.Equal("settings", h.Host.ActivePanelName);
            h.AssertNoUnpause();
        }

        [Fact]
        public void OldInstanceCannotCloseOrUnpauseTheNextComic()
        {
            using var h = new Harness();
            string first = h.Open();
            h.Finish("continue");
            h.Pump();
            h.AssertSingleUnpause();
            h.Settled = 0;
            h.Data["presentationId"] = "bookcomic:2";
            h.Data["pageId"] = "boss";
            string second = h.Open();
            h.Form.CloseBookComicPresentation(first);
            h.Pump();
            Assert.Equal(second, h.Host.ActivePanelInstanceId);
            h.AssertNoUnpause();
        }

        [Fact]
        public void RejectedCloseDoesNotReleasePause()
        {
            using var h = new Harness();
            string instance = h.Open();
            h.Host.Dispose();
            h.Form.CloseBookComicPresentation(instance);
            h.AssertNoUnpause();
        }
    }
}
