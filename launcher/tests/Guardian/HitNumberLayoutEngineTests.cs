using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using CF7Launcher.Guardian.HitNumbers;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class HitNumberLayoutEngineTests
    {
        [Fact]
        public void FixedStackKeepsEveryVisibleSegmentInWorldRows()
        {
            List<HitNumberSegment> segments = BuildBurst(120, 512, 400, "boss");

            HitNumberLayoutFrame frame = HitNumberLayoutEngine.BuildFrame(
                segments,
                2.0,
                HitNumberLayoutCandidate.FixedBurstStack);

            Assert.Equal(120, frame.InputActiveSegmentCount);
            Assert.Equal(0, frame.OffscreenCulledSegmentCount);
            Assert.Equal(120, frame.DetailItemCount);
            Assert.Single(frame.WorldRows);
            Assert.Equal(120, UniqueDetailSequences(frame.Items).Count);
        }

        [Fact]
        public void BalancedSummaryProjectsOneCompactTotalWithoutWorldDetailCells()
        {
            List<HitNumberSegment> segments = BuildBurst(120, 512, 400, "boss");

            HitNumberLayoutFrame frame = HitNumberLayoutEngine.BuildFrame(
                segments,
                2.0,
                HitNumberLayoutCandidate.BalancedSummary);

            Assert.Equal(120, frame.InputActiveSegmentCount);
            Assert.Equal(0, frame.DetailItemCount);
            Assert.Equal(1, frame.SummaryItemCount);
            HitNumberBurstRow row = Assert.Single(frame.WorldRows);
            Assert.Equal(148f, row.Bounds.Width);
            Assert.Equal(29f, row.Bounds.Height);
            Assert.Single(frame.Items);
        }

        [Theory]
        [InlineData(0)]
        [InlineData(1)]
        public void OffscreenTargetCullUsesTheSameContractAcrossWorldModes(int candidateValue)
        {
            var candidate = (HitNumberLayoutCandidate)candidateValue;
            List<HitNumberSegment> segments = BuildBurst(10, 512, 400, "visible");
            segments.AddRange(BuildBurst(6, 1300, 400, "offscreen", 100));

            HitNumberLayoutFrame frame = HitNumberLayoutEngine.BuildFrame(
                segments,
                2.0,
                candidate);

            Assert.Equal(16, frame.InputActiveSegmentCount);
            Assert.Equal(6, frame.OffscreenCulledSegmentCount);
            Assert.Single(frame.WorldRows);
        }

        [Fact]
        public void OffscreenCullIncludesTheContractualHundredPixelMargin()
        {
            var segments = new List<HitNumberSegment>();
            segments.AddRange(BuildBurst(1, -100f, 400, "left-edge", 0));
            segments.AddRange(BuildBurst(1, 1124f, 400, "right-edge", 1));
            segments.AddRange(BuildBurst(1, -100.01f, 400, "left-out", 2));
            segments.AddRange(BuildBurst(1, 1124.01f, 400, "right-out", 3));

            HitNumberLayoutFrame frame = HitNumberLayoutEngine.BuildFrame(
                segments,
                2.0,
                HitNumberLayoutCandidate.BalancedSummary);

            Assert.Equal(4, frame.InputActiveSegmentCount);
            Assert.Equal(2, frame.OffscreenCulledSegmentCount);
            Assert.Equal(
                new[] { "left-edge", "right-edge" },
                frame.WorldRows.Select(row => row.TargetId).OrderBy(id => id));
        }

        [Theory]
        [InlineData(0)]
        [InlineData(1)]
        public void LinkedShotVirtualBulletsShareOneAttackRow(int candidateValue)
        {
            var candidate = (HitNumberLayoutCandidate)candidateValue;
            List<HitNumberSegment> segments = BuildBurst(12, 512, 400, "boss");
            foreach (HitNumberSegment segment in segments) segment.BurstId = "linked-shot-1";

            HitNumberLayoutFrame frame = HitNumberLayoutEngine.BuildFrame(
                segments,
                2.0,
                candidate);

            HitNumberBurstRow row = Assert.Single(frame.WorldRows);
            Assert.Equal("linked-shot-1", row.BurstId);
            Assert.Equal(12, row.HitCount);
            Assert.Equal(12, row.Segments.Count);
        }

        [Fact]
        public void BalancedWorldRowsNeverCombineSameBurstIdAcrossTargets()
        {
            List<HitNumberSegment> segments = BuildBurst(8, 470, 390, "left");
            segments.AddRange(BuildBurst(9, 555, 390, "right", 50));

            HitNumberLayoutFrame frame = HitNumberLayoutEngine.BuildFrame(
                segments,
                2.0,
                HitNumberLayoutCandidate.BalancedSummary);

            Assert.Equal(2, frame.WorldRows.Count);
            Assert.Equal(2, frame.WorldRows.Select(row => row.TargetId).Distinct().Count());
        }

        [Theory]
        [InlineData(0)]
        [InlineData(1)]
        public void LayoutIsDeterministic(int candidateValue)
        {
            var candidate = (HitNumberLayoutCandidate)candidateValue;
            List<HitNumberSegment> segments = BuildRepeatedCloseTargetBursts(3.2);

            HitNumberLayoutFrame first = HitNumberLayoutEngine.BuildFrame(segments, 2.5, candidate);
            HitNumberLayoutFrame second = HitNumberLayoutEngine.BuildFrame(segments, 2.5, candidate);

            Assert.Equal(first.Items.Count, second.Items.Count);
            Assert.Equal(first.WorldRows.Count, second.WorldRows.Count);
            for (int i = 0; i < first.Items.Count; i++)
            {
                Assert.Equal(first.Items[i].StageX, second.Items[i].StageX);
                Assert.Equal(first.Items[i].StageY, second.Items[i].StageY);
                Assert.Equal(first.Items[i].SourceSequence, second.Items[i].SourceSequence);
                Assert.Equal(first.Items[i].SourceBurstId, second.Items[i].SourceBurstId);
            }
            for (int i = 0; i < first.WorldRows.Count; i++)
                Assert.Equal(first.WorldRows[i].Bounds, second.WorldRows[i].Bounds);
        }

        [Theory]
        [InlineData(0)]
        [InlineData(1)]
        public void NeighborTopologyCannotSteerExistingTargetStack(int candidateValue)
        {
            var candidate = (HitNumberLayoutCandidate)candidateValue;
            List<HitNumberSegment> left = BuildBurst(6, 438, 390, "left");
            List<HitNumberSegment> crowded = new List<HitNumberSegment>(left);
            crowded.AddRange(BuildBurst(6, 586, 378, "right", 100));

            HitNumberLayoutFrame isolated = HitNumberLayoutEngine.BuildFrame(left, 2.0, candidate);
            HitNumberLayoutFrame withNeighbor = HitNumberLayoutEngine.BuildFrame(crowded, 2.0, candidate);
            HitNumberBurstRow isolatedLeft = Assert.Single(isolated.WorldRows);
            HitNumberBurstRow crowdedLeft = Assert.Single(
                withNeighbor.WorldRows,
                row => row.TargetId == "left");

            Assert.Equal(isolatedLeft.Bounds, crowdedLeft.Bounds);
            Assert.Equal(isolatedLeft.GrowthDirection, crowdedLeft.GrowthDirection);
            Assert.Equal(isolatedLeft.AttachmentX, crowdedLeft.AttachmentX);
        }

        [Theory]
        [InlineData(0)]
        [InlineData(1)]
        public void NewAttackMovesOlderRowOnlyAlongVerticalAxis(int candidateValue)
        {
            var candidate = (HitNumberLayoutCandidate)candidateValue;
            List<HitNumberSegment> oldOnly = BuildBurst(4, 512, 390, "boss");
            foreach (HitNumberSegment segment in oldOnly) segment.BurstId = "old";
            var withNew = new List<HitNumberSegment>(oldOnly);
            List<HitNumberSegment> newer = BuildBurst(3, 512, 390, "boss", 100);
            foreach (HitNumberSegment segment in newer)
            {
                segment.BurstId = "new";
                segment.ArrivalSeconds += 0.35;
            }
            withNew.AddRange(newer);

            HitNumberBurstRow before = Assert.Single(
                HitNumberLayoutEngine.BuildFrame(oldOnly, 2.0, candidate).WorldRows);
            HitNumberBurstRow after = Assert.Single(
                HitNumberLayoutEngine.BuildFrame(withNew, 2.0, candidate).WorldRows,
                row => row.BurstId == "old");

            Assert.Equal(before.Bounds.X, after.Bounds.X);
            Assert.Equal(before.Bounds.Width, after.Bounds.Width);
            Assert.True(after.Bounds.Y < before.Bounds.Y);
        }

        [Theory]
        [InlineData(0)]
        [InlineData(1)]
        public void NewAttackImmediatelyReservesStableNonOverlappingSlot(int candidateValue)
        {
            var candidate = (HitNumberLayoutCandidate)candidateValue;
            List<HitNumberSegment> segments = BuildBurst(4, 512, 390, "boss");
            foreach (HitNumberSegment segment in segments) segment.BurstId = "old";
            List<HitNumberSegment> newer = BuildBurst(3, 512, 390, "boss", 100);
            foreach (HitNumberSegment segment in newer)
            {
                segment.BurstId = "new";
                segment.ArrivalSeconds += 0.60;
            }
            segments.AddRange(newer);

            HitNumberBurstRow early = Assert.Single(
                HitNumberLayoutEngine.BuildFrame(segments, 1.82, candidate).WorldRows,
                row => row.BurstId == "old");
            HitNumberBurstRow settled = Assert.Single(
                HitNumberLayoutEngine.BuildFrame(segments, 1.92, candidate).WorldRows,
                row => row.BurstId == "old");

            Assert.Equal(early.Bounds.X, settled.Bounds.X);
            Assert.Equal(early.Bounds.Width, settled.Bounds.Width);
            Assert.Equal(early.Bounds, settled.Bounds);
        }

        [Fact]
        public void ExpectedHitCountReservesStableWorldRowGeometryDuringBurstArrival()
        {
            List<HitNumberSegment> complete = BuildBurst(4, 438, 390, "left");
            List<HitNumberSegment> partial = complete.Take(2).ToList();

            HitNumberBurstRow partialRow = Assert.Single(
                HitNumberLayoutEngine.BuildFrame(
                    partial,
                    2.0,
                    HitNumberLayoutCandidate.FixedBurstStack).WorldRows);
            HitNumberBurstRow completeRow = Assert.Single(
                HitNumberLayoutEngine.BuildFrame(
                    complete,
                    2.0,
                    HitNumberLayoutCandidate.FixedBurstStack).WorldRows);

            Assert.Equal(4, partialRow.ExpectedHitCount);
            Assert.Equal(partialRow.Bounds, completeRow.Bounds);
        }

        [Theory]
        [InlineData(0)]
        [InlineData(1)]
        public void StructuredTargetAndBurstOwnershipRemainsExact(int candidateValue)
        {
            var candidate = (HitNumberLayoutCandidate)candidateValue;
            HitNumberLayoutFrame frame = HitNumberLayoutEngine.BuildFrame(
                BuildSixTargetCrowd(),
                2.0,
                candidate);

            Assert.Equal(0, frame.CausalOwnershipViolationCount);
        }

        [Theory]
        [InlineData(0)]
        [InlineData(1)]
        public void WorldRowsStayInsideStage(int candidateValue)
        {
            var candidate = (HitNumberLayoutCandidate)candidateValue;
            HitNumberLayoutFrame frame = HitNumberLayoutEngine.BuildFrame(
                BuildSixTargetCrowd(),
                2.0,
                candidate);

            foreach (HitNumberBurstRow row in frame.WorldRows)
            {
                Assert.True(row.Bounds.Left >= 0, $"row {row.BurstId} left={row.Bounds.Left}");
                Assert.True(row.Bounds.Top >= 0, $"row {row.BurstId} top={row.Bounds.Top}");
                Assert.True(row.Bounds.Right <= HitNumberLayoutEngine.StageWidth,
                    $"row {row.BurstId} right={row.Bounds.Right}");
                Assert.True(row.Bounds.Bottom <= HitNumberLayoutEngine.StageHeight,
                    $"row {row.BurstId} bottom={row.Bounds.Bottom}");
            }
        }

        [Fact]
        public void TargetStackOrdersNewestAttackFirstAndKeepsSegmentOrder()
        {
            List<HitNumberSegment> segments = BuildBurst(3, 512, 390, "boss");
            foreach (HitNumberSegment segment in segments) segment.BurstId = "old";
            List<HitNumberSegment> newer = BuildBurst(4, 512, 390, "boss", 100);
            foreach (HitNumberSegment segment in newer)
            {
                segment.BurstId = "new";
                segment.ArrivalSeconds += 0.30;
            }
            segments.AddRange(newer);

            HitNumberLayoutFrame frame = HitNumberLayoutEngine.BuildFrame(
                segments,
                2.0,
                HitNumberLayoutCandidate.BalancedSummary);

            Assert.Equal("new", frame.WorldRows[0].BurstId);
            Assert.Equal("old", frame.WorldRows[1].BurstId);
            Assert.Equal(new[] { 100, 101, 102, 103 },
                frame.WorldRows[0].Segments.Select(segment => segment.Sequence));
        }

        [Fact]
        public void WorldRowRetainsDamageAndAttributePayloadForPainting()
        {
            List<HitNumberSegment> segments = BuildBurst(2, 512, 390, "boss");
            segments[0].Damage = 431;
            segments[0].Packed = HitNumberPacking.Create(8, false, 31, 1);
            segments[0].EffectText = "火";
            segments[1].Damage = 372;
            segments[1].Packed = HitNumberPacking.Create(32, false, 31, 5);
            segments[1].LifeSteal = 96;

            HitNumberLayoutFrame frame = HitNumberLayoutEngine.BuildFrame(
                segments,
                2.0,
                HitNumberLayoutCandidate.BalancedSummary);
            HitNumberBurstRow row = Assert.Single(frame.WorldRows);

            Assert.Equal(431, row.Segments[0].Damage);
            Assert.Equal("火", row.Segments[0].EffectText);
            Assert.Equal(372, row.Segments[1].Damage);
            Assert.Equal(96, row.Segments[1].LifeSteal);
            Assert.Contains("火", row.AttributeSummary);
            Assert.Contains("汲", row.AttributeSummary);
        }

        [Fact]
        public void SingleSegmentWorldRowDoesNotDuplicateItsValueAsSummary()
        {
            HitNumberLayoutFrame frame = HitNumberLayoutEngine.BuildFrame(
                BuildBurst(1, 512, 390, "boss"),
                2.0,
                HitNumberLayoutCandidate.FixedBurstStack);

            Assert.Equal(1, frame.DetailItemCount);
            Assert.Equal(0, frame.SummaryItemCount);
            Assert.Single(frame.Items);
        }

        [Fact]
        public void SummaryTotalSaturatesWithoutOverflowingPainterContract()
        {
            List<HitNumberSegment> segments = BuildBurst(2, 512, 390, "boss");
            segments[0].Damage = int.MaxValue;
            segments[1].Damage = int.MaxValue;

            HitNumberLayoutFrame frame = HitNumberLayoutEngine.BuildFrame(
                segments,
                2.0,
                HitNumberLayoutCandidate.BalancedSummary);
            HitNumberPaintItem summary = Assert.Single(frame.Items);

            Assert.Equal(int.MaxValue, summary.Damage);
            Assert.Equal((long)int.MaxValue * 2L, frame.WorldRows[0].TotalDamage);
        }

        [Fact]
        public void SharedPainterProducesVisiblePixels()
        {
            using var painter = new HitNumberPainter();
            using var bitmap = new Bitmap(512, 288);
            using Graphics graphics = Graphics.FromImage(bitmap);
            graphics.Clear(Color.Transparent);
            var item = new HitNumberPaintItem
            {
                StageX = 512,
                StageY = 288,
                Damage = 12345,
                Packed = HitNumberPacking.Create(8, false, 32, 2),
                EffectText = "雷"
            };

            HitNumberPaintStats stats = painter.Paint(
                graphics,
                new[] { item },
                new HitNumberPaintContext(new RectangleF(0, 0, 512, 288)));

            Assert.Equal(1, stats.ItemCount);
            Assert.True(stats.RunCount >= 2);
            Assert.True(HasVisiblePixel(bitmap));
        }

        [Fact]
        public void ScenePainter_OmitsBalancedArrow_ButKeepsDetailTargetAnchor()
        {
            using var painter = new HitNumberScenePainter();
            using var bitmap = new Bitmap(1024, 576);
            using Graphics graphics = Graphics.FromImage(bitmap);
            graphics.Clear(Color.Transparent);
            var row = new HitNumberBurstRow
            {
                TargetId = "boss",
                TargetX = 512,
                TargetY = 400,
                AttachmentX = 512,
                AttachmentY = 350,
                Bounds = new RectangleF(438, 321, 148, 29),
                LastArrivalSeconds = 2.0,
                Alpha = 1f
            };

            painter.DrawWorldRows(
                graphics,
                new RectangleF(0, 0, 1024, 576),
                new[] { row },
                HitNumberDisplayMode.Balanced);

            Assert.False(HasVisiblePixel(bitmap));

            graphics.Clear(Color.Transparent);
            painter.DrawWorldRows(
                graphics,
                new RectangleF(0, 0, 1024, 576),
                new[] { row },
                HitNumberDisplayMode.Detail);

            Assert.Equal(0, bitmap.GetPixel(438, 321).A);
            Assert.Equal(0, bitmap.GetPixel(585, 321).A);
            Assert.Equal(0, bitmap.GetPixel(438, 349).A);
            Assert.Equal(0, bitmap.GetPixel(585, 349).A);
            Assert.True(HasVisiblePixel(bitmap));
        }

        [Fact]
        public void ClassicScatterIsDeterministicAndPreservesEveryLiveSegment()
        {
            List<HitNumberSegment> segments = BuildBurst(12, 512, 390, "boss");
            for (int i = 0; i < segments.Count; i++)
                segments[i].ArrivalSeconds = 1.72 + i * 0.01;

            HitNumberLayoutFrame first = HitNumberLayoutEngine.BuildFrame(
                segments,
                2.0,
                HitNumberLayoutCandidate.ClassicScatter,
                HitNumberLayoutEngine.ClassicLifetimeSeconds);
            HitNumberLayoutFrame second = HitNumberLayoutEngine.BuildFrame(
                segments,
                2.0,
                HitNumberLayoutCandidate.ClassicScatter,
                HitNumberLayoutEngine.ClassicLifetimeSeconds);

            Assert.Equal(12, first.DetailItemCount);
            Assert.Equal(12, first.Items.Count);
            Assert.Equal(
                first.Items.Select(item => (item.StageX, item.StageY, item.CombinedScale)),
                second.Items.Select(item => (item.StageX, item.StageY, item.CombinedScale)));
            Assert.All(first.Items, item =>
            {
                Assert.Equal(20, HitNumberPacking.FontSize(item.Packed));
                Assert.Equal("999999999", item.FlagScales);
                Assert.Equal(4f / 9f, item.SemanticDensityScale, 4);
            });
        }

        [Fact]
        public void TotalModePreservesLegacyEffectKindsValuesAndIndependentColors()
        {
            var segments = BuildBurst(3, 512, 390, "boss");
            segments[0].Packed = HitNumberPacking.Create(8 | 2 | 32, false, 28, 1);
            segments[0].EffectText = "火";
            segments[0].LifeSteal = 12;
            segments[1].Packed = HitNumberPacking.Create(4 | 256, false, 28, 2);
            segments[1].ShieldAbsorb = 18;
            segments[2].Packed = HitNumberPacking.Create(1 | 16, false, 28, 6);
            segments[2].EffectText = "粉碎";
            var totals = new HitNumberTotalAccumulator();
            totals.AddRange(segments, 0, segments.Count);

            HitNumberLayoutFrame frame = HitNumberLayoutEngine.BuildTotalFrame(
                totals.Snapshot(2.0),
                2.0,
                HitNumberCamera.Identity,
                24);
            HitNumberPaintItem item = Assert.Single(frame.Items);

            Assert.Equal(20, HitNumberPacking.FontSize(item.Packed));
            Assert.Equal(8 | 2 | 32 | 4 | 256 | 1 | 16,
                HitNumberPacking.Flags(item.Packed));
            Assert.Equal(9, item.FlagScales.Length);
            Assert.Contains(item.FlagScales, level => level > '0');
            Assert.Equal(12f, item.LifeSteal);
            Assert.Equal(18f, item.ShieldAbsorb);
            Assert.Equal("火", item.EffectText);
            Assert.Equal("粉碎", item.CrushText);
            Assert.Equal(Color.Red, item.EffectTextColorOverride);
            Assert.Equal(Color.FromArgb(0x00, 0x99, 0xFF), item.MainColorOverride);
        }

        [Theory]
        [InlineData(0)]
        [InlineData(1)]
        [InlineData(2)]
        [InlineData(3)]
        [InlineData(4)]
        [InlineData(5)]
        [InlineData(6)]
        [InlineData(7)]
        [InlineData(8)]
        [InlineData(9)]
        [InlineData(10)]
        public void CanonicalSingleSegmentUsesTheSameSourceColorsAcrossAllModes(
            int colorId)
        {
            HitNumberSegment segment = Segment(1, "canonical-color", 1.0, 420);
            segment.Packed = HitNumberPacking.Create(8, false, 28, colorId);
            segment.EffectText = "属";
            var source = new[] { segment };
            Color expected = HitNumberPainter.ResolveColorId(colorId);

            HitNumberPaintItem balanced = Assert.Single(
                HitNumberLayoutEngine.BuildFrame(
                    source,
                    1.08,
                    HitNumberLayoutCandidate.BalancedSummary).Items);
            HitNumberPaintItem detail = Assert.Single(
                HitNumberLayoutEngine.BuildFrame(
                    source,
                    1.08,
                    HitNumberLayoutCandidate.FixedBurstStack).Items);
            HitNumberPaintItem classic = Assert.Single(
                HitNumberLayoutEngine.BuildFrame(
                    source,
                    1.08,
                    HitNumberLayoutCandidate.ClassicScatter,
                    HitNumberLayoutEngine.ClassicLifetimeSeconds).Items);
            var totals = new HitNumberTotalAccumulator();
            totals.AddRange(source, 0, 1);
            HitNumberPaintItem total = Assert.Single(
                HitNumberLayoutEngine.BuildTotalFrame(
                    totals.Snapshot(1.08),
                    1.08,
                    HitNumberCamera.Identity,
                    24).Items);

            foreach (HitNumberPaintItem item in new[] { balanced, detail, classic, total })
            {
                Assert.Equal(expected.ToArgb(),
                    (item.MainColorOverride ??
                     HitNumberPainter.ResolveMainColor(item.Packed)).ToArgb());
                Assert.Equal(expected.ToArgb(),
                    (item.EffectTextColorOverride ??
                     item.MainColorOverride ??
                     HitNumberPainter.ResolveMainColor(item.Packed)).ToArgb());
            }
        }

        [Fact]
        public void BalancedSummaryPreservesStructuredEffectsValuesAndSourceColors()
        {
            List<HitNumberSegment> segments = BuildBurst(2, 512, 390, "boss");
            const int flags = 1 | 2 | 4 | 8 | 16 | 32 | 128 | 256;
            for (int i = 0; i < segments.Count; i++)
            {
                segments[i].Packed = HitNumberPacking.Create(flags, false, 28, 6);
                segments[i].EffectText = "热";
                segments[i].EffectEmoji = "✦";
            }
            segments[0].LifeSteal = 12;
            segments[1].LifeSteal = 18;
            segments[0].ShieldAbsorb = 20;
            segments[1].ShieldAbsorb = 22;

            HitNumberLayoutFrame frame = HitNumberLayoutEngine.BuildFrame(
                segments,
                1.25,
                HitNumberLayoutCandidate.BalancedSummary);
            HitNumberPaintItem item = Assert.Single(frame.Items);

            Assert.Equal(flags, HitNumberPacking.Flags(item.Packed));
            Assert.Equal("热", item.EffectText);
            Assert.Equal("热", item.CrushText);
            Assert.Equal("✦", item.CrushEmoji);
            Assert.Equal(30f, item.LifeSteal);
            Assert.Equal(42f, item.ShieldAbsorb);
            Assert.Equal("999999099", item.FlagScales);
            Assert.Equal(4f / 9f, item.SemanticDensityScale, 4);
            Assert.Equal(Color.FromArgb(0x00, 0x99, 0xFF), item.MainColorOverride);
            Assert.Equal(Color.FromArgb(0x00, 0x99, 0xFF), item.EffectTextColorOverride);
        }

        [Fact]
        public void BalancedSummaryFlashesLatestColorThenReturnsTowardBurstDominantColor()
        {
            HitNumberSegment dominant = Segment(1, "mixed-color", 1.0, 1000);
            dominant.Packed = HitNumberPacking.Create(0, false, 28, 1);
            HitNumberSegment latest = Segment(2, "mixed-color", 1.3, 100);
            latest.Packed = HitNumberPacking.Create(0, false, 28, 6);
            var source = new[] { dominant, latest };

            HitNumberPaintItem impact = Assert.Single(
                HitNumberLayoutEngine.BuildFrame(
                    source,
                    1.3,
                    HitNumberLayoutCandidate.BalancedSummary).Items);
            HitNumberPaintItem settled = Assert.Single(
                HitNumberLayoutEngine.BuildFrame(
                    source,
                    1.6,
                    HitNumberLayoutCandidate.BalancedSummary).Items);

            Color impactColor = impact.MainColorOverride.GetValueOrDefault();
            Color settledColor = settled.MainColorOverride.GetValueOrDefault();
            Assert.Equal(Color.FromArgb(0x00, 0x99, 0xFF), impactColor);
            Assert.True(settledColor.R > impactColor.R);
            Assert.True(settledColor.B < impactColor.B);
        }

        [Fact]
        public void TotalModeKeepsSourceColorForNonMissZeroDamage()
        {
            HitNumberSegment segment = Segment(1, "zero", 1.0, 0);
            segment.Packed = HitNumberPacking.Create(8, false, 28, 6);
            segment.EffectText = "冰";
            var totals = new HitNumberTotalAccumulator();
            totals.AddRange(new[] { segment }, 0, 1);

            HitNumberPaintItem item = Assert.Single(
                HitNumberLayoutEngine.BuildTotalFrame(
                    totals.Snapshot(2.0),
                    2.0,
                    HitNumberCamera.Identity,
                    24).Items);

            Assert.Equal(Color.FromArgb(0x00, 0x99, 0xFF), item.MainColorOverride);
            Assert.Equal(Color.FromArgb(0x00, 0x99, 0xFF), item.EffectTextColorOverride);
            Assert.Equal("000900000", item.FlagScales);
        }

        [Fact]
        public void BalancedModeKeepsSourceColorForNonMissZeroDamage()
        {
            HitNumberSegment segment = Segment(1, "zero-balanced", 1.0, 0);
            segment.Packed = HitNumberPacking.Create(8 | 256, false, 28, 6);
            segment.EffectText = "冰";
            segment.ShieldAbsorb = 88;

            HitNumberPaintItem item = Assert.Single(
                HitNumberLayoutEngine.BuildFrame(
                    new[] { segment },
                    2.0,
                    HitNumberLayoutCandidate.BalancedSummary).Items);

            Assert.Equal(Color.FromArgb(0x00, 0x99, 0xFF).ToArgb(),
                item.MainColorOverride.GetValueOrDefault().ToArgb());
            Assert.Equal(Color.FromArgb(0x00, 0x99, 0xFF).ToArgb(),
                item.EffectTextColorOverride.GetValueOrDefault().ToArgb());
            Assert.Equal(88f, item.ShieldAbsorb);
            Assert.Equal("000900009", item.FlagScales);
        }

        [Fact]
        public void DetailGridExpandsForLongAttributedNumbersWithoutItemOverlap()
        {
            List<HitNumberSegment> segments = BuildBurst(20, 512, 390, "boss");
            for (int i = 0; i < segments.Count; i++)
            {
                segments[i].Damage = 34031 + i * 137;
                segments[i].Packed = HitNumberPacking.Create(8, false, 28, 6);
                segments[i].EffectText = "热";
            }

            HitNumberLayoutFrame frame = HitNumberLayoutEngine.BuildFrame(
                segments,
                1.5,
                HitNumberLayoutCandidate.FixedBurstStack);

            Assert.Equal(20, frame.DetailItemCount);
            for (int left = 0; left < frame.Items.Count; left++)
            {
                RectangleF a = HitNumberLayoutEngine.EstimateItemBounds(frame.Items[left]);
                for (int right = left + 1; right < frame.Items.Count; right++)
                {
                    RectangleF b = HitNumberLayoutEngine.EstimateItemBounds(frame.Items[right]);
                    Assert.False(a.IntersectsWith(b),
                        $"items {left}/{right} overlap: {a} vs {b}");
                }
            }
        }

        [Fact]
        public void TotalModePaintsNewestTargetLastAndUsesBoundedLegacyPulse()
        {
            var older = Segment(1, "older-burst", 1.0, 100);
            older.TargetId = "older";
            var newer = Segment(2, "newer-burst", 1.1, 120);
            newer.TargetId = "newer";
            var totals = new HitNumberTotalAccumulator();
            totals.AddRange(new[] { older, newer }, 0, 2);

            HitNumberLayoutFrame impact = HitNumberLayoutEngine.BuildTotalFrame(
                totals.Snapshot(1.1),
                1.1,
                HitNumberCamera.Identity,
                24);

            Assert.Equal(new[] { "older", "newer" },
                impact.Items.Select(item => item.SourceTargetId));
            Assert.Equal(1.62f, impact.Items[1].CombinedScale, 3);

            HitNumberLayoutFrame settled = HitNumberLayoutEngine.BuildTotalFrame(
                totals.Snapshot(1.4),
                1.4,
                HitNumberCamera.Identity,
                24);
            Assert.Equal(1f, settled.Items[1].CombinedScale, 3);
        }

        [Theory]
        [InlineData(0)]
        [InlineData(1)]
        public void WorldModesPaintTheMostRecentlyHitTargetLast(int candidateValue)
        {
            var candidate = (HitNumberLayoutCandidate)candidateValue;
            HitNumberSegment firstA = Segment(1, "a-old", 1.0, 100);
            firstA.TargetId = "a";
            HitNumberSegment middleB = Segment(2, "b", 1.1, 110);
            middleB.TargetId = "b";
            HitNumberSegment latestA = Segment(3, "a-new", 1.2, 120);
            latestA.TargetId = "a";

            HitNumberLayoutFrame frame = HitNumberLayoutEngine.BuildFrame(
                new[] { firstA, middleB, latestA },
                1.3,
                candidate);

            Assert.Equal("a", frame.Items[frame.Items.Count - 1].SourceTargetId);
            Assert.Equal(new[] { "b", "a" },
                frame.WorldRows.Select(row => row.TargetId).Distinct());
        }

        [Fact]
        public void BalancedHighRateStreamKeepsOnlyThreeNewestRowsPerTarget()
        {
            var segments = new List<HitNumberSegment>();
            for (int burst = 0; burst < 20; burst++)
            {
                List<HitNumberSegment> group = BuildBurst(
                    3,
                    512,
                    400,
                    "boss",
                    burst * 10);
                foreach (HitNumberSegment segment in group)
                {
                    segment.BurstId = "stream-" + burst;
                    segment.ArrivalSeconds = 1.0 + burst * 0.05 +
                        (segment.Sequence - burst * 10) * 0.003;
                }
                segments.AddRange(group);
            }

            HitNumberLayoutFrame frame = HitNumberLayoutEngine.BuildFrame(
                segments,
                0,
                2.0,
                HitNumberLayoutCandidate.BalancedSummary,
                HitNumberCamera.Identity,
                24,
                HitNumberLayoutEngine.DefaultLifetimeSeconds,
                true);
            List<RectangleF> bounds = frame.WorldRows
                .Select(row => row.Bounds)
                .OrderBy(value => value.Top)
                .ToList();

            Assert.Equal(3, bounds.Count);
            Assert.Equal(
                new[] { "stream-19", "stream-18", "stream-17" },
                frame.WorldRows.Select(row => row.BurstId));
            Assert.Equal(17, frame.WorldRowOmittedCount);
            Assert.All(bounds, value =>
            {
                Assert.True(value.Top >= HitNumberLayoutEngine.StageMarginForTests);
                Assert.True(value.Bottom <= HitNumberLayoutEngine.StageHeight -
                    HitNumberLayoutEngine.StageMarginForTests);
            });
            for (int i = 1; i < bounds.Count; i++)
                Assert.True(bounds[i - 1].Bottom <= bounds[i].Top);
        }

        [Fact]
        public void BalancedPerTargetCapDoesNotStarveAnotherTargetBeforeGlobalLimit()
        {
            var segments = new List<HitNumberSegment>();
            for (int burst = 0; burst < 5; burst++)
            {
                HitNumberSegment segment = Segment(
                    burst,
                    "boss-" + burst,
                    1.20 + burst * 0.10,
                    100 + burst);
                segment.TargetId = "boss";
                segments.Add(segment);
            }
            HitNumberSegment mob = Segment(10, "mob-0", 1.15, 80);
            mob.TargetId = "mob";
            mob.TargetX = 680;
            segments.Insert(0, mob);

            HitNumberLayoutFrame fast = HitNumberLayoutEngine.BuildFrame(
                segments,
                0,
                2.0,
                HitNumberLayoutCandidate.BalancedSummary,
                HitNumberCamera.Identity,
                4,
                HitNumberLayoutEngine.DefaultLifetimeSeconds,
                false);
            HitNumberLayoutFrame reference = HitNumberLayoutEngine.BuildFrame(
                segments,
                0,
                2.0,
                HitNumberLayoutCandidate.BalancedSummary,
                HitNumberCamera.Identity,
                4,
                HitNumberLayoutEngine.DefaultLifetimeSeconds,
                true);

            Assert.Equal(4, reference.WorldRows.Count);
            Assert.Equal(3, reference.WorldRows.Count(row => row.TargetId == "boss"));
            Assert.Single(reference.WorldRows, row => row.TargetId == "mob");
            Assert.Equal(2, reference.WorldRowOmittedCount);
            Assert.Equal(
                reference.WorldRows.Select(row => row.BurstId),
                fast.WorldRows.Select(row => row.BurstId));
            Assert.Equal(reference.WorldRowOmittedCount, fast.WorldRowOmittedCount);
            Assert.Equal(reference.WorldSegmentOmittedCount, fast.WorldSegmentOmittedCount);
        }

        [Fact]
        public void FiniteDetailWorldLimitKeepsNewestAttacksAtomically()
        {
            List<HitNumberSegment> segments = BuildIndependentBursts(30, 3);

            HitNumberLayoutFrame frame = HitNumberLayoutEngine.BuildFrame(
                segments,
                0,
                2.0,
                HitNumberLayoutCandidate.FixedBurstStack,
                HitNumberCamera.Identity,
                24,
                HitNumberLayoutEngine.DefaultLifetimeSeconds,
                true);

            Assert.Equal(6, frame.WorldRows.Count);
            Assert.Equal(24, frame.WorldRowOmittedCount);
            Assert.Equal(72, frame.WorldSegmentOmittedCount);
            Assert.All(frame.WorldRows, row => Assert.Equal(3, row.Segments.Count));
            Assert.Equal(
                Enumerable.Range(24, 6).Select(index => "attack-" + index).OrderBy(id => id),
                frame.WorldRows.Select(row => row.BurstId).OrderBy(id => id));
        }

        [Fact]
        public void FiniteDetailPerTargetCapDoesNotStarveAnotherTarget()
        {
            List<HitNumberSegment> segments = BuildIndependentBursts(12, 1);
            HitNumberSegment other = Segment(100, "other-0", 1.15, 77);
            other.TargetId = "other";
            other.TargetX = 690;
            segments.Insert(0, other);

            HitNumberLayoutFrame fast = HitNumberLayoutEngine.BuildFrame(
                segments, 0, 2.0, HitNumberLayoutCandidate.FixedBurstStack,
                HitNumberCamera.Identity, 24,
                HitNumberLayoutEngine.DefaultLifetimeSeconds, false);
            HitNumberLayoutFrame reference = HitNumberLayoutEngine.BuildFrame(
                segments, 0, 2.0, HitNumberLayoutCandidate.FixedBurstStack,
                HitNumberCamera.Identity, 24,
                HitNumberLayoutEngine.DefaultLifetimeSeconds, true);

            Assert.Equal(7, reference.WorldRows.Count);
            Assert.Equal(6, reference.WorldRows.Count(row => row.TargetId == "boss"));
            Assert.Single(reference.WorldRows, row => row.TargetId == "other");
            Assert.Equal(6, reference.WorldRowOmittedCount);
            Assert.Equal(
                reference.WorldRows.Select(row => (row.TargetId, row.BurstId)),
                fast.WorldRows.Select(row => (row.TargetId, row.BurstId)));
            Assert.Equal(reference.WorldRowOmittedCount, fast.WorldRowOmittedCount);
            Assert.Equal(reference.WorldSegmentOmittedCount, fast.WorldSegmentOmittedCount);
        }

        [Fact]
        public void FiniteDetailCombinesPerTargetAndGlobalOmissionCounts()
        {
            List<HitNumberSegment> segments = BuildIndependentBursts(20, 1);
            for (int i = 0; i < segments.Count; i++)
            {
                segments[i].TargetId = i % 2 == 0 ? "left" : "right";
                segments[i].TargetX = i % 2 == 0 ? 420 : 610;
            }

            HitNumberLayoutFrame fast = HitNumberLayoutEngine.BuildFrame(
                segments, 0, 2.0, HitNumberLayoutCandidate.FixedBurstStack,
                HitNumberCamera.Identity, 8,
                HitNumberLayoutEngine.DefaultLifetimeSeconds, false);
            HitNumberLayoutFrame reference = HitNumberLayoutEngine.BuildFrame(
                segments, 0, 2.0, HitNumberLayoutCandidate.FixedBurstStack,
                HitNumberCamera.Identity, 8,
                HitNumberLayoutEngine.DefaultLifetimeSeconds, true);

            Assert.Equal(8, reference.WorldRows.Count);
            Assert.Equal(12, reference.WorldRowOmittedCount);
            Assert.Equal(12, reference.WorldSegmentOmittedCount);
            Assert.Equal(
                reference.WorldRows.Select(row => (row.TargetId, row.BurstId)),
                fast.WorldRows.Select(row => (row.TargetId, row.BurstId)));
            Assert.Equal(reference.WorldRowOmittedCount, fast.WorldRowOmittedCount);
            Assert.Equal(reference.WorldSegmentOmittedCount, fast.WorldSegmentOmittedCount);
        }

        [Fact]
        public void UnlimitedDetailStillProjectsEveryVisibleAttack()
        {
            HitNumberLayoutFrame frame = HitNumberLayoutEngine.BuildFrame(
                BuildIndependentBursts(30, 1),
                0, 2.0, HitNumberLayoutCandidate.FixedBurstStack,
                HitNumberCamera.Identity, 0,
                HitNumberLayoutEngine.DefaultLifetimeSeconds, true);

            Assert.Equal(30, frame.WorldRows.Count);
            Assert.Equal(0, frame.WorldRowOmittedCount);
            Assert.Equal(0, frame.WorldSegmentOmittedCount);
        }

        [Fact]
        public void LimitedProductionProjectionMatchesFullDiagnosticSelection()
        {
            List<HitNumberSegment> segments = BuildIndependentBursts(50, 3);
            HitNumberLayoutFrame fast = HitNumberLayoutEngine.BuildFrame(
                segments,
                0,
                2.0,
                HitNumberLayoutCandidate.BalancedSummary,
                HitNumberCamera.Identity,
                24,
                HitNumberLayoutEngine.DefaultLifetimeSeconds,
                false);
            HitNumberLayoutFrame reference = HitNumberLayoutEngine.BuildFrame(
                segments,
                0,
                2.0,
                HitNumberLayoutCandidate.BalancedSummary,
                HitNumberCamera.Identity,
                24,
                HitNumberLayoutEngine.DefaultLifetimeSeconds,
                true);

            Assert.Equal(reference.InputActiveSegmentCount, fast.InputActiveSegmentCount);
            Assert.Equal(reference.OffscreenCulledSegmentCount, fast.OffscreenCulledSegmentCount);
            Assert.Equal(reference.WorldRowOmittedCount, fast.WorldRowOmittedCount);
            Assert.Equal(reference.WorldSegmentOmittedCount, fast.WorldSegmentOmittedCount);
            Assert.Equal(
                reference.WorldRows.Select(row => row.BurstId),
                fast.WorldRows.Select(row => row.BurstId));
            Assert.Equal(
                reference.Items.Select(item => item.Damage),
                fast.Items.Select(item => item.Damage));
        }

        [Fact]
        public void LimitedProjectionMatchesFullPathForInterleavedSameFrameBursts()
        {
            var segments = new List<HitNumberSegment>
            {
                Segment(0, "attack-a", 1.00, 100),
                Segment(1, "attack-b", 1.00, 200),
                Segment(2, "attack-b", 1.10, 201),
                Segment(3, "attack-a", 1.10, 101)
            };

            HitNumberLayoutFrame fast = BuildLimitedFrame(segments, false);
            HitNumberLayoutFrame reference = BuildLimitedFrame(segments, true);

            Assert.Equal("attack-a", Assert.Single(reference.WorldRows).BurstId);
            Assert.Equal(
                reference.WorldRows.Select(row => row.BurstId),
                fast.WorldRows.Select(row => row.BurstId));
            Assert.Equal(reference.WorldSegmentOmittedCount, fast.WorldSegmentOmittedCount);
        }

        [Theory]
        [InlineData(23, 23, 0, 24)]
        [InlineData(24, 24, 0, 24)]
        [InlineData(25, 24, 1, 24)]
        [InlineData(30, 30, 0, 0)]
        public void WorldLimitBoundaryCountsAttackRows(
            int attackCount,
            int expectedRows,
            int expectedOmitted,
            int worldRowLimit)
        {
            List<HitNumberSegment> segments = BuildIndependentBursts(attackCount, 1);
            for (int i = 0; i < segments.Count; i++)
                segments[i].TargetId = "target-" + i;
            HitNumberLayoutFrame frame = HitNumberLayoutEngine.BuildFrame(
                segments,
                0,
                2.0,
                HitNumberLayoutCandidate.FixedBurstStack,
                HitNumberCamera.Identity,
                worldRowLimit,
                HitNumberLayoutEngine.DefaultLifetimeSeconds,
                true);

            Assert.Equal(expectedRows, frame.WorldRows.Count);
            Assert.Equal(expectedOmitted, frame.WorldRowOmittedCount);
            Assert.Equal(expectedOmitted, frame.WorldSegmentOmittedCount);
        }

        private static List<HitNumberSegment> BuildBurst(
            int count,
            float x,
            float y,
            string target,
            int sequenceOffset = 0)
        {
            var segments = new List<HitNumberSegment>();
            for (int i = 0; i < count; i++)
            {
                segments.Add(new HitNumberSegment
                {
                    Sequence = sequenceOffset + i,
                    BurstId = "burst",
                    ExpectedBurstHitCount = count,
                    TargetId = target,
                    TargetX = x,
                    TargetY = y,
                    ArrivalSeconds = 1.2 + i * 0.004,
                    Damage = 100 + i,
                    Packed = HitNumberPacking.Create(i % 5 == 0 ? 2 : 0, false, 28, i % 7)
                });
            }
            return segments;
        }

        private static HitNumberSegment Segment(
            int sequence,
            string burstId,
            double arrivalSeconds,
            int damage)
        {
            return new HitNumberSegment
            {
                Sequence = sequence,
                BurstId = burstId,
                ExpectedBurstHitCount = 2,
                TargetId = "boss",
                TargetX = 512,
                TargetY = 400,
                ArrivalSeconds = arrivalSeconds,
                Damage = damage,
                Packed = HitNumberPacking.Create(0, false, 28, 0)
            };
        }

        private static HitNumberLayoutFrame BuildLimitedFrame(
            IReadOnlyList<HitNumberSegment> segments,
            bool includeDiagnostics)
        {
            return HitNumberLayoutEngine.BuildFrame(
                segments,
                0,
                2.0,
                HitNumberLayoutCandidate.BalancedSummary,
                HitNumberCamera.Identity,
                1,
                HitNumberLayoutEngine.DefaultLifetimeSeconds,
                includeDiagnostics);
        }

        private static List<HitNumberSegment> BuildIndependentBursts(
            int attackCount,
            int segmentsPerAttack)
        {
            var segments = new List<HitNumberSegment>(attackCount * segmentsPerAttack);
            int sequence = 0;
            for (int attack = 0; attack < attackCount; attack++)
            {
                for (int hit = 0; hit < segmentsPerAttack; hit++)
                {
                    segments.Add(new HitNumberSegment
                    {
                        Sequence = sequence++,
                        BurstId = "attack-" + attack,
                        ExpectedBurstHitCount = segmentsPerAttack,
                        TargetId = "boss",
                        TargetX = 512,
                        TargetY = 400,
                        ArrivalSeconds = 1.12 + attack * 0.018 + hit * 0.001,
                        Damage = 100 + attack * 3 + hit,
                        Packed = HitNumberPacking.Create(attack % 5 == 0 ? 2 : 0, false, 28, attack % 7)
                    });
                }
            }
            return segments;
        }

        private static List<HitNumberSegment> BuildSixTargetCrowd()
        {
            var segments = new List<HitNumberSegment>();
            for (int target = 0; target < 6; target++)
            {
                float x = 270 + (target % 3) * 240;
                float y = 330 + (target / 3) * 125;
                List<HitNumberSegment> burst = BuildBurst(
                    6,
                    x,
                    y,
                    "mob-" + target,
                    target * 20);
                foreach (HitNumberSegment segment in burst)
                {
                    segment.BurstId = "mob-" + target;
                    segment.ArrivalSeconds = 1.58 + target * 0.02 +
                        (segment.Sequence - target * 20) * 0.016;
                }
                segments.AddRange(burst);
            }
            return segments;
        }

        private static List<HitNumberSegment> BuildRepeatedCloseTargetBursts(double durationSeconds)
        {
            var segments = new List<HitNumberSegment>();
            int cycle = 0;
            for (double start = 0.18; start < durationSeconds; start += 0.82)
            {
                int sequenceOffset = cycle * 100;
                AddTypedBurst(segments, 6, "left-primary-" + cycle, "left",
                    438, 390, start, 118 + cycle * 3, 17, 1, sequenceOffset);
                AddTypedBurst(segments, 4, "right-proc-" + cycle, "right",
                    586, 378, start + 0.14, 72 + cycle * 2, 9, 6, sequenceOffset + 20);
                AddTypedBurst(segments, 5, "right-primary-" + cycle, "right",
                    586, 378, start + 0.29, 164 + cycle * 4, 21, 2, sequenceOffset + 40);
                AddTypedBurst(segments, 4, "left-proc-" + cycle, "left",
                    438, 390, start + 0.44, 84 + cycle * 3, 11, 5, sequenceOffset + 60);
                cycle++;
            }
            return segments;
        }

        private static void AddTypedBurst(
            List<HitNumberSegment> destination,
            int count,
            string burstId,
            string targetId,
            float x,
            float y,
            double firstArrival,
            int baseDamage,
            int spread,
            int colorId,
            int sequenceOffset)
        {
            for (int i = 0; i < count; i++)
            {
                destination.Add(new HitNumberSegment
                {
                    Sequence = sequenceOffset + i,
                    BurstId = burstId,
                    ExpectedBurstHitCount = count,
                    TargetId = targetId,
                    TargetX = x,
                    TargetY = y,
                    ArrivalSeconds = firstArrival + i * 0.012,
                    Damage = baseDamage + ((i * 13) % Math.Max(1, spread)),
                    Packed = HitNumberPacking.Create(8, false, 27 + (i == 0 ? 5 : 0), colorId)
                });
            }
        }

        private static HashSet<int> UniqueDetailSequences(IReadOnlyList<HitNumberPaintItem> items)
        {
            var sequences = new HashSet<int>();
            for (int i = 0; i < items.Count; i++)
            {
                if (items[i].VisualRole == HitNumberVisualRole.Detail)
                    sequences.Add(items[i].SourceSequence);
            }
            return sequences;
        }

        private static bool HasVisiblePixel(Bitmap bitmap)
        {
            for (int y = 0; y < bitmap.Height; y += 2)
            {
                for (int x = 0; x < bitmap.Width; x += 2)
                {
                    if (bitmap.GetPixel(x, y).A != 0) return true;
                }
            }
            return false;
        }
    }
}
