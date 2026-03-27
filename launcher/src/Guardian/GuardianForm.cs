using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace CF7Launcher.Guardian
{
    public class GuardianForm : Form
    {
        [DllImport("user32.dll")]
        private static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);

        private const uint WM_KEYDOWN = 0x0100;
        private const uint WM_KEYUP = 0x0101;

        private NotifyIcon _trayIcon;
        private ContextMenuStrip _trayMenu;
        private TextBox _logBox;
        private Panel _flashPanel;

        // 悬浮面板
        private Panel _floatPanel;
        private Button _menuBtn;
        private bool _floatVisible;

        // 右侧日志
        private Panel _rightBar;
        private bool _rightVisible;
        private int _rightMaxW = 300;

        private WindowManager _windowManager;

        public Panel FlashHostPanel { get { return _flashPanel; } }

        public GuardianForm()
        {
            InitializeComponent();
            SetupTrayIcon();
            LogManager.Init(this, _logBox);
        }

        public void BindWindowManager(WindowManager wm)
        {
            _windowManager = wm;
        }

        private void InitializeComponent()
        {
            this.Text = "CF7:ME";
            this.Size = new Size(1280, 660);
            this.MinimumSize = new Size(800, 480);
            this.StartPosition = FormStartPosition.CenterScreen;
            this.FormBorderStyle = FormBorderStyle.Sizable;
            this.BackColor = Color.Black;

            // === 右侧日志栏（初始隐藏）===
            _rightBar = new Panel();
            _rightBar.Dock = DockStyle.Right;
            _rightBar.Width = 0;
            _rightBar.Visible = false;
            _rightBar.BackColor = Color.FromArgb(20, 20, 22);

            Label logTitle = new Label();
            logTitle.Text = " Log";
            logTitle.Font = new Font("Segoe UI", 8, FontStyle.Bold);
            logTitle.ForeColor = Color.FromArgb(100, 100, 100);
            logTitle.Dock = DockStyle.Top;
            logTitle.Height = 18;
            _rightBar.Controls.Add(logTitle);

            _logBox = new TextBox();
            _logBox.Multiline = true;
            _logBox.ReadOnly = true;
            _logBox.ScrollBars = ScrollBars.Vertical;
            _logBox.Dock = DockStyle.Fill;
            _logBox.Font = new Font("Consolas", 8);
            _logBox.BackColor = Color.FromArgb(16, 16, 18);
            _logBox.ForeColor = Color.FromArgb(160, 160, 160);
            _logBox.BorderStyle = BorderStyle.None;
            _logBox.WordWrap = true;
            _rightBar.Controls.Add(_logBox);

            this.Controls.Add(_rightBar);

            // === Flash 宿主（填满）===
            _flashPanel = new Panel();
            _flashPanel.Dock = DockStyle.Fill;
            _flashPanel.BackColor = Color.Black;
            this.Controls.Add(_flashPanel);

            // === 悬浮菜单按钮（左上角，覆盖在 Flash 上）===
            _menuBtn = new Button();
            _menuBtn.Text = "\u2630";  // ☰
            _menuBtn.Size = new Size(28, 28);
            _menuBtn.Location = new Point(4, 4);
            _menuBtn.FlatStyle = FlatStyle.Flat;
            _menuBtn.FlatAppearance.BorderSize = 0;
            _menuBtn.BackColor = Color.FromArgb(100, 30, 30, 30);
            _menuBtn.ForeColor = Color.FromArgb(180, 180, 180);
            _menuBtn.Font = new Font("Segoe UI", 11);
            _menuBtn.Cursor = Cursors.Hand;
            _menuBtn.Click += delegate { ToggleFloatPanel(); };
            _menuBtn.MouseEnter += delegate { _menuBtn.BackColor = Color.FromArgb(200, 40, 40, 40); };
            _menuBtn.MouseLeave += delegate { _menuBtn.BackColor = Color.FromArgb(100, 30, 30, 30); };
            _flashPanel.Controls.Add(_menuBtn);
            _menuBtn.BringToFront();

            // === 悬浮面板（覆盖在 Flash 上，默认隐藏）===
            _floatPanel = new Panel();
            _floatPanel.Size = new Size(120, 260);
            _floatPanel.Location = new Point(4, 36);
            _floatPanel.BackColor = Color.FromArgb(220, 22, 22, 24);
            _floatPanel.Visible = false;
            _floatPanel.Padding = new Padding(4);

            // 快捷键发送按钮
            Keys[] keys = new Keys[] { Keys.Q, Keys.W, Keys.R, Keys.F, Keys.P, Keys.O };
            string[] descs = new string[] { "Quit", "Close", "Reset", "Screen", "Print", "Open" };

            for (int i = keys.Length - 1; i >= 0; i--)
            {
                AddSendButton(keys[i], descs[i]);
            }

            // 日志切换
            Button logBtn = new Button();
            logBtn.Text = "\u25A4 Log";  // ▤ Log
            logBtn.Dock = DockStyle.Bottom;
            logBtn.Height = 26;
            logBtn.FlatStyle = FlatStyle.Flat;
            logBtn.FlatAppearance.BorderSize = 0;
            logBtn.BackColor = Color.FromArgb(35, 35, 38);
            logBtn.ForeColor = Color.FromArgb(130, 130, 130);
            logBtn.Font = new Font("Segoe UI", 8);
            logBtn.Cursor = Cursors.Hand;
            logBtn.Click += delegate { ToggleLog(); };
            logBtn.MouseEnter += delegate { logBtn.BackColor = Color.FromArgb(50, 50, 55); };
            logBtn.MouseLeave += delegate { logBtn.BackColor = Color.FromArgb(35, 35, 38); };
            _floatPanel.Controls.Add(logBtn);

            _flashPanel.Controls.Add(_floatPanel);
            _floatPanel.BringToFront();

            _floatVisible = false;
            _rightVisible = false;

            this.Resize += delegate
            {
                if (this.WindowState == FormWindowState.Minimized)
                    this.Hide();
            };

            this.FormClosing += OnFormClosing;
        }

        private void AddSendButton(Keys key, string desc)
        {
            Button btn = new Button();
            btn.Text = "^" + key.ToString() + " " + desc;
            btn.Dock = DockStyle.Top;
            btn.Height = 28;
            btn.FlatStyle = FlatStyle.Flat;
            btn.FlatAppearance.BorderSize = 0;
            btn.BackColor = Color.FromArgb(30, 30, 34);
            btn.ForeColor = Color.FromArgb(160, 160, 160);
            btn.Font = new Font("Consolas", 8);
            btn.Cursor = Cursors.Hand;
            btn.TextAlign = ContentAlignment.MiddleLeft;
            btn.Padding = new Padding(6, 0, 0, 0);

            btn.Click += delegate { SendKeyToFlash(key); };
            btn.MouseEnter += delegate { btn.BackColor = Color.FromArgb(50, 50, 55); };
            btn.MouseLeave += delegate { btn.BackColor = Color.FromArgb(30, 30, 34); };

            _floatPanel.Controls.Add(btn);
        }

        /// <summary>
        /// 通过 PostMessage 直接把按键发送给 Flash 窗口（绕过钩子拦截）
        /// </summary>
        private void SendKeyToFlash(Keys key)
        {
            if (_windowManager == null) return;
            IntPtr hwnd = _windowManager.FlashHwnd;
            if (hwnd == IntPtr.Zero) return;

            // 发送 Ctrl+Key：先按 Ctrl，再按 Key，再释放
            PostMessage(hwnd, WM_KEYDOWN, (IntPtr)Keys.ControlKey, IntPtr.Zero);
            PostMessage(hwnd, WM_KEYDOWN, (IntPtr)key, IntPtr.Zero);
            PostMessage(hwnd, WM_KEYUP, (IntPtr)key, IntPtr.Zero);
            PostMessage(hwnd, WM_KEYUP, (IntPtr)Keys.ControlKey, IntPtr.Zero);

            LogManager.Log("[Input] Sent Ctrl+" + key.ToString() + " to Flash");
        }

        private void ToggleFloatPanel()
        {
            _floatVisible = !_floatVisible;
            _floatPanel.Visible = _floatVisible;
        }

        private void ToggleLog()
        {
            _rightVisible = !_rightVisible;
            this.SuspendLayout();
            if (_rightVisible)
            {
                _rightBar.Visible = true;
                _rightBar.Width = _rightMaxW;
            }
            else
            {
                _rightBar.Width = 0;
                _rightBar.Visible = false;
            }
            this.ResumeLayout(true);
        }

        private void SetupTrayIcon()
        {
            _trayMenu = new ContextMenuStrip();
            _trayMenu.Items.Add("Show", null, delegate { ShowMainWindow(); });
            _trayMenu.Items.Add("Log", null, delegate { ShowMainWindow(); ToggleLog(); });
            _trayMenu.Items.Add("-");
            _trayMenu.Items.Add("Exit", null, delegate { ForceExit(); });

            _trayIcon = new NotifyIcon();
            _trayIcon.Text = "CF7:ME";
            _trayIcon.ContextMenuStrip = _trayMenu;
            _trayIcon.Visible = true;

            try
            {
                _trayIcon.Icon = Icon.ExtractAssociatedIcon(
                    System.Reflection.Assembly.GetExecutingAssembly().Location);
            }
            catch
            {
                _trayIcon.Icon = SystemIcons.Application;
            }

            _trayIcon.DoubleClick += delegate { ShowMainWindow(); };
        }

        private void ShowMainWindow()
        {
            this.Show();
            this.WindowState = FormWindowState.Normal;
            this.BringToFront();
            this.Activate();
        }

        private void OnFormClosing(object sender, FormClosingEventArgs e)
        {
            if (e.CloseReason == CloseReason.UserClosing)
            {
                e.Cancel = true;
                this.Hide();
            }
        }

        public void ForceExit()
        {
            this.FormClosing -= OnFormClosing;
            if (_trayIcon != null)
            {
                _trayIcon.Visible = false;
                _trayIcon.Dispose();
            }
            Application.ExitThread();
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing && _trayIcon != null)
            {
                _trayIcon.Visible = false;
                _trayIcon.Dispose();
            }
            base.Dispose(disposing);
        }
    }
}
