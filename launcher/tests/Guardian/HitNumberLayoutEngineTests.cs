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
        public void BalancedSummaryProjectsCompactSemanticLanesWithoutWorldDetailCells()
        {
            List<HitNumberSegment> singleType = BuildBurst(120, 512, 400, "boss");
            foreach (HitNumberSegment seg in singleType)
                seg.Packed = HitNumberPacking.Create(0, false, 28, 1);

            HitNumberLayoutFrame uniformFrame = HitNumberLayoutEngine.BuildFrame(
                singleType,
                2.0,
                HitNumberLayoutCandidate.BalancedSummary);

            Assert.Equal(120, uniformFrame.InputActiveSegmentCount);
            Assert.Equal(0, uniformFrame.DetailItemCount);
            Assert.Equal(1, uniformFrame.SummaryItemCount);
            HitNumberBurstRow row = Assert.Single(uniformFrame.WorldRows);
            Assert.Equal(148f, row.Bounds.Width);
            Assert.Equal(35f, row.Bounds.Height);
            Assert.Single(uniformFrame.Items);

            // 混伤输入按语义分轨并有界截断为每目标最多 3 轨，绝不展开为逐段格。
            List<HitNumberSegment> mixed = BuildBurst(120, 512, 400, "boss");
            HitNumberLayoutFrame mixedFrame = HitNumberLayoutEngine.BuildFrame(
                mixed,
                2.0,
                HitNumberLayoutCandidate.BalancedSummary);
            Assert.Equal(120, mixedFrame.InputActiveSegmentCount);
            Assert.Equal(0, mixedFrame.DetailItemCount);
            Assert.Equal(HitNumberBalancedAccumulator.LanesPerTarget, mixedFrame.WorldRows.Count);
            Assert.Equal(HitNumberBalancedAccumulator.LanesPerTarget, mixedFrame.SummaryItemCount);
        }

        [Theory]
        [InlineData(0)]
        [InlineData(1)]
        public void OffscreenTargetCullUsesTheSameContractAcrossWorldModes(int candidateValue)
        {
            var candidate = (HitNumberLayoutCandidate)candidateValue;
            List<HitNumberSegment> segments = BuildBurst(10, 512, 400, "visible");
            segments.AddRange(BuildBurst(6, 1300, 400, "offscreen", 100));
            foreach (HitNumberSegment seg in segments)
                seg.Packed = HitNumberPacking.Create(0, false, 28, 1);

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
            foreach (HitNumberSegment segment in segments)
            {
                segment.BurstId = "linked-shot-1";
                if (candidate == HitNumberLayoutCandidate.BalancedSummary)
                    segment.Packed = HitNumberPacking.Create(0, false, 28, 1);
            }

            HitNumberLayoutFrame frame = HitNumberLayoutEngine.BuildFrame(
                segments,
                2.0,
                candidate);

            HitNumberBurstRow row = Assert.Single(frame.WorldRows);
            Assert.Equal(12, row.HitCount);
            if (candidate == HitNumberLayoutCandidate.FixedBurstStack)
            {
                Assert.Equal("linked-shot-1", row.BurstId);
                Assert.Equal(12, row.Segments.Count);
            }
            else
            {
                Assert.StartsWith("#lane:1:", row.BurstId);
            }
        }

        [Fact]
        public void BalancedWorldRowsNeverCombineSameBurstIdAcrossTargets()
        {
            List<HitNumberSegment> segments = BuildBurst(8, 470, 390, "left");
            segments.AddRange(BuildBurst(9, 555, 390, "right", 50));
            foreach (HitNumberSegment seg in segments)
                seg.Packed = HitNumberPacking.Create(0, false, 28, 1);

            HitNumberLayoutFrame frame = HitNumberLayoutEngine.BuildFrame(
                segments,
                2.0,
                HitNumberLayoutCandidate.BalancedSummary);

            Assert.Equal(2, frame.WorldRows.Count);
            Assert.Equal(2, frame.WorldRows.Select(row => row.TargetId).Distinct().Count());
            Assert.Equal(8, frame.WorldRows.Single(row => row.TargetId == "left").HitCount);
            Assert.Equal(9, frame.WorldRows.Single(row => row.TargetId == "right").HitCount);
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
            if (candidate == HitNumberLayoutCandidate.BalancedSummary)
            {
                foreach (HitNumberSegment seg in crowded)
                    seg.Packed = HitNumberPacking.Create(0, false, 28, 1);
            }

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

        [Fact]
        public void NewAttackMovesOlderRowOnlyAlongVerticalAxisInDetailStack()
        {
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
                HitNumberLayoutEngine.BuildFrame(oldOnly, 2.0, HitNumberLayoutCandidate.FixedBurstStack).WorldRows);
            HitNumberBurstRow after = Assert.Single(
                HitNumberLayoutEngine.BuildFrame(withNew, 2.0, HitNumberLayoutCandidate.FixedBurstStack).WorldRows,
                row => row.BurstId == "old");

            Assert.Equal(before.Bounds.X, after.Bounds.X);
            Assert.Equal(before.Bounds.Width, after.Bounds.Width);
            Assert.True(after.Bounds.Y < before.Bounds.Y);
        }

        [Fact]
        public void NewAttackImmediatelyReservesStableNonOverlappingSlotInDetailStack()
        {
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
                HitNumberLayoutEngine.BuildFrame(segments, 1.82, HitNumberLayoutCandidate.FixedBurstStack).WorldRows,
                row => row.BurstId == "old");
            HitNumberBurstRow settled = Assert.Single(
                HitNumberLayoutEngine.BuildFrame(segments, 1.92, HitNumberLayoutCandidate.FixedBurstStack).WorldRows,
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
        public void TargetStackOrdersNewestAttackFirstAndKeepsSegmentOrderInDetailStack()
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
                HitNumberLayoutCandidate.FixedBurstStack);

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

            HitNumberLayoutFrame detail = HitNumberLayoutEngine.BuildFrame(
                segments,
                2.0,
                HitNumberLayoutCandidate.FixedBurstStack);
            HitNumberBurstRow detailRow = Assert.Single(detail.WorldRows);

            Assert.Equal(431, detailRow.Segments[0].Damage);
            Assert.Equal("火", detailRow.Segments[0].EffectText);
            Assert.Equal(372, detailRow.Segments[1].Damage);
            Assert.Equal(96, detailRow.Segments[1].LifeSteal);
            Assert.Contains("火", detailRow.AttributeSummary);
            Assert.Contains("汲", detailRow.AttributeSummary);

            // 平衡语义分轨：异色异属性分离为独立轨道，同轨异效（火+汲）聚合保留。
            HitNumberLayoutFrame balanced = HitNumberLayoutEngine.BuildFrame(
                segments,
                2.0,
                HitNumberLayoutCandidate.BalancedSummary);
            Assert.Equal(2, balanced.WorldRows.Count);
            Assert.Contains(balanced.WorldRows, r => r.TotalDamage == 431 && r.AttributeSummary.Contains("火"));
            Assert.Contains(balanced.WorldRows, r => r.TotalDamage == 372 && r.AttributeSummary.Contains("汲"));
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
            segments[0].Packed = HitNumberPacking.Create(0, false, 28, 1);
            segments[1].Packed = HitNumberPacking.Create(0, false, 28, 1);

            HitNumberLayoutFrame frame = HitNumberLayoutEngine.BuildFrame(
                segments,
                2.0,
                HitNumberLayoutCandidate.BalancedSummary);
            HitNumberPaintItem summary = Assert.Single(frame.Items);

            Assert.Equal(int.MaxValue, summary.Value);
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
                Value = 12345,
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

            // 冲击白闪峰值期间：属性字保持冻结来源色，主数字出现自适应提亮；75ms 稳态后完全回归来源色。
            HitNumberLayoutFrame impactFrame = HitNumberLayoutEngine.BuildFrame(
                segments,
                1.22,
                HitNumberLayoutCandidate.BalancedSummary);
            HitNumberPaintItem impactItem = Assert.Single(impactFrame.Items);
            Assert.Equal(Color.FromArgb(0x00, 0x99, 0xFF), impactItem.EffectTextColorOverride);
            Assert.True(impactItem.MainColorOverride.GetValueOrDefault().R > 0);

            HitNumberLayoutFrame settledFrame = HitNumberLayoutEngine.BuildFrame(
                segments,
                1.35,
                HitNumberLayoutCandidate.BalancedSummary);
            HitNumberPaintItem item = Assert.Single(settledFrame.Items);

            Assert.Equal(flags, HitNumberPacking.Flags(item.Packed));
            Assert.Equal("热", item.EffectText);
            Assert.Equal("热", item.CrushText);
            Assert.Equal("✦", item.CrushEmoji);
            Assert.Equal(30f, item.LifeSteal);
            Assert.Equal(42f, item.ShieldAbsorb);
            Assert.Equal("999999099", item.FlagScales);
            Assert.Equal(HitNumberBalancedAccumulator.SemanticDensityScale, item.SemanticDensityScale, 4);
            Assert.Equal(Color.FromArgb(0x00, 0x99, 0xFF), item.MainColorOverride);
            Assert.Equal(Color.FromArgb(0x00, 0x99, 0xFF), item.EffectTextColorOverride);
        }

        [Fact]
        public void BalancedSummarySeparatesMixedColorsIntoPureSemanticLanesWithAdaptiveWhiteFlash()
        {
            HitNumberSegment red = Segment(1, "mixed-color", 1.0, 1000);
            red.Packed = HitNumberPacking.Create(0, false, 28, 1);
            HitNumberSegment blue = Segment(2, "mixed-color", 1.3, 100);
            blue.Packed = HitNumberPacking.Create(0, false, 28, 6);
            var source = new[] { red, blue };

            HitNumberLayoutFrame impact = HitNumberLayoutEngine.BuildFrame(
                source,
                1.31,
                HitNumberLayoutCandidate.BalancedSummary);
            HitNumberLayoutFrame settled = HitNumberLayoutEngine.BuildFrame(
                source,
                1.50,
                HitNumberLayoutCandidate.BalancedSummary);

            Assert.Equal(2, impact.Items.Count);
            Assert.Equal(2, settled.Items.Count);
            HitNumberPaintItem blueImpact = Assert.Single(impact.Items, i => i.SourceBurstId == "#lane:6:");
            HitNumberPaintItem blueSettled = Assert.Single(settled.Items, i => i.SourceBurstId == "#lane:6:");
            HitNumberPaintItem redSettled = Assert.Single(settled.Items, i => i.SourceBurstId == "#lane:1:");

            // 蓝轨在受击瞬间做自适应白闪，稳态回归纯源色；红轨始终维持纯红，不互相混色。
            Assert.True(blueImpact.MainColorOverride.GetValueOrDefault().R > blueSettled.MainColorOverride.GetValueOrDefault().R);
            Assert.Equal(Color.FromArgb(0x00, 0x99, 0xFF).ToArgb(), blueSettled.MainColorOverride.GetValueOrDefault().ToArgb());
            Assert.Equal(Color.FromArgb(0xFF, 0x00, 0x00).ToArgb(), redSettled.MainColorOverride.GetValueOrDefault().ToArgb());
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
        public void BalancedHighRateStreamKeepsAtMostThreeNonOverlappingSemanticLanesPerTarget()
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

            Assert.Equal(HitNumberBalancedAccumulator.LanesPerTarget, bounds.Count);
            Assert.All(frame.WorldRows, row => Assert.StartsWith("#lane:", row.BurstId));
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
            for (int lane = 0; lane < 5; lane++)
            {
                HitNumberSegment segment = Segment(
                    lane,
                    "boss-" + lane,
                    1.20 + lane * 0.10,
                    100 + lane * 20);
                segment.TargetId = "boss";
                segment.Packed = HitNumberPacking.Create(0, false, 28, lane);
                segments.Add(segment);
            }
            HitNumberSegment mob = Segment(10, "mob-0", 1.15, 80);
            mob.TargetId = "mob";
            mob.TargetX = 680;
            mob.Packed = HitNumberPacking.Create(0, false, 28, 1);
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
            Assert.Equal(
                reference.WorldRows.Select(row => (row.TargetId, row.BurstId)),
                fast.WorldRows.Select(row => (row.TargetId, row.BurstId)));
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
                reference.Items.Select(item => item.Value),
                fast.Items.Select(item => item.Value));
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

            HitNumberLayoutFrame fast = HitNumberLayoutEngine.BuildFrame(
                segments, 0, 2.0, HitNumberLayoutCandidate.FixedBurstStack,
                HitNumberCamera.Identity, 1, HitNumberLayoutEngine.DefaultLifetimeSeconds, false);
            HitNumberLayoutFrame reference = HitNumberLayoutEngine.BuildFrame(
                segments, 0, 2.0, HitNumberLayoutCandidate.FixedBurstStack,
                HitNumberCamera.Identity, 1, HitNumberLayoutEngine.DefaultLifetimeSeconds, true);

            Assert.Equal("attack-a", Assert.Single(reference.WorldRows).BurstId);
            Assert.Equal(
                reference.WorldRows.Select(row => row.BurstId),
                fast.WorldRows.Select(row => row.BurstId));
            Assert.Equal(reference.WorldSegmentOmittedCount, fast.WorldSegmentOmittedCount);
        }

        [Fact]
        public void BalancedB1_FixedSlotsNeverSwapWhenHigherSlotOvertakesDamageAndCompactsOnlyOnExpiry()
        {
            var acc = new HitNumberBalancedAccumulator();
            HitNumberSegment phys = Segment(1, "b1", 1.00, 200);
            phys.Packed = HitNumberPacking.Create(0, false, 26, 1);
            HitNumberSegment thermal = Segment(2, "b2", 1.05, 80);
            thermal.Packed = HitNumberPacking.Create(8, false, 26, 6);
            thermal.EffectText = "热";
            acc.AddRange(new[] { phys, thermal }, 0, 2);

            var initial = acc.Snapshot(1.06);
            HitNumberBalancedLane physLane = Assert.Single(initial, l => l.MainColorId == 1);
            HitNumberBalancedLane thermalLane = Assert.Single(initial, l => l.MainColorId == 6);
            Assert.Equal(0, physLane.SlotIndex);
            Assert.Equal(1, thermalLane.SlotIndex);

            // 热伤轨道反超总伤，槽位绝不互换。
            HitNumberSegment bigThermal = Segment(3, "b3", 1.25, 1500);
            bigThermal.Packed = HitNumberPacking.Create(8, false, 32, 6);
            bigThermal.EffectText = "热";
            acc.AddRange(new[] { bigThermal }, 0, 1);
            var overtaken = acc.Snapshot(1.26);
            Assert.Equal(0, Assert.Single(overtaken, l => l.MainColorId == 1).SlotIndex);
            Assert.Equal(1, Assert.Single(overtaken, l => l.MainColorId == 6).SlotIndex);

            // 物理轨在 1.00 + 1.08s 过期后，热伤轨收敛到槽 0。
            var compacted = acc.Snapshot(2.15);
            HitNumberBalancedLane remaining = Assert.Single(compacted);
            Assert.Equal(6, remaining.MainColorId);
            Assert.Equal(0, remaining.SlotIndex);
        }

        [Fact]
        public void BalancedB1_SlideInOvershootAppliesToNewHigherSlotWithoutOverlappingBounds()
        {
            var acc = new HitNumberBalancedAccumulator();
            HitNumberSegment phys = Segment(1, "b1", 1.00, 120);
            phys.Packed = HitNumberPacking.Create(0, false, 26, 1);
            HitNumberSegment fire = Segment(2, "b2", 1.02, 90);
            fire.Packed = HitNumberPacking.Create(8, false, 26, 2);
            fire.EffectText = "火";
            acc.AddRange(new[] { phys, fire }, 0, 2);

            HitNumberLayoutFrame birth = HitNumberLayoutEngine.BuildBalancedFrame(
                acc.Snapshot(1.02), 1.02, HitNumberCamera.Identity, 24);
            HitNumberLayoutFrame midOvershoot = HitNumberLayoutEngine.BuildBalancedFrame(
                acc.Snapshot(1.115), 1.115, HitNumberCamera.Identity, 24);
            HitNumberLayoutFrame settled = HitNumberLayoutEngine.BuildBalancedFrame(
                acc.Snapshot(1.20), 1.20, HitNumberCamera.Identity, 24);

            // Bounds 从第 0 帧即严格不重叠。
            Assert.False(birth.WorldRows[0].Bounds.IntersectsWith(birth.WorldRows[1].Bounds));
            HitNumberPaintItem physBirth = Assert.Single(birth.Items, i => i.SourceBurstId == "#lane:1:");
            HitNumberPaintItem fireBirth = Assert.Single(birth.Items, i => i.SourceBurstId == "#lane:2:火");
            HitNumberPaintItem fireOver = Assert.Single(midOvershoot.Items, i => i.SourceBurstId == "#lane:2:火");
            HitNumberPaintItem fireSettled = Assert.Single(settled.Items, i => i.SourceBurstId == "#lane:2:火");
            // 出生即保持 >=26px 纵向安全间距，出生在稳态槽位下方、中段过冲略高于稳态槽位、140ms 后落稳。
            Assert.True(physBirth.StageY - fireBirth.StageY >= 26f);
            Assert.True(fireBirth.StageY > fireSettled.StageY);
            Assert.True(fireOver.StageY < fireSettled.StageY);
        }

        [Fact]
        public void BalancedB1_TieredImpactEnergyAccumulatesAndTriggersMicroShakeOnTier3()
        {
            var acc = new HitNumberBalancedAccumulator();
            HitNumberSegment first = Segment(1, "s1", 1.00, 100);
            first.Packed = HitNumberPacking.Create(0, false, 24, 1);
            acc.AddRange(new[] { first }, 0, 1);
            HitNumberBalancedLane lane = Assert.Single(acc.Snapshot(1.00));
            Assert.Equal(2, lane.LastHitTier); // 冷启动首击默认 T2
            float coldScale = lane.ComputeScale();
            Assert.True(coldScale > 1.30f);

            // 衰减后用大字号/斩杀触发 T3：冲击缩放更高、描边更厚且触发微震颤。
            acc.Snapshot(1.30);
            HitNumberSegment heavy = Segment(2, "s2", 1.32, 850);
            heavy.Packed = HitNumberPacking.Create(4, false, 36, 1);
            acc.AddRange(new[] { heavy }, 0, 1);
            // 斩杀轨与普通物理轨分轨：新轨应直接 T3。
            HitNumberBalancedLane execLane = Assert.Single(acc.Snapshot(1.32), l => (l.Flags & 4) != 0);
            Assert.Equal(3, execLane.LastHitTier);
            Assert.True(execLane.ComputeScale() > coldScale);
            Assert.True(execLane.ComputeBlur() > 3.5f);
            execLane.ComputeShake(1.34, out float sx, out float sy);
            Assert.True(Math.Abs(sx) > 0.01f || Math.Abs(sy) > 0.01f);
            execLane.ComputeShake(1.50, out float settledX, out float settledY);
            Assert.Equal(0f, settledX);
            Assert.Equal(0f, settledY);
        }

        [Fact]
        public void BalancedB1_AdaptiveWhiteFlashProtectsPaleBlockColorsFromWashingOut()
        {
            Color red = Color.FromArgb(0xFF, 0x00, 0x00);
            Color paleYellow = Color.FromArgb(0xFF, 0xE7, 0x70); // 挡拆过穿浅黄
            Color palePink = Color.FromArgb(0xFF, 0x7F, 0x7F);   // 敌方过穿浅粉

            Color flashedRed = HitNumberBalancedLane.BlendTowardsWhiteAdaptive(red, 0.55f);
            Color flashedYellow = HitNumberBalancedLane.BlendTowardsWhiteAdaptive(paleYellow, 0.55f);
            Color flashedPink = HitNumberBalancedLane.BlendTowardsWhiteAdaptive(palePink, 0.55f);

            // 饱和红白闪提亮幅度远大于浅黄挡拆色，保护浅黄不洗白撞脸 MISS。
            int redDelta = (flashedRed.G - red.G) + (flashedRed.B - red.B);
            int yellowDelta = (flashedYellow.G - paleYellow.G) + (flashedYellow.B - paleYellow.B);
            Assert.True(redDelta > yellowDelta * 2);
            Assert.True(flashedYellow.B < 200);
            Assert.True(flashedPink.G < 205);
        }

        [Fact]
        public void BalancedB1_DamageSizeWeightsFontSizeAndEvictionProtectsExecuteLane()
        {
            var acc = new HitNumberBalancedAccumulator();
            HitNumberSegment exec = Segment(1, "e1", 1.00, 50);
            exec.Packed = HitNumberPacking.Create(4, false, 36, 1);
            HitNumberSegment small = Segment(2, "e2", 1.01, 40);
            small.Packed = HitNumberPacking.Create(0, false, 18, 2);
            HitNumberSegment mid = Segment(3, "e3", 1.02, 400);
            mid.Packed = HitNumberPacking.Create(0, false, 28, 3);
            HitNumberSegment fourth = Segment(4, "e4", 1.03, 500);
            fourth.Packed = HitNumberPacking.Create(0, false, 30, 5);
            acc.AddRange(new[] { exec, small, mid, fourth }, 0, 4);

            var lanes = acc.Snapshot(1.03);
            Assert.Equal(3, lanes.Count);
            Assert.Contains(lanes, l => (l.Flags & 4) != 0);
            Assert.DoesNotContain(lanes, l => l.MainColorId == 2); // 最低优先级的 40 伤害小轨被淘汰

            HitNumberBalancedLane execLane = Assert.Single(lanes, l => (l.Flags & 4) != 0);
            HitNumberBalancedLane midLane = Assert.Single(lanes, l => l.MainColorId == 3);
            Assert.True(execLane.ComputeFontSize() > midLane.ComputeFontSize());
        }

        [Fact]
        public void BalancedB1_MissLaneSuppressedDuringActiveHitsAndShownOnEmptyTarget()
        {
            var acc = new HitNumberBalancedAccumulator();
            HitNumberSegment missEmpty = Segment(1, "m1", 1.00, 0);
            missEmpty.Packed = HitNumberPacking.Create(0, true, 24, 0);
            acc.AddRange(new[] { missEmpty }, 0, 1);
            Assert.True(Assert.Single(acc.Snapshot(1.10)).IsMissLane);

            // 命中后立刻清掉 MISS 轨；活跃命中后 0.35s 内的 MISS 被抑制。
            HitNumberSegment hit = Segment(2, "h1", 1.15, 220);
            hit.Packed = HitNumberPacking.Create(0, false, 28, 1);
            HitNumberSegment suppressedMiss = Segment(3, "m2", 1.25, 0);
            suppressedMiss.Packed = HitNumberPacking.Create(0, true, 24, 0);
            acc.AddRange(new[] { hit, suppressedMiss }, 0, 2);

            var active = acc.Snapshot(1.26);
            Assert.DoesNotContain(active, l => l.IsMissLane);
            Assert.Single(active);
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
