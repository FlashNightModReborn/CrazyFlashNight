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

        public void Dispose() => Directory.Delete(_root, true);
    }
}
