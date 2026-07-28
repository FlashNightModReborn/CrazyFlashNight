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
        private static JObject Request(string cmd, string callId)
        {
            var payload = new JObject { ["v"] = 1 };
            if (cmd == "tooltip" || cmd == "materialDetail") payload["itemName"] = "不锈钢材";
            else if (cmd == "materials") { }
            else
            {
                payload["category"] = "武器合成";
                if (cmd == "preview") { payload["recipeIndex"] = 3; payload["craftCount"] = 2; }
                if (cmd == "commit") payload["expectedCraftToken"] = "craft.10.1";
            }
            return new JObject
            {
                ["type"] = "panel", ["domain"] = "crafting", ["panel"] = "crafting",
                ["cmd"] = cmd, ["callId"] = callId, ["payload"] = payload
            };
        }

        [Theory]
        [InlineData("snapshot", "craftingSnapshot")]
        [InlineData("materials", "craftingMaterials")]
        [InlineData("materialDetail", "craftingMaterialDetail")]
        [InlineData("preview", "craftingPreview")]
        [InlineData("tooltip", "craftingTooltip")]
        [InlineData("commit", "craftingCommit")]
        public void WebRequest_MapsStrictCommands(string cmd, string expectedAction)
        {
            string sent = null;
            string web = null;
            using (var task = new CraftingTask(() => true, value => { sent = value; return true; }))
            {
                task.SetPostToWeb(value => web = value);
                task.HandleWebRequest(cmd, Request(cmd, "craft.command." + cmd));
                JObject command = JObject.Parse(sent.TrimEnd('\0'));
                Assert.Equal(expectedAction, (string)command["action"]);
                Assert.Equal(1, (int)command["v"]);
                Assert.Null(command["payload"]);
                if (cmd == "preview") Assert.Equal(2, (int)command["craftCount"]);
                if (cmd == "snapshot")
                {
                    task.HandleFlashResponse(SnapshotResponse((int)command["callId"]), null);
                    JObject response = JObject.Parse(web);
                    Assert.True((bool)response["success"]);
                    Assert.Equal("男", (string)response["gender"]);
                    Assert.True((bool)response["recipes"][0]["canCraftOne"]);
                    Assert.Equal("ready", (string)response["recipes"][0]["availability"]);

                    task.HandleWebRequest("snapshot", Request("snapshot", "craft.command.snapshot.inconsistent"));
                    JObject inconsistentCommand = JObject.Parse(sent.TrimEnd('\0'));
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

                task.HandleWebRequest("materials", Request("materials", "craft.materials.bad"));
                int malformedFid = (int)JObject.Parse(sent.TrimEnd('\0'))["callId"];
                JObject malformed = MaterialsResponse(malformedFid);
                malformed["materials"][0]["sourceCount"] = -1;
                task.HandleFlashResponse(malformed, null);
                Assert.Equal("malformed_response", (string)JObject.Parse(web)["error"]);
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
                task.HandleWebRequest("commit", Request("commit", "craft.commit.ok"));
                int fid = (int)sent[0]["callId"];
                task.HandleFlashResponse(new JObject
                {
                    ["task"] = "crafting_response", ["callId"] = fid, ["success"] = true, ["v"] = 1,
                    ["operation"] = "commit", ["category"] = "武器合成", ["recipeIndex"] = 3,
                    ["craftCount"] = 1,
                    ["crafted"] = new JObject { ["name"] = "秋月" },
                    ["balance"] = new JObject { ["money"] = 10, ["kpoints"] = 2 }
                }, null);
                JObject response = JObject.Parse(web);
                Assert.True((bool)response["success"]);
                Assert.Equal("commit", (string)response["operation"]);
                Assert.Equal("idle", task.WriteState);
                Assert.Null(response["requiresReconcile"]);
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
                task.HandleWebRequest("commit", Request("commit", "craft.commit.malformed"));
                int commitFid = (int)sent[0]["callId"];
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
                int previewFid = (int)sent[1]["callId"];
                JObject inconsistentPreview = PreviewResponse(previewFid);
                inconsistentPreview["batchEligible"] = false;
                task.HandleFlashResponse(inconsistentPreview, null);
                Assert.Equal("needs_reconcile", task.WriteState);
                Assert.Equal("malformed_response", (string)web[1]["error"]);

                task.HandleWebRequest("preview", Request("preview", "craft.preview.reconcile.valid"));
                previewFid = (int)sent[2]["callId"];
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
                task.HandleWebRequest("commit", Request("commit", "craft.timeout.1"));
                Assert.True(SpinWait.SpinUntil(() => web.Count > 0, 2000));
                Assert.Equal("needs_reconcile", task.WriteState);
                Assert.True((bool)web[0]["requiresReconcile"]);

                task.HandleWebRequest("commit", Request("commit", "craft.timeout.2"));
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
            using (var task = new CraftingTask(() => true, _ => false))
            {
                task.SetPostToWeb(value => posted = value);

                task.HandleWebRequest(cmd, Request(cmd, "craft.send-failure." + cmd));

                JObject response = JObject.Parse(posted);
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
            using (var responseSeen = new ManualResetEventSlim(false))
            using (var task = new CraftingTask(() => true, _ => true, 20))
            {
                task.SetPostToWeb(value => { posted = JObject.Parse(value); responseSeen.Set(); });

                task.HandleWebRequest(cmd, Request(cmd, "craft.timeout.matrix." + cmd));
                Assert.True(responseSeen.Wait(TimeSpan.FromSeconds(2)), "Crafting timeout response was not posted");

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

        [Theory]
        [InlineData(false)]
        [InlineData(true)]
        public void ClearOrDispose_DrainsWriteAndLateResponseCannotReviveIt(bool dispose)
        {
            var posted = new List<JObject>();
            string sent = null;
            var task = new CraftingTask(() => true, value => { sent = value; return true; });
            try
            {
                task.SetPostToWeb(value => posted.Add(JObject.Parse(value)));
                task.HandleWebRequest("commit", Request("commit", "craft.drain." + dispose));
                int fid = (int)JObject.Parse(sent.TrimEnd('\0'))["callId"];

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

        private static JObject PreviewResponse(int fid)
        {
            return new JObject
            {
                ["task"] = "crafting_response", ["callId"] = fid, ["success"] = true, ["v"] = 1,
                ["category"] = "武器合成", ["recipeIndex"] = 3,
                ["craftCount"] = 2, ["batchEligible"] = true, ["maxCraftCount"] = 4,
                ["balance"] = new JObject { ["money"] = 10, ["kpoints"] = 2 },
                ["output"] = new JObject { ["name"] = "秋月" },
                ["materials"] = new JArray(), ["cost"] = new JObject { ["money"] = 0, ["kpoints"] = 0 },
                ["canCommit"] = false
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
                ["recipes"] = new JArray
                {
                    new JObject
                    {
                        ["recipeIndex"] = 3, ["title"] = "秋月图纸", ["batchEligible"] = false,
                        ["canCraftOne"] = true, ["availability"] = "ready", ["materialCount"] = 2,
                        ["output"] = new JObject { ["name"] = "秋月" },
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
                        ["kind"] = "enemy", ["enemyType"] = "测试敌人",
                        ["displayName"] = "测试敌人", ["probability"] = 0.1,
                        ["minLevel"] = 0, ["maxLevel"] = 0
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
    }
}
