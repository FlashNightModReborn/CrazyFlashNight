using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Text;
using CF7Launcher.Guardian;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Diagnostic
{
    // 退出只固定本轮文件；压缩交给短期隐藏进程，不占用 Guardian 的 8 秒退出预算。
    internal static class FocusExitCollector
    {
        internal const string OwnerVariable = "CF7_FOCUS_EXIT_COLLECTOR";

        internal static bool HasLiveOwner(string owner)
        {
            string[] parts = (owner ?? "").Split(':');
            if (parts.Length != 2 || !int.TryParse(parts[0], out int pid) || pid <= 0 ||
                !long.TryParse(parts[1], NumberStyles.None, CultureInfo.InvariantCulture, out long started)) return false;
            try
            {
                using (Process process = Process.GetProcessById(pid))
                    return !process.HasExited && process.StartTime.ToUniversalTime().Ticks == started;
            }
            catch { return false; }
        }

        internal static void Start(string projectRoot, string session, Action<ProcessStartInfo> start = null)
        {
            if (HasLiveOwner(Environment.GetEnvironmentVariable(OwnerVariable)))
            {
                LogManager.Log("[FocusRecording] exit collection owned by diagnostic launcher");
                return;
            }
            string runDirectory = null;
            try
            {
                string root = Path.GetFullPath(projectRoot);
                string script = Path.Combine(root, "tools", "run-focus-diagnostic.ps1");
                if (!File.Exists(script)) throw new FileNotFoundException("Focus collector script missing", script);
                runDirectory = Path.Combine(root, "logs", "focus-diagnostic",
                    "auto-" + DateTime.Now.ToString("yyyyMMdd-HHmmss-fff", CultureInfo.InvariantCulture) + "-" + session);
                Directory.CreateDirectory(runDirectory);
                var warnings = new JArray();
                void Copy(string relative)
                {
                    string source = Path.Combine(root, relative);
                    if (!File.Exists(source)) return;
                    try
                    {
                        using (var input = new FileStream(source, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
                        using (var output = new FileStream(Path.Combine(runDirectory, Path.GetFileName(source)), FileMode.CreateNew))
                            input.CopyTo(output);
                    }
                    catch (Exception ex) { warnings.Add(relative + ": " + ex.Message); }
                }
                foreach (string name in RollingFocusLog.Names) Copy(Path.Combine("logs", "focus-trace", name));
                foreach (string relative in new[] { "logs/launcher.log.1", "logs/launcher.log", "logs/bootstrap.log",
                    "runtime/cf7-runtime-manifest.tsv", "config/build/runtime-release-consensus.json", "config.toml" }) Copy(relative);
                File.WriteAllText(Path.Combine(runDirectory, "auto-collection.json"), new JObject {
                    ["session"] = session, ["collectionTrigger"] = "game_exit",
                    ["requestedAtUtc"] = DateTime.UtcNow.ToString("O"), ["collectionWarnings"] = warnings
                }.ToString(), new UTF8Encoding(false));

                string powershellDirectory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),
                    "WindowsPowerShell", "v1.0");
                var info = new ProcessStartInfo(Path.Combine(powershellDirectory, "powershell.exe")) {
                    UseShellExecute = false, CreateNoWindow = true, WindowStyle = ProcessWindowStyle.Hidden,
                    WorkingDirectory = root
                };
                foreach (string argument in new[] { "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
                    "-WindowStyle", "Hidden", "-File", script, "-CollectOnly", "-ProjectRoot", root,
                    "-PreparedRunDir", runDirectory }) info.ArgumentList.Add(argument);
                info.Environment["PSModulePath"] = Path.Combine(powershellDirectory, "Modules");
                if (start != null) start(info);
                else
                {
                    using (Process collector = Process.Start(info))
                        if (collector == null) throw new InvalidOperationException("Focus collector did not start");
                }
                LogManager.Log("[FocusRecording] exit collection queued: " + runDirectory + ".zip");
            }
            catch (Exception ex)
            {
                // 保留已固定的现场，失败绝不能拦截退出或冒报 ZIP 已完成。
                try { if (runDirectory != null) File.WriteAllText(Path.Combine(runDirectory, "collection-error.txt"), ex.ToString()); } catch { }
                LogManager.Log("[FocusRecording] exit collection failed: " + ex.Message);
            }
        }
    }
}
