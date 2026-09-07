using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Data
{
    /// <summary>可恢复的多文件应用；文件替换是原子的，整个批次不是文件系统原子事务。</summary>
    public sealed class MapChangeJournal
    {
        public const string Schema = "map-workbench-change.v2", History = "tmp/map-workbench/changes/";
        private const int ByteBudget = 32 * 1024 * 1024;
        private readonly string root;
        public MapChangeJournal(string root) { this.root = root; }
        public static void ValidateId(string id) => MapRuleEvaluator.Need(id != null && Regex.IsMatch(id, @"\A[a-f0-9]{32}\z"), "操作编号不合法。");
        public string PathFor(string id) { ValidateId(id); return MapProjectFiles.Resolve(root, History + id + ".json"); }
        private string PendingPath(string id) { ValidateId(id); return MapProjectFiles.Resolve(root, "tmp/map-workbench/pending/" + id + ".json"); }
        private void MarkPending(JObject record) => MapProjectFiles.Atomic(PendingPath((string)record["operationId"]), MapDefinition.Bytes(new JObject { ["operationId"] = record["operationId"], ["binding"] = record["binding"] }));
        private void ClearPending(JObject record)
        {
            string path = PendingPath((string)record["operationId"]); if (!File.Exists(path)) return;
            var marker = MapProjectFiles.Json(File.ReadAllBytes(path));
            MapRuleEvaluator.Need((string)marker["operationId"] == (string)record["operationId"] && (string)marker["binding"] == (string)record["binding"], "未完成批次标记被替换，已拒绝清理。");
            File.Delete(path);
        }
        public JObject Metadata(string id)
        {
            using var stream = new StreamReader(PathFor(id), MapDefinition.Utf8);
            using var reader = new JsonTextReader(stream) { DateParseHandling = DateParseHandling.None, MaxDepth = 48 };
            var result = new JObject();
            while (reader.Read())
            {
                if (reader.TokenType != JsonToken.PropertyName || reader.Depth != 1) continue;
                string key = (string)reader.Value;
                if (key == "files" || key == "beforeBytes") break;
                if (!reader.Read()) break;
                if (new[] { "operationId", "afterDigest", "createdAt", "phase", "schema", "changeCount" }.Contains(key)) result[key] = JToken.ReadFrom(reader);
                else reader.Skip();
            }
            result["operationId"] = id; return result;
        }
        public JObject Read(string id)
        {
            string path = PathFor(id); if (!File.Exists(path)) return null;
            var value = MapProjectFiles.Json(MapProjectFiles.Read(root, History + id + ".json", 96 * 1024 * 1024));
            MapRuleEvaluator.Need((string)value["operationId"] == id, "操作回执身份不匹配。");
            if ((string)value["schema"] == Schema) Validate(value);
            return value;
        }
        private bool Allowed(string relative)
        {
            if (relative == MapDefinition.RelativePath) return true;
            if (Regex.IsMatch(relative, @"\Alauncher/web/assets/map/imported/[a-f0-9]{64}\.webp\z")) return true;
            if (!relative.StartsWith("data/task/", StringComparison.Ordinal) || relative.StartsWith("data/task/text/", StringComparison.Ordinal)) return false;
            var list = MapProjectFiles.Xml(MapProjectFiles.Read(root, "data/task/list.xml"));
            return list.Root.Elements("task").Any(e => relative == "data/task/" + e.Value.Trim());
        }
        private void Validate(JObject record)
        {
            MapRuleEvaluator.Need(record["files"] is JArray files && files.Count is > 0 and <= 128, "批次文件清单不正确。");
            var paths = new HashSet<string>(StringComparer.OrdinalIgnoreCase); long bytes = 0;
            foreach (JObject file in (JArray)record["files"])
            {
                string path = MapRuleEvaluator.Text(file, "path", 240);
                MapRuleEvaluator.Need(Allowed(path) && paths.Add(path), "批次包含未授权或重复的文件路径。");
                MapProjectFiles.Resolve(root, path);
                foreach (string side in new[] { "before", "after" })
                {
                    byte[] body = Body(file, side); string digest = (string)file[side + "Digest"];
                    MapRuleEvaluator.Need(body == null ? digest == "" : MapDefinition.Hash(body) == digest, "批次备份摘要不匹配。");
                    if (body != null) bytes += body.Length;
                }
                if (path.StartsWith("data/task/", StringComparison.Ordinal))
                {
                    MapRuleEvaluator.Need(Body(file, "before") != null && Body(file, "after") != null, "地图工具不能创建或删除任务源文件。");
                    MapTaskSourcePatch.ValidateOnlyEndpointsChanged(Body(file, "before"), Body(file, "after"));
                }
            }
            MapRuleEvaluator.Need(bytes <= ByteBudget, "批次备份超过 32 MiB，请分批应用。");
        }
        public static byte[] Body(JObject file, string side) => file[side + "Bytes"]?.Type == JTokenType.String ? Convert.FromBase64String((string)file[side + "Bytes"]) : null;
        public static JObject FileChange(string relative, byte[] before, byte[] after) => new JObject { ["path"] = relative,
            ["beforeDigest"] = before == null ? "" : MapDefinition.Hash(before), ["afterDigest"] = after == null ? "" : MapDefinition.Hash(after),
            ["beforeBytes"] = before == null ? JValue.CreateNull() : new JValue(Convert.ToBase64String(before)),
            ["afterBytes"] = after == null ? JValue.CreateNull() : new JValue(Convert.ToBase64String(after)) };
        private string Current(string relative)
        {
            string file = MapProjectFiles.Resolve(root, relative);
            return File.Exists(file) ? MapDefinition.Hash(MapProjectFiles.Read(root, relative, ByteBudget)) : "";
        }
        public JObject State(JObject record)
        {
            var states = new JArray(); bool anyBefore = false, anyAfter = false, foreign = false;
            foreach (JObject file in (JArray)record["files"])
            {
                string digest = Current((string)file["path"]), before = (string)file["beforeDigest"], after = (string)file["afterDigest"];
                string state = digest == before && digest == after ? "unchanged" : digest == after ? "applied" : digest == before ? "original" : "foreign";
                anyBefore |= state == "original"; anyAfter |= state == "applied"; foreign |= state == "foreign";
                states.Add(new JObject { ["path"] = file["path"], ["state"] = state, ["currentDigest"] = digest });
            }
            bool unfinished = (string)record["phase"] == "prepared" || (string)record["phase"] == "undoing";
            string status = foreign ? unfinished ? "recovery_required" : "superseded" : anyAfter && anyBefore ? unfinished ? "partial" : "superseded" : anyBefore ? "original" : "applied";
            return new JObject { ["state"] = status, ["files"] = states, ["operationId"] = record["operationId"], ["phase"] = record["phase"] };
        }
        private void Save(JObject record) => MapProjectFiles.Atomic(PathFor((string)record["operationId"]), MapDefinition.Bytes(record));
        public JObject Prepare(string id, string binding, string beforeDigest, string afterDigest, JArray changes, JArray files)
        {
            MapRuleEvaluator.Need(!File.Exists(PathFor(id)), "操作回执已存在。");
            var record = new JObject { ["schema"] = Schema, ["operationId"] = id, ["binding"] = binding, ["beforeDigest"] = beforeDigest,
                ["afterDigest"] = afterDigest, ["createdAt"] = DateTime.UtcNow.ToString("O"), ["changeCount"] = changes.Count, ["phase"] = "prepared", ["changes"] = changes.DeepClone(), ["files"] = files };
            Validate(record);
            foreach (JObject file in files) MapRuleEvaluator.Need(Current((string)file["path"]) == (string)file["beforeDigest"], "保存前项目文件已变化，请重新读取。");
            Save(record); MarkPending(record); return record;
        }
        private void WriteSide(JObject record, string from, string to)
        {
            var files = ((JArray)record["files"]).OfType<JObject>();
            if (to == "before") files = files.Reverse();
            foreach (var file in files)
            {
                string relative = (string)file["path"], actual = Current(relative), expected = (string)file[from + "Digest"], next = (string)file[to + "Digest"];
                if (actual == next) continue;
                MapRuleEvaluator.Need(actual == expected, "文件已有后续修改，不能覆盖：" + relative);
                string path = MapProjectFiles.Resolve(root, relative); byte[] bytes = Body(file, to);
                if (bytes == null) { MapProjectFiles.PlainPath(path); File.Delete(path); }
                else MapProjectFiles.Atomic(path, bytes);
                MapRuleEvaluator.Need(Current(relative) == next, "写后回读不一致：" + relative);
            }
        }
        public void Commit(JObject record)
        {
            try
            {
                WriteSide(record, "before", "after"); record["phase"] = "applied"; Save(record);
            }
            catch (Exception original)
            {
                // 只恢复仍匹配本批前/后像的文件；外部修改无法安全恢复时保留未完成回执并阻止启动。
                try
                {
                    if ((string)State(record)["state"] != "recovery_required")
                    {
                        record["phase"] = "undoing"; Save(record); MarkPending(record); WriteSide(record, "after", "before"); record["phase"] = "original"; Save(record); ClearPending(record);
                    }
                }
                catch (Exception recovery) { throw new IOException("地图保存失败，自动恢复也未完成；请查询本次操作。", new AggregateException(original, recovery)); }
                throw;
            }
            // 已持久记录 applied 后，清理标记失败只能触发结果查询；不能倒转已经完成的批次。
            ClearPending(record);
        }
        public void Undo(JObject record)
        {
            string state = (string)State(record)["state"];
            if (state == "original") return;
            MapRuleEvaluator.Need(state == "applied", "批次已被后续修改影响，不能整批撤回。");
            record["phase"] = "undoing"; Save(record); MarkPending(record); WriteSide(record, "after", "before"); record["phase"] = "original"; Save(record); ClearPending(record);
        }
        public void Recover(JObject record)
        {
            string state = (string)State(record)["state"], phase = (string)record["phase"];
            if (phase != "prepared" && phase != "undoing") { ClearPending(record); return; }
            MapRuleEvaluator.Need(state != "recovery_required", "未完成地图批次中有外部修改，请先检查操作 " + (string)record["operationId"]);
            if (state == "applied" && phase == "prepared") record["phase"] = "applied";
            else { WriteSide(record, "after", "before"); record["phase"] = "original"; }
            Save(record); ClearPending(record);
        }
        public void RecoverPending()
        {
            string directory = MapProjectFiles.Resolve(root, "tmp/map-workbench/pending");
            if (!Directory.Exists(directory)) return;
            foreach (string file in Directory.EnumerateFiles(directory, "*.json").OrderBy(File.GetLastWriteTimeUtc))
            {
                string id = Path.GetFileNameWithoutExtension(file); var record = Read(id);
                MapRuleEvaluator.Need((string)record?["schema"] == Schema, "未完成标记缺少可验证的地图批次。"); Recover(record);
            }
        }
    }
}
