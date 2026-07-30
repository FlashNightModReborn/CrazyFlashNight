using System;
using CF7Launcher.AgentRuntime.Wings;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.Wings
{
    public sealed class WingsPersonaStateTests
    {
        private const string PublicPhase =
            "sp_7Qm2vL8aR4nK9xT1cY6uP";
        private const string PrivatePhase =
            "sp_2Dp8wR4mN7xK1qV9cL5hT";
        private const string TransitionReceipt =
            "tr_4Cx8mN1qT6vK9rL2pD7hF";

        [Fact]
        public void StoryPhaseAndOperationStateAreOrthogonal()
        {
            var machine = new WingsPersonaStateMachine(
                PublicPhase,
                1,
                true,
                WingsOperationState.Idle);
            machine.TransitionOperation(
                WingsOperationState.Observing);
            machine.TransitionOperation(
                WingsOperationState.Advising);

            WingsStoryPhaseChange change =
                machine.ApplyStoryPhaseTransition(
                    TransitionReceipt,
                    new StoryAuthority(
                        new TrustedStoryPhaseTransition(
                            TransitionReceipt,
                            PrivatePhase,
                            true,
                            2)));
            Assert.Equal(
                WingsOperationState.Advising,
                change.Snapshot.OperationState);
            Assert.Equal(PrivatePhase, change.Snapshot.StoryPhaseId);
            Assert.Equal(WingsPrivilegeDowngrade.None, change.Downgrade);
        }

        [Fact]
        public void LeavingPublicPhaseRevokesEveryEphemeralPrivilege()
        {
            var machine = new WingsPersonaStateMachine(
                PublicPhase,
                1,
                true,
                WingsOperationState.Executing);
            WingsStoryPhaseChange change =
                machine.ApplyStoryPhaseTransition(
                    TransitionReceipt,
                    new StoryAuthority(
                        new TrustedStoryPhaseTransition(
                            TransitionReceipt,
                            PrivatePhase,
                            false,
                            2)));

            Assert.False(change.Snapshot.PublicCompanionEligible);
            Assert.Equal(
                WingsOperationState.Executing,
                change.Snapshot.OperationState);
            Assert.Equal(
                WingsPrivilegeDowngrade.RevokeObservationGrant
                | WingsPrivilegeDowngrade.RevokeWriteLease
                | WingsPrivilegeDowngrade.CancelPendingActions
                | WingsPrivilegeDowngrade.RevokeOneShotTokens,
                change.Downgrade);
        }

        [Fact]
        public void InvalidOperationAndStaleNarrativeReceiptFailClosed()
        {
            var machine = new WingsPersonaStateMachine(
                PublicPhase,
                5,
                true,
                WingsOperationState.Idle);
            InvalidOperationException operation =
                Assert.Throws<InvalidOperationException>(
                    () => machine.TransitionOperation(
                        WingsOperationState.Executing));
            Assert.Equal(
                "operation_transition_invalid",
                operation.Message);

            InvalidOperationException stale =
                Assert.Throws<InvalidOperationException>(
                    () => machine.ApplyStoryPhaseTransition(
                        TransitionReceipt,
                        new StoryAuthority(
                            new TrustedStoryPhaseTransition(
                                TransitionReceipt,
                                PrivatePhase,
                                false,
                                5))));
            Assert.Equal(
                "story_phase_revision_stale",
                stale.Message);
            Assert.Equal(PublicPhase, machine.Snapshot.StoryPhaseId);
        }

        private sealed class StoryAuthority : IStoryPhaseAuthority
        {
            private readonly TrustedStoryPhaseTransition _transition;

            public StoryAuthority(
                TrustedStoryPhaseTransition transition)
            {
                _transition = transition;
            }

            public bool TryResolveTransition(
                string transitionReceiptId,
                out TrustedStoryPhaseTransition transition,
                out string reasonCode)
            {
                transition = _transition;
                reasonCode = null;
                return true;
            }
        }
    }
}
