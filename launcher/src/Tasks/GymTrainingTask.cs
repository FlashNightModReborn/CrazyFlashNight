using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Text.RegularExpressions;
using System.Threading;
using CF7Launcher.Bus;
using CF7Launcher.Guardian;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Tasks
{
    /// <summary>
    /// Gym transport and foreground-only clock. AS2 owns every price, reward and
    /// durable write; only its exact finish response can settle a session.
    /// </summary>
    public sealed class GymTrainingTask : IDisposable
    {
        // A starved timer must not credit a long, unobserved sleep/focus gap.
        private const long MaxObservedClockStepMs = 400;
        private sealed class Pending
        {
            public string Operation, Instance, OpenToken, SessionToken, ProjectId;
            public long ExpectedDurationMs;
            public bool Automatic;
        }

        private sealed class Session
        {
            public string Token, ProjectId, OwnerInstance, Phase;
            public long DurationMs, ElapsedMs, LastTick;
            public bool LastTickActive, CloseRequested, PendingReopenUnqueried;
            public JObject LastResult;
        }

        private static readonly Regex SafeId = new Regex(
            "^[A-Za-z0-9._~-]{1,128}$", RegexOptions.Compiled);
        private readonly object _gate = new object();
        private readonly PanelPendingCallTracker<Pending> _pending;
        private readonly Func<long> _clock;
        private readonly long _frequency;
        private readonly Timer _timer;
        private Func<bool> _isActive;
        private Action<string> _post;
        private Action<Action> _invoke;
        private string _boundInstance, _openToken, _stationId, _inFlight;
        private readonly HashSet<string> _projects = new HashSet<string>(StringComparer.Ordinal);
        private readonly Dictionary<string, long> _projectDurations =
            new Dictionary<string, long>(StringComparer.Ordinal);
        private Session _session;
        private bool _cancelOnStartAck, _disposed;
        private int _automaticSequence;

        public GymTrainingTask(XmlSocketServer socket) : this(
            () => socket != null && socket.IsClientReady,
            text => socket != null && socket.TrySend(text),
            Stopwatch.GetTimestamp, Stopwatch.Frequency, () => false, true) { }

        internal GymTrainingTask(
            Func<bool> ready, Func<string, bool> send,
            Func<long> clock, long frequency, Func<bool> isActive,
            bool startTimer = true, int timeoutMs = 10000)
        {
            _clock = clock ?? Stopwatch.GetTimestamp;
            _frequency = frequency > 0 ? frequency : Stopwatch.Frequency;
            _isActive = isActive ?? (() => false);
            _pending = new PanelPendingCallTracker<Pending>(
                ready, text =>
                {
                    try { return send != null && send(text); }
                    catch (Exception error)
                    {
                        LogManager.Log("[Gym] delivery unknown: " + error.GetType().Name);
                        return false;
                    }
                }, timeoutMs, OnPendingEnded);
            if (startTimer)
                _timer = new Timer(_ => Tick(), null, 200, 200);
        }

        public void SetPostToWeb(Action<string> post) { _post = post; }
        public void SetInvoker(Action<Action> invoke) { _invoke = invoke; }
        public void SetActivityProbe(Func<bool> active)
        { lock (_gate) _isActive = active ?? (() => false); }

        /// <summary>Called by PanelHost's trusted open-data enricher, before Web delivery.</summary>
        public string BindPanelOpenData(string initDataJson, string instance)
        {
            JObject data = Parse(initDataJson);
            JObject snapshot = data?["snapshot"] as JObject;
            JToken pendingToken = snapshot?["pendingSession"];
            JObject pendingSession = pendingToken as JObject;
            string pendingProject = Text(pendingSession?["projectId"]);
            bool valid = Safe(instance)
                && Text(data?["mode"]) == "preview"
                && Text(data?["source"]) == "world_gym"
                && Integer(snapshot?["v"], 2, 2)
                && Token(snapshot?["openToken"], "gym.open.")
                && Text(data?["stationId"]) == Text(snapshot?["stationId"])
                && pendingToken != null
                && (pendingToken.Type == JTokenType.Null
                    || (Exact(pendingSession, "sessionToken", "stationId",
                            "projectId", "phase")
                        && Token(pendingSession["sessionToken"], "gym.session.")
                        && Text(pendingSession["stationId"]) == Text(snapshot["stationId"])
                        && Text(pendingSession["phase"]) == "save_pending"))
                && snapshot["projects"] is JArray;
            lock (_gate)
            {
                _boundInstance = valid ? instance : null;
                _openToken = valid ? Text(snapshot["openToken"]) : null;
                _stationId = valid ? Text(snapshot["stationId"]) : null;
                _projects.Clear();
                _projectDurations.Clear();
                if (valid)
                    foreach (JToken item in (JArray)snapshot["projects"])
                    {
                        string projectId = Text(item?["id"]);
                        if (projectId != null && projectId.StartsWith(
                            _stationId + ".", StringComparison.Ordinal))
                        {
                            _projects.Add(projectId);
                            if (Integer(item?["durationMs"], 1, 3600000))
                                _projectDurations[projectId] = item.Value<long>("durationMs");
                        }
                    }
                if (valid && pendingSession != null
                    && _projectDurations.ContainsKey(pendingProject))
                {
                    string exactToken = Text(pendingSession["sessionToken"]);
                    if (_session == null || _session.Token != exactToken)
                        _session = new Session { Token = exactToken,
                            ProjectId = pendingProject };
                    _session.OwnerInstance = instance;
                    _session.Phase = "save_pending";
                    _session.DurationMs = _projectDurations[pendingProject];
                    _session.ElapsedMs = _session.DurationMs;
                    _session.CloseRequested = false;
                    _session.PendingReopenUnqueried = true;
                    _session.LastResult = null;
                    _session.LastTick = _clock();
                    _session.LastTickActive = false;
                }
                else if (valid && pendingToken.Type == JTokenType.Null)
                {
                    // Fresh AS2 snapshot supersedes any prior terminal or
                    // unknown Host-only state. No business write is replayed.
                    _session = null;
                    _cancelOnStartAck = false;
                }
                else if (valid) _boundInstance = _openToken = _stationId = null;
            }
            return initDataJson;
        }

        /// <summary>Authoritative close wins against any later clock tick.</summary>
        public void HandlePanelClosed(string instance)
        {
            Pending cancel = null;
            JObject payload = null;
            lock (_gate)
            {
                if (_boundInstance != instance) return;
                _boundInstance = _openToken = _stationId = null;
                _projects.Clear();
                _projectDurations.Clear();
                if (_session == null)
                {
                    if (_inFlight == "start") _cancelOnStartAck = true;
                    return;
                }
                _session.CloseRequested = true;
                if (_session.Phase == "running" && _inFlight == null)
                {
                    _session.Phase = "cancelling";
                    cancel = new Pending { Operation = "cancel", Instance = instance,
                        SessionToken = _session.Token, ProjectId = _session.ProjectId,
                        ExpectedDurationMs = _session.DurationMs,
                        Automatic = true };
                    payload = new JObject { ["v"] = 1, ["sessionToken"] = _session.Token };
                }
            }
            if (cancel != null) Send(cancel, payload);
        }

        public void HandleWebRequest(string cmd, JObject message)
        {
            string callId = Text(message?["callId"]);
            string instance = Text(message?["panelInstanceId"]);
            if (!Safe(callId) || _pending.IsKnownWebCallId(callId)) return;
            if (Text(message?["panel"]) != "gym"
                || Text(message?["domain"]) != "gym"
                || !Safe(instance))
            { Reject(callId, cmd, instance, "invalid_owner"); return; }
            if (!new[] { "start", "cancel", "status", "query", "retrySave" }
                .Contains(cmd))
            { Reject(callId, cmd, instance, "unsupported_cmd"); return; }
            JObject payload = message["payload"] as JObject;
            if (!Exact(payload, cmd == "start"
                    ? new[] { "v", "projectId" } : new[] { "v" })
                || !Integer(payload?["v"], 1, 1)
                || (cmd == "start" && !Safe(Text(payload["projectId"]))))
            { Reject(callId, cmd, instance, "invalid_payload"); return; }

            Pending request = null;
            JObject flashPayload = null;
            JObject immediate = null;
            string error = null;
            lock (_gate)
            {
                if (_disposed || _boundInstance != instance)
                    error = "panel_instance_expired";
                else if (cmd == "status")
                    immediate = StateLocked();
                else if (cmd == "start")
                {
                    string project = Text(payload["projectId"]);
                    if (!_projects.Contains(project)
                        || !_projectDurations.ContainsKey(project))
                        error = "invalid_project";
                    else if (_inFlight != null || (_session != null
                        && _session.Phase != "applied" && _session.Phase != "cancelled"))
                        error = "busy";
                    else if (!_pending.IsReady()) error = "disconnected";
                    else
                    {
                        _session = null;
                        request = new Pending { Operation = "start", Instance = instance,
                            OpenToken = _openToken, ProjectId = project,
                            ExpectedDurationMs = _projectDurations[project] };
                        flashPayload = new JObject { ["v"] = 1,
                            ["openToken"] = _openToken, ["stationId"] = _stationId,
                            ["projectId"] = project };
                    }
                }
                else if (cmd == "cancel")
                {
                    if (_inFlight == "start")
                    {
                        _cancelOnStartAck = true;
                        immediate = StateLocked();
                        immediate["phase"] = "cancelling";
                    }
                    else if (_session == null || _session.Phase == "cancelled")
                        immediate = StateLocked();
                    else if (_session.Phase != "running" || _inFlight != null)
                        error = "busy";
                    else if (!_pending.IsReady()) error = "disconnected";
                    else
                    {
                        _session.Phase = "cancelling";
                        request = SessionRequestLocked("cancel", instance);
                        flashPayload = SessionPayloadLocked();
                    }
                }
                else if (cmd == "query")
                {
                    if (_session == null || (_session.Phase != "needs_reconcile"
                        && _session.Phase != "save_pending"))
                        error = "query_not_required";
                    else if (_inFlight != null) error = "busy";
                    else if (!_pending.IsReady()) error = "disconnected";
                    else { request = SessionRequestLocked("query", instance);
                        flashPayload = SessionPayloadLocked(); }
                }
                else if (cmd == "retrySave")
                {
                    if (_session == null || _session.Phase != "save_pending")
                        error = "save_not_pending";
                    else if (_session.PendingReopenUnqueried)
                        error = "query_required";
                    else if (_inFlight != null) error = "busy";
                    else if (!_pending.IsReady()) error = "disconnected";
                    else { request = SessionRequestLocked("retrySave", instance);
                        flashPayload = SessionPayloadLocked(); }
                }
            }
            if (error != null) { Reject(callId, cmd, instance, error); return; }
            if (immediate != null)
            {
                if (!_pending.TryRememberRejected(callId)) return;
                Envelope(immediate, callId, cmd, instance);
                Post(immediate);
                return;
            }
            if (request != null) Send(request, flashPayload, callId);
        }

        public void HandleFlashResponse(JObject message, Action<string> respond)
        {
            PanelPendingCall<Pending> call;
            int fid = Integer(message?["callId"], 1, int.MaxValue)
                ? message.Value<int>("callId") : 0;
            if (!_pending.TryComplete(fid, out call)) { respond?.Invoke(null); return; }
            Pending request = call.Context;
            JObject outbound;
            Pending followup = null;
            JObject followupPayload = null;
            lock (_gate)
            {
                if (request.Operation != "start" && _session != null
                    && _session.Token != request.SessionToken)
                {
                    if (_inFlight == request.Operation) _inFlight = null;
                    respond?.Invoke(null);
                    return;
                }
                if (_inFlight == request.Operation) _inFlight = null;
                bool valid = ValidResponse(message, request);
                if (!valid)
                {
                    if (request.Operation == "finish" || request.Operation == "query"
                        || request.Operation == "retrySave")
                        MarkNeedsReconcileLocked();
                    else if (request.Operation == "cancel" && _session != null)
                        _session.Phase = "needs_reconcile";
                    outbound = ErrorStateLocked("malformed_response");
                }
                else
                {
                    string phase = Text(message["phase"]);
                    bool success = message.Value<bool>("success");
                    if (request.Operation == "start" && success && phase == "running")
                    {
                        _session = new Session { Token = Text(message["sessionToken"]),
                            ProjectId = request.ProjectId, OwnerInstance = request.Instance,
                            Phase = "running", DurationMs = message.Value<long>("durationMs"),
                            LastTick = _clock(), LastTickActive = IsActiveLocked(),
                            LastResult = Clean(message) };
                        if (_cancelOnStartAck || _boundInstance != request.Instance)
                        {
                            _cancelOnStartAck = false;
                            _session.CloseRequested = true;
                            _session.Phase = "cancelling";
                            followup = SessionRequestLocked("cancel", request.Instance, true);
                            followupPayload = SessionPayloadLocked();
                        }
                    }
                    else if (request.Operation == "cancel" && phase == "cancelled")
                    {
                        _session = null;
                    }
                    else if (request.Operation == "cancel" && _session != null)
                    {
                        _session.Phase = phase == "applied"
                            ? "applied" : phase == "save_pending"
                                ? "save_pending" : "needs_reconcile";
                        if (phase == "applied" || phase == "save_pending")
                            _session.LastResult = Clean(message);
                    }
                    else if (_session != null
                        && (request.Operation == "finish" || request.Operation == "query"
                            || request.Operation == "retrySave"))
                    {
                        if (request.Operation == "query"
                            && (phase == "applied" || phase == "save_pending"))
                            _session.PendingReopenUnqueried = false;
                        if (phase == "applied" && message.Value<bool>("saved"))
                            _session.Phase = "applied";
                        else if (phase == "save_pending")
                            _session.Phase = "save_pending";
                        else if (phase == "cancelled")
                            _session.Phase = "cancelled";
                        else if (phase == "preview" && request.Operation == "query"
                            && !success && Text(message["error"]) == "stale_token")
                            _session.Phase = "outcome_unavailable";
                        else if (phase == "running" && request.Operation == "query"
                            && success)
                        {
                            _session.Phase = "running";
                            _session.LastTick = _clock();
                            _session.LastTickActive = IsActiveLocked();
                            if (_session.CloseRequested
                                || _boundInstance != _session.OwnerInstance)
                            {
                                _session.Phase = "cancelling";
                                followup = SessionRequestLocked("cancel",
                                    request.Instance, true);
                                followupPayload = SessionPayloadLocked();
                            }
                        }
                        else if (phase == "running" && request.Operation == "finish"
                            && !success && Text(message["error"]) == "not_ready")
                        {
                            // AS2 proved that no business write happened. Let
                            // one more active second elapse before a new finish.
                            _session.Phase = "running";
                            _session.ElapsedMs = Math.Max(0,
                                _session.DurationMs - 1000);
                            _session.LastTick = _clock();
                            _session.LastTickActive = IsActiveLocked();
                        }
                        else
                            _session.Phase = "needs_reconcile";
                        _session.LastResult = Clean(message);
                    }
                    else if (!success && request.Operation == "start")
                        _session = null;
                    outbound = StateLocked();
                    foreach (JProperty property in Clean(message).Properties())
                        outbound[property.Name] = property.Value;
                    outbound["phase"] = _session != null
                        ? _session.Phase : (request.Operation == "cancel" ? "cancelled" : phase);
                    outbound["requiresReconcile"] = _session != null
                        && _session.Phase == "needs_reconcile";
                }
                if (!request.Automatic)
                    Envelope(outbound, call.WebCallId, request.Operation, request.Instance);
                else
                {
                    outbound["type"] = "panel_event";
                    outbound["panel"] = "gym";
                    outbound["domain"] = "gym";
                    outbound["event"] = request.Operation == "cancel"
                        && Text(outbound["phase"]) == "cancelled"
                        ? "cancelled" : "settled";
                    outbound["panelInstanceId"] = request.Instance;
                }
            }
            Post(outbound);
            if (followup != null) Send(followup, followupPayload);
            respond?.Invoke(null);
        }

        private static bool ValidResponse(JObject value, Pending request)
        {
            if (Text(value?["task"]) != "gym_training_response"
                || !Integer(value?["v"], 1, 1)
                || Text(value?["operation"]) != request.Operation
                || value?["success"]?.Type != JTokenType.Boolean
                || Text(value?["phase"]) == null
                || (value["error"]?.Type != JTokenType.String
                    && value["error"]?.Type != JTokenType.Null)) return false;
            bool success = value.Value<bool>("success");
            string phase = Text(value["phase"]);
            if (request.Operation == "start")
            {
                if (Text(value["openToken"]) != request.OpenToken) return false;
                if (!success)
                    return phase == "preview" && Text(value["error"]) != null;
                return Token(value["sessionToken"], "gym.session.")
                    && Text(value["projectId"]) == request.ProjectId
                    && Integer(value["durationMs"], 1, 3600000)
                    && value.Value<long>("durationMs") == request.ExpectedDurationMs
                    && phase == "running" && FullState(value);
            }
            if (Text(value["sessionToken"]) != request.SessionToken) return false;
            if (phase == "preview")
                return !success && Text(value["error"]) != null;
            if (!FullState(value)
                || value.Value<long>("durationMs") != request.ExpectedDurationMs
                || Text(value["projectId"]) != request.ProjectId) return false;
            if (phase == "applied")
                return success && value.Value<bool>("saved");
            if (phase == "save_pending")
                return !success && !value.Value<bool>("saved")
                    && Text(value["error"]) == "save_pending";
            if (phase == "cancelled")
                return !value.Value<bool>("saved");
            if (phase == "running")
                return !value.Value<bool>("saved")
                    && (success || Text(value["error"]) != null);
            return false;
        }

        private static bool FullState(JObject value)
        {
            JObject award = value?["award"] as JObject;
            JObject balances = value?["balances"] as JObject;
            string kind = Text(award?["kind"]);
            bool coherentAward = kind == "stat"
                ? Integer(award?["amount"], 1, 9007199254740991L)
                    && Integer(award?["baseExperience"], 10000, 10000)
                    && Integer(award?["capExperience"], 0, 0)
                : kind == "experience"
                    ? Integer(award?["amount"], 50000, 50000)
                        && Integer(award?["baseExperience"], 10000, 10000)
                        && Integer(award?["capExperience"], 50000, 50000)
                    : kind == "skillPoints"
                        && Integer(award?["amount"], 1, 9007199254740991L)
                        && Integer(award?["baseExperience"], 0, 0)
                        && Integer(award?["capExperience"], 0, 0);
            return value?["saved"]?.Type == JTokenType.Boolean
                && Integer(value?["durationMs"], 1, 3600000)
                && Text(value?["stationId"]) != null
                && coherentAward
                && Integer(balances?["money"], 0, 9007199254740991L)
                && Integer(balances?["kpoint"], 0, 9007199254740991L)
                && Integer(value?["current"], 0, 9007199254740991L)
                && (value?["cap"]?.Type == JTokenType.Null
                    || Integer(value?["cap"], 1, 9007199254740991L))
                && Integer(value?["experience"], 0, 9007199254740991L)
                && Integer(value?["skillPoints"], 0, 9007199254740991L)
                && Integer(value?["level"], 0, 9007199254740991L);
        }

        private void Tick()
        {
            Pending finish = null;
            JObject finishPayload = null, progress = null;
            lock (_gate)
            {
                if (_disposed || _session == null || _session.Phase != "running") return;
                bool active = IsActiveLocked() && _pending.IsReady();
                long now = _clock();
                if (active && _session.LastTickActive && now >= _session.LastTick)
                {
                    long delta = Math.Min(MaxObservedClockStepMs,
                        (now - _session.LastTick) * 1000 / _frequency);
                    _session.ElapsedMs = Math.Min(_session.DurationMs,
                        _session.ElapsedMs + Math.Max(0, delta));
                }
                _session.LastTick = now;
                _session.LastTickActive = active;
                if (_session.CloseRequested) return;
                if (_session.ElapsedMs >= _session.DurationMs && _inFlight == null)
                {
                    if (_pending.IsReady())
                    {
                        _session.Phase = "settling";
                        finish = SessionRequestLocked("finish",
                            _session.OwnerInstance, true);
                        finishPayload = SessionPayloadLocked();
                    }
                }
                progress = StateLocked();
                progress["type"] = "panel_event";
                progress["panel"] = "gym";
                progress["domain"] = "gym";
                progress["event"] = "progress";
                progress["panelInstanceId"] = _session.OwnerInstance;
            }
            if (progress != null) Post(progress);
            if (finish != null) Send(finish, finishPayload);
        }

        internal void TickForTest() { Tick(); }

        private Pending SessionRequestLocked(string operation, string instance,
            bool automatic = false)
        {
            return new Pending { Operation = operation, Instance = instance,
                SessionToken = _session.Token, ProjectId = _session.ProjectId,
                ExpectedDurationMs = _session.DurationMs,
                Automatic = automatic };
        }
        private JObject SessionPayloadLocked()
        {
            return new JObject { ["v"] = 1, ["sessionToken"] = _session.Token };
        }

        private void Send(Pending request, JObject payload, string webCallId = null)
        {
            string action = FlashActionFor(request.Operation);
            if (action == null) return;
            int fid;
            string id = webCallId ?? "gym.auto." +
                Interlocked.Increment(ref _automaticSequence);
            lock (_gate)
            {
                if (_disposed || !_pending.TryBegin(id, request, out fid)) return;
                _inFlight = request.Operation;
            }
            _pending.Send(fid, PanelBridge.BuildFlashCommand(
                action, fid, payload).ToString(Formatting.None) + "\0");
        }

        private static string FlashActionFor(string operation)
        {
            switch (operation)
            {
                case "start": return "gymStart";
                case "cancel": return "gymCancel";
                case "finish": return "gymFinish";
                case "query": return "gymQuery";
                case "retrySave": return "gymRetrySave";
                default: return null;
            }
        }

        private void OnPendingEnded(
            PanelPendingCall<Pending> call, PanelPendingCallEndReason reason)
        {
            JObject outbound;
            lock (_gate)
            {
                Pending request = call.Context;
                if (_inFlight == request.Operation) _inFlight = null;
                if (request.Operation == "finish" || request.Operation == "query"
                    || request.Operation == "retrySave")
                    MarkNeedsReconcileLocked();
                else if (request.Operation == "cancel" && _session != null)
                    _session.Phase = "needs_reconcile";
                else if (request.Operation == "start")
                    _session = null;
                if (reason == PanelPendingCallEndReason.Cleared) return;
                outbound = ErrorStateLocked(reason == PanelPendingCallEndReason.Timeout
                    ? "timeout" : "disconnected");
                if (!request.Automatic)
                    Envelope(outbound, call.WebCallId,
                        request.Operation, request.Instance);
                else
                {
                    outbound["type"] = "panel_event";
                    outbound["panel"] = "gym";
                    outbound["domain"] = "gym";
                    outbound["event"] = "settled";
                    outbound["panelInstanceId"] = request.Instance;
                }
            }
            Post(outbound);
        }

        public void OnSocketDisconnected()
        {
            _pending.Clear();
            lock (_gate)
            {
                if (_session != null)
                {
                    if (_session.Phase == "running"
                        || _session.Phase == "cancelling"
                        || _session.Phase == "cancelled")
                        _session = null;
                    else if (_session.Phase == "settling"
                        || _session.Phase == "save_pending")
                        _session.Phase = "needs_reconcile";
                }
            }
        }

        private bool IsActiveLocked()
        {
            try { return _isActive != null && _isActive(); }
            catch { return false; }
        }

        private JObject StateLocked()
        {
            JObject state = _session?.LastResult != null
                ? (JObject)_session.LastResult.DeepClone() : new JObject();
            state["success"] = true;
            state["phase"] = _session?.Phase ?? (_inFlight == "start" ? "starting" : "preview");
            state["requiresReconcile"] = _session != null
                && _session.Phase == "needs_reconcile";
            state["queryRequired"] = _session != null
                && _session.PendingReopenUnqueried;
            if (_session != null && _session.Phase == "running")
                state["error"] = JValue.CreateNull();
            if (_session != null)
            {
                state["sessionToken"] = _session.Token;
                state["projectId"] = _session.ProjectId;
                state["durationMs"] = _session.DurationMs;
                state["elapsedMs"] = _session.ElapsedMs;
                state["remainingMs"] = Math.Max(0, _session.DurationMs - _session.ElapsedMs);
                state["progressPercent"] = _session.DurationMs <= 0 ? 0
                    : Math.Min(100, _session.ElapsedMs * 100 / _session.DurationMs);
                state["paused"] = _session.Phase == "running" && !IsActiveLocked();
            }
            return state;
        }

        private JObject ErrorStateLocked(string error)
        {
            JObject result = StateLocked();
            result["success"] = false;
            result["error"] = error;
            return result;
        }

        private void MarkNeedsReconcileLocked()
        {
            if (_session != null) _session.Phase = "needs_reconcile";
        }

        private void Reject(string callId, string cmd, string instance, string error)
        {
            if (!_pending.TryRememberRejected(callId)) return;
            JObject value;
            lock (_gate) value = ErrorStateLocked(error);
            Envelope(value, callId, cmd, instance);
            Post(value);
        }

        private static JObject Clean(JObject response)
        {
            JObject clean = (JObject)response.DeepClone();
            clean.Remove("task");
            clean.Remove("callId");
            return clean;
        }

        private static void Envelope(
            JObject value, string callId, string cmd, string instance)
        {
            value["type"] = "panel_resp";
            value["panel"] = "gym";
            value["domain"] = "gym";
            value["cmd"] = cmd;
            value["callId"] = callId;
            value["panelInstanceId"] = instance;
        }

        private void Post(JObject value)
        {
            string text = value.ToString(Formatting.None);
            Action action = () => { if (!_disposed) _post?.Invoke(text); };
            if (_invoke != null) _invoke(action);
            else action();
        }

        public void Dispose()
        {
            lock (_gate) _disposed = true;
            _timer?.Dispose();
            _pending.Dispose();
        }

        private static JObject Parse(string json)
        {
            try { return JObject.Parse(json); }
            catch (Exception) { return null; }
        }
        private static string Text(JToken token)
        {
            return token?.Type == JTokenType.String
                ? token.Value<string>() : null;
        }
        private static bool Safe(string value)
        {
            return !string.IsNullOrEmpty(value) && SafeId.IsMatch(value);
        }
        private static bool Token(JToken token, string prefix)
        {
            string value = Text(token);
            return Safe(value) && value.StartsWith(prefix, StringComparison.Ordinal);
        }
        private static bool Exact(JObject value, params string[] keys)
        {
            return value != null && value.Properties().Count() == keys.Length
                && keys.All(key => value.Property(key, StringComparison.Ordinal) != null);
        }
        private static bool Integer(JToken value, long min, long max)
        {
            if (value?.Type != JTokenType.Integer) return false;
            try
            {
                long number = value.Value<long>();
                return number >= min && number <= max;
            }
            catch (Exception) { return false; }
        }
    }
}
