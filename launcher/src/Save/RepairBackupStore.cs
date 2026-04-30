// 修复备份存储（INV-4 — saves 根目录纯净）
//
// 把待修复 saves/{slot}.json 的「原坏档」与「修复 audit log」全部写到
// saves/.repair-backups/{slot}/，保持 saves 根目录只放 {slot}.json /
// {slot}.tombstone / .launcher-version-marker.json 三类文件。
//
// 路径布局：
//   saves/.repair-backups/{slot}/{ts}.broken.json   原坏档完整副本
//   saves/.repair-backups/{slot}/{ts}.repair.log    audit log
// ts 格式：yyyy-MM-ddTHH-mm-ss（冒号在 Windows 路径里非法，故用 '-' 替代）。
// 保留策略：每个 slot 最多 RetentionCount 份，按 ts 字典序降序保留新的。

using System;
using System.Collections.Generic;
using System.IO;
using System.Text;

namespace CF7Launcher.Save
{
    public static class RepairBackupStore
    {
        public const string BackupDirName = ".repair-backups";
        public const int RetentionCount = 7;

        public static string GetSlotBackupDir(string savesDir, string safeSlot)
        {
            if (string.IsNullOrEmpty(savesDir)) throw new ArgumentNullException("savesDir");
            if (string.IsNullOrEmpty(safeSlot)) throw new ArgumentNullException("safeSlot");
            return Path.Combine(Path.Combine(savesDir, BackupDirName), safeSlot);
        }

        public static string FormatTimestamp(DateTime utcNow)
        {
            return utcNow.ToString("yyyy-MM-ddTHH-mm-ss");
        }

        public static string WriteBrokenSnapshot(string savesDir, string safeSlot, string timestamp, string content)
        {
            string dir = GetSlotBackupDir(savesDir, safeSlot);
            Directory.CreateDirectory(dir);
            string path = Path.Combine(dir, timestamp + ".broken.json");
            File.WriteAllText(path, content ?? string.Empty, new UTF8Encoding(false));
            return path;
        }

        public static string WriteAuditLog(string savesDir, string safeSlot, string timestamp, string log)
        {
            string dir = GetSlotBackupDir(savesDir, safeSlot);
            Directory.CreateDirectory(dir);
            string path = Path.Combine(dir, timestamp + ".repair.log");
            File.WriteAllText(path, log ?? string.Empty, new UTF8Encoding(false));
            return path;
        }

        /// <summary>列出 slot 下所有备份的时间戳，按字典序降序（最新在前）。</summary>
        public static List<string> ListBackupTimestamps(string savesDir, string safeSlot)
        {
            string dir = GetSlotBackupDir(savesDir, safeSlot);
            var stamps = new HashSet<string>(StringComparer.Ordinal);
            if (!Directory.Exists(dir))
                return new List<string>();

            foreach (string f in Directory.GetFiles(dir, "*.broken.json"))
                AddStamp(stamps, Path.GetFileName(f), ".broken.json");
            foreach (string f in Directory.GetFiles(dir, "*.repair.log"))
                AddStamp(stamps, Path.GetFileName(f), ".repair.log");

            var list = new List<string>(stamps);
            list.Sort(delegate(string a, string b) { return string.Compare(b, a, StringComparison.Ordinal); });
            return list;
        }

        private static void AddStamp(HashSet<string> stamps, string fileName, string suffix)
        {
            int idx = fileName.IndexOf(suffix, StringComparison.Ordinal);
            if (idx > 0) stamps.Add(fileName.Substring(0, idx));
        }

        /// <summary>清理超出 RetentionCount 的旧备份（配对的 .broken.json + .repair.log 一起删）。</summary>
        public static void Prune(string savesDir, string safeSlot)
        {
            string dir = GetSlotBackupDir(savesDir, safeSlot);
            if (!Directory.Exists(dir)) return;

            var stamps = ListBackupTimestamps(savesDir, safeSlot);
            if (stamps.Count <= RetentionCount) return;

            for (int i = RetentionCount; i < stamps.Count; i++)
            {
                string ts = stamps[i];
                TryDelete(Path.Combine(dir, ts + ".broken.json"));
                TryDelete(Path.Combine(dir, ts + ".repair.log"));
            }
        }

        private static void TryDelete(string path)
        {
            try { if (File.Exists(path)) File.Delete(path); }
            catch { /* 备份清理失败不阻断主流程 */ }
        }
    }
}
