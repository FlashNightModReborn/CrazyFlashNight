using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Text;
using CF7Launcher.Guardian.HitNumbers;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class HitNumberRuntimeTests
    {
        [Fact]
        public void IdleAndDisabledFramesPublishNothingAfterInitialReset()
        {
            double now = 1.0;
            var runtime = new HitNumberRuntime(() => now);

            Assert.Null(runtime.ProcessFrame("0|0|1", null));
            HitNumberRuntimeSnapshot reset = runtime.Configure(
                new HitNumberRuntimeOptions(HitNumberDisplayMode.Off, 24));

            Assert.True(reset.IsReset);
            Assert.Equal(HitNumberDisplayMode.Off, reset.Mode);
            Assert.Null(runtime.ProcessFrame("10|20|1.2", Entry("disabled", 1)));
            Assert.Equal(0, runtime.StoredSegmentCountForTests);
        }

        [Fact]
        public void ExpiryPublishesExactlyOneDismissSnapshot()
        {
            double now = 1.0;
            var runtime = new HitNumberRuntime(() => now);

            HitNumberRuntimeSnapshot visible = runtime.ProcessFrame(
                "0|0|1",
                Entry("burst", 1));
            Assert.NotNull(visible);
            Assert.False(visible.IsReset);

            now += HitNumberLayoutEngine.DefaultLifetimeSeconds + 0.01;
            HitNumberRuntimeSnapshot dismiss = runtime.ProcessFrame("0|0|1", null);
            Assert.NotNull(dismiss);
            Assert.False(dismiss.IsReset);
            Assert.True(dismiss.IsDismiss);
            Assert.Null(runtime.ProcessFrame("0|0|1", null));
        }

        [Fact]
        public void BalancedWorldProjectionAndExactLedgerHaveIndependentLifetimes()
        {
            double now = 2.0;
            var runtime = new HitNumberRuntime(() => now);
            string payload = Entry("linked", 2, 100) + ";" + Entry("linked", 2, 120);

            HitNumberRuntimeSnapshot normal = runtime.ProcessFrame("0|0|1", payload);
            Assert.Single(normal.Frame.WorldRows);
            Assert.Equal(2, runtime.StoredSegmentCountForTests);
            Assert.Equal(2, runtime.LedgerSegmentCountForTests);

            now += HitNumberLayoutEngine.DefaultLifetimeSeconds + 0.01;
            Assert.True(runtime.ProcessFrame("0|0|1", null).IsDismiss);
            JObject ledger = runtime.BuildLedgerPage(0, 24);
            JObject burst = Assert.IsType<JObject>(Assert.Single((JArray)ledger["bursts"]));
            Assert.Equal(220L, burst.Value<long>("totalDamage"));
            Assert.Equal(2, burst.Value<int>("hitCount"));
            Assert.Equal(2, ((JArray)burst["segments"]).Count);
        }

        [Fact]
        public void DetailModeFiniteWorldProjectionDoesNotTruncateExactSettingsLedger()
        {
            double now = 2.0;
            var runtime = new HitNumberRuntime(() => now);
            runtime.Configure(new HitNumberRuntimeOptions(HitNumberDisplayMode.Detail, 1));
            string payload = Entry("old", 2, 100) + ";" + Entry("old", 2, 120) + ";" +
                Entry("new", 2, 140) + ";" + Entry("new", 2, 160);

            HitNumberRuntimeSnapshot normal = runtime.ProcessFrame("0|0|1", payload);
            Assert.Single(normal.Frame.WorldRows);
            Assert.Equal(2, normal.Frame.WorldSegmentOmittedCount);

            JObject ledger = runtime.BuildLedgerPage(0, 24);
            Assert.Equal(2, ledger.Value<int>("totalBursts"));
            Assert.Equal(4, ledger.Value<int>("retainedSegments"));
            Assert.Equal(4, ((JArray)ledger["bursts"])
                .Sum(token => ((JArray)token["segments"]).Count));
        }

        [Theory]
        [InlineData("balanced", 1)]
        [InlineData("detail", 2)]
        [InlineData("classic", 3)]
        [InlineData("total", 4)]
        [InlineData("off", 0)]
        [InlineData("unknown", 1)]
        public void PreferencesResolveAllSupportedModes(
            string value,
            int expectedValue)
        {
            Assert.Equal((HitNumberDisplayMode)expectedValue,
                HitNumberRuntimeOptions.FromPreferences(value, 24).Mode);
        }

        [Fact]
        public void TotalModeKeepsOneScalarEntryForContinuousHitsOnOneTarget()
        {
            double now = 0.0;
            var runtime = new HitNumberRuntime(() => now);
            runtime.Configure(new HitNumberRuntimeOptions(HitNumberDisplayMode.Total, 24));

            HitNumberRuntimeSnapshot latest = null;
            for (int frame = 0; frame < 240; frame++)
            {
                latest = runtime.ProcessFrame("0|0|1",
                    Entry("shot-" + frame, 2, 10) + ";" +
                    Entry("shot-" + frame, 2, 11));
                now += 1.0 / 60.0;
            }

            HitNumberBurstRow row = Assert.Single(latest.Frame.WorldRows);
            Assert.Equal(480, row.HitCount);
            Assert.Equal(5040L, row.TotalDamage);
            Assert.Equal(1, runtime.TotalTargetCountForTests);
            Assert.InRange(runtime.StoredSegmentCountForTests, 120, 132);
        }

        [Fact]
        public void TotalAccumulatorPrunesHistoricalTargetsWhileBalancedModeRuns()
        {
            double now = 0.0;
            var runtime = new HitNumberRuntime(() => now);

            for (int i = 0; i < 40; i++)
            {
                runtime.ProcessFrame(
                    "0|0|1",
                    Entry("burst-" + i, 1, 100, "target-" + i));
                now += HitNumberTotalAccumulator.LifetimeSeconds + 0.01;
            }

            Assert.Equal(HitNumberDisplayMode.Balanced, runtime.Options.Mode);
            Assert.Equal(1, runtime.TotalTargetCountForTests);
        }

        [Fact]
        public void ClassicModeUsesShortFlashLifetimeAndPublishesOneDismiss()
        {
            double now = 1.0;
            var runtime = new HitNumberRuntime(() => now);
            runtime.Configure(new HitNumberRuntimeOptions(HitNumberDisplayMode.Classic, 0));

            HitNumberRuntimeSnapshot visible = runtime.ProcessFrame(
                "0|0|1", Entry("classic", 1));
            Assert.Single(visible.Frame.Items);
            Assert.Equal(HitNumberLayoutCandidate.ClassicScatter, visible.Frame.Candidate);

            now += HitNumberLayoutEngine.ClassicLifetimeSeconds + 0.001;
            Assert.True(runtime.ProcessFrame("0|0|1", null).IsDismiss);
            Assert.Null(runtime.ProcessFrame("0|0|1", null));
        }

        [Fact]
        public void ParserClampsExpectedBurstGeometryWithoutDroppingRealSegments()
        {
            var parser = new HitNumberBatchParser();
            var destination = new List<HitNumberSegment>();
            int sequence = 0;

            int accepted = parser.ParseBatch(
                Entry("max", HitNumberRuntime.MaximumExpectedBurstHitCount) + ";" +
                Entry("too-large", HitNumberRuntime.MaximumExpectedBurstHitCount + 1),
                1.0,
                destination,
                ref sequence);

            Assert.Equal(2, accepted);
            Assert.Equal(0, parser.RejectedEntryCount);
            Assert.All(destination, segment => Assert.Equal(
                HitNumberRuntime.MaximumExpectedBurstHitCount,
                segment.ExpectedBurstHitCount));
        }

        [Fact]
        public void ExpiredPrefixCompactsWithoutHistoryProportionalBackingStorage()
        {
            double now = 0.0;
            var runtime = new HitNumberRuntime(() => now);
            var payload = new StringBuilder();
            int count = HitNumberRuntime.MaximumExpectedBurstHitCount;
            for (int i = 0; i < count; i++)
            {
                if (i > 0) payload.Append(';');
                payload.Append(Entry("old", count, 100 + i));
            }
            runtime.ProcessFrame("0|0|1", payload.ToString());

            now = 1.0;
            runtime.ProcessFrame("0|0|1", Entry("new", 1, 999));
            now = HitNumberLayoutEngine.DefaultLifetimeSeconds + 0.01;
            runtime.ProcessFrame("0|0|1", null);

            Assert.Equal(1, runtime.StoredSegmentCountForTests);
            Assert.Equal(1, runtime.BackingSegmentCountForTests);
        }

        [Fact]
        public void SustainedHighHitStreamRemainsBoundedByVisualLifetimeNotHistory()
        {
            const int frames = 2000;
            const int hitsPerFrame = 20;
            double now = 0.0;
            var runtime = new HitNumberRuntime(() => now);

            for (int frame = 0; frame < frames; frame++)
            {
                var payload = new StringBuilder();
                for (int hit = 0; hit < hitsPerFrame; hit++)
                {
                    if (hit > 0) payload.Append(';');
                    payload.Append(Entry(
                        "f" + frame + "h" + hit,
                        1,
                        100 + hit));
                }
                runtime.ProcessFrame("0|0|1", payload.ToString());
                now += 1.0 / 60.0;
            }

            // 1200 段/秒下只保留约 1.08 秒窗口；后备数组也会在过期前缀达到
            // 阈值后压实，不随累计 40,000 段线性增长。
            Assert.InRange(runtime.StoredSegmentCountForTests, 1200, 1320);
            Assert.InRange(runtime.BackingSegmentCountForTests, 1200, 5500);
        }

        [Fact]
        public void ConfigurationChangesAdvanceGenerationWithoutDiscardingLiveSegments()
        {
            double now = 2.0;
            var runtime = new HitNumberRuntime(() => now);
            HitNumberRuntimeSnapshot before = runtime.ProcessFrame(
                "0|0|1",
                Entry("burst", 1));

            HitNumberRuntimeSnapshot after = runtime.Configure(
                new HitNumberRuntimeOptions(HitNumberDisplayMode.Detail, 12));

            Assert.True(after.Generation > before.Generation);
            Assert.Equal(HitNumberDisplayMode.Detail, after.Mode);
            Assert.Single(after.Frame.WorldRows);
            Assert.Equal(1, runtime.StoredSegmentCountForTests);
        }

        private static string Entry(
            string burstId,
            int expectedHitCount,
            int damage = 100,
            string targetId = "boss")
        {
            return damage + "|512|330|28672|||0|0|" + targetId + "|" + burstId + "|" +
                expectedHitCount;
        }
    }

    public sealed class HitNumberTotalAccumulatorTests
    {
        [Fact]
        public void NewHitColorFlashesThenReturnsTowardDamageDominantColor()
        {
            var totals = new HitNumberTotalAccumulator();
            HitNumberSegment dominant = TotalSegment(1, 0.0, 100, 1);
            totals.AddRange(new[] { dominant }, 0, 1);
            totals.Snapshot(0.0);

            HitNumberSegment newest = TotalSegment(2, 0.01, 10, 6);
            totals.AddRange(new[] { newest }, 0, 1);
            HitNumberTotalEntry flash = Assert.Single(totals.Snapshot(0.01));

            Assert.Equal(1, flash.DominantColorId);
            Assert.Equal(0x00, flash.DisplayR);
            Assert.Equal(0x99, flash.DisplayG);
            Assert.Equal(0xFF, flash.DisplayB);
            Assert.Equal(100L, flash.DisplayDamage);
            Assert.Equal(1, flash.DisplayHitCount);

            HitNumberTotalEntry settled = Assert.Single(totals.Snapshot(0.51));
            Assert.True(settled.DisplayR > settled.DisplayB);
            Assert.True(settled.DisplayDamage > 100L);
            Assert.True(settled.DisplayHitCount > 1);
        }

        [Fact]
        public void MissDoesNotCreateOrRefreshTotalButLedgerCanRemainIndependent()
        {
            var totals = new HitNumberTotalAccumulator();
            HitNumberSegment miss = TotalSegment(1, 0.0, 0, 0);
            miss.Packed |= 1 << 9;
            totals.AddRange(new[] { miss }, 0, 1);
            Assert.Empty(totals.Snapshot(0.0));

            HitNumberSegment hit = TotalSegment(2, 0.1, 30, 2);
            totals.AddRange(new[] { hit }, 0, 1);
            miss.ArrivalSeconds = 0.2;
            totals.AddRange(new[] { miss }, 0, 1);
            HitNumberTotalEntry entry = Assert.Single(totals.Snapshot(0.2));

            Assert.Equal(30L, entry.TotalDamage);
            Assert.Equal(1, entry.HitCount);
            Assert.Equal(0.1, entry.LastArrivalSeconds, 6);
        }

        [Fact]
        public void HitDuringFadeWindowResumesExistingTotalInsteadOfResettingIt()
        {
            var totals = new HitNumberTotalAccumulator();
            totals.AddRange(new[] { TotalSegment(1, 0.0, 40, 1) }, 0, 1);
            totals.AddRange(new[] { TotalSegment(2, 1.30, 60, 2) }, 0, 1);

            HitNumberTotalEntry entry = Assert.Single(totals.Snapshot(1.30));
            Assert.Equal(100L, entry.TotalDamage);
            Assert.Equal(2, entry.HitCount);
        }

        private static HitNumberSegment TotalSegment(
            int sequence,
            double arrival,
            int damage,
            int colorId)
        {
            return new HitNumberSegment
            {
                Sequence = sequence,
                BurstId = "burst-" + sequence,
                ExpectedBurstHitCount = 1,
                TargetId = "boss",
                TargetX = 512,
                TargetY = 390,
                ArrivalSeconds = arrival,
                Damage = damage,
                Packed = HitNumberPacking.Create(0, false, 20, colorId)
            };
        }
    }

    public sealed class HitNumberLedgerStoreTests
    {
        [Fact]
        public void FixedRingDisclosesOverflowAndKeepsNewestExactSegments()
        {
            var store = new HitNumberLedgerStore();
            var source = new List<HitNumberSegment>(HitNumberLedgerStore.Capacity + 3);
            for (int i = 0; i < HitNumberLedgerStore.Capacity + 3; i++)
            {
                source.Add(new HitNumberSegment
                {
                    Sequence = i,
                    TargetId = "boss",
                    BurstId = "burst-" + i,
                    ExpectedBurstHitCount = 1,
                    ArrivalSeconds = i / 60.0,
                    Damage = i
                });
            }

            store.AddRange(source, 0, source.Count);
            JObject page = store.BuildPage(1000.0, 0, 2);

            Assert.Equal(HitNumberLedgerStore.Capacity, page.Value<int>("retainedSegments"));
            Assert.Equal(3L, page.Value<long>("droppedSegments"));
            Assert.True(page.Value<bool>("oldestBurstMayBePartial"));
            JArray bursts = (JArray)page["bursts"];
            Assert.Equal("burst-32770", bursts[0].Value<string>("burstId"));
            Assert.Equal("burst-32769", bursts[1].Value<string>("burstId"));
        }

        [Fact]
        public void ResetClearsRetainedAndDroppedCountsAndAdvancesGeneration()
        {
            var store = new HitNumberLedgerStore();
            store.AddRange(new[]
            {
                new HitNumberSegment
                {
                    Sequence = 1,
                    TargetId = "boss",
                    BurstId = "shot",
                    ExpectedBurstHitCount = 1,
                    Damage = 7
                }
            }, 0, 1);
            int before = store.BuildPage(1.0, 0, 1).Value<int>("generation");

            store.Reset();
            JObject after = store.BuildPage(1.0, 0, 1);

            Assert.Equal(before + 1, after.Value<int>("generation"));
            Assert.Equal(0, after.Value<int>("retainedSegments"));
            Assert.Equal(0L, after.Value<long>("droppedSegments"));
            Assert.Empty((JArray)after["bursts"]);
        }
    }

    public sealed class HitNumberFrameMailboxTests
    {
        [Fact]
        public void HundredThousandPublishesKeepOneDispatchAndLatestFrame()
        {
            using var mailbox = new HitNumberFrameMailbox();
            Assert.False(mailbox.SetReady());
            int scheduled = 0;
            for (int i = 0; i < 100000; i++)
            {
                var frame = new HitNumberLayoutFrame { InputActiveSegmentCount = i };
                if (mailbox.Publish(new HitNumberRuntimeSnapshot(
                    0,
                    HitNumberDisplayMode.Balanced,
                    frame)))
                {
                    scheduled++;
                }
            }

            Assert.Equal(1, scheduled);
            Assert.Equal(1, mailbox.PendingDispatchCount);
            HitNumberRuntimeSnapshot latest = mailbox.DrainLatest();
            Assert.Equal(99999, latest.Frame.InputActiveSegmentCount);
            Assert.Equal(0, mailbox.PendingDispatchCount);
        }

        [Fact]
        public void ResetGenerationRejectsOlderLateFrame()
        {
            using var mailbox = new HitNumberFrameMailbox();
            mailbox.SetReady();
            var old = new HitNumberRuntimeSnapshot(
                1,
                HitNumberDisplayMode.Balanced,
                new HitNumberLayoutFrame());
            var reset = new HitNumberRuntimeSnapshot(
                2,
                HitNumberDisplayMode.Balanced,
                null,
                true);

            Assert.True(mailbox.Publish(old));
            Assert.False(mailbox.Publish(reset));
            Assert.False(mailbox.Publish(old));
            Assert.True(mailbox.DrainLatest().IsReset);
            Assert.Equal(2, mailbox.AcceptedGeneration);
        }

        [Fact]
        public void NewerConfigurationGenerationRejectsOlderLateVisualFrame()
        {
            using var mailbox = new HitNumberFrameMailbox();
            mailbox.SetReady();
            var old = new HitNumberRuntimeSnapshot(
                4,
                HitNumberDisplayMode.Balanced,
                new HitNumberLayoutFrame());
            var configured = new HitNumberRuntimeSnapshot(
                5,
                HitNumberDisplayMode.Detail,
                new HitNumberLayoutFrame());

            Assert.True(mailbox.Publish(configured));
            Assert.False(mailbox.Publish(old));
            Assert.Same(configured, mailbox.DrainLatest());
            Assert.Equal(5, mailbox.AcceptedGeneration);
        }

        [Fact]
        public void FailedDispatchCanBeScheduledAgainWithoutLosingLatestFrame()
        {
            using var mailbox = new HitNumberFrameMailbox();
            mailbox.SetReady();
            var snapshot = new HitNumberRuntimeSnapshot(
                0,
                HitNumberDisplayMode.Detail,
                new HitNumberLayoutFrame());

            Assert.True(mailbox.Publish(snapshot));
            mailbox.DispatchFailed();
            Assert.True(mailbox.Publish(snapshot));
            Assert.Same(snapshot, mailbox.DrainLatest());
        }
    }

    public sealed class HitNumberRenderPlannerTests
    {
        [Fact]
        public void WorldOnlyFrameUsesTightRegionInsteadOfFullViewport()
        {
            HitNumberLayoutFrame frame = HitNumberLayoutEngine.BuildFrame(
                BuildSegment(),
                2.0,
                HitNumberLayoutCandidate.BalancedSummary);

            HitNumberRenderRegion region = HitNumberRenderPlanner.Plan(
                frame,
                1600,
                900);

            Assert.False(region.IsEmpty);
            Assert.True(region.PixelBounds.Width < 800);
            Assert.True(region.PixelBounds.Height < 450);
            Assert.Equal(-region.PixelBounds.Left, region.LocalViewport.X);
            Assert.Equal(-region.PixelBounds.Top, region.LocalViewport.Y);
        }

        [Fact]
        public void NoWorldItemsNeverAllocateAFullViewportSurface()
        {
            HitNumberRenderRegion region = HitNumberRenderPlanner.Plan(
                new HitNumberLayoutFrame(),
                1600,
                900);

            Assert.True(region.IsEmpty);
        }

        [Fact]
        public void PlannedRegionContainsOutlinedGlyphsWithoutTouchingSurfaceEdge()
        {
            var frame = new HitNumberLayoutFrame();
            frame.Items.Add(new HitNumberPaintItem
            {
                StageX = 512,
                StageY = 300,
                CombinedScale = 1.52f,
                CombinedBlur = 4f,
                Damage = 33731639,
                Packed = HitNumberPacking.Create(1 | 2 | 4 | 8 | 16 | 32 | 256,
                    false, 32, 2),
                EffectText = "粉碎附加",
                EffectEmoji = "⚡",
                LifeSteal = 1234,
                ShieldAbsorb = 5678,
                HitCount = 44,
                FlagScales = "999999999"
            });
            HitNumberRenderRegion region = HitNumberRenderPlanner.Plan(frame, 1600, 900);

            using var bitmap = new Bitmap(region.PixelBounds.Width, region.PixelBounds.Height);
            using Graphics graphics = Graphics.FromImage(bitmap);
            graphics.Clear(Color.Transparent);
            using var painter = new HitNumberPainter();
            painter.Paint(graphics, frame.Items, new HitNumberPaintContext(region.LocalViewport));

            Assert.True(HasVisiblePixel(bitmap));
            Assert.False(HasVisiblePixelOnBorder(bitmap, 3));
        }

        [Theory]
        [InlineData(1, 64)]
        [InlineData(64, 64)]
        [InlineData(65, 128)]
        [InlineData(191, 192)]
        public void SurfaceCapacityUsesStableSixtyFourPixelBuckets(int input, int expected)
        {
            Assert.Equal(expected, HitNumberRenderPlanner.QuantizeSurfaceCapacity(input));
        }

        private static List<HitNumberSegment> BuildSegment()
        {
            return new List<HitNumberSegment>
            {
                new HitNumberSegment
                {
                    Sequence = 1,
                    BurstId = "burst",
                    ExpectedBurstHitCount = 1,
                    TargetId = "boss",
                    TargetX = 512,
                    TargetY = 330,
                    ArrivalSeconds = 1.5,
                    Damage = 100,
                    Packed = HitNumberPacking.Create(0, false, 28, 0)
                }
            };
        }

        private static bool HasVisiblePixel(Bitmap bitmap)
        {
            for (int y = 0; y < bitmap.Height; y++)
                for (int x = 0; x < bitmap.Width; x++)
                    if (bitmap.GetPixel(x, y).A != 0) return true;
            return false;
        }

        private static bool HasVisiblePixelOnBorder(Bitmap bitmap, int thickness)
        {
            for (int y = 0; y < bitmap.Height; y++)
            {
                for (int x = 0; x < bitmap.Width; x++)
                {
                    if (x >= thickness && x < bitmap.Width - thickness &&
                        y >= thickness && y < bitmap.Height - thickness)
                        continue;
                    if (bitmap.GetPixel(x, y).A != 0) return true;
                }
            }
            return false;
        }
    }
}
