// CF7:ME WebView 故障记录器
//
// 把 WebView2 进程故障 / 浏览器进程退出 / 恢复尝试追加到有界 JSONL：
//   logs/webview-failures.jsonl
// 消费方：Diagnostic/WebViewFailureReportCollector.cs（worker05）按行读取，
// 期望字段：atUtc / session / kind / reason / failureReportFolderPath(可空) /
//   exitCode / browserVersion / documentGeneration / hostLifecycleGeneration。
//
// 约束：
// - 任何路径都不允许抛出（WebView 事件处理里绝不能因诊断写盘崩宿主）。
// - 文件超过 MaxFileBytes 时单份轮转到 .1，永远保持 collector 尾读语义。
// - 所有文本字段截断到 MaxFieldChars，防止单条记录失控。
// - session 优先取 FocusTrace.Session（与诊断包/焦点录制同会话），
//   未启用时用进程级 GUID，保证行内字段永远存在。

using System;
using System.IO;
using System.Text;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Diagnostic
{
    internal static class WebViewFailureRecorder
    {
        internal const int SchemaVersion = 1;
        internal const long MaxFileBytes = 512 * 1024;
        internal const int MaxFieldChars = 512;
        internal const string FileName = "webview-failures.jsonl";

        private static readonly object Gate = new object();
        private static string _logPath;
        private static string _processSession;

        /// <summary>一条有界故障/恢复记录；null 字段序列化时省略。</summary>
        internal sealed class Entry
        {
            internal string Kind;                    // 例 "render_process_exited"
            internal string Reason;                  // 例 "crashed" / "failed"
            internal int? ExitCode;
            internal string BrowserVersion;
            internal long? BrowserProcessId;
            internal int? DocumentGeneration;
            internal int? HostLifecycleGeneration;
            internal long? HostHandle;
            internal string Classification;          // main_document | ancillary | hung | browser_exit
            internal string FailureReportFolderPath;
            internal string ProcessDescription;
            internal string FailureSourceModulePath;
            internal int? FrameCount;
            internal string Detail;
        }

        /// <summary>在 launcher 启动早期配置输出路径；重复调用以最后一次为准。</summary>
        internal static void Configure(string projectRoot)
        {
            try
            {
                string path = null;
                if (!string.IsNullOrEmpty(projectRoot))
                {
                    path = Path.Combine(
                        Path.GetFullPath(projectRoot), "logs", FileName);
                }
                lock (Gate) { _logPath = path; }
            }
            catch { }
        }

        /// <summary>当前输出路径（未配置时 null）。仅供诊断/测试观察。</summary>
        internal static string ConfiguredPath
        {
            get { lock (Gate) { return _logPath; } }
        }

        /// <summary>清空配置与进程会话缓存（测试用）。</summary>
        internal static void ResetForTests()
        {
            lock (Gate)
            {
                _logPath = null;
                _processSession = null;
            }
        }

        private static string CurrentSession
        {
            get
            {
                try
                {
                    if (FocusTrace.Enabled
                        && !string.IsNullOrEmpty(FocusTrace.Session))
                        return FocusTrace.Session;
                }
                catch { }
                lock (Gate)
                {
                    if (_processSession == null)
                        _processSession = Guid.NewGuid().ToString("N");
                    return _processSession;
                }
            }
        }

        /// <summary>
        /// 组装并追加一条记录到已配置日志。未配置路径或任何 IO 失败都静默返回 false，
        /// 绝不影响宿主流程。
        /// </summary>
        internal static bool Record(Entry entry)
        {
            string path;
            lock (Gate) { path = _logPath; }
            if (string.IsNullOrEmpty(path) || entry == null) return false;
            try
            {
                JObject json = BuildJson(entry);
                if (json == null) return false;
                return AppendLineBounded(path, json.ToString(Newtonsoft.Json.Formatting.None));
            }
            catch { return false; }
        }

        /// <summary>把 Entry 转成 JSON object（null 字段省略）。纯函数，可直接测试。</summary>
        internal static JObject BuildJson(Entry entry)
        {
            if (entry == null || string.IsNullOrEmpty(entry.Kind)) return null;
            JObject o = new JObject();
            o["v"] = SchemaVersion;
            o["atUtc"] = DateTime.UtcNow.ToString("O");
            o["session"] = CurrentSession;
            o["kind"] = Trim(entry.Kind, MaxFieldChars);
            if (!string.IsNullOrEmpty(entry.Reason))
                o["reason"] = Trim(entry.Reason, MaxFieldChars);
            if (entry.ExitCode.HasValue)
                o["exitCode"] = entry.ExitCode.Value;
            if (!string.IsNullOrEmpty(entry.BrowserVersion))
                o["browserVersion"] = Trim(entry.BrowserVersion, MaxFieldChars);
            if (entry.BrowserProcessId.HasValue)
                o["browserProcessId"] = entry.BrowserProcessId.Value;
            if (entry.DocumentGeneration.HasValue)
                o["documentGeneration"] = entry.DocumentGeneration.Value;
            if (entry.HostLifecycleGeneration.HasValue)
                o["hostLifecycleGeneration"] = entry.HostLifecycleGeneration.Value;
            if (entry.HostHandle.HasValue)
                o["hostHandle"] = entry.HostHandle.Value;
            if (!string.IsNullOrEmpty(entry.Classification))
                o["classification"] = Trim(entry.Classification, MaxFieldChars);
            if (!string.IsNullOrEmpty(entry.FailureReportFolderPath))
                o["failureReportFolderPath"] = Trim(
                    entry.FailureReportFolderPath, MaxFieldChars);
            if (!string.IsNullOrEmpty(entry.ProcessDescription))
                o["processDescription"] = Trim(
                    entry.ProcessDescription, MaxFieldChars);
            if (!string.IsNullOrEmpty(entry.FailureSourceModulePath))
                o["failureSourceModulePath"] = Trim(
                    entry.FailureSourceModulePath, MaxFieldChars);
            if (entry.FrameCount.HasValue)
                o["frameCount"] = entry.FrameCount.Value;
            if (!string.IsNullOrEmpty(entry.Detail))
                o["detail"] = Trim(entry.Detail, MaxFieldChars);
            return o;
        }

        /// <summary>
        /// 有界追加一行到 path：超出 MaxFileBytes 时先单份轮转到 .1。
        /// 与 collector 的尾读上限（256KiB）保持兼容。返回是否写入成功。
        /// </summary>
        internal static bool AppendLineBounded(string path, string line)
        {
            if (string.IsNullOrEmpty(path) || string.IsNullOrEmpty(line))
                return false;
            try
            {
                lock (Gate)
                {
                    string dir = Path.GetDirectoryName(path);
                    if (!string.IsNullOrEmpty(dir))
                        Directory.CreateDirectory(dir);

                    byte[] payload = Encoding.UTF8.GetBytes(line + "\r\n");
                    FileInfo info = new FileInfo(path);
                    if (info.Exists && info.Length + payload.Length > MaxFileBytes)
                    {
                        string rotated = path + ".1";
                        try
                        {
                            if (File.Exists(rotated)) File.Delete(rotated);
                            File.Move(path, rotated);
                        }
                        catch { }
                    }

                    using (FileStream fs = new FileStream(
                        path, FileMode.Append, FileAccess.Write,
                        FileShare.ReadWrite | FileShare.Delete))
                    {
                        fs.Write(payload, 0, payload.Length);
                    }
                }
                return true;
            }
            catch { return false; }
        }

        private static string Trim(string value, int max)
        {
            if (string.IsNullOrEmpty(value)) return value;
            if (value.Length <= max) return value;
            return value.Substring(0, max);
        }
    }
}
