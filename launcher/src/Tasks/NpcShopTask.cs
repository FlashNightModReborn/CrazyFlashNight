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
    /// <summary>NPC 金币商店 domain 的严格 WebView↔Flash 双层 callId 桥。</summary>
    public sealed class NpcShopTask : IDisposable
    {
        private sealed class PendingRequest
        {
            public string WebCallId;
            public string WebCmd;
            public bool IsWrite;
        }

        private const int DefaultTimeoutMs = 10000;
        private const int RecentCallIdCapacity = 256;
        private static readonly Regex ValidCallId = new Regex("^[A-Za-z0-9._-]{1,96}$", RegexOptions.Compiled);
        private static readonly Regex ValidLease = new Regex("^[A-Za-z0-9._-]{1,160}$", RegexOptions.Compiled);

        private readonly Func<bool> _isClientReady;
        private readonly Func<string, bool> _trySend;
        private readonly int _timeoutMs;
        private readonly Dictionary<int, PendingRequest> _pending = new Dictionary<int, PendingRequest>();
        private readonly Dictionary<int, Timer> _timers = new Dictionary<int, Timer>();
        private readonly HashSet<string> _activeCallIds = new HashSet<string>(StringComparer.Ordinal);
        private readonly HashSet<string> _recentCallIds = new HashSet<string>(StringComparer.Ordinal);
        private readonly Queue<string> _recentOrder = new Queue<string>();
        private readonly object _lock = new object();
        private Action<string> _postToWeb;
        private Action<Action> _invokeOnUI;
        private string _writeState = "idle";
        private int _seq;
        private volatile bool _disposed;

        public NpcShopTask(XmlSocketServer socket)
            : this(delegate { return socket != null && socket.IsClientReady; },
                   delegate(string payload) { return socket != null && socket.TrySend(payload); }, DefaultTimeoutMs) { }

        public NpcShopTask(Func<bool> isClientReady, Func<string, bool> trySend, int timeoutMs = DefaultTimeoutMs)
        {
            _isClientReady = isClientReady ?? delegate { return false; };
            _trySend = trySend ?? delegate { return false; };
            _timeoutMs = Math.Max(1, timeoutMs);
        }

        public void SetPostToWeb(Action<string> post) { _postToWeb = post; }
        public void SetInvoker(Action<Action> invoker) { _invokeOnUI = invoker; }
        internal string WriteState { get { lock (_lock) return _writeState; } }

        public void Dispose() { _disposed = true; ClearPending(); }

        public void HandleWebRequest(string cmd, JObject parsed)
        {
            string callId = parsed != null ? parsed.Value<string>("callId") : null;
            if (string.IsNullOrEmpty(callId)) return;
            if (!ValidCallId.IsMatch(callId)) { RespondError(callId, cmd, "invalid_call_id"); return; }
            if (!string.Equals(parsed.Value<string>("domain"), "npcshop", StringComparison.Ordinal))
            { RejectAndRemember(callId, cmd, "unsupported_domain"); return; }

            string action;
            bool isWrite;
            if (!TryResolveCommand(cmd, out action, out isWrite))
            { RejectAndRemember(callId, cmd, "unsupported_cmd"); return; }

            JObject payload = parsed["payload"] as JObject;
            if (payload == null || payload["v"] == null || payload["v"].Type != JTokenType.Integer)
            { RejectAndRemember(callId, cmd, "invalid_payload"); return; }
            if (payload.Value<int>("v") != 1)
            { RejectAndRemember(callId, cmd, "unsupported_version"); return; }
            JObject normalized;
            if (!TryNormalizePayload(cmd, payload, out normalized))
            { RejectAndRemember(callId, cmd, "invalid_payload"); return; }
            if (!_isClientReady())
            { RejectAndRemember(callId, cmd, "disconnected"); return; }

            int fid;
            lock (_lock)
            {
                if (_activeCallIds.Contains(callId) || _recentCallIds.Contains(callId)) return;
                if (isWrite && _writeState != "idle")
                {
                    RememberRecentLocked(callId);
                    RespondError(callId, cmd, _writeState == "needs_reconcile" ? "reconcile_required" : "busy");
                    return;
                }
                fid = ++_seq;
                _pending[fid] = new PendingRequest { WebCallId = callId, WebCmd = cmd, IsWrite = isWrite };
                _activeCallIds.Add(callId);
                if (isWrite) _writeState = "write_pending";
            }

            var timer = new Timer(delegate { HandleTimeout(fid); }, null, _timeoutMs, Timeout.Infinite);
            lock (_lock) { if (_pending.ContainsKey(fid)) _timers[fid] = timer; else timer.Dispose(); }
            string json = PanelBridge.BuildFlashCommand(action, fid, normalized).ToString(Formatting.None);
            LogManager.Log("[NpcShopTask] -> Flash: " + json);
            if (!_trySend(json + "\0")) HandleSendFailure(fid);
        }

        public void HandleFlashResponse(JObject msg, Action<string> respond)
        {
            int fid = msg != null ? msg.Value<int>("callId") : 0;
            PendingRequest entry;
            bool malformed = false;
            bool definitiveWrite = false;
            lock (_lock)
            {
                if (!_pending.TryGetValue(fid, out entry)) { if (respond != null) respond(null); return; }
                malformed = IsMalformedResponse(msg, entry);
                definitiveWrite = entry.IsWrite && !malformed && IsDefinitiveWriteResponse(msg, entry.WebCmd);
                CompletePendingLocked(fid, entry);
                if (entry.IsWrite)
                    _writeState = definitiveWrite ? "idle" : "needs_reconcile";
                else if (entry.WebCmd == "snapshot" && !malformed
                    && msg != null && msg.Value<bool?>("success") == true
                    && _writeState == "needs_reconcile")
                    _writeState = "idle";
            }
            JObject web = malformed
                ? new JObject { ["success"] = false, ["error"] = "malformed_response" }
                : (msg != null ? (JObject)msg.DeepClone() : new JObject());
            web.Remove("task");
            web["type"] = "panel_resp";
            web["domain"] = "npcshop";
            web["cmd"] = entry.WebCmd;
            web["callId"] = entry.WebCallId;
            if (entry.IsWrite && !definitiveWrite) web["requiresReconcile"] = true;
            PostToWeb(web.ToString(Formatting.None));
            if (respond != null) respond(null);
        }

        public void ClearPending()
        {
            lock (_lock)
            {
                foreach (PendingRequest entry in _pending.Values)
                {
                    _activeCallIds.Remove(entry.WebCallId);
                    RememberRecentLocked(entry.WebCallId);
                    if (entry.IsWrite) _writeState = "needs_reconcile";
                }
                foreach (Timer timer in _timers.Values) timer.Dispose();
                _timers.Clear();
                _pending.Clear();
            }
        }

        private static bool TryResolveCommand(string cmd, out string action, out bool isWrite)
        {
            isWrite = false;
            switch (cmd)
            {
                case "snapshot": action = "npcShopSnapshot"; return true;
                case "tooltip": action = "npcShopTooltip"; return true;
                case "batchPreview": action = "npcShopBatchPreview"; return true;
                case "tradePreview": action = "npcShopTradePreview"; return true;
                case "buy": action = "npcShopBuy"; isWrite = true; return true;
                case "sell": action = "npcShopSell"; isWrite = true; return true;
                case "batchSell": action = "npcShopBatchSell"; isWrite = true; return true;
                case "tradeCommit": action = "npcShopTradeCommit"; isWrite = true; return true;
                default: action = null; return false;
            }
        }

        private static bool TryNormalizePayload(string cmd, JObject payload, out JObject normalized)
        {
            normalized = new JObject { ["v"] = 1 };
            if (cmd == "snapshot") return CopyShopId(payload, normalized);
            if (cmd == "buy")
            {
                int catalogIndex, quantity;
                if (!CopyShopId(payload, normalized)
                    || !TryReadInteger(payload["catalogIndex"], 0, 10000, out catalogIndex)
                    || !TryReadInteger(payload["quantity"], 1, 100, out quantity)) return false;
                normalized["catalogIndex"] = catalogIndex;
                normalized["quantity"] = quantity;
                return true;
            }
            if (cmd == "sell")
            {
                int quantity;
                JObject source;
                if (!CopyShopId(payload, normalized)
                    || !TryReadInteger(payload["quantity"], 1, int.MaxValue, out quantity)
                    || !TryNormalizeSource(payload["source"] as JObject, out source)) return false;
                normalized["source"] = source;
                normalized["quantity"] = quantity;
                return true;
            }
            if (cmd == "tooltip")
            {
                JObject sourceToken = payload["source"] as JObject;
                if (sourceToken != null)
                {
                    JObject source;
                    if (!TryNormalizeSource(sourceToken, out source) || source.Value<string>("containerId") != "背包") return false;
                    normalized["source"] = source;
                    return true;
                }
                string itemName = payload.Value<string>("itemName");
                if (!IsSafeText(itemName, 128)) return false;
                normalized["itemName"] = itemName;
                return true;
            }
            if (cmd == "batchPreview")
            {
                JArray names = payload["itemNames"] as JArray;
                if (names == null || names.Count < 1 || names.Count > 5) return false;
                var seen = new HashSet<string>(StringComparer.Ordinal);
                var clean = new JArray();
                foreach (JToken token in names)
                {
                    if (token.Type != JTokenType.String) return false;
                    string name = token.Value<string>();
                    if (!IsSafeText(name, 128) || !seen.Add(name)) return false;
                    clean.Add(name);
                }
                normalized["itemNames"] = clean;
                return true;
            }
            if (cmd == "batchSell")
            {
                string token = payload.Value<string>("expectedBatchToken");
                if (!CopyShopId(payload, normalized) || string.IsNullOrEmpty(token) || !ValidLease.IsMatch(token)) return false;
                normalized["expectedBatchToken"] = token;
                return true;
            }
            if (cmd == "tradePreview")
            {
                if (!CopyShopId(payload, normalized)) return false;
                JArray purchases = payload["purchases"] as JArray;
                JArray sales = payload["sales"] as JArray;
                if (purchases == null || sales == null || purchases.Count > 40 || sales.Count > 50
                    || purchases.Count + sales.Count < 1) return false;
                var cleanPurchases = new JArray();
                var purchaseIds = new HashSet<int>();
                foreach (JToken token in purchases)
                {
                    JObject line = token as JObject;
                    int catalogIndex, quantity;
                    if (line == null
                        || !TryReadInteger(line["catalogIndex"], 0, 10000, out catalogIndex)
                        || !TryReadInteger(line["quantity"], 1, 100, out quantity)
                        || !purchaseIds.Add(catalogIndex)) return false;
                    cleanPurchases.Add(new JObject { ["catalogIndex"] = catalogIndex, ["quantity"] = quantity });
                }
                var cleanSales = new JArray();
                var saleIds = new HashSet<string>(StringComparer.Ordinal);
                foreach (JToken token in sales)
                {
                    JObject line = token as JObject;
                    JObject source;
                    if (line == null || !TryNormalizeSource(line["source"] as JObject, out source)) return false;
                    string scope = line.Value<string>("scope") ?? "slot";
                    JObject cleanLine;
                    if (scope == "slot")
                    {
                        int quantity;
                        if (!TryReadInteger(line["quantity"], 1, int.MaxValue, out quantity)
                            || line["policy"] != null) return false;
                        cleanLine = new JObject
                        {
                            ["source"] = source,
                            ["quantity"] = quantity,
                            ["scope"] = "slot"
                        };
                    }
                    else if (scope == "same_name")
                    {
                        if (source.Value<string>("containerId") != "背包"
                            || line.Value<string>("policy") != "plain_only"
                            || line["quantity"] != null) return false;
                        cleanLine = new JObject
                        {
                            ["source"] = source,
                            ["scope"] = "same_name",
                            ["policy"] = "plain_only"
                        };
                    }
                    else return false;
                    string identity = source.Value<string>("containerId") == "背包"
                        ? "bag:" + source.Value<int>("slot")
                        : "material:" + source.Value<string>("key");
                    if (!saleIds.Add(identity)) return false;
                    cleanSales.Add(cleanLine);
                }
                normalized["purchases"] = cleanPurchases;
                normalized["sales"] = cleanSales;
                return true;
            }
            if (cmd == "tradeCommit")
            {
                string token = payload.Value<string>("expectedTradeToken");
                if (!CopyShopId(payload, normalized) || string.IsNullOrEmpty(token) || !ValidLease.IsMatch(token)) return false;
                normalized["expectedTradeToken"] = token;
                return true;
            }
            return false;
        }

        private static bool CopyShopId(JObject input, JObject output)
        {
            string shopId = input.Value<string>("shopId");
            if (!IsSafeText(shopId, 80)) return false;
            output["shopId"] = shopId;
            return true;
        }

        private static bool TryNormalizeSource(JObject input, out JObject normalized)
        {
            normalized = null;
            if (input == null || input["count"] != null) return false;
            string lease = input.Value<string>("expectedLease");
            if (string.IsNullOrEmpty(lease) || !ValidLease.IsMatch(lease)) return false;
            if (input.Value<string>("containerId") == "背包")
            {
                int slot;
                if (!TryReadInteger(input["slot"], 0, 49, out slot)) return false;
                normalized = new JObject { ["containerId"] = "背包", ["slot"] = slot, ["expectedLease"] = lease };
                return true;
            }
            if (input.Value<string>("viewId") == "material")
            {
                string key = input.Value<string>("key");
                if (!IsSafeText(key, 128)) return false;
                normalized = new JObject { ["viewId"] = "material", ["key"] = key, ["expectedLease"] = lease };
                return true;
            }
            return false;
        }

        private static bool TryReadInteger(JToken token, int min, int max, out int value)
        {
            value = 0;
            if (token == null || token.Type != JTokenType.Integer) return false;
            long candidate = token.Value<long>();
            if (candidate < min || candidate > max) return false;
            value = (int)candidate;
            return true;
        }

        private static bool IsSafeText(string value, int max)
        {
            if (string.IsNullOrEmpty(value) || value.Length > max) return false;
            for (int i = 0; i < value.Length; i++) if (char.IsControl(value[i])) return false;
            return true;
        }

        private static bool IsDefinitiveWriteResponse(JObject msg, string cmd)
        {
            if (msg == null || msg["success"] == null || msg["success"].Type != JTokenType.Boolean) return false;
            if (msg.Value<bool>("success")) return IsAuthoritativeWriteSuccess(msg, cmd);
            switch (msg.Value<string>("error"))
            {
                case "invalid_payload": case "shop_not_found": case "item_not_found": case "invalid_quantity": case "locked":
                case "insufficient_money": case "inventory_full": case "stale_state": case "sell_forbidden":
                case "insufficient_quantity": case "nothing_to_sell": case "busy": return true;
                case "duplicate_line": case "invalid_price": return true;
                default: return false;
            }
        }

        private static bool IsMalformedResponse(JObject msg, PendingRequest entry)
        {
            if (msg == null || msg["success"] == null || msg["success"].Type != JTokenType.Boolean) return true;
            bool success = msg.Value<bool>("success");
            if (entry.IsWrite)
            {
                if (success) return !IsAuthoritativeWriteSuccess(msg, entry.WebCmd);
                return string.IsNullOrEmpty(msg.Value<string>("error"));
            }
            if (entry.WebCmd == "snapshot")
                return success ? !IsAuthoritativeState(msg) : string.IsNullOrEmpty(msg.Value<string>("error"));
            return false;
        }

        private static bool IsAuthoritativeWriteSuccess(JObject msg, string cmd)
        {
            if (!IsAuthoritativeState(msg) || msg.Value<string>("operation") != cmd) return false;
            return cmd != "tradeCommit" || msg["trade"] is JObject;
        }

        private static bool IsAuthoritativeState(JObject msg)
        {
            if (msg == null || msg.Value<int?>("v") != 1 || string.IsNullOrEmpty(msg.Value<string>("shopId"))) return false;
            if (!IsNumber(msg["balance"]) || !(msg["catalog"] is JArray) || !(msg["layout"] is JObject)) return false;
            JObject views = msg["views"] as JObject;
            return views != null && views["bag"] is JObject
                && views["material"] is JObject && views["intelligence"] is JObject;
        }

        private static bool IsNumber(JToken token)
        {
            return token != null && (token.Type == JTokenType.Integer || token.Type == JTokenType.Float);
        }

        private void HandleTimeout(int fid)
        {
            if (_disposed) return;
            PendingRequest entry;
            lock (_lock)
            {
                if (!_pending.TryGetValue(fid, out entry)) return;
                CompletePendingLocked(fid, entry);
                if (entry.IsWrite) _writeState = "needs_reconcile";
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
                if (entry.IsWrite) _writeState = "needs_reconcile";
            }
            RespondError(entry.WebCallId, entry.WebCmd, "disconnected");
        }

        private void CompletePendingLocked(int fid, PendingRequest entry)
        {
            _pending.Remove(fid);
            Timer timer;
            if (_timers.TryGetValue(fid, out timer)) { timer.Dispose(); _timers.Remove(fid); }
            _activeCallIds.Remove(entry.WebCallId);
            RememberRecentLocked(entry.WebCallId);
        }

        private void RejectAndRemember(string callId, string cmd, string error)
        {
            lock (_lock)
            {
                if (_activeCallIds.Contains(callId) || _recentCallIds.Contains(callId)) return;
                RememberRecentLocked(callId);
            }
            RespondError(callId, cmd, error);
        }

        private void RememberRecentLocked(string callId)
        {
            if (string.IsNullOrEmpty(callId) || !_recentCallIds.Add(callId)) return;
            _recentOrder.Enqueue(callId);
            while (_recentOrder.Count > RecentCallIdCapacity) _recentCallIds.Remove(_recentOrder.Dequeue());
        }

        private void RespondError(string callId, string cmd, string error)
        {
            PostToWeb(new JObject
            {
                ["type"] = "panel_resp", ["domain"] = "npcshop", ["cmd"] = cmd ?? "",
                ["callId"] = callId ?? "", ["success"] = false, ["error"] = error
            }.ToString(Formatting.None));
        }

        private void PostToWeb(string json)
        {
            if (_invokeOnUI != null) _invokeOnUI(delegate { if (_postToWeb != null) _postToWeb(json); });
            else if (_postToWeb != null) _postToWeb(json);
        }
    }
}
