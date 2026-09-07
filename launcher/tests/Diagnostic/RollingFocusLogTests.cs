using System;
using System.IO;
using System.Linq;
using CF7Launcher.Diagnostic;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Diagnostic
{
    public sealed class RollingFocusLogTests : IDisposable
    {
        private readonly string _root = Path.Combine(Path.GetTempPath(), "cf7-focus-ring-" + Guid.NewGuid().ToString("N"));
        private string LogDirectory => Path.Combine(_root, "logs", "focus-trace");
        public void Dispose() { FocusTrace.Stop(); if (Directory.Exists(_root)) Directory.Delete(_root, true); }

        [Fact]
        public void RotationKeepsRecentBoundedSegmentsAndTheirSessionIdentity()
        {
            using (var log = new RollingFocusLog(LogDirectory, new JObject { ["session"] = "fixture.one" }, 1024))
                for (int i = 0; i < 80; i++) log.Append("row=" + i + " " + new string('x', 100));
            string[] paths = Directory.GetFiles(LogDirectory, "focus-trace.log*");
            Assert.Equal(3, paths.Length);
            Assert.All(paths, p => Assert.True(new FileInfo(p).Length <= 1024));
            string recent = string.Join("\n", paths.Select(File.ReadAllText));
            Assert.Contains("row=79 ", recent);
            Assert.DoesNotContain("row=0 ", recent);
            Assert.All(paths, p => Assert.Contains("fixture.one", File.ReadLines(p).First()));
            using (var log = new RollingFocusLog(LogDirectory, new JObject { ["session"] = "fixture.two" }, 1024))
                log.Append("new-session-row");
            Assert.Contains("fixture.two", File.ReadAllText(Path.Combine(LogDirectory, "focus-trace.log")));
            Assert.Contains("fixture.one", File.ReadAllText(Path.Combine(LogDirectory, "focus-trace.log.1")));
            Assert.Equal("stopped", (string)JObject.Parse(File.ReadAllText(Path.Combine(LogDirectory, "recording-context.json")))["status"]);
        }

        [Fact]
        public void OversizedLineIsExplicitAndCannotExceedStorageBudget()
        {
            using (var log = new RollingFocusLog(LogDirectory, new JObject { ["session"] = "fixture" }, 1024))
            {
                log.Append(new string('x', 5000));
                log.MarkError("fixture failure");
            }
            string text = File.ReadAllText(Path.Combine(LogDirectory, "focus-trace.log"));
            Assert.Contains("storage.line_dropped", text);
            Assert.True(new FileInfo(Path.Combine(LogDirectory, "focus-trace.log")).Length <= 1024);
            Assert.Equal("write_error", (string)JObject.Parse(File.ReadAllText(Path.Combine(LogDirectory, "recording-context.json")))["status"]);
        }

        [Fact]
        public void NormalConfiguredStartupRecordsAndStopsWithoutDiagnosticLauncher()
        {
            Directory.CreateDirectory(_root);
            FocusTrace.StartConfigured(false, _root);
            Assert.False(Directory.Exists(LogDirectory));
            FocusTrace.StartConfigured(true, _root);
            Assert.True(FocusTrace.Enabled);
            Assert.True(FocusTrace.IsRolling);
            string session = FocusTrace.Session;
            FocusTrace.Record("fixture.normal_start");
            FocusTrace.CaptureAs2LogBatch("[FocusTraceAS2] session=" + session + " seq=1 event=observe_ready detail=rolling_host_retention");
            FocusTrace.Stop();
            string text = File.ReadAllText(Path.Combine(LogDirectory, "focus-trace.log"));
            Assert.Contains("fixture.normal_start", text);
            Assert.Contains("trace.stop", text);
            JObject context = JObject.Parse(File.ReadAllText(Path.Combine(LogDirectory, "recording-context.json")));
            Assert.Equal(session, (string)context["session"]);
            Assert.True((bool)context["as2ObserveReadySeen"]);
            Assert.Equal("stopped", (string)context["status"]);
        }
    }
}
