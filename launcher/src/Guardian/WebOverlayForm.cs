using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;
using CF7Launcher.Bus;

namespace CF7Launcher.Guardian
{
    /// <summary>
    /// WebView2 透明覆盖层窗口。
    /// 作为独立顶层窗口悬浮于 Flash HWND 之上，承载 HTML/CSS/JS 渲染的 UI。
    ///
    /// 透明度架构：
    /// - Form.TransparencyKey + WS_EX_LAYERED 实现像素级透明
    /// - TransparencyKey 颜色像素：视觉透明 + 点击穿透（无需轮询切换）
    /// - 非 TransparencyKey 像素（notch/toast）：可见 + 可点击
    /// </summary>
    public class WebOverlayForm : Form, IToastSink, INotchSink, IDisposable
    {
        #region Win32

        [DllImport("user32.dll")]
        private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

        [DllImport("user32.dll")]
        private static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter,
            int X, int Y, int cx, int cy, uint uFlags);

        private const int SW_SHOWNOACTIVATE = 4;
        private static readonly IntPtr HWND_TOP = new IntPtr(0);
        private const uint SWP_NOMOVE = 0x0002;
        private const uint SWP_NOSIZE = 0x0001;
        private const uint SWP_NOACTIVATE = 0x0010;

        private const int WS_EX_TOOLWINDOW = 0x00000080;
        private const int WS_EX_NOACTIVATE = 0x08000000;
        private const int WS_EX_TRANSPARENT = 0x00000020;

        #endregion

        /// <summary>
        /// TransparencyKey 颜色。选择极暗色 (1,1,1)：
        /// - 与 HTML 暗色背景 rgba(24,24,26) 反差小，抗锯齿边缘几乎无色差
        /// - 几乎不可能与实际内容颜色冲突
        /// </summary>
        private static readonly Color TRANSPARENT_COLOR = Color.FromArgb(1, 1, 1);

        private readonly Form _owner;
        private readonly Control _anchor;
        private readonly FlashCoordinateMapper _mapper;
        private WebView2 _webView;
        private bool _webReady;
        private bool _shown;
        private bool _disposed;

        // GDI+ fallback：WebView2 未就绪或初始化失败时，消息转发到 GDI+ overlay
        private IToastSink _toastFallback;
        private INotchSink _notchFallback;
        private bool _webFailed; // 初始化永久失败，所有后续消息走 fallback

        // IToastSink: 早期消息缓冲（WebView2 初始化前）
        private readonly List<string> _toastEarlyBuffer = new List<string>();
        private bool _toastReady;

        // UI 数据早期缓冲：WebView2 就绪前收到的状态数据，就绪后 flush
        private readonly List<string> _uiDataEarlyBuffer = new List<string>();

        // InputShieldForm 引用（CDP 输入注入 + hitRects 转发）
        private InputShieldForm _inputShield;

        // 光照等级（静态 24h 数组，初始化后一次性推送给 JS）
        private int[] _lightLevels;

        // INotchSink: FPS 推送 + 按钮委托
        private FpsRingBuffer _fpsBuffer;
        private System.Windows.Forms.Timer _fpsTimer;
        private Action _onToggleFullscreen;
        private Action _onToggleLog;
        private Action _onForceExit;
        private Action<Keys> _onSendKey;

        // 游戏命令通道
        private XmlSocketServer _socketServer;

        public WebOverlayForm(Form owner, Control anchor, string webDir)
        {
            _owner = owner;
            _anchor = anchor;
            _mapper = new FlashCoordinateMapper(anchor, 1024f, 576f);
            _webReady = false;
            _shown = false;

            this.FormBorderStyle = FormBorderStyle.None;
            this.ShowInTaskbar = false;
            this.StartPosition = FormStartPosition.Manual;

            // 像素级透明：BackColor = TransparencyKey → 匹配像素视觉透明 + 点击穿透
            this.BackColor = TRANSPARENT_COLOR;
            this.TransparencyKey = TRANSPARENT_COLOR;

            this.Owner = owner;

            CreateHandle();

            // WebView2 控件
            _webView = new WebView2();
            _webView.Dock = DockStyle.Fill;
            this.Controls.Add(_webView);

            // Owner 跟随：Move/Resize → 同步位置
            owner.Move += delegate { SyncPosition(); };
            owner.Resize += delegate
            {
                SyncPosition();
                // 从最小化恢复时重新显示（Win32 owned 窗口最小化时自动隐藏，
                // 但 ShowWindow(SW_SHOWNOACTIVATE) 创建的窗口可能不自动恢复）
                if (owner.WindowState != FormWindowState.Minimized && _shown && _webReady)
                {
                    ShowWindow(this.Handle, SW_SHOWNOACTIVATE);
                }
            };
            anchor.Resize += delegate { SyncPosition(); };

            // 异步初始化 WebView2
            InitWebView2Async(webDir);
        }

        /// <summary>注入 GDI+ fallback。WebView2 未就绪或失败时消息走这里。</summary>
        public void SetFallback(IToastSink toastFallback, INotchSink notchFallback)
        {
            _toastFallback = toastFallback;
            _notchFallback = notchFallback;
        }

        /// <summary>注入 InputShieldForm 引用。若 WebView2 已就绪，立即补调 SetTargetWebView。</summary>
        public void SetInputShield(InputShieldForm shield)
        {
            _inputShield = shield;
            // 防时序漏洞：如果 WebView2 已经 ready（先于 shield 注入），补调
            if (_webReady && _inputShield != null && _webView != null && _webView.CoreWebView2 != null)
                _inputShield.SetTargetWebView(_webView.CoreWebView2);
        }

        protected override CreateParams CreateParams
        {
            get
            {
                CreateParams cp = base.CreateParams;
                // WS_EX_TOOLWINDOW: 不出现在任务栏和 Alt-Tab 列表
                // WS_EX_NOACTIVATE: 顶层窗口点击时不变前台
                // WS_EX_TRANSPARENT: 永久点击穿透，所有鼠标事件直达 Flash
                //   Phase 0: overlay 纯视觉层，交互走键盘快捷键
                //   Phase 1: 可探索 cursor polling 或 InputHost 方案恢复 notch 鼠标交互
                cp.ExStyle |= WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_TRANSPARENT;
                return cp;
            }
        }

        protected override bool ShowWithoutActivation
        {
            get { return true; }
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

                // 透明背景：WebView2 透明区域显示 Form BackColor (=TransparencyKey) → 视觉穿透
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
                // _webReady 延迟到 JS "ready" 消息到达时才置真（OnWebMessageReceived）
                _webView.CoreWebView2.Navigate("https://overlay.local/overlay.html");

                // 把 CoreWebView2 传给 InputShieldForm 供 CDP 注入（不依赖 _webReady）
                if (_inputShield != null)
                    _inputShield.SetTargetWebView(_webView.CoreWebView2);

                LogManager.Log("[WebOverlay] WebView2 engine ready, waiting for JS ready...");
            }
            catch (Exception ex)
            {
                LogManager.Log("[WebOverlay] WebView2 init failed, falling back to GDI+: " + ex.Message);
                _webFailed = true;
                // 激活 GDI+ fallback 并 flush 早期缓冲
                ActivateFallback();
            }
        }

        /// <summary>WebView2 初始化失败时，激活 GDI+ fallback 并 flush 早期消息。</summary>
        private void ActivateFallback()
        {
            if (_toastFallback != null)
            {
                // 先 SetReady fallback（如果还没 ready）
                _toastFallback.SetReady();
                // flush 早期缓冲到 GDI+
                foreach (string msg in _toastEarlyBuffer)
                    _toastFallback.AddMessage(msg);
                _toastEarlyBuffer.Clear();
            }
            if (_notchFallback != null)
                _notchFallback.SetReady();
        }

        #endregion

        #region Owner 跟随

        /// <summary>当前缩放比（viewport 实际高度 / Flash 设计高度 576）。</summary>
        private double _zoomFactor = 1.0;

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

                // WebView2 缩放：viewport 实际高度 / Flash 设计高度
                double newZoom = Math.Max(0.25, vpH / 576.0);
                if (_webReady && _webView != null && Math.Abs(newZoom - _zoomFactor) > 0.001)
                {
                    _zoomFactor = newZoom;
                    _webView.ZoomFactor = _zoomFactor;
                    if (_inputShield != null)
                        _inputShield.SetZoomFactor(_zoomFactor);
                }
            }
            catch
            {
                // anchor 可能已 disposed
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
                if (json.Contains("\"interactiveRect\""))
                {
                    // JS 上报多矩形交互区域（CSS 像素 flat array）→ 缩放为物理像素 → 转发
                    double z = _zoomFactor;
                    List<Rectangle> rects = new List<Rectangle>();
                    int arrStart = json.IndexOf('[');
                    int arrEnd = json.IndexOf(']');
                    if (arrStart >= 0 && arrEnd > arrStart)
                    {
                        string nums = json.Substring(arrStart + 1, arrEnd - arrStart - 1);
                        string[] parts = nums.Split(',');
                        for (int pi = 0; pi + 3 < parts.Length; pi += 4)
                        {
                            int rx, ry, rw, rh;
                            if (int.TryParse(parts[pi].Trim(), out rx) &&
                                int.TryParse(parts[pi + 1].Trim(), out ry) &&
                                int.TryParse(parts[pi + 2].Trim(), out rw) &&
                                int.TryParse(parts[pi + 3].Trim(), out rh))
                            {
                                rx = (int)(rx * z); ry = (int)(ry * z);
                                rw = (int)(rw * z); rh = (int)(rh * z);
                                if (rw > 0 && rh > 0)
                                    rects.Add(new Rectangle(rx, ry, rw, rh));
                            }
                        }
                    }
                    if (_inputShield != null && rects.Count > 0)
                        _inputShield.UpdateHitRects(rects);
                }
                else if (json.Contains("\"click\""))
                {
                    string key = ExtractString(json, "\"key\":\"");
                    if (key != null)
                        HandleButtonClick(key);
                }
                else if (json.Contains("\"ready\""))
                {
                    LogManager.Log("[WebOverlay] JS side ready → activating web channel");
                    _webReady = true;

                    // flush 早期缓冲
                    if (_toastReady)
                        FlushToastBuffer();
                    FlushUiDataBuffer();

                    // 显示 overlay（如果 SetReady 已先调用）
                    if (_shown)
                    {
                        SyncPosition();
                        ShowWindow(this.Handle, SW_SHOWNOACTIVATE);
                        SetWindowPos(this.Handle, HWND_TOP, 0, 0, 0, 0,
                            SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
                    }

                    // 一次性推送光照等级静态数据
                    PushLightLevels();

                    // 通知 GDI+ fallback 它可以退出了（如果之前在顶着）
                    // 不需要——fallback 继续运行也无害，_webReady=true 后消息走 Web 通道
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

        /// <summary>注入光照等级数据（24 元素数组）。</summary>
        public void SetLightLevels(int[] levels)
        {
            _lightLevels = levels;
        }

        /// <summary>将光照等级数组一次性推送给 JS。</summary>
        private void PushLightLevels()
        {
            if (_lightLevels == null || _lightLevels.Length < 24) return;
            System.Text.StringBuilder sb = new System.Text.StringBuilder(128);
            sb.Append("{\"type\":\"lightLevels\",\"levels\":[");
            for (int i = 0; i < 24; i++)
            {
                if (i > 0) sb.Append(',');
                sb.Append(_lightLevels[i]);
            }
            sb.Append("]}");
            PostToWeb(sb.ToString());
        }

        /// <summary>注入 XmlSocketServer 用于发送游戏命令（pause 等）。</summary>
        public void SetSocketServer(XmlSocketServer server)
        {
            _socketServer = server;
        }

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
            sb.Append(Math.Round(_fpsBuffer.Latest * 10) / 10.0); // 1 位小数
            sb.Append(",\"hour\":");
            sb.Append(_fpsBuffer.GameHour);
            sb.Append(",\"level\":");
            sb.Append(_fpsBuffer.PerfLevel);
            sb.Append(",\"points\":[");
            int count = _fpsBuffer.Count;
            int start = Math.Max(0, count - 30);
            for (int i = start; i < count; i++)
            {
                if (i > start) sb.Append(',');
                sb.Append(Math.Round(_fpsBuffer.GetAt(i) * 10) / 10.0);
            }
            sb.Append("]}");
            PostToWeb(sb.ToString());
        }

        #endregion

        #region UI 数据快车道 (U 前缀)

        /// <summary>
        /// 处理 U 前缀 payload，零解析转发到 JS。
        /// 格式：{type}|{field1}|{field2}|...
        /// JS 端 UiData.dispatch(type, fields[]) 负责分发。
        /// </summary>
        public void HandleUiData(string payload)
        {
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action<string>(HandleUiData), payload);
                return;
            }
            if (_disposed || _webFailed) return; // 永久失败时丢弃（UI 数据无 GDI+ fallback）
            if (!_webReady)
            {
                // WebView2 未就绪，缓冲（上限 200 条防止内存泄漏）
                if (_uiDataEarlyBuffer.Count < 200)
                    _uiDataEarlyBuffer.Add(payload);
                return;
            }
            string escaped = payload.Replace("\\", "\\\\").Replace("'", "\\'");
            ExecScript("typeof UiData!=='undefined'&&UiData.dispatch('" + escaped + "')");
        }

        private void FlushUiDataBuffer()
        {
            foreach (string p in _uiDataEarlyBuffer)
                HandleUiData(p);
            _uiDataEarlyBuffer.Clear();
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
            if (_webFailed || !_webReady || _disposed) { if (_notchFallback != null) _notchFallback.AddNotice(category, text, accentColor); return; }
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
            if (_webFailed || !_webReady || _disposed) { if (_notchFallback != null) _notchFallback.SetStatusItem(id, label, subLabel, accentColor); return; }
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
            if (_webFailed || !_webReady || _disposed) { if (_notchFallback != null) _notchFallback.ClearStatusItem(id); return; }
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
            // WebView2 初始化失败 → 永久走 GDI+ fallback
            if (_webFailed)
            {
                if (_toastFallback != null) _toastFallback.AddMessage(text);
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
            if (!_webReady || _disposed)
            {
                // JS 还没 ready → 走 GDI+ fallback，不丢弃
                if (_toastFallback != null) _toastFallback.AddMessage(text);
                return;
            }
            string escaped = EscapeForJs(text);
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
            if (_webReady)
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
                case "PAUSE": SendGameCommand("togglePause"); break;
                case "WAREHOUSE": SendGameCommand("warehouse"); break;
                case "SETTINGS": SendGameCommand("toggleSettings"); break;
                case "SHOP": SendGameCommand("openShop"); break;
                case "HELP": SendGameCommand("openHelp"); break;
                case "SAFEEXIT": SendGameCommand("safeExit"); break;
                case "PETS": SendGameCommand("togglePets"); break;
                case "MERCS": SendGameCommand("toggleMercs"); break;
                case "TABLET": SendGameCommand("toggleTablet"); break;
                case "GAMESETTINGS": SendGameCommand("openSettings"); break;
                case "JUKEBOX": SendGameCommand("openJukebox"); break;
            }
        }

        /// <summary>通过 XmlSocket 向 AS2 发送游戏命令。</summary>
        private void SendGameCommand(string action)
        {
            if (_socketServer == null) return;
            _socketServer.Send("{\"task\":\"cmd\",\"action\":\"" + action + "\"}\0");
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

        /// <summary>转义字符串供 JS 单引号字面量使用。</summary>
        private static string EscapeForJs(string text)
        {
            return text.Replace("\\", "\\\\").Replace("'", "\\'").Replace("\n", "\\n").Replace("\r", "");
        }

        #endregion
    }
}
