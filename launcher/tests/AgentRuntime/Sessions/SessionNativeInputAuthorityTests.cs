using System;
using System.Collections.Generic;
using System.IO;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.NativeInput;
using CF7Launcher.AgentRuntime.Security;
using CF7Launcher.AgentRuntime.Sessions;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.Sessions
{
    public sealed class SessionNativeInputAuthorityTests
    {
        [Fact]
        public void ExactRegisteredFocusedTargetIsProjected()
        {
            Fixture fixture = new Fixture();
            var authority =
                new SessionNativeInputAuthority(
                    fixture.Registry,
                    new FixedTopLevelResolver(
                        new IntPtr(9001)));

            Assert.True(
                authority.TryResolve(
                    SessionId,
                    TargetId,
                    out var target,
                    out var reason),
                reason);
            Assert.Equal(new IntPtr(1001), target.TargetHwnd);
            Assert.Equal(new IntPtr(9001), target.TopLevelHwnd);
            Assert.Equal(101, target.OwnerProcessId);
            Assert.Equal(
                fixture.Registry.GetSnapshot()
                    .FindSession(SessionId)
                    .FocusEpoch,
                checked((ulong)target.Epochs.FocusEpoch));
            Assert.True(
                authority.IsRegisteredInputWindow(
                    target,
                    new IntPtr(1001)));
            Assert.False(
                authority.IsRegisteredInputWindow(
                    target,
                    new IntPtr(1002)));
        }

        [Fact]
        public void RegisteredWebSurfaceDescendantIsAcceptedButSiblingIsRejected()
        {
            Fixture fixture = new Fixture();
            var resolver = new MappingTopLevelResolver();
            resolver.Bind(new IntPtr(1001), new IntPtr(9001));
            resolver.Bind(new IntPtr(1101), new IntPtr(1001));
            resolver.Bind(new IntPtr(1201), new IntPtr(9001));
            var authority =
                new SessionNativeInputAuthority(
                    fixture.Registry,
                    resolver);

            Assert.True(
                authority.TryResolve(
                    SessionId,
                    TargetId,
                    out var target,
                    out var reason),
                reason);
            Assert.True(
                authority.IsRegisteredInputWindow(
                    target,
                    new IntPtr(1101)));
            Assert.False(
                authority.IsRegisteredInputWindow(
                    target,
                    new IntPtr(1201)));

            fixture.Registry.SetFocus(
                fixture.Owner,
                fixture.ExpectSession(),
                null);
            Assert.False(
                authority.IsRegisteredInputWindow(
                    target,
                    new IntPtr(1101)));
        }

        [Fact]
        public void StaleOrUnfocusedRegistrationFailsClosed()
        {
            Fixture fixture = new Fixture();
            var authority =
                new SessionNativeInputAuthority(
                    fixture.Registry,
                    new FixedTopLevelResolver(
                        new IntPtr(9001)));
            Assert.True(
                authority.TryResolve(
                    SessionId,
                    TargetId,
                    out var before,
                    out _));

            fixture.Registry.SetFocus(
                fixture.Owner,
                fixture.ExpectSession(),
                null);

            Assert.False(
                authority.TryResolve(
                    SessionId,
                    TargetId,
                    out _,
                    out var reason));
            Assert.Equal("foreground_mismatch", reason);
            Assert.False(
                authority.IsRegisteredInputWindow(
                    before,
                    before.TopLevelHwnd));
        }

        [Fact]
        public void HumanOnlySecurityLatchBlocksRuntimeTarget()
        {
            Fixture fixture = new Fixture();
            fixture.Registry.RegisterSurface(
                fixture.Owner,
                fixture.ExpectSession(),
                fixture.SecuritySurface());
            var authority =
                new SessionNativeInputAuthority(
                    fixture.Registry,
                    new FixedTopLevelResolver(
                        new IntPtr(9001)));

            Assert.False(
                authority.TryResolve(
                    SessionId,
                    TargetId,
                    out _,
                    out var reason));
            Assert.Equal("human_intervention_required", reason);
        }

        [Fact]
        public void UnchangedLiveIdentityRemainsDispatchAuthoritative()
        {
            Fixture fixture = new Fixture();
            SessionNativeInputAuthority authority =
                fixture.CreateLiveAuthority();

            Assert.True(
                authority.TryResolveForDispatch(
                    SessionId,
                    TargetId,
                    out NativeInputTargetSnapshot target,
                    out string reason),
                reason);
            using (target)
            {
                Assert.True(
                    authority.TryValidateDispatchIdentity(
                        target,
                        out reason),
                    reason);
            }
        }

        [Fact]
        public void SamePidWithDifferentStartIsRejectedByCallerAndPoisonsGeneration()
        {
            Fixture fixture = new Fixture();
            SessionNativeInputAuthority authority =
                fixture.CreateLiveAuthority();
            fixture.ProcessSignals.SetCurrent(
                new SessionProcessIdentity(
                    fixture.Launcher.ProcessId,
                    fixture.Launcher.StartTimeUtc
                        .AddSeconds(1),
                    fixture.Launcher.ExecutablePath));

            Assert.False(
                authority.TryResolveForDispatch(
                    SessionId,
                    TargetId,
                    out _,
                    out string reason));
            Assert.Equal(
                "surface_owner_process_stale",
                reason);
            Assert.False(
                authority.TryResolve(
                    SessionId,
                    TargetId,
                    out _,
                    out string poisonedReason));
            Assert.Equal(
                "surface_owner_process_stale",
                poisonedReason);
        }

        [Fact]
        public void SamePidWithDifferentPathPoisonsDispatchGeneration()
        {
            Fixture fixture = new Fixture();
            SessionNativeInputAuthority authority =
                fixture.CreateLiveAuthority();
            Assert.True(
                authority.TryResolveForDispatch(
                    SessionId,
                    TargetId,
                    out NativeInputTargetSnapshot captured,
                    out string reason),
                reason);

            fixture.ProcessSignals.SetCurrent(
                new SessionProcessIdentity(
                    fixture.Launcher.ProcessId,
                    fixture.Launcher.StartTimeUtc,
                    Fixture.Absolute("ReusedLauncher.exe")));

            using (captured)
            {
                Assert.False(
                    authority.TryValidateDispatchIdentity(
                        captured,
                        out reason));
            }
            Assert.Equal(
                "surface_owner_process_stale",
                reason);
            Assert.False(
                authority.TryResolveForDispatch(
                    SessionId,
                    TargetId,
                    out _,
                    out string poisonedReason));
            Assert.Equal(
                "surface_owner_process_stale",
                poisonedReason);
        }

        [Fact]
        public void ChangedOwnerRelationPoisonsOwnedDispatchGeneration()
        {
            Fixture fixture = new Fixture();
            fixture.RegisterOwnedSurface();
            SessionNativeInputAuthority authority =
                fixture.CreateLiveAuthority();
            Assert.True(
                authority.TryResolveForDispatch(
                    SessionId,
                    OwnedTargetId,
                    out NativeInputTargetSnapshot captured,
                    out string reason),
                reason);

            fixture.Windows.OwnerWindows[1002] = 9002;

            using (captured)
            {
                Assert.False(
                    authority.TryValidateDispatchIdentity(
                        captured,
                        out reason));
            }
            Assert.Equal(
                "surface_window_owner_relation_mismatch",
                reason);
            Assert.False(
                authority.TryResolve(
                    SessionId,
                    OwnedTargetId,
                    out _,
                    out string poisonedReason));
            Assert.Equal(
                "surface_window_owner_relation_mismatch",
                poisonedReason);
        }

        private sealed class Fixture
        {
            public Fixture()
            {
                Launcher = new SessionProcessIdentity(
                    101,
                    new DateTimeOffset(
                        2026,
                        7,
                        30,
                        0,
                        0,
                        1,
                        TimeSpan.Zero),
                    Absolute("Launcher.Core.exe"));
                ProcessSignals.SetCurrent(Launcher);
                Windows.OwnerProcessIds[1001] =
                    Launcher.ProcessId;
                Owner = new SessionRegistryHostOwner(Launcher);
                var validator =
                    new RecordingSessionSurfaceHostValidator();
                Registry = new SessionSurfaceRegistry(
                    Owner,
                    validator);
                Registry.RegisterSession(
                    Owner,
                    new SessionHostRegistration
                    {
                        SessionId = SessionId,
                        LifecycleGeneration = 1,
                        SessionMode =
                            SessionMode.DeveloperInteractive,
                        Slot = "developer_slot",
                        SaveRevision = 1,
                        LauncherProcess = Launcher,
                        CoreSha256 = new string('C', 64),
                        RuntimeQualification =
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
                        Capabilities = new[]
                        {
                            AgentCapabilitiesV1.Click
                        }
                    });
                Registry.RegisterSurface(
                    Owner,
                    ExpectSession(),
                    RuntimeSurface());
                Registry.SetFocus(
                    Owner,
                    ExpectSession(),
                    TargetId);
            }

            public SessionProcessIdentity Launcher { get; }
            public SessionRegistryHostOwner Owner { get; }
            public SessionSurfaceRegistry Registry { get; }
            public FakeProcessIdentitySignalFactory ProcessSignals
            {
                get;
            } = new FakeProcessIdentitySignalFactory();
            public FakeWindowProbe Windows { get; } =
                new FakeWindowProbe();

            public SessionNativeInputAuthority
                CreateLiveAuthority()
            {
                return new SessionNativeInputAuthority(
                    Registry,
                    new FixedTopLevelResolver(
                        new IntPtr(9001)),
                    ProcessSignals,
                    Windows);
            }

            public void RegisterOwnedSurface()
            {
                Windows.OwnerProcessIds[1002] =
                    Launcher.ProcessId;
                Windows.OwnerWindows[1002] = 1001;
                Registry.RegisterSurface(
                    Owner,
                    ExpectSession(),
                    new SessionSurfaceHostRegistration
                    {
                        TargetId = OwnedTargetId,
                        Kind = SurfaceKind.WebOverlay,
                        SafetyKind =
                            AgentTargetSafetyKind.RuntimeOwned,
                        OwnerRelation =
                            SessionSurfaceOwnerRelation
                                .LauncherOwned,
                        OwnerProcess = Launcher,
                        WindowHandle = 1002,
                        OwnerTargetId = TargetId,
                        OwnerWindowHandle = 1001,
                        BoundsPhysical = Rect(),
                        ClientRectPhysical = Rect(),
                        ContentRectPhysical = Rect(),
                        Dpi = 96,
                        Visible = true,
                        ObservationModes = new[]
                        {
                            ObservationMode
                                .WindowGraphicsCapture
                        },
                        InputModes = new[]
                        {
                            InputMode.SendInputGuarded
                        }
                    });
                Registry.SetFocus(
                    Owner,
                    ExpectSession(),
                    OwnedTargetId);
            }

            public SessionMutationExpectation ExpectSession()
            {
                SessionSnapshot session =
                    Registry.GetSnapshot().FindSession(SessionId);
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

            public SessionSurfaceHostRegistration SecuritySurface()
            {
                return new SessionSurfaceHostRegistration
                {
                    TargetId = SecurityTargetId,
                    Kind = SurfaceKind.BusinessModal,
                    SafetyKind =
                        AgentTargetSafetyKind
                            .HumanOnlySecuritySurface,
                    OwnerRelation =
                        SessionSurfaceOwnerRelation
                            .HumanOnlySecurityReported,
                    OwnerProcess = Launcher,
                    WindowHandle = 1002,
                    BoundsPhysical = Rect(),
                    ClientRectPhysical = Rect(),
                    ContentRectPhysical = Rect(),
                    Dpi = 96,
                    Visible = true,
                    ObservationModes =
                        Array.Empty<ObservationMode>(),
                    InputModes = Array.Empty<InputMode>()
                };
            }

            private SessionSurfaceHostRegistration RuntimeSurface()
            {
                return new SessionSurfaceHostRegistration
                {
                    TargetId = TargetId,
                    Kind = SurfaceKind.Launcher,
                    SafetyKind =
                        AgentTargetSafetyKind.RuntimeOwned,
                    OwnerRelation =
                        SessionSurfaceOwnerRelation
                            .LauncherTopLevel,
                    OwnerProcess = Launcher,
                    WindowHandle = 1001,
                    BoundsPhysical = Rect(),
                    ClientRectPhysical = Rect(),
                    ContentRectPhysical = Rect(),
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

            private static SessionPhysicalRect Rect()
            {
                return new SessionPhysicalRect(
                    0,
                    0,
                    800,
                    600);
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

        private sealed class FixedTopLevelResolver
            : ISessionTopLevelWindowResolver
        {
            private readonly IntPtr _topLevel;

            public FixedTopLevelResolver(IntPtr topLevel)
            {
                _topLevel = topLevel;
            }

            public IntPtr ResolveTopLevel(
                IntPtr registeredHwnd)
            {
                return registeredHwnd == IntPtr.Zero
                    ? IntPtr.Zero
                    : _topLevel;
            }
        }

        private sealed class MappingTopLevelResolver
            : ISessionTopLevelWindowResolver
        {
            private readonly Dictionary<IntPtr, IntPtr> _roots =
                new Dictionary<IntPtr, IntPtr>();

            internal void Bind(IntPtr hwnd, IntPtr root)
            {
                _roots[hwnd] = root;
            }

            public IntPtr ResolveTopLevel(IntPtr registeredHwnd)
            {
                return _roots.TryGetValue(
                    registeredHwnd,
                    out IntPtr root)
                    ? root
                    : IntPtr.Zero;
            }
        }

        private sealed class FakeProcessIdentitySignalFactory
            : ISessionProcessIdentitySignalFactory
        {
            private readonly Dictionary<int, Incarnation>
                _current =
                    new Dictionary<int, Incarnation>();

            internal void SetCurrent(
                SessionProcessIdentity identity)
            {
                if (_current.TryGetValue(
                        identity.ProcessId,
                        out Incarnation previous))
                {
                    previous.Alive = false;
                }
                _current[identity.ProcessId] =
                    new Incarnation(identity);
            }

            public bool TryCapture(
                SessionProcessIdentity expected,
                out INativeInputProcessIdentitySignal signal)
            {
                if (expected != null
                    && _current.TryGetValue(
                        expected.ProcessId,
                        out Incarnation current)
                    && current.Alive
                    && current.Identity.IsExact(expected))
                {
                    signal = new FakeSignal(current);
                    return true;
                }
                signal = null;
                return false;
            }

            private sealed class Incarnation
            {
                internal Incarnation(
                    SessionProcessIdentity identity)
                {
                    Identity = identity;
                }

                internal SessionProcessIdentity Identity { get; }
                internal bool Alive { get; set; } = true;
            }

            private sealed class FakeSignal
                : INativeInputProcessIdentitySignal
            {
                private readonly Incarnation _incarnation;
                private bool _disposed;

                internal FakeSignal(Incarnation incarnation)
                {
                    _incarnation = incarnation;
                }

                public bool IsAliveBounded()
                {
                    return !_disposed
                        && _incarnation.Alive;
                }

                public void Dispose()
                {
                    _disposed = true;
                }
            }
        }

        private sealed class FakeWindowProbe
            : ISessionWindowProbe
        {
            internal Dictionary<long, int> OwnerProcessIds
            {
                get;
            } = new Dictionary<long, int>();
            internal Dictionary<long, long> OwnerWindows
            {
                get;
            } = new Dictionary<long, long>();

            public bool TryGetOwnerProcessId(
                long windowHandle,
                out int processId)
            {
                return OwnerProcessIds.TryGetValue(
                    windowHandle,
                    out processId);
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

        private const string SessionId =
            "session_native_authority_a";
        private const string TargetId =
            "target_native_authority_aa";
        private const string OwnedTargetId =
            "target_native_owned_authority";
        private const string SecurityTargetId =
            "target_security_authority_a";
    }
}
