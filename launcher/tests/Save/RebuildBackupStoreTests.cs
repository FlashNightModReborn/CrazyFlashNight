using System;
using System.IO;
using CF7Launcher.Save;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Save
{
    public sealed class RebuildBackupStoreTests : IDisposable
    {
        private readonly string _root;
        private readonly string _savesDir;
        private readonly RebuildBackupStore _store;

        public RebuildBackupStoreTests()
        {
            _root = Path.Combine(
                Path.GetTempPath(),
                "cf7-rebuild-backup-" + Guid.NewGuid().ToString("N"));
            _savesDir = Path.Combine(_root, "saves");
            Directory.CreateDirectory(_savesDir);
            _store = new RebuildBackupStore(_savesDir);
        }

        public void Dispose()
        {
            try { if (Directory.Exists(_root)) Directory.Delete(_root, true); }
            catch { }
        }

        [Fact]
        public void WriteLatest_RoundTripsVerifiedNormalizedSnapshot()
        {
            string path;
            string error;
            Assert.True(_store.TryWriteLatest(
                "slot_a",
                " 一周目 ",
                BuildSnapshot("角色甲", 7),
                "shadow",
                out path,
                out error), error);

            JObject document;
            Assert.True(_store.TryReadLatest("slot_a", out document, out error), error);
            Assert.Equal(1, document.Value<int>("v"));
            Assert.Equal("slot_a", document.Value<string>("slotKey"));
            Assert.Equal("一周目", document.Value<string>("displayName"));
            Assert.Equal("shadow", document.Value<string>("source"));
            Assert.NotEmpty(document.Value<string>("createdAt"));
            Assert.Matches("^[A-F0-9]{64}$", document.Value<string>("snapshotSha256"));
            Assert.Equal("角色甲", document["snapshot"]["0"][0].Value<string>());
            Assert.Equal(path, _store.GetBackupPath("slot_a"));
        }

        [Fact]
        public void WriteLatest_ReplacesPriorSnapshotAndKeepsOneFile()
        {
            string ignored;
            string error;
            Assert.True(_store.TryWriteLatest(
                "slot_a", "同名", BuildSnapshot("旧角色", 1), "shadow",
                out ignored, out error), error);
            Assert.True(_store.TryWriteLatest(
                "slot_a", "同名", BuildSnapshot("新角色", 9), "sol",
                out ignored, out error), error);

            JObject document;
            Assert.True(_store.TryReadLatest("slot_a", out document, out error), error);
            Assert.Equal("新角色", document["snapshot"]["0"][0].Value<string>());
            Assert.Equal("sol", document.Value<string>("source"));
            Assert.Single(Directory.GetFiles(
                Path.Combine(_savesDir, RebuildBackupStore.DirectoryName),
                "*.json"));
        }

        [Fact]
        public void ReadLatest_TamperedSnapshotFailsClosed()
        {
            string path;
            string error;
            Assert.True(_store.TryWriteLatest(
                "slot_a", "一周目", BuildSnapshot("角色甲", 7), "shadow",
                out path, out error), error);

            JObject tampered = JObject.Parse(File.ReadAllText(path));
            tampered["snapshot"]["0"][0] = "被篡改";
            File.WriteAllText(path, tampered.ToString());

            JObject document;
            Assert.False(_store.TryReadLatest("slot_a", out document, out error));
            Assert.Equal("backup_hash_mismatch", error);
            Assert.Null(document);
        }

        [Theory]
        [InlineData("../slot")]
        [InlineData("slot.name")]
        [InlineData("中文槽位")]
        public void WriteLatest_InvalidSlotNeverCreatesBackup(string slotKey)
        {
            string path;
            string error;
            Assert.False(_store.TryWriteLatest(
                slotKey, "一周目", BuildSnapshot("角色甲", 7), "shadow",
                out path, out error));
            Assert.Equal("invalid_slot_key", error);
            Assert.Null(path);
            Assert.False(Directory.Exists(
                Path.Combine(_savesDir, RebuildBackupStore.DirectoryName)));
        }

        internal static JObject BuildSnapshot(string characterName, int level)
        {
            JObject snapshot = new JObject();
            snapshot["version"] = "3.0";
            snapshot["lastSaved"] = "2026-08-29 12:00:00";
            snapshot["0"] = new JArray(
                characterName, "男", 1000, level, 500, 170, 5, "勇者",
                10000, 0, new JArray(), 0, new JArray(), "");

            JArray equipment = new JArray();
            for (int i = 0; i < 28; i++) equipment.Add(0);
            snapshot["1"] = equipment;
            snapshot["2"] = JValue.CreateNull();
            snapshot["3"] = 0;
            snapshot["4"] = new JArray(new JArray(), 0);
            snapshot["5"] = new JArray();
            snapshot["6"] = JValue.CreateNull();
            snapshot["7"] = new JArray(0, 0, 0, 0, 0);
            snapshot["inventory"] = new JObject
            {
                ["背包"] = new JArray(),
                ["装备栏"] = new JObject(),
                ["药剂栏"] = new JArray(),
                ["仓库"] = new JArray(),
                ["战备箱"] = new JArray()
            };
            snapshot["collection"] = new JObject
            {
                ["材料"] = new JObject(),
                ["情报"] = new JObject()
            };
            snapshot["infrastructure"] = new JObject();
            snapshot["tasks"] = new JObject
            {
                ["tasks_to_do"] = new JArray(),
                ["tasks_finished"] = new JObject(),
                ["task_chains_progress"] = new JObject()
            };
            snapshot["pets"] = new JObject
            {
                ["宠物信息"] = new JArray(
                    new JArray(), new JArray(), new JArray(), new JArray(), new JArray()),
                ["宠物领养限制"] = 5
            };
            snapshot["shop"] = new JObject
            {
                ["商城已购买物品"] = new JArray(),
                ["商城购物车"] = new JArray()
            };
            return snapshot;
        }
    }
}
