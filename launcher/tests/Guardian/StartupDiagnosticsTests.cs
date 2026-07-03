using System;
using System.IO;
using System.Linq;
using System.Text;
using CF7Launcher.Guardian;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public class StartupDiagnosticsTests : IDisposable
    {
        private readonly string _root;

        public StartupDiagnosticsTests()
        {
            _root = Path.Combine(Path.GetTempPath(), "cf7-startup-diagnostics-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(_root);
        }

        public void Dispose()
        {
            StartupDiagnostics.Init(Path.GetTempPath());
            try { if (Directory.Exists(_root)) Directory.Delete(_root, true); }
            catch { }
        }

        [Fact]
        public void ExitAndFailure_WriteBoundedStartupExitJsonl()
        {
            StartupDiagnostics.Init(_root);

            for (int i = 0; i < 25; i++)
                StartupDiagnostics.Failure("launchflow_error:test_" + i, "detail=" + i);
            StartupDiagnostics.Exit("webview2_missing", "bad\nquote \"slash\\中文");

            string path = Path.Combine(_root, "logs", "startup-exit.jsonl");
            Assert.True(File.Exists(path));

            string[] lines = File.ReadAllLines(path, Encoding.UTF8);
            Assert.Equal(20, lines.Length);
            Assert.DoesNotContain(lines, line => line.Contains("test_0"));
            Assert.Contains(lines, line => line.Contains("\"kind\":\"failure\"") && line.Contains("\"terminal\":false"));
            Assert.Contains("\"kind\":\"exit\"", lines.Last());
            Assert.Contains("\"reason\":\"webview2_missing\"", lines.Last());
            Assert.Contains("\"terminal\":true", lines.Last());
            Assert.Contains("bad\\nquote \\\"slash\\\\中文", lines.Last());
        }

        [Fact]
        public void Mark_WritesBootstrapLogWhileAnotherWriterHandleIsOpen()
        {
            string logDir = Path.Combine(_root, "logs");
            Directory.CreateDirectory(logDir);
            string logPath = Path.Combine(logDir, "bootstrap.log");

            using (FileStream nativeLikeHandle = new FileStream(logPath, FileMode.OpenOrCreate, FileAccess.Write,
                FileShare.ReadWrite | FileShare.Delete))
            {
                nativeLikeHandle.Seek(0, SeekOrigin.End);
                byte[] prefix = Encoding.UTF8.GetBytes("[native] open\r\n");
                nativeLikeHandle.Write(prefix, 0, prefix.Length);

                StartupDiagnostics.Init(_root);
                StartupDiagnostics.Mark("share_mode_probe", "ok");
            }

            string text = File.ReadAllText(logPath, Encoding.UTF8);
            Assert.Contains("[native] open", text);
            Assert.Contains("[core-startup] [INFO] share_mode_probe ok", text);
        }
    }
}
