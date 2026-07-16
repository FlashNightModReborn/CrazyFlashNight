using System;
using System.Drawing;
using CF7Launcher.Guardian.Hud;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public class BitmapLruCacheTests
    {
        [Fact]
        public void TryAdd_EvictsLeastRecentlyUsedByDecodedBytes()
        {
            using (BitmapLruCache cache = new BitmapLruCache(800, StringComparer.Ordinal))
            {
                Assert.True(cache.TryAdd("a", new Bitmap(10, 10))); // 400 bytes
                Assert.True(cache.TryAdd("b", new Bitmap(10, 10))); // 400 bytes
                Bitmap hit;
                Assert.True(cache.TryGet("a", out hit));            // a becomes MRU
                Assert.True(cache.TryAdd("c", new Bitmap(10, 10))); // evicts b

                Assert.False(cache.TryGet("b", out hit));
                Assert.True(cache.TryGet("a", out hit));
                Assert.True(cache.TryGet("c", out hit));
                Assert.Equal(800, cache.CurrentBytes);
                Assert.Equal(2, cache.Count);
            }
        }

        [Fact]
        public void TryAdd_RejectsSingleBitmapLargerThanBudget()
        {
            using (BitmapLruCache cache = new BitmapLruCache(399, StringComparer.Ordinal))
            using (Bitmap bitmap = new Bitmap(10, 10))
            {
                Assert.False(cache.TryAdd("oversize", bitmap));
                Assert.Equal(0, cache.CurrentBytes);
                Assert.Equal(0, cache.Count);
            }
        }
    }
}
