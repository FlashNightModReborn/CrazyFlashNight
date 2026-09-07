using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Data
{
    /// <summary>地图领域的唯一条件求值器。只消费有界事实，不执行脚本或任务玩法。</summary>
    public static class MapRuleEvaluator
    {
        public const int MaxDepth = 8, MaxNodes = 128;
        private static readonly string[] TaskStates = { "finished", "notFinished", "active", "deliverable", "available" };

        public static void Validate(JToken node, JObject rules)
        {
            int remaining = MaxNodes;
            Walk(node, rules, null, new HashSet<string>(StringComparer.Ordinal), 0, ref remaining);
        }

        public static JObject Evaluate(JToken node, JObject rules, JObject facts)
        {
            int remaining = MaxNodes;
            return Walk(node, rules, facts ?? new JObject(), new HashSet<string>(StringComparer.Ordinal), 0, ref remaining);
        }

        public static bool Passed(JObject result) => result.Value<string>("state") == "passed";

        public static JObject RequiredFacts(JObject definition)
        {
            var chains = new SortedSet<string>(StringComparer.Ordinal);
            var tasks = new SortedSet<string>(StringComparer.Ordinal);
            var infrastructure = new SortedSet<string>(StringComparer.Ordinal);
            var flags = new SortedSet<string>(StringComparer.Ordinal);
            foreach (var token in definition.DescendantsAndSelf().OfType<JObject>())
            {
                string type = token.Value<string>("type"), key = token.Value<string>("key");
                if (key == null) continue;
                if (type == "chain") chains.Add(key);
                else if (type == "task") tasks.Add(key);
                else if (type == "infra") infrastructure.Add(key);
                else if (type == "flag") flags.Add(key);
            }
            return new JObject { ["chains"] = new JArray(chains), ["tasks"] = new JArray(tasks),
                ["infrastructure"] = new JArray(infrastructure), ["flags"] = new JArray(flags) };
        }

        private static JObject Walk(JToken token, JObject rules, JObject facts, HashSet<string> visiting, int depth, ref int remaining)
        {
            Need(depth <= MaxDepth && --remaining >= 0, "条件过于复杂：最多 8 层、128 个节点。");
            Need(token is JObject, "条件必须是结构化对象。");
            var node = (JObject)token;
            string type = Text(node, "type", 24);
            string label = node["label"] == null ? "" : Text(node, "label", 120);
            if (type == "always")
            {
                Keys(node, "type", "label");
                return Result(true, label == "" ? "始终满足" : label, "无附加条件");
            }
            if (type == "all" || type == "any")
            {
                Keys(node, "type", "label", "children");
                Need(node["children"] is JArray items && items.Count is > 0 and <= 32, "全部/任一条件须包含 1–32 个子条件。");
                var children = new JArray();
                foreach (var child in (JArray)node["children"]) children.Add(Walk(child, rules, facts, visiting, depth + 1, ref remaining));
                bool anyPass = children.Any(x => (string)x["state"] == "passed");
                bool anyFail = children.Any(x => (string)x["state"] == "failed");
                bool anyUnknown = children.Any(x => (string)x["state"] == "unknown");
                bool? value = type == "all" ? anyFail ? false : anyUnknown ? null : true : anyPass ? true : anyUnknown ? null : false;
                var result = Result(value, label == "" ? type == "all" ? "全部满足" : "任一满足" : label,
                    type == "all" ? "逐项检查全部条件" : "至少一条路径满足即可");
                result["children"] = children;
                return result;
            }
            if (type == "rule")
            {
                Keys(node, "type", "label", "key");
                string key = Text(node, "key", 100);
                Need(rules?[key] is JObject, "引用的地图规则不存在：" + key);
                Need(visiting.Add(key), "地图条件存在循环引用：" + key);
                var result = Walk(rules[key]["condition"], rules, facts, visiting, depth + 1, ref remaining);
                visiting.Remove(key);
                result["ruleId"] = key;
                if (label != "") result["label"] = label;
                return result;
            }
            Need(new[] { "chain", "task", "infra", "flag" }.Contains(type), "未知地图条件类型：" + type);
            string factKey = Text(node, "key", 100);
            if (type == "chain" || type == "infra")
            {
                Keys(node, "type", "label", "key", "min", "max");
                long min = Integer(node["min"], "条件下限");
                long? max = node["max"] == null ? null : Integer(node["max"], "条件上限");
                Need(max == null || max >= min, "条件上限不能小于下限。");
                JToken value = facts?[type == "chain" ? "chains" : "infrastructure"]?[factKey];
                double? current = value?.Type == JTokenType.Boolean ? value.Value<bool>() ? 1 : 0 : NumericFact(value);
                var result = Result(current == null ? null : current >= min && (max == null || current <= max),
                    label == "" ? factKey + (type == "chain" ? "进度" : "基建") : label,
                    "要求 " + min + (max == null ? " 以上" : "–" + max) + "；当前 " + (current?.ToString(System.Globalization.CultureInfo.InvariantCulture) ?? "未知"));
                result["current"] = current == null ? JValue.CreateNull() : new JValue(current.Value);
                result["min"] = min; if (max != null) result["max"] = max.Value;
                return result;
            }
            if (type == "task")
            {
                Keys(node, "type", "label", "key", "state");
                string state = Text(node, "state", 24);
                Need(TaskStates.Contains(state), "未知任务事实：" + state);
                JToken value = facts?["tasks"]?[factKey]?[state == "notFinished" ? "finished" : state];
                bool? passed;
                if (state == "finished" || state == "notFinished")
                {
                    var count = NumericFact(value);
                    passed = count == null ? null : state == "finished" ? count > 0 : count == 0;
                }
                else passed = value?.Type == JTokenType.Boolean ? value.Value<bool>() : null;
                string title = state == "finished" ? "历史已完成" : state == "notFinished" ? "历史未完成" : state == "active" ? "进行中" : state == "deliverable" ? "已达成交付条件" : "可接取";
                return Result(passed, label == "" ? "任务 " + factKey + "：" + title : label,
                    passed == null ? "缺少该任务的权威事实" : "事实来自任务服务；不由链序号推断");
            }
            Keys(node, "type", "label", "key", "value");
            Need(node["value"]?.Type == JTokenType.Boolean, "世界事实条件须明确选择是/否。");
            JToken flag = facts?["flags"]?[factKey];
            return Result(flag?.Type == JTokenType.Boolean ? flag.Value<bool>() == node.Value<bool>("value") : null,
                label == "" ? factKey : label, flag?.Type == JTokenType.Boolean ? "要求 " + (node.Value<bool>("value") ? "是" : "否") : "缺少该世界事实");
        }

        private static JObject Result(bool? value, string label, string detail) => new JObject {
            ["state"] = value == null ? "unknown" : value.Value ? "passed" : "failed",
            ["passed"] = value == true, ["label"] = label, ["detail"] = detail };
        private static double? NumericFact(JToken value)
        {
            if (value == null || (value.Type != JTokenType.Integer && value.Type != JTokenType.Float)) return null;
            double number = value.Value<double>();
            return double.IsFinite(number) && number >= 0 && number <= 9007199254740991 && Math.Floor(number) == number ? number : null;
        }
        public static long Integer(JToken value, string name)
        {
            Need(value?.Type == JTokenType.Integer && NumericFact(value) != null, name + "必须是非负安全整数。");
            return value.Value<long>();
        }
        public static string Text(JObject value, string name, int max)
        {
            Need(value?[name]?.Type == JTokenType.String, "缺少文字字段：" + name);
            string text = (string)value[name];
            Need(text.Length > 0 && text.Length <= max && !text.Any(char.IsControl), "文字字段为空、过长或含控制字符：" + name);
            return text;
        }
        public static void Keys(JObject value, params string[] allowed) => Need(value.Properties().All(p => allowed.Contains(p.Name)), "对象含未知字段。");
        public static void Need(bool value, string message) { if (!value) throw new InvalidDataException(message); }
    }
}
