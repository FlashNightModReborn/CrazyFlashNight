// BMH 拆分：import_start / import_commit。
// 零行为改动，纯搬运。

using System;
using System.IO;
using System.Text;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using CF7Launcher.Tasks;

namespace CF7Launcher.Guardian.Handlers
{
    internal static class ImportCommandHandler
    {
        // ─────── import_start ───────
        // 同步流程：Idle 守卫 → OpenFileDialog → 读文件 → schema 早期校验 → PostToWeb import_target
        // Handle 在 UI 线程调用，ShowOpenFileDialog 直接同步弹出

        internal static void HandleImportStart(BootstrapPanel bootForm, ArchiveTask archiveTask, GameLaunchFlow launchFlow)
        {
            BootstrapCommandHelpers.RequireIdleOrTearDown("import_start", bootForm, launchFlow,
                delegate { HandleImportStartInternal(bootForm); });
        }

        private static void HandleImportStartInternal(BootstrapPanel bootForm)
        {
            string filePath = bootForm.ShowOpenFileDialog(
                "JSON 文件|*.json|所有文件|*.*",
                "导入存档");

            if (string.IsNullOrEmpty(filePath))
            {
                BootstrapCommandHelpers.PostResp(bootForm, "import_resp", false, null, "cancelled");
                return;
            }

            string fileContent;
            try
            {
                fileContent = File.ReadAllText(filePath, Encoding.UTF8);
            }
            catch (Exception ex)
            {
                BootstrapCommandHelpers.PostResp(bootForm, "import_resp", false, null, "read_failed: " + ex.Message);
                return;
            }

            // 早期 schema 校验（BMH 侧唯一保留的 schema 校验点）
            JObject dataObj;
            string normErr;
            if (!BootstrapCommandHelpers.NormalizeDataToJObject(new JValue(fileContent), out dataObj, out normErr))
            {
                BootstrapCommandHelpers.PostResp(bootForm, "import_resp", false, null, normErr);
                return;
            }

            string schemaErr;
            if (!ArchiveTask.ValidateSchemaStructure(dataObj, out schemaErr))
            {
                BootstrapCommandHelpers.PostResp(bootForm, "import_resp", false, null, schemaErr);
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

        // ─────── import_commit ───────
        // 职责同 save：Idle + NormalizeDataToJObject + 注入 userEdit:true → HandleShadow

        internal static void HandleImportCommit(JObject msg, BootstrapPanel bootForm, ArchiveTask archiveTask, GameLaunchFlow launchFlow)
        {
            BootstrapCommandHelpers.RequireIdleOrTearDown("import_commit", bootForm, launchFlow,
                delegate { HandleImportCommitInternal(msg, bootForm, archiveTask); });
        }

        private static void HandleImportCommitInternal(JObject msg, BootstrapPanel bootForm, ArchiveTask archiveTask)
        {
            string slot = msg.Value<string>("slot");
            if (string.IsNullOrEmpty(slot)) { BootstrapCommandHelpers.PostResp(bootForm, "import_resp", false, null, "slot_missing"); return; }

            JObject dataObj;
            string normErr;
            if (!BootstrapCommandHelpers.NormalizeDataToJObject(msg["data"], out dataObj, out normErr))
            {
                BootstrapCommandHelpers.PostResp(bootForm, "import_resp", false, slot, normErr);
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
                    BootstrapCommandHelpers.PostResp(bootForm, "import_resp", false, slot, "archive_task_failed");
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
    }
}
