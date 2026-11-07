using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using CF7Launcher.Guardian.Hud.Icons;
using CF7Launcher.Guardian.Hud.Loot;
using Xunit;

namespace CF7Launcher.Tests.Guardian.Hud.Loot
{
    public sealed class LootIconPlaybackTests : IDisposable
    {
        private readonly string _root = Path.Combine(Path.GetTempPath(), "cf7-icon-playback-" + Guid.NewGuid().ToString("N"));
        public LootIconPlaybackTests() { Directory.CreateDirectory(_root); }
        public void Dispose() { Directory.Delete(_root, true); }

        private void Png(string name, Color color)
        {
            using var image = new Bitmap(16, 16);
            using (var g = Graphics.FromImage(image)) g.Clear(color);
            image.Save(Path.Combine(_root, name), ImageFormat.Png);
        }
        private Color Draw(LootIconCatalog catalog, LootIconCatalog.IconDescription description, int frame)
        {
            using var target = new Bitmap(32, 32);
            using var g = Graphics.FromImage(target);
            Assert.True(catalog.TryDrawPlayback(g, new Rectangle(0, 0, 32, 32), description, frame, 1f));
            return target.GetPixel(16, 16);
        }

        [Fact]
        public void Timeline_KeepsRepeatedSlotsFractionalFpsAndLongElapsedTime()
        {
            var timeline = new IconTimeline(new[] { 0, 0, 1 }, 29.97);
            Assert.Equal(0, timeline.Sample(333667));
            Assert.Equal(0, timeline.Sample(667334));
            Assert.Equal(1, timeline.Sample(667335));
            long ticks = (long)int.MaxValue * TimeSpan.TicksPerMillisecond + 1234567;
            int expected = (int)(decimal.Truncate(ticks * 29.97m / TimeSpan.TicksPerSecond) % 3);
            Assert.Equal(expected == 2 ? 1 : 0, timeline.Sample(ticks));
            var uniform = new IconTimeline(new[] { 0, 1, 2 }, 24);
            Assert.Equal(2, uniform.Sample(1249999));
            Assert.Equal(0, uniform.Sample(1250000));
        }

        [Fact]
        public void Timeline_NonuniformHalfOpenBoundariesSkipZeroDurationSlots()
        {
            var timeline = new IconTimeline(new[] { 0, 1, 2, 3 }, 24, new[] { 100, 0, 50, 50 });
            Assert.Equal(0, timeline.Sample(999999));
            Assert.Equal(2, timeline.Sample(1000000));
            Assert.Equal(3, timeline.Sample(1500000));
            Assert.Equal(0, timeline.Sample(2000000));
            Assert.Equal(2000000, timeline.PeriodTicks);
        }

        [Theory]
        [InlineData(double.NaN)]
        [InlineData(double.PositiveInfinity)]
        [InlineData(-1)]
        [InlineData(0)]
        [InlineData(1e-40)]
        public void Timeline_InvalidRatesFallBackWithoutOverflow(double fps)
        {
            Assert.Equal(1, new IconTimeline(new[] { 0, 1 }, fps).Sample(500000));
        }

        [Fact]
        public void CurrentPngFrame_KeepsHoldAndCanRehydrateAfterEviction()
        {
            Png("red.png", Color.Red); Png("blue.png", Color.Blue); Png("poster.png", Color.White);
            File.WriteAllText(Path.Combine(_root, "manifest.json"), "{\"a\":{\"f1\":\"poster.png\",\"fps\":2,\"frames\":[{\"uri\":\"red.png\"},{\"uri\":\"red.png\"},{\"uri\":\"blue.png\"}]},\"b\":{\"f1\":\"poster.png\"}}");
            using var catalog = new LootIconCatalog(_root, maxCacheBytes: 2 * 64L * 64 * 4);
            var a = catalog.DescribeForPlayback("a", true);
            Assert.True(a.Animated);
            Assert.Equal(a.Sample(0, true), a.Sample(5000000, true));
            Assert.NotEqual(a.Sample(0, true), a.Sample(10000000, true));
            Assert.Equal(Color.Red.ToArgb(), Draw(catalog, a, a.Sample(0, true)).ToArgb());
            Assert.Equal(Color.Blue.ToArgb(), Draw(catalog, a, a.Sample(10000000, true)).ToArgb());
            Draw(catalog, catalog.DescribeForPlayback("b", false), -1); // Evicts red.
            Assert.Equal(Color.Red.ToArgb(), Draw(catalog, a, a.Sample(0, true)).ToArgb());
        }

        [Fact]
        public void StaticPoster_DoesNotReadAnimatedSource_AndFailureIsRemembered()
        {
            Png("poster.png", Color.Green);
            File.WriteAllText(Path.Combine(_root, "broken.webp"), "not a WebP");
            File.WriteAllText(Path.Combine(_root, "manifest.json"), "{\"a\":{\"f1\":\"poster.png\",\"uri\":\"broken.webp\",\"format\":\"webp-animated\"}}");
            using var catalog = new LootIconCatalog(_root);
            var a = catalog.DescribeForPlayback("a", false);
            Assert.Equal(Color.Green.ToArgb(), Draw(catalog, a, -1).ToArgb());
            Assert.Equal(1, catalog.PlaybackFileOpens); // The poster alone was opened.
            Assert.Equal(0, catalog.PlaybackCodecCreations);
            catalog.DescribeForPlayback("a", true);
            Assert.False(a.Animated);
            long opens = catalog.PlaybackFileOpens;
            for (int i = 0; i < 20; i++) { catalog.DescribeForPlayback("a", true); Draw(catalog, a, -1); }
            Assert.Equal(opens, catalog.PlaybackFileOpens);
        }

        [Fact]
        public void MissingPngSlot_DoesNotShortenPeriod_AndBudgetFallbackUsesPoster()
        {
            Png("red.png", Color.Red); Png("poster.png", Color.White);
            File.WriteAllText(Path.Combine(_root, "manifest.json"), "{\"a\":{\"f1\":\"poster.png\",\"fps\":2,\"frames\":[{\"uri\":\"red.png\"},{\"uri\":null},{\"uri\":\"missing.png\"}]}}");
            using (var catalog = new LootIconCatalog(_root))
            {
                var a = catalog.DescribeForPlayback("a", true);
                Assert.Equal(15000000, a.Timeline.PeriodTicks);
                Assert.Equal(Color.White.ToArgb(), Draw(catalog, a, a.Sample(5000000, true)).ToArgb());
                Assert.Equal(Color.Red.ToArgb(), Draw(catalog, a, a.Sample(15000000, true)).ToArgb());
            }
            using (var catalog = new LootIconCatalog(_root, maxCacheBytes: 64L * 64 * 4))
            {
                var a = catalog.DescribeForPlayback("a", true);
                Assert.False(a.Animated);
                Assert.Equal(Color.White.ToArgb(), Draw(catalog, a, -1).ToArgb());
            }
        }

        [Fact]
        public void RepeatedSinglePictureUsesTimelinePicture_WithoutAnimationWakeups()
        {
            Png("red.png", Color.Red); Png("poster.png", Color.White);
            File.WriteAllText(Path.Combine(_root, "manifest.json"), "{\"a\":{\"f1\":\"poster.png\",\"fps\":24,\"frames\":[{\"uri\":\"red.png\"},{\"uri\":\"red.png\"}]}}");
            using var catalog = new LootIconCatalog(_root);
            var a = catalog.DescribeForPlayback("a", true);
            Assert.False(a.Animated);
            Assert.Equal(Color.Red.ToArgb(), Draw(catalog, a, a.Sample(0, true)).ToArgb());
            Assert.Equal(Color.White.ToArgb(), Draw(catalog, a, a.Sample(0, false)).ToArgb());
        }

        [Fact]
        public void CorruptPngFrameFallsBackOnce_WithoutRepeatedReads()
        {
            Png("red.png", Color.Red); Png("poster.png", Color.White);
            File.WriteAllText(Path.Combine(_root, "bad.png"), "corrupt image");
            File.WriteAllText(Path.Combine(_root, "manifest.json"), "{\"a\":{\"f1\":\"poster.png\",\"fps\":2,\"frames\":[{\"uri\":\"red.png\"},{\"uri\":\"bad.png\"}]}}");
            using var catalog = new LootIconCatalog(_root);
            var a = catalog.DescribeForPlayback("a", true);
            Assert.Equal(Color.White.ToArgb(), Draw(catalog, a, a.Sample(5000000, true)).ToArgb());
            Assert.False(a.Animated);
            long opens = catalog.PlaybackFileOpens;
            for (int i = 0; i < 20; i++) Draw(catalog, a, a.Sample(i * 320000L, true));
            Assert.Equal(opens, catalog.PlaybackFileOpens);
        }
    }
}
