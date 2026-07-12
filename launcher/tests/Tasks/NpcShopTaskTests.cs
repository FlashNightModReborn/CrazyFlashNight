using System;
using System.Collections.Generic;
using Newtonsoft.Json.Linq;
using Xunit;
using CF7Launcher.Tasks;

namespace CF7Launcher.Tests.Tasks
{
    public class NpcShopTaskTests
    {
        private static JObject ParseSent(string payload) { return JObject.Parse(payload.TrimEnd('\0')); }

        private static JObject Request(string cmd, string callId = "npc.test.1")
        {
            var payload = new JObject { ["v"] = 1 };
            if (cmd == "snapshot") payload["shopId"] = "前治安官";
            else if (cmd == "tooltip") payload["itemName"] = "强化石";
            else if (cmd == "buy")
            {
                payload["shopId"] = "前治安官"; payload["catalogIndex"] = 3; payload["quantity"] = 2;
            }
            else if (cmd == "sell")
            {
                payload["shopId"] = "前治安官"; payload["quantity"] = 4;
                payload["source"] = new JObject { ["viewId"] = "material", ["key"] = "强化石", ["expectedLease"] = "npc1.c2" };
            }
            else if (cmd == "batchPreview") payload["itemNames"] = new JArray("药剂", "弹药");
            else if (cmd == "batchSell")
            {
                payload["shopId"] = "前治安官"; payload["expectedBatchToken"] = "npcbatch1.2";
            }
            else if (cmd == "tradePreview")
            {
                payload["shopId"] = "前治安官";
                payload["purchases"] = new JArray(new JObject { ["catalogIndex"] = 3, ["quantity"] = 2 });
                payload["sales"] = new JArray(new JObject
                {
                    ["quantity"] = 4,
                    ["source"] = new JObject { ["viewId"] = "material", ["key"] = "强化石", ["expectedLease"] = "npc1.c2" }
                });
            }
            else if (cmd == "tradeCommit")
            {
                payload["shopId"] = "前治安官"; payload["expectedTradeToken"] = "npctrade1.2";
            }
            return new JObject
            {
                ["type"] = "panel", ["panel"] = "npcshop", ["domain"] = "npcshop",
                ["cmd"] = cmd, ["callId"] = callId, ["payload"] = payload
            };
        }

        [Theory]
        [InlineData("snapshot", "npcShopSnapshot")]
        [InlineData("tooltip", "npcShopTooltip")]
        [InlineData("buy", "npcShopBuy")]
        [InlineData("sell", "npcShopSell")]
        [InlineData("batchPreview", "npcShopBatchPreview")]
        [InlineData("batchSell", "npcShopBatchSell")]
        [InlineData("tradePreview", "npcShopTradePreview")]
        [InlineData("tradeCommit", "npcShopTradeCommit")]
        public void KnownCommands_MapToTrustedActionsAndDropEnvelopeSpoofing(string cmd, string action)
        {
            string sent = null;
            var task = new NpcShopTask(() => true, json => { sent = json; return true; });
            JObject request = Request(cmd);
            request["action"] = "evil";
            request["payload"]["unknown"] = "drop";

            task.HandleWebRequest(cmd, request);

            JObject flash = ParseSent(sent);
            Assert.Equal("cmd", (string)flash["task"]);
            Assert.Equal(action, (string)flash["action"]);
            Assert.Null(flash["payload"]);
            Assert.Null(flash["domain"]);
            Assert.Null(flash["unknown"]);
        }

        [Fact]
        public void Sell_AcceptsOnlyBagOrMaterialLeaseSources()
        {
            int sends = 0;
            string posted = null;
            var task = new NpcShopTask(() => true, _ => { sends++; return true; });
            task.SetPostToWeb(json => posted = json);
            JObject request = Request("sell");
            request["payload"]["source"] = new JObject
            {
                ["viewId"] = "intelligence", ["key"] = "机密", ["expectedLease"] = "npc1.c1"
            };

            task.HandleWebRequest("sell", request);

            Assert.Equal(0, sends);
            Assert.Equal("invalid_payload", (string)JObject.Parse(posted)["error"]);
        }

        [Fact]
        public void FlashResponse_RestoresNpcShopDomainCmdAndWebCallId()
        {
            string sent = null;
            string posted = null;
            var task = new NpcShopTask(() => true, json => { sent = json; return true; });
            task.SetPostToWeb(json => posted = json);
            task.HandleWebRequest("snapshot", Request("snapshot", "npc.web.snapshot.7"));
            int fid = (int)ParseSent(sent)["callId"];

            task.HandleFlashResponse(new JObject
            {
                ["task"] = "npcshop_response", ["callId"] = fid, ["success"] = true,
                ["shopId"] = "前治安官", ["catalog"] = new JArray()
            }, _ => { });

            JObject web = JObject.Parse(posted);
            Assert.Equal("panel_resp", (string)web["type"]);
            Assert.Equal("npcshop", (string)web["domain"]);
            Assert.Equal("snapshot", (string)web["cmd"]);
            Assert.Equal("npc.web.snapshot.7", (string)web["callId"]);
            Assert.Null(web["task"]);
        }

        [Fact]
        public void AmbiguousWrite_BlocksFurtherWritesUntilSuccessfulSnapshot()
        {
            var sent = new List<JObject>();
            bool failNext = true;
            string lastPosted = null;
            var task = new NpcShopTask(() => true, json =>
            {
                sent.Add(ParseSent(json));
                if (failNext) { failNext = false; return false; }
                return true;
            });
            task.SetPostToWeb(json => lastPosted = json);

            task.HandleWebRequest("buy", Request("buy", "npc.write.1"));
            Assert.Equal("needs_reconcile", task.WriteState);
            task.HandleWebRequest("sell", Request("sell", "npc.write.2"));
            Assert.Equal("reconcile_required", (string)JObject.Parse(lastPosted)["error"]);

            task.HandleWebRequest("snapshot", Request("snapshot", "npc.snapshot.2"));
            int fid = (int)sent[sent.Count - 1]["callId"];
            task.HandleFlashResponse(new JObject
            {
                ["task"] = "npcshop_response", ["callId"] = fid, ["success"] = true,
                ["catalog"] = new JArray(), ["views"] = new JObject()
            }, _ => { });

            Assert.Equal("idle", task.WriteState);
        }

        [Fact]
        public void ShopNotFound_IsDefinitiveRejectionAndDoesNotPoisonWriteGate()
        {
            string sent = null;
            var task = new NpcShopTask(() => true, json => { sent = json; return true; });
            task.HandleWebRequest("buy", Request("buy", "npc.missing-shop.1"));
            int fid = (int)ParseSent(sent)["callId"];

            task.HandleFlashResponse(new JObject
            {
                ["task"] = "npcshop_response", ["callId"] = fid,
                ["success"] = false, ["error"] = "shop_not_found"
            }, _ => { });

            Assert.Equal("idle", task.WriteState);
        }

        [Fact]
        public void BatchPreview_RejectsDuplicateOrOversizedNames()
        {
            int sends = 0;
            string posted = null;
            var task = new NpcShopTask(() => true, _ => { sends++; return true; });
            task.SetPostToWeb(json => posted = json);
            JObject request = Request("batchPreview");
            request["payload"]["itemNames"] = new JArray("药剂", "药剂");

            task.HandleWebRequest("batchPreview", request);

            Assert.Equal(0, sends);
            Assert.Equal("invalid_payload", (string)JObject.Parse(posted)["error"]);
        }

        [Fact]
        public void TradePreview_NormalizesOnlyAuthoritativeLineIdentities()
        {
            string sent = null;
            var task = new NpcShopTask(() => true, json => { sent = json; return true; });
            JObject request = Request("tradePreview");
            request["payload"]["purchases"][0]["clientPrice"] = 1;
            request["payload"]["sales"][0]["clientTotal"] = 999999;

            task.HandleWebRequest("tradePreview", request);

            JObject command = ParseSent(sent);
            Assert.Equal("npcShopTradePreview", (string)command["action"]);
            Assert.Null(command["clientPrice"]);
            Assert.Null(command["clientTotal"]);
            Assert.Equal(3, (int)command["purchases"][0]["catalogIndex"]);
            Assert.Equal("强化石", (string)command["sales"][0]["source"]["key"]);
        }

        [Theory]
        [InlineData(true)]
        [InlineData(false)]
        public void TradePreview_RejectsDuplicatePurchaseOrSaleIdentity(bool duplicatePurchase)
        {
            int sends = 0;
            string posted = null;
            var task = new NpcShopTask(() => true, _ => { sends++; return true; });
            task.SetPostToWeb(json => posted = json);
            JObject request = Request("tradePreview");
            if (duplicatePurchase)
                ((JArray)request["payload"]["purchases"]).Add(((JObject)request["payload"]["purchases"][0]).DeepClone());
            else
                ((JArray)request["payload"]["sales"]).Add(((JObject)request["payload"]["sales"][0]).DeepClone());

            task.HandleWebRequest("tradePreview", request);

            Assert.Equal(0, sends);
            Assert.Equal("invalid_payload", (string)JObject.Parse(posted)["error"]);
        }

        [Fact]
        public void TradePreview_NormalizesSameNamePlainOnlyWithoutClientQuantity()
        {
            string sent = null;
            var task = new NpcShopTask(() => true, json => { sent = json; return true; });
            JObject request = Request("tradePreview");
            request["payload"]["sales"] = new JArray(new JObject
            {
                ["scope"] = "same_name",
                ["policy"] = "plain_only",
                ["clientItemName"] = "伪造名称",
                ["source"] = new JObject
                {
                    ["containerId"] = "背包", ["slot"] = 7, ["expectedLease"] = "inv1.s7"
                }
            });

            task.HandleWebRequest("tradePreview", request);

            JObject line = (JObject)ParseSent(sent)["sales"][0];
            Assert.Equal("same_name", (string)line["scope"]);
            Assert.Equal("plain_only", (string)line["policy"]);
            Assert.Null(line["quantity"]);
            Assert.Null(line["clientItemName"]);
        }

        [Theory]
        [InlineData("slot", "plain_only", true)]
        [InlineData("same_name", "plain_only", true)]
        [InlineData("same_name", "all", true)]
        [InlineData("unknown", "plain_only", false)]
        public void TradePreview_RejectsInvalidBulkScopeCombinations(string scope, string policy, bool materialSource)
        {
            int sends = 0;
            string posted = null;
            var task = new NpcShopTask(() => true, _ => { sends++; return true; });
            task.SetPostToWeb(json => posted = json);
            JObject request = Request("tradePreview");
            var line = new JObject
            {
                ["scope"] = scope,
                ["policy"] = policy,
                ["source"] = materialSource
                    ? new JObject { ["viewId"] = "material", ["key"] = "强化石", ["expectedLease"] = "npc1.c2" }
                    : new JObject { ["containerId"] = "背包", ["slot"] = 7, ["expectedLease"] = "inv1.s7" }
            };
            if (scope == "slot") line["quantity"] = 1;
            request["payload"]["sales"] = new JArray(line);

            task.HandleWebRequest("tradePreview", request);

            Assert.Equal(0, sends);
            Assert.Equal("invalid_payload", (string)JObject.Parse(posted)["error"]);
        }

        [Fact]
        public void TradeCommit_IsAWriteAndDeterministicRejectionReopensGate()
        {
            string sent = null;
            var task = new NpcShopTask(() => true, json => { sent = json; return true; });
            task.HandleWebRequest("tradeCommit", Request("tradeCommit", "npc.trade.commit.1"));
            Assert.Equal("write_pending", task.WriteState);
            int fid = (int)ParseSent(sent)["callId"];

            task.HandleFlashResponse(new JObject
            {
                ["task"] = "npcshop_response", ["callId"] = fid, ["success"] = false, ["error"] = "stale_state"
            }, _ => { });

            Assert.Equal("idle", task.WriteState);
        }
    }
}
