using System;
using System.Collections.Generic;
using System.Threading;
using CF7Launcher.Guardian;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace Launcher.Tests.Tasks
{
    public sealed class EquipmentTuningTaskTests
    {
        private sealed class CommitHarness :
            IDisposable
        {
            public readonly List<JObject> Sent =
                new List<JObject>();
            public readonly List<JObject> Web =
                new List<JObject>();
            public readonly EquipmentTuningTask Task;
            public readonly JObject Command;

            public CommitHarness(JObject source)
            {
                Task = NewTask(
                    value =>
                    {
                        Sent.Add(
                            ParseWire(value));
                        return true;
                    },
                    Web);
                PrimeSession(
                    Task, Sent, source);
                Sent.Clear();
                Web.Clear();
                Task.HandleWebRequest(
                    "commit",
                    Request(
                        "commit",
                        "tune.harness.commit"));
                Command = Assert.Single(Sent);
            }

            public void Dispose()
            {
                Task.Dispose();
            }
        }

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
                Assert.Equal(
                    "inventory",
                    (string)command["source"][
                        "sourceKind"]);
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
                Assert.Equal("男", (string)response["snapshot"]["gender"]);
            }
        }

        [Fact]
        public void SuccessfulSnapshot_RequiresCanonicalGender()
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            using (var task = NewTask(value => { sent.Add(ParseWire(value)); return true; }, web))
            {
                task.HandleWebRequest("snapshot", Request("snapshot", "tune.gender.missing"));
                JObject missing = SnapshotResponse(sent[0]);
                ((JObject)missing["snapshot"]).Remove("gender");
                task.HandleFlashResponse(missing, null);

                task.HandleWebRequest("snapshot", Request("snapshot", "tune.gender.invalid"));
                JObject invalid = SnapshotResponse(sent[1]);
                invalid["snapshot"]["gender"] = "female";
                task.HandleFlashResponse(invalid, null);

                task.HandleWebRequest("snapshot", Request("snapshot", "tune.gender.female"));
                JObject female = SnapshotResponse(sent[2]);
                female["snapshot"]["gender"] = "女";
                task.HandleFlashResponse(female, null);

                Assert.Equal("malformed_response", (string)web[0]["error"]);
                Assert.Equal("malformed_response", (string)web[1]["error"]);
                Assert.True((bool)web[2]["success"]);
                Assert.Equal("女", (string)web[2]["snapshot"]["gender"]);
            }
        }

        [Fact]
        public void SuccessfulPreview_RequiresAs2SubjectProjectionShape()
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            using (var task = NewTask(value => { sent.Add(ParseWire(value)); return true; }, web))
            {
                task.HandleWebRequest("snapshot", Request("snapshot", "tune.projection.snapshot"));
                task.HandleFlashResponse(SnapshotResponse(Assert.Single(sent)), null);
                sent.Clear();
                web.Clear();

                task.HandleWebRequest(
                    "preview",
                    Request("preview", "tune.projection.nested", "enhance"));
                JObject nested = PreviewResponse(Assert.Single(sent), "enhance");
                task.HandleFlashResponse(nested, null);

                JObject accepted = Assert.Single(web);
                Assert.True((bool)accepted["success"]);
                Assert.Equal(
                    "inventory",
                    (string)accepted["before"]["source"]["source"]["sourceKind"]);

                sent.Clear();
                web.Clear();
                task.HandleWebRequest(
                    "preview",
                    Request("preview", "tune.projection.flattened", "enhance"));
                JObject flattened = PreviewResponse(Assert.Single(sent), "enhance");
                JObject source =
                    (JObject)flattened["before"]["source"]["source"];
                flattened["before"] = new JObject
                {
                    ["level"] = 7,
                    ["source"] = source.DeepClone()
                };
                flattened["after"] = new JObject
                {
                    ["level"] = 8,
                    ["source"] = source.DeepClone()
                };
                task.HandleFlashResponse(flattened, null);

                Assert.Equal(
                    "malformed_response",
                    (string)Assert.Single(web)["error"]);
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
                    Assert.Equal(
                        "inventory",
                        (string)command["target"][
                            "sourceKind"]);
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
                Assert.Equal(
                    1,
                    task.PreviewBindingCount);

                failSend = false;
                task.HandleWebRequest(
                    "commit",
                    Request(
                        "commit",
                        "tune.commit.retry"));
                Assert.Equal(2, sent.Count);
                task.HandleFlashResponse(
                    CommitResponse(sent[1]),
                    null);

                Assert.True((bool)web[1]["success"]);
                Assert.Equal("idle", task.WriteState);
                Assert.Equal(
                    0,
                    task.PreviewBindingCount);
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

        [Theory]
        [InlineData("头部装备")]
        [InlineData("上装装备")]
        [InlineData("下装装备")]
        [InlineData("手部装备")]
        [InlineData("脚部装备")]
        [InlineData("颈部装备")]
        [InlineData("长枪")]
        [InlineData("手枪")]
        [InlineData("手枪2")]
        [InlineData("刀")]
        [InlineData("手雷")]
        public void LoadoutSource_AcceptsOnlyFrozenElevenSlotKeys(
            string slotKey)
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            using (var task = NewTask(
                value =>
                {
                    sent.Add(ParseWire(value));
                    return true;
                },
                web))
            {
                JObject source =
                    LoadoutSource(17, slotKey, 23);
                task.HandleWebRequest(
                    "snapshot",
                    Request(
                        "snapshot",
                        "tune.loadout.slot."
                            + sent.Count,
                        null,
                        source));

                JObject command =
                    Assert.Single(sent);
                Assert.Equal(
                    "loadout",
                    (string)command["source"][
                        "sourceKind"]);
                Assert.Equal(
                    slotKey,
                    (string)command["source"][
                        "slotKey"]);
                Assert.Equal(
                    4,
                    ((JObject)command["source"]).Count);
                task.HandleFlashResponse(
                    SnapshotResponse(command),
                    null);
                Assert.True(
                    (bool)Assert.Single(web)[
                        "success"]);
            }
        }

        [Fact]
        public void DualSource_RejectsLegacyMixedAndOutOfRangeShapes()
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            using (var task = NewTask(
                value =>
                {
                    sent.Add(ParseWire(value));
                    return true;
                },
                web))
            {
                var sources = new List<JObject>
                {
                    new JObject
                    {
                        ["containerId"] = "背包",
                        ["slot"] = 7,
                        ["expectedLease"] =
                            "legacy.lease"
                    },
                    new JObject
                    {
                        ["sourceKind"] = "inventory",
                        ["containerId"] = "背包",
                        ["slot"] = 50,
                        ["expectedLease"] =
                            "bad.slot"
                    },
                    new JObject
                    {
                        ["sourceKind"] = "loadout",
                        ["sessionGeneration"] = 0,
                        ["slotKey"] = "手枪2",
                        ["expectedLoadoutRevision"] = 3
                    },
                    new JObject
                    {
                        ["sourceKind"] = "loadout",
                        ["sessionGeneration"] = 7,
                        ["slotKey"] = "不存在",
                        ["expectedLoadoutRevision"] = 3
                    },
                    new JObject
                    {
                        ["sourceKind"] = "loadout",
                        ["sessionGeneration"] = 7,
                        ["slotKey"] = "手枪2",
                        ["expectedLoadoutRevision"] = -1
                    },
                    new JObject
                    {
                        ["sourceKind"] = "loadout",
                        ["sessionGeneration"] = 7,
                        ["slotKey"] = "手枪2",
                        ["expectedLoadoutRevision"] = 3,
                        ["containerId"] = "背包"
                    }
                };
                for (int i = 0;
                    i < sources.Count; i++)
                {
                    task.HandleWebRequest(
                        "snapshot",
                        Request(
                            "snapshot",
                            "tune.bad.source." + i,
                            null,
                            sources[i]));
                }

                Assert.Empty(sent);
                Assert.Equal(
                    sources.Count, web.Count);
                Assert.All(
                    web,
                    response => Assert.Equal(
                        "invalid_payload",
                        (string)response["error"]));
            }
        }

        [Fact]
        public void LoadoutPreview_RejectsConvertBeforeFlashDispatch()
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            using (var task = NewTask(
                value =>
                {
                    sent.Add(ParseWire(value));
                    return true;
                },
                web))
            {
                JObject source =
                    LoadoutSource(
                        9, "手枪2", 12);
                PrimeSession(
                    task, sent, source);
                sent.Clear();
                web.Clear();

                task.HandleWebRequest(
                    "preview",
                    Request(
                        "preview",
                        "tune.loadout.convert",
                        "convert",
                        source));

                Assert.Empty(sent);
                Assert.Equal(
                    "invalid_payload",
                    (string)Assert.Single(web)[
                        "error"]);
            }
        }

        [Fact]
        public void LoadoutSnapshotAndPreview_RejectStaleEchoedSource()
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            JObject source =
                LoadoutSource(
                    9, "手枪2", 12);
            using (var task = NewTask(
                value =>
                {
                    sent.Add(ParseWire(value));
                    return true;
                },
                web))
            {
                task.HandleWebRequest(
                    "snapshot",
                    Request(
                        "snapshot",
                        "tune.loadout.stale.snapshot",
                        null,
                        source));
                JObject staleSnapshot =
                    SnapshotResponse(
                        Assert.Single(sent));
                staleSnapshot["snapshot"][
                    "source"][
                    "expectedLoadoutRevision"] =
                    11;
                task.HandleFlashResponse(
                    staleSnapshot, null);
                Assert.Equal(
                    "malformed_response",
                    (string)web[0]["error"]);

                sent.Clear();
                task.HandleWebRequest(
                    "preview",
                    Request(
                        "preview",
                        "tune.loadout.stale.preview",
                        "enhance",
                        source));
                JObject stalePreview =
                    PreviewResponse(
                        Assert.Single(sent),
                        "enhance",
                        "tuning.token.stale");
                stalePreview["after"]["source"]["source"][
                    "sessionGeneration"] = 8;
                task.HandleFlashResponse(
                    stalePreview, null);

                Assert.Equal(
                    "malformed_response",
                    (string)web[1]["error"]);
                Assert.Equal(
                    0,
                    task.PreviewBindingCount);
            }
        }

        [Fact]
        public void ConvertTarget_RejectsLegacyThreeKeyInventoryReference()
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            using (var task = NewTask(
                value =>
                {
                    sent.Add(ParseWire(value));
                    return true;
                },
                web))
            {
                PrimeSession(task, sent);
                sent.Clear();
                web.Clear();
                JObject request =
                    Request(
                        "preview",
                        "tune.convert.legacy.target",
                        "convert");
                ((JObject)request["payload"][
                    "target"]).Remove(
                    "sourceKind");

                task.HandleWebRequest(
                    "preview", request);

                Assert.Empty(sent);
                Assert.Equal(
                    "invalid_payload",
                    (string)Assert.Single(web)[
                        "error"]);
            }
        }

        [Fact]
        public void LoadoutCommit_RequiresExactPlusOneOrNoOpRevision()
        {
            JObject source =
                LoadoutSource(
                    21, "手枪2", 41);
            using (var harness =
                new CommitHarness(source))
            {
                JObject response =
                    CommitResponse(
                        harness.Command,
                        source,
                        false);
                harness.Task.HandleFlashResponse(
                    response, null);

                JObject web =
                    Assert.Single(harness.Web);
                Assert.True(
                    (bool)web["success"]);
                Assert.Equal(
                    42,
                    (int)web["snapshot"]["source"][
                        "expectedLoadoutRevision"]);
                Assert.Empty(
                    (JArray)web[
                        "inventorySnapshots"]);
                Assert.Equal(
                    "idle",
                    harness.Task.WriteState);
            }

            using (var harness =
                new CommitHarness(source))
            {
                JObject response =
                    CommitResponse(
                        harness.Command,
                        source,
                        true);
                harness.Task.HandleFlashResponse(
                    response, null);

                JObject web =
                    Assert.Single(harness.Web);
                Assert.True(
                    (bool)web["success"]);
                Assert.Equal(
                    41,
                    (int)web["snapshot"]["source"][
                        "expectedLoadoutRevision"]);
                Assert.Equal(
                    "idle",
                    harness.Task.WriteState);
            }
        }

        [Fact]
        public void LoadoutCommit_RejectsSourceDriftAndInventorySnapshots()
        {
            JObject source =
                LoadoutSource(
                    21, "手枪2", 41);

            AssertMalformedLoadoutCommit(
                source,
                response =>
                {
                    response["after"]["source"]["source"][
                        "expectedLoadoutRevision"] =
                        41;
                });
            AssertMalformedLoadoutCommit(
                source,
                response =>
                {
                    response["snapshot"]["source"][
                        "sessionGeneration"] = 22;
                });
            AssertMalformedLoadoutCommit(
                source,
                response =>
                {
                    response["after"]["source"]["source"][
                        "slotKey"] = "刀";
                });
            AssertMalformedLoadoutCommit(
                source,
                response =>
                {
                    ((JArray)response[
                        "inventorySnapshots"]).Add(
                        new JObject());
                });
            AssertMalformedLoadoutCommit(
                source,
                response =>
                {
                    response["tuningToken"] =
                        "tuning.token.drift";
                });
            AssertMalformedLoadoutCommit(
                source,
                response =>
                {
                    response["after"]["source"]["source"][
                        "expectedLoadoutRevision"] =
                        42;
                    response["snapshot"]["source"][
                        "expectedLoadoutRevision"] =
                        42;
                },
                true);
        }

        [Fact]
        public void InventoryCommit_RequiresNewLeaseAndFullBackpackSnapshot()
        {
            JObject source =
                Source(
                    7, "lease.source.7");
            using (var harness =
                new CommitHarness(source))
            {
                JObject response =
                    CommitResponse(
                        harness.Command,
                        source,
                        false);
                response["inventorySnapshots"] =
                    new JArray();
                harness.Task.HandleFlashResponse(
                    response, null);

                Assert.Equal(
                    "malformed_response",
                    (string)Assert.Single(
                        harness.Web)["error"]);
                Assert.Equal(
                    "needs_reconcile",
                    harness.Task.WriteState);
            }

            using (var harness =
                new CommitHarness(source))
            {
                JObject response =
                    CommitResponse(
                        harness.Command,
                        source,
                        false);
                response["after"]["source"]["source"] =
                    source.DeepClone();
                response["snapshot"]["source"] =
                    source.DeepClone();
                harness.Task.HandleFlashResponse(
                    response, null);

                Assert.Equal(
                    "malformed_response",
                    (string)Assert.Single(
                        harness.Web)["error"]);
                Assert.Equal(
                    "needs_reconcile",
                    harness.Task.WriteState);
            }
        }

        [Fact]
        public void CommitRequiresSuccessfulPreviewBindingButTokenAuthorityRemainsAs2()
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            using (var task = NewTask(
                value =>
                {
                    sent.Add(ParseWire(value));
                    return true;
                },
                web))
            {
                task.HandleWebRequest(
                    "snapshot",
                    Request(
                        "snapshot",
                        "tune.no.preview.snapshot"));
                task.HandleFlashResponse(
                    SnapshotResponse(
                        Assert.Single(sent)),
                    null);
                sent.Clear();
                web.Clear();

                task.HandleWebRequest(
                    "commit",
                    Request(
                        "commit",
                        "tune.no.preview.commit"));

                Assert.Empty(sent);
                Assert.Equal(
                    "invalid_payload",
                    (string)Assert.Single(web)[
                        "error"]);
                Assert.Equal(
                    "idle",
                    task.WriteState);
            }
        }

        [Fact]
        public void PreviewBindings_AreCappedAtSixtyFourAndEvictOldest()
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            using (var task = NewTask(
                value =>
                {
                    sent.Add(ParseWire(value));
                    return true;
                },
                web))
            {
                task.HandleWebRequest(
                    "snapshot",
                    Request(
                        "snapshot",
                        "tune.capacity.snapshot"));
                task.HandleFlashResponse(
                    SnapshotResponse(
                        Assert.Single(sent)),
                    null);

                for (int i = 0; i < 65; i++)
                {
                    task.HandleWebRequest(
                        "preview",
                        Request(
                            "preview",
                            "tune.capacity.preview." + i,
                            "enhance"));
                    JObject command =
                        sent[sent.Count - 1];
                    task.HandleFlashResponse(
                        PreviewResponse(
                            command,
                            "enhance",
                            "tuning.token.capacity." + i),
                        null);
                }

                Assert.Equal(
                    64,
                    task.PreviewBindingCount);
                int sentBeforeCommit =
                    sent.Count;
                JObject evicted =
                    Request(
                        "commit",
                        "tune.capacity.evicted");
                evicted["payload"][
                    "expectedTuningToken"] =
                    "tuning.token.capacity.0";
                task.HandleWebRequest(
                    "commit", evicted);

                Assert.Equal(
                    sentBeforeCommit,
                    sent.Count);
                Assert.Equal(
                    "invalid_payload",
                    (string)web[web.Count - 1][
                        "error"]);
                Assert.Equal(
                    64,
                    task.PreviewBindingCount);

                JObject newest =
                    Request(
                        "commit",
                        "tune.capacity.newest");
                newest["payload"][
                    "expectedTuningToken"] =
                    "tuning.token.capacity.64";
                task.HandleWebRequest(
                    "commit", newest);

                Assert.Equal(
                    sentBeforeCommit + 1,
                    sent.Count);
                Assert.Equal(
                    63,
                    task.PreviewBindingCount);
                task.HandleFlashResponse(
                    CommitResponse(
                        sent[sent.Count - 1]),
                    null);
                Assert.True(
                    (bool)web[web.Count - 1][
                        "success"]);
                Assert.Equal(
                    "idle",
                    task.WriteState);
            }
        }

        [Fact]
        public void LoadoutUnknown_ReconcilesOnlyAfterOrderedExternalSnapshotAndWatermarkAck()
        {
            var order = new List<string>();
            var sent = new List<JObject>();
            var web = new List<JObject>();
            JObject source =
                LoadoutSource(
                    31, "手枪2", 8);
            using (var tuning = NewTask(
                value =>
                {
                    JObject wire =
                        ParseWire(value);
                    sent.Add(wire);
                    order.Add(
                        (string)wire["action"]);
                    return true;
                },
                web))
            using (var loadout =
                new CharacterBuildTask(
                    delegate(string value)
                    {
                        JObject wire =
                            ParseWire(value);
                        order.Add(
                            (string)wire["action"]);
                        return true;
                    }))
            {
                PrimeSession(
                    tuning, sent, source);
                sent.Clear();
                web.Clear();
                order.Clear();

                tuning.HandleWebRequest(
                    "commit",
                    Request(
                        "commit",
                        "tune.loadout.unknown"));
                JObject malformed =
                    CommitResponse(
                        Assert.Single(sent),
                        source,
                        false);
                malformed.Remove(
                    "transactionId");
                tuning.HandleFlashResponse(
                    malformed, null);
                Assert.Equal(
                    "needs_reconcile",
                    tuning.WriteState);

                Assert.True(
                    loadout.TryBindPanelInstance(
                        "workbench.instance.1"));
                loadout.HandleWebRequest(
                    "snapshot",
                    LoadoutSnapshotRequest(
                        "loadout.current.1"));
                Assert.Equal(
                    "needs_reconcile",
                    tuning.WriteState);

                JObject currentSource =
                    LoadoutSource(
                        31, "手枪2", 9);
                JObject reconcile =
                    Request(
                        "snapshot",
                        "tune.loadout.reconcile",
                        null,
                        currentSource);
                reconcile["payload"][
                    "reconcileAfterCallId"] =
                    "tune.loadout.unknown";
                tuning.HandleWebRequest(
                    "snapshot", reconcile);
                JObject command = sent[1];
                Assert.Equal(
                    "needs_reconcile",
                    tuning.WriteState);

                JObject acknowledged =
                    SnapshotResponse(command);
                acknowledged["reconciled"] =
                    true;
                acknowledged[
                    "reconcileAfterCallId"] =
                    "tune.loadout.unknown";
                tuning.HandleFlashResponse(
                    acknowledged, null);

                Assert.Equal(
                    new[]
                    {
                        "equipmentTuningCommit",
                        "characterBuildSnapshot",
                        "equipmentTuningSnapshot"
                    },
                    order);
                Assert.Equal(
                    "idle",
                    tuning.WriteState);
                Assert.Single(
                    order.FindAll(
                        action => action
                            == "equipmentTuningCommit"));

                tuning.HandleWebRequest(
                    "commit",
                    Request(
                        "commit",
                        "tune.loadout.replay"));
                Assert.Equal(
                    2,
                    sent.Count);
                Assert.Equal(
                    "invalid_payload",
                    (string)web[2]["error"]);
            }
        }

        private static void AssertMalformedLoadoutCommit(
            JObject source,
            Action<JObject> mutate,
            bool noOp = false)
        {
            using (var harness =
                new CommitHarness(source))
            {
                JObject response =
                    CommitResponse(
                        harness.Command,
                        source,
                        noOp);
                mutate(response);
                harness.Task.HandleFlashResponse(
                    response, null);
                Assert.Equal(
                    "malformed_response",
                    (string)Assert.Single(
                        harness.Web)["error"]);
                Assert.Equal(
                    "needs_reconcile",
                    harness.Task.WriteState);
            }
        }

        private static JObject LoadoutSnapshotRequest(
            string callId)
        {
            return new JObject
            {
                ["type"] = "panel",
                ["panel"] = "workbench",
                ["domain"] = "loadout",
                ["cmd"] = "snapshot",
                ["callId"] = callId,
                ["panelInstanceId"] =
                    "workbench.instance.1",
                ["payload"] =
                    new JObject
                    {
                        ["v"] = 1
                    }
            };
        }

        private static EquipmentTuningTask NewTask(Func<string, bool> send,
            List<JObject> web, int timeoutMs = 10000)
        {
            var task = new EquipmentTuningTask(() => true, send, timeoutMs);
            if (web != null) task.SetPostToWeb(value => web.Add(JObject.Parse(value)));
            Assert.True(task.BindPanelInstance("workbench.instance.1"));
            return task;
        }

        private static void PrimeSession(
            EquipmentTuningTask task,
            List<JObject> sent,
            JObject source = null,
            string tuningToken =
                "tuning.token.1")
        {
            task.HandleWebRequest(
                "snapshot",
                Request(
                    "snapshot",
                    "tune.prime." + sent.Count,
                    null,
                    source));
            task.HandleFlashResponse(SnapshotResponse(sent[sent.Count - 1]), null);
            task.HandleWebRequest(
                "preview",
                Request(
                    "preview",
                    "tune.prime.preview."
                        + sent.Count,
                    "enhance",
                    source));
            task.HandleFlashResponse(
                PreviewResponse(
                    sent[sent.Count - 1],
                    "enhance",
                    tuningToken),
                null);
        }

        private static JObject Request(
            string cmd,
            string callId,
            string operation = null,
            JObject source = null)
        {
            var payload = new JObject
            {
                ["v"] = 1,
                ["viewSessionId"] = "tuning.session.1"
            };
            if (cmd == "snapshot")
                payload["source"] = (source
                    ?? Source(
                        7,
                        "lease.source.7"))
                    .DeepClone();
            else if (cmd == "preview")
            {
                payload["operation"] = operation;
                payload["source"] = (source
                    ?? Source(
                        7,
                        "lease.source.7"))
                    .DeepClone();
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
                ["sourceKind"] = "inventory",
                ["containerId"] = "背包",
                ["slot"] = slot,
                ["expectedLease"] = lease
            };
        }

        private static JObject LoadoutSource(
            int sessionGeneration,
            string slotKey,
            int expectedLoadoutRevision)
        {
            return new JObject
            {
                ["sourceKind"] = "loadout",
                ["sessionGeneration"] =
                    sessionGeneration,
                ["slotKey"] = slotKey,
                ["expectedLoadoutRevision"] =
                    expectedLoadoutRevision
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
            response["snapshot"] = Snapshot(
                command["source"] as JObject);
            return response;
        }

        private static JObject PreviewResponse(
            JObject command,
            string operation,
            string tuningToken =
                "tuning.token.1")
        {
            JObject response = CommonResponse(command, "preview", true);
            response["tuningToken"] = tuningToken;
            response["operation"] = operation;
            JObject source =
                (JObject)command["source"].DeepClone();
            response["before"] =
                TuningProjection(source, 7);
            response["after"] =
                TuningProjection(source, 8);
            response["materials"] = new JArray();
            response["canCommit"] = true;
            return response;
        }

        private static JObject CommitResponse(
            JObject command,
            JObject beforeSource = null,
            bool noOp = false)
        {
            JObject response = CommonResponse(command, "commit", true);
            response["tuningToken"] =
                (string)command[
                    "expectedTuningToken"];
            response["operation"] = "enhance";
            beforeSource = beforeSource
                ?? Source(7, "lease.source.7");
            JObject afterSource =
                BuildPostSource(
                    beforeSource, noOp);
            response["before"] =
                TuningProjection(
                    beforeSource,
                    7);
            response["after"] =
                TuningProjection(
                    afterSource,
                    noOp ? 7 : 8);
            response["materials"] = new JArray();
            response["canCommit"] = true;
            response["noOp"] = noOp;
            response["snapshot"] = Snapshot(
                afterSource);
            response["inventorySnapshots"] =
                (string)beforeSource["sourceKind"]
                    == "loadout"
                ? new JArray()
                : FullBackpackSnapshots();
            response["transactionId"] = "txn.1";
            return response;
        }

        private static JObject TuningProjection(
            JObject source,
            int level)
        {
            return new JObject
            {
                ["source"] = new JObject
                {
                    ["source"] =
                        source.DeepClone(),
                    ["equipment"] =
                        new JObject
                        {
                            ["itemKind"] =
                                "equipment",
                            ["level"] = level
                        }
                }
            };
        }

        private static JObject BuildPostSource(
            JObject beforeSource,
            bool noOp)
        {
            JObject post =
                (JObject)beforeSource.DeepClone();
            if (noOp) return post;
            if ((string)post["sourceKind"]
                == "loadout")
            {
                post["expectedLoadoutRevision"] =
                    (int)post[
                        "expectedLoadoutRevision"] + 1;
            }
            else
            {
                post["expectedLease"] =
                    (string)post["expectedLease"]
                    + ".post";
            }
            return post;
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

        private static JObject Snapshot(
            JObject source = null)
        {
            return new JObject
            {
                ["gender"] = "男",
                ["source"] = (source
                    ?? Source(
                        7,
                        "lease.source.7"))
                    .DeepClone(),
                ["equipment"] = new JObject { ["itemKind"] = "equipment", ["level"] = 7 },
                ["enhance"] = new JObject { ["currentLevel"] = 7, ["maxLevel"] = 13 },
                ["tierCandidates"] = new JArray(),
                ["modCandidates"] = new JArray(),
                ["materials"] = new JArray()
            };
        }

        private static JArray FullBackpackSnapshots()
        {
            var slots = new JArray();
            for (int slot = 0; slot < 50; slot++)
            {
                slots.Add(new JObject
                {
                    ["physicalSlot"] = slot,
                    ["occupied"] = false,
                    ["slotLease"] =
                        "lease.empty." + slot
                });
            }
            return new JArray
            {
                new JObject
                {
                    ["containerId"] = "背包",
                    ["capacity"] = 50,
                    ["accessibleCapacity"] = 50,
                    ["viewCapacity"] = 50,
                    ["filterKey"] = "all",
                    ["pageSizeHint"] = 50,
                    ["locked"] = false,
                    ["snapshotSeq"] = 1,
                    ["containerEpoch"] = 1,
                    ["containerVersion"] = 1,
                    ["offset"] = 0,
                    ["limit"] = 50,
                    ["slots"] = slots,
                    ["filterFacets"] =
                        new JArray(),
                    ["filterItemCount"] = 0,
                    ["setFacets"] =
                        new JArray(),
                    ["setFilterItemCount"] = 0
                }
            };
        }

        private static JObject ParseWire(string value)
        {
            return JObject.Parse(value.TrimEnd('\0'));
        }
    }
}
