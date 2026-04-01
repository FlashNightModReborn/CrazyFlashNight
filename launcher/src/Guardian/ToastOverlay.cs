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
    public class ToastOverlay : OverlayBase, IToastSink
    {
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

        private readonly List<MessageLine> _lines;
        private readonly List<string> _earlyBuffer;
        private readonly System.Windows.Forms.Timer _timer;
        private bool _ready;
        private int _remainingMs;
        private float _globalAlpha;

        private Font _textFont;
        private int _lastVpW;

        public ToastOverlay(Form owner, Control anchor)
            : base(owner, anchor, 1024f, 576f)
        {
            _lines = new List<MessageLine>();
            _earlyBuffer = new List<string>();
            _ready = false;
            _remainingMs = 0;
            _globalAlpha = 0f;
            _lastVpW = 0;
            _textFont = new Font("Microsoft YaHei", 8f, FontStyle.Regular);

            _timer = new System.Windows.Forms.Timer();
            _timer.Interval = TickIntervalMs;
            _timer.Tick += OnTick;
        }

        #region Owner 跟随 (override)

        protected override void OnOwnerBecameVisible()
        {
            PaintLayered();
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

            ShowOverlay();

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
                _lines.Clear();
                _globalAlpha = 0f;
                DismissOverlay();
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

        protected override void OnPositionChanged()
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

                byte windowAlpha = (byte)(255 * _globalAlpha);
                CommitBitmap(bmp, scrX, scrY, windowAlpha);
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
