using System;
using System.IO;
using System.Linq;
using CF7Launcher.Guardian.WorldCompositor;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class BulletVisualCatalogTests
    {
        [Fact]
        public void OrdinaryAndGunChainFormsShareExactlyTwoAuthoredVisuals()
        {
            var catalog = BulletVisualCatalog.Load(ProjectRoot());
            Assert.Equal(2, catalog.Styles.Count);
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
            Assert.False(catalog.TryOrdinary("穿刺子弹", out _));
            Assert.False(catalog.TryGunChain("横向拖尾联弹-普通子弹", out _));
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
        public void CombinedNormalAndChainVisualItemsStopAt256()
        {
            string entries256 = string.Join(";", Enumerable.Repeat("0,10,20,0,100,100,100", 256));
            Assert.True(BulletVisualFrame.TryParse("1|200|255|1|0|1;" + entries256, 2,
                out var full));
            Assert.Equal(256, full.Instances.Length);
            Assert.Equal(255, full.NormalCount);
            Assert.Equal(1, full.ChainCount);
            Assert.False(BulletVisualFrame.TryParse(
                "1|201|256|1|0|1;" + entries256 + ";0,10,20,0,100,100,100", 2, out _));
        }

        [Fact]
        public void ShadowCoverageSeparatesNormalAndChainForEachVisualStyle()
        {
            var shadow = new BulletVisualShadow(BulletVisualCatalog.Load(ProjectRoot()));
            Assert.NotNull(shadow.Observe("1|100|1|1|0;0,10,20,0,100,100,100;1,30,40,0,100,100,100", 7));
            Assert.Equal("normal.plain=1/1,chain.plain=0/0,normal.enhanced=0/0,chain.enhanced=1/1",
                shadow.CoverageForTests());
            Assert.Null(shadow.Observe("1|100|1|1|0;0,10,20,0,100,100,100;1,30,40,0,100,100,100", 7));
            Assert.Equal("normal.plain=1/1,chain.plain=0/0,normal.enhanced=0/0,chain.enhanced=1/1",
                shadow.CoverageForTests());
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
