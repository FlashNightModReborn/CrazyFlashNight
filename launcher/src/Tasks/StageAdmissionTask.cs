using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using CF7Launcher.Bus;
using CF7Launcher.Data;
using CF7Launcher.Guardian;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using static CF7Launcher.Data.MapRuleEvaluator;

namespace CF7Launcher.Tasks
{
    /// <summary>Flash socket request/response domain. The panel command route cannot supply facts or grants.</summary>
    internal delegate bool StageOwner(string owner, string intent, string[] names, string kind, string difficulty, string digest, JObject selector);

    public sealed class StageAdmissionTask
    {
        private sealed class Request
        {
            internal string Id, Kind, Difficulty, Slot, Owner, Intent;
            internal string[] Names;
            internal long Scene, Expires;
            internal JObject Scope;
            internal StageTaskEntryPolicy TaskEntry;
            internal JObject Selector;
            internal string State = "prepared";
            internal bool RequiresLoad, LoadConfirmed;
        }

        private readonly XmlSocketServer socket;
        private readonly StageAdmissionCatalog catalog;
        private readonly Func<MapRuntimeContent> mapContent;
        private readonly Func<long> now;
        private readonly StageOwner ownsPanel;
        private readonly Func<int,string> mapSession;
        private readonly object gate = new object();
        private readonly Dictionary<string, Request> requests = new Dictionary<string, Request>(StringComparer.Ordinal);
        private int generation = -1;
        private string binding = "", taskDigest = "", slot = "";
        private string boundSession = "";
        private long playerEpoch = -1;

        internal StageAdmissionTask(XmlSocketServer socket, string projectRoot, Func<MapRuntimeContent> mapContent,
            StageOwner ownsPanel, Func<int,string> mapSession)
        {
            this.socket = socket;
            this.mapContent = mapContent;
            this.ownsPanel = ownsPanel;
            this.mapSession = mapSession;
            now = () => Environment.TickCount64;
            try { catalog = StageAdmissionCatalog.Load(projectRoot, mapContent().Catalog); }
            catch (Exception e) { LogManager.Log("[StageAdmission] catalog unavailable: " + e.Message); }
        }

        internal StageAdmissionTask(StageAdmissionCatalog catalog, Func<MapRuntimeContent> content, Func<long> clock)
        { this.catalog = catalog; mapContent = content; now = clock; }

        internal void Handle(JObject message, Action<string> respond)
        {
            int expected = socket.CurrentGeneration;
            JObject result = null;
            // Connection transitions and grants use the same fence as the map RPC.
            bool current = socket.RunWithConnectionTransitionFence(() =>
            {
                if (!socket.TryGetReadyGeneration(out int active) || active != expected) return false;
                result = Process(message["payload"] as JObject, expected); return true;
            });
            respond((current ? result : Failure("disconnected")).ToString(Formatting.None));
        }

        internal JObject Process(JObject input, int connection)
        {
            lock (gate)
            {
                try
                {
                    Need(input != null && Integer(input["version"], "version") == 1, "unsupported_admission_version");
                    Need(catalog != null, "stage_catalog_unavailable");
                    var content = mapContent();
                    Need(content != null, "stage_catalog_unavailable");
                    string op = Text(input, "op", 16);
                    string currentSession = mapSession?.Invoke(connection);
                    if (generation != connection || taskDigest != content.ContentDigest || boundSession != (currentSession ?? ""))
                    {
                        if (generation != connection) playerEpoch = -1;
                        generation = connection; taskDigest = content.ContentDigest;
                        boundSession = currentSession ?? "";
                        binding = ""; slot = ""; requests.Clear();
                    }
                    if (op == "bind")
                    {
                        Keys(input, "version", "op", "taskDigest", "slot", "projection", "mapSession", "playerEpoch");
                        string requestedSlot = Text(input, "slot", 128);
                        long epoch = Integer(input["playerEpoch"], "playerEpoch");
                        Need(epoch >= playerEpoch && (mapSession == null || (boundSession.Length == 32 && (string)input["mapSession"] == boundSession)),
                            "admission_binding_expired");
                        Need((string)input["taskDigest"] == taskDigest && JToken.DeepEquals(input["projection"], catalog.Execution), "stage_catalog_mismatch");
                        if (binding == "" || slot != requestedSlot || epoch != playerEpoch)
                        {
                            Need(slot == "" || slot == requestedSlot || epoch > playerEpoch, "admission_binding_expired");
                            playerEpoch = epoch; slot = requestedSlot; binding = Guid.NewGuid().ToString("N"); requests.Clear();
                        }
                        return Success(new JObject { ["binding"] = binding, ["catalog"] = catalog.Digest, ["taskDigest"] = taskDigest });
                    }
                    Need(binding != "" && Text(input, "binding", 64) == binding && Text(input, "slot", 128) == slot
                        && (string)input["catalog"] == catalog.Digest && (string)input["taskDigest"] == taskDigest, "admission_binding_expired");
                    long time = now();
                    // Keep a grace period for outcome queries following a lost response.
                    foreach (string expired in requests.Where(p => p.Value.Expires + 120000 < time).Select(p => p.Key).ToArray())
                        requests.Remove(expired);
                    string id = Text(input, "operation", 160);
                    if (op == "prepare")
                    {
                        Keys(input, "version", "op", "binding", "catalog", "taskDigest", "slot", "operation", "intent", "names", "kind", "difficulty", "owner", "scene", "selector");
                        Need(!requests.ContainsKey(id) && requests.Count < 512, "admission_operation_busy");
                        string intent = Text(input, "intent", 12);
                        Need(intent == "snapshot" || intent == "enter", "invalid_admission_intent");
                        Need(input["names"] is JArray a && a.Count <= 256 && (intent == "snapshot" || a.Count == 1)
                            && a.All(n => n.Type == JTokenType.String && ((string)n).Length is > 0 and <= 100), "invalid_stage_names");
                        string[] names = ((JArray)input["names"]).Values<string>().Distinct(StringComparer.Ordinal).ToArray();
                        var row = new Request { Id = id, Intent = intent, Names = names, Kind = (string)input["kind"],
                            Difficulty = (string)input["difficulty"], Slot = slot, Owner = Text(input, "owner", 160),
                            Scene = Integer(input["scene"], "scene"), Expires = time + 15000 };
                        row.Scope = catalog.Required(names, row.Kind);
                        row.Selector = input["selector"] as JObject;
                        if (intent == "enter")
                        {
                            var stage = catalog.Execution[names[0]];
                            Need(stage != null, "invalid_stage");
                            bool map = (string)stage["Type"] == "外交地图";
                            if (StageTaskEntryPolicy.Supports(row.Kind))
                            {
                                Need(!map && catalog.HasTarget(names[0]), "invalid_stage");
                                row.TaskEntry = new StageTaskEntryPolicy(row.Kind, names[0], row.Difficulty, input["selector"] as JObject, content.Catalog);
                                row.Scope = row.TaskEntry.Scope;
                            }
                            else if (StageAdmissionCatalog.IsSpecial(row.Kind))
                            {
                                Need(catalog.SpecialTarget(row.Kind, names[0], row.Difficulty), "unsupported_entry_kind");
                                row.Selector = new JObject { ["entryId"] = catalog.SpecialSelector(row.Kind,names[0]) };
                            }
                            else
                            {
                                Need(map ? row.Kind == "map" || row.Kind == "legacy_map" : row.Kind == "difficulty" || row.Kind == "legacy_difficulty" || row.Kind == "task", "unsupported_entry_kind");
                                if (row.Kind == "difficulty" || row.Kind == "legacy_difficulty") Need(StageDifficulties.Contains(row.Difficulty), "invalid_difficulty");
                            }
                        }
                        row.RequiresLoad = intent == "enter" && (row.TaskEntry != null || StageAdmissionCatalog.IsSpecial(row.Kind)
                            || row.Kind == "legacy_difficulty" || (row.Kind == "difficulty" && names[0] != "DEATH MATCH角斗场"));
                        Need(OwnerCurrent(row), "panel_instance_expired");
                        requests.Add(id, row);
                        return Success(new JObject { ["operation"] = id, ["scope"] = row.Scope.DeepClone() });
                    }
                    Need(requests.TryGetValue(id, out var request), "unknown_admission_operation");
                    if (op == "confirm_load")
                    {
                        Keys(input, "version", "op", "binding", "catalog", "taskDigest", "slot", "operation", "scene", "owner");
                        Need(request.RequiresLoad && request.State == "granted" && time < request.Expires
                            && Integer(input["scene"], "scene") == request.Scene && (string)input["owner"] == request.Owner
                            && OwnerCurrent(request), "stage_state_changed");
                        request.LoadConfirmed = true;
                        return Success(new JObject { ["operation"] = id, ["binding"] = binding, ["state"] = "load_confirmed" });
                    }
                    if (op == "query" || op == "outcome")
                    {
                        Keys(input, "version", "op", "binding", "catalog", "taskDigest", "slot", "operation", "state");
                        if (op == "outcome")
                        {
                            string next = Text(input, "state", 24);
                            // Notifications can be retried. They never issue or renew a grant.
                            Need(next == request.State || (next == "failed" && (request.State == "prepared" || request.State == "granted" || request.State == "sealed"))
                                || (request.State == "granted" && next == "sealed" && (!request.RequiresLoad || request.LoadConfirmed)) || (request.State == "sealed" && next == "committed")
                                || (request.State == "committed" && next == "started")
                                || (next == "unknown" && (request.State == "sealed" || request.State == "granted")), "admission_state_conflict");
                            request.State = next;
                        }
                        return Success(new JObject { ["operation"] = id, ["state"] = request.State });
                    }
                    Need(op == "decide", "unsupported_admission_operation");
                    Keys(input, "version", "op", "binding", "slot", "catalog", "taskDigest", "operation", "scene", "owner", "facts", "challenge", "force");
                    Need(request.State == "prepared" && time < request.Expires && OwnerCurrent(request), "admission_expired");
                    Need(Integer(input["scene"], "scene") == request.Scene && (string)input["owner"] == request.Owner, "stage_state_changed");
                    Need(input["challenge"]?.Type == JTokenType.Boolean && input["force"]?.Type == JTokenType.Boolean, "invalid_stage_mode");
                    var facts = ValidateFacts(request.Scope, input["facts"] as JObject, content.Catalog);
                    bool challenge = (bool)input["challenge"], force = (bool)input["force"] && !challenge
                        && (request.Kind == "difficulty" || request.Kind == "map" || request.Kind == "task" || request.Kind == "panel" || request.Kind == "legacy_difficulty");
                    var decisions = new JObject();
                    if (request.TaskEntry == null)
                        foreach (string name in request.Names) decisions[name] = catalog.Decide(name, facts, force, request.Kind);
                    if (request.Intent == "snapshot")
                    {
                        requests.Remove(id);
                        return Success(new JObject { ["operation"] = id, ["decisions"] = decisions, ["force"] = force, ["challenge"] = challenge });
                    }
                    request.State = "failed";
                    Need(!challenge || (request.Kind != "difficulty" && request.Kind != "legacy_difficulty") || request.Difficulty == "地狱", "challenge_requires_hell");
                    if (request.TaskEntry == null) Need((bool)decisions[request.Names[0]]["unlocked"], "locked");
                    else { string rejection = request.TaskEntry.Rejection(facts); Need(rejection == null, rejection); }
                    request.State = "granted";
                    return Success(new JObject { ["operation"] = id, ["state"] = request.State, ["catalog"] = catalog.Digest,
                        ["binding"] = binding, ["stage"] = request.Names[0], ["difficulty"] = request.Difficulty,
                        ["kind"] = request.Kind, ["owner"] = request.Owner, ["scene"] = request.Scene });
                }
                catch (Exception e) when (e is InvalidDataException || e is ArgumentException || e is InvalidCastException || e is FormatException || e is OverflowException)
                { return Failure(e.Message); }
            }
        }

        private bool OwnerCurrent(Request r) => ownsPanel == null ||
            ownsPanel(r.Owner, r.Intent, r.Names, r.Kind, r.Difficulty, catalog.Digest, r.Selector);

        private static JObject ValidateFacts(JObject scope, JObject raw, MapTaskCatalog taskCatalog)
        {
            Need(raw != null, "missing_stage_facts");
            if (scope["assets"] == null) Keys(raw, "chains", "tasks", "clears");
            else Keys(raw, "chains", "tasks", "clears", "assets");
            JObject Group(string field, IEnumerable<string> required)
            {
                var group = raw[field] as JObject;
                Need(group != null && new HashSet<string>(group.Properties().Select(p => p.Name), StringComparer.Ordinal).SetEquals(required),
                    "stage_fact_scope_mismatch:" + field);
                return group;
            }
            var chains = Group("chains", scope["chains"].Values<string>());
            foreach (var p in chains.Properties()) if (p.Value.Type != JTokenType.Null) Integer(p.Value, "任务链事实");
            var clears = Group("clears", scope["clears"].Values<string>());
            foreach (var p in clears.Properties())
                Need(p.Value.Type == JTokenType.Null || (p.Value is JArray modes && modes.Count <= 4 &&
                    modes.All(m => m.Type == JTokenType.String && StageDifficulties.Contains((string)m)) &&
                    modes.Values<string>().Distinct().Count() == modes.Count), "invalid_stage_history");
            var neededTasks = (JObject)scope["tasks"];
            var tasks = Group("tasks", neededTasks.Properties().Select(p => p.Name));
            var verifiedTasks = (JObject)tasks.DeepClone();
            foreach (var p in neededTasks.Properties())
            {
                var sample = verifiedTasks[p.Name] as JObject;
                Need(sample != null && new HashSet<string>(sample.Properties().Select(x => x.Name)).SetEquals(p.Value.Values<string>()), "invalid_stage_task_scope");
                foreach (string field in p.Value.Values<string>())
                {
                    var v = sample[field];
                    if (v.Type == JTokenType.Null) continue;
                    if (field == "finished") Integer(v, "任务完成次数");
                    else if (field == "objective")
                    {
                        Need(v.Type == JTokenType.String, "invalid_stage_task_objective");
                        var objectives = taskCatalog.Tasks[p.Name]?["finish_requirements"] as JArray;
                        if (objectives?.Count != 1 || !JToken.DeepEquals(objectives[0], v)) sample[field] = JValue.CreateNull();
                    }
                    else Need(v.Type == JTokenType.Boolean, "invalid_stage_task_fact");
                }
            }
            var verified = new JObject { ["chains"] = chains.DeepClone(), ["tasks"] = verifiedTasks, ["clears"] = clears.DeepClone() };
            if (scope["assets"] != null)
            {
                var assets = Group("assets", scope["assets"].Values<string>());
                foreach (var p in assets.Properties()) if (p.Value.Type != JTokenType.Null) Integer(p.Value, p.Name);
                verified["assets"] = assets.DeepClone();
            }
            return verified;
        }

        private static JObject Success(JObject value) => new JObject { ["task"] = "stage_admission", ["success"] = true, ["result"] = value };
        private static JObject Failure(string error) => new JObject { ["task"] = "stage_admission", ["success"] = false, ["error"] = error };
    }
}
