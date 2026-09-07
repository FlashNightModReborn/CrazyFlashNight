using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.Bus;
using CF7Launcher.Data;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Tasks
{
    /// <summary>socket-only 地图事实入口。Web/HTTP 不能向此域投喂运行态事实。</summary>
    public sealed class MapDomainTask : IDisposable
    {
        private readonly MapRuntimeContent content;
        private readonly XmlSocketServer socket;
        private readonly CF7Launcher.Guardian.Hud.MapHudDataCatalog hudCatalog;
        private readonly object gate = new object();
        private int generation = -1;
        private string token = "", factsDigest = "";
        private long revision = -1, sceneEpoch = -1;
        private JObject lastFacts;
        private readonly Dictionary<string, TaskCompletionSource<JObject>> captures = new Dictionary<string, TaskCompletionSource<JObject>>(StringComparer.Ordinal);
        private bool disposed;
        public MapDomainTask(XmlSocketServer socket, MapRuntimeContent content, CF7Launcher.Guardian.Hud.MapHudDataCatalog hudCatalog = null)
        {
            this.socket = socket; this.content = content; this.hudCatalog = hudCatalog;
            if (socket != null) socket.OnClientDisconnectedForGeneration += Disconnected;
        }
        internal MapDomainTask(MapRuntimeContent content) : this(null, content) { }
        private void Disconnected(int expected)
        {
            lock (gate) if (generation == expected) Reset(-1);
        }
        private void Reset(int next)
        {
            generation = next; token = next < 0 ? "" : Guid.NewGuid().ToString("N"); revision = -1; sceneEpoch = -1; factsDigest = ""; lastFacts = null;
            hudCatalog?.ReplacePayload(null);
            foreach (var waiter in captures.Values) waiter.TrySetException(new InvalidOperationException("地图事实连接已变化。")); captures.Clear();
        }
        public void HandleAsync(JObject message, Action<string> respond)
        {
            int expected = socket.CurrentGeneration;
            ThreadPool.QueueUserWorkItem(_ =>
            {
                JObject response;
                try
                {
                    var payload = message["payload"] as JObject;
                    response = Process(payload, expected, () => socket.TryGetReadyGeneration(out int current) && current == expected,
                        action => socket.RunWithConnectionTransitionFence(action));
                }
                catch (Exception e) { response = Failure(e.Message); }
                respond(response.ToString(Formatting.None));
            });
        }
        internal JObject Process(JObject payload, int expected, Func<bool> ready, Func<Func<bool>, bool> fence = null)
        {
            try
            {
                MapRuleEvaluator.Need(payload != null && payload["version"]?.Type == JTokenType.Integer && payload.Value<int>("version") == 2, "地图事实协议版本不正确。");
                string op = payload.Value<string>("op");
                if (op == "hello")
                {
                    MapRuleEvaluator.Keys(payload, "version", "op"); JObject hello = null;
                    bool Hello()
                    {
                        lock (gate)
                        {
                            if (disposed || !ready()) return false;
                            if (generation != expected) Reset(expected);
                            hello = (JObject)content.Bootstrap.DeepClone(); hello["sessionToken"] = token; return true;
                        }
                    }
                    MapRuleEvaluator.Need(fence == null ? Hello() : fence(Hello), "地图事实连接尚未就绪。");
                    return Success(hello);
                }
                MapRuleEvaluator.Need(op == "project", "地图事实入口不支持该操作。");
                MapRuleEvaluator.Keys(payload, "version", "op", "sessionToken", "contentDigest", "revision", "sceneEpoch", "ready", "facts", "interestTaskIds", "captureIds", "intent");
                long nextRevision = MapRuleEvaluator.Integer(payload["revision"], "事实版本"), nextScene = MapRuleEvaluator.Integer(payload["sceneEpoch"], "场景版本");
                MapRuleEvaluator.Need(payload["ready"]?.Type == JTokenType.Boolean, "缺少事实就绪状态。");
                var interests = content.ValidateTaskIds(payload["interestTaskIds"]);
                MapRuleEvaluator.Need(payload["captureIds"] is JArray captureIds && captureIds.Count <= 8 && captureIds.All(x => x.Type == JTokenType.String && System.Text.RegularExpressions.Regex.IsMatch((string)x, @"\A[a-f0-9]{32}\z")) && captureIds.Select(x => (string)x).Distinct().Count() == captureIds.Count, "事实采样回执不正确。");
                JObject facts = content.NormalizeFacts(payload["facts"] as JObject);
                MapRuleEvaluator.Need(payload["intent"] == null || payload["intent"].Type == JTokenType.Null || payload["intent"] is JObject, "地图意图必须是对象。");
                string digest = MapDefinition.Hash(MapDefinition.Bytes(new JObject { ["ready"] = payload["ready"], ["sceneEpoch"] = nextScene, ["facts"] = facts }));
                JObject projected = payload.Value<bool>("ready") ? content.Project(facts) : null;
                var hud = projected == null || hudCatalog == null ? null : MapDefinition.Hud(content.Definition, (JObject)projected["snapshot"]).ToObject<CF7Launcher.Guardian.Hud.MapHudPayload>();
                JObject admission = projected != null && payload["intent"] is JObject intent ? Admit(intent, projected, facts) : null;
                JObject response = null;
                bool Install()
                {
                    lock (gate)
                    {
                        if (disposed || !ready() || generation != expected || (string)payload["sessionToken"] != token || (string)payload["contentDigest"] != content.ContentDigest)
                        { response = Failure("invalid_session"); return true; }
                        if (nextRevision < revision || nextScene < sceneEpoch || (nextRevision == revision && digest != factsDigest))
                        { response = Failure("stale_facts"); return true; }
                        revision = nextRevision; sceneEpoch = nextScene; factsDigest = digest;
                        hudCatalog?.ReplacePayload(hud);
                        if (projected == null)
                        {
                            lastFacts = null; response = Failure("game_not_ready");
                            foreach (string id in ((JArray)payload["captureIds"]).Select(x => (string)x))
                                if (captures.Remove(id, out var capture)) capture.TrySetException(new InvalidOperationException("尚未进入可读取地图事实的游戏场景。"));
                            return true;
                        }
                        lastFacts = (JObject)facts.DeepClone();
                        response = Success(new JObject { ["version"] = 2, ["sessionToken"] = token, ["contentDigest"] = content.ContentDigest,
                            ["definitionDigest"] = content.DefinitionDigest, ["revision"] = revision, ["sceneEpoch"] = sceneEpoch, ["projection"] = content.ForAs2(projected, facts, interests), ["admission"] = admission });
                        foreach (string id in ((JArray)payload["captureIds"]).Select(x => (string)x))
                            if (captures.TryGetValue(id, out var capture)) { captures.Remove(id); capture.TrySetResult((JObject)lastFacts.DeepClone()); }
                        return true;
                    }
                }
                MapRuleEvaluator.Need(fence == null ? Install() : fence(Install), "地图事实连接已变化。");
                return response;
            }
            catch (Exception e) { return Failure(e.Message); }
        }
        private JObject Admit(JObject intent, JObject projected, JObject facts)
        {
            string kind = intent.Value<string>("kind"), hotspot = "";
            if (kind == "navigate")
            {
                MapRuleEvaluator.Keys(intent, "kind", "targetId"); hotspot = MapRuleEvaluator.Text(intent, "targetId", 100);
                if (projected["snapshot"]["hotspotStates"][hotspot] == null)
                {
                    string location = MapEndpointResolver.FindLocation(content.Definition, hotspot);
                    hotspot = ((JObject)projected["snapshot"]["hotspotStates"]).Properties().FirstOrDefault(p => (string)p.Value["locationId"] == location && p.Value.Value<bool>("visible"))?.Name ?? "";
                }
            }
            else if (kind == "task_finish")
            {
                MapRuleEvaluator.Keys(intent, "kind", "taskId"); string id = MapRuleEvaluator.Text(intent, "taskId", 100);
                if (facts["tasks"]?[id]?.Value<bool?>("active") != true) return new JObject { ["admitted"] = false, ["error"] = "task_not_active" };
                var endpoint = projected["taskEndpoints"]?[id]?["finish"] as JObject;
                if (endpoint?.Value<bool>("navigable") != true) return new JObject { ["admitted"] = false, ["error"] = endpoint?.Value<string>("reason") ?? "task_target_unavailable" };
                hotspot = (string)endpoint["hotspotId"];
            }
            else
            {
                MapRuleEvaluator.Keys(intent, "kind"); MapRuleEvaluator.Need(kind == "deliverable", "不支持的地图准入意图。");
                if (projected["delivery"].Value<bool>("navigable")) hotspot = (string)projected["delivery"]["hotspotId"];
            }
            var state = projected["snapshot"]["hotspotStates"][hotspot] as JObject;
            if (state?.Value<bool>("enabled") != true || facts["navigation"].Value<string>("reason") != "")
                return new JObject { ["admitted"] = false, ["error"] = state?.Value<string>("lockedReason") ?? "not_navigable" };
            string locationId = (string)state["locationId"];
            return new JObject { ["admitted"] = true, ["hotspotId"] = hotspot, ["locationId"] = locationId, ["frame"] = content.Definition["locations"][locationId]["sceneName"] };
        }
        public async Task<JObject> CaptureAsync(JArray taskIds)
        {
            var ids = content.ValidateTaskIds(taskIds); string captureId = Guid.NewGuid().ToString("N");
            var source = new TaskCompletionSource<JObject>(TaskCreationOptions.RunContinuationsAsynchronously);
            int expected = -1; JObject command = null;
            bool registered = socket.RunWithConnectionTransitionFence(() =>
            {
                lock (gate)
                {
                    if (disposed || token == "" || !socket.TryGetReadyGeneration(out expected) || generation != expected || captures.Count >= 8) return false;
                    captures[captureId] = source;
                    command = new JObject { ["task"] = "cmd", ["action"] = "mapDomainCollect", ["sessionToken"] = token,
                        ["contentDigest"] = content.ContentDigest, ["captureId"] = captureId, ["interestTaskIds"] = ids };
                    return true;
                }
            });
            if (!registered) throw new InvalidOperationException("尚未进入可读取地图事实的游戏会话。");
            try
            {
                if (!socket.TrySendIfGen(command.ToString(Formatting.None) + "\0", expected)) throw new InvalidOperationException("地图事实连接已变化。");
                return await source.Task.WaitAsync(TimeSpan.FromSeconds(4)).ConfigureAwait(false);
            }
            finally { lock (gate) captures.Remove(captureId); }
        }
        private static JObject Success(JObject value) => new JObject { ["success"] = true, ["task"] = "map_domain", ["result"] = value };
        private static JObject Failure(string error) => new JObject { ["success"] = false, ["task"] = "map_domain", ["error"] = error };
        public void Dispose()
        {
            if (socket != null) socket.OnClientDisconnectedForGeneration -= Disconnected;
            lock (gate) { disposed = true; Reset(-1); }
        }
    }
}
