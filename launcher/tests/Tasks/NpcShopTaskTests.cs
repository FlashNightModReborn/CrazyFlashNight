using System;
using System.Collections.Generic;
using System.Threading;
using Newtonsoft.Json.Linq;
using Xunit;
using CF7Launcher.Guardian;
using CF7Launcher.Tasks;
using CF7Launcher.Tests.Contracts;

namespace CF7Launcher.Tests.Tasks
{
    public class NpcShopTaskTests
    {
        private const string OwnerA = "panel.npcshop.owner-a";
        private const string OwnerB = "panel.npcshop.owner-b";
        private static int _primeSequence;

        private static JObject ParseSent(string payload) { return JObject.Parse(payload.TrimEnd('\0')); }

        private static void AssertOwnerTuple(
            JObject response, string cmd, string callId, string owner = OwnerA)
        {
            Assert.Equal("npcshop", (string)response["domain"]);
            Assert.Equal("npcshop", (string)response["panel"]);
            Assert.Equal(owner, (string)response["panelInstanceId"]);
            Assert.Equal(cmd, (string)response["cmd"]);
            Assert.Equal(callId, (string)response["callId"]);
        }

        private static JObject StateResponse(int fid, string operation = null)
        {
            var response = new JObject
            {
                ["task"] = "npcshop_response", ["callId"] = fid, ["success"] = true, ["v"] = 1,
                ["shopId"] = "前治安官", ["balance"] = 5000, ["buyRatePermille"] = 1000,
                ["catalog"] = new JArray(new JObject
                {
                    ["catalogIndex"] = 3, ["itemName"] = "光棱射线弹-强化",
                    ["displayName"] = "棱镜折射阵列", ["icon"] = "全光谱棱镜阵列",
                    ["majorType"] = "武器", ["use"] = "手枪", ["actionType"] = "",
                    ["weaponType"] = "手枪", ["setId"] = "", ["setName"] = "",
                    ["setOrder"] = 0, ["basePrice"] = 1000, ["unitPrice"] = 1000,
                    ["maxQuantity"] = 50, ["requiredInfo"] = "", ["locked"] = false
                }),
                ["layout"] = new JObject
                {
                    ["title"] = "前治安官", ["defaultSection"] = "", ["sections"] = new JArray()
                },
                ["views"] = new JObject
                {
                    ["material"] = EmptyCollectionView("材料"),
                    ["intelligence"] = EmptyCollectionView("情报")
                }
            };
            if (!string.IsNullOrEmpty(operation)) response["operation"] = operation;
            if (operation == "tradeCommit") response["trade"] = new JObject
            {
                ["buyTotal"] = 2000, ["sellTotal"] = 100, ["netDelta"] = -1900
            };
            if (operation == "tradeCommit") response["balance"] = 3100;
            return response;
        }

        private static JObject EmptyCollectionView(string containerId)
        {
            return new JObject
            {
                ["containerId"] = containerId, ["capacity"] = 0,
                ["accessibleCapacity"] = 0, ["viewCapacity"] = 0,
                ["offset"] = 0, ["limit"] = 0, ["filterKey"] = "all",
                ["slots"] = new JArray()
            };
        }

        private static JObject CollectionView(
            string containerId,
            string collectionKey,
            JToken quantity)
        {
            return new JObject
            {
                ["containerId"] = containerId, ["capacity"] = 1,
                ["accessibleCapacity"] = 1, ["viewCapacity"] = 1,
                ["offset"] = 0, ["limit"] = 1, ["filterKey"] = "all",
                ["slots"] = new JArray(new JObject
                {
                    ["physicalSlot"] = 0,
                    ["collectionKey"] = collectionKey,
                    ["occupied"] = true,
                    ["slotLease"] = "npc1.collection.1",
                    ["item"] = new JObject
                    {
                        ["itemKind"] = "stack",
                        ["name"] = collectionKey,
                        ["displayName"] = collectionKey,
                        ["icon"] = collectionKey,
                        ["majorType"] = "收集品",
                        ["use"] = containerId,
                        ["quantity"] = quantity,
                        ["enhancementLevel"] = 0,
                        ["rarity"] = ""
                    }
                })
            };
        }

        private static JObject TradePreviewResponse(int fid)
        {
            return new JObject
            {
                ["task"] = "npcshop_response", ["callId"] = fid, ["success"] = true, ["v"] = 1,
                ["shopId"] = "前治安官", ["tradeToken"] = "npctrade10.1",
                ["purchaseLines"] = new JArray(new JObject
                {
                    ["catalogIndex"] = 3, ["itemName"] = "光棱射线弹-强化",
                    ["displayName"] = "棱镜折射阵列", ["icon"] = "全光谱棱镜阵列",
                    ["itemKind"] = "equipment", ["quantity"] = 2,
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

        private static JObject Request(
            string cmd, string callId = "npc.test.1", string owner = OwnerA)
        {
            var payload = new JObject { ["v"] = 1 };
            if (cmd == "snapshot") payload["shopId"] = "前治安官";
            else if (cmd == "tooltip") payload["itemName"] = "强化石";
            else if (cmd == "buy")
            {
                payload["shopId"] = "前治安官"; payload["catalogIndex"] = 3; payload["quantity"] = 2;
            }
            else if (cmd == "batchPreview") payload["itemNames"] = new JArray("药剂", "弹药");
            else if (cmd == "batchSell")
            {
                payload["shopId"] = "前治安官"; payload["expectedBatchToken"] = "npcbatch10.1";
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
                payload["shopId"] = "前治安官"; payload["expectedTradeToken"] = "npctrade10.1";
            }
            return new JObject
            {
                ["type"] = "panel", ["panel"] = "npcshop", ["domain"] = "npcshop",
                ["panelInstanceId"] = owner,
                ["cmd"] = cmd, ["callId"] = callId, ["payload"] = payload
            };
        }

        private static JObject BatchPreviewResponse(int fid)
        {
            return new JObject
            {
                ["task"] = "npcshop_response", ["callId"] = fid,
                ["success"] = true, ["v"] = 1, ["batchToken"] = "npcbatch10.1",
                ["balance"] = 5000,
                ["summary"] = new JArray(
                    new JObject
                    {
                        ["itemName"] = "药剂", ["displayName"] = "高级药剂",
                        ["icon"] = "药剂专用图标", ["quantity"] = 3, ["money"] = 75
                    },
                    new JObject
                    {
                        ["itemName"] = "弹药", ["displayName"] = "制式弹药",
                        ["icon"] = "弹药箱图标", ["quantity"] = 2, ["money"] = 40
                    }),
                ["totalQuantity"] = 5, ["totalMoney"] = 115, ["skipped"] = 0
            };
        }

        private static JObject BuyResponse(int fid)
        {
            JObject response = StateResponse(fid, "buy");
            response["destinationView"] = "bag";
            response["itemName"] = "光棱射线弹-强化";
            response["quantity"] = 2;
            response["total"] = 2000;
            response["balance"] = 3000;
            return response;
        }

        private static string PrimeCallId(string kind)
        {
            return "npc.prime." + kind + "." + Interlocked.Increment(ref _primeSequence);
        }

        private static void PrimeCatalog(NpcShopTask task, Func<JObject> latestSent)
        {
            task.HandleWebRequest("snapshot", Request("snapshot", PrimeCallId("catalog")));
            JObject flash = latestSent();
            Assert.NotNull(flash);
            task.HandleFlashResponse(StateResponse((int)flash["callId"]), null);
        }

        private static void PrimeTrade(NpcShopTask task, Func<JObject> latestSent)
        {
            PrimeCatalog(task, latestSent);
            task.HandleWebRequest("tradePreview", Request("tradePreview", PrimeCallId("trade")));
            JObject flash = latestSent();
            Assert.NotNull(flash);
            task.HandleFlashResponse(TradePreviewResponse((int)flash["callId"]), null);
        }

        private static void PrimeBatch(NpcShopTask task, Func<JObject> latestSent)
        {
            task.HandleWebRequest("batchPreview", Request("batchPreview", PrimeCallId("batch")));
            JObject flash = latestSent();
            Assert.NotNull(flash);
            task.HandleFlashResponse(BatchPreviewResponse((int)flash["callId"]), null);
        }

        [Fact]
        public void Snapshot_AllDistinctIdentity_IsForwardedButUntrustedTopLevelKeysAreDropped()
        {
            string sent = null;
            string posted = null;
            using (var task = new NpcShopTask(() => true, json => { sent = json; return true; }))
            {
                task.SetPostToWeb(json => posted = json);
                task.HandleWebRequest("snapshot", Request("snapshot", "npc.identity.snapshot"));
                JObject response = StateResponse((int)ParseSent(sent)["callId"]);
                response["injectedAuthority"] = "must_not_cross_host";

                task.HandleFlashResponse(response, null);

                JObject web = JObject.Parse(posted);
                Assert.True((bool)web["success"]);
                Assert.Equal("光棱射线弹-强化", (string)web["catalog"][0]["itemName"]);
                Assert.Equal("棱镜折射阵列", (string)web["catalog"][0]["displayName"]);
                Assert.Equal("全光谱棱镜阵列", (string)web["catalog"][0]["icon"]);
                Assert.Equal(1000L, (long)web["buyRatePermille"]);
                Assert.Null(web["buyMultiplier"]);
                Assert.Null(web["injectedAuthority"]);
            }
        }

        [Theory]
        [InlineData("legacy_multiplier")]
        [InlineData("fractional_rate")]
        [InlineData("negative_rate")]
        [InlineData("over_npc_rate")]
        [InlineData("fractional_balance")]
        [InlineData("unsafe_balance")]
        [InlineData("fractional_base_price")]
        [InlineData("unsafe_intermediate")]
        public void Snapshot_PermilleWireRejectsLegacyOrUnsafeNumbers(string mutation)
        {
            string sent = null;
            string posted = null;
            using (var task = new NpcShopTask(
                () => true,
                json => { sent = json; return true; }))
            {
                task.SetPostToWeb(json => posted = json);
                task.HandleWebRequest(
                    "snapshot",
                    Request("snapshot", "npc.permille.invalid." + mutation));
                JObject response = StateResponse((int)ParseSent(sent)["callId"]);
                JObject line = (JObject)response["catalog"][0];
                if (mutation == "legacy_multiplier") response["buyMultiplier"] = 1;
                else if (mutation == "fractional_rate") response["buyRatePermille"] = 850.0;
                else if (mutation == "negative_rate") response["buyRatePermille"] = -1;
                else if (mutation == "over_npc_rate") response["buyRatePermille"] = 1001;
                else if (mutation == "fractional_balance") response["balance"] = 5000.0;
                else if (mutation == "unsafe_balance")
                    response["balance"] = PermilleMath.MaxSafeInteger + 1;
                else if (mutation == "fractional_base_price") line["basePrice"] = 1000.5;
                else
                {
                    line["basePrice"] = PermilleMath.MaxSafeInteger;
                    line["unitPrice"] = PermilleMath.MaxSafeInteger;
                }

                task.HandleFlashResponse(response, null);

                JObject web = JObject.Parse(posted);
                Assert.False((bool)web["success"]);
                Assert.Equal("malformed_response", (string)web["error"]);
            }
        }

        [Fact]
        public void Snapshot_ResponseMustBindRequestedShopSelector()
        {
            string sent = null;
            string posted = null;
            using (var task = new NpcShopTask(() => true, json => { sent = json; return true; }))
            {
                task.SetPostToWeb(json => posted = json);
                task.HandleWebRequest("snapshot", Request("snapshot", "npc.selector.snapshot"));
                JObject response = StateResponse((int)ParseSent(sent)["callId"]);
                response["shopId"] = "伪造商店";

                task.HandleFlashResponse(response, null);

                JObject web = JObject.Parse(posted);
                Assert.False((bool)web["success"]);
                Assert.Equal("malformed_response", (string)web["error"]);
            }
        }

        [Theory]
        [InlineData("missing_display")]
        [InlineData("legacy_display_alias")]
        [InlineData("wrong_icon_type")]
        [InlineData("blank_display")]
        [InlineData("undefined_icon")]
        [InlineData("extra_near_match")]
        [InlineData("price_formula")]
        public void Snapshot_CatalogIdentityLeafRejectsMalformedTriples(string mutation)
        {
            string sent = null;
            string posted = null;
            using (var task = new NpcShopTask(() => true, json => { sent = json; return true; }))
            {
                task.SetPostToWeb(json => posted = json);
                task.HandleWebRequest("snapshot", Request("snapshot", "npc.identity.bad." + mutation));
                JObject response = StateResponse((int)ParseSent(sent)["callId"]);
                JObject line = (JObject)response["catalog"][0];
                if (mutation == "missing_display") line.Remove("displayName");
                else if (mutation == "legacy_display_alias")
                {
                    line["displayname"] = line["displayName"];
                    line.Remove("displayName");
                }
                else if (mutation == "wrong_icon_type") line["icon"] = 7;
                else if (mutation == "blank_display") line["displayName"] = "   ";
                else if (mutation == "undefined_icon") line["icon"] = " Undefined ";
                else if (mutation == "price_formula") line["unitPrice"] = 999;
                else line["displayname"] = line["displayName"];

                task.HandleFlashResponse(response, null);

                JObject web = JObject.Parse(posted);
                Assert.False((bool)web["success"]);
                Assert.Equal("malformed_response", (string)web["error"]);
            }
        }

        [Fact]
        public void Tooltip_ResponseBindsInternalNameAndSanitizesProjection()
        {
            string sent = null;
            string posted = null;
            using (var task = new NpcShopTask(() => true, json => { sent = json; return true; }))
            {
                task.SetPostToWeb(json => posted = json);
                task.HandleWebRequest("tooltip", Request("tooltip", "npc.tooltip.identity"));
                JObject response = new JObject
                {
                    ["task"] = "npcshop_response", ["callId"] = (int)ParseSent(sent)["callId"],
                    ["success"] = true, ["v"] = 1, ["itemName"] = "强化石",
                    ["displayname"] = "高纯强化石", ["iconName"] = "强化石专用图标",
                    ["itemType"] = "材料", ["descHTML"] = "说明", ["introHTML"] = "简介",
                    ["injectedAuthority"] = true
                };

                task.HandleFlashResponse(response, null);

                JObject web = JObject.Parse(posted);
                Assert.True((bool)web["success"]);
                Assert.Equal("强化石", (string)web["itemName"]);
                Assert.Equal("高纯强化石", (string)web["displayname"]);
                Assert.Equal("强化石专用图标", (string)web["iconName"]);
                Assert.Null(web["injectedAuthority"]);
            }
        }

        [Fact]
        public void Tooltip_ResponseRejectsDifferentInternalName()
        {
            string sent = null;
            string posted = null;
            using (var task = new NpcShopTask(() => true, json => { sent = json; return true; }))
            {
                task.SetPostToWeb(json => posted = json);
                task.HandleWebRequest("tooltip", Request("tooltip", "npc.tooltip.selector"));
                task.HandleFlashResponse(new JObject
                {
                    ["task"] = "npcshop_response", ["callId"] = (int)ParseSent(sent)["callId"],
                    ["success"] = true, ["v"] = 1, ["itemName"] = "伪造材料",
                    ["displayname"] = "伪造材料", ["descHTML"] = "", ["introHTML"] = ""
                }, null);

                JObject web = JObject.Parse(posted);
                Assert.False((bool)web["success"]);
                Assert.Equal("malformed_response", (string)web["error"]);
            }
        }

        [Fact]
        public void BatchPreview_AllDistinctLinesBindRequestedNamesAndSums()
        {
            string sent = null;
            string posted = null;
            using (var task = new NpcShopTask(() => true, json => { sent = json; return true; }))
            {
                task.SetPostToWeb(json => posted = json);
                task.HandleWebRequest("batchPreview", Request("batchPreview", "npc.batch.identity"));
                JObject response = BatchPreviewResponse((int)ParseSent(sent)["callId"]);
                response["injectedAuthority"] = "drop";

                task.HandleFlashResponse(response, null);

                JObject web = JObject.Parse(posted);
                Assert.True((bool)web["success"]);
                Assert.Equal("高级药剂", (string)web["summary"][0]["displayName"]);
                Assert.Equal("药剂专用图标", (string)web["summary"][0]["icon"]);
                Assert.Equal(5, (int)web["totalQuantity"]);
                Assert.Equal(115, (int)web["totalMoney"]);
                Assert.Equal(5000, (int)web["balance"]);
                Assert.Null(web["injectedAuthority"]);
            }
        }

        [Theory]
        [InlineData("selector")]
        [InlineData("missing_display")]
        [InlineData("wrong_icon_type")]
        [InlineData("aggregate")]
        [InlineData("fractional_balance")]
        [InlineData("fractional_total")]
        [InlineData("fractional_line_money")]
        public void BatchPreview_ResponseRejectsIdentitySelectorAndAggregateMismatch(string mutation)
        {
            string sent = null;
            string posted = null;
            using (var task = new NpcShopTask(() => true, json => { sent = json; return true; }))
            {
                task.SetPostToWeb(json => posted = json);
                task.HandleWebRequest("batchPreview", Request("batchPreview", "npc.batch.bad." + mutation));
                JObject response = BatchPreviewResponse((int)ParseSent(sent)["callId"]);
                JObject line = (JObject)response["summary"][0];
                if (mutation == "selector") line["itemName"] = "伪造药剂";
                else if (mutation == "missing_display") line.Remove("displayName");
                else if (mutation == "wrong_icon_type") line["icon"] = false;
                else if (mutation == "fractional_balance") response["balance"] = 5000.0;
                else if (mutation == "fractional_total") response["totalMoney"] = 115.0;
                else if (mutation == "fractional_line_money") line["money"] = 75.0;
                else response["totalMoney"] = 114;

                task.HandleFlashResponse(response, null);

                JObject web = JObject.Parse(posted);
                Assert.False((bool)web["success"]);
                Assert.Equal("malformed_response", (string)web["error"]);
            }
        }

        [Fact]
        public void Buy_ResponsePostconditionMustMatchRequestedQuantity()
        {
            string sent = null;
            string posted = null;
            using (var task = new NpcShopTask(() => true, json => { sent = json; return true; }))
            {
                PrimeCatalog(task, () => ParseSent(sent));
                task.SetPostToWeb(json => posted = json);
                task.HandleWebRequest("buy", Request("buy", "npc.buy.postcondition"));
                JObject response = BuyResponse((int)ParseSent(sent)["callId"]);
                response["quantity"] = 1;

                task.HandleFlashResponse(response, null);

                JObject web = JObject.Parse(posted);
                Assert.False((bool)web["success"]);
                Assert.Equal("malformed_response", (string)web["error"]);
                Assert.True((bool)web["requiresReconcile"]);
                Assert.Equal("needs_reconcile", task.WriteState);
            }
        }

        [Fact]
        public void Buy_AuthoritativePostconditionClosesWrite()
        {
            string sent = null;
            string posted = null;
            using (var task = new NpcShopTask(() => true, json => { sent = json; return true; }))
            {
                PrimeCatalog(task, () => ParseSent(sent));
                task.SetPostToWeb(json => posted = json);
                task.HandleWebRequest("buy", Request("buy", "npc.buy.authoritative"));
                task.HandleFlashResponse(BuyResponse((int)ParseSent(sent)["callId"]), null);

                JObject web = JObject.Parse(posted);
                Assert.True((bool)web["success"]);
                Assert.Equal(2, (int)web["quantity"]);
                Assert.Equal("idle", task.WriteState);
                Assert.Null(web["requiresReconcile"]);
            }
        }

        [Theory]
        [InlineData("buy")]
        [InlineData("tradePreview")]
        public void CatalogBoundCommands_RejectBeforeFlashWithoutFreshOwnerSnapshot(string cmd)
        {
            int sends = 0;
            string posted = null;
            using (var task = new NpcShopTask(() => true, _ => { sends++; return true; }))
            {
                task.SetPostToWeb(json => posted = json);
                task.HandleWebRequest(cmd, Request(cmd, "npc.catalog.missing." + cmd));

                Assert.Equal(0, sends);
                JObject response = JObject.Parse(posted);
                Assert.Equal("stale_state", (string)response["error"]);
                Assert.Equal("idle", task.WriteState);
            }
        }

        [Fact]
        public void Buy_CurrentCatalogIdentityMustMatchFrozenRequestedIndex()
        {
            string sent = null;
            string posted = null;
            using (var task = new NpcShopTask(() => true, json => { sent = json; return true; }))
            {
                PrimeCatalog(task, () => ParseSent(sent));
                task.SetPostToWeb(json => posted = json);
                task.HandleWebRequest("buy", Request("buy", "npc.buy.wrong-triple"));
                JObject response = BuyResponse((int)ParseSent(sent)["callId"]);
                response["catalog"][0]["displayName"] = "近似但错误的显示名";
                response["catalog"][0]["icon"] = "近似但错误的图标";

                task.HandleFlashResponse(response, null);

                JObject web = JObject.Parse(posted);
                Assert.False((bool)web["success"]);
                Assert.Equal("malformed_response", (string)web["error"]);
                Assert.True((bool)web["requiresReconcile"]);
            }
        }

        [Fact]
        public void Buy_SuccessCannotExceedFrozenCatalogLimit()
        {
            string sent = null;
            string posted = null;
            using (var task = new NpcShopTask(() => true, json => { sent = json; return true; }))
            {
                PrimeCatalog(task, () => ParseSent(sent));
                task.SetPostToWeb(json => posted = json);
                JObject request = Request("buy", "npc.buy.over-frozen-limit");
                request["payload"]["quantity"] = 51;
                task.HandleWebRequest("buy", request);
                JObject response = BuyResponse((int)ParseSent(sent)["callId"]);
                response["quantity"] = 51;
                response["total"] = 51000;

                task.HandleFlashResponse(response, null);

                JObject web = JObject.Parse(posted);
                Assert.False((bool)web["success"]);
                Assert.Equal("malformed_response", (string)web["error"]);
                Assert.True((bool)web["requiresReconcile"]);
            }
        }

        [Theory]
        [InlineData("snapshot", "npcShopSnapshot")]
        [InlineData("tooltip", "npcShopTooltip")]
        [InlineData("buy", "npcShopBuy")]
        [InlineData("batchPreview", "npcShopBatchPreview")]
        [InlineData("batchSell", "npcShopBatchSell")]
        [InlineData("tradePreview", "npcShopTradePreview")]
        [InlineData("tradeCommit", "npcShopTradeCommit")]
        public void KnownCommands_MapToTrustedActionsAndDropEnvelopeSpoofing(string cmd, string action)
        {
            string sent = null;
            var task = new NpcShopTask(() => true, json => { sent = json; return true; });
            if (cmd == "buy" || cmd == "tradePreview")
                PrimeCatalog(task, () => ParseSent(sent));
            else if (cmd == "batchSell")
                PrimeBatch(task, () => ParseSent(sent));
            else if (cmd == "tradeCommit")
                PrimeTrade(task, () => ParseSent(sent));
            sent = null;
            JObject request = Request(cmd);
            request["action"] = "evil";
            request["payload"]["unknown"] = "drop";

            task.HandleWebRequest(cmd, request);

            JObject flash = ParseSent(sent);
            Assert.Equal("cmd", (string)flash["task"]);
            Assert.Equal(action, (string)flash["action"]);
            Assert.Null(flash["payload"]);
            Assert.Null(flash["domain"]);
            Assert.Null(flash["panelInstanceId"]);
            Assert.Null(flash["unknown"]);
        }

        [Fact]
        public void OrdinarySell_IsRetiredBeforeFlashDispatch()
        {
            int sends = 0;
            string posted = null;
            var task = new NpcShopTask(() => true, _ => { sends++; return true; });
            task.SetPostToWeb(json => posted = json);
            JObject request = Request("sell");

            task.HandleWebRequest("sell", request);

            Assert.Equal(0, sends);
            Assert.Equal("unsupported_cmd", (string)JObject.Parse(posted)["error"]);
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
            AssertOwnerTuple(web, "snapshot", "npc.web.snapshot.7");
            Assert.Null(web["task"]);
        }

        [Fact]
        public void AmbiguousWrite_BlocksFurtherWritesUntilSuccessfulSnapshot()
        {
            var sent = new List<JObject>();
            bool failNext = false;
            string lastPosted = null;
            var task = new NpcShopTask(() => true, json =>
            {
                sent.Add(ParseSent(json));
                if (failNext) { failNext = false; return false; }
                return true;
            });
            PrimeCatalog(task, () => sent[sent.Count - 1]);
            sent.Clear();
            failNext = true;
            task.SetPostToWeb(json => lastPosted = json);

            task.HandleWebRequest("buy", Request("buy", "npc.write.1"));
            Assert.Equal("needs_reconcile", task.WriteState);
            task.HandleWebRequest("buy", Request("buy", "npc.write.2"));
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
            PrimeCatalog(task, () => ParseSent(sent));
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
            PrimeCatalog(task, () => ParseSent(sent));
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
                PrimeCatalog(task, () => ParseSent(sent));
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
        public void TradePreview_TotalUsesAuthoritativePermilleFormula()
        {
            string sent = null;
            string posted = null;
            using (var task = new NpcShopTask(() => true, json => { sent = json; return true; }))
            {
                task.HandleWebRequest("snapshot", Request("snapshot", "npc.price-formula.snapshot"));
                JObject snapshot = StateResponse((int)ParseSent(sent)["callId"]);
                snapshot["buyRatePermille"] = 850;
                snapshot["catalog"][0]["basePrice"] = 1001;
                snapshot["catalog"][0]["unitPrice"] = 850;
                task.HandleFlashResponse(snapshot, null);

                task.SetPostToWeb(json => posted = json);
                task.HandleWebRequest("tradePreview", Request("tradePreview", "npc.price-formula.preview"));
                JObject response = TradePreviewResponse((int)ParseSent(sent)["callId"]);
                response["purchaseLines"][0]["unitPrice"] = 850;
                response["purchaseLines"][0]["total"] = 1701;
                response["buyTotal"] = 1701;
                response["netDelta"] = -1601;
                response["projectedBalance"] = 3399;

                task.HandleFlashResponse(response, null);

                JObject web = JObject.Parse(posted);
                Assert.True((bool)web["success"]);
                Assert.Equal(1701, (int)web["buyTotal"]);
            }
        }

        [Fact]
        public void TradePreview_MalformedSuccess_IsReadFailureWithoutPoisoningWriteGate()
        {
            string sent = null;
            string posted = null;
            using (var task = new NpcShopTask(() => true, json => { sent = json; return true; }))
            {
                PrimeCatalog(task, () => ParseSent(sent));
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
                PrimeCatalog(task, () => ParseSent(sent));
                if (blockingError == "insufficient_money")
                {
                    task.HandleWebRequest("snapshot", Request("snapshot", PrimeCallId("low-balance")));
                    JObject lowBalance = StateResponse((int)ParseSent(sent)["callId"]);
                    lowBalance["balance"] = 1000;
                    task.HandleFlashResponse(lowBalance, null);
                }
                task.SetPostToWeb(json => posted = json);
                task.HandleWebRequest("tradePreview", Request("tradePreview", "npc.preview.blocked." + blockingError));
                int fid = (int)ParseSent(sent)["callId"];
                JObject response = TradePreviewResponse(fid);
                response["canCommit"] = false;
                response["blockingError"] = blockingError;
                if (blockingError == "insufficient_money") response["projectedBalance"] = -900;
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
        [InlineData("purchase_triple")]
        [InlineData("purchase_extra_key")]
        [InlineData("purchase_quantity")]
        [InlineData("purchase_total")]
        [InlineData("purchase_bounds")]
        [InlineData("sale_identity")]
        [InlineData("sale_scope")]
        [InlineData("aggregate_total")]
        [InlineData("capacity_total")]
        [InlineData("commit_capacity_state")]
        [InlineData("commit_money_state")]
        [InlineData("projected_balance")]
        [InlineData("fractional_purchase_total")]
        [InlineData("fractional_sale_total")]
        [InlineData("fractional_buy_total")]
        [InlineData("fractional_sell_total")]
        [InlineData("fractional_net_delta")]
        [InlineData("fractional_projected_balance")]
        [InlineData("slot_counts")]
        [InlineData("shop_selector")]
        [InlineData("destination_without_source")]
        public void TradePreview_ResponseMustMatchIntentAndRemainSelfConsistent(string mutation)
        {
            string sent = null;
            string posted = null;
            using (var task = new NpcShopTask(() => true, json => { sent = json; return true; }))
            {
                PrimeCatalog(task, () => ParseSent(sent));
                task.SetPostToWeb(json => posted = json);
                task.HandleWebRequest("tradePreview", Request("tradePreview", "npc.preview.mismatch." + mutation));
                int fid = (int)ParseSent(sent)["callId"];
                JObject response = TradePreviewResponse(fid);
                if (mutation == "shop_selector") response["shopId"] = "伪造商店";
                else if (mutation == "purchase_identity") response["purchaseLines"][0]["catalogIndex"] = 4;
                else if (mutation == "purchase_extra_key") response["purchaseLines"][0]["success"] = true;
                else if (mutation == "purchase_triple")
                {
                    response["purchaseLines"][0]["displayName"] = "近似但错误的显示名";
                    response["purchaseLines"][0]["icon"] = "近似但错误的图标";
                }
                else if (mutation == "purchase_quantity") response["purchaseLines"][0]["quantity"] = 3;
                else if (mutation == "purchase_total") response["purchaseLines"][0]["total"] = 1999;
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
                else if (mutation == "projected_balance") response["projectedBalance"] = 3000;
                else if (mutation == "fractional_purchase_total")
                    response["purchaseLines"][0]["total"] = 2000.0;
                else if (mutation == "fractional_sale_total")
                    response["saleLines"][0]["total"] = 100.0;
                else if (mutation == "fractional_buy_total") response["buyTotal"] = 2000.0;
                else if (mutation == "fractional_sell_total") response["sellTotal"] = 100.0;
                else if (mutation == "fractional_net_delta") response["netDelta"] = -1900.0;
                else if (mutation == "fractional_projected_balance")
                    response["projectedBalance"] = 3100.0;
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
            string sent = null;
            bool failSend = false;
            using (var task = new NpcShopTask(() => true, json =>
            {
                sent = json;
                return !failSend;
            }))
            {
                if (cmd == "tradeCommit") PrimeTrade(task, () => ParseSent(sent));
                else PrimeCatalog(task, () => ParseSent(sent));
                failSend = true;
                task.SetPostToWeb(json => posted = json);

                task.HandleWebRequest(cmd, Request(cmd, "npc.send-failure." + cmd));

                JObject response = JObject.Parse(posted);
                Assert.Equal("disconnected", (string)response["error"]);
                AssertOwnerTuple(response, cmd, "npc.send-failure." + cmd);
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
                AssertOwnerTuple(response, cmd, "npc.not-ready." + cmd);
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
            string sent = null;
            using (var responseSeen = new ManualResetEventSlim(false))
            using (var task = new NpcShopTask(() => true, json => { sent = json; return true; }, 20))
            {
                if (cmd == "tradeCommit") PrimeTrade(task, () => ParseSent(sent));
                else PrimeCatalog(task, () => ParseSent(sent));
                task.SetPostToWeb(json => { posted = JObject.Parse(json); responseSeen.Set(); });

                task.HandleWebRequest(cmd, Request(cmd, "npc.timeout." + cmd));
                Assert.True(responseSeen.Wait(TimeSpan.FromSeconds(2)), "NPC shop timeout response was not posted");

                Assert.Equal("timeout", (string)posted["error"]);
                AssertOwnerTuple(posted, cmd, "npc.timeout." + cmd);
                Assert.Equal(isWrite, posted.Value<bool?>("requiresReconcile") == true);
                Assert.Equal(isWrite ? "needs_reconcile" : "idle", task.WriteState);
            }
        }

        [Fact]
        public void InvalidOwnerTuple_IsRejectedBeforePendingOrFlashDispatch()
        {
            int sends = 0;
            var posted = new List<JObject>();
            using (var task = new NpcShopTask(() => true, _ => { sends++; return true; }))
            {
                task.SetPostToWeb(json => posted.Add(JObject.Parse(json)));

                JObject missingInstance = Request("snapshot", "npc.owner.missing");
                missingInstance.Remove("panelInstanceId");
                task.HandleWebRequest("snapshot", missingInstance);

                JObject foreignPanel = Request("snapshot", "npc.owner.foreign");
                foreignPanel["panel"] = "kshop";
                task.HandleWebRequest("snapshot", foreignPanel);

                task.HandleWebRequest("snapshot",
                    Request("snapshot", "npc.owner.invalid", "invalid owner"));

                Assert.Equal(0, sends);
                Assert.Empty(posted);
            }
        }

        [Fact]
        public void ClearedOwnerA_LateResponseCannotSatisfySameNameOwnerB()
        {
            var sent = new List<JObject>();
            var posted = new List<JObject>();
            using (var task = new NpcShopTask(
                () => true,
                json => { sent.Add(ParseSent(json)); return true; }))
            {
                task.SetPostToWeb(json => posted.Add(JObject.Parse(json)));

                task.HandleWebRequest("snapshot",
                    Request("snapshot", "npc.owner-a.snapshot", OwnerA));
                int ownerAFid = (int)sent[0]["callId"];
                task.ClearPending();

                task.HandleWebRequest("snapshot",
                    Request("snapshot", "npc.owner-b.snapshot", OwnerB));
                int ownerBFid = (int)sent[1]["callId"];

                task.HandleFlashResponse(StateResponse(ownerAFid), null);
                Assert.Empty(posted);

                task.HandleFlashResponse(StateResponse(ownerBFid), null);
                Assert.Single(posted);
                Assert.True((bool)posted[0]["success"]);
                AssertOwnerTuple(
                    posted[0], "snapshot", "npc.owner-b.snapshot", OwnerB);
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
                PrimeTrade(task, () => ParseSent(sent));
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
                    PrimeCatalog(task, () => ParseSent(sent));
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
            PrimeCatalog(task, () => ParseSent(sent));
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

        [Theory]
        [InlineData("batchSell")]
        [InlineData("tradeCommit")]
        public void PreviewBackedCommit_RejectsBeforeFlashWithoutOwnerLocalPreview(string cmd)
        {
            int sends = 0;
            string posted = null;
            using (var task = new NpcShopTask(() => true, _ => { sends++; return true; }))
            {
                task.SetPostToWeb(json => posted = json);
                task.HandleWebRequest(cmd, Request(cmd, "npc.preview-authority.missing." + cmd));

                Assert.Equal(0, sends);
                JObject response = JObject.Parse(posted);
                Assert.Equal("stale_state", (string)response["error"]);
                Assert.Equal("idle", task.WriteState);
            }
        }

        [Theory]
        [InlineData("batchSell")]
        [InlineData("tradeCommit")]
        public void PreviewBackedCommit_WrongTokenDoesNotDestroyExactAuthority(string cmd)
        {
            var sent = new List<JObject>();
            string posted = null;
            using (var task = new NpcShopTask(
                () => true,
                json => { sent.Add(ParseSent(json)); return true; }))
            {
                if (cmd == "batchSell") PrimeBatch(task, () => sent[sent.Count - 1]);
                else PrimeTrade(task, () => sent[sent.Count - 1]);
                sent.Clear();
                task.SetPostToWeb(json => posted = json);
                JObject request = Request(cmd, "npc.preview-authority.wrong-token." + cmd);
                if (cmd == "batchSell") request["payload"]["expectedBatchToken"] = "npcbatch.wrong";
                else request["payload"]["expectedTradeToken"] = "npctrade.wrong";

                task.HandleWebRequest(cmd, request);

                Assert.Empty(sent);
                Assert.Equal("stale_state", (string)JObject.Parse(posted)["error"]);

                task.HandleWebRequest(cmd, Request(cmd, "npc.preview-authority.correct-after-wrong." + cmd));
                Assert.Single(sent);
                Assert.Equal("write_pending", task.WriteState);
            }
        }

        [Theory]
        [InlineData("batchSell")]
        [InlineData("tradeCommit")]
        public void PreviewBackedCommit_NewerPreviewSupersedesOlderToken(string cmd)
        {
            var sent = new List<JObject>();
            string posted = null;
            using (var task = new NpcShopTask(
                () => true,
                json => { sent.Add(ParseSent(json)); return true; }))
            {
                if (cmd == "batchSell") PrimeBatch(task, () => sent[sent.Count - 1]);
                else PrimeTrade(task, () => sent[sent.Count - 1]);

                string previewCmd = cmd == "batchSell" ? "batchPreview" : "tradePreview";
                task.HandleWebRequest(previewCmd, Request(previewCmd, PrimeCallId("replacement")));
                int previewFid = (int)sent[sent.Count - 1]["callId"];
                JObject replacement = cmd == "batchSell"
                    ? BatchPreviewResponse(previewFid)
                    : TradePreviewResponse(previewFid);
                string replacementToken = cmd == "batchSell" ? "npcbatch10.2" : "npctrade10.2";
                replacement[cmd == "batchSell" ? "batchToken" : "tradeToken"] = replacementToken;
                task.HandleFlashResponse(replacement, null);

                sent.Clear();
                task.SetPostToWeb(json => posted = json);
                task.HandleWebRequest(cmd, Request(cmd, "npc.preview-authority.superseded." + cmd));
                Assert.Empty(sent);
                Assert.Equal("stale_state", (string)JObject.Parse(posted)["error"]);

                JObject current = Request(cmd, "npc.preview-authority.latest." + cmd);
                current["payload"][cmd == "batchSell"
                    ? "expectedBatchToken" : "expectedTradeToken"] = replacementToken;
                task.HandleWebRequest(cmd, current);
                Assert.Single(sent);
                Assert.Equal("write_pending", task.WriteState);
            }
        }

        [Theory]
        [InlineData("batchSell")]
        [InlineData("tradeCommit")]
        public void PreviewBackedCommit_ConsumesExactTokenAtFirstAdmission(string cmd)
        {
            var sent = new List<JObject>();
            string posted = null;
            using (var task = new NpcShopTask(
                () => true,
                json => { sent.Add(ParseSent(json)); return true; }))
            {
                if (cmd == "batchSell") PrimeBatch(task, () => sent[sent.Count - 1]);
                else PrimeTrade(task, () => sent[sent.Count - 1]);
                sent.Clear();
                task.SetPostToWeb(json => posted = json);

                task.HandleWebRequest(cmd, Request(cmd, "npc.preview-authority.consume.1." + cmd));
                int fid = (int)sent[0]["callId"];
                task.HandleFlashResponse(new JObject
                {
                    ["task"] = "npcshop_response", ["callId"] = fid,
                    ["success"] = false, ["error"] = "stale_state"
                }, null);
                task.HandleWebRequest(cmd, Request(cmd, "npc.preview-authority.consume.2." + cmd));

                Assert.Single(sent);
                Assert.Equal("stale_state", (string)JObject.Parse(posted)["error"]);
                Assert.Equal("idle", task.WriteState);
            }
        }

        [Theory]
        [InlineData("batchSell")]
        [InlineData("tradeCommit")]
        public void PreviewBackedCommit_AuthoritativePostconditionClosesWrite(string cmd)
        {
            string sent = null;
            string posted = null;
            using (var task = new NpcShopTask(() => true, json => { sent = json; return true; }))
            {
                if (cmd == "batchSell") PrimeBatch(task, () => ParseSent(sent));
                else PrimeTrade(task, () => ParseSent(sent));
                task.SetPostToWeb(json => posted = json);
                task.HandleWebRequest(cmd, Request(cmd, "npc.preview-authority.success." + cmd));
                int fid = (int)ParseSent(sent)["callId"];
                JObject response = StateResponse(fid, cmd);
                if (cmd == "batchSell")
                {
                    response["quantity"] = 5;
                    response["total"] = 115;
                    response["balance"] = 5115;
                }

                task.HandleFlashResponse(response, null);

                Assert.True((bool)JObject.Parse(posted)["success"]);
                Assert.Equal("idle", task.WriteState);
            }
        }

        [Theory]
        [InlineData("batch_quantity")]
        [InlineData("batch_total")]
        [InlineData("trade_total")]
        [InlineData("trade_balance")]
        [InlineData("trade_catalog_triple")]
        public void PreviewBackedCommit_RejectsSelfConsistentButDifferentPostcondition(string mutation)
        {
            string sent = null;
            string posted = null;
            string cmd = mutation.StartsWith("batch", StringComparison.Ordinal)
                ? "batchSell" : "tradeCommit";
            using (var task = new NpcShopTask(() => true, json => { sent = json; return true; }))
            {
                if (cmd == "batchSell") PrimeBatch(task, () => ParseSent(sent));
                else PrimeTrade(task, () => ParseSent(sent));
                task.SetPostToWeb(json => posted = json);
                task.HandleWebRequest(cmd, Request(cmd, "npc.preview-authority.postcondition." + mutation));
                int fid = (int)ParseSent(sent)["callId"];
                JObject response = StateResponse(fid, cmd);
                if (cmd == "batchSell")
                {
                    response["quantity"] = mutation == "batch_quantity" ? 4 : 5;
                    response["total"] = mutation == "batch_total" ? 114 : 115;
                    response["balance"] = mutation == "batch_total" ? 5114 : 5115;
                }
                else if (mutation == "trade_total")
                {
                    response["trade"]["buyTotal"] = 1900;
                    response["trade"]["sellTotal"] = 100;
                    response["trade"]["netDelta"] = -1800;
                }
                else if (mutation == "trade_balance") response["balance"] = 3101;
                else
                {
                    response["catalog"][0]["displayName"] = "近似但错误的显示名";
                    response["catalog"][0]["icon"] = "近似但错误的图标";
                }

                task.HandleFlashResponse(response, null);

                JObject web = JObject.Parse(posted);
                Assert.False((bool)web["success"]);
                Assert.Equal("malformed_response", (string)web["error"]);
                Assert.True((bool)web["requiresReconcile"]);
                Assert.Equal("needs_reconcile", task.WriteState);
            }
        }

        [Fact]
        public void TradeCommit_IsAWriteAndDeterministicRejectionReopensGate()
        {
            string sent = null;
            var task = new NpcShopTask(() => true, json => { sent = json; return true; });
            PrimeTrade(task, () => ParseSent(sent));
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
                PrimeTrade(task, () => ParseSent(sent));
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
            PrimeTrade(task, () => ParseSent(sent));
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
        public void SnapshotWithNonEmptyCollectionViews_IsAuthoritative()
        {
            string sent = null;
            string posted = null;
            using (var task = new NpcShopTask(
                () => true,
                json => { sent = json; return true; }))
            {
                task.SetPostToWeb(json => posted = json);
                task.HandleWebRequest(
                    "snapshot",
                    Request("snapshot", "npc.snapshot.nonempty.1"));
                int fid = (int)ParseSent(sent)["callId"];
                JObject response = StateResponse(fid);
                response["views"]["material"] = CollectionView(
                    "材料", "强化石", new JValue(3));
                response["views"]["intelligence"] = CollectionView(
                    "情报", "解锁情报", new JValue(1));

                LogManager.SetSink(_ => throw new InvalidOperationException(
                    "diagnostic sink failure"));
                try
                {
                    task.HandleFlashResponse(response, null);
                }
                finally
                {
                    LogManager.ResetSink();
                }

                JObject web = JObject.Parse(posted);
                Assert.True((bool)web["success"]);
                Assert.Equal(3L,
                    (long)web["views"]["material"]["slots"][0]["item"]["quantity"]);
                Assert.Equal(1L,
                    (long)web["views"]["intelligence"]["slots"][0]["item"]["quantity"]);
            }
        }

        [Fact]
        public void FractionalMaterialQuantity_IsRejectedWithRedactedPathDiagnostic()
        {
            const string secretMaterialName = "仅用于确认日志不泄漏的材料";
            string sent = null;
            string posted = null;
            var logs = new List<string>();
            LogManager.SetSink(logs.Add);
            try
            {
                using (var task = new NpcShopTask(
                    () => true,
                    json => { sent = json; return true; }))
                {
                    task.SetPostToWeb(json => posted = json);
                    task.HandleWebRequest(
                        "snapshot",
                        Request("snapshot", "npc.snapshot.fractional.1"));
                    int fid = (int)ParseSent(sent)["callId"];
                    JObject response = StateResponse(fid);
                    response["views"]["material"] = CollectionView(
                        "材料", secretMaterialName, new JValue(1.5));

                    task.HandleFlashResponse(response, null);

                    JObject web = JObject.Parse(posted);
                    Assert.False((bool)web["success"]);
                    Assert.Equal("malformed_response", (string)web["error"]);
                }
            }
            finally
            {
                LogManager.ResetSink();
            }

            string validation = Assert.Single(logs, value => value.StartsWith(
                "event=npcshop_response_validation ",
                StringComparison.Ordinal));
            Assert.Contains("outcome=rejected", validation);
            Assert.Contains("stage=collection", validation);
            Assert.Contains(
                "field=$.views.material.slots[0].item.quantity",
                validation);
            Assert.Contains("expected=positive_safe_integer", validation);
            Assert.Contains("shapeRef=sha256_", validation);
            Assert.All(logs, value =>
            {
                Assert.DoesNotContain(secretMaterialName, value);
                Assert.DoesNotContain("1.5", value);
            });
        }

        [Fact]
        public void MalformedSuccessfulWrite_RequiresSnapshotReconcile()
        {
            string sent = null;
            string posted = null;
            var task = new NpcShopTask(() => true, json => { sent = json; return true; });
            PrimeTrade(task, () => ParseSent(sent));
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
            PrimeTrade(task, () => sent[sent.Count - 1]);
            sent.Clear();
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
        public void SnapshotIssuedBeforeDeliveryUnknownWrite_DoesNotClearReconcileEpoch()
        {
            var sent = new List<JObject>();
            bool failNext = false;
            using (var task = new NpcShopTask(() => true, json =>
            {
                sent.Add(ParseSent(json));
                if (failNext) { failNext = false; return false; }
                return true;
            }))
            {
                PrimeTrade(task, () => sent[sent.Count - 1]);
                sent.Clear();
                task.HandleWebRequest("snapshot", Request("snapshot", "npc.epoch.old-read"));
                int oldSnapshotFid = (int)sent[0]["callId"];

                failNext = true;
                task.HandleWebRequest("tradeCommit", Request("tradeCommit", "npc.epoch.write"));
                Assert.Equal("needs_reconcile", task.WriteState);

                task.HandleFlashResponse(StateResponse(oldSnapshotFid), null);
                Assert.Equal("needs_reconcile", task.WriteState);

                task.HandleWebRequest("snapshot", Request("snapshot", "npc.epoch.new-read"));
                int newSnapshotFid = (int)sent[sent.Count - 1]["callId"];
                task.HandleFlashResponse(StateResponse(newSnapshotFid), null);
                Assert.Equal("idle", task.WriteState);
            }
        }

        [Fact]
        public void SnapshotThatTimedOutBeforeWriteTimeout_CannotClearReconcileEpochWhenLate()
        {
            var sent = new List<JObject>();
            using (var oldReadTimedOut = new ManualResetEventSlim(false))
            using (var writeTimedOut = new ManualResetEventSlim(false))
            using (var task = new NpcShopTask(() => true, json =>
            {
                sent.Add(ParseSent(json));
                return true;
            }, 100))
            {
                PrimeTrade(task, () => sent[sent.Count - 1]);
                sent.Clear();
                task.SetPostToWeb(json =>
                {
                    JObject response = JObject.Parse(json);
                    if (response.Value<string>("error") != "timeout") return;
                    if (response.Value<string>("callId")
                        == "npc.epoch.timeout.old-read")
                    {
                        oldReadTimedOut.Set();
                    }
                    else if (response.Value<string>("callId")
                        == "npc.epoch.timeout.write")
                    {
                        writeTimedOut.Set();
                    }
                });
                task.HandleWebRequest("snapshot", Request("snapshot", "npc.epoch.timeout.old-read"));
                int oldSnapshotFid = (int)sent[0]["callId"];
                Assert.True(oldReadTimedOut.Wait(5000));

                task.HandleWebRequest("tradeCommit", Request("tradeCommit", "npc.epoch.timeout.write"));
                Assert.True(writeTimedOut.Wait(5000));
                Assert.Equal("needs_reconcile", task.WriteState);

                task.HandleFlashResponse(StateResponse(oldSnapshotFid), null);
                Assert.Equal("needs_reconcile", task.WriteState);

                task.HandleWebRequest("snapshot", Request("snapshot", "npc.epoch.timeout.new-read"));
                int newSnapshotFid = (int)sent[sent.Count - 1]["callId"];
                task.HandleFlashResponse(StateResponse(newSnapshotFid), null);
                Assert.Equal("idle", task.WriteState);
            }
        }

        [Fact]
        public void AuthoritativeTradeCommitSuccess_ReopensWriteGate()
        {
            string sent = null;
            var task = new NpcShopTask(() => true, json => { sent = json; return true; });
            PrimeTrade(task, () => ParseSent(sent));
            task.HandleWebRequest("tradeCommit", Request("tradeCommit", "npc.trade.success.1"));
            int fid = (int)ParseSent(sent)["callId"];

            task.HandleFlashResponse(StateResponse(fid, "tradeCommit"), _ => { });

            Assert.Equal("idle", task.WriteState);
        }

        [Theory]
        [InlineData("batchSell", "expectedBatchToken", "npcbatch10.1")]
        [InlineData("tradeCommit", "expectedTradeToken", "npctrade10.1")]
        public void PreviewBackedWrite_LogManagerCaptureNeverContainsRawAuthorityToken(
            string cmd,
            string tokenKey,
            string secret)
        {
            var sent = new List<JObject>();
            var logs = new List<string>();
            LogManager.SetSink(logs.Add);
            try
            {
                using (var task = new NpcShopTask(
                    () => true,
                    value =>
                    {
                        sent.Add(ParseSent(value));
                        return true;
                    }))
                {
                    if (cmd == "batchSell")
                        PrimeBatch(task, () => sent[sent.Count - 1]);
                    else
                        PrimeTrade(task, () => sent[sent.Count - 1]);
                    logs.Clear();
                    task.HandleWebRequest(cmd, Request(
                        cmd, "npc.log-redaction." + cmd));
                }
            }
            finally
            {
                LogManager.ResetSink();
            }

            string flashLog = Assert.Single(logs,
                value => value.Contains("[NpcShopTask] -> Flash:"));
            JObject command = sent[sent.Count - 1];
            string binding = Assert.Single(logs,
                value => value.StartsWith(
                    "event=authority_flash_call_bound ",
                    StringComparison.Ordinal));
            Assert.Equal(
                "event=authority_flash_call_bound domain=npcshop"
                + " webCallId=npc.log-redaction." + cmd
                + " flashCallId=" + (int)command["callId"]
                + " panel=npcshop panelInstanceId=" + OwnerA
                + " cmd=" + cmd + " action=" + (cmd == "batchSell"
                    ? "npcShopBatchSell" : "npcShopTradeCommit"),
                binding);
            Assert.Contains(tokenKey + "Ref="
                + AuthorityLogFormatter.CreateReference(secret), flashLog);
            Assert.All(logs, value => Assert.DoesNotContain(secret, value));
        }

        [Fact]
        public void MaterialShopLease_RequiresLiveCatalogAndFencesAllDomainRequests()
        {
            var sent = new List<JObject>();
            string web = null;
            using (var task = new NpcShopTask(
                () => true,
                value =>
                {
                    sent.Add(ParseSent(value));
                    return true;
                }))
            {
                task.SetPostToWeb(value => web = value);
                PrimeCatalog(task, () => sent[sent.Count - 1]);
                task.BindMaterialShopNavigationOwner("npcshop", OwnerA);

                Assert.False(task.TryAcquireMaterialShopNavigationLease(
                    "npcshop", OwnerA, "lease.wrong-shop", "漂移商店", out _));
                Assert.True(task.TryAcquireMaterialShopNavigationLease(
                    "npcshop", OwnerA, "lease.npcshop.material-shop", "前治安官",
                    out MaterialShopSettlementWitness witness));
                int sends = sent.Count;

                task.HandleWebRequest(
                    "snapshot",
                    Request("snapshot", "lease.npcshop.blocked"));

                Assert.Equal(sends, sent.Count);
                Assert.Equal("busy", JObject.Parse(web).Value<string>("error"));
                Assert.True(task.IsMaterialShopNavigationLeaseCurrent(witness));

                JObject rejectedBeforeParsing = Request(
                    "snapshot",
                    "lease.npcshop.rejected.not-recorded");
                rejectedBeforeParsing["domain"] = "wrong-domain";
                task.HandleWebRequest("snapshot", rejectedBeforeParsing);
                Assert.Equal("busy", JObject.Parse(web).Value<string>("error"));
                Assert.True(task.ReleaseMaterialShopNavigationLease(witness));
                rejectedBeforeParsing["domain"] = "npcshop";
                task.HandleWebRequest("snapshot", rejectedBeforeParsing);
                Assert.Equal(sends + 1, sent.Count);
                task.HandleFlashResponse(
                    StateResponse(sent[sent.Count - 1].Value<int>("callId")),
                    null);

                task.BindMaterialShopNavigationOwner("crafting", "panel.crafting.return");
                Assert.False(task.IsMaterialShopNavigationLeaseCurrent(witness));
                task.BindMaterialShopNavigationOwner("npcshop", OwnerA);
                Assert.True(task.TryAcquireMaterialShopNavigationLease(
                    "npcshop", OwnerA, "lease.npcshop.after-drift", "前治安官",
                    out _));
            }
        }
    }
}
