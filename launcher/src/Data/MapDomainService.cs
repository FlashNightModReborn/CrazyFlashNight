using System;
using System.Collections.Generic;
using System.Linq;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Data
{
    /// <summary>生产和作者模拟使用同一个纯地图投影。不会写玩家数据或执行场景跳转。</summary>
    public static class MapDomainService
    {
        public static JObject Project(JObject definition, JObject facts, JObject tasks, JObject worldBindings = null)
        {
            MapRuleEvaluator.Need(definition.Value<int>("version") == 2, "地图领域需要第二阶段定义。");
            facts ??= new JObject(); tasks ??= new JObject();
            var rules = (JObject)definition["rules"];
            var locations = (JObject)definition["locations"];
            var locationStates = new JObject(); var unlocks = new JObject();
            foreach (var p in locations.Properties())
            {
                var loc = (JObject)p.Value;
                var visible = MapRuleEvaluator.Evaluate(loc["visibleWhen"], rules, facts);
                var enter = MapRuleEvaluator.Evaluate(loc["enterWhen"], rules, facts);
                bool enabled = loc.Value<bool>("enabled");
                locationStates[p.Name] = new JObject { ["visible"] = enabled && MapRuleEvaluator.Passed(visible), ["enterable"] = enabled && MapRuleEvaluator.Passed(enter),
                    ["visibleReason"] = visible, ["enterReason"] = enter, ["sceneName"] = loc["sceneName"], ["sceneKind"] = loc["sceneKind"] };
                string group = MapDomainDefinition.GroupId(p.Name, loc);
                if (group != "") unlocks[group] = MapRuleEvaluator.Passed(enter);
            }
            var placementStates = new JObject();
            foreach (var p in ((JObject)definition["placements"]).Properties())
            {
                var placement = (JObject)p.Value;
                var reason = MapRuleEvaluator.Evaluate(placement["presenceWhen"], rules, facts);
                var binding = placement["worldBinding"] as JObject;
                string occurrence = binding?.Value<string>("occurrenceId") ?? "";
                var npc = definition["npcs"][(string)placement["npcId"]];
                bool worldReady = occurrence != "" && worldBindings?[occurrence]?.Value<bool>("ready") == true &&
                    (string)worldBindings[occurrence]["sourceDigest"] == (string)placement["worldBinding"]["sourceDigest"] &&
                    (string)worldBindings[occurrence]["sceneKey"] == (string)definition["locations"][(string)placement["locationId"]]["sceneName"] &&
                    ((JArray)npc["runtimeNames"]).Concat((JArray)npc["aliases"]).Any(n => (string)n == (string)worldBindings[occurrence]["taskName"]);
                placementStates[p.Name] = new JObject { ["present"] = placement.Value<bool>("enabled") && MapRuleEvaluator.Passed(reason),
                    ["worldReady"] = worldReady, ["reason"] = reason, ["npcId"] = placement["npcId"], ["locationId"] = placement["locationId"] };
            }
            foreach (var npc in ((JObject)definition["npcs"]).Properties())
            {
                if ((string)npc.Value["placementPolicy"] != "unique") continue;
                var active = placementStates.Properties().Where(p => (string)p.Value["npcId"] == npc.Name && p.Value.Value<bool>("present")).ToArray();
                if (active.Length < 2) continue;
                foreach (var p in active) { p.Value["present"] = false; p.Value["conflict"] = "人物的唯一驻点条件重叠"; }
            }
            var pages = new JObject(); var hotspots = new JObject(); var avatarVisibility = new JObject();
            var visualVisibility = new JObject(); var avatarAssets = new JObject(); var visualAssets = new JObject(); var appearances = new JObject { ["avatars"] = new JObject(), ["visuals"] = new JObject() };
            var avatarReasons = new JObject(); var visualReasons = new JObject(); var ruleReasons = new JObject();
            foreach (var p in rules.Properties()) ruleReasons[p.Name] = MapRuleEvaluator.Evaluate(p.Value["condition"], rules, facts);
            var enabledIds = new JArray(); var visibleIds = new JArray();
            var firstHotspot = new Dictionary<string, string>(StringComparer.Ordinal);
            var hotspotPages = new Dictionary<string, string>(StringComparer.Ordinal);
            foreach (var page in MapDefinition.Pages(definition))
            {
                string pageId = (string)page["id"];
                var pageReason = MapRuleEvaluator.Evaluate(page["visibleWhen"], rules, facts);
                bool pageVisible = MapRuleEvaluator.Passed(pageReason);
                pages[pageId] = new JObject { ["visible"] = pageVisible, ["reason"] = pageReason };
                foreach (JObject h in (JArray)page["hotspots"])
                {
                    string id = (string)h["id"], locId = (string)h["locationId"];
                    var state = (JObject)locationStates[locId];
                    bool visible = pageVisible && state.Value<bool>("visible"), enterable = visible && state.Value<bool>("enterable");
                    var reason = (JObject)state["enterReason"];
                    hotspots[id] = new JObject { ["locationId"] = locId, ["pageId"] = pageId, ["visible"] = visible, ["enabled"] = enterable,
                        ["unlockGroup"] = MapDomainDefinition.GroupId(locId, (JObject)locations[locId]), ["lockedReason"] = enterable ? "" : !visible ? "该地点当前不可见" : Explain(reason), ["reason"] = reason.DeepClone() };
                    if (enterable) enabledIds.Add(id); if (visible) visibleIds.Add(id);
                    if (!firstHotspot.ContainsKey(locId) || (!hotspots[firstHotspot[locId]].Value<bool>("visible") && visible)) firstHotspot[locId] = id;
                    hotspotPages[id] = pageId;
                }
                foreach (JObject slot in ((JArray)page["staticAvatars"]).Concat(page["dynamicAvatars"] as JArray ?? new JArray()))
                {
                    string asset = slot.Value<string>("assetUrl") ?? "";
                    if ((string)slot["kind"] == "roommateGender")
                    {
                        string gender = facts["dynamic"]?.Value<string>("roommateGender");
                        asset = gender is "女" or "female" ? "assets/map/roommate-female.webp" : gender is "男" or "male" ? "assets/map/roommate-male.webp" : "";
                    }
                    var appearance = Appearance(slot, asset, rules, facts);
                    appearances["avatars"][(string)slot["id"]] = appearance; avatarAssets[(string)slot["id"]] = appearance["assetUrl"];
                    var ruleReason = MapRuleEvaluator.Evaluate(slot["visibleWhen"], rules, facts);
                    avatarVisibility[(string)slot["id"]] = pageVisible && placementStates[(string)slot["placementId"]].Value<bool>("present") &&
                        hotspots[(string)slot["hotspotId"]].Value<bool>("visible") && MapRuleEvaluator.Passed(ruleReason) && (string)appearance["state"] == "known";
                    string locationId = (string)hotspots[(string)slot["hotspotId"]]["locationId"];
                    avatarReasons[(string)slot["id"]] = VisibilityReason(avatarVisibility.Value<bool>((string)slot["id"]), "头像是否显示", pageReason, ruleReason,
                        (JObject)placementStates[(string)slot["placementId"]]["reason"], (JObject)locationStates[locationId]["visibleReason"]);
                }
                var visualPage = new JObject(); visualVisibility[pageId] = visualPage;
                var assetPage = new JObject(); visualAssets[pageId] = assetPage; appearances["visuals"][pageId] = new JObject();
                visualReasons[pageId] = new JObject();
                foreach (JObject visual in (JArray)page["sceneVisuals"])
                {
                    var appearance = Appearance(visual, (string)visual["assetUrl"], rules, facts);
                    appearances["visuals"][pageId][(string)visual["id"]] = appearance; assetPage[(string)visual["id"]] = appearance["assetUrl"];
                    var ruleReason = MapRuleEvaluator.Evaluate(visual["visibleWhen"] ?? MapDomainDefinition.Always(), rules, facts);
                    visualPage[(string)visual["id"]] = pageVisible && (((JArray)visual["hotspotIds"]).Count == 0 || ((JArray)visual["hotspotIds"]).Any(x => hotspots[(string)x]?.Value<bool>("visible") == true)) &&
                        MapRuleEvaluator.Passed(ruleReason) && (string)appearance["state"] == "known";
                    var parentReasons = ((JArray)visual["hotspotIds"]).Select(id => (JObject)locationStates[(string)hotspots[(string)id]["locationId"]]["visibleReason"]).Prepend(ruleReason).Prepend(pageReason).ToArray();
                    visualReasons[pageId][(string)visual["id"]] = VisibilityReason(visualPage.Value<bool>((string)visual["id"]), "图块是否显示", parentReasons);
                }
            }
            string currentLocation = ResolveCurrentLocation(definition, facts["scene"] as JObject ?? new JObject());
            string currentHotspot = firstHotspot.TryGetValue(currentLocation, out string current) ? current : "";
            string currentPage = currentHotspot != "" ? hotspotPages[currentHotspot] : (string)definition["pageOrder"][0];
            string lockReason = facts["navigation"]?.Value<string>("reason") ?? "facts_unavailable";
            if (lockReason == "" && facts["scene"]?.Value<bool?>("inCombat") == true) lockReason = "combat_active";
            bool locked = lockReason != "";
            var endpoints = new JObject();
            foreach (var task in tasks.Properties())
            {
                var roles = new JObject();
                foreach (var role in new[] { "get", "finish" })
                {
                    var endpoint = MapEndpointResolver.Resolve(definition, (JObject)task.Value, role, placementStates);
                    string locId = endpoint.Value<string>("locationId") ?? "";
                    string hotspot = firstHotspot.TryGetValue(locId, out string target) ? target : "";
                    // 无地图入口的独立场景只为已完成任务提供交付路线，不生成公开传送热点。
                    bool privateDelivery = role == "finish" && hotspot == ""
                        && locationStates[locId]?.Value<bool>("enterable") == true
                        && facts["tasks"]?[task.Name]?.Value<bool>("active") == true
                        && facts["tasks"]?[task.Name]?.Value<bool>("deliverable") == true;
                    bool route = endpoint.Value<bool>("resolved") && (privateDelivery
                        || (hotspot != "" && hotspots[hotspot].Value<bool>("enabled")));
                    endpoint["hotspotId"] = hotspot; endpoint["returnNavigable"] = route; endpoint["navigable"] = route && !locked;
                    endpoint["pageId"] = hotspot != "" ? hotspotPages[hotspot] : "";
                    if (endpoint.Value<bool>("resolved") && !route) endpoint["reason"] = hotspot == "" ? "该驻点没有可见地图表现" : (string)hotspots[hotspot]["lockedReason"];
                    else if (route && locked) endpoint["reason"] = lockReason == "combat_active" || lockReason == "stage_run_active"
                        ? "当前仍在战斗流程中，请先正常返回后再前往" : "当前流程尚未结束，请先完成结算或返回流程，再刷新重试";
                    roles[role] = endpoint;
                }
                endpoints[task.Name] = roles;
            }
            var markers = new JArray(); var seen = new HashSet<string>(StringComparer.Ordinal); var candidates = new List<JObject>();
            var taskFacts = facts["tasks"] as JObject ?? new JObject();
            var order = facts["activeOrder"] as JArray ?? new JArray(taskFacts.Properties().Where(p => p.Value.Value<bool?>("active") == true).Select(p => p.Name));
            foreach (var id in order)
            {
                string taskId = (string)id;
                if (taskFacts[taskId]?.Value<bool?>("deliverable") != true) continue;
                var endpoint = endpoints[taskId]?["finish"] as JObject;
                if (endpoint?.Value<bool>("resolved") != true) continue;
                candidates.Add(endpoint);
                string placementId = (string)endpoint["placementId"];
                if (!seen.Add(placementId) || (string)endpoint["hotspotId"] == "") continue;
                foreach (var view in hotspots.Properties().Where(p => (string)p.Value["locationId"] == (string)endpoint["locationId"] && p.Value.Value<bool>("visible")))
                    markers.Add(new JObject { ["id"] = "task_npc_" + placementId + "_" + view.Name, ["kind"] = "taskNpc", ["npcId"] = endpoint["npcId"],
                        ["npcName"] = endpoint["npcName"], ["placementId"] = placementId, ["pageId"] = view.Value["pageId"], ["hotspotId"] = view.Name });
            }
            if (currentHotspot != "") foreach (var view in hotspots.Properties().Where(p => (string)p.Value["locationId"] == currentLocation && p.Value.Value<bool>("visible")))
                markers.Add(new JObject { ["id"] = "current_location_" + view.Name, ["kind"] = "currentLocation", ["pageId"] = view.Value["pageId"],
                    ["hotspotId"] = view.Name, ["label"] = "当前位置", ["tone"] = "accent" });
            var delivery = candidates.FirstOrDefault(e => e.Value<bool>("navigable")) ?? candidates.FirstOrDefault(e => e.Value<bool>("returnNavigable")) ?? candidates.FirstOrDefault();
            var snapshot = new JObject { ["version"] = 4, ["defaultPageId"] = currentPage, ["regionId"] = currentPage, ["currentHotspotId"] = currentHotspot,
                ["navigationLocked"] = locked, ["navigationLockReason"] = lockReason, ["unlocks"] = unlocks, ["enabledHotspotIds"] = enabledIds,
                ["visibleHotspotIds"] = visibleIds, ["hotspotStates"] = hotspots, ["pageStates"] = pages, ["avatarVisibility"] = avatarVisibility,
                ["visualVisibility"] = visualVisibility, ["avatarAssetUrls"] = avatarAssets, ["visualAssetUrls"] = visualAssets, ["currentLocationId"] = currentLocation,
                ["markers"] = markers, ["tips"] = new JArray(), ["dynamicAvatarState"] = facts["dynamic"]?.DeepClone() ?? new JObject(),
                ["taskChains"] = facts["chains"]?.DeepClone() ?? new JObject(), ["infrastructure"] = facts["infrastructure"]?.DeepClone() ?? new JObject() };
            var npcTasks = MapNpcTaskProjection.Build(definition, tasks, endpoints, currentLocation);
            return new JObject { ["snapshot"] = snapshot, ["locations"] = locationStates, ["placements"] = placementStates, ["taskEndpoints"] = endpoints,
                ["npcTasks"] = npcTasks["npcTasks"], ["autoAccept"] = npcTasks["autoAccept"],
                ["appearances"] = appearances,
                ["avatarReasons"] = avatarReasons, ["visualReasons"] = visualReasons, ["ruleReasons"] = ruleReasons,
                ["hasDeliverable"] = order.Any(id => taskFacts[(string)id]?.Value<bool?>("deliverable") == true),
                ["delivery"] = delivery == null ? new JObject { ["hotspotId"] = "", ["navigable"] = false, ["returnNavigable"] = false } : new JObject {
                    ["hotspotId"] = delivery["hotspotId"], ["navigable"] = delivery["navigable"], ["returnNavigable"] = delivery["returnNavigable"] },
                ["currentLocationId"] = currentLocation, ["hudMode"] = facts["scene"]?.Value<bool?>("inCombat") == true ? "3" : currentLocation == "" ? "0" : (string)locations[currentLocation]["sceneKind"] == "base" ? "1" : "2" };
        }

        private static JObject VisibilityReason(bool visible, string label, params JObject[] reasons) => new JObject {
            ["state"] = visible ? "passed" : reasons.Any(r => (string)r["state"] == "unknown") ? "unknown" : "failed", ["label"] = label,
            ["detail"] = visible ? "页面、地点、驻点和自身条件允许显示" : "请检查下列条件，以及启用状态、人物驻点冲突和外观变体", ["children"] = new JArray(reasons.Select(r => r.DeepClone())) };
        private static JObject Appearance(JObject item, string defaultAsset, JObject rules, JObject facts)
        {
            var branches = new JArray(); string selected = "", asset = defaultAsset; bool unknown = false, selectedKnown = false;
            foreach (JObject variant in item["variants"] as JArray ?? new JArray())
            {
                var reason = MapRuleEvaluator.Evaluate(variant["when"], rules, facts);
                branches.Add(new JObject { ["id"] = variant["id"], ["reason"] = reason });
                if (selectedKnown) continue;
                if ((string)reason["state"] == "unknown") unknown = true;
                if (MapRuleEvaluator.Passed(reason)) { selected = (string)variant["id"]; asset = (string)variant["assetUrl"]; selectedKnown = true; }
            }
            // 变体从上到下首项命中；更靠前的未知条件不能偷偷按 false 跳过。
            return new JObject { ["state"] = unknown || string.IsNullOrEmpty(asset) ? "unknown" : "known", ["variantId"] = selected,
                ["assetUrl"] = unknown ? "" : asset, ["branches"] = branches };
        }
        public static string ResolveCurrentLocation(JObject definition, JObject scene)
        {
            if (scene.Value<bool?>("inCombat") == true) return "";
            var locations = (JObject)definition["locations"];
            string Find(string value) => locations.Properties().FirstOrDefault(p => (string)p.Value["sceneName"] == value)?.Name ?? "";
            string flag = Find(scene.Value<string>("stageFlag") ?? "");
            if (flag != "") return flag;
            string label = scene.Value<string>("frameLabel") ?? "";
            string kind = label == "基地地图" ? "base" : label == "外部地图" ? "outdoor" : "";
            foreach (string key in new[] { "frameLabel", "entrance", "mapFrame" })
            {
                string id = Find(scene.Value<string>(key) ?? "");
                if (id != "" && (kind == "" || (string)locations[id]["sceneKind"] == kind)) return id;
            }
            return "";
        }
        public static string Explain(JObject reason)
        {
            if (reason["children"] is JArray children)
            {
                var failed = children.OfType<JObject>().Where(c => !MapRuleEvaluator.Passed(c)).Select(Explain).Take(4);
                return (string)reason["label"] + "：" + string.Join("；", failed);
            }
            return (string)reason["label"] + "：" + (string)reason["detail"];
        }
    }
}
