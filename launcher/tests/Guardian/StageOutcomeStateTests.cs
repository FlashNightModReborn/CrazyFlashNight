using CF7Launcher.Guardian;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class StageOutcomeStateTests
    {
        [Fact]
        public void VersionFourRequiresConsistentBoundedNativeReturnChoices()
        {
            JObject message = Message("victory");
            message["payload"]["v"] = 4;
            message["payload"]["returnFailure"] = "";
            message["payload"]["canSelectReturn"] = true;
            message["payload"]["returnOptions"] = new JObject {
                ["status"] = "ready", ["token"] = "return.options.1",
                ["choices"] = new JArray(new JObject { ["id"] = "task.40002", ["locationName"] = "联合大学", ["npcName"] = "Bat", ["taskName"] = "边界冲突" })
            };
            Assert.True(StageOutcomeState.TryParseMessage(message, out var state, out var error), error);
            Assert.Single(state.ReturnOptions.Choices);
            var bad = (JObject)message.DeepClone();
            bad["payload"]["returnOptions"]["choices"][0]["frame"] = "基地1层";
            Assert.False(StageOutcomeState.TryParseMessage(bad, out _, out _));
            bad = (JObject)message.DeepClone();
            ((JArray)bad["payload"]["returnOptions"]["choices"]).Add(bad["payload"]["returnOptions"]["choices"][0].DeepClone());
            Assert.False(StageOutcomeState.TryParseMessage(bad, out _, out _));
            foreach (string field in new[] { "token", "status" })
            {
                bad = (JObject)message.DeepClone();
                bad["payload"]["returnOptions"][field] = new JObject();
                Assert.False(StageOutcomeState.TryParseMessage(bad, out _, out _));
            }
            bad = (JObject)message.DeepClone();
            bad["payload"]["canSelectReturn"] = false;
            Assert.False(StageOutcomeState.TryParseMessage(bad, out _, out _));
            bad = (JObject)message.DeepClone();
            bad["payload"]["returnOptions"]["status"] = "loading";
            Assert.False(StageOutcomeState.TryParseMessage(bad, out _, out _));
        }

        private static JObject Message(
            string outcome = "active",
            string life = "alive",
            string settlement = "none",
            bool reviveAllowed = false,
            long reviveCoins = 2,
            string reviveBlockedReason = "",
            int remainingRewards = 0,
            bool canReturnBase = true)
        {
            return new JObject
            {
                ["task"] = "stage_outcome",
                ["payload"] = new JObject
                {
                    ["v"] = 1,
                    ["runId"] = "run.120.1",
                    ["revision"] = 7,
                    ["stageName"] = "废弃地铁",
                    ["difficulty"] = "冒险",
                    ["outcome"] = outcome,
                    ["life"] = life,
                    ["activeFrames"] = 5432,
                    ["reviveCoins"] = reviveCoins,
                    ["reviveAllowed"] = reviveAllowed,
                    ["reviveBlockedReason"] = reviveBlockedReason,
                    ["canReturnBase"] = canReturnBase,
                    ["settlement"] = settlement,
                    ["remainingRewards"] = remainingRewards
                }
            };
        }

        [Fact]
        public void StrictSnapshot_ParsesAuthorityFieldsAndFrameTime()
        {
            StageOutcomeState state;
            string error;

            Assert.True(StageOutcomeState.TryParseMessage(
                Message("victory"), out state, out error));

            Assert.Null(error);
            Assert.Equal("run.120.1", state.RunId);
            Assert.Equal(7, state.Revision);
            Assert.Equal(5432, state.ActiveFrames);
            Assert.True(state.ShouldDisplay);
            Assert.Equal("03:01.06", StageOutcomeState.FormatActiveTime(5432));
            Assert.Equal("01:01:01.00", StageOutcomeState.FormatActiveTime(109830));
        }

        [Theory]
        [InlineData(0L, "0")]
        [InlineData(9999L, "9999")]
        [InlineData(10000L, "1万")]
        [InlineData(20574L, "2.1万")]
        [InlineData(100000000L, "1亿")]
        [InlineData(1000000000000L, "1万亿")]
        public void ReviveCoinCount_UsesBoundedChineseUnits(long value, string expected)
        {
            Assert.Equal(expected, StageOutcomeState.FormatCompactCount(value));
        }

        [Fact]
        public void ActiveAliveSnapshot_IsNotAnOutcomeOverlay()
        {
            StageOutcomeState state;
            string error;

            Assert.True(StageOutcomeState.TryParseMessage(
                Message(), out state, out error));

            Assert.False(state.ShouldDisplay);
        }

        [Fact]
        public void DeathAndSuspendedRewards_AreIndependentDisplayAxes()
        {
            StageOutcomeState dead;
            StageOutcomeState rewards;
            string error;

            Assert.True(StageOutcomeState.TryParseMessage(
                Message(life: "dead", reviveAllowed: true), out dead, out error));
            Assert.True(dead.ShouldDisplay);
            Assert.True(dead.ReviveAllowed);

            Assert.True(StageOutcomeState.TryParseMessage(
                Message("victory", "alive", "rewards_pending",
                    remainingRewards: 3, canReturnBase: false),
                out rewards, out error));
            Assert.True(rewards.ShouldDisplay);
            Assert.Equal(3, rewards.RemainingRewards);
        }

        [Theory]
        [InlineData("failure")]
        [InlineData("retreat")]
        [InlineData("victory")]
        public void ZeroRewardPendingReport_IsValidAndVisible(string outcome)
        {
            StageOutcomeState state;
            string error;

            Assert.True(StageOutcomeState.TryParseMessage(
                Message(outcome, "alive", "rewards_pending",
                    remainingRewards: 0, canReturnBase: false),
                out state, out error));
            Assert.Null(error);
            Assert.Equal(0, state.RemainingRewards);
            Assert.Equal("rewards_pending", state.Settlement);
            Assert.True(state.ShouldDisplay);
        }

        [Fact]
        public void ReturnAndActiveWebSettlement_HideTheInStageDeathCard()
        {
            StageOutcomeState prepared;
            StageOutcomeState webActive;
            StageOutcomeState pending;
            string error;

            Assert.True(StageOutcomeState.TryParseMessage(
                Message("victory", "dead", "prepared"), out prepared, out error));
            Assert.False(prepared.ShouldDisplay);
            Assert.True(StageOutcomeState.TryParseMessage(
                Message("victory", "dead", "web_active"), out webActive, out error));
            Assert.False(webActive.ShouldDisplay);
            Assert.True(StageOutcomeState.TryParseMessage(
                Message("victory", "dead", "rewards_pending",
                    remainingRewards: 2, canReturnBase: false),
                out pending, out error));
            Assert.True(pending.ShouldDisplay);
        }

        [Fact]
        public void PendingRewards_RejectImpossibleActiveOrReturnableClaims()
        {
            StageOutcomeState state;
            string error;

            Assert.False(StageOutcomeState.TryParseMessage(
                Message("active", "alive", "rewards_pending",
                    remainingRewards: 0, canReturnBase: false),
                out state, out error));
            Assert.False(StageOutcomeState.TryParseMessage(
                Message("failure", "alive", "rewards_pending",
                    remainingRewards: 0, canReturnBase: true),
                out state, out error));
        }

        [Fact]
        public void ShapeDriftAndContradictoryReviveClaimsFailClosed()
        {
            StageOutcomeState state;
            string error;
            JObject extra = Message("victory");
            extra["payload"]["forgedReward"] = true;
            Assert.False(StageOutcomeState.TryParseMessage(extra, out state, out error));

            JObject contradiction = Message(
                life: "alive", reviveAllowed: true, reviveCoins: 2);
            Assert.False(StageOutcomeState.TryParseMessage(
                contradiction, out state, out error));

            JObject fractional = Message("victory");
            fractional["payload"]["activeFrames"] = 1.5;
            Assert.False(StageOutcomeState.TryParseMessage(
                fractional, out state, out error));
        }

        [Fact]
        public void TerminalSettlementCannotRetainRewards()
        {
            StageOutcomeState state;
            string error;

            Assert.False(StageOutcomeState.TryParseMessage(
                Message("victory", "alive", "claimed",
                    remainingRewards: 1), out state, out error));
            Assert.True(StageOutcomeState.TryParseMessage(
                Message("victory", "alive", "claimed"), out state, out error));
            Assert.False(state.ShouldDisplay);
        }

        [Theory]
        [InlineData("settlement_prepare_failed")]
        [InlineData("save_failed")]
        [InlineData("transition_failed")]
        [InlineData("return_base_failed")]
        public void V2FailedReturnRemainsVisibleWhilePrepared(string reason)
        {
            JObject message = Message("victory", "alive", "prepared", remainingRewards: 3);
            message["payload"]["v"] = 2;
            message["payload"]["returnFailure"] = reason;
            Assert.True(StageOutcomeState.TryParseMessage(message, out var state, out var error), error);
            Assert.True(state.ShouldDisplay);
            Assert.True(state.CanReturnBase);
            Assert.Equal(reason, state.ReturnFailure);
            message["payload"]["returnFailure"] = "";
            Assert.True(StageOutcomeState.TryParseMessage(message, out state, out error), error);
            Assert.False(state.ShouldDisplay);
        }

        [Fact]
        public void FailureProjectionRejectsUnknownReasonsAndTerminalOrReviveContradictions()
        {
            JObject message = Message("victory", "alive", "prepared");
            message["payload"]["v"] = 2;
            Assert.False(StageOutcomeState.TryParseMessage(message, out _, out _));
            message["payload"]["returnFailure"] = "invented";
            Assert.False(StageOutcomeState.TryParseMessage(message, out _, out _));
            message["payload"]["returnFailure"] = "save_failed";
            message["payload"]["settlement"] = "claimed";
            Assert.False(StageOutcomeState.TryParseMessage(message, out _, out _));
            message["payload"]["settlement"] = "prepared";
            message["payload"]["life"] = "dead";
            message["payload"]["reviveAllowed"] = true;
            Assert.False(StageOutcomeState.TryParseMessage(message, out _, out _));
            message["payload"]["reviveAllowed"] = false;
            message["payload"]["v"] = 1;
            Assert.False(StageOutcomeState.TryParseMessage(message, out _, out _));
        }
    }
}
