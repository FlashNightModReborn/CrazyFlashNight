using System;
using System.Collections.Generic;
using System.Threading;
using Newtonsoft.Json.Linq;
using Xunit;
using CF7Launcher.Guardian;
using CF7Launcher.Tasks;
using CF7Launcher.Tests.Contracts;

namespace Launcher.Tests.Tasks
{
    public sealed class CraftingTaskTests
    {
        private const string DefaultPanelInstanceId = "panel.crafting.instance.1";

        private static JObject Request(string cmd, string callId,
            string panelInstanceId = DefaultPanelInstanceId)
        {
            var payload = new JObject { ["v"] = 1 };
            if (cmd == "tooltip" || cmd == "materialDetail") payload["itemName"] = "不锈钢材";
            else if (cmd == "materials") { }
            else if (cmd == "setPlan")
            {
                payload["recipeId"] = "craft.weapon.004";
                payload["plannedCrafts"] = 1;
                payload["expectedRevision"] = 0;
            }
            else
            {
                payload["category"] = "武器合成";
                if (cmd == "preview") { payload["recipeIndex"] = 3; payload["craftCount"] = 2; }
                if (cmd == "commit") payload["expectedCraftToken"] = "craft.10.1";
            }
            return new JObject
            {
                ["type"] = "panel", ["domain"] = "crafting", ["panel"] = "crafting",
                ["panelInstanceId"] = panelInstanceId,
                ["cmd"] = cmd, ["callId"] = callId, ["payload"] = payload
            };
        }

        private static void AssertOwnerTuple(JObject response, string cmd, string callId,
            string panelInstanceId = DefaultPanelInstanceId)
        {
            Assert.Equal("panel_resp", (string)response["type"]);
            Assert.Equal("crafting", (string)response["domain"]);
            Assert.Equal("crafting", (string)response["panel"]);
            Assert.Equal(panelInstanceId, (string)response["panelInstanceId"]);
            Assert.Equal(cmd, (string)response["cmd"]);
            Assert.Equal(callId, (string)response["callId"]);
        }

        [Theory]
        [InlineData("snapshot", "craftingSnapshot")]
        [InlineData("materials", "craftingMaterials")]
        [InlineData("materialDetail", "craftingMaterialDetail")]
        [InlineData("preview", "craftingPreview")]
        [InlineData("tooltip", "craftingTooltip")]
        [InlineData("setPlan", "craftingPlanSet")]
        [InlineData("commit", "craftingCommit")]
        public void WebRequest_MapsStrictCommands(string cmd, string expectedAction)
        {
            var sentCommands = new List<JObject>();
            string web = null;
            using (var task = new CraftingTask(() => true, value =>
            {
                sentCommands.Add(JObject.Parse(value.TrimEnd('\0')));
                return true;
            }))
            {
                task.SetPostToWeb(value => web = value);
                if (cmd == "commit") PrimeCommitAuthority(task, sentCommands);
                task.HandleWebRequest(cmd, Request(cmd, "craft.command." + cmd));
                JObject command = sentCommands[sentCommands.Count - 1];
                Assert.Equal(expectedAction, (string)command["action"]);
                Assert.Equal(1, (int)command["v"]);
                Assert.Null(command["payload"]);
                if (cmd == "preview") Assert.Equal(2, (int)command["craftCount"]);
                if (cmd == "snapshot")
                {
                    task.HandleFlashResponse(SnapshotResponse((int)command["callId"]), null);
                    JObject response = JObject.Parse(web);
                    AssertOwnerTuple(response, "snapshot", "craft.command.snapshot");
                    Assert.True((bool)response["success"]);
                    Assert.Equal("男", (string)response["gender"]);
                    Assert.True((bool)response["recipes"][0]["canCraftOne"]);
                    Assert.Equal("ready", (string)response["recipes"][0]["availability"]);

                    task.HandleWebRequest("snapshot", Request("snapshot", "craft.command.snapshot.inconsistent"));
                    JObject inconsistentCommand = sentCommands[sentCommands.Count - 1];
                    JObject inconsistent = SnapshotResponse((int)inconsistentCommand["callId"]);
                    inconsistent["recipes"][0]["canCraftOne"] = false;
                    task.HandleFlashResponse(inconsistent, null);
                    Assert.Equal("malformed_response", (string)JObject.Parse(web)["error"]);
                }
            }
        }

        [Fact]
        public void MaterialReads_RequireStrictCatalogAndDetailShapes()
        {
            string sent = null;
            string web = null;
            using (var task = new CraftingTask(() => true, value => { sent = value; return true; }))
            {
                task.SetPostToWeb(value => web = value);
                task.HandleWebRequest("materials", Request("materials", "craft.materials"));
                int catalogFid = (int)JObject.Parse(sent.TrimEnd('\0'))["callId"];
                task.HandleFlashResponse(MaterialsResponse(catalogFid), null);
                JObject catalog = JObject.Parse(web);
                Assert.True((bool)catalog["success"]);
                Assert.Equal("不锈钢材", (string)catalog["materials"][0]["name"]);

                task.HandleWebRequest("materialDetail", Request("materialDetail", "craft.material.detail"));
                int detailFid = (int)JObject.Parse(sent.TrimEnd('\0'))["callId"];
                task.HandleFlashResponse(MaterialDetailResponse(detailFid), null);
                JObject detail = JObject.Parse(web);
                Assert.True((bool)detail["success"]);
                Assert.Equal("武器合成", (string)detail["uses"][0]["category"]);
                Assert.Equal("enemy.internal", (string)detail["sources"][0]["enemyType"]);
                Assert.Equal("敌人展示名", (string)detail["sources"][0]["displayName"]);
                Assert.Equal("quest.internal", (string)detail["sources"][1]["questId"]);
                Assert.Equal("任务展示名", (string)detail["sources"][1]["title"]);

                task.HandleWebRequest("materialDetail", Request(
                    "materialDetail", "craft.material.detail.equal"));
                JObject equalDetail = MaterialDetailResponse(
                    (int)JObject.Parse(sent.TrimEnd('\0'))["callId"]);
                equalDetail["sources"][0]["displayName"] = "enemy.internal";
                equalDetail["sources"][1]["title"] = "quest.internal";
                task.HandleFlashResponse(equalDetail, null);
                JObject equalResponse = JObject.Parse(web);
                Assert.True((bool)equalResponse["success"]);
                Assert.Equal("enemy.internal", (string)equalResponse["sources"][0]["displayName"]);
                Assert.Equal("quest.internal", (string)equalResponse["sources"][1]["title"]);

                for (int variant = 0; variant < 8; variant++)
                {
                    task.HandleWebRequest("materialDetail", Request(
                        "materialDetail", "craft.material.detail.bad." + variant));
                    JObject badDetail = MaterialDetailResponse(
                        (int)JObject.Parse(sent.TrimEnd('\0'))["callId"]);
                    bool enemy = variant < 4;
                    JObject source = (JObject)badDetail["sources"][enemy ? 0 : 1];
                    string field = enemy ? "displayName" : "title";
                    int leafVariant = variant % 4;
                    if (leafVariant == 0) source.Remove(field);
                    else if (leafVariant == 1) source[field] = "   ";
                    else if (leafVariant == 2) source[field] = " Undefined ";
                    else source[field] = 17;
                    task.HandleFlashResponse(badDetail, null);
                    Assert.Equal("malformed_response", (string)JObject.Parse(web)["error"]);
                }

                task.HandleWebRequest("materials", Request("materials", "craft.materials.bad"));
                int malformedFid = (int)JObject.Parse(sent.TrimEnd('\0'))["callId"];
                JObject malformed = MaterialsResponse(malformedFid);
                malformed["materials"][0]["sourceCount"] = -1;
                task.HandleFlashResponse(malformed, null);
                JObject malformedResponse = JObject.Parse(web);
                AssertOwnerTuple(malformedResponse, "materials", "craft.materials.bad");
                Assert.Equal("malformed_response", (string)malformedResponse["error"]);
            }
        }

        [Fact]
        public void SnapshotResponse_RequiresStrictGender()
        {
            string sent = null;
            string web = null;
            using (var task = new CraftingTask(() => true, value => { sent = value; return true; }))
            {
                task.SetPostToWeb(value => web = value);

                task.HandleWebRequest("snapshot", Request("snapshot", "craft.gender.missing"));
                JObject missing = SnapshotResponse((int)JObject.Parse(sent.TrimEnd('\0'))["callId"]);
                missing.Remove("gender");
                task.HandleFlashResponse(missing, null);
                Assert.Equal("malformed_response", (string)JObject.Parse(web)["error"]);

                task.HandleWebRequest("snapshot", Request("snapshot", "craft.gender.invalid"));
                JObject invalid = SnapshotResponse((int)JObject.Parse(sent.TrimEnd('\0'))["callId"]);
                invalid["gender"] = "female";
                task.HandleFlashResponse(invalid, null);
                Assert.Equal("malformed_response", (string)JObject.Parse(web)["error"]);

                task.HandleWebRequest("snapshot", Request("snapshot", "craft.gender.female"));
                JObject female = SnapshotResponse((int)JObject.Parse(sent.TrimEnd('\0'))["callId"]);
                female["gender"] = "女";
                task.HandleFlashResponse(female, null);
                JObject response = JObject.Parse(web);
                AssertOwnerTuple(response, "snapshot", "craft.gender.female");
                Assert.True((bool)response["success"]);
                Assert.Equal("女", (string)response["gender"]);
            }
        }

        [Fact]
        public void WebRequest_RejectsUnknownCategoryBeforeFlash()
        {
            bool sent = false;
            string web = null;
            using (var task = new CraftingTask(() => true, value => { sent = true; return true; }))
            {
                task.SetPostToWeb(value => web = value);
                JObject request = Request("snapshot", "craft.bad.category");
                request["payload"]["category"] = "不存在";
                task.HandleWebRequest("snapshot", request);
                Assert.False(sent);
                Assert.Equal("invalid_payload", (string)JObject.Parse(web)["error"]);

                sent = false;
                JObject wrongVersion = Request("snapshot", "craft.bad.version");
                wrongVersion["payload"]["v"] = "1";
                task.HandleWebRequest("snapshot", wrongVersion);
                Assert.False(sent);
                Assert.Equal("invalid_payload", (string)JObject.Parse(web)["error"]);
            }
        }

        [Theory]
        [MemberData(nameof(PanelContractVectors.CraftingCraftCountValid), MemberType = typeof(PanelContractVectors))]
        public void PreviewCraftCount_WithinContract_IsForwardedToAuthority(int craftCount)
        {
            string sent = null;
            using (var task = new CraftingTask(() => true, value => { sent = value; return true; }))
            {
                JObject request = Request("preview", "craft.count.valid." + craftCount);
                request["payload"]["craftCount"] = craftCount;

                task.HandleWebRequest("preview", request);

                Assert.Equal(craftCount, (int)JObject.Parse(sent.TrimEnd('\0'))["craftCount"]);
            }
        }

        [Theory]
        [MemberData(nameof(PanelContractVectors.CraftingCraftCountInvalid), MemberType = typeof(PanelContractVectors))]
        public void PreviewCraftCount_OutsideContract_IsRejectedBeforeFlash(int craftCount)
        {
            int sends = 0;
            string web = null;
            using (var task = new CraftingTask(() => true, _ => { sends++; return true; }))
            {
                task.SetPostToWeb(value => web = value);
                JObject request = Request("preview", "craft.count.invalid." + craftCount);
                request["payload"]["craftCount"] = craftCount;

                task.HandleWebRequest("preview", request);

                Assert.Equal(0, sends);
                Assert.Equal("invalid_payload", (string)JObject.Parse(web)["error"]);
            }
        }

        [Fact]
        public void CommitSuccess_RequiresAuthoritativeShapeAndClearsGate()
        {
            var sent = new List<JObject>();
            string web = null;
            using (var task = new CraftingTask(() => true, value => { sent.Add(JObject.Parse(value.TrimEnd('\0'))); return true; }))
            {
                task.SetPostToWeb(value => web = value);
                PrimeCommitAuthority(task, sent);
                task.HandleWebRequest("commit", Request("commit", "craft.commit.ok"));
                int fid = (int)sent[sent.Count - 1]["callId"];
                task.HandleFlashResponse(CommitResponse(fid), null);
                JObject response = JObject.Parse(web);
                AssertOwnerTuple(response, "commit", "craft.commit.ok");
                Assert.True((bool)response["success"]);
                Assert.Equal("commit", (string)response["operation"]);
                Assert.Equal("光棱射线弹-强化", (string)response["crafted"]["name"]);
                Assert.Equal("棱镜折射阵列", (string)response["crafted"]["displayName"]);
                Assert.Equal("全光谱棱镜阵列", (string)response["crafted"]["icon"]);
                Assert.Equal("bag", (string)response["acceptedPlan"]["materials"][0]["storageKind"]);
                Assert.Equal("bag", (string)response["acceptedPlan"]["outputDelivery"]["storageKind"]);
                Assert.Equal("idle", task.WriteState);
                Assert.Null(response["requiresReconcile"]);
            }
        }

        [Theory]
        [InlineData("rarity")]
        [InlineData("maximum")]
        [InlineData("mod-meta")]
        [InlineData("mod-signature")]
        [InlineData("balance-presence")]
        [InlineData("balance-value")]
        public void CommitReceipt_MustMatchEveryFrozenEquipmentProjectionField(string drift)
        {
            var sent = new List<JObject>();
            JObject posted = null;
            using (var task = new CraftingTask(
                () => true,
                value => { sent.Add(JObject.Parse(value.TrimEnd('\0'))); return true; }))
            {
                task.SetPostToWeb(value => posted = JObject.Parse(value));
                PrimeCommitAuthority(task, sent);
                task.HandleWebRequest("commit", Request("commit", "craft.receipt." + drift));
                JObject response = CommitResponse((int)sent[sent.Count - 1]["callId"]);
                JObject item = (JObject)response["outputReceipt"]["item"];
                JObject confirm = (JObject)response["outputReceipt"]["confirmProjection"];
                if (drift == "rarity") item["rarity"] = "legendary";
                else if (drift == "maximum") item["maxEnhancementLevel"] = 14;
                else if (drift == "mod-meta") item["modMeta"] = ValidModProjection();
                else if (drift == "mod-signature") confirm["modSignature"] = "1:x;";
                else if (drift == "balance-presence") item.Remove("balanceSummary");
                else item["balanceSummary"]["weightLayers"] = 3;

                task.HandleFlashResponse(response, null);
                Assert.False((bool)posted["success"]);
                Assert.Equal("malformed_response", (string)posted["error"]);
                Assert.True((bool)posted["requiresReconcile"]);
                Assert.Equal("needs_reconcile", task.WriteState);
            }
        }

        [Theory]
        [InlineData("information_collection", "information_collection", "increment", -1, true)]
        [InlineData("bag", "bag", "insert", 3, true)]
        [InlineData("material_collection", "material_collection", "increment", -1, true)]
        [InlineData("drug", "drug", "merge", 4, true)]
        [InlineData("bag_and_drug", "bag", "merge", 5, true)]
        [InlineData("unavailable", "unavailable", "none", -1, false)]
        public void StorageRouteMatrix_PreviewAndCommitEchoExactAcceptedPlan(
            string materialStorageKind, string deliveryStorageKind, string deliveryMode,
            int physicalSlot, bool committable)
        {
            var sent = new List<JObject>();
            var posted = new List<JObject>();
            using (var task = new CraftingTask(() => true, value =>
            {
                sent.Add(JObject.Parse(value.TrimEnd('\0')));
                return true;
            }))
            {
                task.SetPostToWeb(value => posted.Add(JObject.Parse(value)));
                JObject previewRequest = Request("preview",
                    "craft.route.matrix." + materialStorageKind);
                previewRequest["payload"]["craftCount"] = 1;
                task.HandleWebRequest("preview", previewRequest);
                int previewFid = (int)sent[sent.Count - 1]["callId"];
                JObject preview = RoutedPreviewResponse(previewFid, materialStorageKind,
                    deliveryStorageKind, deliveryMode, physicalSlot, committable);
                task.HandleFlashResponse(preview, null);

                JObject previewPosted = posted[posted.Count - 1];
                AssertOwnerTuple(previewPosted, "preview",
                    "craft.route.matrix." + materialStorageKind);
                Assert.True((bool)previewPosted["success"]);
                Assert.Equal(materialStorageKind,
                    (string)previewPosted["materials"][0]["storageKind"]);
                Assert.Equal(deliveryStorageKind,
                    (string)previewPosted["outputDelivery"]["storageKind"]);
                if (!committable)
                {
                    Assert.False((bool)previewPosted["canCommit"]);
                    Assert.Null(previewPosted["acceptedPlan"]);
                    int sendsBeforeCommit = sent.Count;
                    task.HandleWebRequest("commit", Request("commit",
                        "craft.route.matrix.unavailable.commit"));
                    Assert.Equal(sendsBeforeCommit, sent.Count);
                    Assert.Equal("stale_state", (string)posted[posted.Count - 1]["error"]);
                    return;
                }

                Assert.True((bool)previewPosted["canCommit"]);
                Assert.True(JToken.DeepEquals(previewPosted["acceptedPlan"],
                    preview["acceptedPlan"]));
                Assert.True(JToken.DeepEquals(previewPosted["acceptedPlan"]["outputDelivery"],
                    previewPosted["outputDelivery"]));

                task.HandleWebRequest("commit", Request("commit",
                    "craft.route.matrix.commit." + materialStorageKind));
                int commitFid = (int)sent[sent.Count - 1]["callId"];
                task.HandleFlashResponse(CommitResponseFromPreview(commitFid, preview), null);
                JObject commitPosted = posted[posted.Count - 1];
                AssertOwnerTuple(commitPosted, "commit",
                    "craft.route.matrix.commit." + materialStorageKind);
                Assert.True((bool)commitPosted["success"]);
                Assert.True(JToken.DeepEquals(commitPosted["acceptedPlan"],
                    preview["acceptedPlan"]));
                Assert.True(JToken.DeepEquals(commitPosted["crafted"], preview["output"]));
                Assert.Equal("idle", task.WriteState);
            }
        }

        [Theory]
        [InlineData("missing")]
        [InlineData("mismatch")]
        [InlineData("extra")]
        public void StorageRouteContracts_RejectShortMalformedVariants(string variant)
        {
            var sent = new List<JObject>();
            var posted = new List<JObject>();
            using (var task = new CraftingTask(() => true, value =>
            {
                sent.Add(JObject.Parse(value.TrimEnd('\0')));
                return true;
            }))
            {
                task.SetPostToWeb(value => posted.Add(JObject.Parse(value)));
                JObject request = Request("preview", "craft.route.invalid." + variant);
                request["payload"]["craftCount"] = 1;
                task.HandleWebRequest("preview", request);
                JObject response = RoutedPreviewResponse(
                    (int)sent[sent.Count - 1]["callId"], "bag", "bag", "insert", 3, true);
                if (variant == "missing") ((JObject)response["outputDelivery"]).Remove("storageKind");
                else if (variant == "mismatch")
                    response["acceptedPlan"]["outputDelivery"]["mode"] = "merge";
                else response["outputDelivery"]["legacyRoute"] = true;

                task.HandleFlashResponse(response, null);
                Assert.Equal("malformed_response", (string)posted[posted.Count - 1]["error"]);
            }
        }

        [Fact]
        public void PreviewAndCommit_RequireExactStorageAndAcceptedPlanContracts()
        {
            var sent = new List<JObject>();
            var posted = new List<JObject>();
            using (var task = new CraftingTask(() => true, value =>
            {
                sent.Add(JObject.Parse(value.TrimEnd('\0')));
                return true;
            }))
            {
                task.SetPostToWeb(value => posted.Add(JObject.Parse(value)));

                task.HandleWebRequest("preview", Request("preview", "craft.route.missing"));
                JObject missingRoute = PreviewResponse((int)sent[sent.Count - 1]["callId"]);
                ((JObject)missingRoute["materials"][0]).Remove("storageKind");
                task.HandleFlashResponse(missingRoute, null);
                Assert.Equal("malformed_response", (string)posted[posted.Count - 1]["error"]);

                task.HandleWebRequest("preview", Request("preview", "craft.delivery.mismatch"));
                JObject mismatchedDelivery = PreviewResponse((int)sent[sent.Count - 1]["callId"]);
                mismatchedDelivery["outputDelivery"] = OutputDelivery(
                    false, "unavailable", "none", -1, 2);
                task.HandleFlashResponse(mismatchedDelivery, null);
                Assert.Equal("malformed_response", (string)posted[posted.Count - 1]["error"]);

                JObject acceptedRequest = Request("preview", "craft.plan.mismatch");
                acceptedRequest["payload"]["craftCount"] = 1;
                task.HandleWebRequest("preview", acceptedRequest);
                JObject mismatchedPlan = CommittablePreviewResponse(
                    (int)sent[sent.Count - 1]["callId"]);
                mismatchedPlan["acceptedPlan"]["materials"][0]["storageKind"] =
                    "material_collection";
                task.HandleFlashResponse(mismatchedPlan, null);
                Assert.Equal("malformed_response", (string)posted[posted.Count - 1]["error"]);

                PrimeCommitAuthority(task, sent);
                task.HandleWebRequest("commit", Request("commit", "craft.plan.commit-drift"));
                JObject commit = CommitResponse((int)sent[sent.Count - 1]["callId"]);
                commit["acceptedPlan"]["cost"]["money"] = 1;
                task.HandleFlashResponse(commit, null);
                JObject failed = posted[posted.Count - 1];
                Assert.Equal("malformed_response", (string)failed["error"]);
                Assert.True((bool)failed["requiresReconcile"]);
                Assert.Equal("needs_reconcile", task.WriteState);
            }
        }

        [Fact]
        public void MalformedCommitSuccess_EntersReconcile_ThenPreviewClearsIt()
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            using (var task = new CraftingTask(() => true, value => { sent.Add(JObject.Parse(value.TrimEnd('\0'))); return true; }))
            {
                task.SetPostToWeb(value => web.Add(JObject.Parse(value)));
                PrimeCommitAuthority(task, sent);
                web.Clear();
                task.HandleWebRequest("commit", Request("commit", "craft.commit.malformed"));
                int commitFid = (int)sent[sent.Count - 1]["callId"];
                task.HandleFlashResponse(new JObject
                {
                    ["task"] = "crafting_response", ["callId"] = commitFid, ["success"] = true, ["v"] = 1,
                    ["operation"] = "commit", ["category"] = "武器合成", ["recipeIndex"] = 3,
                    ["craftCount"] = 1,
                    ["crafted"] = new JObject { ["name"] = "秋月" },
                    ["balance"] = new JObject()
                }, null);
                Assert.Equal("needs_reconcile", task.WriteState);
                Assert.Equal("malformed_response", (string)web[0]["error"]);
                Assert.True((bool)web[0]["requiresReconcile"]);

                task.HandleWebRequest("preview", Request("preview", "craft.preview.reconcile"));
                int previewFid = (int)sent[sent.Count - 1]["callId"];
                JObject inconsistentPreview = PreviewResponse(previewFid);
                inconsistentPreview["batchEligible"] = false;
                task.HandleFlashResponse(inconsistentPreview, null);
                Assert.Equal("needs_reconcile", task.WriteState);
                Assert.Equal("malformed_response", (string)web[1]["error"]);

                task.HandleWebRequest("preview", Request("preview", "craft.preview.reconcile.valid"));
                previewFid = (int)sent[sent.Count - 1]["callId"];
                task.HandleFlashResponse(PreviewResponse(previewFid), null);
                Assert.Equal("idle", task.WriteState);
                Assert.True((bool)web[2]["success"]);
            }
        }

        [Fact]
        public void TimedOutCommit_BlocksAnotherWriteUntilPreviewReconciles()
        {
            var sent = new List<JObject>();
            var web = new List<JObject>();
            using (var task = new CraftingTask(() => true, value => { sent.Add(JObject.Parse(value.TrimEnd('\0'))); return true; }, 20))
            {
                task.SetPostToWeb(value => web.Add(JObject.Parse(value)));
                PrimeCommitAuthority(task, sent);
                web.Clear();
                task.HandleWebRequest("commit", Request("commit", "craft.timeout.1"));
                Assert.True(SpinWait.SpinUntil(() => web.Count > 0, 2000));
                AssertOwnerTuple(web[0], "commit", "craft.timeout.1");
                Assert.Equal("needs_reconcile", task.WriteState);
                Assert.True((bool)web[0]["requiresReconcile"]);

                task.HandleWebRequest("commit", Request("commit", "craft.timeout.2"));
                AssertOwnerTuple(web[1], "commit", "craft.timeout.2");
                Assert.Equal("reconcile_required", (string)web[1]["error"]);

                task.HandleWebRequest("preview", Request("preview", "craft.timeout.preview"));
                int previewFid = (int)sent[sent.Count - 1]["callId"];
                task.HandleFlashResponse(PreviewResponse(previewFid), null);
                Assert.Equal("idle", task.WriteState);
            }
        }

        [Theory]
        [InlineData("commit")]
        [InlineData("preview")]
        public void ClientNotReady_RejectsWithoutEnteringReconcile(string cmd)
        {
            int sends = 0;
            string posted = null;
            using (var task = new CraftingTask(() => false, _ => { sends++; return true; }))
            {
                task.SetPostToWeb(value => posted = value);

                task.HandleWebRequest(cmd, Request(cmd, "craft.not-ready." + cmd));

                JObject response = JObject.Parse(posted);
                AssertOwnerTuple(response, cmd, "craft.not-ready." + cmd);
                Assert.Equal(0, sends);
                Assert.Equal("disconnected", (string)response["error"]);
                Assert.Null(response["requiresReconcile"]);
                Assert.Equal("idle", task.WriteState);
            }
        }

        [Theory]
        [InlineData("commit", true)]
        [InlineData("preview", false)]
        public void SendFailure_RequiresReconcileOnlyForWrites(string cmd, bool isWrite)
        {
            string posted = null;
            var sent = new List<JObject>();
            using (var task = new CraftingTask(() => true, value =>
            {
                JObject command = JObject.Parse(value.TrimEnd('\0'));
                sent.Add(command);
                return isWrite && sent.Count == 1;
            }))
            {
                if (isWrite) PrimeCommitAuthority(task, sent);
                task.SetPostToWeb(value => posted = value);

                task.HandleWebRequest(cmd, Request(cmd, "craft.send-failure." + cmd));

                JObject response = JObject.Parse(posted);
                AssertOwnerTuple(response, cmd, "craft.send-failure." + cmd);
                Assert.Equal("disconnected", (string)response["error"]);
                Assert.Equal(isWrite, response.Value<bool?>("requiresReconcile") == true);
                Assert.Equal(isWrite ? "needs_reconcile" : "idle", task.WriteState);
            }
        }

        [Theory]
        [InlineData("commit", true)]
        [InlineData("preview", false)]
        public void Timeout_RequiresReconcileOnlyForWrites(string cmd, bool isWrite)
        {
            JObject posted = null;
            var sent = new List<JObject>();
            using (var responseSeen = new ManualResetEventSlim(false))
            using (var task = new CraftingTask(() => true, value =>
            {
                sent.Add(JObject.Parse(value.TrimEnd('\0')));
                return true;
            }, 20))
            {
                if (isWrite) PrimeCommitAuthority(task, sent);
                task.SetPostToWeb(value => { posted = JObject.Parse(value); responseSeen.Set(); });

                task.HandleWebRequest(cmd, Request(cmd, "craft.timeout.matrix." + cmd));
                Assert.True(responseSeen.Wait(TimeSpan.FromSeconds(2)), "Crafting timeout response was not posted");

                AssertOwnerTuple(posted, cmd, "craft.timeout.matrix." + cmd);
                Assert.Equal("timeout", (string)posted["error"]);
                Assert.Equal(isWrite, posted.Value<bool?>("requiresReconcile") == true);
                Assert.Equal(isWrite ? "needs_reconcile" : "idle", task.WriteState);
            }
        }

        [Fact]
        public void ActiveAndRecentDuplicateCallIds_DispatchAndRespondOnce()
        {
            var sent = new List<JObject>();
            var posted = new List<JObject>();
            using (var task = new CraftingTask(() => true, value => { sent.Add(JObject.Parse(value.TrimEnd('\0'))); return true; }))
            {
                task.SetPostToWeb(value => posted.Add(JObject.Parse(value)));
                JObject request = Request("preview", "craft.duplicate.1");

                task.HandleWebRequest("preview", request);
                task.HandleWebRequest("preview", request);
                Assert.Single(sent);

                task.HandleFlashResponse(PreviewResponse((int)sent[0]["callId"]), null);
                task.HandleWebRequest("preview", request);

                Assert.Single(sent);
                Assert.Single(posted);
            }
        }

        [Fact]
        public void DuplicateFlashResponse_PostsOnce()
        {
            var posted = new List<JObject>();
            string sent = null;
            using (var task = new CraftingTask(() => true, value => { sent = value; return true; }))
            {
                task.SetPostToWeb(value => posted.Add(JObject.Parse(value)));
                task.HandleWebRequest("preview", Request("preview", "craft.response.once"));
                int fid = (int)JObject.Parse(sent.TrimEnd('\0'))["callId"];

                task.HandleFlashResponse(PreviewResponse(fid), null);
                task.HandleFlashResponse(PreviewResponse(fid), null);

                Assert.Single(posted);
                Assert.True((bool)posted[0]["success"]);
            }
        }

        [Fact]
        public void CommitAdmission_RequiresExactSingleUsePreviewToken()
        {
            var sent = new List<JObject>();
            var posted = new List<JObject>();
            using (var task = new CraftingTask(
                () => true,
                value => { sent.Add(JObject.Parse(value.TrimEnd('\0'))); return true; }))
            {
                task.SetPostToWeb(value => posted.Add(JObject.Parse(value)));
                task.HandleWebRequest("commit", Request("commit", "craft.commit.no-preview"));
                Assert.Empty(sent);
                Assert.Equal("stale_state", (string)posted[posted.Count - 1]["error"]);

                PrimeCommitAuthority(task, sent);
                JObject wrongToken = Request("commit", "craft.commit.wrong-token");
                wrongToken["payload"]["expectedCraftToken"] = "craft.10.2";
                int sendsBeforeWrongToken = sent.Count;
                task.HandleWebRequest("commit", wrongToken);
                Assert.Equal(sendsBeforeWrongToken, sent.Count);
                Assert.Equal("stale_state", (string)posted[posted.Count - 1]["error"]);

                task.HandleWebRequest("commit", Request("commit", "craft.commit.exact"));
                Assert.Equal(sendsBeforeWrongToken + 1, sent.Count);
                int commitFid = (int)sent[sent.Count - 1]["callId"];
                task.HandleFlashResponse(CommitResponse(commitFid), null);
                Assert.True((bool)posted[posted.Count - 1]["success"]);

                task.HandleWebRequest("commit", Request("commit", "craft.commit.replay"));
                Assert.Equal(sendsBeforeWrongToken + 1, sent.Count);
                Assert.Equal("stale_state", (string)posted[posted.Count - 1]["error"]);
            }
        }

        [Theory]
        [InlineData("recipe")]
        [InlineData("count")]
        [InlineData("identity")]
        public void CommitSuccess_MustMatchPreviewPostcondition(string drift)
        {
            var sent = new List<JObject>();
            JObject posted = null;
            using (var task = new CraftingTask(
                () => true,
                value => { sent.Add(JObject.Parse(value.TrimEnd('\0'))); return true; }))
            {
                task.SetPostToWeb(value => posted = JObject.Parse(value));
                PrimeCommitAuthority(task, sent);
                task.HandleWebRequest("commit", Request("commit", "craft.commit.drift." + drift));
                JObject response = CommitResponse((int)sent[sent.Count - 1]["callId"]);
                if (drift == "recipe") response["recipeIndex"] = 4;
                else if (drift == "count") response["craftCount"] = 2;
                else response["crafted"]["icon"] = "环式棱栅折射阵列";
                task.HandleFlashResponse(response, null);
                Assert.False((bool)posted["success"]);
                Assert.Equal("malformed_response", (string)posted["error"]);
                Assert.True((bool)posted["requiresReconcile"]);
                Assert.Equal("needs_reconcile", task.WriteState);
            }
        }

        [Fact]
        public void PreviewNestedCraftingSources_RequireExactUniqueOccurrenceIdentity()
        {
            var sent = new List<JObject>();
            var posted = new List<JObject>();
            using (var task = new CraftingTask(
                () => true,
                value => { sent.Add(JObject.Parse(value.TrimEnd('\0'))); return true; }))
            {
                task.SetPostToWeb(value => posted.Add(JObject.Parse(value)));
                task.HandleWebRequest("preview", Request("preview", "craft.nested.valid"));
                JObject valid = PreviewResponse((int)sent[sent.Count - 1]["callId"]);
                valid["materials"][0]["craftingSources"] = new JArray(
                    new JObject
                    {
                        ["category"] = "武器合成", ["recipeIndex"] = 1,
                        ["recipeId"] = "craft.weapon.nested", ["title"] = "嵌套图纸"
                    },
                    new JObject
                    {
                        ["category"] = "基础防具", ["recipeIndex"] = 2,
                        ["recipeId"] = "craft.armor.nested", ["title"] = "替代图纸"
                    });
                task.HandleFlashResponse(valid, null);
                Assert.True(posted[posted.Count - 1].Value<bool>("success"));

                Action<JObject>[] mutations =
                {
                    value => value["materials"][0]["craftingSources"][0]["category"] = "未知分类",
                    value => value["materials"][0]["craftingSources"][0]["recipeId"] = "craft.Weapon.bad",
                    value => value["materials"][0]["craftingSources"][1]["recipeId"] = "craft.weapon.nested",
                    value => value["materials"][0]["craftingSources"][0]["legacyProduct"] = "嵌套产物",
                    value => value["materials"][0]["procurement"]["equippedOwned"] = 1,
                    value => value["materials"][0]["procurement"]["battleBoxMaxEnhancement"] = 1,
                    value => { ((JObject)value["materials"][0]["procurement"])
                        .Remove("battleBoxOwned"); }
                };
                for (int index = 0; index < mutations.Length; index++)
                {
                    task.HandleWebRequest("preview", Request("preview", "craft.nested.bad." + index));
                    JObject malformed = (JObject)valid.DeepClone();
                    malformed["callId"] = sent[sent.Count - 1]["callId"];
                    mutations[index](malformed);
                    task.HandleFlashResponse(malformed, null);
                    Assert.Equal("malformed_response",
                        posted[posted.Count - 1].Value<string>("error"));
                }
            }
        }

        [Fact]
        public void IdentityTriples_ArePreservedWhileNearShapeExtraAndCoercionFailClosed()
        {
            var sent = new List<JObject>();
            var posted = new List<JObject>();
            using (var task = new CraftingTask(
                () => true,
                value => { sent.Add(JObject.Parse(value.TrimEnd('\0'))); return true; }))
            {
                task.SetPostToWeb(value => posted.Add(JObject.Parse(value)));

                task.HandleWebRequest("snapshot", Request("snapshot", "craft.identity.valid"));
                JObject valid = SnapshotResponse((int)sent[sent.Count - 1]["callId"]);
                task.HandleFlashResponse(valid, null);
                JObject accepted = posted[posted.Count - 1];
                Assert.True((bool)accepted["success"]);
                Assert.Equal("光棱射线弹-强化", (string)accepted["recipes"][0]["output"]["name"]);
                Assert.Equal("棱镜折射阵列", (string)accepted["recipes"][0]["output"]["displayName"]);
                Assert.Equal("全光谱棱镜阵列", (string)accepted["recipes"][0]["output"]["icon"]);

                string[] malformedCases = { "missing-display", "icon-coercion",
                    "legacy-near-shape", "whitespace-display", "whitespace-icon",
                    "wrapped-undefined-icon" };
                foreach (string malformedCase in malformedCases)
                {
                    task.HandleWebRequest(
                        "snapshot", Request("snapshot", "craft.identity." + malformedCase));
                    JObject malformed = SnapshotResponse((int)sent[sent.Count - 1]["callId"]);
                    JObject output = (JObject)malformed["recipes"][0]["output"];
                    if (malformedCase == "missing-display") output.Remove("displayName");
                    else if (malformedCase == "icon-coercion") output["icon"] = 7;
                    else if (malformedCase == "legacy-near-shape")
                        output["displayname"] = "不得接受的旧字段";
                    else if (malformedCase == "whitespace-display") output["displayName"] = "   ";
                    else if (malformedCase == "whitespace-icon") output["icon"] = "   ";
                    else output["icon"] = " Undefined ";
                    task.HandleFlashResponse(malformed, null);
                    JObject rejected = posted[posted.Count - 1];
                    Assert.False((bool)rejected["success"]);
                    Assert.Equal("malformed_response", (string)rejected["error"]);
                    Assert.Null(rejected["recipes"]);
                }
            }
        }

        [Fact]
        public void SuccessResponses_BindFrozenSelectorsAndSanitizeLegacyTooltipBoundary()
        {
            var sent = new List<JObject>();
            var posted = new List<JObject>();
            using (var task = new CraftingTask(
                () => true,
                value => { sent.Add(JObject.Parse(value.TrimEnd('\0'))); return true; }))
            {
                task.SetPostToWeb(value => posted.Add(JObject.Parse(value)));

                task.HandleWebRequest("snapshot", Request("snapshot", "craft.selector.snapshot"));
                JObject snapshot = SnapshotResponse((int)sent[sent.Count - 1]["callId"]);
                snapshot["category"] = "属性武器";
                task.HandleFlashResponse(snapshot, null);
                Assert.Equal("malformed_response", (string)posted[posted.Count - 1]["error"]);

                task.HandleWebRequest("preview", Request("preview", "craft.selector.preview"));
                JObject preview = PreviewResponse((int)sent[sent.Count - 1]["callId"]);
                preview["recipeIndex"] = 4;
                task.HandleFlashResponse(preview, null);
                Assert.Equal("malformed_response", (string)posted[posted.Count - 1]["error"]);

                JObject detailRequest = Request("materialDetail", "craft.selector.material");
                detailRequest["payload"]["itemName"] = "光棱射线弹-强化";
                task.HandleWebRequest("materialDetail", detailRequest);
                JObject detail = MaterialDetailResponse((int)sent[sent.Count - 1]["callId"]);
                detail["material"]["name"] = "光谱射线弹";
                detail["material"]["displayName"] = "色散射线弹";
                detail["material"]["icon"] = "棱栅射线弹";
                task.HandleFlashResponse(detail, null);
                Assert.Equal("malformed_response", (string)posted[posted.Count - 1]["error"]);

                JObject tooltipRequest = Request("tooltip", "craft.selector.tooltip");
                tooltipRequest["payload"]["itemName"] = "光谱射线弹-强化";
                task.HandleWebRequest("tooltip", tooltipRequest);
                task.HandleFlashResponse(
                    TooltipResponse((int)sent[sent.Count - 1]["callId"],
                        "光谱射线弹-强化", "全谱色散引擎"), null);
                JObject tooltip = posted[posted.Count - 1];
                Assert.True((bool)tooltip["success"]);
                Assert.Equal("光谱射线弹-强化", (string)tooltip["itemName"]);
                Assert.Equal("全谱色散引擎", (string)tooltip["displayName"]);
                Assert.Null(tooltip["displayname"]);
                Assert.Null(tooltip["task"]);
            }
        }

        [Fact]
        public void RequestSelectors_RejectExtraNearShapeAndTypeCoercionBeforeFlash()
        {
            var posted = new List<JObject>();
            int sends = 0;
            using (var task = new CraftingTask(() => true, _ => { sends++; return true; }))
            {
                task.SetPostToWeb(value => posted.Add(JObject.Parse(value)));
                JObject extra = Request("preview", "craft.request.extra");
                extra["payload"]["displayName"] = "伪 selector";
                task.HandleWebRequest("preview", extra);

                JObject near = Request("materialDetail", "craft.request.near");
                ((JObject)near["payload"]).Remove("itemName");
                near["payload"]["itemname"] = "不锈钢材";
                task.HandleWebRequest("materialDetail", near);

                JObject coerced = Request("preview", "craft.request.coercion");
                coerced["payload"]["recipeIndex"] = "3";
                task.HandleWebRequest("preview", coerced);

                JObject extraPlan = Request("setPlan", "craft.request.plan-extra");
                extraPlan["payload"]["displayName"] = "伪字段";
                task.HandleWebRequest("setPlan", extraPlan);

                JObject overflowingPlan = Request("setPlan", "craft.request.plan-overflow");
                overflowingPlan["payload"]["expectedRevision"] = 9007199254740991L;
                task.HandleWebRequest("setPlan", overflowingPlan);

                Assert.Equal(0, sends);
                Assert.Equal(5, posted.Count);
                foreach (JObject response in posted)
                    Assert.Equal("invalid_payload", (string)response["error"]);
            }
        }

        [Fact]
        public void InvalidOwnerTuple_IsDroppedBeforePendingOrFlash()
        {
            int sends = 0;
            var posted = new List<JObject>();
            using (var task = new CraftingTask(() => true, _ => { sends++; return true; }))
            {
                task.SetPostToWeb(value => posted.Add(JObject.Parse(value)));

                JObject missingInstance = Request("preview", "craft.owner.missing");
                missingInstance.Remove("panelInstanceId");
                task.HandleWebRequest("preview", missingInstance);

                JObject malformedInstance = Request(
                    "preview", "craft.owner.malformed", "panel/crafting/malformed");
                task.HandleWebRequest("preview", malformedInstance);

                JObject wrongPanel = Request("preview", "craft.owner.wrong-panel");
                wrongPanel["panel"] = "npcshop";
                task.HandleWebRequest("preview", wrongPanel);

                Assert.Equal(0, sends);
                Assert.Empty(posted);
            }
        }

        [Fact]
        public void LocalValidationErrors_EchoExactOriginalOwnerTuple()
        {
            int sends = 0;
            var posted = new List<JObject>();
            using (var task = new CraftingTask(() => true, _ => { sends++; return true; }))
            {
                task.SetPostToWeb(value => posted.Add(JObject.Parse(value)));

                task.HandleWebRequest("preview", Request("preview", "craft/bad-call"));
                AssertOwnerTuple(posted[0], "preview", "craft/bad-call");
                Assert.Equal("invalid_call_id", (string)posted[0]["error"]);

                JObject wrongDomain = Request("preview", "craft.local.domain");
                wrongDomain["domain"] = "npcshop";
                task.HandleWebRequest("preview", wrongDomain);
                AssertOwnerTuple(posted[1], "preview", "craft.local.domain");
                Assert.Equal("unsupported_domain", (string)posted[1]["error"]);

                task.HandleWebRequest("unknown", Request("unknown", "craft.local.command"));
                AssertOwnerTuple(posted[2], "unknown", "craft.local.command");
                Assert.Equal("unsupported_cmd", (string)posted[2]["error"]);

                JObject invalidPayload = Request("preview", "craft.local.payload");
                invalidPayload["payload"]["category"] = "不存在";
                task.HandleWebRequest("preview", invalidPayload);
                AssertOwnerTuple(posted[3], "preview", "craft.local.payload");
                Assert.Equal("invalid_payload", (string)posted[3]["error"]);

                Assert.Equal(0, sends);
            }
        }

        [Fact]
        public void ClearedInstanceA_LateResponseCannotReachSameNameInstanceB()
        {
            const string instanceA = "panel.crafting.same-name.A";
            const string instanceB = "panel.crafting.same-name.B";
            var sent = new List<JObject>();
            var posted = new List<JObject>();
            using (var task = new CraftingTask(
                () => true,
                value => { sent.Add(JObject.Parse(value.TrimEnd('\0'))); return true; }))
            {
                task.SetPostToWeb(value => posted.Add(JObject.Parse(value)));

                task.HandleWebRequest(
                    "preview", Request("preview", "craft.same-name.A", instanceA));
                int fidA = (int)sent[0]["callId"];
                task.ClearPending();

                task.HandleWebRequest(
                    "preview", Request("preview", "craft.same-name.B", instanceB));
                int fidB = (int)sent[1]["callId"];
                Assert.NotEqual(fidA, fidB);

                task.HandleFlashResponse(PreviewResponse(fidA), null);
                Assert.Empty(posted);

                JObject responseB = PreviewResponse(fidB);
                responseB["domain"] = "npcshop";
                responseB["panel"] = "npcshop";
                responseB["panelInstanceId"] = instanceA;
                responseB["cmd"] = "commit";
                task.HandleFlashResponse(responseB, null);

                Assert.Single(posted);
                AssertOwnerTuple(posted[0], "preview", "craft.same-name.B", instanceB);
                Assert.False((bool)posted[0]["success"]);
                Assert.Equal("malformed_response", (string)posted[0]["error"]);
            }
        }

        [Fact]
        public void SupersededPreviewCannotMintCommitAuthorityForANewerIntent()
        {
            var sent = new List<JObject>();
            var posted = new List<JObject>();
            using (var task = new CraftingTask(() => true, value =>
            {
                sent.Add(JObject.Parse(value.TrimEnd('\0')));
                return true;
            }))
            {
                task.SetPostToWeb(value => posted.Add(JObject.Parse(value)));
                JObject oldRequest = Request("preview", "craft.epoch.old-read");
                oldRequest["payload"]["craftCount"] = 1;
                task.HandleWebRequest("preview", oldRequest);
                int oldPreviewFid = (int)sent[sent.Count - 1]["callId"];

                JObject newRequest = Request("preview", "craft.epoch.new-read");
                newRequest["payload"]["craftCount"] = 1;
                task.HandleWebRequest("preview", newRequest);
                int newPreviewFid = (int)sent[sent.Count - 1]["callId"];

                task.HandleFlashResponse(CommittablePreviewResponse(oldPreviewFid), null);
                int sendsBeforeStaleCommit = sent.Count;
                task.HandleWebRequest("commit", Request("commit", "craft.epoch.stale-commit"));
                Assert.Equal(sendsBeforeStaleCommit, sent.Count);
                Assert.Equal("stale_state", (string)posted[posted.Count - 1]["error"]);

                task.HandleFlashResponse(CommittablePreviewResponse(newPreviewFid), null);
                task.HandleWebRequest("commit", Request("commit", "craft.epoch.current-commit"));
                Assert.Equal(sendsBeforeStaleCommit + 1, sent.Count);
            }
        }

        [Fact]
        public void TimedOutCommitRequiresFreshPreviewBeforeAnotherWrite()
        {
            var sent = new List<JObject>();
            using (var task = new CraftingTask(() => true, value =>
            {
                sent.Add(JObject.Parse(value.TrimEnd('\0')));
                return true;
            }, 20))
            {
                PrimeCommitAuthority(task, sent);
                task.HandleWebRequest("commit", Request("commit", "craft.epoch.timeout.write"));
                Assert.True(SpinWait.SpinUntil(() => task.WriteState == "needs_reconcile", 2000));

                task.HandleWebRequest("preview", Request("preview", "craft.epoch.timeout.new-read"));
                int newPreviewFid = (int)sent[sent.Count - 1]["callId"];
                task.HandleFlashResponse(PreviewResponse(newPreviewFid), null);
                Assert.Equal("idle", task.WriteState);

                int sendsBeforeRejected = sent.Count;
                task.HandleWebRequest("commit", Request("commit", "craft.epoch.timeout.no-authority"));
                Assert.Equal(sendsBeforeRejected, sent.Count);
            }
        }

        [Theory]
        [InlineData(false)]
        [InlineData(true)]
        public void ClearOrDispose_DrainsWriteAndLateResponseCannotReviveIt(bool dispose)
        {
            var posted = new List<JObject>();
            var sent = new List<JObject>();
            var task = new CraftingTask(() => true, value =>
            {
                sent.Add(JObject.Parse(value.TrimEnd('\0')));
                return true;
            });
            try
            {
                task.SetPostToWeb(value => posted.Add(JObject.Parse(value)));
                PrimeCommitAuthority(task, sent);
                posted.Clear();
                task.HandleWebRequest("commit", Request("commit", "craft.drain." + dispose));
                int fid = (int)sent[sent.Count - 1]["callId"];

                if (dispose) task.Dispose();
                else task.ClearPending();
                task.HandleFlashResponse(new JObject
                {
                    ["task"] = "crafting_response", ["callId"] = fid, ["success"] = false, ["error"] = "busy"
                }, null);

                Assert.Equal("needs_reconcile", task.WriteState);
                Assert.Empty(posted);
            }
            finally
            {
                task.Dispose();
            }
        }

        [Fact]
        public void DomainRouting_RecognizesCraftingAndCloseStillWins()
        {
            Assert.Equal(WebOverlayForm.PanelDomainRoute.Crafting,
                WebOverlayForm.ResolvePanelDomainRoute("preview", "crafting"));
            Assert.Equal(WebOverlayForm.PanelDomainRoute.Close,
                WebOverlayForm.ResolvePanelDomainRoute("close", "crafting"));
        }

        [Fact]
        public void RecipeShopLease_UsesLatestPreviewSourceWithoutMaterialCatalogSession()
        {
            var sent = new List<JObject>();
            using var task = new CraftingTask(
                () => true,
                value => { sent.Add(JObject.Parse(value.TrimEnd('\0'))); return true; });
            task.BindMaterialShopNavigationOwner("crafting", DefaultPanelInstanceId);
            task.HandleWebRequest("preview", Request("preview", "craft.recipe.route.preview"));
            int fid = Assert.Single(sent).Value<int>("callId");
            task.HandleFlashResponse(
                RecipeNavigationPreviewResponse(fid, "战术握把"), null);

            Assert.False(task.TryAcquireRecipeShopNavigationLease(
                "crafting", DefaultPanelInstanceId, "recipe.route.wrong",
                "武器合成", 3, "战术握把", "错误商人", 57,
                false, null, null, out _));
            Assert.True(task.TryAcquireRecipeShopNavigationLease(
                "crafting", DefaultPanelInstanceId, "recipe.route.npc",
                "武器合成", 3, "战术握把", "迷之盔甲君", 57,
                false, null, null, out var npcWitness));
            Assert.True(task.IsMaterialShopNavigationLeaseCurrent(npcWitness));
            Assert.True(task.ReleaseMaterialShopNavigationLease(npcWitness));

            Assert.True(task.TryAcquireRecipeShopNavigationLease(
                "crafting", DefaultPanelInstanceId, "recipe.route.kshop",
                "武器合成", 3, "战术握把", null, 7,
                true, "k-material-7", "材料", out var kshopWitness));
            Assert.True(task.IsMaterialShopNavigationLeaseCurrent(kshopWitness));
            task.BindMaterialShopNavigationOwner("crafting", "panel.crafting.instance.2");
            Assert.False(task.IsMaterialShopNavigationLeaseCurrent(kshopWitness));
        }

        private static JObject PreviewResponse(int fid)
        {
            return new JObject
            {
                ["task"] = "crafting_response", ["callId"] = fid, ["success"] = true, ["v"] = 1,
                ["category"] = "武器合成", ["recipeIndex"] = 3,
                ["craftCount"] = 2, ["batchEligible"] = true, ["maxCraftCount"] = 4,
                ["balance"] = new JObject { ["money"] = 10, ["kpoints"] = 2 },
                ["skills"] = new JObject
                {
                    ["reverseLevel"] = 0, ["smithEnabled"] = false, ["smithLevel"] = 0
                },
                ["output"] = ProjectedItem(
                    "光谱射线弹", "色散射线弹", "棱栅射线弹", false, true, 2),
                ["materials"] = new JArray
                {
                    Requirement("光棱射线弹-强化", "棱镜折射阵列", "全光谱棱镜阵列")
                },
                ["cost"] = new JObject { ["money"] = 0, ["kpoints"] = 0 },
                ["levelAllowed"] = true, ["enoughMaterials"] = false,
                ["enoughMoney"] = true, ["enoughKpoints"] = true, ["enoughSpace"] = true,
                ["canCommit"] = false, ["blockingError"] = "material_missing",
                ["outputDelivery"] = OutputDelivery(true, "bag", "insert", 1, 2)
            };
        }

        private static JObject CommittablePreviewResponse(int fid)
        {
            JObject response = PreviewResponse(fid);
            response["craftCount"] = 1;
            response["batchEligible"] = false;
            response["maxCraftCount"] = 1;
            response["output"] = ProjectedItem(
                "光棱射线弹-强化", "棱镜折射阵列", "全光谱棱镜阵列", true, true);
            response["materials"][0]["owned"] = 2;
            response["materials"][0]["enough"] = true;
            response["enoughMaterials"] = true;
            response["canCommit"] = true;
            response["blockingError"] = "";
            response["outputDelivery"] = OutputDelivery(true, "bag", "insert", 1, 1);
            response["craftToken"] = "craft.10.1";
            response["acceptedPlan"] = AcceptedPlanFromPreview(response);
            return response;
        }

        private static JObject RoutedPreviewResponse(int fid, string materialStorageKind,
            string deliveryStorageKind, string deliveryMode, int physicalSlot, bool committable)
        {
            JObject response = committable
                ? CommittablePreviewResponse(fid)
                : PreviewResponse(fid);
            response["craftCount"] = 1;
            response["batchEligible"] = false;
            response["maxCraftCount"] = 1;
            response["materials"][0]["storageKind"] = materialStorageKind;
            if (deliveryStorageKind != "bag" || deliveryMode == "merge")
            {
                response["output"] = ProjectedItem(
                    "测试药剂", "测试药剂", "测试药剂", false, true, 1);
            }
            response["outputDelivery"] = OutputDelivery(committable, deliveryStorageKind,
                deliveryMode, physicalSlot, (int)response["output"]["quantity"]);
            response["enoughSpace"] = committable;
            response["enoughMaterials"] = committable;
            response["canCommit"] = committable;
            response["blockingError"] = committable ? "" : "material_missing";
            if (committable) response["acceptedPlan"] = AcceptedPlanFromPreview(response);
            else
            {
                ((JObject)response).Remove("craftToken");
                ((JObject)response).Remove("acceptedPlan");
            }
            return response;
        }

        private static void PrimeCommitAuthority(
            CraftingTask task, List<JObject> sent)
        {
            JObject request = Request(
                "preview", "craft.prime." + Guid.NewGuid().ToString("N"));
            request["payload"]["craftCount"] = 1;
            task.HandleWebRequest("preview", request);
            int fid = (int)sent[sent.Count - 1]["callId"];
            task.HandleFlashResponse(CommittablePreviewResponse(fid), null);
        }

        private static JObject CommitResponse(int fid)
        {
            return CommitResponseFromPreview(fid, CommittablePreviewResponse(-1));
        }

        private static JObject CommitResponseFromPreview(int fid, JObject preview)
        {
            return new JObject
            {
                ["task"] = "crafting_response", ["callId"] = fid,
                ["success"] = true, ["v"] = 1, ["operation"] = "commit",
                ["category"] = preview["category"].DeepClone(),
                ["recipeIndex"] = preview["recipeIndex"].DeepClone(),
                ["craftCount"] = preview["craftCount"].DeepClone(),
                ["crafted"] = preview["output"].DeepClone(),
                ["acceptedPlan"] = preview["acceptedPlan"].DeepClone(),
                ["outputReceipt"] = OutputReceiptFromPlan(
                    preview["acceptedPlan"] as JObject),
                ["balance"] = new JObject { ["money"] = 10, ["kpoints"] = 2 },
                ["procurement"] = CommitProcurementState()
            };
        }

        private static JObject SnapshotResponse(int fid)
        {
            return new JObject
            {
                ["task"] = "crafting_response", ["callId"] = fid, ["success"] = true, ["v"] = 1,
                ["category"] = "武器合成", ["gender"] = "男",
                ["balance"] = new JObject { ["money"] = 10, ["kpoints"] = 2 },
                ["skills"] = new JObject { ["reverseLevel"] = 0, ["smithEnabled"] = false, ["smithLevel"] = 0 },
                ["procurement"] = PlanSummary(),
                ["note"] = "改装后的装备默认强化等级为 1",
                ["recipes"] = new JArray
                {
                    new JObject
                    {
                        ["recipeId"] = "craft.weapon.004", ["recipeIndex"] = 3,
                        ["title"] = "秋月图纸", ["batchEligible"] = false,
                        ["canCraftOne"] = true, ["availability"] = "ready", ["materialCount"] = 2,
                        ["owned"] = OwnedSummary(1), ["plannedCrafts"] = 0,
                        ["output"] = ProjectedItem(
                            "光棱射线弹-强化", "棱镜折射阵列", "全光谱棱镜阵列", true, false),
                        ["baseCost"] = new JObject { ["money"] = 10, ["kpoints"] = 2 }
                    }
                }
            };
        }

        private static JObject MaterialsResponse(int fid)
        {
            return new JObject
            {
                ["task"] = "crafting_response", ["callId"] = fid,
                ["success"] = true, ["v"] = 1, ["view"] = "materials",
                ["materials"] = new JArray
                {
                    new JObject
                    {
                        ["name"] = "不锈钢材", ["displayName"] = "不锈钢材",
                        ["icon"] = "不锈钢材", ["owned"] = 3,
                        ["sourceCount"] = 2, ["useCount"] = 1,
                        ["hasSourceSummary"] = true
                    }
                }
            };
        }

        private static JObject MaterialDetailResponse(int fid)
        {
            return new JObject
            {
                ["task"] = "crafting_response", ["callId"] = fid,
                ["success"] = true, ["v"] = 1, ["view"] = "materials",
                ["material"] = new JObject
                {
                    ["name"] = "不锈钢材", ["displayName"] = "不锈钢材",
                    ["icon"] = "不锈钢材", ["description"] = "合成材料",
                    ["owned"] = 3, ["sourceSummary"] = "【掉落单位】测试敌人\n【掉落关卡】测试关卡"
                },
                ["sources"] = new JArray
                {
                    new JObject
                    {
                        ["kind"] = "enemy", ["enemyType"] = "enemy.internal",
                        ["displayName"] = "敌人展示名", ["probability"] = 0.1,
                        ["minLevel"] = 0, ["maxLevel"] = 0
                    },
                    new JObject
                    {
                        ["kind"] = "quest", ["questId"] = "quest.internal",
                        ["title"] = "任务展示名", ["quantity"] = 1
                    }
                },
                ["uses"] = new JArray
                {
                    new JObject
                    {
                        ["name"] = "秋月", ["displayName"] = "秋月",
                        ["icon"] = "秋月", ["itemKind"] = "equipment",
                        ["category"] = "武器合成", ["required"] = 2
                    }
                }
            };
        }

        private static JObject TooltipResponse(
            int fid, string itemName, string displayName)
        {
            return new JObject
            {
                ["task"] = "crafting_response", ["callId"] = fid,
                ["success"] = true, ["v"] = 1,
                ["itemName"] = itemName, ["displayname"] = displayName,
                ["descHTML"] = "<p>说明</p>", ["introHTML"] = "<b>简介</b>"
            };
        }

        private static JObject ProjectedItem(
            string name, string displayName, string icon, bool equipment,
            bool withRequiredLevel, int value = 1)
        {
            var item = new JObject
            {
                ["name"] = name,
                ["displayName"] = displayName,
                ["icon"] = icon,
                ["itemKind"] = equipment ? "equipment" : "stack",
                ["value"] = value,
                ["quantity"] = equipment ? 1 : value,
                ["enhancementLevel"] = equipment ? value : 0,
                ["majorType"] = equipment ? "武器" : "收集品",
                ["use"] = equipment ? "枪械" : "材料",
                ["actionType"] = equipment ? "长枪" : "",
                ["weaponType"] = equipment ? "突击步枪" : "",
                ["setId"] = "",
                ["setName"] = "",
                ["setOrder"] = 0
            };
            if (withRequiredLevel) item["requiredLevel"] = equipment ? 12 : 1;
            return item;
        }

        private static JObject Requirement(string name, string displayName, string icon,
            string storageKind = "bag")
        {
            return new JObject
            {
                ["name"] = name, ["displayName"] = displayName, ["icon"] = icon,
                ["itemKind"] = "stack", ["required"] = 2, ["owned"] = 1,
                ["maxEnhancement"] = 0, ["isQuantity"] = true, ["tier"] = "",
                ["consumed"] = true, ["enough"] = false, ["storageKind"] = storageKind,
                ["craftingSources"] = new JArray(),
                ["procurement"] = Demand(name)
            };
        }

        internal static JObject RecipeNavigationPreviewResponse(
            int fid, string materialName)
        {
            JObject response = PreviewResponse(fid);
            JObject material = (JObject)response["materials"][0];
            material["name"] = materialName;
            material["displayName"] = materialName;
            material["icon"] = materialName;
            material["itemKind"] = "equipment";
            material["required"] = 1;
            material["owned"] = 0;
            material["maxEnhancement"] = 0;
            material["isQuantity"] = false;
            material["storageKind"] = "unavailable";
            JObject demand = Demand(materialName);
            demand["required"] = 1;
            demand["usableOwned"] = 0;
            demand["totalOwned"] = 0;
            demand["craftRequired"] = 1;
            demand["reasons"][0]["required"] = 1;
            demand["sources"] = new JArray(
                new JObject
                {
                    ["kind"] = "npcshop",
                    ["shopId"] = "迷之盔甲君",
                    ["catalogIndex"] = 57,
                    ["label"] = "迷之盔甲君"
                },
                new JObject
                {
                    ["kind"] = "kshop",
                    ["catalogIndex"] = 7,
                    ["entryId"] = "k-material-7",
                    ["category"] = "材料",
                    ["label"] = "材料"
                });
            material["procurement"] = demand;
            return response;
        }

        [Fact]
        public void SetPlan_UsesStableIdentityAndOccThenRequiresExactMutationReceipt()
        {
            var sent = new List<JObject>();
            string web = null;
            using (var task = new CraftingTask(
                () => true,
                value => { sent.Add(JObject.Parse(value.TrimEnd('\0'))); return true; }))
            {
                task.SetPostToWeb(value => web = value);
                task.HandleWebRequest("setPlan", Request("setPlan", "craft.plan.ok"));

                JObject command = Assert.Single(sent);
                Assert.Equal("craftingPlanSet", command.Value<string>("action"));
                Assert.Equal("craft.weapon.004", command.Value<string>("recipeId"));
                Assert.Equal(1, command.Value<int>("plannedCrafts"));
                Assert.Equal(0, command.Value<long>("expectedRevision"));
                Assert.Equal("write_pending", task.WriteState);

                task.HandleFlashResponse(SetPlanResponse(command.Value<int>("callId")), null);
                JObject accepted = JObject.Parse(web);
                AssertOwnerTuple(accepted, "setPlan", "craft.plan.ok");
                Assert.True(accepted.Value<bool>("success"));
                Assert.Equal(1, accepted.Value<long>("revision"));
                Assert.Equal("craft.weapon.004", accepted.Value<string>("recipeId"));
                Assert.Equal(1, accepted.Value<int>("plannedCrafts"));
                Assert.Equal("idle", task.WriteState);

                JObject second = Request("setPlan", "craft.plan.bad-revision");
                second["payload"]["expectedRevision"] = 1;
                second["payload"]["plannedCrafts"] = 0;
                task.HandleWebRequest("setPlan", second);
                JObject malformed = SetPlanResponse(sent[sent.Count - 1].Value<int>("callId"));
                malformed["revision"] = 7;
                malformed["plannedCrafts"] = 0;
                task.HandleFlashResponse(malformed, null);

                JObject rejected = JObject.Parse(web);
                Assert.Equal("malformed_response", rejected.Value<string>("error"));
                Assert.True(rejected.Value<bool>("requiresReconcile"));
                Assert.Equal("needs_reconcile", task.WriteState);
            }
        }

        private static JObject PlanSummary()
        {
            return new JObject
            {
                ["revision"] = 0,
                ["directShopNavigation"] = false
            };
        }

        private static JObject CommitProcurementState()
        {
            return new JObject
            {
                ["revision"] = 0,
                ["plannedCrafts"] = 0,
                ["changed"] = false
            };
        }

        private static JObject SetPlanResponse(int fid)
        {
            return new JObject
            {
                ["task"] = "crafting_response",
                ["callId"] = fid,
                ["success"] = true,
                ["v"] = 1,
                ["revision"] = 1,
                ["recipeId"] = "craft.weapon.004",
                ["plannedCrafts"] = 1
            };
        }

        private static JObject OwnedSummary(int bag)
        {
            return new JObject
            {
                ["bag"] = bag,
                ["drug"] = 0,
                ["equipped"] = 0,
                ["battleBox"] = 0,
                ["material"] = 0,
                ["information"] = 0,
                ["usable"] = bag,
                ["total"] = bag,
                ["usableMaxEnhancement"] = bag > 0 ? 1 : 0,
                ["totalMaxEnhancement"] = bag > 0 ? 1 : 0
            };
        }

        private static JObject Demand(string itemName)
        {
            return new JObject
            {
                ["itemName"] = itemName,
                ["required"] = 2,
                ["requiredEnhancement"] = 0,
                ["usableOwned"] = 1,
                ["equippedOwned"] = 0,
                ["battleBoxOwned"] = 0,
                ["totalOwned"] = 1,
                ["usableMaxEnhancement"] = 0,
                ["equippedMaxEnhancement"] = 0,
                ["battleBoxMaxEnhancement"] = 0,
                ["totalMaxEnhancement"] = 0,
                ["obtainMissing"] = 1,
                ["relocateMissing"] = 0,
                ["needsEnhancement"] = false,
                ["craftRequired"] = 2,
                ["taskRequired"] = 0,
                ["plannedRecipeCount"] = 1,
                ["activeTaskCount"] = 0,
                ["reasons"] = new JArray(new JObject
                {
                    ["kind"] = "craft",
                    ["sourceId"] = "craft.weapon.004",
                    ["label"] = "秋月图纸",
                    ["required"] = 2,
                    ["mode"] = "consume"
                }),
                ["sources"] = new JArray()
            };
        }

        private static JObject OutputDelivery(
            bool available, string storageKind, string mode, int physicalSlot, int quantity)
        {
            return new JObject
            {
                ["available"] = available, ["storageKind"] = storageKind, ["mode"] = mode,
                ["physicalSlot"] = physicalSlot, ["quantity"] = quantity
            };
        }

        private static JObject AcceptedPlanFromPreview(JObject preview)
        {
            return new JObject
            {
                ["category"] = preview["category"].DeepClone(),
                ["recipeIndex"] = preview["recipeIndex"].DeepClone(),
                ["craftCount"] = preview["craftCount"].DeepClone(),
                ["output"] = preview["output"].DeepClone(),
                ["materials"] = preview["materials"].DeepClone(),
                ["outputDelivery"] = preview["outputDelivery"].DeepClone(),
                ["outputPrototype"] = OutputPrototype(
                    preview["output"] as JObject,
                    preview["outputDelivery"] as JObject),
                ["cost"] = preview["cost"].DeepClone()
            };
        }

        private static JToken OutputPrototype(JObject output, JObject delivery)
        {
            string storageKind = (string)delivery["storageKind"];
            if (storageKind != "bag" && storageKind != "drug") return JValue.CreateNull();
            JObject item = InventoryProjectionFromOutput(output);
            return new JObject
            {
                ["item"] = item,
                ["confirmProjection"] = StableConfirm(item)
            };
        }

        private static JToken OutputReceiptFromPlan(JObject plan)
        {
            if (plan == null) return JValue.CreateNull();
            JObject prototype = plan["outputPrototype"] as JObject;
            JObject delivery = plan["outputDelivery"] as JObject;
            if (prototype == null || delivery == null) return JValue.CreateNull();
            JObject item = (JObject)prototype["item"].DeepClone();
            long quantity = item.Value<long>("quantity");
            if ((string)delivery["mode"] == "merge") quantity += 4;
            item["quantity"] = quantity;
            JObject confirm = StableConfirm(item);
            confirm["lastUpdate"] = 123456789L;
            return new JObject
            {
                ["item"] = item,
                ["confirmProjection"] = confirm
            };
        }

        private static JObject InventoryProjectionFromOutput(JObject output)
        {
            bool equipment = (string)output["itemKind"] == "equipment";
            int enhancement = output.Value<int>("enhancementLevel");
            var item = new JObject
            {
                ["name"] = output["name"].DeepClone(),
                ["displayName"] = output["displayName"].DeepClone(),
                ["icon"] = output["icon"].DeepClone(),
                ["majorType"] = output["majorType"].DeepClone(),
                ["use"] = output["use"].DeepClone(),
                ["actionType"] = output["actionType"].DeepClone(),
                ["weaponType"] = output["weaponType"].DeepClone(),
                ["setId"] = output["setId"].DeepClone(),
                ["setName"] = output["setName"].DeepClone(),
                ["setOrder"] = output["setOrder"].DeepClone(),
                ["itemKind"] = output["itemKind"].DeepClone(),
                ["quantity"] = output["quantity"].DeepClone(),
                ["enhancementLevel"] = output["enhancementLevel"].DeepClone(),
                ["maxEnhancementLevel"] = 13,
                ["isMaxEnhancement"] = equipment && enhancement >= 13,
                ["tierSlotAvailable"] = false,
                ["tierSlotUsed"] = false,
                ["modSlotCapacity"] = equipment ? 1 : 0,
                ["modSlotUsed"] = 0,
                ["modSlots"] = new JArray(),
                ["modMeta"] = JValue.CreateNull(),
                ["rarity"] = equipment ? "rare" : ""
            };
            if (equipment)
            {
                item["balanceSummary"] = new JObject
                {
                    ["state"] = "confirmed", ["weightLayers"] = 2,
                    ["formula"] = 1, ["level"] = enhancement
                };
            }
            return item;
        }

        private static JObject StableConfirm(JObject item)
        {
            return new JObject
            {
                ["itemKind"] = item["itemKind"].DeepClone(),
                ["name"] = item["name"].DeepClone(),
                ["displayName"] = item["displayName"].DeepClone(),
                ["quantity"] = item["quantity"].DeepClone(),
                ["enhancementLevel"] = item["enhancementLevel"].DeepClone(),
                ["rarity"] = item["rarity"].DeepClone(),
                ["tier"] = "",
                ["modSignature"] = ""
            };
        }

        private static JObject ValidModProjection()
        {
            return new JObject
            {
                ["name"] = "测试插件", ["displayName"] = "测试插件",
                ["icon"] = "测试插件", ["grade"] = "a", ["gradeLabel"] = "A",
                ["gradeColor"] = "#ffffff", ["role"] = "utility",
                ["roleLabel"] = "功能", ["symbol"] = "diamond",
                ["scope"] = "equipment"
            };
        }

        [Fact]
        public void Commit_LogManagerCaptureNeverContainsRawAuthorityToken()
        {
            var sent = new List<JObject>();
            var logs = new List<string>();
            LogManager.SetSink(logs.Add);
            try
            {
                using (var task = new CraftingTask(
                    () => true,
                    value =>
                    {
                        sent.Add(JObject.Parse(value.TrimEnd('\0')));
                        return true;
                    }))
                {
                    PrimeCommitAuthority(task, sent);
                    logs.Clear();
                    task.HandleWebRequest("commit", Request(
                        "commit", "craft.log-redaction.commit"));
                }
            }
            finally
            {
                LogManager.ResetSink();
            }

            string flashLog = Assert.Single(logs,
                value => value.Contains("[CraftingTask] -> Flash:"));
            JObject command = sent[sent.Count - 1];
            string binding = Assert.Single(logs,
                value => value.StartsWith(
                    "event=authority_flash_call_bound ",
                    StringComparison.Ordinal));
            Assert.Equal(
                "event=authority_flash_call_bound domain=crafting"
                + " webCallId=craft.log-redaction.commit"
                + " flashCallId=" + (int)command["callId"]
                + " panel=crafting panelInstanceId=" + DefaultPanelInstanceId
                + " cmd=commit action=craftingCommit",
                binding);
            Assert.Contains("cmd=craftingCommit", flashLog);
            Assert.Contains("expectedCraftTokenRef="
                + AuthorityLogFormatter.CreateReference("craft.10.1"), flashLog);
            Assert.All(logs,
                value => Assert.DoesNotContain("craft.10.1", value));
        }
    }
}
