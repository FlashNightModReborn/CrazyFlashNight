using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using CF7Launcher.AgentRuntime.Contracts;

namespace CF7Launcher.AgentRuntime.Security
{
    public enum WriteLeaseKind
    {
        GuiInput,
        DomainTransaction,
        Shutdown
    }

    public enum WriteLeaseState
    {
        Active,
        Released,
        Revoked,
        Expired,
        Consumed
    }

    public sealed class WriteLeaseRequest
    {
        public string CredentialId { get; init; }
        public string ClientInstanceId { get; init; }
        public string SessionId { get; init; }
        public ulong LifecycleGeneration { get; init; }
        public WriteLeaseKind Kind { get; init; }
        public IReadOnlyCollection<string> Capabilities { get; init; }
        public IReadOnlyCollection<string> TargetScope { get; init; }
        public TimeSpan RequestedLifetime { get; init; }
        public int RequestedActionLimit { get; init; }
        public string ConsentReceipt { get; init; }
        public string ArgumentBoundsHash { get; init; }
        public string PreviewHash { get; init; }
        public string ExpectedRevision { get; init; }
        public string Operation { get; init; }
    }

    public sealed class WriteLease
    {
        internal WriteLease(
            string leaseId,
            PrincipalCredential credential,
            WriteLeaseRequest request,
            long issuedMonotonic,
            long expiresMonotonic,
            int actionLimit)
        {
            LeaseId = leaseId;
            CredentialId = credential.CredentialId;
            OwnerClientId = credential.ClientInstanceId;
            SecurityPrincipalId = credential.SecurityPrincipalId;
            SessionMode = credential.SessionMode;
            SessionId = request.SessionId;
            LifecycleGeneration = request.LifecycleGeneration;
            Kind = request.Kind;
            Capabilities = Freeze(request.Capabilities);
            TargetScope = Freeze(request.TargetScope);
            IssuedMonotonic = issuedMonotonic;
            ExpiresMonotonic = expiresMonotonic;
            RenewAfterMonotonic = issuedMonotonic
                + Math.Max(1, (expiresMonotonic - issuedMonotonic) / 2);
            ActionLimit = actionLimit;
            ConsentReceipt = request.ConsentReceipt;
            ArgumentBoundsHash =
                request.ArgumentBoundsHash;
            PreviewHash = request.PreviewHash;
            ExpectedRevision = request.ExpectedRevision;
            Operation = request.Operation;
            State = WriteLeaseState.Active;
        }

        public string LeaseId { get; }
        public string CredentialId { get; }
        public string OwnerClientId { get; }
        public string SecurityPrincipalId { get; }
        public AgentSessionMode SessionMode { get; }
        public string SessionId { get; }
        public ulong LifecycleGeneration { get; }
        public WriteLeaseKind Kind { get; }
        public ReadOnlyCollection<string> Capabilities { get; }
        public ReadOnlyCollection<string> TargetScope { get; }
        public long IssuedMonotonic { get; }
        public long ExpiresMonotonic { get; internal set; }
        public long RenewAfterMonotonic { get; internal set; }
        public int ActionLimit { get; }
        public int ActionsConsumed { get; internal set; }
        public int RenewalCount { get; internal set; }
        public string ConsentReceipt { get; }
        public string ArgumentBoundsHash { get; }
        public string PreviewHash { get; }
        public string ExpectedRevision { get; }
        public string Operation { get; }
        public WriteLeaseState State { get; internal set; }
        public string RevokeReason { get; internal set; }
        internal bool ActionExecutionPending { get; set; }
        internal bool ShutdownDeliveryPending { get; set; }
        internal bool ShutdownDeliveryWriteOwned { get; set; }
        internal bool ShutdownDeliveryCommitted { get; set; }

        private static ReadOnlyCollection<string> Freeze(
            IEnumerable<string> values)
        {
            return Array.AsReadOnly(
                (values ?? Array.Empty<string>())
                    .Where(value => !string.IsNullOrWhiteSpace(value))
                    .Distinct(StringComparer.Ordinal)
                    .OrderBy(value => value, StringComparer.Ordinal)
                    .ToArray());
        }
    }

    public sealed class WriteLeaseBroker
    {
        private const int PlayerGuiActionHardCap = 8;
        private const int DeveloperActionHardCap = 1024;
        private const int UnattendedActionHardCap = 10000;
        private const int TerminalLeaseTombstoneCapacity = 256;
        private const int CommittedShutdownSessionCapacity = 64;

        private static readonly TimeSpan PlayerGuiLifetimeHardCap =
            TimeSpan.FromSeconds(30);
        private static readonly TimeSpan PlayerConsentCumulativeHardCap =
            TimeSpan.FromSeconds(120);
        private static readonly TimeSpan PlayerDomainLifetimeHardCap =
            TimeSpan.FromSeconds(60);
        private static readonly TimeSpan ShutdownLifetimeHardCap =
            TimeSpan.FromSeconds(30);
        private static readonly TimeSpan DeveloperLifetimeHardCap =
            TimeSpan.FromMinutes(5);

        private readonly object _sync = new object();
        private readonly IAgentRuntimeClock _clock;
        private readonly PrincipalCredentialAuthority _credentials;
        private readonly IAgentTargetAuthority _targets;
        private readonly IAgentSessionModeAuthority _sessionModes;
        // Only active leases and terminal leases whose execution/delivery
        // reservation is still draining belong in the live table.
        private readonly Dictionary<string, WriteLease> _leases =
            new Dictionary<string, WriteLease>(StringComparer.Ordinal);
        private readonly Dictionary<string, WriteLease>
            _terminalLeaseTombstones =
                new Dictionary<string, WriteLease>(
                    StringComparer.Ordinal);
        private readonly Queue<string> _terminalLeaseOrder =
            new Queue<string>();
        private readonly Dictionary<string, string> _activeLeaseBySession =
            new Dictionary<string, string>(StringComparer.Ordinal);
        private readonly Dictionary<string, string> _executingLeaseBySession =
            new Dictionary<string, string>(StringComparer.Ordinal);
        // Session IDs identify launcher lifecycles. A committed shutdown may
        // leave the live/tombstone tables, but this independent latch must
        // never be evicted in a way that re-enables a writer. If the exact
        // bounded set fills, the broker degrades to a global fail-closed latch.
        private readonly HashSet<string> _committedShutdownSessions =
            new HashSet<string>(StringComparer.Ordinal);
        private bool _committedShutdownLatchOverflowed;
        private readonly Dictionary<string, long> _playerConsentGrantedMs =
            new Dictionary<string, long>(StringComparer.Ordinal);
        private int _lastHumanOverrideCandidateCount;

        internal static int TerminalLeaseTombstoneCapacityForTests =>
            TerminalLeaseTombstoneCapacity;

        internal static int CommittedShutdownSessionCapacityForTests =>
            CommittedShutdownSessionCapacity;

        internal int LiveLeaseCountForTests
        {
            get
            {
                lock (_sync) { return _leases.Count; }
            }
        }

        internal int TerminalLeaseTombstoneCountForTests
        {
            get
            {
                lock (_sync)
                {
                    return _terminalLeaseTombstones.Count;
                }
            }
        }

        internal int CommittedShutdownSessionCountForTests
        {
            get
            {
                lock (_sync)
                {
                    return _committedShutdownSessions.Count;
                }
            }
        }

        internal bool CommittedShutdownLatchOverflowedForTests
        {
            get
            {
                lock (_sync)
                {
                    return _committedShutdownLatchOverflowed;
                }
            }
        }

        internal int LastHumanOverrideCandidateCountForTests
        {
            get
            {
                lock (_sync)
                {
                    return _lastHumanOverrideCandidateCount;
                }
            }
        }

        public WriteLeaseBroker(
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

        public WriteLease Acquire(WriteLeaseRequest request)
        {
            if (request == null)
            {
                throw new ArgumentNullException(nameof(request));
            }
            PrincipalCredentialAuthority.RequireValue(
                request.SessionId,
                nameof(request.SessionId));
            if (request.LifecycleGeneration == 0)
            {
                throw new InvalidOperationException(
                    "stale_observation");
            }
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
            if (credential.SessionMode == AgentSessionMode.PlayerAssist
                && request.Kind == WriteLeaseKind.Shutdown)
            {
                // Phase one has no issuer for a neutral, per-invocation
                // player exit consent. A general enrollment receipt cannot
                // authorize process termination.
                throw new InvalidOperationException("consent_required");
            }

            string[] capabilities = NormalizeRequired(
                request.Capabilities,
                "capability_scope_required");
            string[] targets = NormalizeRequired(
                request.TargetScope,
                "target_scope_required");
            ValidateKindBinding(
                request,
                capabilities,
                targets);
            if (targets.Length
                > AgentProtocolV1.MaximumTargetScopeItems)
            {
                throw new InvalidOperationException(
                    "target_scope_denied");
            }
            if (capabilities.Any(capability =>
                    !credential.AllowsCapability(capability)))
            {
                throw new InvalidOperationException(
                    "capability_scope_denied");
            }
            if (targets.Any(target => !credential.AllowsTarget(target)))
            {
                throw new InvalidOperationException("target_scope_denied");
            }
            foreach (string target in targets)
            {
                RequireRuntimeOwnedTarget(
                    request.SessionId,
                    target,
                    request.Kind == WriteLeaseKind.Shutdown
                        ? SurfaceKind.Launcher
                        : null);
            }

            long requestedMs = ToPositiveMilliseconds(
                request.RequestedLifetime);
            int actionLimit;
            long lifetimeMs;
            ValidateModeAndNormalize(
                credential,
                request,
                targets,
                requestedMs,
                out lifetimeMs,
                out actionLimit);

            long credentialRemaining = credential.ExpiresMonotonic
                - _clock.MonotonicMilliseconds;
            lifetimeMs = Math.Min(lifetimeMs, credentialRemaining);
            if (lifetimeMs <= 0)
            {
                throw new InvalidOperationException("credential_expired");
            }

            lock (_sync)
            {
                if (_committedShutdownLatchOverflowed
                    || _committedShutdownSessions.Contains(
                        request.SessionId))
                {
                    throw new InvalidOperationException(
                        "write_lease_already_held");
                }
                ExpireSessionLeaseLocked(request.SessionId);
                if (_activeLeaseBySession.ContainsKey(request.SessionId)
                    || _executingLeaseBySession.ContainsKey(
                        request.SessionId))
                {
                    throw new InvalidOperationException(
                        "write_lease_already_held");
                }

                if (credential.SessionMode == AgentSessionMode.PlayerAssist
                    && request.Kind == WriteLeaseKind.GuiInput)
                {
                    string consentKey = PlayerConsentKey(
                        credential.SecurityPrincipalId,
                        credential.IssuerReceipt);
                    _playerConsentGrantedMs.TryGetValue(
                        consentKey,
                        out long alreadyGranted);
                    if (alreadyGranted + lifetimeMs
                        > (long)PlayerConsentCumulativeHardCap.TotalMilliseconds)
                    {
                        throw new InvalidOperationException(
                            "consent_cumulative_limit");
                    }
                    _playerConsentGrantedMs[consentKey] =
                        alreadyGranted + lifetimeMs;
                }

                WriteLease lease = new WriteLease(
                    OpaqueIdGenerator.Create("lease"),
                    credential,
                    new WriteLeaseRequest
                    {
                        SessionId = request.SessionId,
                        LifecycleGeneration =
                            request.LifecycleGeneration,
                        Kind = request.Kind,
                        Capabilities = capabilities,
                        TargetScope = targets,
                        ConsentReceipt =
                            credential.SessionMode
                                == AgentSessionMode.PlayerAssist
                                ? credential.IssuerReceipt
                                : request.ConsentReceipt,
                        ArgumentBoundsHash =
                            request.ArgumentBoundsHash,
                        PreviewHash = request.PreviewHash,
                        ExpectedRevision = request.ExpectedRevision,
                        Operation = request.Kind
                                == WriteLeaseKind.Shutdown
                            ? AgentCapabilitiesV1.SessionShutdown
                            : request.Operation
                    },
                    _clock.MonotonicMilliseconds,
                    checked(_clock.MonotonicMilliseconds + lifetimeMs),
                    actionLimit);
                _leases.Add(lease.LeaseId, lease);
                _activeLeaseBySession.Add(lease.SessionId, lease.LeaseId);
                return lease;
            }
        }

        public bool TryConsumeAction(
            string leaseId,
            string clientInstanceId,
            string securityPrincipalId,
            out WriteLease lease,
            out string reasonCode)
        {
            lock (_sync)
            {
                if (!TryResolveActiveLocked(
                        leaseId,
                        clientInstanceId,
                        securityPrincipalId,
                        out lease,
                        out reasonCode))
                {
                    return false;
                }
                if (!TryRequireCompatibleSessionMode(
                        lease.SessionId,
                        lease.SessionMode,
                        out reasonCode))
                {
                    RevokeLocked(
                        lease,
                        reasonCode,
                        WriteLeaseState.Revoked);
                    return false;
                }
                if (lease.Kind == WriteLeaseKind.Shutdown)
                {
                    reasonCode = "operation_invalid";
                    return false;
                }
                foreach (string target in lease.TargetScope)
                {
                    if (!TryResolveRuntimeOwnedTarget(
                            lease.SessionId,
                            target,
                            null,
                            out reasonCode))
                    {
                        RevokeLocked(
                            lease,
                            reasonCode,
                            WriteLeaseState.Revoked);
                        return false;
                    }
                }

                lease.ActionsConsumed++;
                if (lease.ActionsConsumed >= lease.ActionLimit)
                {
                    lease.State = WriteLeaseState.Consumed;
                    lease.RevokeReason = "action_limit_consumed";
                    RemoveActiveLeaseLocked(lease);
                    RetireTerminalLeaseLocked(lease);
                }
                reasonCode = null;
                return true;
            }
        }

        public bool TryConsumeAction(
            string leaseId,
            string clientInstanceId,
            string securityPrincipalId,
            string sessionId,
            string requiredCapability,
            string targetId,
            string operation,
            out WriteLease lease,
            out string reasonCode)
        {
            lock (_sync)
            {
                if (!TryResolveActiveLocked(
                        leaseId,
                        clientInstanceId,
                        securityPrincipalId,
                        out lease,
                        out reasonCode))
                {
                    return false;
                }
                if (!TryRequireCompatibleSessionMode(
                        lease.SessionId,
                        lease.SessionMode,
                        out reasonCode))
                {
                    RevokeLocked(
                        lease,
                        reasonCode,
                        WriteLeaseState.Revoked);
                    return false;
                }
                if (!string.Equals(
                        lease.SessionId,
                        sessionId,
                        StringComparison.Ordinal))
                {
                    reasonCode = "session_scope_mismatch";
                    return false;
                }
                if (!lease.Capabilities.Contains(
                        requiredCapability,
                        StringComparer.Ordinal))
                {
                    reasonCode = "capability_scope_denied";
                    return false;
                }
                if (!lease.TargetScope.Contains(
                        targetId,
                        StringComparer.Ordinal))
                {
                    reasonCode = "target_scope_denied";
                    return false;
                }
                bool shutdownOperation = string.Equals(
                    operation,
                    AgentCapabilitiesV1.SessionShutdown,
                    StringComparison.Ordinal);
                if ((lease.Kind == WriteLeaseKind.Shutdown)
                        != shutdownOperation
                    || lease.Kind
                            == WriteLeaseKind.DomainTransaction
                        && !string.Equals(
                            lease.Operation,
                            operation,
                            StringComparison.Ordinal))
                {
                    reasonCode = "operation_invalid";
                    return false;
                }
                if (!TryResolveRuntimeOwnedTarget(
                        lease.SessionId,
                        targetId,
                        lease.Kind == WriteLeaseKind.Shutdown
                            ? SurfaceKind.Launcher
                            : null,
                        out reasonCode))
                {
                    RevokeLocked(
                        lease,
                        reasonCode,
                        WriteLeaseState.Revoked);
                    return false;
                }

                if (_executingLeaseBySession.ContainsKey(
                        lease.SessionId))
                {
                    reasonCode = "write_lease_already_held";
                    return false;
                }
                _executingLeaseBySession[lease.SessionId] =
                    lease.LeaseId;
                lease.ActionExecutionPending = true;
                lease.ActionsConsumed++;
                if (lease.ActionsConsumed >= lease.ActionLimit)
                {
                    lease.State = WriteLeaseState.Consumed;
                    lease.RevokeReason = "action_limit_consumed";
                    if (lease.Kind == WriteLeaseKind.Shutdown)
                    {
                        // Keep the active mapping while the execution
                        // reservation is promoted to response delivery.
                    }
                    else
                    {
                        _activeLeaseBySession.Remove(
                            lease.SessionId);
                    }
                }
                reasonCode = null;
                return true;
            }
        }

        internal bool CompleteActionExecution(
            string leaseId,
            bool retainShutdownDelivery)
        {
            if (string.IsNullOrWhiteSpace(leaseId))
                return false;
            lock (_sync)
            {
                if (!_leases.TryGetValue(
                        leaseId,
                        out WriteLease lease)
                    || !lease.ActionExecutionPending)
                {
                    return false;
                }
                lease.ActionExecutionPending = false;
                RemoveExecutionReservationLocked(lease);
                if (retainShutdownDelivery
                    && lease.Kind == WriteLeaseKind.Shutdown
                    && lease.State == WriteLeaseState.Consumed)
                {
                    lease.ShutdownDeliveryPending = true;
                    return true;
                }
                if (lease.State != WriteLeaseState.Active)
                {
                    RemoveActiveLeaseLocked(lease);
                    RetireTerminalLeaseLocked(lease);
                }
                return true;
            }
        }

        internal bool MarkShutdownDeliveryPending(string leaseId)
        {
            if (string.IsNullOrWhiteSpace(leaseId))
                return false;
            lock (_sync)
            {
                if (!_leases.TryGetValue(
                        leaseId,
                        out WriteLease lease)
                    || lease.Kind != WriteLeaseKind.Shutdown
                    || !lease.ActionExecutionPending
                    || lease.ShutdownDeliveryWriteOwned
                    || lease.ShutdownDeliveryCommitted
                    || lease.State != WriteLeaseState.Consumed)
                {
                    return false;
                }
                lease.ShutdownDeliveryPending = true;
                return true;
            }
        }

        internal bool TryClaimShutdownDeliveryWrite(string leaseId)
        {
            return TryClaimShutdownDeliveryWrite(
                leaseId,
                null);
        }

        internal bool TryClaimShutdownDeliveryWrite(
            string leaseId,
            Func<bool> claimHumanOverrideFence)
        {
            if (string.IsNullOrWhiteSpace(leaseId))
                return false;
            lock (_sync)
            {
                if (!_leases.TryGetValue(
                        leaseId,
                        out WriteLease lease)
                    || lease.Kind != WriteLeaseKind.Shutdown
                    || !lease.ActionExecutionPending
                    || !lease.ShutdownDeliveryPending
                    || lease.ShutdownDeliveryWriteOwned
                    || lease.ShutdownDeliveryCommitted
                    || lease.State != WriteLeaseState.Consumed)
                {
                    return false;
                }
                try
                {
                    if (claimHumanOverrideFence != null
                        && !claimHumanOverrideFence())
                    {
                        return false;
                    }
                }
                catch
                {
                    return false;
                }
                lease.ShutdownDeliveryPending = false;
                lease.ShutdownDeliveryWriteOwned = true;
                return true;
            }
        }

        internal bool IsActionRegistrationAllowed(
            string leaseId)
        {
            if (string.IsNullOrWhiteSpace(leaseId))
                return false;
            lock (_sync)
            {
                return _leases.TryGetValue(
                        leaseId,
                        out WriteLease lease)
                    && (lease.State == WriteLeaseState.Active
                        || lease.State
                            == WriteLeaseState.Consumed
                        && lease.ActionExecutionPending);
            }
        }

        internal bool CompleteShutdownDelivery(string leaseId)
        {
            if (string.IsNullOrWhiteSpace(leaseId))
                return false;
            lock (_sync)
            {
                if (!_leases.TryGetValue(
                        leaseId,
                        out WriteLease lease)
                    || lease.Kind != WriteLeaseKind.Shutdown
                    || !lease.ActionExecutionPending
                    || !lease.ShutdownDeliveryWriteOwned
                    || lease.ShutdownDeliveryCommitted
                    || lease.State != WriteLeaseState.Consumed)
                {
                    return false;
                }
                lease.ActionExecutionPending = false;
                lease.ShutdownDeliveryWriteOwned = false;
                lease.ShutdownDeliveryCommitted = true;
                RemoveExecutionReservationLocked(lease);
                RemoveActiveLeaseLocked(lease);
                LatchCommittedShutdownLocked(lease.SessionId);
                RetireTerminalLeaseLocked(lease);
                return true;
            }
        }

        internal bool AbortClaimedShutdownDeliveryWrite(
            string leaseId)
        {
            if (string.IsNullOrWhiteSpace(leaseId))
                return false;
            lock (_sync)
            {
                if (!_leases.TryGetValue(
                        leaseId,
                        out WriteLease lease)
                    || lease.Kind != WriteLeaseKind.Shutdown
                    || !lease.ActionExecutionPending
                    || !lease.ShutdownDeliveryWriteOwned
                    || lease.ShutdownDeliveryCommitted
                    || lease.State != WriteLeaseState.Consumed)
                {
                    return false;
                }
                lease.ActionExecutionPending = false;
                lease.ShutdownDeliveryWriteOwned = false;
                RemoveExecutionReservationLocked(lease);
                RemoveActiveLeaseLocked(lease);
                RetireTerminalLeaseLocked(lease);
                return true;
            }
        }

        internal bool AbortPendingActionExecution(string leaseId)
        {
            if (string.IsNullOrWhiteSpace(leaseId))
                return false;
            lock (_sync)
            {
                if (!_leases.TryGetValue(
                        leaseId,
                        out WriteLease lease)
                    || !lease.ActionExecutionPending)
                {
                    return false;
                }
                if (lease.ShutdownDeliveryWriteOwned)
                    return false;
                lease.ActionExecutionPending = false;
                lease.ShutdownDeliveryPending = false;
                RemoveExecutionReservationLocked(lease);
                if (lease.State != WriteLeaseState.Active)
                {
                    RemoveActiveLeaseLocked(lease);
                    RetireTerminalLeaseLocked(lease);
                }
                return true;
            }
        }

        internal bool AbortPendingShutdownDelivery(string leaseId)
        {
            if (string.IsNullOrWhiteSpace(leaseId))
                return false;
            lock (_sync)
            {
                if (!_leases.TryGetValue(
                        leaseId,
                        out WriteLease lease)
                    || lease.Kind != WriteLeaseKind.Shutdown
                    || !lease.ShutdownDeliveryPending
                    || lease.ShutdownDeliveryWriteOwned)
                {
                    return false;
                }
                lease.ActionExecutionPending = false;
                lease.ShutdownDeliveryPending = false;
                RemoveExecutionReservationLocked(lease);
                RemoveActiveLeaseLocked(lease);
                RetireTerminalLeaseLocked(lease);
                return true;
            }
        }

        public bool TryRenewDeveloper(
            string leaseId,
            string clientInstanceId,
            string securityPrincipalId,
            TimeSpan requestedLifetime,
            out WriteLease lease,
            out string reasonCode)
        {
            lock (_sync)
            {
                if (!TryResolveActiveLocked(
                        leaseId,
                        clientInstanceId,
                        securityPrincipalId,
                        out lease,
                        out reasonCode))
                {
                    return false;
                }
                if (!TryRequireCompatibleSessionMode(
                        lease.SessionId,
                        lease.SessionMode,
                        out reasonCode))
                {
                    RevokeLocked(
                        lease,
                        reasonCode,
                        WriteLeaseState.Revoked);
                    return false;
                }
                if (lease.SessionMode
                    != AgentSessionMode.DeveloperInteractive)
                {
                    reasonCode = "lease_not_renewable";
                    return false;
                }
                if (lease.Kind == WriteLeaseKind.Shutdown)
                {
                    reasonCode = "operation_invalid";
                    return false;
                }
                if (lease.RenewalCount >= 1)
                {
                    reasonCode = "renewal_limit_reached";
                    return false;
                }
                if (!_credentials.TryResolveActive(
                        lease.CredentialId,
                        clientInstanceId,
                        out PrincipalCredential credential,
                        out reasonCode)
                    || !string.Equals(
                        credential.SecurityPrincipalId,
                        securityPrincipalId,
                        StringComparison.Ordinal))
                {
                    reasonCode ??= "credential_principal_mismatch";
                    RevokeLocked(
                        lease,
                        reasonCode,
                        WriteLeaseState.Revoked);
                    return false;
                }

                long requestedMs = ToPositiveMilliseconds(
                    requestedLifetime);
                long actualMs = Math.Min(
                    requestedMs,
                    (long)DeveloperLifetimeHardCap.TotalMilliseconds);
                actualMs = Math.Min(
                    actualMs,
                    credential.ExpiresMonotonic
                        - _clock.MonotonicMilliseconds);
                if (actualMs <= 0)
                {
                    reasonCode = "credential_expired";
                    RevokeLocked(
                        lease,
                        reasonCode,
                        WriteLeaseState.Expired);
                    return false;
                }
                lease.ExpiresMonotonic = checked(
                    _clock.MonotonicMilliseconds + actualMs);
                lease.RenewAfterMonotonic =
                    _clock.MonotonicMilliseconds
                    + Math.Max(1, actualMs / 2);
                lease.RenewalCount++;
                reasonCode = null;
                return true;
            }
        }

        public bool Revoke(string leaseId, string reason)
        {
            PrincipalCredentialAuthority.RequireValue(reason, nameof(reason));
            lock (_sync)
            {
                if (!_leases.TryGetValue(leaseId, out var lease)
                    || (lease.State != WriteLeaseState.Active
                        && !lease.ActionExecutionPending
                        && !lease.ShutdownDeliveryPending)
                    || lease.ShutdownDeliveryWriteOwned
                    || lease.ShutdownDeliveryCommitted)
                {
                    return false;
                }
                RevokeLocked(lease, reason, WriteLeaseState.Revoked);
                return true;
            }
        }

        public int RevokeAllForHumanOverride(string reason)
        {
            PrincipalCredentialAuthority.RequireValue(reason, nameof(reason));
            lock (_sync)
            {
                int count = 0;
                WriteLease[] candidates =
                    _leases.Values.ToArray();
                _lastHumanOverrideCandidateCount =
                    candidates.Length;
                foreach (WriteLease lease in candidates)
                {
                    if (lease.State == WriteLeaseState.Active
                        || lease.ActionExecutionPending
                        || lease.ShutdownDeliveryPending)
                    {
                        if (lease.ShutdownDeliveryWriteOwned
                            || lease.ShutdownDeliveryCommitted)
                        {
                            continue;
                        }
                        RevokeLocked(
                            lease,
                            reason,
                            WriteLeaseState.Revoked);
                        count++;
                    }
                }
                return count;
            }
        }

        public bool Release(
            string leaseId,
            string clientInstanceId,
            string securityPrincipalId)
        {
            return Release(
                leaseId,
                clientInstanceId,
                securityPrincipalId,
                out _,
                out _);
        }

        public bool Release(
            string leaseId,
            string clientInstanceId,
            string securityPrincipalId,
            out WriteLease lease,
            out string reasonCode)
        {
            lock (_sync)
            {
                if (!TryResolveActiveLocked(
                        leaseId,
                        clientInstanceId,
                        securityPrincipalId,
                        out lease,
                        out reasonCode))
                {
                    return false;
                }
                RevokeLocked(
                    lease,
                    "client_released",
                    WriteLeaseState.Released);
                reasonCode = null;
                return true;
            }
        }

        private void ValidateModeAndNormalize(
            PrincipalCredential credential,
            WriteLeaseRequest request,
            string[] targets,
            long requestedMs,
            out long lifetimeMs,
            out int actionLimit)
        {
            if (request.RequestedActionLimit <= 0)
            {
                throw new InvalidOperationException(
                    "action_limit_required");
            }

            if (credential.SessionMode
                    == AgentSessionMode.PlayerAssist)
            {
                PrincipalCredentialAuthority.RequireValue(
                    request.ConsentReceipt,
                    nameof(request.ConsentReceipt));
                if (!IsSha256(
                        request.ArgumentBoundsHash))
                {
                    throw new InvalidOperationException(
                        "argument_bounds_required");
                }
                if (!PrincipalCredentialAuthority
                    .IsExactIssuerReceipt(
                        credential,
                        request.ConsentReceipt))
                {
                    throw new InvalidOperationException(
                        "consent_receipt_invalid");
                }
            }
            if (credential.SessionMode
                    == AgentSessionMode.UnattendedTest)
            {
                RequireUnattendedBinding(credential);
            }
            if (request.Kind == WriteLeaseKind.Shutdown)
            {
                lifetimeMs = Math.Min(
                    requestedMs,
                    (long)ShutdownLifetimeHardCap
                        .TotalMilliseconds);
                actionLimit = 1;
                return;
            }

            switch (credential.SessionMode)
            {
                case AgentSessionMode.PlayerAssist:
                    if (request.Kind == WriteLeaseKind.GuiInput)
                    {
                        if (targets.Length != 1)
                        {
                            throw new InvalidOperationException(
                                "player_gui_single_target_required");
                        }
                        lifetimeMs = Math.Min(
                            requestedMs,
                            (long)PlayerGuiLifetimeHardCap.TotalMilliseconds);
                        actionLimit = Math.Min(
                            request.RequestedActionLimit,
                            PlayerGuiActionHardCap);
                    }
                    else
                    {
                        RequireDomainBinding(request);
                        lifetimeMs = Math.Min(
                            requestedMs,
                            (long)PlayerDomainLifetimeHardCap.TotalMilliseconds);
                        actionLimit = 1;
                    }
                    break;

                case AgentSessionMode.DeveloperInteractive:
                    lifetimeMs = Math.Min(
                        requestedMs,
                        (long)DeveloperLifetimeHardCap.TotalMilliseconds);
                    actionLimit = Math.Min(
                        request.RequestedActionLimit,
                        DeveloperActionHardCap);
                    break;

                case AgentSessionMode.UnattendedTest:
                    lifetimeMs = requestedMs;
                    actionLimit = Math.Min(
                        request.RequestedActionLimit,
                        UnattendedActionHardCap);
                    break;

                default:
                    throw new ArgumentOutOfRangeException();
            }
        }

        private static bool IsSha256(string value)
        {
            return value != null
                && value.Length == 64
                && value.All(character =>
                    (character >= '0' && character <= '9')
                    || (character >= 'a'
                        && character <= 'f')
                    || (character >= 'A'
                        && character <= 'F'));
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

        private bool TryResolveActiveLocked(
            string leaseId,
            string clientInstanceId,
            string securityPrincipalId,
            out WriteLease lease,
            out string reasonCode)
        {
            lease = null;
            if (string.IsNullOrWhiteSpace(leaseId))
            {
                reasonCode = "lease_not_found";
                return false;
            }
            if (!_leases.TryGetValue(leaseId, out lease))
            {
                if (_terminalLeaseTombstones.TryGetValue(
                        leaseId,
                        out lease))
                {
                    reasonCode =
                        lease.RevokeReason ?? "lease_inactive";
                    return false;
                }
                reasonCode = "lease_not_found";
                return false;
            }
            if (lease.State == WriteLeaseState.Active
                && _clock.MonotonicMilliseconds >= lease.ExpiresMonotonic)
            {
                RevokeLocked(
                    lease,
                    "lease_expired",
                    WriteLeaseState.Expired);
            }
            if (lease.State != WriteLeaseState.Active)
            {
                reasonCode = lease.RevokeReason ?? "lease_inactive";
                return false;
            }
            if (!string.Equals(
                    lease.OwnerClientId,
                    clientInstanceId,
                    StringComparison.Ordinal)
                || !string.Equals(
                    lease.SecurityPrincipalId,
                    securityPrincipalId,
                    StringComparison.Ordinal))
            {
                reasonCode = "lease_owner_mismatch";
                return false;
            }
            reasonCode = null;
            return true;
        }

        private void ExpireSessionLeaseLocked(string sessionId)
        {
            if (_activeLeaseBySession.TryGetValue(
                    sessionId,
                    out string leaseId)
                && _leases.TryGetValue(leaseId, out var lease)
                && !lease.ActionExecutionPending
                && !lease.ShutdownDeliveryPending
                && !lease.ShutdownDeliveryWriteOwned
                && !lease.ShutdownDeliveryCommitted
                && _clock.MonotonicMilliseconds >= lease.ExpiresMonotonic)
            {
                RevokeLocked(
                    lease,
                    "lease_expired",
                    WriteLeaseState.Expired);
            }
        }

        private void RevokeLocked(
            WriteLease lease,
            string reason,
            WriteLeaseState state)
        {
            lease.State = state;
            lease.RevokeReason = reason;
            lease.ShutdownDeliveryPending = false;
            if (!lease.ActionExecutionPending)
            {
                RemoveExecutionReservationLocked(lease);
            }
            if (_activeLeaseBySession.TryGetValue(
                    lease.SessionId,
                    out string activeLeaseId)
                && string.Equals(
                    activeLeaseId,
                    lease.LeaseId,
                    StringComparison.Ordinal))
            {
                _activeLeaseBySession.Remove(lease.SessionId);
            }
            if (!lease.ActionExecutionPending
                && !lease.ShutdownDeliveryPending
                && !lease.ShutdownDeliveryWriteOwned)
            {
                RetireTerminalLeaseLocked(lease);
            }
        }

        private void RemoveExecutionReservationLocked(
            WriteLease lease)
        {
            if (_executingLeaseBySession.TryGetValue(
                    lease.SessionId,
                    out string executingLeaseId)
                && string.Equals(
                    executingLeaseId,
                    lease.LeaseId,
                    StringComparison.Ordinal))
            {
                _executingLeaseBySession.Remove(lease.SessionId);
            }
        }

        private void RemoveActiveLeaseLocked(WriteLease lease)
        {
            if (_activeLeaseBySession.TryGetValue(
                    lease.SessionId,
                    out string activeLeaseId)
                && string.Equals(
                    activeLeaseId,
                    lease.LeaseId,
                    StringComparison.Ordinal))
            {
                _activeLeaseBySession.Remove(lease.SessionId);
            }
        }

        private void RetireTerminalLeaseLocked(WriteLease lease)
        {
            if (lease == null
                || lease.State == WriteLeaseState.Active
                || lease.ActionExecutionPending
                || lease.ShutdownDeliveryPending
                || lease.ShutdownDeliveryWriteOwned
                || !_leases.Remove(lease.LeaseId))
            {
                return;
            }
            _terminalLeaseTombstones.Add(
                lease.LeaseId,
                lease);
            _terminalLeaseOrder.Enqueue(lease.LeaseId);
            while (_terminalLeaseTombstones.Count
                > TerminalLeaseTombstoneCapacity)
            {
                string evictedLeaseId =
                    _terminalLeaseOrder.Dequeue();
                _terminalLeaseTombstones.Remove(
                    evictedLeaseId);
            }
        }

        private void LatchCommittedShutdownLocked(string sessionId)
        {
            if (_committedShutdownLatchOverflowed
                || _committedShutdownSessions.Contains(sessionId))
            {
                return;
            }
            if (_committedShutdownSessions.Count
                < CommittedShutdownSessionCapacity)
            {
                _committedShutdownSessions.Add(sessionId);
                return;
            }
            // Exact storage is full. A global latch is the only bounded
            // transition that cannot forget a committed shutdown.
            _committedShutdownLatchOverflowed = true;
        }

        private static string[] NormalizeRequired(
            IEnumerable<string> values,
            string reason)
        {
            string[] normalized = (values ?? Array.Empty<string>())
                .Where(value => !string.IsNullOrWhiteSpace(value))
                .Distinct(StringComparer.Ordinal)
                .OrderBy(value => value, StringComparer.Ordinal)
                .ToArray();
            if (normalized.Length == 0)
            {
                throw new InvalidOperationException(reason);
            }
            return normalized;
        }

        private static void RequireDomainBinding(WriteLeaseRequest request)
        {
            PrincipalCredentialAuthority.RequireValue(
                request.PreviewHash,
                nameof(request.PreviewHash));
            PrincipalCredentialAuthority.RequireValue(
                request.ExpectedRevision,
                nameof(request.ExpectedRevision));
            PrincipalCredentialAuthority.RequireValue(
                request.Operation,
                nameof(request.Operation));
        }

        private static void RequireUnattendedBinding(
            PrincipalCredential credential)
        {
            if (string.IsNullOrWhiteSpace(
                    credential.BuildIdentity)
                || string.IsNullOrWhiteSpace(
                    credential.AttemptId)
                || string.IsNullOrWhiteSpace(
                    credential.Slot)
                || !credential.Slot.StartsWith(
                    "cf7_agent_",
                    StringComparison.Ordinal))
            {
                throw new InvalidOperationException(
                    "unattended_binding_invalid");
            }
        }

        private static void ValidateKindBinding(
            WriteLeaseRequest request,
            IReadOnlyCollection<string> capabilities,
            IReadOnlyCollection<string> targets)
        {
            bool hasShutdown = capabilities.Contains(
                AgentCapabilitiesV1.SessionShutdown,
                StringComparer.Ordinal);
            if (request.Kind != WriteLeaseKind.Shutdown)
            {
                if (hasShutdown)
                {
                    throw new InvalidOperationException(
                        "capability_scope_denied");
                }
                return;
            }
            if (capabilities.Count != 1
                || !hasShutdown)
            {
                throw new InvalidOperationException(
                    "capability_scope_denied");
            }
            if (targets.Count != 1)
            {
                throw new InvalidOperationException(
                    "target_scope_denied");
            }
            if (request.RequestedActionLimit != 1)
            {
                throw new InvalidOperationException(
                    "lease_action_limit");
            }
            if (!string.IsNullOrWhiteSpace(request.Operation)
                && !string.Equals(
                    request.Operation,
                    AgentCapabilitiesV1.SessionShutdown,
                    StringComparison.Ordinal))
            {
                throw new InvalidOperationException(
                    "operation_invalid");
            }
            if (!string.IsNullOrWhiteSpace(
                    request.PreviewHash)
                || !string.IsNullOrWhiteSpace(
                    request.ExpectedRevision))
            {
                throw new InvalidOperationException(
                    "arguments_invalid");
            }
        }

        private static long ToPositiveMilliseconds(TimeSpan duration)
        {
            if (duration <= TimeSpan.Zero)
            {
                throw new ArgumentOutOfRangeException(nameof(duration));
            }
            return (long)Math.Ceiling(duration.TotalMilliseconds);
        }

        private static string PlayerConsentKey(
            string securityPrincipalId,
            string consentReceipt)
        {
            return securityPrincipalId + "\n" + consentReceipt;
        }

        private void RequireRuntimeOwnedTarget(
            string sessionId,
            string targetId,
            SurfaceKind? requiredKind)
        {
            if (!TryResolveRuntimeOwnedTarget(
                    sessionId,
                    targetId,
                    requiredKind,
                    out string reasonCode))
            {
                throw new InvalidOperationException(reasonCode);
            }
        }

        private bool TryResolveRuntimeOwnedTarget(
            string sessionId,
            string targetId,
            SurfaceKind? requiredKind,
            out string reasonCode)
        {
            if (!_targets.TryResolve(
                    sessionId,
                    targetId,
                    out AgentTargetDescriptor descriptor,
                    out reasonCode))
            {
                reasonCode ??= "target_not_authoritative";
                return false;
            }
            if (descriptor.SafetyKind
                == AgentTargetSafetyKind.HumanOnlySecuritySurface)
            {
                reasonCode = "human_only_security_surface";
                return false;
            }
            if (requiredKind.HasValue
                && descriptor.Kind != requiredKind.Value)
            {
                reasonCode = "unsupported_for_surface";
                return false;
            }
            reasonCode = null;
            return true;
        }
    }
}
