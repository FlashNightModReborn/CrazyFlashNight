// BMH 拆分：save / reset / export。
// 所有三条命令都走 RequireIdleOrTearDown 守卫；save / import_commit 共享 shadow payload
// 构造但 import_commit 归于 Import handler，这里只处理 save。零行为改动。

using System;
using System.IO;
using System.Text;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using CF7Launcher.Tasks;

namespace CF7Launcher.Guardian.Handlers
{
    internal static class DataEditCommandHandler
    {
        // ─────── save ───────
        // 职责：Idle 守卫 + NormalizeDataToJObject + 注入 userEdit:true → HandleShadow 内做 schema/tombstone/lastSaved

        internal static void HandleSave(JObject msg, BootstrapPanel bootForm, ArchiveTask archiveTask, GameLaunchFlow launchFlow)
        {
            BootstrapCommandHelpers.RequireIdleOrTearDown("save", bootForm, launchFlow,
                delegate { HandleSaveInternal(msg, bootForm, archiveTask); });
        }

        private static void HandleSaveInternal(JObject msg, BootstrapPanel bootForm, ArchiveTask archiveTask)
        {
            string slot = msg.Value<string>("slot");
            if (string.IsNullOrEmpty(slot)) { BootstrapCommandHelpers.PostResp(bootForm, "save_resp", false, null, "slot_missing"); return; }

            JObject dataObj;
            string normErr;
            if (!BootstrapCommandHelpers.NormalizeDataToJObject(msg["data"], out dataObj, out normErr))
            {
                BootstrapCommandHelpers.PostResp(bootForm, "save_resp", false, slot, normErr);
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
                    BootstrapCommandHelpers.PostResp(bootForm, "save_resp", false, slot, "archive_task_failed");
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

        // ─────── reset ───────

        internal static void HandleReset(JObject msg, BootstrapPanel bootForm, ArchiveTask archiveTask, GameLaunchFlow launchFlow)
        {
            BootstrapCommandHelpers.RequireIdleOrTearDown("reset", bootForm, launchFlow,
                delegate { HandleResetInternal(msg, bootForm, archiveTask); });
        }

        private static void HandleResetInternal(JObject msg, BootstrapPanel bootForm, ArchiveTask archiveTask)
        {
            string slot = msg.Value<string>("slot");
            if (string.IsNullOrEmpty(slot)) { BootstrapCommandHelpers.PostResp(bootForm, "reset_resp", false, null, "slot_missing"); return; }

            bool confirm = msg.Value<bool?>("confirm") ?? false;
            if (!confirm) { BootstrapCommandHelpers.PostResp(bootForm, "reset_resp", false, slot, "confirm_required"); return; }

            JObject archiveMsg = BootstrapCommandHelpers.BuildArchivePayload("reset", slot);
            archiveTask.HandleAsync(archiveMsg, delegate(string resultJson)
            {
                JObject result;
                try { result = JObject.Parse(resultJson); }
                catch
                {
                    BootstrapCommandHelpers.PostResp(bootForm, "reset_resp", false, slot, "archive_task_failed");
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

        // ─────── export ───────
        // JS 侧按 slotMeta 决定 forceRaw: corrupt/inconsistent → true

        internal static void HandleExport(JObject msg, BootstrapPanel bootForm, ArchiveTask archiveTask)
        {
            string slot = msg.Value<string>("slot");
            if (string.IsNullOrEmpty(slot)) { BootstrapCommandHelpers.PostResp(bootForm, "export_resp", false, null, "slot_missing"); return; }

            bool forceRaw = msg.Value<bool?>("forceRaw") ?? false;
            string defaultName = msg.Value<string>("defaultName");
            string op = forceRaw ? "load_raw" : "load";

            JObject archiveMsg = BootstrapCommandHelpers.BuildArchivePayload(op, slot);
            archiveTask.HandleAsync(archiveMsg, delegate(string resultJson)
            {
                JObject result;
                try { result = JObject.Parse(resultJson); }
                catch
                {
                    BootstrapCommandHelpers.PostResp(bootForm, "export_resp", false, slot, "archive_task_failed");
                    return;
                }

                bool loadOk = result.Value<bool?>("success") ?? false;
                if (!loadOk)
                {
                    string err = result.Value<string>("error");
                    BootstrapCommandHelpers.PostResp(bootForm, "export_resp", false, slot, err ?? "load_failed");
                    return;
                }

                string data = result.Value<string>("data");
                if (string.IsNullOrEmpty(data))
                {
                    BootstrapCommandHelpers.PostResp(bootForm, "export_resp", false, slot, "empty_data");
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
                            BootstrapCommandHelpers.PostResp(bootForm, "export_resp", false, slot, "cancelled");
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
                            BootstrapCommandHelpers.PostResp(bootForm, "export_resp", false, slot, "write_failed: " + ex.Message);
                        }
                    }));
                }
                catch (Exception ex)
                {
                    BootstrapCommandHelpers.PostResp(bootForm, "export_resp", false, slot, "invoke_failed: " + ex.Message);
                }
            });
        }
    }
}
