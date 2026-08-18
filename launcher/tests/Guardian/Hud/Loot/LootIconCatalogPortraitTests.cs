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
