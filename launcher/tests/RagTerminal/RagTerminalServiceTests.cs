using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.Guardian;
using CF7Launcher.RagTerminal;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.RagTerminal
{
    /// <summary>
    /// RagTerminalService 单测：HTTP 走 stub handler（零真实网络），进程拉起走注入
    /// processStarter（零真实进程）；轮询/超时用例把 ReadyDeadlineMs/PollIntervalMs 压短，
    /// 断言点只看「请求序列 + 结构化结果」，不看墙钟。
    /// </summary>
    public class RagTerminalServiceTests : IDisposable
    {
        public RagTerminalServiceTests()
        {
            LogManager.SetSink(delegate(string line) { });
        }

        public void Dispose()
        {
            LogManager.ResetSink();
        }

        private static string NewTempInstallRoot()
        {
            string dir = Path.Combine(Path.GetTempPath(), "cfn-rag-test-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(dir);
            return dir;
        }

        private static string TouchExe(string root, string name, DateTime writtenUtc)
        {
            string path = Path.Combine(root, name);
            File.WriteAllText(path, "");
            File.SetLastWriteTimeUtc(path, writtenUtc);
            return path;
        }

        [Fact]
        public void SlotKeyValidation_MirrorsSaveSlotKeyPattern()
        {
            Assert.True(RagTerminalService.IsValidSlotKey("save1"));
            Assert.True(RagTerminalService.IsValidSlotKey("Save_Slot-9"));
            Assert.True(RagTerminalService.IsValidSlotKey(new string('a', 128)));
            Assert.False(RagTerminalService.IsValidSlotKey(null));
            Assert.False(RagTerminalService.IsValidSlotKey(""));
            Assert.False(RagTerminalService.IsValidSlotKey(new string('a', 129)));
            Assert.False(RagTerminalService.IsValidSlotKey("a/b"));
            Assert.False(RagTerminalService.IsValidSlotKey("存档一"));
            Assert.False(RagTerminalService.IsValidSlotKey("a b"));
        }

        [Fact]
        public async Task InvalidSlotRejectsWithoutHttp()
        {
            var handler = new RagHttpStub(request => RagHttpStub.Json("{}"));
            using var service = new RagTerminalService(@"C:\x\CrazyFlashNight", null, handler, path => { });

            RagTerminalPrepareResult prepared = await service.PrepareForPanelAsync("bad/slot");
            Assert.False(prepared.Success);
            Assert.Equal("rag_slot_invalid", prepared.Error);

            RagTerminalPrepareResult bound = await service.BindAsync("");
            Assert.False(bound.Success);
            Assert.Equal("rag_slot_invalid", bound.Error);

            await service.RefreshBindingBestEffortAsync("bad/slot", new JObject { ["name"] = "x" }, null);

            Assert.Empty(handler.Requests);
        }

        [Fact]
        public async Task HealthyInstanceIsReusedWithoutLaunch()
        {
            var started = new List<string>();
            var handler = new RagHttpStub(request => RagHttpStub.Json("{\"status\":\"ok\",\"mode\":\"standalone\"}"));
            using var service = new RagTerminalService(@"C:\x\CrazyFlashNight", null, handler, started.Add);

            RagTerminalPrepareResult result = await service.EnsureReadyAsync();

            Assert.True(result.Success);
            Assert.Equal("standalone", result.Mode);
            Assert.Empty(started);
            HttpRequestMessage probe = Assert.Single(handler.Requests);
            Assert.Equal("http://127.0.0.1:7077/api/health", probe.RequestUri.AbsoluteUri);
            Assert.Equal(HttpMethod.Get, probe.Method);
        }

        [Fact]
        public async Task ExeDiscoveryPicksNewestMatchAndPollsUntilReady()
        {
            string installRoot = NewTempInstallRoot();
            try
            {
                string projectRoot = Path.Combine(installRoot, "CrazyFlashNight");
                Directory.CreateDirectory(projectRoot);
                TouchExe(installRoot, "CFN-RAG-v3.0.0.exe", DateTime.UtcNow.AddHours(-2));
                string newest = TouchExe(installRoot, "CFN-RAG-v4.0.0.exe", DateTime.UtcNow.AddHours(-1));
                var started = new List<string>();
                RagHttpStub handler = null;
                handler = new RagHttpStub(request => handler.Requests.Count >= 4
                    ? RagHttpStub.Json("{\"status\":\"ok\",\"mode\":\"embedded\"}")
                    : RagHttpStub.Json("{\"status\":\"booting\"}"));
                using var service = new RagTerminalService(projectRoot, null, handler, started.Add);
                service.PollIntervalMs = 5;

                RagTerminalPrepareResult result = await service.EnsureReadyAsync();

                Assert.True(result.Success);
                Assert.Equal("embedded", result.Mode);
                Assert.Equal(new[] { newest }, started);
                Assert.Equal(4, handler.Requests.Count);
            }
            finally
            {
                Directory.Delete(installRoot, true);
            }
        }

        [Fact]
        public async Task MissingExeFailsClosedWithoutLaunch()
        {
            string installRoot = NewTempInstallRoot();
            try
            {
                string projectRoot = Path.Combine(installRoot, "CrazyFlashNight");
                Directory.CreateDirectory(projectRoot);
                var started = new List<string>();
                var handler = new RagHttpStub(request => RagHttpStub.Json("{\"status\":\"booting\"}"));
                using var service = new RagTerminalService(projectRoot, null, handler, started.Add);

                RagTerminalPrepareResult result = await service.EnsureReadyAsync();

                Assert.False(result.Success);
                Assert.Equal("rag_exe_not_found", result.Error);
                Assert.Empty(started);
                Assert.Single(handler.Requests);
            }
            finally
            {
                Directory.Delete(installRoot, true);
            }
        }

        [Fact]
        public async Task ConfiguredExeMissingFailsClosed()
        {
            string missing = Path.Combine(
                Path.GetTempPath(), "cfn-rag-missing-" + Guid.NewGuid().ToString("N") + ".exe");
            var started = new List<string>();
            var handler = new RagHttpStub(request => RagHttpStub.Json("{\"status\":\"booting\"}"));
            using var service = new RagTerminalService(@"C:\x\CrazyFlashNight", missing, handler, started.Add);

            RagTerminalPrepareResult result = await service.EnsureReadyAsync();

            Assert.False(result.Success);
            Assert.Equal("rag_exe_not_found", result.Error);
            Assert.Empty(started);
        }

        [Fact]
        public async Task ProcessStartFailureReturnsStructuredError()
        {
            string installRoot = NewTempInstallRoot();
            try
            {
                string projectRoot = Path.Combine(installRoot, "CrazyFlashNight");
                Directory.CreateDirectory(projectRoot);
                TouchExe(installRoot, "CFN-RAG-v9.0.0.exe", DateTime.UtcNow);
                var handler = new RagHttpStub(request => RagHttpStub.Json("{\"status\":\"booting\"}"));
                using var service = new RagTerminalService(projectRoot, null, handler,
                    path => throw new InvalidOperationException("boom"));

                RagTerminalPrepareResult result = await service.EnsureReadyAsync();

                Assert.False(result.Success);
                Assert.Equal("rag_start_failed", result.Error);
                Assert.False(string.IsNullOrEmpty(result.Message));
                Assert.Single(handler.Requests);
            }
            finally
            {
                Directory.Delete(installRoot, true);
            }
        }

        [Fact]
        public async Task HealthTimeoutIsBounded()
        {
            string installRoot = NewTempInstallRoot();
            try
            {
                string projectRoot = Path.Combine(installRoot, "CrazyFlashNight");
                Directory.CreateDirectory(projectRoot);
                TouchExe(installRoot, "CFN-RAG-v2.0.0.exe", DateTime.UtcNow);
                var handler = new RagHttpStub(request => RagHttpStub.Json("{\"status\":\"booting\"}"));
                using var service = new RagTerminalService(projectRoot, null, handler, path => { });
                service.ReadyDeadlineMs = 80;
                service.PollIntervalMs = 10;

                var watch = Stopwatch.StartNew();
                RagTerminalPrepareResult result = await service.EnsureReadyAsync();
                watch.Stop();

                Assert.False(result.Success);
                Assert.Equal("rag_health_timeout", result.Error);
                Assert.True(handler.Requests.Count >= 2);
                Assert.True(watch.ElapsedMilliseconds < 5000);
            }
            finally
            {
                Directory.Delete(installRoot, true);
            }
        }

        [Fact]
        public async Task BindRetriesExactlyOnceThenSucceeds()
        {
            int bindCalls = 0;
            var handler = new RagHttpStub(request =>
            {
                bindCalls++;
                return bindCalls == 1
                    ? RagHttpStub.Json("{\"ok\":false}", HttpStatusCode.InternalServerError)
                    : RagHttpStub.Json("{\"ok\":true,\"frontend_url\":\"http://127.0.0.1:7077/?embedded=1\",\"mode\":\"embedded\"}");
            });
            using var service = new RagTerminalService(@"C:\x\CrazyFlashNight", null, handler, path => { });

            RagTerminalPrepareResult result = await service.BindAsync("save1");

            Assert.True(result.Success);
            Assert.Equal("http://127.0.0.1:7077/?embedded=1", result.FrontendUrl);
            Assert.Equal("embedded", result.Mode);
            Assert.Equal(2, bindCalls);
            Assert.Equal("{\"slot_key\":\"save1\"}", handler.Bodies[0]);
            Assert.Equal("http://127.0.0.1:7077/api/integration/bind", handler.Requests[0].RequestUri.AbsoluteUri);
            Assert.Equal(HttpMethod.Post, handler.Requests[0].Method);
            Assert.False(handler.Requests[0].Headers.Contains("Origin"));
        }

        [Fact]
        public async Task BindDoubleFailureStopsAfterTwoAttempts()
        {
            int bindCalls = 0;
            var handler = new RagHttpStub(request =>
            {
                bindCalls++;
                return RagHttpStub.Json("{\"ok\":false}", HttpStatusCode.BadGateway);
            });
            using var service = new RagTerminalService(@"C:\x\CrazyFlashNight", null, handler, path => { });

            RagTerminalPrepareResult result = await service.BindAsync("save1");

            Assert.False(result.Success);
            Assert.Equal("rag_bind_failed", result.Error);
            Assert.Equal(2, bindCalls);
        }

        [Fact]
        public async Task ForeignFrontendUrlIsRejected()
        {
            var handler = new RagHttpStub(request =>
                RagHttpStub.Json("{\"ok\":true,\"frontend_url\":\"http://evil.invalid/\",\"mode\":\"embedded\"}"));
            using var service = new RagTerminalService(@"C:\x\CrazyFlashNight", null, handler, path => { });

            RagTerminalPrepareResult result = await service.BindAsync("save1");

            Assert.False(result.Success);
            Assert.Equal("rag_frontend_url_rejected", result.Error);
            Assert.Null(result.FrontendUrl);
            Assert.Single(handler.Requests);
        }

        [Fact]
        public async Task UnbindPostsExactEndpoint()
        {
            var handler = new RagHttpStub(request => RagHttpStub.Json("{\"ok\":true}"));
            using var service = new RagTerminalService(@"C:\x\CrazyFlashNight", null, handler, path => { });

            await service.UnbindAsync();

            Assert.Equal("http://127.0.0.1:7077/api/integration/unbind", handler.Requests[0].RequestUri.AbsoluteUri);
            Assert.Equal(HttpMethod.Post, handler.Requests[0].Method);
            Assert.Equal("{}", handler.Bodies[0]);

            service.UnbindInBackground();
            Assert.True(SpinWait.SpinUntil(() => handler.Requests.Count == 2, TimeSpan.FromSeconds(5)));
        }

        [Fact]
        public void ShutdownOnExitPostsExactEndpoint()
        {
            var handler = new RagHttpStub(request =>
                RagHttpStub.Json("{\"ok\":true,\"status\":\"shutting_down\"}"));
            using var service = new RagTerminalService(@"C:\x\CrazyFlashNight", null, handler, path => { });

            service.ShutdownEmbeddedOnExit();

            Assert.Equal("http://127.0.0.1:7077/api/integration/shutdown", handler.Requests[0].RequestUri.AbsoluteUri);
            Assert.Equal(HttpMethod.Post, handler.Requests[0].Method);
            Assert.Equal("{}", handler.Bodies[0]);
        }

        [Fact]
        public void ShutdownOnExitStandaloneRejectionIsSilent()
        {
            var handler = new RagHttpStub(request =>
                RagHttpStub.Json("{\"detail\":\"standalone\"}", HttpStatusCode.Conflict));
            using var service = new RagTerminalService(@"C:\x\CrazyFlashNight", null, handler, path => { });

            service.ShutdownEmbeddedOnExit();

            Assert.Single(handler.Requests);
        }

        [Fact]
        public async Task PrepareHappyPathProbesHealthThenBinds()
        {
            var handler = new RagHttpStub(request => request.RequestUri.AbsolutePath == "/api/health"
                ? RagHttpStub.Json("{\"status\":\"ok\",\"mode\":\"embedded\"}")
                : RagHttpStub.Json("{\"ok\":true,\"frontend_url\":\"http://127.0.0.1:7077/?embedded=1\",\"mode\":\"embedded\"}"));
            var started = new List<string>();
            using var service = new RagTerminalService(@"C:\x\CrazyFlashNight", null, handler, started.Add);

            RagTerminalPrepareResult result = await service.PrepareForPanelAsync("save1");

            Assert.True(result.Success);
            Assert.Equal("http://127.0.0.1:7077/?embedded=1", result.FrontendUrl);
            Assert.Equal("embedded", result.Mode);
            Assert.Empty(started);
            Assert.Equal(2, handler.Requests.Count);
            Assert.Equal("/api/health", handler.Requests[0].RequestUri.AbsolutePath);
            Assert.Equal("/api/integration/bind", handler.Requests[1].RequestUri.AbsolutePath);
        }

        [Fact]
        public async Task ProjectionSectionsRideTheBindPayload()
        {
            var handler = new RagHttpStub(request => RagHttpStub.Json(
                "{\"ok\":true,\"frontend_url\":\"http://127.0.0.1:7077/?embedded=1\",\"mode\":\"embedded\"}"));
            using var service = new RagTerminalService(@"C:\x\CrazyFlashNight", null, handler, path => { });
            var character = new JObject { ["name"] = "张三" };
            var progress = new JObject
            {
                ["tasks_finished"] = new JArray(21),
                ["task_chains_progress"] = new JObject { ["主线"] = 77 },
                ["tasks_active"] = new JArray(88)
            };
            var scene = new JObject
            {
                ["stageFlag"] = "废城",
                ["stageName"] = "",
                ["entrance"] = "正门",
                ["inCombat"] = false
            };
            var player = new JObject
            {
                ["gender"] = "男",
                ["level"] = 12
            };

            RagTerminalPrepareResult result = await service.BindAsync("save1", character, progress, scene, player);

            Assert.True(result.Success);
            Assert.Equal(
                "{\"slot_key\":\"save1\",\"character\":{\"name\":\"张三\"},"
                + "\"progress\":{\"tasks_finished\":[21],\"task_chains_progress\":{\"主线\":77},\"tasks_active\":[88]},"
                + "\"scene\":{\"stageFlag\":\"废城\",\"stageName\":\"\",\"entrance\":\"正门\",\"inCombat\":false},"
                + "\"player\":{\"gender\":\"男\",\"level\":12}}",
                handler.Bodies[0]);
        }

        [Fact]
        public async Task RefreshSkipsSilentlyWhenExeOffline()
        {
            var handler = new RagHttpStub(request => RagHttpStub.Json("{\"status\":\"booting\"}"));
            var started = new List<string>();
            using var service = new RagTerminalService(@"C:\x\CrazyFlashNight", null, handler, started.Add);

            await service.RefreshBindingBestEffortAsync(
                "save1", new JObject { ["name"] = "张三" }, null);

            Assert.Empty(started);
            HttpRequestMessage probe = Assert.Single(handler.Requests);
            Assert.Equal("/api/health", probe.RequestUri.AbsolutePath);
        }

        [Fact]
        public async Task RefreshPostsSingleBindAndToleratesFailure()
        {
            var handler = new RagHttpStub(request => request.RequestUri.AbsolutePath == "/api/health"
                ? RagHttpStub.Json("{\"status\":\"ok\",\"mode\":\"embedded\"}")
                : RagHttpStub.Json("{\"ok\":false}", HttpStatusCode.BadGateway));
            var started = new List<string>();
            using var service = new RagTerminalService(@"C:\x\CrazyFlashNight", null, handler, started.Add);

            await service.RefreshBindingBestEffortAsync(
                "save1", null, new JObject { ["tasks_finished"] = new JArray(21) });

            Assert.Empty(started);
            Assert.Equal(2, handler.Requests.Count);
            Assert.Equal("/api/health", handler.Requests[0].RequestUri.AbsolutePath);
            Assert.Equal("/api/integration/bind", handler.Requests[1].RequestUri.AbsolutePath);
            Assert.Equal("{\"slot_key\":\"save1\",\"progress\":{\"tasks_finished\":[21]}}",
                handler.Bodies[1]);
        }

        [Fact]
        public async Task TaskCompletedSkipsSilentlyWhenExeOffline()
        {
            var handler = new RagHttpStub(request => RagHttpStub.Json("{\"status\":\"booting\"}"));
            var started = new List<string>();
            using var service = new RagTerminalService(@"C:\x\CrazyFlashNight", null, handler, started.Add);

            await service.NotifyTaskCompletedAsync("save1", 213501, "Andy Law");

            Assert.Empty(started);
            HttpRequestMessage probe = Assert.Single(handler.Requests);
            Assert.Equal("/api/health", probe.RequestUri.AbsolutePath);
        }

        [Fact]
        public async Task TaskCompletedPostsSingleEventAndToleratesFailure()
        {
            var handler = new RagHttpStub(request => request.RequestUri.AbsolutePath == "/api/health"
                ? RagHttpStub.Json("{\"status\":\"ok\",\"mode\":\"embedded\"}")
                : RagHttpStub.Json("{\"ok\":false}", HttpStatusCode.BadGateway));
            var started = new List<string>();
            using var service = new RagTerminalService(@"C:\x\CrazyFlashNight", null, handler, started.Add);

            await service.NotifyTaskCompletedAsync("save1", 213501, "Andy Law");

            Assert.Empty(started);
            Assert.Equal(2, handler.Requests.Count);
            Assert.Equal("/api/health", handler.Requests[0].RequestUri.AbsolutePath);
            Assert.Equal("/api/integration/task-completed", handler.Requests[1].RequestUri.AbsolutePath);
            Assert.Equal("{\"slot_key\":\"save1\",\"task_id\":213501,\"npc\":\"Andy Law\"}",
                handler.Bodies[1]);
        }

        [Fact]
        public async Task TaskCompletedNotAcceptedStillPostsOnceWithoutRetry()
        {
            var handler = new RagHttpStub(request => request.RequestUri.AbsolutePath == "/api/health"
                ? RagHttpStub.Json("{\"status\":\"ok\",\"mode\":\"embedded\"}")
                : RagHttpStub.Json(
                    "{\"ok\":true,\"accepted\":false,\"detail\":\"任务 213501 已委派过，静默跳过\",\"job_id\":\"\"}"));
            using var service = new RagTerminalService(@"C:\x\CrazyFlashNight", null, handler, path => { });

            await service.NotifyTaskCompletedAsync("save1", 213501, null);

            Assert.Equal(2, handler.Requests.Count);
            // npc 缺省落成空串（终端以任务记录里的 get_npc 为权威），且绝不因 accepted=false 重发。
            Assert.Equal("{\"slot_key\":\"save1\",\"task_id\":213501,\"npc\":\"\"}", handler.Bodies[1]);
        }

        [Fact]
        public async Task TaskCompletedRejectsInvalidSlotOrTaskWithoutHttp()
        {
            var handler = new RagHttpStub(request => RagHttpStub.Json("{\"status\":\"ok\"}"));
            var started = new List<string>();
            using var service = new RagTerminalService(@"C:\x\CrazyFlashNight", null, handler, started.Add);

            await service.NotifyTaskCompletedAsync("bad/slot", 213501, "Andy Law");
            await service.NotifyTaskCompletedAsync("", 213501, "Andy Law");
            await service.NotifyTaskCompletedAsync("save1", 0, "Andy Law");
            await service.NotifyTaskCompletedAsync("save1", -213501, "Andy Law");

            Assert.Empty(started);
            Assert.Empty(handler.Requests);
        }

        [Fact]
        public void ResolveExePath_PrefersConfiguredOverride()
        {
            string installRoot = NewTempInstallRoot();
            try
            {
                string projectRoot = Path.Combine(installRoot, "CrazyFlashNight");
                Directory.CreateDirectory(projectRoot);
                TouchExe(installRoot, "CFN-RAG-v1.0.0.exe", DateTime.UtcNow);
                string configured = TouchExe(installRoot, "CFN-RAG-custom.exe", DateTime.UtcNow);
                using var service = new RagTerminalService(projectRoot, configured, null, path => { });

                Assert.Equal(configured, service.ResolveExePath());
            }
            finally
            {
                Directory.Delete(installRoot, true);
            }
        }

        [Fact]
        public void ResolveExePath_PicksNewestGlobMatch()
        {
            string installRoot = NewTempInstallRoot();
            try
            {
                string projectRoot = Path.Combine(installRoot, "CrazyFlashNight");
                Directory.CreateDirectory(projectRoot);
                TouchExe(installRoot, "CFN-RAG-v3.0.0.exe", DateTime.UtcNow.AddHours(-2));
                string newest = TouchExe(installRoot, "CFN-RAG-v4.0.0.exe", DateTime.UtcNow.AddHours(-1));
                using var service = new RagTerminalService(projectRoot, null, null, path => { });

                Assert.Equal(newest, service.ResolveExePath());
            }
            finally
            {
                Directory.Delete(installRoot, true);
            }
        }

        [Fact]
        public void ResolveExePath_NoMatch_ReturnsNull()
        {
            string installRoot = NewTempInstallRoot();
            try
            {
                string projectRoot = Path.Combine(installRoot, "CrazyFlashNight");
                Directory.CreateDirectory(projectRoot);
                using var service = new RagTerminalService(projectRoot, null, null, path => { });

                Assert.Null(service.ResolveExePath());
            }
            finally
            {
                Directory.Delete(installRoot, true);
            }
        }

        [Fact]
        public void ResolveExePath_ConfiguredMissing_ReturnsNull()
        {
            string installRoot = NewTempInstallRoot();
            try
            {
                string projectRoot = Path.Combine(installRoot, "CrazyFlashNight");
                Directory.CreateDirectory(projectRoot);
                // 安装根里放着可通配命中的 exe：显式路径缺失时不允许回退通配。
                TouchExe(installRoot, "CFN-RAG-v1.0.0.exe", DateTime.UtcNow);
                string missing = Path.Combine(installRoot, "cfn-rag-missing-" + Guid.NewGuid().ToString("N") + ".exe");
                using var service = new RagTerminalService(projectRoot, missing, null, path => { });

                Assert.Null(service.ResolveExePath());
            }
            finally
            {
                Directory.Delete(installRoot, true);
            }
        }
    }

    /// <summary>共享 HTTP 桩：记录请求与 body，响应由 responder 决定；零真实网络。</summary>
    internal sealed class RagHttpStub : HttpMessageHandler
    {
        private readonly Func<HttpRequestMessage, HttpResponseMessage> _responder;

        internal readonly List<HttpRequestMessage> Requests = new List<HttpRequestMessage>();
        internal readonly List<string> Bodies = new List<string>();

        internal RagHttpStub(Func<HttpRequestMessage, HttpResponseMessage> responder)
        {
            _responder = responder;
        }

        internal static HttpResponseMessage Json(string body, HttpStatusCode status = HttpStatusCode.OK)
        {
            return new HttpResponseMessage(status)
            {
                Content = new StringContent(body, Encoding.UTF8, "application/json")
            };
        }

        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Requests.Add(request);
            Bodies.Add(request.Content == null
                ? null
                : request.Content.ReadAsStringAsync().GetAwaiter().GetResult());
            return Task.FromResult(_responder(request));
        }
    }
}
