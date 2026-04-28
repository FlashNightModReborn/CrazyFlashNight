using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using System.Xml;
using CF7Launcher.Guardian.Hud;

namespace CF7Launcher.Guardian
{
    /// <summary>
    /// "刘海屏"覆盖层：顶部居中 FPS 药丸，鼠标靠近时展开为完整工具栏。
    ///
    /// 继承 OverlayBase，IsClickThrough=false（需接收鼠标事件）。
    /// 使用 TrackMouseEvent(TME_LEAVE) 检测鼠标离开。
    /// 状态机：Collapsed → Expanding → Expanded → Collapsing → Collapsed
    /// </summary>
    public class NotchOverlay : OverlayBase, INotchSink
    {
        #region Win32 (TrackMouseEvent)

        [DllImport("user32.dll")]
        private static extern bool TrackMouseEvent(ref TRACKMOUSEEVENT lpEventTrack);

        [StructLayout(LayoutKind.Sequential)]
        private struct TRACKMOUSEEVENT
        {
            public int cbSize;
            public uint dwFlags;
            public IntPtr hwndTrack;
            public int dwHoverTime;
        }

        private const uint TME_LEAVE = 0x00000002;
        private const int WM_MOUSEMOVE = 0x0200;
        private const int WM_MOUSELEAVE = 0x02A3;
        private const int WM_LBUTTONUP = 0x0202;
        private const int WM_MOUSEACTIVATE = 0x0021;
        private const int MA_NOACTIVATE = 3;

        #endregion

        #region 状态机

        private enum NotchState { Collapsed, Expanding, Expanded, Collapsing }
        private NotchState _state;

        #endregion

        #region 常量

        // 尺寸基准（Web CSS px，运行时按 Flash viewport height / 576 缩放）。
        // Web #notch-row1: height 28, padding 0 6, center=FPS + sparkline(70x16) + clock(16) + ▼。
        private const int CollapsedH = 28;
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
        private const int ToolbarButtonH = 22;
        private const int ToolbarButtonGap = 2;
        private const int ButtonPadX = 8;

        // 定时器
        private const int TickMs = 16;
        private const int AutoHideDelayMs = 500;
        private const int ExpandAnimMs = 150;
        private const int CollapseAnimMs = 200;
        private const int ExpandClickCooldownMs = 600;
        private const int StableRefreshMs = 250;

        // FPS 曲线
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

        // FPS 颜色阈值
        private const float FpsGreenThreshold = 25f;
        private const float FpsYellowThreshold = 18f;

        #endregion

        #region 字段

        private readonly FpsRingBuffer _fpsBuffer;
        private readonly System.Windows.Forms.Timer _timer;

        private class CurrencySlot
        {
            public int Current;
            public int Target;
            public int From;
            public int AnimElapsedMs;
            public bool Animating;
            public int LastDelta;
            public int DeltaElapsedMs = 1200;
        }

        private class GameNoticeQueueItem
        {
            public string Text;
            public Color Color;
            public int Count;
        }

        private class NotchButtonDef
        {
            public string Label;
            public string CommandKey;
            public Keys KeyCode;
            public bool RequiresGameReady;
            public bool RequiresWarehouse;

            public NotchButtonDef(string label, string commandKey, Keys keyCode, bool requiresGameReady, bool requiresWarehouse)
            {
                Label = label;
                CommandKey = commandKey;
                KeyCode = keyCode;
                RequiresGameReady = requiresGameReady;
                RequiresWarehouse = requiresWarehouse;
            }
        }

        // 工具栏按钮回调
        private readonly Action _onToggleFullscreen;
        private readonly Action _onToggleLog;
        private readonly Action _onForceExit;
        private readonly Action<Keys> _onSendKey;
        private LauncherCommandRouter _router;

        // 状态
        private bool _ready;
        private bool _trackingMouse;
        private float _expandProgress; // 0.0 = collapsed, 1.0 = expanded
        private int _autoHideCountdown;
        private int _expandClickCooldown;
        private int _hoverButtonIndex; // -1 = none
        private bool _gameReady;
        private int _questProgress;
        private int _stableRefreshElapsedMs;

        // 按钮定义
        private static readonly NotchButtonDef[] Row1Buttons = {
            new NotchButtonDef("全屏", "F", Keys.F, false, false),
            new NotchButtonDef("日志", "LOG", Keys.None, false, false),
            new NotchButtonDef("其他 ▸", null, Keys.None, false, false)
        };
        private static readonly NotchButtonDef[] ToolbarButtons = {
            new NotchButtonDef("战宠", "PETS", Keys.None, true, false),
            new NotchButtonDef("佣兵", "MERCS", Keys.None, true, false),
            new NotchButtonDef("平板", "TABLET", Keys.None, true, false),
            new NotchButtonDef("战备箱", "WAREHOUSE", Keys.None, true, true),
            new NotchButtonDef("商城", "SHOP", Keys.None, true, false)
        };
        private static readonly NotchButtonDef[] OtherButtons = {
            new NotchButtonDef("Q 强退", "Q", Keys.Q, false, false),
            new NotchButtonDef("W 关闭", "W", Keys.W, false, false),
            new NotchButtonDef("R 重置", "R", Keys.R, false, false),
            new NotchButtonDef("P 截图", "P", Keys.P, false, false),
            new NotchButtonDef("O 打开", "O", Keys.O, false, false),
            new NotchButtonDef("高安箱测试", "LOCKBOX_TEST", Keys.None, false, false),
            new NotchButtonDef("锁芯校准测试", "PINALIGN_TEST", Keys.None, false, false),
            new NotchButtonDef("铁枪会入侵测试", "GOBANG_TEST", Keys.None, false, false),
            new NotchButtonDef("选关测试", "STAGE_SELECT_TEST", Keys.None, false, false),
            new NotchButtonDef("烘焙图标", "BAKE", Keys.None, false, false),
            new NotchButtonDef("烘焙测试(10)", "BAKE10", Keys.None, false, false)
        };
        private Rectangle[] _buttonRects; // 在 PaintLayered 时计算
        private NotchButtonDef[] _buttonDefs;
        private bool _otherMenuOpen;
        private Rectangle _sparklineRect;
        private Rectangle _expandButtonRect;
        private Rectangle _expandedChartRect;
        private bool _chartVisible;

        private readonly CurrencySlot _gold;
        private readonly CurrencySlot _kp;

        // 渲染
        private Font _fpsFont;
        private int _currentExpandedW; // 当前展开宽度（视口宽度）

        // 光照等级（24 小时，从 WeatherSystemConfig.xml 读取）
        private readonly int[] _lightLevels;
        private const int MaxLightLevel = 9;

        // 通知栈：每条信息独占一行，同 category 替换
        private const int RowH = 20;
        private const int RowGap = 2;
        private const int MaxRows = 4;
        private const int TransientLifetimeMs = 4000;
        private const int GameTransientLifetimeMs = 3000;
        private const int GameThrottleMs = 350;
        private const int MaxGameRows = 4;
        private const int FadeInMs = 300;
        private const int FadeOutMs = 800;

        private readonly List<NotchInfoRow> _infoRows;
        private readonly List<GameNoticeQueueItem> _gameQueue;
        private int _gameThrottleRemainingMs;
        private int _gameNoticeSerial;

        #endregion

        protected override bool IsClickThrough { get { return false; } }

        public NotchOverlay(Form owner, Control anchor, FpsRingBuffer fpsBuffer,
            string projectRoot,
            Action onToggleFullscreen, Action onToggleLog,
            Action onForceExit, Action<Keys> onSendKey)
            : base(owner, anchor, 1024f, 576f)
        {
            _fpsBuffer = fpsBuffer;
            _lightLevels = LoadLightLevels(projectRoot);
            _onToggleFullscreen = onToggleFullscreen;
            _onToggleLog = onToggleLog;
            _onForceExit = onForceExit;
            _onSendKey = onSendKey;

            _ready = false;
            _trackingMouse = false;
            _state = NotchState.Collapsed;
            _expandProgress = 0f;
            _autoHideCountdown = 0;
            _expandClickCooldown = 0;
            _hoverButtonIndex = -1;
            _buttonRects = new Rectangle[0];
            _buttonDefs = new NotchButtonDef[0];
            _otherMenuOpen = false;
            _sparklineRect = Rectangle.Empty;
            _expandButtonRect = Rectangle.Empty;
            _expandedChartRect = Rectangle.Empty;
            _chartVisible = false;
            _currentExpandedW = 800;
            _infoRows = new List<NotchInfoRow>();
            _gameQueue = new List<GameNoticeQueueItem>();
            _gameThrottleRemainingMs = 0;
            _gameNoticeSerial = 0;
            _gameReady = false;
            _questProgress = 0;
            _gold = new CurrencySlot();
            _kp = new CurrencySlot();

            _fpsFont = new Font("Consolas", 13f, FontStyle.Bold);

            _timer = new System.Windows.Forms.Timer();
            _timer.Interval = TickMs;
            _timer.Tick += OnTick;
        }

        #region 公开接口

        public void SetReady()
        {
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action(SetReady));
                return;
            }
            _ready = true;
            ShowOverlay();
            _timer.Start();
            PaintLayered();
        }

        public void SetCommandRouter(LauncherCommandRouter router)
        {
            _router = router;
        }

        /// <summary>
        /// useNativeHud=true 时 Web #notch 被隐藏，金币/K点/s/q 等 UiData 由 native notch 自己消费。
        /// </summary>
        public void HandleUiData(string payload)
        {
            if (this.IsHandleCreated && this.InvokeRequired)
            {
                try { this.BeginInvoke(new Action<string>(HandleUiData), payload); } catch { }
                return;
            }

            bool repaint = false;
            string legacyType;
            string[] legacyFields;
            if (UiDataPacketParser.TryParseLegacy(payload, out legacyType, out legacyFields))
            {
                if (legacyType == "currency" && legacyFields != null && legacyFields.Length >= 2)
                {
                    string id = legacyFields[0];
                    int value = ParseInt(legacyFields[1], 0);
                    int delta = legacyFields.Length >= 3 ? ParseInt(legacyFields[2], 0) : 0;
                    if (id == "gold") { StartCurrencyUpdate(_gold, value, delta); repaint = true; }
                    else if (id == "kpoint") { StartCurrencyUpdate(_kp, value, delta); repaint = true; }
                }
            }
            else
            {
                foreach (KeyValuePair<string, string> kv in UiDataPacketParser.Parse(payload))
                {
                    string key = kv.Key;
                    string value = StripPrefix(kv.Value, key);
                    if (key == "s")
                    {
                        bool ready = value == "1";
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
                            repaint = true;
                        }
                    }
                    else if (key == "q")
                    {
                        int next = ParseInt(value, 0);
                        if (next != _questProgress) { _questProgress = next; repaint = true; }
                    }
                    else if (key == "g")
                    {
                        StartCurrencyUpdate(_gold, ParseInt(value, 0), int.MinValue);
                        repaint = true;
                    }
                    else if (key == "k")
                    {
                        StartCurrencyUpdate(_kp, ParseInt(value, 0), int.MinValue);
                        repaint = true;
                    }
                }
            }

            if (repaint && _ready) PaintLayered();
        }

        /// <summary>挂起：隐藏窗口 + 停止 timer。WebView2 恢复后调用，避免双重 UI。</summary>
        public void Suspend()
        {
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action(Suspend));
                return;
            }
            _ready = false;
            _chartVisible = false;
            _sparklineRect = Rectangle.Empty;
            _expandButtonRect = Rectangle.Empty;
            _expandedChartRect = Rectangle.Empty;
            _timer.Stop();
            DismissOverlay();
        }

        /// <summary>设置或更新状态槽位（前向兼容：无限过图计时器等）。</summary>
        /// <summary>设置或更新持久信息行（外部清除前一直在）。同 category 替换。</summary>
        public void SetStatusItem(string id, string label, string subLabel, Color accentColor)
        {
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action<string, string, string, Color>(SetStatusItem),
                    id, label, subLabel, accentColor);
                return;
            }
            string text = label;
            if (!string.IsNullOrEmpty(subLabel)) text += "  " + subLabel;
            UpsertRow(id, text, accentColor, true, 0);
        }

        /// <summary>清除持久信息行。</summary>
        public void ClearStatusItem(string id)
        {
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action<string>(ClearStatusItem), id);
                return;
            }
            RemoveRow(id);
        }

        /// <summary>添加/替换瞬态通知（同 category 替换，自动淡出）。</summary>
        public void AddNotice(string text, Color accentColor)
        {
            AddNotice("_notice", text, accentColor);
        }

        /// <summary>添加/替换指定 category 的瞬态通知。</summary>
        public void AddNotice(string category, string text, Color accentColor)
        {
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action<string, string, Color>(AddNotice),
                    category, text, accentColor);
                return;
            }
            if (string.Equals(category, "game", StringComparison.Ordinal))
            {
                AddGameNotice(text, accentColor);
                return;
            }
            UpsertRow(category, text, accentColor, false, TransientLifetimeMs);
        }

        private void AddGameNotice(string text, Color color)
        {
            string safeText = text ?? "";
            for (int i = 0; i < _gameQueue.Count; i++)
            {
                if (_gameQueue[i].Text == safeText)
                {
                    _gameQueue[i].Count++;
                    return;
                }
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
                    if (_ready) PaintLayered();
                    return;
                }
            }
            GameNoticeQueueItem item = new GameNoticeQueueItem();
            item.Text = safeText;
            item.Color = color;
            item.Count = 1;
            _gameQueue.Add(item);
            DrainGameQueue();
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
            if (_ready) PaintLayered();
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
                    if (_infoRows[i].IsGame)
                    {
                        _infoRows.RemoveAt(i);
                        gameRows--;
                        break;
                    }
                }
            }
        }

        private void UpsertRow(string category, string text, Color color, bool persistent, int lifetimeMs)
        {
            // 同 category 替换（交叉淡变）
            for (int i = 0; i < _infoRows.Count; i++)
            {
                if (_infoRows[i].Category == category)
                {
                    // 保存旧文字用于交叉淡变（仅文字实际变化时触发）
                    if (_infoRows[i].Text != text)
                    {
                        _infoRows[i].PrevText = _infoRows[i].Text;
                        _infoRows[i].PrevColor = _infoRows[i].AccentColor;
                        _infoRows[i].TransitionMs = 0;
                    }
                    _infoRows[i].Text = text;
                    _infoRows[i].AccentColor = color;
                    // 不重置 AgeMs——行本身不闪烁，只有文字交叉淡变
                    if (!persistent) _infoRows[i].RemainingMs = lifetimeMs;
                    return;
                }
            }
            // 新建
            NotchInfoRow row = new NotchInfoRow();
            row.Category = category;
            row.Text = text;
            row.AccentColor = color;
            row.Persistent = persistent;
            row.RemainingMs = persistent ? 0 : lifetimeMs;
            row.AgeMs = 0;
            _infoRows.Add(row);
            // 持久项排前，瞬态项排后
            SortRows();
            // 超出上限时挤压最旧的瞬态
            while (_infoRows.Count > MaxRows)
            {
                for (int i = _infoRows.Count - 1; i >= 0; i--)
                {
                    if (!_infoRows[i].Persistent) { _infoRows.RemoveAt(i); break; }
                }
                if (_infoRows.Count > MaxRows) break; // 全是持久的，不再删
            }
        }

        private void RemoveRow(string category)
        {
            for (int i = _infoRows.Count - 1; i >= 0; i--)
            {
                if (_infoRows[i].Category == category)
                {
                    _infoRows.RemoveAt(i);
                    break;
                }
            }
        }

        private void SortRows()
        {
            // 持久项在前，瞬态项在后（保持插入顺序内稳定）
            _infoRows.Sort(delegate(NotchInfoRow a, NotchInfoRow b)
            {
                if (a.Persistent && !b.Persistent) return -1;
                if (!a.Persistent && b.Persistent) return 1;
                return 0;
            });
        }

        #endregion

        #region WndProc + 鼠标交互

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == WM_MOUSEACTIVATE)
            {
                // 与 NativeHudOverlay 一致：点击刘海栏不抢前台，避免 GuardianForm.Deactivate
                // 触发 OverlayBase.HideOverlay 后所有 C# HUD 暂时 SW_HIDE。
                m.Result = (IntPtr)MA_NOACTIVATE;
                return;
            }

            if (m.Msg == WM_NCHITTEST)
            {
                int sx = (short)(m.LParam.ToInt32() & 0xFFFF);
                int sy = (short)(m.LParam.ToInt32() >> 16);
                Point local = this.PointToClient(new Point(sx, sy));
                if (IsInActiveRegion(local))
                {
                    m.Result = (IntPtr)1; // HTCLIENT
                    return;
                }
                m.Result = (IntPtr)HTTRANSPARENT;
                return;
            }

            if (m.Msg == WM_MOUSEMOVE)
            {
                if (!_trackingMouse)
                {
                    TRACKMOUSEEVENT tme = new TRACKMOUSEEVENT();
                    tme.cbSize = Marshal.SizeOf(typeof(TRACKMOUSEEVENT));
                    tme.dwFlags = TME_LEAVE;
                    tme.hwndTrack = this.Handle;
                    TrackMouseEvent(ref tme);
                    _trackingMouse = true;
                }

                // 展开触发
                bool canHoverExpand = _state == NotchState.Collapsed || _state == NotchState.Collapsing;
                if (ShouldStartHoverExpand(canHoverExpand, _expandClickCooldown))
                {
                    _state = NotchState.Expanding;
                }
                _autoHideCountdown = 0;

                // 按钮悬停检测
                int mx = (short)(m.LParam.ToInt32() & 0xFFFF);
                int my = (short)(m.LParam.ToInt32() >> 16);
                UpdateHoverButton(mx, my);

                base.WndProc(ref m);
                return;
            }

            if (m.Msg == WM_MOUSELEAVE)
            {
                _trackingMouse = false;
                _hoverButtonIndex = -1;
                if (_state == NotchState.Expanded || _state == NotchState.Expanding)
                {
                    _autoHideCountdown = AutoHideDelayMs;
                }
                base.WndProc(ref m);
                return;
            }

            if (m.Msg == WM_LBUTTONUP)
            {
                int cx = (short)(m.LParam.ToInt32() & 0xFFFF);
                int cy = (short)(m.LParam.ToInt32() >> 16);
                HandleClick(cx, cy);
                base.WndProc(ref m);
                return;
            }

            base.WndProc(ref m);
        }

        private bool IsInActiveRegion(Point local)
        {
            if (!_ready) return false;

            int w, h;
            GetCurrentSize(out w, out h);

            // 活动区域是当前渲染的药丸/展开矩形
            return local.X >= 0 && local.X < w && local.Y >= 0 && local.Y < h;
        }

        private void UpdateHoverButton(int localX, int localY)
        {
            _hoverButtonIndex = -1;
            for (int i = 0; i < _buttonRects.Length; i++)
            {
                if (_buttonRects[i].Contains(localX, localY))
                {
                    _hoverButtonIndex = i;
                    break;
                }
            }
        }

        private void HandleClick(int localX, int localY)
        {
            if (_chartVisible && _expandedChartRect.Contains(localX, localY))
            {
                _chartVisible = false;
                _expandedChartRect = Rectangle.Empty;
                PaintLayered();
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
                _state = NotchState.Expanded;
                _expandProgress = 1f;
                _autoHideCountdown = 0;
            }
            else
            {
                _expandedChartRect = Rectangle.Empty;
            }
            PaintLayered();
        }

        private void ToggleNotchFromExpandButton()
        {
            if (!_gameReady) return;

            bool expandedLike = _state == NotchState.Expanded
                || _state == NotchState.Expanding
                || _expandProgress > 0.01f;
            if (expandedLike)
            {
                _chartVisible = false;
                _expandedChartRect = Rectangle.Empty;
                _otherMenuOpen = false;
                _autoHideCountdown = 0;
                _expandClickCooldown = ExpandClickCooldownMs;
                _state = _expandProgress <= 0f ? NotchState.Collapsed : NotchState.Collapsing;
            }
            else
            {
                _expandClickCooldown = 0;
                _autoHideCountdown = 0;
                _state = NotchState.Expanding;
            }
            PaintLayered();
        }

        private void ExecuteButton(int index)
        {
            if (index < 0 || index >= _buttonDefs.Length) return;
            NotchButtonDef def = _buttonDefs[index];
            if (def == null) return;
            if (def.Label == "其他 ▸")
            {
                _otherMenuOpen = !_otherMenuOpen;
                PaintLayered();
                return;
            }
            if (def.CommandKey == "LOG")
            {
                if (_onToggleLog != null) _onToggleLog();
            }
            else if (def.CommandKey == "F")
            {
                if (_onToggleFullscreen != null) _onToggleFullscreen();
            }
            else if (!string.IsNullOrEmpty(def.CommandKey) && _router != null)
            {
                try { _router.Dispatch(def.CommandKey); }
                catch (Exception ex) { LogManager.Log("[NotchOverlay] dispatch failed key=" + def.CommandKey + " ex=" + ex.Message); }
            }
            else if (def.CommandKey == "Q")
            {
                if (_onForceExit != null) _onForceExit();
            }
            else if (def.KeyCode != Keys.None)
            {
                if (_onSendKey != null) _onSendKey(def.KeyCode);
            }
            else
            {
                _otherMenuOpen = false;
            }
        }

        #endregion

        #region Owner 跟随

        protected override void OnOwnerBecameVisible()
        {
            if (_ready) PaintLayered();
        }

        protected override void OnPositionChanged()
        {
            if (_shown && _ownerVisible && _ready)
                PaintLayered();
        }

        #endregion

        #region 定时器 + 状态机

        private void OnTick(object sender, EventArgs e)
        {
            if (!_ready || !_ownerVisible) return;
            bool needsPaint = false;

            if (_expandClickCooldown > 0)
            {
                _expandClickCooldown -= TickMs;
                if (_expandClickCooldown < 0) _expandClickCooldown = 0;
            }

            switch (_state)
            {
                case NotchState.Expanding:
                    _expandProgress += (float)TickMs / ExpandAnimMs;
                    if (_expandProgress >= 1f)
                    {
                        _expandProgress = 1f;
                        _state = NotchState.Expanded;
                    }
                    needsPaint = true;
                    break;

                case NotchState.Expanded:
                    if (_autoHideCountdown > 0)
                    {
                        _autoHideCountdown -= TickMs;
                        if (_autoHideCountdown <= 0)
                        {
                            _autoHideCountdown = 0;
                            _state = NotchState.Collapsing;
                            _chartVisible = false;
                            _expandedChartRect = Rectangle.Empty;
                            needsPaint = true;
                        }
                    }
                    break;

                case NotchState.Collapsing:
                    _expandProgress -= (float)TickMs / CollapseAnimMs;
                    if (_expandProgress <= 0f)
                    {
                        _expandProgress = 0f;
                        _state = NotchState.Collapsed;
                    }
                    needsPaint = true;
                    break;

                case NotchState.Collapsed:
                    break;
            }

            if (TickCurrencySlot(_gold, TickMs)) needsPaint = true;
            if (TickCurrencySlot(_kp, TickMs)) needsPaint = true;
            if (_gameThrottleRemainingMs > 0)
            {
                _gameThrottleRemainingMs -= TickMs;
                if (_gameThrottleRemainingMs <= 0)
                {
                    _gameThrottleRemainingMs = 0;
                    DrainGameQueue();
                    needsPaint = true;
                }
            }

            // 老化信息行
            bool hadInfoRows = _infoRows.Count > 0;
            for (int i = _infoRows.Count - 1; i >= 0; i--)
            {
                _infoRows[i].AgeMs += TickMs;
                if (_infoRows[i].PulseMs > 0)
                {
                    _infoRows[i].PulseMs -= TickMs;
                    if (_infoRows[i].PulseMs < 0) _infoRows[i].PulseMs = 0;
                    needsPaint = true;
                }
                // 推进交叉淡变
                if (_infoRows[i].PrevText != null)
                {
                    _infoRows[i].TransitionMs += TickMs;
                    if (_infoRows[i].TransitionMs >= NotchInfoRow.TransitionDuration)
                        _infoRows[i].PrevText = null; // 过渡完成
                    needsPaint = true;
                }
                if (!_infoRows[i].Persistent)
                {
                    _infoRows[i].RemainingMs -= TickMs;
                    if (_infoRows[i].RemainingMs <= 0)
                    {
                        _infoRows.RemoveAt(i);
                        needsPaint = true;
                    }
                    else
                    {
                        needsPaint = true;
                    }
                }
            }
            if (hadInfoRows && _infoRows.Count > 0) needsPaint = true;

            _stableRefreshElapsedMs += TickMs;
            if (_stableRefreshElapsedMs >= StableRefreshMs)
            {
                _stableRefreshElapsedMs = 0;
                needsPaint = true;
            }

            if (needsPaint) PaintLayered();
        }

        #endregion

        #region 渲染

        private void GetCurrentSize(out int w, out int h)
        {
            float vpX, vpY, vpW, vpH;
            _mapper.CalcViewport(out vpX, out vpY, out vpW, out vpH);
            float scale = GetScale(vpH);
            int collapsedW = ComputeCollapsedWidth(scale);
            int expandedW = ComputeExpandedWidth(scale, (int)vpW);
            _currentExpandedW = expandedW;

            // ease-out: t*(2-t)
            float t = _expandProgress;
            float eased = t * (2f - t);

            w = collapsedW + (int)((expandedW - collapsedW) * eased);
            int row1H = Px(CollapsedH, scale);
            int toolbarH = _gameReady ? Px(ToolbarPadTop + ToolbarButtonH + ToolbarPadBottom, scale) : 0;
            h = row1H + (int)(toolbarH * eased);
            // 每行信息 +RowGap+RowH
            int rowCount = _infoRows.Count;
            if (rowCount > 0)
                h += rowCount * (Px(RowGap, scale) + Px(RowH, scale));
            if (_otherMenuOpen)
                h += OtherButtons.Length * (Px(ToolbarButtonH, scale) + Px(1, scale)) + Px(8, scale);
            if (_chartVisible)
                h += ExpandedChartHeight(scale);
        }

        private void PaintLayered()
        {
            if (!_ready) return;

            float vpX, vpY, vpW, vpH;
            _mapper.CalcViewport(out vpX, out vpY, out vpW, out vpH);
            float scale = GetScale(vpH);

            int w, h;
            GetCurrentSize(out w, out h);

            Point origin;
            GetAnchorScreenOrigin(out origin);

            // 居中于视口顶部
            int scrX = origin.X + (int)vpX + ((int)vpW - w) / 2;
            int scrY = origin.Y + (int)vpY;

            using (Bitmap bmp = new Bitmap(w, h, PixelFormat.Format32bppPArgb))
            {
                using (Graphics g = Graphics.FromImage(bmp))
                {
                    g.SmoothingMode = SmoothingMode.AntiAlias;
                    g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
                    g.Clear(Color.Transparent);
                    _sparklineRect = Rectangle.Empty;
                    _expandButtonRect = Rectangle.Empty;
                    if (!_chartVisible) _expandedChartRect = Rectangle.Empty;

                    float t = _expandProgress;
                    float eased = t * (2f - t);
                    int row1H = Px(CollapsedH, scale);
                    int toolbarH = _gameReady ? (int)(Px(ToolbarPadTop + ToolbarButtonH + ToolbarPadBottom, scale) * eased) : 0;
                    int pillH = row1H + toolbarH;

                    DrawRoundedRect(g, 0, 0, w, pillH, Px(8, scale), ResolvePillColor());

                    using (Font fpsFont = new Font("Consolas", Pxf(13f, scale), FontStyle.Bold, GraphicsUnit.Pixel))
                    using (Font textFont = new Font("Microsoft YaHei", Pxf(11f, scale), FontStyle.Regular, GraphicsUnit.Pixel))
                    using (Font monoFont = new Font("Consolas", Pxf(12f, scale), FontStyle.Bold, GraphicsUnit.Pixel))
                    {
                        PaintRow1(g, w, row1H, scale, fpsFont, textFont, monoFont, eased);
                        if (_gameReady && toolbarH > 2)
                        {
                            byte buttonAlpha = (byte)(255 * Math.Min(1f, Math.Max(0f, (eased - 0.15f) / 0.85f)));
                            DrawToolbarButtons(g, w, row1H, scale, textFont, buttonAlpha);
                        }
                        if (_otherMenuOpen)
                            DrawOtherMenu(g, w, pillH, scale, textFont);
                    }

                    // 通知栈：每行独立绘制
                    int rowPadX = Px(6, scale);
                    int rowInnerW = w - rowPadX * 2;
                    int scaledRowH = Px(RowH, scale);
                    int scaledRowGap = Px(RowGap, scale);
                    int rowsStartY = pillH + (_otherMenuOpen ? OtherButtons.Length * (Px(ToolbarButtonH, scale) + Px(1, scale)) + Px(8, scale) : 0);
                    using (Font infoFont = CreateInfoRowFont(false, scale))
                    using (Font gameInfoFont = CreateInfoRowFont(true, scale))
                    {
                        for (int ri = 0; ri < _infoRows.Count; ri++)
                        {
                            NotchInfoRow row = _infoRows[ri];
                            Font rowFont = row.IsGame ? gameInfoFont : infoFont;
                            int rowY = rowsStartY + ri * (scaledRowGap + scaledRowH) + scaledRowGap;
                            float textY = rowY + Math.Max(0f, (scaledRowH - rowFont.GetHeight(g)) / 2f);

                        // 行透明度（淡入 + 淡出）
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

                        // 行背景
                        DrawRoundedRect(g, 0, rowY, w, scaledRowH, Px(4, scale),
                            rowBg);
                        if (row.Persistent)
                        {
                            using (SolidBrush accent = new SolidBrush(Color.FromArgb(ra, row.AccentColor)))
                            {
                                g.FillRectangle(accent, 0, rowY, Px(3, scale), scaledRowH);
                            }
                        }
                        if (row.IsGame)
                        {
                            using (Pen border = new Pen(Color.FromArgb((byte)(ra * 0.2f), 255, 215, 0)))
                            {
                                g.DrawRectangle(border, 0, rowY, w - 1, scaledRowH - 1);
                            }
                        }

                        // 设置裁剪区域防止文字溢出
                        g.SetClip(new Rectangle(textPadX, rowY, textInnerW, scaledRowH));

                        // 当前文字测量
                        SizeF textSize = g.MeasureString(row.Text, rowFont);
                        float textW = textSize.Width;
                        float textX;

                        if (textW <= textInnerW)
                        {
                            // 短文本：居中
                            textX = row.Persistent ? textPadX : textPadX + (textInnerW - textW) / 2f;
                        }
                        else
                        {
                            // 长文本：滚动（来回 ping-pong）
                            float overflow = textW - textInnerW;
                            float scrollCycle = 4000f; // 一个来回 4 秒
                            float phase = (row.AgeMs % scrollCycle) / scrollCycle;
                            // 0→0.5 向左滚，0.5→1 向右滚
                            float scrollT = phase < 0.5f ? phase * 2f : (1f - phase) * 2f;
                            // ease in-out
                            scrollT = scrollT * scrollT * (3f - 2f * scrollT);
                            textX = textPadX - overflow * scrollT;
                        }

                        // 交叉淡变渲染
                        if (row.PrevText != null)
                        {
                            float transT = (float)row.TransitionMs / NotchInfoRow.TransitionDuration;
                            transT = Math.Max(0f, Math.Min(1f, transT));

                            // 旧文字（淡出）
                            byte oldA = (byte)(ra * (1f - transT));
                            Color oldC = Color.FromArgb(oldA, row.PrevColor.R, row.PrevColor.G, row.PrevColor.B);
                            SizeF oldSize = g.MeasureString(row.PrevText, rowFont);
                            float oldX = (oldSize.Width <= textInnerW)
                                ? (row.Persistent ? textPadX : textPadX + (textInnerW - oldSize.Width) / 2f)
                                : textPadX;
                            using (SolidBrush ob = new SolidBrush(oldC))
                            {
                                g.DrawString(row.PrevText, rowFont, ob, oldX, textY);
                            }

                            // 新文字（淡入）
                            byte newA = (byte)(ra * transT);
                            Color newC = Color.FromArgb(newA, row.AccentColor.R, row.AccentColor.G, row.AccentColor.B);
                            using (SolidBrush nb = new SolidBrush(newC))
                            {
                                g.DrawString(row.Text, rowFont, nb, textX, textY);
                            }
                        }
                        else
                        {
                            // 正常渲染
                            Color rc = Color.FromArgb(ra, row.AccentColor.R, row.AccentColor.G, row.AccentColor.B);
                            using (SolidBrush rb = new SolidBrush(rc))
                            {
                                g.DrawString(row.Text, rowFont, rb, textX, textY);
                            }
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

                CommitBitmap(bmp, scrX, scrY, 255);
            }

            // 更新窗口大小以匹配渲染区域
            SetWindowPos(this.Handle, HWND_TOP, scrX, scrY, w, h,
                SWP_NOACTIVATE);
        }

        private void DrawToolbarButtons(Graphics g, int totalW, int row1H, float scale, Font font, byte alpha)
        {
            List<Rectangle> rects = new List<Rectangle>();
            List<NotchButtonDef> defs = new List<NotchButtonDef>();
            int btnH = Px(ToolbarButtonH, scale);
            int gap = Px(ToolbarButtonGap, scale);
            int x = Px(ToolbarPadX, scale);
            int y = row1H + Px(ToolbarPadTop, scale);

            for (int i = 0; i < ToolbarButtons.Length; i++)
            {
                NotchButtonDef def = ToolbarButtons[i];
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

        private void PaintRow1(Graphics g, int totalW, int row1H, float scale, Font fpsFont, Font textFont, Font monoFont, float expandedEase)
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
                int goldW = ComputeCurrencyWidth(_gold.Current, scale);
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

            if (expandedEase > 0.65f)
            {
                string badge = "L" + _fpsBuffer.PerfLevel;
                int badgeW = Px(24, scale);
                Rectangle badgeRect = new Rectangle(x, (row1H - Px(14, scale)) / 2, badgeW, Px(14, scale));
                Color badgeColor = GetPerfColor(_fpsBuffer.PerfLevel);
                using (SolidBrush bg = new SolidBrush(Color.FromArgb(38, badgeColor)))
                using (SolidBrush fg = new SolidBrush(badgeColor))
                using (StringFormat sf = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center })
                {
                    g.FillRectangle(bg, badgeRect);
                    g.DrawString(badge, textFont, fg, badgeRect, sf);
                }
                x += badgeW + Px(CenterGap, scale);
            }

            int sparkW = Px(SparklineW, scale);
            int sparkH = Px(SparklineH, scale);
            int sparkY = (row1H - sparkH) / 2;
            _sparklineRect = new Rectangle(x, sparkY, sparkW, sparkH);
            DrawLightBackground(g, x, sparkY, sparkW, sparkH);
            DrawSparkline(g, x, sparkY, sparkW, sparkH, fpsColor);
            x += sparkW + Px(CenterGap + 1, scale);

            int clockSize = Px(16, scale);
            DrawClock(g, x + clockSize / 2, centerY, clockSize / 2, _fpsBuffer.GameHour);
            x += clockSize + Px(CenterGap, scale);

            if (expandedEase > 0.65f)
            {
                string time = FormatGameTime(_fpsBuffer.GameHour);
                int statsW = Px(44, scale);
                Rectangle statsRect = new Rectangle(x, 0, statsW, row1H);
                using (SolidBrush b = new SolidBrush(Color.FromArgb(128, 255, 255, 255)))
                using (StringFormat sf = new StringFormat { Alignment = StringAlignment.Near, LineAlignment = StringAlignment.Center })
                    g.DrawString(time, textFont, b, statsRect, sf);
                x += statsW;
            }

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
                int kpW = ComputeCurrencyWidth(_kp.Current, scale);
                Rectangle kpRect = new Rectangle(x, 0, kpW, row1H);
                DrawCurrencyPanel(g, kpRect, "K", _kp, Color.FromArgb(102, 204, 255), monoFont, false, scale);
                x += kpW;
            }

            if (expandedEase > 0.55f)
            {
                int gap = Px(Row1RightGap, scale);
                int totalButtonsW = 0;
                int visibleCount = 0;
                for (int i = 0; i < Row1Buttons.Length; i++)
                {
                    if (!ShouldShowButton(Row1Buttons[i])) continue;
                    totalButtonsW += MeasureButtonWidth(g, textFont, Row1Buttons[i].Label, scale);
                    visibleCount++;
                }
                if (visibleCount > 1) totalButtonsW += gap * (visibleCount - 1);
                int bx = Math.Max(totalW - Px(RowPadX, scale) - totalButtonsW, x + gap);
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
            }

            _buttonRects = rects.ToArray();
            _buttonDefs = defs.ToArray();
        }

        private void DrawOtherMenu(Graphics g, int totalW, int y, float scale, Font font)
        {
            int btnH = Px(ToolbarButtonH, scale);
            int gap = Px(1, scale);
            int menuW = 0;
            for (int i = 0; i < OtherButtons.Length; i++)
                menuW = Math.Max(menuW, MeasureButtonWidth(g, font, OtherButtons[i].Label, scale));
            menuW = Math.Max(menuW, Px(108, scale));
            int x = totalW - Px(RowPadX, scale) - menuW;
            int menuH = OtherButtons.Length * (btnH + gap) + Px(8, scale);
            using (SolidBrush bg = new SolidBrush(Color.FromArgb(225, 24, 24, 26)))
            using (Pen border = new Pen(Color.FromArgb(31, 255, 255, 255)))
            {
                DrawRoundedRectFill(g, x, y, menuW, menuH, Px(4, scale), bg);
                g.DrawRectangle(border, x, y, menuW - 1, menuH - 1);
            }

            List<Rectangle> rects = new List<Rectangle>();
            List<NotchButtonDef> defs = new List<NotchButtonDef>();
            int itemY = y + Px(4, scale);
            for (int i = 0; i < OtherButtons.Length; i++)
            {
                Rectangle r = new Rectangle(x, itemY, menuW, btnH);
                int idx = _buttonDefs.Length + defs.Count;
                PaintButton(g, r, font, OtherButtons[i].Label, 230, idx == _hoverButtonIndex, scale);
                rects.Add(r);
                defs.Add(OtherButtons[i]);
                itemY += btnH + gap;
            }
            AppendButtonRects(rects, defs);
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
            using (SolidBrush bg = new SolidBrush(hover
                ? Color.FromArgb(alpha, 60, 60, 64)
                : Color.FromArgb((byte)(alpha * 0.34f), 255, 255, 255)))
            using (SolidBrush fg = new SolidBrush(hover
                ? Color.FromArgb(alpha, 255, 255, 255)
                : Color.FromArgb((byte)(alpha * 0.82f), 255, 255, 255)))
            using (StringFormat sf = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center, Trimming = StringTrimming.EllipsisCharacter })
            {
                DrawRoundedRectFill(g, r.X, r.Y, r.Width, r.Height, Px(3, scale), bg);
                g.DrawString(text, font, fg, r, sf);
            }
        }

        private void DrawDivider(Graphics g, int x, int rowH, float scale)
        {
            using (SolidBrush b = new SolidBrush(Color.FromArgb(38, 255, 255, 255)))
            {
                int h = Px(14, scale);
                g.FillRectangle(b, x + Px(DividerMarginX, scale), (rowH - h) / 2, Px(DividerW, scale), h);
            }
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
            using (SolidBrush valFg = new SolidBrush(Color.FromArgb(230, 255, 255, 255)))
            using (StringFormat center = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center })
            using (StringFormat valueFmt = new StringFormat { Alignment = leftAlign ? StringAlignment.Near : StringAlignment.Far, LineAlignment = StringAlignment.Center })
            {
                g.FillRectangle(iconBg, iconR);
                g.DrawString(icon, font, iconFg, iconR, center);
                g.DrawString(FormatNumber(slot.Current), font, valFg, valR, valueFmt);
            }
        }

        private static float GetScale(float viewportH)
        {
            if (viewportH <= 0) return 1f;
            return Math.Max(0.5f, viewportH / 576f);
        }

        private static int Px(int basePx, float scale)
        {
            return Math.Max(1, (int)Math.Round(basePx * scale));
        }

        private static float Pxf(float basePx, float scale)
        {
            return Math.Max(1f, basePx * scale);
        }

        private static Font CreateInfoRowFont(bool isGame, float scale)
        {
            float basePx = isGame ? 13f : 12f;
            FontStyle style = isGame ? FontStyle.Bold : FontStyle.Regular;
            return new Font("Microsoft YaHei", Pxf(basePx, scale), style, GraphicsUnit.Pixel);
        }

        internal static float InfoRowFontPxForTest(bool isGame, float scale)
        {
            return Pxf(isGame ? 13f : 12f, scale);
        }

        private static bool ShouldStartHoverExpand(bool canHoverExpand, int expandCooldownMs)
        {
            return canHoverExpand && expandCooldownMs <= 0;
        }

        internal static bool ShouldStartHoverExpandForTest(bool canHoverExpand, int expandCooldownMs)
        {
            return ShouldStartHoverExpand(canHoverExpand, expandCooldownMs);
        }

        internal static int ExpandClickCooldownMsForTest()
        {
            return ExpandClickCooldownMs;
        }

        private int ComputeCollapsedWidth(float scale)
        {
            int center = Px(CenterFpsMinW + CenterGap + SparklineW + CenterGap + 1 + 16 + CenterGap + ArrowW, scale);
            int w = Px(RowPadX * 2, scale) + center;
            if (_gameReady)
            {
                w += ComputeCurrencyWidth(_gold.Current, scale);
                w += ComputeCurrencyWidth(_kp.Current, scale);
                w += Px((DividerW + DividerMarginX * 2) * 2, scale);
            }
            else
            {
                // 未进游戏时 Web #notch 只保留全屏/日志/其他入口。
                w = Px(RowPadX * 2, scale) + MeasureButtonsApprox(Row1Buttons, scale);
            }
            return w;
        }

        private int ComputeExpandedWidth(float scale, int viewportW)
        {
            int collapsed = ComputeCollapsedWidth(scale);
            int row1Right = MeasureButtonsApprox(Row1Buttons, scale) + Px(Row1RightGap * (CountVisibleButtons(Row1Buttons) + 1), scale);
            int toolbar = _gameReady
                ? Px(ToolbarPadX * 2, scale) + MeasureButtonsApprox(ToolbarButtons, scale) + Px(ToolbarButtonGap * Math.Max(0, CountVisibleButtons(ToolbarButtons) - 1), scale)
                : 0;
            int desired = Math.Max(collapsed + row1Right, toolbar);
            if (_chartVisible)
                desired = Math.Max(desired, Px(ExpandedChartW, scale));
            desired = Math.Max(desired, collapsed);
            int max = Math.Min(viewportW, Px(600, scale));
            return Math.Min(Math.Max(desired, collapsed), Math.Max(collapsed, max));
        }

        private static int ExpandedChartHeight(float scale)
        {
            return Px(ExpandedChartPad * 2 + ExpandedChartCanvasH + ExpandedChartHintGap + ExpandedChartHintH, scale);
        }

        private int ComputeCurrencyWidth(int value, float scale)
        {
            string text = FormatNumber(value);
            int chars = Math.Max(6, text.Length);
            int valueW = Math.Max(Px(CurrencyMinValueW, scale), Px(chars * 8, scale));
            return Px(CurrencyIconW + CurrencyGap, scale) + valueW;
        }

        private int MeasureButtonsApprox(NotchButtonDef[] defs, float scale)
        {
            if (defs == null) return 0;
            int w = 0;
            for (int i = 0; i < defs.Length; i++)
            {
                if (!ShouldShowButton(defs[i])) continue;
                w += Px(ButtonPadX * 2 + Math.Max(28, defs[i].Label.Length * 14 + 4), scale);
            }
            return w;
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
            if (level >= 7) return Color.FromArgb(174, 30, 30, 32);
            if (level >= 4) return Color.FromArgb(199, 28, 26, 24);
            return Color.FromArgb(224, 18, 20, 28);
        }

        private static Color GetPerfColor(int level)
        {
            if (level <= 0) return Color.FromArgb(102, 255, 102);
            if (level == 1) return Color.FromArgb(255, 170, 0);
            if (level == 2) return Color.FromArgb(255, 102, 51);
            return Color.FromArgb(255, 68, 68);
        }

        private static string FormatGameTime(float hour)
        {
            int h = ((int)Math.Floor(hour)) % 24;
            int m = (int)Math.Floor((hour - (float)Math.Floor(hour)) * 60f);
            if (m < 0) m = 0;
            if (m > 59) m = 59;
            return (h < 10 ? "0" : "") + h + ":" + (m < 10 ? "0" : "") + m;
        }

        private void StartCurrencyUpdate(CurrencySlot slot, int value, int deltaOverride)
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

        /// <summary>
        /// 绘制光照等级背景（填充区域图），等价于 FPSVisualization.drawCurve 的光照部分。
        /// 从当前游戏小时开始，取 SparklinePoints 个连续小时的光照值。
        /// </summary>
        private void DrawLightBackground(Graphics g, int x, int y, int w, int h)
        {
            if (_lightLevels == null || _lightLevels.Length < 24) return;

            float gameHour = _fpsBuffer.GameHour;
            int startHour = (int)gameHour;
            int points = SparklinePoints;
            float stepX = (float)w / points;
            float stepH = (float)h / MaxLightLevel;

            // 构建填充多边形：底线 → 光照曲线 → 底线
            PointF[] poly = new PointF[points + 2];
            poly[0] = new PointF(x, y + h); // 左下角
            for (int i = 0; i < points; i++)
            {
                int hourIdx = (startHour + i) % 24;
                float ly = y + h - _lightLevels[hourIdx] * stepH;
                poly[i + 1] = new PointF(x + i * stepX, ly);
            }
            poly[points + 1] = new PointF(x + (points - 1) * stepX, y + h); // 右下角

            // 用暖黄色填充，模拟日光感，alpha 足够高以在深色底上可辨识
            using (SolidBrush brush = new SolidBrush(Color.FromArgb(100, 180, 160, 60)))
            {
                g.FillPolygon(brush, poly);
            }
            // 顶部轮廓线增强可读性
            PointF[] outline = new PointF[points];
            Array.Copy(poly, 1, outline, 0, points);
            using (Pen outlinePen = new Pen(Color.FromArgb(140, 200, 180, 70), 1f))
            {
                g.DrawLines(outlinePen, outline);
            }
        }

        private void DrawSparkline(Graphics g, int x, int y, int w, int h, Color lineColor)
        {
            if (!_fpsBuffer.HasData)
            {
                // 无数据：灰色平直线
                using (Pen grayPen = new Pen(Color.FromArgb(60, 255, 255, 255), 1))
                {
                    g.DrawLine(grayPen, x, y + h / 2, x + w, y + h / 2);
                }
                return;
            }

            int count = _fpsBuffer.Count;
            int points = Math.Min(SparklinePoints, count);
            if (points < 2) return;

            int startIdx = count - points;

            // 计算局部 min/max
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
            {
                g.DrawLines(linePen, linePoints);
            }
        }

        internal struct FpsChartScale
        {
            internal float MinV;
            internal float MaxV;
            internal float Range;
        }

        internal struct FpsChartStats
        {
            internal float Lo;
            internal float Hi;
            internal float Avg;
            internal float P1Low;
            internal float P5Low;
        }

        private void DrawExpandedChart(Graphics g, Rectangle panel, float scale, Font labelFont, Font hintFont)
        {
            _expandedChartRect = panel;

            using (SolidBrush bg = new SolidBrush(Color.FromArgb(224, 24, 24, 26)))
            using (Pen border = new Pen(Color.FromArgb(31, 255, 255, 255)))
            {
                DrawBottomRoundedRectFill(g, panel.X, panel.Y, panel.Width, panel.Height, Px(8, scale), bg);
                DrawBottomRoundedRectBorder(g, panel.X, panel.Y, panel.Width, panel.Height, Px(8, scale), border);
            }

            int pad = Px(ExpandedChartPad, scale);
            int hintGap = Px(ExpandedChartHintGap, scale);
            int hintH = Px(ExpandedChartHintH, scale);
            Rectangle canvas = new Rectangle(
                panel.X + pad,
                panel.Y + pad,
                Math.Max(1, panel.Width - pad * 2),
                Math.Max(1, panel.Height - pad * 2 - hintGap - hintH));

            using (SolidBrush canvasBg = new SolidBrush(Color.FromArgb(76, 0, 0, 0)))
            {
                DrawRoundedRectFill(g, canvas.X, canvas.Y, canvas.Width, canvas.Height, Px(4, scale), canvasBg);
            }

            DrawLightBackground(g, canvas.X, canvas.Y, canvas.Width, canvas.Height);

            float[] history = GetExpandedHistory();
            if (history.Length < 2)
            {
                using (SolidBrush waitBrush = new SolidBrush(Color.FromArgb(90, 255, 255, 255)))
                using (StringFormat sf = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center })
                {
                    g.DrawString("等待数据...", labelFont, waitBrush, canvas, sf);
                }
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
                {
                    g.DrawString(statText, labelFont, statBrush, statRect, sf);
                }
            }

            Rectangle hintRect = new Rectangle(panel.X, canvas.Bottom + hintGap, panel.Width, hintH);
            using (SolidBrush hintBrush = new SolidBrush(Color.FromArgb(90, 255, 255, 255)))
            using (StringFormat sf = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center })
            {
                g.DrawString("点击关闭", hintFont, hintBrush, hintRect, sf);
            }
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
            {
                points[i] = new PointF(canvas.X + i * stepX, FpsChartY(history[i], canvas, chartScale));
            }
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
                {
                    g.FillRectangle(dangerFill, canvas.X, y, canvas.Width, canvas.Bottom - y);
                }
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
                {
                    g.FillPath(grad, path);
                }
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
            {
                g.FillEllipse(glow, point.X - r, point.Y - r, r * 2f, r * 2f);
            }
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
                {
                    g.DrawString(label, font, brush, labelRect, sf);
                }
            }
        }

        internal static int ExpandedChartHeightForTest(float scale)
        {
            return ExpandedChartHeight(scale);
        }

        internal static FpsChartScale ComputeFpsChartScaleForTest(float[] points)
        {
            return ComputeFpsChartScale(points);
        }

        internal static FpsChartStats ComputeFpsStatsForTest(float[] points)
        {
            return ComputeFpsStats(points);
        }

        /// <summary>
        /// 矢量绘制小钟表。gameHour 0-24 映射到 12 小时表盘。
        /// 时针：gameHour 映射角度；分针：小数部分映射角度。
        /// 表盘颜色随昼夜变化。
        /// </summary>
        private static void DrawClock(Graphics g, int cx, int cy, int radius, float gameHour)
        {
            float hour12 = gameHour % 12f; // 0-12 映射到一圈
            int hourInt = ((int)gameHour) % 24;

            // 表盘颜色：白天亮，夜间暗
            Color faceColor, rimColor, handColor;
            if (hourInt >= 5 && hourInt <= 17)
            {
                faceColor = Color.FromArgb(50, 180, 170, 100);  // 白天：暖黄底
                rimColor = Color.FromArgb(180, 200, 190, 120);
                handColor = Color.FromArgb(220, 240, 230, 160);
            }
            else if ((hourInt >= 3 && hourInt <= 4) || (hourInt >= 18 && hourInt <= 20))
            {
                faceColor = Color.FromArgb(50, 200, 140, 60);   // 黄昏：橙底
                rimColor = Color.FromArgb(160, 220, 160, 80);
                handColor = Color.FromArgb(200, 240, 180, 100);
            }
            else
            {
                faceColor = Color.FromArgb(40, 100, 120, 180);  // 夜间：蓝底
                rimColor = Color.FromArgb(140, 130, 150, 200);
                handColor = Color.FromArgb(180, 160, 180, 220);
            }

            // 表盘填充
            using (SolidBrush faceBrush = new SolidBrush(faceColor))
            {
                g.FillEllipse(faceBrush, cx - radius, cy - radius, radius * 2, radius * 2);
            }

            // 外圈
            using (Pen rimPen = new Pen(rimColor, 1.2f))
            {
                g.DrawEllipse(rimPen, cx - radius, cy - radius, radius * 2, radius * 2);
            }

            // 时针（短粗）：hour12 映射到 360°，12点 = -90°
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

            // 分针（长细）：小数部分映射 360°
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

            // 中心点
            using (SolidBrush dotBrush = new SolidBrush(handColor))
            {
                g.FillEllipse(dotBrush, cx - 1, cy - 1, 3, 3);
            }
        }

        private static Color GetFpsColor(float fps)
        {
            if (fps >= FpsGreenThreshold) return Color.FromArgb(0, 255, 100);
            if (fps >= FpsYellowThreshold) return Color.FromArgb(255, 220, 0);
            return Color.FromArgb(255, 60, 60);
        }

        private static void DrawRoundedRect(Graphics g, int x, int y, int w, int h, int r, Color color)
        {
            using (SolidBrush brush = new SolidBrush(color))
            {
                DrawRoundedRectFill(g, x, y, w, h, r, brush);
            }
        }

        private static void DrawRoundedRectFill(Graphics g, int x, int y, int w, int h, int r, Brush brush)
        {
            if (r <= 0)
            {
                g.FillRectangle(brush, x, y, w, h);
                return;
            }
            int d = r * 2;
            using (GraphicsPath path = new GraphicsPath())
            {
                path.AddArc(x, y, d, d, 180, 90);
                path.AddArc(x + w - d, y, d, d, 270, 90);
                path.AddArc(x + w - d, y + h - d, d, d, 0, 90);
                path.AddArc(x, y + h - d, d, d, 90, 90);
                path.CloseFigure();
                g.FillPath(brush, path);
            }
        }

        private static void DrawBottomRoundedRectFill(Graphics g, int x, int y, int w, int h, int r, Brush brush)
        {
            if (r <= 0)
            {
                g.FillRectangle(brush, x, y, w, h);
                return;
            }
            using (GraphicsPath path = CreateBottomRoundedRectPath(x, y, w, h, r))
            {
                g.FillPath(brush, path);
            }
        }

        private static void DrawBottomRoundedRectBorder(Graphics g, int x, int y, int w, int h, int r, Pen pen)
        {
            if (r <= 0)
            {
                g.DrawRectangle(pen, x, y, w - 1, h - 1);
                return;
            }
            using (GraphicsPath path = CreateBottomRoundedRectPath(x, y, w - 1, h - 1, r))
            {
                g.DrawPath(pen, path);
            }
        }

        private static GraphicsPath CreateBottomRoundedRectPath(int x, int y, int w, int h, int r)
        {
            int maxR = Math.Min(r, Math.Min(w, h) / 2);
            int d = maxR * 2;
            GraphicsPath path = new GraphicsPath();
            if (maxR <= 0)
            {
                path.AddRectangle(new Rectangle(x, y, w, h));
                return path;
            }
            path.AddLine(x, y, x + w, y);
            path.AddLine(x + w, y, x + w, y + h - maxR);
            path.AddArc(x + w - d, y + h - d, d, d, 0, 90);
            path.AddArc(x, y + h - d, d, d, 90, 90);
            path.AddLine(x, y + h - maxR, x, y);
            path.CloseFigure();
            return path;
        }

        #endregion

        /// <summary>从 config/WeatherSystemConfig.xml 读取 24 小时光照等级表。</summary>
        private static int[] LoadLightLevels(string projectRoot)
        {
            int[] levels = new int[24];
            // 默认白天值
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
                LogManager.Log("[Notch] Failed to load light levels: " + ex.Message);
            }

            return levels;
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                _timer.Stop();
                _timer.Dispose();
                if (_fpsFont != null) _fpsFont.Dispose();
            }
            base.Dispose(disposing);
        }
    }

    /// <summary>
    /// 通知栈行：持久（波次等）或瞬态（性能等级变化等）。
    /// 同 Category 的新消息替换旧消息。
    /// </summary>
    public class NotchInfoRow
    {
        public string BaseText;
        public bool IsGame;
        public int Count;
        public int PulseMs;
        public string Category;    // 去重键
        public string Text;        // 当前显示文字
        public Color AccentColor;  // 当前文字颜色
        public bool Persistent;    // true=持久，false=自动过期
        public int RemainingMs;    // 瞬态专用：剩余毫秒
        public int AgeMs;          // 已存活毫秒（用于淡入）

        // 平滑过渡：替换旧文字时交叉淡变
        public string PrevText;        // 被替换的旧文字（null=无过渡）
        public Color PrevColor;        // 旧文字颜色
        public int TransitionMs;       // 过渡已进行毫秒
        public const int TransitionDuration = 400; // 交叉淡变时长
    }
}
