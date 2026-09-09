using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using CF7Launcher.Diagnostic;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Diagnostic
{
    public sealed class FocusIncidentRecorderTests : IDisposable
    {
        private readonly string _root = Path.Combine(Path.GetTempPath(), "cf7-incident-" + Guid.NewGuid().ToString("N"));
        private long _now = Stopwatch.Frequency;
        public FocusIncidentRecorderTests() { Directory.CreateDirectory(_root); }
        public void Dispose() { Directory.Delete(_root, true); }
        private string Row(string name, JObject data, string session = "fixture") => "[FocusTrace] " + new JObject {
            ["session"] = session, ["ticks"] = _now, ["event"] = name, ["data"] = data }.ToString(Newtonsoft.Json.Formatting.None);
        private void Advance(int milliseconds) { _now += Stopwatch.Frequency * milliseconds / 1000; }

        [Fact]
        public void StaleIneligibleInjectedAndForeignSessionCannotConsumeClickQuota()
        {
            using var recorder = new FocusIncidentRecorder(_root, "fixture", () => _now);
            foreach (var data in new[] {
                new JObject { ["mouseId"] = "a", ["injected"] = false, ["targetEligible"] = false, ["cacheAgeMs"] = 1 },
                new JObject { ["mouseId"] = "b", ["injected"] = false, ["targetEligible"] = true, ["cacheAgeMs"] = 1001 },
                new JObject { ["mouseId"] = "c", ["injected"] = true, ["targetEligible"] = true, ["cacheAgeMs"] = 1 } })
                recorder.Append(Row("mouse.down", data));
            recorder.Append(Row("mouse.down", new JObject { ["mouseId"] = "d", ["injected"] = false,
                ["targetEligible"] = true, ["cacheAgeMs"] = 1 }, "foreign"));
            Advance(1000); recorder.Append("");
            Assert.Empty(Directory.GetFiles(_root));
        }

        [Fact]
        public void PreservesEarlyGapAcrossLongRollingSessionWithBoundedSlotsAndExplicitPartialWindow()
        {
            using (var recorder = new FocusIncidentRecorder(_root, "fixture", () => _now))
            {
                recorder.Append(Row("mouse.down", new JObject { ["mouseId"] = "first", ["injected"] = false,
                    ["targetEligible"] = true, ["cacheAgeMs"] = 1 }));
                Advance(300); recorder.Append("");
                for (int i = 0; i < 80; i++) recorder.Append(Row("payload", new JObject { ["text"] = new string('x', 20000) }));
                Advance(16000);
                recorder.Append(Row("input.heartbeat_wait", new JObject { ["elapsedMs"] = 900 }));
                Advance(16000);
                recorder.Append(Row("input.heartbeat_wait", new JObject { ["elapsedMs"] = 900 }));
                Advance(16000);
                recorder.Append(Row("input.heartbeat_wait", new JObject { ["elapsedMs"] = 900 }));
                Assert.Equal(3, Directory.GetFiles(_root).Length);
            }
            Assert.All(Directory.GetFiles(_root), path => Assert.True(new FileInfo(path).Length <= FocusIncidentRecorder.SlotBytes));
            string first = File.ReadAllText(Path.Combine(_root, FocusIncidentRecorder.Names[0]));
            Assert.Contains("first", first);
            Assert.Contains("candidate_only", first);
            Assert.Contains("truncated=byte_budget", first);
        }

        [Fact]
        public void UniqueFastCandidateCreatesSeparateNormalSlotAndAmbiguityRetainsGap()
        {
            using (var recorder = new FocusIncidentRecorder(_root, "fixture", () => _now))
            {
                recorder.Append(Row("mouse.down", new JObject { ["mouseId"] = "normal", ["injected"] = false,
                    ["targetEligible"] = true, ["cacheAgeMs"] = 1 }));
                Advance(30);
                recorder.Append(Row("hud.down", new JObject { ["mouseId"] = "normal", ["candidateCount"] = 1 }));
                recorder.Append(Row("mouse.down", new JObject { ["mouseId"] = "uncertain", ["injected"] = false,
                    ["targetEligible"] = true, ["cacheAgeMs"] = 1 }));
                recorder.Append(Row("hud.down", new JObject { ["candidateCount"] = 2 }));
                Advance(500); recorder.Append("");
            }
            Assert.Equal(2, Directory.GetFiles(_root).Length);
            Assert.Contains("normal_position_time_candidate", File.ReadAllText(Path.Combine(_root, FocusIncidentRecorder.Names[3])));
            Assert.Contains("post_window_may_be_short", File.ReadAllText(Path.Combine(_root, FocusIncidentRecorder.Names[3])));
        }
    }
}
