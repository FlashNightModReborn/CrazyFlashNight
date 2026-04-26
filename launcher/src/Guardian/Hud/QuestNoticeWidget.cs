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
    /// 替代 web modules/notch.js 的任务通知条（#quest-notice-bar）。
    ///
    /// 三态：
    /// - Idle: 隐藏，不绘制（td=0 且无 flash 队列）
    /// - Flash: 瞬时通知（"新任务: X" 或公告），NOTICE_MS 后退出，回落到 task-done 或 Idle
    /// - TaskDone: 持久 "任务已达成 · ..." 文案，常驻，可点击触发 TASK_DELIVER / TASK_UI
    ///
    /// 数据通路：
    /// - IUiDataConsumer 消费 td/tdh/tdn/mm 持久态
    /// - IUiDataLegacyConsumer 消费 task|name / announce|text 一次性事件入队
    ///
    /// 点击：
    /// - canDeliver（td=1, tdn=1, tdh!="", mm!="3", 非 Flash 中）→ Dispatch("TASK_DELIVER", "{\"hotspotId\":\"...\"}")
    /// - 否则 → Dispatch("TASK_UI")
    ///
    /// 长文本 marquee：text 宽度超过显示区域时启用 GDI+ phase 滚动；非滚动态完全不 enroll tick。
    /// </summary>
    public class QuestNoticeWidget : INativeHudWidget, IUiDataConsumer, IUiDataLegacyConsumer
    {
        // 设计基准（与 web overlay.css 对齐）：
        //   #context-panel: top:32px, right:80px, width:170px (--right-tools-width = 5*34)
        //   #quest-notice-bar.visible: height:32px
        // C# TopRightToolsWidget 用 38×32 / 5 键 → total 190px，QuestNotice 与之等宽贴齐
        private const int BAR_W_BASE = 190;
        private const int BAR_H_BASE = 32;
        private const int BAR_TOP_OFFSET_BASE = 32;     // 紧贴 top-right-tools 下方
        private const int BAR_RIGHT_OFFSET_BASE = 0;    // 与 top-right-tools 同右边缘
        private const int ICON_W_BASE = 28;
        private const int TEXT_PAD_BASE = 8;
        private const int ARROW_W_BASE = 24;
        private const float FONT_BASE_PX = 11f;

        private const int NOTICE_MS = 5000;             // 与 notch.js NOTICE_MS 对齐
        private const int FLASH_FADE_MS = 220;          // 进入/退出过渡（视觉简化）
        private const int MARQUEE_PX_PER_SEC = 60;      // 滚动速度
        private const int MARQUEE_DWELL_MS = 800;       // 起止停顿
        private const string ICON_TASK_DONE = "❗";
        private const string ICON_PLACEHOLDER = "✦";

        private enum BarMode { Idle, Flash, TaskDone }

        private class FlashItem
        {
            public string Text;
            public string Icon;
        }

        private readonly Control _anchor;
        private readonly LauncherCommandRouter _router;
        private readonly FlashCoordinateMapper _mapper;

        private volatile bool _gameReady;
        private volatile bool _taskDone;
        private volatile bool _navigable;
        private string _hotspotId = "";
        private string _mapMode = "0";

        private readonly Queue<FlashItem> _flashQueue = new Queue<FlashItem>();
        private readonly object _flashLock = new object();
        private FlashItem _activeFlash;
        private int _flashElapsedMs;

        // 当前显示文本（含 marquee 状态）
        private string _displayText = "";
        private string _displayIcon = ICON_PLACEHOLDER;
        private float _marqueePhasePx;        // 已滚动距离（>=0）
        private bool _marqueeActive;
        private int _marqueeDwellMs;          // 起始停顿余量
        private bool _hover;

        public event EventHandler BoundsOrVisibilityChanged;
        public event EventHandler RepaintRequested;
        public event EventHandler AnimationStateChanged;

        public QuestNoticeWidget(Control anchor, LauncherCommandRouter router)
        {
            if (anchor == null) throw new ArgumentNullException("anchor");
            if (router == null) throw new ArgumentNullException("router");
            _anchor = anchor;
            _router = router;
            _mapper = new FlashCoordinateMapper(anchor, 1024f, 576f);
            _anchor.Resize += delegate { FireBounds(); };
        }

        private float Scale { get { return WidgetScaler.GetScale(_mapper); } }
        private int BarW { get { return WidgetScaler.Px(BAR_W_BASE, Scale); } }
        private int BarH { get { return WidgetScaler.Px(BAR_H_BASE, Scale); } }

        private BarMode CurrentMode
        {
            get
            {
                if (!_gameReady) return BarMode.Idle;
                if (_activeFlash != null) return BarMode.Flash;
                if (_taskDone) return BarMode.TaskDone;
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
                    int barW = BarW;
                    int barH = BarH;
                    int rightOffset = WidgetScaler.Px(BAR_RIGHT_OFFSET_BASE, Scale);
                    int topOffset = WidgetScaler.Px(BAR_TOP_OFFSET_BASE, Scale);
                    int x = origin.X + (int)vpX + Math.Max(0, (int)vpW - barW - rightOffset);
                    int y = origin.Y + (int)vpY + topOffset;
                    return new Rectangle(x, y, barW, barH);
                }
                catch { return Rectangle.Empty; }
            }
        }

        public bool WantsAnimationTick
        {
            get
            {
                if (!Visible) return false;
                if (_activeFlash != null) return true; // 计时退场
                return _marqueeActive;
            }
        }

        public void Tick(int deltaMs)
        {
            bool changed = false;

            // Flash 计时退场
            if (_activeFlash != null)
            {
                _flashElapsedMs += deltaMs;
                if (_flashElapsedMs >= NOTICE_MS)
                {
                    _activeFlash = null;
                    _flashElapsedMs = 0;
                    PumpFlashOrFallback();
                    changed = true;
                    FireBounds(); // mode 切换可能 hide/show
                }
                else
                {
                    changed = true; // flash 飘动效（icon-flash）的轻微视觉变化
                }
            }

            // marquee 推进
            if (_marqueeActive)
            {
                if (_marqueeDwellMs > 0)
                {
                    _marqueeDwellMs -= deltaMs;
                    if (_marqueeDwellMs < 0) _marqueeDwellMs = 0;
                    changed = true;
                }
                else
                {
                    _marqueePhasePx += MARQUEE_PX_PER_SEC * (deltaMs / 1000f);
                    changed = true;
                }
            }

            if (changed) FireRepaint();
            if (!WantsAnimationTick) FireAnimState();
        }

        public void Paint(Graphics g, float dpr, Point hudOrigin)
        {
            Rectangle r = ScreenBounds;
            if (r.Width <= 0 || r.Height <= 0) return;
            int localX = r.X - hudOrigin.X;
            int localY = r.Y - hudOrigin.Y;

            BarMode mode = CurrentMode;
            float fontPx = WidgetScaler.Pxf(FONT_BASE_PX, Scale);
            int iconW = WidgetScaler.Px(ICON_W_BASE, Scale);
            int textPad = WidgetScaler.Px(TEXT_PAD_BASE, Scale);
            int arrowW = WidgetScaler.Px(ARROW_W_BASE, Scale);
            bool showArrow = mode == BarMode.TaskDone && CanDeliver();

            // 背景：task-done 暖橙；flash 黄；hover 略亮
            Color bgTop, bgBottom;
            if (mode == BarMode.Flash)
            {
                bgTop = Color.FromArgb(235, 60, 44, 20);
                bgBottom = Color.FromArgb(229, 28, 22, 14);
            }
            else if (mode == BarMode.TaskDone)
            {
                bgTop = _hover ? Color.FromArgb(240, 48, 28, 28) : Color.FromArgb(235, 34, 22, 22);
                bgBottom = _hover ? Color.FromArgb(235, 26, 18, 20) : Color.FromArgb(229, 20, 14, 16);
            }
            else
            {
                bgTop = Color.FromArgb(229, 24, 24, 26);
                bgBottom = Color.FromArgb(229, 16, 16, 18);
            }

            using (LinearGradientBrush bg = new LinearGradientBrush(
                new Rectangle(localX, localY, r.Width, r.Height), bgTop, bgBottom, LinearGradientMode.Vertical))
            {
                g.FillRectangle(bg, localX, localY, r.Width, r.Height);
            }

            // icon 槽
            Rectangle iconRect = new Rectangle(localX, localY, iconW, r.Height);
            Color iconColor;
            if (mode == BarMode.TaskDone)
                iconColor = _hover ? Color.FromArgb(255, 255, 200, 80) : Color.FromArgb(255, 255, 175, 50);
            else if (mode == BarMode.Flash)
                iconColor = Color.FromArgb(255, 255, 220, 130);
            else
                iconColor = Color.FromArgb(178, 255, 255, 255);

            using (Pen sep = new Pen(Color.FromArgb(31, 255, 255, 255)))
                g.DrawLine(sep, iconRect.Right, localY + 2, iconRect.Right, localY + r.Height - 3);

            // 文字区
            Rectangle textRect = new Rectangle(
                iconRect.Right + textPad, localY,
                r.Width - iconRect.Width - textPad - (showArrow ? arrowW : 0) - textPad,
                r.Height);
            if (textRect.Width < 1) textRect.Width = 1;

            // 文字 + 可选 marquee
            using (Font font = new Font("Microsoft YaHei", fontPx, FontStyle.Regular, GraphicsUnit.Pixel))
            using (SolidBrush iconBrush = new SolidBrush(iconColor))
            using (StringFormat iconFmt = new StringFormat
            { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center })
            {
                TextRenderingHint prevHint = g.TextRenderingHint;
                g.TextRenderingHint = TextRenderingHint.AntiAlias;
                try
                {
                    g.DrawString(_displayIcon, font, iconBrush, iconRect, iconFmt);

                    Color textColor;
                    if (mode == BarMode.Flash) textColor = Color.FromArgb(229, 255, 220, 150);
                    else if (mode == BarMode.TaskDone) textColor = _hover
                        ? Color.FromArgb(255, 255, 215, 110)
                        : Color.FromArgb(229, 255, 200, 80);
                    else textColor = Color.FromArgb(178, 255, 255, 255);

                    using (SolidBrush textBrush = new SolidBrush(textColor))
                    {
                        SizeF measured = g.MeasureString(_displayText, font);
                        if (measured.Width <= textRect.Width)
                        {
                            // 不滚：垂直居中、左对齐
                            using (StringFormat fmt = new StringFormat
                            { Alignment = StringAlignment.Near, LineAlignment = StringAlignment.Center, FormatFlags = StringFormatFlags.NoWrap })
                                g.DrawString(_displayText, font, textBrush, textRect, fmt);

                            EnsureMarqueeState(false, measured.Width, textRect.Width);
                        }
                        else
                        {
                            // 滚动：clip 到 textRect，内文 X = textRect.X - phase
                            float scrollDist = measured.Width - textRect.Width + WidgetScaler.Px(12, Scale);
                            if (_marqueePhasePx > scrollDist)
                            {
                                _marqueePhasePx = 0;
                                _marqueeDwellMs = MARQUEE_DWELL_MS;
                            }
                            Region prevClip = g.Clip;
                            g.SetClip(textRect);
                            try
                            {
                                using (StringFormat fmt = new StringFormat
                                { Alignment = StringAlignment.Near, LineAlignment = StringAlignment.Center, FormatFlags = StringFormatFlags.NoWrap })
                                    g.DrawString(_displayText, font, textBrush,
                                        new RectangleF(textRect.X - _marqueePhasePx, textRect.Y, measured.Width + 4, textRect.Height), fmt);
                            }
                            finally { g.Clip = prevClip; }

                            EnsureMarqueeState(true, measured.Width, textRect.Width);
                        }
                    }

                    if (showArrow)
                    {
                        Rectangle arrowRect = new Rectangle(localX + r.Width - arrowW, localY, arrowW, r.Height);
                        using (SolidBrush arrowBg = new SolidBrush(Color.FromArgb(48, 24, 36, 44)))
                            g.FillRectangle(arrowBg, arrowRect);
                        using (Pen sep2 = new Pen(Color.FromArgb(31, 255, 255, 255)))
                            g.DrawLine(sep2, arrowRect.X, localY + 2, arrowRect.X, localY + r.Height - 3);
                        using (SolidBrush arrowBrush = new SolidBrush(_hover
                            ? Color.FromArgb(255, 223, 246, 255)
                            : Color.FromArgb(229, 160, 226, 255)))
                        using (StringFormat afmt = new StringFormat
                        { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center })
                            g.DrawString("➤", font, arrowBrush, arrowRect, afmt);
                    }
                }
                finally { g.TextRenderingHint = prevHint; }
            }
        }

        private void EnsureMarqueeState(bool wantActive, float textW, int areaW)
        {
            if (wantActive == _marqueeActive) return;
            _marqueeActive = wantActive;
            if (wantActive)
            {
                _marqueePhasePx = 0;
                _marqueeDwellMs = MARQUEE_DWELL_MS;
            }
            else
            {
                _marqueePhasePx = 0;
                _marqueeDwellMs = 0;
            }
            FireAnimState();
        }

        public bool TryHitTest(Point screenPt)
        {
            return ScreenBounds.Contains(screenPt);
        }

        public void OnMouseEvent(MouseEventArgs e, MouseEventKind kind)
        {
            switch (kind)
            {
                case MouseEventKind.Enter:
                case MouseEventKind.Move:
                    if (!_hover) { _hover = true; FireRepaint(); }
                    break;
                case MouseEventKind.Leave:
                    if (_hover) { _hover = false; FireRepaint(); }
                    break;
                case MouseEventKind.Click:
                    DispatchClick();
                    break;
            }
        }

        private void DispatchClick()
        {
            // 与 notch.js noticeMain click 等价：可交付直传，否则打开任务栏
            try
            {
                if (CanDeliver())
                {
                    string raw = "{\"hotspotId\":\"" + EscapeJson(_hotspotId) + "\"}";
                    _router.Dispatch("TASK_DELIVER", raw);
                }
                else
                {
                    _router.Dispatch("TASK_UI");
                }
            }
            catch (Exception ex)
            {
                LogManager.Log("[QuestNotice] dispatch failed ex=" + ex.Message);
            }
        }

        internal bool CanDeliver()
        {
            // 与 notch.js canDeliverNow 同一优先级，flash 态禁用避免误点新任务横幅直传
            if (_activeFlash != null) return false;
            if (!_taskDone) return false;
            if (!_navigable) return false;
            if (string.IsNullOrEmpty(_hotspotId)) return false;
            if (_mapMode == "3") return false;
            return true;
        }

        public void OnUiDataChanged(IReadOnlyDictionary<string, string> snapshot, ISet<string> changedKeys)
        {
            bool boundsDirty = false;
            bool repaintDirty = false;
            bool textRecompute = false;
            string piece;

            if (changedKeys.Contains("s") && snapshot.TryGetValue("s", out piece))
            {
                bool ready = TopRightToolsWidget.ParseUiBoolValue(piece);
                if (ready != _gameReady)
                {
                    _gameReady = ready;
                    if (!ready)
                    {
                        // 游戏未就绪：清队列与 flash，复位
                        lock (_flashLock) { _flashQueue.Clear(); }
                        _activeFlash = null;
                        _flashElapsedMs = 0;
                        _hover = false;
                        textRecompute = true;
                    }
                    boundsDirty = true;
                }
            }
            if (changedKeys.Contains("td") && snapshot.TryGetValue("td", out piece))
            {
                bool nextDone = TopRightToolsWidget.ParseUiBoolValue(piece);
                if (nextDone != _taskDone)
                {
                    _taskDone = nextDone;
                    boundsDirty = true; // mode 切换可能 hide/show
                    textRecompute = true;
                }
            }
            if (changedKeys.Contains("tdh") && snapshot.TryGetValue("tdh", out piece))
            {
                string next = StripPrefix(piece, "tdh");
                if (!string.Equals(next, _hotspotId, StringComparison.Ordinal))
                {
                    _hotspotId = next ?? "";
                    repaintDirty = true; // arrow 显示状态可能变化
                    textRecompute = true;
                }
            }
            if (changedKeys.Contains("tdn") && snapshot.TryGetValue("tdn", out piece))
            {
                bool nav = TopRightToolsWidget.ParseUiBoolValue(piece);
                if (nav != _navigable)
                {
                    _navigable = nav;
                    repaintDirty = true;
                    textRecompute = true;
                }
            }
            if (changedKeys.Contains("mm") && snapshot.TryGetValue("mm", out piece))
            {
                string next = StripPrefix(piece, "mm");
                if (!string.Equals(next, _mapMode, StringComparison.Ordinal))
                {
                    _mapMode = next ?? "0";
                    repaintDirty = true;
                    textRecompute = true;
                }
            }

            if (textRecompute) RebuildDisplayText();
            if (boundsDirty) FireBounds();
            else if (repaintDirty) FireRepaint();
        }

        // 与 LegacyTypes 一致；NativeHud 已按 type 集合做门控，这里仍 defensive switch
        private static readonly string[] LEGACY_TYPES = { "task", "announce" };
        public IEnumerable<string> LegacyTypes { get { return LEGACY_TYPES; } }

        public void OnLegacyUiData(string type, string[] fields)
        {
            if (string.IsNullOrEmpty(type)) return;
            if (type == "task")
            {
                string name = (fields != null && fields.Length > 0) ? fields[0] : "";
                EnqueueFlash("新任务: " + name, ICON_PLACEHOLDER);
            }
            else if (type == "announce")
            {
                string text = (fields != null && fields.Length > 0) ? fields[0] : "";
                EnqueueFlash(text, ICON_PLACEHOLDER);
            }
        }

        private void EnqueueFlash(string text, string icon)
        {
            if (string.IsNullOrEmpty(text)) return;
            FlashItem item = new FlashItem { Text = text, Icon = icon };
            lock (_flashLock) { _flashQueue.Enqueue(item); }
            if (_activeFlash == null)
            {
                PumpFlashOrFallback();
                FireBounds(); // 可能从 Idle/TaskDone 切到 Flash → 重算 visibility
            }
        }

        private void PumpFlashOrFallback()
        {
            FlashItem next = null;
            lock (_flashLock) { if (_flashQueue.Count > 0) next = _flashQueue.Dequeue(); }
            if (next != null)
            {
                _activeFlash = next;
                _flashElapsedMs = 0;
                _displayText = next.Text;
                _displayIcon = next.Icon ?? ICON_PLACEHOLDER;
            }
            else
            {
                _activeFlash = null;
                _flashElapsedMs = 0;
                RebuildDisplayText();
            }
            // text 变化 → 让 marquee 重算
            _marqueePhasePx = 0;
            _marqueeDwellMs = MARQUEE_DWELL_MS;
            FireAnimState();
        }

        private void RebuildDisplayText()
        {
            if (_activeFlash != null) return; // flash 文本由 PumpFlashOrFallback 设
            if (_taskDone)
            {
                _displayIcon = ICON_TASK_DONE;
                _displayText = BuildTaskDoneText();
            }
            else
            {
                _displayIcon = ICON_PLACEHOLDER;
                _displayText = "";
            }
            _marqueePhasePx = 0;
            _marqueeDwellMs = MARQUEE_DWELL_MS;
        }

        internal string BuildTaskDoneText()
        {
            // 与 notch.js buildTaskDoneText 同优先级，确保 click 行为与文案一致
            if (CanDeliver()) return "任务已达成 · 可交付";
            if (_mapMode == "3") return "任务已达成 · 战后交付";
            if (string.IsNullOrEmpty(_hotspotId)) return "任务已达成 · 暂无交付目标";
            if (!_navigable) return "任务已达成 · 交付点未解锁";
            return "任务已达成";
        }

        private static string StripPrefix(string fullPiece, string key)
        {
            if (string.IsNullOrEmpty(fullPiece)) return "";
            string prefix = key + ":";
            if (fullPiece.StartsWith(prefix, StringComparison.Ordinal))
                return fullPiece.Substring(prefix.Length);
            return fullPiece;
        }

        private static string EscapeJson(string s)
        {
            if (string.IsNullOrEmpty(s)) return "";
            return s.Replace("\\", "\\\\").Replace("\"", "\\\"");
        }

        // ── 单测可见 ──
        internal bool IsTaskDone { get { return _taskDone; } }
        internal bool IsNavigable { get { return _navigable; } }
        internal string HotspotId { get { return _hotspotId; } }
        internal string MapMode { get { return _mapMode; } }
        internal int FlashQueueCount { get { lock (_flashLock) { return _flashQueue.Count; } } }
        internal bool HasActiveFlash { get { return _activeFlash != null; } }
        internal string DisplayText { get { return _displayText; } }
        internal string DisplayIcon { get { return _displayIcon; } }
        internal void ForceGameReady(bool ready) { _gameReady = ready; }
        internal void AdvanceFlashMs(int ms)
        {
            // 模拟 Tick 时长推进 flash 计时；不触发 marquee（widget 测不依赖布局）
            if (_activeFlash == null) return;
            _flashElapsedMs += ms;
            if (_flashElapsedMs >= NOTICE_MS)
            {
                _activeFlash = null;
                _flashElapsedMs = 0;
                PumpFlashOrFallback();
            }
        }
        internal enum ClickRoute { TaskDeliver, TaskUi }
        internal ClickRoute ResolveClickRoute()
        {
            return CanDeliver() ? ClickRoute.TaskDeliver : ClickRoute.TaskUi;
        }

        private void FireBounds() { EventHandler h = BoundsOrVisibilityChanged; if (h != null) h(this, EventArgs.Empty); }
        private void FireRepaint() { EventHandler h = RepaintRequested; if (h != null) h(this, EventArgs.Empty); }
        private void FireAnimState() { EventHandler h = AnimationStateChanged; if (h != null) h(this, EventArgs.Empty); }
    }
}
