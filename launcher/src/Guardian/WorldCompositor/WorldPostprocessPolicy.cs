namespace CF7Launcher.Guardian.WorldCompositor
{
    // Conservative first candidate. Native uses the actual source/output ratio
    // for a bounded extra correction; these values are CAS controls, not the
    // legacy unsharp-mask coefficient. Artistic acceptance remains separate.
    internal static class WorldPostprocessPolicy
    {
        internal static float CasStrength(string quality) => quality switch {
            "HIGH" or "BEST" => .10f,
            "MEDIUM" => .25f,
            "LOW" => .27f,
            _ => .10f
        };
        internal static int CasStage(string quality) => quality=="LOW"?1:0;
    }
}
