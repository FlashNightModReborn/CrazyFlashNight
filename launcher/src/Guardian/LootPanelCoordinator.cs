using System;
using System.Threading;
using CF7Launcher.AgentRuntime.Security;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Guardian
{
    public interface ILootPanelPort
    {
        bool IsAvailable { get; }
        bool IsIdleForTrackedOpen { get; }
        string ActivePanelName { get; }
        string ActivePanelInstanceId { get; }
        bool TryAcquireIdleFence(string token);
        bool ReleaseIdleFenceExact(string token);
        bool TryOpenTracked(string initDataJson, string panelInstanceId,
            Func<bool> executionGate, Action<PanelHostController.TrackedOpenOutcome> completed);
        bool TryCloseExact(string panelInstanceId, Action<bool> completed);
    }

    public sealed class LootPanelHostPort : ILootPanelPort
    {
        private readonly PanelHostController _panelHost;

        public LootPanelHostPort(PanelHostController panelHost)
        {
            _panelHost = panelHost;
        }

        public bool IsAvailable { get { return _panelHost != null; } }
        public bool IsIdleForTrackedOpen
        {
            get { return _panelHost != null && _panelHost.IsIdleForTrackedOpen; }
        }
        public string ActivePanelName
        {
            get { return _panelHost != null ? _panelHost.ActivePanelName : null; }
        }
        public string ActivePanelInstanceId
        {
            get { return _panelHost != null ? _panelHost.ActivePanelInstanceId : null; }
        }

        public bool TryAcquireIdleFence(string token)
        {
            return _panelHost != null && _panelHost.TryAcquireIdleFence(token);
        }

        public bool ReleaseIdleFenceExact(string token)
        {
            return _panelHost != null && _panelHost.ReleaseIdleFenceExact(token);
        }

        public bool TryOpenTracked(string initDataJson, string panelInstanceId,
            Func<bool> executionGate, Action<PanelHostController.TrackedOpenOutcome> completed)
        {
            return _panelHost != null && _panelHost.TryOpenTrackedPanel(
                "loot", initDataJson, panelInstanceId, executionGate, completed);
        }

        public bool TryCloseExact(string panelInstanceId, Action<bool> completed)
        {
            return _panelHost != null && _panelHost.TryCloseTrackedPanelExact(
                "loot", panelInstanceId, completed);
        }
    }

    /// <summary>
    /// Host-owned visual binding for a single AS2-authoritative loot container. Queue acceptance,
    /// native open, Web binding, AS2 terminal state, and visual detach are deliberately distinct.
    /// This coordinator never invents a chest/container terminal state.
    /// </summary>
    public sealed class LootPanelCoordinator : IDisposable
    {
        public const int ProtocolVersion = 1;
        public const string PanelName = "loot";
        public const string MapChestSource = "map_chest";
        public const string StageSettlementSource = "stage_settlement";
        public const string RewardInboxSource = "reward_inbox";
        public const string RequiredSource = MapChestSource;
        public const int MaximumOpaqueLength = 128;
        public const int DefaultBindWatchdogMs = 2500;
        public const int DefaultCloseRetryDelayMs = 250;
        public const int DefaultCloseRetryMaximumMs = 1000;
        public const int DefaultPauseReleaseRetryMs = 250;

        public enum BindingState
        {
            Idle,
            OpenQueued,
            OpenPosted,
            Bound,
            TerminalCloseQueued,
            SuspendedCloseQueued,
            ForceDetachQueued,
            PauseReleasePending
        }

        public sealed class OpenRequest
        {
            public string ChestSessionId { get; set; }
            public string LootContainerId { get; set; }
            public int ContainerEpoch { get; set; }
            public int OpenAttemptSeq { get; set; }
            public string DisplayName { get; set; }
            public int Capacity { get; set; }
            public int Columns { get; set; }
            public string SourceKind { get; set; }
            public JObject SettlementReport { get; set; }
        }

        public sealed class Binding
        {
            internal Binding(OpenRequest request, string panelInstanceId)
            {
                ChestSessionId = request.ChestSessionId;
                LootContainerId = request.LootContainerId;
                ContainerEpoch = request.ContainerEpoch;
                OpenAttemptSeq = request.OpenAttemptSeq;
                DisplayName = request.DisplayName;
                Capacity = request.Capacity;
                Columns = request.Columns;
                SourceKind = request.SourceKind;
                SettlementReport = request.SettlementReport != null
                    ? (JObject)request.SettlementReport.DeepClone() : null;
                PanelInstanceId = panelInstanceId;
            }

            public string ChestSessionId { get; private set; }
            public string LootContainerId { get; private set; }
            public int ContainerEpoch { get; private set; }
            public int OpenAttemptSeq { get; private set; }
            public string DisplayName { get; private set; }
            public int Capacity { get; private set; }
            public int Columns { get; private set; }
            public string SourceKind { get; private set; }
            public JObject SettlementReport { get; private set; }
            public string PanelInstanceId { get; private set; }
        }

        private readonly object _sync = new object();
        private readonly ILootPanelPort _panel;
        private readonly Func<bool> _releasePause;
        private readonly Func<Binding, string, bool> _requestRecovery;
        private readonly Func<string> _panelInstanceIdFactory;
        private readonly int _bindWatchdogMs;
        private readonly int _closeRetryDelayMs;
        private readonly int _closeRetryMaximumMs;
        private readonly int _pauseReleaseRetryMs;
        private Func<IDisposable> _acquireAdmissionLease;
        private Func<bool> _externalAdmissionGate;
        private Func<Binding, bool> _rewardInboxReturnHandler;
        private BindingState _state;
        private Binding _active;
        private bool _openExecutionStarted;
        private bool _openPosted;
        private bool _recoverySignalAttempted;
        private Binding _recoveryInFlightBinding;
        private bool _deferredFinalizePending;
        private bool _deferredFinalizeReleasePause;
        private bool _closeRequestPending;
        private int _closeAttemptGeneration;
        private int _closeAttemptCount;
        private Timer _bindWatchdog;
        private Timer _closeRetryTimer;
        private Timer _pauseReleaseRetryTimer;
        // Set at the instant a strict AS2 response proves either a terminal tombstone or the
        // non-terminal LOOT_SUSPENDED handoff, before any native close completes.  The exact proof
        // kind is sticky across force-detach/close/pause-release races so a late Web acknowledgement
        // remains idempotent but can never swap terminal and suspended semantics.  A fresh accepted
        // binding clears both fields.
        private string _authorityVisualCloseProvenPanelInstanceId;
        private string _authorityVisualCloseProvenReason;
        private string _rewardInboxReplacementPendingPanelInstanceId;
        private string _rewardInboxReplacementPendingReason;
        private bool _disposed;

        public LootPanelCoordinator(ILootPanelPort panel, Func<bool> releasePause,
            Func<string> panelInstanceIdFactory = null,
            Func<Binding, string, bool> requestRecovery = null,
            int bindWatchdogMs = DefaultBindWatchdogMs,
            int closeRetryDelayMs = DefaultCloseRetryDelayMs,
            int closeRetryMaximumMs = DefaultCloseRetryMaximumMs,
            int pauseReleaseRetryMs = DefaultPauseReleaseRetryMs)
        {
            if (bindWatchdogMs <= 0) throw new ArgumentOutOfRangeException("bindWatchdogMs");
            if (closeRetryDelayMs <= 0) throw new ArgumentOutOfRangeException("closeRetryDelayMs");
            if (closeRetryMaximumMs < closeRetryDelayMs)
                throw new ArgumentOutOfRangeException("closeRetryMaximumMs");
            if (pauseReleaseRetryMs <= 0)
                throw new ArgumentOutOfRangeException("pauseReleaseRetryMs");
            _panel = panel;
            _releasePause = releasePause;
            _requestRecovery = requestRecovery;
            _panelInstanceIdFactory = panelInstanceIdFactory
                ?? delegate
                {
                    return OpaqueIdGenerator.Create(
                        "panelloot");
                };
            _bindWatchdogMs = bindWatchdogMs;
            _closeRetryDelayMs = closeRetryDelayMs;
            _closeRetryMaximumMs = closeRetryMaximumMs;
            _pauseReleaseRetryMs = pauseReleaseRetryMs;
            _state = BindingState.Idle;
        }

        public event Action BindingDetached;

        /// <summary>
        /// Fires only after an executed Loot visual has retired and its global pause release has
        /// completed behind PanelHost's idle fence. Consumers may use the captured immutable
        /// binding to begin a fresh panel preflight; they must not reuse the retired Web session.
        /// </summary>
        public event Action<Binding> BindingSettled;

        /// <summary>
        /// Installs the LootTask recovery-fence admission lease. The factory is invoked outside
        /// coordinator locks and returns a held lease only when no old write/detached authority
        /// can race this open. Production wires it immediately after LootTask construction.
        /// </summary>
        public void SetAdmissionLeaseFactory(Func<IDisposable> acquireAdmissionLease)
        {
            lock (_sync) _acquireAdmissionLease = acquireAdmissionLease;
        }

        /// <summary>
        /// Cross-panel admission fence evaluated both before queueing and again on the UI-thread
        /// tracked-open execution gate. CharacterBuild uses it while its exact pause lease is
        /// awaiting terminal recovery, so Loot can never reuse or later release that lease.
        /// </summary>
        public void SetExternalAdmissionGate(
            Func<bool> externalAdmissionGate)
        {
            lock (_sync)
                _externalAdmissionGate = externalAdmissionGate;
        }

        /// <summary>
        /// Installs the one fixed Reward Inbox -> Character Build navigation edge. The callback
        /// runs only after strict terminal/suspended authority proof, while the exact Loot visual
        /// and its inherited pause lease are still owned by this coordinator.
        /// </summary>
        public void SetRewardInboxReturnHandler(
            Func<Binding, bool> rewardInboxReturnHandler)
        {
            lock (_sync)
                _rewardInboxReturnHandler = rewardInboxReturnHandler;
        }

        public BindingState State { get { lock (_sync) return _state; } }
        public Binding ActiveBinding { get { lock (_sync) return _active; } }

        public string HandlePanelRequest(JObject request)
        {
            OpenRequest normalized;
            string error;
            if (!TryNormalizePanelRequest(request, out normalized, out error))
                return BuildOpenAck(false, error);

            string rejection;
            bool accepted = TryOpen(normalized, out rejection);
            return BuildOpenAck(accepted, accepted ? null : rejection);
        }

        public bool TryOpen(OpenRequest request, out string rejection)
        {
            rejection = null;
            if (request == null || request.OpenAttemptSeq < 1)
            {
                rejection = "invalid_request";
                return false;
            }
            Func<IDisposable> acquireAdmissionLease;
            Func<bool> externalAdmissionGate;
            lock (_sync)
            {
                if (_disposed)
                {
                    rejection = "coordinator_disposed";
                    return false;
                }
                acquireAdmissionLease = _acquireAdmissionLease;
                externalAdmissionGate = _externalAdmissionGate;
            }
            if (!AllowsExternalAdmission(
                externalAdmissionGate))
            {
                rejection = "recovery_pending";
                return false;
            }
            if (_panel == null || !_panel.IsAvailable)
            {
                rejection = "panel_unavailable";
                return false;
            }
            if (!_panel.IsIdleForTrackedOpen)
            {
                rejection = "panel_busy";
                return false;
            }

            string panelInstanceId;
            try { panelInstanceId = _panelInstanceIdFactory(); }
            catch { panelInstanceId = null; }
            if (!IsOpaque(panelInstanceId))
            {
                rejection = "identity_unavailable";
                return false;
            }

            Binding binding = new Binding(request, panelInstanceId);
            IDisposable admissionLease = null;
            if (acquireAdmissionLease != null)
            {
                try { admissionLease = acquireAdmissionLease(); }
                catch (Exception ex)
                {
                    LogManager.Log("event=loot_panel_admission_gate_failed type="
                        + ex.GetType().Name);
                }
                if (admissionLease == null)
                {
                    rejection = "flow_busy";
                    return false;
                }
            }
            try
            {
                if (!AllowsExternalAdmission(
                    externalAdmissionGate))
                {
                    rejection = "recovery_pending";
                    return false;
                }
                lock (_sync)
                {
                    if (_disposed)
                    {
                        rejection = "coordinator_disposed";
                        return false;
                    }
                    if (_state != BindingState.Idle || _active != null)
                    {
                        rejection = "flow_busy";
                        return false;
                    }
                    _active = binding;
                    _authorityVisualCloseProvenPanelInstanceId = null;
                    _authorityVisualCloseProvenReason = null;
                    _state = BindingState.OpenQueued;
                    _openExecutionStarted = false;
                    _openPosted = false;
                    _recoverySignalAttempted = false;
                    _recoveryInFlightBinding = null;
                    _deferredFinalizePending = false;
                    _deferredFinalizeReleasePause = false;
                    _closeRequestPending = false;
                    ClearRewardInboxReplacementLocked();
                    _closeAttemptGeneration = 0;
                    _closeAttemptCount = 0;
                }
            }
            finally { if (admissionLease != null) admissionLease.Dispose(); }

            JObject init = new JObject
            {
                ["v"] = ProtocolVersion,
                ["chestSessionId"] = binding.ChestSessionId,
                ["lootContainerId"] = binding.LootContainerId,
                ["containerEpoch"] = binding.ContainerEpoch,
                ["displayName"] = binding.DisplayName,
                ["capacity"] = binding.Capacity,
                ["columns"] = binding.Columns
            };
            if (binding.SourceKind == RewardInboxSource)
            {
                init["sourceKind"] = RewardInboxSource;
            }
            else if (binding.SourceKind == StageSettlementSource)
            {
                init["sourceKind"] = StageSettlementSource;
                init["report"] = binding.SettlementReport != null
                    ? binding.SettlementReport.DeepClone() : null;
            }

            bool queued = false;
            try
            {
                queued = _panel.TryOpenTracked(init.ToString(Formatting.None), panelInstanceId,
                    delegate
                    {
                        return AllowsExternalAdmission(
                                externalAdmissionGate)
                            && MarkOpenExecuting(binding);
                    },
                    delegate(PanelHostController.TrackedOpenOutcome outcome)
                    {
                        CompleteOpen(binding, outcome);
                    });
            }
            catch (Exception ex)
            {
                LogManager.Log("event=loot_panel_open_queue_failed type=" + ex.GetType().Name);
                queued = false;
            }
            if (queued)
            {
                ArmBindWatchdog(binding);
                return true;
            }

            lock (_sync)
            {
                if (ReferenceEquals(_active, binding))
                {
                    CancelBindWatchdogLocked();
                    CancelCloseRetryLocked();
                    CancelPauseReleaseRetryLocked();
                    _active = null;
                    _state = BindingState.Idle;
                    _openExecutionStarted = false;
                    _openPosted = false;
                    _recoverySignalAttempted = false;
                    _closeRequestPending = false;
                }
            }
            rejection = "open_not_queued";
            return false;
        }

        /// <summary>
        /// Host-only admission for an AS2-stamped durable reward inbox. Unlike panel_request,
        /// this path can run only after the exact CharacterBuild visual and pause owner retire.
        /// </summary>
        public bool TryOpenRewardInbox(
            JObject rewardAuthority,
            out string rejection)
        {
            OpenRequest normalized;
            if (!TryNormalizeRewardAuthority(
                    rewardAuthority, out normalized, out rejection))
            {
                return false;
            }
            return TryOpen(normalized, out rejection);
        }

        /// <summary>
        /// Dedicated AS2 world-entry envelope for an already-durable Reward Inbox authority.
        /// This does not widen the ordinary map/stage panel_request normalizer.
        /// </summary>
        public string HandleRewardInboxPanelRequest(JObject rewardAuthority)
        {
            string rejection;
            bool accepted = TryOpenRewardInbox(
                rewardAuthority,
                out rejection);
            return BuildOpenAck(
                accepted,
                accepted ? null : rejection);
        }

        private static bool AllowsExternalAdmission(
            Func<bool> externalAdmissionGate)
        {
            if (externalAdmissionGate == null) return true;
            try { return externalAdmissionGate(); }
            catch { return false; }
        }

        public bool TryBindExact(string panelInstanceId, string chestSessionId,
            string lootContainerId, int containerEpoch, out Binding binding)
        {
            lock (_sync)
            {
                binding = _active;
                if ((_state != BindingState.OpenPosted && _state != BindingState.Bound)
                    || !MatchesLocked(binding, panelInstanceId, chestSessionId,
                        lootContainerId, containerEpoch)
                    || _panel == null
                    || !string.Equals(_panel.ActivePanelName, PanelName, StringComparison.Ordinal)
                    || !string.Equals(_panel.ActivePanelInstanceId, panelInstanceId,
                        StringComparison.Ordinal))
                {
                    binding = null;
                    return false;
                }
                _state = BindingState.Bound;
                CancelBindWatchdogLocked();
                return true;
            }
        }

        public bool IsCurrentExact(Binding binding)
        {
            lock (_sync)
            {
                return binding != null && ReferenceEquals(_active, binding)
                    && (_state == BindingState.Bound || _state == BindingState.TerminalCloseQueued)
                    && _panel != null
                    && string.Equals(_panel.ActivePanelName, PanelName, StringComparison.Ordinal)
                    && string.Equals(_panel.ActivePanelInstanceId, binding.PanelInstanceId,
                        StringComparison.Ordinal);
            }
        }

        public bool IsActiveVisualExact(string panelInstanceId, bool requireTerminalClose)
        {
            lock (_sync)
            {
                bool stateAllowed = requireTerminalClose
                    ? _state == BindingState.TerminalCloseQueued
                    : _state == BindingState.OpenPosted || _state == BindingState.Bound;
                return stateAllowed && _active != null
                    && string.Equals(_active.PanelInstanceId, panelInstanceId,
                        StringComparison.Ordinal)
                    && _panel != null
                    && string.Equals(_panel.ActivePanelName, PanelName, StringComparison.Ordinal)
                    && string.Equals(_panel.ActivePanelInstanceId, panelInstanceId,
                        StringComparison.Ordinal);
            }
        }

        /// <summary>
        /// Returns true only after the Web loot document has completed its exact AS2/Host bind.
        /// Embedded inventory authority must never be exposed during OpenPosted: the panel can be
        /// visible there, but its chest identity has not yet been acknowledged by the Web runtime.
        /// </summary>
        public bool IsBoundVisualExact(string panelInstanceId)
        {
            lock (_sync)
            {
                return _state == BindingState.Bound && _active != null
                    && string.Equals(_active.PanelInstanceId, panelInstanceId,
                        StringComparison.Ordinal)
                    && _panel != null
                    && string.Equals(_panel.ActivePanelName, PanelName,
                        StringComparison.Ordinal)
                    && string.Equals(_panel.ActivePanelInstanceId, panelInstanceId,
                        StringComparison.Ordinal);
            }
        }

        /// <summary>Called only after a strict AS2 response proves an authority terminal.</summary>
        public bool CloseAfterAuthorityTerminal(Binding binding)
        {
            return CloseAfterAuthorityVisualProof(binding, "terminal",
                BindingState.TerminalCloseQueued);
        }

        /// <summary>
        /// Called only after a strict AS2 response proves LOOT_SUSPENDED.  Suspension is
        /// non-terminal authority state, but it owns the same exact visual-close and pause-release
        /// sequence as a terminal response and must remain sticky against a racing force detach.
        /// </summary>
        public bool CloseAfterAuthoritySuspended(Binding binding)
        {
            return CloseAfterAuthorityVisualProof(binding, "suspended",
                BindingState.SuspendedCloseQueued);
        }

        private bool CloseAfterAuthorityVisualProof(Binding binding, string reason,
            BindingState closeState)
        {
            Func<Binding, bool> rewardInboxReturnHandler = null;
            lock (_sync)
            {
                if (!ReferenceEquals(_active, binding)
                    || (_state != BindingState.Bound
                        && _state != BindingState.ForceDetachQueued
                        && _state != closeState))
                    return false;
                _authorityVisualCloseProvenPanelInstanceId = binding.PanelInstanceId;
                _authorityVisualCloseProvenReason = reason;
                _state = closeState;
                CancelBindWatchdogLocked();
                if (binding.SourceKind == RewardInboxSource
                    && _rewardInboxReturnHandler != null)
                {
                    _rewardInboxReplacementPendingPanelInstanceId =
                        binding.PanelInstanceId;
                    _rewardInboxReplacementPendingReason = reason;
                    rewardInboxReturnHandler = _rewardInboxReturnHandler;
                }
            }
            if (rewardInboxReturnHandler != null)
            {
                bool accepted = false;
                try { accepted = rewardInboxReturnHandler(binding); }
                catch (Exception ex)
                {
                    LogManager.Log(
                        "event=reward_inbox_return_handler_failed type="
                        + ex.GetType().Name);
                }
                if (accepted) return true;
                CancelRewardInboxReplacementAndCloseExact(
                    binding.PanelInstanceId);
                return true;
            }
            return QueueAuthorityVisualClose(binding, closeState);
        }

        /// <summary>
        /// True only while the fixed Reward Inbox -> Character Build replacement owns the exact
        /// active Loot binding. Web's terminal close acknowledgement must not retire the surface
        /// during this interval; the replacement either commits in place or falls back to the
        /// ordinary exact close path.
        /// </summary>
        public bool IsRewardInboxReplacementPendingExact(
            string panelInstanceId)
        {
            lock (_sync)
            {
                return !_disposed
                    && _active != null
                    && _active.SourceKind == RewardInboxSource
                    && IsCloseState(_state)
                    && string.Equals(
                        _active.PanelInstanceId,
                        panelInstanceId,
                        StringComparison.Ordinal)
                    && string.Equals(
                        _rewardInboxReplacementPendingPanelInstanceId,
                        panelInstanceId,
                        StringComparison.Ordinal)
                    && _panel != null
                    && string.Equals(
                        _panel.ActivePanelName,
                        PanelName,
                        StringComparison.Ordinal)
                    && string.Equals(
                        _panel.ActivePanelInstanceId,
                        panelInstanceId,
                        StringComparison.Ordinal);
            }
        }

        /// <summary>
        /// Consumes the old tracked Loot ownership after PanelHost has accepted the exact target
        /// payload. The global pause lease deliberately remains live for the fresh Character Build
        /// authority; no BindingSettled callback is emitted because there is no Host-idle gap.
        /// </summary>
        public bool CompleteRewardInboxReplacementExact(
            string panelInstanceId)
        {
            bool notify = false;
            lock (_sync)
            {
                if (!IsRewardInboxReplacementPendingLocked(panelInstanceId))
                    return false;
                CancelBindWatchdogLocked();
                CancelCloseRetryLocked();
                CancelPauseReleaseRetryLocked();
                _active = null;
                _state = BindingState.Idle;
                _openExecutionStarted = false;
                _openPosted = false;
                _recoverySignalAttempted = false;
                _recoveryInFlightBinding = null;
                _deferredFinalizePending = false;
                _deferredFinalizeReleasePause = false;
                _closeRequestPending = false;
                ClearRewardInboxReplacementLocked();
                notify = true;
            }
            if (notify) NotifyDetached();
            return notify;
        }

        /// <summary>
        /// Aborts only the exact pending replacement and resumes the existing close/unpause path.
        /// A later BindingSettled callback may then reopen Character Build from the idle baseline.
        /// </summary>
        public bool CancelRewardInboxReplacementAndCloseExact(
            string panelInstanceId)
        {
            Binding binding;
            BindingState closeState;
            lock (_sync)
            {
                if (!IsRewardInboxReplacementPendingLocked(panelInstanceId))
                    return false;
                binding = _active;
                closeState = _state;
                ClearRewardInboxReplacementLocked();
            }
            return QueueAuthorityVisualClose(binding, closeState);
        }

        public bool RetryAuthorityTerminalCloseExact(string panelInstanceId)
        {
            return RetryAuthorityVisualCloseExact(panelInstanceId, "terminal");
        }

        public bool RetryAuthoritySuspendedCloseExact(string panelInstanceId)
        {
            return RetryAuthorityVisualCloseExact(panelInstanceId, "suspended");
        }

        public bool RetryAuthorityVisualCloseExact(string panelInstanceId, string reason)
        {
            Binding binding;
            BindingState expectedState = CloseStateForReason(reason);
            if (expectedState == BindingState.Idle) return false;
            lock (_sync)
            {
                binding = _active;
                if (binding == null || _state != expectedState
                    || !string.Equals(binding.PanelInstanceId, panelInstanceId,
                        StringComparison.Ordinal)) return false;
            }
            return QueueAuthorityVisualClose(binding, expectedState);
        }

        /// <summary>
        /// True only when a strict AS2 authority terminal has been observed for this exact active
        /// or most recently detached generated panel instance. This is an idempotency proof for
        /// Web's late terminal notification, not a close command or wildcard idle-state allowance.
        /// </summary>
        public bool IsAuthorityTerminalCloseKnownExact(string panelInstanceId)
        {
            return IsAuthorityVisualCloseKnownExact(panelInstanceId, "terminal");
        }

        public bool IsAuthoritySuspendedCloseKnownExact(string panelInstanceId)
        {
            return IsAuthorityVisualCloseKnownExact(panelInstanceId, "suspended");
        }

        public bool IsAuthorityVisualCloseKnownExact(string panelInstanceId, string reason)
        {
            if (!IsOpaque(panelInstanceId) || CloseStateForReason(reason) == BindingState.Idle)
                return false;
            lock (_sync)
            {
                if (_disposed) return false;
                return string.Equals(_authorityVisualCloseProvenPanelInstanceId,
                        panelInstanceId, StringComparison.Ordinal)
                    && string.Equals(_authorityVisualCloseProvenReason, reason,
                        StringComparison.Ordinal);
            }
        }

        public bool IsAuthorityVisualCloseActiveExact(string panelInstanceId, string reason)
        {
            BindingState expectedState = CloseStateForReason(reason);
            if (expectedState == BindingState.Idle) return false;
            lock (_sync)
            {
                return _state == expectedState && _active != null
                    && string.Equals(_active.PanelInstanceId, panelInstanceId,
                        StringComparison.Ordinal)
                    && _panel != null
                    && string.Equals(_panel.ActivePanelName, PanelName,
                        StringComparison.Ordinal)
                    && string.Equals(_panel.ActivePanelInstanceId, panelInstanceId,
                        StringComparison.Ordinal);
            }
        }

        private bool QueueAuthorityVisualClose(Binding binding, BindingState expectedState)
        {
            lock (_sync)
            {
                if (!ReferenceEquals(_active, binding)
                    || _state != expectedState) return false;
                ClearRewardInboxReplacementLocked();
            }
            return QueueExactClose(binding);
        }

        private static BindingState CloseStateForReason(string reason)
        {
            if (reason == "terminal") return BindingState.TerminalCloseQueued;
            if (reason == "suspended") return BindingState.SuspendedCloseQueued;
            return BindingState.Idle;
        }

        /// <summary>
        /// Navigation, transport failure, or Host shutdown may detach only the exact visual
        /// binding. It does not emit lootClose and therefore cannot become CONSUMED/ABANDONED.
        /// </summary>
        public bool ForceDetach(string reason)
        {
            Binding binding;
            bool closeNative;
            bool alreadyQueued;
            bool authorityVisualCloseProven;
            BindingState authorityCloseState;
            lock (_sync)
            {
                binding = _active;
                if (_disposed || binding == null || _state == BindingState.Idle
                    || _state == BindingState.PauseReleasePending) return false;
                authorityCloseState = AuthorityCloseStateLocked(binding);
                authorityVisualCloseProven = authorityCloseState != BindingState.Idle;
                alreadyQueued = authorityVisualCloseProven
                    || _state == BindingState.ForceDetachQueued;
                if (authorityVisualCloseProven)
                {
                    // A visual/transport detach can never downgrade a strict AS2 tombstone or
                    // LOOT_SUSPENDED proof, nor re-enter either already-settled object into the
                    // authority-handoff path.
                    _state = authorityCloseState;
                    ClearRewardInboxReplacementLocked();
                    CancelBindWatchdogLocked();
                }
                else if (!alreadyQueued)
                {
                    _state = BindingState.ForceDetachQueued;
                    CancelBindWatchdogLocked();
                }
                closeNative = _openExecutionStarted || _openPosted;
            }

            LogManager.Log("event=loot_panel_force_detach reason=" + SafeReason(reason));
            string recoveryReason = RecoveryReasonForDetach(reason);
            if (!authorityVisualCloseProven && recoveryReason != null)
                TrySignalRecoveryOnce(binding, recoveryReason);
            if (!closeNative)
            {
                // The captured execution gate is now stale and will reject if the queued command
                // eventually reaches the UI thread. No pause/native/DOM side effect is required
                // for same-object AS2 authority convergence, so it is safe to finish immediately.
                FinalizeDetached(binding, false);
                return true;
            }
            if (!alreadyQueued || !IsCloseAttemptOwned(binding)) QueueExactClose(binding);
            return true;
        }

        public void OnPanelHostClosed(string panelName, string panelInstanceId)
        {
            Binding detached;
            bool unexpected;
            lock (_sync)
            {
                if (_disposed || _active == null || panelName != PanelName
                    || !string.Equals(_active.PanelInstanceId, panelInstanceId,
                        StringComparison.Ordinal)) return;
                detached = _active;
                if (_state == BindingState.PauseReleasePending) return;
                unexpected = !IsCloseState(_state);
            }
            if (unexpected) TrySignalRecoveryOnce(detached, "web_open_failed");
            FinalizeDetached(detached, true);
        }

        private bool MarkOpenExecuting(Binding binding)
        {
            lock (_sync)
            {
                if (_disposed || !ReferenceEquals(_active, binding)
                    || _state != BindingState.OpenQueued)
                    return false;
                _openExecutionStarted = true;
                return true;
            }
        }

        private void CompleteOpen(Binding binding, PanelHostController.TrackedOpenOutcome outcome)
        {
            bool forceClosePosted = false;
            bool recoverOpenFailure = false;
            bool releasePauseAfterFailure = false;
            lock (_sync)
            {
                if (_disposed || !ReferenceEquals(_active, binding)) return;
                if (outcome == PanelHostController.TrackedOpenOutcome.OpenPosted
                    && _state == BindingState.OpenQueued)
                {
                    _openPosted = true;
                    _state = BindingState.OpenPosted;
                    LogManager.Log("event=loot_panel_open_posted");
                    return;
                }
                if (outcome == PanelHostController.TrackedOpenOutcome.OpenPosted
                    && _state == BindingState.ForceDetachQueued)
                {
                    // ForceDetach won the race after execution began but before completion. The
                    // exact close retry loop remains owned by the captured binding.
                    _openPosted = true;
                    forceClosePosted = true;
                }
                else
                {
                    CancelBindWatchdogLocked();
                    recoverOpenFailure = _state != BindingState.ForceDetachQueued;
                    releasePauseAfterFailure = _openExecutionStarted;
                }
            }
            if (forceClosePosted)
            {
                QueueExactClose(binding);
                return;
            }
            if (recoverOpenFailure) TrySignalRecoveryOnce(binding, "web_open_failed");
            FinalizeDetached(binding, releasePauseAfterFailure);
            LogManager.Log("event=loot_panel_open_failed outcome=" + outcome.ToString());
        }

        private void NotifyDetached()
        {
            Action handler = BindingDetached;
            if (handler != null)
            {
                try { handler(); }
                catch (Exception ex)
                {
                    LogManager.Log("event=loot_binding_detached_callback_failed type="
                        + ex.GetType().Name);
                }
            }
        }

        private void NotifySettled(Binding binding)
        {
            Action<Binding> handler = BindingSettled;
            if (handler != null)
            {
                try { handler(binding); }
                catch (Exception ex)
                {
                    LogManager.Log("event=loot_binding_settled_callback_failed type="
                        + ex.GetType().Name);
                }
            }
        }

        private void ArmBindWatchdog(Binding binding)
        {
            Timer timer = null;
            timer = new Timer(delegate { OnBindWatchdog(binding, timer); }, null,
                Timeout.Infinite, Timeout.Infinite);
            bool armed = false;
            lock (_sync)
            {
                if (!_disposed && ReferenceEquals(_active, binding)
                    && (_state == BindingState.OpenQueued || _state == BindingState.OpenPosted))
                {
                    CancelBindWatchdogLocked();
                    _bindWatchdog = timer;
                    timer.Change(_bindWatchdogMs, Timeout.Infinite);
                    armed = true;
                }
            }
            if (!armed) timer.Dispose();
        }

        private void OnBindWatchdog(Binding binding, Timer timer)
        {
            bool expired = false;
            lock (_sync)
            {
                if (!_disposed && ReferenceEquals(_bindWatchdog, timer)
                    && ReferenceEquals(_active, binding)
                    && (_state == BindingState.OpenQueued || _state == BindingState.OpenPosted))
                {
                    _bindWatchdog = null;
                    expired = true;
                }
            }
            try { timer.Dispose(); } catch { }
            if (!expired) return;
            LogManager.Log("event=loot_panel_bind_watchdog_expired");
            ForceDetach("web_mount_failed");
        }

        private bool QueueExactClose(Binding binding)
        {
            int generation;
            lock (_sync)
            {
                if (_disposed || !ReferenceEquals(_active, binding)
                    || !IsCloseState(_state)) return false;
                if (_closeRequestPending) return true;
                CancelCloseRetryLocked();
                _closeRequestPending = true;
                generation = ++_closeAttemptGeneration;
                _closeAttemptCount++;
                ArmCloseAttemptWatchdogLocked(binding, generation);
            }

            bool queued = false;
            try
            {
                queued = _panel != null && _panel.TryCloseExact(binding.PanelInstanceId,
                    delegate(bool closed)
                    {
                        CompleteExactCloseAttempt(binding, generation, closed);
                    });
            }
            catch (Exception ex)
            {
                LogManager.Log("event=loot_panel_exact_close_queue_failed type="
                    + ex.GetType().Name);
            }
            if (!queued) CompleteExactCloseAttempt(binding, generation, false);
            return queued;
        }

        private void ArmCloseAttemptWatchdogLocked(Binding binding, int generation)
        {
            Timer timer = null;
            timer = new Timer(delegate { OnCloseAttemptWatchdog(binding, generation, timer); },
                null, Timeout.Infinite, Timeout.Infinite);
            _closeRetryTimer = timer;
            timer.Change(CloseRetryDelayLocked(), Timeout.Infinite);
        }

        private void OnCloseAttemptWatchdog(Binding binding, int generation, Timer timer)
        {
            bool retry = false;
            lock (_sync)
            {
                if (!_disposed && ReferenceEquals(_closeRetryTimer, timer)
                    && ReferenceEquals(_active, binding) && IsCloseState(_state)
                    && _closeRequestPending && _closeAttemptGeneration == generation)
                {
                    _closeRetryTimer = null;
                    _closeRequestPending = false;
                    retry = true;
                }
            }
            try { timer.Dispose(); } catch { }
            if (!retry) return;
            LogManager.Log("event=loot_panel_exact_close_completion_timeout");
            ContinueExactClose(binding);
        }

        private void CompleteExactCloseAttempt(Binding binding, int generation, bool closed)
        {
            lock (_sync)
            {
                if (_disposed || !ReferenceEquals(_active, binding) || !IsCloseState(_state)
                    || !_closeRequestPending || _closeAttemptGeneration != generation) return;
                _closeRequestPending = false;
                CancelCloseRetryLocked();
            }
            if (!closed)
                LogManager.Log("event=loot_panel_exact_close_completion_failed");
            ContinueExactClose(binding);
        }

        private void ContinueExactClose(Binding binding)
        {
            bool posted;
            lock (_sync)
            {
                if (_disposed || !ReferenceEquals(_active, binding) || !IsCloseState(_state))
                    return;
                posted = _openPosted;
            }
            bool stillExact = _panel != null
                && string.Equals(_panel.ActivePanelName, PanelName, StringComparison.Ordinal)
                && string.Equals(_panel.ActivePanelInstanceId, binding.PanelInstanceId,
                    StringComparison.Ordinal);
            if (posted && !stillExact)
            {
                FinalizeDetached(binding, true);
                return;
            }
            ScheduleExactCloseRetry(binding);
        }

        private void ScheduleExactCloseRetry(Binding binding)
        {
            Timer timer = null;
            timer = new Timer(delegate { OnCloseRetry(binding, timer); }, null,
                Timeout.Infinite, Timeout.Infinite);
            bool armed = false;
            lock (_sync)
            {
                if (!_disposed && ReferenceEquals(_active, binding) && IsCloseState(_state)
                    && !_closeRequestPending)
                {
                    CancelCloseRetryLocked();
                    _closeRetryTimer = timer;
                    timer.Change(CloseRetryDelayLocked(), Timeout.Infinite);
                    armed = true;
                }
            }
            if (!armed) timer.Dispose();
        }

        private void OnCloseRetry(Binding binding, Timer timer)
        {
            bool retry = false;
            lock (_sync)
            {
                if (!_disposed && ReferenceEquals(_closeRetryTimer, timer)
                    && ReferenceEquals(_active, binding) && IsCloseState(_state)
                    && !_closeRequestPending)
                {
                    _closeRetryTimer = null;
                    retry = true;
                }
            }
            try { timer.Dispose(); } catch { }
            if (retry) QueueExactClose(binding);
        }

        private int CloseRetryDelayLocked()
        {
            int shifts = Math.Min(Math.Max(_closeAttemptCount - 1, 0), 8);
            long delay = (long)_closeRetryDelayMs << shifts;
            return (int)Math.Min(delay, _closeRetryMaximumMs);
        }

        private bool IsCloseAttemptOwned(Binding binding)
        {
            lock (_sync)
            {
                return !_disposed && ReferenceEquals(_active, binding) && IsCloseState(_state)
                    && (_closeRequestPending || _closeRetryTimer != null);
            }
        }

        private static bool IsCloseState(BindingState state)
        {
            return state == BindingState.TerminalCloseQueued
                || state == BindingState.SuspendedCloseQueued
                || state == BindingState.ForceDetachQueued;
        }

        private void FinalizeDetached(Binding binding, bool releasePause)
        {
            bool notify = false;
            lock (_sync)
            {
                if (_disposed || !ReferenceEquals(_active, binding)
                    || _state == BindingState.PauseReleasePending) return;
                if (ReferenceEquals(_recoveryInFlightBinding, binding))
                {
                    // Recovery is an external, binding-scoped transport write.  A concurrent
                    // native close proof may arrive while it is blocked, but the old binding must
                    // remain owned until that exact delegate returns; otherwise a fresh same-triple
                    // attempt could be admitted before the old recovery frame is emitted.
                    _deferredFinalizePending = true;
                    _deferredFinalizeReleasePause |= releasePause;
                    return;
                }
                CancelBindWatchdogLocked();
                CancelCloseRetryLocked();
                CancelPauseReleaseRetryLocked();
                _openExecutionStarted = false;
                _openPosted = false;
                _closeRequestPending = false;
                ClearRewardInboxReplacementLocked();
                if (releasePause)
                {
                    _state = BindingState.PauseReleasePending;
                }
                else
                {
                    _active = null;
                    _state = BindingState.Idle;
                    _recoverySignalAttempted = false;
                }
                notify = true;
            }
            if (notify) NotifyDetached();
            if (releasePause) TryCompletePauseRelease(binding);
        }

        private void TryCompletePauseRelease(Binding binding)
        {
            lock (_sync)
            {
                if (_disposed || !ReferenceEquals(_active, binding)
                    || _state != BindingState.PauseReleasePending) return;
            }

            // webPanelUnpause is global and unscoped. An idle read followed by a socket write has
            // a TOCTOU window, so reserve an exact PanelHost idle fence across the external write.
            // Enqueue paths fail closed while the fence is held; the callback runs outside the
            // PanelHost queue lock and therefore cannot re-enter or invert that lock.
            string fenceToken = "loot.pause." + binding.PanelInstanceId;
            bool fenceAcquired = false;
            try { fenceAcquired = _panel != null && _panel.TryAcquireIdleFence(fenceToken); }
            catch (Exception ex)
            {
                LogManager.Log("event=loot_pause_idle_fence_failed type=" + ex.GetType().Name);
            }
            if (!fenceAcquired)
            {
                SchedulePauseReleaseRetry(binding);
                return;
            }

            bool released = _releasePause == null;
            try
            {
                if (_releasePause != null)
                {
                    try { released = _releasePause(); }
                    catch (Exception ex)
                    {
                        released = false;
                        LogManager.Log("event=loot_pause_release_failed type=" + ex.GetType().Name);
                    }
                }
            }
            finally
            {
                try { _panel.ReleaseIdleFenceExact(fenceToken); }
                catch (Exception ex)
                {
                    LogManager.Log("event=loot_pause_idle_fence_release_failed type="
                        + ex.GetType().Name);
                }
            }
            if (released)
            {
                bool settled = false;
                lock (_sync)
                {
                    if (_disposed || !ReferenceEquals(_active, binding)
                        || _state != BindingState.PauseReleasePending) return;
                    CancelPauseReleaseRetryLocked();
                    _active = null;
                    _state = BindingState.Idle;
                    _recoverySignalAttempted = false;
                    settled = true;
                }
                if (settled) NotifySettled(binding);
                return;
            }
            LogManager.Log("event=loot_pause_release_retry_pending");
            SchedulePauseReleaseRetry(binding);
        }

        /// <summary>
        /// Detached authority settlement can unblock a pause release that previously failed its
        /// LootTask fence. Only the exact coordinator-owned PauseReleasePending binding may retry;
        /// Idle/open states are deliberate no-ops, and the actual global write still runs behind
        /// PanelHost's idle fence in TryCompletePauseRelease.
        /// </summary>
        public bool OnDetachedReconcileSettled()
        {
            Binding binding;
            lock (_sync)
            {
                if (_disposed || _state != BindingState.PauseReleasePending
                    || _active == null) return false;
                binding = _active;
            }
            TryCompletePauseRelease(binding);
            return true;
        }

        private void SchedulePauseReleaseRetry(Binding binding)
        {
            Timer timer = null;
            timer = new Timer(delegate { OnPauseReleaseRetry(binding, timer); }, null,
                Timeout.Infinite, Timeout.Infinite);
            bool armed = false;
            lock (_sync)
            {
                if (!_disposed && ReferenceEquals(_active, binding)
                    && _state == BindingState.PauseReleasePending
                    && _pauseReleaseRetryTimer == null)
                {
                    _pauseReleaseRetryTimer = timer;
                    timer.Change(_pauseReleaseRetryMs, Timeout.Infinite);
                    armed = true;
                }
            }
            if (!armed) timer.Dispose();
        }

        private void OnPauseReleaseRetry(Binding binding, Timer timer)
        {
            bool retry = false;
            lock (_sync)
            {
                if (!_disposed && ReferenceEquals(_pauseReleaseRetryTimer, timer)
                    && ReferenceEquals(_active, binding)
                    && _state == BindingState.PauseReleasePending)
                {
                    _pauseReleaseRetryTimer = null;
                    retry = true;
                }
            }
            try { timer.Dispose(); } catch { }
            if (retry) TryCompletePauseRelease(binding);
        }

        private void TrySignalRecoveryOnce(Binding binding, string reason)
        {
            if (reason != "web_mount_failed" && reason != "web_open_failed") return;
            bool invokeRecovery;
            lock (_sync)
            {
                // Claim the at-most-once slot before invoking external transport: a failed send
                // may synchronously fire disconnect handlers that re-enter ForceDetach.  The
                // production delegate fails closed by disconnecting only its captured generation,
                // so false means "socket-detach proof now owns authority convergence", not
                // "retry later".
                if (_disposed || !ReferenceEquals(_active, binding)
                    || AuthorityCloseStateLocked(binding) != BindingState.Idle
                    || _recoverySignalAttempted) return;
                _recoverySignalAttempted = true;
                invokeRecovery = _requestRecovery != null;
                if (invokeRecovery) _recoveryInFlightBinding = binding;
            }
            if (!invokeRecovery) return;
            bool sent = false;
            try { sent = _requestRecovery(binding, reason); }
            catch (Exception ex)
            {
                LogManager.Log("event=loot_panel_recovery_signal_failed type="
                    + ex.GetType().Name);
            }
            finally
            {
                CompleteRecoverySignal(binding);
            }
            LogManager.Log("event=loot_panel_recovery_signal reason=" + reason
                + " sent=" + (sent ? "1" : "0"));
        }

        private void CompleteRecoverySignal(Binding binding)
        {
            bool finalize = false;
            bool releasePause = false;
            lock (_sync)
            {
                if (!ReferenceEquals(_recoveryInFlightBinding, binding)) return;
                _recoveryInFlightBinding = null;
                if (_deferredFinalizePending && ReferenceEquals(_active, binding))
                {
                    finalize = true;
                    releasePause = _deferredFinalizeReleasePause;
                }
                _deferredFinalizePending = false;
                _deferredFinalizeReleasePause = false;
            }
            if (finalize) FinalizeDetached(binding, releasePause);
        }

        private static string RecoveryReasonForDetach(string reason)
        {
            if (reason == "web_mount_failed") return "web_mount_failed";
            if (reason == "web_navigation" || reason == "panel_host_closed")
                return "web_open_failed";
            return null;
        }

        private BindingState AuthorityCloseStateLocked(Binding binding)
        {
            if (binding == null
                || !string.Equals(_authorityVisualCloseProvenPanelInstanceId,
                    binding.PanelInstanceId, StringComparison.Ordinal)) return BindingState.Idle;
            return CloseStateForReason(_authorityVisualCloseProvenReason);
        }

        private void CancelBindWatchdogLocked()
        {
            DisposeTimerLocked(ref _bindWatchdog);
        }

        private void CancelCloseRetryLocked()
        {
            DisposeTimerLocked(ref _closeRetryTimer);
        }

        private void CancelPauseReleaseRetryLocked()
        {
            DisposeTimerLocked(ref _pauseReleaseRetryTimer);
        }

        private static void DisposeTimerLocked(ref Timer timer)
        {
            Timer captured = timer;
            timer = null;
            if (captured != null)
            {
                try { captured.Dispose(); } catch { }
            }
        }

        /// <summary>
        /// Host-teardown-only cancellation. Runtime callers must invoke ForceDetach first; Dispose
        /// deliberately does not send recovery/close/unpause after its external dependencies may
        /// already be shutting down. Program's early-shutdown path follows that ordering.
        /// </summary>
        public void Dispose()
        {
            lock (_sync)
            {
                if (_disposed) return;
                _disposed = true;
                CancelBindWatchdogLocked();
                CancelCloseRetryLocked();
                CancelPauseReleaseRetryLocked();
                _active = null;
                _state = BindingState.Idle;
                _openExecutionStarted = false;
                _openPosted = false;
                _recoverySignalAttempted = false;
                _recoveryInFlightBinding = null;
                _deferredFinalizePending = false;
                _deferredFinalizeReleasePause = false;
                _closeRequestPending = false;
                ClearRewardInboxReplacementLocked();
                BindingDetached = null;
                BindingSettled = null;
                _rewardInboxReturnHandler = null;
            }
        }

        private bool IsRewardInboxReplacementPendingLocked(
            string panelInstanceId)
        {
            return !_disposed
                && _active != null
                && _active.SourceKind == RewardInboxSource
                && IsCloseState(_state)
                && string.Equals(
                    _active.PanelInstanceId,
                    panelInstanceId,
                    StringComparison.Ordinal)
                && string.Equals(
                    _rewardInboxReplacementPendingPanelInstanceId,
                    panelInstanceId,
                    StringComparison.Ordinal)
                && !string.IsNullOrEmpty(
                    _rewardInboxReplacementPendingReason);
        }

        private void ClearRewardInboxReplacementLocked()
        {
            _rewardInboxReplacementPendingPanelInstanceId = null;
            _rewardInboxReplacementPendingReason = null;
        }


        private static bool MatchesLocked(Binding binding, string panelInstanceId,
            string chestSessionId, string lootContainerId, int containerEpoch)
        {
            return binding != null
                && string.Equals(binding.PanelInstanceId, panelInstanceId, StringComparison.Ordinal)
                && string.Equals(binding.ChestSessionId, chestSessionId, StringComparison.Ordinal)
                && string.Equals(binding.LootContainerId, lootContainerId, StringComparison.Ordinal)
                && binding.ContainerEpoch == containerEpoch;
        }

        public static bool TryNormalizePanelRequest(JObject request, out OpenRequest normalized,
            out string error)
        {
            normalized = null;
            error = "invalid_request";
            bool exactBody = HasExactKeys(request, "panel", "source", "initData");
            bool exactSocketEnvelope = HasExactKeys(request, "task", "panel", "source", "initData")
                && request.Value<string>("task") == "panel_request";
            if (request == null || (!exactBody && !exactSocketEnvelope))
                return false;
            if (request.Value<string>("panel") != PanelName) return false;
            string source = request.Value<string>("source");
            bool isMapChest = source == MapChestSource;
            bool isStageSettlement = source == StageSettlementSource;
            if (!isMapChest && !isStageSettlement) return false;
            JObject init = request["initData"] as JObject;
            if (isMapChest)
            {
                if (!HasExactKeys(init, "v", "chestSessionId", "lootContainerId",
                    "containerEpoch", "openAttemptSeq", "displayName", "capacity",
                    "columns")) return false;
            }
            else if (!HasExactKeys(init, "v", "chestSessionId", "lootContainerId",
                "containerEpoch", "openAttemptSeq", "displayName", "capacity",
                "columns", "sourceKind", "report")
                || init.Value<string>("sourceKind") != StageSettlementSource)
            {
                return false;
            }
            int version;
            int epoch;
            int openAttemptSeq;
            int capacity;
            int columns;
            string chestSessionId;
            string lootContainerId;
            string displayName;
            if (!TryReadInteger(init["v"], 1, 1, out version)
                || !TryReadOpaque(init["chestSessionId"], out chestSessionId)
                || !TryReadOpaque(init["lootContainerId"], out lootContainerId)
                || !TryReadInteger(init["containerEpoch"], 1, int.MaxValue, out epoch)
                || !TryReadInteger(init["openAttemptSeq"], 1, int.MaxValue,
                    out openAttemptSeq)
                || !TryReadDisplayName(init["displayName"], out displayName)
                || !TryReadInteger(init["capacity"], 1, 64, out capacity)
                || !TryReadInteger(init["columns"], 1, 8, out columns)
                || columns > capacity) return false;
            JObject settlementReport = null;
            if (isStageSettlement
                && !TryNormalizeSettlementReport(
                    init["report"] as JObject, out settlementReport))
                return false;
            normalized = new OpenRequest
            {
                ChestSessionId = chestSessionId,
                LootContainerId = lootContainerId,
                ContainerEpoch = epoch,
                OpenAttemptSeq = openAttemptSeq,
                DisplayName = displayName,
                Capacity = capacity,
                Columns = columns,
                SourceKind = source,
                SettlementReport = settlementReport
            };
            error = null;
            return true;
        }

        internal static bool TryNormalizeSettlementReport(
            JObject report, out JObject normalized)
        {
            normalized = null;
            if (!HasExactKeys(report, "v", "runId", "stageName", "difficulty",
                    "outcome", "activeFrames", "totalKills", "omittedKillTypes",
                    "totalItemGains", "totalItemLosses", "omittedItemFlowTypes",
                    "rewardRollOmissions", "kills", "itemFlows"))
                return false;
            int version;
            string runId;
            string stageName;
            string difficulty;
            string outcome;
            long activeFrames;
            long totalKills;
            long omittedKillTypes;
            long totalItemGains;
            long totalItemLosses;
            long omittedItemFlowTypes;
            long rewardRollOmissions;
            if (!TryReadInteger(report["v"], 1, 1, out version)
                || !TryReadOpaque(report["runId"], out runId)
                || !TryReadBoundedText(report["stageName"], 96, false, out stageName)
                || !TryReadBoundedText(report["difficulty"], 48, false, out difficulty)
                || !TryReadOutcome(report["outcome"], out outcome)
                || !TryReadLong(report["activeFrames"], 0, 9007199254740991L,
                    out activeFrames)
                || !TryReadLong(report["totalKills"], 0, 9007199254740991L,
                    out totalKills)
                || !TryReadLong(report["omittedKillTypes"], 0, 9007199254740991L,
                    out omittedKillTypes)
                || !TryReadLong(report["totalItemGains"], 0, 9007199254740991L,
                    out totalItemGains)
                || !TryReadLong(report["totalItemLosses"], 0, 9007199254740991L,
                    out totalItemLosses)
                || !TryReadLong(report["omittedItemFlowTypes"], 0,
                    9007199254740991L, out omittedItemFlowTypes)
                || !TryReadLong(report["rewardRollOmissions"], 0, 9007199254740991L,
                    out rewardRollOmissions))
                return false;

            JArray kills = report["kills"] as JArray;
            if (kills == null || kills.Count > 96) return false;
            JArray normalizedKills = new JArray();
            long projectedKills = 0;
            for (int i = 0; i < kills.Count; i++)
            {
                JObject kill;
                long count;
                if (!TryNormalizeSettlementKill(kills[i] as JObject, out kill, out count))
                    return false;
                if (projectedKills > 9007199254740991L - count) return false;
                projectedKills += count;
                normalizedKills.Add(kill);
            }
            if (projectedKills > totalKills) return false;

            JArray itemFlows = report["itemFlows"] as JArray;
            if (itemFlows == null || itemFlows.Count > 96) return false;
            JArray normalizedItemFlows = new JArray();
            long projectedGains = 0;
            long projectedLosses = 0;
            for (int i = 0; i < itemFlows.Count; i++)
            {
                JObject flow;
                long count;
                bool gain;
                if (!TryNormalizeSettlementItemFlow(itemFlows[i] as JObject,
                        out flow, out count, out gain))
                    return false;
                if (gain)
                {
                    if (projectedGains > 9007199254740991L - count) return false;
                    projectedGains += count;
                    if (projectedGains > totalItemGains) return false;
                }
                else
                {
                    if (projectedLosses > 9007199254740991L - count) return false;
                    projectedLosses += count;
                    if (projectedLosses > totalItemLosses) return false;
                }
                normalizedItemFlows.Add(flow);
            }

            normalized = new JObject
            {
                ["v"] = 1,
                ["runId"] = runId,
                ["stageName"] = stageName,
                ["difficulty"] = difficulty,
                ["outcome"] = outcome,
                ["activeFrames"] = activeFrames,
                ["totalKills"] = totalKills,
                ["omittedKillTypes"] = omittedKillTypes,
                ["totalItemGains"] = totalItemGains,
                ["totalItemLosses"] = totalItemLosses,
                ["omittedItemFlowTypes"] = omittedItemFlowTypes,
                ["rewardRollOmissions"] = rewardRollOmissions,
                ["kills"] = normalizedKills,
                ["itemFlows"] = normalizedItemFlows
            };
            return true;
        }

        internal static bool TryNormalizeRewardAuthority(
            JObject authority,
            out OpenRequest normalized,
            out string error)
        {
            normalized = null;
            error = "invalid_reward_authority";
            if (!HasExactKeys(
                    authority,
                    "sourceKind", "chestSessionId", "lootContainerId",
                    "containerEpoch", "openAttemptSeq", "displayName",
                    "authorityRevision", "state", "remainingCount",
                    "capacity", "columns")
                || authority.Value<string>("sourceKind") != RewardInboxSource
                || authority.Value<string>("state") != "LOOT_ACTIVE")
            {
                return false;
            }
            int epoch;
            int openAttemptSeq;
            int authorityRevision;
            int remainingCount;
            int capacity;
            int columns;
            string chestSessionId;
            string lootContainerId;
            string displayName;
            if (!TryReadOpaque(
                    authority["chestSessionId"], out chestSessionId)
                || !TryReadOpaque(
                    authority["lootContainerId"], out lootContainerId)
                || !TryReadInteger(
                    authority["containerEpoch"], 1, int.MaxValue, out epoch)
                || !TryReadInteger(
                    authority["openAttemptSeq"], 1, int.MaxValue,
                    out openAttemptSeq)
                || !TryReadDisplayName(
                    authority["displayName"], out displayName)
                || displayName != "待领取物品"
                || !TryReadInteger(
                    authority["authorityRevision"],
                    0,
                    int.MaxValue,
                    out authorityRevision)
                || !TryReadInteger(
                    authority["remainingCount"], 1, 64, out remainingCount)
                || !TryReadInteger(
                    authority["capacity"], 1, 64, out capacity)
                || remainingCount > capacity
                || !TryReadInteger(
                    authority["columns"], 1, 8, out columns)
                || columns != Math.Min(8, capacity))
            {
                return false;
            }
            normalized = new OpenRequest
            {
                ChestSessionId = chestSessionId,
                LootContainerId = lootContainerId,
                ContainerEpoch = epoch,
                OpenAttemptSeq = openAttemptSeq,
                DisplayName = displayName,
                Capacity = capacity,
                Columns = columns,
                SourceKind = RewardInboxSource,
                SettlementReport = null
            };
            error = null;
            return true;
        }

        private static bool TryNormalizeSettlementItemFlow(
            JObject value, out JObject normalized, out long count, out bool gain)
        {
            normalized = null;
            count = 0;
            gain = false;
            if (!HasExactKeys(value, "direction", "kind", "itemKey", "displayName",
                    "iconName", "tier", "source", "reason", "count"))
                return false;
            string direction;
            string kind;
            string itemKey;
            string displayName;
            string iconName;
            string tier;
            string source;
            string reason;
            if (!TryReadBoundedText(value["direction"], 4, false, out direction)
                || (direction != "gain" && direction != "loss")
                || !TryReadBoundedText(value["kind"], 16, false, out kind)
                || !IsSettlementAssetKind(kind)
                || !TryReadBoundedText(value["itemKey"], 128, false, out itemKey)
                || !TryReadBoundedText(value["displayName"], 96, false,
                    out displayName)
                || !TryReadBoundedText(value["iconName"], 128, true, out iconName)
                || !TryReadBoundedText(value["tier"], 48, true, out tier)
                || !TryReadBoundedText(value["source"], 48, false, out source)
                || !TryReadBoundedText(value["reason"], 64, true, out reason)
                || !TryReadLong(value["count"], 1, 9007199254740991L, out count))
                return false;
            gain = direction == "gain";
            normalized = new JObject
            {
                ["direction"] = direction,
                ["kind"] = kind,
                ["itemKey"] = itemKey,
                ["displayName"] = displayName,
                ["iconName"] = iconName,
                ["tier"] = tier,
                ["source"] = source,
                ["reason"] = reason,
                ["count"] = count
            };
            return true;
        }

        private static bool IsSettlementAssetKind(string kind)
        {
            return kind == "money" || kind == "kpoint" || kind == "intel"
                || kind == "material" || kind == "item" || kind == "equip";
        }

        private static bool TryNormalizeSettlementKill(
            JObject value, out JObject normalized, out long count)
        {
            normalized = null;
            count = 0;
            if (!HasExactKeys(value, "key", "displayName", "iconName", "doll",
                    "eliteLevel", "count"))
                return false;
            string key;
            string displayName;
            string iconName;
            int eliteLevel;
            if (!TryReadBoundedText(value["key"], 128, false, out key)
                || !TryReadBoundedText(value["displayName"], 96, false,
                    out displayName)
                || !TryReadBoundedText(value["iconName"], 128, true, out iconName)
                || !TryReadInteger(value["eliteLevel"], 0, 16, out eliteLevel)
                || !TryReadLong(value["count"], 1, 9007199254740991L, out count))
                return false;

            JObject doll = null;
            if (value["doll"] == null || value["doll"].Type == JTokenType.Null)
            {
                doll = null;
            }
            else if (!TryNormalizeSettlementDoll(value["doll"] as JObject, out doll))
            {
                return false;
            }
            normalized = new JObject
            {
                ["key"] = key,
                ["displayName"] = displayName,
                ["iconName"] = iconName,
                ["doll"] = doll != null ? (JToken)doll : JValue.CreateNull(),
                ["eliteLevel"] = eliteLevel,
                ["count"] = count
            };
            return true;
        }

        private static bool TryNormalizeSettlementDoll(
            JObject value, out JObject normalized)
        {
            normalized = null;
            string[] keys =
            {
                "face", "hair", "mask", "head", "body", "leg", "hand",
                "foot", "neck", "gender"
            };
            if (!HasExactKeys(value, keys)) return false;
            JObject result = new JObject();
            for (int i = 0; i < keys.Length; i++)
            {
                string text;
                if (!TryReadBoundedText(value[keys[i]], 128, true, out text))
                    return false;
                result[keys[i]] = text;
            }
            normalized = result;
            return true;
        }

        public static bool IsOpaque(string value)
        {
            if (string.IsNullOrEmpty(value) || value.Length > MaximumOpaqueLength) return false;
            for (int i = 0; i < value.Length; i++)
            {
                char c = value[i];
                bool allowed = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')
                    || (c >= '0' && c <= '9') || c == '.' || c == '_' || c == '~' || c == '-';
                if (!allowed) return false;
            }
            return true;
        }

        private static bool TryReadOpaque(JToken token, out string value)
        {
            value = token != null && token.Type == JTokenType.String ? token.Value<string>() : null;
            return IsOpaque(value);
        }

        private static bool TryReadDisplayName(JToken token, out string value)
        {
            value = token != null && token.Type == JTokenType.String ? token.Value<string>() : null;
            if (string.IsNullOrWhiteSpace(value) || value.Length > 48) return false;
            for (int i = 0; i < value.Length; i++) if (char.IsControl(value[i])) return false;
            return true;
        }

        private static bool TryReadBoundedText(
            JToken token, int maximumLength, bool allowEmpty, out string value)
        {
            value = token != null && token.Type == JTokenType.String
                ? token.Value<string>() : null;
            if (value == null || value.Length > maximumLength
                    || (!allowEmpty && value.Length == 0))
                return false;
            for (int i = 0; i < value.Length; i++)
                if (char.IsControl(value[i])) return false;
            return true;
        }

        private static bool TryReadOutcome(JToken token, out string value)
        {
            value = token != null && token.Type == JTokenType.String
                ? token.Value<string>() : null;
            return value == "victory" || value == "failure" || value == "retreat";
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

        private static bool TryReadLong(JToken token, long min, long max, out long value)
        {
            value = 0;
            if (token == null || token.Type != JTokenType.Integer) return false;
            try { value = token.Value<long>(); }
            catch (Exception) { return false; }
            return value >= min && value <= max;
        }

        private static bool HasExactKeys(JObject value, params string[] expected)
        {
            if (value == null || value.Count != expected.Length) return false;
            foreach (string key in expected) if (value.Property(key) == null) return false;
            return true;
        }

        private static string BuildOpenAck(bool accepted, string error)
        {
            JObject ack = new JObject
            {
                ["success"] = accepted,
                ["accepted"] = accepted,
                ["bound"] = false,
                ["panel"] = PanelName
            };
            if (!accepted) ack["error"] = error ?? "open_rejected";
            return ack.ToString(Formatting.None);
        }

        private static string SafeReason(string reason)
        {
            switch (reason)
            {
                case "socket_disconnected":
                case "web_navigation":
                case "web_mount_failed":
                case "host_shutdown":
                case "panel_host_closed":
                    return reason;
                default:
                    return "other";
            }
        }
    }
}
