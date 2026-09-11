using System;
using System.Collections.Generic;
using System.Linq;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Data
{
    /// <summary>进程内固定地图内容；Web、HUD 和规则域共享同一份，作者保存后重启才切换。</summary>
    public sealed class MapRuntimeContent
    {
        public JObject Definition { get; }
        public MapTaskCatalog Catalog { get; }
        public JObject WorldOccurrences { get; }
        public string DefinitionDigest { get; }
        public string ContentDigest { get; }
        public JObject Bootstrap { get; }
        private readonly HashSet<string> taskIds;
        private readonly HashSet<string> structuredIds;
        public MapRuntimeContent(string root)
        {
            MapAuthoringStore.RecoverForStartup(root);
            byte[] bytes = MapProjectFiles.Read(root, MapDefinition.RelativePath);
            Definition = MapDefinition.Parse(bytes);
            MapRuleEvaluator.Need(Definition.Value<int>("version") == 2, "地图内容尚未完成第二阶段迁移。");
            MapAssetCandidates.ValidatePublished(root, Definition);
            Catalog = MapTaskCatalog.Load(root); Catalog.ValidateBindings(Definition);
            var world = new MapRuntimeWorld(root, Definition); WorldOccurrences = world.Occurrences;
            DefinitionDigest = MapDefinition.Hash(bytes);
            ContentDigest = MapDefinition.Hash(MapDefinition.Utf8.GetBytes(DefinitionDigest + "\n" + Catalog.Digest + "\n" + string.Join("\n", world.SourceHashes.OrderBy(p => p.Key, StringComparer.Ordinal).Select(p => p.Key + " " + p.Value))));
            taskIds = new HashSet<string>(Catalog.Tasks.Properties().Select(p => p.Name), StringComparer.Ordinal);
            structuredIds = new HashSet<string>(Catalog.Tasks.Properties().Where(p => p.Value["get_endpoint"] is JObject || p.Value["finish_endpoint"] is JObject).Select(p => p.Name), StringComparer.Ordinal);
            Bootstrap = BuildBootstrap();
        }
        internal MapRuntimeContent(JObject definition, MapTaskCatalog catalog, JObject world)
        {
            MapDefinition.Validate(definition); Definition = (JObject)definition.DeepClone(); Catalog = catalog; WorldOccurrences = (JObject)world.DeepClone();
            DefinitionDigest = MapDefinition.Hash(MapDefinition.Bytes(definition)); ContentDigest = MapDefinition.Hash(MapDefinition.Utf8.GetBytes(DefinitionDigest + catalog.Digest));
            taskIds = new HashSet<string>(catalog.Tasks.Properties().Select(p => p.Name), StringComparer.Ordinal);
            structuredIds = new HashSet<string>(catalog.Tasks.Properties().Where(p => p.Value["get_endpoint"] is JObject || p.Value["finish_endpoint"] is JObject).Select(p => p.Name), StringComparer.Ordinal);
            Bootstrap = BuildBootstrap();
        }
        private JObject BuildBootstrap()
        {
            var locationByHotspot = new JObject(); var pageByHotspot = new JObject(); var locationByFrame = new JObject(); var frames = new JObject();
            var locationLabels = new JObject();
            foreach (var page in MapDefinition.Pages(Definition)) foreach (var h in (JArray)page["hotspots"])
            {
                locationByHotspot[(string)h["id"]] = h["locationId"]; pageByHotspot[(string)h["id"]] = page["id"];
                if (pageByHotspot[(string)h["locationId"]] == null) pageByHotspot[(string)h["locationId"]] = page["id"];
            }
            foreach (var p in ((JObject)Definition["locations"]).Properties())
            {
                locationByHotspot[p.Name] = p.Name; locationByFrame[(string)p.Value["sceneName"]] = p.Name; frames[p.Name] = p.Value["sceneName"];
                locationLabels[p.Name] = p.Value["label"];
            }
            var available = Definition.DescendantsAndSelf().OfType<JObject>().Where(n => (string)n["type"] == "task" && (string)n["state"] == "available")
                .Select(n => (string)n["key"]).Distinct(StringComparer.Ordinal).OrderBy(x => x, StringComparer.Ordinal);
            return new JObject { ["version"] = 2, ["definitionDigest"] = DefinitionDigest, ["contentDigest"] = ContentDigest,
                ["taskIds"] = new JArray(taskIds.OrderBy(x => x, StringComparer.Ordinal)), ["chains"] = new JArray(Catalog.Chains),
                ["infrastructureKeys"] = new JArray(Catalog.Infrastructure.Properties().Select(p => p.Name)),
                ["taskNpcLabels"] = Catalog.NpcLabels(Definition),
                ["availableTaskIds"] = new JArray(available), ["structuredTaskIds"] = new JArray(structuredIds.OrderBy(x => x, StringComparer.Ordinal)),
                ["locationByHotspot"] = locationByHotspot, ["pageByHotspot"] = pageByHotspot, ["locationByFrame"] = locationByFrame, ["frames"] = frames,
                ["locationLabels"] = locationLabels,
                ["worldBindings"] = new JArray(WorldOccurrences.Properties().Select(p => p.Value.DeepClone())) };
        }
        public JArray ValidateTaskIds(JToken token, int maximum = 128)
        {
            MapRuleEvaluator.Need(token is JArray ids && ids.Count <= maximum, "任务采样列表不正确。");
            var seen = new HashSet<string>(StringComparer.Ordinal);
            foreach (var id in (JArray)token) MapRuleEvaluator.Need(id.Type == JTokenType.String && taskIds.Contains((string)id) && seen.Add((string)id), "任务采样标识重复或不存在。");
            return (JArray)token.DeepClone();
        }
        public JObject NormalizeFacts(JObject raw)
        {
            MapRuleEvaluator.Need(raw != null && raw.ToString(Newtonsoft.Json.Formatting.None).Length <= 256 * 1024, "地图事实缺失或过大。");
            MapRuleEvaluator.Keys(raw, "chains", "infrastructure", "flags", "finished", "activeOrder", "deliverableIds", "available", "scene", "navigation", "dynamic");
            foreach (string key in new[] { "chains", "infrastructure", "flags", "finished", "available", "scene", "navigation", "dynamic" }) MapRuleEvaluator.Need(raw[key] is JObject, "地图事实字段缺失：" + key);
            var chains = (JObject)raw["chains"]; MapRuleEvaluator.Need(chains.Count <= 64, "任务链事实过多。");
            foreach (var p in chains.Properties()) { MapRuleEvaluator.Need(Catalog.Chains.Contains(p.Name), "未知任务链事实。"); MapRuleEvaluator.Integer(p.Value, "任务链进度"); }
            var infra = (JObject)raw["infrastructure"]; MapRuleEvaluator.Keys(infra, Catalog.Infrastructure.Properties().Select(p => p.Name).ToArray());
            foreach (var p in infra.Properties()) if (p.Value.Type != JTokenType.Boolean) MapRuleEvaluator.Integer(p.Value, "基建等级");
            var flags = (JObject)raw["flags"]; MapRuleEvaluator.Keys(flags);
            var finished = (JObject)raw["finished"]; MapRuleEvaluator.Need(finished.Count <= taskIds.Count, "任务历史事实过多。");
            foreach (var p in finished.Properties()) { MapRuleEvaluator.Need(taskIds.Contains(p.Name), "未知任务历史标识。"); MapRuleEvaluator.Integer(p.Value, "任务完成次数"); }
            var active = ValidateTaskIds(raw["activeOrder"], 512); var deliverable = ValidateTaskIds(raw["deliverableIds"], 512);
            var activeSet = new HashSet<string>(active.Select(x => (string)x), StringComparer.Ordinal);
            var doneSet = new HashSet<string>(deliverable.Select(x => (string)x), StringComparer.Ordinal);
            MapRuleEvaluator.Need(doneSet.IsSubsetOf(activeSet), "可交付任务必须属于当前进行中任务。");
            var available = (JObject)raw["available"]; MapRuleEvaluator.Need(available.Count <= 256, "任务接取采样过多。");
            foreach (var p in available.Properties()) MapRuleEvaluator.Need(taskIds.Contains(p.Name) && p.Value.Type == JTokenType.Boolean, "任务接取事实不正确。");
            var scene = (JObject)raw["scene"]; MapRuleEvaluator.Keys(scene, "stageFlag", "frameLabel", "entrance", "mapFrame", "inCombat");
            foreach (string key in new[] { "stageFlag", "frameLabel", "entrance", "mapFrame" })
                MapRuleEvaluator.Need(scene[key]?.Type == JTokenType.String && ((string)scene[key]).Length <= 200 && !((string)scene[key]).Any(char.IsControl), "当前场景事实不正确。");
            MapRuleEvaluator.Need(scene["inCombat"]?.Type == JTokenType.Boolean, "战斗场景事实不正确。");
            var navigation = (JObject)raw["navigation"]; MapRuleEvaluator.Keys(navigation, "reason");
            MapRuleEvaluator.Need(navigation["reason"]?.Type == JTokenType.String && ((string)navigation["reason"]).Length <= 128 && !((string)navigation["reason"]).Any(char.IsControl), "导航生命周期事实不正确。");
            var dynamic = (JObject)raw["dynamic"]; MapRuleEvaluator.Keys(dynamic, "roommateGender");
            MapRuleEvaluator.Need(dynamic["roommateGender"]?.Type == JTokenType.String && new[] { "", "男", "女", "male", "female" }.Contains((string)dynamic["roommateGender"]), "动态头像事实不正确。");
            var tasks = new JObject();
            foreach (string id in taskIds)
            {
                var fact = new JObject { ["finished"] = finished[id]?.DeepClone() ?? new JValue(0), ["active"] = activeSet.Contains(id), ["deliverable"] = doneSet.Contains(id) };
                if (available[id] != null) fact["available"] = available[id].DeepClone(); tasks[id] = fact;
            }
            return new JObject { ["chains"] = chains.DeepClone(), ["infrastructure"] = infra.DeepClone(), ["flags"] = flags.DeepClone(), ["tasks"] = tasks,
                ["activeOrder"] = active, ["scene"] = scene.DeepClone(), ["navigation"] = navigation.DeepClone(), ["dynamic"] = dynamic.DeepClone() };
        }
        public JObject Project(JObject facts) => MapDomainService.Project(Definition, facts, Catalog.Tasks, WorldOccurrences);
        public JObject ForAs2(JObject projection, JObject facts, JArray interests)
        {
            var ids = new HashSet<string>(structuredIds, StringComparer.Ordinal);
            foreach (var id in (JArray)facts["activeOrder"]) ids.Add((string)id);
            foreach (var id in interests) ids.Add((string)id);
            var endpoints = new JObject();
            foreach (string id in ids) if (projection["taskEndpoints"][id] != null) endpoints[id] = projection["taskEndpoints"][id].DeepClone();
            var locations = new JObject(); var placements = new JObject(); var snapshot = (JObject)projection["snapshot"].DeepClone();
            foreach (var p in ((JObject)projection["locations"]).Properties()) locations[p.Name] = new JObject { ["visible"] = p.Value["visible"], ["enterable"] = p.Value["enterable"] };
            foreach (var p in ((JObject)projection["placements"]).Properties()) placements[p.Name] = new JObject { ["present"] = p.Value["present"], ["worldReady"] = p.Value["worldReady"], ["npcId"] = p.Value["npcId"], ["locationId"] = p.Value["locationId"] };
            foreach (var p in ((JObject)snapshot["hotspotStates"]).Properties()) ((JObject)p.Value).Remove("reason");
            foreach (var p in ((JObject)snapshot["pageStates"]).Properties()) ((JObject)p.Value).Remove("reason");
            return new JObject { ["snapshot"] = snapshot, ["locations"] = locations,
                ["placements"] = placements, ["taskEndpoints"] = endpoints, ["delivery"] = projection["delivery"].DeepClone(),
                ["npcTasks"] = projection["npcTasks"].DeepClone(), ["autoAccept"] = projection["autoAccept"].DeepClone(), ["hasDeliverable"] = projection["hasDeliverable"],
                ["currentLocationId"] = projection["currentLocationId"], ["hudMode"] = projection["hudMode"] };
        }
    }
}
