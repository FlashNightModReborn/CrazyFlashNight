using System;
using System.Drawing;
using System.IO;
using Xunit;
using CF7Launcher.Guardian.Hud.Loot;
namespace CF7Launcher.Tests.Guardian.Hud.Loot
{
    /// <summary>
    /// 敌人头像库（launcher/web/assets/enemy-portraits）解析的真实资产测试。
    /// 定位策略与 LootIconCatalogWebpTests 一致：从 BaseDirectory 向上找库根。
    /// </summary>
    public class LootIconCatalogPortraitTests
    {
        private const string PortraitRef = "敌人-92式终结者";
        private const string AliasRef = "敌人-拟态投影"; // manifest aliases → 敌人-方舟妖姬

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

        private static LootIconCatalog NewCatalog()
        {
            string iconsDir = FindProjectSubdir(Path.Combine("launcher", "web", "icons"));
            string portraitsDir = FindProjectSubdir(Path.Combine("launcher", "web", "assets", "enemy-portraits"));
            return new LootIconCatalog(iconsDir, portraitsDir);
        }

        [Fact]
        public void TryGet_PortraitRef_RasterizesSvgToStaticThumb()
        {
            using (LootIconCatalog catalog = NewCatalog())
            {
                LootIconCatalog.LootIconFrames frames;
                Assert.True(catalog.TryGet(PortraitRef, out frames));
                Assert.NotNull(frames);
                Assert.False(frames.Animated); // 头像为静态单帧
                Assert.NotNull(frames.First);
                Assert.Equal(LootIconCatalog.ThumbSize, frames.First.Width);
                Assert.Equal(LootIconCatalog.ThumbSize, frames.First.Height);
            }
        }

        [Theory]
        [InlineData("敌人-前治安官")]
        [InlineData("敌人-Codex黑仔")]
        [InlineData("敌人-制式军警犬")]
        [InlineData("敌人-盗贼撕咬犬")]
        [InlineData("敌人-军阀铁卫犬")]
        public void TryGet_DirectPortrait_RendersVisibleImageWithTransparency(string portraitRef)
        {
            using (LootIconCatalog catalog = NewCatalog())
            {
                LootIconCatalog.LootIconFrames frames;
                Assert.True(catalog.TryGet(portraitRef, out frames));
                Assert.False(frames.Animated);
                Assert.Equal(LootIconCatalog.ThumbSize, frames.First.Width);
                Assert.Equal(LootIconCatalog.ThumbSize, frames.First.Height);

                // 内嵌 PNG 的 SVG 必须实际解码，不能只返回全透明画布或错误占位。
                int coloredPixels = 0;
                int transparentPixels = 0;
                for (int y = 0; y < frames.First.Height; y++)
                {
                    for (int x = 0; x < frames.First.Width; x++)
                    {
                        Color pixel = frames.First.GetPixel(x, y);
                        if (pixel.A == 0) transparentPixels++;
                        int brightest = Math.Max(pixel.R, Math.Max(pixel.G, pixel.B));
                        int darkest = Math.Min(pixel.R, Math.Min(pixel.G, pixel.B));
                        if (pixel.A >= 192 && brightest - darkest > 30) coloredPixels++;
                    }
                }
                Assert.True(coloredPixels > 64, "Portrait image was not decoded.");
                Assert.True(transparentPixels > 128, "Portrait transparency was lost.");
                string outputDir = Environment.GetEnvironmentVariable("CF7_TEST_PORTRAIT_OUTPUT");
                if (!string.IsNullOrEmpty(outputDir))
                {
                    Directory.CreateDirectory(outputDir);
                    frames.First.Save(Path.Combine(outputDir, portraitRef + ".png"),
                        System.Drawing.Imaging.ImageFormat.Png);
                }
            }
        }

        [Fact]
        public void TryGet_PortraitAlias_ResolvesToTarget()
        {
            using (LootIconCatalog catalog = NewCatalog())
            {
                LootIconCatalog.LootIconFrames frames;
                Assert.True(catalog.TryGet(AliasRef, out frames));
                Assert.NotNull(frames.First);
            }
        }

        [Fact]
        public void TryGet_UnknownRef_Rejected()
        {
            using (LootIconCatalog catalog = NewCatalog())
            {
                LootIconCatalog.LootIconFrames frames;
                Assert.False(catalog.TryGet("敌人-不存在的单位", out frames));
                Assert.Null(frames);
            }
        }

        [Fact]
        public void TryGet_ItemIconUnaffectedByPortraitFallback()
        {
            using (LootIconCatalog catalog = NewCatalog())
            {
                // 物品图标优先走物品 manifest；金钱为 png-sequence 动画
                LootIconCatalog.LootIconFrames frames;
                Assert.True(catalog.TryGet("金钱", out frames));
                Assert.NotNull(frames);
                Assert.True(frames.Animated);
            }
        }

        [Fact]
        public void StripSvgFilters_RemovesFilterDefsAndReferences()
        {
            string svg = "<svg><defs><filter id=\"f1\"><feGaussianBlur/></filter><filter id=\"f2\"/></defs>"
                + "<g filter=\"url(#f1)\"><rect width=\"10\" height=\"10\" filter='url(#f2)'/></g></svg>";
            string stripped = LootIconCatalog.StripSvgFilters(svg);

            Assert.DoesNotContain("<filter", stripped);
            Assert.DoesNotContain("url(#f1)", stripped);
            Assert.DoesNotContain("url(#f2)", stripped);
            Assert.Contains("<rect width=\"10\" height=\"10\"", stripped);
        }

        [Fact]
        public void StripSvgFilters_KeepsNonFilterContentIntact()
        {
            string svg = "<svg><linearGradient id=\"g\"/><use href=\"#shape0\" filter=\"none\"/></svg>";
            string stripped = LootIconCatalog.StripSvgFilters(svg);

            Assert.Contains("linearGradient", stripped);
            Assert.Contains("filter=\"none\"", stripped); // 非 url(#) 引用不动
        }
    }
}
