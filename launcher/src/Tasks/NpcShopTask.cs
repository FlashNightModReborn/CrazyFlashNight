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
            public string OwnerPanel;
            public string OwnerPanelInstanceId;
            public bool IsWrite;
            public bool IsReconcileProbe;
            public int ReconcileEpoch;
            public JObject NormalizedPayload;
            public JObject CatalogAuthority;
            public JObject BatchAuthority;
            public JObject TradeAuthority;
        }

        private sealed class CatalogAuthority
        {
            public string ShopId;
            public double Balance;
            public double BuyMultiplier;
            public JArray Catalog;
        }

        private const int DefaultTimeoutMs = 10000;
        // npc-shop.v2 的跨层整数技术护栏，不是策划购买配额。装备、情报容量与
        // purchaseLimit 仍由 AS2 在 snapshot/preview/commit 的同一权威路径裁决。
        private const int MaxPurchaseQuantity = 999999;
        private static readonly Regex ValidCallId = new Regex("^[A-Za-z0-9._-]{1,96}$", RegexOptions.Compiled);
        private static readonly Regex ValidPanelInstanceId = new Regex(
            "^[A-Za-z0-9._~-]{1,128}$",
            RegexOptions.CultureInvariant | RegexOptions.Compiled);
        private static readonly Regex ValidLease = new Regex("^[A-Za-z0-9._-]{1,160}$", RegexOptions.Compiled);

        private readonly PanelPendingCallTracker<PendingRequest> _pendingCalls;
        private readonly object _lock = new object();
        private readonly Dictionary<string, CatalogAuthority> _catalogAuthorities =
            new Dictionary<string, CatalogAuthority>(StringComparer.Ordinal);
        private readonly Dictionary<string, Dictionary<string, JObject>> _batchAuthorities =
            new Dictionary<string, Dictionary<string, JObject>>(StringComparer.Ordinal);
        private readonly Dictionary<string, Dictionary<string, JObject>> _tradeAuthorities =
            new Dictionary<string, Dictionary<string, JObject>>(StringComparer.Ordinal);
        private Action<string> _postToWeb;
        private Action<Action> _invokeOnUI;
        private string _writeState = "idle";
        private int _reconcileEpoch;
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
            lock (_lock)
            {
                _catalogAuthorities.Clear();
                _batchAuthorities.Clear();
                _tradeAuthorities.Clear();
                _pendingCalls.Dispose();
            }
        }

        public void HandleWebRequest(string cmd, JObject parsed)
        {
            string callId = parsed != null ? parsed.Value<string>("callId") : null;
            string ownerPanel = parsed != null ? parsed.Value<string>("panel") : null;
            string ownerPanelInstanceId = parsed != null
                ? parsed.Value<string>("panelInstanceId") : null;
            if (!string.Equals(ownerPanel, "npcshop", StringComparison.Ordinal)
                || string.IsNullOrEmpty(ownerPanelInstanceId)
                || !ValidPanelInstanceId.IsMatch(ownerPanelInstanceId)) return;
            if (string.IsNullOrEmpty(callId)) return;
            if (!ValidCallId.IsMatch(callId))
            {
                RespondError(callId, cmd, ownerPanel, ownerPanelInstanceId, "invalid_call_id");
                return;
            }
            if (!string.Equals(parsed.Value<string>("domain"), "npcshop", StringComparison.Ordinal))
            {
                RejectAndRemember(callId, cmd, ownerPanel, ownerPanelInstanceId, "unsupported_domain");
                return;
            }

            string action;
            bool isWrite;
            if (!TryResolveCommand(cmd, out action, out isWrite))
            {
                RejectAndRemember(callId, cmd, ownerPanel, ownerPanelInstanceId, "unsupported_cmd");
                return;
            }

            JObject payload = parsed["payload"] as JObject;
            if (payload == null || payload["v"] == null || payload["v"].Type != JTokenType.Integer)
            {
                RejectAndRemember(callId, cmd, ownerPanel, ownerPanelInstanceId, "invalid_payload");
                return;
            }
            if (payload.Value<int>("v") != 1)
            {
                RejectAndRemember(callId, cmd, ownerPanel, ownerPanelInstanceId, "unsupported_version");
                return;
            }
            JObject normalized;
            if (!TryNormalizePayload(cmd, payload, out normalized))
            {
                RejectAndRemember(callId, cmd, ownerPanel, ownerPanelInstanceId, "invalid_payload");
                return;
            }
            if (!_pendingCalls.IsReady())
            {
                RejectAndRemember(callId, cmd, ownerPanel, ownerPanelInstanceId, "disconnected");
                return;
            }

            int fid;
            lock (_lock)
            {
                if (_pendingCalls.IsKnownWebCallId(callId)) return;
                if (isWrite && _writeState != "idle")
                {
                    if (!_pendingCalls.TryRememberRejected(callId)) return;
                    RespondError(callId, cmd, ownerPanel, ownerPanelInstanceId,
                        _writeState == "needs_reconcile" ? "reconcile_required" : "busy");
                    return;
                }
                JObject catalogAuthority = null;
                JObject batchAuthority = null;
                JObject tradeAuthority = null;
                if ((cmd == "buy" || cmd == "tradePreview")
                    && !TryFreezeCatalogAuthorityLocked(
                        ownerPanelInstanceId,
                        normalized.Value<string>("shopId"),
                        out catalogAuthority))
                {
                    if (!_pendingCalls.TryRememberRejected(callId)) return;
                    RespondError(callId, cmd, ownerPanel, ownerPanelInstanceId, "stale_state");
                    return;
                }
                if (cmd == "batchSell"
                    && !TryFreezePreviewAuthorityLocked(
                        _batchAuthorities,
                        ownerPanelInstanceId,
                        normalized.Value<string>("expectedBatchToken"),
                        null,
                        out batchAuthority))
                {
                    if (!_pendingCalls.TryRememberRejected(callId)) return;
                    RespondError(callId, cmd, ownerPanel, ownerPanelInstanceId, "stale_state");
                    return;
                }
                if (cmd == "tradeCommit"
                    && !TryFreezePreviewAuthorityLocked(
                        _tradeAuthorities,
                        ownerPanelInstanceId,
                        normalized.Value<string>("expectedTradeToken"),
                        normalized.Value<string>("shopId"),
                        out tradeAuthority))
                {
                    if (!_pendingCalls.TryRememberRejected(callId)) return;
                    RespondError(callId, cmd, ownerPanel, ownerPanelInstanceId, "stale_state");
                    return;
                }
                if (!_pendingCalls.TryBegin(
                    callId,
                    new PendingRequest
                    {
                        WebCmd = cmd,
                        OwnerPanel = ownerPanel,
                        OwnerPanelInstanceId = ownerPanelInstanceId,
                        IsWrite = isWrite,
                        IsReconcileProbe = cmd == "snapshot"
                            && _writeState == "needs_reconcile",
                        ReconcileEpoch = _reconcileEpoch,
                        NormalizedPayload = (JObject)normalized.DeepClone(),
                        CatalogAuthority = catalogAuthority,
                        BatchAuthority = batchAuthority,
                        TradeAuthority = tradeAuthority
                    },
                    out fid)) return;
                if (batchAuthority != null)
                    ConsumePreviewAuthorityLocked(
                        _batchAuthorities,
                        ownerPanelInstanceId,
                        normalized.Value<string>("expectedBatchToken"));
                if (tradeAuthority != null)
                    ConsumePreviewAuthorityLocked(
                        _tradeAuthorities,
                        ownerPanelInstanceId,
                        normalized.Value<string>("expectedTradeToken"));
                if (isWrite) _writeState = "write_pending";
            }

            JObject flash = PanelBridge.BuildFlashCommand(action, fid, normalized);
            string json = flash.ToString(Formatting.None);
            LogManager.Log(AuthorityLogFormatter.FormatAuthorityFlashCallBound(
                "NpcShopTask", callId, fid, ownerPanel, ownerPanelInstanceId,
                cmd, action));
            LogManager.Log(AuthorityLogFormatter.FormatFlashCommand(
                "NpcShopTask", flash));
            _pendingCalls.Send(fid, json + "\0");
        }

        public void HandleFlashResponse(JObject msg, Action<string> respond)
        {
            int fid = msg != null ? msg.Value<int>("callId") : 0;
            PendingRequest entry;
            PanelPendingCall<PendingRequest> pendingCall;
            bool malformed = false;
            bool definitiveWrite = false;
            JObject sanitized = null;
            lock (_lock)
            {
                if (!_pendingCalls.TryComplete(fid, out pendingCall))
                {
                    if (respond != null) respond(null);
                    return;
                }
                entry = pendingCall.Context;
                malformed = !TrySanitizeResponse(msg, entry, out sanitized);
                definitiveWrite = entry.IsWrite && !malformed && IsDefinitiveWriteResponse(msg, entry.WebCmd);
                if (!malformed && msg != null && msg.Value<bool?>("success") == true
                    && IsStateResponseCommand(entry.WebCmd))
                    RememberCatalogAuthorityLocked(entry, sanitized);
                if (!malformed && msg != null && msg.Value<bool?>("success") == true
                    && entry.WebCmd == "batchPreview")
                    RememberPreviewAuthorityLocked(
                        _batchAuthorities,
                        entry.OwnerPanelInstanceId,
                        sanitized.Value<string>("batchToken"),
                        sanitized);
                if (!malformed && msg != null && msg.Value<bool?>("success") == true
                    && entry.WebCmd == "tradePreview"
                    && sanitized.Value<bool?>("canCommit") == true)
                    RememberPreviewAuthorityLocked(
                        _tradeAuthorities,
                        entry.OwnerPanelInstanceId,
                        sanitized.Value<string>("tradeToken"),
                        sanitized);
                if (entry.IsWrite)
                {
                    ClearPreviewAuthoritiesLocked(entry.OwnerPanelInstanceId);
                    if (definitiveWrite) _writeState = "idle";
                    else
                    {
                        _catalogAuthorities.Remove(entry.OwnerPanelInstanceId);
                        EnterNeedsReconcileLocked();
                    }
                }
                else if (entry.IsReconcileProbe
                    && entry.ReconcileEpoch == _reconcileEpoch
                    && entry.WebCmd == "snapshot" && !malformed
                    && msg != null && msg.Value<bool?>("success") == true
                    && _writeState == "needs_reconcile")
                    _writeState = "idle";
            }
            JObject web = malformed
                ? new JObject { ["success"] = false, ["error"] = "malformed_response" }
                : sanitized;
            web["type"] = "panel_resp";
            web["domain"] = "npcshop";
            web["panel"] = entry.OwnerPanel;
            web["panelInstanceId"] = entry.OwnerPanelInstanceId;
            web["cmd"] = entry.WebCmd;
            web["callId"] = pendingCall.WebCallId;
            if (entry.IsWrite && !definitiveWrite) web["requiresReconcile"] = true;
            PostToWeb(web.ToString(Formatting.None));
            if (respond != null) respond(null);
        }

        public void ClearPending()
        {
            lock (_lock)
            {
                _catalogAuthorities.Clear();
                _batchAuthorities.Clear();
                _tradeAuthorities.Clear();
                _pendingCalls.Clear();
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

        private static bool TrySanitizeResponse(
            JObject msg,
            PendingRequest entry,
            out JObject sanitized)
        {
            sanitized = null;
            if (msg == null || entry == null || msg["success"] == null
                || msg["success"].Type != JTokenType.Boolean) return false;
            if (!msg.Value<bool>("success"))
            {
                if (!HasErrorCode(msg)) return false;
                sanitized = new JObject
                {
                    ["success"] = false,
                    ["error"] = msg.Value<string>("error")
                };
                return true;
            }

            if (entry.WebCmd == "snapshot")
            {
                if (!IsAuthoritativeState(msg, entry.NormalizedPayload, null,
                        null, null, null)) return false;
                sanitized = CopyResponseKeys(msg, "success", "v", "shopId", "balance",
                    "buyMultiplier", "catalog", "layout", "views");
                return true;
            }
            if (entry.WebCmd == "tradePreview")
            {
                if (!IsAuthoritativeTradePreview(
                        msg,
                        entry.NormalizedPayload,
                        entry.CatalogAuthority)) return false;
                sanitized = CopyResponseKeys(msg, "success", "v", "shopId", "tradeToken",
                    "purchaseLines", "saleLines", "buyTotal", "sellTotal", "netDelta",
                    "projectedBalance", "requiredSlots", "availableSlots", "missingSlots",
                    "canCommit", "blockingError");
                return true;
            }
            if (entry.WebCmd == "batchPreview")
                return TrySanitizeBatchPreview(msg, entry.NormalizedPayload, out sanitized);
            if (entry.WebCmd == "tooltip")
                return TrySanitizeTooltip(msg, entry.NormalizedPayload, out sanitized);
            if (!entry.IsWrite
                || !IsAuthoritativeState(
                    msg,
                    entry.NormalizedPayload,
                    entry.WebCmd,
                    entry.CatalogAuthority,
                    entry.BatchAuthority,
                    entry.TradeAuthority)) return false;

            if (entry.WebCmd == "buy")
                sanitized = CopyResponseKeys(msg, "success", "v", "shopId", "balance",
                    "buyMultiplier", "catalog", "layout", "views", "operation",
                    "destinationView", "itemName", "quantity", "total");
            else if (entry.WebCmd == "batchSell")
                sanitized = CopyResponseKeys(msg, "success", "v", "shopId", "balance",
                    "buyMultiplier", "catalog", "layout", "views", "operation",
                    "quantity", "total");
            else
                sanitized = CopyResponseKeys(msg, "success", "v", "shopId", "balance",
                    "buyMultiplier", "catalog", "layout", "views", "operation", "trade");
            return true;
        }

        private static JObject CopyResponseKeys(JObject source, params string[] keys)
        {
            var result = new JObject();
            foreach (string key in keys)
                if (source.Property(key) != null) result[key] = source[key].DeepClone();
            return result;
        }

        private bool TryFreezeCatalogAuthorityLocked(
            string ownerPanelInstanceId,
            string shopId,
            out JObject frozen)
        {
            frozen = null;
            CatalogAuthority current;
            if (string.IsNullOrEmpty(ownerPanelInstanceId)
                || string.IsNullOrEmpty(shopId)
                || !_catalogAuthorities.TryGetValue(ownerPanelInstanceId, out current)
                || current == null
                || current.ShopId != shopId
                || current.Catalog == null) return false;
            frozen = new JObject
            {
                ["shopId"] = current.ShopId,
                ["balance"] = current.Balance,
                ["buyMultiplier"] = current.BuyMultiplier,
                ["catalog"] = current.Catalog.DeepClone()
            };
            return true;
        }

        private void RememberCatalogAuthorityLocked(PendingRequest entry, JObject state)
        {
            JArray catalog = state != null ? state["catalog"] as JArray : null;
            string shopId = state != null ? state.Value<string>("shopId") : null;
            if (entry == null || string.IsNullOrEmpty(entry.OwnerPanelInstanceId)
                || string.IsNullOrEmpty(shopId) || catalog == null) return;
            if (_catalogAuthorities.Count >= 32
                && !_catalogAuthorities.ContainsKey(entry.OwnerPanelInstanceId))
                _catalogAuthorities.Clear();
            _catalogAuthorities[entry.OwnerPanelInstanceId] = new CatalogAuthority
            {
                ShopId = shopId,
                Balance = state.Value<double>("balance"),
                BuyMultiplier = state.Value<double>("buyMultiplier"),
                Catalog = (JArray)catalog.DeepClone()
            };
        }

        private static bool IsStateResponseCommand(string cmd)
        {
            return cmd == "snapshot" || cmd == "buy"
                || cmd == "batchSell" || cmd == "tradeCommit";
        }

        private static JObject FindCatalogEntry(JArray catalog, int catalogIndex)
        {
            if (catalog == null) return null;
            foreach (JToken token in catalog)
            {
                JObject line = token as JObject;
                if (line != null && line.Value<int?>("catalogIndex") == catalogIndex)
                    return line;
            }
            return null;
        }

        private static bool MatchesCatalogIdentity(JObject candidate, JObject authority)
        {
            return candidate != null && authority != null
                && candidate.Value<string>("itemName") == authority.Value<string>("itemName")
                && candidate.Value<string>("displayName") == authority.Value<string>("displayName")
                && candidate.Value<string>("icon") == authority.Value<string>("icon");
        }

        private static bool MatchesTradePurchaseCatalog(JObject state, JObject tradeAuthority)
        {
            JArray catalog = state != null ? state["catalog"] as JArray : null;
            JArray purchaseLines = tradeAuthority != null
                ? tradeAuthority["purchaseLines"] as JArray : null;
            if (catalog == null || purchaseLines == null) return false;
            foreach (JToken token in purchaseLines)
            {
                JObject frozenLine = token as JObject;
                int catalogIndex;
                if (frozenLine == null
                    || !TryReadInteger(frozenLine["catalogIndex"], 0, 10000, out catalogIndex))
                    return false;
                JObject currentLine = FindCatalogEntry(catalog, catalogIndex);
                if (!MatchesCatalogIdentity(currentLine, frozenLine)
                    || currentLine.Value<double>("unitPrice")
                        != frozenLine.Value<double>("unitPrice")) return false;
            }
            return true;
        }

        private static bool TryFreezePreviewAuthorityLocked(
            Dictionary<string, Dictionary<string, JObject>> authorities,
            string ownerPanelInstanceId,
            string token,
            string expectedShopId,
            out JObject frozen)
        {
            frozen = null;
            Dictionary<string, JObject> ownerAuthorities;
            JObject current;
            if (string.IsNullOrEmpty(ownerPanelInstanceId)
                || string.IsNullOrEmpty(token)
                || !authorities.TryGetValue(ownerPanelInstanceId, out ownerAuthorities)
                || ownerAuthorities == null
                || !ownerAuthorities.TryGetValue(token, out current)
                || current == null
                || (expectedShopId != null
                    && current.Value<string>("shopId") != expectedShopId)) return false;
            frozen = (JObject)current.DeepClone();
            return true;
        }

        private static void RememberPreviewAuthorityLocked(
            Dictionary<string, Dictionary<string, JObject>> authorities,
            string ownerPanelInstanceId,
            string token,
            JObject preview)
        {
            if (string.IsNullOrEmpty(ownerPanelInstanceId)
                || string.IsNullOrEmpty(token) || preview == null) return;
            Dictionary<string, JObject> ownerAuthorities;
            if (!authorities.TryGetValue(ownerPanelInstanceId, out ownerAuthorities))
            {
                ownerAuthorities = new Dictionary<string, JObject>(StringComparer.Ordinal);
                authorities[ownerPanelInstanceId] = ownerAuthorities;
            }
            // Flash keeps one current batch/trade plan per NPC shop owner. Mirror that
            // latest-preview contract locally so an older but once-valid token fails
            // before dispatch after a newer authoritative preview has replaced it.
            ownerAuthorities.Clear();
            ownerAuthorities[token] = (JObject)preview.DeepClone();
        }

        private static void ConsumePreviewAuthorityLocked(
            Dictionary<string, Dictionary<string, JObject>> authorities,
            string ownerPanelInstanceId,
            string token)
        {
            Dictionary<string, JObject> ownerAuthorities;
            if (!authorities.TryGetValue(ownerPanelInstanceId, out ownerAuthorities)) return;
            ownerAuthorities.Remove(token);
            if (ownerAuthorities.Count == 0) authorities.Remove(ownerPanelInstanceId);
        }

        private void ClearPreviewAuthoritiesLocked(string ownerPanelInstanceId)
        {
            _batchAuthorities.Remove(ownerPanelInstanceId);
            _tradeAuthorities.Remove(ownerPanelInstanceId);
        }

        private static bool TrySanitizeBatchPreview(
            JObject msg,
            JObject request,
            out JObject sanitized)
        {
            sanitized = null;
            JArray requested = request != null ? request["itemNames"] as JArray : null;
            JArray summary = msg != null ? msg["summary"] as JArray : null;
            string token = msg != null ? msg.Value<string>("batchToken") : null;
            long totalQuantity;
            int skipped;
            if (msg == null || msg.Value<int?>("v") != 1 || requested == null
                || summary == null || summary.Count > requested.Count
                || string.IsNullOrEmpty(token) || !ValidLease.IsMatch(token)
                || !TryReadPositiveInteger(msg["totalQuantity"], out totalQuantity)
                || !IsNonNegativeNumber(msg["totalMoney"])
                || !TryReadInteger(msg["skipped"], 0, int.MaxValue, out skipped)) return false;
            var requestedNames = new HashSet<string>(StringComparer.Ordinal);
            foreach (JToken requestedName in requested)
                if (requestedName.Type != JTokenType.String
                    || !requestedNames.Add(requestedName.Value<string>())) return false;
            var seen = new HashSet<string>(StringComparer.Ordinal);
            long quantitySum = 0;
            double moneySum = 0;
            foreach (JToken tokenValue in summary)
            {
                JObject line = tokenValue as JObject;
                long quantity;
                string itemName = line != null ? line.Value<string>("itemName") : null;
                if (!HasOnlyKeys(line, "itemName", "displayName", "icon", "quantity", "money")
                    || !IsIdentityString(line["itemName"], 128)
                    || !IsIdentityString(line["displayName"], 256)
                    || !IsIdentityString(line["icon"], 256)
                    || !requestedNames.Contains(itemName) || !seen.Add(itemName)
                    || !TryReadPositiveInteger(line["quantity"], out quantity)
                    || !IsNonNegativeNumber(line["money"])) return false;
                quantitySum += quantity;
                moneySum += line.Value<double>("money");
            }
            if (summary.Count == 0 || quantitySum != totalQuantity
                || moneySum != msg.Value<double>("totalMoney")) return false;
            sanitized = CopyResponseKeys(msg, "success", "v", "batchToken", "summary",
                "totalQuantity", "totalMoney", "skipped");
            return true;
        }

        private static bool TrySanitizeTooltip(
            JObject msg,
            JObject request,
            out JObject sanitized)
        {
            sanitized = null;
            if (msg == null || msg.Value<int?>("v") != 1
                || !IsIdentityString(msg["itemName"], 128)
                || !IsIdentityString(msg["displayname"], 256)
                || !IsSafeMultilineString(msg["descHTML"], 20000)
                || !IsSafeMultilineString(msg["introHTML"], 20000)) return false;
            string requestedName = request != null ? request.Value<string>("itemName") : null;
            if (!string.IsNullOrEmpty(requestedName)
                && msg.Value<string>("itemName") != requestedName) return false;
            if (msg.Property("iconName") != null
                && !IsIdentityString(msg["iconName"], 256)) return false;
            if (msg.Property("itemType") != null
                && !IsSafeString(msg["itemType"], 128, true)) return false;
            sanitized = CopyResponseKeys(msg, "success", "v", "itemName", "displayname",
                "iconName", "itemType", "descHTML", "introHTML");
            return true;
        }

        private static bool IsSafeMultilineString(JToken token, int max)
        {
            if (token == null || token.Type != JTokenType.String) return false;
            string value = token.Value<string>();
            if (value == null || value.Length > max) return false;
            for (int i = 0; i < value.Length; i++)
            {
                char current = value[i];
                if (char.IsControl(current) && current != '\r'
                    && current != '\n' && current != '\t') return false;
            }
            return true;
        }

        private static bool IsAuthoritativeTradePreview(
            JObject msg,
            JObject request,
            JObject catalogAuthority)
        {
            if (msg == null || msg["v"] == null || msg["v"].Type != JTokenType.Integer
                || msg.Value<int>("v") != 1 || request == null
                || !IsSafeString(msg["shopId"], 80, false)
                || msg.Value<string>("shopId") != request.Value<string>("shopId")) return false;
            string token = msg.Value<string>("tradeToken");
            JArray purchaseLines = msg["purchaseLines"] as JArray;
            JArray saleLines = msg["saleLines"] as JArray;
            JArray requestedPurchases = request["purchases"] as JArray;
            JArray requestedSales = request["sales"] as JArray;
            JArray authoritativeCatalog = catalogAuthority != null
                ? catalogAuthority["catalog"] as JArray : null;
            double authoritativeMultiplier = catalogAuthority != null
                ? catalogAuthority.Value<double>("buyMultiplier") : -1;
            double authoritativeBalance = catalogAuthority != null
                ? catalogAuthority.Value<double>("balance") : double.NaN;
            if (msg["tradeToken"] == null || msg["tradeToken"].Type != JTokenType.String
                || string.IsNullOrEmpty(token) || !ValidLease.IsMatch(token)
                || purchaseLines == null || saleLines == null
                || requestedPurchases == null || requestedSales == null
                || authoritativeCatalog == null
                || authoritativeMultiplier < 0
                || double.IsNaN(authoritativeBalance) || double.IsInfinity(authoritativeBalance)
                || catalogAuthority.Value<string>("shopId") != request.Value<string>("shopId")
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
                JObject authoritativeLine;
                string itemKind = line != null ? line.Value<string>("itemKind") : null;
                string destinationView = line != null ? line.Value<string>("destinationView") : null;
                if (!HasOnlyKeys(line, "catalogIndex", "itemName", "displayName", "icon",
                        "quantity", "unitPrice", "total", "maxQuantity", "itemKind",
                        "destinationView", "purchaseLimit", "maxAffordable", "maxByCapacity",
                        "maxPurchasable", "limitingReason")
                    || !TryReadInteger(line["catalogIndex"], 0, 10000, out catalogIndex)
                    || !seenPurchases.Add(catalogIndex)
                    || !requestedPurchaseById.TryGetValue(catalogIndex, out requestedLine)
                    || (authoritativeLine = FindCatalogEntry(authoritativeCatalog, catalogIndex)) == null
                    || !TryReadInteger(line["quantity"], 1, MaxPurchaseQuantity, out quantity)
                    || quantity != requestedLine.Value<int>("quantity")
                    || !TryReadInteger(line["maxQuantity"], 1, MaxPurchaseQuantity, out maxQuantity)
                    || !TryReadInteger(line["purchaseLimit"], 1, MaxPurchaseQuantity, out purchaseLimit)
                    || quantity > maxQuantity || quantity > purchaseLimit || maxQuantity != purchaseLimit
                    || !TryReadInteger(line["maxAffordable"], 0, MaxPurchaseQuantity, out maxAffordable)
                    || !TryReadInteger(line["maxByCapacity"], 0, MaxPurchaseQuantity, out maxByCapacity)
                    || !TryReadInteger(line["maxPurchasable"], 0, MaxPurchaseQuantity, out maxPurchasable)
                    || maxPurchasable > purchaseLimit || maxPurchasable > maxAffordable || maxPurchasable > maxByCapacity
                    || !IsIdentityString(line["itemName"], 128)
                    || !IsIdentityString(line["displayName"], 256)
                    || !IsIdentityString(line["icon"], 256)
                    || !IsOneOf(line["itemKind"], "equipment", "stack")
                    || !IsOneOf(line["destinationView"], "bag", "material", "intelligence", "quickslot")
                    || (destinationView == "intelligence" && itemKind != "stack")
                    || !IsOneOf(line["limitingReason"], "", "insufficient_money", "inventory_full", "destination_full")
                    || !IsNonNegativeNumber(line["unitPrice"]) || !IsNonNegativeNumber(line["total"])
                    || !MatchesCatalogIdentity(line, authoritativeLine)
                    || line.Value<double>("unitPrice") != authoritativeLine.Value<double>("unitPrice")
                    || line.Value<double>("total") != Math.Floor(
                        authoritativeLine.Value<double>("basePrice")
                        * quantity * authoritativeMultiplier)
                    || maxQuantity != authoritativeLine.Value<int>("maxQuantity")) return false;
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
                if (!HasOnlyKeys(line, "itemName", "displayName", "icon", "itemKind",
                        "quantity", "total", "sourceIdentity", "scope", "matchedCount",
                        "eligibleCount", "protectedCount")
                    || string.IsNullOrEmpty(identity) || !seenSales.Add(identity)
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
                    || !IsIdentityString(line["itemName"], 128)
                    || !IsIdentityString(line["displayName"], 256)
                    || !IsIdentityString(line["icon"], 256)
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
                && projectedBalance == authoritativeBalance + sellTotal - buyTotal
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

        private static bool IsIdentityString(JToken token, int max)
        {
            if (!IsSafeString(token, max, false)) return false;
            string value = token.Value<string>();
            return !string.IsNullOrWhiteSpace(value)
                && !string.Equals(value.Trim(), "undefined", StringComparison.OrdinalIgnoreCase);
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
            return msg != null && msg.Value<string>("operation") == cmd;
        }

        private static bool IsAuthoritativeState(
            JObject msg,
            JObject request,
            string expectedOperation,
            JObject catalogAuthority,
            JObject batchAuthority,
            JObject tradeAuthority)
        {
            string requestedShopId = request != null ? request.Value<string>("shopId") : null;
            if (msg == null || msg.Value<int?>("v") != 1
                || !IsSafeString(msg["shopId"], 80, false)
                || string.IsNullOrEmpty(requestedShopId)
                || msg.Value<string>("shopId") != requestedShopId
                || !IsNumber(msg["balance"])
                || !IsNonNegativeNumber(msg["buyMultiplier"])
                || !TryValidateCatalog(
                    msg["catalog"] as JArray,
                    msg.Value<double>("buyMultiplier"))
                || !TryValidateLayout(msg["layout"] as JObject)) return false;
            JObject views = msg["views"] as JObject;
            // 背包由独立 inventory domain 负责；NPC 状态只拥有材料/情报集合投影。
            if (!HasOnlyKeys(views, "material", "intelligence")
                || !TryValidateCollectionView(views["material"] as JObject, "material")
                || !TryValidateCollectionView(views["intelligence"] as JObject, "intelligence")) return false;
            if (expectedOperation == null) return true;
            if (msg.Value<string>("operation") != expectedOperation) return false;
            int requestedQuantity;
            int resultQuantity;
            if (expectedOperation == "buy")
            {
                int catalogIndex;
                JArray authoritativeCatalog = catalogAuthority != null
                    ? catalogAuthority["catalog"] as JArray : null;
                JObject authoritativeLine;
                JObject currentLine;
                return catalogAuthority != null
                    && catalogAuthority.Value<string>("shopId") == requestedShopId
                    && authoritativeCatalog != null
                    && TryReadInteger(request["catalogIndex"], 0, 10000, out catalogIndex)
                    && (authoritativeLine = FindCatalogEntry(authoritativeCatalog, catalogIndex)) != null
                    && (currentLine = FindCatalogEntry(msg["catalog"] as JArray, catalogIndex)) != null
                    && MatchesCatalogIdentity(currentLine, authoritativeLine)
                    && currentLine.Value<double>("unitPrice") == authoritativeLine.Value<double>("unitPrice")
                    && msg.Value<double>("buyMultiplier")
                        == catalogAuthority.Value<double>("buyMultiplier")
                    && TryReadInteger(request["quantity"], 1, MaxPurchaseQuantity, out requestedQuantity)
                    && requestedQuantity <= authoritativeLine.Value<int>("maxQuantity")
                    && TryReadInteger(msg["quantity"], 1, MaxPurchaseQuantity, out resultQuantity)
                    && resultQuantity == requestedQuantity
                    && IsIdentityString(msg["itemName"], 128)
                    && msg.Value<string>("itemName") == authoritativeLine.Value<string>("itemName")
                    && IsOneOf(msg["destinationView"], "bag", "material", "intelligence", "quickslot")
                    && IsNonNegativeNumber(msg["total"])
                    && msg.Value<double>("total")
                        == Math.Floor(
                            authoritativeLine.Value<double>("basePrice")
                            * resultQuantity
                            * catalogAuthority.Value<double>("buyMultiplier"))
                    && msg.Value<double>("balance")
                        == catalogAuthority.Value<double>("balance") - msg.Value<double>("total");
            }
            if (expectedOperation == "batchSell")
            {
                long previewQuantity;
                return batchAuthority != null
                    && batchAuthority.Value<string>("batchToken")
                        == request.Value<string>("expectedBatchToken")
                    && TryReadPositiveInteger(batchAuthority["totalQuantity"], out previewQuantity)
                    && TryReadInteger(msg["quantity"], 1, int.MaxValue, out resultQuantity)
                    && previewQuantity == resultQuantity
                    && IsNonNegativeNumber(msg["total"])
                    && IsNonNegativeNumber(batchAuthority["totalMoney"])
                    && msg.Value<double>("total") == batchAuthority.Value<double>("totalMoney");
            }
            JObject trade = msg["trade"] as JObject;
            return expectedOperation == "tradeCommit"
                && tradeAuthority != null
                && tradeAuthority.Value<string>("shopId") == requestedShopId
                && tradeAuthority.Value<string>("tradeToken")
                    == request.Value<string>("expectedTradeToken")
                && tradeAuthority.Value<bool?>("canCommit") == true
                && MatchesTradePurchaseCatalog(msg, tradeAuthority)
                && msg.Value<double>("balance") == tradeAuthority.Value<double>("projectedBalance")
                && HasOnlyKeys(trade, "buyTotal", "sellTotal", "netDelta")
                && IsNonNegativeNumber(trade["buyTotal"])
                && IsNonNegativeNumber(trade["sellTotal"])
                && IsNumber(trade["netDelta"])
                && trade.Value<double>("buyTotal") == tradeAuthority.Value<double>("buyTotal")
                && trade.Value<double>("sellTotal") == tradeAuthority.Value<double>("sellTotal")
                && trade.Value<double>("netDelta") == tradeAuthority.Value<double>("netDelta")
                && trade.Value<double>("netDelta")
                    == trade.Value<double>("sellTotal") - trade.Value<double>("buyTotal");
        }

        private static bool TryValidateCatalog(JArray catalog, double buyMultiplier)
        {
            if (catalog == null || catalog.Count > 10001) return false;
            var indexes = new HashSet<int>();
            foreach (JToken token in catalog)
            {
                JObject line = token as JObject;
                int catalogIndex;
                int setOrder;
                int maxQuantity;
                if (!HasOnlyKeys(line, "catalogIndex", "itemName", "displayName", "icon",
                        "majorType", "use", "actionType", "weaponType", "setId", "setName",
                        "setOrder", "basePrice", "unitPrice", "maxQuantity", "requiredInfo",
                        "locked", "balanceSummary")
                    || !TryReadInteger(line["catalogIndex"], 0, 10000, out catalogIndex)
                    || !indexes.Add(catalogIndex)
                    || !IsIdentityString(line["itemName"], 128)
                    || !IsIdentityString(line["displayName"], 256)
                    || !IsIdentityString(line["icon"], 256)
                    || !IsSafeString(line["majorType"], 128, true)
                    || !IsSafeString(line["use"], 128, true)
                    || !IsSafeString(line["actionType"], 128, true)
                    || !IsSafeString(line["weaponType"], 128, true)
                    || !IsSafeString(line["setId"], 256, true)
                    || !IsSafeString(line["setName"], 256, true)
                    || !TryReadInteger(line["setOrder"], 0, int.MaxValue, out setOrder)
                    || !IsNonNegativeNumber(line["basePrice"])
                    || !IsNonNegativeNumber(line["unitPrice"])
                    || line.Value<double>("unitPrice")
                        != Math.Floor(line.Value<double>("basePrice") * buyMultiplier)
                    || !TryReadInteger(line["maxQuantity"], 0, MaxPurchaseQuantity, out maxQuantity)
                    || !IsSafeString(line["requiredInfo"], 256, true)
                    || line["locked"] == null || line["locked"].Type != JTokenType.Boolean
                    || (line.Property("balanceSummary") != null
                        && !IsSafeJsonTree(line["balanceSummary"], 0))) return false;
            }
            return true;
        }

        private static bool TryValidateLayout(JObject layout)
        {
            if (!HasOnlyKeys(layout, "title", "defaultSection", "sections")
                || !IsSafeString(layout["title"], 256, false)
                || !IsSafeString(layout["defaultSection"], 128, true)
                || !(layout["sections"] is JArray sections) || sections.Count > 128) return false;
            foreach (JToken token in sections)
            {
                JObject section = token as JObject;
                if (!HasOnlyKeys(section, "id", "label", "kind", "entries")
                    || !IsSafeString(section["id"], 128, true)
                    || !IsSafeString(section["label"], 256, true)
                    || !IsSafeString(section["kind"], 128, true)
                    || !(section["entries"] is JArray entries) || entries.Count > 10001) return false;
                var seen = new HashSet<int>();
                foreach (JToken entry in entries)
                {
                    int index;
                    if (!TryReadInteger(entry, 0, 10000, out index) || !seen.Add(index)) return false;
                }
            }
            return true;
        }

        private static bool TryValidateCollectionView(JObject view, string viewId)
        {
            if (!HasOnlyKeys(view, "containerId", "capacity", "accessibleCapacity",
                    "viewCapacity", "offset", "limit", "filterKey", "slots")
                || view.Value<string>("containerId") != (viewId == "material" ? "材料" : "情报")
                || !IsSafeString(view["filterKey"], 128, false)
                || !(view["slots"] is JArray slots)) return false;
            int capacity;
            int accessible;
            int viewCapacity;
            int offset;
            int limit;
            if (!TryReadInteger(view["capacity"], 0, 100000, out capacity)
                || !TryReadInteger(view["accessibleCapacity"], 0, 100000, out accessible)
                || !TryReadInteger(view["viewCapacity"], 0, 100000, out viewCapacity)
                || !TryReadInteger(view["offset"], 0, 100000, out offset)
                || !TryReadInteger(view["limit"], 0, 100000, out limit)
                || accessible > capacity || viewCapacity > accessible
                || offset != 0 || limit != viewCapacity || slots.Count != viewCapacity) return false;
            var physicalSlots = new HashSet<int>();
            var keys = new HashSet<string>(StringComparer.Ordinal);
            foreach (JToken token in slots)
            {
                JObject slot = token as JObject;
                JObject item = slot != null ? slot["item"] as JObject : null;
                int physicalSlot;
                long quantity;
                string collectionKey = slot != null ? slot.Value<string>("collectionKey") : null;
                if (!HasOnlyKeys(slot, "physicalSlot", "collectionKey", "occupied", "slotLease", "item")
                    || !TryReadInteger(slot["physicalSlot"], 0, 100000, out physicalSlot)
                    || !physicalSlots.Add(physicalSlot)
                    || !IsSafeString(slot["collectionKey"], 128, false) || !keys.Add(collectionKey)
                    || slot.Value<bool?>("occupied") != true
                    || !IsSafeString(slot["slotLease"], 160, false)
                    || !ValidLease.IsMatch(slot.Value<string>("slotLease"))
                    || !HasOnlyKeys(item, "itemKind", "name", "displayName", "icon",
                        "majorType", "use", "quantity", "enhancementLevel", "rarity")
                    || item.Value<string>("itemKind") != "stack"
                    || !IsIdentityString(item["name"], 128)
                    || item.Value<string>("name") != collectionKey
                    || !IsIdentityString(item["displayName"], 256)
                    || !IsIdentityString(item["icon"], 256)
                    || !IsSafeString(item["majorType"], 128, true)
                    || !IsSafeString(item["use"], 128, true)
                    || !TryReadPositiveInteger(item["quantity"], out quantity)
                    || item.Value<int?>("enhancementLevel") != 0
                    || !IsSafeString(item["rarity"], 128, true)) return false;
            }
            return true;
        }

        private static bool IsSafeJsonTree(JToken token, int depth)
        {
            if (token == null || depth > 6) return false;
            if (token.Type == JTokenType.String) return IsSafeString(token, 1024, true);
            if (token.Type == JTokenType.Integer || token.Type == JTokenType.Float) return IsNumber(token);
            if (token.Type == JTokenType.Boolean || token.Type == JTokenType.Null) return true;
            if (token is JArray array)
            {
                if (array.Count > 512) return false;
                foreach (JToken child in array) if (!IsSafeJsonTree(child, depth + 1)) return false;
                return true;
            }
            if (token is JObject value)
            {
                if (value.Count > 128) return false;
                foreach (JProperty property in value.Properties())
                    if (!IsSafeText(property.Name, 128)
                        || !IsSafeJsonTree(property.Value, depth + 1)) return false;
                return true;
            }
            return false;
        }

        private static bool HasOnlyKeys(JObject value, params string[] allowed)
        {
            if (value == null) return false;
            foreach (JProperty property in value.Properties())
            {
                bool found = false;
                for (int i = 0; i < allowed.Length; i++)
                {
                    if (string.Equals(property.Name, allowed[i], StringComparison.Ordinal))
                    {
                        found = true;
                        break;
                    }
                }
                if (!found) return false;
            }
            return true;
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
                if (entry.IsWrite)
                {
                    _catalogAuthorities.Remove(entry.OwnerPanelInstanceId);
                    ClearPreviewAuthoritiesLocked(entry.OwnerPanelInstanceId);
                    EnterNeedsReconcileLocked();
                }
            }
            if (reason == PanelPendingCallEndReason.Cleared) return;
            RespondError(
                pendingCall.WebCallId,
                entry.WebCmd,
                entry.OwnerPanel,
                entry.OwnerPanelInstanceId,
                reason == PanelPendingCallEndReason.Timeout ? "timeout" : "disconnected",
                entry.IsWrite);
        }

        private void EnterNeedsReconcileLocked()
        {
            _writeState = "needs_reconcile";
            _reconcileEpoch++;
        }

        private void RejectAndRemember(string callId, string cmd,
            string ownerPanel, string ownerPanelInstanceId, string error)
        {
            if (!_pendingCalls.TryRememberRejected(callId)) return;
            RespondError(callId, cmd, ownerPanel, ownerPanelInstanceId, error);
        }

        private void RespondError(string callId, string cmd,
            string ownerPanel, string ownerPanelInstanceId, string error,
            bool requiresReconcile = false)
        {
            var response = new JObject
            {
                ["type"] = "panel_resp", ["domain"] = "npcshop", ["cmd"] = cmd ?? "",
                ["panel"] = ownerPanel, ["panelInstanceId"] = ownerPanelInstanceId,
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
