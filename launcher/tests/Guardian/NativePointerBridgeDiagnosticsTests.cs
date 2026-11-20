using System;
using System.Collections.Concurrent;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Threading.Tasks;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.WorldCompositor;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public class NativePointerBridgeDiagnosticsTests
    {
        [Fact]
        public void StartupObservationRetainsExactSourceOwnerAndRootWithoutAnAdmissionVerdict()
        {
            string message=NativePointerBridge.FormatStartupObservation(new IntPtr(0x1234),new IntPtr(0x5678),
                new IntPtr(0x9ABC),42,43,44,45,ulong.MaxValue);
            Assert.Equal("event=world_pointer_bridge_start session=18446744073709551615 hostPid=45 source=0x1234 sourcePid=42 sourceTid=43 owner=0x5678 ownerPid=44 sourceRoot=0x9ABC observationOnly=1 phase=before_create",message);
        }

        [Fact]
        public void UnavailableWindowValuesAreNotPresentedAsAQualifiedIdentity()
        {
            string message=NativePointerBridge.FormatStartupObservation(IntPtr.Zero,IntPtr.Zero,IntPtr.Zero,0,0,0,45,1);
            Assert.Contains("source=0x0 sourcePid=0 sourceTid=0 owner=0x0 ownerPid=0 sourceRoot=0x0 observationOnly=1",message);
        }

        [Fact]
        public void CreateFailureRetainsWindowsErrorAndOriginalException()
        {
            var lines = new ConcurrentQueue<string>();
            LogManager.OnLogLine += lines.Enqueue;
            try {
                var start = new ProcessStartInfo(Path.Combine(Path.GetTempPath(), Guid.NewGuid() + ".exe"))
                    { UseShellExecute = false, CreateNoWindow = true };
                var error = Assert.Throws<Win32Exception>(() => NativePointerBridge.StartBroker(start, 23601));
                Assert.Equal(2, error.NativeErrorCode);
                string line = Assert.Single(lines, s => s.Contains("event=world_pointer_bridge_create_failed session=23601 "));
                Assert.Contains("elapsedMs=", line);
                Assert.Contains("win32=2", line);
                Assert.Contains($"exception={error.GetType().FullName} hresult=0x{error.HResult:X8}", line);
            } finally { LogManager.OnLogLine -= lines.Enqueue; }
        }

        [Fact]
        public async Task CreatedProcessAndReadyWaitHaveSeparateObservations()
        {
            var lines = new ConcurrentQueue<string>();
            LogManager.OnLogLine += lines.Enqueue;
            try {
                var start = new ProcessStartInfo(Path.Combine(Environment.SystemDirectory, "cmd.exe"), "/d /q /c echo READY fixture")
                    { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true };
                using var broker = NativePointerBridge.StartBroker(start, 23602);
                string ready = await NativePointerBridge.WaitForReady(broker.StandardOutput.ReadLineAsync(), broker, 23602, TimeSpan.FromSeconds(10));
                await broker.WaitForExitAsync();
                Assert.Equal("READY fixture", ready);
                foreach (string stage in new[] { "created", "ready_wait_complete" }) {
                    string line = Assert.Single(lines, s => s.Contains($"event=world_pointer_bridge_{stage} session=23602 "));
                    Assert.Contains($"brokerPid={broker.Id}", line);
                    Assert.Contains("elapsedMs=", line);
                }
            } finally { LogManager.OnLogLine -= lines.Enqueue; }
        }

        [Fact]
        public async Task RunningProcessWithoutOutputReportsReadyTimeout()
        {
            var lines = new ConcurrentQueue<string>();
            LogManager.OnLogLine += lines.Enqueue;
            try {
                var start = new ProcessStartInfo(Path.Combine(Environment.SystemDirectory, "cmd.exe"), "/d /q /c set /p value=")
                    { UseShellExecute = false, CreateNoWindow = true, RedirectStandardInput = true, RedirectStandardOutput = true };
                using var broker = NativePointerBridge.StartBroker(start, 23603);
                try {
                    await Assert.ThrowsAsync<TimeoutException>(() => NativePointerBridge.WaitForReady(
                        broker.StandardOutput.ReadLineAsync(), broker, 23603, TimeSpan.FromMilliseconds(75)));
                    string line = Assert.Single(lines, s => s.Contains("event=world_pointer_bridge_ready_timeout session=23603 "));
                    Assert.Contains($"brokerPid={broker.Id}", line);
                    Assert.Contains("elapsedMs=", line);
                    Assert.Contains("exception=System.TimeoutException", line);
                } finally {
                    broker.StandardInput.Close();
                    await broker.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(10));
                }
            } finally { LogManager.OnLogLine -= lines.Enqueue; }
        }

        [Theory]
        [InlineData(null,"unknown")]
        [InlineData(-1,"-1")]
        [InlineData(0,"0")]
        [InlineData(2,"2")]
        [InlineData(3,"3")]
        [InlineData(4,"4")]
        [InlineData(5,"5")]
        [InlineData(6,"6")]
        [InlineData(7,"7")]
        [InlineData(8,"8")]
        [InlineData(9,"9")]
        [InlineData(10,"10")]
        [InlineData(11,"11")]
        [InlineData(12,"12")]
        [InlineData(13,"13")]
        [InlineData(-1073741819,"-1073741819")]
        public void ExitObservationRetainsActualCodeWithoutInferringAWindowsErrorOrRootCause(int? code,string expected)
        {
            Assert.Equal("event=world_pointer_bridge_exit session=123 brokerPid=456 exitCode="+expected
                +" stdoutObserved=0 readyLineObserved=0",NativePointerBridge.FormatExitObservation(123,456,code,false,false));
        }

        [Theory]
        [InlineData(false,false,0,0)]
        [InlineData(true,false,1,0)]
        [InlineData(true,true,1,1)]
        public void StreamAndReadyObservationsRemainSeparate(bool stdout,bool ready,int stdoutValue,int readyValue)
        {
            Assert.Equal("event=world_pointer_bridge_exit session=123 brokerPid=456 exitCode=0 stdoutObserved="+stdoutValue
                +" readyLineObserved="+readyValue,NativePointerBridge.FormatExitObservation(123,456,0,stdout,ready));
        }
    }
}
