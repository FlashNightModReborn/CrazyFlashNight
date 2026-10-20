using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

namespace CF7Launcher.Guardian.Hud.Dialogue
{
    /// <summary>输入层按键裁决结果。</summary>
    internal enum DialogueInterjectKeyResult
    {
        /// <summary>不处理，交给系统/IME 继续。</summary>
        None = 0,
        /// <summary>吞掉，且不产生业务动作（组词 Enter、Esc 不关对话）。</summary>
        Swallow = 1,
        /// <summary>发送当前文本。</summary>
        Send = 2
    }

    /// <summary>
    /// 插话输入框的纯决策模型（G0-1 spike）：
    /// 不依赖 WinForms/GDI，可单测；UI 层只负责把控件事件翻译成这里的调用。
    ///
    /// 口径（《协议》7.1 / 7.3）：
    /// - 单行、最多 150 字、显示计数、Enter 发送、不做多行编辑；
    /// - 中文输入法组词中的 Enter 只确认候选，不发送；
    /// - 输入框聚焦时不得触发游戏热键、不得推进对话；Esc 不关闭对话；
    /// - 输入可用性由播放状态机给出（Enabled），这里只做本地裁决。
    /// </summary>
    internal sealed class DialogueInterjectInputModel
    {
        internal const int MaxInputLength = 150;

        private readonly StringBuilder _text = new StringBuilder();

        /// <summary>输入是否可用（状态机给出的 can-input；false 时 Enter 不发送）。</summary>
        internal bool Enabled { get; set; }
        /// <summary>IME 是否处于组词态（WM_IME_START/ENDCOMPOSITION 或 ImmGetCompositionString 探针）。</summary>
        internal bool IsComposing { get; set; }
        /// <summary>输入框是否持有焦点（决定是否放行游戏热键）。</summary>
        internal bool Focused { get; set; }

        internal string Text { get { return _text.ToString(); } }
        internal int Length { get { return _text.Length; } }
        internal bool IsEmpty { get { return _text.Length == 0; } }
        /// <summary>计数文案：当前/上限。</summary>
        internal string CounterText { get { return _text.Length + "/" + MaxInputLength; } }

        /// <summary>聚焦时游戏热键必须放行；未聚焦时恢复既有热键行为。</summary>
        internal bool SuppressesGameHotkeys { get { return Focused; } }

        internal bool CanSend
        {
            get { return Enabled && !IsComposing && !IsEmpty; }
        }

        /// <summary>整串替换（受 MaxInputLength 截断；UI 层回填时用）。</summary>
        internal void SetText(string value)
        {
            _text.Length = 0;
            if (string.IsNullOrEmpty(value)) return;
            int take = Math.Min(value.Length, MaxInputLength);
            _text.Append(value, 0, take);
        }

        /// <summary>清空文本（发送后/关闭后）。</summary>
        internal void Clear()
        {
            _text.Length = 0;
        }

        /// <summary>
        /// 文本变更回调（TextBox.TextChanged）：超长时截断并返回 true 让 UI 回写。
        /// 返回值 = 是否发生了截断。
        /// </summary>
        internal bool ApplyTextChange(string current)
        {
            if (current == null) current = "";
            if (current.Length <= MaxInputLength)
            {
                _text.Length = 0;
                _text.Append(current);
                return false;
            }
            SetText(current);
            return true;
        }

        /// <summary>
        /// 按键裁决。调用方只在 TextBox.KeyDown 里转 Enter/Esc 两种键。
        /// 组词中的 Enter 必须先于"发送"判定：否则中文候选确认会误发。
        /// </summary>
        internal DialogueInterjectKeyResult HandleKey(bool enter, bool escape)
        {
            if (escape)
            {
                // 组词中：让 IME 自己取消组词；非组词：吞掉，Esc 不关闭对话。
                return IsComposing ? DialogueInterjectKeyResult.None
                    : DialogueInterjectKeyResult.Swallow;
            }
            if (!enter) return DialogueInterjectKeyResult.None;
            if (IsComposing) return DialogueInterjectKeyResult.Swallow;   // 只确认候选
            if (!CanSend) return DialogueInterjectKeyResult.Swallow;      // 空串/禁用：不发也不冒泡
            return DialogueInterjectKeyResult.Send;
        }
    }

    /// <summary>
    /// G0-1 spike 候选 B：原生 WinForms 输入浮窗（顶层小窗 + TextBox）。
    ///
    /// 为什么不是 Native 自绘面板的子控件：对话面板宿主 <c>NativeHudOverlay</c> 是
    /// <c>WS_EX_LAYERED</c> + <c>UpdateLayeredWindow</c> 逐像素 alpha 窗口且带
    /// <c>WS_EX_NOACTIVATE</c>；这种窗口不合成子 HWND、也无法拿键盘焦点，
    /// TextBox/EDIT 放进去既画不出来也收不到 IME。因此输入层必须是独立的可激活窗口，
    /// 由本类承载，位置由调用方按对话面板与关闭钮矩形给出。
    ///
    /// 交互形态与终端前端的动作框一致：收起态只有一个向上箭头按钮，点击展开输入面板；
    /// 展开态箭头旋转 180°，再点收起。面板风格跟对话面板一致（深色头条 + 浅灰正文）。
    /// </summary>
    public sealed class DialogueInterjectInputOverlay : Form
    {
        private const int WM_IME_STARTCOMPOSITION = 0x010D;
        private const int WM_IME_COMPOSITION = 0x010F;
        private const int WM_IME_ENDCOMPOSITION = 0x010E;

        [DllImport("imm32.dll")]
        private static extern IntPtr ImmGetContext(IntPtr hWnd);

        [DllImport("imm32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool ImmReleaseContext(IntPtr hWnd, IntPtr hImc);

        [DllImport("imm32.dll", CharSet = CharSet.Unicode)]
        private static extern int ImmGetCompositionStringW(IntPtr hImc, int dwIndex, byte[] lpBuf, int dwBufLen);

        [DllImport("user32.dll")]
        private static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll", CharSet = CharSet.Auto)]
        private static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);

        private const int GCS_COMPSTR = 0x0008;
        private const int EM_SETMARGINS = 0x00D3;
        private const int EC_LEFTMARGIN = 0x0001;
        private const int EC_RIGHTMARGIN = 0x0002;
        private const int WM_GETMINMAXINFO = 0x0024;
        internal const float DesignHeight = 180f;
        internal const int ToggleWidthDesign = 52;
        internal const int ToggleHeightDesign = 30;

        [StructLayout(LayoutKind.Sequential)]
        private struct NativePoint { public int X; public int Y; }

        [StructLayout(LayoutKind.Sequential)]
        private struct MinMaxInfo
        {
            public NativePoint Reserved;
            public NativePoint MaxSize;
            public NativePoint MaxPosition;
            public NativePoint MinTrackSize;
            public NativePoint MaxTrackSize;
        }

        private readonly DialogueInterjectInputModel _model = new DialogueInterjectInputModel();
        private readonly ComposingTextBox _textBox;
        private readonly Label _placeholderLabel;
        private readonly ToolTip _toolTip;
        private readonly Timer _chevronTimer;

        // 与对话面板同一套视觉：黑色头条、半透明灰面板的等效中灰、黑色文字。
        private Color _bodyBack = Color.FromArgb(191, 191, 191);
        private Color _bodyFore = Color.FromArgb(24, 24, 24);
        private Color _bodyDisabledBack = Color.FromArgb(172, 172, 172);
        private Color _headerBack = Color.FromArgb(25, 25, 25);
        private Color _headerFore = Color.FromArgb(245, 245, 245);
        private Color _accent = Color.FromArgb(204, 0, 0);
        private Color _accentAlt = Color.FromArgb(0, 153, 204);
        private Color _muted = Color.FromArgb(118, 118, 118);
        private Color _fieldBack = Color.FromArgb(250, 248, 243);
        private Color _fieldDisabledBack = Color.FromArgb(238, 235, 228);
        private Color _fieldBorder = Color.FromArgb(188, 182, 170);

        private string _placeholder = "说点什么…";
        private bool _textInputActive;
        private bool _expanded;
        private bool _startRequired;
        private bool _configRequired;
        private bool _chevronHover;
        private bool _actionHover;
        private float _chevronAngle;
        private float _chevronTarget;
        private DateTime _lastInteractionUtc;

        private Rectangle _chevronRect = Rectangle.Empty;
        private Rectangle _actionRect = Rectangle.Empty;
        private Rectangle _fieldRect = Rectangle.Empty;
        private Rectangle _counterRect = Rectangle.Empty;
        private float _uiScale;
        private Font _inputFont;
        private Font _smallFont;
        private Font _headerFont;
        private Font _actionFont;

        /// <summary>玩家发送：参数为已裁剪到 150 字的文本（调用方负责再去空白）。</summary>
        public event Action<string> SendRequested;

        /// <summary>终端未启动时点击展开后的“启动”：只拉起聊天终端，不发送输入。</summary>
        internal event Action StartRequested;

        /// <summary>终端已启动但模型未配置时点击展开后的“配置”：打开配置小窗。</summary>
        internal event Action ConfigRequested;

        /// <summary>焦点变化（true = 输入持有焦点）。调用方据此同步游戏热键放行。</summary>
        public event Action<bool> InputFocusChanged;

        /// <summary>收起/展开切换后触发：宿主据此重新定位窗口。</summary>
        internal event Action ExpandedChanged;

        /// <summary>当前是否为展开输入面板；默认 false（关闭钮左侧的收起箭头）。</summary>
        internal bool IsExpanded { get { return _expanded; } }

        public DialogueInterjectInputOverlay()
        {
            FormBorderStyle = FormBorderStyle.None;
            ShowInTaskbar = false;
            StartPosition = FormStartPosition.Manual;
            AutoScaleMode = AutoScaleMode.None;
            BackColor = _headerBack;
            DoubleBuffered = true;
            KeyPreview = true;
            Padding = new Padding(0);

            _textBox = new ComposingTextBox();
            _textBox.BorderStyle = BorderStyle.None;
            _textBox.BackColor = _fieldBack;
            _textBox.ForeColor = _bodyFore;
            _textBox.Font = new Font("Microsoft YaHei UI", 14f, FontStyle.Regular, GraphicsUnit.Pixel);
            _textBox.Multiline = true;
            _textBox.AutoSize = false;
            _textBox.ShortcutsEnabled = true;
            _textBox.TabStop = true;
            _textBox.Visible = false;
            _textBox.TextChanged += OnTextChanged;
            _textBox.KeyDown += OnKeyDown;
            _textBox.GotFocus += delegate { SetFocused(true); };
            _textBox.LostFocus += delegate
            {
                SetFocused(false);
                if (IsDisposed || !IsHandleCreated) return;
                BeginInvoke((Action)delegate
                {
                    if (IsDisposed || !_expanded || ContainsFocus) return;
                    Collapse(false);   // 点到游戏画面后自动收回收起按钮
                });
            };
            _textBox.CompositionStateChanged += OnCompositionStateChanged;
            Controls.Add(_textBox);

            // 多行 EDIT 不支持 EM_SETCUEBANNER，用同色 Label 承担占位文案。
            _placeholderLabel = new Label();
            _placeholderLabel.AutoSize = false;
            _placeholderLabel.TabStop = false;
            _placeholderLabel.TextAlign = ContentAlignment.TopLeft;
            _placeholderLabel.BackColor = _fieldBack;
            _placeholderLabel.ForeColor = Blend(_bodyFore, _fieldBack, 0.55f);
            _placeholderLabel.Cursor = Cursors.IBeam;
            _placeholderLabel.Visible = false;
            _placeholderLabel.Click += delegate { if (_model.Enabled) FocusInput(); };
            _placeholderLabel.MouseDown += delegate { NoteInteraction(); };
            Controls.Add(_placeholderLabel);
            _placeholderLabel.BringToFront();

            _toolTip = new ToolTip();
            _toolTip.InitialDelay = 350;
            _toolTip.ReshowDelay = 120;
            _toolTip.SetToolTip(this, _placeholder);

            _chevronTimer = new Timer();
            _chevronTimer.Interval = 15;
            _chevronTimer.Tick += OnChevronTick;

            DeriveInputColors();
            ApplyLayout();

            Enter += delegate { if (_expanded && _model.Enabled) _textBox.Focus(); };
        }

        /// <summary>
        /// 挂 Owner（必填 GuardianForm）：owned 顶层窗保证 z-order 跟着游戏窗口走，
        /// 又不会被 owner 的失活隐藏（本次配套的 P0.5 白名单在 NativeHudOverlay 侧）。
        /// </summary>
        public void AttachOwner(Form owner)
        {
            if (owner == null) return;
            Owner = owner;
        }

        /// <summary>本窗是否为本进程当前的系统前台（供 NativeHudOverlay 的白名单探针）。
        /// 输入焦点在 TextBox 子控件上时前景窗仍是本 Form，故只比 Form 句柄。</summary>
        public bool IsForegroundWindow()
        {
            IntPtr handle = Handle;   // 强制创建
            return handle != IntPtr.Zero && GetForegroundWindow() == handle;
        }

        /// <summary>
        /// 收起输入浮窗：把焦点还给 owner，并显式清一次文字输入态
        /// （焦点事件可能因为窗口已隐藏而丢失，不能只依赖 LostFocus）。
        /// </summary>
        public void DismissToOwner()
        {
            Collapse(false);
            ClearInput();
            SetFocused(false);
            Hide();
            Form owner = Owner;
            if (owner != null && !owner.IsDisposed)
            {
                try
                {
                    if (owner.WindowState == FormWindowState.Minimized)
                        owner.WindowState = FormWindowState.Normal;
                    owner.Activate();
                }
                catch { }
            }
        }

        /// <summary>从收起箭头展开输入面板（保持文本，就绪时聚焦输入框）。</summary>
        internal void Expand()
        {
            if (_expanded || !CanToggle || !Visible) return;
            _expanded = true;
            AnimateChevron(180f);
            ApplyLayout();
            NotifyExpandedChanged();
            if (_model.Enabled)
                BeginInvoke((Action)FocusInput);
        }

        /// <summary>回到收起箭头。returnFocus=true 时把焦点还给游戏。</summary>
        internal void Collapse(bool returnFocus)
        {
            if (!_expanded) return;
            _expanded = false;
            _textBox.Visible = false;
            AnimateChevron(0f);
            ApplyLayout();
            if (returnFocus)
            {
                SetFocused(false);
                Form owner = Owner;
                if (owner != null && !owner.IsDisposed)
                {
                    try { owner.Activate(); } catch { }
                }
            }
            NotifyExpandedChanged();
        }

        private bool CanToggle
        {
            get { return _model.Enabled || _startRequired || _configRequired; }
        }

        private bool ActionEnabled
        {
            get { return _startRequired || _configRequired || _model.CanSend; }
        }

        private void NotifyExpandedChanged()
        {
            Action handler = ExpandedChanged;
            if (handler == null) return;
            try { handler(); }
            catch { }
        }

        /// <summary>本窗当前是否处于"文字输入态"（宿主据此同步 KeyboardHook）。</summary>
        public bool IsTextInputActive()
        {
            return _textInputActive;
        }

        /// <summary>终端未启动：展开面板里显示“启动”，点击只拉起终端、不发送输入。</summary>
        internal void SetStartRequired(bool value)
        {
            if (_startRequired == value) return;
            _startRequired = value;
            if (value) Collapse(false);
            UpdateCursor();
            UpdateToolTip();
            Invalidate();
        }

        /// <summary>终端已启动但模型未配置：展开面板里显示“配置”，点击打开配置小窗。</summary>
        internal void SetConfigRequired(bool value)
        {
            if (_configRequired == value) return;
            _configRequired = value;
            if (value) Collapse(false);
            UpdateCursor();
            UpdateToolTip();
            Invalidate();
        }

        private void UpdateCursor()
        {
            bool clickable = _expanded
                ? (_chevronHover || (_actionHover && ActionEnabled))
                : (_chevronHover && CanToggle);
            Cursor = clickable ? Cursors.Hand : Cursors.Default;
        }

        private void UpdateToolTip()
        {
            string text = _startRequired ? "请先启动聊天终端"
                : (_configRequired ? "请配置模型API" : _placeholder);
            _toolTip.SetToolTip(this, text);
            _toolTip.SetToolTip(_textBox, text);
        }

        /// <summary>输入可用性（播放状态机给出）；禁用时灰显、自动收回收起按钮、Enter 不发。</summary>
        public void SetInputEnabled(bool value)
        {
            _model.Enabled = value;
            _textBox.ReadOnly = !value;
            _textBox.BackColor = value ? _fieldBack : _fieldDisabledBack;
            if (!value) Collapse(false);
            UpdatePlaceholder();
            UpdateCursor();
            Invalidate();
        }

        /// <summary>当前文本（只读观测）。</summary>
        public string GetInputText()
        {
            return _model.Text;
        }

        /// <summary>输入框是否持有焦点（供宿主同步热键门）。</summary>
        public bool IsInputFocused()
        {
            return _model.Focused;
        }

        /// <summary>视觉：把对话框皮肤的颜色交给输入层，保持风格一致。</summary>
        public void ApplySkinColors(Color background, Color foreground, Color accent)
        {
            _bodyBack = background;
            _bodyFore = foreground;
            _accent = accent;
            _bodyDisabledBack = Color.FromArgb(
                Math.Max(0, background.R - 15),
                Math.Max(0, background.G - 15),
                Math.Max(0, background.B - 15));
            DeriveInputColors();
            BackColor = _headerBack;
            _textBox.BackColor = _model.Enabled ? _fieldBack : _fieldDisabledBack;
            _textBox.ForeColor = _bodyFore;
            Invalidate();
        }

        /// <summary>输入槽沿用原版面板的中性灰阶：比正文略亮，边框直接用正文黑。</summary>
        private void DeriveInputColors()
        {
            _fieldBack = Blend(Color.FromArgb(232, 232, 232), _bodyBack, 0.30f);
            _fieldDisabledBack = Blend(_fieldBack, _bodyDisabledBack, 0.55f);
            _fieldBorder = _bodyFore;
        }

        private static Color Blend(Color a, Color b, float bWeight)
        {
            float w = Math.Max(0f, Math.Min(1f, bWeight));
            return Color.FromArgb(
                (int)Math.Round(a.R + (b.R - a.R) * w),
                (int)Math.Round(a.G + (b.G - a.G) * w),
                (int)Math.Round(a.B + (b.B - a.B) * w));
        }

        /// <summary>提示文案：收起按钮 Tooltip 与展开态输入框共用。</summary>
        public void SetPlaceholder(string text)
        {
            _placeholder = text ?? "";
            UpdatePlaceholder();
            UpdateToolTip();
            Invalidate();
        }

        /// <summary>多行输入框的占位文案：空文本且未聚焦时用同色 Label 盖在输入区上。</summary>
        private void UpdatePlaceholder()
        {
            if (_placeholderLabel == null) return;
            bool show = _expanded && !_model.Focused && _model.Text.Length == 0
                && !string.IsNullOrEmpty(_placeholder);
            _placeholderLabel.Text = _placeholder ?? "";
            _placeholderLabel.BackColor = _model.Enabled ? _fieldBack : _fieldDisabledBack;
            _placeholderLabel.ForeColor = _model.Enabled
                ? Blend(_bodyFore, _fieldBack, 0.55f)
                : Blend(_bodyFore, _fieldDisabledBack, 0.55f);
            _placeholderLabel.Visible = show;
            if (show) _placeholderLabel.BringToFront();
        }

        /// <summary>清空文本（发送后 / 本组结束）。</summary>
        public void ClearInput()
        {
            _model.Clear();
            _textBox.Text = "";
        }

        /// <summary>聚焦输入框（展开时调用）。</summary>
        public void FocusInput()
        {
            if (!Visible || !_expanded || !_model.Enabled) return;
            _textBox.Focus();
        }

        /// <summary>把焦点还给游戏（收缩/发送后）。</summary>
        public void ReleaseFocus()
        {
            SetFocused(false);
        }

        /// <summary>日志/验收用：IME 是否组词中。</summary>
        public bool IsImeComposing()
        {
            return _model.IsComposing;
        }

        /// <summary>焦点态切换（GotFocus/LostFocus 与宿主显式收起共用）。</summary>
        internal void SetFocused(bool focused)
        {
            if (_model.Focused == focused) return;
            _model.Focused = focused;
            _textInputActive = focused;
            UpdatePlaceholder();
            Invalidate();   // 焦点环
            Action<bool> handler = InputFocusChanged;
            if (handler != null)
            {
                try { handler(focused); }
                catch { }
            }
        }

        private void OnCompositionStateChanged(bool composing)
        {
            _model.IsComposing = composing;
        }

        private void OnTextChanged(object sender, EventArgs e)
        {
            bool truncated = _model.ApplyTextChange(_textBox.Text);
            if (truncated)
            {
                int caret = _model.Length;
                _textBox.Text = _model.Text;
                _textBox.SelectionStart = Math.Min(caret, _textBox.Text.Length);
            }
            UpdatePlaceholder();
            UpdateCursor();
            Invalidate();
        }

        private void OnKeyDown(object sender, KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Enter || e.KeyCode == Keys.Escape)
            {
                // 组词态以 WndProc 的 IME 标记为准；部分输入法不上报 STARTCOMPOSITION，
                // 再补一次 ImmGetCompositionString 现场探针。
                bool composing = _model.IsComposing || ProbeComposition(_textBox.Handle);
                _model.IsComposing = composing;
                if (e.KeyCode == Keys.Escape)
                {
                    // 非组词态 Esc 只收起输入面板，不关闭对话（协议 7.1）。
                    if (!composing)
                    {
                        e.Handled = true;
                        e.SuppressKeyPress = true;
                        Collapse(true);
                    }
                    return;
                }
                DialogueInterjectKeyResult result = _model.HandleKey(true, false);
                if (result != DialogueInterjectKeyResult.None)
                {
                    e.Handled = true;
                    e.SuppressKeyPress = true;
                }
                if (result == DialogueInterjectKeyResult.Send)
                {
                    SendCurrentText();
                }
            }
        }

        private void PerformAction()
        {
            if (_startRequired)
            {
                Action handler = StartRequested;
                if (handler != null) { try { handler(); } catch { } }
                return;
            }
            if (_configRequired)
            {
                Action handler = ConfigRequested;
                if (handler != null) { try { handler(); } catch { } }
                return;
            }
            if (_model.CanSend) SendCurrentText();
        }

        private void SendCurrentText()
        {
            string text = _model.Text;
            ClearInput();
            Collapse(true);
            Action<string> handler = SendRequested;
            if (handler != null)
            {
                try { handler(text); }
                catch { }
            }
        }

        /// <summary>IME 现场探针：有未提交组词串即为组词中。</summary>
        private static bool ProbeComposition(IntPtr hwnd)
        {
            if (hwnd == IntPtr.Zero) return false;
            IntPtr hImc = IntPtr.Zero;
            try
            {
                hImc = ImmGetContext(hwnd);
                if (hImc == IntPtr.Zero) return false;
                int len = ImmGetCompositionStringW(hImc, GCS_COMPSTR, null, 0);
                return len > 0;
            }
            catch
            {
                return false;
            }
            finally
            {
                if (hImc != IntPtr.Zero) ImmReleaseContext(hwnd, hImc);
            }
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            e.Graphics.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
            if (!_expanded)
            {
                PaintCollapsed(e.Graphics);
                return;
            }
            PaintExpanded(e.Graphics);
        }

        /// <summary>收起态：与展开态箭头同尺寸的黑色长方形开关，左上折角、白色箭头、无红色。</summary>
        private void PaintCollapsed(Graphics g)
        {
            Rectangle r = ClientRectangle;
            if (r.Width <= 0 || r.Height <= 0) return;

            int cut = Math.Max(4, (int)Math.Round(7 * _uiScale));
            using (GraphicsPath back = ChamferedRectPath(r, cut))
            using (SolidBrush fill = new SolidBrush(CanToggle ? _headerBack : Color.FromArgb(42, 42, 42)))
                g.FillPath(fill, back);

            // 原版头条右端的斜线刻纹，缩到按钮尺度只保留两道。
            using (Pen hatch = new Pen(Color.FromArgb(72, _headerFore)))
            {
                int step = Math.Max(4, (int)Math.Round(6 * _uiScale));
                for (int x = r.Width - step * 3; x < r.Width - 1; x += step)
                    g.DrawLine(hatch, x, r.Height - 2,
                        Math.Min(r.Width - 1, x + step), Math.Max(2, r.Height - 2 - step));
            }

            DrawChamferedBorder(g, r, cut,
                !CanToggle ? Color.FromArgb(72, 72, 72)
                : (_chevronHover ? Color.FromArgb(225, 225, 225) : Color.FromArgb(118, 118, 118)));

            DrawChevron(g, r.Width / 2f, r.Height / 2f, CanToggle ? _headerFore : _muted, r.Height);

            if (_startRequired || _configRequired)
            {
                float dot = Math.Max(4f, 5f * _uiScale);
                float x = r.Width - dot - Math.Max(4f, 5f * _uiScale);
                using (SolidBrush warn = new SolidBrush(Color.FromArgb(230, 230, 230)))
                    g.FillEllipse(warn, x, 4f, dot, dot);
            }
        }

        /// <summary>展开态：沿用原版对话框的黑色斜切头条 + 平直浅灰面板 + 方角输入槽。</summary>
        private void PaintExpanded(Graphics g)
        {
            int w = ClientSize.Width;
            int h = ClientSize.Height;
            if (w <= 0 || h <= 0) return;
            int headerH = HeaderHeight;
            int footerTop = h - FooterHeight;
            float ui = _uiScale;

            // 页眉：平涂 #191919，右端斜切角 + 斜线刻纹，取自对话框原版头条。
            using (SolidBrush header = new SolidBrush(_headerBack))
                g.FillRectangle(header, 0, 0, w, headerH);
            int cut = Math.Max(4, (int)Math.Round(6 * ui));
            using (Pen chamfer = new Pen(Color.FromArgb(110, _headerFore), Math.Max(1f, ui)))
                g.DrawLine(chamfer, w - cut, 0, w - 1, cut);
            PaintHeaderHatch(g, w - Math.Max(66, (int)Math.Round(96 * ui)),
                w - cut - Math.Max(6, (int)Math.Round(8 * ui)), headerH, ui);

            // 正文：与对话框一致的浅灰平涂底，不再做纸面渐变/纹理。
            Rectangle bodyRect = new Rectangle(0, headerH, w, Math.Max(1, footerTop - headerH));
            using (SolidBrush body = new SolidBrush(_bodyBack))
                g.FillRectangle(body, bodyRect);

            PaintHeaderTitle(g, headerH);

            // 输入槽：方角灰/黑边；聚焦只加粗为黑色 2px，不加颜色光晕。
            if (!_fieldRect.IsEmpty)
            {
                using (SolidBrush fill = new SolidBrush(_model.Enabled ? _fieldBack : _fieldDisabledBack))
                    g.FillRectangle(fill, _fieldRect);
                bool focused = _model.Enabled && _model.Focused;
                using (Pen edge = new Pen(focused ? _bodyFore : _fieldBorder,
                    focused ? Math.Max(2f, 2f * ui) : Math.Max(1f, ui)))
                {
                    edge.Alignment = PenAlignment.Inset;
                    g.DrawRectangle(edge, _fieldRect.X, _fieldRect.Y,
                        _fieldRect.Width - 1, _fieldRect.Height - 1);
                }
            }

            // 页脚：一条黑色细线 + 纯文字计数 + 黑色动作块 + 同尺寸箭头按钮。
            using (Pen separator = new Pen(_headerBack))
                g.DrawLine(separator, Pad, footerTop, w - Pad, footerTop);

            PaintCounter(g);

            if (!_actionRect.IsEmpty)
            {
                string label = _startRequired ? "启动" : (_configRequired ? "配置" : "发送");
                PaintActionButton(g, _actionRect, label, ActionEnabled);
            }

            PaintToggleButton(g, _chevronRect);

            DrawChamferedBorder(g, ClientRectangle,
                Math.Max(6, (int)Math.Round(12 * ui)), Color.FromArgb(190, _bodyFore));
        }

        /// <summary>展开态收起钮：与收起态同尺寸的长方形，浅灰底黑箭头，左上折角。</summary>
        private void PaintToggleButton(Graphics g, Rectangle rect)
        {
            if (rect.Width <= 0 || rect.Height <= 0) return;
            int cut = Math.Max(4, (int)Math.Round(7 * _uiScale));
            Color fill = !CanToggle ? Color.FromArgb(180, 180, 180)
                : (_chevronHover ? Color.FromArgb(168, 168, 168) : _bodyBack);
            using (GraphicsPath back = ChamferedRectPath(rect, cut))
            using (SolidBrush brush = new SolidBrush(fill))
                g.FillPath(brush, back);
            DrawChamferedBorder(g, rect, cut,
                !CanToggle ? Color.FromArgb(158, 158, 158)
                : (_chevronHover ? Color.FromArgb(82, 82, 82) : Color.FromArgb(122, 122, 122)));
            DrawChevron(g, rect.Left + rect.Width / 2f, rect.Top + rect.Height / 2f,
                CanToggle ? _bodyFore : _muted, rect.Height);
        }

        /// <summary>头条右端的 45° 斜线刻纹（原版对话框黑色头条的同款收尾）。</summary>
        private void PaintHeaderHatch(Graphics g, int left, int right, int headerH, float ui)
        {
            int width = right - left;
            if (width < 8 || headerH < 8) return;
            System.Drawing.Drawing2D.GraphicsState state = g.Save();
            try
            {
                g.SetClip(new Rectangle(left, 0, width, headerH));
                using (Pen hatch = new Pen(Color.FromArgb(86, _headerFore), Math.Max(1f, ui)))
                {
                    int step = Math.Max(4, (int)Math.Round(6 * ui));
                    for (int x = left; x < right + headerH; x += step)
                        g.DrawLine(hatch, x, headerH, x + headerH, 0);
                }
            }
            finally
            {
                g.Restore(state);
            }
        }

        /// <summary>头条：与对话框名字栏同一条黑色横带，只写「插话」，不加红色点色。</summary>
        private void PaintHeaderTitle(Graphics g, int headerH)
        {
            int textLeft = (int)Math.Round(Pad + Math.Max(2f, 2 * _uiScale));
            TextRenderer.DrawText(g, "插话", _headerFont,
                new Rectangle(textLeft, 0, Math.Max(20, ClientSize.Width - textLeft - Pad), headerH),
                _headerFore, TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix);
        }

        private void PaintCounter(Graphics g)
        {
            if (_counterRect.IsEmpty) return;
            TextRenderer.DrawText(g, _model.CounterText, _smallFont,
                new Rectangle(_counterRect.Left, _counterRect.Top,
                    _counterRect.Width, _counterRect.Height),
                Blend(_bodyFore, _bodyBack, 0.35f),
                TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix);
        }

        /// <summary>方角动作块：黑底白字，与整体灰黑面板一致；禁用时灰化但文案不变。</summary>
        private void PaintActionButton(Graphics g, Rectangle rect, string label, bool enabled)
        {
            if (rect.Width <= 0 || rect.Height <= 0) return;
            if (enabled)
            {
                Color fill = _actionHover ? Color.FromArgb(44, 44, 44) : _headerBack;
                using (SolidBrush brush = new SolidBrush(fill))
                    g.FillRectangle(brush, rect);
                using (Pen edge = new Pen(Color.FromArgb(110, 110, 110)))
                    g.DrawRectangle(edge, rect.X, rect.Y, rect.Width - 1, rect.Height - 1);
            }
            else
            {
                using (SolidBrush brush = new SolidBrush(Color.FromArgb(201, 201, 201)))
                    g.FillRectangle(brush, rect);
                using (Pen edge = new Pen(Color.FromArgb(150, 150, 150)))
                    g.DrawRectangle(edge, rect.X, rect.Y, rect.Width - 1, rect.Height - 1);
            }

            TextRenderer.DrawText(g, label, _actionFont, rect,
                enabled ? Color.White : Color.FromArgb(110, 110, 110),
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter
                | TextFormatFlags.NoPrefix);
        }

        /// <summary>左上折角的矩形路径；与对话框原版头条的缺口同形。</summary>
        internal static GraphicsPath ChamferedRectPath(Rectangle rect, int cut)
        {
            int max = Math.Max(0, Math.Min(rect.Width, rect.Height) / 2);
            cut = Math.Max(0, Math.Min(cut, max));
            var path = new GraphicsPath();
            path.AddPolygon(new PointF[]
            {
                new PointF(rect.Left + cut, rect.Top),
                new PointF(rect.Right, rect.Top),
                new PointF(rect.Right, rect.Bottom),
                new PointF(rect.Left, rect.Bottom),
                new PointF(rect.Left, rect.Top + cut)
            });
            path.CloseFigure();
            return path;
        }

        /// <summary>沿折角矩形画 1px 边线（含左上斜边）。</summary>
        private static void DrawChamferedBorder(Graphics g, Rectangle rect, int cut, Color color)
        {
            int max = Math.Max(0, Math.Min(rect.Width, rect.Height) / 2);
            cut = Math.Max(0, Math.Min(cut, max));
            float l = rect.Left + 0.5f;
            float t = rect.Top + 0.5f;
            float r = rect.Right - 0.5f;
            float b = rect.Bottom - 0.5f;
            using (Pen pen = new Pen(color))
            {
                g.DrawLines(pen, new PointF[]
                {
                    new PointF(l + cut, t),
                    new PointF(r, t),
                    new PointF(r, b),
                    new PointF(l, b),
                    new PointF(l, t + cut)
                });
                g.DrawLine(pen, l, t + cut, l + cut, t);
            }
        }

        /// <summary>0° = 向上箭头（收起态）；180° = 向下箭头（展开态）。</summary>
        private void DrawChevron(Graphics g, float cx, float cy, Color color, float buttonHeight)
        {
            System.Drawing.Drawing2D.GraphicsState state = g.Save();
            try
            {
                g.TranslateTransform(cx, cy);
                g.RotateTransform(_chevronAngle);
                float size = Math.Max(4.5f, Math.Min(8f, buttonHeight * 0.28f));
                using (Pen pen = new Pen(color, Math.Max(1.7f, size * 0.36f)))
                {
                    pen.StartCap = System.Drawing.Drawing2D.LineCap.Flat;
                    pen.EndCap = System.Drawing.Drawing2D.LineCap.Flat;
                    pen.LineJoin = System.Drawing.Drawing2D.LineJoin.Miter;
                    g.DrawLines(pen, new PointF[]
                    {
                        new PointF(-size, size * 0.45f),
                        new PointF(0f, -size * 0.55f),
                        new PointF(size, size * 0.45f)
                    });
                }
            }
            finally
            {
                g.Restore(state);
            }
        }

        private void AnimateChevron(float target)
        {
            _chevronTarget = target;
            if (Math.Abs(_chevronAngle - target) < 0.5f)
            {
                _chevronAngle = target;
                _chevronTimer.Stop();
                Invalidate();
                return;
            }
            _chevronTimer.Start();
        }

        private void OnChevronTick(object sender, EventArgs e)
        {
            float diff = _chevronTarget - _chevronAngle;
            if (Math.Abs(diff) <= 18f)
            {
                _chevronAngle = _chevronTarget;
                _chevronTimer.Stop();
            }
            else
            {
                _chevronAngle += Math.Sign(diff) * 18f;
            }
            Invalidate();
        }

        /// <summary>收起态整块是展开按钮；展开态只响应箭头、操作按钮与输入区。</summary>
        protected override void OnMouseDown(MouseEventArgs e)
        {
            base.OnMouseDown(e);
            NoteInteraction();
            if (e.Button != MouseButtons.Left) return;
            if (!_expanded)
            {
                if (CanToggle) Expand();
                return;
            }
            if (_chevronRect.Contains(e.Location))
            {
                Collapse(true);
                return;
            }
            if (_actionRect.Contains(e.Location) && ActionEnabled)
            {
                PerformAction();
                return;
            }
            if (_model.Enabled) FocusInput();
        }

        protected override void OnMouseMove(MouseEventArgs e)
        {
            base.OnMouseMove(e);
            bool chevronHover = _chevronRect.Contains(e.Location);
            bool actionHover = _expanded && _actionRect.Contains(e.Location) && ActionEnabled;
            if (chevronHover != _chevronHover || actionHover != _actionHover)
            {
                _chevronHover = chevronHover;
                _actionHover = actionHover;
                UpdateCursor();
                Invalidate();
            }
        }

        protected override void OnMouseLeave(EventArgs e)
        {
            base.OnMouseLeave(e);
            if (_chevronHover || _actionHover)
            {
                _chevronHover = false;
                _actionHover = false;
                UpdateCursor();
                Invalidate();
            }
        }

        protected override void WndProc(ref Message m)
        {
            // 顶层窗默认受系统最小跟踪尺寸约束（约 136×39）；收起按钮只有 38px，
            // 不解除的话箭头会被排到 68px 处，实际变成一个宽条。
            if (m.Msg == WM_GETMINMAXINFO)
            {
                base.WndProc(ref m);
                var info = (MinMaxInfo)Marshal.PtrToStructure(m.LParam, typeof(MinMaxInfo));
                info.MinTrackSize.X = 1;
                info.MinTrackSize.Y = 1;
                Marshal.StructureToPtr(info, m.LParam, false);
                return;
            }
            // WM_MOUSEACTIVATE 早于 owner 失活：提前记下交互，HUD 白名单才不会在点击瞬间隐藏对话。
            if (m.Msg == 0x0021) NoteInteraction();
            base.WndProc(ref m);
        }

        protected override void OnActivated(EventArgs e)
        {
            NoteInteraction();
            base.OnActivated(e);
        }

        private void NoteInteraction()
        {
            _lastInteractionUtc = DateTime.UtcNow;
        }

        /// <summary>HUD 失活白名单判据：输入窗是本会话前台，或刚刚发生过点击/激活
        /// （失活事件可能先于前台切换到达，用 1.5 秒窗口覆盖这个时序）。</summary>
        internal bool ShouldKeepHudPresented()
        {
            if (!Visible) return false;
            if (IsForegroundWindow()) return true;
            return (DateTime.UtcNow - _lastInteractionUtc).TotalMilliseconds < 1500;
        }

        /// <summary>Show() 不抢前台：收起按钮出现不该把焦点从游戏里抠走，点击后才激活。</summary>
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

        protected override void OnVisibleChanged(EventArgs e)
        {
            base.OnVisibleChanged(e);
            // 被直接 Hide（不经 DismissToOwner）时也要退出文字输入态，否则热键会一直放行。
            if (!Visible)
            {
                SetFocused(false);
                Collapse(false);
            }
        }

        protected override void OnResize(EventArgs e)
        {
            base.OnResize(e);
            ApplyLayout();
        }

        private int HeaderHeight { get { return Math.Max(26, (int)Math.Round(30 * _uiScale)); } }
        private int FooterHeight { get { return Math.Max(30, (int)Math.Round(38 * _uiScale)); } }
        private int Pad { get { return Math.Max(8, (int)Math.Round(12 * _uiScale)); } }

        /// <summary>收起态只排箭头按钮；展开态排头条、输入槽、计数、操作与旋转箭头。</summary>
        private void ApplyLayout()
        {
            if (_textBox == null) return;
            float ui = _expanded
                ? Math.Max(1f, Math.Min(2.4f, ClientSize.Height / DesignHeight))
                : Math.Max(1f, Math.Min(2.4f, ClientSize.Height / (float)ToggleHeightDesign));
            EnsureFonts(ui);

            _textBox.Visible = _expanded;
            if (!_expanded)
            {
                _chevronRect = ClientRectangle;
                _actionRect = Rectangle.Empty;
                _fieldRect = Rectangle.Empty;
                _counterRect = Rectangle.Empty;
                BackColor = _headerBack;
                if (_placeholderLabel != null) _placeholderLabel.Visible = false;
                ApplyWindowRegion();
                UpdateCursor();
                Invalidate();
                return;
            }

            BackColor = _bodyBack;
            int w = ClientSize.Width;
            int h = ClientSize.Height;
            int headerH = HeaderHeight;
            int footerH = FooterHeight;
            int pad = Pad;
            int gap = Math.Max(4, (int)Math.Round(6 * ui));
            int footerTop = h - footerH;

            // 输入框吃满头条与页脚之间的正文区，只留 6px 上下呼吸位；至少容纳三行。
            int bodyTop = headerH + gap;
            int bodyBottom = footerTop - gap;
            int fieldH = Math.Max(1, bodyBottom - bodyTop);
            _fieldRect = new Rectangle(pad, bodyTop, Math.Max(80, w - pad * 2), fieldH);

            int insetX = Math.Max(8, (int)Math.Round(12 * ui));
            int insetY = Math.Max(4, (int)Math.Round(6 * ui));
            int textH = Math.Max(1, fieldH - insetY * 2);
            _textBox.Bounds = new Rectangle(_fieldRect.Left + insetX, _fieldRect.Top + insetY,
                Math.Max(40, _fieldRect.Width - insetX * 2), textH);
            if (_textBox.IsHandleCreated) ApplyTextBoxMargins();
            if (_placeholderLabel != null)
            {
                _placeholderLabel.Bounds = _textBox.Bounds;
                _placeholderLabel.Padding = new Padding(
                    Math.Max(2, (int)Math.Round(4 * ui)),
                    Math.Max(1, (int)Math.Round(2 * ui)), 0, 0);
            }

            // 上下两个箭头开关共用同一尺寸；展开态只是转了 180°、换成浅底黑箭头。
            int toggleW = Math.Max(44, (int)Math.Round(ToggleWidthDesign * ui));
            int toggleH = Math.Max(26, (int)Math.Round(ToggleHeightDesign * ui));
            int toggleY = footerTop + Math.Max(0, (footerH - toggleH) / 2);
            _chevronRect = new Rectangle(w - pad - toggleW, toggleY, toggleW, toggleH);

            int actionW = Math.Max(58, (int)Math.Round(66 * ui));
            int actionX = _chevronRect.Left - gap - actionW;
            _actionRect = new Rectangle(actionX, toggleY, actionW, toggleH);

            int counterH = Math.Max(18, (int)Math.Round(21 * ui));
            int counterY = footerTop + Math.Max(0, (footerH - counterH) / 2);
            int counterW = Math.Max(46, (int)Math.Round(56 * ui));
            _counterRect = new Rectangle(pad, counterY, counterW, counterH);

            UpdatePlaceholder();
            ApplyWindowRegion();
            UpdateCursor();
            Invalidate();
        }

        /// <summary>窗口裁出左上折角；收起与展开用同一形状，只随状态换折角大小。</summary>
        private void ApplyWindowRegion()
        {
            if (ClientSize.Width <= 0 || ClientSize.Height <= 0) return;
            int cut = _expanded
                ? Math.Max(6, (int)Math.Round(12 * _uiScale))
                : Math.Max(4, (int)Math.Round(7 * _uiScale));
            using (GraphicsPath path = ChamferedRectPath(ClientRectangle, cut))
            {
                Region previous = Region;
                Region = new Region(path);
                if (previous != null) previous.Dispose();
            }
        }

        private void ApplyTextBoxMargins()
        {
            if (!_textBox.IsHandleCreated) return;
            int margin = Math.Max(2, (int)Math.Round(4 * _uiScale));
            int lParam = (margin & 0xFFFF) | ((margin & 0xFFFF) << 16);
            SendMessage(_textBox.Handle, EM_SETMARGINS,
                (IntPtr)(EC_LEFTMARGIN | EC_RIGHTMARGIN), (IntPtr)lParam);
        }

        protected override void OnHandleCreated(EventArgs e)
        {
            base.OnHandleCreated(e);
            ApplyTextBoxMargins();
        }

        private void EnsureFonts(float ui)
        {
            if (_inputFont != null && Math.Abs(ui - _uiScale) < 0.04f) return;
            _uiScale = ui;
            Font oldInput = _inputFont, oldSmall = _smallFont,
                oldHeader = _headerFont, oldAction = _actionFont;
            _inputFont = new Font("Microsoft YaHei UI", 14f * ui, FontStyle.Regular, GraphicsUnit.Pixel);
            _smallFont = new Font("Microsoft YaHei UI", 10f * ui, FontStyle.Regular, GraphicsUnit.Pixel);
            _headerFont = new Font("Microsoft YaHei UI", 12f * ui, FontStyle.Bold, GraphicsUnit.Pixel);
            _actionFont = new Font("Microsoft YaHei UI", 12f * ui, FontStyle.Regular, GraphicsUnit.Pixel);
            _textBox.Font = _inputFont;
            if (_placeholderLabel != null) _placeholderLabel.Font = _inputFont;
            if (oldInput != null) oldInput.Dispose();
            if (oldSmall != null) oldSmall.Dispose();
            if (oldHeader != null) oldHeader.Dispose();
            if (oldAction != null) oldAction.Dispose();
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                _chevronTimer.Stop();
                _chevronTimer.Dispose();
                _toolTip.Dispose();
                if (_inputFont != null) _inputFont.Dispose();
                if (_smallFont != null) _smallFont.Dispose();
                if (_headerFont != null) _headerFont.Dispose();
                if (_actionFont != null) _actionFont.Dispose();
            }
            base.Dispose(disposing);
        }

        /// <summary>
        /// 只用于把 WM_IME_* 翻译成组词标记；不改任何默认行为。
        /// 子类化 TextBox 而不是 Form：IME 消息目标是获得焦点的 EDIT 控件。
        /// </summary>
        private sealed class ComposingTextBox : TextBox
        {
            internal event Action<bool> CompositionStateChanged;

            private bool _composing;
            internal bool Composing { get { return _composing; } }

            private void SetComposing(bool value)
            {
                if (_composing == value) return;
                _composing = value;
                Action<bool> handler = CompositionStateChanged;
                if (handler != null)
                {
                    try { handler(value); }
                    catch { }
                }
            }

            protected override void WndProc(ref Message m)
            {
                if (m.Msg == WM_IME_STARTCOMPOSITION) SetComposing(true);
                else if (m.Msg == WM_IME_ENDCOMPOSITION) SetComposing(false);
                else if (m.Msg == WM_IME_COMPOSITION) SetComposing(ProbeComposition(Handle));
                base.WndProc(ref m);
            }
        }
    }
}
