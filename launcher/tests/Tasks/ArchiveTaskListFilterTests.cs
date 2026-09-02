// ArchiveTask.HandleList 槽位枚举正则过滤回归测试（INV-4）。
//
// 前修复期：Directory.GetFiles(_savesDir, "*.json") 字面匹配，会把
//   - .launcher-version-marker.json
//   - {slot}.broken-2026-04-29.json
// 等错当成槽位列出。修复：用正则 ^[^.][^.]*\.json$ 排除隐藏文件与含内部点的备份。

using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading;
using CF7Launcher.Guardian.Handlers;
using CF7Launcher.Tasks;
using CF7Launcher.Tests.Save;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Tasks
{
    public class ArchiveTaskListFilterTests : IDisposable
    {
        private readonly string _projectRoot;
        private readonly string _savesDir;
        private readonly ArchiveTask _archive;

        public ArchiveTaskListFilterTests()
        {
            _projectRoot = Path.Combine(Path.GetTempPath(), "cf7-archive-list-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(_projectRoot);
            _savesDir = Path.Combine(_projectRoot, "saves");
            Directory.CreateDirectory(_savesDir);
            _archive = new ArchiveTask(_projectRoot);
        }

        public void Dispose()
        {
            try { if (Directory.Exists(_projectRoot)) Directory.Delete(_projectRoot, true); }
            catch { }
        }

        [Fact]
        public void List_ExcludesHiddenAndBackupFiles()
        {
            // 合法槽位
            WriteJson("test1.json", "{\"version\":\"3.0\"}");
            WriteJson("test2.json", "{\"version\":\"3.0\"}");

            // 隐藏文件（version marker / 备份目录前缀）
            WriteJson(".launcher-version-marker.json", "{\"v\":1}");
            WriteJson(".hidden.json", "{}");

            // 修复备份遗留（按 INV-4 正常应在 .repair-backups/ 下，但根目录如果出现也要排除）
            WriteJson("test1.broken-2026-04-29.json", "{}");
            WriteJson("test1.repair-2026-04-29.json", "{}");

            JArray slots = ListSlots();
            var slotNames = slots.Select(t => t.Value<string>("slot")).OrderBy(s => s).ToList();

            Assert.Equal(2, slotNames.Count);
            Assert.Contains("test1", slotNames);
            Assert.Contains("test2", slotNames);
            Assert.DoesNotContain("", slotNames);
            Assert.DoesNotContain(".launcher-version-marker", slotNames);
            Assert.DoesNotContain(".hidden", slotNames);
            Assert.DoesNotContain("test1.broken-2026-04-29", slotNames);
            Assert.DoesNotContain("test1.repair-2026-04-29", slotNames);
        }

        [Fact]
        public void List_TombstoneFilter_ExcludesHiddenTombstones()
        {
            // 合法 tombstone
            WriteJson("zombie.tombstone", "{\"deletedAt\":\"x\"}");
            // 异常 hidden
            WriteJson(".weird.tombstone", "{\"deletedAt\":\"y\"}");

            JArray slots = ListSlots();
            var slotNames = slots.Select(t => t.Value<string>("slot")).ToList();

            Assert.Single(slotNames);
            Assert.Equal("zombie", slotNames[0]);
            Assert.True(slots[0].Value<bool>("tombstoned"));
        }

        [Fact]
        public void List_EmptySavesDir_ReturnsEmptySlots()
        {
            JArray slots = ListSlots();
            Assert.Empty(slots);
        }

        [Fact]
        public void List_RepairBackupSubdir_NotEnumerated()
        {
            // 真实修复备份所在的子目录，里面的文件根本不应被 list 看到
            string backupDir = Path.Combine(_savesDir, ".repair-backups", "test1");
            Directory.CreateDirectory(backupDir);
            File.WriteAllText(
                Path.Combine(backupDir, "2026-04-29T12-00-00.broken.json"),
                "{}",
                new UTF8Encoding(false));

            // 一个合法槽位
            WriteJson("test1.json", "{\"version\":\"3.0\"}");

            JArray slots = ListSlots();
            var slotNames = slots.Select(t => t.Value<string>("slot")).ToList();

            Assert.Single(slotNames);
            Assert.Equal("test1", slotNames[0]);
        }

        [Fact]
        public void List_ProjectsStableSlotKeyDisplayNameAndCharacterName()
        {
            JObject snapshot = RebuildBackupStoreTests.BuildSnapshot("角色甲", 7);
            WriteJson("slot_a.json", snapshot.ToString(Formatting.None));
            string normalized;
            string error;
            Assert.True(_archive.SlotCatalog.TrySetDisplayName(
                "slot_a", " 一周目 ", out normalized, out error), error);

            JObject slot = (JObject)Assert.Single(ListSlots());
            Assert.Equal("slot_a", slot.Value<string>("slotKey"));
            Assert.Equal("slot_a", slot.Value<string>("slot"));
            Assert.Equal("一周目", slot.Value<string>("displayName"));
            Assert.Equal("角色甲", slot.Value<string>("characterName"));
            Assert.Equal("角色甲 Lv.7", slot.Value<string>("mainProgress"));
        }

        [Fact]
        public void List_MalformedMetadataFallsBackWithoutBlocking()
        {
            JObject snapshot = RebuildBackupStoreTests.BuildSnapshot("角色乙", 3);
            WriteJson("slot_b.json", snapshot.ToString(Formatting.None));
            WriteJson(".slot-display-names.json", "{ malformed");

            JObject slot = (JObject)Assert.Single(ListSlots());
            Assert.Equal("slot_b", slot.Value<string>("slotKey"));
            Assert.Equal("角色乙", slot.Value<string>("displayName"));
            Assert.Equal("角色乙", slot.Value<string>("characterName"));
            Assert.False(_archive.SlotExistsSync("metadata_ghost"));
        }

        [Fact]
        public void List_CatalogOnlyIdentityRemainsVisibleAndPassesStartGate()
        {
            const string slotKey = "cf7_metadata_only";
            string normalized;
            string error;
            Assert.True(_archive.SlotCatalog.TrySetDisplayName(
                slotKey, "断线恢复槽位", out normalized, out error), error);
            Assert.False(File.Exists(Path.Combine(_savesDir, slotKey + ".json")));
            Assert.False(File.Exists(Path.Combine(_savesDir, slotKey + ".tombstone")));

            Assert.True(_archive.SlotExistsSync(slotKey));
            JObject slot = (JObject)Assert.Single(ListSlots());
            Assert.Equal(slotKey, slot.Value<string>("slotKey"));
            Assert.Equal(slotKey, slot.Value<string>("slot"));
            Assert.Equal("断线恢复槽位", slot.Value<string>("displayName"));
            Assert.Null(slot["characterName"].Value<string>());

            string discovered;
            Assert.True(BootstrapCommandHelpers.TryReadDiscoveredSlotKey(
                new JObject { ["slot"] = slotKey },
                "slot",
                _archive,
                out discovered,
                out error), error);
            Assert.Equal(slotKey, discovered);
        }

        [Fact]
        public void List_PreservesDiscoveredLegacyStemLongerThanNewKeyLimit()
        {
            string legacy = new string('c', 64) + "_legacy";
            JObject snapshot = RebuildBackupStoreTests.BuildSnapshot("旧角色", 5);
            WriteJson(legacy + ".json", snapshot.ToString(Formatting.None));

            JObject slot = (JObject)Assert.Single(ListSlots());
            Assert.Equal(legacy, slot.Value<string>("slotKey"));
            Assert.Equal(legacy, slot.Value<string>("slot"));
            Assert.Equal("旧角色", slot.Value<string>("displayName"));
        }

        [Fact]
        public void Delete_PreservesCatalogNameAndTombstoneForRebuildIdentity()
        {
            const string slotKey = "slot_deleted_identity";
            WriteJson(
                slotKey + ".json",
                RebuildBackupStoreTests.BuildSnapshot("待重建角色", 9)
                    .ToString(Formatting.None));
            string normalized;
            string error;
            Assert.True(_archive.SlotCatalog.TrySetDisplayName(
                slotKey,
                "待重建的一周目",
                out normalized,
                out error), error);

            JObject response = Send("delete", slotKey);

            Assert.True(response.Value<bool>("success"));
            Assert.True(response.Value<bool>("tombstoned"));
            Assert.False(File.Exists(Path.Combine(_savesDir, slotKey + ".json")));
            Assert.True(File.Exists(Path.Combine(_savesDir, slotKey + ".tombstone")));
            Assert.Equal(
                "待重建的一周目",
                _archive.SlotCatalog.ReadAll()[slotKey]);
            JObject listed = (JObject)Assert.Single(ListSlots());
            Assert.Equal(slotKey, listed.Value<string>("slotKey"));
            Assert.Equal("待重建的一周目", listed.Value<string>("displayName"));
            Assert.True(listed.Value<bool>("tombstoned"));
            Assert.True(_archive.SlotExistsSync(slotKey));
        }

        [Fact]
        public void Reset_RemovesPhysicalStateAndCatalogOnlyIdentity()
        {
            const string slotKey = "slot_full_reset";
            WriteJson(
                slotKey + ".json",
                RebuildBackupStoreTests.BuildSnapshot("彻底重置角色", 4)
                    .ToString(Formatting.None));
            WriteJson(slotKey + ".tombstone", "{\"deletedAt\":\"x\"}");
            string normalized;
            string error;
            Assert.True(_archive.SlotCatalog.TrySetDisplayName(
                slotKey,
                "不应留下幽灵",
                out normalized,
                out error), error);

            JObject response = Send("reset", slotKey);

            Assert.True(response.Value<bool>("success"));
            Assert.True(response.Value<bool>("reset"));
            Assert.False(File.Exists(Path.Combine(_savesDir, slotKey + ".json")));
            Assert.False(File.Exists(Path.Combine(_savesDir, slotKey + ".tombstone")));
            Assert.False(_archive.SlotCatalog.ReadAll().ContainsKey(slotKey));
            Assert.False(_archive.SlotExistsSync(slotKey));
            Assert.DoesNotContain(
                ListSlots(),
                item => item.Value<string>("slotKey") == slotKey);
        }

        [Fact]
        public void Reset_MalformedCatalogFailsBeforeDeletingPhysicalState()
        {
            const string slotKey = "slot_reset_catalog_error";
            WriteJson(
                slotKey + ".json",
                RebuildBackupStoreTests.BuildSnapshot("保留现场", 6)
                    .ToString(Formatting.None));
            WriteJson(slotKey + ".tombstone", "{\"deletedAt\":\"x\"}");
            WriteJson(".slot-display-names.json", "{ malformed");

            JObject response = Send("reset", slotKey);

            Assert.False(response.Value<bool>("success"));
            Assert.StartsWith(
                "slot_catalog_reset_failed:metadata_parse_failed:",
                response.Value<string>("error"));
            Assert.True(File.Exists(Path.Combine(_savesDir, slotKey + ".json")));
            Assert.True(File.Exists(Path.Combine(_savesDir, slotKey + ".tombstone")));
        }

        [Theory]
        [InlineData("load")]
        [InlineData("load_raw")]
        [InlineData("delete")]
        [InlineData("reset")]
        public void SlotMutationAndReadOps_InvalidKeyFailClosed(string op)
        {
            WriteJson("slot_bad.json", "{\"sentinel\":true}");

            JObject response = Send(op, "slot?bad");

            Assert.False(response.Value<bool>("success"));
            Assert.Equal("invalid_slot_key", response.Value<string>("error"));
            Assert.True(File.Exists(Path.Combine(_savesDir, "slot_bad.json")));
            Assert.False(File.Exists(Path.Combine(_savesDir, "slot_bad.tombstone")));
        }

        // ───────────── helpers ─────────────

        private void WriteJson(string fileName, string content)
        {
            File.WriteAllText(Path.Combine(_savesDir, fileName), content, new UTF8Encoding(false));
        }

        private JArray ListSlots()
        {
            return Send("list", null).Value<JArray>("slots");
        }

        private JObject Send(string op, string slot)
        {
            JObject msg = new JObject();
            JObject payload = new JObject();
            payload["op"] = op;
            if (slot != null) payload["slot"] = slot;
            msg["payload"] = payload;

            string responseJson = null;
            using (ManualResetEventSlim done = new ManualResetEventSlim(false))
            {
                _archive.HandleAsync(msg, delegate(string r) { responseJson = r; done.Set(); });
                Assert.True(done.Wait(TimeSpan.FromSeconds(5)), "Timed out waiting for list response");
            }

            JObject response = JObject.Parse(responseJson);
            if (op == "list") Assert.True(response.Value<bool>("success"));
            return response;
        }
    }
}
