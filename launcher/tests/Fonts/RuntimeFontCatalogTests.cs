using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Security.Cryptography;
using CF7Launcher.Fonts;
using CF7Launcher.Tasks;
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
            Assert.Equal(Path.Combine(root, "fonts"), RuntimeFontCatalog.FontRoot);
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
            Assert.True(RuntimeFontCatalog.IsAllowedDownloadHost(
                "RELEASE-ASSETS.GITHUBUSERCONTENT.COM"));
            Assert.True(RuntimeFontCatalog.IsAllowedDownloadHost(
                "RAW.GITHUBUSERCONTENT.COM"));
            Assert.True(RuntimeFontCatalog.IsAllowedDownloadHost("CDN.JSDELIVR.NET"));
            Assert.False(RuntimeFontCatalog.IsAllowedDownloadHost(
                "evil.release-assets.githubusercontent.com"));
            Assert.False(RuntimeFontCatalog.IsAllowedDownloadHost("evil.invalid"));
        }

        [Fact]
        public void GitHubReleaseRedirect_AllowsExactProductionAssetHostAndRevalidatesEveryHop()
        {
            string root = CreateCatalogRoot();
            RuntimeFontCatalog.ConfigureForTest(root);
            const string release =
                "https://github.com/lxgw/LxgwWenKai-Screen/releases/download/v1.522/LXGWWenKaiScreen.ttf";
            const string productionAsset =
                "https://release-assets.githubusercontent.com/github-production-release-asset/211252834/5f7448d2-5cad-4a5d-90b4-5d230952a1c1?sp=r&sv=2018-11-09&sr=b&sig=fixture";
            string resolved;
            string error;

            Assert.True(FontPackTask.TryResolveRedirectForTest(
                release, productionAsset, out resolved, out error), error);
            Assert.Equal(productionAsset, resolved);

            Assert.False(FontPackTask.TryResolveRedirectForTest(
                resolved,
                "https://objects.githubusercontent.com/github-production-release-asset/211252834/next",
                out resolved,
                out error));
            Assert.Equal("host_not_allowed:objects.githubusercontent.com", error);

            Assert.False(FontPackTask.TryResolveRedirectForTest(
                release,
                "https://evil.release-assets.githubusercontent.com/github-production-release-asset/211252834/next",
                out resolved,
                out error));
            Assert.Equal("host_not_allowed:evil.release-assets.githubusercontent.com", error);

            Assert.False(FontPackTask.TryResolveRedirectForTest(
                release,
                "https://release-assets.githubusercontent.com:444/github-production-release-asset/211252834/next",
                out resolved,
                out error));
            Assert.Equal("url_port", error);

            Assert.True(FontPackTask.TryResolveRedirectForTest(
                release,
                "https://release-assets.githubusercontent.com:443/github-production-release-asset/211252834/next",
                out resolved,
                out error), error);
            Assert.True(new Uri(resolved).IsDefaultPort);
        }

        [Fact]
        public void GitHubRawRedirect_AllowsExactRawHostAndRejectsSiblingOrForeignNextHop()
        {
            string root = CreateCatalogRoot();
            RuntimeFontCatalog.ConfigureForTest(root);
            const string declared =
                "https://github.com/google/fonts/raw/main/ofl/kleeone/KleeOne-Regular.ttf";
            const string raw =
                "https://raw.githubusercontent.com/google/fonts/main/ofl/kleeone/KleeOne-Regular.ttf";
            string resolved;
            string error;

            Assert.True(FontPackTask.TryResolveRedirectForTest(
                declared, raw, out resolved, out error), error);
            Assert.Equal(raw, resolved);

            Assert.False(FontPackTask.TryResolveRedirectForTest(
                resolved,
                "https://media.githubusercontent.com/media/google/fonts/main/ofl/kleeone/KleeOne-Regular.ttf",
                out resolved,
                out error));
            Assert.Equal("host_not_allowed:media.githubusercontent.com", error);

            Assert.False(FontPackTask.TryResolveRedirectForTest(
                declared,
                "https://evil.raw.githubusercontent.com/google/fonts/main/ofl/kleeone/KleeOne-Regular.ttf",
                out resolved,
                out error));
            Assert.Equal("host_not_allowed:evil.raw.githubusercontent.com", error);
        }

        [Fact]
        public void ResolveFile_UsesCustomThenCacheThenPermanentAndRejectsUnparseableWoff2()
        {
            const string fileName = "jetbrains-mono.woff2";
            string source = Path.Combine(_repositoryRoot, "fonts", "permanent", "runtime", fileName);

            string customRoot = CreateCatalogRoot();
            Copy(source, customRoot, "fonts", "permanent", "runtime", fileName);
            Copy(source, customRoot, "fonts", "temporary", "cache", fileName);
            Copy(source, customRoot, "fonts", "temporary", "custom", fileName);
            RuntimeFontCatalog.ConfigureForTest(customRoot);
            Assert.Equal("temporary/cache", RuntimeFontCatalog.ResolveFile(fileName).Source);

            RuntimeFontCatalog.ResetForTest();
            string cacheRoot = CreateCatalogRoot();
            Copy(source, cacheRoot, "fonts", "permanent", "runtime", fileName);
            Copy(source, cacheRoot, "fonts", "temporary", "cache", fileName);
            Write(cacheRoot, StructurallyPlausibleWoff2Garbage(),
                "fonts", "temporary", "custom", fileName);
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
        public void WebResolution_ReusesOneVerifiedByteSnapshotAndHashBoundRevalidationHeaders()
        {
            const string fileName = "jetbrains-mono.woff2";
            string source = Path.Combine(_repositoryRoot, "fonts", "permanent", "runtime", fileName);
            byte[] expected = File.ReadAllBytes(source);
            string root = CreateCatalogRoot();
            Copy(source, root, "fonts", "permanent", "runtime", fileName);
            RuntimeFontCatalog.ConfigureForTest(root);

            RuntimeFontCatalog.ResolvedAsset selected = RuntimeFontCatalog.ResolveWebFileForTest(fileName);
            Assert.NotNull(selected);
            Assert.Equal(expected, selected.Bytes);
            Assert.Equal(Sha256(expected), selected.ContentSha256);
            Assert.Equal(1, RuntimeFontCatalog.ResolvedAssetCountForTest);

            File.WriteAllBytes(selected.Path, new byte[] { 0xde, 0xad, 0xbe, 0xef });
            Assert.Null(RuntimeFontCatalog.ResolveFile(fileName));
            RuntimeFontCatalog.ResolvedAsset repeated = RuntimeFontCatalog.ResolveWebFileForTest(fileName);
            Assert.Same(selected, repeated);
            Assert.Equal(expected, repeated.Bytes);
            Assert.Equal(1, RuntimeFontCatalog.ResolvedAssetCountForTest);

            string headers = RuntimeFontCatalog.WebResponseHeadersForTest(repeated);
            string entityTag = "\"sha256-" + Sha256(expected) + "\"";
            Assert.Contains("Cache-Control: private, max-age=0, must-revalidate", headers);
            Assert.Contains("ETag: " + entityTag, headers);
            Assert.DoesNotContain("Cache-Control: no-store", headers);
            Assert.True(RuntimeFontCatalog.MatchesIfNoneMatchForTest(entityTag, repeated));
            Assert.True(RuntimeFontCatalog.MatchesIfNoneMatchForTest("W/" + entityTag, repeated));
            Assert.True(RuntimeFontCatalog.MatchesIfNoneMatchForTest("\"other\", " + entityTag, repeated));
            Assert.False(RuntimeFontCatalog.MatchesIfNoneMatchForTest("\"other\"", repeated));
        }

        [Fact]
        public void WebResolution_DoesNotCacheMissesBeforeFontPackCompletes()
        {
            const string fileName = "jetbrains-mono.woff2";
            string source = Path.Combine(_repositoryRoot, "fonts", "permanent", "runtime", fileName);
            string root = CreateCatalogRoot();
            RuntimeFontCatalog.ConfigureForTest(root);

            Assert.Null(RuntimeFontCatalog.ResolveWebFileForTest(fileName));
            Assert.Equal(0, RuntimeFontCatalog.ResolvedAssetCountForTest);

            Copy(source, root, "fonts", "temporary", "cache", fileName);
            RuntimeFontCatalog.ResolvedAsset installed = RuntimeFontCatalog.ResolveWebFileForTest(fileName);
            Assert.NotNull(installed);
            Assert.Equal("temporary/cache", installed.Source);
            Assert.Equal(1, RuntimeFontCatalog.ResolvedAssetCountForTest);
        }

        [Theory]
        [InlineData("source-han-serif-cn-regular.otf", "fonts/permanent/runtime/source-han-serif-cn-regular.otf")]
        [InlineData("lxgw-wenkai-screen.ttf", "闪7重置版字体/必需替换字体/7px2bus Regular.ttf")]
        public void ResolveFile_ActualParserAcceptsValidCustomOtfAndTtf(
            string fileName, string sourceRelative)
        {
            string source = Path.Combine(
                _repositoryRoot, sourceRelative.Replace('/', Path.DirectorySeparatorChar));
            string root = CreateCatalogRoot();
            Copy(source, root, "fonts", "temporary", "custom", fileName);
            RuntimeFontCatalog.ConfigureForTest(root);

            RuntimeFontCatalog.ResolvedAsset selected = RuntimeFontCatalog.ResolveFile(fileName);
            Assert.NotNull(selected);
            Assert.Equal("temporary/custom", selected.Source);
        }

        [Fact]
        public void ActualParserAcceptsValidWoffAndPolicyRejectsValidCustomWoff2()
        {
            string sourceTtf = Path.Combine(
                _repositoryRoot, "闪7重置版字体", "必需替换字体", "7px2bus Regular.ttf");
            string directory = Path.Combine(Path.GetTempPath(), "cf7-font-probe-" + Guid.NewGuid().ToString("N"));
            _temporaryRoots.Add(directory);
            Directory.CreateDirectory(directory);
            string woff = Path.Combine(directory, "lxgw-wenkai-screen.woff");
            File.WriteAllBytes(woff, ConvertSfntToWoff(File.ReadAllBytes(sourceTtf)));

            Assert.True(RuntimeFontCatalog.HasValidFontStructureForTest(woff, "woff"));
            Assert.True(RuntimeFontCatalog.CanParseFontForTest(woff, "woff"));
            Assert.True(RuntimeFontCatalog.IsValidCustomFontForTest(woff, "woff"));
            Assert.False(RuntimeFontCatalog.IsValidCustomFontForTest(
                Path.Combine(_repositoryRoot, "fonts", "permanent", "runtime", "jetbrains-mono.woff2"),
                "woff2"));
        }

        [Fact]
        public void NativeFace_MalformedCustomWithMatchingMagicFallsBackToPermanent()
        {
            const string fileName = "source-han-serif-cn-regular.otf";
            const string faceId = "source-han-serif-cn-regular-400";
            string source = Path.Combine(_repositoryRoot, "fonts", "permanent", "runtime", fileName);
            string root = CreateCatalogRoot();
            Copy(source, root, "fonts", "permanent", "runtime", fileName);
            Write(root, StructurallyPlausibleOtfGarbage(),
                "fonts", "temporary", "custom", fileName);
            RuntimeFontCatalog.ConfigureForTest(root);

            using (Font selected = RuntimeFontCatalog.CreateFont(
                "native.hud.body", 14f, FontStyle.Regular, GraphicsUnit.Pixel))
            {
                Assert.NotNull(selected);
            }
            Assert.Equal("permanent/runtime", RuntimeFontCatalog.NativeSelectionForTest(faceId).Source);
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
        public void PackFormatValidation_UsesActualRuntimeParsersAndNamesWoff2StructureOnly()
        {
            byte[] ttf = File.ReadAllBytes(Path.Combine(
                _repositoryRoot, "闪7重置版字体", "必需替换字体", "7px2bus Regular.ttf"));
            byte[] otf = File.ReadAllBytes(Path.Combine(
                _repositoryRoot, "fonts", "permanent", "runtime", "source-han-serif-cn-regular.otf"));
            byte[] woff = ConvertSfntToWoff(ttf);
            byte[] woff2 = File.ReadAllBytes(Path.Combine(
                _repositoryRoot, "fonts", "permanent", "runtime", "jetbrains-mono.woff2"));

            string state;
            Assert.True(RuntimeFontCatalog.ValidatePackFormatForTest(ttf, "ttf", false, out state));
            Assert.Equal("runtime-parser-verified", state);
            Assert.True(RuntimeFontCatalog.ValidatePackFormatForTest(otf, "otf", true, out state));
            Assert.Equal("runtime-parser-native-verified", state);
            Assert.True(RuntimeFontCatalog.ValidatePackFormatForTest(woff, "woff", false, out state));
            Assert.Equal("runtime-parser-verified", state);
            Assert.False(RuntimeFontCatalog.ValidatePackFormatForTest(woff, "woff", true, out state));
            Assert.Equal("native-format-unsupported", state);
            Assert.True(RuntimeFontCatalog.ValidatePackFormatForTest(woff2, "woff2", false, out state));
            Assert.Equal("pinned-web-structure-only", state);
            Assert.False(RuntimeFontCatalog.ValidatePackFormatForTest(woff2, "woff2", true, out state));
            Assert.Equal("native-format-unsupported", state);
            Assert.False(RuntimeFontCatalog.ValidatePackFormatForTest(
                StructurallyPlausibleOtfGarbage(), "otf", false, out state));
            Assert.Equal("runtime-parser-rejected", state);
        }

        [Fact]
        public void FontPackVerification_ReusesCatalogBoundSameByteProbe()
        {
            string root = CreateCatalogRoot();
            RuntimeFontCatalog.ConfigureForTest(root);
            string directory = Path.Combine(
                Path.GetTempPath(), "cf7-font-pack-verify-" + Guid.NewGuid().ToString("N"));
            _temporaryRoots.Add(directory);
            Directory.CreateDirectory(directory);

            byte[] otf = File.ReadAllBytes(Path.Combine(
                _repositoryRoot, "fonts", "permanent", "runtime", "source-han-serif-cn-regular.otf"));
            string otfPath = Path.Combine(directory, "source-han-serif-cn-regular.otf");
            File.WriteAllBytes(otfPath, otf);
            string state;
            Assert.True(FontPackTask.VerifyDownloadedFileForTest(
                otfPath,
                "source-han-serif-cn-regular.otf",
                Sha256(otf),
                otf.LongLength,
                out state));
            Assert.Equal("runtime-parser-native-verified", state);

            byte[] woff2 = File.ReadAllBytes(Path.Combine(
                _repositoryRoot, "fonts", "permanent", "runtime", "jetbrains-mono.woff2"));
            string woff2Path = Path.Combine(directory, "jetbrains-mono.woff2");
            File.WriteAllBytes(woff2Path, woff2);
            Assert.True(FontPackTask.VerifyDownloadedFileForTest(
                woff2Path,
                "jetbrains-mono.woff2",
                Sha256(woff2),
                woff2.LongLength,
                out state));
            Assert.Equal("pinned-web-structure-only", state);

            byte[] impostor = StructurallyPlausibleOtfGarbage();
            File.WriteAllBytes(otfPath, impostor);
            Assert.False(FontPackTask.VerifyDownloadedFileForTest(
                otfPath,
                "source-han-serif-cn-regular.otf",
                Sha256(impostor),
                impostor.LongLength,
                out state));
            Assert.Equal("catalog-integrity-mismatch", state);
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

        private static byte[] StructurallyPlausibleWoff2Garbage()
        {
            // This satisfies RuntimeFontCatalog's bounded header/directory checks,
            // but the final four bytes are not a Brotli-compressed font stream.
            byte[] bytes = new byte[54];
            bytes[0] = (byte)'w';
            bytes[1] = (byte)'O';
            bytes[2] = (byte)'F';
            bytes[3] = (byte)'2';
            WriteUInt32BigEndian(bytes, 4, 0x00010000);
            WriteUInt32BigEndian(bytes, 8, (uint)bytes.Length);
            WriteUInt16BigEndian(bytes, 12, 1);
            WriteUInt32BigEndian(bytes, 16, 64);
            WriteUInt32BigEndian(bytes, 20, 4);
            bytes[48] = 0;
            bytes[49] = 1;
            bytes[50] = 0xde;
            bytes[51] = 0xad;
            bytes[52] = 0xbe;
            bytes[53] = 0xef;
            return bytes;
        }

        private static byte[] StructurallyPlausibleOtfGarbage()
        {
            // A one-table SFNT whose range is internally consistent but whose
            // fake head table cannot be decoded as an OpenType font.
            byte[] bytes = new byte[32];
            bytes[0] = (byte)'O';
            bytes[1] = (byte)'T';
            bytes[2] = (byte)'T';
            bytes[3] = (byte)'O';
            WriteUInt16BigEndian(bytes, 4, 1);
            bytes[12] = (byte)'h';
            bytes[13] = (byte)'e';
            bytes[14] = (byte)'a';
            bytes[15] = (byte)'d';
            WriteUInt32BigEndian(bytes, 20, 28);
            WriteUInt32BigEndian(bytes, 24, 4);
            bytes[28] = 0xde;
            bytes[29] = 0xad;
            bytes[30] = 0xbe;
            bytes[31] = 0xef;
            return bytes;
        }

        private static void WriteUInt16BigEndian(byte[] bytes, int offset, ushort value)
        {
            bytes[offset] = (byte)(value >> 8);
            bytes[offset + 1] = (byte)value;
        }

        private static void WriteUInt32BigEndian(byte[] bytes, int offset, uint value)
        {
            bytes[offset] = (byte)(value >> 24);
            bytes[offset + 1] = (byte)(value >> 16);
            bytes[offset + 2] = (byte)(value >> 8);
            bytes[offset + 3] = (byte)value;
        }

        private static byte[] ConvertSfntToWoff(byte[] sfnt)
        {
            ushort tableCount = ReadUInt16BigEndian(sfnt, 4);
            Assert.True(tableCount > 0);
            Assert.True(12 + (tableCount * 16) <= sfnt.Length);
            var tables = new List<(byte[] Tag, uint Checksum, byte[] Original, byte[] Stored)>();
            for (int index = 0; index < tableCount; index++)
            {
                int record = 12 + (index * 16);
                uint offset = ReadUInt32BigEndian(sfnt, record + 8);
                uint length = ReadUInt32BigEndian(sfnt, record + 12);
                Assert.True(offset <= sfnt.Length && length <= sfnt.Length - offset);
                byte[] original = new byte[(int)length];
                Buffer.BlockCopy(sfnt, (int)offset, original, 0, original.Length);
                byte[] compressed;
                using (var stream = new MemoryStream())
                {
                    using (var zlib = new ZLibStream(stream, CompressionLevel.SmallestSize, true))
                        zlib.Write(original, 0, original.Length);
                    compressed = stream.ToArray();
                }
                byte[] stored = compressed.Length < original.Length ? compressed : original;
                byte[] tag = new byte[4];
                Buffer.BlockCopy(sfnt, record, tag, 0, 4);
                tables.Add((tag, ReadUInt32BigEndian(sfnt, record + 4), original, stored));
            }

            int cursor = Align4(44 + (tableCount * 20));
            var offsets = new int[tables.Count];
            for (int index = 0; index < tables.Count; index++)
            {
                offsets[index] = cursor;
                cursor = Align4(cursor + tables[index].Stored.Length);
            }
            byte[] woff = new byte[cursor];
            woff[0] = (byte)'w';
            woff[1] = (byte)'O';
            woff[2] = (byte)'F';
            woff[3] = (byte)'F';
            WriteUInt32BigEndian(woff, 4, ReadUInt32BigEndian(sfnt, 0));
            WriteUInt32BigEndian(woff, 8, (uint)woff.Length);
            WriteUInt16BigEndian(woff, 12, tableCount);
            uint totalSfntSize = (uint)(12 + (tableCount * 16)
                + tables.Sum((table) => Align4(table.Original.Length)));
            WriteUInt32BigEndian(woff, 16, totalSfntSize);
            for (int index = 0; index < tables.Count; index++)
            {
                int record = 44 + (index * 20);
                Buffer.BlockCopy(tables[index].Tag, 0, woff, record, 4);
                WriteUInt32BigEndian(woff, record + 4, (uint)offsets[index]);
                WriteUInt32BigEndian(woff, record + 8, (uint)tables[index].Stored.Length);
                WriteUInt32BigEndian(woff, record + 12, (uint)tables[index].Original.Length);
                WriteUInt32BigEndian(woff, record + 16, tables[index].Checksum);
                Buffer.BlockCopy(
                    tables[index].Stored, 0, woff, offsets[index], tables[index].Stored.Length);
            }
            return woff;
        }

        private static ushort ReadUInt16BigEndian(byte[] bytes, int offset)
        {
            return (ushort)((bytes[offset] << 8) | bytes[offset + 1]);
        }

        private static uint ReadUInt32BigEndian(byte[] bytes, int offset)
        {
            return ((uint)bytes[offset] << 24)
                | ((uint)bytes[offset + 1] << 16)
                | ((uint)bytes[offset + 2] << 8)
                | bytes[offset + 3];
        }

        private static int Align4(int value)
        {
            return (value + 3) & ~3;
        }

        private static string Sha256(byte[] bytes)
        {
            using (SHA256 sha = SHA256.Create())
                return string.Concat(sha.ComputeHash(bytes).Select((value) => value.ToString("x2")));
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
