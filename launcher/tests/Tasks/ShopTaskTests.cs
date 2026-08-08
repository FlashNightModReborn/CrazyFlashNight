using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Threading;
using Newtonsoft.Json.Linq;
using Xunit;
using CF7Launcher.Guardian;
using CF7Launcher.Tasks;
using CF7Launcher.Tests.Contracts;

namespace CF7Launcher.Tests.Tasks
{
    public class ShopTaskTests
    {
        private const string OwnerA = "panel.kshop.owner-a";
        private const string OwnerB = "panel.kshop.owner-b";

        private static JObject Request(string json, string owner = OwnerA)
        {
            var request = JObject.Parse(json);
            request["panel"] = "kshop";
            request["panelInstanceId"] = owner;
            return request;
        }

        private static JObject Own(JObject request, string owner = OwnerA)
        {
            request["panel"] = "kshop";
            request["panelInstanceId"] = owner;
            return request;
        }

        private static void AssertOwner(JObject response, string cmd, string owner = OwnerA)
        {
            Assert.Equal("kshop", (string)response["panel"]);
            Assert.Equal(owner, (string)response["panelInstanceId"]);
            Assert.Equal(cmd, (string)response["cmd"]);
            Assert.Null(response["domain"]);
        }

        private static JObject ParseSent(string payload)
        {
            return JObject.Parse(payload.TrimEnd('\0'));
        }

        private static JObject CatalogItem()
        {
            return new JObject
            {
                ["idx"] = 0,
                ["id"] = "catalog.alpha",
                ["item"] = "rule.alpha",
                ["type"] = "测试专柜",
                ["price"] = 10,
                ["displayname"] = "展示 Beta",
                ["majorType"] = "消耗品",
                ["subType"] = "药剂",
                ["actionType"] = "",
                ["weaponType"] = "",
                ["setId"] = "",
                ["setName"] = "",
                ["setOrder"] = 0,
                ["level"] = 1,
                ["icon"] = "icon.gamma",
                ["maxQuantity"] = 999999
            };
        }

        private static JArray PurchasedLegacy()
        {
            return new JArray
            {
                new JArray(
                    "catalog.alpha", "rule.alpha", "测试专柜", 10, 2)
            };
        }

        private static JArray PurchasedView()
        {
            return new JArray(new JObject
            {
                ["purchasedIdx"] = 0,
                ["item"] = "rule.alpha",
                ["displayname"] = "展示 Beta",
                ["icon"] = "icon.gamma",
                ["quantity"] = 2
            });
        }

        private static JObject CheckoutLine(int quantity = 1)
        {
            return new JObject
            {
                ["catalogIndex"] = 0,
                ["itemName"] = "rule.alpha",
                ["displayName"] = "展示 Beta",
                ["icon"] = "icon.gamma",
                ["quantity"] = quantity,
                ["unitPrice"] = 10,
                ["total"] = 10 * quantity,
                ["maxQuantity"] = 999999,
                ["maxAffordable"] = 10,
                ["maxByCapacity"] = 999999,
                ["maxPurchasable"] = 10,
                ["itemKind"] = "stack"
            };
        }

        private static JObject ResponseFor(string payload, bool success, string error = null)
        {
            var sent = ParseSent(payload);
            var response = new JObject
            {
                ["task"] = "shop_response",
                ["callId"] = (int)sent["callId"],
                ["success"] = success
            };
            if (error != null) response["error"] = error;
            if (!success && (string)sent["action"] == "shopClaim")
                response["purchasedToken"] = "shop.test.1";
            if (success && (string)sent["action"] == "shopSaveCart")
            {
                response["v"] = 1;
                response["cart"] = sent["cart"] != null
                    ? sent["cart"].DeepClone() : new JArray();
            }
            if (success && (string)sent["action"] == "shopBulkQuery")
            {
                response["catalog"] = new JArray(CatalogItem());
                response["cart"] = new JArray();
                response["cartAdjusted"] = false;
                response["purchased"] = PurchasedLegacy();
                response["purchasedView"] = PurchasedView();
                response["kpoints"] = 100;
                response["playerLevel"] = 20;
                response["reverseLevel"] = 0;
                response["purchasedToken"] = "shop.test.1";
            }
            if (success && (string)sent["action"] == "shopCheckout")
            {
                int quantity = sent["cart"] is JArray legacyCart && legacyCart.Count > 0
                    ? legacyCart[0].Value<int>("qty") : 1;
                response["v"] = 1;
                response["newBalance"] = 100 - 10 * quantity;
                response["delivered"] = new JArray(CheckoutLine(quantity));
                response["cart"] = new JArray();
                response["purchased"] = PurchasedLegacy();
                response["purchasedView"] = PurchasedView();
                response["catalog"] = new JArray(CatalogItem());
                response["purchasedToken"] = "shop.test.1";
            }
            if (success && (string)sent["action"] == "shopCheckoutPreview")
            {
                int quantity = sent["cart"] is JArray previewCart && previewCart.Count > 0
                    ? previewCart[0].Value<int>("qty") : 1;
                int total = 10 * quantity;
                response["v"] = 1;
                response["checkoutToken"] = "kcheckout.test.1";
                response["purchaseLines"] = new JArray(CheckoutLine(quantity));
                response["total"] = total;
                response["balance"] = 100;
                response["projectedBalance"] = 100 - total;
                response["canCommit"] = total <= 100;
                response["blockingError"] = total <= 100 ? "" : "insufficient_kpoints";
            }
            if (success && (string)sent["action"] == "shopCheckoutCommit")
            {
                response["v"] = 1;
                response["newBalance"] = 90;
                response["delivered"] = new JArray(CheckoutLine());
                response["cart"] = new JArray();
                response["purchased"] = PurchasedLegacy();
                response["purchasedView"] = PurchasedView();
                response["catalog"] = new JArray(CatalogItem());
                response["purchasedToken"] = "shop.test.1";
            }
            if (success && (string)sent["action"] == "shopClaim")
            {
                response["purchased"] = new JArray();
                response["purchasedView"] = new JArray();
                response["catalog"] = new JArray(CatalogItem());
                response["purchasedToken"] = "shop.test.2";
            }
            return response;
        }

        private static void SeedBulk(ShopTask task, List<string> sent,
            string callId = "seed.bulk")
        {
            task.HandleWebRequest("bulkQuery", Request("{\"callId\":\"" + callId + "\"}"));
            string payload = sent[sent.Count - 1];
            task.HandleFlashResponse(ResponseFor(payload, true), _ => { });
        }

        private static string SeedPreview(ShopTask task, List<string> sent,
            string prefix = "seed.preview")
        {
            SeedBulk(task, sent, prefix + ".bulk");
            task.HandleWebRequest("checkoutPreview", Request(
                "{\"callId\":\"" + prefix + ".request\",\"v\":1,\"cart\":[{\"idx\":0,\"qty\":1}]}"));
            string payload = sent[sent.Count - 1];
            task.HandleFlashResponse(ResponseFor(payload, true), _ => { });
            return "kcheckout.test.1";
        }

        private static void BeginWrite(ShopTask task, List<string> sent,
            string cmd, string callId = "target.write")
        {
            if (cmd == "checkoutCommit")
            {
                string token = SeedPreview(task, sent, callId + ".seed");
                task.HandleWebRequest(cmd, Request(
                    "{\"callId\":\"" + callId + "\",\"v\":1,\"expectedCheckoutToken\":\"" + token + "\"}"));
                return;
            }
            if (cmd == "claim")
            {
                SeedBulk(task, sent, callId + ".seed");
                task.HandleWebRequest(cmd, Request(
                    "{\"callId\":\"" + callId + "\",\"purchasedIdx\":0,\"expectedPurchasedToken\":\"shop.test.1\"}"));
                return;
            }
            if (cmd == "checkout")
                SeedBulk(task, sent, callId + ".seed");
            task.HandleWebRequest(cmd, Request(
                "{\"callId\":\"" + callId + "\",\"cart\":[{\"idx\":0,\"qty\":1}]}"));
        }

        [Fact]
        public void HandleWebRequest_Disconnected_ReturnsExactOwnerError()
        {
            string posted = null;
            var task = new ShopTask(() => false, _ => true);
            task.SetPostToWeb(json => posted = json);

            task.HandleWebRequest("bulkQuery", Request("{\"callId\":\"wb.s.1.1\"}"));

            var response = JObject.Parse(posted);
            Assert.Equal("panel_resp", (string)response["type"]);
            Assert.Equal("wb.s.1.1", (string)response["callId"]);
            Assert.Equal("disconnected", (string)response["error"]);
            AssertOwner(response, "bulkQuery");
        }

        [Theory]
        [InlineData("bulkQuery", "shopBulkQuery")]
        [InlineData("tooltip", "shopTooltip")]
        [InlineData("saveCart", "shopSaveCart")]
        [InlineData("checkoutPreview", "shopCheckoutPreview")]
        [InlineData("checkoutCommit", "shopCheckoutCommit")]
        [InlineData("checkout", "shopCheckout")]
        [InlineData("claim", "shopClaim")]
        public void HandleWebRequest_KnownCommand_ForwardsTrustedAction(string cmd, string action)
        {
            var sent = new List<string>();
            var task = new ShopTask(() => true, payload => { sent.Add(payload); return true; });
            var request = Request("{\"callId\":\"wb.s.1.1\"}");
            if (cmd == "tooltip") request["idx"] = 0;
            if (cmd == "saveCart" || cmd == "checkout")
                request["cart"] = new JArray(
                    new JObject { ["idx"] = 0, ["qty"] = 2 });
            if (cmd == "checkoutPreview")
            {
                request["v"] = 1;
                request["cart"] = new JArray(
                    new JObject { ["idx"] = 0, ["qty"] = 2 });
            }
            if (cmd == "checkoutCommit")
            {
                request["v"] = 1;
                request["expectedCheckoutToken"] = SeedPreview(task, sent);
            }
            if (cmd == "claim")
            {
                SeedBulk(task, sent);
                request["purchasedIdx"] = 0;
                request["expectedPurchasedToken"] = "shop.test.1";
            }
            if (cmd == "tooltip" || cmd == "saveCart"
                || cmd == "checkoutPreview" || cmd == "checkout")
                SeedBulk(task, sent, "known." + cmd + ".bulk");
            request["action"] = "evil";
            request["task"] = "evil";
            int before = sent.Count;

            task.HandleWebRequest(cmd, request);

            Assert.Equal(before + 1, sent.Count);
            var message = ParseSent(sent[sent.Count - 1]);
            Assert.Equal("cmd", (string)message["task"]);
            Assert.Equal(action, (string)message["action"]);
            if (cmd == "saveCart" || cmd == "checkout" || cmd == "checkoutPreview")
                Assert.Equal(2, (int)message["cart"][0]["qty"]);
            Assert.Null(message["cmd"]);
            Assert.Null(message["panel"]);
            Assert.Null(message["panelInstanceId"]);
            Assert.Null(message["domain"]);
        }

        [Fact]
        public void KShopDomainMustBeCompletelyAbsentBeforeFlashDispatch()
        {
            var sent = new List<string>();
            var posted = new List<JObject>();
            using var task = new ShopTask(
                () => true,
                payload => { sent.Add(payload); return true; });
            task.SetPostToWeb(json => posted.Add(JObject.Parse(json)));

            JToken[] invalidDomains =
            {
                JValue.CreateString(""),
                JValue.CreateNull(),
                new JObject(),
                JValue.CreateString("inventory")
            };
            for (int i = 0; i < invalidDomains.Length; i++)
            {
                JObject request = Request(
                    "{\"callId\":\"wb.domain." + i + "\"}");
                request["domain"] = invalidDomains[i];
                task.HandleWebRequest("bulkQuery", request);
            }

            Assert.Empty(sent);
            Assert.Equal(invalidDomains.Length, posted.Count);
            Assert.All(posted, response =>
            {
                Assert.Equal("invalid_domain", (string)response["error"]);
                AssertOwner(response, "bulkQuery");
            });

            task.HandleWebRequest(
                "bulkQuery",
                Request("{\"callId\":\"wb.domain.absent\"}"));
            JObject flash = ParseSent(Assert.Single(sent));
            Assert.Null(flash["domain"]);
        }

        [Theory]
        [MemberData(nameof(PanelContractVectors.KShopPurchaseQuantityAll), MemberType = typeof(PanelContractVectors))]
        public void CheckoutQuantity_IsPassedThroughForFlashAuthorityToJudge(int quantity)
        {
            var sent = new List<string>();
            using (var task = new ShopTask(
                () => true,
                payload => { sent.Add(payload); return true; }))
            {
                SeedBulk(task, sent, "shop.quantity.seed." + quantity);
                var request = new JObject
                {
                    ["callId"] = "shop.quantity." + quantity,
                    ["v"] = 1,
                    ["cart"] = new JArray(new JObject { ["idx"] = 0, ["qty"] = quantity })
                };

                task.HandleWebRequest("checkoutPreview", Own(request));

                Assert.Equal(quantity,
                    (int)ParseSent(sent[sent.Count - 1])["cart"][0]["qty"]);
            }
        }

        [Fact]
        public void HandleWebRequest_UnsupportedAndInvalidCallId_DoNotReachFlash()
        {
            int sendCount = 0;
            var posted = new List<JObject>();
            var task = new ShopTask(() => true, _ => { sendCount++; return true; });
            task.SetPostToWeb(json => posted.Add(JObject.Parse(json)));

            task.HandleWebRequest("bogus", Request("{\"callId\":\"wb.s.1.1\"}"));
            task.HandleWebRequest("bulkQuery", Request("{\"callId\":\"bad call id\"}"));

            Assert.Equal(0, sendCount);
            Assert.Equal("unsupported_cmd", (string)posted[0]["error"]);
            Assert.Equal("invalid_call_id", (string)posted[1]["error"]);
            AssertOwner(posted[0], "bogus");
            AssertOwner(posted[1], "bulkQuery");
        }

        [Fact]
        public void WriteGate_RejectsSecondWriteBusy_ThenReleasesOnDefinitiveResponse()
        {
            var sent = new List<string>();
            var posted = new List<JObject>();
            var task = new ShopTask(() => true, payload => { sent.Add(payload); return true; });
            task.SetPostToWeb(json => posted.Add(JObject.Parse(json)));

            task.HandleWebRequest("saveCart", Request("{\"callId\":\"wb.s.1.1\",\"cart\":[]}"));
            task.HandleWebRequest("checkout", Request("{\"callId\":\"wb.s.1.2\",\"cart\":[]}"));

            Assert.Single(sent);
            Assert.Equal("busy", (string)posted[0]["error"]);
            AssertOwner(posted[0], "checkout");

            task.HandleFlashResponse(ResponseFor(sent[0], true), _ => { });
            task.HandleWebRequest("saveCart", Request("{\"callId\":\"wb.s.1.3\",\"cart\":[]}"));
            Assert.Equal(2, sent.Count);
        }

        [Fact]
        public void Timeout_RequiresNewSuccessfulBulkQueryBeforeAnotherWrite()
        {
            var sent = new ConcurrentQueue<string>();
            var posted = new ConcurrentQueue<JObject>();
            using var timeoutPosted = new ManualResetEventSlim(false);
            var task = new ShopTask(
                () => true,
                payload => { sent.Enqueue(payload); return true; },
                25);
            task.SetPostToWeb(json =>
            {
                var message = JObject.Parse(json);
                posted.Enqueue(message);
                if ((string)message["error"] == "timeout") timeoutPosted.Set();
            });

            task.HandleWebRequest("saveCart", Request("{\"callId\":\"wb.s.1.1\",\"cart\":[]}"));
            Assert.True(timeoutPosted.Wait(TimeSpan.FromSeconds(2)), "write timeout response was not posted");
            Assert.Contains(posted, item => (string)item["callId"] == "wb.s.1.1"
                && (string)item["panel"] == "kshop"
                && (string)item["panelInstanceId"] == OwnerA
                && (string)item["cmd"] == "saveCart"
                && item["domain"] == null);

            task.HandleWebRequest("claim", Request(
                "{\"callId\":\"wb.s.1.2\",\"purchasedIdx\":0,\"expectedPurchasedToken\":\"shop.unknown.1\"}"));
            Assert.Contains(posted, item => (string)item["callId"] == "wb.s.1.2" && (string)item["error"] == "reconcile_required");

            task.HandleWebRequest("bulkQuery", Request("{\"callId\":\"wb.s.1.3\"}"));
            Assert.True(sent.TryPeek(out _));
            string[] sentArray = sent.ToArray();
            task.HandleFlashResponse(ResponseFor(sentArray[sentArray.Length - 1], true), _ => { });

            int before = sent.Count;
            task.HandleWebRequest("claim", Request(
                "{\"callId\":\"wb.s.1.4\",\"purchasedIdx\":0,\"expectedPurchasedToken\":\"shop.test.1\"}"));
            Assert.Equal(before + 1, sent.Count);
        }

        [Fact]
        public void DisconnectWithWritePending_PreservesReconcileGate()
        {
            var sent = new List<string>();
            var posted = new List<JObject>();
            var task = new ShopTask(() => true, payload => { sent.Add(payload); return true; });
            task.SetPostToWeb(json => posted.Add(JObject.Parse(json)));

            BeginWrite(task, sent, "claim", "wb.s.1.1");
            posted.Clear();
            task.ClearPending();
            task.HandleWebRequest("saveCart", Request("{\"callId\":\"wb.s.2.1\",\"cart\":[]}", OwnerB));

            Assert.Equal("reconcile_required", (string)posted[0]["error"]);
            AssertOwner(posted[0], "saveCart", OwnerB);
            task.HandleWebRequest("bulkQuery", Request("{\"callId\":\"wb.s.2.2\"}", OwnerB));
            task.HandleFlashResponse(ResponseFor(sent[sent.Count - 1], true), _ => { });

            int before = sent.Count;
            task.HandleWebRequest("saveCart", Request("{\"callId\":\"wb.s.2.3\",\"cart\":[]}", OwnerB));
            Assert.Equal(before + 1, sent.Count);
        }

        [Theory]
        [InlineData("checkoutCommit")]
        [InlineData("checkout")]
        [InlineData("claim")]
        public void MalformedSuccessfulWriteResponse_IsRewrittenToReconcileRequired(string cmd)
        {
            var sent = new List<string>();
            string posted = null;
            var task = new ShopTask(() => true, payload => { sent.Add(payload); return true; });
            task.SetPostToWeb(json => posted = json);

            BeginWrite(task, sent, cmd, "wb.s.1.1");
            string target = sent[sent.Count - 1];
            var malformed = new JObject
            {
                ["task"] = "shop_response",
                ["callId"] = (int)ParseSent(target)["callId"],
                ["success"] = true
            };
            task.HandleFlashResponse(malformed, _ => { });

            var response = JObject.Parse(posted);
            Assert.False((bool)response["success"]);
            Assert.Equal("reconcile_required", (string)response["error"]);
            Assert.Equal("invalid_response", (string)response["cause"]);
        }

        [Theory]
        [InlineData("checkoutCommit")]
        [InlineData("claim")]
        public void SuccessfulInventoryWriteWithoutRefreshedCatalog_RequiresReconcile(string cmd)
        {
            var sent = new List<string>();
            string posted = null;
            var task = new ShopTask(() => true, payload => { sent.Add(payload); return true; });
            task.SetPostToWeb(json => posted = json);

            BeginWrite(task, sent, cmd, "wb.s.1.1");
            string target = sent[sent.Count - 1];
            var malformed = ResponseFor(target, true);
            malformed.Remove("catalog");
            task.HandleFlashResponse(malformed, _ => { });

            var response = JObject.Parse(posted);
            Assert.False((bool)response["success"]);
            Assert.Equal("reconcile_required", (string)response["error"]);
        }

        [Fact]
        public void MalformedBulkQuery_DoesNotUnlockReconcileGate()
        {
            var sent = new List<string>();
            var posted = new List<JObject>();
            var task = new ShopTask(() => true, payload => { sent.Add(payload); return true; });
            task.SetPostToWeb(json => posted.Add(JObject.Parse(json)));

            SeedBulk(task, sent, "wb.s.reconcile.seed");
            sent.Clear();
            posted.Clear();
            task.HandleWebRequest("checkout", Request(
                "{\"callId\":\"wb.s.1.1\",\"cart\":[{\"idx\":0,\"qty\":1}]}"));
            task.HandleFlashResponse(new JObject
            {
                ["task"] = "shop_response",
                ["callId"] = (int)ParseSent(sent[0])["callId"],
                ["success"] = true
            }, _ => { });

            task.HandleWebRequest("bulkQuery", Request("{\"callId\":\"wb.s.1.2\"}"));
            task.HandleFlashResponse(new JObject
            {
                ["task"] = "shop_response",
                ["callId"] = (int)ParseSent(sent[sent.Count - 1])["callId"],
                ["success"] = true
            }, _ => { });
            task.HandleWebRequest("checkout", Request("{\"callId\":\"wb.s.1.3\",\"cart\":[]}"));

            Assert.Contains(posted, item => (string)item["callId"] == "wb.s.1.2" && (string)item["error"] == "invalid_response");
            Assert.Contains(posted, item => (string)item["callId"] == "wb.s.1.3" && (string)item["error"] == "reconcile_required");
            Assert.Equal(2, sent.Count);
        }

        [Theory]
        [InlineData("checkoutCommit", "insufficient_kpoints")]
        [InlineData("checkoutCommit", "inventory_full")]
        [InlineData("checkoutCommit", "stale_state")]
        [InlineData("checkout", "insufficient_kpoints")]
        [InlineData("claim", "item_not_found")]
        [InlineData("claim", "inventory_full")]
        [InlineData("claim", "acquire_failed")]
        [InlineData("claim", "stale_state")]
        public void KnownNoWriteFailure_ReleasesHostWriteGate(string cmd, string error)
        {
            var sent = new List<string>();
            var task = new ShopTask(() => true, payload => { sent.Add(payload); return true; });

            BeginWrite(task, sent, cmd, "wb.s.1.1");
            string target = sent[sent.Count - 1];
            task.HandleFlashResponse(ResponseFor(target, false, error), _ => { });

            int before = sent.Count;
            task.HandleWebRequest("saveCart", Request("{\"callId\":\"wb.s.1.2\",\"cart\":[]}"));
            Assert.Equal(before + 1, sent.Count);
        }

        [Fact]
        public void DuplicateActiveAndRecentCallId_AreNeverForwardedTwice()
        {
            var sent = new List<string>();
            var task = new ShopTask(() => true, payload => { sent.Add(payload); return true; });
            var request = Request("{\"callId\":\"wb.s.1.1\"}");

            task.HandleWebRequest("bulkQuery", request);
            task.HandleWebRequest("bulkQuery", request);
            Assert.Single(sent);

            task.HandleFlashResponse(ResponseFor(sent[0], true), _ => { });
            task.HandleWebRequest("bulkQuery", request);
            Assert.Single(sent);
        }

        [Fact]
        public void SendFailureForWrite_EntersReconcileGate()
        {
            var posted = new List<JObject>();
            var task = new ShopTask(() => true, _ => false);
            task.SetPostToWeb(json => posted.Add(JObject.Parse(json)));

            task.HandleWebRequest("saveCart", Request("{\"callId\":\"wb.s.1.1\",\"cart\":[]}"));
            task.HandleWebRequest("checkout", Request("{\"callId\":\"wb.s.1.2\",\"cart\":[]}"));

            Assert.Equal("reconcile_required", (string)posted[0]["error"]);
            Assert.Equal("reconcile_required", (string)posted[1]["error"]);
            AssertOwner(posted[0], "saveCart");
            AssertOwner(posted[1], "checkout");
        }

        [Fact]
        public void FlashResponse_RestoresExactFrozenOwnerTuple()
        {
            string sent = null;
            string posted = null;
            var task = new ShopTask(() => true, payload => { sent = payload; return true; });
            task.SetPostToWeb(json => posted = json);

            task.HandleWebRequest("bulkQuery", Request("{\"callId\":\"wb.session.3.7\"}"));
            task.HandleFlashResponse(ResponseFor(sent, true), _ => { });

            var response = JObject.Parse(posted);
            Assert.Equal("wb.session.3.7", (string)response["callId"]);
            Assert.Null(response["task"]);
            AssertOwner(response, "bulkQuery");
        }

        [Fact]
        public void SameNameRebind_DropsLateAAndProjectsExactB()
        {
            var sent = new List<string>();
            var posted = new List<JObject>();
            var task = new ShopTask(() => true, payload => { sent.Add(payload); return true; });
            task.SetPostToWeb(json => posted.Add(JObject.Parse(json)));

            task.HandleWebRequest("bulkQuery",
                Request("{\"callId\":\"wb.owner-a.1\"}", OwnerA));
            string oldRequest = sent[0];
            task.ClearPending();
            task.HandleWebRequest("bulkQuery",
                Request("{\"callId\":\"wb.owner-b.1\"}", OwnerB));
            string currentRequest = sent[1];

            task.HandleFlashResponse(ResponseFor(oldRequest, true), _ => { });
            Assert.Empty(posted);

            task.HandleFlashResponse(ResponseFor(currentRequest, true), _ => { });
            var response = Assert.Single(posted);
            Assert.Equal("wb.owner-b.1", (string)response["callId"]);
            AssertOwner(response, "bulkQuery", OwnerB);
        }

        [Fact]
        public void MissingOwnerTuple_IsRejectedBeforeFlash()
        {
            int sent = 0;
            int posted = 0;
            var task = new ShopTask(() => true, _ => { sent++; return true; });
            task.SetPostToWeb(_ => posted++);

            task.HandleWebRequest("bulkQuery", JObject.Parse("{\"callId\":\"wb.no-owner.1\"}"));

            Assert.Equal(0, sent);
            Assert.Equal(0, posted);
        }

        [Fact]
        public void CheckoutPreview_MalformedSuccess_CannotAuthorizeCommit()
        {
            var sent = new List<string>();
            var posted = new List<JObject>();
            var task = new ShopTask(() => true, payload => { sent.Add(payload); return true; });
            task.SetPostToWeb(json => posted.Add(JObject.Parse(json)));

            SeedBulk(task, sent, "wb.s.preview.seed");
            sent.Clear();
            posted.Clear();
            task.HandleWebRequest("checkoutPreview", Request(
                "{\"callId\":\"wb.s.1.1\",\"v\":1,\"cart\":[{\"idx\":0,\"qty\":1}]}"));
            task.HandleFlashResponse(new JObject
            {
                ["task"] = "shop_response",
                ["callId"] = (int)ParseSent(sent[0])["callId"],
                ["success"] = true
            }, _ => { });
            task.HandleWebRequest("checkoutCommit", Request(
                "{\"callId\":\"wb.s.1.2\",\"v\":1,\"expectedCheckoutToken\":\"x\"}"));

            Assert.Equal("invalid_response", (string)posted[0]["error"]);
            Assert.Single(sent);
            Assert.Equal("stale_state", (string)posted[1]["error"]);
        }

        [Fact]
        public void ExactRequestContract_RejectsExtraKeysAndWrongScalarTypesBeforeFlash()
        {
            var sent = new List<string>();
            var posted = new List<JObject>();
            var task = new ShopTask(
                () => true,
                payload => { sent.Add(payload); return true; });
            task.SetPostToWeb(json => posted.Add(JObject.Parse(json)));

            task.HandleWebRequest("bulkQuery", Request(
                "{\"callId\":\"shop.bad.extra\",\"extra\":true}"));
            task.HandleWebRequest("checkoutCommit", Request(
                "{\"callId\":\"shop.bad.commit-token\",\"v\":1,\"expectedCheckoutToken\":7}"));
            task.HandleWebRequest("claim", Request(
                "{\"callId\":\"shop.bad.claim-token\",\"purchasedIdx\":0,\"expectedPurchasedToken\":true}"));
            task.HandleWebRequest("checkoutPreview", Request(
                "{\"callId\":\"shop.bad.quantity\",\"v\":1,\"cart\":[{\"idx\":0,\"qty\":\"1\"}]}"));

            Assert.Empty(sent);
            Assert.Equal(4, posted.Count);
            Assert.All(posted, response =>
                Assert.Equal("invalid_payload", (string)response["error"]));
        }

        [Fact]
        public void BulkIdentityTriple_IsProjectedWithoutInternalNameFallback()
        {
            var sent = new List<string>();
            string posted = null;
            var task = new ShopTask(
                () => true,
                payload => { sent.Add(payload); return true; });
            task.SetPostToWeb(json => posted = json);

            task.HandleWebRequest("bulkQuery", Request(
                "{\"callId\":\"shop.triple.bulk\"}"));
            task.HandleFlashResponse(ResponseFor(sent[0], true), _ => { });

            JObject response = JObject.Parse(posted);
            JObject catalog = (JObject)response["catalog"][0];
            JObject purchased = (JObject)response["purchased"][0];
            Assert.Equal("rule.alpha", (string)catalog["item"]);
            Assert.Equal("展示 Beta", (string)catalog["displayname"]);
            Assert.Equal("icon.gamma", (string)catalog["icon"]);
            Assert.Equal("rule.alpha", (string)purchased["item"]);
            Assert.Equal("展示 Beta", (string)purchased["displayname"]);
            Assert.Equal("icon.gamma", (string)purchased["icon"]);
            Assert.NotEqual((string)purchased["item"], (string)purchased["displayname"]);
            Assert.NotEqual((string)purchased["item"], (string)purchased["icon"]);
            Assert.NotEqual((string)purchased["displayname"], (string)purchased["icon"]);
        }

        [Fact]
        public void BulkAuthority_RejectsUnnormalizedLegacyNumericStrings()
        {
            var sent = new List<string>();
            var posted = new List<JObject>();
            var task = new ShopTask(
                () => true,
                payload => { sent.Add(payload); return true; });
            task.SetPostToWeb(json => posted.Add(JObject.Parse(json)));
            task.HandleWebRequest("bulkQuery", Request(
                "{\"callId\":\"shop.legacy-string.bulk\"}"));
            JObject response = ResponseFor(sent[0], true);
            response["purchased"][0][3] = "10";
            response["purchased"][0][4] = "2";

            task.HandleFlashResponse(response, _ => { });

            Assert.Equal("invalid_response", (string)posted[0]["error"]);
            int before = sent.Count;
            task.HandleWebRequest("claim", Request(
                "{\"callId\":\"shop.legacy-string.claim\",\"purchasedIdx\":0,"
                + "\"expectedPurchasedToken\":\"shop.test.1\"}"));
            Assert.Equal(before, sent.Count);
            Assert.Equal("stale_state", (string)posted[1]["error"]);
        }

        [Fact]
        public void BulkAuthority_RejectsMalformedIdentityLeaves()
        {
            for (int variant = 0; variant < 6; variant++)
            {
                var sent = new List<string>();
                var posted = new List<JObject>();
                var task = new ShopTask(
                    () => true,
                    payload => { sent.Add(payload); return true; });
                task.SetPostToWeb(json => posted.Add(JObject.Parse(json)));
                task.HandleWebRequest("bulkQuery", Request(
                    "{\"callId\":\"shop.bad.bulk." + variant + "\"}"));
                JObject response = ResponseFor(sent[0], true);
                JObject item = (JObject)response["catalog"][0];
                if (variant == 0) item["unexpected"] = true;
                else if (variant == 1) item["displayname"] = 42;
                else if (variant == 2) item.Remove("displayname");
                else if (variant == 3) item.Remove("icon");
                else if (variant == 4) item["displayname"] = "   ";
                else item["icon"] = " Undefined ";

                task.HandleFlashResponse(response, _ => { });

                Assert.Equal("invalid_response", (string)posted[0]["error"]);
                int before = sent.Count;
                task.HandleWebRequest("tooltip", Request(
                    "{\"callId\":\"shop.bad.bulk.tooltip." + variant + "\",\"idx\":0}"));
                Assert.Equal(before, sent.Count);
                Assert.Equal("stale_state", (string)posted[1]["error"]);
            }
        }

        [Fact]
        public void SelectorAdmission_RequiresFreshAuthorityAndKnownIndices()
        {
            var sent = new List<string>();
            var posted = new List<JObject>();
            var task = new ShopTask(
                () => true,
                payload => { sent.Add(payload); return true; });
            task.SetPostToWeb(json => posted.Add(JObject.Parse(json)));

            task.HandleWebRequest("checkoutPreview", Request(
                "{\"callId\":\"shop.no-seed.preview\",\"v\":1,\"cart\":[{\"idx\":0,\"qty\":1}]}"));
            Assert.Empty(sent);
            Assert.Equal("stale_state", (string)posted[0]["error"]);

            SeedBulk(task, sent, "shop.selector.seed");
            sent.Clear();
            posted.Clear();
            task.HandleWebRequest("checkoutPreview", Request(
                "{\"callId\":\"shop.unknown.preview\",\"v\":1,\"cart\":[{\"idx\":9,\"qty\":1}]}"));
            task.HandleWebRequest("checkout", Request(
                "{\"callId\":\"shop.unknown.checkout\",\"cart\":[{\"idx\":9,\"qty\":1}]}"));
            task.HandleWebRequest("tooltip", Request(
                "{\"callId\":\"shop.unknown.tooltip\",\"idx\":9}"));
            task.HandleWebRequest("claim", Request(
                "{\"callId\":\"shop.unknown.claim\",\"purchasedIdx\":9,\"expectedPurchasedToken\":\"shop.test.1\"}"));

            Assert.Empty(sent);
            Assert.Equal(4, posted.Count);
            Assert.All(posted, response =>
                Assert.Equal("stale_state", (string)response["error"]));
        }

        [Fact]
        public void PreviewAuthority_RejectsNearMatchIdentityAndWrongSelectorEcho()
        {
            for (int variant = 0; variant < 2; variant++)
            {
                var sent = new List<string>();
                var posted = new List<JObject>();
                var task = new ShopTask(
                    () => true,
                    payload => { sent.Add(payload); return true; });
                task.SetPostToWeb(json => posted.Add(JObject.Parse(json)));
                SeedBulk(task, sent, "shop.preview.seed." + variant);
                sent.Clear();
                posted.Clear();
                task.HandleWebRequest("checkoutPreview", Request(
                    "{\"callId\":\"shop.preview.bad." + variant
                    + "\",\"v\":1,\"cart\":[{\"idx\":0,\"qty\":1}]}"));
                JObject response = ResponseFor(sent[0], true);
                JObject line = (JObject)response["purchaseLines"][0];
                if (variant == 0) line["displayName"] = "rule.alpha";
                else line["catalogIndex"] = 1;

                task.HandleFlashResponse(response, _ => { });
                Assert.Equal("invalid_response", (string)posted[0]["error"]);
                int before = sent.Count;
                task.HandleWebRequest("checkoutCommit", Request(
                    "{\"callId\":\"shop.preview.commit." + variant
                    + "\",\"v\":1,\"expectedCheckoutToken\":\"kcheckout.test.1\"}"));
                Assert.Equal(before, sent.Count);
                Assert.Equal("stale_state", (string)posted[1]["error"]);
            }
        }

        [Fact]
        public void SaveCart_AdoptsAuthoritativeClampAndReportsAdjustment()
        {
            var sent = new List<string>();
            var posted = new List<JObject>();
            var task = new ShopTask(
                () => true,
                payload => { sent.Add(payload); return true; });
            task.SetPostToWeb(json => posted.Add(JObject.Parse(json)));
            SeedBulk(task, sent, "shop.save.authority.seed");
            sent.Clear();
            posted.Clear();
            task.HandleWebRequest("saveCart", Request(
                "{\"callId\":\"shop.save.authority\",\"cart\":[{\"idx\":0,\"qty\":2}]}"));
            JObject response = ResponseFor(sent[0], true);
            response["cart"][0]["qty"] = 1;

            task.HandleFlashResponse(response, null);

            Assert.True((bool)posted[0]["success"]);
            Assert.True((bool)posted[0]["adjusted"]);
            Assert.Equal(1, (int)posted[0]["cart"][0]["qty"]);
        }

        [Theory]
        [InlineData("bare_success")]
        [InlineData("added_selector")]
        [InlineData("quantity_increase")]
        [InlineData("extra_leaf")]
        public void SaveCart_InvalidOrUnboundSuccessRequiresReconcile(string mutation)
        {
            var sent = new List<string>();
            var posted = new List<JObject>();
            var task = new ShopTask(
                () => true,
                payload => { sent.Add(payload); return true; });
            task.SetPostToWeb(json => posted.Add(JObject.Parse(json)));
            SeedBulk(task, sent, "shop.save.invalid.seed." + mutation);
            sent.Clear();
            posted.Clear();
            task.HandleWebRequest("saveCart", Request(
                "{\"callId\":\"shop.save.invalid." + mutation
                + "\",\"cart\":[{\"idx\":0,\"qty\":2}]}"));
            JObject response = ResponseFor(sent[0], true);
            if (mutation == "bare_success")
            {
                response.Remove("v");
                response.Remove("cart");
            }
            else if (mutation == "added_selector") response["cart"][0]["idx"] = 1;
            else if (mutation == "quantity_increase") response["cart"][0]["qty"] = 3;
            else response["cart"][0]["unexpected"] = true;

            task.HandleFlashResponse(response, null);

            Assert.Equal("reconcile_required", (string)posted[0]["error"]);
            Assert.Equal("invalid_response", (string)posted[0]["cause"]);
        }

        [Theory]
        [InlineData("item")]
        [InlineData("display")]
        [InlineData("icon")]
        [InlineData("price")]
        public void CheckoutCommit_RefreshedCatalogMustMatchDeliveredIdentityAndPrice(string mutation)
        {
            var sent = new List<string>();
            var posted = new List<JObject>();
            var task = new ShopTask(
                () => true,
                payload => { sent.Add(payload); return true; });
            task.SetPostToWeb(json => posted.Add(JObject.Parse(json)));
            SeedPreview(task, sent, "shop.commit.catalog.seed." + mutation);
            sent.Clear();
            posted.Clear();
            task.HandleWebRequest("checkoutCommit", Request(
                "{\"callId\":\"shop.commit.catalog." + mutation
                + "\",\"v\":1,\"expectedCheckoutToken\":\"kcheckout.test.1\"}"));
            JObject response = ResponseFor(sent[0], true);
            JObject catalog = (JObject)response["catalog"][0];
            if (mutation == "item") catalog["item"] = "rule.near";
            else if (mutation == "display") catalog["displayname"] = "展示 Near";
            else if (mutation == "icon") catalog["icon"] = "icon.near";
            else catalog["price"] = 11;

            task.HandleFlashResponse(response, null);

            Assert.Equal("reconcile_required", (string)posted[0]["error"]);
            Assert.Equal("invalid_response", (string)posted[0]["cause"]);
        }

        [Fact]
        public void CommitPostconditionMismatch_EntersReconcileGate()
        {
            var sent = new List<string>();
            var posted = new List<JObject>();
            var task = new ShopTask(
                () => true,
                payload => { sent.Add(payload); return true; });
            task.SetPostToWeb(json => posted.Add(JObject.Parse(json)));
            SeedPreview(task, sent, "shop.commit.postcondition.seed");
            sent.Clear();
            posted.Clear();
            task.HandleWebRequest("checkoutCommit", Request(
                "{\"callId\":\"shop.commit.postcondition\",\"v\":1,\"expectedCheckoutToken\":\"kcheckout.test.1\"}"));
            JObject response = ResponseFor(sent[0], true);
            response["newBalance"] = 89;

            task.HandleFlashResponse(response, _ => { });

            Assert.Equal("reconcile_required", (string)posted[0]["error"]);
            Assert.Equal("invalid_response", (string)posted[0]["cause"]);
            int before = sent.Count;
            task.HandleWebRequest("saveCart", Request(
                "{\"callId\":\"shop.commit.postcondition.after\",\"cart\":[]}"));
            Assert.Equal(before, sent.Count);
            Assert.Equal("reconcile_required", (string)posted[1]["error"]);
        }

        [Fact]
        public void CheckoutToken_IsSingleUseAfterDefinitiveFailure()
        {
            var sent = new List<string>();
            var posted = new List<JObject>();
            var task = new ShopTask(
                () => true,
                payload => { sent.Add(payload); return true; });
            task.SetPostToWeb(json => posted.Add(JObject.Parse(json)));
            SeedPreview(task, sent, "shop.commit.single-use.seed");
            sent.Clear();
            posted.Clear();
            task.HandleWebRequest("checkoutCommit", Request(
                "{\"callId\":\"shop.commit.single-use.1\",\"v\":1,\"expectedCheckoutToken\":\"kcheckout.test.1\"}"));
            task.HandleFlashResponse(ResponseFor(sent[0], false, "stale_state"), _ => { });
            int before = sent.Count;

            task.HandleWebRequest("checkoutCommit", Request(
                "{\"callId\":\"shop.commit.single-use.2\",\"v\":1,\"expectedCheckoutToken\":\"kcheckout.test.1\"}"));

            Assert.Equal(before, sent.Count);
            Assert.Equal("stale_state", (string)posted[0]["error"]);
            Assert.Equal("stale_state", (string)posted[1]["error"]);
        }

        [Fact]
        public void ClaimSuccess_MustMatchRemoveOnePostconditionAndRotateToken()
        {
            var sent = new List<string>();
            var posted = new List<JObject>();
            var task = new ShopTask(
                () => true,
                payload => { sent.Add(payload); return true; });
            task.SetPostToWeb(json => posted.Add(JObject.Parse(json)));
            SeedBulk(task, sent, "shop.claim.postcondition.seed");
            sent.Clear();
            posted.Clear();
            task.HandleWebRequest("claim", Request(
                "{\"callId\":\"shop.claim.postcondition\",\"purchasedIdx\":0,\"expectedPurchasedToken\":\"shop.test.1\"}"));
            JObject response = ResponseFor(sent[0], true);
            response["purchased"] = PurchasedLegacy();
            response["purchasedView"] = PurchasedView();

            task.HandleFlashResponse(response, _ => { });

            Assert.Equal("reconcile_required", (string)posted[0]["error"]);
            Assert.Equal("invalid_response", (string)posted[0]["cause"]);
        }

        [Fact]
        public void CheckoutCommit_LogManagerCaptureNeverContainsRawAuthorityToken()
        {
            var sent = new List<string>();
            var logs = new List<string>();
            LogManager.SetSink(logs.Add);
            try
            {
                using (var task = new ShopTask(
                    () => true,
                    payload => { sent.Add(payload); return true; }))
                {
                    SeedPreview(task, sent, "shop.log-redaction.seed");
                    logs.Clear();
                    task.HandleWebRequest("checkoutCommit", Request(
                        "{\"callId\":\"shop.log-redaction.commit\",\"v\":1,"
                        + "\"expectedCheckoutToken\":\"kcheckout.test.1\"}"));
                }
            }
            finally
            {
                LogManager.ResetSink();
            }

            string flashLog = Assert.Single(logs,
                value => value.Contains("[ShopTask] -> Flash:"));
            JObject command = JObject.Parse(
                sent[sent.Count - 1].TrimEnd('\0'));
            string binding = Assert.Single(logs,
                value => value.StartsWith(
                    "event=authority_flash_call_bound ",
                    StringComparison.Ordinal));
            Assert.Equal(
                "event=authority_flash_call_bound domain=shop"
                + " webCallId=shop.log-redaction.commit"
                + " flashCallId=" + (int)command["callId"]
                + " panel=kshop panelInstanceId=" + OwnerA
                + " cmd=checkoutCommit action=shopCheckoutCommit",
                binding);
            Assert.Contains("cmd=shopCheckoutCommit", flashLog);
            Assert.Contains("expectedCheckoutTokenRef="
                + AuthorityLogFormatter.CreateReference("kcheckout.test.1"), flashLog);
            Assert.All(logs,
                value => Assert.DoesNotContain("kcheckout.test.1", value));
        }
    }
}
