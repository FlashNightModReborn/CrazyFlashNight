using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using CF7Launcher.Bus;
using CF7Launcher.Guardian;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Tasks
{
    public sealed class WarlordStageTaskTests
    {
        private sealed class Harness
        {
            internal readonly List<JObject> Sent = new List<JObject>();
            internal readonly WarlordStageTask Task;
            internal int OpenCount;
            internal JObject OpenBinding;
            internal JObject OpenPlayerAvatarPortrait;
            internal JObject OpenResumeCheckpoint;
            internal string PanelInstanceId;
            internal bool SendResult = true;
            internal bool QueueResult = true;
            internal bool CompleteOpen = true;
            internal bool ThrowOpen;
            internal PanelHostController.TrackedOpenOutcome OpenOutcome =
                PanelHostController.TrackedOpenOutcome.OpenPosted;

            internal Harness()
            {
                Task = new WarlordStageTask(delegate(JObject command)
                {
                    Sent.Add((JObject)command.DeepClone());
                    return SendResult;
                });
                Task.SetOpenHandler(Open);
            }

            private bool Open(
                JObject binding,
                JObject playerAvatarPortrait,
                JObject resumeCheckpoint,
                string panelInstanceId,
                Func<bool> executionGate,
                Action<PanelHostController.TrackedOpenOutcome> completed)
            {
                OpenCount++;
                OpenBinding = (JObject)binding.DeepClone();
                OpenPlayerAvatarPortrait =
                    (JObject)playerAvatarPortrait.DeepClone();
                OpenResumeCheckpoint = resumeCheckpoint == null
                    ? null : (JObject)resumeCheckpoint.DeepClone();
                PanelInstanceId = panelInstanceId;
                Assert.True(executionGate());
                if (ThrowOpen) throw new InvalidOperationException("test open");
                if (CompleteOpen) completed(OpenOutcome);
                return QueueResult;
            }

            internal void Start(JObject binding)
            {
                Assert.Null(Task.HandleStart(BuildStart(binding)));
            }

            internal WarlordStageTask.PreparedTerminal Prepare(
                JObject binding,
                string terminal = "CompleteSubStage",
                string reasonCode = "warlord.stage.test")
            {
                WarlordStageTask.PreparedTerminal prepared;
                string rejection;
                WarlordStageTask.TerminalPrepareDisposition disposition =
                    Task.TryPrepareWebTerminal(
                        BuildWebTerminal(
                            PanelInstanceId,
                            binding,
                            terminal,
                            reasonCode),
                        "warlord",
                        PanelInstanceId,
                        out prepared,
                        out rejection);
                Assert.Equal(
                    WarlordStageTask.TerminalPrepareDisposition.Prepared,
                    disposition);
                Assert.Null(rejection);
                return prepared;
            }
        }

        [Fact]
        public void ExactTerminal_IsPreparedBeforeCloseAndSentOnceAfterCommit()
        {
            var harness = new Harness();
            JObject binding = BuildBinding();

            harness.Start(binding);
            JObject activePortrait;
            Assert.True(harness.Task.TryGetActivePlayerAvatarPortrait(
                harness.PanelInstanceId,
                out activePortrait));
            Assert.True(JToken.DeepEquals(
                BuildPlayerAvatarPortrait(),
                activePortrait));
            activePortrait["equipment"]["head"] = "tampered";
            Assert.True(harness.Task.TryGetActivePlayerAvatarPortrait(
                harness.PanelInstanceId,
                out activePortrait));
            Assert.Equal("", (string)activePortrait["equipment"]["head"]);
            WarlordStageTask.PreparedTerminal prepared =
                harness.Prepare(binding);

            Assert.Empty(harness.Sent);
            harness.Task.CommitPreparedTerminal(prepared);
            harness.Task.CommitPreparedTerminal(prepared);

            JObject command = Assert.Single(harness.Sent);
            Assert.Equal(
                new[] { "task", "action", "payload" },
                command.Properties().Select(p => p.Name).ToArray());
            Assert.Equal("cmd", (string)command["task"]);
            Assert.Equal("warlord_stage_result", (string)command["action"]);
            JObject payload = (JObject)command["payload"];
            Assert.Equal(
                new[]
                {
                    "schema", "runId", "subStageId", "scenarioRef",
                    "callId", "revision", "terminal", "reasonCode"
                },
                payload.Properties().Select(p => p.Name).ToArray());
            Assert.Equal(
                WarlordStageTask.TerminalSchema,
                (string)payload["schema"]);
            Assert.Equal("CompleteSubStage", (string)payload["terminal"]);
            Assert.True(SameIdentity(binding, payload));
        }

        [Fact]
        public void OuterCancellationAfterBusinessTerminal_IsIdempotentAndSendsNothing()
        {
            var harness = new Harness();
            JObject binding = BuildBinding();
            harness.Start(binding);
            WarlordStageTask.PreparedTerminal prepared =
                harness.Prepare(binding, "CompleteSubStage");
            harness.Task.CommitPreparedTerminal(prepared);
            Assert.Single(harness.Sent);

            Assert.Null(harness.Task.HandleOuterCancellation(
                BuildOuterCancellation(binding)));
            Assert.Single(harness.Sent);

            harness.Start(BuildBinding(
                runId: "run.after-terminal",
                subStageId: "sub.after-terminal",
                callId: "call.after-terminal"));
            Assert.Equal(2, harness.OpenCount);
        }

        [Fact]
        public void NotStarted_IsStartupFailureAndExactRetryCannotReopen()
        {
            var rejected = new Harness
            {
                QueueResult = false,
                CompleteOpen = false
            };
            JObject binding = BuildBinding();

            rejected.Start(binding);
            JObject attempt = (JObject)Assert.Single(rejected.Sent)["payload"];
            Assert.Equal(WarlordStageTask.AttemptSchema, (string)attempt["schema"]);
            Assert.Equal("not_started", (string)attempt["result"]);
            Assert.True(SameIdentity(binding, attempt));

            rejected.QueueResult = true;
            rejected.CompleteOpen = true;
            rejected.Start(binding);
            Assert.Equal(1, rejected.OpenCount);

            var queuedOnly = new Harness { CompleteOpen = false };
            queuedOnly.Start(binding);
            Assert.Empty(queuedOnly.Sent);

            var postNotDelivered = new Harness
            {
                OpenOutcome =
                    PanelHostController.TrackedOpenOutcome.PostNotDelivered
            };
            postNotDelivered.Start(binding);
            Assert.Equal(
                "not_started",
                (string)Assert.Single(postNotDelivered.Sent)["payload"]["result"]);

            var threw = new Harness { ThrowOpen = true };
            threw.Start(binding);
            JObject uncertain = (JObject)Assert.Single(threw.Sent)["payload"];
            Assert.Equal(WarlordStageTask.TerminalSchema, (string)uncertain["schema"]);
            Assert.Equal("Unknown", (string)uncertain["terminal"]);
        }

        [Fact]
        public void ExactContracts_RejectSpoofDriftAndUnexpectedFields()
        {
            var harness = new Harness();
            JObject extraStart = BuildStart(BuildBinding());
            extraStart["spoof"] = true;
            Assert.Null(harness.Task.HandleStart(extraStart));

            JObject wrongScenario = BuildBinding();
            wrongScenario["scenarioRef"] = "warlord_other";
            harness.Start(wrongScenario);

            JObject portraitWithWeapon = BuildStart(BuildBinding());
            portraitWithWeapon["payload"]["playerAvatarPortrait"]
                ["equipment"]["primary"] = "M4A1";
            Assert.Null(harness.Task.HandleStart(portraitWithWeapon));
            Assert.Equal(0, harness.OpenCount);

            JObject nonInitial = BuildBinding(revision: 1, callId: "call.2");
            harness.Start(nonInitial);
            Assert.Equal(0, harness.OpenCount);
            Assert.Empty(harness.Sent);

            JObject binding = BuildBinding();
            harness.Start(binding);
            JObject terminal = BuildWebTerminal(
                harness.PanelInstanceId,
                binding,
                "CompleteSubStage",
                "warlord.stage.test");
            terminal["payload"]["data"]["spoof"] = true;

            WarlordStageTask.PreparedTerminal prepared;
            string rejection;
            Assert.Equal(
                WarlordStageTask.TerminalPrepareDisposition.Rejected,
                harness.Task.TryPrepareWebTerminal(
                    terminal,
                    "warlord",
                    harness.PanelInstanceId,
                    out prepared,
                    out rejection));
            Assert.Equal("invalid_terminal", rejection);

            terminal = BuildWebTerminal(
                harness.PanelInstanceId,
                binding,
                "CompleteSubStage",
                "warlord.stage.test");
            terminal["payload"]["data"]["callId"] = "call.forged";
            Assert.Equal(
                WarlordStageTask.TerminalPrepareDisposition.Rejected,
                harness.Task.TryPrepareWebTerminal(
                    terminal,
                    "warlord",
                    harness.PanelInstanceId,
                    out prepared,
                    out rejection));
            Assert.Equal("identity_drift", rejection);
        }

        [Fact]
        public void DuplicateTerminal_IsIdempotentWhileConflictAndLateDriftFailClosed()
        {
            var harness = new Harness();
            JObject binding = BuildBinding();
            harness.Start(binding);
            JObject exact = BuildWebTerminal(
                harness.PanelInstanceId,
                binding,
                "CompleteSubStage",
                "warlord.stage.test");

            WarlordStageTask.PreparedTerminal prepared;
            string rejection;
            Assert.Equal(
                WarlordStageTask.TerminalPrepareDisposition.Prepared,
                harness.Task.TryPrepareWebTerminal(
                    exact,
                    "warlord",
                    harness.PanelInstanceId,
                    out prepared,
                    out rejection));
            WarlordStageTask.PreparedTerminal duplicate;
            Assert.Equal(
                WarlordStageTask.TerminalPrepareDisposition.Duplicate,
                harness.Task.TryPrepareWebTerminal(
                    exact,
                    "warlord",
                    harness.PanelInstanceId,
                    out duplicate,
                    out rejection));

            JObject conflict = (JObject)exact.DeepClone();
            conflict["payload"]["data"]["terminal"] = "FailStage";
            Assert.Equal(
                WarlordStageTask.TerminalPrepareDisposition.Rejected,
                harness.Task.TryPrepareWebTerminal(
                    conflict,
                    "warlord",
                    harness.PanelInstanceId,
                    out duplicate,
                    out rejection));
            Assert.Equal("terminal_conflict", rejection);

            harness.Task.CommitPreparedTerminal(prepared);
            Assert.Equal(
                WarlordStageTask.TerminalPrepareDisposition.Duplicate,
                harness.Task.TryPrepareWebTerminal(
                    exact,
                    "warlord",
                    harness.PanelInstanceId,
                    out duplicate,
                    out rejection));
            Assert.Equal(
                WarlordStageTask.TerminalPrepareDisposition.Rejected,
                harness.Task.TryPrepareWebTerminal(
                    conflict,
                    "warlord",
                    harness.PanelInstanceId,
                    out duplicate,
                    out rejection));
            Assert.Single(harness.Sent);
        }

        [Fact]
        public void SuspendedOrUnknownTerminal_CannotResurrectAnotherGeneration()
        {
            var harness = new Harness();
            JObject first = BuildBinding();
            harness.Start(first);
            WarlordStageTask.PreparedTerminal suspended;
            string rejection;
            Assert.Equal(
                WarlordStageTask.TerminalPrepareDisposition.Prepared,
                harness.Task.TryPrepareSuspendedClose(
                    harness.PanelInstanceId,
                    out suspended,
                    out rejection));
            harness.Task.CommitPreparedTerminal(suspended);

            JObject reopened = BuildBinding(revision: 1, callId: "call.2");
            harness.Start(reopened);
            Assert.Equal(1, harness.OpenCount);

            var completed = new Harness();
            completed.Start(first);
            completed.Task.CommitPreparedTerminal(completed.Prepare(first));
            completed.Start(reopened);
            Assert.Equal(1, completed.OpenCount);

            var deliveryUnknown = new Harness { SendResult = false };
            deliveryUnknown.Start(first);
            WarlordStageTask.PreparedTerminal failed;
            Assert.Equal(
                WarlordStageTask.TerminalPrepareDisposition.Prepared,
                deliveryUnknown.Task.TryPrepareSuspendedClose(
                    deliveryUnknown.PanelInstanceId,
                    out failed,
                    out rejection));
            deliveryUnknown.Task.CommitPreparedTerminal(failed);
            deliveryUnknown.Start(reopened);
            Assert.Equal(1, deliveryUnknown.OpenCount);
        }

        [Fact]
        public void CloseFailureAndTransportDisconnect_FreezeWithoutResultOrRetry()
        {
            JObject first = BuildBinding();
            JObject reopened = BuildBinding(revision: 1, callId: "call.2");

            var closeFailed = new Harness();
            closeFailed.Start(first);
            WarlordStageTask.PreparedTerminal prepared =
                closeFailed.Prepare(first, "Unknown", "warlord.stage.unknown");
            closeFailed.Task.FreezePreparedCloseUnknown(
                prepared,
                "test_close_failure");
            closeFailed.Start(first);
            closeFailed.Start(reopened);
            Assert.Equal(1, closeFailed.OpenCount);
            Assert.Empty(closeFailed.Sent);

            var disconnected = new Harness();
            disconnected.Start(first);
            disconnected.Task.HandleTransportDisconnected(
                disconnected.PanelInstanceId);
            disconnected.Start(reopened);
            Assert.Equal(1, disconnected.OpenCount);
            Assert.Empty(disconnected.Sent);

            var disconnectedWhileQueued = new Harness
            {
                CompleteOpen = false
            };
            disconnectedWhileQueued.Start(first);
            disconnectedWhileQueued.Task.HandleTransportDisconnected();
            disconnectedWhileQueued.Start(first);
            Assert.Equal(1, disconnectedWhileQueued.OpenCount);
            Assert.Empty(disconnectedWhileQueued.Sent);
        }

        [Fact]
        public void AuthoritativeExternalRetire_ReportsSuspendedAndNeverFailStage()
        {
            var harness = new Harness();
            JObject binding = BuildBinding();
            harness.Start(binding);

            harness.Task.HandleAuthoritativePanelClosed(
                "warlord",
                harness.PanelInstanceId);

            JObject payload = (JObject)Assert.Single(harness.Sent)["payload"];
            Assert.Equal("Suspended", (string)payload["terminal"]);
            Assert.NotEqual("FailStage", (string)payload["terminal"]);
            harness.Start(BuildBinding(revision: 1, callId: "call.2"));
            Assert.Equal(1, harness.OpenCount);

            var opening = new Harness { CompleteOpen = false };
            opening.Start(binding);
            opening.Task.HandleAuthoritativePanelClosed(
                "warlord",
                opening.PanelInstanceId);
            JObject openingPayload =
                (JObject)Assert.Single(opening.Sent)["payload"];
            Assert.Equal("Unknown", (string)openingPayload["terminal"]);
        }

        [Fact]
        public void OuterCancellation_IsStrictExactIdempotentAndAllowsFreshRun()
        {
            var harness = new Harness();
            JObject binding = BuildBinding();
            harness.Start(binding);
            string retiredPanel = harness.PanelInstanceId;
            Assert.True(harness.Task.IsPanelReadyForGameplay(
                retiredPanel));

            JObject malformed = BuildOuterCancellation(binding);
            malformed["payload"]["extra"] = true;
            Assert.Null(harness.Task.HandleOuterCancellation(malformed));
            Assert.True(harness.Task.IsPanelReadyForGameplay(retiredPanel));

            JObject foreign = (JObject)binding.DeepClone();
            foreign["callId"] = "call.foreign";
            Assert.Null(harness.Task.HandleOuterCancellation(
                BuildOuterCancellation(foreign)));
            Assert.True(harness.Task.IsPanelReadyForGameplay(
                retiredPanel));
            Assert.Empty(harness.Sent);

            Assert.Null(harness.Task.HandleOuterCancellation(
                BuildOuterCancellation(binding)));
            Assert.False(harness.Task.IsPanelReadyForGameplay(
                retiredPanel));
            Assert.Null(harness.Task.HandleOuterCancellation(
                BuildOuterCancellation(binding)));
            Assert.Empty(harness.Sent);

            harness.Start(BuildBinding(
                runId: "run.fresh",
                subStageId: "sub.fresh",
                callId: "call.fresh"));
            Assert.Equal(2, harness.OpenCount);
            string freshPanel = harness.PanelInstanceId;
            Assert.True(harness.Task.IsPanelReadyForGameplay(freshPanel));
            Assert.Null(harness.Task.HandleOuterCancellation(
                BuildOuterCancellation(binding)));
            Assert.True(harness.Task.IsPanelReadyForGameplay(freshPanel));
            Assert.Empty(harness.Sent);
        }

        [Fact]
        public void OuterCancellation_InvalidEnvelopeOrBindingHasZeroOwnerEffect()
        {
            var harness = new Harness();
            JObject binding = BuildBinding();
            harness.Start(binding);
            string panel = harness.PanelInstanceId;

            var invalid = new List<JObject>();
            JObject extraEnvelope = BuildOuterCancellation(binding);
            extraEnvelope["extra"] = true;
            invalid.Add(extraEnvelope);
            JObject missingReason = BuildOuterCancellation(binding);
            ((JObject)missingReason["payload"]).Remove("reasonCode");
            invalid.Add(missingReason);
            JObject invalidReason = BuildOuterCancellation(binding);
            invalidReason["payload"]["reasonCode"] = "not opaque";
            invalid.Add(invalidReason);
            JObject extraBinding = BuildOuterCancellation(binding);
            extraBinding["payload"]["binding"]["extra"] = true;
            invalid.Add(extraBinding);

            foreach (JObject message in invalid)
            {
                Assert.Null(harness.Task.HandleOuterCancellation(message));
                Assert.True(harness.Task.IsPanelReadyForGameplay(panel));
            }
            Assert.Empty(harness.Sent);
        }

        [Fact]
        public void OuterCancellation_RetiresAwaitingBattleResumeWithoutTerminal()
        {
            var harness = new Harness();
            JObject binding = BuildBinding();
            harness.Start(binding);
            string retired = harness.PanelInstanceId;
            string handoffToken;
            Assert.True(harness.Task.TryPermitBattleHandoffClose(
                retired, binding, out handoffToken));
            Assert.True(harness.Task.TryCommitBattleHandoffClose(
                retired, binding, handoffToken));
            Assert.True(harness.Task.CanAdoptBattleResumePanel(
                binding, retired, handoffToken));

            Assert.Null(harness.Task.HandleOuterCancellation(
                BuildOuterCancellation(binding)));
            Assert.False(harness.Task.CanAdoptBattleResumePanel(
                binding, retired, handoffToken));
            Assert.False(harness.Task.TryAdoptBattleResumePanel(
                binding,
                retired,
                "warlord.resume.cancelled",
                handoffToken,
                BuildResumeCheckpoint(binding, retired)));
            Assert.Null(harness.Task.HandleOuterCancellation(
                BuildOuterCancellation(binding)));
            Assert.Empty(harness.Sent);
        }

        [Fact]
        public void OuterCancellation_RetiresAdoptedResumeAndRejectsAppliedReceipt()
        {
            var harness = new Harness();
            JObject binding = BuildBinding();
            harness.Start(binding);
            string retired = harness.PanelInstanceId;
            string handoffToken;
            Assert.True(harness.Task.TryPermitBattleHandoffClose(
                retired, binding, out handoffToken));
            Assert.True(harness.Task.TryCommitBattleHandoffClose(
                retired, binding, handoffToken));
            JObject checkpoint = BuildResumeCheckpoint(binding, retired);
            const string resumed = "warlord.resume.cancelled";
            Assert.True(harness.Task.TryAdoptBattleResumePanel(
                binding,
                retired,
                resumed,
                handoffToken,
                checkpoint));

            Assert.Null(harness.Task.HandleOuterCancellation(
                BuildOuterCancellation(binding)));
            string rejection;
            Assert.False(harness.Task.TryAcceptBattleResumeApplied(
                BuildResumeApplied(resumed, binding, checkpoint, "applied"),
                "warlord",
                resumed,
                out rejection));
            Assert.Equal("late_event", rejection);
            Assert.False(harness.Task.IsPanelReadyForGameplay(resumed));
            Assert.Null(harness.Task.HandleOuterCancellation(
                BuildOuterCancellation(binding)));
            Assert.Empty(harness.Sent);
        }

        [Fact]
        public void BattleHandoffClosePermit_AdoptsOnlyFreshResumePanel()
        {
            var harness = new Harness();
            JObject binding = BuildBinding();
            harness.Start(binding);
            string retired = harness.PanelInstanceId;

            string handoffToken;
            Assert.True(harness.Task.TryPermitBattleHandoffClose(
                retired, binding, out handoffToken));
            Assert.False(string.IsNullOrEmpty(handoffToken));
            // PanelHost commits this before DoClose.  Exercise the real hazard: a
            // battle resume can arrive before its best-effort PanelClosed callback.
            Assert.True(harness.Task.TryCommitBattleHandoffClose(
                retired, binding, handoffToken));
            Assert.Empty(harness.Sent);
            JObject checkpoint = BuildResumeCheckpoint(binding, retired);
            Assert.True(harness.Task.TryAdoptBattleResumePanel(
                binding,
                retired,
                "warlord.resume.2",
                handoffToken,
                checkpoint));
            harness.Task.HandleAuthoritativePanelClosed("warlord", retired);
            Assert.Empty(harness.Sent);
            Assert.False(harness.Task.IsPanelReadyForGameplay(
                "warlord.resume.2"));

            WarlordStageTask.PreparedTerminal pendingTerminal;
            string pendingReason;
            Assert.Equal(WarlordStageTask.TerminalPrepareDisposition.Rejected,
                harness.Task.TryPrepareWebTerminal(
                    BuildWebTerminal(
                        "warlord.resume.2",
                        binding,
                        "CompleteSubStage",
                        "warlord.stage.test"),
                    "warlord",
                    "warlord.resume.2",
                    out pendingTerminal,
                    out pendingReason));
            Assert.Equal("resume_apply_pending", pendingReason);

            string applyReason;
            Assert.True(harness.Task.TryAcceptBattleResumeApplied(
                BuildResumeApplied(
                    "warlord.resume.2",
                    binding,
                    checkpoint,
                    "applied"),
                "warlord",
                "warlord.resume.2",
                out applyReason), applyReason);
            Assert.True(harness.Task.IsPanelReadyForGameplay(
                "warlord.resume.2"));

            WarlordStageTask.PreparedTerminal stale;
            string staleReason;
            Assert.Equal(WarlordStageTask.TerminalPrepareDisposition.Rejected,
                harness.Task.TryPrepareSuspendedClose(retired, out stale, out staleReason));
            Assert.Equal("late_event", staleReason);

            harness.PanelInstanceId = "warlord.resume.2";
            WarlordStageTask.PreparedTerminal prepared = harness.Prepare(binding);
            harness.Task.CommitPreparedTerminal(prepared);
            Assert.Single(harness.Sent);
            Assert.Equal("CompleteSubStage",
                (string)harness.Sent[0]["payload"]["terminal"]);
        }

        [Fact]
        public void SuspendedBattleResume_CannotReopenAcrossOuterGeneration()
        {
            var harness = new Harness();
            JObject first = BuildBinding();
            harness.Start(first);
            string retired = harness.PanelInstanceId;
            string handoffToken;
            Assert.True(harness.Task.TryPermitBattleHandoffClose(
                retired, first, out handoffToken));
            Assert.True(harness.Task.TryCommitBattleHandoffClose(
                retired, first, handoffToken));
            JObject checkpoint = BuildResumeCheckpoint(first, retired);
            const string resumed = "warlord.resume.checkpoint.1";
            Assert.True(harness.Task.TryAdoptBattleResumePanel(
                first,
                retired,
                resumed,
                handoffToken,
                checkpoint));
            string applyReason;
            Assert.True(harness.Task.TryAcceptBattleResumeApplied(
                BuildResumeApplied(resumed, first, checkpoint, "applied"),
                "warlord",
                resumed,
                out applyReason), applyReason);

            harness.Task.HandleAuthoritativePanelClosed("warlord", resumed);
            JObject suspended = (JObject)Assert.Single(harness.Sent)["payload"];
            Assert.Equal("Suspended", (string)suspended["terminal"]);

            JObject next = BuildBinding(revision: 1, callId: "call.2");
            harness.Start(next);
            Assert.Equal(1, harness.OpenCount);
            Assert.Null(harness.OpenResumeCheckpoint);
        }

        [Fact]
        public void BattleHandoff_DoCloseFailureAfterCommitFreezesUnknownAndReleasesStage()
        {
            var harness = new Harness();
            JObject binding = BuildBinding();
            harness.Start(binding);
            string retired = harness.PanelInstanceId;
            var panelPumps = new Queue<Action>();
            using var panelHost = new PanelHostController(
                delegate(Action action) { panelPumps.Enqueue(action); },
                delegate(Action action) { action(); });
            Assert.True(panelHost.TryOpenTrackedPanel(
                "warlord", "{}", retired,
                delegate { return true; },
                delegate(PanelHostController.TrackedOpenOutcome ignored) { }));
            Action openPump = Assert.Single(panelPumps);
            panelPumps.Clear();
            openPump();

            string handoffToken;
            Assert.True(harness.Task.TryPermitBattleHandoffClose(
                retired, binding, out handoffToken));
            bool committed = false;
            bool? closeCompleted = null;
            panelHost.SetBeforeDoCloseForTests(
                delegate { throw new InvalidOperationException("close fixture"); });
            Assert.True(panelHost.TryClosePanelExact(
                "warlord",
                retired,
                false,
                delegate
                {
                    committed = harness.Task.TryCommitBattleHandoffClose(
                        retired, binding, handoffToken);
                    return committed;
                },
                delegate { },
                delegate(bool closed)
                {
                    closeCompleted = closed;
                    if (!closed && committed)
                    {
                        harness.Task.FreezeBattleResumeUnknown(
                            binding,
                            retired,
                            handoffToken,
                            "stage.battle-handoff-close-failed");
                    }
                }));
            Action closePump = Assert.Single(panelPumps);
            panelPumps.Clear();
            closePump();

            Assert.True(committed);
            Assert.False(closeCompleted);
            JObject payload = (JObject)Assert.Single(harness.Sent)["payload"];
            Assert.Equal("Unknown", (string)payload["terminal"]);
            Assert.Equal("stage.battle-handoff-close-failed",
                (string)payload["reasonCode"]);

            harness.Start(BuildBinding(revision: 1, callId: "call.close-failed.2"));
            Assert.Equal(1, harness.OpenCount);
        }

        [Fact]
        public void TerminalHistoryCapacity_OverflowsByFailingClosedWithoutEviction()
        {
            var harness = new Harness();
            for (int i = 0; i < WarlordStageTask.MaximumTerminalHistory; i++)
            {
                JObject binding = BuildBinding(
                    runId: "run." + i,
                    subStageId: "sub." + i,
                    callId: "call." + i);
                harness.Start(binding);
                harness.Task.CommitPreparedTerminal(
                    harness.Prepare(binding));
            }

            int sentBeforeOverflow = harness.Sent.Count;
            harness.Start(BuildBinding(
                runId: "run.overflow",
                subStageId: "sub.overflow",
                callId: "call.overflow"));

            Assert.Equal(
                WarlordStageTask.MaximumTerminalHistory,
                harness.OpenCount);
            Assert.Equal(sentBeforeOverflow, harness.Sent.Count);
        }

        [Fact]
        public void RouterInit_IsHostDerivedAndKeepsExactOuterBinding()
        {
            JObject binding = BuildBinding();
            JObject init;
            string rejection;

            Assert.True(LauncherCommandRouter.TryBuildWarlordStageInitData(
                binding,
                BuildPlayerAvatarPortrait(),
                out init,
                out rejection));
            Assert.Null(rejection);
            Assert.Equal("game_stage", (string)init["source"]);
            Assert.Equal("stage-v1", (string)init["mode"]);
            Assert.Equal("warlord-tutorial-v1-seed-001", (string)init["seed"]);
            Assert.Equal("standard", (string)init["preset"]);
            Assert.Equal("normal", (string)init["difficulty"]);
            Assert.Equal("desert", (string)init["mapTheme"]);
            Assert.False((bool)init["productionWrites"]);
            Assert.Equal("as2", (string)init["battleAuthority"]);
            Assert.True(JToken.DeepEquals(binding, init["stageOuterBinding"]));
            Assert.True(JToken.DeepEquals(
                BuildPlayerAvatarPortrait(),
                init["playerAvatarPortrait"]));

            binding["extra"] = true;
            Assert.False(LauncherCommandRouter.TryBuildWarlordStageInitData(
                binding,
                BuildPlayerAvatarPortrait(),
                out init,
                out rejection));
        }

        [Fact]
        public void RegistryAndStageCloseWiring_StaySocketOnlyAndNeverReturnBase()
        {
            JObject status = JObject.Parse(
                TaskRegistry.ToStatusJson(true, 3000, 3001));
            JObject task = ((JArray)status["tasks"])
                .Children<JObject>()
                .Single(item =>
                    (string)item["name"] == "warlord_stage_start");
            JObject cancellationTask = ((JArray)status["tasks"])
                .Children<JObject>()
                .Single(item =>
                    (string)item["name"]
                        == WarlordStageTask.OuterCancellationTaskName);
            Assert.Equal("json_sync", (string)task["transport"]);
            Assert.Equal("AS2->C#", (string)task["direction"]);
            Assert.False((bool)task["httpCallable"]);
            Assert.Equal("json_sync", (string)cancellationTask["transport"]);
            Assert.Equal("AS2->C#", (string)cancellationTask["direction"]);
            Assert.False((bool)cancellationTask["httpCallable"]);

            string registrySource = File.ReadAllText(FindRepositoryFile(
                "launcher", "src", "Bus", "TaskRegistry.cs"));
            Assert.Contains(
                "warlordStageTask.HandleOuterCancellation",
                registrySource);
            Assert.DoesNotContain(
                "HandleParentActionCancellation",
                registrySource);

            string stageTaskSource = File.ReadAllText(FindRepositoryFile(
                "launcher", "src", "Tasks", "WarlordStageTask.cs"));
            Assert.Contains("invalid_initial_revision", stageTaskSource);
            Assert.DoesNotContain("invalid_reopen_generation", stageTaskSource);

            string source = File.ReadAllText(FindRepositoryFile(
                "launcher", "src", "Guardian", "WebOverlayForm.cs"));
            string stageClose = Slice(
                source,
                "private void QueueWarlordStageTerminalClose(",
                "private void HandleWarlordBattleStart(");
            Assert.Contains("TryCloseTrackedPanelExact(", stageClose);
            Assert.Contains("CommitAcceptedPanelCloseEffects(", stageClose);
            Assert.Contains("task.CommitPreparedTerminal(prepared);", stageClose);
            Assert.DoesNotContain("ConsumeReturnBaseOnFinalClose", stageClose);
            Assert.DoesNotContain("arenaReturnBase", stageClose);
        }

        private static JObject BuildBinding(
            long revision = 0,
            string callId = "call.1",
            string runId = "run.1",
            string subStageId = "sub.1")
        {
            return new JObject
            {
                ["schema"] = WarlordStageTask.BindingSchema,
                ["runId"] = runId,
                ["subStageId"] = subStageId,
                ["scenarioRef"] = WarlordStageTask.AllowedScenarioRef,
                ["callId"] = callId,
                ["revision"] = revision
            };
        }

        private static JObject BuildStart(JObject binding)
        {
            return new JObject
            {
                ["task"] = "warlord_stage_start",
                ["payload"] = new JObject
                {
                    ["binding"] = binding.DeepClone(),
                    ["playerAvatarPortrait"] = BuildPlayerAvatarPortrait()
                }
            };
        }

        private static JObject BuildOuterCancellation(
            JObject binding,
            string reasonCode = "stage.parent-return-base")
        {
            return new JObject
            {
                ["task"] = WarlordStageTask.OuterCancellationTaskName,
                ["payload"] = new JObject
                {
                    ["schema"] = WarlordStageTask.OuterCancellationSchema,
                    ["binding"] = binding.DeepClone(),
                    ["reasonCode"] = reasonCode
                }
            };
        }

        private static JObject BuildResumeCheckpoint(
            JObject binding,
            string retiredPanelInstanceId)
        {
            JObject state = new JObject { ["stateId"] = "state.test.1" };
            JObject command = new JObject { ["type"] = "MOVE_OR_ATTACK" };
            JObject clientContext = new JObject
            {
                ["seed"] = "warlord-tutorial-v1-seed-001",
                ["preset"] = "standard",
                ["difficulty"] = "normal",
                ["mapTheme"] = "desert",
                ["forceWebglFailure"] = false,
                ["aiSeenTransitions"] = new JArray()
            };
            JObject request = new JObject
            {
                ["schema"] = "warlord.as2-battle-request.v1",
                ["sessionId"] = "session.test.1",
                ["requestId"] = "request.test.1",
                ["state"] = state.DeepClone(),
                ["command"] = command.DeepClone(),
                ["clientContext"] = clientContext.DeepClone()
            };
            string digest = WarlordBattleTask.Sha256OfToken(request);
            JObject portrait = BuildPlayerAvatarPortrait();
            JObject resume = new JObject
            {
                ["schema"] = "warlord.as2-resume.v1",
                ["request"] = request,
                ["state"] = state,
                ["command"] = command,
                ["inputDigest"] = digest,
                ["receipt"] = new JObject
                {
                    ["schema"] = "warlord.as2-battle-receipt.v2",
                    ["status"] = "accepted",
                    ["sessionId"] = "session.test.1",
                    ["requestId"] = "request.test.1",
                    ["inputDigest"] = digest
                },
                ["clientContext"] = clientContext.DeepClone(),
                ["playerAvatarPortrait"] = portrait.DeepClone(),
                ["stageOuterBinding"] = binding.DeepClone(),
                ["stageResumeFromPanelInstanceId"] =
                    retiredPanelInstanceId
            };
            return new JObject
            {
                ["seed"] = clientContext["seed"].DeepClone(),
                ["preset"] = clientContext["preset"].DeepClone(),
                ["difficulty"] = clientContext["difficulty"].DeepClone(),
                ["mapTheme"] = clientContext["mapTheme"].DeepClone(),
                ["forceWebglFailure"] = false,
                ["aiSeenTransitions"] = new JArray(),
                ["mode"] = "stage-v1",
                ["source"] = "game_stage",
                ["productionWrites"] = false,
                ["battleAuthority"] = "as2",
                ["as2BattleSession"] = true,
                ["resume"] = resume,
                ["playerAvatarPortrait"] = portrait,
                ["stageOuterBinding"] = binding.DeepClone(),
                ["stageResumeFromPanelInstanceId"] =
                    retiredPanelInstanceId
            };
        }

        private static JObject BuildResumeApplied(
            string panelInstanceId,
            JObject binding,
            JObject checkpoint,
            string status)
        {
            JObject resume = (JObject)checkpoint["resume"];
            JObject request = (JObject)resume["request"];
            return new JObject
            {
                ["type"] = "panel",
                ["panel"] = "warlord",
                ["cmd"] = "minigame_session",
                ["panelInstanceId"] = panelInstanceId,
                ["payload"] = new JObject
                {
                    ["game"] = "warlord",
                    ["kind"] = "battle_resume_applied",
                    ["data"] = new JObject
                    {
                        ["schema"] = WarlordStageTask.ResumeAppliedSchema,
                        ["status"] = status,
                        ["inputDigest"] = resume["inputDigest"].DeepClone(),
                        ["sessionId"] = request["sessionId"].DeepClone(),
                        ["requestId"] = request["requestId"].DeepClone(),
                        ["stageOuterBinding"] = binding.DeepClone()
                    }
                }
            };
        }

        private static JObject BuildPlayerAvatarPortrait()
        {
            return new JObject
            {
                ["schema"] = WarlordStageTask.PlayerAvatarPortraitSchema,
                ["gender"] = "男",
                ["face"] = "男变装-基本脸型",
                ["hair"] = "发型-男式-平头",
                ["equipment"] = new JObject
                {
                    ["head"] = "",
                    ["body"] = "",
                    ["hand"] = "",
                    ["leg"] = "",
                    ["foot"] = "",
                    ["neck"] = ""
                }
            };
        }

        private static JObject BuildWebTerminal(
            string panelInstanceId,
            JObject binding,
            string terminal,
            string reasonCode)
        {
            return new JObject
            {
                ["type"] = "panel",
                ["panel"] = "warlord",
                ["cmd"] = "minigame_session",
                ["panelInstanceId"] = panelInstanceId,
                ["payload"] = new JObject
                {
                    ["game"] = "warlord",
                    ["kind"] = "stage_terminal",
                    ["data"] = WarlordStageTask.BuildTerminal(
                        binding,
                        terminal,
                        reasonCode)
                }
            };
        }

        private static bool SameIdentity(JObject binding, JObject envelope)
        {
            return (string)binding["runId"] == (string)envelope["runId"]
                && (string)binding["subStageId"]
                    == (string)envelope["subStageId"]
                && (string)binding["scenarioRef"]
                    == (string)envelope["scenarioRef"]
                && (string)binding["callId"] == (string)envelope["callId"]
                && (long)binding["revision"] == (long)envelope["revision"];
        }

        private static string Slice(
            string source,
            string startMarker,
            string endMarker)
        {
            int start = source.IndexOf(startMarker, StringComparison.Ordinal);
            Assert.True(start >= 0, "missing marker: " + startMarker);
            int end = source.IndexOf(endMarker, start, StringComparison.Ordinal);
            Assert.True(end > start, "missing marker: " + endMarker);
            return source.Substring(start, end - start);
        }

        private static string FindRepositoryFile(params string[] parts)
        {
            DirectoryInfo current = new DirectoryInfo(AppContext.BaseDirectory);
            while (current != null)
            {
                string candidate = current.FullName;
                for (int i = 0; i < parts.Length; i++)
                    candidate = Path.Combine(candidate, parts[i]);
                if (File.Exists(candidate)) return candidate;
                current = current.Parent;
            }
            throw new FileNotFoundException(
                "repository file not found",
                Path.Combine(parts));
        }
    }
}
