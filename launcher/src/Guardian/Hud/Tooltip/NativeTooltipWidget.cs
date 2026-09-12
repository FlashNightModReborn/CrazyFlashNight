using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.Windows.Forms;
using CF7Launcher.Guardian.Hud.Loot;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Guardian.Hud.Tooltip
{
    /// <summary>
    /// Native tooltip 渲染单元（COMMON 桥协议 v1 kind:"tooltip"）。
    ///
    /// 生命周期由 host 接入：
    ///   NativeInteractionTask 收到 tooltip.show → Show(payload)；
    ///   tooltip.hide → Hide(requestId)（仅清匹配实例，迟到 hide 不动新实例）；
    ///   场景切换 / 断线 / panel suspend / task reset → Reset()。
    ///
    /// 视觉权威 = 迁移前 Web（launcher/web/modules/tooltip.js +
    /// css/panels/foundation-*.css 的 .flash-tt-* / --tt-* token）：
    /// 灰渐变面板 rgba(153,153,153,.8)→rgba(51,51,51,.8)、无边框无阴影、
    /// icon overlay 混合、12px YaHei、行高 1.25、scale=clientH/864。
    /// NPC 菜单等其他 HUD 不在本类范围，仍可用 NativeHud 风格。
    ///
    /// 静止不逐帧：WantsAnimationTick 恒 false；鼠标移动合并为一次定位，位置未变不重绘。
    /// 命中策略：pinned 在框内参与命中（× 关闭）；simple/dense 恒不命中。
    /// 滚轮：实现 INativeHudWheelConsumer——pinned 框内消费并滚动（未滚也消费，
    /// 防穿透到游戏缩放）；simple/dense 不消费（不阻断下层输入）。host 若需 dense
    /// 长文滚动，可经 ScrollByLines/TryScrollAt 主动转发。
    /// 宿主压隐：实现 INativeHudSuppressionAware——panel_suspend/owner_hidden 时
    /// 就地终结会话（pinned 先报 DismissRequested 再清，simple/dense 直接清）。
    /// </summary>
    public sealed class NativeTooltipWidget : INativeHudWidget,
        INativeHudSuppressionAware, INativeHudWheelConsumer,
        ITooltipInspectionProjection, IDisposable
    {
        private const float StageW = 1024f;
        private const float StageH = 576f;

        // Web overlay 设计高（overlay.css --cf7-overlay-scale: innerHeight/864）
        private const float WebDesignHeight = 864f;
        private const float WebMinScale = 0.25f;

        // Web 字体角色：web.workbench.body = Microsoft YaHei → sans-serif
        // （#panel-tooltip 继承 overlay 的 "Microsoft YaHei","Segoe UI",sans-serif；
        //   native.hud.body 是衬线 Source Han Serif，属于 NativeHud 风格，不用于 tooltip）
        private const string TooltipFontRole = "web.workbench.body";

        // 字号（CSS px，×scale 后为物理 px）
        private const float BodyFontBase = 12f;
        private const float PinnedTitleFontBase = 11f;
        private const float PinnedKeycapFontBase = 9f;
        private const float PinnedCloseFontBase = 16f;

        // ---- Web 视觉 token（--tt-*，迁移前基线值）----
        private static readonly Color GradTop = Color.FromArgb(204, 153, 153, 153);  // rgba(153,153,153,.8)
        private static readonly Color GradBot = Color.FromArgb(204, 51, 51, 51);     // rgba(51,51,51,.8)
        private static readonly Color TextDefault = Color.White;                     // --tt-text
        private static readonly Color Divider = Color.FromArgb(51, 255, 255, 255);   // rgba(255,255,255,.20)
        private static readonly Color ScrollTrack = Color.FromArgb(189, 11, 17, 21); // mix(#0b1115,74%,transparent)
        private static readonly Color ScrollThumb = Color.FromArgb(226, 141, 141, 141);   // mix(#fff 44%,#333)
        private static readonly Color ScrollThumbBorder = Color.FromArgb(212, 84, 84, 84);// mix(#fff 16%,#333)

        // pinned shell 视觉（color-mix 展开，底 #0b1115）
        private static readonly Color ShellGradTop = Color.FromArgb(244, 42, 47, 50);  // mix(gradTop 22%,track)
        private static readonly Color ShellGradBot = Color.FromArgb(235, 27, 31, 33);  // mix(gradBot 40%,track)
        private static readonly Color ShellBorder = Color.FromArgb(82, 255, 255, 255); // mix(text 32%)
        private static readonly Color ShellShadow = Color.FromArgb(122, 11, 17, 21);   // mix(track 48%)
        private static readonly Color HeaderBg = Color.FromArgb(97, 11, 17, 21);       // mix(track 38%)
        private static readonly Color HeaderSep = Color.FromArgb(56, 255, 255, 255);   // mix(text 22%)
        private static readonly Color KeycapBorder = Color.FromArgb(66, 255, 255, 255);// mix(text 26%)
        private static readonly Color KeycapText = Color.FromArgb(153, 255, 255, 255); // --tt-dim 60%
        private static readonly Color CloseBorder = Color.FromArgb(71, 255, 255, 255); // mix(text 28%)
        private static readonly Color CloseBg = Color.FromArgb(15, 255, 255, 255);     // mix(text 6%)
        private static readonly Color IconPlaceholderBg = Color.FromArgb(8, 255, 255, 255); // rgba(255,255,255,.03)

        // dense 检视状态条（tokens.css --wb-semantic-*；--tt-status-bg #1b2328）
        private static readonly Color InspPending = Color.FromArgb(255, 229, 166, 77); // #e5a64d warning
        private static readonly Color InspAccept = Color.FromArgb(255, 120, 188, 115); // #78bc73 success
        private static readonly Color InspStatusBg = Color.FromArgb(255, 27, 35, 40);  // --tt-status-bg
        private const int InspDelayMs = 1000;             // --wb-motion-busy = 默认检视停顿时长

        private readonly Control _anchor;
        private readonly FlashCoordinateMapper _mapper;
        private readonly LootIconCatalog _icons; // 可空：缺 catalog 时 icon 占位
        // 宿主窗口 DPI 缩放（物理 px / 视口 CSS px）：缺省每次布局读 anchor.DeviceDpi；
        // parity fixture / 测试可注入确定性值覆盖 1/1.25/1.5 等档。
        private readonly Func<float> _dpiScaleProvider;

        private NativeTooltipDocument _doc;
        private NativeTooltipLayout.Plan _plan;
        private Rectangle _placedRect;      // 屏幕坐标
        private string _lockedSide;
        private Point _anchorScreen;
        private Rectangle _placementAnchorRect;
        private bool _anchorValid;
        private Point? _livePointer;
        private Point _pendingPointer;
        private string _pendingPointerRequest;
        private readonly Timer _pointerMoveTimer;
        private int _scrollLine;
        private bool _closePressed;
        private float _lastLayoutScale = -1f;
        private float _lastDpiScale = -1f;
        private int _lastVpW, _lastVpH;
        private Rectangle? _ownerBounds;

        // 检视投影（input 侧 TooltipInspectionController 每 tick 推送；
        // 与 web data-inspection-state 同值："idle"/"scan"/"pending"/"inspect"）
        private string _inspectionState = "idle";
        private int _inspectionRemainingMs;

        private Font _fontBody;
        private Font _fontBold;
        private Font _fontHeaderTitle;
        private Font _fontKeycap;
        private Font _fontClose;
        private float _lastFontScale = -1f;
        private readonly Dictionary<string, int> _measureCache =
            new Dictionary<string, int>(StringComparer.Ordinal);
        // run 级样式字体缓存（斜体/下划线/fontSize/fontFace），key=role|px|style
        private readonly Dictionary<string, Font> _styledFonts =
            new Dictionary<string, Font>(StringComparer.Ordinal);
        private readonly StringFormat _textFormat;
        // 测量画布：与 Paint 同一 GDI+ 文本管线（DrawString/MeasureString 一致），
        // 不得用 TextRenderer（GDI）——两套度量宽度不同会系统性错行。
        private Bitmap _measureBmp;
        private Graphics _measureG;

        // icon overlay 混合缓存：单条目 LRU（同 icon+同面板高 重复 paint 复用）
        private Bitmap _blendCache;
        private string _blendCacheKey;

        internal event Action PointerMoved;
        public event EventHandler BoundsOrVisibilityChanged;
        public event EventHandler RepaintRequested;
        public event EventHandler AnimationStateChanged;

        /// <summary>pinned × 关闭请求；参数 = 当前 requestId。host 可转发为 nativeInteractionCancel 或直接 Hide。</summary>
        public event Action<string> DismissRequested;

        public NativeTooltipWidget(Control anchor) : this(anchor, null) { }

        public NativeTooltipWidget(Control anchor, LootIconCatalog icons)
            : this(anchor, icons, null) { }

        /// <param name="dpiScaleProvider">
        /// 宿主窗口 DPI 缩放（物理 px / CSS px = DeviceDpi/96f）的可注入来源；
        /// 每次 EnsureLayout 重读，null → 默认读 anchor.DeviceDpi/96f。
        /// parity fixture / 测试用其覆盖 1/1.25/1.5 等档位做确定性对照。
        /// </param>
        public NativeTooltipWidget(Control anchor, LootIconCatalog icons,
            Func<float> dpiScaleProvider)
        {
            if (anchor == null) throw new ArgumentNullException("anchor");
            _anchor = anchor;
            _icons = icons;
            _dpiScaleProvider = dpiScaleProvider;
            _mapper = new FlashCoordinateMapper(anchor, StageW, StageH);
            // 与浏览器帧调度同样合并连续移动；hook 中只存样本，不测字、不绘制。
            _pointerMoveTimer = new Timer { Interval = 16 };
            _pointerMoveTimer.Tick += delegate { FlushPointerMove(); };
            _textFormat = new StringFormat(StringFormat.GenericTypographic)
            {
                FormatFlags = StringFormatFlags.NoWrap | StringFormatFlags.NoClip,
                Trimming = StringTrimming.None
            };
            EnsureFonts(1f);
            _anchor.Resize += delegate { InvalidateLayout(); };
        }

        #region 公开状态（host / 测试检查点）

        public string CurrentRequestId { get { return _doc != null ? _doc.RequestId : null; } }
        public string CurrentSceneId { get { return _doc != null ? _doc.SceneId : null; } }
        public string CurrentOwner { get { return _doc != null ? _doc.Owner : null; } }
        public long CurrentRevision { get { return _doc != null ? _doc.Revision : 0; } }
        public NativeTooltipDocument ActiveDocument { get { return _doc; } }
        public bool Scrollable { get { return _plan != null && _plan.DescScrollable; } }
        public int ScrollLineOffset { get { return _scrollLine; } }
        public int MaxScrollLine { get { return _plan != null ? _plan.MaxScrollLine : 0; } }
        /// <summary>测试/诊断用：当前排版计划（内部类型，经 InternalsVisibleTo 暴露给 Launcher.Tests）。</summary>
        internal NativeTooltipLayout.Plan ActivePlan { get { return _plan; } }
        internal Rectangle PlacedRect { get { return _placedRect; } }

        /// <summary>
        /// host 可传现役 owner 命中区（屏幕坐标，如 shop 槽位矩形）。
        /// 非 pinned 滚轮消费优先按它判定：设置后仅在指针位于 owner bounds 内时
        /// dense+Scrollable 才消费滚轮；缺省时退化为 Flash 客户区（anchor client
        /// 屏幕矩形）内才消费——root 约定 ownerRect 缺失至少限定客户区，不全屏吞轮。
        /// </summary>
        public Rectangle? OwnerScreenBounds
        {
            get
            {
                if (_ownerBounds.HasValue) return _ownerBounds;
                // AS2 hover 会话由 requestId + hide 管理，旧入口未提供槽位矩形。
                // 必须把同一客户区兜底暴露给 controller；只在 widget 的直接
                // TryScrollAt 路径兜底会让真实 hook 仲裁永远因 null 拒绝滚轮。
                if (_doc == null || _anchor.IsDisposed) return null;
                if (_doc.AnchorRect.HasValue && !_placementAnchorRect.IsEmpty) return _placementAnchorRect;
                Rectangle bounds = AnchorScreenClientRect();
                return bounds.Width > 0 && bounds.Height > 0 ? bounds : (Rectangle?)null;
            }
            set { _ownerBounds = value; }
        }

        #endregion

        #region 生命周期 API（host 调用，UI 线程）

        /// <summary>
        /// 处理 tooltip.show payload。同 requestId 重复 show = 内容/锚点刷新（保留滚动）；
        /// 不同 requestId = 替换当前实例；同 requestId 且 revision 低于当前 = 迟到，拒绝。
        /// </summary>
        public bool Show(JObject payload)
        {
            NativeTooltipDocument doc = NativeTooltipDocument.FromPayload(payload);
            if (doc == null || !doc.HasContent) return false;

            bool sameInstance = _doc != null
                && doc.RequestId != null
                && string.Equals(_doc.RequestId, doc.RequestId, StringComparison.Ordinal);
            if (sameInstance && doc.Revision < _doc.Revision) return false; // 迟到 revision

            _doc = doc;
            if (!sameInstance)
            {
                _scrollLine = 0;
                _livePointer = null;
                CancelPointerMove();
            }
            _closePressed = false;
            _lockedSide = sameInstance ? _lockedSide : null;

            EnsureLayout(true);
            FireBounds();
            FireRepaint();
            return true;
        }

        /// <summary>物理鼠标观察入口：不消费输入；同一帧仅处理最新坐标。</summary>
        internal void QueuePointerMove(int screenX, int screenY)
        {
            if (!Visible || _doc.Profile == NativeTooltipProfile.Pinned) return;
            _pendingPointer = new Point(screenX, screenY);
            _pendingPointerRequest = _doc.RequestId;
            if (!_pointerMoveTimer.Enabled) _pointerMoveTimer.Start();
        }

        internal void FlushPointerMove()
        {
            _pointerMoveTimer.Stop();
            string request = _pendingPointerRequest;
            _pendingPointerRequest = null;
            if (!Visible || !string.Equals(request, _doc.RequestId, StringComparison.Ordinal)
                || _doc.Profile == NativeTooltipProfile.Pinned) return;
            Point pointer = _pendingPointer;
            if (!AnchorScreenClientRect().Contains(pointer)) return;
            // 元素锚保持位置稳定；owner leave 仍由 AS2 hide 终结，不拖动旧图标的注释。
            if (_doc.AnchorRect.HasValue && !_placementAnchorRect.Contains(pointer)) return;
            // simple 保留进入浮层阅读的过桥行为；dense 继续避让，浮层不命中。
            if (_doc.Profile == NativeTooltipProfile.Simple && _placedRect.Contains(pointer)) return;
            if (_livePointer.HasValue && _livePointer.Value == pointer) return;
            _livePointer = pointer;
            Rectangle before = _placedRect;
            EnsureLayout(false);
            if (_placedRect != before)
            {
                FireBounds();
                FireRepaint();
            }
            // 刷新检视控制器的几何快照，simple 滚轮/过桥不继续命中旧位置。
            Action moved = PointerMoved;
            if (moved != null) moved();
        }

        private void CancelPointerMove()
        {
            _pointerMoveTimer.Stop();
            _pendingPointerRequest = null;
        }

        /// <summary>仅清 requestId 精确匹配的当前实例；不匹配返回 false 不动显示。</summary>
        public bool Hide(string requestId)
        {
            if (_doc == null || requestId == null) return false;
            if (!string.Equals(_doc.RequestId, requestId, StringComparison.Ordinal)) return false;
            Clear();
            return true;
        }

        /// <summary>宿主生命周期 reset：无条件全清。</summary>
        public void Reset()
        {
            if (_doc == null && _plan == null) return;
            Clear();
        }

        /// <summary>
        /// ITooltipInspectionProjection：input 侧 TooltipInspectionController 的
        /// 每 tick 视觉投影（web setInspectionState / ensureInspectionStatus）。
        /// dense + "pending"/"inspect" 在 tip 顶部绘制检视状态条：
        ///   pending = 23px 文案条 + 72px 进度槽（随 remainingMs 推进）；
        ///   inspect = 稳态折叠的 2px accent 细条（web 约 1.2s 后 collapse）；
        ///   "scan"/"idle" = 无条。状态切换改变 tip 尺寸 → 重排；其余仅重绘。
        /// </summary>
        public void SetInspectionState(string state, int remainingMs)
        {
            string s = state == NativeTooltipLayout.InspStatePending
                || state == NativeTooltipLayout.InspStateInspect
                || state == "scan" ? state : "idle";
            bool changed = s != _inspectionState;
            _inspectionState = s;
            _inspectionRemainingMs = Math.Max(0, remainingMs);
            if (!Visible) return;
            if (changed) InvalidateLayout();   // 条高变化 → tip 尺寸变 → 重排
            else FireRepaint();                // pending 进度推进仅重绘
        }

        /// <summary>测试/诊断：当前检视投影态（无会话时保持上次推送值）。</summary>
        internal string CurrentInspectionState { get { return _inspectionState; } }

        /// <summary>行级滚动（dense 由 host/owner 转发）。返回是否实际滚动。</summary>
        public bool ScrollByLines(int delta)
        {
            if (_plan == null || !_plan.DescScrollable) return false;
            int next = Math.Max(0, Math.Min(_plan.MaxScrollLine, _scrollLine + delta));
            if (next == _scrollLine) return false;
            _scrollLine = next;
            FireRepaint();
            return true;
        }

        /// <summary>
        /// 滚轮增量滚动（120 = 一格 ≈ 3 行）。pinned 需点在框内；非 pinned 在
        /// OwnerScreenBounds 已设置时需点在 owner 命中区内，否则由调用方担保上下文。
        /// </summary>
        public bool TryScrollAt(Point screenPt, int wheelDelta)
        {
            if (_doc == null || _plan == null) return false;
            if (_doc.Profile == NativeTooltipProfile.Pinned)
            {
                if (!_placedRect.Contains(screenPt)) return false;
            }
            else if (_ownerBounds.HasValue)
            {
                if (!_ownerBounds.Value.Contains(screenPt)) return false;
            }
            else if (!AnchorScreenClientRect().Contains(screenPt))
            {
                return false;
            }
            int notches = wheelDelta / 120;
            if (notches == 0) notches = wheelDelta > 0 ? 1 : -1;
            return ScrollByLines(-notches * 3);
        }

        #endregion

        #region INativeHudWheelConsumer / INativeHudSuppressionAware

        /// <summary>
        /// host 全局滚轮钩子路由。
        /// pinned：框内消费（滚到边界也消费，防穿透到游戏）。
        /// 非 pinned 且 DescScrollable：dense 长文显示期间滚轮转为本注释滚动——
        /// 浮层不吃命中（TryHitTest 仍 false），可见生命周期靠 AS2 onRollOut 收敛，
        /// 不要求先把指针移进浮层；host 提供 OwnerScreenBounds 时按真实 owner 命中判定。
        /// 其余情形（simple / dense 未溢出 / 框外）一律放行。
        /// </summary>
        public bool OnMouseWheel(Point screenPt, int wheelDelta)
        {
            if (_doc == null || _plan == null) return false;
            if (_doc.Profile == NativeTooltipProfile.Pinned)
            {
                if (!_placedRect.Contains(screenPt)) return false;
                TryScrollAt(screenPt, wheelDelta);
                return true;
            }
            if (!_plan.DescScrollable) return false;
            if (_ownerBounds.HasValue)
            {
                if (!_ownerBounds.Value.Contains(screenPt)) return false;
            }
            else if (!AnchorScreenClientRect().Contains(screenPt)) return false;
            TryScrollAt(screenPt, wheelDelta);
            return true;
        }

        /// <summary>
        /// 宿主整层压隐（panel_suspend / owner_hidden）：就地终结会话。
        /// pinned 先报 DismissRequested（host 决定是否发 nativeInteractionCancel）再清。
        /// </summary>
        public void OnHostSuppressed(string reason)
        {
            if (_doc == null) return;
            if (_doc.Profile == NativeTooltipProfile.Pinned)
            {
                Action<string> h = DismissRequested;
                if (h != null) h(_doc.RequestId);
            }
            Clear();
        }

        #endregion

        #region INativeHudWidget

        public Rectangle ScreenBounds
        {
            get
            {
                if (!Visible) return Rectangle.Empty;
                EnsureLayout(false);
                return _placedRect;
            }
        }

        public bool Visible { get { return _doc != null && _plan != null; } }

        public bool WantsAnimationTick { get { return false; } }

        public void Tick(int deltaMs) { }

        public void Paint(Graphics g, float dpr, Point hudOrigin)
        {
            if (!Visible) return;
            EnsureLayout(false);
            if (_plan == null) return;
            float scale = CurrentScale();
            EnsureFonts(scale);

            int ox = _placedRect.X - hudOrigin.X;
            int oy = _placedRect.Y - hudOrigin.Y;
            NativeTooltipLayout.Plan plan = _plan;

            GraphicsState state = g.Save();
            try
            {
                g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
                g.SmoothingMode = SmoothingMode.None;

                if (plan.Pinned) PaintPinned(g, plan, ox, oy, scale);
                else PaintFloating(g, plan, ox, oy, scale);
            }
            finally { g.Restore(state); }
        }

        public bool TryHitTest(Point screenPt)
        {
            if (!Visible) return false;
            // 仅 pinned 参与命中；simple/dense 不吃任何鼠标（浮层不阻断游戏/面板输入）。
            if (_doc == null || _doc.Profile != NativeTooltipProfile.Pinned) return false;
            return _placedRect.Contains(screenPt);
        }

        public void OnMouseEvent(MouseEventArgs e, MouseEventKind kind)
        {
            if (_doc == null || _plan == null || _doc.Profile != NativeTooltipProfile.Pinned) return;
            Point local = new Point(e.X - _placedRect.X, e.Y - _placedRect.Y);
            bool inClose = CloseHit(local);
            switch (kind)
            {
                case MouseEventKind.Down:
                    _closePressed = inClose;
                    break;
                case MouseEventKind.Up:
                case MouseEventKind.Click:
                    if (inClose && (_closePressed || kind == MouseEventKind.Click))
                    {
                        _closePressed = false;
                        Action<string> h = DismissRequested;
                        if (h != null) h(_doc.RequestId);
                    }
                    else _closePressed = false;
                    break;
                case MouseEventKind.Cancel:
                case MouseEventKind.Leave:
                    _closePressed = false;
                    break;
            }
        }

        #endregion

        #region 绘制

        /// <summary>浮动 tooltip（rich 骨架或 plain 文本框）。</summary>
        private void PaintFloating(Graphics g, NativeTooltipLayout.Plan plan,
            int ox, int oy, float scale)
        {
            // dense 检视状态条（_el 首子节点，位于面板上方；pointer-events:none）
            if (!plan.InspStrip.IsEmpty)
                PaintInspectionStrip(g, Offset(plan.InspStrip, ox, oy),
                    plan.InspState, scale);

            // intro 面板（plain 模式 = 单文本框；rich = icon+文字列）
            if (!plan.IntroPanel.IsEmpty)
                DrawGradientPanel(g, Offset(plan.IntroPanel, ox, oy));
            // split：desc 独立第二面板，同样画渐变（无边框无阴影）
            if (plan.Split && !plan.DescPanel.IsEmpty)
                DrawGradientPanel(g, Offset(plan.DescPanel, ox, oy));

            if (!plan.IconRect.IsEmpty)
                DrawIcon(g, Offset(plan.IconRect, ox, oy), plan.IconName,
                    Offset(plan.IntroPanel, ox, oy));

            if (plan.Plain)
            {
                Rectangle clip = Offset(plan.IntroPanel, ox, oy);
                clip.Inflate(-1, -1);
                PaintLines(g, plan.IntroLines, 0, plan.IntroLines.Count,
                    ox + plan.IntroContentLeftPx, oy + plan.IntroContentTopPx,
                    plan.LineHeightPx, clip);
                return;
            }

            if (plan.Split && !plan.DescPanel.IsEmpty)
            {
                // intro 面板：文字裁到面板内缘
                Rectangle introClip = Offset(plan.IntroPanel, ox, oy);
                PaintLines(g, plan.IntroLines, 0, plan.IntroLines.Count,
                    ox + plan.IntroContentLeftPx, oy + plan.IntroContentTopPx,
                    plan.LineHeightIntroPx, introClip);

                Rectangle descTextClip = Offset(plan.ScrollViewportRect, ox, oy);
                // 行数不预截：clip 负责边界（末行可部分可见，同 web overflow）。
                PaintLines(g, plan.DescLines, _scrollLine,
                    plan.DescLines.Count - _scrollLine,
                    ox + plan.DescContentLeftPx, oy + plan.DescContentTopPx,
                    plan.LineHeightDescPx, descTextClip);
                if (plan.DescScrollable)
                    DrawScrollbar(g, Offset(plan.DescPanel, ox, oy),
                        plan.DescTotalLines, plan.DescVisibleLines, _scrollLine, plan.MaxScrollLine, scale,
                        NativeTooltipLayout.Px(NativeTooltipLayout.ScrollbarWBase, scale));
            }
            else
            {
                // merge：intro 面板内文字（含拼入的 desc），Web 不滚动
                Rectangle clip = Offset(plan.IntroPanel, ox, oy);
                PaintLines(g, plan.IntroLines, 0, plan.IntroLines.Count,
                    ox + plan.IntroContentLeftPx, oy + plan.IntroContentTopPx,
                    plan.LineHeightIntroPx, clip);
            }
        }

        /// <summary>pinned 检视器：壳（渐变+1px 边+阴影）+ header + 滚动 body。</summary>
        private void PaintPinned(Graphics g, NativeTooltipLayout.Plan plan,
            int ox, int oy, float scale)
        {
            int border = NativeTooltipLayout.Px(NativeTooltipLayout.PinnedBorderBase, scale);
            Rectangle shell = new Rectangle(ox, oy, _placedRect.Width, _placedRect.Height);

            // 阴影近似：Web box-shadow 0 10px 28px → 半透明偏移矩形（高斯模糊无对应物）
            int shOff = NativeTooltipLayout.Px(10, scale);
            int shBlur = NativeTooltipLayout.Px(14, scale);
            using (SolidBrush sh = new SolidBrush(ShellShadow))
                g.FillRectangle(sh, shell.X, shell.Y + shOff,
                    shell.Width + shBlur, shell.Height + shOff / 2);

            // 壳：灰族渐变（提高不透明度版）+ 1px 边框
            using (LinearGradientBrush bg = new LinearGradientBrush(
                shell, ShellGradTop, ShellGradBot, LinearGradientMode.Vertical))
                g.FillRectangle(bg, shell);
            using (Pen p = new Pen(ShellBorder, Math.Max(1, border)))
                g.DrawRectangle(p, shell.X, shell.Y, shell.Width - 1, shell.Height - 1);

            // header
            if (!plan.HeaderRect.IsEmpty)
            {
                Rectangle header = Offset(plan.HeaderRect, ox, oy);
                using (SolidBrush b = new SolidBrush(HeaderBg))
                    g.FillRectangle(b, header);
                using (Pen sep = new Pen(HeaderSep, 1f))
                    g.DrawLine(sep, header.Left, header.Bottom - 1,
                        header.Right, header.Bottom - 1);

                int padL = NativeTooltipLayout.Px(
                    NativeTooltipLayout.PinnedHeaderPadLBase, scale);
                int padR = NativeTooltipLayout.Px(
                    NativeTooltipLayout.PinnedHeaderPadRBase, scale);
                int gap = NativeTooltipLayout.Px(
                    NativeTooltipLayout.PinnedHeaderGapBase, scale);

                // close 24×22（含 1px 边 + 6% 白底 + ×）
                Rectangle close = Offset(plan.CloseRect, ox, oy);
                int pressDy = _closePressed ? 1 : 0;
                Rectangle closeDraw = close;
                closeDraw.Offset(0, pressDy);
                using (SolidBrush cb = new SolidBrush(CloseBg))
                    g.FillRectangle(cb, closeDraw);
                using (Pen cp = new Pen(CloseBorder, 1f))
                    g.DrawRectangle(cp, closeDraw.X, closeDraw.Y,
                        closeDraw.Width - 1, closeDraw.Height - 1);
                using (StringFormat csf = new StringFormat(StringFormat.GenericTypographic)
                {
                    Alignment = StringAlignment.Center,
                    LineAlignment = StringAlignment.Center,
                    FormatFlags = StringFormatFlags.NoWrap
                })
                using (SolidBrush ct = new SolidBrush(TextDefault))
                    g.DrawString("×", _fontClose, ct, closeDraw, csf);

                // keycap "Esc"（close 左侧）
                int keyPadX = NativeTooltipLayout.Px(
                    NativeTooltipLayout.PinnedKeycapPadXBase, scale);
                int keyPadY = NativeTooltipLayout.Px(
                    NativeTooltipLayout.PinnedKeycapPadYBase, scale);
                Size keyText = TextRenderer.MeasureText("Esc", _fontKeycap,
                    new Size(int.MaxValue, int.MaxValue), TextFormatFlags.NoPadding);
                int keyW = Math.Max(keyText.Width + keyPadX * 2,
                    NativeTooltipLayout.Px(18, scale));
                int keyH = keyText.Height + keyPadY * 2;
                Rectangle keycap = new Rectangle(
                    close.X - gap - keyW,
                    header.Y + (header.Height - keyH) / 2,
                    keyW, keyH);
                using (Pen kp = new Pen(KeycapBorder, 1f))
                    g.DrawRectangle(kp, keycap.X, keycap.Y, keycap.Width - 1, keycap.Height - 1);
                using (StringFormat ksf = new StringFormat(StringFormat.GenericTypographic)
                {
                    Alignment = StringAlignment.Center,
                    LineAlignment = StringAlignment.Center,
                    FormatFlags = StringFormatFlags.NoWrap
                })
                using (SolidBrush kt = new SolidBrush(KeycapText))
                    g.DrawString("Esc", _fontKeycap, kt, keycap, ksf);

                // title（左对齐，省略截断）
                Rectangle titleRect = new Rectangle(
                    header.X + padL, header.Y,
                    Math.Max(0, keycap.X - gap - header.X - padL), header.Height);
                using (SolidBrush tb = new SolidBrush(TextDefault))
                using (StringFormat tsf = new StringFormat(StringFormat.GenericTypographic)
                {
                    FormatFlags = StringFormatFlags.NoWrap,
                    Trimming = StringTrimming.EllipsisCharacter,
                    LineAlignment = StringAlignment.Center
                })
                {
                    g.DrawString(plan.Title ?? "", _fontHeaderTitle, tb, titleRect, tsf);
                }
            }

            // body（裁剪 + 行偏移滚动）
            Rectangle body = Offset(plan.BodyRect, ox, oy);
            GraphicsState bodyState = g.Save();
            try
            {
                g.SetClip(body);
                int bodyPad = NativeTooltipLayout.Px(
                    NativeTooltipLayout.PinnedBodyPadBase, scale);
                int scrollY = ScrollOffsetPx(plan, _scrollLine);

                // intro 面板（grid：icon 列 + 文本列）
                Rectangle intro = Offset(plan.PinnedIntroRect, body.X, body.Y - scrollY);
                if (intro.Height > 0 && intro.Bottom > body.Y && intro.Top < body.Bottom)
                {
                    DrawGradientPanel(g, intro);
                    if (!plan.PinnedIconRect.IsEmpty)
                    {
                        Rectangle iconRect = Offset(plan.PinnedIconRect,
                            intro.X, intro.Y);
                        DrawIcon(g, iconRect, plan.IconName, intro);
                    }
                    PaintLines(g, plan.IntroLines, 0, plan.IntroLines.Count,
                        intro.X + plan.PinnedTextX, intro.Y + plan.PinnedTextY,
                        0, intro); // per-line 行高
                }
                // desc 面板（split 时独立全宽）
                if (!plan.PinnedDescRect.IsEmpty)
                {
                    Rectangle desc = Offset(plan.PinnedDescRect, body.X, body.Y - scrollY);
                    DrawGradientPanel(g, desc);
                    int firstDesc = plan.IntroLines.Count;
                    PaintLines(g, plan.DescLines, firstDesc,
                        plan.DescLines.Count - firstDesc,
                        desc.X + bodyPad, desc.Y + bodyPad, 0, desc);
                }
            }
            finally { g.Restore(bodyState); }

            if (plan.DescScrollable)
                DrawScrollbar(g, body, plan.DescTotalLines,
                    plan.DescVisibleLines, _scrollLine, plan.MaxScrollLine, scale,
                    NativeTooltipLayout.Px(NativeTooltipLayout.PinnedScrollbarWBase, scale));
        }

        /// <summary>pinned body 的行偏移 → 像素（变行高浮点累加：intro 1.4 /
        /// desc 1.45，行内大字号 run 再按 line box 抬高；出口取整一次）。</summary>
        private static int ScrollOffsetPx(NativeTooltipLayout.Plan plan, int startLine)
        {
            float y = 0;
            int n = Math.Min(startLine, plan.DescLines.Count);
            for (int i = 0; i < n; i++)
            {
                NativeTooltipLayout.VisualLine l = plan.DescLines[i];
                y += l.LineHeightF > 0 ? l.LineHeightF : l.LineHeightPx;
            }
            return (int)Math.Round(y);
        }

        /// <summary>--tt-bg：灰族垂直渐变，无边框无阴影（Symbol 274 复刻默认主题）。</summary>
        private static void DrawGradientPanel(Graphics g, Rectangle rect)
        {
            if (rect.Width <= 0 || rect.Height <= 0) return;
            using (LinearGradientBrush b = new LinearGradientBrush(
                rect, GradTop, GradBot, LinearGradientMode.Vertical))
            {
                b.WrapMode = WrapMode.Tile;
                g.FillRectangle(b, rect);
            }
        }

        private void PaintLines(Graphics g, List<NativeTooltipLayout.VisualLine> lines,
            int startLine, int maxLines, int x, int y, int lineH, Rectangle? clip)
        {
            if (lines == null || maxLines <= 0) return;
            GraphicsState state = g.Save();
            try
            {
                if (clip.HasValue) g.SetClip(clip.Value);
                int count = Math.Min(lines.Count - startLine, maxLines);
                float cy = y;
                for (int i = 0; i < count; i++)
                {
                    NativeTooltipLayout.VisualLine vl = lines[startLine + i];
                    // 逐行真实高优先（CSS line box：行内最大 run 字号×em——
                    // 大字行物理高 25×scale，不再被常量 15×scale 压叠）；
                    // 外部常量只在行无高度数据时兜底。
                    float lh = vl.LineHeightF > 0 ? vl.LineHeightF
                        : (lineH > 0 ? lineH
                            : (vl.LineHeightPx > 0 ? vl.LineHeightPx : 1));
                    if (!vl.IsBlank)
                    {
                        float cx = x;
                        for (int s = 0; s < vl.Slices.Count; s++)
                        {
                            NativeTooltipLayout.VisualLine.Slice slice = vl.Slices[s];
                            if (string.IsNullOrEmpty(slice.Text)) continue;
                            Color color = slice.Color.HasValue ? slice.Color.Value : TextDefault;
                            using (SolidBrush brush = new SolidBrush(color))
                            {
                                g.DrawString(slice.Text, FontFor(slice.FontOf()),
                                    brush, new PointF(cx, cy), _textFormat);
                            }
                            cx += slice.WidthF;
                        }
                    }
                    cy += lh;
                }
            }
            finally { g.Restore(state); }
        }

        /// <summary>
        /// 图标：Web mix-blend-mode:overlay 等价实现——先把 icon 缩放到目标框，
        /// 再与面板渐变（icon 区域那段的底色）逐像素 overlay 合成。
        /// overlay: 底色&lt;0.5 → 2*b*s；否则 1-2(1-b)(1-s)。源 alpha 作为混合权重。
        /// </summary>
        private void DrawIcon(Graphics g, Rectangle rect, string iconName, Rectangle panelRect)
        {
            Bitmap frame = null;
            if (_icons != null && !string.IsNullOrEmpty(iconName))
            {
                LootIconCatalog.LootIconFrames frames;
                if (_icons.TryGet(iconName, out frames) && frames != null)
                    frame = frames.First;
            }
            if (frame == null)
            {
                // manifest 未命中 / catalog 缺席 → .flash-tt-icon-placeholder：
                // rgba(255,255,255,.03) 底 + 1px 虚线 divider 色框
                using (SolidBrush b = new SolidBrush(IconPlaceholderBg))
                    g.FillRectangle(b, rect);
                using (Pen p = new Pen(Divider, 1f))
                {
                    p.DashStyle = DashStyle.Dash;
                    g.DrawRectangle(p, rect.X, rect.Y, rect.Width - 1, rect.Height - 1);
                }
                return;
            }

            // 合成键：icon 名 + 框尺寸 + 面板高（渐变相位依赖面板高度）
            string key = iconName + "|" + rect.Width + "x" + rect.Height
                + "|" + panelRect.Y + "-" + panelRect.Height;
            Bitmap composed = _blendCache;
            if (composed == null || _blendCacheKey != key
                || composed.Width != rect.Width || composed.Height != rect.Height)
            {
                if (_blendCache != null) _blendCache.Dispose();
                _blendCache = composed = ComposeOverlay(frame, rect, panelRect);
                _blendCacheKey = key;
            }
            g.DrawImageUnscaled(composed, rect.X, rect.Y);
        }

        /// <summary>生成 icon 与面板渐变的 overlay 合成位图（含 icon 自身 alpha）。</summary>
        private static Bitmap ComposeOverlay(Bitmap frame, Rectangle rect, Rectangle panelRect)
        {
            int w = Math.Max(1, rect.Width), h = Math.Max(1, rect.Height);
            Bitmap scaled = new Bitmap(w, h, PixelFormat.Format32bppArgb);
            using (Graphics sg = Graphics.FromImage(scaled))
            {
                sg.InterpolationMode = InterpolationMode.HighQualityBicubic;
                sg.DrawImage(frame, 0, 0, w, h);
            }
            Bitmap output = new Bitmap(w, h, PixelFormat.Format32bppArgb);
            BitmapData sd = scaled.LockBits(
                new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            BitmapData od = output.LockBits(
                new Rectangle(0, 0, w, h), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
            try
            {
                int panelH = Math.Max(1, panelRect.Height);
                byte[] src = new byte[sd.Stride * h];
                byte[] dst = new byte[od.Stride * h];
                System.Runtime.InteropServices.Marshal.Copy(sd.Scan0, src, 0, src.Length);
                for (int y = 0; y < h; y++)
                {
                    // 底色 = 面板渐变在本行的颜色（GDI 32bppArgb 为 B,G,R,A 序）
                    float t = (rect.Y - panelRect.Y + y) / (float)panelH;
                    if (t < 0) t = 0; if (t > 1) t = 1;
                    int br = (int)(153 + (51 - 153) * t + 0.5f);
                    for (int x = 0; x < w; x++)
                    {
                        int i = y * sd.Stride + x * 4;
                        int sa = src[i + 3];
                        for (int ch = 0; ch < 3; ch++)
                        {
                            int s = src[i + ch];
                            // overlay(b,s)
                            float ov = br < 128
                                ? 2f * br * s / 255f
                                : 255f - 2f * (255 - br) * (255 - s) / 255f;
                            float outc = br + (ov - br) * (sa / 255f);
                            dst[i + ch] = (byte)Math.Max(0, Math.Min(255, (int)(outc + 0.5f)));
                        }
                        dst[i + 3] = 255;
                    }
                }
                System.Runtime.InteropServices.Marshal.Copy(dst, 0, od.Scan0, dst.Length);
            }
            finally
            {
                scaled.UnlockBits(sd);
                output.UnlockBits(od);
                scaled.Dispose();
            }
            return output;
        }

        /// <summary>
        /// dense 检视状态条（.panel-tooltip-inspection-status 复刻）：
        /// 底 = 90deg 渐变 accent 17/19%（over --tt-status-bg）→ 4/5% → transparent；
        /// 左边条 2px accent；底边 1px text 14%；圆点 6px；文案 11px/600 白 88%；
        /// pending 附 72×2 进度槽（web 为 scaleX 0→1 动画，native 按
        /// 1 - remaining/1000ms 直接取当前进度）。
        /// inspect = 折叠稳态：只画渐变底 + 左边条（圆点/文案已淡出、meter display:none）。
        /// </summary>
        private void PaintInspectionStrip(Graphics g, Rectangle strip,
            string state, float scale)
        {
            if (strip.Width <= 0 || strip.Height <= 0) return;
            bool pending = state == NativeTooltipLayout.InspStatePending;
            Color accent = pending ? InspPending : InspAccept;

            Color c0 = MixOver(accent, InspStatusBg, pending ? 0.17 : 0.19);
            Color c1 = MixOver(accent, InspStatusBg, pending ? 0.04 : 0.05);
            using (LinearGradientBrush bg = new LinearGradientBrush(
                strip, c0, Color.FromArgb(0, c1), LinearGradientMode.Horizontal))
            {
                ColorBlend blend = new ColorBlend(3);
                blend.Positions = new float[] { 0f, 0.72f, 1f };
                blend.Colors = new Color[] { c0, c1, Color.FromArgb(0, c1) };
                bg.InterpolationColors = blend;
                g.FillRectangle(bg, strip);
            }
            // 左边条：pending accent 82% / inspect accent 88%
            int border = NativeTooltipLayout.Px(NativeTooltipLayout.InspBorderLBase, scale);
            using (SolidBrush eb = new SolidBrush(Color.FromArgb(
                pending ? 209 : 225, accent)))
                g.FillRectangle(eb, strip.X, strip.Y, border, strip.Height);
            if (!pending) return;

            // 底边 1px text 14%
            using (SolidBrush bb = new SolidBrush(Color.FromArgb(36, 255, 255, 255)))
                g.FillRectangle(bb, strip.X, strip.Bottom - 1, strip.Width, 1);

            int padX = NativeTooltipLayout.Px(NativeTooltipLayout.InspPadXBase, scale);
            int gap = NativeTooltipLayout.Px(NativeTooltipLayout.InspGapBase, scale);
            int meterW = NativeTooltipLayout.Px(NativeTooltipLayout.InspMeterWBase, scale);
            int meterX = strip.Right - padX - meterW;

            // 圆点 6px accent 86%（CSS box-shadow 辉光无 GDI 对应物，略）
            int dot = NativeTooltipLayout.Px(NativeTooltipLayout.InspDotBase, scale);
            int dotX = strip.X + border + padX;
            using (SolidBrush db = new SolidBrush(Color.FromArgb(219, InspPending)))
                g.FillEllipse(db, dotX, strip.Y + (strip.Height - dot) / 2, dot, dot);

            // 文案 11px w600 白 88%（_fontHeaderTitle = 11px Bold）
            int labelX = dotX + dot + gap;
            using (SolidBrush tb = new SolidBrush(Color.FromArgb(224, 255, 255, 255)))
            using (StringFormat sf = new StringFormat(StringFormat.GenericTypographic)
            {
                FormatFlags = StringFormatFlags.NoWrap | StringFormatFlags.NoClip,
                LineAlignment = StringAlignment.Center
            })
            {
                g.DrawString(NativeTooltipLayout.InspPendingLabel, _fontHeaderTitle, tb,
                    new Rectangle(labelX, strip.Y,
                        Math.Max(0, meterX - gap - labelX), strip.Height), sf);
            }

            // 进度槽 72×2 accent 82%：web 动画 scaleX 0→1 over remainingMs
            // （--wb-motion-busy = 1000ms = 默认检视停顿时长）
            int mh = NativeTooltipLayout.Px(NativeTooltipLayout.InspMeterHBase, scale);
            double frac = 1.0 - Math.Min(1.0,
                _inspectionRemainingMs / (double)InspDelayMs);
            using (SolidBrush mb = new SolidBrush(Color.FromArgb(209, InspPending)))
                g.FillRectangle(mb, meterX,
                    strip.Y + (strip.Height - mh) / 2,
                    Math.Max(0, (int)Math.Round(meterW * frac)), mh);
        }

        /// <summary>color-mix(in srgb, accent p%, base) 展开（base 不透明 → 结果不透明）。</summary>
        private static Color MixOver(Color accent, Color baseColor, double p)
        {
            return Color.FromArgb(255,
                (int)(accent.R * p + baseColor.R * (1 - p) + 0.5),
                (int)(accent.G * p + baseColor.G * (1 - p) + 0.5),
                (int)(accent.B * p + baseColor.B * (1 - p) + 0.5));
        }

        /// <summary>
        /// ownerRect 缺失时的滚轮边界：Flash 客户区屏幕矩形（root 约定缺省至少
        /// 限定客户区，不全屏吞轮）。无 handle 时退化为布局同域的 client 原点矩形。
        /// </summary>
        private Rectangle AnchorScreenClientRect()
        {
            if (_anchor.IsHandleCreated)
            {
                try
                {
                    return new Rectangle(_anchor.PointToScreen(Point.Empty),
                        _anchor.ClientSize);
                }
                catch { }
            }
            return new Rectangle(Point.Empty, _anchor.ClientSize);
        }

        /// <summary>
        /// ::-webkit-scrollbar 复刻：轨道 = 面板右缘整高 6px 半透明深色；
        /// 滑块 min-height 28px、1px 描边、radius 1px。
        /// </summary>
        private void DrawScrollbar(Graphics g, Rectangle panelRect,
            int totalLines, int visibleLines, int scrollLine, int maxScrollLine, float scale, int sbW)
        {
            if (maxScrollLine <= 0 || panelRect.Height < 8) return;
            int w = Math.Max(2, sbW);
            int trackX = panelRect.Right - w;
            using (SolidBrush track = new SolidBrush(ScrollTrack))
                g.FillRectangle(track, trackX, panelRect.Top, w, panelRect.Height);
            int thumbMin = NativeTooltipLayout.Px(
                NativeTooltipLayout.ScrollThumbMinHBase, scale);
            int thumbH = Math.Min(panelRect.Height, Math.Max(thumbMin,
                (int)Math.Round(panelRect.Height * (double)visibleLines / Math.Max(1, totalLines))));
            int travel = Math.Max(0, panelRect.Height - thumbH);
            // 部分可见行/变行高使 MaxStartLine 不等于 total-visible。
            // 使用真实滚动上限，否则滚到底时滑块会画到面板外。
            int thumbY = panelRect.Top + (int)Math.Round(travel * (double)scrollLine
                / maxScrollLine);
            using (SolidBrush thumb = new SolidBrush(ScrollThumb))
                g.FillRectangle(thumb, trackX, thumbY, w, thumbH);
            using (Pen border = new Pen(ScrollThumbBorder, 1f))
                g.DrawRectangle(border, trackX, thumbY, w - 1, thumbH - 1);
        }

        private static Rectangle Offset(Rectangle r, int dx, int dy)
        {
            return new Rectangle(r.X + dx, r.Y + dy, r.Width, r.Height);
        }

        #endregion

        #region 内部实现

        private bool CloseHit(Point local)
        {
            return !_plan.CloseRect.IsEmpty && _plan.CloseRect.Contains(local);
        }

        private void Clear()
        {
            CancelPointerMove();
            _livePointer = null;
            _doc = null;
            _plan = null;
            _scrollLine = 0;
            _closePressed = false;
            _lockedSide = null;
            _anchorValid = false;
            _ownerBounds = null;
            _inspectionState = "idle";
            _inspectionRemainingMs = 0;
            FireBounds();
            FireRepaint();
        }

        /// <summary>
        /// 宿主窗口 DPI 缩放（物理 px / 视口 CSS px）：默认 anchor.DeviceDpi/96f
        /// （owner 窗口 per-monitor DPI，非全局 system DPI）；provider 注入值、
        /// 无 handle / 异常 / 非正值一律兜底 1f。
        /// </summary>
        private float CurrentDpiScale()
        {
            float dpi;
            try
            {
                dpi = _dpiScaleProvider != null
                    ? _dpiScaleProvider() : _anchor.DeviceDpi / 96f;
            }
            catch { dpi = 1f; }
            if (float.IsNaN(dpi) || float.IsInfinity(dpi) || dpi <= 0f) dpi = 1f;
            return dpi;
        }

        /// <summary>
        /// Web 缩放（物理 px / tooltip 本地 CSS px）：
        /// --cf7-overlay-scale 在 CSS px 域 clamp 为 max(0.25, innerHeight/864)，
        /// 再经 DPI 落到物理 = max(0.25×dpi, clientH/864)。viewport 用宿主整个
        /// client 矩形（=innerWidth/innerHeight×dpi），不是 Flash letterbox。
        /// </summary>
        private float CurrentScale()
        {
            int h = _anchor.ClientSize.Height;
            if (h <= 0) return 1f;
            return Math.Max(WebMinScale * CurrentDpiScale(), h / WebDesignHeight);
        }

        private void EnsureFonts(float scale)
        {
            if (Math.Abs(scale - _lastFontScale) < 0.01f
                && _fontBody != null && _fontBold != null) return;
            _lastFontScale = scale;
            DisposeFonts();
            _fontBody = NativeHudFonts.CreateRoleFont(TooltipFontRole,
                BodyFontBase * scale, FontStyle.Regular, GraphicsUnit.Pixel);
            _fontBold = NativeHudFonts.CreateRoleFont(TooltipFontRole,
                BodyFontBase * scale, FontStyle.Bold, GraphicsUnit.Pixel);
            _fontHeaderTitle = NativeHudFonts.CreateRoleFont(TooltipFontRole,
                PinnedTitleFontBase * scale, FontStyle.Bold, GraphicsUnit.Pixel);
            _fontKeycap = NativeHudFonts.CreateRoleFont(TooltipFontRole,
                PinnedKeycapFontBase * scale, FontStyle.Regular, GraphicsUnit.Pixel);
            _fontClose = NativeHudFonts.CreateRoleFont(TooltipFontRole,
                PinnedCloseFontBase * scale, FontStyle.Regular, GraphicsUnit.Pixel);
            _measureCache.Clear();
        }

        private void DisposeFonts()
        {
            if (_fontBody != null) { _fontBody.Dispose(); _fontBody = null; }
            if (_fontBold != null) { _fontBold.Dispose(); _fontBold = null; }
            if (_fontHeaderTitle != null) { _fontHeaderTitle.Dispose(); _fontHeaderTitle = null; }
            if (_fontKeycap != null) { _fontKeycap.Dispose(); _fontKeycap = null; }
            if (_fontClose != null) { _fontClose.Dispose(); _fontClose = null; }
            foreach (Font f in _styledFonts.Values) f.Dispose();
            _styledFonts.Clear();
        }

        /// <summary>与绘制完全同源的测量：Graphics.MeasureString + 同一 _textFormat。</summary>
        private Graphics MeasureGraphics
        {
            get
            {
                if (_measureG == null)
                {
                    _measureBmp = new Bitmap(1, 1);
                    _measureG = Graphics.FromImage(_measureBmp);
                    _measureG.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
                }
                return _measureG;
            }
        }

        /// <summary>
        /// run.fontFace（sanitizer 别名）→ 字体目录 roleId。
        /// 有效基线对齐（root-font-probe 2026-09-12 Edge DOM 实证）：legacy Web
        /// 的 FONT FACE 产出畸形引号 style——font-family:"MS Mincho", serif
        /// 被 HTML 解析成属性碎片，MS Mincho/Fixedsys 实际被忽略，computed
        /// family 仍是 Microsoft YaHei；web document 适配器同样有效回退。
        /// 故 legacy 别名当前一律渲染为 TooltipFontRole——FontFace 语义字段
        /// 仍保留在 run/slice 上供 parity 核对，不向 GDI+ 传无效字体名；
        /// catalog 的 legacy.tooltip.* 角色留待真正接入原生字体时再启用。
        /// </summary>
        private static string MapFontFace(string face)
        {
            if (face == null) return null;
            switch (face.Trim().ToLowerInvariant())
            {
                case "ms mincho":
                case "fixedsys":
                    return TooltipFontRole;
                default:
                    return null;
            }
        }

        /// <summary>slice 字体：缺省样式走 _fontBody/_fontBold；带 run 样式字段时按
        /// role+字号（CSS px×scale）+FontStyle 建缓存字体。FontFace 当前不改变
        /// 渲染字体（有效基线=正文体，见 MapFontFace），不计 styled。</summary>
        private Font FontFor(NativeTooltipLayout.RunFont f)
        {
            bool styled = f.Italic || f.Underline || f.FontSize.HasValue;
            if (!styled) return f.Bold ? _fontBold : _fontBody;
            string role = MapFontFace(f.FontFace) ?? TooltipFontRole;
            float size = (f.FontSize.HasValue ? f.FontSize.Value : BodyFontBase)
                * CurrentScale();
            FontStyle style = FontStyle.Regular;
            if (f.Bold) style |= FontStyle.Bold;
            if (f.Italic) style |= FontStyle.Italic;
            if (f.Underline) style |= FontStyle.Underline;
            string key = role + "|" + size.ToString("0.###",
                System.Globalization.CultureInfo.InvariantCulture) + "|" + (int)style;
            Font cached;
            if (_styledFonts.TryGetValue(key, out cached)) return cached;
            Font font = NativeHudFonts.CreateRoleFont(role, size, style,
                GraphicsUnit.Pixel);
            _styledFonts[key] = font;
            return font;
        }

        private int MeasureText(string text, NativeTooltipLayout.RunFont font)
        {
            string key = (font.Bold ? "b" : "r")
                + (font.Italic ? "i" : "")
                + (font.Underline ? "u" : "")
                + (font.FontSize.HasValue ? "s" + font.FontSize.Value : "")
                + (font.FontFace != null ? "f" + font.FontFace : "")
                + ":" + text;
            int w;
            if (_measureCache.TryGetValue(key, out w)) return w;
            float mw = MeasureGraphics.MeasureString(text, FontFor(font),
                PointF.Empty, _textFormat).Width;
            w = (int)Math.Ceiling(mw);
            _measureCache[key] = w;
            return w;
        }

        private void InvalidateLayout()
        {
            _lastLayoutScale = -1f;
            if (Visible)
            {
                EnsureLayout(false);
                FireBounds();
                FireRepaint();
            }
        }

        /// <summary>确保 _plan/_placedRect 与当前 doc、缩放、视口、DPI 一致。</summary>
        private void EnsureLayout(bool force)
        {
            if (_doc == null) { _plan = null; return; }
            float dpi = CurrentDpiScale();
            float scale = CurrentScale();
            // viewport = 宿主窗口 client 矩形物理 px（=Web innerWidth/innerHeight
            // ×dpi），不是 Flash letterbox——与 positionFloating 的 vw/vh 对齐。
            int vpWi = Math.Max(1, _anchor.ClientSize.Width);
            int vpHi = Math.Max(1, _anchor.ClientSize.Height);

            // 无 handle 时 PointToScreen 会把控件挂到 WinForms parking window，
            // 返回任意原点——此时布局退化为 anchor 客户区坐标域（原点 0,0），
            // 与 hudOrigin=Empty 的绘制画布保持一致（fixture/早期 show 路径）。
            bool mapped = _anchor.IsHandleCreated;
            Point vpOrigin = Point.Empty;
            if (mapped)
            {
                try { vpOrigin = _anchor.PointToScreen(Point.Empty); } catch { mapped = false; }
            }
            Rectangle viewport = new Rectangle(vpOrigin.X, vpOrigin.Y, vpWi, vpHi);

            bool anchorChanged = false;
            if (_livePointer.HasValue)
            {
                Point pointer = _livePointer.Value;
                anchorChanged = !_anchorValid || _anchorScreen != pointer;
                _anchorScreen = pointer;
                _anchorValid = true;
            }
            else if (_doc.HasAnchor)
            {
                int sx, sy;
                if (mapped)
                {
                    _mapper.FlashToScreen(_doc.AnchorX, _doc.AnchorY, out sx, out sy);
                }
                else
                {
                    // 无 handle：Flash 舞台坐标按比例落到 client 域（letterbox 含内）
                    float vpX, vpY, vpW, vpH;
                    _mapper.CalcViewport(out vpX, out vpY, out vpW, out vpH);
                    sx = (int)(vpX + _doc.AnchorX / StageW * vpW);
                    sy = (int)(vpY + _doc.AnchorY / StageH * vpH);
                }
                if (!_anchorValid || _anchorScreen.X != sx || _anchorScreen.Y != sy)
                {
                    _anchorScreen = new Point(sx, sy);
                    _anchorValid = true;
                    anchorChanged = true;
                }
            }
            else if (!_anchorValid)
            {
                // 无锚点：视口中心
                _anchorScreen = new Point(viewport.X + viewport.Width / 2, viewport.Y + viewport.Height / 2);
                _anchorValid = true;
                anchorChanged = true;
            }

            // DPI 变化不改变 scale（同一物理高下 scale 不变），必须独立跟踪：
            // vh/vw 与定位常量的 CSS px 域 = 物理视口 / dpi。
            bool scaleChanged = Math.Abs(scale - _lastLayoutScale) > 0.001f
                || Math.Abs(dpi - _lastDpiScale) > 0.001f
                || vpWi != _lastVpW || vpHi != _lastVpH;
            if (force || _plan == null || scaleChanged)
            {
                EnsureFonts(scale);
                _lastLayoutScale = scale;
                _lastDpiScale = dpi;
                _lastVpW = vpWi;
                _lastVpH = vpHi;
                // 基准行高保持浮点（12×1.25×scale，如 576 高 → 10，864 高 → 15）——
                // 行内更大 run 字号按 CSS line box 逐行抬高，取整只发生在矩形上。
                float lineH = NativeTooltipLayout.FontPxBase
                    * NativeTooltipLayout.LineHeightEm * scale;
                _plan = NativeTooltipLayout.ComputePlan(
                    _doc, MeasureText, lineH, scale, vpWi, vpHi, _inspectionState, dpi);
                if (_scrollLine > (_plan != null ? _plan.MaxScrollLine : 0))
                    _scrollLine = _plan != null ? _plan.MaxScrollLine : 0;
                anchorChanged = true;
            }
            if (_plan == null) return;
            Rectangle placementAnchor = new Rectangle(_anchorScreen, Size.Empty);
            if (_doc.AnchorRect.HasValue)
            {
                RectangleF logical = _doc.AnchorRect.Value;
                int left, top, right, bottom;
                if (mapped)
                {
                    _mapper.FlashToScreen(logical.Left, logical.Top, out left, out top);
                    _mapper.FlashToScreen(logical.Right, logical.Bottom, out right, out bottom);
                }
                else
                {
                    float vx, vy, vw, vh;
                    _mapper.CalcViewport(out vx, out vy, out vw, out vh);
                    left = (int)(vx + logical.Left / StageW * vw);
                    top = (int)(vy + logical.Top / StageH * vh);
                    right = (int)(vx + logical.Right / StageW * vw);
                    bottom = (int)(vy + logical.Bottom / StageH * vh);
                }
                placementAnchor = Rectangle.FromLTRB(left, top, right, bottom);
            }
            if (placementAnchor != _placementAnchorRect) anchorChanged = true;
            _placementAnchorRect = placementAnchor;
            if (anchorChanged || _placedRect.IsEmpty)
            {
                string side;
                _placedRect = NativeTooltipLayout.SolvePlacement(
                    _placementAnchorRect, _anchorScreen, _plan.TipSize, viewport,
                    _lockedSide, _doc.PlacementHint, dpi,
                    _doc.Profile == NativeTooltipProfile.Pinned, out side);
                _lockedSide = side;
                _plan.Side = side;   // parity-compare 提案 C：side 只读公开
            }
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

        public void Dispose()
        {
            _pointerMoveTimer.Dispose();
            DisposeFonts();
            if (_blendCache != null) { _blendCache.Dispose(); _blendCache = null; }
            if (_measureG != null) { _measureG.Dispose(); _measureG = null; }
            if (_measureBmp != null) { _measureBmp.Dispose(); _measureBmp = null; }
            if (_textFormat != null) _textFormat.Dispose();
        }

        #endregion
    }
}
