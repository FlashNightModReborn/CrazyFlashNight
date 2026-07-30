using System;
using CF7Launcher.AgentRuntime.Input;
using CF7Launcher.Tests.AgentRuntime.Security;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.Input
{
    public sealed class InputSafetyStateMachineTests
    {
        [Fact]
        public void ExternalHeldModifier_BlocksAndCleanupNeverReleasesHumanKey()
        {
            var clock = new ManualAgentRuntimeClock();
            var state = CreateReadyState(clock);
            state.RecordRuntimeControlDown(
                "KeyA",
                state.RuntimeInjectionTag);

            InputPreemption preemption = state.RecordExternalInput(
                "Control",
                true,
                ExternalInputKind.HumanPhysical);

            Assert.Contains("KeyA", preemption.RuntimeControlsToRelease);
            Assert.DoesNotContain(
                "Control",
                preemption.RuntimeControlsToRelease);
            Assert.Equal(
                "input_not_quiescent",
                state.EvaluateQuiescence().ReasonCode);

            state.RecordExternalInput(
                "Control",
                false,
                ExternalInputKind.HumanPhysical);
            clock.Advance(TimeSpan.FromMilliseconds(149));
            Assert.Equal(
                "input_not_quiescent",
                state.EvaluateQuiescence().ReasonCode);
            clock.Advance(TimeSpan.FromMilliseconds(1));
            Assert.True(state.EvaluateQuiescence().Allowed);
        }

        [Fact]
        public void Dispatch_RechecksEpochForegroundAndPointerHit()
        {
            var clock = new ManualAgentRuntimeClock();
            var state = CreateReadyState(clock);
            InputEpochSnapshot epochs = state.CurrentEpochs;
            long inputEpoch = state.InputEpoch;

            InputSafetyDecision allowed = state.EvaluateAtDispatch(
                new InputDispatchCheck
                {
                    ExpectedEpochs = epochs,
                    ExpectedInputEpoch = inputEpoch,
                    ForegroundTargetId = "flash-a",
                    IsPointerAction = true,
                    HitTestTargetId = "flash-a"
                });
            Assert.True(allowed.Allowed);

            InputSafetyDecision wrongHit = state.EvaluateAtDispatch(
                new InputDispatchCheck
                {
                    ExpectedEpochs = epochs,
                    ExpectedInputEpoch = inputEpoch,
                    ForegroundTargetId = "flash-a",
                    IsPointerAction = true,
                    HitTestTargetId = "consent-ui"
                });
            Assert.Equal(
                "hit_test_mismatch",
                wrongHit.ReasonCode);

            state.AdvanceAuthoritativeState(
                epochs with { FocusEpoch = epochs.FocusEpoch + 1 },
                "flash-a",
                "focus_changed");
            InputSafetyDecision stale = state.EvaluateAtDispatch(
                new InputDispatchCheck
                {
                    ExpectedEpochs = epochs,
                    ExpectedInputEpoch = inputEpoch,
                    ForegroundTargetId = "flash-a"
                });
            Assert.Equal("stale_focus", stale.ReasonCode);
        }

        [Fact]
        public void GuardHeartbeatAndSecurityModal_FailClosed()
        {
            var clock = new ManualAgentRuntimeClock();
            var state = CreateReadyState(clock);

            clock.Advance(TimeSpan.FromMilliseconds(501));
            Assert.Equal(
                "input_guard_unhealthy",
                state.EvaluateQuiescence().ReasonCode);

            state.RecordGuardHeartbeat(true);
            state.SetSecurityModal(true, "security_modal_appeared");
            Assert.Equal(
                "human_only_security_surface",
                state.EvaluateQuiescence().ReasonCode);

            state.SetSecurityModal(false, "security_modal_dismissed");
            Assert.Equal(
                "human_intervention_required",
                state.EvaluateQuiescence().ReasonCode);
            state.AcceptTrustedHumanReauthorization();
            Assert.True(state.EvaluateQuiescence().Allowed);
        }

        [Fact]
        public void RuntimeTagMustMatchExactly()
        {
            var state = CreateReadyState(
                new ManualAgentRuntimeClock());

            Assert.Throws<InvalidOperationException>(
                () => state.RecordRuntimeControlDown(
                    "MouseLeft",
                    "some-other-injected-tag"));
        }

        private static InputSafetyStateMachine CreateReadyState(
            ManualAgentRuntimeClock clock)
        {
            var state = new InputSafetyStateMachine(clock);
            state.SetInitialAuthoritativeState(
                new InputEpochSnapshot(
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
                    1),
                "flash-a");
            state.RecordGuardHeartbeat(true);
            return state;
        }
    }
}
