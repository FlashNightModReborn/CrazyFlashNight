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
    public class WebViewFailureReportCollectorTests : IDisposable
    {
        private readonly string _root;
        private readonly string _dest;

        public WebViewFailureReportCollectorTests()
        {
            _root = Path.Combine(Path.GetTempPath(), "cf7-wvf-" + Guid.NewGuid().ToString("N"));
            _dest = Path.Combine(_root, "snapshot");
            Directory.CreateDirectory(Path.Combine(_root, "logs"));
            Directory.CreateDirectory(_dest);
        }

        public void Dispose()
        {
            try { if (Directory.Exists(_root)) Directory.Delete(_root, true); }
            catch { }
        }

        private string Crashpad(string userData)
        {
            return Path.Combine(_root, "launcher", userData, "EBWebView", "Crashpad");
        }

        private string OverlayCrashpad() { return Crashpad("webview2_overlay_userdata"); }

        private string WriteReportFolder(string folder, params string[] names)
        {
            Directory.CreateDirectory(folder);
            foreach (string name in names)
                File.WriteAllBytes(Path.Combine(folder, name),
                    Encoding.UTF8.GetBytes("payload:" + name));
            return folder;
        }

        private void WriteJsonl(params string[] lines)
        {
            File.WriteAllText(Path.Combine(_root, "logs", "webview-failures.jsonl"),
                string.Join("\n", lines) + "\n", new UTF8Encoding(false));
        }

        private static string FailureLine(string folder, string session)
        {
            return new JObject
            {
                ["kind"] = "browser_process_exited",
                ["reason"] = "STATUS_BREAKPOINT",
                ["exitCode"] = -2147483645,
                ["browserVersion"] = "118.0.2088.46",
                ["session"] = session,
                ["documentGeneration"] = 3,
                ["atUtc"] = DateTime.UtcNow.ToString("O"),
                ["failureReportFolderPath"] = folder
            }.ToString(Newtonsoft.Json.Formatting.None);
        }

        private WebViewFailureReportCollector.Result Collect()
        {
            return WebViewFailureReportCollector.Collect(_root,
                new WebViewFailureReportCollector.DirectorySink(_dest));
        }

        private JObject ReadManifest()
        {
            return JObject.Parse(File.ReadAllText(
                Path.Combine(_dest, "webview-failures-manifest.json")));
        }

        private static JArray Omitted(JObject manifest) { return (JArray)manifest["omitted"]; }

        private static bool HasReason(JObject manifest, string reason)
        {
            return Omitted(manifest).OfType<JObject>().Any(o => (string)o["reason"] == reason);
        }

        [Fact]
        public void CollectsReferencedReportsWithConsistentHashes()
        {
            string folder = WriteReportFolder(
                Path.Combine(OverlayCrashpad(), "reports", "abc-123"), "a.dmp", "note.txt", "skip.exe");
            WriteJsonl(FailureLine(folder, "session-1"));

            WebViewFailureReportCollector.Result result = Collect();
            JObject manifest = ReadManifest();

            Assert.True(result.LogIncluded);
            Assert.True(File.Exists(Path.Combine(_dest, "webview-failures.jsonl")));
            Assert.Equal(2, (int)manifest["included"].Count());

            JObject dmp = manifest["included"].OfType<JObject>()
                .Single(e => (string)e["file"] == "wvf-r00-a.dmp");
            byte[] placed = File.ReadAllBytes(Path.Combine(_dest, "wvf-r00-a.dmp"));
            Assert.Equal(Convert.ToHexString(SHA256.HashData(placed)), (string)dmp["sha256"]);
            Assert.Equal("log", (string)dmp["origin"]);
            Assert.Equal("session-1", (string)dmp["session"]);
            Assert.Equal("browser_process_exited", (string)dmp["kind"]);
            Assert.Equal("STATUS_BREAKPOINT", (string)dmp["failureReason"]);
            Assert.Equal("launcher/webview2_overlay_userdata/EBWebView/Crashpad/reports/abc-123/a.dmp",
                (string)dmp["sourcePath"]);
            Assert.True(HasReason(manifest, "unsupported_extension"));
            Assert.DoesNotContain(Directory.GetFiles(_dest), f => f.EndsWith(".exe"));
        }

        [Fact]
        public void RejectsTraversalOutsideRootAndRelativePaths()
        {
            WriteJsonl(
                FailureLine("..\\..\\outside", "s-rel"),
                FailureLine("C:\\Windows\\System32", "s-abs"),
                FailureLine(Path.Combine(OverlayCrashpad(), "..", "..", "Default"), "s-trav"),
                FailureLine("C:\\bad|path", "s-bad"));

            Collect();
            JObject manifest = ReadManifest();

            Assert.Empty(manifest["included"]);
            Assert.True(HasReason(manifest, "outside_allowed_root"));
            Assert.True(HasReason(manifest, "invalid_path"));
            // 穿越回 UDF 但逃出 Crashpad 根也必须拒收
            Assert.Contains(Omitted(manifest).OfType<JObject>(),
                o => (string)o["reason"] == "outside_allowed_root"
                    && ((string)o["candidate"]).Contains(".."));
        }

        [Fact]
        public void JunctionReportFolderRejected()
        {
            string outside = WriteReportFolder(Path.Combine(_root, "outside-reports"), "x.dmp");
            string link = Path.Combine(OverlayCrashpad(), "reports", "jlink");
            Directory.CreateDirectory(Path.GetDirectoryName(link));
            var psi = new System.Diagnostics.ProcessStartInfo("cmd.exe",
                "/c mklink /J \"" + link + "\" \"" + outside + "\"")
            { CreateNoWindow = true, UseShellExecute = false };
            using (var p = System.Diagnostics.Process.Start(psi)) { p.WaitForExit(); }
            if (!Directory.Exists(link)) return; // 环境不允许建 junction 时跳过断言

            WriteJsonl(FailureLine(link, "s-junction"));
            Collect();
            JObject manifest = ReadManifest();
            Assert.True(HasReason(manifest, "reparse_point"));
            Assert.Empty(manifest["included"]);
        }

        [Fact]
        public void JunctionOnUserDataAncestorRejected()
        {
            // F-05：允许根上方的已知祖先（整个 UDF 目录）被做成 junction 时，
            // 字符串路径仍在允许根内但真实字节已越界——必须记 reparse_point 省略而非跟随。
            string outsideUdf = Path.Combine(_root, "outside-udf");
            string folder = WriteReportFolder(
                Path.Combine(outsideUdf, "EBWebView", "Crashpad", "reports", "via-udf"),
                "x.dmp");
            string udf = Path.Combine(_root, "launcher", "webview2_overlay_userdata");
            Directory.CreateDirectory(Path.GetDirectoryName(udf));
            var psi = new System.Diagnostics.ProcessStartInfo("cmd.exe",
                "/c mklink /J \"" + udf + "\" \"" + outsideUdf + "\"")
            { CreateNoWindow = true, UseShellExecute = false };
            using (var p = System.Diagnostics.Process.Start(psi)) { p.WaitForExit(); }
            if (!Directory.Exists(udf)) return; // 环境不允许建 junction 时跳过断言

            string linkedFolder = Path.Combine(
                OverlayCrashpad(), "reports", "via-udf");
            WriteJsonl(FailureLine(linkedFolder, "s-udf-junction"));
            Collect();
            JObject manifest = ReadManifest();
            Assert.True(HasReason(manifest, "reparse_point"));
            Assert.Empty(manifest["included"]);
        }

        [Fact]
        public void LockedFileOmittedWithoutLosingOthers()
        {
            string folder = WriteReportFolder(
                Path.Combine(OverlayCrashpad(), "reports", "locked"), "ok.dmp", "held.dmp");
            WriteJsonl(FailureLine(folder, "s-lock"));
            using (FileStream held = new FileStream(Path.Combine(folder, "held.dmp"),
                FileMode.Open, FileAccess.ReadWrite, FileShare.None))
            {
                Collect();
            }
            JObject manifest = ReadManifest();
            Assert.Single(manifest["included"]);
            Assert.Equal("wvf-r00-ok.dmp", (string)manifest["included"][0]["file"]);
            Assert.True(HasReason(manifest, "locked_or_unreadable"));
        }

        [Fact]
        public void EnforcesAgeSizeCountAndTotalCaps()
        {
            string folder = Path.Combine(OverlayCrashpad(), "reports", "caps");
            Directory.CreateDirectory(folder);
            File.WriteAllBytes(Path.Combine(folder, "old.dmp"), new byte[16]);
            File.SetLastWriteTimeUtc(Path.Combine(folder, "old.dmp"),
                DateTime.UtcNow - TimeSpan.FromDays(30));
            File.WriteAllBytes(Path.Combine(folder, "huge.dmp"),
                new byte[WebViewFailureReportCollector.MaxFileBytes + 1]);
            WriteJsonl(FailureLine(folder, "s-caps"));

            Collect();
            JObject manifest = ReadManifest();
            Assert.True(HasReason(manifest, "too_old"));
            Assert.True(HasReason(manifest, "too_large"));
            Assert.Empty(manifest["included"]);
        }

        [Fact]
        public void PerFolderCountCapAggregates()
        {
            string folder = Path.Combine(OverlayCrashpad(), "reports", "many");
            Directory.CreateDirectory(folder);
            for (int i = 0; i < WebViewFailureReportCollector.MaxFilesPerFolder + 3; i++)
                File.WriteAllBytes(Path.Combine(folder, "f" + i + ".dmp"), new byte[8]);
            WriteJsonl(FailureLine(folder, "s-many"));

            Collect();
            JObject manifest = ReadManifest();
            Assert.Equal(WebViewFailureReportCollector.MaxFilesPerFolder, manifest["included"].Count());
            Assert.True(HasReason(manifest, "file_count_cap"));
        }

        [Fact]
        public void TotalBytesCapRecorded()
        {
            string folder = Path.Combine(OverlayCrashpad(), "reports", "big");
            Directory.CreateDirectory(folder);
            // 每个文件在单文件上限内，但累计超过总量上限 → 触发 total_bytes_cap。
            long each = WebViewFailureReportCollector.MaxFileBytes - 1024 * 1024; // 7 MiB
            for (int i = 0; i < 4; i++)
            {
                string p = Path.Combine(folder, "b" + i + ".dmp");
                File.WriteAllBytes(p, new byte[each]);
                File.SetLastWriteTimeUtc(p, DateTime.UtcNow.AddSeconds(-i));
            }
            WriteJsonl(FailureLine(folder, "s-big"));

            Collect();
            JObject manifest = ReadManifest();
            Assert.Equal(3, manifest["included"].Count()); // 21MiB < 24MiB cap，第 4 个 7MiB 触发总量上限
            Assert.True(HasReason(manifest, "total_bytes_cap"));
        }

        [Fact]
        public void LogTailBoundedToWholeLines()
        {
            string folder = WriteReportFolder(Path.Combine(OverlayCrashpad(), "reports", "t"), "a.dmp");
            var sb = new StringBuilder();
            while (sb.Length < WebViewFailureReportCollector.MaxLogTailBytes * 2)
                sb.Append(FailureLine(folder, "s-tail")).Append('\n');
            File.WriteAllText(Path.Combine(_root, "logs", "webview-failures.jsonl"),
                sb.ToString(), new UTF8Encoding(false));

            WebViewFailureReportCollector.Result result = Collect();
            JObject manifest = ReadManifest();

            Assert.True(result.LogTruncated);
            byte[] placed = File.ReadAllBytes(Path.Combine(_dest, "webview-failures.jsonl"));
            Assert.True(placed.LongLength <= WebViewFailureReportCollector.MaxLogTailBytes);
            string firstLine = Encoding.UTF8.GetString(placed)
                .Split(new[] { '\n' }, StringSplitOptions.RemoveEmptyEntries)[0];
            JObject.Parse(firstLine); // 首行必须是完整 JSON，不带被截断的半行
        }

        // 共享读期间被追加的文件：Length 在开句柄时合法，读循环必须自带累计上限。
        private sealed class EndlessReadStream : Stream
        {
            public override bool CanRead => true;
            public override bool CanSeek => false;
            public override bool CanWrite => false;
            public override long Length => 0;
            public override long Position { get => 0; set { } }
            public override void Flush() { }
            public override int Read(byte[] buffer, int offset, int count) { return count; }
            public override long Seek(long offset, SeekOrigin origin) { return 0; }
            public override void SetLength(long value) { }
            public override void Write(byte[] buffer, int offset, int count) { }
        }

        [Fact]
        public void GrowingFileCappedInsideReadLoop()
        {
            byte[] r = WebViewFailureReportCollector.ReadCapped(
                new EndlessReadStream(), 128 * 1024, out string error);
            Assert.Null(r);
            Assert.Equal("too_large", error);
        }

        [Fact]
        public void RotatedLogTailAlsoCollectedAndParsed()
        {
            // worker01 记录器超限后轮转到 .1；轮转份中的报告目录引用同样要回收。
            string folder = WriteReportFolder(
                Path.Combine(OverlayCrashpad(), "reports", "rot"), "r.dmp");
            File.WriteAllText(Path.Combine(_root, "logs", "webview-failures.jsonl.1"),
                FailureLine(folder, "s-rot") + "\n", new UTF8Encoding(false));
            File.WriteAllText(Path.Combine(_root, "logs", "webview-failures.jsonl"),
                "{\"kind\":\"session_marker\"}\n", new UTF8Encoding(false));

            Collect();
            JObject manifest = ReadManifest();
            Assert.True(File.Exists(Path.Combine(_dest, "webview-failures.jsonl.1")));
            Assert.True((bool)manifest["failuresLog"]["rotated"]["included"]);
            JObject inc = (JObject)Assert.Single(manifest["included"]);
            Assert.Equal("s-rot", (string)inc["session"]);
        }

        [Fact]
        public void MissingLogStillWritesManifestWithExplicitReason()
        {
            Collect();
            JObject manifest = ReadManifest();
            Assert.Equal("log_missing", (string)manifest["failuresLog"]["omittedReason"]);
            Assert.Empty(manifest["included"]);
        }

        [Fact]
        public void ReportsScanCollectsUnreferencedRecentDumps()
        {
            string reports = Path.Combine(OverlayCrashpad(), "reports");
            Directory.CreateDirectory(reports);
            File.WriteAllBytes(Path.Combine(reports, "fresh.dmp"), new byte[32]);
            File.WriteAllBytes(Path.Combine(reports, "stale.dmp"), new byte[32]);
            File.SetLastWriteTimeUtc(Path.Combine(reports, "stale.dmp"),
                DateTime.UtcNow - TimeSpan.FromDays(60));

            Collect();
            JObject manifest = ReadManifest();
            JObject fresh = manifest["included"].OfType<JObject>()
                .Single(e => ((string)e["file"]).EndsWith("fresh.dmp"));
            Assert.Equal("reports_scan", (string)fresh["origin"]);
            Assert.True(HasReason(manifest, "too_old"));
        }

        [Fact]
        public void ZipSinkPlacesStructuredEntries()
        {
            string folder = WriteReportFolder(Path.Combine(OverlayCrashpad(), "reports", "z"), "a.dmp");
            WriteJsonl(FailureLine(folder, "s-zip"));
            string zipPath = Path.Combine(_root, "out.zip");
            using (FileStream fs = new FileStream(zipPath, FileMode.Create))
            using (ZipArchive zip = new ZipArchive(fs, ZipArchiveMode.Create))
            {
                WebViewFailureReportCollector.Collect(_root,
                    new WebViewFailureReportCollector.ZipSink(zip));
            }
            using (ZipArchive zip = ZipFile.OpenRead(zipPath))
            {
                string[] names = zip.Entries.Select(e => e.FullName).ToArray();
                Assert.Contains("logs/webview-failures.jsonl", names);
                Assert.Contains("webview-failures/manifest.json", names);
                Assert.Contains("webview-failures/reports/r00/a.dmp", names);
                JObject manifest = JObject.Parse(ReadEntry(zip, "webview-failures/manifest.json"));
                JObject dmp = manifest["included"].OfType<JObject>()
                    .Single(e => (string)e["file"] == "webview-failures/reports/r00/a.dmp");
                using (Stream s = zip.GetEntry("webview-failures/reports/r00/a.dmp").Open())
                using (var ms = new MemoryStream())
                {
                    s.CopyTo(ms);
                    Assert.Equal((string)dmp["sha256"],
                        Convert.ToHexString(SHA256.HashData(ms.ToArray())));
                }
            }
        }

        private static string ReadEntry(ZipArchive zip, string name)
        {
            using (var reader = new StreamReader(zip.GetEntry(name).Open()))
                return reader.ReadToEnd();
        }
    }
}
