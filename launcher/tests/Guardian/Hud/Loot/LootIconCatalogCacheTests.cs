using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using CF7Launcher.Guardian.Hud.Loot;
using Xunit;

namespace CF7Launcher.Tests.Guardian.Hud.Loot
{
    public class LootIconCatalogCacheTests
    {
        private const long OneFrameBudget = 64L * 64L * 4L;

        [Fact]
        public void TryGet_AfterFrameEviction_RehydratesInsteadOfReturningDisposedBitmap()
        {
            string dir = Path.Combine(Path.GetTempPath(),
                "cf7-looticon-cache-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(dir);
            try
            {
                WritePng(Path.Combine(dir, "a.png"), Color.Red);
                WritePng(Path.Combine(dir, "b.png"), Color.Blue);
                File.WriteAllText(Path.Combine(dir, "manifest.json"),
                    "{\"图标A\":{\"f1\":\"a.png\"},\"图标B\":{\"f1\":\"b.png\"}}");

                using (var catalog = new LootIconCatalog(dir, maxCacheBytes: OneFrameBudget))
                {
                    LootIconCatalog.LootIconFrames firstA;
                    LootIconCatalog.LootIconFrames framesB;
                    LootIconCatalog.LootIconFrames reloadedA;

                    Assert.True(catalog.TryGet("图标A", out firstA));
                    Bitmap evicted = firstA.First;

                    Assert.True(catalog.TryGet("图标B", out framesB));
                    Assert.True(catalog.TryGet("图标A", out reloadedA));

                    Assert.NotSame(evicted, reloadedA.First);
                    Assert.Equal(LootIconCatalog.ThumbSize, reloadedA.First.Width);
                    Assert.Equal(LootIconCatalog.ThumbSize, reloadedA.First.Height);
                }
            }
            finally
            {
                Directory.Delete(dir, true);
            }
        }

        [Fact]
        public void Constructor_CacheSmallerThanOneFrame_IsRejected()
        {
            Assert.Throws<ArgumentOutOfRangeException>(() =>
                new LootIconCatalog("unused", maxCacheBytes: OneFrameBudget - 1));
        }

        [Fact]
        public void TryGet_PngSequenceExceedingBudget_FallsBackToLiveStaticFrame()
        {
            string dir = Path.Combine(Path.GetTempPath(),
                "cf7-looticon-cache-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(dir);
            try
            {
                WritePng(Path.Combine(dir, "a.png"), Color.Red);
                WritePng(Path.Combine(dir, "b.png"), Color.Blue);
                File.WriteAllText(Path.Combine(dir, "manifest.json"),
                    "{\"动画\":{\"f1\":\"a.png\",\"format\":\"png-sequence\",\"frames\":[{\"uri\":\"a.png\"},{\"uri\":\"b.png\"}]}}");

                using (var catalog = new LootIconCatalog(dir, maxCacheBytes: OneFrameBudget))
                {
                    LootIconCatalog.LootIconFrames frames;
                    Assert.True(catalog.TryGet("动画", out frames));
                    Assert.False(frames.Animated);
                    Assert.Single(frames.Frames);
                    Assert.Equal(LootIconCatalog.ThumbSize, frames.First.Width);
                }
            }
            finally
            {
                Directory.Delete(dir, true);
            }
        }

        [Fact]
        public void TryGet_PngSequenceRepeatedUri_CountsOneOwnedFrame()
        {
            string dir = Path.Combine(Path.GetTempPath(),
                "cf7-looticon-cache-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(dir);
            try
            {
                WritePng(Path.Combine(dir, "hold.png"), Color.Green);
                File.WriteAllText(Path.Combine(dir, "manifest.json"),
                    "{\"停顿\":{\"f1\":\"hold.png\",\"format\":\"png-sequence\",\"frames\":[{\"uri\":\"hold.png\"},{\"uri\":\"hold.png\"}]}}");

                using (var catalog = new LootIconCatalog(dir, maxCacheBytes: OneFrameBudget))
                {
                    LootIconCatalog.LootIconFrames frames;
                    Assert.True(catalog.TryGet("停顿", out frames));
                    Assert.True(frames.Animated);
                    Assert.Equal(2, frames.Frames.Length);
                    Assert.Same(frames.Frames[0], frames.Frames[1]);
                    Assert.Equal(LootIconCatalog.ThumbSize, frames.First.Width);
                }
            }
            finally
            {
                Directory.Delete(dir, true);
            }
        }

        private static void WritePng(string path, Color color)
        {
            using (Bitmap bitmap = new Bitmap(16, 16, PixelFormat.Format32bppArgb))
            using (Graphics graphics = Graphics.FromImage(bitmap))
            {
                graphics.Clear(color);
                bitmap.Save(path, ImageFormat.Png);
            }
        }
    }
}
