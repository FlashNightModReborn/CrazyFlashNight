using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using System.Windows.Forms;
using CF7Launcher.Guardian.InputOwnership;
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
        [DllImport("user32.dll")]
        private static extern IntPtr GetFocus();
        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool IsChild(IntPtr parent, IntPtr child);

        private const int WM_MOUSEACTIVATE = 0x0021;
        private const string ConfigEndpoint = "dialogue.interject.config";
        private static readonly Point Offscreen = new Point(-32000, -32000);
        // /config is owned by the terminal frontend. Bind by semantic field,
        // never by label order or by reading the contents of a field.
        private static readonly IReadOnlyDictionary<string, string> EditorSelectors = new Dictionary<string, string>
        {
            ["endpoint"] = "[data-ui-field-id='endpoint'], input:is([name='endpoint' i], [id='endpoint' i], [name='baseUrl' i], [id='baseUrl' i], [name='base_url' i], [id='base_url' i], [name='apiBase' i], [id='apiBase' i], [name='base' i], [id='base' i], [type='url'], [placeholder^='https://' i], [placeholder^='http://' i])",
            ["model"] = "[data-ui-field-id='model'], input:is([name='model' i], [id='model' i], [name='modelName' i], [id='modelName' i], [placeholder*='模型'])",
            ["apiKey"] = "[data-ui-field-id='apiKey'], input:is([name='apiKey' i], [id='apiKey' i], [name='api_key' i], [id='api_key' i], [type='password'], [placeholder*='API Key' i], [placeholder^='sk-' i])"
        };

        private readonly string _userDataFolder;
        private readonly string _url;
        private readonly string _inputSource;
        private readonly bool _autoMode;
        private readonly bool _developerMode;
        private readonly CoreWebView2EnvironmentOptions _environmentOptions;
        private readonly WebView2 _webView;
        private readonly Label _status;
        private bool _revealed;
        private ITextInputAuthority _textAuthority;
        private IUiPointerAuthority _pointerAuthority;
        private WebTextFocusBinding _textFields;
        private string _inputInstance;
        private long _pointerGeneration;
        private bool _documentReady, _closing;
        private ulong _configurationNavigationId;
        private TextExitReceipt? _incomingTextExit;
        private Action _closeTextExit;
        private (Control Control, PointerGestureTicket Ticket, Rectangle ScreenBounds)? _chromePointer;

        /// <summary>页面确认保存成功（或 auto 模式确认已有配置）。</summary>
        internal event Action Saved;
        /// <summary>玩家手动关闭小窗（未保存）。</summary>
        internal event Action Canceled;
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
            _inputSource = Uri.TryCreate(url, UriKind.Absolute, out var uri) ? uri.AbsoluteUri : url;
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
            _webView.LostFocus += (_, _) => QueueWebViewFocusLoss();

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
            KeyDown += delegate (object sender, KeyEventArgs e)
            {
                if (e.KeyCode != Keys.Escape || _textFields?.ImeComposing == true) return;
                e.Handled = true;
                e.SuppressKeyPress = true;
                RequestCancel((int)Keys.Escape);
            };
            foreach (Control chrome in new Control[] { this, _status })
            {
                chrome.MouseDown += BeginChromePointer;
                chrome.MouseUp += CommitChromePointer;
                chrome.MouseCaptureChanged += (_, _) =>
                {
                    if (_chromePointer is { } pending && ReferenceEquals(chrome, pending.Control) && !chrome.Capture)
                        CancelChromePointer("interject_config_capture_lost");
                };
            }
        }

        internal void BindInputAuthority(ITextInputAuthority textAuthority, IUiPointerAuthority pointerAuthority)
        {
            if (IsDisposed || ReferenceEquals(_textAuthority, textAuthority)
                && ReferenceEquals(_pointerAuthority, pointerAuthority)) return;
            CancelChromePointer("interject_config_authority_changed");
            RetireTextFields("interject_config_authority_changed", requestGame: false);
            _incomingTextExit = null;
            _textAuthority = textAuthority;
            _pointerAuthority = pointerAuthority;
            if (IsHandleCreated) StartInputInstance();
            SyncTextFields();
        }

        private void StartInputInstance()
        {
            _inputInstance = Guid.NewGuid().ToString("N");
            // A window may be bound for pointer-only observation.
            _pointerGeneration = _textAuthority?.NextInstanceGeneration(ConfigEndpoint)
                ?? checked(_pointerGeneration + 1);
        }

        protected override void OnHandleCreated(EventArgs e)
        {
            base.OnHandleCreated(e);
            if (_textAuthority != null || _pointerAuthority != null)
            {
                StartInputInstance();
                SyncTextFields();
            }
        }

        protected override void OnHandleDestroyed(EventArgs e)
        {
            CancelChromePointer("interject_config_handle_destroyed");
            if (!_closing) RetireTextFields("interject_config_handle_destroyed", requestGame: !RecreatingHandle);
            base.OnHandleDestroyed(e);
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

        [DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
        internal bool IsRevealed { get { return _revealed; } }

        /// <summary>配置窗持有前台期间保留本会话 HUD。</summary>
        internal bool ShouldKeepHudPresented() => Visible && _revealed && IsHandleCreated
            && GetForegroundWindow() == Handle;

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
                _webView.CoreWebView2.NavigationStarting += OnNavigationStarting;
                _webView.CoreWebView2.NavigationCompleted += OnNavigationCompleted;
                _webView.CoreWebView2.Navigate(_url);
            }
            catch (Exception ex)
            {
                LogManager.Log("[DialogueInterject] config window init failed: " + ex.Message);
                ShowError("配置窗口加载失败，请点击输入条的“配置”重试。");
            }
        }

        private void OnNavigationStarting(object sender, CoreWebView2NavigationStartingEventArgs e)
        {
            _configurationNavigationId = e.NavigationId;
            _documentReady = false;
            if (_textFields is { } fields)
            {
                fields.CaptureExit("interject_config_navigation", requestGame: false)?.Invoke();
                _textFields = null;
                _incomingTextExit = fields.TakeExitReceipt() ?? _incomingTextExit;
            }
        }

        private void OnNavigationCompleted(object sender, CoreWebView2NavigationCompletedEventArgs e)
        {
            if (_configurationNavigationId != e.NavigationId) return;
            if (e.IsSuccess)
            {
                _documentReady = true;
                SyncTextFields();
                return;
            }
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
            if (type == WebTextFocusBinding.MessageType)
            {
                if (!_closing && _textFields is { } fields && _revealed && Visible && e.Source == _inputSource
                    && ReferenceEquals(sender, _webView.CoreWebView2))
                    fields.Observe(message, Owner?.IsHandleCreated == true ? Owner.Handle : Handle,
                        ObserveEditorWindow(), requestGameOnBlur: false);
                return;
            }
            if (string.Equals(type, "llm-config-ready", StringComparison.Ordinal))
            {
                bool configured = message.Value<bool?>("configured") == true;
                if (configured && _autoMode)
                {
                    CaptureClosingText("interject_config_auto_close");
                    RaiseSaved();
                    Close();
                    return;
                }
                Reveal();
                return;
            }
            if (string.Equals(type, "llm-config-saved", StringComparison.Ordinal))
            {
                CaptureClosingText("interject_config_saved");
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

        private void RequestCancel(int triggerVk = 0)
        {
            CaptureClosingText("interject_config_cancel", triggerVk);
            RaiseCanceled();
            Close();
        }

        private void Reveal()
        {
            if (_revealed || IsDisposed) return;
            _revealed = true;
            _status.Visible = false;
            _webView.Visible = true;
            SyncTextFields();
            PositionOnOwner();
            FocusRevealedWindow(focusWeb: true);
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
            _textFields?.CaptureExit("interject_config_error", requestGame: false)?.Invoke();
            _webView.Visible = false;
            _status.Text = message;
            _status.ForeColor = Color.FromArgb(226, 128, 108);
            _status.Visible = true;
            _status.BringToFront();
            if (!_revealed)
            {
                _revealed = true;
                PositionOnOwner();
                FocusRevealedWindow(focusWeb: false);
            }
        }

        private void FocusRevealedWindow(bool focusWeb)
        {
            if (!IsHandleCreated || Owner is not { IsHandleCreated: true, Visible: true } owner
                || owner.WindowState == FormWindowState.Minimized) return;
            IntPtr foreground = GetForegroundWindow();
            if (foreground == IntPtr.Zero) return;
            if (foreground != Handle)
            {
                bool fromOwner = foreground == owner.Handle || IsChild(owner.Handle, foreground);
                bool fromInterject = Control.FromHandle(foreground) is DialogueInterjectInputOverlay input
                    && input.Visible && ReferenceEquals(input.Owner, owner);
                if (!fromOwner && !fromInterject) return;
                Activate();
            }
            if (focusWeb && GetForegroundWindow() == Handle)
            {
                try { _webView.Focus(); } catch { }
            }
        }

        private void SyncTextFields()
        {
            if (_textAuthority == null || _textFields != null || !_revealed || !_documentReady || _closing
                || IsDisposed || !IsHandleCreated || _webView?.CoreWebView2 is not { } core
                || core.Source != _inputSource) return;
            _textFields = new WebTextFocusBinding(_textAuthority, _inputInstance, ConfigEndpoint + ".", EditorSelectors);
            _ = _textFields.InstallAsync(core, _inputSource);
        }

        private IntPtr ObserveEditorWindow()
        {
            if (!IsHandleCreated || !_webView.IsHandleCreated || !_webView.Visible
                || GetForegroundWindow() != Handle) return IntPtr.Zero;
            IntPtr focus = GetFocus();
            return focus != IntPtr.Zero && (focus == _webView.Handle || IsChild(_webView.Handle, focus))
                ? focus : IntPtr.Zero;
        }

        internal bool DeferGameKeyboardFromEditor(ITextInputAuthority authority, TextExitReceipt receipt)
        {
            if (!ReferenceEquals(_textAuthority, authority) || !_revealed || IsDisposed || _closing) return false;
            _incomingTextExit = receipt;
            return true;
        }

        private Action CaptureConfigExit(string reason, int triggerVk = 0, bool detach = true)
        {
            if (_textAuthority == null) return null;
            var authority = _textAuthority;
            var arrival = _incomingTextExit;
            if (detach) _incomingTextExit = null;
            return _textFields?.CaptureExit(reason, requestGame: true, triggerVk: triggerVk, detach: detach)
                ?? (arrival is { } receipt ? () =>
                {
                    if (_incomingTextExit == receipt) _incomingTextExit = null;
                    authority.RequestGameKeyboard(receipt);
                } : null);
        }

        private void RetireTextFields(string reason, bool requestGame)
        {
            var fields = _textFields;
            var exit = requestGame ? CaptureConfigExit(reason) : fields?.CaptureExit(reason, requestGame: false);
            _textFields = null;
            exit?.Invoke();
        }

        private void CaptureClosingText(string reason, int triggerVk = 0)
        {
            if (_closing) return;
            _closing = true;
            _closeTextExit = CaptureConfigExit(reason, triggerVk, detach: false);
        }

        private void QueueWebViewFocusLoss()
        {
            if (_closing || _textFields is not { } fields) return;
            var exit = fields.CaptureExit("interject_config_editor_lost_focus", requestGame: false, detach: false);
            if (exit == null) return;
            QueueConfigExit(() =>
            {
                if (!ReferenceEquals(_textFields, fields) || ObserveEditorWindow() == IntPtr.Zero)
                    exit();
            });
        }

        private void QueueConfigExit(Action captured)
        {
            if (captured == null) return;
            // The owner outlives this popup, including when FormClosed disposes
            // its WebView2 before the posted callback is dispatched.
            try
            {
                if (Owner?.IsHandleCreated == true && !Owner.IsDisposed)
                {
                    Owner.BeginInvoke(captured);
                    return;
                }
            }
            catch (InvalidOperationException) { }
            captured();
        }

        protected override void OnDeactivate(EventArgs e)
        {
            var exit = _closing ? null : CaptureConfigExit("interject_config_deactivate");
            CancelChromePointer("interject_config_deactivate");
            QueueConfigExit(exit);
            base.OnDeactivate(e);
        }

        protected override void OnResize(EventArgs e)
        {
            CancelChromePointer("interject_config_resized");
            base.OnResize(e);
        }

        protected override void OnLocationChanged(EventArgs e)
        {
            CancelChromePointer("interject_config_moved");
            base.OnLocationChanged(e);
        }

        protected override void OnDpiChanged(DpiChangedEventArgs e)
        {
            CancelChromePointer("interject_config_dpi_changed");
            base.OnDpiChanged(e);
        }

        protected override void OnFormClosing(FormClosingEventArgs e)
        {
            CaptureClosingText("interject_config_closing");
            base.OnFormClosing(e);
            if (!e.Cancel) return;
            _closeTextExit = null;
            _closing = false;
        }

        protected override void OnFormClosed(FormClosedEventArgs e)
        {
            CaptureClosingText("interject_config_closed");
            var exit = _closeTextExit;
            _closeTextExit = null;
            _textFields = null;
            QueueConfigExit(exit);
            base.OnFormClosed(e);
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                CancelChromePointer("interject_config_disposed");
                var exit = _closeTextExit ?? CaptureConfigExit("interject_config_disposed");
                _closeTextExit = null;
                _textFields = null;
                exit?.Invoke();
            }
            base.Dispose(disposing);
        }

        private void BeginChromePointer(object sender, MouseEventArgs e)
        {
            if (_pointerAuthority == null || e.Button != MouseButtons.Left || !_revealed
                || _pointerGeneration <= 0 || sender is not Control chrome) return;
            CancelChromePointer("interject_config_new_down");
            if (!_pointerAuthority.TryBeginPointer(ConfigEndpoint, _pointerGeneration, 1,
                chrome.PointToScreen(e.Location), ConfigEndpoint + ".chrome", out var ticket)) return;
            _chromePointer = (chrome, ticket, chrome.RectangleToScreen(chrome.ClientRectangle));
            chrome.Capture = true;
        }

        private void CommitChromePointer(object sender, MouseEventArgs e)
        {
            if (e.Button != MouseButtons.Left || _chromePointer is not { } pending) return;
            _chromePointer = null;
            pending.Control.Capture = false;
            if (ReferenceEquals(sender, pending.Control) && pending.Control.Visible
                && pending.Control.ClientRectangle.Contains(e.Location)
                && pending.Control.RectangleToScreen(pending.Control.ClientRectangle) == pending.ScreenBounds
                && pending.Ticket.InstanceGeneration == _pointerGeneration
                && _pointerAuthority.ValidatePointerCommit(pending.Ticket, ConfigEndpoint + ".chrome"))
                _pointerAuthority.EndPointer(pending.Ticket, committed: true);
            else _pointerAuthority.CancelPointer(pending.Ticket, "interject_config_invalid_up");
        }

        private void CancelChromePointer(string reason)
        {
            if (_chromePointer is not { } pending) return;
            _chromePointer = null;
            _pointerAuthority.CancelPointer(pending.Ticket, reason);
            if (pending.Control.IsHandleCreated) pending.Control.Capture = false;
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

    }
}
