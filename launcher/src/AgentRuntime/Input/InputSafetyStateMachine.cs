using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using CF7Launcher.AgentRuntime.Security;

namespace CF7Launcher.AgentRuntime.Input
{
    public enum ExternalInputKind
    {
        HumanPhysical,
        OtherInjected
    }

    public sealed record InputEpochSnapshot(
        string SessionId,
        long LifecycleGeneration,
        string AttemptId,
        long AttemptGeneration,
        string TargetId,
        long SurfaceEpoch,
        long CoordinateSpaceVersion,
        string PanelInstanceId,
        long DocumentGeneration,
        long FocusEpoch,
        long ModalEpoch);

    public sealed class InputDispatchCheck
    {
        public InputEpochSnapshot ExpectedEpochs { get; init; }
        public long ExpectedInputEpoch { get; init; }
        public string ForegroundTargetId { get; init; }
        public bool IsPointerAction { get; init; }
        public string HitTestTargetId { get; init; }
    }

    public sealed class InputSafetyDecision
    {
        internal InputSafetyDecision(bool allowed, string reasonCode)
        {
            Allowed = allowed;
            ReasonCode = reasonCode;
        }

        public bool Allowed { get; }
        public string ReasonCode { get; }
    }

    public sealed class InputPreemption
    {
        internal InputPreemption(
            long inputEpoch,
            string reasonCode,
            IEnumerable<string> runtimeControlsToRelease)
        {
            InputEpoch = inputEpoch;
            ReasonCode = reasonCode;
            RuntimeControlsToRelease = Array.AsReadOnly(
                runtimeControlsToRelease
                    .OrderBy(value => value, StringComparer.Ordinal)
                    .ToArray());
        }

        public long InputEpoch { get; }
        public string ReasonCode { get; }
        public ReadOnlyCollection<string> RuntimeControlsToRelease { get; }
    }

    /// <summary>
    /// Pure fail-closed state used by both the dispatch path and the eventual
    /// low-level hook callback. It performs no native input by itself.
    /// </summary>
    public sealed class InputSafetyStateMachine
    {
        public const long QuiescenceMilliseconds = 150;
        public const long GuardHeartbeatMaximumAgeMilliseconds = 500;

        private readonly object _sync = new object();
        private readonly IAgentRuntimeClock _clock;
        private readonly HashSet<string> _externalControlsDown =
            new HashSet<string>(StringComparer.Ordinal);
        private readonly HashSet<string> _runtimeControlsDown =
            new HashSet<string>(StringComparer.Ordinal);
        private InputEpochSnapshot _currentEpochs;
        private string _foregroundTargetId;
        private long _lastExternalInputMonotonic = long.MinValue;
        private long _lastGuardHeartbeatMonotonic = long.MinValue;
        private bool _guardHealthy;
        private bool _interactiveDesktop = true;
        private bool _securityModalPresent;
        private bool _humanReauthorizationRequired;
        private long _inputEpoch = 1;

        public InputSafetyStateMachine(IAgentRuntimeClock clock)
        {
            _clock = clock ?? throw new ArgumentNullException(nameof(clock));
            RuntimeInjectionTag = OpaqueIdGenerator.Create("inputtag");
        }

        public string RuntimeInjectionTag { get; }

        public long InputEpoch
        {
            get
            {
                lock (_sync)
                {
                    return _inputEpoch;
                }
            }
        }

        public InputEpochSnapshot CurrentEpochs
        {
            get
            {
                lock (_sync)
                {
                    return _currentEpochs;
                }
            }
        }

        public void SetInitialAuthoritativeState(
            InputEpochSnapshot epochs,
            string foregroundTargetId)
        {
            ValidateEpochs(epochs);
            lock (_sync)
            {
                if (_currentEpochs != null)
                {
                    throw new InvalidOperationException(
                        "Authoritative state is already initialized.");
                }
                _currentEpochs = epochs;
                _foregroundTargetId = foregroundTargetId;
            }
        }

        public InputPreemption AdvanceAuthoritativeState(
            InputEpochSnapshot epochs,
            string foregroundTargetId,
            string reasonCode)
        {
            ValidateEpochs(epochs);
            RequireReason(reasonCode);
            lock (_sync)
            {
                _currentEpochs = epochs;
                _foregroundTargetId = foregroundTargetId;
                return PreemptLocked(reasonCode);
            }
        }

        public InputPreemption SetSecurityModal(
            bool present,
            string reasonCode)
        {
            RequireReason(reasonCode);
            lock (_sync)
            {
                if (_securityModalPresent == present)
                {
                    return new InputPreemption(
                        _inputEpoch,
                        reasonCode,
                        Array.Empty<string>());
                }
                _securityModalPresent = present;
                if (present)
                {
                    _humanReauthorizationRequired = true;
                }
                return PreemptLocked(reasonCode);
            }
        }

        /// <summary>
        /// Called only after the neutral Launcher UI has verified a fresh
        /// human authorization receipt following security-surface dismissal.
        /// This is internal so it cannot become a wire-level client claim.
        /// </summary>
        internal void AcceptTrustedHumanReauthorization()
        {
            lock (_sync)
            {
                if (_securityModalPresent)
                {
                    throw new InvalidOperationException(
                        "security_surface_still_present");
                }
                _humanReauthorizationRequired = false;
            }
        }

        public InputPreemption SetInteractiveDesktop(
            bool interactive,
            string reasonCode)
        {
            RequireReason(reasonCode);
            lock (_sync)
            {
                if (_interactiveDesktop == interactive)
                {
                    return new InputPreemption(
                        _inputEpoch,
                        reasonCode,
                        Array.Empty<string>());
                }
                _interactiveDesktop = interactive;
                return PreemptLocked(reasonCode);
            }
        }

        public void RecordGuardHeartbeat(bool healthy)
        {
            lock (_sync)
            {
                _guardHealthy = healthy;
                _lastGuardHeartbeatMonotonic =
                    _clock.MonotonicMilliseconds;
            }
        }

        public InputPreemption RecordExternalInput(
            string control,
            bool isDown,
            ExternalInputKind source)
        {
            PrincipalCredentialAuthority.RequireValue(
                control,
                nameof(control));
            lock (_sync)
            {
                if (isDown)
                {
                    _externalControlsDown.Add(control);
                }
                else
                {
                    _externalControlsDown.Remove(control);
                }
                _lastExternalInputMonotonic =
                    _clock.MonotonicMilliseconds;
                return PreemptLocked(
                    source == ExternalInputKind.HumanPhysical
                        ? "human_input"
                        : "external_input");
            }
        }

        public void RecordRuntimeControlDown(
            string control,
            string exactRuntimeTag)
        {
            PrincipalCredentialAuthority.RequireValue(
                control,
                nameof(control));
            lock (_sync)
            {
                if (!string.Equals(
                        RuntimeInjectionTag,
                        exactRuntimeTag,
                        StringComparison.Ordinal))
                {
                    throw new InvalidOperationException(
                        "runtime_input_tag_mismatch");
                }
                _runtimeControlsDown.Add(control);
            }
        }

        public bool RecordRuntimeControlUp(
            string control,
            string exactRuntimeTag)
        {
            lock (_sync)
            {
                if (!string.Equals(
                        RuntimeInjectionTag,
                        exactRuntimeTag,
                        StringComparison.Ordinal))
                {
                    return false;
                }
                return _runtimeControlsDown.Remove(control);
            }
        }

        public InputPreemption GuardBecameUnhealthy(string reasonCode)
        {
            RequireReason(reasonCode);
            lock (_sync)
            {
                _guardHealthy = false;
                return PreemptLocked(reasonCode);
            }
        }

        public InputSafetyDecision EvaluateQuiescence()
        {
            lock (_sync)
            {
                return EvaluateQuiescenceLocked();
            }
        }

        public InputSafetyDecision EvaluateAtDispatch(
            InputDispatchCheck check)
        {
            if (check == null)
            {
                throw new ArgumentNullException(nameof(check));
            }
            ValidateEpochs(check.ExpectedEpochs);

            lock (_sync)
            {
                InputSafetyDecision quiescence =
                    EvaluateQuiescenceLocked();
                if (!quiescence.Allowed)
                {
                    return quiescence;
                }
                if (_currentEpochs == null)
                {
                    return Denied("stale_observation");
                }
                string epochMismatch = GetEpochMismatchReason(
                    _currentEpochs,
                    check.ExpectedEpochs);
                if (epochMismatch != null)
                {
                    return Denied(epochMismatch);
                }
                if (check.ExpectedInputEpoch != _inputEpoch)
                {
                    return Denied("external_input_preempted");
                }
                if (!string.Equals(
                        _foregroundTargetId,
                        check.ExpectedEpochs.TargetId,
                        StringComparison.Ordinal)
                    || !string.Equals(
                        check.ForegroundTargetId,
                        check.ExpectedEpochs.TargetId,
                        StringComparison.Ordinal))
                {
                    return Denied("foreground_mismatch");
                }
                if (check.IsPointerAction
                    && !string.Equals(
                        check.HitTestTargetId,
                        check.ExpectedEpochs.TargetId,
                        StringComparison.Ordinal))
                {
                    return Denied("hit_test_mismatch");
                }
                return Allowed();
            }
        }

        public InputPreemption RevokeAndReleaseOwned(string reasonCode)
        {
            RequireReason(reasonCode);
            lock (_sync)
            {
                return PreemptLocked(reasonCode);
            }
        }

        private InputSafetyDecision EvaluateQuiescenceLocked()
        {
            if (!_interactiveDesktop)
            {
                return Denied("desktop_unavailable");
            }
            if (_securityModalPresent)
            {
                return Denied("human_only_security_surface");
            }
            if (_humanReauthorizationRequired)
            {
                return Denied("human_intervention_required");
            }
            if (!_guardHealthy
                || _lastGuardHeartbeatMonotonic == long.MinValue
                || _clock.MonotonicMilliseconds
                    - _lastGuardHeartbeatMonotonic
                    > GuardHeartbeatMaximumAgeMilliseconds)
            {
                return Denied("input_guard_unhealthy");
            }
            if (_externalControlsDown.Count != 0)
            {
                return Denied("input_not_quiescent");
            }
            if (_lastExternalInputMonotonic != long.MinValue
                && _clock.MonotonicMilliseconds
                    - _lastExternalInputMonotonic
                    < QuiescenceMilliseconds)
            {
                return Denied("input_not_quiescent");
            }
            return Allowed();
        }

        private InputPreemption PreemptLocked(string reasonCode)
        {
            string[] owned = _runtimeControlsDown
                .OrderBy(value => value, StringComparer.Ordinal)
                .ToArray();
            _runtimeControlsDown.Clear();
            _inputEpoch = checked(_inputEpoch + 1);
            return new InputPreemption(_inputEpoch, reasonCode, owned);
        }

        private static void ValidateEpochs(InputEpochSnapshot epochs)
        {
            if (epochs == null)
            {
                throw new ArgumentNullException(nameof(epochs));
            }
            PrincipalCredentialAuthority.RequireValue(
                epochs.SessionId,
                nameof(epochs.SessionId));
            PrincipalCredentialAuthority.RequireValue(
                epochs.TargetId,
                nameof(epochs.TargetId));
        }

        private static void RequireReason(string reasonCode)
        {
            PrincipalCredentialAuthority.RequireValue(
                reasonCode,
                nameof(reasonCode));
        }

        private static string GetEpochMismatchReason(
            InputEpochSnapshot current,
            InputEpochSnapshot expected)
        {
            if (!string.Equals(
                    current.SessionId,
                    expected.SessionId,
                    StringComparison.Ordinal)
                || current.LifecycleGeneration
                    != expected.LifecycleGeneration)
            {
                return "stale_lifecycle";
            }
            if (!string.Equals(
                    current.AttemptId,
                    expected.AttemptId,
                    StringComparison.Ordinal)
                || current.AttemptGeneration
                    != expected.AttemptGeneration)
            {
                return "stale_attempt";
            }
            if (!string.Equals(
                    current.TargetId,
                    expected.TargetId,
                    StringComparison.Ordinal)
                || current.SurfaceEpoch != expected.SurfaceEpoch)
            {
                return "stale_surface";
            }
            if (current.CoordinateSpaceVersion
                != expected.CoordinateSpaceVersion)
            {
                return "stale_coordinate_space";
            }
            if (!string.Equals(
                    current.PanelInstanceId,
                    expected.PanelInstanceId,
                    StringComparison.Ordinal))
            {
                return "stale_panel_instance";
            }
            if (current.DocumentGeneration
                != expected.DocumentGeneration)
            {
                return "stale_document";
            }
            if (current.FocusEpoch != expected.FocusEpoch)
            {
                return "stale_focus";
            }
            if (current.ModalEpoch != expected.ModalEpoch)
            {
                return "stale_modal";
            }
            return null;
        }

        private static InputSafetyDecision Allowed()
        {
            return new InputSafetyDecision(true, null);
        }

        private static InputSafetyDecision Denied(string reason)
        {
            return new InputSafetyDecision(false, reason);
        }
    }
}
