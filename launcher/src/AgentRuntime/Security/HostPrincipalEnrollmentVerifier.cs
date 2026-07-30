using System;
using System.Collections.Generic;

namespace CF7Launcher.AgentRuntime.Security
{
    /// <summary>
    /// Production issuer boundary. Developer receipts come only from the
    /// current-user protected neutral-UI store. Player and unattended
    /// authorizations must be registered by trusted Launcher code with exact
    /// host-observed evidence before PrincipalCredentialAuthority can issue.
    /// </summary>
    internal sealed class HostPrincipalEnrollmentVerifier
        : IPrincipalEnrollmentVerifier
    {
        private readonly object _sync = new object();
        private readonly PersistentDeveloperEnrollmentStore _developers;
        private readonly Dictionary<string, TrustedAuthorization>
            _unattended =
                new Dictionary<string, TrustedAuthorization>(
                    StringComparer.Ordinal);
        private readonly Dictionary<string, TrustedAuthorization>
            _player =
                new Dictionary<string, TrustedAuthorization>(
                    StringComparer.Ordinal);

        public HostPrincipalEnrollmentVerifier(
            PersistentDeveloperEnrollmentStore developers)
        {
            _developers = developers
                ?? throw new ArgumentNullException(nameof(developers));
        }

        public bool TryVerifyDeveloper(
            DeveloperEnrollmentEvidence evidence,
            out VerifiedPrincipalAuthorization authorization,
            out string reasonCode)
        {
            return _developers.TryVerifyReceipt(
                evidence,
                out authorization,
                out reasonCode);
        }

        public bool TryVerifyUnattended(
            UnattendedCredentialEvidence evidence,
            out VerifiedPrincipalAuthorization authorization,
            out string reasonCode)
        {
            authorization = null;
            if (evidence == null)
            {
                reasonCode =
                    "unattended_allow_list_evidence_invalid";
                return false;
            }
            string key = UnattendedKey(evidence);
            lock (_sync)
            {
                if (!_unattended.Remove(
                        key,
                        out TrustedAuthorization trusted)
                    || !trusted.Matches(
                        evidence.AllowedCapabilities,
                        evidence.AllowedTargets))
                {
                    reasonCode =
                        "unattended_allow_list_evidence_invalid";
                    return false;
                }
                authorization = trusted.ToVerified();
                reasonCode = null;
                return true;
            }
        }

        public bool TryVerifyPlayerAssist(
            PlayerAssistCredentialEvidence evidence,
            out VerifiedPrincipalAuthorization authorization,
            out string reasonCode)
        {
            authorization = null;
            if (evidence == null
                || string.IsNullOrWhiteSpace(
                    evidence.ConsentReceipt))
            {
                reasonCode = "player_consent_evidence_invalid";
                return false;
            }
            lock (_sync)
            {
                if (!_player.Remove(
                        evidence.ConsentReceipt,
                        out TrustedAuthorization trusted)
                    || !trusted.Matches(
                        evidence.AllowedCapabilities,
                        evidence.AllowedTargets))
                {
                    reasonCode =
                        "player_consent_evidence_invalid";
                    return false;
                }
                authorization = trusted.ToVerified();
                reasonCode = null;
                return true;
            }
        }

        internal void RegisterUnattended(
            UnattendedCredentialEvidence exactEvidence,
            string issuerReceipt)
        {
            if (exactEvidence == null)
                throw new ArgumentNullException(
                    nameof(exactEvidence));
            var trusted = new TrustedAuthorization(
                exactEvidence.AllowedCapabilities,
                exactEvidence.AllowedTargets,
                issuerReceipt);
            lock (_sync)
            {
                _unattended.Add(
                    UnattendedKey(exactEvidence),
                    trusted);
            }
        }

        internal void RegisterPlayerConsent(
            PlayerAssistCredentialEvidence exactEvidence)
        {
            if (exactEvidence == null)
                throw new ArgumentNullException(
                    nameof(exactEvidence));
            PrincipalCredentialAuthority.RequireValue(
                exactEvidence.ConsentReceipt,
                nameof(exactEvidence.ConsentReceipt));
            var trusted = new TrustedAuthorization(
                exactEvidence.AllowedCapabilities,
                exactEvidence.AllowedTargets,
                exactEvidence.ConsentReceipt);
            lock (_sync)
            {
                _player.Add(
                    exactEvidence.ConsentReceipt,
                    trusted);
            }
        }

        private static string UnattendedKey(
            UnattendedCredentialEvidence evidence)
        {
            return string.Join(
                "\u001f",
                evidence.ClientInstanceId ?? string.Empty,
                evidence.RunnerPolicyId ?? string.Empty,
                evidence.RunnerProcessId.ToString(
                    System.Globalization
                        .CultureInfo.InvariantCulture),
                evidence.RunnerProcessStartTimeUtc
                    .UtcDateTime.Ticks.ToString(
                        System.Globalization
                            .CultureInfo.InvariantCulture),
                evidence.RunnerExecutablePath
                    ?? string.Empty,
                evidence.RunnerExecutableSha256
                    ?? string.Empty,
                evidence.RunnerExecutableSize.ToString(
                    System.Globalization
                        .CultureInfo.InvariantCulture),
                evidence.RuntimeExecutablePath
                    ?? string.Empty,
                evidence.RequestNonce ?? string.Empty,
                evidence.BuildIdentity ?? string.Empty,
                evidence.PayloadClosure ?? string.Empty,
                evidence.SessionId ?? string.Empty,
                evidence.AttemptId ?? string.Empty,
                evidence.AttemptGeneration.ToString(
                    System.Globalization
                        .CultureInfo.InvariantCulture),
                evidence.Slot ?? string.Empty,
                evidence.CanonicalSavePath ?? string.Empty,
                evidence.RunnerDeadlineMonotonic.ToString(
                    System.Globalization
                        .CultureInfo.InvariantCulture));
        }

        private sealed class TrustedAuthorization
        {
            public TrustedAuthorization(
                IEnumerable<string> capabilities,
                IEnumerable<string> targets,
                string receipt)
            {
                Authorization =
                    VerifiedPrincipalAuthorization.CreateTrusted(
                        capabilities,
                        targets,
                        receipt);
            }

            public VerifiedPrincipalAuthorization Authorization
            {
                get;
            }

            public bool Matches(
                IEnumerable<string> capabilities,
                IEnumerable<string> targets)
            {
                return ExactSet(
                        Authorization.AllowedCapabilities,
                        capabilities)
                    && ExactSet(
                        Authorization.AllowedTargets,
                        targets);
            }

            public VerifiedPrincipalAuthorization ToVerified()
            {
                return VerifiedPrincipalAuthorization.CreateTrusted(
                    Authorization.AllowedCapabilities,
                    Authorization.AllowedTargets,
                    Authorization.IssuerReceipt);
            }

            private static bool ExactSet(
                IEnumerable<string> left,
                IEnumerable<string> right)
            {
                return new HashSet<string>(
                        left ?? Array.Empty<string>(),
                        StringComparer.Ordinal)
                    .SetEquals(right ?? Array.Empty<string>());
            }
        }
    }
}
