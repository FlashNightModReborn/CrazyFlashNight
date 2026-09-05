using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.Windows.Forms;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.Hud.Loot;
using CF7Launcher.Tasks;

namespace CF7Launcher.Guardian.Hud
{
    /// <summary>
    /// 收敛后的右侧组合 HUD：六入口常驻动作行 + 条件状态槽 + 可选地图预览。
    /// 业务命令仍全部通过 LauncherCommandRouter.Dispatch，不在 widget 内复制业务分支。
    /// </summary>
    public class RightContextWidget : INativeHudWidget, INativeHudCompositeBoundsProvider, IUiDataConsumer, IUiDataLegacyConsumer, IStageOutcomePresenter, IDisposable
    {
        private const int NOTICE_MS = 5000;
        private const int ICON_W_BASE = 28;
        private const int NOTICE_TEXT_PAD_BASE = 8;
        private const int NOTICE_ARROW_W_BASE = 24;
        private const int STAGE_ACTION_W_BASE = 64;
        private const int STAGE_ACTION_REVIVE_W_BASE = 64;
        private const int STAGE_ACTION_PRIMARY_W_BASE = 80;
        private const int STAGE_ACTION_SECONDARY_W_BASE = 48;
        private const int STAGE_ACTION_SINGLE_W_BASE = 84;
        private const int STAGE_ACTION_GAP_BASE = 4;
        private const int STAGE_ACTION_INSET_BASE = 4;
        private const int STAGE_ACTION_LABEL_PAD_X_BASE = 1;
        private const int STAGE_BALANCE_ICON_BASE = 16;
        private const int STAGE_BALANCE_ICON_COMPACT_BASE = 14;
        private const int STAGE_BALANCE_ICON_MICRO_BASE = 12;
        private const int STAGE_BALANCE_GAP_BASE = 2;
        private const int STAGE_BALANCE_GAP_COMPACT_BASE = 1;
        private const int MAP_BODY_INSET_BASE = 8;
        private const int MAP_LABEL_PAD_X_BASE = 6;
        private const int MAP_LABEL_PAD_Y_BASE = 2;
        private const int MAP_BEACON_R_BASE = 5;
        private const float MIN_BLOCK_PX = 4f;

        private const string ICON_TASK_DONE = "❗";
        private const string ICON_PLACEHOLDER = "◆";
        private const string ICON_STAGE_VICTORY = "✓";
        private const string ICON_STAGE_FAILURE = "!";
        private const string ICON_STAGE_DEAD = "!";
        private const string ICON_STAGE_REWARDS = "◆";
        private const string REVIVE_COIN_ICON = "复活币";

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
        private const int IDX_SAFEEXIT = 5;
        private readonly SaveFeedbackState _saveFeedback = new SaveFeedbackState();

        private static readonly string[] LEGACY_TYPES = { "task", "announce" };

        private enum HitKind
        {
            None,
            Tool,
            MapCard,
            MapDisplayToggle,
            Notice,
            StageAction
        }

        private struct HitInfo
        {
            public HitKind Kind;
            public int Index;
        }

        private enum NoticeMode { Idle, StageBroadcast, Flash, TaskDone }

        private class FlashItem
        {
            public string Text;
            public string Icon;
        }

        private struct StageActionGestureToken
        {
            public bool Valid;
            public string Source;
            public string ActionId;
            public string RunId;
            public int Revision;
        }

        private struct NoticeGestureToken
        {
            public bool Valid;
            public string Command;
            public string PayloadSignature;
        }

        private sealed class StageActionSpec
        {
            public string Id;
            public string Label;
            public string Intent;
            public bool Enabled;
        }

        private struct StageBalanceVisualLayout
        {
            public Bitmap Icon;
            public string LabelText;
            public string MetaText;
            public Font LabelFont;
            public Font MetaFont;
            public RectangleF LabelRect;
            public Rectangle IconRect;
            public RectangleF MetaRect;
            public bool Compact;
            public bool Fits;
        }

        private readonly Control _anchor;
        private readonly LauncherCommandRouter _router;
        private readonly MapHudDataCatalog _catalog;
        private readonly LootIconCatalog _itemIcons;
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
        private volatile bool _returnNavigable;
        private string _deliverHotspotId = "";

        private readonly Queue<FlashItem> _flashQueue = new Queue<FlashItem>();
        private readonly object _flashLock = new object();
        private FlashItem _activeFlash;
        private int _flashElapsedMs;
        private string _noticeText = "";
        private string _noticeIcon = ICON_PLACEHOLDER;

        // StageRunSession 仍是唯一权威；这里仅把决策投影进常驻 HUD 的既有状态槽。
        // 决策条不暂停游戏，也不提供伪“继续”确认；玩家可直接忽略并继续探索。
        private readonly List<StageActionSpec> _stageActions =
            new List<StageActionSpec>();
        private StageOutcomeState _stageOutcomeState;
        private bool _stageBridgeReady;
        private string _stageBroadcastText;
        private string _stageBroadcastIcon;
        private string _stageBroadcastOutcome;
        private int _stageBroadcastElapsedMs;

        private HitInfo _hover;
        private HitInfo _down;
        private StageActionGestureToken _downStageActionToken;
        private NoticeGestureToken _downNoticeToken;

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
        private static readonly StringFormat FMT_STAGE_ACTION = MakeFmt(StringAlignment.Center, StringAlignment.Center, StringFormatFlags.NoWrap | StringFormatFlags.LineLimit, StringTrimming.EllipsisCharacter);

        private static StringFormat MakeFmt(StringAlignment h, StringAlignment v, StringFormatFlags flags, StringTrimming trim)
        {
            StringFormat f = new StringFormat(flags);
            f.Alignment = h;
            f.LineAlignment = v;
            f.Trimming = trim;
            return f;
        }

        // 实例 Font 缓存：scale 变化时整体重建（6 个不同 family/size/style）
        // 实例字段不能跨线程：Prewarm 走静态 base font，Paint 走实例 scaled font，二者互不触碰
        // —— 避免 PrewarmGdi (ThreadPool) 与 Paint (UI) 之间 EnsureFonts 重建期的 Font 竞争。
        private float _cachedFontScale = -1f;
        private Font _fontTools15Bold;        // PaintTools 受控中文双字标签
        private Font _fontToolsIcon15;        // 设置/暂停/退出受控符号字体
        private Font _fontMapLabel115Bold;    // PaintMapLabel "Microsoft YaHei" 11.5 Bold
        private Font _fontQuest12;            // 地图预览尺寸切换按钮
        private Font _fontNoticeJuke11;       // 条件状态槽 / hover tooltip
        private Font _fontStageActionCompact9;// 极长复活币计数的单行降级
        private Font _fontStageActionMicro8;  // 合法 long 上界的最终单行降级

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
                        "展开预览 缩略预览 任务已达成 可交付 持有 复活币 回基地"
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
            _fontStageActionCompact9 = NativeHudFonts.CreateUiFont(WidgetScaler.Pxf(9f, scale), FontStyle.Regular, GraphicsUnit.Pixel);
            _fontStageActionMicro8 = NativeHudFonts.CreateUiFont(WidgetScaler.Pxf(8f, scale), FontStyle.Regular, GraphicsUnit.Pixel);
            _cachedFontScale = scale;
        }

        private void DisposeFonts()
        {
            if (_fontTools15Bold != null)     { _fontTools15Bold.Dispose();     _fontTools15Bold = null; }
            if (_fontToolsIcon15 != null)     { _fontToolsIcon15.Dispose();     _fontToolsIcon15 = null; }
            if (_fontMapLabel115Bold != null) { _fontMapLabel115Bold.Dispose(); _fontMapLabel115Bold = null; }
            if (_fontQuest12 != null)         { _fontQuest12.Dispose();         _fontQuest12 = null; }
            if (_fontNoticeJuke11 != null)    { _fontNoticeJuke11.Dispose();    _fontNoticeJuke11 = null; }
            if (_fontStageActionCompact9 != null) { _fontStageActionCompact9.Dispose(); _fontStageActionCompact9 = null; }
            if (_fontStageActionMicro8 != null) { _fontStageActionMicro8.Dispose(); _fontStageActionMicro8 = null; }
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
        public event Action<string, string, int> IntentRequested;

        public RightContextWidget(
            Control anchor,
            LauncherCommandRouter router,
            MapHudDataCatalog catalog,
            MapDisplayPreference mapDisplayPreference = MapDisplayPreference.Auto,
            Action<MapDisplayPreference> onMapDisplayPreferenceChanged = null,
            LootIconCatalog itemIcons = null)
        {
            if (anchor == null) throw new ArgumentNullException("anchor");
            if (router == null) throw new ArgumentNullException("router");
            _anchor = anchor;
            _router = router;
            _catalog = catalog;
            _itemIcons = itemIcons;
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
                if (!string.IsNullOrEmpty(_stageBroadcastText))
                    return NoticeMode.StageBroadcast;
                if (_activeFlash != null) return NoticeMode.Flash;
                if (_taskDone) return NoticeMode.TaskDone;
                return NoticeMode.Idle;
            }
        }

        internal bool RequestsStageDecision
        {
            get
            {
                return _gameReady && _stageBridgeReady
                    && ShouldPresentStageDecision();
            }
        }

        private bool ShowNotice
        {
            get { return CurrentNoticeMode != NoticeMode.Idle; }
        }

        internal bool RequestsActionableNotice
        {
            get { return !RequestsStageDecision && ShowNotice; }
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
                if (_slotOwner == RightContextSlotOwner.StageDecision)
                    return RequestsStageDecision;
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

        private bool PaintsStageDecision
        {
            get
            {
                return _slotOwner == RightContextSlotOwner.StageDecision
                    && RequestsStageDecision;
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
                if (_saveFeedback.NeedsTick) return true;
                if (RequestsStageDecision) return false;
                if (!string.IsNullOrEmpty(_stageBroadcastText)) return true;
                if (_activeFlash != null) return true;
                return false;
            }
        }

        public void Tick(int deltaMs)
        {
            if (!Visible) return;
            bool feedbackWasTicking = _saveFeedback.NeedsTick;
            bool repaint = _saveFeedback.Tick();
            bool tickDirty = feedbackWasTicking != _saveFeedback.NeedsTick;

            // 决策问询必须稳定停留；普通播报及其计时在决策期间冻结。
            if (RequestsStageDecision)
            {
                if (repaint) FireRepaint();
                if (tickDirty) FireAnimState();
                return;
            }

            if (!string.IsNullOrEmpty(_stageBroadcastText))
            {
                _stageBroadcastElapsedMs += deltaMs;
                if (_stageBroadcastElapsedMs >= NOTICE_MS)
                {
                    ClearStageBroadcast();
                    FireBounds();
                    tickDirty = true;
                }
                repaint = true;
            }
            else if (_activeFlash != null)
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
            bool showStageDecision = PaintsStageDecision;
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
                if (showStageDecision) PaintStageDecision(g, notice, scale);
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
                if (i == IDX_SAFEEXIT) SaveFeedbackState.PaintAccent(g, btn, scale, _saveFeedback.Visual);
                g.DrawString(labels[i], font, fgBrush, btn, fmt);
            }
        }

        private void PaintActionTooltip(Graphics g, Rectangle r, float scale)
        {
            int index = _hover.Index;
            if (index < 0 || index >= TOOL_TOOLTIPS.Length || r.Width <= 0 || r.Height <= 0) return;
            NativeHudTheme.DrawPanel(g, r, scale, NativeHudTheme.PanelFillDense,
                Color.Empty, true);
            g.DrawString(ResolveActionHint(index), _fontNoticeJuke11, BR_QUEST_FG, r, FMT_CENTER_ELLIPSIS);
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
            string noticeText = mode == NoticeMode.StageBroadcast
                ? _stageBroadcastText : _noticeText;
            string noticeIcon = mode == NoticeMode.StageBroadcast
                ? _stageBroadcastIcon : _noticeIcon;
            int iconW = WidgetScaler.Px(ICON_W_BASE, scale);
            int pad = WidgetScaler.Px(NOTICE_TEXT_PAD_BASE, scale);
            int arrowW = WidgetScaler.Px(NOTICE_ARROW_W_BASE, scale);
            bool showArrow = mode == NoticeMode.TaskDone && CanDeliver();
            bool hover = mode != NoticeMode.StageBroadcast
                && _hover.Kind == HitKind.Notice;

            Color noticeAccent = mode == NoticeMode.StageBroadcast
                ? (_stageBroadcastOutcome == "victory"
                    ? NativeHudTheme.Cyan : NativeHudTheme.Danger)
                : (mode == NoticeMode.Flash
                    ? NativeHudTheme.Warning
                    : (CanDeliver() ? NativeHudTheme.Cyan : NativeHudTheme.Gold));
            Color noticeFill = hover ? NativeHudTheme.ButtonHover : NativeHudTheme.PanelFillDense;
            NativeHudTheme.DrawPanel(g, r, scale, noticeFill, noticeAccent, true);

            Rectangle iconRect = new Rectangle(r.X, r.Y, iconW, r.Height);
            Rectangle textRect = new Rectangle(iconRect.Right + pad, r.Y,
                Math.Max(1, r.Width - iconW - pad * 2 - (showArrow ? arrowW : 0)), r.Height);
            Color iconColor = mode == NoticeMode.StageBroadcast
                ? noticeAccent
                : (mode == NoticeMode.Flash
                ? Color.FromArgb(255, 255, 220, 130)
                : (hover ? Color.FromArgb(255, 255, 200, 80) : Color.FromArgb(255, 255, 175, 50)));
            Color textColor = mode == NoticeMode.StageBroadcast
                ? NativeHudTheme.TextPrimary
                : (mode == NoticeMode.Flash
                ? Color.FromArgb(229, 255, 220, 150)
                : (hover ? Color.FromArgb(255, 255, 215, 110) : Color.FromArgb(229, 255, 200, 80)));

            // P0 perf：font/sep/center/textFmt 复用；iconBrush/textBrush 颜色按 hover/mode 动态选，仍按需 new
            Font font = _fontNoticeJuke11;
            StringFormat center = FMT_CENTER;
            StringFormat textFmt = FMT_NEAR_NOWRAP_ELLIPSIS;
            using (SolidBrush iconBrush = new SolidBrush(iconColor))
            using (SolidBrush textBrush = new SolidBrush(textColor))
            {
                NativeHudTheme.DrawSeparator(g, iconRect.Right, r.Y + WidgetScaler.Px(4, scale),
                    r.Bottom - WidgetScaler.Px(4, scale), scale);
                g.DrawString(noticeIcon, font, iconBrush, iconRect, center);
                g.DrawString(noticeText, font, textBrush, textRect, textFmt);
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

        private void PaintStageDecision(Graphics g, Rectangle r, float scale)
        {
            StageOutcomeState state = _stageOutcomeState;
            if (!ShouldPresentStageOutcome(state)
                || r.Width <= 0 || r.Height <= 0)
                return;

            Color accent = StageAccent(state);
            NativeHudTheme.DrawPanel(g, r, scale,
                NativeHudTheme.PanelFillDense, accent, true);

            int iconW = WidgetScaler.Px(ICON_W_BASE, scale);
            int pad = WidgetScaler.Px(NOTICE_TEXT_PAD_BASE, scale);
            int actionsWidth = StageActionsTotalWidth(scale);
            Rectangle iconRect = new Rectangle(r.X, r.Y, iconW, r.Height);
            Rectangle textRect = new Rectangle(
                iconRect.Right + pad,
                r.Y,
                Math.Max(1, r.Width - iconW - pad * 2 - actionsWidth),
                r.Height);
            using (SolidBrush accentBrush = new SolidBrush(accent))
            using (SolidBrush textBrush = new SolidBrush(NativeHudTheme.TextPrimary))
            {
                NativeHudTheme.DrawSeparator(g, iconRect.Right,
                    r.Y + WidgetScaler.Px(4, scale),
                    r.Bottom - WidgetScaler.Px(4, scale), scale);
                g.DrawString(
                    StageIcon(state),
                    _fontNoticeJuke11,
                    accentBrush, iconRect, FMT_CENTER);
                if (ShouldShowReviveBalance(state))
                    PaintReviveBalance(
                        g, state, textRect, scale, textBrush);
                else
                    g.DrawString(
                        StageDecisionText(state),
                        _fontNoticeJuke11,
                        textBrush, textRect, FMT_NEAR_NOWRAP_ELLIPSIS);
            }

            for (int i = 0; i < _stageActions.Count; i++)
            {
                StageActionSpec action = _stageActions[i];
                Rectangle button = StageActionRect(r, scale, i);
                bool hover = _hover.Kind == HitKind.StageAction
                    && _hover.Index == i;
                bool pressed = _down.Kind == HitKind.StageAction
                    && _down.Index == i;
                bool primary = action.Id == "revive"
                    || action.Id == "deliver" || action.Id == "resume";
                NativeHudTheme.DrawButton(g, button, scale,
                    hover, pressed, primary, false);
                Color labelColor = action.Enabled
                    ? NativeHudTheme.TextPrimary : NativeHudTheme.TextDisabled;
                using (SolidBrush labelBrush = new SolidBrush(labelColor))
                {
                    Rectangle labelRect = StageActionLabelRect(button, scale);
                    g.DrawString(action.Label, _fontNoticeJuke11,
                        labelBrush, labelRect, FMT_STAGE_ACTION);
                }
            }
        }

        private void PaintReviveBalance(
            Graphics graphics,
            StageOutcomeState state,
            Rectangle content,
            float scale,
            Brush labelBrush)
        {
            StageBalanceVisualLayout layout = BuildReviveBalanceVisualLayout(
                graphics, state, content, scale);
            graphics.DrawString(
                layout.LabelText,
                layout.LabelFont,
                labelBrush,
                layout.LabelRect,
                FMT_STAGE_ACTION);

            if (layout.Icon != null && layout.IconRect.Width > 0)
                DrawStageItemIcon(
                    graphics, layout.Icon, layout.IconRect, true);

            using (SolidBrush metaBrush = new SolidBrush(
                NativeHudTheme.TextSecondary))
            {
                graphics.DrawString(
                    layout.MetaText,
                    layout.MetaFont,
                    metaBrush,
                    layout.MetaRect,
                    FMT_STAGE_ACTION);
            }
        }

        private StageBalanceVisualLayout BuildReviveBalanceVisualLayout(
            Graphics graphics,
            StageOutcomeState state,
            Rectangle content,
            float scale)
        {
            Bitmap icon = ResolveStageItemIcon(REVIVE_COIN_ICON);
            string labelText = icon != null ? "持有" : "复活币";
            string metaText = StageOutcomeState.FormatCompactCount(
                state != null ? state.ReviveCoins : 0L);
            StageBalanceVisualLayout layout;
            if (TryBuildStageBalanceVisualLayout(
                    graphics,
                    labelText,
                    metaText,
                    icon,
                    content,
                    scale,
                    _fontNoticeJuke11,
                    _fontNoticeJuke11,
                    STAGE_BALANCE_ICON_BASE,
                    STAGE_BALANCE_GAP_BASE,
                    false,
                    out layout))
                return layout;
            if (TryBuildStageBalanceVisualLayout(
                    graphics,
                    labelText,
                    metaText,
                    icon,
                    content,
                    scale,
                    _fontStageActionCompact9,
                    _fontStageActionCompact9,
                    STAGE_BALANCE_ICON_COMPACT_BASE,
                    STAGE_BALANCE_GAP_COMPACT_BASE,
                    true,
                    out layout))
                return layout;

            if (TryBuildStageBalanceVisualLayout(
                    graphics,
                    labelText,
                    metaText,
                    icon,
                    content,
                    scale,
                    _fontStageActionMicro8,
                    _fontStageActionMicro8,
                    STAGE_BALANCE_ICON_MICRO_BASE,
                    STAGE_BALANCE_GAP_COMPACT_BASE,
                    true,
                    out layout))
                return layout;

            // JS 安全整数上界等异常存量仍必须保持单行。仅在最终 8px 层仍
            // 放不下时去掉计数的小数位，保留数量级（如 9007.2万亿 →
            // 9007万亿）；常见库存继续显示原始一位小数。
            string tightMetaText = TightenStageBalanceMeta(metaText);
            if (tightMetaText != metaText)
            {
                TryBuildStageBalanceVisualLayout(
                    graphics,
                    labelText,
                    tightMetaText,
                    icon,
                    content,
                    scale,
                    _fontStageActionMicro8,
                    _fontStageActionMicro8,
                    STAGE_BALANCE_ICON_MICRO_BASE,
                    STAGE_BALANCE_GAP_COMPACT_BASE,
                    true,
                    out layout);
            }
            return layout;
        }

        private static string TightenStageBalanceMeta(string text)
        {
            if (string.IsNullOrEmpty(text)) return text;
            int decimalPoint = text.IndexOf('.');
            if (decimalPoint < 0) return text;
            int suffix = decimalPoint + 1;
            while (suffix < text.Length && char.IsDigit(text[suffix]))
                suffix++;
            return suffix > decimalPoint + 1
                ? text.Substring(0, decimalPoint) + text.Substring(suffix)
                : text;
        }

        private static bool TryBuildStageBalanceVisualLayout(
            Graphics graphics,
            string label,
            string metaText,
            Bitmap icon,
            Rectangle content,
            float scale,
            Font labelFont,
            Font metaFont,
            int iconBaseSize,
            int gapBaseSize,
            bool compactLabel,
            out StageBalanceVisualLayout layout)
        {
            float labelWidth = MeasureStageActionText(
                graphics, label, labelFont);
            float metaWidth = MeasureStageActionText(
                graphics, metaText, metaFont);
            int gap = WidgetScaler.Px(gapBaseSize, scale);
            int iconSize = icon != null
                ? WidgetScaler.Px(iconBaseSize, scale)
                : 0;
            int gapCount = icon != null ? 2 : 1;
            float totalWidth = labelWidth + metaWidth + iconSize
                + gap * gapCount;
            bool fits = totalWidth <= content.Width + 0.01f;
            float startX = content.X
                + Math.Max(0f, (content.Width - totalWidth) / 2f);
            float currentX = startX;

            layout = new StageBalanceVisualLayout
            {
                Icon = icon,
                LabelText = label,
                MetaText = metaText,
                LabelFont = labelFont,
                MetaFont = metaFont,
                LabelRect = new RectangleF(
                    currentX, content.Y, labelWidth, content.Height),
                Compact = compactLabel,
                Fits = fits
            };
            currentX += labelWidth + gap;
            if (icon != null)
            {
                layout.IconRect = new Rectangle(
                    (int)Math.Round(currentX),
                    content.Y + (content.Height - iconSize) / 2,
                    iconSize,
                    iconSize);
                currentX += iconSize + gap;
            }
            layout.MetaRect = new RectangleF(
                currentX, content.Y, metaWidth, content.Height);
            return fits;
        }

        private static float MeasureStageActionText(
            Graphics graphics, string text, Font font)
        {
            if (string.IsNullOrEmpty(text)) return 0f;
            SizeF measured = graphics.MeasureString(
                text,
                font,
                PointF.Empty,
                FMT_NEAR_NOWRAP_ELLIPSIS);
            return (float)Math.Ceiling(measured.Width);
        }

        private Bitmap ResolveStageItemIcon(string iconName)
        {
            if (_itemIcons == null || string.IsNullOrEmpty(iconName))
                return null;
            LootIconCatalog.LootIconFrames frames;
            return _itemIcons.TryGet(iconName, out frames)
                && frames != null
                ? frames.First
                : null;
        }

        private static void DrawStageItemIcon(
            Graphics graphics, Bitmap icon, Rectangle destination, bool enabled)
        {
            InterpolationMode previousInterpolation = graphics.InterpolationMode;
            graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
            try
            {
                if (enabled)
                {
                    graphics.DrawImage(
                        icon,
                        destination,
                        0,
                        0,
                        icon.Width,
                        icon.Height,
                        GraphicsUnit.Pixel);
                    return;
                }

                using (ImageAttributes attributes = new ImageAttributes())
                {
                    ColorMatrix matrix = new ColorMatrix();
                    matrix.Matrix33 = 0.42f;
                    attributes.SetColorMatrix(matrix);
                    graphics.DrawImage(
                        icon,
                        destination,
                        0,
                        0,
                        icon.Width,
                        icon.Height,
                        GraphicsUnit.Pixel,
                        attributes);
                }
            }
            finally
            {
                graphics.InterpolationMode = previousInterpolation;
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
                    SetPointerDown((e.Button == MouseButtons.Left) ? hit : NoHit());
                    FireRepaint();
                    break;
                case MouseEventKind.Up:
                    FireRepaint();
                    break;
                case MouseEventKind.Click:
                    if (PointerDownMatches(hit)) DispatchHit(hit);
                    ClearPointerDown();
                    FireRepaint();
                    break;
                case MouseEventKind.Cancel:
                    _hover = NoHit();
                    ClearPointerDown();
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
            if (PaintsStageDecision && notice.Contains(pt))
            {
                for (int i = 0; i < _stageActions.Count; i++)
                {
                    if (_stageActions[i].Enabled
                            && StageActionRect(notice, scale, i).Contains(pt))
                        return Hit(HitKind.StageAction, i);
                }
                return NoHit();
            }
            if (showNotice && CurrentNoticeMode != NoticeMode.StageBroadcast
                    && notice.Contains(pt))
                return Hit(HitKind.Notice, 0);
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
                    case HitKind.StageAction:
                        DispatchStageAction(hit.Index);
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

        private void DispatchStageAction(int index)
        {
            StageOutcomeState state = _stageOutcomeState;
            if (index < 0 || index >= _stageActions.Count)
                return;
            StageActionSpec action = _stageActions[index];
            if (!action.Enabled) return;

            if (ShouldPresentStageOutcome(state))
            {
                Action<string, string, int> handler = IntentRequested;
                if (handler != null && !string.IsNullOrEmpty(action.Intent))
                    handler(action.Intent, state.RunId, state.Revision);
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

        public void SetReady()
        {
            if (MarshalToUi(SetReady)) return;
            if (_stageBridgeReady) return;
            _stageBridgeReady = true;
            FireBounds();
        }

        public void ApplyState(StageOutcomeState state)
        {
            if (state == null) return;
            if (MarshalToUi(delegate { ApplyState(state); })) return;

            string previousRun = _stageOutcomeState != null
                ? _stageOutcomeState.RunId : null;
            if (!string.Equals(previousRun, state.RunId,
                    StringComparison.Ordinal))
                ClearStageBroadcast();
            _stageOutcomeState = state;
            _hover = NoHit();
            ClearPointerDown();
            BuildStageActions();
            FireBounds();
            FireAnimState();
        }

        public void ResetState()
        {
            if (MarshalToUi(ResetState)) return;
            _stageOutcomeState = null;
            _stageActions.Clear();
            ClearStageBroadcast();
            _hover = NoHit();
            ClearPointerDown();
            FireBounds();
            FireAnimState();
        }

        private bool MarshalToUi(Action action)
        {
            if (_anchor == null || _anchor.IsDisposed) return true;
            if (!_anchor.IsHandleCreated || !_anchor.InvokeRequired) return false;
            try { _anchor.BeginInvoke(action); }
            catch { }
            return true;
        }

        private bool ShouldPresentStageDecision()
        {
            return ShouldPresentStageOutcome(_stageOutcomeState);
        }

        private static bool ShouldPresentStageOutcome(StageOutcomeState state)
        {
            return state != null && state.ShouldDisplay;
        }

        private void BuildStageActions()
        {
            _stageActions.Clear();
            try
            {
                StageOutcomeState state = _stageOutcomeState;
                if (!ShouldPresentStageOutcome(state)) return;
                if (state.Settlement == "rewards_pending")
                {
                    AddStageAction("resume",
                        state.RemainingRewards == 0 ? "查看报告" : "继续领取",
                        "resume_rewards", true);
                    return;
                }
                if (state.Life == "dead")
                {
                    bool showReviveBalance = ShouldShowReviveBalance(state);
                    if (showReviveBalance)
                    {
                        AddStageAction(
                            "revive",
                            "复活",
                            "revive",
                            state.ReviveAllowed);
                    }
                    else
                    {
                        AddStageAction(
                            "revive", "禁复活", "revive", false);
                    }
                    if (state.CanReturnBase)
                        AddStageAction("return", "回基地", "return_base", true);
                    return;
                }
                if (state.Life == "reviving") return;
                if (CanOfferStageDelivery(state))
                    AddStageAction("deliver", "前往交付",
                        "return_deliverable", true);
                if (state.CanReturnBase)
                    AddStageAction("return", "回基地", "return_base", true);
            }
            finally
            {
                if (_down.Kind == HitKind.StageAction
                    && !PointerDownMatches(_down))
                    ClearPointerDown();
            }
        }

        private bool CanOfferStageDelivery(StageOutcomeState state)
        {
            return state != null && state.Outcome == "victory"
                && state.Life == "alive" && state.Settlement == "none"
                && state.CanReturnBase && _taskDone
                && _returnNavigable
                && !string.IsNullOrEmpty(_deliverHotspotId);
        }

        private void AddStageAction(
            string id,
            string label,
            string intent,
            bool enabled)
        {
            _stageActions.Add(new StageActionSpec
            {
                Id = id,
                Label = label,
                Intent = intent,
                Enabled = enabled
            });
        }

        private int StageActionsTotalWidth(float scale)
        {
            if (_stageActions.Count == 0) return 0;
            int gap = WidgetScaler.Px(STAGE_ACTION_GAP_BASE, scale);
            int inset = WidgetScaler.Px(STAGE_ACTION_INSET_BASE, scale);
            int total = inset + gap * Math.Max(0, _stageActions.Count - 1);
            for (int i = 0; i < _stageActions.Count; i++)
                total += StageActionWidth(scale, i);
            return total;
        }

        private Rectangle StageActionRect(Rectangle slot, float scale, int index)
        {
            if (index < 0 || index >= _stageActions.Count) return Rectangle.Empty;
            int gap = WidgetScaler.Px(STAGE_ACTION_GAP_BASE, scale);
            int inset = WidgetScaler.Px(STAGE_ACTION_INSET_BASE, scale);
            int total = gap * Math.Max(0, _stageActions.Count - 1);
            for (int i = 0; i < _stageActions.Count; i++)
                total += StageActionWidth(scale, i);
            int height = Math.Max(1, slot.Height - inset * 2);
            int x = slot.Right - inset - total;
            for (int i = 0; i < index; i++)
                x += StageActionWidth(scale, i) + gap;
            int width = StageActionWidth(scale, index);
            return new Rectangle(x, slot.Y + inset, width, height);
        }

        private int StageActionWidth(float scale, int index)
        {
            int baseWidth = STAGE_ACTION_W_BASE;
            if (_stageActions.Count == 1)
                baseWidth = STAGE_ACTION_SINGLE_W_BASE;
            else if (_stageActions.Count == 2)
                baseWidth = index == 0
                    ? (_stageActions[0].Id == "revive"
                        ? STAGE_ACTION_REVIVE_W_BASE
                        : STAGE_ACTION_PRIMARY_W_BASE)
                    : STAGE_ACTION_SECONDARY_W_BASE;
            return WidgetScaler.Px(baseWidth, scale);
        }

        private static Rectangle StageActionLabelRect(
            Rectangle button, float scale)
        {
            int pad = WidgetScaler.Px(STAGE_ACTION_LABEL_PAD_X_BASE, scale);
            return Rectangle.Inflate(button, -pad, 0);
        }

        private static string StageDecisionText(StageOutcomeState state)
        {
            if (state.Settlement == "rewards_pending")
                return state.RemainingRewards == 0
                    ? "行动报告待查看"
                    : "待领奖励 " + state.RemainingRewards + " 项";
            if (state.Life == "reviving") return "正在复活…";
            if (state.Life == "dead")
                return ShouldShowReviveBalance(state)
                    ? "持有复活币 " + StageOutcomeState.FormatCompactCount(
                        state.ReviveCoins)
                    : "你受了重伤";
            if (state.Outcome == "victory") return "关卡已突破";
            return "行动未能完成";
        }

        private static bool ShouldShowReviveBalance(StageOutcomeState state)
        {
            return state != null && state.Life == "dead"
                && (state.ReviveAllowed
                    || state.ReviveBlockedReason == "no_revive_coin");
        }

        private static string StageIcon(StageOutcomeState state)
        {
            if (state.Settlement == "rewards_pending") return ICON_STAGE_REWARDS;
            if (state.Life == "dead" || state.Life == "reviving")
                return ICON_STAGE_DEAD;
            return state.Outcome == "victory"
                ? ICON_STAGE_VICTORY : ICON_STAGE_FAILURE;
        }

        private static Color StageAccent(StageOutcomeState state)
        {
            if (state.Settlement == "rewards_pending") return NativeHudTheme.Gold;
            if (state.Life == "dead" || state.Life == "reviving"
                    || state.Outcome == "failure")
                return NativeHudTheme.Danger;
            return NativeHudTheme.Cyan;
        }

        private void StartStageBroadcast(StageOutcomeState state)
        {
            _stageBroadcastOutcome = state.Outcome;
            _stageBroadcastIcon = state.Outcome == "victory"
                ? ICON_STAGE_VICTORY : ICON_STAGE_FAILURE;
            _stageBroadcastText = (state.Outcome == "victory"
                    ? "关卡已突破 · " : "行动未完成 · ")
                + state.StageName;
            _stageBroadcastElapsedMs = 0;
        }

        private void ClearStageBroadcast()
        {
            _stageBroadcastText = null;
            _stageBroadcastIcon = null;
            _stageBroadcastOutcome = null;
            _stageBroadcastElapsedMs = 0;
        }

        internal void HandleSaveUiData(UiDataPacket packet)
        {
            bool wasTicking = _saveFeedback.NeedsTick;
            long savedBefore = _saveFeedback.CompletedSaveCount;
            bool repaint = _saveFeedback.HandlePacket(packet);
            if (repaint || savedBefore != _saveFeedback.CompletedSaveCount
                    && _hover.Kind == HitKind.Tool && _hover.Index == IDX_SAFEEXIT)
                FireRepaint();
            if (wasTicking != _saveFeedback.NeedsTick) FireAnimState();
        }

        public void OnUiDataChanged(IReadOnlyDictionary<string, string> snapshot, ISet<string> changedKeys)
        {
            bool boundsDirty = false;
            bool repaintDirty = false;
            bool tickDirty = false;
            bool textDirty = false;
            bool stageActionsDirty = false;
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
                    stageActionsDirty = true;
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
                    stageActionsDirty = true;
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
            if (changedKeys.Contains("tdr") && snapshot.TryGetValue("tdr", out piece))
            {
                bool nextReturnNav = UiValueParser.ParseUiBoolValue(piece);
                if (nextReturnNav != _returnNavigable)
                {
                    _returnNavigable = nextReturnNav;
                    repaintDirty = true;
                    textDirty = true;
                    stageActionsDirty = true;
                }
            }
            if (mapInputsDirty && RecomputeEffectiveMapDisplayMode()) boundsDirty = true;
            if (stageActionsDirty)
            {
                BuildStageActions();
                boundsDirty = true;
            }
            if (textDirty) RebuildNoticeText();
            if (boundsDirty) FireBounds();
            else if (repaintDirty) FireRepaint();
            if (tickDirty) FireAnimState();
        }

        private void ResetForNotReady()
        {
            _saveFeedback.Reset();
            lock (_flashLock) { _flashQueue.Clear(); }
            _activeFlash = null;
            _flashElapsedMs = 0;
            _hover = NoHit();
            ClearPointerDown();
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

        private void SetPointerDown(HitInfo hit)
        {
            _down = hit;
            _downStageActionToken = default(StageActionGestureToken);
            _downNoticeToken = default(NoticeGestureToken);
            if (hit.Kind == HitKind.Notice)
            {
                _downNoticeToken = CurrentNoticeGestureToken();
                return;
            }
            if (hit.Kind != HitKind.StageAction
                || hit.Index < 0 || hit.Index >= _stageActions.Count)
                return;

            StageActionSpec action = _stageActions[hit.Index];
            _downStageActionToken.Valid = true;
            _downStageActionToken.ActionId = action.Id;
            if (ShouldPresentStageOutcome(_stageOutcomeState))
            {
                _downStageActionToken.Source = "stage_outcome";
                _downStageActionToken.RunId = _stageOutcomeState.RunId;
                _downStageActionToken.Revision =
                    _stageOutcomeState.Revision;
                return;
            }
            _downStageActionToken = default(StageActionGestureToken);
        }

        private void ClearPointerDown()
        {
            _down = NoHit();
            _downStageActionToken = default(StageActionGestureToken);
            _downNoticeToken = default(NoticeGestureToken);
        }

        private bool PointerDownMatches(HitInfo hit)
        {
            if (!SameHit(_down, hit)) return false;
            if (hit.Kind == HitKind.Notice)
            {
                NoticeGestureToken current = CurrentNoticeGestureToken();
                return _downNoticeToken.Valid && current.Valid
                    && string.Equals(_downNoticeToken.Command,
                        current.Command, StringComparison.Ordinal)
                    && string.Equals(_downNoticeToken.PayloadSignature,
                        current.PayloadSignature, StringComparison.Ordinal);
            }
            if (hit.Kind != HitKind.StageAction) return true;
            if (!_downStageActionToken.Valid
                || hit.Index < 0 || hit.Index >= _stageActions.Count)
                return false;

            StageActionSpec action = _stageActions[hit.Index];
            if (!string.Equals(
                    _downStageActionToken.ActionId,
                    action.Id,
                    StringComparison.Ordinal))
                return false;

            if (ShouldPresentStageOutcome(_stageOutcomeState))
            {
                return string.Equals(
                        _downStageActionToken.Source,
                        "stage_outcome",
                        StringComparison.Ordinal)
                    && string.Equals(
                        _downStageActionToken.RunId,
                        _stageOutcomeState.RunId,
                        StringComparison.Ordinal)
                    && _downStageActionToken.Revision
                        == _stageOutcomeState.Revision;
            }
            return false;
        }

        private NoticeGestureToken CurrentNoticeGestureToken()
        {
            NoticeGestureToken token = default(NoticeGestureToken);
            if (!PaintsActionableNotice) return token;
            token.Valid = true;
            if (CanDeliver())
            {
                token.Command = "TASK_DELIVER";
                token.PayloadSignature = _deliverHotspotId ?? "";
            }
            else
            {
                token.Command = "TASK_UI";
                token.PayloadSignature = "";
            }
            return token;
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
        internal bool IsReturnNavigable { get { return _returnNavigable; } }
        internal string DeliverHotspotId { get { return _deliverHotspotId; } }
        internal string MapMode { get { return ((int)_runtimeMapMode).ToString(); } }
        internal RuntimeMapMode RuntimeMapModeForTest { get { return _runtimeMapMode; } }
        internal MapDisplayPreference MapDisplayPreferenceForTest { get { return _mapDisplayPreference; } }
        internal bool StatusSlotVisibleForTest { get { return ShowStatusSlot; } }
        internal RightContextSlotOwner SlotOwnerForTest { get { return _slotOwner; } }
        internal bool PaintsStageDecisionForTest { get { return PaintsStageDecision; } }
        internal bool PaintsActionableNoticeForTest { get { return PaintsActionableNotice; } }
        internal bool PaintsContextHintForTest { get { return PaintsContextHint; } }
        internal bool SlotHitBoxActiveForTest
        {
            get
            {
                if (PaintsStageDecision)
                {
                    for (int i = 0; i < _stageActions.Count; i++)
                        if (_stageActions[i].Enabled) return true;
                    return false;
                }
                return PaintsActionableNotice
                    && CurrentNoticeMode != NoticeMode.StageBroadcast;
            }
        }
        internal EffectiveMapDisplayMode EffectiveMapDisplayModeForTest { get { return _effectiveMapDisplayMode; } }
        internal string DisplayText
        {
            get
            {
                return CurrentNoticeMode == NoticeMode.StageBroadcast
                    ? _stageBroadcastText : _noticeText;
            }
        }
        internal string[] StageActionLabelsForTest
        {
            get
            {
                string[] labels = new string[_stageActions.Count];
                for (int i = 0; i < _stageActions.Count; i++)
                    labels[i] = _stageActions[i].Label;
                return labels;
            }
        }
        internal bool StageActionEnabledForTest(int index)
        {
            return index >= 0 && index < _stageActions.Count
                && _stageActions[index].Enabled;
        }
        internal string StageDecisionTextForTest
        {
            get
            {
                return ShouldPresentStageOutcome(_stageOutcomeState)
                    ? StageDecisionText(_stageOutcomeState) : null;
            }
        }
        internal Rectangle StageActionBoundsForTest(int index)
        {
            Rectangle viewport = RightHudLayout.GetViewportRect(_anchor, _mapper);
            float scale = RightHudLayout.ScaleForViewport(viewport);
            Rectangle context = RightHudLayout.ContextPanelRectFromViewport(
                viewport, scale, LayoutMapMode, ShowStatusSlot);
            Rectangle slot = RightHudLayout.StatusSlotRectFromContext(
                context, scale, ShowStatusSlot);
            return StageActionRect(slot, scale, index);
        }
        internal bool StageActionLabelFitsForTest(int index)
        {
            if (index < 0 || index >= _stageActions.Count) return false;
            Rectangle viewport = RightHudLayout.GetViewportRect(_anchor, _mapper);
            float scale = RightHudLayout.ScaleForViewport(viewport);
            Rectangle button = StageActionBoundsForTest(index);
            Rectangle labelRect = StageActionLabelRect(button, scale);
            if (labelRect.Width <= 0 || labelRect.Height <= 0) return false;
            EnsureFonts(scale);
            using (Bitmap bitmap = new Bitmap(1, 1))
            using (Graphics graphics = Graphics.FromImage(bitmap))
            using (StringFormat format =
                (StringFormat)StringFormat.GenericTypographic.Clone())
            {
                format.FormatFlags |= StringFormatFlags.NoWrap;
                SizeF measured = graphics.MeasureString(
                    _stageActions[index].Label,
                    _fontNoticeJuke11,
                    PointF.Empty,
                    format);
                return Math.Ceiling(measured.Width) <= labelRect.Width
                    && Math.Ceiling(measured.Height) <= labelRect.Height;
            }
        }
        internal string StageDecisionItemIconForTest
        {
            get
            {
                return ShouldShowReviveBalance(_stageOutcomeState)
                    ? REVIVE_COIN_ICON : null;
            }
        }
        internal bool StageDecisionBalanceIconResolvesForTest
        {
            get
            {
                return ShouldShowReviveBalance(_stageOutcomeState)
                    && ResolveStageItemIcon(REVIVE_COIN_ICON) != null;
            }
        }
        internal string StageDecisionBalanceLabelForTest
        {
            get
            {
                return ShouldShowReviveBalance(_stageOutcomeState)
                    ? ReviveBalanceLayoutForTest().LabelText : null;
            }
        }
        internal string StageDecisionBalanceMetaForTest
        {
            get
            {
                return ShouldShowReviveBalance(_stageOutcomeState)
                    ? ReviveBalanceLayoutForTest().MetaText : null;
            }
        }
        internal bool StageDecisionBalanceUsesCompactFontForTest
        {
            get
            {
                return ShouldShowReviveBalance(_stageOutcomeState)
                    && ReviveBalanceLayoutForTest().Compact;
            }
        }
        internal bool StageDecisionBalanceFitsForTest
        {
            get
            {
                return ShouldShowReviveBalance(_stageOutcomeState)
                    && ReviveBalanceLayoutForTest().Fits;
            }
        }
        private StageBalanceVisualLayout ReviveBalanceLayoutForTest()
        {
            Rectangle viewport = RightHudLayout.GetViewportRect(_anchor, _mapper);
            float scale = RightHudLayout.ScaleForViewport(viewport);
            Rectangle context = RightHudLayout.ContextPanelRectFromViewport(
                viewport, scale, LayoutMapMode, ShowStatusSlot);
            Rectangle slot = RightHudLayout.StatusSlotRectFromContext(
                context, scale, ShowStatusSlot);
            int iconW = WidgetScaler.Px(ICON_W_BASE, scale);
            int pad = WidgetScaler.Px(NOTICE_TEXT_PAD_BASE, scale);
            Rectangle textRect = new Rectangle(
                slot.X + iconW + pad,
                slot.Y,
                Math.Max(1, slot.Width - iconW - pad * 2
                    - StageActionsTotalWidth(scale)),
                slot.Height);
            EnsureFonts(scale);
            using (Bitmap bitmap = new Bitmap(1, 1))
            using (Graphics graphics = Graphics.FromImage(bitmap))
            {
                return BuildReviveBalanceVisualLayout(
                    graphics, _stageOutcomeState, textRect, scale);
            }
        }
        internal bool StageActionTextUsesSingleLineForTest
        {
            get
            {
                return (FMT_STAGE_ACTION.FormatFlags
                        & StringFormatFlags.NoWrap) != 0;
            }
        }
        internal bool HasStageBroadcastForTest
        {
            get { return !string.IsNullOrEmpty(_stageBroadcastText); }
        }
        internal void ClickStageActionForTest(int index)
        {
            DispatchStageAction(index);
        }
        internal void SetStageActionDownForTest(int index)
        {
            SetPointerDown(Hit(HitKind.StageAction, index));
        }
        internal void ClickStageActionGestureForTest(int index)
        {
            HitInfo hit = Hit(HitKind.StageAction, index);
            if (PointerDownMatches(hit)) DispatchHit(hit);
            ClearPointerDown();
        }
        internal void SetNoticeDownForTest()
        {
            SetPointerDown(Hit(HitKind.Notice, 0));
        }
        internal bool ClickNoticeGestureForTest()
        {
            HitInfo hit = Hit(HitKind.Notice, 0);
            bool matched = PointerDownMatches(hit);
            if (matched) DispatchHit(hit);
            ClearPointerDown();
            return matched;
        }
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
        internal void ForceDeliverState(
            bool done, string hotspot, bool navigable, string mapMode,
            bool returnNavigable = false)
        {
            _taskDone = done;
            _deliverHotspotId = hotspot ?? "";
            _navigable = navigable;
            _returnNavigable = returnNavigable;
            _runtimeMapMode = MapDisplayPolicy.ParseRuntimeMode(mapMode);
            RecomputeEffectiveMapDisplayMode();
            RebuildNoticeText();
            BuildStageActions();
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
            if (index == IDX_SAFEEXIT && !string.IsNullOrEmpty(_saveFeedback.Hint))
                return "安全退出 · " + _saveFeedback.Hint;
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
