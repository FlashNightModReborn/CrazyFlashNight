using System;
using System.Collections.Generic;
using System.Text.RegularExpressions;
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
            public string WebCmd;
            public bool IsWrite;
            public JObject NormalizedPayload;
        }

        private const int DefaultTimeoutMs = 10000;
        // npc-shop.v2 的跨层整数技术护栏，不是策划购买配额。装备、情报容量与
        // purchaseLimit 仍由 AS2 在 snapshot/preview/commit 的同一权威路径裁决。
        private const int MaxPurchaseQuantity = 999999;
        private static readonly Regex ValidCallId = new Regex("^[A-Za-z0-9._-]{1,96}$", RegexOptions.Compiled);
        private static readonly Regex ValidLease = new Regex("^[A-Za-z0-9._-]{1,160}$", RegexOptions.Compiled);

        private readonly PanelPendingCallTracker<PendingRequest> _pendingCalls;
        private readonly object _lock = new object();
        private Action<string> _postToWeb;
        private Action<Action> _invokeOnUI;
        private string _writeState = "idle";
        public NpcShopTask(XmlSocketServer socket)
            : this(delegate { return socket != null && socket.IsClientReady; },
                   delegate(string payload) { return socket != null && socket.TrySend(payload); }, DefaultTimeoutMs) { }

        public NpcShopTask(Func<bool> isClientReady, Func<string, bool> trySend, int timeoutMs = DefaultTimeoutMs)
        {
            _pendingCalls = new PanelPendingCallTracker<PendingRequest>(
                isClientReady,
                trySend,
                timeoutMs,
                HandlePendingEnded);
        }

        public void SetPostToWeb(Action<string> post) { _postToWeb = post; }
        public void SetInvoker(Action<Action> invoker) { _invokeOnUI = invoker; }
        internal string WriteState { get { lock (_lock) return _writeState; } }

        public void Dispose()
        {
            lock (_lock) { _pendingCalls.Dispose(); }
        }

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
            if (!_pendingCalls.IsReady())
            { RejectAndRemember(callId, cmd, "disconnected"); return; }

            int fid;
            lock (_lock)
            {
                if (_pendingCalls.IsKnownWebCallId(callId)) return;
                if (isWrite && _writeState != "idle")
                {
                    if (!_pendingCalls.TryRememberRejected(callId)) return;
                    RespondError(callId, cmd, _writeState == "needs_reconcile" ? "reconcile_required" : "busy");
                    return;
                }
                if (!_pendingCalls.TryBegin(
                    callId,
                    new PendingRequest
                    {
                        WebCmd = cmd,
                        IsWrite = isWrite,
                        NormalizedPayload = (JObject)normalized.DeepClone()
                    },
                    out fid)) return;
                if (isWrite) _writeState = "write_pending";
            }

            string json = PanelBridge.BuildFlashCommand(action, fid, normalized).ToString(Formatting.None);
            LogManager.Log("[NpcShopTask] -> Flash: " + json);
            _pendingCalls.Send(fid, json + "\0");
        }

        public void HandleFlashResponse(JObject msg, Action<string> respond)
        {
            int fid = msg != null ? msg.Value<int>("callId") : 0;
            PendingRequest entry;
            PanelPendingCall<PendingRequest> pendingCall;
            bool malformed = false;
            bool definitiveWrite = false;
            lock (_lock)
            {
                if (!_pendingCalls.TryComplete(fid, out pendingCall))
                {
                    if (respond != null) respond(null);
                    return;
                }
                entry = pendingCall.Context;
                malformed = IsMalformedResponse(msg, entry);
                definitiveWrite = entry.IsWrite && !malformed && IsDefinitiveWriteResponse(msg, entry.WebCmd);
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
            web["callId"] = pendingCall.WebCallId;
            if (entry.IsWrite && !definitiveWrite) web["requiresReconcile"] = true;
            PostToWeb(web.ToString(Formatting.None));
            if (respond != null) respond(null);
        }

        public void ClearPending()
        {
            lock (_lock) { _pendingCalls.Clear(); }
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
                    || !TryReadInteger(payload["quantity"], 1, MaxPurchaseQuantity, out quantity)) return false;
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
                        || !TryReadInteger(line["quantity"], 1, MaxPurchaseQuantity, out quantity)
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
                case "duplicate_line": case "invalid_price": case "destination_full": return true;
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
                return !HasErrorCode(msg);
            }
            if (entry.WebCmd == "snapshot")
                return success ? !IsAuthoritativeState(msg) : !HasErrorCode(msg);
            if (entry.WebCmd == "tradePreview")
                return success ? !IsAuthoritativeTradePreview(msg, entry.NormalizedPayload)
                    : !HasErrorCode(msg);
            return !success && !HasErrorCode(msg);
        }

        private static bool IsAuthoritativeTradePreview(JObject msg, JObject request)
        {
            if (msg == null || msg["v"] == null || msg["v"].Type != JTokenType.Integer
                || msg.Value<int>("v") != 1 || request == null) return false;
            string token = msg.Value<string>("tradeToken");
            JArray purchaseLines = msg["purchaseLines"] as JArray;
            JArray saleLines = msg["saleLines"] as JArray;
            JArray requestedPurchases = request["purchases"] as JArray;
            JArray requestedSales = request["sales"] as JArray;
            if (msg["tradeToken"] == null || msg["tradeToken"].Type != JTokenType.String
                || string.IsNullOrEmpty(token) || !ValidLease.IsMatch(token)
                || purchaseLines == null || saleLines == null
                || requestedPurchases == null || requestedSales == null
                || purchaseLines.Count != requestedPurchases.Count || saleLines.Count != requestedSales.Count
                || !IsNonNegativeNumber(msg["buyTotal"]) || !IsNonNegativeNumber(msg["sellTotal"])
                || !IsNumber(msg["netDelta"]) || !IsNumber(msg["projectedBalance"])
                || !IsNonNegativeInteger(msg["requiredSlots"]) || !IsNonNegativeInteger(msg["availableSlots"])
                || !IsNonNegativeInteger(msg["missingSlots"])
                || msg["canCommit"] == null || msg["canCommit"].Type != JTokenType.Boolean
                || msg["blockingError"] == null || msg["blockingError"].Type != JTokenType.String) return false;

            var requestedPurchaseById = new Dictionary<int, JObject>();
            foreach (JToken requestToken in requestedPurchases)
            {
                JObject line = requestToken as JObject;
                int catalogIndex;
                if (line == null || !TryReadInteger(line["catalogIndex"], 0, 10000, out catalogIndex)) return false;
                requestedPurchaseById[catalogIndex] = line;
            }

            double purchaseTotal = 0;
            bool hasPotentialCollectionAcquisition = false;
            var seenPurchases = new HashSet<int>();
            foreach (JToken responseToken in purchaseLines)
            {
                JObject line = responseToken as JObject;
                int catalogIndex, quantity, maxQuantity, purchaseLimit;
                int maxAffordable, maxByCapacity, maxPurchasable;
                JObject requestedLine;
                string itemKind = line != null ? line.Value<string>("itemKind") : null;
                string destinationView = line != null ? line.Value<string>("destinationView") : null;
                if (line == null
                    || !TryReadInteger(line["catalogIndex"], 0, 10000, out catalogIndex)
                    || !seenPurchases.Add(catalogIndex)
                    || !requestedPurchaseById.TryGetValue(catalogIndex, out requestedLine)
                    || !TryReadInteger(line["quantity"], 1, MaxPurchaseQuantity, out quantity)
                    || quantity != requestedLine.Value<int>("quantity")
                    || !TryReadInteger(line["maxQuantity"], 1, MaxPurchaseQuantity, out maxQuantity)
                    || !TryReadInteger(line["purchaseLimit"], 1, MaxPurchaseQuantity, out purchaseLimit)
                    || quantity > maxQuantity || quantity > purchaseLimit || maxQuantity != purchaseLimit
                    || !TryReadInteger(line["maxAffordable"], 0, MaxPurchaseQuantity, out maxAffordable)
                    || !TryReadInteger(line["maxByCapacity"], 0, MaxPurchaseQuantity, out maxByCapacity)
                    || !TryReadInteger(line["maxPurchasable"], 0, MaxPurchaseQuantity, out maxPurchasable)
                    || maxPurchasable > purchaseLimit || maxPurchasable > maxAffordable || maxPurchasable > maxByCapacity
                    || !IsSafeString(line["itemName"], 128, false)
                    || !IsSafeString(line["displayName"], 256, false)
                    || !IsSafeString(line["icon"], 256, false)
                    || !IsOneOf(line["itemKind"], "equipment", "stack")
                    || !IsOneOf(line["destinationView"], "bag", "material", "intelligence", "quickslot")
                    || (destinationView == "intelligence" && itemKind != "stack")
                    || !IsOneOf(line["limitingReason"], "", "insufficient_money", "inventory_full", "destination_full")
                    || !IsNonNegativeNumber(line["unitPrice"]) || !IsNonNegativeNumber(line["total"])) return false;
                int expectedMaximum = Math.Min(purchaseLimit, Math.Min(maxAffordable, maxByCapacity));
                string expectedLimitingReason = expectedMaximum < purchaseLimit
                    ? (maxByCapacity <= maxAffordable
                        ? (line.Value<string>("destinationView") == "intelligence" ? "destination_full" : "inventory_full")
                        : "insufficient_money")
                    : "";
                if (maxPurchasable != expectedMaximum
                    || line.Value<string>("limitingReason") != expectedLimitingReason) return false;
                if (destinationView == "intelligence") hasPotentialCollectionAcquisition = true;
                purchaseTotal += line.Value<double>("total");
            }

            var requestedSaleByIdentity = new Dictionary<string, JObject>(StringComparer.Ordinal);
            foreach (JToken requestToken in requestedSales)
            {
                JObject line = requestToken as JObject;
                string identity = TradeSaleIdentity(line);
                if (line == null || string.IsNullOrEmpty(identity) || requestedSaleByIdentity.ContainsKey(identity)) return false;
                requestedSaleByIdentity[identity] = line;
            }

            double saleTotal = 0;
            var seenSales = new HashSet<string>(StringComparer.Ordinal);
            foreach (JToken responseToken in saleLines)
            {
                JObject line = responseToken as JObject;
                long quantity;
                int matchedCount, eligibleCount, protectedCount;
                string identity = line != null && line["sourceIdentity"] != null
                    && line["sourceIdentity"].Type == JTokenType.String ? line.Value<string>("sourceIdentity") : null;
                string scope = line != null ? line.Value<string>("scope") : null;
                JObject requestedLine;
                if (line == null || string.IsNullOrEmpty(identity) || !seenSales.Add(identity)
                    || !requestedSaleByIdentity.TryGetValue(identity, out requestedLine)
                    || !TryReadPositiveInteger(line["quantity"], out quantity)
                    || !TryReadInteger(line["matchedCount"], 1, int.MaxValue, out matchedCount)
                    || !TryReadInteger(line["eligibleCount"], 1, int.MaxValue, out eligibleCount)
                    || !TryReadInteger(line["protectedCount"], 0, int.MaxValue, out protectedCount)
                    || eligibleCount > matchedCount || protectedCount > matchedCount
                    || (long)eligibleCount + protectedCount != matchedCount
                    || scope != requestedLine.Value<string>("scope")
                    || (scope == "slot" && (quantity != requestedLine.Value<int>("quantity")
                        || matchedCount != 1 || eligibleCount != 1 || protectedCount != 0))
                    || !IsSafeString(line["itemName"], 128, false)
                    || !IsSafeString(line["displayName"], 256, false)
                    || !IsSafeString(line["icon"], 256, false)
                    || !IsOneOf(line["itemKind"], "equipment", "stack")
                    || !IsOneOf(line["scope"], "slot", "same_name")
                    || !IsNonNegativeNumber(line["total"])) return false;
                if (line.Value<string>("itemKind") == "equipment") hasPotentialCollectionAcquisition = true;
                saleTotal += line.Value<double>("total");
            }

            double buyTotal = msg.Value<double>("buyTotal");
            double sellTotal = msg.Value<double>("sellTotal");
            string blockingError = msg.Value<string>("blockingError");
            bool canCommit = msg.Value<bool>("canCommit");
            int requiredSlots = msg.Value<int>("requiredSlots");
            int availableSlots = msg.Value<int>("availableSlots");
            int missingSlots = msg.Value<int>("missingSlots");
            double projectedBalance = msg.Value<double>("projectedBalance");
            bool consistentCommitState = projectedBalance < 0
                ? !canCommit && blockingError == "insufficient_money"
                : blockingError == "destination_full"
                    ? !canCommit && hasPotentialCollectionAcquisition
                    : missingSlots > 0
                        ? !canCommit && blockingError == "inventory_full"
                        : canCommit && string.IsNullOrEmpty(blockingError);
            return buyTotal == purchaseTotal && sellTotal == saleTotal
                && msg.Value<double>("netDelta") == sellTotal - buyTotal
                && missingSlots == Math.Max(0, requiredSlots - availableSlots)
                && IsOneOf(msg["blockingError"], "", "insufficient_money", "inventory_full", "destination_full")
                && consistentCommitState;
        }

        private static string TradeSaleIdentity(JObject line)
        {
            JObject source = line != null ? line["source"] as JObject : null;
            if (source == null) return null;
            if (source.Value<string>("containerId") == "背包") return "bag:" + source.Value<int>("slot");
            if (source.Value<string>("viewId") == "material") return "material:" + source.Value<string>("key");
            return null;
        }

        private static bool IsSafeString(JToken token, int max, bool allowEmpty)
        {
            if (token == null || token.Type != JTokenType.String) return false;
            string value = token.Value<string>();
            if (value == null || (!allowEmpty && value.Length == 0) || value.Length > max) return false;
            for (int i = 0; i < value.Length; i++) if (char.IsControl(value[i])) return false;
            return true;
        }

        private static bool HasErrorCode(JObject msg)
        {
            return msg != null && IsSafeString(msg["error"], 80, false);
        }

        private static bool IsOneOf(JToken token, params string[] values)
        {
            if (token == null || token.Type != JTokenType.String) return false;
            string candidate = token.Value<string>();
            for (int i = 0; i < values.Length; i++) if (candidate == values[i]) return true;
            return false;
        }

        private static bool IsNonNegativeInteger(JToken token)
        {
            if (token == null || token.Type != JTokenType.Integer) return false;
            long candidate = token.Value<long>();
            return candidate >= 0 && candidate <= int.MaxValue;
        }

        private static bool TryReadPositiveInteger(JToken token, out long value)
        {
            value = 0;
            if (token == null || token.Type != JTokenType.Integer) return false;
            long candidate = token.Value<long>();
            if (candidate < 1 || candidate > 9007199254740991L) return false;
            value = candidate;
            return true;
        }

        private static bool IsNonNegativeNumber(JToken token)
        {
            if (!IsNumber(token)) return false;
            double candidate = token.Value<double>();
            return !double.IsNaN(candidate) && !double.IsInfinity(candidate) && candidate >= 0;
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
            // 背包由独立 inventory domain 负责；NPC 状态只拥有材料/情报集合投影。
            return views != null && views["material"] is JObject && views["intelligence"] is JObject;
        }

        private static bool IsNumber(JToken token)
        {
            if (token == null || (token.Type != JTokenType.Integer && token.Type != JTokenType.Float)) return false;
            double candidate = token.Value<double>();
            return !double.IsNaN(candidate) && !double.IsInfinity(candidate);
        }

        private void HandlePendingEnded(
            PanelPendingCall<PendingRequest> pendingCall,
            PanelPendingCallEndReason reason)
        {
            PendingRequest entry = pendingCall.Context;
            lock (_lock)
            {
                if (entry.IsWrite) _writeState = "needs_reconcile";
            }
            if (reason == PanelPendingCallEndReason.Cleared) return;
            RespondError(
                pendingCall.WebCallId,
                entry.WebCmd,
                reason == PanelPendingCallEndReason.Timeout ? "timeout" : "disconnected",
                entry.IsWrite);
        }

        private void RejectAndRemember(string callId, string cmd, string error)
        {
            if (!_pendingCalls.TryRememberRejected(callId)) return;
            RespondError(callId, cmd, error);
        }

        private void RespondError(string callId, string cmd, string error, bool requiresReconcile = false)
        {
            var response = new JObject
            {
                ["type"] = "panel_resp", ["domain"] = "npcshop", ["cmd"] = cmd ?? "",
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
