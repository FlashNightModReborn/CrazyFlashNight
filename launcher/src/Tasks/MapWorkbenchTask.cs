using System;
using System.Linq;
using System.Threading.Tasks;
using CF7Launcher.Data;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Tasks
{
    public sealed class MapWorkbenchTask
    {
        public const string Panel = "map-workbench", Domain = "map_workbench";
        private readonly MapAuthoringStore store;
        private readonly MapRuntimeContent content;
        private readonly MapDomainTask domain;
        public MapWorkbenchTask(string root, MapRuntimeContent content = null, MapDomainTask domain = null) { store = new MapAuthoringStore(root); this.content = content; this.domain = domain; }
        public static bool TryReadRequest(string json, string activePanel, string activeInstance, out JObject message, out JObject request)
        {
            message = null; request = null;
            try
            {
                if (json == null || json.Length > 256 * 1024 || activePanel != Panel || string.IsNullOrEmpty(activeInstance)) return false;
                var m = MapProjectFiles.Json(MapDefinition.Utf8.GetBytes(json));
                var keys = new[] { "type", "panel", "domain", "cmd", "callId", "panelInstanceId", "payload" };
                if (m.Count != keys.Length || m.Properties().Any(p => !keys.Contains(p.Name))) return false;
                if (keys.Where(k => k != "payload").Any(k => m[k]?.Type != JTokenType.String || ((string)m[k]).Length > 200)) return false;
                if ((string)m["type"] != "panel" || (string)m["panel"] != Panel || (string)m["domain"] != Domain || (string)m["panelInstanceId"] != activeInstance || string.IsNullOrEmpty((string)m["callId"])) return false;
                var p = m["payload"] as JObject; if (p == null) return false;
                string cmd = (string)m["cmd"];
                string[] fields = cmd == "read" || cmd == "close" || cmd == "catalog" || cmd == "asset-pick" ? Array.Empty<string>() : cmd == "facts" ? new[] { "taskIds" } :
                    cmd == "asset-inspect" ? new[] { "assetUrl" } : cmd == "open-source" ? new[] { "kind", "id" } : cmd == "asset-crop" ? new[] { "assetUrl", "sourceDigest", "crop" } : cmd == "asset-extract" ? new[] { "sourceSwf", "sourceDigest", "linkage", "frame", "zoom" } :
                    cmd == "preview" ? new[] { "expectedDigest", "changes", "expectedTaskDigest", "facts", "compareFacts" } :
                    cmd == "apply" ? new[] { "expectedDigest", "changes", "operationId", "expectedTaskDigest" } : cmd == "undo" || cmd == "query" || cmd == "recover" ? new[] { "operationId" } : null;
                if (fields == null || p.Properties().Any(x => !fields.Contains(x.Name))) return false;
                foreach (string field in fields)
                {
                    // v1 旧请求和无模拟事实的预览仍可用；v2 磁盘写入的 task 摘要由同一内核硬校验。
                    if (p[field] == null && (field == "expectedTaskDigest" || field == "facts" || field == "compareFacts")) continue;
                    if (field == "changes" || field == "taskIds") { if (p[field] is not JArray) return false; }
                    else if (field == "facts" || field == "compareFacts" || field == "crop") { if (p[field] is not JObject) return false; }
                    else if (field == "frame" || field == "zoom") { if (p[field]?.Type != JTokenType.Integer && p[field]?.Type != JTokenType.Float) return false; }
                    else if (p[field]?.Type != JTokenType.String) return false;
                }
                message = m; request = (JObject)p.DeepClone(); request["op"] = cmd; return true;
            }
            catch (Exception) { return false; }
        }
        public Task<JObject> StageFileAsync(string source) => Task.Run(() =>
        {
            try { return new JObject { ["success"] = true, ["data"] = store.StageFile(source) }; }
            catch (Exception ex) { return new JObject { ["success"] = false, ["error"] = ex.Message }; }
        });
        public async Task<JObject> ExecuteAsync(JObject request)
        {
            try
            {
                JObject result;
                if ((string)request["op"] == "facts")
                {
                    if (domain == null) throw new InvalidOperationException("离线工作台没有游戏实时事实，请使用独立模拟方案。");
                    result = new JObject { ["facts"] = await domain.CaptureAsync((JArray)request["taskIds"]).ConfigureAwait(false), ["capturedAtUtc"] = DateTime.UtcNow.ToString("O") };
                }
                else result = await Task.Run(() => store.Execute(request)).ConfigureAwait(false);
                if (content != null) result["runtime"] = new JObject { ["definitionDigest"] = content.DefinitionDigest, ["contentDigest"] = content.ContentDigest, ["taskDigest"] = content.Catalog.Digest };
                return new JObject { ["success"] = true, ["data"] = result };
            }
            catch (Exception ex) { return new JObject { ["success"] = false, ["error"] = ex.Message }; }
        }
    }
}
