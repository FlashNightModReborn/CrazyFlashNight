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
        public void StaleRetireNeverClosesReplacementAndCompletesOnlyAfterHostBecomesIdle()
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

                var outcomes =
                    new List<PanelHostController
                        .VisualRetireOutcome>();
                Assert.True(
                    harness.Host.TryRetirePanelVisualExact(
                        "workbench",
                        staleInstance,
                        outcomes.Add));
                harness.Pump();
                Assert.Empty(outcomes);
                Assert.Equal(
                    "map",
                    harness.Host.ActivePanelName);
                Assert.Equal(
                    replacementInstance,
                    harness.Host
                        .ActivePanelInstanceId);

                // The stale workbench event can arrive after the replacement is already visible.
                harness.FireNextClosedEvent();
                Assert.Single(closed);
                Assert.Empty(outcomes);
                Assert.Equal(
                    "map",
                    harness.Host.ActivePanelName);

                Assert.True(
                    harness.Host.TryClosePanelExact(
                        "map",
                        replacementInstance,
                        null));
                harness.Pump();
                Assert.Equal(
                    new[]
                    {
                        PanelHostController
                            .VisualRetireOutcome
                            .VisualAlreadyAbsent
                    },
                    outcomes);
                Assert.False(harness.Host.IsPanelOpen);

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
