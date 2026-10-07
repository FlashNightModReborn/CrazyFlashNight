using System;
using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.Guardian;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.RagTerminal
{
    /// <summary>
    /// 游戏内嵌 AI 聊天终端（CFN-RAG exe）的 Host 侧服务：exe 发现 / 静默拉起 / 健康轮询 /
    /// 存档绑定。见《AI聊天终端-游戏内嵌集成-开发计划-2026-10-07》§1.4-G1-1。
    /// 只访问回环地址；HttpClient 复用；不向 exe 转发任何浏览器 Origin。
    /// </summary>
    internal sealed class RagTerminalService : IDisposable
    {
        /// <summary>7077 同时伺服 API 与前端页面（B1-1）；面板 iframe 只允许此 exact origin。</summary>
        internal const string LoopbackOrigin = "http://127.0.0.1:7077";

        /// <summary>镜像 SaveSlotKey.ExistingPattern 与后端 SLOT_KEY_PATTERN，拒绝路径分隔符。</summary>
        private static readonly Regex SlotKeyPattern = new Regex(
            "^[A-Za-z0-9_-]{1,128}$",
            RegexOptions.Compiled | RegexOptions.CultureInvariant);

        private const string ExeSearchPattern = "CFN-RAG-v*.exe";

        private readonly string _projectRoot;
        private readonly string _exePathOverride;
        private readonly Action<string> _processStarter;
        private readonly HttpClient _http;

        internal int HealthProbeTimeoutMs { get; set; } = 1500;
        internal int ReadyDeadlineMs { get; set; } = 20000;
        internal int PollIntervalMs { get; set; } = 500;
        internal int RequestTimeoutMs { get; set; } = 5000;

        internal RagTerminalService(
            string projectRoot,
            string exePathOverride,
            HttpMessageHandler httpHandler = null,
            Action<string> processStarter = null)
        {
            _projectRoot = projectRoot;
            _exePathOverride = exePathOverride;
            _processStarter = processStarter ?? StartEmbeddedProcess;
            _http = new HttpClient(httpHandler ?? new HttpClientHandler())
            {
                Timeout = Timeout.InfiniteTimeSpan
            };
        }

        internal static bool IsValidSlotKey(string value)
        {
            return !string.IsNullOrEmpty(value) && SlotKeyPattern.IsMatch(value);
        }

        /// <summary>健康轮询 + 按需拉起 + bind 的完整前置链；任一步失败都不开面板。</summary>
        internal async Task<RagTerminalPrepareResult> PrepareForPanelAsync(string slotKey)
        {
            if (!IsValidSlotKey(slotKey))
                return RagTerminalPrepareResult.Fail("rag_slot_invalid", "当前存档信息无效，无法打开通讯终端。");
            RagTerminalPrepareResult ready = await EnsureReadyAsync().ConfigureAwait(false);
            if (!ready.Success) return ready;
            return await BindAsync(slotKey).ConfigureAwait(false);
        }

        /// <summary>先探测既有实例（standalone 复用），未就绪才静默拉起 exe 并轮询健康。</summary>
        internal async Task<RagTerminalPrepareResult> EnsureReadyAsync()
        {
            JObject health = await ProbeHealthAsync().ConfigureAwait(false);
            if (health != null)
            {
                LogManager.Log("[RagTerminal] health ready mode=" + health.Value<string>("mode"));
                return RagTerminalPrepareResult.Ok(null, health.Value<string>("mode"));
            }

            string exePath = ResolveExePath();
            if (exePath == null)
                return RagTerminalPrepareResult.Fail("rag_exe_not_found",
                    "未找到通讯终端程序（CFN-RAG），请先启动一次通讯终端。");

            try
            {
                _processStarter(exePath);
                LogManager.Log("[RagTerminal] started embedded exe=" + exePath);
            }
            catch (Exception ex)
            {
                LogManager.Log("[RagTerminal] start failed: " + ex.Message);
                return RagTerminalPrepareResult.Fail("rag_start_failed", "通讯终端启动失败，请稍后重试。");
            }

            Stopwatch wait = Stopwatch.StartNew();
            while (wait.ElapsedMilliseconds < ReadyDeadlineMs)
            {
                await Task.Delay(PollIntervalMs).ConfigureAwait(false);
                health = await ProbeHealthAsync().ConfigureAwait(false);
                if (health != null)
                {
                    LogManager.Log("[RagTerminal] health ready after start elapsedMs=" + wait.ElapsedMilliseconds);
                    return RagTerminalPrepareResult.Ok(null, health.Value<string>("mode"));
                }
            }
            LogManager.Log("[RagTerminal] health timeout deadlineMs=" + ReadyDeadlineMs);
            return RagTerminalPrepareResult.Fail("rag_health_timeout",
                "通讯终端后台服务未就绪，请稍后重试。");
        }

        /// <summary>bind 幂等，写失败允许有限重试一次；绝不无限重放。</summary>
        internal async Task<RagTerminalPrepareResult> BindAsync(string slotKey)
        {
            if (!IsValidSlotKey(slotKey))
                return RagTerminalPrepareResult.Fail("rag_slot_invalid", "当前存档信息无效，无法打开通讯终端。");

            for (int attempt = 0; attempt < 2; attempt++)
            {
                JObject response = await PostJsonAsync(
                    "/api/integration/bind",
                    new JObject { ["slot_key"] = slotKey }.ToString(Formatting.None)).ConfigureAwait(false);
                if (response != null && response.Value<bool?>("ok") == true)
                {
                    string frontendUrl = response.Value<string>("frontend_url");
                    if (string.IsNullOrEmpty(frontendUrl)
                        || !frontendUrl.StartsWith(LoopbackOrigin, StringComparison.Ordinal))
                    {
                        LogManager.Log("[RagTerminal] frontend_url rejected url=" + (frontendUrl ?? "<null>"));
                        return RagTerminalPrepareResult.Fail("rag_frontend_url_rejected",
                            "通讯终端返回的页面地址不可信，已拒绝打开。");
                    }
                    return RagTerminalPrepareResult.Ok(frontendUrl, response.Value<string>("mode"));
                }
                if (attempt == 0)
                    LogManager.Log("[RagTerminal] bind attempt failed; retrying once slot=" + slotKey);
            }
            LogManager.Log("[RagTerminal] bind failed slot=" + slotKey);
            return RagTerminalPrepareResult.Fail("rag_bind_failed", "通讯终端存档绑定失败，请稍后重试。");
        }

        /// <summary>best-effort 解绑（socket 断连等生命周期落点）；失败仅记日志。</summary>
        internal async Task UnbindAsync()
        {
            JObject response = await PostJsonAsync("/api/integration/unbind", "{}").ConfigureAwait(false);
            if (response == null || response.Value<bool?>("ok") != true)
                LogManager.Log("[RagTerminal] unbind best-effort failed (ignored)");
        }

        internal void UnbindInBackground()
        {
            System.Threading.ThreadPool.QueueUserWorkItem(delegate
            {
                try { UnbindAsync().GetAwaiter().GetResult(); }
                catch (Exception ex) { LogManager.Log("[RagTerminal] unbind threw: " + ex.Message); }
            });
        }

        /// <summary>镜像 fscommand/launch_rag.bat：游戏安装根（projectRoot 的父目录）通配 exe。</summary>
        private string ResolveExePath()
        {
            if (!string.IsNullOrEmpty(_exePathOverride))
            {
                if (File.Exists(_exePathOverride)) return _exePathOverride;
                LogManager.Log("[RagTerminal] configured exe missing path=" + _exePathOverride);
                return null;
            }
            string installRoot = string.IsNullOrEmpty(_projectRoot) ? null : Path.GetDirectoryName(_projectRoot);
            if (string.IsNullOrEmpty(installRoot) || !Directory.Exists(installRoot))
            {
                LogManager.Log("[RagTerminal] install root unavailable projectRoot=" + _projectRoot);
                return null;
            }
            string[] matches = Directory.GetFiles(installRoot, ExeSearchPattern);
            string best = null;
            DateTime bestWrite = DateTime.MinValue;
            foreach (string candidate in matches)
            {
                DateTime written = File.GetLastWriteTimeUtc(candidate);
                if (best == null || written > bestWrite
                    || (written == bestWrite && string.CompareOrdinal(candidate, best) > 0))
                {
                    best = candidate;
                    bestWrite = written;
                }
            }
            if (best == null)
                LogManager.Log("[RagTerminal] no exe match root=" + installRoot);
            return best;
        }

        private static void StartEmbeddedProcess(string exePath)
        {
            Process process = Process.Start(new ProcessStartInfo
            {
                FileName = exePath,
                Arguments = "--embedded",
                UseShellExecute = false,
                WorkingDirectory = Path.GetDirectoryName(exePath)
            });
            if (process == null) throw new InvalidOperationException("process_start_returned_null");
        }

        private async Task<JObject> ProbeHealthAsync()
        {
            try
            {
                using (var cts = new CancellationTokenSource(HealthProbeTimeoutMs))
                using (HttpResponseMessage response = await _http
                    .GetAsync(LoopbackOrigin + "/api/health", cts.Token).ConfigureAwait(false))
                {
                    if (!response.IsSuccessStatusCode) return null;
                    string body = await response.Content.ReadAsStringAsync().ConfigureAwait(false);
                    JObject parsed = JObject.Parse(body);
                    return parsed.Value<string>("status") == "ok" ? parsed : null;
                }
            }
            catch (Exception ex)
            {
                LogManager.Log("[RagTerminal] health probe failed: " + ex.Message);
                return null;
            }
        }

        private async Task<JObject> PostJsonAsync(string path, string json)
        {
            try
            {
                using (var cts = new CancellationTokenSource(RequestTimeoutMs))
                using (var content = new StringContent(json, Encoding.UTF8, "application/json"))
                using (HttpResponseMessage response = await _http
                    .PostAsync(LoopbackOrigin + path, content, cts.Token).ConfigureAwait(false))
                {
                    string body = await response.Content.ReadAsStringAsync().ConfigureAwait(false);
                    if (!response.IsSuccessStatusCode)
                    {
                        LogManager.Log("[RagTerminal] post " + path + " status=" + (int)response.StatusCode);
                        return null;
                    }
                    return JObject.Parse(body);
                }
            }
            catch (Exception ex)
            {
                LogManager.Log("[RagTerminal] post " + path + " failed: " + ex.Message);
                return null;
            }
        }

        public void Dispose()
        {
            _http.Dispose();
        }
    }

    /// <summary>结构化前置结果：失败时 Error 为机器码、Message 为可回游戏 toast 的中文文案。</summary>
    internal sealed class RagTerminalPrepareResult
    {
        internal bool Success { get; private set; }
        internal string Error { get; private set; }
        internal string Message { get; private set; }
        internal string FrontendUrl { get; private set; }
        internal string Mode { get; private set; }

        internal static RagTerminalPrepareResult Ok(string frontendUrl, string mode)
        {
            return new RagTerminalPrepareResult
            {
                Success = true,
                Error = "",
                Message = "",
                FrontendUrl = frontendUrl,
                Mode = mode ?? ""
            };
        }

        internal static RagTerminalPrepareResult Fail(string error, string message)
        {
            return new RagTerminalPrepareResult
            {
                Success = false,
                Error = error,
                Message = message,
                FrontendUrl = null,
                Mode = ""
            };
        }
    }
}
