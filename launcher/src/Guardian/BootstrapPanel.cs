// Phase A Step A1: BootstrapForm → BootstrapPanel
// UserControl 版本，宿主 GuardianForm 负责 window chrome / OnFormClosing / 退出 owner
// - WebView2 hosting + PostToWeb 封送到 UI 线程
// - 初始化失败走 BootstrapInitFailed 事件，由宿主 Form ForceExit（不在 panel 内 Close）
// - Ready 过渡：SetPanelVisible(false) 替代原 HideForReady
// - 文件对话框：ShowDialog(this.FindForm())

using System;
using System.Collections.Generic;
using System.IO;
using System.Windows.Forms;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

namespace CF7Launcher.Guardian
{
    public class BootstrapPanel : UserControl
    {
        private readonly string _webDir;
        private readonly bool _webView2DisableGpu;
        private readonly string _webView2AdditionalArgs;
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
            : this(webDir, false, "")
        {
        }

        public BootstrapPanel(string webDir, bool webView2DisableGpu, string webView2AdditionalArgs)
        {
            _webDir = webDir;
            _webView2DisableGpu = webView2DisableGpu;
            _webView2AdditionalArgs = webView2AdditionalArgs ?? "";

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
            try
            {
                userDataDir = Path.Combine(
                    Path.GetDirectoryName(_webDir), "webview2_userdata");

                CoreWebView2Environment env =
                    await CoreWebView2Environment.CreateAsync(null, userDataDir, CreateWebView2EnvironmentOptions());
                await _webView.EnsureCoreWebView2Async(env);

                _webView.CoreWebView2.SetVirtualHostNameToFolderMapping(
                    "bootstrap.local", _webDir,
                    CoreWebView2HostResourceAccessKind.Allow);

                _webView.CoreWebView2.WebMessageReceived += OnWebMessageReceived;
                _webView.CoreWebView2.Settings.AreDevToolsEnabled = true;
                _webView.CoreWebView2.Settings.AreDefaultContextMenusEnabled = true;

                _webView.CoreWebView2.Navigate("https://bootstrap.local/bootstrap.html");

                LogManager.Log("[Bootstrap] WebView2 engine ready");
            }
            catch (Exception ex)
            {
                // Fail-closed：日志落盘 + 可操作 MessageBox + 触发 BootstrapInitFailed
                string logPath = LogManager.LogFilePath ?? "(未启用文件日志)";
                string userData = userDataDir ?? "(未构造)";
                try
                {
                    // LogManager 文件写入 AutoFlush=true，Log 同步写入磁盘
                    LogManager.Log("[Bootstrap] WebView2 init FATAL: userDataDir=" + userData
                        + " ex=" + ex.ToString());
                }
                catch { }

                string dialogText =
                    "WebView2 初始化失败，启动器无法继续运行。\r\n\r\n"
                    + "请先关闭启动器后重试。\r\n"
                    + "如果问题持续存在，请检查 WebView2 Runtime、用户目录权限，或查看日志。\r\n\r\n"
                    + "用户目录: " + userData + "\r\n"
                    + "日志位置: " + logPath + "\r\n\r\n"
                    + "详情: " + ex.Message;

                try
                {
                    MessageBox.Show(this.FindForm(), dialogText,
                        "CF7:ME Bootstrap", MessageBoxButtons.OK, MessageBoxIcon.Error);
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
                LogManager.Log("[Bootstrap] WebView2 resume failed: " + ex.Message);
            }
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
