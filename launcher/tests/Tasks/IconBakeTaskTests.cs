using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
using CF7Launcher.Tasks;
using Xunit;

namespace CF7Launcher.Tests.Tasks
{
    public class IconBakeTaskTests
    {
        [Fact]
        public void ShouldTreatExistingPngAsUnchanged_WhenPixelsAreExact()
        {
            string dir = CreateTempDir();
            try
            {
                string path = Path.Combine(dir, "icon.png");
                byte[] bgra = CreateBaseIcon();
                SaveBgraPng(path, bgra);

                IconBakeTask.IconBakePixelDiffStats stats;
                bool unchanged = IconBakeTask.ShouldTreatExistingPngAsUnchanged(path, (byte[])bgra.Clone(), out stats);

                Assert.True(unchanged);
                Assert.True(stats.ExactPixels);
                Assert.False(stats.IsMicroDiff);
                Assert.Equal(0, stats.ChangedPixels);
            }
            finally
            {
                Directory.Delete(dir, true);
            }
        }

        [Fact]
        public void ShouldTreatExistingPngAsUnchanged_WhenDiffIsMicroJitter()
        {
            string dir = CreateTempDir();
            try
            {
                string path = Path.Combine(dir, "icon.png");
                byte[] bgra = CreateBaseIcon();
                SaveBgraPng(path, bgra);

                byte[] jittered = (byte[])bgra.Clone();
                AddToChannel(jittered, 20, 20, 0, 12);
                AddToChannel(jittered, 21, 20, 1, 8);
                AddToChannel(jittered, 20, 21, 2, 6);

                IconBakeTask.IconBakePixelDiffStats stats;
                bool unchanged = IconBakeTask.ShouldTreatExistingPngAsUnchanged(path, jittered, out stats);

                Assert.True(unchanged);
                Assert.False(stats.ExactPixels);
                Assert.True(stats.IsMicroDiff);
                Assert.Equal(3, stats.ChangedPixels);
                Assert.Equal(12, stats.MaxChannelDelta);
            }
            finally
            {
                Directory.Delete(dir, true);
            }
        }

        [Fact]
        public void ShouldTreatExistingPngAsChanged_WhenSinglePixelDeltaIsLarge()
        {
            string dir = CreateTempDir();
            try
            {
                string path = Path.Combine(dir, "icon.png");
                byte[] bgra = CreateBaseIcon();
                SaveBgraPng(path, bgra);

                byte[] changed = (byte[])bgra.Clone();
                AddToChannel(changed, 20, 20, 0, 128);

                IconBakeTask.IconBakePixelDiffStats stats;
                bool unchanged = IconBakeTask.ShouldTreatExistingPngAsUnchanged(path, changed, out stats);

                Assert.False(unchanged);
            }
            finally
            {
                Directory.Delete(dir, true);
            }
        }

        [Fact]
        public void ShouldTreatExistingPngAsChanged_WhenTooManyPixelsMove()
        {
            string dir = CreateTempDir();
            try
            {
                string path = Path.Combine(dir, "icon.png");
                byte[] bgra = CreateBaseIcon();
                SaveBgraPng(path, bgra);

                byte[] changed = (byte[])bgra.Clone();
                for (int i = 0; i < 513; i++)
                {
                    AddToChannel(changed, i % 256, i / 256, 2, 1);
                }

                IconBakeTask.IconBakePixelDiffStats stats;
                bool unchanged = IconBakeTask.ShouldTreatExistingPngAsUnchanged(path, changed, out stats);

                Assert.False(unchanged);
            }
            finally
            {
                Directory.Delete(dir, true);
            }
        }

        private static string CreateTempDir()
        {
            string dir = Path.Combine(Path.GetTempPath(), "cf7-icon-bake-test-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(dir);
            return dir;
        }

        private static byte[] CreateBaseIcon()
        {
            byte[] bgra = new byte[256 * 256 * 4];
            for (int y = 16; y < 48; y++)
            {
                for (int x = 16; x < 48; x++)
                {
                    int i = (y * 256 + x) * 4;
                    bgra[i] = 40;
                    bgra[i + 1] = 120;
                    bgra[i + 2] = 220;
                    bgra[i + 3] = 255;
                }
            }
            return bgra;
        }

        private static void AddToChannel(byte[] bgra, int x, int y, int channel, int delta)
        {
            int i = (y * 256 + x) * 4 + channel;
            bgra[i] = (byte)Math.Min(255, bgra[i] + delta);
        }

        private static void SaveBgraPng(string path, byte[] bgra)
        {
            using (Bitmap bmp = new Bitmap(256, 256, PixelFormat.Format32bppArgb))
            {
                BitmapData data = bmp.LockBits(
                    new Rectangle(0, 0, 256, 256),
                    ImageLockMode.WriteOnly,
                    PixelFormat.Format32bppArgb);
                try
                {
                    Marshal.Copy(bgra, 0, data.Scan0, bgra.Length);
                }
                finally
                {
                    bmp.UnlockBits(data);
                }

                bmp.Save(path, ImageFormat.Png);
            }
        }
    }
}
