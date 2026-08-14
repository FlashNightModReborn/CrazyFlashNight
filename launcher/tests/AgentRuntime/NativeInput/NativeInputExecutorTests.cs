using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Input;
using CF7Launcher.AgentRuntime.NativeInput;
using CF7Launcher.Tests.AgentRuntime.Security;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.NativeInput
{
    public sealed class NativeInputExecutorTests
    {
        [Fact]
        public void RuntimeInjectionTag_IsNonZeroAndRoundTripsAsDword()
        {
            using var fixture = new Fixture();

            Assert.InRange(
                fixture.Guard.RuntimeInjectionTag,
                1UL,
                uint.MaxValue);
        }

        [Fact]
        public void ExactTaggedBatch_FullHookObservation_IsDispatched()
        {
            using var fixture = new Fixture();

            NativeInputDispatchResult result =
                fixture.Executor.Execute(
                    fixture.KeyPress());

            Assert.Equal(
                ActionOutcome.InputDispatched,
                result.Outcome);
            Assert.Equal(
                EvidenceKind.BrokerDispatch,
                result.EvidenceKind);
            Assert.Equal("none", result.ReasonCode);
            Assert.Equal(2, result.InsertedInputCount);
            Assert.True(result.FocusVerified);
            Assert.Single(fixture.Win32.SentBatches);
            Assert.Empty(fixture.Sink.Notices);
        }

        [Fact]
        public void HookIdentityFailureUsesBoundedSignalAndBlocksBatch()
        {
            using var fixture = new Fixture();
            fixture.Targets.DispatchIdentityCurrent = false;

            NativeInputDispatchResult result =
                fixture.Executor.Execute(
                    fixture.KeyPress());

            Assert.Equal(ActionOutcome.Unknown, result.Outcome);
            Assert.Equal(
                "input_not_inserted",
                result.ReasonCode);
            Assert.Equal(
                2,
                fixture.Targets.DispatchResolveCount);
            Assert.Equal(0, fixture.Targets.ResolveCount);
            Assert.True(
                fixture.Targets.DispatchIdentityValidationCount
                    > 0);
            Assert.True(
                fixture.Sink.WaitFor(
                    "surface_owner_process_stale"));
        }

        [Fact]
        public void WrongForeground_IsRejectedBeforeSend()
        {
            using var fixture = new Fixture();
            fixture.Win32.ForegroundHwnd =
                new IntPtr(999);

            NativeInputDispatchResult result =
                fixture.Executor.Execute(
                    fixture.KeyPress());

            Assert.Equal(
                ActionOutcome.Rejected,
                result.Outcome);
            Assert.Equal(
                "foreground_mismatch",
                result.ReasonCode);
            Assert.Empty(fixture.Win32.SentBatches);
            Assert.True(
                fixture.Sink.WaitFor(
                    "foreground_mismatch"));
        }

        [Fact]
        public void LiteralTextRequiresExactTargetFocusBeforeSend()
        {
            using var fixture = new Fixture();
            fixture.Win32.FocusedHwnd = IntPtr.Zero;

            NativeInputDispatchResult result =
                fixture.Executor.Execute(
                    fixture.TextInput());

            Assert.Equal(ActionOutcome.Rejected, result.Outcome);
            Assert.Equal("stale_focus", result.ReasonCode);
            Assert.False(result.FocusVerified);
            Assert.Empty(fixture.Win32.SentBatches);
            Assert.True(
                fixture.Sink.WaitFor("stale_focus"));
        }

        [Fact]
        public void PointerOutsideRegisteredChildOwner_IsRejected()
        {
            using var fixture = new Fixture();
            fixture.Win32.HitHwnd = new IntPtr(808);
            fixture.Win32.RelatedHit = false;

            NativeInputDispatchResult result =
                fixture.Executor.Execute(
                    fixture.LeftClick());

            Assert.Equal(
                ActionOutcome.Rejected,
                result.Outcome);
            Assert.Equal(
                "hit_test_mismatch",
                result.ReasonCode);
            Assert.Empty(fixture.Win32.SentBatches);
        }

        [Fact]
        public void PointerInsideRegisteredTargetChild_IsDispatched()
        {
            using var fixture = new Fixture();
            fixture.Win32.HitHwnd = new IntPtr(808);
            fixture.Win32.RelatedHit = true;
            fixture.Targets.RegisteredHitHwnd =
                new IntPtr(808);

            NativeInputDispatchResult result =
                fixture.Executor.Execute(
                    fixture.LeftClick());

            Assert.Equal(
                ActionOutcome.InputDispatched,
                result.Outcome);
            Assert.Equal("none", result.ReasonCode);
            Assert.Single(fixture.Win32.SentBatches);
        }

        [Fact]
        public void RelatedButUnregisteredOwnedWindow_IsRejected()
        {
            using var fixture = new Fixture();
            fixture.Win32.HitHwnd = new IntPtr(808);
            fixture.Win32.RelatedHit = true;

            NativeInputDispatchResult result =
                fixture.Executor.Execute(
                    fixture.LeftClick());

            Assert.Equal(
                ActionOutcome.Rejected,
                result.Outcome);
            Assert.Equal(
                "hit_test_mismatch",
                result.ReasonCode);
            Assert.Empty(fixture.Win32.SentBatches);
        }

        [Fact]
        public void AuthoritativeEpochChange_IsStaleBeforeSend()
        {
            using var fixture = new Fixture();
            fixture.Targets.Snapshot =
                fixture.Targets.SnapshotWith(
                    fixture.Epochs with
                    {
                        SurfaceEpoch =
                            fixture.Epochs.SurfaceEpoch + 1
                    });

            NativeInputDispatchResult result =
                fixture.Executor.Execute(
                    fixture.KeyPress());

            Assert.Equal(
                ActionOutcome.Rejected,
                result.Outcome);
            Assert.Equal(
                "stale_observation",
                result.ReasonCode);
            Assert.Empty(fixture.Win32.SentBatches);
        }

        [Fact]
        public void HigherIntegrityTarget_IsRejectedWithoutClaimingUipiCode()
        {
            using var fixture = new Fixture();
            fixture.Win32.IntegrityByPid[
                fixture.Targets.Snapshot.OwnerProcessId] =
                0x3000;

            NativeInputDispatchResult result =
                fixture.Executor.Execute(
                    fixture.KeyPress());

            Assert.Equal(
                ActionOutcome.Rejected,
                result.Outcome);
            Assert.Equal(
                "integrity_mismatch",
                result.ReasonCode);
            Assert.Equal(0, result.InsertedInputCount);
            Assert.Empty(fixture.Win32.SentBatches);
        }

        [Fact]
        public void PartialInsertion_IsUnknownAndReleasesOnlyOwnedControl()
        {
            using var fixture = new Fixture();
            fixture.Win32.InsertedCount = 1;

            NativeInputDispatchResult result =
                fixture.Executor.Execute(
                    fixture.KeyPress());

            Assert.Equal(
                ActionOutcome.Unknown,
                result.Outcome);
            Assert.Equal(
                "input_not_inserted",
                result.ReasonCode);
            Assert.Equal(
                ReconcileKind.VisualAmbiguous,
                result.ReconcileKind);
            Assert.Equal(1, result.InsertedInputCount);
            Assert.True(
                fixture.Sink.WaitFor(
                    "input_not_inserted"));
            Assert.True(
                SpinWait.SpinUntil(
                    () => fixture.Win32.SentBatches.Count >= 2,
                    TimeSpan.FromSeconds(1)));

            NativeInputPacket cleanup =
                fixture.Win32.SentBatches[1].Single();
            Assert.Equal("Key:65", cleanup.ControlId);
            Assert.Equal(
                NativeControlTransition.Up,
                cleanup.Transition);
        }

        [Fact]
        public void PhysicalHeldSameKey_PreemptsButCleanupNeverRaisesIt()
        {
            using var fixture = new Fixture();
            NativeInputDispatchResult down =
                fixture.Executor.Execute(
                    fixture.KeyDown());
            Assert.Equal(
                ActionOutcome.InputDispatched,
                down.Outcome);

            bool swallowed = fixture.Win32.EmitExternal(
                new NativeLowLevelHookEvent(
                    NativeHookDevice.Keyboard,
                    "Key:65",
                    NativeControlTransition.Down,
                    false,
                    0,
                    null,
                    0x0100));

            Assert.False(swallowed);
            Assert.True(
                fixture.Sink.WaitFor("human_input"));
            Thread.Sleep(25);
            Assert.Single(fixture.Win32.SentBatches);
            Assert.Equal(
                "input_not_quiescent",
                fixture.Safety
                    .EvaluateQuiescence()
                    .ReasonCode);
        }

        [Fact]
        public void OtherInjectedInput_IsExternalAndReleasesRuntimeOnlyKey()
        {
            using var fixture = new Fixture();
            NativeInputDispatchResult down =
                fixture.Executor.Execute(
                    fixture.KeyDown());
            Assert.Equal(
                ActionOutcome.InputDispatched,
                down.Outcome);

            bool swallowed = fixture.Win32.EmitExternal(
                new NativeLowLevelHookEvent(
                    NativeHookDevice.Keyboard,
                    "Key:17",
                    NativeControlTransition.Down,
                    true,
                    fixture.Win32.RuntimeTag + 1,
                    null,
                    0x0100));

            Assert.False(swallowed);
            Assert.True(
                fixture.Sink.WaitFor("external_input"));
            Assert.True(
                SpinWait.SpinUntil(
                    () => fixture.Win32.SentBatches.Count >= 2,
                    TimeSpan.FromSeconds(1)));
            NativeInputPacket cleanup =
                fixture.Win32.SentBatches[1].Single();
            Assert.Equal("Key:65", cleanup.ControlId);
            Assert.Equal(
                NativeControlTransition.Up,
                cleanup.Transition);
            Assert.DoesNotContain(
                fixture.Win32.SentBatches.SelectMany(
                    batch => batch),
                packet => packet.ControlId == "Key:17"
                    && packet.Transition
                        == NativeControlTransition.Up);
        }

        [Fact]
        public void AsyncHeldModifier_BlocksAndRevokesWithoutSending()
        {
            using var fixture = new Fixture();
            fixture.Win32.AsyncHeld.Add("Key:17");

            NativeInputDispatchResult result =
                fixture.Executor.Execute(
                    fixture.KeyPress());

            Assert.Equal(
                ActionOutcome.Rejected,
                result.Outcome);
            Assert.Equal(
                "input_not_quiescent",
                result.ReasonCode);
            Assert.Empty(fixture.Win32.SentBatches);
            Assert.True(fixture.Sink.WaitFor("human_input"));
        }

        [Fact]
        public void AsyncHeldModifierAppearingAtImmediateRecheck_NeverSends()
        {
            using var fixture = new Fixture();
            fixture.Win32.AsyncHeldOnReadCall = 3;

            NativeInputDispatchResult result =
                fixture.Executor.Execute(
                    fixture.KeyPress());

            Assert.Equal(
                ActionOutcome.Rejected,
                result.Outcome);
            Assert.Equal(
                "input_not_quiescent",
                result.ReasonCode);
            Assert.Empty(fixture.Win32.SentBatches);
        }

        [Fact]
        public void HookLoss_FailsClosedAndRevokesBeforeSend()
        {
            using var fixture = new Fixture();
            fixture.Win32.HookSession.Healthy = false;

            NativeInputDispatchResult result =
                fixture.Executor.Execute(
                    fixture.KeyPress());

            Assert.Equal(
                ActionOutcome.Rejected,
                result.Outcome);
            Assert.Equal(
                "input_guard_unhealthy",
                result.ReasonCode);
            Assert.Empty(fixture.Win32.SentBatches);
            Assert.True(
                fixture.Sink.WaitFor(
                    "input_guard_unhealthy"));
        }

        [Fact]
        public void HeartbeatOlderThan500Milliseconds_FailsClosed()
        {
            using var fixture = new Fixture();
            fixture.Win32.HookSession
                .HeartbeatAgeMilliseconds = 501;

            NativeInputDispatchResult result =
                fixture.Executor.Execute(
                    fixture.KeyPress());

            Assert.Equal(
                ActionOutcome.Rejected,
                result.Outcome);
            Assert.Equal(
                "input_guard_unhealthy",
                result.ReasonCode);
            Assert.Empty(fixture.Win32.SentBatches);
        }

        [Fact]
        public void GuardMustObserve150MillisecondsBeforeLeaseBinding()
        {
            var clock = new ManualAgentRuntimeClock();
            var epochs = new InputEpochSnapshot(
                "session-a",
                1,
                "attempt-a",
                1,
                "flash-a",
                1,
                1,
                null,
                0,
                1,
                1);
            var safety = new InputSafetyStateMachine(clock);
            safety.SetInitialAuthoritativeState(
                epochs,
                "flash-a");
            var win32 = new FakeWin32Facade();
            using var sink = new RecordingSink();
            using var guard = new NativeInputGuard(
                safety,
                win32,
                sink,
                false);

            win32.MonotonicMilliseconds = 149;
            InvalidOperationException tooEarly =
                Assert.Throws<InvalidOperationException>(
                    () => guard.BindLease(
                        "session-a",
                        "lease-a"));
            Assert.Equal(
                "input_not_quiescent",
                tooEarly.Message);

            win32.MonotonicMilliseconds = 150;
            guard.BindLease("session-a", "lease-a");
            Assert.True(
                guard.IsLeaseBound(
                    "session-a",
                    "lease-a"));
        }

        [Fact]
        public void EpochChangesInsideSendWindow_IsUnknownAndHookSwallows()
        {
            using var fixture = new Fixture();
            fixture.Win32.BeforeHookEmission = () =>
            {
                fixture.Targets.Snapshot =
                    fixture.Targets.SnapshotWith(
                        fixture.Epochs with
                        {
                            FocusEpoch =
                                fixture.Epochs.FocusEpoch + 1
                        });
            };

            NativeInputDispatchResult result =
                fixture.Executor.Execute(
                    fixture.KeyPress());

            Assert.Equal(
                ActionOutcome.Unknown,
                result.Outcome);
            Assert.Equal(
                "input_not_inserted",
                result.ReasonCode);
            Assert.True(fixture.Win32.LastOwnEventSwallowed);
            Assert.True(
                fixture.Sink.WaitFor(
                    "stale_observation"));
        }

        [Fact]
        public void CleanupReleasesRuntimeControlsInReverseDownOrder()
        {
            using var fixture = new Fixture();
            var request = new NativeInputDispatchRequest
            {
                LeaseId = "lease-a",
                ExpectedEpochs = fixture.Epochs,
                ExpectedInputEpoch =
                    fixture.Safety.InputEpoch,
                Packets = new[]
                {
                    NativeInputPacket.Key(65, 0, 0, false),
                    NativeInputPacket.Key(66, 0, 0, false)
                }
            };
            Assert.Equal(
                ActionOutcome.InputDispatched,
                fixture.Executor.Execute(request).Outcome);

            fixture.Win32.EmitExternal(
                new NativeLowLevelHookEvent(
                    NativeHookDevice.Mouse,
                    null,
                    NativeControlTransition.None,
                    false,
                    0,
                    new NativeScreenPoint(1, 1),
                    0x0200));

            Assert.True(fixture.Sink.WaitFor("human_input"));
            Assert.True(
                SpinWait.SpinUntil(
                    () => fixture.Win32.SentBatches.Count >= 2,
                    TimeSpan.FromSeconds(1)));
            Assert.Equal(
                new[] { "Key:66", "Key:65" },
                fixture.Win32.SentBatches[1]
                    .Select(packet => packet.ControlId));
            Assert.All(
                fixture.Win32.SentBatches[1],
                packet => Assert.Equal(
                    NativeControlTransition.Up,
                    packet.Transition));
        }

        [Theory]
        [InlineData(false, false, "desktop_unavailable")]
        [InlineData(true, true, "human_only_security_surface")]
        public void DesktopAndSecurityModalLatch_FailClosed(
            bool interactiveDesktop,
            bool securityModal,
            string expectedReason)
        {
            using var fixture = new Fixture();
            fixture.Win32.InteractiveDesktop =
                interactiveDesktop;
            fixture.Targets.Snapshot =
                fixture.Targets.SnapshotWith(
                    fixture.Epochs,
                    securityModal);

            NativeInputDispatchResult result =
                fixture.Executor.Execute(
                    fixture.KeyPress());

            Assert.Equal(
                ActionOutcome.Rejected,
                result.Outcome);
            Assert.Equal(expectedReason, result.ReasonCode);
            Assert.Empty(fixture.Win32.SentBatches);
        }

        private sealed class Fixture : IDisposable
        {
            internal Fixture()
            {
                Clock = new ManualAgentRuntimeClock();
                Epochs = new InputEpochSnapshot(
                    "session-a",
                    1,
                    "attempt-a",
                    1,
                    "flash-a",
                    1,
                    1,
                    null,
                    0,
                    1,
                    1);
                Safety = new InputSafetyStateMachine(Clock);
                Safety.SetInitialAuthoritativeState(
                    Epochs,
                    "flash-a");
                Win32 = new FakeWin32Facade
                {
                    ForegroundHwnd = new IntPtr(100),
                    FocusedHwnd = new IntPtr(100),
                    HitHwnd = new IntPtr(100),
                    RelatedHit = true,
                    InteractiveDesktop = true
                };
                Win32.IntegrityByPid[
                    Win32.CurrentProcessId] = 0x2000;
                Win32.IntegrityByPid[222] = 0x2000;
                Targets = new MutableTargets(
                    new NativeInputTargetSnapshot(
                        "session-a",
                        "flash-a",
                        new IntPtr(100),
                        222,
                        Epochs,
                        true,
                        false,
                        false));
                Sink = new RecordingSink();
                Guard = new NativeInputGuard(
                    Safety,
                    Win32,
                    Sink,
                    false);
                Win32.MonotonicMilliseconds =
                    InputSafetyStateMachine
                        .QuiescenceMilliseconds;
                Guard.BindLease("session-a", "lease-a");
                Executor = new NativeInputExecutor(
                    Safety,
                    Guard,
                    Win32,
                    Targets);
            }

            internal ManualAgentRuntimeClock Clock { get; }
            internal InputEpochSnapshot Epochs { get; }
            internal InputSafetyStateMachine Safety { get; }
            internal FakeWin32Facade Win32 { get; }
            internal MutableTargets Targets { get; }
            internal RecordingSink Sink { get; }
            internal NativeInputGuard Guard { get; }
            internal NativeInputExecutor Executor { get; }

            internal NativeInputDispatchRequest KeyPress()
            {
                return Request(
                    NativeInputPacket.Key(65, 0, 0, false),
                    NativeInputPacket.Key(65, 0, 0, true));
            }

            internal NativeInputDispatchRequest KeyDown()
            {
                return Request(
                    NativeInputPacket.Key(65, 0, 0, false));
            }

            internal NativeInputDispatchRequest TextInput()
            {
                return new NativeInputDispatchRequest
                {
                    LeaseId = "lease-a",
                    ExpectedEpochs = Epochs,
                    ExpectedInputEpoch = Safety.InputEpoch,
                    RequireTargetFocus = true,
                    Packets = new[]
                    {
                        NativeInputPacket.Unicode('a', false),
                        NativeInputPacket.Unicode('a', true)
                    }
                };
            }

            internal NativeInputDispatchRequest LeftClick()
            {
                return new NativeInputDispatchRequest
                {
                    LeaseId = "lease-a",
                    ExpectedEpochs = Epochs,
                    ExpectedInputEpoch = Safety.InputEpoch,
                    Packets = new[]
                    {
                        NativeInputPacket.Mouse(
                            0,
                            0,
                            0,
                            0x0002,
                            "MouseLeft",
                            NativeControlTransition.Down),
                        NativeInputPacket.Mouse(
                            0,
                            0,
                            0,
                            0x0004,
                            "MouseLeft",
                            NativeControlTransition.Up)
                    },
                    PointerHitTestPoints =
                        new[] { new NativeScreenPoint(20, 20) }
                };
            }

            private NativeInputDispatchRequest Request(
                params NativeInputPacket[] packets)
            {
                return new NativeInputDispatchRequest
                {
                    LeaseId = "lease-a",
                    ExpectedEpochs = Epochs,
                    ExpectedInputEpoch = Safety.InputEpoch,
                    Packets = packets
                };
            }

            public void Dispose()
            {
                Guard.Dispose();
                Sink.Dispose();
            }
        }

        private sealed class MutableTargets :
            IAuthoritativeNativeInputTarget
        {
            internal MutableTargets(
                NativeInputTargetSnapshot snapshot)
            {
                Snapshot = snapshot;
            }

            internal NativeInputTargetSnapshot Snapshot { get; set; }
            internal IntPtr RegisteredHitHwnd { get; set; } =
                new IntPtr(100);
            internal bool DispatchIdentityCurrent { get; set; } =
                true;
            internal int ResolveCount { get; private set; }
            internal int DispatchResolveCount { get; private set; }
            internal int DispatchIdentityValidationCount
            {
                get;
                private set;
            }

            internal NativeInputTargetSnapshot SnapshotWith(
                InputEpochSnapshot epochs,
                bool securityModal = false)
            {
                return new NativeInputTargetSnapshot(
                    Snapshot.SessionId,
                    Snapshot.TargetId,
                    Snapshot.TopLevelHwnd,
                    Snapshot.OwnerProcessId,
                    epochs,
                    Snapshot.Visible,
                    Snapshot.Minimized,
                    securityModal);
            }

            public bool TryResolve(
                string sessionId,
                string targetId,
                out NativeInputTargetSnapshot target,
                out string reasonCode)
            {
                ResolveCount++;
                target = Snapshot;
                reasonCode = null;
                return true;
            }

            public bool TryResolveForDispatch(
                string sessionId,
                string targetId,
                out NativeInputTargetSnapshot target,
                out string reasonCode)
            {
                DispatchResolveCount++;
                target = Snapshot;
                reasonCode = null;
                return true;
            }

            public bool TryValidateDispatchIdentity(
                NativeInputTargetSnapshot target,
                out string reasonCode)
            {
                DispatchIdentityValidationCount++;
                if (!DispatchIdentityCurrent)
                {
                    reasonCode =
                        "surface_owner_process_stale";
                    return false;
                }
                if (Snapshot.TargetHwnd
                        != target.TargetHwnd
                    || Snapshot.TopLevelHwnd
                        != target.TopLevelHwnd
                    || Snapshot.OwnerProcessId
                        != target.OwnerProcessId
                    || !NativeInputEpochComparer.ExactEquals(
                        Snapshot.Epochs,
                        target.Epochs))
                {
                    reasonCode = "stale_observation";
                    return false;
                }
                reasonCode = null;
                return true;
            }

            public bool IsRegisteredInputWindow(
                NativeInputTargetSnapshot target,
                IntPtr candidateHwnd)
            {
                return candidateHwnd == RegisteredHitHwnd;
            }
        }

        private sealed class RecordingSink :
            INativeInputPreemptionSink,
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

            internal bool WaitFor(string reasonCode)
            {
                if (Notices.Any(
                    notice => string.Equals(
                        notice.ReasonCode,
                        reasonCode,
                        StringComparison.Ordinal)))
                {
                    return true;
                }
                _signal.WaitOne(TimeSpan.FromSeconds(1));
                return Notices.Any(
                    notice => string.Equals(
                        notice.ReasonCode,
                        reasonCode,
                        StringComparison.Ordinal));
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

        private sealed class FakeWin32Facade :
            INativeInputWin32Facade
        {
            private Func<NativeLowLevelHookEvent, bool>
                _callback;

            internal FakeHookSession HookSession { get; } =
                new FakeHookSession();
            internal ulong RuntimeTag { get; private set; }
            internal bool InteractiveDesktop { get; set; }
            internal IntPtr ForegroundHwnd { get; set; }
            internal IntPtr FocusedHwnd { get; set; }
            internal IntPtr HitHwnd { get; set; }
            internal bool RelatedHit { get; set; }
            internal HashSet<string> AsyncHeld { get; } =
                new HashSet<string>(StringComparer.Ordinal);
            internal Dictionary<int, int> IntegrityByPid { get; } =
                new Dictionary<int, int>();
            internal int? InsertedCount { get; set; }
            internal Action BeforeHookEmission { get; set; }
            internal int? AsyncHeldOnReadCall { get; set; }
            internal bool LastOwnEventSwallowed { get; private set; }
            internal List<NativeInputPacket[]> SentBatches { get; } =
                new List<NativeInputPacket[]>();

            public int CurrentProcessId => 111;
            public long MonotonicMilliseconds { get; set; }

            public INativeLowLevelHookSession
                InstallLowLevelHooks(
                    ulong runtimeInjectionTag,
                    Func<NativeLowLevelHookEvent, bool> callback)
            {
                RuntimeTag = runtimeInjectionTag;
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
                focusedHwnd = FocusedHwnd;
                return focusedHwnd != IntPtr.Zero;
            }

            public IntPtr WindowFromPoint(
                NativeScreenPoint point)
            {
                return HitHwnd;
            }

            public bool IsSameChildOrOwnedWindow(
                IntPtr targetTopLevelHwnd,
                IntPtr candidateHwnd)
            {
                return RelatedHit;
            }

            public IReadOnlyCollection<string>
                GetAsyncHeldModifiersAndButtons()
            {
                AsyncReadCalls++;
                if (AsyncHeldOnReadCall == AsyncReadCalls)
                {
                    return new[] { "Key:17" };
                }
                return AsyncHeld.ToArray();
            }

            private int AsyncReadCalls { get; set; }

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
                NativeInputPacket[] copy =
                    packets.ToArray();
                SentBatches.Add(copy);
                int inserted = Math.Clamp(
                    InsertedCount ?? copy.Length,
                    0,
                    copy.Length);
                BeforeHookEmission?.Invoke();
                BeforeHookEmission = null;
                for (int i = 0; i < inserted; i++)
                {
                    NativeInputPacket packet = copy[i];
                    LastOwnEventSwallowed = _callback(
                        ToHookEvent(
                            packet,
                            runtimeInjectionTag));
                    if (LastOwnEventSwallowed)
                    {
                        break;
                    }
                }
                return inserted;
            }

            internal bool EmitExternal(
                NativeLowLevelHookEvent hookEvent)
            {
                return _callback(hookEvent);
            }

            private static NativeLowLevelHookEvent ToHookEvent(
                NativeInputPacket packet,
                ulong tag)
            {
                NativeHookDevice device = packet.Kind
                    == NativeInputPacketKind.Keyboard
                        ? NativeHookDevice.Keyboard
                        : NativeHookDevice.Mouse;
                return new NativeLowLevelHookEvent(
                    device,
                    packet.ControlId,
                    packet.Transition,
                    true,
                    tag,
                    device == NativeHookDevice.Mouse
                        ? new NativeScreenPoint(20, 20)
                        : null,
                    NativeMessage(packet));
            }

            private static uint NativeMessage(
                NativeInputPacket packet)
            {
                if (packet.Kind
                    == NativeInputPacketKind.Keyboard)
                {
                    return packet.Transition
                        == NativeControlTransition.Up
                            ? 0x0101u
                            : 0x0100u;
                }
                uint flags = packet.MouseFlags;
                if ((flags & 0x0002) != 0) return 0x0201;
                if ((flags & 0x0004) != 0) return 0x0202;
                if ((flags & 0x0008) != 0) return 0x0204;
                if ((flags & 0x0010) != 0) return 0x0205;
                if ((flags & 0x0020) != 0) return 0x0207;
                if ((flags & 0x0040) != 0) return 0x0208;
                if ((flags & 0x0080) != 0) return 0x020B;
                if ((flags & 0x0100) != 0) return 0x020C;
                if ((flags & 0x0800) != 0) return 0x020A;
                if ((flags & 0x1000) != 0) return 0x020E;
                return 0x0200;
            }
        }

        private sealed class FakeHookSession :
            INativeLowLevelHookSession
        {
            internal bool Healthy { get; set; } = true;
            internal bool RefreshResult { get; set; } = true;
            internal long HeartbeatAgeMilliseconds { get; set; }

            public bool IsHealthy(
                TimeSpan maximumHeartbeatAge)
            {
                return Healthy
                    && HeartbeatAgeMilliseconds
                        <= maximumHeartbeatAge.TotalMilliseconds;
            }

            public bool TryRefresh(TimeSpan timeout)
            {
                return RefreshResult;
            }

            public void Dispose()
            {
                Healthy = false;
            }
        }
    }
}
