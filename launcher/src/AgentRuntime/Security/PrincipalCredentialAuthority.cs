using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using System.Security.Cryptography;
using System.Text;

namespace CF7Launcher.AgentRuntime.Security
{
    public enum AgentPrincipalKind
    {
        DeveloperAgent,
        UnattendedTestRunner,
        WingsPersona
    }

    public enum AgentSessionMode
    {
        DeveloperInteractive,
        UnattendedTest,
        PlayerAssist
    }

    public enum CredentialState
    {
        Active,
        Rotated,
        Revoked,
        Expired
    }

    public sealed class DeveloperEnrollmentEvidence
    {
        public string ClientInstanceId { get; init; }
        public string EnrollmentReceipt { get; init; }
        public IReadOnlyCollection<string> AllowedCapabilities { get; init; }
        public IReadOnlyCollection<string> AllowedTargets { get; init; }
        public TimeSpan RequestedLifetime { get; init; } = TimeSpan.FromHours(8);
    }

    public sealed class UnattendedCredentialEvidence
    {
        public string ClientInstanceId { get; init; }
        public string RunnerPolicyId { get; init; }
        public uint RunnerProcessId { get; init; }
        public DateTimeOffset RunnerProcessStartTimeUtc
        {
            get;
            init;
        }
        public string RunnerExecutablePath { get; init; }
        public string RunnerExecutableSha256 { get; init; }
        public long RunnerExecutableSize { get; init; }
        public string RuntimeExecutablePath { get; init; }
        public string RequestNonce { get; init; }
        public string BuildIdentity { get; init; }
        public string PayloadClosure { get; init; }
        public string SessionId { get; init; }
        public string AttemptId { get; init; }
        public ulong AttemptGeneration { get; init; }
        public string Slot { get; init; }
        public string CanonicalSavePath { get; init; }
        public long RunnerDeadlineMonotonic { get; init; }
        public IReadOnlyCollection<string> AllowedCapabilities { get; init; }
        public IReadOnlyCollection<string> AllowedTargets { get; init; }
    }

    public sealed class PlayerAssistCredentialEvidence
    {
        public string ClientInstanceId { get; init; }
        public string ConsentReceipt { get; init; }
        public string SelectedSessionId { get; init; }
        public IReadOnlyCollection<string> AllowedCapabilities { get; init; }
        public IReadOnlyCollection<string> AllowedTargets { get; init; }
        public TimeSpan RequestedLifetime { get; init; } = TimeSpan.FromMinutes(15);
    }

    public sealed class PrincipalCredential
    {
        internal PrincipalCredential(
            string credentialId,
            string securityPrincipalId,
            string clientInstanceId,
            AgentPrincipalKind principalKind,
            AgentSessionMode sessionMode,
            long generation,
            long issuedMonotonic,
            long expiresMonotonic,
            DateTimeOffset issuedUtc,
            IEnumerable<string> allowedCapabilities,
            IEnumerable<string> allowedTargets,
            string issuerReceipt,
            string selectedSessionId,
            string buildIdentity,
            string attemptId,
            string slot)
        {
            CredentialId = credentialId;
            SecurityPrincipalId = securityPrincipalId;
            ClientInstanceId = clientInstanceId;
            PrincipalKind = principalKind;
            SessionMode = sessionMode;
            Generation = generation;
            IssuedMonotonic = issuedMonotonic;
            ExpiresMonotonic = expiresMonotonic;
            IssuedUtc = issuedUtc;
            AllowedCapabilities = ToFrozenSet(allowedCapabilities);
            AllowedTargets = ToFrozenSet(allowedTargets);
            IssuerReceipt = issuerReceipt;
            SelectedSessionId = selectedSessionId;
            BuildIdentity = buildIdentity;
            AttemptId = attemptId;
            Slot = slot;
            State = CredentialState.Active;
        }

        public string CredentialId { get; }
        public string SecurityPrincipalId { get; }
        public string ClientInstanceId { get; }
        public AgentPrincipalKind PrincipalKind { get; }
        public AgentSessionMode SessionMode { get; }
        public long Generation { get; }
        public long IssuedMonotonic { get; }
        public long ExpiresMonotonic { get; }
        public DateTimeOffset IssuedUtc { get; }
        public ReadOnlyCollection<string> AllowedCapabilities { get; }
        public ReadOnlyCollection<string> AllowedTargets { get; }
        public string IssuerReceipt { get; }
        public string SelectedSessionId { get; }
        public string BuildIdentity { get; }
        public string AttemptId { get; }
        public string Slot { get; }
        public CredentialState State { get; internal set; }
        public string RevokeReason { get; internal set; }

        public bool AllowsCapability(string capability)
        {
            return AllowedCapabilities.Contains(
                capability,
                StringComparer.Ordinal);
        }

        public bool AllowsTarget(string targetId)
        {
            return AllowedTargets.Contains("*", StringComparer.Ordinal)
                || AllowedTargets.Contains(targetId, StringComparer.Ordinal);
        }

        private static ReadOnlyCollection<string> ToFrozenSet(
            IEnumerable<string> values)
        {
            string[] result = (values ?? Array.Empty<string>())
                .Where(value => !string.IsNullOrWhiteSpace(value))
                .Distinct(StringComparer.Ordinal)
                .OrderBy(value => value, StringComparer.Ordinal)
                .ToArray();
            return Array.AsReadOnly(result);
        }
    }

    /// <summary>
    /// Principal kinds can only be issued through a trusted, mode-specific
    /// evidence path. There is deliberately no generic client-selected issuer.
    /// </summary>
    public sealed class PrincipalCredentialAuthority
    {
        private static readonly TimeSpan MaximumDeveloperLifetime =
            TimeSpan.FromHours(8);
        private static readonly TimeSpan MaximumPlayerLifetime =
            TimeSpan.FromMinutes(15);

        private readonly object _sync = new object();
        private readonly IAgentRuntimeClock _clock;
        private readonly IPrincipalEnrollmentVerifier _enrollmentVerifier;
        private readonly Dictionary<string, PrincipalCredential> _credentials =
            new Dictionary<string, PrincipalCredential>(StringComparer.Ordinal);

        public PrincipalCredentialAuthority(
            IAgentRuntimeClock clock,
            IPrincipalEnrollmentVerifier enrollmentVerifier)
        {
            _clock = clock ?? throw new ArgumentNullException(nameof(clock));
            _enrollmentVerifier = enrollmentVerifier
                ?? throw new ArgumentNullException(
                    nameof(enrollmentVerifier));
        }

        public PrincipalCredential IssueDeveloper(
            DeveloperEnrollmentEvidence evidence)
        {
            if (evidence == null)
            {
                throw new ArgumentNullException(nameof(evidence));
            }

            RequireClient(evidence.ClientInstanceId);
            if (!_enrollmentVerifier.TryVerifyDeveloper(
                    evidence,
                    out VerifiedPrincipalAuthorization authorization,
                    out string reasonCode))
            {
                throw new InvalidOperationException(
                    reasonCode
                    ?? "developer_enrollment_evidence_invalid");
            }
            ValidateAuthorization(authorization);
            long lifetime = BoundLifetime(
                evidence.RequestedLifetime,
                MaximumDeveloperLifetime,
                nameof(evidence.RequestedLifetime));

            return Store(new PrincipalCredential(
                OpaqueIdGenerator.Create("cred"),
                OpaqueIdGenerator.Create("principal"),
                evidence.ClientInstanceId,
                AgentPrincipalKind.DeveloperAgent,
                AgentSessionMode.DeveloperInteractive,
                1,
                _clock.MonotonicMilliseconds,
                checked(_clock.MonotonicMilliseconds + lifetime),
                _clock.UtcNow,
                authorization.AllowedCapabilities,
                authorization.AllowedTargets,
                authorization.IssuerReceipt,
                null,
                null,
                null,
                null));
        }

        public PrincipalCredential IssueUnattended(
            UnattendedCredentialEvidence evidence)
        {
            if (evidence == null)
            {
                throw new ArgumentNullException(nameof(evidence));
            }

            RequireClient(evidence.ClientInstanceId);
            RequireValue(
                evidence.RunnerPolicyId,
                nameof(evidence.RunnerPolicyId));
            if (evidence.RunnerProcessId == 0)
            {
                throw new InvalidOperationException(
                    "The unattended runner process is invalid.");
            }
            if (evidence.RunnerProcessStartTimeUtc
                    == default)
            {
                throw new InvalidOperationException(
                    "The unattended runner process start time is invalid.");
            }
            RequireValue(
                evidence.RunnerExecutablePath,
                nameof(evidence.RunnerExecutablePath));
            RequireValue(
                evidence.RunnerExecutableSha256,
                nameof(evidence.RunnerExecutableSha256));
            if (evidence.RunnerExecutableSize <= 0)
            {
                throw new InvalidOperationException(
                    "The unattended runner executable size is invalid.");
            }
            RequireValue(
                evidence.RuntimeExecutablePath,
                nameof(evidence.RuntimeExecutablePath));
            RequireValue(
                evidence.RequestNonce,
                nameof(evidence.RequestNonce));
            RequireValue(evidence.BuildIdentity, nameof(evidence.BuildIdentity));
            RequireValue(evidence.PayloadClosure, nameof(evidence.PayloadClosure));
            RequireValue(evidence.SessionId, nameof(evidence.SessionId));
            RequireValue(evidence.AttemptId, nameof(evidence.AttemptId));
            if (evidence.AttemptGeneration == 0)
            {
                throw new InvalidOperationException(
                    "The unattended attempt generation is invalid.");
            }
            RequireValue(evidence.Slot, nameof(evidence.Slot));
            RequireValue(
                evidence.CanonicalSavePath,
                nameof(evidence.CanonicalSavePath));
            if (!evidence.Slot.StartsWith(
                    "cf7_agent_",
                    StringComparison.Ordinal))
            {
                throw new InvalidOperationException(
                    "Unattended credentials are restricted to cf7_agent_* slots.");
            }
            if (evidence.RunnerDeadlineMonotonic
                <= _clock.MonotonicMilliseconds)
            {
                throw new InvalidOperationException(
                    "The unattended runner deadline has already expired.");
            }
            if (!_enrollmentVerifier.TryVerifyUnattended(
                    evidence,
                    out VerifiedPrincipalAuthorization authorization,
                    out string reasonCode))
            {
                throw new InvalidOperationException(
                    reasonCode
                    ?? "unattended_allow_list_evidence_invalid");
            }
            ValidateAuthorization(authorization);

            return Store(new PrincipalCredential(
                OpaqueIdGenerator.Create("cred"),
                OpaqueIdGenerator.Create("principal"),
                evidence.ClientInstanceId,
                AgentPrincipalKind.UnattendedTestRunner,
                AgentSessionMode.UnattendedTest,
                1,
                _clock.MonotonicMilliseconds,
                evidence.RunnerDeadlineMonotonic,
                _clock.UtcNow,
                authorization.AllowedCapabilities,
                authorization.AllowedTargets,
                authorization.IssuerReceipt,
                null,
                evidence.BuildIdentity,
                evidence.AttemptId,
                evidence.Slot));
        }

        public PrincipalCredential IssuePlayerAssist(
            PlayerAssistCredentialEvidence evidence)
        {
            if (evidence == null)
            {
                throw new ArgumentNullException(nameof(evidence));
            }

            RequireClient(evidence.ClientInstanceId);
            RequireValue(
                evidence.SelectedSessionId,
                nameof(evidence.SelectedSessionId));
            if (!_enrollmentVerifier.TryVerifyPlayerAssist(
                    evidence,
                    out VerifiedPrincipalAuthorization authorization,
                    out string reasonCode))
            {
                throw new InvalidOperationException(
                    reasonCode
                    ?? "player_consent_evidence_invalid");
            }
            ValidateAuthorization(authorization);
            long lifetime = BoundLifetime(
                evidence.RequestedLifetime,
                MaximumPlayerLifetime,
                nameof(evidence.RequestedLifetime));

            return Store(new PrincipalCredential(
                OpaqueIdGenerator.Create("cred"),
                OpaqueIdGenerator.Create("principal"),
                evidence.ClientInstanceId,
                AgentPrincipalKind.WingsPersona,
                AgentSessionMode.PlayerAssist,
                1,
                _clock.MonotonicMilliseconds,
                checked(_clock.MonotonicMilliseconds + lifetime),
                _clock.UtcNow,
                authorization.AllowedCapabilities,
                authorization.AllowedTargets,
                authorization.IssuerReceipt,
                evidence.SelectedSessionId,
                null,
                null,
                null));
        }

        public PrincipalCredential Rotate(string credentialId)
        {
            lock (_sync)
            {
                PrincipalCredential current = ResolveActiveLocked(
                    credentialId,
                    null);
                if (current.SessionMode
                    == AgentSessionMode.UnattendedTest)
                {
                    throw new InvalidOperationException(
                        "unattended_credential_rotation_denied");
                }
                current.State = CredentialState.Rotated;
                current.RevokeReason = "credential_rotated";

                long remaining = current.ExpiresMonotonic
                    - _clock.MonotonicMilliseconds;
                if (remaining <= 0)
                {
                    throw new InvalidOperationException(
                        "Cannot rotate an expired credential.");
                }

                PrincipalCredential replacement = new PrincipalCredential(
                    OpaqueIdGenerator.Create("cred"),
                    current.SecurityPrincipalId,
                    current.ClientInstanceId,
                    current.PrincipalKind,
                    current.SessionMode,
                    checked(current.Generation + 1),
                    _clock.MonotonicMilliseconds,
                    checked(_clock.MonotonicMilliseconds + remaining),
                    _clock.UtcNow,
                    current.AllowedCapabilities,
                    current.AllowedTargets,
                    current.IssuerReceipt,
                    current.SelectedSessionId,
                    current.BuildIdentity,
                    current.AttemptId,
                    current.Slot);
                _credentials.Add(replacement.CredentialId, replacement);
                return replacement;
            }
        }

        public bool Revoke(string credentialId, string reason)
        {
            RequireValue(reason, nameof(reason));
            lock (_sync)
            {
                if (!_credentials.TryGetValue(credentialId, out var credential)
                    || credential.State != CredentialState.Active)
                {
                    return false;
                }

                credential.State = CredentialState.Revoked;
                credential.RevokeReason = reason;
                return true;
            }
        }

        public bool TryResolveActive(
            string credentialId,
            string clientInstanceId,
            out PrincipalCredential credential,
            out string reasonCode)
        {
            lock (_sync)
            {
                try
                {
                    credential = ResolveActiveLocked(
                        credentialId,
                        clientInstanceId);
                    reasonCode = null;
                    return true;
                }
                catch (InvalidOperationException error)
                {
                    credential = null;
                    reasonCode = error.Message;
                    return false;
                }
            }
        }

        private PrincipalCredential Store(PrincipalCredential credential)
        {
            lock (_sync)
            {
                _credentials.Add(credential.CredentialId, credential);
                return credential;
            }
        }

        private PrincipalCredential ResolveActiveLocked(
            string credentialId,
            string clientInstanceId)
        {
            if (string.IsNullOrWhiteSpace(credentialId)
                || !_credentials.TryGetValue(credentialId, out var credential))
            {
                throw new InvalidOperationException("credential_not_found");
            }
            if (clientInstanceId != null
                && !string.Equals(
                    credential.ClientInstanceId,
                    clientInstanceId,
                    StringComparison.Ordinal))
            {
                throw new InvalidOperationException("credential_owner_mismatch");
            }
            if (credential.State != CredentialState.Active)
            {
                throw new InvalidOperationException("credential_inactive");
            }
            if (_clock.MonotonicMilliseconds >= credential.ExpiresMonotonic)
            {
                credential.State = CredentialState.Expired;
                credential.RevokeReason = "credential_expired";
                throw new InvalidOperationException("credential_expired");
            }
            return credential;
        }

        private static long BoundLifetime(
            TimeSpan requested,
            TimeSpan maximum,
            string parameterName)
        {
            if (requested <= TimeSpan.Zero)
            {
                throw new ArgumentOutOfRangeException(parameterName);
            }
            return (long)Math.Min(
                requested.TotalMilliseconds,
                maximum.TotalMilliseconds);
        }

        private static void ValidateAuthorization(
            VerifiedPrincipalAuthorization authorization)
        {
            if (authorization == null
                || authorization.AllowedCapabilities.Count == 0
                || authorization.AllowedTargets.Count == 0)
            {
                throw new InvalidOperationException(
                    "verified_principal_scope_empty");
            }
        }

        private static void RequireClient(string clientInstanceId)
        {
            RequireValue(clientInstanceId, nameof(clientInstanceId));
        }

        internal static void RequireValue(string value, string parameterName)
        {
            if (string.IsNullOrWhiteSpace(value))
            {
                throw new ArgumentException(
                    "A non-empty protocol value is required.",
                    parameterName);
            }
        }

        internal static bool IsExactIssuerReceipt(
            PrincipalCredential credential,
            string presentedReceipt)
        {
            string expected = credential?.IssuerReceipt;
            if (string.IsNullOrWhiteSpace(expected)
                || string.IsNullOrWhiteSpace(
                    presentedReceipt)
                || expected.Length
                    != presentedReceipt.Length
                || expected.Length > 256)
            {
                return false;
            }
            return CryptographicOperations.FixedTimeEquals(
                Encoding.UTF8.GetBytes(expected),
                Encoding.UTF8.GetBytes(
                    presentedReceipt));
        }
    }
}
