// 修复 plan 构建 + 应用。与 tools/cf7-save-repair/src/repair.ts 同源。
//
// C2-α 仅自动应用「高置信度安全修复」：
//   - fix_value / rename_key（self_ref 或 dict_unique）
//   - clear_value（L2/L3 固定 tuple 槽位置空）
//   - drop_value（L3 splice push-list）
//   - drop_key（L2/L3 object key 删除）
// 跳过：
//   - manual_required（L0 / L1 多候选 / L1 装备槽位 key）→ 等 C2-β 卡片
//   - preserve_placeholder（L1 0 候选）→ 等 C2-β 卡片
// 即「保守自动」：高置信度修，疑难留人工。

using System;
using System.Collections.Generic;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Save
{
    public enum RepairActionKind
    {
        FixValue,
        RenameKey,
        DropValue,
        ClearValue,
        DropKey,
        PreservePlaceholder,
        ManualRequired,
    }

    public class RepairAction
    {
        public readonly RepairActionKind Kind;
        public readonly string NewValue;     // FixValue / RenameKey
        public readonly RepairCandidate Via; // FixValue / RenameKey

        public RepairAction(RepairActionKind kind, string newValue, RepairCandidate via)
        {
            Kind = kind;
            NewValue = newValue;
            Via = via;
        }

        public static readonly RepairAction DropValue = new RepairAction(RepairActionKind.DropValue, null, null);
        public static readonly RepairAction ClearValue = new RepairAction(RepairActionKind.ClearValue, null, null);
        public static readonly RepairAction DropKey = new RepairAction(RepairActionKind.DropKey, null, null);
        public static readonly RepairAction Manual = new RepairAction(RepairActionKind.ManualRequired, null, null);
        public static readonly RepairAction Preserve = new RepairAction(RepairActionKind.PreservePlaceholder, null, null);
    }

    public class RepairDecision
    {
        public readonly SaveCorruptionItem Item;
        public readonly RepairAction Action;
        public readonly List<RepairCandidate> Candidates;

        public RepairDecision(SaveCorruptionItem item, RepairAction action, List<RepairCandidate> candidates)
        {
            Item = item;
            Action = action;
            Candidates = candidates;
        }
    }

    public class RepairPlan
    {
        public readonly SaveCorruptionReport Scan;
        public readonly List<RepairDecision> Decisions;
        public readonly int ManualRequired;
        public readonly bool WillBumpLastSaved;

        public RepairPlan(SaveCorruptionReport scan, List<RepairDecision> decisions)
        {
            Scan = scan;
            Decisions = decisions;
            int manual = 0;
            bool bump = false;
            for (int i = 0; i < decisions.Count; i++)
            {
                if (decisions[i].Action.Kind == RepairActionKind.ManualRequired) manual++;
                else if (decisions[i].Action.Kind != RepairActionKind.PreservePlaceholder) bump = true;
            }
            ManualRequired = manual;
            WillBumpLastSaved = bump;
        }
    }

    public class RepairApplyResult
    {
        public int Applied;
        public int Drops;
        public int Preserves;
        public int SkippedManual;
        /// <summary>WillBumpLastSaved 时的新值；null 表示未 bump（无可应用项）。</summary>
        public string BumpedLastSaved;
    }

    public static class RepairPolicy
    {
        public const string Placeholder = "[损坏 待修复]";

        public static RepairPlan BuildPlan(JObject snapshot, RepairDictionary dict)
        {
            SaveCorruptionReport report = SaveCorruptionScanner.Scan(snapshot);
            SelfRefPool selfRef = SelfRefPool.Build(snapshot);

            List<RepairDecision> decisions = new List<RepairDecision>(report.Items.Count);
            for (int i = 0; i < report.Items.Count; i++)
            {
                decisions.Add(DecideOne(report.Items[i], dict, selfRef));
            }
            return new RepairPlan(report, decisions);
        }

        private static RepairDecision DecideOne(SaveCorruptionItem item, RepairDictionary dict, SelfRefPool selfRef)
        {
            string[] bucket = dict.GetBucket(item.Rule.Kind);
            string[] selfPool = selfRef.Get(item.Rule.Kind);
            List<RepairCandidate> candidates = RepairMatcher.FindCandidates(item.BrokenString, bucket, selfPool);

            RepairCandidate top = candidates.Count > 0 ? candidates[0] : null;
            bool highConf = top != null && (top.Source == RepairCandidateSource.SelfRef || top.Source == RepairCandidateSource.DictUnique);

            // L0: 永远 manual
            if (item.Rule.Layer == SaveFieldLayer.L0)
                return new RepairDecision(item, RepairAction.Manual, candidates);

            // L3: 永远 fallback (drop)；候选只用于 audit
            if (item.Rule.Layer == SaveFieldLayer.L3)
                return new RepairDecision(item, ApplyFallbackAction(item), candidates);

            // L1 / L2: 高置信度命中即修
            if (highConf)
            {
                if (item.Spot == SaveCorruptionSpot.Key)
                    return new RepairDecision(item,
                        new RepairAction(RepairActionKind.RenameKey, top.Value, top),
                        candidates);
                return new RepairDecision(item,
                    new RepairAction(RepairActionKind.FixValue, top.Value, top),
                    candidates);
            }

            // L1: 多候选 → manual；0 候选 → fallback
            if (item.Rule.Layer == SaveFieldLayer.L1)
            {
                if (candidates.Count > 1)
                    return new RepairDecision(item, RepairAction.Manual, candidates);
                return new RepairDecision(item, ApplyFallbackAction(item), candidates);
            }

            // L2: 多/0 候选都 fallback
            return new RepairDecision(item, ApplyFallbackAction(item), candidates);
        }

        private static RepairAction ApplyFallbackAction(SaveCorruptionItem item)
        {
            switch (item.Rule.Fallback)
            {
                case SaveFieldFallback.Manual:   return RepairAction.Manual;
                case SaveFieldFallback.Preserve: return RepairAction.Preserve;
                case SaveFieldFallback.Drop:
                default:
                    if (item.Spot == SaveCorruptionSpot.Key) return RepairAction.DropKey;
                    switch (item.Rule.DropMode)
                    {
                        case SaveFieldDropMode.Clear:  return RepairAction.ClearValue;
                        case SaveFieldDropMode.Key:    return RepairAction.DropKey;
                        case SaveFieldDropMode.Splice:
                        default:                       return RepairAction.DropValue;
                    }
            }
        }

        /// <summary>
        /// 应用 plan。仅自动施用「高置信度安全修复」（C2-α）：
        /// preserve_placeholder / manual_required 不动，等 C2-β 卡片处理。
        ///
        /// 多个 splice 在同一数组上必须按 parentKey 降序应用，否则前一个 splice
        /// 让后续索引漂移。下面 sort 保证 splice 排到最后并按降序处理。
        /// </summary>
        public static RepairApplyResult ApplyHighConfidenceOnly(JObject snapshot, RepairPlan plan, DateTime utcNow)
        {
            RepairApplyResult r = new RepairApplyResult();

            // 排序：splice (drop_value on JArray) 排到末尾，按 parentKey 降序
            List<RepairDecision> ordered = new List<RepairDecision>(plan.Decisions);
            ordered.Sort(CompareForSpliceOrder);

            for (int i = 0; i < ordered.Count; i++)
            {
                SaveCorruptionItem item = ordered[i].Item;
                RepairAction act = ordered[i].Action;

                switch (act.Kind)
                {
                    case RepairActionKind.ManualRequired:
                        r.SkippedManual++;
                        break;

                    case RepairActionKind.PreservePlaceholder:
                        // C2-α 不自动写占位串：保留 fffd 原状，留给 C2-β 卡片。
                        // 计入 SkippedManual 让 audit 体现"等人工"。
                        r.SkippedManual++;
                        break;

                    case RepairActionKind.FixValue:
                        SetValue(item.Parent, item.ParentKey, act.NewValue);
                        r.Applied++;
                        break;

                    case RepairActionKind.RenameKey:
                        RenameKey((JObject)item.Parent, (string)item.ParentKey, act.NewValue);
                        r.Applied++;
                        break;

                    case RepairActionKind.ClearValue:
                        SetValue(item.Parent, item.ParentKey, "");
                        r.Drops++;
                        break;

                    case RepairActionKind.DropValue:
                        if (item.Parent.Type == JTokenType.Array)
                        {
                            JArray arr = (JArray)item.Parent;
                            int idx = (int)item.ParentKey;
                            if (idx >= 0 && idx < arr.Count) arr.RemoveAt(idx);
                        }
                        else if (item.Parent.Type == JTokenType.Object)
                        {
                            ((JObject)item.Parent).Remove((string)item.ParentKey);
                        }
                        r.Drops++;
                        break;

                    case RepairActionKind.DropKey:
                        ((JObject)item.Parent).Remove((string)item.ParentKey);
                        r.Drops++;
                        break;
                }
            }

            // bump lastSaved (INV-1) 仅当确实应用了修复
            if (r.Applied > 0 || r.Drops > 0)
            {
                string ts = utcNow.ToString("yyyy-MM-dd HH:mm:ss");
                snapshot["lastSaved"] = ts;
                r.BumpedLastSaved = ts;
            }

            return r;
        }

        private static int CompareForSpliceOrder(RepairDecision a, RepairDecision b)
        {
            bool aSplice = a.Action.Kind == RepairActionKind.DropValue && a.Item.Parent.Type == JTokenType.Array;
            bool bSplice = b.Action.Kind == RepairActionKind.DropValue && b.Item.Parent.Type == JTokenType.Array;
            if (aSplice != bSplice) return aSplice ? 1 : -1;
            if (aSplice && bSplice)
            {
                int ai = (int)a.Item.ParentKey;
                int bi = (int)b.Item.ParentKey;
                return bi - ai; // 降序
            }
            return 0;
        }

        private static void SetValue(JToken parent, object parentKey, string value)
        {
            if (parent.Type == JTokenType.Array)
            {
                ((JArray)parent)[(int)parentKey] = value;
            }
            else
            {
                ((JObject)parent)[(string)parentKey] = value;
            }
        }

        private static void RenameKey(JObject obj, string oldKey, string newKey)
        {
            if (obj == null || oldKey == null || newKey == null) return;
            if (oldKey == newKey) return;
            JToken val = obj[oldKey];
            obj.Remove(oldKey);
            // 若 newKey 已存在则保留旧 key 的值（覆盖）
            obj[newKey] = val;
        }

        // ─────────────────── 自参考池 ───────────────────

        /// <summary>
        /// 同存档自参考池：从未坏掉的字段聚合 string 备选，按 FieldKind 分桶。
        /// </summary>
        private class SelfRefPool
        {
            private readonly Dictionary<SaveFieldKind, List<string>> _buckets = new Dictionary<SaveFieldKind, List<string>>();

            public string[] Get(SaveFieldKind kind)
            {
                List<string> list;
                if (_buckets.TryGetValue(kind, out list)) return list.ToArray();
                return new string[0];
            }

            public static SelfRefPool Build(JObject snapshot)
            {
                SelfRefPool p = new SelfRefPool();

                // 装备栏 name → item
                JObject equipSlots = SafeChild<JObject>(snapshot, "inventory", "装备栏");
                if (equipSlots != null)
                {
                    foreach (JProperty slot in equipSlots.Properties())
                    {
                        JObject obj = slot.Value as JObject;
                        if (obj == null) continue;
                        string name = obj.Value<string>("name");
                        p.Push(SaveFieldKind.Item, name);
                    }
                }

                // 击杀统计.byType keys → enemy
                JObject byType = SafeChild<JObject>(snapshot, "others", "击杀统计", "byType");
                if (byType != null)
                {
                    foreach (JProperty prop in byType.Properties())
                        p.Push(SaveFieldKind.Enemy, prop.Name);
                }

                // 物品来源缓存.discoveredEnemies → enemy
                JArray discE = SafeChild<JArray>(snapshot, "others", "物品来源缓存", "discoveredEnemies");
                if (discE != null)
                {
                    for (int i = 0; i < discE.Count; i++)
                    {
                        JToken t = discE[i];
                        if (t != null && t.Type == JTokenType.String) p.Push(SaveFieldKind.Enemy, t.Value<string>());
                    }
                }

                // collection.材料 / 情报 keys → item
                string[] cats = new string[] { "材料", "情报" };
                for (int i = 0; i < cats.Length; i++)
                {
                    JObject c = SafeChild<JObject>(snapshot, "collection", cats[i]);
                    if (c == null) continue;
                    foreach (JProperty prop in c.Properties())
                        p.Push(SaveFieldKind.Item, prop.Name);
                }

                return p;
            }

            private void Push(SaveFieldKind kind, string v)
            {
                if (string.IsNullOrEmpty(v)) return;
                if (v.IndexOf(SaveCorruptionScanner.FFFD) >= 0) return;
                List<string> list;
                if (!_buckets.TryGetValue(kind, out list))
                {
                    list = new List<string>();
                    _buckets[kind] = list;
                }
                list.Add(v);
            }

            private static T SafeChild<T>(JToken root, params string[] path) where T : JToken
            {
                JToken cur = root;
                for (int i = 0; i < path.Length; i++)
                {
                    JObject obj = cur as JObject;
                    if (obj == null) return null;
                    cur = obj[path[i]];
                    if (cur == null) return null;
                }
                return cur as T;
            }
        }
    }
}
