// SaveAutoRepairService 端到端集成测试：
//   - 干净 saves → 无写入 / 无备份
//   - 脏 saves → 写备份 + audit log + 修复 + bump lastSaved
//   - 全过程不抛
//
// fffd 字符级修复细节在 RepairPolicyTests + tools/cf7-save-repair vitest 已覆盖；
// 本测试聚焦 service 行为：枚举过滤 / 备份目录 / lastSaved bump / 字段级修复结果.

using System;
using System.IO;
using System.Text;
using CF7Launcher.Save;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Save
{
    public class SaveAutoRepairServiceTests : IDisposable
    {
        private readonly string _projectRoot;
        private readonly string _savesDir;
        private readonly ArchiveTask _archive;

        public SaveAutoRepairServiceTests()
        {
            _projectRoot = Path.Combine(Path.GetTempPath(), "cf7-auto-repair-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(_projectRoot);
            _savesDir = Path.Combine(_projectRoot, "saves");
            Directory.CreateDirectory(_savesDir);

            string dataDir = Path.Combine(_projectRoot, "launcher", "data");
            Directory.CreateDirectory(dataDir);
            File.WriteAllText(Path.Combine(dataDir, "save_repair_dict.json"),
                @"{
                    ""schemaVersion"": 1,
                    ""generated"": { ""at"": ""2026-04-30T00:00:00Z"" },
                    ""items"": [""黑色功夫装""],
                    ""mods"": [""攻击+5""],
                    ""enemies"": [""黑铁会大叔""],
                    ""hairstyles"": [],
                    ""skills"": [""基础攻击""],
                    ""taskChains"": [],
                    ""stages"": []
                }",
                new UTF8Encoding(false));

            _archive = new ArchiveTask(_projectRoot);
        }

        public void Dispose()
        {
            try { if (Directory.Exists(_projectRoot)) Directory.Delete(_projectRoot, true); }
            catch { }
        }

        private string WriteSlot(string slot, string content)
        {
            string p = Path.Combine(_savesDir, slot + ".json");
            File.WriteAllText(p, content, new UTF8Encoding(false));
            return p;
        }

        // ─────────────── tests ───────────────

        [Fact]
        public void RunAll_NoSlots_ReturnsEmpty()
        {
            var results = SaveAutoRepairService.RunAll(_projectRoot, _archive);
            Assert.Empty(results);
        }

        [Fact]
        public void RunAll_CleanSlot_NoBackup()
        {
            string equipName = "黑色功夫装"; // "黑色功夫装"
            string skillName = "基础攻击";       // "基础攻击"
            WriteSlot("alice", BuildSnapshotJson(equipName, skillName));

            var results = SaveAutoRepairService.RunAll(_projectRoot, _archive);
            Assert.Single(results);
            Assert.Equal(0, results[0].FffdCount);
            Assert.Null(results[0].BackupPath);
        }

        [Fact]
        public void RunAll_DirtySlot_BackupAndApplyAndBump()
        {
            string slot = "bob";
            // "黑色�夫装" / "基础�击" — 用 \u 转义构造，避免任何编码歧义
            string brokenEquip = "黑色�夫装";
            string brokenSkill = "基础�击";
            string filePath = WriteSlot(slot, BuildSnapshotJson(brokenEquip, brokenSkill));

            var results = SaveAutoRepairService.RunAll(_projectRoot, _archive);
            Assert.Single(results);
            var r = results[0];
            Assert.Equal(2, r.FffdCount);
            Assert.Equal(2, r.Applied);
            Assert.NotNull(r.BackupPath);
            Assert.True(File.Exists(r.BackupPath));
            Assert.NotNull(r.BumpedLastSaved);

            // 字段级验证：修复后的字段值精确匹配 dict 候选
            string after = File.ReadAllText(filePath, Encoding.UTF8);
            JObject snap = JObject.Parse(after);
            Assert.Equal("黑色功夫装",
                (string)snap["inventory"]["装备栏"]["上装装备"]["name"]);
            Assert.Equal("基础攻击", (string)snap["5"][0][0]);
            Assert.Equal(r.BumpedLastSaved, (string)snap["lastSaved"]);

            // backup 与 audit log 存在
            string backupDir = Path.Combine(_savesDir, ".repair-backups", slot);
            Assert.True(Directory.Exists(backupDir));
            Assert.NotEmpty(Directory.GetFiles(backupDir, "*.broken.json"));
            Assert.NotEmpty(Directory.GetFiles(backupDir, "*.repair.log"));
        }

        [Fact]
        public void RunAll_HiddenAndBackupFiles_NotEnumerated()
        {
            WriteSlot("alice", BuildSnapshotJson("黑色功夫装", "基础攻击"));
            File.WriteAllText(Path.Combine(_savesDir, ".launcher-version-marker.json"),
                "{\"version\":1}", new UTF8Encoding(false));
            File.WriteAllText(Path.Combine(_savesDir, "alice.broken-2026-04-29.json"),
                "{\"x\":1}", new UTF8Encoding(false));

            var results = SaveAutoRepairService.RunAll(_projectRoot, _archive);
            Assert.Single(results);
            Assert.Equal("alice", results[0].Slot);
        }

        [Fact]
        public void RunAll_ManualOnlyL0_KeepsFile_NoApplied()
        {
            // 仅 L0 fffd（角色名）→ 全 manual_required → 0 applied → 不 bump
            string slot = "manual_only";
            JObject snap = BuildSnapshot("黑色功夫装", "基础攻击");
            // 玩家� = "玩家�"
            snap["0"][0] = "玩家�";
            string content = snap.ToString(Newtonsoft.Json.Formatting.None);
            WriteSlot(slot, content);

            var results = SaveAutoRepairService.RunAll(_projectRoot, _archive);
            Assert.Single(results);
            var r = results[0];
            Assert.Equal(1, r.FffdCount);
            Assert.Equal(1, r.SkippedManual);
            Assert.Equal(0, r.Applied);
            // 备份仍写了（保留原档以便 C2-β 卡片人工修复后能 rollback）
            Assert.NotNull(r.BackupPath);
            // 没有 applied/drops → 不 bump lastSaved
            Assert.Null(r.BumpedLastSaved);
        }

        // ─────────────── helpers ───────────────

        private static JObject BuildSnapshot(string equipName, string skill0)
        {
            // 用 \u 转义构造模板，避免源文件 CJK 编码任何环境差异
            JObject s = JObject.Parse(@"{
                ""version"": ""3.0"",
                ""lastSaved"": ""2026-04-15 15:03:28"",
                ""0"": [""玩家A"", ""男"", 1000, 1, 0, 175, 0, null, 1000, 0, [], 0, [], """"],
                ""1"": [],
                ""5"": [[""x"", 1, true, """", true]],
                ""inventory"": {
                    ""装备栏"": { ""上装装备"": { ""name"": ""x"", ""value"": { ""mods"": [], ""level"": 1 } } },
                    ""背包"": {}
                },
                ""tasks"": { ""tasks_finished"": {}, ""task_chains_progress"": {} },
                ""others"": {
                    ""设置"": {},
                    ""击杀统计"": { ""total"": 0, ""byType"": {} },
                    ""物品来源缓存"": { ""discoveredStages"": [], ""discoveredEnemies"": [], ""discoveredQuests"": [] }
                },
                ""collection"": { ""材料"": {}, ""情报"": {} }
            }");
            s["inventory"]["装备栏"]["上装装备"]["name"] = equipName;
            s["5"][0][0] = skill0;
            return s;
        }

        private static string BuildSnapshotJson(string equipName, string skill0)
        {
            return BuildSnapshot(equipName, skill0).ToString(Newtonsoft.Json.Formatting.None);
        }
    }
}
