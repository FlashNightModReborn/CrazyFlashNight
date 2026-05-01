using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.Windows.Forms;
using CF7Launcher.Guardian;

namespace CF7Launcher.Guardian.Hud
{
    /// <summary>
    /// Native toast 渲染单元。承载原 ToastOverlay 的消息流，
    /// 由 NativeHudOverlay.AddMessage / IToastSink.SetReady 派发；与 ToastOverlay 单独 ULW 路径互斥
    /// （useNativeHud=true 时 Program.cs 不再实例化 ToastOverlay，本 widget 顶替）。
    ///
    /// 数据通路：socket → WebOverlayForm.AddMessage → (useNativeHud=true) → IToastSink.AddMessage
    ///   → NativeHudOverlay.AddMessage → ToastWidget.AddMessage
    ///
    /// 视觉与原 ToastOverlay 严格对齐：
    /// - 锚点 Flash (5,50)，宽 285 base、letterbox 内缩放
    /// - 8 行上限，每条 8s 寿命，最后 1.2s 二次方淡出，前 0.2s 行级淡入
    /// - Microsoft YaHei 11px base，FlashHtmlParser 解析 font color/BR
    /// - alpha 在 segment 颜色里做（共享 NativeHud bitmap，无独立 ULW α）
    /// </summary>
    public sealed class ToastWidget : INativeHudWidget, IDisposable
    {
        private const float FlashX = 5f;
        private const float FlashY = 50f;
        private const float FlashMsgW = 285f;

        private const int DisplayLifetimeMs = 8000;
        private const int FadeInMs = 200;
        private const int FadeOutMs = 1200;
        private const int MaxLines = 8;
        private const int PaddingX = 2;
        private const int PaddingY = 1;

        private sealed class MessageLine
        {
            public List<FlashHtmlParser.TextSegment> Segments;
            public string PlainText;
            public int Age;
        }

        private readonly Control _anchor;
        private readonly FlashCoordinateMapper _mapper;
        private readonly List<MessageLine> _lines = new List<MessageLine>();
        private readonly List<string> _earlyBuffer = new List<string>();
        private bool _ready;
        private int _remainingMs;
        private float _globalAlpha;

        private Font _textFont;
        private float _lastFontScale = -1f;
        private float _lastBoundsScale = -1f;
        private int _measuredWidthPx;
        private int _measuredHeightPx;

        public event EventHandler BoundsOrVisibilityChanged;
        public event EventHandler RepaintRequested;
        public event EventHandler AnimationStateChanged;

        public ToastWidget(Control anchor)
        {
            if (anchor == null) throw new ArgumentNullException("anchor");
            _anchor = anchor;
            _mapper = new FlashCoordinateMapper(anchor, 1024f, 576f);
            _textFont = new Font("Microsoft YaHei", ToastFontPxForScale(1f), FontStyle.Regular, GraphicsUnit.Pixel);
            _anchor.Resize += delegate { FireBounds(); };
        }

        #region INativeHudWidget

        public Rectangle ScreenBounds
        {
            get
            {
                if (!Visible) return Rectangle.Empty;
                if (_anchor == null || !_anchor.IsHandleCreated) return Rectangle.Empty;
                EnsureFont();
                RecomputeMeasuredBoundsIfNeeded();
                int scrX, scrY;
                _mapper.FlashToScreen(FlashX, FlashY, out scrX, out scrY);
                return new Rectangle(scrX, scrY, _measuredWidthPx, Math.Max(4, _measuredHeightPx));
            }
        }

        public bool Visible { get { return _ready && _lines.Count > 0; } }

        public bool WantsAnimationTick { get { return _ready && _lines.Count > 0; } }

        public void Tick(int deltaMs)
        {
            if (_lines.Count == 0) return;
            int dt = Math.Max(1, deltaMs);
            _remainingMs -= dt;
            for (int i = 0; i < _lines.Count; i++)
                _lines[i].Age += dt;

            if (_remainingMs <= 0)
            {
                _lines.Clear();
                _globalAlpha = 0f;
                _lastBoundsScale = -1f;
                FireAnimationStateChanged();
                FireBounds();
                return;
            }

            if (_remainingMs < FadeOutMs)
            {
                float t = (float)_remainingMs / FadeOutMs;
                _globalAlpha = t * t;
            }
            FireRepaint();
        }

        public void Paint(Graphics g, float dpr, Point hudOrigin)
        {
            if (_lines.Count == 0) return;
            EnsureFont();
            float scale = GetViewportScale();
            int padX = Px(PaddingX, scale);
            int padY = Px(PaddingY, scale);
            int lineGap = Px(1, scale);
            float shadowOffset = Pxf(1f, scale);
            float segmentMeasureAdjust = Pxf(6f, scale);

            int toastW = _mapper.ScaleW(FlashMsgW);
            int textW = toastW - padX * 2;

            int scrX, scrY;
            _mapper.FlashToScreen(FlashX, FlashY, out scrX, out scrY);
            int localX = scrX - hudOrigin.X;
            int localY = scrY - hudOrigin.Y;

            SmoothingMode oldSmooth = g.SmoothingMode;
            TextRenderingHint oldHint = g.TextRenderingHint;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
            try
            {
                float y = localY + padY;
                float globalA = Math.Max(0f, Math.Min(1f, _globalAlpha));
                for (int i = 0; i < _lines.Count; i++)
                {
                    MessageLine line = _lines[i];
                    int lh = MeasureLineHeight(line.PlainText, textW);

                    float lineAlpha = 1f;
                    if (line.Age < FadeInMs)
                        lineAlpha = (float)line.Age / FadeInMs;
                    float a = lineAlpha * globalA;
                    if (a <= 0f) { y += lh + lineGap; continue; }

                    RectangleF textRect = new RectangleF(localX + padX, y, textW, lh);

                    if (line.Segments.Count == 1)
                    {
                        FlashHtmlParser.TextSegment seg = line.Segments[0];
                        byte aa = (byte)Math.Max(0, Math.Min(255, (int)(255 * a)));
                        byte sa = (byte)Math.Max(0, Math.Min(255, (int)(200 * a)));
                        using (StringFormat sf = new StringFormat())
                        {
                            sf.Trimming = StringTrimming.EllipsisWord;
                            RectangleF shadowRect = new RectangleF(
                                textRect.X + shadowOffset, textRect.Y + shadowOffset,
                                textRect.Width, textRect.Height);
                            using (SolidBrush shadow = new SolidBrush(Color.FromArgb(sa, 0, 0, 0)))
                                g.DrawString(seg.Text, _textFont, shadow, shadowRect, sf);
                            using (SolidBrush brush = new SolidBrush(Color.FromArgb(aa, seg.Color.R, seg.Color.G, seg.Color.B)))
                                g.DrawString(seg.Text, _textFont, brush, textRect, sf);
                        }
                    }
                    else
                    {
                        float x = localX + padX;
                        for (int s = 0; s < line.Segments.Count; s++)
                        {
                            FlashHtmlParser.TextSegment seg = line.Segments[s];
                            if (string.IsNullOrEmpty(seg.Text)) continue;
                            byte aa = (byte)Math.Max(0, Math.Min(255, (int)(255 * a)));
                            byte sa = (byte)Math.Max(0, Math.Min(255, (int)(200 * a)));
                            using (SolidBrush shadow = new SolidBrush(Color.FromArgb(sa, 0, 0, 0)))
                                g.DrawString(seg.Text, _textFont, shadow, x + shadowOffset, y + shadowOffset);
                            using (SolidBrush brush = new SolidBrush(Color.FromArgb(aa, seg.Color.R, seg.Color.G, seg.Color.B)))
                                g.DrawString(seg.Text, _textFont, brush, x, y);
                            Size ts = TextRenderer.MeasureText(seg.Text, _textFont,
                                new Size(int.MaxValue, int.MaxValue), TextFormatFlags.NoPadding);
                            x += ts.Width - segmentMeasureAdjust;
                        }
                    }

                    y += lh + lineGap;
                }
            }
            finally
            {
                g.SmoothingMode = oldSmooth;
                g.TextRenderingHint = oldHint;
            }
        }

        public bool TryHitTest(Point screenPt) { return false; }
        public void OnMouseEvent(MouseEventArgs e, MouseEventKind kind) { }

        #endregion

        #region 公共 API（由 NativeHudOverlay 在 UI 线程派发）

        public void SetReady()
        {
            _ready = true;
            if (_earlyBuffer.Count > 0)
            {
                List<string> flush = new List<string>(_earlyBuffer);
                _earlyBuffer.Clear();
                for (int i = 0; i < flush.Count; i++)
                    AppendMessage(flush[i]);
            }
            FireAnimationStateChanged();
            FireBounds();
        }

        public void AddMessage(string text)
        {
            if (!_ready)
            {
                _earlyBuffer.Add(text);
                return;
            }
            AppendMessage(text);
        }

        #endregion

        private void AppendMessage(string text)
        {
            bool wasEmpty = _lines.Count == 0;
            List<FlashHtmlParser.TextSegment> segments = FlashHtmlParser.Parse(text, " ");
            string plain = FlashHtmlParser.ToPlainText(segments);

            MessageLine line = new MessageLine();
            line.Segments = segments;
            line.PlainText = plain;
            line.Age = 0;
            _lines.Add(line);
            while (_lines.Count > MaxLines) _lines.RemoveAt(0);

            _remainingMs = DisplayLifetimeMs;
            _globalAlpha = 1f;
            _lastBoundsScale = -1f;

            if (wasEmpty) FireAnimationStateChanged();
            FireBounds();
            FireRepaint();
        }

        private void EnsureFont()
        {
            float scale = GetViewportScale();
            if (Math.Abs(scale - _lastFontScale) < 0.01f && _textFont != null) return;
            _lastFontScale = scale;
            if (_textFont != null) _textFont.Dispose();
            _textFont = new Font("Microsoft YaHei", ToastFontPxForScale(scale), FontStyle.Regular, GraphicsUnit.Pixel);
            _lastBoundsScale = -1f;
        }

        private void RecomputeMeasuredBoundsIfNeeded()
        {
            float scale = GetViewportScale();
            if (Math.Abs(scale - _lastBoundsScale) < 0.001f && _measuredHeightPx > 0) return;
            _lastBoundsScale = scale;
            int padX = Px(PaddingX, scale);
            int padY = Px(PaddingY, scale);
            int lineGap = Px(1, scale);
            int toastW = _mapper.ScaleW(FlashMsgW);
            int textW = toastW - padX * 2;
            int total = padY;
            for (int i = 0; i < _lines.Count; i++)
            {
                int lh = MeasureLineHeight(_lines[i].PlainText, textW);
                total += lh + lineGap;
            }
            total += padY;
            _measuredWidthPx = toastW;
            _measuredHeightPx = total;
        }

        private int MeasureLineHeight(string plainText, int availW)
        {
            if (string.IsNullOrEmpty(plainText)) return _textFont.Height;
            Size proposed = new Size(availW, int.MaxValue);
            Size measured = TextRenderer.MeasureText(plainText, _textFont, proposed,
                TextFormatFlags.WordBreak | TextFormatFlags.TextBoxControl);
            return Math.Max(_textFont.Height, measured.Height);
        }

        private float GetViewportScale()
        {
            float vpX, vpY, vpW, vpH;
            _mapper.CalcViewport(out vpX, out vpY, out vpW, out vpH);
            if (vpH <= 0) return 1f;
            return Math.Max(0.5f, vpH / _mapper.StageHeight);
        }

        private static int Px(int basePx, float scale)
        {
            return Math.Max(1, (int)Math.Round(basePx * scale));
        }

        private static float Pxf(float basePx, float scale)
        {
            return Math.Max(1f, basePx * scale);
        }

        internal static float ToastFontPxForScale(float scale)
        {
            return Math.Max(1f, 11f * scale);
        }

        private void FireBounds()
        {
            EventHandler h = BoundsOrVisibilityChanged;
            if (h != null) h(this, EventArgs.Empty);
        }
        private void FireRepaint()
        {
            EventHandler h = RepaintRequested;
            if (h != null) h(this, EventArgs.Empty);
        }
        private void FireAnimationStateChanged()
        {
            EventHandler h = AnimationStateChanged;
            if (h != null) h(this, EventArgs.Empty);
        }

        public void Dispose()
        {
            if (_textFont != null) { _textFont.Dispose(); _textFont = null; }
        }
    }
}
