using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Threading;
using Newtonsoft.Json.Linq;
using Xunit;
using CF7Launcher.Tasks;

namespace CF7Launcher.Tests.Tasks
{
    public class ShopTaskTests
    {
        private static JObject ParseSent(string payload)
        {
            return JObject.Parse(payload.TrimEnd('\0'));
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
            if (success && (string)sent["action"] == "shopBulkQuery")
            {
                response["catalog"] = new JArray();
                response["cart"] = new JArray();
                response["purchased"] = new JArray();
                response["kpoints"] = 0;
                response["playerLevel"] = 1;
                response["reverseLevel"] = 0;
                response["purchasedToken"] = "shop.test.1";
            }
            if (success && (string)sent["action"] == "shopCheckout")
            {
                response["newBalance"] = 0;
                response["purchased"] = new JArray();
                response["purchasedToken"] = "shop.test.2";
            }
            if (success && (string)sent["action"] == "shopCheckoutPreview")
            {
                response["v"] = 1;
                response["checkoutToken"] = "kcheckout.test.1";
                response["purchaseLines"] = new JArray();
                response["total"] = 0;
                response["balance"] = 10;
                response["projectedBalance"] = 10;
                response["canCommit"] = true;
                response["blockingError"] = "";
            }
            if (success && (string)sent["action"] == "shopCheckoutCommit")
            {
                response["v"] = 1;
                response["newBalance"] = 0;
                response["delivered"] = new JArray();
                response["cart"] = new JArray();
                response["purchased"] = new JArray();
                response["purchasedToken"] = "shop.test.2";
            }
            if (success && (string)sent["action"] == "shopClaim")
            {
                response["purchased"] = new JArray();
                response["purchasedToken"] = "shop.test.3";
            }
            return response;
        }

        [Fact]
        public void HandleWebRequest_Disconnected_ReturnsLegacyShapedError()
        {
            string posted = null;
            var task = new ShopTask(() => false, _ => true);
            task.SetPostToWeb(json => posted = json);

            task.HandleWebRequest("bulkQuery", JObject.Parse("{\"callId\":\"wb.s.1.1\"}"));

            var response = JObject.Parse(posted);
            Assert.Equal("panel_resp", (string)response["type"]);
            Assert.Equal("wb.s.1.1", (string)response["callId"]);
            Assert.Equal("disconnected", (string)response["error"]);
            Assert.Null(response["panel"]);
            Assert.Null(response["cmd"]);
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
            string sent = null;
            var task = new ShopTask(() => true, payload => { sent = payload; return true; });

            task.HandleWebRequest(cmd, JObject.Parse(
                "{\"callId\":\"wb.s.1.1\",\"action\":\"evil\",\"task\":\"evil\",\"cart\":[{\"idx\":1,\"qty\":2}]}"));

            var message = ParseSent(sent);
            Assert.Equal("cmd", (string)message["task"]);
            Assert.Equal(action, (string)message["action"]);
            Assert.Equal(2, (int)message["cart"][0]["qty"]);
            Assert.Null(message["cmd"]);
        }

        [Fact]
        public void HandleWebRequest_UnsupportedAndInvalidCallId_DoNotReachFlash()
        {
            int sendCount = 0;
            var posted = new List<JObject>();
            var task = new ShopTask(() => true, _ => { sendCount++; return true; });
            task.SetPostToWeb(json => posted.Add(JObject.Parse(json)));

            task.HandleWebRequest("bogus", JObject.Parse("{\"callId\":\"wb.s.1.1\"}"));
            task.HandleWebRequest("bulkQuery", JObject.Parse("{\"callId\":\"bad call id\"}"));

            Assert.Equal(0, sendCount);
            Assert.Equal("unsupported_cmd", (string)posted[0]["error"]);
            Assert.Equal("invalid_call_id", (string)posted[1]["error"]);
        }

        [Fact]
        public void WriteGate_RejectsSecondWriteBusy_ThenReleasesOnDefinitiveResponse()
        {
            var sent = new List<string>();
            var posted = new List<JObject>();
            var task = new ShopTask(() => true, payload => { sent.Add(payload); return true; });
            task.SetPostToWeb(json => posted.Add(JObject.Parse(json)));

            task.HandleWebRequest("saveCart", JObject.Parse("{\"callId\":\"wb.s.1.1\",\"cart\":[]}"));
            task.HandleWebRequest("checkout", JObject.Parse("{\"callId\":\"wb.s.1.2\",\"cart\":[]}"));

            Assert.Single(sent);
            Assert.Equal("busy", (string)posted[0]["error"]);

            task.HandleFlashResponse(ResponseFor(sent[0], true), _ => { });
            task.HandleWebRequest("checkout", JObject.Parse("{\"callId\":\"wb.s.1.3\",\"cart\":[]}"));
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

            task.HandleWebRequest("checkout", JObject.Parse("{\"callId\":\"wb.s.1.1\",\"cart\":[]}"));
            Assert.True(timeoutPosted.Wait(TimeSpan.FromSeconds(2)), "write timeout response was not posted");

            task.HandleWebRequest("claim", JObject.Parse("{\"callId\":\"wb.s.1.2\",\"purchasedIdx\":0}"));
            Assert.Contains(posted, item => (string)item["callId"] == "wb.s.1.2" && (string)item["error"] == "reconcile_required");

            task.HandleWebRequest("bulkQuery", JObject.Parse("{\"callId\":\"wb.s.1.3\"}"));
            Assert.True(sent.TryPeek(out _));
            string[] sentArray = sent.ToArray();
            task.HandleFlashResponse(ResponseFor(sentArray[sentArray.Length - 1], true), _ => { });

            int before = sent.Count;
            task.HandleWebRequest("claim", JObject.Parse("{\"callId\":\"wb.s.1.4\",\"purchasedIdx\":0}"));
            Assert.Equal(before + 1, sent.Count);
        }

        [Fact]
        public void DisconnectWithWritePending_PreservesReconcileGate()
        {
            var sent = new List<string>();
            var posted = new List<JObject>();
            var task = new ShopTask(() => true, payload => { sent.Add(payload); return true; });
            task.SetPostToWeb(json => posted.Add(JObject.Parse(json)));

            task.HandleWebRequest("claim", JObject.Parse("{\"callId\":\"wb.s.1.1\",\"purchasedIdx\":0}"));
            task.ClearPending();
            task.HandleWebRequest("saveCart", JObject.Parse("{\"callId\":\"wb.s.2.1\",\"cart\":[]}"));

            Assert.Equal("reconcile_required", (string)posted[0]["error"]);
            task.HandleWebRequest("bulkQuery", JObject.Parse("{\"callId\":\"wb.s.2.2\"}"));
            task.HandleFlashResponse(ResponseFor(sent[sent.Count - 1], true), _ => { });

            int before = sent.Count;
            task.HandleWebRequest("saveCart", JObject.Parse("{\"callId\":\"wb.s.2.3\",\"cart\":[]}"));
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

            task.HandleWebRequest(cmd, JObject.Parse("{\"callId\":\"wb.s.1.1\",\"cart\":[],\"purchasedIdx\":0}"));
            var malformed = new JObject
            {
                ["task"] = "shop_response",
                ["callId"] = (int)ParseSent(sent[0])["callId"],
                ["success"] = true
            };
            task.HandleFlashResponse(malformed, _ => { });

            var response = JObject.Parse(posted);
            Assert.False((bool)response["success"]);
            Assert.Equal("reconcile_required", (string)response["error"]);
            Assert.Equal("invalid_response", (string)response["cause"]);
        }

        [Fact]
        public void MalformedBulkQuery_DoesNotUnlockReconcileGate()
        {
            var sent = new List<string>();
            var posted = new List<JObject>();
            var task = new ShopTask(() => true, payload => { sent.Add(payload); return true; });
            task.SetPostToWeb(json => posted.Add(JObject.Parse(json)));

            task.HandleWebRequest("checkout", JObject.Parse("{\"callId\":\"wb.s.1.1\",\"cart\":[]}"));
            task.HandleFlashResponse(new JObject
            {
                ["task"] = "shop_response",
                ["callId"] = (int)ParseSent(sent[0])["callId"],
                ["success"] = true
            }, _ => { });

            task.HandleWebRequest("bulkQuery", JObject.Parse("{\"callId\":\"wb.s.1.2\"}"));
            task.HandleFlashResponse(new JObject
            {
                ["task"] = "shop_response",
                ["callId"] = (int)ParseSent(sent[1])["callId"],
                ["success"] = true
            }, _ => { });
            task.HandleWebRequest("checkout", JObject.Parse("{\"callId\":\"wb.s.1.3\",\"cart\":[]}"));

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

            task.HandleWebRequest(cmd, JObject.Parse("{\"callId\":\"wb.s.1.1\",\"cart\":[],\"purchasedIdx\":0}"));
            task.HandleFlashResponse(ResponseFor(sent[0], false, error), _ => { });

            task.HandleWebRequest("saveCart", JObject.Parse("{\"callId\":\"wb.s.1.2\",\"cart\":[]}"));
            Assert.Equal(2, sent.Count);
        }

        [Fact]
        public void DuplicateActiveAndRecentCallId_AreNeverForwardedTwice()
        {
            var sent = new List<string>();
            var task = new ShopTask(() => true, payload => { sent.Add(payload); return true; });
            var request = JObject.Parse("{\"callId\":\"wb.s.1.1\"}");

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

            task.HandleWebRequest("saveCart", JObject.Parse("{\"callId\":\"wb.s.1.1\",\"cart\":[]}"));
            task.HandleWebRequest("checkout", JObject.Parse("{\"callId\":\"wb.s.1.2\",\"cart\":[]}"));

            Assert.Equal("reconcile_required", (string)posted[0]["error"]);
            Assert.Equal("reconcile_required", (string)posted[1]["error"]);
        }

        [Fact]
        public void FlashResponse_RestoresWebCallIdWithoutAddingPanelOrCmd()
        {
            string sent = null;
            string posted = null;
            var task = new ShopTask(() => true, payload => { sent = payload; return true; });
            task.SetPostToWeb(json => posted = json);

            task.HandleWebRequest("bulkQuery", JObject.Parse("{\"callId\":\"wb.session.3.7\"}"));
            task.HandleFlashResponse(ResponseFor(sent, true), _ => { });

            var response = JObject.Parse(posted);
            Assert.Equal("wb.session.3.7", (string)response["callId"]);
            Assert.Null(response["task"]);
            Assert.Null(response["panel"]);
            Assert.Null(response["cmd"]);
        }

        [Fact]
        public void CheckoutPreview_MalformedSuccess_IsRejectedWithoutEnteringWriteGate()
        {
            var sent = new List<string>();
            var posted = new List<JObject>();
            var task = new ShopTask(() => true, payload => { sent.Add(payload); return true; });
            task.SetPostToWeb(json => posted.Add(JObject.Parse(json)));

            task.HandleWebRequest("checkoutPreview", JObject.Parse("{\"callId\":\"wb.s.1.1\",\"v\":1,\"cart\":[]}"));
            task.HandleFlashResponse(new JObject
            {
                ["task"] = "shop_response",
                ["callId"] = (int)ParseSent(sent[0])["callId"],
                ["success"] = true
            }, _ => { });
            task.HandleWebRequest("checkoutCommit", JObject.Parse("{\"callId\":\"wb.s.1.2\",\"expectedCheckoutToken\":\"x\"}"));

            Assert.Equal("invalid_response", (string)posted[0]["error"]);
            Assert.Equal(2, sent.Count);
            Assert.Equal("shopCheckoutCommit", (string)ParseSent(sent[1])["action"]);
        }
    }
}
