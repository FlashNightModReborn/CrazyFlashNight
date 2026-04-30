// RepairPolicy 端到端测试：BuildPlan + ApplyHighConfidenceOnly。
// 与 tools/cf7-save-repair/tests/repair.test.ts 对齐的关键 case 镜像版。

using System;
using System.Collections.Generic;
using CF7Launcher.Save;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Save
{
    public class RepairPolicyTests
    {
        // ─────────────── helpers ───────────────

        private static RepairDictionary BaseDict()
        {
            JObject d = new JObject();
            d["schemaVersion"] = 1;
            d["generated"] = new JObject();
            d["items"] = JArr("黑色功夫装", "咖啡色多包裤", "棕色皮鞋");
            d["mods"] = JArr("攻击+5");
            d["enemies"] = JArr("黑铁会大叔", "军阀步兵");
            d["hairstyles"] = JArr("发型-男式-黑暴走头");
            d["skills"] = JArr("基础攻击", "空翻踢", "强化拳");
            d["taskChains"] = JArr("主线");
            d["stages"] = JArr("第一关", "第二关");
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
                ""1"": [""发型-男式-黑暴走头""],
                ""5"": [
                    [""基础攻击"", 1, true, """", true],
                    [""空翻踢"", 1, false, """", true]
                ],
                ""inventory"": {
                    ""装备栏"": {
                        ""上装装备"": { ""name"": ""黑色功夫装"", ""value"": { ""mods"": [], ""level"": 1 } },
                        ""下装装备"": { ""name"": ""咖啡色多包裤"", ""value"": { ""mods"": [], ""level"": 1 } }
                    },
                    ""背包"": {}
                },
                ""tasks"": { ""tasks_finished"": {}, ""task_chains_progress"": { ""主线"": 0 } },
                ""others"": {
                    ""设置"": { ""jukeboxPlayMode"": ""singleLoop"" },
                    ""击杀统计"": { ""total"": 0, ""byType"": {} },
                    ""物品来源缓存"": { ""discoveredStages"": [], ""discoveredEnemies"": [], ""discoveredQuests"": [] }
                },
                ""collection"": { ""材料"": {}, ""情报"": {} }
            }");
        }

        private static readonly DateTime NowUtc = new DateTime(2026, 4, 30, 12, 0, 0, DateTimeKind.Utc);

        // ─────────────── tests ───────────────

        [Fact]
        public void L1_DictUnique_FixValue_BumpLastSaved()
        {
            JObject s = FreshSnapshot();
            s["inventory"]["装备栏"]["上装装备"]["name"] = "黑色�夫装";
            RepairPlan plan = RepairPolicy.BuildPlan(s, BaseDict());
            Assert.Equal(1, plan.Scan.Total);
            Assert.Equal(RepairActionKind.FixValue, plan.Decisions[0].Action.Kind);
            Assert.Equal("黑色功夫装", plan.Decisions[0].Action.NewValue);

            string before = s.Value<string>("lastSaved");
            RepairApplyResult r = RepairPolicy.ApplyHighConfidenceOnly(s, plan, NowUtc);
            Assert.Equal(1, r.Applied);
            Assert.Equal("2026-04-30 12:00:00", r.BumpedLastSaved);
            Assert.Equal("黑色功夫装", (string)s["inventory"]["装备栏"]["上装装备"]["name"]);
            Assert.NotEqual(before, s.Value<string>("lastSaved"));
        }

        [Fact]
        public void L2_Skill_DictUnique_FixValue()
        {
            JObject s = FreshSnapshot();
            s["5"][0][0] = "基础�击";
            RepairPlan plan = RepairPolicy.BuildPlan(s, BaseDict());
            Assert.Equal(RepairActionKind.FixValue, plan.Decisions[0].Action.Kind);
            RepairPolicy.ApplyHighConfidenceOnly(s, plan, NowUtc);
            Assert.Equal("基础攻击", (string)s["5"][0][0]);
        }

        [Fact]
        public void L1_NoCandidate_PreservePlaceholder_KeptForManual()
        {
            JObject s = FreshSnapshot();
            s["inventory"]["装备栏"]["上装装备"]["name"] = "完全�生�词";  // 不可还原
            RepairPlan plan = RepairPolicy.BuildPlan(s, BaseDict());
            Assert.Equal(RepairActionKind.PreservePlaceholder, plan.Decisions[0].Action.Kind);
            // C2-α 不自动写占位 → SkippedManual+1, fffd 仍在
            RepairApplyResult r = RepairPolicy.ApplyHighConfidenceOnly(s, plan, NowUtc);
            Assert.Equal(1, r.SkippedManual);
            Assert.Equal(0, r.Applied);
            Assert.Null(r.BumpedLastSaved); // 全是 manual → 不 bump
            // fffd 字符仍在原文（等 C2-β 卡片处理）
            Assert.Contains("�", (string)s["inventory"]["装备栏"]["上装装备"]["name"]);
        }

        [Fact]
        public void L2_Skill_NoCandidate_ClearValue()
        {
            JObject s = FreshSnapshot();
            s["5"][0][0] = "完全�陌生�技能";
            RepairPlan plan = RepairPolicy.BuildPlan(s, BaseDict());
            Assert.Equal(RepairActionKind.ClearValue, plan.Decisions[0].Action.Kind);
            RepairPolicy.ApplyHighConfidenceOnly(s, plan, NowUtc);
            Assert.Equal("", (string)s["5"][0][0]);
            Assert.Equal((double)1, (double)s["5"][0][1]); // tuple 形状保留
        }

        [Fact]
        public void L3_DiscoveredEnemies_SpliceOrder_DescendingByIndex()
        {
            JObject s = FreshSnapshot();
            JArray arr = new JArray();
            arr.Add("OK1"); arr.Add("坏�一"); arr.Add("OK2"); arr.Add("坏�二"); arr.Add("OK3"); arr.Add("坏�三"); arr.Add("OK4");
            s["others"]["物品来源缓存"]["discoveredEnemies"] = arr;
            RepairPlan plan = RepairPolicy.BuildPlan(s, BaseDict());
            Assert.Equal(3, plan.Scan.Total);
            RepairPolicy.ApplyHighConfidenceOnly(s, plan, NowUtc);
            JArray after = (JArray)s["others"]["物品来源缓存"]["discoveredEnemies"];
            Assert.Equal(4, after.Count);
            Assert.Equal("OK1", (string)after[0]);
            Assert.Equal("OK2", (string)after[1]);
            Assert.Equal("OK3", (string)after[2]);
            Assert.Equal("OK4", (string)after[3]);
        }

        [Fact]
        public void L0_PlayerName_ManualRequired_NotAutoFixed()
        {
            JObject s = FreshSnapshot();
            s["0"][0] = "玩家�";
            RepairPlan plan = RepairPolicy.BuildPlan(s, BaseDict());
            Assert.Equal(RepairActionKind.ManualRequired, plan.Decisions[0].Action.Kind);
            Assert.Equal(1, plan.ManualRequired);

            RepairApplyResult r = RepairPolicy.ApplyHighConfidenceOnly(s, plan, NowUtc);
            Assert.Equal(1, r.SkippedManual);
            Assert.Equal(0, r.Applied);
            Assert.Null(r.BumpedLastSaved);
            Assert.Equal("玩家�", (string)s["0"][0]); // 未变
        }

        [Fact]
        public void RenameKey_ByType_Enemy()
        {
            JObject s = FreshSnapshot();
            JObject byType = new JObject();
            byType["黑铁会�叔"] = 5;
            byType["军阀步兵"] = 2;
            s["others"]["击杀统计"]["byType"] = byType;
            RepairPlan plan = RepairPolicy.BuildPlan(s, BaseDict());
            Assert.Equal(RepairActionKind.RenameKey, plan.Decisions[0].Action.Kind);
            Assert.Equal("黑铁会大叔", plan.Decisions[0].Action.NewValue);
            RepairPolicy.ApplyHighConfidenceOnly(s, plan, NowUtc);
            JObject result = (JObject)s["others"]["击杀统计"]["byType"];
            Assert.Equal(5, (int)result["黑铁会大叔"]);
            Assert.Null(result["黑铁会�叔"]);
        }

        [Fact]
        public void AnchorSubsequence_CumulativeFffd_Recovers()
        {
            // 模拟累积扩张：1 个 CJK 字符膨胀成多个 fffd
            JObject s = FreshSnapshot();
            s["inventory"]["装备栏"]["上装装备"]["name"] = "黑色�����功�����夫装";
            RepairPlan plan = RepairPolicy.BuildPlan(s, BaseDict());
            // anchor=[黑,色,功,夫,装]，dict 中只有 '黑色功夫装' 命中
            Assert.Equal(RepairActionKind.FixValue, plan.Decisions[0].Action.Kind);
            Assert.Equal("黑色功夫装", plan.Decisions[0].Action.NewValue);
            RepairPolicy.ApplyHighConfidenceOnly(s, plan, NowUtc);
            Assert.Equal("黑色功夫装", (string)s["inventory"]["装备栏"]["上装装备"]["name"]);
        }

        [Fact]
        public void Mixed_AllLayers_BumpsLastSavedOnceAtomic()
        {
            JObject s = FreshSnapshot();
            s["inventory"]["装备栏"]["上装装备"]["name"] = "黑色�夫装";   // L1 fix
            s["5"][0][0] = "基础�击";                                      // L2 fix
            JArray e = new JArray(); e.Add("某�"); e.Add("OK");
            s["others"]["物品来源缓存"]["discoveredEnemies"] = e;          // L3 splice (单候选 unique 也照 L3 drop)
            s["0"][0] = "玩家�";                                            // L0 manual

            RepairPlan plan = RepairPolicy.BuildPlan(s, BaseDict());
            Assert.Equal(4, plan.Scan.Total);

            string before = s.Value<string>("lastSaved");
            RepairApplyResult r = RepairPolicy.ApplyHighConfidenceOnly(s, plan, NowUtc);
            Assert.Equal(2, r.Applied);     // L1 + L2
            Assert.Equal(1, r.Drops);       // L3
            Assert.Equal(1, r.SkippedManual); // L0
            Assert.NotEqual(before, s.Value<string>("lastSaved"));
            Assert.Equal("2026-04-30 12:00:00", s.Value<string>("lastSaved"));
        }

        [Fact]
        public void InventoryEquipSlotKey_DictUnique_AutoRenameKey()
        {
            // EquipmentSlot kind: 硬编码 11 个槽位字典命中即自动 RenameKey, 不再 ManualRequired.
            // anchor=[上,装,备] 在 EquipmentSlots 字典里 unique 命中 '上装装备'.
            JObject s = FreshSnapshot();
            JObject equip = (JObject)s["inventory"]["装备栏"];
            JToken val = equip["上装装备"];
            equip.Remove("上装装备");
            equip["上�装备"] = val;

            RepairPlan plan = RepairPolicy.BuildPlan(s, BaseDict());
            Assert.Equal(1, plan.Scan.Total);
            Assert.Equal(RepairActionKind.RenameKey, plan.Decisions[0].Action.Kind);
            Assert.Equal("上装装备", plan.Decisions[0].Action.NewValue);

            RepairApplyResult r = RepairPolicy.ApplyHighConfidenceOnly(s, plan, NowUtc);
            Assert.Equal(1, r.Applied);
            Assert.NotNull(s["inventory"]["装备栏"]["上装装备"]);
            Assert.Null(s["inventory"]["装备栏"]["上�装备"]);
        }

        [Fact]
        public void InventoryEquipSlotKey_AnchorAmbiguous_FallbackManual()
        {
            // anchor 全 fffd → 0 候选 → fallback Manual (装备保留, 不丢).
            JObject s = FreshSnapshot();
            JObject equip = (JObject)s["inventory"]["装备栏"];
            JToken val = equip["上装装备"];
            equip.Remove("上装装备");
            equip["����"] = val;

            RepairPlan plan = RepairPolicy.BuildPlan(s, BaseDict());
            Assert.Equal(1, plan.Scan.Total);
            Assert.Equal(RepairActionKind.ManualRequired, plan.Decisions[0].Action.Kind);
            RepairPolicy.ApplyHighConfidenceOnly(s, plan, NowUtc);
            Assert.NotNull(s["inventory"]["装备栏"]["����"]);
        }

        [Fact]
        public void InventoryEquipSlotKey_TargetAlreadyExists_DemotedToManual()
        {
            // collision guard: 父 obj 已有合法 '颈部装备' 同时存在损坏 '颈部���备' (anchor 命中
            // 同一 target). 自动 RenameKey 会让 ApplyPatches 撞键失败 → 整批回滚.
            // plan 阶段必须 demote 到 Manual, 让用户决定丢弃 / 改成另一个槽位名.
            JObject s = FreshSnapshot();
            JObject equip = new JObject();
            equip["颈部装备"] = JObject.Parse(@"{""name"":""x"",""value"":{""mods"":[],""level"":1}}"); // 合法 key
            equip["颈部�备"] = JObject.Parse(@"{""name"":""y"",""value"":{""mods"":[],""level"":1}}"); // 损坏 key
            s["inventory"]["装备栏"] = equip;

            RepairPlan plan = RepairPolicy.BuildPlan(s, BaseDict());
            Assert.Equal(1, plan.Scan.Total);
            Assert.Equal(RepairActionKind.ManualRequired, plan.Decisions[0].Action.Kind);

            // 跑 ApplyHighConfidenceOnly 不会动它 (manual 不自动跑)
            RepairPolicy.ApplyHighConfidenceOnly(s, plan, NowUtc);
            Assert.NotNull(s["inventory"]["装备栏"]["颈部装备"]);
            Assert.NotNull(s["inventory"]["装备栏"]["颈部�备"]);
        }

        [Fact]
        public void DuplicateRenameKey_SecondDemotedToManual()
        {
            // 同 parent 上两条 RenameKey 都要把不同 broken key 改成 '黑铁会大叔' (字典 unique 命中).
            // 第一条 RenameKey 保留, 第二条降级 Manual, 防止 ApplyPatches 撞键失败.
            JObject s = FreshSnapshot();
            JObject byType = new JObject();
            byType["黑铁会�叔"] = 5;
            byType["�铁会大叔"] = 3;
            s["others"]["击杀统计"]["byType"] = byType;

            RepairPlan plan = RepairPolicy.BuildPlan(s, BaseDict());
            Assert.Equal(2, plan.Scan.Total);

            int renameCount = 0, manualCount = 0;
            for (int i = 0; i < plan.Decisions.Count; i++)
            {
                if (plan.Decisions[i].Action.Kind == RepairActionKind.RenameKey) renameCount++;
                if (plan.Decisions[i].Action.Kind == RepairActionKind.ManualRequired) manualCount++;
            }
            Assert.Equal(1, renameCount);
            Assert.Equal(1, manualCount);
        }

        [Fact]
        public void CleanSnapshot_NoOp()
        {
            JObject s = FreshSnapshot();
            RepairPlan plan = RepairPolicy.BuildPlan(s, BaseDict());
            Assert.Equal(0, plan.Scan.Total);
            RepairApplyResult r = RepairPolicy.ApplyHighConfidenceOnly(s, plan, NowUtc);
            Assert.Equal(0, r.Applied);
            Assert.Null(r.BumpedLastSaved);
        }
    }
}
