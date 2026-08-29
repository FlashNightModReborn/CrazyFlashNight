// BMH 拆分：list / delete / load / load_raw。
// 零行为改动，纯搬运。

using Newtonsoft.Json.Linq;
using Newtonsoft.Json;
using CF7Launcher.Config;
using CF7Launcher.Tasks;
using CF7Launcher.Save;

namespace CF7Launcher.Guardian.Handlers
{
    internal static class ArchiveCommandHandler
    {
        /// <summary>Phase 2b: list_resp 额外附带 UserPrefs 里的 lastPlayedSlot / introEnabled。</summary>
        internal static void HandleList(BootstrapPanel bootForm, ArchiveTask archiveTask, SaveResolutionContext saveCtx, UserPrefs userPrefs)
        {
            PreheatPresetSlots(saveCtx);
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
            string slot;
            string slotError;
            if (!BootstrapCommandHelpers.TryReadDiscoveredSlotKey(
                    msg, "slot", archiveTask, out slot, out slotError))
            {
                BootstrapCommandHelpers.PostError(bootForm, slotError, "delete needs an exact slot key");
                return;
            }
            BootstrapCommandHelpers.DispatchArchive(
                bootForm,
                archiveTask,
                BootstrapCommandHelpers.BuildArchivePayload("delete", slot),
                "delete_resp",
                /*forwardSlots:*/ false);
        }

        internal static void HandleRename(
            JObject msg,
            BootstrapPanel bootForm,
            ArchiveTask archiveTask)
        {
            JObject response = BuildRenameResponse(msg, archiveTask);
            bootForm.PostToWeb(response.ToString(Formatting.None));
        }

        internal static JObject BuildRenameResponse(
            JObject msg,
            ArchiveTask archiveTask)
        {
            string slotKey;
            string error;
            if (!BootstrapCommandHelpers.TryReadDiscoveredSlotKey(
                    msg, "slotKey", archiveTask, out slotKey, out error))
            {
                return new JObject
                {
                    ["type"] = "bootstrap",
                    ["cmd"] = "rename_slot_resp",
                    ["ok"] = false,
                    ["error"] = error
                };
            }

            JToken displayNameToken = msg != null ? msg["displayName"] : null;
            string displayName = displayNameToken != null
                && displayNameToken.Type == JTokenType.String
                    ? displayNameToken.Value<string>()
                    : null;
            string normalized = null;
            bool restoreFollow = displayName != null
                && displayName.Trim().Length == 0;
            bool updated = restoreFollow
                ? archiveTask.SlotCatalog.TryRemoveDisplayName(
                    slotKey,
                    out error)
                : archiveTask.SlotCatalog.TrySetDisplayName(
                    slotKey,
                    displayName,
                    out normalized,
                    out error);
            if (!updated)
            {
                return new JObject
                {
                    ["type"] = "bootstrap",
                    ["cmd"] = "rename_slot_resp",
                    ["ok"] = false,
                    ["slotKey"] = slotKey,
                    ["error"] = error
                };
            }

            return new JObject
            {
                ["type"] = "bootstrap",
                ["cmd"] = "rename_slot_resp",
                ["ok"] = true,
                ["slotKey"] = slotKey,
                ["displayName"] = restoreFollow
                    ? JValue.CreateNull()
                    : (JToken)normalized,
                ["followsCharacterName"] = restoreFollow
            };
        }

        internal static void HandleLoad(JObject msg, BootstrapPanel bootForm, ArchiveTask archiveTask, SaveResolutionContext saveCtx)
        {
            string slot;
            string slotError;
            if (!BootstrapCommandHelpers.TryReadDiscoveredSlotKey(
                    msg, "slot", archiveTask, out slot, out slotError))
            {
                BootstrapCommandHelpers.PostError(bootForm, slotError, "load needs an exact slot key");
                return;
            }
            PreheatPresetSlot(saveCtx, slot);
            BootstrapCommandHelpers.DispatchArchiveGeneric(
                bootForm,
                archiveTask,
                BootstrapCommandHelpers.BuildArchivePayload("load", slot),
                "load_resp");
        }

        internal static void HandleLoadRaw(JObject msg, BootstrapPanel bootForm, ArchiveTask archiveTask, SaveResolutionContext saveCtx)
        {
            string slot;
            string slotError;
            if (!BootstrapCommandHelpers.TryReadDiscoveredSlotKey(
                    msg, "slot", archiveTask, out slot, out slotError))
            {
                BootstrapCommandHelpers.PostError(bootForm, slotError, "load_raw needs an exact slot key");
                return;
            }
            PreheatPresetSlot(saveCtx, slot);
            BootstrapCommandHelpers.DispatchArchiveGeneric(
                bootForm,
                archiveTask,
                BootstrapCommandHelpers.BuildArchivePayload("load_raw", slot),
                "load_raw_resp");
        }

        private static void PreheatPresetSlots(SaveResolutionContext saveCtx)
        {
            if (saveCtx == null || saveCtx.LegacySeeder == null)
                return;
            saveCtx.LegacySeeder.SeedAllPresetSlotsIfMissing();
        }

        private static void PreheatPresetSlot(SaveResolutionContext saveCtx, string slot)
        {
            if (saveCtx == null || saveCtx.LegacySeeder == null)
                return;
            saveCtx.LegacySeeder.SeedPresetSlotIfMissing(slot);
        }
    }
}
