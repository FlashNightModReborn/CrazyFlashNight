using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Gateway;
using CF7Launcher.AgentRuntime.Input;
using CF7Launcher.AgentRuntime.NativeInput;
using CF7Launcher.AgentRuntime.Security;
using CF7Launcher.AgentRuntime.Sessions;
using CF7Launcher.Tests.AgentRuntime.Security;
using CF7Launcher.Tests.AgentRuntime.Sessions;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.Gateway
{
    public sealed class NativeInputWriteLeaseLifecycleTests
    {
        [Fact]
        public void GuiLeaseRequiresExactlyOneTarget()
        {
            using var fixture = new LifecycleFixture();
            WriteLease lease = fixture.Lease(
                "lease_multi_target_a",
                1,
                new[] { LifecycleFixture.TargetId, "target_other_aaaa" });

            Assert.False(
                fixture.Lifecycle.TryActivate(
                    lease,
                    out string reason));
            Assert.Equal("target_scope_denied", reason);
            Assert.False(fixture.Guard.TryGetBoundLease(
                out _,
                out _));
        }

        [Fact]
        public void LifecycleGenerationMustMatchCurrentSession()
        {
            using var fixture = new LifecycleFixture();

            Assert.False(
                fixture.Lifecycle.TryActivate(
                    fixture.Lease(
                        "lease_stale_lifecycle_a",
                        2),
                    out string reason));
            Assert.Equal("stale_observation", reason);
            Assert.False(fixture.Guard.TryGetBoundLease(
                out _,
                out _));
        }

        [Fact]
        public void HumanOnlySecurityLatchRejectsActivation()
        {
            using var fixture = new LifecycleFixture();
            fixture.RegisterHumanOnlySurface();

            Assert.False(
                fixture.Lifecycle.TryActivate(
                    fixture.Lease(
                        "lease_security_latch_a"),
                    out string reason));
            Assert.Equal(
                "human_intervention_required",
                reason);
            Assert.False(fixture.Guard.TryGetBoundLease(
                out _,
                out _));
        }

        [Fact]
        public void MinimizedTargetRejectsActivation()
        {
            using var fixture = new LifecycleFixture(
                minimized: true,
                setFocus: false);

            Assert.False(
                fixture.Lifecycle.TryActivate(
                    fixture.Lease(
                        "lease_minimized_target_a"),
                    out string reason));
            Assert.Equal("target_minimized", reason);
            Assert.False(fixture.Guard.TryGetBoundLease(
                out _,
                out _));
        }

        [Fact]
        public void SameSessionStaleBindingIsPreciselyRevokedAndReplaced()
        {
            using var fixture = new LifecycleFixture();
            WriteLease predecessor = fixture.Lease(
                "lease_predecessor_aaaa");
            WriteLease replacement = fixture.Lease(
                "lease_replacement_aaaa");
            Assert.True(
                fixture.Lifecycle.TryActivate(
                    predecessor,
                    out string firstReason),
                firstReason);

            Assert.True(
                fixture.Lifecycle.TryActivate(
                    replacement,
                    out string replaceReason),
                replaceReason);

            Assert.True(
                fixture.Guard.IsLeaseBound(
                    LifecycleFixture.SessionId,
                    replacement.LeaseId));
            Assert.False(
                fixture.Guard.IsLeaseBound(
                    LifecycleFixture.SessionId,
                    predecessor.LeaseId));
            Assert.True(
                fixture.Sink.WaitFor(
                    predecessor.LeaseId,
                    "lease_expired"));
        }

        [Fact]
        public void DifferentSessionBindingIsNotRevokedOrReplaced()
        {
            using var fixture = new LifecycleFixture();
            fixture.Win32.MonotonicMilliseconds +=
                InputSafetyStateMachine.QuiescenceMilliseconds;
            fixture.Guard.BindLease(
                "session_foreign_binding_a",
                "lease_foreign_binding_aa");

            Assert.False(
                fixture.Lifecycle.TryActivate(
                    fixture.Lease(
                        "lease_local_candidate_a"),
                    out string reason));

            Assert.Equal(
                "write_lease_already_held",
                reason);
            Assert.True(
                fixture.Guard.IsLeaseBound(
                    "session_foreign_binding_a",
                    "lease_foreign_binding_aa"));
            Assert.Empty(fixture.Sink.Notices);
        }

        [Fact]
        public void ReleaseRevokesBindingAndCleansOnlyRuntimeOwnedControl()
        {
            using var fixture = new LifecycleFixture();
            WriteLease lease = fixture.Lease(
                "lease_release_cleanup_a");
            Assert.True(
                fixture.Lifecycle.TryActivate(
                    lease,
                    out string reason),
                reason);
            Assert.True(
                fixture.Authority.TryResolve(
                    LifecycleFixture.SessionId,
                    LifecycleFixture.TargetId,
                    out NativeInputTargetSnapshot target,
                    out string resolveReason),
                resolveReason);
            var executor = new NativeInputExecutor(
                fixture.Safety,
                fixture.Guard,
                fixture.Win32,
                fixture.Authority);
            NativeInputDispatchResult down = executor.Execute(
                new NativeInputDispatchRequest
                {
                    LeaseId = lease.LeaseId,
                    ExpectedEpochs = target.Epochs,
                    ExpectedInputEpoch =
                        fixture.Safety.InputEpoch,
                    Packets = new[]
                    {
                        NativeInputPacket.Key(
                            65,
                            0,
                            0,
                            false)
                    }
                });
            Assert.Equal(
                ActionOutcome.InputDispatched,
                down.Outcome);

            lease.State = WriteLeaseState.Released;
            lease.RevokeReason = "client_released";
            fixture.Lifecycle.Release(lease);

            Assert.False(
                fixture.Guard.IsLeaseBound(
                    LifecycleFixture.SessionId,
                    lease.LeaseId));
            Assert.True(
                fixture.Sink.WaitFor(
                    lease.LeaseId,
                    "client_released"));
            Assert.True(
                SpinWait.SpinUntil(
                    () => fixture.Win32.SentBatches
                        .Skip(1)
                        .SelectMany(batch => batch)
                        .Any(packet =>
                            packet.ControlId == "Key:65"
                            && packet.Transition
                                == NativeControlTransition.Up),
                    TimeSpan.FromSeconds(1)));
            Assert.DoesNotContain(
                fixture.Win32.SentBatches
                    .Skip(1)
                    .SelectMany(batch => batch),
                packet => packet.ControlId != "Key:65");
        }

        [Fact]
        public void DomainLeaseDoesNotEnterNativeInputContainment()
        {
            using var fixture = new LifecycleFixture();
            WriteLease lease = fixture.DomainLease();

            Assert.True(
                fixture.Lifecycle.TryActivate(
                    lease,
                    out string reason),
                reason);
            Assert.Null(reason);
            Assert.False(fixture.Guard.TryGetBoundLease(
                out _,
                out _));

            fixture.Lifecycle.Release(lease);
            Assert.Empty(fixture.Sink.Notices);
        }

        [Fact]
        public void ShutdownLeaseDoesNotRequireNativeInputModeOrGuardBinding()
        {
            using var fixture = new LifecycleFixture(
                setFocus: false,
                supportsInput: false);

            Assert.False(
                fixture.Lifecycle.TryActivate(
                    fixture.Lease(
                        "lease_gui_unsupported_a"),
                    out string guiReason));
            Assert.Equal(
                "unsupported_for_surface",
                guiReason);

            WriteLease shutdown =
                fixture.ShutdownLease();
            Assert.True(
                fixture.Lifecycle.TryActivate(
                    shutdown,
                    out string shutdownReason),
                shutdownReason);
            Assert.Null(shutdownReason);
            Assert.False(
                fixture.Guard.TryGetBoundLease(
                    out _,
                    out _));

            fixture.Lifecycle.Release(shutdown);
            Assert.Empty(fixture.Sink.Notices);
        }

        private sealed class LifecycleFixture : IDisposable
        {
            internal const string SessionId =
                "session_lifecycle_aaaa";
            internal const string TargetId =
                "target_lifecycle_aaaaa";
            private const string SecurityTargetId =
                "target_security_lifecycle";

            internal LifecycleFixture(
                bool minimized = false,
                bool setFocus = true,
                bool supportsInput = true)
            {
                Clock = new ManualAgentRuntimeClock();
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
                Owner = new SessionRegistryHostOwner(Launcher);
                Registry = new SessionSurfaceRegistry(
                    Owner,
                    new RecordingSessionSurfaceHostValidator());
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
                            AgentCapabilitiesV1.Click,
                            AgentCapabilitiesV1.PressKey
                        }
                    });
                Registry.RegisterSurface(
                    Owner,
                    ExpectSession(),
                    RuntimeSurface(
                        minimized,
                        supportsInput));
                if (setFocus)
                {
                    Registry.SetFocus(
                        Owner,
                        ExpectSession(),
                        TargetId);
                }

                Authority = new SessionNativeInputAuthority(
                    Registry,
                    new FixedTopLevelResolver(
                        new IntPtr(9001)),
                    new FixedProcessIdentitySignalFactory(
                        Launcher),
                    new FixedWindowProbe(
                        1001,
                        Launcher.ProcessId));
                Safety = new InputSafetyStateMachine(Clock);
                Win32 = new LifecycleWin32Facade
                {
                    ForegroundHwnd = new IntPtr(9001),
                    InteractiveDesktop = true
                };
                Win32.IntegrityByPid[Win32.CurrentProcessId] =
                    0x2000;
                Win32.IntegrityByPid[Launcher.ProcessId] =
                    0x2000;
                Sink = new LifecyclePreemptionSink();
                Guard = new NativeInputGuard(
                    Safety,
                    Win32,
                    Sink,
                    false);
                Win32.MonotonicMilliseconds =
                    InputSafetyStateMachine
                        .QuiescenceMilliseconds;
                Lifecycle =
                    new NativeInputWriteLeaseLifecycle(
                        Authority,
                        Safety,
                        Guard);
                Principal = new PrincipalCredential(
                    "credential_lifecycle_a",
                    "principal_lifecycle_aa",
                    "client_lifecycle_aaaa",
                    AgentPrincipalKind.DeveloperAgent,
                    AgentSessionMode.DeveloperInteractive,
                    1,
                    0,
                    60_000,
                    DateTimeOffset.UtcNow,
                    new[]
                    {
                        AgentCapabilitiesV1.Click,
                        AgentCapabilitiesV1.PressKey,
                        AgentCapabilitiesV1
                            .SessionShutdown,
                        AgentMethodsV1.HairCommit
                    },
                    new[] { TargetId, "target_other_aaaa" },
                    "test-enrollment",
                    null,
                    null,
                    null,
                    null);
            }

            internal ManualAgentRuntimeClock Clock { get; }
            internal SessionProcessIdentity Launcher { get; }
            internal SessionRegistryHostOwner Owner { get; }
            internal SessionSurfaceRegistry Registry { get; }
            internal SessionNativeInputAuthority Authority { get; }
            internal InputSafetyStateMachine Safety { get; }
            internal LifecycleWin32Facade Win32 { get; }
            internal LifecyclePreemptionSink Sink { get; }
            internal NativeInputGuard Guard { get; }
            internal NativeInputWriteLeaseLifecycle Lifecycle
            {
                get;
            }
            internal PrincipalCredential Principal { get; }

            internal WriteLease Lease(
                string leaseId,
                ulong lifecycleGeneration = 1,
                IReadOnlyCollection<string> targets = null)
            {
                return new WriteLease(
                    leaseId,
                    Principal,
                    new WriteLeaseRequest
                    {
                        SessionId = SessionId,
                        LifecycleGeneration =
                            lifecycleGeneration,
                        Kind = WriteLeaseKind.GuiInput,
                        Capabilities = new[]
                        {
                            AgentCapabilitiesV1.PressKey
                        },
                        TargetScope =
                            targets ?? new[] { TargetId }
                    },
                    0,
                    60_000,
                    10);
            }

            internal WriteLease DomainLease()
            {
                return new WriteLease(
                    "lease_domain_lifecycle_a",
                    Principal,
                    new WriteLeaseRequest
                    {
                        SessionId = SessionId,
                        LifecycleGeneration = 1,
                        Kind =
                            WriteLeaseKind.DomainTransaction,
                        Capabilities = new[]
                        {
                            AgentMethodsV1.HairCommit
                        },
                        TargetScope = new[] { TargetId },
                        PreviewHash = new string('a', 64),
                        ExpectedRevision = "7",
                        Operation = AgentMethodsV1.HairCommit
                    },
                    0,
                    60_000,
                    1);
            }

            internal WriteLease ShutdownLease()
            {
                return new WriteLease(
                    "lease_shutdown_lifecycle",
                    Principal,
                    new WriteLeaseRequest
                    {
                        SessionId = SessionId,
                        LifecycleGeneration = 1,
                        Kind =
                            WriteLeaseKind.Shutdown,
                        Capabilities = new[]
                        {
                            AgentCapabilitiesV1
                                .SessionShutdown
                        },
                        TargetScope =
                            new[] { TargetId },
                        Operation =
                            AgentCapabilitiesV1
                                .SessionShutdown
                    },
                    0,
                    30_000,
                    1);
            }

            internal void RegisterHumanOnlySurface()
            {
                Registry.RegisterSurface(
                    Owner,
                    ExpectSession(),
                    new SessionSurfaceHostRegistration
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
                        InputModes =
                            Array.Empty<InputMode>()
                    });
            }

            private SessionMutationExpectation ExpectSession()
            {
                SessionSnapshot session =
                    Registry.GetSnapshot()
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

            private SessionSurfaceHostRegistration
                RuntimeSurface(
                    bool minimized,
                    bool supportsInput)
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
                    Visible = !minimized,
                    Minimized = minimized,
                    ObservationModes = new[]
                    {
                        ObservationMode
                            .WindowGraphicsCapture
                    },
                    InputModes = supportsInput
                        ? new[]
                        {
                            InputMode
                                .SendInputGuarded
                        }
                        : Array.Empty<InputMode>()
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

            private static string Absolute(string name)
            {
                return Path.GetFullPath(
                    Path.Combine(
                        Path.GetTempPath(),
                        "cf7-agent-lifecycle-tests",
                        name));
            }

            public void Dispose()
            {
                Guard.Dispose();
                Sink.Dispose();
            }
        }

        private sealed class FixedTopLevelResolver
            : ISessionTopLevelWindowResolver
        {
            private readonly IntPtr _topLevel;

            internal FixedTopLevelResolver(IntPtr topLevel)
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

        private sealed class FixedProcessIdentitySignalFactory
            : ISessionProcessIdentitySignalFactory
        {
            private readonly SessionProcessIdentity _identity;

            internal FixedProcessIdentitySignalFactory(
                SessionProcessIdentity identity)
            {
                _identity = identity;
            }

            public bool TryCapture(
                SessionProcessIdentity expected,
                out INativeInputProcessIdentitySignal signal)
            {
                if (_identity.IsExact(expected))
                {
                    signal = new AlwaysLiveSignal();
                    return true;
                }
                signal = null;
                return false;
            }

            private sealed class AlwaysLiveSignal
                : INativeInputProcessIdentitySignal
            {
                private bool _disposed;

                public bool IsAliveBounded()
                {
                    return !_disposed;
                }

                public void Dispose()
                {
                    _disposed = true;
                }
            }
        }

        private sealed class FixedWindowProbe
            : ISessionWindowProbe
        {
            private readonly long _windowHandle;
            private readonly int _processId;

            internal FixedWindowProbe(
                long windowHandle,
                int processId)
            {
                _windowHandle = windowHandle;
                _processId = processId;
            }

            public bool TryGetOwnerProcessId(
                long windowHandle,
                out int processId)
            {
                processId = _processId;
                return windowHandle == _windowHandle;
            }

            public long GetOwnerWindow(long windowHandle)
            {
                return 0;
            }
        }

        private sealed class LifecyclePreemptionSink
            : INativeInputPreemptionSink,
            IDisposable
        {
            private readonly AutoResetEvent _signal =
                new AutoResetEvent(false);

            internal ConcurrentQueue<Notice> Notices { get; } =
                new ConcurrentQueue<Notice>();

            public void RevokeLeaseAndCancelQueuedActions(
                string sessionId,
                string leaseId,
                string reasonCode)
            {
                Notices.Enqueue(
                    new Notice(
                        sessionId,
                        leaseId,
                        reasonCode));
                _signal.Set();
            }

            internal bool WaitFor(
                string leaseId,
                string reasonCode)
            {
                bool Match()
                {
                    return Notices.Any(
                        notice =>
                            notice.LeaseId == leaseId
                            && notice.ReasonCode
                                == reasonCode);
                }
                if (Match())
                    return true;
                _signal.WaitOne(TimeSpan.FromSeconds(1));
                return Match();
            }

            public void Dispose()
            {
                _signal.Dispose();
            }

            internal sealed record Notice(
                string SessionId,
                string LeaseId,
                string ReasonCode);
        }

        private sealed class LifecycleWin32Facade
            : INativeInputWin32Facade
        {
            private Func<NativeLowLevelHookEvent, bool> _callback;

            internal LifecycleHookSession HookSession { get; } =
                new LifecycleHookSession();
            internal bool InteractiveDesktop { get; set; }
            internal IntPtr ForegroundHwnd { get; set; }
            internal Dictionary<int, int> IntegrityByPid { get; } =
                new Dictionary<int, int>();
            internal List<NativeInputPacket[]> SentBatches { get; } =
                new List<NativeInputPacket[]>();

            public int CurrentProcessId => 111;
            public long MonotonicMilliseconds { get; set; }

            public INativeLowLevelHookSession
                InstallLowLevelHooks(
                    ulong runtimeInjectionTag,
                    Func<NativeLowLevelHookEvent, bool> callback)
            {
                _callback = callback;
                return HookSession;
            }

            public bool IsInteractiveDesktopAvailable()
            {
                return InteractiveDesktop;
            }

            public IntPtr GetForegroundWindow()
            {
                return ForegroundHwnd;
            }

            public bool TryGetFocusedWindow(
                IntPtr foregroundTopLevelHwnd,
                out IntPtr focusedHwnd)
            {
                focusedHwnd = ForegroundHwnd;
                return focusedHwnd != IntPtr.Zero;
            }

            public IntPtr WindowFromPoint(
                NativeScreenPoint point)
            {
                return new IntPtr(1001);
            }

            public bool IsSameChildOrOwnedWindow(
                IntPtr targetTopLevelHwnd,
                IntPtr candidateHwnd)
            {
                return candidateHwnd == new IntPtr(1001);
            }

            public IReadOnlyCollection<string>
                GetAsyncHeldModifiersAndButtons()
            {
                return Array.Empty<string>();
            }

            public bool TryGetProcessIntegrityLevel(
                int processId,
                out int integrityRid)
            {
                return IntegrityByPid.TryGetValue(
                    processId,
                    out integrityRid);
            }

            public int SendInput(
                IReadOnlyList<NativeInputPacket> packets,
                ulong runtimeInjectionTag)
            {
                NativeInputPacket[] copy = packets.ToArray();
                SentBatches.Add(copy);
                foreach (NativeInputPacket packet in copy)
                {
                    NativeHookDevice device =
                        packet.Kind
                            == NativeInputPacketKind.Keyboard
                                ? NativeHookDevice.Keyboard
                                : NativeHookDevice.Mouse;
                    _callback(
                        new NativeLowLevelHookEvent(
                            device,
                            packet.ControlId,
                            packet.Transition,
                            true,
                            runtimeInjectionTag,
                            null,
                            packet.Transition
                                == NativeControlTransition.Up
                                ? 0x0101u
                                : 0x0100u));
                }
                return copy.Length;
            }
        }

        private sealed class LifecycleHookSession
            : INativeLowLevelHookSession
        {
            private bool _healthy = true;

            public bool IsHealthy(TimeSpan maximumHeartbeatAge)
            {
                return _healthy;
            }

            public bool TryRefresh(TimeSpan timeout)
            {
                return _healthy;
            }

            public void Dispose()
            {
                _healthy = false;
            }
        }
    }
}
