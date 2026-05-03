// P3b Phase 1g + Phase 2a: Bootstrap JS→C# 协议 handler
// Phase 1 入站 cmd: ready / list / start_game / delete / rebuild / retry / ping
// Phase 2a 入站 cmd: load / load_raw / save / reset / export / import_start / import_commit / logs
// Phase 1 出站 cmd: state / list_resp / delete_resp / error / pong
// Phase 2a 出站 cmd: load_resp / load_raw_resp / save_resp / reset_resp / export_resp / import_target / import_resp / logs_resp
// 详见 plan compressed-floating-nebula.md Phase 2a §4.3 协议表。
//
// 此文件是薄 dispatcher：按 cmd 分派到 Handlers/*.cs 的各 semantic handler。
// 业务逻辑全部外迁到 Handlers/ 子目录。

using System;
using Newtonsoft.Json.Linq;
using CF7Launcher.Tasks;
using CF7Launcher.Config;
using CF7Launcher.Save;
using CF7Launcher.Guardian.Handlers;

namespace CF7Launcher.Guardian
{
    public static class BootstrapMessageHandler
    {
        public static void Handle(
            string json,
            BootstrapPanel bootForm,
            ArchiveTask archiveTask,
            GameLaunchFlow launchFlow,
            SaveResolutionContext saveCtx,
            UserPrefs userPrefs,
            FontPackTask fontPackTask)
        {
            JObject msg;
            try { msg = JObject.Parse(json); }
            catch (Exception ex)
            {
                BootstrapCommandHelpers.PostError(bootForm, "bad_json", ex.Message);
                return;
            }

            string cmd = msg.Value<string>("cmd");
            if (string.IsNullOrEmpty(cmd))
            {
                BootstrapCommandHelpers.PostError(bootForm, "unknown_cmd", "missing cmd");
                return;
            }

            switch (cmd)
            {
                // ─────── Lifecycle ───────
                case "ready":
                    LifecycleCommandHandler.HandleReady(launchFlow);
                    return;
                case "ping":
                    LifecycleCommandHandler.HandlePing(bootForm, msg["payload"]);
                    return;
                case "cancel_launch":
                    LifecycleCommandHandler.HandleCancelLaunch(launchFlow);
                    return;

                // ─────── GameState ───────
                case "start_game":
                case "rebuild":
                    GameStateCommandHandler.HandleStartOrRebuild(msg, cmd, bootForm, launchFlow, userPrefs);
                    return;
                case "reveal_ok":
                    GameStateCommandHandler.HandleRevealOk(launchFlow);
                    return;
                case "retry":
                    GameStateCommandHandler.HandleRetry(bootForm, launchFlow);
                    return;

                // ─────── Archive query ───────
                case "list":
                    ArchiveCommandHandler.HandleList(bootForm, archiveTask, saveCtx, userPrefs);
                    return;
                case "delete":
                    ArchiveCommandHandler.HandleDelete(msg, bootForm, archiveTask);
                    return;
                case "load":
                    ArchiveCommandHandler.HandleLoad(msg, bootForm, archiveTask, saveCtx);
                    return;
                case "load_raw":
                    ArchiveCommandHandler.HandleLoadRaw(msg, bootForm, archiveTask, saveCtx);
                    return;

                // ─────── Data edit ───────
                case "save":
                    DataEditCommandHandler.HandleSave(msg, bootForm, archiveTask, launchFlow);
                    return;
                case "reset":
                    DataEditCommandHandler.HandleReset(msg, bootForm, archiveTask, launchFlow);
                    return;
                case "export":
                    DataEditCommandHandler.HandleExport(msg, bootForm, archiveTask);
                    return;

                // ─────── Import ───────
                case "import_start":
                    ImportCommandHandler.HandleImportStart(bootForm, archiveTask, launchFlow);
                    return;
                case "import_commit":
                    ImportCommandHandler.HandleImportCommit(msg, bootForm, archiveTask, launchFlow);
                    return;

                // ─────── Ui / diagnostics ───────
                case "logs":
                    UiCommandHandler.HandleLogs(msg, bootForm);
                    return;
                case "open_saves_dir":
                    UiCommandHandler.HandleOpenSavesDir(archiveTask);
                    return;
                case "diagnostic":
                    UiCommandHandler.HandleDiagnostic(msg, bootForm, saveCtx);
                    return;
                case "audio_preview":
                    UiCommandHandler.HandleAudioPreview(msg, bootForm);
                    return;

                // ─────── Config ───────
                case "config_set":
                    ConfigCommandHandler.HandleConfigSet(msg, bootForm, userPrefs);
                    return;

                // ─────── Font pack ───────
                case "fontpack_status":
                    FontPackCommandHandler.HandleStatus(bootForm, fontPackTask);
                    return;
                case "fontpack_install":
                    FontPackCommandHandler.HandleInstall(msg, bootForm, fontPackTask);
                    return;
                case "fontpack_cancel":
                    FontPackCommandHandler.HandleCancel(bootForm, fontPackTask);
                    return;

                // ─────── C2-β: 存档修复卡片 (Repairable saveDecision 路径) ───────
                case "repair_detect":
                    RepairCommandHandler.HandleDetect(msg, bootForm, archiveTask,
                        saveCtx != null ? saveCtx.ProjectRoot : null);
                    return;
                case "repair_apply_manual":
                    RepairCommandHandler.HandleApplyManual(msg, bootForm, archiveTask,
                        saveCtx != null ? saveCtx.ProjectRoot : null, launchFlow);
                    return;
                case "repair_force_continue":
                    RepairCommandHandler.HandleForceContinue(msg, bootForm, archiveTask,
                        saveCtx != null ? saveCtx.ProjectRoot : null, launchFlow);
                    return;

                default:
                    BootstrapCommandHelpers.PostError(bootForm, "unknown_cmd", cmd);
                    return;
            }
        }
    }
}
