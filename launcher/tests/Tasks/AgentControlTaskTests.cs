using System.Collections.Generic;
using Newtonsoft.Json.Linq;
using Xunit;
using CF7Launcher.Guardian.Hud;
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
            ObserveGameEntered(task);

            JObject resp = JObject.Parse(task.Handle(new JObject { ["action"] = "status" }));

            Assert.True((bool)resp["success"]);
            Assert.Equal("Ready", (string)resp["launchState"]);
            Assert.True((bool)resp["revealPerformed"]);
            Assert.True((bool)resp["socketConnected"]);
            Assert.True((bool)resp["gameEnteredObserved"]);
            Assert.True((bool)resp["readyForRuntimeAutomation"]);
            Assert.Empty(resp.Value<JArray>("runtimeReadyBlockedBy"));
            Assert.True((bool)resp["readyForArenaCalibration"]);
            Assert.Empty(resp.Value<JArray>("readyBlockedBy"));
            Assert.Equal("idle", (string)resp["arenaCalibration"]["state"]);
        }

        [Fact]
        public void Status_RuntimeReadiness_DoesNotDependOnArenaStatus()
        {
            AgentControlTask task = CreateRuntimeReadyTask(
                "cf7_agent_equipment_tuning",
                "attempt-tuning",
                delegate { return null; });

            JObject resp = JObject.Parse(task.Handle(new JObject { ["action"] = "status" }));

            Assert.True((bool)resp["readyForRuntimeAutomation"]);
            Assert.Empty(resp.Value<JArray>("runtimeReadyBlockedBy"));
            Assert.False((bool)resp["readyForArenaCalibration"]);
            Assert.Contains("arena_status_unreadable", resp.Value<JArray>("readyBlockedBy").Values<string>());
        }

        [Fact]
        public void Status_ReportsReadOnlyActivePanelObservation()
        {
            AgentControlTask task = CreateRuntimeReadyTask(
                "cf7_agent_equipment_tuning",
                "attempt-tuning");
            task.SetActivePanelStatusProvider(delegate
            {
                return new JObject
                {
                    ["name"] = "workbench",
                    ["instanceId"] = "panel.tuning.1"
                };
            });

            JObject resp = JObject.Parse(task.Handle(new JObject { ["action"] = "status" }));

            Assert.Equal("workbench", (string)resp["activePanel"]["name"]);
            Assert.Equal("panel.tuning.1", (string)resp["activePanel"]["instanceId"]);
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
            ObserveGameEntered(task);

            JObject resp = JObject.Parse(task.Handle(new JObject { ["action"] = "status" }));

            Assert.True((bool)resp["success"]);
            Assert.False((bool)resp["revealPerformed"]);
            Assert.False((bool)resp["readyForRuntimeAutomation"]);
            Assert.Contains("flash_not_revealed", resp.Value<JArray>("runtimeReadyBlockedBy").Values<string>());
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
            ObserveGameEntered(task);

            JObject resp = JObject.Parse(task.Handle(new JObject { ["action"] = "status" }));

            Assert.False((bool)resp["readyForRuntimeAutomation"]);
            Assert.Contains("save_decision_unsafe", resp.Value<JArray>("runtimeReadyBlockedBy").Values<string>());
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
            ObserveGameEntered(task);

            JObject resp = JObject.Parse(task.Handle(new JObject { ["action"] = "status" }));

            Assert.False((bool)resp["readyForRuntimeAutomation"]);
            Assert.Contains("runtime_save_not_loaded", resp.Value<JArray>("runtimeReadyBlockedBy").Values<string>());
            Assert.False((bool)resp["readyForArenaCalibration"]);
            Assert.Contains("runtime_save_not_loaded", resp.Value<JArray>("readyBlockedBy").Values<string>());
        }

        [Fact]
        public void Status_BlocksLoadedRuntimeUntilGameEnteredUiStateIsObserved()
        {
            AgentControlTask task = CreateTask(
                "Ready",
                true,
                true,
                "cf7_agent_equipment_tuning",
                "attempt-tuning",
                true);

            JObject resp = JObject.Parse(task.Handle(new JObject { ["action"] = "status" }));

            Assert.False((bool)resp["gameEnteredObserved"]);
            Assert.False((bool)resp["readyForRuntimeAutomation"]);
            Assert.Contains("game_enter_not_observed", resp.Value<JArray>("runtimeReadyBlockedBy").Values<string>());
            Assert.DoesNotContain("runtime_save_not_loaded", resp.Value<JArray>("runtimeReadyBlockedBy").Values<string>());
        }

        [Fact]
        public void ObserveUiData_S1ClearsGateAndLaterS0Reblocks()
        {
            AgentControlTask task = CreateTask(
                "Ready",
                true,
                true,
                "cf7_agent_equipment_tuning",
                "attempt-tuning",
                true);

            task.ObserveUiData(new UiDataPacket("g:1|s:1|ga:attempt-tuning|k:2"));
            JObject entered = JObject.Parse(task.Handle(new JObject { ["action"] = "status" }));
            Assert.True((bool)entered["gameEnteredObserved"]);
            Assert.Equal("attempt-tuning", (string)entered["gameEnteredAttemptId"]);
            Assert.True((bool)entered["readyForRuntimeAutomation"]);

            task.ObserveUiData(new UiDataPacket("s:1|ga:attempt-tuning|s:0"));
            JObject exited = JObject.Parse(task.Handle(new JObject { ["action"] = "status" }));
            Assert.False((bool)exited["gameEnteredObserved"]);
            Assert.Equal(JTokenType.Null, exited["gameEnteredAttemptId"].Type);
            Assert.False((bool)exited["readyForRuntimeAutomation"]);
            Assert.Contains("game_enter_not_observed", exited.Value<JArray>("runtimeReadyBlockedBy").Values<string>());

            task.ObserveUiData(new UiDataPacket("s:0|s:1|ga:attempt-tuning"));
            JObject reentered = JObject.Parse(task.Handle(new JObject { ["action"] = "status" }));
            Assert.True((bool)reentered["gameEnteredObserved"]);
        }

        [Fact]
        public void ObserveUiData_RejectsLegacyMissingAndStaleAttemptReceipts()
        {
            AgentControlTask task = CreateTask(
                "Ready",
                true,
                true,
                "cf7_agent_equipment_tuning",
                "attempt-tuning",
                true);

            task.ObserveUiData(new UiDataPacket("legacy|s:1|ga:attempt-tuning"));
            JObject legacy = JObject.Parse(task.Handle(new JObject { ["action"] = "status" }));
            Assert.False((bool)legacy["gameEnteredObserved"]);
            Assert.Equal(JTokenType.Null, legacy["gameEnteredAttemptId"].Type);

            task.ObserveUiData(new UiDataPacket("s:1"));
            JObject missing = JObject.Parse(task.Handle(new JObject { ["action"] = "status" }));
            Assert.False((bool)missing["gameEnteredObserved"]);
            Assert.Equal(JTokenType.Null, missing["gameEnteredAttemptId"].Type);

            task.ObserveUiData(new UiDataPacket("s:1|ga:attempt-stale"));
            JObject stale = JObject.Parse(task.Handle(new JObject { ["action"] = "status" }));
            Assert.False((bool)stale["gameEnteredObserved"]);
            Assert.Equal("attempt-stale", (string)stale["gameEnteredAttemptId"]);
            Assert.Contains("game_enter_not_observed", stale.Value<JArray>("runtimeReadyBlockedBy").Values<string>());

            task.ObserveUiData(new UiDataPacket("s:1|ga:attempt-tuning"));
            JObject current = JObject.Parse(task.Handle(new JObject { ["action"] = "status" }));
            Assert.True((bool)current["gameEnteredObserved"]);
            Assert.Equal("attempt-tuning", (string)current["gameEnteredAttemptId"]);
        }

        [Fact]
        public void Start_ClearsPreviouslyObservedGameEnteredState()
        {
            int startCount = 0;
            var task = new AgentControlTask(
                delegate { return "Idle"; },
                delegate { return false; },
                delegate { return false; },
                delegate(string slot, bool fresh, bool deferJsReveal, bool requireFlashReveal)
                {
                    startCount++;
                },
                null,
                null,
                delegate { return new JObject { ["success"] = true, ["state"] = "idle" }; },
                null,
                null,
                delegate
                {
                    return new JObject
                    {
                        ["attemptId"] = "attempt-old",
                        ["slot"] = "cf7_agent_equipment_tuning",
                        ["decision"] = "snapshot",
                        ["kind"] = "Snapshot"
                    };
                });
            ObserveGameEntered(task);

            JObject before = JObject.Parse(task.Handle(new JObject { ["action"] = "status" }));
            Assert.True((bool)before["gameEnteredObserved"]);

            JObject resp = JObject.Parse(task.Handle(new JObject
            {
                ["action"] = "start",
                ["slot"] = "cf7_agent_equipment_tuning"
            }));

            Assert.True((bool)resp["success"]);
            Assert.False((bool)resp["gameEnteredObserved"]);
            Assert.Contains("game_enter_not_observed", resp.Value<JArray>("runtimeReadyBlockedBy").Values<string>());
            Assert.Equal(1, startCount);
        }

        [Fact]
        public void OpenEquipmentTuning_ReadyDedicatedSlot_SendsExactlyOnce()
        {
            int sendCount = 0;
            AgentControlTask task = CreateRuntimeReadyTask(
                "cf7_agent_equipment_tuning",
                "attempt-tuning");
            task.SetEquipmentTuningOpenAction(delegate
            {
                sendCount++;
                return true;
            });

            JObject resp = JObject.Parse(task.Handle(OpenEquipmentTuningRequest(
                "cf7_agent_equipment_tuning",
                "attempt-tuning")));

            Assert.True((bool)resp["success"]);
            Assert.Equal("equipment_tuning_panel_open_requested", (string)resp["note"]);
            Assert.True((bool)resp["readyForRuntimeAutomation"]);
            Assert.Equal(1, sendCount);
        }

        [Theory]
        [InlineData(null)]
        [InlineData("")]
        [InlineData("crazyflasher7_saves")]
        [InlineData("cf7_agent_")]
        [InlineData("cf7_agent_bad/slot")]
        public void OpenEquipmentTuning_RejectsNonDedicatedExpectedSlot(string expectedSlot)
        {
            int sendCount = 0;
            AgentControlTask task = CreateRuntimeReadyTask(
                "cf7_agent_equipment_tuning",
                "attempt-tuning");
            task.SetEquipmentTuningOpenAction(delegate { sendCount++; return true; });
            JObject request = OpenEquipmentTuningRequest(expectedSlot, "attempt-tuning");

            JObject resp = JObject.Parse(task.Handle(request));

            Assert.False((bool)resp["success"]);
            Assert.Equal("invalid_expected_slot", (string)resp["error"]);
            Assert.Equal(0, sendCount);
        }

        [Fact]
        public void OpenEquipmentTuning_RejectsMissingExpectedAttempt()
        {
            int sendCount = 0;
            AgentControlTask task = CreateRuntimeReadyTask(
                "cf7_agent_equipment_tuning",
                "attempt-tuning");
            task.SetEquipmentTuningOpenAction(delegate { sendCount++; return true; });

            JObject resp = JObject.Parse(task.Handle(OpenEquipmentTuningRequest(
                "cf7_agent_equipment_tuning",
                null)));

            Assert.False((bool)resp["success"]);
            Assert.Equal("invalid_expected_attempt", (string)resp["error"]);
            Assert.Equal(0, sendCount);
        }

        [Fact]
        public void OpenEquipmentTuning_RejectsBeforeRuntimeReadyWithoutCallingSender()
        {
            int sendCount = 0;
            AgentControlTask task = CreateTask(
                "Ready",
                true,
                true,
                "cf7_agent_equipment_tuning",
                "attempt-tuning",
                false);
            ObserveGameEntered(task);
            task.SetEquipmentTuningOpenAction(delegate { sendCount++; return true; });

            JObject resp = JObject.Parse(task.Handle(OpenEquipmentTuningRequest(
                "cf7_agent_equipment_tuning",
                "attempt-tuning")));

            Assert.False((bool)resp["success"]);
            Assert.Equal("runtime_not_ready", (string)resp["error"]);
            Assert.Contains("runtime_save_not_loaded", resp.Value<JArray>("runtimeReadyBlockedBy").Values<string>());
            Assert.Equal(0, sendCount);
        }

        [Fact]
        public void OpenEquipmentTuning_RejectsLoadedRuntimeWithoutGameEnteredReceipt()
        {
            int sendCount = 0;
            AgentControlTask task = CreateTask(
                "Ready",
                true,
                true,
                "cf7_agent_equipment_tuning",
                "attempt-tuning",
                true);
            task.SetEquipmentTuningOpenAction(delegate { sendCount++; return true; });

            JObject resp = JObject.Parse(task.Handle(OpenEquipmentTuningRequest(
                "cf7_agent_equipment_tuning",
                "attempt-tuning")));

            Assert.False((bool)resp["success"]);
            Assert.Equal("runtime_not_ready", (string)resp["error"]);
            Assert.Contains("game_enter_not_observed", resp.Value<JArray>("runtimeReadyBlockedBy").Values<string>());
            Assert.Equal(0, sendCount);
        }

        [Theory]
        [InlineData("cf7_agent_other", "attempt-tuning")]
        [InlineData("cf7_agent_equipment_tuning", "attempt-stale")]
        public void OpenEquipmentTuning_RejectsStaleRuntimeAcknowledgement(
            string runtimeSlot,
            string runtimeAttempt)
        {
            int sendCount = 0;
            AgentControlTask task = CreateRuntimeReadyTask(
                "cf7_agent_equipment_tuning",
                "attempt-tuning");
            task.HandleRuntimeStatus(new JObject
            {
                ["payload"] = new JObject
                {
                    ["loaded"] = true,
                    ["attemptId"] = runtimeAttempt,
                    ["savePath"] = runtimeSlot,
                    ["role"] = "fs",
                    ["level"] = 10
                }
            });
            task.SetEquipmentTuningOpenAction(delegate { sendCount++; return true; });

            JObject resp = JObject.Parse(task.Handle(OpenEquipmentTuningRequest(
                "cf7_agent_equipment_tuning",
                "attempt-tuning")));

            Assert.False((bool)resp["success"]);
            Assert.Equal("runtime_not_ready", (string)resp["error"]);
            Assert.Contains("runtime_save_not_loaded", resp.Value<JArray>("runtimeReadyBlockedBy").Values<string>());
            Assert.Equal(0, sendCount);
        }

        [Theory]
        [InlineData("cf7_agent_other", "attempt-tuning", "agent_slot_mismatch")]
        [InlineData("cf7_agent_equipment_tuning", "attempt-other", "agent_attempt_mismatch")]
        public void OpenEquipmentTuning_RejectsExpectedWatermarkMismatch(
            string expectedSlot,
            string expectedAttempt,
            string expectedError)
        {
            int sendCount = 0;
            AgentControlTask task = CreateRuntimeReadyTask(
                "cf7_agent_equipment_tuning",
                "attempt-tuning");
            task.SetEquipmentTuningOpenAction(delegate { sendCount++; return true; });

            JObject resp = JObject.Parse(task.Handle(OpenEquipmentTuningRequest(
                expectedSlot,
                expectedAttempt)));

            Assert.False((bool)resp["success"]);
            Assert.Equal(expectedError, (string)resp["error"]);
            Assert.Equal(0, sendCount);
        }

        [Fact]
        public void OpenEquipmentTuning_RejectsLiveCurrentSlotEvenWhenRuntimeReady()
        {
            int sendCount = 0;
            AgentControlTask task = CreateRuntimeReadyTask(
                "crazyflasher7_saves",
                "attempt-live");
            task.SetEquipmentTuningOpenAction(delegate { sendCount++; return true; });

            JObject resp = JObject.Parse(task.Handle(OpenEquipmentTuningRequest(
                "cf7_agent_equipment_tuning",
                "attempt-live")));

            Assert.False((bool)resp["success"]);
            Assert.Equal("agent_slot_mismatch", (string)resp["error"]);
            Assert.Equal(0, sendCount);
        }

        [Fact]
        public void OpenEquipmentTuning_ReturnsUnavailableWithoutInjectedSender()
        {
            AgentControlTask task = CreateRuntimeReadyTask(
                "cf7_agent_equipment_tuning",
                "attempt-tuning");

            JObject resp = JObject.Parse(task.Handle(OpenEquipmentTuningRequest(
                "cf7_agent_equipment_tuning",
                "attempt-tuning")));

            Assert.False((bool)resp["success"]);
            Assert.Equal("equipment_tuning_open_unavailable", (string)resp["error"]);
        }

        [Fact]
        public void OpenEquipmentTuning_DoesNotClaimRequestedWhenSenderFails()
        {
            int sendCount = 0;
            AgentControlTask task = CreateRuntimeReadyTask(
                "cf7_agent_equipment_tuning",
                "attempt-tuning");
            task.SetEquipmentTuningOpenAction(delegate { sendCount++; return false; });

            JObject resp = JObject.Parse(task.Handle(OpenEquipmentTuningRequest(
                "cf7_agent_equipment_tuning",
                "attempt-tuning")));

            Assert.False((bool)resp["success"]);
            Assert.Equal("equipment_tuning_open_failed", (string)resp["error"]);
            Assert.Equal(1, sendCount);
        }

        [Fact]
        public void OpenCharacterBuild_ReadyDedicatedSlot_SendsFixedOpenerExactlyOnce()
        {
            int sendCount = 0;
            AgentControlTask task = CreateRuntimeReadyTask(
                "cf7_agent_character_build",
                "attempt-build");
            task.SetCharacterBuildOpenAction(delegate
            {
                sendCount++;
                return true;
            });

            JObject resp = JObject.Parse(task.Handle(
                OpenCharacterBuildRequest(
                    "cf7_agent_character_build",
                    "attempt-build")));

            Assert.True((bool)resp["success"]);
            Assert.Equal(
                "character_build_panel_open_requested",
                (string)resp["note"]);
            Assert.True((bool)resp["readyForRuntimeAutomation"]);
            Assert.Equal(1, sendCount);
        }

        [Fact]
        public void OpenCharacterBuild_ReusesRuntimeWatermarkGatesBeforeCallingOpener()
        {
            int sendCount = 0;
            AgentControlTask task = CreateTask(
                "Ready",
                true,
                true,
                "cf7_agent_character_build",
                "attempt-build",
                false);
            ObserveGameEntered(task);
            task.SetCharacterBuildOpenAction(delegate
            {
                sendCount++;
                return true;
            });

            JObject resp = JObject.Parse(task.Handle(
                OpenCharacterBuildRequest(
                    "cf7_agent_character_build",
                    "attempt-build")));

            Assert.False((bool)resp["success"]);
            Assert.Equal("runtime_not_ready", (string)resp["error"]);
            Assert.Contains(
                "runtime_save_not_loaded",
                resp.Value<JArray>(
                    "runtimeReadyBlockedBy").Values<string>());
            Assert.Equal(0, sendCount);
        }

        [Theory]
        [InlineData(false, "character_build_open_failed")]
        [InlineData(null, "character_build_open_unavailable")]
        public void OpenCharacterBuild_DoesNotClaimRequestWithoutSuccessfulOpener(
            bool? sendResult,
            string expectedError)
        {
            int sendCount = 0;
            AgentControlTask task = CreateRuntimeReadyTask(
                "cf7_agent_character_build",
                "attempt-build");
            if (sendResult.HasValue)
            {
                task.SetCharacterBuildOpenAction(delegate
                {
                    sendCount++;
                    return sendResult.Value;
                });
            }

            JObject resp = JObject.Parse(task.Handle(
                OpenCharacterBuildRequest(
                    "cf7_agent_character_build",
                    "attempt-build")));

            Assert.False((bool)resp["success"]);
            Assert.Equal(expectedError, (string)resp["error"]);
            Assert.Equal(sendResult.HasValue ? 1 : 0, sendCount);
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

        private static JObject OpenEquipmentTuningRequest(string expectedSlot, string expectedAttempt)
        {
            JObject request = new JObject
            {
                ["action"] = "openEquipmentTuning"
            };
            if (expectedSlot != null) request["expectedSlot"] = expectedSlot;
            if (expectedAttempt != null) request["expectedAttemptId"] = expectedAttempt;
            return request;
        }

        private static JObject OpenCharacterBuildRequest(
            string expectedSlot,
            string expectedAttempt)
        {
            JObject request = new JObject
            {
                ["action"] = "openCharacterBuild"
            };
            if (expectedSlot != null)
                request["expectedSlot"] = expectedSlot;
            if (expectedAttempt != null)
                request["expectedAttemptId"] = expectedAttempt;
            return request;
        }

        private static AgentControlTask CreateRuntimeReadyTask(
            string slot,
            string attempt,
            System.Func<JObject> arenaStatus = null)
        {
            AgentControlTask task = CreateTask(
                "Ready",
                true,
                true,
                slot,
                attempt,
                true,
                arenaStatus);
            ObserveGameEntered(task);
            return task;
        }

        private static void ObserveGameEntered(AgentControlTask task)
        {
            JObject status = JObject.Parse(task.Handle(new JObject { ["action"] = "status" }));
            string attempt = status.Value<JObject>("save") != null
                ? status.Value<JObject>("save").Value<string>("attemptId")
                : null;
            Assert.False(string.IsNullOrEmpty(attempt));
            task.ObserveUiData(new UiDataPacket("s:1|ga:" + attempt));
        }

        private static AgentControlTask CreateTask(
            string launchState,
            bool socketReady,
            bool revealPerformed,
            string slot,
            string attempt,
            bool publishRuntimeStatus,
            System.Func<JObject> arenaStatus = null)
        {
            var task = new AgentControlTask(
                delegate { return launchState; },
                delegate { return socketReady; },
                delegate { return revealPerformed; },
                null,
                null,
                null,
                arenaStatus ?? delegate { return new JObject { ["success"] = true, ["state"] = "idle" }; },
                null,
                null,
                delegate
                {
                    return new JObject
                    {
                        ["attemptId"] = attempt,
                        ["slot"] = slot,
                        ["decision"] = "snapshot",
                        ["kind"] = "Snapshot",
                        ["source"] = "json_shadow"
                    };
                });
            if (publishRuntimeStatus)
            {
                task.HandleRuntimeStatus(new JObject
                {
                    ["payload"] = new JObject
                    {
                        ["loaded"] = true,
                        ["attemptId"] = attempt,
                        ["savePath"] = slot,
                        ["role"] = "fs",
                        ["level"] = 10
                    }
                });
            }
            return task;
        }
    }
}
