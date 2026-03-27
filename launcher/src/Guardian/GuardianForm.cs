using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;
using System.Diagnostics;

namespace CF7Launcher.Guardian
{
    public class GuardianForm : Form
    {
        // ── Win32 API ──
        [DllImport("user32.dll")]
        private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

        [DllImport("user32.dll")]
        private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

        [DllImport("user32.dll")]
        private static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

        private const uint MOD_CONTROL = 0x0002;
        private const int WM_HOTKEY = 0x0312;
        private const uint KEYEVENTF_KEYUP = 0x0002;

        // 热键 ID
        private const int HK_BASE = 0xCF00;
        private const int HK_ESC = 0xCF10;
        private static readonly Keys[] HotkeyKeys = { Keys.Q, Keys.W, Keys.R, Keys.F, Keys.P, Keys.O };

        private NotifyIcon _trayIcon;
        private ContextMenuStrip _trayMenu;
        private TextBox _logBox;
        private Panel _flashPanel;

        // 工具栏
        private Panel _toolbar;
        private FlowLayoutPanel _hotkeyPanel;
        private bool _hotkeysExpanded;

        // 底部日志
        private Panel _logBar;
        private TextBox _searchBox;
        private int _searchPos;
        private bool _logVisible;
        private int _logBarH = 180;

        // 全屏
        private bool _isFullscreen;
        private Rectangle _savedBounds;
        private FormBorderStyle _savedBorderStyle;

        // 热键
        private bool _hotkeysRegistered;

        // Flash 进程监控
        private Process _flashProcess;
        private System.Windows.Forms.Timer _exitWatchdog;

        private WindowManager _windowManager;

        public Panel FlashHostPanel { get { return _flashPanel; } }

        public GuardianForm()
        {
            InitializeComponent();
            SetupTrayIcon();
            SetupHotkeyPolling();
            LogManager.Init(this, _logBox);
        }

        public void BindWindowManager(WindowManager wm) { _windowManager = wm; }

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

            // 拖拽手柄（日志面板顶部 4px 横条）
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
            _logBox.HideSelection = false; // 搜索高亮始终可见

            // _logBar 子控件添加顺序：Fill 先加（最高 z-order → 最后布局 → 填充剩余）
            _logBar.Controls.Add(_logBox);
            _logBar.Controls.Add(searchBar);
            _logBar.Controls.Add(dragHandle);

            this.Controls.Add(_logBar);

            // ── 顶部工具栏 ──
            _toolbar = new Panel();
            _toolbar.Dock = DockStyle.Top;
            _toolbar.Height = 28;
            _toolbar.BackColor = Color.FromArgb(24, 24, 26);
            _toolbar.Padding = new Padding(2, 2, 2, 2);

            _hotkeyPanel = new FlowLayoutPanel();
            _hotkeyPanel.Dock = DockStyle.Fill;
            _hotkeyPanel.Visible = false;
            _hotkeyPanel.BackColor = Color.FromArgb(24, 24, 26);
            _hotkeyPanel.FlowDirection = FlowDirection.LeftToRight;
            _hotkeyPanel.WrapContents = false;
            _hotkeyPanel.Padding = new Padding(0);

            string[] labels = {
                "Q \u9000\u51FA",  "W \u5173\u95ED",  "R \u91CD\u7F6E",
                "F \u5168\u5C4F",  "P \u622A\u56FE",  "O \u6253\u5F00"
            };
            for (int i = 0; i < HotkeyKeys.Length; i++)
            {
                Button hkBtn = CreateToolbarButton(labels[i], 66, uiFont);
                hkBtn.Margin = new Padding(1, 0, 1, 0);
                Keys captured = HotkeyKeys[i];
                hkBtn.Click += delegate { HandleButtonClick(captured); };
                _hotkeyPanel.Controls.Add(hkBtn);
            }

            // 工具栏子控件顺序：Fill 先加
            _toolbar.Controls.Add(_hotkeyPanel);

            Button menuBtn = CreateToolbarButton("\u2630", 28, uiFont);
            menuBtn.Click += delegate { _hotkeysExpanded = !_hotkeysExpanded; _hotkeyPanel.Visible = _hotkeysExpanded; };
            menuBtn.Dock = DockStyle.Left;
            _toolbar.Controls.Add(menuBtn);

            Button logBtn = CreateToolbarButton("\u65E5\u5FD7", 48, uiFont);
            logBtn.Click += delegate { ToggleLog(); };
            logBtn.Dock = DockStyle.Right;
            _toolbar.Controls.Add(logBtn);

            Button fsBtn = CreateToolbarButton("\u5168\u5C4F", 48, uiFont);
            fsBtn.Click += delegate { ToggleFullscreen(); };
            fsBtn.Dock = DockStyle.Right;
            _toolbar.Controls.Add(fsBtn);

            this.Controls.Add(_toolbar);

            // ── Flash 宿主 ──
            _flashPanel = new Panel();
            _flashPanel.Dock = DockStyle.Fill;
            _flashPanel.BackColor = Color.Black;
            this.Controls.Add(_flashPanel);

            this.FormClosing += OnFormClosing;
        }

        private static Button CreateToolbarButton(string text, int width, Font font)
        {
            Button btn = new Button();
            btn.Text = text;
            btn.Size = new Size(width, 24);
            btn.FlatStyle = FlatStyle.Flat;
            btn.FlatAppearance.BorderSize = 0;
            btn.BackColor = Color.FromArgb(30, 30, 34);
            btn.ForeColor = Color.FromArgb(170, 170, 170);
            btn.Font = font;
            btn.Cursor = Cursors.Hand;
            btn.Margin = new Padding(1, 0, 1, 0);
            btn.MouseEnter += delegate { btn.BackColor = Color.FromArgb(55, 55, 60); };
            btn.MouseLeave += delegate { btn.BackColor = Color.FromArgb(30, 30, 34); };
            return btn;
        }

        // ============================================================
        //  RegisterHotKey（替代低级钩子）
        // ============================================================

        /// <summary>
        /// Handle 创建后一次性注册，退出时才注销。不做前台轮询。
        /// </summary>
        private void SetupHotkeyPolling()
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
            int ok = 0;
            for (int i = 0; i < HotkeyKeys.Length; i++)
            {
                bool result = RegisterHotKey(this.Handle, HK_BASE + i, MOD_CONTROL, (uint)HotkeyKeys[i]);
                if (result) ok++;
                else LogManager.Log("[Hotkey] FAILED Ctrl+" + HotkeyKeys[i]
                    + " err=" + Marshal.GetLastWin32Error());
            }
            _hotkeysRegistered = true;
            LogManager.Log("[Hotkey] Registered " + ok + "/" + HotkeyKeys.Length);
        }

        private void DoUnregisterHotkeys()
        {
            for (int i = 0; i < HotkeyKeys.Length; i++)
                UnregisterHotKey(this.Handle, HK_BASE + i);
            UnregisterHotKey(this.Handle, HK_ESC);
            _hotkeysRegistered = false;
        }

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == WM_HOTKEY)
            {
                int id = m.WParam.ToInt32();
                if (id == HK_ESC)
                {
                    ToggleFullscreen();
                    return;
                }
                int idx = id - HK_BASE;
                if (idx >= 0 && idx < HotkeyKeys.Length)
                {
                    HandleHotkeyFromSystem(HotkeyKeys[idx]);
                    return;
                }
            }
            base.WndProc(ref m);
        }

        // ============================================================
        //  热键处理
        // ============================================================

        private void HandleHotkeyFromSystem(Keys key)
        {
            switch (key)
            {
                case Keys.F: ToggleFullscreen(); break;
                case Keys.Q: ForceExit(); break;
                // W/R/P/O：仅拦截，不转发（由系统消费，Flash 已收不到）
            }
        }

        private void HandleButtonClick(Keys key)
        {
            switch (key)
            {
                case Keys.F: ToggleFullscreen(); break;
                case Keys.Q: ForceExit(); break;
                default: SendKeyToFlash(key); break;
            }
        }

        private void SendKeyToFlash(Keys key)
        {
            int idx = Array.IndexOf(HotkeyKeys, key);
            if (idx >= 0)
                UnregisterHotKey(this.Handle, HK_BASE + idx);

            keybd_event((byte)Keys.ControlKey, 0, 0, UIntPtr.Zero);
            keybd_event((byte)key, 0, 0, UIntPtr.Zero);
            keybd_event((byte)key, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
            keybd_event((byte)Keys.ControlKey, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);

            if (idx >= 0)
                RegisterHotKey(this.Handle, HK_BASE + idx, MOD_CONTROL, (uint)key);

            LogManager.Log("[Input] Sent Ctrl+" + key + " to Flash");
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
                _toolbar.Visible = false;

                if (_hotkeysRegistered)
                    RegisterHotKey(this.Handle, HK_ESC, 0, (uint)Keys.Escape);
            }
            else
            {
                this.WindowState = FormWindowState.Normal;
                this.FormBorderStyle = _savedBorderStyle;
                this.Bounds = _savedBounds;
                _toolbar.Visible = true;

                UnregisterHotKey(this.Handle, HK_ESC);
            }

            this.ResumeLayout(true);
            LogManager.Log("[Guardian] Fullscreen=" + _isFullscreen);
        }

        // ============================================================
        //  日志面板
        // ============================================================

        private void ToggleLog()
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
                    // 不转移焦点——搜索框保持焦点以便连续 Enter
                    // HideSelection=false 确保高亮始终可见
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

        private void DoExit()
        {
            this.FormClosing -= OnFormClosing;
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
            if (disposing) CleanupTrayIcon();
            base.Dispose(disposing);
        }
    }
}
