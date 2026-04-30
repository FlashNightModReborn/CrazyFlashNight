// 字段分层规则（与 tools/cf7-save-repair/src/layering.ts 同源）
//
// L0：阻塞修复，必须人工介入（C2-α 不动）
//   - $[0][0] 角色名（自由文本，无字典可对齐）
//   - $.lastSaved（时间戳）
// L1：字典对齐；命中即修，未命中保留占位 + 提示人工
//   - $.inventory.{背包,装备栏,药剂栏,仓库,战备箱}.*.name
//   - $.inventory.装备栏.*.value.mods[*]（mod 名）
// L2：字典对齐；命中即修，未命中静默丢弃（非关键引用）
//   - $.tasks.tasks_finished[<key>]
//   - $.tasks.task_chains_progress[<key>]
//   - $.others.击杀统计.byType[<key>]
//   - $[5][N][0] 技能名 / $[5][N][3] 技能模式
//   - $[1][N] 发型/外观
//   - $.collection.{材料,情报}[<key>]
// L3：静默丢弃，下次玩自动重建
//   - $.others.物品来源缓存.*[N]
//   - $.others.设置.<键>
//   - $[0][10][N][0..1] 键位标签
//
// C# 5 语法（避免 lambda 表达式 / 模式匹配等较新特性）。

using System;

namespace CF7Launcher.Save
{
    public enum SaveFieldLayer
    {
        L0,
        L1,
        L2,
        L3,
    }

    public enum SaveFieldKind
    {
        Item,
        Mod,
        Enemy,
        Skill,
        Hairstyle,
        Stage,
        TaskChain,
        QuestId,
        FreeText,
        Unknown,
    }

    public enum SaveFieldFallback
    {
        /// <summary>L1 未命中：保留占位 '[损坏 待修复]'</summary>
        Preserve,
        /// <summary>L2/L3：静默丢弃</summary>
        Drop,
        /// <summary>L0 / L1 槽位 key：阻塞，人工介入</summary>
        Manual,
    }

    /// <summary>drop 时的具体方式（splice 数组 / 设空串保 tuple 形状 / 删 object key）。</summary>
    public enum SaveFieldDropMode
    {
        Splice,
        Clear,
        Key,
    }

    public class SaveFieldRule
    {
        public readonly SaveFieldLayer Layer;
        public readonly SaveFieldKind Kind;
        public readonly SaveFieldFallback Fallback;
        public readonly SaveFieldDropMode DropMode;

        public SaveFieldRule(SaveFieldLayer layer, SaveFieldKind kind, SaveFieldFallback fallback, SaveFieldDropMode dropMode)
        {
            Layer = layer;
            Kind = kind;
            Fallback = fallback;
            DropMode = dropMode;
        }
    }

    public static class SaveFieldLayering
    {
        private static readonly SaveFieldRule Default =
            new SaveFieldRule(SaveFieldLayer.L3, SaveFieldKind.Unknown, SaveFieldFallback.Drop, SaveFieldDropMode.Splice);

        public static SaveFieldRule Classify(string[] path)
        {
            // L0: $[0][0] 角色名
            if (path.Length == 2 && path[0] == "0" && path[1] == "0")
                return new SaveFieldRule(SaveFieldLayer.L0, SaveFieldKind.FreeText, SaveFieldFallback.Manual, SaveFieldDropMode.Clear);
            // L0: $.lastSaved
            if (path.Length == 1 && path[0] == "lastSaved")
                return new SaveFieldRule(SaveFieldLayer.L0, SaveFieldKind.FreeText, SaveFieldFallback.Manual, SaveFieldDropMode.Clear);

            // L1: inventory subcat 物品名
            if (path.Length == 4 && path[0] == "inventory" && IsInventorySubcat(path[1]) && path[3] == "name")
                return new SaveFieldRule(SaveFieldLayer.L1, SaveFieldKind.Item, SaveFieldFallback.Preserve, SaveFieldDropMode.Splice);

            // L1: equipment mod (path: inventory/<sub>/<id>/value/mods/<idx>)
            if (path.Length >= 6 && path[0] == "inventory" && IsInventorySubcat(path[1]) && path[3] == "value" && path[4] == "mods")
                return new SaveFieldRule(SaveFieldLayer.L1, SaveFieldKind.Mod, SaveFieldFallback.Preserve, SaveFieldDropMode.Splice);

            // L1: 装备栏槽位 key（如 '颈部装备' fffd 化）
            if (path.Length == 3 && path[0] == "inventory" && path[1] == "装备栏")
                return new SaveFieldRule(SaveFieldLayer.L1, SaveFieldKind.Unknown, SaveFieldFallback.Manual, SaveFieldDropMode.Key);

            // L2: tasks_finished[key]
            if (path.Length >= 2 && path[0] == "tasks" && path[1] == "tasks_finished")
                return new SaveFieldRule(SaveFieldLayer.L2, SaveFieldKind.QuestId, SaveFieldFallback.Drop, SaveFieldDropMode.Key);
            if (path.Length >= 2 && path[0] == "tasks" && path[1] == "task_chains_progress")
                return new SaveFieldRule(SaveFieldLayer.L2, SaveFieldKind.TaskChain, SaveFieldFallback.Drop, SaveFieldDropMode.Key);

            // L2: 击杀统计 byType
            if (path.Length >= 3 && path[0] == "others" && path[1] == "击杀统计" && path[2] == "byType")
                return new SaveFieldRule(SaveFieldLayer.L2, SaveFieldKind.Enemy, SaveFieldFallback.Drop, SaveFieldDropMode.Key);

            // L2: 技能名 [5][N][0]
            if (path.Length == 3 && path[0] == "5" && path[2] == "0")
                return new SaveFieldRule(SaveFieldLayer.L2, SaveFieldKind.Skill, SaveFieldFallback.Drop, SaveFieldDropMode.Clear);
            // [5][N][3] 技能模式描述串
            if (path.Length == 3 && path[0] == "5" && path[2] == "3")
                return new SaveFieldRule(SaveFieldLayer.L3, SaveFieldKind.Unknown, SaveFieldFallback.Drop, SaveFieldDropMode.Clear);

            // [0][10][N][0..1] 键位标签
            if (path.Length == 4 && path[0] == "0" && path[1] == "10" && (path[3] == "0" || path[3] == "1"))
                return new SaveFieldRule(SaveFieldLayer.L3, SaveFieldKind.Unknown, SaveFieldFallback.Drop, SaveFieldDropMode.Clear);

            // L2: 发型 [1][N]
            if (path.Length == 2 && path[0] == "1")
                return new SaveFieldRule(SaveFieldLayer.L2, SaveFieldKind.Hairstyle, SaveFieldFallback.Drop, SaveFieldDropMode.Clear);

            // L2: collection
            if (path.Length >= 2 && path[0] == "collection" && (path[1] == "材料" || path[1] == "情报"))
                return new SaveFieldRule(SaveFieldLayer.L2, SaveFieldKind.Item, SaveFieldFallback.Drop, SaveFieldDropMode.Key);

            // L3: 物品来源缓存（按子类标 kind，便于 audit）
            if (path.Length >= 3 && path[0] == "others" && path[1] == "物品来源缓存")
            {
                if (path[2] == "discoveredEnemies")
                    return new SaveFieldRule(SaveFieldLayer.L3, SaveFieldKind.Enemy, SaveFieldFallback.Drop, SaveFieldDropMode.Splice);
                if (path[2] == "discoveredQuests" || path[2] == "completedChallengeQuests")
                    return new SaveFieldRule(SaveFieldLayer.L3, SaveFieldKind.QuestId, SaveFieldFallback.Drop, SaveFieldDropMode.Splice);
                if (path[2] == "discoveredStages")
                    return new SaveFieldRule(SaveFieldLayer.L3, SaveFieldKind.Stage, SaveFieldFallback.Drop, SaveFieldDropMode.Splice);
            }

            // L3: 设置
            if (path.Length >= 2 && path[0] == "others" && path[1] == "设置")
                return new SaveFieldRule(SaveFieldLayer.L3, SaveFieldKind.Unknown, SaveFieldFallback.Drop, SaveFieldDropMode.Key);

            return Default;
        }

        private static bool IsInventorySubcat(string s)
        {
            return s == "背包" || s == "装备栏" || s == "药剂栏" || s == "仓库" || s == "战备箱";
        }
    }
}
