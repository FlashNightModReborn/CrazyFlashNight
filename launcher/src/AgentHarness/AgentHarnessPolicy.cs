using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using CF7Launcher.AgentRuntime.Integration;
using CF7Launcher.AgentRuntime.TrustedRunner;
using CF7Launcher.Bus;
using CF7Launcher.Guardian;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.AgentHarness
{
    /// <summary>
    /// Configuration and hard isolation policy for explicit `--agent-harness` sessions.
    /// Guarantees only `cf7_agent_*` slots are ever admitted and normal player play is untouched.
    /// </summary>
    internal sealed class AgentHarnessPolicy : IDisposable
    {
        private static readonly Regex AgentSlotRegex = new(
            @"^cf7_agent_[A-Za-z0-9_-]{1,64}$",
            RegexOptions.Compiled);

        private static readonly Regex PipeNameRegex = new(
            @"^[A-Za-z0-9._-]{4,80}$",
            RegexOptions.Compiled);

        internal string ProjectRoot { get; private set; }
        internal string StateRoot { get; private set; }
        internal string StateFilePath { get; private set; }
        internal string PipeName { get; private set; }
        internal string SessionEpoch { get; private set; }
        internal string AutoStartSlot { get; private set; }
        internal bool AllowHeadlessFallback { get; private set; }
        internal int HeadlessSceneFallbackDelayMs { get; private set; }
        internal bool IsolatedRuntimeCandidate { get; private set; }
        internal JObject RuntimeIdentity { get; private set; }

        internal string MutexName => "Local\\CF7ME_AgentHarness_"
            + LegacyHttpAccessPolicy.ComputeProjectRootHash(ProjectRoot);

        internal static bool IsValidAgentSlot(string slot)
        {
            return !string.IsNullOrEmpty(slot) && AgentSlotRegex.IsMatch(slot);
        }

        internal static AgentHarnessPolicy Parse(
            string[] args,
            string explicitProjectRoot,
            string fallbackProjectRoot,
            bool isolatedRuntimeCandidate)
        {
            if (args == null) return null;
            int idx = Array.IndexOf(args, "--agent-harness");
            if (idx < 0) return null;

            if (Array.LastIndexOf(args, "--agent-harness") != idx || idx + 1 >= args.Length)
                throw new InvalidOperationException("Exactly one --agent-harness <config.json> argument is required.");

            foreach (string arg in args)
            {
                if (arg.StartsWith("--", StringComparison.Ordinal)
                    && arg != "--agent-harness"
                    && arg != "--project-root")
                {
                    throw new InvalidOperationException("Agent Harness cannot be combined with mode flag: " + arg);
                }
            }

            string configPath = Path.GetFullPath(args[idx + 1]);
            if (!File.Exists(configPath) || new FileInfo(configPath).Length > 65536)
                throw new InvalidOperationException("Harness config missing or oversized: " + configPath);

            JObject cfg = JObject.Parse(File.ReadAllText(configPath, Encoding.UTF8));
            string schema = cfg.Value<string>("schema");
            if (!string.IsNullOrEmpty(schema) && schema != "cf7-agent-harness.v1")
                throw new InvalidOperationException("Unsupported harness schema: " + schema);

            string resolvedRoot = !string.IsNullOrWhiteSpace(explicitProjectRoot)
                ? Path.GetFullPath(explicitProjectRoot)
                : (!string.IsNullOrWhiteSpace(cfg.Value<string>("projectRoot"))
                    ? Path.GetFullPath(cfg.Value<string>("projectRoot"))
                    : Path.GetFullPath(fallbackProjectRoot));

            if (!Directory.Exists(resolvedRoot) || !File.Exists(Path.Combine(resolvedRoot, "crossdomain.xml")))
                throw new InvalidOperationException("Harness projectRoot is invalid: " + resolvedRoot);

            string pipeName = cfg.Value<string>("pipeName");
            if (string.IsNullOrWhiteSpace(pipeName) || !PipeNameRegex.IsMatch(pipeName))
                throw new InvalidOperationException("Invalid harness pipeName.");

            string sessionEpoch = cfg.Value<string>("sessionEpoch");
            if (string.IsNullOrWhiteSpace(sessionEpoch) || sessionEpoch.Length > 128)
                throw new InvalidOperationException("Invalid harness sessionEpoch.");

            string autoStartSlot = cfg.Value<string>("autoStartSlot") ?? cfg.Value<string>("slot");
            if (!string.IsNullOrEmpty(autoStartSlot) && !IsValidAgentSlot(autoStartSlot))
                throw new InvalidOperationException("Harness autoStartSlot must match ^cf7_agent_[A-Za-z0-9_-]{1,64}$.");

            string stateRoot = cfg.Value<string>("stateRoot");
            if (string.IsNullOrWhiteSpace(stateRoot))
                stateRoot = Path.Combine(resolvedRoot, "tmp", "agent-harness", "sessions", sessionEpoch);
            stateRoot = Path.GetFullPath(stateRoot);
            Directory.CreateDirectory(stateRoot);

            string stateFilePath = cfg.Value<string>("stateFilePath");
            if (string.IsNullOrWhiteSpace(stateFilePath))
                stateFilePath = Path.Combine(stateRoot, "harness-state.json");
            stateFilePath = Path.GetFullPath(stateFilePath);
            Directory.CreateDirectory(Path.GetDirectoryName(stateFilePath));

            bool allowHeadless = cfg.Value<bool?>("allowHeadlessFallback") ?? true;
            int headlessDelayMs = cfg.Value<int?>("headlessSceneFallbackDelayMs") ?? 750;
            if (headlessDelayMs < 100) headlessDelayMs = 100;
            if (headlessDelayMs > 10000) headlessDelayMs = 10000;

            JObject identityObj = BuildRuntimeIdentity(isolatedRuntimeCandidate);

            return new AgentHarnessPolicy
            {
                ProjectRoot = resolvedRoot,
                StateRoot = stateRoot,
                StateFilePath = stateFilePath,
                PipeName = pipeName,
                SessionEpoch = sessionEpoch,
                AutoStartSlot = string.IsNullOrEmpty(autoStartSlot) ? null : autoStartSlot,
                AllowHeadlessFallback = allowHeadless,
                HeadlessSceneFallbackDelayMs = headlessDelayMs,
                IsolatedRuntimeCandidate = isolatedRuntimeCandidate,
                RuntimeIdentity = identityObj
            };
        }

        private static JObject BuildRuntimeIdentity(bool isolatedRuntimeCandidate)
        {
            var identity = new JObject
            {
                ["runtimeMode"] = isolatedRuntimeCandidate ? "isolated_candidate" : "formal_runtime",
                ["processPath"] = Environment.ProcessPath ?? ""
            };
            try
            {
                var hostId = AgentRuntimeHostIdentity.Resolve(true);
                identity["coreSha256"] = hostId?.CoreSha256?.ToUpperInvariant() ?? "";
            }
            catch
            {
                identity["coreSha256"] = "";
            }
            try
            {
                var bundle = TrustedUnattendedRuntimeBundle.VerifySelectedProcess(verifyNativePolicy: false);
                if (bundle != null)
                {
                    identity["runtimeMode"] = bundle.RuntimeMode ?? identity.Value<string>("runtimeMode");
                    identity["buildIdentity"] = bundle.BuildIdentity?.ToUpperInvariant() ?? "";
                    identity["payloadClosure"] = bundle.PayloadClosure?.ToUpperInvariant() ?? "";
                }
            }
            catch
            {
                // Keep partial host identity if called in unit-test context without formal runtime bundle.
            }
            return identity;
        }

        internal void PublishStateFile(int httpPort, int socketPort)
        {
            using var proc = System.Diagnostics.Process.GetCurrentProcess();
            var doc = new JObject
            {
                ["schema"] = "cf7-agent-harness-state.v1",
                ["pid"] = proc.Id,
                ["processStartUtcTicks"] = proc.StartTime.ToUniversalTime().Ticks,
                ["pipeName"] = PipeName,
                ["sessionEpoch"] = SessionEpoch,
                ["projectRoot"] = ProjectRoot,
                ["stateRoot"] = StateRoot,
                ["httpPort"] = httpPort,
                ["socketPort"] = socketPort,
                ["allowHeadlessFallback"] = AllowHeadlessFallback,
                ["runtimeIdentity"] = RuntimeIdentity?.DeepClone()
            };
            string tmpPath = StateFilePath + ".tmp";
            File.WriteAllText(tmpPath, doc.ToString(Formatting.Indented), new UTF8Encoding(false));
            File.Move(tmpPath, StateFilePath, overwrite: true);
        }

        public void Dispose()
        {
            try
            {
                if (!string.IsNullOrEmpty(StateFilePath) && File.Exists(StateFilePath))
                    File.Delete(StateFilePath);
            }
            catch { }
        }
    }
}
