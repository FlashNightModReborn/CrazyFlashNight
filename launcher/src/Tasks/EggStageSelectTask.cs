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
    /// <summary>
    /// U7 彩蛋地图选关的 Host 传输边界。AS2 EggSelectPanelService 保留彩蛋进度门与进关权威；
    /// enter 不写存档，重复进入由 AS2 的 StageRunSession reservation 拒绝。
    /// </summary>
    public sealed class EggStageSelectTask : IDisposable
    {
        private sealed class PendingRequest
        {
            public string Cmd;
            public string Instance;
            public bool IsWrite;
        }

        private static readonly Regex SafeId = new Regex("^[A-Za-z0-9._~-]{1,128}$", RegexOptions.Compiled);
        private static readonly HashSet<string> DefinitiveErrors = new HashSet<string>(StringComparer.Ordinal)
        { "unsupported_cmd", "unsupported_version", "invalid_payload", "unknown_destination",
          "locked", "stage_config_unavailable", "stage_config_failed", "pending_stage_settlement", "enter_refused" };
        private static readonly HashSet<string> DestinationIds = new HashSet<string>(StringComparer.Ordinal)
        { "forest_depth", "machine_zone", "forest_center" };
        private static readonly HashSet<string> Difficulties = new HashSet<string>(StringComparer.Ordinal)
        { "简单", "冒险", "修罗", "地狱" };
        private readonly PanelPendingCallTracker<PendingRequest> _pendingCalls;
        private readonly object _gate = new object();
        private Action<string> _postToWeb;
        private Action<Action> _invokeOnUI;
        private bool _enterInFlight;
        private bool _disposed;

        public EggStageSelectTask(XmlSocketServer socket) : this(
            () => socket != null && socket.IsClientReady,
            payload => socket != null && socket.TrySend(payload)) { }

        public EggStageSelectTask(Func<bool> isReady, Func<string, bool> trySend, int timeoutMs = 10000)
        {
            _pendingCalls = new PanelPendingCallTracker<PendingRequest>(isReady, payload =>
            {
                try { return trySend != null && trySend(payload); }
                catch (Exception error) { LogManager.Log("[EggStageSelect] delivery unknown: " + error.GetType().Name); return false; }
            }, timeoutMs, HandlePendingEnded);
        }

        public void SetPostToWeb(Action<string> post) { _postToWeb = post; }
        public void SetInvoker(Action<Action> invoker) { _invokeOnUI = invoker; }
        public void ClearPending() { lock (_gate) { _enterInFlight = false; _pendingCalls.Clear(); } }
        public void Dispose() { lock (_gate) { _disposed = true; _pendingCalls.Dispose(); } }

        public void HandleWebRequest(string cmd, JObject parsed)
        {
            string callId = ReadString(parsed?["callId"]);
            if (callId == null || !SafeId.IsMatch(callId)) return;
            if (_pendingCalls.IsKnownWebCallId(callId)) return;
            if (parsed["domain"]?.Type != JTokenType.String) { RejectAndRemember(callId, cmd, "unsupported_domain"); return; }
            if (!string.Equals(parsed.Value<string>("domain"), "egg_stage_select", StringComparison.Ordinal))
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
                if (isWrite && _enterInFlight) { RejectAndRemember(callId, cmd, "busy"); return; }
                var entry = new PendingRequest
                {
                    Cmd = cmd, IsWrite = isWrite,
                    Instance = ReadString(parsed["panelInstanceId"])
                };
                if (!_pendingCalls.TryBegin(callId, entry, out fid)) return;
                if (isWrite) _enterInFlight = true;
            }
            _pendingCalls.Send(fid, PanelBridge.BuildFlashCommand(action, fid, normalized).ToString(Formatting.None) + "\0");
        }

        private static bool TryResolveCommand(string cmd, out string action, out bool isWrite)
        {
            action = null; isWrite = false;
            switch (cmd)
            {
                case "snapshot": action = "eggSelectSnapshot"; return true;
                case "enter": action = "eggSelectEnter"; isWrite = true; return true;
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
                if (!Exact(payload, "v", "destinationId")
                    || !DestinationIds.Contains(ReadString(payload["destinationId"]) ?? "")) return false;
            }
            normalized = (JObject)payload.DeepClone();
            return true;
        }

        public void HandleFlashResponse(JObject message, Action<string> respond)
        {
            int fid = Integer(message?["callId"], 1, int.MaxValue) ? message.Value<int>("callId") : 0;
            PanelPendingCall<PendingRequest> call;
            JObject response;
            lock (_gate)
            {
                if (!_pendingCalls.TryComplete(fid, out call)) { respond?.Invoke(null); return; }
                PendingRequest entry = call.Context;
                if (entry.IsWrite) _enterInFlight = false;
                if (IsValidResponse(message, entry)) response = (JObject)message.DeepClone();
                else response = new JObject { ["success"] = false, ["error"] = "malformed_response" };
                response.Remove("task");
                response["type"] = "panel_resp";
                response["panel"] = "egg-stage-select";
                response["domain"] = "egg_stage_select";
                response["cmd"] = entry.Cmd;
                response["callId"] = call.WebCallId;
                response["panelInstanceId"] = entry.Instance;
            }
            Post(response);
            respond?.Invoke(null);
        }

        private static bool IsValidResponse(JObject value, PendingRequest entry)
        {
            if (value == null || !Integer(value["v"], 1, 1) || ReadString(value["operation"]) != entry.Cmd
                || value["success"]?.Type != JTokenType.Boolean) return false;
            if (value.Value<bool>("success") != true)
                return DefinitiveErrors.Contains(ReadString(value["error"]) ?? "");
            if (entry.Cmd == "snapshot") return IsValidSnapshot(value);
            return value["closePanel"]?.Type == JTokenType.Boolean && value.Value<bool>("closePanel")
                && Text(value["stageName"], 1, 96) && Difficulties.Contains(ReadString(value["difficulty"]) ?? "")
                && DestinationIds.Contains(ReadString(value["destinationId"]) ?? "");
        }

        private static bool IsValidSnapshot(JObject value)
        {
            JObject progress = value["progress"] as JObject;
            if (progress == null || !Integer(progress["main"], 0, 9007199254740991)
                || !Integer(progress["egg"], 0, 9007199254740991)) return false;
            JArray destinations = value["destinations"] as JArray;
            if (destinations == null || destinations.Count != 3) return false;
            var seen = new HashSet<string>(StringComparer.Ordinal);
            foreach (JToken destinationToken in destinations)
            {
                JObject destination = destinationToken as JObject;
                if (destination == null
                    || !Exact(destination, "id", "name", "stageName", "difficulty", "unlocked", "hintLocked", "lockReason")) return false;
                string id = ReadString(destination["id"]);
                if (id == null || !DestinationIds.Contains(id) || !seen.Add(id)) return false;
                if (!Text(destination["name"], 1, 64) || !Text(destination["stageName"], 1, 96)
                    || !Difficulties.Contains(ReadString(destination["difficulty"]) ?? "")) return false;
                if (destination["unlocked"]?.Type != JTokenType.Boolean
                    || destination["hintLocked"]?.Type != JTokenType.Boolean) return false;
                string lockReason = ReadString(destination["lockReason"]);
                if (lockReason == null || lockReason.Length > 256 || lockReason.Any(char.IsControl)) return false;
                if (destination.Value<bool>("unlocked") && lockReason != "") return false;
            }
            return true;
        }

        private void RejectAndRemember(string callId, string cmd, string error)
        {
            if (!_pendingCalls.TryRememberRejected(callId)) return;
            Post(new JObject { ["type"] = "panel_resp", ["panel"] = "egg-stage-select", ["domain"] = "egg_stage_select",
                ["cmd"] = cmd, ["callId"] = callId, ["success"] = false, ["error"] = error });
        }
        private void HandlePendingEnded(PanelPendingCall<PendingRequest> call, PanelPendingCallEndReason reason)
        {
            lock (_gate) { if (call.Context.IsWrite) _enterInFlight = false; }
            if (reason == PanelPendingCallEndReason.Cleared) return;
            Post(new JObject { ["type"] = "panel_resp", ["panel"] = "egg-stage-select", ["domain"] = "egg_stage_select",
                ["cmd"] = call.Context.Cmd, ["callId"] = call.WebCallId, ["panelInstanceId"] = call.Context.Instance,
                ["success"] = false,
                ["error"] = reason == PanelPendingCallEndReason.Timeout ? "timeout" : "disconnected",
                ["enterUnknown"] = call.Context.IsWrite });
        }
        private void Post(JObject response)
        {
            string text = response.ToString(Formatting.None);
            Action send = () => { if (!_disposed) _postToWeb?.Invoke(text); };
            if (_invokeOnUI != null) _invokeOnUI(send); else send();
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
    }
}
