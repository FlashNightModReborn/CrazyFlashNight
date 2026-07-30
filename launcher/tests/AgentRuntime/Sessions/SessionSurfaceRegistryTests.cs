using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Security;
using CF7Launcher.AgentRuntime.Sessions;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.Sessions
{
    public sealed class SessionSurfaceRegistryTests
    {
        [Fact]
        public void PositiveHostRegistrationBuildsAuthoritativeSnapshot()
        {
            Setup setup = CreateSetup();
            var wrongOwner = new SessionRegistryHostOwner(
                new SessionProcessIdentity(
                    999,
                    Utc(9),
                    Absolute("other-launcher.exe")));

            InvalidOperationException ownerError =
                Assert.Throws<InvalidOperationException>(
                    () => setup.Registry.RegisterSession(
                        wrongOwner,
                        Session(setup)));
            Assert.Equal(
                "launcher_host_owner_mismatch",
                ownerError.Message);

            setup.Registry.RegisterSession(
                setup.Owner,
                Session(setup));
            setup.Registry.RegisterSurface(
                setup.Owner,
                ExpectSession(setup.Registry, SessionId),
                LauncherSurface(setup));

            SessionSurfaceRegistrySnapshot snapshot =
                setup.Registry.GetSnapshot();
            SessionSnapshot session = Assert.Single(snapshot.Sessions);
            SessionSurfaceSnapshot surface =
                Assert.Single(session.Surfaces);
            Assert.Equal(LauncherTarget, surface.TargetId);
            Assert.Equal(1UL, surface.SurfaceEpoch);
            Assert.Equal(1UL, surface.CoordinateSpaceVersion);
            Assert.Equal(setup.Launcher.ProcessId, surface.OwnerProcess.ProcessId);
            Assert.Equal(RuntimeMode.FormalRuntime,
                session.RuntimeQualification.RuntimeMode);
            Assert.Empty(
                AgentContractValidator.Validate(session.ToContract()));
            Assert.Equal(1, setup.Validator.SessionValidationCount);
            Assert.Equal(1, setup.Validator.SurfaceValidationCount);

            Assert.True(setup.Registry.TryResolve(
                SessionId,
                LauncherTarget,
                out AgentTargetDescriptor descriptor,
                out _));
            Assert.Equal(
                AgentTargetSafetyKind.RuntimeOwned,
                descriptor.SafetyKind);
            Assert.False(setup.Registry.TryResolve(
                SessionId,
                Id("unknown"),
                out _,
                out string reason));
            Assert.Equal("target_not_authoritative", reason);
        }

        [Fact]
        public void HumanOnlySurfaceNeverLeaksAndRequiresFreshHumanAuthorization()
        {
            Setup setup = CreateRegisteredSetup();
            setup.Registry.RegisterSurface(
                setup.Owner,
                ExpectSession(setup.Registry, SessionId),
                LauncherSurface(setup));
            var changes =
                new List<SessionSurfaceRegistryChangedEventArgs>();
            setup.Registry.Changed += (_, change) => changes.Add(change);

            SessionSurfaceRegistryChange appeared =
                setup.Registry.RegisterSurface(
                    setup.Owner,
                    ExpectSession(setup.Registry, SessionId),
                    HumanOnlySurface(setup));

            SessionSnapshot blocked =
                setup.Registry.GetSnapshot().FindSession(SessionId);
            Assert.Single(blocked.Surfaces);
            Assert.DoesNotContain(
                blocked.Surfaces,
                surface => surface.TargetId == SecurityTarget);
            Assert.Equal(
                BlockingModalKind.HumanOnlySecurity,
                blocked.BlockingModalKind);
            Assert.True(blocked.HumanReauthorizationRequired);
            Assert.True(appeared.Invalidation.Has(
                SessionInvalidationFlags.WriteLeases));
            Assert.True(appeared.Invalidation.Has(
                SessionInvalidationFlags.QueuedActions));
            Assert.True(appeared.Invalidation.Has(
                SessionInvalidationFlags.RuntimeHeldInput));
            Assert.DoesNotContain(
                SecurityTarget,
                appeared.Invalidation.TargetIds);

            Assert.True(setup.Registry.TryResolve(
                SessionId,
                SecurityTarget,
                out AgentTargetDescriptor securityDescriptor,
                out _));
            Assert.Equal(
                AgentTargetSafetyKind.HumanOnlySecuritySurface,
                securityDescriptor.SafetyKind);
            Assert.False(setup.Registry.TryResolve(
                SessionId,
                LauncherTarget,
                out _,
                out string blockedReason));
            Assert.Equal(
                "human_intervention_required",
                blockedReason);

            setup.Registry.UnregisterSurface(
                setup.Owner,
                new SessionSurfaceMutationExpectation
                {
                    Session = ExpectSession(
                        setup.Registry,
                        SessionId),
                    TargetId = SecurityTarget,
                    SurfaceEpoch = 1,
                    WindowHandle = 1004
                });
            Assert.False(setup.Registry.TryResolve(
                SessionId,
                LauncherTarget,
                out _,
                out string stillBlocked));
            Assert.Equal(
                "human_intervention_required",
                stillBlocked);

            setup.Registry.AcknowledgeHumanReauthorization(
                setup.Owner,
                ExpectSession(setup.Registry, SessionId));
            Assert.True(setup.Registry.TryResolve(
                SessionId,
                LauncherTarget,
                out _,
                out _));
            Assert.Equal(3, changes.Count);
            Assert.True(
                changes[0].Snapshot.Sequence
                < changes[1].Snapshot.Sequence);
            Assert.True(
                changes[1].Snapshot.Sequence
                < changes[2].Snapshot.Sequence);
        }

        [Fact]
        public void AttemptAdvanceRemovesOnlyFlashScopeAndRejectsStaleGeneration()
        {
            Setup setup = CreateSetup();
            setup.Registry.RegisterSession(
                setup.Owner,
                Session(
                    setup,
                    AttemptA,
                    1,
                    setup.Flash));
            setup.Registry.RegisterSurface(
                setup.Owner,
                ExpectSession(setup.Registry, SessionId),
                LauncherSurface(setup));
            setup.Registry.RegisterSurface(
                setup.Owner,
                ExpectSession(setup.Registry, SessionId),
                FlashSurface(setup));
            SessionMutationExpectation stale =
                ExpectSession(setup.Registry, SessionId);

            var nextFlash = new SessionProcessIdentity(
                303,
                Utc(3),
                Absolute("Flash-next.exe"));
            SessionSurfaceRegistryChange change =
                setup.Registry.AdvanceAttempt(
                    setup.Owner,
                    stale,
                    new SessionAttemptRegistration
                    {
                        AttemptId = AttemptB,
                        FlashProcess = nextFlash,
                        Slot = "cf7_agent_next",
                        SaveRevision = 42
                    });

            SessionSnapshot current =
                setup.Registry.GetSnapshot().FindSession(SessionId);
            Assert.Equal(AttemptB, current.AttemptId);
            Assert.Equal(2UL, current.AttemptGeneration);
            Assert.Equal(303, current.FlashProcess.ProcessId);
            Assert.Single(current.Surfaces);
            Assert.Equal(LauncherTarget, current.Surfaces[0].TargetId);
            Assert.True(change.Invalidation.Has(
                SessionInvalidationFlags.WriteLeases));
            Assert.True(change.Invalidation.Has(
                SessionInvalidationFlags.AttemptScopedAuthorities));
            Assert.Contains(FlashTarget, change.Invalidation.TargetIds);
            Assert.DoesNotContain(
                LauncherTarget,
                change.Invalidation.TargetIds);

            InvalidOperationException staleError =
                Assert.Throws<InvalidOperationException>(
                    () => setup.Registry.SetFocus(
                        setup.Owner,
                        stale,
                        LauncherTarget));
            Assert.Equal("stale_attempt", staleError.Message);
            Assert.Equal(1, setup.Validator.AttemptValidationCount);
        }

        [Fact]
        public void SurfaceFocusAndLayoutGenerationsNeverResurrect()
        {
            Setup setup = CreateRegisteredSetup();
            setup.Registry.RegisterSurface(
                setup.Owner,
                ExpectSession(setup.Registry, SessionId),
                LauncherSurface(setup));
            setup.Registry.SetFocus(
                setup.Owner,
                ExpectSession(setup.Registry, SessionId),
                LauncherTarget);
            SessionSurfaceSnapshot focused =
                Surface(setup.Registry, SessionId, LauncherTarget);
            SessionTargetGenerationExpectation oldAction =
                Generation(setup.Registry, SessionId, LauncherTarget);

            setup.Registry.SetFocus(
                setup.Owner,
                ExpectSession(setup.Registry, SessionId),
                null);
            setup.Registry.SetFocus(
                setup.Owner,
                ExpectSession(setup.Registry, SessionId),
                LauncherTarget);
            Assert.False(setup.Registry.TryValidateTargetGeneration(
                oldAction,
                InputMode.SendInputGuarded,
                out _,
                out string focusReason));
            Assert.Equal("stale_focus", focusReason);
            Assert.True(
                Surface(setup.Registry, SessionId, LauncherTarget)
                    .FocusEpoch
                > focused.FocusEpoch);

            setup.Registry.UpdateSurfaceLayout(
                setup.Owner,
                ExpectSurface(
                    setup.Registry,
                    SessionId,
                    LauncherTarget),
                Layout(20, 30, 900, 700));
            SessionSurfaceSnapshot laidOut =
                Surface(setup.Registry, SessionId, LauncherTarget);
            Assert.Equal(2UL, laidOut.SurfaceEpoch);
            Assert.Equal(2UL, laidOut.CoordinateSpaceVersion);
            Assert.False(setup.Registry.TryValidateTargetGeneration(
                oldAction,
                InputMode.SendInputGuarded,
                out _,
                out string surfaceReason));
            Assert.Equal("stale_surface", surfaceReason);
        }

        [Fact]
        public void HwndRebuildAdvancesSurfaceAndCoordinateEpochTogether()
        {
            Setup setup = CreateRegisteredSetup();
            setup.Registry.RegisterSurface(
                setup.Owner,
                ExpectSession(setup.Registry, SessionId),
                LauncherSurface(setup));
            SessionSurfaceMutationExpectation old =
                ExpectSurface(
                    setup.Registry,
                    SessionId,
                    LauncherTarget);

            SessionSurfaceRegistryChange change =
                setup.Registry.RebuildSurface(
                    setup.Owner,
                    old,
                    CopyWithWindowHandle(
                        LauncherSurface(setup),
                        1101));

            SessionSurfaceSnapshot current =
                Surface(setup.Registry, SessionId, LauncherTarget);
            Assert.Equal(1101, current.WindowHandle);
            Assert.Equal(2UL, current.SurfaceEpoch);
            Assert.Equal(2UL, current.CoordinateSpaceVersion);
            Assert.True(change.Invalidation.Has(
                SessionInvalidationFlags.PendingCoordinateActions));
            InvalidOperationException stale =
                Assert.Throws<InvalidOperationException>(
                    () => setup.Registry.UpdateSurfaceLayout(
                        setup.Owner,
                        old,
                        Layout(0, 0, 800, 600)));
            Assert.Equal("stale_surface", stale.Message);
        }

        [Fact]
        public void AuthorityRevalidatesLivePidAndHwndState()
        {
            Setup setup = CreateRegisteredSetup();
            setup.Registry.RegisterSurface(
                setup.Owner,
                ExpectSession(setup.Registry, SessionId),
                LauncherSurface(setup));
            setup.Validator.RejectionReason =
                "surface_owner_process_stale";

            Assert.False(setup.Registry.TryResolve(
                SessionId,
                LauncherTarget,
                out _,
                out string reason));
            Assert.Equal(
                "surface_owner_process_stale",
                reason);
        }

        [Fact]
        public void BusinessAndForeignModalsHaveDifferentRevocationScope()
        {
            Setup setup = CreateRegisteredSetup();
            setup.Registry.RegisterSurface(
                setup.Owner,
                ExpectSession(setup.Registry, SessionId),
                LauncherSurface(setup));

            SessionSurfaceRegistryChange business =
                setup.Registry.RegisterSurface(
                    setup.Owner,
                    ExpectSession(setup.Registry, SessionId),
                    BusinessModal(setup));
            Assert.Equal(
                SessionInvalidationLevel.Modal,
                business.Invalidation.Level);
            Assert.False(business.Invalidation.Has(
                SessionInvalidationFlags.WriteLeases));
            Assert.True(business.Invalidation.Has(
                SessionInvalidationFlags.PendingInput));
            Assert.Equal(
                BlockingModalKind.BusinessOwned,
                setup.Registry.GetSnapshot()
                    .FindSession(SessionId)
                    .BlockingModalKind);

            setup.Registry.UnregisterSurface(
                setup.Owner,
                ExpectSurface(
                    setup.Registry,
                    SessionId,
                    BusinessTarget));
            SessionSurfaceRegistryChange foreign =
                setup.Registry.SetExternalBlockingModal(
                    setup.Owner,
                    ExpectSession(setup.Registry, SessionId),
                    BlockingModalKind.Foreign);
            Assert.Equal(
                SessionInvalidationLevel.Security,
                foreign.Invalidation.Level);
            Assert.True(foreign.Invalidation.Has(
                SessionInvalidationFlags.WriteLeases));
            Assert.True(foreign.Invalidation.Has(
                SessionInvalidationFlags.QueuedActions));

            setup.Registry.SetExternalBlockingModal(
                setup.Owner,
                ExpectSession(setup.Registry, SessionId),
                BlockingModalKind.None);
            Assert.True(
                setup.Registry.GetSnapshot()
                    .FindSession(SessionId)
                    .HumanReauthorizationRequired);
            setup.Registry.AcknowledgeHumanReauthorization(
                setup.Owner,
                ExpectSession(setup.Registry, SessionId));
            Assert.False(
                setup.Registry.GetSnapshot()
                    .FindSession(SessionId)
                    .HumanReauthorizationRequired);
        }

        [Fact]
        public void WebDocumentAndPanelInvalidateOnlyExactScope()
        {
            Setup setup = CreateRegisteredSetup();
            setup.Registry.RegisterSurface(
                setup.Owner,
                ExpectSession(setup.Registry, SessionId),
                WebSurface(setup));
            ActivePanelRegistration panelA = new ActivePanelRegistration
            {
                Name = "hairdresser",
                InstanceId = PanelA,
                TargetId = WebTarget
            };
            setup.Registry.ChangeActivePanel(
                setup.Owner,
                ExpectSession(setup.Registry, SessionId),
                null,
                panelA);
            SessionTargetGenerationExpectation old =
                Generation(setup.Registry, SessionId, WebTarget);

            SessionSurfaceRegistryChange document =
                setup.Registry.AdvanceWebDocument(
                    setup.Owner,
                    ExpectSurface(
                        setup.Registry,
                        SessionId,
                        WebTarget));
            SessionSurfaceSnapshot current =
                Surface(setup.Registry, SessionId, WebTarget);
            Assert.Equal(2UL, current.DocumentGeneration);
            Assert.Equal(1UL, current.SurfaceEpoch);
            Assert.Equal(
                SessionInvalidationLevel.Document,
                document.Invalidation.Level);
            Assert.False(setup.Registry.TryValidateTargetGeneration(
                old,
                InputMode.Cdp,
                out _,
                out string documentReason));
            Assert.Equal("stale_document", documentReason);

            SessionTargetGenerationExpectation webBeforePanelChange =
                Generation(setup.Registry, SessionId, WebTarget);
            SessionSurfaceRegistryChange panel =
                setup.Registry.ChangeActivePanel(
                    setup.Owner,
                    ExpectSession(setup.Registry, SessionId),
                    PanelA,
                    new ActivePanelRegistration
                    {
                        Name = "inventory",
                        InstanceId = PanelB,
                        TargetId = WebTarget
                    });
            Assert.True(panel.Invalidation.Has(
                SessionInvalidationFlags.ExactInstanceLeases));
            Assert.False(panel.Invalidation.Has(
                SessionInvalidationFlags.WriteLeases));
            Assert.False(
                setup.Registry.TryValidateTargetGeneration(
                    webBeforePanelChange,
                    InputMode.Cdp,
                    out _,
                    out string panelReason));
            Assert.Equal(
                "stale_panel_instance",
                panelReason);
            SessionSnapshot panelSession =
                setup.Registry.GetSnapshot().FindSession(SessionId);
            Assert.NotNull(panelSession);
            Assert.Empty(
                AgentContractValidator.Validate(
                    panelSession.ToContract()));
            Assert.Throws<InvalidOperationException>(
                () => setup.Registry.ChangeActivePanel(
                    setup.Owner,
                    ExpectSession(setup.Registry, SessionId),
                    PanelA,
                    null));
        }

        [Fact]
        public void LifecycleReplacementInvalidatesEverythingAndOldIdDisappears()
        {
            Setup setup = CreateRegisteredSetup();
            setup.Registry.RegisterSurface(
                setup.Owner,
                ExpectSession(setup.Registry, SessionId),
                LauncherSurface(setup));

            SessionSurfaceRegistryChange change =
                setup.Registry.ReplaceLifecycle(
                    setup.Owner,
                    ExpectSession(setup.Registry, SessionId),
                    Session(
                        setup,
                        sessionId: ReplacementSessionId,
                        lifecycleGeneration: 2));

            Assert.Null(
                setup.Registry.GetSnapshot().FindSession(SessionId));
            Assert.NotNull(
                setup.Registry.GetSnapshot()
                    .FindSession(ReplacementSessionId));
            Assert.Equal(
                SessionInvalidationLevel.Lifecycle,
                change.Invalidation.Level);
            Assert.True(change.Invalidation.Has(
                SessionInvalidationFlags.ObservationGrants));
            Assert.True(change.Invalidation.Has(
                SessionInvalidationFlags.WriteLeases));
            Assert.True(change.Invalidation.Has(
                SessionInvalidationFlags.QueuedActions));
            Assert.True(change.Invalidation.Has(
                SessionInvalidationFlags.RuntimeHeldInput));
            Assert.False(setup.Registry.TryResolve(
                SessionId,
                LauncherTarget,
                out _,
                out string reason));
            Assert.Equal("session_not_found", reason);
        }

        [Fact]
        public async Task ConcurrentCasMutationHasOneWinnerAndOrderedEvents()
        {
            Setup setup = CreateRegisteredSetup();
            setup.Registry.RegisterSurface(
                setup.Owner,
                ExpectSession(setup.Registry, SessionId),
                LauncherSurface(setup));
            var sequences = new ConcurrentQueue<ulong>();
            setup.Registry.Changed += (_, change) =>
                sequences.Enqueue(change.Snapshot.Sequence);
            SessionSurfaceMutationExpectation expected =
                ExpectSurface(
                    setup.Registry,
                    SessionId,
                    LauncherTarget);

            Task<string>[] mutations =
            {
                Task.Run(() => TryLayout(
                    setup,
                    expected,
                    Layout(1, 1, 810, 610))),
                Task.Run(() => TryLayout(
                    setup,
                    expected,
                    Layout(2, 2, 820, 620)))
            };
            string[] results = await Task.WhenAll(mutations);

            Assert.Single(results, result => result == "changed");
            Assert.Single(results, result => result == "stale_surface");
            Assert.Equal(
                2UL,
                Surface(
                    setup.Registry,
                    SessionId,
                    LauncherTarget).SurfaceEpoch);
            ulong[] observed = sequences.ToArray();
            Assert.True(observed.SequenceEqual(
                observed.OrderBy(value => value)));
        }

        [Fact]
        public void UnqualifiedRuntimeIsObserveOnlyUnlessVisualInputWasAuthorized()
        {
            Setup setup = CreateSetup();
            setup.Registry.RegisterSession(
                setup.Owner,
                Session(
                    setup,
                    runtimeMode: RuntimeMode.UnqualifiedDev,
                    visualInputAuthorized: false));
            InvalidOperationException denied =
                Assert.Throws<InvalidOperationException>(
                    () => setup.Registry.RegisterSurface(
                        setup.Owner,
                        ExpectSession(setup.Registry, SessionId),
                        LauncherSurface(setup)));
            Assert.Equal("unqualified_input_denied", denied.Message);

            Setup visual = CreateSetup();
            visual.Registry.RegisterSession(
                visual.Owner,
                Session(
                    visual,
                    runtimeMode: RuntimeMode.UnqualifiedDev,
                    visualInputAuthorized: true));
            visual.Registry.RegisterSurface(
                visual.Owner,
                ExpectSession(visual.Registry, SessionId),
                LauncherSurface(visual));
            Assert.Throws<InvalidOperationException>(
                () => visual.Registry.RegisterSurface(
                    visual.Owner,
                    ExpectSession(visual.Registry, SessionId),
                    WebSurface(
                        visual,
                        inputModes: new[]
                        {
                            InputMode.DomainTransaction
                        })));
        }

        private static string TryLayout(
            Setup setup,
            SessionSurfaceMutationExpectation expectation,
            SessionSurfaceLayoutUpdate update)
        {
            try
            {
                setup.Registry.UpdateSurfaceLayout(
                    setup.Owner,
                    expectation,
                    update);
                return "changed";
            }
            catch (InvalidOperationException exception)
            {
                return exception.Message;
            }
        }

        private static Setup CreateRegisteredSetup()
        {
            Setup setup = CreateSetup();
            setup.Registry.RegisterSession(
                setup.Owner,
                Session(setup));
            return setup;
        }

        private static Setup CreateSetup()
        {
            var launcher = new SessionProcessIdentity(
                101,
                Utc(1),
                Absolute("Launcher.Core.exe"));
            var flash = new SessionProcessIdentity(
                202,
                Utc(2),
                Absolute("Flash.exe"));
            var owner = new SessionRegistryHostOwner(launcher);
            var validator =
                new RecordingSessionSurfaceHostValidator();
            return new Setup(
                launcher,
                flash,
                owner,
                validator,
                new SessionSurfaceRegistry(owner, validator));
        }

        private static SessionHostRegistration Session(
            Setup setup,
            string attemptId = null,
            ulong? attemptGeneration = null,
            SessionProcessIdentity flash = null,
            string sessionId = SessionId,
            ulong lifecycleGeneration = 1,
            RuntimeMode runtimeMode = RuntimeMode.FormalRuntime,
            bool visualInputAuthorized = false)
        {
            bool unqualified = runtimeMode == RuntimeMode.UnqualifiedDev;
            return new SessionHostRegistration
            {
                SessionId = sessionId,
                LifecycleGeneration = lifecycleGeneration,
                SessionMode = SessionMode.DeveloperInteractive,
                Slot = "developer_slot",
                SaveRevision = 1,
                AttemptId = attemptId,
                AttemptGeneration = attemptGeneration,
                LauncherProcess = setup.Launcher,
                FlashProcess = flash,
                CoreSha256 = new string('C', 64),
                RuntimeQualification =
                    new RuntimeQualificationRegistration
                    {
                        RuntimeMode = runtimeMode,
                        BuildIdentity = unqualified
                            ? null
                            : new string('A', 64),
                        PayloadClosure = unqualified
                            ? null
                            : new string('B', 64),
                        ActualProcessPath = setup.Launcher.ExecutablePath,
                        UnqualifiedReason = unqualified
                            ? "local spike"
                            : null,
                        UnqualifiedDevVisualInputAuthorized =
                            visualInputAuthorized
                    },
                Capabilities = unqualified
                    ? new[] { AgentCapabilitiesV1.GetWindow }
                    : new[]
                    {
                        AgentCapabilitiesV1.GetWindow,
                        AgentCapabilitiesV1.Click
                    }
            };
        }

        private static SessionSurfaceHostRegistration LauncherSurface(
            Setup setup)
        {
            return SurfaceRegistration(
                setup.Launcher,
                LauncherTarget,
                SurfaceKind.Launcher,
                SessionSurfaceOwnerRelation.LauncherTopLevel,
                1001,
                inputModes: new[] { InputMode.SendInputGuarded });
        }

        private static SessionSurfaceHostRegistration FlashSurface(
            Setup setup)
        {
            return SurfaceRegistration(
                setup.Flash,
                FlashTarget,
                SurfaceKind.Flash,
                SessionSurfaceOwnerRelation.FlashTopLevel,
                2001,
                inputModes: new[] { InputMode.SendInputGuarded });
        }

        private static SessionSurfaceHostRegistration WebSurface(
            Setup setup,
            IReadOnlyCollection<InputMode> inputModes = null)
        {
            return SurfaceRegistration(
                setup.Launcher,
                WebTarget,
                SurfaceKind.WebOverlay,
                SessionSurfaceOwnerRelation.RuntimeOverlay,
                1002,
                observationModes: new[]
                {
                    ObservationMode.WindowGraphicsCapture,
                    ObservationMode.WebSemantic
                },
                inputModes: inputModes ?? new[] { InputMode.Cdp });
        }

        private static SessionSurfaceHostRegistration BusinessModal(
            Setup setup)
        {
            SessionSurfaceHostRegistration value = SurfaceRegistration(
                setup.Launcher,
                BusinessTarget,
                SurfaceKind.BusinessModal,
                SessionSurfaceOwnerRelation.LauncherOwned,
                1003,
                inputModes: new[] { InputMode.SendInputGuarded });
            return CopyWithOwner(
                value,
                LauncherTarget,
                1001);
        }

        private static SessionSurfaceHostRegistration HumanOnlySurface(
            Setup setup)
        {
            return new SessionSurfaceHostRegistration
            {
                TargetId = SecurityTarget,
                Kind = SurfaceKind.BusinessModal,
                SafetyKind =
                    AgentTargetSafetyKind.HumanOnlySecuritySurface,
                OwnerRelation =
                    SessionSurfaceOwnerRelation
                        .HumanOnlySecurityReported,
                OwnerProcess = setup.Launcher,
                WindowHandle = 1004,
                BoundsPhysical = Rect(0, 0, 400, 300),
                ClientRectPhysical = Rect(0, 0, 400, 300),
                ContentRectPhysical = Rect(0, 0, 400, 300),
                Dpi = 96,
                Visible = true,
                ObservationModes = Array.Empty<ObservationMode>(),
                InputModes = Array.Empty<InputMode>()
            };
        }

        private static SessionSurfaceHostRegistration SurfaceRegistration(
            SessionProcessIdentity owner,
            string targetId,
            SurfaceKind kind,
            SessionSurfaceOwnerRelation relation,
            long handle,
            IReadOnlyCollection<ObservationMode> observationModes = null,
            IReadOnlyCollection<InputMode> inputModes = null)
        {
            return new SessionSurfaceHostRegistration
            {
                TargetId = targetId,
                Kind = kind,
                SafetyKind = AgentTargetSafetyKind.RuntimeOwned,
                OwnerRelation = relation,
                OwnerProcess = owner,
                WindowHandle = handle,
                BoundsPhysical = Rect(10, 10, 800, 600),
                ClientRectPhysical = Rect(10, 10, 800, 600),
                ContentRectPhysical = Rect(10, 10, 800, 600),
                Dpi = 96,
                ZIndex = 1,
                Visible = true,
                ObservationModes = observationModes ?? new[]
                {
                    ObservationMode.WindowGraphicsCapture
                },
                InputModes = inputModes ?? Array.Empty<InputMode>()
            };
        }

        private static SessionSurfaceHostRegistration CopyWithOwner(
            SessionSurfaceHostRegistration value,
            string ownerTargetId,
            long ownerHandle)
        {
            return new SessionSurfaceHostRegistration
            {
                TargetId = value.TargetId,
                Kind = value.Kind,
                SafetyKind = value.SafetyKind,
                OwnerRelation = value.OwnerRelation,
                OwnerProcess = value.OwnerProcess,
                WindowHandle = value.WindowHandle,
                OwnerTargetId = ownerTargetId,
                OwnerWindowHandle = ownerHandle,
                BoundsPhysical = value.BoundsPhysical,
                ClientRectPhysical = value.ClientRectPhysical,
                ContentRectPhysical = value.ContentRectPhysical,
                Dpi = value.Dpi,
                ZIndex = value.ZIndex,
                Visible = value.Visible,
                Minimized = value.Minimized,
                ObservationModes = value.ObservationModes,
                InputModes = value.InputModes
            };
        }

        private static SessionSurfaceHostRegistration CopyWithWindowHandle(
            SessionSurfaceHostRegistration value,
            long windowHandle)
        {
            return new SessionSurfaceHostRegistration
            {
                TargetId = value.TargetId,
                Kind = value.Kind,
                SafetyKind = value.SafetyKind,
                OwnerRelation = value.OwnerRelation,
                OwnerProcess = value.OwnerProcess,
                WindowHandle = windowHandle,
                OwnerTargetId = value.OwnerTargetId,
                OwnerWindowHandle = value.OwnerWindowHandle,
                BoundsPhysical = value.BoundsPhysical,
                ClientRectPhysical = value.ClientRectPhysical,
                ContentRectPhysical = value.ContentRectPhysical,
                Dpi = value.Dpi,
                ZIndex = value.ZIndex,
                Visible = value.Visible,
                Minimized = value.Minimized,
                ObservationModes = value.ObservationModes,
                InputModes = value.InputModes
            };
        }

        private static SessionSurfaceLayoutUpdate Layout(
            int x,
            int y,
            int width,
            int height)
        {
            return new SessionSurfaceLayoutUpdate
            {
                BoundsPhysical = Rect(x, y, width, height),
                ClientRectPhysical = Rect(x, y, width, height),
                ContentRectPhysical = Rect(x, y, width, height),
                Dpi = 120,
                ZIndex = 2,
                Visible = true
            };
        }

        private static SessionMutationExpectation ExpectSession(
            SessionSurfaceRegistry registry,
            string sessionId)
        {
            SessionSnapshot current =
                registry.GetSnapshot().FindSession(sessionId);
            return new SessionMutationExpectation
            {
                SessionId = current.SessionId,
                LifecycleGeneration = current.LifecycleGeneration,
                AttemptId = current.AttemptId,
                AttemptGeneration = current.AttemptGeneration
            };
        }

        private static SessionSurfaceMutationExpectation ExpectSurface(
            SessionSurfaceRegistry registry,
            string sessionId,
            string targetId)
        {
            SessionSurfaceSnapshot surface =
                Surface(registry, sessionId, targetId);
            return new SessionSurfaceMutationExpectation
            {
                Session = ExpectSession(registry, sessionId),
                TargetId = targetId,
                SurfaceEpoch = surface.SurfaceEpoch,
                WindowHandle = surface.WindowHandle
            };
        }

        private static SessionTargetGenerationExpectation Generation(
            SessionSurfaceRegistry registry,
            string sessionId,
            string targetId)
        {
            SessionSnapshot session =
                registry.GetSnapshot().FindSession(sessionId);
            SessionSurfaceSnapshot surface =
                session.Surfaces.Single(
                    item => item.TargetId == targetId);
            return new SessionTargetGenerationExpectation
            {
                SessionId = sessionId,
                LifecycleGeneration = session.LifecycleGeneration,
                AttemptId = session.AttemptId,
                AttemptGeneration = session.AttemptGeneration,
                TargetId = targetId,
                SurfaceEpoch = surface.SurfaceEpoch,
                CoordinateSpaceVersion =
                    surface.CoordinateSpaceVersion,
                FocusEpoch = surface.FocusEpoch,
                ModalEpoch = surface.ModalEpoch,
                DocumentGeneration = surface.DocumentGeneration,
                PanelInstanceId =
                    session.PanelInstanceIdForTarget(
                        targetId)
            };
        }

        private static SessionSurfaceSnapshot Surface(
            SessionSurfaceRegistry registry,
            string sessionId,
            string targetId)
        {
            return registry.GetSnapshot()
                .FindSession(sessionId)
                .Surfaces.Single(surface =>
                    surface.TargetId == targetId);
        }

        private static SessionPhysicalRect Rect(
            int x,
            int y,
            int width,
            int height)
        {
            return new SessionPhysicalRect(x, y, width, height);
        }

        private static string Absolute(string name)
        {
            return Path.GetFullPath(
                Path.Combine(
                    Path.GetTempPath(),
                    "cf7-agent-runtime-tests",
                    name));
        }

        private static DateTimeOffset Utc(int second)
        {
            return new DateTimeOffset(
                2026,
                7,
                30,
                0,
                0,
                second,
                TimeSpan.Zero);
        }

        private static string Id(string prefix)
        {
            return prefix + new string(
                'x',
                Math.Max(0, 24 - prefix.Length));
        }

        private const string SessionId =
            "session_aaaaaaaaaaaaaaaaa";
        private const string ReplacementSessionId =
            "session_bbbbbbbbbbbbbbbbb";
        private const string AttemptA =
            "attempt_aaaaaaaaaaaaaaaaa";
        private const string AttemptB =
            "attempt_bbbbbbbbbbbbbbbbb";
        private const string LauncherTarget =
            "target_launcher_aaaaaaaaa";
        private const string FlashTarget =
            "target_flash_aaaaaaaaaaaa";
        private const string WebTarget =
            "target_web_aaaaaaaaaaaaaa";
        private const string BusinessTarget =
            "target_business_aaaaaaaaa";
        private const string SecurityTarget =
            "target_security_aaaaaaaaa";
        private const string PanelA =
            "panel_aaaaaaaaaaaaaaaaaa";
        private const string PanelB =
            "panel_bbbbbbbbbbbbbbbbbb";

        private sealed class Setup
        {
            public Setup(
                SessionProcessIdentity launcher,
                SessionProcessIdentity flash,
                SessionRegistryHostOwner owner,
                RecordingSessionSurfaceHostValidator validator,
                SessionSurfaceRegistry registry)
            {
                Launcher = launcher;
                Flash = flash;
                Owner = owner;
                Validator = validator;
                Registry = registry;
            }

            public SessionProcessIdentity Launcher { get; }
            public SessionProcessIdentity Flash { get; }
            public SessionRegistryHostOwner Owner { get; }
            public RecordingSessionSurfaceHostValidator Validator { get; }
            public SessionSurfaceRegistry Registry { get; }
        }
    }
}
