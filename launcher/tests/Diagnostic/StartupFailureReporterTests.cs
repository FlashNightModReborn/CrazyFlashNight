using System;
using System.IO;
using System.Linq;
using CF7Launcher.Diagnostic;
using Xunit;

namespace CF7Launcher.Tests.Diagnostic
{
    public class StartupFailureReporterTests : IDisposable
    {
        private readonly string _root;

        public StartupFailureReporterTests()
        {
            _root = Path.Combine(Path.GetTempPath(), "cf7-startup-failure-reporter-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(Path.Combine(_root, "logs"));
            File.WriteAllText(Path.Combine(_root, "logs", "launcher.log"), "launcher");
            File.WriteAllText(Path.Combine(_root, "logs", "bootstrap.log"), "bootstrap");
        }

        public void Dispose()
        {
            try { if (Directory.Exists(_root)) Directory.Delete(_root, true); }
            catch { }
        }

        [Fact]
        public void CreateReport_WritesSummaryAndDiagnosticPackage()
        {
            StartupFailureReport report = StartupFailureReporter.CreateReport(
                _root,
                "webview2_missing",
                "CF7-LAUNCH-WEBVIEW2-MISSING",
                "WebView2 Runtime 不可用",
                "forced test",
                "install WebView2",
                null,
                null,
                null,
                true);

            Assert.Equal("CF7-LAUNCH-WEBVIEW2-MISSING", report.Code);
            Assert.True(report.PackageOk, report.PackageError);
            Assert.True(File.Exists(report.ZipPath));
            Assert.True(File.Exists(report.SummaryPath));

            string summary = File.ReadAllText(report.SummaryPath);
            Assert.Contains("CF7-LAUNCH-WEBVIEW2-MISSING", summary);
            Assert.Contains("forced test", summary);
            Assert.Contains("install WebView2", summary);
        }

        [Fact]
        public void LaunchFlowReasonMapping_UsesSpecificCodes()
        {
            Assert.Equal("CF7-LAUNCH-FLASH-START",
                StartupFailureReporter.CodeForLaunchFlowReason("flash_start_failed"));
            Assert.Equal("CF7-LAUNCH-FLOW-ERROR",
                StartupFailureReporter.CodeForLaunchFlowReason("unexpected"));
            Assert.Contains("重试", StartupFailureReporter.RecommendationForLaunchFlowReason("unexpected"));
        }
    }
}
