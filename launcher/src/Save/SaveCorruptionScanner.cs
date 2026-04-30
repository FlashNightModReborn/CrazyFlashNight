// 扫描 save snapshot，定位所有含 U+FFFD 的字符串字段（含 object key）。
// 与 tools/cf7-save-repair/src/scan.ts 同源逻辑。

using System;
using System.Collections.Generic;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Save
{
    public enum SaveCorruptionSpot
    {
        Value,
        Key,
    }

    public class SaveCorruptionItem
    {
        public readonly string[] PathSegments;
        /// <summary>"a.b.c" 形式</summary>
        public readonly string PathStr;
        public readonly SaveFieldRule Rule;
        public readonly SaveCorruptionSpot Spot;
        public readonly string BrokenString;
        /// <summary>父 token：JArray 或 JObject。修复时通过 ParentKey 操作。</summary>
        public readonly JToken Parent;
        /// <summary>父中的索引或 key（PathSegments 的最后一段）。</summary>
        public readonly object ParentKey;

        public SaveCorruptionItem(string[] path, SaveFieldRule rule, SaveCorruptionSpot spot, string broken, JToken parent, object parentKey)
        {
            PathSegments = path;
            PathStr = string.Join(".", path);
            Rule = rule;
            Spot = spot;
            BrokenString = broken;
            Parent = parent;
            ParentKey = parentKey;
        }
    }

    public class SaveCorruptionReport
    {
        public readonly List<SaveCorruptionItem> Items;
        public int Total { get { return Items.Count; } }
        public readonly int L0, L1, L2, L3;

        public SaveCorruptionReport(List<SaveCorruptionItem> items)
        {
            Items = items;
            for (int i = 0; i < items.Count; i++)
            {
                switch (items[i].Rule.Layer)
                {
                    case SaveFieldLayer.L0: L0++; break;
                    case SaveFieldLayer.L1: L1++; break;
                    case SaveFieldLayer.L2: L2++; break;
                    case SaveFieldLayer.L3: L3++; break;
                }
            }
        }
    }

    public static class SaveCorruptionScanner
    {
        public const char FFFD = '�';

        public static SaveCorruptionReport Scan(JObject snapshot)
        {
            List<SaveCorruptionItem> items = new List<SaveCorruptionItem>();
            Walk(snapshot, new List<string>(), snapshot, null, items);
            return new SaveCorruptionReport(items);
        }

        private static void Walk(JToken node, List<string> path, JToken parent, object parentKey, List<SaveCorruptionItem> items)
        {
            if (node == null) return;

            if (node.Type == JTokenType.String)
            {
                string s = node.Value<string>();
                if (s != null && s.IndexOf(FFFD) >= 0)
                {
                    string[] segs = path.ToArray();
                    SaveFieldRule rule = SaveFieldLayering.Classify(segs);
                    items.Add(new SaveCorruptionItem(segs, rule, SaveCorruptionSpot.Value, s, parent, parentKey));
                }
                return;
            }

            if (node.Type == JTokenType.Array)
            {
                JArray arr = (JArray)node;
                for (int i = 0; i < arr.Count; i++)
                {
                    path.Add(i.ToString(System.Globalization.CultureInfo.InvariantCulture));
                    Walk(arr[i], path, arr, i, items);
                    path.RemoveAt(path.Count - 1);
                }
                return;
            }

            if (node.Type == JTokenType.Object)
            {
                JObject obj = (JObject)node;
                // Iterate over a snapshot of keys to allow downstream mutation safety.
                List<string> keys = new List<string>();
                foreach (JProperty p in obj.Properties()) keys.Add(p.Name);

                for (int i = 0; i < keys.Count; i++)
                {
                    string key = keys[i];
                    if (key.IndexOf(FFFD) >= 0)
                    {
                        path.Add(key);
                        SaveFieldRule rule = SaveFieldLayering.Classify(path.ToArray());
                        items.Add(new SaveCorruptionItem(path.ToArray(), rule, SaveCorruptionSpot.Key, key, obj, key));
                        path.RemoveAt(path.Count - 1);
                    }
                    path.Add(key);
                    Walk(obj[key], path, obj, key, items);
                    path.RemoveAt(path.Count - 1);
                }
                return;
            }
        }
    }
}
