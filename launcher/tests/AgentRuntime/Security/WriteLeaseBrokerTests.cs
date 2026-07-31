using System;
using System.Linq;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Security;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.Security
{
    public sealed class WriteLeaseBrokerTests
    {
        [Fact]
        public void PlayerGuiLease_EnforcesThirtySecondsEightActionsOneTarget()
        {
            var setup = CreatePlayerSetup();
            WriteLease lease = setup.Broker.Acquire(
                PlayerGuiRequest(
                    setup.Credential,
                    TimeSpan.FromMinutes(5),
                    50,
                    new[] { "flash-a" },
                    setup.Credential.IssuerReceipt));

            Assert.Equal(30000, lease.ExpiresMonotonic);
            Assert.Equal(8, lease.ActionLimit);
            Assert.Single(lease.TargetScope);
            Assert.Equal(
                new string('A', 64),
                lease.ArgumentBoundsHash);

            Assert.Throws<InvalidOperationException>(
                () => setup.Broker.Acquire(
                    PlayerGuiRequest(
                        setup.Credential,
                        TimeSpan.FromSeconds(10),
                        1,
                        new[] { "flash-a", "web-a" },
                        setup.Credential.IssuerReceipt)));
        }

        [Fact]
        public void PlayerLease_RequiresExactArgumentBoundsHash()
        {
            var setup = CreatePlayerSetup();

            InvalidOperationException error =
                Assert.Throws<InvalidOperationException>(
                    () => setup.Broker.Acquire(
                        PlayerGuiRequest(
                            setup.Credential,
                            TimeSpan.FromSeconds(10),
                            1,
                            new[] { "flash-a" },
                            setup.Credential.IssuerReceipt,
                            includeArgumentBoundsHash: false)));

            Assert.Equal(
                "argument_bounds_required",
                error.Message);
        }

        [Fact]
        public void SingleWriterAndHumanOverride_AreFailClosed()
        {
            var setup = CreatePlayerSetup();
            WriteLease lease = setup.Broker.Acquire(
                PlayerGuiRequest(
                    setup.Credential,
                    TimeSpan.FromSeconds(10),
                    2,
                    new[] { "flash-a" },
                    setup.Credential.IssuerReceipt));

            InvalidOperationException conflict =
                Assert.Throws<InvalidOperationException>(
                    () => setup.Broker.Acquire(
                        PlayerGuiRequest(
                            setup.Credential,
                            TimeSpan.FromSeconds(10),
                            2,
                            new[] { "flash-a" },
                            setup.Credential.IssuerReceipt)));
            Assert.Equal("write_lease_already_held", conflict.Message);

            Assert.Equal(
                1,
                setup.Broker.RevokeAllForHumanOverride("human_input"));
            Assert.Equal(WriteLeaseState.Revoked, lease.State);
            Assert.False(setup.Broker.TryConsumeAction(
                lease.LeaseId,
                "wings-client",
                setup.Credential.SecurityPrincipalId,
                out _,
                out string reason));
            Assert.Equal("human_input", reason);
        }

        [Fact]
        public void PlayerConsent_CannotRollPastCumulativeHardCap()
        {
            var setup = CreatePlayerSetup();
            for (int index = 0; index < 4; index++)
            {
                WriteLease lease = setup.Broker.Acquire(
                    PlayerGuiRequest(
                        setup.Credential,
                        TimeSpan.FromSeconds(30),
                        1,
                        new[] { "flash-a" },
                        setup.Credential.IssuerReceipt));
                Assert.True(setup.Broker.Release(
                    lease.LeaseId,
                    "wings-client",
                    setup.Credential.SecurityPrincipalId));
            }

            InvalidOperationException forged =
                Assert.Throws<InvalidOperationException>(
                    () => setup.Broker.Acquire(
                        PlayerGuiRequest(
                            setup.Credential,
                            TimeSpan.FromSeconds(1),
                            1,
                            new[] { "flash-a" },
                            "different-consent-receipt")));
            Assert.Equal(
                "consent_receipt_invalid",
                forged.Message);

            InvalidOperationException error =
                Assert.Throws<InvalidOperationException>(
                    () => setup.Broker.Acquire(
                        PlayerGuiRequest(
                            setup.Credential,
                            TimeSpan.FromSeconds(1),
                            1,
                            new[] { "flash-a" },
                            setup.Credential
                                .IssuerReceipt)));
            Assert.Equal("consent_cumulative_limit", error.Message);
        }

        [Fact]
        public void DomainLease_IsOneShotAndRequiresExactPreviewBinding()
        {
            var setup = CreatePlayerSetup();
            WriteLease lease = setup.Broker.Acquire(
                new WriteLeaseRequest
                {
                    CredentialId = setup.Credential.CredentialId,
                    ClientInstanceId = "wings-client",
                    SessionId = "session-a",
                    LifecycleGeneration = 1,
                    Kind = WriteLeaseKind.DomainTransaction,
                    Capabilities = new[] { "domain.hair.change" },
                    TargetScope = new[] { "hair-domain" },
                    RequestedLifetime = TimeSpan.FromMinutes(10),
                    RequestedActionLimit = 10,
                    ConsentReceipt =
                        setup.Credential.IssuerReceipt,
                    ArgumentBoundsHash =
                        new string('A', 64),
                    PreviewHash = "preview-hash",
                    ExpectedRevision = "save-rev-7",
                    Operation = "appearance.hair.change.v1"
                });

            Assert.Equal(1, lease.ActionLimit);
            Assert.Equal(60000, lease.ExpiresMonotonic);
            Assert.True(setup.Broker.TryConsumeAction(
                lease.LeaseId,
                "wings-client",
                setup.Credential.SecurityPrincipalId,
                out _,
                out _));
            Assert.Equal(WriteLeaseState.Consumed, lease.State);
            Assert.False(setup.Broker.TryConsumeAction(
                lease.LeaseId,
                "wings-client",
                setup.Credential.SecurityPrincipalId,
                out _,
                out string reason));
            Assert.Equal("action_limit_consumed", reason);
        }

        [Fact]
        public void ShutdownLease_IsDedicatedBoundedAndOneShot()
        {
            var player = CreatePlayerSetup();
            InvalidOperationException guiMismatch =
                Assert.Throws<InvalidOperationException>(
                    () => player.Broker.Acquire(
                        new WriteLeaseRequest
                        {
                            CredentialId =
                                player.Credential
                                    .CredentialId,
                            ClientInstanceId =
                                "wings-client",
                            SessionId = "session-a",
                            LifecycleGeneration = 1,
                            Kind =
                                WriteLeaseKind.GuiInput,
                            Capabilities = new[]
                            {
                                AgentCapabilitiesV1
                                    .SessionShutdown
                            },
                            TargetScope =
                                new[] { "flash-a" },
                            RequestedLifetime =
                                TimeSpan.FromSeconds(10),
                            RequestedActionLimit = 1,
                            ConsentReceipt =
                                player.Credential
                                    .IssuerReceipt,
                            ArgumentBoundsHash =
                                new string('A', 64)
                        }));
            Assert.Equal(
                "capability_scope_denied",
                guiMismatch.Message);

            InvalidOperationException playerDenied =
                Assert.Throws<InvalidOperationException>(
                    () => player.Broker.Acquire(
                        ShutdownRequest(
                            player.Credential,
                            "wings-client",
                            "flash-a")));
            Assert.Equal(
                "consent_required",
                playerDenied.Message);

            var clock = new ManualAgentRuntimeClock();
            var authority = new PrincipalCredentialAuthority(
                clock,
                new TestPrincipalEnrollmentVerifier());
            PrincipalCredential credential =
                authority.IssueDeveloper(
                    new DeveloperEnrollmentEvidence
                    {
                        ClientInstanceId = "dev-client",
                        EnrollmentReceipt = "dev-enroll",
                        AllowedCapabilities = new[]
                        {
                            AgentCapabilitiesV1
                                .SessionShutdown,
                            AgentCapabilitiesV1.Click
                        },
                        AllowedTargets = new[]
                        {
                            "launcher-a",
                            "launcher-b",
                            "flash-a"
                        }
                    });
            var targets = new MutableAgentTargetAuthority();
            targets.Set(
                "session-a",
                "launcher-a",
                kind: SurfaceKind.Launcher);
            targets.Set(
                "session-a",
                "launcher-b",
                kind: SurfaceKind.Launcher);
            targets.Set("session-a", "flash-a");
            var broker = new WriteLeaseBroker(
                clock,
                authority,
                targets);

            InvalidOperationException widened =
                Assert.Throws<InvalidOperationException>(
                    () => broker.Acquire(
                        ShutdownRequest(
                            credential,
                            "dev-client",
                            "launcher-a",
                            capabilities: new[]
                            {
                                AgentCapabilitiesV1
                                    .SessionShutdown,
                                AgentCapabilitiesV1.Click
                            })));
            Assert.Equal(
                "capability_scope_denied",
                widened.Message);

            InvalidOperationException widenedTargets =
                Assert.Throws<InvalidOperationException>(
                    () => broker.Acquire(
                        ShutdownRequest(
                            credential,
                            "dev-client",
                            "launcher-a",
                            targets: new[]
                            {
                                "launcher-a",
                                "launcher-b"
                            })));
            Assert.Equal(
                "target_scope_denied",
                widenedTargets.Message);

            InvalidOperationException widenedActions =
                Assert.Throws<InvalidOperationException>(
                    () => broker.Acquire(
                        ShutdownRequest(
                            credential,
                            "dev-client",
                            "launcher-a",
                            actionLimit: 2)));
            Assert.Equal(
                "lease_action_limit",
                widenedActions.Message);

            InvalidOperationException flashTarget =
                Assert.Throws<InvalidOperationException>(
                    () => broker.Acquire(
                        ShutdownRequest(
                            credential,
                            "dev-client",
                            "flash-a")));
            Assert.Equal(
                "unsupported_for_surface",
                flashTarget.Message);

            WriteLease lease = broker.Acquire(
                ShutdownRequest(
                    credential,
                    "dev-client",
                    "launcher-a"));

            Assert.Equal(
                WriteLeaseKind.Shutdown,
                lease.Kind);
            Assert.Equal(
                AgentCapabilitiesV1.SessionShutdown,
                lease.Operation);
            Assert.Equal(30_000, lease.ExpiresMonotonic);
            Assert.Equal(1, lease.ActionLimit);
            Assert.Single(lease.TargetScope);
            Assert.False(
                broker.TryRenewDeveloper(
                    lease.LeaseId,
                    "dev-client",
                    credential.SecurityPrincipalId,
                    TimeSpan.FromSeconds(10),
                    out _,
                    out string renewReason));
            Assert.Equal(
                "operation_invalid",
                renewReason);
            Assert.False(
                broker.TryConsumeAction(
                    lease.LeaseId,
                    "dev-client",
                    credential
                        .SecurityPrincipalId,
                    out _,
                    out string unboundReason));
            Assert.Equal(
                "operation_invalid",
                unboundReason);
            Assert.False(
                broker.TryConsumeAction(
                    lease.LeaseId,
                    "dev-client",
                    credential
                        .SecurityPrincipalId,
                    "session-a",
                    AgentCapabilitiesV1
                        .SessionShutdown,
                    "launcher-a",
                    AgentCapabilitiesV1.Click,
                    out _,
                    out string wrongOperation));
            Assert.Equal(
                "operation_invalid",
                wrongOperation);
            Assert.True(
                broker.TryConsumeAction(
                    lease.LeaseId,
                    "dev-client",
                    credential
                        .SecurityPrincipalId,
                    "session-a",
                    AgentCapabilitiesV1
                        .SessionShutdown,
                    "launcher-a",
                    AgentCapabilitiesV1
                        .SessionShutdown,
                    out _,
                    out _));
            Assert.Equal(
                WriteLeaseState.Consumed,
                lease.State);
            Assert.True(
                broker.CompleteActionExecution(
                    lease.LeaseId,
                    retainShutdownDelivery: true));
            Assert.True(
                broker.AbortPendingShutdownDelivery(
                    lease.LeaseId));
        }

        [Fact]
        public void
            StructuredActionLease_IsExactLauncherOneShotNonrenewableAndModeBound()
        {
            var player = CreatePlayerSetup();
            InvalidOperationException playerDenied =
                Assert.Throws<InvalidOperationException>(
                    () => player.Broker.Acquire(
                        StructuredActionRequest(
                            player.Credential,
                            "wings-client",
                            "flash-a")));
            Assert.Equal(
                "consent_required",
                playerDenied.Message);

            var setup = CreateDeveloperShutdownSetup();
            setup.Targets.Set(
                "session-a",
                "launcher-b",
                kind: SurfaceKind.Launcher);

            WriteLeaseRequest exact = StructuredActionRequest(
                setup.Credential,
                "dev-client",
                "launcher-a");
            InvalidOperationException guiMismatch =
                Assert.Throws<InvalidOperationException>(
                    () => setup.Broker.Acquire(
                        StructuredActionRequest(
                            setup.Credential,
                            "dev-client",
                            "launcher-a",
                            kind: WriteLeaseKind.GuiInput)));
            Assert.Equal(
                "capability_scope_denied",
                guiMismatch.Message);

            InvalidOperationException widenedCapabilities =
                Assert.Throws<InvalidOperationException>(
                    () => setup.Broker.Acquire(
                        StructuredActionRequest(
                            setup.Credential,
                            "dev-client",
                            "launcher-a",
                            capabilities: new[]
                            {
                                AgentCapabilitiesV1.PanelOpen,
                                AgentCapabilitiesV1.Click
                            })));
            Assert.Equal(
                "capability_scope_denied",
                widenedCapabilities.Message);

            InvalidOperationException widenedTargets =
                Assert.Throws<InvalidOperationException>(
                    () => setup.Broker.Acquire(
                        StructuredActionRequest(
                            setup.Credential,
                            "dev-client",
                            "launcher-a",
                            targets: new[]
                            {
                                "launcher-a",
                                "launcher-b"
                            })));
            Assert.Equal(
                "target_scope_denied",
                widenedTargets.Message);

            InvalidOperationException widenedActions =
                Assert.Throws<InvalidOperationException>(
                    () => setup.Broker.Acquire(
                        StructuredActionRequest(
                            setup.Credential,
                            "dev-client",
                            "launcher-a",
                            actionLimit: 2)));
            Assert.Equal(
                "lease_action_limit",
                widenedActions.Message);

            InvalidOperationException flashTarget =
                Assert.Throws<InvalidOperationException>(
                    () => setup.Broker.Acquire(
                        StructuredActionRequest(
                            setup.Credential,
                            "dev-client",
                            "flash-a")));
            Assert.Equal(
                "unsupported_for_surface",
                flashTarget.Message);

            WriteLease lease = setup.Broker.Acquire(exact);
            Assert.Equal(
                WriteLeaseKind.StructuredAction,
                lease.Kind);
            Assert.Equal(
                AgentCapabilitiesV1.PanelOpen,
                lease.Operation);
            Assert.Equal(30_000, lease.ExpiresMonotonic);
            Assert.Equal(1, lease.ActionLimit);
            Assert.Single(lease.Capabilities);
            Assert.Single(lease.TargetScope);

            InvalidOperationException writerConflict =
                Assert.Throws<InvalidOperationException>(
                    () => setup.Broker.Acquire(
                        DeveloperGuiRequest(
                            setup.Credential,
                            "session-a")));
            Assert.Equal(
                "write_lease_already_held",
                writerConflict.Message);

            Assert.False(
                setup.Broker.TryRenewDeveloper(
                    lease.LeaseId,
                    "dev-client",
                    setup.Credential.SecurityPrincipalId,
                    TimeSpan.FromSeconds(10),
                    out _,
                    out string renewReason));
            Assert.Equal(
                "operation_invalid",
                renewReason);
            Assert.False(
                setup.Broker.TryConsumeAction(
                    lease.LeaseId,
                    "dev-client",
                    setup.Credential.SecurityPrincipalId,
                    out _,
                    out string unboundReason));
            Assert.Equal(
                "operation_invalid",
                unboundReason);
            Assert.False(
                setup.Broker.TryConsumeAction(
                    lease.LeaseId,
                    "dev-client",
                    setup.Credential.SecurityPrincipalId,
                    "session-a",
                    AgentCapabilitiesV1.PanelOpen,
                    "launcher-a",
                    AgentCapabilitiesV1.Click,
                    out _,
                    out string wrongOperation));
            Assert.Equal(
                "operation_invalid",
                wrongOperation);
            Assert.True(
                setup.Broker.TryConsumeAction(
                    lease.LeaseId,
                    "dev-client",
                    setup.Credential.SecurityPrincipalId,
                    "session-a",
                    AgentCapabilitiesV1.PanelOpen,
                    "launcher-a",
                    AgentCapabilitiesV1.PanelOpen,
                    out _,
                    out string consumeReason),
                consumeReason);
            Assert.Equal(WriteLeaseState.Consumed, lease.State);
            Assert.True(lease.ActionExecutionPending);

            Assert.Equal(
                1,
                setup.Broker.RevokeAllForHumanOverride(
                    "human_input"));
            Assert.Equal(WriteLeaseState.Revoked, lease.State);
            Assert.True(lease.ActionExecutionPending);
            Assert.True(
                setup.Broker.AbortPendingActionExecution(
                    lease.LeaseId));
        }

        [Fact]
        public void StructuredActionLease_AllowsExactUnattendedBinding()
        {
            var clock = new ManualAgentRuntimeClock();
            var authority = new PrincipalCredentialAuthority(
                clock,
                new TestPrincipalEnrollmentVerifier());
            PrincipalCredential credential =
                authority.IssueUnattended(
                    new UnattendedCredentialEvidence
                    {
                        ClientInstanceId = "runner-client",
                        RunnerPolicyId = "trusted-runner",
                        RunnerProcessId = 1234,
                        RunnerProcessStartTimeUtc =
                            DateTimeOffset.UtcNow,
                        RunnerExecutablePath = "runner.exe",
                        RunnerExecutableSha256 =
                            new string('A', 64),
                        RunnerExecutableSize = 1024,
                        RuntimeExecutablePath =
                            "Launcher.Core.exe",
                        RequestNonce = "request-nonce",
                        BuildIdentity = new string('B', 64),
                        PayloadClosure = new string('C', 64),
                        SessionId = "session-a",
                        AttemptId = "attempt-a",
                        AttemptGeneration = 1,
                        Slot = "cf7_agent_test",
                        CanonicalSavePath = "save-slot",
                        RunnerDeadlineMonotonic = 60_000,
                        AllowedCapabilities = new[]
                        {
                            AgentCapabilitiesV1.PanelOpen
                        },
                        AllowedTargets =
                            new[] { "launcher-a" }
                    });
            var targets = new MutableAgentTargetAuthority();
            targets.Set(
                "session-a",
                "launcher-a",
                kind: SurfaceKind.Launcher);
            targets.SetSessionMode(
                "session-a",
                SessionMode.UnattendedTest);
            var broker = new WriteLeaseBroker(
                clock,
                authority,
                targets);

            WriteLease lease = broker.Acquire(
                StructuredActionRequest(
                    credential,
                    "runner-client",
                    "launcher-a"));

            Assert.Equal(
                WriteLeaseKind.StructuredAction,
                lease.Kind);
            Assert.Equal(30_000, lease.ExpiresMonotonic);
            Assert.Equal(1, lease.ActionLimit);
        }

        [Fact]
        public void
            ShutdownDeliveryClaim_HumanOverrideCannotRollBackWriteOwnership()
        {
            var setup = CreateDeveloperShutdownSetup();
            WriteLease lease = setup.Broker.Acquire(
                ShutdownRequest(
                    setup.Credential,
                    "dev-client",
                    "launcher-a"));

            Assert.True(
                setup.Broker.TryConsumeAction(
                    lease.LeaseId,
                    "dev-client",
                    setup.Credential
                        .SecurityPrincipalId,
                    "session-a",
                    AgentCapabilitiesV1
                        .SessionShutdown,
                    "launcher-a",
                    AgentCapabilitiesV1
                        .SessionShutdown,
                    out _,
                    out _));
            Assert.True(lease.ActionExecutionPending);
            Assert.True(
                setup.Broker.MarkShutdownDeliveryPending(
                    lease.LeaseId));
            Assert.True(lease.ShutdownDeliveryPending);
            Assert.True(
                setup.Broker.TryClaimShutdownDeliveryWrite(
                    lease.LeaseId));
            Assert.False(lease.ShutdownDeliveryPending);
            Assert.True(lease.ShutdownDeliveryWriteOwned);

            Assert.Equal(
                0,
                setup.Broker.RevokeAllForHumanOverride(
                    "human_input"));
            Assert.Equal(WriteLeaseState.Consumed, lease.State);
            Assert.True(lease.ActionExecutionPending);
            Assert.True(lease.ShutdownDeliveryWriteOwned);
            Assert.False(lease.ShutdownDeliveryCommitted);

            Assert.True(
                setup.Broker.CompleteShutdownDelivery(
                    lease.LeaseId));
            Assert.False(lease.ActionExecutionPending);
            Assert.False(lease.ShutdownDeliveryWriteOwned);
            Assert.True(lease.ShutdownDeliveryCommitted);
        }

        [Fact]
        public void
            ShutdownDelivery_HumanOverrideBeforeClaimKeepsDrainUntilAbort()
        {
            var setup = CreateDeveloperShutdownSetup();
            WriteLease lease = setup.Broker.Acquire(
                ShutdownRequest(
                    setup.Credential,
                    "dev-client",
                    "launcher-a"));

            Assert.True(
                setup.Broker.TryConsumeAction(
                    lease.LeaseId,
                    "dev-client",
                    setup.Credential
                        .SecurityPrincipalId,
                    "session-a",
                    AgentCapabilitiesV1
                        .SessionShutdown,
                    "launcher-a",
                    AgentCapabilitiesV1
                        .SessionShutdown,
                    out _,
                    out _));
            Assert.True(
                setup.Broker.MarkShutdownDeliveryPending(
                    lease.LeaseId));

            Assert.Equal(
                1,
                setup.Broker.RevokeAllForHumanOverride(
                    "human_input"));
            Assert.Equal(WriteLeaseState.Revoked, lease.State);
            Assert.True(lease.ActionExecutionPending);
            Assert.False(lease.ShutdownDeliveryPending);
            Assert.False(
                setup.Broker.TryClaimShutdownDeliveryWrite(
                    lease.LeaseId));

            InvalidOperationException blocked =
                Assert.Throws<InvalidOperationException>(
                    () => setup.Broker.Acquire(
                        ShutdownRequest(
                            setup.Credential,
                            "dev-client",
                            "launcher-a")));
            Assert.Equal(
                "write_lease_already_held",
                blocked.Message);

            Assert.True(
                setup.Broker.AbortPendingActionExecution(
                    lease.LeaseId));
            Assert.False(lease.ActionExecutionPending);
            Assert.Equal(
                WriteLeaseState.Active,
                setup.Broker.Acquire(
                        ShutdownRequest(
                            setup.Credential,
                            "dev-client",
                            "launcher-a"))
                    .State);
        }

        [Fact]
        public void
            OneShotExecutionReservation_BlocksShutdownUntilCompletion()
        {
            var setup = CreateDeveloperShutdownSetup();
            WriteLease lease = setup.Broker.Acquire(
                new WriteLeaseRequest
                {
                    CredentialId =
                        setup.Credential.CredentialId,
                    ClientInstanceId = "dev-client",
                    SessionId = "session-a",
                    LifecycleGeneration = 1,
                    Kind = WriteLeaseKind.GuiInput,
                    Capabilities = new[]
                    {
                        AgentCapabilitiesV1.Click
                    },
                    TargetScope = new[] { "flash-a" },
                    RequestedLifetime =
                        TimeSpan.FromMinutes(1),
                    RequestedActionLimit = 1
                });

            Assert.True(
                setup.Broker.TryConsumeAction(
                    lease.LeaseId,
                    "dev-client",
                    setup.Credential
                        .SecurityPrincipalId,
                    "session-a",
                    AgentCapabilitiesV1.Click,
                    "flash-a",
                    AgentCapabilitiesV1.Click,
                    out _,
                    out _));
            Assert.Equal(WriteLeaseState.Consumed, lease.State);
            Assert.True(lease.ActionExecutionPending);

            InvalidOperationException blocked =
                Assert.Throws<InvalidOperationException>(
                    () => setup.Broker.Acquire(
                        ShutdownRequest(
                            setup.Credential,
                            "dev-client",
                            "launcher-a")));
            Assert.Equal(
                "write_lease_already_held",
                blocked.Message);

            Assert.True(
                setup.Broker.CompleteActionExecution(
                    lease.LeaseId,
                    retainShutdownDelivery: false));
            Assert.False(lease.ActionExecutionPending);
            Assert.Equal(
                WriteLeaseState.Active,
                setup.Broker.Acquire(
                        ShutdownRequest(
                            setup.Credential,
                            "dev-client",
                            "launcher-a"))
                    .State);
        }

        [Fact]
        public void
            TerminalLeaseChurnIsBoundedAndHumanOverrideScansOnlyLive()
        {
            var setup = CreateDeveloperShutdownSetup();
            int capacity =
                WriteLeaseBroker
                    .TerminalLeaseTombstoneCapacityForTests;
            for (int index = 0;
                index < capacity + 32;
                index++)
            {
                WriteLease lease = setup.Broker.Acquire(
                    DeveloperGuiRequest(
                        setup.Credential,
                        "session-a"));
                Assert.True(
                    setup.Broker.Release(
                        lease.LeaseId,
                        "dev-client",
                        setup.Credential
                            .SecurityPrincipalId));
            }

            Assert.Equal(0, setup.Broker.LiveLeaseCountForTests);
            Assert.Equal(
                capacity,
                setup.Broker
                    .TerminalLeaseTombstoneCountForTests);

            WriteLease active = setup.Broker.Acquire(
                DeveloperGuiRequest(
                    setup.Credential,
                    "session-a"));
            Assert.Equal(
                1,
                setup.Broker.RevokeAllForHumanOverride(
                    "human_input"));
            Assert.Equal(
                1,
                setup.Broker
                    .LastHumanOverrideCandidateCountForTests);
            Assert.Equal(WriteLeaseState.Revoked, active.State);
            Assert.Equal(0, setup.Broker.LiveLeaseCountForTests);
            Assert.Equal(
                capacity,
                setup.Broker
                    .TerminalLeaseTombstoneCountForTests);

            Assert.Equal(
                0,
                setup.Broker.RevokeAllForHumanOverride(
                    "human_input"));
            Assert.Equal(
                0,
                setup.Broker
                    .LastHumanOverrideCandidateCountForTests);
        }

        [Fact]
        public void
            CommittedShutdownLatchSurvivesTombstoneEviction()
        {
            var setup = CreateDeveloperShutdownSetup();
            WriteLease committed = CommitShutdown(
                setup.Broker,
                setup.Credential,
                "session-a");
            Assert.True(committed.ShutdownDeliveryCommitted);
            Assert.Equal(0, setup.Broker.LiveLeaseCountForTests);
            Assert.Equal(
                1,
                setup.Broker
                    .CommittedShutdownSessionCountForTests);

            setup.Targets.Set(
                "session-b",
                "flash-a");
            int capacity =
                WriteLeaseBroker
                    .TerminalLeaseTombstoneCapacityForTests;
            for (int index = 0; index < capacity; index++)
            {
                WriteLease churn = setup.Broker.Acquire(
                    DeveloperGuiRequest(
                        setup.Credential,
                        "session-b"));
                Assert.True(
                    setup.Broker.Release(
                        churn.LeaseId,
                        "dev-client",
                        setup.Credential
                            .SecurityPrincipalId));
            }

            Assert.Equal(
                capacity,
                setup.Broker
                    .TerminalLeaseTombstoneCountForTests);
            Assert.False(
                setup.Broker.TryConsumeAction(
                    committed.LeaseId,
                    "dev-client",
                    setup.Credential
                        .SecurityPrincipalId,
                    out _,
                    out string evictedReason));
            Assert.Equal("lease_not_found", evictedReason);

            InvalidOperationException blocked =
                Assert.Throws<InvalidOperationException>(
                    () => setup.Broker.Acquire(
                        DeveloperGuiRequest(
                            setup.Credential,
                            "session-a")));
            Assert.Equal(
                "write_lease_already_held",
                blocked.Message);

            WriteLease otherSession =
                setup.Broker.Acquire(
                    DeveloperGuiRequest(
                        setup.Credential,
                        "session-b"));
            Assert.Equal(
                WriteLeaseState.Active,
                otherSession.State);
        }

        [Fact]
        public void
            CommittedShutdownLatchOverflowFailsClosedWithoutGrowing()
        {
            var setup = CreateDeveloperShutdownSetup();
            int capacity =
                WriteLeaseBroker
                    .CommittedShutdownSessionCapacityForTests;
            for (int index = 0;
                index < capacity + 1;
                index++)
            {
                string sessionId =
                    "shutdown-session-" + index;
                setup.Targets.Set(
                    sessionId,
                    "launcher-a",
                    kind: SurfaceKind.Launcher);
                _ = CommitShutdown(
                    setup.Broker,
                    setup.Credential,
                    sessionId);
            }

            Assert.Equal(
                capacity,
                setup.Broker
                    .CommittedShutdownSessionCountForTests);
            Assert.True(
                setup.Broker
                    .CommittedShutdownLatchOverflowedForTests);
            Assert.Equal(0, setup.Broker.LiveLeaseCountForTests);

            setup.Targets.Set(
                "fresh-session",
                "flash-a");
            InvalidOperationException blocked =
                Assert.Throws<InvalidOperationException>(
                    () => setup.Broker.Acquire(
                        DeveloperGuiRequest(
                            setup.Credential,
                            "fresh-session")));
            Assert.Equal(
                "write_lease_already_held",
                blocked.Message);
        }

        [Fact]
        public void
            PlayerLeaseRejectsCrossPrincipalSessionAndExpiredCredential()
        {
            var setup = CreatePlayerSetup();
            PrincipalCredential other =
                setup.Authority.IssuePlayerAssist(
                    new PlayerAssistCredentialEvidence
                    {
                        ClientInstanceId =
                            "other-wings-client",
                        ConsentReceipt =
                            "other-player-enroll",
                        SelectedSessionId =
                            "session-a",
                        AllowedCapabilities =
                            new[] { "input.click" },
                        AllowedTargets =
                            new[] { "flash-a" }
                    });
            InvalidOperationException principalError =
                Assert.Throws<InvalidOperationException>(
                    () => setup.Broker.Acquire(
                        PlayerGuiRequest(
                            other,
                            TimeSpan.FromSeconds(1),
                            1,
                            new[] { "flash-a" },
                            other.IssuerReceipt)));
            Assert.Equal(
                "credential_owner_mismatch",
                principalError.Message);

            setup.Targets.Set(
                "session-b",
                "flash-b");
            InvalidOperationException sessionError =
                Assert.Throws<InvalidOperationException>(
                    () => setup.Broker.Acquire(
                        new WriteLeaseRequest
                        {
                            CredentialId =
                                setup.Credential
                                    .CredentialId,
                            ClientInstanceId =
                                "wings-client",
                            SessionId = "session-b",
                            LifecycleGeneration = 1,
                            Kind =
                                WriteLeaseKind.GuiInput,
                            Capabilities =
                                new[] { "input.click" },
                            TargetScope =
                                new[] { "flash-b" },
                            RequestedLifetime =
                                TimeSpan.FromSeconds(1),
                            RequestedActionLimit = 1,
                            ConsentReceipt =
                                setup.Credential
                                    .IssuerReceipt,
                            ArgumentBoundsHash =
                                new string('A', 64)
                        }));
            Assert.Equal(
                "session_scope_mismatch",
                sessionError.Message);

            setup.Clock.Advance(
                TimeSpan.FromMinutes(16));
            InvalidOperationException expired =
                Assert.Throws<InvalidOperationException>(
                    () => setup.Broker.Acquire(
                        PlayerGuiRequest(
                            setup.Credential,
                            TimeSpan.FromSeconds(1),
                            1,
                            new[] { "flash-a" },
                            setup.Credential
                                .IssuerReceipt)));
            Assert.Equal(
                "credential_expired",
                expired.Message);
        }

        [Fact]
        public void DeveloperLease_RenewsAtMostOnce()
        {
            var clock = new ManualAgentRuntimeClock();
            var authority = new PrincipalCredentialAuthority(
                clock,
                new TestPrincipalEnrollmentVerifier());
            PrincipalCredential credential = authority.IssueDeveloper(
                new DeveloperEnrollmentEvidence
                {
                    ClientInstanceId = "dev-client",
                    EnrollmentReceipt = "dev-enroll",
                    AllowedCapabilities = new[] { "input.click" },
                    AllowedTargets = new[] { "flash-a" }
                });
            var targets = new MutableAgentTargetAuthority();
            targets.Set("session-a", "flash-a");
            var broker = new WriteLeaseBroker(
                clock,
                authority,
                targets);
            WriteLease lease = broker.Acquire(
                new WriteLeaseRequest
                {
                    CredentialId = credential.CredentialId,
                    ClientInstanceId = "dev-client",
                    SessionId = "session-a",
                    LifecycleGeneration = 1,
                    Kind = WriteLeaseKind.GuiInput,
                    Capabilities = new[] { "input.click" },
                    TargetScope = new[] { "flash-a" },
                    RequestedLifetime = TimeSpan.FromMinutes(1),
                    RequestedActionLimit = 2
                });

            Assert.True(broker.TryRenewDeveloper(
                lease.LeaseId,
                "dev-client",
                credential.SecurityPrincipalId,
                TimeSpan.FromMinutes(10),
                out _,
                out _));
            Assert.False(broker.TryRenewDeveloper(
                lease.LeaseId,
                "dev-client",
                credential.SecurityPrincipalId,
                TimeSpan.FromMinutes(1),
                out _,
                out string reason));
            Assert.Equal("renewal_limit_reached", reason);
        }

        [Fact]
        public void DirectBrokerCallerCannotBypassGlobalTargetScopeCap()
        {
            var clock = new ManualAgentRuntimeClock();
            string[] targetIds = Enumerable.Range(
                    0,
                    AgentProtocolV1.MaximumTargetScopeItems + 1)
                .Select(index => "target-" + index)
                .ToArray();
            var authority = new PrincipalCredentialAuthority(
                clock,
                new TestPrincipalEnrollmentVerifier());
            PrincipalCredential credential = authority.IssueDeveloper(
                new DeveloperEnrollmentEvidence
                {
                    ClientInstanceId = "dev-client",
                    EnrollmentReceipt = "dev-enroll",
                    AllowedCapabilities = new[] { "input.click" },
                    AllowedTargets = targetIds
                });
            var targets = new MutableAgentTargetAuthority();
            foreach (string targetId in targetIds)
                targets.Set("session-a", targetId);
            var broker = new WriteLeaseBroker(
                clock,
                authority,
                targets);

            InvalidOperationException error =
                Assert.Throws<InvalidOperationException>(
                    () => broker.Acquire(
                        new WriteLeaseRequest
                        {
                            CredentialId =
                                credential.CredentialId,
                            ClientInstanceId = "dev-client",
                            SessionId = "session-a",
                            LifecycleGeneration = 1,
                            Kind = WriteLeaseKind.GuiInput,
                            Capabilities =
                                new[] { "input.click" },
                            TargetScope = targetIds,
                            RequestedLifetime =
                                TimeSpan.FromMinutes(1),
                            RequestedActionLimit = 2
                        }));

            Assert.Equal("target_scope_denied", error.Message);
        }

        [Fact]
        public void DeveloperRenewal_CannotOutliveCredential()
        {
            var clock = new ManualAgentRuntimeClock();
            var authority = new PrincipalCredentialAuthority(
                clock,
                new TestPrincipalEnrollmentVerifier());
            PrincipalCredential credential = authority.IssueDeveloper(
                new DeveloperEnrollmentEvidence
                {
                    ClientInstanceId = "dev-client",
                    EnrollmentReceipt = "dev-enroll",
                    AllowedCapabilities = new[] { "input.click" },
                    AllowedTargets = new[] { "flash-a" },
                    RequestedLifetime = TimeSpan.FromMinutes(2)
                });
            var targets = new MutableAgentTargetAuthority();
            targets.Set("session-a", "flash-a");
            var broker = new WriteLeaseBroker(
                clock,
                authority,
                targets);
            WriteLease lease = broker.Acquire(
                new WriteLeaseRequest
                {
                    CredentialId = credential.CredentialId,
                    ClientInstanceId = "dev-client",
                    SessionId = "session-a",
                    LifecycleGeneration = 1,
                    Kind = WriteLeaseKind.GuiInput,
                    Capabilities = new[] { "input.click" },
                    TargetScope = new[] { "flash-a" },
                    RequestedLifetime = TimeSpan.FromMinutes(1),
                    RequestedActionLimit = 2
                });

            clock.Advance(TimeSpan.FromSeconds(30));

            Assert.True(broker.TryRenewDeveloper(
                lease.LeaseId,
                "dev-client",
                credential.SecurityPrincipalId,
                TimeSpan.FromMinutes(5),
                out WriteLease renewed,
                out _));
            Assert.Equal(
                credential.ExpiresMonotonic,
                renewed.ExpiresMonotonic);
        }

        [Fact]
        public void Consume_RevokesLeaseWhenTargetBecomesHumanOnly()
        {
            var setup = CreatePlayerSetup();
            WriteLease lease = setup.Broker.Acquire(
                PlayerGuiRequest(
                    setup.Credential,
                    TimeSpan.FromSeconds(10),
                    2,
                    new[] { "flash-a" },
                    setup.Credential.IssuerReceipt));

            setup.Targets.Set(
                "session-a",
                "flash-a",
                AgentTargetSafetyKind.HumanOnlySecuritySurface);

            Assert.False(setup.Broker.TryConsumeAction(
                lease.LeaseId,
                "wings-client",
                setup.Credential.SecurityPrincipalId,
                out _,
                out string reason));
            Assert.Equal("human_only_security_surface", reason);
            Assert.Equal(WriteLeaseState.Revoked, lease.State);
        }

        [Fact]
        public void
            UnattendedSessionRejectsNewAndPreviouslyIssuedWingsLease()
        {
            var setup = CreatePlayerSetup();
            WriteLease existing = setup.Broker.Acquire(
                PlayerGuiRequest(
                    setup.Credential,
                    TimeSpan.FromSeconds(10),
                    2,
                    new[] { "flash-a" },
                    setup.Credential.IssuerReceipt));

            setup.Targets.SetSessionMode(
                "session-a",
                SessionMode.UnattendedTest);

            Assert.False(setup.Broker.TryConsumeAction(
                existing.LeaseId,
                "wings-client",
                setup.Credential.SecurityPrincipalId,
                out _,
                out string consumeReason));
            Assert.Equal("session_mismatch", consumeReason);
            Assert.Equal(WriteLeaseState.Revoked, existing.State);

            InvalidOperationException acquireError =
                Assert.Throws<InvalidOperationException>(
                    () => setup.Broker.Acquire(
                        PlayerGuiRequest(
                            setup.Credential,
                            TimeSpan.FromSeconds(10),
                            1,
                            new[] { "flash-a" },
                            setup.Credential.IssuerReceipt)));
            Assert.Equal(
                "session_mismatch",
                acquireError.Message);
        }

        private static WriteLeaseRequest PlayerGuiRequest(
            PrincipalCredential credential,
            TimeSpan lifetime,
            int actionLimit,
            string[] targets,
            string consent,
            bool includeArgumentBoundsHash = true)
        {
            return new WriteLeaseRequest
            {
                CredentialId = credential.CredentialId,
                ClientInstanceId = "wings-client",
                SessionId = "session-a",
                LifecycleGeneration = 1,
                Kind = WriteLeaseKind.GuiInput,
                Capabilities = new[] { "input.click" },
                TargetScope = targets,
                RequestedLifetime = lifetime,
                RequestedActionLimit = actionLimit,
                ConsentReceipt = consent,
                ArgumentBoundsHash =
                    includeArgumentBoundsHash
                        ? new string('A', 64)
                        : null
            };
        }

        private static WriteLeaseRequest
            ShutdownRequest(
                PrincipalCredential credential,
                string clientInstanceId,
                string target,
                string[] capabilities = null,
                string[] targets = null,
                int actionLimit = 1,
                string sessionId = "session-a")
        {
            return new WriteLeaseRequest
            {
                CredentialId = credential.CredentialId,
                ClientInstanceId = clientInstanceId,
                SessionId = sessionId,
                LifecycleGeneration = 1,
                Kind = WriteLeaseKind.Shutdown,
                Capabilities = capabilities ?? new[]
                {
                    AgentCapabilitiesV1
                        .SessionShutdown
                },
                TargetScope =
                    targets ?? new[] { target },
                RequestedLifetime =
                    TimeSpan.FromMinutes(5),
                RequestedActionLimit = actionLimit,
                ConsentReceipt = credential.IssuerReceipt,
                ArgumentBoundsHash =
                    credential.SessionMode
                        == AgentSessionMode.PlayerAssist
                        ? new string('A', 64)
                        : null
            };
        }

        private static WriteLeaseRequest
            StructuredActionRequest(
                PrincipalCredential credential,
                string clientInstanceId,
                string target,
                string[] capabilities = null,
                string[] targets = null,
                int actionLimit = 1,
                WriteLeaseKind kind =
                    WriteLeaseKind.StructuredAction)
        {
            return new WriteLeaseRequest
            {
                CredentialId = credential.CredentialId,
                ClientInstanceId = clientInstanceId,
                SessionId = "session-a",
                LifecycleGeneration = 1,
                Kind = kind,
                Capabilities = capabilities ?? new[]
                {
                    AgentCapabilitiesV1.PanelOpen
                },
                TargetScope =
                    targets ?? new[] { target },
                RequestedLifetime =
                    TimeSpan.FromMinutes(5),
                RequestedActionLimit = actionLimit
            };
        }

        private static WriteLeaseRequest DeveloperGuiRequest(
            PrincipalCredential credential,
            string sessionId)
        {
            return new WriteLeaseRequest
            {
                CredentialId = credential.CredentialId,
                ClientInstanceId = "dev-client",
                SessionId = sessionId,
                LifecycleGeneration = 1,
                Kind = WriteLeaseKind.GuiInput,
                Capabilities = new[]
                {
                    AgentCapabilitiesV1.Click
                },
                TargetScope = new[] { "flash-a" },
                RequestedLifetime = TimeSpan.FromMinutes(1),
                RequestedActionLimit = 2
            };
        }

        private static WriteLease CommitShutdown(
            WriteLeaseBroker broker,
            PrincipalCredential credential,
            string sessionId)
        {
            WriteLease lease = broker.Acquire(
                ShutdownRequest(
                    credential,
                    "dev-client",
                    "launcher-a",
                    sessionId: sessionId));
            Assert.True(
                broker.TryConsumeAction(
                    lease.LeaseId,
                    "dev-client",
                    credential.SecurityPrincipalId,
                    sessionId,
                    AgentCapabilitiesV1.SessionShutdown,
                    "launcher-a",
                    AgentCapabilitiesV1.SessionShutdown,
                    out _,
                    out _));
            Assert.True(
                broker.MarkShutdownDeliveryPending(
                    lease.LeaseId));
            Assert.True(
                broker.TryClaimShutdownDeliveryWrite(
                    lease.LeaseId));
            Assert.True(
                broker.CompleteShutdownDelivery(
                    lease.LeaseId));
            return lease;
        }

        private static (
            ManualAgentRuntimeClock Clock,
            PrincipalCredentialAuthority Authority,
            PrincipalCredential Credential,
            MutableAgentTargetAuthority Targets,
            WriteLeaseBroker Broker) CreatePlayerSetup()
        {
            var clock = new ManualAgentRuntimeClock();
            var authority = new PrincipalCredentialAuthority(
                clock,
                new TestPrincipalEnrollmentVerifier());
            var targets = new MutableAgentTargetAuthority();
            targets.Set("session-a", "flash-a");
            targets.Set("session-a", "web-a");
            targets.Set("session-a", "hair-domain");
            PrincipalCredential credential =
                authority.IssuePlayerAssist(
                    new PlayerAssistCredentialEvidence
                    {
                        ClientInstanceId = "wings-client",
                        ConsentReceipt = "player-enroll",
                        SelectedSessionId = "session-a",
                        AllowedCapabilities = new[]
                        {
                            "input.click",
                            "domain.hair.change",
                            AgentCapabilitiesV1
                                .SessionShutdown
                        },
                        AllowedTargets = new[]
                        {
                            "flash-a",
                            "web-a",
                            "hair-domain"
                        }
                    });
            return (
                clock,
                authority,
                credential,
                targets,
                new WriteLeaseBroker(
                    clock,
                    authority,
                    targets));
        }

        private static (
            PrincipalCredential Credential,
            MutableAgentTargetAuthority Targets,
            WriteLeaseBroker Broker)
            CreateDeveloperShutdownSetup()
        {
            var clock = new ManualAgentRuntimeClock();
            var authority = new PrincipalCredentialAuthority(
                clock,
                new TestPrincipalEnrollmentVerifier());
            PrincipalCredential credential =
                authority.IssueDeveloper(
                    new DeveloperEnrollmentEvidence
                    {
                        ClientInstanceId = "dev-client",
                        EnrollmentReceipt = "dev-enroll",
                        AllowedCapabilities = new[]
                        {
                            AgentCapabilitiesV1
                                .SessionShutdown,
                            AgentCapabilitiesV1.Click,
                            AgentCapabilitiesV1.PanelOpen
                        },
                        AllowedTargets = new[]
                        {
                            "launcher-a",
                            "launcher-b",
                            "flash-a"
                        }
                    });
            var targets = new MutableAgentTargetAuthority();
            targets.Set(
                "session-a",
                "launcher-a",
                kind: SurfaceKind.Launcher);
            targets.Set("session-a", "flash-a");
            return (
                credential,
                targets,
                new WriteLeaseBroker(
                    clock,
                    authority,
                    targets));
        }
    }
}
