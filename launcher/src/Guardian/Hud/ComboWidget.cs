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
    /// 替代 web modules/combo.js 的搓招进度可视化（#combo-status）。
    ///
    /// 三态：
    /// - Idle: typed 空 + 无 hints + 不在 hit 倒计时 → 隐藏
    /// - Input: 玩家正在输入序列 → 显示 "已输入 + 各分支剩余 + 招式名"
    /// - Hit: AS2 N 前缀 combo 通知确认招式命中 → 显示完整序列 + 名字，HIT_MS 后回落
    ///
    /// 数据通路：
    /// - IUiDataLegacyConsumer 消费 combo|cmdName|typed|hints 每帧推送（FrameTask 高频流）
    ///   - cmdName 非空 = V8 DFA 命中帧 → 缓存 pendingTyped/pendingName，等 AS2 N 前缀确认
    ///   - cmdName 空 = 输入中或空闲帧 → 更新 typed/hints 显示
    /// - INotchNoticeConsumer 消费 N category="combo" → showHit 触发命中态
    ///   - text 形如 "DFA 波动拳" / "Sync 诛杀步"，DFA=金色路径，Sync=青色路径
    ///   - typed 来源优先级：pendingTyped（V8 缓存且名匹配）→ knownPatterns[name]（hints 历史）→ name
    /// - IUiDataConsumer 消费 "s" 键，s:0 时整体复位（game 未就绪）
    ///
    /// 位置：紧贴 NotchToolbarWidget 下方（viewport 顶部居中），随 letterbox 同源缩放。
    /// width 动态：MeasureString 拿真实像素，min=160 base，max=480 base，超长截断。
    /// </summary>
    public class ComboWidget : INativeHudWidget, IUiDataConsumer, IUiDataLegacyConsumer, INotchNoticeConsumer
    {
        // 设计基准 (1024x576)：Web #combo-status 是 #notch-pill 的兄弟节点，收起态紧贴 pill 下沿。
        private const int INPUT_BAR_H_BASE = 26;
        private const int HIT_BAR_H_BASE = 32;
        private const int NOTCH_PILL_H_BASE = 28;
        private const int COMBO_STATUS_PAD_TOP_BASE = 2;
        private const int BORDER_W_BASE = 1;
        private const int BAR_PADDING_X_BASE = 8;
        private const int HIT_PADDING_X_BASE = 16;
        private const int MIN_BAR_W_BASE = 160;
        private const int MAX_BAR_W_BASE = 480;
        // Web CSS 的 input 态在 150% DPI 下视觉偏松；native 预览态使用更紧凑的 spacing，
        // 保持 typed/remain/name 语义不变，但让候选条更像一个整体。
        private const float FLEX_GAP_BASE = 1f;
        private const float INPUT_JOIN_GAP_BASE = 2f;
        private const float INPUT_JOIN_OVERLAP_BASE = 0f;
        private const float NAME_MARGIN_LEFT_BASE = 0f;
        private const float NAME_PAD_X_BASE = 3f;
        private const float NAME_PAD_Y_BASE = 1f;
        private const float DIVIDER_MARGIN_X_BASE = 3f;
        private const float TYPED_FONT_BASE_PX = 14f;
        private const float REMAIN_FONT_BASE_PX = 13f;
        private const float NAME_FONT_BASE_PX = 10f;
        private const float HIT_FONT_BASE_PX = 16f;
        private const float HIT_TAG_FONT_BASE_PX = 10f;
        private const int HIT_SWEEP_DELAY_MS = 60;
        private const int HIT_SWEEP_MS = 500;
        private const int HIT_CHAR_MS = 700;
        private const int HIT_TAG_DELAY_MS = 300;
        private const int HIT_TAG_FADE_MS = 200;
        private const int HIT_COLLAPSE_DELAY_MS = 700;
        private const int HIT_COLLAPSE_MS = 400;
        private const int LAYOUT_TRACE_LIMIT = 24;
        private const float INPUT_LETTER_SPACING_BASE = 1f;
        private const float HIT_LETTER_SPACING_BASE = 5f;

        private const int HIT_MS = 1200;                 // showHit 持续；与 web combo.js hitTimer=35 帧 ≈ 1.2s 对齐
        private const int PENDING_MAX_AGE_FRAMES = 10;   // V8 命中后等 AS2 确认的最大帧数

        // 显示文本的视觉常量
        private static readonly Color COLOR_TYPED   = Color.FromArgb(255, 215, 0);   // gold
        private static readonly Color COLOR_REMAIN  = Color.FromArgb(150, 128, 208, 255); // dim cyan
        private static readonly Color COLOR_NAME    = Color.FromArgb(128, 255, 255, 255);
        private static readonly Color COLOR_NAME_BG = Color.FromArgb(15, 255, 255, 255);
        private static readonly Color COLOR_DIVIDER = Color.FromArgb(60, 255, 255, 255);
        private static readonly Color COLOR_HIT_DFA = Color.FromArgb(255, 215, 0);
        private static readonly Color COLOR_HIT_SYNC = Color.FromArgb(102, 204, 255);
        private static readonly Color COLOR_BG_INPUT = Color.FromArgb(199, 24, 24, 26);
        private static readonly Color COLOR_BG_HIT   = Color.FromArgb(229, 24, 24, 26);
        private static readonly Color COLOR_BORDER_INPUT = Color.FromArgb(26, 255, 255, 255);
        private static readonly Color COLOR_BORDER_HIT_DFA = Color.FromArgb(140, 255, 215, 0);
        private static readonly Color COLOR_BORDER_HIT_SYNC = Color.FromArgb(140, 102, 204, 255);

        private enum BarMode { Idle, Input, Hit }

        internal class HintEntry
        {
            public string Name;
            public string FullSeq;
            public int Steps;
        }

        internal sealed class InputLayoutProbe
        {
            public int BarWidthBase;
            public float TypedLeftBase = float.NaN;
            public float TypedAdvanceBase = float.NaN;
            public float RemainLeftBase = float.NaN;
            public float RemainAdvanceBase = float.NaN;
            public float NamePillLeftBase = float.NaN;
            public float NamePillWidthBase = float.NaN;
            public float SequenceJoinGapBase = float.NaN;
            public float RemainToNameGapBase = float.NaN;
        }

        internal sealed class InputRenderProbe
        {
            public int Width;
            public int Height;
            public int TypedInkLeft = -1;
            public int TypedInkRight = -1;
            public int RemainInkLeft = -1;
            public int RemainInkRight = -1;
            public int SequenceInkGap
            {
                get
                {
                    if (TypedInkRight < 0 || RemainInkLeft < 0) return int.MaxValue;
                    return RemainInkLeft - TypedInkRight - 1;
                }
            }
        }

        internal sealed class HitLayoutProbe
        {
            public int BarWidthBase;
            public float SeqWidthBase;
            public float NameWidthBase;
            public float SeqToNameGapBase;
        }

        private sealed class VisualTextMetrics
        {
            public float Left;
            public float Top;
            public float Width;
            public float Height;
        }

        private readonly Control _anchor;
        private readonly FlashCoordinateMapper _mapper;

        private volatile bool _gameReady = true; // combo 流通常意味着 game ready；缺 s 键时默认放行

        // 输入态缓存
        private string _typed = "";
        private string _hints = "";
        private List<HintEntry> _parsedHints = new List<HintEntry>();
        private readonly Dictionary<string, string> _knownPatterns = new Dictionary<string, string>(StringComparer.Ordinal);

        // V8 命中缓冲（等 AS2 N 前缀确认）
        private string _pendingTyped = "";
        private string _pendingName = "";
        private int _pendingAge;

        // 命中态
        private string _hitName = "";
        private string _hitTyped = "";
        private bool _hitIsDFA;
        private int _hitRemainingMs;
        private int _hitElapsedMs;

        // 渲染缓存
        private int _measuredWidthBase;       // 设计像素（基准坐标系），ScreenBounds 由其乘 Scale
        private bool _widthDirty = true;
        private bool _boundsMounted;
        private string _lastLayoutTraceKey = "";
        private int _layoutTraceCount;

        public event EventHandler BoundsOrVisibilityChanged;
        public event EventHandler RepaintRequested;
        public event EventHandler AnimationStateChanged;

        public ComboWidget(Control anchor)
        {
            if (anchor == null) throw new ArgumentNullException("anchor");
            _anchor = anchor;
            _mapper = new FlashCoordinateMapper(anchor, 1024f, 576f);
            _anchor.Resize += delegate { FireBounds(); };
        }

        private float Scale { get { return WidgetScaler.GetScale(_mapper); } }
        private int SlotH { get { return WidgetScaler.Px(HIT_BAR_H_BASE, Scale); } }

        private BarMode CurrentMode
        {
            get
            {
                if (!_gameReady) return BarMode.Idle;
                if (_hitRemainingMs > 0) return BarMode.Hit;
                if (_typed.Length > 0 || _parsedHints.Count > 0) return BarMode.Input;
                return BarMode.Idle;
            }
        }

        public bool Visible { get { return _gameReady && _boundsMounted; } }

        public Rectangle ScreenBounds
        {
            get
            {
                if (!Visible) return Rectangle.Empty;
                if (_anchor == null || !_anchor.IsHandleCreated) return Rectangle.Empty;
                try
                {
                    Point origin = _anchor.PointToScreen(Point.Empty);
                    float vpX, vpY, vpW, vpH;
                    _mapper.CalcViewport(out vpX, out vpY, out vpW, out vpH);

                    int wScaled = Math.Min(WidgetScaler.Px(MAX_BAR_W_BASE, Scale), Math.Max(1, (int)vpW));
                    int hScaled = SlotH;
                    int x = origin.X + (int)vpX + Math.Max(0, ((int)vpW - wScaled) / 2);
                    int y = origin.Y + (int)vpY
                          + WidgetScaler.Px(NOTCH_PILL_H_BASE, Scale)
                          + WidgetScaler.Px(COMBO_STATUS_PAD_TOP_BASE, Scale);
                    return new Rectangle(x, y, wScaled, hScaled);
                }
                catch { return Rectangle.Empty; }
            }
        }

        public bool WantsAnimationTick { get { return _hitRemainingMs > 0; } }

        public void Tick(int deltaMs)
        {
            if (_hitRemainingMs <= 0) return;
            bool wasMounted = Visible;
            _hitElapsedMs += Math.Max(1, deltaMs);
            _hitRemainingMs -= deltaMs;
            if (_hitRemainingMs <= 0)
            {
                _hitRemainingMs = 0;
                _hitElapsedMs = 0;
                _hitName = "";
                _hitTyped = "";
                FireAnimationStateChanged();
                FireBoundsIfMountChanged(wasMounted);
                return;
            }
            FireRepaint();
        }

        public void Paint(Graphics g, float dpr, Point hudOrigin)
        {
            BarMode mode = CurrentMode;
            if (mode == BarMode.Idle) return;
            Rectangle r = ScreenBounds;
            if (r.Width <= 0 || r.Height <= 0) return;
            int localX = r.X - hudOrigin.X;
            int localY = r.Y - hudOrigin.Y;

            float scale = Scale;
            if (_widthDirty) RecomputeMeasuredWidthBase();
            float typedFontPx  = WidgetScaler.Pxf(TYPED_FONT_BASE_PX, scale);
            float remainFontPx = WidgetScaler.Pxf(REMAIN_FONT_BASE_PX, scale);
            float nameFontPx   = WidgetScaler.Pxf(NAME_FONT_BASE_PX, scale);
            float hitFontPx    = WidgetScaler.Pxf(HIT_FONT_BASE_PX, scale);
            float hitTagFontPx = WidgetScaler.Pxf(HIT_TAG_FONT_BASE_PX, scale);
            int inputPadX = WidgetScaler.Px(BAR_PADDING_X_BASE, scale);
            int hitPadX = WidgetScaler.Px(HIT_PADDING_X_BASE, scale);
            int borderPx = WidgetScaler.Px(BORDER_W_BASE, scale);

            Color bgColor = mode == BarMode.Hit ? COLOR_BG_HIT : COLOR_BG_INPUT;
            Color borderColor;
            if (mode == BarMode.Hit) borderColor = _hitIsDFA ? COLOR_BORDER_HIT_DFA : COLOR_BORDER_HIT_SYNC;
            else borderColor = COLOR_BORDER_INPUT;

            using (Font typedFont  = new Font("Microsoft YaHei", typedFontPx, FontStyle.Bold, GraphicsUnit.Pixel))
            using (Font remainFont = new Font("Microsoft YaHei", remainFontPx, FontStyle.Regular, GraphicsUnit.Pixel))
            using (Font nameFont   = new Font("Microsoft YaHei", nameFontPx, FontStyle.Regular, GraphicsUnit.Pixel))
            using (Font hitFont    = new Font("Microsoft YaHei", hitFontPx, FontStyle.Bold, GraphicsUnit.Pixel))
            using (Font hitTagFont = new Font("Microsoft YaHei", hitTagFontPx, FontStyle.Regular, GraphicsUnit.Pixel))
            using (StringFormat fmt = new StringFormat { Alignment = StringAlignment.Near, LineAlignment = StringAlignment.Center })
            {
                float contentW = mode == BarMode.Hit
                    ? MeasureHitContentWidth(g, hitFont, hitTagFont, scale)
                    : MeasureInputContentWidth(g, typedFont, remainFont, nameFont, scale);
                int padForMode = mode == BarMode.Hit ? hitPadX : inputPadX;
                int barW = Math.Min(r.Width, Math.Max(1, (int)Math.Ceiling(contentW + padForMode * 2f + borderPx * 2f)));
                int barH = WidgetScaler.Px(mode == BarMode.Hit ? HIT_BAR_H_BASE : INPUT_BAR_H_BASE, scale);
                Rectangle barRect = new Rectangle(localX + Math.Max(0, (r.Width - barW) / 2), localY, barW, Math.Min(r.Height, barH));
                float alpha = 1f;
                if (mode == BarMode.Hit)
                {
                    float collapse = Clamp01((_hitElapsedMs - HIT_COLLAPSE_DELAY_MS) / (float)HIT_COLLAPSE_MS);
                    if (collapse > 0f)
                    {
                        float eased = collapse * collapse;
                        alpha = 1f - eased;
                        int nextH = Math.Max(1, (int)Math.Round(barRect.Height * (1f - 0.9f * eased)));
                        barRect = new Rectangle(barRect.X, barRect.Y + (barRect.Height - nextH) / 2, barRect.Width, nextH);
                    }
                }
                Rectangle contentRect = new Rectangle(
                    barRect.X + borderPx,
                    barRect.Y,
                    Math.Max(1, barRect.Width - borderPx * 2),
                    barRect.Height);
                TraceLayoutIfChanged(mode, scale, r, barRect, contentRect, contentW, padForMode, borderPx);

                DrawBottomRoundedBar(g, barRect, WidgetScaler.Px(mode == BarMode.Hit ? 6 : 5, scale), bgColor, borderColor, alpha);
                GraphicsState clipState = g.Save();
                try
                {
                    g.SetClip(barRect);
                    if (mode == BarMode.Hit)
                    {
                        PaintHitSweep(g, barRect, _hitIsDFA ? COLOR_HIT_DFA : COLOR_HIT_SYNC, alpha);
                        PaintHit(g, contentRect, hitPadX, hitFont, hitTagFont, fmt, scale, alpha);
                    }
                    else if (mode == BarMode.Input) PaintInput(g, contentRect, inputPadX, typedFont, remainFont, nameFont, fmt, scale);
                }
                finally
                {
                    g.Restore(clipState);
                }
            }
        }

        private float MeasureInputContentWidth(Graphics g, Font typedFont, Font remainFont, Font nameFont, float scale)
        {
            float total = 0f;
            bool hasItem = false;
            float flexGap = WidgetScaler.Pxf(FLEX_GAP_BASE, scale);
            float nameMarginLeft = PxfAllowZero(NAME_MARGIN_LEFT_BASE, scale);
            float namePadX = WidgetScaler.Pxf(NAME_PAD_X_BASE, scale);
            float dividerMarginX = WidgetScaler.Pxf(DIVIDER_MARGIN_X_BASE, scale);
            float letterSpacing = WidgetScaler.Pxf(INPUT_LETTER_SPACING_BASE, scale);
            float joinGap = PxfAllowZero(INPUT_JOIN_GAP_BASE, scale);
            float joinOverlap = PxfAllowZero(INPUT_JOIN_OVERLAP_BASE, scale);

            bool joinFirstRemain = HasJoinedFirstRemain();
            AddFlexMeasure(ref total, ref hasItem, flexGap,
                _typed.Length > 0 ? MeasureVisualSpacedString(_typed, typedFont, letterSpacing, !joinFirstRemain).Width : 0f);

            for (int i = 0; i < _parsedHints.Count; i++)
            {
                HintEntry h = _parsedHints[i];
                if (h == null) continue;
                if (i > 0)
                    AddFlexMeasure(ref total, ref hasItem, flexGap,
                        dividerMarginX + MeasureTypographicText(g, "|", remainFont).Width + dividerMarginX);

                string remain = SafeStripPrefix(h.FullSeq, _typed);
                float remainW = remain.Length > 0 ? MeasureVisualSpacedString(remain, remainFont, letterSpacing, true).Width : 0f;
                if (ShouldJoinFirstRemain(i, remain))
                {
                    total += joinGap;
                    total -= Math.Min(joinOverlap, Math.Max(0f, total));
                    total += remainW;
                    hasItem = true;
                }
                else
                {
                    AddFlexMeasure(ref total, ref hasItem, flexGap, remainW);
                }

                if (!string.IsNullOrEmpty(h.Name))
                    AddFlexMeasure(ref total, ref hasItem, flexGap,
                        nameMarginLeft + MeasurePathText(h.Name, nameFont).Width + namePadX * 2f);
            }

            return total;
        }

        private bool HasJoinedFirstRemain()
        {
            if (_typed.Length <= 0 || _parsedHints.Count <= 0) return false;
            HintEntry h = _parsedHints[0];
            if (h == null) return false;
            return SafeStripPrefix(h.FullSeq, _typed).Length > 0;
        }

        private bool ShouldJoinFirstRemain(int hintIndex, string remain)
        {
            return hintIndex == 0 && _typed.Length > 0 && !string.IsNullOrEmpty(remain);
        }

        private float MeasureHitContentWidth(Graphics g, Font hitFont, Font hitTagFont, float scale)
        {
            string seq = _hitTyped ?? "";
            string name = _hitName ?? "";
            float letterSpacing = PxfAllowZero(HIT_LETTER_SPACING_BASE, scale);
            float seqW = MeasureVisualSpacedString(seq, hitFont, letterSpacing, false).Width;
            if (string.IsNullOrEmpty(name)) return seqW;
            return seqW + WidgetScaler.Pxf(6f, scale) + MeasurePathText(name, hitTagFont).Width;
        }

        private static void AddFlexGap(ref float cursorX, ref bool hasItem, float flexGap)
        {
            if (hasItem) cursorX += flexGap;
            else hasItem = true;
        }

        private static void AddFlexMeasure(ref float total, ref bool hasItem, float flexGap, float itemWidth)
        {
            if (hasItem) total += flexGap;
            total += itemWidth;
            hasItem = true;
        }

        private void TraceLayoutIfChanged(BarMode mode, float scale, Rectangle slotRect, Rectangle barRect,
                                          Rectangle contentRect, float contentW, int padX, int borderPx)
        {
            if (_layoutTraceCount >= LAYOUT_TRACE_LIMIT) return;
            string key = mode + "|" + _typed + "|" + _hints + "|" + _hitTyped + "|" + _hitName
                + "|" + slotRect.Width + "x" + slotRect.Height
                + "|" + barRect.Width + "x" + barRect.Height
                + "|" + scale.ToString("0.###", System.Globalization.CultureInfo.InvariantCulture);
            if (string.Equals(key, _lastLayoutTraceKey, StringComparison.Ordinal)) return;
            _lastLayoutTraceKey = key;
            _layoutTraceCount++;

            try
            {
                float vpX, vpY, vpW, vpH;
                _mapper.CalcViewport(out vpX, out vpY, out vpW, out vpH);
                string inputProbe = "";
                if (mode == BarMode.Input)
                {
                    InputLayoutProbe p = InputPreviewProbeForTest();
                    inputProbe = " inputProbe={barWBase="
                        + p.BarWidthBase.ToString(System.Globalization.CultureInfo.InvariantCulture)
                        + ",joinGapBase=" + p.SequenceJoinGapBase.ToString("0.##", System.Globalization.CultureInfo.InvariantCulture)
                        + ",nameGapBase=" + p.RemainToNameGapBase.ToString("0.##", System.Globalization.CultureInfo.InvariantCulture)
                        + "}";
                }
                else if (mode == BarMode.Hit)
                {
                    HitLayoutProbe p = HitPreviewProbeForTest();
                    inputProbe = " hitProbe={barWBase="
                        + p.BarWidthBase.ToString(System.Globalization.CultureInfo.InvariantCulture)
                        + ",seqWBase=" + p.SeqWidthBase.ToString("0.##", System.Globalization.CultureInfo.InvariantCulture)
                        + ",nameWBase=" + p.NameWidthBase.ToString("0.##", System.Globalization.CultureInfo.InvariantCulture)
                        + ",gapBase=" + p.SeqToNameGapBase.ToString("0.##", System.Globalization.CultureInfo.InvariantCulture)
                        + "}";
                }
                LogManager.Log("[ComboWidget] layout mode=" + mode
                    + " scale=" + scale.ToString("0.###", System.Globalization.CultureInfo.InvariantCulture)
                    + " viewport=" + FormatRect(vpX, vpY, vpW, vpH)
                    + " slot=" + slotRect
                    + " bar=" + barRect
                    + " content=" + contentRect
                    + " contentW=" + contentW.ToString("0.##", System.Globalization.CultureInfo.InvariantCulture)
                    + " padX=" + padX
                    + " border=" + borderPx
                    + " typed='" + Trunc(_typed, 24) + "'"
                    + " hints='" + Trunc(_hints, 80) + "'"
                    + " hitTyped='" + Trunc(_hitTyped, 24) + "'"
                    + " hitName='" + Trunc(_hitName, 24) + "'"
                    + inputProbe);
            }
            catch { }
        }

        private static string FormatRect(float x, float y, float w, float h)
        {
            return "{x=" + x.ToString("0.#", System.Globalization.CultureInfo.InvariantCulture)
                + ",y=" + y.ToString("0.#", System.Globalization.CultureInfo.InvariantCulture)
                + ",w=" + w.ToString("0.#", System.Globalization.CultureInfo.InvariantCulture)
                + ",h=" + h.ToString("0.#", System.Globalization.CultureInfo.InvariantCulture) + "}";
        }

        private static string Trunc(string value, int max)
        {
            if (string.IsNullOrEmpty(value)) return "";
            if (value.Length <= max) return value;
            return value.Substring(0, Math.Max(0, max - 1)) + "...";
        }

        private void PaintInput(Graphics g, Rectangle barRect, int padX,
                                Font typedFont, Font remainFont, Font nameFont, StringFormat fmt, float scale)
        {
            // 渲染顺序：typed | (remain name) | divider | (remain name) | ...
            float cursorX = barRect.X + padX;
            float midY = barRect.Y + barRect.Height / 2f;

            using (SolidBrush typedBrush  = new SolidBrush(COLOR_TYPED))
            using (SolidBrush remainBrush = new SolidBrush(COLOR_REMAIN))
            using (SolidBrush nameBrush   = new SolidBrush(COLOR_NAME))
            using (SolidBrush nameBgBrush = new SolidBrush(COLOR_NAME_BG))
            using (SolidBrush dividerBrush = new SolidBrush(COLOR_DIVIDER))
            {
                float flexGap = WidgetScaler.Pxf(FLEX_GAP_BASE, scale);
                float nameMarginLeft = PxfAllowZero(NAME_MARGIN_LEFT_BASE, scale);
                float dividerMarginX = WidgetScaler.Pxf(DIVIDER_MARGIN_X_BASE, scale);
                float letterSpacing = WidgetScaler.Pxf(INPUT_LETTER_SPACING_BASE, scale);
                float joinGap = PxfAllowZero(INPUT_JOIN_GAP_BASE, scale);
                float joinOverlap = PxfAllowZero(INPUT_JOIN_OVERLAP_BASE, scale);
                bool joinFirstRemain = HasJoinedFirstRemain();
                bool hasItem = false;
                AddFlexGap(ref cursorX, ref hasItem, flexGap);
                if (_typed.Length > 0)
                {
                    SizeF s = MeasureVisualSpacedString(_typed, typedFont, letterSpacing, !joinFirstRemain);
                    DrawVisualSpacedString(g, _typed, typedFont, typedBrush, cursorX, midY, letterSpacing, !joinFirstRemain);
                    cursorX += s.Width;
                }

                for (int i = 0; i < _parsedHints.Count; i++)
                {
                    HintEntry h = _parsedHints[i];
                    if (h == null) continue;
                    if (i > 0)
                    {
                        SizeF ds = MeasureTypographicText(g, "|", remainFont);
                        AddFlexGap(ref cursorX, ref hasItem, flexGap);
                        g.DrawString("|", remainFont, dividerBrush, cursorX + dividerMarginX, midY - ds.Height / 2f, fmt);
                        cursorX += dividerMarginX + ds.Width + dividerMarginX;
                    }
                    string remain = SafeStripPrefix(h.FullSeq, _typed);
                    bool joinedRemain = ShouldJoinFirstRemain(i, remain);
                    if (!joinedRemain) AddFlexGap(ref cursorX, ref hasItem, flexGap);
                    else
                    {
                        cursorX += joinGap;
                        cursorX -= joinOverlap;
                        hasItem = true;
                    }
                    if (remain.Length > 0)
                    {
                        SizeF rs = MeasureVisualSpacedString(remain, remainFont, letterSpacing, true);
                        DrawVisualSpacedString(g, remain, remainFont, remainBrush, cursorX, midY, letterSpacing, true);
                        cursorX += rs.Width;
                    }
                    if (!string.IsNullOrEmpty(h.Name))
                    {
                        VisualTextMetrics ns = MeasurePathText(h.Name, nameFont);
                        float pillPadX = WidgetScaler.Pxf(NAME_PAD_X_BASE, scale);
                        float pillPadY = WidgetScaler.Pxf(NAME_PAD_Y_BASE, scale);
                        AddFlexGap(ref cursorX, ref hasItem, flexGap);
                        RectangleF pill = new RectangleF(cursorX + nameMarginLeft,
                            midY - (ns.Height + pillPadY * 2f) / 2f,
                            ns.Width + pillPadX * 2f,
                            ns.Height + pillPadY * 2f);
                        FillRoundedRect(g, pill, WidgetScaler.Pxf(2f, scale), nameBgBrush);
                        DrawPathText(g, h.Name, nameFont, nameBrush, pill.X + pillPadX, midY);
                        cursorX += nameMarginLeft + pill.Width;
                    }
                    if (cursorX > barRect.Right - padX) break; // 超宽截断（设计宽度上限是 480 base）
                }
            }
        }

        private void PaintHit(Graphics g, Rectangle barRect, int padX,
                              Font hitFont, Font hitTagFont, StringFormat fmt, float scale, float alpha)
        {
            PaintHitAnimated(g, barRect, hitFont, hitTagFont, fmt, scale, alpha);
        }

        public bool TryHitTest(Point screenPt) { return false; } // 不可点击
        private void PaintHitAnimated(Graphics g, Rectangle barRect, Font hitFont, Font hitTagFont,
                                      StringFormat fmt, float scale, float alpha)
        {
            Color seqColor = _hitIsDFA ? COLOR_HIT_DFA : COLOR_HIT_SYNC;
            string seq = _hitTyped ?? "";
            string name = _hitName ?? "";
            float letterSpacing = PxfAllowZero(HIT_LETTER_SPACING_BASE, scale);
            SizeF seqSize = MeasureVisualSpacedString(seq, hitFont, letterSpacing, false);
            VisualTextMetrics tagSize = string.IsNullOrEmpty(name) ? null : MeasurePathText(name, hitTagFont);
            float gap = string.IsNullOrEmpty(name) ? 0f : WidgetScaler.Pxf(6f, scale);
            float total = seqSize.Width + gap + (tagSize == null ? 0f : tagSize.Width);
            float startX = barRect.X + (barRect.Width - total) / 2f;
            float midY = barRect.Y + barRect.Height / 2f;
            float x = startX;

            for (int i = 0; i < seq.Length; i++)
            {
                string ch = seq.Substring(i, 1);
                VisualTextMetrics chSize = MeasurePathText(ch, hitFont);
                int delay = 50 + i * 25;
                float p = Clamp01((_hitElapsedMs - delay) / (float)HIT_CHAR_MS);
                if (p > 0f)
                {
                    float charAlpha = alpha * (p < 0.3f ? p / 0.3f : 1f);
                    float mid = seq.Length / 2f;
                    float offset = (float)Math.Round((i - mid) * -3f) * scale * EaseOutCubic(p);
                    using (SolidBrush charBrush = new SolidBrush(WithAlpha(seqColor, charAlpha)))
                        DrawPathText(g, ch, hitFont, charBrush, x + offset, midY);
                }
                x += chSize.Width + letterSpacing;
            }

            if (!string.IsNullOrEmpty(name))
            {
                float tagAlpha = alpha * Clamp01((_hitElapsedMs - HIT_TAG_DELAY_MS) / (float)HIT_TAG_FADE_MS) * 0.45f;
                using (SolidBrush tagBrush = new SolidBrush(WithAlpha(Color.White, tagAlpha)))
                {
                    DrawPathText(g, name, hitTagFont, tagBrush, startX + seqSize.Width + gap, midY);
                }
            }
        }

        private void PaintHitSweep(Graphics g, Rectangle barRect, Color accent, float alpha)
        {
            float t = Clamp01((_hitElapsedMs - HIT_SWEEP_DELAY_MS) / (float)HIT_SWEEP_MS);
            if (t <= 0f || t >= 1f || alpha <= 0f) return;
            Rectangle sweep = new Rectangle(
                barRect.X - barRect.Width + (int)Math.Round(barRect.Width * 2f * t),
                barRect.Y,
                barRect.Width,
                barRect.Height);
            using (LinearGradientBrush brush = new LinearGradientBrush(sweep, Color.Transparent, Color.Transparent, LinearGradientMode.Horizontal))
            {
                ColorBlend blend = new ColorBlend();
                blend.Positions = new[] { 0f, 0.35f, 0.5f, 0.65f, 1f };
                blend.Colors = new[]
                {
                    Color.Transparent,
                    WithAlpha(accent, 0.12f * alpha),
                    WithAlpha(accent, 0.35f * alpha),
                    WithAlpha(accent, 0.12f * alpha),
                    Color.Transparent
                };
                brush.InterpolationColors = blend;
                g.FillRectangle(brush, sweep);
            }
        }

        private static void DrawBottomRoundedBar(Graphics g, Rectangle r, int radius, Color bg, Color border, float alpha)
        {
            using (GraphicsPath path = CreateBottomRoundedPath(r, radius))
            using (SolidBrush bgBrush = new SolidBrush(WithAlpha(bg, alpha)))
            using (Pen borderPen = new Pen(WithAlpha(border, alpha)))
            {
                g.FillPath(bgBrush, path);
                g.DrawPath(borderPen, path);
            }
        }

        private static GraphicsPath CreateBottomRoundedPath(Rectangle r, int radius)
        {
            GraphicsPath path = new GraphicsPath();
            int rr = Math.Max(0, Math.Min(radius, Math.Min(r.Width, r.Height) / 2));
            if (rr <= 0)
            {
                path.AddRectangle(r);
                return path;
            }
            int d = rr * 2;
            path.StartFigure();
            path.AddLine(r.Left, r.Top, r.Right, r.Top);
            path.AddLine(r.Right, r.Top, r.Right, r.Bottom - rr);
            path.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
            path.AddLine(r.Right - rr, r.Bottom, r.Left + rr, r.Bottom);
            path.AddArc(r.Left, r.Bottom - d, d, d, 90, 90);
            path.AddLine(r.Left, r.Bottom - rr, r.Left, r.Top);
            path.CloseFigure();
            return path;
        }

        private static void FillRoundedRect(Graphics g, RectangleF r, float radius, Brush brush)
        {
            float rr = Math.Max(0f, Math.Min(radius, Math.Min(r.Width, r.Height) / 2f));
            if (rr <= 0f)
            {
                g.FillRectangle(brush, r);
                return;
            }
            float d = rr * 2f;
            using (GraphicsPath path = new GraphicsPath())
            {
                path.AddArc(r.Left, r.Top, d, d, 180, 90);
                path.AddArc(r.Right - d, r.Top, d, d, 270, 90);
                path.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
                path.AddArc(r.Left, r.Bottom - d, d, d, 90, 90);
                path.CloseFigure();
                g.FillPath(brush, path);
            }
        }

        private static VisualTextMetrics MeasurePathText(string text, Font font)
        {
            VisualTextMetrics result = new VisualTextMetrics();
            if (string.IsNullOrEmpty(text)) return result;

            using (StringFormat typographic = CreateTypographicFormat())
            using (GraphicsPath path = new GraphicsPath())
            {
                path.AddString(text, font.FontFamily, (int)font.Style, font.Size, PointF.Empty, typographic);
                RectangleF bounds = path.GetBounds();
                result.Left = bounds.Left;
                result.Top = bounds.Top;
                result.Width = bounds.Width;
                result.Height = bounds.Height;
            }
            return result;
        }

        private static SizeF MeasureVisualSpacedString(string text, Font font, float spacing, bool includeTrailingSpacing)
        {
            if (string.IsNullOrEmpty(text)) return SizeF.Empty;
            float w = 0f;
            float h = 0f;
            for (int i = 0; i < text.Length; i++)
            {
                VisualTextMetrics m = MeasurePathText(text.Substring(i, 1), font);
                w += m.Width;
                if (includeTrailingSpacing || i < text.Length - 1) w += spacing;
                if (m.Height > h) h = m.Height;
            }
            return new SizeF(w, h);
        }

        private static void DrawPathText(Graphics g, string text, Font font, Brush brush, float visualLeft, float centerY)
        {
            if (string.IsNullOrEmpty(text)) return;
            using (StringFormat typographic = CreateTypographicFormat())
            using (GraphicsPath path = new GraphicsPath())
            {
                path.AddString(text, font.FontFamily, (int)font.Style, font.Size, PointF.Empty, typographic);
                RectangleF bounds = path.GetBounds();
                using (Matrix m = new Matrix())
                {
                    m.Translate(visualLeft - bounds.Left, centerY - (bounds.Top + bounds.Height / 2f));
                    path.Transform(m);
                }
                g.FillPath(brush, path);
            }
        }

        private static void DrawVisualSpacedString(Graphics g, string text, Font font, Brush brush,
                                                   float x, float centerY, float spacing, bool includeTrailingSpacing)
        {
            if (string.IsNullOrEmpty(text)) return;
            for (int i = 0; i < text.Length; i++)
            {
                string ch = text.Substring(i, 1);
                VisualTextMetrics m = MeasurePathText(ch, font);
                DrawPathText(g, ch, font, brush, x, centerY);
                x += m.Width;
                if (includeTrailingSpacing || i < text.Length - 1) x += spacing;
            }
        }

        private static SizeF MeasureSpacedString(Graphics g, string text, Font font, float spacing, StringFormat fmt)
        {
            return MeasureSpacedString(g, text, font, spacing, fmt, true);
        }

        private static SizeF MeasureSpacedString(Graphics g, string text, Font font, float spacing, StringFormat fmt, bool includeTrailingSpacing)
        {
            if (string.IsNullOrEmpty(text)) return SizeF.Empty;
            float w = 0f;
            float h = 0f;
            using (StringFormat typographic = CreateTypographicFormat())
            {
                for (int i = 0; i < text.Length; i++)
                {
                    SizeF s = g.MeasureString(text.Substring(i, 1), font, PointF.Empty, typographic);
                    w += s.Width;
                    if (includeTrailingSpacing || i < text.Length - 1) w += spacing;
                    if (s.Height > h) h = s.Height;
                }
            }
            return new SizeF(w, h);
        }

        private static float PxfAllowZero(float basePx, float scale)
        {
            if (basePx <= 0f) return 0f;
            return WidgetScaler.Pxf(basePx, scale);
        }

        private static SizeF MeasureTypographicText(Graphics g, string text, Font font)
        {
            if (string.IsNullOrEmpty(text)) return SizeF.Empty;
            using (StringFormat typographic = CreateTypographicFormat())
            {
                return g.MeasureString(text, font, PointF.Empty, typographic);
            }
        }

        private static void DrawSpacedString(Graphics g, string text, Font font, Brush brush, float x, float y, float spacing, StringFormat fmt)
        {
            if (string.IsNullOrEmpty(text)) return;
            using (StringFormat typographic = CreateTypographicFormat())
            {
                for (int i = 0; i < text.Length; i++)
                {
                    string ch = text.Substring(i, 1);
                    SizeF s = g.MeasureString(ch, font, PointF.Empty, typographic);
                    g.DrawString(ch, font, brush, x, y, typographic);
                    x += s.Width + spacing;
                }
            }
        }

        private static void DrawScaledText(Graphics g, string text, Font font, Color color, float alpha, float x, float y, float scale, StringFormat fmt)
        {
            if (alpha <= 0f) return;
            GraphicsState state = g.Save();
            try
            {
                g.TranslateTransform(x, y);
                g.ScaleTransform(scale, scale);
                using (SolidBrush brush = new SolidBrush(WithAlpha(color, alpha)))
                using (StringFormat typographic = CreateTypographicFormat())
                {
                    g.DrawString(text, font, brush, 0f, 0f, typographic);
                }
            }
            finally
            {
                g.Restore(state);
            }
        }

        private static StringFormat CreateTypographicFormat()
        {
            StringFormat fmt = (StringFormat)StringFormat.GenericTypographic.Clone();
            fmt.FormatFlags = fmt.FormatFlags | StringFormatFlags.MeasureTrailingSpaces;
            fmt.Alignment = StringAlignment.Near;
            fmt.LineAlignment = StringAlignment.Near;
            return fmt;
        }

        private static Color WithAlpha(Color color, float alpha)
        {
            int a = (int)Math.Round(color.A * Clamp01(alpha));
            return Color.FromArgb(a, color.R, color.G, color.B);
        }

        private static float Clamp01(float v)
        {
            if (v < 0f) return 0f;
            if (v > 1f) return 1f;
            return v;
        }

        private static float EaseOutCubic(float v)
        {
            v = Clamp01(v);
            float inv = 1f - v;
            return 1f - inv * inv * inv;
        }

        public void OnMouseEvent(MouseEventArgs e, MouseEventKind kind) { }

        // ── IUiDataConsumer (snapshot KV) ──
        public void OnUiDataChanged(IReadOnlyDictionary<string, string> snapshot, ISet<string> changedKeys)
        {
            string piece;
            if (changedKeys.Contains("s") && snapshot.TryGetValue("s", out piece))
            {
                bool ready = TopRightToolsWidget.ParseUiBoolValue(piece);
                if (ready != _gameReady)
                {
                    bool wasMounted = Visible;
                    _gameReady = ready;
                    if (!ready) ResetAllState();
                    FireBoundsIfMountChanged(wasMounted);
                }
            }
        }

        // ── IUiDataLegacyConsumer (combo|cmdName|typed|hints) ──
        private static readonly string[] LEGACY_TYPES = { "combo" };
        public IEnumerable<string> LegacyTypes { get { return LEGACY_TYPES; } }

        public void OnLegacyUiData(string type, string[] fields)
        {
            if (!string.Equals(type, "combo", StringComparison.Ordinal)) return;
            string cmdName = (fields != null && fields.Length > 0) ? (fields[0] ?? "") : "";
            string typed   = (fields != null && fields.Length > 1) ? (fields[1] ?? "") : "";
            string hints   = (fields != null && fields.Length > 2) ? (fields[2] ?? "") : "";
            ApplyComboLegacy(cmdName, typed, hints);
        }

        // ── INotchNoticeConsumer (N combo|color|"DFA 招式名" / "Sync 招式名") ──
        private static readonly string[] NOTICE_CATEGORIES = { "combo" };
        public IEnumerable<string> NoticeCategories { get { return NOTICE_CATEGORIES; } }

        public void OnNotchNotice(string category, string text, Color accentColor)
        {
            if (!string.Equals(category, "combo", StringComparison.Ordinal)) return;
            string raw = text ?? "";
            bool isDFA = raw.StartsWith("DFA", StringComparison.Ordinal);
            // 与 web combo.js 一致：剥离 "DFA " / "Sync " 前缀（含可选空格）
            string name = StripPathPrefix(raw);
            string typed = ResolveHitTyped(name);
            ShowHit(name, typed, isDFA);
        }

        // ── 内部状态机 ──
        private void ApplyComboLegacy(string cmdName, string typed, string hints)
        {
            // pendingTyped 老化
            if (_pendingTyped.Length > 0)
            {
                _pendingAge++;
                if (_pendingAge > PENDING_MAX_AGE_FRAMES)
                {
                    _pendingTyped = "";
                    _pendingName = "";
                    _pendingAge = 0;
                }
            }

            // V8 DFA 命中帧：缓存 typed + 招式名，等 AS2 N 前缀确认
            if (cmdName.Length > 0)
            {
                _pendingTyped = typed ?? "";
                _pendingName = cmdName;
                _pendingAge = 0;
                return; // 不更新 input 显示，避免抢在确认前闪烁
            }

            // hit 持续期间不响应 input 帧（与 web combo.js lastState=='hit' 跳过同语义）
            if (_hitRemainingMs > 0) return;

            // 无输入：回落 Idle
            if (string.IsNullOrEmpty(typed) && string.IsNullOrEmpty(hints))
            {
                if (_typed.Length > 0 || _parsedHints.Count > 0)
                {
                    bool wasMounted = Visible;
                    _typed = "";
                    _hints = "";
                    _parsedHints.Clear();
                    _widthDirty = true;
                    FireBoundsIfMountChanged(wasMounted);
                }
                return;
            }

            // 输入中：解析 hints 并积累 knownPatterns
            if (typed != _typed || hints != _hints)
            {
                bool wasMounted = Visible;
                _typed = typed ?? "";
                _hints = hints ?? "";
                _parsedHints = ParseHints(_hints);
                for (int i = 0; i < _parsedHints.Count; i++)
                {
                    HintEntry h = _parsedHints[i];
                    if (h != null && !string.IsNullOrEmpty(h.Name) && !string.IsNullOrEmpty(h.FullSeq))
                        _knownPatterns[h.Name] = h.FullSeq;
                }
                _widthDirty = true;
                MountBoundsIfActive();
                FireBoundsIfMountChanged(wasMounted);
            }
        }

        private void ShowHit(string name, string typed, bool isDFA)
        {
            bool wasMounted = Visible;
            _hitName = name ?? "";
            _hitTyped = typed ?? "";
            _hitIsDFA = isDFA;
            _hitRemainingMs = HIT_MS;
            _hitElapsedMs = 0;
            _pendingTyped = "";
            _pendingName = "";
            _pendingAge = 0;
            _widthDirty = true;
            MountBoundsIfActive();
            FireAnimationStateChanged();
            FireBoundsIfMountChanged(wasMounted);
        }

        private string ResolveHitTyped(string name)
        {
            if (_pendingTyped.Length > 0 && string.Equals(_pendingName, name, StringComparison.Ordinal))
                return _pendingTyped;
            string seq;
            if (!string.IsNullOrEmpty(name) && _knownPatterns.TryGetValue(name, out seq) && !string.IsNullOrEmpty(seq))
                return seq;
            return name ?? "";
        }

        private void ResetAllState()
        {
            _typed = "";
            _hints = "";
            _parsedHints.Clear();
            _knownPatterns.Clear();
            _pendingTyped = "";
            _pendingName = "";
            _pendingAge = 0;
            bool wasTicking = _hitRemainingMs > 0;
            _hitName = "";
            _hitTyped = "";
            _hitRemainingMs = 0;
            _hitElapsedMs = 0;
            _widthDirty = true;
            _boundsMounted = false;
            if (wasTicking) FireAnimationStateChanged();
        }

        // ── 解析 helper ──
        internal static List<HintEntry> ParseHints(string hintsRaw)
        {
            List<HintEntry> result = new List<HintEntry>();
            if (string.IsNullOrEmpty(hintsRaw)) return result;
            string[] entries = hintsRaw.Split(';');
            for (int i = 0; i < entries.Length; i++)
            {
                string entry = entries[i];
                if (string.IsNullOrEmpty(entry)) continue;
                string[] segs = entry.Split(':');
                if (segs.Length < 3) continue;
                int steps;
                if (!int.TryParse(segs[2], System.Globalization.NumberStyles.Integer,
                                  System.Globalization.CultureInfo.InvariantCulture, out steps)) steps = 0;
                HintEntry h = new HintEntry();
                h.Name = segs[0];
                h.FullSeq = segs[1];
                h.Steps = steps;
                result.Add(h);
            }
            return result;
        }

        internal static string SafeStripPrefix(string fullSeq, string typed)
        {
            if (string.IsNullOrEmpty(fullSeq)) return "";
            if (string.IsNullOrEmpty(typed)) return fullSeq;
            if (fullSeq.Length <= typed.Length) return "";
            return fullSeq.Substring(typed.Length);
        }

        internal static string StripPathPrefix(string raw)
        {
            if (string.IsNullOrEmpty(raw)) return "";
            // 去除前缀 "DFA " 或 "Sync "（容许零或多个空格）。
            string s = raw;
            if (s.StartsWith("DFA", StringComparison.Ordinal)) s = s.Substring(3);
            else if (s.StartsWith("Sync", StringComparison.Ordinal)) s = s.Substring(4);
            else return raw;
            return s.TrimStart(' ', '\t');
        }

        private static int Clamp(int v, int lo, int hi)
        {
            if (v < lo) return lo;
            if (v > hi) return hi;
            return v;
        }

        private void RecomputeMeasuredWidthBase()
        {
            _widthDirty = false;
            // 估算用一次性临时 Bitmap+Graphics（仅在文本变化时调用，频率低）
            try
            {
                using (Bitmap b = new Bitmap(1, 1))
                using (Graphics g = Graphics.FromImage(b))
                using (Font typedFont  = new Font("Microsoft YaHei", TYPED_FONT_BASE_PX, FontStyle.Bold, GraphicsUnit.Pixel))
                using (Font remainFont = new Font("Microsoft YaHei", REMAIN_FONT_BASE_PX, FontStyle.Regular, GraphicsUnit.Pixel))
                using (Font nameFont   = new Font("Microsoft YaHei", NAME_FONT_BASE_PX, FontStyle.Regular, GraphicsUnit.Pixel))
                using (Font hitFont    = new Font("Microsoft YaHei", HIT_FONT_BASE_PX, FontStyle.Bold, GraphicsUnit.Pixel))
                using (Font hitTagFont = new Font("Microsoft YaHei", HIT_TAG_FONT_BASE_PX, FontStyle.Regular, GraphicsUnit.Pixel))
                {
                    float w = 0f;
                    BarMode mode = CurrentMode;
                    if (mode == BarMode.Hit)
                    {
                        w = MeasureHitContentWidth(g, hitFont, hitTagFont, 1f);
                    }
                    else if (mode == BarMode.Input)
                    {
                        w = MeasureInputContentWidth(g, typedFont, remainFont, nameFont, 1f);
                    }
                    // 上面用基准字体测量（base px），结果直接落在设计坐标系，无需再除 Scale。
                    // ScreenBounds 取 _measuredWidthBase 后乘 Scale 得到实际像素；保持 base→scaled 单向转换。
                    int padX = mode == BarMode.Hit ? HIT_PADDING_X_BASE : BAR_PADDING_X_BASE;
                    _measuredWidthBase = (int)Math.Ceiling(w) + padX * 2 + BORDER_W_BASE * 2;
                }
            }
            catch
            {
                _measuredWidthBase = MIN_BAR_W_BASE;
            }
        }

        // ── 测试钩子（InternalsVisibleTo("Launcher.Tests")） ──
        internal void ForceGameReady(bool ready) { _gameReady = ready; }
        internal string TypedSnapshot { get { return _typed; } }
        internal string HintsRawSnapshot { get { return _hints; } }
        internal int ParsedHintCount { get { return _parsedHints.Count; } }
        internal string PendingTyped { get { return _pendingTyped; } }
        internal string PendingName { get { return _pendingName; } }
        internal int PendingAge { get { return _pendingAge; } }
        internal bool IsHitState { get { return _hitRemainingMs > 0; } }
        internal int HitRemainingMs { get { return _hitRemainingMs; } }
        internal string HitName { get { return _hitName; } }
        internal string HitTyped { get { return _hitTyped; } }
        internal bool HitIsDFA { get { return _hitIsDFA; } }
        internal void AdvanceHitMs(int ms) { Tick(ms); }
        internal bool TryGetKnownPattern(string name, out string seq) { return _knownPatterns.TryGetValue(name, out seq); }
        internal BarModeForTest TestMode { get { return (BarModeForTest)CurrentMode; } }
        internal bool VisualVisibleForTest { get { return CurrentMode != BarMode.Idle; } }
        internal int PaintWidthBaseForTest()
        {
            RecomputeMeasuredWidthBase();
            return Clamp(_measuredWidthBase, 1, MAX_BAR_W_BASE);
        }
        internal InputLayoutProbe InputPreviewProbeForTest()
        {
            InputLayoutProbe probe = new InputLayoutProbe();
            probe.BarWidthBase = PaintWidthBaseForTest();

            try
            {
                using (Bitmap b = new Bitmap(1, 1))
                using (Graphics g = Graphics.FromImage(b))
                using (Font typedFont = new Font("Microsoft YaHei", TYPED_FONT_BASE_PX, FontStyle.Bold, GraphicsUnit.Pixel))
                using (Font remainFont = new Font("Microsoft YaHei", REMAIN_FONT_BASE_PX, FontStyle.Regular, GraphicsUnit.Pixel))
                using (Font nameFont = new Font("Microsoft YaHei", NAME_FONT_BASE_PX, FontStyle.Regular, GraphicsUnit.Pixel))
                {
                    float scale = 1f;
                    float flexGap = WidgetScaler.Pxf(FLEX_GAP_BASE, scale);
                    float nameMarginLeft = PxfAllowZero(NAME_MARGIN_LEFT_BASE, scale);
                    float namePadX = WidgetScaler.Pxf(NAME_PAD_X_BASE, scale);
                    float dividerMarginX = WidgetScaler.Pxf(DIVIDER_MARGIN_X_BASE, scale);
                    float letterSpacing = WidgetScaler.Pxf(INPUT_LETTER_SPACING_BASE, scale);
                    float joinGap = PxfAllowZero(INPUT_JOIN_GAP_BASE, scale);
                    float joinOverlap = PxfAllowZero(INPUT_JOIN_OVERLAP_BASE, scale);
                    bool joinFirstRemain = HasJoinedFirstRemain();
                    bool hasItem = false;
                    float cursorX = BORDER_W_BASE + BAR_PADDING_X_BASE;

                    AddFlexGap(ref cursorX, ref hasItem, flexGap);
                    if (_typed.Length > 0)
                    {
                        SizeF typed = MeasureVisualSpacedString(_typed, typedFont, letterSpacing, !joinFirstRemain);
                        probe.TypedLeftBase = cursorX;
                        probe.TypedAdvanceBase = typed.Width;
                        cursorX += typed.Width;
                    }

                    for (int i = 0; i < _parsedHints.Count; i++)
                    {
                        HintEntry h = _parsedHints[i];
                        if (h == null) continue;

                        if (i > 0)
                        {
                            SizeF ds = MeasureTypographicText(g, "|", remainFont);
                            AddFlexGap(ref cursorX, ref hasItem, flexGap);
                            cursorX += dividerMarginX + ds.Width + dividerMarginX;
                        }

                        string remain = SafeStripPrefix(h.FullSeq, _typed);
                        bool joinedRemain = ShouldJoinFirstRemain(i, remain);
                        if (!joinedRemain) AddFlexGap(ref cursorX, ref hasItem, flexGap);
                        else
                        {
                            cursorX += joinGap;
                            cursorX -= joinOverlap;
                            hasItem = true;
                        }

                        if (remain.Length > 0)
                        {
                            SizeF rs = MeasureVisualSpacedString(remain, remainFont, letterSpacing, true);
                            if (float.IsNaN(probe.RemainLeftBase))
                            {
                                probe.RemainLeftBase = cursorX;
                                probe.RemainAdvanceBase = rs.Width;
                                if (joinedRemain && !float.IsNaN(probe.TypedLeftBase) && !float.IsNaN(probe.TypedAdvanceBase))
                                    probe.SequenceJoinGapBase = probe.RemainLeftBase - (probe.TypedLeftBase + probe.TypedAdvanceBase);
                            }
                            cursorX += rs.Width;
                        }

                        if (!string.IsNullOrEmpty(h.Name))
                        {
                            VisualTextMetrics ns = MeasurePathText(h.Name, nameFont);
                            float pillW = ns.Width + namePadX * 2f;
                            AddFlexGap(ref cursorX, ref hasItem, flexGap);
                            float pillLeft = cursorX + nameMarginLeft;
                            if (float.IsNaN(probe.NamePillLeftBase))
                            {
                                probe.NamePillLeftBase = pillLeft;
                                probe.NamePillWidthBase = pillW;
                                if (!float.IsNaN(probe.RemainLeftBase) && !float.IsNaN(probe.RemainAdvanceBase))
                                    probe.RemainToNameGapBase = pillLeft - (probe.RemainLeftBase + probe.RemainAdvanceBase);
                            }
                            cursorX += nameMarginLeft + pillW;
                        }
                    }
                }
            }
            catch { }

            return probe;
        }
        internal InputRenderProbe InputPreviewRenderProbeForTest(float scale)
        {
            InputRenderProbe probe = new InputRenderProbe();

            try
            {
                using (Bitmap measureBitmap = new Bitmap(1, 1))
                using (Graphics measureG = Graphics.FromImage(measureBitmap))
                using (Font typedFont = new Font("Microsoft YaHei", WidgetScaler.Pxf(TYPED_FONT_BASE_PX, scale), FontStyle.Bold, GraphicsUnit.Pixel))
                using (Font remainFont = new Font("Microsoft YaHei", WidgetScaler.Pxf(REMAIN_FONT_BASE_PX, scale), FontStyle.Regular, GraphicsUnit.Pixel))
                using (Font nameFont = new Font("Microsoft YaHei", WidgetScaler.Pxf(NAME_FONT_BASE_PX, scale), FontStyle.Regular, GraphicsUnit.Pixel))
                using (StringFormat fmt = new StringFormat { Alignment = StringAlignment.Near, LineAlignment = StringAlignment.Center })
                {
                    float contentW = MeasureInputContentWidth(measureG, typedFont, remainFont, nameFont, scale);
                    int padX = WidgetScaler.Px(BAR_PADDING_X_BASE, scale);
                    int borderPx = WidgetScaler.Px(BORDER_W_BASE, scale);
                    int barW = Math.Max(1, (int)Math.Ceiling(contentW + padX * 2f + borderPx * 2f));
                    int barH = WidgetScaler.Px(INPUT_BAR_H_BASE, scale);
                    probe.Width = barW;
                    probe.Height = barH;

                    using (Bitmap b = new Bitmap(barW, barH, System.Drawing.Imaging.PixelFormat.Format32bppPArgb))
                    using (Graphics g = Graphics.FromImage(b))
                    {
                        g.Clear(Color.Transparent);
                        g.SmoothingMode = SmoothingMode.AntiAlias;
                        g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
                        Rectangle barRect = new Rectangle(0, 0, barW, barH);
                        Rectangle contentRect = new Rectangle(borderPx, 0, Math.Max(1, barW - borderPx * 2), barH);
                        DrawBottomRoundedBar(g, barRect, WidgetScaler.Px(5, scale), COLOR_BG_INPUT, COLOR_BORDER_INPUT, 1f);
                        PaintInput(g, contentRect, padX, typedFont, remainFont, nameFont, fmt, scale);

                        for (int y = 0; y < b.Height; y++)
                        {
                            for (int x = 0; x < b.Width; x++)
                            {
                                Color c = b.GetPixel(x, y);
                                if (c.A <= 8) continue;
                                if (IsTypedProbePixel(c))
                                {
                                    if (probe.TypedInkLeft < 0 || x < probe.TypedInkLeft) probe.TypedInkLeft = x;
                                    if (x > probe.TypedInkRight) probe.TypedInkRight = x;
                                }
                                else if (IsRemainProbePixel(c))
                                {
                                    if (probe.RemainInkLeft < 0 || x < probe.RemainInkLeft) probe.RemainInkLeft = x;
                                    if (x > probe.RemainInkRight) probe.RemainInkRight = x;
                                }
                            }
                        }
                    }
                }
            }
            catch { }

            return probe;
        }
        internal HitLayoutProbe HitPreviewProbeForTest()
        {
            HitLayoutProbe probe = new HitLayoutProbe();
            probe.BarWidthBase = PaintWidthBaseForTest();

            try
            {
                using (Font hitFont = new Font("Microsoft YaHei", HIT_FONT_BASE_PX, FontStyle.Bold, GraphicsUnit.Pixel))
                using (Font hitTagFont = new Font("Microsoft YaHei", HIT_TAG_FONT_BASE_PX, FontStyle.Regular, GraphicsUnit.Pixel))
                {
                    string seq = _hitTyped ?? "";
                    string name = _hitName ?? "";
                    float letterSpacing = PxfAllowZero(HIT_LETTER_SPACING_BASE, 1f);
                    probe.SeqWidthBase = MeasureVisualSpacedString(seq, hitFont, letterSpacing, false).Width;
                    probe.NameWidthBase = string.IsNullOrEmpty(name) ? 0f : MeasurePathText(name, hitTagFont).Width;
                    probe.SeqToNameGapBase = string.IsNullOrEmpty(name) ? 0f : 6f;
                }
            }
            catch { }

            return probe;
        }

        private static bool IsTypedProbePixel(Color c)
        {
            return c.R >= 180 && c.G >= 130 && c.B <= 90;
        }

        private static bool IsRemainProbePixel(Color c)
        {
            return c.B >= 120 && c.G >= 90 && c.R <= 170 && c.B - c.G >= 12 && c.G - c.R >= 20;
        }
        /// <summary>测试钩子：直接拿 RecomputeMeasuredWidthBase 的结果（设计坐标系，不含 Scale）。</summary>
        internal int MeasureWidthBase()
        {
            RecomputeMeasuredWidthBase();
            return _measuredWidthBase;
        }

        internal enum BarModeForTest { Idle = 0, Input = 1, Hit = 2 }

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
        private void MountBoundsIfActive()
        {
            if (_gameReady && CurrentMode != BarMode.Idle) _boundsMounted = true;
        }
        private void FireBoundsIfMountChanged(bool wasMounted)
        {
            bool mounted = Visible;
            if (wasMounted != mounted) FireBounds();
            else if (mounted) FireRepaint();
        }
        private void FireAnimationStateChanged()
        {
            EventHandler h = AnimationStateChanged;
            if (h != null) h(this, EventArgs.Empty);
        }
    }
}
