using System;
using System.Collections.Generic;
using CF7Launcher.Tasks;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using Xunit;

namespace Launcher.Tests.Tasks
{
    public sealed class GymTrainingTaskTests
    {
        private sealed class Fixture : IDisposable
        {
            internal long Clock;
            internal bool Active = true;
            internal bool Ready = true;
            internal readonly List<JObject> Flash = new List<JObject>();
            internal readonly List<JObject> Web = new List<JObject>();
            internal readonly GymTrainingTask Task;

            internal Fixture()
            {
                Task = new GymTrainingTask(
                    () => Ready,
                    text => { Flash.Add(JObject.Parse(text.TrimEnd('\0'))); return true; },
                    () => Clock, 1000, () => Active, false);
                Task.SetPostToWeb(text => Web.Add(JObject.Parse(text)));
                Task.BindPanelOpenData(OpenData(), "panel.1");
            }

            internal void Request(string cmd, string callId, JObject payload = null,
                string instance = "panel.1")
            {
                Task.HandleWebRequest(cmd, new JObject {
                    ["type"] = "panel", ["panel"] = "gym", ["domain"] = "gym",
                    ["cmd"] = cmd, ["callId"] = callId, ["panelInstanceId"] = instance,
                    ["payload"] = payload ?? new JObject { ["v"] = 1 }
                });
            }

            internal void Start()
            {
                Request("start", "call.start",
                    new JObject { ["v"] = 1, ["projectId"] = "dummy.0" });
                Assert.Equal("gymStart", Flash[0].Value<string>("action"));
                Assert.Equal("gym.open.1.1", Flash[0].Value<string>("openToken"));
                Reply(0, "start", "running");
            }

            internal void Advance(int milliseconds)
            {
                for (int remaining = milliseconds; remaining > 0;)
                {
                    int step = Math.Min(200, remaining);
                    Clock += step;
                    Task.TickForTest();
                    remaining -= step;
                }
            }

            internal void Reply(int index, string operation, string phase,
                bool success = true, string token = "gym.session.1.1",
                string error = "rejected")
            {
                Task.HandleFlashResponse(Response(index, operation, phase,
                    success, token, error), _ => { });
            }

            internal JObject Response(int index, string operation, string phase,
                bool success = true, string token = "gym.session.1.1",
                string error = "rejected")
            {
                return new JObject {
                    ["task"] = "gym_training_response",
                    ["callId"] = Flash[index].Value<int>("callId"),
                    ["v"] = 1, ["operation"] = operation, ["success"] = success,
                    ["error"] = success ? JValue.CreateNull() : new JValue(error),
                    ["openToken"] = "gym.open.1.1",
                    ["sessionToken"] = token,
                    ["stationId"] = "dummy", ["projectId"] = "dummy.0",
                    ["phase"] = phase, ["saved"] = phase == "applied",
                    ["durationMs"] = 10000,
                    ["award"] = new JObject { ["kind"] = "stat", ["amount"] = 3,
                        ["baseExperience"] = 10000, ["capExperience"] = 0 },
                    ["balances"] = new JObject { ["money"] = 100000, ["kpoint"] = 5000 },
                    ["current"] = 3, ["cap"] = 500,
                    ["experience"] = 10000, ["skillPoints"] = 0, ["level"] = 1
                };
            }

            public void Dispose() { Task.Dispose(); }

            private static string OpenData()
            {
                return new JObject {
                    ["mode"] = "preview", ["source"] = "world_gym",
                    ["stationId"] = "dummy",
                    ["snapshot"] = new JObject {
                        ["v"] = 2, ["openToken"] = "gym.open.1.1",
                        ["stationId"] = "dummy",
                        ["pendingSession"] = JValue.CreateNull(),
                        ["projects"] = new JArray {
                            new JObject { ["id"] = "dummy.0", ["durationMs"] = 10000 }
                        }
                    }
                }.ToString(Formatting.None);
            }
        }

        [Fact]
        public void ForegroundClockPausesAndOnlyHostCanSendOneFinish()
        {
            using var f = new Fixture();
            f.Start();
            f.Advance(5000);
            Assert.Single(f.Flash);
            Assert.Equal(5000, f.Web[f.Web.Count - 1].Value<long>("elapsedMs"));

            f.Active = false;
            f.Clock = 9000;
            f.Task.TickForTest();
            Assert.True(f.Web[f.Web.Count - 1].Value<bool>("paused"));
            Assert.Equal(5000, f.Web[f.Web.Count - 1].Value<long>("elapsedMs"));

            f.Active = true;
            f.Clock = 13000;
            f.Task.TickForTest();
            Assert.Single(f.Flash);
            f.Advance(5000);
            Assert.Equal("gymFinish", f.Flash[1].Value<string>("action"));
            Assert.Equal("gym.session.1.1", f.Flash[1].Value<string>("sessionToken"));
            Assert.Equal("settling", f.Web[f.Web.Count - 1].Value<string>("phase"));
            f.Clock = 30000;
            f.Task.TickForTest();
            Assert.Equal(2, f.Flash.Count);

            f.Reply(1, "finish", "applied");
            JObject result = f.Web[f.Web.Count - 1];
            Assert.Equal("settled", result.Value<string>("event"));
            Assert.Equal("applied", result.Value<string>("phase"));
            Assert.True(result.Value<bool>("saved"));
            Assert.Equal("gym.session.1.1", result.Value<string>("sessionToken"));
        }

        [Fact]
        public void StarvedClockNeverCreditsAnUnobservedLongGap()
        {
            using var f = new Fixture();
            f.Start();
            // No timer callback occurs while the machine is asleep, even if
            // process activation appears true both before and after it.
            f.Clock = 10000;
            f.Task.TickForTest();
            Assert.Equal(400, f.Web[f.Web.Count - 1].Value<long>("elapsedMs"));
            Assert.Single(f.Flash);
            f.Advance(9600);
            Assert.Equal("gymFinish", f.Flash[1].Value<string>("action"));
        }

        [Fact]
        public void ClosingRunningPanelCancelsWithoutFinish()
        {
            using var f = new Fixture();
            f.Start();
            f.Task.HandlePanelClosed("panel.1");
            Assert.Equal("gymCancel", f.Flash[1].Value<string>("action"));
            f.Clock = 20000;
            f.Task.TickForTest();
            Assert.Equal(2, f.Flash.Count);
            f.Reply(1, "cancel", "cancelled");
            f.Task.TickForTest();
            Assert.Equal(2, f.Flash.Count);
        }

        [Fact]
        public void UnknownFinishRequiresExactQueryAndNeverReplaysWrite()
        {
            using var f = new Fixture();
            f.Start();
            f.Advance(10000);
            f.Reply(1, "finish", "applied", token: "gym.session.wrong");
            Assert.Equal("needs_reconcile", f.Web[f.Web.Count - 1].Value<string>("phase"));

            f.Request("start", "call.second",
                new JObject { ["v"] = 1, ["projectId"] = "dummy.0" });
            Assert.Equal("busy", f.Web[f.Web.Count - 1].Value<string>("error"));
            Assert.Equal(2, f.Flash.Count);

            f.Request("query", "call.query");
            Assert.Equal("gymQuery", f.Flash[2].Value<string>("action"));
            Assert.Equal("gym.session.1.1", f.Flash[2].Value<string>("sessionToken"));
            f.Reply(2, "query", "applied");
            Assert.Equal("applied", f.Web[f.Web.Count - 1].Value<string>("phase"));
            Assert.Equal(3, f.Flash.Count);
        }

        [Fact]
        public void WebCannotSupplyDurationPriceOrForeignOwner()
        {
            using var f = new Fixture();
            f.Request("start", "call.bad", new JObject {
                ["v"] = 1, ["projectId"] = "dummy.0", ["durationMs"] = 1
            });
            Assert.Equal("invalid_payload", f.Web[f.Web.Count - 1].Value<string>("error"));
            f.Request("start", "call.foreign",
                new JObject { ["v"] = 1, ["projectId"] = "dummy.0" },
                "panel.foreign");
            Assert.Equal("panel_instance_expired",
                f.Web[f.Web.Count - 1].Value<string>("error"));
            Assert.Empty(f.Flash);
        }

        [Fact]
        public void DefinitiveRefusalsRemainNoWriteAndDoNotLockNewStart()
        {
            using var f = new Fixture();
            f.Request("start", "call.refused",
                new JObject { ["v"] = 1, ["projectId"] = "dummy.0" });
            f.Reply(0, "start", "preview", success: false);
            Assert.Equal("preview", f.Web[f.Web.Count - 1].Value<string>("phase"));
            Assert.False(f.Web[f.Web.Count - 1].Value<bool>("requiresReconcile"));

            f.Request("start", "call.start2",
                new JObject { ["v"] = 1, ["projectId"] = "dummy.0" });
            f.Reply(1, "start", "running");
            f.Advance(10000);
            f.Reply(2, "finish", "cancelled", success: false);
            Assert.Equal("cancelled", f.Web[f.Web.Count - 1].Value<string>("phase"));
            Assert.False(f.Web[f.Web.Count - 1].Value<bool>("requiresReconcile"));
            f.Request("start", "call.start3",
                new JObject { ["v"] = 1, ["projectId"] = "dummy.0" });
            Assert.Equal("gymStart", f.Flash[3].Value<string>("action"));
        }

        [Fact]
        public void ExactQueryShowingRunningRearmsSameSessionAfterUnknownFinish()
        {
            using var f = new Fixture();
            f.Start();
            f.Advance(10000);
            f.Reply(1, "finish", "applied", token: "gym.session.wrong");
            f.Request("query", "call.query");
            f.Reply(2, "query", "running");
            Assert.Equal("running", f.Web[f.Web.Count - 1].Value<string>("phase"));
            f.Task.TickForTest();
            Assert.Equal("gymFinish", f.Flash[3].Value<string>("action"));
            Assert.Equal("gym.session.1.1",
                f.Flash[3].Value<string>("sessionToken"));
        }

        [Fact]
        public void DisconnectBeforeFinishDropsUnpaidClockButUnknownFinishIsRetained()
        {
            using var f = new Fixture();
            f.Start();
            f.Ready = false;
            f.Task.OnSocketDisconnected();
            f.Clock = 20000;
            f.Task.TickForTest();
            f.Ready = true;
            f.Request("status", "call.after.disconnect");
            Assert.Equal("preview", f.Web[f.Web.Count - 1].Value<string>("phase"));
            Assert.Single(f.Flash);

            f.Request("start", "call.restart",
                new JObject { ["v"] = 1, ["projectId"] = "dummy.0" });
            f.Reply(1, "start", "running");
            f.Advance(10000);
            Assert.Equal("gymFinish", f.Flash[2].Value<string>("action"));
            f.Ready = false;
            f.Task.OnSocketDisconnected();
            f.Ready = true;
            f.Request("status", "call.unknown");
            Assert.Equal("needs_reconcile",
                f.Web[f.Web.Count - 1].Value<string>("phase"));
        }

        [Fact]
        public void NotReadyIsProvenNoWriteAndNeedsMoreActiveTime()
        {
            using var f = new Fixture();
            f.Start();
            f.Advance(10000);
            f.Reply(1, "finish", "running", success: false, error: "not_ready");
            Assert.Equal("running", f.Web[f.Web.Count - 1].Value<string>("phase"));
            Assert.False(f.Web[f.Web.Count - 1].Value<bool>("requiresReconcile"));
            f.Advance(500);
            Assert.Equal(2, f.Flash.Count);
            f.Advance(500);
            Assert.Equal("gymFinish", f.Flash[2].Value<string>("action"));
        }

        [Fact]
        public void ExactStaleQueryLeavesHonestOutcomeGapUntilFreshOpen()
        {
            using var f = new Fixture();
            f.Start();
            f.Advance(10000);
            f.Reply(1, "finish", "applied", token: "gym.session.wrong");
            f.Request("query", "call.query");
            f.Reply(2, "query", "preview", success: false, error: "stale_token");
            Assert.Equal("outcome_unavailable",
                f.Web[f.Web.Count - 1].Value<string>("phase"));
            f.Request("start", "call.blocked",
                new JObject { ["v"] = 1, ["projectId"] = "dummy.0" });
            Assert.Equal("busy", f.Web[f.Web.Count - 1].Value<string>("error"));
            f.Task.BindPanelOpenData(
                new JObject {
                    ["mode"] = "preview", ["source"] = "world_gym",
                    ["stationId"] = "dummy",
                    ["snapshot"] = new JObject {
                        ["v"] = 2, ["openToken"] = "gym.open.2.1",
                        ["stationId"] = "dummy",
                        ["pendingSession"] = JValue.CreateNull(),
                        ["projects"] = new JArray { new JObject {
                            ["id"] = "dummy.0", ["durationMs"] = 10000 } }
                    }
                }.ToString(Formatting.None), "panel.2");
            f.Request("status", "call.new", instance: "panel.2");
            Assert.Equal("preview", f.Web[f.Web.Count - 1].Value<string>("phase"));
        }

        [Fact]
        public void LateAppliedResultWinsAgainstCancel()
        {
            using var f = new Fixture();
            f.Start();
            f.Task.HandlePanelClosed("panel.1");
            f.Reply(1, "cancel", "applied");
            Assert.Equal("settled", f.Web[f.Web.Count - 1].Value<string>("event"));
            Assert.Equal("applied", f.Web[f.Web.Count - 1].Value<string>("phase"));
        }

        [Fact]
        public void SavePendingReopenBindsExactSessionAndQueriesBeforeRetrySave()
        {
            using var f = new Fixture();
            f.Start();
            f.Advance(10000);
            f.Reply(1, "finish", "save_pending", success: false,
                error: "save_pending");
            f.Task.HandlePanelClosed("panel.1");
            f.Task.BindPanelOpenData(
                new JObject {
                    ["mode"] = "preview", ["source"] = "world_gym",
                    ["stationId"] = "dummy",
                    ["snapshot"] = new JObject {
                        ["v"] = 2, ["openToken"] = "gym.open.2.1",
                        ["stationId"] = "dummy",
                        ["pendingSession"] = new JObject {
                            ["sessionToken"] = "gym.session.1.1",
                            ["stationId"] = "dummy", ["projectId"] = "dummy.0",
                            ["phase"] = "save_pending"
                        },
                        ["projects"] = new JArray { new JObject {
                            ["id"] = "dummy.0", ["durationMs"] = 10000 } }
                    }
                }.ToString(Formatting.None), "panel.2");
            f.Request("status", "call.reopen", instance: "panel.2");
            Assert.Equal("save_pending", f.Web[f.Web.Count - 1].Value<string>("phase"));
            Assert.True(f.Web[f.Web.Count - 1].Value<bool>("queryRequired"));
            f.Request("retrySave", "call.early", instance: "panel.2");
            Assert.Equal("query_required",
                f.Web[f.Web.Count - 1].Value<string>("error"));

            f.Request("query", "call.reconcile", instance: "panel.2");
            Assert.Equal("gymQuery", f.Flash[2].Value<string>("action"));
            f.Reply(2, "query", "save_pending", success: false,
                error: "save_pending");
            Assert.False(f.Web[f.Web.Count - 1].Value<bool>("queryRequired"));
            f.Request("retrySave", "call.save", instance: "panel.2");
            Assert.Equal("gymRetrySave", f.Flash[3].Value<string>("action"));
            Assert.Equal("gym.session.1.1",
                f.Flash[3].Value<string>("sessionToken"));
            f.Reply(3, "retrySave", "applied");
            Assert.Equal("applied", f.Web[f.Web.Count - 1].Value<string>("phase"));
        }

        [Fact]
        public void MalformedAwardCannotBecomeConfirmedFinish()
        {
            using var f = new Fixture();
            f.Start();
            f.Advance(10000);
            JObject forged = f.Response(1, "finish", "applied");
            forged["award"]["kind"] = "experience";
            f.Task.HandleFlashResponse(forged, _ => { });
            Assert.Equal("needs_reconcile",
                f.Web[f.Web.Count - 1].Value<string>("phase"));
            Assert.False(f.Web[f.Web.Count - 1].Value<bool>("success"));
            Assert.Equal(2, f.Flash.Count);
        }

        [Fact]
        public void FreshOpenDoesNotCarryOldCompletedSessionIntoNewPanel()
        {
            using var f = new Fixture();
            f.Start();
            f.Advance(10000);
            f.Reply(1, "finish", "applied");
            f.Task.BindPanelOpenData(
                new JObject {
                    ["mode"] = "preview", ["source"] = "world_gym",
                    ["stationId"] = "dummy",
                    ["snapshot"] = new JObject {
                        ["v"] = 2, ["openToken"] = "gym.open.2.1",
                        ["stationId"] = "dummy",
                        ["pendingSession"] = JValue.CreateNull(),
                        ["projects"] = new JArray { new JObject {
                            ["id"] = "dummy.0", ["durationMs"] = 10000 } }
                    }
                }.ToString(Formatting.None), "panel.2");
            f.Request("status", "call.fresh", instance: "panel.2");
            Assert.Equal("preview", f.Web[f.Web.Count - 1].Value<string>("phase"));
        }
    }
}
