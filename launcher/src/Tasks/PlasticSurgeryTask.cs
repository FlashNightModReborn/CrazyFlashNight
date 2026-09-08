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
    /// <summary>整形领域的严格传输桥。AS2 token 独占业务幂等；未知写只查询原 token。</summary>
    public sealed class PlasticSurgeryTask : IDisposable
    {
        private sealed class PendingRequest
        {
            public string WebCmd;
            public string Operation;
            public string Token;
            public string InstanceId;
            public bool IsWrite;
            public JObject Draft;
        }

        private static readonly Regex SafeId = new Regex("^[A-Za-z0-9._~-]{1,128}$", RegexOptions.Compiled);
        private static readonly HashSet<string> DefinitiveErrors = new HashSet<string>(StringComparer.Ordinal)
        {
            "unsupported_cmd", "unsupported_version", "invalid_payload", "invalid_character_name",
            "invalid_gender", "invalid_height", "invalid_balance", "actor_unavailable",
            "save_unavailable", "currency_unavailable", "stale_state", "no_change",
            "insufficient_funds", "refresh_failed"
        };
        private static readonly HashSet<string> Slots = new HashSet<string>(StringComparer.Ordinal)
        {
            "头部装备", "上装装备", "下装装备", "手部装备", "脚部装备", "颈部装备",
            "长枪", "手枪", "手枪2", "刀", "手雷"
        };
        private readonly PanelPendingCallTracker<PendingRequest> _pendingCalls;
        private readonly object _gate = new object();
        private Action<string> _postToWeb;
        private Action<Action> _invokeOnUI;
        private string _unresolvedToken;
        private JObject _frozenDraft;
        private bool _writePending;
        private bool _requiresQuery;

        public PlasticSurgeryTask(XmlSocketServer socket) : this(
            () => socket != null && socket.IsClientReady,
            payload => socket != null && socket.TrySend(payload)) { }

        public PlasticSurgeryTask(Func<bool> isReady, Func<string, bool> trySend, int timeoutMs = 10000)
        {
            _pendingCalls = new PanelPendingCallTracker<PendingRequest>(isReady, payload =>
            {
                try { return trySend != null && trySend(payload); }
                catch (Exception error) { LogManager.Log("[PlasticSurgery] delivery unknown: " + error.GetType().Name); return false; }
            }, timeoutMs, HandlePendingEnded);
        }

        public void SetPostToWeb(Action<string> post) { _postToWeb = post; }
        public void SetInvoker(Action<Action> invoker) { _invokeOnUI = invoker; }
        public void ClearPending() { lock (_gate) _pendingCalls.Clear(); }
        public void Dispose() { lock (_gate) _pendingCalls.Dispose(); }

        public void HandleWebRequest(string cmd, JObject parsed)
        {
            string callId = ReadString(parsed?["callId"]);
            if (callId == null || !SafeId.IsMatch(callId)) return;
            if (_pendingCalls.IsKnownWebCallId(callId)) return;
            if (parsed["domain"]?.Type != JTokenType.String) { RejectAndRemember(callId, cmd, "unsupported_domain"); return; }
            if (!string.Equals(parsed.Value<string>("domain"), "surgery", StringComparison.Ordinal))
            { RejectAndRemember(callId, cmd, "unsupported_domain"); return; }
            string action;
            bool isWrite;
            if (!TryResolveCommand(cmd, out action, out isWrite)) { RejectAndRemember(callId, cmd, "unsupported_cmd"); return; }
            JObject normalized;
            if (!TryNormalizePayload(cmd, parsed["payload"] as JObject, out normalized)) { RejectAndRemember(callId, cmd, "invalid_payload"); return; }
            if (!_pendingCalls.IsReady()) { RejectAndRemember(callId, cmd, "disconnected"); return; }

            int fid;
            lock (_gate)
            {
                if (_writePending) { RejectAndRemember(callId, cmd, "busy"); return; }
                if (isWrite && (_requiresQuery || (_unresolvedToken != null
                        && (ReadString(normalized["token"]) != _unresolvedToken
                            || !JToken.DeepEquals(normalized["draft"], _frozenDraft)))))
                {
                    RejectAndRemember(callId, cmd, "reconcile_required");
                    return;
                }
                string operation = cmd;
                // 明确要求 Web 查询旧 token，不把 snapshot 隐式改写成另一种命令。
                if (cmd == "snapshot" && _unresolvedToken != null)
                {
                    RejectAndRemember(callId, cmd, "reconcile_required");
                    return;
                }
                var entry = new PendingRequest
                {
                    WebCmd = cmd, Operation = operation, IsWrite = isWrite,
                    Token = ReadString(normalized["token"]),
                    InstanceId = ReadString(parsed["panelInstanceId"]),
                    Draft = normalized["draft"] as JObject
                };
                if (!_pendingCalls.TryBegin(callId, entry, out fid)) return;
                if (isWrite)
                {
                    _writePending = true;
                    _unresolvedToken = entry.Token;
                    _frozenDraft = (JObject)entry.Draft.DeepClone();
                }
            }
            _pendingCalls.Send(fid, PanelBridge.BuildFlashCommand(action, fid, normalized).ToString(Formatting.None) + "\0");
        }

        public void HandleFlashResponse(JObject message, Action<string> respond)
        {
            int fid = 0;
            if (Integer(message?["callId"], 1, int.MaxValue)) fid = message["callId"].Value<int>();
            PanelPendingCall<PendingRequest> call;
            JObject response;
            lock (_gate)
            {
                if (!_pendingCalls.TryComplete(fid, out call)) { respond?.Invoke(null); return; }
                PendingRequest entry = call.Context;
                if (entry.IsWrite) _writePending = false;
                bool stateValid = IsStateResponse(message, entry);
                bool definitive = !stateValid && message?["success"]?.Type == JTokenType.Boolean
                    && message.Value<bool>("success") == false && message?["v"]?.Type == JTokenType.Integer
                    && message.Value<int>("v") == 1 && DefinitiveErrors.Contains(ReadString(message["error"]) ?? "");
                if (stateValid)
                {
                    response = (JObject)message.DeepClone();
                    string phase = message.Value<string>("phase");
                    string token = message.Value<string>("token");
                    if (token == _unresolvedToken)
                    {
                        _requiresQuery = false;
                        if (phase == "save_pending") _frozenDraft = (JObject)message["draft"].DeepClone();
                        else { _unresolvedToken = null; _frozenDraft = null; }
                    }
                    if (phase == "save_pending")
                    {
                        _requiresQuery = false;
                        _unresolvedToken = token;
                        _frozenDraft = (JObject)message["draft"].DeepClone();
                    }
                }
                else
                {
                    if (entry.IsWrite) _requiresQuery = true;
                    response = new JObject
                    {
                        ["success"] = false,
                        ["error"] = definitive ? ReadString(message["error"]) : "malformed_response",
                        ["requiresReconcile"] = entry.IsWrite || _unresolvedToken != null
                    };
                    if (definitive && entry.IsWrite && entry.Token == _unresolvedToken)
                    {
                        _unresolvedToken = null; _frozenDraft = null;
                        _requiresQuery = false;
                        response["requiresReconcile"] = false;
                    }
                }
                response.Remove("task");
                response["type"] = "panel_resp";
                response["panel"] = "surgery";
                response["domain"] = "surgery";
                response["cmd"] = entry.WebCmd;
                response["callId"] = call.WebCallId;
                response["panelInstanceId"] = entry.InstanceId;
            }
            Post(response);
            respond?.Invoke(null);
        }

        private static bool TryResolveCommand(string cmd, out string action, out bool isWrite)
        {
            action = null; isWrite = false;
            switch (cmd)
            {
                case "snapshot": action = "plasticSurgerySnapshot"; return true;
                case "query": action = "plasticSurgeryQuery"; return true;
                case "commit": action = "plasticSurgeryCommit"; isWrite = true; return true;
                default: return false;
            }
        }

        private static bool TryNormalizePayload(string cmd, JObject payload, out JObject normalized)
        {
            normalized = null;
            if (payload == null || !Integer(payload["v"], 1, 1)) return false;
            if (cmd == "snapshot")
            {
                if (!Exact(payload, "v")) return false;
            }
            else
            {
                string token = ReadString(payload["token"]);
                if (token == null || !SafeId.IsMatch(token)) return false;
                if (cmd == "query" && !Exact(payload, "v", "token")) return false;
                if (cmd == "commit" && (!Exact(payload, "v", "token", "draft") || !ValidProfile(payload["draft"] as JObject))) return false;
            }
            normalized = (JObject)payload.DeepClone();
            return true;
        }

        private static bool IsStateResponse(JObject value, PendingRequest entry)
        {
            if (value == null || !Integer(value["v"], 1, 1)
                    || ReadString(value["operation"]) != entry.Operation
                    || value["success"]?.Type != JTokenType.Boolean
                    || value["changed"]?.Type != JTokenType.Boolean || value["saved"]?.Type != JTokenType.Boolean
                    || !ValidProfile(value["current"] as JObject) || !ValidProfile(value["draft"] as JObject)
                    || !Integer(value["cost"], 5, 5) || !Integer(value["balance"], 0, 9007199254740991)) return false;
            string token = ReadString(value["token"]);
            if (token == null || !SafeId.IsMatch(token) || (entry.Token != null && token != entry.Token)) return false;
            var portrait = value["portrait"] as JObject;
            var equipment = portrait?["equipment"] as JObject;
            if (equipment == null || !Text(portrait["hair"], 0, 160) || !Text(portrait["face"], 0, 160)
                    || equipment.Properties().Any(p => !Slots.Contains(p.Name) || !Text(p.Value, 1, 160))) return false;
            string phase = ReadString(value["phase"]);
            bool success = value.Value<bool>("success"), changed = value.Value<bool>("changed"), saved = value.Value<bool>("saved");
            if (phase == "editing") return !entry.IsWrite && success && !changed && !saved;
            if (phase != "applied" && phase != "save_pending") return false;
            if (!JToken.DeepEquals(value["current"], value["draft"])) return false;
            if (entry.IsWrite && !JToken.DeepEquals(entry.Draft, value["draft"])) return false;
            return changed && (phase == "applied" ? success && saved : !success && !saved && ReadString(value["error"]) == "save_pending");
        }

        internal static bool ValidProfile(JObject profile)
        {
            if (!Exact(profile, "characterName", "gender", "height") || !Text(profile["characterName"], 1, 15)
                    || string.IsNullOrWhiteSpace(profile.Value<string>("characterName"))) return false;
            string gender = ReadString(profile["gender"]);
            return (gender == "male" || gender == "female") && Integer(profile["height"], 150, 200);
        }

        private static bool Exact(JObject value, params string[] keys)
        {
            return value != null && value.Properties().Count() == keys.Length && keys.All(k => value.Property(k, StringComparison.Ordinal) != null);
        }
        private static string ReadString(JToken value) { return value?.Type == JTokenType.String ? value.Value<string>() : null; }
        private static bool Text(JToken value, int min, int max)
        {
            string text = ReadString(value);
            return text != null && text.Length >= min && text.Length <= max && !text.Any(char.IsControl);
        }
        private static bool Integer(JToken value, long min, long max)
        {
            if (value?.Type != JTokenType.Integer) return false;
            try { long n = value.Value<long>(); return n >= min && n <= max; } catch (OverflowException) { return false; }
        }
        private void RejectAndRemember(string callId, string cmd, string error)
        {
            if (!_pendingCalls.TryRememberRejected(callId)) return;
            Post(new JObject { ["type"] = "panel_resp", ["panel"] = "surgery", ["domain"] = "surgery", ["cmd"] = cmd,
                ["callId"] = callId, ["success"] = false, ["error"] = error,
                ["requiresReconcile"] = error == "reconcile_required", ["token"] = error == "reconcile_required" ? _unresolvedToken : null });
        }
        private void HandlePendingEnded(PanelPendingCall<PendingRequest> call, PanelPendingCallEndReason reason)
        {
            lock (_gate) if (call.Context.IsWrite) { _writePending = false; _requiresQuery = true; }
            if (reason == PanelPendingCallEndReason.Cleared) return;
            Post(new JObject { ["type"] = "panel_resp", ["panel"] = "surgery", ["domain"] = "surgery", ["cmd"] = call.Context.WebCmd,
                ["callId"] = call.WebCallId, ["panelInstanceId"] = call.Context.InstanceId, ["success"] = false,
                ["error"] = reason == PanelPendingCallEndReason.Timeout ? "timeout" : "disconnected", ["requiresReconcile"] = call.Context.IsWrite });
        }
        private void Post(JObject response)
        {
            string text = response.ToString(Formatting.None);
            if (_invokeOnUI != null) _invokeOnUI(() => _postToWeb?.Invoke(text));
            else _postToWeb?.Invoke(text);
        }
    }
}
