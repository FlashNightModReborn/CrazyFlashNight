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

            _server = new XmlSocketServer(_router);
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
