using System;
using System.Collections.Generic;
using System.Linq;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Data
{
    public sealed class MapAuthoringPlan
    {
        public JObject Definition, Tasks, PreviewAssets;
        public JArray Files, Impact, AssetCatalogue;
        public string TaskDigest;
        public static MapAuthoringPlan Create(string root, byte[] before, JArray changes, MapTaskCatalog tasks, MapWorldCatalog world)
        {
            var original = MapDefinition.Parse(before);
            var plan = new MapAuthoringPlan { Files = new JArray(), Impact = new JArray(), PreviewAssets = new JObject(), AssetCatalogue = new JArray(), Tasks = new JObject() };
            MapRuleEvaluator.Need(changes != null && changes.Count <= 256 && changes.All(x => x is JObject), "内容变更列表不正确。");
            var layout = new JArray(changes.Where(c => (string)c["kind"] != "task").Select(c => c.DeepClone()));
            var taskChanges = new JArray(changes.Where(c => (string)c["kind"] == "task").Select(c => c.DeepClone()));
            plan.Definition = MapDefinition.Edit(original, layout);
            if (original.Value<int>("version") == 2)
            {
                MapRuleEvaluator.Need(tasks != null && world != null, "内容制作目录尚未就绪。");
                var patch = MapTaskSourcePatch.Apply(tasks, taskChanges, plan.Definition); plan.Tasks = patch.Tasks; plan.TaskDigest = tasks.Digest;
                ValidateTaskReferences(plan.Definition, plan.Tasks);
                PreserveLegacyReachability(original, plan.Definition, tasks.Tasks, plan.Tasks);
                world.EnrichBindings(plan.Definition);
                var assets = new MapAssetCandidates(root).Resolve(plan.Definition); plan.PreviewAssets = assets.PreviewData; plan.AssetCatalogue = assets.Catalogue;
                foreach (var change in assets.NewFiles) plan.Files.Add(change);
                foreach (var file in patch.Files) plan.Files.Add(MapChangeJournal.FileChange(file.Key, tasks.SourceBytes[file.Key], file.Value));
                tasks.ValidateFacts(plan.Definition);
            }
            else MapRuleEvaluator.Need(taskChanges.Count == 0, "任务绑定编辑需要第二阶段定义。");
            byte[] after = JToken.DeepEquals(original, plan.Definition) ? before : MapDefinition.Bytes(plan.Definition);
            plan.Files.Add(MapChangeJournal.FileChange(MapDefinition.RelativePath, before, after));
            foreach (JObject file in plan.Files)
                if ((string)file["beforeDigest"] != (string)file["afterDigest"]) plan.Impact.Add(new JObject { ["path"] = file["path"],
                    ["kind"] = (string)file["beforeDigest"] == "" ? "create" : "update", ["beforeDigest"] = file["beforeDigest"], ["afterDigest"] = file["afterDigest"] });
            return plan;
        }
        public static void ValidateTaskReferences(JObject definition, JObject tasks)
        {
            var referenced = MapRuleEvaluator.RequiredFacts(definition);
            foreach (var id in (JArray)referenced["tasks"]) MapRuleEvaluator.Need(tasks[(string)id] != null, "地图条件引用未知任务：" + id);
            foreach (var p in tasks.Properties()) foreach (string role in new[] { "get", "finish" })
            {
                var task = (JObject)p.Value;
                if (task[role + "_endpoint"] == null || task[role + "_endpoint"].Type == JTokenType.Null) continue;
                MapRuleEvaluator.Need(task[role + "_endpoint"] is JObject, "任务端点必须是结构化对象：" + p.Name);
                var endpoint = (JObject)task[role + "_endpoint"];
                MapRuleEvaluator.Need(task[role + "_npc"] == null && task[role + "_npc_hotspot"] == null, "任务保留了新旧两套端点：" + p.Name);
                try { MapEndpointResolver.Validate(definition, endpoint); }
                catch (Exception ex) { throw new System.IO.InvalidDataException("任务 " + p.Name + " 的" + (role == "get" ? "接取" : "交付") + "端点受影响：" + ex.Message); }
                var placements = ((JObject)definition["placements"]).Properties().Where(x => (string)x.Value["npcId"] == (string)endpoint["npcId"]);
                if ((string)endpoint["mode"] == "fixed") placements = placements.Where(x => x.Name == (string)endpoint["placementId"]);
                MapRuleEvaluator.Need(placements.Any() && placements.All(x => MapDefinition.Pages(definition).Any(page => ((JArray)page["hotspots"]).Any(h => (string)h["locationId"] == (string)x.Value["locationId"]))), "任务 " + p.Name + " 的驻点没有地图表现，请先重绑任务或保留一个地点表现。");
            }
        }
        private static void PreserveLegacyReachability(JObject before, JObject after, JObject oldTasks, JObject newTasks)
        {
            foreach (var p in oldTasks.Properties()) foreach (string role in new[] { "get", "finish" })
            {
                if (p.Value[role + "_endpoint"] is JObject || newTasks[p.Name]?[role + "_endpoint"] is JObject) continue;
                string name = p.Value.Value<string>(role + "_npc") ?? "";
                string oldNpc = MapEndpointResolver.FindNpc(before, name); if (oldNpc == "") continue;
                string nextNpc = MapEndpointResolver.FindNpc(after, name);
                MapRuleEvaluator.Need(nextNpc == oldNpc, "人物修改会破坏旧任务 " + p.Name + " 的检索绑定，请先为该任务选择明确端点。");
                string oldHotspot = p.Value.Value<string>(role + "_npc_hotspot") ?? "";
                var previous = ((JObject)before["placements"]).Properties().Where(x => (string)x.Value["npcId"] == oldNpc).ToArray();
                var next = ((JObject)after["placements"]).Properties().Where(x => (string)x.Value["npcId"] == nextNpc).ToArray();
                if (oldHotspot == "") MapRuleEvaluator.Need(previous.Select(x => x.Name).SequenceEqual(next.Select(x => x.Name)), "新增/删除驻点影响旧任务 " + p.Name + " 的任意同名匹配，请先明确固定或跟随绑定。");
                else
                {
                    string location = MapEndpointResolver.FindLocation(before, oldHotspot);
                    MapRuleEvaluator.Need(next.Any(x => (string)x.Value["locationId"] == location), "删除驻点影响旧任务 " + p.Name + "，请先重绑任务。");
                }
                foreach (var placement in previous)
                {
                    string location = (string)placement.Value["locationId"];
                    if (MapDefinition.Pages(before).Any(page => ((JArray)page["hotspots"]).Any(h => (string)h["locationId"] == location)))
                        MapRuleEvaluator.Need(MapDefinition.Pages(after).Any(page => ((JArray)page["hotspots"]).Any(h => (string)h["locationId"] == location)), "地图删除影响旧任务 " + p.Name + " 的地点表现，请先重绑或保留地点表现。");
                }
            }
        }
    }
}
