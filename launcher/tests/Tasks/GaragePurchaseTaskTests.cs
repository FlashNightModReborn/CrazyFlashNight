using System;
using System.Collections.Generic;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace Launcher.Tests.Tasks
{
    public sealed class GaragePurchaseTaskTests
    {
        private static JObject Request(string cmd, string callId, string vehicle = "bicycle", string token = "garage.1")
        {
            var payload = new JObject { ["v"] = 1 };
            if (cmd == "snapshot") payload["vehicleId"] = vehicle;
            else payload["token"] = token;
            if (cmd == "commit") payload["draft"] = new JObject { ["vehicleId"] = vehicle };
            return new JObject { ["type"] = "panel", ["panel"] = "garage", ["domain"] = "garage", ["cmd"] = cmd,
                ["callId"] = callId, ["panelInstanceId"] = "panel.garage.1", ["payload"] = payload };
        }
        private static JObject Sent(string text) => JObject.Parse(text.TrimEnd('\0'));
        private static JObject Response(JObject sent, string phase = "applied", string vehicle = "bicycle")
        {
            var costs = new Dictionary<string, long> { ["bicycle"] = 8000, ["motorcycle"] = 35000, ["offroad"] = 500000 };
            long cost = costs[vehicle];
            bool owned = phase != "editing", changed = phase == "applied" || phase == "save_pending";
            return new JObject { ["v"] = 1, ["callId"] = sent["callId"], ["task"] = "garage_purchase_response",
                ["operation"] = sent.Value<string>("action") == "garagePurchaseSnapshot" ? "snapshot" : sent.Value<string>("action") == "garagePurchaseQuery" ? "query" : "commit",
                ["token"] = sent["token"] ?? "garage.1", ["phase"] = phase, ["vehicleId"] = vehicle,
                ["draft"] = new JObject { ["vehicleId"] = vehicle }, ["name"] = "车辆", ["description"] = "出行权益\n后勤权益",
                ["cost"] = cost, ["balance"] = changed ? 600000 - cost : 600000,
                ["requiredDrivingLevel"] = vehicle == "offroad" ? 2 : vehicle == "motorcycle" ? 1 : 0,
                ["drivingLevel"] = 2, ["owned"] = owned, ["canPurchase"] = !owned,
                ["success"] = phase != "save_pending", ["changed"] = changed, ["saved"] = phase == "applied",
                ["error"] = phase == "save_pending" ? "save_pending" : null };
        }
        [Theory]
        [InlineData("bicycle")]
        [InlineData("motorcycle")]
        [InlineData("offroad")]
        public void ThreeVehiclesUseTheSameNarrowCommandAndCorrelatedResponse(string vehicle)
        {
            var sent = new List<JObject>(); var posted = new List<JObject>();
            using var task = new GaragePurchaseTask(() => true, text => { sent.Add(Sent(text)); return true; });
            task.SetPostToWeb(text => posted.Add(JObject.Parse(text)));
            task.HandleWebRequest("snapshot", Request("snapshot", "read.1", vehicle));
            Assert.Equal("garagePurchaseSnapshot", sent[0].Value<string>("action"));
            Assert.Equal(vehicle, sent[0].Value<string>("vehicleId"));
            task.HandleFlashResponse(Response(sent[0], "editing", vehicle), null);
            Assert.Equal("panel.garage.1", posted[0].Value<string>("panelInstanceId"));
            task.HandleWebRequest("commit", Request("commit", "write.1", vehicle));
            task.HandleFlashResponse(Response(sent[1], "applied", vehicle), null);
            Assert.True(posted[1].Value<bool>("saved"));
            Assert.Equal(vehicle, posted[1].Value<string>("vehicleId"));
        }
        [Theory]
        [InlineData("tank")]
        [InlineData("")]
        public void InvalidVehicleNeverReachesFlash(string vehicle)
        {
            var sent = new List<JObject>(); var posted = new List<JObject>();
            using var task = new GaragePurchaseTask(() => true, text => { sent.Add(Sent(text)); return true; });
            task.SetPostToWeb(text => posted.Add(JObject.Parse(text)));
            task.HandleWebRequest("snapshot", Request("snapshot", "bad.1", vehicle));
            Assert.Empty(sent); Assert.Equal("invalid_payload", posted[0].Value<string>("error"));
        }
        [Fact]
        public void PageCannotSupplyPriceOrOwnAnotherDomain()
        {
            var sent = new List<JObject>(); var posted = new List<JObject>();
            using var task = new GaragePurchaseTask(() => true, text => { sent.Add(Sent(text)); return true; });
            task.SetPostToWeb(text => posted.Add(JObject.Parse(text)));
            var request = Request("commit", "bad.1"); request["payload"]["price"] = 1;
            task.HandleWebRequest("commit", request);
            request = Request("snapshot", "bad.2"); request["domain"] = "surgery";
            task.HandleWebRequest("snapshot", request);
            Assert.Empty(sent); Assert.Equal(2, posted.Count);
        }
        [Fact]
        public void SaveRetryUsesOriginalVehicleAndBlocksAnotherPurchase()
        {
            var sent = new List<JObject>(); var posted = new List<JObject>();
            using var task = new GaragePurchaseTask(() => true, text => { sent.Add(Sent(text)); return true; });
            task.SetPostToWeb(text => posted.Add(JObject.Parse(text)));
            task.HandleWebRequest("commit", Request("commit", "write.1", "offroad"));
            task.HandleFlashResponse(Response(sent[0], "save_pending", "offroad"), null);
            task.HandleWebRequest("commit", Request("commit", "write.2", "bicycle"));
            Assert.Single(sent); Assert.Equal("reconcile_required", posted[1].Value<string>("error"));
            task.HandleWebRequest("commit", Request("commit", "write.3", "offroad"));
            task.HandleFlashResponse(Response(sent[1], "applied", "offroad"), null);
            Assert.True(posted[2].Value<bool>("saved"));
        }
        [Theory]
        [InlineData(false)]
        [InlineData(true)]
        public void LostDeliveryKeepsOriginalTokenAcrossCloseAndOnlyQueries(bool throwOnSend)
        {
            bool fail = true; var sent = new List<JObject>(); var posted = new List<JObject>();
            using var task = new GaragePurchaseTask(() => true, text => {
                sent.Add(Sent(text)); if (fail && throwOnSend) throw new InvalidOperationException("injected"); return !fail;
            });
            task.SetPostToWeb(text => posted.Add(JObject.Parse(text)));
            task.HandleWebRequest("commit", Request("commit", "write.1"));
            Assert.True(posted[0].Value<bool>("requiresReconcile"));
            task.ClearPending(); fail = false;
            task.HandleWebRequest("snapshot", Request("snapshot", "read.1"));
            Assert.Single(sent); Assert.Equal("garage.1", posted[1].Value<string>("token"));
            task.HandleWebRequest("query", Request("query", "query.1"));
            Assert.Equal("garagePurchaseQuery", sent[1].Value<string>("action"));
            task.HandleFlashResponse(Response(sent[1]), null);
            Assert.True(posted[2].Value<bool>("saved"));
        }
        [Theory]
        [InlineData("vehicle")]
        [InlineData("saved")]
        [InlineData("cost")]
        [InlineData("owned")]
        [InlineData("eligibility")]
        public void MalformedSuccessCannotUnlockThePendingPurchase(string mutation)
        {
            var sent = new List<JObject>(); var posted = new List<JObject>();
            using var task = new GaragePurchaseTask(() => true, text => { sent.Add(Sent(text)); return true; });
            task.SetPostToWeb(text => posted.Add(JObject.Parse(text)));
            task.HandleWebRequest("commit", Request("commit", "write.1"));
            var response = Response(sent[0]);
            if (mutation == "vehicle") response["vehicleId"] = "offroad";
            if (mutation == "saved") response["saved"] = false;
            if (mutation == "cost") response["cost"] = 0;
            if (mutation == "owned") response["owned"] = false;
            if (mutation == "eligibility") response["canPurchase"] = true;
            task.HandleFlashResponse(response, null);
            Assert.Equal("malformed_response", posted[0].Value<string>("error"));
            task.HandleWebRequest("commit", Request("commit", "write.2"));
            Assert.Single(sent);
        }
        [Fact]
        public void SnapshotCannotSubstituteAnotherVehicle()
        {
            var sent = new List<JObject>(); var posted = new List<JObject>();
            using var task = new GaragePurchaseTask(() => true, text => { sent.Add(Sent(text)); return true; });
            task.SetPostToWeb(text => posted.Add(JObject.Parse(text)));
            task.HandleWebRequest("snapshot", Request("snapshot", "read.1", "bicycle"));
            task.HandleFlashResponse(Response(sent[0], "editing", "offroad"), null);
            Assert.Equal("malformed_response", posted[0].Value<string>("error"));
        }
        [Fact]
        public void QueryCannotReleaseAWriteWithAnotherVehiclesReceipt()
        {
            bool fail = true; var sent = new List<JObject>(); var posted = new List<JObject>();
            using var task = new GaragePurchaseTask(() => true, text => { sent.Add(Sent(text)); return !fail; });
            task.SetPostToWeb(text => posted.Add(JObject.Parse(text)));
            task.HandleWebRequest("commit", Request("commit", "write.1")); fail = false;
            task.HandleWebRequest("query", Request("query", "query.1"));
            task.HandleFlashResponse(Response(sent[1], "applied", "offroad"), null);
            Assert.Equal("malformed_response", posted[1].Value<string>("error"));
            task.HandleWebRequest("commit", Request("commit", "write.2"));
            Assert.Equal(2, sent.Count); Assert.True(posted[2].Value<bool>("requiresReconcile"));
        }
        [Fact]
        public void DuplicateAndLateRepliesStayWithTheirOriginalCall()
        {
            var sent = new List<JObject>(); var posted = new List<JObject>();
            using var task = new GaragePurchaseTask(() => true, text => { sent.Add(Sent(text)); return true; });
            task.SetPostToWeb(text => posted.Add(JObject.Parse(text)));
            task.HandleWebRequest("snapshot", Request("snapshot", "read.1"));
            var reply = Response(sent[0], "editing"); task.HandleFlashResponse(reply, null); task.HandleFlashResponse(reply, null);
            Assert.Single(posted);
            task.HandleWebRequest("snapshot", Request("snapshot", "read.2")); task.ClearPending();
            task.HandleFlashResponse(Response(sent[1], "editing"), null);
            Assert.Single(posted);
        }
    }
}
