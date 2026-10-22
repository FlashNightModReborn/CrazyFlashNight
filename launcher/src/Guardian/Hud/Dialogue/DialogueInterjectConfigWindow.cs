using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using System.Windows.Forms;
using CF7Launcher.RagTerminal;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Guardian.Hud.Dialogue
{
    /// <summary>
    /// 游戏内模型配置小窗：独立 WebView2 窗口，加载终端前端的 /config 页面。
    ///
    /// 与聊天面板（同一 WebOverlayForm 里的 iframe）使用同一个 WebView2 user data folder
    /// 和同一个 7077 origin，因此 localStorage 就是终端设置页那一份，不额外落盘 API Key。
    /// 所有保存/同步由页面完成，宿主只负责显示、关闭与解锁插话输入。
    ///
    /// 先以“屏外可见”方式创建，收到页面 ready 消息后再决定：
    /// - auto 模式且已有配置：不显示，直接关闭并解锁；
    /// - 其余：移到游戏窗口中央并激活。
    /// </summary>
    internal sealed class DialogueInterjectConfigWindow : Form
    {
        [DllImport("user32.dll")]
        private static extern IntPtr GetForegroundWindow();

        private const int WM_MOUSEACTIVATE = 0x0021;
        private static readonly Point Offscreen = new Point(-32000, -32000);

        private readonly string _userDataFolder;
        private readonly string _url;
        private readonly bool _autoMode;
        private readonly bool _developerMode;
        private readonly CoreWebView2EnvironmentOptions _environmentOptions;
        private readonly WebView2 _webView;
        private readonly Label _status;
        private bool _revealed;
        private DateTime _lastInteractionUtc;

        /// <summary>页面确认保存成功（或 auto 模式确认已有配置）。</summary>
        internal event Action Saved;
        /// <summary>玩家手动关闭小窗（未保存）。</summary>
        internal event Action Canceled;
        /// <summary>小窗是否处于文字输入态（宿主据此放行游戏热键）。</summary>
        internal event Action<bool> TextInputActiveChanged;
        /// <summary>「启动游戏时自动启动终端」勾选变更；宿主负责落盘。</summary>
        internal event Action<bool> AutoStartChanged;

        internal DialogueInterjectConfigWindow(string userDataFolder, string url,
            bool autoMode, bool developerMode,
            CoreWebView2EnvironmentOptions environmentOptions = null)
        {
            if (string.IsNullOrEmpty(userDataFolder))
                throw new ArgumentException("WebView2 user data folder is required", nameof(userDataFolder));
            _userDataFolder = userDataFolder;
            _url = url ?? throw new ArgumentNullException(nameof(url));
            _autoMode = autoMode;
            _developerMode = developerMode;
            _environmentOptions = environmentOptions;

            Text = "配置模型 API";
            // 页面自带标题栏与关闭按钮；宿主不再显示白色系统标题栏。
            FormBorderStyle = FormBorderStyle.None;
            MaximizeBox = false;
            MinimizeBox = false;
            ShowInTaskbar = false;
            StartPosition = FormStartPosition.Manual;
            AutoScaleMode = AutoScaleMode.None;
            ClientSize = new Size(560, 640);
            BackColor = Color.FromArgb(0, 90, 42);   // 1px 边框色，页面内再画细描边
            ForeColor = Color.FromArgb(217, 232, 238);
            Font = new Font("Microsoft YaHei UI", 12f, FontStyle.Regular, GraphicsUnit.Pixel);
            KeyPreview = true;
            Padding = new Padding(1);
            Location = Offscreen;

            // WebView2 在不可见控件上初始化不可靠：保持可见，用状态标签盖住它。
            _webView = new WebView2
            {
                Dock = DockStyle.Fill,
                DefaultBackgroundColor = Color.FromArgb(10, 10, 10)
            };
            Controls.Add(_webView);

            _status = new Label
            {
                Dock = DockStyle.Fill,
                Text = "正在读取终端配置…",
                TextAlign = ContentAlignment.MiddleCenter,
                BackColor = Color.FromArgb(10, 10, 10),
                ForeColor = Color.FromArgb(139, 163, 173),
                Font = new Font("Microsoft YaHei UI", 12f, FontStyle.Regular, GraphicsUnit.Pixel)
            };
            Controls.Add(_status);
            _status.BringToFront();

            Load += async delegate
            {
                ApplyWindowSize();
                await InitAsync();
            };
            Activated += delegate { _lastInteractionUtc = DateTime.UtcNow; };
            Deactivate += delegate { RaiseTextInput(false); };
            FormClosed += delegate { RaiseTextInput(false); };
            KeyDown += delegate (object sender, KeyEventArgs e)
            {
                if (e.KeyCode != Keys.Escape) return;
                e.Handled = true;
                RequestCancel();
            };
        }

        /// <summary>WebView2 需要窗口可见才能初始化；先屏外显示，不抢前台。</summary>
        protected override bool ShowWithoutActivation
        {
            get { return true; }
        }

        protected override CreateParams CreateParams
        {
            get
            {
                CreateParams cp = base.CreateParams;
                cp.ClassStyle |= 0x00020000;   // CS_DROPSHADOW
                return cp;
            }
        }

        /// <summary>WebView2 的 CSS 像素跟随系统 DPI；窗口按 DPI 放大，页面才能完整显示。</summary>
        private void ApplyWindowSize()
        {
            float scale = Math.Max(1f, DeviceDpi / 96f);
            ClientSize = new Size(
                (int)Math.Round(560 * scale),
                (int)Math.Round(640 * scale));
        }

        internal bool IsRevealed { get { return _revealed; } }

        /// <summary>HUD 白名单判据：小窗已展示且在前台/刚交互时，不隐藏对话。</summary>
        internal bool ShouldKeepHudPresented()
        {
            if (!Visible || !_revealed) return false;
            IntPtr handle = Handle;
            if (handle != IntPtr.Zero && GetForegroundWindow() == handle) return true;
            return (DateTime.UtcNow - _lastInteractionUtc).TotalMilliseconds < 1500;
        }

        private async Task InitAsync()
        {
            try
            {
                CoreWebView2EnvironmentOptions options = _environmentOptions
                    ?? FixedWebViewRuntime.CreateStorageSharingOptions();
                CoreWebView2Environment env = await FixedWebViewRuntime.CreateAsync(
                    _userDataFolder, options);
                await _webView.EnsureCoreWebView2Async(env);
                FixedWebViewRuntime.ValidateCore(_webView.CoreWebView2);
                WebView2BrowserPolicy.Apply(_webView.CoreWebView2.Settings, _developerMode,
                    "DialogueInterjectConfig");
                _webView.CoreWebView2.WebMessageReceived += OnWebMessageReceived;
                _webView.CoreWebView2.NavigationCompleted += OnNavigationCompleted;
                _webView.CoreWebView2.Navigate(_url);
            }
            catch (Exception ex)
            {
                LogManager.Log("[DialogueInterject] config window init failed: " + ex.Message);
                ShowError("配置窗口加载失败，请点击输入条的“配置”重试。");
            }
        }

        private void OnNavigationCompleted(object sender, CoreWebView2NavigationCompletedEventArgs e)
        {
            if (e.IsSuccess) return;
            LogManager.Log("[DialogueInterject] config window navigation failed: "
                + e.WebErrorStatus);
            ShowError("配置页面加载失败，请确认通讯终端已启动后重试。");
        }

        private void OnWebMessageReceived(object sender, CoreWebView2WebMessageReceivedEventArgs e)
        {
            JObject message;
            try
            {
                message = JObject.Parse(e.WebMessageAsJson);
            }
            catch (Exception)
            {
                return;
            }
            string type = message.Value<string>("type") ?? "";
            if (string.Equals(type, "llm-config-ready", StringComparison.Ordinal))
            {
                bool configured = message.Value<bool?>("configured") == true;
                if (configured && _autoMode)
                {
                    RaiseSaved();
                    Close();
                    return;
                }
                Reveal();
                return;
            }
            if (string.Equals(type, "llm-config-saved", StringComparison.Ordinal))
            {
                RaiseSaved();
                Close();
                return;
            }
            if (string.Equals(type, "llm-config-cancel", StringComparison.Ordinal))
            {
                RequestCancel();
                return;
            }
            if (string.Equals(type, "rag-terminal-autostart", StringComparison.Ordinal))
            {
                if (message["enabled"]?.Type == JTokenType.Boolean)
                    AutoStartChanged?.Invoke(message.Value<bool>("enabled"));
            }
        }

        private void RequestCancel()
        {
            RaiseCanceled();
            Close();
        }

        private void Reveal()
        {
            if (_revealed || IsDisposed) return;
            _revealed = true;
            _status.Visible = false;
            _webView.Visible = true;
            PositionOnOwner();
            BringToFront();
            Activate();
            try { _webView.Focus(); } catch { }
            RaiseTextInput(true);
        }

        private void PositionOnOwner()
        {
            Rectangle target;
            Form owner = Owner;
            if (owner != null && !owner.IsDisposed)
                target = owner.RectangleToScreen(owner.ClientRectangle);
            else
                target = Screen.PrimaryScreen.WorkingArea;
            int x = target.Left + Math.Max(0, (target.Width - Width) / 2);
            int y = target.Top + Math.Max(0, (target.Height - Height) / 2);
            Location = new Point(x, y);
        }

        private void ShowError(string message)
        {
            if (IsDisposed) return;
            _webView.Visible = false;
            _status.Text = message;
            _status.ForeColor = Color.FromArgb(226, 128, 108);
            _status.Visible = true;
            _status.BringToFront();
            if (!_revealed)
            {
                _revealed = true;
                PositionOnOwner();
                BringToFront();
                Activate();
            }
        }

        private void RaiseSaved()
        {
            Action handler = Saved;
            if (handler == null) return;
            try { handler(); }
            catch (Exception ex) { LogManager.Log("[DialogueInterject] config saved: " + ex.Message); }
        }

        private void RaiseCanceled()
        {
            Action handler = Canceled;
            if (handler == null) return;
            try { handler(); }
            catch { }
        }

        private void RaiseTextInput(bool active)
        {
            Action<bool> handler = TextInputActiveChanged;
            if (handler == null) return;
            try { handler(active); }
            catch { }
        }
    }
}
