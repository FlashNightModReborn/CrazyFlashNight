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
    /// <summary>crafting domain 的严格 WebView↔Flash callId 桥与提交对账门。</summary>
    public sealed class CraftingTask : IDisposable
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
        private static readonly Regex ValidToken = new Regex("^[A-Za-z0-9._-]{1,160}$", RegexOptions.Compiled);
        private static readonly HashSet<string> Categories = new HashSet<string>(StringComparer.Ordinal)
        {
            "铁枪会", "属性武器", "烹饪", "化学生产", "武器合成", "饰品合成",
            "进阶防具", "基础防具", "公社防具", "黑白契约", "插件合成", "大学装备"
        };
        private static readonly HashSet<string> AvailabilityCodes = new HashSet<string>(StringComparer.Ordinal)
        {
            "ready", "level_locked", "material_missing", "insufficient_money",
            "insufficient_kpoint", "inventory_full"
        };

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

        public CraftingTask(XmlSocketServer socket)
            : this(delegate { return socket != null && socket.IsClientReady; },
                   delegate(string payload) { return socket != null && socket.TrySend(payload); }, DefaultTimeoutMs) { }

        public CraftingTask(Func<bool> isClientReady, Func<string, bool> trySend, int timeoutMs = DefaultTimeoutMs)
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
            if (!string.Equals(parsed.Value<string>("domain"), "crafting", StringComparison.Ordinal))
            { RejectAndRemember(callId, cmd, "unsupported_domain"); return; }

            string action;
            bool isWrite;
            if (!TryResolveCommand(cmd, out action, out isWrite))
            { RejectAndRemember(callId, cmd, "unsupported_cmd"); return; }
            JObject payload = parsed["payload"] as JObject;
            JObject normalized;
            if (payload == null || !HasProtocolVersion(payload) || !TryNormalizePayload(cmd, payload, out normalized))
            { RejectAndRemember(callId, cmd, "invalid_payload"); return; }
            if (!_isClientReady()) { RejectAndRemember(callId, cmd, "disconnected"); return; }

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
            LogManager.Log("[CraftingTask] -> Flash: " + json);
            if (!_trySend(json + "\0")) HandleSendFailure(fid);
        }

        public void HandleFlashResponse(JObject msg, Action<string> respond)
        {
            int fid = msg != null ? msg.Value<int>("callId") : 0;
            PendingRequest entry;
            bool malformed;
            bool definitiveWrite;
            lock (_lock)
            {
                if (!_pending.TryGetValue(fid, out entry)) { if (respond != null) respond(null); return; }
                malformed = IsMalformedResponse(msg, entry);
                definitiveWrite = entry.IsWrite && !malformed && IsDefinitiveWriteResponse(msg);
                CompletePendingLocked(fid, entry);
                if (entry.IsWrite) _writeState = definitiveWrite ? "idle" : "needs_reconcile";
                else if (entry.WebCmd == "preview" && !malformed && msg.Value<bool?>("success") == true
                    && _writeState == "needs_reconcile") _writeState = "idle";
            }
            JObject web = malformed
                ? new JObject { ["success"] = false, ["error"] = "malformed_response" }
                : (JObject)msg.DeepClone();
            web.Remove("task");
            web["type"] = "panel_resp";
            web["domain"] = "crafting";
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
                case "snapshot": action = "craftingSnapshot"; return true;
                case "preview": action = "craftingPreview"; return true;
                case "tooltip": action = "craftingTooltip"; return true;
                case "commit": action = "craftingCommit"; isWrite = true; return true;
                default: action = null; return false;
            }
        }

        private static bool TryNormalizePayload(string cmd, JObject payload, out JObject normalized)
        {
            normalized = new JObject { ["v"] = 1 };
            if (cmd == "tooltip")
            {
                string itemName = payload.Value<string>("itemName");
                if (!IsSafeText(itemName, 128)) return false;
                normalized["itemName"] = itemName;
                return true;
            }
            string category = payload.Value<string>("category");
            if (!Categories.Contains(category)) return false;
            normalized["category"] = category;
            if (cmd == "snapshot") return true;
            if (cmd == "preview")
            {
                int recipeIndex;
                int craftCount;
                if (!TryReadInteger(payload["recipeIndex"], 0, 999, out recipeIndex)) return false;
                if (!TryReadInteger(payload["craftCount"], 1, 99, out craftCount)) return false;
                normalized["recipeIndex"] = recipeIndex;
                normalized["craftCount"] = craftCount;
                return true;
            }
            if (cmd == "commit")
            {
                string token = payload.Value<string>("expectedCraftToken");
                if (string.IsNullOrEmpty(token) || !ValidToken.IsMatch(token)) return false;
                normalized["expectedCraftToken"] = token;
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

        private static bool IsMalformedResponse(JObject msg, PendingRequest entry)
        {
            if (msg == null || msg["success"] == null || msg["success"].Type != JTokenType.Boolean) return true;
            if (msg.Value<bool>("success"))
            {
                if (entry.WebCmd == "snapshot") return !IsAuthoritativeSnapshot(msg);
                if (entry.WebCmd == "preview") return !IsAuthoritativePreview(msg);
                if (entry.WebCmd == "commit") return !IsAuthoritativeCommit(msg);
                return !HasProtocolVersion(msg) || !IsSafeText(msg.Value<string>("itemName"), 128);
            }
            return string.IsNullOrEmpty(msg.Value<string>("error"));
        }

        private static bool IsAuthoritativeSnapshot(JObject msg)
        {
            var recipes = msg["recipes"] as JArray;
            if (!CommonState(msg) || recipes == null || !(msg["skills"] is JObject)) return false;
            var seenIndexes = new HashSet<int>();
            foreach (JToken token in recipes)
            {
                var recipe = token as JObject;
                var output = recipe != null ? recipe["output"] as JObject : null;
                var baseCost = recipe != null ? recipe["baseCost"] as JObject : null;
                int recipeIndex;
                int materialCount;
                if (recipe == null || output == null || baseCost == null
                    || !TryReadInteger(recipe["recipeIndex"], 0, 999, out recipeIndex)
                    || !seenIndexes.Add(recipeIndex)
                    || !TryReadInteger(recipe["materialCount"], 0, 999, out materialCount)
                    || recipe["batchEligible"] == null || recipe["batchEligible"].Type != JTokenType.Boolean
                    || recipe["canCraftOne"] == null || recipe["canCraftOne"].Type != JTokenType.Boolean
                    || !IsSafeText(recipe.Value<string>("title"), 256)
                    || !IsSafeText(output.Value<string>("name"), 128)
                    || !IsNumber(baseCost["money"]) || !IsNumber(baseCost["kpoints"])) return false;
                string availability = recipe.Value<string>("availability");
                bool canCraftOne = recipe.Value<bool>("canCraftOne");
                if (!AvailabilityCodes.Contains(availability)
                    || canCraftOne != string.Equals(availability, "ready", StringComparison.Ordinal)) return false;
            }
            return true;
        }

        private static bool IsAuthoritativePreview(JObject msg)
        {
            int recipeIndex;
            int craftCount;
            int maxCraftCount;
            if (!CommonState(msg) || !TryReadInteger(msg["recipeIndex"], 0, 999, out recipeIndex)
                || !TryReadInteger(msg["craftCount"], 1, 99, out craftCount)
                || !TryReadInteger(msg["maxCraftCount"], 0, 99, out maxCraftCount)
                || !(msg["output"] is JObject) || !(msg["materials"] is JArray) || !(msg["cost"] is JObject)
                || msg["batchEligible"] == null || msg["batchEligible"].Type != JTokenType.Boolean
                || msg["canCommit"] == null || msg["canCommit"].Type != JTokenType.Boolean) return false;
            var cost = msg["cost"] as JObject;
            if (cost == null || !IsNumber(cost["money"]) || !IsNumber(cost["kpoints"])) return false;
            bool batchEligible = msg.Value<bool>("batchEligible");
            bool canCommit = msg.Value<bool>("canCommit");
            if (!batchEligible && (craftCount != 1 || maxCraftCount > 1)) return false;
            if (canCommit)
            {
                if (maxCraftCount < craftCount) return false;
                string token = msg.Value<string>("craftToken");
                if (string.IsNullOrEmpty(token) || !ValidToken.IsMatch(token)) return false;
            }
            else if (msg["craftToken"] != null) return false;
            return msg["output"] is JObject && msg["materials"] is JArray
                && msg["canCommit"] != null && msg["canCommit"].Type == JTokenType.Boolean;
        }

        private static bool IsAuthoritativeCommit(JObject msg)
        {
            int recipeIndex;
            int craftCount;
            var crafted = msg["crafted"] as JObject;
            return CommonState(msg) && msg.Value<string>("operation") == "commit"
                && TryReadInteger(msg["recipeIndex"], 0, 999, out recipeIndex) && crafted != null
                && TryReadInteger(msg["craftCount"], 1, 99, out craftCount)
                && IsSafeText(crafted.Value<string>("name"), 128);
        }

        private static bool CommonState(JObject msg)
        {
            var balance = msg["balance"] as JObject;
            return HasProtocolVersion(msg) && Categories.Contains(msg.Value<string>("category"))
                && balance != null && IsNumber(balance["money"]) && IsNumber(balance["kpoints"]);
        }

        private static bool HasProtocolVersion(JObject value)
        {
            return value != null && value["v"] != null && value["v"].Type == JTokenType.Integer
                && value.Value<int>("v") == 1;
        }

        private static bool IsNumber(JToken value)
        {
            return value != null && (value.Type == JTokenType.Integer || value.Type == JTokenType.Float);
        }

        private static bool IsDefinitiveWriteResponse(JObject msg)
        {
            if (msg == null || msg["success"] == null || msg["success"].Type != JTokenType.Boolean) return false;
            if (msg.Value<bool>("success")) return IsAuthoritativeCommit(msg);
            switch (msg.Value<string>("error"))
            {
                case "invalid_payload": case "category_not_found": case "recipe_not_found":
                case "batch_not_supported":
                case "stale_state": case "material_missing": case "insufficient_money":
                case "insufficient_kpoint": case "inventory_full": case "level_locked": case "busy": return true;
                default: return false;
            }
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
            RespondError(entry.WebCallId, entry.WebCmd, "timeout", entry.IsWrite);
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
            RespondError(entry.WebCallId, entry.WebCmd, "disconnected", entry.IsWrite);
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
            RespondError(callId, cmd, error, false);
        }

        private void RememberRecentLocked(string callId)
        {
            if (string.IsNullOrEmpty(callId) || !_recentCallIds.Add(callId)) return;
            _recentOrder.Enqueue(callId);
            while (_recentOrder.Count > RecentCallIdCapacity) _recentCallIds.Remove(_recentOrder.Dequeue());
        }

        private void RespondError(string callId, string cmd, string error, bool requiresReconcile = false)
        {
            var response = new JObject
            {
                ["type"] = "panel_resp", ["domain"] = "crafting", ["cmd"] = cmd ?? "",
                ["callId"] = callId ?? "", ["success"] = false, ["error"] = error
            };
            if (requiresReconcile) response["requiresReconcile"] = true;
            PostToWeb(response.ToString(Formatting.None));
        }

        private void PostToWeb(string json)
        {
            if (_invokeOnUI != null) _invokeOnUI(delegate { if (_postToWeb != null) _postToWeb(json); });
            else if (_postToWeb != null) _postToWeb(json);
        }
    }
}
