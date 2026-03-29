using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace CF7Launcher.Guardian
{
    /// <summary>
    /// 逐像素 Alpha Layered Window 覆盖层。
    /// 使用 FlashCoordinateMapper 定位，FlashHtmlParser 解析文本。
    /// Owner 跟随：最小化/Alt-Tab 时自动隐藏，不会悬浮到其他应用上。
    /// </summary>
    public class ToastOverlay : Form
    {
        #region Win32

        [DllImport("user32.dll")]
        private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

        [DllImport("user32.dll")]
        private static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter,
            int X, int Y, int cx, int cy, uint uFlags);

        [DllImport("user32.dll", ExactSpelling = true, SetLastError = true)]
        private static extern bool UpdateLayeredWindow(IntPtr hwnd, IntPtr hdcDst,
            ref POINT pptDst, ref SIZE psize, IntPtr hdcSrc,
            ref POINT pptSrc, uint crKey, ref BLENDFUNCTION pblend, uint dwFlags);

        [DllImport("gdi32.dll", ExactSpelling = true, SetLastError = true)]
        private static extern IntPtr CreateCompatibleDC(IntPtr hdc);

        [DllImport("gdi32.dll", ExactSpelling = true)]
        private static extern IntPtr SelectObject(IntPtr hdc, IntPtr hObj);

        [DllImport("gdi32.dll", ExactSpelling = true, SetLastError = true)]
        private static extern bool DeleteObject(IntPtr hObj);

        [DllImport("gdi32.dll", ExactSpelling = true, SetLastError = true)]
        private static extern bool DeleteDC(IntPtr hdc);

        [StructLayout(LayoutKind.Sequential)]
        private struct POINT { public int x, y; }

        [StructLayout(LayoutKind.Sequential)]
        private struct SIZE { public int cx, cy; }

        [StructLayout(LayoutKind.Sequential, Pack = 1)]
        private struct BLENDFUNCTION
        {
            public byte BlendOp;
            public byte BlendFlags;
            public byte SourceConstantAlpha;
            public byte AlphaFormat;
        }

        private const int SW_SHOWNOACTIVATE = 4;
        private const int SW_HIDE = 0;
        private static readonly IntPtr HWND_TOP = new IntPtr(0);
        private const uint SWP_NOMOVE = 0x0002;
        private const uint SWP_NOSIZE = 0x0001;
        private const uint SWP_NOACTIVATE = 0x0010;
        private const byte AC_SRC_OVER = 0x00;
        private const byte AC_SRC_ALPHA = 0x01;
        private const uint ULW_ALPHA = 0x02;

        private const int WS_EX_TOOLWINDOW = 0x00000080;
        private const int WS_EX_NOACTIVATE = 0x08000000;
        private const int WS_EX_LAYERED = 0x00080000;
        private const int WS_EX_TRANSPARENT = 0x00000020;
        private const int WM_NCHITTEST = 0x0084;
        private const int HTTRANSPARENT = -1;

        #endregion

        // 消息窗在 Flash 舞台上的坐标
        private const float FlashX = 5f;
        private const float FlashY = 50f;
        private const float FlashMsgW = 205f;
        private const float FlashMaxH = 120f;

        // 配置
        private const int TickIntervalMs = 16;
        private const int DisplayLifetimeMs = 8000;
        private const int FadeInMs = 200;
        private const int FadeOutMs = 1200;
        private const int PaddingX = 2;
        private const int PaddingY = 1;

        private class MessageLine
        {
            public List<FlashHtmlParser.TextSegment> Segments;
            public string PlainText;
            public int Age;
        }

        private readonly Form _owner;
        private readonly FlashCoordinateMapper _mapper;
        private readonly List<MessageLine> _lines;
        private readonly List<string> _earlyBuffer;
        private readonly System.Windows.Forms.Timer _timer;
        private bool _ready;
        private int _remainingMs;
        private bool _shown;
        private bool _ownerVisible;  // owner 是否在前台
        private float _globalAlpha;

        private Font _textFont;
        private int _lastVpW;

        public ToastOverlay(Form owner, Control anchor)
        {
            _owner = owner;
            _mapper = new FlashCoordinateMapper(anchor, 1024f, 576f);
            _lines = new List<MessageLine>();
            _earlyBuffer = new List<string>();
            _ready = false;
            _shown = false;
            _ownerVisible = true;
            _remainingMs = 0;
            _globalAlpha = 0f;
            _lastVpW = 0;
            _textFont = new Font("Microsoft YaHei", 8f, FontStyle.Regular);

            this.FormBorderStyle = FormBorderStyle.None;
            this.ShowInTaskbar = false;
            this.StartPosition = FormStartPosition.Manual;
            this.Owner = owner;  // Win32 owner 关系：最小化时自动跟随

            _timer = new System.Windows.Forms.Timer();
            _timer.Interval = TickIntervalMs;
            _timer.Tick += OnTick;

            CreateHandle();

            // 位置跟踪
            owner.Move += delegate { RepositionAndPaint(); };
            owner.Resize += delegate { RepositionAndPaint(); };
            anchor.Resize += delegate { RepositionAndPaint(); };

            // Owner 可见性跟踪：Alt-Tab / 最小化时隐藏 toast
            owner.Activated += delegate { OnOwnerActivated(); };
            owner.Deactivate += delegate { OnOwnerDeactivated(); };
            owner.Resize += delegate
            {
                if (owner.WindowState == FormWindowState.Minimized)
                    OnOwnerDeactivated();
                else
                    OnOwnerActivated();
            };
        }

        protected override CreateParams CreateParams
        {
            get
            {
                CreateParams cp = base.CreateParams;
                cp.ExStyle |= WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE
                             | WS_EX_LAYERED | WS_EX_TRANSPARENT;
                return cp;
            }
        }

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == WM_NCHITTEST)
            {
                m.Result = (IntPtr)HTTRANSPARENT;
                return;
            }
            base.WndProc(ref m);
        }

        #region Owner 跟随

        private void OnOwnerActivated()
        {
            _ownerVisible = true;
            if (_shown && _lines.Count > 0)
            {
                ShowWindow(this.Handle, SW_SHOWNOACTIVATE);
                PaintLayered();
            }
        }

        private void OnOwnerDeactivated()
        {
            _ownerVisible = false;
            if (_shown)
                ShowWindow(this.Handle, SW_HIDE);
        }

        #endregion

        #region 公开接口

        public void SetReady()
        {
            _ready = true;
            foreach (string msg in _earlyBuffer)
                AppendMessage(msg);
            _earlyBuffer.Clear();
        }

        public void AddMessage(string text)
        {
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action<string>(AddMessage), text);
                return;
            }
            if (!_ready)
            {
                _earlyBuffer.Add(text);
                return;
            }
            AppendMessage(text);
        }

        #endregion

        private void EnsureFont()
        {
            int vpW = (int)_mapper.ViewportWidth;
            if (vpW == _lastVpW) return;
            _lastVpW = vpW;

            float scale = _mapper.ViewportWidth / _mapper.StageWidth;
            float pt = 8f * scale;
            pt = Math.Max(6.5f, Math.Min(pt, 12f));

            if (_textFont != null) _textFont.Dispose();
            _textFont = new Font("Microsoft YaHei", pt, FontStyle.Regular);
        }

        private void AppendMessage(string text)
        {
            List<FlashHtmlParser.TextSegment> segments = FlashHtmlParser.Parse(text, " ");
            string plain = FlashHtmlParser.ToPlainText(segments);

            MessageLine line = new MessageLine();
            line.Segments = segments;
            line.PlainText = plain;
            line.Age = 0;
            _lines.Add(line);

            TrimByHeight();

            _remainingMs = DisplayLifetimeMs;
            _globalAlpha = 1f;

            if (!_timer.Enabled)
                _timer.Start();

            if (!_shown)
                _shown = true;

            if (_ownerVisible)
            {
                ShowWindow(this.Handle, SW_SHOWNOACTIVATE);
                // HWND_TOP 而非 HWND_TOPMOST：保持在 owner 之上，但不遮挡其他应用
                SetWindowPos(this.Handle, HWND_TOP, 0, 0, 0, 0,
                    SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
            }

            PaintLayered();
        }

        private void TrimByHeight()
        {
            EnsureFont();
            int maxH = _mapper.ScaleH(FlashMaxH);
            int textW = _mapper.ScaleW(FlashMsgW) - PaddingX * 2;

            while (_lines.Count > 1)
            {
                int totalH = PaddingY;
                for (int i = 0; i < _lines.Count; i++)
                    totalH += MeasureLineHeight(_lines[i].PlainText, textW) + 1;
                totalH += PaddingY;

                if (totalH <= maxH) break;
                _lines.RemoveAt(0);
            }
        }

        private void OnTick(object sender, EventArgs e)
        {
            _remainingMs -= TickIntervalMs;

            for (int i = 0; i < _lines.Count; i++)
                _lines[i].Age += TickIntervalMs;

            if (_remainingMs <= 0)
            {
                _timer.Stop();
                _shown = false;
                ShowWindow(this.Handle, SW_HIDE);
                _lines.Clear();
                _globalAlpha = 0f;
                return;
            }

            if (_remainingMs < FadeOutMs)
            {
                float t = (float)_remainingMs / FadeOutMs;
                _globalAlpha = t * t;
            }

            if (_ownerVisible)
                PaintLayered();
        }

        private void RepositionAndPaint()
        {
            if (_shown && _ownerVisible)
                PaintLayered();
        }

        private int MeasureLineHeight(string plainText, int availW)
        {
            if (string.IsNullOrEmpty(plainText))
                return _textFont.Height;

            Size proposed = new Size(availW, int.MaxValue);
            Size measured = TextRenderer.MeasureText(plainText, _textFont, proposed,
                TextFormatFlags.WordBreak | TextFormatFlags.TextBoxControl);
            return Math.Max(_textFont.Height, measured.Height);
        }

        private void PaintLayered()
        {
            if (_lines.Count == 0) return;

            EnsureFont();

            int toastW = _mapper.ScaleW(FlashMsgW);
            int textW = toastW - PaddingX * 2;

            int totalH = PaddingY;
            int[] lineHeights = new int[_lines.Count];
            for (int i = 0; i < _lines.Count; i++)
            {
                lineHeights[i] = MeasureLineHeight(_lines[i].PlainText, textW);
                totalH += lineHeights[i] + 1;
            }
            totalH += PaddingY;

            int w = toastW;
            int h = Math.Max(4, totalH);

            int scrX, scrY;
            _mapper.FlashToScreen(FlashX, FlashY, out scrX, out scrY);

            using (Bitmap bmp = new Bitmap(w, h, PixelFormat.Format32bppPArgb))
            {
                using (Graphics g = Graphics.FromImage(bmp))
                {
                    g.SmoothingMode = SmoothingMode.AntiAlias;
                    g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
                    g.Clear(Color.Transparent);

                    float y = PaddingY;
                    for (int i = 0; i < _lines.Count; i++)
                    {
                        MessageLine line = _lines[i];
                        int lh = lineHeights[i];

                        float lineAlpha = 1f;
                        if (line.Age < FadeInMs)
                            lineAlpha = (float)line.Age / FadeInMs;

                        RectangleF textRect = new RectangleF(PaddingX, y, textW, lh);

                        if (line.Segments.Count == 1)
                        {
                            FlashHtmlParser.TextSegment seg = line.Segments[0];
                            byte a = (byte)(255 * lineAlpha);

                            using (StringFormat sf = new StringFormat())
                            {
                                sf.Trimming = StringTrimming.EllipsisWord;

                                RectangleF shadowRect = new RectangleF(
                                    textRect.X + 1, textRect.Y + 1,
                                    textRect.Width, textRect.Height);
                                using (SolidBrush shadow = new SolidBrush(
                                    Color.FromArgb((byte)(200 * lineAlpha), 0, 0, 0)))
                                {
                                    g.DrawString(seg.Text, _textFont, shadow, shadowRect, sf);
                                }

                                using (SolidBrush brush = new SolidBrush(
                                    Color.FromArgb(a, seg.Color.R, seg.Color.G, seg.Color.B)))
                                {
                                    g.DrawString(seg.Text, _textFont, brush, textRect, sf);
                                }
                            }
                        }
                        else
                        {
                            float x = PaddingX;
                            for (int s = 0; s < line.Segments.Count; s++)
                            {
                                FlashHtmlParser.TextSegment seg = line.Segments[s];
                                if (string.IsNullOrEmpty(seg.Text)) continue;

                                byte a = (byte)(255 * lineAlpha);

                                using (SolidBrush shadow = new SolidBrush(
                                    Color.FromArgb((byte)(200 * lineAlpha), 0, 0, 0)))
                                {
                                    g.DrawString(seg.Text, _textFont, shadow, x + 1, y + 1);
                                }

                                using (SolidBrush brush = new SolidBrush(
                                    Color.FromArgb(a, seg.Color.R, seg.Color.G, seg.Color.B)))
                                {
                                    g.DrawString(seg.Text, _textFont, brush, x, y);
                                }

                                Size ts = TextRenderer.MeasureText(seg.Text, _textFont,
                                    new Size(int.MaxValue, int.MaxValue), TextFormatFlags.NoPadding);
                                x += ts.Width - 6;
                            }
                        }

                        y += lh + 1;
                    }
                }

                IntPtr hdcScreen = IntPtr.Zero;
                IntPtr hdcMem = CreateCompatibleDC(hdcScreen);
                IntPtr hBmp = bmp.GetHbitmap(Color.FromArgb(0));
                IntPtr hOld = SelectObject(hdcMem, hBmp);

                try
                {
                    byte windowAlpha = (byte)(255 * _globalAlpha);

                    POINT ptDst = new POINT { x = scrX, y = scrY };
                    SIZE sz = new SIZE { cx = w, cy = h };
                    POINT ptSrc = new POINT { x = 0, y = 0 };
                    BLENDFUNCTION blend = new BLENDFUNCTION
                    {
                        BlendOp = AC_SRC_OVER,
                        BlendFlags = 0,
                        SourceConstantAlpha = windowAlpha,
                        AlphaFormat = AC_SRC_ALPHA
                    };

                    UpdateLayeredWindow(this.Handle, hdcScreen,
                        ref ptDst, ref sz, hdcMem, ref ptSrc, 0, ref blend, ULW_ALPHA);
                }
                finally
                {
                    SelectObject(hdcMem, hOld);
                    DeleteObject(hBmp);
                    DeleteDC(hdcMem);
                }
            }
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                _timer.Stop();
                _timer.Dispose();
                if (_textFont != null)
                    _textFont.Dispose();
            }
            base.Dispose(disposing);
        }
    }
}
