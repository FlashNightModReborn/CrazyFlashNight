using System;
using System.Collections.Generic;
using System.Linq;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Data
{
    /// <summary>现场人物匹配和自动接链的唯一地图投影；任务可接取/完成仍由 AS2 复查。</summary>
    public static class MapNpcTaskProjection
    {
        public static JObject Build(JObject definition, JObject tasks, JObject endpoints, string currentLocation)
        {
            var npcTasks = new JObject(); var autoAccept = new JObject();
            // OrderBy 是稳定排序，保持原任务列表加载顺序作为相同 priority 的次序。
            foreach (var p in tasks.Properties().OrderByDescending(p => p.Value.Value<double?>("priority") ?? 0))
                foreach (string role in new[] { "get", "finish" })
                    foreach (string name in Names(definition, (JObject)p.Value, role, (JObject)endpoints[p.Name][role], currentLocation))
                    {
                        string key = "$" + name;
                        if (npcTasks[key] == null) npcTasks[key] = new JObject { ["get"] = new JArray(), ["finish"] = new JArray() };
                        ((JArray)npcTasks[key][role]).Add(p.Name);
                    }
            var chainTasks = tasks.Properties().Select(p => new { Property = p, Chain = (p.Value.Value<string>("chain") ?? "").Split('#') })
                .Where(t => t.Chain.Length == 2 && int.TryParse(t.Chain[1], out _)).GroupBy(t => t.Chain[0]);
            foreach (var chain in chainTasks)
            {
                var ordered = chain.OrderBy(t => int.Parse(t.Chain[1], System.Globalization.CultureInfo.InvariantCulture)).ToArray();
                for (int i = 0; i + 1 < ordered.Length; i++)
                {
                    var finished = ordered[i].Property; var next = ordered[i + 1].Property;
                    bool allowed;
                    if (finished.Value["finish_endpoint"] is not JObject && next.Value["get_endpoint"] is not JObject)
                    {
                        string finishNpc = finished.Value.Value<string>("finish_npc") ?? "", nextNpc = next.Value.Value<string>("get_npc") ?? "";
                        string finishPlace = finished.Value.Value<string>("finish_npc_hotspot") ?? "", nextPlace = next.Value.Value<string>("get_npc_hotspot") ?? "";
                        allowed = nextNpc != "" && nextNpc == finishNpc && (nextPlace == "" || (finishPlace != "" &&
                            MapEndpointResolver.FindLocation(definition, finishPlace) != "" &&
                            MapEndpointResolver.FindLocation(definition, finishPlace) == MapEndpointResolver.FindLocation(definition, nextPlace)));
                    }
                    else allowed = currentLocation != "" && Names(definition, (JObject)finished.Value, "finish", (JObject)endpoints[finished.Name]["finish"], currentLocation)
                        .Intersect(Names(definition, (JObject)next.Value, "get", (JObject)endpoints[next.Name]["get"], currentLocation), StringComparer.Ordinal).Any();
                    autoAccept[finished.Name] = new JObject { ["nextTaskId"] = next.Name, ["allowed"] = allowed };
                }
            }
            // 显式配对：next_task_id 覆盖同一 finished 任务的 chain 派生条目。
            // 与上面 chain 分支的 allowed 判据同口径——下一段必须在完成 NPC 处接取。
            foreach (var p in tasks.Properties())
            {
                if (p.Value is not JObject finishedTask) continue;
                JToken raw = finishedTask["next_task_id"];
                if (raw == null) continue;
                string nextId;
                if (raw.Type == JTokenType.Integer) nextId = raw.Value<long>().ToString(System.Globalization.CultureInfo.InvariantCulture);
                else if (raw.Type == JTokenType.String && int.TryParse((string)raw, out _)) nextId = ((string)raw).Trim();
                else continue;
                if (nextId == p.Name || tasks[nextId] is not JObject nextTask) continue;
                bool allowed;
                if (finishedTask["finish_endpoint"] is not JObject && nextTask["get_endpoint"] is not JObject)
                {
                    string finishNpc = finishedTask.Value<string>("finish_npc") ?? "", nextNpc = nextTask.Value<string>("get_npc") ?? "";
                    string finishPlace = finishedTask.Value<string>("finish_npc_hotspot") ?? "", nextPlace = nextTask.Value<string>("get_npc_hotspot") ?? "";
                    allowed = nextNpc != "" && nextNpc == finishNpc && (nextPlace == "" || (finishPlace != "" &&
                        MapEndpointResolver.FindLocation(definition, finishPlace) != "" &&
                        MapEndpointResolver.FindLocation(definition, finishPlace) == MapEndpointResolver.FindLocation(definition, nextPlace)));
                }
                else
                {
                    var finishedEndpoint = endpoints[p.Name]?["finish"] as JObject;
                    var nextEndpoint = endpoints[nextId]?["get"] as JObject;
                    allowed = currentLocation != "" && finishedEndpoint != null && nextEndpoint != null
                        && Names(definition, finishedTask, "finish", finishedEndpoint, currentLocation)
                            .Intersect(Names(definition, nextTask, "get", nextEndpoint, currentLocation), StringComparer.Ordinal).Any();
                }
                autoAccept[p.Name] = new JObject { ["nextTaskId"] = nextId, ["allowed"] = allowed };
            }
            return new JObject { ["npcTasks"] = npcTasks, ["autoAccept"] = autoAccept };
        }
        private static IEnumerable<string> Names(JObject definition, JObject task, string role, JObject endpoint, string currentLocation)
        {
            if (task[role + "_endpoint"] is not JObject)
            {
                // 历史空 hotspot 是任意同名现场，不由地图首个驻点把它收窄。未登记人物同样保留旧任务行为。
                string name = task.Value<string>(role + "_npc") ?? "", hotspot = task.Value<string>(role + "_npc_hotspot") ?? "";
                if (name != "" && (hotspot == "" || (currentLocation != "" && MapEndpointResolver.FindLocation(definition, hotspot) == currentLocation))) yield return name;
                yield break;
            }
            if (endpoint?.Value<bool>("resolved") != true || currentLocation == "" || endpoint.Value<string>("locationId") != currentLocation) yield break;
            foreach (string name in ((JArray)endpoint["runtimeNames"]).Concat((JArray)endpoint["aliases"]).Select(x => (string)x)) yield return name;
        }
    }
}
