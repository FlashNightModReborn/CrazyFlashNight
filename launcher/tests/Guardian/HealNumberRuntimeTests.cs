using System;
using System.Collections.Generic;
using System.Drawing;
using System.Globalization;
using System.Linq;
using CF7Launcher.Guardian.HitNumbers;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class HealNumberRuntimeTests
    {
        private static string Heal(string amount, string id = "unit.1.heal.0") =>
            amount + "|512|360|4194304|||0|0|" + id + "||1";
        private static string Damage(string burst, int packed = 28672) =>
            "12|512|360|" + packed.ToString(CultureInfo.InvariantCulture) + "|||0|0|enemy|" + burst + "|1";

        [Fact]
        public void ParserSeparatesOldHighBitDamageAndFractionalHealWithoutSharingSequence()
        {
            var parser = new HitNumberBatchParser();
            var damages = new List<HitNumberSegment>(); var heals = new List<HealNumberEvent>();
            int sequence = 7;
            int accepted = parser.ParseBatch(Damage("old", 8230912) + ";" + Heal("0.4") + ";" + Damage("new"),
                0, damages, ref sequence, heals);
            Assert.Equal(2, accepted); Assert.Equal(9, sequence);
            Assert.Equal(8230912, damages[0].Packed);
            Assert.Equal(new[] { 7, 8 }, damages.Select(s => s.Sequence));
            Assert.Equal(0.4, Assert.Single(heals).Amount);
            Assert.Equal(0, parser.RejectedEntryCount);
        }

        [Theory]
        [InlineData("NaN|512|360|4194304|||0|0|u||1")]
        [InlineData("-1|512|360|4194304|||0|0|u||1")]
        [InlineData("1|512|360|12582912|||0|0|u||1")]
        [InlineData("1|512|360|4194304.5|||0|0|u||1")]
        [InlineData("1|512|360|4194304|fire||0|0|u||1")]
        [InlineData("1|512|360|4194304|||1|0|u||1")]
        [InlineData("1|512|360|4194304|||0|0|u||2")]
        [InlineData("1|512|360|4194304|||0|0|||1")]
        public void MalformedHealCannotEnterEitherPipeline(string wire)
        {
            var parser = new HitNumberBatchParser();
            var damages = new List<HitNumberSegment>(); var heals = new List<HealNumberEvent>(); int seq = 3;
            Assert.Equal(0, parser.ParseBatch(wire, 0, damages, ref seq, heals));
            Assert.Empty(damages); Assert.Empty(heals); Assert.Equal(3, seq);
            Assert.Equal(1, parser.RejectedEntryCount);
        }

        [Theory]
        [InlineData(1)]
        [InlineData(2)]
        [InlineData(3)]
        [InlineData(4)]
        public void HealOnlyFramesRenderInEveryModeWithoutDamageStatistics(int mode)
        {
            double now = 0; var runtime = new HitNumberRuntime(() => now);
            runtime.Configure(new HitNumberRuntimeOptions((HitNumberDisplayMode)mode, 24));
            Assert.Null(runtime.ProcessFrame("0|0|1", Heal("0.8")));
            now = 0.14; runtime.ProcessFrame("", Heal("0.8"));
            now = 0.151; var snapshot = runtime.ProcessFrame("", "");
            var item = Assert.Single(snapshot.Frame.Items);
            Assert.Equal(CombatNumberKind.HealHp, item.Kind); Assert.Equal(1, item.Value);
            Assert.Empty(snapshot.Frame.WorldRows);
            Assert.Equal(0, runtime.LedgerSegmentCountForTests);
            Assert.Equal(0, runtime.TotalTargetCountForTests);
            Assert.False(HitNumberRenderPlanner.Plan(snapshot.Frame, 1024, 576).IsEmpty);
            now = 1.4; Assert.True(runtime.ProcessFrame("", "").IsDismiss);
        }

        [Theory]
        [InlineData(1)]
        [InlineData(2)]
        [InlineData(3)]
        [InlineData(4)]
        public void MixedHealsKeepDamagePositionsAndLedgerIdenticalInEveryMode(int mode)
        {
            double now = 0;
            var baseline = new HitNumberRuntime(() => now); var mixed = new HitNumberRuntime(() => now);
            foreach (var r in new[] { baseline, mixed }) r.Configure(new HitNumberRuntimeOptions((HitNumberDisplayMode)mode, 24));
            baseline.ProcessFrame("0|0|1", Damage("a"));
            mixed.ProcessFrame("0|0|1", Heal("3") + ";" + Damage("a"));
            now = 0.16;
            var expected = baseline.ProcessFrame("", Damage("b")).Frame.Items;
            var actual = mixed.ProcessFrame("", Damage("b") + ";" + Heal("4")).Frame.Items
                .Where(i => i.Kind == CombatNumberKind.Damage).ToList();
            Assert.Equal(expected.Count, actual.Count);
            for (int i = 0; i < expected.Count; i++)
            {
                Assert.Equal(expected[i].SourceSequence, actual[i].SourceSequence);
                Assert.Equal(expected[i].StageX, actual[i].StageX);
                Assert.Equal(expected[i].StageY, actual[i].StageY);
            }
            Assert.Equal(2, mixed.LedgerSegmentCountForTests);
            Assert.Equal(baseline.BuildLedgerPage(0, 10).ToString(), mixed.BuildLedgerPage(0, 10).ToString());
        }

        [Fact]
        public void EpochAndResetBoundariesDoNotMergeOrResurrectPendingHeals()
        {
            double now = 0; var runtime = new HitNumberRuntime(() => now);
            runtime.ProcessFrame("0|0|1", Heal("2", "u.heal.0") + ";" + Heal("3", "u.heal.1"));
            now = 0.16;
            Assert.Equal(new[] { 2, 3 }, runtime.ProcessFrame("", "").Frame.Items.Select(i => i.Value));
            runtime.ProcessFrame("", Heal("10")); runtime.Reset(); now = 1;
            Assert.Null(runtime.ProcessFrame("", ""));
            runtime.ProcessFrame("", Heal("11"));
            runtime.Configure(new HitNumberRuntimeOptions(HitNumberDisplayMode.Off, 24));
            now = 2; runtime.Configure(new HitNumberRuntimeOptions(HitNumberDisplayMode.Total, 24));
            Assert.Null(runtime.ProcessFrame("", ""));
            Assert.Equal(0, runtime.PendingHealCountForTests); Assert.Equal(0, runtime.VisibleHealCountForTests);
        }

        [Fact]
        public void ConnectionResetClearsHealingWithoutResettingDamageAccounting()
        {
            double now = 0; var runtime = new HitNumberRuntime(() => now);
            runtime.Configure(new HitNumberRuntimeOptions(HitNumberDisplayMode.Total, 24));
            runtime.ProcessFrame("0|0|1", Damage("a") + ";" + Heal("10"));
            Assert.True(runtime.ResetHealing().IsReset);
            now = 0.2;
            var frame = runtime.ProcessFrame("", "").Frame;
            Assert.Single(frame.WorldRows);
            Assert.DoesNotContain(frame.Items, i => i.Kind == CombatNumberKind.HealHp);
            Assert.Equal(1, runtime.LedgerSegmentCountForTests);
            Assert.Equal(1, runtime.TotalTargetCountForTests);
            Assert.Equal(0, runtime.PendingHealCountForTests);
        }

        [Fact]
        public void HighFrequencySubUnitHealsHaveFixedDeadlinesAndBoundedState()
        {
            var accumulator = new HealNumberAccumulator();
            for (int i = 0; i < 100; i++) accumulator.Add(new HealNumberEvent("u", 0.001, 512, 360), i * 0.001);
            accumulator.Advance(0.151);
            var frame = new HitNumberLayoutFrame(); accumulator.AppendFrame(frame, HitNumberCamera.Identity, 0.151, 24);
            Assert.Empty(frame.Items);
            accumulator.Add(new HealNumberEvent("u", 0.9, 512, 360), 0.2);
            accumulator.Advance(0.36);
            frame = new HitNumberLayoutFrame(); accumulator.AppendFrame(frame, HitNumberCamera.Identity, 0.36, 24);
            Assert.Equal(1, Assert.Single(frame.Items).Value);
            for (int i = 0; i < 2000; i++) accumulator.Add(new HealNumberEvent("u" + i, 1, 512, 360), 1);
            Assert.InRange(accumulator.PendingCount, 0, HealNumberAccumulator.MaximumTargets);
            Assert.InRange(accumulator.VisibleCount, 0, HealNumberAccumulator.MaximumTargets);
            accumulator.Advance(3); Assert.False(accumulator.HasState);
        }

        [Theory]
        [InlineData("353.056", 353)]
        [InlineData("2836.528", 2836)]
        [InlineData("1e100", int.MaxValue)]
        public void HealingUsesTheSameClampedIntegerPaintValueAsDamage(string raw, int expected)
        {
            double now = 0; var runtime = new HitNumberRuntime(() => now);
            runtime.ProcessFrame("0|0|1", Heal(raw)); now = 0.16;
            var item = Assert.Single(runtime.ProcessFrame("", "").Frame.Items);
            Assert.Equal(expected, item.Value);
            Assert.Equal("+" + expected.ToString(CultureInfo.InvariantCulture), CombatNumberValue.Format(item.Value, true));
            Assert.Equal(0, runtime.LedgerSegmentCountForTests);
        }

        [Fact]
        public void FractionalWindowsCarryUntilOneAndDoNotCreatePhantomCappedHeals()
        {
            var accumulator = new HealNumberAccumulator();
            for (int i = 0; i < 3; i++)
            {
                accumulator.Add(new HealNumberEvent("u", 0.4, 512, 360), i * 0.2);
                accumulator.Advance(i * 0.2 + 0.16);
                var frame = new HitNumberLayoutFrame();
                accumulator.AppendFrame(frame, HitNumberCamera.Identity, i * 0.2 + 0.16, 24);
                if (i < 2) Assert.Empty(frame.Items);
                else Assert.Equal(1, Assert.Single(frame.Items).Value);
            }
            accumulator.Clear();
            accumulator.Add(new HealNumberEvent("u", 1e100, 512, 360), 0);
            accumulator.Advance(0.16); accumulator.Advance(3);
            Assert.False(accumulator.HasState);
        }

        [Fact]
        public void ContinuousWindowsKeepEntranceMotionAndFollowEveryInputFrame()
        {
            var accumulator = new HealNumberAccumulator();
            accumulator.Add(new HealNumberEvent("u", 10, 512, 360), 0);
            accumulator.Advance(0.16);
            // 第二个窗口尚未发布时，锚点就必须跟随新坐标。
            accumulator.Add(new HealNumberEvent("u", 10, 518, 360), 0.2);
            var moving = new HitNumberLayoutFrame();
            accumulator.AppendFrame(moving, HitNumberCamera.Identity, 0.2, 24);
            Assert.Equal(518, Assert.Single(moving.Items).SourceTargetX);
            accumulator.Advance(0.36);
            var after = new HitNumberLayoutFrame();
            accumulator.AppendFrame(after, HitNumberCamera.Identity, 0.36, 24);
            var item = Assert.Single(after.Items);
            Assert.Equal(HitNumberLayoutEngine.ImpactScale(0.36 - 0.15), item.CombinedScale, 4);
            Assert.Equal(360 + 8 + HitNumberLayoutEngine.ImpactLift(0.36 - 0.15), item.StageY, 4);
            Assert.True(item.CombinedScale < 1.01); // 没有重放1.46倍的入场峰值。
        }

        [Fact]
        public void RefreshDuringFadeRecoversOpacityWithoutAnInstantJumpOrVerticalRewind()
        {
            var accumulator = new HealNumberAccumulator();
            accumulator.Add(new HealNumberEvent("u", 10, 512, 360), 0);
            accumulator.Advance(0.16);
            accumulator.Add(new HealNumberEvent("u", 10, 512, 360), 0.98);
            var before = new HitNumberLayoutFrame();
            accumulator.AppendFrame(before, HitNumberCamera.Identity, 1.13, 24);
            accumulator.Advance(1.13);
            var refreshed = new HitNumberLayoutFrame();
            accumulator.AppendFrame(refreshed, HitNumberCamera.Identity, 1.13, 24);
            Assert.Equal(Assert.Single(before.Items).Alpha, Assert.Single(refreshed.Items).Alpha, 4);
            Assert.Equal(before.Items[0].StageY, refreshed.Items[0].StageY);
            var recovered = new HitNumberLayoutFrame();
            accumulator.AppendFrame(recovered, HitNumberCamera.Identity, 1.22, 24);
            Assert.Equal(1f, Assert.Single(recovered.Items).Alpha);
        }

        [Fact]
        public void DelayedWindowDoesNotResurrectAndNewCycleGetsItsOwnEntrance()
        {
            var accumulator = new HealNumberAccumulator();
            accumulator.Add(new HealNumberEvent("u", 10, 512, 360), 0);
            accumulator.Advance(3);
            Assert.False(accumulator.HasState);
            accumulator.Add(new HealNumberEvent("u", 10, 512, 360), 3);
            accumulator.Advance(3.16);
            var frame = new HitNumberLayoutFrame();
            accumulator.AppendFrame(frame, HitNumberCamera.Identity, 3.16, 24);
            Assert.True(Assert.Single(frame.Items).CombinedScale > 1.3f);
        }

        [Theory]
        [InlineData((int)HitNumberDisplayMode.Balanced)]
        [InlineData((int)HitNumberDisplayMode.Total)]
        public void FreshDamageAndContinuousHealingDoNotPaintOverEachOther(int mode)
        {
            double now = 0;
            var runtime = new HitNumberRuntime(() => now);
            runtime.Configure(new HitNumberRuntimeOptions((HitNumberDisplayMode)mode, 24));
            using var painter = new HitNumberPainter();
            using var healing = new Bitmap(1024, 576);
            using var damage = new Bitmap(1024, 576);
            using var healingGraphics = Graphics.FromImage(healing);
            using var damageGraphics = Graphics.FromImage(damage);
            var context = new HitNumberPaintContext(new RectangleF(0, 0, 1024, 576));
            for (int i = 0; i <= 30; i++)
            {
                now = i / 30.0;
                string wire = Heal("567.3056");
                if (i % 9 == 0) wire += ";2836|512|360|28672|||0|0|enemy|attack-" + i + "|1";
                var frame = runtime.ProcessFrame("0|0|1", wire)?.Frame;
                if (frame == null || !frame.Items.Any(x => x.Kind == CombatNumberKind.HealHp)) continue;
                // 核对新攻击入场峰值及其下一帧，不只检查静止的中间帧。
                if (i % 9 > 1) continue;
                healingGraphics.Clear(Color.Transparent); damageGraphics.Clear(Color.Transparent);
                painter.Paint(healingGraphics, frame.Items.Where(x => x.Kind == CombatNumberKind.HealHp).ToList(), context);
                painter.Paint(damageGraphics, frame.Items.Where(x => x.Kind == CombatNumberKind.Damage).ToList(), context);
                for (int y = 200; y < 450; y++) for (int x = 400; x < 700; x++)
                    Assert.False(healing.GetPixel(x,y).A > 0 && damage.GetPixel(x,y).A > 0,
                        "Healing intersects fresh damage at frame " + i);
            }
        }

        [Fact]
        public void OffscreenTargetsDoNotSpendVisibleLimitAndEdgeTextFitsStage()
        {
            var accumulator = new HealNumberAccumulator();
            accumulator.Add(new HealNumberEvent("z-visible", 1e100, 1010, 570), 0);
            // 同一窗口内排序靠前的屏外目标不能挤掉可见目标。
            for (int i = 0; i < 30; i++)
                accumulator.Add(new HealNumberEvent("a-off-" + i, 1, 2000, 360), 0);
            accumulator.Advance(0.16);
            var frame = new HitNumberLayoutFrame();
            accumulator.AppendFrame(frame, HitNumberCamera.Identity, 0.16, 1);
            var item = Assert.Single(frame.Items);
            Assert.Equal("z-visible", item.SourceTargetId);
            var bounds = HitNumberLayoutEngine.EstimateItemBounds(item);
            Assert.True(bounds.Left >= 3.99 && bounds.Right <= 1020.01);
            Assert.True(bounds.Top >= 3.99 && bounds.Bottom <= 572.01);
        }

        [Theory]
        [InlineData(1.4)]
        [InlineData(1e100)]
        [InlineData(353.056)]
        public void IntegerHealingAndTightSurfaceStayNonzeroAndUnclipped(double amount)
        {
            var accumulator = new HealNumberAccumulator();
            accumulator.Add(new HealNumberEvent("u", amount, 512, 360), 0); accumulator.Advance(0.16);
            var frame = new HitNumberLayoutFrame(); accumulator.AppendFrame(frame, HitNumberCamera.Identity, 0.16, 24);
            Assert.True(Assert.Single(frame.Items).Value > 0);
            var region = HitNumberRenderPlanner.Plan(frame, 1024, 576);
            using var bitmap = new Bitmap(region.PixelBounds.Width, region.PixelBounds.Height);
            using var graphics = Graphics.FromImage(bitmap); using var painter = new HitNumberPainter();
            painter.Paint(graphics, frame.Items, new HitNumberPaintContext(region.LocalViewport));
            int ink = 0, edge = 0;
            for (int y = 0; y < bitmap.Height; y++) for (int x = 0; x < bitmap.Width; x++)
            {
                if (bitmap.GetPixel(x, y).A == 0) continue;
                ink++;
                if (x == 0 || y == 0 || x == bitmap.Width - 1 || y == bitmap.Height - 1) edge++;
            }
            Assert.True(ink > 0); Assert.Equal(0, edge);
        }
    }
}
