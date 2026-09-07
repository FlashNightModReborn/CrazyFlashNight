using System;
using System.Linq;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Data
{
    /// <summary>作者删除/重绑前的具体引用清单。它只解释关系，最终准入仍由同一维护内核校验。</summary>
    public static class MapReferenceIndex
    {
        public static JObject Build(JObject definition, JObject tasks)
        {
            var result = new JObject();
            void Add(string kind, string id, string owner, string label, string via, bool blocking = true)
            {
                if (string.IsNullOrEmpty(id)) return;
                string key = kind + "/" + id; if (result[key] == null) result[key] = new JArray();
                ((JArray)result[key]).Add(new JObject { ["owner"] = owner, ["label"] = label, ["via"] = via, ["blocking"] = blocking });
            }
            foreach (var page in MapDefinition.Pages(definition))
            {
                string pageId = (string)page["id"], pageLabel = (string)page["title"];
                foreach (var h in (JArray)page["hotspots"]) Add("location", (string)h["locationId"], "hotspot/" + h["id"], pageLabel + " · " + h["label"], "地点表现");
                foreach (var visual in (JArray)page["sceneVisuals"])
                {
                    foreach (var id in (JArray)visual["hotspotIds"]) Add("hotspot", (string)id, "scene/" + visual["id"], pageLabel + " · " + visual["label"], "图块引用");
                    foreach (var id in visual["filterIds"] as JArray ?? new JArray()) Add("filter", pageId + "/" + id, "scene/" + visual["id"], (string)visual["label"], "图块分层");
                }
                foreach (var filter in (JArray)page["filters"])
                    if ((string)filter["id"] != "all") foreach (var id in (JArray)filter["hotspotIds"]) Add("hotspot", (string)id, "filter/" + filter["id"], pageLabel + " · " + filter["label"], "分层引用");
                foreach (var avatar in ((JArray)page["staticAvatars"]).Concat(page["dynamicAvatars"] as JArray ?? new JArray()))
                {
                    Add("placement", (string)avatar["placementId"], "avatar/" + avatar["id"], pageLabel + " · " + avatar["label"], "头像表现");
                    Add("hotspot", (string)avatar["hotspotId"], "avatar/" + avatar["id"], pageLabel + " · " + avatar["label"], "头像锚点");
                }
            }
            foreach (var p in ((JObject)definition["placements"]).Properties())
            {
                Add("location", (string)p.Value["locationId"], "placement/" + p.Name, (string)p.Value["label"], "人物驻点");
                Add("npc", (string)p.Value["npcId"], "placement/" + p.Name, (string)p.Value["label"], "人物驻点");
            }
            foreach (var task in tasks.Properties()) foreach (string role in new[] { "get", "finish" })
            {
                string owner = "task/" + task.Name, label = "任务 " + task.Name, via = role == "get" ? "接取端点" : "交付端点";
                var endpoint = task.Value[role + "_endpoint"] as JObject;
                string npc = endpoint?.Value<string>("npcId") ?? MapEndpointResolver.FindNpc(definition, task.Value.Value<string>(role + "_npc") ?? "");
                Add("npc", npc, owner, label, via);
                foreach (var p in ((JObject)definition["placements"]).Properties().Where(p => (string)p.Value["npcId"] == npc))
                {
                    bool fixedEndpoint = (string)endpoint?["mode"] == "fixed";
                    if (fixedEndpoint && (string)endpoint["placementId"] != p.Name) continue;
                    Add("placement", p.Name, owner, label, via + (fixedEndpoint ? " · 固定驻点" : endpoint == null ? " · 旧任务检索" : " · 跟随人物"), fixedEndpoint || endpoint == null);
                    string locId = (string)p.Value["locationId"];
                    Add("location", locId, owner, label, via);
                    var views = MapDefinition.Pages(definition).SelectMany(page => ((JArray)page["hotspots"]).Select(h => new { Page = page, Hotspot = h })).Where(h => (string)h.Hotspot["locationId"] == locId).ToArray();
                    foreach (var view in views)
                    {
                        Add("hotspot", (string)view.Hotspot["id"], owner, label, "任务地点的地图表现", views.Length == 1);
                        Add("page", (string)view.Page["id"], owner, label, "任务地点所在页面", views.All(h => h.Page == view.Page));
                    }
                }
            }
            foreach (var node in definition.DescendantsAndSelf().OfType<JObject>())
            {
                if ((string)node["type"] == "rule") Add("rule", (string)node["key"], node.Path, "剧情条件引用", node.Path);
                if (node["assetUrl"]?.Type == JTokenType.String) Add("asset", (string)node["assetUrl"], node.Path, node.Value<string>("label") ?? "地图表现", node.Path);
            }
            return result;
        }
    }
}
