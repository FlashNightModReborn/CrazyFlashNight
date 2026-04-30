// 同源 dict 消费端：直接读 launcher/data/save_repair_dict.json。
// 与 tools/cf7-save-repair 共用同一份 JSON（由 tools/cf7-save-repair-dict-build 生成）。

using System;
using System.IO;
using System.Text;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Save
{
    public class RepairDictionary
    {
        public readonly string[] Items;
        public readonly string[] Mods;
        public readonly string[] Enemies;
        public readonly string[] Hairstyles;
        public readonly string[] Skills;
        public readonly string[] TaskChains;
        public readonly string[] Stages;
        public readonly int SchemaVersion;

        private static readonly string[] Empty = new string[0];

        /// <summary>
        /// inventory.装备栏 下的固定 11 个槽位 key. AS2 强约定 (DressupInitializer.equipmentKeys),
        /// 不会随 dict-build 工具变动, 直接硬编码. 顺序无业务意义.
        /// </summary>
        public static readonly string[] EquipmentSlots = new string[]
        {
            "头部装备", "上装装备", "手部装备", "下装装备", "脚部装备", "颈部装备",
            "长枪", "手枪", "手枪2", "刀", "手雷"
        };

        public RepairDictionary(JObject obj)
        {
            SchemaVersion = obj.Value<int?>("schemaVersion") ?? 0;
            Items = ToArray(obj["items"]);
            Mods = ToArray(obj["mods"]);
            Enemies = ToArray(obj["enemies"]);
            Hairstyles = ToArray(obj["hairstyles"]);
            Skills = ToArray(obj["skills"]);
            TaskChains = ToArray(obj["taskChains"]);
            Stages = ToArray(obj["stages"]);
        }

        public static RepairDictionary LoadFromFile(string path)
        {
            string content = File.ReadAllText(path, Encoding.UTF8);
            JObject obj = JObject.Parse(content);
            return new RepairDictionary(obj);
        }

        public static RepairDictionary LoadFromProjectRoot(string projectRoot)
        {
            string p = Path.Combine(Path.Combine(projectRoot, "launcher"), Path.Combine("data", "save_repair_dict.json"));
            return LoadFromFile(p);
        }

        public string[] GetBucket(SaveFieldKind kind)
        {
            switch (kind)
            {
                case SaveFieldKind.Item:          return Items;
                case SaveFieldKind.Mod:           return Mods;
                case SaveFieldKind.Enemy:         return Enemies;
                case SaveFieldKind.Skill:         return Skills;
                case SaveFieldKind.Hairstyle:     return Hairstyles;
                case SaveFieldKind.Stage:         return Stages;
                case SaveFieldKind.TaskChain:     return TaskChains;
                // QuestId 暂未独立桶；plan 中回退到 stages（与 TS 端一致）
                case SaveFieldKind.QuestId:       return Stages;
                // 装备槽位 key: 硬编码字典, 不依赖 save_repair_dict.json
                case SaveFieldKind.EquipmentSlot: return EquipmentSlots;
                default:                          return Empty;
            }
        }

        private static string[] ToArray(JToken token)
        {
            if (token == null || token.Type != JTokenType.Array) return Empty;
            JArray a = (JArray)token;
            string[] arr = new string[a.Count];
            for (int i = 0; i < a.Count; i++)
            {
                JToken t = a[i];
                arr[i] = t == null || t.Type == JTokenType.Null ? "" : t.ToString();
            }
            return arr;
        }
    }
}
