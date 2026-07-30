using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Domain;
using CF7Launcher.AgentRuntime.Gateway;
using CF7Launcher.AgentRuntime.Security;
using CF7Launcher.AgentRuntime.Sessions;
using CF7Launcher.AgentRuntime.Wings;

namespace CF7Launcher.AgentRuntime.Integration
{
    internal sealed partial class
        LauncherWingsStructuredActionCoordinator
    {
        public async Task<LauncherWingsStructuredActionResult>
            ChangeHairAsync(
                CancellationToken cancellationToken)
        {
            if (_hairTargetId == null
                || _hairPresenter == null
                || _hairIntentFactory == null
                || _hairBindingAuthority == null
                || _hairConsentEvidenceAuthority == null)
            {
                return LauncherWingsStructuredActionResult
                    .Rejected("unsupported_for_surface");
            }
            if (!TryBeginOperation(
                    StructuredOperationKind.HairChange,
                    cancellationToken,
                    out ActiveOperation operation,
                    out string reasonCode))
            {
                return LauncherWingsStructuredActionResult
                    .Rejected(reasonCode);
            }

            try
            {
                if (!TryGetEligibleHairSnapshot(
                        null,
                        out SessionSnapshot beforePreparation,
                        out _,
                        out reasonCode)
                    || !TryReadPrerequisite(out reasonCode))
                {
                    return await RejectAndCleanupAsync(
                            operation,
                            reasonCode)
                        .ConfigureAwait(false);
                }

                DateTimeOffset issued = _clock.UtcNow;
                var preparation =
                    new LauncherWingsHairPreparationProposal(
                        Expectation(beforePreparation),
                        beforePreparation.Slot,
                        _loreView.Progress.SaveBindingId,
                        _loreView.LoreViewId,
                        _hairTargetId,
                        HairdresserPanelName,
                        beforePreparation
                            .ActivePanelInstanceId,
                        issued,
                        issued.Add(ApprovalLifetime));
                operation.HairProposal = preparation;

                LauncherWingsHairSecurityApproval
                    preparationApproval =
                        await _hairPresenter
                            .PresentPreparationAsync(
                                preparation,
                                operation
                                    .TrustedInteractionTicket,
                                operation.Cancellation.Token)
                            .ConfigureAwait(false);
                string preparationFenceFailure =
                    await SealTrustedHumanInteractionAsync(
                            operation,
                            OperationPhase.PresentingConsent)
                        .ConfigureAwait(false);
                if (preparationFenceFailure != null)
                {
                    return await RejectAndCleanupAsync(
                            operation,
                            preparationFenceFailure)
                        .ConfigureAwait(false);
                }
                if (!IsCurrent(operation))
                {
                    return await RejectAndCleanupAsync(
                            operation,
                            "credential_revoked")
                        .ConfigureAwait(false);
                }
                if (preparationApproval == null
                    || !preparationApproval.Approved)
                {
                    return await RejectAndCleanupAsync(
                            operation,
                            preparationApproval?.ReasonCode
                                ?? "consent_required")
                        .ConfigureAwait(false);
                }
                if (_clock.UtcNow >= preparation.ExpiresAtUtc
                    || !TryGetEligibleHairSnapshot(
                        preparation,
                        out SessionSnapshot current,
                        out _,
                        out reasonCode))
                {
                    return await RejectAndCleanupAsync(
                            operation,
                            reasonCode
                                ?? "consent_expired")
                        .ConfigureAwait(false);
                }

                try
                {
                    operation.Indicator =
                        _hairIndicatorFactory();
                }
                catch
                {
                    operation.Indicator = null;
                }
                if (operation.Indicator == null
                    || !operation.Indicator.TryShow(
                        _clock.UtcNow.Add(
                            HairCredentialLifetime),
                        HairCredentialLifetime,
                        () => Revoke(
                            "wings_indicator_closed")))
                {
                    return await RejectAndCleanupAsync(
                            operation,
                            "human_intervention_required")
                        .ConfigureAwait(false);
                }
                operation.Phase =
                    OperationPhase.IndicatorActive;
                if (!IsCurrent(operation))
                {
                    return await RejectAndCleanupAsync(
                            operation,
                            "credential_revoked")
                        .ConfigureAwait(false);
                }

                PrincipalCredential principal;
                try
                {
                    var evidence =
                        new PlayerAssistCredentialEvidence
                        {
                            ClientInstanceId =
                                OpaqueIdGenerator.Create(
                                    "wingshairclient"),
                            ConsentReceipt =
                                preparationApproval
                                    .HumanInteractionReceiptId,
                            SelectedSessionId = _sessionId,
                            AllowedCapabilities =
                                HairCapabilities,
                            AllowedTargets =
                                new[] { _hairTargetId },
                            RequestedLifetime =
                                HairCredentialLifetime
                        };
                    _verifier.RegisterPlayerConsent(evidence);
                    principal =
                        _credentials.IssuePlayerAssist(
                            evidence);
                    operation.Principal = principal;
                }
                catch
                {
                    return await RejectAndCleanupAsync(
                            operation,
                            "credential_revoked")
                        .ConfigureAwait(false);
                }
                if (!IsExactHairPrincipal(principal)
                    || !IsCurrent(operation))
                {
                    return await RejectAndCleanupAsync(
                            operation,
                            "principal_mismatch")
                        .ConfigureAwait(false);
                }

                try
                {
                    operation.Connection =
                        _connectionFactory(principal);
                }
                catch
                {
                    operation.Connection = null;
                }
                if (operation.Connection == null
                    || !ReferenceEquals(
                        operation.Connection.Principal,
                        principal)
                    || !IsCurrent(operation))
                {
                    return await RejectAndCleanupAsync(
                            operation,
                            "credential_revoked")
                        .ConfigureAwait(false);
                }
                operation.Phase =
                    OperationPhase.CredentialActive;

                MinimalSessionReference minimal =
                    await ResolveMinimalSessionAsync(
                            operation,
                            operation.Cancellation.Token)
                        .ConfigureAwait(false);
                if (minimal == null
                    || !minimal.ProjectRunning
                    || minimal.QualificationState
                        != RuntimeQualificationState.Verified
                    || string.IsNullOrWhiteSpace(
                        minimal.LifecycleRef))
                {
                    return await RejectAndCleanupAsync(
                            operation,
                            "runtime_unqualified")
                        .ConfigureAwait(false);
                }

                AgentRuntimeDispatchResult attach =
                    await operation.Connection.DispatchAsync(
                            AgentCapabilitiesV1.SessionAttach,
                            JsonSerializer.SerializeToElement(
                                new SessionBindingParametersV1
                                {
                                    SessionId =
                                        current.SessionId,
                                    LifecycleGeneration =
                                        current
                                            .LifecycleGeneration
                                },
                                AgentProtocolV1.JsonOptions),
                            operation.Cancellation.Token)
                        .ConfigureAwait(false);
                if (!attach.Success)
                {
                    return await RejectAndCleanupAsync(
                            operation,
                            attach.ReasonCode)
                        .ConfigureAwait(false);
                }
                operation.Phase = OperationPhase.Attached;

                if (!TryGetEligibleHairSnapshot(
                        preparation,
                        out current,
                        out _,
                        out reasonCode))
                {
                    return await RejectAndCleanupAsync(
                            operation,
                            reasonCode)
                        .ConfigureAwait(false);
                }

                AgentRuntimeDispatchResult grantResult =
                    await operation.Connection.DispatchAsync(
                            AgentMethodsV1
                                .ObservationGrantIssue,
                            JsonSerializer.SerializeToElement(
                                new ObservationGrantIssueParametersV1
                                {
                                    LifecycleRef =
                                        minimal.LifecycleRef,
                                    TargetIds =
                                        new List<string>
                                        {
                                            _hairTargetId
                                        },
                                    TargetKinds = null,
                                    DataScopes =
                                        new List<string>
                                        {
                                            ObservationDataScopesV1
                                                .PlayerState,
                                            ObservationDataScopesV1
                                                .Pixels
                                        },
                                    RequestedTtlMs =
                                        HairGrantLifetimeMilliseconds,
                                    AllowEphemeralKeyframes = true,
                                    AllowPersistence = false,
                                    AllowExport = false,
                                    ConsentReceipt =
                                        principal.IssuerReceipt
                                },
                                AgentProtocolV1.JsonOptions),
                            operation.Cancellation.Token)
                        .ConfigureAwait(false);
                if (!grantResult.Success
                    || !TryDeserialize(
                        grantResult,
                        out ObservationGrantDescriptor grant)
                    || !GrantMatchesHair(
                        principal,
                        current,
                        grant))
                {
                    return await RejectAndCleanupAsync(
                            operation,
                            grantResult.ReasonCode
                                ?? "observation_scope_mismatch")
                        .ConfigureAwait(false);
                }
                operation.GrantId =
                    grant.ObservationGrantId;
                operation.HairGrant = grant;
                operation.Phase =
                    OperationPhase.GrantActive;

                HairObservationCapture initialCapture =
                    await CaptureFreshHairObservationAsync(
                            operation,
                            grant,
                            null)
                        .ConfigureAwait(false);
                if (!initialCapture.Success)
                {
                    return await RejectAndCleanupAsync(
                            operation,
                            initialCapture.ReasonCode)
                        .ConfigureAwait(false);
                }
                operation.HairObservation =
                    initialCapture.Observation;
                operation.HairFrame =
                    initialCapture.Frame;
                operation.Phase =
                    OperationPhase.ObservationCaptured;

                HairSaveBinding expectedBinding =
                    ToHairBinding(current);
                HairInspectDispatch inspect =
                    await DispatchHairInspectAsync(
                            operation,
                            expectedBinding)
                        .ConfigureAwait(false);
                if (!inspect.Success
                    || !TryGetEligibleHairSnapshot(
                        preparation,
                        out current,
                        out _,
                        out reasonCode)
                    || !ObservationMatchesHair(
                        current,
                        grant,
                        operation.HairObservation,
                        null,
                        out _))
                {
                    return await RejectAndCleanupAsync(
                            operation,
                            inspect.ReasonCode
                                ?? reasonCode
                                ?? "stale_observation")
                        .ConfigureAwait(false);
                }

                LauncherWingsHairChooserCard chooserCard =
                    CreateChooserCard(
                        current,
                        inspect.Result);
                string chooserPriorObservationId =
                    operation.HairObservation.ObservationId;
                if (!BeginTrustedHumanInteraction(
                        operation,
                        OperationPhase.ChoosingHair))
                {
                    return await RejectAndCleanupAsync(
                            operation,
                            "credential_revoked")
                        .ConfigureAwait(false);
                }
                LauncherWingsHairChooserSelection selection =
                    await _hairPresenter.ChooseAsync(
                            chooserCard,
                            operation
                                .TrustedInteractionTicket,
                            operation.Cancellation.Token)
                        .ConfigureAwait(false);
                string chooserFenceFailure =
                    await SealTrustedHumanInteractionAsync(
                            operation,
                            OperationPhase.ChoosingHair)
                        .ConfigureAwait(false);
                if (chooserFenceFailure != null)
                {
                    return await RejectAndCleanupAsync(
                            operation,
                            chooserFenceFailure)
                        .ConfigureAwait(false);
                }
                if (!IsCurrent(operation))
                {
                    return await RejectAndCleanupAsync(
                            operation,
                            "credential_revoked")
                        .ConfigureAwait(false);
                }
                if (!TryValidateHairSelection(
                        chooserCard,
                        selection,
                        out reasonCode)
                    || !TryGetEligibleHairSnapshot(
                        preparation,
                        out current,
                        out _,
                        out reasonCode))
                {
                    return await RejectAndCleanupAsync(
                            operation,
                            reasonCode
                                ?? "stale_observation")
                        .ConfigureAwait(false);
                }

                HairObservationCapture chooserCapture =
                    await CaptureFreshHairObservationAsync(
                            operation,
                            grant,
                            chooserPriorObservationId)
                        .ConfigureAwait(false);
                if (!chooserCapture.Success)
                {
                    return await RejectAndCleanupAsync(
                            operation,
                            chooserCapture.ReasonCode)
                        .ConfigureAwait(false);
                }
                current = chooserCapture.Session;
                operation.HairObservation =
                    chooserCapture.Observation;
                operation.HairFrame =
                    chooserCapture.Frame;

                HairPreviewDispatch previewDispatch =
                    await DispatchHairPreviewAsync(
                            operation,
                            inspect.Result,
                            selection.HairIdentifier)
                        .ConfigureAwait(false);
                if (!previewDispatch.Success
                    || !PreviewMatchesInspectAndSelection(
                        previewDispatch.Preview,
                        inspect.Result,
                        selection.HairIdentifier)
                    || !TryGetEligibleHairSnapshot(
                        preparation,
                        out current,
                        out _,
                        out reasonCode)
                    || !ObservationMatchesHair(
                        current,
                        grant,
                        operation.HairObservation,
                        null,
                        out _))
                {
                    return await RejectAndCleanupAsync(
                            operation,
                            previewDispatch.ReasonCode
                                ?? reasonCode
                                ?? "domain_revision_conflict")
                        .ConfigureAwait(false);
                }
                operation.HairPreview =
                    previewDispatch.Preview;
                operation.Phase =
                    OperationPhase.HairPreviewReady;

                if (!BeginTrustedHumanInteraction(
                        operation,
                        OperationPhase.PresentingHairConsent))
                {
                    return await RejectAndCleanupAsync(
                            operation,
                            "credential_revoked")
                        .ConfigureAwait(false);
                }
                LauncherWingsHairConsentDispatchEvidence
                    consentCapture =
                        await _hairConsentEvidenceAuthority
                            .DispatchAndCaptureAsync(
                                operation.Connection,
                                operation.HairPreview,
                                grant.ObservationGrantId,
                                operation
                                    .TrustedInteractionTicket,
                                operation.Cancellation.Token)
                        .ConfigureAwait(false);
                string consentFenceFailure =
                    await SealTrustedHumanInteractionAsync(
                            operation,
                            OperationPhase.PresentingHairConsent)
                        .ConfigureAwait(false);
                if (consentFenceFailure != null)
                {
                    return await RejectAndCleanupAsync(
                            operation,
                            consentFenceFailure)
                        .ConfigureAwait(false);
                }
                if (!IsCurrent(operation)
                    || !TryGetEligibleHairSnapshot(
                        preparation,
                        out current,
                        out _,
                        out reasonCode)
                    || !consentCapture.Success)
                {
                    return await RejectAndCleanupAsync(
                            operation,
                            reasonCode
                                ?? consentCapture.ReasonCode
                                ?? "consent_required")
                        .ConfigureAwait(false);
                }
                LauncherWingsHairConsentEvidence
                    consentEvidence =
                        consentCapture.Evidence;
                HairConsentDescriptorV1
                    consentDescriptor =
                        consentCapture.Descriptor;

                HairObservationCapture commitCapture =
                    await CaptureFreshHairObservationAsync(
                            operation,
                            grant,
                            operation.HairObservation
                                .ObservationId)
                        .ConfigureAwait(false);
                if (!commitCapture.Success)
                {
                    return await RejectAndCleanupAsync(
                            operation,
                            commitCapture.ReasonCode)
                        .ConfigureAwait(false);
                }
                operation.HairObservation =
                    commitCapture.Observation;
                operation.HairFrame =
                    commitCapture.Frame;

                JsonElement commitArguments =
                    JsonSerializer.SerializeToElement(
                        new
                        {
                            transactionId =
                                operation.HairPreview
                                    .TransactionId,
                            previewHash =
                                operation.HairPreview
                                    .PreviewHash,
                            consentToken =
                                consentDescriptor
                                    .ConsentToken
                        },
                        AgentProtocolV1.JsonOptions);
                WingsActionHostBindingSnapshot
                    commitBinding =
                        CreateHairActionBinding(
                            commitCapture.Session,
                            commitCapture.Observation,
                            commitCapture.Frame,
                            operation.HairPreview);
                if (!_hairIntentFactory.TryIssue(
                        LauncherWingsHairActionBindingAuthority
                            .CommitTemplateKey,
                        commitBinding,
                        commitArguments,
                        out WingsActionIntentV1 commitIntent,
                        out reasonCode)
                    || !_hairConsentEvidenceAuthority
                        .TryConsume(
                            consentEvidence,
                            operation.Connection,
                            principal,
                            operation.HairPreview,
                            consentDescriptor,
                            out string
                                commitHumanReceipt,
                            out string
                                commitReauthorizationReceipt,
                            out reasonCode)
                    || !_hairBindingAuthority.TryRegister(
                        principal,
                        commitIntent,
                        commitCapture.Observation,
                        commitCapture.Frame,
                        operation.HairPreview,
                        consentDescriptor.ConsentToken,
                        out reasonCode)
                    || !_hairBindingAuthority.TryValidate(
                        principal,
                        commitIntent,
                        out reasonCode))
                {
                    return await RejectAndCleanupAsync(
                            operation,
                            reasonCode
                                ?? "wings_action_binding_unavailable")
                        .ConfigureAwait(false);
                }
                operation.Intent = commitIntent;
                operation.Phase =
                    OperationPhase.HairConsentEvidenceConsumed;

                TrustedWingsActionAuthorization
                    commitAuthorization =
                        _consentTrustDomain.Seal(
                            commitIntent,
                            principal,
                            commitHumanReceipt,
                            commitReauthorizationReceipt,
                            _clock.MonotonicMilliseconds);
                HairExecutionTerminal commitTerminal =
                    await ExecuteHairIntentAsync(
                            operation,
                            commitIntent,
                            commitAuthorization)
                        .ConfigureAwait(false);
                if (!commitTerminal.Success)
                {
                    return await RejectAndCleanupAsync(
                            operation,
                            commitTerminal.ReasonCode)
                        .ConfigureAwait(false);
                }
                ActionReceipt commitReceipt =
                    commitTerminal.Receipt;
                if (IsTerminalProjectionConcluded(
                        operation))
                {
                    return FinishWithProjection(
                        operation,
                        commitTerminal.ActionReceiptId);
                }
                if (commitReceipt.Outcome
                        != ActionOutcome.DomainCommitted
                    && commitReceipt.Outcome
                        != ActionOutcome.Unknown)
                {
                    return FinishWithProjection(
                        operation,
                        commitTerminal.ActionReceiptId);
                }
                HairReconcileDispatch commitReconcile =
                    await ReconcileUnknownHairAsync(
                                operation,
                                operation.HairPreview
                                    .TransactionId)
                        .WaitAsync(
                            operation.Cancellation.Token)
                        .ConfigureAwait(false);
                if (IsTerminalProjectionConcluded(
                        operation))
                {
                    return FinishWithProjection(
                        operation,
                        commitTerminal.ActionReceiptId);
                }
                if (!commitReconcile.Success
                    || commitReconcile.Result.Outcome
                        != HairTransactionOutcome
                            .DomainCommitted)
                {
                    return FinishWithProjection(
                        operation,
                        commitTerminal.ActionReceiptId);
                }
                if (!TryCaptureRestoreSecret(
                        operation,
                        commitReceipt,
                        commitReconcile.Result,
                        out reasonCode))
                {
                    return FinishWithProjection(
                        operation,
                        commitTerminal.ActionReceiptId);
                }

                operation.HairObservation = null;
                operation.HairFrame = null;
                if (!TryGetEligibleHairSnapshot(
                        preparation,
                        out SessionSnapshot restoreSession,
                        out SessionSurfaceSnapshot
                            restoreSurface,
                        out reasonCode,
                        requireActiveHairdresserPanel: false))
                {
                    return FinishWithProjection(
                        operation,
                        commitTerminal.ActionReceiptId);
                }
                DateTimeOffset restoreIssued =
                    _clock.UtcNow;
                DateTimeOffset restorePromptExpires =
                    restoreIssued.Add(ApprovalLifetime);
                if (restorePromptExpires
                    > operation.RestoreExpiresAtUtc.Value)
                {
                    restorePromptExpires =
                        operation.RestoreExpiresAtUtc.Value;
                }
                if (restorePromptExpires <= restoreIssued)
                {
                    return FinishWithProjection(
                        operation,
                        commitTerminal.ActionReceiptId);
                }
                var restoreProposal =
                    new LauncherWingsHairRestoreProposal(
                        Expectation(restoreSession),
                        restoreSession.Slot,
                        _loreView.Progress.SaveBindingId,
                        _loreView.LoreViewId,
                        _hairTargetId,
                        preparation.PanelName,
                        preparation.PanelInstanceId,
                        operation.HairPreview.TransactionId,
                        operation.HairPreview.PreviewHash,
                        operation.HairPreview.BeforeHair,
                        operation.HairPreview.AfterHair,
                        operation.RestoreExpiresAtUtc.Value,
                        restoreIssued,
                        restorePromptExpires);
                HairSurfaceFence restoreFence =
                    new HairSurfaceFence(
                        restoreSession,
                        restoreSurface,
                        requirePanelIdentity: false);
                if (!BeginTrustedHumanInteraction(
                        operation,
                        OperationPhase.PresentingRestoreConsent))
                {
                    return FinishWithProjection(
                        operation,
                        commitTerminal.ActionReceiptId);
                }
                LauncherWingsHairSecurityApproval
                    restoreApproval =
                        await _hairPresenter
                            .PresentRestoreAsync(
                                restoreProposal,
                                operation
                                    .TrustedInteractionTicket,
                                operation.Cancellation.Token)
                            .WaitAsync(
                                operation.Cancellation.Token)
                            .ConfigureAwait(false);
                string restoreFenceFailure =
                    await SealTrustedHumanInteractionAsync(
                            operation,
                            OperationPhase.PresentingRestoreConsent)
                        .ConfigureAwait(false);
                if (restoreFenceFailure != null)
                {
                    return FinishWithProjection(
                        operation,
                        commitTerminal.ActionReceiptId);
                }
                if (!IsCurrent(operation))
                {
                    return FinishWithProjection(
                        operation,
                        commitTerminal.ActionReceiptId);
                }
                if (restoreApproval == null
                    || !restoreApproval.Approved)
                {
                    return FinishWithProjection(
                        operation,
                        commitTerminal.ActionReceiptId);
                }
                if (_clock.UtcNow
                        >= restoreProposal.ExpiresAtUtc
                    || !TryGetEligibleHairSnapshot(
                        preparation,
                        out restoreSession,
                        out restoreSurface,
                        out reasonCode,
                        requireActiveHairdresserPanel: false)
                    || !restoreFence.MatchesAfterSecurityPrompt(
                        restoreSession,
                        restoreSurface))
                {
                    return FinishWithProjection(
                        operation,
                        commitTerminal.ActionReceiptId);
                }

                HairObservationCapture restoreCapture =
                    await CaptureFreshHairObservationAsync(
                            operation,
                            grant,
                            commitCapture.Observation
                                .ObservationId,
                            requireActiveHairdresserPanel: false)
                        .ConfigureAwait(false);
                if (!restoreCapture.Success)
                {
                    return FinishWithProjection(
                        operation,
                        commitTerminal.ActionReceiptId);
                }
                operation.HairObservation =
                    restoreCapture.Observation;
                operation.HairFrame =
                    restoreCapture.Frame;
                operation.Phase =
                    OperationPhase.RestoreObservationCaptured;

                JsonElement restoreArguments =
                    JsonSerializer.SerializeToElement(
                        new
                        {
                            transactionId =
                                operation.HairPreview
                                    .TransactionId,
                            restoreToken =
                                operation.RestoreToken
                        },
                        AgentProtocolV1.JsonOptions);
                WingsActionHostBindingSnapshot
                    restoreBinding =
                        CreateHairActionBinding(
                            restoreCapture.Session,
                            restoreCapture.Observation,
                            restoreCapture.Frame,
                            operation.HairPreview);
                if (!_hairIntentFactory.TryIssue(
                        LauncherWingsHairActionBindingAuthority
                            .RestoreTemplateKey,
                        restoreBinding,
                        restoreArguments,
                        out WingsActionIntentV1 restoreIntent,
                        out reasonCode)
                    || !_hairBindingAuthority.TryRegister(
                        principal,
                        restoreIntent,
                        restoreCapture.Observation,
                        restoreCapture.Frame,
                        operation.HairPreview,
                        operation.RestoreToken,
                        out reasonCode)
                    || !_hairBindingAuthority.TryValidate(
                        principal,
                        restoreIntent,
                        out reasonCode))
                {
                    return FinishWithProjection(
                        operation,
                        commitTerminal.ActionReceiptId);
                }
                operation.Intent = restoreIntent;
                operation.Phase =
                    OperationPhase.IntentAuthorized;
                TrustedWingsActionAuthorization
                    restoreAuthorization =
                        _consentTrustDomain.Seal(
                            restoreIntent,
                            principal,
                            restoreApproval
                                .HumanInteractionReceiptId,
                            restoreApproval
                                .ReauthorizationReceiptId,
                            _clock.MonotonicMilliseconds);
                HairExecutionTerminal restoreTerminal =
                    await ExecuteHairIntentAsync(
                            operation,
                            restoreIntent,
                            restoreAuthorization)
                        .ConfigureAwait(false);
                if (!restoreTerminal.Success)
                {
                    return FinishWithProjection(
                        operation,
                        commitTerminal.ActionReceiptId);
                }
                if (restoreTerminal.Receipt.Outcome
                    == ActionOutcome.Unknown)
                {
                    await ReconcileUnknownHairAsync(
                            operation,
                            operation.HairPreview
                                .TransactionId)
                        .ConfigureAwait(false);
                }
                return FinishWithProjection(
                    operation,
                    restoreTerminal.ActionReceiptId);
            }
            catch (OperationCanceledException)
            {
                if (operation.CommitReceiptId != null)
                {
                    return FinishWithProjection(
                        operation,
                        operation.CommitReceiptId);
                }
                return await RejectAndCleanupAsync(
                        operation,
                        "credential_revoked")
                    .ConfigureAwait(false);
            }
            catch
            {
                if (operation.CommitReceiptId != null)
                {
                    return FinishWithProjection(
                        operation,
                        operation.CommitReceiptId);
                }
                return await RejectAndCleanupAsync(
                        operation,
                        "internal_error")
                    .ConfigureAwait(false);
            }
        }

        private LauncherWingsStructuredActionResult
            FinishWithProjection(
                ActiveOperation operation,
                string actionReceiptId)
        {
            string discardedActionReceiptId = null;
            string discardedCommitReceiptId = null;
            bool revokeLiveResources = false;
            lock (_sync)
            {
                if (ReferenceEquals(_active, operation))
                {
                    if (operation
                            .TerminalProjectionConcluded
                        && operation.CommitReceiptId != null)
                    {
                        actionReceiptId =
                            operation.CommitReceiptId;
                    }
                    if (!string.Equals(
                            operation.ActionReceiptId,
                            actionReceiptId,
                            StringComparison.Ordinal))
                    {
                        discardedActionReceiptId =
                            operation.ActionReceiptId;
                    }
                    if (!string.Equals(
                            operation.CommitReceiptId,
                            actionReceiptId,
                            StringComparison.Ordinal))
                    {
                        discardedCommitReceiptId =
                            operation.CommitReceiptId;
                    }
                    operation.ActionReceiptId =
                        actionReceiptId;
                    operation.ClearHairSensitiveState();
                    operation.Phase =
                        OperationPhase.AwaitingProjection;
                    revokeLiveResources =
                        operation
                            .TerminalProjectionConcluded;
                }
            }
            _resultAuthority.Remove(
                discardedActionReceiptId);
            _resultAuthority.Remove(
                discardedCommitReceiptId);
            ScheduleProjectionExpiry(operation);
            if (revokeLiveResources)
            {
                BeginLiveResourceRevocation(
                    operation,
                    "credential_revoked");
            }
            return LauncherWingsStructuredActionResult
                .Completed(actionReceiptId);
        }

        private bool IsTerminalProjectionConcluded(
            ActiveOperation operation)
        {
            lock (_sync)
            {
                return ReferenceEquals(
                        _active,
                        operation)
                    && operation
                        .TerminalProjectionConcluded;
            }
        }

        private async Task<HairExecutionTerminal>
            ExecuteHairIntentAsync(
                ActiveOperation operation,
                WingsActionIntentV1 intent,
                TrustedWingsActionAuthorization authorization)
        {
            operation.Phase =
                OperationPhase.Executing;
            RaiseExecutionStarting();
            var executor =
                new WingsStructuredActionExecutor(
                    _clock,
                    _hairBindingAuthority,
                    operation.Connection,
                    _consentTrustDomain,
                    _receiptTrustDomain);
            WingsStructuredActionExecutionResult execution =
                await executor.ExecuteAsync(
                        authorization,
                        operation.Cancellation.Token)
                    .ConfigureAwait(false);
            if (!execution.HasTerminalReceipt)
            {
                return HairExecutionTerminal.Rejected(
                    execution.ReasonCode
                        ?? "wings_terminal_receipt_required");
            }
            ActionReceipt receipt =
                execution.BrokeredReceipt
                    .ReceiptSnapshot();
            if (!_hairBindingAuthority.TryMarkTerminal(
                    operation.Principal,
                    intent,
                    execution.BrokeredReceipt,
                    _receiptTrustDomain,
                    out string reasonCode)
                || !TryRecordAndAdoptTerminalReceipt(
                    operation,
                    operation.Principal,
                    intent,
                    execution.BrokeredReceipt,
                    commitReceipt: string.Equals(
                        intent.Operation,
                        AgentMethodsV1.HairCommit,
                        StringComparison.Ordinal),
                    out string actionReceiptId,
                    out reasonCode))
            {
                return HairExecutionTerminal.Rejected(
                    reasonCode
                        ?? "wings_terminal_receipt_required");
            }
            return HairExecutionTerminal.Completed(
                actionReceiptId,
                receipt);
        }

        private async Task<HairReconcileDispatch>
            ReconcileUnknownHairAsync(
            ActiveOperation operation,
            string transactionId)
        {
            operation.Phase =
                OperationPhase.Reconciling;
            try
            {
                AgentRuntimeDispatchResult result =
                    await operation.Connection.DispatchAsync(
                            AgentMethodsV1.HairReconcile,
                            JsonSerializer.SerializeToElement(
                                new HairReconcileParametersV1
                                {
                                    ObservationGrantId =
                                        operation.GrantId,
                                    TargetId = _hairTargetId,
                                    TransactionId =
                                        transactionId
                                },
                                AgentProtocolV1.JsonOptions),
                            operation.Cancellation.Token)
                        .ConfigureAwait(false);
                if (result.Success
                    && TryDeserialize(
                        result,
                        out HairTransactionWireResult wire)
                    && wire != null
                    && string.Equals(
                        wire.TransactionId,
                        transactionId,
                        StringComparison.Ordinal)
                    && string.Equals(
                        wire.PreviewHash,
                        operation.HairPreview
                            .PreviewHash,
                        StringComparison.OrdinalIgnoreCase))
                {
                    return HairReconcileDispatch.Completed(
                        wire);
                }
                return HairReconcileDispatch.Rejected(
                    result.ReasonCode
                        ?? "domain_reconcile_required");
            }
            catch (OperationCanceledException)
                when (operation.Cancellation
                    .IsCancellationRequested)
            {
                throw;
            }
            catch
            {
                // The original trusted receipt remains unknown. Reconcile is
                // read-only and is never converted into a synthetic receipt.
                return HairReconcileDispatch.Rejected(
                    "domain_reconcile_required");
            }
        }

        private bool TryCaptureRestoreSecret(
            ActiveOperation operation,
            ActionReceipt receipt,
            HairTransactionWireResult reconcile,
            out string reasonCode)
        {
            HairDomainActionResult result =
                receipt?.DomainResult;
            bool knownCommit =
                receipt?.Outcome
                    == ActionOutcome.DomainCommitted;
            if (receipt == null
                || (receipt.Outcome
                        != ActionOutcome.DomainCommitted
                    && receipt.Outcome
                        != ActionOutcome.Unknown)
                || reconcile == null
                || reconcile.Outcome
                    != HairTransactionOutcome.DomainCommitted
                || !string.Equals(
                    reconcile.TransactionId,
                    operation.HairPreview.TransactionId,
                    StringComparison.Ordinal)
                || !string.Equals(
                    reconcile.PreviewHash,
                    operation.HairPreview.PreviewHash,
                    StringComparison.OrdinalIgnoreCase)
                || (knownCommit
                    && (result == null
                        || !string.Equals(
                            result.TransactionId,
                            operation.HairPreview
                                .TransactionId,
                            StringComparison.Ordinal)
                        || !string.Equals(
                            result.PreviewHash,
                            operation.HairPreview
                                .PreviewHash,
                            StringComparison
                                .OrdinalIgnoreCase))))
            {
                reasonCode =
                    "wings_receipt_domain_mismatch";
                return false;
            }
            string restoreToken =
                HairAppearanceValidation.IsSafeString(
                    result?.RestoreToken,
                    256,
                    false)
                    ? result.RestoreToken
                    : reconcile.RestoreToken;
            DateTimeOffset? restoreExpiresAtUtc =
                result?.RestoreExpiresAtUtc.HasValue == true
                    ? result.RestoreExpiresAtUtc
                    : reconcile.RestoreExpiresAtUtc;
            if (!HairAppearanceValidation.IsSafeString(
                    restoreToken,
                    256,
                    false)
                || !restoreExpiresAtUtc.HasValue
                || restoreExpiresAtUtc.Value
                    <= _clock.UtcNow)
            {
                reasonCode =
                    "wings_receipt_domain_mismatch";
                return false;
            }
            operation.RestoreToken =
                restoreToken;
            operation.RestoreExpiresAtUtc =
                restoreExpiresAtUtc;
            reasonCode = null;
            return true;
        }

        private async Task<HairObservationCapture>
            CaptureFreshHairObservationAsync(
                ActiveOperation operation,
                ObservationGrantDescriptor grant,
                string priorObservationId,
                bool requireActiveHairdresserPanel = true)
        {
            string reasonCode = null;
            ObservationEnvelope observation = null;
            SessionSnapshot session = null;
            FrameEnvelope frame = null;
            AgentRuntimeDispatchResult captureResult =
                await operation.Connection.DispatchAsync(
                        AgentMethodsV1.ObservationCapture,
                        JsonSerializer.SerializeToElement(
                            new ObservationCaptureParametersV1
                            {
                                ObservationGrantId =
                                    grant.ObservationGrantId,
                                SessionId = _sessionId,
                                TargetId = _hairTargetId,
                                DataScope =
                                    ObservationDataScopesV1.Pixels,
                                AllowValidatedFlashKeyframeFallback =
                                    false
                            },
                            AgentProtocolV1.JsonOptions),
                        operation.Cancellation.Token)
                    .ConfigureAwait(false);
            if (!captureResult.Success
                || !TryDeserialize(
                    captureResult,
                    out observation)
                || !TryGetEligibleHairSnapshot(
                    operation.HairProposal,
                    out session,
                    out _,
                    out reasonCode,
                    requireActiveHairdresserPanel)
                || !ObservationMatchesHair(
                    session,
                    grant,
                    observation,
                    priorObservationId,
                    out frame))
            {
                return HairObservationCapture.Rejected(
                    captureResult.ReasonCode
                        ?? reasonCode
                        ?? "stale_observation");
            }
            return HairObservationCapture.Completed(
                session,
                observation,
                frame);
        }

        private async Task<HairInspectDispatch>
            DispatchHairInspectAsync(
                ActiveOperation operation,
                HairSaveBinding binding)
        {
            HairInspectWireResult wire = null;
            AgentRuntimeDispatchResult dispatch =
                await operation.Connection.DispatchAsync(
                        AgentMethodsV1.HairInspect,
                        JsonSerializer.SerializeToElement(
                            new HairInspectParametersV1
                            {
                                ObservationGrantId =
                                    operation.GrantId,
                                TargetId = _hairTargetId,
                                Binding =
                                    ToParameters(binding)
                            },
                            AgentProtocolV1.JsonOptions),
                        operation.Cancellation.Token)
                    .ConfigureAwait(false);
            if (!dispatch.Success
                || !TryDeserialize(
                    dispatch,
                    out wire)
                || !TryFreezeInspect(
                    wire,
                    binding,
                    out HairInspectResult inspect))
            {
                return HairInspectDispatch.Rejected(
                    dispatch.ReasonCode
                        ?? wire?.ReasonCode
                        ?? "malformed_authority");
            }
            return HairInspectDispatch.Completed(inspect);
        }

        private async Task<HairPreviewDispatch>
            DispatchHairPreviewAsync(
                ActiveOperation operation,
                HairInspectResult inspect,
                string selectedIdentifier)
        {
            HairAuthoritativeSnapshot snapshot =
                inspect.Snapshot;
            HairPreviewWireResult wire = null;
            AgentRuntimeDispatchResult dispatch =
                await operation.Connection.DispatchAsync(
                        AgentMethodsV1.HairPreview,
                        JsonSerializer.SerializeToElement(
                            new HairPreviewParametersV1
                            {
                                ObservationGrantId =
                                    operation.GrantId,
                                TargetId = _hairTargetId,
                                Binding =
                                    ToParameters(
                                        snapshot.Binding),
                                HairIdentifier =
                                    selectedIdentifier,
                                ExpectedCurrentHair =
                                    snapshot.CurrentHair,
                                ExpectedRevision =
                                    snapshot.Revision,
                                ExpectedGeneration =
                                    snapshot.Generation,
                                ExpectedSnapshotHash =
                                    inspect.SnapshotHash
                            },
                            AgentProtocolV1.JsonOptions),
                        operation.Cancellation.Token)
                    .ConfigureAwait(false);
            if (!dispatch.Success
                || !TryDeserialize(
                    dispatch,
                    out wire)
                || !TryFreezePreview(
                    wire,
                    out HairAppearancePreview preview))
            {
                return HairPreviewDispatch.Rejected(
                    dispatch.ReasonCode
                        ?? "domain_revision_conflict");
            }
            return HairPreviewDispatch.Completed(preview);
        }

        private bool TryGetEligibleHairSnapshot(
            LauncherWingsHairPreparationProposal proposal,
            out SessionSnapshot session,
            out SessionSurfaceSnapshot surface,
            out string reasonCode,
            bool requireActiveHairdresserPanel = true)
        {
            session = null;
            surface = null;
            if (_hairTargetId == null)
            {
                reasonCode = "unsupported_for_surface";
                return false;
            }
            session = _surfaces.Registry.GetSnapshot()
                .FindSession(_sessionId);
            if (session == null)
            {
                reasonCode = "session_not_found";
                return false;
            }
            if (session.SessionMode
                == SessionMode.UnattendedTest)
            {
                reasonCode = "session_mismatch";
                return false;
            }
            if (proposal != null
                && (!string.Equals(
                        proposal.SessionId,
                        session.SessionId,
                        StringComparison.Ordinal)
                    || proposal.Expectation
                            .LifecycleGeneration
                        != session.LifecycleGeneration
                    || !string.Equals(
                        proposal.Expectation.AttemptId,
                        session.AttemptId,
                        StringComparison.Ordinal)
                    || proposal.Expectation
                            .AttemptGeneration
                        != session.AttemptGeneration
                    || !string.Equals(
                        proposal.Slot,
                        session.Slot,
                        StringComparison.Ordinal)
                    || !string.Equals(
                        proposal.SaveBindingId,
                        _loreView.Progress.SaveBindingId,
                        StringComparison.Ordinal)
                    || !string.Equals(
                        proposal.LoreViewId,
                        _loreView.LoreViewId,
                        StringComparison.Ordinal)
                    || !string.Equals(
                        proposal.TargetId,
                        _hairTargetId,
                        StringComparison.Ordinal)
                    || (requireActiveHairdresserPanel
                        && (!string.Equals(
                            proposal.PanelName,
                            session.ActivePanelName,
                            StringComparison.Ordinal)
                        || !string.Equals(
                            proposal.PanelInstanceId,
                            session.ActivePanelInstanceId,
                            StringComparison.Ordinal)))))
            {
                reasonCode = "stale_lifecycle";
                return false;
            }
            if (session.LifecycleGeneration == 0
                || string.IsNullOrWhiteSpace(
                    session.AttemptId)
                || !session.AttemptGeneration.HasValue
                || string.IsNullOrWhiteSpace(session.Slot))
            {
                reasonCode = "stale_attempt";
                return false;
            }
            if (session.RuntimeQualification == null
                || session.RuntimeQualification.RuntimeMode
                    == RuntimeMode.UnqualifiedDev)
            {
                reasonCode = "runtime_unqualified";
                return false;
            }
            if (!session.Capabilities.Contains(
                    AgentCapabilitiesV1
                        .AppearanceHairChange,
                    StringComparer.Ordinal))
            {
                reasonCode = "capability_denied";
                return false;
            }
            if (!session.DesktopAvailable)
            {
                reasonCode = "desktop_unavailable";
                return false;
            }
            if (session.HumanReauthorizationRequired)
            {
                reasonCode =
                    "human_intervention_required";
                return false;
            }
            if (session.BlockingModalKind
                != BlockingModalKind.None)
            {
                reasonCode = "blocking_modal";
                return false;
            }
            SessionSurfaceSnapshot[] eligible =
                session.Surfaces.Where(candidate =>
                    candidate.Kind
                        == SurfaceKind.WebOverlay
                    && candidate.SafetyKind
                        == AgentTargetSafetyKind
                            .RuntimeOwned
                    && candidate.InputModes.Contains(
                        InputMode.DomainTransaction))
                    .ToArray();
            if (eligible.Length != 1
                || !string.Equals(
                    eligible[0].TargetId,
                    _hairTargetId,
                    StringComparison.Ordinal))
            {
                reasonCode = "unsupported_for_surface";
                return false;
            }
            surface = eligible[0];
            if (!surface.Visible || surface.Minimized)
            {
                reasonCode = "target_minimized";
                return false;
            }
            if (!surface.ObservationModes.Contains(
                    ObservationMode
                        .WindowGraphicsCapture)
                || (requireActiveHairdresserPanel
                    && (!string.Equals(
                        session.ActivePanelTargetId,
                        _hairTargetId,
                        StringComparison.Ordinal)
                    || !string.Equals(
                        session.ActivePanelName,
                        HairdresserPanelName,
                        StringComparison.Ordinal)
                    || string.IsNullOrWhiteSpace(
                        session.ActivePanelInstanceId))))
            {
                reasonCode = "unsupported_for_surface";
                return false;
            }
            if (!HairAppearanceValidation.IsSafeString(
                    _loreView.Progress.SaveSignature,
                    256,
                    false)
                || !HairAppearanceValidation.IsSha256(
                    _loreView.Progress.SaveSignature
                        .ToLowerInvariant()))
            {
                reasonCode = "cross_save";
                return false;
            }
            reasonCode = null;
            return true;
        }

        private bool TryValidateHairOperationState(
            ActiveOperation operation,
            out string reasonCode)
        {
            reasonCode = null;
            if (operation == null
                || operation.Kind
                    != StructuredOperationKind.HairChange)
            {
                reasonCode = "stale_observation";
                return false;
            }
            if (operation.Phase
                    == OperationPhase.AwaitingProjection)
            {
                if (operation.ActionReceiptId == null
                    || !_resultAuthority.TryResolve(
                        operation.ActionReceiptId,
                        out _,
                        out reasonCode))
                {
                    reasonCode ??=
                        "wings_result_unavailable";
                    return false;
                }
                reasonCode = null;
                return true;
            }
            if (!TryGetEligibleHairSnapshot(
                    operation.HairProposal,
                    out SessionSnapshot session,
                    out _,
                    out reasonCode,
                    requireActiveHairdresserPanel:
                        operation.CommitReceiptId == null))
            {
                reasonCode ??= "stale_observation";
                return false;
            }
            if (operation.Principal != null
                && !IsExactHairPrincipal(
                    operation.Principal))
            {
                reasonCode = "principal_mismatch";
                return false;
            }
            if (operation.GrantId != null
                && (!_grants.TryAuthorize(
                        operation.GrantId,
                        operation.Principal.ClientInstanceId,
                        operation.Principal.SecurityPrincipalId,
                        _sessionId,
                        _hairTargetId,
                        ObservationDataScopesV1.PlayerState,
                        out _,
                        out reasonCode)
                    || !_grants.TryAuthorize(
                        operation.GrantId,
                        operation.Principal.ClientInstanceId,
                        operation.Principal.SecurityPrincipalId,
                        _sessionId,
                        _hairTargetId,
                        ObservationDataScopesV1.Pixels,
                        out _,
                        out reasonCode)))
            {
                return false;
            }
            if (operation.Intent != null
                && !_hairBindingAuthority
                    .TryValidateStableExecutionIdentity(
                        operation.Principal,
                        operation.Intent,
                        out reasonCode))
            {
                return false;
            }
            if (operation.HairObservation != null
                && !ObservationMatchesHair(
                    session,
                    operation.HairGrant,
                    operation.HairObservation,
                    null,
                    out _))
            {
                reasonCode = "stale_observation";
                return false;
            }
            reasonCode = null;
            return true;
        }

        private bool GrantMatchesHair(
            PrincipalCredential principal,
            SessionSnapshot session,
            ObservationGrantDescriptor grant)
        {
            return grant != null
                && AgentContractValidator
                    .Validate(grant).Count == 0
                && grant.State
                    == Contracts.ObservationGrantState.Active
                && string.Equals(
                    grant.OwnerClientId,
                    principal.ClientInstanceId,
                    StringComparison.Ordinal)
                && string.Equals(
                    grant.SecurityPrincipalId,
                    principal.SecurityPrincipalId,
                    StringComparison.Ordinal)
                && grant.SessionScope != null
                && string.Equals(
                    grant.SessionScope.SessionId,
                    session.SessionId,
                    StringComparison.Ordinal)
                && grant.SessionScope.LifecycleGeneration
                    == session.LifecycleGeneration
                && string.Equals(
                    grant.SessionScope.AttemptId,
                    session.AttemptId,
                    StringComparison.Ordinal)
                && grant.SessionScope.AttemptGeneration
                    == session.AttemptGeneration
                && !grant.SessionScope.CrossAttempt
                && grant.TargetScope != null
                && grant.TargetScope.Count == 1
                && string.Equals(
                    grant.TargetScope[0],
                    _hairTargetId,
                    StringComparison.Ordinal)
                && grant.DataScope != null
                && grant.DataScope
                    .ToHashSet(StringComparer.Ordinal)
                    .SetEquals(
                        new[]
                        {
                            ObservationDataScopesV1.PlayerState,
                            ObservationDataScopesV1.Pixels
                        })
                && grant.AllowEphemeralKeyframes
                && !grant.AllowPersistence
                && !grant.AllowExport
                && PrincipalCredentialAuthority
                    .IsExactIssuerReceipt(
                        principal,
                        grant.ConsentReceipt)
                && grant.IssuedMonotonic
                    >= checked(
                        (ulong)principal.IssuedMonotonic)
                && grant.ExpiresMonotonic
                    <= checked(
                        (ulong)principal.ExpiresMonotonic);
        }

        private bool ObservationMatchesHair(
            SessionSnapshot session,
            ObservationGrantDescriptor grant,
            ObservationEnvelope observation,
            string priorObservationId,
            out FrameEnvelope frame)
        {
            frame = null;
            SessionSurfaceSnapshot surface =
                session?.Surfaces.FirstOrDefault(
                    candidate => string.Equals(
                        candidate.TargetId,
                        _hairTargetId,
                        StringComparison.Ordinal));
            if (surface == null
                || grant == null
                || observation == null
                || AgentContractValidator
                    .Validate(observation).Count != 0
                || !string.Equals(
                    observation.ObservationGrantId,
                    grant.ObservationGrantId,
                    StringComparison.Ordinal)
                || !string.Equals(
                    observation.SessionId,
                    session.SessionId,
                    StringComparison.Ordinal)
                || observation.LifecycleGeneration
                    != session.LifecycleGeneration
                || !string.Equals(
                    observation.AttemptId,
                    session.AttemptId,
                    StringComparison.Ordinal)
                || observation.AttemptGeneration
                    != session.AttemptGeneration
                || !string.Equals(
                    observation.TargetId,
                    _hairTargetId,
                    StringComparison.Ordinal)
                || (priorObservationId != null
                    && string.Equals(
                        observation.ObservationId,
                        priorObservationId,
                        StringComparison.Ordinal))
                || observation.SurfaceEpoch
                    != surface.SurfaceEpoch
                || observation.CoordinateSpaceVersion
                    != surface.CoordinateSpaceVersion
                || observation.FocusEpoch
                    != session.FocusEpoch
                || observation.ModalEpoch
                    != session.ModalEpoch
                || !string.Equals(
                    observation.PanelInstanceId,
                    session.PanelInstanceIdForTarget(
                        _hairTargetId),
                    StringComparison.Ordinal)
                || observation.DocumentGeneration
                    != surface.DocumentGeneration
                || observation.SemanticGeneration
                    != surface.SemanticGeneration
                || !observation.Visible
                || observation.Minimized
                || !observation.Active
                || observation.BlockingModalKind
                    != BlockingModalKind.None
                || observation.Frames == null
                || observation.Frames.Count != 1)
            {
                return false;
            }
            frame = observation.Frames[0];
            return frame != null
                && string.Equals(
                    frame.ObservationId,
                    observation.ObservationId,
                    StringComparison.Ordinal)
                && string.Equals(
                    frame.TargetId,
                    _hairTargetId,
                    StringComparison.Ordinal)
                && frame.SourceLayer
                    == SourceLayer.WebOverlay
                && frame.SurfaceEpoch
                    == observation.SurfaceEpoch
                && frame.CoordinateSpaceVersion
                    == observation.CoordinateSpaceVersion
                && HairAppearanceValidation.IsSha256(
                    frame.ContentHash?.ToLowerInvariant())
                && !string.IsNullOrWhiteSpace(
                    frame.OpaqueContentHandle);
        }

        private bool IsExactHairPrincipal(
            PrincipalCredential principal)
        {
            return principal != null
                && principal.PrincipalKind
                    == AgentPrincipalKind.WingsPersona
                && principal.SessionMode
                    == AgentSessionMode.PlayerAssist
                && principal.State
                    == CredentialState.Active
                && string.Equals(
                    principal.SelectedSessionId,
                    _sessionId,
                    StringComparison.Ordinal)
                && principal.AllowedCapabilities
                    .ToHashSet(StringComparer.Ordinal)
                    .SetEquals(HairCapabilities)
                && principal.AllowedTargets.Count == 1
                && string.Equals(
                    principal.AllowedTargets[0],
                    _hairTargetId,
                    StringComparison.Ordinal)
                && principal.ExpiresMonotonic
                    > principal.IssuedMonotonic
                && principal.ExpiresMonotonic
                    - principal.IssuedMonotonic
                    <= (long)HairCredentialLifetime
                        .TotalMilliseconds;
        }

        private WingsActionHostBindingSnapshot
            CreateHairActionBinding(
                SessionSnapshot session,
                ObservationEnvelope observation,
                FrameEnvelope frame,
                HairAppearancePreview preview)
        {
            return new WingsActionHostBindingSnapshot(
                session.SessionId,
                session.LifecycleGeneration,
                session.AttemptId,
                session.AttemptGeneration,
                session.Slot,
                _loreView.Progress.SaveBindingId,
                _loreView.Progress.SaveSignature,
                session.SaveRevision,
                _loreView.LoreViewId,
                _hairTargetId,
                observation.SurfaceEpoch,
                observation.PanelInstanceId,
                observation.DocumentGeneration,
                observation.SemanticSnapshotId,
                observation.SemanticGeneration,
                nodeId: null,
                observation.CoordinateSpaceVersion,
                observation.FocusEpoch,
                observation.ModalEpoch,
                observation.ObservationGrantId,
                observation.ObservationId,
                frame.FrameId,
                new WingsHairActionBinding(
                    preview.TransactionId,
                    preview.PreviewHash,
                    preview.ExpectedRevision.ToString(
                        CultureInfo.InvariantCulture),
                    checked((ulong)
                        preview.ExpectedGeneration),
                    preview.ExpectedSnapshotHash,
                    preview.BeforeHair,
                    preview.AfterHair,
                    HairdresserPanelName));
        }

        private LauncherWingsHairChooserCard
            CreateChooserCard(
                SessionSnapshot session,
                HairInspectResult inspect)
        {
            HairAuthoritativeSnapshot snapshot =
                inspect.Snapshot;
            var seen = new HashSet<string>(
                StringComparer.Ordinal);
            var choices =
                new List<LauncherWingsHairChoice>();
            foreach (HairCatalogEntry entry
                in snapshot.Catalog)
            {
                if (!seen.Add(entry.Identifier))
                    continue;
                choices.Add(
                    new LauncherWingsHairChoice(
                        entry.Identifier,
                        entry.DisplayName,
                        string.Equals(
                            entry.Identifier,
                            snapshot.CurrentHair,
                            StringComparison.Ordinal)));
            }
            return new LauncherWingsHairChooserCard(
                OpaqueIdGenerator.Create("hairchooser"),
                session.SessionId,
                session.Slot,
                _hairTargetId,
                snapshot.CurrentHair,
                snapshot.Revision,
                snapshot.Generation,
                inspect.SnapshotHash,
                choices);
        }

        private static bool TryValidateHairSelection(
            LauncherWingsHairChooserCard card,
            LauncherWingsHairChooserSelection selection,
            out string reasonCode)
        {
            if (selection == null
                || !selection.Selected)
            {
                reasonCode = selection?.ReasonCode
                    ?? "consent_required";
                return false;
            }
            if (!string.Equals(
                    selection.ChooserId,
                    card.ChooserId,
                    StringComparison.Ordinal)
                || string.Equals(
                    selection.HairIdentifier,
                    card.CurrentHair,
                    StringComparison.Ordinal)
                || !card.Choices.Any(choice =>
                    string.Equals(
                        choice.Identifier,
                        selection.HairIdentifier,
                        StringComparison.Ordinal)
                    && !choice.IsCurrent))
            {
                reasonCode = "hair_not_found";
                return false;
            }
            reasonCode = null;
            return true;
        }

        private static bool
            PreviewMatchesInspectAndSelection(
                HairAppearancePreview preview,
                HairInspectResult inspect,
                string selectedIdentifier)
        {
            HairAuthoritativeSnapshot snapshot =
                inspect?.Snapshot;
            return HairAppearanceValidation
                    .PreviewHashIsAuthentic(preview)
                && snapshot != null
                && preview.Binding.Equals(snapshot.Binding)
                && string.Equals(
                    preview.BeforeHair,
                    snapshot.CurrentHair,
                    StringComparison.Ordinal)
                && string.Equals(
                    preview.AfterHair,
                    selectedIdentifier,
                    StringComparison.Ordinal)
                && preview.ExpectedRevision
                    == snapshot.Revision
                && preview.ExpectedGeneration
                    == snapshot.Generation
                && string.Equals(
                    preview.ExpectedSnapshotHash,
                    inspect.SnapshotHash,
                    StringComparison.Ordinal);
        }

        private static SessionMutationExpectation Expectation(
            SessionSnapshot session)
        {
            return new SessionMutationExpectation
            {
                SessionId = session.SessionId,
                LifecycleGeneration =
                    session.LifecycleGeneration,
                AttemptId = session.AttemptId,
                AttemptGeneration =
                    session.AttemptGeneration
            };
        }

        private HairSaveBinding ToHairBinding(
            SessionSnapshot session)
        {
            return new HairSaveBinding(
                session.SessionId,
                checked((long)
                    session.LifecycleGeneration),
                session.AttemptId,
                checked((long)
                    session.AttemptGeneration.Value),
                session.Slot,
                _loreView.Progress.SaveSignature);
        }

        private static HairSaveBindingParametersV1
            ToParameters(HairSaveBinding binding)
        {
            return new HairSaveBindingParametersV1
            {
                SessionId = binding.SessionId,
                LifecycleGeneration =
                    checked((ulong)
                        binding.LifecycleGeneration),
                AttemptId = binding.AttemptId,
                AttemptGeneration =
                    checked((ulong)
                        binding.AttemptGeneration),
                SlotId = binding.SlotId,
                SaveSignature =
                    binding.SaveSignature
            };
        }

        private static bool TryFreezeInspect(
            HairInspectWireResult wire,
            HairSaveBinding expectedBinding,
            out HairInspectResult result)
        {
            result = null;
            if (wire == null
                || !wire.Success
                || wire.Snapshot == null
                || wire.Snapshot.Binding == null
                || wire.Snapshot.Catalog == null
                || wire.Snapshot.Catalog.Any(
                    entry => entry == null))
            {
                return false;
            }
            HairSaveBinding binding =
                wire.Snapshot.Binding.ToDomain();
            var snapshot =
                new HairAuthoritativeSnapshot(
                    binding,
                    wire.Snapshot.Revision,
                    wire.Snapshot.Generation,
                    wire.Snapshot.CurrentHair,
                    wire.Snapshot.Catalog.Select(
                        entry =>
                            new HairCatalogEntry(
                                entry.Identifier,
                                entry.DisplayName)));
            if (!binding.Equals(expectedBinding)
                || !HairAppearanceValidation
                    .IsValidSnapshot(snapshot)
                || !HairAppearanceValidation.IsSha256(
                    wire.SnapshotHash)
                || !string.Equals(
                    HairAppearanceHashing
                        .ComputeSnapshotHash(snapshot),
                    wire.SnapshotHash,
                    StringComparison.Ordinal))
            {
                return false;
            }
            result = HairInspectResult.Succeeded(
                snapshot,
                wire.SnapshotHash);
            return true;
        }

        private static bool TryFreezePreview(
            HairPreviewWireResult wire,
            out HairAppearancePreview preview)
        {
            preview = null;
            if (wire == null || wire.Binding == null)
                return false;
            try
            {
                preview = new HairAppearancePreview(
                    wire.TransactionId,
                    wire.Binding.ToDomain(),
                    wire.BeforeHair,
                    wire.AfterHair,
                    wire.ExpectedRevision,
                    wire.ExpectedGeneration,
                    wire.ExpectedSnapshotHash,
                    wire.PreviewHash,
                    wire.CreatedAtUtc);
            }
            catch
            {
                preview = null;
                return false;
            }
            if (!HairAppearanceValidation
                .PreviewHashIsAuthentic(preview))
            {
                preview = null;
                return false;
            }
            return true;
        }

        private sealed class HairExecutionTerminal
        {
            private HairExecutionTerminal(
                string actionReceiptId,
                ActionReceipt receipt,
                string reasonCode)
            {
                ActionReceiptId = actionReceiptId;
                Receipt = receipt;
                ReasonCode = reasonCode;
            }

            internal bool Success =>
                ActionReceiptId != null
                && Receipt != null;
            internal string ActionReceiptId { get; }
            internal ActionReceipt Receipt { get; }
            internal string ReasonCode { get; }

            internal static HairExecutionTerminal Completed(
                string actionReceiptId,
                ActionReceipt receipt)
            {
                return new HairExecutionTerminal(
                    actionReceiptId,
                    receipt,
                    null);
            }

            internal static HairExecutionTerminal Rejected(
                string reasonCode)
            {
                return new HairExecutionTerminal(
                    null,
                    null,
                    reasonCode);
            }
        }

        private sealed class HairObservationCapture
        {
            private HairObservationCapture(
                SessionSnapshot session,
                ObservationEnvelope observation,
                FrameEnvelope frame,
                string reasonCode)
            {
                Session = session;
                Observation = observation;
                Frame = frame;
                ReasonCode = reasonCode;
            }

            internal bool Success =>
                Session != null
                && Observation != null
                && Frame != null;
            internal SessionSnapshot Session { get; }
            internal ObservationEnvelope Observation { get; }
            internal FrameEnvelope Frame { get; }
            internal string ReasonCode { get; }

            internal static HairObservationCapture Completed(
                SessionSnapshot session,
                ObservationEnvelope observation,
                FrameEnvelope frame)
            {
                return new HairObservationCapture(
                    session,
                    observation,
                    frame,
                    null);
            }

            internal static HairObservationCapture Rejected(
                string reasonCode)
            {
                return new HairObservationCapture(
                    null,
                    null,
                    null,
                    reasonCode);
            }
        }

        private sealed class HairInspectDispatch
        {
            private HairInspectDispatch(
                HairInspectResult result,
                string reasonCode)
            {
                Result = result;
                ReasonCode = reasonCode;
            }

            internal bool Success => Result != null;
            internal HairInspectResult Result { get; }
            internal string ReasonCode { get; }

            internal static HairInspectDispatch Completed(
                HairInspectResult result)
            {
                return new HairInspectDispatch(
                    result,
                    null);
            }

            internal static HairInspectDispatch Rejected(
                string reasonCode)
            {
                return new HairInspectDispatch(
                    null,
                    reasonCode);
            }
        }

        private sealed class HairPreviewDispatch
        {
            private HairPreviewDispatch(
                HairAppearancePreview preview,
                string reasonCode)
            {
                Preview = preview;
                ReasonCode = reasonCode;
            }

            internal bool Success => Preview != null;
            internal HairAppearancePreview Preview { get; }
            internal string ReasonCode { get; }

            internal static HairPreviewDispatch Completed(
                HairAppearancePreview preview)
            {
                return new HairPreviewDispatch(
                    preview,
                    null);
            }

            internal static HairPreviewDispatch Rejected(
                string reasonCode)
            {
                return new HairPreviewDispatch(
                    null,
                    reasonCode);
            }
        }

        private sealed class HairSurfaceFence
        {
            internal HairSurfaceFence(
                SessionSnapshot session,
                SessionSurfaceSnapshot surface,
                bool requirePanelIdentity = true)
            {
                LifecycleGeneration =
                    session.LifecycleGeneration;
                AttemptId = session.AttemptId;
                AttemptGeneration =
                    session.AttemptGeneration;
                Slot = session.Slot;
                SaveRevision = session.SaveRevision;
                SurfaceEpoch = surface.SurfaceEpoch;
                DocumentGeneration =
                    surface.DocumentGeneration;
                SemanticGeneration =
                    surface.SemanticGeneration;
                CoordinateSpaceVersion =
                    surface.CoordinateSpaceVersion;
                PanelInstanceId =
                    session.PanelInstanceIdForTarget(
                        surface.TargetId);
                PanelName = session.ActivePanelName;
                PanelTargetId = session.ActivePanelTargetId;
                RequirePanelIdentity =
                    requirePanelIdentity;
            }

            private ulong LifecycleGeneration { get; }
            private string AttemptId { get; }
            private ulong? AttemptGeneration { get; }
            private string Slot { get; }
            private long? SaveRevision { get; }
            private ulong SurfaceEpoch { get; }
            private ulong? DocumentGeneration { get; }
            private ulong? SemanticGeneration { get; }
            private ulong CoordinateSpaceVersion { get; }
            private string PanelInstanceId { get; }
            private string PanelName { get; }
            private string PanelTargetId { get; }
            private bool RequirePanelIdentity { get; }

            internal bool MatchesAfterSecurityPrompt(
                SessionSnapshot session,
                SessionSurfaceSnapshot surface)
            {
                return session != null
                    && surface != null
                    && session.LifecycleGeneration
                        == LifecycleGeneration
                    && string.Equals(
                        session.AttemptId,
                        AttemptId,
                        StringComparison.Ordinal)
                    && session.AttemptGeneration
                        == AttemptGeneration
                    && string.Equals(
                        session.Slot,
                        Slot,
                        StringComparison.Ordinal)
                    && session.SaveRevision
                        == SaveRevision
                    && surface.SurfaceEpoch
                        == SurfaceEpoch
                    && surface.DocumentGeneration
                        == DocumentGeneration
                    && surface.SemanticGeneration
                        == SemanticGeneration
                    && surface.CoordinateSpaceVersion
                        == CoordinateSpaceVersion
                    && (!RequirePanelIdentity
                        || (string.Equals(
                            session.PanelInstanceIdForTarget(
                                surface.TargetId),
                            PanelInstanceId,
                            StringComparison.Ordinal)
                        && string.Equals(
                            session.ActivePanelName,
                            PanelName,
                            StringComparison.Ordinal)
                        && string.Equals(
                            session.ActivePanelTargetId,
                            PanelTargetId,
                            StringComparison.Ordinal)));
            }
        }

        private sealed class HairInspectWireResult
        {
            public bool Success { get; set; }
            public string ReasonCode { get; set; }
            public HairSnapshotWire Snapshot { get; set; }
            public string SnapshotHash { get; set; }
        }

        private sealed class HairSnapshotWire
        {
            public HairBindingWire Binding { get; set; }
            public long Revision { get; set; }
            public long Generation { get; set; }
            public string CurrentHair { get; set; }
            public List<HairCatalogWire> Catalog { get; set; }
        }

        private sealed class HairBindingWire
        {
            public string SessionId { get; set; }
            public long LifecycleGeneration { get; set; }
            public string AttemptId { get; set; }
            public long AttemptGeneration { get; set; }
            public string SlotId { get; set; }
            public string SaveSignature { get; set; }

            internal HairSaveBinding ToDomain()
            {
                return new HairSaveBinding(
                    SessionId,
                    LifecycleGeneration,
                    AttemptId,
                    AttemptGeneration,
                    SlotId,
                    SaveSignature);
            }
        }

        private sealed class HairCatalogWire
        {
            public string Identifier { get; set; }
            public string DisplayName { get; set; }
        }

        private sealed class HairPreviewWireResult
        {
            public string Operation { get; set; }
            public string TransactionId { get; set; }
            public HairBindingWire Binding { get; set; }
            public string BeforeHair { get; set; }
            public string AfterHair { get; set; }
            public long ExpectedRevision { get; set; }
            public long ExpectedGeneration { get; set; }
            public string ExpectedSnapshotHash { get; set; }
            public string PreviewHash { get; set; }
            public DateTimeOffset CreatedAtUtc { get; set; }
        }

        private sealed class HairTransactionWireResult
        {
            public HairTransactionOutcome Outcome { get; set; }
            public string ReasonCode { get; set; }
            public string ReconcileKind { get; set; }
            public string TransactionId { get; set; }
            public string PreviewHash { get; set; }
            public JsonElement? AuthoritativeInspect { get; set; }
            public string RestoreToken { get; set; }
            public DateTimeOffset? RestoreExpiresAtUtc
            {
                get;
                set;
            }
        }

        private sealed class HairReconcileDispatch
        {
            private HairReconcileDispatch(
                HairTransactionWireResult result,
                string reasonCode)
            {
                Result = result;
                ReasonCode = reasonCode;
            }

            internal bool Success => Result != null;
            internal HairTransactionWireResult Result { get; }
            internal string ReasonCode { get; }

            internal static HairReconcileDispatch Completed(
                HairTransactionWireResult result)
            {
                return new HairReconcileDispatch(
                    result
                        ?? throw new ArgumentNullException(
                            nameof(result)),
                    null);
            }

            internal static HairReconcileDispatch Rejected(
                string reasonCode)
            {
                return new HairReconcileDispatch(
                    null,
                    string.IsNullOrWhiteSpace(reasonCode)
                        ? "domain_reconcile_required"
                        : reasonCode);
            }
        }
    }
}
