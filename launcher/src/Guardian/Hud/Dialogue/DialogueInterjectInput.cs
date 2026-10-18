using System;
using System.Drawing;
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
    /// 由本类承载，位置由调用方按正文框屏幕矩形给出。
    ///
    /// 本类只做"输入 + 裁决 + 焦点广播"，不持有播放状态、不发请求；发送只经
    /// <see cref="SendRequested"/> 交给上层。未接线的行为见交付说明（P0 未做游戏内验证）。
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

        private const int GCS_COMPSTR = 0x0008;

        private readonly DialogueInterjectInputModel _model = new DialogueInterjectInputModel();
        private readonly ComposingTextBox _textBox;
        private readonly Label _counter;
        private Color _border = Color.FromArgb(196, 168, 108);
        private Color _back = Color.FromArgb(24, 22, 20);
        private Color _fore = Color.FromArgb(236, 230, 214);
        private Color _hint = Color.FromArgb(150, 144, 130);
        private string _placeholder = "说点什么…";

        /// <summary>玩家发送：参数为已裁剪到 150 字的文本（调用方负责再去空白）。</summary>
        public event Action<string> SendRequested;

        /// <summary>焦点变化（true = 输入持有焦点）。调用方据此同步游戏热键放行。</summary>
        public event Action<bool> InputFocusChanged;

        public DialogueInterjectInputOverlay()
        {
            FormBorderStyle = FormBorderStyle.None;
            ShowInTaskbar = false;
            StartPosition = FormStartPosition.Manual;
            AutoScaleMode = AutoScaleMode.None;
            BackColor = _back;
            DoubleBuffered = true;
            KeyPreview = true;
            Padding = new Padding(8, 6, 8, 4);

            _textBox = new ComposingTextBox();
            _textBox.BorderStyle = BorderStyle.None;
            _textBox.BackColor = _back;
            _textBox.ForeColor = _fore;
            _textBox.Font = new Font("Microsoft YaHei UI", 12f, FontStyle.Regular, GraphicsUnit.Pixel);
            _textBox.Multiline = false;
            _textBox.ShortcutsEnabled = true;
            _textBox.TabStop = true;
            _textBox.TextChanged += OnTextChanged;
            _textBox.KeyDown += OnKeyDown;
            _textBox.GotFocus += delegate { SetFocused(true); };
            _textBox.LostFocus += delegate { SetFocused(false); };
            _textBox.CompositionStateChanged += OnCompositionStateChanged;
            Controls.Add(_textBox);

            _counter = new Label();
            _counter.AutoSize = false;
            _counter.TextAlign = ContentAlignment.MiddleRight;
            _counter.ForeColor = _hint;
            _counter.BackColor = _back;
            _counter.Font = new Font("Microsoft YaHei UI", 10f, FontStyle.Regular, GraphicsUnit.Pixel);
            _counter.Text = _model.CounterText;
            Controls.Add(_counter);
            LayoutCounter();

            Enter += delegate { _textBox.Focus(); };
        }

        /// <summary>输入可用性（播放状态机给出）；禁用时灰显且 Enter 不发。</summary>
        public void SetInputEnabled(bool value)
        {
            _model.Enabled = value;
            _textBox.ReadOnly = !value;
            _textBox.BackColor = value ? _back : Color.FromArgb(38, 36, 33);
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

        /// <summary>视觉：把对话框皮肤的正文颜色/边框色交给输入层，保持风格一致。</summary>
        public void ApplySkinColors(Color background, Color foreground, Color accent)
        {
            _back = background;
            _fore = foreground;
            _border = accent;
            _hint = Color.FromArgb(150, foreground);
            BackColor = _back;
            _textBox.BackColor = _back;
            _textBox.ForeColor = _fore;
            _counter.BackColor = _back;
            _counter.ForeColor = _hint;
            Invalidate();
        }

        /// <summary>提示文案（收缩态/禁用态由调用方切换）。</summary>
        public void SetPlaceholder(string text)
        {
            _placeholder = text ?? "";
            Invalidate();
        }

        /// <summary>清空文本（发送后 / 本组结束）。</summary>
        public void ClearInput()
        {
            _model.Clear();
            _textBox.Text = "";
            _counter.Text = _model.CounterText;
        }

        /// <summary>聚焦输入框（展开时调用）。</summary>
        public void FocusInput()
        {
            if (!Visible) return;
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

        private void SetFocused(bool focused)
        {
            if (_model.Focused == focused) return;
            _model.Focused = focused;
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
            _counter.Text = _model.CounterText;
        }

        private void OnKeyDown(object sender, KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Enter || e.KeyCode == Keys.Escape)
            {
                // 组词态以 WndProc 的 IME 标记为准；部分输入法不上报 STARTCOMPOSITION，
                // 再补一次 ImmGetCompositionString 现场探针。
                bool composing = _model.IsComposing || ProbeComposition(_textBox.Handle);
                _model.IsComposing = composing;
                DialogueInterjectKeyResult result = _model.HandleKey(
                    e.KeyCode == Keys.Enter, e.KeyCode == Keys.Escape);
                if (result != DialogueInterjectKeyResult.None)
                {
                    e.Handled = true;
                    e.SuppressKeyPress = true;
                }
                if (result == DialogueInterjectKeyResult.Send)
                {
                    string text = _model.Text;
                    ClearInput();
                    Action<string> handler = SendRequested;
                    if (handler != null)
                    {
                        try { handler(text); }
                        catch { }
                    }
                }
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
            using (Pen pen = new Pen(_border))
                e.Graphics.DrawRectangle(pen, 0, 0, Width - 1, Height - 1);
            if (_model.IsEmpty && !_model.Focused)
            {
                using (SolidBrush brush = new SolidBrush(_hint))
                using (Font font = new Font(_textBox.Font.FontFamily, _textBox.Font.Size,
                    FontStyle.Italic, GraphicsUnit.Pixel))
                    e.Graphics.DrawString(_placeholder, font, brush, 10f, 7f);
            }
        }

        protected override void OnResize(EventArgs e)
        {
            base.OnResize(e);
            LayoutCounter();
        }

        private void LayoutCounter()
        {
            if (_counter == null) return;
            const int counterW = 48;
            int h = Math.Max(14, ClientSize.Height - 12);
            _counter.Bounds = new Rectangle(Math.Max(0, ClientSize.Width - counterW - 6), 6, counterW, h);
            if (_textBox != null)
                _textBox.Bounds = new Rectangle(8, 6,
                    Math.Max(10, ClientSize.Width - counterW - 20),
                    Math.Max(14, ClientSize.Height - 12));
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
