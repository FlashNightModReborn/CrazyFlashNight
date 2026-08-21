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
    /// 收敛后的右侧组合 HUD：六入口常驻动作行 + 条件状态槽 + 可选地图预览。
    /// 业务命令仍全部通过 LauncherCommandRouter.Dispatch，不在 widget 内复制业务分支。
    /// </summary>
    public class RightContextWidget : INativeHudWidget, INativeHudCompositeBoundsProvider, IUiDataConsumer, IUiDataLegacyConsumer, IDisposable
    {
        private const int NOTICE_MS = 5000;
        private const int ICON_W_BASE = 28;
        private const int NOTICE_TEXT_PAD_BASE = 8;
        private const int NOTICE_ARROW_W_BASE = 24;
        private const int MAP_BODY_INSET_BASE = 8;
        private const int MAP_LABEL_PAD_X_BASE = 6;
        private const int MAP_LABEL_PAD_Y_BASE = 2;
        private const int MAP_BEACON_R_BASE = 5;
        private const float MIN_BLOCK_PX = 4f;

        private const string ICON_TASK_DONE = "❗";
        private const string ICON_PLACEHOLDER = "◆";

        private static readonly string[] TOOL_KEYS = { "TASK_MAP", "TASK_UI", "EQUIP_UI", "GAMESETTINGS", "PAUSE", "SAFEEXIT" };
        private static readonly string[] TOOL_LABELS_DEFAULT = { "地图", "任务", "装备", "⚙", "Ⅱ", "×" };
        private static readonly string[] TOOL_LABELS_PAUSED = { "地图", "任务", "装备", "⚙", "▶", "×" };
        private static readonly string[] TOOL_TOOLTIPS =
        {
            "打开完整地图；显示模式在刘海",
            "打开任务面板",
            "打开角色构筑；其他整备功能在刘海或装备页",
            "打开系统设置",
            "暂停游戏",
            "安全退出"
        };
        private const int IDX_PAUSE = 4;

        private static readonly string[] LEGACY_TYPES = { "task", "announce" };

        private enum HitKind
        {
            None,
            Tool,
            MapCard,
            MapDisplayToggle,
            Notice
        }

        private struct HitInfo
        {
            public HitKind Kind;
            public int Index;
        }

        private enum NoticeMode { Idle, Flash, TaskDone }

        private class FlashItem
        {
            public string Text;
            public string Icon;
        }

        private readonly Control _anchor;
        private readonly LauncherCommandRouter _router;
        private readonly MapHudDataCatalog _catalog;
        private readonly FlashCoordinateMapper _mapper;

        private volatile bool _gameReady;
        private volatile bool _paused;
        private volatile RightContextSlotOwner _slotOwner = RightContextSlotOwner.Hidden;

        // AS2 mm 运行态只负责玩法语义；显示偏好与派生态必须独立，禁止互相覆盖。
        private RuntimeMapMode _runtimeMapMode = RuntimeMapMode.None;
        private MapDisplayPreference _mapDisplayPreference;
        private EffectiveMapDisplayMode _effectiveMapDisplayMode = EffectiveMapDisplayMode.Hidden;
        private bool _tacticalMapDataAvailable;
        private string _mapHotspotId = "";
        private MapHudHotspotEntry _mapEntry;
        private readonly Action<MapDisplayPreference> _onMapDisplayPreferenceChanged;

        private volatile bool _taskDone;
        private volatile bool _navigable;
        private string _deliverHotspotId = "";

        private readonly Queue<FlashItem> _flashQueue = new Queue<FlashItem>();
        private readonly object _flashLock = new object();
        private FlashItem _activeFlash;
        private int _flashElapsedMs;
        private string _noticeText = "";
        private string _noticeIcon = ICON_PLACEHOLDER;

        private HitInfo _hover;
        private HitInfo _down;

        // ── P0 perf：GDI+ 资源静态/实例缓存 ──
        // PaintTools / PaintMapLabel / PaintNotice 的稳定 GDI+ 资源复用。
        // SolidBrush + Font + StringFormat 每帧；30Hz 下整 widget 触发数百个 GDI+ 对象创建。
        // 静态化后：
        //   - 文本颜色 const 的 SolidBrush 进程级共享（不 dispose）
        //   - StringFormat 4 种 shape 静态共享
        //   - Font 实例缓存按 (family,size,style) 三元组复用，scale 变化时整体重建
        //
        // hover/theme-color 分支的 brush 仍按需分配（频率低且需要 alpha/color 注入）。

        // 文本与容器颜色常量
        private static readonly Color C_TOOLS_FG          = NativeHudTheme.TextSecondary;
        private static readonly Color C_TOOLS_FG_HOVER    = NativeHudTheme.TextPrimary;
        private static readonly Color C_TOOLS_FG_PAUSED   = NativeHudTheme.Danger;
        private static readonly Color C_QUEST_FG          = NativeHudTheme.TextSecondary;
        private static readonly Color C_LABEL_TEXT        = NativeHudTheme.TextPrimary;

        // 静态文本 SolidBrush（非动态 alpha/color；进程级共享）
        private static readonly SolidBrush BR_TOOLS_FG          = new SolidBrush(C_TOOLS_FG);
        private static readonly SolidBrush BR_TOOLS_FG_HOVER    = new SolidBrush(C_TOOLS_FG_HOVER);
        private static readonly SolidBrush BR_TOOLS_FG_PAUSED   = new SolidBrush(C_TOOLS_FG_PAUSED);
        private static readonly SolidBrush BR_QUEST_FG          = new SolidBrush(C_QUEST_FG);
        private static readonly SolidBrush BR_LABEL_TEXT        = new SolidBrush(C_LABEL_TEXT);

        // 静态 StringFormat（共享；GDI+ 文档允许多线程读，但本项目 paint 都是 UI 线程）
        private static readonly StringFormat FMT_CENTER       = MakeFmt(StringAlignment.Center, StringAlignment.Center, StringFormatFlags.NoClip, StringTrimming.None);
        private static readonly StringFormat FMT_CENTER_ELLIPSIS = MakeFmt(StringAlignment.Center, StringAlignment.Center, StringFormatFlags.NoClip, StringTrimming.EllipsisCharacter);
        private static readonly StringFormat FMT_NEAR_NOWRAP_ELLIPSIS = MakeFmt(StringAlignment.Near, StringAlignment.Center, StringFormatFlags.NoWrap, StringTrimming.EllipsisCharacter);

        private static StringFormat MakeFmt(StringAlignment h, StringAlignment v, StringFormatFlags flags, StringTrimming trim)
        {
            StringFormat f = new StringFormat(flags);
            f.Alignment = h;
            f.LineAlignment = v;
            f.Trimming = trim;
            return f;
        }

        // 实例 Font 缓存：scale 变化时整体重建（5 个不同 family/size/style）
        // 实例字段不能跨线程：Prewarm 走静态 base font，Paint 走实例 scaled font，二者互不触碰
        // —— 避免 PrewarmGdi (ThreadPool) 与 Paint (UI) 之间 EnsureFonts 重建期的 Font 竞争。
        private float _cachedFontScale = -1f;
        private Font _fontTools15Bold;        // PaintTools 受控中文双字标签
        private Font _fontToolsIcon15;        // 设置/暂停/退出受控符号字体
        private Font _fontMapLabel115Bold;    // PaintMapLabel "Microsoft YaHei" 11.5 Bold
        private Font _fontQuest12;            // 地图预览尺寸切换按钮
        private Font _fontNoticeJuke11;       // 条件状态槽 / hover tooltip

        // 静态 base font（scale=1）：Prewarm + 测试探针专用，避免与实例 _font* 跨线程共用。
        // 进程级共享 + 不 dispose（与 ComboWidget._baseTypedFont 等同形）；double-checked lock 懒初始化。
        private static Font _baseTools15Bold;
        private static Font _baseToolsIcon15;
        private static Font _baseMapLabel115Bold;
        private static Font _baseQuest12;
        private static Font _baseNoticeJuke11;
        private static readonly object _baseFontLock = new object();

        private static void EnsureBaseFonts()
        {
            if (_baseTools15Bold != null) return;
            lock (_baseFontLock)
            {
                if (_baseTools15Bold != null) return;
                _baseTools15Bold     = NativeHudFonts.CreateUiFont(14f, FontStyle.Bold, GraphicsUnit.Pixel);
                _baseToolsIcon15     = NativeHudFonts.CreateRoleFont("native.hud.symbol", 14f, FontStyle.Bold, GraphicsUnit.Pixel);
                _baseMapLabel115Bold = NativeHudFonts.CreateUiFont(11.5f, FontStyle.Bold, GraphicsUnit.Pixel);
                _baseQuest12         = NativeHudFonts.CreateUiFont(12f, FontStyle.Regular, GraphicsUnit.Pixel);
                _baseNoticeJuke11    = NativeHudFonts.CreateUiFont(11f, FontStyle.Regular, GraphicsUnit.Pixel);
            }
        }

        /// <summary>
        /// P2-1 prewarm 入口：在玩家看到 UI 之前触发 GDI+ 资源 + 字体 + 字形 cache。
        /// 与 Paint 路径共用 EnsureFonts；外加一次 DrawString 让 ClearType glyph cache 命中常见字符。
        /// </summary>
        public static void PrewarmGdi()
        {
            try
            {
                // 触发静态 cctor：文本 brush + StringFormat 进程级常量。
                System.GC.KeepAlive(BR_TOOLS_FG);
                EnsureBaseFonts();
                using (System.Drawing.Bitmap warm = new System.Drawing.Bitmap(128, 64, System.Drawing.Imaging.PixelFormat.Format32bppPArgb))
                using (System.Drawing.Graphics g = System.Drawing.Graphics.FromImage(warm))
                {
                    g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
                    g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAlias;
                    // 覆盖 RightContext 全部已知字符：六入口 + 地图尺寸按钮 + 条件状态槽
                    string[] samples = {
                        "地图 任务 装备",
                        "⚙ Ⅱ ▶ × ＋ － ➤",
                        "展开预览 缩略预览 任务已达成 可交付"
                    };
                    // 只接静态 base font，不触碰任何实例 _font*；与 UI 线程 Paint 路径完全无共享状态
                    g.DrawString(samples[0], _baseTools15Bold,     BR_TOOLS_FG,         0f,  0f);
                    g.DrawString(samples[1], _baseToolsIcon15,     BR_TOOLS_FG,         0f, 16f);
                    g.DrawString(samples[2], _baseQuest12,         BR_QUEST_FG,         0f, 32f);
                    g.DrawString(samples[2], _baseNoticeJuke11,    BR_QUEST_FG,         0f, 48f);
                    g.DrawString(samples[2], _baseMapLabel115Bold, BR_LABEL_TEXT,       0f, 60f);
                }
            }
            catch (Exception ex) { LogManager.Log("[RightContextWidget] PrewarmGdi failed: " + ex.Message); }
        }

        private void EnsureFonts(float scale)
        {
            if (Math.Abs(scale - _cachedFontScale) < 0.001f && _fontTools15Bold != null) return;
            DisposeFonts();
            _fontTools15Bold     = NativeHudFonts.CreateUiFont(WidgetScaler.Pxf(14f, scale), FontStyle.Bold, GraphicsUnit.Pixel);
            _fontToolsIcon15     = NativeHudFonts.CreateRoleFont("native.hud.symbol", WidgetScaler.Pxf(14f, scale), FontStyle.Bold, GraphicsUnit.Pixel);
            _fontMapLabel115Bold = NativeHudFonts.CreateUiFont(WidgetScaler.Pxf(11.5f, scale), FontStyle.Bold, GraphicsUnit.Pixel);
            _fontQuest12         = NativeHudFonts.CreateUiFont(WidgetScaler.Pxf(12f, scale), FontStyle.Regular, GraphicsUnit.Pixel);
            _fontNoticeJuke11    = NativeHudFonts.CreateUiFont(WidgetScaler.Pxf(11f, scale), FontStyle.Regular, GraphicsUnit.Pixel);
            _cachedFontScale = scale;
        }

        private void DisposeFonts()
        {
            if (_fontTools15Bold != null)     { _fontTools15Bold.Dispose();     _fontTools15Bold = null; }
            if (_fontToolsIcon15 != null)     { _fontToolsIcon15.Dispose();     _fontToolsIcon15 = null; }
            if (_fontMapLabel115Bold != null) { _fontMapLabel115Bold.Dispose(); _fontMapLabel115Bold = null; }
            if (_fontQuest12 != null)         { _fontQuest12.Dispose();         _fontQuest12 = null; }
            if (_fontNoticeJuke11 != null)    { _fontNoticeJuke11.Dispose();    _fontNoticeJuke11 = null; }
            _cachedFontScale = -1f;
        }

        /// <summary>
        /// 释放实例 Font GDI handle。NativeHudOverlay teardown 时调用，避免依赖 finalizer 延迟回收。
        /// 静态 base font / brush / pen / fmt 是进程级共享资源，不在此释放。
        /// </summary>
        public void Dispose()
        {
            DisposeFonts();
        }

        public event EventHandler BoundsOrVisibilityChanged;
        public event EventHandler RepaintRequested;
        public event EventHandler AnimationStateChanged;

        public RightContextWidget(
            Control anchor,
            LauncherCommandRouter router,
            MapHudDataCatalog catalog,
            MapDisplayPreference mapDisplayPreference = MapDisplayPreference.Auto,
            Action<MapDisplayPreference> onMapDisplayPreferenceChanged = null)
        {
            if (anchor == null) throw new ArgumentNullException("anchor");
            if (router == null) throw new ArgumentNullException("router");
            _anchor = anchor;
            _router = router;
            _catalog = catalog;
            _mapDisplayPreference = mapDisplayPreference;
            _onMapDisplayPreferenceChanged = onMapDisplayPreferenceChanged;
            _mapper = new FlashCoordinateMapper(anchor, 1024f, 576f);
            _hover.Kind = HitKind.None;
            _down.Kind = HitKind.None;
            _anchor.Resize += delegate { FireBounds(); };
            RebuildNoticeText();
        }

        private float Scale { get { return WidgetScaler.GetScale(_mapper); } }

        private bool IsMapModeRenderable
        {
            get { return MapDisplayPolicy.IsRenderableRuntime(_runtimeMapMode); }
        }

        private bool MapAvailable
        {
            get
            {
                if (_catalog == null || !_catalog.IsAvailable) return false;
                if (!IsMapModeRenderable) return false;
                if (string.IsNullOrEmpty(_mapHotspotId)) return false;
                return _mapEntry != null && _mapEntry.Outline != null && _mapEntry.Outline.ViewportRect.HasValue;
            }
        }

        private bool ShowMapSection
        {
            get { return _gameReady && _effectiveMapDisplayMode != EffectiveMapDisplayMode.Hidden && MapAvailable; }
        }

        private EffectiveMapDisplayMode LayoutMapMode
        {
            get { return ShowMapSection ? _effectiveMapDisplayMode : EffectiveMapDisplayMode.Hidden; }
        }

        private bool RecomputeEffectiveMapDisplayMode()
        {
            EffectiveMapDisplayMode next = MapDisplayPolicy.Resolve(
                _runtimeMapMode,
                _mapDisplayPreference,
                MapAvailable,
                _tacticalMapDataAvailable);
            if (next == _effectiveMapDisplayMode) return false;
            _effectiveMapDisplayMode = next;
            return true;
        }

        private NoticeMode CurrentNoticeMode
        {
            get
            {
                if (!_gameReady) return NoticeMode.Idle;
                if (_activeFlash != null) return NoticeMode.Flash;
                if (_taskDone) return NoticeMode.TaskDone;
                return NoticeMode.Idle;
            }
        }

        private bool ShowNotice
        {
            get { return CurrentNoticeMode != NoticeMode.Idle; }
        }

        internal bool RequestsActionableNotice
        {
            get { return ShowNotice; }
        }

        internal bool RequestsContextHint
        {
            get
            {
                return _gameReady
                    && _hover.Kind == HitKind.Tool
                    && _hover.Index >= 0
                    && _hover.Index < TOOL_TOOLTIPS.Length;
            }
        }

        private bool ShowStatusSlot
        {
            get
            {
                if (_slotOwner == RightContextSlotOwner.TransactionDecision) return true;
                if (_slotOwner == RightContextSlotOwner.ActionableNotice)
                    return RequestsActionableNotice;
                if (_slotOwner == RightContextSlotOwner.ContextHint)
                    return RequestsContextHint;
                return false;
            }
        }

        private bool PaintsActionableNotice
        {
            get
            {
                return _slotOwner == RightContextSlotOwner.ActionableNotice
                    && RequestsActionableNotice;
            }
        }

        private bool PaintsContextHint
        {
            get
            {
                return _slotOwner == RightContextSlotOwner.ContextHint
                    && RequestsContextHint;
            }
        }

        public bool Visible { get { return _gameReady; } }

        public Rectangle ScreenBounds
        {
            get
            {
                if (!Visible) return Rectangle.Empty;
                if (_anchor == null || !_anchor.IsHandleCreated) return Rectangle.Empty;
                return RightHudLayout.GetClusterRect(_anchor, _mapper, LayoutMapMode, ShowStatusSlot);
            }
        }

        public Rectangle CompositeBounds
        {
            get
            {
                Rectangle visual = ScreenBounds;
                if (visual.Width <= 0 || visual.Height <= 0) return visual;
                Rectangle viewport = RightHudLayout.GetViewportRect(_anchor, _mapper);
                float scale = RightHudLayout.ScaleForViewport(viewport);
                Rectangle tools = RightHudLayout.TopToolsRectFromViewport(viewport, scale);
                Rectangle tooltipReserve = new Rectangle(
                    tools.X,
                    tools.Y,
                    tools.Width,
                    tools.Height + WidgetScaler.Px(RightHudLayout.StatusSlotHeightBase, scale));
                return Rectangle.Union(visual, tooltipReserve);
            }
        }

        public bool WantsAnimationTick
        {
            get
            {
                if (!Visible) return false;
                if (_activeFlash != null) return true;
                return false;
            }
        }

        public void Tick(int deltaMs)
        {
            if (!Visible) return;
            bool repaint = false;
            bool tickDirty = false;

            if (_activeFlash != null)
            {
                _flashElapsedMs += deltaMs;
                if (_flashElapsedMs >= NOTICE_MS)
                {
                    _activeFlash = null;
                    _flashElapsedMs = 0;
                    PumpFlashOrFallback();
                    FireBounds();
                    tickDirty = true;
                }
                repaint = true;
            }

            if (repaint) FireRepaint();
            if (tickDirty || !WantsAnimationTick) FireAnimState();
        }

        public void Paint(Graphics g, float dpr, Point hudOrigin)
        {
            if (!Visible) return;
            Rectangle viewport = RightHudLayout.GetViewportRect(_anchor, _mapper);
            if (viewport.Width <= 0 || viewport.Height <= 0) return;
            float scale = RightHudLayout.ScaleForViewport(viewport);
            EffectiveMapDisplayMode mapMode = LayoutMapMode;
            bool showMap = mapMode != EffectiveMapDisplayMode.Hidden;
            bool showNotice = PaintsActionableNotice;
            bool showHint = PaintsContextHint;
            bool showStatusSlot = ShowStatusSlot;

            Rectangle tools = RightHudLayout.TopToolsRectFromViewport(viewport, scale);
            Rectangle context = RightHudLayout.ContextPanelRectFromViewport(viewport, scale, mapMode, showStatusSlot);
            Rectangle map = RightHudLayout.MapRectFromContext(context, scale, mapMode, showStatusSlot);
            Rectangle notice = RightHudLayout.StatusSlotRectFromContext(context, scale, showStatusSlot);

            tools.Offset(-hudOrigin.X, -hudOrigin.Y);
            context.Offset(-hudOrigin.X, -hudOrigin.Y);
            map.Offset(-hudOrigin.X, -hudOrigin.Y);
            notice.Offset(-hudOrigin.X, -hudOrigin.Y);

            EnsureFonts(scale);

            SmoothingMode prevSmooth = g.SmoothingMode;
            TextRenderingHint prevHint = g.TextRenderingHint;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = TextRenderingHint.AntiAlias;
            try
            {
                PaintTools(g, tools, scale);
                if (showHint) PaintActionTooltip(g, notice, scale);
                if (showNotice) PaintNotice(g, notice, scale);
                if (showMap) PaintMapCard(g, map, scale);
            }
            finally
            {
                g.SmoothingMode = prevSmooth;
                g.TextRenderingHint = prevHint;
            }
        }

        private void PaintTools(Graphics g, Rectangle r, float scale)
        {
            if (r.Width <= 0 || r.Height <= 0) return;
            string[] labels = _paused ? TOOL_LABELS_PAUSED : TOOL_LABELS_DEFAULT;
            // Flash 白框：每个入口保持独立分舱，hover/pressed/暂停/危险态共用主题语义。
            StringFormat fmt = FMT_CENTER;
            for (int i = 0; i < TOOL_KEYS.Length; i++)
            {
                Rectangle btn = RightHudLayout.ActionButtonRectFromTools(r, scale, i);
                Font font = i < RightHudLayout.PrimaryActionButtonCount ? _fontTools15Bold : _fontToolsIcon15;
                bool hover = _hover.Kind == HitKind.Tool && _hover.Index == i;
                bool pressed = _down.Kind == HitKind.Tool && _down.Index == i;
                bool paused = _paused && i == IDX_PAUSE;
                bool danger = i == TOOL_KEYS.Length - 1;
                Brush fgBrush = paused ? BR_TOOLS_FG_PAUSED : (hover ? BR_TOOLS_FG_HOVER : (Brush)BR_TOOLS_FG);
                NativeHudTheme.DrawButton(g, btn, scale, hover, pressed, paused, danger);
                g.DrawString(labels[i], font, fgBrush, btn, fmt);
            }
        }

        private void PaintActionTooltip(Graphics g, Rectangle r, float scale)
        {
            int index = _hover.Index;
            if (index < 0 || index >= TOOL_TOOLTIPS.Length || r.Width <= 0 || r.Height <= 0) return;
            NativeHudTheme.DrawPanel(g, r, scale, NativeHudTheme.PanelFillDense,
                Color.Empty, true);
            g.DrawString(TOOL_TOOLTIPS[index], _fontNoticeJuke11, BR_QUEST_FG, r, FMT_CENTER_ELLIPSIS);
        }

        private void PaintMapCard(Graphics g, Rectangle card, float scale)
        {
            if (card.Width <= 0 || card.Height <= 0 || _mapEntry == null || _mapEntry.Outline == null) return;
            MapHudWidget.ThemeColors theme = MapHudWidget.ResolveTheme(_mapEntry.Meta != null ? _mapEntry.Meta.Group : null);
            bool hover = _hover.Kind == HitKind.MapCard;
            Color fill = NativeHudTheme.Blend(NativeHudTheme.PanelFillDense,
                hover ? theme.StageB : theme.StageA, hover ? 0.20f : 0.12f, hover ? 244 : 232);
            NativeHudTheme.DrawPanel(g, card, scale, fill, theme.Accent, true);

            Rectangle body = Rectangle.Inflate(card, -WidgetScaler.Px(MAP_BODY_INSET_BASE, scale), -WidgetScaler.Px(MAP_BODY_INSET_BASE, scale));
            PaintMapBody(g, body, theme, scale);
            PaintMapLabel(g, card, theme, scale);
            PaintMapDisplayToggle(g, card, scale);
        }

        private void PaintMapDisplayToggle(Graphics g, Rectangle card, float scale)
        {
            Rectangle toggle = GetMapDisplayToggleRect(card, scale);
            if (toggle.Width <= 0 || toggle.Height <= 0) return;
            bool hover = _hover.Kind == HitKind.MapDisplayToggle;
            bool pressed = _down.Kind == HitKind.MapDisplayToggle;
            string glyph = _effectiveMapDisplayMode == EffectiveMapDisplayMode.Compact ? "＋" : "－";
            NativeHudTheme.DrawButton(g, toggle, scale, hover, pressed, false, false);
            using (SolidBrush fg = new SolidBrush(hover ? NativeHudTheme.TextPrimary : NativeHudTheme.TextSecondary))
            {
                g.DrawString(glyph, _fontQuest12, fg, toggle, FMT_CENTER);
            }
            if (hover)
            {
                int tooltipW = WidgetScaler.Px(74, scale);
                Rectangle tip = new Rectangle(Math.Max(card.X + WidgetScaler.Px(4, scale), toggle.X - tooltipW),
                    toggle.Y, tooltipW, toggle.Height);
                NativeHudTheme.DrawPanel(g, tip, scale, NativeHudTheme.PanelFillDense,
                    Color.Empty, false);
                string text = _effectiveMapDisplayMode == EffectiveMapDisplayMode.Compact ? "展开预览" : "缩略预览";
                g.DrawString(text, _fontNoticeJuke11, BR_QUEST_FG, tip, FMT_CENTER_ELLIPSIS);
            }
        }

        private static Rectangle GetMapDisplayToggleRect(Rectangle card, float scale)
        {
            if (card.Width <= 0 || card.Height <= 0) return Rectangle.Empty;
            int size = WidgetScaler.Px(24, scale);
            int margin = WidgetScaler.Px(4, scale);
            return new Rectangle(card.Right - size - margin, card.Y + margin, size, size);
        }

        private void PaintMapBody(Graphics g, Rectangle body, MapHudWidget.ThemeColors theme, float scale)
        {
            MapHudOutline outline = _mapEntry != null ? _mapEntry.Outline : null;
            MapHudWidget.PaintHudOutline(g, body, outline,
                _mapEntry != null ? _mapEntry.Meta : null,
                theme, scale, MIN_BLOCK_PX, WidgetScaler.Pxf(MAP_BEACON_R_BASE, scale));
        }

        private void PaintMapLabel(Graphics g, Rectangle card, MapHudWidget.ThemeColors theme, float scale)
        {
            string pageLabel = _mapEntry.Meta != null ? (_mapEntry.Meta.PageLabel ?? "") : "";
            string spotLabel = _mapEntry.Meta != null ? (_mapEntry.Meta.Label ?? "") : "";
            string text;
            if (string.IsNullOrEmpty(pageLabel)) text = spotLabel;
            else if (string.IsNullOrEmpty(spotLabel)) text = pageLabel;
            else text = pageLabel + " · " + spotLabel;
            if (string.IsNullOrEmpty(text)) return;

            int padX = WidgetScaler.Px(MAP_LABEL_PAD_X_BASE, scale);
            int padY = WidgetScaler.Px(MAP_LABEL_PAD_Y_BASE, scale);
            int margin = WidgetScaler.Px(6, scale);
            int maxW = Math.Max(1, card.Width - margin * 2);
            // P0 perf：font + fmt + textBrush 复用静态/缓存。
            Font font = _fontMapLabel115Bold;
            StringFormat fmt = FMT_NEAR_NOWRAP_ELLIPSIS;
            SizeF measured = g.MeasureString(text, font, maxW, fmt);
            int pillW = Math.Min(maxW, (int)Math.Ceiling(measured.Width) + padX * 2);
            int pillH = (int)Math.Ceiling(measured.Height) + padY * 2;
            Rectangle pill = new Rectangle(card.X + margin, card.Y + margin, pillW, pillH);
            NativeHudTheme.DrawPanel(g, pill, scale,
                NativeHudTheme.Blend(NativeHudTheme.PanelFillDense, theme.StageA, 0.12f, 236),
                theme.Accent, false);
            Rectangle textRect = new Rectangle(pill.X + padX, pill.Y,
                Math.Max(1, pill.Width - padX * 2), pill.Height);
            g.DrawString(text, font, BR_LABEL_TEXT, textRect, fmt);
        }

        private void PaintNotice(Graphics g, Rectangle r, float scale)
        {
            if (r.Width <= 0 || r.Height <= 0) return;
            NoticeMode mode = CurrentNoticeMode;
            int iconW = WidgetScaler.Px(ICON_W_BASE, scale);
            int pad = WidgetScaler.Px(NOTICE_TEXT_PAD_BASE, scale);
            int arrowW = WidgetScaler.Px(NOTICE_ARROW_W_BASE, scale);
            bool showArrow = mode == NoticeMode.TaskDone && CanDeliver();
            bool hover = _hover.Kind == HitKind.Notice;

            Color noticeAccent = mode == NoticeMode.Flash
                ? NativeHudTheme.Warning
                : (CanDeliver() ? NativeHudTheme.Cyan : NativeHudTheme.Gold);
            Color noticeFill = hover ? NativeHudTheme.ButtonHover : NativeHudTheme.PanelFillDense;
            NativeHudTheme.DrawPanel(g, r, scale, noticeFill, noticeAccent, true);

            Rectangle iconRect = new Rectangle(r.X, r.Y, iconW, r.Height);
            Rectangle textRect = new Rectangle(iconRect.Right + pad, r.Y,
                Math.Max(1, r.Width - iconW - pad * 2 - (showArrow ? arrowW : 0)), r.Height);
            Color iconColor = mode == NoticeMode.Flash
                ? Color.FromArgb(255, 255, 220, 130)
                : (hover ? Color.FromArgb(255, 255, 200, 80) : Color.FromArgb(255, 255, 175, 50));
            Color textColor = mode == NoticeMode.Flash
                ? Color.FromArgb(229, 255, 220, 150)
                : (hover ? Color.FromArgb(255, 255, 215, 110) : Color.FromArgb(229, 255, 200, 80));

            // P0 perf：font/sep/center/textFmt 复用；iconBrush/textBrush 颜色按 hover/mode 动态选，仍按需 new
            Font font = _fontNoticeJuke11;
            StringFormat center = FMT_CENTER;
            StringFormat textFmt = FMT_NEAR_NOWRAP_ELLIPSIS;
            using (SolidBrush iconBrush = new SolidBrush(iconColor))
            using (SolidBrush textBrush = new SolidBrush(textColor))
            {
                NativeHudTheme.DrawSeparator(g, iconRect.Right, r.Y + WidgetScaler.Px(4, scale),
                    r.Bottom - WidgetScaler.Px(4, scale), scale);
                g.DrawString(_noticeIcon, font, iconBrush, iconRect, center);
                g.DrawString(_noticeText, font, textBrush, textRect, textFmt);
                if (showArrow)
                {
                    Rectangle arrowRect = new Rectangle(r.Right - arrowW, r.Y, arrowW, r.Height);
                    using (SolidBrush arrowBg = new SolidBrush(Color.FromArgb(48, 24, 36, 44)))
                    using (SolidBrush arrowBrush = new SolidBrush(hover ? Color.FromArgb(255, 223, 246, 255) : Color.FromArgb(229, 160, 226, 255)))
                    {
                        g.FillRectangle(arrowBg, arrowRect);
                        NativeHudTheme.DrawSeparator(g, arrowRect.X, r.Y + WidgetScaler.Px(4, scale),
                            r.Bottom - WidgetScaler.Px(4, scale), scale);
                        g.DrawString("➤", font, arrowBrush, arrowRect, center);
                    }
                }
            }
        }

        public bool TryHitTest(Point screenPt)
        {
            return Visible && HitTest(screenPt).Kind != HitKind.None;
        }

        public void OnMouseEvent(MouseEventArgs e, MouseEventKind kind)
        {
            Point pt = new Point(e.X, e.Y);
            HitInfo hit = HitTest(pt);
            switch (kind)
            {
                case MouseEventKind.Enter:
                case MouseEventKind.Move:
                    SetHover(hit);
                    break;
                case MouseEventKind.Leave:
                    SetHover(NoHit());
                    break;
                case MouseEventKind.Down:
                    _down = (e.Button == MouseButtons.Left) ? hit : NoHit();
                    FireRepaint();
                    break;
                case MouseEventKind.Up:
                    FireRepaint();
                    break;
                case MouseEventKind.Click:
                    if (SameHit(_down, hit) || _down.Kind == HitKind.None) DispatchHit(hit);
                    _down = NoHit();
                    FireRepaint();
                    break;
            }
        }

        private HitInfo HitTest(Point pt)
        {
            if (!Visible) return NoHit();
            Rectangle viewport = RightHudLayout.GetViewportRect(_anchor, _mapper);
            float scale = RightHudLayout.ScaleForViewport(viewport);
            EffectiveMapDisplayMode mapMode = LayoutMapMode;
            bool showNotice = PaintsActionableNotice;
            bool showStatusSlot = ShowStatusSlot;
            Rectangle tools = RightHudLayout.TopToolsRectFromViewport(viewport, scale);
            if (tools.Contains(pt))
            {
                int idx = RightHudLayout.ActionButtonIndexAt(tools, scale, pt.X);
                if (idx < 0) return NoHit();
                return Hit(HitKind.Tool, idx);
            }

            Rectangle context = RightHudLayout.ContextPanelRectFromViewport(viewport, scale, mapMode, showStatusSlot);
            Rectangle map = RightHudLayout.MapRectFromContext(context, scale, mapMode, showStatusSlot);
            if (map.Contains(pt))
            {
                if (GetMapDisplayToggleRect(map, scale).Contains(pt)) return Hit(HitKind.MapDisplayToggle, 0);
                return Hit(HitKind.MapCard, 0);
            }
            Rectangle notice = RightHudLayout.StatusSlotRectFromContext(context, scale, showStatusSlot);
            if (showNotice && notice.Contains(pt)) return Hit(HitKind.Notice, 0);
            return NoHit();
        }

        private void DispatchHit(HitInfo hit)
        {
            try
            {
                switch (hit.Kind)
                {
                    case HitKind.Tool:
                        if (hit.Index >= 0 && hit.Index < TOOL_KEYS.Length) _router.Dispatch(TOOL_KEYS[hit.Index]);
                        break;
                    case HitKind.MapCard:
                        _router.Dispatch("TASK_MAP");
                        break;
                    case HitKind.MapDisplayToggle:
                        ToggleMapDisplaySize();
                        break;
                    case HitKind.Notice:
                        DispatchNoticeClick();
                        break;
                }
            }
            catch (Exception ex)
            {
                LogManager.Log("[RightContextWidget] dispatch failed kind=" + hit.Kind + " ex=" + ex.Message);
            }
        }

        private void DispatchNoticeClick()
        {
            if (CanDeliver())
            {
                string raw = "{\"hotspotId\":\"" + EscapeJson(_deliverHotspotId) + "\"}";
                _router.Dispatch("TASK_DELIVER", raw);
            }
            else
            {
                _router.Dispatch("TASK_UI");
            }
        }

        private void SetHover(HitInfo hit)
        {
            if (SameHit(_hover, hit)) return;
            bool requestedHintBefore = RequestsContextHint;
            _hover = hit;
            if (requestedHintBefore != RequestsContextHint) FireBounds();
            else FireRepaint();
        }

        public void OnUiDataChanged(IReadOnlyDictionary<string, string> snapshot, ISet<string> changedKeys)
        {
            bool boundsDirty = false;
            bool repaintDirty = false;
            bool tickDirty = false;
            bool textDirty = false;
            string piece;

            if (changedKeys.Contains("s") && snapshot.TryGetValue("s", out piece))
            {
                bool ready = UiValueParser.ParseUiBoolValue(piece);
                if (ready != _gameReady)
                {
                    _gameReady = ready;
                    if (!ready) ResetForNotReady();
                    boundsDirty = true;
                    tickDirty = true;
                    textDirty = true;
                }
            }
            if (changedKeys.Contains("p") && snapshot.TryGetValue("p", out piece))
            {
                bool paused = UiValueParser.ParseUiBoolValue(piece);
                if (paused != _paused) { _paused = paused; repaintDirty = true; }
            }
            bool mapInputsDirty = false;
            if (changedKeys.Contains("mm") && snapshot.TryGetValue("mm", out piece))
            {
                RuntimeMapMode nextMode = MapDisplayPolicy.ParseRuntimeMode(MapHudWidget.StripPrefix(piece, "mm"));
                if (nextMode != _runtimeMapMode)
                {
                    _runtimeMapMode = nextMode;
                    boundsDirty = true;
                    textDirty = true;
                    mapInputsDirty = true;
                }
            }
            if (changedKeys.Contains("mh") && snapshot.TryGetValue("mh", out piece))
            {
                string nextHotspot = MapHudWidget.StripPrefix(piece, "mh") ?? "";
                if (nextHotspot != _mapHotspotId)
                {
                    _mapHotspotId = nextHotspot;
                    _mapEntry = string.IsNullOrEmpty(_mapHotspotId) || _catalog == null ? null : _catalog.GetEntry(_mapHotspotId);
                    MapHudWidget.PrewarmEntry(_mapEntry);
                    if (_mapEntry == null && !string.IsNullOrEmpty(_mapHotspotId))
                        LogManager.Log("[RightContextWidget] map hotspot not in catalog: " + _mapHotspotId);
                    boundsDirty = true;
                    mapInputsDirty = true;
                }
            }
            if (changedKeys.Contains("td") && snapshot.TryGetValue("td", out piece))
            {
                bool nextDone = UiValueParser.ParseUiBoolValue(piece);
                if (nextDone != _taskDone)
                {
                    _taskDone = nextDone;
                    boundsDirty = true;
                    textDirty = true;
                }
            }
            if (changedKeys.Contains("tdh") && snapshot.TryGetValue("tdh", out piece))
            {
                string next = StripPrefix(piece, "tdh");
                if (next != _deliverHotspotId)
                {
                    _deliverHotspotId = next ?? "";
                    repaintDirty = true;
                    textDirty = true;
                }
            }
            if (changedKeys.Contains("tdn") && snapshot.TryGetValue("tdn", out piece))
            {
                bool nextNav = UiValueParser.ParseUiBoolValue(piece);
                if (nextNav != _navigable)
                {
                    _navigable = nextNav;
                    repaintDirty = true;
                    textDirty = true;
                }
            }
            if (mapInputsDirty && RecomputeEffectiveMapDisplayMode()) boundsDirty = true;
            if (textDirty) RebuildNoticeText();
            if (boundsDirty) FireBounds();
            else if (repaintDirty) FireRepaint();
            if (tickDirty) FireAnimState();
        }

        private void ResetForNotReady()
        {
            lock (_flashLock) { _flashQueue.Clear(); }
            _activeFlash = null;
            _flashElapsedMs = 0;
            _hover = NoHit();
            _down = NoHit();
        }

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
                FireBounds();
            }
            FireAnimState();
        }

        private void PumpFlashOrFallback()
        {
            FlashItem next = null;
            lock (_flashLock) { if (_flashQueue.Count > 0) next = _flashQueue.Dequeue(); }
            if (next != null)
            {
                _activeFlash = next;
                _flashElapsedMs = 0;
                _noticeText = next.Text;
                _noticeIcon = next.Icon ?? ICON_PLACEHOLDER;
            }
            else
            {
                _activeFlash = null;
                _flashElapsedMs = 0;
                RebuildNoticeText();
            }
        }

        private void RebuildNoticeText()
        {
            if (_activeFlash != null) return;
            if (_taskDone)
            {
                _noticeIcon = ICON_TASK_DONE;
                _noticeText = BuildTaskDoneText();
            }
            else
            {
                _noticeIcon = ICON_PLACEHOLDER;
                _noticeText = "";
            }
        }

        internal bool CanDeliver()
        {
            if (_activeFlash != null) return false;
            if (!_taskDone) return false;
            if (!_navigable) return false;
            if (string.IsNullOrEmpty(_deliverHotspotId)) return false;
            if (_runtimeMapMode == RuntimeMapMode.Combat) return false;
            return true;
        }

        internal string BuildTaskDoneText()
        {
            if (CanDeliver()) return "任务已达成 · 可交付";
            if (_runtimeMapMode == RuntimeMapMode.Combat) return "任务已达成 · 战后交付";
            if (string.IsNullOrEmpty(_deliverHotspotId)) return "任务已达成 · 暂无交付目标";
            if (!_navigable) return "任务已达成 · 交付点未解锁";
            return "任务已达成";
        }

        public void SetMapCollapsed(bool collapsed)
        {
            SetMapDisplayPreference(collapsed ? MapDisplayPreference.Off : MapDisplayPreference.Compact);
        }

        public void ToggleMapCollapsed()
        {
            ToggleMapVisibility();
        }

        public void SetMapDisplayPreference(MapDisplayPreference preference)
        {
            if (_mapDisplayPreference == preference) return;
            _mapDisplayPreference = preference;
            RecomputeEffectiveMapDisplayMode();
            if (_onMapDisplayPreferenceChanged != null)
            {
                try { _onMapDisplayPreferenceChanged(preference); }
                catch (Exception ex) { LogManager.Log("[RightContextWidget] persist map display preference failed: " + ex.Message); }
            }
            FireBounds();
        }

        internal void ApplySlotOwner(RightContextSlotOwner owner)
        {
            _slotOwner = owner;
        }

        public void ToggleMapVisibility()
        {
            SetMapDisplayPreference(MapDisplayPolicy.ToggleVisibility(_effectiveMapDisplayMode));
        }

        public void ToggleMapDisplaySize()
        {
            SetMapDisplayPreference(MapDisplayPolicy.ToggleSize(_effectiveMapDisplayMode));
        }

        public void SetTacticalMapDataAvailable(bool available)
        {
            if (_tacticalMapDataAvailable == available) return;
            _tacticalMapDataAvailable = available;
            if (RecomputeEffectiveMapDisplayMode()) FireBounds();
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

        private static HitInfo Hit(HitKind kind, int index)
        {
            HitInfo h;
            h.Kind = kind;
            h.Index = index;
            return h;
        }

        private static HitInfo NoHit()
        {
            return Hit(HitKind.None, -1);
        }

        private static bool SameHit(HitInfo a, HitInfo b)
        {
            return a.Kind == b.Kind && a.Index == b.Index;
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

        private void FireAnimState()
        {
            EventHandler h = AnimationStateChanged;
            if (h != null) h(this, EventArgs.Empty);
        }

        // ── test seams ──
        internal bool IsMapCollapsed { get { return _effectiveMapDisplayMode == EffectiveMapDisplayMode.Hidden; } }
        internal bool MapSectionVisibleForTest { get { return ShowMapSection; } }
        internal bool QuestNoticeVisibleForTest { get { return ShowNotice; } }
        internal bool HasActiveFlash { get { return _activeFlash != null; } }
        internal int FlashQueueCount { get { lock (_flashLock) { return _flashQueue.Count; } } }
        internal bool IsTaskDone { get { return _taskDone; } }
        internal bool IsNavigable { get { return _navigable; } }
        internal string DeliverHotspotId { get { return _deliverHotspotId; } }
        internal string MapMode { get { return ((int)_runtimeMapMode).ToString(); } }
        internal RuntimeMapMode RuntimeMapModeForTest { get { return _runtimeMapMode; } }
        internal MapDisplayPreference MapDisplayPreferenceForTest { get { return _mapDisplayPreference; } }
        internal bool StatusSlotVisibleForTest { get { return ShowStatusSlot; } }
        internal RightContextSlotOwner SlotOwnerForTest { get { return _slotOwner; } }
        internal bool PaintsActionableNoticeForTest { get { return PaintsActionableNotice; } }
        internal bool PaintsContextHintForTest { get { return PaintsContextHint; } }
        internal bool SlotHitBoxActiveForTest
        {
            get { return PaintsActionableNotice; }
        }
        internal EffectiveMapDisplayMode EffectiveMapDisplayModeForTest { get { return _effectiveMapDisplayMode; } }
        internal string DisplayText { get { return _noticeText; } }
        internal void ForceGameReady(bool ready) { _gameReady = ready; }
        internal void ForceTaskDone(bool done) { _taskDone = done; RebuildNoticeText(); }
        internal void ForceMapMode(string mode)
        {
            _runtimeMapMode = MapDisplayPolicy.ParseRuntimeMode(mode);
            RecomputeEffectiveMapDisplayMode();
        }
        internal void ForceMapHotspot(string hotspot)
        {
            _mapHotspotId = hotspot ?? "";
            _mapEntry = string.IsNullOrEmpty(_mapHotspotId) || _catalog == null ? null : _catalog.GetEntry(_mapHotspotId);
            RecomputeEffectiveMapDisplayMode();
        }
        internal void ForceDeliverState(bool done, string hotspot, bool navigable, string mapMode)
        {
            _taskDone = done;
            _deliverHotspotId = hotspot ?? "";
            _navigable = navigable;
            _runtimeMapMode = MapDisplayPolicy.ParseRuntimeMode(mapMode);
            RecomputeEffectiveMapDisplayMode();
            RebuildNoticeText();
        }
        internal void AdvanceFlashMs(int ms)
        {
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
        internal ClickRoute ResolveNoticeClickRoute()
        {
            return CanDeliver() ? ClickRoute.TaskDeliver : ClickRoute.TaskUi;
        }
        internal string ResolveActionRoute(int index)
        {
            return index >= 0 && index < TOOL_KEYS.Length ? TOOL_KEYS[index] : null;
        }
        internal string ResolveActionHint(int index)
        {
            return index >= 0 && index < TOOL_TOOLTIPS.Length ? TOOL_TOOLTIPS[index] : null;
        }
        internal void ForceHoveredToolForTest(int index)
        {
            _hover = index >= 0 && index < TOOL_KEYS.Length
                ? Hit(HitKind.Tool, index)
                : NoHit();
        }
    }
}
