using System;
using System.IO;
using CF7Launcher.Save;
using Xunit;

namespace CF7Launcher.Tests.Save
{
    public class SolFileLocatorTests : IDisposable
    {
        private const string Slot = "crazyflasher7_saves2";
        private const string ResourcesSwf = @"E:\steam\steamapps\common\CRAZYFLASHER7StandAloneStarter\resources\CRAZYFLASHER7MercenaryEmpire.swf";
        private const string DevSwf = @"E:\steam\steamapps\common\CRAZYFLASHER7StandAloneStarter\CrazyFlashNight\CRAZYFLASHER7MercenaryEmpire.swf";

        private readonly string _shareRoot;

        public SolFileLocatorTests()
        {
            _shareRoot = Path.Combine(Path.GetTempPath(), "cf7-sol-locator-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(_shareRoot);
        }

        public void Dispose()
        {
            try
            {
                if (Directory.Exists(_shareRoot))
                    Directory.Delete(_shareRoot, true);
            }
            catch { }
        }

        [Fact]
        public void FindSolFile_PrefersCurrentRuntimeRoot()
        {
            string hashDir = CreateHashDir("HASH_B");
            string current = CreateDirectCandidate(hashDir, ResourcesSwf, false);
            CreateDirectCandidate(hashDir, DevSwf, false);

            SolFileLocator locator = new SolFileLocator(_shareRoot);

            Assert.Equal(current, locator.FindSolFile(Slot, ResourcesSwf));
        }

        [Fact]
        public void FindSolFile_FallsBackToExeParentWithinCurrentRoot()
        {
            string hashDir = CreateHashDir("HASH_A");
            string exeCandidate = CreateDirectCandidate(hashDir, Path.ChangeExtension(ResourcesSwf, ".exe"), false);

            SolFileLocator locator = new SolFileLocator(_shareRoot);

            Assert.Equal(exeCandidate, locator.FindSolFile(Slot, ResourcesSwf));
        }

        [Fact]
        public void FindSolFile_RootScopedFallback_DoesNotCrossRuntimeRoots()
        {
            string hashDir = CreateHashDir("HASH_A");
            string resourcesHit = CreateRootScopedCandidate(hashDir, ResourcesSwf, "nested");
            string devHit = CreateRootScopedCandidate(hashDir, DevSwf, "nested");

            SolFileLocator locator = new SolFileLocator(_shareRoot);

            Assert.Equal(resourcesHit, locator.FindSolFile(Slot, ResourcesSwf));

            File.Delete(resourcesHit);
            Assert.Null(locator.FindSolFile(Slot, ResourcesSwf));
            Assert.True(File.Exists(devHit));
        }

        [Fact]
        public void DeleteAllSolFiles_DeletesOnlyCurrentRuntimeRoot()
        {
            string hashDir = CreateHashDir("HASH_A");
            string resourcesSwfHit = CreateDirectCandidate(hashDir, ResourcesSwf, false);
            string resourcesExeHit = CreateDirectCandidate(hashDir, Path.ChangeExtension(ResourcesSwf, ".exe"), false);
            string devHit = CreateDirectCandidate(hashDir, DevSwf, false);

            SolFileLocator locator = new SolFileLocator(_shareRoot);

            int deleted = locator.DeleteAllSolFiles(Slot, ResourcesSwf);

            Assert.InRange(deleted, 2, 4);
            Assert.False(File.Exists(resourcesSwfHit));
            Assert.False(File.Exists(resourcesExeHit));
            Assert.True(File.Exists(devHit));
        }

        private string CreateHashDir(string name)
        {
            string path = Path.Combine(_shareRoot, name);
            Directory.CreateDirectory(path);
            return path;
        }

        private string CreateDirectCandidate(string hashDir, string ownerPath, bool includeDrive)
        {
            string path = Path.Combine(hashDir, BuildSubPath(ownerPath, includeDrive), Slot + ".sol");
            Directory.CreateDirectory(Path.GetDirectoryName(path));
            File.WriteAllText(path, "test");
            return path;
        }

        private string CreateRootScopedCandidate(string hashDir, string swfPath, string nestedDir)
        {
            string path = Path.Combine(
                hashDir,
                BuildSubPath(Path.GetDirectoryName(swfPath), false),
                nestedDir,
                Path.GetFileName(swfPath),
                Slot + ".sol");
            Directory.CreateDirectory(Path.GetDirectoryName(path));
            File.WriteAllText(path, "test");
            return path;
        }

        private static string BuildSubPath(string absolutePath, bool includeDrive)
        {
            string root = Path.GetPathRoot(absolutePath);
            string rest = absolutePath.Substring(root != null ? root.Length : 0);

            System.Collections.Generic.List<string> segments = new System.Collections.Generic.List<string>();
            segments.Add("localhost");
            if (includeDrive && !string.IsNullOrEmpty(root))
            {
                char drive = root[0];
                if (char.IsLetter(drive))
                    segments.Add(drive.ToString());
            }

            string[] parts = rest.Split('\\', '/');
            for (int i = 0; i < parts.Length; i++)
            {
                if (parts[i].Length > 0)
                    segments.Add(parts[i]);
            }

            return string.Join("/", segments.ToArray());
        }
    }
}
