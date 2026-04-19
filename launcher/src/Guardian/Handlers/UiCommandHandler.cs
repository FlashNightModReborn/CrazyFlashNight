// BMH 拆分：logs / open_saves_dir。
// 零行为改动，纯搬运。

using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using CF7Launcher.Tasks;

namespace CF7Launcher.Guardian.Handlers
{
    internal static class UiCommandHandler
    {
        // ─────── logs ───────

        internal static void HandleLogs(JObject msg, BootstrapPanel bootForm)
        {
            int requestedLines = 200;
            int? linesParam = msg.Value<int?>("lines");
            if (linesParam.HasValue && linesParam.Value >= 1 && linesParam.Value <= 2000)
                requestedLines = linesParam.Value;

            string logPath = LogManager.LogFilePath;
            if (string.IsNullOrEmpty(logPath) || !File.Exists(logPath))
            {
                JObject errMsg = new JObject();
                errMsg["type"] = "bootstrap";
                errMsg["cmd"] = "logs_resp";
                errMsg["lines"] = new JArray();
                errMsg["total"] = 0;
                bootForm.PostToWeb(errMsg.ToString(Formatting.None));
                return;
            }

            try
            {
                string[] allLines;
                using (FileStream fs = new FileStream(logPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
                using (StreamReader sr = new StreamReader(fs, Encoding.UTF8))
                {
                    allLines = sr.ReadToEnd().Split(new char[] { '\n' });
                }

                List<string> clean = new List<string>();
                for (int i = 0; i < allLines.Length; i++)
                {
                    string line = allLines[i].TrimEnd('\r');
                    if (line.Length > 0)
                        clean.Add(line);
                }

                int total = clean.Count;
                int skip = total > requestedLines ? total - requestedLines : 0;

                JArray linesArr = new JArray();
                for (int i = skip; i < clean.Count; i++)
                    linesArr.Add(clean[i]);

                JObject outMsg = new JObject();
                outMsg["type"] = "bootstrap";
                outMsg["cmd"] = "logs_resp";
                outMsg["lines"] = linesArr;
                outMsg["total"] = total;
                bootForm.PostToWeb(outMsg.ToString(Formatting.None));
            }
            catch (Exception ex)
            {
                LogManager.Log("[BMH] logs read failed: " + ex.Message);
                JObject errMsg = new JObject();
                errMsg["type"] = "bootstrap";
                errMsg["cmd"] = "logs_resp";
                errMsg["lines"] = new JArray();
                errMsg["total"] = 0;
                bootForm.PostToWeb(errMsg.ToString(Formatting.None));
            }
        }

        // ─────── open_saves_dir ───────

        internal static void HandleOpenSavesDir(ArchiveTask archiveTask)
        {
            string dir = archiveTask.SavesDir;
            if (string.IsNullOrEmpty(dir) || !System.IO.Directory.Exists(dir))
            {
                LogManager.Log("[BMH] open_saves_dir: directory not found");
                return;
            }
            try
            {
                System.Diagnostics.Process.Start("explorer.exe", dir);
            }
            catch (Exception ex)
            {
                LogManager.Log("[BMH] open_saves_dir failed: " + ex.Message);
            }
        }
    }
}
