using System;
using System.IO;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Security;
using CF7Launcher.AgentRuntime.Sessions;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.Sessions
{
    public sealed class SessionSurfaceHostControllerTests
    {
        [Fact]
        public void HostSyncIsIdempotentAndLayoutUsesCas()
        {
            Fixture fixture = new Fixture();
            string targetId =
                "target_host_controller_aaaa";
            fixture.Controller.SynchronizeSurface(
                fixture.Surface(targetId, 1001, 0));
            SessionSurfaceSnapshot first =
                fixture.Controller.Snapshot.Surfaces[0];

            fixture.Controller.SynchronizeSurface(
                fixture.Surface(targetId, 1001, 0));
            SessionSurfaceSnapshot unchanged =
                fixture.Controller.Snapshot.Surfaces[0];
            Assert.Equal(
                first.SurfaceEpoch,
                unchanged.SurfaceEpoch);
            Assert.Equal(
                first.CoordinateSpaceVersion,
                unchanged.CoordinateSpaceVersion);

            fixture.Controller.SynchronizeSurface(
                fixture.Surface(targetId, 1001, 20));
            SessionSurfaceSnapshot moved =
                fixture.Controller.Snapshot.Surfaces[0];
            Assert.True(
                moved.SurfaceEpoch
                    > first.SurfaceEpoch);
            Assert.True(
                moved.CoordinateSpaceVersion
                    > first.CoordinateSpaceVersion);
        }

        [Fact]
        public void AttemptAdvanceDropsOldFlashSurfaceOnly()
        {
            Fixture fixture = new Fixture();
            string launcherTarget =
                "target_host_launcher_aaaaaa";
            string flashTarget =
                "target_host_flash_aaaaaaaa";
            fixture.Controller.SynchronizeSurface(
                fixture.Surface(
                    launcherTarget,
                    1001,
                    0));
            fixture.Controller.SetAttempt(
                "attempt_host_controller_aaa",
                fixture.Flash,
                "developer_slot",
                1);
            fixture.Controller.SynchronizeSurface(
                fixture.Surface(
                    flashTarget,
                    2001,
                    0,
                    fixture.Flash,
                    SurfaceKind.Flash,
                    SessionSurfaceOwnerRelation
                        .FlashTopLevel));

            fixture.Controller.ClearAttempt();

            Assert.Contains(
                fixture.Controller.Snapshot.Surfaces,
                surface =>
                    surface.TargetId == launcherTarget);
            Assert.DoesNotContain(
                fixture.Controller.Snapshot.Surfaces,
                surface => surface.TargetId == flashTarget);
        }

        [Fact]
        public void LifecycleReplacementUsesNewQualificationAndMode()
        {
            Fixture fixture = new Fixture();
            var replacement =
                new RuntimeQualificationRegistration
                {
                    RuntimeMode =
                        RuntimeMode.IsolatedCandidate,
                    BuildIdentity = new string('D', 64),
                    PayloadClosure = new string('E', 64),
                    ActualProcessPath =
                        fixture.Launcher.ExecutablePath
                };

            fixture.Controller.ReplaceLifecycle(
                replacement,
                "cf7_agent_slot",
                SessionMode.UnattendedTest);

            Assert.Equal(
                RuntimeMode.IsolatedCandidate,
                fixture.Controller.Snapshot.RuntimeQualification
                    .RuntimeMode);
            Assert.Equal(
                SessionMode.UnattendedTest,
                fixture.Controller.Snapshot.SessionMode);
        }

        [Fact]
        public void ClassificationChangeReregistersSurface()
        {
            Fixture fixture = new Fixture();
            string targetId =
                "target_host_classify_aaaa";
            fixture.Controller.SynchronizeSurface(
                fixture.Surface(targetId, 1001, 0));
            ulong originalEpoch = fixture.Controller.Snapshot
                .Surfaces[0]
                .SurfaceEpoch;

            SessionSurfaceHostRegistration changed =
                fixture.Surface(
                    targetId,
                    1001,
                    0,
                    kind: SurfaceKind.NativeHud);
            fixture.Controller.SynchronizeSurface(changed);

            SessionSurfaceSnapshot current =
                fixture.Controller.Snapshot.Surfaces[0];
            Assert.Equal(SurfaceKind.NativeHud, current.Kind);
            Assert.True(current.SurfaceEpoch > originalEpoch);
        }

        [Fact]
        public void WebDocumentAdvanceUsesExactRegisteredSurface()
        {
            Fixture fixture = new Fixture();
            string targetId =
                "target_host_web_document_aaa";
            fixture.Controller.SynchronizeSurface(
                fixture.Surface(
                    targetId,
                    1001,
                    0,
                    kind: SurfaceKind.WebOverlay));
            ulong before = fixture.Controller.Snapshot
                .Surfaces[0]
                .DocumentGeneration
                .Value;

            fixture.Controller.AdvanceWebDocument(targetId);

            Assert.Equal(
                before + 1,
                fixture.Controller.Snapshot
                    .Surfaces[0]
                    .DocumentGeneration);
            Assert.Throws<InvalidOperationException>(
                () => fixture.Controller
                    .AdvanceWebDocument(
                        "target_host_web_missing_aaaa"));
        }

        [Fact]
        public void WebDocumentAdvanceRejectsNonWebSurface()
        {
            Fixture fixture = new Fixture();
            string targetId =
                "target_host_non_web_aaaaaaaa";
            fixture.Controller.SynchronizeSurface(
                fixture.Surface(targetId, 1001, 0));

            InvalidOperationException error =
                Assert.Throws<InvalidOperationException>(
                    () => fixture.Controller
                        .AdvanceWebDocument(targetId));

            Assert.Equal(
                "unsupported_for_surface",
                error.Message);
        }

        [Fact]
        public void ActivePanelSetReplaceAndClearUsesHostCas()
        {
            Fixture fixture = new Fixture();
            string targetId =
                "target_host_panel_web_aaaaa";
            fixture.Controller.SynchronizeSurface(
                fixture.Surface(
                    targetId,
                    1001,
                    0,
                    kind: SurfaceKind.WebOverlay));

            fixture.Controller.SetActivePanel(
                "help",
                "panel_host_help_instance_01",
                targetId);
            Assert.Equal(
                "panel_host_help_instance_01",
                fixture.Controller.Snapshot
                    .ActivePanelInstanceId);

            fixture.Controller.SetActivePanel(
                "map",
                "panel_host_map_instance_002",
                targetId);
            Assert.Equal(
                "map",
                fixture.Controller.Snapshot
                    .ActivePanelName);
            Assert.Equal(
                "panel_host_map_instance_002",
                fixture.Controller.Snapshot
                    .ActivePanelInstanceId);

            fixture.Controller.SetActivePanel(
                null,
                null,
                null);
            Assert.Null(
                fixture.Controller.Snapshot
                    .ActivePanelName);
            Assert.Null(
                fixture.Controller.Snapshot
                    .ActivePanelInstanceId);
            Assert.Null(
                fixture.Controller.Snapshot
                    .ActivePanelTargetId);
        }

        [Fact]
        public void ActivePanelRejectsPartialOrForeignRegistration()
        {
            Fixture fixture = new Fixture();
            string targetId =
                "target_host_panel_web_bbbbb";
            fixture.Controller.SynchronizeSurface(
                fixture.Surface(
                    targetId,
                    1001,
                    0,
                    kind: SurfaceKind.WebOverlay));

            Assert.Throws<ArgumentException>(
                () => fixture.Controller.SetActivePanel(
                    "help",
                    null,
                    targetId));
            InvalidOperationException foreign =
                Assert.Throws<InvalidOperationException>(
                    () => fixture.Controller.SetActivePanel(
                        "help",
                        "panel_host_help_foreign_01",
                        "target_host_panel_foreign"));
            Assert.Equal(
                "panel_target_not_authoritative",
                foreign.Message);

            string launcherTarget =
                "target_host_panel_launcher_a";
            fixture.Controller.SynchronizeSurface(
                fixture.Surface(
                    launcherTarget,
                    1002,
                    0));
            InvalidOperationException wrongKind =
                Assert.Throws<InvalidOperationException>(
                    () => fixture.Controller.SetActivePanel(
                        "help",
                        "panel_host_help_wrong_kind",
                        launcherTarget));
            Assert.Equal(
                "unsupported_for_surface",
                wrongKind.Message);
        }

        private sealed class Fixture
        {
            public Fixture()
            {
                Launcher = new SessionProcessIdentity(
                    101,
                    Utc(1),
                    Absolute("Launcher.Core.exe"));
                Flash = new SessionProcessIdentity(
                    202,
                    Utc(2),
                    Absolute("Flash.exe"));
                Owner = new SessionRegistryHostOwner(
                    Launcher);
                var validator =
                    new RecordingSessionSurfaceHostValidator();
                Registry = new SessionSurfaceRegistry(
                    Owner,
                    validator);
                Controller =
                    new SessionSurfaceHostController(
                        Registry,
                        Owner,
                        new RuntimeQualificationRegistration
                        {
                            RuntimeMode =
                                RuntimeMode.FormalRuntime,
                            BuildIdentity =
                                new string('A', 64),
                            PayloadClosure =
                                new string('B', 64),
                            ActualProcessPath =
                                Launcher.ExecutablePath
                        },
                        new string('C', 64),
                        new[]
                        {
                            AgentCapabilitiesV1.GetWindow
                        });
            }

            public SessionProcessIdentity Launcher { get; }
            public SessionProcessIdentity Flash { get; }
            public SessionRegistryHostOwner Owner { get; }
            public SessionSurfaceRegistry Registry { get; }
            public SessionSurfaceHostController Controller
            {
                get;
            }

            public SessionSurfaceHostRegistration Surface(
                string targetId,
                long handle,
                int offset,
                SessionProcessIdentity process = null,
                SurfaceKind kind = SurfaceKind.Launcher,
                SessionSurfaceOwnerRelation relation =
                    SessionSurfaceOwnerRelation
                        .LauncherTopLevel)
            {
                return new SessionSurfaceHostRegistration
                {
                    TargetId = targetId,
                    Kind = kind,
                    SafetyKind =
                        AgentTargetSafetyKind.RuntimeOwned,
                    OwnerRelation = relation,
                    OwnerProcess = process ?? Launcher,
                    WindowHandle = handle,
                    BoundsPhysical = Rect(offset),
                    ClientRectPhysical = Rect(offset),
                    ContentRectPhysical = Rect(offset),
                    Dpi = 96,
                    Visible = true,
                    ObservationModes = new[]
                    {
                        ObservationMode.WindowGraphicsCapture
                    },
                    InputModes = new[]
                    {
                        InputMode.SendInputGuarded
                    }
                };
            }

            private static SessionPhysicalRect Rect(int offset)
            {
                return new SessionPhysicalRect(
                    offset,
                    offset,
                    800,
                    600);
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

            private static string Absolute(string name)
            {
                return Path.GetFullPath(
                    Path.Combine(
                        Path.GetTempPath(),
                        "cf7-agent-runtime-tests",
                        name));
            }
        }
    }
}
