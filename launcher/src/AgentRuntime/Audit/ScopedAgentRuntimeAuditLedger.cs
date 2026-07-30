using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Security;

namespace CF7Launcher.AgentRuntime.Audit
{
    internal static class AgentRuntimeAuditEventTypes
    {
        public const string ConnectionOpened =
            "connection_opened";
        public const string AuthenticationSucceeded =
            "authentication_succeeded";
        public const string ConnectionTerminated =
            "connection_terminated";
        public const string CredentialRevoked =
            "credential_revoked";
        public const string SessionInvalidated =
            "session_invalidated";
        public const string ObservationGrantIssued =
            "observation_grant_issued";
        public const string ObservationGrantRevoked =
            "observation_grant_revoked";
        public const string ObservationGrantBound =
            "observation_grant_bound";
        public const string WriteLeaseAcquired =
            "write_lease_acquired";
        public const string WriteLeaseRenewed =
            "write_lease_renewed";
        public const string WriteLeaseReleased =
            "write_lease_released";
        public const string WriteLeaseRevoked =
            "write_lease_revoked";
        public const string WriteLeaseBound =
            "write_lease_bound";
        public const string ObservationCaptured =
            "observation_captured";
        public const string TraceExportAuthorized =
            "trace_export_authorized";
        public const string TraceExportCompleted =
            "trace_export_completed";
        public const string TraceExportFailed =
            "trace_export_failed";
        public const string ActionValidation =
            "action_validation";
        public const string ActionBindingValidated =
            "action_binding_validated";
        public const string ActionDispatchStarted =
            "action_dispatch_started";
        public const string ActionRejected =
            "action_rejected";
        public const string ActionUnknown =
            "action_unknown";
        public const string ActionReconcileRequired =
            "action_reconcile_required";
        public const string DomainProposal =
            "domain_proposal";
        public const string DomainCommit =
            "domain_commit";
        public const string ActionTerminal =
            "action_terminal";
        public const string ActionResponseWritten =
            "action_response_written";
        public const string ActionResponseUnknown =
            "action_response_unknown";
    }

    internal sealed record AgentAuditScopeKey(
        string SecurityPrincipalId,
        string SessionId,
        string ConsentPurpose);

    internal sealed class AgentRuntimeAuditEventEnvelope
    {
        public PrincipalCredential Principal { get; init; }
        public string SessionId { get; init; }
        public ulong LifecycleGeneration { get; init; }
        public string ConsentPurpose { get; init; }
        public string ConnectionId { get; init; }
        public string CorrelationId { get; init; }
        public string EventType { get; init; }
        public ActionEnvelope Action { get; init; }
        public string ActionPayloadHash { get; init; }
        public WriteLease Lease { get; init; }
        public ActionOutcome? Outcome { get; init; }
        public EvidenceKind? EvidenceKind { get; init; }
        public string ReasonCode { get; init; }
        public ReconcileKind? ReconcileKind { get; init; }
        public string BeforeFrameId { get; init; }
        public string BeforeFrameHash { get; init; }
        public string BeforeFrameReasonCode { get; init; }
        public string AfterObservationId { get; init; }
        public string AfterFrameId { get; init; }
        public string AfterFrameHash { get; init; }
        public string AfterFrameReasonCode { get; init; }
        public string DomainTransactionId { get; init; }
        public string DomainPreviewHash { get; init; }
        public bool RestoreSecretIssued { get; init; }
        public DateTimeOffset? RestoreExpiresAtUtc { get; init; }
        public bool DispatchMayHaveStarted { get; init; }
        public bool TerminalAction { get; init; }
        public bool ResponseDeliveryPending { get; init; }

        public AgentAuditScopeKey ScopeKey =>
            new AgentAuditScopeKey(
                Principal?.SecurityPrincipalId,
                SessionId,
                ConsentPurpose);
    }

    internal sealed record AgentRuntimeAuditCommit(
        string ScopeId,
        long AuditSequence,
        string SegmentId,
        long SegmentSequence,
        string EventType,
        string PayloadHash,
        string EntryHash);

    internal interface IAgentRuntimeAuditSink
    {
        bool TryAppend(
            AgentRuntimeAuditEventEnvelope auditEvent,
            out AgentRuntimeAuditCommit commit,
            out string reasonCode);
    }

    internal enum AgentRuntimeActionResponseDisposition
    {
        Written,
        Unknown
    }

    internal sealed class AgentRuntimeActionResponseAuditFact
    {
        public PrincipalCredential Principal { get; init; }
        public string ConnectionId { get; init; }
        public string SessionId { get; init; }
        public ulong LifecycleGeneration { get; init; }
        public string ConsentPurpose { get; init; }
        public string CorrelationId { get; init; }
        public string ActionId { get; init; }
        public string ActionPayloadHash { get; init; }
        public long TerminalAuditSequence { get; init; }
        public string TerminalEntryHash { get; init; }
        public AgentRuntimeActionResponseDisposition
            Disposition { get; init; }
        public string ReasonCode { get; init; }
    }

    internal interface IAgentRuntimeActionResponseAuditSink
    {
        bool TryClaimActionResponseWrite(
            AgentRuntimeActionResponseAuditFact fact,
            out string reasonCode);

        bool TryCompleteActionResponse(
            AgentRuntimeActionResponseAuditFact fact,
            out AgentRuntimeAuditCommit commit,
            out string reasonCode);
    }

    internal interface IAgentRuntimeConnectionAuditSink
    {
        bool TryRegisterAuthenticatedConnection(
            string connectionId,
            PrincipalCredential principal,
            out string reasonCode);

        void RecordConnectionTermination(
            string connectionId,
            string reasonCode);
    }

    internal sealed class AgentRuntimeTrustedAuditFact
    {
        public PrincipalCredential Principal { get; init; }
        public string ConnectionId { get; init; }
        public string SessionId { get; init; }
        public ulong LifecycleGeneration { get; init; }
        public string ConsentPurpose { get; init; }
        public string EventType { get; init; }
        public string CorrelationId { get; init; }
        public string ObservationGrantId { get; init; }
        public string LeaseId { get; init; }
        public string Capability { get; init; }
        public IReadOnlyCollection<string> TargetScope { get; init; }
        public IReadOnlyCollection<string> DataScope { get; init; }
        public bool? AllowExport { get; init; }
        public bool? AllowPersistence { get; init; }
        public string State { get; init; }
        public string ReasonCode { get; init; }
        public string ConsentReceipt { get; init; }
        public string ArtifactId { get; init; }
        public long? ExportedThroughAuditSequence { get; init; }

        public AgentAuditScopeKey ScopeKey =>
            new AgentAuditScopeKey(
                Principal?.SecurityPrincipalId,
                SessionId,
                ConsentPurpose);
    }

    internal interface IAgentAuditScopeAuthority
    {
        bool TryAuthorize(
            PrincipalCredential principal,
            string sessionId,
            ulong lifecycleGeneration,
            string consentPurpose,
            out string reasonCode);
    }

    internal sealed record AgentAuditDeletionReceipt(
        string DeletionReceiptId,
        int DeletedSegmentCount,
        long DeletedCommittedEventCount,
        string ReasonCode,
        DateTimeOffset DeletedUtc,
        bool RuntimeManagedScopeOnly);

    internal sealed record ScopedAuditSegmentSnapshot(
        int SegmentOrdinal,
        string PreviousSegmentFinalHash,
        ReadOnlyCollection<AuditEntry> Entries,
        AuditSegmentReceipt Receipt);

    internal sealed record ScopedAuditLedgerSnapshot(
        string ScopeId,
        AgentAuditScopeKey Scope,
        string CredentialId,
        long CredentialGeneration,
        ulong LifecycleGeneration,
        bool Active,
        bool TrustedConnectionPrelude,
        bool ActionCoverage,
        bool ObservationGrantCoverage,
        bool WriteLeaseCoverage,
        ReadOnlyCollection<ScopedAuditSegmentSnapshot> Segments);

    internal sealed record ScopedAuditExportRecord(
        long AuditSequence,
        int SegmentOrdinal,
        AuditEntry Entry);

    internal sealed record ScopedAuditExportSnapshot(
        string ScopeId,
        AgentAuditScopeKey Scope,
        string CredentialId,
        long CredentialGeneration,
        ulong LifecycleGeneration,
        long FirstAuditSequence,
        long LastAuditSequence,
        string PreviousEntryHash,
        string FinalEntryHash,
        bool HasMore,
        ReadOnlyCollection<ScopedAuditExportRecord> Records);

    /// <summary>
    /// Owns physically separate, bounded audit chains. A scope is never
    /// reconstructed by filtering entries from a process-global segment.
    /// All public action audit sequences come from a successfully appended
    /// event in the exact principal/session/consent-purpose chain.
    /// </summary>
    internal sealed class ScopedAgentRuntimeAuditLedgerManager
        : IAgentRuntimeAuditSink,
          IAgentRuntimeActionResponseAuditSink,
          IDisposable
    {
        internal const int DefaultMaximumEntriesPerSegment = 256;
        internal const int MaximumRetainedScopes = 256;
        internal const int MaximumDeletionReceipts = 1024;

        private readonly object _sync = new object();
        private readonly IAgentRuntimeClock _clock;
        private readonly PrincipalCredentialAuthority _credentials;
        private readonly IAgentAuditScopeAuthority _scopeAuthority;
        private readonly int _maximumEntriesPerSegment;
        private readonly bool _requireTrustedConnections;
        private readonly Dictionary<AgentAuditScopeKey, ScopeLedger>
            _active =
                new Dictionary<AgentAuditScopeKey, ScopeLedger>();
        private readonly Dictionary<AgentAuditScopeKey, List<ScopeLedger>>
            _retained =
                new Dictionary<AgentAuditScopeKey, List<ScopeLedger>>();
        private readonly Dictionary<string, TrustedConnection>
            _connections =
                new Dictionary<string, TrustedConnection>(
                    StringComparer.Ordinal);
        private readonly Dictionary<string, TrustedGrant>
            _grants =
                new Dictionary<string, TrustedGrant>(
                    StringComparer.Ordinal);
        private readonly Queue<AgentAuditDeletionReceipt>
            _deletionReceipts =
                new Queue<AgentAuditDeletionReceipt>();
        private bool _disposed;

        public ScopedAgentRuntimeAuditLedgerManager(
            IAgentRuntimeClock clock,
            PrincipalCredentialAuthority credentials,
            IAgentAuditScopeAuthority scopeAuthority,
            int maximumEntriesPerSegment =
                DefaultMaximumEntriesPerSegment,
            bool requireTrustedConnections = false)
        {
            _clock = clock
                ?? throw new ArgumentNullException(nameof(clock));
            _credentials = credentials
                ?? throw new ArgumentNullException(
                    nameof(credentials));
            _scopeAuthority = scopeAuthority
                ?? throw new ArgumentNullException(
                    nameof(scopeAuthority));
            if (maximumEntriesPerSegment < 3
                || maximumEntriesPerSegment
                    >= AppendOnlyAuditSegment.MaximumEntries)
            {
                throw new ArgumentOutOfRangeException(
                    nameof(maximumEntriesPerSegment));
            }
            _maximumEntriesPerSegment =
                maximumEntriesPerSegment;
            _requireTrustedConnections =
                requireTrustedConnections;
        }

        public bool TryRegisterAuthenticatedConnection(
            string connectionId,
            PrincipalCredential principal,
            string sessionId,
            ulong lifecycleGeneration,
            out string reasonCode)
        {
            lock (_sync)
            {
                reasonCode = null;
                if (_disposed)
                {
                    reasonCode = "audit_unavailable";
                    return false;
                }
                if (string.IsNullOrWhiteSpace(connectionId)
                    || principal == null
                    || string.IsNullOrWhiteSpace(sessionId)
                    || lifecycleGeneration == 0
                    || !_credentials.TryResolveActive(
                        principal.CredentialId,
                        principal.ClientInstanceId,
                        out PrincipalCredential active,
                        out reasonCode)
                    || !ReferenceEquals(active, principal))
                {
                    reasonCode ??= "credential_inactive";
                    return false;
                }
                if (_connections.ContainsKey(connectionId))
                {
                    reasonCode = "connection_already_registered";
                    return false;
                }
                _connections.Add(
                    connectionId,
                    new TrustedConnection(
                        connectionId,
                        principal,
                        sessionId,
                        lifecycleGeneration));
                reasonCode = null;
                return true;
            }
        }

        public void RecordConnectionTermination(
            string connectionId,
            string reasonCode)
        {
            PrincipalCredentialAuthority.RequireValue(
                connectionId,
                nameof(connectionId));
            PrincipalCredentialAuthority.RequireValue(
                reasonCode,
                nameof(reasonCode));
            lock (_sync)
            {
                if (!_connections.Remove(
                        connectionId,
                        out TrustedConnection connection))
                {
                    return;
                }
                foreach (ScopeLedger scope
                    in _active.Values
                        .Where(candidate =>
                            string.Equals(
                                candidate.ConnectionId,
                                connectionId,
                                StringComparison.Ordinal))
                        .ToArray())
                {
                    bool responseDeliveryPending =
                        scope.PendingResponseDeliveries.Count != 0;
                    DrainPendingResponseDeliveriesLocked(
                        scope,
                        reasonCode);
                    foreach (string grantId
                        in scope
                            .ReferencedObservationGrants)
                    {
                        TryAppendResourceRevocationFactLocked(
                            scope,
                            AgentRuntimeAuditEventTypes
                                .ObservationGrantRevoked,
                            grantId,
                            null,
                            reasonCode);
                    }
                    foreach (string leaseId
                        in scope.ReferencedLeases)
                    {
                        TryAppendResourceRevocationFactLocked(
                            scope,
                            AgentRuntimeAuditEventTypes
                                .WriteLeaseRevoked,
                            null,
                            leaseId,
                            reasonCode);
                    }
                    TryAppendRevocationFactLocked(
                        scope,
                        AgentRuntimeAuditEventTypes
                            .CredentialRevoked,
                        connectionId,
                        reasonCode);
                    TryAppendRevocationFactLocked(
                        scope,
                        AgentRuntimeAuditEventTypes
                            .ConnectionTerminated,
                        connectionId,
                        reasonCode);
                    bool clean =
                        string.Equals(
                            reasonCode,
                            "connection_closed",
                            StringComparison.Ordinal)
                        && scope.OpenCorrelations.Count == 0
                        && !responseDeliveryPending;
                    SealScopeLocked(
                        scope,
                        clean
                            ? AuditSegmentTerminalKind.Completed
                            : AuditSegmentTerminalKind.Truncated,
                        reasonCode);
                }
            }
        }

        public bool TryRebindConnectionLifecycle(
            string connectionId,
            PrincipalCredential principal,
            string sessionId,
            ulong lifecycleGeneration,
            out string reasonCode)
        {
            lock (_sync)
            {
                reasonCode = null;
                if (_disposed
                    || !_connections.TryGetValue(
                        connectionId ?? string.Empty,
                        out TrustedConnection current)
                    || !ReferenceEquals(
                        current.Principal,
                        principal)
                    || string.IsNullOrWhiteSpace(sessionId)
                    || lifecycleGeneration == 0
                    || !_credentials.TryResolveActive(
                        principal.CredentialId,
                        principal.ClientInstanceId,
                        out PrincipalCredential active,
                        out reasonCode)
                    || !ReferenceEquals(active, principal))
                {
                    reasonCode ??=
                        "audit_connection_untrusted";
                    return false;
                }
                _connections[connectionId] =
                    new TrustedConnection(
                        connectionId,
                        principal,
                        sessionId,
                        lifecycleGeneration);
                reasonCode = null;
                return true;
            }
        }

        public bool TryAppendTrustedFact(
            AgentRuntimeTrustedAuditFact fact,
            out AgentRuntimeAuditCommit commit,
            out string reasonCode)
        {
            lock (_sync)
            {
                commit = null;
                if (_disposed)
                {
                    reasonCode = "audit_unavailable";
                    return false;
                }
                if (!TryValidateTrustedFact(
                        fact,
                        out reasonCode))
                {
                    return false;
                }
                if (!TryResolveTrustedConnection(
                        fact.ConnectionId,
                        fact.Principal,
                        fact.SessionId,
                        fact.LifecycleGeneration,
                        out TrustedConnection connection))
                {
                    reasonCode = "audit_connection_untrusted";
                    return false;
                }
                if (!IsCredentialAndScopeActive(
                        fact.Principal,
                        fact.SessionId,
                        fact.LifecycleGeneration,
                        fact.ConsentPurpose,
                        out reasonCode))
                {
                    return false;
                }

                AgentAuditScopeKey key = fact.ScopeKey;
                if (!_active.TryGetValue(
                        key,
                        out ScopeLedger scope))
                {
                    if (!TryCreateScope(
                            fact.Principal,
                            fact.ConnectionId,
                            fact.SessionId,
                            fact.LifecycleGeneration,
                            fact.ConsentPurpose,
                            connection,
                            out scope,
                            out reasonCode))
                    {
                        return false;
                    }
                }
                else if (!ScopeBindingMatches(
                        scope,
                        fact.Principal,
                        fact.ConnectionId,
                        fact.LifecycleGeneration))
                {
                    reasonCode =
                        "audit_scope_binding_mismatch";
                    return false;
                }

                try
                {
                    commit = AppendTrustedFactLocked(
                        scope,
                        fact);
                    TrackTrustedGrantLocked(fact);
                    reasonCode = null;
                    return true;
                }
                catch
                {
                    reasonCode = "audit_append_failed";
                    return false;
                }
            }
        }

        public bool TryAppend(
            AgentRuntimeAuditEventEnvelope auditEvent,
            out AgentRuntimeAuditCommit commit,
            out string reasonCode)
        {
            lock (_sync)
            {
                commit = null;
                if (_disposed)
                {
                    reasonCode = "audit_unavailable";
                    return false;
                }
                if (!TryValidateEvent(
                        auditEvent,
                        out reasonCode))
                {
                    return false;
                }

                AgentAuditScopeKey key = auditEvent.ScopeKey;
                bool isValidation = string.Equals(
                    auditEvent.EventType,
                    AgentRuntimeAuditEventTypes.ActionValidation,
                    StringComparison.Ordinal);
                bool isTerminal = auditEvent.TerminalAction;
                _active.TryGetValue(key, out ScopeLedger scope);

                if (scope == null)
                {
                    TrustedConnection connection = null;
                    if (!string.IsNullOrWhiteSpace(
                            auditEvent.ConnectionId)
                        && !TryResolveTrustedConnection(
                            auditEvent.ConnectionId,
                            auditEvent.Principal,
                            auditEvent.SessionId,
                            auditEvent.LifecycleGeneration,
                            out connection)
                        && _requireTrustedConnections)
                    {
                        reasonCode =
                            "audit_connection_untrusted";
                        return false;
                    }
                    if (!isValidation
                        || !TryCreateScope(
                            auditEvent.Principal,
                            auditEvent.ConnectionId,
                            auditEvent.SessionId,
                            auditEvent.LifecycleGeneration,
                            auditEvent.ConsentPurpose,
                            connection,
                            out scope,
                            out reasonCode))
                    {
                        reasonCode ??= "audit_scope_inactive";
                        return false;
                    }
                }
                else if (!ScopeBindingMatches(
                        scope,
                        auditEvent.Principal,
                        auditEvent.ConnectionId,
                        auditEvent.LifecycleGeneration))
                {
                    reasonCode = "audit_scope_binding_mismatch";
                    return false;
                }

                bool credentialActive =
                    IsCredentialAndScopeActive(
                        auditEvent,
                        out string authorityReason);
                if (!credentialActive
                    && (!isTerminal
                        || !scope.OpenCorrelations.Contains(
                            auditEvent.CorrelationId)
                        || auditEvent.Outcome
                            != ActionOutcome.Unknown))
                {
                    MarkPendingTruncation(
                        scope,
                        authorityReason
                            ?? "credential_inactive");
                    reasonCode = "audit_scope_inactive";
                    return false;
                }

                if (isValidation)
                {
                    if (!scope.OpenCorrelations.Add(
                            auditEvent.CorrelationId))
                    {
                        reasonCode =
                            "audit_correlation_already_open";
                        return false;
                    }
                }
                else if (!scope.OpenCorrelations.Contains(
                        auditEvent.CorrelationId))
                {
                    reasonCode = "audit_correlation_not_open";
                    return false;
                }

                try
                {
                    commit = AppendEventLocked(
                        scope,
                        auditEvent);
                    if (isTerminal
                        && auditEvent.ResponseDeliveryPending)
                    {
                        scope.PendingResponseDeliveries.Add(
                            auditEvent.CorrelationId,
                            new PendingResponseDelivery(
                                auditEvent.Principal,
                                auditEvent.ConnectionId,
                                auditEvent.CorrelationId,
                                auditEvent.Action.ActionId,
                                auditEvent.ActionPayloadHash,
                                commit.AuditSequence,
                                commit.EntryHash));
                    }
                }
                catch
                {
                    if (isValidation)
                    {
                        scope.OpenCorrelations.Remove(
                            auditEvent.CorrelationId);
                    }
                    reasonCode = "audit_append_failed";
                    return false;
                }

                if (isTerminal)
                {
                    scope.OpenCorrelations.Remove(
                        auditEvent.CorrelationId);
                    if (!credentialActive)
                    {
                        MarkPendingTruncation(
                            scope,
                            authorityReason
                                ?? "credential_inactive");
                    }
                    SealPendingIfIdle(scope);
                }
                reasonCode = null;
                return true;
            }
        }

        public bool TryCompleteActionResponse(
            AgentRuntimeActionResponseAuditFact fact,
            out AgentRuntimeAuditCommit commit,
            out string reasonCode)
        {
            lock (_sync)
            {
                commit = null;
                reasonCode =
                    "response_delivery_not_pending";
                if (_disposed
                    || fact?.Principal == null
                    || string.IsNullOrWhiteSpace(
                        fact.ConnectionId)
                    || string.IsNullOrWhiteSpace(
                        fact.SessionId)
                    || fact.LifecycleGeneration == 0
                    || string.IsNullOrWhiteSpace(
                        fact.ConsentPurpose)
                    || string.IsNullOrWhiteSpace(
                        fact.CorrelationId)
                    || string.IsNullOrWhiteSpace(
                        fact.ActionId)
                    || string.IsNullOrWhiteSpace(
                        fact.ActionPayloadHash)
                    || fact.ActionPayloadHash.Length != 64
                    || string.IsNullOrWhiteSpace(
                        fact.TerminalEntryHash)
                    || fact.TerminalAuditSequence <= 0)
                {
                    reasonCode =
                        "audit_event_invalid";
                    return false;
                }

                var key = new AgentAuditScopeKey(
                    fact.Principal.SecurityPrincipalId,
                    fact.SessionId,
                    fact.ConsentPurpose);
                if (!_active.TryGetValue(
                        key,
                        out ScopeLedger scope)
                    || !scope.PendingResponseDeliveries
                        .TryGetValue(
                            fact.CorrelationId,
                            out PendingResponseDelivery pending)
                    || !ReferenceEquals(
                        pending.Principal,
                        fact.Principal)
                    || !string.Equals(
                        pending.ConnectionId,
                        fact.ConnectionId,
                        StringComparison.Ordinal)
                    || scope.LifecycleGeneration
                        != fact.LifecycleGeneration
                    || !string.Equals(
                        pending.ActionId,
                        fact.ActionId,
                        StringComparison.Ordinal)
                    || !string.Equals(
                        pending.ActionPayloadHash,
                        fact.ActionPayloadHash,
                        StringComparison.Ordinal)
                    || pending.TerminalAuditSequence
                        != fact.TerminalAuditSequence
                    || !string.Equals(
                        pending.TerminalEntryHash,
                        fact.TerminalEntryHash,
                        StringComparison.Ordinal)
                    || fact.Disposition
                            == AgentRuntimeActionResponseDisposition
                                .Written
                        && !pending.WriteClaimed)
                {
                    return false;
                }

                string eventType = fact.Disposition switch
                {
                    AgentRuntimeActionResponseDisposition
                        .Written =>
                        AgentRuntimeAuditEventTypes
                            .ActionResponseWritten,
                    AgentRuntimeActionResponseDisposition
                        .Unknown =>
                        AgentRuntimeAuditEventTypes
                            .ActionResponseUnknown,
                    _ => null
                };
                if (eventType == null
                    || fact.Disposition
                            == AgentRuntimeActionResponseDisposition
                                .Unknown
                        && string.IsNullOrWhiteSpace(
                            fact.ReasonCode))
                {
                    reasonCode =
                        "audit_event_invalid";
                    return false;
                }
                try
                {
                    commit = AppendSyntheticFactLocked(
                        scope,
                        eventType,
                        new
                        {
                            correlationId =
                                pending.CorrelationId,
                            actionId = pending.ActionId,
                            actionPayloadHash =
                                pending.ActionPayloadHash,
                            terminalAuditSequence =
                                pending.TerminalAuditSequence,
                            terminalEntryHash =
                                pending.TerminalEntryHash,
                            disposition =
                                fact.Disposition.ToString(),
                            reasonCode =
                                fact.ReasonCode
                        });
                    scope.PendingResponseDeliveries.Remove(
                        fact.CorrelationId);
                    SealPendingIfIdle(scope);
                    reasonCode = null;
                    return true;
                }
                catch
                {
                    if (fact.Disposition
                        == AgentRuntimeActionResponseDisposition
                            .Written)
                    {
                        // The complete response is already on the transport
                        // boundary and cannot truthfully be reclassified as
                        // unknown. Drop the pending disposition and truncate
                        // the chain so later shutdown/dispose cannot synthesize
                        // a compensating unknown fact.
                        scope.PendingResponseDeliveries.Remove(
                            fact.CorrelationId);
                    }
                    MarkPendingTruncation(
                        scope,
                        "audit_append_failed");
                    SealPendingIfIdle(scope);
                    reasonCode =
                        "audit_append_failed";
                    return false;
                }
            }
        }

        public bool TryClaimActionResponseWrite(
            AgentRuntimeActionResponseAuditFact fact,
            out string reasonCode)
        {
            lock (_sync)
            {
                reasonCode =
                    "response_delivery_not_pending";
                if (_disposed
                    || fact?.Principal == null
                    || string.IsNullOrWhiteSpace(
                        fact.ConnectionId)
                    || string.IsNullOrWhiteSpace(
                        fact.SessionId)
                    || fact.LifecycleGeneration == 0
                    || string.IsNullOrWhiteSpace(
                        fact.ConsentPurpose)
                    || string.IsNullOrWhiteSpace(
                        fact.CorrelationId)
                    || string.IsNullOrWhiteSpace(
                        fact.ActionId)
                    || string.IsNullOrWhiteSpace(
                        fact.ActionPayloadHash)
                    || fact.ActionPayloadHash.Length != 64
                    || string.IsNullOrWhiteSpace(
                        fact.TerminalEntryHash)
                    || fact.TerminalAuditSequence <= 0)
                {
                    reasonCode =
                        "audit_event_invalid";
                    return false;
                }

                var key = new AgentAuditScopeKey(
                    fact.Principal.SecurityPrincipalId,
                    fact.SessionId,
                    fact.ConsentPurpose);
                if (!_active.TryGetValue(
                        key,
                        out ScopeLedger scope)
                    || !scope.PendingResponseDeliveries
                        .TryGetValue(
                            fact.CorrelationId,
                            out PendingResponseDelivery pending)
                    || pending.WriteClaimed
                    || !ReferenceEquals(
                        pending.Principal,
                        fact.Principal)
                    || !string.Equals(
                        pending.ConnectionId,
                        fact.ConnectionId,
                        StringComparison.Ordinal)
                    || scope.LifecycleGeneration
                        != fact.LifecycleGeneration
                    || !string.Equals(
                        pending.ActionId,
                        fact.ActionId,
                        StringComparison.Ordinal)
                    || !string.Equals(
                        pending.ActionPayloadHash,
                        fact.ActionPayloadHash,
                        StringComparison.Ordinal)
                    || pending.TerminalAuditSequence
                        != fact.TerminalAuditSequence
                    || !string.Equals(
                        pending.TerminalEntryHash,
                        fact.TerminalEntryHash,
                        StringComparison.Ordinal))
                {
                    return false;
                }
                pending.WriteClaimed = true;
                reasonCode = null;
                return true;
            }
        }

        public void RevokeCredential(
            string credentialId,
            string reasonCode)
        {
            PrincipalCredentialAuthority.RequireValue(
                credentialId,
                nameof(credentialId));
            PrincipalCredentialAuthority.RequireValue(
                reasonCode,
                nameof(reasonCode));
            lock (_sync)
            {
                foreach (ScopeLedger scope
                    in _active.Values
                        .Where(candidate =>
                            string.Equals(
                                candidate.CredentialId,
                                credentialId,
                                StringComparison.Ordinal))
                        .ToArray())
                {
                    DrainPendingResponseDeliveriesLocked(
                        scope,
                        reasonCode);
                    TryAppendRevocationFactLocked(
                        scope,
                        AgentRuntimeAuditEventTypes
                            .CredentialRevoked,
                        scope.ConnectionId,
                        reasonCode);
                    MarkPendingTruncation(scope, reasonCode);
                    SealPendingIfIdle(scope);
                }
                foreach (string connectionId
                    in _connections
                        .Where(pair =>
                            string.Equals(
                                pair.Value.Principal
                                    .CredentialId,
                                credentialId,
                                StringComparison.Ordinal))
                        .Select(pair => pair.Key)
                        .ToArray())
                {
                    _connections.Remove(connectionId);
                }
                var revokedPrincipalIds =
                    new HashSet<string>(
                        _retained.Values
                            .SelectMany(values => values)
                            .Where(scope =>
                                string.Equals(
                                    scope.CredentialId,
                                    credentialId,
                                    StringComparison.Ordinal))
                            .Select(scope =>
                                scope.Key
                                    .SecurityPrincipalId),
                        StringComparer.Ordinal);
                foreach (string grantId
                    in _grants
                        .Where(pair =>
                            revokedPrincipalIds.Contains(
                                pair.Value
                                    .SecurityPrincipalId))
                        .Select(pair => pair.Key)
                        .ToArray())
                {
                    _grants[grantId] =
                        _grants[grantId]
                            with { Active = false };
                }
            }
        }

        public void InvalidateSession(
            string sessionId,
            ulong lifecycleGeneration,
            string reasonCode)
        {
            PrincipalCredentialAuthority.RequireValue(
                sessionId,
                nameof(sessionId));
            PrincipalCredentialAuthority.RequireValue(
                reasonCode,
                nameof(reasonCode));
            lock (_sync)
            {
                foreach (ScopeLedger scope
                    in _active.Values
                        .Where(candidate =>
                            string.Equals(
                                candidate.Key.SessionId,
                                sessionId,
                                StringComparison.Ordinal)
                            && candidate.LifecycleGeneration
                                == lifecycleGeneration)
                        .ToArray())
                {
                    DrainPendingResponseDeliveriesLocked(
                        scope,
                        reasonCode);
                    TryAppendRevocationFactLocked(
                        scope,
                        AgentRuntimeAuditEventTypes
                            .SessionInvalidated,
                        scope.ConnectionId,
                        reasonCode);
                    MarkPendingTruncation(scope, reasonCode);
                    SealPendingIfIdle(scope);
                }
                foreach (string grantId
                    in _grants
                        .Where(pair =>
                            string.Equals(
                                pair.Value.SessionId,
                                sessionId,
                                StringComparison.Ordinal)
                            && pair.Value
                                .LifecycleGeneration
                                == lifecycleGeneration)
                        .Select(pair => pair.Key)
                        .ToArray())
                {
                    _grants[grantId] =
                        _grants[grantId]
                            with { Active = false };
                }
            }
        }

        public void CompleteSession(
            string sessionId,
            ulong lifecycleGeneration)
        {
            PrincipalCredentialAuthority.RequireValue(
                sessionId,
                nameof(sessionId));
            lock (_sync)
            {
                foreach (ScopeLedger scope
                    in _active.Values
                        .Where(candidate =>
                            string.Equals(
                                candidate.Key.SessionId,
                                sessionId,
                                StringComparison.Ordinal)
                            && candidate.LifecycleGeneration
                                == lifecycleGeneration)
                        .ToArray())
                {
                    if (scope.OpenCorrelations.Count != 0
                        || scope.PendingResponseDeliveries
                            .Count != 0)
                    {
                        DrainPendingResponseDeliveriesLocked(
                            scope,
                            "session_closed_with_action_in_flight");
                        MarkPendingTruncation(
                            scope,
                            "session_closed_with_action_in_flight");
                        SealPendingIfIdle(scope);
                    }
                    else
                    {
                        SealScopeLocked(
                            scope,
                            AuditSegmentTerminalKind.Completed,
                            "session_completed");
                    }
                }
            }
        }

        public void TruncateAll(string reasonCode)
        {
            PrincipalCredentialAuthority.RequireValue(
                reasonCode,
                nameof(reasonCode));
            lock (_sync)
            {
                foreach (ScopeLedger scope
                    in _active.Values.ToArray())
                {
                    DrainPendingResponseDeliveriesLocked(
                        scope,
                        reasonCode,
                        includeWriteClaimed: true);
                    SealScopeLocked(
                        scope,
                        AuditSegmentTerminalKind.Truncated,
                        reasonCode);
                }
                _connections.Clear();
                _grants.Clear();
            }
        }

        public bool TryDelete(
            AgentAuditScopeKey key,
            string reasonCode,
            out AgentAuditDeletionReceipt receipt)
        {
            receipt = null;
            PrincipalCredentialAuthority.RequireValue(
                reasonCode,
                nameof(reasonCode));
            lock (_sync)
            {
                var scopes = new List<ScopeLedger>();
                if (_active.TryGetValue(
                        key,
                        out ScopeLedger active))
                {
                    if (active.OpenCorrelations.Count != 0
                        || active.PendingResponseDeliveries.Count != 0)
                        return false;
                    SealScopeLocked(
                        active,
                        AuditSegmentTerminalKind.Completed,
                        "retention_deleted");
                }
                if (_retained.TryGetValue(
                        key,
                        out List<ScopeLedger> retained))
                {
                    scopes.AddRange(retained);
                }
                if (scopes.Count == 0)
                    return false;

                int segmentCount = scopes.Sum(
                    scope => scope.Segments.Count);
                long eventCount = scopes.Sum(
                    scope => scope.NextAuditSequence - 1);
                _retained.Remove(key);
                receipt = new AgentAuditDeletionReceipt(
                    OpaqueIdGenerator.Create("auditdelete"),
                    segmentCount,
                    eventCount,
                    ContentFreeDeletionReason(reasonCode),
                    _clock.UtcNow,
                    true);
                _deletionReceipts.Enqueue(receipt);
                while (_deletionReceipts.Count
                    > MaximumDeletionReceipts)
                {
                    _deletionReceipts.Dequeue();
                }
                return true;
            }
        }

        public ReadOnlyCollection<ScopedAuditLedgerSnapshot>
            SnapshotExact(AgentAuditScopeKey key)
        {
            lock (_sync)
            {
                if (!_retained.TryGetValue(
                        key,
                        out List<ScopeLedger> scopes))
                {
                    return Array.AsReadOnly(
                        Array.Empty<ScopedAuditLedgerSnapshot>());
                }
                return Array.AsReadOnly(
                    scopes.Select(CreateSnapshot).ToArray());
            }
        }

        public bool TrySnapshotExport(
            PrincipalCredential principal,
            string sessionId,
            ulong lifecycleGeneration,
            string consentPurpose,
            long fromAuditSequence,
            int maximumRecords,
            out ScopedAuditExportSnapshot snapshot,
            out string reasonCode)
        {
            snapshot = null;
            lock (_sync)
            {
                if (_disposed)
                {
                    reasonCode = "audit_unavailable";
                    return false;
                }
                if (principal == null
                    || string.IsNullOrWhiteSpace(sessionId)
                    || lifecycleGeneration == 0
                    || string.IsNullOrWhiteSpace(
                        consentPurpose)
                    || fromAuditSequence < 0
                    || maximumRecords <= 0)
                {
                    reasonCode = "arguments_invalid";
                    return false;
                }
                var key = new AgentAuditScopeKey(
                    principal.SecurityPrincipalId,
                    sessionId,
                    consentPurpose);
                if (!_active.TryGetValue(
                        key,
                        out ScopeLedger scope)
                    || !ScopeBindingMatches(
                        scope,
                        principal,
                        scope.ConnectionId,
                        lifecycleGeneration)
                    || !scope.TrustedConnectionPrelude
                    || !scope.ActionCoverage
                    || !scope.ObservationGrantCoverage
                    || !scope.WriteLeaseCoverage)
                {
                    reasonCode =
                        "audit_scope_incomplete";
                    return false;
                }
                if (!VerifyScopeLocked(
                        scope,
                        out reasonCode))
                {
                    return false;
                }

                var all =
                    new List<ScopedAuditExportRecord>();
                long auditSequence = 1;
                foreach (SegmentLedger segment
                    in scope.Segments
                        .OrderBy(
                            value =>
                                value.SegmentOrdinal))
                {
                    foreach (AuditEntry entry
                        in segment.Segment.Snapshot())
                    {
                        all.Add(
                            new ScopedAuditExportRecord(
                                auditSequence++,
                                segment.SegmentOrdinal,
                                entry));
                    }
                }
                long lastAvailable =
                    auditSequence - 1;
                long firstRequested =
                    fromAuditSequence == 0
                        ? 1
                        : fromAuditSequence;
                if (firstRequested > lastAvailable + 1)
                {
                    reasonCode =
                        "audit_sequence_invalid";
                    return false;
                }
                ScopedAuditExportRecord[] selected =
                    all.Where(record =>
                            record.AuditSequence
                                >= firstRequested)
                        .Take(maximumRecords)
                        .ToArray();
                long lastSelected =
                    selected.Length == 0
                        ? firstRequested - 1
                        : selected[^1].AuditSequence;
                string previousEntryHash =
                    firstRequested <= 1
                        ? AppendOnlyAuditSegment
                            .GenesisHash
                        : all[(int)
                            Math.Min(
                                all.Count,
                                firstRequested - 1)
                            - 1]
                            .Entry.EntryHash;
                snapshot =
                    new ScopedAuditExportSnapshot(
                        scope.ScopeId,
                        scope.Key,
                        scope.CredentialId,
                        scope.CredentialGeneration,
                        scope.LifecycleGeneration,
                        selected.Length == 0
                            ? firstRequested
                            : selected[0]
                                .AuditSequence,
                        lastSelected,
                        previousEntryHash,
                        all.Count == 0
                            ? AppendOnlyAuditSegment
                                .GenesisHash
                            : all[^1].Entry.EntryHash,
                        lastSelected < lastAvailable,
                        Array.AsReadOnly(selected));
                reasonCode = null;
                return true;
            }
        }

        public ReadOnlyCollection<AgentAuditDeletionReceipt>
            DeletionReceipts()
        {
            lock (_sync)
            {
                return Array.AsReadOnly(
                    _deletionReceipts.ToArray());
            }
        }

        public void Dispose()
        {
            lock (_sync)
            {
                if (_disposed)
                    return;
                foreach (ScopeLedger scope
                    in _active.Values.ToArray())
                {
                    bool hadActionInFlight =
                        scope.OpenCorrelations.Count != 0
                        || scope.PendingResponseDeliveries
                            .Count != 0;
                    DrainPendingResponseDeliveriesLocked(
                        scope,
                        "manager_disposed_with_action_in_flight",
                        includeWriteClaimed: true);
                    SealScopeLocked(
                        scope,
                        hadActionInFlight
                            ? AuditSegmentTerminalKind.Truncated
                            : AuditSegmentTerminalKind.Completed,
                        hadActionInFlight
                            ? "manager_disposed_with_action_in_flight"
                            : "manager_disposed");
                }
                _connections.Clear();
                _grants.Clear();
                _disposed = true;
            }
        }

        private bool TryCreateScope(
            PrincipalCredential principal,
            string connectionId,
            string sessionId,
            ulong lifecycleGeneration,
            string consentPurpose,
            TrustedConnection connection,
            out ScopeLedger scope,
            out string reasonCode)
        {
            scope = null;
            if (_retained.Values.Sum(items => items.Count)
                >= MaximumRetainedScopes)
            {
                reasonCode = "audit_scope_capacity";
                return false;
            }
            if (!IsCredentialAndScopeActive(
                    principal,
                    sessionId,
                    lifecycleGeneration,
                    consentPurpose,
                    out reasonCode))
            {
                return false;
            }
            var key = new AgentAuditScopeKey(
                principal.SecurityPrincipalId,
                sessionId,
                consentPurpose);
            scope = new ScopeLedger(
                key,
                OpaqueIdGenerator.Create("auditscope"),
                principal.CredentialId,
                principal.ClientInstanceId,
                principal.Generation,
                lifecycleGeneration,
                connectionId,
                connection != null);
            _active.Add(scope.Key, scope);
            if (!_retained.TryGetValue(
                    scope.Key,
                    out List<ScopeLedger> retained))
            {
                retained = new List<ScopeLedger>();
                _retained.Add(scope.Key, retained);
            }
            retained.Add(scope);
            StartSegmentLocked(scope, null);
            if (connection != null)
            {
                AppendConnectionPreludeLocked(
                    scope,
                    connection);
            }
            reasonCode = null;
            return true;
        }

        private bool IsCredentialAndScopeActive(
            AgentRuntimeAuditEventEnvelope auditEvent,
            out string reasonCode)
        {
            return IsCredentialAndScopeActive(
                auditEvent.Principal,
                auditEvent.SessionId,
                auditEvent.LifecycleGeneration,
                auditEvent.ConsentPurpose,
                out reasonCode);
        }

        private bool IsCredentialAndScopeActive(
            PrincipalCredential presented,
            string sessionId,
            ulong lifecycleGeneration,
            string consentPurpose,
            out string reasonCode)
        {
            if (!_credentials.TryResolveActive(
                    presented.CredentialId,
                    presented.ClientInstanceId,
                    out PrincipalCredential active,
                    out reasonCode)
                || !ReferenceEquals(active, presented)
                || !string.Equals(
                    active.SecurityPrincipalId,
                    presented.SecurityPrincipalId,
                    StringComparison.Ordinal)
                || active.Generation
                    != presented.Generation)
            {
                reasonCode ??= "credential_inactive";
                return false;
            }
            if (!_scopeAuthority.TryAuthorize(
                    active,
                    sessionId,
                    lifecycleGeneration,
                    consentPurpose,
                    out reasonCode))
            {
                reasonCode ??= "audit_scope_denied";
                return false;
            }
            reasonCode = null;
            return true;
        }

        private static bool ScopeBindingMatches(
            ScopeLedger scope,
            PrincipalCredential principal,
            string connectionId,
            ulong lifecycleGeneration)
        {
            return string.Equals(
                    scope.CredentialId,
                    principal.CredentialId,
                    StringComparison.Ordinal)
                && string.Equals(
                    scope.ClientInstanceId,
                    principal.ClientInstanceId,
                    StringComparison.Ordinal)
                && scope.CredentialGeneration
                    == principal.Generation
                && scope.LifecycleGeneration
                    == lifecycleGeneration
                && (string.IsNullOrWhiteSpace(connectionId)
                    || string.Equals(
                        scope.ConnectionId,
                        connectionId,
                        StringComparison.Ordinal));
        }

        private AgentRuntimeAuditCommit AppendEventLocked(
            ScopeLedger scope,
            AgentRuntimeAuditEventEnvelope auditEvent)
        {
            if (string.Equals(
                    auditEvent.EventType,
                    AgentRuntimeAuditEventTypes
                        .ActionBindingValidated,
                    StringComparison.Ordinal))
            {
                AppendActionBindingFactsLocked(
                    scope,
                    auditEvent);
            }
            EnsureSegmentCapacityLocked(scope);
            long auditSequence = scope.NextAuditSequence;
            string payload = CanonicalEventPayload(
                auditSequence,
                auditEvent);
            AuditEntry entry =
                scope.Current.Segment.Append(
                    auditEvent.EventType,
                    payload);
            scope.Current.EntryCount++;
            scope.NextAuditSequence =
                checked(auditSequence + 1);
            scope.ActionCoverage = true;
            return new AgentRuntimeAuditCommit(
                scope.ScopeId,
                auditSequence,
                entry.SegmentId,
                entry.ServerSequence,
                entry.EventType,
                entry.PayloadHash,
                entry.EntryHash);
        }

        private void AppendActionBindingFactsLocked(
            ScopeLedger scope,
            AgentRuntimeAuditEventEnvelope auditEvent)
        {
            _grants.TryGetValue(
                auditEvent.Action.ObservationGrantId,
                out TrustedGrant trustedGrant);
            bool trustedGrantMatches =
                trustedGrant != null
                && string.Equals(
                    trustedGrant.SecurityPrincipalId,
                    scope.Key.SecurityPrincipalId,
                    StringComparison.Ordinal)
                && string.Equals(
                    trustedGrant.SessionId,
                    scope.Key.SessionId,
                    StringComparison.Ordinal)
                && trustedGrant.LifecycleGeneration
                    == scope.LifecycleGeneration
                && trustedGrant.Active;
            AppendSyntheticFactLocked(
                scope,
                AgentRuntimeAuditEventTypes
                    .ObservationGrantBound,
                new
                {
                    correlationId =
                        auditEvent.CorrelationId,
                    observationGrantId =
                        auditEvent.Action
                            .ObservationGrantId,
                    observationId =
                        auditEvent.Action.ObservationId,
                    targetId =
                        auditEvent.Action.TargetId,
                    targetScope =
                        trustedGrantMatches
                            ? trustedGrant.TargetScope
                            : null,
                    dataScope =
                        trustedGrantMatches
                            ? trustedGrant.DataScope
                            : null,
                    allowExport =
                        trustedGrantMatches
                            ? (bool?)trustedGrant.AllowExport
                            : null,
                    allowPersistence =
                        trustedGrantMatches
                            ? (bool?)trustedGrant
                                .AllowPersistence
                            : null,
                    consentReceiptHash =
                        trustedGrantMatches
                            ? trustedGrant
                                .ConsentReceiptHash
                            : null,
                    issuedByTrustedHost =
                        trustedGrantMatches,
                    bindingValidated = true
                });
            scope.ObservationGrantCoverage =
                scope.ObservationGrantCoverage
                || trustedGrantMatches;
            if (trustedGrantMatches)
            {
                scope.ReferencedObservationGrants.Add(
                    auditEvent.Action.ObservationGrantId);
            }

            if (auditEvent.Lease == null)
            {
                return;
            }
            AppendSyntheticFactLocked(
                scope,
                AgentRuntimeAuditEventTypes
                    .WriteLeaseBound,
                new
                {
                    correlationId =
                        auditEvent.CorrelationId,
                    leaseId =
                        auditEvent.Lease.LeaseId,
                    kind =
                        auditEvent.Lease.Kind.ToString(),
                    state =
                        auditEvent.Lease.State.ToString(),
                    operation =
                        auditEvent.Action.Operation,
                    targetId =
                        auditEvent.Action.TargetId,
                    consentReceiptHash =
                        HashOptional(
                            auditEvent.Lease
                                .ConsentReceipt),
                    bindingValidated = true
                });
            scope.WriteLeaseCoverage = true;
            scope.ReferencedLeases.Add(
                auditEvent.Lease.LeaseId);
        }

        private AgentRuntimeAuditCommit
            AppendTrustedFactLocked(
                ScopeLedger scope,
                AgentRuntimeTrustedAuditFact fact)
        {
            AgentRuntimeAuditCommit commit =
                AppendSyntheticFactLocked(
                    scope,
                    fact.EventType,
                    new
                    {
                        correlationId =
                            fact.CorrelationId,
                        connectionId =
                            fact.ConnectionId,
                        observationGrantId =
                            fact.ObservationGrantId,
                        leaseId = fact.LeaseId,
                        capability = fact.Capability,
                        targetScope =
                            NormalizeScope(
                                fact.TargetScope),
                        dataScope =
                            NormalizeScope(
                                fact.DataScope),
                        allowExport =
                            fact.AllowExport,
                        allowPersistence =
                            fact.AllowPersistence,
                        state = fact.State,
                        reasonCode =
                            fact.ReasonCode,
                        consentReceiptHash =
                            HashOptional(
                                fact.ConsentReceipt),
                        artifactId =
                            fact.ArtifactId,
                        exportedThroughAuditSequence =
                            fact
                                .ExportedThroughAuditSequence
                    });
            if (string.Equals(
                    fact.EventType,
                    AgentRuntimeAuditEventTypes
                        .ObservationGrantIssued,
                    StringComparison.Ordinal)
                || string.Equals(
                    fact.EventType,
                    AgentRuntimeAuditEventTypes
                        .ObservationGrantBound,
                    StringComparison.Ordinal))
            {
                scope.ObservationGrantCoverage = true;
            }
            if (string.Equals(
                    fact.EventType,
                    AgentRuntimeAuditEventTypes
                        .WriteLeaseAcquired,
                    StringComparison.Ordinal)
                || string.Equals(
                    fact.EventType,
                    AgentRuntimeAuditEventTypes
                        .WriteLeaseBound,
                    StringComparison.Ordinal))
            {
                scope.WriteLeaseCoverage = true;
            }
            return commit;
        }

        private void TrackTrustedGrantLocked(
            AgentRuntimeTrustedAuditFact fact)
        {
            if (string.Equals(
                    fact.EventType,
                    AgentRuntimeAuditEventTypes
                        .ObservationGrantIssued,
                    StringComparison.Ordinal)
                && !string.IsNullOrWhiteSpace(
                    fact.ObservationGrantId))
            {
                _grants[fact.ObservationGrantId] =
                    new TrustedGrant(
                        fact.ObservationGrantId,
                        fact.Principal
                            .SecurityPrincipalId,
                        fact.SessionId,
                        fact.LifecycleGeneration,
                        NormalizeScope(
                            fact.TargetScope),
                        NormalizeScope(
                            fact.DataScope),
                        fact.AllowExport == true,
                        fact.AllowPersistence == true,
                        HashOptional(
                            fact.ConsentReceipt),
                        true);
                return;
            }
            if (!string.Equals(
                    fact.EventType,
                    AgentRuntimeAuditEventTypes
                        .ObservationGrantRevoked,
                    StringComparison.Ordinal)
                || string.IsNullOrWhiteSpace(
                    fact.ObservationGrantId)
                || !_grants.TryGetValue(
                    fact.ObservationGrantId,
                    out TrustedGrant grant))
            {
                return;
            }
            _grants[fact.ObservationGrantId] =
                grant with { Active = false };
            foreach (ScopeLedger referenced
                in _active.Values
                    .Where(candidate =>
                        candidate
                            .ReferencedObservationGrants
                            .Contains(
                                fact.ObservationGrantId))
                    .ToArray())
            {
                AppendSyntheticFactLocked(
                    referenced,
                    AgentRuntimeAuditEventTypes
                        .ObservationGrantRevoked,
                    new
                    {
                        observationGrantId =
                            fact.ObservationGrantId,
                        reasonCode =
                            fact.ReasonCode
                    });
            }
        }

        private AgentRuntimeAuditCommit
            AppendSyntheticFactLocked(
                ScopeLedger scope,
                string eventType,
                object fact)
        {
            EnsureSegmentCapacityLocked(scope);
            long auditSequence = scope.NextAuditSequence;
            string json = JsonSerializer.Serialize(
                new
                {
                    auditSequence,
                    scope = new
                    {
                        securityPrincipalId =
                            scope.Key.SecurityPrincipalId,
                        sessionId =
                            scope.Key.SessionId,
                        consentPurpose =
                            scope.Key.ConsentPurpose,
                        credentialGeneration =
                            scope.CredentialGeneration,
                        lifecycleGeneration =
                            scope.LifecycleGeneration
                    },
                    eventType,
                    fact
                },
                AgentProtocolV1.JsonOptions);
            string payload =
                CanonicalJsonV1.Canonicalize(json);
            AuditEntry entry =
                scope.Current.Segment.Append(
                    eventType,
                    payload);
            scope.Current.EntryCount++;
            scope.NextAuditSequence =
                checked(auditSequence + 1);
            return new AgentRuntimeAuditCommit(
                scope.ScopeId,
                auditSequence,
                entry.SegmentId,
                entry.ServerSequence,
                entry.EventType,
                entry.PayloadHash,
                entry.EntryHash);
        }

        private void AppendConnectionPreludeLocked(
            ScopeLedger scope,
            TrustedConnection connection)
        {
            AppendSyntheticFactLocked(
                scope,
                AgentRuntimeAuditEventTypes.ConnectionOpened,
                new
                {
                    connectionId =
                        connection.ConnectionId,
                    clientInstanceId =
                        connection.Principal
                            .ClientInstanceId,
                    principalKind =
                        connection.Principal
                            .PrincipalKind.ToString(),
                    sessionMode =
                        connection.Principal
                            .SessionMode.ToString()
                });
            AppendSyntheticFactLocked(
                scope,
                AgentRuntimeAuditEventTypes
                    .AuthenticationSucceeded,
                new
                {
                    connectionId =
                        connection.ConnectionId,
                    credentialId =
                        connection.Principal
                            .CredentialId,
                    issuerReceiptHash =
                        HashOptional(
                            connection.Principal
                                .IssuerReceipt)
                });
        }

        private void TryAppendRevocationFactLocked(
            ScopeLedger scope,
            string eventType,
            string connectionId,
            string reasonCode)
        {
            try
            {
                AppendSyntheticFactLocked(
                    scope,
                    eventType,
                    new
                    {
                        connectionId,
                        reasonCode
                    });
            }
            catch
            {
                MarkPendingTruncation(
                    scope,
                    reasonCode);
            }
        }

        private void TryAppendResourceRevocationFactLocked(
            ScopeLedger scope,
            string eventType,
            string observationGrantId,
            string leaseId,
            string reasonCode)
        {
            try
            {
                AppendSyntheticFactLocked(
                    scope,
                    eventType,
                    new
                    {
                        observationGrantId,
                        leaseId,
                        reasonCode
                    });
            }
            catch
            {
                MarkPendingTruncation(
                    scope,
                    reasonCode);
            }
        }

        private void EnsureSegmentCapacityLocked(
            ScopeLedger scope)
        {
            // Reserve one physical entry for the mandatory completed or
            // truncated terminal fact. The configured bound therefore
            // applies to every segment including its terminal entry.
            if (scope.Current.EntryCount
                < _maximumEntriesPerSegment - 1)
            {
                return;
            }
            SealCurrentSegmentLocked(
                scope,
                AuditSegmentTerminalKind.Completed,
                "bounded_rollover");
            StartSegmentLocked(
                scope,
                scope.Segments[^1].Receipt.FinalHash);
        }

        private void StartSegmentLocked(
            ScopeLedger scope,
            string previousSegmentFinalHash)
        {
            var state = new SegmentLedger(
                scope.Segments.Count + 1,
                previousSegmentFinalHash,
                new AppendOnlyAuditSegment(_clock));
            scope.Segments.Add(state);
            scope.Current = state;

            long auditSequence = scope.NextAuditSequence;
            string payload = CanonicalSystemPayload(
                auditSequence,
                scope,
                state,
                "segment_opened",
                previousSegmentFinalHash);
            state.Segment.Append(
                "segment_opened",
                payload);
            state.EntryCount++;
            scope.NextAuditSequence =
                checked(auditSequence + 1);
        }

        private void SealCurrentSegmentLocked(
            ScopeLedger scope,
            AuditSegmentTerminalKind terminalKind,
            string reasonCode)
        {
            SegmentLedger current = scope.Current;
            if (current == null
                || current.Receipt != null)
            {
                return;
            }
            long auditSequence = scope.NextAuditSequence;
            string payload = CanonicalSystemPayload(
                auditSequence,
                scope,
                current,
                terminalKind
                    == AuditSegmentTerminalKind.Completed
                        ? "segment_completed"
                        : "segment_truncated",
                reasonCode);
            current.Receipt =
                terminalKind
                    == AuditSegmentTerminalKind.Completed
                        ? current.Segment.SealCompleted(payload)
                        : current.Segment.SealTruncated(
                            reasonCode,
                            payload);
            scope.NextAuditSequence =
                checked(auditSequence + 1);
        }

        private void SealScopeLocked(
            ScopeLedger scope,
            AuditSegmentTerminalKind terminalKind,
            string reasonCode)
        {
            if (scope.Sealed)
                return;
            bool responseDeliveryPending =
                scope.PendingResponseDeliveries.Count != 0;
            DrainPendingResponseDeliveriesLocked(
                scope,
                reasonCode);
            if (scope.PendingResponseDeliveries.Count != 0)
            {
                MarkPendingTruncation(scope, reasonCode);
                return;
            }
            if (responseDeliveryPending
                && terminalKind
                    == AuditSegmentTerminalKind.Completed)
            {
                terminalKind =
                    AuditSegmentTerminalKind.Truncated;
            }
            SealCurrentSegmentLocked(
                scope,
                terminalKind,
                reasonCode);
            scope.Sealed = true;
            scope.PendingTruncationReason = null;
            _active.Remove(scope.Key);
        }

        private static void MarkPendingTruncation(
            ScopeLedger scope,
            string reasonCode)
        {
            scope.PendingTruncationReason ??=
                string.IsNullOrWhiteSpace(reasonCode)
                    ? "audit_scope_invalidated"
                    : reasonCode;
        }

        private void SealPendingIfIdle(ScopeLedger scope)
        {
            if (scope.OpenCorrelations.Count == 0
                && scope.PendingResponseDeliveries.Count == 0
                && scope.PendingTruncationReason != null)
            {
                SealScopeLocked(
                    scope,
                    AuditSegmentTerminalKind.Truncated,
                    scope.PendingTruncationReason);
            }
        }

        private void DrainPendingResponseDeliveriesLocked(
            ScopeLedger scope,
            string reasonCode,
            bool includeWriteClaimed = false)
        {
            if (scope.PendingResponseDeliveries.Count == 0)
                return;
            string normalizedReason =
                string.IsNullOrWhiteSpace(reasonCode)
                    ? "response_delivery_unknown"
                    : reasonCode;
            foreach (PendingResponseDelivery pending
                in scope.PendingResponseDeliveries
                    .Values
                    .Where(pending =>
                        includeWriteClaimed
                        || !pending.WriteClaimed)
                    .ToArray())
            {
                try
                {
                    AppendSyntheticFactLocked(
                        scope,
                        AgentRuntimeAuditEventTypes
                            .ActionResponseUnknown,
                        new
                        {
                            correlationId =
                                pending.CorrelationId,
                            actionId = pending.ActionId,
                            actionPayloadHash =
                                pending.ActionPayloadHash,
                            terminalAuditSequence =
                                pending.TerminalAuditSequence,
                            terminalEntryHash =
                                pending.TerminalEntryHash,
                            disposition =
                                AgentRuntimeActionResponseDisposition
                                    .Unknown.ToString(),
                            reasonCode =
                                normalizedReason
                        });
                }
                catch
                {
                    MarkPendingTruncation(
                        scope,
                        "audit_append_failed");
                }
                scope.PendingResponseDeliveries.Remove(
                    pending.CorrelationId);
            }
        }

        private static bool TryValidateEvent(
            AgentRuntimeAuditEventEnvelope auditEvent,
            out string reasonCode)
        {
            reasonCode = "audit_event_invalid";
            if (auditEvent?.Principal == null
                || string.IsNullOrWhiteSpace(
                    auditEvent.SessionId)
                || auditEvent.LifecycleGeneration == 0
                || string.IsNullOrWhiteSpace(
                    auditEvent.ConsentPurpose)
                || string.IsNullOrWhiteSpace(
                    auditEvent.CorrelationId)
                || string.IsNullOrWhiteSpace(
                    auditEvent.EventType)
                || auditEvent.Action == null
                || string.IsNullOrWhiteSpace(
                    auditEvent.ActionPayloadHash)
                || auditEvent.ActionPayloadHash.Length != 64)
            {
                return false;
            }
            if (string.Equals(
                    auditEvent.EventType,
                    AgentRuntimeAuditEventTypes
                        .ActionResponseWritten,
                    StringComparison.Ordinal)
                || string.Equals(
                    auditEvent.EventType,
                    AgentRuntimeAuditEventTypes
                        .ActionResponseUnknown,
                    StringComparison.Ordinal))
            {
                reasonCode = "audit_event_reserved";
                return false;
            }
            if (auditEvent.TerminalAction
                != string.Equals(
                    auditEvent.EventType,
                    AgentRuntimeAuditEventTypes.ActionTerminal,
                    StringComparison.Ordinal))
            {
                return false;
            }
            if (auditEvent.TerminalAction
                && !auditEvent.Outcome.HasValue)
            {
                return false;
            }
            if (auditEvent.ResponseDeliveryPending
                && !auditEvent.TerminalAction)
            {
                return false;
            }
            reasonCode = null;
            return true;
        }

        private static bool TryValidateTrustedFact(
            AgentRuntimeTrustedAuditFact fact,
            out string reasonCode)
        {
            reasonCode = "audit_event_invalid";
            if (fact?.Principal == null
                || string.IsNullOrWhiteSpace(
                    fact.ConnectionId)
                || string.IsNullOrWhiteSpace(
                    fact.SessionId)
                || fact.LifecycleGeneration == 0
                || string.IsNullOrWhiteSpace(
                    fact.ConsentPurpose)
                || string.IsNullOrWhiteSpace(
                    fact.EventType))
            {
                return false;
            }
            string[] allowed =
            {
                AgentRuntimeAuditEventTypes
                    .ObservationGrantIssued,
                AgentRuntimeAuditEventTypes
                    .ObservationGrantRevoked,
                AgentRuntimeAuditEventTypes
                    .WriteLeaseAcquired,
                AgentRuntimeAuditEventTypes
                    .WriteLeaseRenewed,
                AgentRuntimeAuditEventTypes
                    .WriteLeaseReleased,
                AgentRuntimeAuditEventTypes
                    .ObservationCaptured,
                AgentRuntimeAuditEventTypes
                    .TraceExportAuthorized,
                AgentRuntimeAuditEventTypes
                    .TraceExportCompleted,
                AgentRuntimeAuditEventTypes
                    .TraceExportFailed
            };
            if (!allowed.Contains(
                    fact.EventType,
                    StringComparer.Ordinal))
            {
                return false;
            }
            reasonCode = null;
            return true;
        }

        private bool TryResolveTrustedConnection(
            string connectionId,
            PrincipalCredential principal,
            string sessionId,
            ulong lifecycleGeneration,
            out TrustedConnection connection)
        {
            connection = null;
            return !string.IsNullOrWhiteSpace(connectionId)
                && principal != null
                && _connections.TryGetValue(
                    connectionId,
                    out connection)
                && ReferenceEquals(
                    connection.Principal,
                    principal)
                && string.Equals(
                    connection.SessionId,
                    sessionId,
                    StringComparison.Ordinal)
                && connection.LifecycleGeneration
                    == lifecycleGeneration;
        }

        private static bool VerifyScopeLocked(
            ScopeLedger scope,
            out string reasonCode)
        {
            string previousSegmentFinalHash = null;
            long auditSequence = 1;
            foreach (SegmentLedger segment
                in scope.Segments
                    .OrderBy(
                        value =>
                            value.SegmentOrdinal))
            {
                if (!string.Equals(
                        segment.PreviousSegmentFinalHash,
                        previousSegmentFinalHash,
                        StringComparison.Ordinal))
                {
                    reasonCode =
                        "audit_segment_link_invalid";
                    return false;
                }
                ReadOnlyCollection<AuditEntry> entries =
                    segment.Segment.Snapshot();
                AuditVerificationResult verification =
                    AppendOnlyAuditSegment.Verify(
                        entries,
                        segment.Segment.SegmentId,
                        segment.Receipt);
                if (!verification.Valid)
                {
                    reasonCode =
                        verification.ReasonCode
                        ?? "audit_chain_invalid";
                    return false;
                }
                foreach (AuditEntry entry in entries)
                {
                    try
                    {
                        using JsonDocument document =
                            JsonDocument.Parse(
                                entry.CanonicalPayload);
                        if (!document.RootElement
                                .TryGetProperty(
                                    "auditSequence",
                                    out JsonElement value)
                            || !value.TryGetInt64(
                                out long actual)
                            || actual != auditSequence)
                        {
                            reasonCode =
                                "audit_sequence_invalid";
                            return false;
                        }
                    }
                    catch (JsonException)
                    {
                        reasonCode =
                            "audit_payload_invalid";
                        return false;
                    }
                    auditSequence++;
                }
                previousSegmentFinalHash =
                    entries.Count == 0
                        ? previousSegmentFinalHash
                        : entries[^1].EntryHash;
            }
            if (scope.NextAuditSequence
                != auditSequence)
            {
                reasonCode = "audit_sequence_invalid";
                return false;
            }
            reasonCode = null;
            return true;
        }

        private static string[] NormalizeScope(
            IReadOnlyCollection<string> values)
        {
            return (values ?? Array.Empty<string>())
                .Where(value =>
                    !string.IsNullOrWhiteSpace(value))
                .Distinct(StringComparer.Ordinal)
                .OrderBy(value => value, StringComparer.Ordinal)
                .ToArray();
        }

        private static string CanonicalEventPayload(
            long auditSequence,
            AgentRuntimeAuditEventEnvelope value)
        {
            ActionEnvelope action = value.Action;
            WriteLease lease = value.Lease;
            string json = JsonSerializer.Serialize(
                new
                {
                    auditSequence,
                    scope = new
                    {
                        securityPrincipalId =
                            value.Principal.SecurityPrincipalId,
                        sessionId = value.SessionId,
                        consentPurpose = value.ConsentPurpose,
                        credentialGeneration =
                            value.Principal.Generation,
                        lifecycleGeneration =
                            value.LifecycleGeneration
                    },
                    correlationId = value.CorrelationId,
                    eventType = value.EventType,
                    action = new
                    {
                        actionId = action.ActionId,
                        actionPayloadHash =
                            value.ActionPayloadHash,
                        operation = action.Operation,
                        targetId = action.TargetId,
                        observationGrantId =
                            action.ObservationGrantId,
                        observationId =
                            action.ObservationId,
                        leaseId = action.LeaseId,
                        expectedLifecycleGeneration =
                            action.ExpectedLifecycleGeneration,
                        expectedAttemptId =
                            action.ExpectedAttemptId,
                        expectedAttemptGeneration =
                            action.ExpectedAttemptGeneration,
                        expectedSurfaceEpoch =
                            action.ExpectedSurfaceEpoch,
                        expectedPanelInstanceId =
                            action.ExpectedPanelInstanceId,
                        expectedDocumentGeneration =
                            action.ExpectedDocumentGeneration,
                        expectedSemanticGeneration =
                            action.ExpectedSemanticGeneration,
                        expectedCoordinateSpaceVersion =
                            action.ExpectedCoordinateSpaceVersion,
                        expectedFocusEpoch =
                            action.ExpectedFocusEpoch,
                        expectedModalEpoch =
                            action.ExpectedModalEpoch
                    },
                    lease = lease == null
                        ? null
                        : new
                        {
                            kind = lease.Kind.ToString(),
                            state = lease.State.ToString(),
                            consentReceiptHash =
                                HashOptional(
                                    lease.ConsentReceipt),
                            previewHash =
                                lease.PreviewHash,
                            expectedRevision =
                                lease.ExpectedRevision
                        },
                    outcome = value.Outcome?.ToString(),
                    evidenceKind =
                        value.EvidenceKind?.ToString(),
                    reasonCode = value.ReasonCode,
                    reconcileKind =
                        value.ReconcileKind?.ToString(),
                    beforeKeyframe = new
                    {
                        observationId =
                            action.ObservationId,
                        frameId = value.BeforeFrameId,
                        frameHash =
                            value.BeforeFrameHash,
                        unavailableReason =
                            value.BeforeFrameReasonCode
                    },
                    afterKeyframe = new
                    {
                        observationId =
                            value.AfterObservationId,
                        frameId = value.AfterFrameId,
                        frameHash =
                            value.AfterFrameHash,
                        unavailableReason =
                            value.AfterFrameReasonCode
                    },
                    domain = new
                    {
                        transactionId =
                            value.DomainTransactionId,
                        previewHash =
                            value.DomainPreviewHash,
                        restoreSecretIssued =
                            value.RestoreSecretIssued,
                        restoreExpiresAtUtc =
                            value.RestoreExpiresAtUtc
                    },
                    dispatchMayHaveStarted =
                        value.DispatchMayHaveStarted,
                    terminalAction =
                        value.TerminalAction,
                    responseDeliveryPending =
                        value.ResponseDeliveryPending
                },
                AgentProtocolV1.JsonOptions);
            return CanonicalJsonV1.Canonicalize(json);
        }

        private static string CanonicalSystemPayload(
            long auditSequence,
            ScopeLedger scope,
            SegmentLedger segment,
            string eventType,
            string value)
        {
            string json = JsonSerializer.Serialize(
                new
                {
                    auditSequence,
                    scopeId = scope.ScopeId,
                    segmentOrdinal =
                        segment.SegmentOrdinal,
                    eventType,
                    previousSegmentFinalHash =
                        segment.PreviousSegmentFinalHash,
                    value
                },
                AgentProtocolV1.JsonOptions);
            return CanonicalJsonV1.Canonicalize(json);
        }

        private static string HashOptional(string value)
        {
            if (string.IsNullOrEmpty(value))
                return null;
            return Convert.ToHexString(
                    SHA256.HashData(
                        Encoding.UTF8.GetBytes(value)))
                .ToLowerInvariant();
        }

        private static string ContentFreeDeletionReason(
            string reasonCode)
        {
            return reasonCode switch
            {
                "retention_expired" =>
                    "retention_expired",
                "user_requested" =>
                    "user_requested",
                "consent_revoked" =>
                    "consent_revoked",
                "policy_evicted" =>
                    "policy_evicted",
                _ => "retention_deleted"
            };
        }

        private static ScopedAuditLedgerSnapshot CreateSnapshot(
            ScopeLedger scope)
        {
            return new ScopedAuditLedgerSnapshot(
                scope.ScopeId,
                scope.Key,
                scope.CredentialId,
                scope.CredentialGeneration,
                scope.LifecycleGeneration,
                !scope.Sealed,
                scope.TrustedConnectionPrelude,
                scope.ActionCoverage,
                scope.ObservationGrantCoverage,
                scope.WriteLeaseCoverage,
                Array.AsReadOnly(
                    scope.Segments.Select(segment =>
                        new ScopedAuditSegmentSnapshot(
                            segment.SegmentOrdinal,
                            segment.PreviousSegmentFinalHash,
                            segment.Segment.Snapshot(),
                            segment.Receipt))
                        .ToArray()));
        }

        private sealed class ScopeLedger
        {
            public ScopeLedger(
                AgentAuditScopeKey key,
                string scopeId,
                string credentialId,
                string clientInstanceId,
                long credentialGeneration,
                ulong lifecycleGeneration,
                string connectionId,
                bool trustedConnectionPrelude)
            {
                Key = key;
                ScopeId = scopeId;
                CredentialId = credentialId;
                ClientInstanceId = clientInstanceId;
                CredentialGeneration =
                    credentialGeneration;
                LifecycleGeneration =
                    lifecycleGeneration;
                ConnectionId = connectionId;
                TrustedConnectionPrelude =
                    trustedConnectionPrelude;
            }

            public AgentAuditScopeKey Key { get; }
            public string ScopeId { get; }
            public string CredentialId { get; }
            public string ClientInstanceId { get; }
            public long CredentialGeneration { get; }
            public ulong LifecycleGeneration { get; }
            public string ConnectionId { get; }
            public bool TrustedConnectionPrelude { get; }
            public bool ActionCoverage { get; set; }
            public bool ObservationGrantCoverage { get; set; }
            public bool WriteLeaseCoverage { get; set; }
            public long NextAuditSequence { get; set; } = 1;
            public List<SegmentLedger> Segments { get; } =
                new List<SegmentLedger>();
            public HashSet<string> OpenCorrelations { get; } =
                new HashSet<string>(StringComparer.Ordinal);
            public Dictionary<string, PendingResponseDelivery>
                PendingResponseDeliveries { get; } =
                    new Dictionary<
                        string,
                        PendingResponseDelivery>(
                            StringComparer.Ordinal);
            public HashSet<string>
                ReferencedObservationGrants { get; } =
                    new HashSet<string>(
                        StringComparer.Ordinal);
            public HashSet<string> ReferencedLeases { get; } =
                new HashSet<string>(
                    StringComparer.Ordinal);
            public SegmentLedger Current { get; set; }
            public string PendingTruncationReason { get; set; }
            public bool Sealed { get; set; }
        }

        private sealed class SegmentLedger
        {
            public SegmentLedger(
                int segmentOrdinal,
                string previousSegmentFinalHash,
                AppendOnlyAuditSegment segment)
            {
                SegmentOrdinal = segmentOrdinal;
                PreviousSegmentFinalHash =
                    previousSegmentFinalHash;
                Segment = segment;
            }

            public int SegmentOrdinal { get; }
            public string PreviousSegmentFinalHash { get; }
            public AppendOnlyAuditSegment Segment { get; }
            public int EntryCount { get; set; }
            public AuditSegmentReceipt Receipt { get; set; }
        }

        private sealed record TrustedConnection(
            string ConnectionId,
            PrincipalCredential Principal,
            string SessionId,
            ulong LifecycleGeneration);

        private sealed class PendingResponseDelivery
        {
            public PendingResponseDelivery(
                PrincipalCredential principal,
                string connectionId,
                string correlationId,
                string actionId,
                string actionPayloadHash,
                long terminalAuditSequence,
                string terminalEntryHash)
            {
                Principal = principal;
                ConnectionId = connectionId;
                CorrelationId = correlationId;
                ActionId = actionId;
                ActionPayloadHash = actionPayloadHash;
                TerminalAuditSequence =
                    terminalAuditSequence;
                TerminalEntryHash = terminalEntryHash;
            }

            public PrincipalCredential Principal { get; }
            public string ConnectionId { get; }
            public string CorrelationId { get; }
            public string ActionId { get; }
            public string ActionPayloadHash { get; }
            public long TerminalAuditSequence { get; }
            public string TerminalEntryHash { get; }
            public bool WriteClaimed { get; set; }
        }

        private sealed record TrustedGrant(
            string ObservationGrantId,
            string SecurityPrincipalId,
            string SessionId,
            ulong LifecycleGeneration,
            string[] TargetScope,
            string[] DataScope,
            bool AllowExport,
            bool AllowPersistence,
            string ConsentReceiptHash,
            bool Active);
    }
}
