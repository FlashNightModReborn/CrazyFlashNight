using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Xml.Linq;
using Newtonsoft.Json.Linq;
using static CF7Launcher.Data.MapRuleEvaluator;

namespace CF7Launcher.Data
{
    /// <summary>The runtime StageInfo lists own entry rules. The Web map only supplies display names.</summary>
    internal sealed class StageAdmissionCatalog
    {
        internal static readonly string[] ExecutionFields = { "Type", "Name", "FadeTransitionFrame", "RootFadeTransitionFrame",
            "Address", "StartFrame", "EndFrame", "Limitation", "LimitLevel", "UnlockCondition", "AltUnlockCondition", "UnlockRule" };
        internal readonly JObject Execution = new JObject();
        private readonly JObject rules = new JObject();
        private readonly HashSet<string> unavailable = new HashSet<string>(StringComparer.Ordinal);
        internal string Digest { get; private set; }

        internal static StageAdmissionCatalog Load(string root, MapTaskCatalog tasks)
        {
            var catalog = new StageAdmissionCatalog();
            var sources = new JObject();
            XElement Read(string file)
            {
                byte[] bytes = MapProjectFiles.Read(root, file);
                sources[file] = MapDefinition.Hash(bytes);
                return MapProjectFiles.Xml(bytes).Root ?? throw new InvalidDataException("空的关卡目录：" + file);
            }
            var folders = Read("data/stages/list.xml").Elements("stages").Select(e => e.Value.Trim()).ToList();
            Need(folders.Count is > 0 and <= 256, "关卡目录列表为空或过大。");
            foreach (string folder in folders.Distinct(StringComparer.Ordinal))
            {
                FileComponent(folder);
                string prefix = "data/stages/" + folder + "/";
                XElement list = Read(prefix + "__list__.xml");
                foreach (var stage in list.Elements("StageInfo"))
                {
                    string name = (string)stage.Element("Name"), type = (string)stage.Element("Type");
                    FileComponent(name);
                    Need(catalog.Execution[name] == null && catalog.Execution.Count < 4096, "关卡重复或过多：" + name);
                    Need(type == "初期关卡" || type == "无限过图" || type == "外交地图", "未知关卡类型：" + name);
                    var projection = new JObject { ["url"] = prefix + name + ".xml" };
                    foreach (string key in ExecutionFields)
                    {
                        var values = stage.Elements(key).Select(FlashXmlValue).ToList();
                        if (values.Count == 0) continue;
                        Need(values.Count == 1 || key == "Limitation" || key == "AltUnlockCondition", "关卡字段重复：" + name + "/" + key);
                        projection[key] = values.Count == 1 ? values[0] : new JArray(values);
                    }
                    catalog.Execution[name] = projection;
                    if (type != "外交地图" && !File.Exists(Path.Combine(root, (string)projection["url"])))
                        catalog.unavailable.Add(name);
                    catalog.rules[name] = new JObject { ["condition"] = ParseRule(stage, name) };
                }
            }
            Need(catalog.rules.Count > 0, "未载入任何关卡。");
            var policies = Read("data/stages/entry-policies.xml");
            Need(policies.Name == "EntryPolicies" && (string)policies.Attribute("version") == "1", "无效的专用入口目录。");
            foreach (var item in policies.Elements())
            {
                Attributes(item, "kind", "id", "stage", "difficulty", "displayOnly");
                string kind = (string)item.Attribute("kind"), stage = (string)item.Attribute("stage");
                string mode = (string)item.Attribute("difficulty");
                bool display = (bool?)item.Attribute("displayOnly") == true;
                Need(item.Name == "entry" && IsSpecial(kind) && item.Elements().Count() == 1, "无效的专用入口。");
                FileComponent(stage);
                string key = RuleKey(stage, kind);
                Need(catalog.rules[key] == null && (display || (catalog.Execution[stage] != null && StageDifficulties.Contains(mode))),
                    "无效的专用入口目标：" + stage);
                int remaining = MaxNodes;
                catalog.rules[key] = new JObject { ["condition"] = CompileNode(item.Elements().Single(), 0, ref remaining),
                    ["difficulty"] = mode, ["displayOnly"] = display, ["entryId"] = (string)item.Attribute("id") };
            }
            foreach (var entry in catalog.rules.Properties())
            {
                var condition = entry.Value["condition"];
                // The shared evaluator validates all branches, including references, node budgets and cycles.
                EvaluateStage(condition, catalog.rules, null);
                foreach (var node in ((JObject)condition).DescendantsAndSelf().OfType<JObject>())
                {
                    string type = (string)node["type"], key = (string)node["key"];
                    if (type == "task") Need(tasks.Tasks[key] != null, "未知解锁任务：" + key);
                    if (type == "chain") Need(key == "主线" || tasks.Chains.Contains(key), "未知解锁任务链：" + key);
                    if (type == "stageCleared") Need(catalog.Execution[key] != null, "未知通关历史目标：" + key);
                }
            }
            catalog.Digest = MapDefinition.Hash(MapDefinition.Bytes(sources));
            return catalog;
        }

        private static void FileComponent(string value) =>
            Need(!string.IsNullOrWhiteSpace(value) && value.Length <= 100 && value != "." && value != ".."
                && value.IndexOfAny(Path.GetInvalidFileNameChars()) < 0 && !value.Contains('/') && !value.Contains('\\')
                && !value.Any(char.IsControl), "无效的关卡目录或名称。");

        private static long UInt(string raw)
        {
            string text = raw?.Trim();
            Need(!string.IsNullOrEmpty(text) && text.All(c => c >= '0' && c <= '9')
                && long.TryParse(text, NumberStyles.None, CultureInfo.InvariantCulture, out long n)
                && n <= 9007199254740991L, "关卡条件须是非负安全整数：" + raw);
            return long.Parse(text, CultureInfo.InvariantCulture);
        }

        private static JObject ParseRule(XElement stage, string name)
        {
            var modern = stage.Elements("UnlockRule").ToList();
            var main = stage.Elements("UnlockCondition").ToList();
            var alternatives = stage.Elements("AltUnlockCondition").ToList();
            Need(modern.Count <= 1 && main.Count <= 1, "重复的解锁根节点：" + name);
            if (modern.Count > 0)
            {
                Need(main.Count == 0 && alternatives.Count == 0, "mixed_unlock_fields: " + name);
                XElement rule = modern[0];
                Attributes(rule, "version");
                Need((string)rule.Attribute("version") == "1" && rule.Elements().Count() == 1, "未知版本或多根解锁规则：" + name);
                int remaining = MaxNodes;
                return CompileNode(rule.Elements().Single(), 0, ref remaining);
            }
            var paths = new JArray();
            if (main.Count != 0)
            {
                Need(!main[0].HasElements && !main[0].HasAttributes, "主线解锁字段形状错误：" + name);
                paths.Add(Chain("主线", main[0].Value));
            }
            foreach (var alt in alternatives)
            {
                Attributes(alt, "chain", "min");
                Need(!alt.HasElements && string.IsNullOrWhiteSpace(alt.Value), "替代条件含多余内容：" + name);
                paths.Add(Chain((string)alt.Attribute("chain"), (string)alt.Attribute("min")));
            }
            Need(paths.Count > 0, "缺少明确的解锁规则：" + name);
            return paths.Count == 1 ? (JObject)paths[0] : new JObject { ["type"] = "any", ["children"] = paths };
        }

        private static JObject Chain(string key, string min) =>
            new JObject { ["type"] = "chain", ["key"] = key, ["min"] = UInt(min) };

        private static void Attributes(XElement node, params string[] allowed) =>
            Need(node.Attributes().All(a => allowed.Contains(a.Name.ToString(), StringComparer.Ordinal))
                && !node.Nodes().OfType<XText>().Any(t => !string.IsNullOrWhiteSpace(t.Value)),
                "关卡规则包含未知属性或文本：" + node.Name);

        private static JObject CompileNode(XElement node, int depth, ref int remaining)
        {
            Need(depth <= MaxDepth && --remaining >= 0, "关卡规则过于复杂。");
            string tag = node.Name.ToString();
            var result = new JObject { ["type"] = tag };
            if (tag == "all" || tag == "any")
            {
                Attributes(node, "label");
                var children = node.Elements().ToList();
                Need(children.Count is > 0 and <= 32, "关卡组合条件需要 1–32 个子项。");
                var compiled = new JArray();
                foreach (var child in children) compiled.Add(CompileNode(child, depth + 1, ref remaining));
                result["children"] = compiled;
            }
            else
            {
                Need(!node.HasElements, "叶条件包含子节点。");
                switch (tag)
                {
                    case "always": Attributes(node, "label"); break;
                    case "chain":
                        Attributes(node, "key", "min", "max", "label");
                        result = Chain((string)node.Attribute("key"), (string)node.Attribute("min"));
                        if (node.Attribute("max") != null) result["max"] = UInt((string)node.Attribute("max"));
                        break;
                    case "task":
                        Attributes(node, "id", "state", "stageObjective", "label");
                        result["key"] = UInt((string)node.Attribute("id")).ToString(CultureInfo.InvariantCulture);
                        result["state"] = (string)node.Attribute("state");
                        if (node.Attribute("stageObjective") != null) result["stageObjective"] = (string)node.Attribute("stageObjective");
                        break;
                    case "stageCleared":
                        Attributes(node, "key", "difficulty", "label");
                        result["key"] = (string)node.Attribute("key"); result["difficulty"] = (string)node.Attribute("difficulty");
                        break;
                    case "rule":
                        Attributes(node, "key", "label"); result["key"] = (string)node.Attribute("key"); break;
                    default: throw new InvalidDataException("未知的关卡规则节点：" + tag);
                }
            }
            if (node.Attribute("label") != null) result["label"] = (string)node.Attribute("label");
            return result;
        }

        // Reconstruct only fields consumed by the Flash loader. Its XMLParser promotes repeated names
        // to arrays and converts numeric scalars and attributes before StageInfoLoader attaches the URL.
        private static JToken FlashXmlValue(XElement node)
        {
            if (!node.HasAttributes && !node.HasElements)
                return FlashScalar(node.Value);
            var value = new JObject();
            foreach (var attr in node.Attributes()) value[attr.Name.ToString()] = FlashScalar(attr.Value);
            foreach (var group in node.Elements().GroupBy(n => n.Name.ToString()))
            {
                var values = group.Select(FlashXmlValue).ToList();
                value[group.Key] = values.Count == 1 ? values[0] : new JArray(values);
            }
            return value;
        }

        private static JToken FlashScalar(string text)
        {
            if (double.TryParse(text, NumberStyles.Float, CultureInfo.InvariantCulture, out double n) && double.IsFinite(n))
                return n == Math.Truncate(n) && Math.Abs(n) <= 9007199254740991L ? new JValue((long)n) : new JValue(n);
            if (bool.TryParse(text, out bool flag)) return new JValue(flag);
            return new JValue(text);
        }

        internal static bool IsSpecial(string kind) => kind == "subway" || kind == "egg";
        private static string RuleKey(string name, string kind) => IsSpecial(kind) ? "@" + kind + ":" + name : name;
        internal string SpecialSelector(string kind, string name) => (string)rules[RuleKey(name,kind)]?["entryId"];
        internal bool SpecialTarget(string kind, string name, string difficulty) =>
            IsSpecial(kind) && (string)rules[RuleKey(name, kind)]?["difficulty"] == difficulty
                && (bool?)rules[RuleKey(name, kind)]?["displayOnly"] == false && !unavailable.Contains(name);
        internal bool HasTarget(string name) => Execution[name] != null && !unavailable.Contains(name);

        internal JObject Required(IEnumerable<string> names, string kind = null)
        {
            var chains = new SortedSet<string>(StringComparer.Ordinal);
            var clears = new SortedSet<string>(StringComparer.Ordinal);
            var tasks = new SortedDictionary<string, SortedSet<string>>(StringComparer.Ordinal);
            var visited = new HashSet<string>(StringComparer.Ordinal);
            void Include(string name)
            {
                if (!visited.Add(name) || rules[name] == null) return;
                foreach (var node in ((JObject)rules[name]["condition"]).DescendantsAndSelf().OfType<JObject>())
                {
                    string key = (string)node["key"];
                    switch ((string)node["type"])
                    {
                        case "chain": chains.Add(key); break;
                        case "stageCleared": clears.Add(key); break;
                        case "rule": Include(key); break;
                        case "task":
                            if (!tasks.TryGetValue(key, out var fields)) tasks[key] = fields = new SortedSet<string>(StringComparer.Ordinal);
                            string state = (string)node["state"];
                            fields.Add(state == "notFinished" ? "finished" : state);
                            if (node["stageObjective"] != null) fields.Add("objective");
                            break;
                    }
                }
            }
            foreach (string name in names) Include(RuleKey(name, kind));
            var requestedTasks = new JObject();
            foreach (var pair in tasks) requestedTasks[pair.Key] = new JArray(pair.Value);
            return new JObject { ["chains"] = new JArray(chains), ["tasks"] = requestedTasks, ["clears"] = new JArray(clears) };
        }

        internal JObject Decide(string name, JObject facts, bool force, string kind = null)
        {
            var rule = rules[RuleKey(name, kind)];
            if (rule == null || unavailable.Contains(name))
                return new JObject { ["unlocked"] = false, ["nativeUnlocked"] = false, ["reason"] = "关卡资料尚未就绪" };
            var evaluated = EvaluateStage(rule["condition"], rules, facts);
            bool native = Passed(evaluated);
            bool allowed = (native || force) && (bool?)rule["displayOnly"] != true;
            return new JObject { ["nativeUnlocked"] = native, ["unlocked"] = allowed,
                ["reason"] = allowed ? "" : (string)rule["condition"]["label"] ?? Reason(evaluated) };
        }

        private static string Reason(JObject part)
        {
            if (part["children"] is JArray children)
                return string.Join((string)part["label"] == "全部满足" ? "，并且" : "，或", children.OfType<JObject>().Select(Reason));
            if (part["min"] != null) return (string)part["label"] + "达到 " + (long)part["min"]
                + "（当前 " + (part["current"]?.Type == JTokenType.Null ? "未知" : part["current"]?.ToString()) + "）";
            return (string)part["label"];
        }
    }
}
