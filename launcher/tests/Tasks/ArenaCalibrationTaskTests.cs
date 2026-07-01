using System;
using System.IO;
using System.Threading;
using Newtonsoft.Json.Linq;
using Xunit;
using CF7Launcher.Tasks;

namespace CF7Launcher.Tests.Tasks
{
    public class ArenaCalibrationTaskTests
    {
        [Fact]
        public void StartBatch_Disconnected_ReturnsErrorWithoutDispatch()
        {
            string root = CreateProjectRoot();
            WriteManifest(root, "pilot-disconnected", 1);
            bool sent = false;
            var task = new ArenaCalibrationTask(root, delegate { return false; },
                delegate(string payload) { sent = true; }, delegate(int frames) { return 50; });

            JObject resp = JObject.Parse(task.HandleControl(new JObject
            {
                ["action"] = "startBatch",
                ["manifestPath"] = "tmp/arena-calibration/batches/pilot-disconnected/case_manifest.json"
            }));

            Assert.False((bool)resp["success"]);
            Assert.Equal("disconnected", (string)resp["error"]);
            Assert.False(sent);
        }

        [Fact]
        public void StartBatch_RejectsManifestPathOutsideArenaCalibrationTmp()
        {
            string root = CreateProjectRoot();
            var task = new ArenaCalibrationTask(root, delegate { return true; },
                delegate(string payload) { }, delegate(int frames) { return 50; });

            JObject resp = JObject.Parse(task.HandleControl(new JObject
            {
                ["action"] = "startBatch",
                ["manifestPath"] = "../case_manifest.json"
            }));

            Assert.False((bool)resp["success"]);
            Assert.Contains("tmp/arena-calibration", (string)resp["message"]);
        }

        [Fact]
        public void StartBatch_RejectsAbsoluteManifestPath()
        {
            string root = CreateProjectRoot();
            string absoluteManifestPath = WriteManifest(root, "pilot-absolute", 1);
            var task = new ArenaCalibrationTask(root, delegate { return true; },
                delegate(string payload) { }, delegate(int frames) { return 50; });

            JObject resp = JObject.Parse(task.HandleControl(new JObject
            {
                ["action"] = "startBatch",
                ["manifestPath"] = absoluteManifestPath
            }));

            Assert.False((bool)resp["success"]);
            Assert.Contains("project-relative", (string)resp["message"]);
        }

        [Fact]
        public void StartBatch_RejectsManifestBatchIdPathTraversalAndKeepsExistingFiles()
        {
            string root = CreateProjectRoot();
            WriteManifest(root, "traversal-carrier", 1, null, null, @"..\..\escape");
            string sentinelPath = Path.Combine(root, "escape-results.jsonl");
            File.WriteAllText(sentinelPath, "sentinel", System.Text.Encoding.UTF8);
            var task = new ArenaCalibrationTask(root, delegate { return true; },
                delegate(string payload) { }, delegate(int frames) { return 50; });

            JObject resp = JObject.Parse(task.HandleControl(new JObject
            {
                ["action"] = "startBatch",
                ["manifestPath"] = "tmp/arena-calibration/batches/traversal-carrier/case_manifest.json"
            }));

            Assert.False((bool)resp["success"]);
            Assert.Contains("batchId must match", (string)resp["message"]);
            Assert.Equal("sentinel", File.ReadAllText(sentinelPath, System.Text.Encoding.UTF8));
        }

        [Fact]
        public void StartBatch_SendsNormalizedFlashCommandAndWritesFlashResult()
        {
            string root = CreateProjectRoot();
            WriteManifest(root, "pilot-ok", 1);
            string sent = null;
            ManualResetEventSlim sentEvent = new ManualResetEventSlim(false);
            var task = new ArenaCalibrationTask(root, delegate { return true; },
                delegate(string payload)
                {
                    sent = payload;
                    sentEvent.Set();
                },
                delegate(int frames) { return 3000; });

            JObject start = JObject.Parse(task.HandleControl(new JObject
            {
                ["action"] = "startBatch",
                ["manifestPath"] = "tmp/arena-calibration/batches/pilot-ok/case_manifest.json"
            }));

            Assert.True((bool)start["success"]);
            Assert.Equal("running", (string)start["state"]);
            Assert.True(sentEvent.Wait(3000), "Flash command was not dispatched");

            JObject command = JObject.Parse(sent.TrimEnd('\0'));
            Assert.Equal("cmd", (string)command["task"]);
            Assert.Equal("arenaCalibrationRun", (string)command["action"]);
            Assert.Equal("pilot-ok", (string)command["batchId"]);
            Assert.Equal("兵种44", (string)command["blueRoster"][0]["兵种"]);
            Assert.Equal(30, (int)command["blueRoster"][0]["等级"]);
            Assert.Null(command["blueRoster"][0]["type"]);
            Assert.NotNull(command["manifestHash"]);
            Assert.NotNull(command["caseHash"]);

            task.HandleFlashResponse(new JObject
            {
                ["task"] = "arena_calibration_response",
                ["callId"] = (int)command["callId"],
                ["success"] = true,
                ["status"] = "finished",
                ["winner"] = "blue",
                ["frames"] = 123,
                ["durationMs"] = 456,
                ["blue"] = new JObject
                {
                    ["maxHp"] = 1000,
                    ["remainHp"] = 250,
                    ["aliveCount"] = 1
                },
                ["red"] = new JObject
                {
                    ["maxHp"] = 1000,
                    ["remainHp"] = 0,
                    ["aliveCount"] = 0
                },
                ["errors"] = new JArray()
            }, delegate(string json) { });

            JObject status = WaitForState(task, "completed");
            Assert.Equal(1, (int)status["completedRuns"]);

            string resultPath = Path.Combine(root, ((string)status["resultPath"]).Replace('/', Path.DirectorySeparatorChar));
            string[] lines = File.ReadAllLines(resultPath);
            Assert.Single(lines);
            JObject row = JObject.Parse(lines[0]);
            Assert.Equal("arena-calibration.result.v1", (string)row["schema"]);
            Assert.Equal("pilot-ok", (string)row["batchId"]);
            Assert.Equal((string)command["manifestHash"], (string)row["manifestHash"]);
            Assert.Equal((string)command["caseHash"], (string)row["caseHash"]);
            Assert.Equal("finished", (string)row["status"]);
            Assert.Equal("blue", (string)row["winner"]);
            Assert.Equal(123, (int)row["frames"]);
        }

        [Fact]
        public void StartBatch_AcceptsNodeGeneratedManifestHashes()
        {
            string root = CreateProjectRoot();
            WriteManifest(root, "pilot-hashed", 1,
                "sha256:dbf14286bebf800931a45161c5ab42534806b201b7b2b99ec8818bf9519534d1",
                "sha256:dd462e8e1737d6ba6b265993242504b0f284a1bd1b153ed61bc0f1d430a68683");
            ManualResetEventSlim sentEvent = new ManualResetEventSlim(false);
            var task = new ArenaCalibrationTask(root, delegate { return true; },
                delegate(string payload) { sentEvent.Set(); },
                delegate(int frames) { return 20; });

            JObject start = JObject.Parse(task.HandleControl(new JObject
            {
                ["action"] = "startBatch",
                ["manifestPath"] = "tmp/arena-calibration/batches/pilot-hashed/case_manifest.json"
            }));

            Assert.True((bool)start["success"]);
            Assert.Equal("sha256:dbf14286bebf800931a45161c5ab42534806b201b7b2b99ec8818bf9519534d1",
                (string)start["manifestHash"]);
            Assert.True(sentEvent.Wait(3000), "Flash command was not dispatched");
            WaitForState(task, "completed");
        }

        [Fact]
        public void StartBatch_TimeoutWritesTimeoutResult()
        {
            string root = CreateProjectRoot();
            WriteManifest(root, "pilot-timeout", 1);
            ManualResetEventSlim sentEvent = new ManualResetEventSlim(false);
            var task = new ArenaCalibrationTask(root, delegate { return true; },
                delegate(string payload) { sentEvent.Set(); },
                delegate(int frames) { return 20; });

            JObject start = JObject.Parse(task.HandleControl(new JObject
            {
                ["action"] = "startBatch",
                ["manifestPath"] = "tmp/arena-calibration/batches/pilot-timeout/case_manifest.json"
            }));

            Assert.True((bool)start["success"]);
            Assert.True(sentEvent.Wait(3000), "Flash command was not dispatched");

            JObject status = WaitForState(task, "completed");
            string resultPath = Path.Combine(root, ((string)status["resultPath"]).Replace('/', Path.DirectorySeparatorChar));
            JObject row = JObject.Parse(File.ReadAllLines(resultPath)[0]);
            Assert.Equal("timeout", (string)row["status"]);
            Assert.Equal("timeout", (string)row["winner"]);
        }

        private static string CreateProjectRoot()
        {
            string root = Path.Combine(Path.GetTempPath(), "cf7-arena-calibration-tests", Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(root);
            return root;
        }

        private static string WriteManifest(string root, string batchId, int repeat)
        {
            return WriteManifest(root, batchId, repeat, null, null);
        }

        private static string WriteManifest(string root, string batchId, int repeat, string manifestHash, string caseHash)
        {
            return WriteManifest(root, batchId, repeat, manifestHash, caseHash, batchId);
        }

        private static string WriteManifest(string root, string batchId, int repeat, string manifestHash, string caseHash, string manifestBatchId)
        {
            string dir = Path.Combine(root, "tmp", "arena-calibration", "batches", batchId);
            Directory.CreateDirectory(dir);
            string manifestPath = Path.Combine(dir, "case_manifest.json");
            var manifest = new JObject
            {
                ["schema"] = "arena-calibration.case-manifest.v1",
                ["batchId"] = manifestBatchId,
                ["createdAt"] = "2026-06-29T00:00:00.000Z",
                ["buildCommit"] = "test",
                ["planner"] = new JObject
                {
                    ["name"] = "test",
                    ["version"] = 1
                },
                ["arenaMode"] = "calibration",
                ["repeat"] = repeat,
                ["timeoutFrames"] = 30,
                ["blueBench"] = JValue.CreateNull(),
                ["cases"] = new JArray
                {
                    new JObject
                    {
                        ["caseId"] = "pilot-thief-lv30x4-mirror",
                        ["blueRoster"] = ThiefRoster(),
                        ["redRoster"] = ThiefRoster(),
                        ["repeat"] = repeat,
                        ["timeoutFrames"] = 30,
                        ["tags"] = new JArray("pilot", "test"),
                        ["plannerReason"] = "unit test"
                    }
                }
            };
            if (!string.IsNullOrEmpty(caseHash))
                ((JObject)((JArray)manifest["cases"])[0])["caseHash"] = caseHash;
            if (!string.IsNullOrEmpty(manifestHash))
                manifest["manifestHash"] = manifestHash;
            File.WriteAllText(manifestPath, manifest.ToString(), System.Text.Encoding.UTF8);
            return manifestPath;
        }

        private static JArray ThiefRoster()
        {
            return new JArray
            {
                new JObject { ["type"] = "兵种44", ["level"] = 30 },
                new JObject { ["type"] = "兵种45", ["level"] = 30 },
                new JObject { ["type"] = "兵种48", ["level"] = 30 },
                new JObject { ["type"] = "兵种49", ["level"] = 30 }
            };
        }

        private static JObject WaitForState(ArenaCalibrationTask task, string expectedState)
        {
            DateTime deadline = DateTime.UtcNow.AddSeconds(3);
            JObject status = null;
            while (DateTime.UtcNow < deadline)
            {
                status = JObject.Parse(task.HandleControl(new JObject { ["action"] = "status" }));
                if ((string)status["state"] == expectedState)
                    return status;
                Thread.Sleep(20);
            }
            return status;
        }
    }
}
