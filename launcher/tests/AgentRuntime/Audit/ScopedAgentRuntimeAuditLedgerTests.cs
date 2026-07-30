using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using CF7Launcher.AgentRuntime.Audit;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Security;
using CF7Launcher.Tests.AgentRuntime.Observation;
using CF7Launcher.Tests.AgentRuntime.Security;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.Audit
{
    public sealed class ScopedAgentRuntimeAuditLedgerTests
    {
        private const ulong LifecycleGeneration = 7;

        [Fact]
        public void ExactScopeKeysOwnPhysicallyIndependentLedgers()
        {
            using var fixture = new LedgerFixture();
            PrincipalCredential first = fixture.Issue(
                "client-first",
                AgentCapabilitiesV1.Click,
                AgentCapabilitiesV1.TypeText);
            PrincipalCredential second = fixture.Issue(
                "client-second",
                AgentCapabilitiesV1.Click);
            var expected = new[]
            {
                new ScopeCase(
                    first,
                    "session-a",
                    AgentCapabilitiesV1.Click,
                    "action-principal-session-purpose-a"),
                new ScopeCase(
                    first,
                    "session-b",
                    AgentCapabilitiesV1.Click,
                    "action-session-b"),
                new ScopeCase(
                    first,
                    "session-a",
                    AgentCapabilitiesV1.TypeText,
                    "action-purpose-type-text"),
                new ScopeCase(
                    second,
                    "session-a",
                    AgentCapabilitiesV1.Click,
                    "action-principal-second")
            };

            foreach (ScopeCase item in expected)
            {
                AppendCompletedAction(
                    fixture.Manager,
                    item.Principal,
                    item.SessionId,
                    item.ConsentPurpose,
                    item.ActionId);
            }
            fixture.Manager.CompleteSession(
                "session-a",
                LifecycleGeneration);
            fixture.Manager.CompleteSession(
                "session-b",
                LifecycleGeneration);

            ScopedAuditLedgerSnapshot[] snapshots = expected
                .Select(item =>
                {
                    var key = ScopeKey(item);
                    ScopedAuditLedgerSnapshot snapshot =
                        Assert.Single(
                            fixture.Manager.SnapshotExact(key));
                    Assert.Equal(key, snapshot.Scope);
                    Assert.False(snapshot.Active);
                    string payloads = string.Join(
                        "\n",
                        snapshot.Segments.SelectMany(
                            segment => segment.Entries)
                            .Select(entry =>
                                entry.CanonicalPayload));
                    Assert.Contains(item.ActionId, payloads);
                    foreach (string foreignActionId in expected
                        .Where(other => !ReferenceEquals(other, item))
                        .Select(other => other.ActionId))
                    {
                        Assert.DoesNotContain(
                            foreignActionId,
                            payloads);
                    }
                    return snapshot;
                })
                .ToArray();

            Assert.Equal(
                snapshots.Length,
                snapshots.Select(snapshot => snapshot.ScopeId)
                    .Distinct(StringComparer.Ordinal)
                    .Count());
            Assert.Equal(
                snapshots.Length,
                snapshots.Select(snapshot =>
                        snapshot.Segments[0].Entries[0].SegmentId)
                    .Distinct(StringComparer.Ordinal)
                    .Count());
        }

        [Fact]
        public void BoundedRolloverLinksCompletedVerifiableSegments()
        {
            using var fixture = new LedgerFixture(
                maximumEntriesPerSegment: 3);
            PrincipalCredential principal = fixture.Issue(
                "client-rollover",
                AgentCapabilitiesV1.Click);
            const string sessionId = "session-rollover";
            const string actionId = "action-rollover";

            Append(
                fixture.Manager,
                principal,
                sessionId,
                AgentCapabilitiesV1.Click,
                actionId,
                AgentRuntimeAuditEventTypes.ActionValidation);
            Append(
                fixture.Manager,
                principal,
                sessionId,
                AgentCapabilitiesV1.Click,
                actionId,
                AgentRuntimeAuditEventTypes.ActionBindingValidated);
            Append(
                fixture.Manager,
                principal,
                sessionId,
                AgentCapabilitiesV1.Click,
                actionId,
                AgentRuntimeAuditEventTypes.ActionDispatchStarted);
            Append(
                fixture.Manager,
                principal,
                sessionId,
                AgentCapabilitiesV1.Click,
                actionId,
                AgentRuntimeAuditEventTypes.ActionTerminal,
                ActionOutcome.InputDispatched,
                terminalAction: true);
            fixture.Manager.CompleteSession(
                sessionId,
                LifecycleGeneration);

            ScopedAuditLedgerSnapshot ledger = Assert.Single(
                fixture.Manager.SnapshotExact(
                    new AgentAuditScopeKey(
                        principal.SecurityPrincipalId,
                        sessionId,
                        AgentCapabilitiesV1.Click)));
            Assert.True(ledger.Segments.Count > 1);
            long[] auditSequences = ledger.Segments
                .SelectMany(segment => segment.Entries)
                .Select(entry =>
                {
                    using JsonDocument payload =
                        JsonDocument.Parse(
                            entry.CanonicalPayload);
                    return payload.RootElement
                        .GetProperty("auditSequence")
                        .GetInt64();
                })
                .ToArray();
            Assert.Equal(
                Enumerable.Range(1, auditSequences.Length)
                    .Select(value => (long)value),
                auditSequences);

            for (int index = 0;
                index < ledger.Segments.Count;
                index++)
            {
                ScopedAuditSegmentSnapshot segment =
                    ledger.Segments[index];
                Assert.InRange(
                    segment.Entries.Count,
                    1,
                    3);
                Assert.NotNull(segment.Receipt);
                Assert.Equal(
                    AuditSegmentTerminalKind.Completed,
                    segment.Receipt.TerminalKind);
                AuditVerificationResult result =
                    AppendOnlyAuditSegment.Verify(
                        segment.Entries,
                        segment.Entries[0].SegmentId,
                        segment.Receipt);
                Assert.True(result.Valid, result.ReasonCode);
                Assert.Equal(
                    segment.Receipt.FinalHash,
                    result.FinalHash);

                if (index == 0)
                {
                    Assert.Null(
                        segment.PreviousSegmentFinalHash);
                }
                else
                {
                    Assert.Equal(
                        ledger.Segments[index - 1]
                            .Receipt.FinalHash,
                        segment.PreviousSegmentFinalHash);
                }
            }
        }

        [Fact]
        public void ExplicitDeleteReturnsContentFreeReceiptForExactScope()
        {
            using var fixture = new LedgerFixture();
            PrincipalCredential principal = fixture.Issue(
                "client-delete",
                AgentCapabilitiesV1.Click,
                AgentCapabilitiesV1.TypeText);
            const string sessionId = "session-delete";
            const string deletedActionId = "action-delete-private";
            const string retainedActionId = "action-retain-private";
            var deletedKey = new AgentAuditScopeKey(
                principal.SecurityPrincipalId,
                sessionId,
                AgentCapabilitiesV1.Click);
            var retainedKey = new AgentAuditScopeKey(
                principal.SecurityPrincipalId,
                sessionId,
                AgentCapabilitiesV1.TypeText);
            AppendCompletedAction(
                fixture.Manager,
                principal,
                sessionId,
                AgentCapabilitiesV1.Click,
                deletedActionId);
            AppendCompletedAction(
                fixture.Manager,
                principal,
                sessionId,
                AgentCapabilitiesV1.TypeText,
                retainedActionId);

            bool deleted = fixture.Manager.TryDelete(
                deletedKey,
                "caller-note:"
                    + principal.SecurityPrincipalId
                    + ":"
                    + sessionId
                    + ":"
                    + deletedActionId,
                out AgentAuditDeletionReceipt receipt);

            Assert.True(deleted);
            Assert.NotNull(receipt);
            Assert.True(receipt.RuntimeManagedScopeOnly);
            Assert.Equal(
                "retention_deleted",
                receipt.ReasonCode);
            Assert.True(receipt.DeletedSegmentCount > 0);
            Assert.True(receipt.DeletedCommittedEventCount > 0);
            Assert.Empty(
                fixture.Manager.SnapshotExact(deletedKey));
            Assert.Single(
                fixture.Manager.SnapshotExact(retainedKey));
            Assert.Same(
                receipt,
                Assert.Single(
                    fixture.Manager.DeletionReceipts()));

            string json = JsonSerializer.Serialize(
                receipt,
                AgentProtocolV1.JsonOptions);
            using JsonDocument document =
                JsonDocument.Parse(json);
            string[] propertyNames = document.RootElement
                .EnumerateObject()
                .Select(property => property.Name)
                .OrderBy(name => name, StringComparer.Ordinal)
                .ToArray();
            Assert.Equal(
                new[]
                {
                    "deletedCommittedEventCount",
                    "deletedSegmentCount",
                    "deletedUtc",
                    "deletionReceiptId",
                    "reasonCode",
                    "runtimeManagedScopeOnly"
                },
                propertyNames);
            Assert.DoesNotContain(
                principal.SecurityPrincipalId,
                json);
            Assert.DoesNotContain(sessionId, json);
            Assert.DoesNotContain(deletedActionId, json);
            Assert.DoesNotContain(retainedActionId, json);
        }

        [Fact]
        public void TruncateAllSealsOpenScopeAndRejectsLateActionEvents()
        {
            using var fixture = new LedgerFixture();
            PrincipalCredential principal = fixture.Issue(
                "client-crash",
                AgentCapabilitiesV1.Click);
            const string sessionId = "session-crash";
            const string actionId = "action-crash";
            Append(
                fixture.Manager,
                principal,
                sessionId,
                AgentCapabilitiesV1.Click,
                actionId,
                AgentRuntimeAuditEventTypes.ActionValidation);

            fixture.Manager.TruncateAll(
                "launcher_crash_recovery");

            ScopedAuditLedgerSnapshot ledger = Assert.Single(
                fixture.Manager.SnapshotExact(
                    new AgentAuditScopeKey(
                        principal.SecurityPrincipalId,
                        sessionId,
                        AgentCapabilitiesV1.Click)));
            Assert.False(ledger.Active);
            ScopedAuditSegmentSnapshot segment =
                Assert.Single(ledger.Segments);
            Assert.Equal(
                AuditSegmentTerminalKind.Truncated,
                segment.Receipt.TerminalKind);
            Assert.Equal(
                AuditSegmentTerminalKind.Truncated,
                segment.Entries[^1].TerminalKind);
            Assert.True(
                AppendOnlyAuditSegment.Verify(
                    segment.Entries,
                    segment.Entries[0].SegmentId,
                    segment.Receipt).Valid);

            bool appended = fixture.Manager.TryAppend(
                CreateEvent(
                    principal,
                    sessionId,
                    AgentCapabilitiesV1.Click,
                    actionId,
                    AgentRuntimeAuditEventTypes
                        .ActionDispatchStarted),
                out AgentRuntimeAuditCommit commit,
                out string reasonCode);
            Assert.False(appended);
            Assert.Null(commit);
            Assert.Equal("audit_scope_inactive", reasonCode);
        }

        [Fact]
        public void RevokedCredentialFailsClosedButCanRecordUnknownTerminal()
        {
            using var fixture = new LedgerFixture();
            PrincipalCredential principal = fixture.Issue(
                "client-revoke",
                AgentCapabilitiesV1.Click);
            const string sessionId = "session-revoke";
            const string actionId = "action-revoke";
            Append(
                fixture.Manager,
                principal,
                sessionId,
                AgentCapabilitiesV1.Click,
                actionId,
                AgentRuntimeAuditEventTypes.ActionValidation);
            Assert.True(
                fixture.Credentials.Revoke(
                    principal.CredentialId,
                    "test_revocation"));
            fixture.Manager.RevokeCredential(
                principal.CredentialId,
                "credential_revoked");

            Assert.False(
                fixture.Manager.TryAppend(
                    CreateEvent(
                        principal,
                        sessionId,
                        AgentCapabilitiesV1.Click,
                        actionId,
                        AgentRuntimeAuditEventTypes
                            .ActionDispatchStarted),
                    out _,
                    out string dispatchReason));
            Assert.Equal(
                "audit_scope_inactive",
                dispatchReason);

            AgentRuntimeAuditCommit terminal = Append(
                fixture.Manager,
                principal,
                sessionId,
                AgentCapabilitiesV1.Click,
                actionId,
                AgentRuntimeAuditEventTypes.ActionTerminal,
                ActionOutcome.Unknown,
                terminalAction: true);
            Assert.Equal(
                AgentRuntimeAuditEventTypes.ActionTerminal,
                terminal.EventType);

            var key = new AgentAuditScopeKey(
                principal.SecurityPrincipalId,
                sessionId,
                AgentCapabilitiesV1.Click);
            ScopedAuditLedgerSnapshot ledger =
                Assert.Single(
                    fixture.Manager.SnapshotExact(key));
            Assert.False(ledger.Active);
            Assert.Equal(
                AuditSegmentTerminalKind.Truncated,
                ledger.Segments[^1].Receipt.TerminalKind);

            Assert.False(
                fixture.Manager.TryAppend(
                    CreateEvent(
                        principal,
                        sessionId,
                        AgentCapabilitiesV1.Click,
                        "action-after-revoke",
                        AgentRuntimeAuditEventTypes
                            .ActionValidation),
                    out _,
                    out _));
        }

        [Fact]
        public void InvalidatedSessionFailsClosedAndTruncatesOnUnknownTerminal()
        {
            using var fixture = new LedgerFixture();
            PrincipalCredential principal = fixture.Issue(
                "client-session-invalidate",
                AgentCapabilitiesV1.Click);
            const string sessionId = "session-invalidated";
            const string actionId = "action-session-invalidated";
            Append(
                fixture.Manager,
                principal,
                sessionId,
                AgentCapabilitiesV1.Click,
                actionId,
                AgentRuntimeAuditEventTypes.ActionValidation);
            fixture.Authority.DenySession(sessionId);
            fixture.Manager.InvalidateSession(
                sessionId,
                LifecycleGeneration,
                "session_invalidated");

            Assert.False(
                fixture.Manager.TryAppend(
                    CreateEvent(
                        principal,
                        sessionId,
                        AgentCapabilitiesV1.Click,
                        actionId,
                        AgentRuntimeAuditEventTypes
                            .ActionDispatchStarted),
                    out _,
                    out string dispatchReason));
            Assert.Equal(
                "audit_scope_inactive",
                dispatchReason);

            Append(
                fixture.Manager,
                principal,
                sessionId,
                AgentCapabilitiesV1.Click,
                actionId,
                AgentRuntimeAuditEventTypes.ActionTerminal,
                ActionOutcome.Unknown,
                terminalAction: true);
            ScopedAuditLedgerSnapshot ledger = Assert.Single(
                fixture.Manager.SnapshotExact(
                    new AgentAuditScopeKey(
                        principal.SecurityPrincipalId,
                        sessionId,
                        AgentCapabilitiesV1.Click)));
            Assert.False(ledger.Active);
            Assert.Equal(
                AuditSegmentTerminalKind.Truncated,
                ledger.Segments[^1].Receipt.TerminalKind);

            Assert.False(
                fixture.Manager.TryAppend(
                    CreateEvent(
                        principal,
                        sessionId,
                        AgentCapabilitiesV1.Click,
                        "action-new-session-invalidated",
                        AgentRuntimeAuditEventTypes
                            .ActionValidation),
                    out _,
                    out _));
        }

        [Fact]
        public void TrustedPreludeBindingsAndRevocationFormExportableExactChain()
        {
            using var fixture = new LedgerFixture();
            PrincipalCredential principal = fixture.Issue(
                "client-exportable",
                AgentCapabilitiesV1.Click,
                AgentCapabilitiesV1
                    .ObservationGrantManage);
            const string connectionId =
                "connection-exportable";
            const string sessionId =
                "session-exportable";
            const string actionId =
                "action-exportable";
            Assert.True(
                fixture.Manager
                    .TryRegisterAuthenticatedConnection(
                        connectionId,
                        principal,
                        sessionId,
                        LifecycleGeneration,
                        out string registerReason),
                registerReason);
            Assert.True(
                fixture.Manager.TryAppendTrustedFact(
                    new AgentRuntimeTrustedAuditFact
                    {
                        Principal = principal,
                        ConnectionId = connectionId,
                        SessionId = sessionId,
                        LifecycleGeneration =
                            LifecycleGeneration,
                        ConsentPurpose =
                            AgentCapabilitiesV1
                                .ObservationGrantManage,
                        EventType =
                            AgentRuntimeAuditEventTypes
                                .ObservationGrantIssued,
                        ObservationGrantId =
                            "grant-" + actionId,
                        TargetScope =
                            new[] { "target-test" },
                        DataScope =
                            new[]
                            {
                                ObservationDataScopesV1
                                    .Pixels
                            },
                        State = "Active",
                        ConsentReceipt =
                            "trusted-consent"
                    },
                    out _,
                    out string grantReason),
                grantReason);
            var lease = new WriteLease(
                "lease-" + actionId,
                principal,
                new WriteLeaseRequest
                {
                    CredentialId =
                        principal.CredentialId,
                    ClientInstanceId =
                        principal.ClientInstanceId,
                    SessionId = sessionId,
                    LifecycleGeneration =
                        LifecycleGeneration,
                    Kind = WriteLeaseKind.GuiInput,
                    Capabilities =
                        new[]
                        {
                            AgentCapabilitiesV1.Click
                        },
                    TargetScope =
                        new[] { "target-test" },
                    RequestedLifetime =
                        TimeSpan.FromMinutes(1),
                    RequestedActionLimit = 1,
                    ConsentReceipt =
                        "trusted-consent"
                },
                fixture.Clock.MonotonicMilliseconds,
                fixture.Clock.MonotonicMilliseconds
                    + 60_000,
                1);
            Append(
                fixture.Manager,
                principal,
                sessionId,
                AgentCapabilitiesV1.Click,
                actionId,
                AgentRuntimeAuditEventTypes
                    .ActionValidation,
                connectionId: connectionId);
            Append(
                fixture.Manager,
                principal,
                sessionId,
                AgentCapabilitiesV1.Click,
                actionId,
                AgentRuntimeAuditEventTypes
                    .ActionBindingValidated,
                connectionId: connectionId,
                lease: lease);
            Append(
                fixture.Manager,
                principal,
                sessionId,
                AgentCapabilitiesV1.Click,
                actionId,
                AgentRuntimeAuditEventTypes
                    .ActionTerminal,
                ActionOutcome.InputDispatched,
                terminalAction: true,
                connectionId: connectionId,
                lease: lease);

            Assert.True(
                fixture.Manager.TrySnapshotExport(
                    principal,
                    sessionId,
                    LifecycleGeneration,
                    AgentCapabilitiesV1.Click,
                    0,
                    100,
                    out ScopedAuditExportSnapshot export,
                    out string exportReason),
                exportReason);
            string[] eventTypes = export.Records
                .Select(record =>
                    record.Entry.EventType)
                .ToArray();
            Assert.Contains(
                AgentRuntimeAuditEventTypes
                    .ConnectionOpened,
                eventTypes);
            Assert.Contains(
                AgentRuntimeAuditEventTypes
                    .AuthenticationSucceeded,
                eventTypes);
            Assert.Contains(
                AgentRuntimeAuditEventTypes
                    .ObservationGrantBound,
                eventTypes);
            Assert.Contains(
                AgentRuntimeAuditEventTypes
                    .WriteLeaseBound,
                eventTypes);
            Assert.Contains(
                AgentRuntimeAuditEventTypes
                    .ActionTerminal,
                eventTypes);

            fixture.Manager.RecordConnectionTermination(
                connectionId,
                "credential_revoked");
            ScopedAuditLedgerSnapshot sealedScope =
                Assert.Single(
                    fixture.Manager.SnapshotExact(
                        new AgentAuditScopeKey(
                            principal
                                .SecurityPrincipalId,
                            sessionId,
                            AgentCapabilitiesV1.Click)));
            Assert.False(sealedScope.Active);
            Assert.Contains(
                sealedScope.Segments
                    .SelectMany(segment =>
                        segment.Entries),
                entry => entry.EventType
                    == AgentRuntimeAuditEventTypes
                        .ConnectionTerminated);
            Assert.Contains(
                sealedScope.Segments
                    .SelectMany(segment =>
                        segment.Entries),
                entry => entry.EventType
                    == AgentRuntimeAuditEventTypes
                        .CredentialRevoked);
            Assert.Contains(
                sealedScope.Segments
                    .SelectMany(segment =>
                        segment.Entries),
                entry => entry.EventType
                    == AgentRuntimeAuditEventTypes
                        .ObservationGrantRevoked);
            Assert.Contains(
                sealedScope.Segments
                    .SelectMany(segment =>
                        segment.Entries),
                entry => entry.EventType
                    == AgentRuntimeAuditEventTypes
                        .WriteLeaseRevoked);
            Assert.Equal(
                AuditSegmentTerminalKind.Truncated,
                sealedScope.Segments[^1]
                    .Receipt.TerminalKind);
        }

        [Fact]
        public void ClaimedResponseWriteSurvivesInvalidationAndCompletesOnce()
        {
            using var fixture = new LedgerFixture();
            PrincipalCredential principal = fixture.Issue(
                "client-response-claimed",
                AgentCapabilitiesV1.SessionShutdown);
            const string connectionId =
                "connection-response-claimed";
            const string sessionId =
                "session-response-claimed";
            const string actionId =
                "action-response-claimed";
            Assert.True(
                fixture.Manager.TryRegisterAuthenticatedConnection(
                    connectionId,
                    principal,
                    sessionId,
                    LifecycleGeneration,
                    out string registerReason),
                registerReason);
            Append(
                fixture.Manager,
                principal,
                sessionId,
                AgentCapabilitiesV1.SessionShutdown,
                actionId,
                AgentRuntimeAuditEventTypes.ActionValidation,
                connectionId: connectionId);
            AgentRuntimeAuditCommit terminal = Append(
                fixture.Manager,
                principal,
                sessionId,
                AgentCapabilitiesV1.SessionShutdown,
                actionId,
                AgentRuntimeAuditEventTypes.ActionTerminal,
                ActionOutcome.InputDispatched,
                terminalAction: true,
                connectionId: connectionId,
                responseDeliveryPending: true);
            AgentRuntimeActionResponseAuditFact fact =
                ResponseFact(
                    principal,
                    connectionId,
                    sessionId,
                    actionId,
                    terminal,
                    AgentRuntimeActionResponseDisposition.Written);

            Assert.True(
                fixture.Manager.TryClaimActionResponseWrite(
                    fact,
                    out string claimReason),
                claimReason);
            fixture.Manager.InvalidateSession(
                sessionId,
                LifecycleGeneration,
                "human_intervention_required");
            Assert.True(
                fixture.Manager.TryCompleteActionResponse(
                    fact,
                    out _,
                    out string completeReason),
                completeReason);
            Assert.False(
                fixture.Manager.TryCompleteActionResponse(
                    fact,
                    out _,
                    out _));

            AuditEntry[] entries = fixture.Manager
                .SnapshotExact(
                    new AgentAuditScopeKey(
                        principal.SecurityPrincipalId,
                        sessionId,
                        AgentCapabilitiesV1.SessionShutdown))
                .SelectMany(snapshot => snapshot.Segments)
                .SelectMany(segment => segment.Entries)
                .ToArray();
            Assert.Single(
                entries,
                entry => entry.EventType
                    == AgentRuntimeAuditEventTypes
                        .ActionResponseWritten);
            Assert.DoesNotContain(
                entries,
                entry => entry.EventType
                    == AgentRuntimeAuditEventTypes
                        .ActionResponseUnknown);
        }

        [Fact]
        public void UnclaimedResponseInvalidationResolvesUnknownOnce()
        {
            using var fixture = new LedgerFixture();
            PrincipalCredential principal = fixture.Issue(
                "client-response-unclaimed",
                AgentCapabilitiesV1.SessionShutdown);
            const string connectionId =
                "connection-response-unclaimed";
            const string sessionId =
                "session-response-unclaimed";
            const string actionId =
                "action-response-unclaimed";
            Assert.True(
                fixture.Manager.TryRegisterAuthenticatedConnection(
                    connectionId,
                    principal,
                    sessionId,
                    LifecycleGeneration,
                    out string registerReason),
                registerReason);
            Append(
                fixture.Manager,
                principal,
                sessionId,
                AgentCapabilitiesV1.SessionShutdown,
                actionId,
                AgentRuntimeAuditEventTypes.ActionValidation,
                connectionId: connectionId);
            AgentRuntimeAuditCommit terminal = Append(
                fixture.Manager,
                principal,
                sessionId,
                AgentCapabilitiesV1.SessionShutdown,
                actionId,
                AgentRuntimeAuditEventTypes.ActionTerminal,
                ActionOutcome.InputDispatched,
                terminalAction: true,
                connectionId: connectionId,
                responseDeliveryPending: true);
            AgentRuntimeActionResponseAuditFact fact =
                ResponseFact(
                    principal,
                    connectionId,
                    sessionId,
                    actionId,
                    terminal,
                    AgentRuntimeActionResponseDisposition.Written);

            fixture.Manager.InvalidateSession(
                sessionId,
                LifecycleGeneration,
                "human_intervention_required");
            Assert.False(
                fixture.Manager.TryClaimActionResponseWrite(
                    fact,
                    out _));
            Assert.False(
                fixture.Manager.TryCompleteActionResponse(
                    fact,
                    out _,
                    out _));

            AuditEntry[] entries = fixture.Manager
                .SnapshotExact(
                    new AgentAuditScopeKey(
                        principal.SecurityPrincipalId,
                        sessionId,
                        AgentCapabilitiesV1.SessionShutdown))
                .SelectMany(snapshot => snapshot.Segments)
                .SelectMany(segment => segment.Entries)
                .ToArray();
            Assert.Single(
                entries,
                entry => entry.EventType
                    == AgentRuntimeAuditEventTypes
                        .ActionResponseUnknown);
            Assert.DoesNotContain(
                entries,
                entry => entry.EventType
                    == AgentRuntimeAuditEventTypes
                        .ActionResponseWritten);
        }

        [Theory]
        [InlineData(AgentRuntimeAuditEventTypes.ActionResponseWritten)]
        [InlineData(AgentRuntimeAuditEventTypes.ActionResponseUnknown)]
        public void GenericAppendCannotForgeReservedResponseFacts(
            string eventType)
        {
            using var fixture = new LedgerFixture();
            PrincipalCredential principal = fixture.Issue(
                "client-response-forge",
                AgentCapabilitiesV1.SessionShutdown);
            const string sessionId =
                "session-response-forge";
            const string actionId =
                "action-response-forge";
            Append(
                fixture.Manager,
                principal,
                sessionId,
                AgentCapabilitiesV1.SessionShutdown,
                actionId,
                AgentRuntimeAuditEventTypes.ActionValidation);

            Assert.False(
                fixture.Manager.TryAppend(
                    CreateEvent(
                        principal,
                        sessionId,
                        AgentCapabilitiesV1.SessionShutdown,
                        actionId,
                        eventType),
                    out _,
                    out string reasonCode));
            Assert.Equal("audit_event_reserved", reasonCode);
            Assert.DoesNotContain(
                fixture.Manager
                    .SnapshotExact(
                        new AgentAuditScopeKey(
                            principal.SecurityPrincipalId,
                            sessionId,
                            AgentCapabilitiesV1.SessionShutdown))
                    .SelectMany(snapshot => snapshot.Segments)
                    .SelectMany(segment => segment.Entries),
                entry => entry.EventType == eventType);
        }

        [Theory]
        [InlineData(false)]
        [InlineData(true)]
        public void DisposeTruncatesPendingResponseAndRecordsUnknownOnce(
            bool claimBeforeDispose)
        {
            using var fixture = new LedgerFixture();
            PrincipalCredential principal = fixture.Issue(
                "client-response-dispose",
                AgentCapabilitiesV1.SessionShutdown);
            const string connectionId =
                "connection-response-dispose";
            const string sessionId =
                "session-response-dispose";
            const string actionId =
                "action-response-dispose";
            Assert.True(
                fixture.Manager.TryRegisterAuthenticatedConnection(
                    connectionId,
                    principal,
                    sessionId,
                    LifecycleGeneration,
                    out string registerReason),
                registerReason);
            Append(
                fixture.Manager,
                principal,
                sessionId,
                AgentCapabilitiesV1.SessionShutdown,
                actionId,
                AgentRuntimeAuditEventTypes.ActionValidation,
                connectionId: connectionId);
            AgentRuntimeAuditCommit terminal = Append(
                fixture.Manager,
                principal,
                sessionId,
                AgentCapabilitiesV1.SessionShutdown,
                actionId,
                AgentRuntimeAuditEventTypes.ActionTerminal,
                ActionOutcome.InputDispatched,
                terminalAction: true,
                connectionId: connectionId,
                responseDeliveryPending: true);
            AgentRuntimeActionResponseAuditFact fact =
                ResponseFact(
                    principal,
                    connectionId,
                    sessionId,
                    actionId,
                    terminal,
                    AgentRuntimeActionResponseDisposition.Written);
            if (claimBeforeDispose)
            {
                Assert.True(
                    fixture.Manager.TryClaimActionResponseWrite(
                        fact,
                        out string claimReason),
                    claimReason);
            }

            fixture.Manager.Dispose();

            ScopedAuditLedgerSnapshot snapshot =
                Assert.Single(
                    fixture.Manager.SnapshotExact(
                        new AgentAuditScopeKey(
                            principal.SecurityPrincipalId,
                            sessionId,
                            AgentCapabilitiesV1.SessionShutdown)));
            AuditEntry[] entries = snapshot.Segments
                .SelectMany(segment => segment.Entries)
                .ToArray();
            Assert.Equal(
                AuditSegmentTerminalKind.Truncated,
                snapshot.Segments[^1].Receipt.TerminalKind);
            Assert.Single(
                entries,
                entry => entry.EventType
                    == AgentRuntimeAuditEventTypes
                        .ActionResponseUnknown);
            Assert.DoesNotContain(
                entries,
                entry => entry.EventType
                    == AgentRuntimeAuditEventTypes
                        .ActionResponseWritten);
            Assert.False(
                fixture.Manager.TryCompleteActionResponse(
                    fact,
                    out _,
                    out _));
        }

        private static void AppendCompletedAction(
            ScopedAgentRuntimeAuditLedgerManager manager,
            PrincipalCredential principal,
            string sessionId,
            string consentPurpose,
            string actionId)
        {
            Append(
                manager,
                principal,
                sessionId,
                consentPurpose,
                actionId,
                AgentRuntimeAuditEventTypes.ActionValidation);
            Append(
                manager,
                principal,
                sessionId,
                consentPurpose,
                actionId,
                AgentRuntimeAuditEventTypes.ActionTerminal,
                ActionOutcome.InputDispatched,
                terminalAction: true);
        }

        private static AgentRuntimeAuditCommit Append(
            ScopedAgentRuntimeAuditLedgerManager manager,
            PrincipalCredential principal,
            string sessionId,
            string consentPurpose,
            string actionId,
            string eventType,
            ActionOutcome? outcome = null,
            bool terminalAction = false,
            string connectionId = null,
            WriteLease lease = null,
            bool responseDeliveryPending = false)
        {
            bool appended = manager.TryAppend(
                CreateEvent(
                    principal,
                    sessionId,
                    consentPurpose,
                    actionId,
                    eventType,
                    outcome,
                    terminalAction,
                    connectionId,
                    lease,
                    responseDeliveryPending),
                out AgentRuntimeAuditCommit commit,
                out string reasonCode);
            Assert.True(appended, reasonCode);
            Assert.NotNull(commit);
            return commit;
        }

        private static AgentRuntimeAuditEventEnvelope CreateEvent(
            PrincipalCredential principal,
            string sessionId,
            string consentPurpose,
            string actionId,
            string eventType,
            ActionOutcome? outcome = null,
            bool terminalAction = false,
            string connectionId = null,
            WriteLease lease = null,
            bool responseDeliveryPending = false)
        {
            ActionEnvelope action = CreateAction(
                actionId,
                sessionId,
                consentPurpose);
            return new AgentRuntimeAuditEventEnvelope
            {
                Principal = principal,
                ConnectionId = connectionId,
                SessionId = sessionId,
                LifecycleGeneration = LifecycleGeneration,
                ConsentPurpose = consentPurpose,
                CorrelationId = "correlation-" + actionId,
                EventType = eventType,
                Action = action,
                ActionPayloadHash =
                    CanonicalJsonV1.ComputeActionPayloadSha256(
                        action),
                Lease = lease,
                Outcome = outcome,
                DispatchMayHaveStarted =
                    eventType
                        == AgentRuntimeAuditEventTypes
                            .ActionDispatchStarted
                    || outcome.HasValue
                        && outcome.Value
                            != ActionOutcome.Rejected,
                TerminalAction = terminalAction,
                ResponseDeliveryPending =
                    responseDeliveryPending
            };
        }

        private static AgentRuntimeActionResponseAuditFact
            ResponseFact(
                PrincipalCredential principal,
                string connectionId,
                string sessionId,
                string actionId,
                AgentRuntimeAuditCommit terminal,
                AgentRuntimeActionResponseDisposition disposition)
        {
            ActionEnvelope action = CreateAction(
                actionId,
                sessionId,
                AgentCapabilitiesV1.SessionShutdown);
            return new AgentRuntimeActionResponseAuditFact
            {
                Principal = principal,
                ConnectionId = connectionId,
                SessionId = sessionId,
                LifecycleGeneration =
                    LifecycleGeneration,
                ConsentPurpose =
                    AgentCapabilitiesV1.SessionShutdown,
                CorrelationId =
                    "correlation-" + actionId,
                ActionId = actionId,
                ActionPayloadHash =
                    CanonicalJsonV1
                        .ComputeActionPayloadSha256(action),
                TerminalAuditSequence =
                    terminal.AuditSequence,
                TerminalEntryHash =
                    terminal.EntryHash,
                Disposition = disposition
            };
        }

        private static ActionEnvelope CreateAction(
            string actionId,
            string sessionId,
            string operation)
        {
            using JsonDocument arguments =
                JsonDocument.Parse("{}");
            return new ActionEnvelope
            {
                ActionId = actionId,
                IdempotencyKey = "idempotency-" + actionId,
                DeadlineMs = 5000,
                SessionId = sessionId,
                ObservationGrantId = "grant-" + actionId,
                LeaseId = "lease-" + actionId,
                ObservationId = "observation-" + actionId,
                ExpectedLifecycleGeneration =
                    LifecycleGeneration,
                TargetId = "target-test",
                ExpectedSurfaceEpoch = 1,
                ExpectedCoordinateSpaceVersion = 1,
                ExpectedFocusEpoch = 1,
                ExpectedModalEpoch = 1,
                Operation = operation,
                Arguments = arguments.RootElement.Clone(),
                Reason = "audit-test"
            };
        }

        private static AgentAuditScopeKey ScopeKey(
            ScopeCase item)
        {
            return new AgentAuditScopeKey(
                item.Principal.SecurityPrincipalId,
                item.SessionId,
                item.ConsentPurpose);
        }

        private sealed record ScopeCase(
            PrincipalCredential Principal,
            string SessionId,
            string ConsentPurpose,
            string ActionId);

        private sealed class LedgerFixture : IDisposable
        {
            public LedgerFixture(
                int maximumEntriesPerSegment =
                    ScopedAgentRuntimeAuditLedgerManager
                        .DefaultMaximumEntriesPerSegment)
            {
                Clock = new ManualAgentRuntimeClock();
                Credentials =
                    new PrincipalCredentialAuthority(
                        Clock,
                        new ObservationEnrollmentVerifier());
                Authority = new MutableScopeAuthority();
                Manager =
                    new ScopedAgentRuntimeAuditLedgerManager(
                        Clock,
                        Credentials,
                        Authority,
                        maximumEntriesPerSegment);
            }

            public ManualAgentRuntimeClock Clock { get; }
            public PrincipalCredentialAuthority Credentials
            {
                get;
            }
            public MutableScopeAuthority Authority { get; }
            public ScopedAgentRuntimeAuditLedgerManager Manager
            {
                get;
            }

            public PrincipalCredential Issue(
                string clientInstanceId,
                params string[] capabilities)
            {
                return Credentials.IssueDeveloper(
                    new DeveloperEnrollmentEvidence
                    {
                        ClientInstanceId = clientInstanceId,
                        EnrollmentReceipt =
                            "audit-test-enrollment",
                        AllowedCapabilities = capabilities,
                        AllowedTargets =
                            new[] { "target-test" }
                    });
            }

            public void Dispose()
            {
                Manager.Dispose();
            }
        }

        private sealed class MutableScopeAuthority
            : IAgentAuditScopeAuthority
        {
            private readonly HashSet<string>
                _deniedSessions =
                    new HashSet<string>(
                        StringComparer.Ordinal);

            public void DenySession(string sessionId)
            {
                _deniedSessions.Add(sessionId);
            }

            public bool TryAuthorize(
                PrincipalCredential principal,
                string sessionId,
                ulong lifecycleGeneration,
                string consentPurpose,
                out string reasonCode)
            {
                if (principal == null
                    || lifecycleGeneration
                        != LifecycleGeneration
                    || _deniedSessions.Contains(
                        sessionId ?? string.Empty)
                    || !principal.AllowsCapability(
                        consentPurpose))
                {
                    reasonCode =
                        "audit_scope_not_authorized";
                    return false;
                }
                reasonCode = null;
                return true;
            }
        }
    }
}
