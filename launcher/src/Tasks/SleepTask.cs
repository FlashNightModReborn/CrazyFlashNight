using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;
using CF7Launcher.Bus;
using CF7Launcher.Guardian;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Tasks
{
    /// <summary>睡眠传输边界。AS2 持有床铺会话和一次性跳时；未知提交只查询。</summary>
    public sealed class SleepTask : IDisposable
    {
        private sealed class PendingRequest
        {
            public string Cmd, Token, Instance;
            public int? Target;
            public bool IsWrite;
        }
        private static readonly Regex SafeId = new Regex("^[A-Za-z0-9._~-]{1,128}$", RegexOptions.Compiled);
        private static readonly HashSet<string> DefinitiveErrors = new HashSet<string>(StringComparer.Ordinal)
        { "unsupported_cmd", "unsupported_version", "invalid_payload", "stale_token", "token_conflict", "cycle_disabled", "clock_unavailable" };
        private readonly object _gate = new object();
        private readonly PanelPendingCallTracker<PendingRequest> _pending;
        private Action<string> _post;
        private Action<Action> _invoke;
        private string _unresolvedToken;
        private int? _unresolvedTarget;
        private bool _writePending, _disposed;

        public SleepTask(XmlSocketServer socket) : this(
            () => socket != null && socket.IsClientReady,
            text => socket != null && socket.TrySend(text)) { }
        public SleepTask(Func<bool> ready, Func<string, bool> send, int timeoutMs = 10000)
        {
            _pending = new PanelPendingCallTracker<PendingRequest>(ready, text =>
            {
                try { return send != null && send(text); }
                catch (Exception error) { LogManager.Log("[Sleep] delivery unknown: " + error.GetType().Name); return false; }
            }, timeoutMs, OnPendingEnded);
        }
        public void SetPostToWeb(Action<string> post) { _post = post; }
        public void SetInvoker(Action<Action> invoke) { _invoke = invoke; }
        public void ClearPending() { lock (_gate) _pending.Clear(); }
        public void Dispose() { lock (_gate) { _disposed = true; _pending.Dispose(); } }

        internal static JObject BuildOpenData(string source, string extras)
        {
            if (source != "world_sleep" || string.IsNullOrEmpty(extras)) return null;
            JObject data;
            try { data = JObject.Parse(extras); } catch (JsonException) { return null; }
            if (!Exact(data, "token") || !ValidToken(data["token"])) return null;
            return new JObject { ["source"] = source, ["mode"] = "runtime", ["token"] = data["token"] };
        }

        public void HandleWebRequest(string cmd, JObject parsed)
        {
            string callId = Text(parsed?["callId"]), instance = Text(parsed?["panelInstanceId"]);
            if (callId == null || !SafeId.IsMatch(callId) || _pending.IsKnownWebCallId(callId)) return;
            if (parsed["domain"]?.Type != JTokenType.String) { RejectAndRemember(callId, cmd, instance, "unsupported_domain"); return; }
            if (!string.Equals(parsed.Value<string>("domain"), "sleep", StringComparison.Ordinal)) { RejectAndRemember(callId, cmd, instance, "unsupported_domain"); return; }
            if (Text(parsed?["panel"]) != "sleep"
                    || instance == null || !SafeId.IsMatch(instance)) { RejectAndRemember(callId, cmd, instance, "invalid_owner"); return; }
            string action;
            bool isWrite;
            if (!TryResolveCommand(cmd, out action, out isWrite)) { RejectAndRemember(callId, cmd, instance, "unsupported_cmd"); return; }
            var payload = parsed["payload"] as JObject;
            if (!Exact(payload, isWrite ? new[] { "v", "token", "targetMinutes" } : new[] { "v", "token" })
                    || !Integer(payload?["v"], 1, 1) || !ValidToken(payload?["token"])
                    || (isWrite && !Integer(payload["targetMinutes"], 0, 1439)))
            { RejectAndRemember(callId, cmd, instance, "invalid_payload"); return; }
            if (!_pending.IsReady()) { RejectAndRemember(callId, cmd, instance, "disconnected"); return; }
            JObject normalized = (JObject)payload.DeepClone();
            int fid;
            lock (_gate)
            {
                if (_writePending) { RejectAndRemember(callId, cmd, instance, "busy"); return; }
                if (_unresolvedToken != null && (isWrite || cmd != "query" || Text(payload["token"]) != _unresolvedToken))
                { RejectAndRemember(callId, cmd, instance, "reconcile_required"); return; }
                var entry = new PendingRequest { Cmd = cmd, Token = Text(payload["token"]), Instance = instance,
                    IsWrite = isWrite, Target = isWrite ? payload.Value<int>("targetMinutes") : (int?)null };
                if (!_pending.TryBegin(callId, entry, out fid)) return;
                if (isWrite) { _writePending = true; _unresolvedToken = entry.Token; _unresolvedTarget = entry.Target; }
            }
            _pending.Send(fid, PanelBridge.BuildFlashCommand(action, fid, normalized).ToString(Formatting.None) + "\0");
        }

        private static bool TryResolveCommand(string cmd, out string action, out bool isWrite)
        {
            action = null; isWrite = false;
            switch (cmd)
            {
                case "snapshot": action = "sleepSnapshot"; return true;
                case "commit": action = "sleepCommit"; isWrite = true; return true;
                case "query": action = "sleepQuery"; return true;
                default: return false;
            }
        }

        public void HandleFlashResponse(JObject message, Action<string> respond)
        {
            PanelPendingCall<PendingRequest> call;
            JObject response;
            lock (_gate)
            {
                int fid = Integer(message?["callId"], 1, int.MaxValue) ? message.Value<int>("callId") : 0;
                if (!_pending.TryComplete(fid, out call)) { respond?.Invoke(null); return; }
                var entry = call.Context;
                if (entry.IsWrite) _writePending = false;
                bool state = ValidState(message, entry);
                if (state && entry.Token == _unresolvedToken && Text(message["phase"]) == "applied"
                        && message.Value<int>("targetMinutes") != _unresolvedTarget) state = false;
                bool rejected = Integer(message?["v"], 1, 1) && Text(message?["operation"]) == entry.Cmd
                    && Text(message?["token"]) == entry.Token && message?["success"]?.Type == JTokenType.Boolean
                    && !message.Value<bool>("success") && DefinitiveErrors.Contains(Text(message["error"]) ?? "");
                if (state || rejected)
                {
                    response = (JObject)message.DeepClone();
                    // 只有原 token 的完整状态或本轮明确拒绝才能消除未知结果。
                    if (entry.Token == _unresolvedToken && (state || entry.IsWrite))
                    { _unresolvedToken = null; _unresolvedTarget = null; }
                }
                else response = new JObject { ["success"] = false, ["error"] = "malformed_response" };
                response["requiresReconcile"] = _unresolvedToken != null;
                if (_unresolvedToken != null) response["recoveryToken"] = _unresolvedToken;
                response.Remove("task");
                Envelope(response, call.WebCallId, entry.Cmd, entry.Instance);
            }
            Post(response);
            respond?.Invoke(null);
        }

        private static bool ValidState(JObject value, PendingRequest entry)
        {
            if (!Integer(value?["v"], 1, 1) || Text(value?["operation"]) != entry.Cmd || Text(value?["token"]) != entry.Token
                    || !Integer(value?["currentMinutes"], 0, 1439) || !Integer(value?["targetMinutes"], 0, 1439)
                    || new[] { "success", "changed", "cycleEnabled", "cyclePaused", "canSleep" }.Any(k => value[k]?.Type != JTokenType.Boolean)
                    || value["reason"]?.Type != JTokenType.String) return false;
            string phase = Text(value["phase"]), reason = Text(value["reason"]);
            bool success = value.Value<bool>("success"), changed = value.Value<bool>("changed"), canSleep = value.Value<bool>("canSleep");
            if (phase == "editing") return !entry.IsWrite && success && !changed && canSleep == value.Value<bool>("cycleEnabled")
                && reason == (canSleep ? "" : "cycle_disabled");
            if (phase == "expired") return !success && !changed && !canSleep && reason == "context_changed";
            return phase == "applied" && success && changed && !canSleep && reason == ""
                && value.Value<int>("targetMinutes") == value.Value<int>("currentMinutes")
                && (!entry.Target.HasValue || value.Value<int>("targetMinutes") == entry.Target.Value);
        }
        private void RejectAndRemember(string callId, string cmd, string instance, string error)
        {
            if (!_pending.TryRememberRejected(callId)) return;
            var result = new JObject { ["success"] = false, ["error"] = error,
                ["requiresReconcile"] = _unresolvedToken != null, ["recoveryToken"] = _unresolvedToken };
            Envelope(result, callId, cmd, instance); Post(result);
        }
        private void OnPendingEnded(PanelPendingCall<PendingRequest> call, PanelPendingCallEndReason reason)
        {
            lock (_gate)
            {
                if (call.Context.IsWrite) _writePending = false;
                if (reason == PanelPendingCallEndReason.Cleared) return;
                var result = new JObject { ["success"] = false,
                    ["error"] = reason == PanelPendingCallEndReason.Timeout ? "timeout" : "disconnected",
                    ["requiresReconcile"] = _unresolvedToken != null, ["recoveryToken"] = _unresolvedToken };
                Envelope(result, call.WebCallId, call.Context.Cmd, call.Context.Instance); Post(result);
            }
        }
        private static void Envelope(JObject value, string callId, string cmd, string instance)
        { value["type"] = "panel_resp"; value["panel"] = "sleep"; value["domain"] = "sleep"; value["cmd"] = cmd; value["callId"] = callId; value["panelInstanceId"] = instance; }
        private void Post(JObject value)
        {
            string text = value.ToString(Formatting.None);
            Action send = () => { if (!_disposed) _post?.Invoke(text); };
            if (_invoke != null) _invoke(send); else send();
        }
        private static string Text(JToken value) => value?.Type == JTokenType.String ? value.Value<string>() : null;
        private static bool ValidToken(JToken value) => Text(value) is string text && text.StartsWith("sleep.", StringComparison.Ordinal) && SafeId.IsMatch(text);
        private static bool Exact(JObject value, params string[] keys) => value != null && value.Properties().Count() == keys.Length && keys.All(k => value.Property(k, StringComparison.Ordinal) != null);
        private static bool Integer(JToken value, long min, long max)
        {
            if (value?.Type != JTokenType.Integer) return false;
            try { long number = value.Value<long>(); return number >= min && number <= max; } catch (OverflowException) { return false; }
        }
    }
}
