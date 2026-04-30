// LauncherVersionGate (INV-2) 单测.
// 覆盖 Check 五种状态分支 + WriteMarker 写回 + 升级 round-trip.

using System;
using System.IO;
using System.Text;
using CF7Launcher.Save;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Save
{
    public class LauncherVersionGateTests : IDisposable
    {
        private readonly string _savesDir;
        private readonly string _markerPath;

        public LauncherVersionGateTests()
        {
            _savesDir = Path.Combine(Path.GetTempPath(), "cf7-version-gate-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(_savesDir);
            _markerPath = Path.Combine(_savesDir, LauncherVersionGate.MarkerFileName);
        }

        public void Dispose()
        {
            try { if (Directory.Exists(_savesDir)) Directory.Delete(_savesDir, true); }
            catch { }
        }

        [Fact]
        public void Check_NoMarker_ShouldShowToast()
        {
            var r = LauncherVersionGate.Check(_savesDir);
            Assert.True(r.ShouldShowToast);
            Assert.Equal("no_marker", r.Reason);
            Assert.Equal(-1, r.PreviousVersion);
        }

        [Fact]
        public void Check_MarkerInvalidJson_ShouldShowToast()
        {
            File.WriteAllText(_markerPath, "{not valid", new UTF8Encoding(false));
            var r = LauncherVersionGate.Check(_savesDir);
            Assert.True(r.ShouldShowToast);
            Assert.Equal("marker_parse_error", r.Reason);
        }

        [Fact]
        public void Check_MarkerMissingVersionField_ShouldShowToast()
        {
            File.WriteAllText(_markerPath, "{\"foo\":\"bar\"}", new UTF8Encoding(false));
            var r = LauncherVersionGate.Check(_savesDir);
            Assert.True(r.ShouldShowToast);
            Assert.Equal("marker_invalid_format", r.Reason);
        }

        [Fact]
        public void Check_MarkerVersionOlder_ShouldShowToast()
        {
            JObject m = new JObject();
            m["version"] = 0;
            m["writtenAt"] = "2026-01-01T00:00:00Z";
            File.WriteAllText(_markerPath, m.ToString(Formatting.None), new UTF8Encoding(false));

            var r = LauncherVersionGate.Check(_savesDir);
            Assert.True(r.ShouldShowToast);
            Assert.StartsWith("version_upgrade_from_", r.Reason);
            Assert.Equal(0, r.PreviousVersion);
        }

        [Fact]
        public void Check_MarkerVersionCurrent_NoToast()
        {
            JObject m = new JObject();
            m["version"] = LauncherVersionGate.CurrentSchemaVersion;
            File.WriteAllText(_markerPath, m.ToString(Formatting.None), new UTF8Encoding(false));

            var r = LauncherVersionGate.Check(_savesDir);
            Assert.False(r.ShouldShowToast);
            Assert.Equal("marker_current", r.Reason);
            Assert.Equal(LauncherVersionGate.CurrentSchemaVersion, r.PreviousVersion);
        }

        [Fact]
        public void Check_MarkerVersionFromFuture_NoToast()
        {
            // 玩家可能从 dev/preview 版回退到 stable, 信任未来版的 marker, 不重复提示.
            JObject m = new JObject();
            m["version"] = LauncherVersionGate.CurrentSchemaVersion + 5;
            File.WriteAllText(_markerPath, m.ToString(Formatting.None), new UTF8Encoding(false));

            var r = LauncherVersionGate.Check(_savesDir);
            Assert.False(r.ShouldShowToast);
            Assert.Equal("marker_current", r.Reason);
        }

        [Fact]
        public void WriteMarker_CreatesValidJson()
        {
            LauncherVersionGate.WriteMarker(_savesDir);

            Assert.True(File.Exists(_markerPath));
            string content = File.ReadAllText(_markerPath, Encoding.UTF8);
            JObject obj = JObject.Parse(content);
            Assert.Equal(LauncherVersionGate.CurrentSchemaVersion, obj.Value<int>("version"));
            Assert.NotNull(obj.Value<string>("writtenAt"));
        }

        [Fact]
        public void WriteMarker_OverwritesExisting()
        {
            File.WriteAllText(_markerPath, "{\"version\":-99}", new UTF8Encoding(false));
            LauncherVersionGate.WriteMarker(_savesDir);

            JObject obj = JObject.Parse(File.ReadAllText(_markerPath, Encoding.UTF8));
            Assert.Equal(LauncherVersionGate.CurrentSchemaVersion, obj.Value<int>("version"));
        }

        [Fact]
        public void RoundTrip_WriteThenCheck_NoToast()
        {
            // 第一次启动 → toast
            var first = LauncherVersionGate.Check(_savesDir);
            Assert.True(first.ShouldShowToast);

            // 写 marker
            LauncherVersionGate.WriteMarker(_savesDir);

            // 二次启动 → 沉默
            var second = LauncherVersionGate.Check(_savesDir);
            Assert.False(second.ShouldShowToast);
            Assert.Equal("marker_current", second.Reason);
        }

        [Fact]
        public void WriteMarker_SavesDirNotExist_AutoCreates()
        {
            string sub = Path.Combine(_savesDir, "nested");
            LauncherVersionGate.WriteMarker(sub);
            Assert.True(File.Exists(Path.Combine(sub, LauncherVersionGate.MarkerFileName)));
        }
    }
}
