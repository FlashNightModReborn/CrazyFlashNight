using System;
using System.Collections.Generic;
using System.Reflection;
using System.Threading;
using CF7Launcher.Bus;
using CF7Launcher.Guardian;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class GameLaunchFlowRevealWatchdogTests
    {
        [Fact]
        public void ProductionDefault_IsBoundedTwentySeconds_AndDeadlineIsInjectable()
        {
            Assert.Equal(
                45000,
                GameLaunchFlow.FLASH_REVEAL_WATCHDOG_DEFAULT_MS);

            using var harness = new Harness(1234);
            Assert.Equal(
                1234,
                GetPrivateField<int>(
                    harness.Flow,
                    "_flashRevealWatchdogMs"));
        }

        [Fact]
        public void AcceptedTitleBeforeDeadline_CancelsWatchdogAndReveals()
        {
            using var harness = new Harness(60000);
            harness.ArmReady("attempt-title-first");

            Assert.NotNull(Watchdog(harness.Flow));
            Assert.True(WaitingForFlash(harness.Flow));
            Assert.False(RevealPerformed(harness.Flow));

            harness.SendRevealReady("attempt-title-first");

            Assert.False(WaitingForFlash(harness.Flow));
            Assert.True(RevealPerformed(harness.Flow));
            Assert.True(
                harness.Flow.HasAcceptedTitleReceipt(
                    "attempt-title-first"));
            Assert.Null(Watchdog(harness.Flow));
        }

        [Fact]
        public void WatchdogFirst_ForceReveals_AndLateTitleRemainsIgnored()
        {
            using var harness = new Harness(25);
            harness.ArmReady("attempt-watchdog-first");

            Assert.True(
                SpinWait.SpinUntil(
                    () => RevealPerformed(harness.Flow),
                    TimeSpan.FromSeconds(2)),
                "injected Flash reveal watchdog did not fire");
            Assert.False(WaitingForFlash(harness.Flow));
            Assert.Null(Watchdog(harness.Flow));

            harness.SendRevealReady("attempt-watchdog-first");

            Assert.False(WaitingForFlash(harness.Flow));
            Assert.True(RevealPerformed(harness.Flow));
            Assert.True(
                harness.Flow.HasAcceptedTitleReceipt(
                    "attempt-watchdog-first"));
            Assert.Null(Watchdog(harness.Flow));
        }

        [Fact]
        public void StaleAttemptTitle_DoesNotConsumeCurrentRevealGate()
        {
            using var harness = new Harness(60000);
            harness.ArmReady("attempt-current");
            Timer armed = Watchdog(harness.Flow);

            harness.SendRevealReady("attempt-stale");

            Assert.True(WaitingForFlash(harness.Flow));
            Assert.False(RevealPerformed(harness.Flow));
            Assert.False(
                harness.Flow.HasAcceptedTitleReceipt(
                    "attempt-current"));
            Assert.Same(armed, Watchdog(harness.Flow));

            harness.SendRevealReady("attempt-current");

            Assert.False(WaitingForFlash(harness.Flow));
            Assert.True(RevealPerformed(harness.Flow));
            Assert.Null(Watchdog(harness.Flow));
        }

        [Fact]
        public void TrustedEntry_SendRequiresExactA5ReadyTitleAttempt()
        {
            using var harness = new Harness(60000);
            const string attemptId = "attempt-trusted-entry";
            harness.ArmReady(attemptId);

            Assert.False(
                harness.Flow.TrySendTrustedResolvedSaveEntry(
                    "cf7_agent_a5_material_shop_run",
                    attemptId));

            harness.SendRevealReady(attemptId);

            Assert.False(
                harness.Flow.TrySendTrustedResolvedSaveEntry(
                    "cf7_agent_a5_material_shop_run_near",
                    attemptId));
            Assert.False(
                harness.Flow.TrySendTrustedResolvedSaveEntry(
                    "cf7_agent_a5_material_shop_run",
                    "attempt-stale"));
            // The fixture has no business-ready socket client, so the exact
            // request remains fail-closed before any send.
            Assert.False(
                harness.Flow.TrySendTrustedResolvedSaveEntry(
                    "cf7_agent_a5_material_shop_run",
                    attemptId));
        }

        [Fact]
        public void Reset_SynchronouslyCancelsWatchdog_AndQueuedCallbackCannotReveal()
        {
            using var harness = new Harness(60000);
            const string attemptId = "attempt-reset";
            harness.ArmReady(attemptId);

            Assert.NotNull(Watchdog(harness.Flow));
            harness.Flow.Reset(null, "reveal_watchdog_test");

            Assert.False(WaitingForFlash(harness.Flow));
            Assert.False(
                harness.Flow.HasAcceptedTitleReceipt(attemptId));
            Assert.Null(Watchdog(harness.Flow));

            InvokePrivate(
                harness.Flow,
                "OnFlashRevealWatchdogFired",
                attemptId);

            Assert.False(WaitingForFlash(harness.Flow));
            Assert.False(RevealPerformed(harness.Flow));
            Assert.Null(Watchdog(harness.Flow));
        }

        [Fact]
        public void RevealNextTick_CommitsOnlyWhenExactQueuedCallbackRuns()
        {
            using var harness = new Harness(60000, true);
            const string attemptId = "attempt-next-tick";
            harness.ArmReady(attemptId);

            harness.SendRevealReady(attemptId);

            Assert.False(RevealPerformed(harness.Flow));
            Assert.True(RevealScheduled(harness.Flow));
            Assert.NotNull(Watchdog(harness.Flow));
            Assert.Equal(1, harness.PendingRevealDispatches);

            harness.RunNextRevealDispatch();

            Assert.True(RevealPerformed(harness.Flow));
            Assert.False(RevealScheduled(harness.Flow));
            Assert.Null(Watchdog(harness.Flow));
        }

        [Fact]
        public void RevealNextTick_StaleAttemptCallbackCannotCommitReplacement()
        {
            using var harness = new Harness(60000, true);
            harness.ArmReady("attempt-old");
            harness.SendRevealReady("attempt-old");
            harness.ArmReady("attempt-new");
            harness.SendRevealReady("attempt-new");

            Assert.Equal(2, harness.PendingRevealDispatches);
            harness.RunNextRevealDispatch();

            Assert.False(RevealPerformed(harness.Flow));
            Assert.True(RevealScheduled(harness.Flow));

            harness.RunNextRevealDispatch();

            Assert.True(RevealPerformed(harness.Flow));
            Assert.False(RevealScheduled(harness.Flow));
            Assert.Null(Watchdog(harness.Flow));
        }

        [Fact]
        public void RevealNextTick_DispatchFailureKeepsWatchdogAndRetries()
        {
            using var harness = new Harness(60000);
            const string attemptId = "attempt-dispatch-retry";
            harness.RejectNextRevealDispatch();
            harness.ArmReady(attemptId);

            harness.SendRevealReady(attemptId);

            Assert.False(RevealPerformed(harness.Flow));
            Assert.False(RevealScheduled(harness.Flow));
            Assert.NotNull(Watchdog(harness.Flow));

            InvokePrivate(
                harness.Flow,
                "OnFlashRevealWatchdogFired",
                attemptId);

            Assert.True(RevealPerformed(harness.Flow));
            Assert.False(RevealScheduled(harness.Flow));
            Assert.Null(Watchdog(harness.Flow));
        }

        [Fact]
        public void RevealNextTick_AcceptedButDroppedCallbackIsRetriedByWatchdog()
        {
            using var harness = new Harness(60000, true);
            const string attemptId = "attempt-accepted-drop";
            harness.ArmReady(attemptId);
            harness.SendRevealReady(attemptId);

            Assert.True(RevealScheduled(harness.Flow));
            Assert.Equal(1, harness.PendingRevealDispatches);

            InvokePrivate(
                harness.Flow,
                "OnFlashRevealWatchdogFired",
                attemptId);

            Assert.True(RevealScheduled(harness.Flow));
            Assert.Equal(2, harness.PendingRevealDispatches);
            harness.RunNextRevealDispatch();
            Assert.False(RevealPerformed(harness.Flow));

            harness.RunNextRevealDispatch();
            Assert.True(RevealPerformed(harness.Flow));
            Assert.False(RevealScheduled(harness.Flow));
            Assert.Null(Watchdog(harness.Flow));
        }

        [Fact]
        public void RevealNextTick_ResetInvalidatesAlreadyQueuedCallback()
        {
            using var harness = new Harness(60000, true);
            const string attemptId = "attempt-reset-next-tick";
            harness.ArmReady(attemptId);
            harness.SendRevealReady(attemptId);
            Assert.True(RevealScheduled(harness.Flow));

            harness.Flow.Reset(null, "reveal_next_tick_reset_test");
            harness.RunNextRevealDispatch();

            Assert.False(RevealPerformed(harness.Flow));
            Assert.False(RevealScheduled(harness.Flow));
            Assert.Null(Watchdog(harness.Flow));
        }

        private static bool WaitingForFlash(GameLaunchFlow flow)
        {
            return GetPrivateField<bool>(flow, "_revealWaitingFlash");
        }

        private static bool RevealPerformed(GameLaunchFlow flow)
        {
            return GetPrivateField<bool>(flow, "_revealPerformed");
        }

        private static bool RevealScheduled(GameLaunchFlow flow)
        {
            return GetPrivateField<bool>(flow, "_revealScheduled");
        }

        private static Timer Watchdog(GameLaunchFlow flow)
        {
            return GetPrivateField<Timer>(flow, "_flashRevealWatchdog");
        }

        private static T GetPrivateField<T>(GameLaunchFlow flow, string name)
        {
            FieldInfo field = typeof(GameLaunchFlow).GetField(
                name,
                BindingFlags.Instance | BindingFlags.NonPublic);
            Assert.NotNull(field);
            return (T)field.GetValue(flow);
        }

        private static void SetPrivateField<T>(
            GameLaunchFlow flow,
            string name,
            T value)
        {
            FieldInfo field = typeof(GameLaunchFlow).GetField(
                name,
                BindingFlags.Instance | BindingFlags.NonPublic);
            Assert.NotNull(field);
            field.SetValue(flow, value);
        }

        private static void InvokePrivate(
            GameLaunchFlow flow,
            string name,
            params object[] arguments)
        {
            MethodInfo method = typeof(GameLaunchFlow).GetMethod(
                name,
                BindingFlags.Instance | BindingFlags.NonPublic);
            Assert.NotNull(method);
            method.Invoke(flow, arguments);
        }

        private sealed class Harness : IDisposable
        {
            private readonly Queue<Action> _revealDispatches =
                new Queue<Action>();
            private readonly bool _deferRevealDispatch;
            private bool _rejectNextRevealDispatch;

            public Harness(int watchdogMs, bool deferRevealDispatch = false)
            {
                _deferRevealDispatch = deferRevealDispatch;
                Router = new MessageRouter();
                Server = new XmlSocketServer(
                    Router,
                    AllowLoopbackXmlSocketPeerAuthority.Instance);
                ProcessManager = new ProcessManager(
                    "unused-flash.exe",
                    "unused.swf");
                Flow = new GameLaunchFlow(
                    Server,
                    Router,
                    ProcessManager,
                    new WindowManager(),
                    null,
                    null,
                    null,
                    null,
                    null,
                    watchdogMs);
                Flow.RevealNextTickDispatcherForTests =
                    DispatchRevealNextTick;
            }

            public MessageRouter Router { get; }
            public XmlSocketServer Server { get; }
            public ProcessManager ProcessManager { get; }
            public GameLaunchFlow Flow { get; }
            public int PendingRevealDispatches
            {
                get { return _revealDispatches.Count; }
            }

            public void RejectNextRevealDispatch()
            {
                _rejectNextRevealDispatch = true;
            }

            public void RunNextRevealDispatch()
            {
                Assert.NotEmpty(_revealDispatches);
                _revealDispatches.Dequeue()();
            }

            public void ArmReady(string attemptId)
            {
                InvokePrivate(Flow, "InvalidateRevealScheduleLocked");
                SetPrivateField(
                    Flow,
                    "_state",
                    GameLaunchFlow.State.WaitingGameReady);
                SetPrivateField(Flow, "_currentAttemptId", attemptId);
                SetPrivateField(Flow, "_pendingSlot", "slot-watchdog-test");
                SetPrivateField(Flow, "_revealWaitingJs", false);
                SetPrivateField(Flow, "_revealWaitingFlash", true);
                SetPrivateField(Flow, "_revealPerformed", false);

                Assert.Null(Send("bootstrap_ready", attemptId));
                Assert.Equal(
                    GameLaunchFlow.State.Ready.ToString(),
                    Flow.CurrentState);
            }

            public void SendRevealReady(string attemptId)
            {
                Assert.Null(Send("bootstrap_reveal_ready", attemptId));
            }

            public void Dispose()
            {
                Timer timer = Watchdog(Flow);
                if (timer != null)
                {
                    SetPrivateField(Flow, "_revealWaitingFlash", false);
                    timer.Dispose();
                    SetPrivateField<Timer>(Flow, "_flashRevealWatchdog", null);
                }
                ProcessManager.Dispose();
                Server.Dispose();
            }

            private bool DispatchRevealNextTick(Action action)
            {
                if (_rejectNextRevealDispatch)
                {
                    _rejectNextRevealDispatch = false;
                    return false;
                }
                if (_deferRevealDispatch)
                {
                    _revealDispatches.Enqueue(action);
                    return true;
                }
                action();
                return true;
            }

            private string Send(string task, string attemptId)
            {
                var message = new JObject
                {
                    ["task"] = task,
                    ["payload"] = new JObject
                    {
                        ["attemptId"] = attemptId,
                    },
                };
                return Router.ProcessMessage(
                    message.ToString(Formatting.None),
                    null);
            }
        }
    }
}
