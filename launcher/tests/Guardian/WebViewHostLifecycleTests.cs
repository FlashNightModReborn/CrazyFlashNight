using System;
using System.IO;
using Newtonsoft.Json.Linq;
using Xunit;
using CF7Launcher.Diagnostic;
using CF7Launcher.Guardian;
using Microsoft.Web.WebView2.Core;

namespace CF7Launcher.Tests.Guardian
{
    /// <summary>
    /// Host-side WebView lifecycle hardening tests: process-failure routing/classification and
    /// the bounded failure recorder contract consumed by WebViewFailureReportCollector.
    /// </summary>
    public class WebViewHostLifecycleTests
    {
        [Theory]
        [InlineData(CoreWebView2ProcessFailedKind.BrowserProcessExited,
            "MainDocumentExited")]
        [InlineData(CoreWebView2ProcessFailedKind.RenderProcessExited,
            "MainDocumentExited")]
        [InlineData(CoreWebView2ProcessFailedKind.FrameRenderProcessExited,
            "Ancillary")]
        [InlineData(CoreWebView2ProcessFailedKind.RenderProcessUnresponsive,
            "RendererHung")]
        [InlineData(CoreWebView2ProcessFailedKind.GpuProcessExited,
            "Ancillary")]
        [InlineData(CoreWebView2ProcessFailedKind.UtilityProcessExited,
            "Ancillary")]
        [InlineData(CoreWebView2ProcessFailedKind.SandboxHelperProcessExited,
            "Ancillary")]
        [InlineData(CoreWebView2ProcessFailedKind.PpapiPluginProcessExited,
            "Ancillary")]
        [InlineData(CoreWebView2ProcessFailedKind.PpapiBrokerProcessExited,
            "Ancillary")]
        [InlineData(CoreWebView2ProcessFailedKind.UnknownProcessExited,
            "Ancillary")]
        public void ProcessFailureKind_RoutesToExpectedClass(
            CoreWebView2ProcessFailedKind kind,
            string expected)
        {
            Assert.Equal(expected,
                WebOverlayForm.ClassifyWebProcessFailure(kind).ToString());
        }

        [Fact]
        public void OldRuntimeOptionalMetadataFailurePreservesAvailableFields()
        {
            string unavailable = WebOverlayForm.ReadOptionalFailureMetadata<string>(
                () => throw new NotImplementedException("old runtime"), null);
            int? exitCode = WebOverlayForm.ReadOptionalFailureMetadata<int?>(() => -1, null);
            Assert.Null(unavailable);
            Assert.Equal(-1, exitCode);
            Assert.Equal(WebOverlayForm.WebProcessFailureClass.MainDocumentExited,
                WebOverlayForm.ClassifyWebProcessFailure(CoreWebView2ProcessFailedKind.RenderProcessExited));
        }

        [Fact]
        public void FailureRecorder_BuildJson_EmitsCollectorContractFields()
        {
            JObject json = WebViewFailureRecorder.BuildJson(
                new WebViewFailureRecorder.Entry
                {
                    Kind = "RenderProcessExited",
                    Reason = "Crashed",
                    ExitCode = -1073740791,
                    BrowserVersion = "118.0.2088.46",
                    BrowserProcessId = 1234,
                    DocumentGeneration = 5,
                    HostLifecycleGeneration = 2,
                    HostHandle = 0xABCDEF,
                    Classification = "main_document",
                    FailureReportFolderPath = "C:\\logs\\webview2failures",
                    ProcessDescription = "test process",
                    FailureSourceModulePath = "msedgewebview2.dll",
                    FrameCount = 3,
                    Detail = "attempt=1"
                });

            Assert.Equal(WebViewFailureRecorder.SchemaVersion, json.Value<int>("v"));
            Assert.False(string.IsNullOrEmpty(json.Value<string>("atUtc")));
            Assert.False(string.IsNullOrEmpty(json.Value<string>("session")));
            Assert.Equal("RenderProcessExited", json.Value<string>("kind"));
            Assert.Equal("Crashed", json.Value<string>("reason"));
            Assert.Equal(-1073740791, json.Value<int>("exitCode"));
            Assert.Equal("118.0.2088.46", json.Value<string>("browserVersion"));
            Assert.Equal(1234, json.Value<long>("browserProcessId"));
            Assert.Equal(5, json.Value<int>("documentGeneration"));
            Assert.Equal(2, json.Value<int>("hostLifecycleGeneration"));
            Assert.Equal("main_document", json.Value<string>("classification"));
            Assert.Equal("C:\\logs\\webview2failures",
                json.Value<string>("failureReportFolderPath"));
            Assert.Equal(3, json.Value<int>("frameCount"));
        }

        [Fact]
        public void FailureRecorder_BuildJson_OmitsNullsAndTrimsLongFields()
        {
            JObject json = WebViewFailureRecorder.BuildJson(
                new WebViewFailureRecorder.Entry
                {
                    Kind = "GpuProcessExited",
                    ProcessDescription = new string('x',
                        WebViewFailureRecorder.MaxFieldChars + 64)
                });

            Assert.Equal("GpuProcessExited", json.Value<string>("kind"));
            Assert.Null(json["reason"]);
            Assert.Null(json["exitCode"]);
            Assert.Null(json["failureReportFolderPath"]);
            Assert.Equal(WebViewFailureRecorder.MaxFieldChars,
                json.Value<string>("processDescription").Length);

            Assert.Null(WebViewFailureRecorder.BuildJson(null));
            Assert.Null(WebViewFailureRecorder.BuildJson(
                new WebViewFailureRecorder.Entry()));
        }

        [Fact]
        public void FailureRecorder_AppendLineBounded_AppendsAndRotates()
        {
            string dir = Path.Combine(
                Path.GetTempPath(), "cf7-webview-failures-" + Guid.NewGuid().ToString("N"));
            try
            {
                string path = Path.Combine(dir, "webview-failures.jsonl");
                Assert.True(WebViewFailureRecorder.AppendLineBounded(
                    path, "{\"kind\":\"A\"}"));
                Assert.True(WebViewFailureRecorder.AppendLineBounded(
                    path, "{\"kind\":\"B\"}"));

                string[] lines = File.ReadAllLines(path);
                Assert.Equal(2, lines.Length);
                Assert.Equal("A", JObject.Parse(lines[0]).Value<string>("kind"));
                Assert.Equal("B", JObject.Parse(lines[1]).Value<string>("kind"));

                // 超上界单份轮转：旧体进 .1，新行落在主文件。
                File.WriteAllText(path, new string('y',
                    (int)WebViewFailureRecorder.MaxFileBytes));
                Assert.True(WebViewFailureRecorder.AppendLineBounded(
                    path, "{\"kind\":\"C\"}"));
                Assert.True(File.Exists(path + ".1"));
                lines = File.ReadAllLines(path);
                Assert.Single(lines);
                Assert.Equal("C", JObject.Parse(lines[0]).Value<string>("kind"));

                Assert.False(WebViewFailureRecorder.AppendLineBounded(null, "x"));
                Assert.False(WebViewFailureRecorder.AppendLineBounded(path, ""));
            }
            finally
            {
                try { Directory.Delete(dir, true); } catch { }
            }
        }

        [Fact]
        public void FailureRecorder_Record_UsesConfiguredPath()
        {
            string dir = Path.Combine(
                Path.GetTempPath(), "cf7-webview-failures-" + Guid.NewGuid().ToString("N"));
            WebViewFailureRecorder.ResetForTests();
            try
            {
                // 未配置时静默 false
                Assert.False(WebViewFailureRecorder.Record(
                    new WebViewFailureRecorder.Entry { Kind = "A" }));

                WebViewFailureRecorder.Configure(dir);
                Assert.True(WebViewFailureRecorder.Record(
                    new WebViewFailureRecorder.Entry
                    {
                        Kind = "BrowserProcessExited",
                        Reason = "Failed",
                        BrowserProcessId = 42
                    }));
                string path = Path.Combine(dir, "logs",
                    WebViewFailureRecorder.FileName);
                Assert.True(File.Exists(path));
                JObject line = JObject.Parse(File.ReadAllLines(path)[0]);
                Assert.Equal("BrowserProcessExited", line.Value<string>("kind"));
                Assert.Equal("Failed", line.Value<string>("reason"));
            }
            finally
            {
                WebViewFailureRecorder.ResetForTests();
                try { Directory.Delete(dir, true); } catch { }
            }
        }
    }
}
