using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;
using CF7Launcher.Guardian.WorldCompositor;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    // 显式设置 CF7_LUTLAB_BAKE_SAMPLES=1 才再生 tmp/lut-lab/samples/xml-regression 样品
    // （PortraitWebViewFact 同款 env 门控；常规测试运行不写仓库文件）。
    public sealed class LutLabSampleBakeFactAttribute : FactAttribute
    {
        public LutLabSampleBakeFactAttribute()
        {
            if (Environment.GetEnvironmentVariable("CF7_LUTLAB_BAKE_SAMPLES") != "1")
                Skip = "显式设置 CF7_LUTLAB_BAKE_SAMPLES=1 才再生 xml-regression 样品";
        }
    }

    public class WorldLutBakerTests
    {
        internal static string RepoRoot()
        {
            string root = AppContext.BaseDirectory;
            while (!File.Exists(Path.Combine(root, "AGENTS.md")))
                root = Directory.GetParent(root)?.FullName ?? throw new Exception("Repository missing");
            return root;
        }

        internal static string PresetXmlPath() =>
            Path.Combine(RepoRoot(), "data", "environment", "color_engine_preset.xml");

        internal static Dictionary<string, Dictionary<int, double[]>> RealTables() =>
            WorldLutBaker.LoadPresetTables(PresetXmlPath());

        // 逐节点对照：baker 输出 == WorldColorMatrix.Generate 矩阵按 shader 语义
        // （saturate(matrix*c+offset/255) → pow(1/gamma) → *255 四舍五入）直接应用同色，±1/255。
        [Theory]
        [InlineData(1.0)]
        [InlineData(1.8)]
        [InlineData(0.5)]
        public void BakeMatchesDirectMatrixApplicationWithinOneByte(double gamma)
        {
            var parameters = new double[] { 0.85, 1.05, 0.9, 1, -12.5, 30, -25, 40 };
            byte[] rgba = WorldLutBaker.Bake(parameters, gamma);
            Assert.Equal(WorldLutBaker.RgbaBytes, rgba.Length);
            double[] m = WorldColorMatrix.Generate(parameters);
            double inverseGamma = 1.0 / Math.Max(gamma, 1e-3);
            for (int node = 0; node < WorldLutBaker.LutSize * WorldLutBaker.LutSize * WorldLutBaker.LutSize; node++)
            {
                int b = node / (WorldLutBaker.LutSize * WorldLutBaker.LutSize);
                int g = (node / WorldLutBaker.LutSize) % WorldLutBaker.LutSize;
                int r = node % WorldLutBaker.LutSize;
                double cr = r / (double)(WorldLutBaker.LutSize - 1);
                double cg = g / (double)(WorldLutBaker.LutSize - 1);
                double cb = b / (double)(WorldLutBaker.LutSize - 1);
                for (int row = 0; row < 3; row++)
                {
                    double value = m[row * 5] * cr + m[row * 5 + 1] * cg + m[row * 5 + 2] * cb
                        + m[row * 5 + 3] + m[row * 5 + 4] / 255.0;
                    value = value < 0 ? 0 : value > 1 ? 1 : value;
                    int expected = (int)Math.Floor(Math.Pow(value, inverseGamma) * 255.0 + 0.5);
                    int actual = rgba[node * 4 + row];
                    Assert.True(Math.Abs(expected - actual) <= 1,
                        $"node({r},{g},{b}) channel {row}: expected {expected}, actual {actual}, gamma {gamma}");
                }
                Assert.Equal(255, rgba[node * 4 + 3]);
            }
        }

        [Fact]
        public void IdentityParametersRoundTripNodeColors()
        {
            byte[] rgba = WorldLutBaker.Bake(new double[] { 1, 1, 1, 1, 0, 0, 0, 0 }, 1);
            for (int node = 0; node < WorldLutBaker.LutSize * WorldLutBaker.LutSize * WorldLutBaker.LutSize; node++)
            {
                int b = node / 1024, g = (node / 32) % 32, r = node % 32;
                Assert.Equal((int)Math.Floor(r / 31.0 * 255 + 0.5), rgba[node * 4]);
                Assert.Equal((int)Math.Floor(g / 31.0 * 255 + 0.5), rgba[node * 4 + 1]);
                Assert.Equal((int)Math.Floor(b / 31.0 * 255 + 0.5), rgba[node * 4 + 2]);
            }
        }

        [Fact]
        public void LightLevelSevenShortCircuitsToIdentityParameters()
        {
            var tables = RealTables();
            Assert.Equal(new double[] { 1, 1, 1, 1, 0, 0, 0, 0 }, WorldLutBaker.Interpolate(tables["光照"], 7));
            Assert.Equal(new double[] { 1, 1, 1, 1, 0, 0, 0, 0 }, WorldLutBaker.Interpolate(tables["夜视仪"], 7));
        }

        [Fact]
        public void IntegerLevelUsesExactPresetRow()
        {
            var tables = RealTables();
            // 光照 level 2：Brightness -27.1 / Contrast 35.7 / Saturation -30 / Hue 0，乘数缺省 1。
            Assert.Equal(new double[] { 1, 1, 1, 1, -27.1, 35.7, -30, 0 },
                WorldLutBaker.Interpolate(tables["光照"], 2));
            // 夜视仪 level 0：red/blue 乘数 0.15，Brightness 0 / Contrast 50。
            Assert.Equal(new double[] { 0.15, 1, 0.15, 1, 0, 50, 0, 0 },
                WorldLutBaker.Interpolate(tables["夜视仪"], 0));
        }

        [Fact]
        public void FractionalLevelLerpsFloorAndCeilRows()
        {
            var tables = RealTables();
            // 光照 2.5 = row2/row3 中点（AS2 floor/ceil 线性插值）。
            Assert.Equal(new double[] { 1, 1, 1, 1, (-27.1 - 15.7) / 2, (35.7 + 28.6) / 2, -25, 5 },
                WorldLutBaker.Interpolate(tables["光照"], 2.5));
        }

        [Fact]
        public void LevelAboveNineExtrapolatesFromLevelsEightAndNine()
        {
            var tables = RealTables();
            // 光照 level 10：ratio=2，value=row8*(-1)+row9*2（AS2 light>9 外推）。
            Assert.Equal(new double[] { 1, 1, 1, 1, 40, 0, 30, 0 }, WorldLutBaker.Interpolate(tables["光照"], 10));
        }

        [Fact]
        public void ModeAliasAndExactNamesResolve()
        {
            var tables = RealTables();
            Assert.Equal("夜视仪", WorldLutBaker.ResolvePresetSetName(tables, "夜视"));
            Assert.Equal("夜视仪", WorldLutBaker.ResolvePresetSetName(tables, "夜视仪"));
            Assert.Equal("光照", WorldLutBaker.ResolvePresetSetName(tables, "光照"));
            Assert.Null(WorldLutBaker.ResolvePresetSetName(tables, "不存在"));
            Assert.Null(WorldLutBaker.ResolvePresetSetName(tables, null));
        }

        [Fact]
        public void MissingLevelAndNonFiniteValuesAreRejected()
        {
            Assert.Null(WorldLutBaker.Interpolate(null, 3));
            Assert.Null(WorldLutBaker.Interpolate(new Dictionary<int, double[]>(), 3));
            var bad = new Dictionary<int, double[]>();
            for (int i = 0; i <= 9; i++) bad[i] = new double[] { 1, 1, 1, 1, 0, 0, 0, 0 };
            bad[4] = new double[] { 1, double.NaN, 1, 1, 0, 0, 0, 0 };
            Assert.Null(WorldLutBaker.Interpolate(bad, 4.5));
            Assert.Null(WorldLutBaker.Interpolate(bad, double.NaN));
            Assert.Null(WorldLutBaker.Interpolate(bad, double.PositiveInfinity));
        }

        [Fact]
        public void RealXmlContractModesBakeAcrossZeroToTen()
        {
            // preset.json v2（lut-set-v1）起经 WorldLightingPreset 读取（v1/v2 均给出 gamma；
            // LUT 模式下生产渲染不再使用 gamma，XML 回归烘焙仍按预设 gamma 取 1）。
            double gamma = WorldLightingPreset.Load(
                Path.Combine(RepoRoot(), "launcher", "data", "world-lighting", "preset.json"), null).Gamma;
            foreach (string mode in new[] { "光照", "夜视" })
                for (int level = 0; level <= 10; level++)
                {
                    string resolved;
                    byte[] rgba = WorldLutBaker.BakeFromXml(PresetXmlPath(), mode, level, gamma, out resolved);
                    Assert.NotNull(resolved);
                    Assert.NotNull(rgba);
                    Assert.Equal(WorldLutBaker.RgbaBytes, rgba.Length);
                }
        }

        [LutLabSampleBakeFact]
        public void BakeXmlRegressionSamples()
        {
            string root = RepoRoot();
            string xmlPath = PresetXmlPath();
            double gamma = WorldLightingPreset.Load(
                Path.Combine(root, "launcher", "data", "world-lighting", "preset.json"), null).Gamma;
            string dir = Path.Combine(root, "tmp", "lut-lab", "samples", "xml-regression");
            Directory.CreateDirectory(dir);
            var modes = new[] { new[] { "光照", "光照" }, new[] { "夜视", "夜视仪" } };
            var entries = new JArray();
            foreach (var mode in modes)
            {
                for (int level = 0; level <= 9; level++)
                {
                    string resolved;
                    byte[] rgba = WorldLutBaker.BakeFromXml(xmlPath, mode[0], level, gamma, out resolved);
                    Assert.NotNull(rgba);
                    Assert.Equal(mode[1], resolved);
                    string name = mode[0] + "-" + level;
                    string fileName = name + ".cube";
                    WorldLutBaker.WriteCube(Path.Combine(dir, fileName),
                        name + " (" + resolved + ", color_engine_preset.xml)", rgba);
                    // manifest 根为条目数组（面板 lut-lab-bridge.js 约定），file 为组目录内文件名。
                    entries.Add(new JObject
                    {
                        ["name"] = name,
                        ["file"] = fileName,
                        ["source"] = "data/environment/color_engine_preset.xml PresetSet[" + resolved + "] level " + level,
                        ["license"] = "项目内部数据派生，随仓库许可",
                        ["notes"] = "WorldLutBaker 离线烘焙；32^3 RGB（R 最快）；gamma="
                            + gamma.ToString("G", CultureInfo.InvariantCulture) + "；与原生合成 shader 同一公式"
                    });
                }
            }
            File.WriteAllText(
                Path.Combine(root, "tmp", "lut-lab", "samples", "manifest.xml-regression.json"),
                entries.ToString(Formatting.Indented) + "\n", new UTF8Encoding(false));
            Assert.Equal(20, entries.Count);
        }
    }
}
