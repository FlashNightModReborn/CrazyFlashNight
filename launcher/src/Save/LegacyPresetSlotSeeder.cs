using System;
using Newtonsoft.Json.Linq;
using CF7Launcher.Guardian;

namespace CF7Launcher.Save
{
    public sealed class LegacyPresetSlotSeeder
    {
        private static readonly string[] PresetSlots = new string[]
        {
            "crazyflasher7_saves",
            "crazyflasher7_saves1",
            "crazyflasher7_saves2",
            "crazyflasher7_saves3",
            "crazyflasher7_saves4",
            "crazyflasher7_saves5",
            "crazyflasher7_saves6",
            "crazyflasher7_saves7",
            "crazyflasher7_saves8",
            "crazyflasher7_saves9"
        };

        private readonly IArchiveStateProbe _archive;
        private readonly SolResolver _resolver;
        private readonly string _swfPath;

        public LegacyPresetSlotSeeder(IArchiveStateProbe archive, SolResolver resolver, string swfPath)
        {
            _archive = archive;
            _resolver = resolver;
            _swfPath = swfPath;
        }

        public void SeedAllPresetSlotsIfMissing()
        {
            for (int i = 0; i < PresetSlots.Length; i++)
                SeedPresetSlotIfMissing(PresetSlots[i]);
        }

        public void SeedPresetSlotIfMissing(string slot)
        {
            if (!IsPresetSlot(slot) || _archive == null || _resolver == null || string.IsNullOrEmpty(_swfPath))
                return;

            if (_archive.IsTombstoned(slot))
            {
                LogManager.Log("[LegacyPresetSlotSeeder] skip slot=" + slot + " reason=tombstoned");
                return;
            }

            JObject shadow;
            string shadowErr;
            if (_archive.TryLoadShadowSync(slot, out shadow, out shadowErr))
            {
                LogManager.Log("[LegacyPresetSlotSeeder] skip slot=" + slot + " reason=shadow_present");
                return;
            }

            if (shadowErr != "not_found")
            {
                LogManager.Log("[LegacyPresetSlotSeeder] skip slot=" + slot
                    + " reason=shadow_unreadable err=" + (shadowErr ?? "unknown"));
                return;
            }

            SolResolveResult resolved = _resolver.Resolve(slot, _swfPath);
            LogManager.Log("[LegacyPresetSlotSeeder] probe slot=" + slot
                + " wire=" + resolved.WireDecision
                + " kind=" + resolved.Kind
                + " source=" + (resolved.Source ?? "n/a"));
        }

        public static bool IsPresetSlot(string slot)
        {
            if (string.IsNullOrEmpty(slot)) return false;
            for (int i = 0; i < PresetSlots.Length; i++)
            {
                if (string.Equals(PresetSlots[i], slot, StringComparison.Ordinal))
                    return true;
            }
            return false;
        }
    }
}
