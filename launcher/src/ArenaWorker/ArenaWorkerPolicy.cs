using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using CF7Launcher.AgentRuntime.TrustedRunner;
using CF7Launcher.Bus;
using CF7Launcher.Config;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.ArenaWorker
{
    // Explicit process composition options. These never change normal Guardian defaults.
    internal sealed class ArenaWorkerPolicy : IDisposable
    {
        internal string WorkerId { get; private set; }
        internal string SessionEpoch { get; private set; }
        internal string ProjectRoot { get; private set; }
        internal string StateRoot { get; private set; }
        internal string SaveRoot { get; private set; }
        internal string OutputRoot { get; private set; }
        internal string SwfOrigin { get; private set; }
        internal string Slot { get; private set; }
        internal static PerformancePolicy DefaultPerformance { get; } = new("performance", "fixed", 180);
        internal PerformancePolicy Performance { get; private set; } = DefaultPerformance;
        internal bool AllowFaultInjection { get; private set; }
        internal JObject RuntimeIdentity { get; private set; }
        internal string MutexName => "Local\\CF7ME_ArenaWorker_" + LegacyHttpAccessPolicy.ComputeProjectRootHash(ProjectRoot);
        private FileStream _claim;
        private string _ownerBody;
        private IDisposable _trustLease;

        internal static bool IsRequested(string[] args) => Array.IndexOf(args, "--arena-worker") >= 0;

        internal static bool RouteBootstrapMessage(string json, Action<string> forward)
        {
            if (string.IsNullOrEmpty(json) || json.Length > 65536) return false;
            JObject message;
            try { message = JObject.Parse(json); }
            catch { return false; }
            string command = message.Value<string>("cmd");
            // Bootstrap readiness is consumed here: its ordinary handler starts
            // prewarm. Only the fixed Worker control start may spawn Flash.
            if (command == "ready") return true;
            if (command != "reveal_ok" && command != "ping" && command != "log") return false;
            forward(json);
            return true;
        }

        internal static ArenaWorkerPolicy Parse(string[] args, string explicitRoot, bool isolatedCandidate)
        {
            if (!IsRequested(args)) return null;
            if (!isolatedCandidate || string.IsNullOrWhiteSpace(explicitRoot))
                throw new InvalidOperationException("Arena Worker requires an explicitly verified isolated candidate.");
            int index = Array.IndexOf(args, "--arena-worker");
            if (index + 1 >= args.Length || Array.LastIndexOf(args, "--arena-worker") != index)
                throw new InvalidOperationException("Exactly one --arena-worker configuration is required.");
            foreach (string arg in args)
                if (arg.StartsWith("--", StringComparison.Ordinal) && arg != "--arena-worker" && arg != "--project-root")
                    throw new InvalidOperationException("Arena Worker cannot combine other execution modes.");
            string configPath = CanonicalPath(args[index + 1]);
            if (!File.Exists(configPath) || new FileInfo(configPath).Length > 32768)
                throw new InvalidOperationException("Worker launch configuration is missing or too large.");
            JObject config = JObject.Parse(File.ReadAllText(configPath, Encoding.UTF8));
            if (config.Value<string>("schema") != "arena-worker.launch.v1")
                throw new InvalidOperationException("Unsupported Worker launch schema.");
            var result = FromConfiguration(config, explicitRoot);
            if (!SteamOwnershipCheck.IsDevRepository(result.ProjectRoot))
                throw new InvalidOperationException("Worker projectRoot must be its real Git worktree or clone.");
            CanonicalPath(Path.Combine(result.ProjectRoot, ".git"));
            VerifyRegisteredGitRoot(result.ProjectRoot);
            var bundle = TrustedUnattendedRuntimeBundle.VerifySelectedProcess(verifyNativePolicy: false);
            if (bundle.RuntimeMode != "isolated_candidate" || !SamePath(bundle.ProjectRoot, result.ProjectRoot))
                throw new InvalidOperationException("Worker resource root must match its verified candidate project root.");
            var hostIdentity = CF7Launcher.AgentRuntime.Integration.AgentRuntimeHostIdentity.Resolve(true);
            result.RuntimeIdentity = new JObject {
                ["runtimeMode"] = bundle.RuntimeMode, ["processPath"] = bundle.CorePath,
                ["coreSha256"] = hostIdentity.CoreSha256.ToUpperInvariant(), ["buildIdentity"] = bundle.BuildIdentity.ToUpperInvariant(),
                ["payloadClosure"] = bundle.PayloadClosure.ToUpperInvariant()
            };
            return result;
        }

        private static void VerifyRegisteredGitRoot(string root)
        {
            string top = RunGit(root, "rev-parse", "--show-toplevel").Trim();
            if (!SamePath(top, root)) throw new InvalidOperationException("Worker Git top-level mismatch.");
            string registered = RunGit(root, "worktree", "list", "--porcelain", "-z");
            foreach (string line in registered.Split('\0'))
                if (line.StartsWith("worktree ", StringComparison.Ordinal)
                    && SamePath(line.Substring(9).TrimEnd('\r'), root)) return;
            throw new InvalidOperationException("Worker project root is not a registered Git checkout.");
        }

        private static string RunGit(string root, params string[] arguments)
        {
            var info = new ProcessStartInfo("git") { UseShellExecute = false, CreateNoWindow = true,
                RedirectStandardOutput = true, RedirectStandardError = true, WorkingDirectory = root };
            foreach (string argument in arguments) info.ArgumentList.Add(argument);
            using Process process = Process.Start(info);
            var output = process.StandardOutput.ReadToEndAsync();
            var errors = process.StandardError.ReadToEndAsync();
            if (!process.WaitForExit(10000)) { process.Kill(); throw new InvalidOperationException("Worker Git authority check timed out."); }
            if (process.ExitCode != 0) throw new InvalidOperationException("Worker Git authority check failed.");
            return output.GetAwaiter().GetResult();
        }

        internal static ArenaWorkerPolicy FromConfiguration(JObject config, string explicitRoot)
        {
            var result = new ArenaWorkerPolicy {
                WorkerId = ArenaRunIdentity.ReadId(config, "workerId"),
                SessionEpoch = ArenaRunIdentity.ReadId(config, "sessionEpoch"),
                ProjectRoot = CanonicalPath(config.Value<string>("projectRoot")),
                StateRoot = CanonicalPath(config.Value<string>("stateRoot")),
                SaveRoot = CanonicalPath(config.Value<string>("saveRoot")),
                OutputRoot = CanonicalPath(config.Value<string>("outputRoot")),
                SwfOrigin = CanonicalPath(config.Value<string>("swfOrigin")),
                Slot = ArenaRunIdentity.ReadId(config, "slot")
            };
            if (config["performance"] != null)
            {
                if (!TryParseWorkerPerformance(config["performance"], out PerformancePolicy performance))
                    throw new InvalidOperationException("Worker performance setting is invalid.");
                result.Performance = performance;
            }
            if (config["allowFaultInjection"] != null)
            {
                if (config["allowFaultInjection"].Type != JTokenType.Boolean)
                    throw new InvalidOperationException("Worker fault opt-in must be boolean.");
                result.AllowFaultInjection = config.Value<bool>("allowFaultInjection");
            }
            if (!SamePath(result.ProjectRoot, explicitRoot)
                || !SamePath(result.SaveRoot, Path.Combine(result.ProjectRoot, "saves"))
                || !SamePath(result.OutputRoot, Path.Combine(result.ProjectRoot, "tmp", "arena-calibration"))
                || !SamePath(result.SwfOrigin, Path.Combine(result.ProjectRoot, "CRAZYFLASHER7MercenaryEmpire.swf"))
                || !IsUnder(result.StateRoot, Path.Combine(result.ProjectRoot, "tmp", "arena-worker"))
                || !result.Slot.StartsWith("cf7_agent_", StringComparison.Ordinal))
                throw new InvalidOperationException("Worker paths and fixed calibration slot must share one exact project root.");
            return result;
        }

        private static bool TryParseWorkerPerformance(JToken value, out PerformancePolicy policy)
        {
            if (PerformancePolicy.TryParse(value, out policy)) return true;
            // 180 is the existing performance renderer's lowest stage, exposed only to
            // the explicit Worker. Ordinary Guardian settings keep their own contract.
            if (value is JObject minimum && minimum.Count == 3
                && minimum["preset"]?.Type == JTokenType.String && minimum.Value<string>("preset") == "performance"
                && minimum["mode"]?.Type == JTokenType.String && minimum.Value<string>("mode") == "fixed"
                && minimum["maxRenderHeight"]?.Type == JTokenType.Integer && minimum.Value<long>("maxRenderHeight") == 180)
            {
                policy = DefaultPerformance;
                return true;
            }
            return false;
        }

        internal void Claim()
        {
            Directory.CreateDirectory(StateRoot);
            _claim = new FileStream(Path.Combine(StateRoot, "host.lock"), FileMode.CreateNew,
                FileAccess.ReadWrite, FileShare.Read);
            byte[] body = Encoding.UTF8.GetBytes(WorkerId + "\n" + SessionEpoch);
            _claim.Write(body); _claim.Flush(true);
            FixedWebViewRuntime.ConfigureWorkerCache(Path.Combine(StateRoot, "webview2-engine"));
        }

        internal void ValidateApplicationPaths(AppConfig config)
        {
            if (!SamePath(config.SwfPath, SwfOrigin) || !IsUnder(CanonicalPath(config.FlashPlayerPath), ProjectRoot))
                throw new InvalidOperationException("Worker Flash executable and SWF must belong to the selected resource root.");
        }

        internal bool AcquireTrust()
        {
            _trustLease = FlashTrustManager.CreateWorkerLease(ProjectRoot, WorkerId, SessionEpoch);
            return _trustLease != null;
        }

        internal void ConfigureFlashStart(ProcessStartInfo start)
        {
            start.WorkingDirectory = ProjectRoot;
            string origin = new Uri(SwfOrigin).AbsoluteUri;
            start.Arguments = "\"" + origin + "?cf7ArenaWorker=1&cf7ArenaWorkerId=" + Uri.EscapeDataString(WorkerId)
                + "&cf7ArenaSessionEpoch=" + Uri.EscapeDataString(SessionEpoch) + "\"";
            FlashStorageEnvironment.PrepareWorker(start, Path.Combine(StateRoot, "flash-temp"));
        }

        internal JObject PortsDocument(int httpPort, int socketPort)
        {
            return new JObject {
                ["httpPort"] = httpPort, ["socketPort"] = socketPort, ["pid"] = Environment.ProcessId,
                ["arenaWorker"] = true, ["workerId"] = WorkerId, ["sessionEpoch"] = SessionEpoch,
                ["swfOrigin"] = new Uri(SwfOrigin).AbsoluteUri
            };
        }

        internal void PublishOwner(int httpPort, int socketPort)
        {
            using Process self = Process.GetCurrentProcess();
            DateTime start = self.StartTime.ToUniversalTime();
            string roaming = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
            var owner = new JObject {
                ["schema"] = "arena-worker.owner.v1", ["executionMode"] = "arena_worker",
                ["workerId"] = WorkerId, ["sessionEpoch"] = SessionEpoch,
                ["projectRoot"] = ProjectRoot, ["stateRoot"] = StateRoot,
                ["saveRoot"] = SaveRoot, ["outputRoot"] = OutputRoot, ["swfOrigin"] = SwfOrigin,
                ["slot"] = Slot, ["performance"] = Performance.ToJson(), ["allowFaultInjection"] = AllowFaultInjection,
                ["hostPid"] = Environment.ProcessId,
                ["processStartUtcTicks"] = start.Ticks.ToString(CultureInfo.InvariantCulture),
                ["startTimeUtc"] = start.ToString("o"), ["processPath"] = Environment.ProcessPath,
                ["httpPort"] = httpPort, ["socketPort"] = socketPort,
                ["appData"] = roaming,
                ["sharedObjectsRoot"] = Path.Combine(roaming, "Macromedia", "Flash Player", "#SharedObjects"),
                ["runtimeIdentity"] = RuntimeIdentity.DeepClone()
            };
            string body = owner.ToString(Formatting.Indented);
            WriteNewAtomic(Path.Combine(StateRoot, "owner.json"), body);
            _ownerBody = body;
        }

        internal static void WriteNewAtomic(string path, string body)
        {
            string temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
            try
            {
                using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None,
                    4096, FileOptions.WriteThrough))
                {
                    byte[] bytes = new UTF8Encoding(false).GetBytes(body);
                    stream.Write(bytes); stream.Flush(true);
                }
                File.Move(temporary, path);
            }
            finally { if (File.Exists(temporary)) File.Delete(temporary); }
        }

        internal static JObject DescribeProcess(Process process)
        {
            var result = new JObject { ["observed"] = false, ["sampledAtUtc"] = DateTime.UtcNow.ToString("o") };
            try
            {
                if (process == null) { result["reason"] = "process_unavailable"; return result; }
                DateTime start = process.StartTime.ToUniversalTime();
                if (process.HasExited) { result["reason"] = "process_exited"; return result; }
                using Process sample = Process.GetProcessById(process.Id);
                if (sample.StartTime.ToUniversalTime() != start || sample.HasExited)
                { result["reason"] = "process_identity_changed"; return result; }
                string processPath = sample.MainModule?.FileName;
                if (string.IsNullOrWhiteSpace(processPath)) { result["reason"] = "process_path_unavailable"; return result; }
                result["pid"] = process.Id; result["processStartUtcTicks"] = start.Ticks.ToString(CultureInfo.InvariantCulture);
                result["startTimeUtc"] = start.ToString("o"); result["processPath"] = processPath;
                result["totalProcessorTimeMs"] = sample.TotalProcessorTime.TotalMilliseconds;
                result["workingSetBytes"] = sample.WorkingSet64;
                result["privateMemoryBytes"] = sample.PrivateMemorySize64;
                result["observed"] = true;
            }
            catch (Exception ex) { result["reason"] = "process_probe_" + ex.GetType().Name; }
            return result;
        }

        internal static string CanonicalPath(string value)
        {
            if (string.IsNullOrWhiteSpace(value) || !Path.IsPathFullyQualified(value))
                throw new InvalidOperationException("Worker paths must be explicit absolute paths.");
            string path = Path.TrimEndingDirectorySeparator(Path.GetFullPath(value));
            for (string current = path; !string.IsNullOrEmpty(current); current = Path.GetDirectoryName(current))
                if ((Directory.Exists(current) || File.Exists(current))
                    && (File.GetAttributes(current) & FileAttributes.ReparsePoint) != 0)
                    throw new InvalidOperationException("Worker paths cannot cross a reparse point.");
            return path;
        }

        internal static bool SamePath(string left, string right) => string.Equals(
            Path.TrimEndingDirectorySeparator(Path.GetFullPath(left)),
            Path.TrimEndingDirectorySeparator(Path.GetFullPath(right)), StringComparison.OrdinalIgnoreCase);
        internal static bool IsUnder(string path, string root) => Path.GetFullPath(path).StartsWith(
            Path.TrimEndingDirectorySeparator(Path.GetFullPath(root)) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase);

        public void Dispose()
        {
            _trustLease?.Dispose();
            string ownerPath = Path.Combine(StateRoot, "owner.json");
            try { if (_ownerBody != null && File.Exists(ownerPath) && File.ReadAllText(ownerPath, Encoding.UTF8) == _ownerBody) File.Delete(ownerPath); } catch { }
            if (_claim != null)
            {
                string lockPath = _claim.Name; _claim.Dispose(); _claim = null;
                try { if (File.ReadAllText(lockPath, Encoding.UTF8) == WorkerId + "\n" + SessionEpoch) File.Delete(lockPath); } catch { }
            }
        }
    }
}
