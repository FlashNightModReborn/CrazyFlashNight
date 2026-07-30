using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using CF7Launcher.AgentRuntime.Contracts;

namespace CF7Launcher.AgentRuntime.Security
{
    public enum ObservationGrantState
    {
        Active,
        Revoked,
        Expired
    }

    public sealed class ObservationTargetScope
    {
        public string TargetId { get; init; }
    }

    public sealed class ObservationGrantRequest
    {
        public string CredentialId { get; init; }
        public string ClientInstanceId { get; init; }
        public string SessionId { get; init; }
        public IReadOnlyCollection<ObservationTargetScope> Targets { get; init; }
        public IReadOnlyCollection<string> DataScopes { get; init; }
        public TimeSpan RequestedLifetime { get; init; } = TimeSpan.FromMinutes(5);
        public string ConsentReceipt { get; init; }
        public bool AllowEphemeralKeyframes { get; init; }
        public bool AllowPersistence { get; init; }
        public bool AllowExport { get; init; }
    }

    public sealed class ObservationGrant
    {
        internal ObservationGrant(
            string observationGrantId,
            PrincipalCredential credential,
            ObservationGrantRequest request,
            long issuedMonotonic,
            long expiresMonotonic)
        {
            ObservationGrantId = observationGrantId;
            OwnerClientId = credential.ClientInstanceId;
            SecurityPrincipalId = credential.SecurityPrincipalId;
            SessionMode = credential.SessionMode;
            SessionId = request.SessionId;
            TargetScope = Array.AsReadOnly(
                request.Targets
                    .Select(target => target.TargetId)
                    .Distinct(StringComparer.Ordinal)
                    .OrderBy(target => target, StringComparer.Ordinal)
                    .ToArray());
            DataScope = Array.AsReadOnly(
                (request.DataScopes ?? Array.Empty<string>())
                    .Where(scope => !string.IsNullOrWhiteSpace(scope))
                    .Distinct(StringComparer.Ordinal)
                    .OrderBy(scope => scope, StringComparer.Ordinal)
                    .ToArray());
            IssuedMonotonic = issuedMonotonic;
            ExpiresMonotonic = expiresMonotonic;
            ConsentReceipt = request.ConsentReceipt;
            AllowEphemeralKeyframes = request.AllowEphemeralKeyframes;
            AllowPersistence = request.AllowPersistence;
            AllowExport = request.AllowExport;
            State = ObservationGrantState.Active;
        }

        public string ObservationGrantId { get; }
        public string OwnerClientId { get; }
        public string SecurityPrincipalId { get; }
        public AgentSessionMode SessionMode { get; }
        public string SessionId { get; }
        public ReadOnlyCollection<string> TargetScope { get; }
        public ReadOnlyCollection<string> DataScope { get; }
        public long IssuedMonotonic { get; }
        public long ExpiresMonotonic { get; }
        public string ConsentReceipt { get; }
        public bool AllowEphemeralKeyframes { get; }
        public bool AllowPersistence { get; }
        public bool AllowExport { get; }
        public ObservationGrantState State { get; internal set; }
        public string RevokeReason { get; internal set; }
    }

    public sealed class ObservationGrantBroker
    {
        private static readonly TimeSpan DeveloperMaximum =
            TimeSpan.FromMinutes(15);
        private static readonly TimeSpan PlayerMaximum =
            TimeSpan.FromMinutes(5);
        private static readonly TimeSpan UnattendedMaximum =
            TimeSpan.FromMinutes(15);

        private readonly object _sync = new object();
        private readonly IAgentRuntimeClock _clock;
        private readonly PrincipalCredentialAuthority _credentials;
        private readonly IAgentTargetAuthority _targets;
        private readonly IAgentSessionModeAuthority _sessionModes;
        private readonly Dictionary<string, ObservationGrant> _grants =
            new Dictionary<string, ObservationGrant>(StringComparer.Ordinal);

        public ObservationGrantBroker(
            IAgentRuntimeClock clock,
            PrincipalCredentialAuthority credentials,
            IAgentTargetAuthority targets)
        {
            _clock = clock ?? throw new ArgumentNullException(nameof(clock));
            _credentials = credentials
                ?? throw new ArgumentNullException(nameof(credentials));
            _targets = targets
                ?? throw new ArgumentNullException(nameof(targets));
            _sessionModes = targets as IAgentSessionModeAuthority
                ?? throw new ArgumentException(
                    "Target authority must also own session mode.",
                    nameof(targets));
        }

        public ObservationGrant Issue(ObservationGrantRequest request)
        {
            if (request == null)
            {
                throw new ArgumentNullException(nameof(request));
            }
            PrincipalCredentialAuthority.RequireValue(
                request.SessionId,
                nameof(request.SessionId));
            if (!_credentials.TryResolveActive(
                    request.CredentialId,
                    request.ClientInstanceId,
                    out var credential,
                    out var credentialReason))
            {
                throw new InvalidOperationException(credentialReason);
            }
            RequireCompatibleSessionMode(
                request.SessionId,
                credential.SessionMode);
            if (credential.SessionMode == AgentSessionMode.PlayerAssist
                && !string.Equals(
                    credential.SelectedSessionId,
                    request.SessionId,
                    StringComparison.Ordinal))
            {
                throw new InvalidOperationException("session_scope_mismatch");
            }

            ObservationTargetScope[] targets =
                (request.Targets ?? Array.Empty<ObservationTargetScope>())
                    .Where(target => target != null)
                    .ToArray();
            if (targets.Length == 0
                || targets.Length
                    > AgentProtocolV1.MaximumTargetScopeItems
                || targets.Any(target =>
                    string.IsNullOrWhiteSpace(target.TargetId)))
            {
                throw new InvalidOperationException("target_scope_required");
            }
            if (targets.Any(target =>
                    !credential.AllowsTarget(target.TargetId)))
            {
                throw new InvalidOperationException("target_scope_denied");
            }
            foreach (ObservationTargetScope target in targets)
            {
                RequireRuntimeOwnedTarget(
                    request.SessionId,
                    target.TargetId);
            }

            string[] requestedDataScopes =
                (request.DataScopes ?? Array.Empty<string>())
                    .ToArray();
            if (requestedDataScopes.Length == 0)
            {
                throw new InvalidOperationException("data_scope_required");
            }
            if (requestedDataScopes.Any(
                    string.IsNullOrWhiteSpace)
                || requestedDataScopes
                    .Distinct(StringComparer.Ordinal)
                    .Count() != requestedDataScopes.Length)
            {
                throw new InvalidOperationException(
                    "data_scope_invalid");
            }
            string[] dataScopes = requestedDataScopes
                .OrderBy(scope => scope, StringComparer.Ordinal)
                .ToArray();
            foreach (string dataScope in dataScopes)
            {
                if (!ObservationDataScopesV1.All.Contains(dataScope)
                    || !credential.AllowsCapability(
                        "observe:" + dataScope))
                {
                    throw new InvalidOperationException("data_scope_denied");
                }
            }

            if (credential.SessionMode == AgentSessionMode.PlayerAssist
                && string.IsNullOrWhiteSpace(
                    request.ConsentReceipt))
            {
                throw new InvalidOperationException(
                    "observation_consent_required");
            }
            if (credential.SessionMode
                    == AgentSessionMode.PlayerAssist
                && !PrincipalCredentialAuthority
                    .IsExactIssuerReceipt(
                        credential,
                        request.ConsentReceipt))
            {
                throw new InvalidOperationException(
                    "observation_consent_invalid");
            }
            if (request.AllowPersistence
                && (!dataScopes.Contains(
                        ObservationDataScopesV1.RetentionPersist,
                        StringComparer.Ordinal)
                    || !credential.AllowsCapability("observation.persist")
                    || string.IsNullOrWhiteSpace(request.ConsentReceipt)))
            {
                throw new InvalidOperationException(
                    "retention_grant_required");
            }
            if (request.AllowExport
                && (!dataScopes.Contains(
                        ObservationDataScopesV1.DataExport,
                        StringComparer.Ordinal)
                    || !credential.AllowsCapability("observation.export")
                    || string.IsNullOrWhiteSpace(request.ConsentReceipt)))
            {
                throw new InvalidOperationException("export_grant_required");
            }

            long requestedLifetime = ToPositiveMilliseconds(
                request.RequestedLifetime);
            long modeMaximum = (long)GetMaximum(
                credential.SessionMode).TotalMilliseconds;
            long credentialRemaining = credential.ExpiresMonotonic
                - _clock.MonotonicMilliseconds;
            long actualLifetime = Math.Min(
                requestedLifetime,
                Math.Min(modeMaximum, credentialRemaining));
            if (actualLifetime <= 0)
            {
                throw new InvalidOperationException("credential_expired");
            }

            ObservationGrant normalized = new ObservationGrant(
                OpaqueIdGenerator.Create("obsgrant"),
                credential,
                new ObservationGrantRequest
                {
                    ClientInstanceId = request.ClientInstanceId,
                    SessionId = request.SessionId,
                    Targets = targets,
                    DataScopes = dataScopes,
                    ConsentReceipt =
                        credential.SessionMode
                            == AgentSessionMode.PlayerAssist
                            ? credential.IssuerReceipt
                            : request.ConsentReceipt,
                    AllowEphemeralKeyframes =
                        request.AllowEphemeralKeyframes,
                    AllowPersistence = request.AllowPersistence,
                    AllowExport = request.AllowExport
                },
                _clock.MonotonicMilliseconds,
                checked(_clock.MonotonicMilliseconds + actualLifetime));

            lock (_sync)
            {
                _grants.Add(
                    normalized.ObservationGrantId,
                    normalized);
            }
            return normalized;
        }

        public bool TryAuthorize(
            string grantId,
            string clientInstanceId,
            string securityPrincipalId,
            string sessionId,
            string targetId,
            string dataScope,
            out ObservationGrant grant,
            out string reasonCode)
        {
            lock (_sync)
            {
                if (!_grants.TryGetValue(grantId, out grant))
                {
                    reasonCode = "observation_grant_not_found";
                    return false;
                }
                if (grant.State == ObservationGrantState.Active
                    && _clock.MonotonicMilliseconds
                        >= grant.ExpiresMonotonic)
                {
                    grant.State = ObservationGrantState.Expired;
                    grant.RevokeReason = "observation_grant_expired";
                }
                if (grant.State != ObservationGrantState.Active)
                {
                    reasonCode = grant.RevokeReason
                        ?? "observation_grant_inactive";
                    return false;
                }
                if (!string.Equals(
                        grant.OwnerClientId,
                        clientInstanceId,
                        StringComparison.Ordinal)
                    || !string.Equals(
                        grant.SecurityPrincipalId,
                        securityPrincipalId,
                        StringComparison.Ordinal))
                {
                    reasonCode = "observation_grant_owner_mismatch";
                    return false;
                }
                if (!string.Equals(
                        grant.SessionId,
                        sessionId,
                        StringComparison.Ordinal))
                {
                    reasonCode = "session_scope_mismatch";
                    return false;
                }
                if (!TryRequireCompatibleSessionMode(
                        grant.SessionId,
                        grant.SessionMode,
                        out reasonCode))
                {
                    grant.State =
                        ObservationGrantState.Revoked;
                    grant.RevokeReason = reasonCode;
                    return false;
                }
                if (!grant.TargetScope.Contains(
                        targetId,
                        StringComparer.Ordinal))
                {
                    reasonCode = "target_scope_denied";
                    return false;
                }
                if (!_targets.TryResolve(
                        sessionId,
                        targetId,
                        out AgentTargetDescriptor descriptor,
                        out reasonCode))
                {
                    grant.State = ObservationGrantState.Revoked;
                    grant.RevokeReason =
                        reasonCode ?? "target_not_authoritative";
                    return false;
                }
                if (descriptor.SafetyKind
                    == AgentTargetSafetyKind.HumanOnlySecuritySurface)
                {
                    grant.State = ObservationGrantState.Revoked;
                    grant.RevokeReason =
                        "human_only_security_surface";
                    reasonCode = grant.RevokeReason;
                    return false;
                }
                if (!grant.DataScope.Contains(
                        dataScope,
                        StringComparer.Ordinal))
                {
                    reasonCode = "data_scope_denied";
                    return false;
                }

                reasonCode = null;
                return true;
            }
        }

        public bool TryAuthorizeSession(
            string grantId,
            string clientInstanceId,
            string securityPrincipalId,
            string sessionId,
            string dataScope,
            out ObservationGrant grant,
            out string reasonCode)
        {
            lock (_sync)
            {
                if (!TryResolveActiveOwnerLocked(
                        grantId,
                        clientInstanceId,
                        securityPrincipalId,
                        out grant,
                        out reasonCode))
                {
                    return false;
                }
                if (!string.Equals(
                        grant.SessionId,
                        sessionId,
                        StringComparison.Ordinal))
                {
                    reasonCode = "session_scope_mismatch";
                    return false;
                }
                if (!TryRequireCompatibleSessionMode(
                        grant.SessionId,
                        grant.SessionMode,
                        out reasonCode))
                {
                    grant.State =
                        ObservationGrantState.Revoked;
                    grant.RevokeReason = reasonCode;
                    return false;
                }
                if (!grant.DataScope.Contains(
                        dataScope,
                        StringComparer.Ordinal))
                {
                    reasonCode = "data_scope_denied";
                    return false;
                }
                reasonCode = null;
                return true;
            }
        }

        public bool RevokeOwned(
            string grantId,
            string clientInstanceId,
            string securityPrincipalId,
            string reason,
            out string reasonCode)
        {
            PrincipalCredentialAuthority.RequireValue(
                reason,
                nameof(reason));
            lock (_sync)
            {
                if (!TryResolveActiveOwnerLocked(
                        grantId,
                        clientInstanceId,
                        securityPrincipalId,
                        out ObservationGrant grant,
                        out reasonCode))
                {
                    return false;
                }
                grant.State = ObservationGrantState.Revoked;
                grant.RevokeReason = reason;
                reasonCode = null;
                return true;
            }
        }

        public int RevokeSession(string sessionId, string reason)
        {
            PrincipalCredentialAuthority.RequireValue(reason, nameof(reason));
            lock (_sync)
            {
                int count = 0;
                foreach (ObservationGrant grant in _grants.Values)
                {
                    if (grant.State == ObservationGrantState.Active
                        && string.Equals(
                            grant.SessionId,
                            sessionId,
                            StringComparison.Ordinal))
                    {
                        grant.State = ObservationGrantState.Revoked;
                        grant.RevokeReason = reason;
                        count++;
                    }
                }
                return count;
            }
        }

        public bool Revoke(string grantId, string reason)
        {
            PrincipalCredentialAuthority.RequireValue(reason, nameof(reason));
            lock (_sync)
            {
                if (!_grants.TryGetValue(grantId, out var grant)
                    || grant.State != ObservationGrantState.Active)
                {
                    return false;
                }
                grant.State = ObservationGrantState.Revoked;
                grant.RevokeReason = reason;
                return true;
            }
        }

        private static TimeSpan GetMaximum(AgentSessionMode mode)
        {
            return mode switch
            {
                AgentSessionMode.DeveloperInteractive => DeveloperMaximum,
                AgentSessionMode.PlayerAssist => PlayerMaximum,
                AgentSessionMode.UnattendedTest => UnattendedMaximum,
                _ => throw new ArgumentOutOfRangeException(nameof(mode))
            };
        }

        private static long ToPositiveMilliseconds(TimeSpan duration)
        {
            if (duration <= TimeSpan.Zero)
            {
                throw new ArgumentOutOfRangeException(nameof(duration));
            }
            return (long)Math.Ceiling(duration.TotalMilliseconds);
        }

        private void RequireRuntimeOwnedTarget(
            string sessionId,
            string targetId)
        {
            if (!_targets.TryResolve(
                    sessionId,
                    targetId,
                    out AgentTargetDescriptor descriptor,
                    out string reasonCode))
            {
                throw new InvalidOperationException(
                    reasonCode ?? "target_not_authoritative");
            }
            if (descriptor.SafetyKind
                == AgentTargetSafetyKind.HumanOnlySecuritySurface)
            {
                throw new InvalidOperationException(
                    "human_only_security_surface");
            }
        }

        private void RequireCompatibleSessionMode(
            string sessionId,
            AgentSessionMode credentialMode)
        {
            if (!TryRequireCompatibleSessionMode(
                    sessionId,
                    credentialMode,
                    out string reasonCode))
            {
                throw new InvalidOperationException(reasonCode);
            }
        }

        private bool TryRequireCompatibleSessionMode(
            string sessionId,
            AgentSessionMode credentialMode,
            out string reasonCode)
        {
            if (!_sessionModes.TryResolveSessionMode(
                    sessionId,
                    out SessionMode sessionMode,
                    out reasonCode))
            {
                return false;
            }
            if (!AgentSessionModeCompatibility.IsCompatible(
                    credentialMode,
                    sessionMode))
            {
                reasonCode = "session_mismatch";
                return false;
            }
            reasonCode = null;
            return true;
        }

        private bool TryResolveActiveOwnerLocked(
            string grantId,
            string clientInstanceId,
            string securityPrincipalId,
            out ObservationGrant grant,
            out string reasonCode)
        {
            if (!_grants.TryGetValue(
                    grantId ?? string.Empty,
                    out grant))
            {
                reasonCode = "observation_grant_not_found";
                return false;
            }
            if (grant.State == ObservationGrantState.Active
                && _clock.MonotonicMilliseconds
                    >= grant.ExpiresMonotonic)
            {
                grant.State = ObservationGrantState.Expired;
                grant.RevokeReason =
                    "observation_grant_expired";
            }
            if (grant.State != ObservationGrantState.Active)
            {
                reasonCode = grant.RevokeReason
                    ?? "observation_grant_inactive";
                return false;
            }
            if (!string.Equals(
                    grant.OwnerClientId,
                    clientInstanceId,
                    StringComparison.Ordinal)
                || !string.Equals(
                    grant.SecurityPrincipalId,
                    securityPrincipalId,
                    StringComparison.Ordinal))
            {
                reasonCode =
                    "observation_grant_owner_mismatch";
                return false;
            }
            reasonCode = null;
            return true;
        }
    }
}
