using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using Newtonsoft.Json.Linq;
using Xunit;
using CF7Launcher.Guardian;
using CF7Launcher.Tasks;

namespace CF7Launcher.Tests.Tasks
{
    public sealed class LootTaskTests
    {
        private const string PanelInstanceId = "panel.loot.host.1";
        private const string ChestSessionId = "chest.session.1";
        private const string LootContainerId = "loot.container.1";
        private const int ContainerEpoch = 7;
        private const string RecoveryNonce = "recovery.nonce.1";

        private sealed class FakePanel : ILootPanelPort
        {
            public string ActiveName;
            public string ActiveInstance;
            public string ReservedInstance;
            public Func<bool> ExecutionGate;
            public Action<PanelHostController.TrackedOpenOutcome> OpenCompleted;
            public int CloseCalls;

            public bool IsAvailable { get { return true; } }
            public bool IsIdleForTrackedOpen { get { return ActiveName == null && _idleFenceToken == null; } }
            public string ActivePanelName { get { return ActiveName; } }
            public string ActivePanelInstanceId { get { return ActiveInstance; } }
            private string _idleFenceToken;

            public bool TryAcquireIdleFence(string token)
            {
                if (ActiveName != null || _idleFenceToken != null) return false;
                _idleFenceToken = token;
                return true;
            }

            public bool ReleaseIdleFenceExact(string token)
            {
                if (_idleFenceToken != token) return false;
                _idleFenceToken = null;
                return true;
            }

            public bool TryOpenTracked(string initDataJson, string panelInstanceId,
                Func<bool> executionGate, Action<PanelHostController.TrackedOpenOutcome> completed)
            {
                ReservedInstance = panelInstanceId;
                ExecutionGate = executionGate;
                OpenCompleted = completed;
                return true;
            }

            public bool TryCloseExact(string panelInstanceId, Action<bool> completed)
            {
                Assert.Equal(ReservedInstance, panelInstanceId);
                CloseCalls++;
                return true;
            }

            public void CompleteOpenPosted()
            {
                Assert.True(ExecutionGate());
                ActiveName = "loot";
                ActiveInstance = ReservedInstance;
                OpenCompleted(PanelHostController.TrackedOpenOutcome.OpenPosted);
            }
        }

        private sealed class Harness : IDisposable
        {
            private readonly object _postedSync = new object();
            private readonly List<JObject> _posted = new List<JObject>();

            public readonly FakePanel Panel = new FakePanel();
            public readonly LootPanelCoordinator Coordinator;
            public readonly LootTask Task;
            public readonly List<JObject> Sent = new List<JObject>();
            public readonly List<int> SentGenerations = new List<int>();
            public volatile bool SendResult = true;
            public volatile bool Ready = true;
            public volatile int Generation = 1;
            public int DetachedReconcileSettled;
            public int PauseReleaseCalls;

            public Harness(int timeoutMs = 10000, int retryInitialMs = 100,
                int retryMaximumMs = 2000,
                Func<LootPanelCoordinator.Binding, string, bool> requestRecovery = null,
                bool stageSettlement = false)
            {
                Coordinator = new LootPanelCoordinator(Panel, delegate
                    {
                        Interlocked.Increment(ref PauseReleaseCalls);
                        return true;
                    },
                    delegate { return PanelInstanceId; }, requestRecovery);
                Task = new LootTask(delegate { return Ready; },
                    delegate(string payload) { return RecordSend(payload, 0); },
                    Coordinator, timeoutMs,
                    delegate { return Ready ? Generation : 0; },
                    delegate(string payload, int generation)
                    {
                        return Ready && generation == Generation
                            && RecordSend(payload, generation);
                    }, retryInitialMs, retryMaximumMs);
                Coordinator.SetAdmissionLeaseFactory(Task.TryAcquirePanelAdmissionLease);
                Task.SetPostToWeb(delegate(string json)
                {
                    lock (_postedSync) _posted.Add(JObject.Parse(json));
                });
                Task.SetDetachedReconcileSettled(delegate
                {
                    Interlocked.Increment(ref DetachedReconcileSettled);
                });

                JObject ack = JObject.Parse(Coordinator.HandlePanelRequest(
                    stageSettlement ? SettlementPanelRequest() : PanelRequest()));
                Assert.True(ack.Value<bool>("accepted"));
                Assert.False(ack.Value<bool>("bound"));
                Panel.CompleteOpenPosted();
            }

            public int PostedCount { get { lock (_postedSync) return _posted.Count; } }
            public int SentCount { get { lock (Sent) return Sent.Count; } }

            public JObject SentAt(int index)
            {
                lock (Sent) return (JObject)Sent[index].DeepClone();
            }

            public int SentGenerationAt(int index)
            {
                lock (Sent) return SentGenerations[index];
            }

            public JObject PostedAt(int index)
            {
                lock (_postedSync) return (JObject)_posted[index].DeepClone();
            }

            public void Dispose()
            {
                Task.Dispose();
                Coordinator.Dispose();
            }

            private bool RecordSend(string payload, int generation)
            {
                lock (Sent)
                {
                    Sent.Add(JObject.Parse(payload.TrimEnd('\0')));
                    SentGenerations.Add(generation);
                }
                return SendResult;
            }
        }

        private static JObject PanelRequest(string chestSessionId = ChestSessionId,
            string lootContainerId = LootContainerId, int containerEpoch = ContainerEpoch,
            int openAttemptSeq = 1)
        {
            return new JObject
            {
                ["panel"] = "loot",
                ["source"] = "map_chest",
                ["initData"] = new JObject
                {
                    ["v"] = 1,
                    ["chestSessionId"] = chestSessionId,
                    ["lootContainerId"] = lootContainerId,
                    ["containerEpoch"] = containerEpoch,
                    ["openAttemptSeq"] = openAttemptSeq,
                    ["displayName"] = "装备箱",
                    ["capacity"] = 2,
                    ["columns"] = 2
                }
            };
        }

        private static JObject SettlementPanelRequest()
        {
            JObject request = PanelRequest();
            request["source"] = LootPanelCoordinator.StageSettlementSource;
            JObject init = (JObject)request["initData"];
            init["sourceKind"] = LootPanelCoordinator.StageSettlementSource;
            init["displayName"] = "Stage rewards";
            init["report"] = new JObject
            {
                ["v"] = 1,
                ["runId"] = "run.stage.1",
                ["stageName"] = "Test stage",
                ["difficulty"] = "challenge",
                ["outcome"] = "victory",
                ["activeFrames"] = 5432,
                ["totalKills"] = 4,
                ["omittedKillTypes"] = 0,
                ["totalItemGains"] = 0,
                ["totalItemLosses"] = 0,
                ["omittedItemFlowTypes"] = 0,
                ["rewardRollOmissions"] = 0,
                ["kills"] = new JArray
                {
                    new JObject
                    {
                        ["key"] = "enemy.infected",
                        ["displayName"] = "Infected",
                        ["iconName"] = "enemy.infected",
                        ["doll"] = JValue.CreateNull(),
                        ["eliteLevel"] = 0,
                        ["count"] = 4
                    }
                },
                ["itemFlows"] = new JArray()
            };
            return request;
        }

        [Fact]
        public void DefaultPanelInstanceFactoryUsesFreshCspRngOpaqueIds()
        {
            var seen = new HashSet<string>(
                StringComparer.Ordinal);

            for (int index = 0; index < 128; index++)
            {
                var panel = new FakePanel();
                using var coordinator =
                    new LootPanelCoordinator(
                        panel,
                        delegate { return true; });

                JObject ack = JObject.Parse(
                    coordinator.HandlePanelRequest(
                        PanelRequest()));

                Assert.True(
                    ack.Value<bool>("accepted"));
                Assert.Matches(
                    "^panelloot_[A-Za-z0-9_-]{24}$",
                    panel.ReservedInstance);
                Assert.True(
                    seen.Add(panel.ReservedInstance));
            }
        }

        private static JObject Request(string cmd, string callId,
            string chestSessionId = ChestSessionId,
            string lootContainerId = LootContainerId, int containerEpoch = ContainerEpoch,
            string operationId = null)
        {
            JObject request = new JObject
            {
                ["type"] = "task",
                ["task"] = "loot_request",
                ["domain"] = "loot",
                ["panel"] = "loot",
                ["v"] = 1,
                ["cmd"] = cmd,
                ["callId"] = callId,
                ["panelInstanceId"] = PanelInstanceId,
                ["chestSessionId"] = chestSessionId,
                ["lootContainerId"] = lootContainerId,
                ["containerEpoch"] = containerEpoch
            };
            if (cmd == "snapshot")
            {
                request["loot"] = new JObject { ["offset"] = 0, ["limit"] = 2 };
                request["backpack"] = new JObject { ["offset"] = 0, ["limit"] = 2 };
            }
            else if (cmd == "tooltip" || cmd == "claim")
            {
                request["expectedAuthorityRevision"] = 0;
                request["source"] = SourceRef(lootContainerId);
                if (cmd == "claim")
                {
                    request["operationId"] = operationId ?? "operation.claim.1";
                    request["direction"] = "loot_to_player";
                    request["targetContainerId"] = "背包";
                }
            }
            else if (cmd == "claimBatch")
            {
                request["expectedAuthorityRevision"] = 0;
                request["operationId"] = operationId ?? "operation.claim.batch.1";
                request["direction"] = "loot_to_player";
                request["sources"] = new JArray(SourceRef(lootContainerId));
                request["targetContainerId"] = "背包";
            }
            else if (cmd == "materials")
            {
                request["expectedAuthorityRevision"] = 0;
            }
            else if (cmd == "close")
            {
                request["expectedAuthorityRevision"] = 0;
                request["operationId"] = operationId ?? "operation.close.1";
                request["closeLease"] = "close.lease.1";
                request["abandon"] = false;
            }
            return request;
        }

        private static JObject SourceRef(string lootContainerId = LootContainerId)
        {
            return new JObject
            {
                ["containerId"] = lootContainerId,
                ["slot"] = 0,
                ["expectedLease"] = "slot.lease.1",
                ["expectedContainerVersion"] = 1
            };
        }

        private static JObject BatchSourceRef(int slot, string lease,
            int expectedContainerVersion = 1)
        {
            return new JObject
            {
                ["containerId"] = LootContainerId,
                ["slot"] = slot,
                ["expectedLease"] = lease,
                ["expectedContainerVersion"] = expectedContainerVersion
            };
        }

        private static JObject Snapshot(string containerId, int capacity, int limit, int epoch)
        {
            JArray slots = new JArray();
            for (int i = 0; i < limit; i++)
            {
                slots.Add(new JObject
                {
                    ["physicalSlot"] = i,
                    ["occupied"] = false,
                    ["slotLease"] = "slot." + containerId.GetHashCode().ToString("x") + "." + i
                });
            }
            return new JObject
            {
                ["containerId"] = containerId,
                ["capacity"] = capacity,
                ["accessibleCapacity"] = capacity,
                ["viewCapacity"] = capacity,
                ["filterKey"] = "all",
                ["pageSizeHint"] = Math.Max(1, limit),
                ["locked"] = false,
                ["snapshotSeq"] = 1,
                ["containerEpoch"] = epoch,
                ["containerVersion"] = 1,
                ["offset"] = 0,
                ["limit"] = limit,
                ["slots"] = slots,
                ["filterFacets"] = new JArray(),
                ["filterItemCount"] = 0,
                ["setFacets"] = new JArray(),
                ["setFilterItemCount"] = 0
            };
        }

        private static JObject ItemProjection()
        {
            return new JObject
            {
                ["name"] = "强化石",
                ["displayName"] = "强化石",
                ["icon"] = "强化石",
                ["majorType"] = "材料",
                ["use"] = "材料",
                ["actionType"] = "",
                ["weaponType"] = "",
                ["setId"] = "",
                ["setName"] = "",
                ["setOrder"] = 0,
                ["itemKind"] = "stack",
                ["quantity"] = 3000000000L,
                ["enhancementLevel"] = 0,
                ["maxEnhancementLevel"] = 15,
                ["isMaxEnhancement"] = false,
                ["tierSlotAvailable"] = false,
                ["tierSlotUsed"] = false,
                ["modSlotCapacity"] = 0,
                ["modSlotUsed"] = 0,
                ["modSlots"] = new JArray(),
                ["modMeta"] = JValue.CreateNull(),
                ["rarity"] = "普通"
            };
        }

        private static JObject ConfirmProjection()
        {
            return new JObject
            {
                ["itemKind"] = "stack",
                ["name"] = "强化石",
                ["displayName"] = "强化石",
                ["quantity"] = 3000000000L,
                ["enhancementLevel"] = 0,
                ["rarity"] = "普通",
                ["tier"] = "",
                ["modSignature"] = "",
                ["lastUpdate"] = 1700000000000L
            };
        }

        private static JObject ActiveResponse(JObject flash, string lastApplied = "",
            int revision = 1)
        {
            return new JObject
            {
                ["task"] = "loot_response",
                ["callId"] = flash.Value<int>("callId"),
                ["success"] = true,
                ["error"] = "",
                ["chestSessionId"] = ChestSessionId,
                ["lootContainerId"] = LootContainerId,
                ["containerEpoch"] = ContainerEpoch,
                ["authorityRevision"] = revision,
                ["lastAppliedOperationId"] = lastApplied,
                ["state"] = "LOOT_ACTIVE",
                ["remainingCount"] = 0,
                ["closeLease"] = "close.lease." + revision,
                ["snapshots"] = new JArray
                {
                    Snapshot(LootContainerId, 2, 2, ContainerEpoch),
                    Snapshot("背包", 4, 2, 1)
                },
                ["tooltip"] = JValue.CreateNull(),
                ["materials"] = JValue.CreateNull(),
                ["terminal"] = JValue.CreateNull()
            };
        }

        private static JObject ErrorResponse(JObject flash, string error = "stale_state")
        {
            return new JObject
            {
                ["task"] = "loot_response",
                ["callId"] = flash.Value<int>("callId"),
                ["success"] = false,
                ["error"] = error,
                ["chestSessionId"] = ChestSessionId,
                ["lootContainerId"] = LootContainerId,
                ["containerEpoch"] = ContainerEpoch,
                ["authorityRevision"] = 0,
                ["lastAppliedOperationId"] = "",
                ["state"] = "LOOT_ACTIVE",
                ["remainingCount"] = 0,
                ["closeLease"] = "",
                ["snapshots"] = new JArray(),
                ["tooltip"] = JValue.CreateNull(),
                ["materials"] = JValue.CreateNull(),
                ["terminal"] = JValue.CreateNull()
            };
        }

        private static JObject MaterialsResponse(JObject flash, int revision = 1)
        {
            JObject response = ActiveResponse(flash, "", revision);
            response["snapshots"] = new JArray();
            response["materials"] = new JArray
            {
                new JObject
                {
                    ["name"] = "material.iron",
                    ["displayName"] = "Iron",
                    ["icon"] = "material.iron",
                    ["owned"] = 3000000000L
                },
                new JObject
                {
                    ["name"] = "material.fiber",
                    ["displayName"] = "Fiber",
                    ["icon"] = "material.fiber",
                    ["owned"] = 0
                }
            };
            return response;
        }

        private static JObject CommitPendingResponse(JObject flash, int revision = 1)
        {
            JObject response = ErrorResponse(flash, "commit_pending");
            response["authorityRevision"] = revision;
            response["state"] = "LOOT_COMMIT_PENDING";
            return response;
        }

        private static JObject TerminalResponse(JObject flash, string operationId,
            string state = "CONSUMED", int revision = 1, int remaining = 0)
        {
            return new JObject
            {
                ["task"] = "loot_response",
                ["callId"] = flash.Value<int>("callId"),
                ["success"] = true,
                ["error"] = "",
                ["chestSessionId"] = ChestSessionId,
                ["lootContainerId"] = LootContainerId,
                ["containerEpoch"] = ContainerEpoch,
                ["authorityRevision"] = revision,
                ["lastAppliedOperationId"] = operationId,
                ["state"] = state,
                ["remainingCount"] = remaining,
                ["closeLease"] = "",
                ["snapshots"] = new JArray(),
                ["tooltip"] = JValue.CreateNull(),
                ["materials"] = JValue.CreateNull(),
                ["terminal"] = new JObject
                {
                    ["kind"] = state,
                    ["reason"] = "player_closed",
                    ["remainingCount"] = remaining
                }
            };
        }

        private static JObject SuspendedResponse(JObject flash, string operationId,
            int revision = 1, int remaining = 1)
        {
            return new JObject
            {
                ["task"] = "loot_response",
                ["callId"] = flash.Value<int>("callId"),
                ["success"] = true,
                ["error"] = "",
                ["chestSessionId"] = ChestSessionId,
                ["lootContainerId"] = LootContainerId,
                ["containerEpoch"] = ContainerEpoch,
                ["authorityRevision"] = revision,
                ["lastAppliedOperationId"] = operationId,
                ["state"] = "LOOT_SUSPENDED",
                ["remainingCount"] = remaining,
                ["closeLease"] = "",
                ["snapshots"] = new JArray(),
                ["tooltip"] = JValue.CreateNull(),
                ["materials"] = JValue.CreateNull(),
                ["terminal"] = JValue.CreateNull()
            };
        }

        private static JObject ActiveResponseWithLoot(JObject flash, int revision = 1)
        {
            JObject response = ActiveResponse(flash, "", revision);
            response["remainingCount"] = 1;
            JObject loot = (JObject)response["snapshots"][0];
            loot["filterItemCount"] = 1;
            ((JArray)loot["slots"])[0] = new JObject
            {
                ["physicalSlot"] = 0,
                ["occupied"] = true,
                ["slotLease"] = "loot.slot." + revision,
                ["item"] = ItemProjection()
            };
            return response;
        }

        private static JObject ActiveResponseWithTwoLoot(JObject flash, int revision = 1)
        {
            JObject response = ActiveResponseWithLoot(flash, revision);
            response["remainingCount"] = 2;
            JObject loot = (JObject)response["snapshots"][0];
            loot["filterItemCount"] = 2;
            ((JArray)loot["slots"])[1] = new JObject
            {
                ["physicalSlot"] = 1,
                ["occupied"] = true,
                ["slotLease"] = "loot.slot.second." + revision,
                ["item"] = ItemProjection()
            };
            return response;
        }

        private static JObject ActiveBatchResponse(JObject flash, string operationId,
            int revision, bool firstApplied, bool secondApplied)
        {
            JObject response = ActiveResponse(flash, operationId, revision);
            JObject loot = (JObject)response["snapshots"][0];
            JArray slots = (JArray)loot["slots"];
            int remaining = 0;
            if (!firstApplied)
            {
                remaining++;
                slots[0] = new JObject
                {
                    ["physicalSlot"] = 0,
                    ["occupied"] = true,
                    ["slotLease"] = "loot.slot.1",
                    ["item"] = ItemProjection()
                };
            }
            if (!secondApplied)
            {
                remaining++;
                slots[1] = new JObject
                {
                    ["physicalSlot"] = 1,
                    ["occupied"] = true,
                    ["slotLease"] = "loot.slot.second.1",
                    ["item"] = ItemProjection()
                };
            }
            response["remainingCount"] = remaining;
            loot["filterItemCount"] = remaining;
            loot["containerVersion"] = revision;
            return response;
        }

        private static void PrimeActiveAuthority(Harness harness, bool hasLoot)
        {
            harness.Task.HandleWebRequest(Request("snapshot",
                hasLoot ? "snapshot.prime.nonempty" : "snapshot.prime.empty"));
            JObject snapshot = Assert.Single(harness.Sent);
            harness.Task.HandleFlashResponse(hasLoot
                ? ActiveResponseWithLoot(snapshot, 1)
                : ActiveResponse(snapshot, "", 1), null);
            Assert.True(harness.PostedAt(0).Value<bool>("success"));
            Assert.Equal("LOOT_ACTIVE", harness.PostedAt(0).Value<string>("state"));
        }

        private static void PrimeActiveAuthorityWithTwoLoot(Harness harness)
        {
            harness.Task.HandleWebRequest(Request("snapshot", "snapshot.prime.two"));
            JObject snapshot = Assert.Single(harness.Sent);
            harness.Task.HandleFlashResponse(ActiveResponseWithTwoLoot(snapshot, 1), null);
            Assert.True(harness.PostedAt(0).Value<bool>("success"));
            Assert.Equal(2, harness.PostedAt(0).Value<int>("remainingCount"));
        }

        private static void AssertExactKeys(JObject value, params string[] expected)
        {
            Assert.Equal(expected.OrderBy(x => x), value.Properties().Select(x => x.Name).OrderBy(x => x));
        }

        private static void AssertExactResponseWrapper(JObject value)
        {
            AssertExactKeys(value,
                "type", "task", "domain", "panel", "cmd", "callId", "panelInstanceId",
                "success", "error", "chestSessionId", "lootContainerId", "containerEpoch",
                "authorityRevision", "lastAppliedOperationId", "state", "remainingCount",
                "closeLease", "snapshots", "tooltip", "materials", "terminal");
            Assert.Equal("panel_resp", value.Value<string>("type"));
            Assert.Equal("loot_response", value.Value<string>("task"));
            Assert.Equal(PanelInstanceId, value.Value<string>("panelInstanceId"));
            Assert.Equal(ChestSessionId, value.Value<string>("chestSessionId"));
            Assert.Equal(LootContainerId, value.Value<string>("lootContainerId"));
            Assert.Equal(ContainerEpoch, value.Value<int>("containerEpoch"));
        }

        private static void DetachSocketLoot(Harness harness)
        {
            harness.Task.OnSocketTransportDetached(harness.Generation);
            Assert.True(harness.Coordinator.ForceDetach("socket_disconnected"));
            harness.Panel.ActiveName = null;
            harness.Panel.ActiveInstance = null;
            harness.Coordinator.OnPanelHostClosed("loot", PanelInstanceId);
            Assert.True(harness.Task.RequiresDetachedReconcile);
        }

        private static JObject WaitForSent(Harness harness, int count)
        {
            Assert.True(SpinWait.SpinUntil(delegate { return harness.SentCount >= count; },
                2000), "timed out waiting for detached reconcile query " + count);
            return harness.SentAt(count - 1);
        }

        private static void AssertDetachedQuery(JObject query, int generation,
            Harness harness, string expectedNonce = null, int expectedAttempt = 1)
        {
            AssertExactKeys(query, "task", "action", "callId", "v", "chestSessionId",
                "lootContainerId", "containerEpoch", "openAttemptSeq", "recoveryNonce");
            Assert.Equal("lootQuery", query.Value<string>("action"));
            Assert.Equal(ChestSessionId, query.Value<string>("chestSessionId"));
            Assert.Equal(LootContainerId, query.Value<string>("lootContainerId"));
            Assert.Equal(ContainerEpoch, query.Value<int>("containerEpoch"));
            Assert.Equal(expectedAttempt, query.Value<int>("openAttemptSeq"));
            Assert.True(LootPanelCoordinator.IsOpaque(
                query.Value<string>("recoveryNonce")));
            if (expectedNonce != null)
                Assert.Equal(expectedNonce, query.Value<string>("recoveryNonce"));
            Assert.Equal(generation, harness.SentGenerationAt(harness.SentCount - 1));
        }

        [Theory]
        [InlineData("terminal")]
        [InlineData("suspended")]
        [InlineData("invalid_init")]
        [InlineData("mount_failed")]
        [InlineData("lazy_load_failed")]
        [InlineData("lazy_register_failed")]
        [InlineData("lazy_register_missing")]
        public void LootVisualClose_RequiresExactCurrentFiveKeyEnvelope(string closeReason)
        {
            JObject envelope = new JObject
            {
                ["type"] = "panel",
                ["panel"] = "loot",
                ["cmd"] = "close",
                ["reason"] = closeReason,
                ["panelInstanceId"] = PanelInstanceId
            };

            string normalizedReason;
            Assert.True(WebOverlayForm.IsValidLootVisualCloseEnvelope(envelope, "loot",
                PanelInstanceId, out normalizedReason));
            Assert.Equal(closeReason, normalizedReason);

            string schemaReason;
            string schemaInstance;
            Assert.True(WebOverlayForm.TryNormalizeLootVisualCloseEnvelope(envelope,
                out schemaReason, out schemaInstance));
            Assert.Equal(closeReason, schemaReason);
            Assert.Equal(PanelInstanceId, schemaInstance);
            Assert.False(WebOverlayForm.IsValidLootVisualCloseEnvelope(envelope, null,
                null, out normalizedReason));

            envelope["extra"] = true;
            Assert.False(WebOverlayForm.TryNormalizeLootVisualCloseEnvelope(envelope,
                out schemaReason, out schemaInstance));
            Assert.False(WebOverlayForm.IsValidLootVisualCloseEnvelope(envelope, "loot",
                PanelInstanceId, out normalizedReason));
            envelope.Remove("extra");
            envelope.Remove("panelInstanceId");
            Assert.False(WebOverlayForm.IsValidLootVisualCloseEnvelope(envelope, "loot",
                PanelInstanceId, out normalizedReason));
        }

        [Theory]
        [InlineData("panel_registry_missing")]
        [InlineData("required_asset_panel_missing")]
        [InlineData("lazy_user_cancel")]
        [InlineData("lazy_cancel")]
        public void LootVisualClose_RejectsDriftedMissingPanelReasons(string closeReason)
        {
            JObject envelope = new JObject
            {
                ["type"] = "panel",
                ["panel"] = "loot",
                ["cmd"] = "close",
                ["reason"] = closeReason,
                ["panelInstanceId"] = PanelInstanceId
            };

            string normalizedReason;
            Assert.False(WebOverlayForm.IsValidLootVisualCloseEnvelope(envelope, "loot",
                PanelInstanceId, out normalizedReason));
        }

        [Theory]
        [InlineData("snapshot", "lootSnapshot")]
        [InlineData("tooltip", "lootTooltip")]
        [InlineData("claim", "lootClaim")]
        [InlineData("claimBatch", "lootClaimBatch")]
        [InlineData("close", "lootClose")]
        [InlineData("query", "lootQuery")]
        public void ExactWebCommands_MapToExactFlashActions(string cmd, string action)
        {
            using var harness = new Harness();

            JObject request = Request(cmd, "web." + cmd + ".1");
            bool primedWrite = cmd == "claim" || cmd == "claimBatch" || cmd == "close";
            if (primedWrite)
            {
                PrimeActiveAuthority(harness, cmd == "claim" || cmd == "claimBatch");
                request["expectedAuthorityRevision"] = 1;
                if (cmd == "claim")
                    request["source"]["expectedLease"] = "loot.slot.1";
                else if (cmd == "claimBatch")
                    request["sources"][0]["expectedLease"] = "loot.slot.1";
            }
            harness.Task.HandleWebRequest(request);

            JObject sent = primedWrite ? harness.Sent[1] : Assert.Single(harness.Sent);
            Assert.Equal("cmd", sent.Value<string>("task"));
            Assert.Equal(action, sent.Value<string>("action"));
            Assert.True(sent.Value<int>("callId") > 0);
            Assert.Null(sent["panelInstanceId"]);
            Assert.Null(sent["domain"]);
            Assert.Null(sent["panel"]);
            Assert.Null(sent["cmd"]);
            if (cmd == "snapshot")
                AssertExactKeys(sent, "task", "action", "callId", "v", "chestSessionId",
                    "lootContainerId", "containerEpoch", "loot", "backpack");
            else if (cmd == "tooltip")
                AssertExactKeys(sent, "task", "action", "callId", "v", "chestSessionId",
                    "lootContainerId", "containerEpoch", "expectedAuthorityRevision", "source");
            else if (cmd == "claim")
                AssertExactKeys(sent, "task", "action", "callId", "v", "chestSessionId",
                    "lootContainerId", "containerEpoch", "expectedAuthorityRevision", "source",
                    "operationId", "direction", "targetContainerId");
            else if (cmd == "claimBatch")
                AssertExactKeys(sent, "task", "action", "callId", "v", "chestSessionId",
                    "lootContainerId", "containerEpoch", "expectedAuthorityRevision", "sources",
                    "operationId", "direction", "targetContainerId");
            else if (cmd == "close")
                AssertExactKeys(sent, "task", "action", "callId", "v", "chestSessionId",
                    "lootContainerId", "containerEpoch", "expectedAuthorityRevision",
                    "operationId", "closeLease", "abandon");
            else
                AssertExactKeys(sent, "task", "action", "callId", "v", "chestSessionId",
                    "lootContainerId", "containerEpoch");
        }

        [Fact]
        public void Materials_IsRejectedForMapChestWithoutSendingToFlash()
        {
            using var harness = new Harness();

            harness.Task.HandleWebRequest(Request("materials", "materials.map.1"));

            Assert.Empty(harness.Sent);
            JObject posted = harness.PostedAt(0);
            AssertExactResponseWrapper(posted);
            Assert.False(posted.Value<bool>("success"));
            Assert.Equal("invalid_payload", posted.Value<string>("error"));
            Assert.Equal("materials", posted.Value<string>("cmd"));
        }

        [Fact]
        public void StageSettlementMaterials_MapsAndForwardsOnlyExactMaterialProjection()
        {
            using var harness = new Harness(stageSettlement: true);

            harness.Task.HandleWebRequest(Request("materials", "materials.stage.1"));

            JObject sent = Assert.Single(harness.Sent);
            Assert.Equal("lootMaterials", sent.Value<string>("action"));
            Assert.Equal(0, sent.Value<int>("expectedAuthorityRevision"));
            AssertExactKeys(sent, "task", "action", "callId", "v", "chestSessionId",
                "lootContainerId", "containerEpoch", "expectedAuthorityRevision");

            harness.Task.HandleFlashResponse(MaterialsResponse(sent), null);

            JObject posted = harness.PostedAt(0);
            AssertExactResponseWrapper(posted);
            Assert.True(posted.Value<bool>("success"));
            Assert.Equal("materials", posted.Value<string>("cmd"));
            JArray materials = Assert.IsType<JArray>(posted["materials"]);
            Assert.Equal(2, materials.Count);
            AssertExactKeys((JObject)materials[0], "name", "displayName", "icon", "owned");
            Assert.Equal(3000000000L, materials[0].Value<long>("owned"));
            Assert.Empty((JArray)posted["snapshots"]);
            Assert.Equal(JTokenType.Null, posted["tooltip"].Type);
        }

        [Fact]
        public void StageSettlementMaterials_RejectsAuthorityShapeDrift()
        {
            using var harness = new Harness(stageSettlement: true);
            harness.Task.HandleWebRequest(Request("materials", "materials.stage.bad"));
            JObject sent = Assert.Single(harness.Sent);
            JObject malformed = MaterialsResponse(sent);
            ((JObject)malformed["materials"][0])["forged"] = true;

            harness.Task.HandleFlashResponse(malformed, null);

            JObject posted = harness.PostedAt(0);
            AssertExactResponseWrapper(posted);
            Assert.False(posted.Value<bool>("success"));
            Assert.Equal("malformed_response", posted.Value<string>("error"));
            Assert.Equal(JTokenType.Null, posted["materials"].Type);
        }

        [Fact]
        public void ClosePreflight_RequiresExactKnownActiveRevisionAndLeaseBeforeSend()
        {
            using var fresh = new Harness();
            fresh.Task.HandleWebRequest(Request("close", "close.preflight.unknown"));
            Assert.Empty(fresh.Sent);
            Assert.Equal("stale_state", fresh.PostedAt(0).Value<string>("error"));

            using var wrongRevision = new Harness();
            PrimeActiveAuthority(wrongRevision, false);
            JObject staleRevision = Request("close", "close.preflight.revision");
            staleRevision["expectedAuthorityRevision"] = 0;
            wrongRevision.Task.HandleWebRequest(staleRevision);
            Assert.Single(wrongRevision.Sent);
            Assert.Equal("stale_state", wrongRevision.PostedAt(1).Value<string>("error"));

            using var wrongLease = new Harness();
            PrimeActiveAuthority(wrongLease, false);
            JObject staleLease = Request("close", "close.preflight.lease");
            staleLease["expectedAuthorityRevision"] = 1;
            staleLease["closeLease"] = "close.lease.stale";
            wrongLease.Task.HandleWebRequest(staleLease);
            Assert.Single(wrongLease.Sent);
            Assert.Equal("stale_state", wrongLease.PostedAt(1).Value<string>("error"));
        }

        [Fact]
        public void ClaimPreflight_RequiresExactKnownActiveRevisionAndContainerVersion()
        {
            using var blind = new Harness();
            blind.Task.HandleWebRequest(Request("claim", "claim.preflight.unknown"));
            Assert.Empty(blind.Sent);
            Assert.Equal("stale_state", blind.PostedAt(0).Value<string>("error"));
            Assert.Equal("idle", blind.Task.WriteState);

            using var staleRevision = new Harness();
            PrimeActiveAuthority(staleRevision, true);
            staleRevision.Task.HandleWebRequest(Request("claim",
                "claim.preflight.revision"));
            Assert.Equal(1, staleRevision.SentCount);
            Assert.Equal("stale_state",
                staleRevision.PostedAt(1).Value<string>("error"));
            Assert.Equal("idle", staleRevision.Task.WriteState);

            using var staleVersion = new Harness();
            PrimeActiveAuthority(staleVersion, true);
            JObject wrongVersion = Request("claim", "claim.preflight.version");
            wrongVersion["expectedAuthorityRevision"] = 1;
            wrongVersion["source"]["expectedLease"] = "loot.slot.1";
            wrongVersion["source"]["expectedContainerVersion"] = 2;
            staleVersion.Task.HandleWebRequest(wrongVersion);
            Assert.Equal(1, staleVersion.SentCount);
            Assert.Equal("stale_state", staleVersion.PostedAt(1).Value<string>("error"));
            Assert.Equal("idle", staleVersion.Task.WriteState);
        }

        [Fact]
        public void FreshOpenAttemptOfSameTriple_HasIndependentAuthorityRevisionScope()
        {
            using var harness = new Harness();
            harness.Task.HandleWebRequest(Request("snapshot", "snapshot.attempt.1"));
            harness.Task.HandleFlashResponse(ActiveResponse(Assert.Single(harness.Sent),
                "", 5), null);
            Assert.Equal(5, harness.Task.LastAuthorityRevision);

            JObject close = Request("close", "close.attempt.1");
            close["expectedAuthorityRevision"] = 5;
            close["closeLease"] = "close.lease.5";
            harness.Task.HandleWebRequest(close);
            harness.Task.HandleFlashResponse(TerminalResponse(harness.Sent[1],
                close.Value<string>("operationId"), "CONSUMED", 6, 0), null);
            Assert.Equal(LootPanelCoordinator.BindingState.TerminalCloseQueued,
                harness.Coordinator.State);

            harness.Panel.ActiveName = null;
            harness.Panel.ActiveInstance = null;
            harness.Coordinator.OnPanelHostClosed("loot", PanelInstanceId);
            Assert.Equal(LootPanelCoordinator.BindingState.Idle,
                harness.Coordinator.State);

            JObject ack = JObject.Parse(harness.Coordinator.HandlePanelRequest(
                PanelRequest(openAttemptSeq: 2)));
            Assert.True(ack.Value<bool>("accepted"));
            Assert.Equal(2, harness.Coordinator.ActiveBinding.OpenAttemptSeq);
            harness.Panel.CompleteOpenPosted();
            harness.Task.HandleWebRequest(Request("snapshot", "snapshot.attempt.2"));
            JObject freshSnapshot = harness.Sent[2];
            harness.Task.HandleFlashResponse(ActiveResponse(freshSnapshot, "", 1), null);

            Assert.True(harness.PostedAt(2).Value<bool>("success"));
            Assert.Equal("LOOT_ACTIVE", harness.PostedAt(2).Value<string>("state"));
            Assert.Equal(1, harness.Task.LastAuthorityRevision);
        }

        [Fact]
        public void FreshAttemptMountFailure_ActivatesScopeBeforeWebAndAcceptsRevisionOneOnly()
        {
            const string freshNonce = "recovery.nonce.attempt.2";
            using var harness = new Harness(retryInitialMs: 10, retryMaximumMs: 20);
            harness.Task.HandleWebRequest(Request("snapshot", "snapshot.attempt.old.prime"));
            harness.Task.HandleFlashResponse(ActiveResponse(Assert.Single(harness.Sent),
                "", 5), null);
            harness.Task.HandleWebRequest(Request("snapshot", "snapshot.attempt.old.late"));
            JObject lateOldSnapshot = harness.Sent[1];

            JObject close = Request("close", "close.attempt.old");
            close["expectedAuthorityRevision"] = 5;
            close["closeLease"] = "close.lease.5";
            harness.Task.HandleWebRequest(close);
            harness.Task.HandleFlashResponse(TerminalResponse(harness.Sent[2],
                close.Value<string>("operationId"), "CONSUMED", 6, 0), null);
            harness.Panel.ActiveName = null;
            harness.Panel.ActiveInstance = null;
            harness.Coordinator.OnPanelHostClosed("loot", PanelInstanceId);

            JObject ack = JObject.Parse(harness.Coordinator.HandlePanelRequest(
                PanelRequest(openAttemptSeq: 2)));
            Assert.True(ack.Value<bool>("accepted"));
            harness.Panel.CompleteOpenPosted();
            LootPanelCoordinator.Binding freshBinding = harness.Coordinator.ActiveBinding;
            Assert.True(harness.Task.PrepareConnectedTransportDetach(freshBinding,
                freshNonce));
            Assert.Equal(0, harness.Task.LastAuthorityRevision);

            // A late attempt-1 response was removed with the old scope and cannot restore rev 6.
            harness.Task.HandleFlashResponse(ActiveResponse(lateOldSnapshot, "", 6), null);
            Assert.Equal(0, harness.Task.LastAuthorityRevision);
            Assert.True(harness.Coordinator.ForceDetach("web_mount_failed"));
            harness.Task.OnConnectedTransportRecoverySent(freshBinding, 1, freshNonce);
            JObject zeroRevisionQuery = WaitForSent(harness, 4);
            AssertDetachedQuery(zeroRevisionQuery, 1, harness, freshNonce, 2);

            harness.Task.HandleFlashResponse(ActiveResponse(zeroRevisionQuery, "", 0), null);
            Assert.True(harness.Task.RequiresDetachedReconcile);
            Assert.Equal(0, harness.Task.LastAuthorityRevision);
            JObject revisionOneQuery = WaitForSent(harness, 5);
            AssertDetachedQuery(revisionOneQuery, 1, harness, freshNonce, 2);
            harness.Task.HandleFlashResponse(SuspendedResponse(revisionOneQuery,
                "operation.recovery.suspended", 1, 1), null);

            Assert.False(harness.Task.RequiresDetachedReconcile);
            Assert.Equal(1, harness.Task.LastAuthorityRevision);
            Assert.Equal(1, harness.DetachedReconcileSettled);
        }

        [Fact]
        public void OldUnknown_BlocksFreshAdmissionUntilResolved_ThenFreshDetachIsProven()
        {
            using var harness = new Harness();
            PrimeActiveAuthority(harness, true);
            harness.SendResult = false;
            JObject oldClaim = Request("claim", "claim.attempt.old.unknown");
            oldClaim["expectedAuthorityRevision"] = 1;
            oldClaim["source"]["expectedLease"] = "loot.slot.1";
            harness.Task.HandleWebRequest(oldClaim);
            Assert.Equal("reconcile_required", harness.Task.WriteState);
            Assert.Equal("operation.claim.1", harness.Task.UnknownOperationId);
            var foreignAttempt = new LootPanelCoordinator.Binding(
                new LootPanelCoordinator.OpenRequest
                {
                    ChestSessionId = ChestSessionId,
                    LootContainerId = LootContainerId,
                    ContainerEpoch = ContainerEpoch,
                    OpenAttemptSeq = 2,
                    DisplayName = "装备箱",
                    Capacity = 2,
                    Columns = 2
                }, "panel.loot.foreign.2");
            Assert.False(harness.Task.PrepareConnectedTransportDetach(foreignAttempt,
                "recovery.nonce.foreign.2"));
            Assert.Equal("operation.claim.1", harness.Task.UnknownOperationId);
            Assert.True(harness.Coordinator.ForceDetach("socket_disconnected"));
            harness.Panel.ActiveName = null;
            harness.Panel.ActiveInstance = null;
            harness.Coordinator.OnPanelHostClosed("loot", PanelInstanceId);

            JObject ack = JObject.Parse(harness.Coordinator.HandlePanelRequest(
                PanelRequest(openAttemptSeq: 2)));
            Assert.False(ack.Value<bool>("accepted"));
            Assert.Equal("flow_busy", ack.Value<string>("error"));
            Assert.True(harness.Task.HasRecoveryFence);
            harness.SendResult = true;
            Assert.Equal(2, harness.SentCount);
            Assert.Equal("reconcile_required", harness.Task.WriteState);
            Assert.Equal("operation.claim.1", harness.Task.UnknownOperationId);

            // Reconcile the only detached authority before admitting any fresh visual binding.
            harness.Task.OnSocketTransportDetached(1);
            harness.Generation = 2;
            harness.Task.OnSocketReconnected();
            JObject oldAttemptQuery = WaitForSent(harness, 3);
            AssertDetachedQuery(oldAttemptQuery, 2, harness, expectedAttempt: 1);
            harness.Task.HandleFlashResponse(TerminalResponse(oldAttemptQuery,
                "operation.claim.1", "CONSUMED", 2, 0), null);
            Assert.Equal("idle", harness.Task.WriteState);
            Assert.False(harness.Task.RequiresDetachedReconcile);
            Assert.False(harness.Task.HasRecoveryFence);

            JObject freshAck = JObject.Parse(harness.Coordinator.HandlePanelRequest(
                PanelRequest(openAttemptSeq: 2)));
            Assert.True(freshAck.Value<bool>("accepted"));
            harness.Panel.CompleteOpenPosted();
            Assert.Equal(2, harness.Coordinator.ActiveBinding.OpenAttemptSeq);

            // A later disconnect owns a distinct exact nine-key proof for attempt 2.
            harness.Task.OnSocketTransportDetached(2);
            Assert.True(harness.Coordinator.ForceDetach("socket_disconnected"));
            harness.Panel.ActiveName = null;
            harness.Panel.ActiveInstance = null;
            harness.Coordinator.OnPanelHostClosed("loot", PanelInstanceId);
            harness.Generation = 3;
            harness.Task.OnSocketReconnected();
            JObject freshAttemptQuery = WaitForSent(harness, 4);
            AssertDetachedQuery(freshAttemptQuery, 3, harness, expectedAttempt: 2);
            harness.Task.HandleFlashResponse(SuspendedResponse(freshAttemptQuery,
                "operation.recovery.suspended", 1, 1), null);
            Assert.False(harness.Task.RequiresDetachedReconcile);
            Assert.Equal(2, harness.DetachedReconcileSettled);
        }

        [Fact]
        public void AdmissionLease_OrdersConcurrentSocketFenceAfterFreshBindingReservation()
        {
            using var harness = new Harness();
            Assert.True(harness.Coordinator.ForceDetach("web_navigation"));
            harness.Panel.ActiveName = null;
            harness.Panel.ActiveInstance = null;
            harness.Coordinator.OnPanelHostClosed("loot", PanelInstanceId);
            Assert.Equal(LootPanelCoordinator.BindingState.Idle,
                harness.Coordinator.State);
            Assert.False(harness.Task.HasRecoveryFence);

            using var leaseAcquired = new ManualResetEventSlim(false);
            using var releaseLease = new ManualResetEventSlim(false);
            harness.Coordinator.SetAdmissionLeaseFactory(delegate
            {
                IDisposable lease = harness.Task.TryAcquirePanelAdmissionLease();
                if (lease != null)
                {
                    leaseAcquired.Set();
                    releaseLease.Wait(TimeSpan.FromSeconds(5));
                }
                return lease;
            });

            string ackJson = null;
            Thread openThread = new Thread(new ThreadStart(delegate
            {
                ackJson = harness.Coordinator.HandlePanelRequest(
                    PanelRequest(openAttemptSeq: 2));
            }));
            Thread detachThread = new Thread(new ThreadStart(delegate
            {
                harness.Task.OnSocketTransportDetached(1);
            }));
            openThread.IsBackground = true;
            detachThread.IsBackground = true;
            bool openStarted = false;
            bool detachStarted = false;
            try
            {
                openThread.Start();
                openStarted = true;
                Assert.True(leaseAcquired.Wait(TimeSpan.FromSeconds(2)));
                detachThread.Start();
                detachStarted = true;
                Assert.False(detachThread.Join(100),
                    "socket detach crossed the held Task admission lease");
                releaseLease.Set();
                Assert.True(openThread.Join(2000));
                Assert.True(detachThread.Join(2000));
            }
            finally
            {
                releaseLease.Set();
                if (openStarted) openThread.Join(2000);
                if (detachStarted) detachThread.Join(2000);
            }

            JObject ack = JObject.Parse(ackJson);
            Assert.True(ack.Value<bool>("accepted"));
            Assert.Equal(2, harness.Coordinator.ActiveBinding.OpenAttemptSeq);
            Assert.True(harness.Task.RequiresDetachedReconcile);
            Assert.True(harness.Task.HasRecoveryFence);

            harness.Generation = 2;
            harness.Task.OnSocketReconnected();
            JObject query = WaitForSent(harness, 1);
            AssertDetachedQuery(query, 2, harness, expectedAttempt: 2);
        }

        [Fact]
        public void ExtraOrMissingFields_FailClosed_WithExactSyntheticUnion()
        {
            using var harness = new Harness();
            JObject withTopSource = Request("snapshot", "invalid.1");
            withTopSource["source"] = "map_chest";
            JObject missingVersion = Request("tooltip", "invalid.2");
            ((JObject)missingVersion["source"]).Remove("expectedContainerVersion");
            JObject claimExtra = Request("claim", "invalid.3");
            claimExtra["intentRevision"] = 1;
            JObject queryExtra = Request("query", "invalid.4");
            queryExtra["operationId"] = "operation.claim.1";

            harness.Task.HandleWebRequest(withTopSource);
            harness.Task.HandleWebRequest(missingVersion);
            harness.Task.HandleWebRequest(claimExtra);
            harness.Task.HandleWebRequest(queryExtra);

            Assert.Empty(harness.Sent);
            Assert.Equal(4, harness.PostedCount);
            for (int i = 0; i < 4; i++)
            {
                JObject error = harness.PostedAt(i);
                AssertExactResponseWrapper(error);
                Assert.False(error.Value<bool>("success"));
                Assert.Equal("invalid_payload", error.Value<string>("error"));
                Assert.Equal("LOOT_COMMIT_PENDING", error.Value<string>("state"));
                Assert.Empty((JArray)error["snapshots"]);
            }
        }

        [Fact]
        public void StalePanelInstance_IsSilentlyDroppedWithoutCrossBindingDisclosure()
        {
            using var harness = new Harness();
            JObject request = Request("snapshot", "stale.1");
            request["panelInstanceId"] = "panel.loot.stale";

            harness.Task.HandleWebRequest(request);

            Assert.Empty(harness.Sent);
            Assert.Equal(0, harness.PostedCount);
        }

        [Fact]
        public void StrictAuthorityResponse_IsSanitizedIntoExactWebWrapper()
        {
            using var harness = new Harness();
            harness.Task.HandleWebRequest(Request("snapshot", "snapshot.1"));
            JObject flash = Assert.Single(harness.Sent);

            harness.Task.HandleFlashResponse(ActiveResponse(flash), null);

            JObject posted = harness.PostedAt(0);
            AssertExactResponseWrapper(posted);
            Assert.True(posted.Value<bool>("success"));
            Assert.Equal("snapshot.1", posted.Value<string>("callId"));
            Assert.Equal("snapshot", posted.Value<string>("cmd"));
            Assert.Equal(2, ((JArray)posted["snapshots"]).Count);
            Assert.IsType<string>(posted["callId"].Value<string>());
        }

        [Fact]
        public void InventoryCompatibleProjection_AllowsSafeLongsAndEnforcesDomainSlotKeys()
        {
            using var harness = new Harness();
            harness.Task.HandleWebRequest(Request("snapshot", "snapshot.items.1"));
            JObject response = ActiveResponse(Assert.Single(harness.Sent));
            response["remainingCount"] = 1;
            JObject loot = (JObject)response["snapshots"][0];
            loot["filterItemCount"] = 1;
            ((JArray)loot["slots"])[0] = new JObject
            {
                ["physicalSlot"] = 0,
                ["occupied"] = true,
                ["slotLease"] = "loot.slot.1",
                ["item"] = ItemProjection()
            };
            JObject backpack = (JObject)response["snapshots"][1];
            backpack["filterItemCount"] = 1;
            ((JArray)backpack["slots"])[0] = new JObject
            {
                ["physicalSlot"] = 0,
                ["occupied"] = true,
                ["slotLease"] = "bag.slot.1",
                ["item"] = ItemProjection(),
                ["confirmProjection"] = ConfirmProjection()
            };

            harness.Task.HandleFlashResponse(response, null);

            Assert.True(harness.PostedAt(0).Value<bool>("success"));
            Assert.Equal(3000000000L,
                harness.PostedAt(0)["snapshots"][1]["slots"][0]["item"].Value<long>("quantity"));
            Assert.Equal(1700000000000L,
                harness.PostedAt(0)["snapshots"][1]["slots"][0]["confirmProjection"]
                    .Value<long>("lastUpdate"));

            harness.Task.HandleWebRequest(Request("snapshot", "snapshot.items.2"));
            JObject invalid = ActiveResponse(harness.Sent[1], "", 2);
            invalid["remainingCount"] = 1;
            JObject invalidLoot = (JObject)invalid["snapshots"][0];
            invalidLoot["filterItemCount"] = 1;
            ((JArray)invalidLoot["slots"])[0] = new JObject
            {
                ["physicalSlot"] = 0,
                ["occupied"] = true,
                ["slotLease"] = "loot.slot.2",
                ["item"] = ItemProjection(),
                ["confirmProjection"] = ConfirmProjection()
            };
            harness.Task.HandleFlashResponse(invalid, null);

            Assert.False(harness.PostedAt(1).Value<bool>("success"));
            Assert.Equal("malformed_response", harness.PostedAt(1).Value<string>("error"));
        }

        [Theory]
        [InlineData("item_name_undefined")]
        [InlineData("item_extra_balance_summary")]
        [InlineData("item_display_blank")]
        [InlineData("item_icon_undefined")]
        [InlineData("mod_slot_display_undefined")]
        [InlineData("mod_meta_icon_blank")]
        [InlineData("confirm_missing")]
        [InlineData("confirm_item_kind")]
        [InlineData("confirm_name")]
        [InlineData("confirm_display_name")]
        [InlineData("confirm_quantity")]
        [InlineData("confirm_enhancement")]
        [InlineData("confirm_rarity")]
        public void InventoryProjectionRejectsIdentitySentinelsAndForgedConfirm(
            string corruption)
        {
            using var harness = new Harness();
            harness.Task.HandleWebRequest(Request(
                "snapshot", "snapshot.identity." + corruption));
            JObject response = ActiveResponse(Assert.Single(harness.Sent));
            JObject backpack = (JObject)response["snapshots"][1];
            backpack["filterItemCount"] = 1;
            JObject item = ItemProjection();
            JObject confirm = ConfirmProjection();
            JObject occupied = new JObject
            {
                ["physicalSlot"] = 0,
                ["occupied"] = true,
                ["slotLease"] = "bag.identity.1",
                ["item"] = item,
                ["confirmProjection"] = confirm
            };
            ((JArray)backpack["slots"])[0] = occupied;
            switch (corruption)
            {
                case "item_name_undefined":
                    item["name"] = " Undefined ";
                    confirm["name"] = " Undefined ";
                    break;
                case "item_extra_balance_summary":
                    item["balanceSummary"] = new JObject
                    {
                        ["state"] = "confirmed",
                        ["weightLayers"] = 1,
                        ["formula"] = 1,
                        ["level"] = 30
                    };
                    break;
                case "item_display_blank":
                    item["displayName"] = "   ";
                    confirm["displayName"] = "   ";
                    break;
                case "item_icon_undefined":
                    item["icon"] = "uNdEfInEd";
                    break;
                case "mod_slot_display_undefined":
                    item["modSlots"] = new JArray(new JObject
                    {
                        ["name"] = "插件内部名",
                        ["displayName"] = " Undefined ",
                        ["icon"] = "插件图标",
                        ["grade"] = "common",
                        ["gradeLabel"] = "普通",
                        ["gradeColor"] = "#FFFFFF",
                        ["role"] = "utility",
                        ["roleLabel"] = "功能",
                        ["symbol"] = "diamond-outline",
                        ["scope"] = "all"
                    });
                    break;
                case "mod_meta_icon_blank":
                    item["modMeta"] = new JObject
                    {
                        ["name"] = "插件内部名",
                        ["displayName"] = "插件展示名",
                        ["icon"] = "   ",
                        ["grade"] = "common",
                        ["gradeLabel"] = "普通",
                        ["gradeColor"] = "#FFFFFF",
                        ["role"] = "utility",
                        ["roleLabel"] = "功能",
                        ["symbol"] = "diamond-outline",
                        ["scope"] = "all"
                    };
                    break;
                case "confirm_missing": occupied.Remove("confirmProjection"); break;
                case "confirm_item_kind": confirm["itemKind"] = "equipment"; break;
                case "confirm_name": confirm["name"] = "伪造内部名"; break;
                case "confirm_display_name": confirm["displayName"] = "伪造展示名"; break;
                case "confirm_quantity": confirm["quantity"] = 1; break;
                case "confirm_enhancement": confirm["enhancementLevel"] = 1; break;
                case "confirm_rarity": confirm["rarity"] = "伪造品质"; break;
                default: throw new InvalidOperationException(corruption);
            }

            harness.Task.HandleFlashResponse(response, null);

            Assert.Equal(
                "malformed_response",
                harness.PostedAt(0).Value<string>("error"));
            Assert.Empty((JArray)harness.PostedAt(0)["snapshots"]);
        }

        [Fact]
        public void UnknownAuthorityField_IsNeverForwarded()
        {
            using var harness = new Harness();
            harness.Task.HandleWebRequest(Request("snapshot", "snapshot.bad"));
            JObject response = ActiveResponse(Assert.Single(harness.Sent));
            response["rewards"] = new JArray("secret");

            harness.Task.HandleFlashResponse(response, null);

            JObject posted = harness.PostedAt(0);
            AssertExactResponseWrapper(posted);
            Assert.False(posted.Value<bool>("success"));
            Assert.Equal("malformed_response", posted.Value<string>("error"));
            Assert.Null(posted["rewards"]);
        }

        [Fact]
        public void TimedOutWrite_RequiresSuccessfulQueryBeforeAnotherWrite()
        {
            using var harness = new Harness(40);
            PrimeActiveAuthority(harness, true);
            JObject claim = Request("claim", "claim.timeout");
            claim["expectedAuthorityRevision"] = 1;
            claim["source"]["expectedLease"] = "loot.slot.1";
            harness.Task.HandleWebRequest(claim);
            JObject timedOutFlash = harness.SentAt(1);
            Assert.True(SpinWait.SpinUntil(delegate { return harness.PostedCount == 2; }, 2000));
            Assert.Equal("reconcile_required", harness.Task.WriteState);
            Assert.Equal("operation.claim.1", harness.Task.UnknownOperationId);

            harness.Task.HandleFlashResponse(ActiveResponse(timedOutFlash,
                "operation.claim.1", 2), null);
            Assert.Equal(2, harness.PostedCount);

            harness.Task.HandleWebRequest(Request("claim", "claim.blocked"));
            Assert.Equal(2, harness.SentCount);
            Assert.Equal("reconcile_required", harness.PostedAt(2).Value<string>("error"));

            harness.Task.HandleWebRequest(Request("query", "query.1"));
            JObject queryFlash = harness.SentAt(2);
            JObject failedQuery = ErrorResponse(queryFlash, "query_failed");
            failedQuery["authorityRevision"] = 1;
            failedQuery["remainingCount"] = 1;
            harness.Task.HandleFlashResponse(failedQuery, null);
            Assert.Equal("reconcile_required", harness.Task.WriteState);

            harness.Task.HandleWebRequest(Request("query", "query.2"));
            JObject querySuccess = harness.SentAt(3);
            harness.Task.HandleFlashResponse(ActiveResponse(querySuccess,
                "operation.claim.1", 2), null);
            Assert.Equal("idle", harness.Task.WriteState);

            JObject afterQuery = Request("close", "close.after.query");
            afterQuery["expectedAuthorityRevision"] = 2;
            afterQuery["closeLease"] = "close.lease.2";
            harness.Task.HandleWebRequest(afterQuery);
            Assert.Equal("lootClose", harness.SentAt(4).Value<string>("action"));
        }

        [Fact]
        public void AmbiguousWriteSendFailure_RequiresReconcileAndUsesExactSyntheticUnion()
        {
            using var harness = new Harness();
            PrimeActiveAuthority(harness, true);
            harness.SendResult = false;

            JObject claim = Request("claim", "claim.not.sent");
            claim["expectedAuthorityRevision"] = 1;
            claim["source"]["expectedLease"] = "loot.slot.1";
            harness.Task.HandleWebRequest(claim);

            Assert.Equal("reconcile_required", harness.Task.WriteState);
            Assert.Equal("operation.claim.1", harness.Task.UnknownOperationId);
            JObject posted = harness.PostedAt(1);
            AssertExactResponseWrapper(posted);
            Assert.Equal("reconcile_required", posted.Value<string>("error"));
            Assert.Equal("LOOT_ACTIVE", posted.Value<string>("state"));

            harness.SendResult = true;
            harness.Task.HandleWebRequest(Request("close", "close.after.ambiguous.send"));
            Assert.Equal(2, harness.SentCount);
            Assert.Equal("reconcile_required", harness.PostedAt(2).Value<string>("error"));
        }

        [Fact]
        public void ReadSendFailure_RemainsDisconnectedWithoutOpeningWriteGate()
        {
            using var harness = new Harness();
            harness.SendResult = false;

            harness.Task.HandleWebRequest(Request("snapshot", "snapshot.not.sent"));

            Assert.Equal("idle", harness.Task.WriteState);
            JObject posted = harness.PostedAt(0);
            AssertExactResponseWrapper(posted);
            Assert.Equal("disconnected", posted.Value<string>("error"));
        }

        [Fact]
        public void CommitPending_BlocksWritesUntilCausalQueryProvesOriginalOperation()
        {
            using var harness = new Harness();
            PrimeActiveAuthority(harness, true);
            JObject claim = Request("claim", "claim.pending");
            claim["expectedAuthorityRevision"] = 1;
            claim["source"]["expectedLease"] = "loot.slot.1";
            harness.Task.HandleWebRequest(claim);
            JObject claimFlash = harness.SentAt(1);

            JObject claimPending = CommitPendingResponse(claimFlash);
            claimPending["remainingCount"] = 1;
            harness.Task.HandleFlashResponse(claimPending, null);

            Assert.Equal("reconcile_required", harness.Task.WriteState);
            Assert.Equal("operation.claim.1", harness.Task.UnknownOperationId);
            Assert.Equal("commit_pending", harness.PostedAt(1).Value<string>("error"));

            harness.Task.HandleWebRequest(Request("claim", "claim.pending.blocked"));
            harness.Task.HandleWebRequest(Request("close", "close.pending.blocked"));
            Assert.Equal(2, harness.SentCount);
            Assert.Equal("reconcile_required", harness.PostedAt(2).Value<string>("error"));
            Assert.Equal("reconcile_required", harness.PostedAt(3).Value<string>("error"));

            harness.Task.HandleWebRequest(Request("query", "query.pending.again"));
            JObject pendingQuery = harness.SentAt(2);
            JObject pendingAgain = CommitPendingResponse(pendingQuery);
            pendingAgain["remainingCount"] = 1;
            harness.Task.HandleFlashResponse(pendingAgain, null);
            Assert.Equal("reconcile_required", harness.Task.WriteState);

            harness.Task.HandleWebRequest(Request("query", "query.pending.old.revision"));
            JObject oldRevisionQuery = harness.SentAt(3);
            harness.Task.HandleFlashResponse(ActiveResponseWithLoot(oldRevisionQuery, 1), null);
            Assert.Equal("reconcile_required", harness.Task.WriteState);

            harness.Task.HandleWebRequest(Request("query", "query.pending.causal"));
            JObject causalQuery = harness.SentAt(4);
            harness.Task.HandleFlashResponse(ActiveResponse(causalQuery,
                "operation.claim.1", 2), null);
            Assert.Equal("idle", harness.Task.WriteState);

            JObject afterPending = Request("close", "close.pending.after");
            afterPending["expectedAuthorityRevision"] = 2;
            afterPending["closeLease"] = "close.lease.2";
            harness.Task.HandleWebRequest(afterPending);
            Assert.Equal("lootClose", harness.SentAt(5).Value<string>("action"));
        }

        [Fact]
        public void QueryDiscoveredCommitPending_BlocksWritesUntilNonPendingQuery()
        {
            using var harness = new Harness();
            harness.Task.HandleWebRequest(Request("query", "query.discovers.pending"));
            JObject firstQuery = Assert.Single(harness.Sent);

            harness.Task.HandleFlashResponse(CommitPendingResponse(firstQuery), null);

            Assert.Equal("reconcile_required", harness.Task.WriteState);
            Assert.Null(harness.Task.UnknownOperationId);
            harness.Task.HandleWebRequest(Request("claim", "claim.query.pending.blocked"));
            harness.Task.HandleWebRequest(Request("close", "close.query.pending.blocked"));
            Assert.Single(harness.Sent);
            Assert.Equal("reconcile_required", harness.PostedAt(1).Value<string>("error"));
            Assert.Equal("reconcile_required", harness.PostedAt(2).Value<string>("error"));

            harness.Task.HandleWebRequest(Request("query", "query.discovers.pending.again"));
            JObject pendingAgain = harness.Sent[1];
            harness.Task.HandleFlashResponse(CommitPendingResponse(pendingAgain), null);
            Assert.Equal("reconcile_required", harness.Task.WriteState);

            harness.Task.HandleWebRequest(Request("query", "query.discovers.pending.done"));
            JObject completed = harness.Sent[2];
            harness.Task.HandleFlashResponse(ActiveResponse(completed), null);
            Assert.Equal("idle", harness.Task.WriteState);

            JObject afterPending = Request("close", "close.query.pending.after");
            afterPending["expectedAuthorityRevision"] = 1;
            harness.Task.HandleWebRequest(afterPending);
            Assert.Equal("lootClose", harness.Sent[3].Value<string>("action"));
        }

        [Fact]
        public void QueryDiscoveredCommitPending_AllowsExactTerminalQueryToClose()
        {
            using var harness = new Harness();
            harness.Task.HandleWebRequest(Request("query", "query.pending.terminal.start"));
            JObject firstQuery = Assert.Single(harness.Sent);
            harness.Task.HandleFlashResponse(CommitPendingResponse(firstQuery), null);
            Assert.Equal("reconcile_required", harness.Task.WriteState);

            harness.Task.HandleWebRequest(Request("query", "query.pending.terminal.done"));
            JObject terminalQuery = harness.Sent[1];
            harness.Task.HandleFlashResponse(TerminalResponse(terminalQuery, "", "EXPIRED"), null);

            Assert.Equal("idle", harness.Task.WriteState);
            Assert.Equal(1, harness.Panel.CloseCalls);
        }

        [Fact]
        public void AuthorityTerminal_ClosesOnlyTrackedVisualAfterResponse()
        {
            using var harness = new Harness();
            PrimeActiveAuthority(harness, false);
            JObject request = Request("close", "close.1");
            request["expectedAuthorityRevision"] = 1;
            harness.Task.HandleWebRequest(request);
            JObject flash = harness.Sent[1];

            harness.Task.HandleFlashResponse(TerminalResponse(flash,
                request.Value<string>("operationId"), "CONSUMED", 2), null);

            JObject posted = harness.PostedAt(1);
            AssertExactResponseWrapper(posted);
            Assert.Equal("CONSUMED", posted.Value<string>("state"));
            Assert.Equal(1, harness.Panel.CloseCalls);
            Assert.Equal(LootPanelCoordinator.BindingState.TerminalCloseQueued,
                harness.Coordinator.State);
            Assert.Equal(2, harness.SentCount);
        }

        [Fact]
        public void AuthoritySuspended_ClosesOnlyExactTrackedVisualAfterStrictResponse()
        {
            using var harness = new Harness();
            PrimeActiveAuthority(harness, true);
            JObject request = Request("close", "close.suspend.1");
            request["expectedAuthorityRevision"] = 1;
            harness.Task.HandleWebRequest(request);
            JObject flash = harness.Sent[1];

            harness.Task.HandleFlashResponse(SuspendedResponse(flash,
                request.Value<string>("operationId"), 2, 1), null);

            JObject posted = harness.PostedAt(1);
            AssertExactResponseWrapper(posted);
            Assert.True(posted.Value<bool>("success"));
            Assert.Equal("LOOT_SUSPENDED", posted.Value<string>("state"));
            Assert.Equal(1, posted.Value<int>("remainingCount"));
            Assert.Empty((JArray)posted["snapshots"]);
            Assert.Equal(JTokenType.Null, posted["terminal"].Type);
            Assert.Equal(1, harness.Panel.CloseCalls);
            Assert.Equal(LootPanelCoordinator.BindingState.SuspendedCloseQueued,
                harness.Coordinator.State);
            Assert.True(harness.Coordinator.IsAuthoritySuspendedCloseKnownExact(
                PanelInstanceId));
            Assert.False(harness.Coordinator.IsAuthorityTerminalCloseKnownExact(
                PanelInstanceId));
            Assert.Equal(2, harness.SentCount);
        }

        [Fact]
        public void StableSuspendedQuery_DoesNotInventAVisualCloseProof()
        {
            using var harness = new Harness();
            PrimeActiveAuthority(harness, true);
            harness.Task.HandleWebRequest(Request("query", "query.suspended.1"));
            JObject flash = harness.Sent[1];

            harness.Task.HandleFlashResponse(SuspendedResponse(flash,
                "operation.close.known", 2, 1), null);

            Assert.Equal("LOOT_SUSPENDED", harness.PostedAt(1).Value<string>("state"));
            Assert.Equal(0, harness.Panel.CloseCalls);
            Assert.Equal(LootPanelCoordinator.BindingState.Bound,
                harness.Coordinator.State);
            Assert.False(harness.Coordinator.IsAuthoritySuspendedCloseKnownExact(
                PanelInstanceId));
        }

        [Fact]
        public void UnknownNonAbandonClose_ExactSuspendedQueryProvesTrackedVisualClose()
        {
            using var harness = new Harness(timeoutMs: 40);
            PrimeActiveAuthority(harness, true);
            JObject request = Request("close", "close.suspend.timeout");
            request["expectedAuthorityRevision"] = 1;
            harness.Task.HandleWebRequest(request);
            Assert.True(SpinWait.SpinUntil(delegate { return harness.PostedCount == 2; },
                2000));
            Assert.Equal("reconcile_required", harness.Task.WriteState);

            harness.Task.HandleWebRequest(Request("query", "query.suspend.proof"));
            JObject query = harness.Sent[2];
            harness.Task.HandleFlashResponse(SuspendedResponse(query,
                request.Value<string>("operationId"), 2, 1), null);

            Assert.Equal("idle", harness.Task.WriteState);
            Assert.Equal("LOOT_SUSPENDED", harness.PostedAt(2).Value<string>("state"));
            Assert.Equal(1, harness.Panel.CloseCalls);
            Assert.Equal(LootPanelCoordinator.BindingState.SuspendedCloseQueued,
                harness.Coordinator.State);
            Assert.True(harness.Coordinator.IsAuthoritySuspendedCloseKnownExact(
                PanelInstanceId));
            Assert.Equal(1, harness.Sent.Count(value =>
                value.Value<string>("action") == "lootClose"));
        }

        [Fact]
        public void UnknownClose_SuspendedQueryNeedsExactOperationRevisionAndRemaining()
        {
            using var harness = new Harness(timeoutMs: 40);
            PrimeActiveAuthority(harness, true);
            JObject request = Request("close", "close.suspend.strict.query");
            request["expectedAuthorityRevision"] = 1;
            harness.Task.HandleWebRequest(request);
            Assert.True(SpinWait.SpinUntil(delegate { return harness.PostedCount == 2; },
                2000));
            string operationId = request.Value<string>("operationId");

            harness.Task.HandleWebRequest(Request("query", "query.suspend.same.revision"));
            harness.Task.HandleFlashResponse(SuspendedResponse(harness.Sent[2],
                operationId, 1, 1), null);
            Assert.Equal("reconcile_required", harness.Task.WriteState);
            Assert.Equal(0, harness.Panel.CloseCalls);

            harness.Task.HandleWebRequest(Request("query", "query.suspend.wrong.operation"));
            harness.Task.HandleFlashResponse(SuspendedResponse(harness.Sent[3],
                "operation.close.other", 2, 1), null);
            Assert.Equal("reconcile_required", harness.Task.WriteState);
            Assert.Equal(0, harness.Panel.CloseCalls);

            harness.Task.HandleWebRequest(Request("query", "query.suspend.wrong.remaining"));
            harness.Task.HandleFlashResponse(SuspendedResponse(harness.Sent[4],
                operationId, 3, 2), null);
            Assert.Equal("reconcile_required", harness.Task.WriteState);
            Assert.Equal(0, harness.Panel.CloseCalls);

            harness.Task.HandleWebRequest(Request("query", "query.suspend.exact"));
            harness.Task.HandleFlashResponse(SuspendedResponse(harness.Sent[5],
                operationId, 4, 1), null);
            Assert.Equal("idle", harness.Task.WriteState);
            Assert.Equal(1, harness.Panel.CloseCalls);
            Assert.True(harness.Coordinator.IsAuthoritySuspendedCloseKnownExact(
                PanelInstanceId));
        }

        [Fact]
        public void UnknownClose_ActiveQueryCannotRollbackFreshnessOrProveAppliedClose()
        {
            using var harness = new Harness();
            PrimeActiveAuthority(harness, true);
            JObject close = Request("close", "close.unknown.active");
            close["expectedAuthorityRevision"] = 1;
            close["closeLease"] = "close.lease.1";
            harness.Task.HandleWebRequest(close);
            JObject closeFlash = harness.SentAt(1);
            JObject impossibleActive = ActiveResponseWithLoot(closeFlash, 2);
            impossibleActive["lastAppliedOperationId"] = close.Value<string>("operationId");
            harness.Task.HandleFlashResponse(impossibleActive, null);

            Assert.Equal("reconcile_required", harness.Task.WriteState);
            Assert.Equal(1, harness.Task.LastAuthorityRevision);

            harness.Task.HandleWebRequest(Request("query", "query.close.active.applied"));
            JObject appliedActiveQuery = harness.SentAt(2);
            JObject appliedActive = ActiveResponseWithLoot(appliedActiveQuery, 2);
            appliedActive["lastAppliedOperationId"] = close.Value<string>("operationId");
            harness.Task.HandleFlashResponse(appliedActive, null);

            Assert.Equal("reconcile_required", harness.Task.WriteState);
            Assert.Equal(1, harness.Task.LastAuthorityRevision);
            Assert.Equal(1, harness.Sent.Count(value =>
                value.Value<string>("action") == "lootClose"));

            harness.Task.HandleWebRequest(Request("query", "query.close.version.drift"));
            JObject versionQuery = harness.SentAt(3);
            JObject versionDrift = ActiveResponseWithLoot(versionQuery, 1);
            versionDrift["snapshots"][0]["containerVersion"] = 2;
            harness.Task.HandleFlashResponse(versionDrift, null);

            Assert.Equal("reconcile_required", harness.Task.WriteState);
            Assert.Equal(1, harness.Task.LastAuthorityRevision);
            Assert.Equal(1, harness.Sent.Count(value =>
                value.Value<string>("action") == "lootClose"));

            harness.Task.HandleWebRequest(Request("query", "query.close.exact.no.write"));
            JObject exactQuery = harness.SentAt(4);
            harness.Task.HandleFlashResponse(ActiveResponseWithLoot(exactQuery, 1), null);

            Assert.Equal("reconcile_required", harness.Task.WriteState);
            Assert.Equal(1, harness.Task.LastAuthorityRevision);
            Assert.Equal(1, harness.Sent.Count(value =>
                value.Value<string>("action") == "lootClose"));

            harness.Task.HandleWebRequest(Request("query", "query.close.suspended.proof"));
            JObject suspendedQuery = harness.SentAt(5);
            harness.Task.HandleFlashResponse(SuspendedResponse(suspendedQuery,
                close.Value<string>("operationId"), 2, 1), null);
            Assert.Equal("idle", harness.Task.WriteState);
            Assert.Equal(1, harness.Panel.CloseCalls);
        }

        [Fact]
        public void UnknownClose_ExactActiveNoWriteProofClearsWithoutReplay()
        {
            using var harness = new Harness();
            PrimeActiveAuthority(harness, true);
            harness.SendResult = false;
            JObject close = Request("close", "close.unknown.no.write");
            close["expectedAuthorityRevision"] = 1;
            harness.Task.HandleWebRequest(close);
            harness.SendResult = true;
            Assert.Equal("reconcile_required", harness.Task.WriteState);

            harness.Task.HandleWebRequest(Request("query", "query.close.no.write.exact"));
            JObject query = harness.SentAt(2);
            harness.Task.HandleFlashResponse(ActiveResponseWithLoot(query, 1), null);

            Assert.Equal("idle", harness.Task.WriteState);
            Assert.Equal(1, harness.Task.LastAuthorityRevision);
            Assert.Equal(1, harness.Sent.Count(value =>
                value.Value<string>("action") == "lootClose"));
        }

        [Fact]
        public void SuspendedAuthorityShape_IsSuccessOnlyDataFreeAndNonnegative()
        {
            Action<JObject>[] corruptions =
            {
                response => response["closeLease"] = "close.stale",
                response => response["snapshots"] = new JArray(
                    Snapshot(LootContainerId, 2, 2, ContainerEpoch)),
                response => response["tooltip"] = new JObject(),
                response => response["terminal"] = new JObject
                {
                    ["kind"] = "ABANDONED",
                    ["reason"] = "player_closed",
                    ["remainingCount"] = 1
                },
                response =>
                {
                    response["success"] = false;
                    response["error"] = "stale_state";
                }
            };

            foreach (Action<JObject> corrupt in corruptions)
            {
                using (var harness = new Harness())
                {
                    PrimeActiveAuthority(harness, true);
                    JObject request = Request("close", "close.suspended.malformed");
                    request["expectedAuthorityRevision"] = 1;
                    harness.Task.HandleWebRequest(request);
                    JObject response = SuspendedResponse(harness.Sent[1],
                        request.Value<string>("operationId"), 2, 1);
                    corrupt(response);

                    harness.Task.HandleFlashResponse(response, null);

                    Assert.Equal("reconcile_required", harness.Task.WriteState);
                    Assert.Equal("reconcile_required",
                        harness.PostedAt(1).Value<string>("error"));
                    Assert.Equal(0, harness.Panel.CloseCalls);
                    Assert.Equal(LootPanelCoordinator.BindingState.Bound,
                        harness.Coordinator.State);
                }
            }
        }

        [Fact]
        public void SuspendedZeroRewardQuery_IsValidDataFreeRecoveryProjection()
        {
            using var harness = new Harness(stageSettlement: true);
            PrimeActiveAuthority(harness, false);
            harness.Task.HandleWebRequest(Request("query", "query.suspended.zero.reward"));
            JObject flash = harness.SentAt(1);

            harness.Task.HandleFlashResponse(SuspendedResponse(flash,
                "operation.stage.report.zero", 2, 0), null);

            JObject posted = harness.PostedAt(1);
            Assert.True(posted.Value<bool>("success"));
            Assert.Equal("LOOT_SUSPENDED", posted.Value<string>("state"));
            Assert.Equal(0, posted.Value<int>("remainingCount"));
            Assert.Empty((JArray)posted["snapshots"]);
            Assert.Equal(JTokenType.Null, posted["terminal"].Type);
            Assert.Equal(0, harness.Panel.CloseCalls);
        }

        [Fact]
        public void SuspendedZeroMapChestQuery_IsRejectedAsMalformedAuthority()
        {
            using var harness = new Harness();
            PrimeActiveAuthority(harness, false);
            harness.Task.HandleWebRequest(Request("query", "query.suspended.zero.map"));
            JObject flash = harness.SentAt(1);

            harness.Task.HandleFlashResponse(SuspendedResponse(flash,
                "operation.map.empty", 2, 0), null);

            JObject posted = harness.PostedAt(1);
            Assert.False(posted.Value<bool>("success"));
            Assert.Equal("malformed_response", posted.Value<string>("error"));
            Assert.Equal(0, harness.Panel.CloseCalls);
        }

        [Fact]
        public void OversizedJsonIntegers_FailClosedWithoutThrowing()
        {
            JToken huge = JToken.Parse("999999999999999999999999999999999999999999");

            using (var requestHarness = new Harness())
            {
                JObject claim = Request("claim", "claim.huge.revision");
                claim["expectedAuthorityRevision"] = huge.DeepClone();
                Exception requestError = Record.Exception(delegate
                {
                    requestHarness.Task.HandleWebRequest(claim);
                });
                Assert.Null(requestError);
                Assert.Empty(requestHarness.Sent);
                Assert.Equal("invalid_payload",
                    requestHarness.PostedAt(0).Value<string>("error"));
            }

            using (var revisionHarness = new Harness())
            {
                revisionHarness.Task.HandleWebRequest(Request("snapshot",
                    "snapshot.huge.revision"));
                JObject response = ActiveResponse(Assert.Single(revisionHarness.Sent));
                response["authorityRevision"] = huge.DeepClone();
                Exception responseError = Record.Exception(delegate
                {
                    revisionHarness.Task.HandleFlashResponse(response, null);
                });
                Assert.Null(responseError);
                Assert.Equal("malformed_response",
                    revisionHarness.PostedAt(0).Value<string>("error"));
            }

            using (var quantityHarness = new Harness())
            {
                quantityHarness.Task.HandleWebRequest(Request("snapshot",
                    "snapshot.huge.quantity"));
                JObject response = ActiveResponseWithLoot(
                    Assert.Single(quantityHarness.Sent));
                response["snapshots"][0]["slots"][0]["item"]["quantity"] =
                    huge.DeepClone();
                Exception quantityError = Record.Exception(delegate
                {
                    quantityHarness.Task.HandleFlashResponse(response, null);
                });
                Assert.Null(quantityError);
                Assert.Equal("malformed_response",
                    quantityHarness.PostedAt(0).Value<string>("error"));
            }
        }

        [Fact]
        public void ExplicitAbandonClose_RejectsSuspendedDisposition()
        {
            using var harness = new Harness();
            PrimeActiveAuthority(harness, true);
            JObject request = Request("close", "close.abandon.suspended");
            request["abandon"] = true;
            request["expectedAuthorityRevision"] = 1;
            harness.Task.HandleWebRequest(request);
            JObject flash = harness.Sent[1];

            harness.Task.HandleFlashResponse(SuspendedResponse(flash,
                request.Value<string>("operationId"), 2, 1), null);

            Assert.Equal("reconcile_required", harness.Task.WriteState);
            Assert.Equal("reconcile_required", harness.PostedAt(1).Value<string>("error"));
            Assert.Equal(0, harness.Panel.CloseCalls);
            Assert.Equal(LootPanelCoordinator.BindingState.Bound,
                harness.Coordinator.State);
        }

        [Fact]
        public void EmptyClose_NormalizesTrueAbandonBitToConsumed()
        {
            using var harness = new Harness();
            PrimeActiveAuthority(harness, false);
            JObject request = Request("close", "close.empty.true");
            request["abandon"] = true;
            request["expectedAuthorityRevision"] = 1;
            harness.Task.HandleWebRequest(request);

            harness.Task.HandleFlashResponse(TerminalResponse(harness.Sent[1],
                request.Value<string>("operationId"), "CONSUMED", 2, 0), null);

            Assert.True(harness.PostedAt(1).Value<bool>("success"));
            Assert.Equal("CONSUMED", harness.PostedAt(1).Value<string>("state"));
            Assert.Equal(1, harness.Panel.CloseCalls);
            Assert.Equal("idle", harness.Task.WriteState);
        }

        [Fact]
        public void NonemptyExplicitAbandon_AcceptsOnlyAbandonedWithFrozenRemaining()
        {
            using var harness = new Harness();
            PrimeActiveAuthority(harness, true);
            JObject request = Request("close", "close.nonempty.abandon");
            request["abandon"] = true;
            request["expectedAuthorityRevision"] = 1;
            harness.Task.HandleWebRequest(request);

            harness.Task.HandleFlashResponse(TerminalResponse(harness.Sent[1],
                request.Value<string>("operationId"), "ABANDONED", 2, 1), null);

            Assert.True(harness.PostedAt(1).Value<bool>("success"));
            Assert.Equal("ABANDONED", harness.PostedAt(1).Value<string>("state"));
            Assert.Equal(1, harness.PostedAt(1).Value<int>("remainingCount"));
            Assert.Equal(1, harness.Panel.CloseCalls);
        }

        [Fact]
        public void CloseDisposition_RejectsTerminalThatContradictsFrozenPrestate()
        {
            using (var harness = new Harness())
            {
                PrimeActiveAuthority(harness, true);
                JObject request = Request("close", "close.nonempty.consume");
                request["expectedAuthorityRevision"] = 1;
                harness.Task.HandleWebRequest(request);
                harness.Task.HandleFlashResponse(TerminalResponse(harness.Sent[1],
                    request.Value<string>("operationId"), "CONSUMED", 2, 0), null);

                Assert.Equal("reconcile_required", harness.Task.WriteState);
                Assert.Equal("reconcile_required",
                    harness.PostedAt(1).Value<string>("error"));
                Assert.Equal(0, harness.Panel.CloseCalls);
            }

            using (var harness = new Harness())
            {
                PrimeActiveAuthority(harness, false);
                JObject request = Request("close", "close.empty.abandoned");
                request["abandon"] = true;
                request["expectedAuthorityRevision"] = 1;
                harness.Task.HandleWebRequest(request);
                harness.Task.HandleFlashResponse(TerminalResponse(harness.Sent[1],
                    request.Value<string>("operationId"), "ABANDONED", 2, 0), null);

                Assert.Equal("reconcile_required", harness.Task.WriteState);
                Assert.Equal("reconcile_required",
                    harness.PostedAt(1).Value<string>("error"));
                Assert.Equal(0, harness.Panel.CloseCalls);
            }
        }

        [Fact]
        public void StrictAuthorityErrorMayStillProveTerminalState()
        {
            using var harness = new Harness();
            harness.Task.HandleWebRequest(Request("query", "query.terminal.error"));
            JObject response = TerminalResponse(Assert.Single(harness.Sent), "", "EXPIRED");
            response["success"] = false;
            response["error"] = "terminal_state";

            harness.Task.HandleFlashResponse(response, null);

            JObject posted = harness.PostedAt(0);
            AssertExactResponseWrapper(posted);
            Assert.False(posted.Value<bool>("success"));
            Assert.Equal("EXPIRED", posted.Value<string>("state"));
            Assert.NotNull(posted["terminal"] as JObject);
            Assert.Equal(1, harness.Panel.CloseCalls);
        }

        [Theory]
        [InlineData("CONSUMED", 1)]
        [InlineData("ABANDONED", 0)]
        public void CorruptTerminalRemainingInvariant_IsRejected(string state, int remaining)
        {
            using var harness = new Harness();
            harness.Task.HandleWebRequest(Request("query", "query.terminal.corrupt." + state));
            JObject response = TerminalResponse(Assert.Single(harness.Sent), "", state,
                1, remaining);

            harness.Task.HandleFlashResponse(response, null);

            Assert.Equal("malformed_response",
                harness.PostedAt(0).Value<string>("error"));
            Assert.Equal(0, harness.Panel.CloseCalls);
            Assert.Equal(LootPanelCoordinator.BindingState.Bound,
                harness.Coordinator.State);
        }

        [Fact]
        public void UnknownClose_TerminalQueryRequiresRevisionAfterFrozenPrestate()
        {
            using var harness = new Harness(timeoutMs: 40);
            PrimeActiveAuthority(harness, false);
            JObject close = Request("close", "close.terminal.same.revision");
            close["expectedAuthorityRevision"] = 1;
            harness.Task.HandleWebRequest(close);
            Assert.True(SpinWait.SpinUntil(delegate { return harness.PostedCount == 2; },
                2000));
            Assert.Equal("reconcile_required", harness.Task.WriteState);

            harness.Task.HandleWebRequest(Request("query", "query.terminal.same.revision"));
            JObject sameRevision = TerminalResponse(harness.Sent[2],
                close.Value<string>("operationId"), "CONSUMED", 1, 0);
            harness.Task.HandleFlashResponse(sameRevision, null);

            Assert.Equal("reconcile_required", harness.Task.WriteState);
            Assert.Equal("malformed_response",
                harness.PostedAt(2).Value<string>("error"));
            Assert.Equal(0, harness.Panel.CloseCalls);

            harness.Task.HandleWebRequest(Request("query", "query.terminal.next.revision"));
            JObject nextRevision = TerminalResponse(harness.Sent[3],
                close.Value<string>("operationId"), "CONSUMED", 2, 0);
            harness.Task.HandleFlashResponse(nextRevision, null);

            Assert.Equal("idle", harness.Task.WriteState);
            Assert.Equal("CONSUMED", harness.PostedAt(3).Value<string>("state"));
            Assert.Equal(1, harness.Panel.CloseCalls);
        }

        [Fact]
        public void AuthorityWriteError_DoesNotCloseTrackedVisual()
        {
            using var harness = new Harness();
            PrimeActiveAuthority(harness, false);
            JObject request = Request("close", "close.error");
            request["expectedAuthorityRevision"] = 1;
            harness.Task.HandleWebRequest(request);
            JObject flash = harness.Sent[1];

            JObject response = ErrorResponse(flash);
            response["authorityRevision"] = 1;
            harness.Task.HandleFlashResponse(response, null);

            Assert.Equal(0, harness.Panel.CloseCalls);
            Assert.Equal(LootPanelCoordinator.BindingState.Bound, harness.Coordinator.State);
            Assert.Equal("idle", harness.Task.WriteState);
            Assert.Equal("stale_state", harness.PostedAt(1).Value<string>("error"));
        }

        [Fact]
        public void DirectCloseSuccess_RequiresExactlyOneAuthorityRevisionAdvance()
        {
            using var harness = new Harness();
            PrimeActiveAuthority(harness, false);
            JObject close = Request("close", "close.direct.skipped.revision");
            close["expectedAuthorityRevision"] = 1;
            harness.Task.HandleWebRequest(close);
            JObject closeFlash = harness.SentAt(1);

            harness.Task.HandleFlashResponse(TerminalResponse(closeFlash,
                close.Value<string>("operationId"), "CONSUMED", 3, 0), null);

            Assert.Equal("reconcile_required", harness.Task.WriteState);
            Assert.Equal(1, harness.Task.LastAuthorityRevision);
            Assert.Equal("reconcile_required",
                harness.PostedAt(1).Value<string>("error"));
            Assert.Equal(0, harness.Panel.CloseCalls);
        }

        [Fact]
        public void ExactClaimSuccess_RequiresPlusOneMinusOneAndEmptiesRequestedSlot()
        {
            using var harness = new Harness();
            PrimeActiveAuthority(harness, true);

            JObject claim = Request("claim", "claim.strict.success");
            claim["expectedAuthorityRevision"] = 1;
            claim["source"]["expectedLease"] = "loot.slot.1";
            harness.Task.HandleWebRequest(claim);
            JObject claimFlash = harness.SentAt(1);

            harness.Task.HandleFlashResponse(ActiveResponse(claimFlash,
                claim.Value<string>("operationId"), 2), null);

            JObject posted = harness.PostedAt(1);
            Assert.True(posted.Value<bool>("success"));
            Assert.Equal("LOOT_ACTIVE", posted.Value<string>("state"));
            Assert.Equal(2, posted.Value<int>("authorityRevision"));
            Assert.Equal(0, posted.Value<int>("remainingCount"));
            Assert.False(posted["snapshots"][0]["slots"][0].Value<bool>("occupied"));
            Assert.Equal("idle", harness.Task.WriteState);
            Assert.Equal(2, harness.Task.LastAuthorityRevision);

            JObject close = Request("close", "close.after.strict.claim");
            close["expectedAuthorityRevision"] = 2;
            close["closeLease"] = "close.lease.2";
            harness.Task.HandleWebRequest(close);
            JObject closeFlash = harness.SentAt(2);
            Assert.Equal("lootClose", closeFlash.Value<string>("action"));
            harness.Task.HandleFlashResponse(TerminalResponse(closeFlash,
                close.Value<string>("operationId"), "CONSUMED", 3, 0), null);
            Assert.Equal(1, harness.Panel.CloseCalls);
        }

        [Theory]
        [InlineData(true, true, 3, 0)]
        [InlineData(true, false, 2, 1)]
        public void ExactClaimBatchSuccess_UsesOneFlashCallAndProvesEveryRequestedSlot(
            bool firstApplied, bool secondApplied, int revision, int remaining)
        {
            using var harness = new Harness();
            PrimeActiveAuthorityWithTwoLoot(harness);
            JObject claim = Request("claimBatch", "claim.batch.strict.success",
                operationId: "operation.claim.batch.strict");
            claim["expectedAuthorityRevision"] = 1;
            claim["sources"] = new JArray
            {
                BatchSourceRef(0, "loot.slot.1"),
                BatchSourceRef(1, "loot.slot.second.1")
            };

            harness.Task.HandleWebRequest(claim);

            JObject flash = harness.SentAt(1);
            Assert.Equal("lootClaimBatch", flash.Value<string>("action"));
            Assert.Equal(2, ((JArray)flash["sources"]).Count);
            harness.Task.HandleFlashResponse(ActiveBatchResponse(flash,
                claim.Value<string>("operationId"), revision, firstApplied, secondApplied), null);

            JObject posted = harness.PostedAt(1);
            Assert.True(posted.Value<bool>("success"));
            Assert.Equal(revision, posted.Value<int>("authorityRevision"));
            Assert.Equal(remaining, posted.Value<int>("remainingCount"));
            Assert.Equal("idle", harness.Task.WriteState);
            Assert.Equal(2, harness.SentCount);
        }

        [Fact]
        public void DriftedClaimBatchSuccess_BecomesUnknownWithoutAdvancingKnownAuthority()
        {
            using var harness = new Harness();
            PrimeActiveAuthorityWithTwoLoot(harness);
            JObject claim = Request("claimBatch", "claim.batch.drift",
                operationId: "operation.claim.batch.drift");
            claim["expectedAuthorityRevision"] = 1;
            claim["sources"] = new JArray
            {
                BatchSourceRef(0, "loot.slot.1"),
                BatchSourceRef(1, "loot.slot.second.1")
            };
            harness.Task.HandleWebRequest(claim);
            JObject flash = harness.SentAt(1);
            JObject impossible = ActiveBatchResponse(flash,
                claim.Value<string>("operationId"), 3, true, false);

            harness.Task.HandleFlashResponse(impossible, null);

            Assert.Equal("reconcile_required", harness.Task.WriteState);
            Assert.Equal(1, harness.Task.LastAuthorityRevision);
            Assert.False(harness.PostedAt(1).Value<bool>("success"));
            Assert.Equal("reconcile_required", harness.PostedAt(1).Value<string>("error"));
        }

        [Fact]
        public void ClaimBatchFailureAfterAppliedPrefix_RequiresExactQueryBeforeLaterWrites()
        {
            using var harness = new Harness();
            PrimeActiveAuthorityWithTwoLoot(harness);
            JObject claim = Request("claimBatch", "claim.batch.partial.failure",
                operationId: "operation.claim.batch.partial.failure");
            claim["expectedAuthorityRevision"] = 1;
            claim["sources"] = new JArray
            {
                BatchSourceRef(0, "loot.slot.1"),
                BatchSourceRef(1, "loot.slot.second.1")
            };
            harness.Task.HandleWebRequest(claim);
            JObject flash = harness.SentAt(1);
            JObject failed = ErrorResponse(flash, "stale_state");
            failed["authorityRevision"] = 2;
            failed["remainingCount"] = 1;
            failed["lastAppliedOperationId"] = claim.Value<string>("operationId");

            harness.Task.HandleFlashResponse(failed, null);

            Assert.Equal("reconcile_required", harness.Task.WriteState);
            Assert.Equal(1, harness.Task.LastAuthorityRevision);
            Assert.Equal("stale_state", harness.PostedAt(1).Value<string>("error"));

            harness.Task.HandleWebRequest(Request("query", "query.batch.partial.failure"));
            JObject query = harness.SentAt(2);
            harness.Task.HandleFlashResponse(ActiveBatchResponse(query,
                claim.Value<string>("operationId"), 2, true, false), null);

            Assert.Equal("idle", harness.Task.WriteState);
            Assert.Equal(2, harness.Task.LastAuthorityRevision);
            Assert.True(harness.PostedAt(2).Value<bool>("success"));
        }

        [Fact]
        public void UnknownClaimBatch_AcceptsOnlyExactFrozenNoWriteProjection()
        {
            using var harness = new Harness();
            PrimeActiveAuthorityWithTwoLoot(harness);
            JObject claim = Request("claimBatch", "claim.batch.not.sent",
                operationId: "operation.claim.batch.not.sent");
            claim["expectedAuthorityRevision"] = 1;
            claim["sources"] = new JArray
            {
                BatchSourceRef(0, "loot.slot.1"),
                BatchSourceRef(1, "loot.slot.second.1")
            };
            harness.SendResult = false;
            harness.Task.HandleWebRequest(claim);
            harness.SendResult = true;
            Assert.Equal("reconcile_required", harness.Task.WriteState);

            harness.Task.HandleWebRequest(Request("query", "query.batch.no.write"));
            JObject query = harness.SentAt(2);
            harness.Task.HandleFlashResponse(ActiveResponseWithTwoLoot(query, 1), null);

            Assert.Equal("idle", harness.Task.WriteState);
            Assert.Equal(1, harness.Task.LastAuthorityRevision);
            Assert.Equal(1, harness.Sent.Count(value =>
                value.Value<string>("action") == "lootClaimBatch"));
        }

        [Fact]
        public void ClaimBatchPayload_RejectsDuplicateSourcesBeforeTransport()
        {
            using var harness = new Harness();
            PrimeActiveAuthorityWithTwoLoot(harness);
            JObject claim = Request("claimBatch", "claim.batch.duplicate");
            claim["expectedAuthorityRevision"] = 1;
            JObject duplicate = BatchSourceRef(0, "loot.slot.1");
            claim["sources"] = new JArray(duplicate, duplicate.DeepClone());

            harness.Task.HandleWebRequest(claim);

            Assert.Equal(1, harness.SentCount);
            Assert.False(harness.PostedAt(1).Value<bool>("success"));
            Assert.Equal("invalid_payload", harness.PostedAt(1).Value<string>("error"));
            Assert.Equal("idle", harness.Task.WriteState);
        }

        [Theory]
        [InlineData("wrong_revision")]
        [InlineData("wrong_count")]
        [InlineData("wrong_slot")]
        [InlineData("missing_slot")]
        public void DriftedClaimSuccess_IsUnknownAndNeverUpdatesKnownAuthority(string drift)
        {
            using var harness = new Harness();
            if (drift == "wrong_slot")
            {
                harness.Task.HandleWebRequest(Request("snapshot", "snapshot.claim.two"));
                JObject prime = Assert.Single(harness.Sent);
                harness.Task.HandleFlashResponse(ActiveResponseWithTwoLoot(prime, 1), null);
                Assert.True(harness.PostedAt(0).Value<bool>("success"));
            }
            else
            {
                PrimeActiveAuthority(harness, true);
            }

            JObject claim = Request("claim", "claim.invalid.success." + drift);
            claim["expectedAuthorityRevision"] = 1;
            claim["source"]["expectedLease"] = "loot.slot.1";
            harness.Task.HandleWebRequest(claim);
            JObject claimFlash = harness.SentAt(1);
            JObject response;

            if (drift == "wrong_revision")
            {
                response = ActiveResponse(claimFlash,
                    claim.Value<string>("operationId"), 3);
            }
            else if (drift == "wrong_count")
            {
                response = ActiveResponse(claimFlash,
                    claim.Value<string>("operationId"), 2);
                response["remainingCount"] = 1;
                JObject loot = (JObject)response["snapshots"][0];
                loot["filterItemCount"] = 1;
                ((JArray)loot["slots"])[1] = new JObject
                {
                    ["physicalSlot"] = 1,
                    ["occupied"] = true,
                    ["slotLease"] = "loot.slot.unrequested.2",
                    ["item"] = ItemProjection()
                };
            }
            else if (drift == "wrong_slot")
            {
                response = ActiveResponseWithLoot(claimFlash, 2);
                response["lastAppliedOperationId"] = claim.Value<string>("operationId");
            }
            else
            {
                response = ActiveResponse(claimFlash,
                    claim.Value<string>("operationId"), 2);
                ((JArray)response["snapshots"][0]["slots"]).RemoveAt(0);
            }

            harness.Task.HandleFlashResponse(response, null);

            JObject posted = harness.PostedAt(1);
            Assert.False(posted.Value<bool>("success"));
            Assert.Equal("reconcile_required", posted.Value<string>("error"));
            Assert.Equal("reconcile_required", harness.Task.WriteState);
            Assert.Equal(1, harness.Task.LastAuthorityRevision);
            Assert.Equal(2, harness.SentCount);
            Assert.Equal(0, harness.Panel.CloseCalls);
        }

        [Fact]
        public void InvalidClaimSuccess_CannotBeLaunderedByQuery_AndSuspendedCannotSettle()
        {
            using var harness = new Harness();
            PrimeActiveAuthority(harness, true);
            JObject claim = Request("claim", "claim.invalid.then.query");
            claim["expectedAuthorityRevision"] = 1;
            claim["source"]["expectedLease"] = "loot.slot.1";
            harness.Task.HandleWebRequest(claim);
            JObject claimFlash = harness.SentAt(1);
            JObject wrongSuccess = ActiveResponseWithLoot(claimFlash, 2);
            wrongSuccess["lastAppliedOperationId"] = claim.Value<string>("operationId");
            harness.Task.HandleFlashResponse(wrongSuccess, null);

            Assert.Equal("reconcile_required", harness.Task.WriteState);
            Assert.Equal(1, harness.Task.LastAuthorityRevision);

            harness.Task.HandleWebRequest(Request("query", "query.same.wrong.claim"));
            JObject wrongQuery = harness.SentAt(2);
            JObject repeatedWrong = ActiveResponseWithLoot(wrongQuery, 2);
            repeatedWrong["lastAppliedOperationId"] = claim.Value<string>("operationId");
            harness.Task.HandleFlashResponse(repeatedWrong, null);

            Assert.False(harness.PostedAt(2).Value<bool>("success"));
            Assert.Equal("reconcile_required",
                harness.PostedAt(2).Value<string>("error"));
            Assert.Equal(2, harness.PostedAt(2).Value<int>("authorityRevision"));
            Assert.Equal("reconcile_required", harness.Task.WriteState);
            Assert.Equal(1, harness.Task.LastAuthorityRevision);

            harness.Task.HandleWebRequest(Request("query", "query.suspended.claim"));
            JObject suspendedQuery = harness.SentAt(3);
            harness.Task.HandleFlashResponse(SuspendedResponse(suspendedQuery,
                claim.Value<string>("operationId"), 2, 1), null);

            Assert.Equal("reconcile_required", harness.Task.WriteState);
            Assert.Equal(1, harness.Task.LastAuthorityRevision);
            Assert.Equal(0, harness.Panel.CloseCalls);

            harness.Task.HandleWebRequest(Request("query", "query.correct.claim"));
            JObject correctQuery = harness.SentAt(4);
            harness.Task.HandleFlashResponse(ActiveResponse(correctQuery,
                claim.Value<string>("operationId"), 2), null);

            Assert.Equal("idle", harness.Task.WriteState);
            Assert.Equal(2, harness.Task.LastAuthorityRevision);
            JObject close = Request("close", "close.after.claim.reconcile");
            close["expectedAuthorityRevision"] = 2;
            close["closeLease"] = "close.lease.2";
            harness.Task.HandleWebRequest(close);
            Assert.Equal("lootClose", harness.SentAt(5).Value<string>("action"));
        }

        [Fact]
        public void UnknownClaim_ExactSameRevisionSourceProof_ClearsAsNotApplied()
        {
            using var harness = new Harness();
            PrimeActiveAuthority(harness, true);
            JObject claim = Request("claim", "claim.not.applied.proof");
            claim["expectedAuthorityRevision"] = 1;
            claim["source"]["expectedLease"] = "loot.slot.1";
            harness.SendResult = false;
            harness.Task.HandleWebRequest(claim);
            harness.SendResult = true;
            Assert.Equal("reconcile_required", harness.Task.WriteState);

            harness.Task.HandleWebRequest(Request("query", "query.not.applied.proof"));
            JObject queryFlash = harness.SentAt(2);
            harness.Task.HandleFlashResponse(ActiveResponseWithLoot(queryFlash, 1), null);

            Assert.Equal("idle", harness.Task.WriteState);
            Assert.Equal(1, harness.Task.LastAuthorityRevision);
            JObject retry = Request("claim", "claim.after.not.applied",
                operationId: "operation.claim.retry");
            retry["expectedAuthorityRevision"] = 1;
            retry["source"]["expectedLease"] = "loot.slot.1";
            harness.Task.HandleWebRequest(retry);
            Assert.Equal("lootClaim", harness.SentAt(3).Value<string>("action"));
        }

        [Fact]
        public void UnknownClaim_NoWriteProofRequiresFrozenCloseLease()
        {
            using var harness = new Harness();
            PrimeActiveAuthority(harness, true);
            harness.SendResult = false;
            JObject claim = Request("claim", "claim.close.lease.proof");
            claim["expectedAuthorityRevision"] = 1;
            claim["source"]["expectedLease"] = "loot.slot.1";
            harness.Task.HandleWebRequest(claim);
            Assert.Equal("reconcile_required", harness.Task.WriteState);
            harness.SendResult = true;

            harness.Task.HandleWebRequest(Request("query", "query.close.lease.drift"));
            JObject driftQuery = harness.SentAt(2);
            JObject drift = ActiveResponseWithLoot(driftQuery, 1);
            drift["closeLease"] = "close.lease.drift";
            harness.Task.HandleFlashResponse(drift, null);

            Assert.Equal("reconcile_required", harness.Task.WriteState);
            Assert.Equal(1, harness.Task.LastAuthorityRevision);

            harness.Task.HandleWebRequest(Request("query", "query.close.lease.exact"));
            JObject exactQuery = harness.SentAt(3);
            harness.Task.HandleFlashResponse(ActiveResponseWithLoot(exactQuery, 1), null);

            Assert.Equal("idle", harness.Task.WriteState);
            Assert.Equal(1, harness.Task.LastAuthorityRevision);
        }

        [Fact]
        public void UnknownClaim_TerminalQueryRequiresRevisionAfterFrozenPrestate()
        {
            using var harness = new Harness();
            PrimeActiveAuthority(harness, true);
            harness.SendResult = false;
            JObject claim = Request("claim", "claim.terminal.revision");
            claim["expectedAuthorityRevision"] = 1;
            claim["source"]["expectedLease"] = "loot.slot.1";
            harness.Task.HandleWebRequest(claim);
            harness.SendResult = true;
            Assert.Equal("reconcile_required", harness.Task.WriteState);

            harness.Task.HandleWebRequest(Request("query", "query.claim.terminal.same"));
            JObject sameRevision = harness.SentAt(2);
            harness.Task.HandleFlashResponse(TerminalResponse(sameRevision, "",
                "EXPIRED", 1, 0), null);

            Assert.Equal("reconcile_required", harness.Task.WriteState);
            Assert.Equal(0, harness.Panel.CloseCalls);
            Assert.Equal("malformed_response",
                harness.PostedAt(2).Value<string>("error"));

            harness.Task.HandleWebRequest(Request("query", "query.claim.terminal.newer"));
            JObject newer = harness.SentAt(3);
            harness.Task.HandleFlashResponse(TerminalResponse(newer, "",
                "EXPIRED", 2, 0), null);

            Assert.Equal("idle", harness.Task.WriteState);
            Assert.Equal(2, harness.Task.LastAuthorityRevision);
            Assert.Equal(1, harness.Panel.CloseCalls);
        }

        [Fact]
        public void InvalidClaimSuccessWatermark_BlocksOldNoWriteAndAcceptsSameRevisionProof()
        {
            using var harness = new Harness();
            PrimeActiveAuthority(harness, true);
            JObject claim = Request("claim", "claim.watermark.direct");
            claim["expectedAuthorityRevision"] = 1;
            claim["source"]["expectedLease"] = "loot.slot.1";
            harness.Task.HandleWebRequest(claim);
            JObject claimFlash = harness.SentAt(1);
            JObject invalidHigh = ActiveResponseWithLoot(claimFlash, 2);
            invalidHigh["lastAppliedOperationId"] = claim.Value<string>("operationId");
            harness.Task.HandleFlashResponse(invalidHigh, null);
            Assert.Equal("reconcile_required", harness.Task.WriteState);

            harness.Task.HandleWebRequest(Request("query", "query.watermark.old.nowrite"));
            JObject oldQuery = harness.SentAt(2);
            harness.Task.HandleFlashResponse(ActiveResponseWithLoot(oldQuery, 1), null);
            Assert.Equal("reconcile_required", harness.Task.WriteState);
            Assert.Equal(1, harness.Task.LastAuthorityRevision);

            harness.Task.HandleWebRequest(Request("query", "query.watermark.exact.applied"));
            JObject exactQuery = harness.SentAt(3);
            harness.Task.HandleFlashResponse(ActiveResponse(exactQuery,
                claim.Value<string>("operationId"), 2), null);

            Assert.Equal("idle", harness.Task.WriteState);
            Assert.Equal(2, harness.Task.LastAuthorityRevision);
        }

        [Theory]
        [InlineData("extra_key")]
        [InlineData("missing_snapshots")]
        public void MalformedExactClaimResponseStillRaisesFreshnessWatermark(string corruption)
        {
            using var harness = new Harness();
            PrimeActiveAuthority(harness, true);
            JObject claim = Request("claim", "claim.watermark.shape." + corruption);
            claim["expectedAuthorityRevision"] = 1;
            claim["source"]["expectedLease"] = "loot.slot.1";
            harness.Task.HandleWebRequest(claim);
            JObject claimFlash = harness.SentAt(1);
            JObject malformedHigh = ActiveResponse(claimFlash,
                claim.Value<string>("operationId"), 2);
            if (corruption == "extra_key") malformedHigh["unexpected"] = true;
            else malformedHigh.Remove("snapshots");
            harness.Task.HandleFlashResponse(malformedHigh, null);

            Assert.Equal("reconcile_required", harness.Task.WriteState);
            Assert.Equal(1, harness.Task.LastAuthorityRevision);

            harness.Task.HandleWebRequest(Request("query",
                "query.watermark.shape.old." + corruption));
            JObject oldQuery = harness.SentAt(2);
            harness.Task.HandleFlashResponse(ActiveResponseWithLoot(oldQuery, 1), null);
            Assert.Equal("reconcile_required", harness.Task.WriteState);
            Assert.Equal(1, harness.Task.LastAuthorityRevision);

            harness.Task.HandleWebRequest(Request("query",
                "query.watermark.shape.exact." + corruption));
            JObject exactQuery = harness.SentAt(3);
            harness.Task.HandleFlashResponse(ActiveResponse(exactQuery,
                claim.Value<string>("operationId"), 2), null);
            Assert.Equal("idle", harness.Task.WriteState);
            Assert.Equal(2, harness.Task.LastAuthorityRevision);
        }

        [Fact]
        public void MalformedHighRevision_ProjectsWatermarkAndFencesUnprovenQueries()
        {
            using var harness = new Harness();
            PrimeActiveAuthority(harness, true);
            JObject claim = Request("claim", "claim.watermark.bridge");
            claim["expectedAuthorityRevision"] = 1;
            claim["source"]["expectedLease"] = "loot.slot.1";
            harness.Task.HandleWebRequest(claim);
            JObject claimFlash = harness.SentAt(1);
            JObject malformedHigh = ActiveResponse(claimFlash,
                claim.Value<string>("operationId"), 3);
            malformedHigh["unexpected"] = true;

            harness.Task.HandleFlashResponse(malformedHigh, null);

            JObject malformedError = harness.PostedAt(1);
            Assert.False(malformedError.Value<bool>("success"));
            Assert.Equal("reconcile_required", malformedError.Value<string>("error"));
            Assert.Equal(3, malformedError.Value<int>("authorityRevision"));
            Assert.Equal("reconcile_required", harness.Task.WriteState);
            Assert.Equal(1, harness.Task.LastAuthorityRevision);

            harness.Task.HandleWebRequest(Request("query", "query.watermark.bridge.active"));
            JObject activeQuery = harness.SentAt(2);
            harness.Task.HandleFlashResponse(ActiveResponse(activeQuery,
                claim.Value<string>("operationId"), 2), null);

            JObject activeError = harness.PostedAt(2);
            Assert.False(activeError.Value<bool>("success"));
            Assert.Equal("reconcile_required", activeError.Value<string>("error"));
            Assert.Equal(3, activeError.Value<int>("authorityRevision"));
            Assert.Equal("reconcile_required", harness.Task.WriteState);

            harness.Task.HandleWebRequest(Request("query", "query.watermark.bridge.terminal"));
            JObject terminalQuery = harness.SentAt(3);
            harness.Task.HandleFlashResponse(TerminalResponse(terminalQuery, "",
                "EXPIRED", 2, 0), null);

            JObject terminalError = harness.PostedAt(3);
            Assert.False(terminalError.Value<bool>("success"));
            Assert.Equal("reconcile_required", terminalError.Value<string>("error"));
            Assert.Equal(3, terminalError.Value<int>("authorityRevision"));
            Assert.Equal("reconcile_required", harness.Task.WriteState);
            Assert.Equal(0, harness.Panel.CloseCalls);

            harness.Task.HandleWebRequest(Request("query",
                "query.watermark.bridge.terminal.fresh"));
            JObject freshTerminalQuery = harness.SentAt(4);
            harness.Task.HandleFlashResponse(TerminalResponse(freshTerminalQuery, "",
                "EXPIRED", 3, 0), null);

            Assert.True(harness.PostedAt(4).Value<bool>("success"));
            Assert.Equal("idle", harness.Task.WriteState);
            Assert.Equal(3, harness.Task.LastAuthorityRevision);
            Assert.Equal(1, harness.Panel.CloseCalls);
        }

        [Fact]
        public void UnprovenHighClaimQueryWatermark_BlocksLowerExactProof()
        {
            using var harness = new Harness();
            PrimeActiveAuthority(harness, true);
            JObject claim = Request("claim", "claim.watermark.query");
            claim["expectedAuthorityRevision"] = 1;
            claim["source"]["expectedLease"] = "loot.slot.1";
            harness.Task.HandleWebRequest(claim);
            JObject claimFlash = harness.SentAt(1);
            JObject invalid = ActiveResponseWithLoot(claimFlash, 2);
            invalid["lastAppliedOperationId"] = claim.Value<string>("operationId");
            harness.Task.HandleFlashResponse(invalid, null);

            harness.Task.HandleWebRequest(Request("query", "query.watermark.high"));
            JObject highQuery = harness.SentAt(2);
            harness.Task.HandleFlashResponse(ActiveResponse(highQuery,
                claim.Value<string>("operationId"), 4), null);
            Assert.Equal("reconcile_required", harness.Task.WriteState);
            Assert.Equal(1, harness.Task.LastAuthorityRevision);

            harness.Task.HandleWebRequest(Request("query", "query.watermark.lower.exact"));
            JObject lowerQuery = harness.SentAt(3);
            harness.Task.HandleFlashResponse(ActiveResponse(lowerQuery,
                claim.Value<string>("operationId"), 2), null);

            Assert.Equal("reconcile_required", harness.Task.WriteState);
            Assert.Equal(1, harness.Task.LastAuthorityRevision);
            Assert.Equal(0, harness.Panel.CloseCalls);

            harness.Task.HandleWebRequest(Request("query", "query.watermark.terminal"));
            JObject terminalQuery = harness.SentAt(4);
            harness.Task.HandleFlashResponse(TerminalResponse(terminalQuery, "",
                "EXPIRED", 4, 0), null);
            Assert.Equal("idle", harness.Task.WriteState);
            Assert.Equal(4, harness.Task.LastAuthorityRevision);
            Assert.Equal(1, harness.Panel.CloseCalls);
        }

        [Fact]
        public void ExactActiveCapacityFailure_PreservesLease_ForStrictSuspendedClose()
        {
            using var harness = new Harness();
            PrimeActiveAuthority(harness, true);

            JObject claim = Request("claim", "claim.target.full");
            claim["expectedAuthorityRevision"] = 1;
            claim["source"]["expectedLease"] = "loot.slot.1";
            harness.Task.HandleWebRequest(claim);
            JObject claimFlash = harness.SentAt(1);
            JObject blocked = ErrorResponse(claimFlash, "target_full");
            blocked["authorityRevision"] = 1;
            blocked["remainingCount"] = 1;

            harness.Task.HandleFlashResponse(blocked, null);

            JObject postedFailure = harness.PostedAt(1);
            Assert.False(postedFailure.Value<bool>("success"));
            Assert.Equal("target_full", postedFailure.Value<string>("error"));
            Assert.Equal("LOOT_ACTIVE", postedFailure.Value<string>("state"));
            Assert.Equal("", postedFailure.Value<string>("closeLease"));

            JObject close = Request("close", "close.after.target.full");
            close["expectedAuthorityRevision"] = 1;
            close["closeLease"] = "close.lease.1";
            harness.Task.HandleWebRequest(close);

            JObject closeFlash = harness.SentAt(2);
            Assert.Equal("lootClose", closeFlash.Value<string>("action"));
            Assert.Equal("close.lease.1", closeFlash.Value<string>("closeLease"));
            harness.Task.HandleFlashResponse(SuspendedResponse(closeFlash,
                close.Value<string>("operationId"), 2, 1), null);

            Assert.Equal(1, harness.Panel.CloseCalls);
            Assert.Equal(LootPanelCoordinator.BindingState.SuspendedCloseQueued,
                harness.Coordinator.State);
            Assert.True(harness.Coordinator.IsAuthoritySuspendedCloseKnownExact(
                PanelInstanceId));

            harness.Panel.ActiveName = null;
            harness.Panel.ActiveInstance = null;
            harness.Coordinator.OnPanelHostClosed("loot", PanelInstanceId);

            Assert.Equal(1, harness.PauseReleaseCalls);
            Assert.Equal(LootPanelCoordinator.BindingState.Idle, harness.Coordinator.State);

            JObject ack = JObject.Parse(harness.Coordinator.HandlePanelRequest(
                PanelRequest(openAttemptSeq: 2)));
            Assert.True(ack.Value<bool>("accepted"));
            harness.Panel.CompleteOpenPosted();
            JObject oldAttemptClose = Request("close", "close.old.attempt.lease");
            oldAttemptClose["expectedAuthorityRevision"] = 1;
            oldAttemptClose["closeLease"] = "close.lease.1";
            harness.Task.HandleWebRequest(oldAttemptClose);

            Assert.Equal(3, harness.SentCount);
            Assert.Equal("stale_state", harness.PostedAt(3).Value<string>("error"));
        }

        [Theory]
        [InlineData("revision")]
        [InlineData("remaining")]
        [InlineData("last_applied")]
        [InlineData("state")]
        public void DriftedFailure_DropsOldLease_UntilFreshActiveQuery(string drift)
        {
            using var harness = new Harness();
            PrimeActiveAuthority(harness, true);

            JObject claim = Request("claim", "claim.drift." + drift);
            claim["expectedAuthorityRevision"] = 1;
            claim["source"]["expectedLease"] = "loot.slot.1";
            harness.Task.HandleWebRequest(claim);
            JObject claimFlash = harness.SentAt(1);
            JObject failure = ErrorResponse(claimFlash, "target_full");
            failure["authorityRevision"] = 1;
            failure["remainingCount"] = 1;
            int refreshedRevision = 2;
            string refreshedLastApplied = "";
            string expectedOldCloseError = "stale_state";

            if (drift == "revision")
            {
                failure["authorityRevision"] = 2;
                refreshedRevision = 3;
            }
            else if (drift == "remaining")
            {
                failure["remainingCount"] = 0;
            }
            else if (drift == "last_applied")
            {
                failure["lastAppliedOperationId"] = "operation.foreign.1";
                refreshedLastApplied = "operation.foreign.1";
            }
            else
            {
                failure["error"] = "commit_pending";
                failure["state"] = "LOOT_COMMIT_PENDING";
                refreshedLastApplied = claim.Value<string>("operationId");
                expectedOldCloseError = "reconcile_required";
            }

            harness.Task.HandleFlashResponse(failure, null);

            JObject oldClose = Request("close", "close.old." + drift);
            oldClose["expectedAuthorityRevision"] = 1;
            oldClose["closeLease"] = "close.lease.1";
            harness.Task.HandleWebRequest(oldClose);

            Assert.Equal(2, harness.SentCount);
            Assert.Equal(expectedOldCloseError,
                harness.PostedAt(2).Value<string>("error"));

            harness.Task.HandleWebRequest(Request("query", "query.refresh." + drift));
            JObject queryFlash = harness.SentAt(2);
            JObject refreshed = drift == "state"
                ? ActiveResponse(queryFlash, refreshedLastApplied, refreshedRevision)
                : ActiveResponseWithLoot(queryFlash, refreshedRevision);
            refreshed["lastAppliedOperationId"] = refreshedLastApplied;
            harness.Task.HandleFlashResponse(refreshed, null);

            Assert.True(harness.PostedAt(3).Value<bool>("success"));
            Assert.Equal("LOOT_ACTIVE", harness.PostedAt(3).Value<string>("state"));
            JObject freshClose = Request("close", "close.fresh." + drift);
            freshClose["expectedAuthorityRevision"] = refreshedRevision;
            freshClose["closeLease"] = "close.lease." + refreshedRevision;
            harness.Task.HandleWebRequest(freshClose);

            JObject freshCloseFlash = harness.SentAt(3);
            Assert.Equal("lootClose", freshCloseFlash.Value<string>("action"));
            Assert.Equal("close.lease." + refreshedRevision,
                freshCloseFlash.Value<string>("closeLease"));
            harness.Task.HandleFlashResponse(drift == "state"
                ? TerminalResponse(freshCloseFlash, freshClose.Value<string>("operationId"),
                    "CONSUMED", refreshedRevision + 1, 0)
                : SuspendedResponse(freshCloseFlash, freshClose.Value<string>("operationId"),
                    refreshedRevision + 1, 1), null);
            Assert.Equal(1, harness.Panel.CloseCalls);
        }

        [Fact]
        public void ConnectedRecovery_QueriesExactGenerationAfterFenceAndNeverPostsStaleWeb()
        {
            using var harness = new Harness();
            PrimeActiveAuthority(harness, true);
            JObject claimRequest = Request("claim", "claim.connected.detach");
            claimRequest["expectedAuthorityRevision"] = 1;
            claimRequest["source"]["expectedLease"] = "loot.slot.1";
            harness.Task.HandleWebRequest(claimRequest);
            JObject claim = harness.SentAt(1);
            LootPanelCoordinator.Binding binding = harness.Coordinator.ActiveBinding;

            Assert.True(harness.Task.PrepareConnectedTransportDetach(binding,
                RecoveryNonce));
            Assert.True(harness.Task.RequiresDetachedReconcile);
            Assert.False(WebOverlayForm.IsLootPauseReleaseAllowed(harness.Task));
            Assert.True(harness.Coordinator.ForceDetach("web_mount_failed"));

            // Production invokes this only after lootPanelRecovery was written to generation 1.
            harness.Task.OnConnectedTransportRecoverySent(binding, 1, RecoveryNonce);
            JObject query = WaitForSent(harness, 3);
            AssertDetachedQuery(query, 1, harness, RecoveryNonce);
            Assert.Equal("lootClaim", claim.Value<string>("action"));
            Assert.DoesNotContain(harness.Sent, value =>
                value.Value<string>("action") == "lootClose");

            harness.Task.HandleFlashResponse(TerminalResponse(query,
                "operation.claim.1", "CONSUMED", 2, 0), null);

            Assert.False(harness.Task.RequiresDetachedReconcile);
            Assert.Equal("idle", harness.Task.WriteState);
            Assert.True(WebOverlayForm.IsLootPauseReleaseAllowed(harness.Task));
            Assert.Equal(1, harness.DetachedReconcileSettled);
            Assert.Equal(1, harness.PostedCount);
        }

        [Fact]
        public void ConnectedRecovery_StaleGenerationCannotQueryOrSettleReplacement()
        {
            using var harness = new Harness();
            LootPanelCoordinator.Binding binding = harness.Coordinator.ActiveBinding;
            Assert.True(harness.Task.PrepareConnectedTransportDetach(binding,
                RecoveryNonce));
            Assert.True(harness.Coordinator.ForceDetach("web_navigation"));

            // Recovery was sent on generation 1, but generation 2 replaced it before the query.
            harness.Generation = 2;
            harness.Task.OnConnectedTransportRecoverySent(binding, 1, RecoveryNonce);
            JObject query = WaitForSent(harness, 1);
            AssertDetachedQuery(query, 2, harness);
            Assert.NotEqual(RecoveryNonce, query.Value<string>("recoveryNonce"));
            Assert.True(harness.Task.RequiresDetachedReconcile);
            Assert.False(WebOverlayForm.IsLootPauseReleaseAllowed(harness.Task));

            // The generation-1 disconnect notification can arrive after the send callback has
            // already observed generation 2. It was atomically claimed during downgrade and may
            // neither rotate the socket nonce nor cancel the generation-2 query.
            harness.Task.OnSocketTransportDetached(1);
            Assert.Equal(1, harness.SentCount);
            Assert.Equal(query.Value<string>("recoveryNonce"),
                harness.SentAt(0).Value<string>("recoveryNonce"));
            // A generic ready notification for the same generation is also idempotent.
            harness.Task.OnSocketReconnected();
            Assert.Equal(1, harness.SentCount);
            harness.Task.HandleFlashResponse(SuspendedResponse(query,
                "operation.recovery.suspended", 1, 1), null);

            Assert.False(harness.Task.RequiresDetachedReconcile);
            Assert.True(WebOverlayForm.IsLootPauseReleaseAllowed(harness.Task));
            Assert.Equal(1, harness.DetachedReconcileSettled);
            Assert.Equal(0, harness.PostedCount);
        }

        [Fact]
        public void ConnectedRecovery_FailedProofRetriesUntilExactSuspendedProof()
        {
            using var harness = new Harness(retryInitialMs: 10, retryMaximumMs: 20);
            LootPanelCoordinator.Binding binding = harness.Coordinator.ActiveBinding;
            Assert.True(harness.Task.PrepareConnectedTransportDetach(binding,
                RecoveryNonce));
            Assert.True(harness.Coordinator.ForceDetach("web_mount_failed"));
            harness.Task.OnConnectedTransportRecoverySent(binding, 1, RecoveryNonce);
            JObject pendingQuery = WaitForSent(harness, 1);
            AssertDetachedQuery(pendingQuery, 1, harness, RecoveryNonce);

            harness.Task.HandleFlashResponse(ErrorResponse(pendingQuery,
                "recovery_pending"), null);

            Assert.True(harness.Task.RequiresDetachedReconcile);
            Assert.Equal(0, harness.DetachedReconcileSettled);
            JObject appliedQuery = WaitForSent(harness, 2);
            AssertDetachedQuery(appliedQuery, 1, harness, RecoveryNonce);
            harness.Task.HandleFlashResponse(SuspendedResponse(appliedQuery,
                "operation.recovery.suspended", 1, 1), null);
            Assert.False(harness.Task.RequiresDetachedReconcile);
            Assert.Equal(1, harness.DetachedReconcileSettled);
            Assert.Equal(0, harness.PostedCount);
        }

        [Fact]
        public void SocketRecovery_StaleTerminalFailureCannotSettleUntilExactSuccess()
        {
            using var harness = new Harness(retryInitialMs: 10, retryMaximumMs: 20);
            harness.Task.OnSocketTransportDetached(harness.Generation);
            harness.Generation = 2;
            harness.Task.OnSocketReconnected();
            JObject rejectedQuery = WaitForSent(harness, 1);
            AssertDetachedQuery(rejectedQuery, 2, harness);
            JObject rejectedTerminal = TerminalResponse(rejectedQuery, "",
                "EXPIRED", 1, 0);
            rejectedTerminal["success"] = false;
            rejectedTerminal["error"] = "stale_recovery_proof";

            harness.Task.HandleFlashResponse(rejectedTerminal, null);

            Assert.True(harness.Task.RequiresDetachedReconcile);
            Assert.True(harness.Task.HasRecoveryFence);
            Assert.Equal(0, harness.DetachedReconcileSettled);
            Assert.Equal(0, harness.Panel.CloseCalls);
            JObject retry = WaitForSent(harness, 2);
            AssertDetachedQuery(retry, 2, harness,
                rejectedQuery.Value<string>("recoveryNonce"));

            harness.Task.HandleFlashResponse(TerminalResponse(retry, "",
                "EXPIRED", 1, 0), null);

            Assert.False(harness.Task.RequiresDetachedReconcile);
            Assert.False(harness.Task.HasRecoveryFence);
            Assert.Equal(1, harness.DetachedReconcileSettled);
            Assert.Equal(0, harness.Panel.CloseCalls);
        }

        [Fact]
        public void ConnectedRecovery_ExactAppliedSuspendedProofSettles()
        {
            using var harness = new Harness();
            LootPanelCoordinator.Binding binding = harness.Coordinator.ActiveBinding;
            Assert.True(harness.Task.PrepareConnectedTransportDetach(binding,
                RecoveryNonce));
            Assert.True(harness.Coordinator.ForceDetach("web_mount_failed"));
            harness.Task.OnConnectedTransportRecoverySent(binding, 1, RecoveryNonce);
            JObject query = WaitForSent(harness, 1);
            AssertDetachedQuery(query, 1, harness, RecoveryNonce);

            harness.Task.HandleFlashResponse(SuspendedResponse(query,
                "operation.reopen.suspended", 1, 1), null);

            Assert.False(harness.Task.RequiresDetachedReconcile);
            Assert.Equal(1, harness.DetachedReconcileSettled);
            Assert.True(harness.Task.IsAuthorityVisualCloseProvenExact(binding));
            Assert.Equal(0, harness.PostedCount);
        }

        [Fact]
        public void SocketDetach_DuplicateOldGenerationCannotRotateOrCancelFreshQuery()
        {
            using var harness = new Harness();
            harness.Task.OnSocketTransportDetached(1);
            harness.Generation = 2;
            harness.Task.OnSocketReconnected();
            JObject query = WaitForSent(harness, 1);
            string nonce = query.Value<string>("recoveryNonce");
            AssertDetachedQuery(query, 2, harness, nonce);

            harness.Task.OnSocketTransportDetached(1);

            Assert.Equal(1, harness.SentCount);
            Assert.Equal(nonce, harness.SentAt(0).Value<string>("recoveryNonce"));
            Assert.True(harness.Task.RequiresDetachedReconcile);
            harness.Task.HandleFlashResponse(SuspendedResponse(query,
                "operation.recovery.suspended", 1, 1), null);
            Assert.False(harness.Task.RequiresDetachedReconcile);
            Assert.Equal(1, harness.DetachedReconcileSettled);
        }

        [Fact]
        public void SocketDetach_AfterReadyAndCoordinatorIdleReusesPreparedBindingAndDispatches()
        {
            using var harness = new Harness();
            LootPanelCoordinator.Binding binding = harness.Coordinator.ActiveBinding;
            Assert.True(harness.Task.PrepareConnectedTransportDetach(binding,
                RecoveryNonce));
            Assert.True(harness.Coordinator.ForceDetach("socket_disconnected"));
            harness.Panel.ActiveName = null;
            harness.Panel.ActiveInstance = null;
            harness.Coordinator.OnPanelHostClosed("loot", PanelInstanceId);
            Assert.Null(harness.Coordinator.ActiveBinding);
            Assert.True(harness.Task.RequiresDetachedReconcile);

            // UI dispatch can reorder these callbacks: ready generation 2 is observed before the
            // delayed generation-1 disconnect notification. The latter must switch the existing
            // detached binding to socket proof and immediately start the already-ready query.
            harness.Generation = 2;
            harness.Task.OnSocketReconnected();
            Assert.Equal(0, harness.SentCount);
            harness.Task.OnSocketTransportDetached(1);

            JObject query = WaitForSent(harness, 1);
            AssertDetachedQuery(query, 2, harness);
            Assert.NotEqual(RecoveryNonce, query.Value<string>("recoveryNonce"));
            harness.Task.HandleFlashResponse(SuspendedResponse(query,
                "operation.recovery.suspended", 1, 1), null);
            Assert.False(harness.Task.RequiresDetachedReconcile);
            Assert.Equal(1, harness.DetachedReconcileSettled);
        }

        [Fact]
        public void SocketReconnect_ActiveProjectionCannotReleaseDetachedFence()
        {
            using var harness = new Harness();
            harness.Task.HandleWebRequest(Request("snapshot", "snapshot.before.detach"));
            JObject snapshot = Assert.Single(harness.Sent);
            harness.Task.HandleFlashResponse(ActiveResponse(snapshot, "", 1), null);
            Assert.Equal(1, harness.PostedCount);

            DetachSocketLoot(harness);
            harness.Generation = 2;
            harness.Task.OnSocketReconnected();
            JObject query = WaitForSent(harness, 2);
            AssertDetachedQuery(query, 2, harness);

            // A detached document cannot own an ACTIVE projection. Even a fresh success response
            // keeps the recovery fence and forces another exact query.
            harness.Task.HandleFlashResponse(ActiveResponse(query, "", 2), null);

            Assert.True(harness.Task.RequiresDetachedReconcile);
            Assert.Equal(0, harness.DetachedReconcileSettled);
            JObject terminalQuery = WaitForSent(harness, 3);
            AssertDetachedQuery(terminalQuery, 2, harness,
                query.Value<string>("recoveryNonce"));
            harness.Task.HandleFlashResponse(TerminalResponse(terminalQuery, "",
                "CONSUMED", 3, 0), null);

            Assert.False(harness.Task.RequiresDetachedReconcile);
            Assert.Equal("idle", harness.Task.WriteState);
            Assert.Equal(1, harness.DetachedReconcileSettled);
            Assert.Equal(1, harness.PostedCount);
        }

        [Fact]
        public void SocketReconnect_InternalQueryNeverPostsEvenIfNativeDetachIsStillQueued()
        {
            using var harness = new Harness();
            harness.Task.OnSocketTransportDetached(harness.Generation);
            Assert.True(harness.Task.RequiresDetachedReconcile);
            Assert.NotEqual(LootPanelCoordinator.BindingState.Idle, harness.Coordinator.State);
            harness.Generation = 2;

            harness.Task.OnSocketReconnected();
            JObject query = WaitForSent(harness, 1);
            harness.Task.HandleFlashResponse(SuspendedResponse(query,
                "operation.recovery.suspended", 1, 1), null);

            Assert.Equal(0, harness.PostedCount);
            Assert.False(harness.Task.RequiresDetachedReconcile);
            Assert.Equal(1, harness.DetachedReconcileSettled);
        }

        [Fact]
        public void SocketReconnect_ExactNonceSuspendedProofSettlesDetachedAuthority()
        {
            using var harness = new Harness(retryInitialMs: 1000, retryMaximumMs: 1000);
            harness.Task.OnSocketTransportDetached(harness.Generation);
            Assert.True(harness.Task.RequiresDetachedReconcile);
            harness.Generation = 2;

            harness.Task.OnSocketReconnected();
            JObject query = WaitForSent(harness, 1);
            AssertDetachedQuery(query, 2, harness);
            harness.Task.HandleFlashResponse(SuspendedResponse(query,
                "operation.close.suspended", 2, 1), null);

            Assert.Equal(0, harness.PostedCount);
            Assert.False(harness.Task.RequiresDetachedReconcile);
            Assert.Equal("idle", harness.Task.WriteState);
            Assert.Equal(1, harness.DetachedReconcileSettled);
            Assert.Equal(0, harness.Panel.CloseCalls);
        }

        [Fact]
        public void SocketReconnect_ExactUnknownCloseSuspendedProofSettlesDetachedAuthority()
        {
            using var harness = new Harness(timeoutMs: 40,
                retryInitialMs: 1000, retryMaximumMs: 1000);
            PrimeActiveAuthority(harness, true);
            JObject close = Request("close", "close.detached.suspended");
            close["expectedAuthorityRevision"] = 1;
            harness.Task.HandleWebRequest(close);
            Assert.True(SpinWait.SpinUntil(delegate { return harness.PostedCount == 2; },
                2000));
            Assert.Equal("reconcile_required", harness.Task.WriteState);

            DetachSocketLoot(harness);
            harness.Generation = 2;
            harness.Task.OnSocketReconnected();
            JObject query = WaitForSent(harness, 3);
            AssertDetachedQuery(query, 2, harness);
            harness.Task.HandleFlashResponse(SuspendedResponse(query,
                close.Value<string>("operationId"), 2, 1), null);

            Assert.False(harness.Task.RequiresDetachedReconcile);
            Assert.Equal("idle", harness.Task.WriteState);
            Assert.Equal(1, harness.DetachedReconcileSettled);
            Assert.Equal(2, harness.PostedCount);
            Assert.Equal(1, harness.Sent.Count(value =>
                value.Value<string>("action") == "lootClose"));
        }

        [Fact]
        public void ForceDetach_RacingAuthorityProofPreventsDetachedReconcileFence()
        {
            Harness harness = null;
            JObject closeResponse = null;
            int recoveryCalls = 0;
            try
            {
                harness = new Harness(requestRecovery: delegate(
                    LootPanelCoordinator.Binding binding, string reason)
                {
                    recoveryCalls++;
                    Assert.Equal("web_mount_failed", reason);
                    // Simulate the socket response winning after ForceDetach selected recovery,
                    // but before the recovery delegate can prepare its authority handoff.
                    harness.Task.HandleFlashResponse(closeResponse, null);
                    Assert.True(harness.Task.IsAuthorityVisualCloseProvenExact(binding));
                    Assert.False(harness.Task.PrepareConnectedTransportDetach(binding,
                        RecoveryNonce));
                    return true;
                });
                PrimeActiveAuthority(harness, true);
                JObject close = Request("close", "close.force.detach.race");
                close["expectedAuthorityRevision"] = 1;
                harness.Task.HandleWebRequest(close);
                closeResponse = SuspendedResponse(harness.Sent[1],
                    close.Value<string>("operationId"), 2, 1);

                Assert.True(harness.Coordinator.ForceDetach("web_mount_failed"));

                Assert.Equal(1, recoveryCalls);
                Assert.False(harness.Task.RequiresDetachedReconcile);
                Assert.Equal("idle", harness.Task.WriteState);
                Assert.True(harness.Task.IsAuthorityVisualCloseProvenExact(
                    harness.Coordinator.ActiveBinding));
                Assert.Equal(LootPanelCoordinator.BindingState.SuspendedCloseQueued,
                    harness.Coordinator.State);
                Assert.Equal(1, harness.Panel.CloseCalls);
            }
            finally
            {
                if (harness != null) harness.Dispose();
            }
        }

        [Fact]
        public void SocketReconnect_LateVisualDetachProofDoesNotCancelInternalQuery()
        {
            using var harness = new Harness();
            harness.Task.OnSocketTransportDetached(harness.Generation);
            Assert.True(harness.Coordinator.ForceDetach("socket_disconnected"));
            harness.Generation = 2;
            harness.Task.OnSocketReconnected();
            JObject query = WaitForSent(harness, 1);

            harness.Panel.ActiveName = null;
            harness.Panel.ActiveInstance = null;
            harness.Coordinator.OnPanelHostClosed("loot", PanelInstanceId);
            Assert.Equal(1, harness.Task.PendingCount);

            harness.Task.HandleFlashResponse(SuspendedResponse(query,
                "operation.recovery.suspended", 1, 1), null);
            Assert.False(harness.Task.RequiresDetachedReconcile);
            Assert.Equal(0, harness.Task.PendingCount);
            Assert.Equal(1, harness.DetachedReconcileSettled);
        }

        [Fact]
        public void SocketReconnect_KnownCommitPendingAcceptsExactTerminalProof()
        {
            using var harness = new Harness();
            PrimeActiveAuthority(harness, true);
            JObject claimRequest = Request("claim", "claim.detach.terminal");
            claimRequest["expectedAuthorityRevision"] = 1;
            claimRequest["source"]["expectedLease"] = "loot.slot.1";
            harness.Task.HandleWebRequest(claimRequest);
            JObject claim = harness.SentAt(1);
            JObject pending = CommitPendingResponse(claim);
            pending["remainingCount"] = 1;
            harness.Task.HandleFlashResponse(pending, null);

            DetachSocketLoot(harness);
            harness.Generation = 2;
            harness.Task.OnSocketReconnected();
            JObject query = WaitForSent(harness, 3);
            harness.Task.HandleFlashResponse(TerminalResponse(query,
                "operation.claim.1", "CONSUMED", 2, 0), null);

            Assert.False(harness.Task.RequiresDetachedReconcile);
            Assert.Equal("idle", harness.Task.WriteState);
            Assert.Equal(1, harness.DetachedReconcileSettled);
            Assert.Equal(2, harness.PostedCount);
        }

        [Fact]
        public void SocketReconnect_PendingAndWrongOperationKeepFenceUntilOriginalOperation()
        {
            using var harness = new Harness(timeoutMs: 1000, retryInitialMs: 10,
                retryMaximumMs: 20);
            PrimeActiveAuthority(harness, true);
            JObject claimRequest = Request("claim", "claim.detach.causal");
            claimRequest["expectedAuthorityRevision"] = 1;
            claimRequest["source"]["expectedLease"] = "loot.slot.1";
            harness.Task.HandleWebRequest(claimRequest);
            JObject claim = harness.SentAt(1);
            JObject pending = CommitPendingResponse(claim);
            pending["remainingCount"] = 1;
            harness.Task.HandleFlashResponse(pending, null);
            DetachSocketLoot(harness);
            harness.Generation = 2;

            harness.Task.OnSocketReconnected();
            JObject pendingQuery = WaitForSent(harness, 3);
            JObject pendingAgain = CommitPendingResponse(pendingQuery);
            pendingAgain["remainingCount"] = 1;
            harness.Task.HandleFlashResponse(pendingAgain, null);
            JObject wrongOperationQuery = WaitForSent(harness, 4);
            harness.Task.HandleFlashResponse(ActiveResponse(wrongOperationQuery,
                "operation.claim.other", 2), null);

            Assert.True(harness.Task.RequiresDetachedReconcile);
            Assert.Equal("reconcile_required", harness.Task.WriteState);
            Assert.Equal(0, harness.DetachedReconcileSettled);

            JObject causalQuery = WaitForSent(harness, 5);
            harness.Task.HandleFlashResponse(TerminalResponse(causalQuery,
                "operation.claim.1", "CONSUMED", 2, 0), null);
            Assert.False(harness.Task.RequiresDetachedReconcile);
            Assert.Equal("idle", harness.Task.WriteState);
            Assert.Equal(1, harness.DetachedReconcileSettled);
            Assert.Equal(2, harness.PostedCount);
        }

        [Fact]
        public void SocketReconnect_SendFalseRetriesReadOnlyQueryOnSameGeneration()
        {
            using var harness = new Harness(timeoutMs: 1000, retryInitialMs: 10,
                retryMaximumMs: 20);
            DetachSocketLoot(harness);
            harness.Generation = 2;
            harness.SendResult = false;
            harness.Task.OnSocketReconnected();
            JObject failedQuery = WaitForSent(harness, 1);
            AssertDetachedQuery(failedQuery, 2, harness);

            harness.SendResult = true;
            JObject retry = WaitForSent(harness, 2);
            AssertDetachedQuery(retry, 2, harness);
            harness.Task.HandleFlashResponse(SuspendedResponse(retry,
                "operation.recovery.suspended", 1, 1), null);

            Assert.False(harness.Task.RequiresDetachedReconcile);
            Assert.Equal(1, harness.DetachedReconcileSettled);
            Assert.All(harness.Sent, value => Assert.Equal("lootQuery",
                value.Value<string>("action")));
        }

        [Fact]
        public void SocketReconnect_QueryTimeoutRetriesSingleFlight()
        {
            using var harness = new Harness(timeoutMs: 20, retryInitialMs: 10,
                retryMaximumMs: 20);
            DetachSocketLoot(harness);
            harness.Generation = 2;
            harness.Task.OnSocketReconnected();
            JObject first = WaitForSent(harness, 1);
            AssertDetachedQuery(first, 2, harness);

            JObject retry = WaitForSent(harness, 2);
            Assert.NotEqual(first.Value<int>("callId"), retry.Value<int>("callId"));
            harness.Task.HandleFlashResponse(SuspendedResponse(retry,
                "operation.recovery.suspended", 1, 1), null);

            Assert.False(harness.Task.RequiresDetachedReconcile);
            Assert.Equal(1, harness.DetachedReconcileSettled);
        }

        [Fact]
        public void SocketReconnect_StaleGenerationResponseCannotSettleFreshGeneration()
        {
            using var harness = new Harness(timeoutMs: 1000, retryInitialMs: 20,
                retryMaximumMs: 20);
            DetachSocketLoot(harness);
            harness.Generation = 2;
            harness.Task.OnSocketReconnected();
            JObject stale = WaitForSent(harness, 1);

            harness.Ready = false;
            harness.Task.OnSocketTransportDetached(harness.Generation);
            harness.Generation = 3;
            harness.Ready = true;
            harness.Task.OnSocketReconnected();
            JObject fresh = WaitForSent(harness, 2);
            AssertDetachedQuery(fresh, 3, harness);

            harness.Task.HandleFlashResponse(ActiveResponse(stale, "", 1), null);
            Assert.True(harness.Task.RequiresDetachedReconcile);
            Assert.Equal(0, harness.DetachedReconcileSettled);

            harness.Task.HandleFlashResponse(SuspendedResponse(fresh,
                "operation.recovery.suspended", 1, 1), null);
            Assert.False(harness.Task.RequiresDetachedReconcile);
            Assert.Equal(1, harness.DetachedReconcileSettled);
        }

        [Fact]
        public void SocketReconnect_FreshIdentityIsFlowBusyUntilOldTerminalProof()
        {
            const string freshChest = "chest.session.2";
            const string freshLoot = "loot.container.2";
            const int freshEpoch = 8;
            using var harness = new Harness();
            PrimeActiveAuthority(harness, true);
            JObject oldClaim = Request("claim", "claim.old.pending");
            oldClaim["expectedAuthorityRevision"] = 1;
            oldClaim["source"]["expectedLease"] = "loot.slot.1";
            harness.Task.HandleWebRequest(oldClaim);
            JObject claim = harness.SentAt(1);
            JObject pending = CommitPendingResponse(claim);
            pending["remainingCount"] = 1;
            harness.Task.HandleFlashResponse(pending, null);
            DetachSocketLoot(harness);
            harness.Generation = 2;
            harness.Task.OnSocketReconnected();
            JObject oldQuery = WaitForSent(harness, 3);

            JObject ack = JObject.Parse(harness.Coordinator.HandlePanelRequest(
                PanelRequest(freshChest, freshLoot, freshEpoch)));
            Assert.False(ack.Value<bool>("accepted"));
            Assert.Equal("flow_busy", ack.Value<string>("error"));
            Assert.Null(harness.Coordinator.ActiveBinding);
            Assert.Equal(3, harness.SentCount);

            harness.Task.HandleFlashResponse(TerminalResponse(oldQuery,
                "operation.claim.1", "CONSUMED", 2, 0), null);
            JObject admitted = JObject.Parse(harness.Coordinator.HandlePanelRequest(
                PanelRequest(freshChest, freshLoot, freshEpoch)));
            Assert.True(admitted.Value<bool>("accepted"));
            harness.Panel.CompleteOpenPosted();
            JObject freshSnapshotRequest = Request("snapshot", "snapshot.fresh.prime",
                freshChest, freshLoot, freshEpoch);
            harness.Task.HandleWebRequest(freshSnapshotRequest);
            JObject freshSnapshot = harness.SentAt(3);
            JObject freshActive = ActiveResponseWithLoot(freshSnapshot, 1);
            freshActive["chestSessionId"] = freshChest;
            freshActive["lootContainerId"] = freshLoot;
            freshActive["containerEpoch"] = freshEpoch;
            ((JObject)freshActive["snapshots"][0])["containerId"] = freshLoot;
            freshActive["snapshots"][0]["containerEpoch"] = freshEpoch;
            harness.Task.HandleFlashResponse(freshActive, null);
            JObject freshClaim = Request("claim", "claim.fresh.allowed",
                freshChest, freshLoot, freshEpoch, "operation.claim.fresh.2");
            freshClaim["expectedAuthorityRevision"] = 1;
            freshClaim["source"]["expectedLease"] = "loot.slot.1";
            harness.Task.HandleWebRequest(freshClaim);

            Assert.Equal(5, harness.SentCount);
            Assert.Equal("lootClaim", harness.SentAt(4).Value<string>("action"));
            Assert.Equal(freshChest, harness.SentAt(4).Value<string>("chestSessionId"));
            Assert.Equal(1, harness.DetachedReconcileSettled);
        }

        [Fact]
        public void TransportDetach_NeverSynthesizesLootClose_AndDropsLateResponse()
        {
            using var harness = new Harness();
            PrimeActiveAuthority(harness, true);
            JObject claim = Request("claim", "claim.detach");
            claim["expectedAuthorityRevision"] = 1;
            claim["source"]["expectedLease"] = "loot.slot.1";
            harness.Task.HandleWebRequest(claim);
            JObject flash = harness.SentAt(1);

            DetachSocketLoot(harness);

            Assert.Equal("reconcile_required", harness.Task.WriteState);
            Assert.Equal(1, harness.Panel.CloseCalls);
            Assert.Equal(2, harness.SentCount);
            Assert.DoesNotContain(harness.Sent, value => value.Value<string>("action") == "lootClose");

            harness.Task.HandleFlashResponse(ActiveResponse(flash,
                claim.Value<string>("operationId")), null);
            Assert.Equal(1, harness.PostedCount);
        }
    }
}
