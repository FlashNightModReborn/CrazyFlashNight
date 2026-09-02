using System;
using System.IO;
using System.Linq;
using System.Text;
using CF7Launcher.Save;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Save
{
    public sealed class SaveSlotCatalogTests : IDisposable
    {
        private readonly string _root;
        private readonly string _saves;

        public SaveSlotCatalogTests()
        {
            _root = Path.Combine(
                Path.GetTempPath(),
                "cf7-slot-catalog-" + Guid.NewGuid().ToString("N"));
            _saves = Path.Combine(_root, "saves");
            Directory.CreateDirectory(_saves);
        }

        public void Dispose()
        {
            try { if (Directory.Exists(_root)) Directory.Delete(_root, true); }
            catch { }
        }

        [Theory]
        [InlineData("crazyflasher7_saves")]
        [InlineData("slot-1")]
        [InlineData("A_B")]
        [InlineData("12345678901234567890123456789012")]
        public void SlotKey_ExactValidValues_AreAccepted(string value)
        {
            string exact;
            Assert.True(SaveSlotKey.TryValidate(value, out exact));
            Assert.Equal(value, exact);
        }

        [Theory]
        [InlineData(null)]
        [InlineData("")]
        [InlineData("a/b")]
        [InlineData("a.b")]
        [InlineData("a?b")]
        [InlineData("a*b")]
        [InlineData("中文槽")]
        [InlineData("123456789012345678901234567890123")]
        public void SlotKey_NonExactValues_AreRejected(string value)
        {
            string exact;
            Assert.False(SaveSlotKey.TryValidate(value, out exact));
            Assert.Null(exact);
        }

        [Fact]
        public void NewSlotKey_HasFrozenShape()
        {
            string value = SaveSlotKey.CreateNew();
            Assert.Equal(32, value.Length);
            Assert.StartsWith("cf7_", value, StringComparison.Ordinal);
            Assert.True(SaveSlotKey.IsValid(value));
        }

        [Fact]
        public void ExistingSlotKey_PreservesLongAsciiStemWithoutSanitizing()
        {
            string legacy = new string('a', 96) + "_legacy-slot";
            string exact;

            Assert.False(SaveSlotKey.TryValidate(legacy, out exact));
            Assert.Null(exact);
            Assert.True(SaveSlotKey.TryValidateExisting(legacy, out exact));
            Assert.Equal(legacy, exact);
            Assert.False(SaveSlotKey.TryValidateExisting(
                new string('a', SaveSlotKey.ExistingMaxLength + 1),
                out exact));
            Assert.False(SaveSlotKey.TryValidateExisting("legacy.slot", out exact));
            Assert.False(SaveSlotKey.TryValidateExisting("legacy/slot", out exact));
        }

        [Fact]
        public void Catalog_CanLabelDiscoveredLegacyStemLongerThanNewKeyLimit()
        {
            string legacy = new string('b', 64);
            var catalog = new SaveSlotCatalog(_saves);
            string normalized;
            string error;

            Assert.True(catalog.TrySetDisplayName(
                legacy, "旧档", out normalized, out error), error);
            Assert.Equal("旧档", catalog.ReadAll()[legacy]);
        }

        [Fact]
        public void Catalog_AllowsDuplicateUnicodeDisplayNames_AndRenamesIndependently()
        {
            var catalog = new SaveSlotCatalog(_saves);
            string normalized;
            string error;

            Assert.True(catalog.TrySetDisplayName(
                "slot_a", "  我的存档  ", out normalized, out error), error);
            Assert.Equal("我的存档", normalized);
            Assert.True(catalog.TrySetDisplayName(
                "slot_b", "我的存档", out normalized, out error), error);

            var reloaded = new SaveSlotCatalog(_saves);
            var first = reloaded.ReadAll();
            Assert.Equal("我的存档", first["slot_a"]);
            Assert.Equal("我的存档", first["slot_b"]);

            Assert.True(reloaded.TrySetDisplayName(
                "slot_a", "第一周目", out normalized, out error), error);
            var second = reloaded.ReadAll();
            Assert.Equal("第一周目", second["slot_a"]);
            Assert.Equal("我的存档", second["slot_b"]);
        }

        [Fact]
        public void Catalog_MissingOrMalformedMetadata_FallsBackWithoutBlocking()
        {
            var catalog = new SaveSlotCatalog(_saves);
            Assert.Equal(
                "角色甲",
                catalog.ResolveDisplayName("slot_a", "角色甲"));

            File.WriteAllText(
                catalog.CatalogPath,
                "{bad-json",
                new UTF8Encoding(false));

            Assert.Empty(catalog.ReadAll());
            Assert.Equal(
                "角色甲",
                catalog.ResolveDisplayName("slot_a", "角色甲"));
            Assert.Equal(
                "slot_a",
                catalog.ResolveDisplayName("slot_a", "\u0001"));
        }

        [Fact]
        public void Catalog_RejectsControlAndTextElementOverflow()
        {
            string normalized;
            string error;
            Assert.False(SaveSlotCatalog.TryNormalizeDisplayName(
                "坏\u0001名字", out normalized, out error));
            Assert.Equal("display_name_control_character", error);

            string tooLong = string.Concat(Enumerable.Repeat("🙂", 33));
            Assert.False(SaveSlotCatalog.TryNormalizeDisplayName(
                tooLong, out normalized, out error));
            Assert.Equal("display_name_length", error);
        }

        [Fact]
        public void Catalog_CountsCombiningAndZwjSequencesAsUnicodeTextElements()
        {
            string normalized;
            string error;
            string boundary = string.Concat(
                Enumerable.Repeat("e\u0301", 31)) + "👩‍🚀";

            Assert.True(SaveSlotCatalog.TryNormalizeDisplayName(
                boundary, out normalized, out error), error);
            Assert.Equal(boundary, normalized);

            Assert.False(SaveSlotCatalog.TryNormalizeDisplayName(
                boundary + "x", out normalized, out error));
            Assert.Equal("display_name_length", error);
        }

        [Fact]
        public void Catalog_DoesNotOverwriteMalformedExistingIndex()
        {
            var catalog = new SaveSlotCatalog(_saves);
            File.WriteAllText(
                catalog.CatalogPath,
                "{bad-json",
                new UTF8Encoding(false));
            string before = File.ReadAllText(catalog.CatalogPath, Encoding.UTF8);

            string normalized;
            string error;
            Assert.False(catalog.TrySetDisplayName(
                "slot_a", "名称", out normalized, out error));
            Assert.StartsWith("metadata_parse_failed:", error, StringComparison.Ordinal);
            Assert.Equal(before, File.ReadAllText(catalog.CatalogPath, Encoding.UTF8));
        }

        [Fact]
        public void Catalog_RemoveOverride_RestoresCharacterNameFollower()
        {
            var catalog = new SaveSlotCatalog(_saves);
            string normalized;
            string error;
            Assert.True(catalog.TrySetDisplayName(
                "slot_a", "自定义名", out normalized, out error), error);

            Assert.True(catalog.TryRemoveDisplayName("slot_a", out error), error);
            Assert.False(catalog.ReadAll().ContainsKey("slot_a"));
            Assert.Equal("角色甲", catalog.ResolveDisplayName("slot_a", "角色甲"));
            Assert.True(catalog.TryRemoveDisplayName("slot_a", out error), error);

            File.WriteAllText(
                catalog.CatalogPath,
                "{bad-json",
                new UTF8Encoding(false));
            string before = File.ReadAllText(catalog.CatalogPath, Encoding.UTF8);
            Assert.False(catalog.TryRemoveDisplayName("slot_a", out error));
            Assert.StartsWith("metadata_parse_failed:", error, StringComparison.Ordinal);
            Assert.Equal(before, File.ReadAllText(catalog.CatalogPath, Encoding.UTF8));
        }
    }
}
