using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using Xunit;
using CF7Launcher.Guardian.Hud.Loot;

namespace CF7Launcher.Tests.Guardian.Hud.Loot
{
    /// <summary>
    /// LootIconCatalog 第四源（运行时纸娃娃胸像库，"纸娃娃-&lt;hex&gt;" ref →
    /// launcher/data/doll-portraits/&lt;hex&gt;.png）：fixture PNG 命中/64px/静态、
    /// 未知键 false、键校验（路径穿越防护）、负缓存 2000ms TTL 到期重探与
    /// InvalidateDoll 主动失效立即重探（NowMs 时钟注入，对齐 LootFeedModel 的 nowMs 风格），
    /// 以及物品/敌人头像两源回归不受第四源接线影响。
    /// </summary>
    public class LootIconCatalogDollTests
    {
        private const string DollHex = "8a44ae89";
        private const string DollRef = "纸娃娃-" + DollHex;

        private static string CreateTempDir()
        {
            string dir = Path.Combine(Path.GetTempPath(), "cf7-doll-catalog-test-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(dir);
            return dir;
        }

        private static void WriteFixturePng(string path)
        {
            using (Bitmap bmp = new Bitmap(256, 256, PixelFormat.Format32bppArgb))
            using (Graphics g = Graphics.FromImage(bmp))
            {
                g.Clear(Color.FromArgb(255, 30, 120, 200));
                bmp.Save(path, ImageFormat.Png);
            }
        }

        private static string FindProjectSubdir(string relative)
        {
            DirectoryInfo dir = new DirectoryInfo(AppContext.BaseDirectory);
            while (dir != null)
            {
                string candidate = Path.Combine(dir.FullName, relative);
                if (Directory.Exists(candidate)) return candidate;
                dir = dir.Parent;
            }
            throw new DirectoryNotFoundException(relative + " not found above " + AppContext.BaseDirectory);
        }

        [Fact]
        public void TryGet_DollRef_LoadsPngAsStaticThumb()
        {
            string iconsDir = CreateTempDir();
            string dollDir = CreateTempDir();
            try
            {
                WriteFixturePng(Path.Combine(dollDir, DollHex + ".png"));
                using (var catalog = new LootIconCatalog(iconsDir, dollPortraitsDir: dollDir))
                {
                    LootIconCatalog.LootIconFrames frames;
                    Assert.True(catalog.TryGet(DollRef, out frames));
                    Assert.NotNull(frames);
                    Assert.False(frames.Animated); // 运行时胸像为静态单帧
                    Assert.NotNull(frames.First);
                    Assert.Equal(LootIconCatalog.ThumbSize, frames.First.Width);
                    Assert.Equal(LootIconCatalog.ThumbSize, frames.First.Height);
                }
            }
            finally
            {
                Directory.Delete(iconsDir, true);
                Directory.Delete(dollDir, true);
            }
        }

        [Fact]
        public void TryGet_UnknownDollRef_Rejected()
        {
            string iconsDir = CreateTempDir();
            string dollDir = CreateTempDir();
            try
            {
                using (var catalog = new LootIconCatalog(iconsDir, dollPortraitsDir: dollDir))
                {
                    LootIconCatalog.LootIconFrames frames;
                    Assert.False(catalog.TryGet("纸娃娃-00000000", out frames));
                    Assert.Null(frames);
                }
            }
            finally
            {
                Directory.Delete(iconsDir, true);
                Directory.Delete(dollDir, true);
            }
        }

        [Theory]
        [InlineData("纸娃娃-../../evil")]
        [InlineData("纸娃娃-ABCDEF12")] // 大写非法
        [InlineData("纸娃娃-123")]      // 长度不足
        public void TryGet_MalformedDollRef_Rejected(string badRef)
        {
            string iconsDir = CreateTempDir();
            string dollDir = CreateTempDir();
            try
            {
                using (var catalog = new LootIconCatalog(iconsDir, dollPortraitsDir: dollDir))
                {
                    LootIconCatalog.LootIconFrames frames;
                    Assert.False(catalog.TryGet(badRef, out frames));
                    Assert.Null(frames);
                }
            }
            finally
            {
                Directory.Delete(iconsDir, true);
                Directory.Delete(dollDir, true);
            }
        }

        [Fact]
        public void TryGet_DollMiss_NegativeCacheTtlAllowsReprobe()
        {
            string iconsDir = CreateTempDir();
            string dollDir = CreateTempDir();
            try
            {
                using (var catalog = new LootIconCatalog(iconsDir, dollPortraitsDir: dollDir))
                {
                    long now = 100000;
                    catalog.NowMs = () => now;
                    LootIconCatalog.LootIconFrames frames;

                    // t0：文件未落盘 → miss（进 TTL 负缓存）
                    Assert.False(catalog.TryGet(DollRef, out frames));

                    // 烘焙完成：文件落盘，但 TTL 未到期 → 仍判 miss
                    WriteFixturePng(Path.Combine(dollDir, DollHex + ".png"));
                    now += LootIconCatalog.DollMissTtlMs - 1;
                    Assert.False(catalog.TryGet(DollRef, out frames));

                    // TTL 到期 → 重探命中
                    now += 2;
                    Assert.True(catalog.TryGet(DollRef, out frames));
                    Assert.NotNull(frames);
                    Assert.False(frames.Animated);
                }
            }
            finally
            {
                Directory.Delete(iconsDir, true);
                Directory.Delete(dollDir, true);
            }
        }

        [Fact]
        public void InvalidateDoll_AllowsImmediateReprobeBeforeTtl()
        {
            string iconsDir = CreateTempDir();
            string dollDir = CreateTempDir();
            try
            {
                using (var catalog = new LootIconCatalog(iconsDir, dollPortraitsDir: dollDir))
                {
                    long now = 100000;
                    catalog.NowMs = () => now;
                    LootIconCatalog.LootIconFrames frames;

                    // t0：文件未落盘 → miss（进 TTL 负缓存）
                    Assert.False(catalog.TryGet(DollRef, out frames));

                    // 烘焙完成：文件落盘 + 完成通知失效负缓存 → TTL 未到期也立即命中
                    WriteFixturePng(Path.Combine(dollDir, DollHex + ".png"));
                    catalog.InvalidateDoll(DollRef);
                    Assert.True(catalog.TryGet(DollRef, out frames));
                    Assert.NotNull(frames);

                    // 空/null ref 静默不抛（widget 通知路径的防御）
                    catalog.InvalidateDoll(null);
                    catalog.InvalidateDoll("");
                }
            }
            finally
            {
                Directory.Delete(iconsDir, true);
                Directory.Delete(dollDir, true);
            }
        }

        [Fact]
        public void TryGet_ItemAndEnemyPortraitUnaffectedByDollFallback()
        {
            string dollDir = CreateTempDir();
            try
            {
                string iconsDir = FindProjectSubdir(Path.Combine("launcher", "web", "icons"));
                string portraitsDir = FindProjectSubdir(Path.Combine("launcher", "web", "assets", "enemy-portraits"));
                using (var catalog = new LootIconCatalog(iconsDir, portraitsDir,
                    dollPortraitsDir: dollDir))
                {
                    // 物品图标优先走物品 manifest；金钱为 png-sequence 动画
                    LootIconCatalog.LootIconFrames frames;
                    Assert.True(catalog.TryGet("金钱", out frames));
                    Assert.NotNull(frames);
                    Assert.True(frames.Animated);

                    // 敌人头像在 doll 之前解析
                    Assert.True(catalog.TryGet("敌人-92式终结者", out frames));
                    Assert.NotNull(frames);
                    Assert.False(frames.Animated);
                }
            }
            finally
            {
                Directory.Delete(dollDir, true);
            }
        }
    }
}
