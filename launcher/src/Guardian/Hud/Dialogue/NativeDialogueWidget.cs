using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.Threading.Tasks;
using System.Windows.Forms;
using CF7Launcher.Guardian;

namespace CF7Launcher.Guardian.Hud.Dialogue
{
    /// <summary>
    /// native_dialogue 现场对白 widget：替代 Flash 内「对话框界面」MovieClip 的呈现层。
    ///
    /// 视觉权威 = 原 XFL（flashswf/UI/对话框界面 open 帧）：浅灰渐隐面板、#191919 深色
    /// 斜切头条、白姓名/称号、黑正文、青色拖动柄、红色关闭钮。装饰位图来自
    /// launcher/web/assets/dialogue-ui（H 从 XFL 直导的 source.svg + 按钮三态），
    /// 经 DialogueUiSkin 按 viewport scale 光栅化缓存；缺资产时退化为同款几何的
    /// GDI 近似（不回到旧黑底设计）。动态文本与立绘不烘焙进 SVG：
    /// 名/称号/正文在各自字段的<b>局部文本坐标系</b>排版（源 matrix 的非均匀缩放
    /// 经 Graphics 变换复刻，折行点与原版一致），立绘按 mask 矩形裁剪、底锚注册。
    ///
    /// 职责边界（COMMON 桥合同）：
    /// - AS2 权威持有句序/人物/暂停/finish-cancel；本类只做呈现、打字与输入采集。
    /// - ShowFrame 整帧替换当前句（同 RequestId 且 Revision 不后退才接受，迟到帧拒绝）。
    /// - HideFrame 仅在 requestId+sceneId 精确匹配时清屏；Reset 为静默全清（断线/转场）。
    /// - 输入出口 = InputRequested(frame 快照, "advance"|"close")；widget 不直接发 wire 包。
    /// - TryAdvance 先补全打字，打字完成后才发 advance（与旧「下一句/结束打字」等价语义）。
    /// - TryClose 立即发 close（显式关闭钮/Esc），不要求打字完成。
    /// - 鼠标手势：Down 绑定 (requestId, revision, zone)，Up 仅在同修订同 zone 时生效——
    ///   跨修订迟到的 Up 绝不推进新句；快速双击的第二次击键落在新句打字上，只补全不跳过。
    ///   拖动柄 zone（原 startDrag 语义）：按住即平移整个面板，Up 不产生 verb。
    /// - 失焦/宿主压隐（Cancel 事件 / SetHostSuppressed(true)）：取消未完成手势、暂停打字、
    ///   隐藏画面，<b>不终结会话</b>——与 NPC 菜单的压隐终结语义刻意不同（长剧情可恢复）。
    ///   NativeHudOverlay 经 INativeHudResumable 合并 panel_suspend / owner_hidden，全部解除才恢复。
    ///
    /// 图片所有权：SetPortrait/SetSceneImage 收到的 Bitmap 由<b>调用方</b>持有与释放；
    /// widget 接受时克隆自持（32bppPArgb），克隆件在替换/清屏/Dispose 时释放。
    /// requestId+revision 不匹配的迟到图直接拒绝（返回 false，不动调用方位图）。
    ///
    /// 性能：排版在字段局部空间进行（与 viewport 无关，换字号/文本才重排），
    /// 位图缩放按（源图/目标尺寸）缓存，SVG 装饰按 scale 光栅化一次缓存；
    /// 打字期间每 tick 仅重绘，打完立即停 tick。
    /// 每句一卡治理：同身份立绘/配图的重投递整体跳过（不克隆、不 flush 缩放
    /// 缓存）；BoundsOrVisibilityChanged 按（Visible, ScreenBounds）快照对比，
    /// 几何未动不触发覆层的立即全量提交；正文画刷按 ARGB 缓存不逐 run 新建。
    /// 消闪治理：立绘/配图换身份默认 hold-last-frame（旧图续画到新图到达原子
    /// 换入，消除「先 Dispose 再异步重载」的空白帧），跨会话同身份 carry
    /// （位图不离场、Host 重投递命中同图跳过），替换路径后台预缩把
    /// HighQualityBicubic 从首次 Paint 的 UI 线程挪到池线程。
    ///
    /// 线程模型：同 NpcMenuWidget——Show/Hide/Set* 可从 socket worker 线程调用
    /// （_gate 保护），Paint/Tick/OnMouseEvent 在 UI 线程；事件回调锁外 fire。
    /// </summary>
    public sealed class NativeDialogueWidget : INativeHudWidget, INativeHudWheelConsumer, INativeHudResumable, IDisposable
    {
        // ── 版面常量的权威在 DialogueUiSkin（XFL 实测，与 layout.json 同源）。
        //    这里只保留排版行为参数。──
        /// <summary>正文字段局部折行宽 = 字段宽 573 − 左右各 2 内边距（Flash 文本域惯例）。</summary>
        internal const float BODY_WRAP_LOCAL = 569f;
        /// <summary>正文局部行距（em）：近似 Flash device 字段默认 leading。</summary>
        internal const float LINE_HEIGHT_EM = 1.2f;
        /// <summary>文本域局部内边距（Flash 文本域左 2px 惯例；顶部 1px）。</summary>
        internal const float TEXT_INSET_LOCAL = 2f;
        /// <summary>打字节拍（ms/字）≈ 旧 24fps enterFrame 逐字节奏略提速。</summary>
        internal const int DEFAULT_CHAR_MS = 36;

        // 命中 zone：显式动作区分，Down/Up 必须同 zone 同修订才生效。
        internal const int ZONE_NONE = 0;
        internal const int ZONE_BODY = 1;   // 「下一句」透明热区 → advance
        internal const int ZONE_CLOSE = 2;  // 关闭钮 → close
        internal const int ZONE_DRAG = 3;   // 拖动柄 → startDrag 语义（不产生 verb）

        private readonly Control _anchor;
        private readonly FlashCoordinateMapper _mapper;
        private readonly Func<Rectangle> _viewportProvider;   // 测试注入点：屏幕坐标 viewport
        private readonly DialogueUiSkin _skin;
        private readonly bool _ownsSkin;
        private readonly EventHandler _anchorResizeHandler;
        private readonly object _gate = new object();

        private NativeDialogueFrame _frame;
        private bool _suppressed;
        private bool _disposed;

        // 打字
        private int _visibleChars;
        private long _typingWallStartMs, _typingWallElapsedMs, _typingTickElapsedMs;
        internal Func<long> TypingClock = () => Environment.TickCount64;
        private int _charMs = DEFAULT_CHAR_MS;
        private NativeDialogueTextLayout.Plan _plan;
        private readonly Dictionary<string, Tuple<string, NativeDialogueTextLayout.Plan>> _headerPlans =
            new Dictionary<string, Tuple<string, NativeDialogueTextLayout.Plan>>();
        private string _planKey;
        private int _manualFirstLine = -1;
        private bool _animActive;

        // 手势（Down 绑定身份+zone；Up 校验）
        private bool _gestureArmed;
        private string _gestureRequestId;
        private int _gestureRevision;
        private int _gestureZone;
        private bool _closeHover;
        private bool _dragHover;

        // 拖动偏移（逻辑 px；原 startDrag(this) 语义——随 widget 存活，跨句保持）
        private float _dragDX, _dragDY;
        private Point _dragGrabScreen;
        private float _dragGrabDX, _dragGrabDY;

        // 立绘（克隆自持）
        private Bitmap _portraitBmp;
        private string _portraitIdentity;
        private bool _portraitPending;
        /// <summary>当前持有立绘自己的取景类别（投递接受帧的 IsDoll）。hold-last-frame
        /// 续画期间旧图仍按自己的纸娃娃/静态窗规则取景，不被新帧的身份套用。</summary>
        private bool _portraitHeldIsDoll;
        /// <summary>外部 SWF 立绘的作者取景（舞台逻辑坐标），随接受的位图原子投递；
        /// null = 无元数据（纸娃娃/静态/旧调用方走统一 fit 或内部窗规则）。</summary>
        private RectangleF? _portraitStageRect;
        private Bitmap _portraitScaled;
        private int _portraitScaledW, _portraitScaledH;

        // 配图（克隆自持）
        private Bitmap _sceneBmp;
        private string _scenePath;
        private bool _scenePending;
        private Bitmap _sceneScaled;
        private int _sceneScaledW, _sceneScaledH;

        // 字体/测量（UI 线程懒建；字段局部字号固定，与 viewport 无关）
        private Font _fontName, _fontTitle, _fontBody;
        private Bitmap _measureBmp;
        private Graphics _measureG;
        private StringFormat _typoFormat;
        private StringFormat _fieldFormat;
        private readonly Dictionary<char, float> _charW =
            new Dictionary<char, float>();
        // 文本画刷按 ARGB 缓存（UI 线程懒建，Dispose 统一释放）：
        // 打字期 ~30fps × 每 run 新建 SolidBrush 是 GC 压力源。
        private readonly Dictionary<int, SolidBrush> _brushCache =
            new Dictionary<int, SolidBrush>();

        /// <summary>
        /// widget → Host Task 的输入出口：(frame 快照, verb)。verb ∈ "advance" | "close"。
        /// task 负责把 revision/identity 包进 wire payload。
        /// </summary>
        public Action<NativeDialogueFrame, string> InputRequested;

        public NativeDialogueWidget(Control flashAnchor)
            : this(flashAnchor, null, DialogueUiSkin.AutoDiscover(), true) { }

        /// <param name="viewportProvider">屏幕坐标 Flash viewport 供给器；null →
        /// RightHudLayout.GetViewportRect(anchor, mapper)。测试注入确定性值。</param>
        internal NativeDialogueWidget(Control flashAnchor, Func<Rectangle> viewportProvider)
            : this(flashAnchor, viewportProvider, null, false) { }

        /// <summary>测试/显式接线：注入皮肤（null → 仅原版几何规格、无 SVG 资产的保底路径）。</summary>
        internal NativeDialogueWidget(Control flashAnchor, Func<Rectangle> viewportProvider,
            DialogueUiSkin skin)
            : this(flashAnchor, viewportProvider, skin, false) { }

        private NativeDialogueWidget(Control flashAnchor, Func<Rectangle> viewportProvider,
            DialogueUiSkin skin, bool ownsSkin)
        {
            if (flashAnchor == null) throw new ArgumentNullException("flashAnchor");
            _anchor = flashAnchor;
            _mapper = new FlashCoordinateMapper(flashAnchor, 1024f, 576f);
            _viewportProvider = viewportProvider;
            _skin = skin ?? DialogueUiSkin.CreateSpecOnly();
            _ownsSkin = ownsSkin || skin == null;
            _anchorResizeHandler = delegate { FireBounds(); };
            _anchor.Resize += _anchorResizeHandler;
        }

        // ════════════════ Host/Task 生命周期 API ════════════════

        /// <summary>当前帧（活跃快照引用；无会话 null）。</summary>
        public NativeDialogueFrame CurrentFrame
        {
            get { lock (_gate) { return _frame; } }
        }

        /// <summary>
        /// 展示一句。新 RequestId = 新会话；同会话要求 Revision 不后退（迟到帧拒绝）。
        /// 消闪取舍（hold-last-frame）：换人/换表情/跨会话换立绘或配图时旧图
        /// <b>不立即清</b>，续画到新图到达原子换入（异步缓存命中典型 10-30ms），
        /// 消除空白帧——代价是换人瞬间最多显示旧图几十 ms，与纸娃娃换表情
        /// 原有的保留旧图语义统一。跨会话同身份位图不离场（carry）：Host 重投递
        /// 命中同图跳过天然 no-op。本句无立绘（WantsPortrait=false）与
        /// imageAction="clear" 仍是立即清的真隐藏，不走 hold。
        /// </summary>
        public bool ShowFrame(NativeDialogueFrame frame)
        {
            if (frame == null || string.IsNullOrEmpty(frame.RequestId)) return false;
            bool boundsChanged;
            lock (_gate)
            {
                if (_disposed) return false;
                BoundsSnapshot before = SnapshotBoundsLocked();
                NativeDialogueFrame cur = _frame;
                bool newSession = cur == null
                    || !string.Equals(cur.RequestId, frame.RequestId, StringComparison.Ordinal);
                if (!newSession && frame.Revision < cur.Revision) return false; // 迟到帧

                if (newSession)
                {
                    if (!frame.WantsPortrait)
                    {
                        DisposePortraitLocked();            // 无立绘会话 = 真隐藏
                        _portraitIdentity = null;
                        _portraitPending = false;
                    }
                    else
                    {
                        // carry 要求持有图确实是该身份（bmp 非空且非 pending——
                        // hold 态 bmp 非空+pending 时旧图身份并不等于
                        // _portraitIdentity，不能误判离场豁免）。
                        bool carry = _portraitBmp != null && !_portraitPending
                            && string.Equals(_portraitIdentity, frame.PortraitIdentity,
                                StringComparison.Ordinal);
                        _portraitIdentity = frame.PortraitIdentity;
                        _portraitPending = !carry;          // 否则 hold：旧图续画等新图
                    }

                    if (!frame.WantsSceneImage)
                    {
                        DisposeSceneLocked();               // 新会话未声明配图 = 真隐藏
                        _scenePath = null;
                        _scenePending = false;
                    }
                    else
                    {
                        bool carryScene = _sceneBmp != null && !_scenePending
                            && string.Equals(_scenePath, frame.ImagePath,
                                StringComparison.Ordinal);
                        _scenePath = frame.ImagePath;
                        _scenePending = !carryScene;
                    }
                }
                else
                {
                    if (!frame.WantsPortrait)
                    {
                        DisposePortraitLocked();            // 本句无立绘 = 真隐藏
                        _portraitIdentity = null;
                        _portraitPending = false;
                    }
                    else if (!string.Equals(_portraitIdentity, frame.PortraitIdentity, StringComparison.Ordinal))
                    {
                        // hold-last-frame：不清旧图，续画到新图到达原子换入。
                        _portraitPending = true;
                        _portraitIdentity = frame.PortraitIdentity;
                    }

                    string action = frame.ImageAction ?? "keep";
                    if (string.Equals(action, "clear", StringComparison.Ordinal))
                    {
                        DisposeSceneLocked();
                        _scenePath = null;
                        _scenePending = false;
                    }
                    else if (string.Equals(action, "show", StringComparison.Ordinal)
                        && !string.IsNullOrEmpty(frame.ImagePath))
                    {
                        if (!string.Equals(_scenePath, frame.ImagePath, StringComparison.Ordinal))
                        {
                            // 配图同规则 hold：path 变了旧图续画到新图到达。
                            _scenePath = frame.ImagePath;
                            _scenePending = true;
                        }
                        else if (_sceneBmp == null)
                        {
                            _scenePending = true;   // 同 path 但还没图
                        }
                    }
                    // "keep" / 未知值 / show+空 path：不动现状
                }

                _frame = frame;
                _visibleChars = 0;
                _manualFirstLine = -1;
                _typingWallStartMs = TypingClock();
                _typingWallElapsedMs = _typingTickElapsedMs = 0;
                _plan = null;
                _planKey = null;
                DisarmGestureLocked();
                _closeHover = false;
                _dragHover = false;
                boundsChanged = BoundsChanged(before, SnapshotBoundsLocked());
            }
            if (boundsChanged) FireBounds();
            FireRepaint();
            UpdateAnim();
            return true;
        }

        /// <summary>AS2 op:"hide"：仅 requestId+sceneId 双匹配才清；迟到 hide 不动新会话。</summary>
        public bool HideFrame(string requestId, string sceneId)
        {
            bool cleared = false;
            bool boundsChanged = false;
            lock (_gate)
            {
                BoundsSnapshot before = SnapshotBoundsLocked();
                NativeDialogueFrame cur = _frame;
                if (cur != null
                    && string.Equals(cur.RequestId, requestId, StringComparison.Ordinal)
                    && string.Equals(cur.SceneId ?? "", sceneId ?? "", StringComparison.Ordinal))
                {
                    ClearSessionLocked();
                    cleared = true;
                }
                boundsChanged = BoundsChanged(before, SnapshotBoundsLocked());
            }
            if (cleared)
            {
                if (boundsChanged) FireBounds();
                FireRepaint();
                UpdateAnim();
            }
            return cleared;
        }

        /// <summary>宿主静默全清（断线/场景滚转/任务 reset）：不回报，不发输入。</summary>
        public void Reset()
        {
            bool had;
            bool boundsChanged = false;
            lock (_gate)
            {
                BoundsSnapshot before = SnapshotBoundsLocked();
                had = _frame != null;
                ClearSessionLocked();
                boundsChanged = BoundsChanged(before, SnapshotBoundsLocked());
            }
            if (had)
            {
                if (boundsChanged) FireBounds();
                FireRepaint();
                UpdateAnim();
            }
        }

        /// <summary>
        /// 宿主压隐/恢复（主控接线）：true = 隐藏画面、取消手势、暂停打字但保留会话；
        /// false = 原样恢复。绝不终结会话——这是与 INativeHudSuppressionAware 的关键差异。
        /// </summary>
        public void SetHostSuppressed(bool suppressed)
        {
            bool changed;
            bool boundsChanged = false;
            lock (_gate)
            {
                if (_suppressed == suppressed) return;
                BoundsSnapshot before = SnapshotBoundsLocked();
                if (suppressed)
                    _typingWallElapsedMs += Math.Max(0, TypingClock() - _typingWallStartMs);
                else
                    _typingWallStartMs = TypingClock();
                _suppressed = suppressed;
                changed = _frame != null;
                if (suppressed)
                {
                    DisarmGestureLocked();
                    _closeHover = false;
                    _dragHover = false;
                }
                boundsChanged = BoundsChanged(before, SnapshotBoundsLocked());
            }
            if (changed)
            {
                if (boundsChanged) FireBounds();
                FireRepaint();
            }
            UpdateAnim();
        }

        /// <summary>
        /// 推进入口（鼠标点面板 / 交互键）：打字未完成 → 补全本句（不发 verb）；
        /// 已打完 → fire InputRequested(frame, "advance")。压隐/无会话返回 false。
        /// </summary>
        public bool TryAdvance()
        {
            NativeDialogueFrame f;
            bool complete;
            lock (_gate)
            {
                f = _frame;
                if (f == null || _suppressed || _disposed) return false;
                complete = TypingCompleteLocked();
            }
            if (!complete)
            {
                CompleteTyping();
                return true;
            }
            FireInput(f, "advance");
            return true;
        }

        /// <summary>显式关闭（× 钮 / Esc 绑定）：fire InputRequested(frame, "close")。</summary>
        public bool TryClose()
        {
            NativeDialogueFrame f;
            lock (_gate)
            {
                f = _frame;
                if (f == null || _suppressed || _disposed) return false;
            }
            FireInput(f, "close");
            return true;
        }

        public bool OnMouseWheel(Point screenPt, int wheelDelta)
        {
            lock (_gate)
            {
                if (_frame == null || _suppressed || _disposed || wheelDelta == 0) return false;
                Layout layout = ComputeLayoutLocked();
                if (!layout.Viewport.Contains(screenPt) || !layout.Panel.Contains(screenPt))
                    return false;
                EnsurePlanLocked();
                if (_plan == null) return false;
                int capacity = BodyCapacityLines;
                int last = NativeDialogueTextLayout.LastNeededLine(_plan, _visibleChars);
                int maximum = Math.Max(0, last - capacity + 1);
                if (maximum == 0) return false;
                int current = _manualFirstLine < 0 ? maximum : _manualFirstLine;
                _manualFirstLine = Math.Max(0, Math.Min(maximum, current - Math.Sign(wheelDelta) * 3));
                DisarmGestureLocked();
            }
            FireRepaint();
            return true;
        }

        /// <summary>
        /// 立绘投递（Host Task 译 appearance→Bitmap 后调用）。
        /// 接受条件：requestId+revision 与当前帧匹配且本帧需要立绘。
        /// 接受 → 克隆自持（原图归调用方释放）；迟到/多余 → false 不克隆不动图。
        /// </summary>
        public bool SetPortrait(string requestId, int revision, Bitmap bitmap)
        {
            return SetPortrait(requestId, revision, bitmap, null);
        }

        /// <summary>
        /// 立绘投递 + 作者取景元数据：stageRect = 位图在舞台逻辑坐标的目标矩形
        /// （外部 SWF 的 union∩window crop 经 manifest.zoom 还原；null/退化 = 走 fit 规则）。
        /// 元数据与位图同属一次 request/revision 接受：过期者一并拒绝，
        /// 迟到图不能改变当前句取景。
        /// 同图跳过：当前帧立绘身份对应的图已在手（_portraitBmp 非空且非 pending）
        /// 时，同一身份 ⇒ 服务端缓存 key 相同 ⇒ 位图内容必然相同，直接返回 true——
        /// 不克隆、不替换、不 dispose 缩放缓存、不 fire 任何事件（省一次克隆 +
        /// HighQualityBicubic 重缩 + bounds 立即全量提交）。身份变化/新会话换身份时
        /// _portraitPending 为 true，仍走原替换路径（hold 的旧图此刻原子换入）；
        /// 跨会话同身份 carry 时 pending=false 且图已在手，重投递命中本跳过路径。
        /// </summary>
        public bool SetPortrait(string requestId, int revision, Bitmap bitmap,
            RectangleF? stageRect)
        {
            if (bitmap == null) return false;
            Bitmap clone;
            Bitmap prescaleSrc = null;
            int prescaleW = 0, prescaleH = 0;
            bool boundsChanged;
            lock (_gate)
            {
                NativeDialogueFrame f = _frame;
                if (f == null || _disposed || !f.WantsPortrait
                    || !string.Equals(f.RequestId, requestId, StringComparison.Ordinal)
                    || f.Revision != revision)
                    return false;
                if (_portraitBmp != null && !_portraitPending)
                    return true;    // 同图已在手：整包跳过（含取景元数据）
                BoundsSnapshot before = SnapshotBoundsLocked();
                clone = CloneArgb(bitmap);
                if (clone == null) return false;
                Bitmap old = _portraitBmp;
                _portraitBmp = clone;
                _portraitPending = false;
                _portraitHeldIsDoll = f.IsDoll;   // 本图自己的取景类别（revision 门保证 f 即目标帧）
                _portraitStageRect = (stageRect.HasValue
                    && stageRect.Value.Width > 0 && stageRect.Value.Height > 0)
                    ? stageRect : (RectangleF?)null;
                DisposeBitmap(ref _portraitScaled);
                if (old != null) old.Dispose();
                // 后台预缩：锁内取当前布局目标尺寸并克隆私有源——GDI+ 只对不同
                // Bitmap 实例并发安全，UI 线程可能同时在画 _portraitBmp，池线程
                // 渲染须用独立实例且不持 _gate。
                Layout L = ComputeLayoutLocked();
                prescaleW = L.Portrait.Width;
                prescaleH = L.Portrait.Height;
                if (prescaleW > 0 && prescaleH > 0)
                    prescaleSrc = CloneArgb(clone);
                boundsChanged = BoundsChanged(before, SnapshotBoundsLocked());
            }
            if (boundsChanged) FireBounds();   // 立绘出现/尺寸变化 → 参与 bounds union
            FireRepaint();
            if (prescaleSrc != null)
                StartPortraitPrescale(clone, prescaleSrc, prescaleW, prescaleH);
            return true;
        }

        /// <summary>配图投递；keep 行仍可采用同一路径的迟到加载，clear 后拒绝。
        /// 同图跳过：_sceneBmp 非空且非 pending 时内容必然相同，直接返回 true，
        /// 不克隆、不替换、不动缩放缓存、不 fire 事件。</summary>
        public bool SetSceneImage(string requestId, int revision, Bitmap bitmap)
        {
            if (bitmap == null) return false;
            Bitmap clone;
            Bitmap prescaleSrc = null;
            int prescaleW = 0, prescaleH = 0;
            bool boundsChanged;
            lock (_gate)
            {
                NativeDialogueFrame f = _frame;
                if (f == null || _disposed || string.IsNullOrEmpty(_scenePath)
                    || !string.Equals(f.RequestId, requestId, StringComparison.Ordinal)
                    || f.Revision != revision)
                    return false;
                if (_sceneBmp != null && !_scenePending)
                    return true;    // 同图已在手：整包跳过
                BoundsSnapshot before = SnapshotBoundsLocked();
                clone = CloneArgb(bitmap);
                if (clone == null) return false;
                Bitmap old = _sceneBmp;
                _sceneBmp = clone;
                _scenePending = false;
                DisposeBitmap(ref _sceneScaled);
                if (old != null) old.Dispose();
                // 后台预缩：与立绘同规则（私有源克隆 + 锁外池线程渲染）。
                Layout L = ComputeLayoutLocked();
                prescaleW = L.Scene.Width;
                prescaleH = L.Scene.Height;
                if (prescaleW > 0 && prescaleH > 0)
                    prescaleSrc = CloneArgb(clone);
                boundsChanged = BoundsChanged(before, SnapshotBoundsLocked());
            }
            if (boundsChanged) FireBounds();
            FireRepaint();
            if (prescaleSrc != null)
                StartScenePrescale(clone, prescaleSrc, prescaleW, prescaleH);
            return true;
        }

        // ════════════════ INativeHudWidget ════════════════

        public event EventHandler BoundsOrVisibilityChanged;
        public event EventHandler RepaintRequested;
        public event EventHandler AnimationStateChanged;

        public bool Visible
        {
            get { lock (_gate) { return _frame != null && !_suppressed && !_disposed; } }
        }

        public bool WantsAnimationTick
        {
            get { lock (_gate) { return _animActive; } }
        }

        public Rectangle ScreenBounds
        {
            get
            {
                lock (_gate)
                {
                    if (_frame == null || _suppressed || _disposed) return Rectangle.Empty;
                    Layout L = ComputeLayoutLocked();
                    if (L.Panel.Width <= 0 || L.Panel.Height <= 0) return Rectangle.Empty;
                    Rectangle u = L.Panel;
                    u = Rectangle.Union(u, L.Close);
                    u = Rectangle.Union(u, L.Drag);
                    u = Rectangle.Union(u, L.Next);
                    if (!L.Portrait.IsEmpty) u = Rectangle.Union(u, L.Portrait);
                    if (!L.Scene.IsEmpty) u = Rectangle.Union(u, L.Scene);
                    return u;
                }
            }
        }

        public bool TryHitTest(Point screenPt)
        {
            lock (_gate)
            {
                if (_frame == null || _suppressed || _disposed) return false;
                // 吸收范围 = 整个已绘制区域（原 clip 不透明底会吃掉这些点击，
                // 不能穿透到游戏世界）；verb 派发仍只看 关闭/拖动/推进 三个原热区。
                Layout L = ComputeLayoutLocked();
                // 命中域必须落在 Flash viewport 内：原热区矩形可探出舞台底缘
                // （next 底 ~582 > 576），越界点不得被当作 widget 命中。
                if (L.Panel.IsEmpty || !L.Viewport.Contains(screenPt)) return false;
                if (L.Panel.Contains(screenPt) || L.Next.Contains(screenPt)
                    || L.Close.Contains(screenPt) || L.Drag.Contains(screenPt))
                    return true;
                if (!L.Portrait.IsEmpty && L.Portrait.Contains(screenPt)) return true;
                if (!L.Scene.IsEmpty && L.Scene.Contains(screenPt)) return true;
                return false;
            }
        }

        public void OnMouseEvent(MouseEventArgs e, MouseEventKind kind)
        {
            switch (kind)
            {
                case MouseEventKind.Move:
                case MouseEventKind.Enter:
                {
                    int zone;
                    bool dragMoved = false;
                    bool boundsChanged = false;
                    lock (_gate)
                    {
                        if (_frame == null || _suppressed || _disposed) return;
                        if (_gestureArmed && _gestureZone == ZONE_DRAG)
                        {
                            // 拖动中：只更新面板偏移（startDrag 语义），不再做命中扫描
                            Layout L = ComputeLayoutLocked();
                            if (L.Scale > 0)
                            {
                                float ndx = _dragGrabDX + (e.X - _dragGrabScreen.X) / L.Scale;
                                float ndy = _dragGrabDY + (e.Y - _dragGrabScreen.Y) / L.Scale;
                                ClampDragLocked(ref ndx, ref ndy);
                                if (ndx != _dragDX || ndy != _dragDY)
                                {
                                    BoundsSnapshot before = SnapshotBoundsLocked();
                                    _dragDX = ndx;
                                    _dragDY = ndy;
                                    dragMoved = true;
                                    boundsChanged = BoundsChanged(before, SnapshotBoundsLocked());
                                }
                            }
                            zone = ZONE_DRAG;
                        }
                        else
                        {
                            zone = ZoneAtLocked(new Point(e.X, e.Y));
                        }
                    }
                    if (dragMoved)
                    {
                        if (boundsChanged) FireBounds();
                        FireRepaint();
                    }
                    SetHovers(zone == ZONE_CLOSE, zone == ZONE_DRAG);
                    break;
                }
                case MouseEventKind.Leave:
                    SetHovers(false, false);
                    break;
                case MouseEventKind.Cancel:
                    // 失焦/捕获丢失/落空松键：只取消手势，会话保留（拖动偏移保留）。
                    lock (_gate) { DisarmGestureLocked(); _closeHover = false; _dragHover = false; }
                    FireRepaint();
                    break;
                case MouseEventKind.Down:
                    if (e.Button != MouseButtons.Left) break;
                    lock (_gate)
                    {
                        // 身份+落点同锁读取：armed 绑定的是 Down 瞬间的真实帧。
                        if (_frame == null || _suppressed || _disposed) break;
                        int zone = ZoneAtLocked(new Point(e.X, e.Y));
                        if (zone == ZONE_NONE) { DisarmGestureLocked(); break; }
                        _gestureArmed = true;
                        _gestureRequestId = _frame.RequestId;
                        _gestureRevision = _frame.Revision;
                        _gestureZone = zone;
                        if (zone == ZONE_DRAG)
                        {
                            _dragGrabScreen = new Point(e.X, e.Y);
                            _dragGrabDX = _dragDX;
                            _dragGrabDY = _dragDY;
                        }
                    }
                    break;
                case MouseEventKind.Up:
                    if (e.Button == MouseButtons.Left)
                        HandleUp(new Point(e.X, e.Y));
                    break;
                // Click 忽略：Up 已完成派发；避免 down/up/click 三段造成二次触发。
            }
        }

        private void HandleUp(Point screenPt)
        {
            int armedZone;
            lock (_gate)
            {
                NativeDialogueFrame f = _frame;
                if (f == null || !_gestureArmed) return;
                // Down 绑定的身份必须与当前帧同会话同修订，且落点 zone 与按下时一致。
                int upZone = ZoneAtLocked(screenPt);
                if (!string.Equals(_gestureRequestId, f.RequestId, StringComparison.Ordinal)
                    || _gestureRevision != f.Revision
                    || _gestureZone != upZone)
                {
                    DisarmGestureLocked();
                    return;
                }
                armedZone = _gestureZone;
                DisarmGestureLocked();
            }
            // 拖动柄不产生 verb；关闭钮立即 close；其余（正文热区）advance/补全。
            if (armedZone == ZONE_CLOSE) TryClose();
            else if (armedZone == ZONE_DRAG) { /* startDrag 结束，无 verb */ }
            else TryAdvance();
        }

        public void Tick(int deltaMs)
        {
            if (deltaMs <= 0) return;
            bool repaint = false;
            bool animChanged = false;
            lock (_gate)
            {
                if (_frame == null || _suppressed || _disposed) return;
                EnsurePlanLocked();
                _typingTickElapsedMs += deltaMs;
                repaint = CatchUpTypingLocked();
                animChanged = UpdateAnimLocked();
            }
            if (repaint) FireRepaint();
            if (animChanged) FireAnimChanged();
        }

        public void Paint(Graphics g, float dpr, Point hudOrigin)
        {
            bool animChanged = false;
            lock (_gate)
            {
                NativeDialogueFrame f = _frame;
                if (f == null || _suppressed || _disposed || g == null) return;
                Layout L = ComputeLayoutLocked();
                if (L.Panel.Width <= 0 || L.Panel.Height <= 0) return;
                EnsureFontsLocked();
                EnsurePlanLocked();
                // WM_TIMER 在繁忙消息队列中优先级低；正常绘制也按真实经过时间补算。
                CatchUpTypingLocked();
                animChanged = UpdateAnimLocked();

                GraphicsState state = g.Save();
                try
                {
                    g.TranslateTransform(-hudOrigin.X, -hudOrigin.Y);
                    g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;

                    // 旧 XFL 层序：立绘（mask 裁剪）在对话框背景下方 → 背景 → 字段文本
                    PaintPortrait(g, L);
                    PaintSceneImage(g, L);
                    PaintDecor(g, L);
                    PaintButtonOverlays(g, L);
                    PaintNameTitle(g, f, L);
                    PaintBody(g, L);
                }
                finally { g.Restore(state); }
            }
            if (animChanged) FireAnimChanged();
        }

        private bool CatchUpTypingLocked()
        {
            if (_frame == null || _suppressed || _plan == null) return false;
            long wallMs = _typingWallElapsedMs + Math.Max(0, TypingClock() - _typingWallStartMs);
            long elapsed = Math.Max(wallMs, _typingTickElapsedMs);
            int next = (int)Math.Min(_plan.TotalGlyphs, elapsed / Math.Max(8, _charMs));
            if (next <= _visibleChars) return false;
            _visibleChars = next;
            return true;
        }

        // ════════════════ 绘制分块 ════════════════

        /// <summary>整幅舞台装饰：source.svg 光栅位图（含按钮 up 态）；缺资产 → GDI 原版近似。</summary>
        private void PaintDecor(Graphics g, Layout L)
        {
            Bitmap stage = _skin != null ? _skin.RasterStage(L.Scale) : null;
            if (stage != null && !L.Stage.IsEmpty)
            {
                g.DrawImage(stage, L.Stage, 0, 0, stage.Width, stage.Height,
                    GraphicsUnit.Pixel);
                return;
            }
            PaintFallbackDecor(g, L);
        }

        /// <summary>
        /// 无 SVG 资产时的保底装饰：仍是原版视觉层级（浅灰体 + #191919 头条 +
        /// 红 X 关闭 + 青拖动柄 + 红扳机片），不回旧黑底设计。
        /// </summary>
        private void PaintFallbackDecor(Graphics g, Layout L)
        {
            Rectangle p = L.Panel;
            using (SolidBrush body = new SolidBrush(Color.FromArgb(230, 0xE5, 0xE5, 0xE5)))
                g.FillRectangle(body, p);
            if (!L.Strip.IsEmpty)
            {
                using (SolidBrush strip = new SolidBrush(Color.FromArgb(255, 0x19, 0x19, 0x19)))
                    g.FillRectangle(strip, L.Strip);
            }
            // 关闭红 X（hit 区中心，≈原 29 逻辑 px 图标）
            Rectangle cr = L.Close;
            if (!cr.IsEmpty)
            {
                float s = L.Scale;
                float cx = (cr.Left + cr.Right) / 2f, cy = (cr.Top + cr.Bottom) / 2f;
                float arm = 8f * s;
                Color c = _closeHover ? Color.FromArgb(0xFF, 0xCC, 0x00)
                    : Color.FromArgb(0xCC, 0x00, 0x00);
                using (Pen xp = new Pen(c, Math.Max(1.5f, 2f * s)))
                {
                    g.DrawLine(xp, cx - arm, cy - arm, cx + arm, cy + arm);
                    g.DrawLine(xp, cx + arm, cy - arm, cx - arm, cy + arm);
                }
            }
            // 拖动柄青块 + 上箭头
            Rectangle dr = L.Drag;
            if (!dr.IsEmpty)
            {
                float cx = (dr.Left + dr.Right) / 2f, cy = (dr.Top + dr.Bottom) / 2f;
                float r = 8f * L.Scale;
                Color c = _dragHover ? Color.FromArgb(0xFF, 0xCC, 0x00)
                    : Color.FromArgb(0x00, 0x99, 0xCC);
                using (SolidBrush cb = new SolidBrush(c))
                {
                    g.FillRectangle(cb, cx - r, cy - r * 0.4f, r * 2, r * 0.8f);
                    PointF[] tri = new PointF[]
                    {
                        new PointF(cx, cy - r * 1.6f),
                        new PointF(cx - r, cy - r * 0.3f),
                        new PointF(cx + r, cy - r * 0.3f)
                    };
                    g.FillPolygon(cb, tri);
                }
            }
        }

        /// <summary>按钮态绘制。separate 合同（layout.buttonRendering）：source.svg 无烘焙
        /// up 态，每帧画所选唯一状态（0/1/2），不留 up 底图残影；旧合同 up 已烘焙，
        /// 仅在 hover/按下时叠画 over/down。</summary>
        private void PaintButtonOverlays(Graphics g, Layout L)
        {
            if (_skin == null || !_skin.HasStageArt) return;
            bool separate = _skin.ButtonsSeparate;
            int closeState = _gestureArmed && _gestureZone == ZONE_CLOSE ? 2
                : (_closeHover ? 1 : (separate ? 0 : -1));
            int dragState = _gestureArmed && _gestureZone == ZONE_DRAG ? 2
                : (_dragHover ? 1 : (separate ? 0 : -1));
            PaintButtonOverlay(g, L, _skin.Close, closeState);
            PaintButtonOverlay(g, L, _skin.Drag, dragState);
        }

        private void PaintButtonOverlay(Graphics g, Layout L,
            DialogueUiSkin.ButtonSpec b, int state)
        {
            if (b == null || state < 0) return;
            RectangleF destLogical;
            Bitmap bmp = _skin.RasterButton(b, state, L.Scale, out destLogical);
            if (bmp == null) return;
            Rectangle dest = MapRect(L, destLogical, true);
            if (dest.Width <= 0 || dest.Height <= 0) return;
            if (b.Alpha < 0.999f)
            {
                using (ImageAttributes ia = new ImageAttributes())
                {
                    ColorMatrix cm = new ColorMatrix();
                    cm.Matrix33 = b.Alpha;
                    ia.SetColorMatrix(cm);
                    g.DrawImage(bmp, dest, 0, 0, bmp.Width, bmp.Height,
                        GraphicsUnit.Pixel, ia);
                }
            }
            else
            {
                g.DrawImage(bmp, dest, 0, 0, bmp.Width, bmp.Height,
                    GraphicsUnit.Pixel);
            }
        }

        /// <summary>名/称号保留字段位置与高度，字形等比绘制，clip 到原字段与头条带。</summary>
        private void PaintNameTitle(Graphics g, NativeDialogueFrame f, Layout L)
        {
            if (_skin == null) return;
            EnsureMeasureLocked();
            DrawFieldText(g, L, _skin.Name, _fontName, f.Name);
            DrawFieldText(g, L, _skin.Title, _fontTitle, f.Title);
        }

        /// <summary>按 ARGB 取共享画刷（懒建缓存，Dispose 统一释放）；
        /// 返回实例归 widget 所有，调用方不得 Dispose。</summary>
        private SolidBrush BrushFor(Color c)
        {
            SolidBrush b;
            if (!_brushCache.TryGetValue(c.ToArgb(), out b))
            {
                b = new SolidBrush(c);
                _brushCache[c.ToArgb()] = b;
            }
            return b;
        }

        private void DrawFieldText(Graphics g, Layout L, DialogueUiSkin.FieldSpec fs,
            Font font, string text)
        {
            if (fs == null || font == null || string.IsNullOrEmpty(text)) return;
            if (fs.Matrix.A == 0 || fs.Matrix.D == 0) return;
            GraphicsState st = g.Save();
            try
            {
                if (!L.Strip.IsEmpty) g.SetClip(L.Strip, CombineMode.Intersect);
                PointF o = LogicalToScreen(L, (float)fs.Matrix.Tx, (float)fs.Matrix.Ty, true);
                g.TranslateTransform(o.X, o.Y);
                g.ScaleTransform(L.Scale * fs.TextScale, L.Scale * fs.TextScale);
                float fieldWidth = Math.Max(1f, fs.TextLocalWidth - TEXT_INSET_LOCAL * 2);
                g.SetClip(new RectangleF(TEXT_INSET_LOCAL, 0, fieldWidth, fs.LocalH), CombineMode.Intersect);
                Tuple<string, NativeDialogueTextLayout.Plan> cached;
                if (!_headerPlans.TryGetValue(fs.Id, out cached) || cached.Item1 != text)
                {
                    // html=false（人物名字）：原文直排，标签按字面渲染不剥离。
                    cached = Tuple.Create(text, NativeDialogueTextLayout.Build(text, (int)fieldWidth,
                        c => _measureG.MeasureString(c.ToString(), font, int.MaxValue, _typoFormat).Width,
                        fs.Color, fs.Html, fs.Indent));
                    _headerPlans[fs.Id] = cached;
                }
                var plan = cached.Item2;
                if (plan.Lines.Count > 0)
                {
                    var line = plan.Lines[0];
                    foreach (var run in line.Runs)
                        g.DrawString(run.Text, font, BrushFor(run.Color),
                            TEXT_INSET_LOCAL + line.Indent + line.PrefixW[run.LineOffset],
                            1f, _typoFormat);
                }
            }
            finally { g.Restore(st); }
        }

        /// <summary>
        /// 正文沿原字段宽高排版，使用与姓名相同的等比字形；折行宽反算到文字空间。
        /// </summary>
        private void PaintBody(Graphics g, Layout L)
        {
            NativeDialogueTextLayout.Plan plan = _plan;
            if (plan == null || plan.Lines.Count == 0) return;
            Rectangle tr = L.Text;
            if (tr.Width <= 0 || tr.Height <= 0 || _fontBody == null) return;

            DialogueUiSkin.FieldSpec fs = _skin.Body;
            float lineH = Math.Max(1f, fs.FontSize * LINE_HEIGHT_EM);
            int capacity = BodyCapacityLines;
            int lastNeed = NativeDialogueTextLayout.LastNeededLine(plan, _visibleChars);
            int firstLine = Math.Max(0, lastNeed - capacity + 1);
            if (_manualFirstLine >= 0) firstLine = Math.Min(firstLine, _manualFirstLine);

            GraphicsState st = g.Save();
            try
            {
                g.SetClip(tr, CombineMode.Intersect);   // 屏幕空间裁剪在变换前
                PointF o = LogicalToScreen(L, (float)fs.Matrix.Tx, (float)fs.Matrix.Ty, true);
                g.TranslateTransform(o.X, o.Y);
                g.ScaleTransform(L.Scale * fs.TextScale, L.Scale * fs.TextScale);
                float y = 1f;
                for (int i = firstLine; i < plan.Lines.Count && y + lineH <= fs.LocalH + 1f; i++)
                {
                    NativeDialogueTextLayout.Line line = plan.Lines[i];
                    float x = TEXT_INSET_LOCAL + line.Indent;   // Flash indent：段首行右移
                    for (int r = 0; r < line.Runs.Count; r++)
                    {
                        NativeDialogueTextLayout.Run run = line.Runs[r];
                        if (run.GlyphStart >= _visibleChars) break;
                        int remain = _visibleChars - run.GlyphStart;
                        string text = run.Text;
                        if (remain < text.Length) text = text.Substring(0, remain);
                        if (text.Length == 0) continue;
                        g.DrawString(text, _fontBody,
                            BrushFor(run.Color.A == 0 ? fs.Color : run.Color),
                            x, y, _typoFormat);
                        // run 覆盖 glyph 区间 [GlyphStart, +Text.Length)，x 按实际绘长推进
                        int off = run.LineOffset;
                        int drawn = Math.Min(text.Length, line.GlyphCount - off);
                        if (drawn > 0 && off + drawn < line.PrefixW.Length)
                            x += line.PrefixW[off + drawn] - line.PrefixW[off];
                    }
                    y += lineH;
                }
            }
            finally { g.Restore(st); }
        }

        /// <summary>立绘：外部 SWF 按作者取景矩形 1:1 落舞台；纸娃娃在内部窗
        /// （≈(29.55,40.95,425.2,365.25)）裁剪固定作者窗口栅格；其余走 560×352 统一 fit。
        /// 裁剪随来源取外部 mask 或内部窗；随面板拖动（同属对话框 clip）。</summary>
        private void PaintPortrait(Graphics g, Layout L)
        {
            if (_portraitBmp == null || L.Portrait.IsEmpty) return;
            Bitmap scaled = EnsureScaled(ref _portraitScaled, ref _portraitScaledW,
                ref _portraitScaledH, _portraitBmp, L.Portrait.Width, L.Portrait.Height);
            if (scaled == null) return;
            GraphicsState st = g.Save();
            try
            {
                if (!L.PortraitClip.IsEmpty)
                    g.SetClip(L.PortraitClip, CombineMode.Intersect);
                g.DrawImage(scaled, L.Portrait, 0, 0, scaled.Width, scaled.Height,
                    GraphicsUnit.Pixel);
            }
            finally { g.Restore(st); }
        }

        /// <summary>配图：原版图载入 _root.图片容器（独立于对话框 clip，不随拖动、无底板框）。</summary>
        private void PaintSceneImage(Graphics g, Layout L)
        {
            if (_sceneBmp == null || L.Scene.IsEmpty) return;
            Bitmap scaled = EnsureScaled(ref _sceneScaled, ref _sceneScaledW,
                ref _sceneScaledH, _sceneBmp, L.Scene.Width, L.Scene.Height);
            if (scaled == null) return;
            g.DrawImage(scaled, L.Scene, 0, 0, scaled.Width, scaled.Height,
                GraphicsUnit.Pixel);
        }

        // ════════════════ 布局 ════════════════

        internal struct Layout
        {
            internal Rectangle Panel;        // 面板美术外接框（滚轮命中/保底装饰参考）
            internal Rectangle Text;         // 正文字段 stageRect→屏幕
            internal Rectangle Name;         // 名字字段
            internal Rectangle Title;        // 称号字段
            internal Rectangle Strip;        // 头条带（名/称号 clip 区：面板顶→正文热区顶）
            internal Rectangle Close;        // 关闭钮命中区
            internal Rectangle Drag;         // 拖动柄命中区
            internal Rectangle Next;         // 「下一句」透明热区
            internal Rectangle Portrait;     // 立绘目标框
            internal Rectangle PortraitClip; // 立绘 mask 裁剪（矩形近似）
            internal Rectangle Scene;        // 配图目标框
            internal Rectangle Stage;        // 舞台装饰位图目标框（含拖动偏移）
            internal Rectangle Viewport;     // 屏幕坐标 viewport（命中/滚轮的裁剪边界）
            internal PointF StageOrigin;     // 舞台逻辑 (0,0) 的屏幕位置（无拖动）
            internal float Scale;
            internal float DragDX, DragDY;   // 逻辑 px
        }

        private Rectangle CurrentViewport()
        {
            try
            {
                if (_viewportProvider != null) return _viewportProvider();
                return RightHudLayout.GetViewportRect(_anchor, _mapper);
            }
            catch { return Rectangle.Empty; }
        }

        /// <summary>舞台逻辑 (0,0) 的屏幕坐标：按高度缩放，宽出部分水平居中（showAll 信箱）。</summary>
        private static PointF StageOrigin(Rectangle vp, float scale)
        {
            return new PointF(
                vp.X + (vp.Width - DialogueUiSkin.StageW * scale) / 2f,
                vp.Y + (vp.Height - DialogueUiSkin.StageH * scale) / 2f);
        }

        /// <summary>锁内调用：由 viewport+scale+拖动偏移+图尺寸算全部矩形。</summary>
        private Layout ComputeLayoutLocked()
        {
            return ComputeLayoutCore(CurrentViewport());
        }

        /// <summary>舞台逻辑矩形 → 屏幕矩形（dragged=true 应用面板拖动偏移）。</summary>
        private static Rectangle MapRect(Layout L, RectangleF logical, bool dragged)
        {
            float dx = dragged ? L.DragDX : 0f;
            float dy = dragged ? L.DragDY : 0f;
            float l = L.StageOrigin.X + (logical.Left + dx) * L.Scale;
            float t = L.StageOrigin.Y + (logical.Top + dy) * L.Scale;
            float r = L.StageOrigin.X + (logical.Right + dx) * L.Scale;
            float b = L.StageOrigin.Y + (logical.Bottom + dy) * L.Scale;
            return Rectangle.FromLTRB(
                (int)Math.Round(l), (int)Math.Round(t),
                (int)Math.Round(r), (int)Math.Round(b));
        }

        /// <summary>舞台逻辑点 → 屏幕点（dragged=true 应用面板拖动偏移）。</summary>
        private static PointF LogicalToScreen(Layout L, float lx, float ly, bool dragged)
        {
            float dx = dragged ? L.DragDX : 0f;
            float dy = dragged ? L.DragDY : 0f;
            return new PointF(
                L.StageOrigin.X + (lx + dx) * L.Scale,
                L.StageOrigin.Y + (ly + dy) * L.Scale);
        }

        /// <summary>拖动偏移钳制：面板至少 64×40 逻辑 px 留在 1024×576 舞台内。</summary>
        private void ClampDragLocked(ref float dx, ref float dy)
        {
            RectangleF art = _skin.PanelArt;
            float minDx = 64f - art.Right;
            float maxDx = DialogueUiSkin.StageW - 64f - art.Left;
            float minDy = 40f - art.Bottom;
            float maxDy = DialogueUiSkin.StageH - 40f - art.Top;
            dx = Math.Max(minDx, Math.Min(maxDx, dx));
            dy = Math.Max(minDy, Math.Min(maxDy, dy));
        }

        /// <summary>正文可视行数：字段局部高 / 局部行高（皮肤实际字段，与 viewport 无关）。</summary>
        internal int BodyCapacityLines
        {
            get
            {
                DialogueUiSkin.FieldSpec body = _skin != null ? _skin.Body : null;
                float localH = body != null ? body.LocalH : DialogueUiSkin.BodyLocalH;
                float fontSize = body != null ? body.FontSize : DialogueUiSkin.BodyFont;
                return Math.Max(1, (int)(localH / Math.Max(1f, fontSize * LINE_HEIGHT_EM)));
            }
        }

        /// <summary>
        /// 立绘目标框（默认规则）：AR 适配进 560×352 逻辑框，底锚 y=405
        /// （external 烘焙窗口底 ≈ 面板顶+5），内容中心 x=325（原外部立绘典型心）。
        /// 外部 SWF（带作者取景）与纸娃娃走 ComputePortraitDestFor 的分支。
        /// </summary>
        internal static Rectangle ComputePortraitDest(Size bmpSize, Layout L)
        {
            if (bmpSize.Width <= 0 || bmpSize.Height <= 0) return Rectangle.Empty;
            return FitPortrait(bmpSize, L, DialogueUiSkin.PortraitMaxW,
                DialogueUiSkin.PortraitMaxH, DialogueUiSkin.PortraitCenterX,
                DialogueUiSkin.PortraitBottom);
        }

        /// <summary>内容裁剪图 AR 适配进 maxW×maxH 逻辑框，底锚 bottom、水平中心 centerX。</summary>
        private static Rectangle FitPortrait(Size bmpSize, Layout L,
            float maxW, float maxH, float centerX, float bottom)
        {
            float ar = (float)bmpSize.Width / bmpSize.Height;
            float w = Math.Min(maxW, maxH * ar);
            float h = w / ar;
            RectangleF logical = new RectangleF(centerX - w / 2f, bottom - h, w, h);
            return MapRect(L, logical, true);
        }

        /// <summary>
        /// 立绘落位分派：
        /// - stageRect（外部 SWF union∩window crop 逻辑矩形）→ 1:1 落舞台，保作者取景；
        /// - 纸娃娃 → 内部窗左上角的 425.2² 作者窗口，超出内部 mask 的底部裁掉；
        /// - 其余（内部静态/无元数据）→ 既有统一 fit。
        /// </summary>
        private static Rectangle ComputePortraitDestFor(Size bmpSize, Layout L,
            RectangleF? stageRect, bool doll, DialogueUiSkin skin)
        {
            if (bmpSize.Width <= 0 || bmpSize.Height <= 0) return Rectangle.Empty;
            if (stageRect.HasValue
                && stageRect.Value.Width > 0 && stageRect.Value.Height > 0)
                return MapRect(L, stageRect.Value, true);
            if (doll && skin != null)
            {
                RectangleF w = skin.DollClip;
                // PNG 以原肖像窗左上角取方形画布，骨架保持原作大小；底部由原 mask 裁去。
                float side = Math.Max(w.Width, w.Height);
                return MapRect(L, new RectangleF(w.Left, w.Top, side, side), true);
            }
            return ComputePortraitDest(bmpSize, L);
        }

        /// <summary>配图目标框：≤400×320 逻辑，右对齐面板右缘，底在面板顶上方；不随拖动。</summary>
        internal static Rectangle ComputeSceneDest(Size bmpSize, Layout L, Rectangle viewport)
        {
            if (bmpSize.Width <= 0 || bmpSize.Height <= 0) return Rectangle.Empty;
            const float maxW = 400f, maxH = 320f, gap = 14f;
            float ar = (float)bmpSize.Width / bmpSize.Height;
            float w = maxW, h = maxW / ar;
            if (h > maxH) { h = maxH; w = h * ar; }
            RectangleF logical = new RectangleF(
                DialogueUiSkin.PanelX + DialogueUiSkin.PanelW - w,
                DialogueUiSkin.PanelY - gap - h, w, h);
            Rectangle r = MapRect(L, logical, false);
            if (r.Y < viewport.Y) r = new Rectangle(r.X, viewport.Y, r.Width, r.Height);
            return r;
        }

        /// <summary>命中 zone：Close 最优先，其次 Drag（原图层序：移动层在按钮层之上），
        /// 再「下一句」透明热区；立绘/配图/头条其余区域不设热区（与原版一致）。</summary>
        private int ZoneAtLocked(Point screenPt)
        {
            Layout L = ComputeLayoutLocked();
            if (L.Panel.IsEmpty || !L.Viewport.Contains(screenPt)) return ZONE_NONE;
            if (L.Close.Contains(screenPt)) return ZONE_CLOSE;
            if (L.Drag.Contains(screenPt)) return ZONE_DRAG;
            if (L.Next.Contains(screenPt)) return ZONE_BODY;
            return ZONE_NONE;
        }

        // ════════════════ 打字/排版 ════════════════

        /// <summary>锁内：typing 是否完成。触发懒排版（UI 线程）。</summary>
        private bool TypingCompleteLocked()
        {
            EnsurePlanLocked();
            int total = _plan != null ? _plan.TotalGlyphs : 0;
            return _visibleChars >= total;
        }

        private void CompleteTyping()
        {
            lock (_gate)
            {
                if (_frame == null) return;
                EnsurePlanLocked();
                int total = _plan != null ? _plan.TotalGlyphs : 0;
                if (_visibleChars >= total) return;
                _visibleChars = total;
            }
            FireRepaint();
            UpdateAnim();
        }

        /// <summary>锁内懒排版：原字段宽度换算到等比文字空间，与 viewport 无关；
        /// key = 帧修订 + 文本。变才重排。</summary>
        private void EnsurePlanLocked()
        {
            NativeDialogueFrame f = _frame;
            if (f == null) { _plan = null; _planKey = null; return; }
            EnsureFontsLocked();
            EnsureMeasureLocked();
            int textW = Math.Max(1,
                (int)Math.Round(_skin.Body.TextLocalWidth - TEXT_INSET_LOCAL * 2));
            string key = f.RequestId + "\x1" + f.Revision + "\x1" + textW + "\x1"
                + (f.Text ?? "");
            if (_plan != null && string.Equals(_planKey, key, StringComparison.Ordinal))
                return;
            _plan = NativeDialogueTextLayout.Build(f.Text, textW, CharWidthLocked,
                _skin.Body.Color, _skin.Body.Html, _skin.Body.Indent);
            _planKey = key;
        }

        private float CharWidthLocked(char c)
        {
            float w;
            if (_charW.TryGetValue(c, out w)) return w;
            if (_measureG == null || _fontBody == null) return DialogueUiSkin.BodyFont;
            try
            {
                w = _measureG.MeasureString(c.ToString(), _fontBody,
                    int.MaxValue, _typoFormat).Width;
            }
            catch { w = DialogueUiSkin.BodyFont; }
            _charW[c] = w;
            return w;
        }

        /// <summary>字体按字段局部字号一次性创建（名 24 / 称号 14 / 正文 12，
        /// 渲染时挂 matrix 变换到屏幕尺寸，无需随 scale 重建）。</summary>
        private void EnsureFontsLocked()
        {
            if (_fontBody != null) return;
            _fontName = NativeHudFonts.CreateRoleFont("native.dialogue.body",
                _skin.Name.FontSize, FontStyle.Regular, GraphicsUnit.Pixel);
            _fontTitle = NativeHudFonts.CreateRoleFont("native.dialogue.body",
                _skin.Title.FontSize, FontStyle.Regular, GraphicsUnit.Pixel);
            _fontBody = NativeHudFonts.CreateRoleFont("native.dialogue.body",
                _skin.Body.FontSize, FontStyle.Regular, GraphicsUnit.Pixel);
            _charW.Clear();
            _plan = null; _planKey = null;
        }

        private void EnsureMeasureLocked()
        {
            if (_measureG != null) return;
            _measureBmp = new Bitmap(8, 8, PixelFormat.Format32bppPArgb);
            _measureG = Graphics.FromImage(_measureBmp);
            _measureG.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
            _typoFormat = new StringFormat(StringFormat.GenericTypographic)
            {
                FormatFlags = StringFormatFlags.NoWrap | StringFormatFlags.NoClip
                    | StringFormatFlags.MeasureTrailingSpaces,
                Trimming = StringTrimming.None
            };
            _fieldFormat = new StringFormat(StringFormat.GenericTypographic)
            {
                Trimming = StringTrimming.None
            };
        }

        // ════════════════ 位图所有权/缩放缓存 ════════════════

        /// <summary>克隆调用方位图为自持 32bppPArgb；失败退回 new Bitmap(src)。</summary>
        private static Bitmap CloneArgb(Bitmap src)
        {
            try
            {
                return src.Clone(new Rectangle(0, 0, src.Width, src.Height),
                    PixelFormat.Format32bppPArgb);
            }
            catch
            {
                try { return new Bitmap(src); } catch { return null; }
            }
        }

        /// <summary>缩放缓存：源/目标尺寸未变不重缩。源图所有权不动。
        /// Paint 懒路径保留为兜底：布局变化或后台预缩未完成时仍是正确性来源。</summary>
        private Bitmap EnsureScaled(ref Bitmap cache, ref int cw, ref int ch,
            Bitmap src, int w, int h)
        {
            if (w <= 0 || h <= 0 || src == null) return null;
            if (cache != null && cw == w && ch == h) return cache;
            DisposeBitmap(ref cache);
            cache = RenderScaled(src, w, h);
            cw = w; ch = h;
            return cache;
        }

        /// <summary>HighQualityBicubic 缩放到 w×h（32bppPArgb）：Paint 懒缩放与
        /// 后台预缩共用同一组参数，两处产物可互换（预缩完成无需 repaint）。</summary>
        private static Bitmap RenderScaled(Bitmap src, int w, int h)
        {
            Bitmap next = new Bitmap(w, h, PixelFormat.Format32bppPArgb);
            using (Graphics g = Graphics.FromImage(next))
            {
                g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                g.SmoothingMode = SmoothingMode.HighQuality;
                g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                g.DrawImage(src, new Rectangle(0, 0, w, h),
                    0, 0, src.Width, src.Height, GraphicsUnit.Pixel);
            }
            return next;
        }

        /// <summary>
        /// 后台预缩（立绘）：替换路径换入新图后在池线程预生成缩放图，把
        /// HighQualityBicubic（实测 ~18ms）从首次 Paint 的 UI 线程挪走。
        /// held = widget 持有的源图（锁内校验用），src = 私有克隆（渲染源；
        /// GDI+ 只对不同 Bitmap 实例并发安全，池线程渲染全程不持 _gate）。
        /// 完成后锁内校验：未 _disposed、held 仍是当前 _portraitBmp、
        /// _portraitScaled 仍为空（懒缩放未先跑）——任一不满足即丢弃。
        /// </summary>
        private void StartPortraitPrescale(Bitmap held, Bitmap src, int w, int h)
        {
            Task.Run(delegate
            {
                Bitmap scaled = null;
                try { scaled = RenderScaled(src, w, h); }
                catch { /* 预缩失败不致命：Paint 懒缩放兜底 */ }
                src.Dispose();
                if (scaled == null) return;
                bool adopt;
                lock (_gate)
                {
                    adopt = !_disposed && ReferenceEquals(_portraitBmp, held)
                        && _portraitScaled == null;
                    if (adopt)
                    {
                        _portraitScaled = scaled;
                        _portraitScaledW = w;
                        _portraitScaledH = h;
                    }
                }
                if (!adopt) scaled.Dispose();
            });
        }

        /// <summary>后台预缩（配图）：与 <see cref="StartPortraitPrescale"/> 同规则。</summary>
        private void StartScenePrescale(Bitmap held, Bitmap src, int w, int h)
        {
            Task.Run(delegate
            {
                Bitmap scaled = null;
                try { scaled = RenderScaled(src, w, h); }
                catch { /* 预缩失败不致命：Paint 懒缩放兜底 */ }
                src.Dispose();
                if (scaled == null) return;
                bool adopt;
                lock (_gate)
                {
                    adopt = !_disposed && ReferenceEquals(_sceneBmp, held)
                        && _sceneScaled == null;
                    if (adopt)
                    {
                        _sceneScaled = scaled;
                        _sceneScaledW = w;
                        _sceneScaledH = h;
                    }
                }
                if (!adopt) scaled.Dispose();
            });
        }

        private static void DisposeBitmap(ref Bitmap b)
        {
            if (b != null) { b.Dispose(); b = null; }
        }

        private void DisposePortraitLocked()
        {
            DisposeBitmap(ref _portraitBmp);
            DisposeBitmap(ref _portraitScaled);
            _portraitPending = false;
            _portraitHeldIsDoll = false;
            _portraitStageRect = null;
        }

        private void DisposeSceneLocked()
        {
            DisposeBitmap(ref _sceneBmp);
            DisposeBitmap(ref _sceneScaled);
            _scenePending = false;
        }

        // ════════════════ 状态清理 ════════════════

        private void ClearSessionLocked()
        {
            _frame = null;
            _visibleChars = 0;
            _manualFirstLine = -1;
            _typingWallElapsedMs = _typingTickElapsedMs = 0;
            _plan = null;
            _planKey = null;
            DisarmGestureLocked();
            _closeHover = false;
            _dragHover = false;
            DisposePortraitLocked();
            DisposeSceneLocked();
            _portraitIdentity = null;
            _scenePath = null;
            // 拖动偏移刻意保留：原 startDrag 移动的是常驻 clip，跨会话不回弹。
        }

        private void DisarmGestureLocked()
        {
            _gestureArmed = false;
            _gestureRequestId = null;
            _gestureRevision = 0;
            _gestureZone = ZONE_NONE;
        }

        private void SetHovers(bool closeHover, bool dragHover)
        {
            bool changed;
            lock (_gate)
            {
                changed = _closeHover != closeHover || _dragHover != dragHover;
                _closeHover = closeHover;
                _dragHover = dragHover;
            }
            if (changed) FireRepaint();
        }

        /// <summary>锁外：按当前态刷新 _animActive，仅变化时 fire AnimationStateChanged。</summary>
        private void UpdateAnim()
        {
            if (UpdateAnimSafe()) FireAnimChanged();
        }

        private bool UpdateAnimSafe()
        {
            lock (_gate) { return UpdateAnimLocked(); }
        }

        /// <summary>锁内：重算动画需求并返回是否变化。plan 未建时按 Text 非空估算——
        /// 保证 ShowFrame 后 tick 能启动，首个 Tick 内排版再校准。</summary>
        private bool UpdateAnimLocked()
        {
            bool typingLeft = _plan != null
                ? _visibleChars < _plan.TotalGlyphs
                : !string.IsNullOrEmpty(_frame != null ? _frame.Text : null);
            bool want = _frame != null && !_suppressed && !_disposed && typingLeft;
            if (want == _animActive) return false;
            _animActive = want;
            return true;
        }

        private void FireAnimChanged()
        {
            EventHandler h = AnimationStateChanged;
            if (h != null) { try { h(this, EventArgs.Empty); } catch { } }
        }

        private void FireInput(NativeDialogueFrame f, string verb)
        {
            Action<NativeDialogueFrame, string> cb = InputRequested;
            if (cb == null) return;
            try { cb(f.Snapshot(), verb); }
            catch (Exception ex)
            {
                LogManager.Log("[NativeDialogue] InputRequested throw: " + ex.Message);
            }
        }

        /// <summary>
        /// Visible + ScreenBounds 快照：BoundsOrVisibilityChanged 改为「实际变化才发」。
        /// 覆层收到该事件会绕过 33ms 合并定时器立即全量重绘 + UpdateLayeredWindow；
        /// 换句但可见性/几何未动（同立绘同配图）时这次提交是纯浪费，故按快照对比过滤。
        /// RepaintRequested 不动——repaint 走 33ms 合并，便宜。
        /// </summary>
        private struct BoundsSnapshot
        {
            internal bool Visible;
            internal Rectangle Bounds;
        }

        /// <summary>锁内调用：Visible/ScreenBounds 的 getter 自取 _gate，lock 可重入。</summary>
        private BoundsSnapshot SnapshotBoundsLocked()
        {
            return new BoundsSnapshot { Visible = Visible, Bounds = ScreenBounds };
        }

        private static bool BoundsChanged(BoundsSnapshot before, BoundsSnapshot after)
        {
            return before.Visible != after.Visible || before.Bounds != after.Bounds;
        }

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

        private void DisposeFontsLocked()
        {
            if (_fontName != null) { _fontName.Dispose(); _fontName = null; }
            if (_fontTitle != null) { _fontTitle.Dispose(); _fontTitle = null; }
            if (_fontBody != null) { _fontBody.Dispose(); _fontBody = null; }
        }

        public void Dispose()
        {
            bool boundsChanged;
            lock (_gate)
            {
                if (_disposed) return;
                BoundsSnapshot before = SnapshotBoundsLocked();
                _disposed = true;
                ClearSessionLocked();
                DisposeFontsLocked();
                DisposeBitmap(ref _portraitScaled);
                DisposeBitmap(ref _sceneScaled);
                if (_measureG != null) { _measureG.Dispose(); _measureG = null; }
                if (_measureBmp != null) { _measureBmp.Dispose(); _measureBmp = null; }
                if (_typoFormat != null) { _typoFormat.Dispose(); _typoFormat = null; }
                if (_fieldFormat != null) { _fieldFormat.Dispose(); _fieldFormat = null; }
                foreach (SolidBrush b in _brushCache.Values) b.Dispose();
                _brushCache.Clear();
                if (_ownsSkin && _skin != null) _skin.Dispose();
                boundsChanged = BoundsChanged(before, SnapshotBoundsLocked());
            }
            try { _anchor.Resize -= _anchorResizeHandler; } catch { }
            if (boundsChanged) FireBounds();   // 曾可见 → 通知覆层撤掉这片区域
            UpdateAnim();
        }

        // ════════════════ 测试钩子（InternalsVisibleTo("Launcher.Tests")） ════════════════

        /// <summary>打字节拍（ms/字），测试可调小加速。</summary>
        internal int TypingIntervalMs
        {
            get { lock (_gate) { return _charMs; } }
            set { lock (_gate) { _charMs = Math.Max(1, value); } }
        }

        internal bool TypingCompleteForTest
        {
            get { lock (_gate) { return _frame != null && TypingCompleteLocked(); } }
        }

        internal int VisibleCharsForTest
        {
            get { lock (_gate) { return _visibleChars; } }
        }

        internal int TotalGlyphsForTest
        {
            get { lock (_gate) { EnsurePlanLocked(); return _plan != null ? _plan.TotalGlyphs : 0; } }
        }

        internal bool HasPortraitForTest
        {
            get { lock (_gate) { return _portraitBmp != null; } }
        }

        /// <summary>测试：当前自持立绘位图引用（同图跳过路径下必须保持不变）。</summary>
        internal Bitmap PortraitBitmapForTest
        {
            get { lock (_gate) { return _portraitBmp; } }
        }

        internal bool PortraitPendingForTest
        {
            get { lock (_gate) { return _portraitPending; } }
        }

        /// <summary>测试：持有立绘自己的取景类别（hold 期间应仍是旧图的值）。</summary>
        internal bool PortraitHeldIsDollForTest
        {
            get { lock (_gate) { return _portraitHeldIsDoll; } }
        }

        /// <summary>测试：立绘缩放缓存尺寸（Empty = 未生成；后台预缩/懒缩放共用）。</summary>
        internal Size PortraitScaledSizeForTest
        {
            get { lock (_gate) { return _portraitScaled != null ? _portraitScaled.Size : Size.Empty; } }
        }

        /// <summary>测试：配图缩放缓存尺寸（Empty = 未生成）。</summary>
        internal Size SceneScaledSizeForTest
        {
            get { lock (_gate) { return _sceneScaled != null ? _sceneScaled.Size : Size.Empty; } }
        }

        internal bool HasSceneImageForTest
        {
            get { lock (_gate) { return _sceneBmp != null; } }
        }

        /// <summary>测试：当前自持配图位图引用（同图跳过路径下必须保持不变）。</summary>
        internal Bitmap SceneBitmapForTest
        {
            get { lock (_gate) { return _sceneBmp; } }
        }

        internal bool ScenePendingForTest
        {
            get { lock (_gate) { return _scenePending; } }
        }

        internal bool GestureArmedForTest
        {
            get { lock (_gate) { return _gestureArmed; } }
        }

        internal bool SuppressedForTest
        {
            get { lock (_gate) { return _suppressed; } }
        }

        internal int PlanLineCountForTest
        {
            get { lock (_gate) { EnsurePlanLocked(); return _plan != null ? _plan.Lines.Count : 0; } }
        }

        /// <summary>测试：当前面板拖动偏移（舞台逻辑 px）。</summary>
        internal PointF DragOffsetForTest
        {
            get { lock (_gate) { return new PointF(_dragDX, _dragDY); } }
        }

        /// <summary>测试：给定 viewport 下的版面快照（确定性注入，不读真实锚点）。</summary>
        internal Layout ComputeLayoutForTest(Rectangle viewport)
        {
            lock (_gate) { return ComputeLayoutCore(viewport); }
        }

        /// <summary>全部屏幕矩形的单出口（锁内）：vp + scale + 拖动偏移 + 图尺寸。</summary>
        private Layout ComputeLayoutCore(Rectangle vp)
        {
            Layout L = new Layout();
            if (vp.Width <= 0 || vp.Height <= 0) return L;
            float scale = RightHudLayout.ScaleForViewport(vp);
            L.Scale = scale;
            L.Viewport = vp;
            L.DragDX = _dragDX;
            L.DragDY = _dragDY;
            L.StageOrigin = StageOrigin(vp, scale);
            L.Stage = new Rectangle(
                (int)Math.Round(L.StageOrigin.X + _dragDX * scale),
                (int)Math.Round(L.StageOrigin.Y + _dragDY * scale),
                Math.Max(1, (int)Math.Round(DialogueUiSkin.StageW * scale)),
                Math.Max(1, (int)Math.Round(DialogueUiSkin.StageH * scale)));

            DialogueUiSkin skin = _skin;
            L.Panel = MapRect(L, skin.PanelArt, true);
            L.Text = MapRect(L, skin.Body.Stage, true);
            L.Name = MapRect(L, skin.Name.Stage, true);
            L.Title = MapRect(L, skin.Title.Stage, true);
            L.Next = MapRect(L, skin.NextHit, true);
            L.Close = MapRect(L, skin.Close.Hit, true);
            L.Drag = MapRect(L, skin.Drag.Hit, true);
            // 续画期用旧图自己的取景类别（hold-last-frame：新帧身份不得套用到旧图）；
            // 无图时按当前帧预估（决定 clip 形态，不影响绘制）。
            bool doll = _portraitBmp != null
                ? _portraitHeldIsDoll
                : (_frame != null && _frame.IsDoll);
            L.PortraitClip = MapRect(L, doll ? skin.DollClip : skin.PortraitClip, true);
            L.Strip = Rectangle.FromLTRB(L.Panel.Left, L.Panel.Top,
                L.Panel.Right, Math.Max(L.Panel.Top, L.Next.Top));

            Bitmap pb = _portraitBmp;
            if (pb != null)
                L.Portrait = ComputePortraitDestFor(pb.Size, L,
                    _portraitStageRect, doll, skin);
            Bitmap sb = _sceneBmp;
            if (sb != null) L.Scene = ComputeSceneDest(sb.Size, L, vp);
            return L;
        }

        /// <summary>测试：给定 glyph 阈值的首个可见行（滚底窗口顶）。</summary>
        internal int FirstVisibleLineForTest(int visibleChars, int capacity)
        {
            lock (_gate)
            {
                EnsurePlanLocked();
                if (_plan == null || _plan.Lines.Count == 0) return 0;
                int last = NativeDialogueTextLayout.LastNeededLine(_plan, visibleChars);
                int first = Math.Max(0, last - Math.Max(1, capacity) + 1);
                return _manualFirstLine < 0 ? first : Math.Min(first, _manualFirstLine);
            }
        }
    }
}
