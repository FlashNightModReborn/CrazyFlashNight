using System;
using System.IO;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Observation;
using CF7Launcher.AgentRuntime.Security;
using CF7Launcher.AgentRuntime.Sessions;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.Observation
{
    public sealed class SessionSurfaceObservationAuthorityTests
    {
        private const string SessionId =
            "session_registry_AAAAAAAAAAAAAAAA";
        private const string AttemptId =
            "attempt_registry_AAAAAAAAAAAAAAAA";
        private const string FlashTarget =
            "target_registry_flash_AAAAAAAAAAA";
        private const string WebTarget =
            "target_registry_web_AAAAAAAAAAAAA";
        private const string PanelA =
            "panel_registry_AAAAAAAAAAAAAAAAAA";
        private const string PanelB =
            "panel_registry_BBBBBBBBBBBBBBBBBB";
        private const string ModalTarget =
            "target_registry_modal_AAAAAAAAAAA";
        private const string SecurityTarget =
            "target_registry_security_AAAAAAAAA";

        [Fact]
        public void PositiveRegistryProducesSeparateOwnedModalFrames()
        {
            Setup setup = CreateSetup();
            setup.Registry.RegisterSurface(
                setup.Owner,
                Expect(setup),
                FlashSurface(setup));
            setup.Registry.SetFocus(
                setup.Owner,
                Expect(setup),
                FlashTarget);
            setup.Registry.RegisterSurface(
                setup.Owner,
                Expect(setup),
                BusinessModal(setup));
            var authority = new SessionSurfaceObservationAuthority(
                setup.Registry);

            Assert.True(authority.TryCreateCapturePlan(
                SessionId,
                FlashTarget,
                out ObservationCapturePlan plan,
                out string reason), reason);
            Assert.Equal(
                BlockingModalKind.BusinessOwned,
                plan.BlockingModalKind);
            Assert.Equal(2, plan.CaptureSurfaces.Count);
            Assert.Equal(
                new[] { FlashTarget, ModalTarget },
                new[]
                {
                    plan.CaptureSurfaces[0].TargetId,
                    plan.CaptureSurfaces[1].TargetId
                });
            Assert.Equal(
                new[] { 10, 20 },
                new[]
                {
                    plan.CaptureSurfaces[0].ZIndex,
                    plan.CaptureSurfaces[1].ZIndex
                });
            Assert.True(
                authority.TryValidateCapturePlan(plan, out reason),
                reason);
        }

        [Fact]
        public void SecurityAndUnknownModalsNeverEnterCapturePlan()
        {
            Setup setup = CreateSetup();
            setup.Registry.RegisterSurface(
                setup.Owner,
                Expect(setup),
                FlashSurface(setup));
            var authority = new SessionSurfaceObservationAuthority(
                setup.Registry);
            setup.Registry.RegisterSurface(
                setup.Owner,
                Expect(setup),
                SecuritySurface(setup));

            Assert.False(authority.TryCreateCapturePlan(
                SessionId,
                FlashTarget,
                out ObservationCapturePlan securityPlan,
                out string securityReason));
            Assert.Null(securityPlan);
            Assert.Equal(
                "human_only_security_surface",
                securityReason);

            Setup unknown = CreateSetup();
            unknown.Registry.RegisterSurface(
                unknown.Owner,
                Expect(unknown),
                FlashSurface(unknown));
            unknown.Registry.SetExternalBlockingModal(
                unknown.Owner,
                Expect(unknown),
                BlockingModalKind.Unknown);
            var unknownAuthority =
                new SessionSurfaceObservationAuthority(
                    unknown.Registry);

            Assert.False(unknownAuthority.TryCreateCapturePlan(
                SessionId,
                FlashTarget,
                out ObservationCapturePlan unknownPlan,
                out string unknownReason));
            Assert.Null(unknownPlan);
            Assert.Equal("unknown_modal", unknownReason);
        }

        [Fact]
        public void LayoutChangeMakesCapturedPlanStaleCoordinateSpace()
        {
            Setup setup = CreateSetup();
            setup.Registry.RegisterSurface(
                setup.Owner,
                Expect(setup),
                FlashSurface(setup));
            var authority = new SessionSurfaceObservationAuthority(
                setup.Registry);
            Assert.True(authority.TryCreateCapturePlan(
                SessionId,
                FlashTarget,
                out ObservationCapturePlan plan,
                out _));

            SessionSurfaceSnapshot old =
                setup.Registry.GetSnapshot()
                    .FindSession(SessionId)
                    .Surfaces[0];
            setup.Registry.UpdateSurfaceLayout(
                setup.Owner,
                new SessionSurfaceMutationExpectation
                {
                    Session = Expect(setup),
                    TargetId = FlashTarget,
                    SurfaceEpoch = old.SurfaceEpoch,
                    WindowHandle = old.WindowHandle
                },
                new SessionSurfaceLayoutUpdate
                {
                    BoundsPhysical = Rect(10, 20, 801, 600),
                    ClientRectPhysical = Rect(14, 50, 793, 566),
                    ContentRectPhysical = Rect(20, 56, 781, 550),
                    Dpi = 144,
                    ZIndex = 10,
                    Visible = true,
                    Minimized = false
                });

            Assert.False(authority.TryValidateCapturePlan(
                plan,
                out string reason));
            Assert.Equal("stale_coordinate_space", reason);
        }

        [Fact]
        public void PanelChangeInvalidatesWebPlanButNotFlashPlan()
        {
            Setup setup = CreateSetup();
            setup.Registry.RegisterSurface(
                setup.Owner,
                Expect(setup),
                FlashSurface(setup));
            setup.Registry.RegisterSurface(
                setup.Owner,
                Expect(setup),
                WebSurface(setup));
            setup.Registry.ChangeActivePanel(
                setup.Owner,
                Expect(setup),
                null,
                new ActivePanelRegistration
                {
                    Name = "hairdresser",
                    InstanceId = PanelA,
                    TargetId = WebTarget
                });
            var authority = new SessionSurfaceObservationAuthority(
                setup.Registry);
            Assert.True(
                authority.TryCreateCapturePlan(
                    SessionId,
                    WebTarget,
                    out ObservationCapturePlan webPlan,
                    out string webCreateReason),
                webCreateReason);
            Assert.True(
                authority.TryCreateCapturePlan(
                    SessionId,
                    FlashTarget,
                    out ObservationCapturePlan flashPlan,
                    out string flashCreateReason),
                flashCreateReason);
            Assert.Equal(PanelA, webPlan.PanelInstanceId);
            Assert.Null(flashPlan.PanelInstanceId);

            setup.Registry.ChangeActivePanel(
                setup.Owner,
                Expect(setup),
                PanelA,
                new ActivePanelRegistration
                {
                    Name = "inventory",
                    InstanceId = PanelB,
                    TargetId = WebTarget
                });

            Assert.False(
                authority.TryValidateCapturePlan(
                    webPlan,
                    out string webReason));
            Assert.Equal(
                "stale_panel_instance",
                webReason);
            Assert.True(
                authority.TryValidateCapturePlan(
                    flashPlan,
                    out string flashReason),
                flashReason);
        }

        private static Setup CreateSetup()
        {
            var launcher = new SessionProcessIdentity(
                101,
                new DateTimeOffset(
                    2026, 7, 30, 8, 0, 0, TimeSpan.Zero),
                Absolute("launcher.exe"));
            var flash = new SessionProcessIdentity(
                102,
                new DateTimeOffset(
                    2026, 7, 30, 8, 1, 0, TimeSpan.Zero),
                Absolute("flash.exe"));
            var owner = new SessionRegistryHostOwner(launcher);
            var registry = new SessionSurfaceRegistry(
                owner,
                new AcceptingHostValidator());
            registry.RegisterSession(
                owner,
                new SessionHostRegistration
                {
                    SessionId = SessionId,
                    LifecycleGeneration = 1,
                    SessionMode =
                        SessionMode.DeveloperInteractive,
                    Slot = "developer-slot",
                    AttemptId = AttemptId,
                    AttemptGeneration = 1,
                    LauncherProcess = launcher,
                    FlashProcess = flash,
                    CoreSha256 = new string('A', 64),
                    RuntimeQualification =
                        new RuntimeQualificationRegistration
                        {
                            RuntimeMode =
                                RuntimeMode.FormalRuntime,
                            BuildIdentity =
                                new string('B', 64),
                            PayloadClosure =
                                new string('C', 64),
                            ActualProcessPath =
                                launcher.ExecutablePath
                        },
                    Capabilities = Array.Empty<string>()
                });
            return new Setup(
                owner,
                registry,
                launcher,
                flash);
        }

        private static SessionSurfaceHostRegistration FlashSurface(
            Setup setup)
        {
            return new SessionSurfaceHostRegistration
            {
                TargetId = FlashTarget,
                Kind = SurfaceKind.Flash,
                SafetyKind = AgentTargetSafetyKind.RuntimeOwned,
                OwnerRelation =
                    SessionSurfaceOwnerRelation.FlashTopLevel,
                OwnerProcess = setup.Flash,
                WindowHandle = 201,
                BoundsPhysical = Rect(10, 20, 800, 600),
                ClientRectPhysical = Rect(14, 50, 792, 566),
                ContentRectPhysical = Rect(20, 56, 780, 550),
                Dpi = 144,
                ZIndex = 10,
                Visible = true,
                ObservationModes = new[]
                {
                    ObservationMode.WindowGraphicsCapture,
                    ObservationMode.FlashSnapshotKeyframe
                },
                InputModes = Array.Empty<InputMode>()
            };
        }

        private static SessionSurfaceHostRegistration WebSurface(
            Setup setup)
        {
            return new SessionSurfaceHostRegistration
            {
                TargetId = WebTarget,
                Kind = SurfaceKind.WebOverlay,
                SafetyKind =
                    AgentTargetSafetyKind.RuntimeOwned,
                OwnerRelation =
                    SessionSurfaceOwnerRelation.RuntimeOverlay,
                OwnerProcess = setup.Launcher,
                WindowHandle = 204,
                BoundsPhysical = Rect(10, 20, 800, 600),
                ClientRectPhysical = Rect(14, 50, 792, 566),
                ContentRectPhysical = Rect(20, 56, 780, 550),
                Dpi = 144,
                ZIndex = 11,
                Visible = true,
                ObservationModes = new[]
                {
                    ObservationMode.WindowGraphicsCapture,
                    ObservationMode.WebSemantic
                },
                InputModes = Array.Empty<InputMode>()
            };
        }

        private static SessionSurfaceHostRegistration BusinessModal(
            Setup setup)
        {
            return new SessionSurfaceHostRegistration
            {
                TargetId = ModalTarget,
                Kind = SurfaceKind.BusinessModal,
                SafetyKind = AgentTargetSafetyKind.RuntimeOwned,
                OwnerRelation =
                    SessionSurfaceOwnerRelation.FlashOwned,
                OwnerProcess = setup.Flash,
                WindowHandle = 202,
                OwnerTargetId = FlashTarget,
                OwnerWindowHandle = 201,
                BoundsPhysical = Rect(100, 120, 400, 300),
                ClientRectPhysical = Rect(104, 150, 392, 266),
                ContentRectPhysical = Rect(110, 156, 380, 250),
                Dpi = 144,
                ZIndex = 20,
                Visible = true,
                ObservationModes = new[]
                {
                    ObservationMode.WindowGraphicsCapture
                },
                InputModes = Array.Empty<InputMode>()
            };
        }

        private static SessionSurfaceHostRegistration SecuritySurface(
            Setup setup)
        {
            return new SessionSurfaceHostRegistration
            {
                TargetId = SecurityTarget,
                Kind = SurfaceKind.Launcher,
                SafetyKind =
                    AgentTargetSafetyKind.HumanOnlySecuritySurface,
                OwnerRelation =
                    SessionSurfaceOwnerRelation
                        .HumanOnlySecurityReported,
                OwnerProcess = setup.Launcher,
                WindowHandle = 203,
                BoundsPhysical = Rect(200, 220, 300, 180),
                ClientRectPhysical = Rect(204, 250, 292, 146),
                ContentRectPhysical = Rect(210, 256, 280, 130),
                Dpi = 144,
                ZIndex = 30,
                Visible = true,
                ObservationModes = Array.Empty<ObservationMode>(),
                InputModes = Array.Empty<InputMode>()
            };
        }

        private static SessionMutationExpectation Expect(Setup setup)
        {
            SessionSnapshot session = setup.Registry
                .GetSnapshot()
                .FindSession(SessionId);
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
                    "cf7-observation-tests",
                    name));
        }

        private sealed class Setup
        {
            public Setup(
                SessionRegistryHostOwner owner,
                SessionSurfaceRegistry registry,
                SessionProcessIdentity launcher,
                SessionProcessIdentity flash)
            {
                Owner = owner;
                Registry = registry;
                Launcher = launcher;
                Flash = flash;
            }

            public SessionRegistryHostOwner Owner { get; }
            public SessionSurfaceRegistry Registry { get; }
            public SessionProcessIdentity Launcher { get; }
            public SessionProcessIdentity Flash { get; }
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
