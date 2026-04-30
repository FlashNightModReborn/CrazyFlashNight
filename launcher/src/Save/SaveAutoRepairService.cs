// 启动期自动 silent 修复（C2-α）。
//
// 调用时机：launcher 启动早期（archiveTask 构造之后、Flash 拉起之前）。
// 流程：
//   1. 加载 launcher/data/save_repair_dict.json
//   2. 枚举 saves/{slot}.json（用 ArchiveTask 同款过滤）
//   3. 每个 slot：读 → SaveCorruptionScanner.Scan
//        - 若无 fffd → 跳过
//        - 若有 fffd → 备份原档到 saves/.repair-backups/{slot}/{ts}.broken.json
//                     RepairPolicy.BuildPlan + ApplyHighConfidenceOnly
//                     bump lastSaved（INV-1）
//                     原子写回 saves/{slot}.json
//                     写 audit log
//                     Prune backups 保留最新 N 份
//   4. 全部失败也不阻塞启动（catch + log）
//
// 不弹卡片、不阻塞 — 完全静默。
// L0 / L1 多候选 / L1 装备槽位 key / L1 0 候选物品名 不动，由 C2-β 卡片处理。

using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using CF7Launcher.Guardian;
using CF7Launcher.Tasks;

namespace CF7Launcher.Save
{
    public class SaveAutoRepairResult
    {
        public string Slot;
        public int FffdCount;
        public int Applied;
        public int Drops;
        public int SkippedManual;
        public string BumpedLastSaved;
        public string BackupPath;
        public string Error;
    }

    public static class SaveAutoRepairService
    {
        private static readonly Regex SlotJsonRegex = new Regex(@"^[^.][^.]*\.json$", RegexOptions.Compiled);

        public static List<SaveAutoRepairResult> RunAll(string projectRoot, ArchiveTask archiveTask)
        {
            List<SaveAutoRepairResult> results = new List<SaveAutoRepairResult>();
            string savesDir = archiveTask.SavesDir;
            if (string.IsNullOrEmpty(savesDir) || !Directory.Exists(savesDir)) return results;

            RepairDictionary dict;
            try { dict = RepairDictionary.LoadFromProjectRoot(projectRoot); }
            catch (Exception ex)
            {
                LogManager.Log("[AutoRepair] dict load failed: " + ex.Message + " — auto repair skipped");
                return results;
            }

            string[] files;
            try { files = Directory.GetFiles(savesDir, "*.json"); }
            catch (Exception ex)
            {
                LogManager.Log("[AutoRepair] enumerate saves failed: " + ex.Message);
                return results;
            }

            for (int i = 0; i < files.Length; i++)
            {
                string fileName = Path.GetFileName(files[i]);
                if (!SlotJsonRegex.IsMatch(fileName)) continue; // 排除隐藏 / .broken / .repair / 备份 (INV-4)
                string slot = Path.GetFileNameWithoutExtension(files[i]);
                SaveAutoRepairResult r = new SaveAutoRepairResult();
                r.Slot = slot;
                try
                {
                    RepairOneSlot(savesDir, slot, files[i], dict, r);
                }
                catch (Exception ex)
                {
                    r.Error = ex.Message;
                    LogManager.Log("[AutoRepair] slot=" + slot + " repair failed: " + ex.Message);
                }
                results.Add(r);
            }

            // 总结日志
            int totalSlots = results.Count;
            int touched = 0, totalFffd = 0, totalApplied = 0, totalDrops = 0, totalManual = 0;
            for (int i = 0; i < results.Count; i++)
            {
                if (results[i].FffdCount > 0) touched++;
                totalFffd += results[i].FffdCount;
                totalApplied += results[i].Applied;
                totalDrops += results[i].Drops;
                totalManual += results[i].SkippedManual;
            }
            LogManager.Log("[AutoRepair] done: slots=" + totalSlots
                + " corrupted=" + touched
                + " fffd_total=" + totalFffd
                + " applied=" + totalApplied
                + " drops=" + totalDrops
                + " kept_for_manual=" + totalManual);

            return results;
        }

        private static void RepairOneSlot(string savesDir, string slot, string filePath, RepairDictionary dict, SaveAutoRepairResult r)
        {
            string raw = File.ReadAllText(filePath, Encoding.UTF8);
            int fffd = CountFffd(raw);
            r.FffdCount = fffd;
            if (fffd == 0)
            {
                LogManager.Log("[AutoRepair] slot=" + slot + " clean, skip");
                return;
            }

            JObject snapshot;
            try { snapshot = JObject.Parse(raw); }
            catch (Exception ex)
            {
                r.Error = "json_parse_failed: " + ex.Message;
                LogManager.Log("[AutoRepair] slot=" + slot + " " + r.Error);
                return;
            }

            RepairPlan plan = RepairPolicy.BuildPlan(snapshot, dict);
            if (plan.Decisions.Count == 0)
            {
                LogManager.Log("[AutoRepair] slot=" + slot + " fffd=" + fffd + " but no decisions (rare)");
                return;
            }

            // 备份原档（INV-4）
            string ts = RepairBackupStore.FormatTimestamp(DateTime.UtcNow);
            r.BackupPath = RepairBackupStore.WriteBrokenSnapshot(savesDir, slot, ts, raw);

            // 应用高置信度修复
            RepairApplyResult applied = RepairPolicy.ApplyHighConfidenceOnly(snapshot, plan, DateTime.UtcNow);
            r.Applied = applied.Applied;
            r.Drops = applied.Drops;
            r.SkippedManual = applied.SkippedManual;
            r.BumpedLastSaved = applied.BumpedLastSaved;

            // 写 audit log
            try
            {
                StringBuilder log = new StringBuilder();
                log.Append("# Auto Repair (C2-alpha) — ").Append(DateTime.UtcNow.ToString("o")).Append("\n");
                log.Append("slot: ").Append(slot).Append("\n");
                log.Append("fffd_count: ").Append(fffd).Append("\n");
                log.Append("applied: ").Append(applied.Applied).Append("\n");
                log.Append("drops: ").Append(applied.Drops).Append("\n");
                log.Append("kept_for_manual: ").Append(applied.SkippedManual).Append("\n");
                if (applied.BumpedLastSaved != null) log.Append("lastSaved_bumped: ").Append(applied.BumpedLastSaved).Append("\n");
                log.Append("decisions:\n");
                for (int i = 0; i < plan.Decisions.Count; i++)
                {
                    RepairDecision d = plan.Decisions[i];
                    log.Append("  - path: ").Append(d.Item.PathStr).Append("\n");
                    log.Append("    layer: ").Append(d.Item.Rule.Layer).Append("\n");
                    log.Append("    spot: ").Append(d.Item.Spot).Append("\n");
                    log.Append("    broken: ").Append(d.Item.BrokenString).Append("\n");
                    log.Append("    action: ").Append(d.Action.Kind);
                    if (d.Action.NewValue != null)
                        log.Append(" -> ").Append(d.Action.NewValue);
                    log.Append("\n");
                    if (d.Candidates.Count > 0)
                    {
                        log.Append("    candidates:");
                        for (int j = 0; j < d.Candidates.Count && j < 5; j++)
                        {
                            log.Append(" ").Append(d.Candidates[j].Value)
                               .Append("(").Append(d.Candidates[j].Source).Append(")");
                        }
                        log.Append("\n");
                    }
                }
                RepairBackupStore.WriteAuditLog(savesDir, slot, ts, log.ToString());
            }
            catch (Exception ex)
            {
                LogManager.Log("[AutoRepair] slot=" + slot + " audit log write failed: " + ex.Message);
            }

            // 原子写回（不走 ArchiveTask.TryWriteShadowAtomic 因为 launcher 启动早期 ArchiveTask
            // 还没收到任何 saveAll 推送，shadow 一致性 _prevSnapshots 不需要预热；自己原子写够用）
            try
            {
                string tmpPath = filePath + ".tmp";
                File.WriteAllText(tmpPath, snapshot.ToString(Formatting.None), new UTF8Encoding(false));
                if (File.Exists(filePath)) File.Delete(filePath);
                File.Move(tmpPath, filePath);
            }
            catch (Exception ex)
            {
                r.Error = "write_failed: " + ex.Message;
                LogManager.Log("[AutoRepair] slot=" + slot + " write failed: " + ex.Message);
                return;
            }

            try { RepairBackupStore.Prune(savesDir, slot); }
            catch { /* prune 失败不阻断 */ }

            LogManager.Log("[AutoRepair] slot=" + slot
                + " fffd=" + fffd
                + " applied=" + applied.Applied
                + " drops=" + applied.Drops
                + " kept_for_manual=" + applied.SkippedManual
                + " bumpedLastSaved=" + (applied.BumpedLastSaved ?? "n/a")
                + " backup=" + r.BackupPath);
        }

        private static int CountFffd(string s)
        {
            if (string.IsNullOrEmpty(s)) return 0;
            int n = 0;
            for (int i = 0; i < s.Length; i++)
                if (s[i] == '�') n++;
            return n;
        }
    }
}
