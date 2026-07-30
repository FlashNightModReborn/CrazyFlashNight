using System;
using System.Drawing;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Security;
using CF7Launcher.AgentRuntime.Sessions;
using CF7Launcher.AgentRuntime.Wings;

namespace CF7Launcher.AgentRuntime.Integration
{
    /// <summary>
    /// Production composition boundary for the phase-one Wings shell. It owns
    /// only Launcher WinForms, uses the deterministic offline backend, and
    /// registers HWNDs from forms it created. It has no network provider and
    /// performs no process or window discovery.
    /// </summary>
    internal sealed class LauncherWingsRuntimeHost
        : IWingsShellHostActions,
          IDisposable
    {
        private readonly object _sync = new object();
        private readonly Form _owner;
        private readonly SessionSurfaceHostController _surfaces;
        private readonly SessionRegistryHostOwner _registryOwner;
        private readonly string _sessionId;
        private readonly string _wingsTargetId;
        private readonly string _launcherTargetId;
        private readonly LoreView _loreView;
        private readonly Func<string, WingsGuidanceRequest>
            _dialogueRequestFactory;
        private readonly Action<WingsShellEffect>
            _applyPauseEffects;
        private readonly Action _requestFreshActivation;
        private readonly Func<TrustedNeutralConsentPrompt>
            _neutralConsentPromptFactory;
        private readonly DeterministicOfflineWingsBackend
            _offlineBackend;
        private readonly WingsPersonaStateMachine _personaState;
        private readonly WingsShellStateMachine _shellState;
        private readonly SessionOnlyWingsMemory _memory;
        private readonly WingsConsentPresentationPort _consentPort;
        private readonly IDisposable _ownedConsentAuthority;
        private readonly Func<
            PrincipalCredential,
            WingsVirtualAuthenticatedConnection>
                _virtualConnectionFactory;
        private readonly
            ILauncherWingsStructuredActionCoordinator
                _structuredActions;
        private readonly WingsShellHost _shell;
        private WingsShellForm _observedShellForm;
        private WingsVirtualAuthenticatedConnection
            _virtualConnection;
        private bool _surfacePublished;
        private bool _disposed;

        public LauncherWingsRuntimeHost(
            Form owner,
            SessionSurfaceHostController surfaces,
            SessionRegistryHostOwner registryOwner,
            string sessionId,
            string wingsTargetId,
            string launcherTargetId,
            LoreView initialLoreView,
            long storyAuthorityRevision,
            Func<string, WingsGuidanceRequest>
                dialogueRequestFactory,
            Action<WingsShellEffect> applyPauseEffects,
            Action requestFreshActivation,
            Func<TrustedNeutralConsentPrompt>
                neutralConsentPromptFactory,
            INeutralConsentDecisionSink consentDecisionSink,
            INeutralConsentFactsAuthority
                consentFactsAuthority = null,
            ITrustedActionResultAuthority
                actionResultAuthority = null,
            Func<DateTimeOffset> utcNow = null,
            IDisposable ownedConsentAuthority = null,
            Func<
                PrincipalCredential,
                WingsVirtualAuthenticatedConnection>
                    virtualConnectionFactory = null,
            ILauncherWingsStructuredActionCoordinator
                structuredActions = null)
        {
            _owner = owner
                ?? throw new ArgumentNullException(nameof(owner));
            _surfaces = surfaces
                ?? throw new ArgumentNullException(
                    nameof(surfaces));
            _registryOwner = registryOwner
                ?? throw new ArgumentNullException(
                    nameof(registryOwner));
            WingsProtocolValue.RequireOpaqueId(
                sessionId,
                nameof(sessionId));
            WingsProtocolValue.RequireOpaqueId(
                wingsTargetId,
                nameof(wingsTargetId));
            WingsProtocolValue.RequireOpaqueId(
                launcherTargetId,
                nameof(launcherTargetId));
            if (initialLoreView == null)
                throw new ArgumentNullException(
                    nameof(initialLoreView));
            if (storyAuthorityRevision <= 0)
            {
                throw new ArgumentOutOfRangeException(
                    nameof(storyAuthorityRevision));
            }
            _dialogueRequestFactory =
                dialogueRequestFactory
                ?? throw new ArgumentNullException(
                    nameof(dialogueRequestFactory));
            _applyPauseEffects = applyPauseEffects
                ?? throw new ArgumentNullException(
                    nameof(applyPauseEffects));
            _requestFreshActivation =
                requestFreshActivation
                ?? throw new ArgumentNullException(
                    nameof(requestFreshActivation));
            _neutralConsentPromptFactory =
                neutralConsentPromptFactory
                ?? throw new ArgumentNullException(
                    nameof(neutralConsentPromptFactory));
            if (consentDecisionSink == null)
            {
                throw new ArgumentNullException(
                    nameof(consentDecisionSink));
            }
            if (!string.Equals(
                    surfaces.Snapshot.SessionId,
                    sessionId,
                    StringComparison.Ordinal))
            {
                throw new ArgumentException(
                    "Wings session must match the host registry.",
                    nameof(sessionId));
            }

            _sessionId = sessionId;
            _wingsTargetId = wingsTargetId;
            _launcherTargetId = launcherTargetId;
            _loreView = initialLoreView;
            if (structuredActions != null
                && actionResultAuthority != null
                && !ReferenceEquals(
                    structuredActions.ResultAuthority,
                    actionResultAuthority))
            {
                throw new ArgumentException(
                    "The structured action coordinator must own "
                    + "the configured action result authority.",
                    nameof(actionResultAuthority));
            }
            _structuredActions = structuredActions;
            _personaState = new WingsPersonaStateMachine(
                initialLoreView.Progress.StoryPhaseId,
                storyAuthorityRevision,
                initialLoreView.PublicCompanionEligible,
                WingsOperationState.Offline);
            _shellState = new WingsShellStateMachine(
                sessionId,
                readGrantActive: false,
                writeLeaseActive: false,
                pendingActionsExist: false,
                captureRunning: false,
                inferenceRunning: false);
            _shellState.Pause();
            _memory = new SessionOnlyWingsMemory(
                sessionId,
                initialLoreView);
            _offlineBackend =
                new DeterministicOfflineWingsBackend(
                    consentFactsAuthority,
                    structuredActions?.ResultAuthority
                        ?? actionResultAuthority,
                    utcNow: utcNow);
            var publisher =
                new LauncherHumanOnlySurfacePublisher(
                    surfaces,
                    registryOwner);
            _consentPort =
                new WingsConsentPresentationPort(
                    owner,
                    publisher,
                    consentDecisionSink,
                    utcNow);
            _ownedConsentAuthority = ownedConsentAuthority;
            _virtualConnectionFactory =
                virtualConnectionFactory;
            _shell = new WingsShellHost(
                owner,
                _personaState,
                _shellState,
                this,
                _consentPort);
            if (_structuredActions != null)
            {
                _structuredActions.ExecutionStarting +=
                    OnStructuredExecutionStarting;
            }
            _owner.FormClosing += OnOwnerFormClosing;
        }

        public WingsShellSnapshot ShellSnapshot =>
            _shellState.Snapshot;

        public WingsPersonaStateSnapshot PersonaSnapshot =>
            _personaState.Snapshot;

        public bool StructuredWindowActivationAvailable =>
            !IsDisposed()
            && IsSessionEligible()
            && _structuredActions?.IsAvailable == true;

        public bool StructuredHairChangeAvailable =>
            !IsDisposed()
            && IsSessionEligible()
            && _structuredActions
                ?.IsHairChangeAvailable == true;

        internal WingsShellForm FormForTest =>
            _shell.FormForTest;

        internal WingsConsentForm ConsentFormForTest =>
            _consentPort.ActiveFormForTest;

        internal string VirtualConnectionIdForTest
        {
            get
            {
                lock (_sync)
                    return _virtualConnection
                        ?.ConnectionId;
            }
        }

        public bool TryShow(out string reasonCode)
        {
            if (IsDisposed())
            {
                reasonCode = "wings_runtime_disposed";
                return false;
            }
            if (!IsSessionEligible())
            {
                reasonCode = "wings_unavailable";
                return false;
            }
            if (!TryEnterIdle(out reasonCode))
                return false;
            if (!_shell.TryShowShell(out reasonCode))
            {
                TryEnterOffline();
                return false;
            }
            if (!TryPublishShellSurface(out reasonCode))
            {
                _shell.TryPause(out _);
                _shell.TryHidePersona(out _);
                TryUnpublishShellSurface(out _);
                TryEnterOffline();
                return false;
            }
            return true;
        }

        public bool TryHide(out string reasonCode)
        {
            if (IsDisposed())
            {
                reasonCode = "wings_runtime_disposed";
                return false;
            }
            RevokeVirtualConnection(
                "wings_shell_hidden");
            _structuredActions?.Revoke(
                "wings_shell_hidden");
            bool paused = _shell.TryPause(
                out string pauseReason);
            bool hidden = _shell.TryHidePersona(
                out string hideReason);
            bool unpublished = TryUnpublishShellSurface(
                out string unpublishReason);
            TryEnterOffline();
            reasonCode = !paused
                ? pauseReason
                : !hidden
                    ? hideReason
                    : !unpublished
                        ? unpublishReason
                        : null;
            return paused && hidden && unpublished;
        }

        public bool TryPause(out string reasonCode)
        {
            if (IsDisposed())
            {
                reasonCode = "wings_runtime_disposed";
                return false;
            }
            RevokeVirtualConnection(
                "wings_shell_paused");
            _structuredActions?.Revoke(
                "wings_shell_paused");
            return _shell.TryPause(out reasonCode);
        }

        public bool TryResume(out string reasonCode)
        {
            if (IsDisposed())
            {
                reasonCode = "wings_runtime_disposed";
                return false;
            }
            if (!IsSessionEligible())
            {
                reasonCode = "wings_unavailable";
                return false;
            }
            WingsShellForm form = _shell.FormForTest;
            if (form == null
                || form.IsDisposed
                || !form.Visible
                || _shellState.Snapshot.Presentation
                    != WingsPersonaPresentation.Visible)
            {
                reasonCode = "wings_shell_hidden";
                return false;
            }
            if (_shell.TryResume(out reasonCode))
                return true;

            // Resume cannot leave the shell active when fresh activation was
            // not accepted by the trusted Host.
            _shell.TryPause(out _);
            return false;
        }

        public bool TryPresentNeutralConsent(
            TrustedNeutralConsentPrompt prompt,
            out string reasonCode)
        {
            if (IsDisposed())
            {
                reasonCode = "wings_runtime_disposed";
                return false;
            }
            if (!IsSessionEligible())
            {
                reasonCode = "wings_unavailable";
                return false;
            }
            return _shell.TryPresentConsent(
                prompt,
                out reasonCode);
        }

        public bool TryGenerateOfflineAndPresent(
            WingsGuidanceRequest request,
            out WingsBackendResult result,
            out string reasonCode)
        {
            result = null;
            if (request == null)
                throw new ArgumentNullException(nameof(request));
            if (IsDisposed())
            {
                reasonCode = "wings_runtime_disposed";
                return false;
            }
            if (!IsSessionEligible())
            {
                reasonCode = "wings_unavailable";
                return false;
            }
            WingsShellSnapshot shell = _shellState.Snapshot;
            WingsPersonaStateSnapshot persona =
                _personaState.Snapshot;
            if (shell.Paused
                || shell.Presentation
                    != WingsPersonaPresentation.Visible)
            {
                reasonCode = "wings_runtime_paused";
                return false;
            }
            if (!string.Equals(
                    request.SessionId,
                    _sessionId,
                    StringComparison.Ordinal))
            {
                reasonCode =
                    "wings_session_binding_mismatch";
                return false;
            }
            if (!request.LoreView
                    .PublicCompanionEligible
                || !persona.PublicCompanionEligible
                || !string.Equals(
                    request.LoreView.Progress.StoryPhaseId,
                    persona.StoryPhaseId,
                    StringComparison.Ordinal))
            {
                reasonCode =
                    "wings_lore_view_not_eligible";
                return false;
            }

            try
            {
                _personaState.TransitionOperation(
                    WingsOperationState.Advising);
                _memory.TransitionLoreView(
                    _sessionId,
                    request.LoreView);
                WingsBackendResult generated =
                    _offlineBackend.Generate(request);
                if (generated.Source
                    != WingsBackendSource.OfflineReference)
                {
                    throw new InvalidOperationException(
                        "wings_non_offline_backend_rejected");
                }
                if (!_shell.TryAppendCheckedDialogue(
                        generated.Output,
                        out reasonCode))
                {
                    _personaState.TransitionOperation(
                        WingsOperationState.SafeError);
                    return false;
                }
                RememberReceipt(request);
                _personaState.TransitionOperation(
                    WingsOperationState.Idle);
                result = generated;
                reasonCode = null;
                return true;
            }
            catch
            {
                TryEnterSafeError();
                reasonCode = "wings_offline_backend_failed";
                return false;
            }
        }

        public void SubmitDialogue(string text)
        {
            if (IsDisposed())
                return;
            try
            {
                _owner.BeginInvoke(
                    new Action(
                        () => ProcessDialogueOnUi(text)));
            }
            catch
            {
                TryNotifyFailure(
                    "Launcher 正在关闭，未处理这条消息。");
            }
        }

        public void ApplyPauseEffects(
            WingsShellEffect requiredEffects)
        {
            _applyPauseEffects(requiredEffects);
        }

        public void RequestFreshActivation()
        {
            _requestFreshActivation();
        }

        public void RequestNeutralConsentPresentation()
        {
            if (IsDisposed())
                return;
            try
            {
                TrustedNeutralConsentPrompt prompt =
                    _neutralConsentPromptFactory();
                string reason = null;
                if (prompt == null
                    || !_shell.TryPresentConsent(
                        prompt,
                        out reason))
                {
                    if (_ownedConsentAuthority
                        is LauncherWingsPlayerAssistAuthority
                            playerAssist)
                    {
                        playerAssist.Suspend(
                            reason
                                ?? "wings_consent_presentation_failed");
                    }
                    TryNotifyFailure(
                        "中性授权界面暂不可用（"
                            + (reason
                                ?? "prompt_unavailable")
                            + "）。");
                }
            }
            catch
            {
                TryNotifyFailure(
                    "Launcher 暂时无法展示中性授权界面。");
            }
        }

        public void RequestActivateCurrentGameWindow()
        {
            if (IsDisposed())
                return;
            try
            {
                if (_owner.InvokeRequired)
                {
                    _owner.BeginInvoke(
                        new Action(
                            () =>
                                _ =
                                    ProcessStructuredWindowActivationOnUiAsync()));
                }
                else
                {
                    _ =
                        ProcessStructuredWindowActivationOnUiAsync();
                }
            }
            catch
            {
                TryNotifyFailure(
                    "Launcher 正在关闭，未提交激活窗口请求。");
            }
        }

        public void RequestChangeHair()
        {
            if (IsDisposed())
                return;
            try
            {
                if (_owner.InvokeRequired)
                {
                    _owner.BeginInvoke(
                        new Action(
                            () =>
                                _ =
                                    ProcessStructuredHairChangeOnUiAsync()));
                }
                else
                {
                    _ =
                        ProcessStructuredHairChangeOnUiAsync();
                }
            }
            catch
            {
                TryNotifyStructuredHairRejected(
                    "wings_action_unavailable");
            }
        }

        internal void ApplyPlayerAssistAuthorization(
            LoreView loreView,
            WingsPlayerAssistAuthorizationChangedEventArgs change)
        {
            if (change == null || IsDisposed())
                return;
            if (!change.Authorized)
            {
                bool ownActionConsentTransition =
                    string.Equals(
                        change.ReasonCode,
                        "security_surface_appeared",
                        StringComparison.Ordinal)
                    && _structuredActions
                            ?.IsPresentingOwnConsent
                        == true;
                if (!ownActionConsentTransition)
                {
                    _structuredActions?.Revoke(
                        change.ReasonCode
                            ?? "wings_authorization_revoked");
                }
                RevokeVirtualConnection(
                    change.ReasonCode
                        ?? "wings_authorization_revoked");
                _shellState.SuspendReadGrant();
                _shell.RefreshProjectedState();
                return;
            }
            if (!TryActivateVirtualConnection(
                    out string connectionReason))
            {
                RevokeVirtualConnection(
                    connectionReason);
                _shellState.SuspendReadGrant();
                _shell.RefreshProjectedState();
                if (_ownedConsentAuthority
                    is LauncherWingsPlayerAssistAuthority
                        failedAuthority)
                {
                    failedAuthority.Suspend(
                        connectionReason
                            ?? "wings_virtual_connection_failed");
                }
                return;
            }
            try
            {
                _shellState.ActivateReadGrant();
                _shell.RefreshProjectedState();
                TryGenerateOfflineAndPresent(
                    WingsGuidanceRequest
                        .ForAuthorizationExplanation(
                            _sessionId,
                            loreView,
                            change.ReceiptId),
                    out _,
                    out _);
            }
            catch
            {
                RevokeVirtualConnection(
                    "wings_authorization_projection_failed");
                _shellState.SuspendReadGrant();
                _shell.RefreshProjectedState();
            }
        }

        public void Dispose()
        {
            bool dispose;
            lock (_sync)
            {
                dispose = !_disposed;
                if (dispose)
                    _disposed = true;
            }
            if (!dispose)
                return;

            RevokeVirtualConnection(
                "wings_runtime_disposed");
            _structuredActions?.Revoke(
                "wings_runtime_disposed");
            try
            {
                if (!_owner.IsDisposed
                    && _owner.IsHandleCreated)
                {
                    if (_owner.InvokeRequired)
                    {
                        _owner.Invoke(
                            new Action(
                                PauseUnpublishAndDetachOnUi));
                    }
                    else
                    {
                        PauseUnpublishAndDetachOnUi();
                    }
                }
                else
                {
                    PauseWithoutUi();
                    TryUnpublishShellSurface(out _);
                }
            }
            catch
            {
                PauseWithoutUi();
                TryUnpublishShellSurface(out _);
            }
            finally
            {
                _owner.FormClosing -=
                    OnOwnerFormClosing;
                if (_structuredActions != null)
                {
                    _structuredActions.ExecutionStarting -=
                        OnStructuredExecutionStarting;
                    _structuredActions.Dispose();
                }
                _shell.Dispose();
                _memory.Dispose();
                _ownedConsentAuthority?.Dispose();
            }
        }

        private void ProcessDialogueOnUi(string text)
        {
            if (IsDisposed())
                return;
            try
            {
                WingsGuidanceRequest request =
                    _dialogueRequestFactory(text);
                string reason = null;
                if (request == null
                    || !TryGenerateOfflineAndPresent(
                        request,
                        out _,
                        out reason))
                {
                    TryNotifyFailure(
                        "本地指导暂不可用（"
                            + (reason
                                ?? "request_unavailable")
                            + "）。");
                }
            }
            catch
            {
                TryNotifyFailure(
                    "本地指导请求无效，未发送到网络。");
            }
        }

        private async Task
            ProcessStructuredWindowActivationOnUiAsync()
        {
            ILauncherWingsStructuredActionCoordinator coordinator =
                _structuredActions;
            WingsShellSnapshot shell = _shellState.Snapshot;
            WingsPersonaStateSnapshot persona =
                _personaState.Snapshot;
            if (IsDisposed()
                || coordinator == null
                || !coordinator.IsAvailable
                || shell.Paused
                || shell.Presentation
                    != WingsPersonaPresentation.Visible
                || !shell.ReadGrantActive
                || persona.OperationState
                    != WingsOperationState.Idle)
            {
                TryNotifyStructuredActionRejected(
                    "wings_action_unavailable");
                _shell.RefreshProjectedState();
                return;
            }

            try
            {
                _personaState.TransitionOperation(
                    WingsOperationState.AwaitingGrant);
                _shell.RefreshProjectedState();
            }
            catch
            {
                TryNotifyStructuredActionRejected(
                    "wings_operation_state_invalid");
                return;
            }

            LauncherWingsStructuredActionResult result;
            try
            {
                result =
                    await coordinator
                        .ActivateCurrentGameWindowAsync(
                            CancellationToken.None);
            }
            catch
            {
                result =
                    LauncherWingsStructuredActionResult
                        .Rejected("internal_error");
            }

            if (IsDisposed())
                return;
            if (result == null
                || !result.HasTerminalReceipt)
            {
                SettleRejectedStructuredAction();
                TryNotifyStructuredActionRejected(
                    result?.ReasonCode
                        ?? "internal_error");
                return;
            }

            string actionReceiptId =
                result.ActionReceiptId;
            try
            {
                WingsShellSnapshot currentShell =
                    _shellState.Snapshot;
                if (currentShell.Paused
                    || currentShell.Presentation
                        != WingsPersonaPresentation.Visible)
                {
                    SettleRejectedStructuredAction();
                    return;
                }

                WingsOperationState operationState =
                    _personaState.Snapshot
                        .OperationState;
                if (operationState
                    == WingsOperationState.AwaitingGrant)
                {
                    // Defensive fallback for a presentation observer that
                    // could not marshal the execution-start event.
                    _personaState.TransitionOperation(
                        WingsOperationState.Executing);
                    operationState =
                        WingsOperationState.Executing;
                }
                if (operationState
                    != WingsOperationState.Executing)
                {
                    throw new InvalidOperationException(
                        "wings_operation_state_invalid");
                }
                _personaState.TransitionOperation(
                    WingsOperationState.Reporting);
                _shell.RefreshProjectedState();

                if (!TryGenerateOfflineAndPresent(
                        WingsGuidanceRequest.ForActionResult(
                            _sessionId,
                            _loreView,
                            actionReceiptId),
                        out _,
                        out string projectionReason))
                {
                    TryNotifyStructuredActionRejected(
                        projectionReason
                            ?? "wings_result_unavailable");
                }
            }
            catch
            {
                TryEnterSafeError();
                _shell.RefreshProjectedState();
                TryNotifyStructuredActionRejected(
                    "wings_result_projection_invalid");
            }
            finally
            {
                coordinator.CompleteResultProjection(
                    actionReceiptId);
                _shell.RefreshProjectedState();
            }
        }

        private async Task
            ProcessStructuredHairChangeOnUiAsync()
        {
            ILauncherWingsStructuredActionCoordinator coordinator =
                _structuredActions;
            WingsShellSnapshot shell = _shellState.Snapshot;
            WingsPersonaStateSnapshot persona =
                _personaState.Snapshot;
            if (IsDisposed()
                || coordinator == null
                || !coordinator.IsHairChangeAvailable
                || shell.Paused
                || shell.Presentation
                    != WingsPersonaPresentation.Visible
                || !shell.ReadGrantActive
                || persona.OperationState
                    != WingsOperationState.Idle)
            {
                TryNotifyStructuredHairRejected(
                    "wings_action_unavailable");
                _shell.RefreshProjectedState();
                return;
            }

            try
            {
                _personaState.TransitionOperation(
                    WingsOperationState.AwaitingGrant);
                _shell.RefreshProjectedState();
            }
            catch
            {
                TryNotifyStructuredHairRejected(
                    "wings_operation_state_invalid");
                return;
            }

            LauncherWingsStructuredActionResult result;
            try
            {
                result =
                    await coordinator.ChangeHairAsync(
                        CancellationToken.None);
            }
            catch
            {
                result =
                    LauncherWingsStructuredActionResult
                        .Rejected("internal_error");
            }

            if (IsDisposed())
                return;
            if (result == null
                || !result.HasTerminalReceipt)
            {
                SettleRejectedStructuredAction();
                TryNotifyStructuredHairRejected(
                    result?.ReasonCode
                        ?? "internal_error");
                return;
            }

            string actionReceiptId =
                result.ActionReceiptId;
            try
            {
                WingsShellSnapshot currentShell =
                    _shellState.Snapshot;
                if (currentShell.Paused
                    || currentShell.Presentation
                        != WingsPersonaPresentation.Visible)
                {
                    SettleRejectedStructuredAction();
                    return;
                }

                WingsOperationState operationState =
                    _personaState.Snapshot
                        .OperationState;
                if (operationState
                    == WingsOperationState.AwaitingGrant)
                {
                    _personaState.TransitionOperation(
                        WingsOperationState.Executing);
                    operationState =
                        WingsOperationState.Executing;
                }
                if (operationState
                    != WingsOperationState.Executing)
                {
                    throw new InvalidOperationException(
                        "wings_operation_state_invalid");
                }
                _personaState.TransitionOperation(
                    WingsOperationState.Reporting);
                _shell.RefreshProjectedState();

                if (!TryGenerateOfflineAndPresent(
                        WingsGuidanceRequest.ForActionResult(
                            _sessionId,
                            _loreView,
                            actionReceiptId),
                        out _,
                        out string projectionReason))
                {
                    TryNotifyStructuredHairRejected(
                        projectionReason
                            ?? "wings_result_unavailable");
                }
            }
            catch
            {
                TryEnterSafeError();
                _shell.RefreshProjectedState();
                TryNotifyStructuredHairRejected(
                    "wings_result_projection_invalid");
            }
            finally
            {
                coordinator.CompleteResultProjection(
                    actionReceiptId);
                _shell.RefreshProjectedState();
            }
        }

        private void OnStructuredExecutionStarting(
            object sender,
            EventArgs args)
        {
            bool accepted = false;
            bool marshalled = InvokeOnOwner(
                () =>
                {
                    WingsShellSnapshot shell =
                        _shellState.Snapshot;
                    if (!IsDisposed()
                        && !shell.Paused
                        && shell.Presentation
                            == WingsPersonaPresentation.Visible
                        && _personaState.Snapshot
                                .OperationState
                            == WingsOperationState.AwaitingGrant)
                    {
                        _personaState.TransitionOperation(
                            WingsOperationState.Executing);
                        _shell.RefreshProjectedState();
                        accepted = true;
                    }
                },
                "wings_execution_projection_failed",
                out _);
            if (!marshalled || !accepted)
            {
                _structuredActions?.Revoke(
                    "human_intervention_required");
            }
        }

        private void SettleRejectedStructuredAction()
        {
            try
            {
                WingsOperationState current =
                    _personaState.Snapshot.OperationState;
                if (current
                    == WingsOperationState.AwaitingGrant)
                {
                    _personaState.TransitionOperation(
                        WingsOperationState.Idle);
                }
                else if (current
                    is WingsOperationState.Executing
                    or WingsOperationState.Reporting)
                {
                    _personaState.TransitionOperation(
                        WingsOperationState.SafeError);
                }
            }
            catch
            {
                TryEnterSafeError();
            }
            _shell.RefreshProjectedState();
        }

        private void TryNotifyStructuredActionRejected(
            string reasonCode)
        {
            try
            {
                _shell.TryNotify(
                    new WingsShellNotification(
                        WingsNotificationKind.Permission,
                        "未执行“激活游戏窗口”（"
                            + (string.IsNullOrWhiteSpace(
                                    reasonCode)
                                ? "request_rejected"
                                : reasonCode)
                            + "）；未保留写权限。"),
                    out _);
            }
            catch
            {
            }
        }

        private void TryNotifyStructuredHairRejected(
            string reasonCode)
        {
            try
            {
                _shell.TryNotify(
                    new WingsShellNotification(
                        WingsNotificationKind.Permission,
                        "发型事务未继续（"
                            + (string.IsNullOrWhiteSpace(
                                    reasonCode)
                                ? "request_rejected"
                                : reasonCode)
                            + "）；真实提交结果只按受信收据显示。"),
                    out _);
            }
            catch
            {
            }
        }

        private bool TryPublishShellSurface(
            out string reasonCode)
        {
            return InvokeOnOwner(
                () =>
                {
                    WingsShellForm form =
                        _shell.FormForTest;
                    if (form == null
                        || form.IsDisposed
                        || !form.IsHandleCreated
                        || !form.Visible
                        || !_owner.IsHandleCreated)
                    {
                        throw new InvalidOperationException(
                            "wings_shell_surface_unavailable");
                    }
                    AttachShellEventsOnUi(form);
                    Rectangle client =
                        form.RectangleToScreen(
                            form.ClientRectangle);
                    _surfaces.SynchronizeSurface(
                        new SessionSurfaceHostRegistration
                        {
                            TargetId = _wingsTargetId,
                            Kind = SurfaceKind.WingsShell,
                            SafetyKind =
                                AgentTargetSafetyKind
                                    .RuntimeOwned,
                            OwnerRelation =
                                SessionSurfaceOwnerRelation
                                    .LauncherOwned,
                            OwnerProcess =
                                _registryOwner
                                    .LauncherProcess,
                            WindowHandle =
                                form.Handle.ToInt64(),
                            OwnerTargetId =
                                _launcherTargetId,
                            OwnerWindowHandle =
                                _owner.Handle.ToInt64(),
                            BoundsPhysical =
                                Rect(form.Bounds),
                            ClientRectPhysical =
                                Rect(client),
                            ContentRectPhysical =
                                Rect(client),
                            Dpi = form.DeviceDpi,
                            ZIndex = 40,
                            Visible = true,
                            Minimized = false,
                            ObservationModes = new[]
                            {
                                ObservationMode
                                    .WindowGraphicsCapture
                            },
                            InputModes =
                                _surfaces.Snapshot
                                    .RuntimeQualification
                                    .RuntimeMode
                                    == RuntimeMode
                                        .UnqualifiedDev
                                    ? Array.Empty<InputMode>()
                                    : new[]
                                    {
                                        InputMode
                                            .SendInputGuarded
                                    }
                        });
                    lock (_sync)
                        _surfacePublished = true;
                },
                "wings_surface_publish_failed",
                out reasonCode);
        }

        private bool TryUnpublishShellSurface(
            out string reasonCode)
        {
            bool published;
            lock (_sync)
            {
                published = _surfacePublished;
                _surfacePublished = false;
            }
            if (!published)
            {
                reasonCode = null;
                return true;
            }
            try
            {
                _surfaces.RemoveSurface(
                    _wingsTargetId);
                reasonCode = null;
                return true;
            }
            catch
            {
                reasonCode =
                    "wings_surface_unpublish_failed";
                return false;
            }
        }

        private void AttachShellEventsOnUi(
            WingsShellForm form)
        {
            if (ReferenceEquals(
                    _observedShellForm,
                    form))
            {
                return;
            }
            DetachShellEventsOnUi();
            _observedShellForm = form;
            form.VisibleChanged +=
                OnShellVisibleChanged;
            form.LocationChanged +=
                OnShellLayoutChanged;
            form.SizeChanged +=
                OnShellLayoutChanged;
        }

        private void DetachShellEventsOnUi()
        {
            WingsShellForm form =
                _observedShellForm;
            _observedShellForm = null;
            if (form == null)
                return;
            form.VisibleChanged -=
                OnShellVisibleChanged;
            form.LocationChanged -=
                OnShellLayoutChanged;
            form.SizeChanged -=
                OnShellLayoutChanged;
        }

        private void OnShellVisibleChanged(
            object sender,
            EventArgs e)
        {
            if (sender is not WingsShellForm form
                || form.Visible)
            {
                return;
            }
            PauseAndUnpublishOnUi();
        }

        private void OnShellLayoutChanged(
            object sender,
            EventArgs e)
        {
            if (sender is WingsShellForm form
                && form.Visible
                && !IsDisposed())
            {
                TryPublishShellSurface(out _);
            }
        }

        private void OnOwnerFormClosing(
            object sender,
            FormClosingEventArgs e)
        {
            PauseAndUnpublishOnUi();
        }

        private void PauseUnpublishAndDetachOnUi()
        {
            PauseAndUnpublishOnUi();
            DetachShellEventsOnUi();
        }

        private void PauseAndUnpublishOnUi()
        {
            _structuredActions?.Revoke(
                "wings_indicator_closed");
            RevokeVirtualConnection(
                "wings_shell_paused");
            if (!_shellState.Snapshot.Paused)
                _shell.TryPause(out _);
            TryUnpublishShellSurface(out _);
            TryEnterOffline();
        }

        private void PauseWithoutUi()
        {
            _structuredActions?.Revoke(
                "wings_shell_paused");
            RevokeVirtualConnection(
                "wings_shell_paused");
            WingsShellTransition transition =
                _shellState.Pause();
            try
            {
                _applyPauseEffects(
                    transition.RequiredEffects);
            }
            catch
            {
                // The state remains paused. External authority cleanup also
                // runs from the composer's shutdown revocation path.
            }
            TryEnterOffline();
        }

        private bool TryActivateVirtualConnection(
            out string reasonCode)
        {
            reasonCode = null;
            if (_virtualConnectionFactory == null
                || _ownedConsentAuthority
                    is not LauncherWingsPlayerAssistAuthority
                        authority
                || !authority.TryGetActiveCredential(
                    out PrincipalCredential credential,
                    out reasonCode))
            {
                reasonCode ??=
                    "wings_virtual_connection_unavailable";
                return false;
            }

            WingsVirtualAuthenticatedConnection replacement =
                null;
            try
            {
                replacement =
                    _virtualConnectionFactory(credential);
                if (replacement == null
                    || !ReferenceEquals(
                        replacement.Principal,
                        credential))
                {
                    reasonCode =
                        "wings_virtual_connection_invalid";
                    TryRevokeVirtualConnection(
                        replacement,
                        reasonCode);
                    return false;
                }

                WingsVirtualAuthenticatedConnection retired;
                lock (_sync)
                {
                    if (_disposed)
                    {
                        reasonCode =
                            "wings_runtime_disposed";
                        retired = null;
                    }
                    else
                    {
                        retired = _virtualConnection;
                        _virtualConnection = replacement;
                        replacement = null;
                        reasonCode = null;
                    }
                }
                TryRevokeVirtualConnection(
                    retired,
                    "wings_credential_rotated");
                if (replacement != null)
                {
                    TryRevokeVirtualConnection(
                        replacement,
                        reasonCode);
                    return false;
                }
                return true;
            }
            catch
            {
                TryRevokeVirtualConnection(
                    replacement,
                    "wings_virtual_connection_failed");
                reasonCode =
                    "wings_virtual_connection_failed";
                return false;
            }
        }

        private void RevokeVirtualConnection(
            string reasonCode)
        {
            WingsVirtualAuthenticatedConnection connection;
            lock (_sync)
            {
                connection = _virtualConnection;
                _virtualConnection = null;
            }
            TryRevokeVirtualConnection(
                connection,
                reasonCode);
        }

        private static void TryRevokeVirtualConnection(
            WingsVirtualAuthenticatedConnection connection,
            string reasonCode)
        {
            if (connection == null)
                return;
            try
            {
                connection.RevokeAsync(
                        reasonCode)
                    .AsTask()
                    .GetAwaiter()
                    .GetResult();
            }
            catch
            {
                try
                {
                    connection.Dispose();
                }
                catch
                {
                }
            }
        }

        private bool TryEnterIdle(out string reasonCode)
        {
            try
            {
                WingsPersonaStateSnapshot current =
                    _personaState.Snapshot;
                if (!current.PublicCompanionEligible)
                {
                    reasonCode =
                        "wings_public_companion_ineligible";
                    return false;
                }
                if (current.OperationState
                    == WingsOperationState.Offline)
                {
                    _personaState.TransitionOperation(
                        WingsOperationState.Idle);
                }
                else if (current.OperationState
                    == WingsOperationState.SafeError)
                {
                    _personaState.TransitionOperation(
                        WingsOperationState.Idle);
                }
                else if (current.OperationState
                    != WingsOperationState.Idle)
                {
                    reasonCode =
                        "wings_operation_state_invalid";
                    return false;
                }
                reasonCode = null;
                return true;
            }
            catch
            {
                reasonCode =
                    "wings_operation_state_invalid";
                return false;
            }
        }

        private void TryEnterOffline()
        {
            try
            {
                WingsOperationState current =
                    _personaState.Snapshot
                        .OperationState;
                if (current
                    is WingsOperationState.Observing
                    or WingsOperationState.Advising
                    or WingsOperationState.AwaitingGrant
                    or WingsOperationState.Executing
                    or WingsOperationState.Reporting)
                {
                    _personaState.TransitionOperation(
                        WingsOperationState.SafeError);
                    current =
                        WingsOperationState.SafeError;
                }
                if (current
                    == WingsOperationState.Idle
                    || current
                        == WingsOperationState.SafeError)
                {
                    _personaState.TransitionOperation(
                        WingsOperationState.Offline);
                }
            }
            catch
            {
            }
        }

        private void TryEnterSafeError()
        {
            try
            {
                WingsOperationState current =
                    _personaState.Snapshot
                        .OperationState;
                if (current
                    != WingsOperationState.SafeError)
                {
                    _personaState.TransitionOperation(
                        WingsOperationState.SafeError);
                }
            }
            catch
            {
            }
        }

        private void RememberReceipt(
            WingsGuidanceRequest request)
        {
            if (request.NeutralPermissionReceiptId
                != null)
            {
                _memory.Remember(
                    _sessionId,
                    request.LoreView,
                    WingsMemoryKey
                        .LastConsentReceiptId,
                    request.NeutralPermissionReceiptId);
            }
            if (request.ActionReceiptId != null)
            {
                _memory.Remember(
                    _sessionId,
                    request.LoreView,
                    WingsMemoryKey
                        .LastActionReceiptId,
                    request.ActionReceiptId);
            }
        }

        private void TryNotifyFailure(string text)
        {
            try
            {
                _shell.TryNotify(
                    new WingsShellNotification(
                        WingsNotificationKind.Error,
                        text),
                    out _);
            }
            catch
            {
            }
        }

        private bool InvokeOnOwner(
            Action action,
            string failureReason,
            out string reasonCode)
        {
            try
            {
                if (_owner.IsDisposed
                    || !_owner.IsHandleCreated)
                {
                    reasonCode =
                        "wings_shell_owner_unavailable";
                    return false;
                }
                if (_owner.InvokeRequired)
                    _owner.Invoke(action);
                else
                    action();
                reasonCode = null;
                return true;
            }
            catch
            {
                reasonCode = failureReason;
                return false;
            }
        }

        private bool IsDisposed()
        {
            lock (_sync)
                return _disposed;
        }

        private bool IsSessionEligible()
        {
            try
            {
                SessionSnapshot snapshot = _surfaces.Snapshot;
                return snapshot.SessionMode
                        != SessionMode.UnattendedTest
                    && string.Equals(
                        snapshot.SessionId,
                        _sessionId,
                        StringComparison.Ordinal);
            }
            catch
            {
                return false;
            }
        }

        private static SessionPhysicalRect Rect(
            Rectangle value)
        {
            return new SessionPhysicalRect(
                value.X,
                value.Y,
                value.Width,
                value.Height);
        }
    }
}
