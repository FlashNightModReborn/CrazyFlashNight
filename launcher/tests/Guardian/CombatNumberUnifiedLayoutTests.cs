using System;
using System.Globalization;
using System.Linq;
using CF7Launcher.Guardian.HitNumbers;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class CombatNumberUnifiedLayoutTests
    {
        private static string Heal(int value, string id = "unit.10.1.heal.0", int x = 512, int y = 360) =>
            $"{value}|{x}|{y}|4194304|||0|0|{id}||1";
        private static string Damage(int n, string id = "enemy", int x = 512, int y = 360) =>
            $"12|{x}|{y}|20480|||0|0|{id}|attack-{n}|1";

        [Theory]
        [InlineData((int)HitNumberDisplayMode.Balanced)]
        [InlineData((int)HitNumberDisplayMode.Detail)]
        [InlineData((int)HitNumberDisplayMode.Classic)]
        [InlineData((int)HitNumberDisplayMode.Total)]
        public void AllKindsSpendOneWorldRowBudgetAndKeepDamageFacts(int modeValue)
        {
            var mode = (HitNumberDisplayMode)modeValue;
            double now = 0;
            var runtime = new HitNumberRuntime(() => now);
            runtime.Configure(new HitNumberRuntimeOptions(mode, 3));
            string damage = string.Join(";", Enumerable.Range(0, 8).Select(i => Damage(i, "enemy-" + i, 180 + i * 90)));
            string healing = string.Join(";", Enumerable.Range(0, 8).Select(i => Heal(5, "unit." + i + ".heal.0", 180 + i * 90)));
            runtime.ProcessFrame("0|0|1", damage + ";" + healing);
            now = .16;
            var frame = runtime.ProcessFrame("", "").Frame;
            Assert.InRange(frame.WorldRows.Count, 1, 3);
            Assert.Contains(frame.Items, i => i.Kind == CombatNumberKind.HealHp);
            Assert.Equal(8, runtime.LedgerSegmentCountForTests);
            Assert.Equal(8, runtime.TotalTargetCountForTests);
            Assert.All(frame.WorldRows.Where(r => r.Kind == CombatNumberKind.HealHp), r =>
            { Assert.Equal(0, r.TotalDamage); Assert.Equal(0, r.HitCount); });
            Assert.All(frame.Items.Where(i => i.Kind == CombatNumberKind.HealHp), i => Assert.Equal(-1, i.SourceSequence));
        }

        [Theory]
        [InlineData((int)HitNumberDisplayMode.Balanced, (int)HitNumberLayoutCandidate.BalancedSummary)]
        [InlineData((int)HitNumberDisplayMode.Detail, (int)HitNumberLayoutCandidate.FixedBurstStack)]
        [InlineData((int)HitNumberDisplayMode.Classic, (int)HitNumberLayoutCandidate.ClassicScatter)]
        [InlineData((int)HitNumberDisplayMode.Total, (int)HitNumberLayoutCandidate.TargetTotal)]
        public void PureHealingUsesSelectedProductionStrategy(int modeValue, int expectedValue)
        {
            var mode = (HitNumberDisplayMode)modeValue;
            var expected = (HitNumberLayoutCandidate)expectedValue;
            double now = 0;
            var runtime = new HitNumberRuntime(() => now);
            runtime.Configure(new HitNumberRuntimeOptions(mode, 24));
            runtime.ProcessFrame("0|0|1", Heal(10)); now = .16;
            var frame = runtime.ProcessFrame("", "").Frame;
            Assert.Equal(expected, frame.Candidate);
            var item = Assert.Single(frame.Items);
            Assert.Equal(CombatNumberKind.HealHp, item.Kind);
            var reference = new HitNumberRuntime(() => now);
            reference.Configure(new HitNumberRuntimeOptions(mode, 24));
            var damageItem = Assert.Single(reference.ProcessFrame("0|0|1", Damage(0)).Frame.Items);
            Assert.Equal(HitNumberPacking.FontSize(damageItem.Packed), HitNumberPacking.FontSize(item.Packed));
            Assert.Equal(damageItem.VisualRole, item.VisualRole);
            Assert.Equal(0, item.HitCount);
            if (mode == HitNumberDisplayMode.Classic)
            {
                Assert.Equal(1.3176f, item.CombinedScale, 4);
                Assert.Equal(4f, item.CombinedBlur);
                now = .15 + HitNumberLayoutEngine.ClassicLifetimeSeconds + .001;
                Assert.True(runtime.ProcessFrame("", "").IsDismiss);
            }
        }

        [Theory]
        [InlineData((int)HitNumberDisplayMode.Detail)]
        [InlineData((int)HitNumberDisplayMode.Classic)]
        public void IndividualModesExposeWindowAmountsWithoutExpandingEveryHealingTick(int modeValue)
        {
            var mode = (HitNumberDisplayMode)modeValue;
            double now = 0;
            var runtime = new HitNumberRuntime(() => now);
            runtime.Configure(new HitNumberRuntimeOptions(mode, 24));
            runtime.ProcessFrame("0|0|1", Heal(10));
            now = .16; runtime.ProcessFrame("", "");
            now = .2; runtime.ProcessFrame("", Heal(20));
            now = .36;
            var frame = runtime.ProcessFrame("", "").Frame;
            Assert.Equal(new[] { 10, 20 }, frame.Items.Select(i => i.Value).OrderBy(v => v));
            Assert.Equal(0, runtime.LedgerSegmentCountForTests);
        }

        [Fact]
        public void TotalProjectsItsOwnContinuousRecoverySumAndSurvivesModeSwitches()
        {
            double now = 0;
            var runtime = new HitNumberRuntime(() => now);
            runtime.ProcessFrame("0|0|1", Heal(10)); now = .16; runtime.ProcessFrame("", "");
            now = .2; runtime.ProcessFrame("", Heal(20)); now = .36; runtime.ProcessFrame("", "");
            var total = runtime.Configure(new HitNumberRuntimeOptions(HitNumberDisplayMode.Total, 24)).Frame;
            Assert.Equal(30, Assert.Single(total.Items).Value);
            Assert.Equal(0, runtime.TotalTargetCountForTests);
            Assert.Equal(20, Assert.Single(runtime.Configure(new HitNumberRuntimeOptions(HitNumberDisplayMode.Balanced, 24)).Frame.Items).Value);
            now = 2; runtime.ProcessFrame("", "");
            now = 3; runtime.ProcessFrame("", Heal(7)); now = 3.16;
            Assert.Equal(7, Assert.Single(runtime.Configure(new HitNumberRuntimeOptions(HitNumberDisplayMode.Total, 24)).Frame.Items).Value);
        }

        [Theory]
        [InlineData((int)HitNumberDisplayMode.Balanced)]
        [InlineData((int)HitNumberDisplayMode.Detail)]
        [InlineData((int)HitNumberDisplayMode.Classic)]
        [InlineData((int)HitNumberDisplayMode.Total)]
        public void DifferentWireTargetKeysStillReserveNonintersectingSemanticRows(int modeValue)
        {
            var mode = (HitNumberDisplayMode)modeValue;
            double now = 0;
            var runtime = new HitNumberRuntime(() => now);
            runtime.Configure(new HitNumberRuntimeOptions(mode, 24));
            runtime.ProcessFrame("0|0|1", Heal(567)); now = .16;
            var frame = runtime.ProcessFrame("", Damage(1)).Frame;
            var heals = frame.Items.Where(i => i.Kind == CombatNumberKind.HealHp).ToArray();
            var damages = frame.Items.Where(i => i.Kind == CombatNumberKind.Damage).ToArray();
            Assert.NotEmpty(heals); Assert.NotEmpty(damages);
            foreach (var heal in heals) foreach (var damage in damages)
                Assert.False(HitNumberLayoutEngine.EstimateItemBounds(heal).IntersectsWith(HitNumberLayoutEngine.EstimateItemBounds(damage)));
            Assert.All(heals, h => Assert.Equal("unit.10.1.heal.0", h.SourceTargetId));
        }

        [Fact]
        public void SpatialPressureKeepsNewestRecoveryInsteadOfLettingOlderRowsOccupyEverySlot()
        {
            var accumulator = new HealNumberAccumulator();
            for (int n = 0; n < 21; n++)
                accumulator.Add(new HealNumberEvent("unit." + n + ".heal.0", 99999999, 512, 300), n * .001);
            accumulator.Advance(.171);
            var frame = HitNumberLayoutEngine.BuildCombatFrame(Array.Empty<HitNumberSegment>(), 0,
                Array.Empty<HitNumberTotalEntry>(), accumulator.Snapshot(.171), HitNumberDisplayMode.Balanced,
                HitNumberCamera.Identity, .171, 24);
            Assert.True(frame.WorldRowOmittedCount > 0);
            Assert.Contains(frame.Items, item => item.SourceTargetId == "unit.20.heal.0");
            Assert.Equal(21, accumulator.VisibleCount);
        }

        [Fact]
        public void PresentationGroupingNeverMergesLifecycleEpochsAndWindowHistoryStaysBounded()
        {
            var accumulator = new HealNumberAccumulator();
            accumulator.Add(new HealNumberEvent("unit.10.1.heal.0", 3, 500, 300), 0);
            accumulator.Add(new HealNumberEvent("unit.10.1.heal.1", 7, 500, 300), 0);
            accumulator.Advance(.16);
            var events = accumulator.Snapshot(.16);
            Assert.Equal(2, events.Count);
            Assert.Equal(events[0].PresentationTargetKey, events[1].PresentationTargetKey);
            Assert.NotEqual(events[0].LifecycleKey, events[1].LifecycleKey);
            for (int n = 0; n < 10000; n++) accumulator.Add(new HealNumberEvent("unit." + n, 1, 500, 300), .2);
            Assert.InRange(accumulator.WindowEventCount, 0, HealNumberAccumulator.MaximumWindowEvents);
            Assert.InRange(accumulator.VisibleCount, 0, HealNumberAccumulator.MaximumTargets);
            accumulator.Advance(5);
            Assert.False(accumulator.HasState);
        }
    }
}
