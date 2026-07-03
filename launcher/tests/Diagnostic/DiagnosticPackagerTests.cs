using System;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Text;
using CF7Launcher.Diagnostic;
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
            }
        }

        private void WriteLog(string name, string content)
        {
            File.WriteAllText(Path.Combine(_root, "logs", name), content, new UTF8Encoding(false));
        }
    }
}
