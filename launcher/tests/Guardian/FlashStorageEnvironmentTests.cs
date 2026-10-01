using System;
using System.Diagnostics;
using System.IO;
using CF7Launcher.Config;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class FlashStorageEnvironmentTests : IDisposable
    {
        private readonly string root = Path.Combine(Path.GetTempPath(), "cf7-flash-storage-" + Guid.NewGuid().ToString("N"));
        public FlashStorageEnvironmentTests() { Directory.CreateDirectory(root); }

        [Fact]
        public void ChildOverridesStaleParentBothVariablesWithoutMutatingHost()
        {
            string beforeTemp = Environment.GetEnvironmentVariable("TEMP");
            string beforeTmp = Environment.GetEnvironmentVariable("TMP");
            var start = new ProcessStartInfo("unused.exe") { UseShellExecute = false };
            start.Environment["TEMP"] = @"Z:\missing-old-steam-temp";
            start.Environment["TMP"] = @"Y:\different-temp";
            string actual = FlashStorageEnvironment.Prepare(start, root);
            Assert.Equal(actual, start.Environment["TEMP"]);
            Assert.Equal(actual, start.Environment["TMP"]);
            Assert.Equal(Path.GetPathRoot(root), Path.GetPathRoot(actual));
            Assert.Equal(beforeTemp, Environment.GetEnvironmentVariable("TEMP"));
            Assert.Equal(beforeTmp, Environment.GetEnvironmentVariable("TMP"));
            Assert.Empty(Directory.GetFiles(actual));
        }

        [Fact]
        public void DeniedDirectoryStopsBeforeChangingChildEnvironment()
        {
            File.WriteAllText(Path.Combine(root, "CF7FlashNight"), "blocked directory");
            var start = new ProcessStartInfo("unused.exe") { UseShellExecute = false };
            start.Environment["TEMP"] = "old-temp";
            Assert.Throws<IOException>(() => FlashStorageEnvironment.Prepare(start, root));
            Assert.Equal("old-temp", start.Environment["TEMP"]);
        }

        [Fact]
        public void UnicodeRoamingPathAndDiagnosticsUseActualStorageRoot()
        {
            string roaming = Path.Combine(root, "重定向存档目录");
            var start = new ProcessStartInfo("unused.exe") { UseShellExecute = false };
            string actual = FlashStorageEnvironment.Prepare(start, roaming);
            var snapshot = FlashStorageEnvironment.Snapshot(roaming);
            Assert.Equal(actual, snapshot.Value<string>("plannedFlashTemp"));
            Assert.Equal(Path.Combine(roaming, "Macromedia", "Flash Player", "#SharedObjects"),
                snapshot.Value<string>("sharedObjectsRoot"));
            Assert.NotNull(snapshot["storageAvailableBytes"]);
        }

        [Theory]
        [InlineData("")]
        [InlineData("relative-path")]
        public void InvalidRoamingPathDoesNotFallBackToWorkingDirectory(string path)
        {
            Assert.Throws<IOException>(() => FlashStorageEnvironment.Prepare(new ProcessStartInfo(), path));
        }

        public void Dispose()
        {
            string resolved = Path.GetFullPath(root);
            if (!resolved.StartsWith(Path.GetFullPath(Path.GetTempPath()), StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("fixture cleanup escaped temporary root");
            Directory.Delete(resolved, true);
        }
    }
}
