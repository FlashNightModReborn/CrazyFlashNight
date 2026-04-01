using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

namespace CF7Launcher.Guardian
{
    /// <summary>
    /// WebView2 透明覆盖层窗口。
    /// 作为独立顶层窗口悬浮于 Flash HWND 之上，承载 HTML/CSS/JS 渲染的 UI。
    ///
    /// Phase 0: PoC 验证 airspace + 点击穿透 + owner 跟随。
    /// Phase 1+: 实现 IToastSink / INotchSink 替代 GDI+ overlay。
    /// </summary>
    public class WebOverlayForm : Form, IToastSink, INotchSink, IDisposable
    {
        #region Win32

        [DllImport("user32.dll")]
        private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

        [DllImport("user32.dll")]
        private static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter,
            int X, int Y, int cx, int cy, uint uFlags);

        [DllImport("user32.dll")]
        private static extern int GetWindowLong(IntPtr hWnd, int nIndex);

        [DllImport("user32.dll")]
        private static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);

        private const int SW_SHOWNOACTIVATE = 4;
        private const int SW_HIDE = 0;
        private static readonly IntPtr HWND_TOP = new IntPtr(0);
        private const uint SWP_NOMOVE = 0x0002;
        private const uint SWP_NOSIZE = 0x0001;
        private const uint SWP_NOACTIVATE = 0x0010;

        private const int WS_EX_TOOLWINDOW = 0x00000080;
        private const int WS_EX_NOACTIVATE = 0x08000000;
        private const int WS_EX_LAYERED = 0x00080000;
        private const int WS_EX_TRANSPARENT = 0x00000020;
        private const int GWL_EXSTYLE = -20;

        #endregion

        private readonly Form _owner;
        private readonly Control _anchor;
        private readonly FlashCoordinateMapper _mapper;
        private WebView2 _webView;
        private bool _webReady;
        private bool _shown;
        private bool _ownerVisible;
        private bool _disposed;

        // 点击穿透切换
        private System.Windows.Forms.Timer _cursorTimer;
        private Rectangle _interactiveRect;
        private bool _isPassthrough;

        // IToastSink: 早期消息缓冲（WebView2 初始化前）
        private readonly List<string> _toastEarlyBuffer = new List<string>();
        private bool _toastReady;

        // INotchSink: FPS 推送 + 按钮委托
        private FpsRingBuffer _fpsBuffer;
        private System.Windows.Forms.Timer _fpsTimer;
        private Action _onToggleFullscreen;
        private Action _onToggleLog;
        private Action _onForceExit;
        private Action<Keys> _onSendKey;

        public WebOverlayForm(Form owner, Control anchor, string webDir)
        {
            _owner = owner;
            _anchor = anchor;
            _mapper = new FlashCoordinateMapper(anchor, 1024f, 576f);
            _webReady = false;
            _shown = false;
            _ownerVisible = true;
            _isPassthrough = true;

            this.FormBorderStyle = FormBorderStyle.None;
            this.ShowInTaskbar = false;
            this.StartPosition = FormStartPosition.Manual;
            this.Owner = owner;

            CreateHandle();

            // WebView2 控件
            _webView = new WebView2();
            _webView.Dock = DockStyle.Fill;
            this.Controls.Add(_webView);

            // Owner 跟随
            owner.Move += delegate { SyncPosition(); };
            owner.Resize += delegate
            {
                SyncPosition();
                if (owner.WindowState == FormWindowState.Minimized)
                    OnOwnerDeactivated();
                else
                    OnOwnerActivated();
            };
            anchor.Resize += delegate { SyncPosition(); };
            owner.Activated += delegate { OnOwnerActivated(); };
            owner.Deactivate += delegate { OnOwnerDeactivated(); };

            // 点击穿透轮询 (50ms)
            _cursorTimer = new System.Windows.Forms.Timer();
            _cursorTimer.Interval = 50;
            _cursorTimer.Tick += OnCursorTick;

            // 异步初始化 WebView2
            InitWebView2Async(webDir);
        }

        protected override CreateParams CreateParams
        {
            get
            {
                CreateParams cp = base.CreateParams;
                // 不加 WS_EX_LAYERED：WebView2 自己处理透明背景，
                // WS_EX_LAYERED 会导致逐像素命中检测（alpha=0 区域永远穿透）
                cp.ExStyle |= WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_TRANSPARENT;
                return cp;
            }
        }

        #region WebView2 初始化

        private async void InitWebView2Async(string webDir)
        {
            try
            {
                // UserData 目录放在 webDir 旁边，避免污染项目目录
                string userDataDir = Path.Combine(
                    Path.GetDirectoryName(webDir), "webview2_userdata");

                CoreWebView2Environment env =
                    await CoreWebView2Environment.CreateAsync(null, userDataDir);
                await _webView.EnsureCoreWebView2Async(env);

                // 透明背景
                _webView.DefaultBackgroundColor = Color.Transparent;

                // 虚拟主机映射：https://overlay.local/ → webDir/
                _webView.CoreWebView2.SetVirtualHostNameToFolderMapping(
                    "overlay.local", webDir,
                    CoreWebView2HostResourceAccessKind.Allow);

                // JS→C# 消息
                _webView.CoreWebView2.WebMessageReceived += OnWebMessageReceived;

                // 调试阶段保留开发者工具
                _webView.CoreWebView2.Settings.AreDevToolsEnabled = true;
                _webView.CoreWebView2.Settings.AreDefaultContextMenusEnabled = true;

                // 导航到 overlay 页面
                _webView.CoreWebView2.Navigate("https://overlay.local/overlay.html");

                _webReady = true;
                _cursorTimer.Start();

                // 如果 SetReady 已经被调用过，flush 早期缓冲
                if (_toastReady)
                    FlushToastBuffer();

                LogManager.Log("[WebOverlay] WebView2 initialized, navigating to overlay.html");
            }
            catch (Exception ex)
            {
                LogManager.Log("[WebOverlay] WebView2 init failed: " + ex.Message);
                // 降级：WebOverlayForm 静默不显示
            }
        }

        #endregion

        #region Owner 跟随

        private void SyncPosition()
        {
            try
            {
                float vpX, vpY, vpW, vpH;
                _mapper.CalcViewport(out vpX, out vpY, out vpW, out vpH);
                Point origin = _anchor.PointToScreen(Point.Empty);

                int x = origin.X + (int)vpX;
                int y = origin.Y + (int)vpY;
                int w = Math.Max(1, (int)vpW);
                int h = Math.Max(1, (int)vpH);

                SetWindowPos(this.Handle, HWND_TOP, x, y, w, h, SWP_NOACTIVATE);
            }
            catch
            {
                // anchor 可能已 disposed
            }
        }

        private void OnOwnerActivated()
        {
            _ownerVisible = true;
            if (_shown && _webReady)
            {
                ShowWindow(this.Handle, SW_SHOWNOACTIVATE);
                SetWindowPos(this.Handle, HWND_TOP, 0, 0, 0, 0,
                    SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
            }
        }

        private void OnOwnerDeactivated()
        {
            _ownerVisible = false;
            if (_shown)
                ShowWindow(this.Handle, SW_HIDE);
        }

        #endregion

        #region 点击穿透

        private int _dbgCounter;
        private static string _dbgFile;

        private static void DbgLog(string msg)
        {
            try
            {
                if (_dbgFile == null)
                    _dbgFile = Path.Combine(
                        Path.GetDirectoryName(typeof(WebOverlayForm).Assembly.Location),
                        "weboverlay_debug.log");
                File.AppendAllText(_dbgFile, DateTime.Now.ToString("HH:mm:ss.fff") + " " + msg + "\r\n");
            }
            catch { }
        }

        private void OnCursorTick(object sender, EventArgs e)
        {
            if (!_webReady || _disposed) return;

            try
            {
                Point cursor = Cursor.Position;
                Point winOrigin = this.Location;
                Rectangle screenRect = new Rectangle(
                    winOrigin.X + _interactiveRect.X,
                    winOrigin.Y + _interactiveRect.Y,
                    _interactiveRect.Width,
                    _interactiveRect.Height);
                bool inInteractive = screenRect.Width > 0
                    && screenRect.Contains(cursor);

                _dbgCounter++;
                if (_dbgCounter % 60 == 1)
                {
                    DbgLog("cursor=" + cursor.X + "," + cursor.Y
                        + " win=" + winOrigin.X + "," + winOrigin.Y
                        + " iRect=" + _interactiveRect
                        + " sRect=" + screenRect
                        + " in=" + inInteractive + " pass=" + _isPassthrough);
                }

                if (inInteractive && _isPassthrough)
                {
                    int ex = GetWindowLong(this.Handle, GWL_EXSTYLE);
                    SetWindowLong(this.Handle, GWL_EXSTYLE, ex & ~WS_EX_TRANSPARENT);
                    _isPassthrough = false;
                }
                else if (!inInteractive && !_isPassthrough)
                {
                    int ex = GetWindowLong(this.Handle, GWL_EXSTYLE);
                    SetWindowLong(this.Handle, GWL_EXSTYLE, ex | WS_EX_TRANSPARENT);
                    _isPassthrough = true;
                }
            }
            catch
            {
                // 窗口可能已 disposed
            }
        }

        #endregion

        #region JS ↔ C# 消息

        private void OnWebMessageReceived(object sender,
            CoreWebView2WebMessageReceivedEventArgs args)
        {
            try
            {
                string json = args.WebMessageAsJson;
                // 使用简单字符串匹配避免 JSON 依赖
                if (json.Contains("\"interactiveRect\""))
                {
                    // 解析交互区域 {type:"interactiveRect", x:N, y:N, w:N, h:N}
                    int x = ExtractInt(json, "\"x\":");
                    int y = ExtractInt(json, "\"y\":");
                    int w = ExtractInt(json, "\"w\":");
                    int h = ExtractInt(json, "\"h\":");
                    _interactiveRect = new Rectangle(x, y, w, h);
                    DbgLog("interactiveRect set: " + _interactiveRect);
                }
                else if (json.Contains("\"click\""))
                {
                    string key = ExtractString(json, "\"key\":\"");
                    if (key != null)
                        HandleButtonClick(key);
                }
                else if (json.Contains("\"ready\""))
                {
                    LogManager.Log("[WebOverlay] JS side ready");
                }
            }
            catch (Exception ex)
            {
                LogManager.Log("[WebOverlay] WebMessage error: " + ex.Message);
            }
        }

        /// <summary>向 JS 发送结构化消息。</summary>
        public void PostToWeb(string json)
        {
            if (!_webReady || _disposed) return;
            try
            {
                _webView.CoreWebView2.PostWebMessageAsJson(json);
            }
            catch { }
        }

        /// <summary>执行 JS 代码。</summary>
        public void ExecScript(string js)
        {
            if (!_webReady || _disposed) return;
            try
            {
                _webView.CoreWebView2.ExecuteScriptAsync(js);
            }
            catch { }
        }

        #endregion

        #region Notch 注入

        /// <summary>
        /// 注入 Notch 所需的依赖。在 FrameTask 创建后调用。
        /// </summary>
        public void SetNotchDependencies(FpsRingBuffer fpsBuffer,
            Action onToggleFullscreen, Action onToggleLog,
            Action onForceExit, Action<Keys> onSendKey)
        {
            _fpsBuffer = fpsBuffer;
            _onToggleFullscreen = onToggleFullscreen;
            _onToggleLog = onToggleLog;
            _onForceExit = onForceExit;
            _onSendKey = onSendKey;

            // FPS 推送 timer (1Hz)
            _fpsTimer = new System.Windows.Forms.Timer();
            _fpsTimer.Interval = 1000;
            _fpsTimer.Tick += OnFpsTick;
        }

        private void OnFpsTick(object sender, EventArgs e)
        {
            if (!_webReady || _disposed || _fpsBuffer == null) return;
            if (!_fpsBuffer.HasData) return;

            // 构建 JSON: {type:"fps", value:N, hour:N, points:[...]}
            System.Text.StringBuilder sb = new System.Text.StringBuilder(256);
            sb.Append("{\"type\":\"fps\",\"value\":");
            sb.Append(Math.Round(_fpsBuffer.Latest));
            sb.Append(",\"hour\":");
            sb.Append(_fpsBuffer.GameHour);
            sb.Append(",\"points\":[");
            int count = _fpsBuffer.Count;
            int start = Math.Max(0, count - 30);
            for (int i = start; i < count; i++)
            {
                if (i > start) sb.Append(',');
                sb.Append(Math.Round(_fpsBuffer.GetAt(i)));
            }
            sb.Append("]}");
            PostToWeb(sb.ToString());
        }

        #endregion

        #region INotchSink

        public void AddNotice(string category, string text, Color accentColor)
        {
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action<string, string, Color>(AddNotice),
                    category, text, accentColor);
                return;
            }
            if (!_webReady || _disposed) return;
            string hex = accentColor.R.ToString("x2") + accentColor.G.ToString("x2") + accentColor.B.ToString("x2");
            string escaped = text.Replace("\\", "\\\\").Replace("'", "\\'");
            ExecScript("typeof Notch!=='undefined'&&Notch.addNotice('" + category + "','" + escaped + "','#" + hex + "')");
        }

        public void SetStatusItem(string id, string label, string subLabel, Color accentColor)
        {
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action<string, string, string, Color>(SetStatusItem),
                    id, label, subLabel, accentColor);
                return;
            }
            if (!_webReady || _disposed) return;
            string text = label;
            if (!string.IsNullOrEmpty(subLabel)) text += "  " + subLabel;
            string hex = accentColor.R.ToString("x2") + accentColor.G.ToString("x2") + accentColor.B.ToString("x2");
            string escaped = text.Replace("\\", "\\\\").Replace("'", "\\'");
            ExecScript("typeof Notch!=='undefined'&&Notch.setStatus('" + id + "','" + escaped + "','#" + hex + "')");
        }

        public void ClearStatusItem(string id)
        {
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action<string>(ClearStatusItem), id);
                return;
            }
            if (!_webReady || _disposed) return;
            ExecScript("typeof Notch!=='undefined'&&Notch.clearStatus('" + id + "')");
        }

        #endregion

        #region IToastSink

        public void AddMessage(string text)
        {
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action<string>(AddMessage), text);
                return;
            }
            if (!_toastReady)
            {
                _toastEarlyBuffer.Add(text);
                return;
            }
            SendToast(text);
        }

        private void SendToast(string text)
        {
            if (!_webReady || _disposed) return;
            // 转义反斜杠和单引号，保留 HTML 标签原样传给 JS innerHTML
            string escaped = text.Replace("\\", "\\\\").Replace("'", "\\'").Replace("\n", "\\n").Replace("\r", "");
            ExecScript("typeof Toast!=='undefined'&&Toast.add('" + escaped + "')");
        }

        private void FlushToastBuffer()
        {
            foreach (string msg in _toastEarlyBuffer)
                SendToast(msg);
            _toastEarlyBuffer.Clear();
        }

        #endregion

        #region 生命周期

        /// <summary>
        /// 激活 overlay 显示。在 Flash 窗口嵌入完成后调用。
        /// </summary>
        public void SetReady()
        {
            if (_disposed) return;
            _shown = true;
            _toastReady = true;
            if (_webReady)
                FlushToastBuffer();
            if (_fpsTimer != null)
                _fpsTimer.Start();
            if (_webReady && _ownerVisible)
            {
                SyncPosition();
                ShowWindow(this.Handle, SW_SHOWNOACTIVATE);
                SetWindowPos(this.Handle, HWND_TOP, 0, 0, 0, 0,
                    SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
            }
        }

        protected override void Dispose(bool disposing)
        {
            if (_disposed) return;
            _disposed = true;

            if (disposing)
            {
                if (_fpsTimer != null)
                {
                    _fpsTimer.Stop();
                    _fpsTimer.Dispose();
                    _fpsTimer = null;
                }
                if (_cursorTimer != null)
                {
                    _cursorTimer.Stop();
                    _cursorTimer.Dispose();
                    _cursorTimer = null;
                }
                if (_webView != null)
                {
                    _webView.Dispose();
                    _webView = null;
                }
            }

            base.Dispose(disposing);
            LogManager.Log("[WebOverlay] Disposed");
        }

        #endregion

        #region 辅助方法

        private void HandleButtonClick(string key)
        {
            switch (key)
            {
                case "Q": if (_onSendKey != null) _onSendKey(Keys.Q); break;
                case "W": if (_onSendKey != null) _onSendKey(Keys.W); break;
                case "R": if (_onSendKey != null) _onSendKey(Keys.R); break;
                case "F": if (_onToggleFullscreen != null) _onToggleFullscreen(); break;
                case "P": if (_onSendKey != null) _onSendKey(Keys.P); break;
                case "O": if (_onSendKey != null) _onSendKey(Keys.O); break;
                case "LOG": if (_onToggleLog != null) _onToggleLog(); break;
                case "EXIT": if (_onForceExit != null) _onForceExit(); break;
            }
        }

        private static int ExtractInt(string json, string key)
        {
            int idx = json.IndexOf(key);
            if (idx < 0) return 0;
            idx += key.Length;
            int end = idx;
            while (end < json.Length && (char.IsDigit(json[end]) || json[end] == '-'))
                end++;
            int val;
            if (int.TryParse(json.Substring(idx, end - idx), out val))
                return val;
            return 0;
        }

        private static string ExtractString(string json, string key)
        {
            int idx = json.IndexOf(key);
            if (idx < 0) return null;
            idx += key.Length;
            int end = json.IndexOf('"', idx);
            if (end < 0) return null;
            return json.Substring(idx, end - idx);
        }

        #endregion
    }
}
