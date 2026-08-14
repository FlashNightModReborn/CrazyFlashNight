using System;

namespace CF7Launcher.AgentRuntime.Integration
{
    /// <summary>
    /// One atomic launch projection used by the narrow A5 unattended-entry
    /// gate.  TrueTitleReceiptAttemptId must come from the accepted Flash
    /// title receipt, never from the reveal watchdog or JS reveal fallback.
    /// </summary>
    internal sealed class TrustedUnattendedGameEntrySnapshot
    {
        internal TrustedUnattendedGameEntrySnapshot(
            string launchState,
            string slot,
            string attemptId,
            string trueTitleReceiptAttemptId)
        {
            LaunchState = launchState;
            Slot = slot;
            AttemptId = attemptId;
            TrueTitleReceiptAttemptId =
                trueTitleReceiptAttemptId;
        }

        public string LaunchState { get; }
        public string Slot { get; }
        public string AttemptId { get; }
        public string TrueTitleReceiptAttemptId { get; }
    }

    /// <summary>
    /// Adds the missing title-to-runtime entry fence only for the exact A5
    /// material-shop slot.  The sender has no command argument: production
    /// composition owns the one fixed AS2 entry payload.
    /// </summary>
    internal sealed class TrustedUnattendedGameEntryGate
    {
        internal const string ExactA5Slot =
            "cf7_agent_a5_material_shop_run";

        private readonly object _sync = new object();
        private readonly Func<TrustedUnattendedGameEntrySnapshot>
            _captureLaunchSnapshot;
        private readonly Func<string, string, bool>
            _isAgentControlReady;
        private readonly Func<string, bool> _sendFixedEntry;

        private string _trackedAttemptId;
        private string _sentAttemptId;
        private bool _sendInFlight;
        private string _sendInFlightAttemptId;

        internal TrustedUnattendedGameEntryGate(
            Func<TrustedUnattendedGameEntrySnapshot>
                captureLaunchSnapshot,
            Func<string, string, bool> isAgentControlReady,
            Func<string, bool> sendFixedEntry)
        {
            _captureLaunchSnapshot = captureLaunchSnapshot
                ?? throw new ArgumentNullException(
                    nameof(captureLaunchSnapshot));
            _isAgentControlReady = isAgentControlReady
                ?? throw new ArgumentNullException(
                    nameof(isAgentControlReady));
            _sendFixedEntry = sendFixedEntry
                ?? throw new ArgumentNullException(
                    nameof(sendFixedEntry));
        }

        /// <summary>
        /// Returns whether credential publication may continue.  Slots other
        /// than the exact A5 slot are deliberately outside this gate.
        /// </summary>
        internal bool TryAllowCredential(
            string slot,
            string attemptId)
        {
            if (!string.Equals(
                    slot,
                    ExactA5Slot,
                    StringComparison.Ordinal))
            {
                return true;
            }

            if (!TryCaptureExactReadyTitle(
                    slot,
                    attemptId))
            {
                return false;
            }

            if (IsAgentControlReady(slot, attemptId))
                return true;

            lock (_sync)
            {
                if (!string.Equals(
                        _trackedAttemptId,
                        attemptId,
                        StringComparison.Ordinal))
                {
                    _trackedAttemptId = attemptId;
                    _sentAttemptId = null;
                }

                if (_sendInFlight
                    || string.Equals(
                        _sentAttemptId,
                        attemptId,
                        StringComparison.Ordinal))
                {
                    return false;
                }

                _sendInFlight = true;
                _sendInFlightAttemptId = attemptId;
            }

            bool sent = false;
            try
            {
                sent = _sendFixedEntry(attemptId);
            }
            catch
            {
                sent = false;
            }
            finally
            {
                lock (_sync)
                {
                    if (string.Equals(
                            _sendInFlightAttemptId,
                            attemptId,
                            StringComparison.Ordinal))
                    {
                        _sendInFlight = false;
                        _sendInFlightAttemptId = null;
                    }

                    if (sent
                        && string.Equals(
                            _trackedAttemptId,
                            attemptId,
                            StringComparison.Ordinal))
                    {
                        _sentAttemptId = attemptId;
                    }
                }
            }

            if (!sent
                || !TryCaptureExactReadyTitle(
                    slot,
                    attemptId))
            {
                return false;
            }

            return IsAgentControlReady(slot, attemptId);
        }

        private bool TryCaptureExactReadyTitle(
            string slot,
            string attemptId)
        {
            if (string.IsNullOrEmpty(attemptId))
                return false;

            TrustedUnattendedGameEntrySnapshot snapshot;
            try
            {
                snapshot = _captureLaunchSnapshot();
            }
            catch
            {
                return false;
            }

            return snapshot != null
                && string.Equals(
                    snapshot.LaunchState,
                    "Ready",
                    StringComparison.Ordinal)
                && string.Equals(
                    snapshot.Slot,
                    slot,
                    StringComparison.Ordinal)
                && string.Equals(
                    snapshot.AttemptId,
                    attemptId,
                    StringComparison.Ordinal)
                && string.Equals(
                    snapshot.TrueTitleReceiptAttemptId,
                    attemptId,
                    StringComparison.Ordinal);
        }

        private bool IsAgentControlReady(
            string slot,
            string attemptId)
        {
            try
            {
                return _isAgentControlReady(slot, attemptId);
            }
            catch
            {
                return false;
            }
        }
    }
}
