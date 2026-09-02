using System;
using System.IO;
using CF7Launcher.Guardian.Handlers;
using CF7Launcher.Tasks;
using CF7Launcher.Tests.Save;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian.Handlers
{
    public sealed class ArchiveCommandHandlerRenameTests : IDisposable
    {
        private readonly string _root;
        private readonly ArchiveTask _archive;

        public ArchiveCommandHandlerRenameTests()
        {
            _root = Path.Combine(
                Path.GetTempPath(),
                "cf7-slot-rename-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(_root);
            _archive = new ArchiveTask(_root);
        }

        public void Dispose()
        {
            try { if (Directory.Exists(_root)) Directory.Delete(_root, true); }
            catch { }
        }

        [Fact]
        public void RenameSlot_WritesOnlyAtomicDisplayMetadataAndReturnsNormalizedName()
        {
            const string slotKey = "slot_rename";
            string shadowPath;
            string error;
            Assert.True(_archive.TrySeedShadowSync(
                slotKey,
                RebuildBackupStoreTests.BuildSnapshot("角色甲", 4),
                out shadowPath,
                out error), error);
            string shadowBefore = File.ReadAllText(shadowPath);

            JObject response = ArchiveCommandHandler.BuildRenameResponse(
                new JObject
                {
                    ["slotKey"] = slotKey,
                    ["displayName"] = "  同名槽位  "
                },
                _archive);

            Assert.True(response.Value<bool>("ok"));
            Assert.Equal("rename_slot_resp", response.Value<string>("cmd"));
            Assert.Equal(slotKey, response.Value<string>("slotKey"));
            Assert.Equal("同名槽位", response.Value<string>("displayName"));
            Assert.Equal("同名槽位", _archive.SlotCatalog.ReadAll()[slotKey]);
            Assert.Equal(shadowBefore, File.ReadAllText(shadowPath));
        }

        [Fact]
        public void RenameSlot_RequiresAnExactDiscoveredSlot()
        {
            JObject invalid = ArchiveCommandHandler.BuildRenameResponse(
                new JObject
                {
                    ["slotKey"] = "slot?collision",
                    ["displayName"] = "名称"
                },
                _archive);
            Assert.False(invalid.Value<bool>("ok"));
            Assert.Equal("invalid_slot_key", invalid.Value<string>("error"));

            JObject missing = ArchiveCommandHandler.BuildRenameResponse(
                new JObject
                {
                    ["slotKey"] = "slot_missing",
                    ["displayName"] = "名称"
                },
                _archive);
            Assert.False(missing.Value<bool>("ok"));
            Assert.Equal("slot_not_found", missing.Value<string>("error"));
            Assert.Empty(_archive.SlotCatalog.ReadAll());
            Assert.False(_archive.SlotExistsSync("slot_missing"));
        }

        [Fact]
        public void RenameSlot_ExplicitBlankRestoresCharacterNameFollower()
        {
            const string slotKey = "slot_follow";
            string shadowPath;
            string error;
            Assert.True(_archive.TrySeedShadowSync(
                slotKey,
                RebuildBackupStoreTests.BuildSnapshot("角色甲", 4),
                out shadowPath,
                out error), error);
            string normalized;
            Assert.True(_archive.SlotCatalog.TrySetDisplayName(
                slotKey,
                "旧自定义名",
                out normalized,
                out error), error);

            JObject response = ArchiveCommandHandler.BuildRenameResponse(
                new JObject
                {
                    ["slotKey"] = slotKey,
                    ["displayName"] = "   "
                },
                _archive);

            Assert.True(response.Value<bool>("ok"));
            Assert.True(response.Value<bool>("followsCharacterName"));
            Assert.Equal(JTokenType.Null, response["displayName"].Type);
            Assert.False(_archive.SlotCatalog.ReadAll().ContainsKey(slotKey));
            Assert.Equal(
                "角色甲",
                _archive.SlotCatalog.ResolveDisplayName(slotKey, "角色甲"));
        }
    }
}
