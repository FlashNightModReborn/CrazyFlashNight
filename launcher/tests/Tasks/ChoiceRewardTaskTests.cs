using System;
using System.Collections.Generic;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Tasks
{
    public sealed class ChoiceRewardTaskTests
    {
        private const string Panel = "choice.panel";
        private sealed class Harness : IDisposable
        {
            public readonly List<JObject> Flash = new List<JObject>();
            public readonly List<JObject> Web = new List<JObject>();
            public readonly ItemUseTask Task;
            public Harness()
            {
                Task = new ItemUseTask(() => true, text => { Flash.Add(JObject.Parse(text.TrimEnd('\0'))); return true; },
                    (panel, generation) => panel == Panel && generation == 1, 10000);
                Task.SetPostToWeb(text => Web.Add(JObject.Parse(text)));
            }
            public void Dispose() => Task.Dispose();
            public void Reply(string command, JObject data)
            {
                var sent = Flash[Flash.Count - 1];
                var result = new JObject { ["task"] = "item_use_response", ["callId"] = sent["callId"],
                    ["v"] = 2, ["command"] = command, ["success"] = true, ["panelInstanceId"] = Panel,
                    ["sessionGeneration"] = 1, ["data"] = data };
                if (sent["operationId"] != null) result["operationId"] = sent["operationId"];
                Task.HandleFlashResponse(result, null);
            }
        }
        private static JObject Request(string command, string callId = "web.1")
        {
            var payload = new JObject { ["v"] = 2, ["panelInstanceId"] = Panel, ["sessionGeneration"] = 1 };
            if (command != "stashChoices")
            {
                payload["operationId"] = "choice.operation.1";
                payload["storeId"] = "stash.test"; payload["expectedRevision"] = 4;
                if (command == "stashChoose") { payload["offerId"] = "stash.test.choice.1"; payload["optionId"] = "option.1"; }
                if (command == "stashOpen") payload["source"] = new JObject { ["physicalSlot"] = 0,
                    ["slotLease"] = "lease.0", ["itemName"] = "自选礼包", ["backpackVersion"] = 1 };
            }
            return new JObject { ["type"] = "panel", ["panel"] = "workbench", ["domain"] = "item_use", ["cmd"] = command,
                ["callId"] = callId, ["panelInstanceId"] = Panel, ["payload"] = payload };
        }
        private static JObject Snapshot()
        {
            var options = new JArray();
            for (int i = 1; i <= 3; i++) options.Add(new JObject { ["optionId"] = "option." + i,
                ["title"] = "配给 " + i, ["description"] = "武器和配套弹药", ["items"] = new JArray(new JObject {
                    ["itemName"] = "UZI", ["displayName"] = "UZI", ["quantity"] = 1, ["level"] = 7 }) });
            return new JObject { ["success"] = true, ["storeId"] = "stash.test", ["revision"] = 4,
                ["pendingOperationId"] = "", ["offers"] = new JArray(new JObject { ["offerId"] = "stash.test.choice.1",
                    ["title"] = "初阶配给", ["options"] = options }) };
        }
        private static JObject Selected() => new JObject { ["success"] = true, ["kind"] = "choiceSelect",
            ["offerId"] = "stash.test.choice.1", ["optionId"] = "option.1", ["rewardReady"] = true };

        [Theory]
        [InlineData("stashChoices", "itemUseStashChoices")]
        [InlineData("stashChoose", "itemUseStashChoose")]
        public void ExactCommandsAreForwarded(string command, string action)
        {
            using var h = new Harness();
            h.Task.HandleWebRequest(command, Request(command));
            Assert.Equal(action, Assert.Single(h.Flash).Value<string>("action"));
            Assert.Equal(command == "stashChoices" ? "idle" : "write_pending", h.Task.WriteState);
        }
        [Theory]
        [InlineData("items")]
        [InlineData("quantity")]
        [InlineData("seed")]
        [InlineData("poolId")]
        public void ClientCannotSupplyRewardContents(string field)
        {
            using var h = new Harness();
            var request = Request("stashChoose"); request["payload"][field] = "forged";
            h.Task.HandleWebRequest("stashChoose", request);
            Assert.Empty(h.Flash); Assert.Equal("idle", h.Task.WriteState);
        }
        [Fact]
        public void SnapshotProjectsTheFrozenBundle()
        {
            using var h = new Harness(); h.Task.HandleWebRequest("stashChoices", Request("stashChoices"));
            h.Reply("stashChoices", Snapshot());
            Assert.True(h.Web[h.Web.Count - 1].Value<bool>("success"));
            Assert.Equal("idle", h.Task.WriteState);
        }
        [Theory]
        [InlineData("duplicate")]
        [InlineData("quantity")]
        [InlineData("extra")]
        [InlineData("foreign")]
        public void MalformedSnapshotCannotBecomeAChoice(string fault)
        {
            using var h = new Harness(); h.Task.HandleWebRequest("stashChoices", Request("stashChoices"));
            var data = Snapshot();
            if (fault == "duplicate") data["offers"][0]["options"][1]["optionId"] = "option.1";
            if (fault == "quantity") data["offers"][0]["options"][0]["items"][0]["quantity"] = -1;
            if (fault == "extra") data["offers"][0]["granted"] = true;
            if (fault == "foreign") data["offers"][0]["offerId"] = "other.choice.1";
            h.Reply("stashChoices", data);
            Assert.False(h.Web[h.Web.Count - 1].Value<bool>("success"));
        }
        [Fact]
        public void OpenReceiptHasNoUnselectedGrant()
        {
            using var h = new Harness(); h.Task.HandleWebRequest("stashOpen", Request("stashOpen"));
            h.Reply("stashOpen", new JObject { ["success"] = true, ["kind"] = "choiceOpen", ["offerId"] = "stash.test.choice.1",
                ["consumed"] = 1, ["remaining"] = 0 });
            Assert.Equal("idle", h.Task.WriteState); Assert.True(h.Web[h.Web.Count - 1].Value<bool>("success"));
            Assert.False(h.Task.TryArmRewardNavigation(Panel, 1));
        }
        [Fact]
        public void WrongSelectedIdentityRequiresExactQueryEvenAfterRead()
        {
            using var h = new Harness(); h.Task.HandleWebRequest("stashChoose", Request("stashChoose"));
            var wrong = Selected(); wrong["optionId"] = "option.2"; h.Reply("stashChoose", wrong);
            Assert.Equal("needs_reconcile", h.Task.WriteState);
            h.Task.HandleWebRequest("stashChoices", Request("stashChoices", "web.read")); h.Reply("stashChoices", Snapshot());
            Assert.Equal("needs_reconcile", h.Task.WriteState);
            int sent = h.Flash.Count;
            h.Task.HandleWebRequest("stashChoose", Request("stashChoose", "web.repeat"));
            Assert.Equal(sent, h.Flash.Count);
            h.Task.HandleWebRequest("stashQuery", Request("stashQuery", "web.query"));
            h.Reply("stashQuery", new JObject { ["success"] = true, ["state"] = "committed", ["result"] = Selected() });
            Assert.Equal("idle", h.Task.WriteState);
        }
        [Fact]
        public void ChosenContentsAreAcknowledgedOnlyForTheRequestedIds()
        {
            using var h = new Harness(); h.Task.HandleWebRequest("stashChoose", Request("stashChoose"));
            h.Reply("stashChoose", Selected());
            Assert.True(h.Web[h.Web.Count - 1].Value<bool>("success")); Assert.Equal("idle", h.Task.WriteState);
        }
    }
}
