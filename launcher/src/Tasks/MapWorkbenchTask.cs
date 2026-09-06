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
        public MapWorkbenchTask(string root) { store = new MapAuthoringStore(root); }
        public static bool TryReadRequest(string json, string activePanel, string activeInstance, out JObject message, out JObject request)
        {
            message = null; request = null;
            try
            {
                if (json == null || json.Length > 256 * 1024 || activePanel != Panel || string.IsNullOrEmpty(activeInstance)) return false;
                var m = JObject.Parse(json, new JsonLoadSettings { DuplicatePropertyNameHandling = DuplicatePropertyNameHandling.Error });
                var keys = new[] { "type", "panel", "domain", "cmd", "callId", "panelInstanceId", "payload" };
                if (m.Count != keys.Length || m.Properties().Any(p => !keys.Contains(p.Name))) return false;
                if (keys.Where(k => k != "payload").Any(k => m[k]?.Type != JTokenType.String || ((string)m[k]).Length > 200)) return false;
                if ((string)m["type"] != "panel" || (string)m["panel"] != Panel || (string)m["domain"] != Domain || (string)m["panelInstanceId"] != activeInstance || string.IsNullOrEmpty((string)m["callId"])) return false;
                var p = m["payload"] as JObject; if (p == null) return false;
                string cmd = (string)m["cmd"];
                string[] fields = cmd == "read" || cmd == "close" ? Array.Empty<string>() : cmd == "preview" ? new[] { "expectedDigest", "changes" } :
                    cmd == "apply" ? new[] { "expectedDigest", "changes", "operationId" } : cmd == "undo" || cmd == "query" ? new[] { "operationId" } : null;
                if (fields == null || p.Count != fields.Length || p.Properties().Any(x => !fields.Contains(x.Name))) return false;
                if (fields.Contains("changes") && p["changes"] is not JArray) return false;
                if (fields.Where(k => k != "changes").Any(k => p[k]?.Type != JTokenType.String)) return false;
                message = m; request = (JObject)p.DeepClone(); request["op"] = cmd; return true;
            }
            catch (Exception) { return false; }
        }
        public Task<JObject> ExecuteAsync(JObject request) => Task.Run(() =>
        {
            try { return new JObject { ["success"] = true, ["data"] = store.Execute(request) }; }
            catch (Exception ex) { return new JObject { ["success"] = false, ["error"] = ex.Message }; }
        });
    }
}
