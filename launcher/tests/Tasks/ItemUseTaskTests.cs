using System;
using System.Collections.Generic;
using System.Threading;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Tasks
{
    public sealed class ItemUseTaskTests
    {
        private const string Panel = "panel.workbench.item.use.1";
        private const long Generation = 17;

        private sealed class Harness : IDisposable
        {
            public readonly List<JObject> Flash = new List<JObject>();
            public readonly List<JObject> Web = new List<JObject>();
            public readonly ItemUseTask Task;
            public bool Ready = true;
            public bool SendSucceeds = true;
            public bool BindingCurrent = true;

            public Harness(int timeoutMs = 1000)
            {
                Task = new ItemUseTask(
                    delegate { return Ready; },
                    delegate(string payload)
                    {
                        Flash.Add(JObject.Parse(payload.TrimEnd('\0')));
                        return SendSucceeds;
                    },
                    delegate(string panel, long generation)
                    {
                        return BindingCurrent
                            && panel == Panel
                            && generation == Generation;
                    },
                    timeoutMs);
                Task.SetPostToWeb(
                    value => Web.Add(JObject.Parse(value)));
            }

            public void Dispose() { Task.Dispose(); }
        }

        [Theory]
        [InlineData("open", "itemUseOpen")]
        [InlineData("consume", "itemUseConsume")]
        [InlineData("inboxSnapshot", "itemUseInboxSnapshot")]
        [InlineData("cooldownSnapshot", "itemUseCooldownSnapshot")]
        public void ExactCommands_FlattenOnlyNormalizedPayload(
            string command,
            string action)
        {
            using (var harness = new Harness())
            {
                JObject request = Request(command, "item.use.exact." + command);

                harness.Task.HandleWebRequest(command, request);

                JObject sent = Assert.Single(harness.Flash);
                Assert.Equal("cmd", sent.Value<string>("task"));
                Assert.Equal(action, sent.Value<string>("action"));
                Assert.Equal(1, sent.Value<int>("v"));
                Assert.Equal(Panel, sent.Value<string>("panelInstanceId"));
                Assert.Equal(Generation, sent.Value<long>("sessionGeneration"));
                Assert.Null(sent["domain"]);
                Assert.Null(sent["panel"]);
                Assert.Null(sent["cmd"]);
                Assert.Null(sent["type"]);
                if (command == "open" || command == "consume")
                {
                    Assert.Equal(
                        "operation." + command,
                        sent.Value<string>("operationId"));
                    Assert.Equal(4, ((JObject)sent["source"]).Count);
                }
                else
                {
                    Assert.Null(sent["operationId"]);
                    Assert.Null(sent["source"]);
                }
            }
        }

        [Fact]
        public void InvalidShapeAndStaleBinding_FailClosedWithoutFlashSend()
        {
            using (var harness = new Harness())
            {
                JObject extra = Request("open", "item.use.invalid.extra");
                extra["extra"] = true;
                harness.Task.HandleWebRequest("open", extra);

                harness.BindingCurrent = false;
                harness.Task.HandleWebRequest(
                    "open",
                    Request("open", "item.use.stale.binding"));

                Assert.Empty(harness.Flash);
                Assert.Equal(2, harness.Web.Count);
                Assert.Equal("invalid_payload", harness.Web[0].Value<string>("error"));
                Assert.Equal(
                    "panel_instance_expired",
                    harness.Web[1].Value<string>("error"));
            }
        }

        [Fact]
        public void WritesAreSingleFlightAndNeverRouteIntoLoadout()
        {
            using (var harness = new Harness())
            {
                harness.Task.HandleWebRequest(
                    "open", Request("open", "item.use.busy.open"));
                harness.Task.HandleWebRequest(
                    "consume", Request("consume", "item.use.busy.consume"));

                JObject sent = Assert.Single(harness.Flash);
                Assert.Equal("itemUseOpen", sent.Value<string>("action"));
                Assert.DoesNotContain(
                    "characterBuild",
                    sent.Value<string>("action"),
                    StringComparison.Ordinal);
                JObject rejected = Assert.Single(harness.Web);
                Assert.Equal("busy", rejected.Value<string>("error"));
                Assert.Equal("write_pending", harness.Task.WriteState);
            }
        }

        [Fact]
        public void UnknownWriteAllowsOnlyExactQueryAndNeverReplaysWrite()
        {
            using (var harness = new Harness())
            {
                harness.SendSucceeds = false;
                harness.Task.HandleWebRequest(
                    "open", Request("open", "item.use.unknown.open"));
                Assert.Equal("needs_reconcile", harness.Task.WriteState);
                Assert.True(harness.Web[0].Value<bool>("requiresReconcile"));

                harness.SendSucceeds = true;
                harness.Task.HandleWebRequest(
                    "consume", Request("consume", "item.use.unknown.blocked"));
                Assert.Equal(
                    "reconcile_required",
                    harness.Web[1].Value<string>("error"));
                Assert.Equal(
                    "operation.open",
                    harness.Web[1].Value<string>("operationId"));

                JObject wrongQuery = Request(
                    "query", "item.use.query.wrong");
                wrongQuery["payload"]["operationId"] = "operation.foreign";
                harness.Task.HandleWebRequest("query", wrongQuery);
                Assert.Equal(
                    "operation_mismatch",
                    harness.Web[2].Value<string>("error"));

                harness.Task.HandleWebRequest(
                    "query", Request("query", "item.use.query.exact"));
                JObject query = harness.Flash[harness.Flash.Count - 1];
                Assert.Equal("itemUseQuery", query.Value<string>("action"));
                harness.Task.HandleFlashResponse(
                    QueryNotFoundResponse(query.Value<int>("callId")),
                    null);

                JObject reconciled = harness.Web[harness.Web.Count - 1];
                Assert.True(reconciled.Value<bool>("success"));
                Assert.Null(reconciled["reconciled"]);
                Assert.Null(reconciled["writeApplied"]);
                Assert.Equal("idle", harness.Task.WriteState);
                Assert.Equal(
                    new[] { "itemUseOpen", "itemUseQuery" },
                    harness.Flash.ConvertAll(
                        value => value.Value<string>("action")).ToArray());
            }
        }

        [Fact]
        public void ClosedWorkbenchClearsStrandedUnknownOperationForNextSession()
        {
            using (var harness = new Harness())
            {
                harness.Task.HandleWebRequest(
                    "open", Request("open", "item.use.close.inflight"));
                Assert.Equal("write_pending", harness.Task.WriteState);

                harness.Task.ClearPending();

                Assert.Equal("idle", harness.Task.WriteState);
                harness.Task.HandleWebRequest(
                    "consume", Request("consume", "item.use.next.session"));
                Assert.Equal(
                    "itemUseConsume",
                    harness.Flash[harness.Flash.Count - 1]
                        .Value<string>("action"));
            }
        }

        [Fact]
        public void DisconnectedWriteFreezesAndReconcilesWithoutReplay()
        {
            using (var harness = new Harness())
            {
                harness.Ready = false;
                harness.Task.HandleWebRequest(
                    "open", Request("open", "item.use.disconnected.open"));

                Assert.Empty(harness.Flash);
                Assert.Equal("needs_reconcile", harness.Task.WriteState);
                Assert.True(
                    Assert.Single(harness.Web)
                        .Value<bool>("requiresReconcile"));

                harness.Ready = true;
                harness.Task.HandleWebRequest(
                    "query", Request("query", "item.use.disconnected.query"));
                JObject query = Assert.Single(harness.Flash);
                Assert.Equal(
                    "itemUseQuery",
                    query.Value<string>("action"));
                harness.Task.HandleFlashResponse(
                    QueryNotFoundResponse(
                        query.Value<int>("callId")),
                    null);

                Assert.Equal("idle", harness.Task.WriteState);
                Assert.Equal(
                    new[] { "itemUseQuery" },
                    harness.Flash.ConvertAll(
                        value => value.Value<string>("action")).ToArray());
            }
        }

        [Fact]
        public void OpenSuccessCachesAuthorityButRequiresExplicitExactCloseHandoff()
        {
            using (var harness = new Harness())
            {
                harness.Task.HandleWebRequest(
                    "open", Request("open", "item.use.open.success"));
                JObject sent = Assert.Single(harness.Flash);
                harness.Task.HandleFlashResponse(
                    OpenSuccessResponse(sent.Value<int>("callId")),
                    null);

                JObject web = Assert.Single(harness.Web);
                Assert.True(web.Value<bool>("success"));
                Assert.Equal("reward.batch.1", web.Value<string>("rewardBatchId"));
                Assert.Equal("idle", harness.Task.WriteState);

                ItemUseTask.RewardHandoff handoff;
                Assert.False(harness.Task.TryTakeClosedRewardHandoff(out handoff));
                Assert.True(harness.Task.TryArmRewardNavigation(Panel, Generation));
                harness.Task.OnWorkbenchPanelClosed("panel.foreign");
                Assert.False(harness.Task.TryTakeClosedRewardHandoff(out handoff));
                harness.Task.OnWorkbenchPanelClosed(Panel);
                Assert.True(harness.Task.TryTakeClosedRewardHandoff(out handoff));
                Assert.Equal(Panel, handoff.PanelInstanceId);
                Assert.Equal(
                    "reward_inbox",
                    handoff.Authority.Value<string>("sourceKind"));
            }
        }

        [Fact]
        public void OrdinaryCloseRetiresUnarmedAuthorityFromExactPanelLifetime()
        {
            using (var harness = new Harness())
            {
                harness.Task.HandleWebRequest(
                    "open", Request("open", "item.use.open.ordinary.close"));
                JObject sent = Assert.Single(harness.Flash);
                harness.Task.HandleFlashResponse(
                    OpenSuccessResponse(sent.Value<int>("callId")),
                    null);

                harness.Task.OnWorkbenchPanelClosed(Panel);

                ItemUseTask.RewardHandoff handoff;
                Assert.False(harness.Task.TryArmRewardNavigation(
                    Panel, Generation));
                Assert.False(harness.Task.TryTakeClosedRewardHandoff(
                    out handoff));
            }
        }

        [Fact]
        public void ZeroHitOpenIsDefinitiveSuccessWithoutRewardHandoff()
        {
            using (var harness = new Harness())
            {
                harness.Task.HandleWebRequest(
                    "open", Request("open", "item.use.open.zero-hit"));
                JObject sent = Assert.Single(harness.Flash);
                JObject response = OpenSuccessResponse(
                    sent.Value<int>("callId"));
                response["rewardReady"] = false;
                response["inboxSummary"] = InboxSummary(0, 0, 3);
                response["rewardAuthority"] = JValue.CreateNull();

                harness.Task.HandleFlashResponse(response, null);

                JObject web = Assert.Single(harness.Web);
                Assert.True(web.Value<bool>("success"));
                Assert.False(web.Value<bool>("rewardReady"));
                Assert.Equal("idle", harness.Task.WriteState);
                Assert.False(harness.Task.TryArmRewardNavigation(
                    Panel, Generation));
            }
        }

        [Fact]
        public void CommittedOpenQueryNeedsExplicitInboxSnapshotBeforeNavigation()
        {
            using (var harness = new Harness())
            {
                harness.SendSucceeds = false;
                harness.Task.HandleWebRequest(
                    "open", Request("open", "item.use.query.committed.open"));
                Assert.Equal("needs_reconcile", harness.Task.WriteState);

                harness.SendSucceeds = true;
                harness.Task.HandleWebRequest(
                    "query", Request("query", "item.use.query.committed"));
                JObject query = harness.Flash[harness.Flash.Count - 1];
                harness.Task.HandleFlashResponse(
                    QueryCommittedOpenResponse(
                        query.Value<int>("callId")),
                    null);

                JObject reconciled = harness.Web[harness.Web.Count - 1];
                Assert.True(reconciled.Value<bool>("success"));
                Assert.True(reconciled.Value<bool>("found"));
                Assert.Null(reconciled["reconciled"]);
                Assert.Null(reconciled["writeApplied"]);
                Assert.Null(reconciled["rewardAuthority"]);
                Assert.False(harness.Task.TryArmRewardNavigation(
                    Panel, Generation));

                harness.Task.HandleWebRequest(
                    "inboxSnapshot",
                    Request(
                        "inboxSnapshot",
                        "item.use.snapshot.after.query"));
                JObject snapshot = harness.Flash[harness.Flash.Count - 1];
                harness.Task.HandleFlashResponse(
                    InboxSnapshotResponse(
                        snapshot.Value<int>("callId")),
                    null);

                Assert.True(harness.Task.TryArmRewardNavigation(
                    Panel, Generation));
            }
        }

        [Fact]
        public void CooldownSnapshotProjectsExactlyFourReadOnlyFrameLanes()
        {
            using (var harness = new Harness())
            {
                harness.Task.HandleWebRequest(
                    "cooldownSnapshot",
                    Request("cooldownSnapshot", "item.use.cooldown.valid"));
                JObject sent = Assert.Single(harness.Flash);
                Assert.Equal(
                    "itemUseCooldownSnapshot",
                    sent.Value<string>("action"));

                harness.Task.HandleFlashResponse(
                    CooldownSnapshotResponse(sent.Value<int>("callId")),
                    null);

                JObject web = Assert.Single(harness.Web);
                Assert.True(web.Value<bool>("success"));
                JArray lanes = Assert.IsType<JArray>(web["cooldownLanes"]);
                Assert.Equal(4, lanes.Count);
                Assert.Equal(2, lanes[2].Value<int>("lane"));
                Assert.False(lanes[2].Value<bool>("ready"));
                Assert.Equal(2300, lanes[2].Value<int>("remainingMs"));
                Assert.Equal("idle", harness.Task.WriteState);
                Assert.Null(web["requiresReconcile"]);

                harness.Task.HandleWebRequest(
                    "cooldownSnapshot",
                    Request("cooldownSnapshot", "item.use.cooldown.invalid"));
                sent = harness.Flash[harness.Flash.Count - 1];
                JObject malformed = CooldownSnapshotResponse(
                    sent.Value<int>("callId"));
                malformed["cooldownLanes"][1]["lane"] = 0;
                harness.Task.HandleFlashResponse(malformed, null);

                JObject rejected = harness.Web[harness.Web.Count - 1];
                Assert.Equal(
                    "malformed_response",
                    rejected.Value<string>("error"));
                Assert.Null(rejected["requiresReconcile"]);
                Assert.Equal("idle", harness.Task.WriteState);
            }
        }

        [Fact]
        public void MalformedOpenSuccessFreezesUntilQuery()
        {
            using (var harness = new Harness())
            {
                harness.Task.HandleWebRequest(
                    "open", Request("open", "item.use.open.malformed"));
                JObject sent = Assert.Single(harness.Flash);
                JObject response = OpenSuccessResponse(
                    sent.Value<int>("callId"));
                response["rewardAuthority"]["sourceKind"] = "map_chest";

                harness.Task.HandleFlashResponse(response, null);

                JObject web = Assert.Single(harness.Web);
                Assert.Equal("malformed_response", web.Value<string>("error"));
                Assert.True(web.Value<bool>("requiresReconcile"));
                Assert.Equal("needs_reconcile", harness.Task.WriteState);
            }
        }

        [Fact]
        public void DefinitiveFailureAndConsumeSuccessClearWriteGate()
        {
            using (var harness = new Harness())
            {
                harness.Task.HandleWebRequest(
                    "open", Request("open", "item.use.open.full"));
                int openCall = harness.Flash[0].Value<int>("callId");
                harness.Task.HandleFlashResponse(
                    FailureResponse(
                        openCall, "open", "operation.open", "reward_inbox_full"),
                    null);
                Assert.Equal("idle", harness.Task.WriteState);
                Assert.Null(harness.Web[0]["requiresReconcile"]);

                harness.Task.HandleWebRequest(
                    "consume", Request("consume", "item.use.consume.success"));
                int consumeCall = harness.Flash[1].Value<int>("callId");
                harness.Task.HandleFlashResponse(
                    ConsumeSuccessResponse(consumeCall), null);

                JObject web = harness.Web[1];
                Assert.True(web.Value<bool>("success"));
                Assert.Equal(2, web.Value<int>("selectedLane"));
                Assert.Equal(1, web.Value<int>("consumed"));
                Assert.Equal("idle", harness.Task.WriteState);
            }
        }

        [Fact]
        public void TimeoutAndDisposeDrainWithoutLateResponseRevival()
        {
            JObject timeout = null;
            using (var seen = new ManualResetEventSlim(false))
            using (var task = new ItemUseTask(
                () => true,
                _ => true,
                (panel, generation) => panel == Panel && generation == Generation,
                20))
            {
                task.SetPostToWeb(value =>
                {
                    timeout = JObject.Parse(value);
                    seen.Set();
                });
                task.HandleWebRequest(
                    "open", Request("open", "item.use.timeout"));
                Assert.True(seen.Wait(TimeSpan.FromSeconds(2)));
                Assert.Equal("timeout", timeout.Value<string>("error"));
                Assert.True(timeout.Value<bool>("requiresReconcile"));
                Assert.Equal("needs_reconcile", task.WriteState);
            }

            var harness = new Harness();
            try
            {
                harness.Task.HandleWebRequest(
                    "consume", Request("consume", "item.use.dispose"));
                int callId = harness.Flash[0].Value<int>("callId");
                harness.Task.Dispose();
                harness.Task.HandleFlashResponse(
                    ConsumeSuccessResponse(callId), null);
                Assert.Empty(harness.Web);
                Assert.Equal("needs_reconcile", harness.Task.WriteState);
            }
            finally
            {
                harness.Dispose();
            }
        }

        private static JObject Request(string command, string callId)
        {
            var payload = new JObject
            {
                ["v"] = 1,
                ["panelInstanceId"] = Panel,
                ["sessionGeneration"] = Generation
            };
            if (command == "open" || command == "consume")
            {
                payload["operationId"] = "operation." + command;
                payload["source"] = new JObject
                {
                    ["physicalSlot"] = 7,
                    ["slotLease"] = "lease.item.use.7",
                    ["itemName"] = command == "open" ? "材料盒子" : "普通hp药剂",
                    ["backpackVersion"] = 31
                };
            }
            else if (command == "query")
            {
                payload["operationId"] = "operation.open";
            }
            return new JObject
            {
                ["type"] = "panel",
                ["panel"] = "workbench",
                ["domain"] = "item_use",
                ["cmd"] = command,
                ["callId"] = callId,
                ["panelInstanceId"] = Panel,
                ["payload"] = payload
            };
        }

        private static JObject CommonResponse(
            int callId,
            string command,
            string operationId,
            bool success)
        {
            var response = new JObject
            {
                ["task"] = "item_use_response",
                ["callId"] = callId,
                ["v"] = 1,
                ["success"] = success,
                ["command"] = command,
                ["panelInstanceId"] = Panel,
                ["sessionGeneration"] = Generation
            };
            if (operationId != null) response["operationId"] = operationId;
            return response;
        }

        private static JObject OpenSuccessResponse(int callId)
        {
            JObject response = CommonResponse(
                callId, "open", "operation.open", true);
            response["consumed"] = 1;
            response["remaining"] = 2;
            response["rewardReady"] = true;
            response["rewardBatchId"] = "reward.batch.1";
            response["inboxSummary"] = InboxSummary();
            response["rewardAuthority"] = RewardAuthority();
            return response;
        }

        private static JObject ConsumeSuccessResponse(int callId)
        {
            JObject response = CommonResponse(
                callId, "consume", "operation.consume", true);
            response["consumed"] = 1;
            response["remaining"] = 4;
            response["selectedLane"] = 2;
            return response;
        }

        private static JObject QueryNotFoundResponse(int callId)
        {
            JObject response = CommonResponse(
                callId, "query", "operation.open", true);
            response["found"] = false;
            response["inboxSummary"] = InboxSummary(0, 0, 3);
            return response;
        }

        private static JObject QueryCommittedOpenResponse(int callId)
        {
            JObject response = CommonResponse(
                callId, "query", "operation.open", true);
            response["found"] = true;
            response["receipt"] = new JObject
            {
                ["kind"] = "open",
                ["status"] = "committed",
                ["consumed"] = 1,
                ["remaining"] = 2,
                ["rewardBatchId"] = "reward.batch.1",
                ["rewardReady"] = true
            };
            response["inboxSummary"] = InboxSummary();
            return response;
        }

        private static JObject InboxSnapshotResponse(int callId)
        {
            JObject response = CommonResponse(
                callId, "inboxSnapshot", null, true);
            response["inboxSummary"] = InboxSummary();
            response["rewardReady"] = true;
            response["rewardAuthority"] = RewardAuthority();
            return response;
        }

        private static JObject CooldownSnapshotResponse(int callId)
        {
            JObject response = CommonResponse(
                callId, "cooldownSnapshot", null, true);
            var lanes = new JArray();
            for (int lane = 0; lane < 4; lane++)
            {
                bool ready = lane != 2;
                lanes.Add(new JObject
                {
                    ["lane"] = lane,
                    ["ready"] = ready,
                    ["totalSteps"] = ready ? 0 : 90,
                    ["currentStep"] = ready ? 0 : 21,
                    ["progressPercent"] = ready ? 0 : 23,
                    ["animationFrame"] = ready ? 1 : 24,
                    ["remainingMs"] = ready ? 0 : 2300
                });
            }
            response["cooldownLanes"] = lanes;
            return response;
        }

        private static JObject FailureResponse(
            int callId,
            string command,
            string operationId,
            string error)
        {
            JObject response = CommonResponse(
                callId, command, operationId, false);
            response["error"] = error;
            return response;
        }

        private static JObject InboxSummary(
            int batchCount = 1,
            int remainingCount = 1,
            int authorityRevision = 2)
        {
            return new JObject
            {
                ["v"] = 1,
                ["batchCount"] = batchCount,
                ["remainingCount"] = remainingCount,
                ["capacity"] = 64,
                ["authorityRevision"] = authorityRevision,
                ["recoverableRootOperationId"] = "",
                ["recoverableRootStatus"] = "not_started",
                ["recoveryRequired"] = false
            };
        }

        private static JObject RewardAuthority()
        {
            return new JObject
            {
                ["sourceKind"] = "reward_inbox",
                ["chestSessionId"] = "reward.chest.1",
                ["lootContainerId"] = "reward.container.1",
                ["containerEpoch"] = 4,
                ["openAttemptSeq"] = 1,
                ["displayName"] = "待领取物品",
                ["authorityRevision"] = 1,
                ["state"] = "LOOT_ACTIVE",
                ["remainingCount"] = 1,
                ["capacity"] = 8,
                ["columns"] = 8,
                ["recoverableRootOperationId"] = "",
                ["recoverableRootStatus"] = "not_started",
                ["recoveryRequired"] = false,
                ["recoveryOnly"] = false
            };
        }
    }
}
