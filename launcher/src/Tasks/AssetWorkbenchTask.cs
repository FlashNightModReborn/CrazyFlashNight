using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Tasks
{
    /// <summary>物品素材工作台的固定命令适配器；导出、校验和事务均归 CLI 内核。</summary>
    public sealed class AssetWorkbenchTask
    {
        public const string Panel = "asset-workbench";
        public const string Domain = "asset_workbench";
        private readonly string _root;
        public AssetWorkbenchTask(string root) { _root = Path.GetFullPath(root); }

        public static bool TryReadRequest(string json, string activePanel, string activeInstance,
            out JObject message, out JObject request)
        {
            message = null;
            request = null;
            try
            {
                if (json == null || json.Length > 16384) return false;
                var value = JObject.Parse(json, new JsonLoadSettings { DuplicatePropertyNameHandling = DuplicatePropertyNameHandling.Error });
                string[] allowed = { "type", "panel", "domain", "cmd", "callId", "panelInstanceId", "payload" };
                if (value.Properties().Any(p => !allowed.Contains(p.Name))) return false;
                foreach (string key in allowed.Where(k => k != "payload"))
                    if (value[key]?.Type != JTokenType.String || value.Value<string>(key).Length > 200) return false;
                if (value.Value<string>("type") != "panel" || value.Value<string>("panel") != Panel
                    || value.Value<string>("domain") != Domain || activePanel != Panel
                    || string.IsNullOrEmpty(activeInstance) || value.Value<string>("panelInstanceId") != activeInstance
                    || string.IsNullOrEmpty(value.Value<string>("callId"))) return false;
                var payload = value["payload"] as JObject;
                if (payload == null) return false;
                string cmd = value.Value<string>("cmd");
                string[] fields;
                switch (cmd)
                {
                    case "catalog": case "rescan": case "close": fields = Array.Empty<string>(); break;
                    case "start": fields = new[] { "item", "kind", "jobId" }; break;
                    case "status": case "apply": case "undo": case "cancel": fields = new[] { "jobId" }; break;
                    default: return false;
                }
                if (payload.Properties().Count() != fields.Length || fields.Any(k => payload[k]?.Type != JTokenType.String)
                    || payload.Properties().Any(p => !fields.Contains(p.Name))) return false;
                if (fields.Contains("jobId") && !System.Text.RegularExpressions.Regex.IsMatch(payload.Value<string>("jobId"), "\\A[a-f0-9]{32}\\z")) return false;
                if (cmd == "start" && (string.IsNullOrWhiteSpace(payload.Value<string>("item"))
                    || payload.Value<string>("item").Length > 160
                    || !new[] { "all", "icons", "dressup" }.Contains(payload.Value<string>("kind")))) return false;
                message = value;
                request = (JObject)payload.DeepClone();
                request["op"] = cmd;
                return true;
            }
            catch (JsonException) { return false; }
        }

        private static string FindPython()
        {
            string local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            string home = Path.Combine(local, "Programs", "Python");
            if (Directory.Exists(home))
                foreach (string directory in Directory.GetDirectories(home, "Python*").OrderByDescending(p => p))
                {
                    string candidate = Path.Combine(directory, "python.exe");
                    if (File.Exists(candidate)) return candidate;
                }
            foreach (string directory in (Environment.GetEnvironmentVariable("PATH") ?? "").Split(Path.PathSeparator))
            {
                if (directory.IndexOf("WindowsApps", StringComparison.OrdinalIgnoreCase) >= 0) continue;
                string candidate = Path.Combine(directory.Trim('"'), "python.exe");
                if (Path.IsPathFullyQualified(candidate) && File.Exists(candidate)) return candidate;
            }
            throw new InvalidOperationException("未找到 Python。请安装 Python 3.11 或更新版本，并安装 tools/asset-workbench/requirements.txt 中的依赖。");
        }

        public async Task<JObject> ExecuteAsync(JObject request)
        {
            try
            {
                var info = new ProcessStartInfo(FindPython())
                {
                    WorkingDirectory = _root, UseShellExecute = false, CreateNoWindow = true,
                    RedirectStandardInput = true, RedirectStandardOutput = true, RedirectStandardError = true,
                    StandardInputEncoding = new UTF8Encoding(false), StandardOutputEncoding = Encoding.UTF8,
                    StandardErrorEncoding = Encoding.UTF8
                };
                foreach (string arg in new[] { "-X", "utf8", "-B", Path.Combine(_root, "tools", "asset-workbench", "cli.py"), "api" })
                    info.ArgumentList.Add(arg);
                using var process = Process.Start(info);
                var output = process.StandardOutput.ReadToEndAsync();
                var errors = process.StandardError.ReadToEndAsync();
                await process.StandardInput.WriteAsync(request.ToString(Formatting.None));
                process.StandardInput.Close();
                using var timeout = new CancellationTokenSource(TimeSpan.FromMinutes(2));
                try { await process.WaitForExitAsync(timeout.Token); }
                catch (OperationCanceledException)
                {
                    // 只终止本次短请求；已提交的导出 worker 由内核持久任务管理。
                    if (!process.HasExited) process.Kill(false);
                    return new JObject { ["success"] = false, ["error"] = "请求等待超时，请刷新任务状态后继续。" };
                }
                string text = await output;
                string error = await errors;
                if (text.Length > 12000000) throw new InvalidOperationException("素材目录响应过大。");
                if (string.IsNullOrWhiteSpace(text)) throw new InvalidOperationException("素材内核未返回结果：" + error.Substring(0, Math.Min(1200, error.Length)));
                return JObject.Parse(text);
            }
            catch (Exception error)
            {
                return new JObject { ["success"] = false, ["error"] = error.Message };
            }
        }
    }
}
