using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Security.Cryptography;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.AgentRuntime.Input;

namespace CF7Launcher.AgentRuntime.NativeInput
{
    internal sealed class ExternalInputObservation
    {
        internal ExternalInputObservation(
            long sequence,
            string reasonCode,
            long foregroundWindowHandle = 0,
            string controlId = null,
            NativeControlTransition transition =
                NativeControlTransition.None)
        {
            if (sequence <= 0)
            {
                throw new ArgumentOutOfRangeException(
                    nameof(sequence));
            }
            Sequence = sequence;
            ReasonCode = string.IsNullOrWhiteSpace(reasonCode)
                ? "external_input"
                : reasonCode;
            ForegroundWindowHandle = foregroundWindowHandle;
            ControlId = controlId;
            Transition = transition;
        }

        internal long Sequence { get; }
        internal string ReasonCode { get; }
        internal long ForegroundWindowHandle { get; }
        internal string ControlId { get; }
        internal NativeControlTransition Transition { get; }
    }

    internal interface IExternalInputObservationSource
    {
        event Action<ExternalInputObservation>
            ExternalInputObserved;

        long ObservedExternalInputSequence { get; }

        bool IsExactForegroundWindow(long windowHandle);

        Task<long> SealTrustedHumanInteractionAsync(
            CancellationToken cancellationToken);
    }

    /// <summary>
    /// Owns the per-runtime native injection tag and translates the global
    /// low-level hook stream into exact-runtime events or external
    /// preemption. Hook callbacks only perform bounded checks and queue
    /// revocation/cleanup work to a dedicated worker.
    /// </summary>
    public sealed class NativeInputGuard
        : IDisposable,
          IExternalInputObservationSource
    {
        private static readonly TimeSpan HeartbeatMaximumAge =
            TimeSpan.FromMilliseconds(
                InputSafetyStateMachine
                    .GuardHeartbeatMaximumAgeMilliseconds);
        private static readonly TimeSpan HookRefreshTimeout =
            TimeSpan.FromMilliseconds(250);
        private static readonly TimeSpan HookObservationTimeout =
            TimeSpan.FromMilliseconds(250);
        private static readonly TimeSpan
            TrustedHumanInteractionSealTimeout =
                TimeSpan.FromSeconds(2);
        private static readonly TimeSpan
            TrustedHumanInteractionPollInterval =
                TimeSpan.FromMilliseconds(10);

        private readonly object _sync = new object();
        private readonly InputSafetyStateMachine _safety;
        private readonly INativeInputWin32Facade _win32;
        private readonly INativeInputPreemptionSink _preemptionSink;
        private readonly INativeLowLevelHookSession _hookSession;
        private readonly ConcurrentQueue<PreemptionWork> _preemptionQueue =
            new ConcurrentQueue<PreemptionWork>();
        private readonly AutoResetEvent _preemptionSignal =
            new AutoResetEvent(false);
        private readonly Thread _preemptionThread;
        private readonly Timer _watchdog;
        private readonly HashSet<string> _externalControlsDown =
            new HashSet<string>(StringComparer.Ordinal);
        private readonly Dictionary<string, NativeInputPacket> _ownedReleases =
            new Dictionary<string, NativeInputPacket>(
                StringComparer.Ordinal);
        private readonly List<string> _ownedDownOrder =
            new List<string>();
        private readonly HashSet<string> _cleanupControls =
            new HashSet<string>(StringComparer.Ordinal);
        private ActiveBatch _activeBatch;
        private string _boundSessionId;
        private string _boundLeaseId;
        private bool _cleanupInProgress;
        private bool _guardUnhealthyLatched;
        private bool _requiresHookRefresh;
        private bool _claimHealthFailurePending;
        private bool _disposed;
        private long _guardObservationStartedMonotonic;
        private long _lastExternalObservedMonotonic =
            long.MinValue;
        private long _externalInputSequence;
        // A fence mismatch is human evidence only when every newer input
        // was physical. Preserve the highest foreign-injected sequence so
        // the synchronous claim cannot overstate evidence before its worker
        // notification arrives.
        private long _lastOtherInjectedInputSequence;
        private long _deliveredExternalInputSequence;

        public NativeInputGuard(
            InputSafetyStateMachine safety,
            INativeInputWin32Facade win32,
            INativeInputPreemptionSink preemptionSink)
            : this(safety, win32, preemptionSink, true)
        {
        }

        internal NativeInputGuard(
            InputSafetyStateMachine safety,
            INativeInputWin32Facade win32,
            INativeInputPreemptionSink preemptionSink,
            bool startWatchdog)
        {
            _safety = safety
                ?? throw new ArgumentNullException(nameof(safety));
            _win32 = win32
                ?? throw new ArgumentNullException(nameof(win32));
            _preemptionSink = preemptionSink
                ?? throw new ArgumentNullException(
                    nameof(preemptionSink));
            RuntimeInjectionTag = CreateRuntimeInjectionTag();
            _guardObservationStartedMonotonic =
                _win32.MonotonicMilliseconds;

            _preemptionThread = new Thread(PreemptionWorker)
            {
                IsBackground = true,
                Name = "CF7 Agent native-input cleanup"
            };
            _preemptionThread.Start();

            try
            {
                _hookSession = _win32.InstallLowLevelHooks(
                    RuntimeInjectionTag,
                    OnLowLevelHookEvent);
            }
            catch
            {
                _hookSession = null;
            }

            if (startWatchdog)
            {
                _watchdog = new Timer(
                    _ => PollHookHealth(false),
                    null,
                    TimeSpan.FromMilliseconds(100),
                    TimeSpan.FromMilliseconds(100));
            }

            PollHookHealth(false);
        }

        internal ulong RuntimeInjectionTag { get; }

        /// <summary>
        /// Raised from the bounded preemption worker, never from the low-level
        /// hook callback, when non-runtime keyboard or pointer input has
        /// preempted ownership. Trusted in-process coordinators use this to
        /// revoke their whole short-lived connection, not merely a lease that
        /// may not have been acquired yet.
        /// </summary>
        internal event Action<ExternalInputObservation>
            ExternalInputObserved;

        event Action<ExternalInputObservation>
            IExternalInputObservationSource.ExternalInputObserved
        {
            add => ExternalInputObserved += value;
            remove => ExternalInputObserved -= value;
        }

        long IExternalInputObservationSource
            .ObservedExternalInputSequence
        {
            get
            {
                lock (_sync)
                    return _externalInputSequence;
            }
        }

        internal long CaptureExternalInputSequence()
        {
            lock (_sync)
                return _externalInputSequence;
        }

        internal bool TryClaimExternalInputSequence(
            long expectedSequence)
        {
            return TryClaimExternalInputSequence(
                expectedSequence,
                out _);
        }

        internal bool TryClaimExternalInputSequence(
            long expectedSequence,
            out string reasonCode)
        {
            lock (_sync)
            {
                if (_disposed
                    || expectedSequence < 0
                    || _guardUnhealthyLatched
                    || _requiresHookRefresh)
                {
                    reasonCode = "input_guard_unhealthy";
                    return false;
                }
                try
                {
                    if (_hookSession == null
                        || !_hookSession.IsHealthy(
                            HeartbeatMaximumAge))
                    {
                        _requiresHookRefresh = true;
                        _claimHealthFailurePending = true;
                        reasonCode = "input_guard_unhealthy";
                        return false;
                    }
                }
                catch
                {
                    _requiresHookRefresh = true;
                    _claimHealthFailurePending = true;
                    reasonCode = "input_guard_unhealthy";
                    return false;
                }
                if (_externalInputSequence
                    != expectedSequence)
                {
                    reasonCode =
                        _lastOtherInjectedInputSequence
                            > expectedSequence
                            ? "external_input"
                            : "human_input";
                    return false;
                }
                reasonCode = null;
                return true;
            }
        }

        internal void PreemptClaimHealthFailureIfAny()
        {
            bool mustPreempt;
            lock (_sync)
            {
                mustPreempt = _claimHealthFailurePending;
                _claimHealthFailurePending = false;
            }
            if (mustPreempt)
            {
                FailAndPreempt(
                    "input_guard_unhealthy");
            }
        }

        internal bool TryAuthorizeShutdownLease(
            out string reasonCode)
        {
            bool refreshRequired;
            lock (_sync)
            {
                if (_disposed)
                {
                    reasonCode = "input_guard_unhealthy";
                    return false;
                }
                refreshRequired = _requiresHookRefresh;
            }
            if (!PollHookHealth(refreshRequired))
            {
                reasonCode = "input_guard_unhealthy";
                return false;
            }
            if (!HasRequiredQuiescence(out reasonCode))
                return false;
            lock (_sync)
            {
                if (_disposed
                    || _guardUnhealthyLatched
                    || _requiresHookRefresh)
                {
                    reasonCode = "input_guard_unhealthy";
                    return false;
                }
                if (_deliveredExternalInputSequence
                    < _externalInputSequence)
                {
                    reasonCode = "input_not_quiescent";
                    return false;
                }
                reasonCode = null;
                return true;
            }
        }

        bool IExternalInputObservationSource
            .IsExactForegroundWindow(long windowHandle)
        {
            if (windowHandle == 0)
                return false;
            try
            {
                return _win32.GetForegroundWindow().ToInt64()
                    == windowHandle;
            }
            catch
            {
                return false;
            }
        }

        async Task<long> IExternalInputObservationSource
            .SealTrustedHumanInteractionAsync(
                CancellationToken cancellationToken)
        {
            return await SealTrustedHumanInteractionAsync(
                    cancellationToken)
                .ConfigureAwait(false);
        }

        internal async Task<long>
            SealTrustedHumanInteractionAsync(
                CancellationToken cancellationToken)
        {
            var elapsed = Stopwatch.StartNew();
            while (elapsed.Elapsed
                < TrustedHumanInteractionSealTimeout)
            {
                cancellationToken.ThrowIfCancellationRequested();
                ThrowIfDisposed();

                IReadOnlyCollection<string> asynchronouslyHeld;
                try
                {
                    asynchronouslyHeld = _win32
                        .GetAsyncHeldModifiersAndButtons()
                        ?? Array.Empty<string>();
                }
                catch
                {
                    throw new InvalidOperationException(
                        "input_guard_unhealthy");
                }

                long candidateSequence;
                long deliveredSequence;
                long lastObserved;
                bool trackedControlHeld;
                lock (_sync)
                {
                    candidateSequence = _externalInputSequence;
                    deliveredSequence =
                        _deliveredExternalInputSequence;
                    lastObserved = Math.Max(
                        _guardObservationStartedMonotonic,
                        _lastExternalObservedMonotonic);
                    trackedControlHeld =
                        _externalControlsDown.Count != 0;
                }

                long now = _win32.MonotonicMilliseconds;
                bool asyncControlHeld = asynchronouslyHeld.Any(
                    control =>
                        !string.IsNullOrWhiteSpace(control)
                        && !HasRuntimeOwnership(control));
                if (!trackedControlHeld
                    && !asyncControlHeld
                    && now >= lastObserved
                    && now - lastObserved
                        >= InputSafetyStateMachine
                            .QuiescenceMilliseconds
                    && deliveredSequence >= candidateSequence)
                {
                    // Recheck the sequence while holding the same lock used by
                    // the hook callback. An event observed after this fence is
                    // necessarily assigned a larger sequence and must
                    // preempt the operation.
                    lock (_sync)
                    {
                        if (!_disposed
                            && _externalControlsDown.Count == 0
                            && _externalInputSequence
                                == candidateSequence
                            && _deliveredExternalInputSequence
                                >= candidateSequence)
                        {
                            return candidateSequence;
                        }
                    }
                }

                await Task.Delay(
                        TrustedHumanInteractionPollInterval,
                        cancellationToken)
                    .ConfigureAwait(false);
            }

            throw new InvalidOperationException(
                "input_not_quiescent");
        }

        public void BindLease(string sessionId, string leaseId)
        {
            RequireValue(sessionId, nameof(sessionId));
            RequireValue(leaseId, nameof(leaseId));
            ThrowIfDisposed();
            bool refreshRequired;
            lock (_sync)
            {
                refreshRequired = _requiresHookRefresh;
            }
            if (!PollHookHealth(refreshRequired))
            {
                throw new InvalidOperationException(
                    "input_guard_unhealthy");
            }
            if (!HasRequiredQuiescence(
                    out string quiescenceReason))
            {
                throw new InvalidOperationException(
                    quiescenceReason);
            }

            lock (_sync)
            {
                if (_boundLeaseId != null
                    && (!string.Equals(
                            _boundSessionId,
                            sessionId,
                            StringComparison.Ordinal)
                        || !string.Equals(
                            _boundLeaseId,
                            leaseId,
                            StringComparison.Ordinal)))
                {
                    throw new InvalidOperationException(
                        "another_native_input_lease_is_bound");
                }
                _boundSessionId = sessionId;
                _boundLeaseId = leaseId;
            }
        }

        public void UnbindLease(string sessionId, string leaseId)
        {
            lock (_sync)
            {
                if (string.Equals(
                        _boundSessionId,
                        sessionId,
                        StringComparison.Ordinal)
                    && string.Equals(
                        _boundLeaseId,
                        leaseId,
                        StringComparison.Ordinal))
                {
                    _boundSessionId = null;
                    _boundLeaseId = null;
                }
            }
        }

        public void RevokeBoundLease(
            string sessionId,
            string leaseId,
            string reasonCode)
        {
            RequireValue(sessionId, nameof(sessionId));
            RequireValue(leaseId, nameof(leaseId));
            RequireValue(reasonCode, nameof(reasonCode));
            ThrowIfDisposed();
            lock (_sync)
            {
                if (!string.Equals(
                        _boundSessionId,
                        sessionId,
                        StringComparison.Ordinal)
                    || !string.Equals(
                        _boundLeaseId,
                        leaseId,
                        StringComparison.Ordinal))
                {
                    return;
                }
            }
            FailAndPreempt(reasonCode);
        }

        internal bool IsLeaseBound(string sessionId, string leaseId)
        {
            lock (_sync)
            {
                return string.Equals(
                        _boundSessionId,
                        sessionId,
                        StringComparison.Ordinal)
                    && string.Equals(
                        _boundLeaseId,
                        leaseId,
                        StringComparison.Ordinal);
            }
        }

        internal bool TryGetBoundLease(
            out string sessionId,
            out string leaseId)
        {
            lock (_sync)
            {
                sessionId = _boundSessionId;
                leaseId = _boundLeaseId;
                return sessionId != null && leaseId != null;
            }
        }

        internal bool TryPrepareForDispatch(
            out string reasonCode)
        {
            if (!PollHookHealth(false))
            {
                reasonCode = "input_guard_unhealthy";
                return false;
            }
            if (HasRequiredQuiescence(out reasonCode))
            {
                return true;
            }
            if (!string.Equals(
                    reasonCode,
                    "input_not_quiescent",
                    StringComparison.Ordinal))
            {
                FailAndPreempt(reasonCode);
            }
            return false;
        }

        internal bool HasRuntimeOwnership(string controlId)
        {
            lock (_sync)
            {
                return _ownedReleases.ContainsKey(controlId);
            }
        }

        internal void ObserveExternallyHeldControls(
            IEnumerable<string> controls)
        {
            foreach (string control in (controls
                ?? Array.Empty<string>())
                .Where(value => !string.IsNullOrWhiteSpace(value))
                .Distinct(StringComparer.Ordinal))
            {
                if (HasRuntimeOwnership(control))
                {
                    continue;
                }
                long externalInputSequence;
                lock (_sync)
                {
                    _externalControlsDown.Add(control);
                    _lastExternalObservedMonotonic =
                        _win32.MonotonicMilliseconds;
                    externalInputSequence =
                        ++_externalInputSequence;
                }
                InputPreemption preemption =
                    _safety.RecordExternalInput(
                        control,
                        true,
                        ExternalInputKind.HumanPhysical);
                long foregroundWindowHandle;
                try
                {
                    foregroundWindowHandle =
                        _win32.GetForegroundWindow()
                            .ToInt64();
                }
                catch
                {
                    foregroundWindowHandle = 0;
                }
                QueuePreemption(
                    preemption,
                    "human_input",
                    externalInputSequence,
                    foregroundWindowHandle,
                    control,
                    NativeControlTransition.Down);
            }
        }

        internal BatchHandle BeginBatch(
            IReadOnlyList<NativeInputPacket> packets,
            Func<NativeLowLevelHookEvent, string> validateAtHook)
        {
            if (packets == null || packets.Count == 0)
            {
                throw new ArgumentException(
                    "A non-empty input batch is required.",
                    nameof(packets));
            }
            if (validateAtHook == null)
            {
                throw new ArgumentNullException(nameof(validateAtHook));
            }

            lock (_sync)
            {
                ThrowIfDisposed();
                if (_activeBatch != null)
                {
                    throw new InvalidOperationException(
                        "native_input_batch_already_active");
                }
                var batch = new ActiveBatch(
                    packets.ToArray(),
                    validateAtHook);
                _activeBatch = batch;
                return new BatchHandle(this, batch);
            }
        }

        internal void FailAndPreempt(
            string reasonCode,
            ActiveBatch expectedBatch = null)
        {
            InputPreemption preemption;
            lock (_sync)
            {
                if (expectedBatch != null
                    && !ReferenceEquals(
                        expectedBatch,
                        _activeBatch))
                {
                    return;
                }
                if (_activeBatch != null)
                {
                    _activeBatch.Block(reasonCode);
                }
                if (string.Equals(
                        reasonCode,
                        "input_guard_unhealthy",
                        StringComparison.Ordinal))
                {
                    _requiresHookRefresh = true;
                }
                preemption = _safety.RevokeAndReleaseOwned(
                    reasonCode);
            }
            QueuePreemption(preemption, reasonCode);
        }

        internal bool PollHookHealth(bool refresh)
        {
            if (_disposed)
            {
                return false;
            }

            bool healthy = false;
            try
            {
                healthy = _hookSession != null
                    && (!refresh
                        || _hookSession.TryRefresh(
                            HookRefreshTimeout))
                    && _hookSession.IsHealthy(
                        HeartbeatMaximumAge);
            }
            catch
            {
                healthy = false;
            }

            if (healthy)
            {
                _safety.RecordGuardHeartbeat(true);
                lock (_sync)
                {
                    _guardUnhealthyLatched = false;
                    if (refresh)
                    {
                        _requiresHookRefresh = false;
                        _guardObservationStartedMonotonic =
                            _win32.MonotonicMilliseconds;
                    }
                }
                return true;
            }

            bool shouldPreempt;
            lock (_sync)
            {
                shouldPreempt = !_guardUnhealthyLatched;
                _guardUnhealthyLatched = true;
                _requiresHookRefresh = true;
            }
            if (shouldPreempt)
            {
                InputPreemption preemption =
                    _safety.GuardBecameUnhealthy(
                        "input_guard_unhealthy");
                QueuePreemption(
                    preemption,
                    "input_guard_unhealthy");
            }
            return false;
        }

        private bool OnLowLevelHookEvent(
            NativeLowLevelHookEvent hookEvent)
        {
            if (hookEvent == null)
            {
                return false;
            }

            _safety.RecordGuardHeartbeat(true);
            if (hookEvent.IsInjected
                && hookEvent.ExtraInfo == RuntimeInjectionTag)
            {
                return OnRuntimeHookEvent(hookEvent);
            }

            string control = string.IsNullOrWhiteSpace(
                hookEvent.ControlId)
                ? hookEvent.Device == NativeHookDevice.Mouse
                    ? "PointerMotion"
                    : "UnknownKeyboard"
                : hookEvent.ControlId;

            long externalInputSequence;
            lock (_sync)
            {
                _lastExternalObservedMonotonic =
                    _win32.MonotonicMilliseconds;
                externalInputSequence =
                    ++_externalInputSequence;
                if (hookEvent.IsInjected)
                {
                    _lastOtherInjectedInputSequence =
                        externalInputSequence;
                }
                if (hookEvent.Transition
                    == NativeControlTransition.Down)
                {
                    _externalControlsDown.Add(control);
                }
                else if (hookEvent.Transition
                    == NativeControlTransition.Up)
                {
                    _externalControlsDown.Remove(control);
                }
            }

            InputPreemption preemption = _safety.RecordExternalInput(
                control,
                hookEvent.Transition
                    == NativeControlTransition.Down,
                hookEvent.IsInjected
                    ? ExternalInputKind.OtherInjected
                    : ExternalInputKind.HumanPhysical);
            long foregroundWindowHandle;
            try
            {
                foregroundWindowHandle =
                    _win32.GetForegroundWindow().ToInt64();
            }
            catch
            {
                foregroundWindowHandle = 0;
            }
            QueuePreemption(
                preemption,
                hookEvent.IsInjected
                    ? "external_input"
                    : "human_input",
                externalInputSequence,
                foregroundWindowHandle,
                hookEvent.ControlId,
                hookEvent.Transition);
            return false;
        }

        private bool OnRuntimeHookEvent(
            NativeLowLevelHookEvent hookEvent)
        {
            ActiveBatch batch;
            lock (_sync)
            {
                if (_cleanupInProgress)
                {
                    return HandleCleanupHookEventLocked(
                        hookEvent);
                }
                batch = _activeBatch;
            }

            if (batch == null)
            {
                InputPreemption orphanPreemption =
                    _safety.GuardBecameUnhealthy(
                        "input_guard_unhealthy");
                QueuePreemption(
                    orphanPreemption,
                    "input_guard_unhealthy");
                return true;
            }

            NativeInputPacket expected = batch.NextExpected;
            if (expected == null
                || !HookEventMatches(expected, hookEvent))
            {
                batch.Block("input_guard_unhealthy");
                InputPreemption mismatchPreemption =
                    _safety.GuardBecameUnhealthy(
                        "input_guard_unhealthy");
                QueuePreemption(
                    mismatchPreemption,
                    "input_guard_unhealthy");
                return true;
            }

            string validationReason;
            try
            {
                validationReason = batch.ValidateAtHook(
                    hookEvent);
            }
            catch
            {
                validationReason = "input_guard_unhealthy";
            }
            if (validationReason != null)
            {
                batch.Block(validationReason);
                InputPreemption preemption =
                    _safety.RevokeAndReleaseOwned(
                        validationReason);
                QueuePreemption(preemption, validationReason);
                return true;
            }

            lock (_sync)
            {
                if (hookEvent.Transition
                        == NativeControlTransition.Down
                    && !string.IsNullOrWhiteSpace(
                        hookEvent.ControlId))
                {
                    NativeInputPacket release;
                    try
                    {
                        release = expected.CreateRelease();
                    }
                    catch
                    {
                        batch.Block("input_guard_unhealthy");
                        InputPreemption invalidPacketPreemption =
                            _safety.GuardBecameUnhealthy(
                                "input_guard_unhealthy");
                        QueuePreemption(
                            invalidPacketPreemption,
                            "input_guard_unhealthy");
                        return true;
                    }
                    _safety.RecordRuntimeControlDown(
                        hookEvent.ControlId,
                        _safety.RuntimeInjectionTag);
                    _ownedReleases[hookEvent.ControlId] =
                        release;
                    _ownedDownOrder.Remove(hookEvent.ControlId);
                    _ownedDownOrder.Add(hookEvent.ControlId);
                }
                else if (hookEvent.Transition
                        == NativeControlTransition.Up
                    && !string.IsNullOrWhiteSpace(
                        hookEvent.ControlId))
                {
                    _safety.RecordRuntimeControlUp(
                        hookEvent.ControlId,
                        _safety.RuntimeInjectionTag);
                    _ownedReleases.Remove(hookEvent.ControlId);
                    _ownedDownOrder.Remove(hookEvent.ControlId);
                }
            }
            batch.AcceptOne();
            return false;
        }

        private bool HandleCleanupHookEventLocked(
            NativeLowLevelHookEvent hookEvent)
        {
            if (hookEvent.Transition
                    != NativeControlTransition.Up
                || string.IsNullOrWhiteSpace(
                    hookEvent.ControlId)
                || !_cleanupControls.Contains(
                    hookEvent.ControlId)
                || _externalControlsDown.Contains(
                    hookEvent.ControlId))
            {
                return true;
            }

            _cleanupControls.Remove(hookEvent.ControlId);
            _safety.RecordRuntimeControlUp(
                hookEvent.ControlId,
                _safety.RuntimeInjectionTag);
            return false;
        }

        private void QueuePreemption(
            InputPreemption preemption,
            string reasonCode,
            long externalInputSequence = 0,
            long foregroundWindowHandle = 0,
            string controlId = null,
            NativeControlTransition transition =
                NativeControlTransition.None)
        {
            string sessionId;
            string leaseId;
            lock (_sync)
            {
                sessionId = _boundSessionId;
                leaseId = _boundLeaseId;
                _boundSessionId = null;
                _boundLeaseId = null;
                if (string.Equals(
                        reasonCode,
                        "input_guard_unhealthy",
                        StringComparison.Ordinal))
                {
                    _requiresHookRefresh = true;
                }
                if (_activeBatch != null)
                {
                    _activeBatch.Block(reasonCode);
                }
            }
            _preemptionQueue.Enqueue(
                new PreemptionWork(
                    sessionId,
                    leaseId,
                    reasonCode,
                    preemption.RuntimeControlsToRelease,
                    externalInputSequence,
                    foregroundWindowHandle,
                    controlId,
                    transition));
            _preemptionSignal.Set();
        }

        private void PreemptionWorker()
        {
            while (true)
            {
                _preemptionSignal.WaitOne();
                while (_preemptionQueue.TryDequeue(
                    out PreemptionWork work))
                {
                    if (work.IsStop)
                    {
                        return;
                    }

                    if (work.SessionId != null
                        && work.LeaseId != null)
                    {
                        try
                        {
                            _preemptionSink
                                .RevokeLeaseAndCancelQueuedActions(
                                    work.SessionId,
                                    work.LeaseId,
                                    work.ReasonCode);
                        }
                        catch
                        {
                            // The input side remains revoked even when
                            // downstream audit/reporting fails.
                        }
                    }
                    NotifyExternalInputObserved(
                        work.ReasonCode,
                        work.ExternalInputSequence,
                        work.ForegroundWindowHandle,
                        work.ControlId,
                        work.Transition);
                    ReleaseRuntimeOwnedControls(work);
                }
            }
        }

        private void NotifyExternalInputObserved(
            string reasonCode,
            long externalInputSequence,
            long foregroundWindowHandle,
            string controlId,
            NativeControlTransition transition)
        {
            if (!string.Equals(
                    reasonCode,
                    "human_input",
                    StringComparison.Ordinal)
                && !string.Equals(
                    reasonCode,
                    "external_input",
                    StringComparison.Ordinal))
            {
                return;
            }
            if (externalInputSequence <= 0)
                return;
            Action<ExternalInputObservation> handlers =
                ExternalInputObserved;
            if (handlers != null)
            {
                var observation =
                    new ExternalInputObservation(
                        externalInputSequence,
                        reasonCode,
                        foregroundWindowHandle,
                        controlId,
                        transition);
                foreach (Action<ExternalInputObservation> handler
                    in handlers.GetInvocationList())
                {
                    try
                    {
                        handler(observation);
                    }
                    catch
                    {
                        // Preemption and owned-control cleanup remain
                        // authoritative even if an observer is shutting
                        // down.
                    }
                }
            }
            lock (_sync)
            {
                if (externalInputSequence
                    > _deliveredExternalInputSequence)
                {
                    _deliveredExternalInputSequence =
                        externalInputSequence;
                }
            }
        }

        private void ReleaseRuntimeOwnedControls(
            PreemptionWork work)
        {
            HashSet<string> requested = new HashSet<string>(
                work.RuntimeControlsToRelease,
                StringComparer.Ordinal);
            List<NativeInputPacket> releases =
                new List<NativeInputPacket>();
            lock (_sync)
            {
                for (int i = _ownedDownOrder.Count - 1;
                    i >= 0;
                    i--)
                {
                    string control = _ownedDownOrder[i];
                    if (!requested.Contains(control))
                    {
                        continue;
                    }

                    _ownedDownOrder.RemoveAt(i);
                    if (_ownedReleases.TryGetValue(
                            control,
                            out NativeInputPacket release))
                    {
                        _ownedReleases.Remove(control);
                        if (!_externalControlsDown.Contains(
                                control))
                        {
                            releases.Add(release);
                            _cleanupControls.Add(control);
                        }
                    }
                }
                if (releases.Count == 0)
                {
                    return;
                }
                _cleanupInProgress = true;
            }

            try
            {
                int inserted = _win32.SendInput(
                    releases,
                    RuntimeInjectionTag);
                if (inserted != releases.Count)
                {
                    _safety.GuardBecameUnhealthy(
                        "input_guard_unhealthy");
                }
            }
            catch
            {
                _safety.GuardBecameUnhealthy(
                    "input_guard_unhealthy");
            }
            finally
            {
                lock (_sync)
                {
                    _cleanupControls.Clear();
                    _cleanupInProgress = false;
                }
            }
        }

        private static bool HookEventMatches(
            NativeInputPacket packet,
            NativeLowLevelHookEvent hookEvent)
        {
            if ((packet.Kind == NativeInputPacketKind.Keyboard)
                    != (hookEvent.Device
                        == NativeHookDevice.Keyboard)
                || packet.Transition != hookEvent.Transition
                || !string.Equals(
                    packet.ControlId,
                    hookEvent.ControlId,
                    StringComparison.Ordinal))
            {
                return false;
            }

            if (packet.Kind == NativeInputPacketKind.Keyboard)
            {
                return true;
            }

            uint expectedMessage = MouseMessageForFlags(
                packet.MouseFlags);
            return expectedMessage == 0
                || expectedMessage == hookEvent.NativeMessage;
        }

        private static uint MouseMessageForFlags(uint flags)
        {
            if ((flags & 0x0002) != 0) return 0x0201;
            if ((flags & 0x0004) != 0) return 0x0202;
            if ((flags & 0x0008) != 0) return 0x0204;
            if ((flags & 0x0010) != 0) return 0x0205;
            if ((flags & 0x0020) != 0) return 0x0207;
            if ((flags & 0x0040) != 0) return 0x0208;
            if ((flags & 0x0080) != 0) return 0x020B;
            if ((flags & 0x0100) != 0) return 0x020C;
            if ((flags & 0x0800) != 0) return 0x020A;
            if ((flags & 0x1000) != 0) return 0x020E;
            if ((flags & 0x0001) != 0) return 0x0200;
            return 0;
        }

        private static ulong CreateRuntimeInjectionTag()
        {
            Span<byte> bytes = stackalloc byte[sizeof(ulong)];
            ulong value;
            do
            {
                RandomNumberGenerator.Fill(bytes);
                value = BitConverter.ToUInt64(bytes);
            }
            while (value == 0);
            return value;
        }

        private bool HasRequiredQuiescence(
            out string reasonCode)
        {
            IReadOnlyCollection<string> held;
            try
            {
                held = _win32
                    .GetAsyncHeldModifiersAndButtons()
                    ?? Array.Empty<string>();
            }
            catch
            {
                reasonCode = "input_guard_unhealthy";
                return false;
            }
            string[] externalHeld = held
                .Where(control =>
                    !string.IsNullOrWhiteSpace(control)
                    && !HasRuntimeOwnership(control))
                .Distinct(StringComparer.Ordinal)
                .ToArray();
            if (externalHeld.Length != 0)
            {
                ObserveExternallyHeldControls(externalHeld);
                reasonCode = "input_not_quiescent";
                return false;
            }

            InputSafetyDecision stateDecision =
                _safety.EvaluateQuiescence();
            if (!stateDecision.Allowed)
            {
                reasonCode = stateDecision.ReasonCode;
                return false;
            }

            long lastObserved;
            lock (_sync)
            {
                lastObserved = Math.Max(
                    _guardObservationStartedMonotonic,
                    _lastExternalObservedMonotonic);
            }
            long now = _win32.MonotonicMilliseconds;
            if (now < lastObserved
                || now - lastObserved
                    < InputSafetyStateMachine
                        .QuiescenceMilliseconds)
            {
                reasonCode = "input_not_quiescent";
                return false;
            }
            reasonCode = null;
            return true;
        }

        private void ThrowIfDisposed()
        {
            if (_disposed)
            {
                throw new ObjectDisposedException(
                    nameof(NativeInputGuard));
            }
        }

        private static void RequireValue(
            string value,
            string parameterName)
        {
            if (string.IsNullOrWhiteSpace(value))
            {
                throw new ArgumentException(
                    "A non-empty value is required.",
                    parameterName);
            }
        }

        public void Dispose()
        {
            if (_disposed)
            {
                return;
            }
            _disposed = true;
            _watchdog?.Dispose();
            try
            {
                _hookSession?.Dispose();
            }
            catch
            {
                // Shutdown must still release our bookkeeping.
            }

            InputPreemption preemption =
                _safety.RevokeAndReleaseOwned(
                    "input_guard_unhealthy");
            QueuePreemption(
                preemption,
                "input_guard_unhealthy");
            _preemptionQueue.Enqueue(PreemptionWork.Stop);
            _preemptionSignal.Set();
            _preemptionThread.Join(TimeSpan.FromSeconds(2));
            _preemptionSignal.Dispose();
        }

        internal sealed class BatchHandle : IDisposable
        {
            private readonly NativeInputGuard _owner;
            private readonly ActiveBatch _batch;
            private bool _disposed;

            internal BatchHandle(
                NativeInputGuard owner,
                ActiveBatch batch)
            {
                _owner = owner;
                _batch = batch;
            }

            internal ActiveBatch Batch => _batch;

            internal bool WaitForHookObservation()
            {
                return _batch.Wait(HookObservationTimeout);
            }

            public void Dispose()
            {
                if (_disposed)
                {
                    return;
                }
                _disposed = true;
                lock (_owner._sync)
                {
                    if (ReferenceEquals(
                            _owner._activeBatch,
                            _batch))
                    {
                        _owner._activeBatch = null;
                    }
                }
                _batch.Dispose();
            }
        }

        internal sealed class ActiveBatch : IDisposable
        {
            private readonly object _sync = new object();
            private readonly NativeInputPacket[] _packets;
            private readonly ManualResetEventSlim _completed =
                new ManualResetEventSlim(false);
            private int _observed;
            private bool _blocked;
            private string _blockReason;

            internal ActiveBatch(
                NativeInputPacket[] packets,
                Func<NativeLowLevelHookEvent, string> validateAtHook)
            {
                _packets = packets;
                ValidateAtHook = validateAtHook;
            }

            internal Func<NativeLowLevelHookEvent, string>
                ValidateAtHook { get; }

            internal NativeInputPacket NextExpected
            {
                get
                {
                    lock (_sync)
                    {
                        return _blocked
                            || _observed >= _packets.Length
                                ? null
                                : _packets[_observed];
                    }
                }
            }

            internal bool Blocked
            {
                get
                {
                    lock (_sync)
                    {
                        return _blocked;
                    }
                }
            }

            internal string BlockReason
            {
                get
                {
                    lock (_sync)
                    {
                        return _blockReason;
                    }
                }
            }

            internal void AcceptOne()
            {
                lock (_sync)
                {
                    if (_blocked)
                    {
                        return;
                    }
                    _observed++;
                    if (_observed == _packets.Length)
                    {
                        _completed.Set();
                    }
                }
            }

            internal void Block(string reasonCode)
            {
                lock (_sync)
                {
                    if (!_blocked)
                    {
                        _blocked = true;
                        _blockReason = reasonCode;
                    }
                    _completed.Set();
                }
            }

            internal bool Wait(TimeSpan timeout)
            {
                return _completed.Wait(timeout);
            }

            public void Dispose()
            {
                _completed.Dispose();
            }
        }

        private sealed class PreemptionWork
        {
            internal PreemptionWork(
                string sessionId,
                string leaseId,
                string reasonCode,
                IEnumerable<string> runtimeControlsToRelease,
                long externalInputSequence = 0,
                long foregroundWindowHandle = 0,
                string controlId = null,
                NativeControlTransition transition =
                    NativeControlTransition.None,
                bool isStop = false)
            {
                SessionId = sessionId;
                LeaseId = leaseId;
                ReasonCode = reasonCode;
                RuntimeControlsToRelease =
                    (runtimeControlsToRelease
                        ?? Array.Empty<string>())
                    .ToArray();
                ExternalInputSequence =
                    externalInputSequence;
                ForegroundWindowHandle =
                    foregroundWindowHandle;
                ControlId = controlId;
                Transition = transition;
                IsStop = isStop;
            }

            internal static PreemptionWork Stop { get; } =
                new PreemptionWork(
                    null,
                    null,
                    null,
                    Array.Empty<string>(),
                    0,
                    0,
                    null,
                    NativeControlTransition.None,
                    true);

            internal string SessionId { get; }
            internal string LeaseId { get; }
            internal string ReasonCode { get; }
            internal string[] RuntimeControlsToRelease { get; }
            internal long ExternalInputSequence { get; }
            internal long ForegroundWindowHandle { get; }
            internal string ControlId { get; }
            internal NativeControlTransition Transition { get; }
            internal bool IsStop { get; }
        }
    }
}
