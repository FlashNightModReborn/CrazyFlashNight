using System;
using System.IO;
using CF7Launcher.Config;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class FlashLocalStorageSettingsTests : IDisposable
    {
        // 实采现役 flashplayer_sa 写出的 #local\settings.sol 原始字节样本：
        // 10 MB (klimit = 10240.0 = 40 C4 00 00 00 00 00 00)
        private static readonly byte[] RealFlashLocal10Mb = Convert.FromHexString(
            "00BF000000665443534F000400000000000E6C6F63616C2F73657474696E677300000000" +
            "0005616C6C6F77010000" +
            "0006616C77617973010000" +
            "00066B6C696D69740040C400000000000000" +
            "000B616C6C6F77736563757265010000" +
            "000C616C77617973736563757265010000");

        // 无限制 (klimit = -2.0 = C0 00 00 00 00 00 00 00)
        private static readonly byte[] RealFlashLocalUnlimited = Convert.FromHexString(
            "00BF000000665443534F000400000000000E6C6F63616C2F73657474696E677300000000" +
            "0005616C6C6F77010000" +
            "0006616C77617973010000" +
            "00066B6C696D697400C00000000000000000" +
            "000B616C6C6F77736563757265010000" +
            "000C616C77617973736563757265010000");

        private readonly string _root = Path.Combine(Path.GetTempPath(), "cf7-flash-quota-" + Guid.NewGuid().ToString("N"));

        public FlashLocalStorageSettingsTests()
        {
            Directory.CreateDirectory(_root);
        }

        [Fact]
        public void FreshMachineDefaultsTo100KbWarningAndCreatesExactCanonicalLocalSol()
        {
            var initial = FlashLocalStorageSettings.ReadStatus(_root);
            Assert.True(initial.Ok);
            Assert.False(initial.Unlimited);
            Assert.Equal(100.0, initial.LimitKb);
            Assert.Equal(100 * 1024L, initial.LimitBytes);
            Assert.Equal("flash_default", initial.Source);
            Assert.Equal("warning", initial.Status);
            Assert.True(initial.NeedsAttention);

            var updated = FlashLocalStorageSettings.SetLocalLimitKb(FlashLocalStorageSettings.LimitUnlimitedKb, _root);
            Assert.True(updated.Ok);
            Assert.True(updated.Unlimited);
            Assert.Equal(-2.0, updated.LimitKb);
            Assert.Null(updated.LimitBytes);
            Assert.Equal("local_settings", updated.Source);
            Assert.Equal("ok", updated.Status);
            Assert.False(updated.NeedsAttention);

            byte[] written = File.ReadAllBytes(FlashLocalStorageSettings.GetLocalSettingsSolPath(_root));
            Assert.Equal(RealFlashLocalUnlimited, written);
        }

        [Fact]
        public void PatchingReal10MbLocalSolToUnlimitedMatchesLiveFlashBytesExactly()
        {
            string localSol = FlashLocalStorageSettings.GetLocalSettingsSolPath(_root);
            Directory.CreateDirectory(Path.GetDirectoryName(localSol));
            File.WriteAllBytes(localSol, RealFlashLocal10Mb);

            // 构造 10.07 MB 已用 SOL 触发 exceeded（复现现网 10339 KB 撞墙）
            string solDir = Path.Combine(FlashLocalStorageSettings.GetSharedObjectsRoot(_root), "L5HT6R75", "localhost", "game.swf");
            Directory.CreateDirectory(solDir);
            File.WriteAllBytes(Path.Combine(solDir, "big.sol"), new byte[10 * 1024 * 1024 + 70 * 1024]);

            var before = FlashLocalStorageSettings.ReadStatus(_root);
            Assert.True(before.Ok);
            Assert.False(before.Unlimited);
            Assert.Equal(10240.0, before.LimitKb);
            Assert.Equal("exceeded", before.Status);
            Assert.True(before.NeedsAttention);
            Assert.Equal(1, before.UsedFiles);

            var after = FlashLocalStorageSettings.SetLocalLimitKb(-2.0, _root);
            Assert.True(after.Ok);
            Assert.True(after.Unlimited);
            Assert.Equal("ok", after.Status);
            Assert.False(after.NeedsAttention);

            byte[] actualBytes = File.ReadAllBytes(localSol);
            Assert.Equal(RealFlashLocalUnlimited, actualBytes);
        }

        [Fact]
        public void PreservesUnknownPropertiesAndSplicesDomainsLocalInGlobalSettingsSol()
        {
            string globalSol = FlashLocalStorageSettings.GetGlobalSettingsSolPath(_root);
            Directory.CreateDirectory(Path.GetDirectoryName(globalSol));

            // 构造含 defaultklimit=100、未知字符串属性、不含 local 的 domains 对象的全局 settings.sol
            var globalDoc = new FlashLocalStorageSettings.SolDocument("settings");
            globalDoc.SetNumber("defaultklimit", 100.0);
            globalDoc.Properties.Add(new FlashLocalStorageSettings.SolProperty
            {
                Name = "customCamera",
                RawValue = new byte[] { 0x02, 0x00, 0x04, (byte)'T', (byte)'e', (byte)'s', (byte)'t' }
            });
            // domains = { "127.0.0.1": true }
            globalDoc.Properties.Add(new FlashLocalStorageSettings.SolProperty
            {
                Name = "domains",
                RawValue = new byte[]
                {
                    0x03,
                    0x00, 0x09, (byte)'1',(byte)'2',(byte)'7',(byte)'.',(byte)'0',(byte)'.',(byte)'0',(byte)'.',(byte)'1',
                    0x01, 0x01,
                    0x00, 0x00, 0x09
                }
            });
            File.WriteAllBytes(globalSol, globalDoc.Serialize());

            var before = FlashLocalStorageSettings.ReadStatus(_root);
            Assert.Equal("default_settings", before.Source);
            Assert.Equal(100.0, before.LimitKb);

            var after = FlashLocalStorageSettings.SetLocalLimitKb(1024.0, _root);
            Assert.True(after.Ok);
            Assert.Equal(1024.0, after.LimitKb);
            Assert.Equal("local_settings", after.Source);

            byte[] globalAfterBytes = File.ReadAllBytes(globalSol);
            Assert.True(FlashLocalStorageSettings.SolDocument.TryParse(globalAfterBytes, out var parsedGlobal, out _));
            Assert.True(parsedGlobal.TryGetNumber("defaultklimit", out double defKb));
            Assert.Equal(100.0, defKb);
            // 未知属性原样保真
            Assert.Contains(parsedGlobal.Properties, p => p.Name == "customCamera" && p.RawValue.Length == 7);
            // domains 已写入 local=true，再次调用不再产生变更
            Assert.True(parsedGlobal.TryEnsureDomainFlag("domains", "local", true, out bool changedAgain));
            Assert.False(changedAgain);
        }

        [Fact]
        public void CorruptOrAmf3LocalSolFailsClosedWithoutOverwriting()
        {
            string localSol = FlashLocalStorageSettings.GetLocalSettingsSolPath(_root);
            Directory.CreateDirectory(Path.GetDirectoryName(localSol));
            byte[] corrupt = new byte[] { 0x00, 0xBF, 0x00, 0x00, 0x00, 0x10, 0x54, 0x43, 0x53, 0x4F, 0x99, 0x88 };
            File.WriteAllBytes(localSol, corrupt);

            var read = FlashLocalStorageSettings.ReadStatus(_root);
            Assert.False(read.Ok);
            Assert.True(read.NeedsAttention);

            var write = FlashLocalStorageSettings.SetLocalLimitKb(-2.0, _root);
            Assert.False(write.Ok);
            Assert.StartsWith("sol_parse_failed:", write.Error);
            Assert.Equal(corrupt, File.ReadAllBytes(localSol));
        }

        [Theory]
        [InlineData(-1.0)]
        [InlineData(0.0)]
        [InlineData(50.0)]
        [InlineData(99999.0)]
        [InlineData(double.NaN)]
        public void InvalidPresetLimitIsRejectedWithoutCreatingFiles(double badLimit)
        {
            var res = FlashLocalStorageSettings.SetLocalLimitKb(badLimit, _root);
            Assert.False(res.Ok);
            Assert.Equal("invalid_limit", res.Error);
            Assert.False(File.Exists(FlashLocalStorageSettings.GetLocalSettingsSolPath(_root)));
        }

        [Fact]
        public void BlockedZeroLimitAndHeadroomClassificationWorkAccurately()
        {
            string localSol = FlashLocalStorageSettings.GetLocalSettingsSolPath(_root);
            Directory.CreateDirectory(Path.GetDirectoryName(localSol));
            var doc = new FlashLocalStorageSettings.SolDocument("local/settings");
            doc.SetNumber("klimit", 0.0);
            File.WriteAllBytes(localSol, doc.Serialize());

            var blocked = FlashLocalStorageSettings.ReadStatus(_root);
            Assert.True(blocked.Ok);
            Assert.Equal("blocked", blocked.Status);
            Assert.True(blocked.NeedsAttention);

            // 1 MB 上限 + 850 KB 已用 (>= 80%) → warning
            doc.SetNumber("klimit", 1024.0);
            File.WriteAllBytes(localSol, doc.Serialize());
            string solDir = Path.Combine(FlashLocalStorageSettings.GetSharedObjectsRoot(_root), "HASH1", "localhost", "a.swf");
            Directory.CreateDirectory(solDir);
            File.WriteAllBytes(Path.Combine(solDir, "save.sol"), new byte[850 * 1024]);

            var warn = FlashLocalStorageSettings.ReadStatus(_root);
            Assert.Equal("warning", warn.Status);
            Assert.True(warn.NeedsAttention);

            // 升到 10 MB 后 → ok
            var ok = FlashLocalStorageSettings.SetLocalLimitKb(10240.0, _root);
            Assert.True(ok.Ok);
            Assert.Equal("ok", ok.Status);
            Assert.False(ok.NeedsAttention);

            // FlashStorageEnvironment.Snapshot 包含 localStorageQuota 诊断字段
            JObject snap = FlashStorageEnvironment.Snapshot(_root);
            Assert.NotNull(snap["localStorageQuota"]);
            Assert.Equal(10240.0, snap["localStorageQuota"].Value<double>("limitKb"));
        }

        public void Dispose()
        {
            string resolved = Path.GetFullPath(_root);
            if (!resolved.StartsWith(Path.GetFullPath(Path.GetTempPath()), StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("fixture cleanup escaped temporary root");
            if (Directory.Exists(resolved)) Directory.Delete(resolved, true);
        }
    }
}
