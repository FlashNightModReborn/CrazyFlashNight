using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;
using CF7Launcher.Guardian.InputOwnership;

namespace CF7Launcher.Guardian
{
    internal sealed record TextInputClaim(ITextInputAuthority Authority, string SessionId, TextInputLease Lease)
    {
        private static long _focusSerial;
        internal static long NextFocusSerial() => Interlocked.Increment(ref _focusSerial);
    }

    /// <summary>
    /// 带有占位提示与 IME 组合输入感知的原生修改器文本框；不修改 Text 属性本身。
    /// </summary>
    internal sealed class ModifierTextBox : TextBox
    {
        private const int EM_SETMARGINS = 0x00D3;
        private const int EC_LEFTMARGIN = 0x0001;
        private const int EC_RIGHTMARGIN = 0x0002;
        private const int WM_PAINT = 0x000F;
        private const int WM_KILLFOCUS = 0x0008;
        private const int WM_IME_STARTCOMPOSITION = 0x010D;
        private const int WM_IME_ENDCOMPOSITION = 0x010E;
        private const int GCS_COMPSTR = 0x0008;

        [DllImport("user32.dll")]
        private static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);

        [DllImport("user32.dll")]
        private static extern bool HideCaret(IntPtr hWnd);

        [DllImport("user32.dll")]
        private static extern bool ShowCaret(IntPtr hWnd);

        [DllImport("imm32.dll")]
        private static extern IntPtr ImmGetContext(IntPtr hwnd);

        [DllImport("imm32.dll")]
        private static extern bool ImmReleaseContext(IntPtr hwnd, IntPtr context);

        [DllImport("imm32.dll", ExactSpelling = true)]
        private static extern int ImmGetCompositionStringW(IntPtr context, int index, IntPtr buffer, int length);

        private string _hintText = "";
        private Color _hintColor = Color.FromArgb(156, 156, 156);
        private int _horizontalMargin;
        private bool _imeComposing;
        private string _draftAtFocus;

        [DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
        internal string InputEndpointId { get; }
        [DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
        internal long InputInstanceGeneration { get; set; }
        [DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
        internal TextInputClaim TextFocus { get; set; }
        [DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
        internal TextInputClaim QueuedTextExit { get; set; }

        internal ModifierTextBox(string endpointId)
        {
            InputEndpointId = endpointId;
        }

        [DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
        internal bool IsImeComposing
        {
            get
            {
                if (_imeComposing) return true;
                if (!IsHandleCreated || !Focused) return false;
                IntPtr hwnd = Handle;
                IntPtr context = ImmGetContext(hwnd);
                if (context == IntPtr.Zero) return false;
                try { return ImmGetCompositionStringW(context, GCS_COMPSTR, IntPtr.Zero, 0) > 0; }
                finally { ImmReleaseContext(hwnd, context); }
            }
        }

        internal void RememberDraft() => _draftAtFocus = Text;

        internal void CancelDraft()
        {
            if (_draftAtFocus != null) Text = _draftAtFocus;
        }

        [DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
        internal string HintText
        {
            get { return _hintText; }
            set
            {
                string next = value ?? "";
                if (string.Equals(_hintText, next, StringComparison.Ordinal)) return;
                _hintText = next;
                if (IsHandleCreated) Invalidate();
            }
        }

        [DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
        internal Color HintColor
        {
            get { return _hintColor; }
            set
            {
                if (_hintColor == value) return;
                _hintColor = value;
                if (IsHandleCreated && IsShowingHint) Invalidate();
            }
        }

        [DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
        internal int HorizontalMargin
        {
            get { return _horizontalMargin; }
            set
            {
                int next = Math.Max(0, value);
                if (_horizontalMargin == next) return;
                _horizontalMargin = next;
                ApplyHorizontalMargin();
                if (IsHandleCreated && IsShowingHint) Invalidate();
            }
        }

        internal bool IsShowingHint
        {
            get { return !string.IsNullOrEmpty(_hintText) && TextLength == 0 && !_imeComposing; }
        }

        protected override void OnHandleCreated(EventArgs e)
        {
            base.OnHandleCreated(e);
            ApplyHorizontalMargin();
        }

        protected override void OnFontChanged(EventArgs e)
        {
            base.OnFontChanged(e);
            ApplyHorizontalMargin();
        }

        protected override void OnTextChanged(EventArgs e)
        {
            base.OnTextChanged(e);
            if (!string.IsNullOrEmpty(_hintText) && IsHandleCreated) Invalidate();
        }

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == WM_IME_STARTCOMPOSITION)
            {
                _imeComposing = true;
                base.WndProc(ref m);
                if (!string.IsNullOrEmpty(_hintText) && IsHandleCreated) Invalidate();
                return;
            }
            if (m.Msg == WM_IME_ENDCOMPOSITION || m.Msg == WM_KILLFOCUS)
            {
                _imeComposing = false;
                base.WndProc(ref m);
                if (!string.IsNullOrEmpty(_hintText) && IsHandleCreated) Invalidate();
                return;
            }

            base.WndProc(ref m);

            if (m.Msg == WM_PAINT && IsShowingHint && IsHandleCreated
                && ClientSize.Width > 0 && ClientSize.Height > 0)
            {
                PaintHintText();
            }
        }

        private void ApplyHorizontalMargin()
        {
            if (!IsHandleCreated) return;
            IntPtr lParam = (IntPtr)((_horizontalMargin << 16) | (_horizontalMargin & 0xFFFF));
            SendMessage(Handle, EM_SETMARGINS, (IntPtr)(EC_LEFTMARGIN | EC_RIGHTMARGIN), lParam);
        }

        private void PaintHintText()
        {
            int leftInset = _horizontalMargin + 1;
            var bounds = new Rectangle(
                leftInset,
                0,
                Math.Max(1, ClientSize.Width - leftInset - _horizontalMargin),
                Math.Max(1, ClientSize.Height));
            bool focused = Focused;
            if (focused) HideCaret(Handle);
            try
            {
                using (Graphics graphics = Graphics.FromHwnd(Handle))
                {
                    TextRenderer.DrawText(
                        graphics,
                        _hintText,
                        Font,
                        bounds,
                        _hintColor,
                        Color.Transparent,
                        TextFormatFlags.Left | TextFormatFlags.VerticalCenter
                            | TextFormatFlags.SingleLine | TextFormatFlags.NoPrefix
                            | TextFormatFlags.EndEllipsis);
                }
            }
            finally
            {
                if (focused) ShowCaret(Handle);
            }
        }
    }

    internal sealed class ModifierInputOverlay : Form
    {
        internal static readonly Color InputBorderColor = Color.White;

        private readonly Dictionary<TextBox, Rectangle> _frames = new Dictionary<TextBox, Rectangle>();

        internal ModifierInputOverlay(Form owner)
        {
            FormBorderStyle = FormBorderStyle.None;
            ShowInTaskbar = false;
            StartPosition = FormStartPosition.Manual;
            AutoScaleMode = AutoScaleMode.None;
            BackColor = Color.Magenta;
            TransparencyKey = Color.Magenta;
            DoubleBuffered = true;
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint, true);
            Owner = owner;
        }

        protected override bool ShowWithoutActivation { get { return true; } }

        protected override CreateParams CreateParams
        {
            get
            {
                CreateParams cp = base.CreateParams;
                cp.ExStyle |= 0x00000080 | 0x08000000;
                return cp;
            }
        }

        internal void SetInputFrame(TextBox input, Rectangle frame)
        {
            if (input == null) return;
            _frames[input] = frame;
            if (IsHandleCreated) Invalidate();
        }

        internal bool TryGetInputFrame(TextBox input, out Rectangle frame)
        {
            if (input == null)
            {
                frame = Rectangle.Empty;
                return false;
            }
            return _frames.TryGetValue(input, out frame);
        }

        internal void PaintInputFrames(Graphics graphics)
        {
            if (graphics == null) return;
            SmoothingMode previous = graphics.SmoothingMode;
            // 关闭抗锯齿，避免白色外框与 Magenta 透明键混合出粉边。
            graphics.SmoothingMode = SmoothingMode.None;
            try
            {
                using (var pen = new Pen(InputBorderColor, 1f))
                {
                    foreach (KeyValuePair<TextBox, Rectangle> pair in _frames)
                    {
                        Rectangle frame = pair.Value;
                        if (!pair.Key.Visible || frame.Width < 2 || frame.Height < 2) continue;
                        graphics.FillRectangle(Brushes.Black, frame);
                        graphics.DrawRectangle(pen, frame.X, frame.Y, frame.Width - 1, frame.Height - 1);
                    }
                }
            }
            finally
            {
                graphics.SmoothingMode = previous;
            }
        }

        internal bool OwnsCurrentPanelForeground(IntPtr window)
            => window != IntPtr.Zero && !IsDisposed && Visible && IsHandleCreated && window == Handle
                && Owner is ModifierNativeSurface panel && panel.OwnsCurrentPanelForeground(window);

        internal void Sync(bool visible, Rectangle bounds)
        {
            Bounds = bounds;
            if (visible && !Visible) Show();
            else if (!visible && Visible) Hide();
            if (visible && IsHandleCreated) Invalidate();
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            PaintInputFrames(e.Graphics);
        }

        protected override void OnMouseDown(MouseEventArgs e)
        {
            base.OnMouseDown(e);
            if (e.Button != MouseButtons.Left) return;
            foreach (KeyValuePair<TextBox, Rectangle> pair in _frames)
            {
                if (!pair.Key.Visible || !pair.Value.Contains(e.Location)) continue;
                pair.Key.Focus();
                if (pair.Key.TextAlign == HorizontalAlignment.Center) pair.Key.SelectAll();
                break;
            }
        }
    }
}
