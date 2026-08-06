using System;
using System.Collections.Generic;
using CF7Launcher.Guardian;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class PanelHostVisualRetireTests
    {
        private sealed class HostHarness : IDisposable
        {
            public readonly Queue<Action> Pumps =
                new Queue<Action>();
            public readonly Queue<Action> ClosedEvents =
                new Queue<Action>();
            public readonly PanelHostController Host;

            public HostHarness()
            {
                Host = new PanelHostController(
                    delegate(Action pump)
                    {
                        Pumps.Enqueue(pump);
                    },
                    delegate(Action fire)
                    {
                        ClosedEvents.Enqueue(fire);
                    });
            }

            public void Pump()
            {
                Action pump = Assert.Single(Pumps);
                Pumps.Clear();
                pump();
            }

            public void FireNextClosedEvent()
            {
                Action fire = Assert.Single(ClosedEvents);
                ClosedEvents.Clear();
                fire();
            }

            public void Dispose()
            {
                Host.Dispose();
            }
        }

        [Fact]
        public void IdleOpenAdmissionRejectsAQueuedOpenThatHasNotYetBecomeActive()
        {
            using (var harness = new HostHarness())
            {
                long admission;
                string activePanel;
                string activeInstance;
                Assert.True(
                    harness.Host
                        .TryCaptureOpenAdmission(
                            out admission,
                            out activePanel,
                            out activeInstance));
                Assert.True(
                    harness.Host.TryOpenPanel(
                        "map",
                        "{}",
                        null,
                        null));

                Assert.False(
                    harness.Host
                        .TryOpenPanelFromAdmission(
                            admission,
                            activePanel,
                            activeInstance,
                            "workbench",
                            "{}",
                            null,
                            null));

                harness.Pump();
                Assert.Equal(
                    "map",
                    harness.Host.ActivePanelName);
            }
        }

        [Fact]
        public void IdleOpenAdmissionRejectsAnInterveningTrackedReservationCycle()
        {
            using (var harness = new HostHarness())
            {
                long admission;
                string activePanel;
                string activeInstance;
                Assert.True(
                    harness.Host
                        .TryCaptureOpenAdmission(
                            out admission,
                            out activePanel,
                            out activeInstance));
                Assert.True(
                    harness.Host.TryOpenTrackedPanel(
                        "loot",
                        "{}",
                        "panel.loot.rejected",
                        delegate { return false; },
                        null));
                harness.Pump();
                Assert.True(
                    harness.Host.IsIdleForTrackedOpen);

                Assert.False(
                    harness.Host
                        .TryOpenPanelFromAdmission(
                            admission,
                            activePanel,
                            activeInstance,
                            "workbench",
                            "{}",
                            null,
                            null));
                Assert.Empty(harness.Pumps);
                Assert.False(
                    harness.Host.IsPanelOpen);
            }
        }

        [Fact]
        public void IdleOpenAdmissionRejectsAnInterveningIdleFenceCycle()
        {
            using (var harness = new HostHarness())
            {
                long admission;
                string activePanel;
                string activeInstance;
                Assert.True(
                    harness.Host
                        .TryCaptureOpenAdmission(
                            out admission,
                            out activePanel,
                            out activeInstance));
                Assert.True(
                    harness.Host.TryAcquireIdleFence(
                        "test.navigation.fence"));
                Assert.True(
                    harness.Host.ReleaseIdleFenceExact(
                        "test.navigation.fence"));

                Assert.False(
                    harness.Host
                        .TryOpenPanelFromAdmission(
                            admission,
                            activePanel,
                            activeInstance,
                            "skills",
                            "{}",
                            null,
                            null));
                Assert.Empty(harness.Pumps);
                Assert.False(
                    harness.Host.IsPanelOpen);
            }
        }

        [Fact]
        public void SameNameReplacementAheadOfExactCloseSurvivesAndReportsStale()
        {
            using (var harness = new HostHarness())
            {
                Assert.True(
                    harness.Host.TryOpenPanel(
                        "workbench",
                        "{\"generation\":\"A\"}",
                        null,
                        null));
                harness.Pump();
                string instanceA =
                    harness.Host.ActivePanelInstanceId;
                bool? closeResult = null;

                Assert.True(
                    harness.Host.TryOpenPanel(
                        "workbench",
                        "{\"generation\":\"B\"}",
                        null,
                        null));
                Assert.True(
                    harness.Host.TryClosePanelExact(
                        "workbench",
                        instanceA,
                        delegate(bool closed)
                        {
                            closeResult = closed;
                        }));

                harness.Pump();

                Assert.False(closeResult);
                Assert.Equal(
                    "workbench",
                    harness.Host.ActivePanelName);
                Assert.NotEqual(
                    instanceA,
                    harness.Host.ActivePanelInstanceId);
                Assert.Empty(harness.ClosedEvents);
            }
        }

        [Fact]
        public void ExactCloseCompletionReceiptRequiresMatchingActiveInstance()
        {
            var logs = new List<string>();
            LogManager.SetSink(logs.Add);
            try
            {
                using (var harness = new HostHarness())
                {
                    Assert.True(
                        harness.Host.TryOpenPanel(
                            "kshop",
                            "{}",
                            null,
                            null));
                    harness.Pump();
                    string activeInstance =
                        harness.Host.ActivePanelInstanceId;

                    Assert.True(
                        harness.Host.TryClosePanelExact(
                            "kshop",
                            "panel.kshop.stale",
                            null));
                    harness.Pump();
                    Assert.Empty(logs.FindAll(line =>
                        line.StartsWith(
                            "event=panel_exact_close_completed",
                            StringComparison.Ordinal)));

                    Assert.True(
                        harness.Host.TryClosePanelExact(
                            "kshop",
                            activeInstance,
                            null));
                    harness.Pump();

                    Assert.Single(logs.FindAll(line =>
                        string.Equals(
                            line,
                            "event=panel_exact_close_completed"
                            + " panel=kshop panelInstanceId="
                            + activeInstance,
                            StringComparison.Ordinal)));
                }
            }
            finally
            {
                LogManager.ResetSink();
            }
        }

        [Fact]
        public void ExactCloseAheadOfSameNameReplacementClosesAThenOpensB()
        {
            using (var harness = new HostHarness())
            {
                Assert.True(
                    harness.Host.TryOpenPanel(
                        "workbench",
                        "{\"generation\":\"A\"}",
                        null,
                        null));
                harness.Pump();
                string instanceA =
                    harness.Host.ActivePanelInstanceId;
                bool? closeResult = null;

                Assert.True(
                    harness.Host.TryClosePanelExact(
                        "workbench",
                        instanceA,
                        delegate(bool closed)
                        {
                            closeResult = closed;
                        }));
                Assert.True(
                    harness.Host.TryOpenPanel(
                        "workbench",
                        "{\"generation\":\"B\"}",
                        null,
                        null));

                harness.Pump();

                Assert.True(closeResult);
                Assert.Equal(
                    "workbench",
                    harness.Host.ActivePanelName);
                Assert.NotEqual(
                    instanceA,
                    harness.Host.ActivePanelInstanceId);
            }
        }

        [Fact]
        public void StaleExactCloseDoesNotDiscardDeferredRebindOrBarrierOpen()
        {
            using (var harness = new HostHarness())
            {
                Assert.True(
                    harness.Host.TryOpenPanel(
                        "workbench",
                        "{\"generation\":\"A\"}",
                        null,
                        null));
                harness.Pump();
                string instanceA =
                    harness.Host.ActivePanelInstanceId;

                harness.Host.SetRebindGate(
                    delegate { return false; });
                Assert.True(
                    harness.Host.TryOpenPanel(
                        "workbench",
                        "{\"generation\":\"B\"}",
                        null,
                        null));
                harness.Pump();

                harness.Host.SetOpenGate(
                    delegate { return false; });
                Assert.True(
                    harness.Host.TryOpenPanel(
                        "map",
                        "{}",
                        null,
                        null));
                harness.Pump();

                bool? closeResult = null;
                Assert.True(
                    harness.Host.TryClosePanelExact(
                        "workbench",
                        "panel.workbench.stale",
                        delegate(bool closed)
                        {
                            closeResult = closed;
                        }));
                harness.Pump();
                Assert.False(closeResult);
                Assert.Equal(
                    instanceA,
                    harness.Host.ActivePanelInstanceId);

                harness.Host.SetRebindGate(
                    delegate { return true; });
                harness.Host.SetOpenGate(
                    delegate { return true; });
                harness.Host.FlushDeferredRebind(
                    "workbench");
                harness.Pump();
                Assert.Equal(
                    "workbench",
                    harness.Host.ActivePanelName);
                Assert.NotEqual(
                    instanceA,
                    harness.Host.ActivePanelInstanceId);

                harness.Host.FlushDeferredBarrierOpen();
                harness.Pump();
                Assert.Equal(
                    "map",
                    harness.Host.ActivePanelName);
            }
        }

        [Fact]
        public void DismissReturnStackFlagIsAppliedOnlyAfterExactMatch()
        {
            using (var staleHarness = new HostHarness())
            {
                Assert.True(
                    staleHarness.Host.TryOpenPanel(
                        "workbench",
                        "{}",
                        "map",
                        "{}"));
                staleHarness.Pump();
                string instance =
                    staleHarness.Host.ActivePanelInstanceId;

                Assert.True(
                    staleHarness.Host.TryClosePanelExact(
                        "workbench",
                        "panel.workbench.stale",
                        true,
                        null));
                staleHarness.Pump();
                Assert.Equal(
                    instance,
                    staleHarness.Host.ActivePanelInstanceId);

                Assert.True(
                    staleHarness.Host.TryClosePanelExact(
                        "workbench",
                        instance,
                        null));
                staleHarness.Pump();
                Assert.Equal(
                    "map",
                    staleHarness.Host.ActivePanelName);
            }

            using (var matchingHarness = new HostHarness())
            {
                Assert.True(
                    matchingHarness.Host.TryOpenPanel(
                        "workbench",
                        "{}",
                        "map",
                        "{}"));
                matchingHarness.Pump();
                string instance =
                    matchingHarness.Host.ActivePanelInstanceId;

                Assert.True(
                    matchingHarness.Host.TryClosePanelExact(
                        "workbench",
                        instance,
                        true,
                        null));
                matchingHarness.Pump();
                Assert.False(
                    matchingHarness.Host.IsPanelOpen);
                Assert.Empty(matchingHarness.Pumps);
            }
        }

        [Fact]
        public void DeferredOpenPreventsFalseIdleRetireProofAndRemainsFlushable()
        {
            using (var harness = new HostHarness())
            {
                harness.Host.SetOpenGate(
                    delegate { return false; });
                Assert.True(
                    harness.Host.TryOpenPanel(
                        "map",
                        "{}",
                        null,
                        null));
                harness.Pump();
                Assert.False(harness.Host.IsPanelOpen);

                var outcomes =
                    new List<PanelHostController
                        .VisualRetireOutcome>();
                Assert.True(
                    harness.Host.TryRetirePanelVisualExact(
                        "workbench",
                        "panel.workbench.stale",
                        outcomes.Add));
                harness.Pump();
                Assert.Equal(
                    new[]
                    {
                        PanelHostController
                            .VisualRetireOutcome
                            .Superseded
                    },
                    outcomes);

                harness.Host.SetOpenGate(
                    delegate { return true; });
                harness.Host.FlushDeferredBarrierOpen();
                harness.Pump();
                Assert.Equal(
                    "map",
                    harness.Host.ActivePanelName);
            }
        }

        [Fact]
        public void DeferredBarrierOpenIsNotTrackedIdleAndRejectsAnIdleFence()
        {
            using (var harness = new HostHarness())
            {
                harness.Host.SetOpenGate(
                    delegate { return false; });
                Assert.True(
                    harness.Host.TryOpenPanel(
                        "map",
                        "{}",
                        null,
                        null));
                harness.Pump();

                Assert.False(
                    harness.Host.IsIdleForTrackedOpen);
                Assert.False(
                    harness.Host.TryAcquireIdleFence(
                        "test.deferred-open.fence"));
                Assert.False(
                    harness.Host.TryOpenTrackedPanel(
                        "loot",
                        "{}",
                        "panel.loot.must-not-bypass-deferred",
                        delegate { return true; },
                        null));
                Assert.Empty(harness.Pumps);

                harness.Host.SetOpenGate(
                    delegate { return true; });
                harness.Host.FlushDeferredBarrierOpen();
                harness.Pump();
                Assert.Equal(
                    "map",
                    harness.Host.ActivePanelName);
            }
        }

        [Fact]
        public void RetireAheadOfNewerOpenCompletesSupersededWithoutClosingReplacement()
        {
            using (var harness = new HostHarness())
            {
                harness.Host.PanelClosed +=
                    delegate { };
                Assert.True(
                    harness.Host.TryOpenPanel(
                        "workbench",
                        "{\"generation\":\"A\"}",
                        null,
                        null));
                harness.Pump();
                string instanceA =
                    harness.Host.ActivePanelInstanceId;
                var outcomes =
                    new List<PanelHostController
                        .VisualRetireOutcome>();

                Assert.True(
                    harness.Host.TryRetirePanelVisualExact(
                        "workbench",
                        instanceA,
                        outcomes.Add));
                Assert.True(
                    harness.Host.TryOpenPanel(
                        "map",
                        "{\"generation\":\"B\"}",
                        null,
                        null));
                harness.Pump();

                Assert.Equal(
                    new[]
                    {
                        PanelHostController
                            .VisualRetireOutcome
                            .Superseded
                    },
                    outcomes);
                Assert.Equal(
                    "map",
                    harness.Host.ActivePanelName);
                Assert.NotEqual(
                    instanceA,
                    harness.Host.ActivePanelInstanceId);
                Assert.Single(harness.ClosedEvents);
                Assert.Empty(harness.Pumps);
            }
        }

        [Fact]
        public void RetireAheadOfBlockedOpenCompletesSupersededAndKeepsIntentFlushable()
        {
            using (var harness = new HostHarness())
            {
                Assert.True(
                    harness.Host.TryOpenPanel(
                        "workbench",
                        "{\"generation\":\"A\"}",
                        null,
                        null));
                harness.Pump();
                string instanceA =
                    harness.Host.ActivePanelInstanceId;
                var outcomes =
                    new List<PanelHostController
                        .VisualRetireOutcome>();
                harness.Host.SetOpenGate(
                    delegate { return false; });

                Assert.True(
                    harness.Host.TryRetirePanelVisualExact(
                        "workbench",
                        instanceA,
                        outcomes.Add));
                Assert.True(
                    harness.Host.TryOpenPanel(
                        "map",
                        "{\"generation\":\"B\"}",
                        null,
                        null));
                harness.Pump();

                Assert.Equal(
                    new[]
                    {
                        PanelHostController
                            .VisualRetireOutcome
                            .Superseded
                    },
                    outcomes);
                Assert.False(
                    harness.Host.IsPanelOpen);
                Assert.False(
                    harness.Host.IsIdleForTrackedOpen);
                Assert.False(
                    harness.Host.TryAcquireIdleFence(
                        "test.retire-ahead.fence"));

                harness.Host.SetOpenGate(
                    delegate { return true; });
                harness.Host.FlushDeferredBarrierOpen();
                harness.Pump();
                Assert.Equal(
                    "map",
                    harness.Host.ActivePanelName);
                Assert.Single(outcomes);
            }
        }

        [Fact]
        public void ActiveNullRetireAheadOfOpenCannotInstallAStuckWaiter()
        {
            using (var harness = new HostHarness())
            {
                bool? staleClose = null;
                var outcomes =
                    new List<PanelHostController
                        .VisualRetireOutcome>();

                Assert.True(
                    harness.Host.TryClosePanelExact(
                        "workbench",
                        "panel.workbench.already-absent",
                        delegate(bool closed)
                        {
                            staleClose = closed;
                        }));
                Assert.True(
                    harness.Host.TryRetirePanelVisualExact(
                        "workbench",
                        "panel.workbench.already-absent",
                        outcomes.Add));
                Assert.True(
                    harness.Host.TryOpenPanel(
                        "map",
                        "{}",
                        null,
                        null));
                harness.Pump();

                Assert.False(staleClose);
                Assert.Equal(
                    new[]
                    {
                        PanelHostController
                            .VisualRetireOutcome
                            .Superseded
                    },
                    outcomes);
                Assert.Equal(
                    "map",
                    harness.Host.ActivePanelName);
                Assert.Empty(harness.Pumps);
            }
        }

        [Fact]
        public void RetireQueuedBehindTrackedOpenReservationRejectsVisualBeforeItAppears()
        {
            using (var harness = new HostHarness())
            {
                PanelHostController.TrackedOpenOutcome?
                    openOutcome = null;
                var retireOutcomes =
                    new List<PanelHostController
                        .VisualRetireOutcome>();

                Assert.True(
                    harness.Host.TryOpenTrackedPanel(
                        "loot",
                        "{}",
                        "panel.loot.reserved",
                        delegate { return true; },
                        delegate(
                            PanelHostController
                                .TrackedOpenOutcome outcome)
                        {
                            openOutcome = outcome;
                        }));
                Assert.True(
                    harness.Host.TryRetirePanelVisualExact(
                        "workbench",
                        "panel.workbench.bound",
                        retireOutcomes.Add));

                harness.Pump();

                Assert.Equal(
                    PanelHostController.TrackedOpenOutcome
                        .PreExecutionRejected,
                    openOutcome);
                Assert.Equal(
                    new[]
                    {
                        PanelHostController
                            .VisualRetireOutcome
                            .VisualAlreadyAbsent
                    },
                    retireOutcomes);
                Assert.False(harness.Host.IsPanelOpen);
                Assert.False(
                    harness.Host.HasTrackedPanelLease);
                Assert.Empty(harness.ClosedEvents);
            }
        }

        [Fact]
        public void MatchingTrackedLeaseRetiresAndReleasesBeforeCompletionDespiteLateEvent()
        {
            using (var harness = new HostHarness())
            {
                int closedEvents = 0;
                harness.Host.PanelClosed +=
                    delegate { closedEvents++; };
                PanelHostController.TrackedOpenOutcome?
                    openOutcome = null;
                var retireOutcomes =
                    new List<PanelHostController
                        .VisualRetireOutcome>();

                Assert.True(
                    harness.Host.TryOpenTrackedPanel(
                        "loot",
                        "{}",
                        "panel.loot.active",
                        delegate { return true; },
                        delegate(
                            PanelHostController
                                .TrackedOpenOutcome outcome)
                        {
                            openOutcome = outcome;
                        }));
                harness.Pump();
                Assert.Equal(
                    PanelHostController.TrackedOpenOutcome
                        .OpenPosted,
                    openOutcome);
                Assert.True(harness.Host.IsPanelOpen);
                Assert.True(
                    harness.Host.HasTrackedPanelLease);

                Assert.True(
                    harness.Host.TryRetirePanelVisualExact(
                        "loot",
                        "panel.loot.active",
                        retireOutcomes.Add));
                harness.Pump();

                Assert.Equal(
                    new[]
                    {
                        PanelHostController
                            .VisualRetireOutcome
                            .RetiredExact
                    },
                    retireOutcomes);
                Assert.False(harness.Host.IsPanelOpen);
                Assert.False(
                    harness.Host.HasTrackedPanelLease);
                Assert.Equal(0, closedEvents);

                harness.FireNextClosedEvent();
                Assert.Equal(1, closedEvents);
                Assert.Single(retireOutcomes);

                Assert.True(
                    harness.Host.TryOpenPanel(
                        "map", "{}", null, null));
                harness.Pump();
                Assert.Equal(
                    "map",
                    harness.Host.ActivePanelName);
            }
        }

        [Fact]
        public void StaleRetireReportsSupersededImmediatelyWithoutInstallingAnIdleWaiter()
        {
            using (var harness = new HostHarness())
            {
                var closed =
                    new List<string>();
                harness.Host.PanelClosed +=
                    delegate(
                        string panel,
                        string instance)
                    {
                        closed.Add(
                            panel + ":" + instance);
                    };
                Assert.True(
                    harness.Host.TryOpenPanel(
                        "workbench",
                        "{}",
                        null,
                        null));
                harness.Pump();
                string staleInstance =
                    harness.Host.ActivePanelInstanceId;

                Assert.True(
                    harness.Host.TryOpenPanel(
                        "map",
                        "{}",
                        null,
                        null));
                harness.Pump();
                string replacementInstance =
                    harness.Host.ActivePanelInstanceId;
                Assert.NotEqual(
                    staleInstance,
                    replacementInstance);
                Assert.Equal(
                    "map",
                    harness.Host.ActivePanelName);

                harness.Host.SetRebindGate(
                    delegate { return false; });
                Assert.True(
                    harness.Host.TryOpenPanel(
                        "map",
                        "{\"generation\":\"B\"}",
                        null,
                        null));
                harness.Pump();
                Assert.Equal(
                    replacementInstance,
                    harness.Host.ActivePanelInstanceId);

                var outcomes =
                    new List<PanelHostController
                        .VisualRetireOutcome>();
                Assert.True(
                    harness.Host.TryRetirePanelVisualExact(
                        "workbench",
                        staleInstance,
                        outcomes.Add));
                harness.Pump();
                Assert.Equal(
                    new[]
                    {
                        PanelHostController
                            .VisualRetireOutcome
                            .Superseded
                    },
                    outcomes);
                Assert.Equal(
                    "map",
                    harness.Host.ActivePanelName);
                Assert.Equal(
                    replacementInstance,
                    harness.Host
                        .ActivePanelInstanceId);

                harness.Host.SetRebindGate(
                    delegate { return true; });
                harness.Host.FlushDeferredRebind(
                    "map");
                harness.Pump();
                Assert.Equal(
                    "map",
                    harness.Host.ActivePanelName);
                Assert.NotEqual(
                    replacementInstance,
                    harness.Host.ActivePanelInstanceId);

                // The stale workbench event can arrive after the replacement is already visible.
                harness.FireNextClosedEvent();
                Assert.Single(closed);
                Assert.Single(outcomes);
                Assert.Equal(
                    "map",
                    harness.Host.ActivePanelName);

                Assert.True(
                    harness.Host.TryOpenPanel(
                        "inventory",
                        "{}",
                        null,
                        null));
                harness.Pump();
                Assert.Equal(
                    "inventory",
                    harness.Host.ActivePanelName);
                Assert.Single(outcomes);

                harness.FireNextClosedEvent();
                Assert.Equal(2, closed.Count);
                Assert.Single(outcomes);
            }
        }

        [Fact]
        public void CharacterRecoveryContinuesOnceFromHostProofNotPanelClosedDelivery()
        {
            var recovery =
                new List<JObject>();
            var generations =
                new List<int>();
            using (var harness = new HostHarness())
            using (var task = new CharacterBuildTask(
                delegate { return true; },
                delegate { return true; },
                5000,
                delegate { return 32; },
                delegate(
                    string payload,
                    int generation)
                {
                    recovery.Add(
                        JObject.Parse(
                            payload.TrimEnd('\0')));
                    generations.Add(generation);
                    return true;
                },
                delegate { return true; }))
            {
                harness.Host.PanelClosed +=
                    delegate { };
                Assert.True(
                    harness.Host.TryOpenTrackedPanel(
                        "loot",
                        "{}",
                        "panel.loot.recovery",
                        delegate { return true; },
                        null));
                harness.Pump();
                Assert.True(
                    harness.Host.HasTrackedPanelLease);

                Assert.True(
                    task.TryBindPanelInstance(
                        "panel.workbench.recovery"));
                Assert.True(
                    task.BeginSocketDetachBarrier(31));
                Assert.Equal(
                    "awaiting_visual_retire",
                    task.DetachRecoveryStatus);
                int continuationCount = 0;
                Assert.True(
                    harness.Host.TryRetirePanelVisualExact(
                        "loot",
                        "panel.loot.recovery",
                        delegate(
                            PanelHostController
                                .VisualRetireOutcome outcome)
                        {
                            Assert.True(
                                outcome
                                    == PanelHostController
                                        .VisualRetireOutcome
                                        .RetiredExact
                                || outcome
                                    == PanelHostController
                                        .VisualRetireOutcome
                                        .VisualAlreadyAbsent);
                            continuationCount++;
                            task
                                .ContinueDetachRecoveryAfterVisualRetired(
                                    32);
                        }));
                Assert.Empty(recovery);
                harness.Pump();

                Assert.Equal(1, continuationCount);
                Assert.Single(recovery);
                Assert.Equal(
                    new[] { 32 },
                    generations);
                Assert.Equal(
                    "in_flight",
                    task.DetachRecoveryStatus);

                harness.FireNextClosedEvent();
                Assert.Equal(1, continuationCount);
                Assert.Single(recovery);
            }
        }
    }
}
