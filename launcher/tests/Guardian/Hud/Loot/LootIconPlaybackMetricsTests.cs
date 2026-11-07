using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using CF7Launcher.Guardian.Hud.Loot;
using Newtonsoft.Json;
using Xunit;
using Xunit.Abstractions;

namespace CF7Launcher.Tests.Guardian.Hud.Loot
{
    public sealed class LootIconPlaybackMetricsTests
    {
        private readonly ITestOutputHelper _output;
        public LootIconPlaybackMetricsTests(ITestOutputHelper output) { _output = output; }
        internal static string FindIcons()
        {
            for (var dir = new DirectoryInfo(AppContext.BaseDirectory); dir != null; dir = dir.Parent)
            {
                string path = Path.Combine(dir.FullName, "launcher", "web", "icons");
                if (File.Exists(Path.Combine(path, "manifest.json"))) return path;
            }
            throw new DirectoryNotFoundException("Production icon manifest was not found");
        }

        [Theory]
        [InlineData("金钱", 32, 10560000L)]
        [InlineData("K点", 32, 13333334L)]
        [InlineData("强化石", 119, 50400000L)]
        public void RealTimelineMatchesContainerAndRetainsHalfOpenLoop(string name, int slots, long period)
        {
            using var catalog = new LootIconCatalog(FindIcons());
            var description = catalog.DescribeForPlayback(name, true);
            Assert.Equal(slots, description.Timeline.SlotCount);
            Assert.Equal(period, description.Timeline.PeriodTicks);
            Assert.Equal(description.Sample(0, true), description.Sample(period, true));
            Assert.Equal(description.Sample(0, true), description.Sample(period * 2, true));
            Assert.NotEqual(description.Sample(0, true), description.Sample(period - 1, true));
            if (name == "金钱")
            {
                Assert.Equal(13, description.Sample(4480000, true));
                Assert.Equal(13, description.Sample(4500000, true));
                Assert.Equal(13, description.Sample(4510000, true));
                Assert.Equal(30, description.Sample(10000000, true));
            }
            if (name == "强化石")
            {
                Assert.Equal(0, description.Sample(419999, true));
                Assert.Equal(1, description.Sample(420000, true));
                Assert.Equal(118, description.Sample(50399999, true));
                Assert.Equal(118, description.Sample(50000000, true)); // final frame holds for 84ms.
            }
        }

        [Theory]
        [InlineData(1)]
        [InlineData(5)]
        public void ResidentSamplingAndDrawing_DoNotReopenDecodeOrAllocateArrays(int count)
        {
            using var catalog = new LootIconCatalog(FindIcons());
            using var bitmap = new Bitmap(64, 64);
            using var graphics = Graphics.FromImage(bitmap);
            var destination = new Rectangle(0, 0, 64, 64);
            string[] names = { "金钱", "K点", "强化石", "金钱", "K点" };
            var descriptions = new LootIconCatalog.IconDescription[count];
            var cold = Stopwatch.StartNew();
            for (int i = 0; i < count; i++)
            {
                var d = descriptions[i] = catalog.DescribeForPlayback(names[i], true);
                for (long t = 0; t < d.Timeline.PeriodTicks; t += 100000)
                    Assert.True(catalog.TryDrawPlayback(graphics, destination, d, d.Sample(t, true), 1f));
            }
            cold.Stop();
            long opens = catalog.PlaybackFileOpens, codecs = catalog.PlaybackCodecCreations, decodes = catalog.PlaybackFullDecodes;
            const int iterations = 1000;
            var samples = new long[iterations];
            for (int i = 0; i < 100; i++) descriptions[0].Sample(i * 320000L, true); // JIT/tiering warmup.
            long allocated = GC.GetAllocatedBytesForCurrentThread();
            int gen0 = GC.CollectionCount(0);
            for (int i = 0; i < iterations; i++)
            {
                long start = Stopwatch.GetTimestamp();
                for (int n = 0; n < count; n++)
                {
                    var d = catalog.DescribeForPlayback(names[n], true);
                    int frame = d.Sample(i * 320000L + n * 170000L, true);
                    catalog.TryDrawPlayback(graphics, destination, d, frame, 1f);
                }
                samples[i] = Stopwatch.GetTimestamp() - start;
            }
            allocated = GC.GetAllocatedBytesForCurrentThread() - allocated;
            Assert.Equal(opens, catalog.PlaybackFileOpens);
            Assert.Equal(codecs, catalog.PlaybackCodecCreations);
            Assert.Equal(decodes, catalog.PlaybackFullDecodes);
            Assert.Equal(0, allocated);
            Array.Sort(samples);
            double sum = 0; foreach (long ticks in samples) sum += ticks;
            _output.WriteLine("LOOT_PLAYBACK_METRICS " + JsonConvert.SerializeObject(new {
                count, iterations, coldPreparationAndAllFramesMs = cold.Elapsed.TotalMilliseconds,
                coldFileOpens = opens, coldCodecs = codecs, coldFullDecodes = decodes,
                warmFileOpens = catalog.PlaybackFileOpens - opens, warmCodecs = catalog.PlaybackCodecCreations - codecs,
                warmFullDecodes = catalog.PlaybackFullDecodes - decodes, warmAllocatedBytes = allocated,
                gen0 = GC.CollectionCount(0) - gen0, meanUs = sum / iterations * 1e6 / Stopwatch.Frequency,
                p95Us = samples[949] * 1e6 / Stopwatch.Frequency, p99Us = samples[989] * 1e6 / Stopwatch.Frequency,
                boundary = "catalog prepare/sample/resident DrawImage; excludes Overlay commit and GPU upload"
            }));
        }

        [DllImport("user32.dll")] private static extern int GetGuiResources(IntPtr process, int flags);
        [Fact]
        public void RepeatedDecodeEvictDispose_ReleasesNativeImagesAndGdiObjects()
        {
            void Cycle()
            {
                using var catalog = new LootIconCatalog(FindIcons());
                using var bitmap = new Bitmap(64, 64);
                using var g = Graphics.FromImage(bitmap);
                var description = catalog.DescribeForPlayback("金钱", true);
                Assert.True(catalog.TryDrawPlayback(g, new Rectangle(0, 0, 64, 64), description, 0, 1f));
            }
            void Collect() { GC.Collect(); GC.WaitForPendingFinalizers(); GC.Collect(); }
            for (int i = 0; i < 5; i++) Cycle(); Collect();
            using var process = Process.GetCurrentProcess(); process.Refresh();
            int gdi = GetGuiResources(process.Handle, 0), handles = process.HandleCount;
            long memory = process.PrivateMemorySize64;
            for (int i = 0; i < 30; i++) Cycle(); Collect(); process.Refresh();
            int finalGdi = GetGuiResources(process.Handle, 0), finalHandles = process.HandleCount;
            _output.WriteLine("LOOT_DISPOSAL_METRICS " + JsonConvert.SerializeObject(new {
                cycles = 30, gdiBefore = gdi, gdiAfter = finalGdi, handlesBefore = handles, handlesAfter = finalHandles,
                privateBytesBefore = memory, privateBytesAfter = process.PrivateMemorySize64
            }));
            Assert.InRange(finalGdi, 0, gdi + 5);
            Assert.InRange(finalHandles, 0, handles + 20);
        }
    }
}
