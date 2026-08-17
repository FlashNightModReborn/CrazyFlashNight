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
    /// 商城面板 WebView↔Flash 双层 callId 桥接 + 写请求可靠性门。
    ///
    /// 既有 shop* wire shape 保持不变：
    ///   Web   -> C#    {type:"panel", cmd, callId, ...}
    ///   C#    -> Flash {task:"cmd", action:"shop"+Cmd, callId:fid, ...}
    ///   Flash -> C#    {task:"shop_response", callId:fid, success, ...}
    ///   C#    -> Web   {type:"panel_resp", callId:webCallId, success, ...}
    ///
    /// saveCart / checkoutCommit / legacy checkout / claim 共享单写 owner。写结果超时、断线、发送失败或畸形时进入
    /// needs_reconcile；此后只允许读请求，且只有进入该状态后新发起并成功的 bulkQuery
    /// 能解除写门。活动/近期 callId 不会再次下发 Flash。
    /// </summary>
    public sealed class ShopTask : IDisposable
    {
        private enum WriteGateState
        {
            Idle,
            WritePending,
            NeedsReconcile
        }

        private sealed class PendingRequest
        {
            public string WebCallId;
            public string WebCmd;
            public string OwnerPanel;
            public string OwnerPanelInstanceId;
            public bool IsWrite;
            public bool IsReconcileProbe;
            public int ReconcileEpoch;
            public JObject NormalizedPayload;
            public JArray ExpectedLines;
            public JArray SaveCartAuthority;
            public double? BalanceBefore;
            public CheckoutAuthority CommitAuthority;
            public JArray PurchasedBefore;
            public JArray PurchasedViewBefore;
            public string PurchasedTokenBefore;
            public int ClaimIndex = -1;
        }

        private sealed class CheckoutAuthority
        {
            public string Token;
            public JArray Lines;
            public double Balance;
            public double Total;
            public double ProjectedBalance;
        }

        private const int DEFAULT_TIMEOUT_MS = 10000;
        private const int RECENT_CALL_ID_CAPACITY = 256;
        private const int MAX_CART_LINES = 40;
        private const int MAX_PURCHASE_QUANTITY = 999999;
        private static readonly Regex ValidCallId = new Regex(
            "^[A-Za-z0-9._-]{1,96}$",
            RegexOptions.CultureInvariant | RegexOptions.Compiled);
        private static readonly Regex ValidPanelInstanceId = new Regex(
            "^[A-Za-z0-9._~-]{1,128}$",
            RegexOptions.CultureInvariant | RegexOptions.Compiled);
        private static readonly Regex ValidToken = new Regex(
            "^[A-Za-z0-9._-]{1,160}$",
            RegexOptions.CultureInvariant | RegexOptions.Compiled);

        private readonly Func<bool> _isClientReady;
        private readonly Func<string, bool> _trySend;
        private readonly int _timeoutMs;
        private Action<string> _postToWeb;
        private Action<Action> _invokeOnUI;
        private readonly Dictionary<int, PendingRequest> _pending;
        private readonly Dictionary<int, Timer> _timers;
        private readonly HashSet<string> _activeWebCallIds;
        private readonly HashSet<string> _recentWebCallIds;
        private readonly Queue<string> _recentWebCallIdOrder;
        private int _seq;
        private int _writeOwnerFid;
        private int _reconcileEpoch;
        private WriteGateState _writeGate;
        private Dictionary<int, JObject> _catalogByIndex;
        private JArray _purchasedSnapshot;
        private JArray _purchasedViewSnapshot;
        private string _purchasedToken;
        private double? _knownBalance;
        private CheckoutAuthority _checkoutAuthority;
        private readonly object _lock = new object();
        private string _navigationOwnerPanel;
        private string _navigationOwnerPanelInstanceId;
        private string _navigationLeaseToken;
        private bool _navigationLeaseTransferred;
        private long _navigationGeneration;
        private volatile bool _disposed;

        public ShopTask(XmlSocketServer socket)
            : this(
                delegate { return socket != null && socket.IsClientReady; },
                delegate(string payload) { return socket != null && socket.TrySend(payload); },
                DEFAULT_TIMEOUT_MS)
        {
        }

        public ShopTask(Func<bool> isClientReady, Func<string, bool> trySend)
            : this(isClientReady, trySend, DEFAULT_TIMEOUT_MS)
        {
        }

        public ShopTask(Func<bool> isClientReady, Func<string, bool> trySend, int timeoutMs)
        {
            _isClientReady = isClientReady ?? delegate { return false; };
            _trySend = trySend ?? delegate { return false; };
            _timeoutMs = Math.Max(1, timeoutMs);
            _pending = new Dictionary<int, PendingRequest>();
            _timers = new Dictionary<int, Timer>();
            _activeWebCallIds = new HashSet<string>(StringComparer.Ordinal);
            _recentWebCallIds = new HashSet<string>(StringComparer.Ordinal);
            _recentWebCallIdOrder = new Queue<string>();
            _catalogByIndex = new Dictionary<int, JObject>();
            _purchasedSnapshot = new JArray();
            _purchasedViewSnapshot = new JArray();
            _writeGate = WriteGateState.Idle;
        }

        public void SetPostToWeb(Action<string> post) { _postToWeb = post; }
        public void SetInvoker(Action<Action> invoker) { _invokeOnUI = invoker; }

        internal void BindMaterialShopNavigationOwner(
            string panelName,
            string panelInstanceId)
        {
            lock (_lock)
            {
                if (_disposed) return;
                if (string.Equals(_navigationOwnerPanel, panelName, StringComparison.Ordinal)
                    && string.Equals(_navigationOwnerPanelInstanceId, panelInstanceId,
                        StringComparison.Ordinal)) return;
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
            out MaterialShopSettlementWitness witness)
        {
            witness = null;
            lock (_lock)
            {
                if (_disposed || string.IsNullOrEmpty(leaseToken)
                    || _navigationLeaseToken != null
                    || !string.Equals(_navigationOwnerPanel, panelName,
                        StringComparison.Ordinal)
                    || !string.Equals(_navigationOwnerPanelInstanceId, panelInstanceId,
                        StringComparison.Ordinal)
                    || _pending.Count != 0 || _writeGate != WriteGateState.Idle)
                    return false;
                _navigationLeaseToken = leaseToken;
                _navigationLeaseTransferred = false;
                _navigationGeneration++;
                witness = new MaterialShopSettlementWitness
                {
                    TaskName = "kshop",
                    LeaseToken = leaseToken,
                    OwnerPanel = panelName,
                    OwnerPanelInstanceId = panelInstanceId,
                    Generation = _navigationGeneration
                };
                return true;
            }
        }

        internal bool IsMaterialShopNavigationLeaseCurrent(
            MaterialShopSettlementWitness witness)
        {
            lock (_lock)
            {
                return MatchesMaterialShopNavigationLeaseLocked(witness)
                    && !_disposed && !_navigationLeaseTransferred
                    && string.Equals(witness.OwnerPanel, _navigationOwnerPanel,
                        StringComparison.Ordinal)
                    && string.Equals(witness.OwnerPanelInstanceId,
                        _navigationOwnerPanelInstanceId, StringComparison.Ordinal)
                    && _pending.Count == 0 && _writeGate == WriteGateState.Idle;
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
                && string.Equals(witness.TaskName, "kshop", StringComparison.Ordinal)
                && string.Equals(witness.LeaseToken, _navigationLeaseToken,
                    StringComparison.Ordinal)
                && witness.Generation == _navigationGeneration;
        }

        public void Dispose()
        {
            _disposed = true;
            ClearPending();
        }

        /// <summary>WebView 侧面板请求入口（UI 线程调用）。</summary>
        public void HandleWebRequest(string cmd, JObject parsed)
        {
            LogManager.Log("[ShopTask] HandleWebRequest: cmd="
                + AuthorityLogFormatter.FormatOperation(cmd));
            string webCallId = parsed != null ? parsed.Value<string>("callId") : null;
            string ownerPanel = parsed != null ? parsed.Value<string>("panel") : null;
            string ownerPanelInstanceId = parsed != null
                ? parsed.Value<string>("panelInstanceId") : null;
            if (ownerPanel != "kshop" || string.IsNullOrEmpty(ownerPanelInstanceId)
                || !ValidPanelInstanceId.IsMatch(ownerPanelInstanceId))
            {
                LogManager.Log("[ShopTask] invalid or missing owner tuple");
                return;
            }
            if (string.IsNullOrEmpty(webCallId))
            {
                LogManager.Log("[ShopTask] webCallId is empty");
                return;
            }
            if (!ValidCallId.IsMatch(webCallId))
            {
                RespondError(webCallId, cmd, ownerPanel, ownerPanelInstanceId, "invalid_call_id");
                return;
            }
            if (!WebOverlayForm.IsStrictDomainlessPanelEnvelope(parsed))
            {
                RejectAndRemember(
                    webCallId,
                    cmd,
                    ownerPanel,
                    ownerPanelInstanceId,
                    "invalid_domain");
                return;
            }

            string action;
            bool isWrite;
            if (!TryResolveCommand(cmd, out action, out isWrite))
            {
                RejectAndRemember(webCallId, cmd, ownerPanel, ownerPanelInstanceId, "unsupported_cmd");
                return;
            }

            // A new preview attempt retires the previous capability even when the
            // replacement payload is malformed and therefore never reaches AS2.
            if (cmd == "checkoutPreview")
            {
                lock (_lock) { _checkoutAuthority = null; }
            }

            JObject normalizedPayload;
            if (!TryNormalizePayload(cmd, parsed, out normalizedPayload))
            {
                RejectAndRemember(webCallId, cmd, ownerPanel, ownerPanelInstanceId, "invalid_payload");
                return;
            }

            if (!_isClientReady())
            {
                RejectAndRemember(webCallId, cmd, ownerPanel, ownerPanelInstanceId, "disconnected");
                return;
            }

            int fid = 0;
            string localError = null;
            lock (_lock)
            {
                if (_navigationLeaseToken != null)
                {
                    RememberRecentLocked(webCallId);
                    localError = "busy";
                }
                else if (_activeWebCallIds.Contains(webCallId) || _recentWebCallIds.Contains(webCallId))
                {
                    LogManager.Log("[ShopTask] duplicate/replayed callId ignored: " + webCallId);
                    return;
                }

                if (isWrite && _writeGate == WriteGateState.WritePending)
                {
                    RememberRecentLocked(webCallId);
                    localError = "busy";
                }
                else if (isWrite && _writeGate == WriteGateState.NeedsReconcile)
                {
                    RememberRecentLocked(webCallId);
                    localError = "reconcile_required";
                }
                else
                {
                    var entry = new PendingRequest
                    {
                        WebCallId = webCallId,
                        WebCmd = cmd,
                        OwnerPanel = ownerPanel,
                        OwnerPanelInstanceId = ownerPanelInstanceId,
                        IsWrite = isWrite,
                        IsReconcileProbe = cmd == "bulkQuery" && _writeGate == WriteGateState.NeedsReconcile,
                        ReconcileEpoch = _reconcileEpoch,
                        NormalizedPayload = (JObject)normalizedPayload.DeepClone()
                    };
                    if (!TryBindAuthorityLocked(entry, out localError))
                    {
                        RememberRecentLocked(webCallId);
                    }
                    else
                    {
                        fid = ++_seq;
                        _pending[fid] = entry;
                        _activeWebCallIds.Add(webCallId);
                        if (isWrite)
                        {
                            _writeGate = WriteGateState.WritePending;
                            _writeOwnerFid = fid;
                        }
                    }
                }
            }

            if (localError != null)
            {
                RespondError(webCallId, cmd, ownerPanel, ownerPanelInstanceId, localError);
                return;
            }

            var timer = new Timer(delegate { HandleTimeout(fid); }, null, _timeoutMs, Timeout.Infinite);
            lock (_lock)
            {
                if (_pending.ContainsKey(fid)) _timers[fid] = timer;
                else timer.Dispose();
            }

            // Only the command-specific normalized business payload enters the
            // legacy domain-less AS2 wire. A2 owner metadata remains Host-local.
            var flashMsg = PanelBridge.BuildFlashCommand(action, fid, normalizedPayload);
            string flashJson = flashMsg.ToString(Formatting.None);
            LogManager.Log(AuthorityLogFormatter.FormatAuthorityFlashCallBound(
                "ShopTask", webCallId, fid, ownerPanel, ownerPanelInstanceId,
                cmd, action));
            LogManager.Log(AuthorityLogFormatter.FormatFlashCommand(
                "ShopTask", flashMsg));
            if (!_trySend(flashJson + "\0"))
            {
                HandleSendFailure(fid);
            }
        }

        /// <summary>Flash 侧回包入口（MessageRouter 在 XmlSocket 线程调用）。</summary>
        public void HandleFlashResponse(JObject msg, Action<string> respond)
        {
            LogManager.Log("[ShopTask] <- Flash response received");
            int fid = msg != null ? msg.Value<int>("callId") : 0;
            PendingRequest entry;
            bool ambiguousWrite = false;
            bool invalidReadResponse = false;
            bool validResponse = false;
            JObject sanitized = null;

            lock (_lock)
            {
                if (!_pending.TryGetValue(fid, out entry))
                {
                    if (respond != null) respond(null);
                    return;
                }
                CompletePendingLocked(fid, entry);
                validResponse = TrySanitizeResponseLocked(msg, entry, out sanitized);

                if (entry.IsWrite && _writeOwnerFid == fid)
                {
                    if (validResponse && IsDefinitiveWriteResponse(entry.WebCmd, sanitized))
                    {
                        _writeGate = WriteGateState.Idle;
                        _writeOwnerFid = 0;
                    }
                    else
                    {
                        EnterNeedsReconcileLocked();
                        ambiguousWrite = true;
                    }
                }
                else if (!validResponse)
                {
                    invalidReadResponse = true;
                }
                else if (entry.IsReconcileProbe
                    && entry.ReconcileEpoch == _reconcileEpoch
                    && _writeGate == WriteGateState.NeedsReconcile
                    && sanitized.Value<bool?>("success") == true)
                {
                    _writeGate = WriteGateState.Idle;
                }
            }

            JObject webMsg = validResponse && sanitized != null
                ? (JObject)sanitized.DeepClone()
                : new JObject { ["success"] = false };
            webMsg["type"] = "panel_resp";
            webMsg["panel"] = entry.OwnerPanel;
            webMsg["panelInstanceId"] = entry.OwnerPanelInstanceId;
            webMsg["cmd"] = entry.WebCmd;
            webMsg["callId"] = entry.WebCallId;
            if (ambiguousWrite)
            {
                string originalError = validResponse ? webMsg.Value<string>("error") : null;
                webMsg["success"] = false;
                webMsg["error"] = "reconcile_required";
                webMsg["cause"] = string.IsNullOrEmpty(originalError) ? "invalid_response" : originalError;
            }
            else if (invalidReadResponse)
            {
                webMsg["success"] = false;
                webMsg["error"] = "invalid_response";
            }

            PostToWeb(webMsg.ToString(Formatting.None));
            if (respond != null) respond(null);
        }

        /// <summary>
        /// 断连/面板强关时清传输 pending。若有已下发写 owner，必须保留 needs_reconcile；
        /// 清理不会清空近期 callId，迟到/重放请求不会再次下发。
        /// </summary>
        public void ClearPending()
        {
            lock (_lock)
            {
                _navigationGeneration++;
                _navigationLeaseToken = null;
                _navigationLeaseTransferred = false;
                _navigationOwnerPanel = null;
                _navigationOwnerPanelInstanceId = null;
                if (_writeGate == WriteGateState.WritePending)
                    EnterNeedsReconcileLocked();

                foreach (var entry in _pending.Values)
                {
                    _activeWebCallIds.Remove(entry.WebCallId);
                    RememberRecentLocked(entry.WebCallId);
                }
                foreach (var timer in _timers.Values) timer.Dispose();
                _timers.Clear();
                _pending.Clear();
                _writeOwnerFid = 0;
                ClearAuthorityLocked();
            }
        }

        private static bool TryResolveCommand(string cmd, out string action, out bool isWrite)
        {
            isWrite = false;
            switch (cmd)
            {
                case "bulkQuery": action = "shopBulkQuery"; return true;
                case "tooltip": action = "shopTooltip"; return true;
                case "saveCart": action = "shopSaveCart"; isWrite = true; return true;
                case "checkoutPreview": action = "shopCheckoutPreview"; return true;
                case "checkoutCommit": action = "shopCheckoutCommit"; isWrite = true; return true;
                case "checkout": action = "shopCheckout"; isWrite = true; return true;
                case "claim": action = "shopClaim"; isWrite = true; return true;
                default: action = null; return false;
            }
        }

        private static bool TryNormalizePayload(
            string cmd,
            JObject input,
            out JObject normalized)
        {
            normalized = new JObject();
            if (input == null) return false;
            if (cmd == "bulkQuery")
                return HasOnlyRequestKeys(input);
            if (cmd == "tooltip")
            {
                int idx;
                if (!HasOnlyRequestKeys(input, "idx")
                    || !TryReadInteger(input["idx"], int.MinValue, int.MaxValue, out idx))
                    return false;
                normalized["idx"] = idx;
                return true;
            }
            if (cmd == "saveCart" || cmd == "checkout")
            {
                JArray cart;
                int minimum = 0;
                if (!HasOnlyRequestKeys(input, "cart")
                    || !TryNormalizeCart(input["cart"] as JArray, minimum, out cart))
                    return false;
                normalized["cart"] = cart;
                return true;
            }
            if (cmd == "checkoutPreview")
            {
                JArray cart;
                if (!HasOnlyRequestKeys(input, "v", "cart")
                    || !HasExactInteger(input["v"], 1)
                    || !TryNormalizeCart(input["cart"] as JArray, 0, out cart))
                    return false;
                normalized["v"] = 1;
                normalized["cart"] = cart;
                return true;
            }
            if (cmd == "checkoutCommit")
            {
                string token = input.Value<string>("expectedCheckoutToken");
                if (!HasOnlyRequestKeys(input, "v", "expectedCheckoutToken")
                    || !HasExactInteger(input["v"], 1)
                    || !IsStringToken(
                        input["expectedCheckoutToken"], 160, false)
                    || !IsValidToken(token)) return false;
                normalized["v"] = 1;
                normalized["expectedCheckoutToken"] = token;
                return true;
            }
            if (cmd == "claim")
            {
                int index;
                string token = input.Value<string>("expectedPurchasedToken");
                if (!HasOnlyRequestKeys(
                        input, "purchasedIdx", "expectedPurchasedToken")
                    || !TryReadInteger(
                        input["purchasedIdx"], int.MinValue, int.MaxValue, out index)
                    || !IsStringToken(
                        input["expectedPurchasedToken"], 160, false)
                    || !IsValidToken(token)) return false;
                normalized["purchasedIdx"] = index;
                normalized["expectedPurchasedToken"] = token;
                return true;
            }
            return false;
        }

        private static bool HasOnlyRequestKeys(
            JObject value,
            params string[] businessKeys)
        {
            if (value == null) return false;
            foreach (JProperty property in value.Properties())
            {
                string key = property.Name;
                if (key == "type" || key == "panel" || key == "panelInstanceId"
                    || key == "cmd" || key == "callId" || key == "action"
                    || key == "task") continue;
                bool found = false;
                for (int i = 0; i < businessKeys.Length; i++)
                {
                    if (string.Equals(key, businessKeys[i], StringComparison.Ordinal))
                    {
                        found = true;
                        break;
                    }
                }
                if (!found) return false;
            }
            for (int i = 0; i < businessKeys.Length; i++)
            {
                if (value.Property(businessKeys[i]) == null) return false;
            }
            return true;
        }

        private static bool TryNormalizeCart(
            JArray input,
            int minimumCount,
            out JArray output)
        {
            output = null;
            if (input == null || input.Count < minimumCount
                || input.Count > MAX_CART_LINES) return false;
            var clean = new JArray();
            foreach (JToken token in input)
            {
                JObject line = token as JObject;
                int idx;
                int quantity;
                if (!HasExactKeys(line, "idx", "qty")
                    || !TryReadInteger(line["idx"], int.MinValue, int.MaxValue, out idx)
                    || !TryReadInteger(line["qty"], int.MinValue, int.MaxValue, out quantity))
                    return false;
                clean.Add(new JObject { ["idx"] = idx, ["qty"] = quantity });
            }
            output = clean;
            return true;
        }

        private bool TryBindAuthorityLocked(
            PendingRequest entry,
            out string error)
        {
            error = null;
            string cmd = entry.WebCmd;
            if (cmd == "bulkQuery")
            {
                _checkoutAuthority = null;
                return true;
            }
            if (cmd == "saveCart")
            {
                JArray authority;
                if (!TryBuildSaveCartAuthorityLocked(
                        entry.NormalizedPayload["cart"] as JArray,
                        out authority))
                {
                    error = "stale_state";
                    return false;
                }
                entry.SaveCartAuthority = authority;
                return true;
            }
            if (cmd == "tooltip")
            {
                int idx = entry.NormalizedPayload.Value<int>("idx");
                JObject catalog;
                if (!_catalogByIndex.TryGetValue(idx, out catalog))
                {
                    error = "stale_state";
                    return false;
                }
                entry.ExpectedLines = new JArray((JObject)catalog.DeepClone());
                return true;
            }
            if (cmd == "checkoutPreview" || cmd == "checkout")
            {
                JArray expected;
                if (!TryBuildExpectedLinesLocked(
                        entry.NormalizedPayload["cart"] as JArray, out expected))
                {
                    error = "stale_state";
                    return false;
                }
                entry.ExpectedLines = expected;
                entry.BalanceBefore = _knownBalance;
                if (cmd == "checkout")
                {
                    _checkoutAuthority = null;
                    FreezePurchasedLocked(entry);
                }
                return true;
            }
            if (cmd == "checkoutCommit")
            {
                string token = entry.NormalizedPayload.Value<string>(
                    "expectedCheckoutToken");
                if (_checkoutAuthority == null || token != _checkoutAuthority.Token)
                {
                    error = "stale_state";
                    return false;
                }
                entry.CommitAuthority = CloneCheckoutAuthority(_checkoutAuthority);
                entry.ExpectedLines = (JArray)_checkoutAuthority.Lines.DeepClone();
                entry.BalanceBefore = _checkoutAuthority.Balance;
                FreezePurchasedLocked(entry);
                // Exact-token commit is single-use at the Host boundary, including
                // timeout/send-failure/invalid-response outcomes.
                _checkoutAuthority = null;
                return true;
            }
            if (cmd == "claim")
            {
                string token = entry.NormalizedPayload.Value<string>(
                    "expectedPurchasedToken");
                if (string.IsNullOrEmpty(_purchasedToken) || token != _purchasedToken)
                {
                    error = "stale_state";
                    return false;
                }
                entry.ClaimIndex = entry.NormalizedPayload.Value<int>("purchasedIdx");
                if (entry.ClaimIndex < 0
                    || entry.ClaimIndex >= _purchasedSnapshot.Count)
                {
                    error = "stale_state";
                    return false;
                }
                FreezePurchasedLocked(entry);
                _checkoutAuthority = null;
                return true;
            }
            return true;
        }

        private void FreezePurchasedLocked(PendingRequest entry)
        {
            entry.PurchasedBefore = (JArray)_purchasedSnapshot.DeepClone();
            entry.PurchasedViewBefore = (JArray)_purchasedViewSnapshot.DeepClone();
            entry.PurchasedTokenBefore = _purchasedToken;
        }

        private static CheckoutAuthority CloneCheckoutAuthority(
            CheckoutAuthority source)
        {
            return source == null ? null : new CheckoutAuthority
            {
                Token = source.Token,
                Lines = (JArray)source.Lines.DeepClone(),
                Balance = source.Balance,
                Total = source.Total,
                ProjectedBalance = source.ProjectedBalance
            };
        }

        private bool TryBuildExpectedLinesLocked(JArray cart, out JArray output)
        {
            output = null;
            if (cart == null || !_knownBalance.HasValue) return false;
            var clean = new JArray();
            var seen = new HashSet<int>();
            foreach (JToken token in cart)
            {
                int idx = token.Value<int>("idx");
                int quantity = token.Value<int>("qty");
                JObject catalog;
                // Quantity policy remains AS2 business authority. Host admission
                // binds only the exact selector and identity/price projection.
                if (idx < 0 || !seen.Add(idx)
                    || !_catalogByIndex.TryGetValue(idx, out catalog))
                    return false;
                double unitPrice = catalog.Value<double>("price");
                clean.Add(new JObject
                {
                    ["catalogIndex"] = idx,
                    ["itemName"] = catalog.Value<string>("item"),
                    ["displayName"] = catalog.Value<string>("displayname"),
                    ["icon"] = catalog.Value<string>("icon"),
                    ["quantity"] = quantity,
                    ["unitPrice"] = unitPrice,
                    ["total"] = unitPrice * quantity,
                    ["maxQuantity"] = catalog.Value<int>("maxQuantity")
                });
            }
            output = clean;
            return true;
        }

        private bool TrySanitizeResponseLocked(
            JObject message,
            PendingRequest entry,
            out JObject normalized)
        {
            normalized = null;
            if (message == null
                || !HasExactString(message["task"], "shop_response")
                || message["callId"] == null
                || message["callId"].Type != JTokenType.Integer
                || message["success"] == null
                || message["success"].Type != JTokenType.Boolean) return false;
            if (!message.Value<bool>("success"))
                return TrySanitizeFailure(message, entry.WebCmd, out normalized);
            switch (entry.WebCmd)
            {
                case "bulkQuery":
                    return TrySanitizeBulkSuccessLocked(message, out normalized);
                case "tooltip":
                    return TrySanitizeTooltipSuccessLocked(
                        message, entry, out normalized);
                case "saveCart":
                    return TrySanitizeSaveCartSuccessLocked(
                        message, entry, out normalized);
                case "checkoutPreview":
                    return TrySanitizePreviewSuccessLocked(
                        message, entry, out normalized);
                case "checkoutCommit":
                case "checkout":
                    return TrySanitizeCheckoutSuccessLocked(
                        message, entry, out normalized);
                case "claim":
                    return TrySanitizeClaimSuccessLocked(
                        message, entry, out normalized);
                default:
                    return false;
            }
        }

        private static bool TrySanitizeFailure(
            JObject message,
            string cmd,
            out JObject output)
        {
            output = null;
            string error = message.Value<string>("error");
            if (!IsStringToken(message["error"], 80, false)) return false;
            bool hasBalance = cmd == "checkout" && message.Property("balance") != null;
            bool hasPurchasedToken = cmd == "claim"
                && message.Property("purchasedToken") != null;
            if (hasBalance)
            {
                double balance;
                if (!HasExactKeys(
                        message, "task", "callId", "success", "error", "balance")
                    || !TryReadNonNegativeNumber(message["balance"], out balance))
                    return false;
                output = new JObject
                {
                    ["success"] = false,
                    ["error"] = error,
                    ["balance"] = balance
                };
                return true;
            }
            if (hasPurchasedToken)
            {
                string token = message.Value<string>("purchasedToken");
                if (!HasExactKeys(message,
                        "task", "callId", "success", "error", "purchasedToken")
                    || !IsStringToken(message["purchasedToken"], 160, false)
                    || !IsValidToken(token)) return false;
                output = new JObject
                {
                    ["success"] = false,
                    ["error"] = error,
                    ["purchasedToken"] = token
                };
                return true;
            }
            if (!HasExactKeys(message, "task", "callId", "success", "error"))
                return false;
            output = new JObject { ["success"] = false, ["error"] = error };
            return true;
        }

        private bool TrySanitizeBulkSuccessLocked(
            JObject message,
            out JObject output)
        {
            output = null;
            if (!HasExactKeys(message,
                    "task", "callId", "success", "catalog", "playerLevel",
                    "reverseLevel", "kpoints", "cart", "cartAdjusted",
                    "purchased", "purchasedView", "purchasedToken")) return false;
            JArray catalog;
            Dictionary<int, JObject> catalogByIndex;
            JArray cart;
            JArray purchased;
            JArray purchasedView;
            int playerLevel;
            int reverseLevel;
            double kpoints;
            bool cartAdjusted;
            string token = message.Value<string>("purchasedToken");
            if (!TrySanitizeCatalog(
                    message["catalog"] as JArray, out catalog, out catalogByIndex)
                || !TrySanitizeCartSnapshot(
                    message["cart"] as JArray, catalogByIndex, out cart)
                || !TrySanitizePurchased(
                    message["purchased"] as JArray,
                    message["purchasedView"] as JArray,
                    out purchased,
                    out purchasedView)
                || !TryReadInteger(message["playerLevel"], 0, int.MaxValue,
                    out playerLevel)
                || !TryReadInteger(message["reverseLevel"], 0, int.MaxValue,
                    out reverseLevel)
                || !TryReadNonNegativeNumber(message["kpoints"], out kpoints)
                || !TryReadBoolean(message["cartAdjusted"], out cartAdjusted)
                || !IsStringToken(message["purchasedToken"], 160, false)
                || !IsValidToken(token)) return false;
            _catalogByIndex = catalogByIndex;
            _purchasedSnapshot = purchased;
            _purchasedViewSnapshot = purchasedView;
            _purchasedToken = token;
            _knownBalance = kpoints;
            _checkoutAuthority = null;
            output = new JObject
            {
                ["success"] = true,
                ["catalog"] = catalog,
                ["playerLevel"] = playerLevel,
                ["reverseLevel"] = reverseLevel,
                ["kpoints"] = kpoints,
                ["cart"] = cart,
                ["cartAdjusted"] = cartAdjusted,
                // The Web surface receives only the canonical display projection;
                // the legacy storage arrays remain inside the AS2/Host boundary.
                ["purchased"] = (JArray)purchasedView.DeepClone(),
                ["purchasedToken"] = token
            };
            return true;
        }

        private bool TrySanitizeTooltipSuccessLocked(
            JObject message,
            PendingRequest entry,
            out JObject output)
        {
            output = null;
            if (!HasExactKeys(message,
                    "task", "callId", "success", "descHTML", "introHTML",
                    "itemName", "displayname", "iconName")
                || !IsStringToken(message["descHTML"], 250000, true)
                || !IsStringToken(message["introHTML"], 250000, true)
                || !IsIdentityToken(message["itemName"], 128)
                || !IsIdentityToken(message["displayname"], 256)
                || !IsIdentityToken(message["iconName"], 256)
                || entry.ExpectedLines == null || entry.ExpectedLines.Count != 1)
                return false;
            JObject expected = entry.ExpectedLines[0] as JObject;
            if (expected == null
                || message.Value<string>("itemName") != expected.Value<string>("item")
                || message.Value<string>("displayname") != expected.Value<string>("displayname")
                || message.Value<string>("iconName") != expected.Value<string>("icon"))
                return false;
            output = new JObject
            {
                ["success"] = true,
                ["descHTML"] = message.Value<string>("descHTML"),
                ["introHTML"] = message.Value<string>("introHTML"),
                ["itemName"] = message.Value<string>("itemName"),
                ["displayname"] = message.Value<string>("displayname"),
                ["iconName"] = message.Value<string>("iconName")
            };
            return true;
        }

        private bool TrySanitizePreviewSuccessLocked(
            JObject message,
            PendingRequest entry,
            out JObject output)
        {
            output = null;
            if (!HasExactKeys(message,
                    "task", "callId", "success", "v", "checkoutToken",
                    "purchaseLines", "total", "balance", "projectedBalance",
                    "canCommit", "blockingError")
                || !HasExactInteger(message["v"], 1)
                || entry.ExpectedLines == null || !entry.BalanceBefore.HasValue)
                return false;
            string token = message.Value<string>("checkoutToken");
            double total;
            double balance;
            double projected;
            bool canCommit;
            string blocking = message.Value<string>("blockingError");
            JArray lines;
            if (!IsStringToken(message["checkoutToken"], 160, false)
                || !IsValidToken(token)
                || !TryReadNonNegativeNumber(message["total"], out total)
                || !TryReadNonNegativeNumber(message["balance"], out balance)
                || !TryReadNumber(message["projectedBalance"], out projected)
                || !TryReadBoolean(message["canCommit"], out canCommit)
                || !IsStringToken(message["blockingError"], 64, true)
                || !IsOneOf(blocking,
                    "", "insufficient_kpoints", "inventory_full", "destination_full")
                || balance != entry.BalanceBefore.Value
                || projected != balance - total
                || !TrySanitizeCheckoutLines(
                    message["purchaseLines"] as JArray,
                    entry.ExpectedLines,
                    balance,
                    out lines)
                || total != SumLineTotals(lines)
                || !IsConsistentCommitState(lines, balance, total, canCommit, blocking))
                return false;
            _checkoutAuthority = new CheckoutAuthority
            {
                Token = token,
                Lines = (JArray)lines.DeepClone(),
                Balance = balance,
                Total = total,
                ProjectedBalance = projected
            };
            output = new JObject
            {
                ["success"] = true,
                ["v"] = 1,
                ["checkoutToken"] = token,
                ["purchaseLines"] = lines,
                ["total"] = total,
                ["balance"] = balance,
                ["projectedBalance"] = projected,
                ["canCommit"] = canCommit,
                ["blockingError"] = blocking
            };
            return true;
        }

        private bool TrySanitizeSaveCartSuccessLocked(
            JObject message,
            PendingRequest entry,
            out JObject output)
        {
            output = null;
            if (!HasExactKeys(
                    message, "task", "callId", "success", "v", "cart")
                || !HasExactInteger(message["v"], 1)
                || entry == null
                || entry.SaveCartAuthority == null) return false;
            JArray cart;
            if (!TrySanitizeSavedCart(
                    message["cart"] as JArray,
                    entry.SaveCartAuthority,
                    out cart)) return false;
            JArray requested = entry.NormalizedPayload["cart"] as JArray;
            output = new JObject
            {
                ["success"] = true,
                ["v"] = 1,
                ["cart"] = cart,
                ["adjusted"] = requested == null || !JToken.DeepEquals(cart, requested)
            };
            return true;
        }

        private bool TrySanitizeCheckoutSuccessLocked(
            JObject message,
            PendingRequest entry,
            out JObject output)
        {
            output = null;
            if (!HasExactKeys(message,
                    "task", "callId", "success", "v", "newBalance",
                    "delivered", "cart", "purchased", "purchasedView",
                    "purchasedToken", "catalog")
                || !HasExactInteger(message["v"], 1)
                || entry.ExpectedLines == null || !entry.BalanceBefore.HasValue)
                return false;
            JArray delivered;
            if (entry.WebCmd == "checkoutCommit")
            {
                if (entry.CommitAuthority == null
                    || !TrySanitizeCheckoutLines(
                        message["delivered"] as JArray,
                        entry.ExpectedLines,
                        entry.CommitAuthority.Balance,
                        out delivered)
                    || !JToken.DeepEquals(
                        delivered, entry.CommitAuthority.Lines)) return false;
            }
            else if (!TrySanitizeCheckoutLines(
                    message["delivered"] as JArray,
                    entry.ExpectedLines,
                    entry.BalanceBefore.Value,
                    out delivered)) return false;
            double newBalance;
            double expectedBalance = entry.WebCmd == "checkoutCommit"
                ? entry.CommitAuthority.ProjectedBalance
                : entry.BalanceBefore.Value - SumLineTotals(delivered);
            JArray cart = message["cart"] as JArray;
            JArray catalog;
            Dictionary<int, JObject> catalogByIndex;
            JArray purchased;
            JArray purchasedView;
            string token = message.Value<string>("purchasedToken");
            if (!TryReadNonNegativeNumber(message["newBalance"], out newBalance)
                || newBalance != expectedBalance
                || cart == null || cart.Count != 0
                || !TrySanitizeCatalog(
                    message["catalog"] as JArray, out catalog, out catalogByIndex)
                || !CatalogMatchesDelivered(catalogByIndex, delivered)
                || !TrySanitizePurchased(
                    message["purchased"] as JArray,
                    message["purchasedView"] as JArray,
                    out purchased,
                    out purchasedView)
                || !IsStringToken(message["purchasedToken"], 160, false)
                || !IsValidToken(token)
                || token != entry.PurchasedTokenBefore
                || !JToken.DeepEquals(purchased, entry.PurchasedBefore)
                || !JToken.DeepEquals(purchasedView, entry.PurchasedViewBefore))
                return false;
            _catalogByIndex = catalogByIndex;
            _purchasedSnapshot = purchased;
            _purchasedViewSnapshot = purchasedView;
            _purchasedToken = token;
            _knownBalance = newBalance;
            _checkoutAuthority = null;
            output = new JObject
            {
                ["success"] = true,
                ["v"] = 1,
                ["newBalance"] = newBalance,
                ["delivered"] = delivered,
                ["cart"] = new JArray(),
                ["purchased"] = (JArray)purchasedView.DeepClone(),
                ["purchasedToken"] = token,
                ["catalog"] = catalog
            };
            return true;
        }

        private bool TryBuildSaveCartAuthorityLocked(
            JArray cart,
            out JArray authority)
        {
            authority = null;
            if (cart == null || cart.Count > MAX_CART_LINES) return false;
            var result = new JArray();
            var seen = new HashSet<int>();
            foreach (JToken token in cart)
            {
                JObject line = token as JObject;
                int idx;
                int quantity;
                JObject catalog;
                if (!HasExactKeys(line, "idx", "qty")
                    || !TryReadInteger(line["idx"], 0, 10000, out idx)
                    || !TryReadInteger(
                        line["qty"], 1, MAX_PURCHASE_QUANTITY, out quantity)
                    || !seen.Add(idx)
                    || !_catalogByIndex.TryGetValue(idx, out catalog)) return false;
                result.Add(new JObject
                {
                    ["idx"] = idx,
                    ["qty"] = quantity,
                    ["maxQuantity"] = catalog.Value<int>("maxQuantity")
                });
            }
            authority = result;
            return true;
        }

        private static bool TrySanitizeSavedCart(
            JArray input,
            JArray authority,
            out JArray output)
        {
            output = null;
            if (input == null || authority == null || input.Count > authority.Count)
                return false;
            var expectedByIndex = new Dictionary<int, JObject>();
            var positionByIndex = new Dictionary<int, int>();
            for (int i = 0; i < authority.Count; i++)
            {
                JObject expected = authority[i] as JObject;
                if (expected == null) return false;
                int idx = expected.Value<int>("idx");
                expectedByIndex[idx] = expected;
                positionByIndex[idx] = i;
            }
            var clean = new JArray();
            var seen = new HashSet<int>();
            int previousPosition = -1;
            foreach (JToken token in input)
            {
                JObject line = token as JObject;
                int idx;
                int quantity;
                JObject expected;
                int position;
                if (!HasExactKeys(line, "idx", "qty")
                    || !TryReadInteger(line["idx"], 0, 10000, out idx)
                    || !TryReadInteger(
                        line["qty"], 1, MAX_PURCHASE_QUANTITY, out quantity)
                    || !seen.Add(idx)
                    || !expectedByIndex.TryGetValue(idx, out expected)
                    || !positionByIndex.TryGetValue(idx, out position)
                    || position <= previousPosition
                    || quantity > expected.Value<int>("qty")
                    || quantity > expected.Value<int>("maxQuantity")) return false;
                previousPosition = position;
                clean.Add(new JObject { ["idx"] = idx, ["qty"] = quantity });
            }
            output = clean;
            return true;
        }

        private static bool CatalogMatchesDelivered(
            Dictionary<int, JObject> catalog,
            JArray delivered)
        {
            if (catalog == null || delivered == null) return false;
            foreach (JToken token in delivered)
            {
                JObject line = token as JObject;
                JObject current;
                if (line == null
                    || !catalog.TryGetValue(line.Value<int>("catalogIndex"), out current)
                    || current.Value<string>("item") != line.Value<string>("itemName")
                    || current.Value<string>("displayname") != line.Value<string>("displayName")
                    || current.Value<string>("icon") != line.Value<string>("icon")
                    || current.Value<double>("price") != line.Value<double>("unitPrice"))
                    return false;
            }
            return true;
        }

        private bool TrySanitizeClaimSuccessLocked(
            JObject message,
            PendingRequest entry,
            out JObject output)
        {
            output = null;
            if (!HasExactKeys(message,
                    "task", "callId", "success", "purchased", "purchasedView",
                    "purchasedToken", "catalog")
                || entry.PurchasedBefore == null
                || entry.PurchasedViewBefore == null
                || entry.ClaimIndex < 0
                || entry.ClaimIndex >= entry.PurchasedBefore.Count) return false;
            JArray catalog;
            Dictionary<int, JObject> catalogByIndex;
            JArray purchased;
            JArray purchasedView;
            string token = message.Value<string>("purchasedToken");
            if (!TrySanitizeCatalog(
                    message["catalog"] as JArray, out catalog, out catalogByIndex)
                || !TrySanitizePurchased(
                    message["purchased"] as JArray,
                    message["purchasedView"] as JArray,
                    out purchased,
                    out purchasedView)
                || !IsStringToken(message["purchasedToken"], 160, false)
                || !IsValidToken(token)
                || token == entry.PurchasedTokenBefore
                || !MatchesClaimPostcondition(entry, purchased, purchasedView))
                return false;
            _catalogByIndex = catalogByIndex;
            _purchasedSnapshot = purchased;
            _purchasedViewSnapshot = purchasedView;
            _purchasedToken = token;
            _checkoutAuthority = null;
            output = new JObject
            {
                ["success"] = true,
                ["catalog"] = catalog,
                ["purchased"] = (JArray)purchasedView.DeepClone(),
                ["purchasedToken"] = token
            };
            return true;
        }

        private static bool MatchesClaimPostcondition(
            PendingRequest entry,
            JArray purchased,
            JArray purchasedView)
        {
            if (purchased.Count != entry.PurchasedBefore.Count - 1
                || purchasedView.Count != entry.PurchasedViewBefore.Count - 1)
                return false;
            int outputIndex = 0;
            for (int sourceIndex = 0;
                sourceIndex < entry.PurchasedBefore.Count;
                sourceIndex++)
            {
                if (sourceIndex == entry.ClaimIndex) continue;
                if (!JToken.DeepEquals(
                        purchased[outputIndex], entry.PurchasedBefore[sourceIndex]))
                    return false;
                JObject actualView = purchasedView[outputIndex] as JObject;
                JObject oldView = entry.PurchasedViewBefore[sourceIndex] as JObject;
                if (actualView == null || oldView == null
                    || actualView.Value<int>("purchasedIdx") != outputIndex
                    || actualView.Value<string>("item") != oldView.Value<string>("item")
                    || actualView.Value<string>("displayname") != oldView.Value<string>("displayname")
                    || actualView.Value<string>("icon") != oldView.Value<string>("icon")
                    || actualView.Value<int>("quantity") != oldView.Value<int>("quantity"))
                    return false;
                outputIndex++;
            }
            return true;
        }

        private static bool TrySanitizeCatalog(
            JArray input,
            out JArray output,
            out Dictionary<int, JObject> byIndex)
        {
            output = null;
            byIndex = null;
            if (input == null || input.Count > 10000) return false;
            var clean = new JArray();
            var index = new Dictionary<int, JObject>();
            foreach (JToken token in input)
            {
                JObject item = token as JObject;
                bool hasSummary = item != null
                    && item.Property("balanceSummary") != null;
                bool hasProcurement = item != null
                    && item.Property("procurement") != null;
                if (!((hasSummary && hasProcurement)
                        ? HasExactKeys(item,
                            "idx", "id", "item", "type", "price", "displayname",
                            "majorType", "subType", "actionType", "weaponType",
                            "setId", "setName", "setOrder", "level", "icon",
                            "maxQuantity", "balanceSummary", "procurement")
                        : hasSummary
                        ? HasExactKeys(item,
                            "idx", "id", "item", "type", "price", "displayname",
                            "majorType", "subType", "actionType", "weaponType",
                            "setId", "setName", "setOrder", "level", "icon",
                            "maxQuantity", "balanceSummary")
                        : hasProcurement
                        ? HasExactKeys(item,
                            "idx", "id", "item", "type", "price", "displayname",
                            "majorType", "subType", "actionType", "weaponType",
                            "setId", "setName", "setOrder", "level", "icon",
                            "maxQuantity", "procurement")
                        : HasExactKeys(item,
                            "idx", "id", "item", "type", "price", "displayname",
                            "majorType", "subType", "actionType", "weaponType",
                            "setId", "setName", "setOrder", "level", "icon",
                            "maxQuantity"))) return false;
                int idx;
                int setOrder;
                int level;
                int maximum;
                double price;
                JObject summary = null;
                if (!TryReadInteger(item["idx"], 0, 10000, out idx)
                    || index.ContainsKey(idx)
                    || !IsStringToken(item["id"], 128, false)
                    || !IsIdentityToken(item["item"], 128)
                    || !IsStringToken(item["type"], 128, false)
                    || !TryReadNonNegativeNumber(item["price"], out price)
                    || !IsIdentityToken(item["displayname"], 256)
                    || !IsStringToken(item["majorType"], 128, true)
                    || !IsStringToken(item["subType"], 128, true)
                    || !IsStringToken(item["actionType"], 128, true)
                    || !IsStringToken(item["weaponType"], 128, true)
                    || !IsStringToken(item["setId"], 128, true)
                    || !IsStringToken(item["setName"], 256, true)
                    || !TryReadInteger(item["setOrder"], 0, int.MaxValue, out setOrder)
                    || !TryReadInteger(item["level"], 0, int.MaxValue, out level)
                    || !IsIdentityToken(item["icon"], 256)
                    || !TryReadInteger(
                        item["maxQuantity"], 0, MAX_PURCHASE_QUANTITY, out maximum)
                    || (hasSummary && !TrySanitizeBalanceSummary(
                        item["balanceSummary"] as JObject, out summary))
                    || (hasProcurement && !ProcurementProjectionValidator.IsDemand(
                        item["procurement"] as JObject,
                        item.Value<string>("item")))) return false;
                var projected = new JObject
                {
                    ["idx"] = idx,
                    ["id"] = item.Value<string>("id"),
                    ["item"] = item.Value<string>("item"),
                    ["type"] = item.Value<string>("type"),
                    ["price"] = price,
                    ["displayname"] = item.Value<string>("displayname"),
                    ["majorType"] = item.Value<string>("majorType"),
                    ["subType"] = item.Value<string>("subType"),
                    ["actionType"] = item.Value<string>("actionType"),
                    ["weaponType"] = item.Value<string>("weaponType"),
                    ["setId"] = item.Value<string>("setId"),
                    ["setName"] = item.Value<string>("setName"),
                    ["setOrder"] = setOrder,
                    ["level"] = level,
                    ["icon"] = item.Value<string>("icon"),
                    ["maxQuantity"] = maximum
                };
                if (summary != null) projected["balanceSummary"] = summary;
                if (hasProcurement)
                    projected["procurement"] = item["procurement"].DeepClone();
                clean.Add(projected);
                index[idx] = projected;
            }
            output = clean;
            byIndex = index;
            return true;
        }

        private static bool TrySanitizeBalanceSummary(
            JObject input,
            out JObject output)
        {
            output = null;
            int layers;
            int formula;
            int level;
            if (!HasExactKeys(input,
                    "state", "weightLayers", "formula", "level")
                || !HasExactString(input["state"], "confirmed")
                || !TryReadInteger(input["weightLayers"], -100000, 100000, out layers)
                || !TryReadInteger(input["formula"], 1, 1, out formula)
                || !TryReadInteger(input["level"], 0, int.MaxValue, out level))
                return false;
            output = new JObject
            {
                ["state"] = "confirmed",
                ["weightLayers"] = layers,
                ["formula"] = formula,
                ["level"] = level
            };
            return true;
        }

        private static bool TrySanitizeCartSnapshot(
            JArray input,
            Dictionary<int, JObject> catalog,
            out JArray output)
        {
            output = null;
            if (input == null || input.Count > MAX_CART_LINES) return false;
            var clean = new JArray();
            var seen = new HashSet<int>();
            foreach (JToken token in input)
            {
                JObject line = token as JObject;
                int idx;
                int quantity;
                if (!HasExactKeys(line, "idx", "qty")
                    || !TryReadInteger(line["idx"], 0, 10000, out idx)
                    || !TryReadInteger(
                        line["qty"], 1, MAX_PURCHASE_QUANTITY, out quantity)
                    || !seen.Add(idx) || !catalog.ContainsKey(idx)) return false;
                clean.Add(new JObject { ["idx"] = idx, ["qty"] = quantity });
            }
            output = clean;
            return true;
        }

        private static bool TrySanitizePurchased(
            JArray legacy,
            JArray view,
            out JArray cleanLegacy,
            out JArray cleanView)
        {
            cleanLegacy = null;
            cleanView = null;
            if (legacy == null || view == null || legacy.Count != view.Count
                || legacy.Count > 10000) return false;
            var legacyOut = new JArray();
            var viewOut = new JArray();
            for (int i = 0; i < legacy.Count; i++)
            {
                JArray row = legacy[i] as JArray;
                JObject item = view[i] as JObject;
                int quantity;
                double price;
                int purchasedIndex;
                int projectedQuantity;
                if (row == null || row.Count != 5
                    || !IsStringToken(row[0], 128, false)
                    || !IsIdentityToken(row[1], 128)
                    || !IsStringToken(row[2], 128, true)
                    || !TryReadNonNegativeNumber(row[3], out price)
                    || !TryReadInteger(row[4], 1, int.MaxValue, out quantity)
                    || !HasExactKeys(item,
                        "purchasedIdx", "item", "displayname", "icon", "quantity")
                    || !TryReadInteger(
                        item["purchasedIdx"], 0, 9999, out purchasedIndex)
                    || purchasedIndex != i
                    || !IsIdentityToken(item["item"], 128)
                    || !IsIdentityToken(item["displayname"], 256)
                    || !IsIdentityToken(item["icon"], 256)
                    || !TryReadInteger(
                        item["quantity"], 1, int.MaxValue, out projectedQuantity)
                    || item.Value<string>("item") != row[1].Value<string>()
                    || projectedQuantity != quantity) return false;
                legacyOut.Add(new JArray(
                    row[0].Value<string>(), row[1].Value<string>(),
                    row[2].Value<string>(), price, quantity));
                viewOut.Add(new JObject
                {
                    ["purchasedIdx"] = purchasedIndex,
                    ["item"] = item.Value<string>("item"),
                    ["displayname"] = item.Value<string>("displayname"),
                    ["icon"] = item.Value<string>("icon"),
                    ["quantity"] = projectedQuantity
                });
            }
            cleanLegacy = legacyOut;
            cleanView = viewOut;
            return true;
        }

        private static bool TrySanitizeCheckoutLines(
            JArray input,
            JArray expected,
            double balance,
            out JArray output)
        {
            output = null;
            if (input == null || expected == null || input.Count != expected.Count
                || input.Count < 1 || input.Count > MAX_CART_LINES) return false;
            var clean = new JArray();
            for (int i = 0; i < input.Count; i++)
            {
                JObject line = input[i] as JObject;
                JObject selector = expected[i] as JObject;
                int catalogIndex;
                int quantity;
                int maximum;
                int affordable;
                int byCapacity;
                int purchasable;
                double unitPrice;
                double total;
                string itemKind = line != null ? line.Value<string>("itemKind") : null;
                if (!HasExactKeys(line,
                        "catalogIndex", "itemName", "displayName", "icon",
                        "quantity", "unitPrice", "total", "maxQuantity",
                        "maxAffordable", "maxByCapacity", "maxPurchasable", "itemKind")
                    || selector == null
                    || !TryReadInteger(line["catalogIndex"], 0, 10000, out catalogIndex)
                    || !TryReadInteger(
                        line["quantity"], 1, MAX_PURCHASE_QUANTITY, out quantity)
                    || !TryReadNonNegativeNumber(line["unitPrice"], out unitPrice)
                    || !TryReadNonNegativeNumber(line["total"], out total)
                    || !TryReadInteger(
                        line["maxQuantity"], 1, MAX_PURCHASE_QUANTITY, out maximum)
                    || !TryReadInteger(
                        line["maxAffordable"], 0, MAX_PURCHASE_QUANTITY, out affordable)
                    || !TryReadInteger(
                        line["maxByCapacity"], 0, MAX_PURCHASE_QUANTITY, out byCapacity)
                    || !TryReadInteger(
                        line["maxPurchasable"], 0, MAX_PURCHASE_QUANTITY, out purchasable)
                    || !IsIdentityToken(line["itemName"], 128)
                    || !IsIdentityToken(line["displayName"], 256)
                    || !IsIdentityToken(line["icon"], 256)
                    || !IsStringToken(line["itemKind"], 32, false)
                    || !IsOneOf(itemKind, "equipment", "information", "stack")
                    || catalogIndex != selector.Value<int>("catalogIndex")
                    || quantity != selector.Value<int>("quantity")
                    || line.Value<string>("itemName") != selector.Value<string>("itemName")
                    || line.Value<string>("displayName") != selector.Value<string>("displayName")
                    || line.Value<string>("icon") != selector.Value<string>("icon")
                    || unitPrice != selector.Value<double>("unitPrice")
                    || total != selector.Value<double>("total")
                    || maximum != selector.Value<int>("maxQuantity")
                    || quantity > maximum
                    || purchasable != Math.Min(maximum, Math.Min(affordable, byCapacity)))
                    return false;
                clean.Add(new JObject
                {
                    ["catalogIndex"] = catalogIndex,
                    ["itemName"] = line.Value<string>("itemName"),
                    ["displayName"] = line.Value<string>("displayName"),
                    ["icon"] = line.Value<string>("icon"),
                    ["quantity"] = quantity,
                    ["unitPrice"] = unitPrice,
                    ["total"] = total,
                    ["maxQuantity"] = maximum,
                    ["maxAffordable"] = affordable,
                    ["maxByCapacity"] = byCapacity,
                    ["maxPurchasable"] = purchasable,
                    ["itemKind"] = itemKind
                });
            }
            // maxAffordable is computed against the same whole-order balance.
            double orderTotal = SumLineTotals(clean);
            for (int i = 0; i < clean.Count; i++)
            {
                JObject line = clean[i] as JObject;
                double unitPrice = line.Value<double>("unitPrice");
                double otherTotal = orderTotal - line.Value<double>("total");
                int maximum = line.Value<int>("maxQuantity");
                int expectedAffordable = unitPrice <= 0
                    ? maximum
                    : Math.Max(0, Math.Min(
                        maximum,
                        (int)Math.Floor((balance - otherTotal) / unitPrice)));
                if (line.Value<int>("maxAffordable") != expectedAffordable)
                    return false;
            }
            output = clean;
            return true;
        }

        private static bool IsConsistentCommitState(
            JArray lines,
            double balance,
            double total,
            bool canCommit,
            string blocking)
        {
            bool enoughCapacity = true;
            bool destinationFull = false;
            foreach (JToken token in lines)
            {
                JObject line = token as JObject;
                if (line.Value<int>("maxByCapacity") < line.Value<int>("quantity"))
                {
                    enoughCapacity = false;
                    if (line.Value<string>("itemKind") == "information")
                        destinationFull = true;
                }
            }
            string expected = balance < total
                ? "insufficient_kpoints"
                : enoughCapacity ? "" : (destinationFull ? "destination_full" : "inventory_full");
            return blocking == expected && canCommit == (expected.Length == 0);
        }

        private static double SumLineTotals(JArray lines)
        {
            double total = 0;
            foreach (JToken token in lines) total += token.Value<double>("total");
            return total;
        }

        private static bool HasExactKeys(JObject value, params string[] expected)
        {
            if (value == null || value.Count != expected.Length) return false;
            foreach (JProperty property in value.Properties())
            {
                bool found = false;
                for (int i = 0; i < expected.Length; i++)
                {
                    if (string.Equals(
                        property.Name, expected[i], StringComparison.Ordinal))
                    {
                        found = true;
                        break;
                    }
                }
                if (!found) return false;
            }
            return true;
        }

        private static bool HasExactString(JToken token, string expected)
        {
            return token != null && token.Type == JTokenType.String
                && string.Equals(
                    token.Value<string>(), expected, StringComparison.Ordinal);
        }

        private static bool HasExactInteger(JToken token, int expected)
        {
            int actual;
            return TryReadInteger(token, expected, expected, out actual);
        }

        private static bool TryReadInteger(
            JToken token,
            int minimum,
            int maximum,
            out int value)
        {
            value = 0;
            if (token == null || token.Type != JTokenType.Integer) return false;
            long candidate;
            try { candidate = token.Value<long>(); }
            catch { return false; }
            if (candidate < minimum || candidate > maximum) return false;
            value = (int)candidate;
            return true;
        }

        private static bool TryReadBoolean(JToken token, out bool value)
        {
            value = false;
            if (token == null || token.Type != JTokenType.Boolean) return false;
            value = token.Value<bool>();
            return true;
        }

        private static bool TryReadNumber(JToken token, out double value)
        {
            value = 0;
            if (token == null || (token.Type != JTokenType.Integer
                && token.Type != JTokenType.Float)) return false;
            value = token.Value<double>();
            return !double.IsNaN(value) && !double.IsInfinity(value);
        }

        private static bool TryReadNonNegativeNumber(
            JToken token,
            out double value)
        {
            return TryReadNumber(token, out value) && value >= 0;
        }

        private static bool IsSafeText(
            string value,
            int maximumLength,
            bool allowEmpty)
        {
            if (value == null || value.Length > maximumLength
                || (!allowEmpty && value.Length == 0)) return false;
            for (int i = 0; i < value.Length; i++)
            {
                if (char.IsControl(value[i])) return false;
            }
            return true;
        }

        private static bool IsStringToken(
            JToken token,
            int maximumLength,
            bool allowEmpty)
        {
            if (token == null || token.Type != JTokenType.String) return false;
            string value = token.Value<string>();
            return IsSafeText(value, maximumLength, allowEmpty);
        }

        private static bool IsIdentityToken(JToken token, int maximumLength)
        {
            if (!IsStringToken(token, maximumLength, false)) return false;
            string value = token.Value<string>();
            return !string.IsNullOrWhiteSpace(value)
                && !string.Equals(value.Trim(), "undefined", StringComparison.OrdinalIgnoreCase);
        }

        private static bool IsValidToken(string value)
        {
            return !string.IsNullOrEmpty(value) && ValidToken.IsMatch(value);
        }

        private static bool IsOneOf(string candidate, params string[] values)
        {
            for (int i = 0; i < values.Length; i++)
            {
                if (candidate == values[i]) return true;
            }
            return false;
        }

        private static bool IsDefinitiveWriteResponse(string cmd, JObject msg)
        {
            if (msg == null || msg["success"] == null
                || msg["success"].Type != JTokenType.Boolean) return false;
            if (msg.Value<bool>("success")) return true;

            string error = msg.Value<string>("error") ?? "";
            if (cmd == "checkout") return IsOneOf(error,
                "invalid_payload", "item_not_found", "not_for_sale", "locked",
                "invalid_quantity", "invalid_price", "duplicate_line",
                "insufficient_kpoints", "inventory_full", "destination_full");
            if (cmd == "checkoutCommit") return error == "insufficient_kpoints"
                || error == "inventory_full" || error == "destination_full"
                || error == "stale_state";
            if (cmd == "claim")
            {
                return error == "item_not_found"
                    || error == "inventory_full"
                    || error == "destination_full"
                    || error == "acquire_failed"
                    || error == "stale_state";
            }
            return false;
        }

        private void HandleTimeout(int fid)
        {
            if (_disposed) return;
            PendingRequest entry;
            lock (_lock)
            {
                if (!_pending.TryGetValue(fid, out entry)) return;
                CompletePendingLocked(fid, entry);
                if (entry.IsWrite && _writeOwnerFid == fid) EnterNeedsReconcileLocked();
            }
            RespondError(entry.WebCallId, entry.WebCmd, entry.OwnerPanel,
                entry.OwnerPanelInstanceId, "timeout");
        }

        private void HandleSendFailure(int fid)
        {
            PendingRequest entry;
            lock (_lock)
            {
                if (!_pending.TryGetValue(fid, out entry)) return;
                CompletePendingLocked(fid, entry);
                if (entry.IsWrite && _writeOwnerFid == fid) EnterNeedsReconcileLocked();
            }
            RespondError(entry.WebCallId, entry.WebCmd, entry.OwnerPanel,
                entry.OwnerPanelInstanceId,
                entry.IsWrite ? "reconcile_required" : "disconnected");
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

        private void EnterNeedsReconcileLocked()
        {
            _writeGate = WriteGateState.NeedsReconcile;
            _writeOwnerFid = 0;
            _reconcileEpoch++;
            _checkoutAuthority = null;
        }

        private void ClearAuthorityLocked()
        {
            _catalogByIndex = new Dictionary<int, JObject>();
            _purchasedSnapshot = new JArray();
            _purchasedViewSnapshot = new JArray();
            _purchasedToken = null;
            _knownBalance = null;
            _checkoutAuthority = null;
        }

        private void RejectAndRemember(string webCallId, string webCmd,
            string ownerPanel, string ownerPanelInstanceId, string error)
        {
            lock (_lock)
            {
                if (_activeWebCallIds.Contains(webCallId) || _recentWebCallIds.Contains(webCallId))
                {
                    LogManager.Log("[ShopTask] duplicate/replayed rejected callId ignored: " + webCallId);
                    return;
                }
                RememberRecentLocked(webCallId);
            }
            RespondError(webCallId, webCmd, ownerPanel, ownerPanelInstanceId, error);
        }

        private void RememberRecentLocked(string webCallId)
        {
            if (string.IsNullOrEmpty(webCallId) || !_recentWebCallIds.Add(webCallId)) return;
            _recentWebCallIdOrder.Enqueue(webCallId);
            while (_recentWebCallIdOrder.Count > RECENT_CALL_ID_CAPACITY)
            {
                string evicted = _recentWebCallIdOrder.Dequeue();
                _recentWebCallIds.Remove(evicted);
            }
        }

        private void RespondError(string webCallId, string webCmd,
            string ownerPanel, string ownerPanelInstanceId, string error)
        {
            var resp = new JObject();
            resp["type"] = "panel_resp";
            resp["panel"] = ownerPanel;
            resp["panelInstanceId"] = ownerPanelInstanceId;
            resp["cmd"] = webCmd;
            resp["callId"] = webCallId;
            resp["success"] = false;
            resp["error"] = error;
            PostToWeb(resp.ToString(Formatting.None));
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
