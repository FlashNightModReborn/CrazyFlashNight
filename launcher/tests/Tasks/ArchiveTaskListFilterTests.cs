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
using CF7Launcher.Save;
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
        public void List_ProjectsEquippedOutfitForBustWithoutInventoryOrTuningValues()
        {
            JObject snapshot = RebuildBackupStoreTests.BuildSnapshot("试装员", 12);
            snapshot["1"][0] = "男变装-基本脸型";
            snapshot["1"][1] = "发型-男式-Andy发型";
            snapshot["inventory"]["装备栏"] = new JObject
            {
                ["头部装备"] = new JObject { ["name"] = "钢盔", ["value"] = 11 },
                ["上装装备"] = new JObject { ["name"] = "剑圣胸甲", ["value"] = new JObject { ["level"] = 13 } },
                ["手部装备"] = new JObject { ["name"] = "剑圣手甲" },
                ["长枪"] = new JObject { ["name"] = "配枪" },
                ["手枪2"] = new JObject { ["name"] = "副手" },
                ["下装装备"] = new JObject { ["name"] = "工装裤" },
                ["脚部装备"] = new JObject { ["name"] = "棕色皮鞋" },
                ["其他"] = new JObject { ["name"] = "未穿戴" }
            };
            WriteJson("outfit.json", snapshot.ToString(Formatting.None));

            var look = (JObject)Assert.Single(ListSlots())["appearance"];
            var equipment = (JObject)look["equipment"];
            Assert.Equal("男变装-基本脸型", (string)look["face"]);
            Assert.Equal("发型-男式-Andy发型", (string)look["hair"]);
            Assert.Equal("钢盔", (string)equipment["head"]);
            Assert.Equal("剑圣手甲", (string)equipment["hand"]);
            Assert.Equal("配枪", (string)equipment["primary"]);
            Assert.Equal("副手", (string)equipment["secondary2"]);
            Assert.Equal("剑圣胸甲", (string)look["upper"]);
            Assert.Equal("工装裤", (string)look["lower"]);
            Assert.Equal("棕色皮鞋", (string)look["footwear"]);
            Assert.Equal(7, equipment.Count);
            Assert.All(equipment.Values(), token => Assert.Equal(JTokenType.String, token.Type));
        }

        [Fact]
        public void List_MixedCaseLegacyAliasUsesOnePhysicalRowBeforeAndAfterDelete()
        {
            const string key = "Patrol_A";
            WriteJson(key + ".json", RebuildBackupStoreTests.BuildSnapshot("巡逻员", 5).ToString(Formatting.None));
            WriteJson(".slot-display-names.json", "{\"v\":1,\"slots\":{\"PATROL_A\":{\"displayName\":\"夜巡\"}}}");
            var live = Assert.Single(ListSlots());
            Assert.Equal(key, (string)live["slot"]);
            Assert.Equal("夜巡", (string)live["displayName"]);
            Assert.True(_archive.SlotCatalog.TrySetDisplayName(key, "晚班", out _, out _));
            Assert.Single(_archive.SlotCatalog.ReadAll());
            Assert.True(Send("delete", key).Value<bool>("success"));
            var removed = Assert.Single(ListSlots());
            Assert.True((bool)removed["tombstoned"]);
            Assert.Equal(key, (string)removed["slot"]);
            Assert.Equal("晚班", (string)removed["displayName"]);
            Assert.True(Send("reset", "patrol_a").Value<bool>("success"));
            Assert.Empty(_archive.SlotCatalog.ReadAll());
            Assert.True((bool)Assert.Single(ListSlots())["tombstoned"]);
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
        public void Reset_RemovesCopyAndAliasButRetainsDeletionAuthority()
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
            Assert.True(File.Exists(Path.Combine(_savesDir, slotKey + ".tombstone")));
            Assert.False(_archive.SlotCatalog.ReadAll().ContainsKey(slotKey));
            Assert.True(_archive.SlotExistsSync(slotKey));
            Assert.True(Assert.Single(ListSlots()).Value<bool>("tombstoned"));
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

        [Fact]
        public void LockedShadow_CleanupFailsClosedAndRetriesWithoutChangingTheDisplayName()
        {
            const string key = "crazyflasher7_saves2";
            string contents = RebuildBackupStoreTests.BuildSnapshot("同名角色", 7).ToString(Formatting.None);
            WriteJson(key + ".json", contents);
            Assert.True(_archive.SlotCatalog.TrySetDisplayName(key, "保留档名", out _, out _));
            using (File.Open(Path.Combine(_savesDir, key + ".json"), FileMode.Open, FileAccess.Read, FileShare.Read))
            {
                var deletion = Send("delete", key);
                Assert.True(deletion.Value<bool>("success"));
                Assert.Equal("shadow_cleanup_pending", (string)deletion["warning"]);
                Assert.False(Send("reset", key).Value<bool>("success"));
                Assert.False(Send("reset", key, true).Value<bool>("success"));
                Assert.Throws<IOException>(() => _archive.ResetSlotSync(key));
                Assert.Equal("保留档名", _archive.SlotCatalog.ReadAll()[key]);
                Assert.False(Send("load", key).Value<bool>("success"));
                Assert.Equal(contents, (string)Send("load_raw", key)["data"]);
                Assert.True(Assert.Single(ListSlots()).Value<bool>("inconsistent"));
            }
            Assert.True(Send("reset", key, true).Value<bool>("success"));
            Assert.True(Send("reset", key, true).Value<bool>("success"));
            Assert.Equal("保留档名", _archive.SlotCatalog.ReadAll()[key]);
            Assert.True(new ArchiveTask(_projectRoot).IsTombstoned(key));
            Assert.False(File.Exists(Path.Combine(_savesDir, key + ".json")));
        }

        [Fact]
        public void ResidueCleanupRejectsLiveSlotAndLeavesItsBytesIntact()
        {
            const string key = "slot_reused";
            string contents = RebuildBackupStoreTests.BuildSnapshot("重建后的角色", 1).ToString(Formatting.None);
            WriteJson(key + ".json", contents);
            Assert.Equal("slot_not_deleted", (string)Send("reset", key, true)["error"]);
            Assert.False(_archive.IsTombstoned(key));
            Assert.Equal(contents, File.ReadAllText(Path.Combine(_savesDir, key + ".json")));
        }

        [Fact]
        public void CatalogDeleteRemovesBothFormatsAndAliasAndRejectsLateDataAfterRestart()
        {
            const string key = "one";
            var snapshot = RebuildBackupStoreTests.BuildSnapshot("巡逻队", 4);
            WriteJson(key + ".json", snapshot.ToString());
            Assert.True(_archive.SlotCatalog.TrySetDisplayName(key, "单独命名", out _, out _));
            string direct = MakeSol("HASH_A", "game", "main.swf", key);
            string alternate = MakeSol("HASH_B", "game", "main.exe", key);
            string neighbor = MakeSol("HASH_A", "other", "main.swf", key);
            string sibling = MakeSol("HASH_A", "game", "main.swf", "two");
            var storage = Catalog(_archive);

            var result = Send("delete", key, catalog:storage);
            Assert.True(result.Value<bool>("success"));
            Assert.Null(result["warning"]);
            Assert.False(File.Exists(direct));
            Assert.False(File.Exists(alternate));
            Assert.True(File.Exists(neighbor));
            Assert.True(File.Exists(sibling));
            Assert.False(File.Exists(Path.Combine(_savesDir, key + ".json")));
            Assert.DoesNotContain(key, _archive.SlotCatalog.ReadAll().Keys);

            var restarted = Catalog(new ArchiveTask(_projectRoot));
            var guard = Assert.Single((JArray)Send("list", null, catalog:restarted)["slots"]);
            Assert.True((bool)guard["tombstoned"]);
            Assert.False((bool)guard["cleanupPending"]);
            Assert.False((bool)guard["rebuildInProgress"]);
            Assert.False(restarted.Archive.TrySeedShadowSync(key, snapshot, out _, out _));
            MakeSol("HASH_A", "game", "main.swf", key);
            Assert.Equal(DecisionKind.Deleted, restarted.Resolver.Resolve(key, restarted.SwfPath).Kind);
        }

        [Theory]
        [InlineData(true)]
        [InlineData(false)]
        public void CatalogDeleteRecordsOccupiedFileAndExplicitCleanupSurvivesRestart(bool lockFlash)
        {
            const string key = "locked";
            string shadow = Path.Combine(_savesDir, key + ".json");
            WriteJson(key + ".json", RebuildBackupStoreTests.BuildSnapshot("守卫", 5).ToString());
            string sol = MakeSol("HASH_A", "game", "main.swf", key);
            var storage = Catalog(_archive);
            using (File.Open(lockFlash ? sol : shadow, FileMode.Open, FileAccess.Read, FileShare.Read))
            {
                var result = Send("delete", key, catalog:storage);
                Assert.Equal("slot_cleanup_pending", (string)result["warning"]);
                Assert.True(_archive.IsTombstoned(key));
                Assert.True((bool)Assert.Single((JArray)Send("list", null, catalog:storage)["slots"])["cleanupPending"]);
            }
            var restarted = Catalog(new ArchiveTask(_projectRoot));
            var cleared = Send("reset", key, true, restarted);
            Assert.True((bool)cleared["success"]);
            Assert.Null(cleared["warning"]);
            Assert.False(File.Exists(shadow));
            Assert.False(File.Exists(sol));
            Assert.False((bool)Assert.Single((JArray)Send("list", null, catalog:restarted)["slots"])["cleanupPending"]);
        }

        [Fact]
        public void LegacyDeletionProbeIsReadOnlyAndCleanupCannotEraseANewOrPendingCharacter()
        {
            const string key = "old";
            var storage = Catalog(_archive);
            string sol = MakeSol("HASH_A", "game", "main.swf", key);
            WriteJson(key + ".tombstone", "deleted");
            Assert.True((bool)Assert.Single((JArray)Send("list", null, catalog:storage)["slots"])["cleanupPending"]);
            Assert.True(File.Exists(sol));
            WriteJson(key + ".tombstone", new JObject { ["rebuildCallId"] = "same-attempt" }.ToString());
            Assert.Equal("rebuild_pending",(string)Send("reset", key, true, storage)["error"]);
            Assert.Equal("rebuild_pending",(string)Send("delete", key, catalog:storage)["error"]);
            Assert.True(File.Exists(sol));
            File.Delete(Path.Combine(_savesDir, key + ".tombstone"));
            WriteJson(key + ".json", RebuildBackupStoreTests.BuildSnapshot("新角色", 1).ToString());
            Assert.Equal("slot_not_deleted", (string)Send("reset", key, true, storage)["error"]);
            Assert.True(File.Exists(sol));
        }

        private SaveResolutionContext Catalog(ArchiveTask archive)
        {
            var locator = new SolFileLocator(Path.Combine(_projectRoot, "flash"));
            return new SaveResolutionContext(locator, new SolResolver(locator, archive, null), archive, @"Q:\game\main.swf");
        }

        private string MakeSol(string hash, string game, string projector, string key)
        {
            string dir = Path.Combine(_projectRoot, "flash", hash, "localhost", game, projector);
            Directory.CreateDirectory(dir);
            string path = Path.Combine(dir, key + ".sol");
            File.WriteAllText(path, "stand-in for a Flash copy");
            return path;
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

        private JObject Send(string op, string slot, bool residueOnly = false, SaveResolutionContext catalog = null)
        {
            JObject msg = new JObject();
            JObject payload = new JObject();
            payload["op"] = op;
            if (residueOnly) payload["residueOnly"] = true;
            if (slot != null) payload["slot"] = slot;
            msg["payload"] = payload;

            string responseJson = null;
            using (ManualResetEventSlim done = new ManualResetEventSlim(false))
            {
                (catalog?.Archive ?? _archive).HandleAsync(msg, delegate(string r) { responseJson = r; done.Set(); }, catalog);
                Assert.True(done.Wait(TimeSpan.FromSeconds(5)), "Timed out waiting for list response");
            }

            JObject response = JObject.Parse(responseJson);
            if (op == "list") Assert.True(response.Value<bool>("success"));
            return response;
        }
    }
}
