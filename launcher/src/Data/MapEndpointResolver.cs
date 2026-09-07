using System;
using System.Linq;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Data
{
    /// <summary>任务源拥有端点选择；地图域只解析人物/驻点，不拥有另一份任务绑定。</summary>
    public static class MapEndpointResolver
    {
        public static void Validate(JObject definition, JObject endpoint)
        {
            MapRuleEvaluator.Keys(endpoint, "mode", "npcId", "placementId");
            string mode = MapRuleEvaluator.Text(endpoint, "mode", 24), npcId = MapDomainDefinition.Id(endpoint, "npcId");
            MapRuleEvaluator.Need(definition["npcs"]?[npcId] != null, "任务端点引用未知人物。");
            if (mode == "fixed")
            {
                string placementId = MapDomainDefinition.Id(endpoint, "placementId");
                MapRuleEvaluator.Need((string)definition["placements"]?[placementId]?["npcId"] == npcId, "任务固定驻点不属于所选人物。");
            }
            else MapRuleEvaluator.Need(mode == "followCurrent" && endpoint["placementId"] == null, "任务端点只支持固定驻点或跟随当前唯一驻点。");
        }

        public static string FindNpc(JObject definition, string name)
        {
            foreach (var p in ((JObject)definition["npcs"]).Properties())
                if (((JArray)p.Value["runtimeNames"]).Concat((JArray)p.Value["aliases"]).Any(x => string.Equals((string)x, name, StringComparison.OrdinalIgnoreCase))) return p.Name;
            return "";
        }

        public static JObject Resolve(JObject definition, JObject task, string role, JObject placementStates)
        {
            string field = role == "get" ? "get" : "finish";
            JObject endpoint = task[field + "_endpoint"] as JObject;
            string npcId = "", placementId = "", mode = "legacy";
            var placements = (JObject)definition["placements"];
            if (endpoint != null)
            {
                Validate(definition, endpoint);
                npcId = (string)endpoint["npcId"]; mode = (string)endpoint["mode"];
                if (mode == "fixed") placementId = (string)endpoint["placementId"];
                else
                {
                    var owned = placements.Properties().Where(p => (string)p.Value["npcId"] == npcId && p.Value.Value<bool>("enabled")).ToArray();
                    if (owned.Any(p => placementStates[p.Name]?["conflict"] != null))
                        return Missing("ambiguous_placement", npcId, mode, "该人物当前有多个有效驻点，请指定固定驻点");
                    if (owned.Any(p => (string)placementStates[p.Name]?["reason"]?["state"] == "unknown"))
                        return Missing("unknown_placement", npcId, mode, "缺少人物驻点所需的剧情事实，不能推测当前驻点");
                    var active = placements.Properties().Where(p => (string)p.Value["npcId"] == npcId && placementStates[p.Name]?.Value<bool>("present") == true).ToArray();
                    if (active.Length != 1) return Missing(active.Length == 0 ? "npc_absent" : "ambiguous_placement", npcId, mode,
                        active.Length == 0 ? "该人物当前没有有效驻点" : "该人物当前有多个有效驻点，请指定固定驻点");
                    placementId = active[0].Name;
                }
            }
            else
            {
                npcId = FindNpc(definition, task.Value<string>(field + "_npc") ?? "");
                if (npcId == "") return Missing("unmapped_legacy_npc", "", mode, "旧任务人物未登记到地图");
                string hotspot = task.Value<string>(field + "_npc_hotspot") ?? "";
                string location = hotspot == "" ? "" : FindLocation(definition, hotspot);
                var found = placements.Properties().FirstOrDefault(p => (string)p.Value["npcId"] == npcId && (hotspot == "" || (string)p.Value["locationId"] == location));
                if (found == null) return Missing("placement_missing", npcId, mode, "任务指定的旧驻点不存在");
                placementId = found.Name;
            }
            var placement = (JObject)placements[placementId];
            var state = (JObject)placementStates[placementId];
            var npc = (JObject)definition["npcs"][npcId];
            bool present = state?.Value<bool>("present") == true;
            // 新结构端点不能把未接入真实场景的地图头像当可互动人物；legacy 仍保留既有世界接入。
            bool legacyUnbound = mode == "legacy" && placement.Value<bool?>("legacyWorldAdapter") == true && placement["worldBinding"]?.Type == JTokenType.Null;
            bool worldReady = legacyUnbound || state?.Value<bool>("worldReady") == true;
            return new JObject { ["status"] = !present ? "npc_absent" : !worldReady ? "world_binding_required" : "resolved",
                ["resolved"] = present && worldReady, ["mode"] = mode, ["npcId"] = npcId, ["placementId"] = placementId,
                ["locationId"] = placement["locationId"], ["npcName"] = npc["label"], ["runtimeNames"] = npc["runtimeNames"].DeepClone(),
                ["aliases"] = npc["aliases"].DeepClone(), ["reason"] = !present ? "该人物驻点当前不存在" : !worldReady ? "请先绑定已就绪的真实 NPC 实例" : "" };
        }

        public static string FindLocation(JObject definition, string hotspotId)
        {
            if (definition["locations"]?[hotspotId] != null) return hotspotId;
            foreach (var page in MapDefinition.Pages(definition))
                foreach (var h in (JArray)page["hotspots"]) if ((string)h["id"] == hotspotId) return (string)h["locationId"];
            return "";
        }
        private static JObject Missing(string status, string npcId, string mode, string reason) => new JObject {
            ["status"] = status, ["resolved"] = false, ["npcId"] = npcId, ["mode"] = mode,
            ["placementId"] = "", ["locationId"] = "", ["reason"] = reason };
    }
}
