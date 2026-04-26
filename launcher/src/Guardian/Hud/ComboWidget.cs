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
        // 设计基准 (1024x576):
        //   notch pill 高 28；NotchToolbarWidget 高 ≈ 26+8=34；本 widget 紧贴其下。
        //   若 NotchToolbar 因 _gameReady=false 不可见，本 widget Visible 依 ComboWidget 自身门控（_gameReady）。
        private const int BAR_H_BASE = 28;
        private const int NOTCH_PILL_H_BASE = 28;
        private const int NOTCH_TOOLBAR_GAP_BASE = 34;   // 与 NotchToolbarWidget 高度一致
        private const int BAR_PADDING_X_BASE = 10;
        private const int MIN_BAR_W_BASE = 160;
        private const int MAX_BAR_W_BASE = 480;
        private const float TYPED_FONT_BASE_PX = 14f;
        private const float REMAIN_FONT_BASE_PX = 13f;
        private const float NAME_FONT_BASE_PX = 10f;
        private const float HIT_FONT_BASE_PX = 16f;
        private const float HIT_TAG_FONT_BASE_PX = 10f;

        private const int HIT_MS = 1200;                 // showHit 持续；与 web combo.js hitTimer=35 帧 ≈ 1.2s 对齐
        private const int PENDING_MAX_AGE_FRAMES = 10;   // V8 命中后等 AS2 确认的最大帧数

        // 显示文本的视觉常量
        private static readonly Color COLOR_TYPED   = Color.FromArgb(255, 215, 0);   // gold
        private static readonly Color COLOR_REMAIN  = Color.FromArgb(150, 128, 208, 255); // dim cyan
        private static readonly Color COLOR_NAME    = Color.FromArgb(180, 255, 255, 255);
        private static readonly Color COLOR_DIVIDER = Color.FromArgb(60, 255, 255, 255);
        private static readonly Color COLOR_HIT_DFA = Color.FromArgb(255, 215, 0);
        private static readonly Color COLOR_HIT_SYNC = Color.FromArgb(102, 204, 255);
        private static readonly Color COLOR_BG_INPUT = Color.FromArgb(229, 24, 24, 26);
        private static readonly Color COLOR_BG_HIT   = Color.FromArgb(229, 24, 24, 26);
        private static readonly Color COLOR_BORDER_INPUT = Color.FromArgb(64, 255, 255, 255);
        private static readonly Color COLOR_BORDER_HIT_DFA = Color.FromArgb(140, 255, 215, 0);
        private static readonly Color COLOR_BORDER_HIT_SYNC = Color.FromArgb(140, 102, 204, 255);

        private enum BarMode { Idle, Input, Hit }

        internal class HintEntry
        {
            public string Name;
            public string FullSeq;
            public int Steps;
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

        // 渲染缓存
        private int _measuredWidthBase;       // 设计像素（基准坐标系），ScreenBounds 由其乘 Scale
        private bool _widthDirty = true;

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
        private int BarH { get { return WidgetScaler.Px(BAR_H_BASE, Scale); } }

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

        public bool Visible { get { return CurrentMode != BarMode.Idle; } }

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

                    if (_widthDirty) RecomputeMeasuredWidthBase();
                    int wScaled = WidgetScaler.Px(Clamp(_measuredWidthBase, MIN_BAR_W_BASE, MAX_BAR_W_BASE), Scale);
                    int hScaled = BarH;
                    int x = origin.X + (int)vpX + Math.Max(0, ((int)vpW - wScaled) / 2);
                    int y = origin.Y + (int)vpY
                          + WidgetScaler.Px(NOTCH_PILL_H_BASE, Scale)
                          + WidgetScaler.Px(NOTCH_TOOLBAR_GAP_BASE, Scale);
                    return new Rectangle(x, y, wScaled, hScaled);
                }
                catch { return Rectangle.Empty; }
            }
        }

        public bool WantsAnimationTick { get { return _hitRemainingMs > 0; } }

        public void Tick(int deltaMs)
        {
            if (_hitRemainingMs <= 0) return;
            _hitRemainingMs -= deltaMs;
            if (_hitRemainingMs <= 0)
            {
                _hitRemainingMs = 0;
                _hitName = "";
                _hitTyped = "";
                FireAnimationStateChanged();
                FireBounds(); // hit 退出 → 可能回落 Input/Idle，bounds 与 visibility 都可能变
            }
            // 注：HIT 期间静态显示，不需要每帧 repaint；NativeHud 的 OnAnimTick 仍会调 RenderToBitmapAndCommit，但成本可控。
        }

        public void Paint(Graphics g, float dpr, Point hudOrigin)
        {
            Rectangle r = ScreenBounds;
            if (r.Width <= 0 || r.Height <= 0) return;
            int localX = r.X - hudOrigin.X;
            int localY = r.Y - hudOrigin.Y;

            BarMode mode = CurrentMode;
            float scale = Scale;
            float typedFontPx  = WidgetScaler.Pxf(TYPED_FONT_BASE_PX, scale);
            float remainFontPx = WidgetScaler.Pxf(REMAIN_FONT_BASE_PX, scale);
            float nameFontPx   = WidgetScaler.Pxf(NAME_FONT_BASE_PX, scale);
            float hitFontPx    = WidgetScaler.Pxf(HIT_FONT_BASE_PX, scale);
            float hitTagFontPx = WidgetScaler.Pxf(HIT_TAG_FONT_BASE_PX, scale);
            int padX = WidgetScaler.Px(BAR_PADDING_X_BASE, scale);

            Color bgColor = mode == BarMode.Hit ? COLOR_BG_HIT : COLOR_BG_INPUT;
            Color borderColor;
            if (mode == BarMode.Hit) borderColor = _hitIsDFA ? COLOR_BORDER_HIT_DFA : COLOR_BORDER_HIT_SYNC;
            else borderColor = COLOR_BORDER_INPUT;

            using (SolidBrush bg = new SolidBrush(bgColor))
            using (Pen border = new Pen(borderColor))
            using (Font typedFont  = new Font("Microsoft YaHei", typedFontPx, FontStyle.Bold, GraphicsUnit.Pixel))
            using (Font remainFont = new Font("Microsoft YaHei", remainFontPx, FontStyle.Regular, GraphicsUnit.Pixel))
            using (Font nameFont   = new Font("Microsoft YaHei", nameFontPx, FontStyle.Regular, GraphicsUnit.Pixel))
            using (Font hitFont    = new Font("Microsoft YaHei", hitFontPx, FontStyle.Bold, GraphicsUnit.Pixel))
            using (Font hitTagFont = new Font("Microsoft YaHei", hitTagFontPx, FontStyle.Regular, GraphicsUnit.Pixel))
            using (StringFormat fmt = new StringFormat { Alignment = StringAlignment.Near, LineAlignment = StringAlignment.Center })
            {
                Rectangle barRect = new Rectangle(localX, localY, r.Width, r.Height);
                g.FillRectangle(bg, barRect);
                g.DrawRectangle(border, barRect.X, barRect.Y, barRect.Width - 1, barRect.Height - 1);

                if (mode == BarMode.Hit) PaintHit(g, barRect, padX, hitFont, hitTagFont, fmt);
                else if (mode == BarMode.Input) PaintInput(g, barRect, padX, typedFont, remainFont, nameFont, fmt);
            }
        }

        private void PaintInput(Graphics g, Rectangle barRect, int padX,
                                Font typedFont, Font remainFont, Font nameFont, StringFormat fmt)
        {
            // 渲染顺序：typed | (remain name) | divider | (remain name) | ...
            float cursorX = barRect.X + padX;
            float midY = barRect.Y + barRect.Height / 2f;

            using (SolidBrush typedBrush  = new SolidBrush(COLOR_TYPED))
            using (SolidBrush remainBrush = new SolidBrush(COLOR_REMAIN))
            using (SolidBrush nameBrush   = new SolidBrush(COLOR_NAME))
            using (SolidBrush dividerBrush = new SolidBrush(COLOR_DIVIDER))
            {
                if (_typed.Length > 0)
                {
                    SizeF s = g.MeasureString(_typed, typedFont, int.MaxValue, fmt);
                    g.DrawString(_typed, typedFont, typedBrush, cursorX, midY - s.Height / 2f, fmt);
                    cursorX += s.Width + 4f;
                }

                for (int i = 0; i < _parsedHints.Count; i++)
                {
                    HintEntry h = _parsedHints[i];
                    if (h == null) continue;
                    if (i > 0)
                    {
                        SizeF ds = g.MeasureString("|", remainFont, int.MaxValue, fmt);
                        g.DrawString("|", remainFont, dividerBrush, cursorX, midY - ds.Height / 2f, fmt);
                        cursorX += ds.Width + 6f;
                    }
                    string remain = SafeStripPrefix(h.FullSeq, _typed);
                    if (remain.Length > 0)
                    {
                        SizeF rs = g.MeasureString(remain, remainFont, int.MaxValue, fmt);
                        g.DrawString(remain, remainFont, remainBrush, cursorX, midY - rs.Height / 2f, fmt);
                        cursorX += rs.Width + 4f;
                    }
                    if (!string.IsNullOrEmpty(h.Name))
                    {
                        SizeF ns = g.MeasureString(h.Name, nameFont, int.MaxValue, fmt);
                        g.DrawString(h.Name, nameFont, nameBrush, cursorX, midY - ns.Height / 2f, fmt);
                        cursorX += ns.Width + 8f;
                    }
                    if (cursorX > barRect.Right - padX) break; // 超宽截断（设计宽度上限是 480 base）
                }
            }
        }

        private void PaintHit(Graphics g, Rectangle barRect, int padX,
                              Font hitFont, Font hitTagFont, StringFormat fmt)
        {
            Color seqColor = _hitIsDFA ? COLOR_HIT_DFA : COLOR_HIT_SYNC;
            string seq = _hitTyped ?? "";
            string name = _hitName ?? "";

            using (SolidBrush seqBrush = new SolidBrush(seqColor))
            using (SolidBrush tagBrush = new SolidBrush(COLOR_NAME))
            {
                // 居中布局：[seq]  [tag]
                SizeF seqSize = g.MeasureString(seq, hitFont, int.MaxValue, fmt);
                SizeF tagSize = string.IsNullOrEmpty(name) ? SizeF.Empty : g.MeasureString(name, hitTagFont, int.MaxValue, fmt);
                float gap = string.IsNullOrEmpty(name) ? 0f : 8f;
                float total = seqSize.Width + gap + tagSize.Width;
                float startX = barRect.X + (barRect.Width - total) / 2f;
                float midY = barRect.Y + barRect.Height / 2f;
                if (seq.Length > 0)
                    g.DrawString(seq, hitFont, seqBrush, startX, midY - seqSize.Height / 2f, fmt);
                if (!string.IsNullOrEmpty(name))
                    g.DrawString(name, hitTagFont, tagBrush,
                                 startX + seqSize.Width + gap,
                                 midY - tagSize.Height / 2f + 1f, fmt);
            }
        }

        public bool TryHitTest(Point screenPt) { return false; } // 不可点击
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
                    _gameReady = ready;
                    if (!ready) ResetAllState();
                    FireBounds();
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
                    _typed = "";
                    _hints = "";
                    _parsedHints.Clear();
                    _widthDirty = true;
                    FireBounds();
                }
                return;
            }

            // 输入中：解析 hints 并积累 knownPatterns
            if (typed != _typed || hints != _hints)
            {
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
                FireBounds();
            }
        }

        private void ShowHit(string name, string typed, bool isDFA)
        {
            _hitName = name ?? "";
            _hitTyped = typed ?? "";
            _hitIsDFA = isDFA;
            bool wasTicking = _hitRemainingMs > 0;
            _hitRemainingMs = HIT_MS;
            _pendingTyped = "";
            _pendingName = "";
            _pendingAge = 0;
            _widthDirty = true;
            if (!wasTicking) FireAnimationStateChanged();
            FireBounds();
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
            _widthDirty = true;
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
                using (StringFormat fmt = new StringFormat())
                {
                    float w = 0f;
                    BarMode mode = CurrentMode;
                    if (mode == BarMode.Hit)
                    {
                        SizeF seqSize = g.MeasureString(_hitTyped ?? "", hitFont, int.MaxValue, fmt);
                        SizeF tagSize = string.IsNullOrEmpty(_hitName) ? SizeF.Empty
                            : g.MeasureString(_hitName, hitTagFont, int.MaxValue, fmt);
                        w = seqSize.Width + (string.IsNullOrEmpty(_hitName) ? 0f : 8f) + tagSize.Width;
                    }
                    else if (mode == BarMode.Input)
                    {
                        if (_typed.Length > 0) w += g.MeasureString(_typed, typedFont, int.MaxValue, fmt).Width + 4f;
                        for (int i = 0; i < _parsedHints.Count; i++)
                        {
                            HintEntry h = _parsedHints[i];
                            if (h == null) continue;
                            if (i > 0) w += g.MeasureString("|", remainFont, int.MaxValue, fmt).Width + 12f;
                            string remain = SafeStripPrefix(h.FullSeq, _typed);
                            if (remain.Length > 0) w += g.MeasureString(remain, remainFont, int.MaxValue, fmt).Width + 4f;
                            if (!string.IsNullOrEmpty(h.Name)) w += g.MeasureString(h.Name, nameFont, int.MaxValue, fmt).Width + 8f;
                        }
                    }
                    _measuredWidthBase = (int)Math.Ceiling(w / Math.Max(0.01f, Scale)) + BAR_PADDING_X_BASE * 2;
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

        internal enum BarModeForTest { Idle = 0, Input = 1, Hit = 2 }

        private void FireBounds()
        {
            EventHandler h = BoundsOrVisibilityChanged;
            if (h != null) h(this, EventArgs.Empty);
        }
        private void FireAnimationStateChanged()
        {
            EventHandler h = AnimationStateChanged;
            if (h != null) h(this, EventArgs.Empty);
        }
    }
}
