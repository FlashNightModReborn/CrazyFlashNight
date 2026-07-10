using System;
using System.Collections.Generic;
using System.Text.RegularExpressions;
using System.Threading;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using CF7Launcher.Bus;
using CF7Launcher.Guardian;

namespace CF7Launcher.Tasks
{
    /// <summary>
    /// inventory-domain WebView↔Flash 双层 callId 桥。
    /// Web 的 payload 不透传；每个 v1 命令都递归重建仅含白名单字段的 Flash 参数。
    /// </summary>
    public sealed class InventoryTask : IDisposable
    {
        private sealed class PendingRequest
        {
            public string WebCallId;
            public string WebCmd;
        }

        private const int DefaultTimeoutMs = 10000;
        private const int RecentCallIdCapacity = 256;
        private static readonly Regex ValidCallId = new Regex(
            "^[A-Za-z0-9._-]{1,96}$",
            RegexOptions.CultureInvariant | RegexOptions.Compiled);
        private static readonly Regex ValidLease = new Regex(
            "^[A-Za-z0-9._-]{1,128}$",
            RegexOptions.CultureInvariant | RegexOptions.Compiled);

        private readonly Func<bool> _isClientReady;
        private readonly Func<string, bool> _trySend;
        private readonly int _timeoutMs;
        private Action<string> _postToWeb;
        private Action<Action> _invokeOnUI;
        private readonly Dictionary<int, PendingRequest> _pending = new Dictionary<int, PendingRequest>();
        private readonly Dictionary<int, Timer> _timers = new Dictionary<int, Timer>();
        private readonly HashSet<string> _activeWebCallIds = new HashSet<string>(StringComparer.Ordinal);
        private readonly HashSet<string> _recentWebCallIds = new HashSet<string>(StringComparer.Ordinal);
        private readonly Queue<string> _recentWebCallIdOrder = new Queue<string>();
        private readonly object _lock = new object();
        private int _seq;
        private volatile bool _disposed;

        public InventoryTask(XmlSocketServer socket)
            : this(
                delegate { return socket != null && socket.IsClientReady; },
                delegate(string payload) { return socket != null && socket.TrySend(payload); },
                DefaultTimeoutMs)
        {
        }

        public InventoryTask(Func<bool> isClientReady, Func<string, bool> trySend)
            : this(isClientReady, trySend, DefaultTimeoutMs)
        {
        }

        public InventoryTask(Func<bool> isClientReady, Func<string, bool> trySend, int timeoutMs)
        {
            _isClientReady = isClientReady ?? delegate { return false; };
            _trySend = trySend ?? delegate { return false; };
            _timeoutMs = Math.Max(1, timeoutMs);
        }

        public void SetPostToWeb(Action<string> post) { _postToWeb = post; }
        public void SetInvoker(Action<Action> invoker) { _invokeOnUI = invoker; }

        public void Dispose()
        {
            _disposed = true;
            ClearPending();
        }

        public void HandleWebRequest(string cmd, JObject parsed)
        {
            string webCallId = parsed != null ? parsed.Value<string>("callId") : null;
            if (string.IsNullOrEmpty(webCallId)) return;
            if (!ValidCallId.IsMatch(webCallId))
            {
                RespondError(webCallId, cmd, "invalid_call_id");
                return;
            }
            if (!string.Equals(parsed.Value<string>("domain"), "inventory", StringComparison.Ordinal))
            {
                RejectAndRemember(webCallId, cmd, "unsupported_domain");
                return;
            }

            string action;
            if (!TryResolveCommand(cmd, out action))
            {
                RejectAndRemember(webCallId, cmd, "unsupported_cmd");
                return;
            }

            JObject payload = parsed["payload"] as JObject;
            if (payload == null || payload["v"] == null || payload["v"].Type != JTokenType.Integer)
            {
                RejectAndRemember(webCallId, cmd, "invalid_payload");
                return;
            }
            if (payload.Value<int>("v") != 1)
            {
                RejectAndRemember(webCallId, cmd, "unsupported_version");
                return;
            }

            JObject normalized;
            if (!TryNormalizePayload(cmd, payload, out normalized))
            {
                RejectAndRemember(webCallId, cmd, "invalid_payload");
                return;
            }
            if (!_isClientReady())
            {
                RejectAndRemember(webCallId, cmd, "disconnected");
                return;
            }

            int fid;
            lock (_lock)
            {
                if (_activeWebCallIds.Contains(webCallId) || _recentWebCallIds.Contains(webCallId))
                {
                    LogManager.Log("[InventoryTask] duplicate/replayed callId ignored: " + webCallId);
                    return;
                }
                fid = ++_seq;
                _pending[fid] = new PendingRequest { WebCallId = webCallId, WebCmd = cmd };
                _activeWebCallIds.Add(webCallId);
            }

            var timer = new Timer(delegate { HandleTimeout(fid); }, null, _timeoutMs, Timeout.Infinite);
            lock (_lock)
            {
                if (_pending.ContainsKey(fid)) _timers[fid] = timer;
                else timer.Dispose();
            }

            JObject flashMessage = PanelBridge.BuildFlashCommand(action, fid, normalized);
            string flashJson = flashMessage.ToString(Formatting.None);
            LogManager.Log("[InventoryTask] -> Flash: " + flashJson);
            if (!_trySend(flashJson + "\0")) HandleSendFailure(fid);
        }

        public void HandleFlashResponse(JObject msg, Action<string> respond)
        {
            int fid = msg != null ? msg.Value<int>("callId") : 0;
            PendingRequest entry;
            lock (_lock)
            {
                if (!_pending.TryGetValue(fid, out entry))
                {
                    if (respond != null) respond(null);
                    return;
                }
                CompletePendingLocked(fid, entry);
            }

            JObject webMessage = msg != null ? (JObject)msg.DeepClone() : new JObject();
            webMessage.Remove("task");
            webMessage["type"] = "panel_resp";
            webMessage["domain"] = "inventory";
            webMessage["cmd"] = entry.WebCmd;
            webMessage["callId"] = entry.WebCallId;
            PostToWeb(webMessage.ToString(Formatting.None));
            if (respond != null) respond(null);
        }

        public void ClearPending()
        {
            lock (_lock)
            {
                foreach (PendingRequest entry in _pending.Values)
                {
                    _activeWebCallIds.Remove(entry.WebCallId);
                    RememberRecentLocked(entry.WebCallId);
                }
                foreach (Timer timer in _timers.Values) timer.Dispose();
                _timers.Clear();
                _pending.Clear();
            }
        }

        private static bool TryResolveCommand(string cmd, out string action)
        {
            switch (cmd)
            {
                case "snapshot": action = "inventorySnapshot"; return true;
                case "discard": action = "inventoryDiscard"; return true;
                case "move": action = "inventoryMove"; return true;
                case "merge": action = "inventoryMerge"; return true;
                case "swap": action = "inventorySwap"; return true;
                case "sortAndMerge": action = "inventorySortAndMerge"; return true;
                default: action = null; return false;
            }
        }

        private static bool TryNormalizePayload(string cmd, JObject payload, out JObject normalized)
        {
            normalized = new JObject { ["v"] = 1 };
            if (cmd == "snapshot")
            {
                JArray requests = payload["requests"] as JArray;
                if (requests == null || requests.Count < 1 || requests.Count > 4) return false;
                var cleanRequests = new JArray();
                foreach (JToken token in requests)
                {
                    JObject request = token as JObject;
                    if (request == null) return false;
                    string containerId = request.Value<string>("containerId");
                    int offset;
                    int limit;
                    if (!IsContainerId(containerId)
                        || !TryReadNonNegativeInteger(request["offset"], out offset)
                        || !TryReadPositiveInteger(request["limit"], 100, out limit)) return false;
                    cleanRequests.Add(new JObject
                    {
                        ["containerId"] = containerId,
                        ["offset"] = offset,
                        ["limit"] = limit
                    });
                }
                normalized["requests"] = cleanRequests;
                return true;
            }

            if (cmd == "sortAndMerge")
            {
                JObject container = payload["container"] as JObject;
                string containerId = container != null ? container.Value<string>("containerId") : null;
                string methodName = payload.Value<string>("methodName");
                int offset;
                int limit;
                if (container == null
                    || !IsContainerId(containerId)
                    || !TryReadNonNegativeInteger(container["offset"], out offset)
                    || !TryReadPositiveInteger(container["limit"], 100, out limit)
                    || !IsSortMethod(methodName)) return false;
                normalized["container"] = new JObject
                {
                    ["containerId"] = containerId,
                    ["offset"] = offset,
                    ["limit"] = limit
                };
                normalized["methodName"] = methodName;
                return true;
            }

            if (payload["count"] != null) return false;
            JObject source;
            if (!TryNormalizeSlotRef(payload["source"] as JObject, out source)) return false;
            normalized["source"] = source;
            if (cmd == "discard") return true;

            JObject target;
            if (!TryNormalizeSlotRef(payload["target"] as JObject, out target)) return false;
            normalized["target"] = target;
            return true;
        }

        private static bool TryNormalizeSlotRef(JObject input, out JObject normalized)
        {
            normalized = null;
            if (input == null || input["count"] != null) return false;
            string containerId = input.Value<string>("containerId");
            string expectedLease = input.Value<string>("expectedLease");
            int slot;
            if (!IsContainerId(containerId)
                || !TryReadNonNegativeInteger(input["slot"], out slot)
                || string.IsNullOrEmpty(expectedLease)
                || !ValidLease.IsMatch(expectedLease)) return false;
            normalized = new JObject
            {
                ["containerId"] = containerId,
                ["slot"] = slot,
                ["expectedLease"] = expectedLease
            };
            return true;
        }

        private static bool IsContainerId(string value)
        {
            return !string.IsNullOrEmpty(value) && value.Length <= 16;
        }

        private static bool IsSortMethod(string value)
        {
            switch (value)
            {
                case "byType":
                case "byUse":
                case "byPrice":
                case "byLevel":
                case "byID":
                case "byName":
                case "byValue":
                case "byTime":
                    return true;
                default:
                    return false;
            }
        }

        private static bool TryReadNonNegativeInteger(JToken token, out int value)
        {
            value = 0;
            if (token == null || token.Type != JTokenType.Integer) return false;
            long candidate = token.Value<long>();
            if (candidate < 0 || candidate > int.MaxValue) return false;
            value = (int)candidate;
            return true;
        }

        private static bool TryReadPositiveInteger(JToken token, int max, out int value)
        {
            if (!TryReadNonNegativeInteger(token, out value)) return false;
            return value > 0 && value <= max;
        }

        private void HandleTimeout(int fid)
        {
            if (_disposed) return;
            PendingRequest entry;
            lock (_lock)
            {
                if (!_pending.TryGetValue(fid, out entry)) return;
                CompletePendingLocked(fid, entry);
            }
            RespondError(entry.WebCallId, entry.WebCmd, "timeout");
        }

        private void HandleSendFailure(int fid)
        {
            PendingRequest entry;
            lock (_lock)
            {
                if (!_pending.TryGetValue(fid, out entry)) return;
                CompletePendingLocked(fid, entry);
            }
            RespondError(entry.WebCallId, entry.WebCmd, "disconnected");
        }

        private void CompletePendingLocked(int fid, PendingRequest entry)
        {
            _pending.Remove(fid);
            Timer timer;
            if (_timers.TryGetValue(fid, out timer))
            {
                timer.Dispose();
                _timers.Remove(fid);
            }
            _activeWebCallIds.Remove(entry.WebCallId);
            RememberRecentLocked(entry.WebCallId);
        }

        private void RejectAndRemember(string webCallId, string cmd, string error)
        {
            lock (_lock)
            {
                if (_activeWebCallIds.Contains(webCallId) || _recentWebCallIds.Contains(webCallId)) return;
                RememberRecentLocked(webCallId);
            }
            RespondError(webCallId, cmd, error);
        }

        private void RememberRecentLocked(string webCallId)
        {
            if (string.IsNullOrEmpty(webCallId) || !_recentWebCallIds.Add(webCallId)) return;
            _recentWebCallIdOrder.Enqueue(webCallId);
            while (_recentWebCallIdOrder.Count > RecentCallIdCapacity)
            {
                string evicted = _recentWebCallIdOrder.Dequeue();
                _recentWebCallIds.Remove(evicted);
            }
        }

        private void RespondError(string webCallId, string cmd, string error)
        {
            var response = new JObject
            {
                ["type"] = "panel_resp",
                ["domain"] = "inventory",
                ["cmd"] = cmd ?? "",
                ["callId"] = webCallId ?? "",
                ["success"] = false,
                ["error"] = error
            };
            PostToWeb(response.ToString(Formatting.None));
        }

        private void PostToWeb(string json)
        {
            if (_invokeOnUI != null)
                _invokeOnUI(delegate { if (_postToWeb != null) _postToWeb(json); });
            else if (_postToWeb != null)
                _postToWeb(json);
        }
    }
}
