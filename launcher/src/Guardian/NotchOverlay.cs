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

        #endregion

        #region 状态机

        private enum NotchState { Collapsed, Expanding, Expanded, Collapsing }
        private NotchState _state;

        #endregion

        #region 常量

        // 尺寸（屏幕像素，非 Flash 舞台坐标）
        // 8(pad) + ~32(fps@13pt) + 3 + 70(sparkline) + 4 + 16(clock) + 4 + 14(▼) + 8(pad) ≈ 160
        private const int CollapsedW = 160;
        private const int CollapsedH = 28;
        // 展开宽度在渲染时动态计算（跟随视口宽度）

        // 定时器
        private const int TickMs = 16;
        private const int AutoHideDelayMs = 500;
        private const int ExpandAnimMs = 150;
        private const int CollapseAnimMs = 200;

        // FPS 曲线
        private const int SparklinePoints = 30;
        private const int SparklineW = 70;
        private const int SparklineH = 16;

        // FPS 颜色阈值
        private const float FpsGreenThreshold = 25f;
        private const float FpsYellowThreshold = 18f;

        #endregion

        #region 字段

        private readonly FpsRingBuffer _fpsBuffer;
        private readonly System.Windows.Forms.Timer _timer;

        // 工具栏按钮回调
        private readonly Action _onToggleFullscreen;
        private readonly Action _onToggleLog;
        private readonly Action _onForceExit;
        private readonly Action<Keys> _onSendKey;

        // 状态
        private bool _ready;
        private bool _trackingMouse;
        private float _expandProgress; // 0.0 = collapsed, 1.0 = expanded
        private int _autoHideCountdown;
        private int _hoverButtonIndex; // -1 = none

        // 按钮定义
        private static readonly string[] ButtonLabels = {
            "Q 退出", "W 关闭", "R 重置", "F 全屏", "P 截图", "O 打开", "日志"
        };
        private static readonly Keys[] ButtonKeys = {
            Keys.Q, Keys.W, Keys.R, Keys.F, Keys.P, Keys.O, Keys.None
        };
        private Rectangle[] _buttonRects; // 在 PaintLayered 时计算

        // 渲染
        private Font _fpsFont;
        private Font _buttonFont;
        private int _currentExpandedW; // 当前展开宽度（视口宽度）

        // 光照等级（24 小时，从 WeatherSystemConfig.xml 读取）
        private readonly int[] _lightLevels;
        private const int MaxLightLevel = 9;

        // 通知栈：每条信息独占一行，同 category 替换
        private const int RowH = 20;
        private const int RowGap = 2;
        private const int MaxRows = 4;
        private const int TransientLifetimeMs = 4000;
        private const int FadeInMs = 300;
        private const int FadeOutMs = 800;

        private readonly List<NotchInfoRow> _infoRows;

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
            _hoverButtonIndex = -1;
            _buttonRects = new Rectangle[0];
            _currentExpandedW = 800;
            _infoRows = new List<NotchInfoRow>();

            _fpsFont = new Font("Consolas", 13f, FontStyle.Bold);
            _buttonFont = new Font("Microsoft YaHei", 8f, FontStyle.Regular);

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

        /// <summary>挂起：隐藏窗口 + 停止 timer。WebView2 恢复后调用，避免双重 UI。</summary>
        public void Suspend()
        {
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action(Suspend));
                return;
            }
            _ready = false;
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
            UpsertRow(category, text, accentColor, false, TransientLifetimeMs);
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
                if (_state == NotchState.Collapsed || _state == NotchState.Collapsing)
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
            if (_expandProgress < 0.5f) return;
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
            if (_expandProgress < 0.5f) return;
            for (int i = 0; i < _buttonRects.Length; i++)
            {
                if (_buttonRects[i].Contains(localX, localY))
                {
                    ExecuteButton(i);
                    break;
                }
            }
        }

        private void ExecuteButton(int index)
        {
            if (index < 0 || index >= ButtonKeys.Length) return;

            Keys key = ButtonKeys[index];
            if (key == Keys.None)
            {
                // 日志按钮
                if (_onToggleLog != null) _onToggleLog();
            }
            else if (key == Keys.F)
            {
                if (_onToggleFullscreen != null) _onToggleFullscreen();
            }
            else if (key == Keys.Q)
            {
                if (_onForceExit != null) _onForceExit();
            }
            else
            {
                if (_onSendKey != null) _onSendKey(key);
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

            switch (_state)
            {
                case NotchState.Expanding:
                    _expandProgress += (float)TickMs / ExpandAnimMs;
                    if (_expandProgress >= 1f)
                    {
                        _expandProgress = 1f;
                        _state = NotchState.Expanded;
                    }
                    break;

                case NotchState.Expanded:
                    if (_autoHideCountdown > 0)
                    {
                        _autoHideCountdown -= TickMs;
                        if (_autoHideCountdown <= 0)
                        {
                            _autoHideCountdown = 0;
                            _state = NotchState.Collapsing;
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
                    break;

                case NotchState.Collapsed:
                    // 定期刷新 FPS 显示
                    break;
            }

            // 老化信息行
            for (int i = _infoRows.Count - 1; i >= 0; i--)
            {
                _infoRows[i].AgeMs += TickMs;
                // 推进交叉淡变
                if (_infoRows[i].PrevText != null)
                {
                    _infoRows[i].TransitionMs += TickMs;
                    if (_infoRows[i].TransitionMs >= NotchInfoRow.TransitionDuration)
                        _infoRows[i].PrevText = null; // 过渡完成
                }
                if (!_infoRows[i].Persistent)
                {
                    _infoRows[i].RemainingMs -= TickMs;
                    if (_infoRows[i].RemainingMs <= 0)
                        _infoRows.RemoveAt(i);
                }
            }

            // 每 16ms 刷新一次（FPS 数字更新 + 曲线滚动）
            PaintLayered();
        }

        #endregion

        #region 渲染

        private void GetCurrentSize(out int w, out int h)
        {
            float vpX, vpY, vpW, vpH;
            _mapper.CalcViewport(out vpX, out vpY, out vpW, out vpH);
            _currentExpandedW = Math.Max(CollapsedW, (int)vpW);

            // ease-out: t*(2-t)
            float t = _expandProgress;
            float eased = t * (2f - t);

            w = CollapsedW + (int)((_currentExpandedW - CollapsedW) * eased);
            h = CollapsedH;
            // 每行信息 +RowGap+RowH
            int rowCount = _infoRows.Count;
            if (rowCount > 0)
                h += rowCount * (RowGap + RowH);
        }

        private void PaintLayered()
        {
            if (!_ready) return;

            float vpX, vpY, vpW, vpH;
            _mapper.CalcViewport(out vpX, out vpY, out vpW, out vpH);
            _currentExpandedW = Math.Max(CollapsedW, (int)vpW);

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

                    // 背景圆角矩形
                    // 主栏背景（仅 CollapsedH 高度）
                    DrawRoundedRect(g, 0, 0, w, CollapsedH, 6,
                        Color.FromArgb(200, 24, 24, 26));

                    int contentX = 8;

                    // FPS 数值（垂直居中）
                    string fpsText = _fpsBuffer.HasData
                        ? ((int)_fpsBuffer.Latest).ToString()
                        : "--";
                    Color fpsColor = GetFpsColor(_fpsBuffer.HasData ? _fpsBuffer.Latest : 0f);
                    SizeF fpsSize = g.MeasureString(fpsText, _fpsFont);
                    float fpsY = (CollapsedH - fpsSize.Height) / 2f;
                    using (SolidBrush fpsBrush = new SolidBrush(fpsColor))
                    {
                        g.DrawString(fpsText, _fpsFont, fpsBrush, contentX, fpsY);
                    }
                    contentX += (int)fpsSize.Width + 3;

                    // 迷你曲线区域
                    // 光照等级背景（填充区域图，在曲线下方）
                    DrawLightBackground(g, contentX, 6, SparklineW, SparklineH);
                    // FPS 曲线（叠在光照背景之上）
                    DrawSparkline(g, contentX, 6, SparklineW, SparklineH, fpsColor);
                    contentX += SparklineW + 4;

                    // 矢量钟表（曲线右侧，▼之前）
                    float gameHour = _fpsBuffer.GameHour;
                    int clockSize = 16;
                    int clockCY = CollapsedH / 2;
                    int clockCX = contentX + clockSize / 2;
                    DrawClock(g, clockCX, clockCY, clockSize / 2, gameHour);
                    contentX += clockSize + 4;

                    // 展开指示（收起状态，紧跟内容）
                    if (_expandProgress < 0.5f)
                    {
                        using (SolidBrush arrowBrush = new SolidBrush(Color.FromArgb(120, 255, 255, 255)))
                        {
                            g.DrawString("▼", _buttonFont, arrowBrush, contentX, 7);
                        }
                    }

                    // 展开时：工具栏按钮（仅在主栏内）
                    if (_expandProgress >= 0.3f)
                    {
                        byte buttonAlpha = (byte)(255 * Math.Min(1f, (_expandProgress - 0.3f) / 0.7f));
                        DrawToolbarButtons(g, w, CollapsedH, buttonAlpha);
                    }

                    // 通知栈：每行独立绘制
                    int rowPadX = 6;
                    int rowInnerW = w - rowPadX * 2;
                    for (int ri = 0; ri < _infoRows.Count; ri++)
                    {
                        NotchInfoRow row = _infoRows[ri];
                        int rowY = CollapsedH + ri * (RowGap + RowH) + RowGap;

                        // 行透明度（淡入 + 淡出）
                        float rowAlpha = 1f;
                        if (row.AgeMs < FadeInMs)
                            rowAlpha = (float)row.AgeMs / FadeInMs;
                        if (!row.Persistent && row.RemainingMs < FadeOutMs)
                            rowAlpha = Math.Min(rowAlpha, (float)row.RemainingMs / FadeOutMs);
                        byte ra = (byte)(255 * Math.Max(0f, Math.Min(1f, rowAlpha)));

                        // 行背景
                        DrawRoundedRect(g, 0, rowY, w, RowH, 4,
                            Color.FromArgb((byte)(ra * 0.7f), 20, 20, 22));

                        // 设置裁剪区域防止文字溢出
                        g.SetClip(new Rectangle(rowPadX, rowY, rowInnerW, RowH));

                        // 当前文字测量
                        SizeF textSize = g.MeasureString(row.Text, _buttonFont);
                        float textW = textSize.Width;
                        float textX;

                        if (textW <= rowInnerW)
                        {
                            // 短文本：居中
                            textX = rowPadX + (rowInnerW - textW) / 2f;
                        }
                        else
                        {
                            // 长文本：滚动（来回 ping-pong）
                            float overflow = textW - rowInnerW;
                            float scrollCycle = 4000f; // 一个来回 4 秒
                            float phase = (row.AgeMs % scrollCycle) / scrollCycle;
                            // 0→0.5 向左滚，0.5→1 向右滚
                            float scrollT = phase < 0.5f ? phase * 2f : (1f - phase) * 2f;
                            // ease in-out
                            scrollT = scrollT * scrollT * (3f - 2f * scrollT);
                            textX = rowPadX - overflow * scrollT;
                        }

                        // 交叉淡变渲染
                        if (row.PrevText != null)
                        {
                            float t = (float)row.TransitionMs / NotchInfoRow.TransitionDuration;
                            t = Math.Max(0f, Math.Min(1f, t));

                            // 旧文字（淡出）
                            byte oldA = (byte)(ra * (1f - t));
                            Color oldC = Color.FromArgb(oldA, row.PrevColor.R, row.PrevColor.G, row.PrevColor.B);
                            SizeF oldSize = g.MeasureString(row.PrevText, _buttonFont);
                            float oldX = (oldSize.Width <= rowInnerW)
                                ? rowPadX + (rowInnerW - oldSize.Width) / 2f
                                : rowPadX;
                            using (SolidBrush ob = new SolidBrush(oldC))
                            {
                                g.DrawString(row.PrevText, _buttonFont, ob, oldX, rowY + 2);
                            }

                            // 新文字（淡入）
                            byte newA = (byte)(ra * t);
                            Color newC = Color.FromArgb(newA, row.AccentColor.R, row.AccentColor.G, row.AccentColor.B);
                            using (SolidBrush nb = new SolidBrush(newC))
                            {
                                g.DrawString(row.Text, _buttonFont, nb, textX, rowY + 2);
                            }
                        }
                        else
                        {
                            // 正常渲染
                            Color rc = Color.FromArgb(ra, row.AccentColor.R, row.AccentColor.G, row.AccentColor.B);
                            using (SolidBrush rb = new SolidBrush(rc))
                            {
                                g.DrawString(row.Text, _buttonFont, rb, textX, rowY + 2);
                            }
                        }

                        g.ResetClip();
                    }
                }

                CommitBitmap(bmp, scrX, scrY, 255);
            }

            // 更新窗口大小以匹配渲染区域
            SetWindowPos(this.Handle, HWND_TOP, scrX, scrY, w, h,
                SWP_NOACTIVATE);
        }

        private void DrawToolbarButtons(Graphics g, int totalW, int totalH, byte alpha)
        {
            int btnW = 56;
            int btnH = 20;
            int btnY = (totalH - btnH) / 2;
            int spacing = 2;

            // 从右侧开始布局
            int rightX = totalW - 8;

            _buttonRects = new Rectangle[ButtonLabels.Length];

            for (int i = ButtonLabels.Length - 1; i >= 0; i--)
            {
                SizeF textSize = g.MeasureString(ButtonLabels[i], _buttonFont);
                int thisBtnW = Math.Max(btnW, (int)textSize.Width + 12);
                int btnX = rightX - thisBtnW;

                _buttonRects[i] = new Rectangle(btnX, btnY, thisBtnW, btnH);

                // 背景
                Color bgColor = (i == _hoverButtonIndex)
                    ? Color.FromArgb(alpha, 55, 55, 60)
                    : Color.FromArgb((byte)(alpha * 0.4f), 40, 40, 44);
                using (SolidBrush bgBrush = new SolidBrush(bgColor))
                {
                    DrawRoundedRectFill(g, btnX, btnY, thisBtnW, btnH, 3, bgBrush);
                }

                // 文字
                Color textColor = Color.FromArgb(alpha, 200, 200, 200);
                using (SolidBrush textBrush = new SolidBrush(textColor))
                {
                    using (StringFormat sf = new StringFormat())
                    {
                        sf.Alignment = StringAlignment.Center;
                        sf.LineAlignment = StringAlignment.Center;
                        g.DrawString(ButtonLabels[i], _buttonFont, textBrush,
                            new RectangleF(btnX, btnY, thisBtnW, btnH), sf);
                    }
                }

                rightX = btnX - spacing;
            }
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
                if (_buttonFont != null) _buttonFont.Dispose();
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
