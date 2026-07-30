using System;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.Bus;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Bus
{
    public sealed class HttpApiServerTests
    {
        [Fact]
        public async Task Shutdown_ReturnsAcceptedRequestSemanticsBeforeRunningAction()
        {
            int port = ProbeFreePort();
            string projectRoot = CreateTempProjectRoot();
            var accessPolicy = LegacyHttpAccessPolicy.Create(projectRoot);
            string token = ReadToken(accessPolicy.CredentialFilePath);
            using (var actionObserved = new ManualResetEventSlim(false))
            using (var server = new HttpApiServer(
                0,
                projectRoot,
                null,
                accessPolicy))
            using (var handler = new HttpClientHandler { UseProxy = false })
            using (var client = new HttpClient(handler))
            {
                server.SetShutdownAction(
                    delegate
                    {
                        actionObserved.Set();
                    });
                Assert.True(
                    server.Start(port),
                    "HttpApiServer failed to start on probed port "
                        + port);

                var request = new HttpRequestMessage(
                    HttpMethod.Post,
                    "http://localhost:" + port + "/shutdown");
                request.Headers.Add(LegacyHttpAccessPolicy.HeaderName, token);
                request.Content = new StringContent("");
                HttpResponseMessage response = await client.SendAsync(request);
                string body =
                    await response.Content.ReadAsStringAsync();
                JObject json =
                    JObject.Parse(body);

                Assert.Equal(
                    HttpStatusCode.Accepted,
                    response.StatusCode);
                Assert.True(
                    json.Value<bool>("ok"));
                Assert.Equal(
                    "shutdown_requested",
                    json.Value<string>("status"));
                Assert.Equal(
                    "shutdown requested",
                    json.Value<string>("message"));
                Assert.DoesNotContain(
                    "shutting down",
                    body.ToLowerInvariant());
                Assert.True(
                    actionObserved.Wait(
                        TimeSpan.FromSeconds(2)),
                    "queued shutdown action was not invoked");
            }
        }

        [Fact]
        public async Task PrivilegedRoute_RejectsMissingCredentialWithoutDispatch()
        {
            int port = ProbeFreePort();
            string projectRoot = CreateTempProjectRoot();
            var accessPolicy = LegacyHttpAccessPolicy.DenyAll();
            using (var actionObserved = new ManualResetEventSlim(false))
            using (var server = new HttpApiServer(0, projectRoot, null, accessPolicy))
            using (var handler = new HttpClientHandler { UseProxy = false })
            using (var client = new HttpClient(handler))
            {
                server.SetShutdownAction(() => actionObserved.Set());
                Assert.True(server.Start(port));

                HttpResponseMessage response = await client.PostAsync(
                    "http://localhost:" + port + "/shutdown",
                    new StringContent(""));
                JObject json = JObject.Parse(
                    await response.Content.ReadAsStringAsync());

                Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
                Assert.Equal(
                    "legacy_http_credential_required",
                    json.Value<string>("error"));
                Assert.False(actionObserved.Wait(TimeSpan.FromMilliseconds(400)));
                Assert.False(response.Headers.Contains("Access-Control-Allow-Origin"));
            }
        }

        [Fact]
        public async Task BrowserOrigin_IsRejectedEvenWithValidCredential()
        {
            int port = ProbeFreePort();
            string projectRoot = CreateTempProjectRoot();
            var accessPolicy = LegacyHttpAccessPolicy.Create(projectRoot);
            string token = ReadToken(accessPolicy.CredentialFilePath);
            using (var actionObserved = new ManualResetEventSlim(false))
            using (var server = new HttpApiServer(0, projectRoot, null, accessPolicy))
            using (var handler = new HttpClientHandler { UseProxy = false })
            using (var client = new HttpClient(handler))
            {
                server.SetShutdownAction(() => actionObserved.Set());
                Assert.True(server.Start(port));
                var request = new HttpRequestMessage(
                    HttpMethod.Post,
                    "http://localhost:" + port + "/shutdown");
                request.Headers.Add("Origin", "https://attacker.example");
                request.Headers.Add(LegacyHttpAccessPolicy.HeaderName, token);
                request.Content = new StringContent("");

                HttpResponseMessage response = await client.SendAsync(request);
                JObject json = JObject.Parse(
                    await response.Content.ReadAsStringAsync());

                Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
                Assert.Equal(
                    "browser_origin_forbidden",
                    json.Value<string>("error"));
                Assert.False(actionObserved.Wait(TimeSpan.FromMilliseconds(400)));
                Assert.False(response.Headers.Contains("Access-Control-Allow-Origin"));
            }
        }

        [Fact]
        public async Task FlashProbe_RemainsNarrowAndDoesNotEmitCors()
        {
            int port = ProbeFreePort();
            string projectRoot = CreateTempProjectRoot();
            var accessPolicy = LegacyHttpAccessPolicy.DenyAll();
            using (var server = new HttpApiServer(0, projectRoot, null, accessPolicy))
            using (var handler = new HttpClientHandler { UseProxy = false })
            using (var client = new HttpClient(handler))
            {
                Assert.True(server.Start(port));
                HttpResponseMessage response = await client.PostAsync(
                    "http://localhost:" + port + "/testConnection",
                    new StringContent(""));

                Assert.Equal(HttpStatusCode.OK, response.StatusCode);
                Assert.Equal(
                    "status=success",
                    await response.Content.ReadAsStringAsync());
                Assert.False(response.Headers.Contains("Access-Control-Allow-Origin"));
            }
        }

        [Fact]
        public async Task LogBatch_RejectsOversizedBodyInStandardMode()
        {
            int port = ProbeFreePort();
            string projectRoot = CreateTempProjectRoot();
            using (var server = new HttpApiServer(
                0,
                projectRoot,
                null,
                LegacyHttpAccessPolicy.DenyAll()))
            using (var handler = new HttpClientHandler { UseProxy = false })
            using (var client = new HttpClient(handler))
            {
                Assert.True(server.Start(port));
                byte[] oversizedBody = new byte[(64 * 1024) + 1];

                HttpResponseMessage response = await client.PostAsync(
                    "http://localhost:" + port + "/logBatch",
                    new ChunkedContent(oversizedBody));
                JObject json = JObject.Parse(
                    await response.Content.ReadAsStringAsync());

                Assert.Equal(
                    (HttpStatusCode)413,
                    response.StatusCode);
                Assert.Equal(
                    "request_body_too_large",
                    json.Value<string>("error"));
            }
        }

        [Fact]
        public async Task StandardMode_PublicCompatibilityRoutesStayMethodBounded()
        {
            int port = ProbeFreePort();
            string projectRoot = CreateTempProjectRoot();
            using (var server = new HttpApiServer(
                24680,
                projectRoot,
                null,
                LegacyHttpAccessPolicy.DenyAll()))
            using (var handler = new HttpClientHandler { UseProxy = false })
            using (var client = new HttpClient(handler))
            {
                Assert.True(server.Start(port));

                HttpResponseMessage socketPort = await client.GetAsync(
                    "http://localhost:" + port + "/getSocketPort");
                Assert.Equal(HttpStatusCode.OK, socketPort.StatusCode);
                Assert.Equal(
                    "socketPort=24680",
                    await socketPort.Content.ReadAsStringAsync());

                HttpResponseMessage logBatch = await client.PostAsync(
                    "http://localhost:" + port + "/logBatch",
                    new StringContent("frame=1&messages=bounded"));
                Assert.Equal(HttpStatusCode.OK, logBatch.StatusCode);
                Assert.Equal(
                    "OK",
                    await logBatch.Content.ReadAsStringAsync());

                HttpResponseMessage policy = await client.GetAsync(
                    "http://localhost:" + port + "/crossdomain.xml");
                Assert.Equal(HttpStatusCode.OK, policy.StatusCode);
                Assert.Contains(
                    "<cross-domain-policy>",
                    await policy.Content.ReadAsStringAsync());

                HttpResponseMessage wrongMethod = await client.PostAsync(
                    "http://localhost:" + port + "/crossdomain.xml",
                    new StringContent(""));
                Assert.Equal(
                    HttpStatusCode.NotFound,
                    wrongMethod.StatusCode);
            }
        }

        [Fact]
        public void LogBatch_EscapesPhysicalNewlinesBeforeLogging()
        {
            Assert.Equal(
                "messages=first\\n12:00:00.000+forged",
                HttpApiServer.NormalizeLogBatchForLog(
                    "messages=first%0A12%3A00%3A00.000+forged"));
        }

        private static int ProbeFreePort()
        {
            TcpListener probe =
                new TcpListener(
                    IPAddress.Loopback,
                    0);
            probe.Start();
            try
            {
                return ((IPEndPoint)probe.LocalEndpoint)
                    .Port;
            }
            finally
            {
                probe.Stop();
            }
        }

        private static string CreateTempProjectRoot()
        {
            string root = Path.Combine(
                Path.GetTempPath(),
                "cf7-http-tests",
                Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(root);
            return root;
        }

        private static string ReadToken(string credentialFilePath)
        {
            Assert.False(string.IsNullOrWhiteSpace(credentialFilePath));
            return JObject.Parse(
                File.ReadAllText(credentialFilePath, Encoding.UTF8))
                .Value<string>("token");
        }

        private sealed class ChunkedContent : HttpContent
        {
            private readonly byte[] _body;

            internal ChunkedContent(byte[] body)
            {
                _body = body;
            }

            protected override Task SerializeToStreamAsync(
                Stream stream,
                TransportContext context)
            {
                return stream.WriteAsync(
                    _body,
                    0,
                    _body.Length);
            }

            protected override bool TryComputeLength(
                out long length)
            {
                length = 0;
                return false;
            }
        }
    }
}
