using System;
using System.Collections.Generic;
using Newtonsoft.Json.Linq;
using Xunit;
using CF7Launcher.Tasks;

namespace CF7Launcher.Tests.Tasks
{
    /// <summary>
    /// 四个严格白名单 task 的 tooltip 成功响应：可选 document 键的放行/净化/剥离
    /// 端到端验证，以及"其余严格 schema 不放宽"的回归断言。
    /// </summary>
    public class TooltipDocumentResponseTests
    {
        private static JObject ParseSent(string payload)
        {
            return JObject.Parse(payload.TrimEnd('\0'));
        }

        private static JObject ValidDocument()
        {
            return new JObject
            {
                ["version"] = 1,
                ["title"] = "M4A1-消音",
                ["icon"] = new JObject { ["kind"] = "item", ["name"] = "M4A1" },
                ["profile"] = "dense",
                ["sections"] = new JArray
                {
                    new JObject
                    {
                        ["role"] = "intro",
                        ["runs"] = new JArray
                        {
                            new JObject { ["text"] = "M4A1-消音", ["bold"] = true },
                            new JObject { ["text"] = "+15%", ["color"] = "#ffcc00" }
                        }
                    }
                },
                ["unlisted"] = "must-not-forward"
            };
        }

        private static void AssertSanitizedDocument(JObject web)
        {
            JObject doc = web["document"] as JObject;
            Assert.NotNull(doc);
            Assert.Equal(1, (int)doc["version"]);
            Assert.Equal("M4A1-消音", (string)doc["title"]);
            Assert.Equal("M4A1", (string)doc["icon"]["name"]);
            Assert.Equal("dense", (string)doc["profile"]);
            Assert.Equal("intro", (string)doc["sections"][0]["role"]);
            Assert.Equal("+15%", (string)doc["sections"][0]["runs"][1]["text"]);
            Assert.Equal("#FFCC00", (string)doc["sections"][0]["runs"][1]["color"]);
            Assert.Null(doc["unlisted"]);
        }

        private static JObject InvalidDocument()
        {
            return new JObject { ["version"] = 2, ["title"] = "越版文档" };
        }

        // ── InventoryTask（generic inventoryTooltip 与严格角色候选共用同一归一化器）──

        private static JObject InventoryTooltipRequest(string callId)
        {
            return new JObject
            {
                ["type"] = "panel",
                ["panel"] = "kshop",
                ["domain"] = "inventory",
                ["cmd"] = "tooltip",
                ["callId"] = callId,
                ["payload"] = new JObject
                {
                    ["v"] = 1,
                    ["source"] = new JObject
                    {
                        ["containerId"] = "背包",
                        ["slot"] = 2,
                        ["expectedLease"] = "inv100.2"
                    }
                }
            };
        }

        private static JObject InventoryTooltipResponse(JObject flash)
        {
            return new JObject
            {
                ["task"] = "inventory_response",
                ["callId"] = flash.Value<int>("callId"),
                ["success"] = true,
                ["v"] = 1,
                ["itemName"] = "候选",
                ["displayname"] = "候选",
                ["iconName"] = "候选图标",
                ["itemType"] = "武器",
                ["descHTML"] = "候选说明",
                ["introHTML"] = "<b>候选</b>"
            };
        }

        private static JObject RunInventoryTooltip(Action<JObject> mutate, string callId)
        {
            string sent = null;
            string posted = null;
            using (var task = new InventoryTask(
                () => true, payload => { sent = payload; return true; }))
            {
                task.SetPostToWeb(json => posted = json);
                task.HandleWebRequest("tooltip", InventoryTooltipRequest(callId));
                JObject response = InventoryTooltipResponse(ParseSent(sent));
                if (mutate != null) mutate(response);
                task.HandleFlashResponse(response, _ => { });
            }
            return JObject.Parse(posted);
        }

        [Fact]
        public void InventoryTooltip_ForwardsSanitizedDocument()
        {
            JObject web = RunInventoryTooltip(
                response => response["document"] = ValidDocument(),
                "ttdoc.inv.forward");

            Assert.True(web.Value<bool>("success"));
            Assert.Equal("<b>候选</b>", web.Value<string>("introHTML"));
            AssertSanitizedDocument(web);
        }

        [Fact]
        public void InventoryTooltip_InvalidDocumentStripped_LegacySuccessKept()
        {
            JObject web = RunInventoryTooltip(
                response => response["document"] = InvalidDocument(),
                "ttdoc.inv.strip");

            Assert.True(web.Value<bool>("success"));
            Assert.Equal("<b>候选</b>", web.Value<string>("introHTML"));
            Assert.Null(web["document"]);
        }

        [Fact]
        public void InventoryTooltip_NonObjectDocumentStripped_LegacySuccessKept()
        {
            JObject web = RunInventoryTooltip(
                response => response["document"] = "not-an-object",
                "ttdoc.inv.strip2");

            Assert.True(web.Value<bool>("success"));
            Assert.Null(web["document"]);
        }

        [Fact]
        public void InventoryTooltip_StillRejectsUnknownExtraKey()
        {
            JObject web = RunInventoryTooltip(
                response =>
                {
                    response["document"] = ValidDocument();
                    response["legacyProjection"] = "unproved";
                },
                "ttdoc.inv.extra");

            Assert.False(web.Value<bool>("success"));
            Assert.Equal("malformed_response", web.Value<string>("error"));
            Assert.Null(web["document"]);
        }

        [Fact]
        public void CharacterCandidateTooltip_ForwardsSanitizedDocument()
        {
            string sent = null;
            string posted = null;
            using (var task = new InventoryTask(
                () => true, payload => { sent = payload; return true; }))
            {
                task.SetPostToWeb(json => posted = json);
                JObject request = InventoryTooltipRequest("ttdoc.inv.candidate");
                request["panel"] = "workbench";
                request["panelInstanceId"] = "panel.workbench.build.1";
                task.HandleCharacterCandidateTooltip(request, () => true);
                JObject response = InventoryTooltipResponse(ParseSent(sent));
                response["document"] = ValidDocument();

                task.HandleFlashResponse(response, _ => { });
            }

            JObject web = JObject.Parse(posted);
            Assert.True(web.Value<bool>("success"));
            Assert.Equal("workbench", web.Value<string>("panel"));
            AssertSanitizedDocument(web);
        }

        // ── ShopTask（K商城 shopTooltip，先 seed bulk 权威目录）──

        private static JObject ShopRequest(string callId, bool tooltip)
        {
            var request = new JObject
            {
                ["callId"] = callId,
                ["panel"] = "kshop",
                ["panelInstanceId"] = "panel.kshop.owner-a"
            };
            if (tooltip) request["idx"] = 0;
            return request;
        }

        private static JObject ShopCatalogItem()
        {
            return new JObject
            {
                ["idx"] = 0, ["id"] = "catalog.alpha", ["item"] = "rule.alpha",
                ["type"] = "测试专柜", ["price"] = 10, ["displayname"] = "展示 Beta",
                ["majorType"] = "消耗品", ["subType"] = "药剂", ["actionType"] = "",
                ["weaponType"] = "", ["setId"] = "", ["setName"] = "",
                ["setOrder"] = 0, ["level"] = 1, ["icon"] = "icon.gamma",
                ["maxQuantity"] = 999999
            };
        }

        private static void SeedShopCatalog(ShopTask task, List<string> sent)
        {
            task.HandleWebRequest("bulkQuery", ShopRequest("ttdoc.shop.bulk", false));
            JObject bulk = ParseSent(sent[sent.Count - 1]);
            task.HandleFlashResponse(new JObject
            {
                ["task"] = "shop_response",
                ["callId"] = (int)bulk["callId"],
                ["success"] = true,
                ["catalog"] = new JArray(ShopCatalogItem()),
                ["cart"] = new JArray(),
                ["cartAdjusted"] = false,
                ["purchased"] = new JArray
                {
                    new JArray("catalog.alpha", "rule.alpha", "测试专柜", 10, 2)
                },
                ["purchasedView"] = new JArray(new JObject
                {
                    ["purchasedIdx"] = 0, ["item"] = "rule.alpha",
                    ["displayname"] = "展示 Beta", ["icon"] = "icon.gamma",
                    ["quantity"] = 2,
                    ["rowFingerprint"] = "kpr1.0123456789abcdef.0"
                }),
                ["kpoints"] = 100, ["playerLevel"] = 20, ["reverseLevel"] = 0,
                ["purchasedToken"] = "shop.test.1"
            }, _ => { });
        }

        private static JObject RunShopTooltip(Action<JObject> mutate, string callId)
        {
            var sent = new List<string>();
            var posted = new List<JObject>();
            using (var task = new ShopTask(
                () => true, payload => { sent.Add(payload); return true; }))
            {
                task.SetPostToWeb(json => posted.Add(JObject.Parse(json)));
                SeedShopCatalog(task, sent);
                task.HandleWebRequest("tooltip", ShopRequest(callId, true));
                JObject flash = ParseSent(sent[sent.Count - 1]);
                var response = new JObject
                {
                    ["task"] = "shop_response",
                    ["callId"] = (int)flash["callId"],
                    ["success"] = true,
                    ["descHTML"] = "<p>说明</p>",
                    ["introHTML"] = "<b>简介</b>",
                    ["itemName"] = "rule.alpha",
                    ["displayname"] = "展示 Beta",
                    ["iconName"] = "icon.gamma"
                };
                if (mutate != null) mutate(response);
                task.HandleFlashResponse(response, _ => { });
            }
            return posted[posted.Count - 1];
        }

        [Fact]
        public void ShopTooltip_ForwardsSanitizedDocument()
        {
            JObject web = RunShopTooltip(
                response => response["document"] = ValidDocument(),
                "ttdoc.shop.forward");

            Assert.True(web.Value<bool>("success"));
            Assert.Equal("<b>简介</b>", web.Value<string>("introHTML"));
            Assert.Equal("rule.alpha", web.Value<string>("itemName"));
            AssertSanitizedDocument(web);
        }

        [Fact]
        public void ShopTooltip_InvalidDocumentStripped_LegacySuccessKept()
        {
            JObject web = RunShopTooltip(
                response => response["document"] = InvalidDocument(),
                "ttdoc.shop.strip");

            Assert.True(web.Value<bool>("success"));
            Assert.Equal("<b>简介</b>", web.Value<string>("introHTML"));
            Assert.Null(web["document"]);
        }

        [Fact]
        public void ShopTooltip_StillRejectsUnknownExtraKey()
        {
            JObject web = RunShopTooltip(
                response =>
                {
                    response["document"] = ValidDocument();
                    response["injectedAuthority"] = true;
                },
                "ttdoc.shop.extra");

            Assert.False(web.Value<bool>("success"));
            Assert.Equal("invalid_response", web.Value<string>("error"));
            Assert.Null(web["document"]);
        }

        // ── NpcShopTask（npcShopTooltip，白名单投影本来就丢多余键）──

        private static JObject RunNpcShopTooltip(Action<JObject> mutate, string callId)
        {
            string sent = null;
            string posted = null;
            using (var task = new NpcShopTask(
                () => true, json => { sent = json; return true; }))
            {
                task.SetPostToWeb(json => posted = json);
                task.HandleWebRequest("tooltip", new JObject
                {
                    ["type"] = "panel", ["panel"] = "npcshop", ["domain"] = "npcshop",
                    ["panelInstanceId"] = "panel.npcshop.owner-a",
                    ["cmd"] = "tooltip", ["callId"] = callId,
                    ["payload"] = new JObject { ["v"] = 1, ["itemName"] = "强化石" }
                });
                var response = new JObject
                {
                    ["task"] = "npcshop_response",
                    ["callId"] = (int)ParseSent(sent)["callId"],
                    ["success"] = true, ["v"] = 1,
                    ["itemName"] = "强化石", ["displayname"] = "高纯强化石",
                    ["iconName"] = "强化石专用图标", ["itemType"] = "材料",
                    ["descHTML"] = "说明", ["introHTML"] = "简介"
                };
                if (mutate != null) mutate(response);
                task.HandleFlashResponse(response, null);
            }
            return JObject.Parse(posted);
        }

        [Fact]
        public void NpcShopTooltip_ForwardsSanitizedDocument()
        {
            JObject web = RunNpcShopTooltip(
                response =>
                {
                    response["document"] = ValidDocument();
                    response["injectedAuthority"] = true;
                },
                "ttdoc.npc.forward");

            Assert.True(web.Value<bool>("success"));
            Assert.Equal("高纯强化石", web.Value<string>("displayname"));
            Assert.Null(web["injectedAuthority"]);
            AssertSanitizedDocument(web);
        }

        [Fact]
        public void NpcShopTooltip_InvalidDocumentStripped_LegacySuccessKept()
        {
            JObject web = RunNpcShopTooltip(
                response => response["document"] = InvalidDocument(),
                "ttdoc.npc.strip");

            Assert.True(web.Value<bool>("success"));
            Assert.Equal("高纯强化石", web.Value<string>("displayname"));
            Assert.Null(web["document"]);
        }

        // ── CraftingTask（craftingTooltip，displayname→displayName 翻译保持）──

        private static JObject RunCraftingTooltip(Action<JObject> mutate, string callId)
        {
            var sent = new List<JObject>();
            var posted = new List<JObject>();
            using (var task = new CraftingTask(
                () => true,
                value => { sent.Add(JObject.Parse(value.TrimEnd('\0'))); return true; }))
            {
                task.SetPostToWeb(value => posted.Add(JObject.Parse(value)));
                task.HandleWebRequest("tooltip", new JObject
                {
                    ["type"] = "panel", ["domain"] = "crafting", ["panel"] = "crafting",
                    ["panelInstanceId"] = "panel.crafting.instance.1",
                    ["cmd"] = "tooltip", ["callId"] = callId,
                    ["payload"] = new JObject { ["v"] = 1, ["itemName"] = "不锈钢材" }
                });
                var response = new JObject
                {
                    ["task"] = "crafting_response",
                    ["callId"] = (int)sent[sent.Count - 1]["callId"],
                    ["success"] = true, ["v"] = 1,
                    ["itemName"] = "不锈钢材", ["displayname"] = "不锈精制钢材",
                    ["descHTML"] = "<p>说明</p>", ["introHTML"] = "<b>简介</b>"
                };
                if (mutate != null) mutate(response);
                task.HandleFlashResponse(response, null);
            }
            return posted[posted.Count - 1];
        }

        [Fact]
        public void CraftingTooltip_ForwardsSanitizedDocument()
        {
            JObject web = RunCraftingTooltip(
                response => response["document"] = ValidDocument(),
                "ttdoc.craft.forward");

            Assert.True(web.Value<bool>("success"));
            Assert.Equal("不锈精制钢材", web.Value<string>("displayName"));
            Assert.Null(web["displayname"]);
            AssertSanitizedDocument(web);
        }

        [Fact]
        public void CraftingTooltip_InvalidDocumentRemovedFromClone_LegacySuccessKept()
        {
            JObject web = RunCraftingTooltip(
                response => response["document"] = InvalidDocument(),
                "ttdoc.craft.strip");

            Assert.True(web.Value<bool>("success"));
            Assert.Equal("不锈精制钢材", web.Value<string>("displayName"));
            Assert.Null(web["document"]);
        }

        [Fact]
        public void CraftingTooltip_StillRejectsUnknownExtraKey()
        {
            JObject web = RunCraftingTooltip(
                response =>
                {
                    response["document"] = ValidDocument();
                    response["injected"] = true;
                },
                "ttdoc.craft.extra");

            Assert.False(web.Value<bool>("success"));
            Assert.Equal("malformed_response", web.Value<string>("error"));
            Assert.Null(web["document"]);
        }
    }
}
