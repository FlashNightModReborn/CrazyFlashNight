using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Data
{
    /// <summary>地图定义与静态布局投影；剧情求值由同领域的 MapRuleEvaluator 统一负责。</summary>
    public static class MapDefinition
    {
        public const string RelativePath = "data/map/map_definition.json";
        public static readonly UTF8Encoding Utf8 = new UTF8Encoding(false);
        public static string Hash(byte[] bytes) => Convert.ToHexString(SHA256.HashData(bytes));
        public static byte[] Bytes(JObject value) => Utf8.GetBytes(value.ToString(Formatting.Indented) + "\n");
        public static JObject Parse(byte[] bytes)
        {
            if (bytes.Length > 2 * 1024 * 1024) throw new InvalidDataException("地图定义超过 2 MiB。");
            using var reader = new JsonTextReader(new StringReader(Utf8.GetString(bytes).TrimStart('\uFEFF'))) { MaxDepth = 48, DateParseHandling = DateParseHandling.None };
            var value = JObject.Load(reader, new JsonLoadSettings { DuplicatePropertyNameHandling = DuplicatePropertyNameHandling.Error });
            if (reader.Read()) throw new InvalidDataException("地图定义含多余内容。");
            Validate(value);
            return value;
        }
        public static JObject Load(string root) => Parse(MapProjectFiles.Read(root, RelativePath));
        public static string Script(JObject value) => "var MapDefinitionData = " + JsonConvert.SerializeObject(MapDomainDefinition.WebProjection(value), Formatting.None,
            new JsonSerializerSettings { StringEscapeHandling = StringEscapeHandling.EscapeHtml }) + ";\n";
        public static string BootstrapScript(JObject value) => "if (window === window.top && location.origin === 'https://overlay.local') {\n" + Script(value) + "}\n";
        public static double Number(JToken value)
        {
            if (value == null || (value.Type != JTokenType.Integer && value.Type != JTokenType.Float)) throw new InvalidDataException("坐标必须是数字。");
            double n = value.Value<double>();
            if (!double.IsFinite(n) || Math.Abs(n) > 32768) throw new InvalidDataException("坐标超出可用范围。");
            return n;
        }
        public static JObject Rect(JToken value)
        {
            if (value is not JObject r || r.Count != 4) throw new InvalidDataException("矩形必须包含 x/y/w/h。");
            foreach (var k in new[] { "x", "y", "w", "h" }) Number(r[k]);
            if (Number(r["w"]) <= 0 || Number(r["h"]) <= 0) throw new InvalidDataException("宽高必须大于零。");
            return r;
        }
        public static IEnumerable<JObject> Pages(JObject d) => ((JArray)d["pageOrder"]).Select(id => (JObject)d["pages"][(string)id]);
        private static void Need(bool valid, string message) { if (!valid) throw new InvalidDataException(message); }
        public static void Validate(JObject d)
        {
            int version = d.Value<int?>("version") ?? 0;
            Need((version == 1 || version == 2) && d["pages"] is JObject && d["pageOrder"] is JArray, "地图版本或页面结构不正确。");
            var order = (JArray)d["pageOrder"];
            Need(order.Count > 0 && order.Count <= 32 && order.Select(x => (string)x).Distinct().Count() == order.Count, "地图页面重复或数量不正确。");
            Need(d["avatarSources"] is JObject && (version == 2 || (d["pageUnlockGroups"] is JObject && d["unlockGroups"] is JObject)), "缺少头像或分组定义。");
            Need(((JObject)d["pages"]).Count == order.Count && d["handTunedLayoutIds"] is JObject, "页面集合与顺序不一致。");
            var allHotspots = new HashSet<string>(StringComparer.Ordinal);
            int totalVisuals = 0, totalAvatars = 0;
            foreach (var page in Pages(d))
            {
                Need(page != null && order.Any(x => (string)x == page.Value<string>("id")), "页面 ID 不匹配。");
                Need(Number(page["width"]) > 0 && Number(page["height"]) > 0, "页面尺寸不正确。");
                var ids = new HashSet<string>(StringComparer.Ordinal);
                foreach (string kind in new[] { "hotspots", "filters", "sceneVisuals", "staticAvatars" })
                {
                    Need(page[kind] is JArray list && list.Count <= 512, "地图列表缺失或过大：" + kind);
                    ids.Clear();
                    foreach (JObject item in (JArray)page[kind])
                    {
                        string id = item.Value<string>("id");
                        Need(!string.IsNullOrWhiteSpace(id) && ids.Add(id), "地图对象 ID 为空或重复。");
                        if (kind == "hotspots") Need(allHotspots.Add(id), "热点 ID 跨页面重复。");
                        if (item["rect"] != null) Rect(item["rect"]);
                        if (item["buttonRect"] != null) Rect(item["buttonRect"]);
                        if (item["assetUrl"] != null) ValidateAsset((string)item["assetUrl"]);
                    }
                }
                var hotIds = new HashSet<string>(((JArray)page["hotspots"]).Select(h => (string)h["id"]));
                foreach (var visual in (JArray)page["sceneVisuals"])
                    Need(visual["hotspotIds"] is JArray links && links.All(x => hotIds.Contains((string)x)), "图块引用未知热点。");
                foreach (var filter in (JArray)page["filters"])
                    Need(filter["hotspotIds"] is JArray links && links.All(x => hotIds.Contains((string)x)), "筛选引用未知热点。");
                foreach (var avatar in ((JArray)page["staticAvatars"]).Concat(page["dynamicAvatars"] as JArray ?? new JArray()))
                {
                    Need(hotIds.Contains((string)avatar["hotspotId"]), "头像引用未知热点。");
                    foreach (string key in new[] { "relX", "relY", "w", "h" })
                        if (avatar[key] != null) { var n = Number(avatar[key]); Need(key == "relX" || key == "relY" || n > 0, "头像尺寸必须大于零。"); }
                }
                totalVisuals += ((JArray)page["sceneVisuals"]).Count; totalAvatars += ((JArray)page["staticAvatars"]).Count + ((page["dynamicAvatars"] as JArray)?.Count ?? 0);
            }
            Need(allHotspots.Count <= 512 && totalVisuals <= 1024 && totalAvatars <= 1024, "地图总表现数量超出范围，请拆分内容批次。");
            Need(Bytes(d).Length <= 2 * 1024 * 1024, "地图定义超过 2 MiB。");
            if (version == 2) MapDomainDefinition.Validate(d);
        }
        private static void ValidateAsset(string path)
        {
            Need(path != null && path.StartsWith("assets/map/", StringComparison.Ordinal) && !path.Contains("..") && !path.Contains(':') && !path.Contains('\\'), "地图资源路径不合法。");
        }
        public static JObject Edit(JObject definition, JArray changes)
        {
            if (definition.Value<int>("version") == 2) return MapEditOperations.Edit(definition, changes);
            Need(changes != null && changes.Count <= 256, "编辑操作过多。");
            var d = (JObject)definition.DeepClone();
            foreach (JObject change in changes)
            {
                Need(change.Properties().All(p => new[] { "pageId", "kind", "id", "values" }.Contains(p.Name)), "编辑操作含未知字段。");
                var page = d["pages"][change.Value<string>("pageId")] as JObject;
                Need(page != null, "页面不存在。");
                string kind = change.Value<string>("kind"), id = change.Value<string>("id");
                string collection = kind == "scene" ? "sceneVisuals" : kind == "filter" ? "filters" : kind == "hotspot" ? "hotspots" : "staticAvatars";
                Need(new[] { "page", "scene", "filter", "hotspot", "avatar" }.Contains(kind), "不支持的编辑对象。");
                JObject item = kind == "page" ? page : ((JArray)page[collection]).OfType<JObject>().FirstOrDefault(x => (string)x["id"] == id);
                if (item == null && kind == "avatar") item = (page["dynamicAvatars"] as JArray)?.OfType<JObject>().FirstOrDefault(x => (string)x["id"] == id);
                Need(item != null && change["values"] is JObject, "编辑对象不存在。");
                string[] allowed = kind == "page" ? new[] { "title", "tabLabel" } : kind == "scene" ? new[] { "rect" } :
                    kind == "filter" ? new[] { "buttonRect", "label" } : kind == "hotspot" ? new[] { "label" } : new[] { "relX", "relY", "w", "h" };
                foreach (var p in ((JObject)change["values"]).Properties())
                {
                    Need(allowed.Contains(p.Name), "此字段属于第二阶段或只读身份：" + p.Name);
                    if (p.Name == "rect" || p.Name == "buttonRect") Rect(p.Value);
                    else if (p.Name == "label" || p.Name == "title" || p.Name == "tabLabel") Need(p.Value.Type == JTokenType.String && p.Value.Value<string>().Length is > 0 and <= 100, "显示文字长度须为 1–100。");
                    else { var n = Number(p.Value); Need(p.Name == "relX" || p.Name == "relY" || n > 0, "头像尺寸必须大于零。"); }
                    item[p.Name] = p.Value.DeepClone();
                }
                if (kind == "scene")
                    foreach (JObject hotspot in (JArray)page["hotspots"])
                    {
                        var visuals = ((JArray)page["sceneVisuals"]).Where(v => ((JArray)v["hotspotIds"]).Any(x => (string)x == (string)hotspot["id"])).ToArray();
                        if (!visuals.Any()) continue;
                        var bounds = Union(visuals.Select(v => (JObject)v["rect"]));
                        if (!JToken.DeepEquals(bounds, hotspot["rect"])) d["handTunedLayoutIds"][(string)hotspot["id"]] = true;
                        hotspot["rect"] = bounds;
                    }
            }
            Validate(d);
            return d;
        }
        public static JObject Union(IEnumerable<JObject> rects)
        {
            var r = rects.ToArray(); if (r.Length == 0) return null;
            double x = r.Min(v => (double)v["x"]), y = r.Min(v => (double)v["y"]);
            return MakeRect(x, y, r.Max(v => (double)v["x"] + (double)v["w"]) - x, r.Max(v => (double)v["y"] + (double)v["h"]) - y);
        }
        public static JObject MakeRect(double x, double y, double w, double h) => new JObject { ["x"] = Round(x), ["y"] = Round(y), ["w"] = Round(w), ["h"] = Round(h) };
        private static double Round(double value) => Math.Round(value, 2, MidpointRounding.AwayFromZero);
        public static JObject Hud(JObject d, JObject snapshot = null)
        {
            d = MapDomainDefinition.WebProjection(d);
            if (snapshot != null)
                foreach (var page in Pages(d))
                {
                    string pageId = (string)page["id"];
                    foreach (var hotspot in ((JArray)page["hotspots"]).Where(h => snapshot["hotspotStates"]?[(string)h["id"]]?.Value<bool>("visible") != true).ToArray()) hotspot.Remove();
                    var visible = new HashSet<string>(((JArray)page["hotspots"]).Select(h => (string)h["id"]), StringComparer.Ordinal);
                    foreach (var filter in (JArray)page["filters"]) filter["hotspotIds"] = new JArray(((JArray)filter["hotspotIds"]).Where(id => visible.Contains((string)id)).Select(id => id.DeepClone()));
                    foreach (JObject visual in ((JArray)page["sceneVisuals"]).ToArray())
                    {
                        if (snapshot["visualVisibility"]?[pageId]?[(string)visual["id"]]?.Value<bool>() != true) visual.Remove();
                        else visual["assetUrl"] = snapshot["visualAssetUrls"][pageId][(string)visual["id"]].DeepClone();
                    }
                }
            var entries = new JObject();
            foreach (var page in Pages(d)) foreach (JObject hotspot in (JArray)page["hotspots"])
            {
                string id = (string)hotspot["id"], pageId = (string)page["id"];
                var filters = ((JArray)page["filters"]).OfType<JObject>().Where(f => (string)f["id"] != "all" && (string)f["id"] != "hierarchy" && (string)f["viewMode"] != "hierarchy" &&
                    ((JArray)f["hotspotIds"]).Count < ((JArray)page["hotspots"]).Count && ((JArray)f["hotspotIds"]).Any(x => (string)x == id)).OrderBy(f => ((JArray)f["hotspotIds"]).Count);
                var filter = filters.FirstOrDefault();
                var ids = filter == null ? null : new HashSet<string>(((JArray)filter["hotspotIds"]).Select(x => (string)x));
                var visuals = new JArray(((JArray)page["sceneVisuals"]).Where(v => ids == null || !((JArray)v["hotspotIds"]).Any() || ((JArray)v["hotspotIds"]).Any(x => ids.Contains((string)x))).Select(v => new JObject {
                    ["id"] = v["id"], ["label"] = v["label"] ?? v["id"], ["assetUrl"] = v["assetUrl"], ["hotspotIds"] = v["hotspotIds"], ["sourceRect"] = v["rect"], ["isCurrent"] = ((JArray)v["hotspotIds"]).Any(x => (string)x == id) }));
                var blocks = new JArray(((JArray)page["hotspots"]).Where(h => ids == null || ids.Contains((string)h["id"])).Select(h => new JObject { ["hotspotId"] = h["id"], ["label"] = h["label"] ?? h["id"], ["sourceRect"] = h["rect"] }));
                var bounds = Union(visuals.Concat(blocks).Select(v => (JObject)v["sourceRect"]));
                double padX = Math.Clamp((double)bounds["w"] * .055 * .42, 22 * .22, 54 * .24);
                double padY = Math.Clamp((double)bounds["h"] * .07 * .38, 20 * .18, 48 * .2);
                double x = Math.Max(0, (double)bounds["x"] - padX), y = Math.Max(0, (double)bounds["y"] - padY);
                var viewport = MakeRect(x, y, Math.Max(1, Math.Min((double)page["width"], (double)bounds["x"] + (double)bounds["w"] + padX) - x), Math.Max(1, Math.Min((double)page["height"], (double)bounds["y"] + (double)bounds["h"] + padY) - y));
                entries[id] = new JObject {
                    ["meta"] = new JObject { ["pageId"] = pageId, ["pageLabel"] = page["title"], ["hotspotId"] = id, ["label"] = hotspot["label"], ["sceneName"] = hotspot["sceneName"], ["group"] = d["pageUnlockGroups"][pageId]?["hotspots"]?[id] ?? "" },
                    ["outline"] = new JObject { ["focusFilterId"] = filter?["id"] ?? "", ["focusFilterLabel"] = filter?["label"] ?? "", ["viewportRect"] = viewport, ["currentRect"] = hotspot["rect"], ["blocks"] = blocks, ["visuals"] = visuals }
                };
            }
            return new JObject { ["protocolVersion"] = 1, ["sourceFile"] = RelativePath, ["hotspots"] = entries };
        }
    }
}
