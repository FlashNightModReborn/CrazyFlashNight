using System;
using System.Collections.Generic;
using System.Threading;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using CF7Launcher.Bus;
using CF7Launcher.Guardian;

namespace CF7Launcher.Tasks
{
    /// <summary>
    /// Strict Web↔AS2 transport for an AS2-authoritative transient loot container. The Host owns
    /// routing, panel-instance binding, duplicate suppression, and unknown-write reconciliation;
    /// it never owns or logs reward descriptors.
    /// </summary>
    public sealed class LootTask : IDisposable
    {
        private sealed class PendingRequest
        {
            public int FlashCallId;
            public string WebCallId;
            public string WebCmd;
            public string OperationId;
            public bool IsWrite;
            public bool HasKnownClaimPrestate;
            public int ClaimAuthorityRevisionBefore;
            public int ClaimRemainingBefore;
            public int ClaimPhysicalSlot;
            public string ClaimSourceLease;
            public int[] ClaimBatchPhysicalSlots;
            public string[] ClaimBatchSourceLeases;
            public int ClaimSourceContainerVersion;
            public string ClaimLastAppliedOperationIdBefore;
            public string ClaimCloseLeaseBefore;
            public bool CloseAbandon;
            public string CloseLease;
            public bool HasKnownClosePrestate;
            public int CloseAuthorityRevisionBefore;
            public int CloseRemainingBefore;
            public string CloseLastAppliedOperationIdBefore;
            public int CloseLootContainerVersionBefore;
            public bool IsDetachedReconcile;
            public int ReconcileEpoch;
            public int TransportGeneration;
            public string RecoveryNonce;
            public bool IsSocketDetachProof;
            public int ExpectedAuthorityRevision;
            public LootPanelCoordinator.Binding Binding;
        }

        private sealed class PanelAdmissionLease : IDisposable
        {
            private object _sync;

            public PanelAdmissionLease(object sync) { _sync = sync; }

            public void Dispose()
            {
                object sync = _sync;
                if (sync == null) return;
                _sync = null;
                Monitor.Exit(sync);
            }
        }

        private const int DefaultTimeoutMs = 10000;
        private const int MaxPending = 8;
        private const int RecentCallIdCapacity = 256;
        private const int MaxSnapshotSlots = 100;
        private const long MaxSafeInteger = 9007199254740991L;
        private const int DefaultDetachedReconcileRetryInitialMs = 100;
        private const int DefaultDetachedReconcileRetryMaximumMs = 2000;

        private static readonly HashSet<string> CommonRequestKeys = Set(
            "type", "task", "domain", "panel", "v", "cmd", "callId", "panelInstanceId",
            "chestSessionId", "lootContainerId", "containerEpoch");
        private static readonly HashSet<string> ResponseKeys = Set(
            "task", "callId", "success", "error", "chestSessionId", "lootContainerId",
            "containerEpoch", "authorityRevision", "lastAppliedOperationId", "state",
            "remainingCount", "closeLease", "snapshots", "tooltip", "materials", "terminal");
        private static readonly HashSet<string> MaterialKeys = Set(
            "name", "displayName", "icon", "owned");
        private static readonly HashSet<string> SnapshotKeys = Set(
            "containerId", "capacity", "accessibleCapacity", "viewCapacity", "filterKey",
            "pageSizeHint", "locked", "snapshotSeq", "containerEpoch", "containerVersion",
            "offset", "limit", "slots", "filterFacets", "filterItemCount", "setFacets",
            "setFilterItemCount", "filterSpec");
        private static readonly HashSet<string> SnapshotRequiredKeys = Set(
            "containerId", "capacity", "accessibleCapacity", "viewCapacity", "filterKey",
            "pageSizeHint", "locked", "snapshotSeq", "containerEpoch", "containerVersion",
            "offset", "limit", "slots", "filterFacets", "filterItemCount", "setFacets",
            "setFilterItemCount");
        private static readonly HashSet<string> ItemKeys = Set(
            "name", "displayName", "icon", "majorType", "use", "actionType", "weaponType",
            "setId", "setName", "setOrder", "itemKind", "quantity", "enhancementLevel",
            "maxEnhancementLevel", "isMaxEnhancement", "tierSlotAvailable", "tierSlotUsed",
            "modSlotCapacity", "modSlotUsed", "modSlots", "modMeta", "rarity");
        private static readonly HashSet<string> ConfirmKeys = Set(
            "itemKind", "name", "displayName", "quantity", "enhancementLevel", "rarity",
            "tier", "modSignature", "lastUpdate");
        private static readonly HashSet<string> ModKeys = Set(
            "name", "displayName", "icon", "grade", "gradeLabel", "gradeColor",
            "role", "roleLabel", "symbol", "scope");
        private static readonly HashSet<string> States = Set(
            "LOOT_COMMIT_PENDING", "LOOT_ACTIVE", "LOOT_SUSPENDED",
            "CONSUMED", "ABANDONED", "EXPIRED");

        private readonly object _sync = new object();
        private readonly Func<bool> _isClientReady;
        private readonly Func<string, bool> _trySend;
        private readonly Func<int> _getReadyGeneration;
        private readonly Func<string, int, bool> _trySendIfGeneration;
        private readonly LootPanelCoordinator _coordinator;
        private readonly int _timeoutMs;
        private readonly int _detachedReconcileRetryInitialMs;
        private readonly int _detachedReconcileRetryMaximumMs;
        private readonly Dictionary<int, PendingRequest> _pending =
            new Dictionary<int, PendingRequest>();
        private readonly Dictionary<int, Timer> _timers = new Dictionary<int, Timer>();
        private readonly HashSet<string> _activeCallIds = new HashSet<string>(StringComparer.Ordinal);
        private readonly HashSet<string> _recentCallIds = new HashSet<string>(StringComparer.Ordinal);
        private readonly Queue<string> _recentCallIdOrder = new Queue<string>();

        private Action<string> _postToWeb;
        private Action<Action> _invokeOnUI;
        private Action _detachedReconcileSettled;
        private int _sequence;
        private string _writeState = "idle";
        private string _unknownOperationId;
        private string _unknownChestSessionId;
        private string _unknownLootContainerId;
        private int _unknownContainerEpoch;
        private int _unknownOpenAttemptSeq;
        private int _unknownExpectedAuthorityRevision;
        private int _unknownFreshnessWatermark;
        private bool _unknownRequiresCausalCompletion;
        private string _unknownWebCmd;
        private bool _unknownCloseAbandon;
        private bool _unknownHasKnownClosePrestate;
        private int _unknownCloseAuthorityRevisionBefore;
        private int _unknownCloseRemainingBefore;
        private string _unknownCloseLastAppliedOperationIdBefore;
        private string _unknownCloseLease;
        private int _unknownCloseLootContainerVersionBefore;
        private bool _unknownHasKnownClaimPrestate;
        private int _unknownClaimAuthorityRevisionBefore;
        private int _unknownClaimRemainingBefore;
        private int _unknownClaimPhysicalSlot;
        private string _unknownClaimSourceLease;
        private int[] _unknownClaimBatchPhysicalSlots;
        private string[] _unknownClaimBatchSourceLeases;
        private int _unknownClaimSourceContainerVersion;
        private string _unknownClaimLastAppliedOperationIdBefore;
        private string _unknownClaimCloseLeaseBefore;
        private int _lastAuthorityRevision;
        private string _revisionChestSessionId;
        private string _revisionLootContainerId;
        private int _revisionContainerEpoch;
        private int _revisionOpenAttemptSeq;
        private string _knownAuthorityState = "LOOT_COMMIT_PENDING";
        private int _knownRemainingCount;
        private string _knownCloseLease = "";
        private string _knownLastAppliedOperationId = "";
        private int _knownLootContainerVersion = -1;
        private JObject _knownTerminal;
        private LootPanelCoordinator.Binding _knownAuthorityBinding;
        private LootPanelCoordinator.Binding _unknownBinding;
        private LootPanelCoordinator.Binding _authorityVisualCloseProofBinding;
        private LootPanelCoordinator.Binding _detachedReconcileBinding;
        private bool _detachedReconcileRequired;
        private int _detachedReconcileExpectedAuthorityRevision;
        private Timer _detachedReconcileRetryTimer;
        private int _detachedReconcileEpoch;
        private int _detachedReconcileTransportGeneration;
        private int _detachedReconcileRetryAttempt;
        private string _detachedReconcileRecoveryNonce;
        private bool _detachedReconcileSocketMode;
        private int _lastSocketDetachGeneration;
        private volatile bool _disposed;

        public LootTask(XmlSocketServer socket, LootPanelCoordinator coordinator)
            : this(delegate { return socket != null && socket.IsClientReady; },
                delegate(string payload) { return socket != null && socket.TrySend(payload); },
                coordinator, DefaultTimeoutMs,
                delegate
                {
                    int generation;
                    return socket != null && socket.TryGetReadyGeneration(out generation)
                        ? generation : 0;
                },
                delegate(string payload, int generation)
                {
                    return socket != null && socket.TrySendIfGen(payload, generation);
                })
        {
        }

        public LootTask(Func<bool> isClientReady, Func<string, bool> trySend,
            LootPanelCoordinator coordinator, int timeoutMs = DefaultTimeoutMs,
            Func<int> getReadyGeneration = null,
            Func<string, int, bool> trySendIfGeneration = null,
            int detachedReconcileRetryInitialMs = DefaultDetachedReconcileRetryInitialMs,
            int detachedReconcileRetryMaximumMs = DefaultDetachedReconcileRetryMaximumMs)
        {
            _isClientReady = isClientReady ?? delegate { return false; };
            _trySend = trySend ?? delegate { return false; };
            _getReadyGeneration = getReadyGeneration
                ?? delegate { return _isClientReady() ? 1 : 0; };
            _trySendIfGeneration = trySendIfGeneration
                ?? delegate(string payload, int generation)
                {
                    return generation > 0 && generation == SafeReadyGeneration()
                        && _trySend(payload);
                };
            _coordinator = coordinator ?? throw new ArgumentNullException(nameof(coordinator));
            _timeoutMs = Math.Max(1, timeoutMs);
            _detachedReconcileRetryInitialMs = Math.Max(1,
                detachedReconcileRetryInitialMs);
            _detachedReconcileRetryMaximumMs = Math.Max(
                _detachedReconcileRetryInitialMs, detachedReconcileRetryMaximumMs);
            _coordinator.BindingDetached += OnBindingDetached;
        }

        public void SetPostToWeb(Action<string> post) { _postToWeb = post; }
        public void SetInvoker(Action<Action> invoker) { _invokeOnUI = invoker; }
        public void SetDetachedReconcileSettled(Action settled)
        {
            _detachedReconcileSettled = settled;
        }

        internal int PendingCount { get { lock (_sync) return _pending.Count; } }
        internal string WriteState { get { lock (_sync) return _writeState; } }
        internal string UnknownOperationId { get { lock (_sync) return _unknownOperationId; } }
        internal int LastAuthorityRevision { get { lock (_sync) return _lastAuthorityRevision; } }
        internal bool RequiresDetachedReconcile
        {
            get { lock (_sync) return _detachedReconcileRequired; }
        }
        internal bool HasRecoveryFence
        {
            get { lock (_sync) return HasRecoveryFenceLocked(); }
        }

        internal IDisposable TryAcquirePanelAdmissionLease()
        {
            Monitor.Enter(_sync);
            if (_disposed || HasRecoveryFenceLocked())
            {
                Monitor.Exit(_sync);
                return null;
            }
            return new PanelAdmissionLease(_sync);
        }

        private bool HasRecoveryFenceLocked()
        {
            if (_writeState != "idle" || _unknownBinding != null
                || _detachedReconcileRequired) return true;
            foreach (PendingRequest entry in _pending.Values)
                if (entry.IsWrite || entry.IsDetachedReconcile) return true;
            return false;
        }

        internal bool IsAuthorityVisualCloseProvenExact(
            LootPanelCoordinator.Binding binding)
        {
            lock (_sync)
                return binding != null
                    && ReferenceEquals(_authorityVisualCloseProofBinding, binding);
        }

        public void HandleWebRequest(JObject parsed)
        {
            if (_disposed || parsed == null) return;
            string cmd = ReadString(parsed["cmd"]);
            string webCallId = ReadString(parsed["callId"]);
            string panelInstanceId = ReadString(parsed["panelInstanceId"]);
            string chestSessionId = ReadString(parsed["chestSessionId"]);
            string lootContainerId = ReadString(parsed["lootContainerId"]);
            int containerEpoch;

            if (!IsCallId(webCallId) || !TryReadInteger(parsed["containerEpoch"], 1,
                    int.MaxValue, out containerEpoch))
            {
                return;
            }

            LootPanelCoordinator.Binding binding;
            if (!_coordinator.TryBindExact(panelInstanceId, chestSessionId, lootContainerId,
                    containerEpoch, out binding))
            {
                // A stale document never receives data about the replacement binding.
                return;
            }

            string action;
            bool isWrite;
            if (!TryResolveCommand(cmd, out action, out isWrite))
            {
                RejectAndRemember(binding, webCallId, cmd, "unsupported_cmd");
                return;
            }

            JObject normalized;
            string operationId;
            int expectedRevision;
            if (!TryNormalizeRequest(parsed, binding, cmd, out normalized, out operationId,
                    out expectedRevision))
            {
                RejectAndRemember(binding, webCallId, cmd, "invalid_payload");
                return;
            }
            if (!_isClientReady())
            {
                RejectAndRemember(binding, webCallId, cmd, "disconnected");
                return;
            }

            PendingRequest entry = new PendingRequest
            {
                WebCallId = webCallId,
                WebCmd = cmd,
                OperationId = operationId,
                IsWrite = isWrite,
                ClaimPhysicalSlot = cmd == "claim"
                    ? normalized["source"].Value<int>("slot") : -1,
                ClaimSourceLease = cmd == "claim"
                    ? normalized["source"].Value<string>("expectedLease") : null,
                ClaimSourceContainerVersion = cmd == "claim"
                    ? normalized["source"].Value<int>("expectedContainerVersion") : -1,
                CloseAbandon = cmd == "close" && normalized.Value<bool>("abandon"),
                CloseLease = cmd == "close" ? normalized.Value<string>("closeLease") : null,
                ExpectedAuthorityRevision = expectedRevision,
                Binding = binding
            };
            if (cmd == "claimBatch")
            {
                JArray sources = normalized["sources"] as JArray;
                entry.ClaimBatchPhysicalSlots = new int[sources.Count];
                entry.ClaimBatchSourceLeases = new string[sources.Count];
                for (int sourceIndex = 0; sourceIndex < sources.Count; sourceIndex++)
                {
                    entry.ClaimBatchPhysicalSlots[sourceIndex] =
                        sources[sourceIndex].Value<int>("slot");
                    entry.ClaimBatchSourceLeases[sourceIndex] =
                        sources[sourceIndex].Value<string>("expectedLease");
                }
                entry.ClaimSourceContainerVersion =
                    sources[0].Value<int>("expectedContainerVersion");
            }
            string rejection = null;
            lock (_sync)
            {
                if (_activeCallIds.Contains(webCallId) || _recentCallIds.Contains(webCallId)) return;
                bool sameRevisionIdentity = BindingIdentityMatchesRevisionLocked(binding);
                bool sameUnknownIdentity = string.Equals(_unknownChestSessionId,
                        binding.ChestSessionId, StringComparison.Ordinal)
                    && string.Equals(_unknownLootContainerId, binding.LootContainerId,
                        StringComparison.Ordinal)
                    && _unknownContainerEpoch == binding.ContainerEpoch
                    && _unknownOpenAttemptSeq == binding.OpenAttemptSeq;
                bool sameDetachedIdentity = _detachedReconcileBinding != null
                    && BindingIdentityMatches(_detachedReconcileBinding, binding);
                if (_detachedReconcileRequired)
                    rejection = sameDetachedIdentity ? "reconcile_required" : "flow_busy";
                else if (_writeState == "reconcile_required" && !sameUnknownIdentity)
                    rejection = "flow_busy";
                else if (!sameRevisionIdentity && (_pending.Count != 0 || _writeState != "idle"))
                    rejection = "flow_busy";
                else if (!sameRevisionIdentity)
                {
                    ActivateRevisionScopeLocked(binding);
                }
                if (rejection == null && _pending.Count >= MaxPending) rejection = "busy";
                if (rejection == null && !_coordinator.IsCurrentExact(binding))
                    rejection = "panel_instance_expired";
                if (rejection == null && cmd == "query")
                {
                    if (_writeState == "write_pending") rejection = "busy";
                }
                else if (rejection == null && isWrite)
                {
                    if (_writeState == "write_pending") rejection = "busy";
                    else if (_writeState == "reconcile_required") rejection = "reconcile_required";
                    else
                    {
                        if (cmd == "claim" || cmd == "claimBatch")
                        {
                            int requestedClaims = cmd == "claimBatch"
                                ? entry.ClaimBatchPhysicalSlots.Length : 1;
                            bool exactClaimPrestate = ReferenceEquals(
                                    _knownAuthorityBinding, binding)
                                && _coordinator.IsCurrentExact(binding)
                                && _knownAuthorityState == "LOOT_ACTIVE"
                                && _lastAuthorityRevision == entry.ExpectedAuthorityRevision
                                && LootPanelCoordinator.IsOpaque(_knownCloseLease)
                                && _knownLootContainerVersion >= 0
                                && entry.ClaimSourceContainerVersion
                                    == _knownLootContainerVersion
                                && requestedClaims > 0
                                && requestedClaims <= _knownRemainingCount;
                            if (!exactClaimPrestate) rejection = "stale_state";
                            else
                            {
                                entry.HasKnownClaimPrestate = true;
                                entry.ClaimAuthorityRevisionBefore = _lastAuthorityRevision;
                                entry.ClaimRemainingBefore = _knownRemainingCount;
                                entry.ClaimLastAppliedOperationIdBefore =
                                    _knownLastAppliedOperationId;
                                entry.ClaimCloseLeaseBefore = _knownCloseLease;
                            }
                        }
                        else if (cmd == "close")
                        {
                            bool exactClosePrestate = ReferenceEquals(
                                    _knownAuthorityBinding, binding)
                                && _knownAuthorityState == "LOOT_ACTIVE"
                                && _lastAuthorityRevision == entry.ExpectedAuthorityRevision
                                && _knownLootContainerVersion >= 0
                                && !string.IsNullOrEmpty(_knownCloseLease)
                                && string.Equals(_knownCloseLease, entry.CloseLease,
                                    StringComparison.Ordinal);
                            if (!exactClosePrestate) rejection = "stale_state";
                            else
                            {
                                entry.HasKnownClosePrestate = true;
                                entry.CloseAuthorityRevisionBefore = _lastAuthorityRevision;
                                entry.CloseRemainingBefore = _knownRemainingCount;
                                entry.CloseLastAppliedOperationIdBefore =
                                    _knownLastAppliedOperationId;
                                entry.CloseLootContainerVersionBefore =
                                    _knownLootContainerVersion;
                            }
                        }
                        if (rejection == null) _writeState = "write_pending";
                    }
                }
                else if (rejection == null && _writeState == "write_pending") rejection = "busy";
                else if (rejection == null && _writeState == "reconcile_required" && cmd != "query")
                    rejection = "reconcile_required";

                if (rejection == null)
                {
                    entry.FlashCallId = ++_sequence;
                    _pending[entry.FlashCallId] = entry;
                    _activeCallIds.Add(webCallId);
                }
                else RememberRecentLocked(webCallId);
            }

            if (rejection != null)
            {
                RespondError(binding, webCallId, cmd, rejection);
                return;
            }

            Timer timer = new Timer(delegate { HandleTimeout(entry.FlashCallId); }, null,
                _timeoutMs, Timeout.Infinite);
            lock (_sync)
            {
                if (_pending.ContainsKey(entry.FlashCallId)) _timers[entry.FlashCallId] = timer;
                else timer.Dispose();
            }

            JObject flash = PanelBridge.BuildFlashCommand(action, entry.FlashCallId, normalized);
            LogManager.Log("event=loot_request_forwarded cmd=" + cmd + " pending=" + PendingCount);
            bool sent = false;
            try { sent = _trySend(flash.ToString(Formatting.None) + "\0"); }
            catch (Exception ex)
            {
                LogManager.Log("event=loot_request_send_failed type=" + ex.GetType().Name);
            }
            if (!sent)
                HandleSendFailure(entry.FlashCallId);
        }

        public void HandleFlashResponse(JObject msg, Action<string> respond)
        {
            int fid;
            if (!TryReadInteger(msg != null ? msg["callId"] : null, 1, int.MaxValue, out fid))
            {
                if (respond != null) respond(null);
                return;
            }

            PendingRequest entry;
            JObject sanitized;
            bool authorityTerminal;
            bool authoritySuspended;
            bool commitPending;
            bool valid;
            bool droppedDetachedResponse = false;
            bool retryDetachedReconcile = false;
            bool detachedReconcileSettled = false;
            bool suspendedCloseProven = false;
            bool terminalCloseProven = false;
            bool unprovenUnknownQuery = false;
            int readyGeneration = SafeReadyGeneration();
            lock (_sync)
            {
                if (!_pending.TryGetValue(fid, out entry))
                {
                    if (respond != null) respond(null);
                    return;
                }
                if (entry.IsDetachedReconcile
                    && !DetachedReconcileContextMatchesLocked(entry, readyGeneration))
                {
                    CompletePendingLocked(fid, entry);
                    sanitized = null;
                    authorityTerminal = false;
                    authoritySuspended = false;
                    commitPending = false;
                    valid = false;
                    droppedDetachedResponse = true;
                }
                else
                {
                    int exactResponseRevision;
                    bool hasExactResponseRevision = TryReadExactResponseRevisionLocked(
                        msg, entry, out exactResponseRevision);
                    valid = TrySanitizeResponse(msg, entry, out sanitized,
                        out authorityTerminal, out authoritySuspended);
                    commitPending = valid && IsCommitPendingProjection(sanitized);
                    CompletePendingLocked(fid, entry);

                    if (!valid)
                    {
                        if (entry.IsWrite) MarkUnknownLocked(entry);
                        if (hasExactResponseRevision)
                            RaiseUnknownFreshnessWatermarkLocked(entry,
                                exactResponseRevision);
                    }
                    else
                    {
                        bool responseSuccess = sanitized.Value<bool>("success");
                        bool batchFailureAdvancedAuthority = entry.IsWrite
                            && string.Equals(entry.WebCmd, "claimBatch",
                                StringComparison.Ordinal)
                            && !responseSuccess
                            && entry.HasKnownClaimPrestate
                            && sanitized.Value<int>("authorityRevision")
                                > entry.ClaimAuthorityRevisionBefore;
                        bool exactRecoveryProof = entry.IsDetachedReconcile
                            && !string.IsNullOrEmpty(entry.RecoveryNonce);
                        // A detached handoff is stricter than ordinary Web/business traffic: an
                        // error may carry a strict terminal tombstone for normal causal
                        // reconciliation, but stale_recovery_proof does not prove that this exact
                        // nonce/attempt was applied.
                        suspendedCloseProven = authoritySuspended
                            && (entry.WebCmd == "close" || exactRecoveryProof
                                || entry.WebCmd == "query"
                                    && QueryProvesUnknownSuspendedCloseLocked(entry,
                                        sanitized));
                        terminalCloseProven = authorityTerminal
                            && (!entry.IsDetachedReconcile
                                || responseSuccess && exactRecoveryProof)
                            && (entry.WebCmd != "query"
                                || QueryMayCloseTerminalLocked(entry, sanitized));
                        // A detached document can no longer own an ACTIVE projection. Only a
                        // first-class suspended authority or exact terminal tombstone settles
                        // the visual recovery fence; ACTIVE falls through to another exact query.
                        if ((suspendedCloseProven || terminalCloseProven)
                            && ReferenceEquals(_detachedReconcileBinding, entry.Binding)
                            && _detachedReconcileRequired)
                        {
                            ClearDetachedReconcileLocked();
                            detachedReconcileSettled = true;
                        }
                        if (suspendedCloseProven || terminalCloseProven)
                            _authorityVisualCloseProofBinding = entry.Binding;
                        bool queryReconcilesUnknown = entry.WebCmd == "query"
                            && (responseSuccess
                                || !entry.IsDetachedReconcile && authorityTerminal)
                            && _writeState == "reconcile_required"
                            && QueryReconcilesUnknownLocked(entry, sanitized);
                        unprovenUnknownQuery = entry.WebCmd == "query"
                            && _writeState == "reconcile_required"
                            && !queryReconcilesUnknown;
                        if (unprovenUnknownQuery)
                            RaiseUnknownFreshnessWatermarkLocked(entry,
                                sanitized.Value<int>("authorityRevision"));
                        if (!unprovenUnknownQuery && !batchFailureAdvancedAuthority)
                        {
                            bool preserveKnownLootVersion =
                                AuthorityActivePrestateWasUnchangedLocked(entry, sanitized);
                            string preservedCloseLease =
                                ShouldPreserveKnownCloseLeaseLocked(entry, sanitized)
                                    ? _knownCloseLease : null;
                            int revision = sanitized.Value<int>("authorityRevision");
                            if (revision > _lastAuthorityRevision)
                                _lastAuthorityRevision = revision;
                            _knownAuthorityState = sanitized.Value<string>("state");
                            _knownRemainingCount = sanitized.Value<int>("remainingCount");
                            _knownCloseLease = preservedCloseLease
                                ?? sanitized.Value<string>("closeLease") ?? "";
                            _knownLastAppliedOperationId = sanitized.Value<string>(
                                "lastAppliedOperationId") ?? "";
                            int projectedLootVersion = FindLootContainerVersion(sanitized,
                                entry.Binding.LootContainerId);
                            _knownLootContainerVersion = projectedLootVersion >= 0
                                ? projectedLootVersion
                                : preserveKnownLootVersion ? _knownLootContainerVersion : -1;
                            _knownTerminal = sanitized["terminal"] is JObject terminal
                                ? (JObject)terminal.DeepClone() : null;
                            _knownAuthorityBinding = entry.Binding;
                        }
                        if (commitPending)
                        {
                            MarkCommitPendingProjectionLocked(entry);
                            if (batchFailureAdvancedAuthority)
                                RaiseUnknownFreshnessWatermarkLocked(entry,
                                    sanitized.Value<int>("authorityRevision"));
                        }
                        else if (batchFailureAdvancedAuthority)
                        {
                            // AS2 may have committed a recoverable prefix before a
                            // non-capacity failure. The root operation journal and revision
                            // show that a write occurred, but the failure response deliberately
                            // carries no snapshots. Fence later writes until an exact query
                            // proves which frozen batch sources were consumed.
                            MarkUnknownLocked(entry);
                            RaiseUnknownFreshnessWatermarkLocked(entry,
                                sanitized.Value<int>("authorityRevision"));
                        }
                        else if (entry.IsWrite)
                        {
                            _writeState = "idle";
                            ClearUnknownLocked();
                        }
                        else if (queryReconcilesUnknown
                            && _writeState == "reconcile_required")
                        {
                            _writeState = "idle";
                            ClearUnknownLocked();
                        }
                    }
                    retryDetachedReconcile = entry.IsDetachedReconcile
                        && DetachedReconcileContextMatchesLocked(entry, readyGeneration);
                }
            }

            if (droppedDetachedResponse)
            {
                if (respond != null) respond(null);
                return;
            }

            if (!valid)
            {
                if (!entry.IsDetachedReconcile && _coordinator.IsCurrentExact(entry.Binding))
                    RespondError(entry.Binding, entry.WebCallId, entry.WebCmd,
                        entry.IsWrite ? "reconcile_required" : "malformed_response");
                if (respond != null) respond(null);
                if (retryDetachedReconcile) ScheduleDetachedReconcileRetry(entry);
                return;
            }

            if (!entry.IsDetachedReconcile && _coordinator.IsCurrentExact(entry.Binding))
            {
                if (unprovenUnknownQuery)
                    RespondError(entry.Binding, entry.WebCallId, entry.WebCmd,
                        "reconcile_required");
                else
                    PostSanitizedResponse(entry, sanitized);
            }
            if (terminalCloseProven && !entry.IsDetachedReconcile)
                _coordinator.CloseAfterAuthorityTerminal(entry.Binding);
            else if (suspendedCloseProven && !entry.IsDetachedReconcile)
                _coordinator.CloseAfterAuthoritySuspended(entry.Binding);
            if (respond != null) respond(null);
            if (detachedReconcileSettled) NotifyDetachedReconcileSettled();
            else if (retryDetachedReconcile) ScheduleDetachedReconcileRetry(entry);
        }

        public void OnTransportDetached()
        {
            DetachPendingRequests(null, false, true, null, false, 0);
        }

        /// <summary>
        /// A connected Web-document failure has a two-step handoff. Capture and fence the exact
        /// old authority before LootPanelCoordinator sends lootPanelRecovery, so a late response
        /// can never escape to the document that is being destroyed.
        /// </summary>
        public bool PrepareConnectedTransportDetach(LootPanelCoordinator.Binding binding,
            string recoveryNonce)
        {
            if (!LootPanelCoordinator.IsOpaque(recoveryNonce)) return false;
            return DetachPendingRequests(binding, true, false, recoveryNonce, false, 0);
        }

        /// <summary>
        /// Called only after the strict eight-key lootPanelRecovery was written to this exact
        /// socket generation. The following nine-key query repeats the exact attempt and nonce;
        /// AS2 returns success only after that handoff is actually applied. The proof response is
        /// internal and is never forwarded to Web.
        /// </summary>
        public void OnConnectedTransportRecoverySent(LootPanelCoordinator.Binding binding,
            int transportGeneration, string recoveryNonce)
        {
            if (_disposed || binding == null || transportGeneration <= 0
                || !LootPanelCoordinator.IsOpaque(recoveryNonce)) return;
            if (!DetachPendingRequests(binding, true, false, recoveryNonce, false, 0)) return;
            int currentGeneration = SafeReadyGeneration();
            if (currentGeneration != transportGeneration)
            {
                // The connected authority-handoff frame belonged to a socket that has already
                // been replaced. Its nonce may never have reached AS2; socket close itself selects
                // the causal socket-detach proof path. Drop only that nonce, then reconcile on
                // the replacement.
                string socketNonce = DowngradeConnectedRecoveryToSocketProof(binding,
                    recoveryNonce, transportGeneration);
                if (currentGeneration > 0 && socketNonce != null)
                    BeginDetachedReconcile(binding, currentGeneration, socketNonce, true);
                return;
            }
            BeginDetachedReconcile(binding, transportGeneration, recoveryNonce, false);
        }

        public void OnSocketTransportDetached(int closedGeneration)
        {
            // Keep the same Task -> Coordinator lock order as panel admission.  Otherwise a
            // disconnect could snapshot ActiveBinding=null while an admission lease was held,
            // then miss the freshly reserved binding immediately after that lease was released.
            lock (_sync)
            {
                LootPanelCoordinator.Binding binding = _coordinator.ActiveBinding;
                if (!DetachPendingRequests(binding, true, true, null, true,
                        closedGeneration)) return;
            }
            int currentGeneration = SafeReadyGeneration();
            if (currentGeneration <= closedGeneration) return;
            string socketNonce;
            lock (_sync)
            {
                if (!_detachedReconcileRequired || !_detachedReconcileSocketMode) return;
                socketNonce = _detachedReconcileRecoveryNonce;
            }
            BeginDetachedReconcile(null, currentGeneration, socketNonce, true);
        }

        /// <summary>
        /// A detached Web document cannot own reconciliation. On a fresh socket generation the
        /// Host asks AS2 about the exact old authority identity, but never replays the write and
        /// never posts the answer to the stale Web instance.
        /// </summary>
        public void OnSocketReconnected()
        {
            if (_disposed) return;
            int transportGeneration = SafeReadyGeneration();
            if (transportGeneration <= 0) return;
            string socketNonce;
            lock (_sync)
            {
                if (!_detachedReconcileRequired || !_detachedReconcileSocketMode) return;
                socketNonce = _detachedReconcileRecoveryNonce;
            }
            BeginDetachedReconcile(null, transportGeneration, socketNonce, true);
        }

        private void BeginDetachedReconcile(LootPanelCoordinator.Binding expectedBinding,
            int transportGeneration, string expectedRecoveryNonce,
            bool expectedSocketMode)
        {
            int reconcileEpoch;
            lock (_sync)
            {
                if (!_detachedReconcileRequired || _detachedReconcileBinding == null) return;
                if (expectedBinding != null
                    && !ReferenceEquals(expectedBinding, _detachedReconcileBinding)) return;
                // This is the CAS boundary between connected recovery proof and socket-close
                // proof. A disconnect switches mode, replaces the nonce, and bumps the epoch
                // before any replacement query; a late dead-generation callback cannot overwrite it.
                if (_detachedReconcileSocketMode != expectedSocketMode
                    || !string.Equals(expectedRecoveryNonce, _detachedReconcileRecoveryNonce,
                        StringComparison.Ordinal)) return;
                if (_detachedReconcileTransportGeneration == transportGeneration) return;
                CancelDetachedReconcileRetryLocked();
                DropDetachedReconcilePendingLocked();
                _detachedReconcileEpoch++;
                _detachedReconcileTransportGeneration = transportGeneration;
                _detachedReconcileRetryAttempt = 0;
                reconcileEpoch = _detachedReconcileEpoch;
            }
            DispatchDetachedReconcile(reconcileEpoch, transportGeneration);
        }

        public void Dispose()
        {
            if (_disposed) return;
            _disposed = true;
            _coordinator.BindingDetached -= OnBindingDetached;
            lock (_sync)
            {
                CancelDetachedReconcileRetryLocked();
                _detachedReconcileEpoch++;
                _detachedReconcileTransportGeneration = 0;
                _detachedReconcileRecoveryNonce = null;
                _detachedReconcileSocketMode = false;
                _unknownBinding = null;
                _detachedReconcileBinding = null;
                _detachedReconcileRequired = false;
                foreach (Timer timer in _timers.Values) timer.Dispose();
                _timers.Clear();
                _pending.Clear();
                _activeCallIds.Clear();
            }
        }

        private void OnBindingDetached()
        {
            DetachPendingRequests(null, false, true, null, false, 0);
        }

        private bool DetachPendingRequests(LootPanelCoordinator.Binding binding,
            bool requireAuthorityHandoff, bool restartExistingHandoff,
            string recoveryNonce, bool socketMode, int socketDetachGeneration)
        {
            lock (_sync)
            {
                if (_disposed) return false;
                if (socketMode)
                {
                    if (socketDetachGeneration <= 0) return false;
                    if (socketDetachGeneration <= _lastSocketDetachGeneration) return true;
                    _lastSocketDetachGeneration = socketDetachGeneration;
                }
                if (requireAuthorityHandoff && !socketMode
                    && !LootPanelCoordinator.IsOpaque(recoveryNonce)) return false;
                LootPanelCoordinator.Binding handoffBinding = socketMode
                    ? _detachedReconcileBinding ?? _unknownBinding ?? binding
                    : binding ?? _unknownBinding;
                if (requireAuthorityHandoff && handoffBinding != null
                    && ReferenceEquals(_authorityVisualCloseProofBinding,
                        handoffBinding)) return false;
                // The native/DOM close proof may arrive after a fresh socket already started the
                // detached authority query. Visual teardown must not cancel that generation-bound
                // read or strand the handoff fence until another reconnect that may never happen.
                if (!requireAuthorityHandoff && _detachedReconcileRequired)
                {
                    DropNonDetachedPendingLocked();
                    return true;
                }
                // Connected recovery is deliberately two-phase. Re-observing the same prepared
                // binding after the recovery command was written must preserve its query/epoch;
                // a different authority can never replace an unresolved detached handoff.
                if (requireAuthorityHandoff && !restartExistingHandoff
                    && _detachedReconcileRequired)
                {
                    if (_detachedReconcileSocketMode
                        || !ReferenceEquals(binding, _detachedReconcileBinding)
                        || !string.Equals(recoveryNonce, _detachedReconcileRecoveryNonce,
                            StringComparison.Ordinal)) return false;
                    DropNonDetachedPendingLocked();
                    return true;
                }
                LootPanelCoordinator.Binding exactBinding = requireAuthorityHandoff
                    ? (socketMode
                        ? _detachedReconcileBinding ?? _unknownBinding ?? binding
                        : binding ?? _unknownBinding)
                    : null;
                if (requireAuthorityHandoff && _detachedReconcileRequired
                    && !ReferenceEquals(exactBinding, _detachedReconcileBinding))
                    return false;
                string proofNonce = recoveryNonce;
                if (requireAuthorityHandoff && socketMode)
                {
                    bool duplicateDetachedNotification = _detachedReconcileRequired
                        && _detachedReconcileSocketMode
                        && _detachedReconcileTransportGeneration == 0
                        && LootPanelCoordinator.IsOpaque(_detachedReconcileRecoveryNonce);
                    proofNonce = duplicateDetachedNotification
                        ? _detachedReconcileRecoveryNonce : Guid.NewGuid().ToString("N");
                }
                if (exactBinding != null
                    && !BindingIdentityMatchesRevisionLocked(exactBinding))
                {
                    // Revision/cache state is scoped by the full authority identity, including
                    // openAttemptSeq.  Switching it is safe only while no unresolved write can
                    // still mutate the old scope; otherwise preserve the old fence and fail closed.
                    if (_writeState != "idle") return false;
                    foreach (PendingRequest pending in _pending.Values)
                        if (pending.IsWrite) return false;
                    ActivateRevisionScopeLocked(exactBinding);
                }
                CancelDetachedReconcileRetryLocked();
                _detachedReconcileEpoch++;
                _detachedReconcileTransportGeneration = 0;
                foreach (PendingRequest entry in _pending.Values)
                {
                    if (entry.IsWrite) MarkUnknownLocked(entry);
                    _activeCallIds.Remove(entry.WebCallId);
                    RememberRecentLocked(entry.WebCallId);
                }
                foreach (Timer timer in _timers.Values) timer.Dispose();
                _timers.Clear();
                _pending.Clear();
                if (requireAuthorityHandoff)
                {
                    LootPanelCoordinator.Binding exact = exactBinding;
                    if (!_detachedReconcileRequired && exact != null)
                    {
                        _detachedReconcileBinding = exact;
                        _detachedReconcileRequired = true;
                        _detachedReconcileRecoveryNonce = proofNonce;
                        _detachedReconcileSocketMode = socketMode;
                        _detachedReconcileExpectedAuthorityRevision =
                            BindingIdentityMatchesRevisionLocked(exact)
                                ? _lastAuthorityRevision : 0;
                    }
                    else if (_detachedReconcileRequired
                        && ReferenceEquals(_detachedReconcileBinding, exact)
                        && restartExistingHandoff)
                    {
                        // A real socket detach supersedes an in-flight connected recovery proof.
                        // The replacement socket must use the disconnect causal path, never an
                        // unacknowledged nonce from the dead generation.
                        _detachedReconcileRecoveryNonce = proofNonce;
                        _detachedReconcileSocketMode = socketMode;
                    }
                }
                return !requireAuthorityHandoff
                    || (_detachedReconcileRequired
                        && ReferenceEquals(_detachedReconcileBinding, exactBinding));
            }
        }

        private void HandleTimeout(int fid)
        {
            PendingRequest entry;
            bool retryDetachedReconcile;
            int readyGeneration = SafeReadyGeneration();
            lock (_sync)
            {
                if (_disposed || !_pending.TryGetValue(fid, out entry)) return;
                CompletePendingLocked(fid, entry);
                if (entry.IsWrite) MarkUnknownLocked(entry);
                retryDetachedReconcile = entry.IsDetachedReconcile
                    && DetachedReconcileContextMatchesLocked(entry, readyGeneration);
            }
            if (!entry.IsDetachedReconcile && _coordinator.IsCurrentExact(entry.Binding))
                RespondError(entry.Binding, entry.WebCallId, entry.WebCmd,
                    entry.IsWrite ? "reconcile_required" : "timeout");
            if (retryDetachedReconcile) ScheduleDetachedReconcileRetry(entry);
        }

        private void HandleSendFailure(int fid)
        {
            PendingRequest entry;
            bool retryDetachedReconcile;
            int readyGeneration = SafeReadyGeneration();
            lock (_sync)
            {
                if (!_pending.TryGetValue(fid, out entry)) return;
                CompletePendingLocked(fid, entry);
                // A bool send failure cannot distinguish a pre-write rejection from a Write/Flush
                // exception after the peer may have received a complete NUL frame. Writes therefore
                // enter causal reconciliation; reads remain an ordinary disconnected failure.
                if (entry.IsWrite) MarkUnknownLocked(entry);
                retryDetachedReconcile = entry.IsDetachedReconcile
                    && DetachedReconcileContextMatchesLocked(entry, readyGeneration);
            }
            if (!entry.IsDetachedReconcile && _coordinator.IsCurrentExact(entry.Binding))
                RespondError(entry.Binding, entry.WebCallId, entry.WebCmd,
                    entry.IsWrite ? "reconcile_required" : "disconnected");
            if (retryDetachedReconcile) ScheduleDetachedReconcileRetry(entry);
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
            _activeCallIds.Remove(entry.WebCallId);
            RememberRecentLocked(entry.WebCallId);
        }

        private void MarkUnknownLocked(PendingRequest entry)
        {
            bool sameUnknown = _writeState == "reconcile_required"
                && string.Equals(_unknownOperationId, entry.OperationId,
                    StringComparison.Ordinal)
                && string.Equals(_unknownChestSessionId, entry.Binding.ChestSessionId,
                    StringComparison.Ordinal)
                && string.Equals(_unknownLootContainerId, entry.Binding.LootContainerId,
                    StringComparison.Ordinal)
                && _unknownContainerEpoch == entry.Binding.ContainerEpoch
                && _unknownOpenAttemptSeq == entry.Binding.OpenAttemptSeq;
            if (!sameUnknown && !entry.IsDetachedReconcile)
            {
                CancelDetachedReconcileRetryLocked();
                _detachedReconcileEpoch++;
                _detachedReconcileTransportGeneration = 0;
                _detachedReconcileRetryAttempt = 0;
            }
            _writeState = "reconcile_required";
            _unknownOperationId = entry.OperationId;
            _unknownChestSessionId = entry.Binding.ChestSessionId;
            _unknownLootContainerId = entry.Binding.LootContainerId;
            _unknownContainerEpoch = entry.Binding.ContainerEpoch;
            _unknownOpenAttemptSeq = entry.Binding.OpenAttemptSeq;
            _unknownExpectedAuthorityRevision = entry.ExpectedAuthorityRevision;
            int priorFreshnessWatermark = sameUnknown
                ? _unknownFreshnessWatermark : 0;
            _unknownFreshnessWatermark = Math.Max(priorFreshnessWatermark,
                Math.Max(_lastAuthorityRevision, entry.ExpectedAuthorityRevision));
            _unknownRequiresCausalCompletion = false;
            _unknownWebCmd = entry.WebCmd;
            _unknownCloseAbandon = entry.CloseAbandon;
            _unknownHasKnownClosePrestate = entry.HasKnownClosePrestate;
            _unknownCloseAuthorityRevisionBefore = entry.CloseAuthorityRevisionBefore;
            _unknownCloseRemainingBefore = entry.CloseRemainingBefore;
            _unknownCloseLastAppliedOperationIdBefore =
                entry.CloseLastAppliedOperationIdBefore;
            _unknownCloseLease = entry.CloseLease;
            _unknownCloseLootContainerVersionBefore =
                entry.CloseLootContainerVersionBefore;
            _unknownHasKnownClaimPrestate = entry.HasKnownClaimPrestate;
            _unknownClaimAuthorityRevisionBefore = entry.ClaimAuthorityRevisionBefore;
            _unknownClaimRemainingBefore = entry.ClaimRemainingBefore;
            _unknownClaimPhysicalSlot = entry.ClaimPhysicalSlot;
            _unknownClaimSourceLease = entry.ClaimSourceLease;
            _unknownClaimBatchPhysicalSlots = entry.ClaimBatchPhysicalSlots == null
                ? null : (int[])entry.ClaimBatchPhysicalSlots.Clone();
            _unknownClaimBatchSourceLeases = entry.ClaimBatchSourceLeases == null
                ? null : (string[])entry.ClaimBatchSourceLeases.Clone();
            _unknownClaimSourceContainerVersion = entry.ClaimSourceContainerVersion;
            _unknownClaimLastAppliedOperationIdBefore =
                entry.ClaimLastAppliedOperationIdBefore;
            _unknownClaimCloseLeaseBefore = entry.ClaimCloseLeaseBefore;
            _unknownBinding = entry.Binding;
        }

        private void MarkCommitPendingLocked(PendingRequest entry)
        {
            MarkUnknownLocked(entry);
            _unknownRequiresCausalCompletion = true;
        }

        private void MarkCommitPendingProjectionLocked(PendingRequest entry)
        {
            bool sameUnknownIdentity = _writeState == "reconcile_required"
                && string.Equals(_unknownChestSessionId, entry.Binding.ChestSessionId,
                    StringComparison.Ordinal)
                && string.Equals(_unknownLootContainerId, entry.Binding.LootContainerId,
                    StringComparison.Ordinal)
                && _unknownContainerEpoch == entry.Binding.ContainerEpoch
                && _unknownOpenAttemptSeq == entry.Binding.OpenAttemptSeq;
            if (!sameUnknownIdentity) MarkCommitPendingLocked(entry);
            else _unknownRequiresCausalCompletion = true;
        }

        private void ClearUnknownLocked()
        {
            _unknownBinding = null;
            _unknownOperationId = null;
            _unknownChestSessionId = null;
            _unknownLootContainerId = null;
            _unknownContainerEpoch = 0;
            _unknownOpenAttemptSeq = 0;
            _unknownExpectedAuthorityRevision = 0;
            _unknownFreshnessWatermark = 0;
            _unknownRequiresCausalCompletion = false;
            _unknownWebCmd = null;
            _unknownCloseAbandon = false;
            _unknownHasKnownClosePrestate = false;
            _unknownCloseAuthorityRevisionBefore = 0;
            _unknownCloseRemainingBefore = 0;
            _unknownCloseLastAppliedOperationIdBefore = null;
            _unknownCloseLease = null;
            _unknownCloseLootContainerVersionBefore = -1;
            _unknownHasKnownClaimPrestate = false;
            _unknownClaimAuthorityRevisionBefore = 0;
            _unknownClaimRemainingBefore = 0;
            _unknownClaimPhysicalSlot = -1;
            _unknownClaimSourceLease = null;
            _unknownClaimBatchPhysicalSlots = null;
            _unknownClaimBatchSourceLeases = null;
            _unknownClaimSourceContainerVersion = -1;
            _unknownClaimLastAppliedOperationIdBefore = null;
            _unknownClaimCloseLeaseBefore = null;
        }

        private void RaiseUnknownFreshnessWatermarkLocked(PendingRequest entry, int revision)
        {
            if (entry == null || revision < 0
                || _writeState != "reconcile_required"
                || !ReferenceEquals(_unknownBinding, entry.Binding)) return;
            if (revision > _unknownFreshnessWatermark)
                _unknownFreshnessWatermark = revision;
        }

        private void ClearDetachedReconcileLocked()
        {
            CancelDetachedReconcileRetryLocked();
            _detachedReconcileEpoch++;
            _detachedReconcileTransportGeneration = 0;
            _detachedReconcileRetryAttempt = 0;
            _detachedReconcileRecoveryNonce = null;
            _detachedReconcileSocketMode = false;
            _detachedReconcileBinding = null;
            _detachedReconcileRequired = false;
            _detachedReconcileExpectedAuthorityRevision = 0;
        }

        private bool QueryReconcilesUnknownLocked(PendingRequest entry, JObject sanitized)
        {
            if (entry == null || sanitized == null) return false;
            if (_unknownBinding != null
                && !ReferenceEquals(_unknownBinding, entry.Binding)) return false;
            if (string.IsNullOrEmpty(_unknownOperationId)) return true;
            if (string.Equals(sanitized.Value<string>("state"), "LOOT_SUSPENDED",
                    StringComparison.Ordinal)
                && string.Equals(_unknownWebCmd, "close", StringComparison.Ordinal))
                return QueryProvesUnknownSuspendedCloseLocked(entry, sanitized);
            if (sanitized["terminal"] is JObject)
            {
                if (string.Equals(_unknownWebCmd, "close", StringComparison.Ordinal))
                    return QueryProvesUnknownTerminalCloseLocked(entry, sanitized);
                if (string.Equals(_unknownWebCmd, "claim", StringComparison.Ordinal)
                    || string.Equals(_unknownWebCmd, "claimBatch", StringComparison.Ordinal))
                    return QueryProvesUnknownTerminalClaimLocked(entry, sanitized);
                return true;
            }
            if (string.Equals(_unknownWebCmd, "claim", StringComparison.Ordinal))
                return QueryProvesUnknownClaimLocked(entry, sanitized);
            if (string.Equals(_unknownWebCmd, "claimBatch", StringComparison.Ordinal))
                return QueryProvesUnknownClaimBatchLocked(entry, sanitized);
            if (string.Equals(_unknownWebCmd, "close", StringComparison.Ordinal))
                return QueryProvesUnknownActiveCloseNotAppliedLocked(entry, sanitized);
            string lastApplied = sanitized.Value<string>("lastAppliedOperationId") ?? "";
            if (string.Equals(lastApplied, _unknownOperationId, StringComparison.Ordinal))
                return true;
            return !_unknownRequiresCausalCompletion
                && sanitized.Value<int>("authorityRevision") == _unknownExpectedAuthorityRevision;
        }

        private bool QueryMayCloseTerminalLocked(PendingRequest entry, JObject sanitized)
        {
            return _writeState != "reconcile_required"
                || QueryReconcilesUnknownLocked(entry, sanitized);
        }

        private bool QueryProvesUnknownTerminalClaimLocked(PendingRequest entry,
            JObject sanitized)
        {
            if (entry == null || sanitized == null
                || _writeState != "reconcile_required"
                || !(string.Equals(_unknownWebCmd, "claim", StringComparison.Ordinal)
                    || string.Equals(_unknownWebCmd, "claimBatch", StringComparison.Ordinal))
                || !_unknownHasKnownClaimPrestate
                || !ReferenceEquals(_unknownBinding, entry.Binding)) return false;
            int revision = sanitized.Value<int>("authorityRevision");
            return revision >= _unknownFreshnessWatermark
                && revision > _unknownExpectedAuthorityRevision
                && revision > _unknownClaimAuthorityRevisionBefore
                && revision >= _lastAuthorityRevision;
        }

        private bool QueryProvesUnknownTerminalCloseLocked(PendingRequest entry,
            JObject sanitized)
        {
            int revision = sanitized != null
                ? sanitized.Value<int>("authorityRevision") : -1;
            if (entry == null || sanitized == null
                || _writeState != "reconcile_required"
                || !string.Equals(_unknownWebCmd, "close", StringComparison.Ordinal)
                || !_unknownHasKnownClosePrestate
                || !ReferenceEquals(_unknownBinding, entry.Binding)
                || revision < _unknownFreshnessWatermark
                || revision <= _unknownExpectedAuthorityRevision)
                return false;
            string state = sanitized.Value<string>("state") ?? "";
            if (state == "EXPIRED") return true;
            if (!string.Equals(sanitized.Value<string>("lastAppliedOperationId"),
                    _unknownOperationId, StringComparison.Ordinal)) return false;
            int remaining = sanitized.Value<int>("remainingCount");
            if (_unknownCloseRemainingBefore == 0)
                return state == "CONSUMED" && remaining == 0;
            return _unknownCloseAbandon && state == "ABANDONED"
                && remaining == _unknownCloseRemainingBefore;
        }

        private bool QueryProvesUnknownSuspendedCloseLocked(PendingRequest entry,
            JObject sanitized)
        {
            return entry != null && sanitized != null
                && _writeState == "reconcile_required"
                && string.Equals(_unknownWebCmd, "close", StringComparison.Ordinal)
                && !_unknownCloseAbandon
                && _unknownHasKnownClosePrestate
                && _unknownCloseRemainingBefore > 0
                && ReferenceEquals(_unknownBinding, entry.Binding)
                && string.Equals(sanitized.Value<string>("state"), "LOOT_SUSPENDED",
                    StringComparison.Ordinal)
                && string.Equals(sanitized.Value<string>("lastAppliedOperationId"),
                    _unknownOperationId, StringComparison.Ordinal)
                && sanitized.Value<int>("authorityRevision")
                    >= _unknownFreshnessWatermark
                && sanitized.Value<int>("authorityRevision")
                    > _unknownExpectedAuthorityRevision
                && sanitized.Value<int>("remainingCount")
                    == _unknownCloseRemainingBefore;
        }

        private bool QueryProvesUnknownClaimLocked(PendingRequest entry, JObject sanitized)
        {
            if (entry == null || sanitized == null
                || _writeState != "reconcile_required"
                || !string.Equals(_unknownWebCmd, "claim", StringComparison.Ordinal)
                || !_unknownHasKnownClaimPrestate
                || !ReferenceEquals(_unknownBinding, entry.Binding)
                || !string.Equals(sanitized.Value<string>("state"), "LOOT_ACTIVE",
                    StringComparison.Ordinal)) return false;

            JObject sourceSlot;
            int containerVersion;
            if (!TryFindLootSlotProjection(sanitized, entry.Binding.LootContainerId,
                    _unknownClaimPhysicalSlot, out sourceSlot, out containerVersion)) return false;

            int revision = sanitized.Value<int>("authorityRevision");
            int remaining = sanitized.Value<int>("remainingCount");
            string lastApplied = sanitized.Value<string>("lastAppliedOperationId") ?? "";
            if (revision < _unknownFreshnessWatermark) return false;
            bool applied = string.Equals(lastApplied, _unknownOperationId,
                    StringComparison.Ordinal)
                && (long)revision == (long)_unknownClaimAuthorityRevisionBefore + 1L
                && remaining == _unknownClaimRemainingBefore - 1
                && !sourceSlot.Value<bool>("occupied");
            if (applied) return true;

            return !_unknownRequiresCausalCompletion
                && revision == _unknownClaimAuthorityRevisionBefore
                && remaining == _unknownClaimRemainingBefore
                && string.Equals(lastApplied,
                    _unknownClaimLastAppliedOperationIdBefore ?? "",
                    StringComparison.Ordinal)
                && string.Equals(sanitized.Value<string>("closeLease") ?? "",
                    _unknownClaimCloseLeaseBefore ?? "", StringComparison.Ordinal)
                && sourceSlot.Value<bool>("occupied")
                && string.Equals(sourceSlot.Value<string>("slotLease"),
                    _unknownClaimSourceLease, StringComparison.Ordinal)
                && containerVersion == _unknownClaimSourceContainerVersion;
        }

        private bool QueryProvesUnknownClaimBatchLocked(PendingRequest entry,
            JObject sanitized)
        {
            if (entry == null || sanitized == null
                || _writeState != "reconcile_required"
                || !string.Equals(_unknownWebCmd, "claimBatch", StringComparison.Ordinal)
                || !_unknownHasKnownClaimPrestate
                || _unknownClaimBatchPhysicalSlots == null
                || _unknownClaimBatchSourceLeases == null
                || _unknownClaimBatchPhysicalSlots.Length == 0
                || _unknownClaimBatchPhysicalSlots.Length
                    != _unknownClaimBatchSourceLeases.Length
                || !ReferenceEquals(_unknownBinding, entry.Binding)
                || !string.Equals(sanitized.Value<string>("state"), "LOOT_ACTIVE",
                    StringComparison.Ordinal)) return false;

            int revision = sanitized.Value<int>("authorityRevision");
            int remaining = sanitized.Value<int>("remainingCount");
            string lastApplied = sanitized.Value<string>("lastAppliedOperationId") ?? "";
            if (revision < _unknownFreshnessWatermark) return false;
            long appliedCount = (long)revision - _unknownClaimAuthorityRevisionBefore;
            int emptyRequested;
            int containerVersion;
            bool exactRequestedProjection = TryInspectClaimBatchProjection(sanitized,
                entry.Binding.LootContainerId, _unknownClaimBatchPhysicalSlots,
                _unknownClaimBatchSourceLeases, out emptyRequested, out containerVersion);
            bool applied = exactRequestedProjection
                && appliedCount >= 1L
                && appliedCount <= _unknownClaimBatchPhysicalSlots.Length
                && string.Equals(lastApplied, _unknownOperationId, StringComparison.Ordinal)
                && remaining == _unknownClaimRemainingBefore - (int)appliedCount
                && emptyRequested == (int)appliedCount;
            if (applied) return true;

            return !_unknownRequiresCausalCompletion
                && exactRequestedProjection
                && revision == _unknownClaimAuthorityRevisionBefore
                && remaining == _unknownClaimRemainingBefore
                && string.Equals(lastApplied,
                    _unknownClaimLastAppliedOperationIdBefore ?? "",
                    StringComparison.Ordinal)
                && string.Equals(sanitized.Value<string>("closeLease") ?? "",
                    _unknownClaimCloseLeaseBefore ?? "", StringComparison.Ordinal)
                && containerVersion == _unknownClaimSourceContainerVersion
                && emptyRequested == 0;
        }

        private bool QueryProvesUnknownActiveCloseNotAppliedLocked(PendingRequest entry,
            JObject sanitized)
        {
            if (entry == null || sanitized == null
                || _writeState != "reconcile_required"
                || !string.Equals(_unknownWebCmd, "close", StringComparison.Ordinal)
                || _unknownRequiresCausalCompletion
                || !_unknownHasKnownClosePrestate
                || !ReferenceEquals(_unknownBinding, entry.Binding)
                || !string.Equals(sanitized.Value<string>("state"), "LOOT_ACTIVE",
                    StringComparison.Ordinal)
                || sanitized.Value<int>("authorityRevision")
                    < _unknownFreshnessWatermark
                || sanitized.Value<int>("authorityRevision")
                    != _unknownCloseAuthorityRevisionBefore
                || sanitized.Value<int>("remainingCount")
                    != _unknownCloseRemainingBefore
                || !string.Equals(sanitized.Value<string>("lastAppliedOperationId") ?? "",
                    _unknownCloseLastAppliedOperationIdBefore ?? "",
                    StringComparison.Ordinal)
                || !string.Equals(sanitized.Value<string>("closeLease") ?? "",
                    _unknownCloseLease, StringComparison.Ordinal)) return false;

            return FindLootContainerVersion(sanitized, entry.Binding.LootContainerId)
                == _unknownCloseLootContainerVersionBefore;
        }

        private static bool TryFindLootSlotProjection(JObject sanitized, string lootContainerId,
            int physicalSlot, out JObject sourceSlot, out int containerVersion)
        {
            sourceSlot = null;
            containerVersion = -1;
            JArray snapshots = sanitized != null ? sanitized["snapshots"] as JArray : null;
            if (snapshots == null || physicalSlot < 0) return false;
            foreach (JToken token in snapshots)
            {
                JObject snapshot = token as JObject;
                if (snapshot == null || !string.Equals(ReadString(snapshot["containerId"]),
                        lootContainerId, StringComparison.Ordinal)) continue;
                containerVersion = snapshot.Value<int>("containerVersion");
                JArray slots = snapshot["slots"] as JArray;
                if (slots == null) return false;
                foreach (JToken slotToken in slots)
                {
                    JObject slot = slotToken as JObject;
                    if (slot != null && slot.Value<int>("physicalSlot") == physicalSlot)
                    {
                        sourceSlot = slot;
                        return true;
                    }
                }
                return false;
            }
            return false;
        }

        private static int FindLootContainerVersion(JObject sanitized, string lootContainerId)
        {
            JArray snapshots = sanitized != null ? sanitized["snapshots"] as JArray : null;
            if (snapshots == null) return -1;
            foreach (JToken token in snapshots)
            {
                JObject snapshot = token as JObject;
                if (snapshot != null && string.Equals(ReadString(snapshot["containerId"]),
                        lootContainerId, StringComparison.Ordinal))
                    return snapshot.Value<int>("containerVersion");
            }
            return -1;
        }

        private static bool TryInspectClaimBatchProjection(JObject sanitized,
            string lootContainerId, int[] physicalSlots, string[] expectedLeases,
            out int emptyRequested, out int containerVersion)
        {
            emptyRequested = 0;
            containerVersion = -1;
            if (physicalSlots == null || expectedLeases == null
                || physicalSlots.Length == 0
                || physicalSlots.Length != expectedLeases.Length) return false;
            JArray snapshots = sanitized != null ? sanitized["snapshots"] as JArray : null;
            if (snapshots == null) return false;
            JObject lootSnapshot = null;
            foreach (JToken token in snapshots)
            {
                JObject candidate = token as JObject;
                if (candidate != null && string.Equals(ReadString(candidate["containerId"]),
                        lootContainerId, StringComparison.Ordinal))
                {
                    lootSnapshot = candidate;
                    break;
                }
            }
            if (lootSnapshot == null) return false;
            containerVersion = lootSnapshot.Value<int>("containerVersion");
            JArray slots = lootSnapshot["slots"] as JArray;
            if (slots == null) return false;
            for (int requestedIndex = 0; requestedIndex < physicalSlots.Length;
                requestedIndex++)
            {
                JObject requestedSlot = null;
                foreach (JToken slotToken in slots)
                {
                    JObject slot = slotToken as JObject;
                    if (slot != null && slot.Value<int>("physicalSlot")
                            == physicalSlots[requestedIndex])
                    {
                        requestedSlot = slot;
                        break;
                    }
                }
                if (requestedSlot == null) return false;
                if (!requestedSlot.Value<bool>("occupied"))
                {
                    emptyRequested++;
                    continue;
                }
                if (!string.Equals(requestedSlot.Value<string>("slotLease"),
                        expectedLeases[requestedIndex], StringComparison.Ordinal)) return false;
            }
            return true;
        }

        private bool AuthorityActivePrestateWasUnchangedLocked(PendingRequest entry,
            JObject sanitized)
        {
            return entry != null && sanitized != null
                && ReferenceEquals(_knownAuthorityBinding, entry.Binding)
                && _coordinator.IsCurrentExact(entry.Binding)
                && string.Equals(_knownAuthorityState, "LOOT_ACTIVE",
                    StringComparison.Ordinal)
                && string.Equals(sanitized.Value<string>("state"), "LOOT_ACTIVE",
                    StringComparison.Ordinal)
                && sanitized.Value<int>("authorityRevision") == _lastAuthorityRevision
                && sanitized.Value<int>("remainingCount") == _knownRemainingCount
                && string.Equals(sanitized.Value<string>("lastAppliedOperationId") ?? "",
                    _knownLastAppliedOperationId, StringComparison.Ordinal);
        }

        private int SafeReadyGeneration()
        {
            try { return _getReadyGeneration == null ? 0 : _getReadyGeneration(); }
            catch { return 0; }
        }

        private static bool BindingIdentityMatches(LootPanelCoordinator.Binding left,
            LootPanelCoordinator.Binding right)
        {
            return left != null && right != null
                && string.Equals(left.ChestSessionId, right.ChestSessionId,
                    StringComparison.Ordinal)
                && string.Equals(left.LootContainerId, right.LootContainerId,
                    StringComparison.Ordinal)
                && left.ContainerEpoch == right.ContainerEpoch
                && left.OpenAttemptSeq == right.OpenAttemptSeq;
        }

        private bool BindingIdentityMatchesRevisionLocked(LootPanelCoordinator.Binding binding)
        {
            return binding != null
                && string.Equals(_revisionChestSessionId, binding.ChestSessionId,
                    StringComparison.Ordinal)
                && string.Equals(_revisionLootContainerId, binding.LootContainerId,
                    StringComparison.Ordinal)
                && _revisionContainerEpoch == binding.ContainerEpoch
                && _revisionOpenAttemptSeq == binding.OpenAttemptSeq;
        }

        private void ActivateRevisionScopeLocked(LootPanelCoordinator.Binding binding)
        {
            _revisionChestSessionId = binding.ChestSessionId;
            _revisionLootContainerId = binding.LootContainerId;
            _revisionContainerEpoch = binding.ContainerEpoch;
            _revisionOpenAttemptSeq = binding.OpenAttemptSeq;
            _lastAuthorityRevision = 0;
            _knownAuthorityState = "LOOT_COMMIT_PENDING";
            _knownRemainingCount = 0;
            _knownCloseLease = "";
            _knownLastAppliedOperationId = "";
            _knownLootContainerVersion = -1;
            _knownTerminal = null;
            _knownAuthorityBinding = null;
            _authorityVisualCloseProofBinding = null;
            ClearUnknownLocked();
        }

        private string DowngradeConnectedRecoveryToSocketProof(
            LootPanelCoordinator.Binding binding, string recoveryNonce,
            int closedGeneration)
        {
            lock (_sync)
            {
                if (!_detachedReconcileRequired
                    || _detachedReconcileSocketMode
                    || !ReferenceEquals(_detachedReconcileBinding, binding)
                    || !string.Equals(_detachedReconcileRecoveryNonce, recoveryNonce,
                        StringComparison.Ordinal)) return null;
                if (closedGeneration <= 0
                    || closedGeneration <= _lastSocketDetachGeneration) return null;
                _lastSocketDetachGeneration = closedGeneration;
                CancelDetachedReconcileRetryLocked();
                DropDetachedReconcilePendingLocked();
                _detachedReconcileEpoch++;
                _detachedReconcileTransportGeneration = 0;
                _detachedReconcileRetryAttempt = 0;
                _detachedReconcileRecoveryNonce = Guid.NewGuid().ToString("N");
                _detachedReconcileSocketMode = true;
                return _detachedReconcileRecoveryNonce;
            }
        }

        private bool DetachedReconcileContextMatchesLocked(PendingRequest entry,
            int readyGeneration)
        {
            return entry != null && entry.IsDetachedReconcile
                && !_disposed
                && _detachedReconcileRequired
                && _detachedReconcileBinding != null
                && entry.ReconcileEpoch == _detachedReconcileEpoch
                && entry.TransportGeneration == _detachedReconcileTransportGeneration
                && entry.TransportGeneration > 0
                && entry.TransportGeneration == readyGeneration
                && ReferenceEquals(entry.Binding, _detachedReconcileBinding)
                && entry.IsSocketDetachProof == _detachedReconcileSocketMode
                && string.Equals(entry.RecoveryNonce, _detachedReconcileRecoveryNonce,
                    StringComparison.Ordinal);
        }

        private void DispatchDetachedReconcile(int reconcileEpoch, int transportGeneration)
        {
            if (_disposed || transportGeneration <= 0
                || SafeReadyGeneration() != transportGeneration) return;

            PendingRequest entry;
            JObject flash;
            lock (_sync)
            {
                if (_disposed || !_detachedReconcileRequired
                    || _detachedReconcileBinding == null
                    || !LootPanelCoordinator.IsOpaque(_detachedReconcileRecoveryNonce)
                    || reconcileEpoch != _detachedReconcileEpoch
                    || transportGeneration != _detachedReconcileTransportGeneration
                    || _pending.Count != 0) return;

                entry = new PendingRequest
                {
                    FlashCallId = ++_sequence,
                    WebCallId = "host.detached.reconcile." + _sequence,
                    WebCmd = "query",
                    OperationId = null,
                    IsWrite = false,
                    IsDetachedReconcile = true,
                    ReconcileEpoch = reconcileEpoch,
                    TransportGeneration = transportGeneration,
                    RecoveryNonce = _detachedReconcileRecoveryNonce,
                    IsSocketDetachProof = _detachedReconcileSocketMode,
                    ExpectedAuthorityRevision = Math.Max(0,
                        _detachedReconcileExpectedAuthorityRevision),
                    Binding = _detachedReconcileBinding
                };
                _pending[entry.FlashCallId] = entry;
                _activeCallIds.Add(entry.WebCallId);
                Timer timer = new Timer(delegate { HandleTimeout(entry.FlashCallId); },
                    null, _timeoutMs, Timeout.Infinite);
                _timers[entry.FlashCallId] = timer;
                flash = PanelBridge.BuildFlashCommand("lootQuery", entry.FlashCallId,
                    new JObject
                    {
                        ["v"] = 1,
                        ["chestSessionId"] = entry.Binding.ChestSessionId,
                        ["lootContainerId"] = entry.Binding.LootContainerId,
                        ["containerEpoch"] = entry.Binding.ContainerEpoch
                    });
                flash["openAttemptSeq"] = entry.Binding.OpenAttemptSeq;
                flash["recoveryNonce"] = entry.RecoveryNonce;
            }

            LogManager.Log("event=loot_detached_reconcile_query generation="
                + transportGeneration + " attempt=" + (_detachedReconcileRetryAttempt + 1));
            bool sent = false;
            try
            {
                sent = SafeReadyGeneration() == transportGeneration
                    && _trySendIfGeneration(flash.ToString(Formatting.None) + "\0",
                        transportGeneration);
            }
            catch (Exception ex)
            {
                LogManager.Log("event=loot_detached_reconcile_send_failed type="
                    + ex.GetType().Name);
            }
            if (!sent) HandleSendFailure(entry.FlashCallId);
        }

        private void ScheduleDetachedReconcileRetry(PendingRequest entry)
        {
            if (entry == null) return;
            int readyGeneration = SafeReadyGeneration();
            Timer retryTimer = null;
            int retryDelay;
            lock (_sync)
            {
                if (!DetachedReconcileContextMatchesLocked(entry, readyGeneration)
                    || _pending.Count != 0 || _detachedReconcileRetryTimer != null) return;
                retryDelay = _detachedReconcileRetryInitialMs;
                for (int index = 0; index < _detachedReconcileRetryAttempt
                    && retryDelay < _detachedReconcileRetryMaximumMs; index++)
                {
                    retryDelay = retryDelay > _detachedReconcileRetryMaximumMs / 2
                        ? _detachedReconcileRetryMaximumMs : retryDelay * 2;
                }
                if (_detachedReconcileRetryAttempt < 30)
                    _detachedReconcileRetryAttempt++;
                int reconcileEpoch = entry.ReconcileEpoch;
                int transportGeneration = entry.TransportGeneration;
                retryTimer = new Timer(delegate
                {
                    RunDetachedReconcileRetry(retryTimer, reconcileEpoch,
                        transportGeneration);
                }, null, retryDelay, Timeout.Infinite);
                _detachedReconcileRetryTimer = retryTimer;
            }
            LogManager.Log("event=loot_detached_reconcile_retry delayMs=" + retryDelay);
        }

        private void RunDetachedReconcileRetry(Timer timer, int reconcileEpoch,
            int transportGeneration)
        {
            bool dispatch = false;
            lock (_sync)
            {
                if (!ReferenceEquals(_detachedReconcileRetryTimer, timer)) return;
                _detachedReconcileRetryTimer = null;
                dispatch = !_disposed && _detachedReconcileRequired
                    && _detachedReconcileBinding != null
                    && _pending.Count == 0
                    && reconcileEpoch == _detachedReconcileEpoch
                    && transportGeneration == _detachedReconcileTransportGeneration;
            }
            try { timer.Dispose(); } catch { }
            if (dispatch) DispatchDetachedReconcile(reconcileEpoch, transportGeneration);
        }

        private void CancelDetachedReconcileRetryLocked()
        {
            Timer timer = _detachedReconcileRetryTimer;
            _detachedReconcileRetryTimer = null;
            if (timer != null)
            {
                try { timer.Dispose(); } catch { }
            }
        }

        private void DropDetachedReconcilePendingLocked()
        {
            var stale = new List<int>();
            foreach (KeyValuePair<int, PendingRequest> pair in _pending)
            {
                if (pair.Value.IsDetachedReconcile) stale.Add(pair.Key);
            }
            foreach (int fid in stale)
            {
                PendingRequest entry;
                if (_pending.TryGetValue(fid, out entry)) CompletePendingLocked(fid, entry);
            }
        }

        private void DropNonDetachedPendingLocked()
        {
            var stale = new List<int>();
            foreach (KeyValuePair<int, PendingRequest> pair in _pending)
            {
                if (!pair.Value.IsDetachedReconcile) stale.Add(pair.Key);
            }
            foreach (int fid in stale)
            {
                PendingRequest entry;
                if (!_pending.TryGetValue(fid, out entry)) continue;
                if (entry.IsWrite) MarkUnknownLocked(entry);
                CompletePendingLocked(fid, entry);
            }
        }

        private void NotifyDetachedReconcileSettled()
        {
            Action callback = _detachedReconcileSettled;
            if (callback == null) return;
            Action<Action> invoker = _invokeOnUI;
            if (invoker != null)
            {
                try { invoker(callback); } catch { }
                return;
            }
            try { callback(); } catch { }
        }

        private static bool TryResolveCommand(string cmd, out string action, out bool isWrite)
        {
            isWrite = false;
            switch (cmd)
            {
                case "snapshot": action = "lootSnapshot"; return true;
                case "tooltip": action = "lootTooltip"; return true;
                case "claim": action = "lootClaim"; isWrite = true; return true;
                case "claimBatch": action = "lootClaimBatch"; isWrite = true; return true;
                case "close": action = "lootClose"; isWrite = true; return true;
                case "query": action = "lootQuery"; return true;
                case "materials": action = "lootMaterials"; return true;
                default: action = null; return false;
            }
        }

        private static bool TryNormalizeRequest(JObject parsed, LootPanelCoordinator.Binding binding,
            string cmd, out JObject normalized, out string operationId, out int expectedRevision)
        {
            normalized = null;
            operationId = null;
            expectedRevision = -1;
            HashSet<string> expected = new HashSet<string>(CommonRequestKeys, StringComparer.Ordinal);
            if (cmd == "snapshot")
            {
                expected.Add("loot");
                expected.Add("backpack");
            }
            else if (cmd == "tooltip")
            {
                expected.Add("expectedAuthorityRevision");
                expected.Add("source");
            }
            else if (cmd == "materials")
            {
                expected.Add("expectedAuthorityRevision");
            }
            else if (cmd == "claim" || cmd == "claimBatch")
            {
                expected.Add("expectedAuthorityRevision");
                expected.Add("operationId");
                expected.Add("direction");
                expected.Add(cmd == "claim" ? "source" : "sources");
                expected.Add("targetContainerId");
            }
            else if (cmd == "close")
            {
                expected.Add("expectedAuthorityRevision");
                expected.Add("operationId");
                expected.Add("closeLease");
                expected.Add("abandon");
            }
            if (!HasExactKeys(parsed, expected)
                || ReadString(parsed["type"]) != "task"
                || ReadString(parsed["task"]) != "loot_request"
                || ReadString(parsed["domain"]) != "loot"
                || ReadString(parsed["panel"]) != "loot"
                || ReadString(parsed["cmd"]) != cmd)
                return false;
            int version;
            int epoch;
            if (!TryReadInteger(parsed["v"], 1, 1, out version)
                || !TryReadInteger(parsed["containerEpoch"], 1, int.MaxValue, out epoch)
                || epoch != binding.ContainerEpoch) return false;

            normalized = new JObject
            {
                ["v"] = 1,
                ["chestSessionId"] = binding.ChestSessionId,
                ["lootContainerId"] = binding.LootContainerId,
                ["containerEpoch"] = binding.ContainerEpoch
            };

            if (cmd == "snapshot")
            {
                JObject loot;
                JObject backpack;
                if (!TryNormalizeWindow(parsed["loot"] as JObject, binding.Capacity, true, out loot)
                    || !TryNormalizeWindow(parsed["backpack"] as JObject, 1200, false,
                        out backpack)) return false;
                normalized["loot"] = loot;
                normalized["backpack"] = backpack;
                return true;
            }
            if (cmd == "query") return true;

            if (!TryReadInteger(parsed["expectedAuthorityRevision"], 0, int.MaxValue,
                    out expectedRevision)) return false;
            normalized["expectedAuthorityRevision"] = expectedRevision;
            if (cmd == "materials")
                return binding.SourceKind == LootPanelCoordinator.StageSettlementSource;
            if (cmd == "tooltip" || cmd == "claim")
            {
                JObject source;
                if (!TryNormalizeSourceRef(parsed["source"] as JObject, binding, out source))
                    return false;
                normalized["source"] = source;
                if (cmd == "tooltip") return true;
                operationId = ReadString(parsed["operationId"]);
                if (!LootPanelCoordinator.IsOpaque(operationId)
                    || ReadString(parsed["direction"]) != "loot_to_player"
                    || ReadString(parsed["targetContainerId"]) != "背包") return false;
                normalized["operationId"] = operationId;
                normalized["direction"] = "loot_to_player";
                normalized["targetContainerId"] = "背包";
                return true;
            }

            if (cmd == "claimBatch")
            {
                JArray sources = parsed["sources"] as JArray;
                if (sources == null || sources.Count < 1 || sources.Count > 50) return false;
                JArray cleanSources = new JArray();
                var seenSlots = new HashSet<int>();
                int sourceContainerVersion = -1;
                foreach (JToken token in sources)
                {
                    JObject source;
                    if (!TryNormalizeSourceRef(token as JObject, binding, out source)) return false;
                    int slot = source.Value<int>("slot");
                    int containerVersion = source.Value<int>("expectedContainerVersion");
                    if (!seenSlots.Add(slot)
                        || sourceContainerVersion >= 0
                            && containerVersion != sourceContainerVersion) return false;
                    sourceContainerVersion = containerVersion;
                    cleanSources.Add(source);
                }
                operationId = ReadString(parsed["operationId"]);
                if (!LootPanelCoordinator.IsOpaque(operationId) || operationId.Length > 72
                    || ReadString(parsed["direction"]) != "loot_to_player"
                    || ReadString(parsed["targetContainerId"]) != "背包") return false;
                normalized["operationId"] = operationId;
                normalized["direction"] = "loot_to_player";
                normalized["sources"] = cleanSources;
                normalized["targetContainerId"] = "背包";
                return true;
            }

            operationId = ReadString(parsed["operationId"]);
            string closeLease = ReadString(parsed["closeLease"]);
            bool abandon;
            if (!LootPanelCoordinator.IsOpaque(operationId)
                || !LootPanelCoordinator.IsOpaque(closeLease)
                || !TryReadBoolean(parsed["abandon"], out abandon)) return false;
            normalized["operationId"] = operationId;
            normalized["closeLease"] = closeLease;
            normalized["abandon"] = abandon;
            return true;
        }

        private static bool TryNormalizeWindow(JObject input, int maxCapacity, bool isLoot,
            out JObject normalized)
        {
            normalized = null;
            if (!HasExactKeys(input, Set("offset", "limit"))) return false;
            int offset;
            int limit;
            if (!TryReadInteger(input["offset"], 0, Math.Max(0, maxCapacity - 1), out offset)
                || !TryReadInteger(input["limit"], 1, Math.Min(MaxSnapshotSlots, maxCapacity),
                    out limit)
                || (isLoot && offset + limit > maxCapacity)) return false;
            normalized = new JObject { ["offset"] = offset, ["limit"] = limit };
            return true;
        }

        private static bool TryNormalizeSourceRef(JObject input,
            LootPanelCoordinator.Binding binding, out JObject normalized)
        {
            normalized = null;
            if (!HasExactKeys(input, Set("containerId", "slot", "expectedLease",
                    "expectedContainerVersion"))) return false;
            int slot;
            int version;
            string lease = ReadString(input["expectedLease"]);
            if (ReadString(input["containerId"]) != binding.LootContainerId
                || !TryReadInteger(input["slot"], 0, binding.Capacity - 1, out slot)
                || !LootPanelCoordinator.IsOpaque(lease)
                || !TryReadInteger(input["expectedContainerVersion"], 0, int.MaxValue,
                    out version)) return false;
            normalized = new JObject
            {
                ["containerId"] = binding.LootContainerId,
                ["slot"] = slot,
                ["expectedLease"] = lease,
                ["expectedContainerVersion"] = version
            };
            return true;
        }

        private bool TryReadExactResponseRevisionLocked(JObject msg, PendingRequest entry,
            out int revision)
        {
            revision = -1;
            int callId;
            int epoch;
            return entry != null
                && BindingIdentityMatchesRevisionLocked(entry.Binding)
                && msg != null
                && ReadString(msg["task"]) == "loot_response"
                && TryReadInteger(msg["callId"], 1, int.MaxValue, out callId)
                && callId == entry.FlashCallId
                && ReadString(msg["chestSessionId"]) == entry.Binding.ChestSessionId
                && ReadString(msg["lootContainerId"]) == entry.Binding.LootContainerId
                && TryReadInteger(msg["containerEpoch"], 1, int.MaxValue, out epoch)
                && epoch == entry.Binding.ContainerEpoch
                && TryReadInteger(msg["authorityRevision"], 0, int.MaxValue,
                    out revision);
        }

        private bool TrySanitizeResponse(JObject msg, PendingRequest entry,
            out JObject sanitized, out bool authorityTerminal,
            out bool authoritySuspended)
        {
            sanitized = null;
            authorityTerminal = false;
            authoritySuspended = false;
            if (!BindingIdentityMatchesRevisionLocked(entry != null ? entry.Binding : null)
                || !HasExactKeys(msg, ResponseKeys)
                || ReadString(msg["task"]) != "loot_response") return false;
            bool success;
            int callId;
            int epoch;
            int revision;
            int remaining;
            string error = ReadString(msg["error"]);
            string chestSessionId = ReadString(msg["chestSessionId"]);
            string lootContainerId = ReadString(msg["lootContainerId"]);
            string lastApplied = ReadString(msg["lastAppliedOperationId"]);
            string state = ReadString(msg["state"]);
            string closeLease = ReadString(msg["closeLease"]);
            if (!TryReadInteger(msg["callId"], 1, int.MaxValue, out callId)
                || callId != entry.FlashCallId
                || !TryReadBoolean(msg["success"], out success)
                || !IsSafeWord(error, true)
                || chestSessionId != entry.Binding.ChestSessionId
                || lootContainerId != entry.Binding.LootContainerId
                || !TryReadInteger(msg["containerEpoch"], 1, int.MaxValue, out epoch)
                || epoch != entry.Binding.ContainerEpoch
                || !TryReadInteger(msg["authorityRevision"], 0, int.MaxValue, out revision)
                || revision < entry.ExpectedAuthorityRevision
                || revision < _lastAuthorityRevision
                || lastApplied == null
                || (!string.IsNullOrEmpty(lastApplied)
                    && !LootPanelCoordinator.IsOpaque(lastApplied))
                || !States.Contains(state)
                || !TryReadInteger(msg["remainingCount"], 0, entry.Binding.Capacity, out remaining)
                || closeLease == null
                || (!string.IsNullOrEmpty(closeLease)
                    && !LootPanelCoordinator.IsOpaque(closeLease))) return false;
            if (success != string.IsNullOrEmpty(error)) return false;
            if (success && revision == 0) return false;
            bool commitPending = state == "LOOT_COMMIT_PENDING";
            if (commitPending != (!success && error == "commit_pending")
                || (commitPending && entry.WebCmd != "claim"
                    && entry.WebCmd != "claimBatch" && entry.WebCmd != "query"))
                return false;
            if (success && entry.IsWrite
                && !string.Equals(lastApplied, entry.OperationId, StringComparison.Ordinal))
                return false;
            bool terminalState = state == "CONSUMED" || state == "ABANDONED"
                || state == "EXPIRED";
            if (terminalState && ReferenceEquals(_knownAuthorityBinding, entry.Binding)
                && _knownAuthorityState == "LOOT_ACTIVE"
                && revision <= _lastAuthorityRevision)
                return false;

            JArray snapshots;
            if (!TrySanitizeSnapshots(msg["snapshots"] as JArray, entry.Binding, out snapshots))
                return false;
            JObject tooltip;
            if (!TrySanitizeTooltip(msg["tooltip"], out tooltip)) return false;
            JArray materials;
            if (!TrySanitizeMaterials(msg["materials"], out materials)) return false;
            JObject terminal;
            if (!TrySanitizeTerminal(msg["terminal"], state, remaining, out terminal)) return false;
            authorityTerminal = terminal != null;
            authoritySuspended = state == "LOOT_SUSPENDED";
            if (!TryValidateResponseShape(entry, success, authorityTerminal,
                    authoritySuspended, state, revision, closeLease, snapshots, tooltip,
                    materials, entry.Binding.LootContainerId, remaining)) return false;

            sanitized = new JObject
            {
                ["success"] = success,
                ["error"] = error,
                ["chestSessionId"] = chestSessionId,
                ["lootContainerId"] = lootContainerId,
                ["containerEpoch"] = epoch,
                ["authorityRevision"] = revision,
                ["lastAppliedOperationId"] = lastApplied,
                ["state"] = state,
                ["remainingCount"] = remaining,
                ["closeLease"] = closeLease,
                ["snapshots"] = snapshots,
                ["tooltip"] = tooltip == null ? JValue.CreateNull() : (JToken)tooltip,
                ["materials"] = materials == null ? JValue.CreateNull() : (JToken)materials,
                ["terminal"] = terminal == null ? JValue.CreateNull() : (JToken)terminal
            };
            return true;
        }

        private static bool IsCommitPendingProjection(JObject sanitized)
        {
            return sanitized != null && !sanitized.Value<bool>("success")
                && sanitized.Value<string>("error") == "commit_pending"
                && sanitized.Value<string>("state") == "LOOT_COMMIT_PENDING";
        }

        private bool ShouldPreserveKnownCloseLeaseLocked(PendingRequest entry,
            JObject sanitized)
        {
            // AS2 deliberately returns no close capability on a failure. Preserve the capability
            // already bound to this exact live projection only when the complete authority
            // prestate is unchanged. The error name is not proof of a zero-write outcome.
            JArray snapshots = sanitized != null ? sanitized["snapshots"] as JArray : null;
            return entry != null && sanitized != null
                && !sanitized.Value<bool>("success")
                && ReferenceEquals(_knownAuthorityBinding, entry.Binding)
                && _coordinator.IsCurrentExact(entry.Binding)
                && string.Equals(_knownAuthorityState, "LOOT_ACTIVE",
                    StringComparison.Ordinal)
                && string.Equals(sanitized.Value<string>("state"), _knownAuthorityState,
                    StringComparison.Ordinal)
                && LootPanelCoordinator.IsOpaque(_knownCloseLease)
                && sanitized.Value<int>("authorityRevision") == _lastAuthorityRevision
                && sanitized.Value<int>("remainingCount") == _knownRemainingCount
                && string.Equals(sanitized.Value<string>("lastAppliedOperationId") ?? "",
                    _knownLastAppliedOperationId, StringComparison.Ordinal)
                && string.IsNullOrEmpty(sanitized.Value<string>("closeLease"))
                && snapshots != null && snapshots.Count == 0
                && sanitized["tooltip"] != null
                && sanitized["tooltip"].Type == JTokenType.Null
                && sanitized["materials"] != null
                && sanitized["materials"].Type == JTokenType.Null
                && sanitized["terminal"] != null
                && sanitized["terminal"].Type == JTokenType.Null;
        }

        private static bool TrySanitizeSnapshots(JArray input,
            LootPanelCoordinator.Binding binding, out JArray output)
        {
            output = null;
            if (input == null || input.Count > 2) return false;
            JArray clean = new JArray();
            foreach (JToken token in input)
            {
                JObject snapshot;
                if (!TrySanitizeSnapshot(token as JObject, binding, out snapshot)) return false;
                clean.Add(snapshot);
            }
            output = clean;
            return true;
        }

        private static bool TryValidateResponseShape(PendingRequest entry, bool success,
            bool authorityTerminal, bool authoritySuspended, string state,
            int authorityRevision, string closeLease, JArray snapshots, JObject tooltip,
            JArray materials, string lootContainerId, int remainingCount)
        {
            string cmd = entry.WebCmd;
            if (authoritySuspended && !success) return false;
            if (!success)
            {
                return string.IsNullOrEmpty(closeLease) && snapshots.Count == 0
                    && tooltip == null && materials == null;
            }
            if (cmd == "claim" && !ClaimSuccessMatchesFrozenPrestate(entry, state,
                    authorityRevision, remainingCount, snapshots)) return false;
            if (cmd == "claimBatch" && !ClaimBatchSuccessMatchesFrozenPrestate(entry, state,
                    authorityRevision, remainingCount, snapshots)) return false;
            if (cmd == "close")
            {
                if (!entry.HasKnownClosePrestate
                    || (long)authorityRevision
                        != (long)entry.ExpectedAuthorityRevision + 1L
                    || (long)authorityRevision
                        != (long)entry.CloseAuthorityRevisionBefore + 1L)
                    return false;
                if (entry.CloseRemainingBefore == 0)
                {
                    return authorityTerminal && state == "CONSUMED"
                        && remainingCount == 0
                        && string.IsNullOrEmpty(closeLease)
                        && snapshots.Count == 0 && tooltip == null && materials == null;
                }
                if (entry.CloseAbandon)
                {
                    return authorityTerminal && state == "ABANDONED"
                        && remainingCount == entry.CloseRemainingBefore
                        && string.IsNullOrEmpty(closeLease)
                        && snapshots.Count == 0 && tooltip == null && materials == null;
                }
                return authoritySuspended
                    && remainingCount == entry.CloseRemainingBefore
                    && string.IsNullOrEmpty(closeLease)
                    && snapshots.Count == 0 && tooltip == null && materials == null;
            }
            if (authorityTerminal)
            {
                return cmd == "query"
                    && string.IsNullOrEmpty(closeLease)
                    && snapshots.Count == 0 && tooltip == null && materials == null;
            }
            if (authoritySuspended)
            {
                return cmd == "query"
                    && remainingCount > 0
                    && string.IsNullOrEmpty(closeLease)
                    && snapshots.Count == 0 && tooltip == null && materials == null;
            }
            if (string.IsNullOrEmpty(closeLease)) return false;
            if (cmd == "tooltip")
                return snapshots.Count == 0 && tooltip != null && materials == null;
            if (cmd == "materials")
                return snapshots.Count == 0 && tooltip == null && materials != null;
            if (tooltip != null || materials != null || cmd == "close") return false;
            if (cmd == "snapshot" || cmd == "claim" || cmd == "claimBatch" || cmd == "query")
            {
                if (snapshots.Count != 2) return false;
                bool sawLoot = false;
                bool sawBackpack = false;
                foreach (JToken token in snapshots)
                {
                    string containerId = ReadString(token["containerId"]);
                    if (containerId == "背包")
                    {
                        if (sawBackpack) return false;
                        sawBackpack = true;
                    }
                    else
                    {
                        if (sawLoot || containerId != lootContainerId) return false;
                        int occupied = 0;
                        foreach (JToken slot in token["slots"] as JArray)
                            if (slot.Value<bool>("occupied")) occupied++;
                        if (occupied != remainingCount) return false;
                        sawLoot = true;
                    }
                }
                return sawLoot && sawBackpack;
            }
            return false;
        }

        private static bool ClaimSuccessMatchesFrozenPrestate(PendingRequest entry,
            string state, int authorityRevision, int remainingCount, JArray snapshots)
        {
            if (entry == null || !entry.HasKnownClaimPrestate
                || !string.Equals(state, "LOOT_ACTIVE", StringComparison.Ordinal)
                || (long)authorityRevision != (long)entry.ExpectedAuthorityRevision + 1L
                || (long)authorityRevision != (long)entry.ClaimAuthorityRevisionBefore + 1L
                || entry.ClaimRemainingBefore <= 0
                || remainingCount != entry.ClaimRemainingBefore - 1
                || entry.ClaimPhysicalSlot < 0) return false;

            foreach (JToken token in snapshots)
            {
                JObject snapshot = token as JObject;
                if (snapshot == null || !string.Equals(ReadString(snapshot["containerId"]),
                        entry.Binding.LootContainerId, StringComparison.Ordinal)) continue;
                JArray slots = snapshot["slots"] as JArray;
                if (slots == null) return false;
                foreach (JToken slotToken in slots)
                {
                    JObject slot = slotToken as JObject;
                    if (slot != null && slot.Value<int>("physicalSlot")
                            == entry.ClaimPhysicalSlot)
                        return !slot.Value<bool>("occupied");
                }
                return false;
            }
            return false;
        }

        private static bool ClaimBatchSuccessMatchesFrozenPrestate(PendingRequest entry,
            string state, int authorityRevision, int remainingCount, JArray snapshots)
        {
            if (entry == null || !entry.HasKnownClaimPrestate
                || entry.ClaimBatchPhysicalSlots == null
                || entry.ClaimBatchSourceLeases == null
                || entry.ClaimBatchPhysicalSlots.Length == 0
                || entry.ClaimBatchPhysicalSlots.Length != entry.ClaimBatchSourceLeases.Length
                || !string.Equals(state, "LOOT_ACTIVE", StringComparison.Ordinal)) return false;
            long appliedCount = (long)authorityRevision - entry.ClaimAuthorityRevisionBefore;
            if (appliedCount < 1L || appliedCount > entry.ClaimBatchPhysicalSlots.Length
                || (long)authorityRevision
                    != (long)entry.ExpectedAuthorityRevision + appliedCount
                || remainingCount != entry.ClaimRemainingBefore - (int)appliedCount)
                return false;
            var projection = new JObject { ["snapshots"] = snapshots };
            int emptyRequested;
            int containerVersion;
            return TryInspectClaimBatchProjection(projection,
                entry.Binding.LootContainerId, entry.ClaimBatchPhysicalSlots,
                entry.ClaimBatchSourceLeases, out emptyRequested, out containerVersion)
                && emptyRequested == (int)appliedCount;
        }

        private static bool TrySanitizeSnapshot(JObject input,
            LootPanelCoordinator.Binding binding, out JObject output)
        {
            output = null;
            if (!HasOnlyKeys(input, SnapshotKeys) || !HasRequiredKeys(input, SnapshotRequiredKeys))
                return false;
            string containerId = ReadString(input["containerId"]);
            bool isLoot = containerId == binding.LootContainerId;
            if (!isLoot && containerId != "背包") return false;
            int capacity;
            int accessible;
            int viewCapacity;
            int pageSize;
            int snapshotSeq;
            int epoch;
            int version;
            int offset;
            int limit;
            int filterItemCount;
            int setFilterItemCount;
            bool locked;
            int maxCapacity = isLoot ? binding.Capacity : 1200;
            if (!TryReadInteger(input["capacity"], 1, maxCapacity, out capacity)
                || (isLoot && capacity != binding.Capacity)
                || !TryReadInteger(input["accessibleCapacity"], 0, capacity, out accessible)
                || !TryReadInteger(input["viewCapacity"], 0, capacity, out viewCapacity)
                || ReadString(input["filterKey"]) != "all"
                || !TryReadInteger(input["pageSizeHint"], 1, 100, out pageSize)
                || !TryReadBoolean(input["locked"], out locked)
                || !TryReadInteger(input["snapshotSeq"], 0, int.MaxValue, out snapshotSeq)
                || !TryReadInteger(input["containerEpoch"], 1, int.MaxValue, out epoch)
                || (isLoot && epoch != binding.ContainerEpoch)
                || !TryReadInteger(input["containerVersion"], 0, int.MaxValue, out version)
                || !TryReadInteger(input["offset"], 0, Math.Max(0, capacity - 1), out offset)
                || !TryReadInteger(input["limit"], 0, MaxSnapshotSlots, out limit)
                || !TryReadInteger(input["filterItemCount"], 0, capacity, out filterItemCount)
                || !TryReadInteger(input["setFilterItemCount"], 0, capacity,
                    out setFilterItemCount)
                || input.Property("filterSpec") != null
                || (isLoot && (accessible != capacity || viewCapacity != capacity
                    || offset != 0 || limit != capacity || locked))) return false;

            JArray slots;
            if (!TrySanitizeSlots(input["slots"] as JArray, capacity, offset, limit, isLoot,
                    out slots)) return false;
            JArray facets;
            JArray setFacets;
            if (!TrySanitizeFacets(input["filterFacets"] as JArray, 0, out facets)
                || !TrySanitizeFacets(input["setFacets"] as JArray, 0, out setFacets)) return false;
            output = new JObject
            {
                ["containerId"] = containerId,
                ["capacity"] = capacity,
                ["accessibleCapacity"] = accessible,
                ["viewCapacity"] = viewCapacity,
                ["filterKey"] = ReadString(input["filterKey"]),
                ["pageSizeHint"] = pageSize,
                ["locked"] = locked,
                ["snapshotSeq"] = snapshotSeq,
                ["containerEpoch"] = epoch,
                ["containerVersion"] = version,
                ["offset"] = offset,
                ["limit"] = limit,
                ["slots"] = slots,
                ["filterFacets"] = facets,
                ["filterItemCount"] = filterItemCount,
                ["setFacets"] = setFacets,
                ["setFilterItemCount"] = setFilterItemCount
            };
            return true;
        }

        private static bool TrySanitizeSlots(JArray input, int capacity, int offset,
            int expectedCount, bool isLoot, out JArray output)
        {
            output = null;
            if (input == null || input.Count != expectedCount || input.Count > MaxSnapshotSlots)
                return false;
            JArray clean = new JArray();
            HashSet<int> seen = new HashSet<int>();
            foreach (JToken token in input)
            {
                JObject slot = token as JObject;
                if (slot == null) return false;
                bool occupied;
                int physical;
                string lease = ReadString(slot["slotLease"]);
                if (!TryReadBoolean(slot["occupied"], out occupied)
                    || !TryReadInteger(slot["physicalSlot"], 0, capacity - 1, out physical)
                    || physical < offset || physical >= offset + expectedCount
                    || !seen.Add(physical)
                    || !LootPanelCoordinator.IsOpaque(lease)) return false;
                HashSet<string> expected = occupied
                    ? (isLoot
                        ? Set("physicalSlot", "occupied", "slotLease", "item")
                        : Set("physicalSlot", "occupied", "slotLease", "item",
                            "confirmProjection"))
                    : Set("physicalSlot", "occupied", "slotLease");
                if (!HasExactKeys(slot, expected)) return false;
                JObject row = new JObject
                {
                    ["physicalSlot"] = physical,
                    ["occupied"] = occupied,
                    ["slotLease"] = lease
                };
                if (occupied)
                {
                    JObject item;
                    if (!TrySanitizeItem(slot["item"] as JObject, out item)) return false;
                    row["item"] = item;
                    if (!isLoot)
                    {
                        JObject confirm;
                        if (!TrySanitizeConfirm(
                                slot["confirmProjection"] as JObject,
                                item,
                                out confirm))
                            return false;
                        row["confirmProjection"] = confirm;
                    }
                }
                clean.Add(row);
            }
            output = clean;
            return true;
        }

        private static bool TrySanitizeItem(JObject input, out JObject output)
        {
            output = null;
            if (!HasExactKeys(input, ItemKeys)) return false;
            JObject row = new JObject();
            string[] strings = { "name", "displayName", "icon", "majorType", "use", "actionType",
                "weaponType", "setId", "setName", "itemKind", "rarity" };
            foreach (string key in strings)
            {
                string value;
                bool identity = key == "name" || key == "displayName" || key == "icon";
                if (!TryReadBoundedText(input[key], 256, !identity, out value)
                    || (identity && !IsIdentityText(value))) return false;
                row[key] = value;
            }
            if (ReadString(input["itemKind"]) != "equipment"
                && ReadString(input["itemKind"]) != "stack") return false;
            string[] integers = { "setOrder", "enhancementLevel", "maxEnhancementLevel",
                "modSlotCapacity", "modSlotUsed" };
            foreach (string key in integers)
            {
                int value;
                if (!TryReadInteger(input[key], 0, int.MaxValue, out value)) return false;
                row[key] = value;
            }
            long quantity;
            if (!TryReadLongInteger(input["quantity"], 0, MaxSafeInteger, out quantity))
                return false;
            row["quantity"] = quantity;
            string[] booleans = { "isMaxEnhancement", "tierSlotAvailable", "tierSlotUsed" };
            foreach (string key in booleans)
            {
                bool value;
                if (!TryReadBoolean(input[key], out value)) return false;
                row[key] = value;
            }
            JArray mods;
            if (!TrySanitizeMods(input["modSlots"] as JArray, out mods)) return false;
            row["modSlots"] = mods;
            if (input["modMeta"] == null || input["modMeta"].Type == JTokenType.Null)
                row["modMeta"] = JValue.CreateNull();
            else
            {
                JObject meta;
                if (!TrySanitizeMod(input["modMeta"] as JObject, out meta)) return false;
                row["modMeta"] = meta;
            }
            output = row;
            return true;
        }

        private static bool TrySanitizeConfirm(
            JObject input,
            JObject item,
            out JObject output)
        {
            output = null;
            if (!HasExactKeys(input, ConfirmKeys) || item == null) return false;
            JObject row = new JObject();
            string[] strings = { "itemKind", "name", "displayName", "rarity", "tier", "modSignature" };
            foreach (string key in strings)
            {
                string value;
                bool identity = key == "name" || key == "displayName";
                if (!TryReadBoundedText(
                        input[key], key == "modSignature" ? 1024 : 256,
                        !identity, out value)
                    || (identity && !IsIdentityText(value))) return false;
                row[key] = value;
            }
            long quantity;
            int level;
            long lastUpdate;
            if (!TryReadLongInteger(input["quantity"], 0, MaxSafeInteger, out quantity)
                || !TryReadInteger(input["enhancementLevel"], 0, int.MaxValue, out level)
                || !TryReadLongInteger(input["lastUpdate"], 0, MaxSafeInteger,
                    out lastUpdate)
                || row.Value<string>("itemKind") != item.Value<string>("itemKind")
                || row.Value<string>("name") != item.Value<string>("name")
                || row.Value<string>("displayName") != item.Value<string>("displayName")
                || row.Value<string>("rarity") != item.Value<string>("rarity")
                || quantity != item.Value<long>("quantity")
                || level != item.Value<int>("enhancementLevel")) return false;
            row["quantity"] = quantity;
            row["enhancementLevel"] = level;
            row["lastUpdate"] = lastUpdate;
            output = row;
            return true;
        }

        private static bool TrySanitizeMods(JArray input, out JArray output)
        {
            output = null;
            if (input == null || input.Count > 3) return false;
            JArray clean = new JArray();
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
            if (!HasExactKeys(input, ModKeys)) return false;
            JObject row = new JObject();
            foreach (string key in ModKeys)
            {
                string value;
                bool identity = key == "name" || key == "displayName" || key == "icon";
                if (!TryReadBoundedText(input[key], identity ? 256 : 128, !identity, out value)
                    || (identity && !IsIdentityText(value))) return false;
                row[key] = value;
            }
            output = row;
            return true;
        }

        private static bool TrySanitizeFacets(JArray input, int depth, out JArray output)
        {
            output = null;
            if (input == null || input.Count > 64 || depth > 3) return false;
            JArray clean = new JArray();
            foreach (JToken token in input)
            {
                JObject node = token as JObject;
                if (!HasExactKeys(node, Set("id", "label", "order", "count", "children")))
                    return false;
                string id;
                string label;
                int order;
                int count;
                JArray children;
                if (!TryReadBoundedText(node["id"], 128, true, out id)
                    || !TryReadBoundedText(node["label"], 128, true, out label)
                    || !TryReadInteger(node["order"], 0, int.MaxValue, out order)
                    || !TryReadInteger(node["count"], 0, 1200, out count)
                    || !TrySanitizeFacets(node["children"] as JArray, depth + 1, out children))
                    return false;
                clean.Add(new JObject
                {
                    ["id"] = id, ["label"] = label, ["order"] = order,
                    ["count"] = count, ["children"] = children
                });
            }
            output = clean;
            return true;
        }

        private static bool TrySanitizeFilterSpec(JToken token, out JObject output)
        {
            output = null;
            if (token == null || token.Type == JTokenType.Null) return true;
            JObject input = token as JObject;
            if (input == null) return false;
            if (input.Value<string>("branch") == "set")
            {
                if (!HasExactKeys(input, Set("branch", "setId"))) return false;
                string setId;
                if (!TryReadBoundedText(input["setId"], 64, true, out setId)) return false;
                output = new JObject { ["branch"] = "set", ["setId"] = setId };
                return true;
            }
            if (!HasOnlyKeys(input, Set("branch", "major", "use", "subtype"))
                || input.Value<string>("branch") != "category") return false;
            string major;
            string use;
            string subtype;
            if (!TryReadBoundedText(input["major"], 64, false, out major)
                || !TryReadBoundedText(input["use"], 64, true, out use)
                || !TryReadBoundedText(input["subtype"], 64, true, out subtype)) return false;
            output = new JObject { ["branch"] = "category", ["major"] = major };
            if (input.Property("use") != null) output["use"] = use;
            if (input.Property("subtype") != null) output["subtype"] = subtype;
            return true;
        }

        private static bool TrySanitizeTooltip(JToken token, out JObject output)
        {
            output = null;
            if (token == null || token.Type == JTokenType.Null) return true;
            JObject input = token as JObject;
            HashSet<string> keys = Set("itemName", "displayname", "iconName", "itemType",
                "descHTML", "introHTML");
            if (!HasExactKeys(input, keys)) return false;
            JObject clean = new JObject();
            foreach (string key in keys)
            {
                string value;
                int max = key == "descHTML" || key == "introHTML" ? 32768 : 256;
                if (!TryReadBoundedText(input[key], max, true, out value)) return false;
                clean[key] = value;
            }
            output = clean;
            return true;
        }

        private static bool TrySanitizeMaterials(JToken token, out JArray output)
        {
            output = null;
            if (token == null || token.Type == JTokenType.Null) return true;
            JArray input = token as JArray;
            if (input == null || input.Count > 4096) return false;
            JArray clean = new JArray();
            HashSet<string> names = new HashSet<string>(StringComparer.Ordinal);
            foreach (JToken entry in input)
            {
                JObject material = entry as JObject;
                string name;
                string displayName;
                string icon;
                long owned;
                if (!HasExactKeys(material, MaterialKeys)
                    || !TryReadBoundedText(material["name"], 128, false, out name)
                    || !TryReadBoundedText(material["displayName"], 256, false,
                        out displayName)
                    || !TryReadBoundedText(material["icon"], 256, false, out icon)
                    || !TryReadLongInteger(material["owned"], 0, MaxSafeInteger,
                        out owned)
                    || !names.Add(name))
                    return false;
                clean.Add(new JObject
                {
                    ["name"] = name,
                    ["displayName"] = displayName,
                    ["icon"] = icon,
                    ["owned"] = owned
                });
            }
            output = clean;
            return true;
        }

        private static bool TrySanitizeTerminal(JToken token, string state, int remaining,
            out JObject output)
        {
            output = null;
            bool terminalState = state == "CONSUMED" || state == "ABANDONED" || state == "EXPIRED";
            if (token == null || token.Type == JTokenType.Null) return !terminalState;
            JObject input = token as JObject;
            if (!terminalState || !HasExactKeys(input, Set("kind", "reason", "remainingCount")))
                return false;
            string kind = ReadString(input["kind"]);
            string reason = ReadString(input["reason"]);
            int terminalRemaining;
            if (kind != state || !IsSafeWord(reason, false)
                || !TryReadInteger(input["remainingCount"], 0, int.MaxValue,
                    out terminalRemaining)
                || terminalRemaining != remaining
                || kind == "CONSUMED" && terminalRemaining != 0
                || kind == "ABANDONED" && terminalRemaining <= 0) return false;
            output = new JObject
            {
                ["kind"] = kind,
                ["reason"] = reason,
                ["remainingCount"] = terminalRemaining
            };
            return true;
        }

        private void PostSanitizedResponse(PendingRequest entry, JObject authority)
        {
            JObject response = (JObject)authority.DeepClone();
            response["type"] = "panel_resp";
            response["task"] = "loot_response";
            response["domain"] = "loot";
            response["panel"] = "loot";
            response["cmd"] = entry.WebCmd;
            response["callId"] = entry.WebCallId;
            response["panelInstanceId"] = entry.Binding.PanelInstanceId;
            PostToWeb(response.ToString(Formatting.None));
        }

        private void RejectAndRemember(LootPanelCoordinator.Binding binding, string callId,
            string cmd, string error)
        {
            lock (_sync)
            {
                if (_activeCallIds.Contains(callId) || _recentCallIds.Contains(callId)) return;
                RememberRecentLocked(callId);
            }
            RespondError(binding, callId, cmd, error);
        }

        private void RespondError(LootPanelCoordinator.Binding binding, string callId,
            string cmd, string error)
        {
            if (binding == null || !_coordinator.IsCurrentExact(binding)) return;
            int authorityRevision = 0;
            int remainingCount = 0;
            string authorityState = "LOOT_COMMIT_PENDING";
            string lastAppliedOperationId = "";
            JObject terminal = null;
            lock (_sync)
            {
                bool sameIdentity = string.Equals(_revisionChestSessionId,
                        binding.ChestSessionId, StringComparison.Ordinal)
                    && string.Equals(_revisionLootContainerId, binding.LootContainerId,
                        StringComparison.Ordinal)
                    && _revisionContainerEpoch == binding.ContainerEpoch
                    && _revisionOpenAttemptSeq == binding.OpenAttemptSeq;
                if (sameIdentity)
                {
                    bool sameUnknownIdentity = _writeState == "reconcile_required"
                        && string.Equals(_unknownChestSessionId,
                            binding.ChestSessionId, StringComparison.Ordinal)
                        && string.Equals(_unknownLootContainerId,
                            binding.LootContainerId, StringComparison.Ordinal)
                        && _unknownContainerEpoch == binding.ContainerEpoch
                        && _unknownOpenAttemptSeq == binding.OpenAttemptSeq;
                    authorityRevision = sameUnknownIdentity
                        ? Math.Max(_lastAuthorityRevision, _unknownFreshnessWatermark)
                        : _lastAuthorityRevision;
                    remainingCount = _knownRemainingCount;
                    authorityState = _knownAuthorityState;
                    lastAppliedOperationId = _knownLastAppliedOperationId;
                    terminal = _knownTerminal == null
                        ? null : (JObject)_knownTerminal.DeepClone();
                }
            }
            JObject response = new JObject
            {
                ["type"] = "panel_resp",
                ["task"] = "loot_response",
                ["domain"] = "loot",
                ["panel"] = "loot",
                ["cmd"] = cmd ?? "",
                ["callId"] = callId ?? "",
                ["panelInstanceId"] = binding.PanelInstanceId,
                ["chestSessionId"] = binding.ChestSessionId,
                ["lootContainerId"] = binding.LootContainerId,
                ["containerEpoch"] = binding.ContainerEpoch,
                ["success"] = false,
                ["error"] = error,
                ["authorityRevision"] = authorityRevision,
                ["lastAppliedOperationId"] = lastAppliedOperationId,
                ["state"] = authorityState,
                ["remainingCount"] = remainingCount,
                ["closeLease"] = "",
                ["snapshots"] = new JArray(),
                ["tooltip"] = JValue.CreateNull(),
                ["materials"] = JValue.CreateNull(),
                ["terminal"] = terminal == null ? JValue.CreateNull() : (JToken)terminal
            };
            PostToWeb(response.ToString(Formatting.None));
        }

        private void RememberRecentLocked(string callId)
        {
            if (string.IsNullOrEmpty(callId) || !_recentCallIds.Add(callId)) return;
            _recentCallIdOrder.Enqueue(callId);
            while (_recentCallIdOrder.Count > RecentCallIdCapacity)
                _recentCallIds.Remove(_recentCallIdOrder.Dequeue());
        }

        private void PostToWeb(string json)
        {
            if (_invokeOnUI != null)
                _invokeOnUI(delegate { if (_postToWeb != null) _postToWeb(json); });
            else if (_postToWeb != null) _postToWeb(json);
        }

        private static string ReadString(JToken token)
        {
            return token != null && token.Type == JTokenType.String ? token.Value<string>() : null;
        }

        private static bool IsCallId(string value)
        {
            if (string.IsNullOrEmpty(value) || value.Length > 96) return false;
            for (int i = 0; i < value.Length; i++)
            {
                char c = value[i];
                bool allowed = char.IsLetterOrDigit(c) || c == '.' || c == '_' || c == '-';
                if (!allowed) return false;
            }
            return true;
        }

        private static bool TryReadInteger(JToken token, int min, int max, out int value)
        {
            value = 0;
            if (token == null || token.Type != JTokenType.Integer) return false;
            long candidate;
            try { candidate = token.Value<long>(); }
            catch (Exception) { return false; }
            if (candidate < min || candidate > max) return false;
            value = (int)candidate;
            return true;
        }

        private static bool TryReadLongInteger(JToken token, long min, long max, out long value)
        {
            value = 0;
            if (token == null || token.Type != JTokenType.Integer) return false;
            long candidate;
            try { candidate = token.Value<long>(); }
            catch (Exception) { return false; }
            if (candidate < min || candidate > max) return false;
            value = candidate;
            return true;
        }

        private static bool TryReadBoolean(JToken token, out bool value)
        {
            value = false;
            if (token == null || token.Type != JTokenType.Boolean) return false;
            value = token.Value<bool>();
            return true;
        }

        private static bool TryReadBoundedText(JToken token, int maxLength, bool allowEmpty,
            out string value)
        {
            value = ReadString(token);
            if (value == null || value.Length > maxLength || (!allowEmpty && value.Length == 0))
                return false;
            for (int i = 0; i < value.Length; i++) if (value[i] == '\0') return false;
            return true;
        }

        private static bool IsIdentityText(string value)
        {
            return !string.IsNullOrWhiteSpace(value)
                && !string.Equals(
                    value.Trim(), "undefined", StringComparison.OrdinalIgnoreCase);
        }

        private static bool IsSafeWord(string value, bool allowEmpty)
        {
            if (value == null || value.Length > 64 || (!allowEmpty && value.Length == 0)) return false;
            if (value.Length == 0) return allowEmpty;
            if (value[0] < 'a' || value[0] > 'z') return false;
            for (int i = 0; i < value.Length; i++)
            {
                char c = value[i];
                bool allowed = (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_';
                if (!allowed) return false;
            }
            return true;
        }

        private static bool IsFilterKey(string value)
        {
            return value == "all" || value == "weapon" || value == "armor"
                || value == "consumable" || value == "material" || value == "other";
        }

        private static HashSet<string> Set(params string[] values)
        {
            return new HashSet<string>(values, StringComparer.Ordinal);
        }

        private static bool HasExactKeys(JObject value, HashSet<string> expected)
        {
            return value != null && value.Count == expected.Count && HasOnlyKeys(value, expected);
        }

        private static bool HasOnlyKeys(JObject value, HashSet<string> allowed)
        {
            if (value == null) return false;
            foreach (JProperty property in value.Properties())
                if (!allowed.Contains(property.Name)) return false;
            return true;
        }

        private static bool HasRequiredKeys(JObject value, HashSet<string> required)
        {
            if (value == null) return false;
            foreach (string key in required) if (value.Property(key) == null) return false;
            return true;
        }
    }
}
