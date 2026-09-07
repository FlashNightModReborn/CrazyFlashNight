using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Data
{
    /// <summary>第二阶段人工真源：物理地点、地图表现、人物和驻点分别持有稳定身份。</summary>
    public static class MapDomainDefinition
    {
        private static readonly Regex IdPattern = new Regex(@"\A[a-zA-Z0-9][a-zA-Z0-9_.-]{0,99}\z", RegexOptions.CultureInvariant);
        private static readonly string[] ReservedIds = { "constructor", "prototype", "__proto__", "hasOwnProperty", "toString", "valueOf" };
        private static readonly string[] Tones = { "base", "warlord", "rock", "blackiron", "fallen", "defense", "restricted", "schoolOutside", "schoolInside" };
        public static JObject Always() => new JObject { ["type"] = "always" };
        public static string Id(JObject value, string key)
        {
            string id = MapRuleEvaluator.Text(value, key, 100);
            MapRuleEvaluator.Need(IdPattern.IsMatch(id) && !ReservedIds.Contains(id), "标识含保留名称或非法字符：" + key);
            return id;
        }
        private static JObject Dictionary(JObject d, string key, int limit)
        {
            MapRuleEvaluator.Need(d[key] is JObject values && values.Count <= limit, "地图字典缺失或过大：" + key);
            var result = (JObject)d[key];
            foreach (var p in result.Properties()) MapRuleEvaluator.Need(IdPattern.IsMatch(p.Name) && !ReservedIds.Contains(p.Name) && p.Value is JObject, "地图字典标识或内容不合法：" + key);
            return result;
        }
        public static void Validate(JObject d)
        {
            var rules = Dictionary(d, "rules", 256);
            var locations = Dictionary(d, "locations", 256);
            var npcs = Dictionary(d, "npcs", 256);
            var placements = Dictionary(d, "placements", 512);
            MapRuleEvaluator.Need(d["unlockGroups"] == null && d["pageUnlockGroups"] == null, "第二阶段定义不能保存重复的解锁投影。");
            foreach (var rule in rules.Properties())
            {
                var value = (JObject)rule.Value;
                MapRuleEvaluator.Keys(value, "label", "condition", "tone");
                MapRuleEvaluator.Text(value, "label", 100);
                MapRuleEvaluator.Validate(value["condition"], rules);
            }
            var routeKeys = new HashSet<string>(StringComparer.Ordinal);
            foreach (var p in locations.Properties())
            {
                var loc = (JObject)p.Value;
                MapRuleEvaluator.Keys(loc, "label", "sceneName", "sceneKind", "enabled", "enterWhen", "visibleWhen", "tone", "sceneBinding");
                MapRuleEvaluator.Text(loc, "label", 100);
                string scene = MapRuleEvaluator.Text(loc, "sceneName", 160);
                MapRuleEvaluator.Need(!scene.Contains('"') && !scene.Contains('\\'), "场景绑定不能含协议保留字符。");
                MapRuleEvaluator.Need(routeKeys.Add(scene), "同一真实场景不能注册为两个地点；复制地图表现请复用地点引用：" + scene);
                MapRuleEvaluator.Need(new[] { "base", "outdoor" }.Contains((string)loc["sceneKind"]), "地点场景类型不正确。");
                MapRuleEvaluator.Need(loc["enabled"]?.Type == JTokenType.Boolean, "地点须声明是否启用。");
                MapRuleEvaluator.Validate(loc["enterWhen"], rules);
                MapRuleEvaluator.Validate(loc["visibleWhen"], rules);
                if (loc["sceneBinding"] != null)
                {
                    MapRuleEvaluator.Need(loc["sceneBinding"] is JObject, "场景发布绑定不正确。");
                    var sceneBinding = (JObject)loc["sceneBinding"]; MapRuleEvaluator.Keys(sceneBinding, "sourceSwf", "linkage");
                    SourceSwf(MapRuleEvaluator.Text(sceneBinding, "sourceSwf", 220)); MapRuleEvaluator.Text(sceneBinding, "linkage", 160);
                }
            }
            var names = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            foreach (var p in npcs.Properties())
            {
                var npc = (JObject)p.Value;
                MapRuleEvaluator.Keys(npc, "label", "runtimeNames", "aliases", "placementPolicy");
                MapRuleEvaluator.Text(npc, "label", 100);
                MapRuleEvaluator.Need(new[] { "multiple", "unique" }.Contains((string)npc["placementPolicy"]), "人物驻点策略不正确。");
                foreach (string field in new[] { "runtimeNames", "aliases" })
                {
                    MapRuleEvaluator.Need(npc[field] is JArray list && list.Count <= 16 && (field != "runtimeNames" || list.Count > 0), "人物检索名列表不正确。");
                    foreach (var name in (JArray)npc[field])
                    {
                        MapRuleEvaluator.Need(name.Type == JTokenType.String && ((string)name).Length is > 0 and <= 100 && !((string)name).Any(char.IsControl)
                            && !((string)name).Contains('"') && !((string)name).Contains('\\'), "人物检索名不正确。");
                        string text = (string)name;
                        MapRuleEvaluator.Need(!names.TryGetValue(text, out string owner) || owner == p.Name, "人物检索名或别名重复：" + text);
                        names[text] = p.Name;
                    }
                }
            }
            foreach (var p in placements.Properties())
            {
                var placement = (JObject)p.Value;
                MapRuleEvaluator.Keys(placement, "npcId", "locationId", "label", "enabled", "presenceWhen", "worldBinding", "legacyWorldAdapter");
                if (placement["legacyWorldAdapter"] != null) MapRuleEvaluator.Need(placement["legacyWorldAdapter"].Type == JTokenType.Boolean, "旧驻点导入标记须为布尔值。");
                MapRuleEvaluator.Need(npcs[Id(placement, "npcId")] != null && locations[Id(placement, "locationId")] != null, "驻点的人物或地点不存在。");
                MapRuleEvaluator.Text(placement, "label", 100);
                MapRuleEvaluator.Need(placement["enabled"]?.Type == JTokenType.Boolean, "驻点须声明是否启用。");
                MapRuleEvaluator.Validate(placement["presenceWhen"], rules);
                if (placement["worldBinding"]?.Type != JTokenType.Null)
                {
                    MapRuleEvaluator.Need(placement["worldBinding"] is JObject, "驻点缺少世界绑定状态。");
                    var binding = (JObject)placement["worldBinding"];
                    MapRuleEvaluator.Keys(binding, "occurrenceId", "sourceDigest", "runtime");
                    MapRuleEvaluator.Need(Regex.IsMatch(MapRuleEvaluator.Text(binding, "sourceDigest", 64), @"\A[A-F0-9]{64}\z"), "NPC 来源摘要不正确。");
                    Id(binding, "occurrenceId");
                    if (binding["runtime"] != null)
                    {
                        MapRuleEvaluator.Need(binding["runtime"] is JObject, "NPC 发布绑定不正确。");
                        var runtime = (JObject)binding["runtime"]; MapRuleEvaluator.Keys(runtime, "sourceSwf", "swfSha256", "sceneKey", "runtimeName", "taskName", "instanceName");
                        SourceSwf(MapRuleEvaluator.Text(runtime, "sourceSwf", 220));
                        MapRuleEvaluator.Need(Regex.IsMatch(MapRuleEvaluator.Text(runtime, "swfSha256", 64), @"\A[A-F0-9]{64}\z"), "NPC 发布摘要不正确。");
                        foreach (string field in new[] { "sceneKey", "runtimeName", "taskName" }) MapRuleEvaluator.Text(runtime, field, 160);
                        MapRuleEvaluator.Need(runtime["instanceName"]?.Type == JTokenType.String && ((string)runtime["instanceName"]).Length <= 160 && !((string)runtime["instanceName"]).Any(char.IsControl), "NPC 实例名称不正确。");
                    }
                }
            }
            var avatars = new HashSet<string>(StringComparer.Ordinal);
            int count = 0;
            foreach (var page in MapDefinition.Pages(d))
            {
                MapRuleEvaluator.Need(++count <= 32, "页面过多。");
                Id(page, "id"); MapRuleEvaluator.Text(page, "title", 100); MapRuleEvaluator.Text(page, "tabLabel", 100);
                if (page["tone"] != null) MapRuleEvaluator.Need(Tones.Contains((string)page["tone"]), "页面主题不受支持。");
                if (page["backgroundAssetUrl"]?.Type != JTokenType.Null && page["backgroundAssetUrl"] != null) Asset((string)page["backgroundAssetUrl"]);
                MapRuleEvaluator.Validate(page["visibleWhen"], rules);
                foreach (JObject hotspot in (JArray)page["hotspots"])
                {
                    Id(hotspot, "id"); MapRuleEvaluator.Text(hotspot, "label", 100); MapDefinition.Rect(hotspot["rect"]);
                    MapRuleEvaluator.Need(locations[Id(hotspot, "locationId")] != null, "地图表现引用不存在的地点。");
                    MapRuleEvaluator.Need(locations[(string)hotspot["id"]] == null || (string)hotspot["id"] == (string)hotspot["locationId"], "表现 ID 与另一物理地点身份冲突。");
                    MapRuleEvaluator.Need(hotspot["sceneName"] == null, "地图表现不能保存第二份物理场景绑定。");
                }
                foreach (JObject filter in (JArray)page["filters"])
                {
                    Id(filter, "id"); MapRuleEvaluator.Text(filter, "label", 100); MapDefinition.Rect(filter["buttonRect"]);
                    if (filter["tone"] != null) MapRuleEvaluator.Need(Tones.Contains((string)filter["tone"]), "分层主题不受支持。");
                    if (filter["viewMode"] != null) MapRuleEvaluator.Need(new[] { "default", "hierarchy" }.Contains((string)filter["viewMode"]), "分层视图类型不受支持。");
                }
                foreach (JObject visual in (JArray)page["sceneVisuals"])
                {
                    Id(visual, "id"); MapRuleEvaluator.Text(visual, "label", 100); Asset((string)visual["assetUrl"]); MapDefinition.Rect(visual["rect"]);
                    if (visual["visibleWhen"] != null) MapRuleEvaluator.Validate(visual["visibleWhen"], rules);
                    Variants(visual, rules);
                }
                foreach (JObject slot in ((JArray)page["staticAvatars"]).Concat(page["dynamicAvatars"] as JArray ?? new JArray()))
                {
                    MapRuleEvaluator.Text(slot, "label", 100);
                    foreach (string field in new[] { "relX", "relY", "w", "h" }) MapDefinition.Number(slot[field]);
                    if (slot["assetUrl"] != null) Asset((string)slot["assetUrl"]);
                    string placementId = Id(slot, "placementId");
                    MapRuleEvaluator.Need(placements[placementId] != null && avatars.Add(Id(slot, "id")), "头像驻点不存在或头像 ID 跨页重复。");
                    var hotspot = ((JArray)page["hotspots"]).First(x => (string)x["id"] == (string)slot["hotspotId"]);
                    MapRuleEvaluator.Need((string)hotspot["locationId"] == (string)placements[placementId]["locationId"], "头像的地图表现与人物驻点不在同一地点。");
                    MapRuleEvaluator.Validate(slot["visibleWhen"], rules);
                    Variants(slot, rules);
                }
            }
        }

        public static void Asset(string value) => MapRuleEvaluator.Need(value != null && value.StartsWith("assets/map/", StringComparison.Ordinal) &&
            value.EndsWith(".webp", StringComparison.OrdinalIgnoreCase) && !value.Contains("..") && !value.Any(c => c is ':' or '\\' or '?' or '#' or '%') && !value.Any(char.IsControl), "地图资源须为项目地图目录内的 WebP。");
        public static void SourceSwf(string value) => MapRuleEvaluator.Need(value != null && value.StartsWith("flashswf/", StringComparison.Ordinal) &&
            value.EndsWith(".swf", StringComparison.OrdinalIgnoreCase) && !value.Contains("..") && !value.Contains(':') && !value.Contains('\\') && !value.Any(char.IsControl), "SWF 来源路径不合法。");
        private static void Variants(JObject item, JObject rules)
        {
            if (item["variants"] == null) return;
            MapRuleEvaluator.Need(item["variants"] is JArray list && list.Count <= 16, "表现变体须为最多 16 项的列表。");
            var ids = new HashSet<string>(StringComparer.Ordinal);
            foreach (JObject variant in (JArray)item["variants"])
            {
                MapRuleEvaluator.Keys(variant, "id", "when", "assetUrl"); MapRuleEvaluator.Need(ids.Add(Id(variant, "id")), "表现变体标识重复。");
                Asset((string)variant["assetUrl"]); MapRuleEvaluator.Validate(variant["when"], rules);
            }
        }

        public static string GroupId(string locationId, JObject location)
        {
            if ((string)location["enterWhen"]?["type"] == "always") return "";
            string reference = (string)location["enterWhen"]?["key"];
            return (string)location["enterWhen"]?["type"] == "rule" && reference?.StartsWith("unlock.", StringComparison.Ordinal) == true
                ? reference.Substring(7) : "location_" + locationId;
        }

        /// <summary>只在内存中适配现役 renderer API；绝不把这些派生字段回写定义。</summary>
        public static JObject WebProjection(JObject definition)
        {
            if (definition.Value<int>("version") == 1) return (JObject)definition.DeepClone();
            var d = (JObject)definition.DeepClone();
            var locations = (JObject)d["locations"];
            var groups = new JObject(); var mappings = new JObject();
            var avatarSources = new JObject();
            foreach (string dynamicId in new[] { "roommate_male", "roommate_female" }) if (d["avatarSources"]?[dynamicId] != null) avatarSources[dynamicId] = d["avatarSources"][dynamicId].DeepClone();
            foreach (var p in locations.Properties())
            {
                var loc = (JObject)p.Value; string group = GroupId(p.Name, loc);
                if (group == "") continue;
                string rule = (string)loc["enterWhen"]?["type"] == "rule" ? (string)loc["enterWhen"]["key"] : "";
                groups[group] = new JObject { ["id"] = group, ["conditionId"] = "unlock." + group,
                    ["label"] = d["rules"]?[rule]?["label"] ?? loc["label"], ["lockedReason"] = "请查看当前剧情条件", ["tone"] = loc["tone"] ?? "base" };
            }
            foreach (var page in MapDefinition.Pages(d))
            {
                var hs = new JObject(); var fs = new JObject();
                foreach (JObject hotspot in (JArray)page["hotspots"])
                {
                    string locId = (string)hotspot["locationId"]; var loc = (JObject)locations[locId];
                    hotspot["sceneName"] = loc["sceneName"].DeepClone();
                    hs[(string)hotspot["id"]] = GroupId(locId, loc);
                }
                foreach (JObject filter in (JArray)page["filters"])
                {
                    var used = ((JArray)filter["hotspotIds"]).Select(id => (string)hs[(string)id]).Distinct().ToArray();
                    if (used.Length == 1) fs[(string)filter["id"]] = used[0];
                }
                mappings[(string)page["id"]] = new JObject { ["hotspots"] = hs, ["filters"] = fs };
                foreach (JObject slot in (JArray)page["staticAvatars"])
                {
                    string id = (string)slot["id"];
                    var old = (d["avatarSources"] as JObject)?.Properties().LastOrDefault(p => (string)p.Value["assetUrl"] == (string)slot["assetUrl"])?.Value as JObject;
                    var entry = old != null && (string)old["assetUrl"] == (string)slot["assetUrl"] ? (JObject)old.DeepClone() : new JObject { ["symbolName"] = slot["label"] ?? slot["id"] };
                    entry["assetUrl"] = slot["assetUrl"]; entry["hotspotId"] = slot["hotspotId"]; entry["relX"] = slot["relX"]; entry["relY"] = slot["relY"];
                    entry["size"] = new JObject { ["w"] = slot["w"], ["h"] = slot["h"] };
                    var asset = d["assets"]?[(string)slot["assetUrl"]] as JObject;
                    if (asset != null) entry["assetSize"] = new JObject { ["w"] = asset["width"], ["h"] = asset["height"] };
                    avatarSources[System.IO.Path.GetFileNameWithoutExtension((string)slot["assetUrl"])] = entry;
                }
            }
            d["unlockGroups"] = groups; d["pageUnlockGroups"] = mappings; d["avatarSources"] = avatarSources;
            d["assetCapabilities"] = AssetCapabilities(definition);
            return d;
        }
        private static JObject AssetCapabilities(JObject definition)
        {
            var result = new JObject();
            foreach (var page in MapDefinition.Pages(definition))
            {
                var pageCaps = new JObject(); result[(string)page["id"]] = pageCaps;
                foreach (string filterId in ((JArray)page["filters"]).Select(f => (string)f["id"]).Concat(new[] { "*" }))
                {
                    double ratio = double.PositiveInfinity; string worst = ""; bool missing = false;
                    void Sample(string url, double width, double height)
                    {
                        var asset = definition["assets"]?[url] as JObject;
                        if (asset == null) { missing = true; return; }
                        double candidate = Math.Min((double)asset["width"] / width, (double)asset["height"] / height);
                        if (candidate < ratio) { ratio = candidate; worst = url; }
                    }
                    foreach (JObject visual in (JArray)page["sceneVisuals"])
                    {
                        var filters = visual["filterIds"] as JArray;
                        if (filterId != "*" && filterId != "all" && filters?.Count > 0 && !filters.Any(f => (string)f == filterId)) continue;
                        Sample((string)visual["assetUrl"], (double)visual["rect"]["w"], (double)visual["rect"]["h"]);
                        foreach (var variant in visual["variants"] as JArray ?? new JArray()) Sample((string)variant["assetUrl"], (double)visual["rect"]["w"], (double)visual["rect"]["h"]);
                    }
                    if (page["backgroundAssetUrl"]?.Type == JTokenType.String) Sample((string)page["backgroundAssetUrl"], (double)page["width"], (double)page["height"]);
                    pageCaps[filterId] = new JObject { ["sourceRatio"] = missing || !double.IsFinite(ratio) ? 1 : Math.Round(ratio, 3), ["worstAsset"] = worst, ["verified"] = !missing && double.IsFinite(ratio) };
                }
            }
            return result;
        }
    }
}
