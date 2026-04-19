// BMH 拆分：list / delete / load / load_raw。
// 零行为改动，纯搬运。

using Newtonsoft.Json.Linq;
using CF7Launcher.Config;
using CF7Launcher.Tasks;

namespace CF7Launcher.Guardian.Handlers
{
    internal static class ArchiveCommandHandler
    {
        /// <summary>Phase 2b: list_resp 额外附带 UserPrefs 里的 lastPlayedSlot / introEnabled。</summary>
        internal static void HandleList(BootstrapPanel bootForm, ArchiveTask archiveTask, UserPrefs userPrefs)
        {
            BootstrapCommandHelpers.DispatchArchive(
                bootForm,
                archiveTask,
                BootstrapCommandHelpers.BuildArchivePayload("list", null),
                "list_resp",
                /*forwardSlots:*/ true,
                userPrefs);
        }

        internal static void HandleDelete(JObject msg, BootstrapPanel bootForm, ArchiveTask archiveTask)
        {
            string slot = msg.Value<string>("slot");
            if (string.IsNullOrEmpty(slot))
            {
                BootstrapCommandHelpers.PostError(bootForm, "slot_missing", "delete needs slot");
                return;
            }
            BootstrapCommandHelpers.DispatchArchive(
                bootForm,
                archiveTask,
                BootstrapCommandHelpers.BuildArchivePayload("delete", slot),
                "delete_resp",
                /*forwardSlots:*/ false);
        }

        internal static void HandleLoad(JObject msg, BootstrapPanel bootForm, ArchiveTask archiveTask)
        {
            string slot = msg.Value<string>("slot");
            if (string.IsNullOrEmpty(slot))
            {
                BootstrapCommandHelpers.PostError(bootForm, "slot_missing", "load needs slot");
                return;
            }
            BootstrapCommandHelpers.DispatchArchiveGeneric(
                bootForm,
                archiveTask,
                BootstrapCommandHelpers.BuildArchivePayload("load", slot),
                "load_resp");
        }

        internal static void HandleLoadRaw(JObject msg, BootstrapPanel bootForm, ArchiveTask archiveTask)
        {
            string slot = msg.Value<string>("slot");
            if (string.IsNullOrEmpty(slot))
            {
                BootstrapCommandHelpers.PostError(bootForm, "slot_missing", "load_raw needs slot");
                return;
            }
            BootstrapCommandHelpers.DispatchArchiveGeneric(
                bootForm,
                archiveTask,
                BootstrapCommandHelpers.BuildArchivePayload("load_raw", slot),
                "load_raw_resp");
        }
    }
}
