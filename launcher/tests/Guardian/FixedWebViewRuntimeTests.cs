using System;
using System.IO;
using System.Security.Cryptography;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class FixedWebViewRuntimeTests : IDisposable
    {
        private readonly string _root = Path.Combine(Path.GetTempPath(), "cf7-webview-test-" + Guid.NewGuid().ToString("N"));
        public FixedWebViewRuntimeTests() => Directory.CreateDirectory(_root);
        private FixedWebViewRuntime.Entry Write(string name, byte[] data)
        {
            string full = FixedWebViewRuntime.SafePath(_root, name);
            Directory.CreateDirectory(Path.GetDirectoryName(full));
            File.WriteAllBytes(full, data);
            return new FixedWebViewRuntime.Entry { Path = name, Size = data.Length, Sha256 = Convert.ToHexString(SHA256.HashData(data)) };
        }

        [Theory]
        [InlineData("../outside.dll")]
        [InlineData("/absolute.dll")]
        [InlineData("nested\\outside.dll")]
        [InlineData("file.dll:stream")]
        [InlineData("nested/./file")]
        [InlineData("nested//file")]
        [InlineData("nested/../file")]
        [InlineData("folder./file")]
        public void InventoryCannotEscapeOrAliasRoot(string name)
            => Assert.Throws<InvalidDataException>(() => FixedWebViewRuntime.SafePath(_root, name));

        [Fact]
        public void CompleteNestedInventory_IsAccepted()
        {
            var one = Write("msedgewebview2.exe", new byte[] { 1, 2 });
            var two = Write("locales/zh-CN.pak", new byte[] { 3, 4 });
            FixedWebViewRuntime.VerifyTree(_root, new[] { one, two });
        }

        [Fact]
        public void TamperedSameLengthFile_IsRejected()
        {
            var entry = Write("engine.dll", new byte[] { 1, 2 });
            File.WriteAllBytes(Path.Combine(_root, entry.Path), new byte[] { 2, 1 });
            Assert.Throws<InvalidDataException>(() => FixedWebViewRuntime.VerifyTree(_root, new[] { entry }));
        }

        [Fact]
        public void UnexpectedAndMissingFiles_AreRejected()
        {
            var entry = Write("engine.dll", new byte[] { 1 });
            Write("injected.dll", new byte[] { 2 });
            Assert.Throws<InvalidDataException>(() => FixedWebViewRuntime.VerifyTree(_root, new[] { entry }));
            File.Delete(Path.Combine(_root, "injected.dll"));
            File.Delete(Path.Combine(_root, entry.Path));
            Assert.Throws<InvalidDataException>(() => FixedWebViewRuntime.VerifyTree(_root, new[] { entry }));
        }

        [Fact]
        public void PhysicalPath_ResolvesLogicalAndActualFileToSameIdentity()
        {
            var entry = Write("engine.dll", new byte[] { 1 });
            string logical = Path.Combine(_root, entry.Path);
            string physical = FixedWebViewRuntime.ResolvePhysicalPath(logical);
            Assert.Equal(physical, FixedWebViewRuntime.ResolvePhysicalPath(physical));
            string other = Path.Combine(_root, "different.dll");
            File.WriteAllBytes(other, new byte[] { 1 });
            Assert.NotEqual(physical, FixedWebViewRuntime.ResolvePhysicalPath(other));
        }

        [Fact]
        public void DuplicateCaseInsensitivePaths_AreRejected()
        {
            var entry = Write("engine.dll", new byte[] { 1 });
            var duplicate = new FixedWebViewRuntime.Entry { Path = "ENGINE.dll", Size = entry.Size, Sha256 = entry.Sha256 };
            Assert.Throws<InvalidDataException>(() => FixedWebViewRuntime.VerifyTree(_root, new[] { entry, duplicate }));
        }

        [Fact]
        public void BufferedHash_RejectsTamperingBeyondFirstReadBuffer()
        {
            byte[] bytes = new byte[700000];
            new Random(17).NextBytes(bytes);
            var entry = Write("engine.dll", bytes);
            FixedWebViewRuntime.VerifyFile(Path.Combine(_root, entry.Path), entry.Size, entry.Sha256);
            bytes[600000] ^= 1;
            File.WriteAllBytes(Path.Combine(_root, entry.Path), bytes);
            Assert.Throws<InvalidDataException>(() => FixedWebViewRuntime.VerifyFile(
                Path.Combine(_root, entry.Path), entry.Size, entry.Sha256));
        }

        [Fact]
        public void VerifiedBundle_ReusesUnusedChunksOnlyForFullyVerifiedCache()
        {
            var specification = CachedSpecification();
            string payload = Path.Combine(_root, "payload");
            string cache = Path.Combine(_root, "cache");
            Directory.CreateDirectory(payload);
            string engine = FixedWebViewRuntime.SafePath(cache,
                specification.Version + "-" + specification.CabSha256 + "/engine");
            Directory.CreateDirectory(engine);
            File.WriteAllBytes(Path.Combine(engine, "engine.dll"), new byte[] { 1, 2 });
            Assert.Equal(engine, FixedWebViewRuntime.Prepare(payload, cache, specification, runtimeBundleVerified: true));
            Assert.Throws<InvalidDataException>(() => FixedWebViewRuntime.Prepare(payload, cache, specification));
        }

        [Fact]
        public void VerifiedBundle_CorruptCacheStillRequiresFreshSourceVerification()
        {
            var specification = CachedSpecification();
            string payload = Path.Combine(_root, "payload");
            string cache = Path.Combine(_root, "cache");
            Directory.CreateDirectory(payload);
            string engine = FixedWebViewRuntime.SafePath(cache,
                specification.Version + "-" + specification.CabSha256 + "/engine");
            Directory.CreateDirectory(engine);
            File.WriteAllBytes(Path.Combine(engine, "engine.dll"), new byte[] { 2, 1 });
            Assert.Throws<InvalidDataException>(() => FixedWebViewRuntime.Prepare(
                payload, cache, specification, runtimeBundleVerified: true));
            Assert.Single(Directory.GetDirectories(cache, "*.invalid-*"));
        }

        private static FixedWebViewRuntime.RuntimeLock CachedSpecification() => new()
        {
            Version = "1.0.0.0",
            CabSha256 = new string('A', 64),
            Parts = new[] { new FixedWebViewRuntime.Entry { Path = "runtime.cabpart", Size = 1, Sha256 = new string('B', 64) } },
            Files = new[] { new FixedWebViewRuntime.Entry { Path = "engine.dll", Size = 2,
                Sha256 = Convert.ToHexString(SHA256.HashData(new byte[] { 1, 2 })) } }
        };

        [Fact]
        public void BundleAdmission_RequiresExactCompleteChunkBindings()
        {
            var specification = CachedSpecification();
            string row = "file\truntime/webview2/runtime.cabpart\t1\t" + new string('B', 64);
            Assert.True(FixedWebViewRuntime.ManifestCoversPayload(new[] { row }, specification));
            Assert.False(FixedWebViewRuntime.ManifestCoversPayload(Array.Empty<string>(), specification));
            Assert.False(FixedWebViewRuntime.ManifestCoversPayload(new[] { row, row }, specification));
            Assert.False(FixedWebViewRuntime.ManifestCoversPayload(new[] { row.Replace("\t1\t", "\t2\t") }, specification));
            Assert.False(FixedWebViewRuntime.ManifestCoversPayload(new[] { row.Replace(new string('B', 64), new string('C', 64)) }, specification));
        }

        public void Dispose() => Directory.Delete(_root, true);
    }
}
