using System;
using System.Diagnostics;
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
    public sealed class FocusExitCollectorTests : IDisposable
    {
        private readonly string _root = Path.Combine(Path.GetTempPath(), "cf7-focus-exit-" + Guid.NewGuid().ToString("N"));
        private readonly string _previousOwner = Environment.GetEnvironmentVariable(FocusExitCollector.OwnerVariable);

        public FocusExitCollectorTests()
        {
            Environment.SetEnvironmentVariable(FocusExitCollector.OwnerVariable, null);
            Directory.CreateDirectory(Path.Combine(_root, "tools"));
            File.WriteAllText(Path.Combine(_root, "tools", "run-focus-diagnostic.ps1"), "# fixture");
        }

        public void Dispose()
        {
            FocusTrace.Stop();
            Environment.SetEnvironmentVariable(FocusExitCollector.OwnerVariable, _previousOwner);
            Directory.Delete(_root, true);
        }

        [Fact]
        public void ExitFreezesStoppedSessionBeforeHiddenCollectorAndRunsOnce()
        {
            ProcessStartInfo invocation = null;
            int calls = 0;
            FocusTrace.StartConfigured(true, _root);
            string session = FocusTrace.Session;
            FocusTrace.Record("fixture.before_exit");
            FocusTrace.Shutdown(info => { invocation = info; calls++; });
            FocusTrace.Shutdown(_ => calls++);
            Assert.Equal(1, calls);
            Assert.True(invocation.CreateNoWindow);
            Assert.False(invocation.UseShellExecute);
            Assert.Equal(ProcessWindowStyle.Hidden, invocation.WindowStyle);
            Assert.Equal(Path.Combine(Path.GetDirectoryName(invocation.FileName), "Modules"), invocation.Environment["PSModulePath"]);
            string snapshot = invocation.ArgumentList.Last();
            Assert.StartsWith(Path.Combine(_root, "logs", "focus-diagnostic", "auto-"), snapshot);
            JObject context = JObject.Parse(File.ReadAllText(Path.Combine(snapshot, "recording-context.json")));
            Assert.Equal("stopped", (string)context["status"]);
            Assert.Equal(session, (string)context["session"]);
            string frozen = File.ReadAllText(Path.Combine(snapshot, "focus-trace.log"));
            Assert.Contains("fixture.before_exit", frozen);
            Assert.Contains("trace.stop", frozen);
            FocusTrace.StartConfigured(true, _root);
            FocusTrace.Record("fixture.next_game");
            FocusTrace.Stop();
            Assert.Equal(frozen, File.ReadAllText(Path.Combine(snapshot, "focus-trace.log")));
        }

        [Fact]
        public void DisabledRecordingDoesNotCreateAutomaticArchive()
        {
            FocusTrace.StartConfigured(false, _root);
            FocusTrace.Shutdown(_ => Assert.Fail("Disabled diagnostics must not launch a collector"));
            Assert.False(Directory.Exists(Path.Combine(_root, "logs")));
        }

        [Fact]
        public void RealHiddenCollectorCreatesZipFromExitSnapshotAcrossImmediateRestart()
        {
            DirectoryInfo repository = new DirectoryInfo(AppContext.BaseDirectory);
            while (repository != null && !File.Exists(Path.Combine(repository.FullName, "tools", "run-focus-diagnostic.ps1")))
                repository = repository.Parent;
            Assert.NotNull(repository);
            File.Copy(Path.Combine(repository.FullName, "tools", "run-focus-diagnostic.ps1"),
                Path.Combine(_root, "tools", "run-focus-diagnostic.ps1"), true);
            FocusTrace.StartConfigured(true, _root);
            string session = FocusTrace.Session;
            FocusTrace.Record("fixture.automatic_zip");
            Process collector = null;
            FocusTrace.Shutdown(info => collector = Process.Start(info));
            Assert.NotNull(collector);
            string snapshot = Directory.GetDirectories(Path.Combine(_root, "logs", "focus-diagnostic")).Single();
            // 自动采集还未完成就重开；ZIP 必须保持上一轮已停止的身份与字节。
            FocusTrace.StartConfigured(true, _root);
            FocusTrace.Record("fixture.next_game_only");
            FocusTrace.Stop();
            using (collector)
            {
                if (!collector.WaitForExit(30000)) { collector.Kill(); Assert.Fail("Automatic collector did not exit in 30 seconds"); }
                string error = Path.Combine(snapshot, "collection-error.txt");
                Assert.True(collector.ExitCode == 0, File.Exists(error) ? File.ReadAllText(error) : "Collector exit=" + collector.ExitCode);
            }
            Assert.False(Directory.Exists(snapshot));
            using (ZipArchive zip = ZipFile.OpenRead(snapshot + ".zip"))
            {
                string Read(string name) { using (var reader = new StreamReader(zip.Entries.Single(e => e.Name == name).Open())) return reader.ReadToEnd(); }
                JObject context = JObject.Parse(Read("diagnostic-context.json"));
                Assert.Equal("game_exit", (string)context["collectionTrigger"]);
                Assert.Equal("recorded", (string)context["captureStatus"]);
                Assert.Equal(session, (string)context["recording"]["session"]);
                string events = Read("focus-events.txt");
                Assert.Contains("fixture.automatic_zip", events);
                Assert.Contains("trace.stop", events);
                Assert.DoesNotContain("fixture.next_game_only", events);
                foreach (JObject hash in JArray.Parse(Read("file-hashes.json")))
                {
                    using (Stream stream = zip.Entries.Single(e => e.Name == (string)hash["file"]).Open())
                        Assert.Equal((string)hash["Hash"], Convert.ToHexString(SHA256.HashData(stream)));
                }
            }
        }

        [Fact]
        public void DedicatedLauncherOwnsCollectionOnlyWhileExactProcessLives()
        {
            using (Process process = Process.GetCurrentProcess())
            {
                long started = process.StartTime.ToUniversalTime().Ticks;
                string owner = process.Id + ":" + started;
                Assert.True(FocusExitCollector.HasLiveOwner(owner));
                Assert.False(FocusExitCollector.HasLiveOwner(process.Id + ":" + (started - 1)));
                Assert.False(FocusExitCollector.HasLiveOwner("2147483647:" + started));
                Environment.SetEnvironmentVariable(FocusExitCollector.OwnerVariable, owner);
                FocusTrace.StartConfigured(true, _root);
                FocusTrace.Shutdown(_ => Assert.Fail("Dedicated launcher already waits for this exit"));
                Assert.False(Directory.Exists(Path.Combine(_root, "logs", "focus-diagnostic")));
                Environment.SetEnvironmentVariable(FocusExitCollector.OwnerVariable, process.Id + ":" + (started - 1));
                bool launched = false;
                FocusTrace.StartConfigured(true, _root);
                FocusTrace.Shutdown(_ => launched = true);
                Assert.True(launched);
            }
        }

        [Fact]
        public void ExitSnapshotIncludesBoundedWebViewFailureBundle()
        {
            string crashpad = Path.Combine(_root, "launcher", "webview2_overlay_userdata",
                "EBWebView", "Crashpad", "reports", "exit-1");
            Directory.CreateDirectory(crashpad);
            File.WriteAllBytes(Path.Combine(crashpad, "crash.dmp"),
                new UTF8Encoding(false).GetBytes("minidump"));
            File.WriteAllBytes(Path.Combine(crashpad, "stray.exe"), new byte[] { 1 });
            Directory.CreateDirectory(Path.Combine(_root, "logs"));
            File.WriteAllText(Path.Combine(_root, "logs", "webview-failures.jsonl"),
                new JObject { ["kind"] = "browser_process_exited", ["session"] = "s-exit",
                    ["failureReportFolderPath"] = crashpad }.ToString(Newtonsoft.Json.Formatting.None),
                new UTF8Encoding(false));

            ProcessStartInfo invocation = null;
            FocusTrace.StartConfigured(true, _root);
            FocusTrace.Shutdown(info => invocation = info);
            Assert.NotNull(invocation);
            string snapshot = invocation.ArgumentList.Last();

            // 快照目录只收顶层扁平文件：采集脚本的 file-hashes.json 自动覆盖这些条目。
            Assert.True(File.Exists(Path.Combine(snapshot, "webview-failures.jsonl")));
            Assert.True(File.Exists(Path.Combine(snapshot, "webview-failures-manifest.json")));
            Assert.True(File.Exists(Path.Combine(snapshot, "wvf-r00-crash.dmp")));
            Assert.False(File.Exists(Path.Combine(snapshot, "wvf-r00-stray.exe")));

            JObject auto = JObject.Parse(File.ReadAllText(Path.Combine(snapshot, "auto-collection.json")));
            Assert.True((bool)auto["webviewFailures"]["logIncluded"]);
            Assert.Equal(1, (int)auto["webviewFailures"]["filesIncluded"]);

            JObject manifest = JObject.Parse(
                File.ReadAllText(Path.Combine(snapshot, "webview-failures-manifest.json")));
            Assert.True(manifest["omitted"].OfType<JObject>()
                .Any(o => (string)o["reason"] == "unsupported_extension"));
            byte[] placed = File.ReadAllBytes(Path.Combine(snapshot, "wvf-r00-crash.dmp"));
            Assert.Equal(Convert.ToHexString(SHA256.HashData(placed)),
                (string)manifest["included"][0]["sha256"]);
        }

        [Fact]
        public void CollectorLaunchFailurePreservesSnapshotAndDoesNotBlockExit()
        {
            FocusTrace.StartConfigured(true, _root);
            FocusTrace.Record("fixture.keep_on_error");
            FocusTrace.Shutdown(_ => throw new IOException("fixture collector unavailable"));
            string snapshot = Directory.GetDirectories(Path.Combine(_root, "logs", "focus-diagnostic")).Single();
            Assert.Contains("fixture collector unavailable", File.ReadAllText(Path.Combine(snapshot, "collection-error.txt")));
            Assert.Contains("fixture.keep_on_error", File.ReadAllText(Path.Combine(snapshot, "focus-trace.log")));
            Assert.False(File.Exists(snapshot + ".zip"));
        }
    }
}
