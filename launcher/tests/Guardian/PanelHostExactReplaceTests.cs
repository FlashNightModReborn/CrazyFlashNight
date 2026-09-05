using System;
using System.Collections.Generic;
using System.Reflection;
using CF7Launcher.Guardian;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class PanelHostExactReplaceTests
    {
        private sealed class Harness : IDisposable
        {
            internal readonly Queue<Action> Pumps = new Queue<Action>();
            internal readonly PanelHostController Host;

            internal Harness()
            {
                Host = new PanelHostController(
                    action => Pumps.Enqueue(action),
                    action => action());
            }

            internal void Pump()
            {
                Action action = Assert.Single(Pumps);
                Pumps.Clear();
                action();
            }

            internal string OpenSource()
            {
                Assert.True(Host.TryOpenPanel(
                    "crafting", "{}", null, null));
                Pump();
                return Host.ActivePanelInstanceId;
            }

            public void Dispose()
            {
                Host.Dispose();
            }
        }

        [Fact]
        public void Replace_CommitsCapabilitiesAndTokenBeforePanelChanged()
        {
            using var harness = new Harness();
            string source = harness.OpenSource();
            var order = new List<string>();
            harness.Host.PanelChanged += (panel, instance) =>
            {
                if (panel == "npcshop") order.Add("changed");
            };
            var plan = new PreparedPanelReplace(
                "npcshop",
                "panel.npc.target",
                "{\"mode\":\"runtime\"}",
                () => order.Add("capabilities"),
                () => order.Add("abort"),
                () => order.Add("token_committed"));
            PanelHostController.ExactReplaceOutcome? outcome = null;

            Assert.True(harness.Host.TryReplacePanelExact(
                "crafting",
                source,
                plan,
                () => { order.Add("gate"); return true; },
                value => { outcome = value; order.Add("completed"); }));
            Assert.False(harness.Host.TryClosePanelExact(
                "crafting", source, null));
            harness.Pump();

            Assert.Equal(
                new[]
                {
                    "gate", "capabilities", "token_committed", "changed", "completed"
                },
                order);
            Assert.Equal(
                PanelHostController.ExactReplaceOutcome.TargetCommitted,
                outcome);
            Assert.Equal("npcshop", harness.Host.ActivePanelName);
            Assert.Equal("panel.npc.target", harness.Host.ActivePanelInstanceId);
            Assert.False(plan.CommitCapabilitiesNoFail());
            Assert.False(plan.AbortPrepared());
        }

        [Fact]
        public void Replace_ConsumesMatchingTrackedSourceLeaseWithoutClosingSurface()
        {
            using var harness = new Harness();
            PanelHostController.TrackedOpenOutcome? openOutcome = null;
            Assert.True(harness.Host.TryOpenTrackedPanel(
                "loot",
                "{}",
                "panel.loot.tracked",
                () => true,
                value => openOutcome = value));
            harness.Pump();
            Assert.Equal(
                PanelHostController.TrackedOpenOutcome.OpenPosted,
                openOutcome);
            Assert.True(harness.Host.HasTrackedPanelLease);

            int commits = 0;
            int aborts = 0;
            var plan = new PreparedPanelReplace(
                "workbench",
                "panel.workbench.target",
                "{\"mode\":\"runtime\"}",
                () => commits++,
                () => aborts++);
            PanelHostController.ExactReplaceOutcome? outcome = null;
            Assert.True(harness.Host.TryReplacePanelExact(
                "loot",
                "panel.loot.tracked",
                plan,
                () => true,
                value => outcome = value));
            harness.Pump();

            Assert.Equal(1, commits);
            Assert.Equal(0, aborts);
            Assert.Equal(
                PanelHostController.ExactReplaceOutcome.TargetCommitted,
                outcome);
            Assert.Equal("workbench", harness.Host.ActivePanelName);
            Assert.Equal(
                "panel.workbench.target",
                harness.Host.ActivePanelInstanceId);
            Assert.False(harness.Host.HasTrackedPanelLease);
        }

        [Fact]
        public void ExactClose_TrackedSourceCommitsBeforeCloseAndReleasesLease()
        {
            using var harness = new Harness();
            PanelHostController.TrackedOpenOutcome? opened = null;
            Assert.True(harness.Host.TryOpenTrackedPanel(
                "warlord", "{}", "warlord.stage.old",
                () => true, value => opened = value));
            harness.Pump();
            Assert.Equal(PanelHostController.TrackedOpenOutcome.OpenPosted, opened);
            Assert.True(harness.Host.HasTrackedPanelLease);

            var order = new List<string>();
            bool? closed = null;
            Assert.True(harness.Host.TryClosePanelExact(
                "warlord",
                "warlord.stage.old",
                false,
                () => { order.Add("gate"); return true; },
                () => order.Add("commit"),
                value => closed = value));
            harness.Pump();

            Assert.Equal(new[] { "gate", "commit" }, order);
            Assert.True(closed);
            Assert.False(harness.Host.IsPanelOpen);
            Assert.False(harness.Host.HasTrackedPanelLease);

            PanelHostController.TrackedOpenOutcome? resumed = null;
            Assert.True(harness.Host.TryOpenTrackedPanel(
                "warlord", "{}", "warlord.stage.resume",
                () => true, value => resumed = value));
            harness.Pump();
            Assert.Equal(PanelHostController.TrackedOpenOutcome.OpenPosted, resumed);
        }

        [Fact]
        public void GateRejection_AbortsOnceAndPreservesSource()
        {
            using var harness = new Harness();
            string source = harness.OpenSource();
            int commits = 0;
            int aborts = 0;
            PanelHostController.ExactReplaceOutcome? outcome = null;
            var plan = new PreparedPanelReplace(
                "npcshop", "panel.target", "{}",
                () => commits++, () => aborts++);

            Assert.True(harness.Host.TryReplacePanelExact(
                "crafting", source, plan, () => false,
                value => outcome = value));
            harness.Pump();

            Assert.Equal(0, commits);
            Assert.Equal(1, aborts);
            Assert.Equal(
                PanelHostController.ExactReplaceOutcome.PreExecutionRejected,
                outcome);
            Assert.Equal("crafting", harness.Host.ActivePanelName);
            Assert.Equal(source, harness.Host.ActivePanelInstanceId);
            Assert.False(plan.AbortPrepared());
        }

        [Theory]
        [InlineData(false)]
        [InlineData(true)]
        public void PostFailureOrThrow_AbortsOnceAndPreservesSource(bool throws)
        {
            using var harness = new Harness();
            string source = harness.OpenSource();
            harness.Host.SetExactReplacePosterForTests(_ =>
            {
                if (throws) throw new InvalidOperationException("fixture");
                return false;
            });
            int commits = 0;
            int aborts = 0;
            PanelHostController.ExactReplaceOutcome? outcome = null;
            var plan = new PreparedPanelReplace(
                "npcshop", "panel.target", "{}",
                () => commits++, () => aborts++);

            Assert.True(harness.Host.TryReplacePanelExact(
                "crafting", source, plan, () => true,
                value => outcome = value));
            harness.Pump();

            Assert.Equal(0, commits);
            Assert.Equal(1, aborts);
            Assert.Equal(
                PanelHostController.ExactReplaceOutcome.PostNotDelivered,
                outcome);
            Assert.Equal("crafting", harness.Host.ActivePanelName);
            Assert.Equal(source, harness.Host.ActivePanelInstanceId);
        }

        [Fact]
        public void ImmediateAdmissionFailure_AbortsPreparedPlanExactlyOnce()
        {
            using var harness = new Harness();
            harness.OpenSource();
            int aborts = 0;
            var plan = new PreparedPanelReplace(
                "npcshop", "panel.target", "{}",
                null, () => aborts++);

            Assert.False(harness.Host.TryReplacePanelExact(
                "crafting", "panel.stale", plan, () => true, null));

            Assert.Equal(1, aborts);
            Assert.Empty(harness.Pumps);
        }

        [Fact]
        public void SourceMismatch_AbortsPreparedPlanExactlyOnce()
        {
            using var harness = new Harness();
            string source = harness.OpenSource();
            int commits = 0;
            int aborts = 0;
            PanelHostController.ExactReplaceOutcome? outcome = null;
            var plan = new PreparedPanelReplace(
                "npcshop", "panel.target", "{}",
                () => commits++, () => aborts++);

            Assert.True(harness.Host.TryReplacePanelExact(
                "crafting", source, plan, () => true,
                value => outcome = value));
            SetActivePanelInstanceForRace(
                harness.Host,
                "panel.crafting.superseded");
            harness.Pump();

            Assert.Equal(0, commits);
            Assert.Equal(1, aborts);
            Assert.Equal(
                PanelHostController.ExactReplaceOutcome.SourceMismatch,
                outcome);
            Assert.False(plan.AbortPrepared());
        }

        [Fact]
        public void HostUnavailableAfterAdmission_AbortsPreparedPlanExactlyOnce()
        {
            using var harness = new Harness();
            string source = harness.OpenSource();
            int commits = 0;
            int aborts = 0;
            int completions = 0;
            PanelHostController.ExactReplaceOutcome? outcome = null;
            var plan = new PreparedPanelReplace(
                "npcshop", "panel.target", "{}",
                () => commits++, () => aborts++);

            Assert.True(harness.Host.TryReplacePanelExact(
                "crafting", source, plan, () => true,
                value =>
                {
                    completions++;
                    outcome = value;
                }));
            harness.Host.Dispose();

            Assert.Equal(0, commits);
            Assert.Equal(1, aborts);
            Assert.Equal(1, completions);
            Assert.Equal(
                PanelHostController.ExactReplaceOutcome.HostUnavailable,
                outcome);
            Assert.False(plan.AbortPrepared());
        }

        [Fact]
        public void ExactCloseGateAndCommit_RunBeforeOwnerRetirement()
        {
            using var harness = new Harness();
            string source = harness.OpenSource();
            var order = new List<string>();
            harness.Host.PanelChanged += (panel, _) =>
            {
                if (panel == null) order.Add("changed");
            };

            Assert.True(harness.Host.TryClosePanelExact(
                "crafting",
                source,
                true,
                () => { order.Add("gate"); return true; },
                () => order.Add("commit"),
                closed => order.Add(closed ? "completed" : "failed")));
            harness.Pump();

            Assert.Equal(
                new[] { "gate", "commit", "changed", "completed" },
                order);
            Assert.False(harness.Host.IsPanelOpen);
        }

        private static void SetActivePanelInstanceForRace(
            PanelHostController host,
            string panelInstanceId)
        {
            FieldInfo field = typeof(PanelHostController).GetField(
                "_activePanelInstanceId",
                BindingFlags.Instance | BindingFlags.NonPublic);
            Assert.NotNull(field);
            field.SetValue(host, panelInstanceId);
        }
    }
}
