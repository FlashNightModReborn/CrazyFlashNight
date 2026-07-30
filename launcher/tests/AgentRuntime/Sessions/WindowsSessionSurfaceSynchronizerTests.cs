using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Security;
using CF7Launcher.AgentRuntime.Sessions;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.Sessions
{
    public sealed class WindowsSessionSurfaceSynchronizerTests
    {
        private const string LauncherTarget =
            "target_sync_launcher_aaaa";
        private const string FlashTarget =
            "target_sync_flash_aaaaaaaa";
        private const string SecurityTarget =
            "target_sync_security_aaaaa";

        [Fact]
        public void RefreshProbesOnlyHostSuppliedKnownHwnd()
        {
            var fixture = new Fixture();
            fixture.Specs.Add(fixture.LauncherSpec());
            fixture.Probe.Windows[1001] =
                Window(fixture.Launcher.ProcessId, 0, 96);
            fixture.Probe.Focus =
                new WindowsSessionFocusSnapshot(1001, 1001);

            WindowsSessionSurfaceRefreshResult result =
                fixture.Synchronizer.Refresh();

            Assert.Equal(new long[] { 1001 }, fixture.Probe.ProbedHandles);
            Assert.Single(fixture.Controller.Snapshot.Surfaces);
            Assert.Equal(LauncherTarget, result.ActiveTargetId);
            Assert.Equal(
                LauncherTarget,
                fixture.Controller.Snapshot.ActiveTargetId);
        }

        [Fact]
        public void RefreshCompletionSeesOnlyFinalCommittedSurfaceSet()
        {
            Fixture fixture = null;
            var observedCounts = new List<int>();
            fixture = new Fixture(
                result =>
                {
                    Assert.Same(
                        result,
                        fixture.Synchronizer.LastResult);
                    observedCounts.Add(
                        fixture.Controller.Snapshot
                            .Surfaces.Count);
                });
            fixture.Controller.SetAttempt(
                "attempt_sync_callback_aaaa",
                fixture.Flash,
                "developer_slot",
                1);
            fixture.Specs.Add(fixture.LauncherSpec());
            fixture.Specs.Add(fixture.FlashSpec());
            fixture.Probe.Windows[1001] =
                Window(fixture.Launcher.ProcessId, 0, 96);
            fixture.Probe.Windows[2001] =
                Window(fixture.Flash.ProcessId, 20, 96);

            WindowsSessionSurfaceRefreshResult result =
                fixture.Synchronizer.Refresh();

            Assert.Equal(2, result.SynchronizedSurfaceCount);
            Assert.Equal(new[] { 2 }, observedCounts);
        }

        [Fact]
        public void EveryRefreshAttemptNotifiesForFailClosedRetry()
        {
            var results =
                new List<WindowsSessionSurfaceRefreshResult>();
            var fixture = new Fixture(results.Add);
            fixture.Specs.Add(fixture.LauncherSpec());
            fixture.Probe.Windows[1001] =
                Window(fixture.Launcher.ProcessId, 0, 96);
            fixture.Probe.Focus =
                new WindowsSessionFocusSnapshot(1001, 1001);

            fixture.Probe.DesktopAvailable = false;
            fixture.Synchronizer.Refresh();
            fixture.Probe.DesktopAvailable = true;
            fixture.Synchronizer.Refresh();

            Assert.Equal(2, results.Count);
            Assert.False(results[0].DesktopAvailable);
            Assert.True(results[1].DesktopAvailable);
            Assert.Equal(
                LauncherTarget,
                results[1].ActiveTargetId);
        }

        [Fact]
        public void RefreshCompletionFailureDoesNotRollbackSurfaceState()
        {
            var fixture = new Fixture(
                _ => throw new InvalidOperationException(
                    "callback_failed"));
            fixture.Specs.Add(fixture.LauncherSpec());
            fixture.Probe.Windows[1001] =
                Window(fixture.Launcher.ProcessId, 0, 96);
            fixture.Probe.Focus =
                new WindowsSessionFocusSnapshot(1001, 1001);

            WindowsSessionSurfaceRefreshResult result =
                fixture.Synchronizer.Refresh();

            Assert.True(result.DesktopAvailable);
            Assert.Single(fixture.Controller.Snapshot.Surfaces);
            Assert.Equal(
                LauncherTarget,
                fixture.Controller.Snapshot.ActiveTargetId);
        }

        [Fact]
        public void ReusedHwndWithDifferentPidIsRemoved()
        {
            var fixture = new Fixture();
            fixture.Specs.Add(fixture.LauncherSpec());
            fixture.Probe.Windows[1001] =
                Window(fixture.Launcher.ProcessId, 0, 96);
            fixture.Synchronizer.Refresh();
            Assert.Single(fixture.Controller.Snapshot.Surfaces);

            fixture.Probe.Windows[1001] =
                Window(999, 0, 96);
            WindowsSessionSurfaceRefreshResult result =
                fixture.Synchronizer.Refresh();

            Assert.Empty(fixture.Controller.Snapshot.Surfaces);
            Assert.Contains(
                "known_hwnd_pid_mismatch",
                result.ReasonCodes);
            Assert.Equal(1, result.RemovedSurfaceCount);
        }

        [Fact]
        public void SameHwndAndPidWithDifferentStartIsRemoved()
        {
            var fixture = new Fixture();
            fixture.Specs.Add(fixture.LauncherSpec());
            fixture.Probe.Windows[1001] =
                Window(fixture.Launcher.ProcessId, 0, 96);
            fixture.Synchronizer.Refresh();
            Assert.Single(fixture.Controller.Snapshot.Surfaces);
            SessionSnapshot before =
                fixture.Controller.Snapshot;
            SessionTargetGenerationExpectation oldGeneration =
                Expectation(
                    before,
                    before.Surfaces.Single());

            fixture.ProcessProbe.SetCurrent(
                new SessionProcessIdentity(
                    fixture.Launcher.ProcessId,
                    fixture.Launcher.StartTimeUtc
                        .AddSeconds(1),
                    fixture.Launcher.ExecutablePath));
            WindowsSessionSurfaceRefreshResult result =
                fixture.Synchronizer.Refresh();

            Assert.Empty(fixture.Controller.Snapshot.Surfaces);
            Assert.Contains(
                "surface_synchronize_rejected",
                result.ReasonCodes);
            Assert.Equal(1, result.RemovedSurfaceCount);
            Assert.False(
                fixture.Registry.TryValidateTargetGenerationBounded(
                    oldGeneration,
                    InputMode.SendInputGuarded,
                    out _,
                    out string generationReason));
            Assert.Equal(
                "target_not_authoritative",
                generationReason);
        }

        [Fact]
        public void SameHwndAndPidWithDifferentPathIsRemoved()
        {
            var fixture = new Fixture();
            fixture.Specs.Add(fixture.LauncherSpec());
            fixture.Probe.Windows[1001] =
                Window(fixture.Launcher.ProcessId, 0, 96);
            fixture.Synchronizer.Refresh();

            fixture.ProcessProbe.SetCurrent(
                new SessionProcessIdentity(
                    fixture.Launcher.ProcessId,
                    fixture.Launcher.StartTimeUtc,
                    Fixture.Absolute("ReusedLauncher.exe")));
            fixture.Synchronizer.Refresh();

            Assert.Empty(fixture.Controller.Snapshot.Surfaces);
        }

        [Fact]
        public void UnchangedLiveIdentityIsRevalidatedWithoutEpochChurn()
        {
            var fixture = new Fixture();
            fixture.Specs.Add(fixture.LauncherSpec());
            fixture.Probe.Windows[1001] =
                Window(fixture.Launcher.ProcessId, 0, 96);
            fixture.Synchronizer.Refresh();
            SessionSurfaceSnapshot first =
                fixture.Controller.Snapshot.Surfaces.Single();
            int validations =
                fixture.Validator.SurfaceValidationCount;

            WindowsSessionSurfaceRefreshResult result =
                fixture.Synchronizer.Refresh();
            SessionSurfaceSnapshot second =
                fixture.Controller.Snapshot.Surfaces.Single();

            Assert.Equal(1, result.SynchronizedSurfaceCount);
            Assert.True(
                fixture.Validator.SurfaceValidationCount
                    > validations);
            Assert.Equal(
                first.SurfaceEpoch,
                second.SurfaceEpoch);
            Assert.Equal(
                first.CoordinateSpaceVersion,
                second.CoordinateSpaceVersion);
        }

        [Fact]
        public void ChangedOwnedWindowRelationRemovesOnlyAffectedTarget()
        {
            var fixture = new Fixture();
            fixture.Controller.SetAttempt(
                "attempt_sync_owner_aaaaa",
                fixture.Flash,
                "developer_slot",
                1);
            fixture.Specs.Add(fixture.LauncherSpec());
            fixture.Specs.Add(fixture.FlashSpec());
            fixture.Probe.Windows[1001] =
                Window(fixture.Launcher.ProcessId, 0, 96);
            fixture.Probe.Windows[2001] =
                Window(fixture.Flash.ProcessId, 20, 96);
            fixture.Synchronizer.Refresh();
            Assert.Equal(
                2,
                fixture.Controller.Snapshot.Surfaces.Count);

            fixture.Probe.OwnerWindows[2001] = 9001;
            fixture.Synchronizer.Refresh();

            Assert.Single(fixture.Controller.Snapshot.Surfaces);
            Assert.Equal(
                LauncherTarget,
                fixture.Controller.Snapshot.Surfaces
                    .Single().TargetId);
        }

        [Fact]
        public void PhysicalLayoutAndDpiChangesAdvanceBothEpochs()
        {
            var fixture = new Fixture();
            fixture.Specs.Add(fixture.LauncherSpec());
            fixture.Probe.Windows[1001] =
                Window(fixture.Launcher.ProcessId, 0, 96);
            fixture.Synchronizer.Refresh();
            SessionSurfaceSnapshot first =
                fixture.Controller.Snapshot.Surfaces.Single();

            fixture.Probe.Windows[1001] =
                Window(fixture.Launcher.ProcessId, 40, 144);
            fixture.Synchronizer.Refresh();
            SessionSurfaceSnapshot changed =
                fixture.Controller.Snapshot.Surfaces.Single();

            Assert.Equal(144, changed.Dpi);
            Assert.Equal(40, changed.BoundsPhysical.X);
            Assert.True(changed.SurfaceEpoch > first.SurfaceEpoch);
            Assert.True(
                changed.CoordinateSpaceVersion
                    > first.CoordinateSpaceVersion);
        }

        [Fact]
        public void DisappearedKnownHwndRemovesSurface()
        {
            var fixture = new Fixture();
            fixture.Specs.Add(fixture.LauncherSpec());
            fixture.Probe.Windows[1001] =
                Window(fixture.Launcher.ProcessId, 0, 96);
            fixture.Synchronizer.Refresh();

            fixture.Probe.Windows.Remove(1001);
            WindowsSessionSurfaceRefreshResult result =
                fixture.Synchronizer.Refresh();

            Assert.Empty(fixture.Controller.Snapshot.Surfaces);
            Assert.Equal(1, result.RemovedSurfaceCount);
            Assert.Contains(
                "known_hwnd_unavailable",
                result.ReasonCodes);
        }

        [Fact]
        public void EmbeddedFlashFocusWinsOverTopLevelForeground()
        {
            var fixture = new Fixture();
            fixture.Controller.SetAttempt(
                "attempt_sync_flash_aaaaa",
                fixture.Flash,
                "developer_slot",
                1);
            fixture.Specs.Add(fixture.LauncherSpec());
            fixture.Specs.Add(fixture.FlashSpec());
            fixture.Probe.Windows[1001] =
                Window(fixture.Launcher.ProcessId, 0, 96);
            fixture.Probe.Windows[2001] =
                Window(fixture.Flash.ProcessId, 20, 144);
            fixture.Probe.Children.Add((1001, 2001));
            fixture.Probe.Focus =
                new WindowsSessionFocusSnapshot(1001, 2001);

            WindowsSessionSurfaceRefreshResult result =
                fixture.Synchronizer.Refresh();

            Assert.Equal(FlashTarget, result.ActiveTargetId);
            Assert.Equal(
                FlashTarget,
                fixture.Controller.Snapshot.ActiveTargetId);
            Assert.Equal(
                BlockingModalKind.None,
                fixture.Controller.Snapshot.BlockingModalKind);
        }

        [Fact]
        public void ForeignForegroundClearsFocusWithoutInventingModal()
        {
            var fixture = new Fixture();
            fixture.Specs.Add(fixture.LauncherSpec());
            fixture.Probe.Windows[1001] =
                Window(fixture.Launcher.ProcessId, 0, 96);
            fixture.Probe.Focus =
                new WindowsSessionFocusSnapshot(1001, 1001);
            fixture.Synchronizer.Refresh();
            Assert.Equal(
                LauncherTarget,
                fixture.Controller.Snapshot.ActiveTargetId);

            fixture.Probe.Focus =
                new WindowsSessionFocusSnapshot(9001, 9001);
            WindowsSessionSurfaceRefreshResult result =
                fixture.Synchronizer.Refresh();

            Assert.Null(result.ActiveTargetId);
            Assert.Null(fixture.Controller.Snapshot.ActiveTargetId);
            Assert.Equal(
                BlockingModalKind.None,
                fixture.Controller.Snapshot.BlockingModalKind);
            Assert.Contains(
                "foreground_outside_known_surfaces",
                result.ReasonCodes);
        }

        [Fact]
        public void InteractiveDesktopFailureRemovesManagedSurfaces()
        {
            var fixture = new Fixture();
            fixture.Specs.Add(fixture.LauncherSpec());
            fixture.Probe.Windows[1001] =
                Window(fixture.Launcher.ProcessId, 0, 96);
            fixture.Synchronizer.Refresh();

            fixture.Probe.DesktopAvailable = false;
            WindowsSessionSurfaceRefreshResult result =
                fixture.Synchronizer.Refresh();

            Assert.False(result.DesktopAvailable);
            Assert.False(fixture.Controller.Snapshot.DesktopAvailable);
            Assert.Empty(fixture.Controller.Snapshot.Surfaces);
            Assert.Contains(
                "interactive_desktop_unavailable",
                result.ReasonCodes);
        }

        [Fact]
        public void HumanOnlySpecRequiresEmptyModesAndRegistryRevalidates()
        {
            var fixture = new Fixture();
            Assert.Throws<ArgumentException>(
                () => fixture.HumanOnlySpec(
                    new[]
                    {
                        ObservationMode.WindowGraphicsCapture
                    },
                    Array.Empty<InputMode>()));

            fixture.Specs.Add(fixture.HumanOnlySpec(
                Array.Empty<ObservationMode>(),
                Array.Empty<InputMode>()));
            fixture.Probe.Windows[3001] =
                Window(fixture.Launcher.ProcessId, 0, 96);

            WindowsSessionSurfaceRefreshResult result =
                fixture.Synchronizer.Refresh();

            Assert.Equal(1, result.SynchronizedSurfaceCount);
            Assert.True(fixture.Validator.SurfaceValidationCount > 0);
            Assert.Empty(fixture.Controller.Snapshot.Surfaces);
            Assert.Equal(
                BlockingModalKind.HumanOnlySecurity,
                fixture.Controller.Snapshot.BlockingModalKind);
            Assert.True(fixture.Registry.TryResolve(
                fixture.Controller.SessionId,
                SecurityTarget,
                out AgentTargetDescriptor descriptor,
                out string reason));
            Assert.Null(reason);
            Assert.Equal(
                AgentTargetSafetyKind.HumanOnlySecuritySurface,
                descriptor.SafetyKind);

            Assert.Equal(
                1,
                fixture.Synchronizer.Refresh()
                    .SynchronizedSurfaceCount);
            fixture.Probe.Windows.Remove(3001);
            fixture.Synchronizer.Refresh();
            Assert.False(fixture.Registry.TryResolve(
                fixture.Controller.SessionId,
                SecurityTarget,
                out _,
                out string missingReason));
            Assert.Equal(
                "target_not_authoritative",
                missingReason);
        }

        private static WindowsSessionWindowSnapshot Window(
            int processId,
            int offset,
            int dpi)
        {
            return new WindowsSessionWindowSnapshot(
                processId,
                Rect(offset, 900, 700),
                Rect(offset + 8, 860, 640),
                Rect(offset + 12, 840, 620),
                dpi,
                true,
                false);
        }

        private static SessionPhysicalRect Rect(
            int offset,
            int width,
            int height)
        {
            return new SessionPhysicalRect(
                offset,
                offset,
                width,
                height);
        }

        private static SessionTargetGenerationExpectation
            Expectation(
                SessionSnapshot session,
                SessionSurfaceSnapshot surface)
        {
            return new SessionTargetGenerationExpectation
            {
                SessionId = session.SessionId,
                LifecycleGeneration =
                    session.LifecycleGeneration,
                AttemptId = session.AttemptId,
                AttemptGeneration =
                    session.AttemptGeneration,
                TargetId = surface.TargetId,
                SurfaceEpoch = surface.SurfaceEpoch,
                CoordinateSpaceVersion =
                    surface.CoordinateSpaceVersion,
                FocusEpoch = session.FocusEpoch,
                ModalEpoch = session.ModalEpoch,
                DocumentGeneration =
                    surface.DocumentGeneration,
                PanelInstanceId =
                    session.PanelInstanceIdForTarget(
                        surface.TargetId)
            };
        }

        private sealed class Fixture
        {
            public Fixture(
                Action<WindowsSessionSurfaceRefreshResult>
                    refreshCompleted = null)
            {
                Launcher = new SessionProcessIdentity(
                    101,
                    Utc(1),
                    Absolute("Launcher.Core.exe"));
                Flash = new SessionProcessIdentity(
                    202,
                    Utc(2),
                    Absolute("Flash.exe"));
                ProcessProbe.SetCurrent(Launcher);
                ProcessProbe.SetCurrent(Flash);
                ProcessProbe.DirectChildren.Add((
                    Flash.ProcessId,
                    Launcher.ProcessId));
                Probe.OwnerWindows[2001] = 1001;
                Owner = new SessionRegistryHostOwner(Launcher);
                Validator = new LiveHostValidator(
                    new WindowsSessionSurfaceHostValidator(
                        ProcessProbe,
                        Probe));
                Registry = new SessionSurfaceRegistry(
                    Owner,
                    Validator);
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
                Synchronizer =
                    new WindowsSessionSurfaceSynchronizer(
                        Controller,
                        () => Specs,
                        Probe,
                        refreshCompleted);
            }

            public SessionProcessIdentity Launcher { get; }
            public SessionProcessIdentity Flash { get; }
            public SessionRegistryHostOwner Owner { get; }
            public LiveHostValidator Validator
            {
                get;
            }
            public FakeProcessProbe ProcessProbe { get; } =
                new FakeProcessProbe();
            public SessionSurfaceRegistry Registry { get; }
            public SessionSurfaceHostController Controller { get; }
            public List<WindowsSessionSurfaceSpec> Specs { get; } =
                new List<WindowsSessionSurfaceSpec>();
            public FakeProbe Probe { get; } = new FakeProbe();
            public WindowsSessionSurfaceSynchronizer Synchronizer
            {
                get;
            }

            public WindowsSessionSurfaceSpec LauncherSpec()
            {
                return new WindowsSessionSurfaceSpec(
                    LauncherTarget,
                    SurfaceKind.Launcher,
                    AgentTargetSafetyKind.RuntimeOwned,
                    SessionSurfaceOwnerRelation.LauncherTopLevel,
                    Launcher,
                    1001,
                    null,
                    0,
                    new[]
                    {
                        ObservationMode.WindowGraphicsCapture
                    },
                    new[]
                    {
                        InputMode.SendInputGuarded
                    },
                    0);
            }

            public WindowsSessionSurfaceSpec FlashSpec()
            {
                return new WindowsSessionSurfaceSpec(
                    FlashTarget,
                    SurfaceKind.Flash,
                    AgentTargetSafetyKind.RuntimeOwned,
                    SessionSurfaceOwnerRelation.FlashOwned,
                    Flash,
                    2001,
                    LauncherTarget,
                    1001,
                    new[]
                    {
                        ObservationMode.FlashSnapshotKeyframe
                    },
                    new[]
                    {
                        InputMode.SendInputGuarded
                    },
                    10);
            }

            public WindowsSessionSurfaceSpec HumanOnlySpec(
                IEnumerable<ObservationMode> observationModes,
                IEnumerable<InputMode> inputModes)
            {
                return new WindowsSessionSurfaceSpec(
                    SecurityTarget,
                    SurfaceKind.BusinessModal,
                    AgentTargetSafetyKind.HumanOnlySecuritySurface,
                    SessionSurfaceOwnerRelation
                        .HumanOnlySecurityReported,
                    Launcher,
                    3001,
                    null,
                    0,
                    observationModes,
                    inputModes,
                    100);
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

            internal static string Absolute(string name)
            {
                return Path.GetFullPath(
                    Path.Combine(
                        Path.GetTempPath(),
                        "cf7-agent-runtime-tests",
                        name));
            }
        }

        private sealed class FakeProbe
            : IWindowsSessionSurfaceProbe,
            ISessionWindowProbe
        {
            public bool DesktopAvailable { get; set; } = true;
            public Dictionary<long, WindowsSessionWindowSnapshot>
                Windows { get; } =
                    new Dictionary<
                        long,
                        WindowsSessionWindowSnapshot>();
            public HashSet<(long Parent, long Child)> Children
            {
                get;
            } = new HashSet<(long Parent, long Child)>();
            public List<long> ProbedHandles { get; } =
                new List<long>();
            public WindowsSessionFocusSnapshot Focus { get; set; }
            public Dictionary<long, long> OwnerWindows { get; } =
                new Dictionary<long, long>();

            public bool IsInteractiveDesktopAvailable()
            {
                return DesktopAvailable;
            }

            public bool TryProbeKnownWindow(
                long knownWindowHandle,
                out WindowsSessionWindowSnapshot snapshot)
            {
                ProbedHandles.Add(knownWindowHandle);
                return Windows.TryGetValue(
                    knownWindowHandle,
                    out snapshot);
            }

            public bool TryProbeFocus(
                out WindowsSessionFocusSnapshot snapshot)
            {
                snapshot = Focus;
                return snapshot != null;
            }

            public bool IsSameOrChildWindow(
                long knownAncestorWindowHandle,
                long candidateWindowHandle)
            {
                return knownAncestorWindowHandle
                        == candidateWindowHandle
                    || Children.Contains((
                        knownAncestorWindowHandle,
                        candidateWindowHandle));
            }

            public bool TryGetOwnerProcessId(
                long windowHandle,
                out int processId)
            {
                if (Windows.TryGetValue(
                        windowHandle,
                        out WindowsSessionWindowSnapshot snapshot))
                {
                    processId = snapshot.ProcessId;
                    return true;
                }
                processId = 0;
                return false;
            }

            public long GetOwnerWindow(long windowHandle)
            {
                return OwnerWindows.TryGetValue(
                        windowHandle,
                        out long ownerWindow)
                    ? ownerWindow
                    : 0;
            }
        }

        private sealed class FakeProcessProbe
            : ISessionProcessProbe
        {
            private readonly Dictionary<int, SessionProcessIdentity>
                _current =
                    new Dictionary<int, SessionProcessIdentity>();

            internal HashSet<(int Child, int Parent)>
                DirectChildren { get; } =
                    new HashSet<(int Child, int Parent)>();

            internal void SetCurrent(
                SessionProcessIdentity identity)
            {
                _current[identity.ProcessId] = identity;
            }

            public bool IsExactProcess(
                SessionProcessIdentity expected)
            {
                return expected != null
                    && _current.TryGetValue(
                        expected.ProcessId,
                        out SessionProcessIdentity current)
                    && current.IsExact(expected);
            }

            public bool IsDirectChildProcess(
                SessionProcessIdentity child,
                SessionProcessIdentity parent)
            {
                return IsExactProcess(child)
                    && IsExactProcess(parent)
                    && DirectChildren.Contains((
                        child.ProcessId,
                        parent.ProcessId));
            }
        }

        private sealed class LiveHostValidator
            : ISessionSurfaceHostValidator
        {
            private readonly ISessionSurfaceHostValidator _inner;

            internal LiveHostValidator(
                ISessionSurfaceHostValidator inner)
            {
                _inner = inner;
            }

            internal int SurfaceValidationCount
            {
                get;
                private set;
            }

            public bool ValidateSession(
                SessionRegistryHostOwner hostOwner,
                SessionHostRegistration registration,
                out string reasonCode)
            {
                return _inner.ValidateSession(
                    hostOwner,
                    registration,
                    out reasonCode);
            }

            public bool ValidateAttemptProcess(
                SessionRegistryHostOwner hostOwner,
                SessionProcessIdentity flashProcess,
                out string reasonCode)
            {
                return _inner.ValidateAttemptProcess(
                    hostOwner,
                    flashProcess,
                    out reasonCode);
            }

            public bool ValidateSurface(
                SessionRegistryHostOwner hostOwner,
                SessionSurfaceValidationContext context,
                SessionSurfaceHostRegistration registration,
                out string reasonCode)
            {
                SurfaceValidationCount++;
                return _inner.ValidateSurface(
                    hostOwner,
                    context,
                    registration,
                    out reasonCode);
            }
        }
    }
}
