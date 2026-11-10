using System;

namespace CF7Launcher.AgentRuntime.TrustedRunner
{
    // A closed test cohort, shared by qualified candidate and formal acceptance.
    // Deployment mode does not authorize a different slot or change business rules.
    internal static class TrustedRegressionSlots
    {
        internal static bool Contains(string slot) => slot is
            "cf7_agent_152_a28" or "cf7_agent_152_b29" or "cf7_agent_152_c68" or
            "cf7_agent_152_d69" or "cf7_agent_152_e69" || IsQualification(slot);

        internal static bool IsQualification(string slot) => slot is
            "cf7_agent_review1110" or "cf7_agent_i2051110";

        // Only the dedicated soak slot has a long window. Ordinary regression,
        // A5, acquisition and individual input deadlines remain unchanged.
        internal static TimeSpan MaximumLifetime(string slot) =>
            TimeSpan.FromMinutes(slot == "cf7_agent_i2051110" ? 80 : 10);

        internal static bool RequiresRuntimeEntry(string slot) => Contains(slot)
            || string.Equals(slot, "cf7_agent_a5_material_shop_run", StringComparison.Ordinal);
    }
}
