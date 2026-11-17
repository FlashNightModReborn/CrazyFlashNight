using System;
using System.IO;
using System.IO.Pipes;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.AgentHarness;
using CF7Launcher.Guardian;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime
{
    public sealed class AgentHarnessTests
    {
        private static string FindRepoRoot()
        {
            string dir = AppContext.BaseDirectory;
            for (int i = 0; i < 10 && !string.IsNullOrEmpty(dir); i++)
            {
                if (File.Exists(Path.Combine(dir, "crossdomain.xml")))
                    return dir;
                dir = Path.GetDirectoryName(dir);
            }
            throw new DirectoryNotFoundException("Could not locate repo root containing crossdomain.xml");
        }

        [Fact]
        public void SlotRegexAllowsOnlyDedicatedAgentSlots()
        {
            Assert.True(AgentHarnessPolicy.IsValidAgentSlot("cf7_agent_test_01"));
            Assert.True(AgentHarnessPolicy.IsValidAgentSlot("cf7_agent_A-Z_9"));
            Assert.False(AgentHarnessPolicy.IsValidAgentSlot(null));
            Assert.False(AgentHarnessPolicy.IsValidAgentSlot(""));
            Assert.False(AgentHarnessPolicy.IsValidAgentSlot("slot_1"));
            Assert.False(AgentHarnessPolicy.IsValidAgentSlot("crazyflasher7_saves"));
            Assert.False(AgentHarnessPolicy.IsValidAgentSlot("cf7_agent_../evil"));
            Assert.False(AgentHarnessPolicy.IsValidAgentSlot("bookrun_01"));
        }

        [Fact]
        public void PolicyParseValidatesModeExclusivityAndStateLifecycle()
        {
            string repoRoot = FindRepoRoot();
            string tempDir = Path.Combine(Path.GetTempPath(), "cf7_ah_policy_" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(tempDir);
            try
            {
                string cfgPath = Path.Combine(tempDir, "launch.json");
                string stateRoot = Path.Combine(tempDir, "state");
                string stateFile = Path.Combine(stateRoot, "harness-state.json");
                var cfg = new JObject
                {
                    ["schema"] = "cf7-agent-harness.v1",
                    ["projectRoot"] = repoRoot,
                    ["pipeName"] = "cf7-ah-test-" + Guid.NewGuid().ToString("N").Substring(0, 8),
                    ["sessionEpoch"] = "epoch-" + Guid.NewGuid().ToString("N"),
                    ["autoStartSlot"] = "cf7_agent_unit_slot",
                    ["stateRoot"] = stateRoot,
                    ["stateFilePath"] = stateFile,
                    ["allowHeadlessFallback"] = true,
                    ["headlessSceneFallbackDelayMs"] = 500
                };
                File.WriteAllText(cfgPath, cfg.ToString(), new UTF8Encoding(false));

                Assert.Throws<InvalidOperationException>(() => AgentHarnessPolicy.Parse(
                    new[] { "--agent-harness", cfgPath, "--bus-only" },
                    repoRoot,
                    repoRoot,
                    isolatedRuntimeCandidate: true));

                Assert.Throws<InvalidOperationException>(() => AgentHarnessPolicy.Parse(
                    new[] { "--agent-harness", cfgPath, "--arena-worker", cfgPath },
                    repoRoot,
                    repoRoot,
                    isolatedRuntimeCandidate: true));

                using (var policy = AgentHarnessPolicy.Parse(
                    new[] { "--agent-harness", cfgPath, "--project-root", repoRoot },
                    repoRoot,
                    repoRoot,
                    isolatedRuntimeCandidate: true))
                {
                    Assert.NotNull(policy);
                    Assert.Equal("cf7_agent_unit_slot", policy.AutoStartSlot);
                    Assert.Equal(500, policy.HeadlessSceneFallbackDelayMs);
                    Assert.True(policy.AllowHeadlessFallback);

                    policy.PublishStateFile(12345, 23456);
                    Assert.True(File.Exists(stateFile));
                    JObject stateDoc = JObject.Parse(File.ReadAllText(stateFile, Encoding.UTF8));
                    Assert.Equal(12345, stateDoc.Value<int>("httpPort"));
                    Assert.Equal(23456, stateDoc.Value<int>("socketPort"));
                    Assert.Equal(policy.PipeName, stateDoc.Value<string>("pipeName"));
                }

                Assert.False(File.Exists(stateFile));
            }
            finally
            {
                try { Directory.Delete(tempDir, recursive: true); } catch { }
            }
        }

        [Fact]
        public void SceneTransitionPresentationPolicyPreservesInteractiveAndUnblocksHarnessHeadless()
        {
            var reportProj = new JObject
            {
                ["version"] = 3,
                ["report"] = new JObject { ["runId"] = "r1" },
                ["reportVisible"] = true
            };
            var v1Proj = new JObject { ["version"] = 1 };

            Assert.False(SceneTransitionPresentationPolicy.Interactive.NonActivating);
            Assert.False(SceneTransitionPresentationPolicy.Interactive.AllowsHeadlessPresentation);
            Assert.False(SceneTransitionPresentationPolicy.Interactive.CanPresentCurtain(
                admitted: true, ownerVisible: true, ownerMinimized: false, connected: true,
                foregroundOwned: false, backgroundQualified: true));

            Assert.True(SceneTransitionPresentationPolicy.ArenaWorker.NonActivating);
            Assert.False(SceneTransitionPresentationPolicy.ArenaWorker.AllowsHeadlessPresentation);
            Assert.True(SceneTransitionPresentationPolicy.ArenaWorker.AllowsBackgroundCurtain(
                v1Proj, connected: true, retainedSettlement: false, bookshelfActive: false, exclusive: false));
            Assert.False(SceneTransitionPresentationPolicy.ArenaWorker.AllowsBackgroundCurtain(
                reportProj, connected: true, retainedSettlement: false, bookshelfActive: false, exclusive: false));
            Assert.False(SceneTransitionPresentationPolicy.ArenaWorker.CanPresentCurtain(
                admitted: true, ownerVisible: true, ownerMinimized: true, connected: true,
                foregroundOwned: false, backgroundQualified: true));

            Assert.True(SceneTransitionPresentationPolicy.AgentHarness.NonActivating);
            Assert.True(SceneTransitionPresentationPolicy.AgentHarness.AllowsHeadlessPresentation);
            Assert.True(SceneTransitionPresentationPolicy.AgentHarness.AllowsBackgroundCurtain(
                reportProj, connected: true, retainedSettlement: true, bookshelfActive: true, exclusive: false));
            Assert.True(SceneTransitionPresentationPolicy.AgentHarness.CanPresentCurtain(
                admitted: true, ownerVisible: true, ownerMinimized: true, connected: true,
                foregroundOwned: false, backgroundQualified: true));
            Assert.True(SceneTransitionPresentationPolicy.AgentHarness.CanPresentSurface(
                ownerVisible: true, ownerMinimized: true, foregroundOwned: false, backgroundQualified: true));
        }

        [Fact]
        public async Task EventHubWatermarksWaitersLogTapAndAs2CorrelationWork()
        {
            using var hub = new AgentHarnessEventHub();
            long seq0 = hub.CurrentEventSeq;

            var waiter = hub.WaitForAsync(
                seq0,
                AgentHarnessEventHub.BuildFilter(new JObject { ["kind"] = "archive_shadow_saved", ["slot"] = "cf7_agent_u1" }),
                3000);

            hub.HandleLogLine("[ArchiveTask] Shadow saved: cf7_agent_u1 (128 chars) path=saves/cf7_agent_u1.json");
            var res = await waiter;
            Assert.True(res.Matched);
            Assert.Equal("archive_shadow_saved", res.Event.Kind);
            Assert.True(res.LastSeq > seq0);

            JObject logs = hub.QueryLogs(0, 50, "Shadow saved", null);
            Assert.Equal(1, logs.Value<int>("count"));

            var as2Tcs = hub.RegisterAs2Waiter("req_42");
            hub.CompleteAs2Response(new JObject
            {
                ["requestId"] = "req_42",
                ["sub"] = "world_snapshot",
                ["ok"] = true,
                ["data"] = new JObject { ["frame"] = 100 }
            });
            JObject as2Resp = await as2Tcs.Task;
            Assert.True(as2Resp.Value<bool>("ok"));
            Assert.Equal(100, as2Resp["data"].Value<int>("frame"));
        }

        [Fact]
        public async Task PipeServerEnforcesSessionEpochAndRunsOnResponseWrittenAfterFlush()
        {
            string pipeName = "cf7-ah-pipe-" + Guid.NewGuid().ToString("N").Substring(0, 12);
            const string epoch = "secret_epoch_12345";
            int callbackCount = 0;

            using var server = new AgentHarnessPipeServer(
                pipeName,
                epoch,
                (method, @params, ct) =>
                {
                    if (method == "echo")
                    {
                        var result = new JObject { ["ok"] = true, ["msg"] = @params?.Value<string>("msg") ?? "" };
                        return Task.FromResult<(JObject, Action)>((result, () => Interlocked.Increment(ref callbackCount)));
                    }
                    return Task.FromResult<(JObject, Action)>((new JObject { ["ok"] = false, ["error"] = "unknown" }, null));
                });
            server.Start();

            using var client = new NamedPipeClientStream(".", pipeName, PipeDirection.InOut, PipeOptions.Asynchronous);
            await client.ConnectAsync(3000);
            using var writer = new StreamWriter(client, new UTF8Encoding(false), 1024, leaveOpen: true) { NewLine = "\n", AutoFlush = true };
            using var reader = new StreamReader(client, new UTF8Encoding(false), false, 1024, leaveOpen: true);

            // 1. Mismatched epoch rejected
            await writer.WriteLineAsync(new JObject
            {
                ["id"] = "1",
                ["sessionEpoch"] = "wrong_epoch",
                ["method"] = "echo",
                ["params"] = new JObject { ["msg"] = "hi" }
            }.ToString(Newtonsoft.Json.Formatting.None));
            JObject badResp = JObject.Parse(await reader.ReadLineAsync());
            Assert.False(badResp.Value<bool>("ok"));
            Assert.Equal("session_epoch_mismatch", badResp.Value<string>("error"));
            Assert.Equal(0, Volatile.Read(ref callbackCount));

            // 2. Valid epoch accepted and callback fires
            await writer.WriteLineAsync(new JObject
            {
                ["id"] = "2",
                ["sessionEpoch"] = epoch,
                ["method"] = "echo",
                ["params"] = new JObject { ["msg"] = "hello" }
            }.ToString(Newtonsoft.Json.Formatting.None));
            JObject goodResp = JObject.Parse(await reader.ReadLineAsync());
            Assert.True(goodResp.Value<bool>("ok"));
            Assert.Equal("hello", goodResp["result"].Value<string>("msg"));

            await Task.Delay(50);
            Assert.Equal(1, Volatile.Read(ref callbackCount));
        }
    }
}
