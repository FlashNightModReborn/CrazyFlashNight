using System;
using System.Collections.Generic;
using System.IO;
using System.Security.Cryptography;
using CF7Launcher.Guardian.WorldCompositor;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    // lut-set-v1 生产 LUT 路径（2026-09-25）：preset v2 解析/回退、等级 blend、mode 分派、
    // 断连语义（断连 → ResetSource → 新过渡机 CurrentMode=null → legacy 矩阵路径）。
    public class WorldLutSetTests
    {
        // 合成 lutset：level k 全部节点 = (k*25, k*25, k*25, 255)（灰阶等距，便于 blend 精确断言）
        private static byte[] BuildLutSet(Action<byte[]> corrupt = null)
        {
            var data = new byte[WorldLutSet.LevelCount * WorldLutSet.LevelBytes];
            for (int level = 0; level < WorldLutSet.LevelCount; level++)
            {
                byte v = (byte)(level * 25);
                for (int i = level * WorldLutSet.LevelBytes; i < (level + 1) * WorldLutSet.LevelBytes; i += 4)
                {
                    data[i] = v; data[i + 1] = v; data[i + 2] = v; data[i + 3] = 255;
                }
            }
            byte[] hash;
            using (var sha = SHA256.Create()) hash = sha.ComputeHash(data);
            var file = new byte[WorldLutSet.TotalBytes];
            file[0] = (byte)'C'; file[1] = (byte)'F'; file[2] = (byte)'7'; file[3] = (byte)'L';
            BitConverter.GetBytes(1).CopyTo(file, 4);
            BitConverter.GetBytes(WorldLutSet.LutSize).CopyTo(file, 8);
            BitConverter.GetBytes(WorldLutSet.LevelCount).CopyTo(file, 12);
            hash.CopyTo(file, 16);
            data.CopyTo(file, WorldLutSet.HeaderBytes);
            corrupt?.Invoke(file);
            return file;
        }

        private static string WriteTemp(Action<string> extra, out string dir)
        {
            dir = Path.Combine(Path.GetTempPath(), "cf7-lutset-test-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(dir);
            var path = Path.Combine(dir, "preset.json");
            extra(dir);
            return path;
        }

        [Fact]
        public void ParseAcceptsWellFormedAndVerifiesIntegrity()
        {
            var set = WorldLutSet.Parse(BuildLutSet(), "合成");
            Assert.Equal(32, WorldLutSet.LutSize);
            Assert.Equal(64, set.DataSha256.Length);
            // 整数档精确取档（无混合）
            Assert.Equal(100, set.Level(4)[0]);
            Assert.Equal(225, set.Level(9)[12]);
        }

        [Fact]
        public void ParseRejectsBadMagicVersionSizeLevelsLengthAndHash()
        {
            Assert.Throws<InvalidDataException>(() => WorldLutSet.Parse(BuildLutSet(f => f[0] = 0), "magic"));
            Assert.Throws<InvalidDataException>(() => WorldLutSet.Parse(BuildLutSet(f => f[4] = 2), "version"));
            Assert.Throws<InvalidDataException>(() => WorldLutSet.Parse(BuildLutSet(f => f[8] = 16), "size"));
            Assert.Throws<InvalidDataException>(() => WorldLutSet.Parse(BuildLutSet(f => f[12] = 9), "levels"));
            Assert.Throws<InvalidDataException>(() => WorldLutSet.Parse(new byte[16], "length"));
            // 数据段任何字节翻转都必须被内嵌 SHA-256 拦下
            Assert.Throws<InvalidDataException>(() => WorldLutSet.Parse(BuildLutSet(f => f[WorldLutSet.HeaderBytes + 7] ^= 0x01), "hash"));
            // 头内哈希字段被篡改同样拦下
            Assert.Throws<InvalidDataException>(() => WorldLutSet.Parse(BuildLutSet(f => f[20] ^= 0x01), "hashfield"));
        }

        [Fact]
        public void BlendLevelIsExactAtIntegersAndMidpoint()
        {
            var set = WorldLutSet.Parse(BuildLutSet(), "合成");
            // 中点：L4(100) 与 L5(125) 各半 → floor(112.5+0.5)=113，逐字节全缓冲
            var mid = set.BlendLevel(4.5);
            Assert.Equal(WorldLutSet.LevelBytes, mid.Length);
            for (int i = 0; i < mid.Length; i += 4)
            {
                Assert.Equal(113, mid[i]); Assert.Equal(113, mid[i + 1]); Assert.Equal(113, mid[i + 2]);
                Assert.Equal(255, mid[i + 3]);
            }
            Assert.Equal(100, set.BlendLevel(4)[0]);
            Assert.Equal(110, set.BlendLevel(4.4)[0]); // 100+(125-100)*0.4=110
        }

        [Fact]
        public void BlendLevelClampsToSetRange()
        {
            var set = WorldLutSet.Parse(BuildLutSet(), "合成");
            Assert.Equal(225, set.BlendLevel(9.7)[0]);   // light>9 钳到 9（钉 L9，不外推）
            Assert.Equal(225, set.BlendLevel(100)[0]);
            Assert.Equal(0, set.BlendLevel(-1)[0]);      // light<0 钳到 0
            Assert.Equal(175, set.BlendLevel(double.NaN)[0]);  // 非有限值回 7（白天恒等档）
            Assert.Equal(175, set.BlendLevel(double.PositiveInfinity)[0]);
        }

        [Fact]
        public void PresetV1KeepsLegacyMatrixSemantics()
        {
            var path = WriteTemp(d => File.WriteAllText(Path.Combine(d, "preset.json"),
                "{\"version\":1,\"algorithm\":\"legacy-matrix-v1\",\"gamma\":1.4}"), out _);
            var warnings = new List<string>();
            var preset = WorldLightingPreset.Load(path, warnings.Add);
            Assert.Null(preset.LutSet);
            Assert.False(preset.UsesLut("光照"));
            Assert.Equal(1.4f, preset.Gamma, 3);
            Assert.Empty(warnings);
        }

        [Fact]
        public void PresetV2LoadsLutSetAndDispatchesByMode()
        {
            var path = WriteTemp(d =>
            {
                File.WriteAllText(Path.Combine(d, "preset.json"),
                    "{\"version\":2,\"algorithm\":\"lut-set-v1\",\"file\":\"ok.lutset\",\"gamma\":1}");
                File.WriteAllBytes(Path.Combine(d, "ok.lutset"), BuildLutSet());
            }, out _);
            var warnings = new List<string>();
            var preset = WorldLightingPreset.Load(path, warnings.Add);
            Assert.NotNull(preset.LutSet);
            Assert.Equal("ok.lutset", preset.LutFile);
            Assert.True(preset.UsesLut("光照"));
            Assert.False(preset.UsesLut("夜视"));
            Assert.False(preset.UsesLut("夜视仪"));
            Assert.False(preset.UsesLut("其他未知"));
            Assert.False(preset.UsesLut(null));
            Assert.Empty(warnings);
        }

        [Fact]
        public void PresetV2FallsBackToLegacyOnAnyLutSetFailure()
        {
            // 文件缺失 / 哈希不符 / 算法不识 / 路径穿越 / gamma 非法：全部回退 + 警告，绝不抛出
            var cases = new Dictionary<string, Action<string>>
            {
                ["missing"] = d => File.WriteAllText(Path.Combine(d, "preset.json"),
                    "{\"version\":2,\"algorithm\":\"lut-set-v1\",\"file\":\"gone.lutset\",\"gamma\":1}"),
                ["hash"] = d =>
                {
                    File.WriteAllText(Path.Combine(d, "preset.json"),
                        "{\"version\":2,\"algorithm\":\"lut-set-v1\",\"file\":\"bad.lutset\",\"gamma\":1}");
                    File.WriteAllBytes(Path.Combine(d, "bad.lutset"), BuildLutSet(f => f[WorldLutSet.HeaderBytes + 3] ^= 0x01));
                },
                ["algorithm"] = d => File.WriteAllText(Path.Combine(d, "preset.json"),
                    "{\"version\":2,\"algorithm\":\"future-v9\",\"file\":\"ok.lutset\",\"gamma\":1}"),
                ["traversal"] = d => File.WriteAllText(Path.Combine(d, "preset.json"),
                    "{\"version\":2,\"algorithm\":\"lut-set-v1\",\"file\":\"..\\\\evil.lutset\",\"gamma\":1}"),
                ["gamma"] = d => File.WriteAllText(Path.Combine(d, "preset.json"),
                    "{\"version\":2,\"algorithm\":\"lut-set-v1\",\"file\":\"ok.lutset\",\"gamma\":99}"),
            };
            foreach (var (name, setup) in cases)
            {
                var path = WriteTemp(setup, out var dir);
                var warnings = new List<string>();
                var preset = WorldLightingPreset.Load(path, warnings.Add);
                Assert.True(preset.LutSet == null, name + " 应回退 legacy");
                Assert.Equal(1f, preset.Gamma, 3);
                Assert.Single(warnings);
                Assert.Contains("world_lighting_preset_fallback", warnings[0]);
                // 回退后 legacy 矩阵路径可用（gamma=1 中性预设）
                var probe = preset.ShaderSettings(WorldColorMatrix.Identity());
                Assert.Equal(1f, probe[15], 6);
            }
        }

        [Fact]
        public void PresetUnknownVersionKeepsThrowing()
        {
            var path = WriteTemp(d => File.WriteAllText(Path.Combine(d, "preset.json"),
                "{\"version\":3,\"algorithm\":\"lut-set-v1\"}"), out _);
            Assert.Throws<InvalidDataException>(() => WorldLightingPreset.Load(path, _ => { }));
        }

        [Fact]
        public void TransitionSampleLightSharesTheMatrixBlendWindow()
        {
            var transition = new WorldLightingTransition();
            Assert.Null(transition.CurrentMode);
            transition.Adopt(Frame(1, 1, "光照", 7), 0);
            Assert.Equal(7, transition.SampleLight(0), 6);
            // 同场景 350ms 过渡：light 语义插值（非矩阵）
            transition.Adopt(Frame(2, 1, "光照", 4), 100);
            Assert.Equal(350, transition.BlendDurationMs);
            Assert.Equal(7, transition.SampleLight(100), 6);
            Assert.Equal(5.5, transition.SampleLight(275), 6);
            Assert.Equal(4, transition.SampleLight(450), 6);
            // 模式切换即时（无过渡）
            transition.Adopt(Frame(3, 1, "夜视", 4), 500);
            Assert.Equal(0, transition.BlendDurationMs);
            Assert.Equal("夜视", transition.CurrentMode);
            Assert.Equal(4, transition.SampleLight(500), 6);
        }

        [Fact]
        public void HoldKeepsFrozenLightWhilePending()
        {
            var transition = new WorldLightingTransition();
            transition.Adopt(Frame(1, 1, "光照", 4), 0);
            transition.Adopt(Frame(2, 2, "光照", 4, ready: false), 100);
            Assert.True(transition.Pending);
            Assert.Equal(4, transition.SampleLight(5000), 6);  // hold 期间冻结，不漂移
            Assert.Equal("光照", transition.CurrentMode);       // 分派只看已 Commit 模式
        }

        // 断连语义链：Disconnected → 控制器 ResetSource → 新过渡机 CurrentMode=null
        // → UsesLut(null)=false → legacy 矩阵路径（直到新快照到达）。
        [Fact]
        public void DisconnectDropsLutDispatchUntilNewSnapshots()
        {
            var path = WriteTemp(d =>
            {
                File.WriteAllText(Path.Combine(d, "preset.json"),
                    "{\"version\":2,\"algorithm\":\"lut-set-v1\",\"file\":\"ok.lutset\",\"gamma\":1}");
                File.WriteAllBytes(Path.Combine(d, "ok.lutset"), BuildLutSet());
            }, out _);
            var preset = WorldLightingPreset.Load(path, _ => { });
            var transition = new WorldLightingTransition();
            transition.Adopt(Frame(1, 1, "光照", 4), 0);
            Assert.True(preset.UsesLut(transition.CurrentMode));
            transition = new WorldLightingTransition();   // ResetSource 语义：状态机整体更换
            Assert.False(preset.UsesLut(transition.CurrentMode));
        }

        // 真实产物（仓库内已验收的 hardlight-dusk-v4.lutset）：完整性 + L7 恒等档逐节点核验。
        [Fact]
        public void RealV4LutSetPassesIntegrityAndL7IsIdentity()
        {
            var path = Path.Combine(WorldLutBakerTests.RepoRoot(),
                "launcher", "data", "world-lighting", "hardlight-dusk-v4.lutset");
            Assert.True(File.Exists(path), "v4 lutset 应已生成（先跑 pack-set）: " + path);
            var set = WorldLutSet.Load(path);
            var l7 = set.Level(7);
            // 恒等语义（与量化细节解耦）：节点 (r,g,b) 的字节 == [f(r), f(g), f(b), 255]，
            // f(k) 取对角线节点 (k,0,0) 的 R 值；f 单调、端点 0/255。
            for (int k = 0; k < WorldLutSet.LutSize; k++)
            {
                int diag = k * 4;
                Assert.Equal(255, l7[diag + 3]);
                if (k > 0) Assert.True(l7[diag] >= l7[(k - 1) * 4], "L7 对角量化应单调");
            }
            Assert.Equal(0, l7[0]); Assert.Equal(255, l7[(WorldLutSet.LutSize - 1) * 4]);
            int nodes = WorldLutSet.LutSize * WorldLutSet.LutSize * WorldLutSet.LutSize;
            for (int b = 0; b < WorldLutSet.LutSize; b++)
                for (int g = 0; g < WorldLutSet.LutSize; g++)
                    for (int r = 0; r < WorldLutSet.LutSize; r++)
                    {
                        int o = (((b * WorldLutSet.LutSize) + g) * WorldLutSet.LutSize + r) * 4;
                        Assert.True(l7[o] == l7[r * 4] && l7[o + 1] == l7[g * 4] && l7[o + 2] == l7[b * 4]
                            && l7[o + 3] == 255, $"L7 节点({r},{g},{b}) 应恒等");
                    }
            Assert.Equal(nodes * 4, l7.Length);
        }

        private static WorldLightingFrame Frame(long sequence, long scene, string mode, double light, bool ready = true) =>
            new WorldLightingFrame
            {
                Sequence = sequence, Scene = scene, Ready = ready, Mode = mode, Light = light,
                Parameters = new double[] { 1, 1, 1, 1, 0, 0, 0, 0 },
            };
    }
}
