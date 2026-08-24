using System;
using System.Collections.Generic;
using System.Text;
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
            public long Balance;
            public long BuyRatePermille;
            public JArray Catalog;
        }

        private sealed class ResponseValidationFailure
        {
            public string Stage;
            public string FieldPath;
            public string Expected;
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
        private string _navigationOwnerPanel;
        private string _navigationOwnerPanelInstanceId;
        private string _navigationLeaseToken;
        private bool _navigationLeaseTransferred;
        private long _navigationGeneration;
        private bool _disposed;
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
                if (_disposed) return;
                _disposed = true;
                _navigationGeneration++;
                _navigationLeaseToken = null;
                _navigationLeaseTransferred = false;
                _navigationOwnerPanel = null;
                _navigationOwnerPanelInstanceId = null;
                _catalogAuthorities.Clear();
                _batchAuthorities.Clear();
                _tradeAuthorities.Clear();
                _pendingCalls.Dispose();
            }
        }

        internal void BindMaterialShopNavigationOwner(
            string panelName,
            string panelInstanceId)
        {
            lock (_lock)
            {
                if (_disposed) return;
                if (string.Equals(_navigationOwnerPanel, panelName, StringComparison.Ordinal)
                    && string.Equals(
                        _navigationOwnerPanelInstanceId,
                        panelInstanceId,
                        StringComparison.Ordinal))
                {
                    return;
                }
                _navigationLeaseToken = null;
                _navigationLeaseTransferred = false;
                _navigationOwnerPanel = panelName;
                _navigationOwnerPanelInstanceId = panelInstanceId;
                _navigationGeneration++;
            }
        }

        internal bool TryAcquireMaterialShopNavigationLease(
            string panelName,
            string panelInstanceId,
            string leaseToken,
            string shopId,
            out MaterialShopSettlementWitness witness)
        {
            witness = null;
            lock (_lock)
            {
                CatalogAuthority catalog;
                if (_disposed
                    || string.IsNullOrEmpty(leaseToken)
                    || _navigationLeaseToken != null
                    || !string.Equals(panelName, "npcshop", StringComparison.Ordinal)
                    || !string.Equals(_navigationOwnerPanel, panelName, StringComparison.Ordinal)
                    || !string.Equals(
                        _navigationOwnerPanelInstanceId,
                        panelInstanceId,
                        StringComparison.Ordinal)
                    || _pendingCalls.PendingCount != 0
                    || !string.Equals(_writeState, "idle", StringComparison.Ordinal)
                    || !_catalogAuthorities.TryGetValue(panelInstanceId, out catalog)
                    || catalog == null
                    || !string.Equals(catalog.ShopId, shopId, StringComparison.Ordinal))
                {
                    return false;
                }
                _navigationLeaseToken = leaseToken;
                _navigationLeaseTransferred = false;
                _navigationGeneration++;
                witness = new MaterialShopSettlementWitness
                {
                    TaskName = "npcshop",
                    LeaseToken = leaseToken,
                    OwnerPanel = panelName,
                    OwnerPanelInstanceId = panelInstanceId,
                    Generation = _navigationGeneration,
                    ShopId = shopId,
                    RequiresCatalogAuthority = true
                };
                return true;
            }
        }

        internal bool TryAcquireMaterialShopCloseLease(
            string panelName,
            string panelInstanceId,
            string leaseToken,
            out MaterialShopSettlementWitness witness)
        {
            witness = null;
            lock (_lock)
            {
                if (_disposed
                    || string.IsNullOrEmpty(leaseToken)
                    || _navigationLeaseToken != null
                    || !string.Equals(panelName, "npcshop", StringComparison.Ordinal)
                    || !string.Equals(
                        _navigationOwnerPanel,
                        panelName,
                        StringComparison.Ordinal)
                    || !string.Equals(
                        _navigationOwnerPanelInstanceId,
                        panelInstanceId,
                        StringComparison.Ordinal)
                    || _pendingCalls.PendingCount != 0
                    || !string.Equals(_writeState, "idle", StringComparison.Ordinal))
                {
                    return false;
                }
                _navigationLeaseToken = leaseToken;
                _navigationLeaseTransferred = false;
                _navigationGeneration++;
                witness = new MaterialShopSettlementWitness
                {
                    TaskName = "npcshop",
                    LeaseToken = leaseToken,
                    OwnerPanel = panelName,
                    OwnerPanelInstanceId = panelInstanceId,
                    Generation = _navigationGeneration,
                    RequiresCatalogAuthority = false
                };
                return true;
            }
        }

        internal bool IsMaterialShopNavigationLeaseCurrent(
            MaterialShopSettlementWitness witness)
        {
            lock (_lock)
            {
                CatalogAuthority catalog;
                return witness != null
                    && witness.RequiresCatalogAuthority
                    && !_disposed
                    && !_navigationLeaseTransferred
                    && string.Equals(witness.TaskName, "npcshop", StringComparison.Ordinal)
                    && string.Equals(
                        witness.LeaseToken,
                        _navigationLeaseToken,
                        StringComparison.Ordinal)
                    && witness.Generation == _navigationGeneration
                    && string.Equals(
                        witness.OwnerPanel,
                        _navigationOwnerPanel,
                        StringComparison.Ordinal)
                    && string.Equals(
                        witness.OwnerPanelInstanceId,
                        _navigationOwnerPanelInstanceId,
                        StringComparison.Ordinal)
                    && _pendingCalls.PendingCount == 0
                    && string.Equals(_writeState, "idle", StringComparison.Ordinal)
                    && _catalogAuthorities.TryGetValue(
                        witness.OwnerPanelInstanceId,
                        out catalog)
                    && catalog != null
                    && string.Equals(catalog.ShopId, witness.ShopId, StringComparison.Ordinal);
            }
        }

        internal bool IsMaterialShopCloseLeaseCurrent(
            MaterialShopSettlementWitness witness)
        {
            lock (_lock)
            {
                return witness != null
                    && !witness.RequiresCatalogAuthority
                    && !_disposed
                    && !_navigationLeaseTransferred
                    && string.Equals(
                        witness.TaskName,
                        "npcshop",
                        StringComparison.Ordinal)
                    && string.Equals(
                        witness.LeaseToken,
                        _navigationLeaseToken,
                        StringComparison.Ordinal)
                    && witness.Generation == _navigationGeneration
                    && string.Equals(
                        witness.OwnerPanel,
                        _navigationOwnerPanel,
                        StringComparison.Ordinal)
                    && string.Equals(
                        witness.OwnerPanelInstanceId,
                        _navigationOwnerPanelInstanceId,
                        StringComparison.Ordinal)
                    && _pendingCalls.PendingCount == 0
                    && string.Equals(_writeState, "idle", StringComparison.Ordinal);
            }
        }

        internal bool ReleaseMaterialShopNavigationLease(
            MaterialShopSettlementWitness witness)
        {
            lock (_lock)
            {
                if (!MatchesMaterialShopNavigationLeaseLocked(witness)) return false;
                _navigationLeaseToken = null;
                _navigationLeaseTransferred = false;
                _navigationGeneration++;
                return true;
            }
        }

        internal bool TransferMaterialShopNavigationLease(
            MaterialShopSettlementWitness witness)
        {
            lock (_lock)
            {
                if (!MatchesMaterialShopNavigationLeaseLocked(witness)
                    || _navigationLeaseTransferred) return false;
                _navigationLeaseTransferred = true;
                return true;
            }
        }

        private bool MatchesMaterialShopNavigationLeaseLocked(
            MaterialShopSettlementWitness witness)
        {
            return witness != null
                && string.Equals(witness.TaskName, "npcshop", StringComparison.Ordinal)
                && string.Equals(
                    witness.LeaseToken,
                    _navigationLeaseToken,
                    StringComparison.Ordinal)
                && witness.Generation == _navigationGeneration;
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
                if (_navigationLeaseToken != null)
                {
                    RespondError(callId, cmd, ownerPanel, ownerPanelInstanceId, "busy");
                    return;
                }
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
                _navigationGeneration++;
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
                _navigationGeneration++;
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
            TryLogResponseValidation(
                msg, entry, pendingCall.WebCallId, fid, malformed);
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

        private static void TryLogResponseValidation(
            JObject msg,
            PendingRequest entry,
            string webCallId,
            int flashCallId,
            bool malformed)
        {
            if (entry == null || (entry.WebCmd != "snapshot" && !malformed)) return;
            try
            {
                ResponseValidationFailure failure = malformed
                    ? DiagnoseSanitizationFailure(msg, entry) : null;
                bool rawSuccess = msg != null
                    && msg.Value<bool?>("success") == true;
                string outcome = malformed
                    ? "rejected"
                    : (rawSuccess ? "accepted" : "host_error");
                string error = malformed
                    ? "malformed_response"
                    : (rawSuccess ? "" : msg != null
                        ? msg.Value<string>("error") : "other");
                LogManager.Log(AuthorityLogFormatter.FormatNpcShopResponseValidation(
                    outcome,
                    webCallId,
                    flashCallId,
                    entry.OwnerPanelInstanceId,
                    entry.WebCmd,
                    error,
                    failure != null ? failure.Stage : "complete",
                    failure != null ? failure.FieldPath : "none",
                    failure != null ? failure.Expected : "none",
                    BuildResponseShapeSignature(msg)));
            }
            catch
            {
                // 诊断是旁路观测：镜像、格式化或日志 sink 异常均不得改变已完成的业务裁决。
                try
                {
                    LogManager.Log(AuthorityLogFormatter.FormatNpcShopResponseValidation(
                        malformed ? "rejected" : "other",
                        webCallId,
                        flashCallId,
                        entry.OwnerPanelInstanceId,
                        entry.WebCmd,
                        malformed ? "malformed_response" : "other",
                        "diagnostic_error",
                        "none",
                        "none",
                        "diagnostic_error"));
                }
                catch { }
            }
        }

        public void ClearPending()
        {
            lock (_lock)
            {
                _navigationGeneration++;
                _navigationLeaseToken = null;
                _navigationLeaseTransferred = false;
                _navigationOwnerPanel = null;
                _navigationOwnerPanelInstanceId = null;
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

        private static bool TryComputePurchaseTotal(
            JObject catalogLine,
            long quantity,
            long buyRatePermille,
            out long total)
        {
            total = 0;
            long basePrice;
            long amount;
            return catalogLine != null
                && PermilleMath.TryReadSafeNonNegativeInteger(
                    catalogLine["basePrice"], out basePrice)
                && PermilleMath.TryMultiply(basePrice, quantity, out amount)
                && PermilleMath.TryFloor(amount, buyRatePermille, out total);
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
                    "buyRatePermille", "catalog", "layout", "views");
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
                    "buyRatePermille", "catalog", "layout", "views", "operation",
                    "destinationView", "itemName", "quantity", "total");
            else if (entry.WebCmd == "batchSell")
                sanitized = CopyResponseKeys(msg, "success", "v", "shopId", "balance",
                    "buyRatePermille", "catalog", "layout", "views", "operation",
                    "quantity", "total");
            else
                sanitized = CopyResponseKeys(msg, "success", "v", "shopId", "balance",
                    "buyRatePermille", "catalog", "layout", "views", "operation", "trade");
            return true;
        }

        private static ResponseValidationFailure DiagnoseSanitizationFailure(
            JObject msg,
            PendingRequest entry)
        {
            if (msg == null)
                return ValidationFailure("envelope", "$", "object");
            if (entry == null)
                return ValidationFailure("pending", "$", "pending_context");
            if (msg["success"] == null || msg["success"].Type != JTokenType.Boolean)
                return ValidationFailure("envelope", "$.success", "boolean");
            if (!msg.Value<bool>("success"))
                return ValidationFailure("failure", "$.error", "known_error_code");

            switch (entry.WebCmd)
            {
                case "snapshot":
                    return DiagnoseStateResponse(msg, entry.NormalizedPayload, null);
                case "buy":
                case "batchSell":
                case "tradeCommit":
                    return DiagnoseStateResponse(msg, entry.NormalizedPayload, entry.WebCmd);
                case "tradePreview":
                    return ValidationFailure(
                        "trade_preview", "$", "authoritative_trade_preview");
                case "batchPreview":
                    return ValidationFailure(
                        "batch_preview", "$", "authoritative_batch_preview");
                case "tooltip":
                    return ValidationFailure(
                        "tooltip", "$", "authoritative_tooltip");
                default:
                    return ValidationFailure(
                        "command", "$", "supported_response_command");
            }
        }

        private static ResponseValidationFailure DiagnoseStateResponse(
            JObject msg,
            JObject request,
            string expectedOperation)
        {
            string requestedShopId = request != null
                ? request.Value<string>("shopId") : null;
            if (msg.Value<int?>("v") != 1)
                return ValidationFailure("state", "$.v", "wire_revision_1");
            if (!IsSafeString(msg["shopId"], 80, false))
                return ValidationFailure("state", "$.shopId", "safe_identity");
            if (string.IsNullOrEmpty(requestedShopId)
                || msg.Value<string>("shopId") != requestedShopId)
                return ValidationFailure("state", "$.shopId", "requested_shop_identity");
            long balance;
            if (!PermilleMath.TryReadSafeNonNegativeInteger(msg["balance"], out balance))
                return ValidationFailure(
                    "state", "$.balance", "safe_nonnegative_integer");
            long buyRatePermille;
            if (msg.Property("buyMultiplier") != null)
                return ValidationFailure("state", "$.buyMultiplier", "removed_field");
            if (!PermilleMath.TryReadSafeNonNegativeInteger(
                    msg["buyRatePermille"], out buyRatePermille))
                return ValidationFailure(
                    "state", "$.buyRatePermille", "safe_nonnegative_integer");
            if (buyRatePermille > PermilleMath.Scale)
                return ValidationFailure(
                    "state", "$.buyRatePermille", "npc_rate_0_to_1000");

            ResponseValidationFailure nested = DiagnoseCatalog(
                msg["catalog"] as JArray,
                buyRatePermille);
            if (nested != null) return nested;
            nested = DiagnoseLayout(msg["layout"] as JObject);
            if (nested != null) return nested;

            JObject views = msg["views"] as JObject;
            if (!HasOnlyKeys(views, "material", "intelligence"))
                return ValidationFailure("state", "$.views", "material_intelligence_only");
            nested = DiagnoseCollectionView(
                views != null ? views["material"] as JObject : null,
                "material");
            if (nested != null) return nested;
            nested = DiagnoseCollectionView(
                views != null ? views["intelligence"] as JObject : null,
                "intelligence");
            if (nested != null) return nested;
            if (expectedOperation == null)
                return ValidationFailure("state", "$", "authoritative_snapshot");
            if (msg.Value<string>("operation") != expectedOperation)
                return ValidationFailure("state", "$.operation", "requested_operation");
            return ValidationFailure(
                "state_postcondition", "$", "authoritative_write_postcondition");
        }

        private static ResponseValidationFailure DiagnoseCatalog(
            JArray catalog,
            long buyRatePermille)
        {
            if (catalog == null)
                return ValidationFailure("catalog", "$.catalog", "array");
            if (catalog.Count > 10001)
                return ValidationFailure("catalog", "$.catalog", "at_most_10001_entries");
            var indexes = new HashSet<int>();
            for (int i = 0; i < catalog.Count; i++)
            {
                JObject line = catalog[i] as JObject;
                string path = "$.catalog[" + i + "]";
                if (!HasOnlyKeys(line, "catalogIndex", "itemName", "displayName", "icon",
                        "majorType", "use", "actionType", "weaponType", "setId", "setName",
                        "setOrder", "basePrice", "unitPrice", "maxQuantity", "requiredInfo",
                        "locked", "balanceSummary", "procurement"))
                    return ValidationFailure("catalog", path, "closed_catalog_entry");
                int integer;
                if (!TryReadInteger(line["catalogIndex"], 0, 10000, out integer))
                    return ValidationFailure("catalog", path + ".catalogIndex", "catalog_index");
                if (!indexes.Add(integer))
                    return ValidationFailure("catalog", path + ".catalogIndex", "unique_catalog_index");
                if (!IsIdentityString(line["itemName"], 128))
                    return ValidationFailure("catalog", path + ".itemName", "safe_identity");
                if (!IsIdentityString(line["displayName"], 256))
                    return ValidationFailure("catalog", path + ".displayName", "safe_identity");
                if (!IsIdentityString(line["icon"], 256))
                    return ValidationFailure("catalog", path + ".icon", "safe_identity");
                if (!IsSafeString(line["majorType"], 128, true))
                    return ValidationFailure("catalog", path + ".majorType", "safe_optional_text");
                if (!IsSafeString(line["use"], 128, true))
                    return ValidationFailure("catalog", path + ".use", "safe_optional_text");
                if (!IsSafeString(line["actionType"], 128, true))
                    return ValidationFailure("catalog", path + ".actionType", "safe_optional_text");
                if (!IsSafeString(line["weaponType"], 128, true))
                    return ValidationFailure("catalog", path + ".weaponType", "safe_optional_text");
                if (!IsSafeString(line["setId"], 256, true))
                    return ValidationFailure("catalog", path + ".setId", "safe_optional_text");
                if (!IsSafeString(line["setName"], 256, true))
                    return ValidationFailure("catalog", path + ".setName", "safe_optional_text");
                if (!TryReadInteger(line["setOrder"], 0, int.MaxValue, out integer))
                    return ValidationFailure("catalog", path + ".setOrder", "nonnegative_integer");
                long basePrice;
                long unitPrice;
                long expectedUnitPrice;
                if (!PermilleMath.TryReadSafeNonNegativeInteger(
                        line["basePrice"], out basePrice))
                    return ValidationFailure(
                        "catalog", path + ".basePrice", "safe_nonnegative_integer");
                if (!PermilleMath.TryReadSafeNonNegativeInteger(
                        line["unitPrice"], out unitPrice))
                    return ValidationFailure(
                        "catalog", path + ".unitPrice", "safe_nonnegative_integer");
                if (!PermilleMath.TryFloor(
                        basePrice, buyRatePermille, out expectedUnitPrice)
                    || unitPrice != expectedUnitPrice)
                    return ValidationFailure("catalog", path + ".unitPrice", "derived_floor_price");
                if (!TryReadInteger(line["maxQuantity"], 0, MaxPurchaseQuantity, out integer))
                    return ValidationFailure("catalog", path + ".maxQuantity", "purchase_quantity_bound");
                if (!IsSafeString(line["requiredInfo"], 256, true))
                    return ValidationFailure("catalog", path + ".requiredInfo", "safe_optional_text");
                if (line["locked"] == null || line["locked"].Type != JTokenType.Boolean)
                    return ValidationFailure("catalog", path + ".locked", "boolean");
                if (line.Property("balanceSummary") != null
                    && !IsSafeJsonTree(line["balanceSummary"], 0))
                    return ValidationFailure("catalog", path + ".balanceSummary", "safe_json_tree");
                if (line.Property("procurement") != null
                    && !ProcurementProjectionValidator.IsDemand(
                        line["procurement"] as JObject,
                        line.Value<string>("itemName")))
                    return ValidationFailure("catalog", path + ".procurement", "procurement_projection");
            }
            return null;
        }

        private static ResponseValidationFailure DiagnoseLayout(JObject layout)
        {
            if (!HasOnlyKeys(layout, "title", "defaultSection", "sections"))
                return ValidationFailure("layout", "$.layout", "closed_layout");
            if (!IsSafeString(layout["title"], 256, false))
                return ValidationFailure("layout", "$.layout.title", "safe_text");
            if (!IsSafeString(layout["defaultSection"], 128, true))
                return ValidationFailure("layout", "$.layout.defaultSection", "safe_optional_text");
            JArray sections = layout["sections"] as JArray;
            if (sections == null || sections.Count > 128)
                return ValidationFailure("layout", "$.layout.sections", "at_most_128_entries");
            for (int i = 0; i < sections.Count; i++)
            {
                JObject section = sections[i] as JObject;
                string path = "$.layout.sections[" + i + "]";
                if (!HasOnlyKeys(section, "id", "label", "kind", "entries"))
                    return ValidationFailure("layout", path, "closed_layout_section");
                if (!IsSafeString(section["id"], 128, true))
                    return ValidationFailure("layout", path + ".id", "safe_optional_text");
                if (!IsSafeString(section["label"], 256, true))
                    return ValidationFailure("layout", path + ".label", "safe_optional_text");
                if (!IsSafeString(section["kind"], 128, true))
                    return ValidationFailure("layout", path + ".kind", "safe_optional_text");
                JArray entries = section["entries"] as JArray;
                if (entries == null || entries.Count > 10001)
                    return ValidationFailure("layout", path + ".entries", "catalog_index_array");
                var seen = new HashSet<int>();
                for (int j = 0; j < entries.Count; j++)
                {
                    int index;
                    if (!TryReadInteger(entries[j], 0, 10000, out index))
                        return ValidationFailure("layout", path + ".entries[" + j + "]", "catalog_index");
                    if (!seen.Add(index))
                        return ValidationFailure("layout", path + ".entries[" + j + "]", "unique_catalog_index");
                }
            }
            return null;
        }

        private static ResponseValidationFailure DiagnoseCollectionView(
            JObject view,
            string viewId)
        {
            string root = "$.views." + viewId;
            if (!HasOnlyKeys(view, "containerId", "capacity", "accessibleCapacity",
                    "viewCapacity", "offset", "limit", "filterKey", "slots"))
                return ValidationFailure("collection", root, "closed_collection_view");
            string expectedContainer = viewId == "material" ? "材料" : "情报";
            if (view.Value<string>("containerId") != expectedContainer)
                return ValidationFailure("collection", root + ".containerId", "expected_container");
            if (!IsSafeString(view["filterKey"], 128, false))
                return ValidationFailure("collection", root + ".filterKey", "safe_text");
            JArray slots = view["slots"] as JArray;
            if (slots == null)
                return ValidationFailure("collection", root + ".slots", "array");
            int capacity;
            int accessible;
            int viewCapacity;
            int offset;
            int limit;
            if (!TryReadInteger(view["capacity"], 0, 100000, out capacity))
                return ValidationFailure("collection", root + ".capacity", "bounded_nonnegative_integer");
            if (!TryReadInteger(view["accessibleCapacity"], 0, 100000, out accessible))
                return ValidationFailure("collection", root + ".accessibleCapacity", "bounded_nonnegative_integer");
            if (!TryReadInteger(view["viewCapacity"], 0, 100000, out viewCapacity))
                return ValidationFailure("collection", root + ".viewCapacity", "bounded_nonnegative_integer");
            if (!TryReadInteger(view["offset"], 0, 100000, out offset))
                return ValidationFailure("collection", root + ".offset", "zero");
            if (!TryReadInteger(view["limit"], 0, 100000, out limit))
                return ValidationFailure("collection", root + ".limit", "view_capacity");
            if (accessible > capacity)
                return ValidationFailure("collection", root + ".accessibleCapacity", "not_above_capacity");
            if (viewCapacity > accessible)
                return ValidationFailure("collection", root + ".viewCapacity", "not_above_accessible_capacity");
            if (offset != 0)
                return ValidationFailure("collection", root + ".offset", "zero");
            if (limit != viewCapacity)
                return ValidationFailure("collection", root + ".limit", "view_capacity");
            if (slots.Count != viewCapacity)
                return ValidationFailure("collection", root + ".slots", "view_capacity_count");

            var physicalSlots = new HashSet<int>();
            var keys = new HashSet<string>(StringComparer.Ordinal);
            for (int i = 0; i < slots.Count; i++)
            {
                JObject slot = slots[i] as JObject;
                string path = root + ".slots[" + i + "]";
                if (!HasOnlyKeys(slot, "physicalSlot", "collectionKey", "occupied", "slotLease", "item"))
                    return ValidationFailure("collection", path, "closed_collection_slot");
                int physicalSlot;
                if (!TryReadInteger(slot["physicalSlot"], 0, 100000, out physicalSlot))
                    return ValidationFailure("collection", path + ".physicalSlot", "bounded_nonnegative_integer");
                if (!physicalSlots.Add(physicalSlot))
                    return ValidationFailure("collection", path + ".physicalSlot", "unique_physical_slot");
                string collectionKey = slot.Value<string>("collectionKey");
                if (!IsSafeString(slot["collectionKey"], 128, false))
                    return ValidationFailure("collection", path + ".collectionKey", "safe_identity");
                if (!keys.Add(collectionKey))
                    return ValidationFailure("collection", path + ".collectionKey", "unique_collection_key");
                if (slot.Value<bool?>("occupied") != true)
                    return ValidationFailure("collection", path + ".occupied", "true");
                if (!IsSafeString(slot["slotLease"], 160, false)
                    || !ValidLease.IsMatch(slot.Value<string>("slotLease")))
                    return ValidationFailure("collection", path + ".slotLease", "valid_opaque_lease");
                JObject item = slot["item"] as JObject;
                if (!HasOnlyKeys(item, "itemKind", "name", "displayName", "icon",
                        "majorType", "use", "quantity", "enhancementLevel", "rarity"))
                    return ValidationFailure("collection", path + ".item", "closed_stack_item");
                if (item.Value<string>("itemKind") != "stack")
                    return ValidationFailure("collection", path + ".item.itemKind", "stack");
                if (!IsIdentityString(item["name"], 128)
                    || item.Value<string>("name") != collectionKey)
                    return ValidationFailure("collection", path + ".item.name", "collection_key_identity");
                if (!IsIdentityString(item["displayName"], 256))
                    return ValidationFailure("collection", path + ".item.displayName", "safe_identity");
                if (!IsIdentityString(item["icon"], 256))
                    return ValidationFailure("collection", path + ".item.icon", "safe_identity");
                if (!IsSafeString(item["majorType"], 128, true))
                    return ValidationFailure("collection", path + ".item.majorType", "safe_optional_text");
                if (!IsSafeString(item["use"], 128, true))
                    return ValidationFailure("collection", path + ".item.use", "safe_optional_text");
                long quantity;
                if (!TryReadPositiveInteger(item["quantity"], out quantity))
                    return ValidationFailure("collection", path + ".item.quantity", "positive_safe_integer");
                if (item.Value<int?>("enhancementLevel") != 0)
                    return ValidationFailure("collection", path + ".item.enhancementLevel", "zero");
                if (!IsSafeString(item["rarity"], 128, true))
                    return ValidationFailure("collection", path + ".item.rarity", "safe_optional_text");
            }
            return null;
        }

        private static ResponseValidationFailure ValidationFailure(
            string stage,
            string fieldPath,
            string expected)
        {
            return new ResponseValidationFailure
            {
                Stage = stage,
                FieldPath = fieldPath,
                Expected = expected
            };
        }

        private static string BuildResponseShapeSignature(JToken token)
        {
            var value = new StringBuilder(4096);
            AppendResponseShape(value, token, 0);
            return value.ToString();
        }

        private static void AppendResponseShape(
            StringBuilder value,
            JToken token,
            int depth)
        {
            if (value.Length >= 32768)
            {
                value.Append("#limit");
                return;
            }
            if (token == null)
            {
                value.Append("missing");
                return;
            }
            if (depth > 12)
            {
                value.Append("depth");
                return;
            }
            JObject obj = token as JObject;
            if (obj != null)
            {
                var properties = new List<JProperty>(obj.Properties());
                properties.Sort(delegate(JProperty left, JProperty right)
                {
                    return string.CompareOrdinal(left.Name, right.Name);
                });
                value.Append("O").Append(properties.Count).Append('{');
                int count = Math.Min(properties.Count, 256);
                for (int i = 0; i < count; i++)
                {
                    JProperty property = properties[i];
                    value.Append(property.Name.Length).Append(':')
                        .Append(property.Name).Append('=');
                    AppendResponseShape(value, property.Value, depth + 1);
                    value.Append(';');
                }
                if (properties.Count > count) value.Append("more");
                value.Append('}');
                return;
            }
            JArray array = token as JArray;
            if (array != null)
            {
                value.Append("A").Append(array.Count).Append('[');
                int count = Math.Min(array.Count, 1024);
                for (int i = 0; i < count; i++)
                    AppendResponseShape(value, array[i], depth + 1);
                if (array.Count > count) value.Append("more");
                value.Append(']');
                return;
            }
            switch (token.Type)
            {
                case JTokenType.String:
                    value.Append('S').Append(Math.Min(token.Value<string>().Length, 1024));
                    break;
                case JTokenType.Integer: value.Append('I'); break;
                case JTokenType.Float: value.Append('F'); break;
                case JTokenType.Boolean: value.Append('B'); break;
                case JTokenType.Null: value.Append('N'); break;
                default: value.Append('T').Append((int)token.Type); break;
            }
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
                ["buyRatePermille"] = current.BuyRatePermille,
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
                Balance = state.Value<long>("balance"),
                BuyRatePermille = state.Value<long>("buyRatePermille"),
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
                long currentUnitPrice;
                long frozenUnitPrice;
                if (!MatchesCatalogIdentity(currentLine, frozenLine)
                    || !PermilleMath.TryReadSafeNonNegativeInteger(
                        currentLine["unitPrice"], out currentUnitPrice)
                    || !PermilleMath.TryReadSafeNonNegativeInteger(
                        frozenLine["unitPrice"], out frozenUnitPrice)
                    || currentUnitPrice != frozenUnitPrice) return false;
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
            long balance;
            long totalMoney;
            int skipped;
            if (msg == null || msg.Value<int?>("v") != 1 || requested == null
                || summary == null || summary.Count > requested.Count
                || string.IsNullOrEmpty(token) || !ValidLease.IsMatch(token)
                || !TryReadPositiveInteger(msg["totalQuantity"], out totalQuantity)
                || !PermilleMath.TryReadSafeNonNegativeInteger(
                    msg["balance"], out balance)
                || !PermilleMath.TryReadSafeNonNegativeInteger(
                    msg["totalMoney"], out totalMoney)
                || !TryReadInteger(msg["skipped"], 0, int.MaxValue, out skipped)) return false;
            var requestedNames = new HashSet<string>(StringComparer.Ordinal);
            foreach (JToken requestedName in requested)
                if (requestedName.Type != JTokenType.String
                    || !requestedNames.Add(requestedName.Value<string>())) return false;
            var seen = new HashSet<string>(StringComparer.Ordinal);
            long quantitySum = 0;
            long moneySum = 0;
            foreach (JToken tokenValue in summary)
            {
                JObject line = tokenValue as JObject;
                long quantity;
                long money;
                string itemName = line != null ? line.Value<string>("itemName") : null;
                if (!HasOnlyKeys(line, "itemName", "displayName", "icon", "quantity", "money")
                    || !IsIdentityString(line["itemName"], 128)
                    || !IsIdentityString(line["displayName"], 256)
                    || !IsIdentityString(line["icon"], 256)
                    || !requestedNames.Contains(itemName) || !seen.Add(itemName)
                    || !TryReadPositiveInteger(line["quantity"], out quantity)
                    || !PermilleMath.TryReadSafeNonNegativeInteger(
                        line["money"], out money)
                    || !PermilleMath.TryAdd(quantitySum, quantity, out quantitySum)
                    || !PermilleMath.TryAdd(moneySum, money, out moneySum)) return false;
            }
            if (summary.Count == 0 || quantitySum != totalQuantity
                || moneySum != totalMoney) return false;
            sanitized = CopyResponseKeys(msg, "success", "v", "batchToken", "balance", "summary",
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
            long authoritativeRatePermille = 0;
            bool hasAuthoritativeRate = catalogAuthority != null
                && PermilleMath.TryReadSafeNonNegativeInteger(
                    catalogAuthority["buyRatePermille"],
                    out authoritativeRatePermille)
                && authoritativeRatePermille <= PermilleMath.Scale;
            long authoritativeBalance = 0;
            bool hasAuthoritativeBalance = catalogAuthority != null
                && PermilleMath.TryReadSafeNonNegativeInteger(
                    catalogAuthority["balance"], out authoritativeBalance);
            long buyTotal;
            long responseSellTotal;
            long responseNetDelta;
            long responseProjectedBalance;
            if (msg["tradeToken"] == null || msg["tradeToken"].Type != JTokenType.String
                || string.IsNullOrEmpty(token) || !ValidLease.IsMatch(token)
                || purchaseLines == null || saleLines == null
                || requestedPurchases == null || requestedSales == null
                || authoritativeCatalog == null
                || !hasAuthoritativeRate
                || !hasAuthoritativeBalance
                || catalogAuthority.Value<string>("shopId") != request.Value<string>("shopId")
                || purchaseLines.Count != requestedPurchases.Count || saleLines.Count != requestedSales.Count
                || !PermilleMath.TryReadSafeNonNegativeInteger(msg["buyTotal"], out buyTotal)
                || !PermilleMath.TryReadSafeNonNegativeInteger(
                    msg["sellTotal"], out responseSellTotal)
                || !PermilleMath.TryReadSafeInteger(msg["netDelta"], out responseNetDelta)
                || !PermilleMath.TryReadSafeInteger(
                    msg["projectedBalance"], out responseProjectedBalance)
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

            long purchaseTotal = 0;
            bool hasPotentialCollectionAcquisition = false;
            var seenPurchases = new HashSet<int>();
            foreach (JToken responseToken in purchaseLines)
            {
                JObject line = responseToken as JObject;
                int catalogIndex, quantity, maxQuantity, purchaseLimit;
                int maxAffordable, maxByCapacity, maxPurchasable;
                JObject requestedLine;
                JObject authoritativeLine;
                long lineUnitPrice;
                long lineTotal;
                long authoritativeUnitPrice;
                long expectedTotal;
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
                    || !PermilleMath.TryReadSafeNonNegativeInteger(
                        line["unitPrice"], out lineUnitPrice)
                    || !PermilleMath.TryReadSafeNonNegativeInteger(
                        line["total"], out lineTotal)
                    || !PermilleMath.TryReadSafeNonNegativeInteger(
                        authoritativeLine["unitPrice"], out authoritativeUnitPrice)
                    || !MatchesCatalogIdentity(line, authoritativeLine)
                    || lineUnitPrice != authoritativeUnitPrice
                    || !TryComputePurchaseTotal(
                        authoritativeLine,
                        quantity,
                        authoritativeRatePermille,
                        out expectedTotal)
                    || lineTotal != expectedTotal
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
                if (!PermilleMath.TryAdd(purchaseTotal, lineTotal, out purchaseTotal)) return false;
            }

            var requestedSaleByIdentity = new Dictionary<string, JObject>(StringComparer.Ordinal);
            foreach (JToken requestToken in requestedSales)
            {
                JObject line = requestToken as JObject;
                string identity = TradeSaleIdentity(line);
                if (line == null || string.IsNullOrEmpty(identity) || requestedSaleByIdentity.ContainsKey(identity)) return false;
                requestedSaleByIdentity[identity] = line;
            }

            long saleTotal = 0;
            var seenSales = new HashSet<string>(StringComparer.Ordinal);
            foreach (JToken responseToken in saleLines)
            {
                JObject line = responseToken as JObject;
                long quantity;
                int matchedCount, eligibleCount, protectedCount;
                long lineTotal;
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
                    || !PermilleMath.TryReadSafeNonNegativeInteger(
                        line["total"], out lineTotal)) return false;
                if (line.Value<string>("itemKind") == "equipment") hasPotentialCollectionAcquisition = true;
                if (!PermilleMath.TryAdd(saleTotal, lineTotal, out saleTotal)) return false;
            }

            string blockingError = msg.Value<string>("blockingError");
            bool canCommit = msg.Value<bool>("canCommit");
            int requiredSlots = msg.Value<int>("requiredSlots");
            int availableSlots = msg.Value<int>("availableSlots");
            int missingSlots = msg.Value<int>("missingSlots");
            long expectedNetDelta;
            long expectedProjectedBalance;
            if (!PermilleMath.TryAdd(
                    authoritativeBalance, responseSellTotal, out _)
                || !PermilleMath.TrySubtract(responseSellTotal, buyTotal, out expectedNetDelta)
                || !PermilleMath.TryAddSigned(
                    authoritativeBalance, expectedNetDelta, out expectedProjectedBalance)) return false;
            bool consistentCommitState = responseProjectedBalance < 0
                ? !canCommit && blockingError == "insufficient_money"
                : blockingError == "destination_full"
                    ? !canCommit && hasPotentialCollectionAcquisition
                    : missingSlots > 0
                        ? !canCommit && blockingError == "inventory_full"
                        : canCommit && string.IsNullOrEmpty(blockingError);
            return buyTotal == purchaseTotal && responseSellTotal == saleTotal
                && responseNetDelta == expectedNetDelta
                && responseProjectedBalance == expectedProjectedBalance
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
            long buyRatePermille;
            long stateBalance;
            if (msg == null || msg.Value<int?>("v") != 1
                || !IsSafeString(msg["shopId"], 80, false)
                || string.IsNullOrEmpty(requestedShopId)
                || msg.Value<string>("shopId") != requestedShopId
                || !PermilleMath.TryReadSafeNonNegativeInteger(
                    msg["balance"], out stateBalance)
                || msg.Property("buyMultiplier") != null
                || !PermilleMath.TryReadSafeNonNegativeInteger(
                    msg["buyRatePermille"], out buyRatePermille)
                || buyRatePermille > PermilleMath.Scale
                || !TryValidateCatalog(
                    msg["catalog"] as JArray,
                    buyRatePermille)
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
                long currentUnitPrice;
                long authoritativeUnitPrice;
                long authoritativeRatePermille;
                long resultTotal;
                long expectedTotal;
                long authoritativeBalance;
                long expectedBalance;
                return catalogAuthority != null
                    && catalogAuthority.Value<string>("shopId") == requestedShopId
                    && authoritativeCatalog != null
                    && TryReadInteger(request["catalogIndex"], 0, 10000, out catalogIndex)
                    && (authoritativeLine = FindCatalogEntry(authoritativeCatalog, catalogIndex)) != null
                    && (currentLine = FindCatalogEntry(msg["catalog"] as JArray, catalogIndex)) != null
                    && MatchesCatalogIdentity(currentLine, authoritativeLine)
                    && PermilleMath.TryReadSafeNonNegativeInteger(
                        currentLine["unitPrice"], out currentUnitPrice)
                    && PermilleMath.TryReadSafeNonNegativeInteger(
                        authoritativeLine["unitPrice"], out authoritativeUnitPrice)
                    && currentUnitPrice == authoritativeUnitPrice
                    && PermilleMath.TryReadSafeNonNegativeInteger(
                        catalogAuthority["buyRatePermille"], out authoritativeRatePermille)
                    && buyRatePermille == authoritativeRatePermille
                    && TryReadInteger(request["quantity"], 1, MaxPurchaseQuantity, out requestedQuantity)
                    && requestedQuantity <= authoritativeLine.Value<int>("maxQuantity")
                    && TryReadInteger(msg["quantity"], 1, MaxPurchaseQuantity, out resultQuantity)
                    && resultQuantity == requestedQuantity
                    && IsIdentityString(msg["itemName"], 128)
                    && msg.Value<string>("itemName") == authoritativeLine.Value<string>("itemName")
                    && IsOneOf(msg["destinationView"], "bag", "material", "intelligence", "quickslot")
                    && PermilleMath.TryReadSafeNonNegativeInteger(
                        msg["total"], out resultTotal)
                    && TryComputePurchaseTotal(
                        authoritativeLine,
                        resultQuantity,
                        authoritativeRatePermille,
                        out expectedTotal)
                    && resultTotal == expectedTotal
                    && PermilleMath.TryReadSafeNonNegativeInteger(
                        catalogAuthority["balance"], out authoritativeBalance)
                    && PermilleMath.TrySubtract(
                        authoritativeBalance, resultTotal, out expectedBalance)
                    && expectedBalance >= 0
                    && stateBalance == expectedBalance;
            }
            if (expectedOperation == "batchSell")
            {
                long previewQuantity;
                long previewBalance;
                long previewTotal;
                long resultTotal;
                long expectedBalance;
                return batchAuthority != null
                    && batchAuthority.Value<string>("batchToken")
                        == request.Value<string>("expectedBatchToken")
                    && TryReadPositiveInteger(batchAuthority["totalQuantity"], out previewQuantity)
                    && TryReadInteger(msg["quantity"], 1, int.MaxValue, out resultQuantity)
                    && previewQuantity == resultQuantity
                    && PermilleMath.TryReadSafeNonNegativeInteger(
                        batchAuthority["balance"], out previewBalance)
                    && PermilleMath.TryReadSafeNonNegativeInteger(
                        batchAuthority["totalMoney"], out previewTotal)
                    && PermilleMath.TryReadSafeNonNegativeInteger(
                        msg["total"], out resultTotal)
                    && resultTotal == previewTotal
                    && PermilleMath.TryAdd(
                        previewBalance, previewTotal, out expectedBalance)
                    && stateBalance == expectedBalance;
            }
            JObject trade = msg["trade"] as JObject;
            long committedBuyTotal;
            long previewBuyTotal;
            long committedSellTotal;
            long previewSellTotal;
            long committedNetDelta;
            long previewNetDelta;
            long previewProjectedBalance;
            long expectedNetDelta;
            return expectedOperation == "tradeCommit"
                && tradeAuthority != null
                && tradeAuthority.Value<string>("shopId") == requestedShopId
                && tradeAuthority.Value<string>("tradeToken")
                    == request.Value<string>("expectedTradeToken")
                && tradeAuthority.Value<bool?>("canCommit") == true
                && MatchesTradePurchaseCatalog(msg, tradeAuthority)
                && PermilleMath.TryReadSafeNonNegativeInteger(
                    tradeAuthority["projectedBalance"], out previewProjectedBalance)
                && stateBalance == previewProjectedBalance
                && HasOnlyKeys(trade, "buyTotal", "sellTotal", "netDelta")
                && PermilleMath.TryReadSafeNonNegativeInteger(
                    trade["buyTotal"], out committedBuyTotal)
                && PermilleMath.TryReadSafeNonNegativeInteger(
                    tradeAuthority["buyTotal"], out previewBuyTotal)
                && PermilleMath.TryReadSafeNonNegativeInteger(
                    trade["sellTotal"], out committedSellTotal)
                && PermilleMath.TryReadSafeNonNegativeInteger(
                    tradeAuthority["sellTotal"], out previewSellTotal)
                && PermilleMath.TryReadSafeInteger(
                    trade["netDelta"], out committedNetDelta)
                && PermilleMath.TryReadSafeInteger(
                    tradeAuthority["netDelta"], out previewNetDelta)
                && committedBuyTotal == previewBuyTotal
                && committedSellTotal == previewSellTotal
                && committedNetDelta == previewNetDelta
                && PermilleMath.TrySubtract(
                    committedSellTotal, committedBuyTotal, out expectedNetDelta)
                && committedNetDelta == expectedNetDelta;
        }

        private static bool TryValidateCatalog(JArray catalog, long buyRatePermille)
        {
            if (catalog == null || catalog.Count > 10001) return false;
            var indexes = new HashSet<int>();
            foreach (JToken token in catalog)
            {
                JObject line = token as JObject;
                int catalogIndex;
                int setOrder;
                int maxQuantity;
                long basePrice;
                long unitPrice;
                long expectedUnitPrice;
                if (!HasOnlyKeys(line, "catalogIndex", "itemName", "displayName", "icon",
                        "majorType", "use", "actionType", "weaponType", "setId", "setName",
                        "setOrder", "basePrice", "unitPrice", "maxQuantity", "requiredInfo",
                        "locked", "balanceSummary", "procurement")
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
                    || !PermilleMath.TryReadSafeNonNegativeInteger(
                        line["basePrice"], out basePrice)
                    || !PermilleMath.TryReadSafeNonNegativeInteger(
                        line["unitPrice"], out unitPrice)
                    || !PermilleMath.TryFloor(
                        basePrice, buyRatePermille, out expectedUnitPrice)
                    || unitPrice != expectedUnitPrice
                    || !TryReadInteger(line["maxQuantity"], 0, MaxPurchaseQuantity, out maxQuantity)
                    || !IsSafeString(line["requiredInfo"], 256, true)
                    || line["locked"] == null || line["locked"].Type != JTokenType.Boolean
                    || (line.Property("balanceSummary") != null
                        && !IsSafeJsonTree(line["balanceSummary"], 0))
                    || (line.Property("procurement") != null
                        && !ProcurementProjectionValidator.IsDemand(
                            line["procurement"] as JObject,
                            line.Value<string>("itemName")))) return false;
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
                _navigationGeneration++;
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
            string responseError = error;
            lock (_lock)
            {
                if (_navigationLeaseToken != null)
                    responseError = "busy";
                else if (!_pendingCalls.TryRememberRejected(callId))
                    return;
            }
            RespondError(
                callId,
                cmd,
                ownerPanel,
                ownerPanelInstanceId,
                responseError);
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
