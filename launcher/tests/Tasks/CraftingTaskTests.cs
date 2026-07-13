using System;
using System.Collections.Generic;
using System.Threading;
using Newtonsoft.Json.Linq;
using Xunit;
using CF7Launcher.Guardian;
using CF7Launcher.Tasks;

namespace Launcher.Tests.Tasks
{
    public sealed class CraftingTaskTests
    {
        private static JObject Request(string cmd, string callId)
        {
            var payload = new JObject { ["v"] = 1 };
            if (cmd == "tooltip") payload["itemName"] = "不锈钢材";
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
                JObject badCount = Request("preview", "craft.bad.count");
                badCount["payload"]["craftCount"] = 100;
                task.HandleWebRequest("preview", badCount);
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
                ["category"] = "武器合成",
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
    }
}
