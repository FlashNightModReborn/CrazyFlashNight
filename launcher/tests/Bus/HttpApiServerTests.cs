using System;
using System.Net;
using System.Net.Http;
using System.Net.Sockets;
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
            using (var actionObserved = new ManualResetEventSlim(false))
            using (var server = new HttpApiServer(
                0,
                AppContext.BaseDirectory,
                null))
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

                HttpResponseMessage response =
                    await client.PostAsync(
                        "http://localhost:"
                            + port
                            + "/shutdown",
                        new StringContent(""));
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
    }
}
