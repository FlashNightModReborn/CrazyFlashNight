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
        private sealed class ThreadSafeLogCapture
        {
            private readonly object _gate = new object();
            private readonly List<string> _items =
                new List<string>();

            public void Add(string value)
            {
                lock (_gate) _items.Add(value);
            }

            public void Clear()
            {
                lock (_gate) _items.Clear();
            }

            public List<string> FindAll(
                Predicate<string> match)
            {
                lock (_gate) return _items.FindAll(match);
            }

            public string[] Snapshot()
            {
                lock (_gate) return _items.ToArray();
            }
        }

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

        private sealed class OperationFixture
        {
            public JObject BeforeSourceEquipment;
            public JObject AfterSourceEquipment;
            public JObject BeforeTargetEquipment;
            public JObject AfterTargetEquipment;
            public JArray Materials;
            public JArray RemovedMods;
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
                else Assert.Equal("candidate.one", (string)command["candidateKey"]);

                // replace_mod 与 install_mod 共用顶层“配件”栏目，但 wire 必须同时冻结新旧候选。
                if (operation == "install_mod")
                {
                    task.HandleWebRequest("preview", Request("preview", "tune.preview.replace_mod", "replace_mod"));
                    JObject replacement = sent[1];
                    Assert.Equal("replace_mod", (string)replacement["operation"]);
                    Assert.Equal("candidate.one", (string)replacement["candidateKey"]);
                    Assert.Equal("candidate.old", (string)replacement["replaceCandidateKey"]);
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
                Assert.Equal("candidate.one", (string)sent[0]["candidateKey"]);
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
        public void IdentityTripleCandidatesAndMaterials_ArePreservedAndMalformedLeavesFailClosed()
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            using (var task = NewTask(
                value => { sent.Add(ParseWire(value)); return true; }, web))
            {
                task.HandleWebRequest(
                    "snapshot",
                    Request("snapshot", "tune.identity.valid"));
                JObject valid = SnapshotResponse(Assert.Single(sent));
                valid["snapshot"]["modCandidates"] =
                    IdentityTripleCandidates();
                task.HandleFlashResponse(valid, null);

                JObject accepted = Assert.Single(web);
                Assert.True((bool)accepted["success"]);
                JArray projected = (JArray)accepted["snapshot"]["modCandidates"];
                Assert.Equal(3, projected.Count);
                Assert.Equal("光棱射线弹-强化", (string)projected[0]["itemName"]);
                Assert.Equal("棱镜折射阵列", (string)projected[0]["displayName"]);
                Assert.Equal("全光谱棱镜阵列", (string)projected[0]["icon"]);
                Assert.Equal("光谱射线弹", (string)projected[1]["itemName"]);
                Assert.Equal("色散射线弹", (string)projected[1]["displayName"]);
                Assert.Equal("棱栅射线弹", (string)projected[1]["icon"]);
                Assert.Equal("光谱射线弹-强化", (string)projected[2]["itemName"]);
                Assert.Equal("全谱色散引擎", (string)projected[2]["displayName"]);
                Assert.Equal("环式棱栅折射阵列", (string)projected[2]["icon"]);
                JObject projectedMaterial = (JObject)accepted[
                    "snapshot"]["materials"][0];
                Assert.Equal("强化石", (string)projectedMaterial["itemName"]);
                Assert.Equal(
                    MaterialDisplayName("强化石"),
                    (string)projectedMaterial["displayName"]);
                Assert.Equal(
                    MaterialIcon("强化石"),
                    (string)projectedMaterial["icon"]);
                Assert.NotEqual(
                    (string)projectedMaterial["itemName"],
                    (string)projectedMaterial["displayName"]);
                Assert.NotEqual(
                    (string)projectedMaterial["displayName"],
                    (string)projectedMaterial["icon"]);

                sent.Clear();
                web.Clear();
                string[] malformedCaseIds = {
                    "missing-display-name",
                    "number-display-name",
                    "wrong-icon-type",
                    "object-icon",
                    "legacy-display-alias",
                    "whitespace-display-name",
                    "literal-undefined-icon",
                    "material-missing-display-name",
                    "material-object-display-name",
                    "material-wrong-icon-type",
                    "material-object-icon",
                    "material-legacy-display-alias",
                    "material-whitespace-display-name",
                    "material-literal-undefined-icon"
                };
                for (int index = 0; index < malformedCaseIds.Length; index++)
                {
                    task.HandleWebRequest(
                        "snapshot",
                        Request(
                            "snapshot",
                            "tune.identity." + malformedCaseIds[index]));
                    JObject malformed = SnapshotResponse(
                        sent[sent.Count - 1]);
                    malformed["snapshot"]["modCandidates"] =
                        IdentityTripleCandidates();
                    JObject first = (JObject)malformed[
                        "snapshot"]["modCandidates"][0];
                    JObject firstMaterial = (JObject)malformed[
                        "snapshot"]["materials"][0];
                    string malformedCaseId = malformedCaseIds[index];
                    if (malformedCaseId == "missing-display-name")
                        first.Remove("displayName");
                    else if (malformedCaseId == "number-display-name")
                        first["displayName"] = 73;
                    else if (malformedCaseId == "wrong-icon-type")
                        first["icon"] = 7;
                    else if (malformedCaseId == "object-icon")
                        first["icon"] = new JObject { ["bad"] = true };
                    else if (malformedCaseId == "legacy-display-alias")
                        first["displayname"] = "不得接受的旧字段";
                    else if (malformedCaseId == "whitespace-display-name")
                        first["displayName"] = " \t ";
                    else if (malformedCaseId == "literal-undefined-icon")
                        first["icon"] = " UnDeFiNeD ";
                    else if (malformedCaseId == "material-missing-display-name")
                        firstMaterial.Remove("displayName");
                    else if (malformedCaseId == "material-object-display-name")
                        firstMaterial["displayName"] =
                            new JObject { ["bad"] = true };
                    else if (malformedCaseId == "material-wrong-icon-type")
                        firstMaterial["icon"] = 7;
                    else if (malformedCaseId == "material-object-icon")
                        firstMaterial["icon"] =
                            new JObject { ["bad"] = true };
                    else if (malformedCaseId == "material-legacy-display-alias")
                        firstMaterial["displayname"] = "不得接受的旧字段";
                    else if (malformedCaseId == "material-whitespace-display-name")
                        firstMaterial["displayName"] = " \t ";
                    else firstMaterial["icon"] = " UnDeFiNeD ";

                    task.HandleFlashResponse(malformed, null);
                    JObject rejected = web[web.Count - 1];
                    Assert.False((bool)rejected["success"]);
                    Assert.Equal(
                        "malformed_response",
                        (string)rejected["error"]);
                    Assert.Null(rejected["snapshot"]);
                }

                sent.Clear();
                web.Clear();
                JObject selectorDrift = Request(
                    "preview",
                    "tune.identity.selector-drift",
                    "install_mod");
                selectorDrift["payload"]["candidateKey"] =
                    "mod.identity.0";
                selectorDrift["payload"]["displayName"] =
                    "棱镜折射阵列";
                task.HandleWebRequest("preview", selectorDrift);
                Assert.Empty(sent);
                Assert.Equal(
                    "invalid_payload",
                    (string)Assert.Single(web)["error"]);
            }
        }

        [Theory]
        [InlineData(" \t ")]
        [InlineData(" undefined ")]
        [InlineData(" UnDeFiNeD ")]
        public void TooltipDisplayIdentity_RejectsSentinelText(
            string text)
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
                task.HandleWebRequest(
                    "tooltip",
                    Request(
                        "tooltip",
                        "tune.tooltip.identity." + text.Length));
                JObject response = TooltipResponse(
                    Assert.Single(sent));
                response["text"] = text;

                task.HandleFlashResponse(response, null);

                JObject rejected = Assert.Single(web);
                Assert.False((bool)rejected["success"]);
                Assert.Equal(
                    "malformed_response",
                    (string)rejected["error"]);
            }
        }

        [Theory]
        [InlineData(false)]
        [InlineData(true)]
        public void TooltipAndPreview_ConcurrentResponsesSettleInEitherOrder(
            bool previewFirst)
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            using (var task = NewTask(value => { sent.Add(ParseWire(value)); return true; }, web))
            {
                PrimeSession(task, sent);
                sent.Clear();
                web.Clear();

                task.HandleWebRequest(
                    "tooltip",
                    Request("tooltip", "tune.concurrent.tooltip"));
                task.HandleWebRequest(
                    "preview",
                    Request("preview", "tune.concurrent.preview", "enhance"));

                Assert.Equal(2, sent.Count);
                Assert.Equal(2, task.PendingCount);
                JObject tooltip = sent.Find(
                    value => (string)value["action"] == "equipmentTuningTooltip");
                JObject preview = sent.Find(
                    value => (string)value["action"] == "equipmentTuningPreview");
                Assert.NotNull(tooltip);
                Assert.NotNull(preview);

                if (previewFirst)
                {
                    task.HandleFlashResponse(
                        PreviewResponse(preview, "enhance", "tuning.token.concurrent"),
                        null);
                    task.HandleFlashResponse(TooltipResponse(tooltip), null);
                }
                else
                {
                    task.HandleFlashResponse(TooltipResponse(tooltip), null);
                    task.HandleFlashResponse(
                        PreviewResponse(preview, "enhance", "tuning.token.concurrent"),
                        null);
                }

                Assert.Equal(0, task.PendingCount);
                Assert.Equal(2, web.Count);
                Assert.Contains(
                    web,
                    value => (string)value["callId"] == "tune.concurrent.tooltip"
                        && (bool)value["success"]);
                Assert.Contains(
                    web,
                    value => (string)value["callId"] == "tune.concurrent.preview"
                        && (bool)value["success"]
                        && (string)value["tuningToken"] == "tuning.token.concurrent");
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
        public void FirstSnapshotDisconnected_EchoesRequestedSessionAndLeavesNoPending()
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            using (var task = new EquipmentTuningTask(
                () => false,
                value => { sent.Add(ParseWire(value)); return true; }))
            {
                task.SetPostToWeb(value => web.Add(JObject.Parse(value)));
                Assert.True(task.BindPanelInstance("workbench.instance.1"));
                JObject request = Request(
                    "snapshot",
                    "tune.snapshot.disconnected.first");
                request["payload"]["viewSessionId"] =
                    "tuning.session.requested.first";

                task.HandleWebRequest("snapshot", request);

                Assert.Empty(sent);
                JObject response = Assert.Single(web);
                Assert.Equal("snapshot", (string)response["cmd"]);
                Assert.Equal(
                    "tune.snapshot.disconnected.first",
                    (string)response["callId"]);
                Assert.Equal(
                    "workbench.instance.1",
                    (string)response["panelInstanceId"]);
                Assert.Equal(
                    "tuning.session.requested.first",
                    (string)response["viewSessionId"]);
                Assert.Equal("disconnected", (string)response["error"]);
                Assert.Null(task.ActiveViewSessionId);
                Assert.Equal(0, task.PendingCount);
            }
        }

        [Fact]
        public void PreflightErrors_EchoExactRequestedMuxIdentityAndLeaveNoPending()
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            using (var task = NewTask(value => { sent.Add(ParseWire(value)); return true; }, web))
            {
                JObject malformed = Request(
                    "snapshot",
                    "tune.preflight.invalid.payload");
                malformed["payload"]["viewSessionId"] =
                    "tuning.session.request.invalid";
                malformed["payload"]["unexpected"] = true;
                task.HandleWebRequest("snapshot", malformed);

                JObject stalePanel = Request(
                    "snapshot",
                    "tune.preflight.stale.panel");
                stalePanel["panelInstanceId"] = "workbench.instance.stale";
                stalePanel["payload"]["viewSessionId"] =
                    "tuning.session.request.stale";
                task.HandleWebRequest("snapshot", stalePanel);

                Assert.Empty(sent);
                Assert.Equal(2, web.Count);
                Assert.Equal(
                    "tuning.session.request.invalid",
                    (string)web[0]["viewSessionId"]);
                Assert.Equal(
                    "workbench.instance.1",
                    (string)web[0]["panelInstanceId"]);
                Assert.Equal("invalid_payload", (string)web[0]["error"]);
                Assert.Equal(
                    "tuning.session.request.stale",
                    (string)web[1]["viewSessionId"]);
                Assert.Equal(
                    "workbench.instance.stale",
                    (string)web[1]["panelInstanceId"]);
                Assert.Equal(
                    "panel_instance_expired",
                    (string)web[1]["error"]);
                Assert.Equal(0, task.PendingCount);
            }
        }

        [Fact]
        public void PreviewWithStaleSession_FailsClosedAndEchoesStaleSession()
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            using (var task = NewTask(value => { sent.Add(ParseWire(value)); return true; }, web))
            {
                PrimeSession(task, sent);
                sent.Clear();
                web.Clear();
                JObject stale = Request(
                    "preview",
                    "tune.preview.stale.session",
                    "enhance");
                stale["payload"]["viewSessionId"] =
                    "tuning.session.stale";

                task.HandleWebRequest("preview", stale);

                Assert.Empty(sent);
                JObject response = Assert.Single(web);
                Assert.Equal(
                    "view_session_expired",
                    (string)response["error"]);
                Assert.Equal(
                    "tuning.session.stale",
                    (string)response["viewSessionId"]);
                Assert.Equal(
                    "tuning.session.1",
                    task.ActiveViewSessionId);
                Assert.Equal(0, task.PendingCount);
            }
        }

        [Fact]
        public void PreviewSettledLog_UsesSafeStructuredReceiptFields()
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            var logs = new ThreadSafeLogCapture();
            LogManager.SetSink(value => logs.Add(value));
            try
            {
                using (var task = NewTask(
                    value => { sent.Add(ParseWire(value)); return true; },
                    web))
                {
                    PrimeSession(task, sent);
                    sent.Clear();
                    web.Clear();
                    logs.Clear();
                    JObject request = Request(
                        "preview",
                        "tune.preview.receipt",
                        "install_mod");
                    request["payload"]["candidateKey"] = "candidate.one";
                    task.HandleWebRequest("preview", request);
                    JObject command = Assert.Single(sent);
                    string binding = Assert.Single(logs.FindAll(
                        value => value.StartsWith(
                            "event=authority_flash_call_bound ",
                            StringComparison.Ordinal)));
                    Assert.Equal(
                        "event=authority_flash_call_bound domain=equipment_tuning"
                        + " webCallId=tune.preview.receipt"
                        + " flashCallId=" + (int)command["callId"]
                        + " panel=workbench"
                        + " panelInstanceId=workbench.instance.1"
                        + " cmd=preview action=equipmentTuningPreview"
                        + " viewSessionId=tuning.session.1",
                        binding);

                    task.HandleFlashResponse(
                        PreviewResponse(
                            command,
                            "install_mod",
                            "tuning.token.receipt"),
                        null);

                    string receipt = Assert.Single(logs.FindAll(
                        value => value.StartsWith(
                            "event=equipment_tuning_preview_settled ",
                            StringComparison.Ordinal)));
                    Assert.DoesNotContain("\r", receipt);
                    Assert.DoesNotContain("\n", receipt);
                    Assert.Contains("webCallId=tune.preview.receipt", receipt);
                    Assert.Contains(" requestCallId=tune.preview.receipt", receipt);
                    Assert.Contains(" tokenRef=sha256_", receipt);
                    Assert.Contains(" flashCallId=", receipt);
                    Assert.Contains(" panelInstanceId=workbench.instance.1", receipt);
                    Assert.Contains(" viewSessionId=tuning.session.1", receipt);
                    Assert.Contains(
                        " sourceKeyRef=" + AuthorityLogFormatter.CreateReference(
                            "inventory:背包:7:lease.source.7"),
                        receipt);
                    Assert.Contains(" operation=install_mod", receipt);
                    Assert.Contains(
                        " candidateKey=candidate.one",
                        receipt);
                    Assert.Contains(
                        " intentKeyRef=" + AuthorityLogFormatter.CreateReference(
                            "install_mod|candidate.one|"),
                        receipt);
                    Assert.All(
                        logs.Snapshot(),
                        value => Assert.DoesNotContain("lease.source.7", value));
                    string previewCommandLog = Assert.Single(logs.FindAll(
                        value => value.StartsWith(
                            "[EquipmentTuningTask] -> Flash: ",
                            StringComparison.Ordinal)
                            && value.Contains(
                                "\"action\":\"equipmentTuningPreview\"")));
                    Assert.Contains(
                        "\"expectedLeaseRef\":\""
                            + AuthorityLogFormatter.CreateReference(
                                "lease.source.7") + "\"",
                        previewCommandLog);
                    Assert.Contains(" outcome=success", receipt);
                    Assert.EndsWith(" remainingPending=0", receipt);
                    Assert.Equal(0, task.PendingCount);
                }
            }
            finally
            {
                LogManager.ResetSink();
            }
        }

        [Fact]
        public void SnapshotConfirmedLog_StateReferenceIgnoresLeaseButTracksAuthorityState()
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            var logs = new ThreadSafeLogCapture();
            LogManager.SetSink(value => logs.Add(value));
            try
            {
                using (var task = NewTask(
                    value => { sent.Add(ParseWire(value)); return true; },
                    web))
                {
                    task.HandleWebRequest(
                        "snapshot", Request("snapshot", "tune.snapshot.receipt"));
                    task.HandleFlashResponse(
                        SnapshotResponse(Assert.Single(sent)), null);

                    string receipt = Assert.Single(logs.FindAll(
                        value => value.StartsWith(
                            "event=equipment_tuning_snapshot_confirmed ",
                            StringComparison.Ordinal)));
                    Assert.Equal(
                        AuthorityLogFormatter.CreateReference(
                            "inventory:背包:7:lease.source.7"),
                        ReceiptField(receipt, "sourceKeyRef"));
                    Assert.DoesNotContain("lease.source.7", receipt);
                    string stateRef = Uri.UnescapeDataString(
                        ReceiptField(receipt, "stateRef"));
                    Assert.StartsWith("sha256_", stateRef);
                    Assert.Equal(31, stateRef.Length);

                    sent.Clear();
                    web.Clear();
                    logs.Clear();
                    task.HandleWebRequest(
                        "snapshot",
                        Request(
                            "snapshot",
                            "tune.snapshot.receipt.new-lease",
                            null,
                            Source(7, "lease.source.after-reload")));
                    task.HandleFlashResponse(
                        SnapshotResponse(Assert.Single(sent)), null);
                    string newLeaseReceipt = Assert.Single(logs.FindAll(
                        value => value.StartsWith(
                            "event=equipment_tuning_snapshot_confirmed ",
                            StringComparison.Ordinal)));
                    Assert.Equal(
                        stateRef,
                        Uri.UnescapeDataString(
                            ReceiptField(newLeaseReceipt, "stateRef")));

                    sent.Clear();
                    web.Clear();
                    logs.Clear();
                    task.HandleWebRequest(
                        "snapshot",
                        Request(
                            "snapshot",
                            "tune.snapshot.receipt.changed-state",
                            null,
                            Source(7, "lease.source.changed-state")));
                    JObject changed = SnapshotResponse(Assert.Single(sent));
                    changed["snapshot"]["equipment"]["level"] = 8;
                    changed["snapshot"]["enhance"]["currentLevel"] = 8;
                    task.HandleFlashResponse(changed, null);
                    string changedReceipt = Assert.Single(logs.FindAll(
                        value => value.StartsWith(
                            "event=equipment_tuning_snapshot_confirmed ",
                            StringComparison.Ordinal)));
                    Assert.NotEqual(
                        stateRef,
                        Uri.UnescapeDataString(
                            ReceiptField(changedReceipt, "stateRef")));
                }
            }
            finally
            {
                LogManager.ResetSink();
            }
        }

        [Fact]
        public void CommitSettledLog_LinksExactPreviewIdentityWithoutRawToken()
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            var logs = new ThreadSafeLogCapture();
            LogManager.SetSink(value => logs.Add(value));
            try
            {
                using (var task = NewTask(
                    value => { sent.Add(ParseWire(value)); return true; },
                    web))
                {
                    task.HandleWebRequest(
                        "snapshot",
                        Request("snapshot", "tune.receipt.snapshot"));
                    task.HandleFlashResponse(
                        SnapshotResponse(Assert.Single(sent)), null);
                    sent.Clear();
                    web.Clear();
                    logs.Clear();

                    JObject preview = Request(
                        "preview", "tune.receipt.preview", "install_mod");
                    preview["payload"]["candidateKey"] = "candidate.one";
                    task.HandleWebRequest("preview", preview);
                    JObject previewCommand = Assert.Single(sent);
                    task.HandleFlashResponse(
                        PreviewResponse(
                            previewCommand,
                            "install_mod",
                            "tuning.token.receipt"),
                        null);

                    JObject commit = Request(
                        "commit", "tune.receipt.commit");
                    commit["payload"]["expectedTuningToken"] =
                        "tuning.token.receipt";
                    task.HandleWebRequest("commit", commit);
                    JObject commitCommand = sent[sent.Count - 1];
                    JObject response = CommitResponse(
                        commitCommand,
                        null,
                        false,
                        "install_mod");
                    task.HandleFlashResponse(response, null);

                    string previewReceipt = Assert.Single(logs.FindAll(
                        value => value.StartsWith(
                            "event=equipment_tuning_preview_settled ",
                            StringComparison.Ordinal)));
                    string commitReceipt = Assert.Single(logs.FindAll(
                        value => value.StartsWith(
                            "event=equipment_tuning_commit_settled ",
                            StringComparison.Ordinal)));
                    string tokenRef = ReceiptField(
                        previewReceipt, "tokenRef");
                    Assert.StartsWith("sha256_", tokenRef);
                    Assert.Equal(31, tokenRef.Length);
                    Assert.Equal(
                        tokenRef,
                        ReceiptField(commitReceipt, "tokenRef"));
                    Assert.DoesNotContain(
                        "tuning.token.receipt", previewReceipt);
                    Assert.DoesNotContain(
                        "tuning.token.receipt", commitReceipt);
                    Assert.All(
                        logs.Snapshot(),
                        value => Assert.DoesNotContain(
                            "tuning.token.receipt", value));
                    string commitCommandLog = Assert.Single(logs.FindAll(
                        value => value.StartsWith(
                            "[EquipmentTuningTask] -> Flash: ",
                            StringComparison.Ordinal)
                            && value.Contains("\"action\":\"equipmentTuningCommit\"")));
                    Assert.Contains(
                        "\"expectedTuningTokenRef\":\"" + tokenRef + "\"",
                        commitCommandLog);
                    Assert.DoesNotContain(
                        "\"expectedTuningToken\":", commitCommandLog);
                    Assert.Contains(
                        " previewWebCallId=tune.receipt.preview",
                        commitReceipt);
                    Assert.Equal(
                        ReceiptField(previewReceipt, "panelInstanceId"),
                        ReceiptField(commitReceipt, "panelInstanceId"));
                    Assert.Equal(
                        ReceiptField(previewReceipt, "viewSessionId"),
                        ReceiptField(commitReceipt, "viewSessionId"));
                    Assert.Equal(
                        ReceiptField(previewReceipt, "sourceKeyRef"),
                        ReceiptField(commitReceipt, "sourceKeyRef"));
                    Assert.Equal(
                        ReceiptField(previewReceipt, "operation"),
                        ReceiptField(commitReceipt, "operation"));
                    Assert.Equal(
                        ReceiptField(previewReceipt, "candidateKey"),
                        ReceiptField(commitReceipt, "candidateKey"));
                    Assert.Equal(
                        ReceiptField(previewReceipt, "intentKeyRef"),
                        ReceiptField(commitReceipt, "intentKeyRef"));
                    Assert.Contains(" outcome=success", commitReceipt);
                    Assert.Contains(" writeState=idle", commitReceipt);
                    Assert.Contains(" remainingPending=0", commitReceipt);
                    string stateRef = ReceiptField(
                        commitReceipt, "stateRef");
                    Assert.StartsWith("sha256_", stateRef);
                    Assert.Equal(31, stateRef.Length);
                    Assert.Contains(" snapshotPresent=true", commitReceipt);
                    Assert.EndsWith(
                        " transactionIdPresent=true", commitReceipt);
                    Assert.Equal("idle", task.WriteState);
                }
            }
            finally
            {
                LogManager.ResetSink();
            }
        }

        [Fact]
        public void CommitSettledLog_UnknownOutcomeRequiresReconcile()
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            var logs = new ThreadSafeLogCapture();
            LogManager.SetSink(value => logs.Add(value));
            try
            {
                using (var task = NewTask(
                    value => { sent.Add(ParseWire(value)); return true; },
                    web))
                {
                    PrimeSession(task, sent);
                    sent.Clear();
                    web.Clear();
                    logs.Clear();
                    task.HandleWebRequest(
                        "commit", Request("commit", "tune.receipt.malformed"));
                    JObject malformed = CommitResponse(Assert.Single(sent));
                    malformed.Remove("snapshot");
                    task.HandleFlashResponse(malformed, null);

                    JObject terminal = Assert.Single(web);
                    Assert.Equal("malformed_response", (string)terminal["error"]);
                    Assert.True((bool)terminal["requiresReconcile"]);
                    Assert.Equal("needs_reconcile", task.WriteState);
                    string receipt = Assert.Single(logs.FindAll(
                        value => value.StartsWith(
                            "event=equipment_tuning_commit_settled ",
                            StringComparison.Ordinal)));
                    Assert.Contains(" outcome=malformed_response", receipt);
                    Assert.Contains(" writeState=needs_reconcile", receipt);
                    Assert.Contains(" stateRef=-", receipt);
                    Assert.Contains(" snapshotPresent=false", receipt);
                    Assert.EndsWith(" transactionIdPresent=false", receipt);
                }
            }
            finally
            {
                LogManager.ResetSink();
            }
        }

        [Fact]
        public void CommitSettledLog_NotSentRestoresBindingAndRemainsIdle()
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            var logs = new ThreadSafeLogCapture();
            bool sendEnabled = true;
            LogManager.SetSink(value => logs.Add(value));
            try
            {
                using (var task = NewTask(
                    value =>
                    {
                        sent.Add(ParseWire(value));
                        return sendEnabled;
                    },
                    web))
                {
                    PrimeSession(task, sent);
                    sent.Clear();
                    web.Clear();
                    logs.Clear();
                    sendEnabled = false;

                    task.HandleWebRequest(
                        "commit", Request("commit", "tune.receipt.not-sent"));

                    JObject terminal = Assert.Single(web);
                    Assert.Equal("not_sent", (string)terminal["error"]);
                    Assert.Equal("idle", task.WriteState);
                    Assert.Equal(1, task.PreviewBindingCount);
                    string receipt = Assert.Single(logs.FindAll(
                        value => value.StartsWith(
                            "event=equipment_tuning_commit_settled ",
                            StringComparison.Ordinal)));
                    Assert.Contains(" outcome=not_sent", receipt);
                    Assert.Contains(" writeState=idle", receipt);
                    Assert.Contains(" stateRef=-", receipt);
                    Assert.EndsWith(" transactionIdPresent=false", receipt);
                }
            }
            finally
            {
                LogManager.ResetSink();
            }
        }

        [Fact]
        public void CommitSettledLog_TimeoutRequiresReconcile()
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            var logs = new ThreadSafeLogCapture();
            LogManager.SetSink(value => logs.Add(value));
            try
            {
                using (var task = NewTask(
                    value => { sent.Add(ParseWire(value)); return true; },
                    web,
                    25))
                {
                    PrimeSession(task, sent);
                    sent.Clear();
                    web.Clear();
                    logs.Clear();
                    task.HandleWebRequest(
                        "commit", Request("commit", "tune.receipt.timeout"));

                    Assert.True(SpinWait.SpinUntil(
                        () => web.Count == 1, 2000));
                    Assert.Equal("timeout", (string)web[0]["error"]);
                    Assert.True((bool)web[0]["requiresReconcile"]);
                    Assert.Equal("needs_reconcile", task.WriteState);
                    string receipt = Assert.Single(logs.FindAll(
                        value => value.StartsWith(
                            "event=equipment_tuning_commit_settled ",
                            StringComparison.Ordinal)));
                    Assert.Contains(" outcome=timeout", receipt);
                    Assert.Contains(" writeState=needs_reconcile", receipt);
                    Assert.Contains(" stateRef=-", receipt);
                    Assert.EndsWith(" transactionIdPresent=false", receipt);
                }
            }
            finally
            {
                LogManager.ResetSink();
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
                            "invalid.lease"
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
                    "snapshot",
                    Request(
                        "snapshot",
                        "tune.loadout.valid.snapshot",
                        null,
                        source));
                task.HandleFlashResponse(
                    SnapshotResponse(Assert.Single(sent)),
                    null);
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
                    (string)web[2]["error"]);
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
                        "tune.convert.invalid.target",
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
        public void LoadoutCommit_RequiresExactPlusOneAndRejectsForgedNoOp()
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
                Assert.False(
                    (bool)web["success"]);
                Assert.Equal(
                    "malformed_response",
                    (string)web["error"]);
                Assert.Equal(
                    "needs_reconcile",
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
        public void SuccessfulPreviewB_SupersedesAAtHostAndOnlyBMayCommit()
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            using (var task = NewTask(
                value => { sent.Add(ParseWire(value)); return true; },
                web))
            {
                PrimeSession(task, sent, null, "tuning.token.a");
                Assert.Equal(1, task.PreviewBindingCount);
                sent.Clear();
                web.Clear();

                task.HandleWebRequest(
                    "preview",
                    Request("preview", "tune.preview.b", "enhance"));
                JObject previewBCommand = Assert.Single(sent);
                Assert.Equal(0, task.PreviewBindingCount);
                task.HandleFlashResponse(
                    PreviewResponse(
                        previewBCommand,
                        "enhance",
                        "tuning.token.b"),
                    null);
                Assert.Equal(1, task.PreviewBindingCount);

                int sentBeforeCommit = sent.Count;
                JObject commitA = Request("commit", "tune.commit.a.superseded");
                commitA["payload"]["expectedTuningToken"] = "tuning.token.a";
                task.HandleWebRequest("commit", commitA);
                Assert.Equal(sentBeforeCommit, sent.Count);
                Assert.Equal(
                    "invalid_payload",
                    (string)web[web.Count - 1]["error"]);
                Assert.Equal(1, task.PreviewBindingCount);

                JObject commitB = Request("commit", "tune.commit.b.current");
                commitB["payload"]["expectedTuningToken"] = "tuning.token.b";
                task.HandleWebRequest("commit", commitB);
                Assert.Equal(sentBeforeCommit + 1, sent.Count);
                Assert.Equal(0, task.PreviewBindingCount);
                task.HandleFlashResponse(
                    CommitResponse(sent[sent.Count - 1]),
                    null);
                Assert.True((bool)web[web.Count - 1]["success"]);
                Assert.Equal("idle", task.WriteState);
            }
        }

        [Fact]
        public void SameOwnerMalformedPreviewAttempt_RevokesPriorBindingBeforePayloadValidation()
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            using (var task = NewTask(
                value => { sent.Add(ParseWire(value)); return true; },
                web))
            {
                PrimeSession(task, sent, null, "tuning.token.a");
                sent.Clear();
                web.Clear();

                JObject malformed = Request(
                    "preview", "tune.preview.malformed", "enhance");
                ((JObject)malformed["payload"]).Remove("targetLevel");
                task.HandleWebRequest("preview", malformed);

                Assert.Empty(sent);
                Assert.Equal(
                    "invalid_payload",
                    (string)Assert.Single(web)["error"]);
                Assert.Equal(0, task.PreviewBindingCount);

                task.HandleWebRequest(
                    "commit",
                    Request("commit", "tune.commit.after-malformed"));
                Assert.Empty(sent);
                Assert.Equal(
                    "invalid_payload",
                    (string)web[web.Count - 1]["error"]);
            }
        }

        [Fact]
        public void ForeignOwnerPreviewAttempts_DoNotRevokeCurrentBinding()
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            using (var task = NewTask(
                value => { sent.Add(ParseWire(value)); return true; },
                web))
            {
                PrimeSession(task, sent, null, "tuning.token.a");
                sent.Clear();
                web.Clear();

                JObject wrongPanel = Request(
                    "preview", "tune.preview.foreign-panel", "enhance");
                wrongPanel["panelInstanceId"] = "workbench.instance.foreign";
                task.HandleWebRequest("preview", wrongPanel);
                JObject wrongSession = Request(
                    "preview", "tune.preview.foreign-session", "enhance");
                wrongSession["payload"]["viewSessionId"] = "tuning.session.foreign";
                task.HandleWebRequest("preview", wrongSession);

                Assert.Empty(sent);
                Assert.Equal(2, web.Count);
                Assert.Equal("panel_instance_expired", (string)web[0]["error"]);
                Assert.Equal("view_session_expired", (string)web[1]["error"]);
                Assert.Equal(1, task.PreviewBindingCount);

                JObject commit = Request(
                    "commit", "tune.commit.after-foreign");
                commit["payload"]["expectedTuningToken"] =
                    "tuning.token.a";
                task.HandleWebRequest(
                    "commit",
                    commit);
                Assert.Single(sent);
                Assert.Equal(0, task.PreviewBindingCount);
            }
        }

        [Fact]
        public void FailedOrMalformedPreviewResponse_DoesNotRestorePriorBinding()
        {
            foreach (bool malformed in new[] { false, true })
            {
                var sent = new List<JObject>();
                var web = new List<JObject>();
                using (var task = NewTask(
                    value => { sent.Add(ParseWire(value)); return true; },
                    web))
                {
                    PrimeSession(task, sent, null, "tuning.token.a");
                    sent.Clear();
                    web.Clear();

                    task.HandleWebRequest(
                        "preview",
                        Request(
                            "preview",
                            malformed
                                ? "tune.preview.malformed-response"
                                : "tune.preview.failure",
                            "enhance"));
                    JObject previewCommand = Assert.Single(sent);
                    JObject response;
                    if (malformed)
                    {
                        response = PreviewResponse(
                            previewCommand,
                            "enhance",
                            "tuning.token.untrusted");
                        response.Remove("materials");
                    }
                    else
                    {
                        response = CommonResponse(
                            previewCommand,
                            "preview",
                            false);
                        response["error"] = "invalid_target";
                    }
                    task.HandleFlashResponse(response, null);

                    Assert.Equal(0, task.PreviewBindingCount);
                    int sentBeforeCommit = sent.Count;
                    task.HandleWebRequest(
                        "commit",
                        Request(
                            "commit",
                            malformed
                                ? "tune.commit.after-malformed-response"
                                : "tune.commit.after-preview-failure"));
                    Assert.Equal(sentBeforeCommit, sent.Count);
                    Assert.Equal(
                        "invalid_payload",
                        (string)web[web.Count - 1]["error"]);
                }
            }
        }

        [Fact]
        public void PreviewTimeout_DoesNotRestorePriorBinding()
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            using (var task = NewTask(
                value => { sent.Add(ParseWire(value)); return true; },
                web,
                25))
            {
                PrimeSession(task, sent, null, "tuning.token.a");
                sent.Clear();
                web.Clear();

                task.HandleWebRequest(
                    "preview",
                    Request("preview", "tune.preview.timeout", "enhance"));
                Assert.Single(sent);
                Assert.True(SpinWait.SpinUntil(() => web.Count == 1, 2000));
                Assert.Equal("timeout", (string)web[0]["error"]);
                Assert.Equal(0, task.PreviewBindingCount);

                int sentBeforeCommit = sent.Count;
                task.HandleWebRequest(
                    "commit",
                    Request("commit", "tune.commit.after-preview-timeout"));
                Assert.Equal(sentBeforeCommit, sent.Count);
                Assert.Equal(
                    "invalid_payload",
                    (string)web[web.Count - 1]["error"]);
            }
        }

        [Fact]
        public void PreviewSendFailure_DoesNotRestorePriorBinding()
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            bool failSend = false;
            using (var task = NewTask(
                value =>
                {
                    sent.Add(ParseWire(value));
                    return !failSend;
                },
                web))
            {
                PrimeSession(task, sent, null, "tuning.token.a");
                sent.Clear();
                web.Clear();
                failSend = true;

                task.HandleWebRequest(
                    "preview",
                    Request("preview", "tune.preview.not-sent", "enhance"));
                Assert.Single(sent);
                Assert.Equal("disconnected", (string)Assert.Single(web)["error"]);
                Assert.Equal(0, task.PreviewBindingCount);

                failSend = false;
                int sentBeforeCommit = sent.Count;
                task.HandleWebRequest(
                    "commit",
                    Request("commit", "tune.commit.after-preview-not-sent"));
                Assert.Equal(sentBeforeCommit, sent.Count);
                Assert.Equal(
                    "invalid_payload",
                    (string)web[web.Count - 1]["error"]);
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

        [Theory]
        [InlineData("before_rule_key")]
        [InlineData("before_display_name")]
        [InlineData("after_rule_key_coherent")]
        [InlineData("after_display_name_coherent")]
        [InlineData("after_icon_coherent")]
        [InlineData("after_level_coherent")]
        [InlineData("after_mods_coherent")]
        [InlineData("after_max_level")]
        [InlineData("material_totals_coherent")]
        [InlineData("material_identity_coherent")]
        [InlineData("material_snapshot_count")]
        [InlineData("material_snapshot_missing")]
        [InlineData("snapshot_equipment")]
        [InlineData("backpack_equipment")]
        [InlineData("post_source_snapshot")]
        [InlineData("post_source_backpack")]
        [InlineData("last_update_not_advanced")]
        [InlineData("removed_mods")]
        [InlineData("can_commit")]
        public void CommitSuccess_RejectsForgedFrozenOrPostStateFields(
            string mutation)
        {
            using (var harness = new CommitHarness(
                Source(7, "lease.source.7")))
            {
                JObject response = CommitResponse(
                    harness.Command);
                MutateForgedCommit(response, mutation);

                harness.Task.HandleFlashResponse(
                    response, null);

                JObject web = Assert.Single(
                    harness.Web);
                Assert.False((bool)web["success"]);
                Assert.Equal(
                    "malformed_response",
                    (string)web["error"]);
                Assert.True(
                    (bool)web["requiresReconcile"]);
                Assert.Equal(
                    "needs_reconcile",
                    harness.Task.WriteState);
            }
        }

        [Theory]
        [InlineData("missing_display_name")]
        [InlineData("missing_icon")]
        [InlineData("whitespace_display_name")]
        [InlineData("literal_undefined_icon")]
        [InlineData("identity_drift")]
        [InlineData("level_drift")]
        [InlineData("mods_drift")]
        [InlineData("material_arithmetic")]
        [InlineData("material_rule")]
        [InlineData("material_snapshot_before")]
        [InlineData("material_snapshot_identity")]
        [InlineData("material_missing_display_name")]
        [InlineData("material_wrong_icon_type")]
        [InlineData("material_legacy_alias")]
        [InlineData("material_whitespace_display_name")]
        [InlineData("material_literal_undefined_icon")]
        [InlineData("can_commit_false")]
        public void PreviewSuccess_RejectsNonCanonicalOrForgedPlan(
            string mutation)
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
                        "tune.forged.preview.snapshot." + mutation));
                task.HandleFlashResponse(
                    SnapshotResponse(Assert.Single(sent)),
                    null);
                sent.Clear();
                web.Clear();

                task.HandleWebRequest(
                    "preview",
                    Request(
                        "preview",
                        "tune.forged.preview." + mutation,
                        "enhance"));
                JObject response = PreviewResponse(
                    Assert.Single(sent),
                    "enhance");
                MutateForgedPreview(response, mutation);

                task.HandleFlashResponse(
                    response, null);

                Assert.Equal(
                    "malformed_response",
                    (string)Assert.Single(web)["error"]);
                Assert.Equal(0, task.PreviewBindingCount);
                Assert.Equal("idle", task.WriteState);
            }
        }

        [Theory]
        [InlineData("install_tier")]
        [InlineData("install_mod")]
        [InlineData("replace_mod")]
        public void PreviewSelectorAuthority_RejectsCoherentPlanForDifferentSnapshotCandidate(
            string operation)
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
                        "tune.selector.snapshot." + operation));
                JObject snapshotResponse = OperationSnapshotResponse(
                    Assert.Single(sent),
                    operation,
                    false);
                JObject snapshot = (JObject)snapshotResponse["snapshot"];
                if (operation == "install_tier")
                {
                    ((JArray)snapshot["tierCandidates"]).Add(
                        TierCandidate(
                            "candidate.two",
                            "测试进阶材料B",
                            "二阶",
                            7,
                            true));
                    ((JArray)snapshot["materials"]).Add(
                        SnapshotMaterialRow(
                            "测试进阶材料B",
                            7));
                }
                else
                {
                    ((JArray)snapshot["modCandidates"]).Add(
                        ModCandidate(
                            "candidate.two",
                            "测试插件B",
                            7,
                            false,
                            operation == "install_mod",
                            operation == "replace_mod"
                                ? new JArray("candidate.old")
                                : new JArray()));
                    ((JArray)snapshot["materials"]).Add(
                        SnapshotMaterialRow(
                            "测试插件B",
                            7));
                }
                task.HandleFlashResponse(snapshotResponse, null);
                Assert.True((bool)Assert.Single(web)["success"]);
                sent.Clear();
                web.Clear();

                task.HandleWebRequest(
                    "preview",
                    Request(
                        "preview",
                        "tune.selector.preview." + operation,
                        operation));
                JObject response = OperationPreviewResponse(
                    Assert.Single(sent),
                    operation,
                    false);
                if (operation == "install_tier")
                {
                    response["after"]["source"]["equipment"]["tier"] =
                        "二阶";
                    response["materials"] = new JArray(
                        MaterialRow(
                            "测试进阶材料B",
                            7,
                            -1,
                            6));
                }
                else
                {
                    response["after"]["source"]["equipment"]["mods"] =
                        new JArray("测试插件B");
                    response["materials"] = operation == "replace_mod"
                        ? new JArray(
                            MaterialRow("旧插件", 0, 1, 1),
                            MaterialRow("测试插件B", 7, -1, 6))
                        : new JArray(
                            MaterialRow("测试插件B", 7, -1, 6));
                }

                task.HandleFlashResponse(response, null);

                JObject rejected = Assert.Single(web);
                Assert.False((bool)rejected["success"]);
                Assert.Equal(
                    "malformed_response",
                    (string)rejected["error"]);
                Assert.Equal(0, task.PreviewBindingCount);
            }
        }

        [Fact]
        public void ReplaceSelectorAuthority_RejectsCoherentPlanForDifferentInstalledCandidate()
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
                        "tune.replace-selector.snapshot"));
                JObject snapshotResponse = OperationSnapshotResponse(
                    Assert.Single(sent),
                    "replace_mod",
                    false);
                JObject snapshot = (JObject)snapshotResponse["snapshot"];
                ((JArray)snapshot["equipment"]["mods"]).Add("依赖插件");
                ((JArray)snapshot["modCandidates"]).Add(
                    ModCandidate(
                        "candidate.dependency",
                        "依赖插件",
                        0,
                        true,
                        false,
                        new JArray()));
                ((JArray)snapshot["modCandidates"])[1]["replaceableFrom"] =
                    new JArray(
                        "candidate.old",
                        "candidate.dependency");
                ((JArray)snapshot["materials"]).Add(
                    SnapshotMaterialRow(
                        "依赖插件",
                        0));
                task.HandleFlashResponse(snapshotResponse, null);
                Assert.True((bool)Assert.Single(web)["success"]);
                sent.Clear();
                web.Clear();

                task.HandleWebRequest(
                    "preview",
                    Request(
                        "preview",
                        "tune.replace-selector.preview",
                        "replace_mod"));
                JObject response = OperationPreviewResponse(
                    Assert.Single(sent),
                    "replace_mod",
                    false);
                response["before"]["source"]["equipment"]["mods"] =
                    new JArray("旧插件", "依赖插件");
                response["after"]["source"]["equipment"]["mods"] =
                    new JArray("旧插件", "测试插件A");
                response["removedMods"] =
                    new JArray("依赖插件");
                response["materials"] = new JArray(
                    MaterialRow("依赖插件", 0, 1, 1),
                    MaterialRow("测试插件A", 5, -1, 4));

                task.HandleFlashResponse(response, null);

                JObject rejected = Assert.Single(web);
                Assert.False((bool)rejected["success"]);
                Assert.Equal(
                    "malformed_response",
                    (string)rejected["error"]);
                Assert.Equal(0, task.PreviewBindingCount);
            }
        }

        [Fact]
        public void ReplaceSelectorAuthority_AcceptsSlotFullCandidateAuthorizedByReplaceableFrom()
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
                        "tune.replace-slot-full.snapshot"));
                JObject snapshotResponse = OperationSnapshotResponse(
                    Assert.Single(sent),
                    "replace_mod",
                    false);
                JObject replacement = null;
                foreach (JToken token in (JArray)snapshotResponse[
                    "snapshot"]["modCandidates"])
                {
                    JObject candidate = token as JObject;
                    if ((string)(candidate != null
                            ? candidate["candidateKey"] : null)
                            == "candidate.one")
                    {
                        replacement = candidate;
                        break;
                    }
                }
                Assert.NotNull(replacement);
                Assert.False((bool)replacement["available"]);
                JArray replaceableFrom =
                    (JArray)replacement["replaceableFrom"];
                Assert.Single(replaceableFrom);
                Assert.Equal(
                    "candidate.old",
                    (string)replaceableFrom[0]);
                task.HandleFlashResponse(snapshotResponse, null);
                Assert.True((bool)Assert.Single(web)["success"]);
                sent.Clear();
                web.Clear();

                task.HandleWebRequest(
                    "preview",
                    Request(
                        "preview",
                        "tune.replace-slot-full.preview",
                        "replace_mod"));
                task.HandleFlashResponse(
                    OperationPreviewResponse(
                        Assert.Single(sent),
                        "replace_mod",
                        false),
                    null);

                JObject accepted = Assert.Single(web);
                Assert.True((bool)accepted["success"]);
                Assert.Equal(1, task.PreviewBindingCount);
            }
        }

        [Theory]
        [InlineData("before")]
        [InlineData("identity")]
        public void PreviewMaterialAuthority_RejectsCoherentDetachAllPlanOutsideAcceptedSnapshot(
            string mutation)
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
                        "tune.detach-all-material.snapshot." + mutation));
                task.HandleFlashResponse(
                    OperationSnapshotResponse(
                        Assert.Single(sent),
                        "detach_all_mods",
                        false),
                    null);
                Assert.True((bool)Assert.Single(web)["success"]);
                sent.Clear();
                web.Clear();

                task.HandleWebRequest(
                    "preview",
                    Request(
                        "preview",
                        "tune.detach-all-material.preview." + mutation,
                        "detach_all_mods"));
                JObject response = OperationPreviewResponse(
                    Assert.Single(sent),
                    "detach_all_mods",
                    false);
                JObject material =
                    (JObject)response["materials"][0];
                if (mutation == "before")
                {
                    material["before"] =
                        material.Value<int>("before") + 1;
                    material["after"] =
                        material.Value<int>("after") + 1;
                }
                else
                {
                    material["displayName"] =
                        "伪造批量卸下材料展示名";
                    material["icon"] =
                        "伪造批量卸下材料图标";
                }

                task.HandleFlashResponse(response, null);

                JObject rejected = Assert.Single(web);
                Assert.False((bool)rejected["success"]);
                Assert.Equal(
                    "malformed_response",
                    (string)rejected["error"]);
                Assert.Equal(0, task.PreviewBindingCount);
            }
        }

        [Fact]
        public void PreviewSelectorAuthority_UsesLatestAcceptedSnapshotMap()
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
                        "tune.selector.latest.first"));
                task.HandleFlashResponse(
                    OperationSnapshotResponse(
                        Assert.Single(sent),
                        "install_mod",
                        false),
                    null);
                sent.Clear();

                task.HandleWebRequest(
                    "snapshot",
                    Request(
                        "snapshot",
                        "tune.selector.latest.second"));
                JObject latest = OperationSnapshotResponse(
                    Assert.Single(sent),
                    "install_mod",
                    false);
                ((JArray)latest["snapshot"]["modCandidates"])[0][
                    "candidateKey"] = "candidate.two";
                task.HandleFlashResponse(latest, null);
                sent.Clear();
                web.Clear();

                task.HandleWebRequest(
                    "preview",
                    Request(
                        "preview",
                        "tune.selector.latest.old",
                        "install_mod"));
                Assert.Empty(sent);
                Assert.Equal(
                    "invalid_payload",
                    (string)Assert.Single(web)["error"]);

                web.Clear();
                JObject current = Request(
                    "preview",
                    "tune.selector.latest.current",
                    "install_mod");
                current["payload"]["candidateKey"] =
                    "candidate.two";
                task.HandleWebRequest(
                    "preview",
                    current);
                Assert.Single(sent);
                Assert.Empty(web);
            }
        }

        [Theory]
        [InlineData("enhance", false)]
        [InlineData("convert", false)]
        [InlineData("convert", true)]
        [InlineData("install_tier", false)]
        [InlineData("install_mod", false)]
        [InlineData("replace_mod", false)]
        [InlineData("detach_mod", false)]
        [InlineData("detach_all_mods", false)]
        public void ProductionOperationFixture_PreviewCommitAndPostStateAreAccepted(
            string operation,
            bool noOp)
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
                        "tune.operation.snapshot."
                            + operation + "." + noOp));
                JObject snapshotCommand = Assert.Single(sent);
                task.HandleFlashResponse(
                    OperationSnapshotResponse(
                        snapshotCommand,
                        operation,
                        noOp),
                    null);
                Assert.True((bool)Assert.Single(web)["success"]);
                sent.Clear();
                web.Clear();

                task.HandleWebRequest(
                    "preview",
                    Request(
                        "preview",
                        "tune.operation.preview."
                            + operation + "." + noOp,
                        operation));
                JObject previewCommand = Assert.Single(sent);
                task.HandleFlashResponse(
                    OperationPreviewResponse(
                        previewCommand,
                        operation,
                        noOp),
                    null);
                JObject preview = Assert.Single(web);
                Assert.True((bool)preview["success"]);
                Assert.Equal(noOp, (bool)preview["noOp"]);
                Assert.Equal(1, task.PreviewBindingCount);
                sent.Clear();
                web.Clear();

                task.HandleWebRequest(
                    "commit",
                    Request(
                        "commit",
                        "tune.operation.commit."
                            + operation + "." + noOp));
                JObject commitCommand = Assert.Single(sent);
                task.HandleFlashResponse(
                    OperationCommitResponse(
                        commitCommand,
                        operation,
                        noOp),
                    null);

                JObject committed = Assert.Single(web);
                Assert.True((bool)committed["success"]);
                Assert.Equal(operation, (string)committed["operation"]);
                Assert.Equal(noOp, (bool)committed["noOp"]);
                Assert.Equal("idle", task.WriteState);
                Assert.Equal(0, task.PreviewBindingCount);
                Assert.True(JToken.DeepEquals(
                    committed["after"]["source"]["equipment"],
                    committed["snapshot"]["equipment"]));
            }
        }

        [Theory]
        [InlineData("enhance")]
        [InlineData("convert")]
        [InlineData("install_tier")]
        [InlineData("install_mod")]
        [InlineData("replace_mod")]
        [InlineData("detach_mod")]
        [InlineData("detach_all_mods")]
        public void ProductionOperationFixture_RejectsCoherentForgeryAgainstPreview(
            string operation)
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
                        "tune.operation.forged.snapshot." + operation));
                task.HandleFlashResponse(
                    OperationSnapshotResponse(
                        Assert.Single(sent),
                        operation,
                        false),
                    null);
                sent.Clear();
                web.Clear();

                task.HandleWebRequest(
                    "preview",
                    Request(
                        "preview",
                        "tune.operation.forged.preview." + operation,
                        operation));
                task.HandleFlashResponse(
                    OperationPreviewResponse(
                        Assert.Single(sent),
                        operation,
                        false),
                    null);
                Assert.True((bool)Assert.Single(web)["success"]);
                sent.Clear();
                web.Clear();

                task.HandleWebRequest(
                    "commit",
                    Request(
                        "commit",
                        "tune.operation.forged.commit." + operation));
                JObject response = OperationCommitResponse(
                    Assert.Single(sent),
                    operation,
                    false);
                MutateCoherentOperationForgery(response, operation);

                task.HandleFlashResponse(response, null);

                JObject rejected = Assert.Single(web);
                Assert.False((bool)rejected["success"]);
                Assert.Equal(
                    "malformed_response",
                    (string)rejected["error"]);
                Assert.True((bool)rejected["requiresReconcile"]);
                Assert.Equal("needs_reconcile", task.WriteState);
                Assert.Equal(0, task.PreviewBindingCount);
            }
        }

        private static void MutateCoherentOperationForgery(
            JObject response,
            string operation)
        {
            JObject afterEquipment =
                (JObject)response["after"]["source"]["equipment"];
            JArray materials = (JArray)response["materials"];
            switch (operation)
            {
                case "enhance":
                    materials[0]["delta"] = -4;
                    materials[0]["after"] = 96;
                    break;
                case "convert":
                    afterEquipment["displayName"] =
                        "伪造转换后显示名";
                    break;
                case "install_tier":
                    afterEquipment["tier"] = "二阶";
                    break;
                case "install_mod":
                    afterEquipment["mods"] =
                        new JArray("测试插件B");
                    materials[0]["itemName"] = "测试插件B";
                    break;
                case "replace_mod":
                    afterEquipment["mods"] =
                        new JArray("测试插件B");
                    materials[1]["itemName"] = "测试插件B";
                    break;
                case "detach_mod":
                    materials[0]["before"] = 8;
                    materials[0]["after"] = 9;
                    break;
                case "detach_all_mods":
                    materials[0]["before"] = 8;
                    materials[0]["after"] = 9;
                    materials[1]["before"] = 3;
                    materials[1]["after"] = 4;
                    break;
                default:
                    throw new InvalidOperationException(operation);
            }

            SynchronizeCommittedSourceSurfaces(response);
            response["snapshot"]["materials"] =
                SnapshotMaterialCounts(materials, true);
        }

        private static void SynchronizeCommittedSourceSurfaces(
            JObject response)
        {
            JObject afterSubject =
                (JObject)response["after"]["source"];
            JObject source = (JObject)afterSubject["source"];
            JObject equipment =
                (JObject)afterSubject["equipment"];
            JObject snapshot = (JObject)response["snapshot"];
            snapshot["equipment"] = equipment.DeepClone();
            snapshot["enhance"]["currentLevel"] =
                equipment["level"].DeepClone();
            snapshot["enhance"]["maxLevel"] =
                equipment["maxLevel"].DeepClone();
            snapshot["enhance"]["availableMaxLevel"] =
                equipment["maxLevel"].DeepClone();
            snapshot["enhance"]["hardMaxLevel"] =
                equipment["hardMaxLevel"].DeepClone();
            var candidates = new JArray();
            JArray mods = (JArray)equipment["mods"];
            for (int index = 0; index < mods.Count; index++)
            {
                candidates.Add(InstalledModCandidate(
                    (string)mods[index],
                    index));
            }
            snapshot["modCandidates"] = candidates;

            JObject backpack =
                (JObject)response["inventorySnapshots"][0];
            int slot = source.Value<int>("slot");
            backpack["slots"][slot] =
                OccupiedBackpackSlot(source, equipment);
        }

        private static void MutateForgedPreview(
            JObject response,
            string mutation)
        {
            JObject before =
                (JObject)response["before"]["source"]["equipment"];
            JObject after =
                (JObject)response["after"]["source"]["equipment"];
            JObject material =
                (JObject)response["materials"][0];
            switch (mutation)
            {
                case "missing_display_name":
                    after.Remove("displayName");
                    break;
                case "missing_icon":
                    after.Remove("icon");
                    break;
                case "whitespace_display_name":
                    after["displayName"] = " \t ";
                    break;
                case "literal_undefined_icon":
                    after["icon"] = " undefined ";
                    break;
                case "identity_drift":
                    after["name"] = "伪造规则键";
                    break;
                case "level_drift":
                    after["level"] = 9;
                    break;
                case "mods_drift":
                    after["mods"] = new JArray("伪造插件");
                    break;
                case "material_arithmetic":
                    material["after"] = 98;
                    break;
                case "material_rule":
                    material["itemName"] = "伪造强化材料";
                    break;
                case "material_snapshot_before":
                    material["before"] = material.Value<int>("before") + 1;
                    material["after"] = material.Value<int>("after") + 1;
                    break;
                case "material_snapshot_identity":
                    material["displayName"] = "伪造强化材料展示名";
                    material["icon"] = "伪造强化材料图标";
                    break;
                case "material_missing_display_name":
                    material.Remove("displayName");
                    break;
                case "material_wrong_icon_type":
                    material["icon"] = 7;
                    break;
                case "material_legacy_alias":
                    material["displayname"] = "旧字段";
                    break;
                case "material_whitespace_display_name":
                    material["displayName"] = " \t ";
                    break;
                case "material_literal_undefined_icon":
                    material["icon"] = " UnDeFiNeD ";
                    break;
                case "can_commit_false":
                    response["canCommit"] = false;
                    break;
                default:
                    throw new InvalidOperationException(mutation);
            }
            Assert.NotNull(before);
        }

        private static void MutateForgedCommit(
            JObject response,
            string mutation)
        {
            JObject before =
                (JObject)response["before"]["source"]["equipment"];
            JObject after =
                (JObject)response["after"]["source"]["equipment"];
            JObject snapshot =
                (JObject)response["snapshot"];
            JObject snapshotEquipment =
                (JObject)snapshot["equipment"];
            JObject backpack =
                (JObject)response["inventorySnapshots"][0];
            JObject slot =
                (JObject)backpack["slots"][7];
            JObject item = (JObject)slot["item"];
            JObject confirm =
                (JObject)slot["confirmProjection"];
            switch (mutation)
            {
                case "before_rule_key":
                    before["name"] = "伪造提交前规则键";
                    break;
                case "before_display_name":
                    before["displayName"] = "伪造提交前显示名";
                    break;
                case "after_rule_key_coherent":
                    after["name"] = "伪造提交后规则键";
                    snapshotEquipment["name"] = after["name"].DeepClone();
                    item["name"] = after["name"].DeepClone();
                    confirm["name"] = after["name"].DeepClone();
                    break;
                case "after_display_name_coherent":
                    after["displayName"] = "伪造提交后显示名";
                    snapshotEquipment["displayName"] =
                        after["displayName"].DeepClone();
                    item["displayName"] =
                        after["displayName"].DeepClone();
                    confirm["displayName"] =
                        after["displayName"].DeepClone();
                    break;
                case "after_icon_coherent":
                    after["icon"] = "伪造提交后图标";
                    snapshotEquipment["icon"] =
                        after["icon"].DeepClone();
                    item["icon"] = after["icon"].DeepClone();
                    break;
                case "after_level_coherent":
                    after["level"] = 9;
                    snapshotEquipment["level"] = 9;
                    snapshot["enhance"]["currentLevel"] = 9;
                    item["enhancementLevel"] = 9;
                    confirm["enhancementLevel"] = 9;
                    break;
                case "after_mods_coherent":
                    after["mods"] = new JArray("伪造插件");
                    snapshotEquipment["mods"] =
                        after["mods"].DeepClone();
                    ((JArray)snapshot["modCandidates"]).Add(
                        InstalledModCandidate("伪造插件"));
                    item["modSlotUsed"] = 1;
                    confirm["modSignature"] = "4:伪造插件;";
                    break;
                case "after_max_level":
                    after["maxLevel"] = 12;
                    break;
                case "material_totals_coherent":
                    response["materials"][0]["before"] = 101;
                    response["materials"][0]["after"] = 98;
                    snapshot["materials"][0]["count"] = 98;
                    break;
                case "material_identity_coherent":
                    response["materials"][0]["displayName"] =
                        "伪造材料展示名";
                    response["materials"][0]["icon"] =
                        "伪造材料图标";
                    snapshot["materials"][0]["displayName"] =
                        response["materials"][0]["displayName"].DeepClone();
                    snapshot["materials"][0]["icon"] =
                        response["materials"][0]["icon"].DeepClone();
                    break;
                case "material_snapshot_count":
                    snapshot["materials"][0]["count"] = 96;
                    break;
                case "material_snapshot_missing":
                    ((JArray)snapshot["materials"]).Clear();
                    break;
                case "snapshot_equipment":
                    snapshotEquipment["displayName"] =
                        "未对齐的快照显示名";
                    break;
                case "backpack_equipment":
                    item["icon"] = "未对齐的背包图标";
                    break;
                case "post_source_snapshot":
                    snapshot["source"]["expectedLease"] =
                        "lease.unmatched.snapshot";
                    break;
                case "post_source_backpack":
                    slot["slotLease"] =
                        "lease.unmatched.backpack";
                    break;
                case "last_update_not_advanced":
                    after["lastUpdate"] = 1000;
                    snapshotEquipment["lastUpdate"] = 1000;
                    confirm["lastUpdate"] = 1000;
                    break;
                case "removed_mods":
                    response["removedMods"] =
                        new JArray("伪造卸下插件");
                    break;
                case "can_commit":
                    response["canCommit"] = true;
                    break;
                default:
                    throw new InvalidOperationException(mutation);
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

        private static string ReceiptField(string receipt, string name)
        {
            string marker = name + "=";
            int start = receipt.IndexOf(marker, StringComparison.Ordinal);
            Assert.True(start >= 0, "Missing receipt field: " + name);
            start += marker.Length;
            int end = receipt.IndexOf(' ', start);
            return end >= 0
                ? receipt.Substring(start, end - start)
                : receipt.Substring(start);
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
                else if (operation != "detach_all_mods") payload["candidateKey"] = "candidate.one";
                if (operation == "replace_mod") payload["replaceCandidateKey"] = "candidate.old";
            }
            else if (cmd == "commit") payload["expectedTuningToken"] = "tuning.token.1";
            else if (cmd == "tooltip") payload["candidateKey"] = "candidate.one";

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

        private static JObject OperationSnapshotResponse(
            JObject command,
            string operation,
            bool noOp)
        {
            OperationFixture fixture = BuildOperationFixture(
                operation,
                noOp,
                1000);
            JObject response = CommonResponse(
                command,
                "snapshot",
                true);
            response["snapshot"] = SnapshotForEquipment(
                command["source"] as JObject,
                fixture.BeforeSourceEquipment,
                SnapshotMaterialCounts(
                    fixture.Materials,
                    false),
                operation,
                false);
            return response;
        }

        private static JObject OperationPreviewResponse(
            JObject command,
            string operation,
            bool noOp)
        {
            OperationFixture fixture = BuildOperationFixture(
                operation,
                noOp,
                1000);
            JObject source =
                (JObject)command["source"].DeepClone();
            JObject target = operation == "convert"
                ? (JObject)command["target"].DeepClone()
                : null;
            JObject response = CommonResponse(
                command,
                "preview",
                true);
            response["tuningToken"] = "tuning.token.1";
            response["operation"] = operation;
            response["before"] = OperationProjection(
                source,
                fixture.BeforeSourceEquipment,
                target,
                fixture.BeforeTargetEquipment);
            response["after"] = OperationProjection(
                source,
                fixture.AfterSourceEquipment,
                target,
                fixture.AfterTargetEquipment);
            response["materials"] =
                fixture.Materials.DeepClone();
            response["removedMods"] =
                fixture.RemovedMods.DeepClone();
            response["noOp"] = noOp;
            response["canCommit"] = true;
            return response;
        }

        private static JObject OperationCommitResponse(
            JObject command,
            string operation,
            bool noOp)
        {
            JObject beforeSource = Source(
                7,
                "lease.source.7");
            JObject beforeTarget = operation == "convert"
                ? Source(8, "lease.target.8")
                : null;
            JObject afterSource = BuildPostSource(
                beforeSource,
                noOp);
            JObject afterTarget = beforeTarget != null
                ? BuildPostSource(beforeTarget, noOp)
                : null;
            OperationFixture fixture = BuildOperationFixture(
                operation,
                noOp,
                noOp ? 1000 : 2000);
            JObject response = CommonResponse(
                command,
                "commit",
                true);
            response["tuningToken"] =
                (string)command["expectedTuningToken"];
            response["operation"] = operation;
            response["before"] = OperationProjection(
                beforeSource,
                fixture.BeforeSourceEquipment,
                beforeTarget,
                fixture.BeforeTargetEquipment);
            response["after"] = OperationProjection(
                afterSource,
                fixture.AfterSourceEquipment,
                afterTarget,
                fixture.AfterTargetEquipment);
            response["materials"] =
                fixture.Materials.DeepClone();
            response["removedMods"] =
                fixture.RemovedMods.DeepClone();
            response["canCommit"] = false;
            response["noOp"] = noOp;
            response["snapshot"] = SnapshotForEquipment(
                afterSource,
                fixture.AfterSourceEquipment,
                SnapshotMaterialCounts(
                    fixture.Materials,
                    true),
                operation,
                true);
            response["inventorySnapshots"] =
                FullBackpackSnapshots(
                    afterSource,
                    fixture.AfterSourceEquipment,
                    afterTarget,
                    fixture.AfterTargetEquipment);
            response["transactionId"] = "txn.operation.1";
            return response;
        }

        private static OperationFixture BuildOperationFixture(
            string operation,
            bool noOp,
            double afterLastUpdate)
        {
            int beforeLevel = 7;
            int afterLevel = 7;
            string beforeTier = "一阶";
            string afterTier = "一阶";
            var beforeMods = new JArray();
            var afterMods = new JArray();
            var materials = new JArray();
            var removedMods = new JArray();
            JObject beforeTarget = null;
            JObject afterTarget = null;

            switch (operation)
            {
                case "enhance":
                    afterLevel = 8;
                    materials = EnhancementMaterials();
                    break;
                case "convert":
                    int targetLevel = noOp ? 7 : 5;
                    afterLevel = targetLevel;
                    beforeTarget = EquipmentProjection(
                        targetLevel,
                        1000,
                        new JArray(),
                        "测试手枪B",
                        "测试手枪乙",
                        "测试手枪图标乙",
                        "一阶");
                    afterTarget = EquipmentProjection(
                        noOp ? targetLevel : beforeLevel,
                        afterLastUpdate,
                        new JArray(),
                        "测试手枪B",
                        "测试手枪乙",
                        "测试手枪图标乙",
                        "一阶");
                    break;
                case "install_tier":
                    beforeTier = "";
                    afterTier = "一阶";
                    materials.Add(MaterialRow(
                        "测试进阶材料",
                        3,
                        -1,
                        2));
                    break;
                case "install_mod":
                    afterMods.Add("测试插件A");
                    materials.Add(MaterialRow(
                        "测试插件A",
                        5,
                        -1,
                        4));
                    break;
                case "replace_mod":
                    beforeMods.Add("旧插件");
                    afterMods.Add("测试插件A");
                    removedMods.Add("旧插件");
                    materials.Add(MaterialRow(
                        "旧插件",
                        0,
                        1,
                        1));
                    materials.Add(MaterialRow(
                        "测试插件A",
                        5,
                        -1,
                        4));
                    break;
                case "detach_mod":
                    beforeMods.Add("旧插件");
                    removedMods.Add("旧插件");
                    materials.Add(MaterialRow(
                        "旧插件",
                        0,
                        1,
                        1));
                    break;
                case "detach_all_mods":
                    beforeMods.Add("旧插件");
                    beforeMods.Add("依赖插件");
                    removedMods.Add("旧插件");
                    removedMods.Add("依赖插件");
                    materials.Add(MaterialRow(
                        "旧插件",
                        0,
                        1,
                        1));
                    materials.Add(MaterialRow(
                        "依赖插件",
                        2,
                        1,
                        3));
                    break;
                default:
                    throw new InvalidOperationException(operation);
            }

            return new OperationFixture
            {
                BeforeSourceEquipment = EquipmentProjection(
                    beforeLevel,
                    1000,
                    beforeMods,
                    "测试手枪A",
                    "测试手枪甲",
                    "测试手枪图标甲",
                    beforeTier),
                AfterSourceEquipment = EquipmentProjection(
                    afterLevel,
                    afterLastUpdate,
                    afterMods,
                    "测试手枪A",
                    "测试手枪甲",
                    "测试手枪图标甲",
                    afterTier),
                BeforeTargetEquipment = beforeTarget,
                AfterTargetEquipment = afterTarget,
                Materials = materials,
                RemovedMods = removedMods
            };
        }

        private static JObject MaterialRow(
            string itemName,
            int before,
            int delta,
            int after)
        {
            return new JObject
            {
                ["itemName"] = itemName,
                ["displayName"] = MaterialDisplayName(itemName),
                ["icon"] = MaterialIcon(itemName),
                ["before"] = before,
                ["delta"] = delta,
                ["after"] = after
            };
        }

        private static JObject SnapshotMaterialRow(
            string itemName,
            int count)
        {
            return new JObject
            {
                ["itemName"] = itemName,
                ["displayName"] = MaterialDisplayName(itemName),
                ["icon"] = MaterialIcon(itemName),
                ["count"] = count
            };
        }

        private static JObject OperationProjection(
            JObject source,
            JObject sourceEquipment,
            JObject target,
            JObject targetEquipment)
        {
            var projection = new JObject
            {
                ["source"] = new JObject
                {
                    ["source"] = source.DeepClone(),
                    ["equipment"] = sourceEquipment.DeepClone()
                }
            };
            if (target != null)
            {
                projection["target"] = new JObject
                {
                    ["source"] = target.DeepClone(),
                    ["equipment"] = targetEquipment.DeepClone()
                };
            }
            return projection;
        }

        private static JArray SnapshotMaterialCounts(
            JArray materials,
            bool after)
        {
            var result = new JArray();
            bool hasEnhancementStone = false;
            foreach (JToken token in materials)
            {
                JObject row = (JObject)token;
                string itemName = (string)row["itemName"];
                if (itemName == "强化石")
                    hasEnhancementStone = true;
                result.Add(new JObject
                {
                    ["itemName"] = itemName,
                    ["displayName"] = row["displayName"].DeepClone(),
                    ["icon"] = row["icon"].DeepClone(),
                    ["count"] = (int)row[
                        after ? "after" : "before"]
                });
            }
            if (!hasEnhancementStone)
            {
                result.Add(new JObject
                {
                    ["itemName"] = "强化石",
                    ["displayName"] = MaterialDisplayName("强化石"),
                    ["icon"] = MaterialIcon("强化石"),
                    ["count"] = 100
                });
            }
            return result;
        }

        private static string MaterialDisplayName(string itemName)
        {
            return "展示名·" + itemName;
        }

        private static string MaterialIcon(string itemName)
        {
            return "图标名·" + itemName;
        }

        private static JObject SnapshotForEquipment(
            JObject source,
            JObject equipment,
            JArray materialSnapshot,
            string operation = "enhance",
            bool postState = false)
        {
            JArray mods = (JArray)equipment["mods"];
            var modCandidates = new JArray();
            for (int index = 0; index < mods.Count; index++)
            {
                string installedName = (string)mods[index];
                string installedKey = operation == "detach_mod"
                    ? "candidate.one"
                    : operation == "replace_mod"
                        ? "candidate.old"
                        : "mod.installed." + index;
                if (postState && (operation == "install_mod"
                        || operation == "replace_mod")
                    && installedName == "测试插件A")
                {
                    installedKey = "candidate.one";
                }
                modCandidates.Add(ModCandidate(
                    installedKey,
                    installedName,
                    MaterialCount(materialSnapshot, installedName),
                    true,
                    false,
                    new JArray()));
            }
            if (!postState && operation == "install_mod")
                modCandidates.Add(ModCandidate(
                    "candidate.one", "测试插件A", 5,
                    false, true, new JArray()));
            if (!postState && operation == "replace_mod")
                modCandidates.Add(ModCandidate(
                    "candidate.one", "测试插件A", 5,
                    false, false, new JArray("candidate.old")));
            var tierCandidates = new JArray();
            if (operation == "install_tier")
            {
                tierCandidates.Add(TierCandidate(
                    "candidate.one",
                    "测试进阶材料",
                    "一阶",
                    MaterialCount(
                        materialSnapshot,
                        "测试进阶材料"),
                    !postState));
            }
            return new JObject
            {
                ["gender"] = "男",
                ["source"] = source.DeepClone(),
                ["equipment"] = equipment.DeepClone(),
                ["enhance"] = new JObject
                {
                    ["currentLevel"] = equipment["level"].DeepClone(),
                    ["maxLevel"] = equipment["maxLevel"].DeepClone(),
                    ["availableMaxLevel"] = equipment["maxLevel"].DeepClone(),
                    ["hardMaxLevel"] = equipment["hardMaxLevel"].DeepClone()
                },
                ["tierCandidates"] = tierCandidates,
                ["modCandidates"] = modCandidates,
                ["materials"] = materialSnapshot.DeepClone(),
                ["materialRevision"] = 7,
                ["inventoryRevision"] = 11
            };
        }

        private static int MaterialCount(
            JArray materials,
            string itemName)
        {
            if (materials == null) return 0;
            foreach (JToken token in materials)
            {
                JObject row = token as JObject;
                if ((string)(row != null ? row["itemName"] : null)
                        == itemName)
                    return (int)row["count"];
            }
            return 0;
        }

        private static JObject TierCandidate(
            string candidateKey,
            string itemName,
            string tierName,
            int owned,
            bool available)
        {
            return new JObject
            {
                ["candidateKey"] = candidateKey,
                ["itemName"] = itemName,
                ["displayName"] = MaterialDisplayName(itemName),
                ["icon"] = MaterialIcon(itemName),
                ["tierName"] = tierName,
                ["owned"] = owned,
                ["available"] = available,
                ["reason"] = available ? "" : "tier_transition_rejected"
            };
        }

        private static JObject ModCandidate(
            string candidateKey,
            string itemName,
            int owned,
            bool installed,
            bool available,
            JArray replaceableFrom)
        {
            return new JObject
            {
                ["candidateKey"] = candidateKey,
                ["itemName"] = itemName,
                ["displayName"] = MaterialDisplayName(itemName),
                ["icon"] = MaterialIcon(itemName),
                ["owned"] = owned,
                ["installed"] = installed,
                ["available"] = available,
                ["availabilityCode"] = available ? 1 : installed ? -2 : -1,
                ["reason"] = available ? "" : installed
                    ? "already_installed" : "slot_full",
                ["replaceableFrom"] = replaceableFrom,
                ["grade"] = "common",
                ["scope"] = "firearm",
                ["role"] = "utility"
            };
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
            JArray beforeMods = new JArray();
            JArray afterMods = operation == "install_mod"
                ? new JArray("测试插件A")
                : new JArray();
            response["before"] =
                TuningProjection(source, 7, 1000, beforeMods);
            response["after"] =
                TuningProjection(
                    source,
                    operation == "enhance" ? 8 : 7,
                    1000,
                    afterMods);
            response["materials"] = OperationMaterials(operation);
            response["removedMods"] = new JArray();
            response["noOp"] = false;
            response["canCommit"] = true;
            return response;
        }

        private static JObject CommitResponse(
            JObject command,
            JObject beforeSource = null,
            bool noOp = false,
            string operation = "enhance")
        {
            JObject response = CommonResponse(command, "commit", true);
            response["tuningToken"] =
                (string)command[
                    "expectedTuningToken"];
            response["operation"] = operation;
            beforeSource = beforeSource
                ?? Source(7, "lease.source.7");
            JObject afterSource =
                BuildPostSource(
                    beforeSource, noOp);
            JArray beforeMods = new JArray();
            JArray afterMods = operation == "install_mod"
                ? new JArray("测试插件A")
                : new JArray();
            response["before"] =
                TuningProjection(
                    beforeSource,
                    7,
                    1000,
                    beforeMods);
            response["after"] =
                TuningProjection(
                    afterSource,
                    operation == "enhance" && !noOp ? 8 : 7,
                    noOp ? 1000 : 2000,
                    afterMods);
            response["materials"] = OperationMaterials(operation);
            response["removedMods"] = new JArray();
            response["canCommit"] = false;
            response["noOp"] = noOp;
            response["snapshot"] = Snapshot(
                afterSource,
                operation == "enhance" && !noOp ? 8 : 7,
                noOp ? 1000 : 2000,
                operation == "enhance" ? 97 : 100,
                afterMods,
                operation);
            response["inventorySnapshots"] =
                (string)beforeSource["sourceKind"]
                    == "loadout"
                ? new JArray()
                : FullBackpackSnapshots(
                    afterSource,
                    (JObject)response["after"]["source"]["equipment"]);
            response["transactionId"] = "txn.1";
            return response;
        }

        private static JObject TuningProjection(
            JObject source,
            int level,
            double lastUpdate,
            JArray mods = null)
        {
            return new JObject
            {
                ["source"] = new JObject
                {
                    ["source"] =
                        source.DeepClone(),
                    ["equipment"] =
                        EquipmentProjection(
                            level,
                            lastUpdate,
                            mods)
                }
            };
        }

        private static JObject EquipmentProjection(
            int level,
            double lastUpdate,
            JArray mods = null,
            string name = "测试手枪A",
            string displayName = "测试手枪甲",
            string icon = "测试手枪图标甲",
            string tier = "一阶")
        {
            return new JObject
            {
                ["name"] = name,
                ["displayName"] = displayName,
                ["icon"] = icon,
                ["type"] = "武器",
                ["use"] = "手枪",
                ["level"] = level,
                ["tier"] = tier,
                ["mods"] = mods != null
                    ? mods.DeepClone() : new JArray(),
                ["lastUpdate"] = lastUpdate,
                ["modSlotCapacity"] = 3,
                ["maxLevel"] = 13,
                ["hardMaxLevel"] = 13
            };
        }

        private static JArray EnhancementMaterials()
        {
            return new JArray
            {
                MaterialRow("强化石", 100, -3, 97)
            };
        }

        private static JArray OperationMaterials(string operation)
        {
            if (operation == "install_mod")
            {
                return new JArray
                {
                    MaterialRow("测试插件A", 5, -1, 4)
                };
            }
            return EnhancementMaterials();
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
            response["candidateKey"] = command["candidateKey"].DeepClone();
            response["introHTML"] = "<b>候选</b>";
            response["descHTML"] = "候选说明";
            response["itemType"] = "收集品";
            response["itemUse"] = "材料";
            response["text"] = "候选";
            return response;
        }

        private static JObject Snapshot(
            JObject source = null,
            int level = 7,
            double lastUpdate = 1000,
            int stoneCount = 100,
            JArray mods = null,
            string operation = "enhance")
        {
            mods = mods ?? new JArray();
            var modCandidates = new JArray();
            bool hasTestMod = false;
            bool hasOldMod = false;
            for (int index = 0; index < mods.Count; index++)
            {
                string installedName = (string)mods[index];
                hasTestMod = hasTestMod
                    || installedName == "测试插件A";
                hasOldMod = hasOldMod
                    || installedName == "旧插件";
                modCandidates.Add(ModCandidate(
                    installedName == "测试插件A"
                        ? "candidate.one"
                        : installedName == "旧插件"
                            ? "candidate.old"
                            : "mod.installed." + index,
                    installedName,
                    installedName == "测试插件A"
                        && operation == "install_mod" ? 4 : 0,
                    true,
                    false,
                    new JArray()));
            }
            if (!hasTestMod)
                modCandidates.Add(ModCandidate(
                    "candidate.one",
                    "测试插件A",
                    5,
                    false,
                    true,
                    new JArray("candidate.old")));
            if (!hasOldMod)
                modCandidates.Add(ModCandidate(
                    "candidate.old",
                    "旧插件",
                    0,
                    false,
                    false,
                    new JArray()));
            var materialSnapshot = new JArray
            {
                new JObject
                {
                    ["itemName"] = "强化石",
                    ["displayName"] = MaterialDisplayName("强化石"),
                    ["icon"] = MaterialIcon("强化石"),
                    ["count"] = stoneCount
                }
            };
            materialSnapshot.Add(new JObject
            {
                ["itemName"] = "测试插件A",
                ["displayName"] = MaterialDisplayName("测试插件A"),
                ["icon"] = MaterialIcon("测试插件A"),
                ["count"] = operation == "install_mod" ? 4 : 5
            });
            materialSnapshot.Add(new JObject
            {
                ["itemName"] = "测试进阶材料",
                ["displayName"] = MaterialDisplayName("测试进阶材料"),
                ["icon"] = MaterialIcon("测试进阶材料"),
                ["count"] = 3
            });
            return new JObject
            {
                ["gender"] = "男",
                ["source"] = (source
                    ?? Source(
                        7,
                        "lease.source.7"))
                    .DeepClone(),
                ["equipment"] = EquipmentProjection(
                    level,
                    lastUpdate,
                    mods),
                ["enhance"] = new JObject
                {
                    ["currentLevel"] = level,
                    ["maxLevel"] = 13,
                    ["availableMaxLevel"] = 13,
                    ["hardMaxLevel"] = 13
                },
                ["tierCandidates"] = new JArray(
                    TierCandidate(
                        "candidate.one",
                        "测试进阶材料",
                        "一阶",
                        3,
                        true)),
                ["modCandidates"] = modCandidates,
                ["materials"] = materialSnapshot,
                ["materialRevision"] = 7,
                ["inventoryRevision"] = 11
            };
        }

        private static JObject InstalledModCandidate(
            string itemName,
            int index = 0)
        {
            return new JObject
            {
                ["candidateKey"] = "mod.installed." + index,
                ["itemName"] = itemName,
                ["displayName"] = "测试插件甲",
                ["icon"] = "测试插件图标甲",
                ["owned"] = 4,
                ["installed"] = true,
                ["available"] = false,
                ["availabilityCode"] = -2,
                ["reason"] = "already_installed",
                ["replaceableFrom"] = new JArray(),
                ["grade"] = "common",
                ["scope"] = "firearm",
                ["role"] = "utility"
            };
        }

        private static JArray IdentityTripleCandidates()
        {
            return new JArray
            {
                IdentityTripleCandidate(
                    "mod.identity.0",
                    "光棱射线弹-强化",
                    "棱镜折射阵列",
                    "全光谱棱镜阵列"),
                IdentityTripleCandidate(
                    "mod.identity.1",
                    "光谱射线弹",
                    "色散射线弹",
                    "棱栅射线弹"),
                IdentityTripleCandidate(
                    "mod.identity.2",
                    "光谱射线弹-强化",
                    "全谱色散引擎",
                    "环式棱栅折射阵列")
            };
        }

        private static JObject IdentityTripleCandidate(
            string candidateKey,
            string itemName,
            string displayName,
            string icon)
        {
            return new JObject
            {
                ["candidateKey"] = candidateKey,
                ["itemName"] = itemName,
                ["displayName"] = displayName,
                ["icon"] = icon,
                ["owned"] = 1,
                ["installed"] = false,
                ["available"] = true,
                ["availabilityCode"] = 1,
                ["reason"] = "",
                ["replaceableFrom"] = new JArray(),
                ["grade"] = "high",
                ["scope"] = "firearm",
                ["role"] = "precision"
            };
        }

        private static JArray FullBackpackSnapshots(
            JObject source,
            JObject equipment,
            JObject targetSource = null,
            JObject targetEquipment = null)
        {
            var slots = new JArray();
            int occupiedCount = targetSource == null ? 1 : 2;
            for (int slot = 0; slot < 50; slot++)
            {
                if (slot == source.Value<int>("slot"))
                {
                    slots.Add(OccupiedBackpackSlot(
                        source,
                        equipment));
                }
                else if (targetSource != null
                    && slot == targetSource.Value<int>("slot"))
                {
                    slots.Add(OccupiedBackpackSlot(
                        targetSource,
                        targetEquipment));
                }
                else
                {
                    slots.Add(new JObject
                    {
                        ["physicalSlot"] = slot,
                        ["occupied"] = false,
                        ["slotLease"] =
                            "lease.empty." + slot
                    });
                }
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
                        new JArray
                        {
                            new JObject
                            {
                                ["id"] = "all",
                                ["label"] = "全部",
                                ["order"] = 0,
                                ["count"] = occupiedCount,
                                ["children"] = new JArray()
                            }
                        },
                    ["filterItemCount"] = occupiedCount,
                    ["setFacets"] =
                        new JArray(),
                    ["setFilterItemCount"] = 0
                }
            };
        }

        private static JObject OccupiedBackpackSlot(
            JObject source,
            JObject equipment)
        {
            JObject item = BackpackItemProjection(equipment);
            return new JObject
            {
                ["physicalSlot"] = source.Value<int>("slot"),
                ["occupied"] = true,
                ["slotLease"] = (string)source["expectedLease"],
                ["item"] = item,
                ["confirmProjection"] = new JObject
                {
                    ["itemKind"] = "equipment",
                    ["name"] = equipment["name"].DeepClone(),
                    ["displayName"] = equipment["displayName"].DeepClone(),
                    ["quantity"] = 1,
                    ["enhancementLevel"] = equipment["level"].DeepClone(),
                    ["rarity"] = "rare",
                    ["tier"] = equipment["tier"].DeepClone(),
                    ["modSignature"] = TestModSignature(
                        (JArray)equipment["mods"]),
                    ["lastUpdate"] = equipment["lastUpdate"].DeepClone()
                }
            };
        }

        private static JObject BackpackItemProjection(
            JObject equipment)
        {
            JArray mods = (JArray)equipment["mods"];
            int level = equipment.Value<int>("level");
            int hardMax = equipment.Value<int>("hardMaxLevel");
            return new JObject
            {
                ["name"] = equipment["name"].DeepClone(),
                ["displayName"] = equipment["displayName"].DeepClone(),
                ["icon"] = equipment["icon"].DeepClone(),
                ["majorType"] = equipment["type"].DeepClone(),
                ["use"] = equipment["use"].DeepClone(),
                ["actionType"] = "",
                ["weaponType"] = "",
                ["setId"] = "",
                ["setName"] = "",
                ["setOrder"] = 0,
                ["itemKind"] = "equipment",
                ["quantity"] = 1,
                ["enhancementLevel"] = level,
                ["maxEnhancementLevel"] = hardMax,
                ["isMaxEnhancement"] = level >= hardMax,
                ["tierSlotAvailable"] = true,
                ["tierSlotUsed"] = true,
                ["modSlotCapacity"] = equipment.Value<int>("modSlotCapacity"),
                ["modSlotUsed"] = mods.Count,
                ["modSlots"] = new JArray(),
                ["modMeta"] = JValue.CreateNull(),
                ["rarity"] = "rare"
            };
        }

        private static string TestModSignature(JArray mods)
        {
            string result = "";
            foreach (JToken token in mods)
            {
                string name = (string)token;
                result += name.Length + ":" + name + ";";
            }
            return result;
        }

        private static JObject ParseWire(string value)
        {
            return JObject.Parse(value.TrimEnd('\0'));
        }
    }
}
