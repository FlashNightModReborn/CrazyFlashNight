using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Linq;
using CF7Launcher.Fonts;
using Xunit;

namespace CF7Launcher.Tests.Fonts
{
    public sealed class RuntimeFontCatalogTests : IDisposable
    {
        private readonly List<string> _temporaryRoots = new List<string>();
        private readonly string _repositoryRoot;

        public RuntimeFontCatalogTests()
        {
            RuntimeFontCatalog.ResetForTest();
            _repositoryRoot = FindRepositoryRoot();
        }

        public void Dispose()
        {
            RuntimeFontCatalog.ResetForTest();
            foreach (string root in _temporaryRoots)
            {
                try { Directory.Delete(root, true); } catch { }
            }
        }

        [Fact]
        public void Configure_LoadsExactGateEProjectionAndSemanticRoles()
        {
            string root = CreateCatalogRoot();
            RuntimeFontCatalog.ConfigureForTest(root);

            Assert.True(RuntimeFontCatalog.IsReady, RuntimeFontCatalog.Failure);
            Assert.Equal(
                File.ReadAllText(Path.Combine(root, "launcher", "web", "generated", "font-catalog.json")),
                RuntimeFontCatalog.ProjectionJsonForTest);
            string[] roles = RuntimeFontCatalog.RoleIdsForTest;
            Assert.Equal(28, roles.Length);
            Assert.Contains("native.hud.body", roles);
            Assert.Contains("native.hud.mono", roles);
            Assert.Contains("native.hud.symbol", roles);
            Assert.Contains("native.combo.body", roles);
            Assert.Contains("native.combat.number", roles);
            Assert.Contains("web.intelligence.title", roles);
            Assert.Contains("web.overlay.mono", roles);
            Assert.True(RuntimeFontCatalog.IsAllowedDownloadHost("github.com"));
            Assert.True(RuntimeFontCatalog.IsAllowedDownloadHost("CDN.JSDELIVR.NET"));
            Assert.False(RuntimeFontCatalog.IsAllowedDownloadHost("evil.invalid"));
        }

        [Fact]
        public void ResolveFile_UsesCustomThenCacheThenPermanentAndRejectsBadMagicOrHash()
        {
            const string fileName = "jetbrains-mono.woff2";
            string source = Path.Combine(_repositoryRoot, "fonts", "permanent", "runtime", fileName);

            string customRoot = CreateCatalogRoot();
            Copy(source, customRoot, "fonts", "permanent", "runtime", fileName);
            Copy(source, customRoot, "fonts", "temporary", "cache", fileName);
            Copy(source, customRoot, "fonts", "temporary", "custom", fileName);
            RuntimeFontCatalog.ConfigureForTest(customRoot);
            Assert.Equal("temporary/custom", RuntimeFontCatalog.ResolveFile(fileName).Source);

            RuntimeFontCatalog.ResetForTest();
            string cacheRoot = CreateCatalogRoot();
            Copy(source, cacheRoot, "fonts", "permanent", "runtime", fileName);
            Copy(source, cacheRoot, "fonts", "temporary", "cache", fileName);
            Write(cacheRoot, new byte[] { 1, 2, 3, 4 }, "fonts", "temporary", "custom", fileName);
            RuntimeFontCatalog.ConfigureForTest(cacheRoot);
            Assert.Equal("temporary/cache", RuntimeFontCatalog.ResolveFile(fileName).Source);

            RuntimeFontCatalog.ResetForTest();
            string permanentRoot = CreateCatalogRoot();
            Copy(source, permanentRoot, "fonts", "permanent", "runtime", fileName);
            Write(permanentRoot, new byte[] { (byte)'w', (byte)'O', (byte)'F', (byte)'2', 0 },
                "fonts", "temporary", "cache", fileName);
            RuntimeFontCatalog.ConfigureForTest(permanentRoot);
            Assert.Equal("permanent/runtime", RuntimeFontCatalog.ResolveFile(fileName).Source);
        }

        [Fact]
        public void NativeFace_SelectionIsFrozenForProcessLifetimeAndStyleFallsBack()
        {
            const string fileName = "source-han-serif-cn-regular.otf";
            const string faceId = "source-han-serif-cn-regular-400";
            string source = Path.Combine(_repositoryRoot, "fonts", "permanent", "runtime", fileName);
            string root = CreateCatalogRoot();
            Copy(source, root, "fonts", "permanent", "runtime", fileName);
            RuntimeFontCatalog.ConfigureForTest(root);

            using (Font first = RuntimeFontCatalog.CreateFont(
                "native.hud.body", 14f, FontStyle.Bold, GraphicsUnit.Pixel))
            {
                Assert.NotNull(first);
                Assert.True(first.Size > 0f);
            }
            Assert.Equal("permanent/runtime", RuntimeFontCatalog.NativeSelectionForTest(faceId).Source);

            Copy(source, root, "fonts", "temporary", "custom", fileName);
            using (Font second = RuntimeFontCatalog.CreateFont(
                "native.hud.body", 14f, FontStyle.Bold, GraphicsUnit.Pixel))
            {
                Assert.NotNull(second);
            }
            Assert.Equal("permanent/runtime", RuntimeFontCatalog.NativeSelectionForTest(faceId).Source);

            RuntimeFontCatalog.ResetForTest();
            RuntimeFontCatalog.ConfigureForTest(root);
            using (Font afterRestart = RuntimeFontCatalog.CreateFont(
                "native.hud.body", 14f, FontStyle.Bold, GraphicsUnit.Pixel))
            {
                Assert.NotNull(afterRestart);
            }
            Assert.Equal("temporary/custom", RuntimeFontCatalog.NativeSelectionForTest(faceId).Source);
        }

        [Fact]
        public void Configure_FailsClosedWhenProjectionDoesNotMatchXml()
        {
            string root = CreateCatalogRoot();
            File.AppendAllText(Path.Combine(root, "fonts", "fonts.xml"), Environment.NewLine);
            RuntimeFontCatalog.ConfigureForTest(root);

            Assert.False(RuntimeFontCatalog.IsReady);
            Assert.Contains("sourceSha256", RuntimeFontCatalog.Failure);
            using (Font fallback = RuntimeFontCatalog.CreateFont(
                "native.hud.body", 12f, FontStyle.Regular, GraphicsUnit.Pixel))
            {
                Assert.NotNull(fallback);
            }
        }

        private string CreateCatalogRoot()
        {
            string root = Path.Combine(Path.GetTempPath(), "cf7-font-catalog-" + Guid.NewGuid().ToString("N"));
            _temporaryRoots.Add(root);
            Copy(Path.Combine(_repositoryRoot, "fonts", "fonts.xml"), root, "fonts", "fonts.xml");
            Copy(Path.Combine(_repositoryRoot, "launcher", "web", "generated", "font-catalog.json"),
                root, "launcher", "web", "generated", "font-catalog.json");
            return root;
        }

        private static void Copy(string source, string root, params string[] parts)
        {
            string destination = parts.Aggregate(root, Path.Combine);
            Directory.CreateDirectory(Path.GetDirectoryName(destination));
            File.Copy(source, destination, true);
        }

        private static void Write(string root, byte[] bytes, params string[] parts)
        {
            string destination = parts.Aggregate(root, Path.Combine);
            Directory.CreateDirectory(Path.GetDirectoryName(destination));
            File.WriteAllBytes(destination, bytes);
        }

        private static string FindRepositoryRoot()
        {
            DirectoryInfo current = new DirectoryInfo(AppContext.BaseDirectory);
            while (current != null)
            {
                if (File.Exists(Path.Combine(current.FullName, "fonts", "fonts.xml"))) return current.FullName;
                current = current.Parent;
            }
            throw new DirectoryNotFoundException("Unable to find repository root from " + AppContext.BaseDirectory);
        }
    }
}
