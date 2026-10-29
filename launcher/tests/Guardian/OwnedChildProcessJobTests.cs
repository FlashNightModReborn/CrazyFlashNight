using System;
using System.Diagnostics;
using System.IO;
using CF7Launcher.Guardian;
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
    }
}
