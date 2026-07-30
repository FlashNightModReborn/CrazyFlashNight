using System;

namespace CF7Launcher.AgentRuntime.Wings
{
    internal enum WingsPersonaPresentation
    {
        Visible,
        Hidden
    }

    [Flags]
    internal enum WingsShellEffect
    {
        None = 0,
        StopCapture = 1 << 0,
        StopInference = 1 << 1,
        RevokeWriteLease = 1 << 2,
        CancelPendingActions = 1 << 3,
        SuspendReadGrant = 1 << 4,
        RequiresFreshActivation = 1 << 5
    }

    internal sealed class TrustedNeutralPausePolicy
    {
        internal TrustedNeutralPausePolicy(
            string receiptId,
            string sessionId,
            bool retainReadGrantWhilePaused)
        {
            WingsProtocolValue.RequireOpaqueId(
                receiptId,
                nameof(receiptId));
            WingsProtocolValue.RequireOpaqueId(
                sessionId,
                nameof(sessionId));
            ReceiptId = receiptId;
            SessionId = sessionId;
            RetainReadGrantWhilePaused =
                retainReadGrantWhilePaused;
        }

        public string ReceiptId { get; }
        public string SessionId { get; }
        public bool RetainReadGrantWhilePaused { get; }
    }

    internal interface INeutralPausePolicyAuthority
    {
        bool TryResolve(
            string receiptId,
            out TrustedNeutralPausePolicy policy,
            out string reasonCode);
    }

    internal sealed class WingsShellSnapshot
    {
        public WingsShellSnapshot(
            WingsPersonaPresentation presentation,
            bool paused,
            bool captureRunning,
            bool inferenceRunning,
            bool readGrantActive,
            bool writeLeaseActive,
            bool pendingActionsExist,
            bool neutralObservationIndicatorVisible)
        {
            Presentation = presentation;
            Paused = paused;
            CaptureRunning = captureRunning;
            InferenceRunning = inferenceRunning;
            ReadGrantActive = readGrantActive;
            WriteLeaseActive = writeLeaseActive;
            PendingActionsExist = pendingActionsExist;
            NeutralObservationIndicatorVisible =
                neutralObservationIndicatorVisible;
        }

        public WingsPersonaPresentation Presentation { get; }
        public bool Paused { get; }
        public bool CaptureRunning { get; }
        public bool InferenceRunning { get; }
        public bool ReadGrantActive { get; }
        public bool WriteLeaseActive { get; }
        public bool PendingActionsExist { get; }
        public bool NeutralObservationIndicatorVisible { get; }
    }

    internal sealed class WingsShellTransition
    {
        public WingsShellTransition(
            WingsShellSnapshot snapshot,
            WingsShellEffect requiredEffects,
            bool neutralRetainReadPolicyApplied)
        {
            Snapshot = snapshot;
            RequiredEffects = requiredEffects;
            NeutralRetainReadPolicyApplied =
                neutralRetainReadPolicyApplied;
        }

        public WingsShellSnapshot Snapshot { get; }
        public WingsShellEffect RequiredEffects { get; }
        public bool NeutralRetainReadPolicyApplied { get; }
    }

    /// <summary>
    /// Pure shell lifecycle model. It never owns a game-exit command and it
    /// cannot mint read/write authority while resuming.
    /// </summary>
    internal sealed class WingsShellStateMachine
    {
        private readonly object _sync = new object();
        private readonly string _sessionId;
        private WingsPersonaPresentation _presentation;
        private bool _paused;
        private bool _captureRunning;
        private bool _inferenceRunning;
        private bool _readGrantActive;
        private bool _writeLeaseActive;
        private bool _pendingActionsExist;
        private bool _neutralIndicatorVisible;

        public WingsShellStateMachine(
            string sessionId,
            bool readGrantActive,
            bool writeLeaseActive,
            bool pendingActionsExist,
            bool captureRunning = true,
            bool inferenceRunning = true)
        {
            WingsProtocolValue.RequireOpaqueId(
                sessionId,
                nameof(sessionId));
            if ((!readGrantActive && captureRunning)
                || (!captureRunning && inferenceRunning))
            {
                throw new ArgumentException(
                    "Initial shell observation state is inconsistent.");
            }
            _sessionId = sessionId;
            _presentation = WingsPersonaPresentation.Visible;
            _captureRunning = captureRunning;
            _inferenceRunning = inferenceRunning;
            _readGrantActive = readGrantActive;
            _writeLeaseActive = writeLeaseActive;
            _pendingActionsExist = pendingActionsExist;
            _neutralIndicatorVisible =
                readGrantActive && captureRunning;
        }

        public WingsShellSnapshot Snapshot
        {
            get
            {
                lock (_sync)
                    return SnapshotLocked();
            }
        }

        public WingsShellSnapshot HidePersona()
        {
            lock (_sync)
            {
                _presentation = WingsPersonaPresentation.Hidden;
                return SnapshotLocked();
            }
        }

        public WingsShellSnapshot ShowPersona()
        {
            lock (_sync)
            {
                _presentation = WingsPersonaPresentation.Visible;
                return SnapshotLocked();
            }
        }

        public WingsShellTransition Pause(
            string neutralPolicyReceiptId = null,
            INeutralPausePolicyAuthority authority = null)
        {
            bool retainRead = ResolveRetainReadPolicy(
                neutralPolicyReceiptId,
                authority);
            lock (_sync)
            {
                if (_paused)
                {
                    return new WingsShellTransition(
                        SnapshotLocked(),
                        WingsShellEffect.None,
                        retainRead && _readGrantActive);
                }

                WingsShellEffect effects =
                    WingsShellEffect.StopCapture
                    | WingsShellEffect.StopInference
                    | WingsShellEffect.RevokeWriteLease
                    | WingsShellEffect.CancelPendingActions;
                if (!retainRead)
                    effects |= WingsShellEffect.SuspendReadGrant;

                _paused = true;
                _captureRunning = false;
                _inferenceRunning = false;
                _writeLeaseActive = false;
                _pendingActionsExist = false;
                if (!retainRead)
                    _readGrantActive = false;
                _neutralIndicatorVisible = false;
                return new WingsShellTransition(
                    SnapshotLocked(),
                    effects,
                    retainRead && _readGrantActive);
            }
        }

        public WingsShellTransition ResumeShell()
        {
            lock (_sync)
            {
                if (!_paused)
                {
                    return new WingsShellTransition(
                        SnapshotLocked(),
                        WingsShellEffect.None,
                        false);
                }
                _paused = false;
                return new WingsShellTransition(
                    SnapshotLocked(),
                    WingsShellEffect.RequiresFreshActivation,
                    false);
            }
        }

        public WingsShellSnapshot ActivateReadGrant()
        {
            lock (_sync)
            {
                if (_paused)
                {
                    throw new InvalidOperationException(
                        "Cannot activate observation while paused.");
                }
                _readGrantActive = true;
                _captureRunning = true;
                _inferenceRunning = true;
                _neutralIndicatorVisible = true;
                return SnapshotLocked();
            }
        }

        public WingsShellSnapshot SuspendReadGrant()
        {
            lock (_sync)
            {
                _captureRunning = false;
                _inferenceRunning = false;
                _readGrantActive = false;
                _neutralIndicatorVisible = false;
                return SnapshotLocked();
            }
        }

        private bool ResolveRetainReadPolicy(
            string receiptId,
            INeutralPausePolicyAuthority authority)
        {
            if (receiptId == null || authority == null)
                return false;
            try
            {
                WingsProtocolValue.RequireOpaqueId(
                    receiptId,
                    nameof(receiptId));
            }
            catch (ArgumentException)
            {
                return false;
            }
            return authority.TryResolve(
                    receiptId,
                    out TrustedNeutralPausePolicy policy,
                    out _)
                && policy != null
                && string.Equals(
                    policy.ReceiptId,
                    receiptId,
                    StringComparison.Ordinal)
                && string.Equals(
                    policy.SessionId,
                    _sessionId,
                    StringComparison.Ordinal)
                && policy.RetainReadGrantWhilePaused;
        }

        private WingsShellSnapshot SnapshotLocked()
        {
            return new WingsShellSnapshot(
                _presentation,
                _paused,
                _captureRunning,
                _inferenceRunning,
                _readGrantActive,
                _writeLeaseActive,
                _pendingActionsExist,
                _neutralIndicatorVisible);
        }
    }
}
