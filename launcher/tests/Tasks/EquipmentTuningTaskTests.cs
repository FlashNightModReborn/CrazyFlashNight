using System;
using System.Collections.Generic;
using System.Threading;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace Launcher.Tests.Tasks
{
    public sealed class EquipmentTuningTaskTests
    {
        [Fact]
        public void SnapshotRequest_RebuildsStrictPayloadAndInjectsHostAuthority()
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            using (var task = NewTask(value => { sent.Add(ParseWire(value)); return true; }, web))
            {
                task.HandleWebRequest("snapshot", Request("snapshot", "tune.snapshot.1"));

                JObject command = Assert.Single(sent);
                Assert.Equal("cmd", (string)command["task"]);
                Assert.Equal("equipmentTuningSnapshot", (string)command["action"]);
                Assert.Equal("workbench.instance.1", (string)command["panelInstanceId"]);
                Assert.Equal("tuning.session.1", (string)command["viewSessionId"]);
                Assert.Equal("tune.snapshot.1", (string)command["requestCallId"]);
                Assert.Equal(0, (int)command["writeEpoch"]);
                Assert.Equal("背包", (string)command["source"]["containerId"]);
                Assert.Equal(7, (int)command["source"]["slot"]);
                Assert.Null(command["payload"]);
                Assert.Null(command["domain"]);

                task.HandleFlashResponse(SnapshotResponse(command), null);
                JObject response = Assert.Single(web);
                Assert.True((bool)response["success"]);
                Assert.Equal("panel_resp", (string)response["type"]);
                Assert.Equal("workbench", (string)response["panel"]);
                Assert.Equal("equipment_tuning", (string)response["domain"]);
                Assert.Equal("snapshot", (string)response["cmd"]);
                Assert.Equal("tune.snapshot.1", (string)response["callId"]);
                Assert.Equal("workbench.instance.1", (string)response["panelInstanceId"]);
                Assert.Equal("tuning.session.1", (string)response["viewSessionId"]);
            }
        }

        [Theory]
        [InlineData("enhance")]
        [InlineData("convert")]
        [InlineData("install_tier")]
        [InlineData("install_mod")]
        [InlineData("detach_mod")]
        [InlineData("detach_all_mods")]
        public void PreviewRequest_AllSevenOperationsMapToFrozenAction(string operation)
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            using (var task = NewTask(value => { sent.Add(ParseWire(value)); return true; }, web))
            {
                PrimeSession(task, sent);
                sent.Clear(); web.Clear();

                task.HandleWebRequest("preview", Request("preview", "tune.preview." + operation, operation));

                JObject command = Assert.Single(sent);
                Assert.Equal("equipmentTuningPreview", (string)command["action"]);
                Assert.Equal(operation, (string)command["operation"]);
                Assert.Equal("tuning.session.1", (string)command["viewSessionId"]);
                Assert.Equal(0, (int)command["writeEpoch"]);
                if (operation == "enhance") Assert.Equal(8, (int)command["targetLevel"]);
                else if (operation == "convert")
                {
                    Assert.Equal(8, (int)command["target"]["slot"]);
                    Assert.Equal("lease.target.8", (string)command["target"]["expectedLease"]);
                }
                else if (operation == "detach_all_mods") Assert.Null(command["candidateKey"]);
                else Assert.Equal("候选.一", (string)command["candidateKey"]);

                // replace_mod 与 install_mod 共用顶层“配件”栏目，但 wire 必须同时冻结新旧候选。
                if (operation == "install_mod")
                {
                    task.HandleWebRequest("preview", Request("preview", "tune.preview.replace_mod", "replace_mod"));
                    JObject replacement = sent[1];
                    Assert.Equal("replace_mod", (string)replacement["operation"]);
                    Assert.Equal("候选.一", (string)replacement["candidateKey"]);
                    Assert.Equal("候选.旧", (string)replacement["replaceCandidateKey"]);
                }
            }
        }

        [Fact]
        public void CommitAndTooltip_MapToFrozenActionsAndCarryViewBinding()
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            using (var task = NewTask(value => { sent.Add(ParseWire(value)); return true; }, web))
            {
                PrimeSession(task, sent);
                sent.Clear(); web.Clear();

                task.HandleWebRequest("tooltip", Request("tooltip", "tune.tooltip.1"));
                Assert.Equal("equipmentTuningTooltip", (string)sent[0]["action"]);
                Assert.Equal("tuning.session.1", (string)sent[0]["viewSessionId"]);
                Assert.Equal("候选.一", (string)sent[0]["candidateKey"]);
                task.HandleFlashResponse(TooltipResponse(sent[0]), null);
                Assert.Single(web);
                Assert.Equal("<b>候选</b>", (string)web[0]["introHTML"]);
                Assert.Equal("候选说明", (string)web[0]["descHTML"]);
                Assert.Equal("收集品", (string)web[0]["itemType"]);
                Assert.Equal("材料", (string)web[0]["itemUse"]);

                task.HandleWebRequest("commit", Request("commit", "tune.commit.1"));
                Assert.Equal("equipmentTuningCommit", (string)sent[1]["action"]);
                Assert.Equal("tuning.token.1", (string)sent[1]["expectedTuningToken"]);
                Assert.Equal(1, (int)sent[1]["writeEpoch"]);
                Assert.Equal("tune.commit.1", (string)sent[1]["requestCallId"]);
            }
        }

        [Fact]
        public void StrictEnvelope_RejectsUnknownKeysStaleInstanceAndRawSlotProjection()
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            using (var task = NewTask(value => { sent.Add(ParseWire(value)); return true; }, web))
            {
                JObject unknownTop = Request("snapshot", "tune.bad.top");
                unknownTop["action"] = "openEquipUI";
                task.HandleWebRequest("snapshot", unknownTop);

                JObject rawSlot = Request("snapshot", "tune.bad.slot");
                rawSlot["payload"]["source"]["occupied"] = true;
                task.HandleWebRequest("snapshot", rawSlot);

                JObject stale = Request("snapshot", "tune.bad.instance");
                stale["panelInstanceId"] = "workbench.instance.old";
                task.HandleWebRequest("snapshot", stale);

                JObject badTooltip = Request("tooltip", "tune.bad.tooltip");
                ((JObject)badTooltip["payload"]).Remove("viewSessionId");
                task.HandleWebRequest("tooltip", badTooltip);

                Assert.Empty(sent);
                Assert.Equal("invalid_payload", (string)web[0]["error"]);
                Assert.Equal("invalid_payload", (string)web[1]["error"]);
                Assert.Equal("panel_instance_expired", (string)web[2]["error"]);
                Assert.Equal("invalid_payload", (string)web[3]["error"]);
                Assert.All(web, response => Assert.Equal("equipment_tuning", (string)response["domain"]));
            }
        }

        [Fact]
        public void FlashResponse_RequiresMatchingCommandAndFrozenTopLevelShape()
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            using (var task = NewTask(value => { sent.Add(ParseWire(value)); return true; }, web))
            {
                task.HandleWebRequest("snapshot", Request("snapshot", "tune.response.command"));
                JObject wrongCommand = SnapshotResponse(sent[0]);
                wrongCommand["command"] = "preview";
                task.HandleFlashResponse(wrongCommand, null);
                Assert.Equal("malformed_response", (string)web[0]["error"]);

                task.HandleWebRequest("snapshot", Request("snapshot", "tune.response.extra"));
                JObject extra = SnapshotResponse(sent[1]);
                extra["forgedBusinessField"] = true;
                task.HandleFlashResponse(extra, null);
                Assert.Equal("malformed_response", (string)web[1]["error"]);

                task.HandleWebRequest("snapshot", Request("snapshot", "tune.response.valid"));
                task.HandleFlashResponse(SnapshotResponse(sent[2]), null);
                Assert.True((bool)web[2]["success"]);
                Assert.Equal("snapshot", (string)web[2]["cmd"]);
                Assert.Null(web[2]["command"]);
                Assert.Null(web[2]["task"]);
            }
        }

        [Fact]
        public void CommitSuccess_RequiresAuthoritativeShapeAndSettlesWriteGate()
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            using (var task = NewTask(value => { sent.Add(ParseWire(value)); return true; }, web))
            {
                PrimeSession(task, sent);
                sent.Clear(); web.Clear();
                task.HandleWebRequest("commit", Request("commit", "tune.commit.success"));
                Assert.Equal("write_pending", task.WriteState);

                task.HandleFlashResponse(CommitResponse(sent[0]), null);

                Assert.Equal("idle", task.WriteState);
                Assert.True((bool)web[0]["success"]);
                Assert.Equal("txn.1", (string)web[0]["transactionId"]);
                Assert.Equal(1, (int)web[0]["writeEpoch"]);
                Assert.Null(web[0]["requiresReconcile"]);
            }
        }

        [Fact]
        public void DefinitiveCommitRejection_SettlesWithoutReconcile()
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            using (var task = NewTask(value => { sent.Add(ParseWire(value)); return true; }, web))
            {
                PrimeSession(task, sent);
                sent.Clear(); web.Clear();
                task.HandleWebRequest("commit", Request("commit", "tune.commit.rejected"));
                JObject rejected = CommonResponse(sent[0], "commit", false);
                rejected["error"] = "mod_unavailable";
                rejected["transactionId"] = "txn.rejected.1";

                task.HandleFlashResponse(rejected, null);

                Assert.Equal("idle", task.WriteState);
                Assert.False((bool)web[0]["success"]);
                Assert.Equal("mod_unavailable", (string)web[0]["error"]);
                Assert.Equal("txn.rejected.1", (string)web[0]["transactionId"]);
                Assert.Null(web[0]["requiresReconcile"]);
            }
        }

        [Fact]
        public void PanelRebindAndClose_AreBlockedUntilOldPendingRequestSettles()
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            using (var task = NewTask(value => { sent.Add(ParseWire(value)); return true; }, web))
            {
                task.HandleWebRequest("snapshot", Request("snapshot", "tune.lifecycle.pending"));
                Assert.False(task.CanRebind);
                Assert.False(task.CanClose);
                Assert.False(task.BindPanelInstance("workbench.instance.2"));
                Assert.False(task.HandlePanelClosed("workbench.instance.1"));
                Assert.Equal("workbench.instance.1", task.PanelInstanceId);

                JObject oldResponse = SnapshotResponse(sent[0]);
                task.HandleFlashResponse(oldResponse, null);
                Assert.True(task.CanRebind);
                Assert.True(task.CanClose);
                Assert.True(task.BindPanelInstance("workbench.instance.2"));
                Assert.Equal("workbench.instance.2", task.PanelInstanceId);

                task.HandleFlashResponse(oldResponse, null);
                Assert.Equal("idle", task.WriteState);
                Assert.Equal("workbench.instance.2", task.PanelInstanceId);
                Assert.Single(web);
            }
        }

        [Fact]
        public void BrowserTimeoutReconcile_IsBusyWhileWritePendingThenActsAsIdleBarrier()
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            using (var task = NewTask(value => { sent.Add(ParseWire(value)); return true; }, web))
            {
                PrimeSession(task, sent);
                sent.Clear(); web.Clear();
                task.HandleWebRequest("commit", Request("commit", "tune.race.commit"));

                JObject early = Request("snapshot", "tune.race.early");
                early["payload"]["reconcileAfterCallId"] = "tune.race.commit";
                task.HandleWebRequest("snapshot", early);
                Assert.Single(sent);
                Assert.Equal("busy", (string)web[0]["error"]);
                Assert.Equal("write_pending", task.WriteState);

                task.HandleFlashResponse(CommitResponse(sent[0]), null);
                Assert.Equal("idle", task.WriteState);

                JObject barrier = Request("snapshot", "tune.race.barrier");
                barrier["payload"]["reconcileAfterCallId"] = "tune.race.commit";
                task.HandleWebRequest("snapshot", barrier);
                Assert.Equal(2, sent.Count);
                JObject acknowledged = SnapshotResponse(sent[1]);
                acknowledged["reconciled"] = true;
                acknowledged["reconcileAfterCallId"] = "tune.race.commit";
                task.HandleFlashResponse(acknowledged, null);

                Assert.Equal("idle", task.WriteState);
                Assert.True((bool)web[2]["reconciled"]);
                Assert.Equal("tune.race.commit", (string)web[2]["reconcileAfterCallId"]);
            }
        }

        [Fact]
        public void TrySendFalse_IsDefinitivelyNotSentAndDoesNotRequireReconcile()
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            bool failSend = false;
            using (var task = NewTask(value =>
            {
                sent.Add(ParseWire(value));
                return !failSend;
            }, web))
            {
                PrimeSession(task, sent);
                sent.Clear(); web.Clear();
                failSend = true;

                task.HandleWebRequest("commit", Request("commit", "tune.commit.not.sent"));

                Assert.Single(sent);
                Assert.Single(web);
                Assert.Equal("not_sent", (string)web[0]["error"]);
                Assert.Null(web[0]["requiresReconcile"]);
                Assert.Equal("idle", task.WriteState);
                Assert.Equal(0, task.PendingCount);
            }
        }

        [Fact]
        public void ClientNotReadyBeforeDispatch_DoesNotCreateWriteWatermarkOrReconcileGate()
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            bool ready = true;
            using (var task = new EquipmentTuningTask(() => ready, value =>
            {
                sent.Add(ParseWire(value));
                return true;
            }))
            {
                task.SetPostToWeb(value => web.Add(JObject.Parse(value)));
                Assert.True(task.BindPanelInstance("workbench.instance.1"));
                PrimeSession(task, sent);
                sent.Clear();
                web.Clear();

                ready = false;
                task.HandleWebRequest("commit", Request("commit", "tune.commit.disconnected.preflight"));

                Assert.Empty(sent);
                JObject response = Assert.Single(web);
                Assert.Equal("disconnected", (string)response["error"]);
                Assert.Null(response["requiresReconcile"]);
                Assert.Null(response["reconcileAfterCallId"]);
                Assert.Equal("idle", task.WriteState);
                Assert.Equal(0, task.WriteEpoch);
                Assert.Equal("tuning.session.1", task.ActiveViewSessionId);
                Assert.True(task.CanClose);
            }
        }

        [Fact]
        public void DetachRequiresExactBoundSessionAndInvalidatesOldViewBeforeStorageSwitch()
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            using (var task = NewTask(value => { sent.Add(ParseWire(value)); return true; }, web))
            {
                PrimeSession(task, sent);
                sent.Clear();
                web.Clear();

                JObject malformed = Request("detach", "tune.detach.extra");
                malformed["payload"]["unexpected"] = true;
                task.HandleWebRequest("detach", malformed);
                Assert.Empty(sent);
                Assert.Equal("invalid_payload", (string)Assert.Single(web)["error"]);
                web.Clear();

                JObject staleSession = Request("detach", "tune.detach.stale.session");
                staleSession["payload"]["viewSessionId"] = "tuning.session.stale";
                task.HandleWebRequest("detach", staleSession);
                Assert.Empty(sent);
                Assert.Equal("view_session_expired", (string)Assert.Single(web)["error"]);
                web.Clear();

                task.HandleWebRequest("detach", Request("detach", "tune.detach.1"));
                JObject detachCommand = Assert.Single(sent);
                Assert.Equal("equipmentTuningDetach", (string)detachCommand["action"]);
                Assert.Equal("tuning.session.1", (string)detachCommand["viewSessionId"]);
                Assert.False(task.CanClose);

                task.HandleWebRequest("commit", Request("commit", "tune.commit.during.detach"));
                Assert.Single(sent);
                Assert.Equal("view_session_expired", (string)Assert.Single(web)["error"]);

                task.HandleFlashResponse(CommonResponse(detachCommand, "detach", true), null);
                Assert.Null(task.ActiveViewSessionId);
                Assert.True(task.CanClose);
                Assert.Equal("detach", (string)web[1]["cmd"]);
                Assert.True((bool)web[1]["success"]);

                task.HandleWebRequest("commit", Request("commit", "tune.commit.after.detach"));
                Assert.Single(sent);
                Assert.Equal("view_session_expired", (string)web[2]["error"]);
                Assert.Equal("tuning.session.1", (string)web[2]["viewSessionId"]);
            }
        }

        [Fact]
        public void ClearPending_NewSessionSnapshotReturnsTrustedHintAndExactBarrierClearsGate()
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            using (var task = NewTask(value => { sent.Add(ParseWire(value)); return true; }, web))
            {
                PrimeSession(task, sent);
                sent.Clear(); web.Clear();
                task.HandleWebRequest("commit", Request("commit", "tune.disconnect.write"));
                Assert.Equal("write_pending", task.WriteState);
                Assert.Single(sent);

                task.ClearPending();
                sent.Clear();
                Assert.Equal("needs_reconcile", task.WriteState);
                Assert.False(task.HasBoundPanel);
                Assert.True(task.BindPanelInstance("workbench.instance.2"));

                JObject normal = Request("snapshot", "tune.reopen.snapshot");
                normal["panelInstanceId"] = "workbench.instance.2";
                normal["payload"]["viewSessionId"] = "tuning.session.2";
                task.HandleWebRequest("snapshot", normal);

                Assert.Empty(sent);
                JObject hint = Assert.Single(web);
                Assert.Equal("reconcile_required", (string)hint["error"]);
                Assert.True((bool)hint["requiresReconcile"]);
                Assert.Equal("tune.disconnect.write", (string)hint["reconcileAfterCallId"]);
                Assert.Equal("workbench.instance.2", (string)hint["panelInstanceId"]);
                Assert.Equal("tuning.session.2", (string)hint["viewSessionId"]);

                JObject barrier = Request("snapshot", "tune.reopen.barrier");
                barrier["panelInstanceId"] = "workbench.instance.2";
                barrier["payload"]["viewSessionId"] = "tuning.session.2";
                barrier["payload"]["reconcileAfterCallId"] = (string)hint["reconcileAfterCallId"];
                task.HandleWebRequest("snapshot", barrier);
                JObject command = Assert.Single(sent);
                Assert.Equal("tune.disconnect.write", (string)command["reconcileAfterCallId"]);
                Assert.Equal(1, (int)command["writeEpoch"]);

                JObject acknowledged = SnapshotResponse(command);
                acknowledged["reconciled"] = true;
                acknowledged["reconcileAfterCallId"] = "tune.disconnect.write";
                task.HandleFlashResponse(acknowledged, null);

                Assert.Equal("idle", task.WriteState);
                Assert.True((bool)web[1]["success"]);
                Assert.True((bool)web[1]["reconciled"]);
                Assert.Equal("tune.disconnect.write", (string)web[1]["reconcileAfterCallId"]);
            }
        }

        [Fact]
        public void MalformedCommit_RequiresMatchingWatermarkSnapshotBeforeAnotherWrite()
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            using (var task = NewTask(value => { sent.Add(ParseWire(value)); return true; }, web))
            {
                PrimeSession(task, sent);
                sent.Clear(); web.Clear();

                task.HandleWebRequest("commit", Request("commit", "tune.commit.unknown"));
                JObject malformed = CommitResponse(sent[0]);
                malformed.Remove("transactionId");
                task.HandleFlashResponse(malformed, null);
                Assert.Equal("needs_reconcile", task.WriteState);
                Assert.True((bool)web[0]["requiresReconcile"]);

                task.HandleWebRequest("commit", Request("commit", "tune.commit.blocked"));
                Assert.Single(sent);
                Assert.Equal("reconcile_required", (string)web[1]["error"]);

                JObject reconcile = Request("snapshot", "tune.reconcile.first");
                reconcile["payload"]["reconcileAfterCallId"] = "tune.commit.unknown";
                task.HandleWebRequest("snapshot", reconcile);
                task.HandleFlashResponse(SnapshotResponse(sent[1]), null);
                Assert.Equal("needs_reconcile", task.WriteState);
                Assert.True((bool)web[2]["requiresReconcile"]);

                reconcile = Request("snapshot", "tune.reconcile.confirmed");
                reconcile["payload"]["reconcileAfterCallId"] = "tune.commit.unknown";
                task.HandleWebRequest("snapshot", reconcile);
                JObject acknowledged = SnapshotResponse(sent[2]);
                acknowledged["reconciled"] = true;
                acknowledged["reconcileAfterCallId"] = "tune.commit.unknown";
                task.HandleFlashResponse(acknowledged, null);

                Assert.Equal("idle", task.WriteState);
                Assert.True((bool)web[3]["reconciled"]);
                Assert.Equal("tune.commit.unknown", (string)web[3]["reconcileAfterCallId"]);
                Assert.Single(sent.FindAll(command => (string)command["action"] == "equipmentTuningCommit"));
            }
        }

        [Fact]
        public void TimedOutCommit_IsNeverReplayedAndEntersReconcileGate()
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            using (var task = NewTask(value => { sent.Add(ParseWire(value)); return true; }, web, 20))
            {
                PrimeSession(task, sent);
                sent.Clear(); web.Clear();

                task.HandleWebRequest("commit", Request("commit", "tune.commit.timeout"));

                Assert.True(SpinWait.SpinUntil(() => web.Count == 1, 2000));
                Assert.Equal("timeout", (string)web[0]["error"]);
                Assert.True((bool)web[0]["requiresReconcile"]);
                Assert.Equal("needs_reconcile", task.WriteState);
                Assert.Single(sent);
                Assert.Equal("equipmentTuningCommit", (string)sent[0]["action"]);
            }
        }

        private static EquipmentTuningTask NewTask(Func<string, bool> send,
            List<JObject> web, int timeoutMs = 10000)
        {
            var task = new EquipmentTuningTask(() => true, send, timeoutMs);
            if (web != null) task.SetPostToWeb(value => web.Add(JObject.Parse(value)));
            Assert.True(task.BindPanelInstance("workbench.instance.1"));
            return task;
        }

        private static void PrimeSession(EquipmentTuningTask task, List<JObject> sent)
        {
            task.HandleWebRequest("snapshot", Request("snapshot", "tune.prime." + sent.Count));
            task.HandleFlashResponse(SnapshotResponse(sent[sent.Count - 1]), null);
        }

        private static JObject Request(string cmd, string callId, string operation = null)
        {
            var payload = new JObject
            {
                ["v"] = 1,
                ["viewSessionId"] = "tuning.session.1"
            };
            if (cmd == "snapshot") payload["source"] = Source(7, "lease.source.7");
            else if (cmd == "preview")
            {
                payload["operation"] = operation;
                payload["source"] = Source(7, "lease.source.7");
                if (operation == "enhance") payload["targetLevel"] = 8;
                else if (operation == "convert") payload["target"] = Source(8, "lease.target.8");
                else if (operation != "detach_all_mods") payload["candidateKey"] = "候选.一";
                if (operation == "replace_mod") payload["replaceCandidateKey"] = "候选.旧";
            }
            else if (cmd == "commit") payload["expectedTuningToken"] = "tuning.token.1";
            else if (cmd == "tooltip") payload["candidateKey"] = "候选.一";

            return new JObject
            {
                ["type"] = "panel",
                ["panel"] = "workbench",
                ["domain"] = "equipment_tuning",
                ["cmd"] = cmd,
                ["callId"] = callId,
                ["panelInstanceId"] = "workbench.instance.1",
                ["payload"] = payload
            };
        }

        private static JObject Source(int slot, string lease)
        {
            return new JObject
            {
                ["containerId"] = "背包",
                ["slot"] = slot,
                ["expectedLease"] = lease
            };
        }

        private static JObject CommonResponse(JObject command, string cmd, bool success)
        {
            return new JObject
            {
                ["task"] = "equipment_tuning_response",
                ["callId"] = (int)command["callId"],
                ["v"] = 1,
                ["success"] = success,
                ["command"] = cmd,
                ["panelInstanceId"] = (string)command["panelInstanceId"],
                ["viewSessionId"] = (string)command["viewSessionId"],
                ["writeEpoch"] = (int)command["writeEpoch"]
            };
        }

        private static JObject SnapshotResponse(JObject command)
        {
            JObject response = CommonResponse(command, "snapshot", true);
            response["snapshot"] = Snapshot();
            return response;
        }

        private static JObject PreviewResponse(JObject command, string operation)
        {
            JObject response = CommonResponse(command, "preview", true);
            response["tuningToken"] = "tuning.token.1";
            response["operation"] = operation;
            response["before"] = new JObject { ["level"] = 7 };
            response["after"] = new JObject { ["level"] = 8 };
            response["materials"] = new JArray();
            response["canCommit"] = true;
            return response;
        }

        private static JObject CommitResponse(JObject command)
        {
            JObject response = CommonResponse(command, "commit", true);
            response["tuningToken"] = "tuning.token.1";
            response["operation"] = "enhance";
            response["before"] = new JObject { ["level"] = 7 };
            response["after"] = new JObject { ["level"] = 8 };
            response["materials"] = new JArray();
            response["canCommit"] = true;
            response["snapshot"] = Snapshot();
            response["inventorySnapshots"] = new JArray();
            response["transactionId"] = "txn.1";
            return response;
        }

        private static JObject TooltipResponse(JObject command)
        {
            JObject response = CommonResponse(command, "tooltip", true);
            response["candidateKey"] = "候选.一";
            response["introHTML"] = "<b>候选</b>";
            response["descHTML"] = "候选说明";
            response["itemType"] = "收集品";
            response["itemUse"] = "材料";
            response["html"] = "<b>候选</b>候选说明";
            response["text"] = "候选";
            return response;
        }

        private static JObject Snapshot()
        {
            return new JObject
            {
                ["source"] = Source(7, "lease.source.7"),
                ["equipment"] = new JObject { ["itemKind"] = "equipment", ["level"] = 7 },
                ["enhance"] = new JObject { ["currentLevel"] = 7, ["maxLevel"] = 13 },
                ["tierCandidates"] = new JArray(),
                ["modCandidates"] = new JArray(),
                ["materials"] = new JArray()
            };
        }

        private static JObject ParseWire(string value)
        {
            return JObject.Parse(value.TrimEnd('\0'));
        }
    }
}
