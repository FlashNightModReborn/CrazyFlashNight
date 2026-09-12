using System;
using System.Drawing;
using System.Drawing.Text;
using System.Windows.Forms;
using CF7Launcher.Guardian;

namespace CF7Launcher.Guardian.Hud
{
    /// <summary>
    /// native_interaction NPC 菜单 widget：替代 Flash 内 Symbol 1770 弹出菜单。
    ///
    /// 语义：
    /// - 会话身份 = requestId + sceneId（由 AS2 侧生成，host 只透传不解释）。
    /// - ShowSession 整体替换当前会话（新 show 即旧实例死亡，无部分更新）。
    /// - HideSession 仅在 requestId+sceneId 与当前会话精确匹配时清除；迟到/错位 hide 不动新实例。
    /// - 点击已启用行 → ActionChosen(requestId, sceneId, actionId) 且会话结束（一次性菜单）。
    /// - 禁用行整行命中但不可激活（吞掉点击，不派发）。
    /// - 宿主关闭路径统一走 DismissInteractive(reason)：外部点击 / owner_hidden / panel_suspend，
    ///   清除会话并 fire SessionDismissed（task 据此发 nativeInteractionCancel）。
    /// - ForceClear 为静默清除（断线 / 场景滚转）：不 fire SessionDismissed——AS2 已知情或通道已死。
    ///
    /// 位置：payload 的 x/y 是 Flash 逻辑鼠标锚点，经 FlashCoordinateMapper.FlashToScreen 映射；
    /// 菜单整体 clamp 进 Flash viewport（RightHudLayout.GetViewportRect），右侧溢出左翻、底部溢出上翻。
    /// ScreenBounds 每次动态计算：窗口拖动/全屏切换后菜单跟随 viewport，不做跨场景存活假设。
    ///
    /// 线程模型：Show/Hide/Dismiss 可从 socket worker 线程调用（task 经 UI 派发，但 widget
    /// 自身用 _gate 保护状态），OnMouseEvent 在 UI 线程。事件在锁外 fire。
    /// </summary>
    public class NpcMenuWidget : INativeHudWidget, INativeHudSuppressionAware
    {
        /// <summary>单个菜单行。Id 为 AS2 定义的动作 id（原样回传），Enabled=false 渲染但不激活。</summary>
        public sealed class Entry
        {
            public string Id;
            public string Label;
            public bool Enabled;
        }

        /// <summary>一次菜单会话的不可变快照（host 不修改；替换 = 新实例）。public：ShowSession 签名一致性。</summary>
        public sealed class MenuSession
        {
            public string RequestId;
            public string SceneId;
            public string TargetName;
            public string Title;
            public float AnchorFx;
            public float AnchorFy;
            public Entry[] Entries;
        }

        // 逻辑尺寸（1024×576 设计坐标，WidgetScaler 缩放）
        private const int WIDTH_BASE = 170;
        private const int TITLE_H_BASE = 26;
        private const int ROW_H_BASE = 24;
        private const int PAD_BASE = 5;
        private const int TEXT_PAD_BASE = 10;
        private const int ANCHOR_GAP_BASE = 6;
        private const int VIEWPORT_INSET_BASE = 6;
        private const float TITLE_FONT_BASE_PX = 12.5f;
        private const float ROW_FONT_BASE_PX = 12f;

        private readonly Control _anchor;
        private readonly FlashCoordinateMapper _mapper;
        private readonly object _gate = new object();

        private MenuSession _session;
        private int _hoverIndex = -1;
        private int _downIndex = -1;

        public event EventHandler BoundsOrVisibilityChanged;
        public event EventHandler RepaintRequested;
        public event EventHandler AnimationStateChanged;

        /// <summary>用户点选启用行：(requestId, sceneId, actionId)。task 注入，负责发 nativeInteractionAction。</summary>
        public Action<string, string, string> ActionChosen;

        /// <summary>宿主侧关闭（非 AS2 hide、非行选择）：(requestId, sceneId, reason)。task 注入，负责发 nativeInteractionCancel。</summary>
        public Action<string, string, string> SessionDismissed;

        public NpcMenuWidget(Control anchor)
        {
            if (anchor == null) throw new ArgumentNullException("anchor");
            _anchor = anchor;
            _mapper = new FlashCoordinateMapper(anchor, 1024f, 576f);
            _anchor.Resize += delegate { FireBounds(); };
        }

        private float Scale { get { return WidgetScaler.GetScale(_mapper); } }
        private int MenuWidth { get { return WidgetScaler.Px(WIDTH_BASE, Scale); } }
        private int TitleH { get { return WidgetScaler.Px(TITLE_H_BASE, Scale); } }
        private int RowH { get { return WidgetScaler.Px(ROW_H_BASE, Scale); } }
        private int Pad { get { return WidgetScaler.Px(PAD_BASE, Scale); } }

        // ── 会话管理（task / 宿主调用） ────────────────────────────────

        public void ShowSession(MenuSession session)
        {
            if (session == null || session.Entries == null) return;
            lock (_gate)
            {
                _session = session;
                _hoverIndex = -1;
                _downIndex = -1;
            }
            FireBounds();
        }

        /// <summary>AS2 op:"hide"：仅当身份与当前会话完全匹配时清除。返回是否实际清除。</summary>
        public bool HideSession(string requestId, string sceneId)
        {
            bool cleared = false;
            lock (_gate)
            {
                MenuSession cur = _session;
                if (cur != null
                    && string.Equals(cur.RequestId, requestId, StringComparison.Ordinal)
                    && string.Equals(cur.SceneId, sceneId, StringComparison.Ordinal))
                {
                    _session = null;
                    _hoverIndex = -1;
                    _downIndex = -1;
                    cleared = true;
                }
            }
            if (cleared) FireBounds();
            return cleared;
        }

        /// <summary>静默清除（断线 / 场景滚转 / 任务 reset）：不回报 cancel。</summary>
        public void ForceClear()
        {
            bool had;
            lock (_gate)
            {
                had = _session != null;
                _session = null;
                _hoverIndex = -1;
                _downIndex = -1;
            }
            if (had) FireBounds();
        }

        /// <summary>
        /// 宿主发起的关闭（外部点击 / owner_hidden / panel_suspend）：清除会话并
        /// fire SessionDismissed——是否发 nativeInteractionCancel 由 task 决定。
        /// </summary>
        public void DismissInteractive(string reason)
        {
            MenuSession dismissed;
            lock (_gate)
            {
                dismissed = _session;
                if (dismissed == null) return;
                _session = null;
                _hoverIndex = -1;
                _downIndex = -1;
            }
            FireBounds();
            Action<string, string, string> cb = SessionDismissed;
            if (cb != null)
            {
                try { cb(dismissed.RequestId, dismissed.SceneId, reason); }
                catch (Exception ex) { LogManager.Log("[NpcMenu] SessionDismissed throw: " + ex.Message); }
            }
        }

        /// <summary>INativeHudSuppressionAware：整层被宿主压隐时终结会话（经 task 回报 cancel）。</summary>
        public void OnHostSuppressed(string reason)
        {
            DismissInteractive(reason);
        }

        // ── INativeHudWidget ─────────────────────────────────────────

        public bool Visible
        {
            get { lock (_gate) { return _session != null; } }
        }

        public Rectangle ScreenBounds
        {
            get
            {
                MenuSession s;
                lock (_gate) { s = _session; }
                if (s == null) return Rectangle.Empty;
                if (_anchor == null || !_anchor.IsHandleCreated) return Rectangle.Empty;
                try
                {
                    float scale = Scale;
                    int w = MenuWidth;
                    int h = Pad + TitleH + s.Entries.Length * RowH + Pad;
                    int sx, sy;
                    _mapper.FlashToScreen(s.AnchorFx, s.AnchorFy, out sx, out sy);
                    Rectangle viewport = RightHudLayout.GetViewportRect(_anchor, _mapper);
                    if (viewport.Width <= 0 || viewport.Height <= 0) return Rectangle.Empty;
                    return ComputeMenuRect(sx, sy, w, h,
                        WidgetScaler.Px(ANCHOR_GAP_BASE, scale), viewport,
                        WidgetScaler.Px(VIEWPORT_INSET_BASE, scale));
                }
                catch { return Rectangle.Empty; }
            }
        }

        /// <summary>
        /// 定位：默认锚点右下展开；右边溢出翻到锚点左侧，下边溢出翻到锚点上方；
        /// 最后硬 clamp 进 viewport inset。internal static 便于单测。
        /// </summary>
        internal static Rectangle ComputeMenuRect(
            int anchorScreenX, int anchorScreenY,
            int width, int height, int gap,
            Rectangle viewport, int inset)
        {
            int x = anchorScreenX + gap;
            int y = anchorScreenY + gap;
            if (x + width > viewport.Right - inset)
                x = anchorScreenX - gap - width;
            if (y + height > viewport.Bottom - inset)
                y = anchorScreenY - gap - height;
            int minX = viewport.Left + inset;
            int minY = viewport.Top + inset;
            int maxX = Math.Max(minX, viewport.Right - inset - width);
            int maxY = Math.Max(minY, viewport.Bottom - inset - height);
            if (x < minX) x = minX;
            if (x > maxX) x = maxX;
            if (y < minY) y = minY;
            if (y > maxY) y = maxY;
            return new Rectangle(x, y, width, height);
        }

        public void Paint(Graphics g, float dpr, Point hudOrigin)
        {
            MenuSession s;
            int hover;
            lock (_gate) { s = _session; hover = _hoverIndex; }
            if (s == null) return;
            Rectangle r = ScreenBounds;
            if (r.Width <= 0 || r.Height <= 0) return;

            int localX = r.X - hudOrigin.X;
            int localY = r.Y - hudOrigin.Y;
            float scale = Scale;
            int pad = Pad;
            int titleH = TitleH;
            int rowH = RowH;
            int textPad = WidgetScaler.Px(TEXT_PAD_BASE, scale);
            float titleFontPx = WidgetScaler.Pxf(TITLE_FONT_BASE_PX, scale);
            float rowFontPx = WidgetScaler.Pxf(ROW_FONT_BASE_PX, scale);

            using (Font titleFont = NativeHudFonts.CreateUiFont(titleFontPx, FontStyle.Bold, GraphicsUnit.Pixel))
            using (Font rowFont = NativeHudFonts.CreateUiFont(rowFontPx, FontStyle.Regular, GraphicsUnit.Pixel))
            using (StringFormat leftFmt = new StringFormat
            {
                Alignment = StringAlignment.Near,
                LineAlignment = StringAlignment.Center,
                Trimming = StringTrimming.EllipsisCharacter,
                FormatFlags = StringFormatFlags.NoWrap
            })
            {
                TextRenderingHint prevHint = g.TextRenderingHint;
                g.TextRenderingHint = TextRenderingHint.AntiAlias;
                try
                {
                    NativeHudTheme.DrawPanel(g,
                        new Rectangle(localX, localY, r.Width, r.Height),
                        scale, NativeHudTheme.PanelFillDense, Color.Empty, true);

                    // 标题行：NPC 名
                    Rectangle titleRect = new Rectangle(localX + pad, localY + pad,
                        r.Width - pad * 2, titleH);
                    using (SolidBrush fg = new SolidBrush(NativeHudTheme.TextPrimary))
                        g.DrawString(s.Title ?? "", titleFont, fg, titleRect, leftFmt);
                    using (Pen sep = new Pen(NativeHudTheme.Separator, 1f))
                        g.DrawLine(sep, localX + pad, titleRect.Bottom,
                            localX + r.Width - pad - 1, titleRect.Bottom);

                    int rowsTop = localY + pad + titleH;
                    for (int i = 0; i < s.Entries.Length; i++)
                    {
                        Entry entry = s.Entries[i];
                        Rectangle rowRect = new Rectangle(localX + pad,
                            rowsTop + i * rowH, r.Width - pad * 2, rowH);
                        bool enabled = entry.Enabled;
                        bool rowHover = enabled && i == hover;
                        NativeHudTheme.DrawButton(g, rowRect, scale,
                            rowHover, false, false, false);
                        Color textColor = !enabled
                            ? NativeHudTheme.TextDisabled
                            : (rowHover ? NativeHudTheme.TextPrimary : NativeHudTheme.TextSecondary);
                        Rectangle textRect = new Rectangle(
                            rowRect.X + textPad, rowRect.Y,
                            Math.Max(1, rowRect.Width - textPad * 2), rowRect.Height);
                        using (SolidBrush tb = new SolidBrush(textColor))
                            g.DrawString(entry.Label ?? "", rowFont, tb, textRect, leftFmt);
                    }
                }
                finally { g.TextRenderingHint = prevHint; }
            }
        }

        public bool TryHitTest(Point screenPt)
        {
            return ScreenBounds.Contains(screenPt);
        }

        public void OnMouseEvent(MouseEventArgs e, MouseEventKind kind)
        {
            Rectangle r = ScreenBounds;
            if (r.Width <= 0 || r.Height <= 0) return;
            HandleMouseEvent(e, kind, r);
        }

        /// <summary>与 OnMouseEvent 同逻辑但显式传入 rect——测试钩子（ScreenBounds 依赖 anchor handle）。</summary>
        internal void HandleMouseEventForTest(MouseEventArgs e, MouseEventKind kind, Rectangle rect)
        {
            HandleMouseEvent(e, kind, rect);
        }

        private void HandleMouseEvent(MouseEventArgs e, MouseEventKind kind, Rectangle r)
        {
            int idx = HitRowIndex(r, Pad, TitleH, RowH, EntryCount, e.X, e.Y);
            switch (kind)
            {
                case MouseEventKind.Move:
                case MouseEventKind.Enter:
                    SetHover(idx);
                    break;
                case MouseEventKind.Leave:
                    SetHover(-1);
                    break;
                case MouseEventKind.Cancel:
                    _downIndex = -1;
                    SetHover(-1);
                    break;
                case MouseEventKind.Down:
                    _downIndex = (e.Button == MouseButtons.Left) ? idx : -1;
                    break;
                case MouseEventKind.Click:
                    TryActivateRow(idx);
                    break;
            }
        }

        /// <summary>行命中：标题行与 padding 区返回 -1（命中菜单但不命中行）。internal static 便于单测。</summary>
        internal static int HitRowIndex(Rectangle menuRect, int pad, int titleH, int rowH,
            int entryCount, int sx, int sy)
        {
            int rowsTop = menuRect.Top + pad + titleH;
            int rowsBottom = rowsTop + entryCount * rowH;
            if (sy < rowsTop || sy >= rowsBottom) return -1;
            if (sx < menuRect.Left + pad || sx >= menuRect.Right - pad) return -1;
            int idx = (sy - rowsTop) / Math.Max(1, rowH);
            return (idx >= 0 && idx < entryCount) ? idx : -1;
        }

        private int EntryCount
        {
            get { lock (_gate) { return _session == null ? 0 : _session.Entries.Length; } }
        }

        /// <summary>
        /// Click 派发：Down/Up 行匹配 + 行启用才触发 ActionChosen；菜单一次性，派发即关。
        /// 返回派发结果供测试断言（与 OnMouseEvent.Click 分支共享唯一实现）。
        /// </summary>
        internal ClickOutcome TryActivateRow(int upIdx)
        {
            int down = _downIndex;
            _downIndex = -1;
            MenuSession s;
            lock (_gate) { s = _session; }
            if (s == null || upIdx < 0 || upIdx >= s.Entries.Length) return ClickOutcome.OutOfRange;
            if (upIdx != down) return ClickOutcome.MismatchedDownUp;
            Entry entry = s.Entries[upIdx];
            if (entry == null || !entry.Enabled || string.IsNullOrEmpty(entry.Id))
                return ClickOutcome.Disabled;

            string requestId = s.RequestId;
            string sceneId = s.SceneId;
            string actionId = entry.Id;
            lock (_gate)
            {
                if (_session == s)
                {
                    _session = null;
                    _hoverIndex = -1;
                }
            }
            FireBounds();
            Action<string, string, string> cb = ActionChosen;
            if (cb != null)
            {
                try { cb(requestId, sceneId, actionId); }
                catch (Exception ex) { LogManager.Log("[NpcMenu] ActionChosen throw: " + ex.Message); }
            }
            return ClickOutcome.Activated;
        }

        internal enum ClickOutcome { OutOfRange, MismatchedDownUp, Disabled, Activated }

        private void SetHover(int idx)
        {
            if (_hoverIndex == idx) return;
            _hoverIndex = idx;
            FireRepaint();
        }

        public bool WantsAnimationTick { get { return false; } }
        public void Tick(int deltaMs) { }

        // ── 身份/测试钩子（task 场景滚转判定 + InternalsVisibleTo("Launcher.Tests")） ──
        internal string CurrentRequestId
        {
            get { lock (_gate) { return _session == null ? null : _session.RequestId; } }
        }
        internal string CurrentSceneId
        {
            get { lock (_gate) { return _session == null ? null : _session.SceneId; } }
        }
        internal int SessionEntryCountForTest { get { return EntryCount; } }
        internal int HoverIndexForTest { get { return _hoverIndex; } }
        internal int DownIndexForTest { get { return _downIndex; } set { _downIndex = value; } }

        private void FireBounds()
        {
            EventHandler h = BoundsOrVisibilityChanged;
            if (h != null) { try { h(this, EventArgs.Empty); } catch { } }
        }

        private void FireRepaint()
        {
            EventHandler h = RepaintRequested;
            if (h != null) { try { h(this, EventArgs.Empty); } catch { } }
        }
    }
}
