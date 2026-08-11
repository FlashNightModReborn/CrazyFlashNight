using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text.RegularExpressions;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using CF7Launcher.Bus;
using CF7Launcher.Tasks;

namespace CF7Launcher.Guardian
{
    /// <summary>
    /// Strict workbench/loadout WebView↔Flash bridge and close-barrier state kernel.
    /// Host owns the Web response identity, exact panel binding, delivery classification and
    /// write/reconcile watermarks. AS2 owns the session generation and loadout projections.
    /// </summary>
    public sealed partial class CharacterBuildTask : IDisposable
    {
        private enum UnknownKind
        {
            None,
            Mutation,
            FlushLive,
            Finalize
        }

        private enum MutationTarget
        {
            None,
            Equipment,
            Drug
        }

        private sealed class PendingRequest
        {
            public int BackendCallId;
            public string PanelInstanceId;
            public int BindingEpoch;
            public long? SessionGeneration;
            public string WebCallId;
            public string Command;
            public string FlashAction;
            public string ReconcileAfterCallId;
            public JObject NormalizedPayload;
            public bool PostToWeb;
            public bool IsInitialSnapshot;
            public bool IsInitialRetry;
            public bool IsReconcileSnapshot;
            public bool IsWrite;
            public int WriteEpoch;
            public int ReconcileTargetEpoch;
            public UnknownKind ReconcileTargetKind;
            public UnknownKind Kind;
            public MutationTarget MutationTarget;
            public long ExpectedLoadoutRevision;
            public long ExpectedLiveRevision;
            public long ExpectedDrugRevision;
            public long RequestedLoadoutRevision;
            public long RequestedDrugRevision;
            public bool IsDetachRecovery;
            public int RecoveryEpoch;
            public int TransportGeneration;
            public long CandidateTooltipEpoch;
        }

        private const int DefaultTimeoutMs = 10000;
        private const int MaxPending = 24;
        private const int MaxCandidateRows = 50;
        private const int MaxCandidatePhysicalSlot = 49;

        private static readonly Regex ValidCallId = new Regex(
            "^[A-Za-z0-9._-]{1,96}$",
            RegexOptions.CultureInvariant | RegexOptions.Compiled);
        private static readonly Regex ValidOpaque = new Regex(
            "^[A-Za-z0-9._~-]{1,128}$",
            RegexOptions.CultureInvariant | RegexOptions.Compiled);
        private static readonly HashSet<string> TopLevelKeys = Set(
            "type", "panel", "domain", "cmd", "callId", "panelInstanceId", "payload");
        private static readonly HashSet<string> CommonResponseKeys = Set(
            "task", "callId", "v", "success", "command", "requestCallId",
            "panelInstanceId", "writeEpoch", "active", "sessionGeneration",
            "loadoutRevision", "liveRevision", "liveRefreshDirty", "drugRevision");
        private static readonly HashSet<string> CandidateBlockedReasons = Set(
            "level_locked", "cooldown_active", "cooldown_unavailable",
            "incompatible_item");

        private readonly object _gate = new object();
        private readonly object _bindingGate = new object();
        private readonly PanelPendingCallTracker<PendingRequest> _pendingCalls;
        private readonly Dictionary<int, PendingRequest> _productionPending =
            new Dictionary<int, PendingRequest>();
        private readonly Func<int> _getReadyGeneration;
        private readonly Func<string, int, bool> _trySendIfGeneration;
        private readonly Func<int, bool> _forceCloseIfGeneration;

        private Action<string> _postToWeb;
        private Action<Action> _invokeOnUI;
        private Action _onCoordinatorSettled;
        private Action<string, string> _onDetachRecoveryBlocked;
        private Func<bool> _admissionGate;
        private string _panelInstanceId;
        private int _bindingEpoch;
        private bool _bindingChanging;
        private long? _sessionGeneration;
        private bool _initialSnapshotOutcomeUnknown;
        private string _writeState = "idle";
        private int _writeEpoch;
        private int _pendingCount;
        private string _unknownCallId;
        private int _unknownEpoch;
        private UnknownKind _unknownKind;
        private long _loadoutRevision;
        private long _liveRevision;
        private long _drugRevision;
        private bool _liveRefreshDirty;
        private bool _finalizePersistenceProven;
        private long _finalizedLoadoutRevision = -1;
        private long _finalizedLiveRevision = -1;
        private long _finalizedDrugRevision = -1;
        private long _candidateTooltipEpoch;
        private readonly HashSet<string> _candidateTooltipSources =
            new HashSet<string>(StringComparer.Ordinal);
        private bool _disposed;

        public CharacterBuildTask(XmlSocketServer socket)
            : this(
                delegate { return socket != null && socket.IsClientReady; },
                delegate(string payload) { return socket != null && socket.TrySend(payload); },
                DefaultTimeoutMs,
                delegate
                {
                    int generation;
                    return socket != null
                        && socket.TryGetReadyGeneration(out generation)
                        ? generation : 0;
                },
                delegate(string payload, int generation)
                {
                    return socket != null
                        && socket.TrySendIfGen(payload, generation);
                },
                delegate(int generation)
                {
                    return socket != null
                        && socket.ForceCloseCurrentClientIfGen(generation);
                })
        {
        }

        public CharacterBuildTask(Func<string, bool> trySend, int timeoutMs = DefaultTimeoutMs)
            : this(delegate { return true; }, trySend, timeoutMs)
        {
        }

        public CharacterBuildTask(
            Func<bool> isClientReady,
            Func<string, bool> trySend,
            int timeoutMs = DefaultTimeoutMs)
            : this(
                isClientReady,
                trySend,
                timeoutMs,
                delegate { return isClientReady != null && isClientReady() ? 1 : 0; },
                delegate(string payload, int generation)
                {
                    return generation == 1 && trySend != null && trySend(payload);
                },
                delegate { return false; })
        {
        }

        internal CharacterBuildTask(
            Func<bool> isClientReady,
            Func<string, bool> trySend,
            int timeoutMs,
            Func<int> getReadyGeneration,
            Func<string, int, bool> trySendIfGeneration,
            Func<int, bool> forceCloseIfGeneration)
        {
            Func<bool> ready = isClientReady ?? delegate { return false; };
            Func<string, bool> send = trySend ?? delegate { return false; };
            _getReadyGeneration = getReadyGeneration
                ?? delegate { return ready() ? 1 : 0; };
            _trySendIfGeneration = trySendIfGeneration
                ?? delegate(string payload, int generation)
                {
                    return generation > 0
                        && generation == SafeReadyGeneration()
                        && send(payload);
                };
            _forceCloseIfGeneration =
                forceCloseIfGeneration ?? delegate { return false; };
            _pendingCalls = new PanelPendingCallTracker<PendingRequest>(
                ready,
                send,
                Math.Max(1, timeoutMs),
                HandlePendingEnded);
        }

        public void SetPostToWeb(Action<string> post) { _postToWeb = post; }
        public void SetInvoker(Action<Action> invoker) { _invokeOnUI = invoker; }
        public void SetCoordinatorSettled(Action callback) { _onCoordinatorSettled = callback; }
        public void SetDetachRecoveryBlocked(
            Action<string, string> callback)
        {
            _onDetachRecoveryBlocked = callback;
        }
        internal void SetAdmissionGate(
            Func<bool> gate)
        {
            _admissionGate = gate;
        }

        internal string PanelInstanceId { get { lock (_gate) return _panelInstanceId; } }
        internal long? SessionGeneration { get { lock (_gate) return _sessionGeneration; } }
        internal string WriteState { get { lock (_gate) return _writeState; } }
        internal int WriteEpoch { get { lock (_gate) return _writeEpoch; } }
        internal int PendingCount { get { lock (_gate) return _pendingCount; } }
        internal string ReconcileAfterCallId { get { lock (_gate) return _unknownCallId; } }
        internal long LoadoutRevision { get { lock (_gate) return _loadoutRevision; } }
        internal long LiveRevision { get { lock (_gate) return _liveRevision; } }
        internal long DrugRevision { get { lock (_gate) return _drugRevision; } }
        internal bool LiveRefreshDirty { get { lock (_gate) return _liveRefreshDirty; } }
        internal long CandidateTooltipEpoch
        {
            get { lock (_gate) return _candidateTooltipEpoch; }
        }
        public bool HasBoundPanel
        {
            get { lock (_gate) return !_disposed && !string.IsNullOrEmpty(_panelInstanceId); }
        }
        public bool CanRebind
        {
            get { lock (_gate) return CanReleaseBindingLocked(); }
        }
        internal bool RequiresDetachRecovery
        {
            get { lock (_gate) return !_disposed && _detachRecoveryRequired; }
        }
        internal string DetachRecoveryStatus
        {
            get { lock (_gate) return _detachRecoveryStatus; }
        }
        internal string DetachRecoveryFailure
        {
            get { lock (_gate) return _detachRecoveryFailure; }
        }
        public bool BlocksPauseReleaseAfterDisconnect
        {
            get
            {
                lock (_gate)
                    return !_disposed && !string.IsNullOrEmpty(_panelInstanceId)
                        && !CanReleaseBindingLocked();
            }
        }
        internal bool CanClose
        {
            get { lock (_gate) return HasFinalizeProofLocked(); }
        }

        public bool IsBoundTo(string panelInstanceId)
        {
            lock (_gate)
                return !_disposed && IsOpaque(panelInstanceId)
                    && string.Equals(
                        _panelInstanceId, panelInstanceId, StringComparison.Ordinal);
        }

        /// <summary>
        /// Grants a read-only tooltip capability only for a source emitted by the most recently
        /// accepted candidates projection. The returned fence is rechecked when InventoryTask
        /// completes, so a snapshot, write, candidates refresh or panel replacement revokes an
        /// already-sent tooltip without exposing its rich payload.
        /// </summary>
        internal bool TryCaptureCandidateTooltipFence(
            string panelInstanceId,
            long sessionGeneration,
            JObject source,
            out JObject normalizedSource,
            out Func<bool> completionFence)
        {
            normalizedSource = null;
            completionFence = null;
            JObject normalized;
            if (!CanAdmitRequest()
                || !CharacterBuildProtocol.TryNormalizeBackpackSource(
                    source, out normalized))
            {
                return false;
            }

            string sourceKey = CandidateTooltipSourceKey(normalized);
            int bindingEpoch;
            long tooltipEpoch;
            lock (_gate)
            {
                if (_disposed || _bindingChanging || _detachRecoveryRequired
                    || _writeState != "idle"
                    || !_sessionGeneration.HasValue
                    || _sessionGeneration.Value != sessionGeneration
                    || !string.Equals(
                        _panelInstanceId, panelInstanceId, StringComparison.Ordinal)
                    || !_candidateTooltipSources.Contains(sourceKey))
                {
                    return false;
                }
                bindingEpoch = _bindingEpoch;
                tooltipEpoch = _candidateTooltipEpoch;
                normalizedSource = (JObject)normalized.DeepClone();
            }

            completionFence = delegate
            {
                lock (_gate)
                {
                    return !_disposed && !_bindingChanging
                        && !_detachRecoveryRequired
                        && _writeState == "idle"
                        && _bindingEpoch == bindingEpoch
                        && _candidateTooltipEpoch == tooltipEpoch
                        && _sessionGeneration.HasValue
                        && _sessionGeneration.Value == sessionGeneration
                        && string.Equals(
                            _panelInstanceId,
                            panelInstanceId,
                            StringComparison.Ordinal)
                        && _candidateTooltipSources.Contains(sourceKey);
                }
            };
            return true;
        }

        /// <summary>
        /// Host panel replacement is an authority boundary. Old pending calls remain recent in the
        /// bounded tracker, but their callbacks cannot mutate the replacement session.
        /// </summary>
        public bool BindPanelInstance(string panelInstanceId)
        {
            if (!IsOpaque(panelInstanceId)) return false;
            if (!CanAdmitRequest()) return false;
            lock (_bindingGate)
            {
                int boundEpoch;
                lock (_gate)
                {
                    if (_disposed) return false;
                    if (string.Equals(
                        _panelInstanceId, panelInstanceId, StringComparison.Ordinal))
                    {
                        return !_detachRecoveryRequired;
                    }
                    _bindingChanging = true;
                    _bindingEpoch++;
                    boundEpoch = _bindingEpoch;
                    _panelInstanceId = panelInstanceId;
                    ResetSessionLocked();
                }
                try
                {
                    _pendingCalls.Clear();
                }
                finally
                {
                    lock (_gate) _bindingChanging = false;
                }
                LogPanelBound(
                    panelInstanceId,
                    boundEpoch);
            }
            return true;
        }

        /// <summary>
        /// Production binding never replaces a retained Host instance. Even a finalized session
        /// still owns its exact AS2 pause authority; finalize proof authorizes the acknowledged
        /// close handoff, not a silent same-name rebind.
        /// </summary>
        public bool TryBindPanelInstance(string panelInstanceId)
        {
            if (!IsOpaque(panelInstanceId)) return false;
            if (!CanAdmitRequest()) return false;
            lock (_bindingGate)
            {
                int boundEpoch;
                lock (_gate)
                {
                    if (_disposed || _bindingChanging) return false;
                    if (string.Equals(
                        _panelInstanceId, panelInstanceId, StringComparison.Ordinal))
                    {
                        return !_detachRecoveryRequired;
                    }
                    // A releasable/finalized binding still owns the exact AS2 pause authority.
                    // Production may replace it only after acknowledged Host recovery consumes
                    // that binding; silently rebinding here loses the only safe release identity.
                    if (!string.IsNullOrEmpty(_panelInstanceId))
                        return false;
                    _bindingChanging = true;
                    _bindingEpoch++;
                    boundEpoch = _bindingEpoch;
                    _panelInstanceId = panelInstanceId;
                    ResetSessionLocked();
                }
                try
                {
                    _pendingCalls.Clear();
                }
                finally
                {
                    lock (_gate) _bindingChanging = false;
                }
                LogPanelBound(
                    panelInstanceId,
                    boundEpoch);
            }
            return true;
        }

        /// <summary>
        /// A normal close consumes either an unopened/definitively rejected binding or a terminal
        /// finalize proof. Rebinding to the same panel id then starts from a fresh baseline.
        /// </summary>
        public bool TryClosePanelInstance(string panelInstanceId)
        {
            lock (_bindingGate)
            {
                lock (_gate)
                {
                    if (_disposed
                        || !string.Equals(
                            _panelInstanceId, panelInstanceId, StringComparison.Ordinal)
                        || !CanReleaseBindingLocked())
                    {
                        return false;
                    }
                    _bindingChanging = true;
                    _bindingEpoch++;
                    _panelInstanceId = null;
                    ResetSessionLocked();
                }
                try
                {
                    _pendingCalls.Clear();
                }
                finally
                {
                    lock (_gate) _bindingChanging = false;
                }
            }
            return true;
        }

        /// <summary>
        /// Strict production ingress. The browser may supply only the seven frozen envelope keys;
        /// command payloads are normalized from per-command allow-lists and then flattened into a
        /// freshly constructed Flash request with Host-owned identity and write watermarks.
        /// </summary>
        public void HandleWebRequest(string command, JObject parsed)
        {
            string callId = ReadString(parsed != null ? parsed["callId"] : null);
            if (!IsCallId(callId))
            {
                RespondError(callId, command, "invalid_call_id", false, null);
                return;
            }

            if (!CanAdmitRequest())
            {
                RejectAndRemember(
                    callId, command, "host_closing");
                return;
            }

            if (!IsExactObject(parsed, TopLevelKeys)
                || ReadString(parsed["type"]) != "panel"
                || ReadString(parsed["panel"]) != "workbench"
                || ReadString(parsed["domain"]) != "loadout"
                || ReadString(parsed["cmd"]) != command)
            {
                RejectAndRemember(callId, command, "invalid_payload");
                return;
            }

            string requestedPanel = ReadString(parsed["panelInstanceId"]);
            if (!IsOpaque(requestedPanel) || !IsBoundTo(requestedPanel))
            {
                RejectAndRemember(callId, command, "panel_instance_expired");
                return;
            }

            string flashAction;
            if (!TryResolveProductionCommand(command, out flashAction))
            {
                RejectAndRemember(callId, command, "unsupported_cmd");
                return;
            }

            JObject normalized;
            long? requestedGeneration;
            string reconcileAfterCallId;
            bool initialRetry;
            string normalizationError;
            if (!TryNormalizeProductionPayload(
                    command,
                    callId,
                    parsed["payload"] as JObject,
                    out normalized,
                    out requestedGeneration,
                    out reconcileAfterCallId,
                    out initialRetry,
                    out normalizationError))
            {
                RejectAndRemember(
                    callId,
                    command,
                    string.IsNullOrEmpty(normalizationError)
                        ? "invalid_payload" : normalizationError,
                    string.Equals(
                        normalizationError,
                        "reconcile_required",
                        StringComparison.Ordinal));
                return;
            }

            if (!_pendingCalls.IsReady())
            {
                RejectAndRemember(
                    callId, command, "disconnected", true);
                return;
            }

            int backendCallId;
            string error;
            if (!TryBeginHostAcceptedCore(
                    requestedPanel,
                    requestedGeneration,
                    callId,
                    command,
                    reconcileAfterCallId,
                    flashAction,
                    normalized,
                    true,
                    initialRetry,
                    out backendCallId,
                    out error))
            {
                RejectAndRemember(
                    callId,
                    command,
                    error ?? "invalid_request",
                    true);
            }
        }

        /// <summary>
        /// Strict production response endpoint registered as task=loadout_response.
        /// Unknown/stale backend call ids are consumed only by the socket dispatcher callback.
        /// </summary>
        public void HandleFlashResponse(JObject message, Action<string> respond)
        {
            int backendCallId;
            if (!TryReadInteger(
                    message != null ? message["callId"] : null,
                    1,
                    int.MaxValue,
                    out backendCallId))
            {
                if (respond != null) respond(null);
                return;
            }

            PendingRequest entry;
            lock (_gate)
            {
                if (!_productionPending.TryGetValue(backendCallId, out entry))
                {
                    if (respond != null) respond(null);
                    return;
                }
            }

            if (entry.IsDetachRecovery)
            {
                HandleDetachRecoveryResponse(message, entry);
                if (respond != null) respond(null);
                return;
            }

            JObject sanitized;
            string failureCode;
            bool success;
            long responseGeneration;
            long loadoutRevision;
            long liveRevision;
            long drugRevision;
            bool liveRefreshDirty;
            bool active;
            bool? closed;
            bool? persistenceSucceeded;
            bool? mutationChanged;
            if (!TryValidateProductionResponse(
                    message,
                    entry,
                    out sanitized,
                    out success,
                    out failureCode,
                    out responseGeneration,
                    out loadoutRevision,
                    out liveRevision,
                    out drugRevision,
                    out liveRefreshDirty,
                    out active,
                    out closed,
                    out persistenceSucceeded,
                    out mutationChanged))
            {
                PendingRequest malformedEntry;
                if (TryCompleteMalformedResponse(
                    backendCallId, out malformedEntry))
                {
                    bool requiresReconcile;
                    string reconcileAfterCallId;
                    lock (_gate)
                    {
                        requiresReconcile =
                            _writeState == "needs_reconcile"
                            && IsCallId(_unknownCallId);
                        reconcileAfterCallId = requiresReconcile
                            ? _unknownCallId : null;
                    }
                    RespondError(
                        malformedEntry.WebCallId,
                        malformedEntry.Command,
                        "malformed_response",
                        requiresReconcile,
                        reconcileAfterCallId,
                        malformedEntry.PanelInstanceId,
                        malformedEntry.WriteEpoch);
                }
                NotifyCoordinatorSettledIfReady();
                if (respond != null) respond(null);
                return;
            }

            string completionError;
            bool completed;
            if (success)
            {
                completed = TryCompleteSuccess(
                    backendCallId,
                    entry.PanelInstanceId,
                    responseGeneration,
                    entry.WebCallId,
                    entry.Command,
                    entry.WriteEpoch,
                    loadoutRevision,
                    liveRevision,
                    drugRevision,
                    liveRefreshDirty,
                    active,
                    closed,
                    persistenceSucceeded,
                    mutationChanged,
                    out completionError);
            }
            else
            {
                completed = TryCompleteKnownFailure(
                    backendCallId,
                    entry.PanelInstanceId,
                    responseGeneration,
                    entry.WebCallId,
                    entry.Command,
                    entry.WriteEpoch,
                    active,
                    failureCode,
                    loadoutRevision,
                    liveRevision,
                    drugRevision,
                    liveRefreshDirty,
                    out completionError);
            }

            if (!completed)
            {
                // Timeout/disconnect may have won after the dictionary lookup but before tracker
                // completion. Its callback already emitted the single Host-stamped terminal
                // response; never manufacture a second response for that stale backend id.
                if (string.Equals(
                    completionError, "unknown_call", StringComparison.Ordinal))
                {
                    if (respond != null) respond(null);
                    return;
                }
                bool requiresReconcile;
                string reconcileAfter;
                lock (_gate)
                {
                    requiresReconcile = entry.IsWrite
                        && _writeState == "needs_reconcile";
                    reconcileAfter = requiresReconcile ? _unknownCallId : null;
                }
                RespondError(
                    entry.WebCallId,
                    entry.Command,
                    completionError ?? "malformed_response",
                    requiresReconcile,
                    reconcileAfter,
                    entry.PanelInstanceId,
                    entry.WriteEpoch);
            }
            else
            {
                if (string.Equals(entry.Command, "candidates", StringComparison.Ordinal))
                    ApplyCandidateTooltipSourcesIfCurrent(entry, sanitized);
                StampAndPostProductionResponse(sanitized, entry);
            }
            NotifyCoordinatorSettledIfReady();
            if (respond != null) respond(null);
        }

        /// <summary>
        /// Browser-side synchronous not_sent occurs before Host acceptance. It is intentionally not
        /// inserted into the pending tracker and cannot reset another accepted call.
        /// </summary>
        internal bool TryClassifyBrowserPreAcceptNotSent(
            string panelInstanceId,
            long? sessionGeneration,
            string callId,
            string command,
            out string error)
        {
            error = null;
            if (!IsCallId(callId) || !TryResolveCommand(command, out _, out _, out _))
            {
                error = "invalid_request";
                return false;
            }
            lock (_gate)
            {
                bool exactPanel = string.Equals(
                    _panelInstanceId, panelInstanceId, StringComparison.Ordinal);
                bool initialSnapshot = command == "snapshot" && !_sessionGeneration.HasValue;
                bool exactSession = _sessionGeneration.HasValue
                    && sessionGeneration == _sessionGeneration;
                if (_disposed || _bindingChanging || !exactPanel
                    || (initialSnapshot ? sessionGeneration.HasValue : !exactSession))
                {
                    error = "stale_session";
                    return false;
                }
                if (_writeState == "finalized")
                {
                    error = "session_finalized";
                    return false;
                }
                if (_pendingCalls.IsKnownWebCallId(callId))
                {
                    error = "duplicate";
                    return false;
                }
            }
            error = "not_sent";
            return true;
        }

        /// <summary>
        /// Begins a call only after Host accepted the browser envelope. Backend send=false from this
        /// point is DeliveryUnknown, never browser pre-accept not_sent.
        /// </summary>
        internal bool TryBeginHostAccepted(
            string panelInstanceId,
            long? sessionGeneration,
            string callId,
            string command,
            string reconcileAfterCallId,
            out int backendCallId,
            out string error)
        {
            return TryBeginHostAcceptedCore(
                panelInstanceId,
                sessionGeneration,
                callId,
                command,
                reconcileAfterCallId,
                null,
                null,
                false,
                false,
                out backendCallId,
                out error);
        }

        private bool TryBeginHostAcceptedCore(
            string panelInstanceId,
            long? sessionGeneration,
            string callId,
            string command,
            string reconcileAfterCallId,
            string flashAction,
            JObject normalizedPayload,
            bool postToWeb,
            bool allowInitialRetry,
            out int backendCallId,
            out string error)
        {
            backendCallId = 0;
            error = null;
            if (!IsCallId(callId))
            {
                error = "invalid_call_id";
                return false;
            }
            if (!CanAdmitRequest())
            {
                error = "host_closing";
                return false;
            }

            bool isWrite;
            UnknownKind kind;
            MutationTarget mutationTarget;
            if (!TryResolveCommand(command, out isWrite, out kind, out mutationTarget))
            {
                error = "unsupported_cmd";
                return false;
            }

            PendingRequest entry;
            lock (_gate)
            {
                if (_disposed)
                {
                    error = "disposed";
                    return false;
                }
                if (_bindingChanging)
                {
                    error = "binding_in_progress";
                    return false;
                }
                if (_detachRecoveryRequired)
                {
                    error = "detach_recovery_pending";
                    return false;
                }
                if (!string.Equals(_panelInstanceId, panelInstanceId, StringComparison.Ordinal))
                {
                    error = "panel_instance_expired";
                    return false;
                }
                if (_writeState == "finalized")
                {
                    error = "session_finalized";
                    return false;
                }
                if (_pendingCount >= MaxPending)
                {
                    error = "busy";
                    return false;
                }
                bool noGenerationSnapshot = command == "snapshot"
                    && !sessionGeneration.HasValue;
                bool openingRetry = allowInitialRetry
                    && noGenerationSnapshot
                    && !_sessionGeneration.HasValue
                    && _initialSnapshotOutcomeUnknown;
                bool generationlessRecovery = allowInitialRetry
                    && noGenerationSnapshot
                    && _sessionGeneration.HasValue;
                bool initialRetry = openingRetry || generationlessRecovery;
                if (HasActiveProductionCallLocked(callId)
                    || _pendingCalls.IsKnownWebCallId(callId))
                {
                    error = "duplicate";
                    return false;
                }

                bool initialSnapshot = noGenerationSnapshot
                    && !_sessionGeneration.HasValue;
                if (initialSnapshot)
                {
                    if (_pendingCount != 0)
                    {
                        error = "busy";
                        return false;
                    }
                    if (sessionGeneration.HasValue || !string.IsNullOrEmpty(reconcileAfterCallId)
                        || _writeState != "idle")
                    {
                        error = "session_not_bound";
                        return false;
                    }
                }
                else if (generationlessRecovery)
                {
                    if (!string.IsNullOrEmpty(reconcileAfterCallId)
                        || _writeState != "idle")
                    {
                        error = _writeState == "needs_reconcile"
                            ? "reconcile_required"
                            : "session_generation_required";
                        return false;
                    }
                }
                else if (!sessionGeneration.HasValue)
                {
                    error = "session_generation_required";
                    return false;
                }
                else if (!_sessionGeneration.HasValue
                    || sessionGeneration.Value != _sessionGeneration.Value)
                {
                    error = "session_generation_expired";
                    return false;
                }

                bool reconcileSnapshot = command == "snapshot"
                    && !string.IsNullOrEmpty(reconcileAfterCallId);
                bool finalizeRetry = command == "finalize"
                    && !string.IsNullOrEmpty(reconcileAfterCallId);
                if (!reconcileSnapshot && !finalizeRetry
                    && !string.IsNullOrEmpty(reconcileAfterCallId))
                {
                    error = "invalid_reconcile_watermark";
                    return false;
                }

                if (reconcileSnapshot)
                {
                    if (_writeState != "needs_reconcile"
                        || !string.Equals(
                            reconcileAfterCallId, _unknownCallId, StringComparison.Ordinal))
                    {
                        error = "invalid_reconcile_watermark";
                        return false;
                    }
                }
                else if (finalizeRetry)
                {
                    if (_writeState != "needs_reconcile"
                        || _unknownKind != UnknownKind.Finalize
                        || !string.Equals(
                            reconcileAfterCallId, _unknownCallId, StringComparison.Ordinal))
                    {
                        error = "invalid_reconcile_watermark";
                        return false;
                    }
                }
                else if (isWrite)
                {
                    bool retryingFlushFailure = _writeState == "flush_failed"
                        && (command == "flushLive" || command == "finalize");
                    if (_writeState != "idle" && !retryingFlushFailure)
                    {
                        error = _writeState == "needs_reconcile"
                            ? "reconcile_required" : "busy";
                        return false;
                    }
                }
                else if (_writeState != "idle")
                {
                    error = _writeState == "needs_reconcile"
                        ? "reconcile_required" : "busy";
                    return false;
                }

                entry = new PendingRequest
                {
                    PanelInstanceId = panelInstanceId,
                    BindingEpoch = _bindingEpoch,
                    SessionGeneration = generationlessRecovery
                        ? _sessionGeneration
                        : initialSnapshot ? null : sessionGeneration,
                    WebCallId = callId,
                    Command = command,
                    FlashAction = flashAction,
                    ReconcileAfterCallId = reconcileAfterCallId,
                    NormalizedPayload = normalizedPayload != null
                        ? (JObject)normalizedPayload.DeepClone() : null,
                    PostToWeb = postToWeb,
                    IsInitialSnapshot = initialSnapshot,
                    IsInitialRetry = initialRetry,
                    IsReconcileSnapshot = reconcileSnapshot,
                    IsWrite = isWrite,
                    WriteEpoch = isWrite ? unchecked(_writeEpoch + 1) : _writeEpoch,
                    ReconcileTargetEpoch = reconcileSnapshot ? _unknownEpoch : 0,
                    ReconcileTargetKind = reconcileSnapshot
                        ? _unknownKind : UnknownKind.None,
                    Kind = kind,
                    MutationTarget = mutationTarget,
                    ExpectedLoadoutRevision = _loadoutRevision,
                    ExpectedLiveRevision = _liveRevision,
                    ExpectedDrugRevision = _drugRevision,
                    RequestedLoadoutRevision =
                        normalizedPayload != null
                            && normalizedPayload["expectedLoadoutRevision"] != null
                        ? normalizedPayload.Value<long>("expectedLoadoutRevision")
                        : _loadoutRevision,
                    RequestedDrugRevision =
                        normalizedPayload != null
                            && normalizedPayload["expectedDrugRevision"] != null
                        ? normalizedPayload.Value<long>("expectedDrugRevision")
                        : _drugRevision
                };

                if (!_pendingCalls.TryBegin(callId, entry, out backendCallId))
                {
                    error = "duplicate";
                    return false;
                }
                if (command == "snapshot" || command == "candidates" || isWrite)
                    InvalidateCandidateTooltipsLocked();
                entry.CandidateTooltipEpoch = _candidateTooltipEpoch;
                entry.BackendCallId = backendCallId;
                if (postToWeb) _productionPending[backendCallId] = entry;
                if (isWrite)
                {
                    _writeEpoch = entry.WriteEpoch;
                    _writeState = "write_pending";
                    InvalidateFinalizeProofLocked();
                }
                _pendingCount++;
            }

            string wirePayload = postToWeb
                ? BuildFlashWirePayload(entry)
                : "character-build:" + command + ":" + callId;
            _pendingCalls.Send(backendCallId, wirePayload);
            return true;
        }

        private bool CanAdmitRequest()
        {
            Func<bool> gate =
                _admissionGate;
            if (gate == null) return true;
            try { return gate(); }
            catch (Exception ex)
            {
                LogManager.Log(
                    "[CharacterBuildTask] admission gate threw "
                    + ex.GetType().Name);
                return false;
            }
        }

        internal bool TryCompleteSuccess(
            int backendCallId,
            string panelInstanceId,
            long? sessionGeneration,
            string responseWebCallId,
            string responseCommand,
            int responseWriteEpoch,
            long loadoutRevision,
            long liveRevision,
            long drugRevision,
            bool liveRefreshDirty,
            bool responseActive,
            bool? responseClosed,
            bool? persistenceSucceeded,
            out string error)
        {
            return TryCompleteSuccess(
                backendCallId,
                panelInstanceId,
                sessionGeneration,
                responseWebCallId,
                responseCommand,
                responseWriteEpoch,
                loadoutRevision,
                liveRevision,
                drugRevision,
                liveRefreshDirty,
                responseActive,
                responseClosed,
                persistenceSucceeded,
                null,
                out error);
        }

        private bool TryCompleteSuccess(
            int backendCallId,
            string panelInstanceId,
            long? sessionGeneration,
            string responseWebCallId,
            string responseCommand,
            int responseWriteEpoch,
            long loadoutRevision,
            long liveRevision,
            long drugRevision,
            bool liveRefreshDirty,
            bool responseActive,
            bool? responseClosed,
            bool? persistenceSucceeded,
            bool? mutationChanged,
            out string error)
        {
            error = null;
            PanelPendingCall<PendingRequest> pending;
            if (!_pendingCalls.TryComplete(backendCallId, out pending))
            {
                error = "unknown_call";
                return false;
            }

            PendingRequest entry = pending.Context;
            lock (_gate)
            {
                _productionPending.Remove(backendCallId);
                if (!IsCurrentBindingLocked(entry))
                {
                    error = "stale_session";
                    return false;
                }
                DecrementPendingLocked();
                bool identityValid = IsCurrentIdentityLocked(entry, panelInstanceId)
                    && IsResponseGenerationValid(entry, sessionGeneration)
                    && responseWriteEpoch == entry.WriteEpoch
                    && string.Equals(
                        responseWebCallId, entry.WebCallId, StringComparison.Ordinal)
                    && string.Equals(
                        responseCommand, entry.Command, StringComparison.Ordinal);
                bool operationEnvelopeValid = entry.Kind == UnknownKind.Finalize
                    ? !responseActive && responseClosed == true
                        && persistenceSucceeded == true
                    : responseActive && responseClosed != true;
                bool snapshotValid = IsSnapshotShapeValid(
                    loadoutRevision, liveRevision, drugRevision, liveRefreshDirty);
                if (!identityValid || !operationEnvelopeValid || !snapshotValid)
                {
                    if (entry.IsWrite) MarkUnknownLocked(entry);
                    if (entry.IsInitialSnapshot)
                        _initialSnapshotOutcomeUnknown = true;
                    error = "malformed_response";
                    return false;
                }

                if (entry.IsInitialSnapshot)
                {
                    _sessionGeneration = sessionGeneration;
                    _initialSnapshotOutcomeUnknown = false;
                    ApplySnapshotLocked(
                        loadoutRevision, liveRevision, drugRevision, liveRefreshDirty);
                    LogSnapshotAccepted(
                        entry,
                        sessionGeneration,
                        loadoutRevision,
                        liveRevision,
                        drugRevision,
                        liveRefreshDirty,
                        "initial",
                        false,
                        true);
                    return true;
                }

                if (entry.IsReconcileSnapshot)
                {
                    bool currentWatermark = _writeState == "needs_reconcile"
                        && entry.WriteEpoch == _writeEpoch
                        && entry.ReconcileTargetEpoch == _unknownEpoch
                        && string.Equals(
                            entry.ReconcileAfterCallId, _unknownCallId, StringComparison.Ordinal);
                    if (!currentWatermark)
                    {
                        error = "stale_snapshot";
                        return false;
                    }
                }

                if (!IsSnapshotCurrentLocked(
                    entry, loadoutRevision, liveRevision, drugRevision))
                {
                    if (entry.IsWrite)
                    {
                        MarkUnknownLocked(entry);
                        error = "needs_reconcile";
                    }
                    else
                    {
                        error = "stale_snapshot";
                    }
                    return false;
                }

                if (entry.IsWrite)
                {
                    bool correspondingRevisionAdvanced =
                        entry.MutationTarget == MutationTarget.None
                        || (entry.MutationTarget == MutationTarget.Equipment
                            && loadoutRevision > entry.ExpectedLoadoutRevision)
                        || (entry.MutationTarget == MutationTarget.Drug
                            && drugRevision > entry.ExpectedDrugRevision);
                    bool expectedCleanRevision = loadoutRevision
                            == entry.ExpectedLoadoutRevision
                        && liveRevision == entry.ExpectedLoadoutRevision
                        && !liveRefreshDirty;
                    bool proofValid = correspondingRevisionAdvanced;
                    if (entry.Kind == UnknownKind.Mutation
                        && mutationChanged.HasValue)
                    {
                        proofValid = IsExactMutationPostcondition(
                            entry,
                            mutationChanged.Value,
                            loadoutRevision,
                            liveRevision,
                            drugRevision,
                            liveRefreshDirty);
                    }
                    else if (entry.Kind == UnknownKind.FlushLive
                        || entry.Kind == UnknownKind.Finalize)
                    {
                        proofValid = expectedCleanRevision;
                    }

                    if (!proofValid)
                    {
                        MarkUnknownLocked(entry);
                        error = "needs_reconcile";
                        return false;
                    }

                    ApplySnapshotLocked(
                        loadoutRevision, liveRevision, drugRevision, liveRefreshDirty);
                    ClearUnknownLocked();
                    if (entry.Kind == UnknownKind.Finalize)
                    {
                        _writeState = "finalized";
                        SetFinalizeProofLocked(
                            loadoutRevision, liveRevision, drugRevision);
                    }
                    else
                    {
                        _writeState = "idle";
                        InvalidateFinalizeProofLocked();
                    }
                    return true;
                }

                if (entry.IsReconcileSnapshot)
                {
                    ApplySnapshotLocked(
                        loadoutRevision, liveRevision, drugRevision, liveRefreshDirty);
                    bool clears = _unknownKind == UnknownKind.Mutation
                        || (_unknownKind == UnknownKind.FlushLive
                            && !liveRefreshDirty && loadoutRevision == liveRevision);
                    if (clears)
                    {
                        _writeState = "idle";
                        ClearUnknownLocked();
                    }
                    LogSnapshotAccepted(
                        entry,
                        sessionGeneration,
                        loadoutRevision,
                        liveRevision,
                        drugRevision,
                        liveRefreshDirty,
                        "subsequent",
                        true,
                        true);
                    return true;
                }

                // A read accepted before a write may arrive afterward. It can complete for its
                // caller, but only the still-current idle epoch may advance Host authority.
                bool applied = false;
                if (entry.WriteEpoch == _writeEpoch && _writeState == "idle")
                {
                    ApplySnapshotLocked(
                        loadoutRevision, liveRevision, drugRevision, liveRefreshDirty);
                    applied = true;
                }
                if (entry.Command == "snapshot")
                    LogSnapshotAccepted(
                        entry,
                        sessionGeneration,
                        loadoutRevision,
                        liveRevision,
                        drugRevision,
                        liveRefreshDirty,
                        "subsequent",
                        false,
                        applied);
                return true;
            }
        }

        internal bool TryCompleteKnownFailure(
            int backendCallId,
            string panelInstanceId,
            long? sessionGeneration,
            string responseWebCallId,
            string responseCommand,
            int responseWriteEpoch,
            bool responseActive,
            string failureCode,
            long? loadoutRevision,
            long? liveRevision,
            long? drugRevision,
            bool? liveRefreshDirty,
            out string error)
        {
            error = null;
            PanelPendingCall<PendingRequest> pending;
            if (!_pendingCalls.TryComplete(backendCallId, out pending))
            {
                error = "unknown_call";
                return false;
            }

            PendingRequest entry = pending.Context;
            lock (_gate)
            {
                _productionPending.Remove(backendCallId);
                if (!IsCurrentBindingLocked(entry))
                {
                    error = "stale_session";
                    return false;
                }
                DecrementPendingLocked();
                if (!IsCurrentIdentityLocked(entry, panelInstanceId)
                    || !IsFailureGenerationValid(entry, sessionGeneration)
                    || responseWriteEpoch != entry.WriteEpoch
                    || !string.Equals(
                        responseWebCallId, entry.WebCallId, StringComparison.Ordinal)
                    || !string.Equals(
                        responseCommand, entry.Command, StringComparison.Ordinal)
                    || !IsKnownFailureCode(failureCode))
                {
                    if (entry.IsWrite) MarkUnknownLocked(entry);
                    if (entry.IsInitialSnapshot)
                        _initialSnapshotOutcomeUnknown = true;
                    error = "malformed_response";
                    return false;
                }

                if (entry.Kind == UnknownKind.Mutation
                    && (!responseActive
                        || !IsMutationFailureCode(failureCode)))
                {
                    MarkUnknownLocked(entry);
                    error = "needs_reconcile";
                    return false;
                }

                bool reconcileFailure = failureCode == "needs_reconcile";
                bool flushFailure = failureCode == "flush_failed";
                if ((reconcileFailure && !entry.IsWrite)
                    || (flushFailure
                        && (!entry.IsWrite
                            || (entry.Kind != UnknownKind.FlushLive
                                && entry.Kind != UnknownKind.Finalize))))
                {
                    if (entry.IsWrite) MarkUnknownLocked(entry);
                    error = "malformed_response";
                    return false;
                }

                bool hasAnySnapshot = loadoutRevision.HasValue || liveRevision.HasValue
                    || drugRevision.HasValue || liveRefreshDirty.HasValue;
                bool hasCompleteSnapshot = loadoutRevision.HasValue
                    && liveRevision.HasValue && drugRevision.HasValue
                    && liveRefreshDirty.HasValue;
                if (hasAnySnapshot && (!hasCompleteSnapshot
                    || !IsSnapshotShapeValid(
                        loadoutRevision.Value,
                        liveRevision.Value,
                        drugRevision.Value,
                        liveRefreshDirty.Value)))
                {
                    if (entry.IsWrite) MarkUnknownLocked(entry);
                    error = "malformed_response";
                    return false;
                }

                if (hasCompleteSnapshot && !IsSnapshotCurrentLocked(
                    entry,
                    loadoutRevision.Value,
                    liveRevision.Value,
                    drugRevision.Value))
                {
                    if (entry.IsWrite)
                    {
                        MarkUnknownLocked(entry);
                        error = "needs_reconcile";
                    }
                    else
                    {
                        error = "stale_snapshot";
                    }
                    return false;
                }

                if (hasCompleteSnapshot
                    && entry.Kind == UnknownKind.Mutation
                    && !reconcileFailure
                    && (loadoutRevision.Value != entry.ExpectedLoadoutRevision
                        || liveRevision.Value != entry.ExpectedLiveRevision
                        || drugRevision.Value != entry.ExpectedDrugRevision
                        || liveRefreshDirty.Value
                            != (entry.ExpectedLoadoutRevision
                                != entry.ExpectedLiveRevision)))
                {
                    MarkUnknownLocked(entry);
                    error = "needs_reconcile";
                    return false;
                }

                if (hasCompleteSnapshot)
                {
                    ApplySnapshotLocked(
                        loadoutRevision.Value,
                        liveRevision.Value,
                        drugRevision.Value,
                        liveRefreshDirty.Value);
                }

                if (entry.IsInitialSnapshot)
                    _initialSnapshotOutcomeUnknown = false;

                if (reconcileFailure)
                {
                    MarkUnknownLocked(entry);
                    return true;
                }

                if (flushFailure)
                {
                    InvalidateFinalizeProofLocked();
                    ClearUnknownLocked();
                    _writeState = "flush_failed";
                    return true;
                }

                if (entry.IsWrite)
                {
                    InvalidateFinalizeProofLocked();
                    ClearUnknownLocked();
                    _writeState = "idle";
                }
                return true;
            }
        }

        /// <summary>
        /// Socket detach drains transport ownership. Accepted writes become unknown; reads simply
        /// terminate. The panel/session binding and reconcile watermark are retained.
        /// </summary>
        public void HandleDisconnect()
        {
            HandleDisconnect(SafeReadyGeneration());
        }

        public void HandleDisconnect(int closedGeneration)
        {
            RequireDetachRecovery(
                "socket_detach",
                closedGeneration,
                0,
                false);
        }

        public void Dispose()
        {
            lock (_gate)
            {
                if (_disposed) return;
                _disposed = true;
                ResetDetachRecoveryLocked();
                System.Threading.Monitor.PulseAll(
                    _gate);
            }
            _pendingCalls.Dispose();
        }

        private void HandlePendingEnded(
            PanelPendingCall<PendingRequest> call,
            PanelPendingCallEndReason reason)
        {
            PendingRequest entry = call.Context;
            if (entry != null && entry.IsDetachRecovery)
            {
                HandleDetachRecoveryPendingEnded(entry, reason);
                return;
            }
            bool postToWeb = false;
            bool requiresReconcile = false;
            string reconcileAfterCallId = null;
            lock (_gate)
            {
                if (entry != null)
                    _productionPending.Remove(entry.BackendCallId);
                if (_disposed || !IsCurrentBindingLocked(entry)) return;
                DecrementPendingLocked();
                if (entry.IsWrite) MarkUnknownLocked(entry);
                if (entry.IsInitialSnapshot)
                    _initialSnapshotOutcomeUnknown = true;
                postToWeb = entry.PostToWeb;
                requiresReconcile = entry.IsWrite;
                reconcileAfterCallId = requiresReconcile ? entry.WebCallId : null;
            }
            if (postToWeb)
            {
                string error = reason == PanelPendingCallEndReason.Timeout
                    ? "timeout"
                    : reason == PanelPendingCallEndReason.DeliveryUnknown
                        ? "delivery_unknown" : "disconnected";
                RespondError(
                    entry.WebCallId,
                    entry.Command,
                    error,
                    requiresReconcile,
                    reconcileAfterCallId,
                    entry.PanelInstanceId,
                    entry.WriteEpoch);
                NotifyCoordinatorSettledIfReady();
            }
        }

        private void MarkUnknownLocked(PendingRequest entry)
        {
            _writeState = "needs_reconcile";
            _unknownCallId = entry.WebCallId;
            _unknownEpoch = entry.WriteEpoch;
            _unknownKind = entry.Kind;
            InvalidateFinalizeProofLocked();
        }

        private void ClearUnknownLocked()
        {
            _unknownCallId = null;
            _unknownEpoch = 0;
            _unknownKind = UnknownKind.None;
        }

        private void SetFinalizeProofLocked(
            long loadoutRevision,
            long liveRevision,
            long drugRevision)
        {
            _finalizePersistenceProven = true;
            _finalizedLoadoutRevision = loadoutRevision;
            _finalizedLiveRevision = liveRevision;
            _finalizedDrugRevision = drugRevision;
        }

        private void InvalidateFinalizeProofLocked()
        {
            _finalizePersistenceProven = false;
            _finalizedLoadoutRevision = -1;
            _finalizedLiveRevision = -1;
            _finalizedDrugRevision = -1;
        }

        private void ApplySnapshotLocked(
            long loadoutRevision,
            long liveRevision,
            long drugRevision,
            bool liveRefreshDirty)
        {
            _loadoutRevision = loadoutRevision;
            _liveRevision = liveRevision;
            _drugRevision = drugRevision;
            _liveRefreshDirty = liveRefreshDirty;
        }

        private static void LogPanelBound(
            string panelInstanceId,
            int bindingEpoch)
        {
            // Bounded evidence only: the opaque exact Host identity and a local epoch.
            // Item projections and player-owned strings never enter this event.
            LogManager.Log(
                "event=character_build_panel_bound"
                + " panelInstanceId=" + panelInstanceId
                + " bindingEpoch="
                + bindingEpoch.ToString(
                    CultureInfo.InvariantCulture));
        }

        private static void LogSnapshotAccepted(
            PendingRequest entry,
            long? sessionGeneration,
            long loadoutRevision,
            long liveRevision,
            long drugRevision,
            bool liveRefreshDirty,
            string phase,
            bool reconcile,
            bool authorityApplied)
        {
            // Fixed scalar schema for unattended evidence. Never log payload/equipment names.
            LogManager.Log(
                "event=character_build_snapshot_accepted"
                + " phase=" + phase
                + " reconcile=" + (reconcile ? "true" : "false")
                + " authorityApplied=" + (authorityApplied ? "true" : "false")
                + " panelInstanceId=" + entry.PanelInstanceId
                + " sessionGeneration="
                + (sessionGeneration.HasValue
                    ? sessionGeneration.Value.ToString(
                        CultureInfo.InvariantCulture)
                    : "0")
                + " loadoutRevision="
                + loadoutRevision.ToString(
                    CultureInfo.InvariantCulture)
                + " liveRevision="
                + liveRevision.ToString(
                    CultureInfo.InvariantCulture)
                + " drugRevision="
                + drugRevision.ToString(
                    CultureInfo.InvariantCulture)
                + " liveRefreshDirty="
                + (liveRefreshDirty ? "true" : "false"));
        }

        private bool IsCurrentBindingLocked(PendingRequest entry)
        {
            return !_disposed && entry.BindingEpoch == _bindingEpoch
                && string.Equals(
                    entry.PanelInstanceId, _panelInstanceId, StringComparison.Ordinal);
        }

        private bool IsCurrentIdentityLocked(PendingRequest entry, string responsePanelInstanceId)
        {
            return IsCurrentBindingLocked(entry)
                && string.Equals(
                    responsePanelInstanceId, _panelInstanceId, StringComparison.Ordinal);
        }

        private bool IsResponseGenerationValid(
            PendingRequest entry,
            long? responseGeneration)
        {
            if (!IsGeneration(responseGeneration)) return false;
            if (entry.IsInitialSnapshot)
                return !_sessionGeneration.HasValue;
            return entry.SessionGeneration == responseGeneration
                && _sessionGeneration == responseGeneration;
        }

        private bool IsFailureGenerationValid(
            PendingRequest entry,
            long? responseGeneration)
        {
            if (entry.IsInitialSnapshot)
            {
                return !_sessionGeneration.HasValue
                    && (!responseGeneration.HasValue || responseGeneration.Value == 0);
            }
            return IsResponseGenerationValid(entry, responseGeneration);
        }

        private bool IsSnapshotCurrentLocked(
            PendingRequest entry,
            long loadoutRevision,
            long liveRevision,
            long drugRevision)
        {
            return loadoutRevision >= entry.ExpectedLoadoutRevision
                && liveRevision >= entry.ExpectedLiveRevision
                && drugRevision >= entry.ExpectedDrugRevision
                && loadoutRevision >= _loadoutRevision
                && liveRevision >= _liveRevision
                && drugRevision >= _drugRevision;
        }

        private static bool IsExactMutationPostcondition(
            PendingRequest entry,
            bool changed,
            long loadoutRevision,
            long liveRevision,
            long drugRevision,
            bool liveRefreshDirty)
        {
            if (entry == null || entry.Kind != UnknownKind.Mutation)
                return false;
            if (entry.MutationTarget == MutationTarget.Equipment)
            {
                long expected = entry.RequestedLoadoutRevision;
                if (expected != entry.ExpectedLoadoutRevision
                    || (changed && expected == int.MaxValue))
                {
                    return false;
                }
                long expectedAfter = changed ? expected + 1 : expected;
                return loadoutRevision == expectedAfter
                    && liveRevision == entry.ExpectedLiveRevision
                    && drugRevision == entry.ExpectedDrugRevision
                    && liveRefreshDirty
                        == (expectedAfter != entry.ExpectedLiveRevision);
            }
            if (entry.MutationTarget == MutationTarget.Drug)
            {
                long expected = entry.RequestedDrugRevision;
                if (expected != entry.ExpectedDrugRevision
                    || (changed && expected == int.MaxValue))
                {
                    return false;
                }
                long expectedAfter = changed ? expected + 1 : expected;
                return loadoutRevision == entry.ExpectedLoadoutRevision
                    && liveRevision == entry.ExpectedLiveRevision
                    && drugRevision == expectedAfter
                    && liveRefreshDirty
                        == (entry.ExpectedLoadoutRevision
                            != entry.ExpectedLiveRevision);
            }
            return false;
        }

        private static bool IsSnapshotShapeValid(
            long loadoutRevision,
            long liveRevision,
            long drugRevision,
            bool liveRefreshDirty)
        {
            return loadoutRevision >= 0 && liveRevision >= 0 && drugRevision >= 0
                && liveRevision <= loadoutRevision
                && liveRefreshDirty == (loadoutRevision != liveRevision);
        }

        private static string CandidateTooltipSourceKey(JObject source)
        {
            return source.Value<int>("slot").ToString(CultureInfo.InvariantCulture)
                + "\n" + ReadString(source["expectedLease"]);
        }

        private void InvalidateCandidateTooltipsLocked()
        {
            _candidateTooltipEpoch = _candidateTooltipEpoch == long.MaxValue
                ? 1 : _candidateTooltipEpoch + 1;
            _candidateTooltipSources.Clear();
        }

        private void ApplyCandidateTooltipSourcesIfCurrent(
            PendingRequest entry,
            JObject response)
        {
            JObject payload = response != null ? response["payload"] as JObject : null;
            JArray candidates = payload != null ? payload["candidates"] as JArray : null;
            if (entry == null || candidates == null) return;
            lock (_gate)
            {
                if (!IsCurrentBindingLocked(entry)
                    || _bindingChanging || _detachRecoveryRequired
                    || _writeState != "idle"
                    || entry.CandidateTooltipEpoch != _candidateTooltipEpoch
                    || !_sessionGeneration.HasValue
                    || !entry.SessionGeneration.HasValue
                    || _sessionGeneration.Value != entry.SessionGeneration.Value)
                {
                    return;
                }
                _candidateTooltipSources.Clear();
                foreach (JToken token in candidates)
                {
                    JObject row = token as JObject;
                    JObject source = row != null ? row["source"] as JObject : null;
                    JObject normalized;
                    if (CharacterBuildProtocol.TryNormalizeBackpackSource(
                        source, out normalized))
                    {
                        _candidateTooltipSources.Add(
                            CandidateTooltipSourceKey(normalized));
                    }
                }
            }
        }

        private void ResetSessionLocked()
        {
            InvalidateCandidateTooltipsLocked();
            ResetDetachRecoveryLocked();
            _sessionGeneration = null;
            _initialSnapshotOutcomeUnknown = false;
            _writeState = "idle";
            _writeEpoch = 0;
            _pendingCount = 0;
            _loadoutRevision = 0;
            _liveRevision = 0;
            _drugRevision = 0;
            _liveRefreshDirty = false;
            InvalidateFinalizeProofLocked();
            ClearUnknownLocked();
        }

        private bool CanReleaseBindingLocked()
        {
            if (_disposed || _bindingChanging || _detachRecoveryRequired
                || _pendingCount != 0) return false;
            if (!_sessionGeneration.HasValue)
                return !_initialSnapshotOutcomeUnknown && _writeState == "idle";
            return HasFinalizeProofLocked();
        }

        private bool HasFinalizeProofLocked()
        {
            if (_disposed || _bindingChanging || _pendingCount != 0) return false;
            return _writeState == "finalized"
                && _finalizePersistenceProven
                && !_liveRefreshDirty
                && _loadoutRevision == _liveRevision
                && _loadoutRevision == _finalizedLoadoutRevision
                && _liveRevision == _finalizedLiveRevision
                && _drugRevision == _finalizedDrugRevision;
        }

        private bool HasActiveProductionCallLocked(string webCallId)
        {
            foreach (PendingRequest pending in _productionPending.Values)
                if (string.Equals(
                    pending.WebCallId, webCallId, StringComparison.Ordinal))
                    return true;
            return false;
        }

        private void DecrementPendingLocked()
        {
            if (_pendingCount > 0) _pendingCount--;
        }

        private static bool TryResolveProductionCommand(
            string command,
            out string action)
        {
            if (CharacterBuildProtocol.TryResolveMutationAction(
                command, out action))
            {
                return true;
            }
            switch (command)
            {
                case "snapshot":
                    action = "characterBuildSnapshot";
                    return true;
                case "candidates":
                    action = "characterBuildCandidates";
                    return true;
                case "tooltip":
                    action = "characterBuildTooltip";
                    return true;
                case "flushLive":
                    action = "characterBuildFlushLive";
                    return true;
                case "statsSnapshot":
                    action = "characterBuildStatsSnapshot";
                    return true;
                case "finalize":
                    action = "characterBuildFinalize";
                    return true;
                default:
                    action = null;
                    return false;
            }
        }

        private bool TryNormalizeProductionPayload(
            string command,
            string callId,
            JObject payload,
            out JObject normalized,
            out long? sessionGeneration,
            out string reconcileAfterCallId,
            out bool initialRetry,
            out string error)
        {
            normalized = null;
            sessionGeneration = null;
            reconcileAfterCallId = null;
            initialRetry = false;
            error = null;
            if (payload == null || !HasVersion(payload))
            {
                error = "invalid_payload";
                return false;
            }

            if (CharacterBuildProtocol.IsMutationCommand(command))
            {
                long mutationGeneration;
                if (!CharacterBuildProtocol.TryNormalizeMutationPayload(
                        command,
                        payload,
                        out normalized,
                        out mutationGeneration,
                        out error))
                {
                    return false;
                }
                sessionGeneration = mutationGeneration;
                return true;
            }

            var result = new JObject { ["v"] = 1 };
            if (command == "snapshot")
            {
                if (IsExactObject(payload, Set("v")))
                {
                    lock (_gate)
                    {
                        if (_sessionGeneration.HasValue)
                        {
                            if (_writeState != "idle")
                            {
                                error = _writeState == "needs_reconcile"
                                    ? "reconcile_required"
                                    : "session_generation_required";
                                return false;
                            }
                            // Web may have lost the first Host-stamped response after Host already
                            // bound AS2 generation. The exact bound panel may repeat the original
                            // generation-less snapshot with a new Web call id; AS2 returns the
                            // existing generation instead of opening another session.
                            initialRetry = true;
                        }
                        else
                        {
                            initialRetry = _initialSnapshotOutcomeUnknown;
                        }
                    }
                    normalized = result;
                    return true;
                }

                bool hasReconcile = payload["reconcileAfterCallId"] != null;
                HashSet<string> allowed = hasReconcile
                    ? Set("v", "sessionGeneration", "reconcileAfterCallId")
                    : Set("v", "sessionGeneration");
                long generation;
                if (!IsExactObject(payload, allowed)
                    || !TryReadInteger(
                        payload["sessionGeneration"], 1, int.MaxValue, out generation))
                {
                    error = "invalid_payload";
                    return false;
                }
                sessionGeneration = generation;
                result["sessionGeneration"] = generation;
                if (hasReconcile)
                {
                    reconcileAfterCallId =
                        ReadString(payload["reconcileAfterCallId"]);
                    if (!IsCallId(reconcileAfterCallId))
                    {
                        error = "invalid_payload";
                        return false;
                    }
                    result["reconcileAfterCallId"] = reconcileAfterCallId;
                }
                normalized = result;
                return true;
            }

            long requiredGeneration;
            if (!TryReadInteger(
                    payload["sessionGeneration"],
                    1,
                    int.MaxValue,
                    out requiredGeneration))
            {
                error = "session_generation_required";
                return false;
            }
            sessionGeneration = requiredGeneration;
            result["sessionGeneration"] = requiredGeneration;

            if (command == "candidates")
            {
                bool hasSlotKey = payload["slotKey"] != null;
                bool hasDrugSlot = payload["drugSlot"] != null;
                HashSet<string> expectedKeys = hasSlotKey
                    ? Set("v", "sessionGeneration", "expectedLoadoutRevision",
                        "expectedDrugRevision", "candidateScope", "slotKey")
                    : Set("v", "sessionGeneration", "expectedLoadoutRevision",
                        "expectedDrugRevision", "candidateScope", "drugSlot");
                long expectedLoadout;
                long expectedDrug;
                string candidateScope = ReadString(payload["candidateScope"]);
                if (hasSlotKey == hasDrugSlot
                    || !IsExactObject(payload, expectedKeys)
                    || (candidateScope != "compatible"
                        && candidateScope != "backpack")
                    || !TryReadInteger(
                        payload["expectedLoadoutRevision"],
                        0,
                        int.MaxValue,
                        out expectedLoadout)
                    || !TryReadInteger(
                        payload["expectedDrugRevision"],
                        0,
                        int.MaxValue,
                        out expectedDrug))
                {
                    error = "invalid_payload";
                    return false;
                }
                result["expectedLoadoutRevision"] = expectedLoadout;
                result["expectedDrugRevision"] = expectedDrug;
                result["candidateScope"] = candidateScope;
                if (hasSlotKey)
                {
                    string slotKey = ReadString(payload["slotKey"]);
                    if (!CharacterBuildProtocol.IsEquipmentSlotKey(slotKey))
                    {
                        error = "invalid_payload";
                        return false;
                    }
                    result["slotKey"] = slotKey;
                }
                else
                {
                    int drugSlot;
                    if (!TryReadInteger(payload["drugSlot"], 0, 3, out drugSlot))
                    {
                        error = "invalid_payload";
                        return false;
                    }
                    result["drugSlot"] = drugSlot;
                }
                normalized = result;
                return true;
            }

            if (command == "tooltip")
            {
                bool hasSlotKey = payload["slotKey"] != null;
                bool hasDrugSlot = payload["drugSlot"] != null;
                HashSet<string> expectedKeys = hasSlotKey
                    ? Set("v", "sessionGeneration", "expectedLoadoutRevision",
                        "expectedDrugRevision", "slotKey")
                    : Set("v", "sessionGeneration", "expectedLoadoutRevision",
                        "expectedDrugRevision", "drugSlot");
                long expectedLoadout;
                long expectedDrug;
                if (hasSlotKey == hasDrugSlot
                    || !IsExactObject(payload, expectedKeys)
                    || !TryReadInteger(
                        payload["expectedLoadoutRevision"],
                        0,
                        int.MaxValue,
                        out expectedLoadout)
                    || !TryReadInteger(
                        payload["expectedDrugRevision"],
                        0,
                        int.MaxValue,
                        out expectedDrug))
                {
                    error = "invalid_payload";
                    return false;
                }
                result["expectedLoadoutRevision"] = expectedLoadout;
                result["expectedDrugRevision"] = expectedDrug;
                if (hasSlotKey)
                {
                    string slotKey = ReadString(payload["slotKey"]);
                    if (!CharacterBuildProtocol.IsEquipmentSlotKey(slotKey))
                    {
                        error = "invalid_payload";
                        return false;
                    }
                    result["slotKey"] = slotKey;
                }
                else
                {
                    int drugSlot;
                    if (!TryReadInteger(payload["drugSlot"], 0, 3, out drugSlot))
                    {
                        error = "invalid_payload";
                        return false;
                    }
                    result["drugSlot"] = drugSlot;
                }
                normalized = result;
                return true;
            }

            if (command == "flushLive")
            {
                long expectedLoadout;
                if (!IsExactObject(
                        payload,
                        Set("v", "sessionGeneration", "expectedLoadoutRevision"))
                    || !TryReadInteger(
                        payload["expectedLoadoutRevision"],
                        0,
                        int.MaxValue,
                        out expectedLoadout))
                {
                    error = "invalid_payload";
                    return false;
                }
                result["expectedLoadoutRevision"] = expectedLoadout;
                normalized = result;
                return true;
            }

            if (command == "statsSnapshot")
            {
                long expectedLoadout;
                long expectedLive;
                if (!IsExactObject(
                        payload,
                        Set("v", "sessionGeneration", "expectedLoadoutRevision",
                            "expectedLiveRevision"))
                    || !TryReadInteger(
                        payload["expectedLoadoutRevision"],
                        0,
                        int.MaxValue,
                        out expectedLoadout)
                    || !TryReadInteger(
                        payload["expectedLiveRevision"],
                        0,
                        int.MaxValue,
                        out expectedLive))
                {
                    error = "invalid_payload";
                    return false;
                }
                result["expectedLoadoutRevision"] = expectedLoadout;
                result["expectedLiveRevision"] = expectedLive;
                normalized = result;
                return true;
            }

            if (command == "finalize")
            {
                bool hasReconcile = payload["reconcileAfterCallId"] != null;
                HashSet<string> expectedKeys = hasReconcile
                    ? Set("v", "sessionGeneration", "expectedLoadoutRevision",
                        "reconcileAfterCallId")
                    : Set("v", "sessionGeneration", "expectedLoadoutRevision");
                long expectedLoadout;
                if (!IsExactObject(payload, expectedKeys)
                    || !TryReadInteger(
                        payload["expectedLoadoutRevision"],
                        0,
                        int.MaxValue,
                        out expectedLoadout))
                {
                    error = "invalid_payload";
                    return false;
                }
                result["expectedLoadoutRevision"] = expectedLoadout;
                if (hasReconcile)
                {
                    reconcileAfterCallId =
                        ReadString(payload["reconcileAfterCallId"]);
                    if (!IsCallId(reconcileAfterCallId))
                    {
                        error = "invalid_payload";
                        return false;
                    }
                    result["reconcileAfterCallId"] = reconcileAfterCallId;
                }
                normalized = result;
                return true;
            }

            error = "unsupported_cmd";
            return false;
        }

        private string BuildFlashWirePayload(PendingRequest entry)
        {
            JObject parameters = entry.NormalizedPayload != null
                ? (JObject)entry.NormalizedPayload.DeepClone() : new JObject();
            parameters["panelInstanceId"] = entry.PanelInstanceId;
            parameters["requestCallId"] = entry.WebCallId;
            parameters["writeEpoch"] = entry.WriteEpoch;
            JObject flash = PanelBridge.BuildFlashCommand(
                entry.FlashAction,
                entry.BackendCallId,
                parameters);
            string json = flash.ToString(Formatting.None);
            LogManager.Log("[CharacterBuildTask] -> Flash: " + json);
            return json + "\0";
        }

        private static bool TryValidateProductionResponse(
            JObject message,
            PendingRequest entry,
            out JObject sanitized,
            out bool success,
            out string failureCode,
            out long sessionGeneration,
            out long loadoutRevision,
            out long liveRevision,
            out long drugRevision,
            out bool liveRefreshDirty,
            out bool active,
            out bool? closed,
            out bool? persistenceSucceeded,
            out bool? mutationChanged)
        {
            sanitized = null;
            success = false;
            failureCode = null;
            sessionGeneration = 0;
            loadoutRevision = 0;
            liveRevision = 0;
            drugRevision = 0;
            liveRefreshDirty = false;
            active = false;
            closed = null;
            persistenceSucceeded = null;
            mutationChanged = null;
            if (message == null
                || ReadString(message["task"]) != "loadout_response"
                || ReadString(message["command"]) != entry.Command
                || ReadString(message["requestCallId"]) != entry.WebCallId
                || ReadString(message["panelInstanceId"]) != entry.PanelInstanceId
                || !HasVersion(message)
                || message["success"] == null
                || message["success"].Type != JTokenType.Boolean
                || message["active"] == null
                || message["active"].Type != JTokenType.Boolean
                || message["liveRefreshDirty"] == null
                || message["liveRefreshDirty"].Type != JTokenType.Boolean)
            {
                return false;
            }

            int backendCallId;
            int writeEpoch;
            if (!TryReadInteger(
                    message["callId"], 1, int.MaxValue, out backendCallId)
                || backendCallId != entry.BackendCallId
                || !TryReadInteger(
                    message["writeEpoch"], 0, int.MaxValue, out writeEpoch)
                || writeEpoch != entry.WriteEpoch
                || !TryReadInteger(
                    message["sessionGeneration"],
                    0,
                    int.MaxValue,
                    out sessionGeneration)
                || !TryReadInteger(
                    message["loadoutRevision"],
                    0,
                    int.MaxValue,
                    out loadoutRevision)
                || !TryReadInteger(
                    message["liveRevision"],
                    0,
                    int.MaxValue,
                    out liveRevision)
                || !TryReadInteger(
                    message["drugRevision"],
                    0,
                    int.MaxValue,
                    out drugRevision))
            {
                return false;
            }

            success = message.Value<bool>("success");
            active = message.Value<bool>("active");
            liveRefreshDirty = message.Value<bool>("liveRefreshDirty");
            if (!HasOnlyProductionResponseKeys(
                    message, entry, success)
                || !IsSnapshotShapeValid(
                    loadoutRevision,
                    liveRevision,
                    drugRevision,
                    liveRefreshDirty))
            {
                return false;
            }

            var web = new JObject
            {
                ["v"] = 1,
                ["success"] = success,
                ["writeEpoch"] = entry.WriteEpoch,
                ["active"] = active,
                ["sessionGeneration"] = sessionGeneration,
                ["loadoutRevision"] = loadoutRevision,
                ["liveRevision"] = liveRevision,
                ["liveRefreshDirty"] = liveRefreshDirty,
                ["drugRevision"] = drugRevision
            };

            if (!success)
            {
                // A failed initial snapshot is definitive only when AS2 proves that no session
                // became active. Otherwise the opening outcome remains ambiguous and must use
                // the malformed/unknown recovery path.
                if (entry.IsInitialSnapshot
                    && (active || sessionGeneration != 0))
                    return false;
                failureCode = ReadString(message["error"]);
                if (!IsSafeText(failureCode, 1, 64)) return false;
                web["error"] = failureCode;
                if (entry.Command == "flushLive")
                {
                    if (message["changed"] == null
                        || message["changed"].Type != JTokenType.Boolean)
                        return false;
                    web["changed"] = message.Value<bool>("changed");
                }
                else if (entry.Command == "finalize")
                {
                    JObject persistence = message["persistence"] as JObject;
                    if (message["closed"] == null
                        || message["closed"].Type != JTokenType.Boolean
                        || message["liveChanged"] == null
                        || message["liveChanged"].Type != JTokenType.Boolean
                        || !IsPersistenceProof(persistence))
                        return false;
                    closed = message.Value<bool>("closed");
                    persistenceSucceeded =
                        persistence.Value<bool>("success");
                    web["closed"] = closed.Value;
                    web["liveChanged"] = message.Value<bool>("liveChanged");
                    web["persistence"] = persistence.DeepClone();
                }
                sanitized = web;
                return true;
            }

            if (CharacterBuildProtocol.IsMutationCommand(entry.Command))
            {
                int affectedBackpackSlot;
                bool changed;
                if (!CharacterBuildProtocol.TryValidateMutationSuccess(
                        message,
                        entry.Command,
                        entry.NormalizedPayload,
                        out changed,
                        out affectedBackpackSlot))
                {
                    return false;
                }
                mutationChanged = changed;
                web["changed"] = changed;
                web["operation"] = entry.Command;
                web["affectedBackpackSlot"] = affectedBackpackSlot;
                web["payload"] = message["payload"].DeepClone();
                web["inventorySnapshots"] =
                    message["inventorySnapshots"].DeepClone();
            }
            else if (entry.Command == "snapshot")
            {
                JObject payload = message["payload"] as JObject;
                if (entry.IsReconcileSnapshot
                    && entry.ReconcileTargetKind == UnknownKind.Mutation)
                {
                    if (!CharacterBuildProtocol.IsMutationReconcileSnapshot(
                            message,
                            entry.ReconcileAfterCallId))
                    {
                        return false;
                    }
                    web["reconcileAfterCallId"] =
                        entry.ReconcileAfterCallId;
                    web["inventorySnapshots"] =
                        message["inventorySnapshots"].DeepClone();
                }
                else
                {
                    if (!CharacterBuildProtocol.IsLoadoutProjection(
                        payload, false))
                    {
                        return false;
                    }
                    if (entry.IsReconcileSnapshot)
                    {
                        // flushLive/finalize unknown 的 reconcile 快照同样携带 barrier
                        // 与整包背包证明：内容门槛与 mutation 一致，
                        // 但 Host/Web 都只消费 payload，两键不转发。
                        if (!string.Equals(
                                ReadString(message["reconcileAfterCallId"]),
                                entry.ReconcileAfterCallId,
                                StringComparison.Ordinal)
                            || !CharacterBuildProtocol.IsFullBackpackSnapshots(
                                message["inventorySnapshots"] as JArray))
                        {
                            return false;
                        }
                    }
                }
                web["payload"] = payload.DeepClone();
            }
            else if (entry.Command == "candidates")
            {
                JObject payload = message["payload"] as JObject;
                if (!IsCandidatesProjection(payload, entry.NormalizedPayload))
                    return false;
                web["payload"] = payload.DeepClone();
            }
            else if (entry.Command == "tooltip")
            {
                JObject payload = message["payload"] as JObject;
                if (loadoutRevision
                        != entry.NormalizedPayload.Value<long>(
                            "expectedLoadoutRevision")
                    || drugRevision
                        != entry.NormalizedPayload.Value<long>(
                            "expectedDrugRevision")
                    || !IsTooltipProjection(payload, entry.NormalizedPayload))
                {
                    return false;
                }
                web["payload"] = payload.DeepClone();
            }
            else if (entry.Command == "statsSnapshot")
            {
                JObject payload = message["payload"] as JObject;
                if (!IsStatsProjection(payload)) return false;
                web["payload"] = payload.DeepClone();
            }
            else if (entry.Command == "flushLive")
            {
                if (message["changed"] == null
                    || message["changed"].Type != JTokenType.Boolean)
                    return false;
                web["changed"] = message.Value<bool>("changed");
            }
            else if (entry.Command == "finalize")
            {
                JObject persistence = message["persistence"] as JObject;
                if (message["closed"] == null
                    || message["closed"].Type != JTokenType.Boolean
                    || message["liveChanged"] == null
                    || message["liveChanged"].Type != JTokenType.Boolean
                    || !IsPersistenceProof(persistence))
                    return false;
                closed = message.Value<bool>("closed");
                persistenceSucceeded = persistence.Value<bool>("success");
                web["closed"] = closed.Value;
                web["liveChanged"] = message.Value<bool>("liveChanged");
                web["persistence"] = persistence.DeepClone();
            }
            else
            {
                return false;
            }

            sanitized = web;
            return true;
        }

        private static bool HasOnlyProductionResponseKeys(
            JObject message,
            PendingRequest entry,
            bool success)
        {
            if (entry == null) return false;
            string command = entry.Command;
            var allowed = new HashSet<string>(
                CommonResponseKeys,
                StringComparer.Ordinal);
            if (!success)
            {
                allowed.Add("error");
                if (command == "flushLive") allowed.Add("changed");
                else if (command == "finalize")
                {
                    allowed.Add("closed");
                    allowed.Add("liveChanged");
                    allowed.Add("persistence");
                }
            }
            else if (CharacterBuildProtocol.IsMutationCommand(command))
            {
                allowed.Add("changed");
                allowed.Add("operation");
                allowed.Add("affectedBackpackSlot");
                allowed.Add("payload");
                allowed.Add("inventorySnapshots");
            }
            else if (command == "snapshot")
            {
                allowed.Add("payload");
                // 任何 unknown 种类的 reconcile 快照都允许携带 barrier 与整包背包证明；
                // 内容门槛在消毒路径按种类分别强制执行。
                if (entry.IsReconcileSnapshot)
                {
                    allowed.Add("reconcileAfterCallId");
                    allowed.Add("inventorySnapshots");
                }
            }
            else if (command == "candidates"
                || command == "tooltip"
                || command == "statsSnapshot")
            {
                allowed.Add("payload");
            }
            else if (command == "flushLive")
            {
                allowed.Add("changed");
            }
            else if (command == "finalize")
            {
                allowed.Add("closed");
                allowed.Add("liveChanged");
                allowed.Add("persistence");
            }
            else
            {
                return false;
            }
            return IsExactObject(message, allowed);
        }

        private static bool IsCandidatesProjection(
            JObject payload,
            JObject request)
        {
            if (!IsExactObject(
                    payload,
                    Set("target", "candidateScope", "candidates", "backpackVersion",
                        "stateHealth", "diagnostics"))
                || !(payload["target"] is JObject target)
                || !(payload["candidates"] is JArray candidates)
                || candidates.Count > MaxCandidateRows
                || !(payload["diagnostics"] is JArray diagnostics)
                || !IsDiagnostics(diagnostics)
                || !IsStateHealth(payload["stateHealth"])
                || (diagnostics.Count == 0)
                    != (ReadString(payload["stateHealth"]) == "ok"))
                return false;
            string candidateScope = ReadString(payload["candidateScope"]);
            if (request == null
                || (candidateScope != "compatible" && candidateScope != "backpack")
                || ReadString(request["candidateScope"]) != candidateScope)
                return false;
            int backpackVersion;
            if (!TryReadInteger(
                payload["backpackVersion"], 0, int.MaxValue, out backpackVersion))
                return false;

            string kind = ReadString(target["kind"]);
            string targetSlotKey = null;
            int targetDrugSlot = -1;
            if (kind == "equipment")
            {
                targetSlotKey = ReadString(target["slotKey"]);
                if (!IsExactObject(target, Set("kind", "slotKey"))
                    || !CharacterBuildProtocol.IsEquipmentSlotKey(targetSlotKey)
                    || request == null
                    || ReadString(request["slotKey"]) != targetSlotKey
                    || request["drugSlot"] != null)
                    return false;
            }
            else
            {
                int requestedDrugSlot;
                if (kind != "drug"
                    || !IsExactObject(target, Set("kind", "drugSlot"))
                    || !TryReadInteger(
                        target["drugSlot"], 0, 3, out targetDrugSlot)
                    || request == null
                    || request["slotKey"] != null
                    || !TryReadInteger(
                        request["drugSlot"], 0, 3, out requestedDrugSlot)
                    || requestedDrugSlot != targetDrugSlot)
                    return false;
            }

            bool universalEquipmentBackpack =
                candidateScope == "backpack" && kind == "equipment";

            int previousPhysicalSlot = -1;
            foreach (JToken token in candidates)
            {
                JObject row = token as JObject;
                if (!IsExactObject(
                        row,
                        universalEquipmentBackpack
                            ? Set("physicalSlot", "disabled", "blockedReason",
                                "item", "source", "equipmentEligibility")
                            : Set("physicalSlot", "disabled", "blockedReason",
                                "item", "source")))
                    return false;

                int physicalSlot;
                if (!TryReadInteger(
                        row["physicalSlot"],
                        0,
                        MaxCandidatePhysicalSlot,
                        out physicalSlot)
                    || physicalSlot <= previousPhysicalSlot
                    || row["disabled"] == null
                    || row["disabled"].Type != JTokenType.Boolean
                    || !IsBoundedText(row["blockedReason"], 32, true))
                    return false;
                previousPhysicalSlot = physicalSlot;

                bool disabled = row.Value<bool>("disabled");
                string blockedReason = ReadString(row["blockedReason"]);
                if ((!disabled && blockedReason.Length != 0)
                    || (disabled
                        && !CandidateBlockedReasons.Contains(blockedReason)))
                    return false;

                JObject source = row["source"] as JObject;
                int sourceSlot;
                if (!IsExactObject(
                        source,
                        Set("containerId", "slot", "expectedLease"))
                    || ReadString(source["containerId"]) != "背包"
                    || !TryReadInteger(
                        source["slot"],
                        0,
                        MaxCandidatePhysicalSlot,
                        out sourceSlot)
                    || sourceSlot != physicalSlot
                    || !IsOpaque(ReadString(source["expectedLease"])))
                    return false;

                string itemKind;
                string use;
                string majorType;
                double quantity;
                if (!CharacterBuildProtocol.TryValidateItemProjection(
                        row["item"] as JObject,
                        out itemKind,
                        out use,
                        out majorType,
                        out quantity))
                    return false;
                string eligibilityReason = null;
                if (universalEquipmentBackpack)
                {
                    JObject eligibility = row["equipmentEligibility"] as JObject;
                    JArray eligibilitySlots = eligibility != null
                        ? eligibility["slots"] as JArray : null;
                    string[] expectedSlots =
                        CharacterBuildProtocol.CompatibleEquipmentSlotKeys(
                            itemKind, use, majorType, quantity);
                    eligibilityReason = ReadString(
                        eligibility != null ? eligibility["blockedReason"] : null);
                    if (!IsExactObject(
                            eligibility, Set("slots", "blockedReason"))
                        || eligibilitySlots == null
                        || eligibilitySlots.Count != expectedSlots.Length
                        || !IsBoundedText(
                            eligibility["blockedReason"], 32, true)
                        || (expectedSlots.Length == 0
                            && (itemKind == "equipment"
                                || CharacterBuildProtocol.IsEquipmentSlotKey(use)
                                || eligibilityReason.Length != 0))
                        || (eligibilityReason.Length != 0
                            && eligibilityReason != "level_locked"))
                        return false;
                    for (int eligibilityIndex = 0;
                            eligibilityIndex < expectedSlots.Length;
                            eligibilityIndex++)
                    {
                        JToken eligibilitySlot = eligibilitySlots[eligibilityIndex];
                        if (eligibilitySlot == null
                            || eligibilitySlot.Type != JTokenType.String
                            || ReadString(eligibilitySlot)
                                != expectedSlots[eligibilityIndex])
                            return false;
                    }
                }
                bool compatible = CharacterBuildProtocol.IsCandidateCompatible(
                    kind,
                    targetSlotKey,
                    itemKind,
                    use,
                    majorType,
                    quantity);
                if (candidateScope == "compatible")
                {
                    if (!compatible
                        || (kind == "equipment" && disabled
                            && blockedReason != "level_locked")
                        || (kind == "drug" && disabled
                            && blockedReason != "cooldown_active"
                            && blockedReason != "cooldown_unavailable"))
                        return false;
                }
                else
                {
                    if (universalEquipmentBackpack
                        && (compatible
                            ? (disabled != (eligibilityReason.Length != 0)
                                || blockedReason != eligibilityReason)
                            : (!disabled
                                || blockedReason != "incompatible_item")))
                        return false;
                    if ((!compatible
                            && (!disabled
                                || blockedReason != "incompatible_item"))
                        || (compatible && blockedReason == "incompatible_item")
                        || (blockedReason == "level_locked" && kind != "equipment")
                        || ((blockedReason == "cooldown_active"
                                || blockedReason == "cooldown_unavailable")
                            && kind != "drug"))
                        return false;
                }
            }
            return true;
        }

        private static bool IsTooltipProjection(
            JObject payload,
            JObject request)
        {
            if (!IsExactObject(
                    payload,
                    Set("v", "target", "itemName", "displayName", "iconName",
                        "itemType", "descHTML", "introHTML"))
                || !HasVersion(payload)
                || !IsTooltipTarget(payload["target"] as JObject, request)
                || !IsIdentityText(payload["itemName"], 256)
                || !IsIdentityText(payload["displayName"], 256)
                || !IsIdentityText(payload["iconName"], 256)
                || !IsBoundedText(payload["itemType"], 128, true)
                || !IsBoundedText(payload["descHTML"], 131072, true)
                || !IsBoundedText(payload["introHTML"], 131072, true)
                || (ReadString(payload["descHTML"]).Length == 0
                    && ReadString(payload["introHTML"]).Length == 0))
            {
                return false;
            }
            return true;
        }

        private static bool IsTooltipTarget(JObject target, JObject request)
        {
            if (target == null || request == null) return false;
            string kind = ReadString(target["kind"]);
            if (kind == "equipment")
            {
                string slotKey = ReadString(target["slotKey"]);
                return IsExactObject(target, Set("kind", "slotKey"))
                    && CharacterBuildProtocol.IsEquipmentSlotKey(slotKey)
                    && ReadString(request["slotKey"]) == slotKey
                    && request["drugSlot"] == null;
            }
            int targetDrugSlot;
            int requestedDrugSlot;
            return kind == "drug"
                && IsExactObject(target, Set("kind", "drugSlot"))
                && TryReadInteger(
                    target["drugSlot"], 0, 3, out targetDrugSlot)
                && request["slotKey"] == null
                && TryReadInteger(
                    request["drugSlot"], 0, 3, out requestedDrugSlot)
                && requestedDrugSlot == targetDrugSlot;
        }

        private static bool IsStatsProjection(JObject payload)
        {
            return IsExactObject(
                    payload,
                    Set("v", "groups", "stateHealth", "diagnostics"))
                && HasVersion(payload)
                && ReadString(payload["stateHealth"]) == "ok"
                && payload["groups"] is JArray
                && IsDiagnostics(payload["diagnostics"] as JArray);
        }

        private static bool IsDiagnostics(JArray diagnostics)
        {
            if (diagnostics == null || diagnostics.Count > 64) return false;
            foreach (JToken item in diagnostics)
                if (!IsSafeText(ReadString(item), 1, 256)) return false;
            return true;
        }

        private static bool IsPersistenceProof(JObject persistence)
        {
            return IsExactObject(persistence, Set("success", "changed"))
                && persistence["success"].Type == JTokenType.Boolean
                && persistence["changed"].Type == JTokenType.Boolean;
        }

        private bool TryCompleteMalformedResponse(
            int backendCallId,
            out PendingRequest entry)
        {
            entry = null;
            PanelPendingCall<PendingRequest> pending;
            if (!_pendingCalls.TryComplete(backendCallId, out pending))
                return false;
            entry = pending.Context;
            lock (_gate)
            {
                _productionPending.Remove(backendCallId);
                if (!IsCurrentBindingLocked(entry)) return false;
                DecrementPendingLocked();
                if (entry.IsWrite) MarkUnknownLocked(entry);
                if (entry.IsInitialSnapshot)
                    _initialSnapshotOutcomeUnknown = true;
                return true;
            }
        }

        private void StampAndPostProductionResponse(
            JObject response,
            PendingRequest entry)
        {
            JObject web = response != null
                ? (JObject)response.DeepClone() : new JObject();
            web["type"] = "panel_resp";
            web["panel"] = "workbench";
            web["domain"] = "loadout";
            web["cmd"] = entry.Command;
            web["callId"] = entry.WebCallId;
            web["panelInstanceId"] = entry.PanelInstanceId;
            bool requiresReconcile;
            string reconcileAfter;
            lock (_gate)
            {
                requiresReconcile = entry.IsWrite
                    && _writeState == "needs_reconcile";
                reconcileAfter = requiresReconcile ? _unknownCallId : null;
            }
            if (requiresReconcile)
            {
                web["requiresReconcile"] = true;
                web["reconcileAfterCallId"] = reconcileAfter;
            }
            PostToWeb(web.ToString(Formatting.None));
        }

        private void RejectAndRemember(
            string callId,
            string command,
            string error,
            bool preserveReconcile = false)
        {
            if (!_pendingCalls.TryRememberRejected(callId)) return;
            bool requiresReconcile = false;
            string reconcileAfterCallId = null;
            if (preserveReconcile)
            {
                lock (_gate)
                {
                    requiresReconcile = _writeState == "needs_reconcile"
                        && IsCallId(_unknownCallId);
                    reconcileAfterCallId =
                        requiresReconcile ? _unknownCallId : null;
                }
            }
            RespondError(
                callId,
                command,
                error,
                requiresReconcile,
                reconcileAfterCallId);
        }

        private void RespondError(
            string callId,
            string command,
            string error,
            bool requiresReconcile,
            string reconcileAfterCallId,
            string panelInstanceId = null,
            int? writeEpoch = null)
        {
            long? generation;
            long loadoutRevision;
            long liveRevision;
            long drugRevision;
            bool dirty;
            bool active;
            string boundPanel;
            int currentWriteEpoch;
            lock (_gate)
            {
                generation = _sessionGeneration;
                loadoutRevision = _loadoutRevision;
                liveRevision = _liveRevision;
                drugRevision = _drugRevision;
                dirty = _liveRefreshDirty;
                active = _sessionGeneration.HasValue
                    && _writeState != "finalized";
                boundPanel = _panelInstanceId;
                currentWriteEpoch = _writeEpoch;
            }
            var response = new JObject
            {
                ["type"] = "panel_resp",
                ["panel"] = "workbench",
                ["domain"] = "loadout",
                ["cmd"] = command ?? "",
                ["callId"] = callId ?? "",
                ["panelInstanceId"] = panelInstanceId ?? boundPanel,
                ["v"] = 1,
                ["success"] = false,
                ["error"] = error ?? "invalid_request",
                ["writeEpoch"] = writeEpoch ?? currentWriteEpoch,
                ["active"] = active,
                ["sessionGeneration"] = generation.HasValue
                    ? new JValue(generation.Value) : JValue.CreateNull(),
                ["loadoutRevision"] = loadoutRevision,
                ["liveRevision"] = liveRevision,
                ["liveRefreshDirty"] = dirty,
                ["drugRevision"] = drugRevision
            };
            if (requiresReconcile)
            {
                response["requiresReconcile"] = true;
                if (IsCallId(reconcileAfterCallId))
                    response["reconcileAfterCallId"] = reconcileAfterCallId;
            }
            PostToWeb(response.ToString(Formatting.None));
        }

        private void PostToWeb(string json)
        {
            if (_invokeOnUI != null)
                _invokeOnUI(delegate
                {
                    if (_postToWeb != null) _postToWeb(json);
                });
            else if (_postToWeb != null)
                _postToWeb(json);
        }

        private void NotifyCoordinatorSettledIfReady()
        {
            Action callback;
            lock (_gate)
                callback = CanReleaseBindingLocked()
                    ? _onCoordinatorSettled : null;
            if (callback != null) callback();
        }

        private static bool TryResolveCommand(
            string command,
            out bool isWrite,
            out UnknownKind kind,
            out MutationTarget mutationTarget)
        {
            isWrite = false;
            kind = UnknownKind.None;
            mutationTarget = MutationTarget.None;
            switch (command)
            {
                case "snapshot":
                case "candidates":
                case "tooltip":
                case "statsSnapshot":
                    return true;
                case "equipEquipment":
                case "unequipEquipment":
                    isWrite = true;
                    kind = UnknownKind.Mutation;
                    mutationTarget = MutationTarget.Equipment;
                    return true;
                case "equipDrug":
                case "unequipDrug":
                    isWrite = true;
                    kind = UnknownKind.Mutation;
                    mutationTarget = MutationTarget.Drug;
                    return true;
                case "flushLive":
                    isWrite = true;
                    kind = UnknownKind.FlushLive;
                    return true;
                case "finalize":
                    isWrite = true;
                    kind = UnknownKind.Finalize;
                    return true;
                default:
                    return false;
            }
        }

        private static bool IsKnownFailureCode(string failureCode)
        {
            switch (failureCode)
            {
                case "needs_reconcile":
                case "flush_failed":
                case "service_not_ready":
                case "invalid_drug_revision":
                case "invalid_loadout":
                case "invalid_payload":
                case "invalid_slot":
                case "unsupported_version":
                case "unsupported_cmd":
                case "projection_failed":
                case "live_unavailable":
                case "live_not_clean":
                case "level_locked":
                case "cooldown_active":
                case "cooldown_unavailable":
                case "incompatible_item":
                case "backpack_full":
                case "write_failed":
                case "write_busy":
                case "stats_failed":
                case "stats_unavailable":
                case "internal_error":
                case "session_active":
                case "stale_container":
                case "stale_drug_revision":
                case "session_not_active":
                case "stale_session":
                case "stale_panel_instance":
                case "stale_state":
                case "pause_lease_missing":
                    return true;
                default:
                    return false;
            }
        }

        private static bool IsMutationFailureCode(string failureCode)
        {
            switch (failureCode)
            {
                case "needs_reconcile":
                case "service_not_ready":
                case "invalid_drug_revision":
                case "invalid_loadout":
                case "invalid_payload":
                case "invalid_slot":
                case "unsupported_version":
                case "unsupported_cmd":
                case "projection_failed":
                case "level_locked":
                case "cooldown_active":
                case "cooldown_unavailable":
                case "incompatible_item":
                case "backpack_full":
                case "write_failed":
                case "write_busy":
                case "internal_error":
                case "stale_container":
                case "stale_drug_revision":
                case "stale_state":
                    return true;
                default:
                    return false;
            }
        }

        private static bool IsCallId(string value)
        {
            return !string.IsNullOrEmpty(value) && ValidCallId.IsMatch(value);
        }

        private static bool IsOpaque(string value)
        {
            return !string.IsNullOrEmpty(value) && ValidOpaque.IsMatch(value);
        }

        private static bool IsGeneration(long? value)
        {
            return value.HasValue && value.Value > 0 && value.Value <= int.MaxValue;
        }

        private static HashSet<string> Set(params string[] values)
        {
            return new HashSet<string>(values, StringComparer.Ordinal);
        }

        private static bool IsExactObject(
            JObject value,
            HashSet<string> expectedKeys)
        {
            if (value == null || expectedKeys == null
                || value.Count != expectedKeys.Count) return false;
            foreach (JProperty property in value.Properties())
                if (!expectedKeys.Contains(property.Name)) return false;
            return true;
        }

        private static bool HasVersion(JObject value)
        {
            int version;
            return value != null
                && TryReadInteger(value["v"], 1, 1, out version);
        }

        private static string ReadString(JToken token)
        {
            return token != null && token.Type == JTokenType.String
                ? token.Value<string>() : null;
        }

        private static bool TryReadInteger(
            JToken token,
            int minimum,
            int maximum,
            out int value)
        {
            value = 0;
            if (token == null || token.Type != JTokenType.Integer) return false;
            long raw;
            try { raw = token.Value<long>(); }
            catch { return false; }
            if (raw < minimum || raw > maximum) return false;
            value = (int)raw;
            return true;
        }

        private static bool TryReadInteger(
            JToken token,
            long minimum,
            long maximum,
            out long value)
        {
            value = 0;
            if (token == null || token.Type != JTokenType.Integer) return false;
            try { value = token.Value<long>(); }
            catch { return false; }
            return value >= minimum && value <= maximum;
        }

        private static bool IsBoundedText(
            JToken token,
            int maximumLength,
            bool allowEmpty)
        {
            string value = ReadString(token);
            if (value == null
                || value.Length > maximumLength
                || (!allowEmpty && value.Length == 0))
                return false;
            foreach (char c in value)
                if (char.IsControl(c)) return false;
            return true;
        }

        private static bool IsIdentityText(JToken token, int maximumLength)
        {
            string value = ReadString(token);
            return IsBoundedText(token, maximumLength, false)
                && value.Trim().Length != 0
                && !string.Equals(
                    value.Trim(), "undefined", StringComparison.OrdinalIgnoreCase);
        }

        private static bool IsSafeText(
            string value,
            int minimumLength,
            int maximumLength)
        {
            if (string.IsNullOrEmpty(value)
                || value.Length < minimumLength
                || value.Length > maximumLength) return false;
            foreach (char c in value)
                if (char.IsControl(c)) return false;
            return true;
        }

        private static bool IsStateHealth(JToken value)
        {
            string state = ReadString(value);
            return state == "ok" || state == "degraded";
        }
    }
}
