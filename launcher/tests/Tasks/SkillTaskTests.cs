using System;
using System.Collections.Generic;
using System.Threading;
using Newtonsoft.Json.Linq;
using Xunit;
using CF7Launcher.Guardian;
using CF7Launcher.Tasks;

namespace Launcher.Tests.Tasks
{
    public sealed class SkillTaskTests
    {
        [Theory]
        [InlineData("snapshot", "skillSnapshot")]
        [InlineData("learnPreview", "skillLearnPreview")]
        [InlineData("equip", "skillEquip")]
        [InlineData("unequip", "skillUnequip")]
        [InlineData("moveSlot", "skillMoveSlot")]
        [InlineData("setPassive", "skillSetPassive")]
        [InlineData("reorder", "skillReorder")]
        public void StrictEnvelope_MapsOnlyNormalizedPayload(string cmd, string expectedAction)
        {
            string sent = null;
            using (var task = NewTask(value => { sent = value; return true; }))
            {
                if (cmd == "learnPreview") BindTrainerContext(task);
                task.HandleWebRequest(cmd, Request(cmd, "skill.map." + cmd));
                JObject flash = JObject.Parse(sent.TrimEnd('\0'));
                Assert.Equal(expectedAction, (string)flash["action"]);
                Assert.Equal(1, (int)flash["v"]);
                Assert.Null(flash["payload"]);
                Assert.Null(flash["domain"]);
                Assert.Equal(cmd == "learnPreview" ? "trainer" : "manage", (string)flash["view"]);
                if (cmd == "learnPreview") Assert.Equal("trainer.one", (string)flash["trainerSession"]);
                Assert.Equal(cmd == "learnPreview" ? "skills.instance.trainer" : "skills.instance.1",
                    (string)flash["panelInstanceId"]);
                if (cmd == "moveSlot")
                {
                    Assert.Equal(4, (int)flash["sourceSlot"]);
                    Assert.Equal(9, (int)flash["targetSlot"]);
                    Assert.Equal(12, (int)flash["expectedRevision"]);
                }
            }
        }

        [Fact]
        public void StrictEnvelope_RejectsUnknownTopAndPayloadKeys()
        {
            var sent = new List<string>();
            var web = new List<JObject>();
            using (var task = NewTask(value => { sent.Add(value); return true; }, web))
            {
                JObject top = Request("snapshot", "skill.bad.top");
                top["action"] = "skillEquip";
                task.HandleWebRequest("snapshot", top);
                Assert.Equal("invalid_payload", (string)web[0]["error"]);

                JObject payload = Request("equip", "skill.bad.payload");
                payload["payload"]["unexpected"] = true;
                task.HandleWebRequest("equip", payload);
                Assert.Equal("invalid_payload", (string)web[1]["error"]);
                Assert.Empty(sent);
            }
        }

        [Fact]
        public void MoveSlot_RejectsOutOfRangePhysicalSlotsBeforeFlashDispatch()
        {
            var sent = new List<string>();
            var web = new List<JObject>();
            using (var task = NewTask(value => { sent.Add(value); return true; }, web))
            {
                JObject badSource = Request("moveSlot", "skill.move.bad.source");
                badSource["payload"]["sourceSlot"] = 0;
                task.HandleWebRequest("moveSlot", badSource);

                JObject badTarget = Request("moveSlot", "skill.move.bad.target");
                badTarget["payload"]["targetSlot"] = 13;
                task.HandleWebRequest("moveSlot", badTarget);

                Assert.Empty(sent);
                Assert.Equal(2, web.Count);
                Assert.All(web, response => Assert.Equal("invalid_payload", (string)response["error"]));
            }
        }

        [Fact]
        public void DuplicateActiveOrRecentCallId_IsNotRedispatchedOrDoubleSettled()
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            using (var task = NewTask(value => { sent.Add(ParseWire(value)); return true; }, web))
            {
                JObject request = Request("snapshot", "skill.call.duplicate");
                task.HandleWebRequest("snapshot", request);
                task.HandleWebRequest("snapshot", (JObject)request.DeepClone());
                Assert.Single(sent);
                Assert.Empty(web);

                JObject snapshot = Snapshot(12, null, null);
                snapshot["task"] = "skill_response";
                snapshot["callId"] = (int)sent[0]["callId"];
                task.HandleFlashResponse(snapshot, null);
                task.HandleWebRequest("snapshot", (JObject)request.DeepClone());

                Assert.Single(sent);
                Assert.Single(web);
                Assert.Equal("skill.call.duplicate", (string)web[0]["callId"]);
            }
        }

        [Fact]
        public void DelayedOldInstanceRequests_AreRejectedAfterSameViewRebindWithoutFlashDispatch()
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            using (var task = NewTask(value => { sent.Add(ParseWire(value)); return true; }, web))
            {
                JObject delayedWrite = Request("equip", "skill.old.instance.write");
                JObject delayedRead = Request("snapshot", "skill.old.instance.read");
                task.EnrichPanelInitData("{\"view\":\"manage\"}");
                task.BindPanelInstance("skills.instance.2");
                int before = sent.Count;

                task.HandleWebRequest("equip", delayedWrite);
                task.HandleWebRequest("snapshot", delayedRead);

                Assert.Equal(before, sent.Count);
                Assert.Equal("panel_instance_expired", (string)web[0]["error"]);
                Assert.Equal("panel_instance_expired", (string)web[1]["error"]);
            }
        }

        [Fact]
        public void ResponseSchema_RejectsUnknownBusinessKeysButOverwritesKnownRoutingKeys()
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            using (var task = NewTask(value => { sent.Add(ParseWire(value)); return true; }, web))
            {
                task.HandleWebRequest("snapshot", Request("snapshot", "skill.response.bad"));
                JObject bad = Snapshot(12, null, null);
                bad["task"] = "skill_response"; bad["callId"] = (int)sent[0]["callId"]; bad["extra"] = true;
                task.HandleFlashResponse(bad, null);
                Assert.Equal("malformed_response", (string)web[0]["error"]);

                task.HandleWebRequest("snapshot", Request("snapshot", "skill.response.routing"));
                JObject routed = Snapshot(12, null, null);
                routed["task"] = "skill_response"; routed["callId"] = (int)sent[1]["callId"];
                routed["type"] = "forged"; routed["panel"] = "forged"; routed["domain"] = "forged";
                routed["cmd"] = "equip"; routed["panelInstanceId"] = "forged"; routed["writeEpoch"] = 999;
                task.HandleFlashResponse(routed, null);
                Assert.True((bool)web[1]["success"]);
                Assert.Equal("skills", (string)web[1]["panel"]);
                Assert.Equal("snapshot", (string)web[1]["cmd"]);
                Assert.Equal("skills.instance.1", (string)web[1]["panelInstanceId"]);
                Assert.Equal(0, (int)web[1]["writeEpoch"]);
            }
        }

        [Fact]
        public void NoOpWrite_IsDefinitiveAndDoesNotEnterReconcile()
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            using (var task = NewTask(value => { sent.Add(ParseWire(value)); return true; }, web))
            {
                task.HandleWebRequest("equip", Request("equip", "skill.noop"));
                JObject response = WriteSuccess((int)sent[0]["callId"], false, 12, Snapshot(12, 4, "闪现"));
                task.HandleFlashResponse(response, null);

                Assert.Equal("idle", task.WriteState);
                Assert.False((bool)web[0]["changed"]);
                Assert.Null(web[0]["requiresReconcile"]);
                Assert.Equal(1, (int)web[0]["writeEpoch"]);
            }
        }

        [Fact]
        public void UnknownWriteError_RequiresReconcileAndBlocksFurtherWrites()
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            using (var task = NewTask(value => { sent.Add(ParseWire(value)); return true; }, web))
            {
                task.HandleWebRequest("equip", Request("equip", "skill.unknown.1"));
                task.HandleFlashResponse(ErrorResponse((int)sent[0]["callId"], "future_error", 12), null);
                Assert.Equal("needs_reconcile", task.WriteState);
                Assert.True((bool)web[0]["requiresReconcile"]);

                task.HandleWebRequest("unequip", Request("unequip", "skill.unknown.2"));
                Assert.Equal("reconcile_required", (string)web[1]["error"]);
                Assert.Single(sent);
            }
        }

        [Fact]
        public void AllowlistedWriteRejection_IsDefinitiveAndReturnsIdle()
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            using (var task = NewTask(value => { sent.Add(ParseWire(value)); return true; }, web))
            {
                task.HandleWebRequest("equip", Request("equip", "skill.reject.stale"));
                task.HandleFlashResponse(ErrorResponse((int)sent[0]["callId"], "stale_state", 13), null);
                Assert.Equal("idle", task.WriteState);
                Assert.Equal("stale_state", (string)web[0]["error"]);
                Assert.Null(web[0]["requiresReconcile"]);
            }
        }

        [Fact]
        public void LearnCommit_IsBoundToAuthoritativePreviewTokenAndExpectedLevel()
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            using (var task = NewTask(value => { sent.Add(ParseWire(value)); return true; }, web))
            {
                BindTrainerContext(task);
                JObject preview = Request("learnPreview", "skill.preview.bind");
                preview["payload"]["desiredLevel"] = 2;
                task.HandleWebRequest("learnPreview", preview);
                task.HandleFlashResponse(PreviewResponse((int)sent[0]["callId"], "learn.bound", 2), null);

                JObject commit = Request("learnCommit", "skill.commit.bound");
                commit["payload"]["expectedLearnToken"] = "learn.bound";
                task.HandleWebRequest("learnCommit", commit);
                JObject wrong = WriteSuccess((int)sent[1]["callId"], true, 13, Snapshot(13, null, null));
                task.HandleFlashResponse(wrong, null);

                Assert.Equal("needs_reconcile", task.WriteState);
                Assert.Equal("malformed_response", (string)web[1]["error"]);
                Assert.True((bool)web[1]["requiresReconcile"]);
            }
        }

        [Fact]
        public void LearnPreview_LatestRequestSupersedesPendingPreviewAndOnlyLatestTokenCanCommit()
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            using (var task = NewTask(value => { sent.Add(ParseWire(value)); return true; }, web))
            {
                BindTrainerContext(task);
                JObject first = Request("learnPreview", "skill.preview.first");
                JObject second = Request("learnPreview", "skill.preview.second");
                second["payload"]["desiredLevel"] = 2;
                task.HandleWebRequest("learnPreview", first);
                task.HandleWebRequest("learnPreview", second);

                Assert.Equal(2, sent.Count);
                Assert.Equal(1, task.PendingCount);
                task.HandleFlashResponse(PreviewResponse((int)sent[0]["callId"], "learn.first", 1), null);
                Assert.Empty(web);
                task.HandleFlashResponse(PreviewResponse((int)sent[1]["callId"], "learn.second", 2), null);
                Assert.Single(web);
                Assert.Equal("skill.preview.second", (string)web[0]["callId"]);

                JObject staleCommit = Request("learnCommit", "skill.commit.first.token");
                staleCommit["payload"]["expectedLearnToken"] = "learn.first";
                task.HandleWebRequest("learnCommit", staleCommit);
                Assert.Equal("invalid_payload", (string)web[1]["error"]);
                JObject latestCommit = Request("learnCommit", "skill.commit.second.token");
                latestCommit["payload"]["expectedLearnToken"] = "learn.second";
                task.HandleWebRequest("learnCommit", latestCommit);
                Assert.Equal("skillLearnCommit", (string)sent[2]["action"]);
            }
        }

        [Fact]
        public void LearnCommit_UnknownOrConsumedTokenIsDefinitivelyRejectedBeforeFlash()
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            using (var task = NewTask(value => { sent.Add(ParseWire(value)); return true; }, web))
            {
                BindTrainerContext(task);
                task.HandleWebRequest("learnCommit", Request("learnCommit", "skill.commit.unknown"));
                Assert.Empty(sent);
                Assert.Equal("invalid_payload", (string)web[0]["error"]);
                Assert.Equal("idle", task.WriteState);

                JObject preview = Request("learnPreview", "skill.preview.consume");
                preview["payload"]["desiredLevel"] = 2;
                task.HandleWebRequest("learnPreview", preview);
                task.HandleFlashResponse(PreviewResponse((int)sent[0]["callId"], "learn.consume", 2), null);

                JObject commit = Request("learnCommit", "skill.commit.consume");
                commit["payload"]["expectedLearnToken"] = "learn.consume";
                task.HandleWebRequest("learnCommit", commit);
                Assert.Equal("skillLearnCommit", (string)sent[1]["action"]);
                JObject learned = TrainerSnapshot(13, "trainer.one");
                learned["learned"][0]["level"] = 2;
                task.HandleFlashResponse(WriteSuccess((int)sent[1]["callId"], true, 13, learned), null);
                Assert.Equal("idle", task.WriteState);

                JObject repeated = Request("learnCommit", "skill.commit.repeated");
                repeated["payload"]["expectedLearnToken"] = "learn.consume";
                task.HandleWebRequest("learnCommit", repeated);
                Assert.Equal(2, sent.Count);
                Assert.Equal("invalid_payload", (string)web[web.Count - 1]["error"]);
            }
        }

        [Fact]
        public void LearnCommit_ChangedFalseSuccessIsMalformedAndRequiresReconcile()
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            using (var task = NewTask(value => { sent.Add(ParseWire(value)); return true; }, web))
            {
                BindTrainerContext(task);
                JObject preview = Request("learnPreview", "skill.preview.noop");
                preview["payload"]["desiredLevel"] = 2;
                task.HandleWebRequest("learnPreview", preview);
                task.HandleFlashResponse(PreviewResponse((int)sent[0]["callId"], "learn.noop", 2), null);
                JObject commit = Request("learnCommit", "skill.commit.noop");
                commit["payload"]["expectedLearnToken"] = "learn.noop";
                task.HandleWebRequest("learnCommit", commit);
                task.HandleFlashResponse(WriteSuccess((int)sent[1]["callId"], false, 12, Snapshot(12, null, null)), null);
                Assert.Equal("needs_reconcile", task.WriteState);
                Assert.Equal("malformed_response", (string)web[1]["error"]);
                Assert.True((bool)web[1]["requiresReconcile"]);
            }
        }

        [Fact]
        public void LearnCommit_PreviewTokenCannotCrossPanelClose()
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            using (var task = NewTask(value => { sent.Add(ParseWire(value)); return true; }, web))
            {
                BindTrainerContext(task);
                JObject preview = Request("learnPreview", "skill.preview.close");
                task.HandleWebRequest("learnPreview", preview);
                task.HandleFlashResponse(PreviewResponse((int)sent[0]["callId"], "learn.close", 1), null);

                Assert.True(task.HandlePanelClosed("skills.instance.trainer"));
                Assert.False(task.CanOpenTrainer);
                task.HandleFlashResponse(CleanupAck((int)sent[sent.Count - 1]["callId"], 12), null);
                Assert.True(task.CanOpenTrainer);
                int sentAfterClose = sent.Count;
                task.EnrichPanelInitData("{\"view\":\"trainer\",\"trainerSession\":\"trainer.one\"}");
                task.BindPanelInstance("skills.instance.2");
                JObject commit = Request("learnCommit", "skill.commit.after.close");
                commit["payload"]["expectedLearnToken"] = "learn.close";
                commit["panelInstanceId"] = "skills.instance.2";
                task.HandleWebRequest("learnCommit", commit);

                Assert.Equal(sentAfterClose, sent.Count);
                Assert.Equal("invalid_payload", (string)web[1]["error"]);
                Assert.Equal("idle", task.WriteState);
            }
        }

        [Fact]
        public void LazyLoadedPanel_CanBindAndCloseBeforeAnyBusinessRequest()
        {
            var sent = new List<JObject>();
            using (var task = new SkillTask(() => true, value => { sent.Add(ParseWire(value)); return true; }))
            {
                task.EnrichPanelInitData("{\"view\":\"manage\"}");
                task.BindPanelInstance("skills.lazy.instance");

                Assert.True(task.HandlePanelClosed("skills.lazy.instance"));
                Assert.All(sent, item => Assert.Equal("skillPanelClose", (string)item["action"]));
            }
        }

        [Fact]
        public void DisconnectBeforeFirstBusinessRequest_RetainsNextTrainerCapabilityForScopedCleanup()
        {
            var sent = new List<JObject>();
            using (var task = new SkillTask(() => true, value => { sent.Add(ParseWire(value)); return true; }))
            {
                task.EnrichPanelInitData("{\"view\":\"trainer\",\"trainerSession\":\"trainer.candidate\"}");
                task.ClearPending();
                task.OnSocketReconnected();

                Assert.Single(sent);
                Assert.Equal("skillPanelClose", (string)sent[0]["action"]);
                Assert.Equal("trainer.candidate", (string)sent[0]["trainerSession"]);
                Assert.False(task.CanOpenTrainer);
            }
        }

        [Fact]
        public void ManageRebind_RevokesTrainerCapabilityAndPreviewTokenImmediatelyWhenIdle()
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            using (var task = NewTask(value => { sent.Add(ParseWire(value)); return true; }, web))
            {
                BindTrainerContext(task);
                task.HandleWebRequest("learnPreview", Request("learnPreview", "skill.preview.manage"));
                task.HandleFlashResponse(PreviewResponse((int)sent[0]["callId"], "learn.manage", 1), null);

                JObject init = JObject.Parse(task.EnrichPanelInitData("{\"view\":\"manage\"}"));
                Assert.Equal("manage", (string)init["view"]);
                Assert.Equal("skillPanelClose", (string)sent[1]["action"]);
                Assert.Equal("trainer.one", (string)sent[1]["trainerSession"]);
                Assert.False(task.CanOpenTrainer);
                task.HandleFlashResponse(CleanupAck((int)sent[1]["callId"], 12), null);
                Assert.True(task.CanOpenTrainer);
                task.BindPanelInstance("skills.instance.manage");
                BindTrainerContext(task);

                JObject commit = Request("learnCommit", "skill.commit.after.manage");
                commit["payload"]["expectedLearnToken"] = "learn.manage";
                task.HandleWebRequest("learnCommit", commit);
                Assert.Equal(2, sent.Count);
                Assert.Equal("invalid_payload", (string)web[1]["error"]);
            }
        }

        [Fact]
        public void TrainerOriginManageBridge_HidesCapabilityAllowsOneReturnAndCleansOnClose()
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            using (var task = NewTask(value => { sent.Add(ParseWire(value)); return true; }, web))
            {
                BindTrainerContext(task);
                task.HandleWebRequest("learnPreview", Request("learnPreview", "skill.preview.bridge"));
                task.HandleFlashResponse(PreviewResponse((int)sent[0]["callId"], "learn.bridge", 1), null);

                Assert.True(task.TrySuspendTrainerForManage("skills.instance.trainer"));
                JObject manage = JObject.Parse(task.EnrichPanelInitData("{\"view\":\"manage\"}"));
                Assert.True((bool)manage["canReturnTrainer"]);
                Assert.Null(manage["trainerSession"]);
                Assert.Single(sent);

                task.BindPanelInstance("skills.instance.bridge.manage");
                string session;
                Assert.True(task.TryGetTrainerReturnSession("skills.instance.bridge.manage", out session));
                Assert.Equal("trainer.one", session);

                JObject trainer = JObject.Parse(task.EnrichPanelInitData(
                    "{\"view\":\"trainer\",\"trainerSession\":\"trainer.one\"}"));
                Assert.Equal("trainer.one", (string)trainer["trainerSession"]);
                task.BindPanelInstance("skills.instance.bridge.trainer");
                Assert.False(task.TryGetTrainerReturnSession("skills.instance.bridge.manage", out session));

                JObject staleCommit = Request("learnCommit", "skill.commit.bridge.stale");
                staleCommit["panelInstanceId"] = "skills.instance.bridge.trainer";
                staleCommit["payload"]["expectedLearnToken"] = "learn.bridge";
                task.HandleWebRequest("learnCommit", staleCommit);
                Assert.Single(sent);
                Assert.Equal("invalid_payload", (string)web[1]["error"]);

                Assert.True(task.HandlePanelClosed("skills.instance.bridge.trainer"));
                Assert.Equal(2, sent.Count);
                Assert.Equal("skillPanelClose", (string)sent[1]["action"]);
                Assert.Equal("trainer.one", (string)sent[1]["trainerSession"]);
            }
        }

        [Fact]
        public void TrainerOriginManageBridge_CloseWithoutReturn_CleansSuspendedCapability()
        {
            var sent = new List<JObject>();
            using (var task = new SkillTask(() => true, value => { sent.Add(ParseWire(value)); return true; }))
            {
                task.EnrichPanelInitData("{\"view\":\"trainer\",\"trainerSession\":\"trainer.suspended\"}");
                task.BindPanelInstance("skills.instance.suspended.trainer");
                Assert.True(task.TrySuspendTrainerForManage("skills.instance.suspended.trainer"));
                JObject manage = JObject.Parse(task.EnrichPanelInitData("{\"view\":\"manage\"}"));
                Assert.True((bool)manage["canReturnTrainer"]);
                task.BindPanelInstance("skills.instance.suspended.manage");

                Assert.True(task.HandlePanelClosed("skills.instance.suspended.manage"));
                Assert.Single(sent);
                Assert.Equal("skillPanelClose", (string)sent[0]["action"]);
                Assert.Equal("trainer.suspended", (string)sent[0]["trainerSession"]);
            }
        }

        [Fact]
        public void UnsafeTrainerInit_DowngradesToManageAndDefersCleanupUntilReconcileSettles()
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            using (var task = NewTask(value => { sent.Add(ParseWire(value)); return true; }, web))
            {
                task.HandleWebRequest("equip", Request("equip", "skill.cleanup.write"));
                JObject init = JObject.Parse(task.EnrichPanelInitData(
                    "{\"view\":\"trainer\",\"trainerSession\":\"trainer.new\"}"));
                Assert.Equal("manage", (string)init["view"]);
                Assert.Null(init["trainerSession"]);
                Assert.Single(sent);
                Assert.False(task.CanOpenTrainer);

                task.HandleFlashResponse(ErrorResponse((int)sent[0]["callId"], "future_error", 12), null);
                Assert.Equal("needs_reconcile", task.WriteState);
                Assert.Single(sent);

                JObject reconcile = Request("snapshot", "skill.cleanup.reconcile");
                reconcile["payload"]["reconcileId"] = "cleanup.reconcile";
                reconcile["payload"]["reconcileAfterCallId"] = "skill.cleanup.write";
                task.HandleWebRequest("snapshot", reconcile);
                JObject snapshot = Snapshot(12, null, null);
                snapshot["task"] = "skill_response";
                snapshot["callId"] = (int)sent[1]["callId"];
                task.HandleFlashResponse(snapshot, null);

                Assert.Equal("skillPanelClose", (string)sent[2]["action"]);
                Assert.False(task.CanOpenTrainer);
                task.HandleFlashResponse(CleanupAck((int)sent[2]["callId"], 12), null);
                Assert.True(task.CanOpenTrainer);
            }
        }

        [Fact]
        public void TrainerCleanup_TimeoutRetriesWithoutReconnectAndAckReopensGate()
        {
            var sent = new List<JObject>();
            // The same timeout also guards the background snapshot. Keep this
            // short enough to exercise the timeout path, but leave enough time
            // for the test thread to answer after observing the emitted probe
            // when the full xUnit suite is scheduling in parallel.
            using (var task = NewTask(value => { sent.Add(ParseWire(value)); return true; }, null, 250))
            {
                task.EnrichPanelInitData("{\"view\":\"manage\"}");
                Assert.False(task.CanOpenTrainer);
                Assert.True(SpinWait.SpinUntil(() => sent.Count >= 2, 2000));
                Assert.False(task.CanOpenTrainer);

                Assert.Equal(2, sent.Count);
                task.HandleFlashResponse(CleanupAck((int)sent[1]["callId"], 12), null);
                Assert.True(task.CanOpenTrainer);
            }
        }

        [Fact]
        public void TrainerCleanup_ContinuousTimeoutsUseBoundedRetryBurstThenAwaitReconnect()
        {
            var sent = new List<JObject>();
            using (var task = NewTask(value => { sent.Add(ParseWire(value)); return true; }, null, 15))
            {
                task.RequestTrainerCleanup("trainer.A");
                Assert.True(SpinWait.SpinUntil(() => sent.Count >= 3 && task.PendingCount == 0, 2000));
                Thread.Sleep(100);

                Assert.Equal(3, sent.Count);
                Assert.Equal(1, task.CleanupBacklogCount);
                Assert.False(task.CanOpenTrainer);

                task.OnSocketReconnected();
                Assert.Equal(4, sent.Count);
                task.HandleFlashResponse(CleanupAck((int)sent[3]["callId"], 12), null);
                Assert.True(task.CanOpenTrainer);
            }
        }

        [Fact]
        public void TrainerCleanup_FloodKeepsOnlyInFlightAndLatestCapability()
        {
            var sent = new List<JObject>();
            using (var task = NewTask(value => { sent.Add(ParseWire(value)); return true; }))
            {
                task.RequestTrainerCleanup("trainer.A");
                for (int i = 0; i < 40; i++) task.RequestTrainerCleanup("trainer." + i);

                Assert.Single(sent);
                Assert.Equal(2, task.CleanupBacklogCount);
                Assert.Equal("trainer.A", (string)sent[0]["trainerSession"]);
                task.HandleFlashResponse(CleanupAck((int)sent[0]["callId"], 12), null);

                Assert.Equal(2, sent.Count);
                Assert.Equal("trainer.39", (string)sent[1]["trainerSession"]);
                Assert.Equal(1, task.CleanupBacklogCount);
                task.HandleFlashResponse(CleanupAck((int)sent[1]["callId"], 12), null);
                Assert.Equal(0, task.CleanupBacklogCount);
                Assert.True(task.CanOpenTrainer);
            }
        }

        [Fact]
        public void TrainerCleanup_LostAckWithQueuedCandidateEscalatesToForceCleanup()
        {
            var sent = new List<JObject>();
            using (var task = NewTask(value => { sent.Add(ParseWire(value)); return true; }, null, 20))
            {
                task.RequestTrainerCleanup("trainer.active.A");
                task.RequestTrainerCleanup("trainer.candidate.B");

                Assert.Single(sent);
                Assert.Equal(2, task.CleanupBacklogCount);
                Assert.False(task.CanOpenTrainer);
                Assert.True(SpinWait.SpinUntil(() => sent.Count >= 2, 2000));
                Assert.Equal(2, sent.Count);
                Assert.Equal("skillPanelClose", (string)sent[1]["action"]);
                Assert.Null(sent[1]["trainerSession"]);
                Assert.False(task.CanOpenTrainer);

                task.HandleFlashResponse(CleanupAck((int)sent[1]["callId"], 12), null);
                Assert.Equal(0, task.CleanupBacklogCount);
                Assert.True(task.CanOpenTrainer);
            }
        }

        [Fact]
        public void TrainerRebind_CloseBeforeCandidateRequest_CleansPriorActiveAndCandidateBeforeOpeningGate()
        {
            var sent = new List<JObject>();
            using (var task = new SkillTask(() => true, value => { sent.Add(ParseWire(value)); return true; }))
            {
                task.EnrichPanelInitData("{\"view\":\"trainer\",\"trainerSession\":\"trainer.active.A\"}");
                task.BindPanelInstance("skills.instance.A");

                task.EnrichPanelInitData("{\"view\":\"trainer\",\"trainerSession\":\"trainer.candidate.B\"}");
                Assert.True(task.HandleAuthoritativePanelClosed("skills.instance.B"));

                Assert.Single(sent);
                Assert.Equal("skillPanelClose", (string)sent[0]["action"]);
                Assert.Equal("trainer.active.A", (string)sent[0]["trainerSession"]);
                Assert.Equal(2, task.CleanupBacklogCount);
                Assert.False(task.CanOpenTrainer);

                task.HandleFlashResponse(CleanupAck((int)sent[0]["callId"], 12), null);
                Assert.Equal(2, sent.Count);
                Assert.Equal("trainer.candidate.B", (string)sent[1]["trainerSession"]);
                Assert.Equal(1, task.CleanupBacklogCount);
                Assert.False(task.CanOpenTrainer);

                task.HandleFlashResponse(CleanupAck((int)sent[1]["callId"], 12), null);
                Assert.Equal(0, task.CleanupBacklogCount);
                Assert.True(task.CanOpenTrainer);
            }
        }

        [Fact]
        public void TrainerRebind_PriorCleanupQueuedForRetryThenCandidateCloses_UsesGlobalCleanup()
        {
            var sent = new List<JObject>();
            bool failFirstCleanup = true;
            using (var task = new SkillTask(() => true, value =>
            {
                JObject wire = ParseWire(value);
                sent.Add(wire);
                if (failFirstCleanup && (string)wire["action"] == "skillPanelClose")
                {
                    failFirstCleanup = false;
                    return false;
                }
                return true;
            }, 10000))
            {
                task.EnrichPanelInitData("{\"view\":\"trainer\",\"trainerSession\":\"trainer.active.A\"}");
                task.BindPanelInstance("skills.instance.A");
                task.EnrichPanelInitData("{\"view\":\"trainer\",\"trainerSession\":\"trainer.candidate.B\"}");
                task.BindPanelInstance("skills.instance.B");

                Assert.Single(sent);
                Assert.Equal("trainer.active.A", (string)sent[0]["trainerSession"]);
                Assert.Equal(1, task.CleanupBacklogCount);

                JObject snapshotRequest = Request("snapshot", "skill.snapshot.candidate.B");
                snapshotRequest["panelInstanceId"] = "skills.instance.B";
                snapshotRequest["payload"]["view"] = "trainer";
                snapshotRequest["payload"]["trainerSession"] = "trainer.candidate.B";
                task.HandleWebRequest("snapshot", snapshotRequest);
                JObject promoted = TrainerSnapshot(12, "trainer.candidate.B");
                promoted["task"] = "skill_response";
                promoted["callId"] = (int)sent[1]["callId"];
                task.HandleFlashResponse(promoted, null);

                Assert.True(task.HandlePanelClosed("skills.instance.B"));
                Assert.Equal(1, task.CleanupBacklogCount);
                Assert.False(task.CanOpenTrainer);

                task.OnSocketReconnected();
                Assert.Equal(3, sent.Count);
                Assert.Equal("skillPanelClose", (string)sent[2]["action"]);
                Assert.Null(sent[2]["trainerSession"]);
                Assert.False(task.CanOpenTrainer);

                task.HandleFlashResponse(CleanupAck((int)sent[2]["callId"], 12), null);
                Assert.Equal(0, task.CleanupBacklogCount);
                Assert.True(task.CanOpenTrainer);
            }
        }

        [Fact]
        public void GatedTrainerCandidate_DistinctFromQueuedActiveSession_CollapsesToGlobalCleanup()
        {
            var sent = new List<JObject>();
            using (var task = new SkillTask(() => true, value => { sent.Add(ParseWire(value)); return true; }))
            {
                task.EnrichPanelInitData("{\"view\":\"trainer\",\"trainerSession\":\"trainer.one\"}");
                task.BindPanelInstance("skills.instance.trainer");
                JObject preview = Request("learnPreview", "skill.preview.cleanup.queue");
                preview["payload"]["desiredLevel"] = 2;
                task.HandleWebRequest("learnPreview", preview);
                task.HandleFlashResponse(PreviewResponse((int)sent[0]["callId"], "learn.cleanup.queue", 2), null);
                JObject commit = Request("learnCommit", "skill.commit.cleanup.queue");
                commit["payload"]["expectedLearnToken"] = "learn.cleanup.queue";
                task.HandleWebRequest("learnCommit", commit);
                Assert.Equal("write_pending", task.WriteState);

                Assert.True(task.HandlePanelClosed("skills.instance.trainer"));
                JObject gated = JObject.Parse(task.EnrichPanelInitData(
                    "{\"view\":\"trainer\",\"trainerSession\":\"trainer.candidate.B\"}"));
                Assert.Equal("manage", (string)gated["view"]);
                Assert.Equal(1, task.CleanupBacklogCount);
                Assert.False(task.CanOpenTrainer);

                JObject learned = TrainerSnapshot(13, "trainer.one");
                learned["learned"][0]["level"] = 2;
                task.HandleFlashResponse(WriteSuccess((int)sent[1]["callId"], true, 13, learned), null);

                Assert.Equal(3, sent.Count);
                Assert.Equal("skillPanelClose", (string)sent[2]["action"]);
                Assert.Null(sent[2]["trainerSession"]);
                Assert.False(task.CanOpenTrainer);

                task.HandleFlashResponse(CleanupAck((int)sent[2]["callId"], 13), null);
                Assert.Equal(0, task.CleanupBacklogCount);
                Assert.True(task.CanOpenTrainer);
            }
        }

        [Fact]
        public void UnknownReconcileTarget_DispatchesImmediateProbeAtCurrentEpoch()
        {
            var sent = new List<JObject>();
            using (var task = NewTask(value => { sent.Add(ParseWire(value)); return true; }))
            {
                JObject reconcile = Request("snapshot", "skill.reconcile.unknown");
                reconcile["payload"]["reconcileId"] = "reconcile.unknown";
                reconcile["payload"]["reconcileAfterCallId"] = "skill.write.evicted";
                task.HandleWebRequest("snapshot", reconcile);

                Assert.Single(sent);
                Assert.Equal("skillSnapshot", (string)sent[0]["action"]);
                Assert.Equal(0, (int)sent[0]["writeEpoch"]);
            }
        }

        [Fact]
        public void UnknownReconcileTarget_IsRejectedWhileDifferentWriteIsPending()
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            using (var task = NewTask(value => { sent.Add(ParseWire(value)); return true; }, web))
            {
                task.HandleWebRequest("equip", Request("equip", "skill.write.active"));
                JObject reconcile = Request("snapshot", "skill.reconcile.wrong.target");
                reconcile["payload"]["reconcileId"] = "reconcile.wrong";
                reconcile["payload"]["reconcileAfterCallId"] = "skill.write.different";
                task.HandleWebRequest("snapshot", reconcile);

                Assert.Single(sent);
                Assert.Equal("invalid_payload", (string)web[0]["error"]);
                Assert.Equal("write_pending", task.WriteState);
            }
        }

        [Fact]
        public void RecentOlderWriteTarget_IsRejectedWhileNewWriteIsPending()
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            using (var task = NewTask(value => { sent.Add(ParseWire(value)); return true; }, web))
            {
                task.HandleWebRequest("equip", Request("equip", "skill.write.old"));
                task.HandleFlashResponse(WriteSuccess((int)sent[0]["callId"], true, 13,
                    Snapshot(13, 4, "闪现")), null);
                task.HandleWebRequest("unequip", Request("unequip", "skill.write.active.new"));

                JObject reconcile = Request("snapshot", "skill.reconcile.old.while.active");
                reconcile["payload"]["reconcileId"] = "reconcile.old.active";
                reconcile["payload"]["reconcileAfterCallId"] = "skill.write.old";
                task.HandleWebRequest("snapshot", reconcile);

                Assert.Equal(2, sent.Count);
                Assert.Equal("invalid_payload", (string)web[1]["error"]);
                Assert.Equal("write_pending", task.WriteState);
            }
        }

        [Fact]
        public void NeedsReconcile_RejectsOlderRecentWriteTargetInsteadOfClearingLatestUnknownWrite()
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            using (var task = NewTask(value => { sent.Add(ParseWire(value)); return true; }, web))
            {
                task.HandleWebRequest("equip", Request("equip", "skill.write.known.old"));
                task.HandleFlashResponse(WriteSuccess((int)sent[0]["callId"], true, 13,
                    Snapshot(13, 4, "闪现")), null);
                task.HandleWebRequest("unequip", Request("unequip", "skill.write.unknown.latest"));
                task.HandleFlashResponse(ErrorResponse((int)sent[1]["callId"], "future_error", 13), null);
                Assert.Equal("needs_reconcile", task.WriteState);

                JObject reconcile = Request("snapshot", "skill.reconcile.known.old");
                reconcile["payload"]["reconcileId"] = "reconcile.known.old";
                reconcile["payload"]["reconcileAfterCallId"] = "skill.write.known.old";
                task.HandleWebRequest("snapshot", reconcile);

                Assert.Equal(2, sent.Count);
                Assert.Equal("invalid_payload", (string)web[2]["error"]);
                Assert.Equal("needs_reconcile", task.WriteState);
            }
        }

        [Fact]
        public void SnapshotResponse_MustMatchBoundPanelViewAndTrainerSession()
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            using (var task = NewTask(value => { sent.Add(ParseWire(value)); return true; }, web))
            {
                BindTrainerContext(task);
                JObject request = Request("snapshot", "skill.snapshot.trainer");
                request["panelInstanceId"] = "skills.instance.trainer";
                request["payload"]["view"] = "trainer";
                request["payload"]["trainerSession"] = "trainer.one";
                task.HandleWebRequest("snapshot", request);

                JObject wrong = TrainerSnapshot(12, "trainer.other");
                wrong["task"] = "skill_response";
                wrong["callId"] = (int)sent[0]["callId"];
                task.HandleFlashResponse(wrong, null);

                Assert.Equal("malformed_response", (string)web[0]["error"]);
            }
        }

        [Fact]
        public void TrainerContext_RejectsManageOnlyLoadoutWritesBeforeFlash()
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            using (var task = NewTask(value => { sent.Add(ParseWire(value)); return true; }, web))
            {
                BindTrainerContext(task);
                JObject equip = Request("equip", "skill.trainer.equip");
                equip["panelInstanceId"] = "skills.instance.trainer";
                task.HandleWebRequest("equip", equip);

                Assert.Empty(sent);
                Assert.Equal("panel_context_mismatch", (string)web[0]["error"]);
                Assert.Equal("idle", task.WriteState);
            }
        }

        [Fact]
        public void ReconcileProbe_WaitsForTargetWriteThenClearsWithPostWriteSnapshot()
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            using (var task = NewTask(value => { sent.Add(ParseWire(value)); return true; }, web))
            {
                task.HandleWebRequest("equip", Request("equip", "skill.write.1"));
                JObject reconcile = Request("snapshot", "skill.reconcile.1");
                reconcile["payload"]["reconcileId"] = "reconcile.one";
                reconcile["payload"]["reconcileAfterCallId"] = "skill.write.1";
                task.HandleWebRequest("snapshot", reconcile);
                Assert.Single(sent);

                task.HandleFlashResponse(WriteSuccess((int)sent[0]["callId"], true, 13,
                    Snapshot(13, 4, "闪现")), null);
                Assert.Equal(2, sent.Count);
                Assert.Equal("skillSnapshot", (string)sent[1]["action"]);
                Assert.Equal(1, (int)sent[1]["writeEpoch"]);

                JObject reconciled = Snapshot(13, 4, "闪现");
                reconciled["task"] = "skill_response";
                reconciled["callId"] = (int)sent[1]["callId"];
                task.HandleFlashResponse(reconciled, null);

                Assert.Equal("idle", task.WriteState);
                Assert.True((bool)web[1]["reconciled"]);
                Assert.Equal("reconcile.one", (string)web[1]["reconcileId"]);
            }
        }

        [Fact]
        public void StaleIdleProbe_CannotClearNewerUnknownWriteWatermark()
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            using (var task = NewTask(value => { sent.Add(ParseWire(value)); return true; }, web))
            {
                JObject oldProbe = Request("snapshot", "skill.reconcile.old.probe");
                oldProbe["payload"]["reconcileId"] = "reconcile.old.probe";
                oldProbe["payload"]["reconcileAfterCallId"] = "skill.write.old";
                task.HandleWebRequest("snapshot", oldProbe);
                task.HandleWebRequest("equip", Request("equip", "skill.write.newer"));

                task.HandleFlashResponse(ErrorResponse((int)sent[1]["callId"], "future_error", 13), null);
                Assert.Equal("needs_reconcile", task.WriteState);

                JObject stale = Snapshot(12, null, null);
                stale["task"] = "skill_response";
                stale["callId"] = (int)sent[0]["callId"];
                task.HandleFlashResponse(stale, null);

                Assert.Equal("needs_reconcile", task.WriteState);
                Assert.Null(web[1]["reconciled"]);
                Assert.Equal(1, task.WriteEpoch);
            }
        }

        [Fact]
        public void CloseBeforeWriteTimeout_BackgroundReconcileSettlesAndRunsCleanupWithoutReopen()
        {
            var sent = new List<JObject>();
            var logs = new List<string>();
            // The same timeout guards the emitted background snapshot.
            // Leave the full-suite worker enough time to answer that probe.
            LogManager.SetSink(logs.Add);
            try
            {
                using (var task = NewTask(value => { sent.Add(ParseWire(value)); return true; }, null, 250))
                {
                    task.HandleWebRequest("equip", Request("equip", "skill.background.close.first"));
                    Assert.True(task.HandlePanelClosed("skills.instance.1"));

                    Assert.True(SpinWait.SpinUntil(() => sent.Count >= 2, 2000));
                    Assert.Equal("skillSnapshot", (string)sent[1]["action"]);
                    Assert.Equal("manage", (string)sent[1]["view"]);
                    JObject reconciled = Snapshot(13, 4, "闪现");
                    reconciled["task"] = "skill_response";
                    reconciled["callId"] = (int)sent[1]["callId"];
                    task.HandleFlashResponse(reconciled, null);

                    Assert.Equal("idle", task.WriteState);
                    Assert.Equal("skillPanelClose", (string)sent[2]["action"]);
                    task.HandleFlashResponse(CleanupAck((int)sent[2]["callId"], 13), null);
                    Assert.True(task.CanOpenTrainer);
                }
            }
            finally
            {
                LogManager.ResetSink();
            }

            string binding = Assert.Single(logs.FindAll(line =>
                line.StartsWith(
                    "event=authority_flash_call_bound ",
                    StringComparison.Ordinal)));
            Assert.Contains(" webCallId=skill.background.close.first ", binding);
            Assert.Contains(" cmd=equip action=skillEquip", binding);
            Assert.DoesNotContain(
                " flashCallId=" + (int)sent[1]["callId"] + " ",
                binding);
        }

        [Fact]
        public void WriteTimeoutThenClose_StartsBackgroundReconcileWithoutReopen()
        {
            var sent = new List<JObject>();
            // Once close emits the background snapshot, its response must not
            // race a 20 ms wall-clock timeout under parallel test load.
            using (var task = NewTask(value => { sent.Add(ParseWire(value)); return true; }, null, 250))
            {
                task.HandleWebRequest("equip", Request("equip", "skill.background.timeout.first"));
                Assert.True(SpinWait.SpinUntil(() => task.WriteState == "needs_reconcile", 2000));
                Assert.Single(sent);

                Assert.True(task.HandlePanelClosed("skills.instance.1"));
                Assert.Equal(2, sent.Count);
                JObject reconciled = Snapshot(13, 4, "闪现");
                reconciled["task"] = "skill_response";
                reconciled["callId"] = (int)sent[1]["callId"];
                task.HandleFlashResponse(reconciled, null);

                Assert.Equal("idle", task.WriteState);
                Assert.Equal("skillPanelClose", (string)sent[2]["action"]);
                task.HandleFlashResponse(CleanupAck((int)sent[2]["callId"], 13), null);
                Assert.True(task.CanOpenTrainer);
            }
        }

        [Fact]
        public void DisconnectReconnect_BackgroundReconcileSettlesAndCleansWithoutReopen()
        {
            bool ready = true;
            var sent = new List<JObject>();
            using (var task = new SkillTask(() => ready, value => { sent.Add(ParseWire(value)); return true; }, 250))
            {
                task.BindPanelInstance("skills.instance.disconnect");
                JObject write = Request("equip", "skill.background.disconnect");
                write["panelInstanceId"] = "skills.instance.disconnect";
                task.HandleWebRequest("equip", write);

                ready = false;
                task.ClearPending();
                Assert.Equal("needs_reconcile", task.WriteState);
                ready = true;
                task.OnSocketReconnected();

                Assert.Equal(2, sent.Count);
                Assert.Equal("skillSnapshot", (string)sent[1]["action"]);
                JObject reconciled = Snapshot(13, 4, "闪现");
                reconciled["task"] = "skill_response";
                reconciled["callId"] = (int)sent[1]["callId"];
                task.HandleFlashResponse(reconciled, null);
                Assert.Equal("skillPanelClose", (string)sent[2]["action"]);
                task.HandleFlashResponse(CleanupAck((int)sent[2]["callId"], 13), null);

                Assert.Equal("idle", task.WriteState);
                Assert.True(task.CanOpenTrainer);
            }
        }

        [Fact]
        public void ExpiredTrainerAfterMalformedLearnCommit_FallsBackToManageBackgroundReconcile()
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            using (var task = NewTask(value => { sent.Add(ParseWire(value)); return true; }, web))
            {
                BindTrainerContext(task);
                task.HandleWebRequest("learnPreview", Request("learnPreview", "skill.background.preview"));
                task.HandleFlashResponse(PreviewResponse((int)sent[0]["callId"], "learn.background", 1), null);
                JObject commit = Request("learnCommit", "skill.background.commit");
                commit["payload"]["expectedLearnToken"] = "learn.background";
                task.HandleWebRequest("learnCommit", commit);

                task.HandleFlashResponse(WriteSuccess((int)sent[1]["callId"], true, 13, null), null);
                Assert.Equal("needs_reconcile", task.WriteState);
                Assert.Equal("malformed_response", (string)web[1]["error"]);
                Assert.True(task.HandlePanelClosed("skills.instance.trainer"));
                Assert.Equal("trainer", (string)sent[2]["view"]);
                Assert.Equal("trainer.one", (string)sent[2]["trainerSession"]);

                task.HandleFlashResponse(ErrorResponse((int)sent[2]["callId"], "trainer_session_expired", 13), null);
                Assert.Equal("skillSnapshot", (string)sent[3]["action"]);
                Assert.Equal("manage", (string)sent[3]["view"]);
                Assert.Null(sent[3]["trainerSession"]);

                JObject manage = Snapshot(13, null, null);
                manage["task"] = "skill_response";
                manage["callId"] = (int)sent[3]["callId"];
                task.HandleFlashResponse(manage, null);
                Assert.Equal("idle", task.WriteState);
                Assert.Equal("skillPanelClose", (string)sent[4]["action"]);
                Assert.Equal("trainer.one", (string)sent[4]["trainerSession"]);
                task.HandleFlashResponse(CleanupAck((int)sent[4]["callId"], 13), null);
                Assert.True(task.CanOpenTrainer);
            }
        }

        [Fact]
        public void ReadBeforeWrite_LateSnapshotKeepsCapturedEpoch()
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            using (var task = NewTask(value => { sent.Add(ParseWire(value)); return true; }, web))
            {
                task.HandleWebRequest("snapshot", Request("snapshot", "skill.read.old"));
                task.HandleWebRequest("equip", Request("equip", "skill.write.new"));
                Assert.Equal(0, (int)sent[0]["writeEpoch"]);
                Assert.Equal(1, (int)sent[1]["writeEpoch"]);

                task.HandleFlashResponse(WriteSuccess((int)sent[1]["callId"], true, 13,
                    Snapshot(13, 4, "闪现")), null);
                JObject stale = Snapshot(12, null, null);
                stale["task"] = "skill_response";
                stale["callId"] = (int)sent[0]["callId"];
                task.HandleFlashResponse(stale, null);

                Assert.Equal("skill.read.old", (string)web[1]["callId"]);
                Assert.Equal(0, (int)web[1]["writeEpoch"]);
            }
        }

        [Fact]
        public void HostTimeoutEntersUnknownState_CloseAndReopenPreserveEpochUntilReconcile()
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            using (var task = NewTask(value => { sent.Add(ParseWire(value)); return true; }, web, 20))
            {
                task.HandleWebRequest("equip", Request("equip", "skill.timeout.write"));
                Assert.True(SpinWait.SpinUntil(() => web.Count > 0, 2000));
                Assert.Equal("needs_reconcile", task.WriteState);
                Assert.True((bool)web[0]["requiresReconcile"]);
                Assert.True(task.HandlePanelClosed("skills.instance.1"));

                task.BindPanelInstance("skills.instance.2");
                JObject resume = JObject.Parse(task.EnrichPanelInitData("{\"view\":\"manage\"}"));
                Assert.Equal("needs_reconcile", (string)resume["writeState"]);
                Assert.Equal("skill.timeout.write", (string)resume["reconcileAfterCallId"]);
                Assert.Equal(1, (int)resume["writeEpoch"]);
                JObject retry = Request("equip", "skill.timeout.retry");
                retry["panelInstanceId"] = "skills.instance.2";
                task.HandleWebRequest("equip", retry);
                Assert.Equal("reconcile_required", (string)web[1]["error"]);
                Assert.Equal(1, task.WriteEpoch);
            }
        }

        [Fact]
        public void DomainAndCloseRouting_RecognizeSkillsAndRejectStaleInstance()
        {
            Assert.Equal(WebOverlayForm.PanelDomainRoute.Skills,
                WebOverlayForm.ResolvePanelDomainRoute("equip", "skills"));
            Assert.Equal(WebOverlayForm.PanelDomainRoute.Close,
                WebOverlayForm.ResolvePanelDomainRoute("close", "skills"));
            JObject close = new JObject
            {
                ["type"] = "panel", ["panel"] = "skills", ["cmd"] = "close",
                ["panelInstanceId"] = "skills.instance.2"
            };
            Assert.True(WebOverlayForm.IsValidSkillCloseEnvelope(close, "skills", "skills.instance.2"));
            Assert.False(WebOverlayForm.IsValidSkillCloseEnvelope(close, "skills", "skills.instance.1"));
            close["reason"] = "navigate_character_build";
            Assert.True(WebOverlayForm.IsValidSkillCloseEnvelope(close, "skills", "skills.instance.2"));
            close["reason"] = "escape";
            Assert.False(WebOverlayForm.IsValidSkillCloseEnvelope(close, "skills", "skills.instance.2"));
            close["reason"] = 1;
            Assert.False(WebOverlayForm.IsValidSkillCloseEnvelope(close, "skills", "skills.instance.2"));
            close.Remove("reason");
            close["domain"] = "skills";
            Assert.False(WebOverlayForm.IsValidSkillCloseEnvelope(close, "skills", "skills.instance.2"));
        }

        [Fact]
        public void CharacterBuildReturnCapability_IsExactOneShotAndWaitsForCloseCleanup()
        {
            var sent = new List<JObject>();
            using (var task = new SkillTask(
                () => true,
                value =>
                {
                    sent.Add(ParseWire(value));
                    return true;
                }))
            {
                JObject init = JObject.Parse(
                    task.EnrichPanelInitData(
                        "{\"view\":\"manage\",\"source\":\"nativehud\",\"canReturnCharacterBuild\":true}",
                        "skills.instance.from-build"));
                Assert.True((bool)init["canReturnCharacterBuild"]);
                task.BindPanelInstance("skills.instance.foreign");
                Assert.False(
                    task.TryConsumeCharacterBuildReturnCapability(
                        "skills.instance.foreign"));

                init = JObject.Parse(
                    task.EnrichPanelInitData(
                        "{\"view\":\"manage\",\"source\":\"nativehud\",\"canReturnCharacterBuild\":true}",
                        "skills.instance.from-build"));
                task.BindPanelInstance("skills.instance.from-build");
                Assert.False(task.IsClosedAndSettled);
                Assert.True(
                    task.TryConsumeCharacterBuildReturnCapability(
                        "skills.instance.from-build"));
                Assert.False(
                    task.TryConsumeCharacterBuildReturnCapability(
                        "skills.instance.from-build"));

                Assert.True(
                    task.HandlePanelClosed(
                        "skills.instance.from-build"));
                Assert.False(task.IsClosedAndSettled);
                JObject cleanup = Assert.Single(sent);
                Assert.Equal(
                    "skillPanelClose",
                    (string)cleanup["action"]);
                task.HandleFlashResponse(
                    CleanupAck(
                        (int)cleanup["callId"],
                        12),
                    null);
                Assert.True(task.IsClosedAndSettled);
            }
        }

        [Fact]
        public void CharacterBuildReturnCapability_IsRemovedFromTrainerAndUnboundInit()
        {
            using (var task = new SkillTask(
                () => true,
                _ => true))
            {
                JObject trainer = JObject.Parse(
                    task.EnrichPanelInitData(
                        "{\"view\":\"trainer\",\"source\":\"world_skill_trainer\",\"trainerSession\":\"trainer.one\",\"canReturnCharacterBuild\":true}",
                        "skills.instance.trainer"));
                Assert.Null(
                    trainer["canReturnCharacterBuild"]);
                task.BindPanelInstance(
                    "skills.instance.trainer");
                Assert.False(
                    task.TryConsumeCharacterBuildReturnCapability(
                        "skills.instance.trainer"));

                JObject unbound = JObject.Parse(
                    task.EnrichPanelInitData(
                        "{\"view\":\"manage\",\"source\":\"nativehud\",\"canReturnCharacterBuild\":true}"));
                Assert.Null(
                    unbound["canReturnCharacterBuild"]);
            }
        }

        [Fact]
        public void LearnCommit_LogManagerCaptureNeverContainsRawAuthorityToken()
        {
            const string secret = "learn.log.secret.1";
            var sent = new List<JObject>();
            var logs = new List<string>();
            LogManager.SetSink(logs.Add);
            try
            {
                using (var task = NewTask(
                    value =>
                    {
                        sent.Add(ParseWire(value));
                        return true;
                    }))
                {
                    BindTrainerContext(task);
                    task.HandleWebRequest(
                        "learnPreview",
                        Request("learnPreview", "skill.log.preview"));
                    task.HandleFlashResponse(
                        PreviewResponse(
                            (int)sent[0]["callId"],
                            secret,
                            1),
                        null);

                    JObject commit = Request(
                        "learnCommit",
                        "skill.log.commit");
                    commit["payload"]["expectedLearnToken"] = secret;
                    task.HandleWebRequest("learnCommit", commit);
                }
            }
            finally
            {
                LogManager.ResetSink();
            }

            string flashLog = Assert.Single(
                logs.FindAll(line =>
                    line.Contains("[SkillTask] -> Flash:")
                    && line.Contains("cmd=skillLearnCommit")));
            JObject command = sent[sent.Count - 1];
            string binding = Assert.Single(
                logs.FindAll(line =>
                    line.StartsWith(
                        "event=authority_flash_call_bound ",
                        StringComparison.Ordinal)
                    && line.EndsWith(
                        " cmd=learnCommit action=skillLearnCommit",
                        StringComparison.Ordinal)));
            Assert.Equal(
                "event=authority_flash_call_bound domain=skills"
                + " webCallId=skill.log.commit"
                + " flashCallId=" + (int)command["callId"]
                + " panel=skills panelInstanceId=skills.instance.trainer"
                + " cmd=learnCommit action=skillLearnCommit",
                binding);
            Assert.All(logs, line => Assert.DoesNotContain(secret, line));
            Assert.Contains(
                "expectedLearnTokenRef="
                    + AuthorityLogFormatter.CreateReference(secret),
                flashLog);
        }

        private static SkillTask NewTask(Func<string, bool> send, List<JObject> web = null, int timeout = 10000)
        {
            var task = new SkillTask(() => true, send, timeout);
            task.BindPanelInstance("skills.instance.1");
            if (web != null) task.SetPostToWeb(value => web.Add(JObject.Parse(value)));
            return task;
        }

        private static void BindTrainerContext(SkillTask task)
        {
            task.EnrichPanelInitData("{\"view\":\"trainer\",\"trainerSession\":\"trainer.one\"}");
            task.BindPanelInstance("skills.instance.trainer");
        }

        private static JObject Request(string cmd, string callId)
        {
            JObject payload = new JObject { ["v"] = 1 };
            switch (cmd)
            {
                case "snapshot": payload["view"] = "manage"; break;
                case "learnPreview":
                    payload["skillKey"] = "闪现"; payload["desiredLevel"] = 1;
                    payload["trainerSession"] = "trainer.one"; payload["expectedRevision"] = 12; break;
                case "learnCommit": payload["expectedLearnToken"] = "learn.one"; break;
                case "equip":
                    payload["skillKey"] = "闪现"; payload["slot"] = 4; payload["expectedRevision"] = 12; break;
                case "unequip": payload["slot"] = 4; payload["expectedRevision"] = 12; break;
                case "moveSlot":
                    payload["sourceSlot"] = 4; payload["targetSlot"] = 9; payload["expectedRevision"] = 12; break;
                case "setPassive":
                    payload["skillKey"] = "坚韧"; payload["enabled"] = true; payload["expectedRevision"] = 12; break;
                case "reorder":
                    payload["skillKey"] = "闪现"; payload["targetIndex"] = 0; payload["expectedRevision"] = 12; break;
            }
            return new JObject
            {
                ["type"] = "panel", ["panel"] = "skills", ["domain"] = "skills",
                ["cmd"] = cmd, ["callId"] = callId,
                ["panelInstanceId"] = (cmd == "learnPreview" || cmd == "learnCommit")
                    ? "skills.instance.trainer" : "skills.instance.1",
                ["payload"] = payload
            };
        }

        private static JObject ErrorResponse(int fid, string error, int revision)
        {
            return new JObject
            {
                ["task"] = "skill_response", ["callId"] = fid, ["success"] = false,
                ["v"] = 1, ["error"] = error, ["revision"] = revision
            };
        }

        private static JObject PreviewResponse(int fid, string token, int desiredLevel)
        {
            return new JObject
            {
                ["task"] = "skill_response", ["callId"] = fid, ["success"] = true, ["v"] = 1,
                ["trainerSession"] = "trainer.one", ["skillKey"] = "闪现", ["currentLevel"] = 1,
                ["desiredLevel"] = desiredLevel, ["cost"] = 1, ["revision"] = 12,
                ["canCommit"] = true, ["blockingError"] = null, ["learnToken"] = token
            };
        }

        private static JObject WriteSuccess(int fid, bool changed, int revision, JObject snapshot)
        {
            return new JObject
            {
                ["task"] = "skill_response", ["callId"] = fid, ["success"] = true,
                ["v"] = 1, ["changed"] = changed, ["revision"] = revision, ["snapshot"] = snapshot
            };
        }

        private static JObject CleanupAck(int fid, int revision)
        {
            return new JObject
            {
                ["task"] = "skill_response", ["callId"] = fid, ["success"] = true,
                ["v"] = 1, ["changed"] = false, ["revision"] = revision
            };
        }

        private static JObject Snapshot(int revision, int? equippedSlot, string equippedKey)
        {
            var loadout = new JArray();
            for (int slot = 1; slot <= 12; slot++)
            {
                if (equippedSlot == slot)
                {
                    loadout.Add(new JObject
                    {
                        ["slot"] = slot, ["skillKey"] = equippedKey, ["keyLabel"] = slot.ToString(),
                        ["level"] = 1, ["iconKey"] = equippedKey, ["stateHealth"] = "ok", ["writeBlocked"] = false
                    });
                }
                else
                {
                    loadout.Add(new JObject
                    {
                        ["slot"] = slot, ["skillKey"] = null, ["keyLabel"] = slot.ToString(),
                        ["stateHealth"] = "ok", ["writeBlocked"] = false
                    });
                }
            }
            return new JObject
            {
                ["success"] = true, ["v"] = 1, ["revision"] = revision, ["view"] = "manage",
                ["player"] = new JObject { ["level"] = 20, ["skillPoints"] = 10, ["easyMode"] = false },
                ["learned"] = new JArray
                {
                    new JObject
                    {
                        ["skillKey"] = "闪现", ["orderIndex"] = 0, ["level"] = 1, ["maxLevel"] = 20,
                        ["type"] = "主动", ["passive"] = false, ["equippable"] = true, ["enabled"] = true,
                        ["equippedSlots"] = equippedSlot.HasValue ? new JArray(equippedSlot.Value) : new JArray(),
                        ["unlockLevel"] = 1, ["unlockSP"] = 1, ["upgradeSP"] = 1, ["mp"] = 5.0,
                        ["cooldownMs"] = 1000, ["iconKey"] = "闪现", ["description"] = "位移技能",
                        ["stateHealth"] = "ok", ["writeBlocked"] = false
                    }
                },
                ["loadout"] = loadout, ["trainer"] = null, ["diagnostics"] = new JArray()
            };
        }

        private static JObject TrainerSnapshot(int revision, string trainerSession)
        {
            JObject snapshot = Snapshot(revision, null, null);
            snapshot["view"] = "trainer";
            snapshot["trainer"] = new JObject
            {
                ["session"] = trainerSession,
                ["entries"] = new JArray()
            };
            return snapshot;
        }

        private static JObject ParseWire(string value) { return JObject.Parse(value.TrimEnd('\0')); }
    }
}
