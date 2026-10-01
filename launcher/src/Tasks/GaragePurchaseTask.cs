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
    /// <summary>车库付费服务桥；复用请求生命周期，AS2 token 拥有一次性购车与保存恢复。</summary>
    public sealed class GaragePurchaseTask : IDisposable
    {
        private sealed class PendingRequest
        {
            public string WebCmd;
            public string Operation;
            public string Token;
            public string InstanceId;
            public bool IsWrite;
            public JObject Draft;
            public string SnapshotVehicleId;
        }

        private static readonly Regex SafeId = new Regex("^[A-Za-z0-9._~-]{1,128}$", RegexOptions.Compiled);
        private static readonly HashSet<string> DefinitiveErrors = new HashSet<string>(StringComparer.Ordinal)
        { "unsupported_cmd", "unsupported_version", "invalid_payload", "invalid_vehicle", "catalog_invalid", "catalog_changed",
          "invalid_balance", "actor_unavailable", "infrastructure_unavailable", "save_unavailable", "currency_unavailable",
          "insufficient_funds", "driving_required" };
        private static readonly HashSet<string> VehicleIds = new HashSet<string>(StringComparer.Ordinal)
        { "bicycle", "motorcycle", "offroad" };
        public static bool ValidVehicleId(string id) => id != null && VehicleIds.Contains(id);
        private readonly PanelPendingCallTracker<PendingRequest> _pendingCalls;
        private readonly object _gate = new object();
        private Action<string> _postToWeb;
        private Action<Action> _invokeOnUI;
        private string _unresolvedToken;
        private JObject _frozenDraft;
        private bool _writePending;
        private bool _requiresQuery;

        public GaragePurchaseTask(XmlSocketServer socket) : this(
            () => socket != null && socket.IsClientReady,
            payload => socket != null && socket.TrySend(payload)) { }

        public GaragePurchaseTask(Func<bool> isReady, Func<string, bool> trySend, int timeoutMs = 10000)
        {
            _pendingCalls = new PanelPendingCallTracker<PendingRequest>(isReady, payload =>
            {
                try { return trySend != null && trySend(payload); }
                catch (Exception error) { LogManager.Log("[GaragePurchase] delivery unknown: " + error.GetType().Name); return false; }
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
            if (!string.Equals(parsed.Value<string>("domain"), "garage", StringComparison.Ordinal))
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
                    Draft = normalized["draft"] as JObject,
                    SnapshotVehicleId = ReadString(normalized["vehicleId"])
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
                if (stateValid && ReadString(message["token"]) == _unresolvedToken && _frozenDraft != null
                    && !JToken.DeepEquals(_frozenDraft, message["draft"])) stateValid = false;
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
                response["panel"] = "garage";
                response["domain"] = "garage";
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
                case "snapshot": action = "garagePurchaseSnapshot"; return true;
                case "query": action = "garagePurchaseQuery"; return true;
                case "commit": action = "garagePurchaseCommit"; isWrite = true; return true;
                default: return false;
            }
        }

        private static bool TryNormalizePayload(string cmd, JObject payload, out JObject normalized)
        {
            normalized = null;
            if (payload == null || !Integer(payload["v"], 1, 1)) return false;
            if (cmd == "snapshot")
            {
                if (!Exact(payload, "v", "vehicleId") || !ValidVehicleId(ReadString(payload["vehicleId"]))) return false;
            }
            else
            {
                string token = ReadString(payload["token"]);
                if (token == null || !SafeId.IsMatch(token)) return false;
                if (cmd == "query" && !Exact(payload, "v", "token")) return false;
                if (cmd == "commit" && (!Exact(payload, "v", "token", "draft") || !ValidDraft(payload["draft"] as JObject))) return false;
            }
            normalized = (JObject)payload.DeepClone();
            return true;
        }

        private static bool IsStateResponse(JObject value, PendingRequest entry)
        {
            if (value == null || !Integer(value["v"], 1, 1) || ReadString(value["operation"]) != entry.Operation
                || value["success"]?.Type != JTokenType.Boolean || value["changed"]?.Type != JTokenType.Boolean
                || value["saved"]?.Type != JTokenType.Boolean || value["owned"]?.Type != JTokenType.Boolean
                || value["canPurchase"]?.Type != JTokenType.Boolean || !ValidDraft(value["draft"] as JObject)
                || !ValidVehicleId(ReadString(value["vehicleId"])) || ReadString(value["draft"]?["vehicleId"]) != ReadString(value["vehicleId"])
                || !Text(value["name"], 1, 160) || !Description(value["description"])
                || !Integer(value["cost"], 1, 9007199254740991) || !Integer(value["balance"], 0, 9007199254740991)
                || !Integer(value["requiredDrivingLevel"], 0, 2) || !Integer(value["drivingLevel"], 0, 9007199254740991)) return false;
            string token = ReadString(value["token"]);
            if (token == null || !SafeId.IsMatch(token) || (entry.Token != null && token != entry.Token)) return false;
            bool owned = value.Value<bool>("owned"), changed = value.Value<bool>("changed"), saved = value.Value<bool>("saved"), success = value.Value<bool>("success");
            bool eligible = !owned && value.Value<long>("balance") >= value.Value<long>("cost")
                && value.Value<long>("drivingLevel") >= value.Value<long>("requiredDrivingLevel");
            if (value.Value<bool>("canPurchase") != eligible) return false;
            if (entry.IsWrite && !JToken.DeepEquals(entry.Draft, value["draft"])) return false;
            string phase = ReadString(value["phase"]);
            if (entry.SnapshotVehicleId != null && phase != "save_pending"
                && ReadString(value["vehicleId"]) != entry.SnapshotVehicleId) return false;
            if (phase == "editing") return !entry.IsWrite && success && !owned && !changed && !saved;
            if (phase == "owned") return success && owned && !changed && !saved;
            if (phase == "applied") return success && owned && changed && saved;
            return phase == "save_pending" && !success && owned && changed && !saved && ReadString(value["error"]) == "save_pending";
        }
        internal static bool ValidDraft(JObject draft) => Exact(draft, "vehicleId") && ValidVehicleId(ReadString(draft["vehicleId"]));

        private static bool Exact(JObject value, params string[] keys)
        {
            return value != null && value.Properties().Count() == keys.Length && keys.All(k => value.Property(k, StringComparison.Ordinal) != null);
        }
        private static string ReadString(JToken value) { return value?.Type == JTokenType.String ? value.Value<string>() : null; }
        private static bool Description(JToken value)
        {
            string text = ReadString(value);
            return text != null && text.Length <= 8192 && !text.Any(c => char.IsControl(c) && c != '\n' && c != '\r' && c != '\t');
        }
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
            Post(new JObject { ["type"] = "panel_resp", ["panel"] = "garage", ["domain"] = "garage", ["cmd"] = cmd,
                ["callId"] = callId, ["success"] = false, ["error"] = error,
                ["requiresReconcile"] = error == "reconcile_required", ["token"] = error == "reconcile_required" ? _unresolvedToken : null });
        }
        private void HandlePendingEnded(PanelPendingCall<PendingRequest> call, PanelPendingCallEndReason reason)
        {
            lock (_gate) if (call.Context.IsWrite) { _writePending = false; _requiresQuery = true; }
            if (reason == PanelPendingCallEndReason.Cleared) return;
            Post(new JObject { ["type"] = "panel_resp", ["panel"] = "garage", ["domain"] = "garage", ["cmd"] = call.Context.WebCmd,
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
