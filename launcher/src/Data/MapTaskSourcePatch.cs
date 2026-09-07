using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Data
{
    /// <summary>仅替换原任务 JSON 中被编辑的任务对象；其他任务、文件换行和 BOM 原字节保留。</summary>
    public static class MapTaskSourcePatch
    {
        public static (JObject Tasks, Dictionary<string, byte[]> Files) Apply(MapTaskCatalog catalog, JArray changes, JObject definition)
        {
            var tasks = (JObject)catalog.Tasks.DeepClone(); var changed = new HashSet<string>(StringComparer.Ordinal);
            foreach (JObject change in changes)
            {
                MapRuleEvaluator.Keys(change, "kind", "id", "values", "action", "pageId");
                MapRuleEvaluator.Need((string)change["kind"] == "task" && ((string)change["action"] ?? "edit") == "edit", "任务仅支持编辑接取/交付端点。");
                string id = MapRuleEvaluator.Text(change, "id", 100); var task = tasks[id] as JObject;
                MapRuleEvaluator.Need(task != null && change["values"] is JObject, "任务不存在或端点字段缺失。");
                var values = (JObject)change["values"]; MapRuleEvaluator.Keys(values, "get_endpoint", "finish_endpoint");
                foreach (var property in values.Properties())
                {
                    MapRuleEvaluator.Need(property.Value is JObject, "端点不能清空；请选择明确的固定驻点或跟随模式。");
                    MapEndpointResolver.Validate(definition, (JObject)property.Value);
                    string role = property.Name == "get_endpoint" ? "get" : "finish";
                    task[role + "_endpoint"] = property.Value.DeepClone(); task.Remove(role + "_npc"); task.Remove(role + "_npc_hotspot");
                }
                changed.Add(id);
            }
            var files = new Dictionary<string, byte[]>(StringComparer.Ordinal);
            foreach (var group in changed.GroupBy(id => catalog.TaskFiles[id]))
                files[group.Key] = ReplaceObjects(catalog.SourceBytes[group.Key], group.ToDictionary(id => id, id => (JObject)tasks[id], StringComparer.Ordinal));
            return (tasks, files);
        }
        private sealed class Range { public int Start, End; public string Id; }
        private static byte[] ReplaceObjects(byte[] original, Dictionary<string, JObject> replacements)
        {
            int bom = original.Length >= 3 && original[0] == 239 && original[1] == 187 && original[2] == 191 ? 3 : 0;
            var reader = new Utf8JsonReader(original.AsSpan(bom), new JsonReaderOptions { MaxDepth = 48 });
            var ranges = new List<Range>(); Range current = null; bool tasksProperty = false, inTasks = false;
            while (reader.Read())
            {
                if (reader.TokenType == JsonTokenType.PropertyName && reader.CurrentDepth == 1) tasksProperty = reader.GetString() == "tasks";
                else if (reader.TokenType == JsonTokenType.StartArray && reader.CurrentDepth == 1 && tasksProperty) inTasks = true;
                else if (reader.TokenType == JsonTokenType.EndArray && reader.CurrentDepth == 1) inTasks = false;
                if (!inTasks) continue;
                if (reader.TokenType == JsonTokenType.StartObject && reader.CurrentDepth == 2) current = new Range { Start = checked((int)reader.TokenStartIndex + bom) };
                else if (reader.TokenType == JsonTokenType.PropertyName && reader.CurrentDepth == 3 && reader.GetString() == "id")
                {
                    MapRuleEvaluator.Need(reader.Read() && reader.TokenType == JsonTokenType.Number && reader.TryGetInt64(out long _), "任务源 ID 不是整数。");
                    current.Id = reader.GetInt64().ToString(System.Globalization.CultureInfo.InvariantCulture);
                }
                else if (reader.TokenType == JsonTokenType.EndObject && reader.CurrentDepth == 2)
                {
                    current.End = checked((int)reader.BytesConsumed + bom);
                    if (replacements.ContainsKey(current.Id)) ranges.Add(current);
                    current = null;
                }
            }
            MapRuleEvaluator.Need(ranges.Count == replacements.Count, "无法唯一定位原任务对象。");
            string originalText = MapDefinition.Utf8.GetString(original); string newline = originalText.Contains("\r\n", StringComparison.Ordinal) ? "\r\n" : "\n";
            using var output = new MemoryStream(); int start = 0;
            foreach (var range in ranges.OrderBy(r => r.Start))
            {
                output.Write(original.AsSpan(start, range.Start - start));
                int line = range.Start - 1; while (line >= 0 && original[line] != 10 && original[line] != 13) line--;
                string indent = MapDefinition.Utf8.GetString(original, line + 1, range.Start - line - 1);
                if (indent.Any(c => c != ' ' && c != '\t')) indent = "";
                using var writerText = new StringWriter { NewLine = newline };
                using (var writer = new JsonTextWriter(writerText) { Formatting = Formatting.Indented, Indentation = 4, CloseOutput = false }) replacements[range.Id].WriteTo(writer);
                string replacement = writerText.ToString().Replace(newline, newline + indent, StringComparison.Ordinal);
                output.Write(MapDefinition.Utf8.GetBytes(replacement)); start = range.End;
            }
            output.Write(original.AsSpan(start)); return output.ToArray();
        }
        public static void ValidateOnlyEndpointsChanged(byte[] before, byte[] after)
        {
            var left = MapProjectFiles.Json(before); var right = MapProjectFiles.Json(after);
            foreach (var document in new[] { left, right }) foreach (JObject task in (JArray)document["tasks"])
                foreach (string role in new[] { "get", "finish" }) foreach (string suffix in new[] { "_npc", "_npc_hotspot", "_endpoint" }) task.Remove(role + suffix);
            MapRuleEvaluator.Need(JToken.DeepEquals(left, right), "任务补丁改变了端点之外的内容，已拒绝。");
        }
    }
}
