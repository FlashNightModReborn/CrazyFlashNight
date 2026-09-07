using System;
using System.Linq;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Data
{
    public static class MapSimulationFacts
    {
        /// <summary>模拟可以缺事实（按未知处理），不能包含不可能的任务集合或任意存档字段。</summary>
        public static void Validate(JObject facts, MapTaskCatalog catalog)
        {
            MapRuleEvaluator.Need(facts != null, "模拟事实缺失。");
            MapRuleEvaluator.Keys(facts, "chains", "tasks", "activeOrder", "infrastructure", "flags", "scene", "navigation", "dynamic");
            foreach (string group in new[] { "chains", "tasks", "infrastructure", "flags", "scene", "navigation", "dynamic" })
                MapRuleEvaluator.Need(facts[group] == null || facts[group] is JObject, "模拟事实必须是对象：" + group);
            foreach (var p in (facts["chains"] as JObject ?? new JObject()).Properties())
            { MapRuleEvaluator.Need(catalog.Chains.Contains(p.Name), "未知模拟任务链：" + p.Name); MapRuleEvaluator.Integer(p.Value, "任务链序号"); }
            foreach (var p in (facts["infrastructure"] as JObject ?? new JObject()).Properties())
            { MapRuleEvaluator.Need(catalog.Infrastructure[p.Name] != null, "未知模拟基建：" + p.Name); if (p.Value.Type != JTokenType.Boolean) MapRuleEvaluator.Integer(p.Value, "基建等级"); }
            MapRuleEvaluator.Keys(facts["flags"] as JObject ?? new JObject());
            var tasks = facts["tasks"] as JObject ?? new JObject();
            foreach (var p in tasks.Properties())
            {
                MapRuleEvaluator.Need(catalog.Tasks[p.Name] != null && p.Value is JObject, "未知模拟任务：" + p.Name);
                var task = (JObject)p.Value; MapRuleEvaluator.Keys(task, "finished", "active", "deliverable", "available");
                if (task["finished"] != null) MapRuleEvaluator.Integer(task["finished"], "历史完成次数");
                foreach (string field in new[] { "active", "deliverable", "available" }) MapRuleEvaluator.Need(task[field] == null || task[field].Type == JTokenType.Boolean, "任务模拟状态须明确选择是、否或未知。");
                MapRuleEvaluator.Need(task.Value<bool?>("deliverable") != true || task.Value<bool?>("active") == true, "可交付任务必须先设为进行中：" + p.Name);
            }
            if (facts["activeOrder"] != null)
            {
                MapRuleEvaluator.Need(facts["activeOrder"] is JArray a && a.Count <= 512 && a.All(id => id.Type == JTokenType.String && tasks[(string)id]?.Value<bool?>("active") == true) && a.Select(id => (string)id).Distinct().Count() == a.Count, "进行中任务顺序含重复、未知或未进行中的任务。");
                var order = (JArray)facts["activeOrder"];
                MapRuleEvaluator.Need(tasks.Properties().Where(p => p.Value.Value<bool?>("active") == true).All(p => order.Any(id => (string)id == p.Name)), "进行中任务顺序遗漏了已设置的任务。");
            }
            foreach (var group in new[] { (Name:"scene", Keys:new[] { "stageFlag", "frameLabel", "entrance", "mapFrame", "inCombat" }),
                (Name:"navigation", Keys:new[] { "reason" }), (Name:"dynamic", Keys:new[] { "roommateGender" }) })
            {
                var value = facts[group.Name] as JObject ?? new JObject(); MapRuleEvaluator.Keys(value, group.Keys);
                foreach (var p in value.Properties()) MapRuleEvaluator.Need(p.Name == "inCombat" ? p.Value.Type == JTokenType.Boolean : p.Value.Type == JTokenType.String && ((string)p.Value).Length <= 200 && !((string)p.Value).Any(char.IsControl), "模拟场景事实不正确。" );
            }
        }
    }
}
