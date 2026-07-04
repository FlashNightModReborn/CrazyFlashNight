using System.Collections.Generic;
using Newtonsoft.Json.Linq;
using Xunit;
using CF7Launcher.Tasks;

namespace CF7Launcher.Tests.Tasks
{
    public class AgentControlTaskTests
    {
        [Fact]
        public void Status_ReportsCalibrationReadiness()
        {
            var task = new AgentControlTask(
                delegate { return "Ready"; },
                delegate { return true; },
                delegate { return true; },
                null,
                null,
                null,
                delegate { return new JObject { ["success"] = true, ["state"] = "idle" }; },
                null,
                null,
                delegate
                {
                    return new JObject
                    {
                        ["attemptId"] = "attempt-a",
                        ["slot"] = "cf7_agent_arena_calibration",
                        ["decision"] = "snapshot",
                        ["kind"] = "Snapshot",
                        ["source"] = "json_shadow"
                    };
                });
            task.HandleRuntimeStatus(new JObject
            {
                ["payload"] = new JObject
                {
                    ["loaded"] = true,
                    ["attemptId"] = "attempt-a",
                    ["savePath"] = "cf7_agent_arena_calibration",
                    ["role"] = "fs",
                    ["level"] = 10
                }
            });

            JObject resp = JObject.Parse(task.Handle(new JObject { ["action"] = "status" }));

            Assert.True((bool)resp["success"]);
            Assert.Equal("Ready", (string)resp["launchState"]);
            Assert.True((bool)resp["revealPerformed"]);
            Assert.True((bool)resp["socketConnected"]);
            Assert.True((bool)resp["readyForArenaCalibration"]);
            Assert.Empty(resp.Value<JArray>("readyBlockedBy"));
            Assert.Equal("idle", (string)resp["arenaCalibration"]["state"]);
        }

        [Fact]
        public void Start_DefaultsToFlashRevealAndRemembersSlot()
        {
            var calls = new List<string>();
            string remembered = null;
            var task = new AgentControlTask(
                delegate { return "Idle"; },
                delegate { return false; },
                delegate { return false; },
                delegate(string slot, bool fresh, bool deferJsReveal, bool requireFlashReveal)
                {
                    calls.Add(slot + "|" + fresh + "|" + deferJsReveal + "|" + requireFlashReveal);
                },
                null,
                null,
                delegate { return new JObject { ["state"] = "idle" }; },
                null,
                delegate(string slot) { remembered = slot; });

            JObject resp = JObject.Parse(task.Handle(new JObject
            {
                ["action"] = "start",
                ["slot"] = "crazyflasher7_saves",
                ["rememberSlot"] = true
            }));

            Assert.True((bool)resp["success"]);
            Assert.Equal("start_requested", (string)resp["note"]);
            Assert.Equal("crazyflasher7_saves", remembered);
            Assert.Single(calls);
            Assert.Equal("crazyflasher7_saves|False|False|True", calls[0]);
        }

        [Fact]
        public void Status_DoesNotReportReadyBeforeReveal()
        {
            var task = new AgentControlTask(
                delegate { return "Ready"; },
                delegate { return true; },
                delegate { return false; },
                null,
                null,
                null,
                delegate { return new JObject { ["success"] = true, ["state"] = "idle" }; },
                null,
                null,
                delegate
                {
                    return new JObject
                    {
                        ["attemptId"] = "attempt-a",
                        ["slot"] = "cf7_agent_arena_calibration",
                        ["decision"] = "snapshot",
                        ["kind"] = "Snapshot",
                        ["source"] = "json_shadow"
                    };
                });
            task.HandleRuntimeStatus(new JObject
            {
                ["payload"] = new JObject
                {
                    ["loaded"] = true,
                    ["attemptId"] = "attempt-a",
                    ["savePath"] = "cf7_agent_arena_calibration",
                    ["role"] = "fs",
                    ["level"] = 10
                }
            });

            JObject resp = JObject.Parse(task.Handle(new JObject { ["action"] = "status" }));

            Assert.True((bool)resp["success"]);
            Assert.False((bool)resp["revealPerformed"]);
            Assert.False((bool)resp["readyForArenaCalibration"]);
        }

        [Fact]
        public void Status_BlocksCorruptSaveDecision()
        {
            var task = new AgentControlTask(
                delegate { return "Ready"; },
                delegate { return true; },
                delegate { return true; },
                null,
                null,
                null,
                delegate { return new JObject { ["success"] = true, ["state"] = "idle" }; },
                null,
                null,
                delegate
                {
                    return new JObject
                    {
                        ["attemptId"] = "attempt-a",
                        ["slot"] = "crazyflasher7_saves",
                        ["decision"] = "corrupt",
                        ["kind"] = "Corrupt",
                        ["corruptDetail"] = "v3.0_structure_invalid"
                    };
                });
            task.HandleRuntimeStatus(new JObject
            {
                ["payload"] = new JObject
                {
                    ["loaded"] = true,
                    ["attemptId"] = "attempt-a",
                    ["savePath"] = "crazyflasher7_saves",
                    ["role"] = "fs",
                    ["level"] = 10
                }
            });

            JObject resp = JObject.Parse(task.Handle(new JObject { ["action"] = "status" }));

            Assert.False((bool)resp["readyForArenaCalibration"]);
            Assert.Contains("save_decision_unsafe", resp.Value<JArray>("readyBlockedBy").Values<string>());
        }

        [Fact]
        public void Status_BlocksBeforeRuntimeSaveLoaded()
        {
            var task = new AgentControlTask(
                delegate { return "Ready"; },
                delegate { return true; },
                delegate { return true; },
                null,
                null,
                null,
                delegate { return new JObject { ["success"] = true, ["state"] = "idle" }; },
                null,
                null,
                delegate
                {
                    return new JObject
                    {
                        ["attemptId"] = "attempt-a",
                        ["slot"] = "cf7_agent_arena_calibration",
                        ["decision"] = "snapshot",
                        ["kind"] = "Snapshot",
                        ["source"] = "json_shadow"
                    };
                });

            JObject resp = JObject.Parse(task.Handle(new JObject { ["action"] = "status" }));

            Assert.False((bool)resp["readyForArenaCalibration"]);
            Assert.Contains("runtime_save_not_loaded", resp.Value<JArray>("readyBlockedBy").Values<string>());
        }

        [Fact]
        public void Start_RejectsUnsafeSlot()
        {
            bool started = false;
            var task = new AgentControlTask(
                delegate { return "Idle"; },
                delegate { return false; },
                delegate { return false; },
                delegate(string slot, bool fresh, bool deferJsReveal, bool requireFlashReveal)
                {
                    started = true;
                },
                null,
                null,
                delegate { return new JObject { ["state"] = "idle" }; },
                null,
                null);

            JObject resp = JObject.Parse(task.Handle(new JObject
            {
                ["action"] = "start",
                ["slot"] = "..\\real-save"
            }));

            Assert.False((bool)resp["success"]);
            Assert.Equal("invalid_slot", (string)resp["error"]);
            Assert.False(started);
        }

        [Fact]
        public void Start_ReturnsUnavailableUntilLaunchFlowIsInjected()
        {
            var task = new AgentControlTask(
                delegate { return false; },
                delegate { return new JObject { ["state"] = "idle" }; },
                null);

            JObject resp = JObject.Parse(task.Handle(new JObject
            {
                ["action"] = "start",
                ["slot"] = "crazyflasher7_saves"
            }));

            Assert.False((bool)resp["success"]);
            Assert.Equal("launch_flow_unavailable", (string)resp["error"]);
        }
    }
}
