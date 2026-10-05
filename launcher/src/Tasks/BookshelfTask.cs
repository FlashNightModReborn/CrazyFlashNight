using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using CF7Launcher.Bus;
using CF7Launcher.Guardian;
using CF7Launcher.Save;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Tasks
{
    /// <summary>Bookshelf transport and canonical slot resolution. AS2 owns context admission.</summary>
    public sealed class BookshelfTask : IDisposable
    {
        private sealed class Request { public string Cmd, Token, Instance, Kind, Target, Destination; public bool IsWrite; }
        private static readonly Regex Id = new Regex("^[A-Za-z0-9._~-]{1,128}$");
        private readonly string _runNamespace = Guid.NewGuid().ToString("N");
        private readonly object _gate = new object();
        private readonly PanelPendingCallTracker<Request> _pending;
        private Action<string> _post;
        private Action<Action> _invoke;
        private Action<string> _permanentSlotApplied;
        private Action<string, JObject> _returnPresentation;
        private string _lastAppliedToken;
        private string _originalInstance, _originalToken;
        private Action _originalRevoked;
        private SaveResolutionContext _saves;
        private readonly Func<JArray> _catalogSource;
        private readonly Func<string, SolResolveResult> _resolveSource;
        private string _unresolved, _unresolvedKind, _unresolvedTarget, _unresolvedDestination;
        private bool _writePending, _disposed;

        public BookshelfTask(XmlSocketServer socket) : this(() => socket != null && socket.IsClientReady,
            text => socket != null && socket.TrySend(text)) { }
        public BookshelfTask(Func<bool> ready, Func<string, bool> send, int timeoutMs = 15000,
            Func<JArray> catalog = null, Func<string, SolResolveResult> resolve = null)
        {
            _catalogSource = catalog; _resolveSource = resolve;
            _pending = new PanelPendingCallTracker<Request>(ready, text => {
                try { return send != null && send(text); } catch { return false; }
            }, timeoutMs, Ended);
        }
        public void SetPermanentSlotApplied(Action<string> callback) { _permanentSlotApplied = callback; }
        public void SetSaveContext(SaveResolutionContext saves) { _saves = saves; }
        public void SetPostToWeb(Action<string> post) { _post = post; }
        public void SetInvoker(Action<Action> invoke) { _invoke = invoke; }
        internal void SetReturnPresentation(Action<string, JObject> callback) { _returnPresentation = callback; }
        internal bool IsReturning { get { lock (_gate) return _unresolvedKind == "return"; } }
        internal void SetOriginalRevoked(Action callback) { _originalRevoked = callback; }
        private void RevokeOriginal() { _originalInstance = _originalToken = null; _originalRevoked?.Invoke(); }
        internal bool CanOpenOriginal(string instance, string token)
        {
            lock (_gate) return !_disposed && !_writePending && _unresolved == null && _pending.IsReady()
                && _originalInstance == instance && _originalToken == token && instance != null && token != null;
        }
        public void ClearPending() { lock (_gate) { RevokeOriginal(); _pending.Clear(); } }
        public void Dispose() { lock (_gate) { _disposed = true; RevokeOriginal(); _pending.Dispose(); } }
        internal static JObject BuildOpenData(string source, string extras)
        {
            if (source != "world_bookshelf") return null;
            JObject data;
            try { data = JObject.Parse(extras ?? ""); } catch (JsonException) { return null; }
            if (!Exact(data, "token") || !Token(data["token"])) return null;
            return new JObject { ["source"] = source, ["token"] = data["token"] };
        }
        internal static bool IsPermanentSlot(string slot) => SaveSlotKey.IsValidExisting(slot)
            && !slot.StartsWith("bookrun_", StringComparison.OrdinalIgnoreCase);
        private JArray Catalog()
        {
            if (_catalogSource != null) return _catalogSource();
            var result = new JArray();
            if (_saves == null) return result;
            var names = _saves.Archive.SlotCatalog.ReadAll();
            var slots = new HashSet<string>(names.Keys, StringComparer.Ordinal);
            if (Directory.Exists(_saves.Archive.SavesDir))
                foreach (var path in Directory.GetFiles(_saves.Archive.SavesDir, "*.json"))
                    slots.Add(Path.GetFileNameWithoutExtension(path));
            foreach (var slot in slots.Where(IsPermanentSlot).OrderBy(s => s, StringComparer.Ordinal))
            {
                if (_saves.Archive.IsTombstoned(slot)) continue;
                names.TryGetValue(slot, out var label);
                if (string.IsNullOrEmpty(label) && _saves.Archive.TryLoadShadowSync(slot, out JObject snapshot, out _))
                    label = Text((snapshot["0"] as JArray)?.First);
                result.Add(new JObject { ["slot"] = slot, ["name"] = string.IsNullOrEmpty(label) ? slot : label });
            }
            return result;
        }
        public void HandleWebRequest(string cmd, JObject parsed)
        {
            string callId = Text(parsed?["callId"]), instance = Text(parsed?["panelInstanceId"]);
            if (callId == null || !Id.IsMatch(callId) || _pending.IsKnownWebCallId(callId)) return;
            if (Text(parsed["panel"]) != "bookshelf"
                || instance == null || !Id.IsMatch(instance)) { RejectAndRemember(callId, cmd, instance, "invalid_owner"); return; }
            if (parsed["domain"]?.Type != JTokenType.String) { RejectAndRemember(callId, cmd, instance, "unsupported_domain"); return; }
            if (!string.Equals(parsed.Value<string>("domain"), "bookshelf", StringComparison.Ordinal)) { RejectAndRemember(callId, cmd, instance, "unsupported_domain"); return; }
            string action;
            bool isWrite;
            if (!TryResolveCommand(cmd, out action, out isWrite)) { RejectAndRemember(callId, cmd, instance, "unsupported_cmd"); return; }
            var payload = parsed["payload"] as JObject;
            if (!Exact(payload,
                    isWrite ? new[] { "v", "token", "kind", "target" } : new[] { "v", "token" })
                || payload?["v"]?.Type != JTokenType.Integer || payload.Value<int>("v") != 1 || !Token(payload["token"]))
            { RejectAndRemember(callId, cmd, instance, "invalid_payload"); return; }
            var normalized = (JObject)payload.DeepClone();
            lock (_gate)
            {
                if (_writePending || (_unresolved != null && (cmd != "query" || Text(payload["token"]) != _unresolved)))
                { RejectAndRemember(callId, cmd, instance, "reconcile_required"); return; }
                if (!_pending.IsReady()) { RejectAndRemember(callId, cmd, instance, "disconnected"); return; }
                if (_saves == null && _resolveSource == null) { RejectAndRemember(callId, cmd, instance, "save_unavailable"); return; }
                try
                {
                    if (cmd == "snapshot") normalized["slots"] = Catalog();
                    if (cmd == "query" && _unresolved != null)
                    {
                        normalized["reconcileKind"] = _unresolvedKind;
                        normalized["reconcileTarget"] = _unresolvedTarget;
                    }
                    if (isWrite)
                    {
                        string kind = Text(payload["kind"]), target = Text(payload["target"]);
                        if (kind == "play" && target == "repair-campus")
                            normalized["runSlot"] = "bookrun_" + Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(
                                _runNamespace + ":" + Text(payload["token"])))).Substring(0, 24).ToLowerInvariant();
                        else if ((kind == "switch" && IsPermanentSlot(target))
                            || (kind == "return" && IsPermanentSlot(target))
                            || (kind == "settle" && SaveSlotKey.IsValidExisting(target) && target.StartsWith("bookrun_", StringComparison.Ordinal)))
                        {
                            var resolved = _resolveSource != null ? _resolveSource(target) : _saves.Resolver.Resolve(target, _saves.SwfPath);
                            if (kind == "settle" && (resolved.Kind == DecisionKind.Empty || resolved.Kind == DecisionKind.Deleted))
                            {
                                normalized["missingRun"] = true;
                            }
                            else
                            {
                                if (resolved.Kind != DecisionKind.Snapshot)
                                { RejectAndRemember(callId, cmd, instance, "slot_" + resolved.WireDecision); return; }
                                normalized["snapshot"] = resolved.Snapshot.DeepClone();
                            }
                        }
                        else { RejectAndRemember(callId, cmd, instance, "invalid_payload"); return; }
                    }
                }
                catch (Exception error)
                {
                    LogManager.Log("[Bookshelf] canonical resolution failed: " + error.GetType().Name);
                    RejectAndRemember(callId, cmd, instance, "save_unavailable"); return;
                }
                var context = new Request { Cmd = cmd, Token = Text(payload["token"]), Instance = instance, IsWrite = isWrite,
                    Kind = isWrite ? Text(payload["kind"]) : _unresolvedKind,
                    Target = isWrite ? Text(payload["target"]) : _unresolvedTarget,
                    Destination = isWrite ? Text(normalized["runSlot"]) ?? Text(payload["target"]) : _unresolvedDestination };
                if (!_pending.TryBegin(callId, context, out int fid)) return;
                if (isWrite) { RevokeOriginal(); _writePending = true; _unresolved = context.Token; _unresolvedKind = context.Kind;
                    _unresolvedTarget = context.Target; _unresolvedDestination = context.Destination; }
                _pending.Send(fid, PanelBridge.BuildFlashCommand(action, fid, normalized).ToString(Formatting.None) + "\0");
            }
        }
        private static bool TryResolveCommand(string cmd, out string action, out bool isWrite)
        {
            action = null; isWrite = false;
            switch (cmd)
            {
                case "snapshot": action = "bookshelfSnapshot"; return true;
                case "commit": action = "bookshelfCommit"; isWrite = true; return true;
                case "query": action = "bookshelfQuery"; return true;
                default: return false;
            }
        }
        public void HandleFlashResponse(JObject message, Action<string> respond)
        {
            lock (_gate)
            {
                int fid = message?["callId"]?.Type == JTokenType.Integer ? message.Value<int>("callId") : 0;
                if (!_pending.TryComplete(fid, out PanelPendingCall<Request> call)) { respond?.Invoke(null); return; }
                var request = call.Context;
                if (request.IsWrite) _writePending = false;
                bool envelope = message?["v"]?.Type == JTokenType.Integer && message.Value<int>("v") == 1
                    && Text(message["operation"]) == request.Cmd && Text(message["token"]) == request.Token;
                string phase = Text(message?["phase"]);
                bool state = envelope && message["success"]?.Type == JTokenType.Boolean
                    && Text(message["activeSlot"]) != null && Text(message["role"]) != null
                    && message["inRun"]?.Type == JTokenType.Boolean && message["unlocked"]?.Type == JTokenType.Boolean
                    && message["canSwitch"]?.Type == JTokenType.Boolean
                    && new[] { "editing", "switching", "applied", "save_pending", "expired" }.Contains(phase);
                if (state && request.Kind != null)
                {
                    state = Text(message["kind"]) == request.Kind && Text(message["target"]) == request.Target
                        && phase != "editing";
                    if (phase == "applied" && request.Kind != "settle")
                        state = state && Text(message["activeSlot"]) == request.Destination;
                }
                if (state) state = message.Value<bool>("success") == (phase != "expired" && phase != "save_pending");
                if (state && message["nextToken"] != null && Text(message["nextToken"]) != "")
                    state = (phase == "applied" || phase == "expired") && Token(message["nextToken"])
                        && Text(message["nextToken"]) != request.Token;
                if (state && message["exitRequired"] != null)
                    state = message["exitRequired"].Type == JTokenType.Boolean;
                if (state && message["records"] != null) state = ValidRecords(message["records"] as JObject);
                if (state && message["returningResult"]?.Type != JTokenType.Null && message["returningResult"] != null)
                    state = ValidResult(message["returningResult"] as JObject, true);
                bool rejected = envelope && message["success"]?.Type == JTokenType.Boolean && !message.Value<bool>("success")
                    && new[] { "invalid_payload", "stale_token", "context_changed", "busy", "locked", "invalid_target",
                        "save_failed", "transition_rejected", "token_conflict", "config_unavailable" }.Contains(Text(message["error"]));
                if (_unresolved == request.Token && ((state && (phase == "applied" || phase == "expired")) || (request.IsWrite && rejected)))
                { _unresolved = _unresolvedKind = _unresolvedTarget = _unresolvedDestination = null; }
                if (state && phase == "applied" && (request.Kind == "switch" || request.Kind == "return")
                    && IsPermanentSlot(Text(message["activeSlot"])) && _lastAppliedToken != request.Token)
                {
                    _lastAppliedToken = request.Token;
                    string appliedSlot = Text(message["activeSlot"]);
                    Action publish = () => {
                        try { _permanentSlotApplied?.Invoke(appliedSlot); }
                        catch (Exception error) { LogManager.Log("[Bookshelf] last-played projection failed: " + error.GetType().Name); }
                    };
                    if (_invoke == null) publish(); else _invoke(publish);
                }
                if (state && message.Value<bool>("success") && message.Value<bool>("canSwitch")
                    && !message.Value<bool>("inRun") && (phase == "editing" || phase == "applied")
                    && IsPermanentSlot(Text(message["activeSlot"])) && string.IsNullOrEmpty(Text(message["pendingRun"]))
                    && message["outcomePending"]?.Type == JTokenType.Boolean && !message.Value<bool>("outcomePending"))
                    _saves?.Archive.QueueSettledBookRunCleanup(Text(message["activeSlot"]));
                if (state && request.Kind == "return" && _returnPresentation != null)
                {
                    var receipt = (JObject)message.DeepClone();
                    Action presentReturn = () => _returnPresentation(request.Instance, receipt);
                    if (_invoke == null) presentReturn(); else _invoke(presentReturn);
                }
                JObject result = state || rejected ? (JObject)message.DeepClone()
                    : new JObject { ["success"] = false, ["error"] = "malformed_response" };
                if (state && message.Value<bool>("success") && phase == "editing" && request.Cmd == "snapshot"
                    && message.Value<bool>("canSwitch") && !message.Value<bool>("inRun") && _unresolved == null
                    && string.IsNullOrEmpty(Text(message["pendingRun"]))
                    && message["outcomePending"]?.Type == JTokenType.Boolean && !message.Value<bool>("outcomePending"))
                { _originalInstance = request.Instance; _originalToken = request.Token; }
                else RevokeOriginal();
                result.Remove("task"); Send(result, call.WebCallId, request.Cmd, request.Instance);
            }
            respond?.Invoke(null);
        }
        private void Ended(PanelPendingCall<Request> call, PanelPendingCallEndReason reason)
        {
            lock (_gate)
            {
                if (call.Context.IsWrite) _writePending = false;
                RevokeOriginal();
                if (reason != PanelPendingCallEndReason.Cleared)
                    Send(new JObject { ["success"] = false, ["error"] = reason == PanelPendingCallEndReason.Timeout ? "timeout" : "disconnected" },
                        call.WebCallId, call.Context.Cmd, call.Context.Instance);
            }
        }
        private static bool BoundedInteger(JToken value, long maximum)
            => value?.Type == JTokenType.Integer && long.TryParse(value.ToString(), out long number) && number >= 0 && number <= maximum;
        private static bool ValidResult(JObject result, bool pending)
        {
            if (result == null || !Exact(result, "runId", "bookId", "outcome", "elapsedMs", "completedAt", "sp", "reason", "debug")) return false;
            return Text(result["runId"]) is string run && SaveSlotKey.IsValidExisting(run)
                && Text(result["bookId"]) == "repair-campus"
                && new[] { "victory", "failure", "defeat", "retreat", "abandoned" }.Contains(Text(result["outcome"]))
                && BoundedInteger(result["elapsedMs"], 86399999) && BoundedInteger(result["completedAt"], 9007199254740991)
                && BoundedInteger(result["sp"], 1000000) && result["debug"]?.Type == JTokenType.Boolean
                && (new[] { "first_clear", "personal_best", "clear", "debug", "incomplete" }.Contains(Text(result["reason"]))
                    || pending && Text(result["reason"]) == "pending" && result.Value<int>("sp") == 0);
        }
        private static bool ValidRecords(JObject records)
            => records != null && Exact(records, "bestMs", "clears", "history")
                && BoundedInteger(records["bestMs"], 86399999) && BoundedInteger(records["clears"], 9007199254740991)
                && records["history"] is JArray history && history.Count <= 20 && history.All(r => ValidResult(r as JObject, false))
                && history.Select(r => Text(r["runId"])).Distinct(StringComparer.Ordinal).Count() == history.Count;
        private void RejectAndRemember(string call, string cmd, string instance, string error)
        { if (_pending.TryRememberRejected(call)) Send(new JObject { ["success"] = false, ["error"] = error }, call, cmd, instance); }
        private void Send(JObject result, string call, string cmd, string instance)
        {
            result["type"] = "panel_resp"; result["panel"] = result["domain"] = "bookshelf";
            result["callId"] = call; result["cmd"] = cmd; result["panelInstanceId"] = instance;
            result["requiresReconcile"] = _unresolved != null; result["recoveryToken"] = _unresolved;
            string text = result.ToString(Formatting.None);
            Action send = () => { if (!_disposed) _post?.Invoke(text); };
            if (_invoke == null) send(); else _invoke(send);
        }
        private static string Text(JToken value) => value?.Type == JTokenType.String ? value.Value<string>() : null;
        private static bool Token(JToken value) => Text(value) is string token && token.StartsWith("bookshelf.", StringComparison.Ordinal) && Id.IsMatch(token);
        private static bool Exact(JObject value, params string[] keys) => value != null && value.Count == keys.Length && keys.All(k => value.Property(k) != null);
    }
}
