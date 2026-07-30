using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Domain;
using CF7Launcher.AgentRuntime.Gateway;
using CF7Launcher.AgentRuntime.NativeInput;
using CF7Launcher.AgentRuntime.Security;
using CF7Launcher.AgentRuntime.Sessions;
using CF7Launcher.AgentRuntime.Wings;

namespace CF7Launcher.AgentRuntime.Integration
{
    internal sealed class LauncherWingsStructuredActionResult
    {
        private LauncherWingsStructuredActionResult(
            string actionReceiptId,
            string reasonCode)
        {
            ActionReceiptId = actionReceiptId;
            ReasonCode = reasonCode;
        }

        public bool HasTerminalReceipt =>
            ActionReceiptId != null;
        public string ActionReceiptId { get; }
        public string ReasonCode { get; }

        internal static LauncherWingsStructuredActionResult
            Completed(string actionReceiptId)
        {
            WingsProtocolValue.RequireOpaqueId(
                actionReceiptId,
                nameof(actionReceiptId));
            return new LauncherWingsStructuredActionResult(
                actionReceiptId,
                null);
        }

        internal static LauncherWingsStructuredActionResult
            Rejected(string reasonCode)
        {
            return new LauncherWingsStructuredActionResult(
                null,
                string.IsNullOrWhiteSpace(reasonCode)
                    ? "internal_error"
                    : reasonCode);
        }
    }

    /// <summary>
    /// Closed router for the two product slices owned by this coordinator.
    /// It does not accept a caller-selected authority or operation family.
    /// </summary>
    internal sealed class LauncherWingsActionBindingRouter
        : IWingsActionBindingAuthority
    {
        private readonly IWingsActionBindingAuthority
            _windowActivation;
        private readonly IWingsActionBindingAuthority _hair;

        internal LauncherWingsActionBindingRouter(
            IWingsActionBindingAuthority windowActivation,
            IWingsActionBindingAuthority hair)
        {
            _windowActivation = windowActivation
                ?? throw new ArgumentNullException(
                    nameof(windowActivation));
            _hair = hair;
        }

        public bool TryValidate(
            PrincipalCredential principal,
            WingsActionIntentV1 intent,
            out string reasonCode)
        {
            if (intent?.Operation
                is AgentMethodsV1.HairCommit
                    or AgentMethodsV1.HairRestore)
            {
                if (_hair == null)
                {
                    reasonCode =
                        "wings_action_binding_unavailable";
                    return false;
                }
                return _hair.TryValidate(
                    principal,
                    intent,
                    out reasonCode);
            }
            if (intent?.Operation
                == AgentCapabilitiesV1.ActivateWindow)
            {
                return _windowActivation.TryValidate(
                    principal,
                    intent,
                    out reasonCode);
            }
            reasonCode =
                "wings_action_binding_unavailable";
            return false;
        }
    }

    /// <summary>
    /// Deliberately narrow production API. There is no generic template key,
    /// operation, target, arguments, or dialogue entry point. The only Hair
    /// API is the fixed no-argument ChangeHairAsync product flow.
    /// </summary>
    internal interface ILauncherWingsStructuredActionCoordinator
        : IDisposable
    {
        bool IsAvailable { get; }
        bool IsHairChangeAvailable { get; }
        bool IsPresentingOwnConsent { get; }
        ITrustedActionResultAuthority ResultAuthority { get; }
        event EventHandler ExecutionStarting;

        Task<LauncherWingsStructuredActionResult>
            ActivateCurrentGameWindowAsync(
                CancellationToken cancellationToken);

        Task<LauncherWingsStructuredActionResult>
            ChangeHairAsync(
                CancellationToken cancellationToken);

        void CompleteResultProjection(
            string actionReceiptId);

        void Revoke(string reasonCode);
    }

    /// <summary>
    /// Host-owned vertical slice for exactly one allow-listed action:
    /// window.activate on the current registered Flash target with {}.
    ///
    /// The security modal is intentionally phase one. Only after it is closed,
    /// unpublished and reauthorized does this coordinator issue a separate
    /// short write credential/virtual connection, attach it, issue an exact
    /// pixel grant, capture a fresh one-use observation, mint the immutable
    /// intent and acquire a one-action lease through the shared dispatcher.
    /// The long-lived Wings lore credential is only a prerequisite and is
    /// never widened or reused for execution.
    /// </summary>
    internal sealed partial class LauncherWingsStructuredActionCoordinator
        : ILauncherWingsStructuredActionCoordinator
    {
        internal const string ActivationTemplateKey =
            "wings.action.window.activate.v1";
        internal const string HairdresserPanelName =
            "hairdresser";
        private static readonly TimeSpan ApprovalLifetime =
            TimeSpan.FromSeconds(60);
        private static readonly TimeSpan CredentialLifetime =
            TimeSpan.FromSeconds(30);
        private static readonly TimeSpan ProjectionLifetime =
            TimeSpan.FromSeconds(10);
        private const int IntentLifetimeMilliseconds = 15_000;
        private const int GrantLifetimeMilliseconds = 30_000;

        private static readonly TimeSpan HairCredentialLifetime =
            TimeSpan.FromMinutes(5);
        private const int HairIntentLifetimeMilliseconds = 60_000;
        private const int HairGrantLifetimeMilliseconds = 300_000;

        private static readonly string[] ActivationCapabilities =
        {
            AgentCapabilitiesV1.ActivateWindow,
            AgentCapabilitiesV1.LeaseAcquire,
            AgentCapabilitiesV1.LeaseRelease,
            AgentCapabilitiesV1.ObservationCapture,
            AgentCapabilitiesV1.ObservationGrantManage,
            AgentCapabilitiesV1.SessionAttach,
            AgentCapabilitiesV1.SessionStatus,
            "observe:" + ObservationDataScopesV1.Pixels
        };
        private static readonly string[] HairCapabilities =
        {
            AgentCapabilitiesV1.AppearanceHairChange,
            AgentCapabilitiesV1.LeaseAcquire,
            AgentCapabilitiesV1.LeaseRelease,
            AgentCapabilitiesV1.ObservationCapture,
            AgentCapabilitiesV1.ObservationGrantManage,
            AgentCapabilitiesV1.SessionAttach,
            AgentCapabilitiesV1.SessionStatus,
            "observe:" + ObservationDataScopesV1.PlayerState,
            "observe:" + ObservationDataScopesV1.Pixels
        };

        private readonly object _sync = new object();
        private readonly IAgentRuntimeClock _clock;
        private readonly SessionSurfaceHostController _surfaces;
        private readonly LauncherWingsPlayerAssistAuthority
            _readAuthority;
        private readonly HostPrincipalEnrollmentVerifier
            _verifier;
        private readonly PrincipalCredentialAuthority
            _credentials;
        private readonly ObservationGrantBroker _grants;
        private readonly IExternalInputObservationSource
            _nativeGuard;
        private readonly Func<
            PrincipalCredential,
            WingsVirtualAuthenticatedConnection>
                _connectionFactory;
        private readonly IWingsWindowActivationConsentPresenter
            _presenter;
        private readonly IDisposable _ownedPresenter;
        private readonly Func<IWingsStructuredActionIndicator>
            _indicatorFactory;
        private readonly Func<IWingsStructuredActionIndicator>
            _hairIndicatorFactory;
        private readonly ILauncherWingsHairInteractionPresenter
            _hairPresenter;
        private readonly IDisposable _ownedHairPresenter;
        private readonly string _sessionId;
        private readonly string _targetId;
        private readonly string _hairTargetId;
        private readonly long
            _trustedInteractionOwnerWindowHandle;
        private readonly LoreView _loreView;
        private readonly WingsActionIntentV1.HostFactory
            _intentFactory;
        private readonly WingsActionConsentTrustDomain
            _consentTrustDomain =
                new WingsActionConsentTrustDomain();
        private readonly WingsActionReceiptTrustDomain
            _receiptTrustDomain =
                new WingsActionReceiptTrustDomain();
        private readonly
            LauncherWingsWindowActivationBindingAuthority
                _bindingAuthority;
        private readonly WingsActionIntentV1.HostFactory
            _hairIntentFactory;
        private readonly LauncherWingsHairActionBindingAuthority
            _hairBindingAuthority;
        private readonly LauncherWingsHairConsentEvidenceAuthority
            _hairConsentEvidenceAuthority;
        private readonly LauncherWingsActionBindingRouter
            _bindingRouter;
        private readonly
            SessionOnlyTrustedWingsActionResultAuthority
                _resultAuthority;
        private readonly EventHandler<
            WingsPlayerAssistAuthorizationChangedEventArgs>
                _readAuthorizationChanged;
        private readonly EventHandler<
            SessionSurfaceRegistryChangedEventArgs>
                _registryChanged;
        private readonly Action<ExternalInputObservation>
            _externalInputObserved;
        private ActiveOperation _active;
        private ActiveOperation _revoking;
        private bool _disposed;
        private Action _terminalReceiptRecordedBeforeAdoptionForTest;
        private Action _terminalReceiptAdoptedForTest;

        internal LauncherWingsStructuredActionCoordinator(
            Form owner,
            IAgentRuntimeClock clock,
            SessionSurfaceHostController surfaces,
            SessionRegistryHostOwner registryOwner,
            LauncherWingsPlayerAssistAuthority readAuthority,
            HostPrincipalEnrollmentVerifier verifier,
            PrincipalCredentialAuthority credentials,
            ObservationGrantBroker grants,
            NativeInputGuard nativeGuard,
            Func<
                PrincipalCredential,
                WingsVirtualAuthenticatedConnection>
                    connectionFactory,
            string sessionId,
            string targetId,
            LoreView loreView)
            : this(
                clock,
                surfaces,
                readAuthority,
                verifier,
                credentials,
                grants,
                nativeGuard,
                connectionFactory,
                sessionId,
                targetId,
                loreView,
                new LauncherWingsWindowActivationConsentPresenter(
                    owner
                        ?? throw new ArgumentNullException(
                            nameof(owner)),
                    clock,
                    surfaces,
                    registryOwner),
                () =>
                    new LauncherWingsStructuredActionIndicator(
                        owner),
                ownsPresenter: true,
                trustedInteractionOwnerWindowHandle:
                    owner.Handle.ToInt64())
        {
        }

        internal LauncherWingsStructuredActionCoordinator(
            Form owner,
            IAgentRuntimeClock clock,
            SessionSurfaceHostController surfaces,
            SessionRegistryHostOwner registryOwner,
            LauncherWingsPlayerAssistAuthority readAuthority,
            HostPrincipalEnrollmentVerifier verifier,
            PrincipalCredentialAuthority credentials,
            ObservationGrantBroker grants,
            NativeInputGuard nativeGuard,
            Func<
                PrincipalCredential,
                WingsVirtualAuthenticatedConnection>
                    connectionFactory,
            string sessionId,
            string targetId,
            string hairTargetId,
            LoreView loreView)
            : this(
                clock,
                surfaces,
                readAuthority,
                verifier,
                credentials,
                grants,
                nativeGuard,
                connectionFactory,
                sessionId,
                targetId,
                loreView,
                new LauncherWingsWindowActivationConsentPresenter(
                    owner
                        ?? throw new ArgumentNullException(
                            nameof(owner)),
                    clock,
                    surfaces,
                    registryOwner),
                () =>
                    new LauncherWingsStructuredActionIndicator(
                        owner),
                ownsPresenter: true,
                hairTargetId: hairTargetId,
                hairPresenter:
                    new LauncherWingsHairChooserPresenter(
                        owner,
                        clock,
                        surfaces,
                        registryOwner),
                hairIndicatorFactory:
                    () =>
                        new LauncherWingsStructuredActionIndicator(
                            owner,
                            WingsStructuredActionIndicatorKind
                                .HairChange),
                ownsHairPresenter: true,
                trustedInteractionOwnerWindowHandle:
                    owner.Handle.ToInt64())
        {
        }

        internal LauncherWingsStructuredActionCoordinator(
            IAgentRuntimeClock clock,
            SessionSurfaceHostController surfaces,
            LauncherWingsPlayerAssistAuthority readAuthority,
            HostPrincipalEnrollmentVerifier verifier,
            PrincipalCredentialAuthority credentials,
            ObservationGrantBroker grants,
            IExternalInputObservationSource nativeGuard,
            Func<
                PrincipalCredential,
                WingsVirtualAuthenticatedConnection>
                    connectionFactory,
            string sessionId,
            string targetId,
            LoreView loreView,
            IWingsWindowActivationConsentPresenter presenter,
            Func<IWingsStructuredActionIndicator>
                indicatorFactory,
            bool ownsPresenter = false,
            string hairTargetId = null,
            ILauncherWingsHairInteractionPresenter
                hairPresenter = null,
            Func<IWingsStructuredActionIndicator>
                hairIndicatorFactory = null,
            bool ownsHairPresenter = false,
            long trustedInteractionOwnerWindowHandle = 0)
        {
            _clock = clock
                ?? throw new ArgumentNullException(nameof(clock));
            _surfaces = surfaces
                ?? throw new ArgumentNullException(nameof(surfaces));
            _readAuthority = readAuthority
                ?? throw new ArgumentNullException(
                    nameof(readAuthority));
            _verifier = verifier
                ?? throw new ArgumentNullException(nameof(verifier));
            _credentials = credentials
                ?? throw new ArgumentNullException(
                    nameof(credentials));
            _grants = grants
                ?? throw new ArgumentNullException(nameof(grants));
            _nativeGuard = nativeGuard
                ?? throw new ArgumentNullException(
                    nameof(nativeGuard));
            _connectionFactory = connectionFactory
                ?? throw new ArgumentNullException(
                    nameof(connectionFactory));
            WingsProtocolValue.RequireOpaqueId(
                sessionId,
                nameof(sessionId));
            WingsProtocolValue.RequireOpaqueId(
                targetId,
                nameof(targetId));
            _loreView = loreView
                ?? throw new ArgumentNullException(nameof(loreView));
            _presenter = presenter
                ?? throw new ArgumentNullException(
                    nameof(presenter));
            _indicatorFactory = indicatorFactory
                ?? throw new ArgumentNullException(
                    nameof(indicatorFactory));
            _ownedPresenter = ownsPresenter
                ? presenter as IDisposable
                    ?? throw new ArgumentException(
                        "Owned presenter must be disposable.",
                        nameof(presenter))
                : null;
            _sessionId = sessionId;
            _targetId = targetId;
            _trustedInteractionOwnerWindowHandle =
                trustedInteractionOwnerWindowHandle;
            if ((hairTargetId == null)
                != (hairPresenter == null))
            {
                throw new ArgumentException(
                    "Hair target and presenter must be configured together.");
            }
            if (hairTargetId != null)
            {
                WingsProtocolValue.RequireOpaqueId(
                    hairTargetId,
                    nameof(hairTargetId));
                _hairTargetId = hairTargetId;
                _hairPresenter = hairPresenter;
                _hairIndicatorFactory =
                    hairIndicatorFactory
                    ?? indicatorFactory;
                _ownedHairPresenter = ownsHairPresenter
                    ? hairPresenter as IDisposable
                        ?? throw new ArgumentException(
                            "Owned Hair presenter must be disposable.",
                            nameof(hairPresenter))
                    : null;
            }
            else if (ownsHairPresenter)
            {
                throw new ArgumentException(
                    "A Hair presenter is required when ownership is requested.",
                    nameof(ownsHairPresenter));
            }

            _intentFactory =
                new WingsActionIntentV1.HostFactory(
                    clock,
                    new WingsActionTemplateCatalog(
                        new[]
                        {
                            new WingsActionTemplate(
                                ActivationTemplateKey,
                                AgentCapabilitiesV1
                                    .ActivateWindow,
                                "Activate the exact current CF7 game window.",
                                WingsActionLeaseKind.GuiInput,
                                IntentLifetimeMilliseconds)
                        }));
            _bindingAuthority =
                new LauncherWingsWindowActivationBindingAuthority(
                    clock,
                    surfaces,
                    credentials,
                    grants,
                    sessionId,
                    targetId,
                    loreView,
                    ActivationCapabilities);
            if (_hairTargetId != null)
            {
                _hairIntentFactory =
                    new WingsActionIntentV1.HostFactory(
                        clock,
                        new WingsActionTemplateCatalog(
                            new[]
                            {
                                new WingsActionTemplate(
                                    LauncherWingsHairActionBindingAuthority
                                        .CommitTemplateKey,
                                    AgentMethodsV1.HairCommit,
                                    "Commit the exact frozen Hair preview.",
                                    WingsActionLeaseKind
                                        .DomainTransaction,
                                    HairIntentLifetimeMilliseconds),
                                new WingsActionTemplate(
                                    LauncherWingsHairActionBindingAuthority
                                        .RestoreTemplateKey,
                                    AgentMethodsV1.HairRestore,
                                    "Restore the exact committed Hair transaction.",
                                    WingsActionLeaseKind
                                        .DomainTransaction,
                                    HairIntentLifetimeMilliseconds)
                            }));
                _hairBindingAuthority =
                    new LauncherWingsHairActionBindingAuthority(
                        clock,
                        surfaces,
                        credentials,
                        grants,
                        sessionId,
                        _hairTargetId,
                        HairdresserPanelName,
                        loreView,
                        HairCapabilities);
                _hairConsentEvidenceAuthority =
                    new LauncherWingsHairConsentEvidenceAuthority(
                        clock,
                        sessionId,
                        _hairTargetId);
            }
            _bindingRouter =
                new LauncherWingsActionBindingRouter(
                    _bindingAuthority,
                    _hairBindingAuthority);
            var projector =
                new TrustedWingsActionReceiptAuthority(
                    _receiptTrustDomain,
                    _bindingRouter);
            _resultAuthority =
                new SessionOnlyTrustedWingsActionResultAuthority(
                    sessionId,
                    projector,
                    clock,
                    ProjectionLifetime);

            _readAuthorizationChanged =
                OnReadAuthorizationChanged;
            _registryChanged = OnRegistryChanged;
            _externalInputObserved = OnExternalInputObserved;
            _readAuthority.AuthorizationChanged +=
                _readAuthorizationChanged;
            _surfaces.Registry.Changed += _registryChanged;
            _nativeGuard.ExternalInputObserved +=
                _externalInputObserved;
        }

        public event EventHandler ExecutionStarting;

        public ITrustedActionResultAuthority ResultAuthority =>
            _resultAuthority;

        public bool IsPresentingOwnConsent
        {
            get
            {
                lock (_sync)
                {
                    return !_disposed
                        && _active?.Phase
                            is OperationPhase.PresentingConsent
                                or OperationPhase
                                    .PresentingHairConsent
                                or OperationPhase
                                    .PresentingRestoreConsent;
                }
            }
        }

        public bool IsAvailable
        {
            get
            {
                lock (_sync)
                {
                    if (_disposed
                        || _active != null
                        || _revoking != null)
                        return false;
                }
                return TryGetEligibleSnapshot(
                        null,
                        out _,
                        out _)
                    && TryReadPrerequisite(out _);
            }
        }

        public bool IsHairChangeAvailable
        {
            get
            {
                lock (_sync)
                {
                    if (_disposed
                        || _hairTargetId == null
                        || _active != null
                        || _revoking != null)
                    {
                        return false;
                    }
                }
                return TryGetEligibleHairSnapshot(
                        null,
                        out _,
                        out _,
                        out _)
                    && TryReadPrerequisite(out _);
            }
        }

        internal PrincipalCredential ActiveCredentialForTest
        {
            get
            {
                lock (_sync)
                    return _active?.Principal;
            }
        }

        internal string ActiveConnectionIdForTest
        {
            get
            {
                lock (_sync)
                    return _active?.Connection?.ConnectionId;
            }
        }

        internal WingsActionIntentV1 ActiveIntentForTest
        {
            get
            {
                lock (_sync)
                    return _active?.Intent;
            }
        }

        internal string ActiveActionReceiptIdForTest
        {
            get
            {
                lock (_sync)
                    return _active?.ActionReceiptId;
            }
        }

        internal string ActiveCommitReceiptIdForTest
        {
            get
            {
                lock (_sync)
                    return _active?.CommitReceiptId;
            }
        }

        internal string ActiveHairTargetIdForTest =>
            _hairTargetId;
        internal Action TerminalReceiptRecordedBeforeAdoptionForTest
        {
            get => _terminalReceiptRecordedBeforeAdoptionForTest;
            set => _terminalReceiptRecordedBeforeAdoptionForTest = value;
        }
        internal Action TerminalReceiptAdoptedForTest
        {
            get => _terminalReceiptAdoptedForTest;
            set => _terminalReceiptAdoptedForTest = value;
        }

        public async Task<LauncherWingsStructuredActionResult>
            ActivateCurrentGameWindowAsync(
                CancellationToken cancellationToken)
        {
            if (!TryBeginOperation(
                    StructuredOperationKind.WindowActivation,
                    cancellationToken,
                    out ActiveOperation operation,
                    out string reasonCode))
            {
                return LauncherWingsStructuredActionResult
                    .Rejected(reasonCode);
            }

            try
            {
                if (!TryGetEligibleSnapshot(
                        null,
                        out SessionSnapshot beforeConsent,
                        out reasonCode)
                    || !TryReadPrerequisite(out reasonCode))
                {
                    return await RejectAndCleanupAsync(
                            operation,
                            reasonCode)
                        .ConfigureAwait(false);
                }

                var expectation =
                    new SessionMutationExpectation
                    {
                        SessionId = beforeConsent.SessionId,
                        LifecycleGeneration =
                            beforeConsent
                                .LifecycleGeneration,
                        AttemptId =
                            beforeConsent.AttemptId,
                        AttemptGeneration =
                            beforeConsent
                                .AttemptGeneration
                    };
                DateTimeOffset issued = _clock.UtcNow;
                var proposal =
                    new LauncherWingsWindowActivationProposal(
                        expectation,
                        beforeConsent.Slot,
                        _loreView.Progress.SaveBindingId,
                        _loreView.LoreViewId,
                        _targetId,
                        issued,
                        issued.Add(ApprovalLifetime));
                operation.Proposal = proposal;

                LauncherWingsWindowActivationApproval approval =
                    await _presenter.PresentAsync(
                            proposal,
                            operation.TrustedInteractionTicket,
                            operation.Cancellation.Token)
                        .ConfigureAwait(false);
                string interactionFenceFailure =
                    await SealTrustedHumanInteractionAsync(
                            operation,
                            OperationPhase.PresentingConsent)
                        .ConfigureAwait(false);
                if (interactionFenceFailure != null)
                {
                    return await RejectAndCleanupAsync(
                            operation,
                            interactionFenceFailure)
                        .ConfigureAwait(false);
                }
                if (!IsCurrent(operation))
                {
                    return await RejectAndCleanupAsync(
                            operation,
                            "credential_revoked")
                        .ConfigureAwait(false);
                }
                if (approval == null || !approval.Approved)
                {
                    return await RejectAndCleanupAsync(
                            operation,
                            approval?.ReasonCode
                                ?? "consent_required")
                        .ConfigureAwait(false);
                }
                if (_clock.UtcNow >= proposal.ExpiresAtUtc
                    || !TryGetEligibleSnapshot(
                        proposal,
                        out SessionSnapshot current,
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
                        _indicatorFactory();
                }
                catch
                {
                    operation.Indicator = null;
                }
                if (operation.Indicator == null
                    || !operation.Indicator.TryShow(
                        _clock.UtcNow.Add(
                            CredentialLifetime),
                        CredentialLifetime,
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
                    string consentReceipt =
                        OpaqueIdGenerator.Create(
                            "actionconsent");
                    var evidence =
                        new PlayerAssistCredentialEvidence
                        {
                            ClientInstanceId =
                                OpaqueIdGenerator.Create(
                                    "wingsactionclient"),
                            ConsentReceipt = consentReceipt,
                            SelectedSessionId = _sessionId,
                            AllowedCapabilities =
                                ActivationCapabilities,
                            AllowedTargets =
                                new[] { _targetId },
                            RequestedLifetime =
                                CredentialLifetime
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

                if (!IsExactActionPrincipal(principal)
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

                if (!TryGetEligibleSnapshot(
                        proposal,
                        out current,
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
                                            _targetId
                                        },
                                    TargetKinds = null,
                                    DataScopes =
                                        new List<string>
                                        {
                                            ObservationDataScopesV1
                                                .Pixels
                                        },
                                    RequestedTtlMs =
                                        GrantLifetimeMilliseconds,
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
                    || !GrantMatches(
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
                operation.Phase =
                    OperationPhase.GrantActive;

                AgentRuntimeDispatchResult captureResult =
                    await operation.Connection.DispatchAsync(
                            AgentMethodsV1.ObservationCapture,
                            JsonSerializer.SerializeToElement(
                                new ObservationCaptureParametersV1
                                {
                                    ObservationGrantId =
                                        grant
                                            .ObservationGrantId,
                                    SessionId = _sessionId,
                                    TargetId = _targetId,
                                    DataScope =
                                        ObservationDataScopesV1
                                            .Pixels,
                                    AllowValidatedFlashKeyframeFallback =
                                        false
                                },
                                AgentProtocolV1.JsonOptions),
                            operation.Cancellation.Token)
                        .ConfigureAwait(false);
                if (!captureResult.Success
                    || !TryDeserialize(
                        captureResult,
                        out ObservationEnvelope observation)
                    || !TryGetEligibleSnapshot(
                        proposal,
                        out current,
                        out reasonCode)
                    || !ObservationMatches(
                        current,
                        grant,
                        observation,
                        out FrameEnvelope frame))
                {
                    return await RejectAndCleanupAsync(
                            operation,
                            captureResult.ReasonCode
                                ?? reasonCode
                                ?? "stale_observation")
                        .ConfigureAwait(false);
                }
                operation.Phase =
                    OperationPhase.ObservationCaptured;

                WingsActionHostBindingSnapshot binding =
                    CreateBinding(
                        current,
                        observation,
                        frame);
                JsonElement emptyArguments =
                    JsonSerializer.SerializeToElement(
                        new EmptyParametersV1(),
                        AgentProtocolV1.JsonOptions);
                if (!_intentFactory.TryIssue(
                        ActivationTemplateKey,
                        binding,
                        emptyArguments,
                        out WingsActionIntentV1 intent,
                        out reasonCode)
                    || !_bindingAuthority.TryRegister(
                        principal,
                        intent,
                        observation,
                        frame,
                        out reasonCode)
                    || !_bindingAuthority.TryValidate(
                        principal,
                        intent,
                        out reasonCode))
                {
                    return await RejectAndCleanupAsync(
                            operation,
                            reasonCode
                                ?? "wings_action_binding_unavailable")
                        .ConfigureAwait(false);
                }
                operation.Intent = intent;
                operation.Phase =
                    OperationPhase.IntentAuthorized;

                TrustedWingsActionAuthorization authorization =
                    _consentTrustDomain.Seal(
                        intent,
                        principal,
                        approval.HumanInteractionReceiptId,
                        approval.ReauthorizationReceiptId,
                        _clock.MonotonicMilliseconds);
                var executor =
                    new WingsStructuredActionExecutor(
                        _clock,
                        _bindingAuthority,
                        operation.Connection,
                        _consentTrustDomain,
                        _receiptTrustDomain);

                if (!_bindingAuthority
                        .TryBeginExpectedActivation(
                            principal,
                            intent,
                            out reasonCode))
                {
                    return await RejectAndCleanupAsync(
                            operation,
                            reasonCode
                                ?? "stale_observation")
                        .ConfigureAwait(false);
                }
                operation.Phase = OperationPhase.Executing;
                RaiseExecutionStarting();
                WingsStructuredActionExecutionResult execution =
                    await executor.ExecuteAsync(
                            authorization,
                            operation.Cancellation.Token)
                        .ConfigureAwait(false);
                if (!execution.HasTerminalReceipt
                    || !_bindingAuthority.TryMarkTerminal(
                        principal,
                        intent,
                        execution.BrokeredReceipt,
                        _receiptTrustDomain,
                        out reasonCode)
                    || !TryRecordAndAdoptTerminalReceipt(
                        operation,
                        principal,
                        intent,
                        execution.BrokeredReceipt,
                        commitReceipt: false,
                        out string actionReceiptId,
                        out reasonCode))
                {
                    return await RejectAndCleanupAsync(
                            operation,
                            execution.ReasonCode
                                ?? reasonCode
                                ?? "wings_terminal_receipt_required")
                        .ConfigureAwait(false);
                }

                operation.Phase =
                    OperationPhase.AwaitingProjection;
                ScheduleProjectionExpiry(operation);
                return LauncherWingsStructuredActionResult
                    .Completed(actionReceiptId);
            }
            catch (OperationCanceledException)
            {
                return await RejectAndCleanupAsync(
                        operation,
                        "credential_revoked")
                    .ConfigureAwait(false);
            }
            catch
            {
                return await RejectAndCleanupAsync(
                        operation,
                        "internal_error")
                    .ConfigureAwait(false);
            }
        }

        private bool TryRecordAndAdoptTerminalReceipt(
            ActiveOperation operation,
            PrincipalCredential principal,
            WingsActionIntentV1 intent,
            WingsBrokeredActionReceipt evidence,
            bool commitReceipt,
            out string actionReceiptId,
            out string reasonCode)
        {
            bool consumePreemption = false;
            lock (_sync)
            {
                actionReceiptId = null;
                if (_disposed
                    || !ReferenceEquals(_active, operation)
                    || operation.Phase != OperationPhase.Executing
                    || operation.TerminalProjectionConcluded)
                {
                    reasonCode = "credential_revoked";
                    return false;
                }
                if (!_resultAuthority.TryRecord(
                        principal,
                        intent,
                        evidence,
                        out actionReceiptId,
                        out reasonCode))
                {
                    return false;
                }
                operation.TerminalReceiptRecordedAwaitingAdoption =
                    true;

                // This hook exists solely to exercise the former adoption
                // gap. It runs while the coordinator lock is held, so a
                // re-entrant external-input callback can write its tombstone
                // but cannot make the just-recorded receipt disappear.
                try
                {
                    _terminalReceiptRecordedBeforeAdoptionForTest
                        ?.Invoke();
                }
                catch
                {
                    // Test/presentation observers never affect authority.
                }

                if (_disposed
                    || !ReferenceEquals(_active, operation))
                {
                    operation
                        .TerminalReceiptRecordedAwaitingAdoption =
                            false;
                    _resultAuthority.Remove(actionReceiptId);
                    actionReceiptId = null;
                    reasonCode = "credential_revoked";
                    return false;
                }
                if (operation.TerminalProjectionConcluded)
                {
                    operation
                        .TerminalReceiptRecordedAwaitingAdoption =
                            false;
                    string concludedReceiptId =
                        PreferredTerminalReceipt(operation);
                    if (!string.Equals(
                            actionReceiptId,
                            concludedReceiptId,
                            StringComparison.Ordinal))
                    {
                        _resultAuthority.Remove(
                            actionReceiptId);
                    }
                    actionReceiptId =
                        concludedReceiptId;
                    reasonCode =
                        concludedReceiptId == null
                            ? "credential_revoked"
                            : null;
                    return concludedReceiptId != null;
                }
                operation.TerminalReceiptRecordedAwaitingAdoption =
                    false;
                operation.ActionReceiptId = actionReceiptId;
                if (commitReceipt)
                {
                    operation.CommitReceiptId =
                        actionReceiptId;
                }
                try
                {
                    _terminalReceiptAdoptedForTest
                        ?.Invoke();
                }
                catch
                {
                    // Test/presentation observers never affect authority.
                }
                if (operation.TerminalProjectionPreempted)
                {
                    operation.TerminalProjectionPreempted =
                        false;
                    operation.TerminalProjectionConcluded =
                        true;
                    operation.Phase =
                        OperationPhase.AwaitingProjection;
                    consumePreemption = true;
                }
                reasonCode = null;
            }
            if (consumePreemption)
            {
                BeginTerminalProjectionRevocation(
                    operation,
                    PreferredTerminalReceipt(operation),
                    "credential_revoked");
            }
            return true;
        }

        public void CompleteResultProjection(
            string actionReceiptId)
        {
            ActiveOperation operation;
            lock (_sync)
            {
                operation = _active;
                if (_disposed
                    || operation == null
                    || operation.Phase
                        != OperationPhase.AwaitingProjection
                    || !string.Equals(
                        operation.ActionReceiptId,
                        actionReceiptId,
                        StringComparison.Ordinal))
                {
                    return;
                }
            }
            _resultAuthority.Remove(actionReceiptId);
            _ = FinalizeOperationRevocationAsync(
                operation,
                "credential_revoked");
        }

        public void Revoke(string reasonCode)
        {
            PreemptOperation(reasonCode);
        }

        private void PreemptOperation(string reasonCode)
        {
            ActiveOperation operation;
            string terminalReceiptId = null;
            bool executingWithoutAdoptedTerminal = false;
            bool preserveRecordedTerminalReceipt = false;
            lock (_sync)
            {
                operation = _active;
                if (operation == null)
                    return;
                terminalReceiptId =
                    PreferredTerminalReceipt(operation);
                if (terminalReceiptId != null)
                {
                    operation.TerminalProjectionPreempted =
                        false;
                    operation.TerminalProjectionConcluded =
                        true;
                    operation.Phase =
                        OperationPhase.AwaitingProjection;
                    operation.TryCancelExecution();
                }
                else if (operation.Phase
                    == OperationPhase.Executing)
                {
                    preserveRecordedTerminalReceipt =
                        operation
                            .TerminalReceiptRecordedAwaitingAdoption;
                    operation.TerminalProjectionPreempted =
                        preserveRecordedTerminalReceipt;
                    operation.TerminalProjectionConcluded =
                        !preserveRecordedTerminalReceipt;
                    operation.TryCancelExecution();
                    executingWithoutAdoptedTerminal = true;
                }
            }
            if (terminalReceiptId != null)
            {
                BeginTerminalProjectionRevocation(
                    operation,
                    terminalReceiptId,
                    reasonCode);
                return;
            }
            if (executingWithoutAdoptedTerminal)
            {
                // A tombstone is only valid for a receipt that has already
                // passed TryRecord's complete HMAC/binding projection and is
                // inside the tiny record-to-adopt gap. Before that point
                // there is no terminal fact to preserve: clear all projected
                // authority. In both cases live grants, credentials,
                // connection, indicator and security surface are revoked
                // immediately, without waiting for a cooperative executor.
                if (!preserveRecordedTerminalReceipt)
                    _resultAuthority.RevokeSession();
                BeginLiveResourceRevocation(
                    operation,
                    reasonCode);
                return;
            }
            _resultAuthority.RevokeSession();
            _ = FinalizeOperationRevocationAsync(
                operation,
                reasonCode);
        }

        private Task FinalizeOperationRevocationAsync(
            ActiveOperation operation,
            string reasonCode)
        {
            if (operation == null)
                return Task.CompletedTask;
            lock (_sync)
            {
                if (ReferenceEquals(_active, operation))
                {
                    _active = null;
                    _revoking = operation;
                }
                else if (!ReferenceEquals(
                    _revoking,
                    operation))
                {
                    return operation
                        .FinalizationCompletion.Task;
                }
            }
            operation.TryCancel();
            if (!operation.TryBeginFinalization())
            {
                return operation
                    .FinalizationCompletion.Task;
            }
            BeginLiveResourceRevocation(
                operation,
                reasonCode);
            _ = FinalizeAfterLiveRevocationAsync(
                operation);
            return operation.FinalizationCompletion.Task;
        }

        public void Dispose()
        {
            ActiveOperation operation;
            lock (_sync)
            {
                if (_disposed)
                    return;
                _disposed = true;
                operation = _active ?? _revoking;
            }
            _readAuthority.AuthorizationChanged -=
                _readAuthorizationChanged;
            _surfaces.Registry.Changed -= _registryChanged;
            _nativeGuard.ExternalInputObserved -=
                _externalInputObserved;
            if (operation != null)
            {
                _ = FinalizeOperationRevocationAsync(
                    operation,
                    "credential_revoked");
            }
            else
            {
                _bindingAuthority.Clear();
                _hairBindingAuthority?.Clear();
            }
            _resultAuthority.RevokeSession();
            _ownedPresenter?.Dispose();
            _ownedHairPresenter?.Dispose();
            _resultAuthority.Dispose();
        }

        private bool TryBeginOperation(
            StructuredOperationKind kind,
            CancellationToken cancellationToken,
            out ActiveOperation operation,
            out string reasonCode)
        {
            lock (_sync)
            {
                operation = null;
                if (_disposed)
                {
                    reasonCode = "credential_revoked";
                    return false;
                }
                if (_active != null
                    || _revoking != null)
                {
                    reasonCode = "lease_busy";
                    return false;
                }
                operation =
                    new ActiveOperation(
                        kind,
                        cancellationToken,
                        _nativeGuard
                            .ObservedExternalInputSequence,
                        _trustedInteractionOwnerWindowHandle);
                _active = operation;
                reasonCode = null;
                return true;
            }
        }

        private async Task<LauncherWingsStructuredActionResult>
            RejectAndCleanupAsync(
                ActiveOperation operation,
                string reasonCode)
        {
            string terminalReceiptId =
                operation?.ActionReceiptId
                ?? operation?.CommitReceiptId;
            if (terminalReceiptId != null)
            {
                return FinishWithProjection(
                    operation,
                    terminalReceiptId);
            }
            string normalized = string.IsNullOrWhiteSpace(
                    reasonCode)
                ? "internal_error"
                : reasonCode;
            lock (_sync)
            {
                if (ReferenceEquals(_active, operation))
                {
                    _active = null;
                    _revoking = operation;
                }
            }
            operation.TryCancel();
            _resultAuthority.RevokeSession();
            await FinalizeOperationRevocationAsync(
                    operation,
                    NormalizeRevocationReason(normalized))
                .ConfigureAwait(false);
            return LauncherWingsStructuredActionResult
                .Rejected(normalized);
        }

        private void BeginTerminalProjectionRevocation(
            ActiveOperation operation,
            string actionReceiptId,
            string reasonCode)
        {
            if (operation == null
                || string.IsNullOrWhiteSpace(
                    actionReceiptId))
            {
                return;
            }
            string discardedActionReceiptId = null;
            string discardedCommitReceiptId = null;
            lock (_sync)
            {
                if (_disposed
                    || !ReferenceEquals(_active, operation))
                {
                    return;
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
                operation.TerminalProjectionPreempted =
                    false;
                operation.TerminalProjectionConcluded =
                    true;
                operation.Phase =
                    OperationPhase.AwaitingProjection;
                operation.TryCancelExecution();
            }
            _resultAuthority.Remove(
                discardedActionReceiptId);
            _resultAuthority.Remove(
                discardedCommitReceiptId);
            ScheduleProjectionExpiry(operation);
            BeginLiveResourceRevocation(
                operation,
                reasonCode);
        }

        private void BeginLiveResourceRevocation(
            ActiveOperation operation,
            string reasonCode)
        {
            if (operation == null
                || !operation.TryBeginLiveRevocation())
            {
                return;
            }
            string normalized =
                NormalizeRevocationReason(reasonCode);
            operation.TryCancelExecution();
            operation.TrustedInteractionTicket?.Revoke();
            RevokeExactInteractionSurface(operation);
            _bindingAuthority.Clear();
            _hairBindingAuthority?.Clear();

            if (operation.GrantId != null)
            {
                try
                {
                    _grants.Revoke(
                        operation.GrantId,
                        normalized);
                }
                catch
                {
                }
            }
            if (operation.Principal != null)
            {
                try
                {
                    _credentials.Revoke(
                        operation.Principal.CredentialId,
                        normalized);
                }
                catch
                {
                }
            }
            try
            {
                operation.Indicator?.Close();
            }
            catch
            {
            }

            Task connectionRevocation =
                Task.CompletedTask;
            if (operation.Connection != null)
            {
                try
                {
                    connectionRevocation =
                        operation.Connection
                            .RevokeAsync(normalized)
                            .AsTask();
                }
                catch
                {
                    try
                    {
                        operation.Connection.Dispose();
                    }
                    catch
                    {
                    }
                }
            }
            operation.ClearHairSensitiveState();
            _ = CompleteLiveResourceRevocationAsync(
                operation,
                connectionRevocation);
        }

        private async Task CompleteLiveResourceRevocationAsync(
            ActiveOperation operation,
            Task connectionRevocation)
        {
            try
            {
                try
                {
                    await connectionRevocation
                        .ConfigureAwait(false);
                }
                catch
                {
                    try
                    {
                        operation.Connection?.Dispose();
                    }
                    catch
                    {
                    }
                }
                try
                {
                    await Task.Run(
                            () => operation.Indicator
                                ?.Dispose())
                        .ConfigureAwait(false);
                }
                catch
                {
                }
            }
            finally
            {
                operation.LiveRevocationCompletion
                    .TrySetResult(true);
            }
        }

        private async Task FinalizeAfterLiveRevocationAsync(
            ActiveOperation operation)
        {
            try
            {
                await operation.LiveRevocationCompletion.Task
                    .ConfigureAwait(false);
                operation.TryCancel();
                operation.Dispose();
            }
            finally
            {
                lock (_sync)
                {
                    if (ReferenceEquals(
                            _revoking,
                            operation))
                    {
                        _revoking = null;
                    }
                }
                operation.FinalizationCompletion
                    .TrySetResult(true);
            }
        }

        private void RevokeExactInteractionSurface(
            ActiveOperation operation)
        {
            string targetId =
                operation?.TrustedInteractionSurfaceTargetId;
            if (targetId == null
                || !_surfaces.Registry
                    .TryGetRegisteredSurface(
                        _sessionId,
                        targetId,
                        out SessionSurfaceSnapshot surface)
                || surface.SafetyKind
                    != AgentTargetSafetyKind
                        .HumanOnlySecuritySurface
                || surface.Kind != SurfaceKind.BusinessModal
                || surface.WindowHandle
                    != operation
                        .TrustedInteractionWindowHandle
                || surface.SurfaceEpoch
                    != operation
                        .TrustedInteractionSurfaceEpoch)
            {
                return;
            }
            try
            {
                _surfaces.RemoveSurface(targetId);
            }
            catch
            {
            }
        }

        private static string PreferredTerminalReceipt(
            ActiveOperation operation)
        {
            if (operation == null)
                return null;
            return operation.Kind
                    == StructuredOperationKind.HairChange
                ? operation.CommitReceiptId
                    ?? operation.ActionReceiptId
                : operation.ActionReceiptId;
        }

        private async Task<MinimalSessionReference>
            ResolveMinimalSessionAsync(
                ActiveOperation operation,
                CancellationToken cancellationToken)
        {
            AgentRuntimeDispatchResult result =
                await operation.Connection.DispatchAsync(
                        AgentCapabilitiesV1.SessionStatus,
                        JsonSerializer.SerializeToElement(
                            new EmptyParametersV1(),
                            AgentProtocolV1.JsonOptions),
                        cancellationToken)
                    .ConfigureAwait(false);
            if (!result.Success
                || !TryDeserialize(
                    result,
                    out MinimalSessionReference minimal))
            {
                return null;
            }
            return minimal;
        }

        private bool TryReadPrerequisite(
            out string reasonCode)
        {
            if (!_readAuthority.TryGetActiveCredential(
                    out PrincipalCredential readCredential,
                    out reasonCode))
            {
                return false;
            }
            if (readCredential == null
                || readCredential.State
                    != CredentialState.Active
                || !string.Equals(
                    readCredential.SelectedSessionId,
                    _sessionId,
                    StringComparison.Ordinal))
            {
                reasonCode = "credential_revoked";
                return false;
            }
            reasonCode = null;
            return true;
        }

        private bool TryGetEligibleSnapshot(
            LauncherWingsWindowActivationProposal proposal,
            out SessionSnapshot session,
            out string reasonCode)
        {
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
                        _targetId,
                        StringComparison.Ordinal)))
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
                    AgentCapabilitiesV1.ActivateWindow,
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
            SessionSurfaceSnapshot surface =
                FindTarget(session);
            if (surface == null)
            {
                reasonCode = "target_not_found";
                return false;
            }
            if (!surface.Visible || surface.Minimized)
            {
                reasonCode = "target_minimized";
                return false;
            }
            if (surface.Kind != SurfaceKind.Flash
                || surface.SafetyKind
                    != AgentTargetSafetyKind.RuntimeOwned
                || !surface.ObservationModes.Contains(
                    ObservationMode.WindowGraphicsCapture)
                || !surface.InputModes.Contains(
                    InputMode.SendInputGuarded))
            {
                reasonCode = "unsupported_for_surface";
                return false;
            }
            reasonCode = null;
            return true;
        }

        private bool GrantMatches(
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
                    _targetId,
                    StringComparison.Ordinal)
                && grant.DataScope != null
                && grant.DataScope.Count == 1
                && string.Equals(
                    grant.DataScope[0],
                    ObservationDataScopesV1.Pixels,
                    StringComparison.Ordinal)
                && grant.AllowEphemeralKeyframes
                && !grant.AllowPersistence
                && !grant.AllowExport
                && PrincipalCredentialAuthority
                    .IsExactIssuerReceipt(
                        principal,
                        grant.ConsentReceipt)
                && grant.IssuedMonotonic
                    >= checked((ulong)principal.IssuedMonotonic)
                && grant.ExpiresMonotonic
                    <= checked((ulong)principal.ExpiresMonotonic);
        }

        private bool ObservationMatches(
            SessionSnapshot session,
            ObservationGrantDescriptor grant,
            ObservationEnvelope observation,
            out FrameEnvelope frame)
        {
            frame = null;
            SessionSurfaceSnapshot surface =
                FindTarget(session);
            if (surface == null
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
                    _targetId,
                    StringComparison.Ordinal)
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
                        _targetId),
                    StringComparison.Ordinal)
                || observation.DocumentGeneration
                    != surface.DocumentGeneration
                || observation.SemanticGeneration
                    != surface.SemanticGeneration
                || !observation.Visible
                || observation.Minimized
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
                    _targetId,
                    StringComparison.Ordinal)
                && frame.SurfaceEpoch
                    == observation.SurfaceEpoch
                && frame.CoordinateSpaceVersion
                    == observation.CoordinateSpaceVersion
                && IsSha256(frame.ContentHash)
                && !string.IsNullOrWhiteSpace(
                    frame.OpaqueContentHandle);
        }

        private WingsActionHostBindingSnapshot CreateBinding(
            SessionSnapshot session,
            ObservationEnvelope observation,
            FrameEnvelope frame)
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
                _targetId,
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
                frame.FrameId);
        }

        private bool IsExactActionPrincipal(
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
                    .SetEquals(ActivationCapabilities)
                && principal.AllowedTargets.Count == 1
                && string.Equals(
                    principal.AllowedTargets[0],
                    _targetId,
                    StringComparison.Ordinal)
                && principal.ExpiresMonotonic
                    > principal.IssuedMonotonic
                && principal.ExpiresMonotonic
                    - principal.IssuedMonotonic
                    <= (long)CredentialLifetime
                        .TotalMilliseconds;
        }

        private bool IsCurrent(ActiveOperation operation)
        {
            bool current;
            bool requiresIndicator;
            lock (_sync)
            {
                current = !_disposed
                    && ReferenceEquals(_active, operation)
                    && !operation.Cancellation
                        .IsCancellationRequested;
                requiresIndicator = operation.Phase
                    != OperationPhase.PresentingConsent;
            }
            return current
                && (!requiresIndicator
                    || operation.Indicator?.IsAlive == true);
        }

        private void ScheduleProjectionExpiry(
            ActiveOperation operation)
        {
            if (operation == null
                || !operation.TryScheduleProjectionExpiry())
            {
                return;
            }
            _ = Task.Run(
                async () =>
                {
                    try
                    {
                        await Task.Delay(
                                ProjectionLifetime,
                                operation.ProjectionCancellation
                                    .Token)
                            .ConfigureAwait(false);
                    }
                    catch (OperationCanceledException)
                    {
                        return;
                    }
                    lock (_sync)
                    {
                        if (!ReferenceEquals(
                                _active,
                                operation)
                            || operation.Phase
                                != OperationPhase
                                    .AwaitingProjection)
                        {
                            return;
                        }
                    }
                    _resultAuthority.Remove(
                        operation.ActionReceiptId);
                    _ = FinalizeOperationRevocationAsync(
                        operation,
                        "credential_revoked");
                });
        }

        private void OnReadAuthorizationChanged(
            object sender,
            WingsPlayerAssistAuthorizationChangedEventArgs args)
        {
            if (args == null || args.Authorized)
                return;
            ActiveOperation operation;
            lock (_sync)
            {
                operation = _disposed ? null : _active;
            }
            if (operation != null
                && IsOwnConsentPhase(operation.Phase)
                && string.Equals(
                    args.ReasonCode,
                    "security_surface_appeared",
                    StringComparison.Ordinal)
                && HasExactPublishedInteractionTicket(
                    operation))
            {
                // Only the exact Launcher-owned interaction surface for this
                // operation instance may retire the lore/read credential.
                return;
            }
            PreemptOperation(
                args.ReasonCode
                    ?? "credential_revoked");
        }

        private void OnRegistryChanged(
            object sender,
            SessionSurfaceRegistryChangedEventArgs args)
        {
            ActiveOperation operation;
            lock (_sync)
            {
                operation = _active;
                if (_disposed
                    || operation == null
                    || (operation.Kind
                            == StructuredOperationKind.HairChange
                        && (operation.Phase
                            is OperationPhase.Executing
                                or OperationPhase.Reconciling)
                        && args?.Invalidation?.Level
                            != SessionInvalidationLevel.Security))
                {
                    return;
                }
            }

            if (IsTrustedHumanInteractionPhase(
                    operation.Phase))
            {
                if (TryAcceptTrustedInteractionRegistryChange(
                        operation,
                        args,
                        out string interactionReason))
                {
                    return;
                }
                PreemptOperation(
                    interactionReason
                        ?? args?.Invalidation?.ReasonCode
                        ?? "credential_revoked");
                return;
            }

            string reasonCode;
            bool valid;
            if (operation.Kind
                == StructuredOperationKind.HairChange)
            {
                valid = TryValidateHairOperationState(
                    operation,
                    out reasonCode);
            }
            else
            {
                valid = operation.Intent != null
                    ? _bindingAuthority.TryValidate(
                        operation.Principal,
                        operation.Intent,
                        out reasonCode)
                    : TryGetEligibleSnapshot(
                        operation.Proposal,
                        out _,
                        out reasonCode);
            }
            if (!valid)
            {
                PreemptOperation(
                    reasonCode
                        ?? args?.Invalidation?.ReasonCode
                        ?? "stale_observation");
            }
        }

        private bool TryAcceptTrustedInteractionRegistryChange(
            ActiveOperation operation,
            SessionSurfaceRegistryChangedEventArgs args,
            out string reasonCode)
        {
            reasonCode = null;
            if (operation == null
                || args?.Invalidation == null
                || !operation.TrustedHumanInteractionOpen)
            {
                reasonCode = "credential_revoked";
                return false;
            }

            SessionScopeInvalidation invalidation =
                args.Invalidation;
            if (invalidation.Level
                    == SessionInvalidationLevel.Security)
            {
                if (string.Equals(
                        invalidation.ReasonCode,
                        "security_surface_appeared",
                        StringComparison.Ordinal))
                {
                    return TryBindExactHumanSecuritySurface(
                        operation,
                        args.Snapshot,
                        out reasonCode);
                }
                if (string.Equals(
                        invalidation.ReasonCode,
                        "security_surface_disappeared",
                        StringComparison.Ordinal))
                {
                    return TryMarkExactHumanSecuritySurfaceClosed(
                        operation,
                        args.Snapshot,
                        out reasonCode);
                }
                if (string.Equals(
                        invalidation.ReasonCode,
                        "human_reauthorized",
                        StringComparison.Ordinal)
                    && operation
                            .TrustedInteractionSurfaceTargetId
                        != null
                    && operation
                        .TrustedInteractionSurfaceClosed
                    && !HasHumanOnlySecuritySurface(
                        args.Snapshot))
                {
                    return true;
                }

                // UAC, secure-desktop, foreign modal, or a second security
                // surface is never part of this interaction instance.
                reasonCode =
                    invalidation.ReasonCode
                    ?? "human_intervention_required";
                return false;
            }

            if (invalidation.Level
                    == SessionInvalidationLevel.Focus
                && operation.TrustedInteractionTicket
                    .TryGetBinding(
                        out LauncherTrustedHumanInteractionBinding
                            focusBinding)
                && _nativeGuard.IsExactForegroundWindow(
                    focusBinding.WindowHandle))
            {
                return true;
            }

            reasonCode =
                invalidation.ReasonCode
                ?? "stale_observation";
            return false;
        }

        private bool TryBindExactHumanSecuritySurface(
            ActiveOperation operation,
            SessionSurfaceRegistrySnapshot snapshot,
            out string reasonCode)
        {
            reasonCode = null;
            if (operation == null
                || snapshot == null
                || !IsOwnConsentPhase(operation.Phase)
                || !operation.TrustedHumanInteractionOpen)
            {
                reasonCode = "credential_revoked";
                return false;
            }
            if (!operation.TrustedInteractionTicket
                    .TryGetBinding(
                        out LauncherTrustedHumanInteractionBinding
                            interaction)
                || !interaction.SecuritySurface
                || interaction.Closed
                || interaction.Phase
                    != TrustedInteractionPhaseFor(
                        operation.Kind,
                        operation.Phase)
                || !string.Equals(
                    interaction.InstanceId,
                    operation.TrustedInteractionTicket
                        .InstanceId,
                    StringComparison.Ordinal))
            {
                reasonCode =
                    "human_intervention_required";
                return false;
            }
            if (!_surfaces.Registry.TryGetRegisteredSurface(
                    _sessionId,
                    interaction.TargetId,
                    out SessionSurfaceSnapshot registered)
                || registered.Kind != SurfaceKind.BusinessModal
                || registered.SafetyKind
                    != AgentTargetSafetyKind
                        .HumanOnlySecuritySurface
                || registered.OwnerRelation
                    != SessionSurfaceOwnerRelation
                        .HumanOnlySecurityReported
                || registered.WindowHandle
                    != interaction.WindowHandle
                || registered.OwnerWindowHandle
                    != interaction.OwnerWindowHandle
                || registered.SurfaceEpoch == 0
                || (interaction.SurfaceEpoch != 0
                    && interaction.SurfaceEpoch
                        != registered.SurfaceEpoch))
            {
                reasonCode =
                    "human_intervention_required";
                return false;
            }
            SessionSnapshot session =
                snapshot.FindSession(_sessionId);
            if (session == null
                || session.BlockingModalKind
                    != BlockingModalKind.HumanOnlySecurity)
            {
                reasonCode =
                    "human_intervention_required";
                return false;
            }
            if (_trustedInteractionOwnerWindowHandle != 0
                    && interaction.OwnerWindowHandle
                        != _trustedInteractionOwnerWindowHandle)
            {
                reasonCode =
                    "human_intervention_required";
                return false;
            }
            lock (_sync)
            {
                if (_disposed
                    || !ReferenceEquals(_active, operation)
                    || !operation
                        .TrustedHumanInteractionOpen)
                {
                    reasonCode = "credential_revoked";
                    return false;
                }
                if (operation
                        .TrustedInteractionSurfaceTargetId
                    != null)
                {
                    reasonCode =
                        "human_intervention_required";
                    return false;
                }
                operation.TrustedInteractionSurfaceTargetId =
                    interaction.TargetId;
                operation.TrustedInteractionSurfaceEpoch =
                    registered.SurfaceEpoch;
                operation.TrustedInteractionWindowHandle =
                    interaction.WindowHandle;
                operation.TrustedInteractionSurfaceClosed =
                    false;
            }
            return true;
        }

        private bool TryMarkExactHumanSecuritySurfaceClosed(
            ActiveOperation operation,
            SessionSurfaceRegistrySnapshot snapshot,
            out string reasonCode)
        {
            reasonCode = null;
            if (operation == null
                || !operation.TrustedInteractionTicket
                    .TryGetBinding(
                        out LauncherTrustedHumanInteractionBinding
                            interaction)
                || !interaction.SecuritySurface
                || !interaction.Closed
                || !string.Equals(
                    interaction.TargetId,
                    operation
                        .TrustedInteractionSurfaceTargetId,
                    StringComparison.Ordinal)
                || interaction.WindowHandle
                    != operation
                        .TrustedInteractionWindowHandle
                || interaction.SurfaceEpoch
                    != operation
                        .TrustedInteractionSurfaceEpoch
                || operation
                        .TrustedInteractionSurfaceTargetId
                    == null
                || HasHumanOnlySecuritySurface(snapshot))
            {
                reasonCode =
                    "human_intervention_required";
                return false;
            }
            lock (_sync)
            {
                if (_disposed
                    || !ReferenceEquals(_active, operation)
                    || !operation
                        .TrustedHumanInteractionOpen)
                {
                    reasonCode = "credential_revoked";
                    return false;
                }
                operation.TrustedInteractionSurfaceClosed =
                    true;
            }
            return true;
        }

        private bool HasHumanOnlySecuritySurface(
            SessionSurfaceRegistrySnapshot snapshot)
        {
            return snapshot?.FindSession(_sessionId)
                ?.BlockingModalKind
                == BlockingModalKind.HumanOnlySecurity;
        }

        private bool HasExactPublishedInteractionTicket(
            ActiveOperation operation)
        {
            if (operation == null
                || !operation.TrustedHumanInteractionOpen
                || !operation.TrustedInteractionTicket
                    .TryGetBinding(
                        out LauncherTrustedHumanInteractionBinding
                            interaction)
                || !interaction.SecuritySurface
                || interaction.Closed
                || interaction.Phase
                    != TrustedInteractionPhaseFor(
                        operation.Kind,
                        operation.Phase)
                || (_trustedInteractionOwnerWindowHandle
                        != 0
                    && interaction.OwnerWindowHandle
                        != _trustedInteractionOwnerWindowHandle))
            {
                return false;
            }
            return _surfaces.Registry.TryGetRegisteredSurface(
                    _sessionId,
                    interaction.TargetId,
                    out SessionSurfaceSnapshot registered)
                && registered.Kind == SurfaceKind.BusinessModal
                && registered.SafetyKind
                    == AgentTargetSafetyKind
                        .HumanOnlySecuritySurface
                && registered.OwnerRelation
                    == SessionSurfaceOwnerRelation
                        .HumanOnlySecurityReported
                && registered.WindowHandle
                    == interaction.WindowHandle
                && registered.OwnerWindowHandle
                    == interaction.OwnerWindowHandle
                && registered.SurfaceEpoch != 0
                && (interaction.SurfaceEpoch == 0
                    || interaction.SurfaceEpoch
                        == registered.SurfaceEpoch);
        }

        private bool BeginTrustedHumanInteraction(
            ActiveOperation operation,
            OperationPhase phase)
        {
            if (!IsOwnConsentPhase(phase)
                && phase != OperationPhase.ChoosingHair)
            {
                throw new ArgumentOutOfRangeException(
                    nameof(phase));
            }
            lock (_sync)
            {
                if (_disposed
                    || !ReferenceEquals(_active, operation)
                    || operation.Cancellation
                        .IsCancellationRequested)
                {
                    return false;
                }
                operation.Phase = phase;
                operation.TrustedHumanInteractionOpen = true;
                operation.TrustedInteractionTicket =
                    new LauncherTrustedHumanInteractionTicket(
                        OpaqueIdGenerator.Create(
                            "winteraction"),
                        TrustedInteractionPhaseFor(
                            operation.Kind,
                            phase),
                        operation
                            .TrustedInteractionOwnerWindowHandle);
                operation.TrustedInteractionWindowHandle = 0;
                operation.TrustedInteractionSurfaceTargetId = null;
                operation.TrustedInteractionSurfaceEpoch = 0;
                operation.TrustedInteractionSurfaceClosed = false;
                operation.TrustedInteractionStartSequence =
                    _nativeGuard
                        .ObservedExternalInputSequence;
                operation.TrustedOwnerTailAllowed = false;
                return true;
            }
        }

        private static LauncherTrustedHumanInteractionPhase
            TrustedInteractionPhaseFor(
                StructuredOperationKind kind,
                OperationPhase phase)
        {
            return phase switch
            {
                OperationPhase.PresentingConsent
                    when kind
                        == StructuredOperationKind
                            .WindowActivation =>
                    LauncherTrustedHumanInteractionPhase
                        .WindowActivationConsent,
                OperationPhase.PresentingConsent
                    when kind
                        == StructuredOperationKind
                            .HairChange =>
                    LauncherTrustedHumanInteractionPhase
                        .HairPreparationConsent,
                OperationPhase.ChoosingHair =>
                    LauncherTrustedHumanInteractionPhase
                        .HairChooser,
                OperationPhase.PresentingHairConsent =>
                    LauncherTrustedHumanInteractionPhase
                        .HairCommitConsent,
                OperationPhase.PresentingRestoreConsent =>
                    LauncherTrustedHumanInteractionPhase
                        .HairRestoreConsent,
                _ => throw new ArgumentOutOfRangeException(
                    nameof(phase))
            };
        }

        private async Task<string>
            SealTrustedHumanInteractionAsync(
                ActiveOperation operation,
                OperationPhase expectedPhase)
        {
            long sequence;
            try
            {
                sequence = await _nativeGuard
                    .SealTrustedHumanInteractionAsync(
                        operation.Cancellation.Token)
                    .ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
                return "credential_revoked";
            }
            catch (InvalidOperationException exception)
            {
                return string.IsNullOrWhiteSpace(
                        exception.Message)
                    ? "input_guard_unhealthy"
                    : exception.Message;
            }
            catch
            {
                return "input_guard_unhealthy";
            }

            lock (_sync)
            {
                if (_disposed
                    || !ReferenceEquals(_active, operation)
                    || operation.Cancellation
                        .IsCancellationRequested
                    || operation.Phase != expectedPhase
                    || !operation.TrustedHumanInteractionOpen
                    || !operation.TrustedInteractionTicket
                        .TryGetBinding(
                            out LauncherTrustedHumanInteractionBinding
                                interaction)
                    || !interaction.Closed
                    || interaction.Phase
                        != TrustedInteractionPhaseFor(
                            operation.Kind,
                            expectedPhase))
                {
                    return "credential_revoked";
                }
                if (expectedPhase == OperationPhase.ChoosingHair)
                {
                    if (interaction.SecuritySurface
                        || interaction.SurfaceEpoch != 0)
                    {
                        return "human_intervention_required";
                    }
                }
                else if (!interaction.SecuritySurface
                    || interaction.SurfaceEpoch == 0
                    || operation
                            .TrustedInteractionSurfaceTargetId
                        == null
                    || !operation
                        .TrustedInteractionSurfaceClosed
                    || !string.Equals(
                        interaction.TargetId,
                        operation
                            .TrustedInteractionSurfaceTargetId,
                        StringComparison.Ordinal)
                    || interaction.WindowHandle
                        != operation
                            .TrustedInteractionWindowHandle
                    || interaction.SurfaceEpoch
                        != operation
                            .TrustedInteractionSurfaceEpoch
                    || (operation
                                .TrustedInteractionOwnerWindowHandle
                            != 0
                        && interaction.OwnerWindowHandle
                            != operation
                                .TrustedInteractionOwnerWindowHandle))
                {
                    return "human_intervention_required";
                }
                operation.TrustedHumanInteractionFence =
                    sequence;
                operation.TrustedHumanInteractionOpen = false;
                if (operation.HighestExternalInputSequence
                    > sequence)
                {
                    return "external_input_preempted";
                }
            }
            return null;
        }

        private void OnExternalInputObserved(
            ExternalInputObservation observation)
        {
            if (observation == null)
                return;
            lock (_sync)
            {
                ActiveOperation operation = _active;
                if (!_disposed
                    && operation != null
                    && IsTrustedHumanInteractionPhase(
                        operation.Phase))
                {
                    bool exactInteractionInput =
                        string.Equals(
                            observation.ReasonCode,
                            "human_input",
                            StringComparison.Ordinal)
                        && operation.TrustedInteractionTicket
                            .TryGetBinding(
                                out LauncherTrustedHumanInteractionBinding
                                    interaction)
                        && observation.ForegroundWindowHandle
                            == interaction.WindowHandle;
                    bool boundedOwnerTail =
                        string.Equals(
                            observation.ReasonCode,
                            "human_input",
                            StringComparison.Ordinal)
                        && operation.TrustedOwnerTailAllowed
                        && operation
                                .TrustedInteractionOwnerWindowHandle
                            != 0
                        && observation.ForegroundWindowHandle
                            == operation
                                .TrustedInteractionOwnerWindowHandle
                        && (observation.Sequence
                                <= operation
                                    .TrustedInteractionStartSequence
                            || observation.Transition
                                == NativeControlTransition.Up);
                    if ((exactInteractionInput
                            || boundedOwnerTail)
                        && observation.Sequence
                            > operation
                                .HighestExternalInputSequence)
                    {
                        operation
                            .HighestExternalInputSequence =
                                observation.Sequence;
                    }
                    if ((exactInteractionInput
                            || boundedOwnerTail)
                        && (operation
                                .TrustedHumanInteractionOpen
                            || observation.Sequence
                                <= operation
                                    .TrustedHumanInteractionFence))
                    {
                        return;
                    }
                }
            }
            PreemptOperation("external_input_preempted");
        }

        private static bool IsOwnConsentPhase(
            OperationPhase phase)
        {
            return phase is OperationPhase.PresentingConsent
                or OperationPhase.PresentingHairConsent
                or OperationPhase.PresentingRestoreConsent;
        }

        private static bool IsTrustedHumanInteractionPhase(
            OperationPhase phase)
        {
            return IsOwnConsentPhase(phase)
                || phase == OperationPhase.ChoosingHair;
        }

        private void RaiseExecutionStarting()
        {
            try
            {
                ExecutionStarting?.Invoke(
                    this,
                    EventArgs.Empty);
            }
            catch
            {
                // Presentation observers cannot affect authorization.
            }
        }

        private SessionSurfaceSnapshot FindTarget(
            SessionSnapshot session)
        {
            return session?.Surfaces.FirstOrDefault(
                surface => string.Equals(
                    surface.TargetId,
                    _targetId,
                    StringComparison.Ordinal));
        }

        private static bool TryDeserialize<T>(
            AgentRuntimeDispatchResult result,
            out T value)
            where T : class
        {
            value = null;
            if (result == null || !result.Success)
                return false;
            try
            {
                value = result.Result.Deserialize<T>(
                    AgentProtocolV1.JsonOptions);
                return value != null;
            }
            catch (JsonException)
            {
                return false;
            }
        }

        private static bool IsSha256(string value)
        {
            return value != null
                && value.Length == 64
                && value.All(character =>
                    character is >= '0' and <= '9'
                    or >= 'a' and <= 'f'
                    or >= 'A' and <= 'F');
        }

        private static string NormalizeRevocationReason(
            string reasonCode)
        {
            if (AgentReasonCodesV1.TryGet(
                    reasonCode,
                    out _))
            {
                return reasonCode;
            }
            return reasonCode switch
            {
                "human_input" or
                "external_input" =>
                    "external_input_preempted",
                "wings_shell_paused" or
                "wings_shell_hidden" or
                "wings_indicator_closed" =>
                    "human_intervention_required",
                "wings_session_binding_changed" =>
                    "stale_lifecycle",
                _ => "credential_revoked"
            };
        }

        private enum OperationPhase
        {
            PresentingConsent,
            IndicatorActive,
            CredentialActive,
            Attached,
            GrantActive,
            ObservationCaptured,
            ChoosingHair,
            HairPreviewReady,
            PresentingHairConsent,
            HairConsentEvidenceConsumed,
            IntentAuthorized,
            Executing,
            Reconciling,
            PresentingRestoreConsent,
            RestoreObservationCaptured,
            AwaitingProjection
        }

        private enum StructuredOperationKind
        {
            WindowActivation,
            HairChange
        }

        private sealed class ActiveOperation : IDisposable
        {
            private int _liveRevocationStarted;
            private int _finalizationStarted;
            private int _projectionExpiryScheduled;

            internal ActiveOperation(
                StructuredOperationKind kind,
                CancellationToken callerCancellation,
                long initialExternalInputSequence,
                long trustedInteractionOwnerWindowHandle)
            {
                Kind = kind;
                Cancellation =
                    CancellationTokenSource
                        .CreateLinkedTokenSource(
                            callerCancellation);
                ProjectionCancellation =
                    new CancellationTokenSource();
                LiveRevocationCompletion =
                    new TaskCompletionSource<bool>(
                        TaskCreationOptions
                            .RunContinuationsAsynchronously);
                FinalizationCompletion =
                    new TaskCompletionSource<bool>(
                        TaskCreationOptions
                            .RunContinuationsAsynchronously);
                Phase =
                    OperationPhase.PresentingConsent;
                TrustedHumanInteractionOpen = true;
                TrustedInteractionOwnerWindowHandle =
                    trustedInteractionOwnerWindowHandle;
                TrustedInteractionTicket =
                    new LauncherTrustedHumanInteractionTicket(
                        OpaqueIdGenerator.Create(
                            "winteraction"),
                        kind
                            == StructuredOperationKind
                                .WindowActivation
                            ? LauncherTrustedHumanInteractionPhase
                                .WindowActivationConsent
                            : LauncherTrustedHumanInteractionPhase
                                .HairPreparationConsent,
                        trustedInteractionOwnerWindowHandle);
                TrustedInteractionStartSequence =
                    initialExternalInputSequence;
                TrustedOwnerTailAllowed = true;
            }

            internal CancellationTokenSource Cancellation
            {
                get;
            }
            internal StructuredOperationKind Kind { get; }
            internal CancellationTokenSource
                ProjectionCancellation { get; }
            internal TaskCompletionSource<bool>
                LiveRevocationCompletion { get; }
            internal TaskCompletionSource<bool>
                FinalizationCompletion { get; }
            internal OperationPhase Phase { get; set; }
            internal bool TrustedHumanInteractionOpen
            {
                get;
                set;
            }
            internal long TrustedHumanInteractionFence
            {
                get;
                set;
            }
            internal long HighestExternalInputSequence
            {
                get;
                set;
            }
            internal LauncherTrustedHumanInteractionTicket
                TrustedInteractionTicket { get; set; }
            internal long TrustedInteractionWindowHandle
            {
                get;
                set;
            }
            internal long TrustedInteractionOwnerWindowHandle
            {
                get;
            }
            internal long TrustedInteractionStartSequence
            {
                get;
                set;
            }
            internal string TrustedInteractionSurfaceTargetId
            {
                get;
                set;
            }
            internal ulong TrustedInteractionSurfaceEpoch
            {
                get;
                set;
            }
            internal bool TrustedInteractionSurfaceClosed
            {
                get;
                set;
            }
            internal bool TrustedOwnerTailAllowed
            {
                get;
                set;
            }
            internal bool TerminalProjectionPreempted
            {
                get;
                set;
            }
            internal bool
                TerminalReceiptRecordedAwaitingAdoption
            {
                get;
                set;
            }
            internal bool TerminalProjectionConcluded
            {
                get;
                set;
            }
            internal LauncherWingsWindowActivationProposal
                Proposal { get; set; }
            internal PrincipalCredential Principal { get; set; }
            internal WingsVirtualAuthenticatedConnection
                Connection { get; set; }
            internal IWingsStructuredActionIndicator
                Indicator { get; set; }
            internal string GrantId { get; set; }
            internal WingsActionIntentV1 Intent { get; set; }
            internal string ActionReceiptId { get; set; }
            internal LauncherWingsHairPreparationProposal
                HairProposal { get; set; }
            internal HairAppearancePreview HairPreview
            {
                get;
                set;
            }
            internal ObservationGrantDescriptor HairGrant
            {
                get;
                set;
            }
            internal ObservationEnvelope HairObservation
            {
                get;
                set;
            }
            internal FrameEnvelope HairFrame { get; set; }
            internal string CommitReceiptId { get; set; }
            internal string RestoreToken { get; set; }
            internal DateTimeOffset? RestoreExpiresAtUtc
            {
                get;
                set;
            }

            internal void ClearHairSensitiveState()
            {
                RestoreToken = null;
                RestoreExpiresAtUtc = null;
                HairPreview = null;
                HairObservation = null;
                HairFrame = null;
                HairGrant = null;
                HairProposal = null;
                Intent = null;
            }

            internal void TryCancel()
            {
                TryCancelExecution();
                try
                {
                    ProjectionCancellation.Cancel();
                }
                catch
                {
                }
            }

            internal void TryCancelExecution()
            {
                try
                {
                    Cancellation.Cancel();
                }
                catch
                {
                }
            }

            internal bool TryBeginLiveRevocation()
            {
                return Interlocked.CompareExchange(
                    ref _liveRevocationStarted,
                    1,
                    0) == 0;
            }

            internal bool TryBeginFinalization()
            {
                return Interlocked.CompareExchange(
                    ref _finalizationStarted,
                    1,
                    0) == 0;
            }

            internal bool TryScheduleProjectionExpiry()
            {
                return Interlocked.CompareExchange(
                    ref _projectionExpiryScheduled,
                    1,
                    0) == 0;
            }

            public void Dispose()
            {
                ClearHairSensitiveState();
                Cancellation.Dispose();
                ProjectionCancellation.Dispose();
            }
        }
    }

    /// <summary>
    /// Trusted in-memory binding for the single fixed action. Every executor
    /// and result projection call rechecks the exact principal, grant,
    /// observation, current session/save/target and immutable intent. The
    /// terminal phase permits only the focus epoch to advance because that is
    /// the direct effect of window.activate.
    /// </summary>
    internal sealed class
        LauncherWingsWindowActivationBindingAuthority
        : IWingsActionBindingAuthority
    {
        private readonly object _sync = new object();
        private readonly IAgentRuntimeClock _clock;
        private readonly SessionSurfaceHostController _surfaces;
        private readonly PrincipalCredentialAuthority
            _credentials;
        private readonly ObservationGrantBroker _grants;
        private readonly string _sessionId;
        private readonly string _targetId;
        private readonly LoreView _loreView;
        private readonly HashSet<string> _exactCapabilities;
        private BindingRecord _record;

        internal LauncherWingsWindowActivationBindingAuthority(
            IAgentRuntimeClock clock,
            SessionSurfaceHostController surfaces,
            PrincipalCredentialAuthority credentials,
            ObservationGrantBroker grants,
            string sessionId,
            string targetId,
            LoreView loreView,
            IEnumerable<string> exactCapabilities)
        {
            _clock = clock
                ?? throw new ArgumentNullException(nameof(clock));
            _surfaces = surfaces
                ?? throw new ArgumentNullException(nameof(surfaces));
            _credentials = credentials
                ?? throw new ArgumentNullException(
                    nameof(credentials));
            _grants = grants
                ?? throw new ArgumentNullException(nameof(grants));
            _sessionId = sessionId;
            _targetId = targetId;
            _loreView = loreView
                ?? throw new ArgumentNullException(nameof(loreView));
            _exactCapabilities =
                new HashSet<string>(
                    exactCapabilities
                        ?? Array.Empty<string>(),
                    StringComparer.Ordinal);
        }

        internal bool TryRegister(
            PrincipalCredential principal,
            WingsActionIntentV1 intent,
            ObservationEnvelope observation,
            FrameEnvelope frame,
            out string reasonCode)
        {
            BindingRecord record;
            try
            {
                record = new BindingRecord(
                    principal,
                    intent,
                    observation,
                    frame);
            }
            catch
            {
                reasonCode =
                    "wings_action_binding_unavailable";
                return false;
            }
            lock (_sync)
            {
                if (_record != null)
                {
                    reasonCode = "lease_busy";
                    return false;
                }
                _record = record;
            }
            if (!TryValidate(
                    principal,
                    intent,
                    out reasonCode))
            {
                Clear();
                return false;
            }
            return true;
        }

        internal bool TryMarkTerminal(
            PrincipalCredential principal,
            WingsActionIntentV1 intent,
            WingsBrokeredActionReceipt evidence,
            WingsActionReceiptTrustDomain trustDomain,
            out string reasonCode)
        {
            reasonCode = null;
            if (trustDomain == null
                || !trustDomain.Verify(evidence)
                || evidence == null
                || !ReferenceEquals(
                    principal,
                    CurrentRecord()?.Principal)
                || !ReferenceEquals(
                    intent,
                    CurrentRecord()?.Intent)
                || !WingsTerminalActionReceiptValidator
                    .TryValidate(
                        intent,
                        evidence.ReceiptSnapshot(),
                        out reasonCode))
            {
                reasonCode ??=
                    "wings_terminal_receipt_required";
                return false;
            }
            lock (_sync)
            {
                if (_record == null
                    || !ReferenceEquals(
                        _record.Principal,
                        principal)
                    || !ReferenceEquals(
                        _record.Intent,
                        intent))
                {
                    reasonCode =
                        "wings_action_binding_unavailable";
                    return false;
                }
                _record.Terminal = true;
            }
            reasonCode = null;
            return true;
        }

        internal bool TryBeginExpectedActivation(
            PrincipalCredential principal,
            WingsActionIntentV1 intent,
            out string reasonCode)
        {
            if (!TryValidate(
                    principal,
                    intent,
                    out reasonCode))
            {
                return false;
            }
            lock (_sync)
            {
                if (_record == null
                    || !ReferenceEquals(
                        _record.Principal,
                        principal)
                    || !ReferenceEquals(
                        _record.Intent,
                        intent))
                {
                    reasonCode =
                        "wings_action_binding_unavailable";
                    return false;
                }
                _record.ActivationInFlight = true;
            }
            reasonCode = null;
            return true;
        }

        public bool TryValidate(
            PrincipalCredential principal,
            WingsActionIntentV1 intent,
            out string reasonCode)
        {
            BindingRecord record = CurrentRecord();
            if (record == null
                || principal == null
                || intent == null
                || !ReferenceEquals(
                    record.Principal,
                    principal)
                || !ReferenceEquals(record.Intent, intent))
            {
                reasonCode =
                    "wings_action_binding_unavailable";
                return false;
            }
            if (!_credentials.TryResolveActive(
                    principal.CredentialId,
                    principal.ClientInstanceId,
                    out PrincipalCredential active,
                    out reasonCode)
                || !ReferenceEquals(active, principal)
                || principal.PrincipalKind
                    != AgentPrincipalKind.WingsPersona
                || principal.SessionMode
                    != AgentSessionMode.PlayerAssist
                || !string.Equals(
                    principal.SelectedSessionId,
                    _sessionId,
                    StringComparison.Ordinal)
                || !principal.AllowedCapabilities
                    .ToHashSet(StringComparer.Ordinal)
                    .SetEquals(_exactCapabilities)
                || principal.AllowedTargets.Count != 1
                || !string.Equals(
                    principal.AllowedTargets[0],
                    _targetId,
                    StringComparison.Ordinal)
                || _clock.MonotonicMilliseconds
                    >= principal.ExpiresMonotonic)
            {
                reasonCode ??= "principal_mismatch";
                return false;
            }
            if (!IntentMatches(record))
            {
                reasonCode =
                    "wings_action_binding_unavailable";
                return false;
            }
            if (!_grants.TryAuthorize(
                    intent.ObservationGrantId,
                    principal.ClientInstanceId,
                    principal.SecurityPrincipalId,
                    _sessionId,
                    _targetId,
                    ObservationDataScopesV1.Pixels,
                    out ObservationGrant grant,
                    out reasonCode)
                || !string.Equals(
                    grant.ConsentReceipt,
                    principal.IssuerReceipt,
                    StringComparison.Ordinal)
                || grant.AllowPersistence
                || grant.AllowExport)
            {
                reasonCode ??=
                    "observation_grant_revoked";
                return false;
            }

            SessionSnapshot session =
                _surfaces.Registry.GetSnapshot()
                    .FindSession(_sessionId);
            SessionSurfaceSnapshot surface =
                session?.Surfaces.FirstOrDefault(
                    candidate => string.Equals(
                        candidate.TargetId,
                        _targetId,
                        StringComparison.Ordinal));
            if (session == null
                || surface == null
                || session.LifecycleGeneration
                    != intent.LifecycleGeneration
                || !string.Equals(
                    session.AttemptId,
                    intent.AttemptId,
                    StringComparison.Ordinal)
                || session.AttemptGeneration
                    != intent.AttemptGeneration
                || !string.Equals(
                    session.Slot,
                    intent.Slot,
                    StringComparison.Ordinal)
                || session.SaveRevision != intent.SaveRevision
                || session.RuntimeQualification == null
                || session.RuntimeQualification.RuntimeMode
                    == RuntimeMode.UnqualifiedDev
                || !session.Capabilities.Contains(
                    AgentCapabilitiesV1.ActivateWindow,
                    StringComparer.Ordinal)
                || !session.DesktopAvailable
                || session.HumanReauthorizationRequired
                || session.BlockingModalKind
                    != BlockingModalKind.None
                || surface.Kind != SurfaceKind.Flash
                || surface.SafetyKind
                    != AgentTargetSafetyKind.RuntimeOwned
                || !surface.Visible
                || surface.Minimized
                || !surface.ObservationModes.Contains(
                    ObservationMode.WindowGraphicsCapture)
                || !surface.InputModes.Contains(
                    InputMode.SendInputGuarded)
                || surface.SurfaceEpoch
                    != intent.SurfaceEpoch
                || surface.CoordinateSpaceVersion
                    != intent.CoordinateSpaceVersion
                || surface.DocumentGeneration
                    != intent.DocumentGeneration
                || surface.SemanticGeneration
                    != intent.SemanticGeneration
                || session.ModalEpoch
                    != intent.ModalEpoch
                || !string.Equals(
                    session.PanelInstanceIdForTarget(
                        _targetId),
                    intent.PanelInstanceId,
                    StringComparison.Ordinal)
                || !FocusBindingMatches(
                    record,
                    session,
                    intent))
            {
                reasonCode = "stale_observation";
                return false;
            }
            reasonCode = null;
            return true;
        }

        internal void Clear()
        {
            lock (_sync)
                _record = null;
        }

        private BindingRecord CurrentRecord()
        {
            lock (_sync)
                return _record;
        }

        private bool IntentMatches(BindingRecord record)
        {
            WingsActionIntentV1 intent = record.Intent;
            ObservationEnvelope observation =
                record.Observation;
            FrameEnvelope frame = record.Frame;
            return string.Equals(
                    intent.TemplateKey,
                    LauncherWingsStructuredActionCoordinator
                        .ActivationTemplateKey,
                    StringComparison.Ordinal)
                && string.Equals(
                    intent.Operation,
                    AgentCapabilitiesV1.ActivateWindow,
                    StringComparison.Ordinal)
                && intent.LeaseKind
                    == WingsActionLeaseKind.GuiInput
                && intent.HairBinding == null
                && intent.CanonicalArguments.ValueKind
                    == JsonValueKind.Object
                && !intent.CanonicalArguments
                    .EnumerateObject().Any()
                && string.Equals(
                    intent.SessionId,
                    _sessionId,
                    StringComparison.Ordinal)
                && string.Equals(
                    intent.TargetId,
                    _targetId,
                    StringComparison.Ordinal)
                && string.Equals(
                    intent.SaveBindingId,
                    _loreView.Progress.SaveBindingId,
                    StringComparison.Ordinal)
                && string.Equals(
                    intent.SaveSignature,
                    _loreView.Progress.SaveSignature,
                    StringComparison.OrdinalIgnoreCase)
                && string.Equals(
                    intent.LoreViewId,
                    _loreView.LoreViewId,
                    StringComparison.Ordinal)
                && intent.IssuedMonotonic
                    >= record.Principal.IssuedMonotonic
                && intent.ExpiresMonotonic
                    <= record.Principal.ExpiresMonotonic
                && string.Equals(
                    intent.ObservationGrantId,
                    observation.ObservationGrantId,
                    StringComparison.Ordinal)
                && string.Equals(
                    intent.ObservationId,
                    observation.ObservationId,
                    StringComparison.Ordinal)
                && intent.LifecycleGeneration
                    == observation.LifecycleGeneration
                && string.Equals(
                    intent.AttemptId,
                    observation.AttemptId,
                    StringComparison.Ordinal)
                && intent.AttemptGeneration
                    == observation.AttemptGeneration
                && intent.SurfaceEpoch
                    == observation.SurfaceEpoch
                && intent.CoordinateSpaceVersion
                    == observation.CoordinateSpaceVersion
                && intent.FocusEpoch
                    == observation.FocusEpoch
                && intent.ModalEpoch
                    == observation.ModalEpoch
                && string.Equals(
                    intent.PanelInstanceId,
                    observation.PanelInstanceId,
                    StringComparison.Ordinal)
                && intent.DocumentGeneration
                    == observation.DocumentGeneration
                && string.Equals(
                    intent.SemanticSnapshotId,
                    observation.SemanticSnapshotId,
                    StringComparison.Ordinal)
                && intent.SemanticGeneration
                    == observation.SemanticGeneration
                && intent.NodeId == null
                && string.Equals(
                    intent.FrameId,
                    frame.FrameId,
                    StringComparison.Ordinal)
                && string.Equals(
                    frame.ObservationId,
                    observation.ObservationId,
                    StringComparison.Ordinal)
                && string.Equals(
                    frame.TargetId,
                    _targetId,
                    StringComparison.Ordinal)
                && frame.SurfaceEpoch
                    == observation.SurfaceEpoch
                && frame.CoordinateSpaceVersion
                    == observation.CoordinateSpaceVersion
                && frame.ContentHash?.Length == 64;
        }

        private bool FocusBindingMatches(
            BindingRecord record,
            SessionSnapshot session,
            WingsActionIntentV1 intent)
        {
            if (session.FocusEpoch == intent.FocusEpoch)
                return true;
            return (record.ActivationInFlight
                    || record.Terminal)
                && session.FocusEpoch > intent.FocusEpoch
                && string.Equals(
                    session.ActiveTargetId,
                    _targetId,
                    StringComparison.Ordinal);
        }

        private sealed class BindingRecord
        {
            internal BindingRecord(
                PrincipalCredential principal,
                WingsActionIntentV1 intent,
                ObservationEnvelope observation,
                FrameEnvelope frame)
            {
                Principal = principal
                    ?? throw new ArgumentNullException(
                        nameof(principal));
                Intent = intent
                    ?? throw new ArgumentNullException(
                        nameof(intent));
                Observation = Clone(observation);
                Frame = Clone(frame);
            }

            internal PrincipalCredential Principal { get; }
            internal WingsActionIntentV1 Intent { get; }
            internal ObservationEnvelope Observation { get; }
            internal FrameEnvelope Frame { get; }
            internal bool ActivationInFlight { get; set; }
            internal bool Terminal { get; set; }

            private static T Clone<T>(T value)
                where T : class
            {
                if (value == null)
                    throw new ArgumentNullException(nameof(value));
                return JsonSerializer.Deserialize<T>(
                        JsonSerializer.SerializeToUtf8Bytes(
                            value,
                            AgentProtocolV1.JsonOptions),
                        AgentProtocolV1.JsonOptions)
                    ?? throw new InvalidOperationException(
                        "wings_action_binding_clone_failed");
            }
        }
    }
}
