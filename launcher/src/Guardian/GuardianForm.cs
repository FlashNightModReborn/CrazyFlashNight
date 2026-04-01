using System;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;
using System.Diagnostics;
using CF7Launcher.Config;
using CF7Launcher.Render;

namespace CF7Launcher.Guardian
{
    public class GuardianForm : Form
    {
        [DllImport("user32.dll")]
        private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

        [DllImport("user32.dll")]
        private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

        [DllImport("user32.dll")]
        private static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

        [DllImport("user32.dll")]
        private static extern bool SetForegroundWindow(IntPtr hWnd);

        [DllImport("user32.dll")]
        private static extern bool PostMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);

        [DllImport("user32.dll")]
        private static extern uint MapVirtualKey(uint uCode, uint uMapType);

        private const uint MOD_CONTROL = 0x0002;
        private const int WM_HOTKEY = 0x0312;
        private const uint KEYEVENTF_KEYUP = 0x0002;
        private const int WM_KEYDOWN = 0x0100;
        private const int WM_KEYUP = 0x0101;
        private const int WM_CHAR = 0x0102;
        private const int WM_SYSKEYDOWN = 0x0104;
        private const int WM_SYSKEYUP = 0x0105;
        private const int WM_MOUSEMOVE = 0x0200;
        private const int WM_LBUTTONDOWN = 0x0201;
        private const int WM_LBUTTONUP = 0x0202;
        private const int WM_LBUTTONDBLCLK = 0x0203;
        private const int WM_RBUTTONDOWN = 0x0204;
        private const int WM_RBUTTONUP = 0x0205;
        private const int WM_RBUTTONDBLCLK = 0x0206;
        private const int WM_MBUTTONDOWN = 0x0207;
        private const int WM_MBUTTONUP = 0x0208;
        private const int WM_MBUTTONDBLCLK = 0x0209;
        private const int WM_MOUSEWHEEL = 0x020A;
        private const int WM_XBUTTONDOWN = 0x020B;
        private const int WM_XBUTTONUP = 0x020C;
        private const int WM_XBUTTONDBLCLK = 0x020D;
        private const int MK_LBUTTON = 0x0001;
        private const int MK_RBUTTON = 0x0002;
        private const int MK_SHIFT = 0x0004;
        private const int MK_CONTROL = 0x0008;
        private const int MK_MBUTTON = 0x0010;
        private const int MK_XBUTTON1 = 0x0020;
        private const int MK_XBUTTON2 = 0x0040;
        private const uint MAPVK_VK_TO_VSC = 0;
        private const int GpuPaintIntervalMs = 33;
        private const int GpuCaptureStripWidth = 16;

        public const int DefaultGpuCaptureWidth = 1024;
        public const int DefaultGpuCaptureHeight = 576;

        // RegisterHotKey ID（仅 Guardian 自身动作）
        private const int HK_CTRL_F = 0xCF01;
        private const int HK_CTRL_Q = 0xCF02;
        private const int HK_ESC = 0xCF10;

        // 工具栏按钮键
        private static readonly Keys[] AllHotkeyKeys = { Keys.Q, Keys.W, Keys.R, Keys.F, Keys.P, Keys.O };

        private NotifyIcon _trayIcon;
        private ContextMenuStrip _trayMenu;
        private TextBox _logBox;
        private D3DPanel _flashPanel;
        private Panel _gpuCaptureStrip;
        private System.Windows.Forms.Timer _gpuPaintTimer;
        private Panel _logBar;
        private TextBox _searchBox;
        private int _searchPos;
        private bool _logVisible;
        private int _logBarH = 180;

        private bool _isFullscreen;
        private Rectangle _savedBounds;
        private FormBorderStyle _savedBorderStyle;

        private bool _hotkeysRegistered;

        private Process _flashProcess;
        private System.Windows.Forms.Timer _exitWatchdog;

        private WindowManager _windowManager;

        private GpuRenderer _gpuRenderer;
        private bool _gpuMode;
        private bool _gpuFallbackPending;

        /// <summary>Flash 嵌入目标：始终是 _flashPanel。</summary>
        public Panel FlashHostPanel { get { return _flashPanel; } }
        public Panel GpuCaptureHostPanel { get { return _gpuCaptureStrip; } }

        public void SetGpuCaptureHostVisible(bool visible)
        {
            if (!this.IsHandleCreated)
            {
                _gpuCaptureStrip.Visible = visible;
                return;
            }

            if (this.InvokeRequired)
            {
                if (!this.IsDisposed)
                    this.BeginInvoke(new Action<bool>(SetGpuCaptureHostVisible), visible);
                return;
            }

            _gpuCaptureStrip.Visible = visible;
        }

        public GuardianForm()
        {
            InitializeComponent();
            SetupTrayIcon();
            SetupHotkeys();
            LogManager.Init(this, _logBox);
        }

        public void BindWindowManager(WindowManager wm) { _windowManager = wm; }



        public bool InitGpuRenderer(AppConfig config)
        {
            if (this.InvokeRequired)
            {
                bool started = false;
                this.Invoke(new MethodInvoker(delegate { started = InitGpuRenderer(config); }));
                return started;
            }

            if (_windowManager == null || _windowManager.FlashHwnd == IntPtr.Zero)
            {
                LogManager.Log("[Guardian] GPU init skipped: Flash window not ready");
                return false;
            }

            StopGpuRenderer();

            GpuRenderer renderer = new GpuRenderer();
            renderer.Sharpness = config.Sharpness;
            renderer.OnFallbackRequested += OnGpuFallbackRequested;

            if (!renderer.Init(DefaultGpuCaptureWidth, DefaultGpuCaptureHeight))
            {
                renderer.OnFallbackRequested -= OnGpuFallbackRequested;
                renderer.Dispose();
                LogManager.Log("[Guardian] GPU renderer init failed");
                return false;
            }

            _gpuRenderer = renderer;
            _gpuMode = true;
            _gpuFallbackPending = false;
            SetGpuCaptureHostVisible(true);
            _flashPanel.Renderer = renderer;
            EnsureGpuPaintTimer();
            _gpuPaintTimer.Start();
            renderer.StartRenderLoop(_windowManager.FlashHwnd);
            _flashPanel.Focus();
            _flashPanel.Invalidate();
            LogManager.Log("[Guardian] GPU post-processing enabled");
            return true;
        }

        public void StopGpuRenderer()
        {
            if (this.InvokeRequired)
            {
                if (this.IsHandleCreated && !this.IsDisposed)
                    this.BeginInvoke(new Action(StopGpuRenderer));
                return;
            }

            if (_gpuPaintTimer != null)
                _gpuPaintTimer.Stop();

            if (_gpuRenderer != null)
            {
                _gpuRenderer.OnFallbackRequested -= OnGpuFallbackRequested;
                _gpuRenderer.Dispose();
                _gpuRenderer = null;
            }

            _flashPanel.Renderer = null;
            _gpuMode = false;
            _gpuFallbackPending = false;
            _flashPanel.Invalidate();
        }

        public void TrackFlashProcess(Process p)
        {
            _flashProcess = p;
            if (_exitWatchdog == null)
            {
                _exitWatchdog = new System.Windows.Forms.Timer();
                _exitWatchdog.Interval = 500;
                _exitWatchdog.Tick += delegate
                {
                    if (_flashProcess != null && _flashProcess.HasExited)
                    {
                        _exitWatchdog.Stop();
                        LogManager.Log("[Guardian] Flash exit detected by watchdog");
                        ForceExit();
                    }
                };
            }
            _exitWatchdog.Start();
        }

        // ============================================================
        //  布局
        // ============================================================

        private void InitializeComponent()
        {
            this.Text = "CF7:ME";
            this.Size = new Size(1280, 660);
            this.MinimumSize = new Size(800, 480);
            this.StartPosition = FormStartPosition.CenterScreen;
            this.FormBorderStyle = FormBorderStyle.Sizable;
            this.BackColor = Color.Black;

            Font uiFont = new Font("Microsoft YaHei UI", 8.25f);

            // ── 底部日志控制台 ──
            _logBar = new Panel();
            _logBar.Dock = DockStyle.Bottom;
            _logBar.Height = 0;
            _logBar.Visible = false;
            _logBar.BackColor = Color.FromArgb(20, 20, 22);

            // 拖拽手柄
            Panel dragHandle = new Panel();
            dragHandle.Dock = DockStyle.Top;
            dragHandle.Height = 4;
            dragHandle.BackColor = Color.FromArgb(56, 56, 60);
            dragHandle.Cursor = Cursors.HSplit;

            bool dragging = false;
            int dragStartY = 0;
            int dragStartH = 0;

            dragHandle.MouseDown += delegate(object s, MouseEventArgs e)
            {
                if (e.Button == MouseButtons.Left)
                {
                    dragging = true;
                    dragStartY = Cursor.Position.Y;
                    dragStartH = _logBar.Height;
                    dragHandle.Capture = true;
                }
            };
            dragHandle.MouseMove += delegate(object s, MouseEventArgs e)
            {
                if (!dragging) return;
                int delta = dragStartY - Cursor.Position.Y;
                int newH = dragStartH + delta;
                newH = Math.Max(60, Math.Min(newH, this.ClientSize.Height - 100));
                _logBar.Height = newH;
            };
            dragHandle.MouseUp += delegate
            {
                dragging = false;
                dragHandle.Capture = false;
            };

            // 搜索栏
            Panel searchBar = new Panel();
            searchBar.Dock = DockStyle.Top;
            searchBar.Height = 24;
            searchBar.BackColor = Color.FromArgb(28, 28, 30);
            searchBar.Padding = new Padding(4, 2, 4, 2);

            _searchBox = new TextBox();
            _searchBox.Dock = DockStyle.Fill;
            _searchBox.Font = new Font("Consolas", 8);
            _searchBox.BackColor = Color.FromArgb(36, 36, 40);
            _searchBox.ForeColor = Color.FromArgb(200, 200, 200);
            _searchBox.BorderStyle = BorderStyle.FixedSingle;
            _searchBox.KeyDown += OnSearchKeyDown;
            searchBar.Controls.Add(_searchBox);

            Label searchHint = new Label();
            searchHint.Text = "\u641C\u7D22";
            searchHint.Dock = DockStyle.Left;
            searchHint.Width = 36;
            searchHint.Font = uiFont;
            searchHint.ForeColor = Color.FromArgb(100, 100, 100);
            searchHint.TextAlign = ContentAlignment.MiddleLeft;
            searchBar.Controls.Add(searchHint);

            _logBox = new TextBox();
            _logBox.Multiline = true;
            _logBox.ReadOnly = true;
            _logBox.ScrollBars = ScrollBars.Both;
            _logBox.Dock = DockStyle.Fill;
            _logBox.Font = new Font("Consolas", 8);
            _logBox.BackColor = Color.FromArgb(16, 16, 18);
            _logBox.ForeColor = Color.FromArgb(160, 160, 160);
            _logBox.BorderStyle = BorderStyle.None;
            _logBox.WordWrap = false;
            _logBox.HideSelection = false;

            // Fill 先加（最高 z-order → 最后布局）
            _logBar.Controls.Add(_logBox);
            _logBar.Controls.Add(searchBar);
            _logBar.Controls.Add(dragHandle);

            this.Controls.Add(_logBar);

            // ── Flash 宿主（单 Panel + GPU overlay 架构）──
            // Flash 嵌入 _flashPanel。GPU 模式下，在 _flashPanel 内部创建
            // _gpuOverlay 子 Panel 覆盖在 Flash HWND 之上，SwapChain 渲染到 overlay。
            _flashPanel = new D3DPanel();
            _flashPanel.Dock = DockStyle.Fill;
            _flashPanel.BackColor = Color.Black;
            _flashPanel.MouseEnter += OnFlashPanelMouseEnter;
            _flashPanel.MouseDown += OnFlashPanelMouseDown;
            _flashPanel.MouseUp += OnFlashPanelMouseUp;
            _flashPanel.MouseMove += OnFlashPanelMouseMove;
            _flashPanel.MouseWheel += OnFlashPanelMouseWheel;
            _flashPanel.MouseDoubleClick += OnFlashPanelMouseDoubleClick;
            _flashPanel.KeyDown += OnFlashPanelKeyDown;
            _flashPanel.KeyUp += OnFlashPanelKeyUp;
            _flashPanel.KeyPress += OnFlashPanelKeyPress;
            this.Controls.Add(_flashPanel);

            _gpuCaptureStrip = new Panel();
            _gpuCaptureStrip.Dock = DockStyle.Right;
            _gpuCaptureStrip.Width = GpuCaptureStripWidth;
            _gpuCaptureStrip.BackColor = Color.Black;
            _gpuCaptureStrip.Visible = false;
            this.Controls.Add(_gpuCaptureStrip);

            this.FormClosing += OnFormClosing;
        }

        // ============================================================
        //  热键：仅注册 Guardian 自身动作（Ctrl+F 全屏、Ctrl+Q 退出）
        //  Flash SA 的原生快捷键由 WindowManager.SetMenu(null) 从源头禁用
        // ============================================================

        private void SetupHotkeys()
        {
            System.Windows.Forms.Timer t = new System.Windows.Forms.Timer();
            t.Interval = 200;
            t.Tick += delegate
            {
                if (!this.IsHandleCreated) return;
                t.Stop();
                t.Dispose();
                DoRegisterHotkeys();
            };
            t.Start();
        }

        private void DoRegisterHotkeys()
        {
            if (_hotkeysRegistered) return;
            bool f = RegisterHotKey(this.Handle, HK_CTRL_F, MOD_CONTROL, (uint)Keys.F);
            bool q = RegisterHotKey(this.Handle, HK_CTRL_Q, MOD_CONTROL, (uint)Keys.Q);
            _hotkeysRegistered = true;
            LogManager.Log("[Hotkey] Ctrl+F=" + f + " Ctrl+Q=" + q);
        }

        private void DoUnregisterHotkeys()
        {
            if (!_hotkeysRegistered) return;
            UnregisterHotKey(this.Handle, HK_CTRL_F);
            UnregisterHotKey(this.Handle, HK_CTRL_Q);
            UnregisterHotKey(this.Handle, HK_ESC);
            _hotkeysRegistered = false;
        }

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == WM_HOTKEY)
            {
                int id = m.WParam.ToInt32();
                if (id == HK_ESC || id == HK_CTRL_F)
                {
                    ToggleFullscreen();
                    return;
                }
                if (id == HK_CTRL_Q)
                {
                    ForceExit();
                    return;
                }
            }
            base.WndProc(ref m);
        }

        // ============================================================
        //  工具栏按钮
        // ============================================================

        public void HandleButtonClick(Keys key)
        {
            switch (key)
            {
                case Keys.F: ToggleFullscreen(); break;
                case Keys.Q: ForceExit(); break;
                default: SendKeyToFlash(key); break;
            }
        }

        public void SendKeyToFlash(Keys key)
        {
            if (_gpuMode)
            {
                ForwardCtrlComboToFlash(key);
                return;
            }

            if (_windowManager != null && _windowManager.FlashHwnd != IntPtr.Zero)
                SetForegroundWindow(_windowManager.FlashHwnd);

            keybd_event((byte)Keys.ControlKey, 0, 0, UIntPtr.Zero);
            keybd_event((byte)key, 0, 0, UIntPtr.Zero);
            keybd_event((byte)key, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
            keybd_event((byte)Keys.ControlKey, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);

            LogManager.Log("[Input] Sent Ctrl+" + key + " to Flash");
        }

        private void ForwardCtrlComboToFlash(Keys key)
        {
            IntPtr flashHwnd = (_windowManager != null) ? _windowManager.FlashHwnd : IntPtr.Zero;
            if (flashHwnd == IntPtr.Zero)
                return;

            PostKeyMessage(flashHwnd, WM_KEYDOWN, Keys.ControlKey);
            PostKeyMessage(flashHwnd, WM_KEYDOWN, key);
            PostKeyMessage(flashHwnd, WM_KEYUP, key);
            PostKeyMessage(flashHwnd, WM_KEYUP, Keys.ControlKey);

            LogManager.Log("[Input] Posted Ctrl+" + key + " to Flash");
        }

        // ============================================================
        //  全屏
        // ============================================================

        public void ToggleFullscreen()
        {
            if (this.InvokeRequired)
            {
                try { this.BeginInvoke(new Action(ToggleFullscreen)); } catch { }
                return;
            }

            _isFullscreen = !_isFullscreen;
            this.SuspendLayout();

            if (_isFullscreen)
            {
                _savedBounds = this.Bounds;
                _savedBorderStyle = this.FormBorderStyle;
                this.WindowState = FormWindowState.Normal;
                this.FormBorderStyle = FormBorderStyle.None;
                this.WindowState = FormWindowState.Maximized;

                if (_hotkeysRegistered)
                    RegisterHotKey(this.Handle, HK_ESC, 0, (uint)Keys.Escape);
            }
            else
            {
                this.WindowState = FormWindowState.Normal;
                this.FormBorderStyle = _savedBorderStyle;
                this.Bounds = _savedBounds;

                UnregisterHotKey(this.Handle, HK_ESC);
            }

            this.ResumeLayout(true);

            // GPU 渲染器 resize（暂时禁用）
            // if (_gpuRenderer != null)
            //     _gpuRenderer.RequestResize(_flashPanel.Width, _flashPanel.Height);

            _flashPanel.Invalidate();
            LogManager.Log("[Guardian] Fullscreen=" + _isFullscreen);
        }

        // ============================================================
        //  日志
        // ============================================================

        public void ToggleLog()
        {
            _logVisible = !_logVisible;
            this.SuspendLayout();
            if (_logVisible)
            {
                _logBar.Visible = true;
                _logBar.Height = _logBarH;
            }
            else
            {
                _logBarH = _logBar.Height;
                _logBar.Height = 0;
                _logBar.Visible = false;
            }
            this.ResumeLayout(true);
        }

        private void OnSearchKeyDown(object sender, KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Enter)
            {
                e.SuppressKeyPress = true;
                string query = _searchBox.Text;
                if (string.IsNullOrEmpty(query)) return;

                int idx = _logBox.Text.IndexOf(query, _searchPos, StringComparison.OrdinalIgnoreCase);
                if (idx < 0 && _searchPos > 0)
                    idx = _logBox.Text.IndexOf(query, 0, StringComparison.OrdinalIgnoreCase);

                if (idx >= 0)
                {
                    _logBox.SelectionStart = idx;
                    _logBox.SelectionLength = query.Length;
                    _logBox.ScrollToCaret();
                    _searchPos = idx + query.Length;
                }
                else
                {
                    _searchPos = 0;
                }
            }
            else if (e.KeyCode == Keys.Escape)
            {
                e.SuppressKeyPress = true;
                _searchPos = 0;
                _logBox.SelectionLength = 0;
            }
        }

        private void EnsureGpuPaintTimer()
        {
            if (_gpuPaintTimer != null)
                return;

            _gpuPaintTimer = new System.Windows.Forms.Timer();
            _gpuPaintTimer.Interval = GpuPaintIntervalMs;
            _gpuPaintTimer.Tick += delegate
            {
                if (_gpuMode && !_flashPanel.IsDisposed)
                    _flashPanel.Invalidate();
            };
        }

        private void OnGpuFallbackRequested()
        {
            if (_gpuFallbackPending)
                return;

            _gpuFallbackPending = true;

            try
            {
                if (this.InvokeRequired)
                    this.BeginInvoke(new Action(HandleGpuFallbackOnUiThread));
                else
                    HandleGpuFallbackOnUiThread();
            }
            catch
            {
                _gpuFallbackPending = false;
            }
        }

        private void HandleGpuFallbackOnUiThread()
        {
            if (!_gpuMode)
            {
                _gpuFallbackPending = false;
                return;
            }

            LogManager.Log("[Guardian] GPU renderer fallback to embedded Flash");
            StopGpuRenderer();

            if (_windowManager != null)
            {
                _windowManager.DisableGpuMode();
                _windowManager.ReparentFlash(_flashPanel);
            }

            SetGpuCaptureHostVisible(false);
            _flashPanel.Focus();
            _gpuFallbackPending = false;
        }

        private void OnFlashPanelMouseEnter(object sender, EventArgs e)
        {
            if (_gpuMode)
                _flashPanel.Focus();
        }

        private void OnFlashPanelMouseDown(object sender, MouseEventArgs e)
        {
            if (!_gpuMode)
                return;

            _flashPanel.Focus();
            ForwardMouseMessage(GetMouseDownMessage(e.Button), e);
        }

        private void OnFlashPanelMouseUp(object sender, MouseEventArgs e)
        {
            if (!_gpuMode)
                return;

            ForwardMouseMessage(GetMouseUpMessage(e.Button), e);
        }

        private void OnFlashPanelMouseMove(object sender, MouseEventArgs e)
        {
            if (!_gpuMode)
                return;

            ForwardMouseMessage(WM_MOUSEMOVE, e);
        }

        private void OnFlashPanelMouseWheel(object sender, MouseEventArgs e)
        {
            if (!_gpuMode)
                return;

            IntPtr flashHwnd = (_windowManager != null) ? _windowManager.FlashHwnd : IntPtr.Zero;
            if (flashHwnd == IntPtr.Zero)
                return;

            Point mapped;
            if (!TryMapPanelPointToCapture(e.Location, out mapped))
                return;

            int keyState = GetMouseKeyState(Control.MouseButtons);
            int wParam = (unchecked((short)e.Delta) << 16) | (keyState & 0xFFFF);
            PostMessage(flashHwnd, WM_MOUSEWHEEL, new IntPtr(wParam), MakeMouseLParam(mapped.X, mapped.Y));
        }

        private void OnFlashPanelMouseDoubleClick(object sender, MouseEventArgs e)
        {
            if (!_gpuMode)
                return;

            ForwardMouseMessage(GetMouseDoubleClickMessage(e.Button), e);
        }

        private void OnFlashPanelKeyDown(object sender, KeyEventArgs e)
        {
            if (!_gpuMode)
                return;

            IntPtr flashHwnd = (_windowManager != null) ? _windowManager.FlashHwnd : IntPtr.Zero;
            if (flashHwnd == IntPtr.Zero)
                return;

            int message = (e.Alt ? WM_SYSKEYDOWN : WM_KEYDOWN);
            PostKeyMessage(flashHwnd, message, e.KeyCode);
            e.Handled = true;
            e.SuppressKeyPress = true;
        }

        private void OnFlashPanelKeyUp(object sender, KeyEventArgs e)
        {
            if (!_gpuMode)
                return;

            IntPtr flashHwnd = (_windowManager != null) ? _windowManager.FlashHwnd : IntPtr.Zero;
            if (flashHwnd == IntPtr.Zero)
                return;

            int message = (e.Alt ? WM_SYSKEYUP : WM_KEYUP);
            PostKeyMessage(flashHwnd, message, e.KeyCode);
            e.Handled = true;
            e.SuppressKeyPress = true;
        }

        private void OnFlashPanelKeyPress(object sender, KeyPressEventArgs e)
        {
            if (!_gpuMode)
                return;

            IntPtr flashHwnd = (_windowManager != null) ? _windowManager.FlashHwnd : IntPtr.Zero;
            if (flashHwnd == IntPtr.Zero)
                return;

            PostMessage(flashHwnd, WM_CHAR, new IntPtr(e.KeyChar), IntPtr.Zero);
            e.Handled = true;
        }

        private void ForwardMouseMessage(int message, MouseEventArgs e)
        {
            if (message == 0)
                return;

            IntPtr flashHwnd = (_windowManager != null) ? _windowManager.FlashHwnd : IntPtr.Zero;
            if (flashHwnd == IntPtr.Zero)
                return;

            Point mapped;
            if (!TryMapPanelPointToCapture(e.Location, out mapped))
                return;

            int keyState = GetMouseKeyState(Control.MouseButtons);
            keyState |= GetMouseButtonMask(e.Button);

            if (message == WM_XBUTTONDOWN || message == WM_XBUTTONUP || message == WM_XBUTTONDBLCLK)
            {
                int xButtonMask = (e.Button == MouseButtons.XButton2) ? (2 << 16) : (1 << 16);
                PostMessage(flashHwnd, message, new IntPtr(xButtonMask | (keyState & 0xFFFF)), MakeMouseLParam(mapped.X, mapped.Y));
            }
            else
            {
                PostMessage(flashHwnd, message, new IntPtr(keyState), MakeMouseLParam(mapped.X, mapped.Y));
            }
        }

        private bool TryMapPanelPointToCapture(Point panelPoint, out Point capturePoint)
        {
            capturePoint = Point.Empty;
            if (!_gpuMode || _gpuRenderer == null)
                return false;

            Rectangle drawRect = GetGpuDrawRect();
            if (drawRect.Width <= 0 || drawRect.Height <= 0 || !drawRect.Contains(panelPoint))
                return false;

            int captureW = _gpuRenderer.CaptureWidth;
            int captureH = _gpuRenderer.CaptureHeight;
            int x = (panelPoint.X - drawRect.Left) * captureW / drawRect.Width;
            int y = (panelPoint.Y - drawRect.Top) * captureH / drawRect.Height;

            capturePoint = new Point(
                Math.Max(0, Math.Min(captureW - 1, x)),
                Math.Max(0, Math.Min(captureH - 1, y)));
            return true;
        }

        private Rectangle GetGpuDrawRect()
        {
            int sourceWidth = (_gpuRenderer != null) ? _gpuRenderer.CaptureWidth : DefaultGpuCaptureWidth;
            int sourceHeight = (_gpuRenderer != null) ? _gpuRenderer.CaptureHeight : DefaultGpuCaptureHeight;

            Rectangle bounds = _flashPanel.ClientRectangle;
            if (bounds.Width <= 0 || bounds.Height <= 0 || sourceWidth <= 0 || sourceHeight <= 0)
                return Rectangle.Empty;

            float scale = Math.Min((float)bounds.Width / sourceWidth, (float)bounds.Height / sourceHeight);
            int drawWidth = Math.Max(1, (int)Math.Round(sourceWidth * scale));
            int drawHeight = Math.Max(1, (int)Math.Round(sourceHeight * scale));
            int drawX = bounds.X + (bounds.Width - drawWidth) / 2;
            int drawY = bounds.Y + (bounds.Height - drawHeight) / 2;
            return new Rectangle(drawX, drawY, drawWidth, drawHeight);
        }

        private static int GetMouseDownMessage(MouseButtons button)
        {
            switch (button)
            {
                case MouseButtons.Left: return WM_LBUTTONDOWN;
                case MouseButtons.Right: return WM_RBUTTONDOWN;
                case MouseButtons.Middle: return WM_MBUTTONDOWN;
                case MouseButtons.XButton1:
                case MouseButtons.XButton2:
                    return WM_XBUTTONDOWN;
                default:
                    return 0;
            }
        }

        private static int GetMouseUpMessage(MouseButtons button)
        {
            switch (button)
            {
                case MouseButtons.Left: return WM_LBUTTONUP;
                case MouseButtons.Right: return WM_RBUTTONUP;
                case MouseButtons.Middle: return WM_MBUTTONUP;
                case MouseButtons.XButton1:
                case MouseButtons.XButton2:
                    return WM_XBUTTONUP;
                default:
                    return 0;
            }
        }

        private static int GetMouseDoubleClickMessage(MouseButtons button)
        {
            switch (button)
            {
                case MouseButtons.Left: return WM_LBUTTONDBLCLK;
                case MouseButtons.Right: return WM_RBUTTONDBLCLK;
                case MouseButtons.Middle: return WM_MBUTTONDBLCLK;
                case MouseButtons.XButton1:
                case MouseButtons.XButton2:
                    return WM_XBUTTONDBLCLK;
                default:
                    return 0;
            }
        }

        private static int GetMouseButtonMask(MouseButtons button)
        {
            switch (button)
            {
                case MouseButtons.Left: return MK_LBUTTON;
                case MouseButtons.Right: return MK_RBUTTON;
                case MouseButtons.Middle: return MK_MBUTTON;
                case MouseButtons.XButton1: return MK_XBUTTON1;
                case MouseButtons.XButton2: return MK_XBUTTON2;
                default: return 0;
            }
        }

        private static int GetMouseKeyState(MouseButtons buttons)
        {
            int state = 0;
            if ((buttons & MouseButtons.Left) == MouseButtons.Left)
                state |= MK_LBUTTON;
            if ((buttons & MouseButtons.Right) == MouseButtons.Right)
                state |= MK_RBUTTON;
            if ((buttons & MouseButtons.Middle) == MouseButtons.Middle)
                state |= MK_MBUTTON;
            if ((buttons & MouseButtons.XButton1) == MouseButtons.XButton1)
                state |= MK_XBUTTON1;
            if ((buttons & MouseButtons.XButton2) == MouseButtons.XButton2)
                state |= MK_XBUTTON2;

            Keys modifiers = Control.ModifierKeys;
            if ((modifiers & Keys.Shift) == Keys.Shift)
                state |= MK_SHIFT;
            if ((modifiers & Keys.Control) == Keys.Control)
                state |= MK_CONTROL;

            return state;
        }

        private static void PostKeyMessage(IntPtr flashHwnd, int message, Keys key)
        {
            bool keyUp = (message == WM_KEYUP || message == WM_SYSKEYUP);
            PostMessage(flashHwnd, message, new IntPtr((int)key), MakeKeyLParam(key, keyUp));
        }

        private static IntPtr MakeMouseLParam(int x, int y)
        {
            return new IntPtr((y << 16) | (x & 0xFFFF));
        }

        private static IntPtr MakeKeyLParam(Keys key, bool keyUp)
        {
            uint scanCode = MapVirtualKey((uint)key, MAPVK_VK_TO_VSC);
            int lParam = 1 | ((int)scanCode << 16);
            if (IsExtendedKey(key))
                lParam |= 1 << 24;
            if (keyUp)
                lParam |= unchecked((int)0xC0000000);
            return new IntPtr(lParam);
        }

        private static bool IsExtendedKey(Keys key)
        {
            switch (key)
            {
                case Keys.Right:
                case Keys.Left:
                case Keys.Up:
                case Keys.Down:
                case Keys.Insert:
                case Keys.Delete:
                case Keys.Home:
                case Keys.End:
                case Keys.PageUp:
                case Keys.PageDown:
                case Keys.NumLock:
                case Keys.Cancel:
                case Keys.PrintScreen:
                case Keys.Divide:
                case Keys.RControlKey:
                case Keys.RMenu:
                    return true;
                default:
                    return false;
            }
        }

        // ============================================================
        //  GPU 渲染器（显示管线待完善，代码保留）
        // ============================================================
        // 已验证可行：BitBlt 捕获（0/300黑帧）、D3D11 off-screen CAS 处理、回读
        // 待解决：如何将 GPU 处理后的帧显示到用户可见的面板上
        //   - SwapChain → WinForms Panel：WM_PAINT 覆盖 SwapChain 输出
        //   - Overlay Panel：Flash 被遮挡后停止 GDI 渲染
        //   - SetWindowRgn 空区域：Flash 同样停止渲染
        // 需要外部技术验证后继续

        // ============================================================
        //  托盘
        // ============================================================

        private void SetupTrayIcon()
        {
            _trayMenu = new ContextMenuStrip();
            _trayMenu.Items.Add("\u663E\u793A", null, delegate { ShowMainWindow(); });
            _trayMenu.Items.Add("\u65E5\u5FD7", null, delegate { ShowMainWindow(); if (!_logVisible) ToggleLog(); });
            _trayMenu.Items.Add("-");
            _trayMenu.Items.Add("\u9000\u51FA", null, delegate { ForceExit(); });

            _trayIcon = new NotifyIcon();
            _trayIcon.Text = "CF7:ME";
            _trayIcon.ContextMenuStrip = _trayMenu;
            _trayIcon.Visible = true;
            try { _trayIcon.Icon = Icon.ExtractAssociatedIcon(System.Reflection.Assembly.GetExecutingAssembly().Location); }
            catch { _trayIcon.Icon = SystemIcons.Application; }
            _trayIcon.DoubleClick += delegate { ShowMainWindow(); };
        }

        private void ShowMainWindow()
        {
            this.Show();
            this.WindowState = FormWindowState.Normal;
            this.BringToFront();
            this.Activate();
        }

        // ============================================================
        //  退出
        // ============================================================

        private void OnFormClosing(object sender, FormClosingEventArgs e)
        {
            e.Cancel = true;
            ForceExit();
        }

        public void ForceExit()
        {
            if (this.InvokeRequired)
            {
                bool invoked = false;
                try
                {
                    if (this.IsHandleCreated && !this.IsDisposed)
                    {
                        this.BeginInvoke(new Action(DoExit));
                        invoked = true;
                    }
                }
                catch { }

                if (!invoked) { CleanupTrayIcon(); Environment.Exit(0); }

                ThreadPool.QueueUserWorkItem(delegate { Thread.Sleep(3000); Environment.Exit(0); });
                return;
            }
            DoExit();
        }

        /// <summary>退出前回调。Program.cs 注入，在 Form dispose 之前断开快车道。</summary>
        public Action OnShutdownEarly;

        private void DoExit()
        {
            // 最早期断开快车道，防止 dispose 后 FrameTask 推到已释放的 overlay
            if (OnShutdownEarly != null)
            {
                try { OnShutdownEarly(); } catch { }
                OnShutdownEarly = null;
            }
            this.FormClosing -= OnFormClosing;
            StopGpuRenderer();
            DoUnregisterHotkeys();
            CleanupTrayIcon();
            if (_exitWatchdog != null) _exitWatchdog.Stop();
            Application.ExitThread();
            ThreadPool.QueueUserWorkItem(delegate { Thread.Sleep(1000); Environment.Exit(0); });
        }

        private void CleanupTrayIcon()
        {
            if (_trayIcon != null)
            {
                try { _trayIcon.Visible = false; _trayIcon.Dispose(); } catch { }
                _trayIcon = null;
            }
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                StopGpuRenderer();
                CleanupTrayIcon();
            }
            base.Dispose(disposing);
        }
    }
}
