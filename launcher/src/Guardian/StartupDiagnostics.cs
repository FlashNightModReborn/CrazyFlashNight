using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

namespace CF7Launcher.Guardian
{
    /// <summary>
    /// Cross-boundary startup diagnostics written to logs/bootstrap.log.
    /// This intentionally records only lifecycle milestones and file probes, not
    /// the full launcher.log stream, so player-submitted logs stay small.
    /// </summary>
    public static class StartupDiagnostics
    {
        private static readonly object _lock = new object();
        private static readonly UTF8Encoding Utf8NoBom = new UTF8Encoding(false);
        private const int StartupIssueHistoryLimit = 20;
        private static string _projectRoot;
        private static string _logPath;
        private static string _startupExitPath;
        private static bool _enabled;

        public static string LogPath { get { return _logPath; } }

        public static void Init(string projectRoot)
        {
            if (string.IsNullOrEmpty(projectRoot))
                return;

            try
            {
                string fullRoot = Path.GetFullPath(projectRoot).TrimEnd('\\', '/');
                string logDir = Path.Combine(fullRoot, "logs");
                Directory.CreateDirectory(logDir);

                lock (_lock)
                {
                    _projectRoot = fullRoot;
                    _logPath = Path.Combine(logDir, "bootstrap.log");
                    _startupExitPath = Path.Combine(logDir, "startup-exit.jsonl");
                    _enabled = true;
                }
            }
            catch
            {
                lock (_lock)
                {
                    _enabled = false;
                    _projectRoot = null;
                    _logPath = null;
                    _startupExitPath = null;
                }
            }
        }

        public static void Mark(string stage)
        {
            Mark(stage, null);
        }

        public static void Mark(string stage, string detail)
        {
            Write("INFO", stage, detail);
        }

        public static void Warn(string stage, string detail)
        {
            Write("WARN", stage, detail);
        }

        public static void Exit(string reason)
        {
            Exit(reason, null);
        }

        public static void Exit(string reason, string detail)
        {
            Write("ERROR", "exit:" + reason, detail);
            RecordStartupIssue("exit", reason, detail, true);
        }

        public static void Failure(string reason)
        {
            Failure(reason, null);
        }

        public static void Failure(string reason, string detail)
        {
            Write("ERROR", "failure:" + reason, detail);
            RecordStartupIssue("failure", reason, detail, false);
        }

        public static void Exception(string stage, Exception ex)
        {
            if (ex == null)
            {
                Write("ERROR", stage, null);
                return;
            }
            Write("ERROR", stage, ex.GetType().FullName + ": " + ex.Message + "\n" + ex.StackTrace);
        }

        public static void LogCoreEnvironment(string exePath, string[] args, bool busOnly, bool forceWebViewFail)
        {
            StringBuilder sb = new StringBuilder();
            sb.Append("pid=").Append(Process.GetCurrentProcess().Id);
            sb.Append(" exe=").Append(exePath ?? "(null)");
            sb.Append(" baseDir=").Append(AppContext.BaseDirectory);
            sb.Append(" cwd=").Append(Environment.CurrentDirectory);
            sb.Append(" clr=").Append(RuntimeInformation.FrameworkDescription);
            sb.Append(" os=").Append(RuntimeInformation.OSDescription);
            sb.Append(" process64=").Append(Environment.Is64BitProcess);
            sb.Append(" os64=").Append(Environment.Is64BitOperatingSystem);
            sb.Append(" busOnly=").Append(busOnly);
            sb.Append(" forceWebViewFail=").Append(forceWebViewFail);
            sb.Append(" args=").Append(args == null ? 0 : args.Length);
            Write("INFO", "core.environment", sb.ToString());
        }

        public static bool ProbeFile(string label, string path, bool required)
        {
            if (string.IsNullOrEmpty(path))
            {
                Write(required ? "ERROR" : "WARN", "file_probe:" + label, "path is empty");
                return false;
            }

            try
            {
                FileInfo fi = new FileInfo(path);
                if (!fi.Exists)
                {
                    Write(required ? "ERROR" : "WARN", "file_probe:" + label, "missing path=" + path);
                    return false;
                }

                Write("INFO", "file_probe:" + label,
                    "ok size=" + fi.Length.ToString(CultureInfo.InvariantCulture)
                    + " mtime=" + fi.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture)
                    + " path=" + fi.FullName);
                return true;
            }
            catch (Exception ex)
            {
                Write(required ? "ERROR" : "WARN", "file_probe:" + label,
                    "exception " + ex.GetType().Name + ": " + ex.Message + " path=" + path);
                return false;
            }
        }

        public static bool ProbeDirectory(string label, string path, bool required)
        {
            if (string.IsNullOrEmpty(path))
            {
                Write(required ? "ERROR" : "WARN", "dir_probe:" + label, "path is empty");
                return false;
            }

            try
            {
                DirectoryInfo di = new DirectoryInfo(path);
                if (!di.Exists)
                {
                    Write(required ? "ERROR" : "WARN", "dir_probe:" + label, "missing path=" + path);
                    return false;
                }

                Write("INFO", "dir_probe:" + label, "ok path=" + di.FullName);
                return true;
            }
            catch (Exception ex)
            {
                Write(required ? "ERROR" : "WARN", "dir_probe:" + label,
                    "exception " + ex.GetType().Name + ": " + ex.Message + " path=" + path);
                return false;
            }
        }

        public static void ProbeCoreSidecars()
        {
            string baseDir = AppContext.BaseDirectory;
            ProbeFile("Core.dll", Path.Combine(baseDir, "CRAZYFLASHER7MercenaryEmpire.Core.dll"), true);
            ProbeFile("Core.deps", Path.Combine(baseDir, "CRAZYFLASHER7MercenaryEmpire.Core.deps.json"), true);
            ProbeFile("Core.runtimeconfig", Path.Combine(baseDir, "CRAZYFLASHER7MercenaryEmpire.Core.runtimeconfig.json"), true);
            ProbeFile("WebView2Loader", Path.Combine(baseDir, "WebView2Loader.dll"), true);
            ProbeFile("WebView2.Core", Path.Combine(baseDir, "Microsoft.Web.WebView2.Core.dll"), true);
            ProbeFile("ClearScriptV8.native", Path.Combine(baseDir, "ClearScriptV8.win-x64.dll"), true);
            ProbeFile("miniaudio", Path.Combine(baseDir, "miniaudio.dll"), true);
            ProbeFile("sol_parser", Path.Combine(baseDir, "sol_parser.dll"), true);
        }

        public static void ProbeProjectFiles(string projectRoot, string flashPlayerPath, string swfPath, bool requireGameFiles)
        {
            if (string.IsNullOrEmpty(projectRoot))
                return;

            ProbeDirectory("projectRoot", projectRoot, true);
            ProbeFile("config.toml", Path.Combine(projectRoot, "config.toml"), false);
            ProbeFile("crossdomain.xml", Path.Combine(projectRoot, "crossdomain.xml"), true);
            ProbeDirectory("launcher.web", Path.Combine(projectRoot, "launcher", "web"), !requireGameFiles ? false : true);
            ProbeFile("bootstrap.html", Path.Combine(projectRoot, "launcher", "web", "bootstrap.html"), requireGameFiles);
            ProbeFile("overlay.html", Path.Combine(projectRoot, "launcher", "web", "overlay.html"), false);
            ProbeFile("map_hud_data", Path.Combine(projectRoot, "launcher", "data", "map_hud_data.json"), false);
            ProbeFile("save_schema", Path.Combine(projectRoot, "launcher", "data", "save_schema.json"), false);

            if (requireGameFiles)
            {
                ProbeFile("FlashPlayer", flashPlayerPath, true);
                ProbeFile("GameSWF", swfPath, true);
            }
            else
            {
                ProbeFile("FlashPlayer", flashPlayerPath, false);
                ProbeFile("GameSWF", swfPath, false);
            }
        }

        private static void Write(string level, string stage, string detail)
        {
            string path;
            lock (_lock)
            {
                if (!_enabled || string.IsNullOrEmpty(_logPath))
                    return;
                path = _logPath;
            }

            string safeStage = Sanitize(stage);
            string safeDetail = Sanitize(detail);
            string line = "["
                + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss.fff", CultureInfo.InvariantCulture)
                + "] [core-startup] [" + (level ?? "INFO") + "] "
                + safeStage
                + (string.IsNullOrEmpty(safeDetail) ? "" : " " + safeDetail)
                + Environment.NewLine;

            lock (_lock)
            {
                try
                {
                    using (FileStream stream = new FileStream(path, FileMode.Append, FileAccess.Write,
                        FileShare.ReadWrite | FileShare.Delete))
                    using (StreamWriter writer = new StreamWriter(stream, Utf8NoBom))
                    {
                        writer.Write(line);
                    }
                }
                catch
                {
                    // Bootstrap may still hold the log during the 5s handoff window.
                    // Keep diagnostics enabled so later milestones can still land.
                }
            }
        }

        private static void RecordStartupIssue(string kind, string reason, string detail, bool terminal)
        {
            string path;
            string root;
            lock (_lock)
            {
                if (!_enabled || string.IsNullOrEmpty(_startupExitPath))
                    return;
                path = _startupExitPath;
                root = _projectRoot;
            }

            string line = "{"
                + "\"ts\":\"" + JsonEscape(DateTime.Now.ToString("yyyy-MM-ddTHH:mm:ss.fffK", CultureInfo.InvariantCulture)) + "\","
                + "\"pid\":" + Process.GetCurrentProcess().Id.ToString(CultureInfo.InvariantCulture) + ","
                + "\"kind\":\"" + JsonEscape(kind) + "\","
                + "\"reason\":\"" + JsonEscape(reason) + "\","
                + "\"terminal\":" + (terminal ? "true" : "false") + ","
                + "\"detail\":" + JsonStringOrNull(detail) + ","
                + "\"projectRoot\":" + JsonStringOrNull(root)
                + "}";

            lock (_lock)
            {
                try
                {
                    string[] existing = File.Exists(path) ? File.ReadAllLines(path, Encoding.UTF8) : new string[0];
                    int keep = Math.Min(existing.Length, StartupIssueHistoryLimit - 1);
                    using (StreamWriter writer = new StreamWriter(path, false, Utf8NoBom))
                    {
                        for (int i = existing.Length - keep; i < existing.Length; i++)
                        {
                            if (!string.IsNullOrWhiteSpace(existing[i]))
                                writer.WriteLine(existing[i]);
                        }
                        writer.WriteLine(line);
                    }
                }
                catch
                {
                    // Do not disable bootstrap.log if this optional summary file fails.
                }
            }
        }

        private static string Sanitize(string value)
        {
            if (string.IsNullOrEmpty(value)) return "";
            return value.Replace("\r", "\\r").Replace("\n", "\\n");
        }

        private static string JsonStringOrNull(string value)
        {
            if (value == null) return "null";
            return "\"" + JsonEscape(value) + "\"";
        }

        private static string JsonEscape(string value)
        {
            if (string.IsNullOrEmpty(value)) return "";
            StringBuilder sb = new StringBuilder(value.Length + 16);
            for (int i = 0; i < value.Length; i++)
            {
                char ch = value[i];
                switch (ch)
                {
                    case '\\': sb.Append("\\\\"); break;
                    case '"': sb.Append("\\\""); break;
                    case '\r': sb.Append("\\r"); break;
                    case '\n': sb.Append("\\n"); break;
                    case '\t': sb.Append("\\t"); break;
                    case '\b': sb.Append("\\b"); break;
                    case '\f': sb.Append("\\f"); break;
                    default:
                        if (ch < 32)
                        {
                            sb.Append("\\u");
                            sb.Append(((int)ch).ToString("x4", CultureInfo.InvariantCulture));
                        }
                        else
                        {
                            sb.Append(ch);
                        }
                        break;
                }
            }
            return sb.ToString();
        }
    }
}
