// CF7:ME 诊断包打包器
// 把当前档(json + sol 二进制原件) + launcher.log + 配置 + 系统信息 打成 zip 给开发者排查
// C# 5 syntax

using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Text;
using CF7Launcher.Guardian;
using CF7Launcher.Save;

namespace CF7Launcher.Diagnostic
{
    public class DiagnosticResult
    {
        public bool Ok;
        public string ZipPath;
        public string ZipName;
        public long ZipSize;
        public string Error;
        public List<string> Warnings;
    }

    /// <summary>
    /// 一次性打包诊断 zip，落到 &lt;projectRoot&gt;/logs/diagnostic-{slot}-{ts}.zip。
    /// 调用方负责传 slot（当前编辑器聚焦的存档）；slot 为 null 时只打 logs + 配置 + 系统信息。
    /// SOL 一律按二进制原件复制，迁移期需要原始字节做对比。
    /// </summary>
    public static class DiagnosticPackager
    {
        public static DiagnosticResult Pack(
            string projectRoot,
            string slot,
            string swfPath,
            ISolFileLocator solLocator)
        {
            DiagnosticResult r = new DiagnosticResult();
            r.Warnings = new List<string>();

            if (string.IsNullOrEmpty(projectRoot) || !Directory.Exists(projectRoot))
            {
                r.Ok = false;
                r.Error = "projectRoot invalid";
                return r;
            }

            string outDir = Path.Combine(projectRoot, "logs");
            try { if (!Directory.Exists(outDir)) Directory.CreateDirectory(outDir); }
            catch (Exception ex) { r.Ok = false; r.Error = "create logs dir failed: " + ex.Message; return r; }

            string ts = DateTime.Now.ToString("yyyyMMdd-HHmmss");
            string slotPart = string.IsNullOrEmpty(slot) ? "" : "-" + SanitizeForFilename(slot);
            string zipName = "diagnostic" + slotPart + "-" + ts + ".zip";
            string zipPath = Path.Combine(outDir, zipName);

            try
            {
                using (FileStream fs = new FileStream(zipPath, FileMode.Create, FileAccess.Write))
                using (ZipArchive zip = new ZipArchive(fs, ZipArchiveMode.Create))
                {
                    PackSave(zip, projectRoot, slot, swfPath, solLocator, r.Warnings);
                    PackLogs(zip, projectRoot, r.Warnings);
                    PackConfig(zip, projectRoot, r.Warnings);
                    PackMeta(zip, projectRoot, slot);
                    PackReadme(zip, slot);
                }

                FileInfo fi = new FileInfo(zipPath);
                r.Ok = true;
                r.ZipPath = zipPath;
                r.ZipName = zipName;
                r.ZipSize = fi.Length;
                LogManager.Log("[Diagnostic] packed " + zipName + " size=" + fi.Length
                    + " warnings=" + r.Warnings.Count);
                return r;
            }
            catch (Exception ex)
            {
                try { if (File.Exists(zipPath)) File.Delete(zipPath); } catch { }
                r.Ok = false;
                r.Error = ex.Message;
                LogManager.Log("[Diagnostic] pack FAILED: " + ex.Message);
                return r;
            }
        }

        private static void PackSave(ZipArchive zip, string projectRoot, string slot, string swfPath,
            ISolFileLocator solLocator, List<string> warnings)
        {
            if (string.IsNullOrEmpty(slot)) return;

            string safeName = SanitizeSlotForJson(slot);
            string saveJson = Path.Combine(projectRoot, "saves", safeName + ".json");
            if (File.Exists(saveJson))
                AddFile(zip, saveJson, "save/" + safeName + ".json");
            else
                warnings.Add("save json missing: saves/" + safeName + ".json");

            // SOL：二进制原件复制（迁移期权威源对比需要原始字节）
            if (solLocator != null && !string.IsNullOrEmpty(swfPath))
            {
                try
                {
                    string solPath = solLocator.FindSolFile(slot, swfPath);
                    if (!string.IsNullOrEmpty(solPath) && File.Exists(solPath))
                        AddFile(zip, solPath, "save/" + safeName + ".sol");
                    else
                        warnings.Add("sol not located for slot: " + slot);
                }
                catch (Exception ex)
                {
                    warnings.Add("sol locate exception: " + ex.Message);
                }
            }
            else
            {
                warnings.Add("sol locator/swfPath unavailable; skipping sol");
            }
        }

        private static void PackLogs(ZipArchive zip, string projectRoot, List<string> warnings)
        {
            string current = Path.Combine(projectRoot, "logs", "launcher.log");
            string backup = Path.Combine(projectRoot, "logs", "launcher.log.1");
            if (File.Exists(current))
                AddFileShared(zip, current, "logs/launcher.log");
            else
                warnings.Add("launcher.log missing");
            if (File.Exists(backup))
                AddFileShared(zip, backup, "logs/launcher.log.1");
        }

        private static void PackConfig(ZipArchive zip, string projectRoot, List<string> warnings)
        {
            string cfgToml = Path.Combine(projectRoot, "config.toml");
            if (File.Exists(cfgToml))
                AddFile(zip, cfgToml, "config/config.toml");

            string localPrefs = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "CF7FlashNight", "launcher_user_prefs.json");
            if (File.Exists(localPrefs))
                AddFile(zip, localPrefs, "config/launcher_user_prefs.json");

            string legacyPrefs = Path.Combine(projectRoot, "launcher_user_prefs.json");
            if (File.Exists(legacyPrefs))
                AddFile(zip, legacyPrefs, "config/launcher_user_prefs.legacy.json");
        }

        private static void PackMeta(ZipArchive zip, string projectRoot, string slot)
        {
            StringBuilder sb = new StringBuilder();
            sb.Append("{\n");
            sb.Append("  \"generatedAt\": \"").Append(DateTime.Now.ToString("yyyy-MM-ddTHH:mm:ssK")).Append("\",\n");
            sb.Append("  \"slot\": ").Append(slot == null ? "null" : "\"" + EscapeJson(slot) + "\"").Append(",\n");
            sb.Append("  \"projectRoot\": \"").Append(EscapeJson(projectRoot)).Append("\",\n");
            sb.Append("  \"os\": \"").Append(EscapeJson(Environment.OSVersion.ToString())).Append("\",\n");
            sb.Append("  \"clr\": \"").Append(EscapeJson(Environment.Version.ToString())).Append("\",\n");
            sb.Append("  \"machine\": \"").Append(EscapeJson(Environment.MachineName)).Append("\",\n");
            sb.Append("  \"is64BitProcess\": ").Append(Environment.Is64BitProcess ? "true" : "false").Append(",\n");
            sb.Append("  \"is64BitOS\": ").Append(Environment.Is64BitOperatingSystem ? "true" : "false").Append(",\n");
            sb.Append("  \"processorCount\": ").Append(Environment.ProcessorCount).Append(",\n");
            sb.Append("  \"workingSetMB\": ").Append(Environment.WorkingSet / 1024 / 1024).Append(",\n");
            sb.Append("  \"gitHead\": \"").Append(EscapeJson(TryReadGitHead(projectRoot))).Append("\"\n");
            sb.Append("}\n");
            AddText(zip, "meta.json", sb.ToString());
        }

        private static void PackReadme(ZipArchive zip, string slot)
        {
            StringBuilder sb = new StringBuilder();
            sb.Append("CF7:ME 诊断包\r\n");
            sb.Append("生成时间: ").Append(DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss")).Append("\r\n");
            sb.Append("\r\n");
            sb.Append("内容\r\n");
            sb.Append("----\r\n");
            if (!string.IsNullOrEmpty(slot))
            {
                sb.Append("save/        当前编辑的存档（JSON + 原始 SOL 二进制）\r\n");
            }
            sb.Append("logs/        launcher.log + launcher.log.1（最近两份运行日志）\r\n");
            sb.Append("config/      config.toml + launcher_user_prefs.json（用户偏好）\r\n");
            sb.Append("meta.json    系统信息：OS / git HEAD / 时间戳 / 机器名等\r\n");
            sb.Append("\r\n");
            sb.Append("使用\r\n");
            sb.Append("----\r\n");
            sb.Append("把整个 zip 文件发给开发者即可。请勿单独抽出文件发送。\r\n");
            AddText(zip, "README.txt", sb.ToString());
        }

        // ==================== helpers ====================

        private static void AddFile(ZipArchive zip, string sourcePath, string entryName)
        {
            zip.CreateEntryFromFile(sourcePath, entryName, CompressionLevel.Optimal);
        }

        // launcher.log 可能正被 launcher 自身写入，必须以 FileShare.ReadWrite 打开
        private static void AddFileShared(ZipArchive zip, string sourcePath, string entryName)
        {
            ZipArchiveEntry entry = zip.CreateEntry(entryName, CompressionLevel.Optimal);
            using (FileStream fs = new FileStream(sourcePath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
            using (Stream zs = entry.Open())
            {
                byte[] buf = new byte[64 * 1024];
                int n;
                while ((n = fs.Read(buf, 0, buf.Length)) > 0) zs.Write(buf, 0, n);
            }
        }

        private static void AddText(ZipArchive zip, string entryName, string content)
        {
            ZipArchiveEntry entry = zip.CreateEntry(entryName, CompressionLevel.Optimal);
            using (StreamWriter sw = new StreamWriter(entry.Open(), new UTF8Encoding(false)))
                sw.Write(content);
        }

        // 与 ArchiveTask.SanitizeSlotName 同口径：非法字符替换 _，不删除
        private static string SanitizeSlotForJson(string slot)
        {
            return System.Text.RegularExpressions.Regex.Replace(slot, @"[^a-zA-Z0-9_\-]", "_");
        }

        // 文件名场景下 slot 直接落进 zip 名，作风更严，多打掉路径分隔符
        private static string SanitizeForFilename(string s)
        {
            return System.Text.RegularExpressions.Regex.Replace(s, @"[^a-zA-Z0-9_\-]", "_");
        }

        private static string TryReadGitHead(string projectRoot)
        {
            try
            {
                string headFile = Path.Combine(projectRoot, ".git", "HEAD");
                if (!File.Exists(headFile)) return "(no .git)";
                string head = File.ReadAllText(headFile).Trim();
                if (head.StartsWith("ref: "))
                {
                    string refPath = head.Substring(5);
                    string refFile = Path.Combine(projectRoot, ".git", refPath);
                    if (File.Exists(refFile))
                        return File.ReadAllText(refFile).Trim().Substring(0, 12) + " (" + refPath + ")";
                    return head;
                }
                return head.Length >= 12 ? head.Substring(0, 12) + " (detached)" : head;
            }
            catch (Exception ex)
            {
                return "(read failed: " + ex.Message + ")";
            }
        }

        private static string EscapeJson(string s)
        {
            if (s == null) return "";
            StringBuilder sb = new StringBuilder(s.Length);
            foreach (char c in s)
            {
                if (c == '\\') sb.Append("\\\\");
                else if (c == '"') sb.Append("\\\"");
                else if (c == '\n') sb.Append("\\n");
                else if (c == '\r') sb.Append("\\r");
                else if (c == '\t') sb.Append("\\t");
                else if (c < 0x20) sb.Append("\\u").Append(((int)c).ToString("X4"));
                else sb.Append(c);
            }
            return sb.ToString();
        }
    }
}
