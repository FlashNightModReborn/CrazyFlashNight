using System;
using System.Collections.Generic;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using Xunit;
using CF7Launcher.Tasks;
using CF7Launcher.Bus;
using CF7Launcher.ArenaWorker;

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

            Assert.True((bool)start["success"], "Unexpected start response: " + start);
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
            Assert.Equal(650, (int)command["spawnDistance"]);
            Assert.Equal("line", (string)command["blueFormation"]);
            Assert.Equal("line", (string)command["redFormation"]);
            Assert.Equal(54, (int)command["formationSpacing"]);

            task.HandleFlashResponse(new JObject
            {
                ["task"] = "arena_calibration_response",
                ["callId"] = (int)command["callId"],
                ["workerId"] = command["workerId"].DeepClone(),
                ["sessionEpoch"] = command["sessionEpoch"].DeepClone(),
                ["assignmentId"] = command["assignmentId"].DeepClone(),
                ["attemptId"] = command["attemptId"].DeepClone(),
                ["batchId"] = command["batchId"].DeepClone(),
                ["manifestHash"] = command["manifestHash"].DeepClone(),
                ["caseId"] = command["caseId"].DeepClone(),
                ["caseHash"] = command["caseHash"].DeepClone(),
                ["runId"] = command["runId"].DeepClone(),
                ["repeatIndex"] = command["repeatIndex"].DeepClone(),
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
            Assert.Equal(650, (int)row["requestedSpawnDistance"]);
        }

        [Fact]
        public void StartBatch_SpawnDistanceIsDispatchedAndRecorded()
        {
            string root = CreateProjectRoot();
            WriteManifest(root, "pilot-distance", 1, null, null, "pilot-distance", 620);
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
                ["manifestPath"] = "tmp/arena-calibration/batches/pilot-distance/case_manifest.json"
            }));

            Assert.True((bool)start["success"]);
            Assert.True(sentEvent.Wait(3000), "Flash command was not dispatched");

            string frozenPath = Path.Combine(root, ((string)start["frozenManifestPath"]).Replace('/', Path.DirectorySeparatorChar));
            JObject frozen = JObject.Parse(File.ReadAllText(frozenPath));
            Assert.Equal(620, (int)frozen["cases"][0]["spawnDistance"]);
            Assert.Equal("line", (string)frozen["cases"][0]["blueFormation"]);
            Assert.Equal("line", (string)frozen["cases"][0]["redFormation"]);
            Assert.Equal(54, (int)frozen["cases"][0]["formationSpacing"]);

            JObject command = JObject.Parse(sent.TrimEnd('\0'));
            Assert.Equal(620, (int)command["spawnDistance"]);
            Assert.Equal("line", (string)command["blueFormation"]);
            Assert.Equal("line", (string)command["redFormation"]);
            Assert.Equal(54, (int)command["formationSpacing"]);

            task.HandleFlashResponse(new JObject
            {
                ["task"] = "arena_calibration_response",
                ["callId"] = (int)command["callId"],
                ["workerId"] = command["workerId"].DeepClone(),
                ["sessionEpoch"] = command["sessionEpoch"].DeepClone(),
                ["assignmentId"] = command["assignmentId"].DeepClone(),
                ["attemptId"] = command["attemptId"].DeepClone(),
                ["batchId"] = command["batchId"].DeepClone(),
                ["manifestHash"] = command["manifestHash"].DeepClone(),
                ["caseId"] = command["caseId"].DeepClone(),
                ["caseHash"] = command["caseHash"].DeepClone(),
                ["runId"] = command["runId"].DeepClone(),
                ["repeatIndex"] = command["repeatIndex"].DeepClone(),
                ["success"] = true,
                ["status"] = "finished",
                ["winner"] = "blue",
                ["frames"] = 123,
                ["durationMs"] = 456,
                ["spawnDistance"] = 620,
                ["blueX"] = 585,
                ["redX"] = 1205,
                ["blueSpawnPositions"] = new JArray(
                    new JObject { ["side"] = "blue", ["index"] = 0, ["unit"] = "兵种44", ["level"] = 30, ["name"] = "斗兽标定_blue_test_0", ["x"] = 585, ["y"] = 400 }),
                ["redSpawnPositions"] = new JArray(
                    new JObject { ["side"] = "red", ["index"] = 0, ["unit"] = "兵种11", ["level"] = 30, ["name"] = "斗兽标定_red_test_0", ["x"] = 1205, ["y"] = 400 }),
                ["formationAudit"] = new JObject
                {
                    ["blue"] = new JObject { ["count"] = 1, ["xRange"] = 0, ["yRange"] = 0, ["distinctX"] = 1, ["distinctY"] = 1 },
                    ["red"] = new JObject { ["count"] = 1, ["xRange"] = 0, ["yRange"] = 0, ["distinctX"] = 1, ["distinctY"] = 1 }
                },
                ["blue"] = new JObject { ["maxHp"] = 1000, ["remainHp"] = 250, ["aliveCount"] = 1 },
                ["red"] = new JObject { ["maxHp"] = 1000, ["remainHp"] = 0, ["aliveCount"] = 0 },
                ["errors"] = new JArray()
            }, delegate(string json) { });

            JObject status = WaitForState(task, "completed");
            string resultPath = Path.Combine(root, ((string)status["resultPath"]).Replace('/', Path.DirectorySeparatorChar));
            JObject row = JObject.Parse(File.ReadAllLines(resultPath)[0]);
            Assert.Equal(620, (int)row["requestedSpawnDistance"]);
            Assert.Equal(620, (int)row["spawnDistance"]);
            Assert.Equal("line", (string)row["blueFormation"]);
            Assert.Equal("line", (string)row["redFormation"]);
            Assert.Equal(54, (int)row["formationSpacing"]);
            Assert.Equal(585, (int)row["blueX"]);
            Assert.Equal(1205, (int)row["redX"]);
            Assert.Single((JArray)row["blueSpawnPositions"]);
            Assert.Single((JArray)row["redSpawnPositions"]);
            Assert.Equal(585, (int)row["blueSpawnPositions"][0]["x"]);
            Assert.Equal(1205, (int)row["redSpawnPositions"][0]["x"]);
            Assert.Equal(1, (int)row["formationAudit"]["blue"]["distinctX"]);
            Assert.Equal(1, (int)row["formationAudit"]["red"]["distinctY"]);
        }

        [Fact]
        public void StartSingle_WrapsInlineCaseAndDispatchesFlashCommand()
        {
            string root = CreateProjectRoot();
            string sent = null;
            ManualResetEventSlim sentEvent = new ManualResetEventSlim(false);
            var task = new ArenaCalibrationTask(root, delegate { return true; },
                delegate(string payload)
                {
                    sent = payload;
                    sentEvent.Set();
                },
                delegate(int frames) { return 3000; });

            JObject start = task.StartSingle(new JObject
            {
                ["batchId"] = "custom-inline",
                ["matchCode"] = "CF7ARENA:v1;mode=mvm;seed=1;blue=u44@30x1;red=u11@30x1",
                ["calibrationCase"] = new JObject
                {
                    ["caseId"] = "custom-case",
                    ["blueRoster"] = new JArray(new JObject
                    {
                        ["type"] = "兵种44",
                        ["level"] = 30,
                        ["parameters"] = new JObject { ["手枪"] = "P90战术版" }
                    }),
                    ["redRoster"] = new JArray(new JObject { ["type"] = "兵种11", ["level"] = 30 }),
                    ["repeat"] = 1,
                    ["timeoutFrames"] = 60,
                    ["spawnDistance"] = 820,
                    ["blueFormation"] = "wedge",
                    ["redFormation"] = "shield",
                    ["formationSpacing"] = 64,
                    ["tags"] = new JArray("arena-custom-p2"),
                    ["plannerReason"] = "unit test"
                }
            });

            Assert.True((bool)start["success"]);
            Assert.Equal("running", (string)start["state"]);
            Assert.Equal("custom-inline", (string)start["batchId"]);
            Assert.True(sentEvent.Wait(3000), "Flash command was not dispatched");

            JObject command = JObject.Parse(sent.TrimEnd('\0'));
            Assert.Equal("arenaCalibrationRun", (string)command["action"]);
            Assert.Equal("custom-inline", (string)command["batchId"]);
            Assert.Equal("custom-case", (string)command["caseId"]);
            Assert.Equal(820, (int)command["spawnDistance"]);
            Assert.Equal("wedge", (string)command["blueFormation"]);
            Assert.Equal("shield", (string)command["redFormation"]);
            Assert.Equal(64, (int)command["formationSpacing"]);
            Assert.Equal("兵种44", (string)command["blueRoster"][0]["兵种"]);
            Assert.Equal("P90战术版", (string)command["blueRoster"][0]["Parameters"]["手枪"]);

            string frozenPath = Path.Combine(root, ((string)start["frozenManifestPath"]).Replace('/', Path.DirectorySeparatorChar));
            Assert.True(File.Exists(frozenPath));
            JObject frozen = JObject.Parse(File.ReadAllText(frozenPath));
            Assert.Equal("arena-calibration.case-manifest.v1", (string)frozen["schema"]);
            Assert.Equal("arena-custom-match", (string)frozen["planner"]["name"]);
            Assert.Equal(820, (int)frozen["cases"][0]["spawnDistance"]);
            Assert.Equal("wedge", (string)frozen["cases"][0]["blueFormation"]);
            Assert.Equal("shield", (string)frozen["cases"][0]["redFormation"]);
            Assert.Equal(64, (int)frozen["cases"][0]["formationSpacing"]);
            Assert.Equal("P90战术版", (string)frozen["cases"][0]["blueRoster"][0]["parameters"]["手枪"]);

            task.HandleFlashResponse(new JObject
            {
                ["task"] = "arena_calibration_response",
                ["callId"] = (int)command["callId"],
                ["workerId"] = command["workerId"].DeepClone(),
                ["sessionEpoch"] = command["sessionEpoch"].DeepClone(),
                ["assignmentId"] = command["assignmentId"].DeepClone(),
                ["attemptId"] = command["attemptId"].DeepClone(),
                ["batchId"] = command["batchId"].DeepClone(),
                ["manifestHash"] = command["manifestHash"].DeepClone(),
                ["caseId"] = command["caseId"].DeepClone(),
                ["caseHash"] = command["caseHash"].DeepClone(),
                ["runId"] = command["runId"].DeepClone(),
                ["repeatIndex"] = command["repeatIndex"].DeepClone(),
                ["success"] = true,
                ["status"] = "finished",
                ["winner"] = "red",
                ["frames"] = 90,
                ["red"] = new JObject { ["maxHp"] = 100, ["remainHp"] = 20, ["aliveCount"] = 1 },
                ["blue"] = new JObject { ["maxHp"] = 100, ["remainHp"] = 0, ["aliveCount"] = 0 }
            }, delegate(string json) { });

            JObject status = WaitForState(task, "completed");
            Assert.NotNull(status["lastResult"]);
            Assert.Equal("red", (string)status["lastResult"]["winner"]);
            Assert.Contains("tmp/arena-calibration/batches/custom-inline/attempts/", (string)status["resultPath"]);
            string resultPath = Path.Combine(root, ((string)status["resultPath"]).Replace('/', Path.DirectorySeparatorChar));
            JObject row = JObject.Parse(File.ReadAllLines(resultPath)[0]);
            Assert.Equal("finished", (string)row["status"]);
            Assert.Equal("red", (string)row["winner"]);
        }

        [Fact]
        public void ArenaTask_CustomStart_DelegatesToCalibrationAndPostsPanelResponse()
        {
            string root = CreateProjectRoot();
            ManualResetEventSlim sentEvent = new ManualResetEventSlim(false);
            ManualResetEventSlim webEvent = new ManualResetEventSlim(false);
            ManualResetEventSlim openEvent = new ManualResetEventSlim(false);
            string sent = null;
            string webJson = null;
            JObject openedInitData = null;
            var calibration = new ArenaCalibrationTask(root, delegate { return true; },
                delegate(string payload)
                {
                    sent = payload;
                    sentEvent.Set();
                },
                delegate(int frames) { return 3000; });
            var arena = new ArenaTask(delegate { return true; }, delegate(string payload) { });
            arena.SetCalibrationTask(calibration);
            arena.SetCustomResultOpenHandler(delegate(JObject initData)
            {
                openedInitData = initData;
                openEvent.Set();
            });
            arena.SetPostToWeb(delegate(string json)
            {
                webJson = json;
                webEvent.Set();
            });

            arena.HandleWebRequest("custom_start", new JObject
            {
                ["callId"] = "web-custom-1",
                ["calibrationCase"] = new JObject
                {
                    ["caseId"] = "custom-case",
                    ["blueRoster"] = new JArray(new JObject { ["type"] = "兵种44", ["level"] = 30 }),
                    ["redRoster"] = new JArray(new JObject { ["type"] = "兵种11", ["level"] = 30 }),
                    ["repeat"] = 1,
                    ["timeoutFrames"] = 60,
                    ["spawnDistance"] = 760,
                    ["blueFormation"] = "grid",
                    ["redFormation"] = "column",
                    ["formationSpacing"] = 58
                }
            });

            Assert.True(webEvent.Wait(3000), "panel response was not posted");
            Assert.True(sentEvent.Wait(3000), "calibration run was not dispatched");
            JObject response = JObject.Parse(webJson);
            Assert.True((bool)response["success"]);
            Assert.Equal("panel_resp", (string)response["type"]);
            Assert.Equal("arena", (string)response["panel"]);
            Assert.Equal("custom_start", (string)response["cmd"]);
            Assert.Equal("web-custom-1", (string)response["callId"]);
            Assert.Equal("running", (string)response["state"]);
            Assert.True((bool)response["closePanel"]);

            JObject command = JObject.Parse(sent.TrimEnd('\0'));
            Assert.Equal(760, (int)command["spawnDistance"]);
            Assert.Equal("grid", (string)command["blueFormation"]);
            Assert.Equal("column", (string)command["redFormation"]);
            Assert.Equal(58, (int)command["formationSpacing"]);
            calibration.HandleFlashResponse(new JObject
            {
                ["task"] = "arena_calibration_response",
                ["callId"] = (int)command["callId"],
                ["workerId"] = command["workerId"].DeepClone(),
                ["sessionEpoch"] = command["sessionEpoch"].DeepClone(),
                ["assignmentId"] = command["assignmentId"].DeepClone(),
                ["attemptId"] = command["attemptId"].DeepClone(),
                ["batchId"] = command["batchId"].DeepClone(),
                ["manifestHash"] = command["manifestHash"].DeepClone(),
                ["caseId"] = command["caseId"].DeepClone(),
                ["caseHash"] = command["caseHash"].DeepClone(),
                ["runId"] = command["runId"].DeepClone(),
                ["repeatIndex"] = command["repeatIndex"].DeepClone(),
                ["success"] = true,
                ["status"] = "finished",
                ["winner"] = "blue",
                ["frames"] = 77,
                ["blue"] = new JObject { ["maxHp"] = 100, ["remainHp"] = 10, ["aliveCount"] = 1 },
                ["red"] = new JObject { ["maxHp"] = 100, ["remainHp"] = 0, ["aliveCount"] = 0 }
            }, delegate(string json) { });

            Assert.True(openEvent.Wait(3000), "custom result panel was not opened");
            Assert.Equal("custom_result", (string)openedInitData["mode"]);
            Assert.Equal("arena_custom_match_result", (string)openedInitData["source"]);
            Assert.Equal("completed", (string)openedInitData["state"]);
            Assert.Equal("blue", (string)openedInitData["lastResult"]["winner"]);
            Assert.Equal(77, (int)openedInitData["lastResult"]["frames"]);
        }

        [Fact]
        public void ArenaTask_CustomStart_FastBridgeLossStillOpensResultAfterStartResponse()
        {
            string root = CreateProjectRoot();
            int readyCalls = 0;
            bool sent = false;
            ManualResetEventSlim webEvent = new ManualResetEventSlim(false);
            ManualResetEventSlim openEvent = new ManualResetEventSlim(false);
            List<string> events = new List<string>();
            string webJson = null;
            JObject openedInitData = null;

            var calibration = new ArenaCalibrationTask(root,
                delegate { return Interlocked.Increment(ref readyCalls) == 1; },
                delegate(string payload) { sent = true; },
                delegate(int frames) { return 20; });
            var arena = new ArenaTask(delegate { return true; }, delegate(string payload) { });
            arena.SetCalibrationTask(calibration);
            arena.SetCustomResultOpenHandler(delegate(JObject initData)
            {
                lock (events) { events.Add("open"); }
                openedInitData = initData;
                openEvent.Set();
            });
            arena.SetPostToWeb(delegate(string json)
            {
                lock (events) { events.Add("response"); }
                webJson = json;
                webEvent.Set();
            });

            arena.HandleWebRequest("custom_start", new JObject
            {
                ["callId"] = "web-custom-fast-loss",
                ["matchCode"] = "CF7ARENA:v1;mode=mvm;seed=1;blue=u44@30x1;red=u11@30x1",
                ["calibrationCase"] = new JObject
                {
                    ["caseId"] = "custom-fast-loss",
                    ["blueRoster"] = new JArray(new JObject { ["type"] = "兵种44", ["level"] = 30 }),
                    ["redRoster"] = new JArray(new JObject { ["type"] = "兵种11", ["level"] = 30 }),
                    ["repeat"] = 1,
                    ["timeoutFrames"] = 60,
                    ["spawnDistance"] = 760,
                    ["blueFormation"] = "grid",
                    ["redFormation"] = "column",
                    ["formationSpacing"] = 58
                }
            });

            Assert.True(webEvent.Wait(3000), "custom_start panel response was not posted");
            Assert.True(openEvent.Wait(3000), "custom result panel was not opened for fast bridge loss");
            Assert.False(sent);

            JObject response = JObject.Parse(webJson);
            Assert.True((bool)response["success"]);
            Assert.True((bool)response["closePanel"]);
            Assert.Equal("failed", (string)openedInitData["state"]);
            Assert.Equal("bridge_lost", (string)openedInitData["lastResult"]["status"]);
            Assert.Equal("none", (string)openedInitData["lastResult"]["winner"]);
            Assert.Equal("CF7ARENA:v1;mode=mvm;seed=1;blue=u44@30x1;red=u11@30x1",
                (string)openedInitData["matchCode"]);

            string[] orderedEvents;
            lock (events) { orderedEvents = events.ToArray(); }
            Assert.Equal(new[] { "response", "open" }, orderedEvents);
        }

        [Fact]
        public void StartBatch_AcceptsNodeGeneratedManifestHashes()
        {
            string root = CreateProjectRoot();
            WriteManifest(root, "pilot-hashed", 1,
                "sha256:bd3dd8741578878071671d3c65688451f5e22ae40330646abd312b0fa8213ce0",
                "sha256:bddcf9a1bde3e3142721364c5205bffae41eb965bd746c3ec015d65f91cb644c");
            ManualResetEventSlim sentEvent = new ManualResetEventSlim(false);
            var task = new ArenaCalibrationTask(root, delegate { return true; },
                delegate(string payload) { sentEvent.Set(); },
                delegate(int frames) { return 20; });

            JObject start = JObject.Parse(task.HandleControl(new JObject
            {
                ["action"] = "startBatch",
                ["manifestPath"] = "tmp/arena-calibration/batches/pilot-hashed/case_manifest.json"
            }));

            Assert.True((bool)start["success"], "Unexpected start response: " + start);
            Assert.Equal("sha256:bd3dd8741578878071671d3c65688451f5e22ae40330646abd312b0fa8213ce0",
                (string)start["manifestHash"]);
            Assert.True(sentEvent.Wait(3000), "Flash command was not dispatched");
            WaitForState(task, "failed");
        }

        [Fact]
        public void StartBatch_TransportDeadlineWritesBridgeLostResult()
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

            JObject status = WaitForState(task, "failed");
            string resultPath = Path.Combine(root, ((string)status["resultPath"]).Replace('/', Path.DirectorySeparatorChar));
            JObject row = JObject.Parse(File.ReadAllLines(resultPath)[0]);
            Assert.Equal("bridge_lost", (string)row["status"]);
            Assert.Equal("none", (string)row["winner"]);
            Assert.Equal("bridge_lost", (string)row["errors"][0]["code"]);
            Assert.Contains("Host transport deadline", (string)row["errors"][0]["message"]);
        }

        [Theory]
        [InlineData(1, 30068)]
        [InlineData(1800, 150000)]
        [InlineData(5400, 390000)]
        [InlineData(int.MaxValue, 600000)]
        public void DefaultTransportTimeout_SeparatesBattleFramesFromHostDeadline(int frames, int expectedMs)
        {
            Assert.Equal(expectedMs, ArenaCalibrationTask.DefaultTransportTimeoutMsFromFrames(frames));
        }

        [Fact]
        public void AbortBatch_DispatchesFlashCleanupCommandAndWritesAbortedResult()
        {
            string root = CreateProjectRoot();
            WriteManifest(root, "pilot-abort", 1);
            List<string> sent = new List<string>();
            ManualResetEventSlim firstSent = new ManualResetEventSlim(false);
            ManualResetEventSlim secondSent = new ManualResetEventSlim(false);
            var task = new ArenaCalibrationTask(root, delegate { return true; },
                delegate(string payload)
                {
                    lock (sent)
                    {
                        sent.Add(payload);
                        if (sent.Count == 1) firstSent.Set();
                        if (sent.Count == 2) secondSent.Set();
                    }
                },
                delegate(int frames) { return 3000; });

            JObject start = JObject.Parse(task.HandleControl(new JObject
            {
                ["action"] = "startBatch",
                ["manifestPath"] = "tmp/arena-calibration/batches/pilot-abort/case_manifest.json"
            }));

            Assert.True((bool)start["success"]);
            Assert.True(firstSent.Wait(3000), "Flash run command was not dispatched");

            JObject abort = JObject.Parse(task.HandleControl(new JObject
            {
                ["action"] = "abort",
                ["batchId"] = "pilot-abort"
            }));

            Assert.True((bool)abort["success"]);
            Assert.Equal("abort_requested", (string)abort["note"]);
            Assert.True(secondSent.Wait(3000), "Flash abort cleanup command was not dispatched");

            JObject abortCommand;
            lock (sent)
            {
                abortCommand = JObject.Parse(sent[1].TrimEnd('\0'));
            }
            Assert.Equal("cmd", (string)abortCommand["task"]);
            Assert.Equal("arenaCalibrationAbort", (string)abortCommand["action"]);
            Assert.Equal("pilot-abort", (string)abortCommand["batchId"]);

            JObject status = WaitForState(task, "aborted");
            Assert.Equal(1, (int)status["completedRuns"]);

            string resultPath = Path.Combine(root, ((string)status["resultPath"]).Replace('/', Path.DirectorySeparatorChar));
            JObject row = JObject.Parse(File.ReadAllLines(resultPath)[0]);
            Assert.Equal("aborted", (string)row["status"]);
            Assert.Equal("none", (string)row["winner"]);
        }


        [Theory]
        [InlineData("workerId")]
        [InlineData("sessionEpoch")]
        [InlineData("assignmentId")]
        [InlineData("attemptId")]
        [InlineData("batchId")]
        [InlineData("manifestHash")]
        [InlineData("caseId")]
        [InlineData("caseHash")]
        [InlineData("runId")]
        [InlineData("repeatIndex")]
        public void ForeignEcho_DoesNotConsumePending_ThenExactResponseCompletes(string field)
        {
            string root = CreateProjectRoot();
            WriteManifest(root, "exact-echo", 1);
            JObject command = null;
            using var sent = new ManualResetEventSlim();
            var task = new ArenaCalibrationTask(root, () => true,
                payload => { command = JObject.Parse(payload.TrimEnd('\0')); sent.Set(); }, _ => 3000);
            task.HandleControl(new JObject { ["action"] = "startBatch",
                ["manifestPath"] = "tmp/arena-calibration/batches/exact-echo/case_manifest.json" });
            Assert.True(sent.Wait(2000));
            JObject foreign = ExactResponse(command);
            foreign[field] = field == "repeatIndex" ? new JValue(999) : new JValue("foreign");
            task.HandleFlashResponse(foreign, _ => { });
            JObject pending = JObject.Parse(task.HandleControl(new JObject { ["action"] = "status" }));
            Assert.Equal("running", (string)pending["state"]);
            Assert.Equal(0, (int)pending["completedRuns"]);
            Assert.Equal(JTokenType.Null, pending["lastResult"].Type);
            task.HandleFlashResponse(ExactResponse(command), _ => { });
            JObject terminal = WaitForState(task, "completed");
            Assert.Equal((string)command["attemptId"], (string)terminal["lastResult"]["attemptId"]);
            Assert.Equal(1, (int)terminal["completedRuns"]);
        }

        [Fact]
        public void RepeatedBatch_UsesImmutableAttemptOutputs_AndRejectsAttemptReuse()
        {
            string root = CreateProjectRoot();
            WriteManifest(root, "attempt-files", 1);
            ArenaCalibrationTask task = null;
            task = new ArenaCalibrationTask(root, () => true, payload => {
                JObject command = JObject.Parse(payload.TrimEnd('\0'));
                task.HandleFlashResponse(ExactResponse(command), _ => { });
            }, _ => 3000);
            JObject request = new JObject { ["action"] = "startBatch", ["attemptId"] = "attempt-1",
                ["manifestPath"] = "tmp/arena-calibration/batches/attempt-files/case_manifest.json" };
            Assert.True(JObject.Parse(task.HandleControl(request)).Value<bool>("success"));
            JObject first = WaitForState(task, "completed");
            string firstPath = Path.Combine(root, (string)first["resultPath"]);
            byte[] original = File.ReadAllBytes(firstPath);
            request["attemptId"] = "attempt-2";
            Assert.True(JObject.Parse(task.HandleControl(request)).Value<bool>("success"));
            JObject second = WaitForState(task, "completed");
            Assert.NotEqual((string)first["resultPath"], (string)second["resultPath"]);
            request["attemptId"] = "attempt-1";
            Assert.False(JObject.Parse(task.HandleControl(request)).Value<bool>("success"));
            Assert.Equal(original, File.ReadAllBytes(firstPath));
        }

        [Fact]
        public void TransportLoss_StopsRemainingCases_AndPoisonsNextAdmission()
        {
            string root = CreateProjectRoot();
            WriteManifest(root, "transport-stop", 3);
            int sent = 0;
            var task = new ArenaCalibrationTask(root, () => true, _ => Interlocked.Increment(ref sent), _ => 20);
            JObject request = new JObject { ["action"] = "startBatch",
                ["manifestPath"] = "tmp/arena-calibration/batches/transport-stop/case_manifest.json" };
            task.HandleControl(request);
            JObject terminal = WaitForState(task, "failed");
            Assert.True(terminal.Value<bool>("transportPoisoned"));
            Assert.Equal(1, sent);
            Assert.Equal(1, terminal.Value<int>("completedRuns"));
            Assert.Equal("bridge_lost", (string)terminal["lastResult"]["status"]);
            Assert.Equal("transport_poisoned", JObject.Parse(task.HandleControl(request)).Value<string>("error"));
        }

        [Fact]
        public void NaturalCombatTimeout_IsAnEchoedResult_AndDoesNotPoisonTransport()
        {
            string root = CreateProjectRoot();
            WriteManifest(root, "combat-timeout", 1);
            ArenaCalibrationTask task = null;
            task = new ArenaCalibrationTask(root, () => true, payload => {
                JObject command = JObject.Parse(payload.TrimEnd('\0'));
                JObject response = ExactResponse(command);
                response["status"] = "timeout"; response["winner"] = "timeout";
                task.HandleFlashResponse(response, _ => { });
            }, _ => 3000);
            task.HandleControl(new JObject { ["action"] = "startBatch",
                ["manifestPath"] = "tmp/arena-calibration/batches/combat-timeout/case_manifest.json" });
            JObject terminal = WaitForState(task, "completed");
            Assert.False(terminal.Value<bool>("transportPoisoned"));
            Assert.Equal("timeout", (string)terminal["lastResult"]["status"]);
        }

        private static JObject ExactResponse(JObject command)
        {
            var response = new JObject { ["task"] = "arena_calibration_response", ["callId"] = command["callId"].DeepClone(),
                ["success"] = true, ["status"] = "finished", ["winner"] = "blue", ["frames"] = 1, ["errors"] = new JArray() };
            foreach (string field in new[] { "workerId", "sessionEpoch", "assignmentId", "attemptId",
                "batchId", "manifestHash", "caseId", "caseHash", "runId", "repeatIndex" })
                response[field] = command[field].DeepClone();
            return response;
        }

        [Theory]
        [InlineData(true)]
        [InlineData(false)]
        public void TransportPoison_RebindRequiresNewOwnedFlash_AndIsNeverAllowedForWorker(bool allowRebind)
        {
            string root = CreateProjectRoot();
            WriteManifest(root, "owned-rebind", 1);
            bool echo = false;
            ArenaCalibrationTask task = null;
            task = new ArenaCalibrationTask(root, () => true, payload => {
                if (echo) task.HandleFlashResponse(ExactResponse(JObject.Parse(payload.TrimEnd('\0'))), _ => { });
            }, _ => 25, "guardian", "original-epoch", allowRebind);
            var original = new XmlSocketPeerProcessIdentity(123, DateTimeOffset.UtcNow, Path.Combine(root, "Flash.exe"));
            task.ObserveOwnedFlashIdentity(original);
            JObject request = new JObject { ["action"] = "startBatch",
                ["manifestPath"] = "tmp/arena-calibration/batches/owned-rebind/case_manifest.json" };
            task.HandleControl(request);
            JObject lost = WaitForState(task, "failed");
            string firstPath = Path.Combine(root, (string)lost["resultPath"]);
            byte[] originalBytes = File.ReadAllBytes(firstPath);
            // A fresh socket or another Process object is still the same live process identity.
            task.ObserveOwnedFlashIdentity(new XmlSocketPeerProcessIdentity(original.ProcessId,
                original.StartTimeUtc, original.ExecutablePath.ToUpperInvariant()));
            Assert.Equal("transport_poisoned", JObject.Parse(task.HandleControl(request)).Value<string>("error"));
            // PID reuse is distinct only when the trusted lifecycle supplies a new start time.
            task.ObserveOwnedFlashIdentity(new XmlSocketPeerProcessIdentity(original.ProcessId,
                original.StartTimeUtc.AddSeconds(1), original.ExecutablePath));
            echo = true;
            JObject admission = JObject.Parse(task.HandleControl(request));
            if (allowRebind)
            {
                Assert.True(admission.Value<bool>("success"));
                JObject completed = WaitForState(task, "completed");
                Assert.NotEqual((string)lost["sessionEpoch"], (string)completed["sessionEpoch"]);
                Assert.False(completed.Value<bool>("transportPoisoned"));
                Assert.NotEqual((string)lost["resultPath"], (string)completed["resultPath"]);
            }
            else Assert.Equal("transport_poisoned", (string)admission["error"]);
            Assert.Equal(originalBytes, File.ReadAllBytes(firstPath));
        }

        [Fact]
        public void TransportPoison_WithoutOriginalOwnedIdentity_CannotBeRebound()
        {
            string root = CreateProjectRoot(); WriteManifest(root, "unproven-rebind", 1);
            var task = new ArenaCalibrationTask(root, () => true, _ => { }, _ => 20);
            JObject request = new JObject { ["action"] = "startBatch",
                ["manifestPath"] = "tmp/arena-calibration/batches/unproven-rebind/case_manifest.json" };
            task.HandleControl(request); WaitForState(task, "failed");
            task.ObserveOwnedFlashIdentity(new XmlSocketPeerProcessIdentity(234,
                DateTimeOffset.UtcNow, Path.Combine(root, "Flash.exe")));
            Assert.Equal("transport_poisoned", JObject.Parse(task.HandleControl(request)).Value<string>("error"));
        }

        [Theory]
        [InlineData("workerId")]
        [InlineData("sessionEpoch")]
        [InlineData("assignmentId")]
        [InlineData("attemptId")]
        [InlineData("batchId")]
        [InlineData("manifestHash")]
        [InlineData("caseId")]
        [InlineData("caseHash")]
        [InlineData("runId")]
        [InlineData("repeatIndex")]
        public void FaultStopFlash_ForeignTupleNeverConsumesTheTicketOrKills(string field)
        {
            using var fixture = new FaultFixture();
            JObject request = fixture.Request();
            request[field] = field == "repeatIndex" ? new JValue(999) : new JValue("foreign");
            JObject rejected = fixture.Arena.FaultStopFlash(request, fixture.Process);
            Assert.Equal("fault_context_mismatch", rejected.Value<string>("error"));
            Assert.Equal(0, fixture.Process.KillCalls);
            Assert.Equal(JTokenType.Null, fixture.Status()["faultReceipt"].Type);
            Assert.True(fixture.Arena.FaultStopFlash(fixture.Request(), fixture.Process).Value<bool>("success"));
            Assert.Equal(1, fixture.Process.KillCalls);
        }

        [Theory]
        [InlineData("pid")]
        [InlineData("start")]
        [InlineData("path")]
        [InlineData("observed")]
        [InlineData("generation")]
        [InlineData("exited")]
        [InlineData("opt-in")]
        public void FaultStopFlash_RequiresOptInAndTheExactLiveOwnedProcess(string mismatch)
        {
            using var fixture = new FaultFixture(allowFaultInjection: mismatch != "opt-in");
            var original = fixture.Process.Identity;
            if (mismatch == "pid") fixture.Process.Identity = new XmlSocketPeerProcessIdentity(original.ProcessId + 1, original.StartTimeUtc, original.ExecutablePath);
            if (mismatch == "start") fixture.Process.Identity = new XmlSocketPeerProcessIdentity(original.ProcessId, original.StartTimeUtc.AddTicks(1), original.ExecutablePath);
            if (mismatch == "path") fixture.Process.Identity = new XmlSocketPeerProcessIdentity(original.ProcessId, original.StartTimeUtc, original.ExecutablePath + ".other");
            if (mismatch == "observed") fixture.Arena.ObserveOwnedFlashIdentity(new XmlSocketPeerProcessIdentity(original.ProcessId + 1, original.StartTimeUtc, original.ExecutablePath));
            if (mismatch == "generation") fixture.Ready = false;
            if (mismatch == "exited") fixture.Process.IsAlive = false;
            JObject rejected = fixture.Arena.FaultStopFlash(fixture.Request(), fixture.Process);
            string error = mismatch == "generation" ? "fault_generation_mismatch"
                : mismatch == "exited" ? "fault_process_exited"
                : mismatch == "opt-in" ? "worker_fault_not_enabled" : "fault_process_mismatch";
            Assert.Equal(error, rejected.Value<string>("error"));
            Assert.Equal(0, fixture.Process.KillCalls);
            Assert.Equal(0, fixture.Process.WaitCalls);
            Assert.Equal(0, fixture.Status().Value<int>("completedRuns"));
            Assert.True(fixture.Status()["faultReceipt"] == null || fixture.Status()["faultReceipt"].Type == JTokenType.Null);
        }

        [Fact]
        public void FaultStopFlash_ResponseCompletedFirstRejectsTheOldRunWithoutRetargeting()
        {
            using var fixture = new FaultFixture(repeat: 2);
            JObject original = fixture.Request();
            fixture.Arena.HandleFlashResponse(ExactResponse(fixture.Command), _ => { });
            Assert.True(SpinWait.SpinUntil(() => fixture.CommandCount == 2, 2000));
            Assert.NotEqual(original.Value<string>("runId"), fixture.Command.Value<string>("runId"));
            JObject rejected = fixture.Arena.FaultStopFlash(original, fixture.Process);
            Assert.Equal("fault_context_mismatch", rejected.Value<string>("error"));
            Assert.Equal(0, fixture.Process.KillCalls);
            Assert.Equal(JTokenType.Null, fixture.Status()["faultReceipt"].Type);
        }

        [Fact]
        public async Task FaultStopFlash_ClaimAndKillBlockCompletionButExitObservationDoesNotHoldTheTaskLock()
        {
            using var fixture = new FaultFixture(repeat: 2);
            using var killEntered = new ManualResetEventSlim();
            using var allowKillReturn = new ManualResetEventSlim();
            using var observationEntered = new ManualResetEventSlim();
            using var allowObservation = new ManualResetEventSlim();
            using var responseAttempted = new ManualResetEventSlim();
            using var responseDone = new ManualResetEventSlim();
            JObject selected = fixture.Request();
            JObject selectedCommand = fixture.Command;
            fixture.Process.OnKill = () => { killEntered.Set(); Assert.True(allowKillReturn.Wait(2000)); };
            fixture.Process.ObserveExit = () => { observationEntered.Set(); Assert.True(allowObservation.Wait(2000)); return true; };
            Task<JObject> fault = Task.Run(() => fixture.Arena.FaultStopFlash(selected, fixture.Process));
            Task response = null;
            try
            {
                Assert.True(killEntered.Wait(2000));
                response = Task.Run(() => {
                    responseAttempted.Set();
                    fixture.Arena.HandleFlashResponse(ExactResponse(selectedCommand), _ => { });
                    responseDone.Set();
                });
                Assert.True(responseAttempted.Wait(2000));
                Assert.False(responseDone.Wait(50));
                Assert.Equal(1, fixture.CommandCount);
                allowKillReturn.Set();
                Assert.True(observationEntered.Wait(2000));
                Assert.True(responseDone.Wait(2000));
                Assert.True(SpinWait.SpinUntil(() => fixture.CommandCount == 2, 2000));
                // A fake process lets the test response through after Kill returns. The
                // ticket must still name the originally selected run, never the next one.
                JObject observing = fixture.Status();
                Assert.Equal("kill_issued", (string)observing["faultReceipt"]["outcome"]);
                Assert.Equal((string)selected["runId"], (string)observing["faultReceipt"]["runId"]);
                Assert.Equal(1, fixture.Process.KillCalls);
            }
            finally
            {
                allowKillReturn.Set(); allowObservation.Set();
                await fault.WaitAsync(TimeSpan.FromSeconds(3));
                if (response != null) await response.WaitAsync(TimeSpan.FromSeconds(3));
            }
            JObject finished = await fault;
            Assert.True(finished.Value<bool>("success"));
            Assert.Equal("killed", (string)finished["faultReceipt"]["outcome"]);
            Assert.Equal((string)selected["runId"], (string)finished["faultReceipt"]["runId"]);
        }

        [Theory]
        [InlineData("kill-throws")]
        [InlineData("wait-throws")]
        [InlineData("wait-timeout")]
        public void FaultStopFlash_PostClaimFailureRemainsUnknownAndCannotReplay(string failure)
        {
            using var fixture = new FaultFixture();
            if (failure == "kill-throws") fixture.Process.OnKill = () => throw new InvalidOperationException("fixture failure");
            if (failure == "wait-throws") fixture.Process.ObserveExit = () => throw new InvalidOperationException("fixture failure");
            if (failure == "wait-timeout") fixture.Process.ObserveExit = () => false;
            JObject result = fixture.Arena.FaultStopFlash(fixture.Request(), fixture.Process);
            Assert.False(result.Value<bool>("success"));
            Assert.Equal("fault_outcome_unknown", result.Value<string>("error"));
            JObject receipt = (JObject)result["faultReceipt"];
            Assert.Equal("unknown", receipt.Value<string>("outcome"));
            Assert.True(receipt.Value<bool>("killAttempted"));
            Assert.False(receipt.Value<bool>("processExitObserved"));
            if (failure == "kill-throws") Assert.Equal(JTokenType.Null, receipt["killIssued"].Type);
            else Assert.True(receipt.Value<bool>("killIssued"));
            Assert.True(JToken.DeepEquals(receipt, fixture.Status()["faultReceipt"]));
            Assert.Equal("fault_already_claimed", fixture.Arena.FaultStopFlash(fixture.Request(), fixture.Process).Value<string>("error"));
            Assert.Equal(1, fixture.Process.KillCalls);
            Assert.Equal(failure == "kill-throws" ? 0 : 1, fixture.Process.WaitCalls);
            receipt["outcome"] = "modified-client-copy";
            Assert.Equal("unknown", (string)fixture.Status()["faultReceipt"]["outcome"]);
        }

        [Fact]
        public void FaultStopFlash_SuccessRecordsTheFullTicketWithoutManufacturingATerminalResult()
        {
            using var fixture = new FaultFixture();
            JObject request = fixture.Request();
            JObject result = fixture.Arena.FaultStopFlash(request, fixture.Process);
            Assert.True(result.Value<bool>("success"));
            JObject receipt = (JObject)result["faultReceipt"];
            Assert.True(ArenaRunIdentity.Matches(request, receipt));
            Assert.Equal("fault-fixture", receipt.Value<string>("faultId"));
            Assert.Equal("arena-worker.fault-receipt.v1", receipt.Value<string>("schema"));
            Assert.Equal(fixture.Process.Identity.ProcessId, (int)receipt["flashProcess"]["pid"]);
            Assert.Equal(fixture.Process.Identity.StartTimeUtc.UtcTicks.ToString(System.Globalization.CultureInfo.InvariantCulture), (string)receipt["flashProcess"]["processStartUtcTicks"]);
            Assert.Equal(fixture.Process.Identity.ExecutablePath, (string)receipt["flashProcess"]["processPath"]);
            Assert.Equal(1, receipt.Value<int>("socketGeneration"));
            Assert.Equal(5000, fixture.Process.LastWaitTimeout);
            Assert.Equal("running", result.Value<string>("state"));
            Assert.Equal(0, result.Value<int>("completedRuns"));
            Assert.Equal(JTokenType.Null, result["lastResult"].Type);
            Assert.Equal("fault_already_claimed", fixture.Arena.FaultStopFlash(request, fixture.Process).Value<string>("error"));
            Assert.Equal(1, fixture.Process.KillCalls);
        }

        [Theory]
        [InlineData(0, false)]
        [InlineData(120, false)]
        [InlineData(120, true)]
        public void FaultStopFlash_FirstWireReceiptMatchesLaterStatusAndResultBytesWithFractionalZeros(int milliseconds, bool killThrows)
        {
            DateTime fixedUtc = new DateTime(2026, 10, 11, 5, 30, 12, milliseconds, DateTimeKind.Utc);
            using var fixture = new FaultFixture(faultUtcNow: () => fixedUtc);
            if (killThrows) fixture.Process.OnKill = () => throw new InvalidOperationException("fixture failure");
            JObject config = new JObject {
                ["workerId"] = "fault-worker", ["sessionEpoch"] = "fault-session", ["allowFaultInjection"] = true,
                ["projectRoot"] = fixture.Root, ["stateRoot"] = Path.Combine(fixture.Root, "tmp", "arena-worker", "fault-session"),
                ["saveRoot"] = Path.Combine(fixture.Root, "saves"), ["outputRoot"] = Path.Combine(fixture.Root, "tmp", "arena-calibration"),
                ["swfOrigin"] = Path.Combine(fixture.Root, "CRAZYFLASHER7MercenaryEmpire.swf"), ["slot"] = "cf7_agent_fault_fixture"
            };
            var policy = ArenaWorkerPolicy.FromConfiguration(config, fixture.Root);
            var agent = new AgentControlTask(() => false, () => null, _ => { });
            var controller = new ArenaWorkerController(policy, agent, fixture.Arena, () => null, () => { },
                faultProcess: _ => fixture.Process);
            JObject first = ReadWorkerWire(controller.Handle(fixture.Request()));
            Assert.Equal(!killThrows, first.Value<bool>("success"));
            string firstReceipt = first["faultReceipt"].ToString(Formatting.None);
            Assert.Contains(killThrows ? "unknown" : "killed", firstReceipt);
            Assert.Equal(fixedUtc, DateTimeOffset.Parse(first["faultReceipt"]["claimedAtUtc"].Value<string>(),
                System.Globalization.CultureInfo.InvariantCulture).UtcDateTime);
            foreach (string action in new[] { "status", "result" })
            {
                JObject request = new JObject { ["action"] = action,
                    ["workerId"] = "fault-worker", ["sessionEpoch"] = "fault-session" };
                if (action == "result")
                {
                    request["assignmentId"] = fixture.Command["assignmentId"].DeepClone();
                    request["attemptId"] = fixture.Command["attemptId"].DeepClone();
                }
                JObject later = ReadWorkerWire(controller.Handle(request));
                Assert.Equal(System.Text.Encoding.UTF8.GetBytes(firstReceipt),
                    System.Text.Encoding.UTF8.GetBytes(later["faultReceipt"].ToString(Formatting.None)));
            }
            Assert.Equal(1, fixture.Process.KillCalls);
        }

        private static JObject ReadWorkerWire(JObject response)
        {
            string wire = null;
            HttpApiServer.WriteArenaWorkerResponse(response, value => wire = value, null);
            using var reader = new JsonTextReader(new StringReader(wire)) { DateParseHandling = DateParseHandling.None };
            // Keep the actual wire strings. Parsing dates here would hide the very
            // timestamp-normalization drift this regression is required to catch.
            return JObject.Load(reader);
        }

        private sealed class FaultProcess : IArenaWorkerFaultProcess
        {
            public XmlSocketPeerProcessIdentity Identity { get; set; }
            public bool IsAlive { get; set; } = true;
            internal int KillCalls;
            internal int WaitCalls;
            internal int LastWaitTimeout;
            internal Action OnKill;
            internal Func<bool> ObserveExit = () => true;
            public void Kill() { Interlocked.Increment(ref KillCalls); OnKill?.Invoke(); }
            public bool WaitForExit(int timeoutMs) { Interlocked.Increment(ref WaitCalls); LastWaitTimeout = timeoutMs; return ObserveExit(); }
            public void Dispose() { }
        }

        private sealed class FaultFixture : IDisposable
        {
            internal readonly ArenaCalibrationTask Arena;
            internal readonly FaultProcess Process;
            internal readonly string Root;
            internal volatile bool Ready = true;
            private readonly List<JObject> _commands = new List<JObject>();
            internal JObject Command { get { lock (_commands) return (JObject)_commands[^1].DeepClone(); } }
            internal int CommandCount { get { lock (_commands) return _commands.Count; } }

            internal FaultFixture(bool allowFaultInjection = true, int repeat = 1, Func<DateTime> faultUtcNow = null)
            {
                string root = Root = CreateProjectRoot();
                WriteManifest(root, "fault-fixture", repeat);
                Process = new FaultProcess { Identity = new XmlSocketPeerProcessIdentity(123,
                    DateTimeOffset.UtcNow, Path.Combine(root, "Flash.exe")) };
                Arena = new ArenaCalibrationTask(root, () => Ready, payload => {
                    JObject command = JObject.Parse(payload.TrimEnd('\0'));
                    if (command.Value<string>("action") == "arenaCalibrationRun")
                        lock (_commands) _commands.Add(command);
                }, _ => 10000, "fault-worker", "fault-session", false, allowFaultInjection, faultUtcNow);
                Arena.ObserveOwnedFlashIdentity(Process.Identity);
                JObject started = JObject.Parse(Arena.HandleControl(new JObject { ["action"] = "startBatch",
                    ["manifestPath"] = "tmp/arena-calibration/batches/fault-fixture/case_manifest.json" }));
                Assert.True(started.Value<bool>("success"), started.ToString());
                Assert.True(SpinWait.SpinUntil(() => CommandCount == 1, 2000));
            }
            internal JObject Request()
            {
                JObject request = ArenaRunIdentity.Capture(Command);
                request["action"] = "faultStopFlash"; request["faultId"] = "fault-fixture";
                return request;
            }
            internal JObject Status() => JObject.Parse(Arena.HandleControl(new JObject { ["action"] = "status" }));
            public void Dispose()
            {
                if (Status().Value<string>("state") == "running")
                {
                    Arena.HandleControl(new JObject { ["action"] = "abort" });
                    Assert.Equal("aborted", WaitForState(Arena, "aborted").Value<string>("state"));
                }
            }
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
            return WriteManifest(root, batchId, repeat, manifestHash, caseHash, manifestBatchId, null);
        }

        private static string WriteManifest(string root, string batchId, int repeat, string manifestHash, string caseHash, string manifestBatchId, int? spawnDistance)
        {
            string dir = Path.Combine(root, "tmp", "arena-calibration", "batches", batchId);
            Directory.CreateDirectory(dir);
            string manifestPath = Path.Combine(dir, "case_manifest.json");
            var testCase = new JObject
            {
                ["caseId"] = "pilot-thief-lv30x4-mirror",
                ["blueRoster"] = ThiefRoster(),
                ["redRoster"] = ThiefRoster(),
                ["repeat"] = repeat,
                ["timeoutFrames"] = 30,
                ["tags"] = new JArray("pilot", "test"),
                ["plannerReason"] = "unit test"
            };
            if (spawnDistance.HasValue)
                testCase["spawnDistance"] = spawnDistance.Value;

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
                    testCase
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
