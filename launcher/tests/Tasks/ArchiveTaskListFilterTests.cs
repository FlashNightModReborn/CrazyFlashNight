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
using CF7Launcher.Tasks;
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

        // ───────────── helpers ─────────────

        private void WriteJson(string fileName, string content)
        {
            File.WriteAllText(Path.Combine(_savesDir, fileName), content, new UTF8Encoding(false));
        }

        private JArray ListSlots()
        {
            JObject msg = new JObject();
            JObject payload = new JObject();
            payload["op"] = "list";
            msg["payload"] = payload;

            string responseJson = null;
            using (ManualResetEventSlim done = new ManualResetEventSlim(false))
            {
                _archive.HandleAsync(msg, delegate(string r) { responseJson = r; done.Set(); });
                Assert.True(done.Wait(TimeSpan.FromSeconds(5)), "Timed out waiting for list response");
            }

            JObject response = JObject.Parse(responseJson);
            Assert.True(response.Value<bool>("success"));
            return response.Value<JArray>("slots");
        }
    }
}
