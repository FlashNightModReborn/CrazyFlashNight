// P3b Phase 1g: BootstrapForm production 升级（spike → 正式入口）
// - PostToWeb 封送到 UI 线程（Control.BeginInvoke；不变式 #5）
// - FormClosing 按状态拦截（close-policy 六状态表；StateProvider 由 Program.cs 注入 GameLaunchFlow.CurrentState）
// - Ready 时 Hide 不 Close（不变式 #1）

using System;
using System.Drawing;
using System.IO;
using System.Windows.Forms;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

namespace CF7Launcher.Guardian
{
    public class BootstrapForm : Form
    {
        private readonly string _webDir;
        private WebView2 _webView;
        private bool _disposed;

        public event Action<string> OnJsMessage;

        /// <summary>
        /// 状态提供者：11b-β 由 Program.cs 注入 `() => launchFlow.CurrentState`。
        /// 未注入（null）时 FormClosing 放行（spike 兼容行为）。
        /// </summary>
        public Func<string> StateProvider;

        public BootstrapForm(string webDir)
        {
            _webDir = webDir;

            this.Text = "CF7:ME Bootstrap";
            this.Width = 900;
            this.Height = 600;
            this.StartPosition = FormStartPosition.CenterScreen;
            this.BackColor = Color.FromArgb(24, 24, 26);

            _webView = new WebView2();
            _webView.Dock = DockStyle.Fill;
            this.Controls.Add(_webView);

            this.FormClosing += OnFormClosingGuard;

            InitWebView2Async();
        }

        /// <summary>
        /// close-policy 拦截：非 Idle/Error/Ready/Resetting(消息差异) 状态下用户关窗需阻止。
        /// Ready 状态已 Hide 不会触发；11b-β 填充完整六状态消息文案。
        /// </summary>
        private void OnFormClosingGuard(object sender, FormClosingEventArgs e)
        {
            if (StateProvider == null) return;  // spike 兼容：无状态机时放行
            string state = null;
            try { state = StateProvider(); } catch { }
            if (string.IsNullOrEmpty(state)) return;

            switch (state)
            {
                case "Idle":
                case "Error":
                case "Ready":
                    return;  // 放行
                case "Resetting":
                    e.Cancel = true;
                    MessageBox.Show(this, "\u91cd\u7f6e\u4e2d\uff0c\u8bf7\u7a0d\u5019",
                        "CF7:ME", MessageBoxButtons.OK, MessageBoxIcon.Information);
                    return;
                default:
                    // Spawning / WaitingConnect / WaitingHandshake / Embedding / WaitingGameReady
                    e.Cancel = true;
                    MessageBox.Show(this, "\u542f\u52a8\u4e2d\uff0c\u8bf7\u7b49\u5f85\u5b8c\u6210\u6216\u70b9\u91cd\u7f6e",
                        "CF7:ME", MessageBoxButtons.OK, MessageBoxIcon.Information);
                    return;
            }
        }

        private async void InitWebView2Async()
        {
            try
            {
                string userDataDir = Path.Combine(
                    Path.GetDirectoryName(_webDir), "webview2_userdata");

                CoreWebView2Environment env =
                    await CoreWebView2Environment.CreateAsync(null, userDataDir);
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
                LogManager.Log("[Bootstrap] WebView2 init failed: " + ex.Message);
                MessageBox.Show("WebView2 init failed:\n" + ex.Message,
                    "Bootstrap", MessageBoxButtons.OK, MessageBoxIcon.Error);
                this.Close();
            }
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
            if (_webView == null || _webView.CoreWebView2 == null) return;
            try { _webView.CoreWebView2.PostWebMessageAsJson(json); }
            catch (Exception ex) { LogManager.Log("[Bootstrap] PostToWeb failed: " + ex.Message); }
        }

        /// <summary>
        /// Ready 过渡：隐藏窗口而非关闭（不变式 #1）。UI 线程安全。
        /// </summary>
        public void HideForReady()
        {
            if (this.IsHandleCreated && this.InvokeRequired)
            {
                try { this.BeginInvoke(new Action(delegate { this.Hide(); })); } catch { }
            }
            else
            {
                this.Hide();
            }
        }

        // ==================== Phase 2a: 文件对话框 helper ====================
        // Handle 由 WebView2 WebMessageReceived 事件在 UI 线程触发，
        // 所以这些 helper 直接同步 ShowDialog(this) 即可，不需 BeginInvoke。

        /// <summary>打开文件对话框，返回选中路径；用户取消返回 null。</summary>
        public string ShowOpenFileDialog(string filter, string title)
        {
            using (OpenFileDialog dlg = new OpenFileDialog())
            {
                dlg.Filter = filter;
                dlg.Title = title;
                if (dlg.ShowDialog(this) == DialogResult.OK) return dlg.FileName;
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
                if (dlg.ShowDialog(this) == DialogResult.OK) return dlg.FileName;
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
