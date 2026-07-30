using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using CF7Launcher.AgentRuntime.Audit;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Domain;
using CF7Launcher.AgentRuntime.Gateway;
using CF7Launcher.AgentRuntime.Input;
using CF7Launcher.AgentRuntime.NativeInput;
using CF7Launcher.AgentRuntime.Observation;
using CF7Launcher.AgentRuntime.Security;
using CF7Launcher.AgentRuntime.Sessions;
using CF7Launcher.AgentRuntime.Transport;
using CF7Launcher.AgentRuntime.Wings;
using CF7Launcher.Guardian;
using CF7Launcher.Tasks;

namespace CF7Launcher.AgentRuntime.Integration
{
    /// <summary>
    /// Stable, process-local IDs used by host-owned surface registration and
    /// structured action callbacks. They are generated once per Runtime host;
    /// no client chooses or predicts them.
    /// </summary>
    internal sealed class LauncherAgentRuntimeTargetIds
    {
        private LauncherAgentRuntimeTargetIds()
        {
            Launcher = OpaqueIdGenerator.Create("launcher");
            Flash = OpaqueIdGenerator.Create("flash");
            WebOverlay = OpaqueIdGenerator.Create("web");
            NativeHud = OpaqueIdGenerator.Create("nativehud");
            WingsShell = OpaqueIdGenerator.Create("wings");
        }

        public string Launcher { get; }
        public string Flash { get; }
        public string WebOverlay { get; }
        public string NativeHud { get; }
        public string WingsShell { get; }

        internal static LauncherAgentRuntimeTargetIds Create()
        {
            return new LauncherAgentRuntimeTargetIds();
        }
    }

    internal sealed class LauncherAgentStructuredActionBindings
    {
        public LauncherAgentUiMarshal MarshalToUi { get; init; }
        public Func<
            LauncherAgentRuntimeTargetIds,
            IReadOnlyDictionary<
                string,
                Func<LauncherAgentExactTargetBinding, bool>>>
                CreateTargetActivators { get; init; }
        public Func<string, bool> PrepareSafeExit { get; init; }
        public Action<string> CompleteSafeExit { get; init; }
        public Action<string> AbortSafeExit { get; init; }
        public Action RevealLifecycle { get; init; }
        public Action CancelLifecycle { get; init; }
        public Func<string, bool> TryOpenPanel { get; init; }

        internal bool IsComplete =>
            MarshalToUi != null
            && CreateTargetActivators != null
            && PrepareSafeExit != null
            && CompleteSafeExit != null
            && AbortSafeExit != null
            && RevealLifecycle != null
            && CancelLifecycle != null
            && TryOpenPanel != null;
    }

    internal sealed class LauncherAgentRuntimeWingsContext
    {
        internal LauncherAgentRuntimeWingsContext(
            SessionSurfaceHostController surfaces,
            SessionRegistryHostOwner registryOwner,
            LauncherAgentRuntimeTargetIds targets)
        {
            Surfaces = surfaces;
            RegistryOwner = registryOwner;
            Targets = targets;
        }

        public SessionSurfaceHostController Surfaces { get; }
        public SessionRegistryHostOwner RegistryOwner { get; }
        public LauncherAgentRuntimeTargetIds Targets { get; }
        public string SessionId => Surfaces.SessionId;
    }

    internal sealed class LauncherAgentRuntimeHostOptions
    {
        public string ProjectRoot { get; init; }
        public Form Owner { get; init; }
        public bool IsolatedRuntimeCandidate { get; init; }
        public HairdresserTask HairdresserTask { get; init; }
        public Func<
            LauncherAgentRuntimeTargetIds,
            IReadOnlyCollection<WindowsSessionSurfaceSpec>>
                SurfaceSource { get; init; }
        public LauncherAgentStructuredActionBindings
            StructuredActions { get; init; }
        public IAgentHairConsentPresenter
            HairConsentPresenter { get; init; }
        public ILauncherAgentDeveloperEnrollmentPresenter
            DeveloperEnrollmentPresenter { get; init; }
        public Func<
            LauncherAgentRuntimeWingsContext,
            LoreView,
            LauncherWingsRuntimeHost> WingsFactory { get; init; }
        public TimeSpan SurfaceRefreshInterval { get; init; } =
            TimeSpan.FromMilliseconds(250);
        public string LocalAppDataOverride { get; init; }
        public string UnattendedBootstrapRequestPath
        {
            get;
            init;
        }
    }

    /// <summary>
    /// Narrow test seam for OS and persistence boundaries. Production callers
    /// leave every member null.
    /// </summary>
    internal sealed class LauncherAgentRuntimeHostServices
    {
        public IAgentRuntimeClock Clock { get; init; }
        public SessionSurfaceRegistry Registry { get; init; }
        public SessionRegistryHostOwner RegistryOwner { get; init; }
        public IWindowsSessionSurfaceProbe SurfaceProbe { get; init; }
        public INativeInputWin32Facade NativeInput { get; init; }
        public IWindowFrameSourceFactory FrameSources { get; init; }
        public IAgentRendezvousClock RendezvousClock { get; init; }
        public IAgentRendezvousProcessProbe RendezvousProcessProbe
        {
            get;
            init;
        }
        public IAgentRendezvousFileProtection FileProtection
        {
            get;
            init;
        }
    }

    /// <summary>
    /// Production composition root for the phase-one Agent Runtime.
    /// Construction publishes one prepared named-pipe rendezvous. Shutdown
    /// first stops the pipe and revokes live authorities, then tears down
    /// capture, input, UI and persistence resources.
    /// </summary>
    internal sealed class LauncherAgentRuntimeHost
        : IDisposable,
          IAsyncDisposable
    {
        private static readonly HashSet<string>
            UnqualifiedWriteCapabilities =
                new HashSet<string>(
                    new[]
                    {
                        AgentCapabilitiesV1.Click,
                        AgentCapabilitiesV1.PressKey,
                        AgentCapabilitiesV1.TypeText,
                        AgentCapabilitiesV1.Scroll,
                        AgentCapabilitiesV1.SetValue,
                        AgentCapabilitiesV1.Drag,
                        AgentCapabilitiesV1
                            .PerformSecondaryAction,
                        AgentCapabilitiesV1.ActivateWindow,
                        AgentCapabilitiesV1.SessionShutdown,
                        AgentCapabilitiesV1.LifecycleReveal,
                        AgentCapabilitiesV1.LifecycleCancel,
                        AgentCapabilitiesV1.PanelOpen,
                        AgentCapabilitiesV1.LeaseAcquire,
                        AgentCapabilitiesV1.LeaseRenew,
                        AgentCapabilitiesV1.LeaseRelease,
                        AgentCapabilitiesV1
                            .AppearanceHairChange
                    },
                    StringComparer.Ordinal);

        private readonly object _stateSync = new object();
        private readonly object _unattendedBindingSync =
            new object();
        private readonly string _projectRoot;
        private readonly IAgentRuntimeClock _clock;
        private readonly AgentRuntimeHostIdentity _identity;
        private readonly SessionRegistryHostOwner _registryOwner;
        private readonly SessionSurfaceRegistry _registry;
        private readonly SessionSurfaceHostController _surfaces;
        private readonly HumanOnlySecuritySurfaceAuthority
            _humanOnlySecuritySurfaces;
        private readonly WindowsSessionSurfaceSynchronizer
            _surfaceSynchronizer;
        private readonly PersistentDeveloperEnrollmentStore
            _developerEnrollments;
        private readonly ILauncherAgentDeveloperEnrollmentPresenter
            _developerEnrollmentPresenter;
        private readonly PersistentHairDomainAuthority _hairAuthority;
        private readonly HairAppearanceModifierTransaction
            _hairTransaction;
        private readonly LauncherAgentHairConsentPresenter
            _ownedHairConsentPresenter;
        private readonly LauncherAgentStructuredActionHost
            _ownedStructuredActions;
        private LauncherWingsRuntimeHost _wings;
        private readonly Form _wingsOwner;
        private readonly Func<
            LauncherAgentRuntimeWingsContext,
            LoreView,
            LauncherWingsRuntimeHost> _wingsFactory;
        private readonly LauncherAgentRuntimeWingsContext
            _wingsContext;
        private readonly HostPrincipalEnrollmentVerifier
            _principalVerifier;
        private readonly PrincipalCredentialAuthority
            _principalCredentials;
        private readonly ObservationGrantBroker _observationGrants;
        private readonly Func<
            PrincipalCredential,
            WingsVirtualAuthenticatedConnection>
                _wingsVirtualConnectionFactory;
        private string _wingsSaveSignature;
        private readonly AgentConnectionAuthenticator _authenticator;
        private readonly LauncherUnattendedCredentialBootstrap
            _unattendedBootstrap;
        private readonly AgentRuntimeRevocationCoordinator _revocations;
        private readonly NativeInputGuard _nativeGuard;
        private readonly ObservationCaptureBroker _captures;
        private readonly PixelContentHandleStore _content;
        private readonly AppendOnlyAuditSegment _audit;
        private readonly ScopedAgentRuntimeAuditLedgerManager
            _scopedAudit;
        private readonly AgentRendezvousStore _rendezvous;
        private readonly AgentRuntimeNamedPipeHost _pipe;
        private readonly CancellationTokenSource _stop =
            new CancellationTokenSource();
        private readonly EventHandler<
            SessionSurfaceRegistryChangedEventArgs>
                _registryChanged;
        private Task _runTask;
        private int _admissionStopped;
        private int _disposeStarted;

        private LauncherAgentRuntimeHost(
            string projectRoot,
            IAgentRuntimeClock clock,
            AgentRuntimeHostIdentity identity,
            SessionRegistryHostOwner registryOwner,
            SessionSurfaceRegistry registry,
            SessionSurfaceHostController surfaces,
            WindowsSessionSurfaceSynchronizer surfaceSynchronizer,
            PersistentDeveloperEnrollmentStore developerEnrollments,
            ILauncherAgentDeveloperEnrollmentPresenter
                developerEnrollmentPresenter,
            PersistentHairDomainAuthority hairAuthority,
            HairAppearanceModifierTransaction hairTransaction,
            LauncherAgentHairConsentPresenter
                ownedHairConsentPresenter,
            LauncherAgentStructuredActionHost
                ownedStructuredActions,
            LauncherWingsRuntimeHost wings,
            Form wingsOwner,
            Func<
                LauncherAgentRuntimeWingsContext,
                LoreView,
                LauncherWingsRuntimeHost> wingsFactory,
            LauncherAgentRuntimeWingsContext wingsContext,
            HostPrincipalEnrollmentVerifier principalVerifier,
            PrincipalCredentialAuthority principalCredentials,
            ObservationGrantBroker observationGrants,
            Func<
                PrincipalCredential,
                WingsVirtualAuthenticatedConnection>
                    wingsVirtualConnectionFactory,
            AgentConnectionAuthenticator authenticator,
            LauncherUnattendedCredentialBootstrap
                unattendedBootstrap,
            AgentRuntimeRevocationCoordinator revocations,
            NativeInputGuard nativeGuard,
            ObservationCaptureBroker captures,
            PixelContentHandleStore content,
            AppendOnlyAuditSegment audit,
            ScopedAgentRuntimeAuditLedgerManager scopedAudit,
            AgentRendezvousStore rendezvous,
            AgentRuntimeGateway gateway,
            LauncherAgentRuntimeTargetIds targets,
            EventHandler<SessionSurfaceRegistryChangedEventArgs>
                registryChanged,
            string lifecycleId)
        {
            _projectRoot = projectRoot;
            _clock = clock;
            _identity = identity;
            _registryOwner = registryOwner;
            _registry = registry;
            _surfaces = surfaces;
            _humanOnlySecuritySurfaces =
                new HumanOnlySecuritySurfaceAuthority(
                    _surfaces.SetExternalBlockingModal);
            _surfaceSynchronizer = surfaceSynchronizer;
            _developerEnrollments = developerEnrollments;
            _developerEnrollmentPresenter =
                developerEnrollmentPresenter;
            _hairAuthority = hairAuthority;
            _hairTransaction = hairTransaction
                ?? throw new ArgumentNullException(
                    nameof(hairTransaction));
            _ownedHairConsentPresenter =
                ownedHairConsentPresenter;
            _ownedStructuredActions = ownedStructuredActions;
            _wings = wings;
            _wingsOwner = wingsOwner;
            _wingsFactory = wingsFactory;
            _wingsContext = wingsContext;
            _principalVerifier = principalVerifier;
            _principalCredentials = principalCredentials;
            _observationGrants = observationGrants;
            _wingsVirtualConnectionFactory =
                wingsVirtualConnectionFactory;
            _authenticator = authenticator;
            _unattendedBootstrap =
                unattendedBootstrap;
            _revocations = revocations;
            _nativeGuard = nativeGuard;
            _captures = captures;
            _content = content;
            _audit = audit;
            _scopedAudit = scopedAudit;
            _rendezvous = rendezvous;
            Targets = targets;
            GatewayForTests = gateway;
            _registryChanged = registryChanged;
            LifecycleId = lifecycleId;

            string pipeId = OpaqueIdGenerator.Create("pipe");
            _pipe = new AgentRuntimeNamedPipeHost(
                pipeId,
                gateway);
            try
            {
                // The first kernel pipe exists before a client can observe
                // rendezvous.json. RunAsync remains the sole accept owner.
                _pipe.Prepare();
                _rendezvous.Publish(
                    new AgentRendezvousOwner(
                        pipeId,
                        _registryOwner.LauncherProcess.ProcessId,
                        _registryOwner.LauncherProcess
                            .StartTimeUtc,
                        LifecycleId,
                        QualificationWireName(
                            _identity.Qualification
                                .RuntimeMode)),
                    AgentRendezvousStore.MaximumTicketTtl);
                _runTask = _pipe.RunAsync(_stop.Token);
                TryAudit(
                    "agent_runtime_started",
                    new
                    {
                        sessionId = _surfaces.SessionId,
                        runtimeMode =
                            _identity.Qualification.RuntimeMode,
                        pipePreparedBeforePublish = true
                    });
            }
            catch
            {
                DisposeAsync().AsTask()
                    .GetAwaiter()
                    .GetResult();
                throw;
            }
        }

        public LauncherAgentRuntimeTargetIds Targets { get; }

        public string SessionId => _surfaces.SessionId;

        public string RendezvousPath => _rendezvous.Path;

        public string LifecycleId { get; }

        public string UnattendedSlot =>
            _unattendedBootstrap?.Slot;

        internal AgentRuntimeGateway GatewayForTests { get; }

        internal bool IsDisposedForTests =>
            Volatile.Read(ref _disposeStarted) != 0;

        internal SessionSnapshot SnapshotForTests =>
            _surfaces.Snapshot;

        public static LauncherAgentRuntimeHost CreateProduction(
            LauncherAgentRuntimeHostOptions options,
            LauncherAgentRuntimeHostServices services = null)
        {
            ValidateOptions(options);
            services ??= new LauncherAgentRuntimeHostServices();

            IAgentRuntimeClock clock =
                services.Clock ?? new SystemAgentRuntimeClock();
            AgentRuntimeHostIdentity identity =
                AgentRuntimeHostIdentity.Resolve(
                    options.IsolatedRuntimeCandidate);
            SessionSurfaceRegistry registry;
            SessionRegistryHostOwner registryOwner;
            if (services.Registry == null
                && services.RegistryOwner == null)
            {
                registry =
                    SessionSurfaceRegistry
                        .CreateForCurrentLauncher(
                            out registryOwner);
            }
            else if (services.Registry != null
                && services.RegistryOwner != null)
            {
                registry = services.Registry;
                registryOwner = services.RegistryOwner;
            }
            else
            {
                throw new ArgumentException(
                    "Registry and RegistryOwner must be supplied together.",
                    nameof(services));
            }

            string localRoot = ResolveLocalRoot(
                options.LocalAppDataOverride);
            IAgentRendezvousFileProtection protection =
                services.FileProtection;
            bool qualified =
                identity.Qualification.RuntimeMode
                    != RuntimeMode.UnqualifiedDev;
            bool hairEnabled =
                qualified
                && options.HairdresserTask != null
                && (options.HairConsentPresenter != null
                    || options.Owner != null);
            bool structuredEnabled =
                qualified
                && options.StructuredActions?.IsComplete == true;
            LauncherAgentRuntimeTargetIds targets =
                LauncherAgentRuntimeTargetIds.Create();
            IReadOnlyDictionary<
                string,
                Func<LauncherAgentExactTargetBinding, bool>>
                    targetActivators = null;
            if (structuredEnabled)
            {
                targetActivators =
                    options.StructuredActions
                        .CreateTargetActivators(targets);
            }
            bool activationEnabled =
                structuredEnabled
                && HasProductionActivationProvider(
                    targetActivators,
                    targets);
            string[] sessionCapabilities =
                BuildSessionCapabilities(
                    qualified,
                    hairEnabled,
                    structuredEnabled,
                    activationEnabled);
            LauncherUnattendedBootstrapRequest
                unattendedRequest =
                    LauncherUnattendedBootstrapRequest
                        .Import(
                            options.ProjectRoot,
                            localRoot,
                            options
                                .UnattendedBootstrapRequestPath,
                            clock,
                            identity,
                            protection);
            var surfaces =
                new SessionSurfaceHostController(
                    registry,
                    registryOwner,
                    identity.Qualification,
                    identity.CoreSha256,
                    sessionCapabilities,
                    unattendedRequest?.Slot
                        ?? "launcher_idle",
                    unattendedRequest == null
                        ? SessionMode
                            .DeveloperInteractive
                        : SessionMode.UnattendedTest);

            string projectHash =
                AgentRendezvousPath.ComputeProjectRootHash(
                    options.ProjectRoot);
            string runtimeRoot = Path.Combine(
                localRoot,
                "CF7FlashNight",
                "agent-runtime",
                "v1",
                projectHash);
            var developerEnrollments =
                new PersistentDeveloperEnrollmentStore(
                    options.ProjectRoot,
                    clock,
                    Path.Combine(
                        runtimeRoot,
                        "developer-credentials"),
                    protection);
            LauncherUnattendedCredentialBootstrap
                unattendedBootstrap =
                    unattendedRequest == null
                        ? null
                        : new LauncherUnattendedCredentialBootstrap(
                            unattendedRequest,
                            clock,
                            surfaces,
                            protection);
            IUnattendedCredentialBindingAuthority
                unattendedBindings =
                    unattendedBootstrap != null
                        ? unattendedBootstrap
                        : new RejectingUnattendedCredentialBindingAuthority();
            var verifier =
                new HostPrincipalEnrollmentVerifier(
                    developerEnrollments);
            var credentials =
                new PrincipalCredentialAuthority(
                    clock,
                    verifier);
            var grants = new ObservationGrantBroker(
                clock,
                credentials,
                registry);
            var leases = new WriteLeaseBroker(
                clock,
                credentials,
                registry);
            var revocations =
                new AgentRuntimeRevocationCoordinator(
                    credentials,
                    grants,
                    leases);
            ScopedAgentRuntimeAuditLedgerManager
                scopedAudit = null;
            EventHandler<SessionSurfaceRegistryChangedEventArgs>
                registryChanged =
                    (_, args) =>
                    {
                        try
                        {
                            revocations
                                .HandleSessionInvalidation(
                                    args.Invalidation);
                        }
                        catch (ObjectDisposedException)
                        {
                        }
                        if (args.Invalidation.Level
                                == SessionInvalidationLevel
                                    .Registration
                            || args.Invalidation.Level
                                == SessionInvalidationLevel
                                    .Lifecycle)
                        {
                            try
                            {
                                scopedAudit?.InvalidateSession(
                                    args.Invalidation.SessionId,
                                    args.Invalidation
                                        .LifecycleGeneration,
                                    args.Invalidation.ReasonCode
                                        ?? "session_invalidated");
                            }
                            catch
                            {
                                // Registry invalidation remains the source
                                // of truth. Future audit appends re-check it
                                // and fail closed even if sealing failed.
                            }
                        }
                    };
            registry.Changed += registryChanged;

            NativeInputGuard nativeGuard = null;
            LauncherAgentStructuredActionHost
                ownedStructured = null;
            LauncherAgentHairConsentPresenter
                ownedHairPresenter = null;
            LauncherWingsRuntimeHost wings = null;
            ObservationCaptureBroker captures = null;
            PixelContentHandleStore content = null;
            AgentConnectionAuthenticator authenticator = null;
            AgentRendezvousStore rendezvous = null;
            WindowsSessionSurfaceSynchronizer synchronizer =
                null;
            AppendOnlyAuditSegment audit = null;
            PersistentHairDomainAuthority hairAuthority =
                null;
            HairAppearanceModifierTransaction hair = null;

            try
            {
                audit = new AppendOnlyAuditSegment(clock);
                scopedAudit =
                    new ScopedAgentRuntimeAuditLedgerManager(
                        clock,
                        credentials,
                        new RegistryAgentAuditScopeAuthority(
                            registry),
                        requireTrustedConnections: true);
                content = new PixelContentHandleStore(
                    clock,
                    grants,
                    new AppendOnlyPixelContentAuditSink(
                        audit));
                captures = new ObservationCaptureBroker(
                    clock,
                    grants,
                    new SessionSurfaceObservationAuthority(
                        registry),
                    services.FrameSources
                        ?? new WindowsGraphicsCaptureSourceFactory(),
                    null,
                    content);
                var observationStore =
                    new AgentObservationEnvelopeStore();
                var hairConsentBroker =
                    new HairAppearanceConsentBroker(clock);
                hairAuthority =
                    new PersistentHairDomainAuthority(
                        options.ProjectRoot,
                        localRoot,
                        protection);
                IHairdresserDomainAdapter hairAdapter =
                    hairEnabled
                        ? new HairdresserTaskDomainAdapter(
                            options.HairdresserTask,
                            hairAuthority)
                        : new FailClosedHairdresserDomainAdapter();
                IHairRestorePointStore restoreStore =
                    hairEnabled
                        ? new PersistentHairRestorePointStore(
                            options.ProjectRoot,
                            localRoot,
                            protection)
                        : new FailClosedHairRestorePointStore();
                hair =
                    new HairAppearanceModifierTransaction(
                        hairAdapter,
                        restoreStore,
                        hairConsentBroker,
                        clock);
                IAgentHairConsentPresenter hairPresenter =
                    options.HairConsentPresenter;
                if (hairPresenter == null
                    && hairEnabled)
                {
                    ownedHairPresenter =
                        new LauncherAgentHairConsentPresenter(
                            options.Owner,
                            clock,
                            surfaces,
                            registryOwner);
                    hairPresenter = ownedHairPresenter;
                }
                hairPresenter ??=
                    new FailClosedAgentHairConsentPresenter();
                var hairTargets =
                    new RegistryAgentHairDomainTargetAuthority(
                        registry);
                var hairConsent =
                    new AgentHairConsentIssuanceService(
                        hair,
                        hairPresenter,
                        registry,
                        grants,
                        hairTargets);
                var hairPreviews =
                    new AgentHairPreviewStore();

                IAgentStructuredActionHost structuredHost =
                    new FailClosedAgentStructuredActionHost();
                if (structuredEnabled)
                {
                    ownedStructured =
                        new LauncherAgentStructuredActionHost(
                            registry.GetSnapshot,
                            options.StructuredActions
                                .MarshalToUi,
                            targetActivators,
                            options.StructuredActions
                                .PrepareSafeExit,
                            options.StructuredActions
                                .CompleteSafeExit,
                            options.StructuredActions
                                .AbortSafeExit,
                            options.StructuredActions
                                .RevealLifecycle,
                            options.StructuredActions
                                .CancelLifecycle,
                            options.StructuredActions
                                .TryOpenPanel);
                    structuredHost = ownedStructured;
                }

                IAgentWriteLeaseLifecycle leaseLifecycle;
                IAgentRuntimeActionPerformer performer;
                if (qualified)
                {
                    var safety =
                        new InputSafetyStateMachine(clock);
                    INativeInputWin32Facade native =
                        services.NativeInput
                        ?? new Win32NativeInputFacade();
                    var nativeTargets =
                        new SessionNativeInputAuthority(
                            registry);
                    nativeGuard = new NativeInputGuard(
                        safety,
                        native,
                        revocations);
                    revocations.BindNativeGuard(nativeGuard);
                    var nativeExecutor =
                        new NativeInputExecutor(
                            safety,
                            nativeGuard,
                            native,
                            nativeTargets);
                    leaseLifecycle =
                        new NativeInputWriteLeaseLifecycle(
                            nativeTargets,
                            safety,
                            nativeGuard);
                    performer =
                        new CompositeAgentRuntimeActionPerformer(
                            nativeExecutor,
                            nativeGuard,
                            safety,
                            observationStore,
                            structuredHost,
                            hair,
                            hairPreviews,
                            hairTargets);
                }
                else
                {
                    leaseLifecycle =
                        new FailClosedAgentWriteLeaseLifecycle();
                    performer =
                        new FailClosedRuntimeActionPerformer();
                }

                var ledger = new ActionIdempotencyLedger();
                var actions =
                    new AgentRuntimeActionExecutionBroker(
                        captures,
                        observationStore,
                        leases,
                        ledger,
                        revocations,
                        performer,
                        scopedAudit);
                var minimalSessions =
                    new RegistryMinimalSessionReferenceProvider(
                        registry,
                        OpaqueIdGenerator.Create(
                            "lifecyclesalt"));
                var hostMethods =
                    new LauncherAgentRuntimeHostMethodService(
                        options.ProjectRoot,
                        clock,
                        audit,
                        surfaces,
                        minimalSessions,
                        grants,
                        identity,
                        Path.Combine(runtimeRoot, "exports"),
                        protection,
                        scopedAudit);
                var dispatcher =
                    new AgentRuntimeMethodDispatcher(
                        registry,
                        minimalSessions,
                        grants,
                        captures,
                        content,
                        observationStore,
                        leases,
                        leaseLifecycle,
                        revocations,
                        ledger,
                        actions,
                        hair,
                        hairPreviews,
                        hairTargets,
                        hairConsent,
                        hostMethods,
                        scopedAudit);
                authenticator =
                    new AgentConnectionAuthenticator(
                        developerEnrollments,
                        verifier,
                        credentials,
                        unattendedBindings);

                var rendezvousCandidate =
                    new AgentRendezvousStore(
                        options.ProjectRoot,
                        localRoot,
                        services.RendezvousClock,
                        services.RendezvousProcessProbe,
                        protection);
                rendezvous = rendezvousCandidate;
                string lifecycleId =
                    OpaqueIdGenerator.Create("lifecycle");
                var connectionResources =
                    new AgentConnectionResourceAuthority(
                        revocations,
                        unattendedBindings,
                        new RegistryAgentRuntimeConnectionAuditSink(
                            registry,
                            scopedAudit));
                Func<
                    PrincipalCredential,
                    WingsVirtualAuthenticatedConnection>
                        wingsVirtualConnectionFactory =
                            principal =>
                                new WingsVirtualAuthenticatedConnection(
                                    principal,
                                    connectionResources,
                                    dispatcher,
                                    clock);
                var gateway = new AgentRuntimeGateway(
                    new AgentRendezvousTicketAuthority(
                        rendezvousCandidate,
                        lifecycleId),
                    new AgentConnectionAuthenticationAuthority(
                        authenticator),
                    connectionResources,
                    clock,
                    minimalSessions,
                    dispatcher,
                    OpaqueIdGenerator.Create("server"));

                IReadOnlyCollection<WindowsSessionSurfaceSpec>
                    SurfaceSource()
                {
                    IReadOnlyCollection<
                        WindowsSessionSurfaceSpec> source =
                            options.SurfaceSource(targets)
                            ?? Array.Empty<
                                WindowsSessionSurfaceSpec>();
                    return SanitizeSurfaceSpecs(
                        source,
                        qualified,
                        hairEnabled);
                }

                LauncherAgentRuntimeHost host = null;
                synchronizer =
                    new WindowsSessionSurfaceSynchronizer(
                        surfaces,
                        SurfaceSource,
                        services.SurfaceProbe,
                        _ =>
                            host?.SynchronizeUnattendedBinding(
                                allowPublish: true));
                synchronizer.Refresh();

                ILauncherAgentDeveloperEnrollmentPresenter
                    enrollmentPresenter =
                        options
                            .DeveloperEnrollmentPresenter;
                if (enrollmentPresenter == null
                    && options.Owner != null)
                {
                    enrollmentPresenter =
                        new LauncherAgentDeveloperEnrollmentPresenter(
                            options.Owner,
                            surfaces,
                            registryOwner);
                }

                var wingsContext =
                    new LauncherAgentRuntimeWingsContext(
                        surfaces,
                        registryOwner,
                        targets);

                host = new LauncherAgentRuntimeHost(
                    options.ProjectRoot,
                    clock,
                    identity,
                    registryOwner,
                    registry,
                    surfaces,
                    synchronizer,
                    developerEnrollments,
                    enrollmentPresenter,
                    hairAuthority,
                    hair,
                    ownedHairPresenter,
                    ownedStructured,
                    wings,
                    options.Owner,
                    options.WingsFactory,
                    wingsContext,
                    verifier,
                    credentials,
                    grants,
                    wingsVirtualConnectionFactory,
                    authenticator,
                    unattendedBootstrap,
                    revocations,
                    nativeGuard,
                    captures,
                    content,
                    audit,
                    scopedAudit,
                    rendezvous,
                    gateway,
                    targets,
                    registryChanged,
                    lifecycleId);
                synchronizer.Start(
                    options.SurfaceRefreshInterval);
                return host;
            }
            catch
            {
                TryDispose(rendezvous);
                synchronizer?.Stop();
                TryDispose(wings);
                TryDispose(ownedHairPresenter);
                TryDispose(ownedStructured);
                TryDispose(hair);
                hairAuthority?.Unbind();
                try
                {
                    surfaces.ClearAttempt();
                }
                catch
                {
                }
                TryDispose(synchronizer);
                registry.Changed -= registryChanged;
                TryDispose(revocations);
                TryDispose(nativeGuard);
                TryDispose(captures);
                TryDispose(content);
                TryDispose(unattendedBootstrap);
                TryDispose(authenticator);
                scopedAudit?.TruncateAll(
                    "startup_failed");
                TryDispose(scopedAudit);
                TrySealTruncated(audit, "startup_failed");
                throw;
            }
        }

        public bool RefreshSurfaces()
        {
            if (IsStopping())
                return false;
            try
            {
                _surfaceSynchronizer.Refresh();
                return true;
            }
            catch
            {
                return false;
            }
        }

        public bool SynchronizeLaunchSnapshot(
            GameLaunchFlow.AgentRuntimeLaunchSnapshot snapshot)
        {
            if (IsStopping())
                return false;
            if (snapshot == null)
                return ClearAttempt(false);

            bool hasAnyAttemptField =
                snapshot.AttemptId != null
                || snapshot.Slot != null
                || snapshot.FlashProcess != null;
            if (!hasAnyAttemptField)
                return ClearAttempt(true);
            if (string.IsNullOrWhiteSpace(snapshot.AttemptId)
                || string.IsNullOrWhiteSpace(snapshot.Slot)
                || snapshot.FlashProcess == null
                || !TryCaptureProcessIdentity(
                    snapshot.FlashProcess,
                    out SessionProcessIdentity flash))
            {
                return ClearAttempt(false);
            }

            try
            {
                _surfaces.SetAttempt(
                    snapshot.AttemptId,
                    flash,
                    snapshot.Slot,
                    null);
                BindHairIfAuthoritative(snapshot);
                TryConfigureBaselineWings(
                    snapshot.SaveSignature);
                RefreshSurfaces();
                SynchronizeUnattendedBinding(
                    allowPublish: true);
                return true;
            }
            catch
            {
                _hairAuthority?.Unbind();
                return false;
            }
        }

        public bool AdvanceWebDocument()
        {
            if (IsStopping())
                return false;
            try
            {
                _surfaces.AdvanceWebDocument(
                    Targets.WebOverlay);
                return true;
            }
            catch
            {
                return false;
            }
        }

        public bool SetActivePanel(
            string name,
            string instanceId)
        {
            if (IsStopping())
                return false;
            try
            {
                bool clear =
                    name == null && instanceId == null;
                _surfaces.SetActivePanel(
                    clear ? null : name,
                    clear ? null : instanceId,
                    clear ? null : Targets.WebOverlay);
                return true;
            }
            catch
            {
                return false;
            }
        }

        public IDisposable EnterHumanOnlySecuritySurface()
        {
            if (IsStopping())
                return null;
            return _humanOnlySecuritySurfaces.Enter();
        }

        /// <summary>
        /// Returns only the protected credential file path. The bearer proof
        /// remains inside that file and is never surfaced or logged here.
        /// </summary>
        public string ShowDeveloperEnrollmentDialog()
        {
            if (IsStopping()
                || _developerEnrollmentPresenter == null)
            {
                return null;
            }
            try
            {
                SessionSnapshot session = _surfaces.Snapshot;
                LauncherAgentEnrollmentTargetOption[] targets =
                    session.Surfaces
                        .Where(surface =>
                            surface.SafetyKind
                                == AgentTargetSafetyKind
                                    .RuntimeOwned)
                        .Take(
                            AgentProtocolV1
                                .MaximumTargetScopeItems)
                        .Select(surface =>
                            new LauncherAgentEnrollmentTargetOption(
                                surface.TargetId,
                                surface.Kind,
                                SurfaceDisplayName(surface.Kind)))
                        .ToArray();
                if (targets.Length == 0)
                    return null;

                string[] capabilities =
                    EnrollmentCapabilities(
                        session.Capabilities);
                var request =
                    new LauncherAgentDeveloperEnrollmentPresentationRequest(
                        capabilities,
                        targets);
                LauncherAgentDeveloperEnrollmentSelection selection =
                    _developerEnrollmentPresenter.Present(
                        request);
                if (selection == null
                    || !IsExactSubset(
                        capabilities,
                        selection.AllowedCapabilities)
                    || !IsExactSubset(
                        targets.Select(
                            target => target.TargetId),
                        selection.AllowedTargets))
                {
                    return null;
                }
                int revokedConnections =
                    _revocations.RevokeDeveloperEnrollment(
                        selection.ClientInstanceId,
                        "developer_enrollment_rotated");
                DeveloperEnrollment enrollment =
                    _developerEnrollments.IssueOrRotate(
                        selection.ClientInstanceId,
                        selection.AllowedCapabilities,
                        selection.AllowedTargets,
                        selection.Lifetime);
                _revocations.ActivateDeveloperEnrollment(
                        selection.ClientInstanceId,
                        enrollment.EnrollmentReceipt,
                        "developer_enrollment_rotated");
                TryAudit(
                    "developer_enrollment_written",
                    new
                    {
                        clientInstanceId =
                            selection.ClientInstanceId,
                        capabilityCount =
                            selection
                                .AllowedCapabilities.Count,
                        targetCount =
                            selection.AllowedTargets.Count,
                        expiresUtc = enrollment.ExpiresUtc,
                        revokedConnections
                    });
                return enrollment.CredentialFilePath;
            }
            catch
            {
                return null;
            }
        }

        public bool RevokeDeveloperEnrollment(
            string clientInstanceId)
        {
            if (IsStopping()
                || string.IsNullOrWhiteSpace(
                    clientInstanceId))
            {
                return false;
            }
            try
            {
                int revokedConnections =
                    _revocations.RevokeDeveloperEnrollment(
                        clientInstanceId,
                        "developer_enrollment_revoked");
                bool removed =
                    _developerEnrollments.Revoke(
                        clientInstanceId);
                TryAudit(
                    "developer_enrollment_revoked",
                    new
                    {
                        clientInstanceId,
                        credentialFileRemoved = removed,
                        revokedConnections
                    });
                return removed || revokedConnections > 0;
            }
            catch
            {
                return false;
            }
        }

        public bool TryShowWings(out string reasonCode)
        {
            lock (_stateSync)
            {
                if (IsStopping()
                    || !IsWingsSessionEligible())
                {
                    RetireWingsLocked();
                    reasonCode = "wings_unavailable";
                    return false;
                }
                if (_wings == null)
                {
                    reasonCode = "wings_unavailable";
                    return false;
                }
                try
                {
                    return _wings.TryShow(out reasonCode);
                }
                catch
                {
                    reasonCode = "wings_unavailable";
                    return false;
                }
            }
        }

        public bool TryHideWings(out string reasonCode)
        {
            lock (_stateSync)
            {
                if (IsStopping()
                    || !IsWingsSessionEligible())
                {
                    RetireWingsLocked();
                    reasonCode = "wings_unavailable";
                    return false;
                }
                if (_wings == null)
                {
                    reasonCode = "wings_unavailable";
                    return false;
                }
                try
                {
                    return _wings.TryHide(out reasonCode);
                }
                catch
                {
                    reasonCode = "wings_unavailable";
                    return false;
                }
            }
        }

        public bool TryPauseWings(out string reasonCode)
        {
            lock (_stateSync)
            {
                if (IsStopping()
                    || !IsWingsSessionEligible())
                {
                    RetireWingsLocked();
                    reasonCode = "wings_unavailable";
                    return false;
                }
                if (_wings == null)
                {
                    reasonCode = "wings_unavailable";
                    return false;
                }
                try
                {
                    return _wings.TryPause(out reasonCode);
                }
                catch
                {
                    reasonCode = "wings_unavailable";
                    return false;
                }
            }
        }

        public bool TryResumeWings(out string reasonCode)
        {
            lock (_stateSync)
            {
                if (IsStopping()
                    || !IsWingsSessionEligible())
                {
                    RetireWingsLocked();
                    reasonCode = "wings_unavailable";
                    return false;
                }
                if (_wings == null)
                {
                    reasonCode = "wings_unavailable";
                    return false;
                }
                try
                {
                    return _wings.TryResume(out reasonCode);
                }
                catch
                {
                    reasonCode = "wings_unavailable";
                    return false;
                }
            }
        }

        public bool TryConfigureBaselineWings(
            string saveSignature)
        {
            if (IsStopping()
                || !IsSha256(saveSignature)
                || _surfaces.Snapshot.AttemptGeneration == null)
            {
                return false;
            }
            if (!IsWingsSessionEligible())
            {
                lock (_stateSync)
                    RetireWingsLocked();
                return false;
            }

            lock (_stateSync)
            {
                if (IsStopping()
                    || !IsWingsSessionEligible())
                {
                    RetireWingsLocked();
                    return false;
                }
                if (_wings != null
                    && string.Equals(
                        _wingsSaveSignature,
                        saveSignature,
                        StringComparison.OrdinalIgnoreCase))
                {
                    return true;
                }

                LauncherWingsRuntimeHost replacement = null;
                try
                {
                    LoreView view =
                        CreateHostMinimalLoreView(
                            saveSignature);
                    if (_wingsFactory != null)
                    {
                        replacement = _wingsFactory(
                            _wingsContext,
                            view);
                    }
                    else if (_wingsOwner != null)
                    {
                        replacement =
                            CreateHostMinimalWings(
                                view);
                    }
                    if (replacement == null)
                        return false;
                }
                catch
                {
                    TryDispose(replacement);
                    return false;
                }

                LauncherWingsRuntimeHost retired = _wings;
                if (IsStopping())
                {
                    TryDispose(replacement);
                    return false;
                }
                _wings = replacement;
                _wingsSaveSignature =
                    saveSignature.ToUpperInvariant();
                TryDispose(retired);
                return true;
            }
        }

        public void Dispose()
        {
            DisposeAsync().AsTask()
                .GetAwaiter()
                .GetResult();
        }

        /// <summary>
        /// Synchronously and idempotently removes discovery before cancelling
        /// the root accept lifetime. It performs no wait and is safe for an
        /// early WinForms shutdown callback.
        /// </summary>
        public void StopAdmission()
        {
            if (Interlocked.Exchange(
                    ref _admissionStopped,
                    1) != 0)
            {
                return;
            }

            // A client must lose discovery before the accept lifetime is
            // cancelled. Every public mutation observes _admissionStopped.
            TryDispose(_rendezvous);
            try
            {
                _stop.Cancel();
            }
            catch
            {
            }
        }

        public async ValueTask DisposeAsync()
        {
            if (Interlocked.Exchange(
                    ref _disposeStarted,
                    1) != 0)
            {
                return;
            }

            StopAdmission();

            // No cleanup below may race a newly authenticated connection.
            try
            {
                await _pipe.DisposeAsync()
                    .ConfigureAwait(false);
            }
            catch
            {
            }

            // Stop host ingress first. Teardown mutations below intentionally
            // keep registry.Changed subscribed so all live resources receive
            // the terminal invalidations before revocation is disposed.
            _surfaceSynchronizer.Stop();
            lock (_unattendedBindingSync)
            {
                // StopAdmission prevents a queued refresh callback from
                // entering publication. This barrier lets any in-flight
                // publication finish before its bootstrap/authenticator
                // dependencies are disposed.
            }
            lock (_stateSync)
            {
                TryDispose(_wings);
                _wings = null;
                _wingsSaveSignature = null;
            }
            TryDispose(_ownedHairConsentPresenter);
            TryDispose(_ownedStructuredActions);
            TryDispose(_hairTransaction);
            TryDispose(_humanOnlySecuritySurfaces);
            _hairAuthority?.Unbind();
            try
            {
                _surfaces.ClearAttempt();
            }
            catch
            {
            }
            TryDispose(_surfaceSynchronizer);
            _registry.Changed -= _registryChanged;
            TryDispose(_revocations);
            TryDispose(_nativeGuard);
            TryDispose(_captures);
            TryDispose(_content);
            TryDispose(_unattendedBootstrap);
            TryDispose(_authenticator);
            TryDispose(_scopedAudit);
            TryAudit(
                "agent_runtime_stopped",
                new
                {
                    sessionId = _surfaces.SessionId,
                    pipeStoppedBeforeCleanup = true
                });
            TrySealCompleted(_audit);
            _stop.Dispose();
        }

        private bool ClearAttempt(bool validIdle)
        {
            try
            {
                _hairAuthority?.Unbind();
                lock (_stateSync)
                {
                    TryDispose(_wings);
                    _wings = null;
                    _wingsSaveSignature = null;
                }
                _surfaces.ClearAttempt();
                RefreshSurfaces();
                SynchronizeUnattendedBinding(
                    allowPublish: false);
                return validIdle;
            }
            catch
            {
                return false;
            }
        }

        private void SynchronizeUnattendedBinding(
            bool allowPublish)
        {
            lock (_unattendedBindingSync)
            {
                if (IsStopping())
                    return;
                SynchronizeUnattendedBindingCore(
                    _unattendedBootstrap,
                    _authenticator,
                    _revocations,
                    allowPublish);
            }
        }

        private static void SynchronizeUnattendedBindingCore(
            LauncherUnattendedCredentialBootstrap
                unattendedBootstrap,
            AgentConnectionAuthenticator authenticator,
            AgentRuntimeRevocationCoordinator revocations,
            bool allowPublish)
        {
            if (unattendedBootstrap == null
                || authenticator == null
                || revocations == null)
            {
                return;
            }
            try
            {
                if (allowPublish)
                {
                    unattendedBootstrap
                        .TryPublishObservedCredential(
                            authenticator,
                            out _);
                }
                unattendedBootstrap
                    .EnforceCurrentBinding(
                        authenticator,
                        revocations);
            }
            catch
            {
                foreach (string credentialId
                    in unattendedBootstrap
                        .TakeInvalidPrincipalCredentialIds())
                {
                    revocations.RevokeCredential(
                        credentialId,
                        "unattended_binding_changed");
                }
            }
        }

        private void BindHairIfAuthoritative(
            GameLaunchFlow.AgentRuntimeLaunchSnapshot snapshot)
        {
            if (_hairAuthority == null
                || _identity.Qualification.RuntimeMode
                    == RuntimeMode.UnqualifiedDev
                || !IsSha256(snapshot.SaveSignature))
            {
                _hairAuthority?.Unbind();
                return;
            }
            SessionSnapshot session = _surfaces.Snapshot;
            if (!session.Capabilities.Contains(
                    AgentCapabilitiesV1
                        .AppearanceHairChange,
                    StringComparer.Ordinal)
                || session.AttemptGeneration == null
                || session.LifecycleGeneration > long.MaxValue
                || session.AttemptGeneration > long.MaxValue)
            {
                _hairAuthority.Unbind();
                return;
            }
            _hairAuthority.Bind(
                new HairSaveBinding(
                    session.SessionId,
                    checked((long)
                        session.LifecycleGeneration),
                    session.AttemptId,
                    checked((long)
                        session.AttemptGeneration.Value),
                    session.Slot,
                    snapshot.SaveSignature));
        }

        private bool IsStopping()
        {
            return Volatile.Read(ref _admissionStopped) != 0
                || Volatile.Read(ref _disposeStarted) != 0;
        }

        private bool IsWingsSessionEligible()
        {
            try
            {
                return _surfaces.Snapshot.SessionMode
                    != SessionMode.UnattendedTest;
            }
            catch
            {
                return false;
            }
        }

        private void RetireWingsLocked()
        {
            LauncherWingsRuntimeHost retired = _wings;
            _wings = null;
            _wingsSaveSignature = null;
            TryDispose(retired);
        }

        private LoreView CreateHostMinimalLoreView(
            string saveSignature)
        {
            string catalogPath = Path.Combine(
                _projectRoot,
                "launcher",
                "agent-assets",
                "lore",
                "public-companion.v1.json");
            byte[] payload = File.ReadAllBytes(catalogPath);
            LoreCatalog catalog =
                LoreCatalogParser.Parse(payload);
            SessionSnapshot session = _surfaces.Snapshot;
            string bindingSource = string.Join(
                "\n",
                "cf7.wings.host-minimal.v1",
                session.SessionId,
                session.Slot ?? string.Empty,
                saveSignature.ToUpperInvariant());
            string saveBindingId =
                Convert.ToBase64String(
                        SHA256.HashData(
                            Encoding.UTF8.GetBytes(
                                bindingSource)))
                    .TrimEnd('=')
                    .Replace('+', '-')
                    .Replace('/', '_');
            var progress = new LoreProgressSnapshot(
                saveBindingId,
                saveSignature,
                WingsSaveClass.Legacy,
                catalog.PublicStoryPhaseIds[0],
                "host-minimal-v1",
                Array.Empty<string>(),
                new Dictionary<string, string>(
                    StringComparer.Ordinal),
                Array.Empty<string>());
            return new LoreProjectionService().Project(
                catalog,
                progress);
        }

        private LauncherWingsRuntimeHost
            CreateHostMinimalWings(LoreView view)
        {
            if (!IsWingsSessionEligible())
            {
                throw new InvalidOperationException(
                    "Wings is unavailable in unattended sessions.");
            }
            bool playerAssistEnabled =
                _identity.Qualification.RuntimeMode
                    != RuntimeMode.UnqualifiedDev;
            LauncherWingsPlayerAssistAuthority authority =
                playerAssistEnabled
                    ? new LauncherWingsPlayerAssistAuthority(
                        _wingsOwner,
                        _clock,
                        _surfaces,
                        _registryOwner,
                        _principalVerifier,
                        _principalCredentials,
                        _observationGrants,
                        Targets.WebOverlay,
                        view)
                    : null;
            LauncherWingsStructuredActionCoordinator
                structuredActions =
                    authority == null
                        ? null
                        : _hairAuthority == null
                            ? new LauncherWingsStructuredActionCoordinator(
                                _wingsOwner,
                                _clock,
                                _surfaces,
                                _registryOwner,
                                authority,
                                _principalVerifier,
                                _principalCredentials,
                                _observationGrants,
                                _nativeGuard,
                                _wingsVirtualConnectionFactory,
                                _surfaces.SessionId,
                                Targets.Flash,
                                view)
                            : new LauncherWingsStructuredActionCoordinator(
                                _wingsOwner,
                                _clock,
                                _surfaces,
                                _registryOwner,
                                authority,
                                _principalVerifier,
                                _principalCredentials,
                                _observationGrants,
                                _nativeGuard,
                                _wingsVirtualConnectionFactory,
                                _surfaces.SessionId,
                                Targets.Flash,
                                Targets.WebOverlay,
                                view);
            LauncherWingsRuntimeHost runtime = null;
            try
            {
                runtime = new LauncherWingsRuntimeHost(
                    _wingsOwner,
                    _surfaces,
                    _registryOwner,
                    _surfaces.SessionId,
                    Targets.WingsShell,
                    Targets.Launcher,
                    view,
                    1,
                    text => CreateHostMinimalGuidance(
                        view,
                        text,
                        authority),
                    effects =>
                    {
                        if (effects.HasFlag(
                                WingsShellEffect.SuspendReadGrant))
                        {
                            authority?.Suspend(
                                "wings_shell_paused");
                        }
                    },
                    () =>
                    {
                        if (authority != null)
                        {
                            runtime
                                .RequestNeutralConsentPresentation();
                        }
                    },
                    authority == null
                        ? () => null
                        : authority.CreatePrompt,
                    (INeutralConsentDecisionSink)authority
                        ?? new RejectingNeutralConsentDecisionSink(),
                    consentFactsAuthority: authority,
                    utcNow: () => _clock.UtcNow,
                    ownedConsentAuthority: authority,
                    virtualConnectionFactory:
                        _wingsVirtualConnectionFactory,
                    structuredActions: structuredActions);
            }
            catch
            {
                structuredActions?.Dispose();
                authority?.Dispose();
                throw;
            }
            if (authority != null)
            {
                authority.AuthorizationChanged +=
                    (_, change) =>
                        runtime.ApplyPlayerAssistAuthorization(
                            view,
                            change);
            }
            return runtime;
        }

        private WingsGuidanceRequest CreateHostMinimalGuidance(
            LoreView view,
            string text,
            LauncherWingsPlayerAssistAuthority authority)
        {
            (WingsGuidanceDomain Domain, string Key) route =
                MapHostMinimalGuidance(text);
            return WingsGuidanceRequest.ForGuidance(
                _surfaces.SessionId,
                view,
                route.Domain,
                route.Key,
                authority?.VisibleContext(route.Domain)
                    ?? WingsVisibleGuidanceContext.Empty(
                        route.Domain));
        }

        private static (
            WingsGuidanceDomain Domain,
            string Key) MapHostMinimalGuidance(
                string text)
        {
            string value = text ?? string.Empty;
            if (value.Contains(
                    "装备",
                    StringComparison.OrdinalIgnoreCase)
                || value.Contains(
                    "equipment",
                    StringComparison.OrdinalIgnoreCase))
            {
                return (
                    WingsGuidanceDomain.Equipment,
                    "equipment.properties");
            }
            if (value.Contains(
                    "路线",
                    StringComparison.OrdinalIgnoreCase)
                || value.Contains(
                    "地图",
                    StringComparison.OrdinalIgnoreCase)
                || value.Contains(
                    "route",
                    StringComparison.OrdinalIgnoreCase))
            {
                // With empty progress flags this key intentionally resolves
                // to no fact until a real progress authority says otherwise.
                return (
                    WingsGuidanceDomain.Route,
                    "route.map");
            }
            if (value.Contains(
                    "界面",
                    StringComparison.OrdinalIgnoreCase)
                || value.Contains(
                    "ui",
                    StringComparison.OrdinalIgnoreCase))
            {
                return (
                    WingsGuidanceDomain.Ui,
                    "ui.wings_shell");
            }
            return (
                WingsGuidanceDomain.Task,
                "task.overview");
        }

        private void TryAudit(string eventType, object payload)
        {
            if (_audit == null || _audit.IsSealed)
                return;
            try
            {
                string json =
                    System.Text.Json.JsonSerializer.Serialize(
                        payload,
                        AgentProtocolV1.JsonOptions);
                _audit.Append(
                    eventType,
                    CanonicalJsonV1.Canonicalize(json));
            }
            catch
            {
            }
        }

        private static void ValidateOptions(
            LauncherAgentRuntimeHostOptions options)
        {
            if (options == null)
                throw new ArgumentNullException(nameof(options));
            if (string.IsNullOrWhiteSpace(options.ProjectRoot))
            {
                throw new ArgumentException(
                    "A project root is required.",
                    nameof(options));
            }
            if (options.SurfaceSource == null)
            {
                throw new ArgumentException(
                    "A host-owned surface source is required.",
                    nameof(options));
            }
            if (options.SurfaceRefreshInterval
                    < TimeSpan.FromMilliseconds(50)
                || options.SurfaceRefreshInterval
                    > TimeSpan.FromMinutes(1))
            {
                throw new ArgumentOutOfRangeException(
                    nameof(options));
            }
            if (options.StructuredActions != null
                && !options.StructuredActions.IsComplete)
            {
                throw new ArgumentException(
                    "Structured action bindings must be complete.",
                    nameof(options));
            }
        }

        internal static string[] BuildSessionCapabilities(
            bool qualified,
            bool hairEnabled,
            bool structuredEnabled,
            bool activationEnabled)
        {
            var capabilities = new HashSet<string>(
                AgentCapabilitiesV1.All,
                StringComparer.Ordinal);
            capabilities.Remove(
                AgentCapabilitiesV1.SetValue);
            capabilities.Remove(
                AgentCapabilitiesV1
                    .PerformSecondaryAction);
            capabilities.Remove(
                AgentCapabilitiesV1.TraceExport);
            if (!qualified)
                capabilities.ExceptWith(
                    UnqualifiedWriteCapabilities);
            if (!hairEnabled)
            {
                capabilities.Remove(
                    AgentCapabilitiesV1
                        .AppearanceHairChange);
            }
            if (!structuredEnabled)
            {
                capabilities.Remove(
                    AgentCapabilitiesV1.SessionShutdown);
                capabilities.Remove(
                    AgentCapabilitiesV1.LifecycleReveal);
                capabilities.Remove(
                    AgentCapabilitiesV1.LifecycleCancel);
                capabilities.Remove(
                    AgentCapabilitiesV1.PanelOpen);
            }
            if (!activationEnabled)
                capabilities.Remove(
                    AgentCapabilitiesV1.ActivateWindow);
            return capabilities
                .OrderBy(value => value, StringComparer.Ordinal)
                .ToArray();
        }

        internal static bool HasProductionActivationProvider(
            IReadOnlyDictionary<
                string,
                Func<LauncherAgentExactTargetBinding, bool>>
                    targetActivators,
            LauncherAgentRuntimeTargetIds targets)
        {
            if (targetActivators == null
                || targets == null)
            {
                return false;
            }
            return targetActivators.TryGetValue(
                    targets.Flash,
                    out Func<
                        LauncherAgentExactTargetBinding,
                        bool> activator)
                && activator != null;
        }

        private static IReadOnlyCollection<
            WindowsSessionSurfaceSpec> SanitizeSurfaceSpecs(
                IReadOnlyCollection<
                    WindowsSessionSurfaceSpec> source,
                bool qualified,
                bool hairEnabled)
        {
            if (source == null)
                return Array.Empty<WindowsSessionSurfaceSpec>();
            var result =
                new List<WindowsSessionSurfaceSpec>(
                    source.Count);
            foreach (WindowsSessionSurfaceSpec spec in source)
            {
                if (spec == null)
                {
                    result.Add(null);
                    continue;
                }
                InputMode[] input = spec.InputModes
                    .Where(mode =>
                        qualified
                        && (mode == InputMode.SendInputGuarded
                            || hairEnabled
                            && mode
                                == InputMode
                                    .DomainTransaction))
                    .ToArray();
                result.Add(
                    new WindowsSessionSurfaceSpec(
                        spec.TargetId,
                        spec.Kind,
                        spec.SafetyKind,
                        spec.OwnerRelation,
                        spec.OwnerProcess,
                        spec.KnownWindowHandle,
                        spec.OwnerTargetId,
                        spec.OwnerWindowHandle,
                        spec.ObservationModes,
                        input,
                        spec.ZIndex));
            }
            return result;
        }

        internal static string[] EnrollmentCapabilities(
            IEnumerable<string> sessionCapabilities)
        {
            var capabilities = new HashSet<string>(
                sessionCapabilities
                    ?? Array.Empty<string>(),
                StringComparer.Ordinal);
            capabilities.Add(
                AgentCapabilitiesV1.TraceExport);
            capabilities.Add(
                "observation.export");
            capabilities.Add(
                "observe:"
                + ObservationDataScopesV1.DataExport);
            if (capabilities.Contains(
                    AgentCapabilitiesV1.ListWindows)
                || capabilities.Contains(
                    AgentCapabilitiesV1.GetWindow)
                || capabilities.Contains(
                    AgentCapabilitiesV1.GetWindowState))
            {
                capabilities.Add(
                    "observe:"
                    + ObservationDataScopesV1
                        .WindowMetadata);
            }
            if (capabilities.Contains(
                    AgentCapabilitiesV1.ObservationCapture)
                || capabilities.Contains(
                    AgentCapabilitiesV1.GetWindowState))
            {
                capabilities.Add(
                    "observe:"
                    + ObservationDataScopesV1.Pixels);
            }
            if (capabilities.Contains(
                    AgentCapabilitiesV1
                        .AppearanceHairChange))
            {
                capabilities.Add(
                    "observe:"
                    + ObservationDataScopesV1
                        .PlayerState);
            }
            return capabilities
                .OrderBy(value => value, StringComparer.Ordinal)
                .ToArray();
        }

        private static bool IsExactSubset(
            IEnumerable<string> allowed,
            IEnumerable<string> selected)
        {
            var allow = new HashSet<string>(
                allowed ?? Array.Empty<string>(),
                StringComparer.Ordinal);
            string[] values =
                (selected ?? Array.Empty<string>())
                    .Where(value =>
                        !string.IsNullOrWhiteSpace(value))
                    .Distinct(StringComparer.Ordinal)
                    .ToArray();
            return values.Length > 0
                && values.All(allow.Contains);
        }

        private static string SurfaceDisplayName(
            SurfaceKind kind)
        {
            return kind switch
            {
                SurfaceKind.Launcher => "Launcher",
                SurfaceKind.Flash => "Flash 游戏",
                SurfaceKind.WebOverlay => "Web 面板",
                SurfaceKind.NativeHud => "原生 HUD",
                SurfaceKind.WingsShell => "Wings",
                SurfaceKind.BusinessModal => "业务模态窗口",
                _ => kind.ToString()
            };
        }

        private static bool TryCaptureProcessIdentity(
            Process process,
            out SessionProcessIdentity identity)
        {
            identity = null;
            try
            {
                if (process.HasExited)
                    return false;
                string path = process.MainModule?.FileName;
                if (string.IsNullOrWhiteSpace(path))
                    return false;
                identity = new SessionProcessIdentity(
                    process.Id,
                    new DateTimeOffset(
                        process.StartTime.ToUniversalTime()),
                    path);
                return !process.HasExited;
            }
            catch
            {
                identity = null;
                return false;
            }
        }

        private static bool IsSha256(string value)
        {
            if (value == null || value.Length != 64)
                return false;
            for (int index = 0; index < value.Length; index++)
            {
                char character = value[index];
                bool hexadecimal =
                    character is >= '0' and <= '9'
                    || character is >= 'a' and <= 'f'
                    || character is >= 'A' and <= 'F';
                if (!hexadecimal)
                    return false;
            }
            return true;
        }

        private static string ResolveLocalRoot(
            string localAppDataOverride)
        {
            string value = string.IsNullOrWhiteSpace(
                    localAppDataOverride)
                ? Environment.GetFolderPath(
                    Environment.SpecialFolder
                        .LocalApplicationData)
                : Path.GetFullPath(localAppDataOverride);
            if (string.IsNullOrWhiteSpace(value)
                || !Path.IsPathFullyQualified(value))
            {
                throw new InvalidOperationException(
                    "LOCALAPPDATA is unavailable.");
            }
            return value;
        }

        private static string QualificationWireName(
            RuntimeMode mode)
        {
            return mode switch
            {
                RuntimeMode.FormalRuntime =>
                    "formal_runtime",
                RuntimeMode.IsolatedCandidate =>
                    "isolated_candidate",
                _ => "unqualified_dev"
            };
        }

        private static void TryDispose(IDisposable value)
        {
            try
            {
                value?.Dispose();
            }
            catch
            {
            }
        }

        private static void TrySealCompleted(
            AppendOnlyAuditSegment audit)
        {
            if (audit == null || audit.IsSealed)
                return;
            try
            {
                audit.SealCompleted(
                    "{\"shutdownOrder\":\"pipe_then_revoke_then_cleanup\"}");
            }
            catch
            {
            }
        }

        private static void TrySealTruncated(
            AppendOnlyAuditSegment audit,
            string reason)
        {
            if (audit == null || audit.IsSealed)
                return;
            try
            {
                audit.SealTruncated(reason);
            }
            catch
            {
            }
        }

        private sealed class FailClosedRuntimeActionPerformer
            : IAgentRuntimeActionPerformer
        {
            public Task<AgentActionPerformance> PerformAsync(
                AgentRuntimeDispatchContext context,
                ActionEnvelope action,
                WriteLease lease,
                CancellationToken cancellationToken)
            {
                return Task.FromResult(
                    AgentActionPerformance.Rejected(
                        "runtime_unqualified"));
            }
        }

        private sealed class
            RejectingNeutralConsentDecisionSink
            : INeutralConsentDecisionSink
        {
            public void SubmitHumanDecision(
                NeutralConsentDecisionIntent intent)
            {
                // Unqualified runtime never owns player-assist authority.
            }
        }
    }
}
