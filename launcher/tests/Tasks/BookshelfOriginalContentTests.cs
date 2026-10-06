using System;
using System.IO;
using System.Numerics;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.Config;
using CF7Launcher.Guardian;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Tasks
{
    public sealed class BookshelfOriginalContentTests
    {
        private const string Instance = "bookshelf.panel.1", Token = "bookshelf.test.1";
        private static JObject Prepare(int chapter = 2, string language = "cn", string call = "original.1") => new JObject {
            ["type"] = "panel", ["panel"] = "bookshelf", ["domain"] = "bookshelf-original", ["cmd"] = "prepare",
            ["callId"] = call, ["panelInstanceId"] = Instance,
            ["payload"] = new JObject { ["v"] = 1, ["token"] = Token, ["chapter"] = chapter, ["language"] = language } };
        private static JObject Release(string session, string call = "release.1") => new JObject {
            ["type"] = "panel", ["panel"] = "bookshelf", ["domain"] = "bookshelf-original", ["cmd"] = "release",
            ["callId"] = call, ["panelInstanceId"] = Instance, ["payload"] = new JObject { ["v"] = 1, ["session"] = session } };
        private static CollectionAccess Ready(ulong id = 1, bool dlc = false) => new CollectionAccess {
            SteamId = id, AccountNamespace = CollectionAccess.NamespaceFor(id), InstallDirectory = Path.GetTempPath(),
            PersonaName = "测试;player=\n", DlcInstalled = dlc };
        private static BookshelfOriginalContent Service(Func<CollectionAccess> access, Func<string, string, bool> admission = null,
            Func<string, string, int, string, byte[]> reader = null) => new BookshelfOriginalContent(Path.GetTempPath(),
                admission ?? ((instance, token) => instance == Instance && token == Token), access,
                reader ?? ((root, install, chapter, language) => new byte[8]));

        [Theory]
        [InlineData("not_owned")][InlineData("not_installed")][InlineData("sdk_unavailable")][InlineData("steam_unavailable")]
        public async Task MissingLicenseInstallOrSdkNeverReadsMovie(string error)
        {
            int reads = 0;
            using var content = Service(() => new CollectionAccess { Error = error }, reader: (_, _, _, _) => { reads++; return new byte[8]; });
            var result = await content.ExecuteAsync(Prepare());
            Assert.Equal(error, result.Value<string>("error")); Assert.Equal(0, reads); Assert.Null(result["playerUrl"]);
        }
        [Theory]
        [InlineData("v")][InlineData("chapter")]
        public async Task ArbitrarilyLargeIntegersAreRejectedWithoutConversionException(string field)
        {
            using var content = Service(() => Ready());
            var request = Prepare(); request["payload"][field] = new JValue(BigInteger.Pow(10, 100));
            Assert.Equal("invalid_payload", (await content.ExecuteAsync(request)).Value<string>("error"));
        }
        [Theory]
        [InlineData(0, "cn")][InlineData(7, "cn")][InlineData(1, "en")][InlineData(2, "../../en")]
        public async Task OnlyKnownChapterLanguagePairsAreAccepted(int chapter, string language)
        {
            using var content = Service(() => Ready());
            Assert.Equal("invalid_payload", (await content.ExecuteAsync(Prepare(chapter, language))).Value<string>("error"));
        }
        [Fact]
        public async Task ForeignOwnerTokenAndUncontractedFieldsAreRejected()
        {
            int reads = 0;
            using var content = Service(() => Ready(), reader: (_, _, _, _) => { reads++; return new byte[8]; });
            var foreign = Prepare(); foreign["payload"]["token"] = "bookshelf.other";
            Assert.Equal("context_unavailable", (await content.ExecuteAsync(foreign)).Value<string>("error"));
            var injected = Prepare(call:"original.2"); injected["payload"]["path"] = "C:/file.swf";
            Assert.Equal("invalid_payload", (await content.ExecuteAsync(injected)).Value<string>("error"));
            var business = Prepare(call:"original.3"); business["cmd"] = "commit";
            Assert.Equal("unsupported_cmd", (await content.ExecuteAsync(business)).Value<string>("error")); Assert.Equal(0, reads);
        }
        [Fact]
        public async Task ReopenRotatesLeaseWhileAccountChapterLanguageStorageLocationStaysStable()
        {
            using var content = Service(() => Ready());
            var first = await content.ExecuteAsync(Prepare(5));
            Assert.True(first.Value<bool>("success"));
            var firstUri = new Uri(first.Value<string>("playerUrl"));
            string session = first.Value<string>("session"), oldMovie = BookshelfOriginalContent.Origin + "/session/" + session + "/movie.swf";
            Assert.Equal(200, content.Resolve(oldMovie, "GET").Status);
            await content.ExecuteAsync(Release(session));
            Assert.Equal(404, content.Resolve(oldMovie, "GET").Status);
            var second = await content.ExecuteAsync(Prepare(5, call:"original.2"));
            var secondUri = new Uri(second.Value<string>("playerUrl"));
            Assert.Equal(firstUri.AbsolutePath, secondUri.AbsolutePath); Assert.NotEqual(firstUri.Fragment, secondUri.Fragment);
            Assert.Equal(404, content.Resolve(oldMovie, "GET").Status);
            await content.ExecuteAsync(Release(session, "release.2")); // old release cannot close the new movie
            string current = BookshelfOriginalContent.Origin + "/session/" + second.Value<string>("session") + "/movie.swf";
            Assert.Equal(200, content.Resolve(current, "GET").Status);
            Assert.False(content.IsPlayerNavigation("https://example.com/"));
            Assert.True(content.IsPlayerNavigation(secondUri.AbsoluteUri));
            foreach (var url in new[] { current + "?download=1", current + "#fragment", BookshelfOriginalContent.Origin + "/exes/SteamID.txt",
                BookshelfOriginalContent.Origin + "/ruffle/ruffle.js.map", BookshelfOriginalContent.Origin + "/../save.json",
                BookshelfOriginalContent.Origin + ":444/session/" + second.Value<string>("session") + "/movie.swf" })
                Assert.Equal(404, content.Resolve(url, "GET").Status);
            Assert.Equal(404, content.Resolve(current, "POST").Status);
            content.Revoke(); Assert.Equal(404, content.Resolve(current, "GET").Status);
        }
        [Fact]
        public async Task CurrentAccountOrLicenseLossRevokesContent()
        {
            var account = Ready();
            using var content = Service(() => account);
            var result = await content.ExecuteAsync(Prepare());
            string url = BookshelfOriginalContent.Origin + "/session/" + result.Value<string>("session") + "/movie.swf";
            account = Ready(2); Assert.Equal(404, content.Resolve(url, "GET").Status);
            account = Ready(); Assert.Equal(404, content.Resolve(url, "GET").Status);
            Assert.NotEqual(CollectionAccess.NamespaceFor(1), CollectionAccess.NamespaceFor(2));
        }
        [Fact]
        public async Task CloseDuringExtractionCannotCreateLateLease()
        {
            using var started = new ManualResetEventSlim(); using var finish = new ManualResetEventSlim();
            using var content = Service(() => Ready(), reader: (_, _, _, _) => { started.Set(); finish.Wait(3000); return new byte[8]; });
            var request = content.ExecuteAsync(Prepare()); Assert.True(started.Wait(3000)); content.Revoke(); finish.Set();
            var result = await request; Assert.Equal("panel_instance_expired", result.Value<string>("error")); Assert.Null(result["playerUrl"]);
        }
        [Fact]
        public async Task Cf1DoesNotRequireCollectionOrPretendToOwnIt()
        {
            int queries = 0;
            using var content = Service(() => { queries++; return new CollectionAccess { Error = "not_owned" }; });
            Assert.True((await content.ExecuteAsync(Prepare(1))).Value<bool>("success")); Assert.Equal(0, queries);
        }
        [Fact]
        public async Task DevelopmentMovieUsesIndependentStorageWithoutSteamIdentityOrDlc()
        {
            var account = new CollectionAccess { IsDevelopment = true, AccountNamespace = new string('d', 64),
                InstallDirectory = Path.GetTempPath() };
            using var content = Service(() => account);
            var first = await content.ExecuteAsync(Prepare(5));
            Assert.True(first.Value<bool>("success"));
            string session = first.Value<string>("session"), prefix = BookshelfOriginalContent.Origin + "/session/" + session + "/";
            Assert.Contains("/player/" + account.AccountNamespace + "/cf5-cn/", first.Value<string>("playerUrl"));
            Assert.Equal(200, content.Resolve(prefix + "movie.swf", "GET").Status);
            Assert.Equal(404, content.Resolve(prefix + "exes/SteamID.txt", "GET").Status);
            await content.ExecuteAsync(Release(session));
            var next = await content.ExecuteAsync(Prepare(5, call:"original.2"));
            Assert.Equal(new Uri(first.Value<string>("playerUrl")).AbsolutePath, new Uri(next.Value<string>("playerUrl")).AbsolutePath);
            string current = BookshelfOriginalContent.Origin + "/session/" + next.Value<string>("session") + "/movie.swf";
            account = new CollectionAccess { IsDevelopment = true, AccountNamespace = new string('e', 64),
                InstallDirectory = Path.GetTempPath() };
            Assert.Equal(404, content.Resolve(current, "GET").Status);
        }
        [Theory]
        [InlineData(false, "0")][InlineData(true, "1")]
        public void IdentityCompatibilityUsesAuthenticatedFieldsAndActualDlcState(bool installed, string expected)
        {
            byte[] bytes = BookshelfOriginalContent.IdentityBytes(Ready(123, installed));
            Assert.Equal(new byte[] { 0xff, 0xfe }, bytes[..2]);
            string text = Encoding.Unicode.GetString(bytes, 2, bytes.Length - 2);
            Assert.Equal("SteamID=123;steamName=测试 player  ;myDLC=" + expected, text);
        }
        [Fact]
        public void ProjectorFooterSelectsOnlyBoundedPayloadAndMalformedFootersFail()
        {
            var bytes = new byte[40]; bytes[0] = (byte)'M'; bytes[1] = (byte)'Z';
            for (int i = 0; i < 16; i++) bytes[16 + i] = (byte)i;
            BitConverter.GetBytes(0xfa123456u).CopyTo(bytes, 32); BitConverter.GetBytes(16u).CopyTo(bytes, 36);
            Assert.Equal(bytes[16..32], BookshelfOriginalContent.ReadProjector(new MemoryStream(bytes)));
            foreach (uint size in new[] { 0u, 7u, 32u, uint.MaxValue }) {
                BitConverter.GetBytes(size).CopyTo(bytes, 36);
                Assert.Throws<InvalidDataException>(() => BookshelfOriginalContent.ReadProjector(new MemoryStream(bytes)));
            }
            BitConverter.GetBytes(16u).CopyTo(bytes, 36); bytes[32] = 0;
            Assert.Throws<InvalidDataException>(() => BookshelfOriginalContent.ReadProjector(new MemoryStream(bytes)));
        }
        [Theory]
        [InlineData("https://overlay.local/overlay.html", true)]
        [InlineData("https://overlay.local.evil/overlay.html", false)]
        [InlineData("https://overlay.local:444/overlay.html", false)]
        [InlineData("https://cf7-originals.local/player.html", false)]
        [InlineData("https://overlay.local/modules/bookshelf/original/player.html", false)]
        public void OnlyTheOverlayDocumentCanRequestPreparation(string source, bool valid)
            => Assert.Equal(valid, BookshelfOriginalContent.IsOverlaySource(source));
        [Fact]
        public void PolicyDisallowsExternalNetworkFramesAndObjects()
        {
            var policy = BookshelfOriginalWebResources.ContentSecurityPolicy;
            Assert.Contains("connect-src 'self'", policy); Assert.Contains("frame-src 'none'", policy);
            Assert.Contains("object-src 'none'", policy); Assert.DoesNotContain("https:", policy.Split("frame-ancestors")[0]);
        }
    }
}
