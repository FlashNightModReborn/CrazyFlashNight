using System;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using CF7Launcher.Diagnostic;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Diagnostic
{
    public class DiagnosticPackagerTests : IDisposable
    {
        private readonly string _root;

        public DiagnosticPackagerTests()
        {
            _root = Path.Combine(Path.GetTempPath(), "cf7-diagnostic-packager-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(_root);
            Directory.CreateDirectory(Path.Combine(_root, "logs"));
            Directory.CreateDirectory(Path.Combine(_root, "runtime"));
        }

        public void Dispose()
        {
            try { if (Directory.Exists(_root)) Directory.Delete(_root, true); }
            catch { }
        }

        [Fact]
        public void Pack_IncludesBootstrapAndPerfLogs()
        {
            WriteLog("launcher.log", "launcher");
            WriteLog("launcher.log.1", "launcher backup");
            WriteLog("bootstrap.log", "bootstrap");
            WriteLog("bootstrap.log.old", "bootstrap old");
            WriteLog("perf-latest.jsonl", "{\"kind\":\"session\"}");
            WriteLog("startup-exit.jsonl", "{\"reason\":\"webview2_missing\"}");
            WriteLog("startup-failure-latest.txt", "CF7-LAUNCH-WEBVIEW2-MISSING");
            string dumpDir = Path.Combine(_root, "logs", "dumps");
            Directory.CreateDirectory(dumpDir);
            File.WriteAllText(Path.Combine(dumpDir, "createdump-123.log"), "createdump", new UTF8Encoding(false));
            File.WriteAllText(Path.Combine(_root, "runtime", "cf7-runtime-manifest.tsv"), "cf7-runtime-manifest-v1", new UTF8Encoding(false));
            Directory.CreateDirectory(Path.Combine(_root, "logs", "focus-trace"));
            foreach (string name in RollingFocusLog.Names)
                File.WriteAllText(Path.Combine(_root, "logs", "focus-trace", name), "fixture");

            DiagnosticResult result = DiagnosticPackager.Pack(_root, null, null, null);

            Assert.True(result.Ok, result.Error);
            Assert.True(File.Exists(result.ZipPath));

            using (ZipArchive zip = ZipFile.OpenRead(result.ZipPath))
            {
                string[] names = zip.Entries.Select(e => e.FullName).ToArray();
                Assert.Contains("logs/launcher.log", names);
                Assert.Contains("logs/launcher.log.1", names);
                Assert.Contains("logs/bootstrap.log", names);
                Assert.Contains("logs/bootstrap.log.old", names);
                Assert.Contains("logs/perf-latest.jsonl", names);
                Assert.Contains("logs/startup-exit.jsonl", names);
                Assert.Contains("logs/startup-failure-latest.txt", names);
                Assert.Contains("logs/dumps/createdump-123.log", names);
                Assert.Contains("runtime/cf7-runtime-manifest.tsv", names);
                foreach (string name in RollingFocusLog.Names)
                    Assert.Contains("logs/focus-trace/" + name, names);
            }
        }

        [Fact]
        public void Pack_IncludesBoundedWebViewFailureBundleWithIntegrityHashes()
        {
            WriteLog("launcher.log", "launcher");
            WriteLog("bootstrap.log", "bootstrap");
            string crashpad = Path.Combine(_root, "launcher", "webview2_overlay_userdata",
                "EBWebView", "Crashpad", "reports", "crash-1");
            Directory.CreateDirectory(crashpad);
            byte[] dump = Encoding.UTF8.GetBytes("minidump-fixture");
            File.WriteAllBytes(Path.Combine(crashpad, "crash.dmp"), dump);
            File.WriteAllBytes(Path.Combine(crashpad, "notes.txt"), new byte[] { 1, 2, 3 });
            File.WriteAllBytes(Path.Combine(crashpad, "cookie.dat"), new byte[] { 9 });
            WriteLog("webview-failures.jsonl", new JObject
            {
                ["kind"] = "browser_process_exited", ["reason"] = "STATUS_BREAKPOINT",
                ["session"] = "s-pack", ["failureReportFolderPath"] = crashpad
            }.ToString(Newtonsoft.Json.Formatting.None));

            DiagnosticResult result = DiagnosticPackager.Pack(_root, null, null, null);
            Assert.True(result.Ok, result.Error);

            using (ZipArchive zip = ZipFile.OpenRead(result.ZipPath))
            {
                string[] names = zip.Entries.Select(e => e.FullName).ToArray();
                Assert.Contains("logs/webview-failures.jsonl", names);
                Assert.Contains("webview-failures/manifest.json", names);
                Assert.Contains("webview-failures/reports/r00/crash.dmp", names);
                Assert.Contains("webview-failures/reports/r00/notes.txt", names);
                // 非白名单扩展（cookie/任意二进制）不得进包
                Assert.DoesNotContain(names, n => n.EndsWith("cookie.dat"));

                JObject manifest = JObject.Parse(ReadEntry(zip, "webview-failures/manifest.json"));
                foreach (JObject entry in (JArray)manifest["included"])
                {
                    ZipArchiveEntry placed = zip.GetEntry((string)entry["file"]);
                    Assert.NotNull(placed);
                    using (Stream s = placed.Open())
                    using (var ms = new MemoryStream())
                    {
                        s.CopyTo(ms);
                        Assert.Equal((string)entry["sha256"],
                            Convert.ToHexString(SHA256.HashData(ms.ToArray())));
                    }
                }
                Assert.True(manifest["omitted"].OfType<JObject>()
                    .Any(o => (string)o["reason"] == "unsupported_extension"));
            }
        }

        [Fact]
        public void Pack_ToleratesLockedReportFile()
        {
            WriteLog("launcher.log", "launcher");
            WriteLog("bootstrap.log", "bootstrap");
            string crashpad = Path.Combine(_root, "launcher", "webview2_overlay_userdata",
                "EBWebView", "Crashpad", "reports", "held");
            Directory.CreateDirectory(crashpad);
            string heldPath = Path.Combine(crashpad, "held.dmp");
            File.WriteAllBytes(heldPath, new byte[64]);
            WriteLog("webview-failures.jsonl", new JObject
            {
                ["kind"] = "render_process_exited", ["failureReportFolderPath"] = crashpad
            }.ToString(Newtonsoft.Json.Formatting.None));

            DiagnosticResult result;
            using (new FileStream(heldPath, FileMode.Open, FileAccess.ReadWrite, FileShare.None))
                result = DiagnosticPackager.Pack(_root, null, null, null);

            Assert.True(result.Ok, result.Error);
            using (ZipArchive zip = ZipFile.OpenRead(result.ZipPath))
            {
                JObject manifest = JObject.Parse(ReadEntry(zip, "webview-failures/manifest.json"));
                Assert.Empty(manifest["included"]);
                Assert.True(manifest["omitted"].OfType<JObject>()
                    .Any(o => (string)o["reason"] == "locked_or_unreadable"));
            }
        }

        [Fact]
        public void Pack_WithoutWebViewLogStillWritesManifest()
        {
            WriteLog("launcher.log", "launcher");
            WriteLog("bootstrap.log", "bootstrap");
            DiagnosticResult result = DiagnosticPackager.Pack(_root, null, null, null);
            Assert.True(result.Ok, result.Error);
            using (ZipArchive zip = ZipFile.OpenRead(result.ZipPath))
            {
                JObject manifest = JObject.Parse(ReadEntry(zip, "webview-failures/manifest.json"));
                Assert.Equal("log_missing", (string)manifest["failuresLog"]["omittedReason"]);
            }
        }

        private static string ReadEntry(ZipArchive zip, string name)
        {
            using (var reader = new StreamReader(zip.GetEntry(name).Open()))
                return reader.ReadToEnd();
        }

        private void WriteLog(string name, string content)
        {
            File.WriteAllText(Path.Combine(_root, "logs", name), content, new UTF8Encoding(false));
        }
    }
}
