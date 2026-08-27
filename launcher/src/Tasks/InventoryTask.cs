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
            public string WebPanel;
            public string WebPanelInstanceId;
            public Func<bool> CompletionFence;
            public bool StrictTooltipResponse;
            public bool IsWrite;
            public bool IsReconcileProbe;
            public int ReconcileEpoch;
            public JObject NormalizedPayload;
            public HashSet<string> AffectedContainers;
        }

        private const int DefaultTimeoutMs = 10000;
        private const int RecentCallIdCapacity = 256;
        private static readonly Regex ValidCallId = new Regex(
            "^[A-Za-z0-9._-]{1,96}$",
            RegexOptions.CultureInvariant | RegexOptions.Compiled);
        private static readonly Regex ValidLease = new Regex(
            "^[A-Za-z0-9._-]{1,128}$",
            RegexOptions.CultureInvariant | RegexOptions.Compiled);
        private static readonly HashSet<string> CharacterTooltipErrors =
            new HashSet<string>(StringComparer.Ordinal)
            {
                "busy", "unsupported_version", "unsupported_cmd",
                "invalid_payload", "unsupported_container", "invalid_slot",
                "slot_locked", "stale_state", "item_data_missing",
                "tooltip_failed"
            };
        private static readonly HashSet<string> InventoryErrors =
            new HashSet<string>(StringComparer.Ordinal)
            {
                "busy", "unsupported_version", "unsupported_cmd", "invalid_payload",
                "unsupported_container", "unsupported_scope", "unsupported_filter",
                "invalid_slot", "slot_locked", "stale_state", "item_data_missing",
                "tooltip_failed", "discard_forbidden", "same_slot", "target_occupied",
                "merge_rejected", "target_empty", "transfer_forbidden",
                "unsupported_policy", "target_full", "unsupported_sort_method",
                "sort_forbidden", "sort_failed", "commit_failed"
            };

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
        private int _writeOwnerFid;
        private int _reconcileEpoch;
        private WriteGateState _writeGate;
        private readonly HashSet<string> _writeAffectedContainers =
            new HashSet<string>(StringComparer.Ordinal);
        private readonly HashSet<string> _reconcileContainers =
            new HashSet<string>(StringComparer.Ordinal);
        private string _navigationOwnerPanel;
        private string _navigationOwnerPanelInstanceId;
        private string _navigationLeaseToken;
        private bool _navigationLeaseTransferred;
        private long _navigationGeneration;
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
        internal string WriteState
        {
            get
            {
                lock (_lock)
                {
                    if (_writeGate == WriteGateState.WritePending) return "write_pending";
                    if (_writeGate == WriteGateState.NeedsReconcile) return "needs_reconcile";
                    return "idle";
                }
            }
        }

        public void Dispose()
        {
            _disposed = true;
            ClearPending();
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
            out MaterialShopSettlementWitness witness)
        {
            witness = null;
            lock (_lock)
            {
                if (_disposed
                    || string.IsNullOrEmpty(leaseToken)
                    || _navigationLeaseToken != null
                    || !string.Equals(_navigationOwnerPanel, panelName, StringComparison.Ordinal)
                    || !string.Equals(
                        _navigationOwnerPanelInstanceId,
                        panelInstanceId,
                        StringComparison.Ordinal)
                    || _pending.Count != 0
                    || _writeGate != WriteGateState.Idle)
                {
                    return false;
                }
                _navigationLeaseToken = leaseToken;
                _navigationLeaseTransferred = false;
                _navigationGeneration++;
                witness = new MaterialShopSettlementWitness
                {
                    TaskName = "inventory",
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
                return witness != null
                    && !_disposed
                    && !_navigationLeaseTransferred
                    && string.Equals(witness.TaskName, "inventory", StringComparison.Ordinal)
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
                    && _pending.Count == 0
                    && _writeGate == WriteGateState.Idle;
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
                && string.Equals(witness.TaskName, "inventory", StringComparison.Ordinal)
                && string.Equals(
                    witness.LeaseToken,
                    _navigationLeaseToken,
                    StringComparison.Ordinal)
                && witness.Generation == _navigationGeneration;
        }

        public void HandleWebRequest(string cmd, JObject parsed)
        {
            HandleWebRequestCore(cmd, parsed, null, false);
        }

        internal void HandleCharacterCandidateTooltip(
            JObject parsed,
            Func<bool> completionFence)
        {
            HandleWebRequestCore("tooltip", parsed, completionFence, true);
        }

        private void HandleWebRequestCore(
            string cmd,
            JObject parsed,
            Func<bool> completionFence,
            bool strictTooltipResponse)
        {
            string webCallId = parsed != null ? parsed.Value<string>("callId") : null;
            string webPanel = parsed != null ? parsed.Value<string>("panel") : null;
            string webPanelInstanceId = parsed != null
                ? parsed.Value<string>("panelInstanceId") : null;
            if (string.IsNullOrEmpty(webCallId)) return;
            if (!ValidCallId.IsMatch(webCallId))
            {
                RespondError(webCallId, cmd, "invalid_call_id", webPanel, webPanelInstanceId);
                return;
            }
            if (!string.Equals(parsed.Value<string>("domain"), "inventory", StringComparison.Ordinal))
            {
                RejectAndRemember(webCallId, cmd, "unsupported_domain",
                    webPanel, webPanelInstanceId);
                return;
            }

            string action;
            bool isWrite;
            if (!TryResolveCommand(cmd, out action, out isWrite))
            {
                RejectAndRemember(webCallId, cmd, "unsupported_cmd",
                    webPanel, webPanelInstanceId);
                return;
            }

            JObject payload = parsed["payload"] as JObject;
            int payloadVersion;
            if (payload == null || !TryReadNonNegativeInteger(payload["v"], out payloadVersion))
            {
                RejectAndRemember(webCallId, cmd, "invalid_payload",
                    webPanel, webPanelInstanceId);
                return;
            }
            if (payloadVersion != 1)
            {
                RejectAndRemember(webCallId, cmd, "unsupported_version",
                    webPanel, webPanelInstanceId);
                return;
            }

            JObject normalized;
            if (!TryNormalizePayload(cmd, payload, out normalized))
            {
                RejectAndRemember(webCallId, cmd, "invalid_payload",
                    webPanel, webPanelInstanceId);
                return;
            }
            if (strictTooltipResponse && !IsCompletionFenceCurrent(completionFence))
            {
                RejectAndRemember(webCallId, cmd, "stale_state",
                    webPanel, webPanelInstanceId);
                return;
            }
            if (!_isClientReady())
            {
                RejectAndRemember(webCallId, cmd, "disconnected",
                    webPanel, webPanelInstanceId);
                return;
            }

            HashSet<string> affectedContainers = isWrite
                ? GetAffectedContainers(cmd, normalized)
                : new HashSet<string>(StringComparer.Ordinal);
            int fid = 0;
            string localError = null;
            lock (_lock)
            {
                if (_activeWebCallIds.Contains(webCallId) || _recentWebCallIds.Contains(webCallId))
                {
                    LogManager.Log("[InventoryTask] duplicate/replayed callId ignored: " + webCallId);
                    return;
                }
                if (_navigationLeaseToken != null)
                {
                    localError = "busy";
                }
                else if (isWrite && _writeGate == WriteGateState.WritePending)
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
                    fid = ++_seq;
                    bool reconcileProbe = cmd == "snapshot"
                        && _writeGate == WriteGateState.NeedsReconcile
                        && SnapshotRequestCovers(
                            normalized["requests"] as JArray,
                            _reconcileContainers);
                    _pending[fid] = new PendingRequest
                    {
                        WebCallId = webCallId,
                        WebCmd = cmd,
                        WebPanel = webPanel,
                        WebPanelInstanceId = webPanelInstanceId,
                        CompletionFence = completionFence,
                        StrictTooltipResponse = strictTooltipResponse,
                        IsWrite = isWrite,
                        IsReconcileProbe = reconcileProbe,
                        ReconcileEpoch = _reconcileEpoch,
                        NormalizedPayload = (JObject)normalized.DeepClone(),
                        AffectedContainers = affectedContainers
                    };
                    _activeWebCallIds.Add(webCallId);
                    _navigationGeneration++;
                    if (isWrite)
                    {
                        _writeGate = WriteGateState.WritePending;
                        _writeOwnerFid = fid;
                        _writeAffectedContainers.Clear();
                        foreach (string containerId in affectedContainers)
                            _writeAffectedContainers.Add(containerId);
                    }
                }
            }

            if (localError != null)
            {
                RespondError(webCallId, cmd, localError, webPanel, webPanelInstanceId);
                return;
            }

            var timer = new Timer(delegate { HandleTimeout(fid); }, null, _timeoutMs, Timeout.Infinite);
            lock (_lock)
            {
                if (_pending.ContainsKey(fid)) _timers[fid] = timer;
                else timer.Dispose();
            }

            JObject flashMessage = PanelBridge.BuildFlashCommand(action, fid, normalized);
            string flashJson = flashMessage.ToString(Formatting.None);
            LogManager.Log(AuthorityLogFormatter.FormatAuthorityFlashCallBound(
                "InventoryTask", webCallId, fid, webPanel, webPanelInstanceId,
                cmd, action));
            LogManager.Log(AuthorityLogFormatter.FormatFlashCommand(
                "InventoryTask", flashMessage));
            bool sent = false;
            try
            {
                sent = _trySend(flashJson + "\0");
            }
            catch (Exception ex)
            {
                LogManager.Log(
                    "[InventoryTask] transport send threw: "
                    + ex.GetType().Name);
            }
            if (!sent) HandleSendFailure(fid);
        }

        public void HandleFlashResponse(JObject msg, Action<string> respond)
        {
            int fid;
            try
            {
                fid = msg != null ? msg.Value<int>("callId") : 0;
            }
            catch
            {
                if (respond != null) respond(null);
                return;
            }
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

            if (entry.StrictTooltipResponse
                && !IsCompletionFenceCurrent(entry.CompletionFence))
            {
                RespondError(entry.WebCallId, entry.WebCmd, "stale_state",
                    entry.WebPanel, entry.WebPanelInstanceId);
                if (respond != null) respond(null);
                return;
            }

            JObject webMessage;
            bool malformed = !TryNormalizeResponse(
                msg, fid, entry, out webMessage);
            bool definitiveWrite = false;
            lock (_lock)
            {
                if (entry.IsWrite && _writeOwnerFid == fid)
                {
                    definitiveWrite = !malformed
                        && IsDefinitiveWriteResponse(webMessage);
                    if (definitiveWrite)
                    {
                        _writeGate = WriteGateState.Idle;
                        _writeOwnerFid = 0;
                        _writeAffectedContainers.Clear();
                        _reconcileContainers.Clear();
                    }
                    else
                    {
                        EnterNeedsReconcileLocked(entry.AffectedContainers);
                    }
                }
                else if (!malformed
                    && entry.IsReconcileProbe
                    && entry.ReconcileEpoch == _reconcileEpoch
                    && _writeGate == WriteGateState.NeedsReconcile
                    && webMessage.Value<bool?>("success") == true)
                {
                    _writeGate = WriteGateState.Idle;
                    _reconcileContainers.Clear();
                }
            }

            if (malformed)
            {
                webMessage = new JObject
                {
                    ["success"] = false,
                    ["error"] = "malformed_response"
                };
            }
            if (entry.IsWrite && !definitiveWrite)
                webMessage["requiresReconcile"] = true;
            // AS2 is not allowed to manufacture or retain a Web panel capability.  Restore these
            // fields solely from the Host-validated pending request (or omit them for legacy calls).
            webMessage["type"] = "panel_resp";
            webMessage["domain"] = "inventory";
            webMessage["cmd"] = entry.WebCmd;
            webMessage["callId"] = entry.WebCallId;
            if (!string.IsNullOrEmpty(entry.WebPanel)) webMessage["panel"] = entry.WebPanel;
            if (!string.IsNullOrEmpty(entry.WebPanelInstanceId))
                webMessage["panelInstanceId"] = entry.WebPanelInstanceId;
            PostToWeb(webMessage.ToString(Formatting.None));
            if (respond != null) respond(null);
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
                if (_writeGate == WriteGateState.WritePending)
                    EnterNeedsReconcileLocked(_writeAffectedContainers);
                foreach (PendingRequest entry in _pending.Values)
                {
                    _activeWebCallIds.Remove(entry.WebCallId);
                    RememberRecentLocked(entry.WebCallId);
                }
                foreach (Timer timer in _timers.Values) timer.Dispose();
                _timers.Clear();
                _pending.Clear();
                _writeOwnerFid = 0;
            }
        }

        private static bool TryResolveCommand(string cmd, out string action, out bool isWrite)
        {
            isWrite = false;
            switch (cmd)
            {
                case "snapshot": action = "inventorySnapshot"; return true;
                case "tooltip": action = "inventoryTooltip"; return true;
                case "discard": action = "inventoryDiscard"; isWrite = true; return true;
                case "move": action = "inventoryMove"; isWrite = true; return true;
                case "merge": action = "inventoryMerge"; isWrite = true; return true;
                case "swap": action = "inventorySwap"; isWrite = true; return true;
                case "autoTransfer": action = "inventoryAutoTransfer"; isWrite = true; return true;
                case "autoTransferBatch": action = "inventoryAutoTransferBatch"; isWrite = true; return true;
                case "sortAndMerge": action = "inventorySortAndMerge"; isWrite = true; return true;
                default: action = null; return false;
            }
        }

        private static bool TryNormalizePayload(string cmd, JObject payload, out JObject normalized)
        {
            normalized = new JObject { ["v"] = 1 };
            if (cmd == "snapshot")
            {
                JArray cleanRequests;
                if (!TryNormalizeWindows(payload["requests"] as JArray, out cleanRequests)) return false;
                normalized["requests"] = cleanRequests;
                return true;
            }

            if (cmd == "sortAndMerge")
            {
                JObject container = payload["container"] as JObject;
                string containerId = container != null ? container.Value<string>("containerId") : null;
                string filterKey = container != null ? (container.Value<string>("filterKey") ?? "all") : null;
                string scope = container != null ? (container.Value<string>("scope") ?? "all") : null;
                string methodName = payload.Value<string>("methodName");
                int offset;
                int limit;
                if (container == null
                    || !IsKnownContainerId(containerId)
                    || !TryReadNonNegativeInteger(container["offset"], out offset)
                    || !TryReadPositiveInteger(container["limit"], 100, out limit)
                    || !IsFilterKey(filterKey)
                    || !string.Equals(scope, "all", StringComparison.Ordinal)
                    || !IsSortMethod(methodName)) return false;
                var cleanContainer = new JObject
                {
                    ["containerId"] = containerId,
                    ["offset"] = offset,
                    ["limit"] = limit,
                    ["filterKey"] = filterKey
                };
                JObject filterSpec;
                if (!TryNormalizeFilterSpec(container["filterSpec"], filterKey, out filterSpec)) return false;
                if (filterSpec != null) cleanContainer["filterSpec"] = filterSpec;
                normalized["container"] = cleanContainer;
                normalized["methodName"] = methodName;
                return true;
            }

            if (cmd == "autoTransferBatch")
                return TryNormalizeAutoTransferBatchPayload(payload, out normalized);

            if (payload["count"] != null) return false;
            JObject source;
            if (!TryNormalizeSlotRef(payload["source"] as JObject, out source)) return false;
            normalized["source"] = source;
            if (cmd == "discard" || cmd == "tooltip") return true;

            if (cmd == "autoTransfer")
            {
                string targetContainerId = payload.Value<string>("targetContainerId");
                string policy = payload.Value<string>("policy");
                JArray windows;
                if (!IsKnownContainerId(targetContainerId)
                    || !string.Equals(policy, "mergeThenEmpty", StringComparison.Ordinal)
                    || !TryNormalizeWindows(payload["windows"] as JArray, out windows)) return false;
                normalized["targetContainerId"] = targetContainerId;
                normalized["policy"] = policy;
                normalized["windows"] = windows;
                return true;
            }

            JObject target;
            if (!TryNormalizeSlotRef(payload["target"] as JObject, out target)) return false;
            normalized["target"] = target;
            return true;
        }

        private static bool TryNormalizeAutoTransferBatchPayload(
            JObject payload,
            out JObject normalized)
        {
            normalized = null;
            if (!HasExactKeys(
                    payload,
                    "v", "sources", "targetContainerId", "policy", "windows")
                || !HasExactInteger(payload["v"], 1)
                || !HasExactString(payload["policy"], "mergeThenEmpty")
                || payload["targetContainerId"] == null
                || payload["targetContainerId"].Type != JTokenType.String)
            {
                return false;
            }

            JArray sources = payload["sources"] as JArray;
            if (sources == null || sources.Count < 1 || sources.Count > 50)
                return false;

            string sourceContainerId = null;
            var seenSlots = new HashSet<int>();
            var cleanSources = new JArray();
            foreach (JToken token in sources)
            {
                JObject input = token as JObject;
                JObject source;
                if (!HasExactKeys(input, "containerId", "slot", "expectedLease")
                    || input["containerId"].Type != JTokenType.String
                    || input["expectedLease"].Type != JTokenType.String
                    || !TryNormalizeSlotRef(input, out source)) return false;

                string currentContainerId = source.Value<string>("containerId");
                int currentSlot = source.Value<int>("slot");
                if (sourceContainerId == null) sourceContainerId = currentContainerId;
                else if (!string.Equals(
                    sourceContainerId, currentContainerId, StringComparison.Ordinal)) return false;
                if (!seenSlots.Add(currentSlot)) return false;
                cleanSources.Add(source);
            }

            string targetContainerId = payload.Value<string>("targetContainerId");
            if (!IsKnownContainerId(targetContainerId)
                || !IsAllowedAutoTransferPair(sourceContainerId, targetContainerId))
            {
                return false;
            }

            JArray windows;
            if (!TryNormalizeStrictWindows(payload["windows"] as JArray, out windows)
                || !WindowSetExactlyMatches(
                    windows, sourceContainerId, targetContainerId)) return false;

            normalized = new JObject
            {
                ["v"] = 1,
                ["sources"] = cleanSources,
                ["targetContainerId"] = targetContainerId,
                ["policy"] = "mergeThenEmpty",
                ["windows"] = windows
            };
            return true;
        }

        private static bool TryNormalizeStrictWindows(
            JArray requests,
            out JArray normalized)
        {
            normalized = null;
            if (requests == null || requests.Count < 1 || requests.Count > 4)
                return false;
            foreach (JToken token in requests)
            {
                JObject request = token as JObject;
                if (!HasOnlyKeys(
                        request,
                        "containerId", "offset", "limit", "filterKey",
                        "scope", "filterSpec")
                    || !HasRequiredKeys(request, "containerId", "offset", "limit")
                    || request["containerId"].Type != JTokenType.String)
                {
                    return false;
                }
                if (request.Property("filterKey") != null
                    && request["filterKey"].Type != JTokenType.String) return false;
                if (request.Property("scope") != null
                    && request["scope"].Type != JTokenType.String) return false;
                if (!HasStrictFilterSpecKeys(request["filterSpec"])) return false;
            }
            return TryNormalizeWindows(requests, out normalized);
        }

        private static bool HasStrictFilterSpecKeys(JToken token)
        {
            if (token == null || token.Type == JTokenType.Null) return true;
            JObject input = token as JObject;
            if (input == null) return false;
            JToken branchToken = input["branch"];
            if (branchToken != null && branchToken.Type != JTokenType.String)
                return false;
            string branch = input.Value<string>("branch") ?? "category";
            if (branch == "set")
                return HasOnlyKeys(input, "branch", "setId")
                    && (input.Property("setId") == null
                        || input["setId"].Type == JTokenType.String);
            if (branch != "category") return false;
            if (!HasOnlyKeys(input, "branch", "major", "use", "subtype"))
                return false;
            return (input.Property("major") == null
                    || input["major"].Type == JTokenType.String)
                && (input.Property("use") == null
                    || input["use"].Type == JTokenType.String)
                && (input.Property("subtype") == null
                    || input["subtype"].Type == JTokenType.String);
        }

        private static bool IsAllowedAutoTransferPair(
            string sourceContainerId,
            string targetContainerId)
        {
            if (sourceContainerId == "背包")
                return targetContainerId == "仓库" || targetContainerId == "战备箱";
            return targetContainerId == "背包"
                && (sourceContainerId == "仓库" || sourceContainerId == "战备箱");
        }

        private static bool WindowSetExactlyMatches(
            JArray windows,
            string sourceContainerId,
            string targetContainerId)
        {
            if (windows == null || windows.Count != 2) return false;
            var expected = new HashSet<string>(StringComparer.Ordinal)
            {
                sourceContainerId,
                targetContainerId
            };
            foreach (JToken token in windows)
            {
                JObject window = token as JObject;
                if (window == null
                    || !expected.Remove(window.Value<string>("containerId"))) return false;
            }
            return expected.Count == 0;
        }

        private static bool TryNormalizeWindows(JArray requests, out JArray normalized)
        {
            normalized = null;
            if (requests == null || requests.Count < 1 || requests.Count > 4) return false;
            var cleanRequests = new JArray();
            var seenContainers = new HashSet<string>(StringComparer.Ordinal);
            foreach (JToken token in requests)
            {
                JObject request = token as JObject;
                if (request == null) return false;
                string containerId = request.Value<string>("containerId");
                string filterKey = request.Value<string>("filterKey") ?? "all";
                string scope = request.Value<string>("scope") ?? "all";
                int offset;
                int limit;
                if (!IsKnownContainerId(containerId)
                    || !seenContainers.Add(containerId)
                    || !TryReadNonNegativeInteger(request["offset"], out offset)
                    || !TryReadPositiveInteger(request["limit"], 100, out limit)
                    || !IsFilterKey(filterKey)
                    || !IsProjectionScope(scope)
                    || (scope == "equipment" && containerId != "背包")) return false;
                var cleanRequest = new JObject
                {
                    ["containerId"] = containerId,
                    ["offset"] = offset,
                    ["limit"] = limit,
                    ["filterKey"] = filterKey
                };
                if (scope == "equipment") cleanRequest["scope"] = scope;
                JObject filterSpec;
                if (!TryNormalizeFilterSpec(request["filterSpec"], filterKey, out filterSpec)) return false;
                if (filterSpec != null) cleanRequest["filterSpec"] = filterSpec;
                cleanRequests.Add(cleanRequest);
            }
            normalized = cleanRequests;
            return true;
        }

        private static bool TryNormalizeSlotRef(JObject input, out JObject normalized)
        {
            normalized = null;
            if (input == null || input["count"] != null) return false;
            string containerId = input.Value<string>("containerId");
            string expectedLease = input.Value<string>("expectedLease");
            int slot;
            if (!IsKnownContainerId(containerId)
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

        private static bool IsKnownContainerId(string value)
        {
            return value == "背包" || value == "仓库" || value == "战备箱";
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

        private static bool IsFilterKey(string value)
        {
            switch (value)
            {
                case "all":
                case "weapon":
                case "armor":
                case "consumable":
                case "material":
                case "other":
                    return true;
                default:
                    return false;
            }
        }

        private static bool IsProjectionScope(string value)
        {
            return value == "all" || value == "equipment";
        }

        private static bool TryNormalizeFilterSpec(JToken token, string fallbackKey, out JObject normalized)
        {
            normalized = null;
            if (token == null || token.Type == JTokenType.Null) return true;
            JObject input = token as JObject;
            if (input == null) return false;
            string branch = input.Value<string>("branch") ?? "category";
            if (branch == "set")
            {
                string setId = input.Value<string>("setId") ?? string.Empty;
                if (fallbackKey != "all" || !IsSafeFilterValue(setId)) return false;
                normalized = new JObject { ["branch"] = "set" };
                if (setId.Length > 0) normalized["setId"] = setId;
                return true;
            }
            if (branch != "category") return false;
            string major = input.Value<string>("major") ?? fallbackKey;
            string use = input.Value<string>("use") ?? string.Empty;
            string subtype = input.Value<string>("subtype") ?? string.Empty;
            if (!IsFilterMajor(major)
                || !IsSafeFilterValue(use)
                || !IsSafeFilterValue(subtype)
                || !FilterSpecMatchesKey(fallbackKey, major)
                || (major == "all" && (use.Length > 0 || subtype.Length > 0))
                || (subtype.Length > 0 && (major != "weapon" || use.Length == 0))) return false;
            normalized = new JObject { ["major"] = major };
            if (input["branch"] != null) normalized["branch"] = "category";
            if (use.Length > 0) normalized["use"] = use;
            if (subtype.Length > 0) normalized["subtype"] = subtype;
            return true;
        }

        private static bool FilterSpecMatchesKey(string filterKey, string major)
        {
            string expectedKey = major == "collection" ? "other" : major;
            return filterKey == expectedKey;
        }

        private static bool IsFilterMajor(string value)
        {
            return value == "all" || value == "weapon" || value == "armor"
                || value == "consumable" || value == "material"
                || value == "collection" || value == "other";
        }

        private static bool IsSafeFilterValue(string value)
        {
            if (value == null || value.Length > 64) return false;
            for (int i = 0; i < value.Length; i++)
            {
                if (char.IsControl(value[i])) return false;
            }
            return true;
        }

        private static bool TryReadNonNegativeInteger(JToken token, out int value)
        {
            value = 0;
            if (token == null || token.Type != JTokenType.Integer) return false;
            long candidate;
            try { candidate = token.ToObject<long>(); }
            catch { return false; }
            if (candidate < 0 || candidate > int.MaxValue) return false;
            value = (int)candidate;
            return true;
        }

        private static bool TryReadPositiveInteger(JToken token, int max, out int value)
        {
            if (!TryReadNonNegativeInteger(token, out value)) return false;
            return value > 0 && value <= max;
        }

        private static bool IsCompletionFenceCurrent(Func<bool> fence)
        {
            if (fence == null) return false;
            try { return fence(); }
            catch { return false; }
        }

        private static string PendingError(PendingRequest entry, string fallback)
        {
            return entry != null && entry.StrictTooltipResponse
                    && !IsCompletionFenceCurrent(entry.CompletionFence)
                ? "stale_state" : fallback;
        }

        private static HashSet<string> GetAffectedContainers(
            string cmd,
            JObject normalized)
        {
            var affected = new HashSet<string>(StringComparer.Ordinal);
            if (normalized == null) return affected;
            if (cmd == "sortAndMerge")
            {
                JObject container = normalized["container"] as JObject;
                AddContainer(affected, container != null
                    ? container.Value<string>("containerId") : null);
                return affected;
            }
            if (cmd == "autoTransferBatch")
            {
                JArray sources = normalized["sources"] as JArray;
                if (sources != null)
                {
                    foreach (JToken token in sources)
                    {
                        JObject sourceEntry = token as JObject;
                        AddContainer(affected, sourceEntry != null
                            ? sourceEntry.Value<string>("containerId") : null);
                    }
                }
                AddContainer(affected, normalized.Value<string>("targetContainerId"));
                return affected;
            }
            JObject source = normalized["source"] as JObject;
            AddContainer(affected, source != null
                ? source.Value<string>("containerId") : null);
            if (cmd == "move" || cmd == "merge" || cmd == "swap")
            {
                JObject target = normalized["target"] as JObject;
                AddContainer(affected, target != null
                    ? target.Value<string>("containerId") : null);
            }
            else if (cmd == "autoTransfer")
            {
                AddContainer(affected, normalized.Value<string>("targetContainerId"));
            }
            return affected;
        }

        private static void AddContainer(HashSet<string> containers, string containerId)
        {
            if (containers != null && !string.IsNullOrEmpty(containerId))
                containers.Add(containerId);
        }

        private static bool SnapshotRequestCovers(
            JArray requests,
            HashSet<string> required)
        {
            if (requests == null || required == null || required.Count == 0) return false;
            var present = new HashSet<string>(StringComparer.Ordinal);
            foreach (JToken token in requests)
            {
                JObject request = token as JObject;
                if (request != null) AddContainer(
                    present, request.Value<string>("containerId"));
            }
            foreach (string containerId in required)
            {
                if (!present.Contains(containerId)) return false;
            }
            return true;
        }

        private static bool TryNormalizeResponse(
            JObject message,
            int backendCallId,
            PendingRequest entry,
            out JObject normalized)
        {
            normalized = null;
            if (entry == null) return false;
            if (entry.WebCmd == "tooltip")
                return TryNormalizeCharacterTooltipResponse(
                    message, backendCallId, out normalized);
            if (message == null
                || !HasExactString(message["task"], "inventory_response")
                || !HasExactInteger(message["callId"], backendCallId)
                || message["success"] == null
                || message["success"].Type != JTokenType.Boolean)
            {
                return false;
            }
            if (!message.Value<bool>("success"))
            {
                if (!HasExactKeys(message,
                        "task", "callId", "success", "error")
                    || !IsBoundedText(message["error"], 64, false)) return false;
                string error = message.Value<string>("error");
                if (!InventoryErrors.Contains(error)) return false;
                normalized = new JObject
                {
                    ["success"] = false,
                    ["error"] = error
                };
                return true;
            }
            if (entry.WebCmd == "snapshot")
                return TryNormalizeSnapshotResponse(message, entry, out normalized);
            return entry.IsWrite
                && TryNormalizeWriteResponse(message, entry, out normalized);
        }

        private static bool TryNormalizeSnapshotResponse(
            JObject message,
            PendingRequest entry,
            out JObject normalized)
        {
            normalized = null;
            if (!HasExactKeys(message,
                    "task", "callId", "success", "v", "sessionNonce", "snapshots")
                || !HasExactInteger(message["v"], 1)
                || !IsBoundedText(message["sessionNonce"], 128, false)) return false;
            JArray snapshots;
            if (!TrySanitizeSnapshotBatch(
                    message["snapshots"] as JArray,
                    entry.NormalizedPayload != null
                        ? entry.NormalizedPayload["requests"] as JArray : null,
                    true,
                    out snapshots)) return false;
            normalized = new JObject
            {
                ["success"] = true,
                ["v"] = 1,
                ["sessionNonce"] = message.Value<string>("sessionNonce"),
                ["snapshots"] = snapshots
            };
            return true;
        }

        private static bool TryNormalizeWriteResponse(
            JObject message,
            PendingRequest entry,
            out JObject normalized)
        {
            normalized = null;
            JArray snapshots;
            if (entry.WebCmd == "discard")
            {
                JObject source = entry.NormalizedPayload != null
                    ? entry.NormalizedPayload["source"] as JObject : null;
                JObject discarded;
                if (!HasExactKeys(message,
                        "task", "callId", "success", "v", "operation",
                        "discarded", "snapshots")
                    || !HasExactInteger(message["v"], 1)
                    || !HasExactString(message["operation"], "discard")
                    || source == null
                    || source.Value<string>("containerId") != "背包"
                    || !TrySanitizeItem(message["discarded"] as JObject, out discarded)
                    || !TrySanitizeSnapshotBatch(
                        message["snapshots"] as JArray, null, false, out snapshots)
                    || !SnapshotBatchMatchesAffected(
                        snapshots, entry.AffectedContainers)
                    || !SnapshotBatchCoversSlotRef(snapshots, source)) return false;
                normalized = new JObject
                {
                    ["success"] = true, ["v"] = 1,
                    ["operation"] = "discard", ["discarded"] = discarded,
                    ["snapshots"] = snapshots
                };
                return true;
            }

            if (entry.WebCmd == "move" || entry.WebCmd == "merge"
                || entry.WebCmd == "swap")
            {
                JObject source = entry.NormalizedPayload != null
                    ? entry.NormalizedPayload["source"] as JObject : null;
                JObject target = entry.NormalizedPayload != null
                    ? entry.NormalizedPayload["target"] as JObject : null;
                if (!HasExactKeys(message,
                        "task", "callId", "success", "v", "operation", "snapshots")
                    || !HasExactInteger(message["v"], 1)
                    || !HasExactString(message["operation"], entry.WebCmd)
                    || !TrySanitizeSnapshotBatch(
                        message["snapshots"] as JArray, null, false, out snapshots)
                    || !SnapshotBatchMatchesAffected(
                        snapshots, entry.AffectedContainers)
                    || !SnapshotBatchCoversSlotRef(snapshots, source)
                    || !SnapshotBatchCoversSlotRef(snapshots, target)) return false;
                normalized = new JObject
                {
                    ["success"] = true, ["v"] = 1,
                    ["operation"] = entry.WebCmd, ["snapshots"] = snapshots
                };
                return true;
            }

            if (entry.WebCmd == "autoTransfer")
            {
                JObject destination = message["destination"] as JObject;
                int destinationSlot;
                string operation = message.Value<string>("operation");
                string targetContainerId = entry.NormalizedPayload != null
                    ? entry.NormalizedPayload.Value<string>("targetContainerId") : null;
                if (!HasExactKeys(message,
                        "task", "callId", "success", "v", "operation", "policy",
                        "destination", "snapshots")
                    || !HasExactInteger(message["v"], 1)
                    || (operation != "move" && operation != "merge")
                    || !HasExactString(message["policy"], "mergeThenEmpty")
                    || !HasExactKeys(destination, "containerId", "slot")
                    || destination.Value<string>("containerId") != targetContainerId
                    || !TryReadInteger(destination["slot"], 0, 1199, out destinationSlot)
                    || !TrySanitizeSnapshotBatch(
                        message["snapshots"] as JArray,
                        entry.NormalizedPayload != null
                            ? entry.NormalizedPayload["windows"] as JArray : null,
                        true,
                        out snapshots)
                    || !SnapshotBatchMatchesAffected(
                        snapshots, entry.AffectedContainers)) return false;
                normalized = new JObject
                {
                    ["success"] = true, ["v"] = 1,
                    ["operation"] = operation,
                    ["policy"] = "mergeThenEmpty",
                    ["destination"] = new JObject
                    {
                        ["containerId"] = targetContainerId,
                        ["slot"] = destinationSlot
                    },
                    ["snapshots"] = snapshots
                };
                return true;
            }

            if (entry.WebCmd == "autoTransferBatch")
            {
                JArray sources = entry.NormalizedPayload != null
                    ? entry.NormalizedPayload["sources"] as JArray : null;
                int requestedCount = sources != null ? sources.Count : 0;
                int responseRequestedCount;
                int completedCount = 0;
                string targetContainerId = entry.NormalizedPayload != null
                    ? entry.NormalizedPayload.Value<string>("targetContainerId") : null;
                JArray inputResults = message["results"] as JArray;
                bool countsValid = TryReadInteger(
                        message["requestedCount"], 1, 50, out responseRequestedCount)
                    && responseRequestedCount == requestedCount
                    && TryReadInteger(
                        message["completedCount"], 1, requestedCount, out completedCount);
                bool partial = countsValid && completedCount < requestedCount;
                if ((!partial && !HasExactKeys(message,
                            "task", "callId", "success", "v", "operation", "policy",
                            "requestedCount", "completedCount", "results", "snapshots"))
                    || (partial && !HasExactKeys(message,
                            "task", "callId", "success", "v", "operation", "policy",
                            "requestedCount", "completedCount", "results", "failure",
                            "snapshots"))
                    || !HasExactInteger(message["v"], 1)
                    || !HasExactString(message["operation"], "autoTransferBatch")
                    || !HasExactString(message["policy"], "mergeThenEmpty")
                    || !countsValid
                    || inputResults == null
                    || inputResults.Count != completedCount)
                {
                    return false;
                }

                var results = new JArray();
                foreach (JToken token in inputResults)
                {
                    JObject result = token as JObject;
                    JObject destination = result != null
                        ? result["destination"] as JObject : null;
                    string operation = result != null
                        ? result.Value<string>("operation") : null;
                    int destinationSlot;
                    if (!HasExactKeys(result, "operation", "destination")
                        || (operation != "move" && operation != "merge")
                        || !HasExactKeys(destination, "containerId", "slot")
                        || destination["containerId"].Type != JTokenType.String
                        || destination.Value<string>("containerId") != targetContainerId
                        || !TryReadInteger(
                            destination["slot"], 0, 1199, out destinationSlot))
                    {
                        return false;
                    }
                    results.Add(new JObject
                    {
                        ["operation"] = operation,
                        ["destination"] = new JObject
                        {
                            ["containerId"] = targetContainerId,
                            ["slot"] = destinationSlot
                        }
                    });
                }

                JObject failure = message["failure"] as JObject;
                if (partial)
                {
                    int failureIndex;
                    if (!HasExactKeys(failure, "index", "error")
                        || !TryReadInteger(
                            failure["index"], completedCount, completedCount,
                            out failureIndex)
                        || !HasExactString(failure["error"], "target_full"))
                    {
                        return false;
                    }
                }
                if (!TrySanitizeSnapshotBatch(
                        message["snapshots"] as JArray,
                        entry.NormalizedPayload != null
                            ? entry.NormalizedPayload["windows"] as JArray : null,
                        true,
                        out snapshots)
                    || !SnapshotBatchMatchesAffected(
                        snapshots, entry.AffectedContainers)) return false;

                normalized = new JObject
                {
                    ["success"] = true,
                    ["v"] = 1,
                    ["operation"] = "autoTransferBatch",
                    ["policy"] = "mergeThenEmpty",
                    ["requestedCount"] = requestedCount,
                    ["completedCount"] = completedCount,
                    ["results"] = results,
                    ["snapshots"] = snapshots
                };
                if (partial)
                {
                    normalized["failure"] = new JObject
                    {
                        ["index"] = completedCount,
                        ["error"] = "target_full"
                    };
                }
                return true;
            }

            if (entry.WebCmd == "sortAndMerge")
            {
                int sortedCapacity;
                JObject container = entry.NormalizedPayload != null
                    ? entry.NormalizedPayload["container"] as JObject : null;
                JArray expected = container == null
                    ? null : new JArray((JObject)container.DeepClone());
                string methodName = entry.NormalizedPayload != null
                    ? entry.NormalizedPayload.Value<string>("methodName") : null;
                if (!HasExactKeys(message,
                        "task", "callId", "success", "v", "operation",
                        "methodName", "sortedCapacity", "snapshots")
                    || !HasExactInteger(message["v"], 1)
                    || !HasExactString(message["operation"], "sortAndMerge")
                    || !HasExactString(message["methodName"], methodName)
                    || !TryReadInteger(message["sortedCapacity"], 1, 1200,
                        out sortedCapacity)
                    || !TrySanitizeSnapshotBatch(
                        message["snapshots"] as JArray, expected, true, out snapshots)
                    || !SnapshotBatchMatchesAffected(
                        snapshots, entry.AffectedContainers)) return false;
                normalized = new JObject
                {
                    ["success"] = true, ["v"] = 1,
                    ["operation"] = "sortAndMerge",
                    ["methodName"] = methodName,
                    ["sortedCapacity"] = sortedCapacity,
                    ["snapshots"] = snapshots
                };
                return true;
            }
            return false;
        }

        private static bool IsDefinitiveWriteResponse(JObject normalized)
        {
            if (normalized == null) return false;
            if (normalized.Value<bool?>("success") == true) return true;
            return normalized.Value<bool?>("success") == false
                && normalized.Value<string>("error") != "commit_failed";
        }

        private static bool SnapshotBatchMatchesAffected(
            JArray snapshots,
            HashSet<string> affected)
        {
            if (snapshots == null || snapshots.Count == 0
                || affected == null || affected.Count == 0) return false;
            var seen = new HashSet<string>(StringComparer.Ordinal);
            foreach (JToken token in snapshots)
            {
                string containerId = token.Value<string>("containerId");
                if (!affected.Contains(containerId)) return false;
                seen.Add(containerId);
            }
            foreach (string containerId in affected)
            {
                if (!seen.Contains(containerId)) return false;
            }
            return true;
        }

        private static bool SnapshotBatchCoversSlotRef(
            JArray snapshots,
            JObject slotRef)
        {
            if (snapshots == null || slotRef == null) return false;
            string containerId = slotRef.Value<string>("containerId");
            int physicalSlot;
            if (!TryReadInteger(
                    slotRef["slot"], 0, int.MaxValue, out physicalSlot)) return false;
            foreach (JToken snapshotToken in snapshots)
            {
                JObject snapshot = snapshotToken as JObject;
                if (snapshot == null
                    || snapshot.Value<string>("containerId") != containerId) continue;
                JArray slots = snapshot["slots"] as JArray;
                if (slots == null) continue;
                foreach (JToken slotToken in slots)
                {
                    if (slotToken.Value<int?>("physicalSlot") == physicalSlot)
                        return true;
                }
            }
            return false;
        }

        private static bool TrySanitizeSnapshotBatch(
            JArray input,
            JArray expectedRequests,
            bool bindRequests,
            out JArray output)
        {
            output = null;
            if (input == null || input.Count < 1 || input.Count > 4) return false;
            if (bindRequests
                && (expectedRequests == null || input.Count != expectedRequests.Count))
                return false;
            var clean = new JArray();
            if (!bindRequests)
            {
                var seenContainers = new HashSet<string>(StringComparer.Ordinal);
                foreach (JToken token in input)
                {
                    JObject snapshot;
                    if (!TrySanitizeSnapshot(token as JObject, out snapshot)) return false;
                    if (!seenContainers.Add(snapshot.Value<string>("containerId")))
                        return false;
                    clean.Add(snapshot);
                }
                output = clean;
                return true;
            }

            var byContainer = new Dictionary<string, JObject>(StringComparer.Ordinal);
            foreach (JToken token in input)
            {
                JObject snapshot;
                if (!TrySanitizeSnapshot(token as JObject, out snapshot)) return false;
                string containerId = snapshot.Value<string>("containerId");
                if (byContainer.ContainsKey(containerId)) return false;
                byContainer[containerId] = snapshot;
            }
            var requested = new HashSet<string>(StringComparer.Ordinal);
            foreach (JToken token in expectedRequests)
            {
                JObject request = token as JObject;
                string containerId = request != null
                    ? request.Value<string>("containerId") : null;
                JObject snapshot;
                if (string.IsNullOrEmpty(containerId)
                    || !requested.Add(containerId)
                    || !byContainer.TryGetValue(containerId, out snapshot)
                    || !SnapshotMatchesRequest(snapshot, request)) return false;
                clean.Add(snapshot);
            }
            output = clean;
            return true;
        }

        private static bool SnapshotMatchesRequest(JObject snapshot, JObject request)
        {
            if (snapshot == null || request == null
                || snapshot.Value<string>("containerId")
                    != request.Value<string>("containerId")) return false;
            string requestedFilter = request.Value<string>("filterKey") ?? "all";
            string responseFilter = snapshot.Value<string>("filterKey") ?? "all";
            string requestedScope = request.Value<string>("scope") ?? "all";
            string responseScope = snapshot.Value<string>("scope") ?? "all";
            if (requestedFilter != responseFilter || requestedScope != responseScope)
                return false;
            JToken requestSpec = request["filterSpec"];
            JToken responseSpec = snapshot["filterSpec"];
            bool requestHasSpec = requestSpec != null && requestSpec.Type != JTokenType.Null;
            bool responseHasSpec = responseSpec != null && responseSpec.Type != JTokenType.Null;
            if (requestHasSpec != responseHasSpec
                || (requestHasSpec && !JToken.DeepEquals(requestSpec, responseSpec)))
                return false;
            int requestedOffset;
            int requestedLimit;
            if (!TryReadInteger(request["offset"], 0, int.MaxValue, out requestedOffset)
                || !TryReadInteger(request["limit"], 1, 100, out requestedLimit))
                return false;
            int viewCapacity = snapshot.Value<int>("viewCapacity");
            int expectedOffset = requestedOffset;
            if (viewCapacity <= 0) expectedOffset = 0;
            else if (expectedOffset >= viewCapacity)
                expectedOffset = ((viewCapacity - 1) / requestedLimit) * requestedLimit;
            int expectedLimit = Math.Min(
                requestedLimit,
                Math.Max(0, viewCapacity - expectedOffset));
            return snapshot.Value<int>("offset") == expectedOffset
                && snapshot.Value<int>("limit") == expectedLimit;
        }

        private static bool TrySanitizeSnapshot(JObject input, out JObject output)
        {
            output = null;
            if (!HasOnlyKeys(input,
                    "containerId", "capacity", "accessibleCapacity", "viewCapacity",
                    "filterKey", "pageSizeHint", "locked", "snapshotSeq",
                    "containerEpoch", "containerVersion", "offset", "limit", "slots",
                    "filterFacets", "filterItemCount", "setFacets", "setFilterItemCount",
                    "filterSpec", "scope")
                || !HasRequiredKeys(input,
                    "containerId", "capacity", "accessibleCapacity", "viewCapacity",
                    "filterKey", "pageSizeHint", "locked", "snapshotSeq",
                    "containerEpoch", "containerVersion", "offset", "limit", "slots",
                    "filterFacets", "filterItemCount", "setFacets", "setFilterItemCount"))
                return false;
            string containerId = input.Value<string>("containerId");
            string filterKey = input.Value<string>("filterKey");
            bool hasScope = input.Property("scope") != null;
            string scope = hasScope ? input.Value<string>("scope") : "all";
            int capacity;
            int accessible;
            int viewCapacity;
            int pageSizeHint;
            int snapshotSeq;
            int containerEpoch;
            int containerVersion;
            int offset;
            int limit;
            int filterItemCount;
            int setFilterItemCount;
            bool locked;
            if (!IsKnownContainerId(containerId)
                || !IsFilterKey(filterKey)
                || !IsProjectionScope(scope)
                || (hasScope && scope != "equipment")
                || (scope == "equipment" && containerId != "背包")
                || !TryReadInteger(input["capacity"], 1, 1200, out capacity)
                || !TryReadInteger(input["accessibleCapacity"], 0, capacity, out accessible)
                || !TryReadInteger(input["viewCapacity"], 0, accessible, out viewCapacity)
                || !TryReadInteger(input["pageSizeHint"], 1, 100, out pageSizeHint)
                || !TryReadBoolean(input["locked"], out locked)
                || locked != (accessible <= 0)
                || !TryReadInteger(input["snapshotSeq"], 1, int.MaxValue, out snapshotSeq)
                || !TryReadInteger(input["containerEpoch"], 1, int.MaxValue, out containerEpoch)
                || !TryReadInteger(input["containerVersion"], 0, int.MaxValue, out containerVersion)
                || !TryReadInteger(input["offset"], 0,
                    Math.Max(0, viewCapacity - 1), out offset)
                || !TryReadInteger(input["limit"], 0, 100, out limit)
                || (viewCapacity <= 0 && offset != 0)
                || limit > Math.Max(0, viewCapacity - offset)
                || !TryReadInteger(input["filterItemCount"], 0, accessible,
                    out filterItemCount)
                || !TryReadInteger(input["setFilterItemCount"], 0, accessible,
                    out setFilterItemCount)
                || setFilterItemCount > filterItemCount) return false;
            JObject filterSpec;
            bool hasFilterSpec = input.Property("filterSpec") != null;
            if (hasFilterSpec
                && (input["filterSpec"] == null
                    || input["filterSpec"].Type == JTokenType.Null)) return false;
            if (!TrySanitizeResponseFilterSpec(input["filterSpec"], out filterSpec))
                return false;
            if (filterSpec != null)
            {
                string major = filterSpec.Value<string>("major") ?? "all";
                if (filterSpec.Value<string>("branch") == "set")
                {
                    if (filterKey != "all") return false;
                }
                else if (!FilterSpecMatchesKey(filterKey, major)) return false;
            }
            JArray slots;
            if (!TrySanitizeSlots(
                    input["slots"] as JArray,
                    accessible,
                    offset,
                    limit,
                    filterKey,
                    filterSpec,
                    scope,
                    out slots)) return false;
            JArray facets;
            JArray setFacets;
            int facetTotal;
            int setFacetTotal;
            if (!TrySanitizeFacets(
                    input["filterFacets"] as JArray,
                    0,
                    false,
                    accessible,
                    out facets,
                    out facetTotal)
                || facetTotal != filterItemCount
                || !TrySanitizeFacets(
                    input["setFacets"] as JArray,
                    0,
                    true,
                    accessible,
                    out setFacets,
                    out setFacetTotal)
                || setFacetTotal != setFilterItemCount)
                return false;
            output = new JObject
            {
                ["containerId"] = containerId,
                ["capacity"] = capacity,
                ["accessibleCapacity"] = accessible,
                ["viewCapacity"] = viewCapacity,
                ["filterKey"] = filterKey,
                ["pageSizeHint"] = pageSizeHint,
                ["locked"] = locked,
                ["snapshotSeq"] = snapshotSeq,
                ["containerEpoch"] = containerEpoch,
                ["containerVersion"] = containerVersion,
                ["offset"] = offset,
                ["limit"] = limit,
                ["slots"] = slots,
                ["filterFacets"] = facets,
                ["filterItemCount"] = filterItemCount,
                ["setFacets"] = setFacets,
                ["setFilterItemCount"] = setFilterItemCount
            };
            if (filterSpec != null) output["filterSpec"] = filterSpec;
            if (scope != "all") output["scope"] = scope;
            return true;
        }

        private static bool TrySanitizeSlots(
            JArray input,
            int accessibleCapacity,
            int offset,
            int expectedCount,
            string filterKey,
            JObject filterSpec,
            string scope,
            out JArray output)
        {
            output = null;
            if (input == null || input.Count != expectedCount) return false;
            bool direct = scope == "all" && filterKey == "all" && filterSpec == null;
            int previous = -1;
            var seen = new HashSet<int>();
            var clean = new JArray();
            for (int index = 0; index < input.Count; index++)
            {
                JObject slot = input[index] as JObject;
                int physicalSlot;
                bool occupied;
                string lease = slot != null ? slot.Value<string>("slotLease") : null;
                if (slot == null
                    || !TryReadInteger(slot["physicalSlot"], 0,
                        Math.Max(0, accessibleCapacity - 1), out physicalSlot)
                    || accessibleCapacity <= 0
                    || !seen.Add(physicalSlot)
                    || physicalSlot <= previous
                    || (direct && physicalSlot != offset + index)
                    || !TryReadBoolean(slot["occupied"], out occupied)
                    || string.IsNullOrEmpty(lease)
                    || !ValidLease.IsMatch(lease)) return false;
                previous = physicalSlot;
                if (!occupied)
                {
                    if (!HasExactKeys(
                            slot, "physicalSlot", "occupied", "slotLease")) return false;
                    clean.Add(new JObject
                    {
                        ["physicalSlot"] = physicalSlot,
                        ["occupied"] = false,
                        ["slotLease"] = lease
                    });
                    continue;
                }
                if (!HasExactKeys(slot,
                        "physicalSlot", "occupied", "slotLease", "item",
                        "confirmProjection")) return false;
                JObject item;
                JObject confirm;
                if (!TrySanitizeItem(slot["item"] as JObject, out item)
                    || !TrySanitizeConfirm(
                        slot["confirmProjection"] as JObject, item, out confirm))
                    return false;
                clean.Add(new JObject
                {
                    ["physicalSlot"] = physicalSlot,
                    ["occupied"] = true,
                    ["slotLease"] = lease,
                    ["item"] = item,
                    ["confirmProjection"] = confirm
                });
            }
            output = clean;
            return true;
        }

        internal static bool TrySanitizeItem(JObject input, out JObject output)
        {
            output = null;
            if (!HasOnlyKeys(input,
                    "name", "displayName", "icon", "majorType", "use", "actionType",
                    "weaponType", "setId", "setName", "setOrder", "itemKind",
                    "quantity", "enhancementLevel", "maxEnhancementLevel",
                    "isMaxEnhancement", "tierSlotAvailable", "tierSlotUsed",
                    "modSlotCapacity", "modSlotUsed", "modSlots", "modMeta", "rarity",
                    "balanceSummary")
                || !HasRequiredKeys(input,
                    "name", "displayName", "icon", "majorType", "use", "actionType",
                    "weaponType", "setId", "setName", "setOrder", "itemKind",
                    "quantity", "enhancementLevel", "maxEnhancementLevel",
                    "isMaxEnhancement", "tierSlotAvailable", "tierSlotUsed",
                    "modSlotCapacity", "modSlotUsed", "modSlots", "modMeta", "rarity"))
                return false;
            var clean = new JObject();
            string[] requiredIdentityFields =
            {
                "name", "displayName", "icon"
            };
            foreach (string field in requiredIdentityFields)
            {
                if (!IsStrictIdentityProjectionText(input[field], 256)) return false;
                clean[field] = input.Value<string>(field);
            }
            string[] optionalTextFields =
            {
                "majorType", "use", "actionType", "weaponType",
                "setId", "setName", "rarity"
            };
            foreach (string field in optionalTextFields)
            {
                int maximumLength = field == "use" ? 64 : 256;
                if (!IsStrictProjectionText(input[field], maximumLength, true)) return false;
                clean[field] = input.Value<string>(field);
            }
            string itemKind = input.Value<string>("itemKind");
            if (itemKind != "equipment" && itemKind != "stack") return false;
            clean["itemKind"] = itemKind;
            int setOrder;
            int enhancementLevel;
            int maxEnhancementLevel;
            int modSlotCapacity;
            int modSlotUsed;
            long quantity;
            bool isMaxEnhancement;
            bool tierSlotAvailable;
            bool tierSlotUsed;
            if (!TryReadInteger(input["setOrder"], 0, int.MaxValue, out setOrder)
                || !TryReadLongInteger(input["quantity"], 0, 9007199254740991L,
                    out quantity)
                || !TryReadInteger(input["enhancementLevel"], 0, int.MaxValue,
                    out enhancementLevel)
                || !TryReadInteger(input["maxEnhancementLevel"], 0, int.MaxValue,
                    out maxEnhancementLevel)
                || !TryReadBoolean(input["isMaxEnhancement"], out isMaxEnhancement)
                || !TryReadBoolean(input["tierSlotAvailable"], out tierSlotAvailable)
                || !TryReadBoolean(input["tierSlotUsed"], out tierSlotUsed)
                || !TryReadInteger(input["modSlotCapacity"], 0, int.MaxValue,
                    out modSlotCapacity)
                || !TryReadInteger(input["modSlotUsed"], 0, int.MaxValue,
                    out modSlotUsed)
                || (tierSlotUsed && !tierSlotAvailable)
                || isMaxEnhancement != (itemKind == "equipment"
                    && enhancementLevel >= maxEnhancementLevel)
                || (itemKind == "equipment" && quantity != 1)
                || (itemKind == "stack"
                    && (quantity <= 0
                        || enhancementLevel != 0
                        || isMaxEnhancement
                        || tierSlotAvailable
                        || tierSlotUsed
                        || modSlotCapacity != 0
                        || modSlotUsed != 0))) return false;
            clean["setOrder"] = setOrder;
            clean["quantity"] = quantity;
            clean["enhancementLevel"] = enhancementLevel;
            clean["maxEnhancementLevel"] = maxEnhancementLevel;
            clean["isMaxEnhancement"] = isMaxEnhancement;
            clean["tierSlotAvailable"] = tierSlotAvailable;
            clean["tierSlotUsed"] = tierSlotUsed;
            clean["modSlotCapacity"] = modSlotCapacity;
            clean["modSlotUsed"] = modSlotUsed;
            JArray mods;
            if (!TrySanitizeMods(input["modSlots"] as JArray, out mods)) return false;
            if (mods.Count > modSlotUsed
                || (itemKind == "stack" && mods.Count != 0)) return false;
            clean["modSlots"] = mods;
            if (input["modMeta"] == null || input["modMeta"].Type == JTokenType.Null)
            {
                clean["modMeta"] = JValue.CreateNull();
            }
            else
            {
                JObject modMeta;
                if (!TrySanitizeMod(input["modMeta"] as JObject, out modMeta)) return false;
                clean["modMeta"] = modMeta;
            }
            if (input.Property("balanceSummary") != null)
            {
                JObject balance;
                if (!TrySanitizeBalanceSummary(
                        input["balanceSummary"] as JObject, out balance)) return false;
                clean["balanceSummary"] = balance;
            }
            output = clean;
            return true;
        }

        internal static bool TrySanitizeConfirm(
            JObject input,
            JObject item,
            out JObject output)
        {
            return TrySanitizeConfirmCore(input, item, true, out output);
        }

        internal static bool TrySanitizeStableConfirm(
            JObject input,
            JObject item,
            out JObject output)
        {
            return TrySanitizeConfirmCore(input, item, false, out output);
        }

        private static bool TrySanitizeConfirmCore(
            JObject input,
            JObject item,
            bool withLastUpdate,
            out JObject output)
        {
            output = null;
            string[] expectedKeys = withLastUpdate
                ? new[] { "itemKind", "name", "displayName", "quantity",
                    "enhancementLevel", "rarity", "tier", "modSignature", "lastUpdate" }
                : new[] { "itemKind", "name", "displayName", "quantity",
                    "enhancementLevel", "rarity", "tier", "modSignature" };
            if (!HasExactKeys(input, expectedKeys))
                return false;
            string[] textFields =
            {
                "itemKind", "name", "displayName", "rarity", "tier", "modSignature"
            };
            foreach (string field in textFields)
            {
                if (!IsStrictProjectionText(input[field], field == "modSignature" ? 1024 : 256,
                        true)) return false;
            }
            long quantity;
            int enhancementLevel;
            long lastUpdate = 0;
            if (!TryReadLongInteger(input["quantity"], 0, 9007199254740991L,
                    out quantity)
                || !TryReadInteger(input["enhancementLevel"], 0, int.MaxValue,
                    out enhancementLevel)
                || (withLastUpdate && !TryReadLongInteger(
                    input["lastUpdate"], 0, 9007199254740991L, out lastUpdate))
                || input.Value<string>("itemKind") != item.Value<string>("itemKind")
                || input.Value<string>("name") != item.Value<string>("name")
                || input.Value<string>("displayName") != item.Value<string>("displayName")
                || input.Value<string>("rarity") != item.Value<string>("rarity")
                || quantity != item.Value<long>("quantity")
                || enhancementLevel != item.Value<int>("enhancementLevel")) return false;
            var clean = new JObject
            {
                ["itemKind"] = input.Value<string>("itemKind"),
                ["name"] = input.Value<string>("name"),
                ["displayName"] = input.Value<string>("displayName"),
                ["quantity"] = quantity,
                ["enhancementLevel"] = enhancementLevel,
                ["rarity"] = input.Value<string>("rarity"),
                ["tier"] = input.Value<string>("tier"),
                ["modSignature"] = input.Value<string>("modSignature")
            };
            if (withLastUpdate) clean["lastUpdate"] = lastUpdate;
            output = clean;
            return true;
        }

        private static bool TrySanitizeMods(JArray input, out JArray output)
        {
            output = null;
            if (input == null || input.Count > 3) return false;
            var clean = new JArray();
            foreach (JToken token in input)
            {
                JObject mod;
                if (!TrySanitizeMod(token as JObject, out mod)) return false;
                clean.Add(mod);
            }
            output = clean;
            return true;
        }

        private static bool TrySanitizeMod(JObject input, out JObject output)
        {
            output = null;
            string[] fields =
            {
                "name", "displayName", "icon", "grade", "gradeLabel", "gradeColor",
                "role", "roleLabel", "symbol", "scope"
            };
            if (!HasExactKeys(input, fields)) return false;
            var clean = new JObject();
            foreach (string field in fields)
            {
                bool identity = field == "name" || field == "displayName" || field == "icon";
                if (identity
                    ? !IsStrictIdentityProjectionText(input[field], 256)
                    : !IsStrictProjectionText(input[field], 128, true)) return false;
                clean[field] = input.Value<string>(field);
            }
            output = clean;
            return true;
        }

        private static bool TrySanitizeBalanceSummary(
            JObject input,
            out JObject output)
        {
            output = null;
            int weightLayers;
            int formula;
            int level;
            if (!HasExactKeys(input, "state", "weightLayers", "formula", "level")
                || !HasExactString(input["state"], "confirmed")
                || !TryReadInteger(input["weightLayers"], -100000, 100000,
                    out weightLayers)
                || !TryReadInteger(input["formula"], 1, 1, out formula)
                || !TryReadInteger(input["level"], 0, int.MaxValue, out level))
                return false;
            output = new JObject
            {
                ["state"] = "confirmed",
                ["weightLayers"] = weightLayers,
                ["formula"] = formula,
                ["level"] = level
            };
            return true;
        }

        private static bool TrySanitizeFacets(
            JArray input,
            int depth,
            bool sets,
            int maximumCount,
            out JArray output,
            out int total)
        {
            output = null;
            total = 0;
            if (input == null || input.Count > 64 || depth > 2) return false;
            var clean = new JArray();
            var ids = new HashSet<string>(StringComparer.Ordinal);
            foreach (JToken token in input)
            {
                JObject node = token as JObject;
                int order;
                int count;
                JArray children;
                if (!HasExactKeys(node, "id", "label", "order", "count", "children")
                    || !IsStrictProjectionText(node["id"], 128, false)
                    || !ids.Add(node.Value<string>("id"))
                    || !IsStrictProjectionText(node["label"], 128, false)
                    || !TryReadInteger(node["order"], -1000000, 1000000, out order)
                    || !TryReadInteger(node["count"], 0, maximumCount, out count))
                    return false;
                JArray inputChildren = node["children"] as JArray;
                int childTotal;
                if (sets)
                {
                    if (inputChildren == null || inputChildren.Count != 0) return false;
                    children = new JArray();
                    childTotal = 0;
                }
                else
                {
                    if (inputChildren == null) return false;
                    if (inputChildren.Count == 0)
                    {
                        children = new JArray();
                        childTotal = 0;
                    }
                    else if (depth >= 2
                        || !TrySanitizeFacets(
                            inputChildren,
                            depth + 1,
                            false,
                            maximumCount,
                            out children,
                            out childTotal)
                        || childTotal > count) return false;
                }
                if (count > maximumCount - total) return false;
                total += count;
                clean.Add(new JObject
                {
                    ["id"] = node.Value<string>("id"),
                    ["label"] = node.Value<string>("label"),
                    ["order"] = order,
                    ["count"] = count,
                    ["children"] = children
                });
            }
            output = clean;
            return true;
        }

        private static bool TrySanitizeResponseFilterSpec(
            JToken token,
            out JObject output)
        {
            output = null;
            if (token == null || token.Type == JTokenType.Null) return true;
            JObject input = token as JObject;
            if (input == null) return false;
            if (input.Value<string>("branch") == "set")
            {
                if (!HasOnlyKeys(input, "branch", "setId")
                    || !HasRequiredKeys(input, "branch")
                    || (input.Property("setId") != null
                        && !IsStrictProjectionText(input["setId"], 64, false))) return false;
                output = new JObject { ["branch"] = "set" };
                if (input.Property("setId") != null)
                    output["setId"] = input.Value<string>("setId");
                return true;
            }
            if (!HasOnlyKeys(input, "branch", "major", "use", "subtype")
                || !HasRequiredKeys(input, "major")
                || (input.Property("branch") != null
                    && !HasExactString(input["branch"], "category"))
                || !IsStrictProjectionText(input["major"], 64, false)
                || !IsFilterMajor(input.Value<string>("major"))
                || (input.Property("use") != null
                    && !IsStrictProjectionText(input["use"], 64, false))
                || (input.Property("subtype") != null
                    && !IsStrictProjectionText(input["subtype"], 64, false))) return false;
            string major = input.Value<string>("major");
            string use = input.Value<string>("use") ?? string.Empty;
            string subtype = input.Value<string>("subtype") ?? string.Empty;
            if ((major == "all" && (use.Length > 0 || subtype.Length > 0))
                || (subtype.Length > 0 && (major != "weapon" || use.Length == 0)))
                return false;
            output = new JObject { ["major"] = major };
            if (input.Property("branch") != null) output["branch"] = "category";
            if (input.Property("use") != null) output["use"] = use;
            if (input.Property("subtype") != null) output["subtype"] = subtype;
            return true;
        }

        private static bool TryNormalizeCharacterTooltipResponse(
            JObject message,
            int backendCallId,
            out JObject normalized)
        {
            normalized = null;
            if (message == null
                || !HasExactString(message["task"], "inventory_response")
                || !HasExactInteger(message["callId"], backendCallId)
                || message["success"] == null
                || message["success"].Type != JTokenType.Boolean)
            {
                return false;
            }

            bool success = message.Value<bool>("success");
            if (!success)
            {
                if (!HasExactKeys(
                        message,
                        "task", "callId", "success", "error")
                    || !IsBoundedText(message["error"], 64, false))
                {
                    return false;
                }
                string error = message.Value<string>("error");
                if (!CharacterTooltipErrors.Contains(error)) return false;
                normalized = new JObject
                {
                    ["success"] = false,
                    ["error"] = error
                };
                return true;
            }

            if (!HasExactKeys(
                    message,
                    "task", "callId", "success", "v", "itemName",
                    "displayname", "iconName", "itemType", "descHTML",
                    "introHTML")
                || !HasExactInteger(message["v"], 1)
                || !IsBoundedText(message["itemName"], 256, true)
                || !IsBoundedText(message["displayname"], 256, true)
                || !IsBoundedText(message["iconName"], 256, true)
                || !IsBoundedText(message["itemType"], 128, true)
                || !IsBoundedText(message["descHTML"], 131072, true)
                || !IsBoundedText(message["introHTML"], 131072, true))
            {
                return false;
            }

            normalized = new JObject
            {
                ["success"] = true,
                ["v"] = 1,
                ["itemName"] = message.Value<string>("itemName"),
                ["displayname"] = message.Value<string>("displayname"),
                ["iconName"] = message.Value<string>("iconName"),
                ["itemType"] = message.Value<string>("itemType"),
                ["descHTML"] = message.Value<string>("descHTML"),
                ["introHTML"] = message.Value<string>("introHTML")
            };
            return true;
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

        private static bool HasRequiredKeys(JObject value, params string[] required)
        {
            if (value == null) return false;
            for (int i = 0; i < required.Length; i++)
            {
                if (value.Property(required[i]) == null) return false;
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
            if (token == null || token.Type != JTokenType.Integer) return false;
            try { return token.ToObject<long>() == expected; }
            catch { return false; }
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
            try { candidate = token.ToObject<long>(); }
            catch { return false; }
            if (candidate < minimum || candidate > maximum) return false;
            value = (int)candidate;
            return true;
        }

        private static bool TryReadLongInteger(
            JToken token,
            long minimum,
            long maximum,
            out long value)
        {
            value = 0;
            if (token == null || token.Type != JTokenType.Integer) return false;
            try { value = token.ToObject<long>(); }
            catch { return false; }
            return value >= minimum && value <= maximum;
        }

        private static bool TryReadBoolean(JToken token, out bool value)
        {
            value = false;
            if (token == null || token.Type != JTokenType.Boolean) return false;
            value = token.Value<bool>();
            return true;
        }

        private static bool IsStrictProjectionText(
            JToken token,
            int maxLength,
            bool allowEmpty)
        {
            if (token == null || token.Type != JTokenType.String) return false;
            string value = token.Value<string>();
            if (value == null || value.Length > maxLength
                || (!allowEmpty && value.Length == 0)) return false;
            for (int i = 0; i < value.Length; i++)
            {
                char current = value[i];
                if (current <= '\u001f' || current == '\u007f') return false;
            }
            return true;
        }

        private static bool IsStrictIdentityProjectionText(
            JToken token,
            int maxLength)
        {
            if (!IsStrictProjectionText(token, maxLength, false)) return false;
            string value = token.Value<string>();
            return !string.IsNullOrWhiteSpace(value)
                && !string.Equals(
                    value.Trim(), "undefined", StringComparison.OrdinalIgnoreCase);
        }

        private static bool IsBoundedText(
            JToken token,
            int maxLength,
            bool allowEmpty)
        {
            if (token == null || token.Type != JTokenType.String) return false;
            string value = token.Value<string>();
            if (value == null || value.Length > maxLength
                || (!allowEmpty && value.Length == 0)) return false;
            for (int i = 0; i < value.Length; i++)
            {
                char current = value[i];
                if (char.IsControl(current)
                    && current != '\r' && current != '\n' && current != '\t')
                {
                    return false;
                }
            }
            return true;
        }

        private void HandleTimeout(int fid)
        {
            if (_disposed) return;
            PendingRequest entry;
            lock (_lock)
            {
                if (!_pending.TryGetValue(fid, out entry)) return;
                CompletePendingLocked(fid, entry);
                if (entry.IsWrite && _writeOwnerFid == fid)
                    EnterNeedsReconcileLocked(entry.AffectedContainers);
            }
            RespondError(entry.WebCallId, entry.WebCmd,
                PendingError(entry, "timeout"),
                entry.WebPanel, entry.WebPanelInstanceId,
                entry.IsWrite);
        }

        private void HandleSendFailure(int fid)
        {
            PendingRequest entry;
            lock (_lock)
            {
                if (!_pending.TryGetValue(fid, out entry)) return;
                CompletePendingLocked(fid, entry);
                if (entry.IsWrite && _writeOwnerFid == fid)
                    EnterNeedsReconcileLocked(entry.AffectedContainers);
            }
            RespondError(entry.WebCallId, entry.WebCmd,
                PendingError(entry, "disconnected"),
                entry.WebPanel, entry.WebPanelInstanceId,
                entry.IsWrite);
        }

        private void CompletePendingLocked(int fid, PendingRequest entry)
        {
            _navigationGeneration++;
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

        private void EnterNeedsReconcileLocked(IEnumerable<string> affectedContainers)
        {
            var frozenAffected = new HashSet<string>(StringComparer.Ordinal);
            IEnumerable<string> source = affectedContainers
                ?? _writeAffectedContainers;
            foreach (string containerId in source)
            {
                if (!string.IsNullOrEmpty(containerId))
                    frozenAffected.Add(containerId);
            }
            _writeGate = WriteGateState.NeedsReconcile;
            _writeOwnerFid = 0;
            _reconcileEpoch++;
            _writeAffectedContainers.Clear();
            _reconcileContainers.Clear();
            foreach (string containerId in frozenAffected)
                _reconcileContainers.Add(containerId);
        }

        private void RejectAndRemember(string webCallId, string cmd, string error,
            string webPanel, string webPanelInstanceId)
        {
            string responseError = error;
            lock (_lock)
            {
                if (_navigationLeaseToken != null)
                    responseError = "busy";
                else
                {
                    if (_activeWebCallIds.Contains(webCallId)
                        || _recentWebCallIds.Contains(webCallId)) return;
                    RememberRecentLocked(webCallId);
                }
            }
            RespondError(
                webCallId,
                cmd,
                responseError,
                webPanel,
                webPanelInstanceId);
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

        private void RespondError(string webCallId, string cmd, string error,
            string webPanel, string webPanelInstanceId,
            bool requiresReconcile = false)
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
            if (requiresReconcile) response["requiresReconcile"] = true;
            if (!string.IsNullOrEmpty(webPanel)) response["panel"] = webPanel;
            if (!string.IsNullOrEmpty(webPanelInstanceId))
                response["panelInstanceId"] = webPanelInstanceId;
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
