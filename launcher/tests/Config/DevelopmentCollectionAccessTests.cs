using System;
using System.IO;
using CF7Launcher.Config;
using CF7Launcher.Tasks;
using Xunit;

namespace CF7Launcher.Tests.Config
{
    public sealed class DevelopmentCollectionAccessTests : IDisposable
    {
        private readonly string _temp = Path.Combine(Path.GetTempPath(), "cf7-original-dev-" + Guid.NewGuid().ToString("N"));
        private string Steam => Path.Combine(_temp, "Steam");
        private string Project => Path.Combine(Steam, "steamapps", "common", "CF7", "resources");
        private string Collection => Path.Combine(Steam, "steamapps", "common", "CrazyFlasherSeries");

        public DevelopmentCollectionAccessTests() => Directory.CreateDirectory(Project);
        public void Dispose() { if (Directory.Exists(_temp)) Directory.Delete(_temp, true); }
        private static void AddMovie(string install)
        {
            Directory.CreateDirectory(Path.Combine(install, "exes"));
            File.WriteAllText(Path.Combine(install, "exes", "crazyflasher5-cn_secure.exe"), "not a supported projector");
        }
        private void AddGitFixture()
        {
            // Exercise exactly the existing exemption's HEAD/pack predicate.
            Directory.CreateDirectory(Path.Combine(Project, ".git", "objects", "pack"));
            File.WriteAllText(Path.Combine(Project, ".git", "HEAD"), "ref: refs/heads/main\n");
            File.WriteAllBytes(Path.Combine(Project, ".git", "objects", "pack", "fixture.pack"), new byte[] { 1 });
        }

        [Fact]
        public void ExistingGitExemptionFindsSiblingCollectionWithoutCallingSteam()
        {
            AddGitFixture(); AddMovie(Collection);
            var read = SteamCollectionAccess.CreateReader(Project, () => throw new Exception("Must not initialize Steam"));
            var access = read();
            Assert.True(access.Ready); Assert.True(access.IsDevelopment);
            Assert.Equal(Path.GetFullPath(Collection), access.InstallDirectory);
            Assert.Equal(0UL, access.SteamId); Assert.False(access.DlcInstalled); Assert.Null(access.PersonaName);
            Assert.Throws<InvalidOperationException>(() => BookshelfOriginalContent.IdentityBytes(access));
            // Discovery does not bypass the existing payload integrity checks.
            Assert.Throws<InvalidDataException>(() => BookshelfOriginalContent.ReadMovie(Project, access.InstallDirectory, 5, "cn"));
        }

        [Theory]
        [InlineData(false)][InlineData(true)]
        public void OrdinaryInstallOrEmptyGitDirectoryStillRequiresSteam(bool emptyGit)
        {
            AddMovie(Collection);
            if (emptyGit) Directory.CreateDirectory(Path.Combine(Project, ".git"));
            int queries = 0;
            var read = SteamCollectionAccess.CreateReader(Project, () => { queries++; return new CollectionAccess { Error = "not_owned" }; });
            var access = read();
            Assert.Equal(1, queries); Assert.Equal("not_owned", access.Error);
            Assert.False(access.Ready); Assert.False(access.IsDevelopment); Assert.Null(access.InstallDirectory);
        }

        [Fact]
        public void SeparateSteamLibraryIsDiscoveredWithoutClientOrIdentityFiles()
        {
            string extra = Path.Combine(_temp, "另外的游戏库");
            string install = Path.Combine(extra, "steamapps", "common", "CrazyFlasherSeries");
            AddMovie(install);
            Directory.CreateDirectory(Path.Combine(Steam, "steamapps"));
            File.WriteAllText(Path.Combine(Steam, "steamapps", "libraryfolders.vdf"),
                "\"libraryfolders\" { \"1\" { \"path\" \"" + extra.Replace("\\", "\\\\") + "\" } }");
            var access = DevelopmentCollectionAccess.Read(Project, new[] { Steam });
            Assert.True(access.Ready); Assert.Equal(install, access.InstallDirectory);
            Assert.False(File.Exists(Path.Combine(install, "exes", "SteamID.txt")));
        }

        [Fact]
        public void MissingLocalMovieHasDevelopmentSpecificFailure()
        {
            Directory.CreateDirectory(Path.Combine(Collection, "exes"));
            var access = DevelopmentCollectionAccess.Read(Project, Array.Empty<string>());
            Assert.False(access.Ready); Assert.Equal("development_content_missing", access.Error);
        }

        [Fact]
        public void DevelopmentStorageIsStableAndSeparateFromOtherCheckoutsAndSteam()
        {
            AddMovie(Collection);
            var first = DevelopmentCollectionAccess.Read(Project, Array.Empty<string>());
            var again = DevelopmentCollectionAccess.Read(Project + Path.DirectorySeparatorChar, Array.Empty<string>());
            string other = Path.Combine(Steam, "steamapps", "common", "Other", "resources");
            Directory.CreateDirectory(other);
            var second = DevelopmentCollectionAccess.Read(other, Array.Empty<string>());
            Assert.Equal(first.AccountNamespace, again.AccountNamespace);
            Assert.NotEqual(first.AccountNamespace, second.AccountNamespace);
            Assert.NotEqual(first.AccountNamespace, CollectionAccess.NamespaceFor(1));
            Assert.Matches("^[0-9a-f]{64}$", first.AccountNamespace);
        }
    }
}
