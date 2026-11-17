using System;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.Bus;
using CF7Launcher.Tasks;
using CF7Launcher.Tooltips;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

internal static partial class Program
{
    private sealed class ManagedRoundTrip : IDisposable
    {
        internal const string Panel = "tooltip.workbench.1";
        internal const long Generation = 7;
        internal readonly TooltipService Service;
        internal readonly TooltipResponseEnricher Enricher;
        internal readonly InventoryTask Inventory;
        internal readonly EquipmentTuningTask Tuning;
        internal readonly ItemUseTask ItemUse;
        internal readonly MessageRouter Router;
        internal readonly ConcurrentQueue<JObject> Flash = new ConcurrentQueue<JObject>();
        internal readonly ConcurrentDictionary<string, JObject> Web = new ConcurrentDictionary<string, JObject>();
        internal bool BindingCurrent = true;

        internal ManagedRoundTrip(Func<ITooltipContentEngine> engine)
        {
            Service = new TooltipService(engine);
            Enricher = new TooltipResponseEnricher(Service);
            bool Send(string text) { Flash.Enqueue(JObject.Parse(text.TrimEnd('\0'))); return true; }
            void Post(string text) { var value = JObject.Parse(text); Web[value.Value<string>("callId")] = value; }
            Inventory = new InventoryTask(() => true, Send, 10000);
            Inventory.SetPostToWeb(Post);
            Tuning = new EquipmentTuningTask(() => true, Send, 10000);
            Tuning.SetPostToWeb(Post);
            Assert(Tuning.BindPanelInstance(Panel), "production tuning panel did not bind");
            ItemUse = new ItemUseTask(() => true, Send,
                (panel, generation) => BindingCurrent && panel == Panel && generation == Generation, 10000);
            ItemUse.SetPostToWeb(Post);
            Enricher.RegisterOwnerResolver("inventory_response", Inventory.ResolveTooltipOwner);
            Enricher.RegisterOwnerResolver("equipment_tuning_response", Tuning.ResolveTooltipOwner);
            Enricher.RegisterOwnerResolver("item_use_response", ItemUse.ResolveTooltipOwner);
            Router = new MessageRouter { TooltipResponses = Enricher };
            Router.RegisterAsync("inventory_response", Inventory.HandleFlashResponse);
            Router.RegisterAsync("equipment_tuning_response", Tuning.HandleFlashResponse);
            Router.RegisterAsync("item_use_response", ItemUse.HandleFlashResponse);
        }
        internal JObject Sent()
        {
            Assert(Flash.TryDequeue(out var sent), "production task did not send a Flash request");
            return sent;
        }
        internal void Reply(JObject value) => Router.ProcessMessage(value.ToString(Formatting.None), _ => { });
        internal async Task<JObject> Receive(string callId)
        {
            var clock = Stopwatch.StartNew();
            while (!Web.TryGetValue(callId, out _))
            {
                if (clock.Elapsed > Deadline) throw new TimeoutException("production task did not return " + callId);
                await Task.Delay(1);
            }
            return Web[callId];
        }
        public void Dispose() { Inventory.Dispose(); Tuning.Dispose(); ItemUse.Dispose(); Enricher.Dispose(); Service.Dispose(); }
    }

    private static JObject InventoryRead(string callId, string lease = "inv.1.0") => new JObject
    {
        ["type"] = "panel", ["panel"] = "workbench", ["domain"] = "inventory", ["cmd"] = "tooltip",
        ["callId"] = callId, ["panelInstanceId"] = ManagedRoundTrip.Panel,
        ["payload"] = new JObject { ["v"] = 1, ["source"] = new JObject {
            ["containerId"] = "背包", ["slot"] = 0, ["expectedLease"] = lease } }
    };
    private static JObject TooltipRow(JObject input) => new JObject
    {
        ["itemName"] = "测试物品", ["displayname"] = "测试物品", ["iconName"] = "test",
        ["itemType"] = "武器", ["descHTML"] = "", ["introHTML"] = "", ["tooltipInput"] = input.DeepClone()
    };
    private static JObject InventoryReply(JObject sent, JObject input)
    {
        var value = TooltipRow(input); value["task"] = "inventory_response";
        value["callId"] = sent["callId"].DeepClone(); value["success"] = true; value["v"] = 1;
        return value;
    }
    private static JObject ItemUseRead(string command, string callId)
    {
        var payload = new JObject { ["v"] = command == "consume" ? 1 : 2,
            ["panelInstanceId"] = ManagedRoundTrip.Panel, ["sessionGeneration"] = ManagedRoundTrip.Generation };
        if (command == "stashTooltip")
        {
            payload["storeId"] = "stash.test"; payload["entryId"] = "stash.test.e1"; payload["revision"] = 1;
        }
        if (command == "consume")
        {
            payload["operationId"] = "operation.consume";
            payload["source"] = new JObject { ["physicalSlot"] = 0, ["slotLease"] = "lease.0",
                ["itemName"] = "普通hp药剂", ["backpackVersion"] = 1 };
        }
        return new JObject { ["type"] = "panel", ["panel"] = "workbench", ["domain"] = "item_use",
            ["cmd"] = command, ["callId"] = callId, ["panelInstanceId"] = ManagedRoundTrip.Panel, ["payload"] = payload };
    }
    private static JObject ItemUseReply(JObject sent, string command, JObject data = null)
    {
        var response = new JObject { ["task"] = "item_use_response", ["callId"] = sent["callId"].DeepClone(),
            ["v"] = sent["v"].DeepClone(), ["success"] = true, ["command"] = command,
            ["panelInstanceId"] = ManagedRoundTrip.Panel, ["sessionGeneration"] = ManagedRoundTrip.Generation };
        if (data != null) response["data"] = data;
        if (sent["operationId"] != null) response["operationId"] = sent["operationId"].DeepClone();
        if (command == "consume") { response["consumed"] = 1; response["remaining"] = 4; response["selectedLane"] = 2; }
        return response;
    }
    private static JObject Choices(JObject firstInput = null, int itemsPerOption = 1)
    {
        var options = new JArray();
        for (int option = 0; option < 2; option++)
        {
            var items = new JArray();
            for (int i = 0; i < itemsPerOption; i++)
            {
                var input = option == 0 && i == 0 && firstInput != null ? (JObject)firstInput.DeepClone()
                    : Input("选择奖励 " + option + "." + i);
                input["output"] = "details";
                items.Add(new JObject { ["itemName"] = "UZI", ["displayName"] = "UZI", ["quantity"] = 1,
                    ["level"] = 1, ["icon"] = "UZI", ["tooltipInput"] = input });
            }
            options.Add(new JObject { ["optionId"] = "option." + option, ["title"] = "选项 " + option,
                ["description"] = "装备配给", ["items"] = items });
        }
        return new JObject { ["success"] = true, ["storeId"] = "stash.test", ["revision"] = 1,
            ["pendingOperationId"] = "", ["offers"] = new JArray(new JObject { ["offerId"] = "stash.test.choice.1",
                ["title"] = "配给", ["options"] = options }) };
    }

    private static async Task ManagedTaskTests(string root)
    {
        await Check("production Inventory task round-trip reuses same-item cache and distinguishes lease", async () =>
        {
            var engine = new FakeEngine(); using var h = new ManagedRoundTrip(() => engine);
            for (int i = 1; i <= 3; i++)
            {
                string call = "inventory.cache." + i;
                h.Inventory.HandleWebRequest("tooltip", InventoryRead(call, i == 3 ? "inv.2.0" : "inv.1.0"));
                h.Reply(InventoryReply(h.Sent(), Input("same item")));
                var web = await h.Receive(call);
                Assert(web.Value<bool>("success") && web["document"] != null && web["tooltipInput"] == null,
                    "production Inventory validator rejected enrichment");
            }
            Assert(engine.Calls == 2 && h.Service.GetMetrics().CacheHits == 1, "real pending identity broke cache/lease boundary");
        });
        await Check("production Inventory pending owner supersedes hover and retires late closed responses", async () =>
        {
            var engine = new FakeEngine(); engine.Release.Reset(); using var h = new ManagedRoundTrip(() => engine);
            h.Inventory.HandleWebRequest("tooltip", InventoryRead("inventory.old")); var old = h.Sent();
            h.Reply(InventoryReply(old, Input("old"))); Assert(engine.Entered.Wait(Deadline), "old hover not started");
            h.Inventory.HandleWebRequest("tooltip", InventoryRead("inventory.new"));
            h.Reply(InventoryReply(h.Sent(), Input("new"))); engine.Release.Set();
            Assert((await h.Receive("inventory.new")).Value<bool>("success"), "new hover failed");
            Assert((await h.Receive("inventory.old")).Value<string>("error") == "stale_state", "old pending was not retired");
            h.Inventory.HandleWebRequest("tooltip", InventoryRead("inventory.closed")); var closed = h.Sent();
            h.Inventory.ClearPending(); int before = engine.Calls;
            h.Reply(InventoryReply(closed, Input("late closed"))); await Task.Delay(20);
            Assert(engine.Calls == before && !h.Web.ContainsKey("inventory.closed"), "closed response entered V8 or reached Web");
        });
        await Check("production ItemUse choice snapshot and hover use independent pending lanes", async () =>
        {
            var engine = new FakeEngine(); engine.Release.Reset(); using var h = new ManagedRoundTrip(() => engine);
            h.ItemUse.HandleWebRequest("stashChoices", ItemUseRead("stashChoices", "choices.read"));
            h.Reply(ItemUseReply(h.Sent(), "stashChoices", Choices())); Assert(engine.Entered.Wait(Deadline), "choice batch not started");
            h.ItemUse.HandleWebRequest("stashTooltip", ItemUseRead("stashTooltip", "stash.hover"));
            h.Reply(ItemUseReply(h.Sent(), "stashTooltip", new JObject { ["success"] = true, ["tooltip"] = TooltipRow(Input("hover")) }));
            engine.Release.Set();
            var choice = await h.Receive("choices.read"); var hover = await h.Receive("stash.hover");
            Assert(choice.Value<bool>("success") && hover.Value<bool>("success"), "hover canceled choice snapshot");
            var row = (JObject)choice["data"]["offers"][0]["options"][0]["items"][0];
            Assert(row.Count == 6 && row["details"]?.Type == JTokenType.String && h.ItemUse.WriteState == "idle", "choice exact shape/read authority changed");
        });
        await Check("production ItemUse binding close cancels queued batch and bypasses later absent pending", async () =>
        {
            var engine = new FakeEngine(); engine.Release.Reset(); using var h = new ManagedRoundTrip(() => engine);
            var blocker = h.Service.BuildAsync(Input("blocker"), Id("external")); Assert(engine.Entered.Wait(Deadline), "blocker not started");
            h.ItemUse.HandleWebRequest("stashChoices", ItemUseRead("stashChoices", "choices.closed")); var sent = h.Sent();
            var response = ItemUseReply(sent, "stashChoices", Choices(itemsPerOption: 16)); h.Reply(response);
            Assert(h.Service.GetMetrics().Queued == 1, "choice batch not queued");
            h.BindingCurrent = false; h.ItemUse.ClearPending(); engine.Release.Set(); await blocker.WaitAsync(Deadline);
            for (int i = 0; i < 100 && h.Service.GetMetrics().ActiveRequests > 0; i++) await Task.Delay(1);
            h.Reply(response); await Task.Delay(20);
            Assert(engine.Calls == 1 && h.Web.Count == 0, "closed batch consumed V8 or delivered");
        });
        await Check("production ItemUse content failure preserves strict read shape and independent committed write acknowledgement", async () =>
        {
            var engine = new FakeEngine { AlwaysFail = true }; using var h = new ManagedRoundTrip(() => engine);
            h.ItemUse.HandleWebRequest("consume", ItemUseRead("consume", "write.consume")); var write = h.Sent();
            Assert(h.ItemUse.WriteState == "write_pending", "write gate not held");
            h.ItemUse.HandleWebRequest("stashTooltip", ItemUseRead("stashTooltip", "failed.read"));
            h.Reply(ItemUseReply(h.Sent(), "stashTooltip", new JObject { ["success"] = true, ["tooltip"] = TooltipRow(Input("fails")) }));
            var read = await h.Receive("failed.read");
            Assert(read.Value<bool>("success") && read["data"]["tooltip"]["document"].Value<string>("title") == "注释暂不可用",
                "unavailable content broke the real read schema");
            Assert(h.ItemUse.WriteState == "write_pending", "read failure rewrote write authority");
            h.Reply(ItemUseReply(write, "consume")); var acknowledged = await h.Receive("write.consume");
            Assert(acknowledged.Value<bool>("success") && h.ItemUse.WriteState == "idle", "committed write did not settle");
            using var control = new ManagedRoundTrip(() => new FakeEngine());
            control.ItemUse.HandleWebRequest("consume", ItemUseRead("consume", "write.consume"));
            control.Reply(ItemUseReply(control.Sent(), "consume"));
            Assert(JToken.DeepEquals(acknowledged, await control.Receive("write.consume")), "write response schema changed due to content failure");
        });
        await Check("production ItemUse details-only engine failure preserves the exact choice item schema", async () =>
        {
            using var h = new ManagedRoundTrip(() => new TooltipV8Engine(root));
            var failedProjection = new JObject { ["version"] = 1, ["kind"] = "item", ["itemName"] = "missing-projection", ["output"] = "details" };
            h.ItemUse.HandleWebRequest("stashChoices", ItemUseRead("stashChoices", "choices.failed-details"));
            h.Reply(ItemUseReply(h.Sent(), "stashChoices", Choices(failedProjection)));
            var web = await h.Receive("choices.failed-details");
            Assert(web.Value<bool>("success"), "real ChoiceReward validator rejected failure fallback");
            var row = (JObject)web["data"]["offers"][0]["options"][0]["items"][0];
            Assert(row.Count == 6 && row.Value<string>("details") == "注释暂不可用。"
                && row["document"] == null && row["introHTML"] == null, "failure fallback expanded exact choice schema");
        });
    }
}
