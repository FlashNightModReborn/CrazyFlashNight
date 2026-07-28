using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.IO;
using System.Windows.Forms;
using System.Xml;
using CF7Launcher.Guardian;

namespace CF7Launcher.Guardian.Hud
{
    /// <summary>
    /// Native notch 渲染单元。承载原 NotchOverlay 的「FPS 药丸 + 展开工具栏 + 通知栈 + 展开图表」全部行为，
    /// 由 NativeHudOverlay 的 widget 容器调度；与 NotchOverlay 单独 ULW 路径互斥
    /// （useNativeHud=true 时 Program.cs 不再实例化 NotchOverlay，本 widget 顶替）。
    ///
    /// 视觉与原 NotchOverlay 严格对齐（PaintRow1 / DrawToolbarButtons / DrawOtherMenu / DrawSparkline /
    /// DrawClock / DrawCurrencyPanel / DrawExpandedChart 全部移植）。差异：
    /// - 不再 SetWindowPos：NativeHud 统一 union → SetWindowPos
    /// - 鼠标走 OnMouseEvent (Move/Enter/Leave/Down/Up/Click) 而非 WndProc
    /// - 自身 Tick 由 NativeHud anim tick 驱动；33ms render coalesce 由 NativeHud 控制
    /// - 局部坐标（widget-local，原点 0,0）；Paint 时加 (ScreenBounds.X - hudOrigin.X, ScreenBounds.Y - hudOrigin.Y) 偏移
    /// </summary>
    public sealed class NotchWidget : INativeHudWidget, INativeHudCompositeBoundsProvider, IUiDataConsumer, IUiDataLegacyConsumer, IDisposable
    {
        #region 状态机

        private enum NotchState { Collapsed, Expanding, Expanded, Collapsing }
        private NotchState _state;

        #endregion

        #region 常量（与 NotchOverlay 完全一致）

        private const int CollapsedH = NativeHudTheme.TopBarHeightBase;
        private const int RowPadX = 6;
        private const int CurrencyIconW = 20;
        private const int CurrencyMinValueW = 48;
        private const int CurrencyGap = 2;
        private const int CenterFpsMinW = 28;
        private const int CenterGap = 3;
        private const int ArrowW = 14;
        private const int DividerW = 1;
        private const int DividerMarginX = 3;
        private const int Row1RightGap = 2;
        private const int ToolbarPadX = 8;
        private const int ToolbarPadTop = 2;
        private const int ToolbarPadBottom = 4;
        private const int ToolbarButtonH = NativeHudTheme.ToolbarButtonHeightBase;
        private const int ToolbarButtonGap = 2;
        private const int ToolbarRowGap = 2;
        private const int ToolbarGroupLabelW = 38;
        private const int ButtonPadX = 8;

        private const int AutoHideDelayMs = 500;
        private const int ExpandAnimMs = 150;
        private const int CollapseAnimMs = 200;
        private const int ExpandClickCooldownMs = 600;
        private const int StableRefreshMs = 250;

        private const int SparklinePoints = 30;
        private const int SparklineW = 70;
        private const int SparklineH = 16;
        private const int ExpandedChartW = 400;
        private const int ExpandedChartCanvasH = 120;
        private const int ExpandedChartPad = 6;
        private const int ExpandedChartHintGap = 3;
        private const int ExpandedChartHintH = 9;
        private const int ExpandedChartMaxHistory = 300;
        private const int ExpandedChartDangerFps = 18;
        private const int ExpandedChartTargetFps = 26;
        private const int ExpandedChartMinDiff = 5;

        private const float FpsGreenThreshold = 25f;
        private const float FpsYellowThreshold = 18f;

        // 通知栈
        private const int RowH = 20;
        private const int RowGap = 2;
        private const int MaxRows = 4;
        private const int TransientLifetimeMs = 4000;
        private const int GameTransientLifetimeMs = 3000;
        private const int GameThrottleMs = 350;
        private const int MaxGameRows = 4;
        private const int FadeInMs = 300;
        private const int FadeOutMs = 800;

        private const int MaxLightLevel = 9;

        #endregion

        #region 数据结构

        private sealed class CurrencySlot
        {
            public int Current;
            public int Target;
            public int From;
            public int AnimElapsedMs;
            public bool Animating;
            public int LastDelta;
            public int DeltaElapsedMs = 1200;
        }

        private sealed class GameNoticeQueueItem
        {
            public string Text;
            public Color Color;
            public int Count;
        }

        private sealed class NotchButtonDef
        {
            public string Label;
            public string CommandKey;
            public Keys KeyCode;
            public bool RequiresGameReady;
            public bool RequiresWarehouse;

            public NotchButtonDef(string label, string commandKey, Keys keyCode,
                bool requiresGameReady, bool requiresWarehouse)
            {
                Label = label;
                CommandKey = commandKey;
                KeyCode = keyCode;
                RequiresGameReady = requiresGameReady;
                RequiresWarehouse = requiresWarehouse;
            }
        }

        private static readonly NotchButtonDef[] Row1Buttons = {
            new NotchButtonDef("全屏", "F", Keys.F, false, false),
            new NotchButtonDef("日志", "LOG", Keys.None, false, false),
            new NotchButtonDef("其他 ▸", null, Keys.None, false, false)
        };
        private static readonly NotchButtonDef[] ToolbarButtons = {
            new NotchButtonDef("战队", "TEAM", Keys.None, true, false),
            new NotchButtonDef("平板", "TABLET", Keys.None, true, false),
            new NotchButtonDef("战备箱", "WAREHOUSE", Keys.None, true, true),
            new NotchButtonDef("情报", "INTELLIGENCE", Keys.None, true, false),
            new NotchButtonDef("材料", "MATERIALS", Keys.None, true, false),
            new NotchButtonDef("技能", "SKILLS", Keys.None, true, false),
            new NotchButtonDef("商城", "SHOP", Keys.None, true, false)
        };
        private static readonly NotchButtonDef[] ToolbarUtilityButtons = {
            new NotchButtonDef("点歌机", "JUKEBOX_EXPAND", Keys.None, true, false),
            new NotchButtonDef("地图开关", "MAPHUD_TOGGLE", Keys.None, true, false),
            new NotchButtonDef("修改器", "SETTINGS", Keys.None, true, false),
            new NotchButtonDef("帮助", "HELP", Keys.None, true, false)
        };
        private static readonly NotchButtonDef[] OtherGroupButtons = {
            new NotchButtonDef("控制", "OTHER_GROUP_0", Keys.None, false, false),
            new NotchButtonDef("测试", "OTHER_GROUP_1", Keys.None, false, false),
            new NotchButtonDef("工具", "OTHER_GROUP_2", Keys.None, false, false)
        };
        private static readonly NotchButtonDef[] OtherControlButtons = {
            new NotchButtonDef("Q 强退", "Q", Keys.Q, false, false),
            new NotchButtonDef("W 关闭", "W", Keys.W, false, false),
            new NotchButtonDef("R 重置", "R", Keys.R, false, false),
            new NotchButtonDef("P 截图", "P", Keys.P, false, false),
            new NotchButtonDef("O 打开", "O", Keys.O, false, false)
        };
        private static readonly NotchButtonDef[] OtherTestButtons = {
            new NotchButtonDef("高安箱测试", "LOCKBOX_TEST", Keys.None, false, false),
            new NotchButtonDef("锁芯校准测试", "PINALIGN_TEST", Keys.None, false, false),
            new NotchButtonDef("铁枪会入侵测试", "GOBANG_TEST", Keys.None, false, false),
            new NotchButtonDef("情报测试", "INTELLIGENCE_TEST", Keys.None, false, false),
            new NotchButtonDef("选关测试", "STAGE_SELECT_TEST", Keys.None, false, false),
            new NotchButtonDef("角斗场测试", "ARENA_TEST", Keys.None, false, false),
            new NotchButtonDef("新任务界面", "NEW_TASK_UI", Keys.None, true, false)
        };
        private static readonly NotchButtonDef[] OtherToolButtons = {
            new NotchButtonDef("动画测试", "CUTSCENE_TEST", Keys.None, false, false),
            new NotchButtonDef("烘焙图标", "BAKE", Keys.None, false, false),
            new NotchButtonDef("烘焙测试(10)", "BAKE10", Keys.None, false, false),
            new NotchButtonDef("烘焙技能图标", "BAKE_SKILL", Keys.None, false, false)
        };
        private static readonly NotchButtonDef[][] OtherButtonGroups = {
            OtherControlButtons,
            OtherTestButtons,
            OtherToolButtons
        };

        #endregion

        #region 字段

        private readonly Control _anchor;
        private readonly FlashCoordinateMapper _mapper;
        private readonly FpsRingBuffer _fpsBuffer;
        private readonly AudioHudState _audioHudState;
        private readonly Action _onToggleFullscreen;
        private readonly Action _onToggleLog;
        private readonly Action _onForceExit;
        private readonly Action<Keys> _onSendKey;
        private LauncherCommandRouter _router;

        private readonly int[] _lightLevels;
        private readonly CurrencySlot _gold = new CurrencySlot();
        private readonly CurrencySlot _kp = new CurrencySlot();
        private readonly List<NotchInfoRow> _infoRows = new List<NotchInfoRow>();
        private readonly List<GameNoticeQueueItem> _gameQueue = new List<GameNoticeQueueItem>();

        private float _expandProgress; // 0=collapsed, 1=expanded
        private int _autoHideCountdown;
        private int _expandClickCooldown;
        private int _hoverButtonIndex = -1;
        private bool _gameReady;
        private int _questProgress;
        private int _stableRefreshElapsedMs;
        private int _gameThrottleRemainingMs;
        private int _gameNoticeSerial;

        private bool _otherMenuOpen;
        private int _otherMenuGroupIndex;
        private bool _chartVisible;
        // 展开/收起动画期间保留最大合成矩形；实际命中仍只认 ScreenBounds。
        private bool _reserveExpandedCompositeBounds;

        // widget-local hit rects（widget 自身 ScreenBounds 原点为 (0,0)）
        private Rectangle[] _buttonRects = new Rectangle[0];
        private NotchButtonDef[] _buttonDefs = new NotchButtonDef[0];
        private Rectangle _sparklineRect = Rectangle.Empty;
        private Rectangle _expandButtonRect = Rectangle.Empty;
        private Rectangle _expandedChartRect = Rectangle.Empty;

        public event EventHandler BoundsOrVisibilityChanged;
        public event EventHandler RepaintRequested;
        public event EventHandler AnimationStateChanged;

        #endregion

        public NotchWidget(Control anchor, FpsRingBuffer fpsBuffer, string projectRoot,
            Action onToggleFullscreen, Action onToggleLog,
            Action onForceExit, Action<Keys> onSendKey,
            AudioHudState audioHudState = null)
        {
            if (anchor == null) throw new ArgumentNullException("anchor");
            if (fpsBuffer == null) throw new ArgumentNullException("fpsBuffer");
            _anchor = anchor;
            _mapper = new FlashCoordinateMapper(anchor, 1024f, 576f);
            _fpsBuffer = fpsBuffer;
            _audioHudState = audioHudState ?? new AudioHudState();
            _onToggleFullscreen = onToggleFullscreen;
            _onToggleLog = onToggleLog;
            _onForceExit = onForceExit;
            _onSendKey = onSendKey;
            _lightLevels = LoadLightLevels(projectRoot);
            _state = NotchState.Collapsed;
            _anchor.Resize += delegate { FireBounds(); };
        }

        public void SetCommandRouter(LauncherCommandRouter router)
        {
            _router = router;
        }

        #region INativeHudWidget

        public Rectangle ScreenBounds
        {
            get
            {
                if (_anchor == null || !_anchor.IsHandleCreated) return Rectangle.Empty;
                try
                {
                    Point origin = _anchor.PointToScreen(Point.Empty);
                    float vpX, vpY, vpW, vpH;
                    _mapper.CalcViewport(out vpX, out vpY, out vpW, out vpH);
                    int w, h;
                    GetCurrentSize(out w, out h);
                    int scrX = origin.X + (int)vpX + ((int)vpW - w) / 2;
                    int scrY = origin.Y + (int)vpY;
                    return new Rectangle(scrX, scrY, Math.Max(1, w), Math.Max(1, h));
                }
                catch { return Rectangle.Empty; }
            }
        }

        public Rectangle CompositeBounds
        {
            get
            {
                if (!_reserveExpandedCompositeBounds) return ScreenBounds;
                if (_anchor == null || !_anchor.IsHandleCreated) return Rectangle.Empty;
                try
                {
                    Point origin = _anchor.PointToScreen(Point.Empty);
                    float vpX, vpY, vpW, vpH;
                    _mapper.CalcViewport(out vpX, out vpY, out vpW, out vpH);
                    int w, h;
                    GetSizeForProgress(1f, out w, out h);
                    int scrX = origin.X + (int)vpX + ((int)vpW - w) / 2;
                    int scrY = origin.Y + (int)vpY;
                    return new Rectangle(scrX, scrY, Math.Max(1, w), Math.Max(1, h));
                }
                catch { return Rectangle.Empty; }
            }
        }

        public bool Visible { get { return _anchor != null && _anchor.IsHandleCreated; } }

        public bool WantsAnimationTick
        {
            get
            {
                if (_state == NotchState.Expanding || _state == NotchState.Collapsing) return true;
                if (_state == NotchState.Expanded && _autoHideCountdown > 0) return true;
                if (_expandClickCooldown > 0) return true;
                if (_gold.Animating || _gold.DeltaElapsedMs < 1200) return true;
                if (_kp.Animating || _kp.DeltaElapsedMs < 1200) return true;
                if (_gameThrottleRemainingMs > 0 || _gameQueue.Count > 0) return true;
                if (_infoRows.Count > 0) return true;
                // FPS sparkline / clock 走 stable refresh（每 250ms 重绘）；
                // 这里强制需要 tick 推动 _stableRefreshElapsedMs 累加
                if (_fpsBuffer != null && _fpsBuffer.HasData) return true;
                if (_audioHudState != null && _audioHudState.WantsTick) return true;
                return false;
            }
        }

        public void Tick(int deltaMs)
        {
            int dt = Math.Max(1, deltaMs);
            bool needsPaint = false;
            bool boundsChanged = false;

            if (_expandClickCooldown > 0)
            {
                _expandClickCooldown -= dt;
                if (_expandClickCooldown < 0) _expandClickCooldown = 0;
            }

            switch (_state)
            {
                case NotchState.Expanding:
                    _expandProgress += (float)dt / ExpandAnimMs;
                    if (_expandProgress >= 1f) { _expandProgress = 1f; _state = NotchState.Expanded; }
                    needsPaint = true;
                    break;
                case NotchState.Expanded:
                    if (_autoHideCountdown > 0)
                    {
                        _autoHideCountdown -= dt;
                        if (_autoHideCountdown <= 0)
                        {
                            _autoHideCountdown = 0;
                            _state = NotchState.Collapsing;
                            CloseOtherMenu();
                            _chartVisible = false;
                            _expandedChartRect = Rectangle.Empty;
                            needsPaint = true;
                        }
                    }
                    break;
                case NotchState.Collapsing:
                    _expandProgress -= (float)dt / CollapseAnimMs;
                    if (_expandProgress <= 0f)
                    {
                        _expandProgress = 0f;
                        _state = NotchState.Collapsed;
                        _reserveExpandedCompositeBounds = false;
                        boundsChanged = true;
                    }
                    needsPaint = true;
                    break;
                case NotchState.Collapsed:
                    break;
            }

            if (TickCurrencySlot(_gold, dt)) needsPaint = true;
            if (TickCurrencySlot(_kp, dt)) needsPaint = true;
            if (_audioHudState != null && _audioHudState.Tick(dt)) needsPaint = true;
            if (_gameThrottleRemainingMs > 0)
            {
                _gameThrottleRemainingMs -= dt;
                if (_gameThrottleRemainingMs <= 0)
                {
                    _gameThrottleRemainingMs = 0;
                    DrainGameQueue();
                    needsPaint = true;
                    boundsChanged = true;
                }
            }

            for (int i = _infoRows.Count - 1; i >= 0; i--)
            {
                _infoRows[i].AgeMs += dt;
                if (_infoRows[i].PulseMs > 0)
                {
                    _infoRows[i].PulseMs -= dt;
                    if (_infoRows[i].PulseMs < 0) _infoRows[i].PulseMs = 0;
                    needsPaint = true;
                }
                if (_infoRows[i].PrevText != null)
                {
                    _infoRows[i].TransitionMs += dt;
                    if (_infoRows[i].TransitionMs >= NotchInfoRow.TransitionDuration)
                        _infoRows[i].PrevText = null;
                    needsPaint = true;
                }
                if (!_infoRows[i].Persistent)
                {
                    _infoRows[i].RemainingMs -= dt;
                    if (_infoRows[i].RemainingMs <= 0)
                    {
                        _infoRows.RemoveAt(i);
                        boundsChanged = true;
                    }
                    needsPaint = true;
                }
            }

            _stableRefreshElapsedMs += dt;
            if (_stableRefreshElapsedMs >= StableRefreshMs)
            {
                _stableRefreshElapsedMs = 0;
                needsPaint = true;
            }

            if (boundsChanged) FireBounds();
            else if (needsPaint) FireRepaint();

            // 上一个 tick 后 WantsAnimationTick 可能从 true 转 false（无 animating slot / 通知耗尽）
            // FireAnimationStateChanged 让 NativeHud 重新评估是否停 _animTick
            FireAnimationStateChanged();
        }

        public void Paint(Graphics g, float dpr, Point hudOrigin)
        {
            Rectangle bounds = ScreenBounds;
            if (bounds.Width <= 0 || bounds.Height <= 0) return;
            int offX = bounds.X - hudOrigin.X;
            int offY = bounds.Y - hudOrigin.Y;

            float vpX, vpY, vpW, vpH;
            _mapper.CalcViewport(out vpX, out vpY, out vpW, out vpH);
            float scale = GetScale(vpH);

            int w = bounds.Width;
            int h = bounds.Height;

            _sparklineRect = Rectangle.Empty;
            _expandButtonRect = Rectangle.Empty;
            if (!_chartVisible) _expandedChartRect = Rectangle.Empty;

            float t = _expandProgress;
            float eased = t * (2f - t);
            int row1H = Px(CollapsedH, scale);
            int toolbarH = _gameReady ? (int)(ExpandedToolbarHeight(scale) * eased) : 0;
            int pillH = row1H + toolbarH;

            GraphicsState saved = g.Save();
            try
            {
                g.TranslateTransform(offX, offY);
                // 最后一道绘制护栏：即使未来按钮测量回归，也不得越过 Notch 自身视觉矩形侵入右侧 HUD。
                g.SetClip(new Rectangle(0, 0, w, h), CombineMode.Intersect);

                NativeHudTheme.DrawPanel(g, new Rectangle(0, 0, w, pillH), scale,
                    ResolvePillColor(), Color.Empty, false);
                if (toolbarH > 2)
                {
                    using (Pen separator = new Pen(NativeHudTheme.Separator, NativeHudTheme.StrokePx(scale)))
                        g.DrawLine(separator, Px(4, scale), row1H, w - Px(4, scale), row1H);
                }

                using (Font fpsFont = new Font("Consolas", Pxf(13f, scale), FontStyle.Bold, GraphicsUnit.Pixel))
                using (Font textFont = NativeHudFonts.CreateUiFont(Pxf(12f, scale), FontStyle.Regular, GraphicsUnit.Pixel))
                using (Font monoFont = new Font("Consolas", Pxf(12f, scale), FontStyle.Bold, GraphicsUnit.Pixel))
                {
                    PaintRow1(g, row1H, scale, fpsFont, textFont, monoFont);
                    if (_gameReady && toolbarH > 2)
                    {
                        byte buttonAlpha = (byte)(255 * Math.Min(1f, Math.Max(0f, (eased - 0.15f) / 0.85f)));
                        DrawToolbarButtons(g, w, row1H, scale, textFont, buttonAlpha);
                    }
                    if (_otherMenuOpen)
                        DrawOtherMenu(g, w, pillH, scale, textFont);
                }

                int rowPadX = Px(6, scale);
                int scaledRowH = Px(RowH, scale);
                int scaledRowGap = Px(RowGap, scale);
                int rowsStartY = pillH + (_otherMenuOpen ? OtherMenuHeight(scale) : 0);
                using (Font infoFont = CreateInfoRowFont(false, scale))
                using (Font gameInfoFont = CreateInfoRowFont(true, scale))
                {
                    for (int ri = 0; ri < _infoRows.Count; ri++)
                    {
                        NotchInfoRow row = _infoRows[ri];
                        Font rowFont = row.IsGame ? gameInfoFont : infoFont;
                        int rowY = rowsStartY + ri * (scaledRowGap + scaledRowH) + scaledRowGap;
                        float textY = rowY + Math.Max(0f, (scaledRowH - rowFont.GetHeight(g)) / 2f);

                        float rowAlpha = 1f;
                        if (row.AgeMs < FadeInMs)
                            rowAlpha = (float)row.AgeMs / FadeInMs;
                        if (!row.Persistent && row.RemainingMs < FadeOutMs)
                            rowAlpha = Math.Min(rowAlpha, (float)row.RemainingMs / FadeOutMs);
                        byte ra = (byte)(255 * Math.Max(0f, Math.Min(1f, rowAlpha)));
                        int textPadX = row.Persistent ? rowPadX + Px(10, scale) : rowPadX;
                        int textInnerW = w - textPadX - rowPadX;
                        if (textInnerW < Px(20, scale)) textInnerW = Px(20, scale);
                        float pulse = row.PulseMs > 0 ? (float)row.PulseMs / 350f : 0f;
                        Color rowBg = row.IsGame
                            ? Color.FromArgb((byte)(ra * (0.10f + 0.10f * pulse)), 255, 255, 255)
                            : Color.FromArgb((byte)(ra * (row.Persistent ? 0.82f : 0.70f)), 20, 20, 22);

                        NativeHudTheme.DrawPanel(g, new Rectangle(0, rowY, w, scaledRowH), scale,
                            rowBg, row.Persistent ? row.AccentColor : Color.Empty, row.Persistent || row.IsGame);
                        if (row.Persistent)
                        {
                            using (SolidBrush accent = new SolidBrush(Color.FromArgb(ra, row.AccentColor)))
                                g.FillRectangle(accent, 0, rowY, Px(3, scale), scaledRowH);
                        }
                        if (row.IsGame)
                        {
                            using (Pen border = new Pen(Color.FromArgb((byte)(ra * 0.2f), 255, 215, 0)))
                                g.DrawRectangle(border, 0, rowY, w - 1, scaledRowH - 1);
                        }

                        g.SetClip(new Rectangle(textPadX, rowY, textInnerW, scaledRowH));

                        SizeF textSize = g.MeasureString(row.Text, rowFont);
                        float textW = textSize.Width;
                        float textX;
                        if (textW <= textInnerW)
                        {
                            textX = row.Persistent ? textPadX : textPadX + (textInnerW - textW) / 2f;
                        }
                        else
                        {
                            float overflow = textW - textInnerW;
                            float scrollCycle = 4000f;
                            float phase = (row.AgeMs % scrollCycle) / scrollCycle;
                            float scrollT = phase < 0.5f ? phase * 2f : (1f - phase) * 2f;
                            scrollT = scrollT * scrollT * (3f - 2f * scrollT);
                            textX = textPadX - overflow * scrollT;
                        }

                        if (row.PrevText != null)
                        {
                            float transT = (float)row.TransitionMs / NotchInfoRow.TransitionDuration;
                            transT = Math.Max(0f, Math.Min(1f, transT));
                            byte oldA = (byte)(ra * (1f - transT));
                            Color oldC = Color.FromArgb(oldA, row.PrevColor.R, row.PrevColor.G, row.PrevColor.B);
                            SizeF oldSize = g.MeasureString(row.PrevText, rowFont);
                            float oldX = (oldSize.Width <= textInnerW)
                                ? (row.Persistent ? textPadX : textPadX + (textInnerW - oldSize.Width) / 2f)
                                : textPadX;
                            using (SolidBrush ob = new SolidBrush(oldC))
                                g.DrawString(row.PrevText, rowFont, ob, oldX, textY);
                            byte newA = (byte)(ra * transT);
                            Color newC = Color.FromArgb(newA, row.AccentColor.R, row.AccentColor.G, row.AccentColor.B);
                            using (SolidBrush nb = new SolidBrush(newC))
                                g.DrawString(row.Text, rowFont, nb, textX, textY);
                        }
                        else
                        {
                            Color rc = Color.FromArgb(ra, row.AccentColor.R, row.AccentColor.G, row.AccentColor.B);
                            using (SolidBrush rb = new SolidBrush(rc))
                                g.DrawString(row.Text, rowFont, rb, textX, textY);
                        }
                        g.ResetClip();
                    }
                }

                if (_chartVisible)
                {
                    int chartH = ExpandedChartHeight(scale);
                    Rectangle chartRect = new Rectangle(0, h - chartH, w, chartH);
                    using (Font chartLabelFont = new Font("Consolas", Pxf(9f, scale), FontStyle.Regular, GraphicsUnit.Pixel))
                    using (Font chartHintFont = new Font("Consolas", Pxf(9f, scale), FontStyle.Regular, GraphicsUnit.Pixel))
                    {
                        DrawExpandedChart(g, chartRect, scale, chartLabelFont, chartHintFont);
                    }
                }
            }
            finally
            {
                g.Restore(saved);
            }
        }

        public bool TryHitTest(Point screenPt)
        {
            Rectangle bounds = ScreenBounds;
            return bounds.Width > 0 && bounds.Contains(screenPt);
        }

        public void OnMouseEvent(MouseEventArgs e, MouseEventKind kind)
        {
            Rectangle bounds = ScreenBounds;
            if (bounds.Width <= 0) return;
            int localX = e.X - bounds.X;
            int localY = e.Y - bounds.Y;

            switch (kind)
            {
                case MouseEventKind.Enter:
                {
                    bool canHoverExpand = _state == NotchState.Collapsed || _state == NotchState.Collapsing;
                    if (ShouldStartHoverExpand(canHoverExpand, _expandClickCooldown))
                    {
                        _reserveExpandedCompositeBounds = true;
                        _state = NotchState.Expanding;
                        FireBounds();
                        FireAnimationStateChanged();
                    }
                    _autoHideCountdown = 0;
                    UpdateHoverButton(localX, localY);
                    FireRepaint();
                    break;
                }
                case MouseEventKind.Move:
                {
                    bool canHoverExpand = _state == NotchState.Collapsed || _state == NotchState.Collapsing;
                    if (ShouldStartHoverExpand(canHoverExpand, _expandClickCooldown))
                    {
                        _reserveExpandedCompositeBounds = true;
                        _state = NotchState.Expanding;
                        FireBounds();
                        FireAnimationStateChanged();
                    }
                    _autoHideCountdown = 0;
                    int prevHover = _hoverButtonIndex;
                    UpdateHoverButton(localX, localY);
                    if (prevHover != _hoverButtonIndex) FireRepaint();
                    break;
                }
                case MouseEventKind.Leave:
                {
                    _hoverButtonIndex = -1;
                    if (_state == NotchState.Expanded || _state == NotchState.Expanding)
                    {
                        _autoHideCountdown = AutoHideDelayMs;
                        FireAnimationStateChanged();
                    }
                    FireRepaint();
                    break;
                }
                case MouseEventKind.Click:
                    if (e.Button == MouseButtons.Left) HandleClick(localX, localY);
                    break;
            }
        }

        #endregion

        #region INotchSink-equivalent（NativeHudOverlay 在 UI 线程派发）

        public void AddNotice(string text, Color accentColor)
        {
            AddNotice("_notice", text, accentColor);
        }

        public void AddNotice(string category, string text, Color accentColor)
        {
            if (string.Equals(category, "game", StringComparison.Ordinal))
            {
                AddGameNotice(text, accentColor);
                return;
            }
            UpsertRow(category, text, accentColor, false, TransientLifetimeMs);
            FireBounds();
            FireAnimationStateChanged();
            FireRepaint();
        }

        public void SetStatusItem(string id, string label, string subLabel, Color accentColor)
        {
            string text = label;
            if (!string.IsNullOrEmpty(subLabel)) text += "  " + subLabel;
            UpsertRow(id, text, accentColor, true, 0);
            FireBounds();
            FireAnimationStateChanged();
            FireRepaint();
        }

        public void ClearStatusItem(string id)
        {
            RemoveRow(id);
            FireBounds();
            FireAnimationStateChanged();
            FireRepaint();
        }

        private void AddGameNotice(string text, Color color)
        {
            string safeText = text ?? "";
            for (int i = 0; i < _gameQueue.Count; i++)
            {
                if (_gameQueue[i].Text == safeText) { _gameQueue[i].Count++; return; }
            }
            for (int i = 0; i < _infoRows.Count; i++)
            {
                NotchInfoRow row = _infoRows[i];
                if (row != null && row.IsGame && row.BaseText == safeText)
                {
                    row.Count = Math.Max(1, row.Count) + 1;
                    row.Text = safeText + " x" + row.Count.ToString(System.Globalization.CultureInfo.InvariantCulture);
                    row.AccentColor = color;
                    row.RemainingMs = GameTransientLifetimeMs;
                    row.PulseMs = 350;
                    FireRepaint();
                    return;
                }
            }
            GameNoticeQueueItem item = new GameNoticeQueueItem();
            item.Text = safeText;
            item.Color = color;
            item.Count = 1;
            _gameQueue.Add(item);
            DrainGameQueue();
            FireBounds();
            FireAnimationStateChanged();
            FireRepaint();
        }

        private void DrainGameQueue()
        {
            if (_gameThrottleRemainingMs > 0 || _gameQueue.Count == 0) return;
            GameNoticeQueueItem item = _gameQueue[0];
            _gameQueue.RemoveAt(0);
            string display = item.Count > 1
                ? item.Text + " x" + item.Count.ToString(System.Globalization.CultureInfo.InvariantCulture)
                : item.Text;
            NotchInfoRow row = new NotchInfoRow();
            row.Category = "game_" + (++_gameNoticeSerial).ToString(System.Globalization.CultureInfo.InvariantCulture);
            row.Text = display;
            row.BaseText = item.Text;
            row.AccentColor = item.Color;
            row.Persistent = false;
            row.RemainingMs = GameTransientLifetimeMs;
            row.AgeMs = 0;
            row.IsGame = true;
            row.Count = item.Count;
            _infoRows.Add(row);
            TrimGameRows();
            if (_gameQueue.Count > 0) _gameThrottleRemainingMs = GameThrottleMs;
        }

        private void TrimGameRows()
        {
            int gameRows = 0;
            for (int i = 0; i < _infoRows.Count; i++)
                if (_infoRows[i].IsGame) gameRows++;
            while (gameRows > MaxGameRows)
            {
                for (int i = 0; i < _infoRows.Count; i++)
                {
                    if (_infoRows[i].IsGame) { _infoRows.RemoveAt(i); gameRows--; break; }
                }
            }
        }

        private void UpsertRow(string category, string text, Color color, bool persistent, int lifetimeMs)
        {
            for (int i = 0; i < _infoRows.Count; i++)
            {
                if (_infoRows[i].Category == category)
                {
                    if (_infoRows[i].Text != text)
                    {
                        _infoRows[i].PrevText = _infoRows[i].Text;
                        _infoRows[i].PrevColor = _infoRows[i].AccentColor;
                        _infoRows[i].TransitionMs = 0;
                    }
                    _infoRows[i].Text = text;
                    _infoRows[i].AccentColor = color;
                    if (!persistent) _infoRows[i].RemainingMs = lifetimeMs;
                    return;
                }
            }
            NotchInfoRow row = new NotchInfoRow();
            row.Category = category;
            row.Text = text;
            row.AccentColor = color;
            row.Persistent = persistent;
            row.RemainingMs = persistent ? 0 : lifetimeMs;
            row.AgeMs = 0;
            _infoRows.Add(row);
            SortRows();
            while (_infoRows.Count > MaxRows)
            {
                bool removed = false;
                for (int i = _infoRows.Count - 1; i >= 0; i--)
                {
                    if (!_infoRows[i].Persistent) { _infoRows.RemoveAt(i); removed = true; break; }
                }
                if (!removed) break;
            }
        }

        private void RemoveRow(string category)
        {
            for (int i = _infoRows.Count - 1; i >= 0; i--)
            {
                if (_infoRows[i].Category == category) { _infoRows.RemoveAt(i); break; }
            }
        }

        private void SortRows()
        {
            _infoRows.Sort(delegate(NotchInfoRow a, NotchInfoRow b)
            {
                if (a.Persistent && !b.Persistent) return -1;
                if (!a.Persistent && b.Persistent) return 1;
                return 0;
            });
        }

        #endregion

        #region IUiDataConsumer / IUiDataLegacyConsumer

        private static readonly string[] _uiDataTypes = { "currency" };
        public IEnumerable<string> LegacyTypes { get { return _uiDataTypes; } }

        public void OnUiDataChanged(IReadOnlyDictionary<string, string> snapshot, ISet<string> changedKeys)
        {
            bool repaint = false;
            bool bounds = false;
            string fullPiece;
            if (_audioHudState != null && _audioHudState.ApplyUiData(snapshot, changedKeys))
                repaint = true;
            if (snapshot.TryGetValue("s", out fullPiece))
            {
                bool ready = StripPrefix(fullPiece, "s") == "1";
                if (ready != _gameReady)
                {
                    _gameReady = ready;
                    if (!ready)
                    {
                        _otherMenuOpen = false;
                        _chartVisible = false;
                        _sparklineRect = Rectangle.Empty;
                        _expandButtonRect = Rectangle.Empty;
                        _expandedChartRect = Rectangle.Empty;
                        _hoverButtonIndex = -1;
                    }
                    bounds = true;
                    repaint = true;
                }
            }
            if (snapshot.TryGetValue("q", out fullPiece))
            {
                int next = ParseInt(StripPrefix(fullPiece, "q"), 0);
                if (next != _questProgress) { _questProgress = next; repaint = true; bounds = true; }
            }
            if (snapshot.TryGetValue("g", out fullPiece))
            {
                StartCurrencyUpdate(_gold, ParseInt(StripPrefix(fullPiece, "g"), 0), int.MinValue);
                repaint = true;
                bounds = true;
            }
            if (snapshot.TryGetValue("k", out fullPiece))
            {
                StartCurrencyUpdate(_kp, ParseInt(StripPrefix(fullPiece, "k"), 0), int.MinValue);
                repaint = true;
                bounds = true;
            }
            if (bounds) FireBounds();
            else if (repaint) FireRepaint();
            if (repaint) FireAnimationStateChanged();
        }

        public void OnLegacyUiData(string type, string[] fields)
        {
            if (type != "currency" || fields == null || fields.Length < 2) return;
            string id = fields[0];
            int value = ParseInt(fields[1], 0);
            int delta = fields.Length >= 3 ? ParseInt(fields[2], 0) : 0;
            bool repaint = false;
            if (id == "gold") { StartCurrencyUpdate(_gold, value, delta); repaint = true; }
            else if (id == "kpoint") { StartCurrencyUpdate(_kp, value, delta); repaint = true; }
            if (repaint)
            {
                FireBounds();
                FireAnimationStateChanged();
            }
        }

        #endregion

        #region Click handling

        private void HandleClick(int localX, int localY)
        {
            if (_chartVisible && _expandedChartRect.Contains(localX, localY))
            {
                _chartVisible = false;
                _expandedChartRect = Rectangle.Empty;
                FireBounds();
                FireRepaint();
                return;
            }
            if (_sparklineRect.Contains(localX, localY))
            {
                ToggleExpandedChart();
                return;
            }
            if (_expandButtonRect.Contains(localX, localY))
            {
                ToggleNotchFromExpandButton();
                return;
            }
            for (int i = 0; i < _buttonRects.Length; i++)
            {
                if (_buttonRects[i].Contains(localX, localY))
                {
                    ExecuteButton(i);
                    break;
                }
            }
        }

        private void ToggleExpandedChart()
        {
            if (!_gameReady) return;
            _chartVisible = !_chartVisible;
            if (_chartVisible)
            {
                CloseOtherMenu();
                _reserveExpandedCompositeBounds = true;
                _state = NotchState.Expanded;
                _expandProgress = 1f;
                _autoHideCountdown = 0;
            }
            else
            {
                _expandedChartRect = Rectangle.Empty;
            }
            FireBounds();
            FireAnimationStateChanged();
            FireRepaint();
        }

        private void ToggleNotchFromExpandButton()
        {
            if (!_gameReady) return;
            bool expandedLike = _state == NotchState.Expanded
                || _state == NotchState.Expanding
                || _expandProgress > 0.01f;
            if (expandedLike)
            {
                _reserveExpandedCompositeBounds = true;
                _chartVisible = false;
                _expandedChartRect = Rectangle.Empty;
                CloseOtherMenu();
                _autoHideCountdown = 0;
                _expandClickCooldown = ExpandClickCooldownMs;
                _state = _expandProgress <= 0f ? NotchState.Collapsed : NotchState.Collapsing;
            }
            else
            {
                _reserveExpandedCompositeBounds = true;
                _expandClickCooldown = 0;
                _autoHideCountdown = 0;
                _state = NotchState.Expanding;
            }
            FireBounds();
            FireAnimationStateChanged();
            FireRepaint();
        }

        private void ExecuteButton(int index)
        {
            if (index < 0 || index >= _buttonDefs.Length) return;
            NotchButtonDef def = _buttonDefs[index];
            if (def == null) return;
            if (def.Label == "其他 ▸")
            {
                if (_otherMenuOpen) CloseOtherMenu();
                else
                {
                    _otherMenuOpen = true;
                    _otherMenuGroupIndex = 0;
                }
                FireBounds();
                FireRepaint();
                return;
            }
            if (!string.IsNullOrEmpty(def.CommandKey)
                && def.CommandKey.StartsWith("OTHER_GROUP_", StringComparison.Ordinal))
            {
                int nextGroup;
                if (int.TryParse(def.CommandKey.Substring("OTHER_GROUP_".Length), out nextGroup)
                    && nextGroup >= 0 && nextGroup < OtherButtonGroups.Length
                    && nextGroup != _otherMenuGroupIndex)
                {
                    _otherMenuGroupIndex = nextGroup;
                    FireBounds();
                    FireRepaint();
                }
                return;
            }
            bool closeOtherAfterCommand = _otherMenuOpen;
            if (closeOtherAfterCommand) CloseOtherMenu();
            if (def.CommandKey == "LOG")
            {
                if (_onToggleLog != null) _onToggleLog();
            }
            else if (def.CommandKey == "F")
            {
                if (_onToggleFullscreen != null) _onToggleFullscreen();
            }
            else if (def.CommandKey == "Q")
            {
                if (_onForceExit != null) _onForceExit();
            }
            else if (!string.IsNullOrEmpty(def.CommandKey) && _router != null)
            {
                try { _router.Dispatch(def.CommandKey); }
                catch (Exception ex) { LogManager.Log("[NotchWidget] dispatch failed key=" + def.CommandKey + " ex=" + ex.Message); }
            }
            else if (def.KeyCode != Keys.None)
            {
                if (_onSendKey != null) _onSendKey(def.KeyCode);
            }
            else
            {
                FireRepaint();
            }
            if (closeOtherAfterCommand)
            {
                FireBounds();
                FireRepaint();
            }
        }

        private void UpdateHoverButton(int localX, int localY)
        {
            _hoverButtonIndex = -1;
            for (int i = 0; i < _buttonRects.Length; i++)
            {
                if (_buttonRects[i].Contains(localX, localY)) { _hoverButtonIndex = i; break; }
            }
        }

        #endregion

        #region 渲染辅助（与 NotchOverlay 严格对齐）

        private void GetCurrentSize(out int w, out int h)
        {
            GetSizeForProgress(_expandProgress, out w, out h);
        }

        private void GetSizeForProgress(float progress, out int w, out int h)
        {
            float vpX, vpY, vpW, vpH;
            _mapper.CalcViewport(out vpX, out vpY, out vpW, out vpH);
            float scale = GetScale(vpH);
            int collapsedW = ComputeCollapsedWidth(scale);
            Rectangle viewport = new Rectangle(0, 0, Math.Max(1, (int)vpW), Math.Max(1, (int)vpH));
            int expandedW = ComputeExpandedWidth(scale, viewport);

            float t = Math.Max(0f, Math.Min(1f, progress));
            float eased = t * (2f - t);

            w = collapsedW + (int)((expandedW - collapsedW) * eased);
            int row1H = Px(CollapsedH, scale);
            int toolbarH = _gameReady ? ExpandedToolbarHeight(scale) : 0;
            h = row1H + (int)(toolbarH * eased);
            int rowCount = _infoRows.Count;
            if (rowCount > 0)
                h += rowCount * (Px(RowGap, scale) + Px(RowH, scale));
            if (_otherMenuOpen) h += OtherMenuHeight(scale);
            if (_chartVisible)
                h += ExpandedChartHeight(scale);
        }

        private void DrawToolbarButtons(Graphics g, int totalW, int row1H, float scale, Font font, byte alpha)
        {
            int firstY = row1H + Px(ToolbarPadTop, scale);
            DrawToolbarButtonRow(g, "游戏", ToolbarButtons, firstY, scale, font, alpha);
            int secondY = firstY + Px(ToolbarButtonH + ToolbarRowGap, scale);
            DrawToolbarButtonRow(g, "辅助", ToolbarUtilityButtons, secondY, scale, font, alpha);
            int thirdY = secondY + Px(ToolbarButtonH + ToolbarRowGap, scale);
            DrawToolbarButtonRow(g, "系统", Row1Buttons, thirdY, scale, font, alpha);
        }

        private void DrawToolbarButtonRow(Graphics g, string groupLabel, NotchButtonDef[] source, int y, float scale, Font font, byte alpha)
        {
            List<Rectangle> rects = new List<Rectangle>();
            List<NotchButtonDef> defs = new List<NotchButtonDef>();
            int btnH = Px(ToolbarButtonH, scale);
            int gap = Px(ToolbarButtonGap, scale);
            int x = Px(ToolbarPadX, scale);
            int labelW = Px(ToolbarGroupLabelW, scale);
            Rectangle labelRect = new Rectangle(x, y, labelW, btnH);
            using (SolidBrush labelBrush = new SolidBrush(NativeHudTheme.WithAlpha(
                NativeHudTheme.TextSecondary, Math.Min(210, (int)alpha))))
            using (StringFormat labelFmt = new StringFormat { Alignment = StringAlignment.Near, LineAlignment = StringAlignment.Center })
                g.DrawString(groupLabel, font, labelBrush, labelRect, labelFmt);
            x += labelW;

            for (int i = 0; i < source.Length; i++)
            {
                NotchButtonDef def = source[i];
                if (!ShouldShowButton(def)) continue;
                int btnW = MeasureButtonWidth(g, font, def.Label, scale);
                Rectangle r = new Rectangle(x, y, btnW, btnH);
                int idx = _buttonDefs.Length + defs.Count;
                PaintButton(g, r, font, def.Label, alpha, idx == _hoverButtonIndex, scale);
                rects.Add(r);
                defs.Add(def);
                x += btnW + gap;
            }
            AppendButtonRects(rects, defs);
        }

        private static int ExpandedToolbarHeight(float scale)
        {
            return Px(ToolbarPadTop, scale)
                + Px(ToolbarButtonH, scale) * 3
                + Px(ToolbarRowGap, scale) * 2
                + Px(ToolbarPadBottom, scale);
        }

        private void PaintRow1(Graphics g, int row1H, float scale, Font fpsFont, Font textFont, Font monoFont)
        {
            List<Rectangle> rects = new List<Rectangle>();
            List<NotchButtonDef> defs = new List<NotchButtonDef>();
            _buttonRects = new Rectangle[0];
            _buttonDefs = new NotchButtonDef[0];

            int x = Px(RowPadX, scale);
            int centerY = row1H / 2;
            if (!_gameReady)
            {
                _sparklineRect = Rectangle.Empty;
                _expandButtonRect = Rectangle.Empty;
                int bx = x;
                int gap = Px(Row1RightGap, scale);
                for (int i = 0; i < Row1Buttons.Length; i++)
                {
                    NotchButtonDef def = Row1Buttons[i];
                    if (!ShouldShowButton(def)) continue;
                    int btnW = MeasureButtonWidth(g, textFont, def.Label, scale);
                    Rectangle r = new Rectangle(bx, (row1H - Px(ToolbarButtonH, scale)) / 2, btnW, Px(ToolbarButtonH, scale));
                    int idx = defs.Count;
                    PaintButton(g, r, textFont, def.Label, (byte)220, idx == _hoverButtonIndex, scale);
                    rects.Add(r);
                    defs.Add(def);
                    bx += btnW + gap;
                }
                _buttonRects = rects.ToArray();
                _buttonDefs = defs.ToArray();
                return;
            }
            if (_gameReady)
            {
                int goldW = ComputeCurrencyWidth(_gold, scale);
                Rectangle goldRect = new Rectangle(x, 0, goldW, row1H);
                DrawCurrencyPanel(g, goldRect, "$", _gold, Color.FromArgb(255, 215, 0), monoFont, true, scale);
                x += goldW;
                DrawDivider(g, x, row1H, scale);
                x += Px(DividerW + DividerMarginX * 2, scale);
            }

            string fpsText = _fpsBuffer.HasData ? ((int)_fpsBuffer.Latest).ToString() : "--";
            Color fpsColor = GetFpsColor(_fpsBuffer.HasData ? _fpsBuffer.Latest : 0f);
            int fpsW = Px(CenterFpsMinW, scale);
            Rectangle fpsRect = new Rectangle(x, 0, fpsW, row1H);
            using (SolidBrush fpsBrush = new SolidBrush(fpsColor))
            using (StringFormat sf = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center })
                g.DrawString(fpsText, fpsFont, fpsBrush, fpsRect, sf);
            x += fpsW + Px(CenterGap, scale);

            int sparkW = Px(SparklineW, scale);
            int sparkH = Px(SparklineH, scale);
            int sparkY = (row1H - sparkH) / 2;
            _sparklineRect = new Rectangle(x, sparkY, sparkW, sparkH);
            DrawLightBackground(g, x, sparkY, sparkW, sparkH);
            DrawAudioEnvelope(g, _sparklineRect);
            DrawSparkline(g, x, sparkY, sparkW, sparkH, fpsColor);
            x += sparkW + Px(CenterGap + 1, scale);

            int clockSize = Px(16, scale);
            DrawClock(g, x + clockSize / 2, centerY, clockSize / 2, _fpsBuffer.GameHour);
            x += clockSize + Px(CenterGap, scale);

            using (SolidBrush arrowBrush = new SolidBrush(Color.FromArgb(128, 255, 255, 255)))
            using (StringFormat sf = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center })
            {
                Rectangle arrowRect = new Rectangle(x, 0, Px(ArrowW, scale), row1H);
                _expandButtonRect = arrowRect;
                g.DrawString("▼", textFont, arrowBrush, arrowRect, sf);
            }
            x += Px(ArrowW, scale);

            if (_gameReady)
            {
                DrawDivider(g, x, row1H, scale);
                x += Px(DividerW + DividerMarginX * 2, scale);
                int kpW = ComputeCurrencyWidth(_kp, scale);
                Rectangle kpRect = new Rectangle(x, 0, kpW, row1H);
                DrawCurrencyPanel(g, kpRect, "K", _kp, Color.FromArgb(102, 204, 255), monoFont, false, scale);
                x += kpW;
            }

            _buttonRects = rects.ToArray();
            _buttonDefs = defs.ToArray();
        }

        private void DrawOtherMenu(Graphics g, int totalW, int y, float scale, Font font)
        {
            int btnH = Px(ToolbarButtonH, scale);
            int gap = Px(1, scale);
            int pad = Px(4, scale);
            NotchButtonDef[] activeButtons = GetActiveOtherButtons();
            int menuW = Px(210, scale);
            for (int i = 0; i < activeButtons.Length; i++)
                menuW = Math.Max(menuW, MeasureButtonWidth(g, font, activeButtons[i].Label, scale) + pad * 2);
            menuW = Math.Min(menuW, Math.Max(Px(120, scale), totalW - Px(RowPadX * 2, scale)));
            int x = totalW - Px(RowPadX, scale) - menuW;
            int menuH = OtherMenuHeight(scale);
            NativeHudTheme.DrawPanel(g, new Rectangle(x, y, menuW, menuH), scale,
                NativeHudTheme.PanelFillDense, Color.Empty, true);

            List<Rectangle> rects = new List<Rectangle>();
            List<NotchButtonDef> defs = new List<NotchButtonDef>();
            int innerX = x + pad;
            int innerW = menuW - pad * 2;
            int tabY = y + pad;
            int tabW = Math.Max(1, innerW / OtherGroupButtons.Length);
            for (int i = 0; i < OtherGroupButtons.Length; i++)
            {
                int tabX = innerX + i * tabW;
                int width = i == OtherGroupButtons.Length - 1 ? x + menuW - pad - tabX : tabW;
                Rectangle r = new Rectangle(tabX, tabY, width, btnH);
                int idx = _buttonDefs.Length + defs.Count;
                PaintButton(g, r, font, OtherGroupButtons[i].Label, 230, idx == _hoverButtonIndex, scale);
                if (i == _otherMenuGroupIndex)
                {
                    using (SolidBrush accent = new SolidBrush(NativeHudTheme.Cyan))
                        g.FillRectangle(accent, r.X + Px(3, scale), r.Bottom - Px(2, scale),
                            Math.Max(1, r.Width - Px(6, scale)), Px(2, scale));
                }
                rects.Add(r);
                defs.Add(OtherGroupButtons[i]);
            }

            int itemY = tabY + btnH + Px(3, scale);
            for (int i = 0; i < activeButtons.Length; i++)
            {
                if (!ShouldShowButton(activeButtons[i])) continue;
                Rectangle r = new Rectangle(innerX, itemY, innerW, btnH);
                int idx = _buttonDefs.Length + defs.Count;
                PaintButton(g, r, font, activeButtons[i].Label, 230, idx == _hoverButtonIndex, scale);
                rects.Add(r);
                defs.Add(activeButtons[i]);
                itemY += btnH + gap;
            }
            AppendButtonRects(rects, defs);
        }

        private NotchButtonDef[] GetActiveOtherButtons()
        {
            if (_otherMenuGroupIndex < 0 || _otherMenuGroupIndex >= OtherButtonGroups.Length)
                _otherMenuGroupIndex = 0;
            return OtherButtonGroups[_otherMenuGroupIndex];
        }

        private int OtherMenuHeight(float scale)
        {
            int count = CountVisibleButtons(GetActiveOtherButtons());
            int btnH = Px(ToolbarButtonH, scale);
            int gap = Px(1, scale);
            return Px(4 + 3 + 4, scale) + btnH + count * btnH + Math.Max(0, count - 1) * gap;
        }

        private void CloseOtherMenu()
        {
            _otherMenuOpen = false;
            _otherMenuGroupIndex = 0;
        }

        private void AppendButtonRects(List<Rectangle> rects, List<NotchButtonDef> defs)
        {
            if (rects == null || defs == null || rects.Count == 0) return;
            int oldLen = _buttonRects != null ? _buttonRects.Length : 0;
            Rectangle[] nextRects = new Rectangle[oldLen + rects.Count];
            NotchButtonDef[] nextDefs = new NotchButtonDef[oldLen + defs.Count];
            if (oldLen > 0)
            {
                Array.Copy(_buttonRects, nextRects, oldLen);
                Array.Copy(_buttonDefs, nextDefs, oldLen);
            }
            for (int i = 0; i < rects.Count; i++)
            {
                nextRects[oldLen + i] = rects[i];
                nextDefs[oldLen + i] = defs[i];
            }
            _buttonRects = nextRects;
            _buttonDefs = nextDefs;
        }

        private void PaintButton(Graphics g, Rectangle r, Font font, string text, byte alpha, bool hover, float scale)
        {
            NativeHudTheme.DrawButton(g, r, scale, hover, false, false, false);
            using (SolidBrush fg = new SolidBrush(hover
                ? NativeHudTheme.WithAlpha(NativeHudTheme.TextPrimary, alpha)
                : NativeHudTheme.WithAlpha(NativeHudTheme.TextSecondary, (byte)(alpha * 0.9f))))
            using (StringFormat sf = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center, Trimming = StringTrimming.EllipsisCharacter })
            {
                g.DrawString(text, font, fg, r, sf);
            }
        }

        private void DrawDivider(Graphics g, int x, int rowH, float scale)
        {
            int hh = Px(18, scale);
            NativeHudTheme.DrawSeparator(g, x + Px(DividerMarginX, scale),
                (rowH - hh) / 2, (rowH + hh) / 2, scale);
        }

        private void DrawCurrencyPanel(Graphics g, Rectangle rect, string icon, CurrencySlot slot, Color accent, Font font, bool leftAlign, float scale)
        {
            int iconW = Px(CurrencyIconW, scale);
            Rectangle iconR = leftAlign
                ? new Rectangle(rect.X, (rect.Height - Px(18, scale)) / 2, iconW, Px(18, scale))
                : new Rectangle(rect.Right - iconW, (rect.Height - Px(18, scale)) / 2, iconW, Px(18, scale));
            Rectangle valR = leftAlign
                ? new Rectangle(iconR.Right + Px(CurrencyGap, scale), 0, rect.Right - iconR.Right - Px(CurrencyGap, scale), rect.Height)
                : new Rectangle(rect.X, 0, iconR.X - rect.X - Px(CurrencyGap, scale), rect.Height);
            using (SolidBrush iconBg = new SolidBrush(Color.FromArgb(38, accent)))
            using (SolidBrush iconFg = new SolidBrush(accent))
            using (SolidBrush valFg = new SolidBrush(NativeHudTheme.TextPrimary))
            using (StringFormat center = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center })
            using (StringFormat valueFmt = new StringFormat { Alignment = leftAlign ? StringAlignment.Near : StringAlignment.Far, LineAlignment = StringAlignment.Center })
            {
                g.FillRectangle(iconBg, iconR);
                using (Pen iconFrame = new Pen(NativeHudTheme.FrameNormal, NativeHudTheme.StrokePx(scale)))
                    g.DrawRectangle(iconFrame, iconR.X, iconR.Y, Math.Max(0, iconR.Width - 1), Math.Max(0, iconR.Height - 1));
                g.DrawString(icon, font, iconFg, iconR, center);
                g.DrawString(FormatNumber(slot.Current), font, valFg, valR, valueFmt);
            }
        }

        private static int Px(int basePx, float scale) { return Math.Max(1, (int)Math.Round(basePx * scale)); }
        private static float Pxf(float basePx, float scale) { return Math.Max(1f, basePx * scale); }
        private static float GetScale(float viewportH)
        {
            if (viewportH <= 0) return 1f;
            return Math.Max(0.5f, viewportH / 576f);
        }

        private static Font CreateInfoRowFont(bool isGame, float scale)
        {
            float basePx = isGame ? 13f : 12f;
            FontStyle style = isGame ? FontStyle.Bold : FontStyle.Regular;
            return NativeHudFonts.CreateUiFont(Pxf(basePx, scale), style, GraphicsUnit.Pixel);
        }

        private static bool ShouldStartHoverExpand(bool canHoverExpand, int expandCooldownMs)
        {
            return canHoverExpand && expandCooldownMs <= 0;
        }

        private int ComputeCollapsedWidth(float scale)
        {
            int center = Px(CenterFpsMinW + CenterGap + SparklineW + CenterGap + 1 + 16 + CenterGap + ArrowW, scale);
            int w = Px(RowPadX * 2, scale) + center;
            if (_gameReady)
            {
                w += ComputeCurrencyWidth(_gold, scale);
                w += ComputeCurrencyWidth(_kp, scale);
                w += Px((DividerW + DividerMarginX * 2) * 2, scale);
            }
            else
            {
                w = Px(RowPadX * 2, scale) + MeasureButtonsApprox(Row1Buttons, scale);
            }
            return w;
        }

        private int ComputeExpandedWidth(float scale, Rectangle viewport)
        {
            int collapsed = ComputeCollapsedWidth(scale);
            int toolbar = _gameReady
                ? Math.Max(
                    MeasureToolbarRowApprox(ToolbarButtons, scale),
                    Math.Max(
                        MeasureToolbarRowApprox(ToolbarUtilityButtons, scale),
                        MeasureToolbarRowApprox(Row1Buttons, scale)))
                : 0;
            int desired = Math.Max(collapsed, toolbar);
            if (_chartVisible) desired = Math.Max(desired, Px(ExpandedChartW, scale));
            desired = Math.Max(desired, collapsed);
            int max = RightHudLayout.SafeNotchMaxWidthFromViewport(viewport, scale, collapsed);
            return Math.Min(Math.Max(desired, collapsed), Math.Max(collapsed, max));
        }

        private int MeasureToolbarRowApprox(NotchButtonDef[] defs, float scale)
        {
            int count = CountVisibleButtons(defs);
            return Px(ToolbarPadX * 2 + ToolbarGroupLabelW, scale)
                + MeasureButtonsApprox(defs, scale)
                + Px(ToolbarButtonGap * Math.Max(0, count - 1), scale);
        }

        private static int ExpandedChartHeight(float scale)
        {
            return Px(ExpandedChartPad * 2 + ExpandedChartCanvasH + ExpandedChartHintGap + ExpandedChartHintH, scale);
        }

        private int ComputeCurrencyWidth(CurrencySlot slot, float scale)
        {
            int chars = 6;
            if (slot != null)
            {
                chars = Math.Max(chars, FormatNumber(slot.Current).Length);
                chars = Math.Max(chars, FormatNumber(slot.Target).Length);
                chars = Math.Max(chars, FormatNumber(slot.From).Length);
            }
            int valueW = Math.Max(Px(CurrencyMinValueW, scale), Px(chars * 8, scale));
            return Px(CurrencyIconW + CurrencyGap, scale) + valueW;
        }

        private int MeasureButtonsApprox(NotchButtonDef[] defs, float scale)
        {
            if (defs == null) return 0;
            int wsum = 0;
            for (int i = 0; i < defs.Length; i++)
            {
                if (!ShouldShowButton(defs[i])) continue;
                wsum += Px(ButtonPadX * 2 + Math.Max(28, defs[i].Label.Length * 14 + 4), scale);
            }
            return wsum;
        }

        private int CountVisibleButtons(NotchButtonDef[] defs)
        {
            if (defs == null) return 0;
            int count = 0;
            for (int i = 0; i < defs.Length; i++)
                if (ShouldShowButton(defs[i])) count++;
            return count;
        }

        private int MeasureButtonWidth(Graphics g, Font font, string text, float scale)
        {
            SizeF size = g.MeasureString(text, font);
            return Math.Max(Px(36, scale), (int)Math.Ceiling(size.Width) + Px(ButtonPadX * 2, scale));
        }

        private bool ShouldShowButton(NotchButtonDef def)
        {
            if (def == null) return false;
            if (def.RequiresGameReady && !_gameReady) return false;
            if (def.RequiresWarehouse && _questProgress <= 13) return false;
            return true;
        }

        private Color ResolvePillColor()
        {
            int hour = ((int)Math.Floor(_fpsBuffer.GameHour)) % 24;
            int level = (_lightLevels != null && _lightLevels.Length >= 24) ? _lightLevels[hour] : 7;
            if (level >= 7)
                return NativeHudTheme.Blend(NativeHudTheme.PanelFill, Color.FromArgb(48, 48, 44), 0.08f, 218);
            if (level >= 4)
                return NativeHudTheme.Blend(NativeHudTheme.PanelFill, Color.FromArgb(54, 42, 28), 0.08f, 228);
            return NativeHudTheme.Blend(NativeHudTheme.PanelFillDense, Color.FromArgb(24, 32, 48), 0.10f, 238);
        }

        private static void StartCurrencyUpdate(CurrencySlot slot, int value, int deltaOverride)
        {
            if (slot == null) return;
            int old = slot.Target;
            if (value == old && !slot.Animating) return;
            slot.From = slot.Animating ? slot.Current : old;
            slot.Target = value;
            slot.AnimElapsedMs = 0;
            slot.Animating = true;
            int delta = deltaOverride == int.MinValue ? value - old : deltaOverride;
            if (delta != 0)
            {
                slot.LastDelta = delta;
                slot.DeltaElapsedMs = 0;
            }
        }

        private static bool TickCurrencySlot(CurrencySlot slot, int deltaMs)
        {
            if (slot == null) return false;
            bool changed = false;
            if (slot.Animating)
            {
                slot.AnimElapsedMs += deltaMs;
                float t = Math.Min(1f, slot.AnimElapsedMs / 600f);
                float eased = 1f - (float)Math.Pow(1 - t, 3);
                int next = slot.From + (int)Math.Round((slot.Target - slot.From) * eased);
                if (next != slot.Current) { slot.Current = next; changed = true; }
                if (t >= 1f)
                {
                    slot.Animating = false;
                    slot.Current = slot.Target;
                    changed = true;
                }
            }
            if (slot.DeltaElapsedMs < 1200)
            {
                slot.DeltaElapsedMs += deltaMs;
                changed = true;
            }
            return changed;
        }

        private static string StripPrefix(string fullPiece, string key)
        {
            if (string.IsNullOrEmpty(fullPiece)) return "";
            string prefix = key + ":";
            if (fullPiece.StartsWith(prefix, StringComparison.Ordinal)) return fullPiece.Substring(prefix.Length);
            return fullPiece;
        }

        private static int ParseInt(string raw, int fallback)
        {
            int n;
            if (int.TryParse(raw, out n)) return n;
            return fallback;
        }

        private static string FormatNumber(int n)
        {
            string s = Math.Abs(n).ToString("N0", System.Globalization.CultureInfo.InvariantCulture);
            return n < 0 ? "-" + s : s;
        }

        private void DrawLightBackground(Graphics g, int x, int y, int w, int h)
        {
            if (_lightLevels == null || _lightLevels.Length < 24) return;

            float gameHour = _fpsBuffer.GameHour;
            int startHour = (int)gameHour;
            int points = SparklinePoints;
            float stepX = (float)w / points;
            float stepH = (float)h / MaxLightLevel;

            PointF[] poly = new PointF[points + 2];
            poly[0] = new PointF(x, y + h);
            for (int i = 0; i < points; i++)
            {
                int hourIdx = (startHour + i) % 24;
                float ly = y + h - _lightLevels[hourIdx] * stepH;
                poly[i + 1] = new PointF(x + i * stepX, ly);
            }
            poly[points + 1] = new PointF(x + (points - 1) * stepX, y + h);

            using (SolidBrush brush = new SolidBrush(Color.FromArgb(100, 180, 160, 60)))
                g.FillPolygon(brush, poly);
            PointF[] outline = new PointF[points];
            Array.Copy(poly, 1, outline, 0, points);
            using (Pen outlinePen = new Pen(Color.FromArgb(140, 200, 180, 70), 1f))
                g.DrawLines(outlinePen, outline);
        }

        private void DrawAudioEnvelope(Graphics g, Rectangle area)
        {
            if (_audioHudState == null || _audioHudState.DisableVisualizers || !_audioHudState.HasSamples) return;
            if (area.Width <= 0 || area.Height <= 0) return;

            int count = _audioHudState.SampleCount;
            float stepX = (float)area.Width / Math.Max(1, count);
            float midY = area.Y + area.Height / 2f;
            float maxHalfH = Math.Max(1f, area.Height / 2f - 1f);
            int alpha = _audioHudState.IsPlaying ? 48 : 18;
            using (SolidBrush leftBrush = new SolidBrush(Color.FromArgb(alpha, 82, 172, 220)))
            using (SolidBrush rightBrush = new SolidBrush(Color.FromArgb(Math.Max(10, alpha - 10), 120, 202, 238)))
            {
                for (int i = 0; i < count; i++)
                {
                    float left, right;
                    _audioHudState.GetSample(i, out left, out right);
                    float x = area.X + i * stepX;
                    float barW = Math.Max(1f, stepX - 0.5f);
                    float leftH = Math.Max(0.5f, left * maxHalfH);
                    float rightH = Math.Max(0.5f, right * maxHalfH);
                    g.FillRectangle(leftBrush, x, midY - leftH, barW, leftH);
                    g.FillRectangle(rightBrush, x, midY, barW, rightH);
                }
            }
        }

        private void DrawSparkline(Graphics g, int x, int y, int w, int h, Color lineColor)
        {
            if (!_fpsBuffer.HasData)
            {
                using (Pen grayPen = new Pen(Color.FromArgb(60, 255, 255, 255), 1))
                    g.DrawLine(grayPen, x, y + h / 2, x + w, y + h / 2);
                return;
            }

            int count = _fpsBuffer.Count;
            int points = Math.Min(SparklinePoints, count);
            if (points < 2) return;

            int startIdx = count - points;
            float localMin = float.MaxValue;
            float localMax = float.MinValue;
            for (int i = 0; i < points; i++)
            {
                float v = _fpsBuffer.GetAt(startIdx + i);
                if (v < localMin) localMin = v;
                if (v > localMax) localMax = v;
            }
            float range = localMax - localMin;
            if (range < 5f) range = 5f;

            PointF[] linePoints = new PointF[points];
            float stepX = (float)w / (points - 1);
            for (int i = 0; i < points; i++)
            {
                float v = _fpsBuffer.GetAt(startIdx + i);
                float normalY = 1f - (v - localMin) / range;
                linePoints[i] = new PointF(x + i * stepX, y + normalY * h);
            }

            using (Pen linePen = new Pen(Color.FromArgb(180, lineColor.R, lineColor.G, lineColor.B), 1.5f))
                g.DrawLines(linePen, linePoints);
        }

        private struct FpsChartScale { public float MinV; public float MaxV; public float Range; }
        private struct FpsChartStats { public float Lo, Hi, Avg, P1Low, P5Low; }

        private void DrawExpandedChart(Graphics g, Rectangle panel, float scale, Font labelFont, Font hintFont)
        {
            _expandedChartRect = panel;

            NativeHudTheme.DrawPanel(g, panel, scale, NativeHudTheme.PanelFillDense,
                NativeHudTheme.Cyan, true);

            int pad = Px(ExpandedChartPad, scale);
            int hintGap = Px(ExpandedChartHintGap, scale);
            int hintH = Px(ExpandedChartHintH, scale);
            Rectangle canvas = new Rectangle(
                panel.X + pad,
                panel.Y + pad,
                Math.Max(1, panel.Width - pad * 2),
                Math.Max(1, panel.Height - pad * 2 - hintGap - hintH));

            NativeHudTheme.DrawPanel(g, canvas, scale, Color.FromArgb(188, 0, 0, 0),
                Color.Empty, false);

            DrawLightBackground(g, canvas.X, canvas.Y, canvas.Width, canvas.Height);

            float[] history = GetExpandedHistory();
            if (history.Length < 2)
            {
                using (SolidBrush waitBrush = new SolidBrush(Color.FromArgb(90, 255, 255, 255)))
                using (StringFormat sf = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center })
                    g.DrawString("等待数据...", labelFont, waitBrush, canvas, sf);
            }
            else
            {
                FpsChartScale chartScale = ComputeFpsChartScale(history);
                FpsChartStats stats = ComputeFpsStats(history);
                PointF[] points = BuildChartPoints(history, canvas, chartScale);

                DrawExpandedZones(g, canvas, chartScale);
                DrawExpandedArea(g, points, canvas);
                DrawExpandedSegments(g, points, history, scale);
                DrawEndGlow(g, points[points.Length - 1], history[history.Length - 1], scale);

                DrawAnnotation(g, canvas, chartScale, stats.Avg, "avg " + stats.Avg.ToString("0.0", System.Globalization.CultureInfo.InvariantCulture),
                    Color.FromArgb(150, 180, 180, 180), new float[] { 4f, 4f }, labelFont);
                DrawAnnotation(g, canvas, chartScale, stats.P5Low, "5% low " + stats.P5Low.ToString("0.0", System.Globalization.CultureInfo.InvariantCulture),
                    Color.FromArgb(140, 255, 180, 0), new float[] { 3f, 3f }, labelFont);
                DrawAnnotation(g, canvas, chartScale, stats.P1Low, "1% low " + stats.P1Low.ToString("0.0", System.Globalization.CultureInfo.InvariantCulture),
                    Color.FromArgb(140, 255, 80, 80), new float[] { 2f, 2f }, labelFont);

                string statText = history.Length.ToString(System.Globalization.CultureInfo.InvariantCulture)
                    + " samples | lo:" + stats.Lo.ToString("0.0", System.Globalization.CultureInfo.InvariantCulture)
                    + " hi:" + stats.Hi.ToString("0.0", System.Globalization.CultureInfo.InvariantCulture);
                Rectangle statRect = new Rectangle(canvas.X + Px(4, scale), canvas.Bottom - Px(14, scale), canvas.Width - Px(8, scale), Px(12, scale));
                using (SolidBrush statBrush = new SolidBrush(Color.FromArgb(128, 255, 255, 255)))
                using (StringFormat sf = new StringFormat { Alignment = StringAlignment.Far, LineAlignment = StringAlignment.Far })
                    g.DrawString(statText, labelFont, statBrush, statRect, sf);
            }

            Rectangle hintRect = new Rectangle(panel.X, canvas.Bottom + hintGap, panel.Width, hintH);
            using (SolidBrush hintBrush = new SolidBrush(Color.FromArgb(90, 255, 255, 255)))
            using (StringFormat sf = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center })
                g.DrawString("点击关闭", hintFont, hintBrush, hintRect, sf);
        }

        private float[] GetExpandedHistory()
        {
            if (_fpsBuffer == null || !_fpsBuffer.HasData) return new float[0];
            int count = _fpsBuffer.Count;
            int points = Math.Min(ExpandedChartMaxHistory, count);
            if (points <= 0) return new float[0];
            int start = count - points;
            float[] history = new float[points];
            for (int i = 0; i < points; i++)
                history[i] = _fpsBuffer.GetAt(start + i);
            return history;
        }

        private static PointF[] BuildChartPoints(float[] history, Rectangle canvas, FpsChartScale chartScale)
        {
            PointF[] points = new PointF[history.Length];
            float stepX = history.Length > 1 ? (float)canvas.Width / (history.Length - 1) : 0f;
            for (int i = 0; i < history.Length; i++)
                points[i] = new PointF(canvas.X + i * stepX, FpsChartY(history[i], canvas, chartScale));
            return points;
        }

        private static FpsChartScale ComputeFpsChartScale(float[] points)
        {
            FpsChartScale chartScale = new FpsChartScale();
            if (points == null || points.Length == 0)
            {
                chartScale.MinV = 0f;
                chartScale.MaxV = ExpandedChartMinDiff;
                chartScale.Range = ExpandedChartMinDiff;
                return chartScale;
            }
            float minV = points[0];
            float maxV = points[0];
            for (int i = 1; i < points.Length; i++)
            {
                if (points[i] < minV) minV = points[i];
                if (points[i] > maxV) maxV = points[i];
            }
            if (maxV - minV < ExpandedChartMinDiff)
            {
                float delta = (ExpandedChartMinDiff - (maxV - minV)) / 2f;
                minV -= delta;
                maxV += delta;
            }
            float range = maxV - minV;
            if (range < 1f) range = 1f;
            chartScale.MinV = minV;
            chartScale.MaxV = maxV;
            chartScale.Range = range;
            return chartScale;
        }

        private static FpsChartStats ComputeFpsStats(float[] points)
        {
            FpsChartStats stats = new FpsChartStats();
            if (points == null || points.Length == 0) return stats;

            float sum = 0f;
            float lo = points[0];
            float hi = points[0];
            for (int i = 0; i < points.Length; i++)
            {
                float v = points[i];
                sum += v;
                if (v < lo) lo = v;
                if (v > hi) hi = v;
            }

            float[] sorted = new float[points.Length];
            Array.Copy(points, sorted, points.Length);
            Array.Sort(sorted);
            int p1Count = Math.Max(1, (int)Math.Floor(points.Length * 0.01f));
            int p5Count = Math.Max(1, (int)Math.Floor(points.Length * 0.05f));
            float p1Sum = 0f;
            float p5Sum = 0f;
            for (int i = 0; i < p5Count; i++)
            {
                p5Sum += sorted[i];
                if (i < p1Count) p1Sum += sorted[i];
            }

            stats.Lo = lo;
            stats.Hi = hi;
            stats.Avg = sum / points.Length;
            stats.P1Low = p1Sum / p1Count;
            stats.P5Low = p5Sum / p5Count;
            return stats;
        }

        private static float FpsChartY(float fps, Rectangle canvas, FpsChartScale chartScale)
        {
            return canvas.Bottom - ((fps - chartScale.MinV) / chartScale.Range) * canvas.Height;
        }

        private static void DrawExpandedZones(Graphics g, Rectangle canvas, FpsChartScale chartScale)
        {
            float dangerY = FpsChartY(ExpandedChartDangerFps, canvas, chartScale);
            if (dangerY < canvas.Bottom)
            {
                int y = (int)Math.Max(canvas.Top, Math.Round(dangerY));
                using (SolidBrush dangerFill = new SolidBrush(Color.FromArgb(26, 255, 50, 50)))
                    g.FillRectangle(dangerFill, canvas.X, y, canvas.Width, canvas.Bottom - y);
                DrawDashedHLine(g, canvas, dangerY, Color.FromArgb(64, 255, 80, 80), new float[] { 2f, 3f });
            }
            float targetY = FpsChartY(ExpandedChartTargetFps, canvas, chartScale);
            if (targetY > canvas.Top && targetY < canvas.Bottom)
                DrawDashedHLine(g, canvas, targetY, Color.FromArgb(46, 102, 255, 102), new float[] { 3f, 4f });
        }

        private static void DrawDashedHLine(Graphics g, Rectangle canvas, float y, Color color, float[] dash)
        {
            using (Pen pen = new Pen(color, 1f))
            {
                pen.DashPattern = dash;
                g.DrawLine(pen, canvas.X, y, canvas.Right, y);
            }
        }

        private static void DrawExpandedArea(Graphics g, PointF[] points, Rectangle canvas)
        {
            if (points == null || points.Length < 2) return;
            using (GraphicsPath path = new GraphicsPath())
            {
                path.AddLines(points);
                path.AddLine(points[points.Length - 1].X, points[points.Length - 1].Y, points[points.Length - 1].X, canvas.Bottom);
                path.AddLine(points[points.Length - 1].X, canvas.Bottom, points[0].X, canvas.Bottom);
                path.CloseFigure();
                using (LinearGradientBrush grad = new LinearGradientBrush(canvas,
                    Color.FromArgb(60, 100, 255, 100),
                    Color.FromArgb(8, 255, 50, 50),
                    LinearGradientMode.Vertical))
                    g.FillPath(grad, path);
            }
        }

        private static void DrawExpandedSegments(Graphics g, PointF[] points, float[] history, float scale)
        {
            if (points == null || history == null || points.Length < 2) return;
            for (int i = 1; i < points.Length; i++)
            {
                float fps = (history[i - 1] + history[i]) / 2f;
                Color c = GetFpsColor(fps);
                using (Pen pen = new Pen(Color.FromArgb(220, c.R, c.G, c.B), Pxf(1.5f, scale)))
                {
                    pen.StartCap = LineCap.Round;
                    pen.EndCap = LineCap.Round;
                    g.DrawLine(pen, points[i - 1], points[i]);
                }
            }
        }

        private static void DrawEndGlow(Graphics g, PointF point, float fps, float scale)
        {
            Color c = GetFpsColor(fps);
            float r = Pxf(2.5f, scale);
            using (SolidBrush glow = new SolidBrush(Color.FromArgb(120, c.R, c.G, c.B)))
                g.FillEllipse(glow, point.X - r, point.Y - r, r * 2f, r * 2f);
        }

        private static void DrawAnnotation(Graphics g, Rectangle canvas, FpsChartScale chartScale, float fps,
            string label, Color color, float[] dash, Font font)
        {
            float y = FpsChartY(fps, canvas, chartScale);
            if (y < canvas.Top + 2 || y > canvas.Bottom - 2) return;
            using (Pen pen = new Pen(color, 1f))
            using (SolidBrush brush = new SolidBrush(color))
            {
                pen.DashPattern = dash;
                g.DrawLine(pen, canvas.X, y, canvas.Right, y);
                RectangleF labelRect = new RectangleF(canvas.X + 3f, y - font.GetHeight(g) - 2f, canvas.Width - 6f, font.GetHeight(g) + 2f);
                using (StringFormat sf = new StringFormat { Alignment = StringAlignment.Near, LineAlignment = StringAlignment.Far })
                    g.DrawString(label, font, brush, labelRect, sf);
            }
        }

        private static void DrawClock(Graphics g, int cx, int cy, int radius, float gameHour)
        {
            float hour12 = gameHour % 12f;
            int hourInt = ((int)gameHour) % 24;

            Color faceColor, rimColor, handColor;
            if (hourInt >= 5 && hourInt <= 17)
            {
                faceColor = Color.FromArgb(50, 180, 170, 100);
                rimColor = Color.FromArgb(180, 200, 190, 120);
                handColor = Color.FromArgb(220, 240, 230, 160);
            }
            else if ((hourInt >= 3 && hourInt <= 4) || (hourInt >= 18 && hourInt <= 20))
            {
                faceColor = Color.FromArgb(50, 200, 140, 60);
                rimColor = Color.FromArgb(160, 220, 160, 80);
                handColor = Color.FromArgb(200, 240, 180, 100);
            }
            else
            {
                faceColor = Color.FromArgb(40, 100, 120, 180);
                rimColor = Color.FromArgb(140, 130, 150, 200);
                handColor = Color.FromArgb(180, 160, 180, 220);
            }

            using (SolidBrush faceBrush = new SolidBrush(faceColor))
                g.FillEllipse(faceBrush, cx - radius, cy - radius, radius * 2, radius * 2);
            using (Pen rimPen = new Pen(rimColor, 1.2f))
                g.DrawEllipse(rimPen, cx - radius, cy - radius, radius * 2, radius * 2);

            float hourAngle = (hour12 / 12f) * 360f - 90f;
            float hourRad = hourAngle * (float)Math.PI / 180f;
            float hourLen = radius * 0.5f;
            using (Pen hourPen = new Pen(handColor, 2f))
            {
                hourPen.StartCap = LineCap.Round;
                hourPen.EndCap = LineCap.Round;
                g.DrawLine(hourPen, cx, cy,
                    cx + (float)Math.Cos(hourRad) * hourLen,
                    cy + (float)Math.Sin(hourRad) * hourLen);
            }

            float minuteFrac = gameHour - (float)Math.Floor(gameHour);
            float minAngle = minuteFrac * 360f - 90f;
            float minRad = minAngle * (float)Math.PI / 180f;
            float minLen = radius * 0.8f;
            using (Pen minPen = new Pen(handColor, 1f))
            {
                minPen.StartCap = LineCap.Round;
                minPen.EndCap = LineCap.Round;
                g.DrawLine(minPen, cx, cy,
                    cx + (float)Math.Cos(minRad) * minLen,
                    cy + (float)Math.Sin(minRad) * minLen);
            }
            using (SolidBrush dotBrush = new SolidBrush(handColor))
                g.FillEllipse(dotBrush, cx - 1, cy - 1, 3, 3);
        }

        private static Color GetFpsColor(float fps)
        {
            if (fps >= FpsGreenThreshold) return Color.FromArgb(0, 255, 100);
            if (fps >= FpsYellowThreshold) return Color.FromArgb(255, 220, 0);
            return Color.FromArgb(255, 60, 60);
        }

        #endregion

        private static int[] LoadLightLevels(string projectRoot)
        {
            int[] levels = new int[24];
            int[] defaults = { 0, 0, 1, 4, 7, 7, 7, 7, 7, 7, 7, 7, 9, 7, 7, 7, 7, 7, 7, 4, 1, 0, 0, 0 };
            Array.Copy(defaults, levels, 24);
            try
            {
                string xmlPath = Path.Combine(projectRoot, "config", "WeatherSystemConfig.xml");
                if (!File.Exists(xmlPath)) return levels;
                XmlDocument doc = new XmlDocument();
                doc.Load(xmlPath);
                XmlNodeList hours = doc.SelectNodes("/WeatherSystemConfig/LightLevels/Hour");
                if (hours == null) return levels;
                foreach (XmlNode node in hours)
                {
                    XmlAttribute indexAttr = node.Attributes["index"];
                    if (indexAttr == null) continue;
                    int idx;
                    if (!int.TryParse(indexAttr.Value, out idx)) continue;
                    if (idx < 0 || idx >= 24) continue;
                    int val;
                    if (int.TryParse(node.InnerText.Trim(), out val))
                        levels[idx] = val;
                }
            }
            catch (Exception ex)
            {
                LogManager.Log("[NotchWidget] Failed to load light levels: " + ex.Message);
            }
            return levels;
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

        internal string ResolveUtilityRouteForTest(int index)
        {
            if (index < 0 || index >= ToolbarUtilityButtons.Length) return null;
            return ToolbarUtilityButtons[index].CommandKey;
        }

        internal static string[] ToolbarRoutesForTest()
        {
            string[] routes = new string[ToolbarButtons.Length];
            for (int i = 0; i < ToolbarButtons.Length; i++) routes[i] = ToolbarButtons[i].CommandKey;
            return routes;
        }

        internal static int CollapsedHeightBaseForTest
        {
            get { return CollapsedH; }
        }

        internal void BeginExpandForTest()
        {
            _reserveExpandedCompositeBounds = true;
            _state = NotchState.Expanding;
            _expandProgress = 0f;
            FireBounds();
        }

        internal void BeginCollapseForTest()
        {
            _reserveExpandedCompositeBounds = true;
            _state = NotchState.Collapsing;
            _expandProgress = 1f;
            CloseOtherMenu();
        }

        internal bool HasCompositeReservationForTest { get { return _reserveExpandedCompositeBounds; } }
        internal bool IsOtherMenuOpenForTest { get { return _otherMenuOpen; } }
        internal int OtherMenuGroupIndexForTest { get { return _otherMenuGroupIndex; } }
        internal int OtherMenuItemCountForTest { get { return CountVisibleButtons(GetActiveOtherButtons()); } }
        internal void OpenOtherMenuForTest(int groupIndex)
        {
            _otherMenuOpen = true;
            _otherMenuGroupIndex = Math.Max(0, Math.Min(OtherButtonGroups.Length - 1, groupIndex));
        }
        internal void ForceGameReadyForTest(bool ready)
        {
            _gameReady = ready;
        }
        internal void ForceCurrenciesForTest(int gold, int kpoint)
        {
            _gold.Current = _gold.Target = _gold.From = gold;
            _kp.Current = _kp.Target = _kp.From = kpoint;
        }
        internal Size SizeForProgressForTest(float progress)
        {
            int width, height;
            GetSizeForProgress(progress, out width, out height);
            return new Size(width, height);
        }

        public void Dispose() { }
    }
}
