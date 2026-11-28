using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading;
using CF7Launcher.Guardian;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class OwnedChildProcessJobTests
    {
        private static Process StartSleeper()
        {
            return Process.Start(new ProcessStartInfo
            {
                FileName = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),
                    @"WindowsPowerShell\v1.0\powershell.exe"),
                Arguments = "-NoProfile -NonInteractive -Command \"Start-Sleep -Seconds 60\"",
                UseShellExecute = false,
                CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Hidden
            });
        }

        private static void StopOwnedFixture(Process process)
        {
            if (process == null) return;
            try
            {
                if (!process.HasExited) process.Kill(entireProcessTree: true);
                process.WaitForExit(5000);
            }
            finally { process.Dispose(); }
        }

        [Fact]
        public void ClosingHostJobTerminatesItsChildrenAndPreservesAnUnrelatedProcess()
        {
            using var job = new OwnedChildProcessJob();
            Process first = null, second = null, unrelated = null;
            try
            {
                first = StartSleeper();
                second = StartSleeper();
                unrelated = StartSleeper();
                job.Assign(first);
                job.Assign(second);
                Assert.False(first.HasExited);
                Assert.False(second.HasExited);
                job.Dispose();
                Assert.True(first.WaitForExit(5000));
                Assert.True(second.WaitForExit(5000));
                Assert.False(unrelated.HasExited);
            }
            finally
            {
                StopOwnedFixture(first);
                StopOwnedFixture(second);
                StopOwnedFixture(unrelated);
            }
        }

        [Fact]
        public void DisposedJobRejectsAssignmentWithoutKillingAnUnownedProcess()
        {
            using var job = new OwnedChildProcessJob();
            Process unrelated = StartSleeper();
            try
            {
                job.Dispose();
                Assert.Throws<ObjectDisposedException>(() => job.Assign(unrelated));
                Assert.False(unrelated.HasExited);
            }
            finally { StopOwnedFixture(unrelated); }
        }

        [Fact]
        public void NonActivatingChildKeepsItsArgumentsDirectoryUnicodeEnvironmentAndJobOwnership()
        {
            DirectoryInfo directory = Directory.CreateTempSubdirectory("CF7 startup 验证 ");
            string script = Path.Combine(directory.FullName, "capture 启动.ps1");
            string receipt = Path.Combine(directory.FullName, "capture 结果.json");
            const string expectedArgument = "实机启动 复验.jpg";
            const string expectedEnvironment = "启动态：静默";
            using var job = new OwnedChildProcessJob();
            Process child = null;
            try
            {
                File.WriteAllText(script, """
                    param($Value, $Receipt)
                    $state = [ordered]@{
                        pid = $PID
                        argument = $Value
                        directory = [Environment]::CurrentDirectory
                        temporary = $env:TEMP
                        alternateTemp = $env:TMP
                        unicode = $env:CF7_STARTUP_TEST_TEXT
                    }
                    $staged = $Receipt + '.tmp'
                    [IO.File]::WriteAllText($staged, ($state | ConvertTo-Json -Compress), [Text.UTF8Encoding]::new($false))
                    [IO.File]::Move($staged, $Receipt)
                    Start-Sleep -Seconds 60
                    """, new UTF8Encoding(encoderShouldEmitUTF8Identifier: true));
                var start = new ProcessStartInfo
                {
                    FileName = Path.Combine(Environment.SystemDirectory, @"WindowsPowerShell\v1.0\powershell.exe"),
                    Arguments = $"-NoProfile -NonInteractive -File \"{script}\" \"{expectedArgument}\" \"{receipt}\"",
                    WorkingDirectory = directory.FullName,
                    UseShellExecute = false,
                    CreateNoWindow = true
                };
                start.Environment["TEMP"] = directory.FullName;
                start.Environment["TMP"] = directory.FullName;
                start.Environment["CF7_STARTUP_TEST_TEXT"] = expectedEnvironment;
                child = job.StartNonActivatingChild(start);

                Assert.True(SpinWait.SpinUntil(() => File.Exists(receipt), TimeSpan.FromSeconds(5)));
                JObject state = JObject.Parse(File.ReadAllText(receipt, Encoding.UTF8));
                Assert.Equal(child.Id, state.Value<int>("pid"));
                Assert.Equal(expectedArgument, state.Value<string>("argument"));
                Assert.Equal(directory.FullName, state.Value<string>("directory"));
                Assert.Equal(directory.FullName, state.Value<string>("temporary"));
                Assert.Equal(directory.FullName, state.Value<string>("alternateTemp"));
                Assert.Equal(expectedEnvironment, state.Value<string>("unicode"));
                Assert.False(child.HasExited);

                job.Dispose();
                Assert.True(child.WaitForExit(5000));
            }
            finally
            {
                StopOwnedFixture(child);
                File.Delete(script);
                File.Delete(receipt);
                File.Delete(receipt + ".tmp");
                Directory.Delete(directory.FullName);
            }
        }
    }
}
