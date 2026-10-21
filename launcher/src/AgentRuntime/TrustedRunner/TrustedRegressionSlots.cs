using System;

namespace CF7Launcher.AgentRuntime.TrustedRunner
{
    // A closed regression cohort. It never authorizes a player slot or formal runtime.
    internal static class TrustedRegressionSlots
    {
        internal static bool Contains(string slot) => slot is
            "cf7_agent_152_a28" or "cf7_agent_152_b29" or "cf7_agent_152_c68" or
            "cf7_agent_152_d69" or "cf7_agent_152_e69";

        internal static bool RequiresRuntimeEntry(string slot) => Contains(slot)
            || string.Equals(slot, "cf7_agent_a5_material_shop_run", StringComparison.Ordinal);
    }
}
