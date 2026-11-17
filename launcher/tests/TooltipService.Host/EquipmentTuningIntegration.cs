using System.Threading.Tasks;
using Newtonsoft.Json.Linq;

internal static partial class Program
{
    private const string TuningView = "tooltip.tuning.view.1";

    private static JObject TuningSource() => new JObject
    {
        ["sourceKind"] = "inventory", ["containerId"] = "背包", ["slot"] = 7,
        ["expectedLease"] = "lease.source.7"
    };

    private static JObject TuningRead(string command, string callId)
    {
        var payload = new JObject { ["v"] = 1, ["viewSessionId"] = TuningView, ["source"] = TuningSource() };
        if (command == "tooltip") payload["candidateKey"] = "candidate.one";
        return new JObject { ["type"] = "panel", ["panel"] = "workbench", ["domain"] = "equipment_tuning",
            ["cmd"] = command, ["callId"] = callId, ["panelInstanceId"] = ManagedRoundTrip.Panel, ["payload"] = payload };
    }

    private static JObject TuningReply(JObject sent, string command) => new JObject
    {
        ["task"] = "equipment_tuning_response", ["callId"] = sent["callId"].DeepClone(),
        ["v"] = 1, ["success"] = true, ["command"] = command,
        ["panelInstanceId"] = sent["panelInstanceId"].DeepClone(),
        ["viewSessionId"] = sent["viewSessionId"].DeepClone(), ["writeEpoch"] = sent["writeEpoch"].DeepClone()
    };

    // Fixture data only. Snapshot acceptance, source/lease binding, candidate authority,
    // pending completion and tooltip validation all execute the actual production Task.
    private static async Task PrimeTuning(ManagedRoundTrip h)
    {
        h.Tuning.HandleWebRequest("snapshot", TuningRead("snapshot", "tuning.snapshot"));
        JObject sent = h.Sent();
        JObject response = TuningReply(sent, "snapshot");
        response["snapshot"] = new JObject
        {
            ["gender"] = "男", ["source"] = sent["source"].DeepClone(),
            ["equipment"] = new JObject { ["name"] = "测试手枪A", ["displayName"] = "测试手枪甲",
                ["icon"] = "测试手枪图标甲", ["type"] = "武器", ["use"] = "手枪", ["level"] = 7,
                ["tier"] = "一阶", ["mods"] = new JArray(), ["lastUpdate"] = 1000,
                ["modSlotCapacity"] = 3, ["maxLevel"] = 13, ["hardMaxLevel"] = 13 },
            ["enhance"] = new JObject { ["currentLevel"] = 7, ["maxLevel"] = 13,
                ["availableMaxLevel"] = 13, ["hardMaxLevel"] = 13 },
            ["tierCandidates"] = new JArray(new JObject { ["candidateKey"] = "candidate.one",
                ["itemName"] = "测试进阶材料", ["displayName"] = "测试进阶材料甲", ["icon"] = "测试进阶材料图标",
                ["tierName"] = "一阶", ["owned"] = 3, ["available"] = true, ["reason"] = "" }),
            ["modCandidates"] = new JArray(),
            ["materials"] = new JArray(new JObject { ["itemName"] = "测试进阶材料", ["displayName"] = "测试进阶材料甲",
                ["icon"] = "测试进阶材料图标", ["count"] = 3 }),
            ["materialRevision"] = 7, ["inventoryRevision"] = 11
        };
        h.Reply(response);
        Assert((await h.Receive("tuning.snapshot")).Value<bool>("success"), "production tuning snapshot fixture was rejected");
        Assert(h.Tuning.PendingCount == 0 && h.Tuning.ActiveViewSessionId == TuningView,
            "production tuning snapshot did not establish the active view");
    }

    private static JObject TuningTooltipReply(JObject sent, JObject input = null)
    {
        JObject response = TuningReply(sent, "tooltip");
        response["candidateKey"] = sent["candidateKey"].DeepClone();
        response["introHTML"] = "<b>候选</b>"; response["descHTML"] = "候选说明";
        response["itemType"] = "收集品"; response["itemUse"] = "材料"; response["text"] = "候选";
        response["statsBefore"] = new JArray(new JObject { ["key"] = "damage", ["label"] = "伤害加成", ["value"] = 10 });
        response["statsAfter"] = new JArray(new JObject { ["key"] = "damage", ["label"] = "伤害加成", ["value"] = 12 });
        if (input != null)
        {
            response["introHTML"] = ""; response["descHTML"] = "";
            response["tooltipInput"] = input.DeepClone();
        }
        return response;
    }

    private static async Task EquipmentTuningTests(string root)
    {
        await Check("production EquipmentTuning accepts real V8 document after snapshot candidate authority", async () =>
        {
            using var h = new ManagedRoundTrip(() => new CF7Launcher.Tooltips.TooltipV8Engine(root));
            await PrimeTuning(h);
            h.Tuning.HandleWebRequest("tooltip", TuningRead("tooltip", "tuning.valid"));
            JObject sent = h.Sent();
            Assert(sent.Value<string>("action") == "equipmentTuningTooltip" && JToken.DeepEquals(sent["source"], TuningSource()),
                "production tuning request lost candidate source authority");
            h.Reply(TuningTooltipReply(sent, Input("<b>候选说明</b>")));
            JObject web = await h.Receive("tuning.valid");
            Assert(web.Value<bool>("success") && web["document"] is JObject && web["tooltipInput"] == null,
                "production tuning whitelist rejected generated document");
            Assert(web.Value<string>("descHTML").Contains("候选说明") && web["statsAfter"][0].Value<int>("value") == 12,
                "tuning content enrichment lost HTML or stat preview");
            Assert(h.Tuning.PendingCount == 0 && h.Tuning.WriteState == "idle", "tooltip altered the tuning write gate");
        });

        await Check("production EquipmentTuning content failure keeps explicit unavailable document and exact success shape", async () =>
        {
            using var h = new ManagedRoundTrip(() => new CF7Launcher.Tooltips.TooltipV8Engine(root));
            await PrimeTuning(h);
            h.Tuning.HandleWebRequest("tooltip", TuningRead("tooltip", "tuning.content.failure"));
            h.Reply(TuningTooltipReply(h.Sent(), new JObject { ["version"] = 1, ["kind"] = "item", ["itemName"] = "missing-projection" }));
            JObject web = await h.Receive("tuning.content.failure");
            Assert(web.Value<bool>("success") && web["error"] == null && web["tooltipInput"] == null,
                "content failure was converted to a malformed tuning response");
            Assert(web["document"].Value<string>("title") == "注释暂不可用"
                && web.Value<string>("introHTML").Length > 0 && web.Value<string>("descHTML").Contains("暂不可用"),
                "content failure did not produce explicit unavailable presentation");
            Assert(web.Value<string>("candidateKey") == "candidate.one" && web["statsBefore"][0].Value<int>("value") == 10
                && h.Tuning.PendingCount == 0 && h.Tuning.WriteState == "idle", "fallback changed tuning authority or settlement");
        });

        await Check("production EquipmentTuning sanitizes optional document while preserving strict outer schema", async () =>
        {
            var engine = new FakeEngine(); using var h = new ManagedRoundTrip(() => engine);
            await PrimeTuning(h);
            for (int i = 0; i < 4; i++)
            {
                string call = "tuning.sanitize." + i;
                h.Tuning.HandleWebRequest("tooltip", TuningRead("tooltip", call));
                JObject response = TuningTooltipReply(h.Sent());
                if (i == 0) response["document"] = new JObject { ["version"] = 1, ["title"] = "候选文档",
                    ["untrusted"] = "strip", ["sections"] = new JArray(new JObject { ["role"] = "body", ["unknown"] = true,
                        ["runs"] = new JArray(new JObject { ["text"] = "正文", ["handler"] = "strip" }) }) };
                if (i == 1) response["document"] = "invalid-document";
                if (i == 3) response["unexpected"] = true;
                h.Reply(response);
                JObject web = await h.Receive(call);
                if (i == 3)
                    Assert(!web.Value<bool>("success") && web.Value<string>("error") == "malformed_response",
                        "allowing document relaxed unrelated outer keys");
                else
                {
                    Assert(web.Value<bool>("success") && web.Value<string>("descHTML") == "候选说明", "optional document broke HTML compatibility");
                    if (i == 0)
                        Assert(web["document"].Value<string>("title") == "候选文档" && web["document"]["untrusted"] == null
                            && web["document"]["sections"][0]["unknown"] == null
                            && web["document"]["sections"][0]["runs"][0]["handler"] == null, "document bypassed the production sanitizer");
                    else Assert(web["document"] == null, "invalid or absent optional document was forwarded");
                }
            }
            Assert(engine.Calls == 0 && h.Tuning.PendingCount == 0, "legacy document validation unexpectedly entered the engine");
        });
    }
}
