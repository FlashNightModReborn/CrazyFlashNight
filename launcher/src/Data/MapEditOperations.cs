using System;
using System.Linq;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Data
{
    /// <summary>封闭的内容制作操作；身份只由创建产生，编辑显示文字不会改人物或地点身份。</summary>
    public static class MapEditOperations
    {
        private static readonly string[] Kinds = { "page", "hotspot", "scene", "filter", "avatar", "location", "npc", "placement", "rule" };
        private static string ChildId(string kind, string parent, string old) => kind + "_" + MapDefinition.Hash(MapDefinition.Utf8.GetBytes(parent + "/" + old)).Substring(0, 20).ToLowerInvariant();
        public static JObject Edit(JObject definition, JArray changes)
        {
            MapRuleEvaluator.Need(changes != null && changes.Count <= 256, "内容操作过多。");
            var d = (JObject)definition.DeepClone();
            foreach (JObject change in changes)
            {
                MapRuleEvaluator.Keys(change, "kind", "pageId", "id", "values", "action");
                string kind = MapRuleEvaluator.Text(change, "kind", 24), id = MapDomainDefinition.Id(change, "id");
                MapRuleEvaluator.Need(Kinds.Contains(kind), "不支持的内容对象：" + kind);
                string action = change.Value<string>("action") ?? "edit";
                MapRuleEvaluator.Need(new[] { "edit", "create", "copy", "delete", "reorder" }.Contains(action), "不支持的内容操作。");
                var values = change["values"] as JObject;
                MapRuleEvaluator.Need(values != null, "内容操作缺少字段。");
                string dictionary = kind == "location" ? "locations" : kind == "npc" ? "npcs" : kind == "placement" ? "placements" : kind == "rule" ? "rules" : kind == "page" ? "pages" : "";
                var page = d["pages"]?[change.Value<string>("pageId") ?? ""] as JObject;
                string collection = kind == "hotspot" ? "hotspots" : kind == "scene" ? "sceneVisuals" : kind == "filter" ? "filters" : "staticAvatars";
                if (dictionary == "") MapRuleEvaluator.Need(page != null, "页面不存在。");
                var list = dictionary == "" ? (JArray)page[collection] : null;
                var item = dictionary != "" ? d[dictionary][id] as JObject : list.OfType<JObject>().FirstOrDefault(x => (string)x["id"] == id);
                if (item == null && kind == "avatar") item = (page["dynamicAvatars"] as JArray)?.OfType<JObject>().FirstOrDefault(x => (string)x["id"] == id);
                if (action == "create")
                {
                    MapRuleEvaluator.Need(item == null, "内容标识已存在。");
                    item = Create(kind, id, values, d);
                    if (dictionary != "") d[dictionary][id] = item; else list.Add(item);
                    if (kind == "page") ((JArray)d["pageOrder"]).Add(id);
                }
                else
                {
                    MapRuleEvaluator.Need(item != null, "内容对象不存在。");
                    if (action == "reorder")
                    {
                        MapRuleEvaluator.Keys(values, "index"); int nextIndex = checked((int)MapRuleEvaluator.Integer(values["index"], "目标排序"));
                        MapRuleEvaluator.Need(kind == "page" || dictionary == "", "该身份对象不支持重排。");
                        JArray target = kind == "page" ? (JArray)d["pageOrder"] : (JArray)item.Parent;
                        MapRuleEvaluator.Need(nextIndex < target.Count, "排序位置超出范围。");
                        if (kind == "filter")
                        {
                            var ordered = target.OrderBy(f => (double)f["buttonRect"]["y"]).ToArray();
                            target.RemoveAll(); foreach (var entry in ordered) target.Add(entry);
                        }
                        var positions = kind == "filter" ? target.Select(f => (double)f["buttonRect"]["y"]).OrderBy(y => y).ToArray() : null;
                        JToken token = kind == "page" ? target.First(x => (string)x == id) : item;
                        token.Remove(); target.Insert(nextIndex, token);
                        if (positions != null) for (int i = 0; i < target.Count; i++) target[i]["buttonRect"]["y"] = positions[i];
                    }
                    else if (action == "delete")
                    {
                        MapRuleEvaluator.Need(values.Count == 0, "删除不能携带额外字段。");
                        if (dictionary != "") ((JObject)d[dictionary]).Property(id).Remove(); else item.Remove();
                        if (kind == "page")
                        {
                            foreach (var token in ((JArray)d["pageOrder"]).Where(x => (string)x == id).ToArray()) token.Remove();
                            if (d["pageAliases"] is JObject aliases) foreach (var p in aliases.Properties().Where(p => (string)p.Value == id).ToArray()) p.Remove();
                        }
                    }
                    else if (action == "copy")
                    {
                        MapRuleEvaluator.Keys(values, "newId", "title");
                        string nextId = MapDomainDefinition.Id(values, "newId");
                        if (kind == "page") CopyPage(d, item, nextId, values.Value<string>("title"));
                        else
                        {
                            MapRuleEvaluator.Need(kind == "scene", "只有地图页和图块支持直接复制；人物请显式创建身份/驻点。");
                            MapRuleEvaluator.Need(!list.Any(x => (string)x["id"] == nextId), "复制目标标识已存在。");
                            var copy = (JObject)item.DeepClone(); copy["id"] = nextId; copy["label"] = values.Value<string>("title") ?? (string)item["label"] + "副本"; list.Add(copy);
                        }
                    }
                    else
                    {
                        bool identityChanged = values.Properties().Any(p => p.Name != "label" && !JToken.DeepEquals(item[p.Name], p.Value));
                        Patch(kind, item, values);
                        // 迁移保留的旧世界适配不能被编辑继承成“新驻点已接入”的假证明。
                        if (kind == "placement" && identityChanged) item.Remove("legacyWorldAdapter");
                        if (kind == "npc" && identityChanged)
                            foreach (JObject placement in ((JObject)d["placements"]).Properties().Where(p => (string)p.Value["npcId"] == id).Select(p => p.Value)) placement.Remove("legacyWorldAdapter");
                    }
                }
            }
            foreach (var page in MapDefinition.Pages(d)) RefreshBounds(d, page);
            MapDefinition.Validate(d); return d;
        }
        private static JObject Create(string kind, string id, JObject values, JObject d)
        {
            JObject item;
            switch (kind)
            {
                case "page": item = new JObject { ["id"] = id, ["title"] = "新地图", ["tabLabel"] = "新地图", ["width"] = 1024, ["height"] = 576,
                    ["renderMode"] = "assembled", ["tone"] = "base", ["visibleWhen"] = MapDomainDefinition.Always(), ["hotspots"] = new JArray(), ["sceneVisuals"] = new JArray(),
                    ["staticAvatars"] = new JArray(), ["dynamicAvatars"] = new JArray(), ["filters"] = new JArray(new JObject { ["id"] = "all", ["label"] = "全部", ["viewMode"] = "default",
                        ["hotspotIds"] = new JArray(), ["buttonRect"] = MapDefinition.MakeRect(0, 0, 60, 28) }) }; break;
                case "location": item = new JObject { ["label"] = "新地点", ["sceneName"] = "", ["sceneKind"] = "outdoor", ["enabled"] = true,
                    ["enterWhen"] = MapDomainDefinition.Always(), ["visibleWhen"] = MapDomainDefinition.Always(), ["tone"] = "base" }; break;
                case "hotspot": item = new JObject { ["id"] = id, ["label"] = "新地点表现", ["locationId"] = "", ["rect"] = MapDefinition.MakeRect(100, 100, 160, 100) }; break;
                case "scene": item = new JObject { ["id"] = id, ["label"] = "新图块", ["assetUrl"] = "", ["rect"] = MapDefinition.MakeRect(100, 100, 160, 100),
                    ["hotspotIds"] = new JArray(), ["filterIds"] = new JArray("all"), ["visibleWhen"] = MapDomainDefinition.Always() }; break;
                case "filter": item = new JObject { ["id"] = id, ["label"] = "新分层", ["hotspotIds"] = new JArray(), ["buttonRect"] = MapDefinition.MakeRect(0, 100, 60, 28), ["viewMode"] = "default", ["tone"] = "base" }; break;
                case "npc": item = new JObject { ["label"] = "新人物", ["runtimeNames"] = new JArray(), ["aliases"] = new JArray(), ["placementPolicy"] = "unique" }; break;
                case "placement": item = new JObject { ["npcId"] = "", ["locationId"] = "", ["label"] = "新驻点", ["enabled"] = true,
                    ["presenceWhen"] = MapDomainDefinition.Always(), ["worldBinding"] = JValue.CreateNull() }; break;
                case "avatar": item = new JObject { ["id"] = id, ["label"] = "新头像", ["placementId"] = "", ["hotspotId"] = "", ["assetUrl"] = "",
                    ["relX"] = 0, ["relY"] = 0, ["w"] = 44, ["h"] = 44, ["visibleWhen"] = MapDomainDefinition.Always() }; break;
                case "rule": item = new JObject { ["label"] = "新剧情条件", ["condition"] = MapDomainDefinition.Always(), ["tone"] = "base" }; break;
                default: throw new System.IO.InvalidDataException("不支持的创建类型。");
            }
            Patch(kind, item, values); return item;
        }
        private static void Patch(string kind, JObject item, JObject values)
        {
            string[] allowed = kind switch {
                "page" => new[] { "title", "tabLabel", "width", "height", "visibleWhen", "tone", "backgroundAssetUrl" },
                "location" => new[] { "label", "sceneName", "sceneKind", "enabled", "enterWhen", "visibleWhen", "tone" },
                "hotspot" => new[] { "label", "locationId", "rect" },
                "scene" => new[] { "label", "assetUrl", "rect", "hotspotIds", "filterIds", "visibleWhen", "variants" },
                "filter" => new[] { "label", "buttonRect", "hotspotIds", "viewMode", "tone" },
                "npc" => new[] { "label", "runtimeNames", "aliases", "placementPolicy" },
                "placement" => new[] { "npcId", "locationId", "label", "enabled", "presenceWhen", "worldBinding" },
                "avatar" => new[] { "label", "placementId", "hotspotId", "assetUrl", "relX", "relY", "w", "h", "visibleWhen", "variants" },
                "rule" => new[] { "label", "condition", "tone" }, _ => Array.Empty<string>() };
            MapRuleEvaluator.Keys(values, allowed);
            foreach (var p in values.Properties()) item[p.Name] = p.Value.DeepClone();
        }
        private static void CopyPage(JObject d, JObject original, string id, string title)
        {
            MapRuleEvaluator.Need(d["pages"][id] == null, "复制页面标识已存在。");
            var page = (JObject)original.DeepClone(); page["id"] = id; page["title"] = title ?? (string)page["title"] + "副本"; page["tabLabel"] = page["title"].DeepClone();
            var hotspots = ((JArray)page["hotspots"]).ToDictionary(x => (string)x["id"], x => ChildId("view", id, (string)x["id"]));
            var filters = ((JArray)page["filters"]).ToDictionary(x => (string)x["id"], x => (string)x["id"] is "all" or "hierarchy" ? (string)x["id"] : ChildId("filter", id, (string)x["id"]));
            if (page["defaultFilterId"] != null && filters.TryGetValue((string)page["defaultFilterId"], out string defaultFilter)) page["defaultFilterId"] = defaultFilter;
            foreach (JObject hotspot in (JArray)page["hotspots"]) hotspot["id"] = hotspots[(string)hotspot["id"]];
            foreach (JObject filter in (JArray)page["filters"])
            {
                filter["id"] = filters[(string)filter["id"]]; filter["hotspotIds"] = new JArray(((JArray)filter["hotspotIds"]).Select(x => hotspots[(string)x]));
            }
            foreach (JObject visual in (JArray)page["sceneVisuals"])
            {
                visual["id"] = ChildId("visual", id, (string)visual["id"]); visual["hotspotIds"] = new JArray(((JArray)visual["hotspotIds"]).Select(x => hotspots[(string)x]));
                if (visual["filterIds"] is JArray list) visual["filterIds"] = new JArray(list.Select(x => filters.TryGetValue((string)x, out string next) ? next : (string)x));
            }
            foreach (JObject avatar in ((JArray)page["staticAvatars"]).Concat(page["dynamicAvatars"] as JArray ?? new JArray()))
            {
                avatar["id"] = ChildId("avatar", id, (string)avatar["id"]); avatar["hotspotId"] = hotspots[(string)avatar["hotspotId"]];
            }
            d["pages"][id] = page; ((JArray)d["pageOrder"]).Add(id);
        }
        private static void RefreshBounds(JObject d, JObject page)
        {
            foreach (JObject hotspot in (JArray)page["hotspots"])
            {
                var visuals = ((JArray)page["sceneVisuals"]).Where(v => v["hotspotIds"] is JArray ids && ids.Any(id => (string)id == (string)hotspot["id"])).ToArray();
                if (visuals.Length == 0) continue;
                foreach (var visual in visuals) MapDefinition.Rect(visual["rect"]);
                var bounds = MapDefinition.Union(visuals.Select(v => (JObject)v["rect"]));
                if (!JToken.DeepEquals(bounds, hotspot["rect"])) d["handTunedLayoutIds"][(string)hotspot["id"]] = true;
                hotspot["rect"] = bounds;
            }
            var all = ((JArray)page["filters"]).OfType<JObject>().FirstOrDefault(f => (string)f["id"] == "all");
            if (all != null) all["hotspotIds"] = new JArray(((JArray)page["hotspots"]).Select(h => h["id"].DeepClone()));
        }
    }
}
