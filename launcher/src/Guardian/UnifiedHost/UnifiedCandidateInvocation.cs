#nullable enable
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

namespace CF7Launcher.Guardian.UnifiedHost;

// Called only AFTER Program's existing runtime verifier. This selects an
// exclusive candidate startup; the legacy forms/input shield are never built.
internal static class UnifiedCandidateInvocation
{
    internal const string Flag = "--unified-input-candidate";
    internal static bool IsRequested(string[] args) => args.Any(arg =>
        arg.StartsWith(Flag, StringComparison.OrdinalIgnoreCase));

    internal static UnifiedHostOptions Parse(string[] args, bool verifiedIsolatedCandidate)
    {
        if (!verifiedIsolatedCandidate)
            throw new InvalidOperationException("Unified input requires a verified isolated runtime candidate.");
        var values = new Dictionary<string, string>(StringComparer.Ordinal);
        bool diagnostics = false;
        for (int i = 0; i < args.Length; i++) {
            string key = args[i];
            if (key == "--diagnostic-input") {
                if (diagnostics) throw new ArgumentException("Duplicate diagnostic flag.");
                diagnostics = true; continue;
            }
            if (key != Flag && key != "--project-root" && key != "--evidence")
                throw new ArgumentException("Unsupported unified candidate argument: " + key);
            if (++i >= args.Length || args[i].StartsWith("--", StringComparison.Ordinal)
                || !values.TryAdd(key, args[i])) throw new ArgumentException("Missing or duplicate candidate argument.");
        }
        if (values.Count != 3 || !values.TryGetValue(Flag, out string? profile) || profile != "c1")
            throw new ArgumentException("Only the implemented c1 scene profile is available.");
        string root = values["--project-root"], evidence = values["--evidence"];
        if (!Path.IsPathFullyQualified(root) || !Path.IsPathFullyQualified(evidence))
            throw new ArgumentException("Project and evidence paths must be absolute.");
        return new UnifiedHostOptions {
            ProjectRoot = Path.GetFullPath(root), Evidence = Path.GetFullPath(evidence),
            Mode = "--interactive", Scene = UnifiedSceneProfile.C1, DiagnosticCommands = diagnostics
        };
    }
}
