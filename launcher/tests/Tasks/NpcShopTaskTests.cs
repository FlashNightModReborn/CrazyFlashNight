using System;
using System.Collections.Generic;
using System.Threading;
using Newtonsoft.Json.Linq;
using Xunit;
using CF7Launcher.Tasks;
using CF7Launcher.Tests.Contracts;

namespace CF7Launcher.Tests.Tasks
{
    public class NpcShopTaskTests
    {
        private static JObject ParseSent(string payload) { return JObject.Parse(payload.TrimEnd('\0')); }

        private static JObject StateResponse(int fid, string operation = null)
        {
            var response = new JObject
            {
                ["task"] = "npcshop_response", ["callId"] = fid, ["success"] = true, ["v"] = 1,
                ["shopId"] = "前治安官", ["balance"] = 5000, ["catalog"] = new JArray(),
                ["layout"] = new JObject(),
                ["views"] = new JObject
                {
                    ["material"] = new JObject(), ["intelligence"] = new JObject()
                }
            };
            if (!string.IsNullOrEmpty(operation)) response["operation"] = operation;
            if (operation == "tradeCommit") response["trade"] = new JObject { ["buyTotal"] = 0, ["sellTotal"] = 0 };
            return response;
        }

        private static JObject TradePreviewResponse(int fid)
        {
            return new JObject
            {
                ["task"] = "npcshop_response", ["callId"] = fid, ["success"] = true, ["v"] = 1,
                ["tradeToken"] = "npctrade10.1",
                ["purchaseLines"] = new JArray(new JObject
                {
                    ["catalogIndex"] = 3, ["itemName"] = "训练手枪", ["displayName"] = "训练手枪",
                    ["icon"] = "训练手枪", ["itemKind"] = "equipment", ["quantity"] = 2,
                    ["unitPrice"] = 1000, ["total"] = 2000, ["maxQuantity"] = 50,
                    ["destinationView"] = "bag", ["purchaseLimit"] = 50, ["maxAffordable"] = 5,
                    ["maxByCapacity"] = 3, ["maxPurchasable"] = 3, ["limitingReason"] = "inventory_full"
                }),
                ["saleLines"] = new JArray(new JObject
                {
                    ["itemName"] = "强化石", ["displayName"] = "强化石", ["icon"] = "强化石",
                    ["itemKind"] = "stack", ["quantity"] = 4, ["total"] = 100,
                    ["sourceIdentity"] = "material:强化石", ["scope"] = "slot",
                    ["matchedCount"] = 1, ["eligibleCount"] = 1, ["protectedCount"] = 0
                }),
                ["buyTotal"] = 2000, ["sellTotal"] = 100, ["netDelta"] = -1900,
                ["projectedBalance"] = 3100, ["requiredSlots"] = 2, ["availableSlots"] = 3,
                ["missingSlots"] = 0, ["canCommit"] = true, ["blockingError"] = ""
            };
        }

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
        public void Tooltip_BagSource_NormalizesLeaseBoundSlotRef()
        {
            string sent = null;
            var task = new NpcShopTask(() => true, json => { sent = json; return true; });
            JObject request = Request("tooltip", "npc.tooltip.bag.1");
            request["payload"]["source"] = new JObject
            {
                ["containerId"] = "背包", ["slot"] = 5, ["expectedLease"] = "inv1.s5"
            };

            task.HandleWebRequest("tooltip", request);

            JObject flash = ParseSent(sent);
            Assert.Equal("npcShopTooltip", (string)flash["action"]);
            Assert.Equal("背包", (string)flash["source"]["containerId"]);
            Assert.Equal(5, (int)flash["source"]["slot"]);
            Assert.Equal("inv1.s5", (string)flash["source"]["expectedLease"]);
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

            task.HandleFlashResponse(StateResponse(fid), _ => { });

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
            task.HandleFlashResponse(StateResponse(fid), _ => { });

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

        [Fact]
        public void TradePreview_AuthoritativeShape_IsForwardedToWeb()
        {
            string sent = null;
            string posted = null;
            using (var task = new NpcShopTask(() => true, json => { sent = json; return true; }))
            {
                task.SetPostToWeb(json => posted = json);
                task.HandleWebRequest("tradePreview", Request("tradePreview", "npc.preview.valid.1"));
                int fid = (int)ParseSent(sent)["callId"];

                task.HandleFlashResponse(TradePreviewResponse(fid), null);

                JObject response = JObject.Parse(posted);
                Assert.True((bool)response["success"]);
                Assert.Equal("npctrade10.1", (string)response["tradeToken"]);
                Assert.Equal(3, (int)response["purchaseLines"][0]["maxPurchasable"]);
                Assert.Equal("idle", task.WriteState);
                Assert.Null(response["requiresReconcile"]);
            }
        }

        [Fact]
        public void TradePreview_MalformedSuccess_IsReadFailureWithoutPoisoningWriteGate()
        {
            string sent = null;
            string posted = null;
            using (var task = new NpcShopTask(() => true, json => { sent = json; return true; }))
            {
                task.SetPostToWeb(json => posted = json);
                task.HandleWebRequest("tradePreview", Request("tradePreview", "npc.preview.malformed.1"));
                int fid = (int)ParseSent(sent)["callId"];

                task.HandleFlashResponse(new JObject
                {
                    ["task"] = "npcshop_response", ["callId"] = fid, ["success"] = true
                }, null);

                JObject response = JObject.Parse(posted);
                Assert.False((bool)response["success"]);
                Assert.Equal("malformed_response", (string)response["error"]);
                Assert.Equal("idle", task.WriteState);
                Assert.Null(response["requiresReconcile"]);
            }
        }

        [Theory]
        [InlineData("insufficient_money")]
        [InlineData("inventory_full")]
        [InlineData("destination_full")]
        public void TradePreview_ConsistentBlockedState_IsAccepted(string blockingError)
        {
            string sent = null;
            string posted = null;
            using (var task = new NpcShopTask(() => true, json => { sent = json; return true; }))
            {
                task.SetPostToWeb(json => posted = json);
                task.HandleWebRequest("tradePreview", Request("tradePreview", "npc.preview.blocked." + blockingError));
                int fid = (int)ParseSent(sent)["callId"];
                JObject response = TradePreviewResponse(fid);
                response["canCommit"] = false;
                response["blockingError"] = blockingError;
                if (blockingError == "insufficient_money") response["projectedBalance"] = -1;
                else if (blockingError == "inventory_full")
                {
                    response["requiredSlots"] = 4; response["availableSlots"] = 3; response["missingSlots"] = 1;
                }
                else
                {
                    response["purchaseLines"][0]["itemKind"] = "stack";
                    response["purchaseLines"][0]["destinationView"] = "intelligence";
                    response["purchaseLines"][0]["maxByCapacity"] = 0;
                    response["purchaseLines"][0]["maxPurchasable"] = 0;
                    response["purchaseLines"][0]["limitingReason"] = "destination_full";
                    response["requiredSlots"] = 0;
                }

                task.HandleFlashResponse(response, null);

                JObject web = JObject.Parse(posted);
                Assert.True((bool)web["success"]);
                Assert.False((bool)web["canCommit"]);
                Assert.Equal(blockingError, (string)web["blockingError"]);
            }
        }

        [Theory]
        [InlineData("purchase_identity")]
        [InlineData("purchase_quantity")]
        [InlineData("purchase_bounds")]
        [InlineData("sale_identity")]
        [InlineData("sale_scope")]
        [InlineData("aggregate_total")]
        [InlineData("capacity_total")]
        [InlineData("commit_capacity_state")]
        [InlineData("commit_money_state")]
        [InlineData("slot_counts")]
        [InlineData("destination_without_source")]
        public void TradePreview_ResponseMustMatchIntentAndRemainSelfConsistent(string mutation)
        {
            string sent = null;
            string posted = null;
            using (var task = new NpcShopTask(() => true, json => { sent = json; return true; }))
            {
                task.SetPostToWeb(json => posted = json);
                task.HandleWebRequest("tradePreview", Request("tradePreview", "npc.preview.mismatch." + mutation));
                int fid = (int)ParseSent(sent)["callId"];
                JObject response = TradePreviewResponse(fid);
                if (mutation == "purchase_identity") response["purchaseLines"][0]["catalogIndex"] = 4;
                else if (mutation == "purchase_quantity") response["purchaseLines"][0]["quantity"] = 3;
                else if (mutation == "purchase_bounds") response["purchaseLines"][0]["maxPurchasable"] = 2;
                else if (mutation == "sale_identity") response["saleLines"][0]["sourceIdentity"] = "material:伪造材料";
                else if (mutation == "sale_scope") response["saleLines"][0]["scope"] = "same_name";
                else if (mutation == "aggregate_total") response["buyTotal"] = 1999;
                else if (mutation == "capacity_total") response["missingSlots"] = 1;
                else if (mutation == "commit_capacity_state")
                {
                    response["requiredSlots"] = 4; response["availableSlots"] = 3; response["missingSlots"] = 1;
                }
                else if (mutation == "commit_money_state") response["projectedBalance"] = -1;
                else if (mutation == "slot_counts")
                {
                    response["saleLines"][0]["matchedCount"] = 2;
                    response["saleLines"][0]["protectedCount"] = 1;
                }
                else
                {
                    response["canCommit"] = false;
                    response["blockingError"] = "destination_full";
                }

                task.HandleFlashResponse(response, null);

                JObject web = JObject.Parse(posted);
                Assert.False((bool)web["success"]);
                Assert.Equal("malformed_response", (string)web["error"]);
                Assert.Equal("idle", task.WriteState);
                Assert.Null(web["requiresReconcile"]);
            }
        }

        [Theory]
        [InlineData("tradeCommit", true)]
        [InlineData("tradePreview", false)]
        public void PendingSendFailure_RequiresReconcileOnlyForWrites(string cmd, bool isWrite)
        {
            string posted = null;
            using (var task = new NpcShopTask(() => true, _ => false))
            {
                task.SetPostToWeb(json => posted = json);

                task.HandleWebRequest(cmd, Request(cmd, "npc.send-failure." + cmd));

                JObject response = JObject.Parse(posted);
                Assert.Equal("disconnected", (string)response["error"]);
                Assert.Equal(isWrite, response.Value<bool?>("requiresReconcile") == true);
                Assert.Equal(isWrite ? "needs_reconcile" : "idle", task.WriteState);
            }
        }

        [Theory]
        [InlineData("tradeCommit")]
        [InlineData("tradePreview")]
        public void ClientNotReady_RejectsWithoutEnteringReconcile(string cmd)
        {
            int sends = 0;
            string posted = null;
            using (var task = new NpcShopTask(() => false, _ => { sends++; return true; }))
            {
                task.SetPostToWeb(json => posted = json);

                task.HandleWebRequest(cmd, Request(cmd, "npc.not-ready." + cmd));

                JObject response = JObject.Parse(posted);
                Assert.Equal(0, sends);
                Assert.Equal("disconnected", (string)response["error"]);
                Assert.Null(response["requiresReconcile"]);
                Assert.Equal("idle", task.WriteState);
            }
        }

        [Theory]
        [InlineData("tradeCommit", true)]
        [InlineData("tradePreview", false)]
        public void Timeout_RequiresReconcileOnlyForWrites(string cmd, bool isWrite)
        {
            JObject posted = null;
            using (var responseSeen = new ManualResetEventSlim(false))
            using (var task = new NpcShopTask(() => true, _ => true, 20))
            {
                task.SetPostToWeb(json => { posted = JObject.Parse(json); responseSeen.Set(); });

                task.HandleWebRequest(cmd, Request(cmd, "npc.timeout." + cmd));
                Assert.True(responseSeen.Wait(TimeSpan.FromSeconds(2)), "NPC shop timeout response was not posted");

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
            using (var task = new NpcShopTask(() => true, json => { sent.Add(ParseSent(json)); return true; }))
            {
                task.SetPostToWeb(json => posted.Add(JObject.Parse(json)));
                JObject request = Request("snapshot", "npc.duplicate.1");

                task.HandleWebRequest("snapshot", request);
                task.HandleWebRequest("snapshot", request);
                Assert.Single(sent);

                task.HandleFlashResponse(StateResponse((int)sent[0]["callId"]), null);
                task.HandleWebRequest("snapshot", request);

                Assert.Single(sent);
                Assert.Single(posted);
            }
        }

        [Fact]
        public void DuplicateFlashResponse_PostsOnce()
        {
            var posted = new List<JObject>();
            string sent = null;
            using (var task = new NpcShopTask(() => true, json => { sent = json; return true; }))
            {
                task.SetPostToWeb(json => posted.Add(JObject.Parse(json)));
                task.HandleWebRequest("snapshot", Request("snapshot", "npc.response.once"));
                int fid = (int)ParseSent(sent)["callId"];

                task.HandleFlashResponse(StateResponse(fid), null);
                task.HandleFlashResponse(StateResponse(fid), null);

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
            var task = new NpcShopTask(() => true, json => { sent = json; return true; });
            try
            {
                task.SetPostToWeb(json => posted.Add(JObject.Parse(json)));
                task.HandleWebRequest("tradeCommit", Request("tradeCommit", "npc.drain." + dispose));
                int fid = (int)ParseSent(sent)["callId"];

                if (dispose) task.Dispose();
                else task.ClearPending();
                task.HandleFlashResponse(StateResponse(fid, "tradeCommit"), null);

                Assert.Equal("needs_reconcile", task.WriteState);
                Assert.Empty(posted);
            }
            finally
            {
                task.Dispose();
            }
        }

        [Theory]
        [MemberData(nameof(PanelContractVectors.NpcShopPurchaseQuantityValid), MemberType = typeof(PanelContractVectors))]
        public void PurchaseQuantity_WithinProtocolCeiling_IsForwardedToAuthority(int quantity)
        {
            foreach (string cmd in new[] { "buy", "tradePreview" })
            {
                string sent = null;
                using (var task = new NpcShopTask(() => true, json => { sent = json; return true; }))
                {
                    JObject request = Request(cmd, "npc.quantity." + cmd + "." + quantity);
                    if (cmd == "buy") request["payload"]["quantity"] = quantity;
                    else request["payload"]["purchases"][0]["quantity"] = quantity;

                    task.HandleWebRequest(cmd, request);

                    JObject command = ParseSent(sent);
                    int forwarded = cmd == "buy"
                        ? (int)command["quantity"]
                        : (int)command["purchases"][0]["quantity"];
                    Assert.Equal(quantity, forwarded);
                }
            }
        }

        [Theory]
        [MemberData(nameof(PanelContractVectors.NpcShopPurchaseQuantityInvalid), MemberType = typeof(PanelContractVectors))]
        public void PurchaseQuantity_OutsideProtocolCeiling_IsRejectedBeforeFlash(int quantity)
        {
            foreach (string cmd in new[] { "buy", "tradePreview" })
            {
                int sends = 0;
                string posted = null;
                using (var task = new NpcShopTask(() => true, _ => { sends++; return true; }))
                {
                    task.SetPostToWeb(json => posted = json);
                    JObject request = Request(cmd, "npc.quantity.invalid." + cmd + "." + quantity);
                    if (cmd == "buy") request["payload"]["quantity"] = quantity;
                    else request["payload"]["purchases"][0]["quantity"] = quantity;

                    task.HandleWebRequest(cmd, request);

                    Assert.Equal(0, sends);
                    Assert.Equal("invalid_payload", (string)JObject.Parse(posted)["error"]);
                }
            }
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

        [Fact]
        public void DestinationFull_IsDefinitiveWriteRejectionAndReopensGate()
        {
            string sent = null;
            string posted = null;
            using (var task = new NpcShopTask(() => true, json => { sent = json; return true; }))
            {
                task.SetPostToWeb(json => posted = json);
                task.HandleWebRequest("tradeCommit", Request("tradeCommit", "npc.trade.destination-full.1"));
                int fid = (int)ParseSent(sent)["callId"];

                task.HandleFlashResponse(new JObject
                {
                    ["task"] = "npcshop_response", ["callId"] = fid,
                    ["success"] = false, ["error"] = "destination_full"
                }, null);

                JObject response = JObject.Parse(posted);
                Assert.Equal("destination_full", (string)response["error"]);
                Assert.Equal("idle", task.WriteState);
                Assert.Null(response["requiresReconcile"]);
            }
        }

        [Fact]
        public void SnapshotWithoutDuplicateBagProjection_IsAuthoritative()
        {
            string sent = null;
            string posted = null;
            var task = new NpcShopTask(() => true, json => { sent = json; return true; });
            task.SetPostToWeb(json => posted = json);
            task.HandleWebRequest("snapshot", Request("snapshot", "npc.snapshot.domain.1"));
            int fid = (int)ParseSent(sent)["callId"];

            task.HandleFlashResponse(StateResponse(fid), _ => { });

            JObject web = JObject.Parse(posted);
            Assert.True((bool)web["success"]);
            Assert.Null(web["views"]["bag"]);
            Assert.NotNull(web["views"]["material"]);
            Assert.NotNull(web["views"]["intelligence"]);
        }

        [Fact]
        public void MalformedSuccessfulWrite_RequiresSnapshotReconcile()
        {
            string sent = null;
            string posted = null;
            var task = new NpcShopTask(() => true, json => { sent = json; return true; });
            task.SetPostToWeb(json => posted = json);
            task.HandleWebRequest("tradeCommit", Request("tradeCommit", "npc.trade.malformed.1"));
            int fid = (int)ParseSent(sent)["callId"];

            task.HandleFlashResponse(new JObject
            {
                ["task"] = "npcshop_response", ["callId"] = fid, ["success"] = true
            }, _ => { });

            JObject web = JObject.Parse(posted);
            Assert.Equal("needs_reconcile", task.WriteState);
            Assert.False((bool)web["success"]);
            Assert.Equal("malformed_response", (string)web["error"]);
            Assert.True((bool)web["requiresReconcile"]);
        }

        [Fact]
        public void EarlierSnapshot_DoesNotClearAWriteStillInFlight()
        {
            var sent = new List<JObject>();
            var task = new NpcShopTask(() => true, json => { sent.Add(ParseSent(json)); return true; });
            task.HandleWebRequest("snapshot", Request("snapshot", "npc.snapshot.concurrent.1"));
            int snapshotFid = (int)sent[0]["callId"];
            task.HandleWebRequest("tradeCommit", Request("tradeCommit", "npc.trade.concurrent.1"));
            int writeFid = (int)sent[1]["callId"];

            task.HandleFlashResponse(StateResponse(snapshotFid), _ => { });
            Assert.Equal("write_pending", task.WriteState);

            task.HandleFlashResponse(new JObject
            {
                ["task"] = "npcshop_response", ["callId"] = writeFid,
                ["success"] = false, ["error"] = "stale_state"
            }, _ => { });
            Assert.Equal("idle", task.WriteState);
        }

        [Fact]
        public void AuthoritativeTradeCommitSuccess_ReopensWriteGate()
        {
            string sent = null;
            var task = new NpcShopTask(() => true, json => { sent = json; return true; });
            task.HandleWebRequest("tradeCommit", Request("tradeCommit", "npc.trade.success.1"));
            int fid = (int)ParseSent(sent)["callId"];

            task.HandleFlashResponse(StateResponse(fid, "tradeCommit"), _ => { });

            Assert.Equal("idle", task.WriteState);
        }
    }
}
