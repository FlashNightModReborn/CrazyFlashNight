// Phase A Step A1: BootstrapForm → BootstrapPanel
// UserControl 版本，宿主 GuardianForm 负责 window chrome / OnFormClosing / 退出 owner
// - WebView2 hosting + PostToWeb 封送到 UI 线程
// - 初始化失败走 BootstrapInitFailed 事件，由宿主 Form ForceExit（不在 panel 内 Close）
// - Ready 过渡：SetPanelVisible(false) 替代原 HideForReady
// - 文件对话框：ShowDialog(this.FindForm())

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;
using CF7Launcher.Diagnostic;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

namespace CF7Launcher.Guardian
{
    public class BootstrapPanel : UserControl
    {
        private readonly string _webDir;
        private readonly bool _webView2DisableGpu;
        private readonly string _webView2AdditionalArgs;
        private readonly bool _webView2DeveloperMode;
        private WebView2 _webView;
        private bool _disposed;
        private bool _webViewSuspended;

        public event Action<string> OnJsMessage;

        /// <summary>
        /// WebView2 引擎初始化失败（fatal）。宿主 Form 订阅此事件调 ForceExit。
        /// 传递的 string 是失败原因（用于日志/诊断）。
        /// </summary>
        public event Action<string> BootstrapInitFailed;

        public BootstrapPanel(string webDir)
            : this(webDir, false, "", false)
        {
        }

        public BootstrapPanel(string webDir, bool webView2DisableGpu, string webView2AdditionalArgs)
            : this(webDir, webView2DisableGpu, webView2AdditionalArgs, false)
        {
        }

        public BootstrapPanel(
            string webDir,
            bool webView2DisableGpu,
            string webView2AdditionalArgs,
            bool webView2DeveloperMode)
        {
            _webDir = webDir;
            _webView2DisableGpu = webView2DisableGpu;
            _webView2AdditionalArgs = webView2AdditionalArgs ?? "";
            _webView2DeveloperMode = webView2DeveloperMode;

            this.AutoScaleMode = AutoScaleMode.None;
            this.BackColor = System.Drawing.Color.FromArgb(24, 24, 26);

            _webView = new WebView2();
            _webView.Dock = DockStyle.Fill;
            this.Controls.Add(_webView);

            // 延迟到 Load 事件触发 WebView2 init：
            // 1) 此时 GuardianForm 已完成 BootstrapInitFailed 订阅（ctor 内抛异常无订阅者会丢信号）
            // 2) 此时 Application.Run 消息循环已启动（ForceExit 的 ExitThread 才真正生效）
            // 两者合起来保证 fail-closed 语义：init 失败 = 弹错框 + 进程终结，而不是弹错框 + 继续跑
            this.Load += OnPanelLoad;
        }

        private bool _initStarted;
        private void OnPanelLoad(object sender, EventArgs e)
        {
            if (_initStarted) return;
            _initStarted = true;
            InitWebView2Async();
        }

        private async void InitWebView2Async()
        {
            string userDataDir = null;
            long initStart = Stopwatch.GetTimestamp();
            try
            {
                StartupDiagnostics.Mark("bootstrap.webview2.init_start", "webDir=" + _webDir);
                userDataDir = Path.Combine(
                    Path.GetDirectoryName(_webDir), "webview2_userdata");
                ProbeUserDataDirWritable(userDataDir);

                long envStart = Stopwatch.GetTimestamp();
                StartupDiagnostics.Mark("bootstrap.webview2.create_environment_start", "userDataDir=" + userDataDir);
                CoreWebView2Environment env =
                    await CoreWebView2Environment.CreateAsync(null, userDataDir, CreateWebView2EnvironmentOptions());
                PerfTrace.Duration("bootstrap.webview2.create_environment", envStart);
                StartupDiagnostics.Mark("bootstrap.webview2.create_environment_ok");

                long ensureStart = Stopwatch.GetTimestamp();
                StartupDiagnostics.Mark("bootstrap.webview2.ensure_core_start");
                await _webView.EnsureCoreWebView2Async(env);
                PerfTrace.Duration("bootstrap.webview2.ensure_core", ensureStart);
                StartupDiagnostics.Mark("bootstrap.webview2.ensure_core_ok");

                WebView2BrowserPolicy.Apply(
                    _webView.CoreWebView2.Settings,
                    _webView2DeveloperMode,
                    "BootstrapPanel");

                _webView.CoreWebView2.SetVirtualHostNameToFolderMapping(
                    "bootstrap.local", _webDir,
                    CoreWebView2HostResourceAccessKind.Allow);

                _webView.CoreWebView2.WebMessageReceived += OnWebMessageReceived;
                _webView.CoreWebView2.NavigationCompleted += OnNavigationCompleted;

                StartupDiagnostics.Mark("bootstrap.webview2.navigate_start", "https://bootstrap.local/bootstrap.html");
                PerfTrace.Mark("bootstrap.webview2.navigate_start");
                _webView.CoreWebView2.Navigate("https://bootstrap.local/bootstrap.html");

                LogManager.Log("[Bootstrap] WebView2 engine ready");
                PerfTrace.Duration("bootstrap.webview2.init_total", initStart);
                StartupDiagnostics.Mark("bootstrap.webview2.init_ok");
            }
            catch (Exception ex)
            {
                // Fail-closed：日志落盘 + 自诊断弹窗 + 触发 BootstrapInitFailed
                string logPath = LogManager.LogFilePath ?? "(未启用文件日志)";
                string userData = userDataDir ?? "(未构造)";
                PerfTrace.Duration("bootstrap.webview2.init_total", initStart, "fail:" + ex.GetType().Name);
                try
                {
                    // LogManager 文件写入 AutoFlush=true，Log 同步写入磁盘
                    LogManager.Log("[Bootstrap] WebView2 init FATAL: userDataDir=" + userData
                        + " ex=" + ex.ToString());
                }
                catch { }

                try
                {
                    IWin32Window owner = this.FindForm();
                    if (owner == null) owner = this;
                    StartupFailureReporter.ReportTerminalFailure(
                        owner,
                        ResolveProjectRootFromWebDir(),
                        "bootstrap_webview2_init_failed",
                        "CF7-LAUNCH-BOOTSTRAP-WEBVIEW2",
                        "启动页面初始化失败",
                        ex.GetType().Name + ": " + ex.Message
                            + "\r\nuserDataDir=" + userData
                            + "\r\nlauncherLog=" + logPath,
                        "请先关闭启动器后重试。如果问题持续存在，请修复 WebView2 Runtime，并确认 launcher\\webview2_userdata 目录可写。",
                        null,
                        null,
                        null);
                }
                catch { }

                Action<string> handler = BootstrapInitFailed;
                if (handler != null)
                {
                    try { handler(ex.Message); }
                    catch (Exception hex)
                    {
                        LogManager.Log("[Bootstrap] BootstrapInitFailed handler error: " + hex.Message);
                    }
                }
            }
        }

        private string ResolveProjectRootFromWebDir()
        {
            try
            {
                DirectoryInfo web = new DirectoryInfo(_webDir);
                if (web.Parent != null && web.Parent.Parent != null)
                    return web.Parent.Parent.FullName;
            }
            catch { }
            return null;
        }

        private static void ProbeUserDataDirWritable(string userDataDir)
        {
            long start = Stopwatch.GetTimestamp();
            try
            {
                Directory.CreateDirectory(userDataDir);
                string testPath = Path.Combine(userDataDir,
                    ".cf7-write-test-" + Process.GetCurrentProcess().Id + ".tmp");
                File.WriteAllText(testPath, "ok");
                File.Delete(testPath);
                StartupDiagnostics.Mark("bootstrap.webview2.user_data_writable", "path=" + userDataDir);
                PerfTrace.Duration("bootstrap.webview2.user_data_writable", start, "ok");
            }
            catch (Exception ex)
            {
                StartupDiagnostics.Warn("bootstrap.webview2.user_data_not_writable",
                    ex.GetType().Name + ": " + ex.Message + " path=" + userDataDir);
                PerfTrace.Duration("bootstrap.webview2.user_data_writable", start, "fail:" + ex.GetType().Name);
            }
        }

        private void OnNavigationCompleted(object sender, CoreWebView2NavigationCompletedEventArgs e)
        {
            string detail = "success=" + e.IsSuccess + " status=" + e.WebErrorStatus;
            if (e.IsSuccess)
            {
                StartupDiagnostics.Mark("bootstrap.webview2.navigation_completed", detail);
            }
            else
            {
                StartupDiagnostics.Warn("bootstrap.webview2.navigation_failed", detail);
            }
            PerfTrace.Mark("bootstrap.webview2.navigation_completed", detail);
            LogManager.Log("[Bootstrap] WebView2 navigation completed " + detail);
        }

        private CoreWebView2EnvironmentOptions CreateWebView2EnvironmentOptions()
        {
            List<string> args = new List<string>();
            if (_webView2DisableGpu)
            {
                args.Add("--disable-gpu");
                args.Add("--disable-gpu-rasterization");
                args.Add("--disable-accelerated-2d-canvas");
            }

            if (!string.IsNullOrWhiteSpace(_webView2AdditionalArgs))
                args.Add(_webView2AdditionalArgs.Trim());

            if (args.Count == 0)
            {
                LogManager.Log("[Bootstrap] WebView2 perf options: disableGpu=false");
                return null;
            }

            CoreWebView2EnvironmentOptions options = new CoreWebView2EnvironmentOptions();
            options.AdditionalBrowserArguments = string.Join(" ", args.ToArray());
            LogManager.Log("[Bootstrap] WebView2 perf options: disableGpu=" + _webView2DisableGpu
                + " args=" + options.AdditionalBrowserArguments);
            return options;
        }

        private void OnWebMessageReceived(object sender, CoreWebView2WebMessageReceivedEventArgs e)
        {
            string raw;
            try { raw = e.TryGetWebMessageAsString(); }
            catch { raw = e.WebMessageAsJson; }

            LogManager.Log("[Bootstrap] JS→C#: " + raw);

            if (OnJsMessage != null)
                OnJsMessage(raw);
        }

        public void PostToWeb(string json)
        {
            if (_webView == null || _disposed) return;
            // 封送到 UI 线程（WebView2 CoreWebView2 只能在创建线程访问）
            if (this.IsHandleCreated && this.InvokeRequired)
            {
                try { this.BeginInvoke(new Action<string>(PostToWebCore), json); }
                catch (Exception ex) { LogManager.Log("[Bootstrap] PostToWeb BeginInvoke failed: " + ex.Message); }
            }
            else
            {
                PostToWebCore(json);
            }
        }

        private void PostToWebCore(string json)
        {
            CoreWebView2 core = TryGetCoreWebView2();
            if (core == null) return;
            try { core.PostWebMessageAsJson(json); }
            catch (Exception ex) { LogManager.Log("[Bootstrap] PostToWeb failed: " + ex.Message); }
        }

        /// <summary>
        /// Ready 过渡：隐藏 panel 而非关闭（不变式 #1）。UI 线程安全。
        /// </summary>
        public void SetPanelVisible(bool visible)
        {
            if (this.IsHandleCreated && this.InvokeRequired)
            {
                try { this.BeginInvoke(new Action<bool>(SetPanelVisible), visible); } catch { }
                return;
            }

            if (visible)
            {
                ResumeWebViewIfNeeded();
                this.Visible = true;
            }
            else
            {
                this.Visible = false;
                SuspendWebViewIfPossible();
            }
        }

        private async void SuspendWebViewIfPossible()
        {
            CoreWebView2 core = TryGetCoreWebView2();
            if (core == null || _webViewSuspended)
                return;

            try
            {
                bool ok = await core.TrySuspendAsync();
                _webViewSuspended = ok;
                LogManager.Log("[Bootstrap] WebView2 suspend requested, ok=" + ok);
            }
            catch (Exception ex)
            {
                if (IsWebViewDisposeRace(ex))
                    return;
                LogManager.Log("[Bootstrap] WebView2 suspend failed: " + ex.Message);
            }
        }

        private void ResumeWebViewIfNeeded()
        {
            CoreWebView2 core = TryGetCoreWebView2();
            if (core == null || !_webViewSuspended)
                return;

            try
            {
                core.Resume();
                _webViewSuspended = false;
                LogManager.Log("[Bootstrap] WebView2 resumed");
            }
            catch (Exception ex)
            {
                if (IsWebViewDisposeRace(ex))
                    return;
                LogManager.Log("[Bootstrap] WebView2 resume failed: " + ex.Message);
            }
        }

        private bool IsWebViewDisposeRace(Exception ex)
        {
            if (_disposed || _webView == null)
                return true;
            try { if (_webView.IsDisposed) return true; } catch { return true; }
            if (ex is ObjectDisposedException)
                return true;
            InvalidOperationException invalid = ex as InvalidOperationException;
            return invalid != null
                && invalid.Message != null
                && invalid.Message.IndexOf("disposed", StringComparison.OrdinalIgnoreCase) >= 0;
        }

        private CoreWebView2 TryGetCoreWebView2()
        {
            if (_disposed || _webView == null || _webView.IsDisposed)
                return null;

            try { return _webView.CoreWebView2; }
            catch (ObjectDisposedException) { return null; }
            catch (InvalidOperationException) { return null; }
        }

        // ==================== 文件对话框 helper ====================
        // Handle 由 WebView2 WebMessageReceived 事件在 UI 线程触发，
        // ShowDialog 以宿主 Form 作为 owner。

        /// <summary>打开文件对话框，返回选中路径；用户取消返回 null。</summary>
        public string ShowOpenFileDialog(string filter, string title)
        {
            using (OpenFileDialog dlg = new OpenFileDialog())
            {
                dlg.Filter = filter;
                dlg.Title = title;
                Form owner = this.FindForm();
                if (dlg.ShowDialog(owner) == DialogResult.OK) return dlg.FileName;
            }
            return null;
        }

        /// <summary>保存文件对话框，返回选中路径；用户取消返回 null。</summary>
        public string ShowSaveFileDialog(string filter, string title, string defaultName)
        {
            using (SaveFileDialog dlg = new SaveFileDialog())
            {
                dlg.Filter = filter;
                dlg.Title = title;
                if (!string.IsNullOrEmpty(defaultName))
                    dlg.FileName = defaultName;
                Form owner = this.FindForm();
                if (dlg.ShowDialog(owner) == DialogResult.OK) return dlg.FileName;
            }
            return null;
        }

        protected override void Dispose(bool disposing)
        {
            if (_disposed) { base.Dispose(disposing); return; }
            _disposed = true;
            if (disposing)
            {
                try { if (_webView != null) _webView.Dispose(); } catch { }
            }
            base.Dispose(disposing);
        }
    }
}
