// RepairBackupStore 单测：验证 saves/.repair-backups/{slot}/ 路径布局、写入、列举与 Prune。
//
// 不变式：备份不污染 saves/ 根目录（INV-4）；保留最新 RetentionCount 份。

using System;
using System.IO;
using System.Linq;
using CF7Launcher.Save;
using Xunit;

namespace CF7Launcher.Tests.Save
{
    public class RepairBackupStoreTests : IDisposable
    {
        private readonly string _savesDir;

        public RepairBackupStoreTests()
        {
            _savesDir = Path.Combine(Path.GetTempPath(), "cf7-repair-backup-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(_savesDir);
        }

        public void Dispose()
        {
            try { if (Directory.Exists(_savesDir)) Directory.Delete(_savesDir, true); }
            catch { }
        }

        [Fact]
        public void GetSlotBackupDir_ReturnsExpectedLayout()
        {
            string dir = RepairBackupStore.GetSlotBackupDir(_savesDir, "test_slot");
            string expected = Path.Combine(_savesDir, ".repair-backups", "test_slot");
            Assert.Equal(expected, dir);
        }

        [Fact]
        public void FormatTimestamp_NoColon_FilesystemSafe()
        {
            // Windows 路径不允许 ':'，必须用 '-' 替代。
            string ts = RepairBackupStore.FormatTimestamp(new DateTime(2026, 4, 29, 12, 34, 56, DateTimeKind.Utc));
            Assert.Equal("2026-04-29T12-34-56", ts);
            Assert.DoesNotContain(":", ts);
        }

        [Fact]
        public void WriteBrokenSnapshot_CreatesFileUnderBackupDir_NotInSavesRoot()
        {
            string ts = RepairBackupStore.FormatTimestamp(DateTime.UtcNow);
            string path = RepairBackupStore.WriteBrokenSnapshot(_savesDir, "test_slot", ts, "{\"foo\":1}");

            Assert.True(File.Exists(path));
            Assert.Contains(".repair-backups", path);
            // 不污染 saves 根
            Assert.Empty(Directory.GetFiles(_savesDir, "*.broken*"));
            Assert.Equal("{\"foo\":1}", File.ReadAllText(path));
        }

        [Fact]
        public void WriteAuditLog_CreatesLogUnderBackupDir()
        {
            string ts = RepairBackupStore.FormatTimestamp(DateTime.UtcNow);
            string path = RepairBackupStore.WriteAuditLog(_savesDir, "test_slot", ts, "applied 3 fixes");

            Assert.True(File.Exists(path));
            Assert.EndsWith(".repair.log", path);
            Assert.Equal("applied 3 fixes", File.ReadAllText(path));
        }

        [Fact]
        public void ListBackupTimestamps_DescendingOrder_PairsDeduped()
        {
            // 写 3 个时间戳的备份，每个含 .broken.json + .repair.log
            string[] timestamps = new[] {
                "2026-04-29T10-00-00",
                "2026-04-29T11-00-00",
                "2026-04-29T09-00-00"
            };
            foreach (string ts in timestamps)
            {
                RepairBackupStore.WriteBrokenSnapshot(_savesDir, "slot", ts, "{}");
                RepairBackupStore.WriteAuditLog(_savesDir, "slot", ts, "log");
            }

            var listed = RepairBackupStore.ListBackupTimestamps(_savesDir, "slot");
            Assert.Equal(3, listed.Count);
            Assert.Equal("2026-04-29T11-00-00", listed[0]);
            Assert.Equal("2026-04-29T10-00-00", listed[1]);
            Assert.Equal("2026-04-29T09-00-00", listed[2]);
        }

        [Fact]
        public void ListBackupTimestamps_NoDir_ReturnsEmpty()
        {
            var listed = RepairBackupStore.ListBackupTimestamps(_savesDir, "never_existed");
            Assert.Empty(listed);
        }

        [Fact]
        public void Prune_KeepsLatestRetentionCount()
        {
            const int total = 10;
            // 制造 10 个递增时间戳
            for (int i = 0; i < total; i++)
            {
                string ts = RepairBackupStore.FormatTimestamp(new DateTime(2026, 4, 29, 0, i, 0, DateTimeKind.Utc));
                RepairBackupStore.WriteBrokenSnapshot(_savesDir, "slot", ts, "{}");
                RepairBackupStore.WriteAuditLog(_savesDir, "slot", ts, "log");
            }
            Assert.Equal(total, RepairBackupStore.ListBackupTimestamps(_savesDir, "slot").Count);

            RepairBackupStore.Prune(_savesDir, "slot");

            var remaining = RepairBackupStore.ListBackupTimestamps(_savesDir, "slot");
            Assert.Equal(RepairBackupStore.RetentionCount, remaining.Count);
            // 最旧的 (00 分) 已被删，最新的 (09 分) 保留
            Assert.Equal("2026-04-29T00-09-00", remaining[0]);
            Assert.Equal("2026-04-29T00-03-00", remaining[remaining.Count - 1]);

            // 配对一起删：被裁剪的时间戳两类文件都应消失
            string dir = RepairBackupStore.GetSlotBackupDir(_savesDir, "slot");
            Assert.False(File.Exists(Path.Combine(dir, "2026-04-29T00-00-00.broken.json")));
            Assert.False(File.Exists(Path.Combine(dir, "2026-04-29T00-00-00.repair.log")));
        }

        [Fact]
        public void Prune_BelowThreshold_NoOp()
        {
            for (int i = 0; i < 3; i++)
            {
                string ts = RepairBackupStore.FormatTimestamp(new DateTime(2026, 4, 29, 0, i, 0, DateTimeKind.Utc));
                RepairBackupStore.WriteBrokenSnapshot(_savesDir, "slot", ts, "{}");
            }
            RepairBackupStore.Prune(_savesDir, "slot");
            Assert.Equal(3, RepairBackupStore.ListBackupTimestamps(_savesDir, "slot").Count);
        }

        [Fact]
        public void IsolatedBetweenSlots()
        {
            string ts = RepairBackupStore.FormatTimestamp(DateTime.UtcNow);
            RepairBackupStore.WriteBrokenSnapshot(_savesDir, "slotA", ts, "A");
            RepairBackupStore.WriteBrokenSnapshot(_savesDir, "slotB", ts, "B");

            Assert.Equal(1, RepairBackupStore.ListBackupTimestamps(_savesDir, "slotA").Count);
            Assert.Equal(1, RepairBackupStore.ListBackupTimestamps(_savesDir, "slotB").Count);

            string aPath = Path.Combine(RepairBackupStore.GetSlotBackupDir(_savesDir, "slotA"), ts + ".broken.json");
            string bPath = Path.Combine(RepairBackupStore.GetSlotBackupDir(_savesDir, "slotB"), ts + ".broken.json");
            Assert.Equal("A", File.ReadAllText(aPath));
            Assert.Equal("B", File.ReadAllText(bPath));
        }
    }
}
