using System;
using System.Collections.Generic;
using CF7Launcher.Guardian;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Tasks
{
    public sealed class StageOutcomeTaskTests
    {
        private sealed class FakePresenter : IStageOutcomePresenter
        {
            public event Action<string, string, int> IntentRequested;
            public int ReadyCalls;
            public int ResetCalls;
            public readonly List<StageOutcomeState> States =
                new List<StageOutcomeState>();

            public void SetReady() { ReadyCalls++; }
            public void ApplyState(StageOutcomeState state) { States.Add(state); }
            public void ResetState() { ResetCalls++; }

            public void Raise(string intent, string runId, int revision)
            {
                Action<string, string, int> handler = IntentRequested;
                if (handler != null) handler(intent, runId, revision);
            }
        }

        private static JObject Message()
        {
            return new JObject
            {
                ["task"] = "stage_outcome",
                ["payload"] = new JObject
                {
                    ["v"] = 1,
                    ["runId"] = "run.task.1",
                    ["revision"] = 4,
                    ["stageName"] = "测试关卡",
                    ["difficulty"] = "挑战",
                    ["outcome"] = "victory",
                    ["life"] = "dead",
                    ["activeFrames"] = 3723,
                    ["reviveCoins"] = 2,
                    ["reviveAllowed"] = true,
                    ["reviveBlockedReason"] = "",
                    ["canReturnBase"] = true,
                    ["settlement"] = "none",
                    ["remainingRewards"] = 0
                }
            };
        }

        [Fact]
        public void ValidState_IsAppliedButNeverAcknowledgedAsNewAuthority()
        {
            var sent = new List<string>();
            var overlay = new FakePresenter();
            using (var task = new StageOutcomeTask(
                payload => { sent.Add(payload); return true; }, overlay))
            {
                Assert.Null(task.Handle(Message()));
                Assert.Single(overlay.States);
                Assert.Equal("victory", overlay.States[0].Outcome);
                Assert.Empty(sent);

                JObject malformed = Message();
                malformed["payload"]["rewardAuthority"] = true;
                Assert.Null(task.Handle(malformed));
                Assert.Single(overlay.States);
                Assert.Empty(sent);
            }
        }

        [Fact]
        public void ReadyAndAllowedIntents_EmitExactNullTerminatedCommands()
        {
            var sent = new List<string>();
            var overlay = new FakePresenter();
            using (var task = new StageOutcomeTask(
                payload => { sent.Add(payload); return true; }, overlay))
            {
                task.SetReady();
                Assert.Equal(1, overlay.ReadyCalls);
                Assert.Single(sent);
                Assert.EndsWith("\0", sent[0]);
                Assert.Equal(new JObject
                {
                    ["task"] = "cmd",
                    ["action"] = "stageOutcomeSync",
                    ["v"] = 1
                }, JObject.Parse(sent[0].TrimEnd('\0')));

                overlay.Raise("revive", "run.task.1", 4);
                overlay.Raise("return_base", "run.task.1", 4);
                overlay.Raise("return_deliverable", "run.task.1", 4);
                overlay.Raise("resume_rewards", "run.task.1", 4);
                Assert.Equal(5, sent.Count);
                var ids = new HashSet<string>(StringComparer.Ordinal);
                for (int i = 1; i < sent.Count; i++)
                {
                    Assert.EndsWith("\0", sent[i]);
                    JObject command = JObject.Parse(sent[i].TrimEnd('\0'));
                    Assert.Equal(7, command.Count);
                    Assert.Equal("cmd", command.Value<string>("task"));
                    Assert.Equal("stageOutcomeAction", command.Value<string>("action"));
                    Assert.Equal(1, command.Value<int>("v"));
                    Assert.Equal("run.task.1", command.Value<string>("runId"));
                    Assert.Equal(4, command.Value<int>("expectedRevision"));
                    Assert.True(ids.Add(command.Value<string>("intentId")));
                }
                Assert.Equal("revive", JObject.Parse(sent[1].TrimEnd('\0')).Value<string>("intent"));
                Assert.Equal("return_base", JObject.Parse(sent[2].TrimEnd('\0')).Value<string>("intent"));
                Assert.Equal("return_deliverable", JObject.Parse(sent[3].TrimEnd('\0')).Value<string>("intent"));
                Assert.Equal("resume_rewards", JObject.Parse(sent[4].TrimEnd('\0')).Value<string>("intent"));
            }
        }

        [Fact]
        public void InvalidIntentAndDisposedTask_AreZeroSend()
        {
            var sent = new List<string>();
            var overlay = new FakePresenter();
            var task = new StageOutcomeTask(
                payload => { sent.Add(payload); return true; }, overlay);

            overlay.Raise("continue", "run.task.1", 4);
            overlay.Raise("revive", "", 4);
            overlay.Raise("revive", "run.task.1", 0);
            Assert.Empty(sent);

            task.Dispose();
            overlay.Raise("revive", "run.task.1", 4);
            task.SetReady();
            task.Handle(Message());
            Assert.Empty(sent);
            Assert.Empty(overlay.States);
        }

        [Fact]
        public void TransportDisconnect_ClearsStaleOverlayExactlyWhileAlive()
        {
            var overlay = new FakePresenter();
            var task = new StageOutcomeTask(payload => true, overlay);

            task.HandleTransportDisconnected();
            Assert.Equal(1, overlay.ResetCalls);

            task.Dispose();
            task.HandleTransportDisconnected();
            Assert.Equal(1, overlay.ResetCalls);
        }

        [Fact]
        public void ZeroRewardPendingReport_IsAppliedAndCanRequestResume()
        {
            var sent = new List<string>();
            var overlay = new FakePresenter();
            JObject message = Message();
            message["payload"]["outcome"] = "failure";
            message["payload"]["life"] = "alive";
            message["payload"]["reviveAllowed"] = false;
            message["payload"]["reviveCoins"] = 0;
            message["payload"]["settlement"] = "rewards_pending";
            message["payload"]["remainingRewards"] = 0;
            message["payload"]["canReturnBase"] = false;

            using (var task = new StageOutcomeTask(
                payload => { sent.Add(payload); return true; }, overlay))
            {
                task.Handle(message);
                Assert.Single(overlay.States);
                Assert.True(overlay.States[0].ShouldDisplay);
                Assert.Equal(0, overlay.States[0].RemainingRewards);

                overlay.Raise("resume_rewards", "run.task.1", 4);
                Assert.Single(sent);
                JObject command = JObject.Parse(sent[0].TrimEnd('\0'));
                Assert.Equal("stageOutcomeAction", command.Value<string>("action"));
                Assert.Equal("resume_rewards", command.Value<string>("intent"));
                Assert.Equal("run.task.1", command.Value<string>("runId"));
                Assert.Equal(4, command.Value<int>("expectedRevision"));
            }
        }
    }
}
