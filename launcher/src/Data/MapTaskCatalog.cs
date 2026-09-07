using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Data
{
    /// <summary>读取既有任务制作源。这里只维护地图端点，任务玩法字段从不成为地图工作台的写入面。</summary>
    public sealed class MapTaskCatalog
    {
        public readonly JObject Tasks = new JObject(), Texts = new JObject();
        public readonly Dictionary<string, byte[]> SourceBytes = new Dictionary<string, byte[]>(StringComparer.Ordinal);
        public readonly Dictionary<string, string> TaskFiles = new Dictionary<string, string>(StringComparer.Ordinal);
        public readonly SortedSet<string> Chains = new SortedSet<string>(StringComparer.Ordinal);
        public readonly JObject Infrastructure = new JObject();
        public string Digest => MapDefinition.Hash(MapDefinition.Utf8.GetBytes(string.Join("\n", SourceBytes.OrderBy(p => p.Key, StringComparer.Ordinal).Select(p => p.Key + " " + MapDefinition.Hash(p.Value)))));

        public static MapTaskCatalog Load(string root, IReadOnlyDictionary<string, byte[]> overrides = null)
        {
            var catalog = new MapTaskCatalog();
            const string infrastructureFile = "data/infrastructure/infrastructure.xml";
            byte[] infrastructureBytes = MapProjectFiles.Read(root, infrastructureFile); catalog.SourceBytes[infrastructureFile] = infrastructureBytes;
            foreach (var project in MapProjectFiles.Xml(infrastructureBytes).Root.Elements("Infrastructure"))
            {
                string name = project.Element("Name")?.Value ?? ""; int maximum = project.Elements("Level").Count() - 1;
                MapRuleEvaluator.Need(name.Length is > 0 and <= 100 && !name.Any(char.IsControl) && catalog.Infrastructure[name] == null && maximum >= 0 && maximum <= 100, "基建事实目录重复或不正确。");
                catalog.Infrastructure[name] = new JObject { ["label"] = name, ["maximumLevel"] = maximum };
            }
            MapRuleEvaluator.Need(catalog.Infrastructure.Count is > 0 and <= 128, "基建事实目录为空或过大。");
            foreach (bool text in new[] { false, true })
            {
                string folder = text ? "data/task/text/" : "data/task/", tag = text ? "text" : "task";
                byte[] listBytes = MapProjectFiles.Read(root, folder + "list.xml"); catalog.SourceBytes[folder + "list.xml"] = listBytes;
                var entries = MapProjectFiles.Xml(listBytes).Root.Elements(tag).ToArray();
                MapRuleEvaluator.Need(entries.Length is > 0 and <= 128, "任务源目录为空或过大。");
                foreach (var entry in entries)
                {
                    string name = entry.Value.Trim();
                    MapRuleEvaluator.Need(Regex.IsMatch(name, @"\A[\p{L}\p{N}_. -]+\.json\z") && !name.Contains(".."), "任务目录包含非法文件名。");
                    string file = folder + name;
                    MapRuleEvaluator.Need(!catalog.SourceBytes.ContainsKey(file), "任务目录重复引用源文件。");
                    byte[] bytes = overrides != null && overrides.TryGetValue(file, out byte[] replacement) ? replacement : MapProjectFiles.Read(root, file); catalog.SourceBytes[file] = bytes;
                    var document = MapProjectFiles.Json(bytes);
                    if (text)
                    {
                        foreach (var p in document.Properties()) catalog.Texts[p.Name] = p.Value.DeepClone();
                        continue;
                    }
                    MapRuleEvaluator.Need(document["tasks"] is JArray taskList && taskList.Count <= 4096, "任务源列表缺失或过大。");
                    foreach (JObject task in (JArray)document["tasks"])
                    {
                        string id = MapRuleEvaluator.Integer(task["id"], "任务 ID").ToString(System.Globalization.CultureInfo.InvariantCulture);
                        MapRuleEvaluator.Need(catalog.Tasks[id] == null, "任务源 ID 重复：" + id);
                        catalog.Tasks[id] = task.DeepClone(); catalog.TaskFiles[id] = file;
                        string chain = (task.Value<string>("chain") ?? "").Split('#')[0];
                        if (chain != "") catalog.Chains.Add(chain);
                    }
                }
            }
            return catalog;
        }
        public string Title(JObject task)
        {
            string value = task.Value<string>("title") ?? "";
            return value.StartsWith('$') && Texts[value]?.Type == JTokenType.String ? (string)Texts[value] : value;
        }
        public JArray Summary()
        {
            return new JArray(Tasks.Properties().Select(p => new JObject { ["id"] = p.Name, ["title"] = Title((JObject)p.Value),
                ["chain"] = p.Value["chain"], ["sourceFile"] = TaskFiles[p.Name], ["sourceDigest"] = MapDefinition.Hash(SourceBytes[TaskFiles[p.Name]]),
                ["get_endpoint"] = p.Value["get_endpoint"]?.DeepClone(), ["finish_endpoint"] = p.Value["finish_endpoint"]?.DeepClone(),
                ["get_npc"] = p.Value["get_npc"], ["get_npc_hotspot"] = p.Value["get_npc_hotspot"],
                ["finish_npc"] = p.Value["finish_npc"], ["finish_npc_hotspot"] = p.Value["finish_npc_hotspot"],
                ["prerequisites"] = p.Value["get_requirements"]?.DeepClone() ?? new JArray(),
                ["rewards"] = p.Value["rewards"]?.DeepClone() ?? new JArray(), ["hasDialogue"] = p.Value["get_conversation"] != null || p.Value["finish_conversation"] != null }));
        }
        public void ValidateBindings(JObject definition)
        {
            foreach (var property in Tasks.Properties()) foreach (string role in new[] { "get", "finish" })
            {
                var task = (JObject)property.Value;
                if (task[role + "_endpoint"] == null || task[role + "_endpoint"].Type == JTokenType.Null) continue;
                MapRuleEvaluator.Need(task[role + "_endpoint"] is JObject, "任务端点必须是结构化对象：" + property.Name);
                MapRuleEvaluator.Need(task[role + "_npc"] == null && task[role + "_npc_hotspot"] == null, "任务端点不能同时维护新旧两套真源：" + property.Name);
                MapEndpointResolver.Validate(definition, (JObject)task[role + "_endpoint"]);
            }
            ValidateFacts(definition);
        }
        public JObject NpcLabels(JObject definition)
        {
            var result = new JObject();
            foreach (var task in Tasks.Properties())
            {
                var labels = new JObject(); result[task.Name] = labels;
                foreach (string role in new[] { "get", "finish" })
                {
                    string legacy = task.Value.Value<string>(role + "_npc") ?? "";
                    string npc = (task.Value[role + "_endpoint"] as JObject)?.Value<string>("npcId") ?? MapEndpointResolver.FindNpc(definition, legacy);
                    labels[role] = definition["npcs"][npc]?.Value<string>("label") ?? legacy;
                    // 显示名可自由编辑；旧对白头像检索仍使用稳定的现场检索名，不把显示名当素材身份。
                    labels[role + "RuntimeName"] = task.Value[role + "_endpoint"] is JObject
                        ? definition["npcs"][npc]?["runtimeNames"]?.First?.Value<string>() ?? "" : legacy;
                }
            }
            return result;
        }
        public void ValidateFacts(JObject definition)
        {
            var required = MapRuleEvaluator.RequiredFacts(definition);
            foreach (var id in (JArray)required["tasks"]) MapRuleEvaluator.Need(Tasks[(string)id] != null, "地图条件引用未知任务：" + id);
            foreach (var chain in (JArray)required["chains"]) MapRuleEvaluator.Need(Chains.Contains((string)chain), "地图条件引用未知任务链：" + chain);
            foreach (var key in (JArray)required["infrastructure"])
                MapRuleEvaluator.Need(Infrastructure[(string)key] != null, "地图尚未接入该基建事实：" + key);
            foreach (var key in (JArray)required["flags"])
                throw new InvalidDataException("地图尚未接入该世界事实：" + key);
        }
    }
}
