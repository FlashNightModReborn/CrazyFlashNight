// P3b Phase 1g + Phase 2a: Bootstrap JS→C# 协议 handler
// Phase 1 入站 cmd: ready / list / start_game / delete / rebuild / retry / ping
// Phase 2a 入站 cmd: load / load_raw / save / reset / export / import_start / import_commit / logs
// Phase 1 出站 cmd: state / list_resp / delete_resp / error / pong
// Phase 2a 出站 cmd: load_resp / load_raw_resp / save_resp / reset_resp / export_resp / import_target / import_resp / logs_resp
// 详见 plan compressed-floating-nebula.md Phase 2a §4.3 协议表。

using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using CF7Launcher.Tasks;
using CF7Launcher.Config;

namespace CF7Launcher.Guardian
{
    public static class BootstrapMessageHandler
    {
        public static void Handle(
            string json,
            BootstrapPanel bootForm,
            ArchiveTask archiveTask,
            GameLaunchFlow launchFlow,
            UserPrefs userPrefs)
        {
            JObject msg;
            try { msg = JObject.Parse(json); }
            catch (Exception ex)
            {
                PostError(bootForm, "bad_json", ex.Message);
                return;
            }

            string cmd = msg.Value<string>("cmd");
            if (string.IsNullOrEmpty(cmd))
            {
                PostError(bootForm, "unknown_cmd", "missing cmd");
                return;
            }

            switch (cmd)
            {
                // ==================== Phase 1 existing ====================
                case "ready":
                    // Phase D Step D9: 冷启动 prewarm 触发. Prewarm() 内部 session-level latch
                    // (_prewarmTriggered) 保证一次 launcher 生命周期仅尝试一次 — bootstrap.html
                    // reload / 双 rAF 导致 ready 多发也 no-op.
                    if (launchFlow != null)
                    {
                        try { launchFlow.Prewarm(); }
                        catch (Exception ex) { LogManager.Log("[BMH] Prewarm invoke error: " + ex.Message); }
                    }
                    return;

                case "ping":
                    PostPong(bootForm, msg["payload"]);
                    return;

                case "list":
                    // Phase 2b: list_resp 额外附带 UserPrefs 里的 lastPlayedSlot / introEnabled
                    DispatchArchive(bootForm, archiveTask, BuildArchivePayload("list", null), "list_resp",
                        /*forwardSlots:*/ true, userPrefs);
                    return;

                // Phase 2b: 前端改 "加载片头动画" 复选框等, 落到 UserPrefs
                case "config_set":
                    HandleConfigSet(msg, bootForm, userPrefs);
                    return;

                case "delete":
                    {
                        string slot = msg.Value<string>("slot");
                        if (string.IsNullOrEmpty(slot)) { PostError(bootForm, "slot_missing", "delete needs slot"); return; }
                        DispatchArchive(bootForm, archiveTask, BuildArchivePayload("delete", slot), "delete_resp",
                            /*forwardSlots:*/ false);
                        return;
                    }

                case "start_game":
                case "rebuild":
                    {
                        string slot = msg.Value<string>("slot");
                        if (string.IsNullOrEmpty(slot)) { PostError(bootForm, "slot_missing", cmd + " needs slot"); return; }
                        if (launchFlow == null)
                        {
                            PostError(bootForm, "flash_start_failed", "launchFlow not available (flash path missing?)");
                            return;
                        }
                        // Phase 2b: 落盘 lastPlayedSlot — 只记录 start_game (实际游玩意图),
                        // rebuild 不算"玩家玩这个槽位", 不 overwrite.
                        if (cmd == "start_game" && userPrefs != null && userPrefs.LastPlayedSlot != slot)
                        {
                            userPrefs.LastPlayedSlot = slot;
                            userPrefs.Save();
                        }
                        // Phase 2b-ext: defer reveal 两个独立 flag, 前端按需 opt-in
                        //   deferReveal       — 片头视频播放期 (JS 发 reveal_ok 才清)
                        //   requireFlashReveal — Flash 封面帧 (Flash 发 bootstrap_reveal_ready 才清)
                        bool deferJs = msg.Value<bool?>("deferReveal") ?? false;
                        bool reqFlash = msg.Value<bool?>("requireFlashReveal") ?? false;
                        launchFlow.StartGame(slot, deferJs, reqFlash);
                        return;
                    }

                // Phase 2b-ext: JS 侧 reveal 信号 (片头视频播完 / 跳过 / 无片头直通)
                case "reveal_ok":
                    if (launchFlow != null) launchFlow.OnJsRevealOk();
                    return;

                case "retry":
                    if (launchFlow == null) { PostError(bootForm, "flash_start_failed", "launchFlow not available"); return; }
                    launchFlow.Retry();
                    return;

                case "cancel_launch":
                    // Phase B Step B2: 启动中用户主动取消。仅非 Idle 有效，Idle 下 no-op + log
                    if (launchFlow == null) return;
                    if (launchFlow.CurrentState == "Idle")
                    {
                        LogManager.Log("[BMH] cancel_launch ignored: state=Idle");
                        return;
                    }
                    launchFlow.Reset(null, "user_cancel");
                    return;

                // ==================== Phase 2a new ====================
                case "load":
                    {
                        string slot = msg.Value<string>("slot");
                        if (string.IsNullOrEmpty(slot)) { PostError(bootForm, "slot_missing", "load needs slot"); return; }
                        DispatchArchiveGeneric(bootForm, archiveTask, BuildArchivePayload("load", slot), "load_resp");
                        return;
                    }

                case "load_raw":
                    {
                        string slot = msg.Value<string>("slot");
                        if (string.IsNullOrEmpty(slot)) { PostError(bootForm, "slot_missing", "load_raw needs slot"); return; }
                        DispatchArchiveGeneric(bootForm, archiveTask, BuildArchivePayload("load_raw", slot), "load_raw_resp");
                        return;
                    }

                case "save":
                    HandleSave(msg, bootForm, archiveTask, launchFlow);
                    return;

                case "reset":
                    HandleReset(msg, bootForm, archiveTask, launchFlow);
                    return;

                case "export":
                    HandleExport(msg, bootForm, archiveTask);
                    return;

                case "import_start":
                    HandleImportStart(bootForm, archiveTask, launchFlow);
                    return;

                case "import_commit":
                    HandleImportCommit(msg, bootForm, archiveTask, launchFlow);
                    return;

                case "logs":
                    HandleLogs(msg, bootForm);
                    return;

                case "open_saves_dir":
                    HandleOpenSavesDir(archiveTask);
                    return;

                default:
                    PostError(bootForm, "unknown_cmd", cmd);
                    return;
            }
        }

        // ==================== Phase 2a: save ====================
        // 职责：Idle 守卫 + NormalizeDataToJObject + 注入 userEdit:true → HandleShadow 内做 schema/tombstone/lastSaved

        private static void HandleSave(JObject msg, BootstrapPanel bootForm, ArchiveTask archiveTask, GameLaunchFlow launchFlow)
        {
            RequireIdleOrTearDown("save", bootForm, launchFlow, delegate { HandleSaveInternal(msg, bootForm, archiveTask); });
        }

        private static void HandleSaveInternal(JObject msg, BootstrapPanel bootForm, ArchiveTask archiveTask)
        {
            string slot = msg.Value<string>("slot");
            if (string.IsNullOrEmpty(slot)) { PostResp(bootForm, "save_resp", false, null, "slot_missing"); return; }

            JObject dataObj;
            string normErr;
            if (!NormalizeDataToJObject(msg["data"], out dataObj, out normErr))
            {
                PostResp(bootForm, "save_resp", false, slot, normErr);
                return;
            }

            // 构造 archive shadow payload，注入 userEdit:true
            JObject archiveMsg = new JObject();
            archiveMsg["task"] = "archive";
            JObject payload = new JObject();
            payload["op"] = "shadow";
            payload["slot"] = slot;
            payload["data"] = dataObj;
            payload["userEdit"] = true;
            archiveMsg["payload"] = payload;

            archiveTask.HandleAsync(archiveMsg, delegate(string resultJson)
            {
                JObject result;
                try { result = JObject.Parse(resultJson); }
                catch
                {
                    PostResp(bootForm, "save_resp", false, slot, "archive_task_failed");
                    return;
                }

                bool ok = result.Value<bool?>("success") ?? false;
                JObject outMsg = new JObject();
                outMsg["type"] = "bootstrap";
                outMsg["cmd"] = "save_resp";
                outMsg["slot"] = slot;
                outMsg["ok"] = ok;
                if (ok)
                {
                    JToken size = result["size"];
                    if (size != null) outMsg["size"] = size;
                    JToken warnings = result["warnings"];
                    if (warnings != null) outMsg["warnings"] = warnings;
                }
                else
                {
                    string err = result.Value<string>("error");
                    if (err != null) outMsg["error"] = err;
                }
                bootForm.PostToWeb(outMsg.ToString(Formatting.None));
            });
        }

        // ==================== Phase 2a: reset ====================

        private static void HandleReset(JObject msg, BootstrapPanel bootForm, ArchiveTask archiveTask, GameLaunchFlow launchFlow)
        {
            RequireIdleOrTearDown("reset", bootForm, launchFlow, delegate { HandleResetInternal(msg, bootForm, archiveTask); });
        }

        private static void HandleResetInternal(JObject msg, BootstrapPanel bootForm, ArchiveTask archiveTask)
        {
            string slot = msg.Value<string>("slot");
            if (string.IsNullOrEmpty(slot)) { PostResp(bootForm, "reset_resp", false, null, "slot_missing"); return; }

            bool confirm = msg.Value<bool?>("confirm") ?? false;
            if (!confirm) { PostResp(bootForm, "reset_resp", false, slot, "confirm_required"); return; }

            JObject archiveMsg = BuildArchivePayload("reset", slot);
            archiveTask.HandleAsync(archiveMsg, delegate(string resultJson)
            {
                JObject result;
                try { result = JObject.Parse(resultJson); }
                catch
                {
                    PostResp(bootForm, "reset_resp", false, slot, "archive_task_failed");
                    return;
                }

                bool ok = result.Value<bool?>("success") ?? false;
                JObject outMsg = new JObject();
                outMsg["type"] = "bootstrap";
                outMsg["cmd"] = "reset_resp";
                outMsg["slot"] = slot;
                outMsg["ok"] = ok;
                if (!ok)
                {
                    string err = result.Value<string>("error");
                    if (err != null) outMsg["error"] = err;
                }
                bootForm.PostToWeb(outMsg.ToString(Formatting.None));
            });
        }

        // ==================== Phase 2a: export ====================
        // JS 侧按 slotMeta 决定 forceRaw: corrupt/inconsistent → true

        private static void HandleExport(JObject msg, BootstrapPanel bootForm, ArchiveTask archiveTask)
        {
            string slot = msg.Value<string>("slot");
            if (string.IsNullOrEmpty(slot)) { PostResp(bootForm, "export_resp", false, null, "slot_missing"); return; }

            bool forceRaw = msg.Value<bool?>("forceRaw") ?? false;
            string defaultName = msg.Value<string>("defaultName");
            string op = forceRaw ? "load_raw" : "load";

            JObject archiveMsg = BuildArchivePayload(op, slot);
            archiveTask.HandleAsync(archiveMsg, delegate(string resultJson)
            {
                JObject result;
                try { result = JObject.Parse(resultJson); }
                catch
                {
                    PostResp(bootForm, "export_resp", false, slot, "archive_task_failed");
                    return;
                }

                bool loadOk = result.Value<bool?>("success") ?? false;
                if (!loadOk)
                {
                    string err = result.Value<string>("error");
                    PostResp(bootForm, "export_resp", false, slot, err ?? "load_failed");
                    return;
                }

                string data = result.Value<string>("data");
                if (string.IsNullOrEmpty(data))
                {
                    PostResp(bootForm, "export_resp", false, slot, "empty_data");
                    return;
                }

                // SaveFileDialog 必须在 UI 线程；HandleAsync callback 在 ThreadPool
                // 通过 BeginInvoke 封送回 UI 线程
                try
                {
                    bootForm.BeginInvoke(new Action(delegate
                    {
                        string path = bootForm.ShowSaveFileDialog(
                            "JSON 文件|*.json|所有文件|*.*",
                            "导出存档",
                            defaultName ?? (slot + ".json"));

                        if (string.IsNullOrEmpty(path))
                        {
                            PostResp(bootForm, "export_resp", false, slot, "cancelled");
                            return;
                        }

                        try
                        {
                            File.WriteAllText(path, data, new UTF8Encoding(false));
                            JObject outMsg = new JObject();
                            outMsg["type"] = "bootstrap";
                            outMsg["cmd"] = "export_resp";
                            outMsg["slot"] = slot;
                            outMsg["ok"] = true;
                            outMsg["path"] = path;
                            bootForm.PostToWeb(outMsg.ToString(Formatting.None));
                        }
                        catch (Exception ex)
                        {
                            PostResp(bootForm, "export_resp", false, slot, "write_failed: " + ex.Message);
                        }
                    }));
                }
                catch (Exception ex)
                {
                    PostResp(bootForm, "export_resp", false, slot, "invoke_failed: " + ex.Message);
                }
            });
        }

        // ==================== Phase 2a: import_start ====================
        // 同步流程：Idle 守卫 → OpenFileDialog → 读文件 → schema 早期校验 → PostToWeb import_target
        // Handle 在 UI 线程调用，ShowOpenFileDialog 直接同步弹出

        private static void HandleImportStart(BootstrapPanel bootForm, ArchiveTask archiveTask, GameLaunchFlow launchFlow)
        {
            RequireIdleOrTearDown("import_start", bootForm, launchFlow, delegate { HandleImportStartInternal(bootForm); });
        }

        private static void HandleImportStartInternal(BootstrapPanel bootForm)
        {
            string filePath = bootForm.ShowOpenFileDialog(
                "JSON 文件|*.json|所有文件|*.*",
                "导入存档");

            if (string.IsNullOrEmpty(filePath))
            {
                PostResp(bootForm, "import_resp", false, null, "cancelled");
                return;
            }

            string fileContent;
            try
            {
                fileContent = File.ReadAllText(filePath, Encoding.UTF8);
            }
            catch (Exception ex)
            {
                PostResp(bootForm, "import_resp", false, null, "read_failed: " + ex.Message);
                return;
            }

            // 早期 schema 校验（BMH 侧唯一保留的 schema 校验点）
            JObject dataObj;
            string normErr;
            if (!NormalizeDataToJObject(new JValue(fileContent), out dataObj, out normErr))
            {
                PostResp(bootForm, "import_resp", false, null, normErr);
                return;
            }

            string schemaErr;
            if (!ArchiveTask.ValidateSchemaStructure(dataObj, out schemaErr))
            {
                PostResp(bootForm, "import_resp", false, null, schemaErr);
                return;
            }

            // 从文件名推测 slot（去 .json 后缀 + sanitize）
            string suggestedSlot = Path.GetFileNameWithoutExtension(filePath);

            JObject outMsg = new JObject();
            outMsg["type"] = "bootstrap";
            outMsg["cmd"] = "import_target";
            outMsg["sourceData"] = fileContent;
            outMsg["suggestedSlot"] = suggestedSlot;
            outMsg["ok"] = true;
            bootForm.PostToWeb(outMsg.ToString(Formatting.None));
        }

        // ==================== Phase 2a: import_commit ====================
        // 职责同 save：Idle + NormalizeDataToJObject + 注入 userEdit:true → HandleShadow

        private static void HandleImportCommit(JObject msg, BootstrapPanel bootForm, ArchiveTask archiveTask, GameLaunchFlow launchFlow)
        {
            RequireIdleOrTearDown("import_commit", bootForm, launchFlow, delegate { HandleImportCommitInternal(msg, bootForm, archiveTask); });
        }

        private static void HandleImportCommitInternal(JObject msg, BootstrapPanel bootForm, ArchiveTask archiveTask)
        {
            string slot = msg.Value<string>("slot");
            if (string.IsNullOrEmpty(slot)) { PostResp(bootForm, "import_resp", false, null, "slot_missing"); return; }

            JObject dataObj;
            string normErr;
            if (!NormalizeDataToJObject(msg["data"], out dataObj, out normErr))
            {
                PostResp(bootForm, "import_resp", false, slot, normErr);
                return;
            }

            // 构造 archive shadow payload，注入 userEdit:true
            JObject archiveMsg = new JObject();
            archiveMsg["task"] = "archive";
            JObject payload = new JObject();
            payload["op"] = "shadow";
            payload["slot"] = slot;
            payload["data"] = dataObj;
            payload["userEdit"] = true;
            archiveMsg["payload"] = payload;

            archiveTask.HandleAsync(archiveMsg, delegate(string resultJson)
            {
                JObject result;
                try { result = JObject.Parse(resultJson); }
                catch
                {
                    PostResp(bootForm, "import_resp", false, slot, "archive_task_failed");
                    return;
                }

                bool ok = result.Value<bool?>("success") ?? false;
                JObject outMsg = new JObject();
                outMsg["type"] = "bootstrap";
                outMsg["cmd"] = "import_resp";
                outMsg["slot"] = slot;
                outMsg["ok"] = ok;
                if (!ok)
                {
                    string err = result.Value<string>("error");
                    if (err != null) outMsg["error"] = err;
                }
                bootForm.PostToWeb(outMsg.ToString(Formatting.None));
            });
        }

        // ==================== Phase 2a: logs ====================

        private static void HandleLogs(JObject msg, BootstrapPanel bootForm)
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

        // ==================== Phase 2a: open_saves_dir ====================

        private static void HandleOpenSavesDir(ArchiveTask archiveTask)
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

        // ==================== Phase 2a: helpers ====================

        /// <summary>
        /// Phase D Step D11: Idle 守卫 + silent prewarm tear down 回调协议.
        ///   - Idle → 直接 onReady()
        ///   - silent prewarm (launchFlow.IsInSilentPrewarm) → Reset(onReady, "user_edit_" + cmd),
        ///     Reset 推到 Idle 后 flush pending queue 跑 onReady; 用户编辑不被 prewarm 挡住
        ///   - 其他非 Idle (用户已点 play, Embedding/WaitingGameReady/Ready) → reject not_idle
        /// </summary>
        private static void RequireIdleOrTearDown(string cmd, BootstrapPanel bootForm, GameLaunchFlow launchFlow, Action onReady)
        {
            if (launchFlow == null)
            {
                PostNotIdleResp(cmd, bootForm);
                return;
            }
            if (launchFlow.CurrentState == "Idle")
            {
                onReady();
                return;
            }
            if (launchFlow.IsInSilentPrewarm)
            {
                LogManager.Log("[BMH] silent teardown for cmd=" + cmd + " → Reset(user_edit_" + cmd + ")");
                launchFlow.Reset(onReady, "user_edit_" + cmd);
                return;
            }
            PostNotIdleResp(cmd, bootForm);
        }

        private static void PostNotIdleResp(string cmd, BootstrapPanel bootForm)
        {
            string outCmd;
            switch (cmd)
            {
                case "save":          outCmd = "save_resp";   break;
                case "reset":         outCmd = "reset_resp";  break;
                case "import_start":  outCmd = "import_resp"; break;
                case "import_commit": outCmd = "import_resp"; break;
                default:              outCmd = "error";       break;
            }
            PostResp(bootForm, outCmd, false, null, "not_idle");
        }

        /// <summary>
        /// 将 string 或 JObject 的 data 归一为 JObject（C# 5 兼容）。
        /// </summary>
        private static bool NormalizeDataToJObject(JToken raw, out JObject obj, out string error)
        {
            obj = null;
            error = null;
            if (raw == null) { error = "missing_data"; return false; }
            if (raw.Type == JTokenType.Object)
            {
                obj = (JObject)raw;
                return true;
            }
            if (raw.Type == JTokenType.String)
            {
                try
                {
                    obj = JObject.Parse((string)raw);
                    return true;
                }
                catch
                {
                    error = "schema_parse_failed";
                    return false;
                }
            }
            error = "schema_data_type_invalid";
            return false;
        }

        /// <summary>
        /// 通用响应：{type:"bootstrap", cmd, ok, slot?, error?}
        /// </summary>
        private static void PostResp(BootstrapPanel bootForm, string cmd, bool ok, string slot, string error)
        {
            JObject obj = new JObject();
            obj["type"] = "bootstrap";
            obj["cmd"] = cmd;
            obj["ok"] = ok;
            if (slot != null) obj["slot"] = slot;
            if (!ok && error != null) obj["error"] = error;
            bootForm.PostToWeb(obj.ToString(Formatting.None));
        }

        // ==================== Phase 1 existing helpers ====================

        private static JObject BuildArchivePayload(string op, string slot)
        {
            JObject msg = new JObject();
            msg["task"] = "archive";
            JObject payload = new JObject();
            payload["op"] = op;
            if (slot != null) payload["slot"] = slot;
            msg["payload"] = payload;
            return msg;
        }

        /// <summary>
        /// Phase 2a 通用 archive dispatch：透传 result 全部字段 + 映射 cmd。
        /// 用于 load / load_raw 等需要原样转发 data/tombstoned/corrupt 字段的场景。
        /// </summary>
        private static void DispatchArchiveGeneric(
            BootstrapPanel bootForm,
            ArchiveTask archiveTask,
            JObject archiveMsg,
            string outCmd)
        {
            archiveTask.HandleAsync(archiveMsg, delegate(string resultJson)
            {
                JObject result;
                try { result = JObject.Parse(resultJson); }
                catch
                {
                    PostResp(bootForm, outCmd, false, null, "archive_task_failed");
                    return;
                }

                bool ok = result.Value<bool?>("success") ?? false;
                JObject outMsg = new JObject();
                outMsg["type"] = "bootstrap";
                outMsg["cmd"] = outCmd;
                outMsg["ok"] = ok;

                // 透传所有非 success/task 字段
                foreach (var kv in result)
                {
                    if (kv.Key == "success" || kv.Key == "task") continue;
                    outMsg[kv.Key] = kv.Value;
                }

                bootForm.PostToWeb(outMsg.ToString(Formatting.None));
            });
        }

        /// <summary>Phase 1 DispatchArchive（list_resp / delete_resp 专用，保留 forwardSlots 逻辑）。
        /// Phase 2b: forwardSlots 路径 (list_resp) 附带 UserPrefs 的 lastPlayedSlot / introEnabled,
        /// 让欢迎页一次性拿到"上次槽位 + 片头偏好", 不需要额外 roundtrip.</summary>
        private static void DispatchArchive(
            BootstrapPanel bootForm,
            ArchiveTask archiveTask,
            JObject archiveMsg,
            string outCmd,
            bool forwardSlots,
            UserPrefs userPrefs = null)
        {
            archiveTask.HandleAsync(archiveMsg, delegate(string resultJson)
            {
                JObject result;
                try { result = JObject.Parse(resultJson); }
                catch
                {
                    PostError(bootForm, "archive_task_failed", "bad archive response");
                    return;
                }

                JObject outMsgObj = new JObject();
                outMsgObj["type"] = "bootstrap";
                outMsgObj["cmd"] = outCmd;
                if (forwardSlots)
                {
                    JToken slots = result["slots"];
                    outMsgObj["slots"] = slots != null ? slots : (JToken)new JArray();
                    // Phase 2b: 欢迎页偏好附带
                    if (userPrefs != null)
                    {
                        if (!string.IsNullOrEmpty(userPrefs.LastPlayedSlot))
                            outMsgObj["lastPlayedSlot"] = userPrefs.LastPlayedSlot;
                        outMsgObj["introEnabled"] = userPrefs.IntroEnabled;
                    }
                }
                else
                {
                    bool ok = result.Value<bool?>("success") ?? false;
                    outMsgObj["ok"] = ok;
                    string slot = result.Value<string>("slot");
                    if (slot != null) outMsgObj["slot"] = slot;
                    string err = result.Value<string>("error");
                    if (!ok && err != null) outMsgObj["error"] = err;
                }
                bootForm.PostToWeb(outMsgObj.ToString(Formatting.None));
            });
        }

        // ==================== Phase 2b: config_set ====================
        // 前端 send({cmd:'config_set', key:'introEnabled', value:true/false}) 等.
        // key 白名单:  introEnabled (bool), lastPlayedSlot (string)
        // 异常的 key 返回 config_set_resp {ok:false, error:"unknown_key"}.
        private static void HandleConfigSet(JObject msg, BootstrapPanel bootForm, UserPrefs userPrefs)
        {
            string key = msg.Value<string>("key");
            if (string.IsNullOrEmpty(key))
            {
                PostConfigSetResp(bootForm, null, false, "key_missing");
                return;
            }
            if (userPrefs == null)
            {
                PostConfigSetResp(bootForm, key, false, "userprefs_unavailable");
                return;
            }
            JToken val = msg["value"];
            try
            {
                switch (key)
                {
                    case "introEnabled":
                        userPrefs.IntroEnabled = val != null && val.Type == JTokenType.Boolean && val.Value<bool>();
                        break;
                    case "lastPlayedSlot":
                        userPrefs.LastPlayedSlot = val != null && val.Type == JTokenType.String ? val.Value<string>() : null;
                        break;
                    default:
                        PostConfigSetResp(bootForm, key, false, "unknown_key");
                        return;
                }
                userPrefs.Save();
                PostConfigSetResp(bootForm, key, true, null);
            }
            catch (Exception ex)
            {
                LogManager.Log("[BMH] config_set error key=" + key + " ex=" + ex.Message);
                PostConfigSetResp(bootForm, key, false, "exception");
            }
        }

        private static void PostConfigSetResp(BootstrapPanel bootForm, string key, bool ok, string err)
        {
            JObject obj = new JObject();
            obj["type"] = "bootstrap";
            obj["cmd"] = "config_set_resp";
            if (key != null) obj["key"] = key;
            obj["ok"] = ok;
            if (!ok && err != null) obj["error"] = err;
            bootForm.PostToWeb(obj.ToString(Formatting.None));
        }

        private static void PostError(BootstrapPanel bootForm, string code, string msg)
        {
            JObject obj = new JObject();
            obj["type"] = "bootstrap";
            obj["cmd"] = "error";
            obj["code"] = code;
            obj["msg"] = msg ?? "";
            bootForm.PostToWeb(obj.ToString(Formatting.None));
        }

        private static void PostPong(BootstrapPanel bootForm, JToken payload)
        {
            JObject obj = new JObject();
            obj["type"] = "bootstrap";
            obj["cmd"] = "pong";
            if (payload != null) obj["payload"] = payload;
            bootForm.PostToWeb(obj.ToString(Formatting.None));
        }
    }
}
