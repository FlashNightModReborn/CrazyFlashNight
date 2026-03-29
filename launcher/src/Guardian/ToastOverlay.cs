using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using System.Windows.Forms;

namespace CF7Launcher.Guardian
{
    /// <summary>
    /// 逐像素 Alpha Layered Window 覆盖层。
    /// 按 Flash 舞台坐标精确定位（考虑黑边），文字自动换行。
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
        private static readonly IntPtr HWND_TOPMOST = new IntPtr(-1);
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

        // Flash 舞台
        private const float StageW = 1024f;
        private const float StageH = 576f;
        private const float StageAspect = StageW / StageH;

        // 消息窗在 Flash 舞台上的坐标
        private const float FlashX = 5f;
        private const float FlashY = 50f;
        private const float FlashMsgW = 205f;

        // 配置 — 高度上限用 Flash 坐标像素，而非行数
        private const float FlashMaxH = 120f;  // Flash 舞台像素，约 8 行小字的高度
        private const int TickIntervalMs = 16;
        private const int DisplayLifetimeMs = 8000;
        private const int FadeInMs = 200;
        private const int FadeOutMs = 1200;
        private const int PaddingX = 2;
        private const int PaddingY = 1;

        // HTML 解析
        private static readonly Regex FontColorRegex = new Regex(
            @"<font\s+color=['""]?#([0-9A-Fa-f]{6})['""]?\s*>",
            RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex FontCloseRegex = new Regex(
            @"</font\s*>",
            RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex HtmlTagRegex = new Regex(
            @"<[^>]+>",
            RegexOptions.Compiled);

        private struct TextSegment
        {
            public string Text;
            public Color Color;
        }

        private class MessageLine
        {
            public List<TextSegment> Segments;
            public string PlainText;  // 拼接后的纯文本（用于换行测量）
            public int Age;
        }

        private readonly Form _owner;
        private readonly Control _anchor;
        private readonly List<MessageLine> _lines;
        private readonly List<string> _earlyBuffer;
        private readonly System.Windows.Forms.Timer _timer;
        private bool _ready;
        private int _remainingMs;
        private bool _shown;
        private float _globalAlpha;

        private Font _textFont;
        private int _lastPanelW;

        public ToastOverlay(Form owner, Control anchor)
        {
            _owner = owner;
            _anchor = anchor;
            _lines = new List<MessageLine>();
            _earlyBuffer = new List<string>();
            _ready = false;
            _shown = false;
            _remainingMs = 0;
            _globalAlpha = 0f;
            _lastPanelW = 0;
            _textFont = new Font("Microsoft YaHei", 9f, FontStyle.Regular);

            this.FormBorderStyle = FormBorderStyle.None;
            this.ShowInTaskbar = false;
            this.StartPosition = FormStartPosition.Manual;

            _timer = new System.Windows.Forms.Timer();
            _timer.Interval = TickIntervalMs;
            _timer.Tick += OnTick;

            CreateHandle();

            owner.Move += delegate { RepositionAndPaint(); };
            owner.Resize += delegate { RepositionAndPaint(); };
            anchor.Resize += delegate { RepositionAndPaint(); };
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

        /// <summary>
        /// 计算 Flash 内容在 panel 中的实际渲染区域（考虑黑边/letterbox）。
        /// Flash Player SA 保持宽高比居中显示。
        /// </summary>
        private void CalcFlashViewport(out float vpX, out float vpY, out float vpW, out float vpH)
        {
            int panelW = _anchor.Width;
            int panelH = _anchor.Height;
            float panelAspect = (float)panelW / panelH;

            if (panelAspect > StageAspect)
            {
                // panel 比舞台更宽 → 左右黑边
                vpH = panelH;
                vpW = panelH * StageAspect;
                vpX = (panelW - vpW) / 2f;
                vpY = 0;
            }
            else
            {
                // panel 比舞台更高 → 上下黑边
                vpW = panelW;
                vpH = panelW / StageAspect;
                vpX = 0;
                vpY = (panelH - vpH) / 2f;
            }
        }

        /// <summary>
        /// Flash 舞台坐标 → 屏幕像素坐标。
        /// </summary>
        private void FlashToScreen(float fx, float fy, out int sx, out int sy)
        {
            float vpX, vpY, vpW, vpH;
            CalcFlashViewport(out vpX, out vpY, out vpW, out vpH);

            Point origin;
            try { origin = _anchor.PointToScreen(Point.Empty); }
            catch { origin = Point.Empty; }

            sx = origin.X + (int)(vpX + fx / StageW * vpW);
            sy = origin.Y + (int)(vpY + fy / StageH * vpH);
        }

        /// <summary>
        /// Flash 舞台像素宽度 → 屏幕像素宽度。
        /// </summary>
        private int FlashScaleW(float flashPx)
        {
            float vpX, vpY, vpW, vpH;
            CalcFlashViewport(out vpX, out vpY, out vpW, out vpH);
            return Math.Max(1, (int)(flashPx / StageW * vpW));
        }

        /// <summary>
        /// Flash 舞台像素高度 → 屏幕像素高度。
        /// </summary>
        private int FlashScaleH(float flashPx)
        {
            float vpX, vpY, vpW, vpH;
            CalcFlashViewport(out vpX, out vpY, out vpW, out vpH);
            return Math.Max(1, (int)(flashPx / StageH * vpH));
        }

        private void EnsureFont()
        {
            float vpX, vpY, vpW, vpH;
            CalcFlashViewport(out vpX, out vpY, out vpW, out vpH);
            int roundedW = (int)vpW;
            if (roundedW == _lastPanelW) return;
            _lastPanelW = roundedW;

            float scale = vpW / StageW;
            float pt = 8f * scale;
            pt = Math.Max(6.5f, Math.Min(pt, 12f));

            if (_textFont != null) _textFont.Dispose();
            _textFont = new Font("Microsoft YaHei", pt, FontStyle.Regular);
        }

        private void AppendMessage(string text)
        {
            List<TextSegment> segments = ParseHtmlText(text);

            // 拼接纯文本
            string plain = "";
            for (int i = 0; i < segments.Count; i++)
                plain += segments[i].Text;

            MessageLine line = new MessageLine();
            line.Segments = segments;
            line.PlainText = plain;
            line.Age = 0;
            _lines.Add(line);

            // 按高度裁剪：计算总渲染高度，超出 FlashMaxH 时移除最老的行
            TrimByHeight();

            _remainingMs = DisplayLifetimeMs;
            _globalAlpha = 1f;

            if (!_timer.Enabled)
                _timer.Start();

            if (!_shown)
            {
                _shown = true;
                ShowWindow(this.Handle, SW_SHOWNOACTIVATE);
            }

            SetWindowPos(this.Handle, HWND_TOPMOST, 0, 0, 0, 0,
                SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);

            PaintLayered();
        }

        /// <summary>
        /// 按渲染高度裁剪：从最老的行开始移除，直到总高度不超过 FlashMaxH。
        /// </summary>
        private void TrimByHeight()
        {
            EnsureFont();
            int maxH = FlashScaleH(FlashMaxH);
            int textW = FlashScaleW(FlashMsgW) - PaddingX * 2;

            while (_lines.Count > 1)
            {
                int totalH = PaddingY;
                for (int i = 0; i < _lines.Count; i++)
                    totalH += MeasureLineHeight(_lines[i].PlainText, textW) + 1;
                totalH += PaddingY;

                if (totalH <= maxH)
                    break;
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
                this.Hide();
                _lines.Clear();
                _globalAlpha = 0f;
                return;
            }

            if (_remainingMs < FadeOutMs)
            {
                float t = (float)_remainingMs / FadeOutMs;
                _globalAlpha = t * t;
            }

            PaintLayered();
        }

        private void RepositionAndPaint()
        {
            if (_shown)
                PaintLayered();
        }

        /// <summary>
        /// 测量一行消息在指定宽度下的实际高度（含换行）。
        /// </summary>
        private int MeasureLineHeight(string plainText, int availW)
        {
            if (string.IsNullOrEmpty(plainText))
                return _textFont.Height;

            Size proposed = new Size(availW, int.MaxValue);
            Size measured = TextRenderer.MeasureText(plainText, _textFont, proposed,
                TextFormatFlags.WordBreak | TextFormatFlags.TextBoxControl);
            return Math.Max(_textFont.Height, measured.Height);
        }

        /// <summary>
        /// 渲染。无背景，文字自动换行，按 Flash 坐标精确定位。
        /// </summary>
        private void PaintLayered()
        {
            if (_lines.Count == 0) return;
            if (_anchor == null || _anchor.IsDisposed) return;

            EnsureFont();

            int toastW = FlashScaleW(FlashMsgW);
            int textW = toastW - PaddingX * 2;

            // 计算总高度（每行可能多行显示）
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
            FlashToScreen(FlashX, FlashY, out scrX, out scrY);

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

                        // 绘制区域
                        RectangleF textRect = new RectangleF(PaddingX, y, textW, lh);

                        if (line.Segments.Count == 1)
                        {
                            // 单色：直接用 DrawString + 自动换行
                            TextSegment seg = line.Segments[0];
                            byte a = (byte)(255 * lineAlpha);

                            using (StringFormat sf = new StringFormat())
                            {
                                sf.FormatFlags = 0; // 允许换行
                                sf.Trimming = StringTrimming.EllipsisWord;

                                // 阴影
                                RectangleF shadowRect = new RectangleF(
                                    textRect.X + 1, textRect.Y + 1,
                                    textRect.Width, textRect.Height);
                                using (SolidBrush shadow = new SolidBrush(
                                    Color.FromArgb((byte)(200 * lineAlpha), 0, 0, 0)))
                                {
                                    g.DrawString(seg.Text, _textFont, shadow, shadowRect, sf);
                                }

                                // 文字
                                using (SolidBrush brush = new SolidBrush(
                                    Color.FromArgb(a, seg.Color.R, seg.Color.G, seg.Color.B)))
                                {
                                    g.DrawString(seg.Text, _textFont, brush, textRect, sf);
                                }
                            }
                        }
                        else
                        {
                            // 多色 segment：逐段绘制（简单横排，超长时截断）
                            float x = PaddingX;
                            for (int s = 0; s < line.Segments.Count; s++)
                            {
                                TextSegment seg = line.Segments[s];
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

                // UpdateLayeredWindow
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

        #region HTML 解析

        private static List<TextSegment> ParseHtmlText(string raw)
        {
            List<TextSegment> result = new List<TextSegment>();
            if (string.IsNullOrEmpty(raw))
            {
                result.Add(new TextSegment { Text = "", Color = Color.White });
                return result;
            }

            string text = Regex.Replace(raw, @"<BR\s*/?>", " ", RegexOptions.IgnoreCase);

            Color currentColor = Color.White;
            Stack<Color> colorStack = new Stack<Color>();
            int pos = 0;

            while (pos < text.Length)
            {
                Match fontOpen = FontColorRegex.Match(text, pos);
                Match fontClose = FontCloseRegex.Match(text, pos);

                int nextOpen = fontOpen.Success ? fontOpen.Index : int.MaxValue;
                int nextClose = fontClose.Success ? fontClose.Index : int.MaxValue;
                int nextTag = Math.Min(nextOpen, nextClose);

                Match anyTag = HtmlTagRegex.Match(text, pos);
                int nextAny = anyTag.Success ? anyTag.Index : int.MaxValue;
                int nextEvent = Math.Min(nextTag, nextAny);

                if (nextEvent == int.MaxValue)
                {
                    string remainder = text.Substring(pos);
                    if (remainder.Length > 0)
                        result.Add(new TextSegment { Text = remainder, Color = currentColor });
                    break;
                }

                if (nextEvent > pos)
                {
                    string before = text.Substring(pos, nextEvent - pos);
                    if (before.Length > 0)
                        result.Add(new TextSegment { Text = before, Color = currentColor });
                }

                if (nextEvent == nextOpen && fontOpen.Success)
                {
                    colorStack.Push(currentColor);
                    string hex = fontOpen.Groups[1].Value;
                    try
                    {
                        int r = Convert.ToInt32(hex.Substring(0, 2), 16);
                        int gr = Convert.ToInt32(hex.Substring(2, 2), 16);
                        int b = Convert.ToInt32(hex.Substring(4, 2), 16);
                        currentColor = Color.FromArgb(r, gr, b);
                    }
                    catch { }
                    pos = fontOpen.Index + fontOpen.Length;
                }
                else if (nextEvent == nextClose && fontClose.Success)
                {
                    if (colorStack.Count > 0)
                        currentColor = colorStack.Pop();
                    else
                        currentColor = Color.White;
                    pos = fontClose.Index + fontClose.Length;
                }
                else if (anyTag.Success && anyTag.Index == nextEvent)
                {
                    pos = anyTag.Index + anyTag.Length;
                }
            }

            if (result.Count == 0)
                result.Add(new TextSegment { Text = "", Color = Color.White });

            return result;
        }

        #endregion

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
