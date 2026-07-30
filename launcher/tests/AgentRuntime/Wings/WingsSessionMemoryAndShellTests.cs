using System;
using System.Linq;
using CF7Launcher.AgentRuntime.Wings;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.Wings
{
    public sealed class WingsSessionMemoryAndShellTests
    {
        [Fact]
        public void SessionMemoryIsTypedAndBounded()
        {
            LoreView view = WingsTestFixture.View();
            using var memory = new SessionOnlyWingsMemory(
                WingsTestFixture.SessionId,
                view,
                maximumEntries: 2,
                maximumCharacters: 256);
            memory.Remember(
                WingsTestFixture.SessionId,
                view,
                WingsMemoryKey.GuidanceVerbosity,
                "brief");
            memory.Remember(
                WingsTestFixture.SessionId,
                view,
                WingsMemoryKey.RouteStyle,
                "safe");
            memory.Remember(
                WingsTestFixture.SessionId,
                view,
                WingsMemoryKey.LastFrameHash,
                new string('A', 64));

            Assert.Equal(2, memory.Count);
            Assert.False(memory.TryRecall(
                WingsTestFixture.SessionId,
                view,
                WingsMemoryKey.GuidanceVerbosity,
                out _));
            Assert.Equal(
                new[]
                {
                    WingsMemoryKey.RouteStyle,
                    WingsMemoryKey.LastFrameHash
                },
                memory.Snapshot(
                    WingsTestFixture.SessionId,
                    view).Select(item => item.Key));
        }

        [Fact]
        public void MemoryRejectsRawSensitiveProfilesAndCrossSessionReads()
        {
            LoreView view = WingsTestFixture.View();
            using var memory = new SessionOnlyWingsMemory(
                WingsTestFixture.SessionId,
                view);
            Assert.Throws<ArgumentException>(
                () => memory.Remember(
                    WingsTestFixture.SessionId,
                    view,
                    WingsMemoryKey.LastActionReasonHash,
                    "玩家似乎焦虑且经济困难"));
            Assert.Throws<ArgumentOutOfRangeException>(
                () => memory.Remember(
                    WingsTestFixture.SessionId,
                    view,
                    (WingsMemoryKey)999,
                    "profile"));

            memory.Remember(
                WingsTestFixture.SessionId,
                view,
                WingsMemoryKey.GuidanceVerbosity,
                "standard");
            Assert.False(memory.TryRecall(
                WingsTestFixture.OtherSessionId,
                view,
                WingsMemoryKey.GuidanceVerbosity,
                out _));
            Assert.Throws<InvalidOperationException>(
                () => memory.Remember(
                    WingsTestFixture.OtherSessionId,
                    view,
                    WingsMemoryKey.RouteStyle,
                    "balanced"));
        }

        [Fact]
        public void LoreViewTransitionClearsSessionMemory()
        {
            LoreView view = WingsTestFixture.View();
            LoreView rebound = WingsTestFixture.ReboundView(
                view,
                "sv_6Nx2mT9qR4vK8cL1wH7dP");
            using var memory = new SessionOnlyWingsMemory(
                WingsTestFixture.SessionId,
                view);
            memory.Remember(
                WingsTestFixture.SessionId,
                view,
                WingsMemoryKey.RouteStyle,
                "fast");
            memory.TransitionLoreView(
                WingsTestFixture.SessionId,
                rebound);
            Assert.Equal(0, memory.Count);
            Assert.False(memory.TryRecall(
                WingsTestFixture.SessionId,
                rebound,
                WingsMemoryKey.RouteStyle,
                out _));
            Assert.False(memory.TryRecall(
                WingsTestFixture.SessionId,
                view,
                WingsMemoryKey.RouteStyle,
                out _));
        }

        [Fact]
        public void HidingPersonaNeverHidesNeutralIndicator()
        {
            var shell = ActiveShell();
            WingsShellSnapshot hidden = shell.HidePersona();
            Assert.Equal(
                WingsPersonaPresentation.Hidden,
                hidden.Presentation);
            Assert.True(hidden.NeutralObservationIndicatorVisible);
            Assert.True(hidden.CaptureRunning);
            Assert.True(hidden.ReadGrantActive);
        }

        [Fact]
        public void PauseStopsWorkAndDefaultsToReadSuspension()
        {
            var shell = ActiveShell();
            WingsShellTransition paused = shell.Pause();
            Assert.True(paused.Snapshot.Paused);
            Assert.False(paused.Snapshot.CaptureRunning);
            Assert.False(paused.Snapshot.InferenceRunning);
            Assert.False(paused.Snapshot.ReadGrantActive);
            Assert.False(paused.Snapshot.WriteLeaseActive);
            Assert.False(paused.Snapshot.PendingActionsExist);
            Assert.False(
                paused.Snapshot
                    .NeutralObservationIndicatorVisible);
            Assert.Equal(
                WingsShellEffect.StopCapture
                | WingsShellEffect.StopInference
                | WingsShellEffect.RevokeWriteLease
                | WingsShellEffect.CancelPendingActions
                | WingsShellEffect.SuspendReadGrant,
                paused.RequiredEffects);

            WingsShellTransition resumed = shell.ResumeShell();
            Assert.False(resumed.Snapshot.Paused);
            Assert.False(resumed.Snapshot.CaptureRunning);
            Assert.False(resumed.Snapshot.ReadGrantActive);
            Assert.Equal(
                WingsShellEffect.RequiresFreshActivation,
                resumed.RequiredEffects);
        }

        [Fact]
        public void OnlyNeutralPolicyMayRetainReadGrantDuringPause()
        {
            var shell = ActiveShell();
            var policy = new TrustedNeutralPausePolicy(
                WingsTestFixture.PauseReceiptId,
                WingsTestFixture.SessionId,
                true);
            WingsShellTransition paused = shell.Pause(
                policy.ReceiptId,
                new StubPauseAuthority(policy));
            Assert.True(paused.NeutralRetainReadPolicyApplied);
            Assert.True(paused.Snapshot.ReadGrantActive);
            Assert.False(paused.Snapshot.CaptureRunning);
            Assert.False(
                paused.Snapshot
                    .NeutralObservationIndicatorVisible);
            Assert.False(
                paused.RequiredEffects.HasFlag(
                    WingsShellEffect.SuspendReadGrant));

            var wrongSessionShell = ActiveShell();
            var wrongPolicy = new TrustedNeutralPausePolicy(
                WingsTestFixture.PauseReceiptId,
                WingsTestFixture.OtherSessionId,
                true);
            WingsShellTransition failClosed =
                wrongSessionShell.Pause(
                    wrongPolicy.ReceiptId,
                    new StubPauseAuthority(wrongPolicy));
            Assert.False(
                failClosed.NeutralRetainReadPolicyApplied);
            Assert.False(failClosed.Snapshot.ReadGrantActive);
            Assert.True(
                failClosed.RequiredEffects.HasFlag(
                    WingsShellEffect.SuspendReadGrant));

            var malformedReceiptShell = ActiveShell();
            WingsShellTransition malformed =
                malformedReceiptShell.Pause(
                    "persona-says-retain",
                    new StubPauseAuthority(policy));
            Assert.False(
                malformed.NeutralRetainReadPolicyApplied);
            Assert.False(malformed.Snapshot.ReadGrantActive);
        }

        private static WingsShellStateMachine ActiveShell()
        {
            return new WingsShellStateMachine(
                WingsTestFixture.SessionId,
                readGrantActive: true,
                writeLeaseActive: true,
                pendingActionsExist: true);
        }

        private sealed class StubPauseAuthority
            : INeutralPausePolicyAuthority
        {
            private readonly TrustedNeutralPausePolicy _policy;

            public StubPauseAuthority(
                TrustedNeutralPausePolicy policy)
            {
                _policy = policy;
            }

            public bool TryResolve(
                string receiptId,
                out TrustedNeutralPausePolicy policy,
                out string reasonCode)
            {
                policy = string.Equals(
                    receiptId,
                    _policy.ReceiptId,
                    StringComparison.Ordinal)
                        ? _policy
                        : null;
                reasonCode = policy == null ? "not_found" : null;
                return policy != null;
            }
        }
    }
}
