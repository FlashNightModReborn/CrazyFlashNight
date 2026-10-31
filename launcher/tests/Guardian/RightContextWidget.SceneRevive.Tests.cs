using System.Collections.Generic;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.Hud;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public partial class RightContextWidgetTests
    {
        private static StageOutcomeState SceneReviveState(string life, int revision, int version = 3)
        {
            var payload = new JObject
            {
                ["v"] = version, ["runId"] = "scene.100.1", ["revision"] = revision,
                ["stageName"] = "基地1层", ["difficulty"] = "普通地图", ["outcome"] = "active",
                ["life"] = life, ["activeFrames"] = 0, ["reviveCoins"] = 2,
                ["reviveAllowed"] = life == "dead", ["reviveBlockedReason"] = "",
                ["canReturnBase"] = false, ["settlement"] = "none", ["remainingRewards"] = 0
            };
            if (version >= 2) payload["returnFailure"] = "";
            if (version >= 3) payload["canSelectReturn"] = false;
            Assert.True(StageOutcomeState.TryParseMessage(
                new JObject { ["task"] = "stage_outcome", ["payload"] = payload },
                out var state, out var error), error);
            return state;
        }

        [Theory]
        [InlineData(1)]
        [InlineData(2)]
        [InlineData(3)]
        public void OrdinaryMapRevive_UsesExistingProtocolWithoutStageSettlement(int version)
        {
            var dead = SceneReviveState("dead", 2, version);
            Assert.True(dead.ShouldDisplay);
            Assert.True(dead.ReviveAllowed);
            Assert.False(dead.CanReturnBase);
            Assert.False(dead.CanSelectReturn);
            Assert.False(SceneReviveState("alive", 4, version).ShouldDisplay);
        }

        [Fact]
        public void OrdinaryMapDeath_OverridesCompletedTaskHint_ThenRestoresItAfterRevival()
        {
            var right = MakeWidget(out var capture);
            var intents = new List<string>();
            right.IntentRequested += (intent, identity, revision) =>
                intents.Add(intent + ":" + identity + ":" + revision);
            right.SetReady();
            right.ForceDeliverState(true, "base_dorm", true, "1");
            Assert.Equal(RightContextSlotOwner.ActionableNotice,
                NativeHudOverlay.ResolveAndProjectRightContextSlotOwner(right, null));

            right.ApplyState(SceneReviveState("dead", 2));
            Assert.Equal(RightContextSlotOwner.StageDecision,
                NativeHudOverlay.ResolveAndProjectRightContextSlotOwner(right, null));
            Assert.True(right.PaintsStageDecisionForTest);
            Assert.False(right.PaintsActionableNoticeForTest);
            Assert.Equal(new[] { "复活" }, right.StageActionLabelsForTest);
            Assert.True(right.StageActionEnabledForTest(0));
            Assert.True(right.StageActionBoundsForTest(0).Width > 0);
            right.SetStageActionDownForTest(0);
            right.ClickStageActionGestureForTest(0);
            Assert.Equal(new[] { "revive:scene.100.1:2" }, intents);

            right.ApplyState(SceneReviveState("reviving", 3));
            Assert.Empty(right.StageActionLabelsForTest);
            right.ApplyState(SceneReviveState("alive", 4));
            Assert.Equal(RightContextSlotOwner.ActionableNotice,
                NativeHudOverlay.ResolveAndProjectRightContextSlotOwner(right, null));
            Assert.True(right.PaintsActionableNoticeForTest);
            Assert.False(right.PaintsStageDecisionForTest);
        }
    }
}
