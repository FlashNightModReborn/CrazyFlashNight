using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.ArenaWorker;
using CF7Launcher.Bus;
using CF7Launcher.Config;
using CF7Launcher.Tasks;
using CF7Launcher.Guardian;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public class ArenaWorkerTests
    {
        [Fact]
        public void BootstrapBoundary_ConsumesReadyWithoutPrewarm_AndOnlyForwardsRenderAcksAndLogs()
        {
            var forwarded = new List<string>();
            Assert.True(ArenaWorkerPolicy.RouteBootstrapMessage("{\"cmd\":\"ready\"}", forwarded.Add));
            Assert.Empty(forwarded);
            foreach (string command in new[] { "start_game", "character_create_open", "character_create_submit",
                "list", "load", "load_raw", "save", "reset", "delete", "rename_slot", "import_start", "import_commit",
                "retry", "cancel_launch", "repair_apply_manual", "repair_force_continue", "config_set", "fontpack_install" })
                Assert.False(ArenaWorkerPolicy.RouteBootstrapMessage(new JObject { ["cmd"] = command }.ToString(), forwarded.Add));
            Assert.Empty(forwarded);
            foreach (string command in new[] { "reveal_ok", "ping", "log" })
                Assert.True(ArenaWorkerPolicy.RouteBootstrapMessage(new JObject { ["cmd"] = command }.ToString(), forwarded.Add));
            Assert.Equal(3, forwarded.Count);
            Assert.False(ArenaWorkerPolicy.RouteBootstrapMessage("not-json", forwarded.Add));
        }

        [Fact]
        public void PerformanceRequest_UsesExistingContractAndOnlyPrivatePreferences()
        {
            JObject config = Configuration();
            config["performance"] = new PerformancePolicy("performance", "fixed", 540).ToJson();
            var policy = ArenaWorkerPolicy.FromConfiguration(config, (string)config["projectRoot"]);
            Assert.Equal(new PerformancePolicy("performance", "fixed", 540), policy.Performance);
            string preferences = Path.Combine(policy.StateRoot, "preferences");
            var prefs = new UserPrefs(policy.ProjectRoot, preferences) { Performance = policy.Performance };
            Assert.False(File.Exists(Path.Combine(preferences, "launcher_user_prefs.json")));
            Assert.True(prefs.Save());
            Assert.Equal(540, JObject.Parse(File.ReadAllText(Path.Combine(preferences, "launcher_user_prefs.json")))
                .SelectToken("performance.maxRenderHeight").Value<int>());
            Assert.False(File.Exists(Path.Combine(policy.ProjectRoot, "launcher_user_prefs.json")));
            Assert.Equal(new PerformancePolicy("performance", "fixed", 180), Policy().Performance);
            Assert.Equal(new PerformancePolicy("balanced", "auto", 0), PerformancePolicy.Default);
            config["performance"]["maxRenderHeight"] = 541;
            Assert.Throws<InvalidOperationException>(() => ArenaWorkerPolicy.FromConfiguration(config, (string)config["projectRoot"]));
        }

        [Theory]
        [InlineData("performance", "fixed", 180, true)]
        [InlineData("performance", "fixed", 360, true)]
        [InlineData("performance", "fixed", 540, true)]
        [InlineData("balanced", "auto", 0, true)]
        [InlineData("performance", "auto", 180, false)]
        [InlineData("balanced", "fixed", 180, false)]
        [InlineData("quality", "fixed", 180, false)]
        [InlineData("performance", "fixed", 179, false)]
        public void PerformanceRequest_MinimumIsWorkerOnlyAndRequiresTheExactTuple(string preset, string mode, int height, bool allowed)
        {
            JObject config = Configuration();
            var requested = new PerformancePolicy(preset, mode, height);
            config["performance"] = requested.ToJson();
            if (allowed)
                Assert.Equal(requested, ArenaWorkerPolicy.FromConfiguration(config, (string)config["projectRoot"]).Performance);
            else
                Assert.Throws<InvalidOperationException>(() => ArenaWorkerPolicy.FromConfiguration(config, (string)config["projectRoot"]));
            if (height == 180) Assert.False(PerformancePolicy.TryParse(requested.ToJson(), out _));
        }

        [Fact]
        public void WindowObservation_UsesBoundOwnersAndActualValuesWithoutForegroundClaims()
        {
            var api = new WindowApi();
            var observer = new ArenaWorkerWindowObserver(api, 10, new IntPtr(100), () => new IntPtr(200), () => 20,
                () => new PerformanceDisplayState("balanced", "auto", "inactive", 960, 540, "HIGH", 1, "viewport_changed"));
            JObject sample = observer.Capture();
            Assert.True(sample.Value<bool>("observed"));
            Assert.True(sample.Value<bool>("guardianVisible"));
            Assert.True(sample.Value<bool>("guardianMinimized"));
            Assert.False(sample.Value<bool>("hostForeground"));
            Assert.False(sample.Value<bool>("flashForeground"));
            Assert.Equal(30, sample.Value<int>("foregroundProcessId"));
            JObject performance = observer.CapturePerformance();
            Assert.True(performance.Value<bool>("observed"));
            Assert.Equal("inactive", performance.Value<string>("status"));
            Assert.Equal(540, performance.Value<int>("height"));
            api.FlashOwner = 99;
            Assert.False(observer.Capture().Value<bool>("observed"));
        }

        [Fact]
        public void WindowObservation_RejectsHandleReplacementDuringTheSample()
        {
            var api = new WindowApi();
            int calls = 0;
            var observer = new ArenaWorkerWindowObserver(api, 10, new IntPtr(100),
                () => new IntPtr(++calls == 1 ? 200 : 201), () => 20);
            JObject sample = observer.Capture();
            Assert.False(sample.Value<bool>("observed"));
            Assert.Equal("bound_window_changed_during_sample", sample.Value<string>("reason"));
        }

        [Fact]
        public void ProcessObservation_ReportsOwnedCumulativeCounters_AndLeavesUnavailableCountersMissing()
        {
            using Process process = Process.GetCurrentProcess();
            JObject actual = ArenaWorkerPolicy.DescribeProcess(process);
            Assert.True(actual.Value<bool>("observed"));
            Assert.Equal(Environment.ProcessId, actual.Value<int>("pid"));
            Assert.True(actual.Value<double>("totalProcessorTimeMs") >= 0);
            Assert.True(actual.Value<long>("workingSetBytes") > 0);
            Assert.True(actual.Value<long>("privateMemoryBytes") > 0);
            JObject missing = ArenaWorkerPolicy.DescribeProcess(null);
            Assert.False(missing.Value<bool>("observed"));
            Assert.Null(missing["totalProcessorTimeMs"]);
            Assert.Null(missing["workingSetBytes"]);
        }

        private sealed class WindowApi : IArenaWorkerWindowObservationApi
        {
            internal int FlashOwner = 20;
            public bool IsWindow(IntPtr window) => window == new IntPtr(100) || window == new IntPtr(200);
            public bool IsVisible(IntPtr window) => true;
            public bool IsMinimized(IntPtr window) => window == new IntPtr(100);
            public int OwnerProcessId(IntPtr window) => window == new IntPtr(100) ? 10 : window == new IntPtr(200) ? FlashOwner : 30;
            public IntPtr ForegroundWindow() => new IntPtr(300);
        }

        [Theory]
        [InlineData("projectRoot")]
        [InlineData("saveRoot")]
        [InlineData("outputRoot")]
        [InlineData("swfOrigin")]
        [InlineData("stateRoot")]
        public void Configuration_RejectsCrossRootPaths(string field)
        {
            JObject config = Configuration();
            string root = (string)config["projectRoot"];
            config[field] = Path.Combine(Path.GetTempPath(), "foreign-worker", Guid.NewGuid().ToString("N"));
            Assert.Throws<InvalidOperationException>(() => ArenaWorkerPolicy.FromConfiguration(config, root));
        }

        [Fact]
        public void Invocation_RequiresVerifiedCandidate_AndDoesNotAffectNormalMode()
        {
            Assert.Null(ArenaWorkerPolicy.Parse(Array.Empty<string>(), null, false));
            Assert.Throws<InvalidOperationException>(() => ArenaWorkerPolicy.Parse(new[] { "--arena-worker", "x" }, null, false));
            JObject config = Configuration();
            config["slot"] = "crazyflasher7_saves";
            Assert.Throws<InvalidOperationException>(() => ArenaWorkerPolicy.FromConfiguration(config, (string)config["projectRoot"]));
        }

        [Fact]
        public void Controller_StartUsesOnlyFixedSafeSlot_AndRejectsOverrideAndReplay()
        {
            var policy = Policy();
            string seenSlot = null;
            bool? fresh = null, defer = null, require = null;
            int remembers = 0;
            var agent = new AgentControlTask(() => "Idle", () => false, () => false,
                (slot, f, d, r) => { seenSlot = slot; fresh = f; defer = d; require = r; },
                () => { }, () => { }, () => null, () => { }, _ => remembers++);
            var arena = new ArenaCalibrationTask(policy.ProjectRoot, () => false, _ => { }, _ => 10, policy.WorkerId, policy.SessionEpoch);
            var controller = new ArenaWorkerController(policy, agent, arena, () => null, () => { });
            foreach (string field in new[] { "slot", "fresh", "rememberSlot", "console" })
            {
                JObject forbidden = Request(policy, "start"); forbidden[field] = "unsafe";
                Assert.Equal("worker_field_forbidden", (string)controller.Handle(forbidden)["error"]);
            }
            Assert.True(controller.Handle(Request(policy, "start")).Value<bool>("success"));
            Assert.Equal(policy.Slot, seenSlot);
            Assert.False(fresh); Assert.False(defer); Assert.True(require); Assert.Equal(0, remembers);
            Assert.Equal("worker_start_already_requested", (string)controller.Handle(Request(policy, "start"))["error"]);
            JObject foreign = Request(policy, "status"); foreign["sessionEpoch"] = "foreign";
            Assert.Equal("worker_session_mismatch", (string)controller.Handle(foreign)["error"]);
        }

        [Fact]
        public void Controller_AbortRejectionStaysFailureAtTheControlBoundary()
        {
            var policy = Policy();
            var agent = new AgentControlTask(() => false, () => null, _ => { });
            var controller = new ArenaWorkerController(policy, agent, null, () => null, () => { }, request =>
                request.Value<string>("action") == "status"
                    ? new JObject { ["assignmentId"] = "assignment", ["attemptId"] = "attempt" }
                    : new JObject { ["success"] = false, ["error"] = "attempt_mismatch" });
            JObject abort = Request(policy, "abort");
            abort["assignmentId"] = "assignment"; abort["attemptId"] = "attempt";
            JObject response = controller.Handle(abort);
            Assert.False(response.Value<bool>("ok"));
            Assert.Equal("attempt_mismatch", (string)response["error"]);
        }

        [Fact]
        public void Controller_ShutdownWhileStarting_WaitsForItsWriterAndCommitsExactlyOnce()
        {
            var policy = Policy();
            var queued = new List<Action>();
            int shutdowns = 0;
            var agent = new AgentControlTask(() => false, () => null, _ => { });
            var arena = new ArenaCalibrationTask(policy.ProjectRoot, () => false, _ => { }, _ => 10, policy.WorkerId, policy.SessionEpoch);
            var controller = new ArenaWorkerController(policy, agent, arena, () => null, () => shutdowns++, queueShutdown: queued.Add);
            JObject response = controller.Handle(Request(policy, "shutdown"));
            Assert.True(response.Value<bool>("success"));
            Assert.Empty(queued);
            Assert.Equal("worker_shutting_down", (string)controller.Handle(Request(policy, "start"))["error"]);
            HttpApiServer.WriteArenaWorkerResponse(response, body => {
                Assert.True(JObject.Parse(body).Value<bool>("shutdownRequested"));
                Assert.Empty(queued);
                Assert.Equal(0, shutdowns);
            }, controller.ResponseWritten);
            Assert.Single(queued);
            controller.ResponseWritten(response);
            Assert.Single(queued);
            queued[0]();
            Assert.Equal(1, shutdowns);
        }

        [Theory]
        [InlineData(false)]
        [InlineData(true)]
        public void Controller_ShutdownWriterFailure_DoesNotCommitOrReopenAdmission(bool failedAtClose)
        {
            var policy = Policy();
            var queued = new List<Action>();
            var agent = new AgentControlTask(() => false, () => null, _ => { });
            var arena = new ArenaCalibrationTask(policy.ProjectRoot, () => false, _ => { }, _ => 10, policy.WorkerId, policy.SessionEpoch);
            var controller = new ArenaWorkerController(policy, agent, arena, () => null, () => { }, queueShutdown: queued.Add);
            JObject response = controller.Handle(Request(policy, "shutdown"));
            Assert.Throws<IOException>(() => HttpApiServer.WriteArenaWorkerResponse(response, body => {
                if (failedAtClose) Assert.True(JObject.Parse(body).Value<bool>("ok"));
                throw new IOException(failedAtClose ? "response close failed" : "response write failed");
            }, controller.ResponseWritten));
            Assert.Empty(queued);
            Assert.Equal("worker_shutting_down", (string)controller.Handle(Request(policy, "start"))["error"]);
            Assert.True(controller.Handle(Request(policy, "status")).Value<bool>("shutdownRequested"));
        }

        [Fact]
        public void Controller_ShutdownWriterReceipt_RejectsCopiedAndUnrelatedResponses()
        {
            var policy = Policy();
            var queued = new List<Action>();
            var agent = new AgentControlTask(() => false, () => null, _ => { });
            var arena = new ArenaCalibrationTask(policy.ProjectRoot, () => false, _ => { }, _ => 10, policy.WorkerId, policy.SessionEpoch);
            var controller = new ArenaWorkerController(policy, agent, arena, () => null, () => { }, queueShutdown: queued.Add);
            JObject response = controller.Handle(Request(policy, "shutdown"));
            controller.ResponseWritten((JObject)response.DeepClone());
            controller.ResponseWritten(controller.Handle(Request(policy, "status")));
            controller.ResponseWritten(controller.Handle(Request(policy, "shutdown")));
            Assert.Empty(queued);
            HttpApiServer.WriteArenaWorkerResponse(response, _ => { }, controller.ResponseWritten);
            Assert.Single(queued);
        }

        [Fact]
        public async Task WorkerHttp_ShutdownClosesItsConnectionAndOnlyThenCommitsTheOwnedReply()
        {
            var policy = Policy();
            using var access = LegacyHttpAccessPolicy.CreateWorker(policy.StateRoot, policy.WorkerId, policy.SessionEpoch);
            using var socket = new XmlSocketServer(new MessageRouter());
            Assert.True(socket.Start(0));
            using var server = new HttpApiServer(socket.Port, policy.ProjectRoot, socket, access);
            using var committed = new ManualResetEventSlim();
            int commits = 0;
            var agent = new AgentControlTask(() => false, () => null, _ => { });
            var arena = new ArenaCalibrationTask(policy.ProjectRoot, () => false, _ => { }, _ => 10, policy.WorkerId, policy.SessionEpoch);
            var controller = new ArenaWorkerController(policy, agent, arena, () => null, () => { },
                queueShutdown: _ => { Interlocked.Increment(ref commits); committed.Set(); });
            server.SetArenaWorkerControl(controller.Handle, controller.ResponseWritten);
            Assert.True(server.StartWorkerPort());
            using var client = new HttpClient { BaseAddress = new Uri("http://localhost:" + server.Port) };
            JObject credential = JObject.Parse(File.ReadAllText(access.CredentialFilePath));
            client.DefaultRequestHeaders.Add(LegacyHttpAccessPolicy.HeaderName, (string)credential["token"]);
            using var response = await client.PostAsync("/arena-worker",
                new StringContent(Request(policy, "shutdown").ToString(), Encoding.UTF8, "application/json"));
            Assert.Equal(HttpStatusCode.OK, response.StatusCode);
            Assert.True(response.Headers.ConnectionClose);
            JObject body = JObject.Parse(await response.Content.ReadAsStringAsync());
            Assert.True(body.Value<bool>("success"));
            Assert.True(body.Value<bool>("shutdownRequested"));
            Assert.Equal(policy.SessionEpoch, body.Value<string>("sessionEpoch"));
            Assert.True(committed.Wait(2000));
            Assert.Equal(1, Volatile.Read(ref commits));
        }

        [Fact]
        public void WorkerStorageAndTrust_AreScoped_AndPreserveChangedLease()
        {
            var policy = Policy();
            string roaming = Path.Combine(policy.StateRoot, "fake-roaming");
            string trustDirectory = Path.Combine(roaming, "Macromedia", "Flash Player", "#Security", "FlashPlayerTrust");
            Directory.CreateDirectory(trustDirectory);
            string normal = Path.Combine(trustDirectory, "cf7me.cfg");
            File.WriteAllText(normal, "existing-normal-trust");
            var first = FlashTrustManager.CreateWorkerLease(policy.ProjectRoot, "w01", "s01", roaming);
            var second = FlashTrustManager.CreateWorkerLease(policy.ProjectRoot, "w02", "s02", roaming);
            string firstPath = Path.Combine(trustDirectory, "cf7me-arena-w01-s01.cfg");
            string secondPath = Path.Combine(trustDirectory, "cf7me-arena-w02-s02.cfg");
            Assert.Equal(new byte[] { 0xef, 0xbb, 0xbf }, File.ReadAllBytes(firstPath)[..3]);
            Assert.Throws<IOException>(() => FlashTrustManager.CreateWorkerLease(policy.ProjectRoot, "w01", "s01", roaming));
            first.Dispose(); Assert.False(File.Exists(firstPath)); Assert.True(File.Exists(secondPath));
            File.AppendAllText(secondPath, "\nchanged"); second.Dispose();
            Assert.True(File.Exists(secondPath));
            Assert.Equal("existing-normal-trust", File.ReadAllText(normal));
            var start = new ProcessStartInfo();
            string originalAppData = start.Environment["APPDATA"];
            string temp = FlashStorageEnvironment.PrepareWorker(start, Path.Combine(policy.StateRoot, "flash-temp"));
            Assert.Equal(temp, start.Environment["TEMP"]); Assert.Equal(temp, start.Environment["TMP"]);
            Assert.Equal(originalAppData, start.Environment["APPDATA"]);
        }

        [Fact]
        public void WorkerWebViewCache_InvalidSharedTreeIsPreserved_AndPrivateTreeIsUsed()
        {
            var policy = Policy();
            string shared = Path.Combine(policy.StateRoot, "shared-engine");
            string own = Path.Combine(policy.StateRoot, "own-engine");
            string hash = new string('A', 64);
            string key = "1.2.3.4-" + hash;
            string sharedEngine = Path.Combine(shared, key, "engine");
            string ownEngine = Path.Combine(own, key, "engine");
            Directory.CreateDirectory(sharedEngine); Directory.CreateDirectory(ownEngine);
            File.WriteAllText(Path.Combine(sharedEngine, "engine.exe"), "invalid");
            byte[] expected = Encoding.UTF8.GetBytes("verified");
            File.WriteAllBytes(Path.Combine(ownEngine, "engine.exe"), expected);
            var specification = new FixedWebViewRuntime.RuntimeLock { Version = "1.2.3.4", CabSha256 = hash,
                Parts = Array.Empty<FixedWebViewRuntime.Entry>(), Files = new[] { new FixedWebViewRuntime.Entry {
                    Path = "engine.exe", Size = expected.Length,
                    Sha256 = Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(expected)) } } };
            string selected = FixedWebViewRuntime.PrepareWorkerRuntime(policy.ProjectRoot, shared, own, specification, true);
            Assert.Equal(ownEngine, selected);
            Assert.Equal("invalid", File.ReadAllText(Path.Combine(sharedEngine, "engine.exe")));
            Assert.Empty(Directory.GetDirectories(shared, "*.invalid-*"));
        }

        [Fact]
        public void AtomicDescriptor_RejectsReuseAndPreservesExistingBytes()
        {
            var policy = Policy(); Directory.CreateDirectory(policy.StateRoot);
            string file = Path.Combine(policy.StateRoot, "owner.json");
            ArenaWorkerPolicy.WriteNewAtomic(file, "first");
            Assert.Throws<IOException>(() => ArenaWorkerPolicy.WriteNewAtomic(file, "second"));
            Assert.Equal("first", File.ReadAllText(file));
            Assert.Empty(Directory.GetFiles(policy.StateRoot, "*.tmp"));
        }

        [Fact]
        public async Task WorkerHttp_RejectsLegacyRoutesAndForeignCredentials()
        {
            var policy = Policy();
            using var access = LegacyHttpAccessPolicy.CreateWorker(policy.StateRoot, policy.WorkerId, policy.SessionEpoch);
            using var socket = new XmlSocketServer(new MessageRouter());
            Assert.True(socket.Start(0)); Assert.InRange(socket.Port, 1, 65535);
            using var server = new HttpApiServer(socket.Port, policy.ProjectRoot, socket, access);
            server.SetArenaWorkerControl(_ => new JObject { ["ok"] = true });
            Assert.True(server.StartWorkerPort());
            using var client = new HttpClient { BaseAddress = new Uri("http://localhost:" + server.Port) };
            using var unauthenticated = await client.PostAsync("/arena-worker", new StringContent("{}", Encoding.UTF8, "application/json"));
            Assert.Equal(HttpStatusCode.Unauthorized, unauthenticated.StatusCode);
            JObject credential = JObject.Parse(File.ReadAllText(access.CredentialFilePath));
            client.DefaultRequestHeaders.Add(LegacyHttpAccessPolicy.HeaderName, (string)credential["token"]);
            foreach (string route in new[] { "/task", "/console", "/save-push", "/shutdown" })
            {
                using var refused = await client.PostAsync(route, new StringContent("{}", Encoding.UTF8, "application/json"));
                Assert.Equal(HttpStatusCode.Forbidden, refused.StatusCode);
            }
            using var accepted = await client.PostAsync("/arena-worker", new StringContent("{}", Encoding.UTF8, "application/json"));
            Assert.Equal(HttpStatusCode.OK, accepted.StatusCode);
        }

        [Fact]
        public void FaultOptIn_DefaultsToOffAndRejectsNonBooleanConfiguration()
        {
            Assert.False(Policy().AllowFaultInjection);
            JObject config = Configuration();
            config["allowFaultInjection"] = "true";
            Assert.Throws<InvalidOperationException>(() => ArenaWorkerPolicy.FromConfiguration(config, (string)config["projectRoot"]));
            config["allowFaultInjection"] = true;
            var policy = ArenaWorkerPolicy.FromConfiguration(config, (string)config["projectRoot"]);
            Assert.True(policy.AllowFaultInjection);
        }

        [Theory]
        [InlineData(false, null, "worker_fault_not_enabled")]
        [InlineData(true, "pid", "worker_field_forbidden")]
        [InlineData(true, "processPath", "worker_field_forbidden")]
        public void Controller_FaultGateRejectsOrdinaryWorkersAndCallerSelectedProcesses(bool enabled, string forbidden, string error)
        {
            JObject config = Configuration(); config["allowFaultInjection"] = enabled;
            var policy = ArenaWorkerPolicy.FromConfiguration(config, (string)config["projectRoot"]);
            var agent = new AgentControlTask(() => false, () => null, _ => { });
            var arena = new ArenaCalibrationTask(policy.ProjectRoot, () => false, _ => { }, _ => 10,
                policy.WorkerId, policy.SessionEpoch, false, true);
            int opens = 0;
            var controller = new ArenaWorkerController(policy, agent, arena, () => null, () => { },
                faultProcess: _ => { opens++; throw new InvalidOperationException("must not open a process"); });
            JObject request = Request(policy, "faultStopFlash");
            foreach (string key in ArenaRunIdentity.Keys)
                if (request[key] == null) request[key] = key == "repeatIndex" ? new JValue(1) : new JValue("selected");
            request["faultId"] = "fault-fixture";
            if (forbidden != null) request[forbidden] = "forbidden";
            Assert.Equal(error, controller.Handle(request).Value<string>("error"));
            Assert.Equal(0, opens);
            Assert.Equal("unsupported_action", JObject.Parse(arena.HandleControl(request)).Value<string>("error"));
        }

        private static ArenaWorkerPolicy Policy()
        {
            JObject config = Configuration();
            return ArenaWorkerPolicy.FromConfiguration(config, (string)config["projectRoot"]);
        }
        private static JObject Configuration()
        {
            string root = Path.Combine(Path.GetTempPath(), "cf7-worker-tests", Guid.NewGuid().ToString("N"), "CrazyFlashNight");
            Directory.CreateDirectory(root);
            return new JObject { ["schema"] = "arena-worker.launch.v1", ["workerId"] = "w01", ["sessionEpoch"] = "session01",
                ["projectRoot"] = root, ["stateRoot"] = Path.Combine(root, "tmp", "arena-worker", "session01"),
                ["saveRoot"] = Path.Combine(root, "saves"), ["outputRoot"] = Path.Combine(root, "tmp", "arena-calibration"),
                ["swfOrigin"] = Path.Combine(root, "CRAZYFLASHER7MercenaryEmpire.swf"), ["slot"] = "cf7_agent_worker" };
        }
        private static JObject Request(ArenaWorkerPolicy policy, string action) => new JObject {
            ["action"] = action, ["workerId"] = policy.WorkerId, ["sessionEpoch"] = policy.SessionEpoch };
    }
}
