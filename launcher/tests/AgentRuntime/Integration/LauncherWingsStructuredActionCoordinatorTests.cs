using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.ExceptionServices;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Domain;
using CF7Launcher.AgentRuntime.Gateway;
using CF7Launcher.AgentRuntime.Integration;
using CF7Launcher.AgentRuntime.NativeInput;
using CF7Launcher.AgentRuntime.Security;
using CF7Launcher.AgentRuntime.Sessions;
using CF7Launcher.AgentRuntime.Wings;
using CF7Launcher.Tests.AgentRuntime.Security;
using CF7Launcher.Tests.AgentRuntime.Wings;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.Integration
{
    public sealed class
        LauncherWingsStructuredActionCoordinatorTests
    {
        [Fact]
        public void ProductionCardClosesBeforeExactReauthorization()
        {
            RunSta(() =>
            {
                using var setup = new Setup(
                    authorizeRead: false);
                using var presenter =
                    new LauncherWingsWindowActivationConsentPresenter(
                        setup.Owner,
                        setup.Clock,
                        setup.Controller,
                        setup.RegistryOwner);

                Task<LauncherWingsWindowActivationApproval> pending =
                    presenter.PresentAsync(
                        setup.Proposal(),
                        new LauncherTrustedHumanInteractionTicket(
                            Id("interaction"),
                            LauncherTrustedHumanInteractionPhase
                                .WindowActivationConsent,
                            setup.Owner.Handle.ToInt64()),
                        CancellationToken.None);
                WingsConsentForm form =
                    presenter.ActiveFormForTest;
                Assert.NotNull(form);
                Assert.True(
                    setup.Controller.Snapshot
                        .HumanReauthorizationRequired);
                Assert.Contains(
                    "window.activate",
                    AllControlText(form),
                    StringComparison.Ordinal);
                Assert.Contains(
                    "参数为 {}",
                    AllControlText(form),
                    StringComparison.Ordinal);

                form.AllowButton.PerformClick();
                LauncherWingsWindowActivationApproval approval =
                    AwaitWithMessages(pending);

                Assert.True(approval.Approved);
                Assert.Null(presenter.ActiveFormForTest);
                Assert.False(
                    setup.Controller.Snapshot
                        .HumanReauthorizationRequired);
                Assert.DoesNotContain(
                    setup.Controller.Snapshot.Surfaces,
                    surface => surface.SafetyKind
                        == AgentTargetSafetyKind
                            .HumanOnlySecuritySurface);
            });
        }

        [Fact]
        public void ApprovedActionUsesSeparateExactCredentialAndTrustedReceipt()
        {
            RunSta(() =>
            {
                using var setup = new Setup();
                using LauncherWingsStructuredActionCoordinator
                    coordinator = setup.CreateCoordinator();
                PrincipalCredential loreCredential =
                    setup.ReadAuthority.CredentialForTest;

                LauncherWingsStructuredActionResult result =
                    coordinator
                        .ActivateCurrentGameWindowAsync(
                            CancellationToken.None)
                        .GetAwaiter()
                        .GetResult();

                Assert.True(
                    result.HasTerminalReceipt,
                    result.ReasonCode);
                Assert.NotNull(setup.Presenter.Proposal);
                Assert.Equal(
                    AgentCapabilitiesV1.ActivateWindow,
                    setup.Presenter.Proposal.Operation);
                Assert.Equal(
                    "{}",
                    setup.Presenter.Proposal
                        .CanonicalArguments);
                Assert.Equal(
                    1,
                    setup.Presenter.Proposal.MaximumActions);
                Assert.False(
                    setup.Presenter.Proposal
                        .AllowsPersistence);
                Assert.False(
                    setup.Presenter.Proposal.AllowsExport);

                PrincipalCredential actionCredential =
                    coordinator.ActiveCredentialForTest;
                Assert.NotNull(actionCredential);
                Assert.NotSame(
                    loreCredential,
                    actionCredential);
                Assert.Equal(
                    AgentPrincipalKind.WingsPersona,
                    actionCredential.PrincipalKind);
                Assert.Equal(
                    AgentSessionMode.PlayerAssist,
                    actionCredential.SessionMode);
                Assert.Equal(
                    new[] { Setup.FlashTargetId },
                    actionCredential.AllowedTargets);
                Assert.Equal(
                    new[]
                    {
                        AgentCapabilitiesV1.ActivateWindow,
                        AgentCapabilitiesV1.LeaseAcquire,
                        AgentCapabilitiesV1.LeaseRelease,
                        AgentCapabilitiesV1
                            .ObservationCapture,
                        AgentCapabilitiesV1
                            .ObservationGrantManage,
                        AgentCapabilitiesV1.SessionAttach,
                        AgentCapabilitiesV1.SessionStatus,
                        "observe:pixels"
                    }.OrderBy(value => value),
                    actionCredential.AllowedCapabilities
                        .OrderBy(value => value));
                Assert.DoesNotContain(
                    AgentCapabilitiesV1.Click,
                    actionCredential.AllowedCapabilities);
                Assert.DoesNotContain(
                    AgentCapabilitiesV1.TypeText,
                    actionCredential.AllowedCapabilities);
                Assert.Equal(
                    new[]
                    {
                        AgentCapabilitiesV1.SessionStatus,
                        AgentCapabilitiesV1.SessionAttach,
                        AgentMethodsV1.ObservationGrantIssue,
                        AgentMethodsV1.ObservationCapture,
                        AgentCapabilitiesV1.LeaseAcquire,
                        AgentCapabilitiesV1.ActivateWindow
                    },
                    setup.Dispatcher.Methods);
                Assert.NotNull(setup.Dispatcher.Action);
                Assert.Equal(
                    JsonValueKind.Object,
                    setup.Dispatcher.Action
                        .Arguments.ValueKind);
                Assert.Empty(
                    setup.Dispatcher.Action
                        .Arguments.EnumerateObject());
                Assert.Equal(
                    1,
                    setup.Dispatcher.RequestedActionLimit);
                Assert.True(
                    coordinator.ResultAuthority.TryResolve(
                        result.ActionReceiptId,
                        out TrustedActionResultFacts facts,
                        out string resolveReason),
                    resolveReason);
                Assert.Equal(
                    ActionOutcome.InputDispatched,
                    facts.Outcome);
                Assert.True(setup.Indicators.Last.IsAlive);
                Assert.Equal(
                    CredentialState.Revoked,
                    loreCredential.State);

                coordinator.CompleteResultProjection(
                    result.ActionReceiptId);
                SpinWait.SpinUntil(
                    () => actionCredential.State
                        == CredentialState.Revoked,
                    TimeSpan.FromSeconds(2));
                Assert.Equal(
                    CredentialState.Revoked,
                    actionCredential.State);
                Assert.Equal(
                    CredentialState.Revoked,
                    loreCredential.State);
                Assert.False(
                    coordinator.ResultAuthority.TryResolve(
                        result.ActionReceiptId,
                        out _,
                        out _));
                Assert.False(setup.Indicators.Last.IsAlive);
            });
        }

        [Fact]
        public void UnattendedSessionCannotEnterWingsWriteCoordinator()
        {
            RunSta(() =>
            {
                using var setup = new Setup(
                    authorizeRead: false,
                    sessionMode: SessionMode.UnattendedTest);
                using LauncherWingsStructuredActionCoordinator
                    coordinator = setup.CreateCoordinator();

                LauncherWingsStructuredActionResult result =
                    coordinator
                        .ActivateCurrentGameWindowAsync(
                            CancellationToken.None)
                        .GetAwaiter()
                        .GetResult();

                Assert.False(result.HasTerminalReceipt);
                Assert.Equal(
                    "session_mismatch",
                    result.ReasonCode);
                Assert.Null(setup.Presenter.Proposal);
                Assert.Equal(0, setup.ConnectionCreations);
                Assert.False(coordinator.IsAvailable);
            });
        }

        [Fact]
        public void RealActionCardRetiresLoreCredentialThenUsesSeparateActionPath()
        {
            RunSta(() =>
            {
                using var setup = new Setup();
                PrincipalCredential loreCredential =
                    setup.ReadAuthority.CredentialForTest;
                using var presenter =
                    new LauncherWingsWindowActivationConsentPresenter(
                        setup.Owner,
                        setup.Clock,
                        setup.Controller,
                        setup.RegistryOwner);
                using LauncherWingsStructuredActionCoordinator
                    coordinator =
                        setup.CreateCoordinator(presenter);

                Task<LauncherWingsStructuredActionResult> pending =
                    coordinator.ActivateCurrentGameWindowAsync(
                        CancellationToken.None);
                WingsConsentForm form =
                    presenter.ActiveFormForTest;
                Assert.NotNull(form);
                Assert.Equal(
                    CredentialState.Revoked,
                    loreCredential.State);
                Assert.True(
                    coordinator.IsPresentingOwnConsent);

                form.AllowButton.PerformClick();
                LauncherWingsStructuredActionResult result =
                    AwaitWithMessages(pending);

                Assert.True(
                    result.HasTerminalReceipt,
                    result.ReasonCode);
                Assert.NotSame(
                    loreCredential,
                    coordinator.ActiveCredentialForTest);
                Assert.Equal(
                    CredentialState.Active,
                    coordinator.ActiveCredentialForTest.State);
                coordinator.CompleteResultProjection(
                    result.ActionReceiptId);
            });
        }

        [Fact]
        public void RejectedCardIssuesNoActionCredentialConnectionOrGrant()
        {
            RunSta(() =>
            {
                using var setup = new Setup();
                setup.Presenter.Approve = false;
                using LauncherWingsStructuredActionCoordinator
                    coordinator = setup.CreateCoordinator();
                PrincipalCredential loreCredential =
                    setup.ReadAuthority.CredentialForTest;

                LauncherWingsStructuredActionResult result =
                    coordinator
                        .ActivateCurrentGameWindowAsync(
                            CancellationToken.None)
                        .GetAwaiter()
                        .GetResult();

                Assert.False(result.HasTerminalReceipt);
                Assert.Equal(
                    "consent_required",
                    result.ReasonCode);
                Assert.Equal(0, setup.ConnectionCreations);
                Assert.Empty(setup.Dispatcher.Methods);
                Assert.Null(coordinator.ActiveCredentialForTest);
                Assert.Null(setup.Indicators.Last);
                Assert.Equal(
                    CredentialState.Revoked,
                    loreCredential.State);
            });
        }

        [Fact]
        public void ExternalInputRevokesWholeShortConnectionGrantAndReceipt()
        {
            RunSta(() =>
            {
                using var setup = new Setup();
                setup.Dispatcher.BlockActivation = true;
                using LauncherWingsStructuredActionCoordinator
                    coordinator = setup.CreateCoordinator();
                Task<LauncherWingsStructuredActionResult> pending =
                    coordinator.ActivateCurrentGameWindowAsync(
                        CancellationToken.None);
                Assert.True(
                    setup.Dispatcher.ActivationEntered
                        .Wait(TimeSpan.FromSeconds(2)));
                PrincipalCredential actionCredential =
                    coordinator.ActiveCredentialForTest;
                ObservationGrant actionGrant =
                    setup.Dispatcher.Grant;
                Assert.NotNull(actionCredential);
                Assert.NotNull(actionGrant);
                Assert.True(setup.Indicators.Last.IsAlive);

                setup.ExternalInput.Raise("human_input");
                LauncherWingsStructuredActionResult result =
                    pending.GetAwaiter().GetResult();
                SpinWait.SpinUntil(
                    () => actionCredential.State
                            == CredentialState.Revoked
                        && actionGrant.State
                            == CF7Launcher.AgentRuntime.Security
                                .ObservationGrantState.Revoked,
                    TimeSpan.FromSeconds(2));

                Assert.False(result.HasTerminalReceipt);
                Assert.Equal(
                    CredentialState.Revoked,
                    actionCredential.State);
                Assert.Equal(
                    CF7Launcher.AgentRuntime.Security
                        .ObservationGrantState.Revoked,
                    actionGrant.State);
                Assert.False(setup.Indicators.Last.IsAlive);
                Assert.False(
                    coordinator.ResultAuthority.TryResolve(
                        Id("missingresult"),
                        out _,
                        out _));
            });
        }

        [Fact]
        public void ExternalInputBeforeTerminalRecordFullyRevokesAndCannotProjectReceipt()
        {
            RunSta(() =>
            {
                using var setup = new Setup();
                using LauncherWingsStructuredActionCoordinator
                    coordinator = setup.CreateCoordinator();
                PrincipalCredential credential = null;
                ObservationGrant grant = null;
                string connectionId = null;
                RecordingIndicator indicator = null;
                coordinator.ExecutionStarting += (_, _) =>
                {
                    credential =
                        coordinator.ActiveCredentialForTest;
                    grant = setup.Dispatcher.Grant;
                    connectionId =
                        coordinator.ActiveConnectionIdForTest;
                    indicator = setup.Indicators.Last;
                    setup.ExternalInput.Raise(
                        "human_input",
                        foregroundWindowHandle: 9_090);
                };

                LauncherWingsStructuredActionResult result =
                    coordinator
                        .ActivateCurrentGameWindowAsync(
                            CancellationToken.None)
                        .GetAwaiter()
                        .GetResult();

                Assert.False(result.HasTerminalReceipt);
                Assert.NotNull(credential);
                Assert.NotNull(grant);
                Assert.NotNull(connectionId);
                Assert.NotNull(indicator);
                Assert.Equal(
                    CredentialState.Revoked,
                    credential.State);
                Assert.Equal(
                    CF7Launcher.AgentRuntime.Security
                        .ObservationGrantState.Revoked,
                    grant.State);
                Assert.False(
                    setup.Resources.IsDispatchAuthorized(
                        connectionId,
                        credential));
                Assert.False(indicator.IsAlive);
                Assert.DoesNotContain(
                    AgentCapabilitiesV1.ActivateWindow,
                    setup.Dispatcher.Methods);
                Assert.Equal(
                    0,
                    Assert.IsType<
                        SessionOnlyTrustedWingsActionResultAuthority>(
                        coordinator.ResultAuthority)
                        .CountForTest);
            });
        }

        [Fact]
        public void ExternalInputWhileCancellationIgnoringExecutorIsBlockedImmediatelyFullyRevokesAndRejectsLateReceipt()
        {
            RunSta(() =>
            {
                using var setup = new Setup();
                setup.Dispatcher.BlockActivation = true;
                setup.Dispatcher
                    .IgnoreActivationCancellation = true;
                using LauncherWingsStructuredActionCoordinator
                    coordinator = setup.CreateCoordinator();
                Task<LauncherWingsStructuredActionResult> pending =
                    coordinator.ActivateCurrentGameWindowAsync(
                        CancellationToken.None);
                Assert.True(
                    setup.Dispatcher.ActivationEntered
                        .Wait(TimeSpan.FromSeconds(2)));
                PrincipalCredential credential =
                    coordinator.ActiveCredentialForTest;
                ObservationGrant grant =
                    setup.Dispatcher.Grant;
                string connectionId =
                    coordinator.ActiveConnectionIdForTest;
                RecordingIndicator indicator =
                    setup.Indicators.Last;
                var authority =
                    Assert.IsType<
                        SessionOnlyTrustedWingsActionResultAuthority>(
                        coordinator.ResultAuthority);

                setup.ExternalInput.Raise(
                    "human_input",
                    foregroundWindowHandle: 9_191);

                Assert.False(pending.IsCompleted);
                Assert.Equal(
                    CredentialState.Revoked,
                    credential.State);
                Assert.Equal(
                    CF7Launcher.AgentRuntime.Security
                        .ObservationGrantState.Revoked,
                    grant.State);
                Assert.False(
                    setup.Resources.IsDispatchAuthorized(
                        connectionId,
                        credential));
                Assert.False(indicator.IsAlive);
                Assert.DoesNotContain(
                    setup.Controller.Snapshot.Surfaces,
                    surface => surface.SafetyKind
                        == AgentTargetSafetyKind
                            .HumanOnlySecuritySurface);
                Assert.Equal(0, authority.CountForTest);

                setup.Dispatcher.ReleaseBlockedActivation();
                Assert.True(
                    pending.Wait(TimeSpan.FromSeconds(2)));
                LauncherWingsStructuredActionResult result =
                    pending.GetAwaiter().GetResult();
                Assert.False(result.HasTerminalReceipt);
                Assert.Equal(0, authority.CountForTest);
            });
        }

        [Fact]
        public void ExternalInputBetweenTerminalRecordAndAdoptionPreservesGenericReceipt()
        {
            RunSta(() =>
            {
                using var setup = new Setup();
                using LauncherWingsStructuredActionCoordinator
                    coordinator = setup.CreateCoordinator();
                coordinator
                    .TerminalReceiptRecordedBeforeAdoptionForTest =
                        () => setup.ExternalInput.Raise(
                            "human_input",
                            foregroundWindowHandle: 9191);

                LauncherWingsStructuredActionResult result =
                    coordinator
                        .ActivateCurrentGameWindowAsync(
                            CancellationToken.None)
                        .GetAwaiter()
                        .GetResult();

                Assert.True(
                    result.HasTerminalReceipt,
                    result.ReasonCode);
                Assert.Equal(
                    CredentialState.Revoked,
                    coordinator.ActiveCredentialForTest.State);
                Assert.Equal(
                    CF7Launcher.AgentRuntime.Security
                        .ObservationGrantState.Revoked,
                    setup.Dispatcher.Grant.State);
                Assert.False(setup.Indicators.Last.IsAlive);
                Assert.False(
                    setup.Resources.IsDispatchAuthorized(
                        coordinator.ActiveConnectionIdForTest,
                        coordinator.ActiveCredentialForTest));
                Assert.True(
                    coordinator.ResultAuthority.TryResolve(
                        result.ActionReceiptId,
                        out TrustedActionResultFacts facts,
                        out string reasonCode),
                    reasonCode);
                Assert.Equal(
                    ActionOutcome.InputDispatched,
                    facts.Outcome);
                Assert.Equal(
                    1,
                    Assert.IsType<
                        SessionOnlyTrustedWingsActionResultAuthority>(
                        coordinator.ResultAuthority)
                        .CountForTest);
                coordinator.CompleteResultProjection(
                    result.ActionReceiptId);
            });
        }

        [Fact]
        public void ClosingActionIndicatorRevokesWholeShortConnection()
        {
            RunSta(() =>
            {
                using var setup = new Setup();
                setup.Dispatcher.BlockActivation = true;
                using LauncherWingsStructuredActionCoordinator
                    coordinator = setup.CreateCoordinator();
                Task<LauncherWingsStructuredActionResult> pending =
                    coordinator.ActivateCurrentGameWindowAsync(
                        CancellationToken.None);
                Assert.True(
                    setup.Dispatcher.ActivationEntered
                        .Wait(TimeSpan.FromSeconds(2)));
                PrincipalCredential actionCredential =
                    coordinator.ActiveCredentialForTest;

                setup.Indicators.Last.RevokeByHuman();
                LauncherWingsStructuredActionResult result =
                    pending.GetAwaiter().GetResult();
                SpinWait.SpinUntil(
                    () => actionCredential.State
                        == CredentialState.Revoked,
                    TimeSpan.FromSeconds(2));

                Assert.False(result.HasTerminalReceipt);
                Assert.Equal(
                    CredentialState.Revoked,
                    actionCredential.State);
                Assert.False(setup.Indicators.Last.IsAlive);
            });
        }

        [Fact]
        public void ImmediateRetryStaysBusyUntilRevocationCleanupCompletes()
        {
            RunSta(() =>
            {
                using var setup = new Setup();
                setup.Indicators.BlockDispose = true;
                using LauncherWingsStructuredActionCoordinator
                    coordinator = setup.CreateCoordinator();
                LauncherWingsStructuredActionResult completed =
                    coordinator
                        .ActivateCurrentGameWindowAsync(
                            CancellationToken.None)
                        .GetAwaiter()
                        .GetResult();
                Assert.True(
                    completed.HasTerminalReceipt,
                    completed.ReasonCode);

                _ = Task.Run(
                    () => coordinator.Revoke(
                        "credential_revoked"));
                Assert.True(
                    setup.Indicators.Last.DisposeEntered.Wait(
                        TimeSpan.FromSeconds(2)));
                coordinator.CompleteResultProjection(
                    completed.ActionReceiptId);

                LauncherWingsStructuredActionResult retry =
                    coordinator
                        .ActivateCurrentGameWindowAsync(
                            CancellationToken.None)
                        .GetAwaiter()
                        .GetResult();

                Assert.False(retry.HasTerminalReceipt);
                Assert.Equal("lease_busy", retry.ReasonCode);
                Assert.False(coordinator.IsAvailable);

                setup.Indicators.Last.ReleaseDispose.Set();
                Assert.True(
                    setup.Indicators.Last.DisposeCompleted.Wait(
                        TimeSpan.FromSeconds(2)));
                setup.AuthorizeRead();
                Assert.True(
                    SpinWait.SpinUntil(
                        () => coordinator.IsAvailable,
                        TimeSpan.FromSeconds(2)));
            });
        }

        [Fact]
        public void ChangeHairRunsExactTrustedPromptsAndReturnsCommitReceipt()
        {
            RunSta(() =>
            {
                using var setup = new Setup();
                using LauncherWingsStructuredActionCoordinator
                    coordinator =
                        setup.CreateHairCoordinator();

                LauncherWingsStructuredActionResult result =
                    coordinator.ChangeHairAsync(
                            CancellationToken.None)
                        .GetAwaiter()
                        .GetResult();

                Assert.True(
                    result.HasTerminalReceipt,
                    result.ReasonCode);
                Assert.Equal(
                    1,
                    setup.Dispatcher.HairCommitCount);
                Assert.Equal(
                    1,
                    setup.Dispatcher.HairReconcileCount);
                Assert.Equal(
                    0,
                    setup.Dispatcher.HairRestoreCount);
                Assert.Equal(
                    new[]
                    {
                        LauncherTrustedHumanInteractionPhase
                            .HairPreparationConsent,
                        LauncherTrustedHumanInteractionPhase
                            .HairChooser,
                        LauncherTrustedHumanInteractionPhase
                            .HairCommitConsent,
                        LauncherTrustedHumanInteractionPhase
                            .HairRestoreConsent
                    },
                    setup.HairPresenter.Phases);
                Assert.True(
                    coordinator.ResultAuthority.TryResolve(
                        result.ActionReceiptId,
                        out TrustedActionResultFacts facts,
                        out string reasonCode),
                    reasonCode);
                Assert.Equal(
                    1,
                    Assert.IsType<
                        SessionOnlyTrustedWingsActionResultAuthority>(
                        coordinator.ResultAuthority)
                        .CountForTest);
                Assert.Equal(
                    ActionOutcome.DomainCommitted,
                    facts.Outcome);
                coordinator.CompleteResultProjection(
                    result.ActionReceiptId);
            });
        }

        [Theory]
        [InlineData(HairInteractionFault.ForeignInput)]
        [InlineData(HairInteractionFault.SecondSecuritySurface)]
        public void ChangeHairRejectsForeignInputOrSecondSecuritySurface(
            HairInteractionFault fault)
        {
            RunSta(() =>
            {
                using var setup = new Setup();
                setup.HairPresenter.PreparationFault = fault;
                using LauncherWingsStructuredActionCoordinator
                    coordinator =
                        setup.CreateHairCoordinator();

                LauncherWingsStructuredActionResult result =
                    coordinator.ChangeHairAsync(
                            CancellationToken.None)
                        .GetAwaiter()
                        .GetResult();

                Assert.False(result.HasTerminalReceipt);
                Assert.Equal(
                    0,
                    setup.Dispatcher.HairCommitCount);
            });
        }

        [Theory]
        [InlineData(HairInteractionFault.UnregisteredSurface)]
        [InlineData(HairInteractionFault.SurfaceNotClosed)]
        [InlineData(HairInteractionFault.SurfaceEpochDrift)]
        public void ChangeHairCommitConsentRequiresExactRegisteredClosedSurface(
            HairInteractionFault fault)
        {
            RunSta(() =>
            {
                using var setup = new Setup();
                setup.HairPresenter.CommitFault = fault;
                using LauncherWingsStructuredActionCoordinator
                    coordinator =
                        setup.CreateHairCoordinator();

                LauncherWingsStructuredActionResult result =
                    coordinator.ChangeHairAsync(
                            CancellationToken.None)
                        .GetAwaiter()
                        .GetResult();

                Assert.False(result.HasTerminalReceipt);
                Assert.Equal(
                    0,
                    setup.Dispatcher.HairCommitCount);
            });
        }

        [Fact]
        public void ChangeHairUnknownCommitReconcilesOnceAndUsesRestoreCapabilityOnce()
        {
            RunSta(() =>
            {
                using var setup = new Setup();
                setup.Dispatcher.ReturnUnknownHairCommit = true;
                setup.HairPresenter.ApproveRestore = true;
                using LauncherWingsStructuredActionCoordinator
                    coordinator =
                        setup.CreateHairCoordinator();

                LauncherWingsStructuredActionResult result =
                    coordinator.ChangeHairAsync(
                            CancellationToken.None)
                        .GetAwaiter()
                        .GetResult();

                Assert.True(
                    result.HasTerminalReceipt,
                    result.ReasonCode);
                Assert.Equal(
                    1,
                    setup.Dispatcher.HairCommitCount);
                Assert.Equal(
                    1,
                    setup.Dispatcher.HairReconcileCount);
                Assert.Equal(
                    1,
                    setup.Dispatcher.HairRestoreCount);
                Assert.True(
                    coordinator.ResultAuthority.TryResolve(
                        result.ActionReceiptId,
                        out TrustedActionResultFacts facts,
                        out string reasonCode),
                    reasonCode);
                Assert.Equal(
                    1,
                    Assert.IsType<
                        SessionOnlyTrustedWingsActionResultAuthority>(
                        coordinator.ResultAuthority)
                        .CountForTest);
                Assert.Equal(
                    ActionOutcome.DomainCommitted,
                    facts.Outcome);
                coordinator.CompleteResultProjection(
                    result.ActionReceiptId);
            });
        }

        [Fact]
        public void ExternalInputBetweenHairTerminalRecordAndAdoptionPreservesReceipt()
        {
            RunSta(() =>
            {
                using var setup = new Setup();
                using LauncherWingsStructuredActionCoordinator
                    coordinator =
                        setup.CreateHairCoordinator();
                coordinator
                    .TerminalReceiptRecordedBeforeAdoptionForTest =
                        () => setup.ExternalInput.Raise(
                            "human_input",
                            foregroundWindowHandle: 9292);

                LauncherWingsStructuredActionResult result =
                    coordinator.ChangeHairAsync(
                            CancellationToken.None)
                        .GetAwaiter()
                        .GetResult();

                Assert.True(
                    result.HasTerminalReceipt,
                    result.ReasonCode);
                Assert.Equal(
                    1,
                    setup.Dispatcher.HairCommitCount);
                Assert.Equal(
                    0,
                    setup.Dispatcher.HairReconcileCount);
                Assert.Equal(
                    0,
                    setup.Dispatcher.HairRestoreCount);
                Assert.Equal(
                    CredentialState.Revoked,
                    coordinator.ActiveCredentialForTest.State);
                Assert.Equal(
                    CF7Launcher.AgentRuntime.Security
                        .ObservationGrantState.Revoked,
                    setup.Dispatcher.Grant.State);
                Assert.False(setup.Indicators.Last.IsAlive);
                Assert.False(
                    setup.Resources.IsDispatchAuthorized(
                        coordinator.ActiveConnectionIdForTest,
                        coordinator.ActiveCredentialForTest));
                Assert.True(
                    coordinator.ResultAuthority.TryResolve(
                        result.ActionReceiptId,
                        out TrustedActionResultFacts facts,
                        out string reasonCode),
                    reasonCode);
                Assert.Equal(
                    ActionOutcome.DomainCommitted,
                    facts.Outcome);
                Assert.Equal(
                    1,
                    Assert.IsType<
                        SessionOnlyTrustedWingsActionResultAuthority>(
                        coordinator.ResultAuthority)
                        .CountForTest);
                coordinator.CompleteResultProjection(
                    result.ActionReceiptId);
            });
        }

        [Fact]
        public void PreemptAfterRestoreReceiptAdoptionRetainsOnlyCommitProjection()
        {
            RunSta(() =>
            {
                using var setup = new Setup();
                setup.HairPresenter.ApproveRestore = true;
                using LauncherWingsStructuredActionCoordinator
                    coordinator =
                        setup.CreateHairCoordinator();
                int adoptionCount = 0;
                string commitReceiptId = null;
                coordinator.TerminalReceiptAdoptedForTest =
                    () =>
                    {
                        int current = Interlocked.Increment(
                            ref adoptionCount);
                        if (current == 1)
                        {
                            commitReceiptId =
                                coordinator
                                    .ActiveCommitReceiptIdForTest;
                        }
                        else if (current == 2)
                        {
                            setup.ExternalInput.Raise(
                                "human_input",
                                foregroundWindowHandle:
                                    93_939);
                        }
                    };

                LauncherWingsStructuredActionResult result =
                    coordinator.ChangeHairAsync(
                            CancellationToken.None)
                        .GetAwaiter()
                        .GetResult();

                Assert.True(
                    result.HasTerminalReceipt,
                    result.ReasonCode);
                Assert.Equal(2, adoptionCount);
                Assert.Equal(
                    1,
                    setup.Dispatcher.HairCommitCount);
                Assert.Equal(
                    1,
                    setup.Dispatcher.HairRestoreCount);
                Assert.Equal(
                    commitReceiptId,
                    result.ActionReceiptId);
                var authority =
                    Assert.IsType<
                        SessionOnlyTrustedWingsActionResultAuthority>(
                        coordinator.ResultAuthority);
                Assert.Equal(1, authority.CountForTest);
                Assert.True(
                    authority.TryResolve(
                        result.ActionReceiptId,
                        out TrustedActionResultFacts facts,
                        out string reasonCode),
                    reasonCode);
                Assert.Equal(
                    ActionOutcome.DomainCommitted,
                    facts.Outcome);

                coordinator.CompleteResultProjection(
                    result.ActionReceiptId);
                Assert.Equal(0, authority.CountForTest);
            });
        }

        [Fact]
        public void ForeignInputDuringCancellationIgnoringRestorePromptImmediatelyRevokesLiveAuthorityAndReturnsCommitProjection()
        {
            RunSta(() =>
            {
                using var setup = new Setup();
                setup.HairPresenter
                    .BlockRestoreAndIgnoreCancellation = true;
                setup.HairPresenter.ApproveRestore = true;
                using LauncherWingsStructuredActionCoordinator
                    coordinator =
                        setup.CreateHairCoordinator();

                Task<LauncherWingsStructuredActionResult> pending =
                    coordinator.ChangeHairAsync(
                        CancellationToken.None);
                Assert.True(
                    setup.HairPresenter.RestoreEntered.Wait(
                        TimeSpan.FromSeconds(2)));

                PrincipalCredential credential =
                    coordinator.ActiveCredentialForTest;
                ObservationGrant grant =
                    setup.Dispatcher.Grant;
                string connectionId =
                    coordinator.ActiveConnectionIdForTest;
                Assert.NotNull(credential);
                Assert.NotNull(grant);
                Assert.NotNull(connectionId);
                Assert.True(setup.Indicators.Last.IsAlive);
                Assert.False(
                    pending.IsCompleted,
                    pending.IsCompleted
                        ? pending.GetAwaiter().GetResult()
                            .ReasonCode
                            ?? "unexpected_terminal_projection"
                        : null);
                Assert.True(
                    setup.Controller.Registry
                        .TryGetRegisteredSurface(
                            setup.Controller.SessionId,
                            setup.HairPresenter
                                .BlockedRestoreTargetId,
                            out SessionSurfaceSnapshot
                                blockedSurface));
                Assert.Equal(
                    AgentTargetSafetyKind
                        .HumanOnlySecuritySurface,
                    blockedSurface.SafetyKind);

                setup.ExternalInput.Raise(
                    "human_input",
                    foregroundWindowHandle: 99_999);

                Assert.Equal(
                    CredentialState.Revoked,
                    credential.State);
                Assert.Equal(
                    CF7Launcher.AgentRuntime.Security
                        .ObservationGrantState.Revoked,
                    grant.State);
                Assert.False(
                    setup.Resources.IsDispatchAuthorized(
                        connectionId,
                        credential));
                Assert.False(setup.Indicators.Last.IsAlive);
                Assert.False(
                    setup.Controller.Registry
                        .TryGetRegisteredSurface(
                            setup.Controller.SessionId,
                            setup.HairPresenter
                                .BlockedRestoreTargetId,
                            out _));
                Assert.DoesNotContain(
                    setup.Controller.Snapshot.Surfaces,
                    surface => surface.SafetyKind
                        == AgentTargetSafetyKind
                            .HumanOnlySecuritySurface);
                Assert.Equal(
                    0,
                    setup.Dispatcher.HairRestoreCount);
                Assert.True(
                    pending.Wait(TimeSpan.FromSeconds(2)));

                LauncherWingsStructuredActionResult result =
                    pending.GetAwaiter().GetResult();
                Assert.True(
                    result.HasTerminalReceipt,
                    result.ReasonCode);
                Assert.True(
                    coordinator.ResultAuthority.TryResolve(
                        result.ActionReceiptId,
                        out TrustedActionResultFacts facts,
                        out string reasonCode),
                    reasonCode);
                Assert.Equal(
                    1,
                    Assert.IsType<
                        SessionOnlyTrustedWingsActionResultAuthority>(
                        coordinator.ResultAuthority)
                        .CountForTest);
                Assert.Equal(
                    ActionOutcome.DomainCommitted,
                    facts.Outcome);
                coordinator.CompleteResultProjection(
                    result.ActionReceiptId);
            });
        }

        private static string AllControlText(Control root)
        {
            var values = new List<string>();
            void Visit(Control control)
            {
                if (!string.IsNullOrWhiteSpace(control.Text))
                    values.Add(control.Text);
                foreach (Control child in control.Controls)
                    Visit(child);
            }
            Visit(root);
            return string.Join("\n", values);
        }

        private static T AwaitWithMessages<T>(Task<T> task)
        {
            DateTimeOffset deadline =
                DateTimeOffset.UtcNow.AddSeconds(5);
            while (!task.IsCompleted
                && DateTimeOffset.UtcNow < deadline)
            {
                Application.DoEvents();
                Thread.Sleep(1);
            }
            Assert.True(task.IsCompleted);
            return task.GetAwaiter().GetResult();
        }

        private static void RunSta(Action action)
        {
            Exception failure = null;
            var thread = new Thread(() =>
            {
                try
                {
                    action();
                }
                catch (Exception exception)
                {
                    failure = exception;
                }
            });
            thread.SetApartmentState(ApartmentState.STA);
            thread.Start();
            if (!thread.Join(TimeSpan.FromSeconds(20)))
            {
                throw new TimeoutException(
                    "Wings structured-action STA test timed out.");
            }
            if (failure != null)
                ExceptionDispatchInfo.Capture(failure).Throw();
        }

        private static string Id(string prefix)
        {
            return (prefix
                + "_0123456789abcdefghijklmnop")
                .Substring(0, 32);
        }

        private sealed class Setup : IDisposable
        {
            public const string FlashTargetId =
                "flash_0123456789abcdefghijklmnop";
            private const string LauncherTargetId =
                "launcher_0123456789abcdefghijkl";
            public const string HairTargetId =
                "web_0123456789abcdefghijklmnopqr";
            private readonly string _tempRoot;
            private readonly WingsConsentPresentationPort
                _readConsentPort;
            private readonly AgentRuntimeRevocationCoordinator
                _revocations;

            public Setup(
                bool authorizeRead = true,
                SessionMode sessionMode =
                    SessionMode.DeveloperInteractive)
            {
                Clock = new ManualAgentRuntimeClock();
                Clock.Advance(TimeSpan.FromSeconds(1));
                Owner = new Form
                {
                    ShowInTaskbar = false,
                    StartPosition = FormStartPosition.Manual
                };
                Owner.Show();
                _ = Owner.Handle;
                RegistryOwner =
                    SessionRegistryHostOwner
                        .CaptureCurrentLauncher();
                var registry = new SessionSurfaceRegistry(
                    RegistryOwner,
                    new AcceptingHostValidator());
                Qualification =
                    new RuntimeQualificationRegistration
                    {
                        RuntimeMode =
                            RuntimeMode.FormalRuntime,
                        BuildIdentity = new string('a', 64),
                        PayloadClosure = new string('b', 64),
                        ActualProcessPath =
                            RegistryOwner.LauncherProcess
                                .ExecutablePath
                    };
                Controller = new SessionSurfaceHostController(
                    registry,
                    RegistryOwner,
                    Qualification,
                    new string('c', 64),
                    new[]
                    {
                        AgentCapabilitiesV1.ActivateWindow,
                        AgentCapabilitiesV1
                            .AppearanceHairChange
                    },
                    initialSlot:
                        sessionMode
                                == SessionMode.UnattendedTest
                            ? "cf7_agent_test"
                            : "launcher_idle",
                    sessionMode: sessionMode);
                FlashProcess = new SessionProcessIdentity(
                    Environment.ProcessId + 100,
                    Clock.UtcNow.AddSeconds(1),
                    Path.GetFullPath("FlashPlayer.exe"));
                Controller.SetAttempt(
                    Id("attempt"),
                    FlashProcess,
                    sessionMode
                            == SessionMode.UnattendedTest
                        ? "cf7_agent_test"
                        : "developer_slot",
                    7);
                RegisterSurface(
                    LauncherTargetId,
                    SurfaceKind.Launcher,
                    SessionSurfaceOwnerRelation
                        .LauncherTopLevel,
                    RegistryOwner.LauncherProcess,
                    Owner.Handle.ToInt64(),
                    null,
                    0,
                    includeInput: true);
                RegisterSurface(
                    FlashTargetId,
                    SurfaceKind.Flash,
                    SessionSurfaceOwnerRelation
                        .FlashTopLevel,
                    FlashProcess,
                    Owner.Handle.ToInt64() + 10,
                    null,
                    0,
                    includeInput: true);
                RegisterSurface(
                    HairTargetId,
                    SurfaceKind.WebOverlay,
                    SessionSurfaceOwnerRelation
                        .LauncherOwned,
                    RegistryOwner.LauncherProcess,
                    Owner.Handle.ToInt64() + 20,
                    LauncherTargetId,
                    Owner.Handle.ToInt64(),
                    includeInput: false);
                Controller.SetActivePanel(
                    LauncherWingsStructuredActionCoordinator
                        .HairdresserPanelName,
                    Id("hair-panel"),
                    HairTargetId);

                _tempRoot = Path.Combine(
                    Path.GetTempPath(),
                    "cf7-wings-structured-tests",
                    Guid.NewGuid().ToString("N"));
                Verifier =
                    new HostPrincipalEnrollmentVerifier(
                        new PersistentDeveloperEnrollmentStore(
                            Directory.GetCurrentDirectory(),
                            Clock,
                            _tempRoot));
                Credentials =
                    new PrincipalCredentialAuthority(
                        Clock,
                        Verifier);
                Grants = new ObservationGrantBroker(
                    Clock,
                    Credentials,
                    registry);
                var leases = new WriteLeaseBroker(
                    Clock,
                    Credentials,
                    registry);
                _revocations =
                    new AgentRuntimeRevocationCoordinator(
                        Credentials,
                        Grants,
                        leases);
                Resources =
                    new AgentConnectionResourceAuthority(
                        _revocations,
                        new RejectingUnattendedCredentialBindingAuthority());
                ReadAuthority =
                    new LauncherWingsPlayerAssistAuthority(
                        Owner,
                        Clock,
                        Controller,
                        RegistryOwner,
                        Verifier,
                        Credentials,
                        Grants,
                    HairTargetId,
                        WingsTestFixture.View());
                _readConsentPort =
                    new WingsConsentPresentationPort(
                        Owner,
                        new LauncherHumanOnlySurfacePublisher(
                            Controller,
                            RegistryOwner),
                        ReadAuthority,
                        () => Clock.UtcNow);
                if (authorizeRead)
                    AuthorizeRead();

                Presenter = new RecordingPresenter(
                    Controller,
                    RegistryOwner);
                Indicators = new RecordingIndicatorFactory();
                ExternalInput = new RecordingExternalInput();
                HairPresenter =
                    new RecordingHairPresenter(
                        Controller,
                        RegistryOwner,
                        ExternalInput);
                Dispatcher = new StructuredDispatcher(
                    Clock,
                    Controller,
                    Grants,
                    HairPresenter);
            }

            public ManualAgentRuntimeClock Clock { get; }
            public Form Owner { get; }
            public SessionRegistryHostOwner RegistryOwner { get; }
            public RuntimeQualificationRegistration Qualification
            {
                get;
            }
            public SessionProcessIdentity FlashProcess { get; }
            public SessionSurfaceHostController Controller { get; }
            public HostPrincipalEnrollmentVerifier Verifier { get; }
            public PrincipalCredentialAuthority Credentials
            {
                get;
            }
            public ObservationGrantBroker Grants { get; }
            public AgentConnectionResourceAuthority Resources
            {
                get;
            }
            public LauncherWingsPlayerAssistAuthority ReadAuthority
            {
                get;
            }
            public RecordingPresenter Presenter { get; }
            public RecordingIndicatorFactory Indicators { get; }
            public RecordingExternalInput ExternalInput { get; }
            public RecordingHairPresenter HairPresenter { get; }
            public StructuredDispatcher Dispatcher { get; }
            public int ConnectionCreations { get; private set; }

            public LauncherWingsWindowActivationProposal
                Proposal()
            {
                SessionSnapshot snapshot = Controller.Snapshot;
                return new LauncherWingsWindowActivationProposal(
                    new SessionMutationExpectation
                    {
                        SessionId = snapshot.SessionId,
                        LifecycleGeneration =
                            snapshot.LifecycleGeneration,
                        AttemptId = snapshot.AttemptId,
                        AttemptGeneration =
                            snapshot.AttemptGeneration
                    },
                    snapshot.Slot,
                    WingsTestFixture.View()
                        .Progress.SaveBindingId,
                    WingsTestFixture.View().LoreViewId,
                    FlashTargetId,
                    Clock.UtcNow,
                    Clock.UtcNow.AddMinutes(1));
            }

            public LauncherWingsStructuredActionCoordinator
                CreateCoordinator(
                    IWingsWindowActivationConsentPresenter
                        presenter = null)
            {
                return new LauncherWingsStructuredActionCoordinator(
                    Clock,
                    Controller,
                    ReadAuthority,
                    Verifier,
                    Credentials,
                    Grants,
                    ExternalInput,
                    principal =>
                    {
                        ConnectionCreations++;
                        return new WingsVirtualAuthenticatedConnection(
                            principal,
                            Resources,
                            Dispatcher,
                            Clock);
                    },
                    Controller.SessionId,
                    FlashTargetId,
                    WingsTestFixture.View(),
                    presenter ?? Presenter,
                    Indicators.Create);
            }

            public LauncherWingsStructuredActionCoordinator
                CreateHairCoordinator()
            {
                return new LauncherWingsStructuredActionCoordinator(
                    Clock,
                    Controller,
                    ReadAuthority,
                    Verifier,
                    Credentials,
                    Grants,
                    ExternalInput,
                    principal =>
                    {
                        ConnectionCreations++;
                        return new WingsVirtualAuthenticatedConnection(
                            principal,
                            Resources,
                            Dispatcher,
                            Clock);
                    },
                    Controller.SessionId,
                    FlashTargetId,
                    WingsTestFixture.View(),
                    Presenter,
                    Indicators.Create,
                    hairTargetId: HairTargetId,
                    hairPresenter: HairPresenter,
                    hairIndicatorFactory:
                        Indicators.Create,
                    trustedInteractionOwnerWindowHandle:
                        Owner.Handle.ToInt64());
            }

            public void Dispose()
            {
                Dispatcher.ReleaseBlockedActivation();
                HairPresenter.ReleaseBlockedRestore();
                _readConsentPort.Dispose();
                ReadAuthority.Dispose();
                _revocations.Dispose();
                if (!Owner.IsDisposed)
                {
                    Owner.Close();
                    Owner.Dispose();
                }
                Application.DoEvents();
                if (Directory.Exists(_tempRoot))
                    Directory.Delete(_tempRoot, true);
            }

            public void AuthorizeRead()
            {
                TrustedNeutralConsentPrompt prompt =
                    ReadAuthority.CreatePrompt();
                Assert.True(
                    _readConsentPort.TryPresent(
                        prompt,
                        out string reasonCode),
                    reasonCode);
                _readConsentPort.ActiveFormForTest
                    .AllowButton.PerformClick();
                DateTimeOffset deadline =
                    DateTimeOffset.UtcNow.AddSeconds(3);
                while (ReadAuthority.CredentialForTest == null
                    && DateTimeOffset.UtcNow < deadline)
                {
                    Application.DoEvents();
                    Thread.Sleep(1);
                }
                Assert.NotNull(
                    ReadAuthority.CredentialForTest);
            }

            private void RegisterSurface(
                string targetId,
                SurfaceKind kind,
                SessionSurfaceOwnerRelation relation,
                SessionProcessIdentity process,
                long handle,
                string ownerTargetId,
                long ownerWindowHandle,
                bool includeInput)
            {
                var bounds =
                    new SessionPhysicalRect(
                        10,
                        20,
                        800,
                        600);
                Controller.SynchronizeSurface(
                    new SessionSurfaceHostRegistration
                    {
                        TargetId = targetId,
                        Kind = kind,
                        SafetyKind =
                            AgentTargetSafetyKind.RuntimeOwned,
                        OwnerRelation = relation,
                        OwnerProcess = process,
                        WindowHandle = handle,
                        OwnerTargetId = ownerTargetId,
                        OwnerWindowHandle =
                            ownerWindowHandle,
                        BoundsPhysical = bounds,
                        ClientRectPhysical = bounds,
                        ContentRectPhysical = bounds,
                        Dpi = 96,
                        ZIndex = 10,
                        Visible = true,
                        ObservationModes = new[]
                        {
                            ObservationMode
                                .WindowGraphicsCapture
                        },
                        InputModes = kind
                                == SurfaceKind.WebOverlay
                            ? new[]
                            {
                                InputMode.DomainTransaction
                            }
                            : includeInput
                                ? new[]
                            {
                                InputMode.SendInputGuarded
                            }
                                : Array.Empty<InputMode>()
                    });
            }
        }

        private sealed class RecordingPresenter
            : IWingsWindowActivationConsentPresenter
        {
            private readonly SessionSurfaceHostController
                _controller;
            private readonly LauncherHumanOnlySurfacePublisher
                _publisher;

            internal RecordingPresenter(
                SessionSurfaceHostController controller,
                SessionRegistryHostOwner registryOwner)
            {
                _controller = controller;
                _publisher =
                    new LauncherHumanOnlySurfacePublisher(
                        controller,
                        registryOwner);
            }

            public bool Approve { get; set; } = true;
            public LauncherWingsWindowActivationProposal Proposal
            {
                get;
                private set;
            }

            public Task<LauncherWingsWindowActivationApproval>
                PresentAsync(
                    LauncherWingsWindowActivationProposal proposal,
                    LauncherTrustedHumanInteractionTicket interaction,
                    CancellationToken cancellationToken)
            {
                Proposal = proposal;
                const long interactionWindow = 4242;
                var descriptor =
                    new WingsHumanOnlySurfaceDescriptor(
                        Id("interaction-target"),
                        interactionWindow,
                        interaction.OwnerWindowHandle,
                        new System.Drawing.Rectangle(
                            0,
                            0,
                            100,
                            100),
                        new System.Drawing.Rectangle(
                            0,
                            0,
                            100,
                            100),
                        96);
                Assert.True(
                    interaction.TryBindSecuritySurface(
                        descriptor,
                        out _));
                Assert.True(
                    _publisher.TryPublish(
                        descriptor,
                        out IWingsHumanOnlySurfaceLease lease,
                        out string publishReason),
                    publishReason);
                Assert.NotNull(lease);
                Assert.True(
                    interaction.TryConfirmPublishedSurface(
                        lease.TargetId,
                        lease.WindowHandle,
                        lease.OwnerWindowHandle,
                        lease.SurfaceEpoch,
                        out string confirmReason),
                    confirmReason);
                interaction.MarkClosed(interactionWindow);
                lease.Dispose();
                SessionSnapshot snapshot =
                    _controller.Snapshot;
                Assert.True(
                    _publisher
                        .TryAcknowledgeHumanReauthorization(
                            new SessionMutationExpectation
                            {
                                SessionId =
                                    snapshot.SessionId,
                                LifecycleGeneration =
                                    snapshot
                                        .LifecycleGeneration,
                                AttemptId =
                                    snapshot.AttemptId,
                                AttemptGeneration =
                                    snapshot
                                        .AttemptGeneration
                            },
                            out string acknowledgeReason),
                    acknowledgeReason);
                return Task.FromResult(
                    Approve
                        ? LauncherWingsWindowActivationApproval
                            .AllowAfterClose(
                                Id("human"),
                                Id("reauthorize"))
                        : LauncherWingsWindowActivationApproval
                            .Reject("consent_required"));
            }
        }

        public enum HairInteractionFault
        {
            None,
            ForeignInput,
            SecondSecuritySurface,
            UnregisteredSurface,
            SurfaceNotClosed,
            SurfaceEpochDrift
        }

        private sealed class RecordingHairPresenter
            : ILauncherWingsHairInteractionPresenter
        {
            private readonly SessionSurfaceHostController
                _controller;
            private readonly LauncherHumanOnlySurfacePublisher
                _publisher;
            private readonly RecordingExternalInput
                _externalInput;
            private int _surfaceSequence;

            internal RecordingHairPresenter(
                SessionSurfaceHostController controller,
                SessionRegistryHostOwner registryOwner,
                RecordingExternalInput externalInput)
            {
                _controller = controller;
                _publisher =
                    new LauncherHumanOnlySurfacePublisher(
                        controller,
                        registryOwner);
                _externalInput = externalInput;
            }

            internal HairInteractionFault PreparationFault
            {
                get;
                set;
            }

            internal HairInteractionFault CommitFault
            {
                get;
                set;
            }

            internal HairInteractionFault RestoreFault
            {
                get;
                set;
            }

            internal bool ApproveRestore { get; set; }
            internal bool BlockRestoreAndIgnoreCancellation
            {
                get;
                set;
            }
            internal ManualResetEventSlim RestoreEntered
            {
                get;
            } = new ManualResetEventSlim(false);
            private readonly TaskCompletionSource<
                LauncherWingsHairSecurityApproval>
                    _blockedRestore =
                        new TaskCompletionSource<
                            LauncherWingsHairSecurityApproval>(
                            TaskCreationOptions
                                .RunContinuationsAsynchronously);
            private IWingsHumanOnlySurfaceLease
                _blockedRestoreLease;
            internal string BlockedRestoreTargetId
            {
                get;
                private set;
            }

            internal List<
                LauncherTrustedHumanInteractionPhase> Phases
            {
                get;
            } = new();

            public Task<LauncherWingsHairSecurityApproval>
                PresentPreparationAsync(
                    LauncherWingsHairPreparationProposal proposal,
                    LauncherTrustedHumanInteractionTicket interaction,
                    CancellationToken cancellationToken)
            {
                cancellationToken.ThrowIfCancellationRequested();
                CompleteSecurityInteraction(
                    interaction,
                    PreparationFault);
                return Task.FromResult(
                    LauncherWingsHairSecurityApproval.Allow(
                        Id("hair-preparation-human"),
                        Id("hair-preparation-reauth")));
            }

            public Task<LauncherWingsHairChooserSelection>
                ChooseAsync(
                    LauncherWingsHairChooserCard card,
                    LauncherTrustedHumanInteractionTicket interaction,
                    CancellationToken cancellationToken)
            {
                cancellationToken.ThrowIfCancellationRequested();
                Phases.Add(interaction.Phase);
                long windowHandle =
                    50_000 + Interlocked.Increment(
                        ref _surfaceSequence);
                Assert.True(
                    interaction.TryBindChooserWindow(
                        card.ChooserId,
                        windowHandle,
                        interaction.OwnerWindowHandle,
                        out string reasonCode),
                    reasonCode);
                interaction.MarkClosed(windowHandle);
                LauncherWingsHairChoice selected =
                    card.Choices.First(choice =>
                        !choice.IsCurrent);
                return Task.FromResult(
                    LauncherWingsHairChooserSelection.Select(
                        card.ChooserId,
                        selected.Identifier));
            }

            public Task<LauncherWingsHairSecurityApproval>
                PresentRestoreAsync(
                    LauncherWingsHairRestoreProposal proposal,
                    LauncherTrustedHumanInteractionTicket interaction,
                    CancellationToken cancellationToken)
            {
                if (BlockRestoreAndIgnoreCancellation)
                {
                    BeginBlockedRestoreInteraction(
                        interaction);
                    RestoreEntered.Set();
                    return _blockedRestore.Task;
                }
                cancellationToken.ThrowIfCancellationRequested();
                CompleteSecurityInteraction(
                    interaction,
                    RestoreFault);
                return Task.FromResult(
                    ApproveRestore
                        ? LauncherWingsHairSecurityApproval.Allow(
                            Id("hair-restore-human"),
                            Id("hair-restore-reauth"))
                        : LauncherWingsHairSecurityApproval.Reject());
            }

            internal void ReleaseBlockedRestore()
            {
                _blockedRestoreLease?.Dispose();
                _blockedRestoreLease = null;
                _blockedRestore.TrySetResult(
                    LauncherWingsHairSecurityApproval
                        .Reject());
            }

            internal void CompleteCommitConsent(
                LauncherTrustedHumanInteractionTicket interaction)
            {
                CompleteSecurityInteraction(
                    interaction,
                    CommitFault);
            }

            private void CompleteSecurityInteraction(
                LauncherTrustedHumanInteractionTicket interaction,
                HairInteractionFault fault)
            {
                Phases.Add(interaction.Phase);
                int ordinal = Interlocked.Increment(
                    ref _surfaceSequence);
                long windowHandle = 60_000 + ordinal;
                var descriptor =
                    new WingsHumanOnlySurfaceDescriptor(
                        Id("hair-security-" + ordinal),
                        windowHandle,
                        interaction.OwnerWindowHandle,
                        new System.Drawing.Rectangle(
                            0,
                            0,
                            120,
                            80),
                        new System.Drawing.Rectangle(
                            0,
                            0,
                            120,
                            80),
                        96);
                Assert.True(
                    interaction.TryBindSecuritySurface(
                        descriptor,
                        out string bindReason),
                    bindReason);

                if (fault
                    == HairInteractionFault.UnregisteredSurface)
                {
                    Assert.True(
                        interaction.TryConfirmPublishedSurface(
                            descriptor.TargetId,
                            descriptor.WindowHandle,
                            descriptor.OwnerWindowHandle,
                            999,
                            out string spoofReason),
                        spoofReason);
                    interaction.MarkClosed(windowHandle);
                    return;
                }

                Assert.True(
                    _publisher.TryPublish(
                        descriptor,
                        out IWingsHumanOnlySurfaceLease lease,
                        out string publishReason),
                    publishReason);
                Assert.NotNull(lease);
                ulong confirmedEpoch =
                    fault
                        == HairInteractionFault
                            .SurfaceEpochDrift
                        ? lease.SurfaceEpoch + 1
                        : lease.SurfaceEpoch;
                Assert.True(
                    interaction.TryConfirmPublishedSurface(
                        lease.TargetId,
                        lease.WindowHandle,
                        lease.OwnerWindowHandle,
                        confirmedEpoch,
                        out string confirmReason),
                    confirmReason);

                IWingsHumanOnlySurfaceLease secondLease = null;
                if (fault
                    == HairInteractionFault.ForeignInput)
                {
                    _externalInput.Raise(
                        "human_input",
                        foregroundWindowHandle:
                            windowHandle + 99);
                }
                else if (fault
                    == HairInteractionFault
                        .SecondSecuritySurface)
                {
                    var second =
                        new WingsHumanOnlySurfaceDescriptor(
                            Id("hair-security-second-" + ordinal),
                            windowHandle + 1,
                            interaction.OwnerWindowHandle,
                            new System.Drawing.Rectangle(
                                0,
                                0,
                                90,
                                70),
                            new System.Drawing.Rectangle(
                                0,
                                0,
                                90,
                                70),
                            96);
                    Assert.True(
                        _publisher.TryPublish(
                            second,
                            out secondLease,
                            out string secondReason),
                        secondReason);
                }

                if (fault
                    != HairInteractionFault.SurfaceNotClosed)
                {
                    interaction.MarkClosed(windowHandle);
                }
                secondLease?.Dispose();
                lease.Dispose();
                SessionSnapshot snapshot =
                    _controller.Snapshot;
                if (snapshot.HumanReauthorizationRequired)
                {
                    _publisher.TryAcknowledgeHumanReauthorization(
                        new SessionMutationExpectation
                        {
                            SessionId = snapshot.SessionId,
                            LifecycleGeneration =
                                snapshot.LifecycleGeneration,
                            AttemptId = snapshot.AttemptId,
                            AttemptGeneration =
                                snapshot.AttemptGeneration
                        },
                        out _);
                }
            }

            private void BeginBlockedRestoreInteraction(
                LauncherTrustedHumanInteractionTicket interaction)
            {
                Phases.Add(interaction.Phase);
                int ordinal = Interlocked.Increment(
                    ref _surfaceSequence);
                long windowHandle = 70_000 + ordinal;
                var descriptor =
                    new WingsHumanOnlySurfaceDescriptor(
                        Id("hair-blocked-restore-" + ordinal),
                        windowHandle,
                        interaction.OwnerWindowHandle,
                        new System.Drawing.Rectangle(
                            0,
                            0,
                            120,
                            80),
                        new System.Drawing.Rectangle(
                            0,
                            0,
                            120,
                            80),
                        96);
                Assert.True(
                    interaction.TryBindSecuritySurface(
                        descriptor,
                        out string bindReason),
                    bindReason);
                Assert.True(
                    _publisher.TryPublish(
                        descriptor,
                        out _blockedRestoreLease,
                        out string publishReason),
                    publishReason);
                Assert.NotNull(_blockedRestoreLease);
                BlockedRestoreTargetId =
                    _blockedRestoreLease.TargetId;
                Assert.True(
                    interaction.TryConfirmPublishedSurface(
                        _blockedRestoreLease.TargetId,
                        _blockedRestoreLease.WindowHandle,
                        _blockedRestoreLease.OwnerWindowHandle,
                        _blockedRestoreLease.SurfaceEpoch,
                        out string confirmReason),
                    confirmReason);
                IWingsHumanOnlySurfaceLease exactLease =
                    _blockedRestoreLease;
                Assert.True(
                    interaction.TryRegisterRevocation(
                        () => exactLease.Dispose()));
            }
        }

        private sealed class RecordingIndicatorFactory
        {
            public RecordingIndicator Last { get; private set; }
            public bool BlockDispose { get; set; }

            public IWingsStructuredActionIndicator Create()
            {
                Last = new RecordingIndicator(
                    BlockDispose);
                return Last;
            }
        }

        private sealed class RecordingIndicator
            : IWingsStructuredActionIndicator
        {
            private Action _revoked;
            private readonly bool _blockDispose;

            internal RecordingIndicator(bool blockDispose)
            {
                _blockDispose = blockDispose;
            }

            public bool IsAlive { get; private set; }
            internal ManualResetEventSlim DisposeEntered
            {
                get;
            } = new ManualResetEventSlim(false);
            internal ManualResetEventSlim ReleaseDispose
            {
                get;
            } = new ManualResetEventSlim(false);
            internal ManualResetEventSlim DisposeCompleted
            {
                get;
            } = new ManualResetEventSlim(false);

            public bool TryShow(
                DateTimeOffset expiresAtUtc,
                TimeSpan lifetime,
                Action revoked)
            {
                _revoked = revoked;
                IsAlive = true;
                return true;
            }

            public void RevokeByHuman()
            {
                if (!IsAlive)
                    return;
                IsAlive = false;
                Action revoked = _revoked;
                _revoked = null;
                revoked?.Invoke();
            }

            public void Close()
            {
                IsAlive = false;
                _revoked = null;
            }

            public void Dispose()
            {
                Close();
                if (_blockDispose)
                {
                    DisposeEntered.Set();
                    ReleaseDispose.Wait(
                        TimeSpan.FromSeconds(5));
                }
                DisposeCompleted.Set();
            }
        }

        private sealed class RecordingExternalInput
            : IExternalInputObservationSource
        {
            private long _sequence;

            public event Action<ExternalInputObservation>
                ExternalInputObserved;

            public long ObservedExternalInputSequence =>
                Interlocked.Read(ref _sequence);

            public long ForegroundWindowHandle { get; set; }

            public bool IsExactForegroundWindow(
                long windowHandle)
            {
                return windowHandle != 0
                    && (ForegroundWindowHandle == 0
                        || windowHandle
                            == ForegroundWindowHandle);
            }

            public void Raise(
                string reasonCode,
                long foregroundWindowHandle = 0,
                NativeControlTransition transition =
                    NativeControlTransition.None)
            {
                ExternalInputObserved?.Invoke(
                    new ExternalInputObservation(
                        Interlocked.Increment(
                            ref _sequence),
                        reasonCode,
                        foregroundWindowHandle,
                        null,
                        transition));
            }

            public Task<long>
                SealTrustedHumanInteractionAsync(
                    CancellationToken cancellationToken)
            {
                cancellationToken
                    .ThrowIfCancellationRequested();
                return Task.FromResult(
                    Interlocked.Read(ref _sequence));
            }
        }

        private sealed class StructuredDispatcher
            : IAgentRuntimeMethodDispatcher
        {
            private const string CurrentHair =
                "hair-current";
            private const string SelectedHair =
                "hair-selected";
            private readonly ManualAgentRuntimeClock _clock;
            private readonly SessionSurfaceHostController
                _controller;
            private readonly ObservationGrantBroker _grants;
            private readonly RecordingHairPresenter
                _hairPresenter;
            private readonly TaskCompletionSource<bool>
                _activationGate =
                    new TaskCompletionSource<bool>(
                        TaskCreationOptions
                            .RunContinuationsAsynchronously);

            public StructuredDispatcher(
                ManualAgentRuntimeClock clock,
                SessionSurfaceHostController controller,
                ObservationGrantBroker grants,
                RecordingHairPresenter hairPresenter)
            {
                _clock = clock;
                _controller = controller;
                _grants = grants;
                _hairPresenter = hairPresenter;
            }

            public List<string> Methods { get; } = new();
            public bool BlockActivation { get; set; }
            public bool IgnoreActivationCancellation
            {
                get;
                set;
            }
            public ManualResetEventSlim ActivationEntered
            {
                get;
            } = new ManualResetEventSlim(false);
            public ObservationGrant Grant { get; private set; }
            public ActionEnvelope Action { get; private set; }
            public int RequestedActionLimit { get; private set; }
            public bool ReturnUnknownHairCommit { get; set; }
            public int HairCommitCount { get; private set; }
            public int HairRestoreCount { get; private set; }
            public int HairReconcileCount { get; private set; }
            public string HairTransactionId { get; private set; }
            public string HairPreviewHash { get; private set; }
            public string HairRestoreToken { get; private set; }

            public void ReleaseBlockedActivation()
            {
                _activationGate.TrySetResult(true);
            }

            public async Task<AgentRuntimeDispatchResult>
                DispatchAsync(
                    AgentRuntimeDispatchContext context,
                    AgentJsonRpcRequest request,
                    CancellationToken cancellationToken)
            {
                Methods.Add(request.Method);
                if (request.Method
                    == AgentCapabilitiesV1.SessionStatus)
                {
                    return AgentRuntimeDispatchResult.Completed(
                        new MinimalSessionReference
                        {
                            ProjectRunning = true,
                            QualificationState =
                                RuntimeQualificationState
                                    .Verified,
                            LifecycleRef = Id("lifecycle")
                        });
                }
                if (request.Method
                    == AgentCapabilitiesV1.SessionAttach)
                {
                    return AgentRuntimeDispatchResult.Completed(
                        new { attached = true });
                }
                if (request.Method
                    == AgentMethodsV1.ObservationGrantIssue)
                {
                    ObservationGrantIssueParametersV1 parameters =
                        request.Params.Deserialize<
                            ObservationGrantIssueParametersV1>(
                            AgentProtocolV1.JsonOptions);
                    Grant = _grants.Issue(
                        new ObservationGrantRequest
                        {
                            CredentialId =
                                context.Principal
                                    .CredentialId,
                            ClientInstanceId =
                                context.Principal
                                    .ClientInstanceId,
                            SessionId =
                                _controller.SessionId,
                            Targets = parameters.TargetIds
                                .Select(target =>
                                    new ObservationTargetScope
                                    {
                                        TargetId = target
                                    })
                                .ToArray(),
                            DataScopes =
                                parameters.DataScopes,
                            RequestedLifetime =
                                TimeSpan.FromMilliseconds(
                                    parameters
                                        .RequestedTtlMs),
                            ConsentReceipt =
                                parameters.ConsentReceipt,
                            AllowEphemeralKeyframes =
                                parameters
                                    .AllowEphemeralKeyframes,
                            AllowPersistence =
                                parameters.AllowPersistence,
                            AllowExport =
                                parameters.AllowExport
                        });
                    return AgentRuntimeDispatchResult.Completed(
                        GrantContract(
                            Grant,
                            _controller.Snapshot));
                }
                if (request.Method
                    == AgentMethodsV1.ObservationCapture)
                {
                    ObservationCaptureParametersV1 parameters =
                        request.Params.Deserialize<
                            ObservationCaptureParametersV1>(
                            AgentProtocolV1.JsonOptions);
                    return AgentRuntimeDispatchResult.Completed(
                        Observation(parameters.TargetId));
                }
                if (request.Method
                    == AgentMethodsV1.HairInspect)
                {
                    return AgentRuntimeDispatchResult.Completed(
                        HairInspectContract());
                }
                if (request.Method
                    == AgentMethodsV1.HairPreview)
                {
                    HairPreviewParametersV1 parameters =
                        request.Params.Deserialize<
                            HairPreviewParametersV1>(
                            AgentProtocolV1.JsonOptions);
                    return AgentRuntimeDispatchResult.Completed(
                        HairPreviewContract(parameters));
                }
                if (request.Method
                    == AgentMethodsV1.HairConsent)
                {
                    HairConsentParametersV1 parameters =
                        request.Params.Deserialize<
                            HairConsentParametersV1>(
                            AgentProtocolV1.JsonOptions);
                    LauncherTrustedHumanInteractionTicket
                        interaction =
                            LauncherTrustedHumanInteractionContext
                                .Current;
                    Assert.NotNull(interaction);
                    _hairPresenter.CompleteCommitConsent(
                        interaction);
                    return AgentRuntimeDispatchResult.Completed(
                        new HairConsentDescriptorV1
                        {
                            ConsentToken =
                                Id("hair-consent-token"),
                            ConsentReceipt =
                                Id("hair-consent-receipt"),
                            TransactionId =
                                parameters.TransactionId,
                            PreviewHash =
                                parameters.PreviewHash,
                            ExpiresInMs = 30_000
                        });
                }
                if (request.Method
                    == AgentMethodsV1.HairReconcile)
                {
                    HairReconcileCount++;
                    return AgentRuntimeDispatchResult.Completed(
                        new
                        {
                            outcome =
                                HairTransactionOutcome
                                    .DomainCommitted,
                            reasonCode = (string)null,
                            reconcileKind = (string)null,
                            transactionId =
                                HairTransactionId,
                            previewHash =
                                HairPreviewHash,
                            authoritativeInspect =
                                (object)null,
                            restoreToken =
                                HairRestoreToken,
                            restoreExpiresAtUtc =
                                _clock.UtcNow
                                    .AddMinutes(2)
                        });
                }
                if (request.Method
                    == AgentCapabilitiesV1.LeaseAcquire)
                {
                    LeaseAcquireParametersV1 parameters =
                        request.Params.Deserialize<
                            LeaseAcquireParametersV1>(
                            AgentProtocolV1.JsonOptions);
                    RequestedActionLimit =
                        parameters.RequestedActionLimit;
                    ulong now = checked(
                        (ulong)_clock
                            .MonotonicMilliseconds);
                    SessionSnapshot session =
                        _controller.Snapshot;
                    return AgentRuntimeDispatchResult.Completed(
                        new LeaseDescriptor
                        {
                            LeaseId = Id("lease"),
                            OwnerClientId =
                                context.Principal
                                    .ClientInstanceId,
                            SecurityPrincipalId =
                                context.Principal
                                    .SecurityPrincipalId,
                            SessionMode =
                                SessionMode.PlayerAssist,
                            Purpose = string.Equals(
                                    parameters.Kind,
                                    "domain_transaction",
                                    StringComparison.Ordinal)
                                ? LeasePurpose
                                    .DomainTransaction
                                : LeasePurpose.GuiInput,
                            Scope =
                                new LeaseScopeDescriptor
                                {
                                    Session =
                                        new SessionScopeDescriptor
                                        {
                                            SessionId =
                                                session.SessionId,
                                            LifecycleGeneration =
                                                session
                                                    .LifecycleGeneration,
                                            AttemptId =
                                                session.AttemptId,
                                            AttemptGeneration =
                                                session
                                                    .AttemptGeneration,
                                            CrossAttempt = false
                                        },
                                    TargetScope =
                                        parameters.TargetScope,
                                    OperationScope =
                                        parameters.Capabilities,
                                    MaximumActions =
                                        parameters
                                            .RequestedActionLimit,
                                    ArgumentBoundsHash =
                                        parameters
                                            .ArgumentBoundsHash
                                },
                            Capabilities =
                                parameters.Capabilities,
                            IssuedMonotonic = now,
                            ExpiresMonotonic =
                                now + 10_000,
                            RenewAfter = now + 5_000,
                            ConsentReceipt =
                                parameters.ConsentReceipt,
                            HumanOverridePolicy =
                                HumanOverridePolicy
                                    .AlwaysPreempt,
                            State = LeaseState.Active
                        });
                }
                if (request.Method
                    == AgentCapabilitiesV1.LeaseRelease)
                {
                    return AgentRuntimeDispatchResult.Completed(
                        new { released = true });
                }
                if (request.Method
                    == AgentCapabilitiesV1.ActivateWindow)
                {
                    ActivationEntered.Set();
                    if (BlockActivation)
                    {
                        if (IgnoreActivationCancellation)
                        {
                            await _activationGate.Task
                                .ConfigureAwait(false);
                        }
                        else
                        {
                            await _activationGate.Task
                                .WaitAsync(cancellationToken);
                        }
                    }
                    Action = request.Params
                        .Deserialize<ActionEnvelope>(
                            AgentProtocolV1.JsonOptions);
                    return AgentRuntimeDispatchResult.Completed(
                        new ActionReceipt
                        {
                            ActionId = Action.ActionId,
                            AuditSequence = 1,
                            Terminal = true,
                            Outcome =
                                ActionOutcome.InputDispatched,
                            EvidenceKind =
                                EvidenceKind.BrokerDispatch,
                            ReasonCode = "none",
                            ReconcileKind =
                                ReconcileKind.None,
                            Retryable = false,
                            ActualTargetId =
                                Action.TargetId,
                            FocusVerified = true,
                            BeforeObservationId =
                                Action.ObservationId,
                            LeaseState =
                                LeaseState.Consumed
                        });
                }
                if (request.Method
                        == AgentMethodsV1.HairCommit
                    || request.Method
                        == AgentMethodsV1.HairRestore)
                {
                    Action = request.Params
                        .Deserialize<ActionEnvelope>(
                            AgentProtocolV1.JsonOptions);
                    bool restore = request.Method
                        == AgentMethodsV1.HairRestore;
                    if (restore)
                        HairRestoreCount++;
                    else
                        HairCommitCount++;
                    ActionOutcome outcome =
                        !restore && ReturnUnknownHairCommit
                            ? ActionOutcome.Unknown
                            : ActionOutcome
                                .DomainCommitted;
                    return AgentRuntimeDispatchResult.Completed(
                        new ActionReceipt
                        {
                            ActionId = Action.ActionId,
                            AuditSequence =
                                checked((ulong)
                                    (HairCommitCount
                                        + HairRestoreCount)),
                            Terminal = true,
                            Outcome = outcome,
                            EvidenceKind =
                                outcome
                                    == ActionOutcome.Unknown
                                ? EvidenceKind
                                    .ReconciliationRequired
                                : EvidenceKind.DomainAck,
                            ReasonCode =
                                outcome
                                    == ActionOutcome.Unknown
                                ? "domain_commit_unknown"
                                : "none",
                            ReconcileKind =
                                outcome
                                    == ActionOutcome.Unknown
                                ? ReconcileKind
                                    .DomainAuthoritative
                                : ReconcileKind.None,
                            Retryable = false,
                            ActualTargetId =
                                outcome
                                    == ActionOutcome
                                        .DomainCommitted
                                ? Action.TargetId
                                : null,
                            FocusVerified = false,
                            BeforeObservationId =
                                Action.ObservationId,
                            LeaseState =
                                LeaseState.Consumed,
                            DomainResult =
                                outcome
                                    == ActionOutcome
                                        .DomainCommitted
                                ? new HairDomainActionResult
                                {
                                    TransactionId =
                                        HairTransactionId,
                                    PreviewHash =
                                        HairPreviewHash,
                                    RestoreToken =
                                        restore
                                            ? null
                                            : HairRestoreToken,
                                    RestoreExpiresAtUtc =
                                        restore
                                            ? null
                                            : _clock.UtcNow
                                                .AddMinutes(2)
                                }
                                : null
                        });
                }
                return AgentRuntimeDispatchResult.Rejected(
                    "method_not_found");
            }

            private object HairInspectContract()
            {
                HairSaveBinding binding = HairBinding();
                var snapshot =
                    new HairAuthoritativeSnapshot(
                        binding,
                        7,
                        3,
                        CurrentHair,
                        new[]
                        {
                            new HairCatalogEntry(
                                CurrentHair,
                                "Current hair"),
                            new HairCatalogEntry(
                                SelectedHair,
                                "Selected hair")
                        });
                string snapshotHash =
                    HairAppearanceHashing
                        .ComputeSnapshotHash(snapshot);
                return new
                {
                    success = true,
                    reasonCode = (string)null,
                    snapshot = new
                    {
                        binding =
                            HairBindingContract(binding),
                        revision = snapshot.Revision,
                        generation = snapshot.Generation,
                        currentHair =
                            snapshot.CurrentHair,
                        catalog = snapshot.Catalog.Select(
                            entry => new
                            {
                                identifier =
                                    entry.Identifier,
                                displayName =
                                    entry.DisplayName
                            }).ToArray()
                    },
                    snapshotHash
                };
            }

            private object HairPreviewContract(
                HairPreviewParametersV1 parameters)
            {
                HairSaveBinding binding = HairBinding();
                HairTransactionId =
                    Id("hair-transaction");
                HairPreviewHash =
                    HairAppearanceHashing
                        .ComputePreviewHash(
                            HairTransactionId,
                            binding,
                            CurrentHair,
                            parameters.HairIdentifier,
                            parameters.ExpectedRevision,
                            parameters.ExpectedGeneration,
                            parameters
                                .ExpectedSnapshotHash);
                HairRestoreToken =
                    Id("hair-restore-token");
                return new
                {
                    operation =
                        HairAppearanceOperation.Name,
                    transactionId =
                        HairTransactionId,
                    binding =
                        HairBindingContract(binding),
                    beforeHair = CurrentHair,
                    afterHair =
                        parameters.HairIdentifier,
                    expectedRevision =
                        parameters.ExpectedRevision,
                    expectedGeneration =
                        parameters.ExpectedGeneration,
                    expectedSnapshotHash =
                        parameters.ExpectedSnapshotHash,
                    previewHash = HairPreviewHash,
                    createdAtUtc = _clock.UtcNow
                };
            }

            private HairSaveBinding HairBinding()
            {
                SessionSnapshot session =
                    _controller.Snapshot;
                return new HairSaveBinding(
                    session.SessionId,
                    checked((long)
                        session.LifecycleGeneration),
                    session.AttemptId,
                    checked((long)
                        session.AttemptGeneration.Value),
                    session.Slot,
                    WingsTestFixture.View()
                        .Progress.SaveSignature);
            }

            private static object HairBindingContract(
                HairSaveBinding binding)
            {
                return new
                {
                    sessionId = binding.SessionId,
                    lifecycleGeneration =
                        binding.LifecycleGeneration,
                    attemptId = binding.AttemptId,
                    attemptGeneration =
                        binding.AttemptGeneration,
                    slotId = binding.SlotId,
                    saveSignature =
                        binding.SaveSignature
                };
            }

            private ObservationEnvelope Observation(
                string targetId)
            {
                SessionSnapshot session =
                    _controller.Snapshot;
                SessionSurfaceSnapshot surface =
                    session.Surfaces.Single(candidate =>
                        candidate.TargetId
                            == targetId);
                string observationId = Id(
                    "observation-"
                    + Methods.Count);
                ulong now = checked(
                    (ulong)_clock.MonotonicMilliseconds);
                var rect = new PhysicalRect
                {
                    X = surface.ContentRectPhysical.X,
                    Y = surface.ContentRectPhysical.Y,
                    Width =
                        surface.ContentRectPhysical.Width,
                    Height =
                        surface.ContentRectPhysical.Height
                };
                return new ObservationEnvelope
                {
                    ObservationId = observationId,
                    ObservationGrantId =
                        Grant.ObservationGrantId,
                    SessionId = session.SessionId,
                    LifecycleGeneration =
                        session.LifecycleGeneration,
                    CapturedUtc = _clock.UtcNow,
                    CapturedAtMonotonic = now,
                    AttemptId = session.AttemptId,
                    AttemptGeneration =
                        session.AttemptGeneration,
                    PanelInstanceId =
                        session.PanelInstanceIdForTarget(
                            targetId),
                    DocumentGeneration =
                        surface.DocumentGeneration,
                    TargetId = targetId,
                    SurfaceEpoch = surface.SurfaceEpoch,
                    CoordinateSpaceVersion =
                        surface.CoordinateSpaceVersion,
                    FocusEpoch = session.FocusEpoch,
                    ModalEpoch = session.ModalEpoch,
                    SemanticSnapshotId = null,
                    SemanticGeneration =
                        surface.SemanticGeneration,
                    Visible = true,
                    Minimized = false,
                    Active = true,
                    BlockingModalKind =
                        BlockingModalKind.None,
                    Frames = new List<FrameEnvelope>
                    {
                        new FrameEnvelope
                        {
                            FrameId = Id("frame"),
                            ObservationId =
                                observationId,
                            TargetId =
                                targetId,
                            SurfaceEpoch =
                                surface.SurfaceEpoch,
                            SourceLayer =
                                surface.Kind
                                    == SurfaceKind.WebOverlay
                                ? SourceLayer.WebOverlay
                                : SourceLayer.Flash,
                            ZIndex = surface.ZIndex,
                            CapturedAtMonotonic = now,
                            CoordinateSpaceId =
                                Id("coordinates"),
                            CoordinateSpaceVersion =
                                surface
                                    .CoordinateSpaceVersion,
                            CaptureRectPhysical = rect,
                            ClientRectPhysical = rect,
                            ContentRectPhysical = rect,
                            FrameToTargetContentTransform =
                                new AffineTransform
                                {
                                    M11 = 1,
                                    M22 = 1
                                },
                            Width = rect.Width,
                            Height = rect.Height,
                            Dpi = surface.Dpi,
                            PixelFormat =
                                PixelFormat
                                    .Bgra8Premultiplied,
                            ContentHash =
                                new string('d', 64),
                            OpaqueContentHandle =
                                Id("content")
                        }
                    }
                };
            }

            private static ObservationGrantDescriptor
                GrantContract(
                    ObservationGrant grant,
                    SessionSnapshot session)
            {
                return new ObservationGrantDescriptor
                {
                    ObservationGrantId =
                        grant.ObservationGrantId,
                    OwnerClientId = grant.OwnerClientId,
                    SecurityPrincipalId =
                        grant.SecurityPrincipalId,
                    SessionScope =
                        new SessionScopeDescriptor
                        {
                            SessionId = grant.SessionId,
                            LifecycleGeneration =
                                session
                                    .LifecycleGeneration,
                            AttemptId = session.AttemptId,
                            AttemptGeneration =
                                session.AttemptGeneration,
                            CrossAttempt = false
                        },
                    TargetScope =
                        grant.TargetScope.ToList(),
                    DataScope =
                        grant.DataScope.ToList(),
                    IssuedMonotonic = checked(
                        (ulong)grant.IssuedMonotonic),
                    ExpiresMonotonic = checked(
                        (ulong)grant.ExpiresMonotonic),
                    ConsentReceipt =
                        grant.ConsentReceipt,
                    AllowEphemeralKeyframes =
                        grant.AllowEphemeralKeyframes,
                    AllowPersistence =
                        grant.AllowPersistence,
                    AllowExport = grant.AllowExport,
                    State =
                        CF7Launcher.AgentRuntime.Contracts
                            .ObservationGrantState.Active
                };
            }
        }

        private sealed class AcceptingHostValidator
            : ISessionSurfaceHostValidator
        {
            public bool ValidateSession(
                SessionRegistryHostOwner hostOwner,
                SessionHostRegistration registration,
                out string reasonCode)
            {
                reasonCode = null;
                return true;
            }

            public bool ValidateAttemptProcess(
                SessionRegistryHostOwner hostOwner,
                SessionProcessIdentity flashProcess,
                out string reasonCode)
            {
                reasonCode = null;
                return true;
            }

            public bool ValidateSurface(
                SessionRegistryHostOwner hostOwner,
                SessionSurfaceValidationContext context,
                SessionSurfaceHostRegistration registration,
                out string reasonCode)
            {
                reasonCode = null;
                return true;
            }
        }
    }
}
