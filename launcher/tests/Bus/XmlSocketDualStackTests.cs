// Regression guard for the IPv4/IPv6 loopback bind asymmetry (#2).
//
// Before fix: XmlSocketServer bound only IPAddress.Loopback (IPv4 127.0.0.1).
//   On modern Windows "localhost" resolves to ::1 first, so a client targeting
//   ::1 could never reach the IPv4-only listener -> socket_connect_timeout.
//   (Real game tolerates it because Flash falls back to 127.0.0.1, but we harden
//   against environments that only try ::1.)
// After fix: also listen on IPv6 loopback (::1), staying loopback-only (NOT
//   IPv6Any) so the port is never exposed beyond the local machine.
//
// These tests pin both loopback families as acceptable connection targets.

using System;
using System.Collections.Concurrent;
using System.Linq;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using CF7Launcher.Bus;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Bus
{
    public class XmlSocketDualStackTests : IDisposable
    {
        private readonly XmlSocketServer _server;
        private readonly MessageRouter _router;
        private TcpClient _client;
        private readonly ConcurrentQueue<string> _payloads = new ConcurrentQueue<string>();
        private readonly SemaphoreSlim _avail = new SemaphoreSlim(0);
        private readonly int _port;

        public XmlSocketDualStackTests()
        {
            _router = new MessageRouter();
            _router.RegisterSync("dualstack_ping", delegate(JObject msg)
            {
                _payloads.Enqueue(msg.Value<string>("payload"));
                _avail.Release();
                return "{\"ok\":true}";
            });

            _server = new XmlSocketServer(
                _router,
                AllowLoopbackXmlSocketPeerAuthority.Instance);
            _port = ProbeFreePort();
            Assert.True(_server.Start(_port), "XmlSocketServer failed to start on probed port " + _port);
        }

        public void Dispose()
        {
            try { if (_client != null) _client.Close(); } catch { }
            try { _server.Dispose(); } catch { }
            try { _avail.Dispose(); } catch { }
        }

        [Fact]
        public void AcceptsIPv4Loopback()
        {
            ConnectAndRoundTrip(IPAddress.Loopback, "v4");
        }

        [Fact]
        public void AcceptsIPv6Loopback()
        {
            // The fix makes the IPv6 loopback listener best-effort: on hosts with IPv6
            // disabled the server runs IPv4-only and there is nothing to assert here.
            if (!IPv6LoopbackAvailable())
                return;
            ConnectAndRoundTrip(IPAddress.IPv6Loopback, "v6");
        }

        // ───────────── Helpers ─────────────

        [Fact]
        public void GenerationBoundForceClose_DoesNotDisconnectReplacementClient()
        {
            TcpClient first = new TcpClient(AddressFamily.InterNetwork);
            first.Connect(IPAddress.Loopback, _port);
            Assert.True(SpinWait.SpinUntil(delegate { return _server.HasClient; },
                TimeSpan.FromSeconds(2)));
            int firstGeneration = _server.CurrentGeneration;

            TcpClient replacement = new TcpClient(AddressFamily.InterNetwork);
            replacement.Connect(IPAddress.Loopback, _port);
            Assert.True(SpinWait.SpinUntil(delegate
            {
                return _server.CurrentGeneration > firstGeneration && _server.HasClient;
            }, TimeSpan.FromSeconds(2)), "Server did not accept the replacement client");
            try { first.Close(); } catch { }
            _client = replacement;

            Assert.False(_server.ForceCloseCurrentClientIfGen(firstGeneration));
            Assert.True(_server.HasClient);

            byte[] bytes = Encoding.UTF8.GetBytes(BuildJsonMessage("replacement") + "\0");
            NetworkStream stream = replacement.GetStream();
            stream.Write(bytes, 0, bytes.Length);
            stream.Flush();
            Assert.True(_avail.Wait(TimeSpan.FromSeconds(5)));
            string payload;
            Assert.True(_payloads.TryDequeue(out payload));
            Assert.Equal("replacement", payload);
        }

        [Fact]
        public void Replacement_NotifiesOldGenerationOnceBeforeNewReady()
        {
            var order = new ConcurrentQueue<string>();
            int genericDisconnects = 0;
            int generationDisconnects = 0;
            _server.OnClientDisconnected += delegate
            {
                Interlocked.Increment(ref genericDisconnects);
                order.Enqueue("disconnect");
            };
            _server.OnClientDisconnectedForGeneration += delegate(int generation)
            {
                Interlocked.Increment(ref generationDisconnects);
                order.Enqueue("disconnect:" + generation);
            };
            _server.OnClientReadyForGeneration += delegate(int generation)
            {
                order.Enqueue("ready:" + generation);
            };

            TcpClient first = new TcpClient(AddressFamily.InterNetwork);
            first.Connect(IPAddress.Loopback, _port);
            Assert.True(SpinWait.SpinUntil(delegate { return _server.HasClient; },
                TimeSpan.FromSeconds(2)));
            int firstGeneration = _server.CurrentGeneration;
            Send(first, "first-ready");
            Assert.True(_avail.Wait(TimeSpan.FromSeconds(5)));
            string firstPayload;
            Assert.True(_payloads.TryDequeue(out firstPayload));
            Assert.Equal("first-ready", firstPayload);
            string ignored;
            while (order.TryDequeue(out ignored)) { }

            TcpClient replacement = new TcpClient(AddressFamily.InterNetwork);
            replacement.Connect(IPAddress.Loopback, _port);
            Assert.True(SpinWait.SpinUntil(delegate
            {
                return _server.CurrentGeneration > firstGeneration && _server.HasClient;
            }, TimeSpan.FromSeconds(2)), "Server did not install replacement client");
            int replacementGeneration = _server.CurrentGeneration;
            _client = replacement;
            Send(replacement, "replacement-ready");
            Assert.True(_avail.Wait(TimeSpan.FromSeconds(5)));
            string replacementPayload;
            Assert.True(_payloads.TryDequeue(out replacementPayload));
            Assert.Equal("replacement-ready", replacementPayload);
            Assert.True(SpinWait.SpinUntil(delegate
            {
                return order.Contains("ready:" + replacementGeneration);
            }, TimeSpan.FromSeconds(2)));

            try { first.Close(); } catch { }
            Assert.False(SpinWait.SpinUntil(delegate
            {
                return Volatile.Read(ref generationDisconnects) > 1
                    || Volatile.Read(ref genericDisconnects) > 1;
            }, TimeSpan.FromMilliseconds(250)), "old ReadLoop emitted duplicate disconnect");

            string[] events = order.ToArray();
            Assert.Equal(1, Volatile.Read(ref genericDisconnects));
            Assert.Equal(1, Volatile.Read(ref generationDisconnects));
            Assert.Equal(new[]
            {
                "disconnect",
                "disconnect:" + firstGeneration,
                "ready:" + replacementGeneration
            }, events);
            Assert.True(_server.HasClient);
            Assert.Equal(replacementGeneration, _server.CurrentGeneration);
        }

        [Fact]
        public void StaleMessageBlockedBeforeTransition_CannotClaimReadyAfterReplacement()
        {
            using var oldMessageEntered = new ManualResetEventSlim(false);
            using var releaseOldMessage = new ManualResetEventSlim(false);
            var readyGenerations = new ConcurrentQueue<int>();
            _server.OnClientReadyForGeneration += readyGenerations.Enqueue;

            TcpClient first = new TcpClient(AddressFamily.InterNetwork);
            TcpClient replacement = null;
            try
            {
                first.Connect(IPAddress.Loopback, _port);
                Assert.True(SpinWait.SpinUntil(delegate { return _server.HasClient; },
                    TimeSpan.FromSeconds(2)));
                int firstGeneration = _server.CurrentGeneration;
                int blocked = 0;
                _server.BeforeMessageTransitionForTests = delegate(int generation)
                {
                    if (generation != firstGeneration
                        || Interlocked.CompareExchange(ref blocked, 1, 0) != 0) return;
                    oldMessageEntered.Set();
                    releaseOldMessage.Wait(TimeSpan.FromSeconds(5));
                };
                Send(first, "old-blocked");
                Assert.True(oldMessageEntered.Wait(TimeSpan.FromSeconds(2)));

                replacement = new TcpClient(AddressFamily.InterNetwork);
                replacement.Connect(IPAddress.Loopback, _port);
                Assert.True(SpinWait.SpinUntil(delegate
                {
                    return _server.CurrentGeneration > firstGeneration && _server.HasClient;
                }, TimeSpan.FromSeconds(2)));
                int replacementGeneration = _server.CurrentGeneration;
                _client = replacement;
                Send(replacement, "replacement-only");

                Assert.True(_avail.Wait(TimeSpan.FromSeconds(5)));
                string payload;
                Assert.True(_payloads.TryDequeue(out payload));
                Assert.Equal("replacement-only", payload);
                Assert.True(SpinWait.SpinUntil(delegate
                {
                    return readyGenerations.Contains(replacementGeneration);
                }, TimeSpan.FromSeconds(2)));

                releaseOldMessage.Set();
                Assert.False(_avail.Wait(TimeSpan.FromMilliseconds(250)),
                    "stale old frame reached MessageRouter after replacement");
                Assert.Equal(new[] { replacementGeneration }, readyGenerations.ToArray());
            }
            finally
            {
                releaseOldMessage.Set();
                _server.BeforeMessageTransitionForTests = null;
                try { first.Close(); } catch { }
                if (replacement != null) _client = replacement;
            }
        }

        [Fact]
        public void NaturalDisconnectPublication_BlocksReplacementReadyUntilComplete()
        {
            using var disconnectEntered = new ManualResetEventSlim(false);
            using var releaseDisconnect = new ManualResetEventSlim(false);
            var readyGenerations = new ConcurrentQueue<int>();
            TcpClient first = new TcpClient(AddressFamily.InterNetwork);
            TcpClient replacement = null;
            int firstGeneration = 0;
            _server.OnClientReadyForGeneration += readyGenerations.Enqueue;
            _server.OnClientDisconnectedForGeneration += delegate(int generation)
            {
                if (generation != firstGeneration) return;
                disconnectEntered.Set();
                releaseDisconnect.Wait(TimeSpan.FromSeconds(5));
            };

            try
            {
                first.Connect(IPAddress.Loopback, _port);
                Assert.True(SpinWait.SpinUntil(delegate { return _server.HasClient; },
                    TimeSpan.FromSeconds(2)));
                firstGeneration = _server.CurrentGeneration;
                Send(first, "first-ready-before-eof");
                Assert.True(_avail.Wait(TimeSpan.FromSeconds(5)));
                string firstPayload;
                Assert.True(_payloads.TryDequeue(out firstPayload));
                Assert.Equal("first-ready-before-eof", firstPayload);

                first.Close();
                Assert.True(disconnectEntered.Wait(TimeSpan.FromSeconds(2)));
                replacement = new TcpClient(AddressFamily.InterNetwork);
                replacement.Connect(IPAddress.Loopback, _port);
                Send(replacement, "replacement-after-eof");

                Assert.False(SpinWait.SpinUntil(delegate
                {
                    return _server.CurrentGeneration > firstGeneration;
                }, TimeSpan.FromMilliseconds(250)),
                    "replacement overtook the in-flight disconnect publication");

                releaseDisconnect.Set();
                Assert.True(SpinWait.SpinUntil(delegate
                {
                    return _server.CurrentGeneration > firstGeneration && _server.HasClient;
                }, TimeSpan.FromSeconds(2)));
                int replacementGeneration = _server.CurrentGeneration;
                _client = replacement;
                Assert.True(_avail.Wait(TimeSpan.FromSeconds(5)));
                string replacementPayload;
                Assert.True(_payloads.TryDequeue(out replacementPayload));
                Assert.Equal("replacement-after-eof", replacementPayload);
                Assert.True(SpinWait.SpinUntil(delegate
                {
                    return readyGenerations.Contains(replacementGeneration);
                }, TimeSpan.FromSeconds(2)));
                Assert.Equal(new[] { firstGeneration, replacementGeneration },
                    readyGenerations.ToArray());
            }
            finally
            {
                releaseDisconnect.Set();
                try { first.Close(); } catch { }
                if (replacement != null) _client = replacement;
            }
        }

        private void ConnectAndRoundTrip(IPAddress addr, string tag)
        {
            _client = new TcpClient(addr.AddressFamily);
            _client.Connect(addr, _port);
            _client.NoDelay = true;

            Assert.True(
                SpinWait.SpinUntil(delegate() { return _server.HasClient; }, TimeSpan.FromSeconds(2)),
                "Server did not accept " + tag + " connection on " + addr);

            string msg = BuildJsonMessage(tag);
            byte[] bytes = Encoding.UTF8.GetBytes(msg + "\0");
            NetworkStream s = _client.GetStream();
            s.Write(bytes, 0, bytes.Length);
            s.Flush();

            Assert.True(_avail.Wait(TimeSpan.FromSeconds(5)), "Router did not receive " + tag + " message");
            string p;
            Assert.True(_payloads.TryDequeue(out p), "Payload queue empty after semaphore release");
            Assert.Equal(tag, p);
        }

        private static void Send(TcpClient client, string payload)
        {
            byte[] bytes = Encoding.UTF8.GetBytes(BuildJsonMessage(payload) + "\0");
            NetworkStream stream = client.GetStream();
            stream.Write(bytes, 0, bytes.Length);
            stream.Flush();
        }

        private static string BuildJsonMessage(string payload)
        {
            JObject obj = new JObject();
            obj["task"] = "dualstack_ping";
            obj["payload"] = payload;
            return obj.ToString(Newtonsoft.Json.Formatting.None);
        }

        private static bool IPv6LoopbackAvailable()
        {
            try
            {
                TcpListener probe = new TcpListener(IPAddress.IPv6Loopback, 0);
                probe.Start();
                probe.Stop();
                return true;
            }
            catch
            {
                return false;
            }
        }

        private static int ProbeFreePort()
        {
            // 选一个在 IPv4 与（若可用）IPv6 loopback 上都空闲的端口，
            // 避免选到仅 IPv4 空闲的端口让 server 静默退成 IPv4-only、令 AcceptsIPv6Loopback 假阴性。
            bool needV6 = IPv6LoopbackAvailable();
            for (int attempt = 0; attempt < 16; attempt++)
            {
                TcpListener probe = new TcpListener(IPAddress.Loopback, 0);
                probe.Start();
                int port = ((IPEndPoint)probe.LocalEndpoint).Port;
                probe.Stop();

                if (!needV6 || CanBind(IPAddress.IPv6Loopback, port))
                    return port;
            }
            throw new InvalidOperationException("Could not find a dual-stack free loopback port after 16 attempts");
        }

        private static bool CanBind(IPAddress addr, int port)
        {
            TcpListener probe = null;
            try
            {
                probe = new TcpListener(addr, port);
                probe.Start();
                return true;
            }
            catch
            {
                return false;
            }
            finally
            {
                if (probe != null) probe.Stop();
            }
        }
    }
}
