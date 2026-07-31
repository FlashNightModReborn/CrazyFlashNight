using System;
using System.Collections.Generic;
using System.Threading;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Gateway;
using CF7Launcher.AgentRuntime.Input;
using CF7Launcher.AgentRuntime.NativeInput;
using CF7Launcher.AgentRuntime.Security;
using CF7Launcher.AgentRuntime.Sessions;
using CF7Launcher.Tests.AgentRuntime.Security;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.Gateway
{
    public sealed class AgentRuntimeRevocationCoordinatorTests
    {
        [Fact]
        public void DisconnectRevokesCredentialGrantLeaseAndAction()
        {
            Fixture fixture = new Fixture();
            using var coordinator =
                new AgentRuntimeRevocationCoordinator(
                    fixture.Credentials,
                    fixture.Grants,
                    fixture.Leases);
            coordinator.RegisterConnection(
                ConnectionId,
                fixture.Credential);
            using var guard = new NativeInputGuard(
                new InputSafetyStateMachine(fixture.Clock),
                new GuardWin32Facade(),
                coordinator,
                false);
            coordinator.BindNativeGuard(guard);
            AgentRuntimeRevocationCoordinator
                .SessionFenceTicket fence =
                    fixture.CaptureFence(coordinator);
            ObservationGrant grant =
                fixture.IssueObservationGrant();
            WriteLease lease = fixture.IssueLease();
            Assert.True(
                coordinator.TryTrackGrant(
                    fence,
                    grant,
                    out string grantReason),
                grantReason);
            Assert.True(
                coordinator.TryTrackLease(
                    fence,
                    lease,
                    out string leaseReason),
                leaseReason);
            using var action = coordinator.RegisterAction(
                ConnectionId,
                lease.LeaseId,
                CancellationToken.None);

            coordinator.RevokeConnection(
                ConnectionId,
                "connection_closed");

            Assert.True(action.Token.IsCancellationRequested);
            Assert.Equal(
                CredentialState.Revoked,
                fixture.Credential.State);
            Assert.Equal(
                CF7Launcher.AgentRuntime.Security
                    .ObservationGrantState.Revoked,
                grant.State);
            Assert.Equal(
                WriteLeaseState.Revoked,
                lease.State);
        }

        [Fact]
        public void NativePreemptionRevokesOnlyExactTrackedLease()
        {
            Fixture fixture = new Fixture();
            using var coordinator =
                new AgentRuntimeRevocationCoordinator(
                    fixture.Credentials,
                    fixture.Grants,
                    fixture.Leases);
            coordinator.RegisterConnection(
                ConnectionId,
                fixture.Credential);
            using var guard = new NativeInputGuard(
                new InputSafetyStateMachine(fixture.Clock),
                new GuardWin32Facade(),
                coordinator,
                false);
            coordinator.BindNativeGuard(guard);
            AgentRuntimeRevocationCoordinator
                .SessionFenceTicket fence =
                    fixture.CaptureFence(coordinator);
            WriteLease lease = fixture.IssueLease();
            Assert.True(
                coordinator.TryTrackLease(
                    fence,
                    lease,
                    out string trackReason),
                trackReason);
            using var action = coordinator.RegisterAction(
                ConnectionId,
                lease.LeaseId,
                CancellationToken.None);

            coordinator.RevokeLeaseAndCancelQueuedActions(
                SessionId,
                lease.LeaseId,
                "external_input_preempted");

            Assert.True(action.Token.IsCancellationRequested);
            Assert.Equal(
                WriteLeaseState.Revoked,
                lease.State);
            Assert.Equal(
                CredentialState.Active,
                fixture.Credential.State);
        }

        [Fact]
        public void PhysicalInputObservedBeforeShutdownClaimWinsFence()
        {
            Fixture fixture = new Fixture();
            using var coordinator =
                new AgentRuntimeRevocationCoordinator(
                    fixture.Credentials,
                    fixture.Grants,
                    fixture.Leases);
            coordinator.RegisterConnection(
                ConnectionId,
                fixture.Credential);
            var win32 = new GuardWin32Facade();
            using var guard = new NativeInputGuard(
                new InputSafetyStateMachine(fixture.Clock),
                win32,
                coordinator,
                false);
            coordinator.BindNativeGuard(guard);
            win32.AdvanceQuiescence();
            AgentRuntimeRevocationCoordinator
                .SessionFenceTicket fence =
                    fixture.CaptureFence(coordinator);
            WriteLease lease = fixture.IssueShutdownLease();
            Assert.True(
                coordinator.TryTrackLease(
                    fence,
                    lease,
                    out string trackReason),
                trackReason);
            Assert.True(
                fixture.Leases.TryConsumeAction(
                    lease.LeaseId,
                    ClientId,
                    fixture.Credential.SecurityPrincipalId,
                    SessionId,
                    AgentCapabilitiesV1.SessionShutdown,
                    TargetId,
                    AgentCapabilitiesV1.SessionShutdown,
                    out _,
                    out string consumeReason),
                consumeReason);
            Assert.True(
                fixture.Leases.MarkShutdownDeliveryPending(
                    lease.LeaseId));

            guard.ObserveExternallyHeldControls(
                new[] { "key:A" });

            Assert.False(
                coordinator.TryClaimShutdownDeliveryWrite(
                    lease.LeaseId));
            Assert.True(
                SpinWait.SpinUntil(
                    () => lease.State
                        == WriteLeaseState.Revoked,
                    TimeSpan.FromSeconds(3)));
            Assert.True(
                fixture.Leases.AbortPendingActionExecution(
                    lease.LeaseId));
        }

        [Fact]
        public void ShutdownClaimBeforePhysicalInputCannotBeRolledBack()
        {
            Fixture fixture = new Fixture();
            using var coordinator =
                new AgentRuntimeRevocationCoordinator(
                    fixture.Credentials,
                    fixture.Grants,
                    fixture.Leases);
            coordinator.RegisterConnection(
                ConnectionId,
                fixture.Credential);
            var win32 = new GuardWin32Facade();
            using var guard = new NativeInputGuard(
                new InputSafetyStateMachine(fixture.Clock),
                win32,
                coordinator,
                false);
            coordinator.BindNativeGuard(guard);
            win32.AdvanceQuiescence();
            AgentRuntimeRevocationCoordinator
                .SessionFenceTicket fence =
                    fixture.CaptureFence(coordinator);
            WriteLease lease = fixture.IssueShutdownLease();
            Assert.True(
                coordinator.TryTrackLease(
                    fence,
                    lease,
                    out string trackReason),
                trackReason);
            Assert.True(
                fixture.Leases.TryConsumeAction(
                    lease.LeaseId,
                    ClientId,
                    fixture.Credential.SecurityPrincipalId,
                    SessionId,
                    AgentCapabilitiesV1.SessionShutdown,
                    TargetId,
                    AgentCapabilitiesV1.SessionShutdown,
                    out _,
                    out string consumeReason),
                consumeReason);
            Assert.True(
                fixture.Leases.MarkShutdownDeliveryPending(
                    lease.LeaseId));
            using var observed =
                new ManualResetEventSlim(false);
            guard.ExternalInputObserved +=
                _ => observed.Set();
            Assert.True(
                coordinator.TryClaimShutdownDeliveryWrite(
                    lease.LeaseId));

            guard.ObserveExternallyHeldControls(
                new[] { "key:A" });

            Assert.True(
                observed.Wait(TimeSpan.FromSeconds(3)));
            Assert.Equal(
                WriteLeaseState.Consumed,
                lease.State);
            Assert.True(
                fixture.Leases.CompleteShutdownDelivery(
                    lease.LeaseId));
        }

        [Fact]
        public void ShutdownLeaseCannotBeTrackedWithoutNativeGuard()
        {
            Fixture fixture = new Fixture();
            using var coordinator =
                new AgentRuntimeRevocationCoordinator(
                    fixture.Credentials,
                    fixture.Grants,
                    fixture.Leases);
            coordinator.RegisterConnection(
                ConnectionId,
                fixture.Credential);
            AgentRuntimeRevocationCoordinator
                .SessionFenceTicket fence =
                    fixture.CaptureFence(coordinator);
            WriteLease lease = fixture.IssueShutdownLease();

            Assert.False(
                coordinator.TryTrackLease(
                    fence,
                    lease,
                    out string reasonCode));
            Assert.Equal(
                "input_guard_unhealthy",
                reasonCode);
            Assert.True(
                fixture.Leases.Revoke(
                    lease.LeaseId,
                reasonCode));
        }

        [Fact]
        public void
            StructuredActionLeaseRequiresHumanFenceAndExternalInputRevokesIt()
        {
            Fixture unguarded = new Fixture();
            using (var coordinator =
                new AgentRuntimeRevocationCoordinator(
                    unguarded.Credentials,
                    unguarded.Grants,
                    unguarded.Leases))
            {
                coordinator.RegisterConnection(
                    ConnectionId,
                    unguarded.Credential);
                AgentRuntimeRevocationCoordinator
                    .SessionFenceTicket fence =
                        unguarded.CaptureFence(coordinator);
                WriteLease lease =
                    unguarded.IssueStructuredActionLease();

                Assert.False(
                    coordinator.TryTrackLease(
                        fence,
                        lease,
                        out string reasonCode));
                Assert.Equal(
                    "input_guard_unhealthy",
                    reasonCode);
                Assert.True(
                    unguarded.Leases.Revoke(
                        lease.LeaseId,
                        reasonCode));
            }

            Fixture fixture = new Fixture();
            using var guarded =
                new AgentRuntimeRevocationCoordinator(
                    fixture.Credentials,
                    fixture.Grants,
                    fixture.Leases);
            guarded.RegisterConnection(
                ConnectionId,
                fixture.Credential);
            var win32 = new GuardWin32Facade();
            using var guard = new NativeInputGuard(
                new InputSafetyStateMachine(fixture.Clock),
                win32,
                guarded,
                false);
            guarded.BindNativeGuard(guard);
            win32.AdvanceQuiescence();
            AgentRuntimeRevocationCoordinator
                .SessionFenceTicket guardedFence =
                    fixture.CaptureFence(guarded);
            WriteLease structured =
                fixture.IssueStructuredActionLease();
            Assert.True(
                guarded.TryTrackLease(
                    guardedFence,
                    structured,
                    out string trackReason),
                trackReason);
            Assert.False(
                guard.TryGetBoundLease(
                    out _,
                    out _));
            using AgentRuntimeRevocationCoordinator
                .ActionCancellationRegistration action =
                    guarded.RegisterAction(
                        ConnectionId,
                        structured.LeaseId,
                        CancellationToken.None);

            guard.ObserveExternallyHeldControls(
                new[] { "key:A" });

            Assert.True(
                SpinWait.SpinUntil(
                    () => structured.State
                            == WriteLeaseState.Revoked
                        && action.Token
                            .IsCancellationRequested,
                    TimeSpan.FromSeconds(3)));
            Assert.False(
                guard.TryGetBoundLease(
                    out _,
                    out _));
        }

        [Fact]
        public void HookUnhealthyBeforeShutdownClaimFailsClosed()
        {
            Fixture fixture = new Fixture();
            using var coordinator =
                new AgentRuntimeRevocationCoordinator(
                    fixture.Credentials,
                    fixture.Grants,
                    fixture.Leases);
            coordinator.RegisterConnection(
                ConnectionId,
                fixture.Credential);
            var win32 = new GuardWin32Facade();
            using var guard = new NativeInputGuard(
                new InputSafetyStateMachine(fixture.Clock),
                win32,
                coordinator,
                false);
            coordinator.BindNativeGuard(guard);
            win32.AdvanceQuiescence();
            AgentRuntimeRevocationCoordinator
                .SessionFenceTicket fence =
                    fixture.CaptureFence(coordinator);
            WriteLease lease = fixture.IssueShutdownLease();
            Assert.True(
                coordinator.TryTrackLease(
                    fence,
                    lease,
                    out string trackReason),
                trackReason);
            Assert.True(
                fixture.Leases.TryConsumeAction(
                    lease.LeaseId,
                    ClientId,
                    fixture.Credential.SecurityPrincipalId,
                    SessionId,
                    AgentCapabilitiesV1.SessionShutdown,
                    TargetId,
                    AgentCapabilitiesV1.SessionShutdown,
                    out _,
                    out string consumeReason),
                consumeReason);
            Assert.True(
                fixture.Leases.MarkShutdownDeliveryPending(
                    lease.LeaseId));

            win32.HookSession.Healthy = false;

            Assert.False(
                coordinator.TryClaimShutdownDeliveryWrite(
                    lease.LeaseId));
            Assert.True(
                SpinWait.SpinUntil(
                    () => lease.State
                        == WriteLeaseState.Revoked,
                    TimeSpan.FromSeconds(3)));
            Assert.True(
                fixture.Leases.AbortPendingActionExecution(
                    lease.LeaseId));
        }

        [Fact]
        public void HeldHumanControlPreventsShutdownLeaseTracking()
        {
            Fixture fixture = new Fixture();
            using var coordinator =
                new AgentRuntimeRevocationCoordinator(
                    fixture.Credentials,
                    fixture.Grants,
                    fixture.Leases);
            coordinator.RegisterConnection(
                ConnectionId,
                fixture.Credential);
            var win32 = new GuardWin32Facade
            {
                HeldControls = new[] { "key:A" }
            };
            using var guard = new NativeInputGuard(
                new InputSafetyStateMachine(fixture.Clock),
                win32,
                coordinator,
                false);
            coordinator.BindNativeGuard(guard);
            win32.AdvanceQuiescence();
            AgentRuntimeRevocationCoordinator
                .SessionFenceTicket fence =
                    fixture.CaptureFence(coordinator);
            WriteLease lease = fixture.IssueShutdownLease();

            Assert.False(
                coordinator.TryTrackLease(
                    fence,
                    lease,
                    out string reasonCode));
            Assert.Equal(
                "input_not_quiescent",
                reasonCode);
            Assert.True(
                fixture.Leases.Revoke(
                    lease.LeaseId,
                    reasonCode));
        }

        [Fact]
        public void QueuedHumanObservationCannotBecomeShutdownBaseline()
        {
            Fixture fixture = new Fixture();
            using var coordinator =
                new AgentRuntimeRevocationCoordinator(
                    fixture.Credentials,
                    fixture.Grants,
                    fixture.Leases);
            coordinator.RegisterConnection(
                ConnectionId,
                fixture.Credential);
            var win32 = new GuardWin32Facade();
            using var guard = new NativeInputGuard(
                new InputSafetyStateMachine(fixture.Clock),
                win32,
                coordinator,
                false);
            using var observerEntered =
                new ManualResetEventSlim(false);
            using var releaseObserver =
                new ManualResetEventSlim(false);
            guard.ExternalInputObserved +=
                _ =>
                {
                    observerEntered.Set();
                    releaseObserver.Wait(
                        TimeSpan.FromSeconds(3));
                };
            coordinator.BindNativeGuard(guard);
            win32.AdvanceQuiescence();
            AgentRuntimeRevocationCoordinator
                .SessionFenceTicket fence =
                    fixture.CaptureFence(coordinator);
            WriteLease lease = fixture.IssueShutdownLease();
            Assert.True(
                coordinator.TryTrackLease(
                    fence,
                    lease,
                    out string trackReason),
                trackReason);
            Assert.True(
                fixture.Leases.TryConsumeAction(
                    lease.LeaseId,
                    ClientId,
                    fixture.Credential.SecurityPrincipalId,
                    SessionId,
                    AgentCapabilitiesV1.SessionShutdown,
                    TargetId,
                    AgentCapabilitiesV1.SessionShutdown,
                    out _,
                    out string consumeReason),
                consumeReason);
            Assert.True(
                fixture.Leases.MarkShutdownDeliveryPending(
                    lease.LeaseId));

            try
            {
                guard.ObserveExternallyHeldControls(
                    new[] { "key:A" });
                Assert.True(
                    observerEntered.Wait(
                        TimeSpan.FromSeconds(3)));
                Assert.False(
                    coordinator.TryClaimShutdownDeliveryWrite(
                        lease.LeaseId));
            }
            finally
            {
                releaseObserver.Set();
            }
            Assert.True(
                SpinWait.SpinUntil(
                    () => lease.State
                        == WriteLeaseState.Revoked,
                    TimeSpan.FromSeconds(3)));
            Assert.True(
                fixture.Leases.AbortPendingActionExecution(
                    lease.LeaseId));
        }

        [Fact]
        public void DetachRevokesConnectionSessionResourcesOnly()
        {
            Fixture fixture = new Fixture();
            using var coordinator =
                new AgentRuntimeRevocationCoordinator(
                    fixture.Credentials,
                    fixture.Grants,
                    fixture.Leases);
            coordinator.RegisterConnection(
                ConnectionId,
                fixture.Credential);
            Assert.True(
                coordinator.TryAttachSession(
                    ConnectionId,
                    fixture.Credential,
                    SessionId,
                    1,
                    out string attachReason),
                attachReason);
            AgentRuntimeRevocationCoordinator
                .SessionFenceTicket fence =
                    fixture.CaptureFence(coordinator);
            ObservationGrant grant =
                fixture.IssueObservationGrant();
            WriteLease lease = fixture.IssueLease();
            Assert.True(
                coordinator.TryTrackGrant(
                    fence,
                    grant,
                    out string grantReason),
                grantReason);
            Assert.True(
                coordinator.TryTrackLease(
                    fence,
                    lease,
                    out string leaseReason),
                leaseReason);
            using var action = coordinator.RegisterAction(
                ConnectionId,
                lease.LeaseId,
                CancellationToken.None);

            Assert.True(
                coordinator.TryDetachSession(
                    ConnectionId,
                    fixture.Credential,
                    SessionId,
                    1,
                    out string detachReason),
                detachReason);

            Assert.True(action.Token.IsCancellationRequested);
            Assert.Equal(
                CF7Launcher.AgentRuntime.Security
                    .ObservationGrantState.Revoked,
                grant.State);
            Assert.Equal(
                WriteLeaseState.Revoked,
                lease.State);
            Assert.Equal(
                CredentialState.Active,
                fixture.Credential.State);
            Assert.True(
                coordinator.IsDispatchAuthorized(
                    ConnectionId,
                    fixture.Credential));
            Assert.True(
                coordinator.TryAttachSession(
                    ConnectionId,
                    fixture.Credential,
                    SessionId,
                    1,
                    out string reattachReason),
                reattachReason);
        }

        [Fact]
        public void
            ExplicitDetachFencesCrossingResourcesUntilExactReattach()
        {
            Fixture fixture = new Fixture();
            using var coordinator =
                new AgentRuntimeRevocationCoordinator(
                    fixture.Credentials,
                    fixture.Grants,
                    fixture.Leases);
            coordinator.RegisterConnection(
                ConnectionId,
                fixture.Credential);
            Assert.True(
                coordinator.TryAttachSession(
                    ConnectionId,
                    fixture.Credential,
                    SessionId,
                    1,
                    out string attachReason),
                attachReason);
            AgentRuntimeRevocationCoordinator
                .SessionFenceTicket crossingFence =
                    fixture.CaptureFence(coordinator);

            Assert.True(
                coordinator.TryDetachSession(
                    ConnectionId,
                    fixture.Credential,
                    SessionId,
                    1,
                    out string detachReason),
                detachReason);
            Assert.False(
                coordinator.TryCaptureSessionFence(
                    ConnectionId,
                    fixture.Credential,
                    SessionId,
                    1,
                    out _,
                    out string fencedReason));
            Assert.Equal("session_mismatch", fencedReason);

            ObservationGrant crossingGrant =
                fixture.IssueObservationGrant();
            WriteLease crossingLease =
                fixture.IssueLease();
            Assert.False(
                coordinator.TryTrackGrant(
                    crossingFence,
                    crossingGrant,
                    out string grantReason));
            Assert.Equal("session_mismatch", grantReason);
            Assert.False(
                coordinator.TryTrackLease(
                    crossingFence,
                    crossingLease,
                    out string leaseReason));
            Assert.Equal("session_mismatch", leaseReason);
            fixture.Grants.Revoke(
                crossingGrant.ObservationGrantId,
                grantReason);
            fixture.Leases.Revoke(
                crossingLease.LeaseId,
                leaseReason);
            Assert.Equal(
                CF7Launcher.AgentRuntime.Security
                    .ObservationGrantState.Revoked,
                crossingGrant.State);
            Assert.Equal(
                WriteLeaseState.Revoked,
                crossingLease.State);

            Assert.False(
                coordinator.TryAttachSession(
                    ConnectionId,
                    fixture.Credential,
                    SessionId,
                    2,
                    out string wrongLifecycleReason));
            Assert.Equal(
                "session_mismatch",
                wrongLifecycleReason);
            Assert.True(
                coordinator.TryAttachSession(
                    ConnectionId,
                    fixture.Credential,
                    SessionId,
                    1,
                    out string reattachReason),
                reattachReason);
            AgentRuntimeRevocationCoordinator
                .SessionFenceTicket replacementFence =
                    fixture.CaptureFence(coordinator);
            ObservationGrant replacementGrant =
                fixture.IssueObservationGrant();
            WriteLease replacementLease =
                fixture.IssueLease();
            Assert.True(
                coordinator.TryTrackGrant(
                    replacementFence,
                    replacementGrant,
                    out string replacementGrantReason),
                replacementGrantReason);
            Assert.True(
                coordinator.TryTrackLease(
                    replacementFence,
                    replacementLease,
                    out string replacementLeaseReason),
                replacementLeaseReason);
        }

        [Fact]
        public void LifecycleInvalidationRejectsCrossingFenceResources()
        {
            Fixture fixture = new Fixture();
            using var coordinator =
                new AgentRuntimeRevocationCoordinator(
                    fixture.Credentials,
                    fixture.Grants,
                    fixture.Leases);
            coordinator.RegisterConnection(
                ConnectionId,
                fixture.Credential);
            AgentRuntimeRevocationCoordinator
                .SessionFenceTicket crossingFence =
                    fixture.CaptureFence(coordinator);
            ObservationGrant crossingGrant =
                fixture.IssueObservationGrant();
            WriteLease crossingLease =
                fixture.IssueLease();

            coordinator.HandleSessionInvalidation(
                new SessionScopeInvalidation(
                    SessionInvalidationLevel.Lifecycle,
                    "stale_lifecycle",
                    SessionId,
                    1,
                    SessionInvalidationFlags.None,
                    Array.Empty<string>(),
                    true,
                    false));

            Assert.False(
                coordinator.TryTrackGrant(
                    crossingFence,
                    crossingGrant,
                    out string grantReason));
            Assert.Equal("stale_lifecycle", grantReason);
            Assert.False(
                coordinator.TryTrackLease(
                    crossingFence,
                    crossingLease,
                    out string leaseReason));
            Assert.Equal("stale_lifecycle", leaseReason);
            fixture.Grants.Revoke(
                crossingGrant.ObservationGrantId,
                grantReason);
            fixture.Leases.Revoke(
                crossingLease.LeaseId,
                leaseReason);
        }

        [Fact]
        public void ConnectionRevocationRejectsCrossingFenceResources()
        {
            Fixture fixture = new Fixture();
            using var coordinator =
                new AgentRuntimeRevocationCoordinator(
                    fixture.Credentials,
                    fixture.Grants,
                    fixture.Leases);
            coordinator.RegisterConnection(
                ConnectionId,
                fixture.Credential);
            AgentRuntimeRevocationCoordinator
                .SessionFenceTicket crossingFence =
                    fixture.CaptureFence(coordinator);
            ObservationGrant crossingGrant =
                fixture.IssueObservationGrant();
            WriteLease crossingLease =
                fixture.IssueLease();

            coordinator.RevokeConnection(
                ConnectionId,
                "connection_closed");

            Assert.False(
                coordinator.TryTrackGrant(
                    crossingFence,
                    crossingGrant,
                    out string grantReason));
            Assert.Equal("credential_revoked", grantReason);
            Assert.False(
                coordinator.TryTrackLease(
                    crossingFence,
                    crossingLease,
                    out string leaseReason));
            Assert.Equal("credential_revoked", leaseReason);
            fixture.Grants.Revoke(
                crossingGrant.ObservationGrantId,
                grantReason);
            fixture.Leases.Revoke(
                crossingLease.LeaseId,
                leaseReason);
            Assert.Equal(
                CF7Launcher.AgentRuntime.Security
                    .ObservationGrantState.Revoked,
                crossingGrant.State);
            Assert.Equal(
                WriteLeaseState.Revoked,
                crossingLease.State);
        }

        [Fact]
        public void
            RotationRevokesOnlyOldReceiptAndRejectsLateRegistration()
        {
            Fixture fixture = new Fixture();
            using var coordinator =
                new AgentRuntimeRevocationCoordinator(
                    fixture.Credentials,
                    fixture.Grants,
                    fixture.Leases);
            bool oldTerminated = false;
            bool otherTerminated = false;
            PrincipalCredential other =
                fixture.IssueDeveloperCredential(
                    OtherClientId,
                    OtherReceipt);
            coordinator.RegisterConnection(
                ConnectionId,
                fixture.Credential,
                reason => oldTerminated = true);
            coordinator.RegisterConnection(
                OtherConnectionId,
                other,
                reason => otherTerminated = true);
            AgentRuntimeRevocationCoordinator
                .SessionFenceTicket fence =
                    fixture.CaptureFence(coordinator);
            ObservationGrant grant =
                fixture.IssueObservationGrant();
            WriteLease lease = fixture.IssueLease();
            Assert.True(
                coordinator.TryTrackGrant(
                    fence,
                    grant,
                    out string grantReason),
                grantReason);
            Assert.True(
                coordinator.TryTrackLease(
                    fence,
                    lease,
                    out string leaseReason),
                leaseReason);
            using var action = coordinator.RegisterAction(
                ConnectionId,
                lease.LeaseId,
                CancellationToken.None);

            Assert.Equal(
                1,
                coordinator.ActivateDeveloperEnrollment(
                    ClientId,
                    NewReceipt,
                    "developer_enrollment_rotated"));

            Assert.True(oldTerminated);
            Assert.False(otherTerminated);
            Assert.True(action.Token.IsCancellationRequested);
            Assert.Equal(
                CredentialState.Revoked,
                fixture.Credential.State);
            Assert.Equal(
                CredentialState.Active,
                other.State);
            Assert.Equal(
                CF7Launcher.AgentRuntime.Security
                    .ObservationGrantState.Revoked,
                grant.State);
            Assert.Equal(
                WriteLeaseState.Revoked,
                lease.State);
            Assert.False(
                coordinator.IsDispatchAuthorized(
                    ConnectionId,
                    fixture.Credential));
            Assert.True(
                coordinator.IsDispatchAuthorized(
                    OtherConnectionId,
                    other));

            PrincipalCredential lateOld =
                fixture.IssueDeveloperCredential(
                    ClientId,
                    OldReceipt);
            bool lateTerminated = false;
            InvalidOperationException rejected =
                Assert.Throws<InvalidOperationException>(
                    () => coordinator.RegisterConnection(
                        LateConnectionId,
                        lateOld,
                        reason => lateTerminated = true));
            Assert.Equal(
                "developer_enrollment_rotated",
                rejected.Message);
            Assert.True(lateTerminated);
            Assert.Equal(
                CredentialState.Revoked,
                lateOld.State);

            PrincipalCredential replacement =
                fixture.IssueDeveloperCredential(
                    ClientId,
                    NewReceipt);
            coordinator.RegisterConnection(
                ReplacementConnectionId,
                replacement);
            Assert.True(
                coordinator.IsDispatchAuthorized(
                    ReplacementConnectionId,
                    replacement));
        }

        [Fact]
        public void
            ExplicitRevocationBlocksInFlightOldPrincipalUntilReenrollment()
        {
            Fixture fixture = new Fixture();
            using var coordinator =
                new AgentRuntimeRevocationCoordinator(
                    fixture.Credentials,
                    fixture.Grants,
                    fixture.Leases);
            bool terminated = false;
            coordinator.RegisterConnection(
                ConnectionId,
                fixture.Credential,
                reason => terminated = true);

            Assert.Equal(
                1,
                coordinator.RevokeDeveloperEnrollment(
                    ClientId,
                    "developer_enrollment_revoked"));
            Assert.True(terminated);
            Assert.False(
                coordinator.IsDispatchAuthorized(
                    ConnectionId,
                    fixture.Credential));

            PrincipalCredential stale =
                fixture.IssueDeveloperCredential(
                    ClientId,
                    OldReceipt);
            Assert.Throws<InvalidOperationException>(
                () => coordinator.RegisterConnection(
                    LateConnectionId,
                    stale));

            coordinator.ActivateDeveloperEnrollment(
                ClientId,
                NewReceipt,
                "developer_enrollment_rotated");
            PrincipalCredential replacement =
                fixture.IssueDeveloperCredential(
                    ClientId,
                    NewReceipt);
            coordinator.RegisterConnection(
                ReplacementConnectionId,
                replacement);
            Assert.True(
                coordinator.IsDispatchAuthorized(
                    ReplacementConnectionId,
                    replacement));
        }

        [Fact]
        public void DispatchAuthorizationExpiresCredentialInMemory()
        {
            Fixture fixture = new Fixture();
            using var coordinator =
                new AgentRuntimeRevocationCoordinator(
                    fixture.Credentials,
                    fixture.Grants,
                    fixture.Leases);
            coordinator.RegisterConnection(
                ConnectionId,
                fixture.Credential);
            fixture.Clock.Advance(
                TimeSpan.FromHours(2));

            Assert.False(
                coordinator.IsDispatchAuthorized(
                    ConnectionId,
                    fixture.Credential));
            Assert.Equal(
                CredentialState.Expired,
                fixture.Credential.State);
        }

        private sealed class Fixture
        {
            public Fixture()
            {
                Clock = new ManualAgentRuntimeClock();
                Targets = new MutableAgentTargetAuthority();
                Targets.Set(SessionId, TargetId);
                Credentials =
                    new PrincipalCredentialAuthority(
                        Clock,
                        new TestPrincipalEnrollmentVerifier());
                Credential = Credentials.IssueDeveloper(
                    Evidence(ClientId, OldReceipt));
                Grants = new ObservationGrantBroker(
                    Clock,
                    Credentials,
                    Targets);
                Leases = new WriteLeaseBroker(
                    Clock,
                    Credentials,
                    Targets);
            }

            public ManualAgentRuntimeClock Clock { get; }
            public MutableAgentTargetAuthority Targets { get; }
            public PrincipalCredentialAuthority Credentials
            {
                get;
            }
            public PrincipalCredential Credential { get; }
            public ObservationGrantBroker Grants { get; }
            public WriteLeaseBroker Leases { get; }

            public AgentRuntimeRevocationCoordinator
                .SessionFenceTicket CaptureFence(
                    AgentRuntimeRevocationCoordinator coordinator)
            {
                Assert.True(
                    coordinator.TryCaptureSessionFence(
                        ConnectionId,
                        Credential,
                        SessionId,
                        1,
                        out AgentRuntimeRevocationCoordinator
                            .SessionFenceTicket ticket,
                        out string reasonCode),
                    reasonCode);
                return ticket;
            }

            public ObservationGrant IssueObservationGrant()
            {
                return Grants.Issue(
                    new ObservationGrantRequest
                    {
                        CredentialId = Credential.CredentialId,
                        ClientInstanceId = ClientId,
                        SessionId = SessionId,
                        Targets = new[]
                        {
                            new ObservationTargetScope
                            {
                                TargetId = TargetId
                            }
                        },
                        DataScopes = new[] { "pixels" },
                        RequestedLifetime =
                            TimeSpan.FromMinutes(1),
                        AllowEphemeralKeyframes = true
                    });
            }

            public WriteLease IssueLease()
            {
                return Leases.Acquire(
                    new WriteLeaseRequest
                    {
                        CredentialId = Credential.CredentialId,
                        ClientInstanceId = ClientId,
                        SessionId = SessionId,
                        LifecycleGeneration = 1,
                        Kind = WriteLeaseKind.GuiInput,
                        Capabilities = new[]
                        {
                            AgentCapabilitiesV1.Click
                        },
                        TargetScope = new[] { TargetId },
                        RequestedLifetime =
                            TimeSpan.FromSeconds(10),
                        RequestedActionLimit = 1
                });
            }

            public WriteLease IssueShutdownLease()
            {
                Targets.Set(
                    SessionId,
                    TargetId,
                    kind: SurfaceKind.Launcher);
                return Leases.Acquire(
                    new WriteLeaseRequest
                    {
                        CredentialId = Credential.CredentialId,
                        ClientInstanceId = ClientId,
                        SessionId = SessionId,
                        LifecycleGeneration = 1,
                        Kind = WriteLeaseKind.Shutdown,
                        Capabilities = new[]
                        {
                            AgentCapabilitiesV1
                                .SessionShutdown
                        },
                        TargetScope = new[] { TargetId },
                        RequestedLifetime =
                            TimeSpan.FromSeconds(30),
                        RequestedActionLimit = 1
                    });
            }

            public WriteLease IssueStructuredActionLease()
            {
                Targets.Set(
                    SessionId,
                    TargetId,
                    kind: SurfaceKind.Launcher);
                return Leases.Acquire(
                    new WriteLeaseRequest
                    {
                        CredentialId = Credential.CredentialId,
                        ClientInstanceId = ClientId,
                        SessionId = SessionId,
                        LifecycleGeneration = 1,
                        Kind =
                            WriteLeaseKind.StructuredAction,
                        Capabilities = new[]
                        {
                            AgentCapabilitiesV1.PanelOpen
                        },
                        TargetScope = new[] { TargetId },
                        RequestedLifetime =
                            TimeSpan.FromSeconds(30),
                        RequestedActionLimit = 1
                    });
            }

            public PrincipalCredential
                IssueDeveloperCredential(
                    string clientInstanceId,
                    string receipt)
            {
                return Credentials.IssueDeveloper(
                    Evidence(
                        clientInstanceId,
                        receipt));
            }

            private static DeveloperEnrollmentEvidence
                Evidence(
                    string clientInstanceId,
                    string receipt)
            {
                return new DeveloperEnrollmentEvidence
                {
                    ClientInstanceId =
                        clientInstanceId,
                    EnrollmentReceipt = receipt,
                    AllowedCapabilities = new[]
                    {
                        AgentCapabilitiesV1.GetWindow,
                        AgentCapabilitiesV1.Click,
                        AgentCapabilitiesV1.SessionShutdown,
                        AgentCapabilitiesV1.PanelOpen,
                        "observe:pixels"
                    },
                    AllowedTargets =
                        new[] { TargetId },
                    RequestedLifetime =
                        TimeSpan.FromHours(1)
                };
            }
        }

        private sealed class GuardWin32Facade
            : INativeInputWin32Facade
        {
            public HealthyHookSession HookSession { get; } =
                new HealthyHookSession();
            public IReadOnlyCollection<string> HeldControls
            {
                get;
                set;
            } = Array.Empty<string>();
            public int CurrentProcessId => 111;
            public long MonotonicMilliseconds { get; private set; }
                = 1_000;

            public void AdvanceQuiescence()
            {
                MonotonicMilliseconds +=
                    InputSafetyStateMachine
                        .QuiescenceMilliseconds;
            }

            public INativeLowLevelHookSession
                InstallLowLevelHooks(
                    ulong runtimeInjectionTag,
                    Func<NativeLowLevelHookEvent, bool> callback)
            {
                return HookSession;
            }

            public bool IsInteractiveDesktopAvailable()
            {
                return true;
            }

            public IntPtr GetForegroundWindow()
            {
                return new IntPtr(9001);
            }

            public bool TryGetFocusedWindow(
                IntPtr foregroundTopLevelHwnd,
                out IntPtr focusedHwnd)
            {
                focusedHwnd = foregroundTopLevelHwnd;
                return focusedHwnd != IntPtr.Zero;
            }

            public IntPtr WindowFromPoint(
                NativeScreenPoint point)
            {
                return new IntPtr(9001);
            }

            public bool IsSameChildOrOwnedWindow(
                IntPtr targetTopLevelHwnd,
                IntPtr candidateHwnd)
            {
                return targetTopLevelHwnd == candidateHwnd;
            }

            public IReadOnlyCollection<string>
                GetAsyncHeldModifiersAndButtons()
            {
                return HeldControls;
            }

            public bool TryGetProcessIntegrityLevel(
                int processId,
                out int integrityRid)
            {
                integrityRid = 0x2000;
                return true;
            }

            public int SendInput(
                IReadOnlyList<NativeInputPacket> packets,
                ulong runtimeInjectionTag)
            {
                return packets?.Count ?? 0;
            }
        }

        private sealed class HealthyHookSession
            : INativeLowLevelHookSession
        {
            public bool Healthy { get; set; } = true;

            public bool IsHealthy(
                TimeSpan maximumHeartbeatAge)
            {
                return Healthy;
            }

            public bool TryRefresh(TimeSpan timeout)
            {
                return true;
            }

            public void Dispose()
            {
            }
        }

        private const string ConnectionId =
            "connection_aaaaaaaaaaaaaaaa";
        private const string ClientId =
            "client_gateway_aaaaaaaaaaa";
        private const string OtherClientId =
            "client_gateway_bbbbbbbbbbb";
        private const string SessionId =
            "session_gateway_aaaaaaaaaa";
        private const string TargetId =
            "target_gateway_aaaaaaaaaaa";
        private const string OtherConnectionId =
            "connection_bbbbbbbbbbbbbbbb";
        private const string LateConnectionId =
            "connection_cccccccccccccccc";
        private const string ReplacementConnectionId =
            "connection_dddddddddddddddd";
        private const string OldReceipt =
            "receipt_aaaaaaaaaaaaaaaaaaaa";
        private const string OtherReceipt =
            "receipt_bbbbbbbbbbbbbbbbbbbb";
        private const string NewReceipt =
            "receipt_cccccccccccccccccccc";
    }
}
