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
    /// Native fallback 消息行（原左上 toast）。承载 socket（ToastTask，即 AS2 `_root.发布消息`）中
    /// 尚未结构化的文本消息，由 NativeHudOverlay.AddMessage / IToastSink.SetReady 派发。
    ///
    /// 数据通路：
    ///   socket → WebOverlayForm.AddMessage → IToastSink.AddMessage → NativeHudOverlay.AddMessage → ToastWidget.AddMessage
    ///   面板 Toast.add 的操作回执已改走刘海临时行（WebOverlayForm.AddPanelToast），不再进入本 widget。
    ///
    /// 位置与视觉（docs/上层HUD风格锚定与分区仲裁-ADR-2026-11-05.md D4–D6）：
    /// - BL 事件流：下沿紧贴结构化事件卡上方（无卡时贴 460），向上增长，最新消息在最下；
    ///   上沿让位 TL 状态列（Buff/聚焦目标），放不下时只显示最新的若干行，绝不覆盖状态列。
    /// - 每行为“左侧细银轨 + 半透明渐隐底”的日志行，保留 Flash HTML 的 font color / BR。
    /// - 8 行上限，每条 8s 寿命，最后 1.2s 二次方淡出，前 0.2s 行级淡入（沿用原合同）。
    /// - alpha 在 segment 颜色里做（共享 NativeHud bitmap，无独立 ULW α）。
    /// </summary>
    public sealed class ToastWidget : INativeHudWidget, IDisposable
    {
        private const float FlashX = HudZoneLayout.LeftColumnX;
        private const float FlashMsgW = 285f;

        private const int DisplayLifetimeMs = 8000;
        private const int FadeInMs = 200;
        private const int FadeOutMs = 1200;
        private const int MaxLines = 8;
        private const int PaddingX = 9;
        private const int PaddingY = 1;
        private const int LineGapBase = 2;

        private static readonly StringFormat SegmentFormat = CreateSegmentFormat();

        private static StringFormat CreateSegmentFormat()
        {
            StringFormat f = (StringFormat)StringFormat.GenericTypographic.Clone();
            f.FormatFlags |= StringFormatFlags.MeasureTrailingSpaces | StringFormatFlags.NoWrap;
            return f;
        }

        private sealed class MessageLine
        {
            public List<FlashHtmlParser.TextSegment> Segments;
            public string PlainText;
            public int Age;
            public int HeightPx;
            public int TextWidthPx;
            public FlashTextLayout Layout;
        }

        private readonly Control _anchor;
        private readonly FlashCoordinateMapper _mapper;
        private readonly List<MessageLine> _lines = new List<MessageLine>();
        private readonly List<string> _earlyBuffer = new List<string>();
        private readonly EventHandler _zoneChanged;
        private bool _ready;
        private int _remainingMs;
        private float _globalAlpha;

        private Font _textFont;
        private float _lastFontScale = -1f;
        private float _lastBoundsScale = -1f;
        private int _lastRegionPx = -1;
        private int _visibleStart;
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
            _textFont = NativeHudFonts.CreateUiFont(ToastFontPxForScale(1f), FontStyle.Regular, GraphicsUnit.Pixel);
            _anchor.Resize += delegate { FireBounds(); };
            _zoneChanged = delegate
            {
                _lastBoundsScale = -1f;
                if (_lines.Count == 0) return;
                FireBounds();
                FireRepaint();
            };
            HudZoneLayout.Changed += _zoneChanged;
        }

        #region INativeHudWidget

        public Rectangle ScreenBounds
        {
            get
            {
                if (!Visible) return Rectangle.Empty;
                if (_anchor == null || !_anchor.IsHandleCreated) return Rectangle.Empty;
                return ComputeBounds();
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
            Rectangle bounds = ComputeBounds();
            if (bounds.Width <= 0 || bounds.Height <= 0) return;
            float scale = GetViewportScale();
            int padX = Px(PaddingX, scale);
            int padY = Px(PaddingY, scale);
            int lineGap = Px(LineGapBase, scale);
            int railW = Math.Max(2, Px(2, scale));
            float shadowOffset = Pxf(1f, scale);
            int textW = Math.Max(1, bounds.Width - padX - Px(4, scale));

            int localX = bounds.X - hudOrigin.X;
            int localY = bounds.Y - hudOrigin.Y;
            GraphicsState widgetState = g.Save();
            g.SetClip(new Rectangle(localX, localY, bounds.Width, bounds.Height), CombineMode.Intersect);

            SmoothingMode oldSmooth = g.SmoothingMode;
            TextRenderingHint oldHint = g.TextRenderingHint;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
            try
            {
                float y = localY;
                float globalA = Math.Max(0f, Math.Min(1f, _globalAlpha));
                for (int i = _visibleStart; i < _lines.Count; i++)
                {
                    MessageLine line = _lines[i];
                    int lh = line.HeightPx + padY * 2;

                    float lineAlpha = 1f;
                    if (line.Age < FadeInMs)
                        lineAlpha = (float)line.Age / FadeInMs;
                    float a = lineAlpha * globalA;
                    if (a <= 0f) { y += lh + lineGap; continue; }

                    // 日志行底：左侧细银轨 + 向右渐隐的半透明炭黑底（ADR D6）。
                    int backW = Math.Min(bounds.Width, padX + line.TextWidthPx + Px(18, scale));
                    Rectangle back = new Rectangle(localX, (int)y, Math.Max(1, backW), lh);
                    using (LinearGradientBrush bg = new LinearGradientBrush(
                        new Rectangle(back.X - 1, back.Y, back.Width + 2, back.Height),
                        Color.FromArgb(Clamp(200 * a), 8, 9, 10), Color.FromArgb(0, 8, 9, 10),
                        LinearGradientMode.Horizontal))
                    {
                        bg.Blend = new Blend { Positions = new[] { 0f, 0.72f, 1f }, Factors = new[] { 0f, 0.28f, 1f } };
                        g.FillRectangle(bg, back);
                    }
                    using (SolidBrush rail = new SolidBrush(Color.FromArgb(Clamp(NativeHudTheme.AnchorRimMuted.A * a),
                        NativeHudTheme.AnchorRimMuted)))
                        g.FillRectangle(rail, back.X, back.Y + Px(2, scale), railW, Math.Max(1, back.Height - Px(4, scale)));

                    float textTop = y + padY;
                    // 测量和绘制使用同一份字素换行结果；裁切同时约束阴影/抗锯齿外沿。
                    GraphicsState textState = g.Save();
                    try
                    {
                        g.SetClip(new Rectangle(localX, (int)y, bounds.Width, lh), CombineMode.Intersect);
                        foreach (var run in line.Layout.Runs)
                        {
                            byte aa = (byte)Clamp(255 * a);
                            byte sa = (byte)Clamp(200 * a);
                            float x = localX + padX + run.X, runY = textTop + run.Y;
                            using (SolidBrush shadow = new SolidBrush(Color.FromArgb(sa, 0, 0, 0)))
                                g.DrawString(run.Text, _textFont, shadow, x + shadowOffset, runY + shadowOffset, SegmentFormat);
                            using (SolidBrush brush = new SolidBrush(Color.FromArgb(aa, run.Color.R, run.Color.G, run.Color.B)))
                                g.DrawString(run.Text, _textFont, brush, x, runY, SegmentFormat);
                        }
                    }
                    finally { g.Restore(textState); }

                    y += lh + lineGap;
                }
            }
            finally
            {
                g.SmoothingMode = oldSmooth;
                g.TextRenderingHint = oldHint;
                g.Restore(widgetState);
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

        /// <summary>测试/诊断：当前实际可见的消息行数（受分区高度约束）。</summary>
        internal int VisibleLineCount { get { return _lines.Count == 0 ? 0 : _lines.Count - _visibleStart; } }

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

        private Rectangle ComputeBounds()
        {
            EnsureFont();
            float topBase, bottomBase;
            HudZoneLayout.CurrentFallbackRegion(out topBase, out bottomBase);
            int sx, sTop, sBottom;
            _mapper.FlashToScreen(FlashX, topBase, out sx, out sTop);
            _mapper.FlashToScreen(FlashX, bottomBase, out sx, out sBottom);
            RecomputeMeasuredBoundsIfNeeded(Math.Max(0, sBottom - sTop));
            if (_measuredHeightPx <= 0) return Rectangle.Empty;
            return new Rectangle(sx, sBottom - _measuredHeightPx, _measuredWidthPx, _measuredHeightPx);
        }

        private void EnsureFont()
        {
            float scale = GetViewportScale();
            if (Math.Abs(scale - _lastFontScale) < 0.01f && _textFont != null) return;
            _lastFontScale = scale;
            if (_textFont != null) _textFont.Dispose();
            _textFont = NativeHudFonts.CreateUiFont(ToastFontPxForScale(scale), FontStyle.Regular, GraphicsUnit.Pixel);
            _lastBoundsScale = -1f;
        }

        private void RecomputeMeasuredBoundsIfNeeded(int regionPx)
        {
            float scale = GetViewportScale();
            if (Math.Abs(scale - _lastBoundsScale) < 0.001f && regionPx == _lastRegionPx && _measuredWidthPx > 0) return;
            _lastBoundsScale = scale;
            _lastRegionPx = regionPx;
            int padX = Px(PaddingX, scale);
            int padY = Px(PaddingY, scale);
            int lineGap = Px(LineGapBase, scale);
            int toastW = _mapper.ScaleW(FlashMsgW);
            int textW = Math.Max(1, toastW - padX - Px(4, scale));
            using var measurementBitmap = new Bitmap(1, 1);
            using var measurementGraphics = Graphics.FromImage(measurementBitmap);
            measurementGraphics.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
            for (int i = 0; i < _lines.Count; i++)
            {
                var layout = FlashTextLayout.Measure(measurementGraphics, _textFont, _lines[i].Segments, textW, SegmentFormat);
                _lines[i].Layout = layout;
                _lines[i].HeightPx = layout.Height;
                _lines[i].TextWidthPx = layout.Width;
            }
            // 最新在下：从最新一行向上累加，直到放不下分区高度为止。
            int total = 0;
            int start = _lines.Count;
            for (int i = _lines.Count - 1; i >= 0; i--)
            {
                int lh = _lines[i].HeightPx + padY * 2 + (total > 0 ? lineGap : 0);
                if (total + lh > regionPx) break;
                total += lh;
                start = i;
            }
            _visibleStart = start;
            _measuredWidthPx = toastW;
            _measuredHeightPx = start < _lines.Count ? total : 0;
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

        private static int Clamp(float v)
        {
            return Math.Max(0, Math.Min(255, (int)v));
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
            HudZoneLayout.Changed -= _zoneChanged;
            if (_textFont != null) { _textFont.Dispose(); _textFont = null; }
        }
    }
}
