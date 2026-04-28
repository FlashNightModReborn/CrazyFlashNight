// BMH 拆分：logs / open_saves_dir / diagnostic / audio_preview。
// diagnostic / audio_preview 为 Phase 5.8 新增（迁移期音频临时入口配套）。

using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using CF7Launcher.Tasks;
using CF7Launcher.Audio;
using CF7Launcher.Save;
using CF7Launcher.Diagnostic;

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

        // ─────── diagnostic（Phase 5.8）───────
        // web 端"导出诊断包"按钮入口；fire-and-forget。
        // 响应 cmd: "diagnostic_resp" { ok, zipName, zipSize, zipPath, warnings:[] }

        internal static void HandleDiagnostic(JObject msg, BootstrapPanel bootForm, SaveResolutionContext saveCtx)
        {
            string slot = msg.Value<string>("slot");
            JObject outMsg = new JObject();
            outMsg["type"] = "bootstrap";
            outMsg["cmd"] = "diagnostic_resp";

            if (saveCtx == null || string.IsNullOrEmpty(saveCtx.ProjectRoot))
            {
                outMsg["ok"] = false;
                outMsg["error"] = "saveCtx/projectRoot unavailable";
                bootForm.PostToWeb(outMsg.ToString(Formatting.None));
                return;
            }

            DiagnosticResult result = DiagnosticPackager.Pack(
                saveCtx.ProjectRoot, slot, saveCtx.SwfPath, saveCtx.Locator);

            outMsg["ok"] = result.Ok;
            if (result.Ok)
            {
                outMsg["zipPath"] = result.ZipPath;
                outMsg["zipName"] = result.ZipName;
                outMsg["zipSize"] = result.ZipSize;
            }
            else
            {
                outMsg["error"] = result.Error ?? "unknown";
            }
            JArray warnings = new JArray();
            if (result.Warnings != null)
                for (int i = 0; i < result.Warnings.Count; i++) warnings.Add(result.Warnings[i]);
            outMsg["warnings"] = warnings;
            bootForm.PostToWeb(outMsg.ToString(Formatting.None));
        }

        // ─────── audio_preview（Phase 5.8）───────
        // web 端存档编辑器系统卡片"试听"按钮入口；不需回执（响应仅供前端 ack 状态）。
        // 协议: { cmd: "audio_preview", channel: "master|bgm|sfx", value: 0..100 }
        // - 写入 launcher 实际音频引擎（master_vol / bgm_vol / sfx_vol，0..1）
        // - SFX 通道额外触发硬编码常驻 SFX 播放（Button9.wav）
        //
        // 响应 cmd: "audio_preview_resp" { ok, channel, applied, played }

        private const string PREVIEW_SFX_ID = "Button9.wav";

        internal static void HandleAudioPreview(JObject msg, BootstrapPanel bootForm)
        {
            string channel = msg.Value<string>("channel");
            float value = msg.Value<float?>("value") ?? 0f;
            float vol01 = value / 100f;
            if (vol01 < 0f) vol01 = 0f;
            if (vol01 > 1f) vol01 = 1f;

            JObject outMsg = new JObject();
            outMsg["type"] = "bootstrap";
            outMsg["cmd"] = "audio_preview_resp";
            outMsg["channel"] = channel;
            outMsg["applied"] = false;
            outMsg["played"] = false;

            try
            {
                if (channel == "master")
                {
                    AudioEngine.ma_bridge_set_master_volume(vol01);
                    outMsg["applied"] = true;
                }
                else if (channel == "bgm")
                {
                    AudioEngine.ma_bridge_bgm_set_volume(vol01);
                    outMsg["applied"] = true;
                }
                else if (channel == "sfx")
                {
                    AudioEngine.ma_bridge_sfx_set_volume(vol01);
                    outMsg["applied"] = true;
                    int handle = AudioEngine.ResolveSfxHandle(PREVIEW_SFX_ID);
                    if (handle >= 0)
                    {
                        AudioEngine.ma_bridge_sfx_play(handle, 1f);
                        outMsg["played"] = true;
                    }
                }
                else
                {
                    outMsg["error"] = "unknown channel: " + channel;
                }
                outMsg["ok"] = true;
            }
            catch (Exception ex)
            {
                outMsg["ok"] = false;
                outMsg["error"] = ex.Message;
                LogManager.Log("[BMH] audio_preview failed: " + ex.Message);
            }
            bootForm.PostToWeb(outMsg.ToString(Formatting.None));
        }
    }
}
