using System;
using System.IO;
using System.Linq;
using System.Text.Json.Nodes;
using CF7Launcher.Guardian.WorldCompositor;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class BulletVisualCatalogTests
    {
        [Fact]
        public void TwoSharedTrianglesAndSixPiercingSpritesRetainTheirAuthoredRegistration()
        {
            var catalog = BulletVisualCatalog.Load(ProjectRoot());
            Assert.Equal(8, catalog.Styles.Count);
            Assert.Equal(6, catalog.GunChainPrefixes.Count);
            Assert.True(catalog.TryOrdinary("普通子弹", out var plain));
            Assert.True(catalog.TryOrdinary("加强普通子弹", out var enhanced));
            Assert.Equal("单元体-普通子弹", plain.GunChainUnitLinkage);
            Assert.Equal("单元体-加强普通子弹", enhanced.GunChainUnitLinkage);
            Assert.Equal(0, plain.GlowX);
            Assert.Equal(8, enhanced.GlowX);
            Assert.Equal(25.25f, plain.VerticesPx[2]);
            Assert.Equal(-0.9f, plain.VerticesPx[3]);
            foreach (string prefix in catalog.GunChainPrefixes)
            {
                Assert.True(catalog.TryGunChain(prefix + "-普通子弹", out var chainPlain));
                Assert.Same(plain, chainPlain);
                Assert.True(catalog.TryGunChain(prefix + "-加强普通子弹", out var chainEnhanced));
                Assert.Same(enhanced, chainEnhanced);
            }
            string[] families = { "穿刺子弹", "次级穿刺子弹", "无壳穿刺子弹" };
            for (int i = 0; i < families.Length; i++)
            {
                Assert.True(catalog.TryOrdinary(families[i], out var ordinary));
                Assert.Same(catalog.Styles[i + 2], ordinary);
                Assert.True(ordinary.IsSprite);
                Assert.Null(ordinary.GunChainUnitLinkage);
                foreach (string prefix in catalog.GunChainPrefixes)
                {
                    Assert.True(catalog.TryGunChain(prefix + "-" + families[i], out var chain));
                    Assert.Same(catalog.Styles[i + 5], chain);
                    Assert.True(chain.IsSprite);
                    Assert.Null(chain.OrdinaryLinkage);
                    Assert.NotSame(ordinary, chain);
                }
            }
            Assert.Equal(6.75f, catalog.Styles[6].Sprite.OffsetX - catalog.Styles[3].Sprite.OffsetX, 4);
            Assert.Equal(.95f, catalog.Styles[6].Sprite.OffsetY - catalog.Styles[3].Sprite.OffsetY, 4);
            Assert.True(catalog.Styles[5].Sprite.Height > 8 && catalog.Styles[7].Sprite.Height > 8,
                "The authored glows must survive rasterization beyond the thin chain-unit geometry bounds.");
            Assert.Equal(catalog.AtlasWidth * catalog.AtlasHeight * 4, catalog.AtlasBgraPremultiplied.Length);
            Assert.Contains(catalog.AtlasBgraPremultiplied, b => b != 0);
            Assert.False(catalog.TryGunChain("横向拖尾联弹-普通子弹", out _));
        }

        [Theory]
        [InlineData("rect")]
        [InlineData("scale")]
        [InlineData("unmapped")]
        [InlineData("duplicate")]
        [InlineData("atlas-hash")]
        public void SpriteCatalogRejectsBrokenGeometryIdentityAndAtlasIntegrity(string mutation)
        {
            string root = ProjectRoot();
            string fixture = Path.Combine(Path.GetTempPath(), "cf7-bullet-catalog-" + Guid.NewGuid().ToString("N"));
            try
            {
                foreach (string path in new[] { BulletVisualCatalog.RelativePath, BulletVisualCatalog.SourceSwf, BulletVisualCatalog.AtlasPath })
                {
                    string target = Path.Combine(fixture, path);
                    Directory.CreateDirectory(Path.GetDirectoryName(target));
                    File.Copy(Path.Combine(root, path), target);
                }
                string catalogPath = Path.Combine(fixture, BulletVisualCatalog.RelativePath);
                JsonNode document = JsonNode.Parse(File.ReadAllText(catalogPath));
                JsonNode style = document["styles"][2];
                if (mutation == "rect") style["visual"]["atlasRectPx"][0] = 1024;
                if (mutation == "scale") style["visual"]["sizePx"][0] = 1;
                if (mutation == "unmapped") style["ordinaryLinkage"] = null;
                if (mutation == "duplicate") style["ordinaryLinkage"] = "普通子弹";
                if (mutation == "atlas-hash") document["atlas"]["sha256"] = new string('0', 64);
                File.WriteAllText(catalogPath, document.ToJsonString());
                Assert.Throws<InvalidDataException>(() => BulletVisualCatalog.Load(fixture));
            }
            finally
            {
                var directory = new DirectoryInfo(fixture);
                string temporaryRoot = Path.GetFullPath(Path.GetTempPath()).TrimEnd(Path.DirectorySeparatorChar);
                if (directory.Exists && directory.Parent != null
                    && string.Equals(directory.Parent.FullName, temporaryRoot, StringComparison.OrdinalIgnoreCase)
                    && directory.Name.StartsWith("cf7-bullet-catalog-", StringComparison.Ordinal))
                    directory.Delete(true);
            }
        }

        [Fact]
        public void VisualFrameAcceptsBoundedCompleteSnapshotAndRejectsMalformedValues()
        {
            string valid = "2|120|1|1|0;0,10,20,0,100,100,100;1,30,40,15,100,100,80";
            Assert.True(BulletVisualFrame.TryParse(valid, 2, out var frame));
            Assert.False(frame.NativeOwned);
            Assert.Equal(2, frame.Epoch);
            Assert.Equal(120, frame.Frame);
            Assert.Equal(1, frame.NormalCount);
            Assert.Equal(1, frame.ChainCount);
            Assert.Equal(2, frame.Instances.Length);
            Assert.Equal(30, frame.Instances[1].X);
            Assert.True(BulletVisualFrame.TryParse("2|121|0|0|0", 2, out var empty));
            Assert.Empty(empty.Instances);
            Assert.True(BulletVisualFrame.TryParse("2|122|1|0|0|1;1,30,40,0,100,100,100", 2,
                out var native));
            Assert.True(native.NativeOwned);
            Assert.False(BulletVisualFrame.TryParse("2|122|1|0|0|2;1,30,40,0,100,100,100", 2, out _));
            Assert.False(BulletVisualFrame.TryParse(valid.Replace("1,30", "2,30"), 2, out _));
            Assert.False(BulletVisualFrame.TryParse(valid.Replace("30,40", "NaN,40"), 2, out _));
            Assert.False(BulletVisualFrame.TryParse(valid.Replace("1|1|0", "1|2|0"), 2, out _));
            Assert.False(BulletVisualFrame.TryParse(valid + ";", 2, out _));
        }

        [Fact]
        public void CombinedNormalAndChainVisualItemsRespectTheSharedBudget()
        {
            string entries = string.Join(";", Enumerable.Repeat("0,10,20,0,100,100,100", 1024));
            Assert.True(BulletVisualFrame.TryParse("1|200|1024|0|0|1;" + entries, 2,
                out var full));
            Assert.Equal(1024, full.Instances.Length);
            Assert.Equal(1024, full.NormalCount);
            Assert.Equal(0, full.ChainCount);
            // Ordinary snapshots stop at the shared 1024 budget instead of the old 256 cap.
            Assert.False(BulletVisualFrame.TryParse(
                "1|201|1025|0|0|1;" + entries + ";0,10,20,0,100,100,100", 2, out _));
            // Packets without the ownership flag still parse but never authorize native drawing.
            Assert.True(BulletVisualFrame.TryParse("1|202|1|0|0;0,10,20,0,100,100,100", 2,
                out var shadow));
            Assert.False(shadow.NativeOwned);
        }

        [Fact]
        public void ShadowCoverageSeparatesNormalAndChainForEachVisualStyle()
        {
            var shadow = new BulletVisualShadow(BulletVisualCatalog.Load(ProjectRoot()));
            Assert.NotNull(shadow.Observe("1|100|1|1|0;0,10,20,0,100,100,100;1,30,40,0,100,100,100", 7));
            string firstCoverage = shadow.CoverageForTests();
            Assert.StartsWith("normal.plain=1/1,chain.plain=0/0,normal.enhanced=0/0,chain.enhanced=1/1,", firstCoverage);
            Assert.Contains("normal.secondary-pierce=0/0", firstCoverage);
            Assert.Null(shadow.Observe("1|100|1|1|0;0,10,20,0,100,100,100;1,30,40,0,100,100,100", 7));
            Assert.Equal(firstCoverage, shadow.CoverageForTests());
            shadow.ResetIfGeneration(6);
            Assert.Contains("chain.enhanced=1/1", shadow.CoverageForTests());
            shadow.ResetIfGeneration(7);
            Assert.Contains("chain.enhanced=0/0", shadow.CoverageForTests());
        }

        private static string ProjectRoot()
        {
            for (var directory = new DirectoryInfo(AppContext.BaseDirectory);
                 directory != null; directory = directory.Parent)
            {
                if (File.Exists(Path.Combine(directory.FullName, BulletVisualCatalog.RelativePath)))
                    return directory.FullName;
            }
            throw new FileNotFoundException(BulletVisualCatalog.RelativePath);
        }
    }
}
