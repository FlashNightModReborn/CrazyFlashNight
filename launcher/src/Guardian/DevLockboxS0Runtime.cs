using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using CF7Launcher.Bus;

namespace CF7Launcher.Guardian
{
    public interface IDevLockboxS0PanelPort
    {
        bool IsAvailable { get; }
        bool IsIdleForTrackedOpen { get; }
        bool TryOpenTracked(string initDataJson, string panelInstanceId,
            Func<bool> executionGate, Action<PanelHostController.TrackedOpenOutcome> completed);
        bool TryCloseExact(string panelInstanceId, Action<bool> completed);
    }

    public sealed class DevLockboxS0PanelHostPort : IDevLockboxS0PanelPort
    {
        private readonly PanelHostController _panelHost;

        public DevLockboxS0PanelHostPort(PanelHostController panelHost)
        {
            _panelHost = panelHost;
        }

        public bool IsAvailable { get { return _panelHost != null; } }
        public bool IsIdleForTrackedOpen
        {
            get { return _panelHost != null && _panelHost.IsIdleForTrackedOpen; }
        }

        public bool TryOpenTracked(string initDataJson, string panelInstanceId,
            Func<bool> executionGate, Action<PanelHostController.TrackedOpenOutcome> completed)
        {
            return _panelHost != null && _panelHost.TryOpenTrackedPanel("lockbox", initDataJson,
                panelInstanceId, executionGate, completed);
        }

        public bool TryCloseExact(string panelInstanceId, Action<bool> completed)
        {
            return _panelHost != null && _panelHost.TryCloseTrackedPanelExact(
                "lockbox", panelInstanceId, completed);
        }
    }

    /// <summary>
    /// Actual S0 development wire.  This object is deliberately outside MessageRouter and
    /// TaskRegistry: its AS2 entry point is installed only as XmlSocketServer's dedicated handler.
    /// It owns the one-shot capability, process/generation binding, Web arm, tracked PanelHost
    /// reservation, and the exact result/query/close reconciliation protocol.
    /// </summary>
    public sealed class DevLockboxS0Runtime : IDisposable
    {
        public const int ProtocolVersion = 1;
        public const string SocketTask = "dev_lockbox_s0";
        public const string SocketResponseTask = "dev_lockbox_s0_response";
        public const string WebControlType = "lockbox_chest_s0_control";
        public const string WebBusinessType = "lockbox_chest_s0";

        private const int BindTimeoutMilliseconds = 2500;
        private const int AuthorityTimeoutMilliseconds = 2500;
        private const int DefaultReconcileRetryMilliseconds = 2500;
        private const int DefaultBindingAckTimeoutMilliseconds = 1000;
        private const int MaximumImmediateReleaseGenerationRetries = 8;

        public readonly struct GameProcessIdentity : IEquatable<GameProcessIdentity>
        {
            public GameProcessIdentity(int processId, long startTimeUtcTicks)
            {
                ProcessId = processId;
                StartTimeUtcTicks = startTimeUtcTicks;
            }

            public int ProcessId { get; }
            public long StartTimeUtcTicks { get; }
            public bool IsValid { get { return ProcessId > 0 && StartTimeUtcTicks > 0; } }
            public bool Equals(GameProcessIdentity other)
            {
                return ProcessId == other.ProcessId
                    && StartTimeUtcTicks == other.StartTimeUtcTicks;
            }
            public override bool Equals(object obj)
            {
                return obj is GameProcessIdentity other && Equals(other);
            }
            public override int GetHashCode()
            {
                return HashCode.Combine(ProcessId, StartTimeUtcTicks);
            }
        }

        private enum CapabilityState
        {
            None,
            WebArmPending,
            As2BootstrapPending,
            Ready,
            Consumed
        }

        private sealed class CapabilityBinding
        {
            public string Capability;
            public string Digest;
            public int ConnectionGeneration;
            public GameProcessIdentity Process;
            public long DocumentEpoch;
            public bool ResumeActive;
            public CapabilityState State;
            public Timer AckTimer;
        }

        private sealed class OwnedTimerSlot
        {
            public Timer Timer;
            public long Version;
        }

        private readonly object _sync = new object();
        private readonly IDevLockboxS0PanelPort _panel;
        private readonly Func<bool> _isDevRepository;
        private readonly Func<string> _environmentGateProvider;
        private readonly Func<GameProcessIdentity?> _gameProcessProvider;
        private readonly Func<string, int, bool> _sendSocketForGeneration;
        private readonly Func<string, bool> _postToWeb;
        private readonly Func<int, bool> _acquireTrackedPause;
        private readonly Func<int, bool> _releaseTrackedPause;
        private readonly Func<string> _capabilityFactory;
        private readonly int _reconcileRetryMilliseconds;
        private readonly int _bindTimeoutMilliseconds;
        private readonly int _bindingAckTimeoutMilliseconds;
        private readonly DevLockboxS0Coordinator _coordinator;
        private readonly HashSet<string> _usedCapabilities =
            new HashSet<string>(StringComparer.Ordinal);

        private CapabilityBinding _binding;
        private int _liveGeneration;
        private int _disconnectedGenerationHighWater;
        private bool _connectionAlive;
        private bool _disposed;
        private bool _disposeCompleted;
        private string _activeCapability;
        private CapabilityBinding _activeBinding;
        private string _activeSessionId;
        private DevLockboxS0Coordinator.AttemptIdentity _activeIdentity;
        private GameProcessIdentity? _activeProcessBinding;
        private string _pendingOpenFailureReason;
        private bool _nativePanelClosed;
        private bool _nativeCloseInProgress;
        private bool _pauseReleaseInProgress;
        private bool _processReplacementRecoveryStarted;
        private bool _genericUnpausePending;
        private readonly OwnedTimerSlot _bindTimer = new OwnedTimerSlot();
        private readonly OwnedTimerSlot _authorityTimer = new OwnedTimerSlot();
        private Timer _bindingRetryTimer;
        private long _bindingRetryVersion;
        private Timer _reconcileTimer;
        private int _reconcileGeneration;
        private int _reconcileActionsInFlight;
        private int _authorityActionsInFlight;
        private int _outboundActionsInFlight;
        private readonly Dictionary<int, int> _outboundActionsByThread =
            new Dictionary<int, int>();
        private string _lastWebAuthorityCommand;
        private JObject _lastWebAuthorityPayload;
        private bool _webNavigationPending;
        private ulong _pendingNavigationId;
        private bool _pendingNavigationLoadedNewDocument;
        private DevLockboxS0Coordinator.AttemptIdentity _oldDocumentIdentity;

        public DevLockboxS0Runtime(IDevLockboxS0PanelPort panel,
            Func<bool> isDevRepository,
            Func<string> environmentGateProvider,
            Func<GameProcessIdentity?> gameProcessProvider,
            Func<string, int, bool> sendSocketForGeneration,
            Func<string, bool> postToWeb,
            Func<int, bool> acquireTrackedPause,
            Func<int, bool> releaseTrackedPause,
            long initialDocumentEpoch = 1,
            Func<string> capabilityFactory = null,
            Func<string> flowHandleFactory = null,
            Func<string> requestTokenFactory = null,
            Func<string> panelInstanceIdFactory = null,
            int closeAckRetryMilliseconds = DefaultReconcileRetryMilliseconds,
            int bindTimeoutMilliseconds = BindTimeoutMilliseconds,
            int bindingAckTimeoutMilliseconds = DefaultBindingAckTimeoutMilliseconds)
        {
            _panel = panel;
            _isDevRepository = isDevRepository ?? throw new ArgumentNullException(nameof(isDevRepository));
            _environmentGateProvider = environmentGateProvider
                ?? throw new ArgumentNullException(nameof(environmentGateProvider));
            _gameProcessProvider = gameProcessProvider
                ?? throw new ArgumentNullException(nameof(gameProcessProvider));
            _sendSocketForGeneration = sendSocketForGeneration
                ?? throw new ArgumentNullException(nameof(sendSocketForGeneration));
            _postToWeb = postToWeb ?? throw new ArgumentNullException(nameof(postToWeb));
            _acquireTrackedPause = acquireTrackedPause
                ?? throw new ArgumentNullException(nameof(acquireTrackedPause));
            _releaseTrackedPause = releaseTrackedPause
                ?? throw new ArgumentNullException(nameof(releaseTrackedPause));
            _capabilityFactory = capabilityFactory ?? CreateCapability;
            _reconcileRetryMilliseconds = Math.Max(10, closeAckRetryMilliseconds);
            _bindTimeoutMilliseconds = Math.Max(10, bindTimeoutMilliseconds);
            _bindingAckTimeoutMilliseconds = Math.Max(10, bindingAckTimeoutMilliseconds);
            _coordinator = new DevLockboxS0Coordinator(initialDocumentEpoch,
                flowHandleFactory ?? delegate { return "flow." + CreateOpaqueId(); },
                requestTokenFactory ?? delegate { return "request." + CreateOpaqueId(); },
                panelInstanceIdFactory ?? delegate { return "panel.lockbox." + CreateOpaqueId(); });
        }

        public long DocumentEpoch { get { return _coordinator.WebDocumentEpoch; } }
        public bool HoldsGlobalPause { get { return _coordinator.HoldsGlobalPause; } }

        /// <summary>
        /// Defense-in-depth for the generic minigame log boundary.  While S0 owns the pause,
        /// WebOverlay may log only this exact four-field observation; raw Lockbox session data is
        /// rejected without serialization.
        /// </summary>
        public static bool TryNormalizeMinigameTelemetry(JToken value, out JObject normalized)
        {
            normalized = null;
            JObject payload = value as JObject;
            if (!HasExactKeys(payload, "game", "kind", "data")) return false;
            string game;
            string kind;
            if (!TryReadString(payload, "game", out game) || game != "lockbox"
                || !TryReadString(payload, "kind", out kind) || kind != "s0_telemetry")
                return false;
            JObject data = payload["data"] as JObject;
            if (!HasExactKeys(data, "eventCategory", "resultCategory",
                "durationBucket", "errorCategory")) return false;
            string eventCategory;
            string resultCategory;
            string durationBucket;
            string errorCategory;
            if (!TryReadString(data, "eventCategory", out eventCategory)
                || !IsTelemetryEvent(eventCategory)
                || !TryReadString(data, "resultCategory", out resultCategory)
                || !IsTelemetryResult(resultCategory)
                || !TryReadString(data, "durationBucket", out durationBucket)
                || !IsTelemetryDuration(durationBucket)
                || !TryReadString(data, "errorCategory", out errorCategory)
                || !IsTelemetryError(errorCategory)) return false;
            normalized = new JObject
            {
                ["eventCategory"] = eventCategory,
                ["resultCategory"] = resultCategory,
                ["durationBucket"] = durationBucket,
                ["errorCategory"] = errorCategory
            };
            return true;
        }
        public bool CanRebuildWebDocument
        {
            get
            {
                lock (_sync)
                    return !_webNavigationPending && _coordinator.CanRebuildWebDocument;
            }
        }

        public bool AllowRegularPanelOpen(string panelName)
        {
            bool allowed = !_coordinator.ShouldRejectOtherPanelOpen;
            if (!allowed) Log("gate_rejected", "code=other_panel_blocked origin=panel_host");
            return allowed;
        }

        /// <summary>
        /// Linearizes the generic web-panel unpause write with S0 begin.  The socket callback is
        /// intentionally executed while holding the runtime lock: XmlSocketServer invokes this
        /// runtime outside its client lock, so the lock order is runtime -> socket and cannot be
        /// inverted by the dedicated receive path.  A begin therefore happens wholly before this
        /// check (and blocks the write), or wholly after the write (and reacquires the tracked
        /// pause before any panel side effect).
        /// </summary>
        public bool TryReleaseGenericPause()
        {
            bool delivered = false;
            string rejection = null;
            int generation = 0;
            lock (_sync)
            {
                if (_disposed)
                    rejection = "disposed";
                else if (_pauseReleaseInProgress || _coordinator.ShouldBlockGenericUnpause)
                    rejection = "s0_active";
                else if (!_connectionAlive || _liveGeneration <= 0)
                {
                    rejection = "socket_not_ready";
                    _genericUnpausePending = true;
                }
                else
                {
                    generation = _liveGeneration;
                    try
                    {
                        delivered = _sendSocketForGeneration(
                            "{\"task\":\"cmd\",\"action\":\"webPanelUnpause\"}", generation);
                    }
                    catch
                    {
                        delivered = false;
                    }
                    _genericUnpausePending = !delivered;
                }
            }
            if (rejection != null)
                Log("generic_unpause_blocked", "reason=" + rejection);
            else
                Log("generic_unpause", "delivered=" + Lower(delivered) + " gen=" + generation);
            return delivered;
        }

        /// <summary>
        /// Called after PanelHost has completely returned to idle.  This closes the race where a
        /// normal panel opens after S0 arm but before AS2 begin consumes that one-shot capability.
        /// The failed begin is never replayed; a fresh capability is armed only after idle.
        /// </summary>
        public void OnPanelHostClosed(string panelName, string panelInstanceId)
        {
            Log("panel_host_idle", "panel=" + SafeWord(panelName)
                + " instanceDigest=" + Digest(panelInstanceId));
            DevLockboxS0Coordinator.AttemptIdentity identity;
            lock (_sync) identity = _activeIdentity;
            if (identity != null && panelName == "lockbox"
                && panelInstanceId == identity.PanelInstanceId)
            {
                RecordNativePanelClosed(identity, "panel_host_closed_event");
            }
            if (!_coordinator.HoldsGlobalPause) TryIssueWebArm();
        }

        /// <summary>
        /// PanelClosed may run synchronously while the queue pump still owns _processing.  This
        /// separate signal is emitted only after the pump has cleared that bit and released its
        /// lock, providing the missing retry edge for a fresh arm after fast failure settlement.
        /// </summary>
        public void OnPanelHostOrchestrationSettled()
        {
            bool pauseHeld = _coordinator.HoldsGlobalPause;
            Log("panel_queue_idle", "pauseHeld=" + Lower(pauseHeld));
            if (!pauseHeld) TryIssueWebArm();
        }

        public void OnSocketReady(int connectionGeneration)
        {
            if (connectionGeneration <= 0) return;
            CapabilityBinding invalidatedBinding = null;
            bool staleReady = false;
            lock (_sync)
            {
                if (_disposed) return;
                if (connectionGeneration <= _disconnectedGenerationHighWater
                    || (_liveGeneration > 0 && connectionGeneration < _liveGeneration))
                {
                    staleReady = true;
                }
                else
                {
                    _connectionAlive = true;
                    _liveGeneration = connectionGeneration;
                    if (_binding != null && _binding.ConnectionGeneration != connectionGeneration)
                    {
                        invalidatedBinding = _binding;
                        _binding = null;
                    }
                }
            }
            if (staleReady)
            {
                Log("gate_rejected", "code=stale_socket_ready origin=socket gen="
                    + connectionGeneration);
                return;
            }
            DisposeBindingAckTimer(invalidatedBinding);
            Log("socket_ready", "gen=" + connectionGeneration);
            if (_coordinator.HoldsGlobalPause)
            {
                // A prior release may have raced a newly accepted but not-yet-adopted socket.
                // Retry against this exact adopted generation before issuing resume bootstrap.
                TryReleasePauseAndReset();
                if (_coordinator.HoldsGlobalPause)
                    TryIssueActiveReconnectBootstrap(connectionGeneration);
            }
            else
            {
                bool retryGeneric;
                lock (_sync) retryGeneric = _genericUnpausePending;
                if (retryGeneric && !TryReleaseGenericPause()) return;
                TryIssueWebArm();
            }
        }

        public void OnWebReady()
        {
            if (!_coordinator.HoldsGlobalPause)
            {
                bool retryGeneric;
                lock (_sync) retryGeneric = _genericUnpausePending;
                if (retryGeneric && !TryReleaseGenericPause()) return;
                TryIssueWebArm();
            }
        }

        public void OnSocketDisconnected(int connectionGeneration)
        {
            DevLockboxS0Coordinator.AttemptIdentity identity = null;
            CapabilityBinding invalidatedBinding = null;
            Timer invalidatedRetry = null;
            lock (_sync)
            {
                if (_disposed) return;
                if (connectionGeneration > _disconnectedGenerationHighWater)
                    _disconnectedGenerationHighWater = connectionGeneration;
                if (connectionGeneration < _liveGeneration) return;
                if (connectionGeneration == _liveGeneration && !_connectionAlive) return;
                if (connectionGeneration > _liveGeneration)
                    _liveGeneration = connectionGeneration;
                _connectionAlive = false;
                invalidatedBinding = _binding;
                _binding = null;
                invalidatedRetry = DetachBindingRetryTimerLocked();
                identity = _activeIdentity;
            }
            DisposeBindingAckTimer(invalidatedBinding);
            invalidatedRetry?.Dispose();
            Log("socket_disconnected", "gen=" + connectionGeneration);
            if (identity != null && _coordinator.State == DevLockboxS0Coordinator.FlowState.ResultPending
                && _coordinator.SubmittedFlowCallId == 1)
            {
                MarkResultUnknown(identity, 1);
            }
            if (identity != null) EnsureNativePanelClosed(identity, "socket_disconnected");
        }

        public bool TryHandleSocketJson(string json, int connectionGeneration, out string response)
        {
            response = null;
            JObject message;
            try { message = JObject.Parse(json); }
            catch
            {
                if (!string.IsNullOrEmpty(json)
                    && json.IndexOf(SocketTask, StringComparison.Ordinal) >= 0)
                {
                    Log("gate_rejected", "code=socket_json_malformed origin=socket");
                    return true;
                }
                return false;
            }
            string task;
            if (!TryReadString(message, "task", out task) || task != SocketTask) return false;

            bool releaseInProgress;
            lock (_sync)
            {
                if (_disposed) return true;
                releaseInProgress = _pauseReleaseInProgress;
            }
            if (releaseInProgress)
            {
                Log("gate_rejected", "code=pause_release_in_progress origin=socket");
                return true;
            }

            JObject payload = message["payload"] as JObject;
            string action;
            if (!TryReadString(payload, "action", out action)) action = null;
            if (action == "bootstrap_ack")
            {
                HandleAs2BootstrapAck(message, payload, connectionGeneration);
                return true;
            }
            if (action == "begin")
            {
                response = HandleBegin(message, payload, connectionGeneration);
                return true;
            }
            if (action == "result_ack")
            {
                HandleAuthorityResultAck(message, payload, connectionGeneration);
                return true;
            }
            if (action == "result_query_reply")
            {
                HandleAuthorityQueryReply(message, payload, connectionGeneration);
                return true;
            }
            if (action == "revocation_ack")
            {
                HandleRevocationAck(message, payload, connectionGeneration);
                return true;
            }
            if (action == "authority_terminal")
            {
                HandleAuthorityTerminal(message, payload, connectionGeneration);
                return true;
            }

            Log("gate_rejected", "code=socket_action_not_allowed origin=socket");
            response = BuildBeginFailure(message["callId"], "action_not_allowed");
            return true;
        }

        public bool TryHandleWebMessage(JObject message)
        {
            if (message == null) return false;
            string type;
            if (!TryReadString(message, "type", out type)) return false;
            if (type != WebControlType && type != WebBusinessType) return false;
            if (!HasExactKeys(message, "type", "cmd", "payload"))
            {
                Log("gate_rejected", "code=web_envelope_mismatch origin=web_control");
                return true;
            }
            lock (_sync)
            {
                if (_disposed) return true;
                if (_pauseReleaseInProgress)
                {
                    Log("gate_rejected", "code=pause_release_in_progress origin=web_control");
                    return true;
                }
                if (_webNavigationPending)
                {
                    Log("gate_rejected", "code=web_navigation_pending origin=web_control");
                    return true;
                }
            }
            string command;
            if (!TryReadString(message, "cmd", out command))
            {
                Log("gate_rejected", "code=web_command_not_allowed origin=web_control");
                return true;
            }
            JObject payload = message["payload"] as JObject;
            if (type == WebControlType)
            {
                if (command == "armed") HandleWebArmed(payload);
                else if (command == "rejected") HandleWebArmRejected(payload);
                else if (command == "runtime_rejected") HandleWebRuntimeRejected(payload);
                else if (command == "teardown_ack") HandleWebTeardownAck(payload);
                else Log("gate_rejected", "code=web_control_not_allowed origin=web_control");
                return true;
            }

            bool allowProcessReplacementCloseAck;
            lock (_sync)
            {
                allowProcessReplacementCloseAck = command == "close_ack"
                    && _processReplacementRecoveryStarted && _activeIdentity != null;
            }
            if (!allowProcessReplacementCloseAck && !IsCurrentProcessAndConnectionValid())
            {
                Log("gate_rejected", "code=process_or_generation_mismatch origin=web_business");
                return true;
            }
            if (command == "bind") HandleWebBind(payload);
            else if (command == "bind_query_result") HandleWebBindQueryResult(payload);
            else if (command == "result") HandleWebResult(payload);
            else if (command == "result_query") HandleWebResultQuery(payload);
            else if (command == "close_ack") HandleWebCloseAck(payload);
            else Log("gate_rejected", "code=web_command_not_allowed origin=web_business");
            return true;
        }

        public void OnWebDocumentNavigationStarting(ulong navigationId)
        {
            if (navigationId == 0) return;
            DevLockboxS0Coordinator.AttemptIdentity active;
            CapabilityBinding invalidatedBinding = null;
            Timer invalidatedRetry = null;
            lock (_sync)
            {
                if (_disposed) return;
                active = _coordinator.ActiveIdentity;
                _webNavigationPending = true;
                _pendingNavigationId = navigationId;
                _pendingNavigationLoadedNewDocument = false;
                _oldDocumentIdentity = active;
                if (active == null)
                {
                    invalidatedBinding = _binding;
                    _binding = null;
                    invalidatedRetry = DetachBindingRetryTimerLocked();
                }
            }
            // Active-flow resume bootstrap belongs to the AS2 authority connection, not to the
            // DOM being navigated.  Preserve its exact owner timer; only an idle document arm is
            // invalidated here.
            DisposeBindingAckTimer(invalidatedBinding);
            invalidatedRetry?.Dispose();
            Log("document_navigation_start", "navigationId=" + navigationId
                + " active=" + Lower(active != null));
        }

        public void OnWebDocumentContentLoading(ulong navigationId)
        {
            lock (_sync)
            {
                if (_disposed) return;
                if (_webNavigationPending && navigationId == _pendingNavigationId)
                    _pendingNavigationLoadedNewDocument = true;
            }
        }

        public void OnWebDocumentNavigationCompleted(ulong navigationId, bool isSuccess)
        {
            DevLockboxS0Coordinator.AttemptIdentity oldIdentity;
            bool loadedNewDocument;
            lock (_sync)
            {
                if (_disposed) return;
                if (!_webNavigationPending || navigationId != _pendingNavigationId)
                {
                    Log("gate_rejected", "code=navigation_completion_mismatch origin=web_control");
                    return;
                }
                _webNavigationPending = false;
                _pendingNavigationId = 0;
                loadedNewDocument = _pendingNavigationLoadedNewDocument;
                _pendingNavigationLoadedNewDocument = false;
                oldIdentity = _oldDocumentIdentity;
                _oldDocumentIdentity = null;
            }
            if (!isSuccess || !loadedNewDocument)
            {
                Log("document_navigation_failed", "navigationId=" + navigationId
                    + " success=" + Lower(isSuccess)
                    + " loadedNewDocument=" + Lower(loadedNewDocument)
                    + " active=" + Lower(oldIdentity != null));
                if (!_coordinator.HoldsGlobalPause) TryIssueWebArm();
                return;
            }
            long oldEpoch = _coordinator.WebDocumentEpoch;
            if (oldEpoch >= DevLockboxS0Coordinator.MaximumWebDocumentEpoch)
            {
                Log("gate_rejected", "code=document_epoch_exhausted origin=web_control");
                return;
            }
            if (!_coordinator.AdvanceWebDocumentEpoch(oldEpoch + 1)) return;
            lock (_sync)
            {
                if (oldIdentity == null) _binding = null;
            }
            Log("document_epoch_advance", "navigationId=" + navigationId
                + " old=" + oldEpoch + " new=" + (oldEpoch + 1)
                + " active=" + Lower(oldIdentity != null));
            if (oldIdentity != null)
            {
                bool proved = _coordinator.ConfirmOldDocumentTeardown(oldIdentity.FlowHandle,
                    oldIdentity.PanelInstanceId, oldIdentity.WebDocumentEpoch);
                Log("old_document_teardown", "proved=" + Lower(proved)
                    + " panelDigest=" + Digest(oldIdentity.PanelInstanceId));
                if (proved)
                {
                    StartReconcileTick(oldIdentity);
                    DevLockboxS0Coordinator.FlowState state = _coordinator.State;
                    if (state == DevLockboxS0Coordinator.FlowState.RevokePending)
                    {
                        Log("document_recovery", "path=pre_result state=revoke_pending");
                        SendOpenFailed(oldIdentity, GetActiveSessionId(), "web_bind_rejected");
                    }
                    else if (state == DevLockboxS0Coordinator.FlowState.ReconcileRequired
                        && _coordinator.UnknownFlowCallId == 1)
                    {
                        bool sent = SendAuthorityQuery(oldIdentity, "document_teardown");
                        Log("document_recovery", "path=post_result state=reconcile_required"
                            + " unknownFlowCallId=1 delivered=" + Lower(sent));
                    }
                    EnsureNativePanelClosed(oldIdentity, "document_teardown");
                    TryReleasePauseAndReset();
                }
            }
            if (!_coordinator.HoldsGlobalPause) TryIssueWebArm();
        }

        private void TryIssueWebArm()
        {
            bool retryGenericUnpause;
            lock (_sync)
            {
                if (_disposed || !_connectionAlive || _webNavigationPending
                    || _coordinator.HoldsGlobalPause) return;
                retryGenericUnpause = _genericUnpausePending;
            }
            // Every fresh-arm edge shares this admission path.  A failed generic unpause cannot
            // be bypassed by panel-idle, navigation, timeout, or release-completion callbacks.
            if (retryGenericUnpause && !TryReleaseGenericPause()) return;
            lock (_sync)
            {
                // Service a pending ordinary-panel unpause even when a usable S0 binding already
                // exists.  Only decide whether a fresh arm is needed after that release attempt.
                if (_disposed || !_connectionAlive || _webNavigationPending
                    || _coordinator.HoldsGlobalPause || _genericUnpausePending) return;
                if (_binding != null && (_binding.State == CapabilityState.WebArmPending
                    || _binding.State == CapabilityState.As2BootstrapPending
                    || _binding.State == CapabilityState.Ready)) return;
            }

            CapabilityBinding binding;
            string rejection = ValidateArmPrerequisites(out binding);
            if (rejection != null)
            {
                Log("gate_rejected", "code=" + rejection + " origin=socket");
                return;
            }

            bool assigned = false;
            bool timerStarted = false;
            bool posted = false;
            bool clearedForRetry = false;
            Timer supersededRetry = null;
            GameProcessIdentity? currentProcess = SafeGetProcess();
            lock (_sync)
            {
                if (!_disposed && _connectionAlive && !_webNavigationPending
                    && !_coordinator.HoldsGlobalPause
                    && !_genericUnpausePending
                    && _liveGeneration == binding.ConnectionGeneration
                    && _coordinator.WebDocumentEpoch == binding.DocumentEpoch
                    && currentProcess.HasValue && currentProcess.Value.Equals(binding.Process)
                    && (_binding == null || (_binding.State != CapabilityState.WebArmPending
                        && _binding.State != CapabilityState.As2BootstrapPending
                        && _binding.State != CapabilityState.Ready)))
                {
                    _binding = binding;
                    assigned = true;
                    supersededRetry = DetachBindingRetryTimerLocked();
                    timerStarted = StartBindingAckTimer(binding,
                        CapabilityState.WebArmPending, "web_arm_ack_timeout");
                    if (timerStarted)
                    {
                        JObject payload = BuildArmPayload(binding);
                        JObject envelope = new JObject
                        {
                            ["type"] = WebControlType,
                            ["cmd"] = "arm",
                            ["payload"] = payload
                        };
                        try { posted = _postToWeb(envelope.ToString(Formatting.None)); }
                        catch { posted = false; }
                    }
                    if (!posted && ReferenceEquals(_binding, binding)
                        && binding.State == CapabilityState.WebArmPending)
                    {
                        _binding = null;
                        clearedForRetry = true;
                    }
                }
                if (!assigned) _usedCapabilities.Remove(binding.Capability);
            }
            supersededRetry?.Dispose();
            if (!assigned) return;
            if (!posted)
            {
                if (clearedForRetry)
                {
                    DisposeBindingAckTimer(binding);
                    Log("gate_rejected", "code=web_unavailable origin=web_control");
                    ScheduleBindingRetry(false, binding.ConnectionGeneration);
                }
                return;
            }
            Log("arm_issued", "gen=" + binding.ConnectionGeneration
                + " pid=" + binding.Process.ProcessId + " epoch=" + binding.DocumentEpoch
                + " capDigest=" + binding.Digest);
        }

        private void TryIssueActiveReconnectBootstrap(int connectionGeneration)
        {
            if (_disposed || !_isDevRepository()
                || _environmentGateProvider() != DevLockboxS0Coordinator.RequiredEnvironmentValue
                || _panel == null || !_panel.IsAvailable)
            {
                Log("gate_rejected", "code=reconnect_prerequisite_failed origin=socket");
                return;
            }
            GameProcessIdentity? expected;
            DevLockboxS0Coordinator.AttemptIdentity expectedIdentity;
            lock (_sync)
            {
                if (_disposed || !_connectionAlive || _liveGeneration != connectionGeneration
                    || _pauseReleaseInProgress || !_coordinator.HoldsGlobalPause
                    || _processReplacementRecoveryStarted
                    || _activeIdentity == null || !_activeProcessBinding.HasValue
                    || _binding != null) return;
                expected = _activeProcessBinding;
                expectedIdentity = _activeIdentity;
            }
            GameProcessIdentity? current = SafeGetProcess();
            if (!expected.HasValue || !current.HasValue || !current.Value.Equals(expected.Value))
            {
                Log("gate_rejected", "code=reconnect_process_mismatch origin=socket");
                StartProcessReplacementRecovery(expectedIdentity, "reconnect_process_mismatch");
                return;
            }
            string capability;
            try { capability = _capabilityFactory(); }
            catch { capability = null; }
            if (!IsOpaque(capability) || !TryRegisterCapability(capability))
            {
                Log("gate_rejected", "code=capability_generation_failed origin=socket");
                return;
            }
            CapabilityBinding binding = new CapabilityBinding
            {
                Capability = capability,
                Digest = Digest(capability),
                ConnectionGeneration = connectionGeneration,
                Process = current.Value,
                DocumentEpoch = _coordinator.WebDocumentEpoch,
                ResumeActive = true,
                State = CapabilityState.As2BootstrapPending
            };
            bool assigned = false;
            bool sent = false;
            bool clearedForRetry = false;
            Timer supersededRetry = null;
            lock (_sync)
            {
                if (!_disposed && _connectionAlive && _liveGeneration == connectionGeneration
                    && !_pauseReleaseInProgress && _coordinator.HoldsGlobalPause
                    && ReferenceEquals(_activeIdentity, expectedIdentity)
                    && _activeProcessBinding.HasValue
                    && _activeProcessBinding.Value.Equals(expected.Value)
                    && _binding == null)
                {
                    _binding = binding;
                    assigned = true;
                    supersededRetry = DetachBindingRetryTimerLocked();
                    if (StartBindingAckTimer(binding, CapabilityState.As2BootstrapPending,
                        "as2_bootstrap_ack_timeout"))
                    {
                        // Linearize the exact-generation send with pause release/fresh arm.  The
                        // production callback follows runtime -> socket lock order and is safe here.
                        sent = SendAs2Bootstrap(binding);
                    }
                    if (!sent && ReferenceEquals(_binding, binding)
                        && binding.State == CapabilityState.As2BootstrapPending)
                    {
                        _binding = null;
                        clearedForRetry = true;
                    }
                }
                if (!assigned) _usedCapabilities.Remove(binding.Capability);
            }
            supersededRetry?.Dispose();
            if (!assigned)
            {
                Log("reconnect_bootstrap_superseded", "gen=" + connectionGeneration);
                return;
            }
            Log("reconnect_bootstrap_sent", "gen=" + connectionGeneration
                + " pid=" + binding.Process.ProcessId + " epoch=" + binding.DocumentEpoch
                + " resumeActive=true capDigest=" + binding.Digest
                + " delivered=" + Lower(sent));
            if (!sent)
            {
                DisposeBindingAckTimer(binding);
                if (clearedForRetry)
                    ScheduleBindingRetry(true, binding.ConnectionGeneration);
            }
        }

        private string ValidateArmPrerequisites(out CapabilityBinding binding)
        {
            binding = null;
            if (_disposed) return "disposed";
            if (!_isDevRepository()) return "not_dev_repository";
            if (!string.Equals(_environmentGateProvider(),
                DevLockboxS0Coordinator.RequiredEnvironmentValue, StringComparison.Ordinal))
                return "environment_gate_closed";
            if (_panel == null || !_panel.IsAvailable) return "panel_host_unavailable";
            if (!_panel.IsIdleForTrackedOpen) return "panel_orchestration_busy";
            int generation;
            lock (_sync)
            {
                if (!_connectionAlive || _liveGeneration <= 0) return "socket_not_ready";
                generation = _liveGeneration;
            }
            GameProcessIdentity? process = SafeGetProcess();
            if (!process.HasValue || !process.Value.IsValid) return "game_process_unavailable";
            string capability;
            try { capability = _capabilityFactory(); }
            catch { return "capability_generation_failed"; }
            if (!IsOpaque(capability) || !TryRegisterCapability(capability))
                return "capability_generation_failed";
            binding = new CapabilityBinding
            {
                Capability = capability,
                Digest = Digest(capability),
                ConnectionGeneration = generation,
                Process = process.Value,
                DocumentEpoch = _coordinator.WebDocumentEpoch,
                ResumeActive = false,
                State = CapabilityState.WebArmPending
            };
            return null;
        }

        private void HandleWebArmed(JObject payload)
        {
            CapabilityBinding binding;
            lock (_sync) { binding = _binding; }
            if (binding == null || binding.State != CapabilityState.WebArmPending
                || !IsExactArmPayload(payload, binding))
            {
                Log("gate_rejected", "code=web_arm_mismatch origin=web_control");
                return;
            }
            if (!IsCurrentProcessAndConnectionValid(binding))
            {
                Log("gate_rejected", "code=process_or_generation_mismatch origin=web_control");
                return;
            }
            bool transitioned = false;
            bool sent = false;
            bool clearedForRetry = false;
            lock (_sync)
            {
                if (ReferenceEquals(_binding, binding)
                    && binding.State == CapabilityState.WebArmPending
                    && !_disposed && _connectionAlive
                    && _liveGeneration == binding.ConnectionGeneration)
                {
                    binding.State = CapabilityState.As2BootstrapPending;
                    transitioned = true;
                    if (StartBindingAckTimer(binding, CapabilityState.As2BootstrapPending,
                        "as2_bootstrap_ack_timeout"))
                    {
                        // Keep state transition, timer ownership, and the generation-bound socket
                        // dispatch in one Runtime critical section.  A newer ready/dispose cannot
                        // overtake this dispatch and then be overwritten by the stale operation.
                        sent = SendAs2Bootstrap(binding);
                    }
                    if (!sent && ReferenceEquals(_binding, binding)
                        && binding.State == CapabilityState.As2BootstrapPending)
                    {
                        _binding = null;
                        clearedForRetry = true;
                    }
                }
            }
            if (!transitioned) return;
            Log("web_armed", "gen=" + binding.ConnectionGeneration
                + " pid=" + binding.Process.ProcessId + " epoch=" + binding.DocumentEpoch
                + " capDigest=" + binding.Digest);
            if (!sent)
            {
                if (clearedForRetry)
                {
                    DisposeBindingAckTimer(binding);
                    Log("gate_rejected", "code=as2_bootstrap_not_delivered origin=socket");
                    ScheduleBindingRetry(false, binding.ConnectionGeneration);
                }
            }
        }

        private void HandleWebArmRejected(JObject payload)
        {
            CapabilityBinding binding;
            lock (_sync) { binding = _binding; }
            string code;
            if (binding == null || binding.State != CapabilityState.WebArmPending || payload == null
                || !HasExactKeys(payload, "protocolVersion", "capability",
                    "connectionGeneration", "gameProcessId", "documentEpoch", "source",
                    "fixture", "code")
                || !ArmValuesMatch(payload, binding)
                || !TryReadString(payload, "code", out code) || !IsOpaque(code))
            {
                Log("gate_rejected", "code=web_rejection_mismatch origin=web_control");
                return;
            }
            bool cleared = false;
            lock (_sync)
            {
                if (ReferenceEquals(_binding, binding)
                    && binding.State == CapabilityState.WebArmPending)
                {
                    _binding = null;
                    cleared = true;
                }
            }
            if (!cleared)
            {
                Log("gate_rejected", "code=web_rejection_mismatch origin=web_control");
                return;
            }
            DisposeBindingAckTimer(binding);
            Log("gate_rejected", "code=web_arm_rejected origin=web_control reason="
                + SafeWord(code));
            if (code == "panel_orchestration_busy" || code == "wire_busy"
                || code == "wire_loading")
                ScheduleBindingRetry(false, binding.ConnectionGeneration);
        }

        private void HandleWebRuntimeRejected(JObject payload)
        {
            CapabilityBinding binding;
            DevLockboxS0Coordinator.AttemptIdentity identity;
            lock (_sync)
            {
                binding = _activeBinding;
                identity = _activeIdentity;
            }
            string code;
            if (!TryReadString(payload, "code", out code)) code = null;
            if (binding == null || binding.State != CapabilityState.Consumed || identity == null
                || payload == null
                || !HasExactKeys(payload, "protocolVersion", "capability",
                    "connectionGeneration", "gameProcessId", "documentEpoch", "source",
                    "fixture", "code")
                || !ArmValuesMatch(payload, binding) || !IsRuntimeOpenRejection(code))
            {
                Log("gate_rejected", "code=web_runtime_rejection_mismatch origin=web_control");
                return;
            }
            bool accepted = _coordinator.MarkKnownOpenFailure(identity.FlowHandle,
                identity.PanelInstanceId, identity.WebDocumentEpoch,
                DevLockboxS0Coordinator.KnownOpenFailure.WebBindRejected);
            Log("runtime_open_rejected", "accepted=" + Lower(accepted)
                + " code=" + SafeWord(code) + " panelDigest=" + Digest(identity.PanelInstanceId));
            if (accepted)
            {
                DisposeTimer(_bindTimer);
                SendOpenFailed(identity, GetActiveSessionId(), "web_bind_rejected");
            }
        }

        private void HandleWebTeardownAck(JObject payload)
        {
            CapabilityBinding binding;
            DevLockboxS0Coordinator.AttemptIdentity identity;
            lock (_sync)
            {
                binding = _activeBinding;
                identity = _activeIdentity;
            }
            string reason;
            if (!TryReadString(payload, "reason", out reason)) reason = null;
            if (binding == null || binding.State != CapabilityState.Consumed || identity == null
                || payload == null
                || !HasExactKeys(payload, "protocolVersion", "capability",
                    "connectionGeneration", "gameProcessId", "documentEpoch", "source",
                    "fixture", "reason")
                || !ArmValuesMatch(payload, binding)
                || (reason != "runtime_rejected" && reason != "force_close"))
            {
                Log("gate_rejected", "code=web_teardown_mismatch origin=web_control");
                return;
            }
            bool recorded = _coordinator.RecordExactCloseAck(identity.FlowHandle,
                identity.PanelInstanceId, identity.WebDocumentEpoch);
            Log("close_proof", "recorded=" + Lower(recorded)
                + " origin=web_dom reason=" + reason
                + " panelDigest=" + Digest(identity.PanelInstanceId));
            if (!recorded) return;
            StartReconcileTick(identity);
            string pendingFailure;
            lock (_sync) pendingFailure = _pendingOpenFailureReason;
            if (_coordinator.State == DevLockboxS0Coordinator.FlowState.RevokePending
                && string.IsNullOrEmpty(pendingFailure))
            {
                SendOpenFailed(identity, GetActiveSessionId(), "web_bind_rejected");
            }
            EnsureNativePanelClosed(identity, reason);
            TryReleasePauseAndReset();
        }

        private bool SendAs2Bootstrap(CapabilityBinding binding)
        {
            JObject command = new JObject
            {
                ["task"] = "cmd",
                ["action"] = "devLockboxS0Bootstrap",
                ["protocolVersion"] = ProtocolVersion,
                ["capability"] = binding.Capability,
                ["connectionGeneration"] = binding.ConnectionGeneration,
                ["gameProcessId"] = binding.Process.ProcessId,
                ["documentEpoch"] = binding.DocumentEpoch,
                ["resumeActive"] = binding.ResumeActive,
                ["source"] = DevLockboxS0Coordinator.RequiredSource,
                ["fixture"] = DevLockboxS0Coordinator.RequiredFixture
            };
            bool sent = SendSocket(command, binding.ConnectionGeneration);
            if (sent) Log("as2_bootstrap_sent", "gen=" + binding.ConnectionGeneration
                + " resumeActive=" + Lower(binding.ResumeActive)
                + " capDigest=" + binding.Digest);
            return sent;
        }

        private bool StartBindingAckTimer(CapabilityBinding binding,
            CapabilityState expectedState, string timeoutCode)
        {
            if (binding == null) return false;
            Timer timer = null;
            timer = new Timer(delegate
            {
                bool ownsTimer = false;
                bool expired = false;
                int retryGeneration = 0;
                lock (_sync)
                {
                    if (ReferenceEquals(binding.AckTimer, timer))
                    {
                        ownsTimer = true;
                        binding.AckTimer = null;
                        if (!_disposed && ReferenceEquals(_binding, binding)
                            && binding.State == expectedState)
                        {
                            _binding = null;
                            retryGeneration = _liveGeneration;
                            expired = true;
                        }
                    }
                }
                timer.Dispose();
                if (!ownsTimer || !expired) return;
                Log("gate_rejected", "code=" + timeoutCode
                    + " origin=" + (expectedState == CapabilityState.WebArmPending
                        ? "web_control" : "socket"));
                // The timed-out capability stays burned.  Recovery always generates a fresh
                // capability and revalidates process/generation/document state.
                if (binding.ResumeActive)
                {
                    if (_coordinator.HoldsGlobalPause)
                        TryIssueActiveReconnectBootstrap(retryGeneration);
                }
                else if (!_coordinator.HoldsGlobalPause)
                {
                    TryIssueWebArm();
                }
            }, null, Timeout.Infinite, Timeout.Infinite);

            Timer old = null;
            bool installed = false;
            lock (_sync)
            {
                if (!_disposed && ReferenceEquals(_binding, binding)
                    && binding.State == expectedState)
                {
                    old = binding.AckTimer;
                    binding.AckTimer = timer;
                    installed = true;
                }
            }
            if (!installed)
            {
                timer.Dispose();
                return false;
            }
            old?.Dispose();
            try { timer.Change(_bindingAckTimeoutMilliseconds, Timeout.Infinite); }
            catch (ObjectDisposedException)
            {
                lock (_sync)
                {
                    if (ReferenceEquals(binding.AckTimer, timer)) binding.AckTimer = null;
                }
                timer.Dispose();
                return false;
            }
            return true;
        }

        private void DisposeBindingAckTimer(CapabilityBinding binding)
        {
            if (binding == null) return;
            Timer old;
            lock (_sync)
            {
                old = binding.AckTimer;
                binding.AckTimer = null;
            }
            old?.Dispose();
        }

        private void ScheduleBindingRetry(bool resumeActive, int connectionGeneration)
        {
            Timer timer = null;
            Timer old = null;
            long version = 0;
            lock (_sync)
            {
                if (_disposed || !_connectionAlive || connectionGeneration <= 0
                    || _liveGeneration != connectionGeneration || _binding != null
                    || (_webNavigationPending && !resumeActive)
                    || _coordinator.HoldsGlobalPause != resumeActive) return;
                version = ++_bindingRetryVersion;
                timer = new Timer(delegate
                {
                    bool run;
                    lock (_sync)
                    {
                        run = !_disposed && ReferenceEquals(_bindingRetryTimer, timer)
                            && version == _bindingRetryVersion && _connectionAlive
                            && _liveGeneration == connectionGeneration && _binding == null
                            && (!_webNavigationPending || resumeActive)
                            && _coordinator.HoldsGlobalPause == resumeActive;
                        if (ReferenceEquals(_bindingRetryTimer, timer))
                            _bindingRetryTimer = null;
                    }
                    timer.Dispose();
                    if (!run) return;
                    if (resumeActive)
                        TryIssueActiveReconnectBootstrap(connectionGeneration);
                    else
                        TryIssueWebArm();
                }, null, Timeout.Infinite, Timeout.Infinite);
                old = _bindingRetryTimer;
                _bindingRetryTimer = timer;
            }
            old?.Dispose();
            try { timer.Change(_bindingAckTimeoutMilliseconds, Timeout.Infinite); }
            catch (ObjectDisposedException) { }
        }

        private void ScheduleActiveReconnectRetryIfNeeded()
        {
            int generation;
            lock (_sync)
            {
                if (_disposed || !_connectionAlive || _liveGeneration <= 0
                    || _pauseReleaseInProgress || !_coordinator.HoldsGlobalPause
                    || _processReplacementRecoveryStarted
                    || _activeIdentity == null || _binding != null) return;
                generation = _liveGeneration;
            }
            // ScheduleBindingRetry revalidates the same state and exact generation.  This restores
            // an edge consumed by an ack/retry callback while pause release was in progress.
            ScheduleBindingRetry(true, generation);
        }

        private Timer DetachBindingRetryTimerLocked()
        {
            _bindingRetryVersion += 1;
            Timer old = _bindingRetryTimer;
            _bindingRetryTimer = null;
            return old;
        }

        private void HandleAs2BootstrapAck(JObject message, JObject payload, int generation)
        {
            if (!HasExactKeys(message, "task", "payload"))
            {
                Log("gate_rejected", "code=bootstrap_ack_envelope_mismatch origin=socket");
                return;
            }
            CapabilityBinding binding;
            lock (_sync) { binding = _binding; }
            if (binding == null || binding.State != CapabilityState.As2BootstrapPending
                || generation != binding.ConnectionGeneration
                || !IsExactBootstrapAckPayload(payload, binding)
                || !IsCurrentProcessAndConnectionValid(binding))
            {
                Log("gate_rejected", "code=bootstrap_ack_mismatch origin=socket");
                return;
            }
            bool committed = false;
            lock (_sync)
            {
                GameProcessIdentity? commitProcess = SafeGetProcess();
                bool holdsGlobalPause = _coordinator.HoldsGlobalPause;
                if (!_disposed && _connectionAlive && generation == _liveGeneration
                    && ReferenceEquals(_binding, binding)
                    && binding.State == CapabilityState.As2BootstrapPending
                    && commitProcess.HasValue && commitProcess.Value.Equals(binding.Process)
                    && binding.ResumeActive == holdsGlobalPause)
                {
                    binding.State = binding.ResumeActive
                        ? CapabilityState.Consumed : CapabilityState.Ready;
                    committed = true;
                }
            }
            if (!committed)
            {
                Log("gate_rejected", "code=bootstrap_ack_mismatch origin=socket");
                return;
            }
            DisposeBindingAckTimer(binding);
            Log("as2_bootstrap_ack", "gen=" + generation + " pid="
                + binding.Process.ProcessId + " epoch=" + binding.DocumentEpoch
                + " resumeActive=" + Lower(binding.ResumeActive)
                + " capDigest=" + binding.Digest);
            if (binding.ResumeActive) ResumeActiveAfterReconnect();
        }

        private void ResumeActiveAfterReconnect()
        {
            DevLockboxS0Coordinator.AttemptIdentity identity = _coordinator.ActiveIdentity;
            if (identity == null) return;
            string pendingFailure;
            lock (_sync) pendingFailure = _pendingOpenFailureReason;
            if (!string.IsNullOrEmpty(pendingFailure))
            {
                SendOpenFailed(identity, GetActiveSessionId(), pendingFailure);
                return;
            }
            if (_coordinator.CanIssueCausalResultQuery && _coordinator.UnknownFlowCallId == 1)
            {
                bool sent = SendAuthorityQuery(identity, "reconnect");
                Log("query_forward", "unknownFlowCallId=1 delivered=" + Lower(sent)
                    + " reason=reconnect");
            }
            else if (_coordinator.State == DevLockboxS0Coordinator.FlowState.OpenBindUnknown)
            {
                SendWebControl("bind_query", BuildWebIdentity(identity));
            }
            StartReconcileTick(identity);
        }

        private bool StartProcessReplacementRecovery(
            DevLockboxS0Coordinator.AttemptIdentity identity, string reason)
        {
            CapabilityBinding invalidatedBinding = null;
            Timer invalidatedRetry = null;
            bool started = false;
            lock (_sync)
            {
                if (_disposed || identity == null || !SameIdentity(_activeIdentity, identity))
                    return false;
                if (!_processReplacementRecoveryStarted)
                {
                    if (!_coordinator.ConfirmAuthorityExpired(identity.FlowHandle,
                        identity.PanelInstanceId, identity.WebDocumentEpoch)) return false;
                    _processReplacementRecoveryStarted = true;
                    invalidatedBinding = _binding;
                    _binding = null;
                    invalidatedRetry = DetachBindingRetryTimerLocked();
                    _pendingOpenFailureReason = null;
                    started = true;
                }
            }

            DisposeBindingAckTimer(invalidatedBinding);
            invalidatedRetry?.Dispose();
            if (started)
            {
                DisposeTimer(_bindTimer);
                DisposeTimer(_authorityTimer);
                StopReconcileTick();
                Log("process_replacement_recovery", "reason=" + SafeWord(reason)
                    + " panelDigest=" + Digest(identity.PanelInstanceId));
                JObject web = BuildWebIdentity(identity);
                web["flowCallId"] = 1;
                web["terminal"] = "EXPIRED";
                SendWebAuthorityProjection("authority_terminal", web);
                RequestWebClose(identity);
            }
            EnsureNativePanelClosed(identity, reason);
            TryReleasePauseAndReset();
            return true;
        }

        private string HandleBegin(JObject message, JObject payload, int generation)
        {
            JToken callId = message["callId"];
            int parsedCallId;
            int protocolVersion;
            bool as2PauseAcquired;
            string action;
            string capability;
            string sessionId;
            string source;
            string fixture;
            if (!HasExactKeys(message, "task", "callId", "payload")
                || !TryReadInt32(message, "callId", out parsedCallId) || parsedCallId < 0
                || payload == null
                || !HasExactKeys(payload, "action", "protocolVersion", "capability",
                    "sessionId", "pauseAcquired", "source", "fixture")
                || !TryReadString(payload, "action", out action) || action != "begin"
                || !TryReadInt32(payload, "protocolVersion", out protocolVersion)
                    || protocolVersion != ProtocolVersion
                || !TryReadString(payload, "capability", out capability) || !IsOpaque(capability)
                || !TryReadString(payload, "sessionId", out sessionId) || !IsOpaque(sessionId)
                || !TryReadBoolean(payload, "pauseAcquired", out as2PauseAcquired)
                    || !as2PauseAcquired
                || !TryReadString(payload, "source", out source)
                    || source != DevLockboxS0Coordinator.RequiredSource
                || !TryReadString(payload, "fixture", out fixture)
                    || fixture != DevLockboxS0Coordinator.RequiredFixture)
            {
                Log("gate_rejected", "code=begin_schema_mismatch origin=socket");
                return BuildBeginFailure(callId, "schema_mismatch");
            }

            CapabilityBinding binding;
            bool navigationPending;
            lock (_sync)
            {
                binding = _binding;
                navigationPending = _webNavigationPending;
            }
            Log("begin_received", "origin=trusted_as2_socket gen=" + generation
                + " pid=" + (binding != null ? binding.Process.ProcessId : 0)
                + " pauseAcquired=true");
            if (navigationPending)
            {
                Log("gate_rejected", "code=web_navigation_pending origin=socket");
                return BuildBeginFailure(callId, "web_navigation_pending");
            }
            if (binding == null || binding.State != CapabilityState.Ready
                || binding.ResumeActive
                || generation != binding.ConnectionGeneration
                || !FixedEquals(capability, binding.Capability)
                || binding.DocumentEpoch != _coordinator.WebDocumentEpoch
                || !IsCurrentProcessAndConnectionValid(binding)
                || !_isDevRepository()
                || _environmentGateProvider() != DevLockboxS0Coordinator.RequiredEnvironmentValue)
            {
                Log("gate_rejected", "code=capability_binding_mismatch origin=socket");
                return BuildBeginFailure(callId, "capability_rejected");
            }

            DevLockboxS0Coordinator.BeginRequest request = new DevLockboxS0Coordinator.BeginRequest
            {
                IsDevRepository = _isDevRepository(),
                EnvironmentGateValue = _environmentGateProvider(),
                Origin = DevLockboxS0Coordinator.RouteOrigin.TrustedAs2Socket,
                Source = source,
                Fixture = fixture,
                IsPanelOrchestrationIdle = _panel != null && _panel.IsIdleForTrackedOpen,
                WebDocumentEpoch = binding.DocumentEpoch
            };
            DevLockboxS0Coordinator.AttemptIdentity identity;
            DevLockboxS0Coordinator.BeginRejection rejection;
            bool began;
            bool pauseAcquired = false;
            bool enqueued = false;
            lock (_sync)
            {
                if (_disposed || !_connectionAlive || generation != _liveGeneration)
                    return BuildBeginFailure(callId, "capability_rejected");
                if (_webNavigationPending)
                    return BuildBeginFailure(callId, "web_navigation_pending");
                if (_genericUnpausePending)
                {
                    Log("gate_rejected", "code=generic_unpause_pending origin=socket");
                    return BuildBeginFailure(callId, "capability_rejected");
                }
                if (!ReferenceEquals(_binding, binding) || binding.State != CapabilityState.Ready)
                    return BuildBeginFailure(callId, "capability_rejected");
                binding.State = CapabilityState.Consumed;
                _activeCapability = binding.Capability;
                began = _coordinator.TryBegin(request, out identity, out rejection);
                if (began)
                {
                    _activeSessionId = sessionId;
                    _activeIdentity = identity;
                    _activeProcessBinding = binding.Process;
                    _activeBinding = binding;
                    _pendingOpenFailureReason = null;
                    _lastWebAuthorityCommand = null;
                    _lastWebAuthorityPayload = null;
                    _nativePanelClosed = false;
                    _nativeCloseInProgress = false;
                    _processReplacementRecoveryStarted = false;
                }
                else
                {
                    _activeCapability = null;
                    _activeBinding = null;
                    _binding = null;
                }
            }
            Log("capability_consumed", "capDigest=" + binding.Digest);
            if (!began)
            {
                Log("gate_rejected", "code=" + BeginRejectionCode(rejection) + " origin=socket");
                if (!_coordinator.HoldsGlobalPause) TryIssueWebArm();
                return BuildBeginFailure(callId, BeginRejectionCode(rejection));
            }
            Log("open_reserved", "flowDigest=" + Digest(identity.FlowHandle)
                + " requestDigest=" + Digest(identity.RequestToken)
                + " panelDigest=" + Digest(identity.PanelInstanceId)
                + " sessionDigest=" + Digest(sessionId) + " epoch=" + identity.WebDocumentEpoch);

            bool acquireEntered;
            lock (_sync)
            {
                acquireEntered = !_disposed && _connectionAlive
                    && generation == _liveGeneration
                    && ReferenceEquals(_binding, binding)
                    && ReferenceEquals(_activeBinding, binding)
                    && SameIdentity(_activeIdentity, identity)
                    && TryEnterOutboundActionLocked();
            }
            if (acquireEntered)
            {
                try
                {
                    try { pauseAcquired = _acquireTrackedPause(binding.ConnectionGeneration); }
                    catch { pauseAcquired = false; }
                }
                finally
                {
                    ExitOutboundAction();
                }
            }

            Log("pause_acquire", "delivered=" + Lower(pauseAcquired)
                + " gen=" + binding.ConnectionGeneration
                + " panelDigest=" + Digest(identity.PanelInstanceId));
            if (!pauseAcquired)
            {
                lock (_sync) _coordinator.CancelQueuedOpenExact(identity.RequestToken);
                RecordNativePanelClosed(identity, "pause_acquire_failed");
                Log("gate_rejected", "code=pause_acquire_failed origin=socket");
                SendOpenFailed(identity, sessionId, "pre_execution_rejected");
                return BuildBeginFailure(callId, "panel_enqueue_failed");
            }

            lock (_sync)
            {
                if (!_disposed && _connectionAlive && generation == _liveGeneration
                    && !_webNavigationPending && !_genericUnpausePending
                    && ReferenceEquals(_binding, binding)
                    && ReferenceEquals(_activeBinding, binding)
                    && SameIdentity(_activeIdentity, identity))
                {
                    string initDataJson = BuildTrackedOpenInit(binding, identity)
                        .ToString(Formatting.None);
                    bool panelCallEntered = TryEnterOutboundActionLocked();
                    try
                    {
                        if (panelCallEntered)
                        {
                            enqueued = _panel != null && _panel.TryOpenTracked(initDataJson,
                                identity.PanelInstanceId,
                                delegate { return ExecuteOpenGate(binding, identity); },
                                delegate(PanelHostController.TrackedOpenOutcome outcome)
                                {
                                    OnTrackedOpenCompleted(binding, identity, sessionId, outcome);
                                });
                        }
                    }
                    catch
                    {
                        enqueued = false;
                    }
                    finally
                    {
                        if (panelCallEntered) ExitOutboundAction();
                    }
                }
                if (!enqueued) _coordinator.CancelQueuedOpenExact(identity.RequestToken);
            }

            if (!enqueued)
            {
                RecordNativePanelClosed(identity, "open_enqueue_rejected");
                Log("gate_rejected", "code=panel_enqueue_failed origin=panel_host");
                SendOpenFailed(identity, sessionId, "pre_execution_rejected");
                return BuildBeginFailure(callId, "panel_enqueue_failed");
            }
            Log("open_enqueued", "flowDigest=" + Digest(identity.FlowHandle)
                + " requestDigest=" + Digest(identity.RequestToken));
            return BuildBeginSuccess(callId, identity);
        }

        private bool ExecuteOpenGate(CapabilityBinding binding,
            DevLockboxS0Coordinator.AttemptIdentity identity)
        {
            bool allowed;
            lock (_sync)
            {
                allowed = !_disposed && _connectionAlive && !_webNavigationPending
                    && binding != null
                    && binding.State == CapabilityState.Consumed
                    && ReferenceEquals(_activeBinding, binding)
                    && SameIdentity(_activeIdentity, identity)
                    && binding.DocumentEpoch == _coordinator.WebDocumentEpoch
                    && IsCurrentProcessAndConnectionValid(binding)
                    && _coordinator.CanExecuteQueuedOpen(identity.RequestToken)
                    && _coordinator.MarkQueuedOpenExecuting(identity.RequestToken);
            }
            Log("open_execute_recheck", "allowed=" + Lower(allowed)
                + " gen=" + (binding != null ? binding.ConnectionGeneration : 0)
                + " pid=" + (binding != null ? binding.Process.ProcessId : 0)
                + " epoch=" + _coordinator.WebDocumentEpoch);
            return allowed;
        }

        private void OnTrackedOpenCompleted(CapabilityBinding binding,
            DevLockboxS0Coordinator.AttemptIdentity identity, string sessionId,
            PanelHostController.TrackedOpenOutcome outcome)
        {
            GameProcessIdentity? currentProcess = outcome == PanelHostController.TrackedOpenOutcome.OpenPosted
                ? SafeGetProcess() : null;
            bool staleOpen;
            bool navigationPending;
            bool processMismatch;
            bool processReplacementRecoveryStarted;
            lock (_sync)
            {
                if (_disposed || !ReferenceEquals(_activeBinding, binding)
                    || !SameIdentity(_activeIdentity, identity)) return;
                navigationPending = _webNavigationPending;
                processMismatch = outcome == PanelHostController.TrackedOpenOutcome.OpenPosted
                    && (!currentProcess.HasValue || !currentProcess.Value.Equals(binding.Process));
                processReplacementRecoveryStarted = _processReplacementRecoveryStarted;
                staleOpen = !_connectionAlive || navigationPending
                    || binding.ConnectionGeneration != _liveGeneration
                    || binding.DocumentEpoch != _coordinator.WebDocumentEpoch
                    || processMismatch;
            }
            if (outcome == PanelHostController.TrackedOpenOutcome.OpenPosted)
            {
                Log("panel_post", "delivered=true host=PanelHostController transport=WebView2"
                    + " panelDigest=" + Digest(identity.PanelInstanceId));
                if (processMismatch)
                {
                    StartProcessReplacementRecovery(identity, "tracked_open_process_replaced");
                    return;
                }
                if (staleOpen)
                {
                    bool marked = _coordinator.MarkBindTimeout(identity.FlowHandle,
                        identity.PanelInstanceId, identity.WebDocumentEpoch);
                    Log("tracked_open_stale", "markedBindUnknown=" + Lower(marked)
                        + " panelDigest=" + Digest(identity.PanelInstanceId));
                    if (marked)
                    {
                        if (!navigationPending)
                        {
                            SendWebControl("bind_timeout", BuildWebIdentity(identity));
                            SendWebControl("bind_query", BuildWebIdentity(identity));
                            SendWebCloseQuery(identity);
                        }
                        StartReconcileTick(identity);
                    }
                    EnsureNativePanelClosed(identity, "tracked_open_settled_stale");
                    return;
                }
                StartBindTimer(identity);
                return;
            }
            if (processReplacementRecoveryStarted)
            {
                // The process-replacement path may race the queued UI command.  PanelHost emits
                // every non-success outcome only after reset (or before visual effects), so it is
                // the exact native-close proof for the already-terminal old identity.  Every
                // outcome except PostAcceptedThenFailed also proves that Web never accepted the
                // tracked identity; an accepted post must still return the exact close ack.
                Log("panel_post", "delivered=false host=PanelHostController transport=WebView2"
                    + " panelDigest=" + Digest(identity.PanelInstanceId));
                if (outcome != PanelHostController.TrackedOpenOutcome.PostAcceptedThenFailed)
                {
                    _coordinator.ConfirmTrackedOpenDidNotReachDom(identity.FlowHandle,
                        identity.PanelInstanceId, identity.WebDocumentEpoch);
                }
                RecordNativePanelClosed(identity, "tracked_open_process_replaced_"
                    + outcome.ToString().ToLowerInvariant());
                return;
            }
            bool accepted;
            string reason;
            if (outcome == PanelHostController.TrackedOpenOutcome.PostNotDelivered)
            {
                accepted = _coordinator.MarkKnownOpenFailure(identity.FlowHandle, identity.PanelInstanceId,
                    identity.WebDocumentEpoch,
                    DevLockboxS0Coordinator.KnownOpenFailure.PostNotDelivered);
                reason = "post_not_delivered";
            }
            else if (outcome == PanelHostController.TrackedOpenOutcome.PostAcceptedThenFailed
                || outcome == PanelHostController.TrackedOpenOutcome.Failed)
            {
                accepted = _coordinator.MarkKnownOpenFailure(identity.FlowHandle,
                    identity.PanelInstanceId,
                    identity.WebDocumentEpoch,
                    DevLockboxS0Coordinator.KnownOpenFailure.WebBindRejected);
                reason = "web_bind_rejected";
            }
            else
            {
                accepted = _coordinator.CancelQueuedOpenExact(identity.RequestToken);
                reason = "pre_execution_rejected";
            }
            if (!accepted)
            {
                Log("gate_rejected", "code=stale_tracked_open_completion origin=panel_host");
                return;
            }

            // PanelHost guarantees that every non-success completion is emitted only after its
            // native reset (or before any visual side effect), so this is a valid native-close
            // proof.  DOM authority remains separate for PostAcceptedThenFailed.
            RecordNativePanelClosed(identity, "tracked_open_" + outcome.ToString().ToLowerInvariant());
            Log("panel_post", "delivered=false host=PanelHostController transport=WebView2"
                + " panelDigest=" + Digest(identity.PanelInstanceId));
            SendOpenFailed(identity, sessionId, reason);
        }

        private void StartBindTimer(DevLockboxS0Coordinator.AttemptIdentity identity)
        {
            ReplaceTimer(_bindTimer, _bindTimeoutMilliseconds, delegate
            {
                if (!_coordinator.MarkBindTimeout(identity.FlowHandle, identity.PanelInstanceId,
                    identity.WebDocumentEpoch)) return;
                Log("bind_unknown", "panelDigest=" + Digest(identity.PanelInstanceId));
                SendWebControl("bind_timeout", BuildWebIdentity(identity));
                SendWebControl("bind_query", BuildWebIdentity(identity));
                SendWebCloseQuery(identity);
                StartReconcileTick(identity);
            });
        }

        private void HandleWebBind(JObject payload)
        {
            DevLockboxS0Coordinator.AttemptIdentity identity;
            if (!TryValidateWebIdentity(payload, Array.Empty<string>(), out identity))
            {
                Log("web_bind", "accepted=false");
                return;
            }
            bool accepted = _coordinator.TryAcknowledgeBind(identity.FlowHandle,
                identity.PanelInstanceId, identity.WebDocumentEpoch);
            if (accepted)
            {
                DisposeTimer(_bindTimer);
                StopReconcileTick();
            }
            Log("web_bind", "accepted=" + Lower(accepted)
                + " panelDigest=" + Digest(identity.PanelInstanceId));
        }

        private void HandleWebBindQueryResult(JObject payload)
        {
            DevLockboxS0Coordinator.AttemptIdentity identity;
            if (!TryValidateWebIdentity(payload, new[] { "binding" }, out identity)) return;
            string binding;
            if (!TryReadString(payload, "binding", out binding)) return;
            DevLockboxS0Coordinator.BindQueryConclusion conclusion;
            if (binding == "bound") conclusion = DevLockboxS0Coordinator.BindQueryConclusion.Bound;
            else if (binding == "unbound") conclusion = DevLockboxS0Coordinator.BindQueryConclusion.Unbound;
            else return;
            bool applied = _coordinator.ApplyExactBindQuery(identity.FlowHandle,
                identity.PanelInstanceId, identity.WebDocumentEpoch, conclusion);
            Log("bind_query_reply", "accepted=" + Lower(applied) + " binding=" + binding
                + " panelDigest=" + Digest(identity.PanelInstanceId));
            if (applied) StopReconcileTick();
            if (applied && conclusion == DevLockboxS0Coordinator.BindQueryConclusion.Unbound)
                SendOpenFailed(identity, GetActiveSessionId(), "web_bind_rejected");
        }

        private void HandleWebResult(JObject payload)
        {
            DevLockboxS0Coordinator.AttemptIdentity identity;
            if (!TryValidateWebIdentity(payload, new[] { "flowCallId", "result" }, out identity)) return;
            int callId;
            string resultName;
            DevLockboxS0Coordinator.LimitedResult result;
            if (!TryReadInt32(payload, "flowCallId", out callId) || callId != 1
                || !TryReadString(payload, "result", out resultName)
                || !TryParseResult(resultName, out result)) return;
            if (!_coordinator.TrySubmitResult(identity.FlowHandle, identity.PanelInstanceId,
                identity.WebDocumentEpoch, callId, result)) return;
            string sessionId = GetActiveSessionId();
            JObject command = BuildAs2IdentityCommand("devLockboxS0ApplyResult", identity, sessionId);
            command["flowCallId"] = callId;
            command["result"] = ResultName(result);
            bool sent = SendSocket(command, GetActiveGeneration());
            Log("result_forward", "flowCallId=1 result=" + ResultName(result)
                + " delivered=" + Lower(sent));
            if (!sent)
            {
                MarkResultUnknown(identity, callId);
                return;
            }
            ReplaceTimer(_authorityTimer, AuthorityTimeoutMilliseconds,
                delegate { MarkResultUnknown(identity, callId); });
        }

        private void MarkResultUnknown(DevLockboxS0Coordinator.AttemptIdentity identity, int callId)
        {
            if (!_coordinator.MarkResultTransportUnknown(identity.FlowHandle,
                identity.PanelInstanceId, identity.WebDocumentEpoch, callId)) return;
            Log("result_unknown", "flowCallId=" + callId);
            JObject payload = BuildWebIdentity(identity);
            payload["flowCallId"] = callId;
            SendWebControl("result_unknown", payload);
            SendAuthorityQuery(identity, "host_detected_unknown");
            StartReconcileTick(identity);
        }

        private void HandleWebResultQuery(JObject payload)
        {
            DevLockboxS0Coordinator.AttemptIdentity identity;
            if (!TryValidateWebIdentity(payload, new[] { "unknownFlowCallId" }, out identity)) return;
            int unknownCallId;
            if (!TryReadInt32(payload, "unknownFlowCallId", out unknownCallId)
                || unknownCallId != 1) return;
            if (_coordinator.State == DevLockboxS0Coordinator.FlowState.PanelBound)
            {
                bool marked = _coordinator.MarkExternalResultDeliveryUnknown(identity.FlowHandle,
                    identity.PanelInstanceId, identity.WebDocumentEpoch, unknownCallId);
                Log("result_unknown", "flowCallId=1 origin=web_ack_timeout accepted="
                    + Lower(marked));
            }
            if (!_coordinator.CanIssueCausalResultQuery) return;
            bool sent = SendAuthorityQuery(identity, "web_request");
            Log("query_forward", "unknownFlowCallId=1 delivered=" + Lower(sent));
            StartReconcileTick(identity);
        }

        private bool SendAuthorityQuery(DevLockboxS0Coordinator.AttemptIdentity identity,
            string reason)
        {
            DevLockboxS0Coordinator.FlowState state = _coordinator.State;
            bool causalUnknown = state == DevLockboxS0Coordinator.FlowState.ReconcileRequired
                && _coordinator.UnknownFlowCallId == 1;
            bool terminalPoll = state == DevLockboxS0Coordinator.FlowState.ResultApplied
                && _coordinator.SubmittedFlowCallId == 1
                && _coordinator.SubmittedResult == DevLockboxS0Coordinator.LimitedResult.Success;
            if (identity == null || (!causalUnknown && !terminalPoll)) return false;
            JObject command = BuildAs2IdentityCommand("devLockboxS0QueryResult", identity,
                GetActiveSessionId());
            command["unknownFlowCallId"] = 1;
            bool sent = SendSocket(command, GetActiveGeneration());
            Log("causal_query", "unknownFlowCallId=1 reason=" + SafeWord(reason)
                + " delivered=" + Lower(sent));
            return sent;
        }

        private void HandleAuthorityResultAck(JObject message, JObject payload, int generation)
        {
            string[] extras = { "action", "protocolVersion", "sessionId", "flowHandle",
                "panelInstanceId", "documentEpoch", "flowCallId", "result", "applied",
                "observedCallWatermark", "authorityTerminal", "authorityState", "source", "fixture" };
            DevLockboxS0Coordinator.AttemptIdentity identity;
            if (!HasExactKeys(message, "task", "payload") || payload == null
                || !HasExactKeys(payload, extras)
                || !TryEnterAuthorityBinding(payload, generation, out identity)) return;
            try
            {
                int flowCallId;
                int watermark;
                bool applied;
                bool terminal;
                DevLockboxS0Coordinator.LimitedResult result;
                string resultName;
                string state;
                if (!TryReadInt32(payload, "flowCallId", out flowCallId) || flowCallId != 1
                    || !TryReadInt32(payload, "observedCallWatermark", out watermark) || watermark != 1
                    || !TryReadBoolean(payload, "applied", out applied) || !applied
                    || !TryReadBoolean(payload, "authorityTerminal", out terminal)
                    || !TryReadString(payload, "result", out resultName)
                    || !TryParseResult(resultName, out result)
                    || !TryReadString(payload, "authorityState", out state)
                    || !IsAuthorityState(state) || terminal != IsTerminalState(state)
                    || !IsValidResultAuthorityState(result, state, terminal)) return;
                bool accepted = _coordinator.TryAcknowledgeResult(identity.FlowHandle,
                    identity.PanelInstanceId, identity.WebDocumentEpoch, flowCallId, result,
                    watermark, terminal);
                if (!accepted) return;
                DisposeTimer(_authorityTimer);
                Log("authority_ack", "watermark=" + watermark + " state=" + state
                    + " terminal=" + Lower(terminal)
                    + " panelDigest=" + Digest(identity.PanelInstanceId));
                JObject web = BuildWebIdentity(identity);
                web["flowCallId"] = flowCallId;
                web["result"] = ResultName(result);
                web["applied"] = true;
                web["authorityTerminal"] = terminal;
                SendWebAuthorityProjection("result_ack", web);
                if (terminal)
                {
                    if (_coordinator.CanReleaseGlobalPause) TryReleasePauseAndReset();
                    else RequestWebClose(identity);
                }
                else StartReconcileTick(identity);
            }
            finally
            {
                ExitAuthorityAction();
            }
        }

        private void HandleAuthorityQueryReply(JObject message, JObject payload, int generation)
        {
            string[] keys = { "action", "protocolVersion", "sessionId", "flowHandle",
                "panelInstanceId", "documentEpoch", "flowCallId", "observedCallWatermark",
                "disposition", "authorityTerminal", "authorityState", "source", "fixture" };
            DevLockboxS0Coordinator.AttemptIdentity identity;
            if (!HasExactKeys(message, "task", "payload") || payload == null
                || !HasExactKeys(payload, keys)
                || !TryEnterAuthorityBinding(payload, generation, out identity)) return;
            try
            {
                int flowCallId;
                int watermark;
                bool terminal;
                string state;
                string disposition;
                if (!TryReadInt32(payload, "flowCallId", out flowCallId) || flowCallId != 1
                    || !TryReadInt32(payload, "observedCallWatermark", out watermark)
                    || watermark < 0 || watermark > 1
                    || !TryReadBoolean(payload, "authorityTerminal", out terminal)
                    || !TryReadString(payload, "authorityState", out state)
                    || !TryReadString(payload, "disposition", out disposition)
                    || !IsAuthorityState(state) || terminal != IsTerminalState(state)) return;
                if (disposition == "unknown")
                {
                    Log("query_reply", "flowCallId=1 watermark=" + watermark
                        + " disposition=unknown state=" + state
                        + " terminal=" + Lower(terminal)
                        + " panelDigest=" + Digest(identity.PanelInstanceId));
                    return;
                }
                DevLockboxS0Coordinator.AuthorityQueryConclusion conclusion;
                if (disposition == "success") conclusion = DevLockboxS0Coordinator.AuthorityQueryConclusion.AppliedSuccess;
                else if (disposition == "cancel") conclusion = DevLockboxS0Coordinator.AuthorityQueryConclusion.AppliedCancel;
                else if (disposition == "failure") conclusion = DevLockboxS0Coordinator.AuthorityQueryConclusion.AppliedFailure;
                else if (disposition == "not_applied") conclusion = DevLockboxS0Coordinator.AuthorityQueryConclusion.ConfirmedNoWrite;
                else return;
                if (!IsValidQueryAuthorityState(disposition, state, terminal)) return;
                if (watermark < 1) return;
                if (_coordinator.State == DevLockboxS0Coordinator.FlowState.ResultApplied)
                {
                    if (disposition != "success") return;
                    if (!terminal)
                    {
                        if (state != "OPENING_ANIMATION") return;
                        Log("query_reply", "flowCallId=1 watermark=" + watermark
                            + " disposition=success state=" + state + " terminal=false"
                            + " panelDigest=" + Digest(identity.PanelInstanceId));
                        StartReconcileTick(identity);
                        return;
                    }
                    if (state != "COMPLETED_NO_REWARD" && state != "EXPIRED") return;
                    if (!_coordinator.MarkSuccessAuthorityTerminal(identity.FlowHandle,
                        identity.PanelInstanceId, identity.WebDocumentEpoch, watermark)) return;
                    Log("query_reply", "flowCallId=1 watermark=" + watermark
                        + " disposition=success state=" + state + " terminal=true"
                        + " panelDigest=" + Digest(identity.PanelInstanceId));
                    JObject terminalWeb = BuildWebIdentity(identity);
                    terminalWeb["flowCallId"] = 1;
                    terminalWeb["terminal"] = state;
                    SendWebAuthorityProjection("authority_terminal", terminalWeb);
                    RequestWebClose(identity);
                    return;
                }
                bool accepted = _coordinator.ApplyAuthorityQuery(identity.FlowHandle,
                    identity.PanelInstanceId, identity.WebDocumentEpoch, flowCallId,
                    watermark, conclusion, terminal);
                if (!accepted) return;
                Log("query_reply", "flowCallId=1 watermark=" + watermark
                    + " disposition=" + disposition + " state=" + state
                    + " terminal=" + Lower(terminal)
                    + " panelDigest=" + Digest(identity.PanelInstanceId));
                JObject web = BuildWebIdentity(identity);
                web["flowCallId"] = flowCallId;
                web["observedCallWatermark"] = watermark;
                web["disposition"] = disposition;
                web["authorityTerminal"] = terminal;
                SendWebAuthorityProjection("reconcile_reply", web);
                if (terminal)
                {
                    if (_coordinator.CanReleaseGlobalPause) TryReleasePauseAndReset();
                    else RequestWebClose(identity);
                }
            }
            finally
            {
                ExitAuthorityAction();
            }
        }

        private void HandleRevocationAck(JObject message, JObject payload, int generation)
        {
            string[] keys = { "action", "protocolVersion", "sessionId", "flowHandle",
                "panelInstanceId", "documentEpoch", "observedCallWatermark", "authorityState",
                "source", "fixture" };
            DevLockboxS0Coordinator.AttemptIdentity identity;
            if (!HasExactKeys(message, "task", "payload") || payload == null
                || !HasExactKeys(payload, keys)
                || !TryEnterAuthorityBinding(payload, generation, out identity)) return;
            try
            {
                int watermark;
                string state;
                if (!TryReadInt32(payload, "observedCallWatermark", out watermark)
                    || watermark != 1
                    || !TryReadString(payload, "authorityState", out state)
                    || state != "REVOKED") return;
                if (!_coordinator.AcknowledgeKnownRevocation(identity.FlowHandle,
                    identity.PanelInstanceId, identity.WebDocumentEpoch)) return;
                lock (_sync) _pendingOpenFailureReason = null;
                DisposeTimer(_authorityTimer);
                Log("authority_ack", "watermark=1 state=REVOKED terminal=true"
                    + " panelDigest=" + Digest(identity.PanelInstanceId));
                if (_coordinator.CanReleaseGlobalPause) TryReleasePauseAndReset();
                else RequestWebClose(identity);
            }
            finally
            {
                ExitAuthorityAction();
            }
        }

        private void HandleAuthorityTerminal(JObject message, JObject payload, int generation)
        {
            string[] keys = { "action", "protocolVersion", "sessionId", "flowHandle",
                "panelInstanceId", "documentEpoch", "flowCallId", "observedCallWatermark",
                "terminal", "source", "fixture" };
            DevLockboxS0Coordinator.AttemptIdentity identity;
            if (!HasExactKeys(message, "task", "payload") || payload == null
                || !HasExactKeys(payload, keys)
                || !TryEnterAuthorityBinding(payload, generation, out identity)) return;
            try
            {
                int flowCallId;
                int watermark;
                string terminal;
                if (!TryReadInt32(payload, "flowCallId", out flowCallId)
                    || !TryReadInt32(payload, "observedCallWatermark", out watermark)
                    || !TryReadString(payload, "terminal", out terminal)) return;
                bool validTerminalWatermark = terminal == "EXPIRED"
                    ? watermark >= 0 && watermark <= 1
                    : terminal == "COMPLETED_NO_REWARD" && watermark == 1;
                if (flowCallId != 1 || !validTerminalWatermark) return;
                bool accepted = terminal == "COMPLETED_NO_REWARD"
                    ? _coordinator.MarkSuccessAuthorityTerminal(identity.FlowHandle,
                        identity.PanelInstanceId, identity.WebDocumentEpoch, watermark)
                    : _coordinator.ConfirmAuthorityExpired(identity.FlowHandle,
                        identity.PanelInstanceId, identity.WebDocumentEpoch);
                if (!accepted) return;
                Log("authority_ack", "watermark=" + watermark + " state=" + terminal
                    + " terminal=true panelDigest=" + Digest(identity.PanelInstanceId));
                JObject web = BuildWebIdentity(identity);
                web["flowCallId"] = flowCallId;
                web["terminal"] = terminal;
                SendWebAuthorityProjection("authority_terminal", web);
                if (_coordinator.CanReleaseGlobalPause) TryReleasePauseAndReset();
                else RequestWebClose(identity);
            }
            finally
            {
                ExitAuthorityAction();
            }
        }

        private void HandleWebCloseAck(JObject payload)
        {
            DevLockboxS0Coordinator.AttemptIdentity identity;
            if (!TryValidateWebIdentity(payload, Array.Empty<string>(), out identity)) return;
            bool accepted = _coordinator.RecordExactCloseAck(identity.FlowHandle,
                identity.PanelInstanceId, identity.WebDocumentEpoch);
            Log("web_close_ack", "accepted=" + Lower(accepted)
                + " panelDigest=" + Digest(identity.PanelInstanceId));
            if (!accepted) return;
            StartReconcileTick(identity);
            EnsureNativePanelClosed(identity, "web_close_ack");
            TryReleasePauseAndReset();
        }

        private void RequestWebClose(DevLockboxS0Coordinator.AttemptIdentity identity)
        {
            SendWebControl("close_request", BuildWebIdentity(identity));
            StartReconcileTick(identity);
        }

        private void StartReconcileTick(DevLockboxS0Coordinator.AttemptIdentity identity)
        {
            int retryGeneration;
            lock (_sync)
            {
                if (_disposed || identity == null || !SameIdentity(_activeIdentity, identity)) return;
                retryGeneration = ++_reconcileGeneration;
            }
            ScheduleReconcileTick(identity, retryGeneration);
        }

        private void ScheduleReconcileTick(
            DevLockboxS0Coordinator.AttemptIdentity identity, int retryGeneration)
        {
            Timer oldTimer;
            Timer newTimer = null;
            lock (_sync)
            {
                if (_disposed || retryGeneration != _reconcileGeneration
                    || !SameIdentity(_activeIdentity, identity)) return;
                newTimer = new Timer(delegate
                {
                    bool current;
                    lock (_sync)
                    {
                        current = ReferenceEquals(_reconcileTimer, newTimer)
                            && !_disposed && retryGeneration == _reconcileGeneration
                            && SameIdentity(_activeIdentity, identity);
                        if (ReferenceEquals(_reconcileTimer, newTimer)) _reconcileTimer = null;
                    }
                    newTimer?.Dispose();
                    if (!current) return;
                    RunReconcileTick(identity, retryGeneration);
                    ScheduleReconcileTick(identity, retryGeneration);
                }, null, _reconcileRetryMilliseconds, Timeout.Infinite);
                oldTimer = _reconcileTimer;
                _reconcileTimer = newTimer;
            }
            oldTimer?.Dispose();
        }

        private void RunReconcileTick(
            DevLockboxS0Coordinator.AttemptIdentity identity, int retryGeneration)
        {
            lock (_sync)
            {
                if (_disposed || _pauseReleaseInProgress
                    || retryGeneration != _reconcileGeneration
                    || !SameIdentity(_activeIdentity, identity)) return;
                _reconcileActionsInFlight += 1;
            }
            try
            {
                DevLockboxS0Coordinator.FlowState state = _coordinator.State;
                if (!IsReconcileActionCurrent(identity, retryGeneration)) return;
                Log("reconcile_tick", "state=" + state.ToString().ToLowerInvariant()
                    + " panelDigest=" + Digest(identity.PanelInstanceId));
                if (state == DevLockboxS0Coordinator.FlowState.OpenBindUnknown)
                {
                    if (!IsReconcileActionCurrent(identity, retryGeneration)) return;
                    SendWebControl("bind_query", BuildWebIdentity(identity));
                    if (!IsReconcileActionCurrent(identity, retryGeneration)) return;
                    SendWebCloseQuery(identity);
                    return;
                }
                if (state == DevLockboxS0Coordinator.FlowState.RevokePending)
                {
                    string reason;
                    lock (_sync) reason = _pendingOpenFailureReason;
                    if (!string.IsNullOrEmpty(reason))
                    {
                        if (!IsReconcileActionCurrent(identity, retryGeneration)) return;
                        SendOpenFailed(identity, GetActiveSessionId(), reason, false);
                    }
                    if (!IsReconcileActionCurrent(identity, retryGeneration)) return;
                    SendWebCloseQuery(identity);
                    if (!IsReconcileActionCurrent(identity, retryGeneration)) return;
                    EnsureNativePanelClosed(identity, "reconcile_revoke");
                    return;
                }
                if (state == DevLockboxS0Coordinator.FlowState.ReconcileRequired)
                {
                    if (!IsReconcileActionCurrent(identity, retryGeneration)) return;
                    SendAuthorityQuery(identity, "timer_reconcile");
                    return;
                }
                if (state == DevLockboxS0Coordinator.FlowState.ResultApplied)
                {
                    if (!IsReconcileActionCurrent(identity, retryGeneration)) return;
                    ResendLastWebAuthorityProjection();
                    if (!IsReconcileActionCurrent(identity, retryGeneration)) return;
                    SendAuthorityQuery(identity, "terminal_poll");
                    return;
                }
                if (state == DevLockboxS0Coordinator.FlowState.KnownTerminal)
                {
                    if (!IsReconcileActionCurrent(identity, retryGeneration)) return;
                    ResendLastWebAuthorityProjection();
                    if (!IsReconcileActionCurrent(identity, retryGeneration)) return;
                    if (!_coordinator.CanReleaseGlobalPause) SendWebCloseQuery(identity);
                    if (!IsReconcileActionCurrent(identity, retryGeneration)) return;
                    EnsureNativePanelClosed(identity, "reconcile_terminal");
                    return;
                }
                StopReconcileTick();
            }
            finally
            {
                lock (_sync) _reconcileActionsInFlight -= 1;
                TryReleasePauseAndReset();
            }
        }

        private bool IsReconcileActionCurrent(
            DevLockboxS0Coordinator.AttemptIdentity identity, int retryGeneration)
        {
            lock (_sync)
            {
                return !_disposed && !_pauseReleaseInProgress
                    && retryGeneration == _reconcileGeneration
                    && SameIdentity(_activeIdentity, identity);
            }
        }

        private void StopReconcileTick()
        {
            Timer oldTimer;
            lock (_sync)
            {
                _reconcileGeneration += 1;
                oldTimer = _reconcileTimer;
                _reconcileTimer = null;
            }
            oldTimer?.Dispose();
        }

        private bool SendOpenFailed(DevLockboxS0Coordinator.AttemptIdentity identity,
            string sessionId, string reason, bool scheduleReconcile = true)
        {
            if (identity == null || string.IsNullOrEmpty(sessionId)) return false;
            int generation;
            lock (_sync)
            {
                if (_disposed || _pauseReleaseInProgress
                    || !SameIdentity(_activeIdentity, identity)
                    || sessionId != _activeSessionId) return false;
                _pendingOpenFailureReason = reason;
                generation = _liveGeneration;
            }
            JObject command = BuildAs2IdentityCommand("devLockboxS0OpenFailed", identity, sessionId);
            command["flowCallId"] = 1;
            command["reason"] = reason;
            bool sent = SendSocket(command, generation);
            Log("result_forward", "flowCallId=1 result=failure reason=" + reason
                + " delivered=" + Lower(sent));
            if (scheduleReconcile) StartReconcileTick(identity);
            return true;
        }

        private void EnsureNativePanelClosed(
            DevLockboxS0Coordinator.AttemptIdentity identity, string reason)
        {
            if (identity == null) return;
            bool enqueued = false;
            bool outboundEntered = false;
            lock (_sync)
            {
                if (_disposed || _nativePanelClosed || _nativeCloseInProgress
                    || !SameIdentity(_activeIdentity, identity)) return;
                _nativeCloseInProgress = true;
                if (_panel == null)
                {
                    if (SameIdentity(_activeIdentity, identity)) _nativeCloseInProgress = false;
                    Log("panel_exact_close", "closed=false reason=panel_host_unavailable"
                        + " panelDigest=" + Digest(identity.PanelInstanceId));
                    return;
                }
                outboundEntered = TryEnterOutboundActionLocked();
                if (!outboundEntered)
                {
                    if (SameIdentity(_activeIdentity, identity)) _nativeCloseInProgress = false;
                    return;
                }
            }

            // PanelHost completes asynchronously in production, but a test or future port may
            // complete inline.  Never hold the Runtime lock across the external enqueue: an inline
            // close proof is allowed to release pause or re-enter Runtime without lock inversion.
            try
            {
                enqueued = _panel.TryCloseExact(identity.PanelInstanceId, delegate(bool closed)
                {
                    if (!closed)
                    {
                        lock (_sync)
                        {
                            if (SameIdentity(_activeIdentity, identity))
                                _nativeCloseInProgress = false;
                        }
                    }
                    Log("panel_exact_close", "closed=" + Lower(closed)
                        + " reason=" + SafeWord(reason)
                        + " panelDigest=" + Digest(identity.PanelInstanceId));
                    if (closed) RecordNativePanelClosed(identity, reason);
                });
            }
            catch
            {
                enqueued = false;
            }
            finally
            {
                if (outboundEntered) ExitOutboundAction();
            }
            if (!enqueued)
            {
                lock (_sync)
                {
                    if (SameIdentity(_activeIdentity, identity)) _nativeCloseInProgress = false;
                }
                Log("panel_exact_close", "closed=false reason=enqueue_rejected"
                    + " panelDigest=" + Digest(identity.PanelInstanceId));
            }
        }

        private void RecordNativePanelClosed(
            DevLockboxS0Coordinator.AttemptIdentity identity, string reason)
        {
            bool recorded = false;
            bool stale = false;
            lock (_sync)
            {
                if (identity != null && SameIdentity(_activeIdentity, identity)
                    && !_nativePanelClosed)
                {
                    _nativePanelClosed = true;
                    _nativeCloseInProgress = false;
                    recorded = true;
                }
                else if (identity != null && !SameIdentity(_activeIdentity, identity))
                {
                    stale = true;
                }
            }
            if (!recorded)
            {
                if (stale)
                    Log("gate_rejected", "code=stale_native_close_proof origin=panel_host");
                return;
            }
            Log("native_close_proof", "recorded=" + Lower(recorded)
                + " reason=" + SafeWord(reason)
                + " panelDigest=" + Digest(identity != null ? identity.PanelInstanceId : null));
            if (recorded) TryReleasePauseAndReset();
        }

        private void TryReleasePauseAndReset()
        {
            DevLockboxS0Coordinator.AttemptIdentity identity;
            int releaseGeneration;
            lock (_sync)
            {
                if (!_nativePanelClosed || _pauseReleaseInProgress
                    || _reconcileActionsInFlight != 0
                    || _authorityActionsInFlight != 0
                    || !_coordinator.CanReleaseGlobalPause
                    || !_connectionAlive || _liveGeneration <= 0) return;
                _pauseReleaseInProgress = true;
                identity = _activeIdentity;
                releaseGeneration = _liveGeneration;
            }
            int immediateGenerationRetries = 0;
            while (true)
            {
                int attemptedGeneration = releaseGeneration;
                bool callbackReleased = false;
                bool callbackEntered = false;
                lock (_sync)
                {
                    if (!_disposed && _connectionAlive
                        && _liveGeneration == attemptedGeneration)
                        callbackEntered = TryEnterOutboundActionLocked();
                }
                if (callbackEntered)
                {
                    try
                    {
                        callbackReleased = _releaseTrackedPause(attemptedGeneration);
                    }
                    catch
                    {
                        callbackReleased = false;
                    }
                    finally
                    {
                        ExitOutboundAction();
                    }
                }

                int adoptedGeneration = 0;
                bool retryAdoptedGeneration = false;
                bool releaseFailed = false;
                bool stateMismatch = false;
                bool released = false;
                string failureReason = null;
                CapabilityBinding releasedBinding = null;
                Timer releasedRetry = null;
                lock (_sync)
                {
                    if (_disposed)
                    {
                        _pauseReleaseInProgress = false;
                        return;
                    }
                    adoptedGeneration = _liveGeneration;
                    // A local Write+Flush on the old socket is not proof for a socket adopted
                    // reentrantly during that callback.  Regardless of the old return value,
                    // chase the latest exact generation while the release window stays closed.
                    if (_connectionAlive && adoptedGeneration > attemptedGeneration)
                    {
                        releaseGeneration = adoptedGeneration;
                        retryAdoptedGeneration = true;
                    }
                    else if (!_connectionAlive || adoptedGeneration <= 0
                        || adoptedGeneration != attemptedGeneration)
                    {
                        _pauseReleaseInProgress = false;
                        releaseFailed = true;
                        failureReason = "connection_changed";
                    }
                    else if (!callbackReleased)
                    {
                        _pauseReleaseInProgress = false;
                        releaseFailed = true;
                        failureReason = "callback_false";
                    }
                    else if (!_coordinator.TryReleaseGlobalPauseAndReset())
                    {
                        _pauseReleaseInProgress = false;
                        stateMismatch = true;
                    }
                    else
                    {
                        releasedBinding = _binding;
                        _activeCapability = null;
                        _activeBinding = null;
                        _activeSessionId = null;
                        _activeIdentity = null;
                        _activeProcessBinding = null;
                        _pendingOpenFailureReason = null;
                        _lastWebAuthorityCommand = null;
                        _lastWebAuthorityPayload = null;
                        _binding = null;
                        releasedRetry = DetachBindingRetryTimerLocked();
                        _nativePanelClosed = false;
                        _nativeCloseInProgress = false;
                        _pauseReleaseInProgress = false;
                        _genericUnpausePending = false;
                        _processReplacementRecoveryStarted = false;
                        released = true;
                    }
                }

                if (retryAdoptedGeneration)
                {
                    Log("pause_release_generation_retry", "oldGen=" + attemptedGeneration
                        + " newGen=" + adoptedGeneration);
                    immediateGenerationRetries += 1;
                    if (immediateGenerationRetries > MaximumImmediateReleaseGenerationRetries)
                    {
                        lock (_sync) _pauseReleaseInProgress = false;
                        Log("gate_rejected", "code=pause_release_failed origin=socket gen="
                            + adoptedGeneration + " reason=generation_churn");
                        if (identity != null) StartReconcileTick(identity);
                        ScheduleActiveReconnectRetryIfNeeded();
                        return;
                    }
                    continue;
                }
                if (releaseFailed)
                {
                    Log("gate_rejected", "code=pause_release_failed origin=socket gen="
                        + attemptedGeneration + " reason=" + failureReason);
                    if (identity != null) StartReconcileTick(identity);
                    ScheduleActiveReconnectRetryIfNeeded();
                    return;
                }
                if (stateMismatch)
                {
                    Log("gate_rejected", "code=pause_release_state_mismatch origin=socket");
                    if (identity != null) StartReconcileTick(identity);
                    ScheduleActiveReconnectRetryIfNeeded();
                    return;
                }
                if (!released) return;

                StopReconcileTick();
                DisposeBindingAckTimer(releasedBinding);
                releasedRetry?.Dispose();
                Log("pause_release", "terminal=true domClosed=true nativeClosed=true"
                    + " panelDigest=" + Digest(identity != null ? identity.PanelInstanceId : null));
                TryIssueWebArm();
                return;
            }
        }

        private bool TryValidateWebIdentity(JObject payload, string[] extras,
            out DevLockboxS0Coordinator.AttemptIdentity identity)
        {
            identity = _coordinator.ActiveIdentity;
            if (identity == null || payload == null || _coordinator.DocumentEpochChanged)
                return false;
            string[] keys = new string[5 + extras.Length];
            keys[0] = "flowHandle";
            keys[1] = "panelInstanceId";
            keys[2] = "documentEpoch";
            keys[3] = "source";
            keys[4] = "fixture";
            Array.Copy(extras, 0, keys, 5, extras.Length);
            string flowHandle;
            string panelInstanceId;
            long documentEpoch;
            string source;
            string fixture;
            return HasExactKeys(payload, keys)
                && TryReadString(payload, "flowHandle", out flowHandle)
                && flowHandle == identity.FlowHandle
                && TryReadString(payload, "panelInstanceId", out panelInstanceId)
                && panelInstanceId == identity.PanelInstanceId
                && TryReadInt64(payload, "documentEpoch", out documentEpoch)
                && documentEpoch == identity.WebDocumentEpoch
                && TryReadString(payload, "source", out source)
                && source == DevLockboxS0Coordinator.RequiredSource
                && TryReadString(payload, "fixture", out fixture)
                && fixture == DevLockboxS0Coordinator.RequiredFixture;
        }

        private bool TryEnterAuthorityBinding(JObject payload, int generation,
            out DevLockboxS0Coordinator.AttemptIdentity identity)
        {
            identity = null;
            CapabilityBinding binding;
            string sessionId;
            lock (_sync)
            {
                if (_disposed || _pauseReleaseInProgress || _authorityActionsInFlight != 0
                    || !_connectionAlive || generation <= 0 || generation != _liveGeneration)
                    return false;
                identity = _activeIdentity;
                binding = _binding;
                sessionId = _activeSessionId;
                if (identity == null || binding == null
                    || binding.ConnectionGeneration != generation
                    || !SameIdentity(identity, _coordinator.ActiveIdentity))
                {
                    identity = null;
                    return false;
                }
                _authorityActionsInFlight += 1;
            }

            bool transferredToCaller = false;
            try
            {
                int protocolVersion;
                long documentEpoch;
                string payloadSessionId;
                string flowHandle;
                string panelInstanceId;
                string source;
                string fixture;
                bool valid = payload != null
                    && TryReadInt32(payload, "protocolVersion", out protocolVersion)
                    && protocolVersion == ProtocolVersion
                    && TryReadString(payload, "sessionId", out payloadSessionId)
                    && payloadSessionId == sessionId
                    && TryReadString(payload, "flowHandle", out flowHandle)
                    && flowHandle == identity.FlowHandle
                    && TryReadString(payload, "panelInstanceId", out panelInstanceId)
                    && panelInstanceId == identity.PanelInstanceId
                    && TryReadInt64(payload, "documentEpoch", out documentEpoch)
                    && documentEpoch == identity.WebDocumentEpoch
                    && TryReadString(payload, "source", out source)
                    && source == DevLockboxS0Coordinator.RequiredSource
                    && TryReadString(payload, "fixture", out fixture)
                    && fixture == DevLockboxS0Coordinator.RequiredFixture
                    && IsCurrentProcessAndConnectionValid(binding);
                lock (_sync)
                {
                    valid = valid && !_disposed && !_pauseReleaseInProgress
                        && _connectionAlive && generation == _liveGeneration
                        && ReferenceEquals(binding, _binding)
                        && sessionId == _activeSessionId
                        && SameIdentity(identity, _activeIdentity);
                }
                if (!valid) return false;

                transferredToCaller = true;
                return true;
            }
            catch
            {
                Log("gate_rejected", "code=authority_binding_malformed origin=socket");
                return false;
            }
            finally
            {
                if (!transferredToCaller)
                {
                    identity = null;
                    ExitAuthorityAction();
                }
            }
        }

        private void ExitAuthorityAction()
        {
            lock (_sync)
            {
                if (_authorityActionsInFlight > 0) _authorityActionsInFlight -= 1;
            }
            TryReleasePauseAndReset();
        }

        private JObject BuildArmPayload(CapabilityBinding binding)
        {
            return new JObject
            {
                ["protocolVersion"] = ProtocolVersion,
                ["capability"] = binding.Capability,
                ["connectionGeneration"] = binding.ConnectionGeneration,
                ["gameProcessId"] = binding.Process.ProcessId,
                ["documentEpoch"] = binding.DocumentEpoch,
                ["source"] = DevLockboxS0Coordinator.RequiredSource,
                ["fixture"] = DevLockboxS0Coordinator.RequiredFixture
            };
        }

        private JObject BuildTrackedOpenInit(CapabilityBinding binding,
            DevLockboxS0Coordinator.AttemptIdentity identity)
        {
            JObject value = BuildArmPayload(binding);
            value["flowHandle"] = identity.FlowHandle;
            value["panelInstanceId"] = identity.PanelInstanceId;
            return value;
        }

        private JObject BuildWebIdentity(DevLockboxS0Coordinator.AttemptIdentity identity)
        {
            return new JObject
            {
                ["flowHandle"] = identity.FlowHandle,
                ["panelInstanceId"] = identity.PanelInstanceId,
                ["documentEpoch"] = identity.WebDocumentEpoch,
                ["source"] = DevLockboxS0Coordinator.RequiredSource,
                ["fixture"] = DevLockboxS0Coordinator.RequiredFixture
            };
        }

        private JObject BuildAs2IdentityCommand(string action,
            DevLockboxS0Coordinator.AttemptIdentity identity, string sessionId)
        {
            return new JObject
            {
                ["task"] = "cmd",
                ["action"] = action,
                ["protocolVersion"] = ProtocolVersion,
                ["sessionId"] = sessionId,
                ["flowHandle"] = identity.FlowHandle,
                ["panelInstanceId"] = identity.PanelInstanceId,
                ["documentEpoch"] = identity.WebDocumentEpoch,
                ["source"] = DevLockboxS0Coordinator.RequiredSource,
                ["fixture"] = DevLockboxS0Coordinator.RequiredFixture
            };
        }

        private bool TryEnterOutboundAction()
        {
            lock (_sync)
            {
                return TryEnterOutboundActionLocked();
            }
        }

        private bool TryEnterOutboundActionLocked()
        {
            if (_disposed) return false;
            int threadId = Thread.CurrentThread.ManagedThreadId;
            int depth;
            _outboundActionsByThread.TryGetValue(threadId, out depth);
            _outboundActionsByThread[threadId] = depth + 1;
            _outboundActionsInFlight += 1;
            return true;
        }

        private void ExitOutboundAction()
        {
            lock (_sync)
            {
                int threadId = Thread.CurrentThread.ManagedThreadId;
                int depth;
                if (_outboundActionsByThread.TryGetValue(threadId, out depth))
                {
                    if (depth <= 1) _outboundActionsByThread.Remove(threadId);
                    else _outboundActionsByThread[threadId] = depth - 1;
                }
                if (_outboundActionsInFlight > 0) _outboundActionsInFlight -= 1;
                Monitor.PulseAll(_sync);
            }
        }

        private int GetOutboundDepthLocked(int threadId)
        {
            int depth;
            return _outboundActionsByThread.TryGetValue(threadId, out depth) ? depth : 0;
        }

        private bool SendWebControl(string command, JObject payload)
        {
            JObject message = new JObject
            {
                ["type"] = WebControlType,
                ["cmd"] = command,
                ["payload"] = payload
            };
            if (!TryEnterOutboundAction()) return false;
            bool delivered = false;
            try
            {
                try { delivered = _postToWeb(message.ToString(Formatting.None)); }
                catch { delivered = false; }
            }
            finally
            {
                ExitOutboundAction();
            }
            if (!delivered)
                Log("gate_rejected", "code=web_post_not_delivered origin=web_business");
            return delivered;
        }

        private bool SendWebCloseQuery(DevLockboxS0Coordinator.AttemptIdentity identity)
        {
            if (identity == null) return false;
            bool delivered = SendWebControl("close_query", BuildWebIdentity(identity));
            if (delivered)
                Log("close_query", "panelDigest=" + Digest(identity.PanelInstanceId));
            return delivered;
        }

        private void SendWebAuthorityProjection(string command, JObject payload)
        {
            lock (_sync)
            {
                _lastWebAuthorityCommand = command;
                _lastWebAuthorityPayload = payload != null
                    ? (JObject)payload.DeepClone() : null;
            }
            SendWebControl(command, payload);
        }

        private void ResendLastWebAuthorityProjection()
        {
            string command;
            JObject payload;
            lock (_sync)
            {
                command = _lastWebAuthorityCommand;
                payload = _lastWebAuthorityPayload != null
                    ? (JObject)_lastWebAuthorityPayload.DeepClone() : null;
            }
            if (string.IsNullOrEmpty(command) || payload == null) return;
            Log("authority_projection_retry", "cmd=" + SafeWord(command)
                + " panelDigest=" + Digest(payload.Value<string>("panelInstanceId")));
            SendWebControl(command, payload);
        }

        private bool SendSocket(JObject value, int generation)
        {
            lock (_sync)
            {
                if (_disposed || !_connectionAlive || generation <= 0
                    || generation != _liveGeneration)
                    return false;
            }
            if (!TryEnterOutboundAction()) return false;
            try
            {
                lock (_sync)
                {
                    if (_disposed || !_connectionAlive || generation != _liveGeneration)
                        return false;
                }
                try
                {
                    return _sendSocketForGeneration(value.ToString(Formatting.None), generation);
                }
                catch
                {
                    return false;
                }
            }
            finally
            {
                ExitOutboundAction();
            }
        }

        private bool IsExactArmPayload(JObject payload, CapabilityBinding binding)
        {
            return payload != null && HasExactKeys(payload, "protocolVersion", "capability",
                "connectionGeneration", "gameProcessId", "documentEpoch", "source", "fixture")
                && ArmValuesMatch(payload, binding);
        }

        private bool IsExactBootstrapAckPayload(JObject payload, CapabilityBinding binding)
        {
            string action;
            bool resumeActive;
            return payload != null && HasExactKeys(payload, "action", "protocolVersion",
                "capability", "connectionGeneration", "gameProcessId", "documentEpoch",
                "resumeActive", "source", "fixture")
                && TryReadString(payload, "action", out action) && action == "bootstrap_ack"
                && TryReadBoolean(payload, "resumeActive", out resumeActive)
                && resumeActive == binding.ResumeActive
                && ArmValuesMatch(payload, binding);
        }

        private bool ArmValuesMatch(JObject payload, CapabilityBinding binding)
        {
            int protocolVersion;
            int connectionGeneration;
            int gameProcessId;
            long documentEpoch;
            string capability;
            string source;
            string fixture;
            return TryReadInt32(payload, "protocolVersion", out protocolVersion)
                && protocolVersion == ProtocolVersion
                && TryReadString(payload, "capability", out capability)
                && FixedEquals(capability, binding.Capability)
                && TryReadInt32(payload, "connectionGeneration", out connectionGeneration)
                && connectionGeneration == binding.ConnectionGeneration
                && TryReadInt32(payload, "gameProcessId", out gameProcessId)
                && gameProcessId == binding.Process.ProcessId
                && TryReadInt64(payload, "documentEpoch", out documentEpoch)
                && documentEpoch == binding.DocumentEpoch
                && TryReadString(payload, "source", out source)
                && source == DevLockboxS0Coordinator.RequiredSource
                && TryReadString(payload, "fixture", out fixture)
                && fixture == DevLockboxS0Coordinator.RequiredFixture;
        }

        private bool IsCurrentProcessAndConnectionValid()
        {
            CapabilityBinding binding;
            lock (_sync) { binding = _binding; }
            return binding != null && IsCurrentProcessAndConnectionValid(binding);
        }

        private bool IsCurrentProcessAndConnectionValid(CapabilityBinding binding)
        {
            int liveGeneration;
            bool alive;
            lock (_sync)
            {
                liveGeneration = _liveGeneration;
                alive = _connectionAlive;
            }
            GameProcessIdentity? current = SafeGetProcess();
            return alive && binding != null && binding.ConnectionGeneration == liveGeneration
                && current.HasValue && current.Value.Equals(binding.Process);
        }

        private GameProcessIdentity? SafeGetProcess()
        {
            try { return _gameProcessProvider(); }
            catch { return null; }
        }

        private bool TryRegisterCapability(string capability)
        {
            lock (_sync) return _usedCapabilities.Add(capability);
        }

        private string GetActiveSessionId()
        {
            lock (_sync) return _activeSessionId;
        }

        private int GetActiveGeneration()
        {
            lock (_sync) return _binding != null
                ? _binding.ConnectionGeneration : _liveGeneration;
        }

        private static bool HasExactKeys(JObject value, params string[] keys)
        {
            if (value == null || value.Count != keys.Length) return false;
            for (int i = 0; i < keys.Length; i++)
                if (value.Property(keys[i], StringComparison.Ordinal) == null) return false;
            return true;
        }

        private static bool IsTelemetryEvent(string value)
        {
            return value == "bind" || value == "result" || value == "reconcile"
                || value == "close" || value == "error" || value == "unknown";
        }

        private static bool IsTelemetryResult(string value)
        {
            return value == "success" || value == "cancel" || value == "failure"
                || value == "unknown" || value == "none";
        }

        private static bool IsTelemetryDuration(string value)
        {
            return value == "lt_1s" || value == "1_5s" || value == "5_30s"
                || value == "gte_30s" || value == "unknown";
        }

        private static bool IsTelemetryError(string value)
        {
            return value == "none" || value == "transport" || value == "timeout"
                || value == "protocol" || value == "stale" || value == "disabled"
                || value == "unknown";
        }

        private static bool TryReadInt32(JObject value, string key, out int result)
        {
            result = 0;
            long parsed;
            if (!TryReadInt64(value, key, out parsed)
                || parsed < int.MinValue || parsed > int.MaxValue) return false;
            result = (int)parsed;
            return true;
        }

        private static bool TryReadInt64(JObject value, string key, out long result)
        {
            result = 0;
            JToken token = value != null ? value[key] : null;
            if (token == null || token.Type != JTokenType.Integer) return false;
            try
            {
                result = token.Value<long>();
                return true;
            }
            catch
            {
                return false;
            }
        }

        private static bool TryReadBoolean(JObject value, string key, out bool result)
        {
            result = false;
            JToken token = value != null ? value[key] : null;
            if (token == null || token.Type != JTokenType.Boolean) return false;
            try
            {
                result = token.Value<bool>();
                return true;
            }
            catch
            {
                return false;
            }
        }

        private static bool TryReadString(JObject value, string key, out string result)
        {
            result = null;
            JToken token = value != null ? value[key] : null;
            if (token == null || token.Type != JTokenType.String) return false;
            result = (string)token;
            return result != null;
        }

        private static bool IsOpaque(string value)
        {
            if (string.IsNullOrEmpty(value) || value.Length > 256 || value.Trim() != value) return false;
            for (int i = 0; i < value.Length; i++)
                if (value[i] < 0x20 || value[i] == 0x7f) return false;
            return true;
        }

        private static bool FixedEquals(string left, string right)
        {
            if (left == null || right == null) return false;
            byte[] a = Encoding.UTF8.GetBytes(left);
            byte[] b = Encoding.UTF8.GetBytes(right);
            return a.Length == b.Length && CryptographicOperations.FixedTimeEquals(a, b);
        }

        private static string CreateCapability()
        {
            byte[] bytes = RandomNumberGenerator.GetBytes(32);
            return Convert.ToHexString(bytes).ToLowerInvariant();
        }

        private static string CreateOpaqueId()
        {
            return Convert.ToHexString(RandomNumberGenerator.GetBytes(16)).ToLowerInvariant();
        }

        private static string Digest(string value)
        {
            if (string.IsNullOrEmpty(value)) return "none";
            byte[] hash = SHA256.HashData(Encoding.UTF8.GetBytes(value));
            return Convert.ToHexString(hash, 0, 6).ToLowerInvariant();
        }

        private static string Lower(bool value) { return value ? "true" : "false"; }

        private static string SafeWord(string value)
        {
            if (string.IsNullOrEmpty(value)) return "none";
            StringBuilder result = new StringBuilder(Math.Min(value.Length, 48));
            for (int i = 0; i < value.Length && result.Length < 48; i++)
            {
                char c = value[i];
                if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
                    || (c >= '0' && c <= '9') || c == '_' || c == '-') result.Append(c);
            }
            return result.Length == 0 ? "none" : result.ToString();
        }

        private static bool SameIdentity(DevLockboxS0Coordinator.AttemptIdentity left,
            DevLockboxS0Coordinator.AttemptIdentity right)
        {
            return left != null && right != null
                && left.FlowHandle == right.FlowHandle
                && left.PanelInstanceId == right.PanelInstanceId
                && left.WebDocumentEpoch == right.WebDocumentEpoch;
        }

        private static bool IsRuntimeOpenRejection(string code)
        {
            switch (code)
            {
                case "open_schema_mismatch":
                case "protocol_version_mismatch":
                case "invalid_capability":
                case "invalid_connection_generation":
                case "invalid_game_process_id":
                case "invalid_document_epoch":
                case "source_mismatch":
                case "fixture_mismatch":
                case "arm_mismatch":
                case "invalid_flow_handle":
                case "invalid_panel_instance":
                case "dom_bind_not_committed":
                case "panel_open_exception":
                case "same_name_rebind_rejected":
                    return true;
                default:
                    return false;
            }
        }

        private static bool TryParseResult(string value,
            out DevLockboxS0Coordinator.LimitedResult result)
        {
            if (value == "success") { result = DevLockboxS0Coordinator.LimitedResult.Success; return true; }
            if (value == "cancel") { result = DevLockboxS0Coordinator.LimitedResult.Cancel; return true; }
            if (value == "failure") { result = DevLockboxS0Coordinator.LimitedResult.Failure; return true; }
            result = DevLockboxS0Coordinator.LimitedResult.Failure;
            return false;
        }

        private static string ResultName(DevLockboxS0Coordinator.LimitedResult result)
        {
            if (result == DevLockboxS0Coordinator.LimitedResult.Success) return "success";
            if (result == DevLockboxS0Coordinator.LimitedResult.Cancel) return "cancel";
            return "failure";
        }

        private static bool IsAuthorityState(string state)
        {
            return state == "LOCK_PENDING" || state == "OPENING_ANIMATION"
                || state == "COMPLETED_NO_REWARD" || state == "REVOKED" || state == "EXPIRED";
        }

        private static bool IsTerminalState(string state)
        {
            return state == "COMPLETED_NO_REWARD" || state == "REVOKED" || state == "EXPIRED";
        }

        private static bool IsValidResultAuthorityState(
            DevLockboxS0Coordinator.LimitedResult result, string state, bool terminal)
        {
            if (result == DevLockboxS0Coordinator.LimitedResult.Success)
            {
                return (!terminal && state == "OPENING_ANIMATION")
                    || (terminal && (state == "COMPLETED_NO_REWARD" || state == "EXPIRED"));
            }
            return terminal && state == "REVOKED";
        }

        private static bool IsValidQueryAuthorityState(
            string disposition, string state, bool terminal)
        {
            if (disposition == "success")
                return IsValidResultAuthorityState(
                    DevLockboxS0Coordinator.LimitedResult.Success, state, terminal);
            if (disposition == "cancel" || disposition == "failure" || disposition == "not_applied")
                return terminal && state == "REVOKED";
            return false;
        }

        private static string BeginRejectionCode(DevLockboxS0Coordinator.BeginRejection rejection)
        {
            return rejection switch
            {
                DevLockboxS0Coordinator.BeginRejection.Busy => "busy",
                DevLockboxS0Coordinator.BeginRejection.NotDevRepository => "not_dev_repository",
                DevLockboxS0Coordinator.BeginRejection.EnvironmentGateClosed => "environment_gate_closed",
                DevLockboxS0Coordinator.BeginRejection.UntrustedOrigin => "untrusted_origin",
                DevLockboxS0Coordinator.BeginRejection.SourceMismatch => "source_mismatch",
                DevLockboxS0Coordinator.BeginRejection.FixtureMismatch => "fixture_mismatch",
                DevLockboxS0Coordinator.BeginRejection.PanelOrchestrationBusy => "panel_orchestration_busy",
                DevLockboxS0Coordinator.BeginRejection.InvalidDocumentEpoch => "invalid_document_epoch",
                DevLockboxS0Coordinator.BeginRejection.DocumentEpochMismatch => "document_epoch_mismatch",
                DevLockboxS0Coordinator.BeginRejection.InvalidIdentity => "invalid_identity",
                _ => "invalid_request"
            };
        }

        private static string BuildBeginFailure(JToken callId, string error)
        {
            JObject value = new JObject
            {
                ["task"] = SocketResponseTask,
                ["action"] = "begin",
                ["success"] = false,
                ["accepted"] = false,
                ["error"] = error
            };
            if (callId != null && callId.Type == JTokenType.Integer) value["callId"] = callId.DeepClone();
            return value.ToString(Formatting.None);
        }

        private static string BuildBeginSuccess(JToken callId,
            DevLockboxS0Coordinator.AttemptIdentity identity)
        {
            JObject value = new JObject
            {
                ["task"] = SocketResponseTask,
                ["action"] = "begin",
                ["success"] = true,
                ["accepted"] = true,
                ["flowHandle"] = identity.FlowHandle,
                ["panelInstanceId"] = identity.PanelInstanceId,
                ["documentEpoch"] = identity.WebDocumentEpoch,
                ["callId"] = callId.DeepClone()
            };
            return value.ToString(Formatting.None);
        }

        private void ReplaceTimer(OwnedTimerSlot slot, int dueMilliseconds, Action callback)
        {
            Timer timer = null;
            long version;
            Timer old;
            lock (_sync)
            {
                if (_disposed) return;
                version = ++slot.Version;
                timer = new Timer(delegate
                {
                    bool run;
                    lock (_sync)
                    {
                        run = !_disposed && slot.Version == version
                            && ReferenceEquals(slot.Timer, timer);
                        if (ReferenceEquals(slot.Timer, timer)) slot.Timer = null;
                    }
                    timer.Dispose();
                    if (run) callback();
                }, null, Timeout.Infinite, Timeout.Infinite);
                old = slot.Timer;
                slot.Timer = timer;
                timer.Change(dueMilliseconds, Timeout.Infinite);
            }
            old?.Dispose();
        }

        private void DisposeTimer(OwnedTimerSlot slot)
        {
            Timer old;
            lock (_sync)
            {
                slot.Version += 1;
                old = slot.Timer;
                slot.Timer = null;
            }
            old?.Dispose();
        }

        private static void Log(string eventName, string fields)
        {
            LogManager.Log("[DevLockboxS0] event=" + eventName
                + (string.IsNullOrEmpty(fields) ? "" : " " + fields));
        }

        public void Dispose()
        {
            CapabilityBinding disposedBinding = null;
            Timer disposedRetry = null;
            int callerThreadId = Thread.CurrentThread.ManagedThreadId;
            lock (_sync)
            {
                if (_disposed)
                {
                    while (!_disposeCompleted && GetOutboundDepthLocked(callerThreadId) == 0)
                        Monitor.Wait(_sync);
                    return;
                }
                _disposed = true;
                disposedBinding = _binding;
                _binding = null;
                _connectionAlive = false;
                disposedRetry = DetachBindingRetryTimerLocked();
            }
            try
            {
                DisposeTimer(_bindTimer);
                DisposeTimer(_authorityTimer);
                DisposeBindingAckTimer(disposedBinding);
                disposedRetry?.Dispose();
                StopReconcileTick();
                lock (_sync)
                {
                    int callerDepth = GetOutboundDepthLocked(callerThreadId);
                    while (_outboundActionsInFlight > callerDepth)
                        Monitor.Wait(_sync);
                }
            }
            finally
            {
                lock (_sync)
                {
                    _disposeCompleted = true;
                    Monitor.PulseAll(_sync);
                }
            }
        }
    }
}
