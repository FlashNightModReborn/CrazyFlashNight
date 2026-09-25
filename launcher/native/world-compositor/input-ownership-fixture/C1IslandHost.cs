using CF7Launcher.Guardian.UnifiedHost;

// C1 fixture entry point. The host implementation moved to Core:
// launcher/src/Guardian/UnifiedHost/UnifiedInputHost*.cs (namespace
// CF7Launcher.Guardian.UnifiedHost, class UnifiedInputHost). This wrapper
// keeps the exact C1 argument contract and explicitly enables the
// diagnostic command surface, which Core keeps closed by default.
internal static class C1IslandHost
{
    [STAThread] private static int Main(string[] args)
    {
        if (args.Length < 2 || args.Length > 3 || (args.Length == 3 && args[2] != "--independent-source" && args[2] != "--interactive")) return 2;
        return UnifiedInputHost.RunCandidate(new UnifiedHostOptions {
            ProjectRoot = Path.GetFullPath(args[0]),
            Evidence = Path.GetFullPath(args[1]),
            Mode = args.Length == 3 ? args[2] : "",
            DiagnosticCommands = true });
    }
}
