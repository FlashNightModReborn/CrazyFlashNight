// Regression tests for the UTF-8 chunk-boundary corruption bug.
//
// Before fix (XmlSocketServer.ReadLoop using per-chunk Encoding.UTF8.GetString):
//   when a multi-byte UTF-8 character (e.g. 3-byte CJK) straddles a TCP chunk
//   boundary, GetString on each chunk independently substitutes U+FFFD for the
//   incomplete byte sequence — corrupting payload silently.
//
// After fix: byte-level buffering, split on \0, decode each whole message once.
//
// These tests pin the behavior so the bug cannot regress.

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
    public class XmlSocketReadLoopTests : IDisposable
    {
        private readonly XmlSocketServer _server;
        private readonly MessageRouter _router;
        private TcpClient _client;
        // Queue + semaphore: ReadLoop 可能在测试线程读出第一条之前就连发两条；
        // 用集合而非单字段, 避免 second-overwrites-first 的竞争.
        private readonly ConcurrentQueue<string> _payloads = new ConcurrentQueue<string>();
        private readonly SemaphoreSlim _payloadAvailable = new SemaphoreSlim(0);

        public XmlSocketReadLoopTests()
        {
            _router = new MessageRouter();
            _router.RegisterSync("utf8_round_trip", delegate(JObject msg)
            {
                _payloads.Enqueue(msg.Value<string>("payload"));
                _payloadAvailable.Release();
                return "{\"ok\":true}";
            });

            _server = new XmlSocketServer(_router);
            int port = ProbeFreePort();
            bool started = _server.Start(port);
            Assert.True(started, "XmlSocketServer failed to start on probed port " + port);

            // Connect a single TCP client (XmlSocketServer is single-client).
            _client = new TcpClient();
            _client.Connect(IPAddress.Loopback, port);
            _client.NoDelay = true;
            // Wait briefly for the server to accept and ReadLoop to spin up.
            SpinWait.SpinUntil(delegate() { return _server.HasClient; }, TimeSpan.FromSeconds(2));
            Assert.True(_server.HasClient, "Server did not accept the client connection");
        }

        public void Dispose()
        {
            try { if (_client != null) _client.Close(); } catch { }
            try { _server.Dispose(); } catch { }
            try { _payloadAvailable.Dispose(); } catch { }
        }

        // ───────────── Tests ─────────────

        [Fact]
        public void SinglePacket_AsciiJson_Decoded()
        {
            // Sanity baseline — non-multibyte payload survives a clean send/recv.
            SendJsonMessage("hello");
            string got = WaitForNextPayload();
            Assert.Equal("hello", got);
            AssertNoFffd(got);
        }

        [Fact]
        public void Cjk24KB_SplitAcross8KBoundaries_NoFffd()
        {
            // Payload larger than server's 8KB read buffer → multiple TCP chunks
            // guaranteed. Use 3-byte CJK so chunk boundary mid-character would have
            // triggered U+FFFD pre-fix.
            string body = BuildCjkPayload(8000);  // 8000 chars × 3 bytes ≈ 24KB
            SendJsonMessageInChunks(body, 8192);
            string got = WaitForNextPayload();

            AssertNoFffd(got);
            Assert.Equal(body, got);
        }

        [Fact]
        public void Cjk_SplitInsideMultibyteChar_NoFffd()
        {
            // 1-byte chunk guarantees every multibyte CJK sequence is split.
            string body = "中文测试";
            SendJsonMessageInChunks(body, 1);
            string got = WaitForNextPayload();

            AssertNoFffd(got);
            Assert.Equal(body, got);
        }

        [Fact]
        public void TwoMessagesBackToBack_BothDecoded()
        {
            // Tests that the byte buffer correctly resets between messages.
            string m1 = BuildJsonMessage("第一条消息");
            string m2 = BuildJsonMessage("第二条消息");

            byte[] combined = Encoding.UTF8.GetBytes(m1 + "\0" + m2 + "\0");
            SendBytes(combined);

            string first = WaitForNextPayload();
            string second = WaitForNextPayload();

            Assert.Equal("第一条消息", first);
            Assert.Equal("第二条消息", second);
            AssertNoFffd(first);
            AssertNoFffd(second);
        }

        [Fact]
        public void MessageExactlyAtChunkBoundary_NoFffd()
        {
            // Build payload whose total bytes (incl. \0) ≈ 8192 — server reads
            // it in one chunk. Documents the fix doesn't regress the simple case.
            int targetTotal = 8192;
            string template = "{\"task\":\"utf8_round_trip\",\"payload\":\"";
            string suffix = "\"}";
            int filler = targetTotal - 1 - Encoding.UTF8.GetByteCount(template) - Encoding.UTF8.GetByteCount(suffix);
            // 3-byte CJK — round down to multiple of 3.
            filler -= filler % 3;
            int cjkCount = filler / 3;
            string body = BuildCjkPayload(cjkCount);

            byte[] bytes = Encoding.UTF8.GetBytes(template + body + suffix + "\0");
            Assert.True(bytes.Length <= targetTotal, "Payload overshoots target boundary");
            SendBytes(bytes);
            string got = WaitForNextPayload();

            AssertNoFffd(got);
            Assert.Equal(body, got);
        }

        // ───────────── Helpers ─────────────

        /// <summary>
        /// 探测一个空闲端口：用 listener bind port=0 拿 OS 分配的端口，立刻 Stop 让出。
        /// 有 TOCTOU 风险，但测试场景可接受（短窗内被抢占概率极低）。
        /// 之所以不直接传 port=0 给 XmlSocketServer.Start：它把传入 port 字面写回
        /// Port 字段，port=0 会让 Port=0，client 无从拨号。
        /// </summary>
        private static int ProbeFreePort()
        {
            TcpListener probe = new TcpListener(IPAddress.Loopback, 0);
            probe.Start();
            int port = ((IPEndPoint)probe.LocalEndpoint).Port;
            probe.Stop();
            return port;
        }

        private void SendBytes(byte[] payload)
        {
            NetworkStream s = _client.GetStream();
            s.Write(payload, 0, payload.Length);
            s.Flush();
        }

        private void SendInChunks(byte[] payload, int chunkSize)
        {
            NetworkStream s = _client.GetStream();
            int offset = 0;
            while (offset < payload.Length)
            {
                int n = Math.Min(chunkSize, payload.Length - offset);
                s.Write(payload, offset, n);
                s.Flush();
                offset += n;
                // Tiny gap to encourage the server's Read() to return per-chunk.
                Thread.Sleep(1);
            }
        }

        private void SendJsonMessage(string payload)
        {
            string msg = BuildJsonMessage(payload);
            SendBytes(Encoding.UTF8.GetBytes(msg + "\0"));
        }

        private void SendJsonMessageInChunks(string payload, int chunkSize)
        {
            string msg = BuildJsonMessage(payload);
            byte[] bytes = Encoding.UTF8.GetBytes(msg + "\0");
            SendInChunks(bytes, chunkSize);
        }

        private static string BuildJsonMessage(string payload)
        {
            JObject obj = new JObject();
            obj["task"] = "utf8_round_trip";
            obj["payload"] = payload;
            return obj.ToString(Newtonsoft.Json.Formatting.None);
        }

        private string WaitForNextPayload()
        {
            bool got = _payloadAvailable.Wait(TimeSpan.FromSeconds(5));
            Assert.True(got, "Timed out waiting for router to receive message");
            string p;
            Assert.True(_payloads.TryDequeue(out p), "Payload queue empty after semaphore release");
            return p;
        }

        // U+FFFD via Unicode escape — independent of source file encoding so the
        // test result doesn't depend on whether msbuild reads the .cs as UTF-8 or
        // ANSI. Same character either way.
        private const char FffdChar = '\uFFFD';

        private static void AssertNoFffd(string s)
        {
            Assert.NotNull(s);
            int idx = s.IndexOf(FffdChar);
            if (idx >= 0)
            {
                throw new Xunit.Sdk.XunitException(
                    "U+FFFD found at index " + idx + " (length=" + s.Length + ")");
            }
        }

        private static string BuildCjkPayload(int charCount)
        {
            // CJK alphabet via Unicode escapes — see FffdChar comment for why.
            // Original: "存档损坏修复测试中文字符跨边界编码安全"
            const string alphabet =
                "存档损坏修复测试"
                + "中文字符跨边界"
                + "编码安全";
            StringBuilder sb = new StringBuilder(charCount);
            for (int i = 0; i < charCount; i++)
                sb.Append(alphabet[i % alphabet.Length]);
            return sb.ToString();
        }
    }
}
