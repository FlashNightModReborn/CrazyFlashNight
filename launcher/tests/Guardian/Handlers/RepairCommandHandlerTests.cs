// RepairCommandHandler.BuildPlanWireJson 序列化形状测试。
// 验证 plan → wire JSON 的字段稳定性（前端 UI 解析约定）。
//
// HandleDetect 端到端 (含 BootstrapPanel.PostToWeb) 留给 step 4 整套 apply / push 协议
// 一起做集成测试. 这里只测纯函数形状.

using System.Collections.Generic;
using CF7Launcher.Guardian.Handlers;
using CF7Launcher.Save;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian.Handlers
{
    public class RepairCommandHandlerTests
    {
        private static RepairDictionary BaseDict()
        {
            JObject d = new JObject();
            d["schemaVersion"] = 1;
            d["generated"] = new JObject();
            d["items"] = JArr("黑色功夫装");
            d["mods"] = JArr("攻击+5");
            d["enemies"] = JArr("黑铁会大叔");
            d["hairstyles"] = new JArray();
            d["skills"] = JArr("基础攻击");
            d["taskChains"] = new JArray();
            d["stages"] = new JArray();
            return new RepairDictionary(d);
        }

        private static JArray JArr(params string[] values)
        {
            JArray arr = new JArray();
            for (int i = 0; i < values.Length; i++) arr.Add(values[i]);
            return arr;
        }

        private static JObject FreshSnapshot()
        {
            return JObject.Parse(@"{
                ""version"": ""3.0"",
                ""lastSaved"": ""2026-04-15 15:03:28"",
                ""0"": [""玩家A"", ""男"", 1000, 1, 0, 175, 0, null, 1000, 0, [], 0, [], """"],
                ""1"": [],
                ""5"": [[""基础攻击"", 1, true, """", true]],
                ""inventory"": {
                    ""装备栏"": { ""上装装备"": { ""name"": ""黑色功夫装"", ""value"": { ""mods"": [], ""level"": 1 } } },
                    ""背包"": {}
                },
                ""tasks"": { ""tasks_finished"": {}, ""task_chains_progress"": {} },
                ""others"": {
                    ""设置"": {},
                    ""击杀统计"": { ""total"": 0, ""byType"": {} },
                    ""物品来源缓存"": { ""discoveredStages"": [], ""discoveredEnemies"": [], ""discoveredQuests"": [] }
                },
                ""collection"": { ""材料"": {}, ""情报"": {} }
            }");
        }

        [Fact]
        public void Wire_TopLevelShape_HasAllExpectedFields()
        {
            JObject s = FreshSnapshot();
            s["inventory"]["装备栏"]["上装装备"]["name"] = "黑色�夫装";
            s["0"][0] = "玩家�";

            RepairPlan plan = RepairPolicy.BuildPlan(s, BaseDict());
            JObject wire = RepairCommandHandler.BuildPlanWireJson(plan);

            Assert.Equal(2, (int)wire["totalFffd"]);
            Assert.NotNull(wire["byLayer"]);
            Assert.Equal(1, (int)wire["byLayer"]["L0"]);
            Assert.Equal(1, (int)wire["byLayer"]["L1"]);
            Assert.Equal(0, (int)wire["byLayer"]["L2"]);
            Assert.Equal(0, (int)wire["byLayer"]["L3"]);
            Assert.Equal(1, (int)wire["manualRequired"]);  // L0 manual
            Assert.True((bool)wire["willBumpLastSaved"]);  // L1 fix → bump

            JArray decisions = (JArray)wire["decisions"];
            Assert.Equal(2, decisions.Count);
        }

        [Fact]
        public void Wire_FixValueDecision_HasAutoNewValueAndCandidates()
        {
            JObject s = FreshSnapshot();
            s["inventory"]["装备栏"]["上装装备"]["name"] = "黑色�夫装";

            RepairPlan plan = RepairPolicy.BuildPlan(s, BaseDict());
            JObject wire = RepairCommandHandler.BuildPlanWireJson(plan);
            JObject d0 = (JObject)((JArray)wire["decisions"])[0];

            Assert.Equal("FixValue", (string)d0["action"]);
            Assert.Equal("黑色功夫装", (string)d0["autoNewValue"]);
            Assert.Equal("DictUnique", (string)d0["autoSource"]);
            Assert.Equal("L1", (string)d0["layer"]);
            Assert.Equal("Item", (string)d0["kind"]);
            Assert.Equal("value", (string)d0["spot"]);

            JArray cands = (JArray)d0["candidates"];
            Assert.Single(cands);
            Assert.Equal("黑色功夫装", (string)cands[0]["value"]);
            Assert.Equal("DictUnique", (string)cands[0]["source"]);
        }

        [Fact]
        public void Wire_ManualDecision_NoAutoNewValue()
        {
            JObject s = FreshSnapshot();
            s["0"][0] = "玩家�";  // L0 manual_required

            RepairPlan plan = RepairPolicy.BuildPlan(s, BaseDict());
            JObject wire = RepairCommandHandler.BuildPlanWireJson(plan);
            JObject d0 = (JObject)((JArray)wire["decisions"])[0];

            Assert.Equal("ManualRequired", (string)d0["action"]);
            Assert.Null(d0["autoNewValue"]);
            Assert.Null(d0["autoSource"]);
            Assert.Equal("L0", (string)d0["layer"]);
            Assert.Equal("FreeText", (string)d0["kind"]);
            // 候选数组存在但可能为空 (L0 自由文本无字典桶)
            Assert.NotNull(d0["candidates"]);
            Assert.IsType<JArray>(d0["candidates"]);
        }

        [Fact]
        public void Wire_KeySpotDecision_SpotIsKey()
        {
            // 装备槽位 key 损坏: '上装装备' → '上�装备' → EquipmentSlot 字典命中 → 自动 RenameKey.
            // anchor 全 fffd 时才 fallback Manual (单独测试见 Wire_KeySpotDecision_AmbiguousAnchor_Manual).
            JObject s = FreshSnapshot();
            JObject equip = (JObject)s["inventory"]["装备栏"];
            JToken val = equip["上装装备"];
            equip.Remove("上装装备");
            equip["上�装备"] = val;

            RepairPlan plan = RepairPolicy.BuildPlan(s, BaseDict());
            JObject wire = RepairCommandHandler.BuildPlanWireJson(plan);
            JObject d0 = (JObject)((JArray)wire["decisions"])[0];

            Assert.Equal("key", (string)d0["spot"]);
            Assert.Equal("RenameKey", (string)d0["action"]);
            Assert.Equal("上装装备", (string)d0["autoNewValue"]);
            Assert.Equal("EquipmentSlot", (string)d0["kind"]);
        }

        [Fact]
        public void Wire_KeySpotDecision_AmbiguousAnchor_Manual()
        {
            // anchor 全 fffd → 0 候选 → ManualRequired (装备保留, 待人工)
            JObject s = FreshSnapshot();
            JObject equip = (JObject)s["inventory"]["装备栏"];
            JToken val = equip["上装装备"];
            equip.Remove("上装装备");
            equip["����"] = val;

            RepairPlan plan = RepairPolicy.BuildPlan(s, BaseDict());
            JObject wire = RepairCommandHandler.BuildPlanWireJson(plan);
            JObject d0 = (JObject)((JArray)wire["decisions"])[0];

            Assert.Equal("key", (string)d0["spot"]);
            Assert.Equal("ManualRequired", (string)d0["action"]);
        }

        [Fact]
        public void Wire_PathSegments_PreservesArrayIndicesAsStrings()
        {
            JObject s = FreshSnapshot();
            s["5"][0][0] = "基础�击";  // 路径 ["5", "0", "0"]

            RepairPlan plan = RepairPolicy.BuildPlan(s, BaseDict());
            JObject wire = RepairCommandHandler.BuildPlanWireJson(plan);
            JArray path = (JArray)((JObject)((JArray)wire["decisions"])[0])["path"];

            Assert.Equal(3, path.Count);
            Assert.Equal("5", (string)path[0]);
            Assert.Equal("0", (string)path[1]);
            Assert.Equal("0", (string)path[2]);
        }

        [Fact]
        public void Wire_CleanSnapshot_EmptyDecisions()
        {
            JObject s = FreshSnapshot();
            RepairPlan plan = RepairPolicy.BuildPlan(s, BaseDict());
            JObject wire = RepairCommandHandler.BuildPlanWireJson(plan);

            Assert.Equal(0, (int)wire["totalFffd"]);
            Assert.False((bool)wire["willBumpLastSaved"]);
            Assert.Empty((JArray)wire["decisions"]);
        }

        // ─────────────── ApplyPatches ───────────────

        private static JArray Patches(params JObject[] ops)
        {
            JArray arr = new JArray();
            foreach (var o in ops) arr.Add(o);
            return arr;
        }

        private static JObject Patch(string action, string spot, string[] path, string newValue = null, string newKey = null)
        {
            JObject p = new JObject();
            p["action"] = action;
            p["spot"] = spot;
            JArray pathArr = new JArray();
            for (int i = 0; i < path.Length; i++) pathArr.Add(path[i]);
            p["path"] = pathArr;
            if (newValue != null) p["newValue"] = newValue;
            if (newKey != null) p["newKey"] = newKey;
            return p;
        }

        [Fact]
        public void Apply_FixValue_SingleField()
        {
            JObject s = FreshSnapshot();
            s["inventory"]["装备栏"]["上装装备"]["name"] = "黑色�夫装";
            JArray patches = Patches(
                Patch("FixValue", "value",
                    new[] { "inventory", "装备栏", "上装装备", "name" },
                    newValue: "黑色功夫装"));

            int applied; string err;
            bool ok = RepairCommandHandler.ApplyPatches(s, patches, out applied, out err);

            Assert.True(ok);
            Assert.Equal(1, applied);
            Assert.Equal("黑色功夫装", (string)s["inventory"]["装备栏"]["上装装备"]["name"]);
        }

        [Fact]
        public void Apply_DropValue_ArrayIndex()
        {
            JObject s = FreshSnapshot();
            JArray e = new JArray(); e.Add("OK1"); e.Add("坏�"); e.Add("OK2");
            s["others"]["物品来源缓存"]["discoveredEnemies"] = e;
            JArray patches = Patches(
                Patch("DropValue", "value",
                    new[] { "others", "物品来源缓存", "discoveredEnemies", "1" }));

            int applied; string err;
            bool ok = RepairCommandHandler.ApplyPatches(s, patches, out applied, out err);

            Assert.True(ok);
            Assert.Equal(1, applied);
            JArray after = (JArray)s["others"]["物品来源缓存"]["discoveredEnemies"];
            Assert.Equal(2, after.Count);
            Assert.Equal("OK1", (string)after[0]);
            Assert.Equal("OK2", (string)after[1]);
        }

        [Fact]
        public void Apply_MultipleDropValue_SameArray_DescendingOrderPreservesIntegrity()
        {
            JObject s = FreshSnapshot();
            JArray e = new JArray();
            e.Add("OK1"); e.Add("坏一"); e.Add("OK2"); e.Add("坏二"); e.Add("OK3"); e.Add("坏三"); e.Add("OK4");
            s["others"]["物品来源缓存"]["discoveredEnemies"] = e;
            // 故意按升序 (1, 3, 5) 提交; ApplyPatches 内部需 sort 成降序避免 index 漂移.
            JArray patches = Patches(
                Patch("DropValue", "value", new[] { "others", "物品来源缓存", "discoveredEnemies", "1" }),
                Patch("DropValue", "value", new[] { "others", "物品来源缓存", "discoveredEnemies", "3" }),
                Patch("DropValue", "value", new[] { "others", "物品来源缓存", "discoveredEnemies", "5" }));

            int applied; string err;
            bool ok = RepairCommandHandler.ApplyPatches(s, patches, out applied, out err);

            Assert.True(ok);
            Assert.Equal(3, applied);
            JArray after = (JArray)s["others"]["物品来源缓存"]["discoveredEnemies"];
            Assert.Equal(4, after.Count);
            Assert.Equal("OK1", (string)after[0]);
            Assert.Equal("OK2", (string)after[1]);
            Assert.Equal("OK3", (string)after[2]);
            Assert.Equal("OK4", (string)after[3]);
        }

        [Fact]
        public void Apply_RenameKey_Success()
        {
            JObject s = FreshSnapshot();
            JObject byType = new JObject();
            byType["黑铁会�叔"] = 5;
            s["others"]["击杀统计"]["byType"] = byType;
            JArray patches = Patches(
                Patch("RenameKey", "key",
                    new[] { "others", "击杀统计", "byType", "黑铁会�叔" },
                    newKey: "黑铁会大叔"));

            int applied; string err;
            bool ok = RepairCommandHandler.ApplyPatches(s, patches, out applied, out err);

            Assert.True(ok);
            Assert.Equal(1, applied);
            JObject result = (JObject)s["others"]["击杀统计"]["byType"];
            Assert.Equal(5, (int)result["黑铁会大叔"]);
            Assert.Null(result["黑铁会�叔"]);
        }

        [Fact]
        public void Apply_RenameKey_Collision_SkippedNotFatal()
        {
            // collision 不应让整批 patch 回滚; 应跳过有冲突的那条, 让其它 patch 落盘.
            // 与 plan 阶段 (DemoteDuplicateRenameKeys + DecideOne collision guard) 配对的兜底行为.
            JObject s = FreshSnapshot();
            JObject byType = new JObject();
            byType["黑铁会�叔"] = 5;
            byType["黑铁会大叔"] = 9;  // 已存在 → rename 冲突, 应被跳过
            s["others"]["击杀统计"]["byType"] = byType;
            JArray patches = Patches(
                Patch("RenameKey", "key",
                    new[] { "others", "击杀统计", "byType", "黑铁会�叔" },
                    newKey: "黑铁会大叔"));

            int applied; string err;
            bool ok = RepairCommandHandler.ApplyPatches(s, patches, out applied, out err);

            Assert.True(ok);
            Assert.Null(err);
            Assert.Equal(0, applied);  // collision skip → 不计入 applied
            // 双方原 key 都保留, 不被 destructive mutate
            Assert.NotNull(s["others"]["击杀统计"]["byType"]["黑铁会�叔"]);
            Assert.NotNull(s["others"]["击杀统计"]["byType"]["黑铁会大叔"]);
        }

        [Fact]
        public void Apply_ClearValue_TupleShapePreserved()
        {
            JObject s = FreshSnapshot();
            s["5"][0][0] = "完全�陌生�技能";
            JArray patches = Patches(
                Patch("ClearValue", "value", new[] { "5", "0", "0" }));

            int applied; string err;
            bool ok = RepairCommandHandler.ApplyPatches(s, patches, out applied, out err);

            Assert.True(ok);
            Assert.Equal(1, applied);
            Assert.Equal("", (string)s["5"][0][0]);
            Assert.Equal((double)1, (double)s["5"][0][1]); // tuple 形状未被破坏
        }

        [Fact]
        public void Apply_DropKey_Object()
        {
            JObject s = FreshSnapshot();
            JObject byType = new JObject();
            byType["敌人A"] = 3;
            byType["完全�陌生"] = 7;
            s["others"]["击杀统计"]["byType"] = byType;
            JArray patches = Patches(
                Patch("DropKey", "key",
                    new[] { "others", "击杀统计", "byType", "完全�陌生" }));

            int applied; string err;
            bool ok = RepairCommandHandler.ApplyPatches(s, patches, out applied, out err);

            Assert.True(ok);
            Assert.Equal(1, applied);
            JObject result = (JObject)s["others"]["击杀统计"]["byType"];
            Assert.Equal(3, (int)result["敌人A"]);
            Assert.Null(result["完全�陌生"]);
        }

        [Fact]
        public void Apply_PathMissing_SilentSkip()
        {
            JObject s = FreshSnapshot();
            // 路径 'inventory.背包.999.name' 不存在 (背包 是空 array)
            JArray patches = Patches(
                Patch("FixValue", "value",
                    new[] { "inventory", "背包", "999", "name" },
                    newValue: "anything"));

            int applied; string err;
            bool ok = RepairCommandHandler.ApplyPatches(s, patches, out applied, out err);

            Assert.True(ok);
            Assert.Equal(0, applied);
        }

        [Fact]
        public void Apply_MixedPatches_AllAppliedCorrectly()
        {
            JObject s = FreshSnapshot();
            s["inventory"]["装备栏"]["上装装备"]["name"] = "黑色�夫装";
            s["5"][0][0] = "基础�击";
            JArray e = new JArray(); e.Add("某�"); e.Add("OK");
            s["others"]["物品来源缓存"]["discoveredEnemies"] = e;

            JArray patches = Patches(
                Patch("FixValue", "value",
                    new[] { "inventory", "装备栏", "上装装备", "name" },
                    newValue: "黑色功夫装"),
                Patch("FixValue", "value",
                    new[] { "5", "0", "0" },
                    newValue: "基础攻击"),
                Patch("DropValue", "value",
                    new[] { "others", "物品来源缓存", "discoveredEnemies", "0" }));

            int applied; string err;
            bool ok = RepairCommandHandler.ApplyPatches(s, patches, out applied, out err);

            Assert.True(ok);
            Assert.Equal(3, applied);
            Assert.Equal("黑色功夫装", (string)s["inventory"]["装备栏"]["上装装备"]["name"]);
            Assert.Equal("基础攻击", (string)s["5"][0][0]);
            JArray after = (JArray)s["others"]["物品来源缓存"]["discoveredEnemies"];
            Assert.Single(after);
            Assert.Equal("OK", (string)after[0]);
        }

        [Fact]
        public void Apply_FixValue_MissingNewValue_FailsAtomic()
        {
            JObject s = FreshSnapshot();
            JArray patches = new JArray();
            JObject p = new JObject();
            p["action"] = "FixValue";
            p["spot"] = "value";
            p["path"] = JArr("0", "0");
            // 故意不带 newValue
            patches.Add(p);

            int applied; string err;
            bool ok = RepairCommandHandler.ApplyPatches(s, patches, out applied, out err);

            Assert.False(ok);
            Assert.NotNull(err);
        }

        // ─────────────── Navigate ───────────────

        [Fact]
        public void Navigate_ObjectChain_ResolvesParentAndKey()
        {
            JObject root = JObject.Parse(@"{ ""a"": { ""b"": { ""c"": ""target"" } } }");
            JToken parent;
            object key;
            bool ok = RepairCommandHandler.Navigate(root, new[] { "a", "b", "c" }, "value", out parent, out key);

            Assert.True(ok);
            Assert.Equal(JTokenType.Object, parent.Type);
            Assert.Equal("c", (string)key);
            Assert.Equal("target", (string)((JObject)parent)[(string)key]);
        }

        [Fact]
        public void Navigate_ArrayIndex_ResolvesIntKey()
        {
            JObject root = JObject.Parse(@"{ ""arr"": [""a"", ""b"", ""c""] }");
            JToken parent;
            object key;
            bool ok = RepairCommandHandler.Navigate(root, new[] { "arr", "1" }, "value", out parent, out key);

            Assert.True(ok);
            Assert.Equal(JTokenType.Array, parent.Type);
            Assert.IsType<int>(key);
            Assert.Equal(1, (int)key);
            Assert.Equal("b", (string)((JArray)parent)[(int)key]);
        }

        [Fact]
        public void Navigate_OutOfRangeIndex_ReturnsFalse()
        {
            JObject root = JObject.Parse(@"{ ""arr"": [""a""] }");
            JToken parent;
            object key;
            // 末段 999 越界但仍 navigate 成功 (parent=arr, key=999); 调用方 SetValue/RemoveAt 会 noop.
            // 这里测中间段越界.
            bool ok = RepairCommandHandler.Navigate(root, new[] { "arr", "999", "x" }, "value", out parent, out key);
            Assert.False(ok);
        }
    }
}
