using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using CF7Launcher.AgentRuntime.Security;
using CF7Launcher.Diagnostic;
using CF7Launcher.Guardian.Hud;

namespace CF7Launcher.Guardian
{
    internal enum PanelGeometryMeasurementKind
    {
        Valid,
        ExplicitInvalid,
        Unavailable
    }

    internal readonly struct PanelGeometryMeasurement
    {
        private PanelGeometryMeasurement(
            PanelGeometryMeasurementKind kind,
            Rectangle rect,
            string source,
            string reason)
        {
            Kind = kind;
            Rect = rect;
            Source = source ?? "unknown";
            Reason = reason ?? "unspecified";
        }

        internal PanelGeometryMeasurementKind Kind { get; }
        internal Rectangle Rect { get; }
        internal string Source { get; }
        internal string Reason { get; }

        internal static PanelGeometryMeasurement FromViewport(
            double viewportX,
            double viewportY,
            double viewportWidth,
            double viewportHeight,
            Point screenOrigin,
            string source,
            string reason)
        {
            if (!double.IsFinite(viewportX)
                || !double.IsFinite(viewportY)
                || !double.IsFinite(viewportWidth)
                || !double.IsFinite(viewportHeight))
            {
                return ExplicitInvalid(source, "non_finite");
            }
            if (viewportWidth <= 1.0 || viewportHeight <= 1.0)
            {
                return ExplicitInvalid(source,
                    viewportWidth <= 0.0 || viewportHeight <= 0.0
                        ? "non_positive"
                        : "transient_sentinel");
            }

            double screenX = screenOrigin.X + viewportX;
            double screenY = screenOrigin.Y + viewportY;
            if (!double.IsFinite(screenX) || !double.IsFinite(screenY)
                || screenX < int.MinValue || screenX > int.MaxValue
                || screenY < int.MinValue || screenY > int.MaxValue
                || viewportWidth > int.MaxValue || viewportHeight > int.MaxValue)
            {
                return ExplicitInvalid(source, "out_of_range");
            }

            int width = (int)viewportWidth;
            int height = (int)viewportHeight;
            if (width <= 1 || height <= 1)
                return ExplicitInvalid(source, "transient_sentinel");
            return Valid(
                new Rectangle((int)screenX, (int)screenY, width, height),
                source,
                reason);
        }

        internal static PanelGeometryMeasurement FromRectangle(
            Rectangle rect,
            string source,
            string reason)
        {
            if (rect.Width <= 1 || rect.Height <= 1)
            {
                return ExplicitInvalid(source,
                    rect.Width <= 0 || rect.Height <= 0
                        ? "non_positive"
                        : "transient_sentinel");
            }
            return Valid(rect, source, reason);
        }

        internal static PanelGeometryMeasurement Valid(
            Rectangle rect,
            string source,
            string reason)
        {
            return new PanelGeometryMeasurement(
                PanelGeometryMeasurementKind.Valid,
                rect,
                source,
                reason);
        }

        internal static PanelGeometryMeasurement ExplicitInvalid(
            string source,
            string reason)
        {
            return new PanelGeometryMeasurement(
                PanelGeometryMeasurementKind.ExplicitInvalid,
                Rectangle.Empty,
                source,
                reason);
        }

        internal static PanelGeometryMeasurement Unavailable(
            string source,
            string reason)
        {
            return new PanelGeometryMeasurement(
                PanelGeometryMeasurementKind.Unavailable,
                Rectangle.Empty,
                source,
                reason);
        }
    }

    internal enum PanelRestoreRevalidationDisposition
    {
        None,
        ReplayCommitted,
        GeometryChanged
    }

    internal sealed class PanelRestoreRevalidationGate
    {
        private int _generation;
        private bool _pending;

        internal bool IsPendingFor(int generation)
        {
            return _pending && generation > 0 && _generation == generation;
        }

        internal bool Mark(int generation, bool hasCommittedSnapshot)
        {
            if (generation <= 0 || !hasCommittedSnapshot) return false;
            _generation = generation;
            _pending = true;
            return true;
        }

        internal PanelRestoreRevalidationDisposition Consume(
            int generation,
            bool sameGeometry)
        {
            if (!_pending) return PanelRestoreRevalidationDisposition.None;
            if (generation <= 0 || _generation != generation)
            {
                Clear();
                return PanelRestoreRevalidationDisposition.None;
            }
            Clear();
            return sameGeometry
                ? PanelRestoreRevalidationDisposition.ReplayCommitted
                : PanelRestoreRevalidationDisposition.GeometryChanged;
        }

        internal void Clear()
        {
            _generation = 0;
            _pending = false;
        }
    }

    internal interface IPanelHudCompanion
    {
        // PanelHost cannot infer whether a throwing implementation changed
        // state before it failed. Implementations must therefore be
        // idempotent and must not let suspend/resume exceptions escape.
        void Suspend();
        void Resume();
    }

    /// <summary>
    /// Panel 状态机：把 OpenPanel / ClosePanel 序列化为命令队列，按序在 UI 线程执行。
    ///
    /// 核心不变量（Phase 2 起完全成立；Phase 1 stub 阶段尚未严格）：
    ///   IsPanelOpen ⇔ WebOverlay 在 panel-rect/opaque/non-layered 状态
    ///                ⇔ NativePanelBackdrop 显示
    ///                ⇔ NativeHudOverlay 已 Suspend
    ///                ⇔ InputShield 在 telemetry 模式
    ///
    /// 异常恢复：任何 DoOpen/DoClose 路径中途抛 → catch → ResetToClosedState 强制走 close 序列回到一致基线。
    /// 连续 N 次失败 → 熔断清空队列防级联失败。
    ///
    /// Phase 2 完整序列：
    /// - FlashSnapshot.Capture → ComposeBackdrop → backdrop 显示
    /// - WebOverlay.ResumeForPanel 完整去 LAYERED+TRANSPARENT/timer 恢复/PostToWeb
    /// - panelRect 经 PanelLayoutCatalog 决定
    /// - SetPanelEscapeEnabled 由 PanelHost 接管（_escSource）
    /// - InputShield 进 telemetry 模式（filter 为前台=Guardian + anchor 内 + panelRect 外）
    /// </summary>
    public class PanelHostController : IDisposable
    {
        private sealed class PanelGeometrySnapshot
        {
            internal string PanelName;
            internal string PanelInstanceId;
            internal IntPtr OwnerHwnd;
            internal int OwnerHandleGeneration;
            internal int FocusGeneration;
            internal Rectangle AnchorRect;
            internal Rectangle PanelRect;
            internal string Source;
            internal string ValidReason;
            internal string MonitorDeviceName;
            internal int Dpi;

            internal bool HasSameGeometry(PanelGeometrySnapshot other)
            {
                return other != null
                    && AnchorRect.Equals(other.AnchorRect)
                    && PanelRect.Equals(other.PanelRect);
            }

            internal bool HasSameOwnerAndDisplay(PanelGeometrySnapshot other)
            {
                return other != null
                    && OwnerHwnd == other.OwnerHwnd
                    && OwnerHandleGeneration == other.OwnerHandleGeneration
                    && string.Equals(MonitorDeviceName, other.MonitorDeviceName,
                        StringComparison.Ordinal)
                    && Dpi == other.Dpi;
            }
        }

        #region Win32

        [DllImport("user32.dll")]
        private static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter,
            int X, int Y, int cx, int cy, uint uFlags);

        private static readonly IntPtr HWND_TOP = new IntPtr(0);
        private const uint SWP_NOMOVE = 0x0002;
        private const uint SWP_NOSIZE = 0x0001;
        private const uint SWP_NOACTIVATE = 0x0010;
        private const uint SWP_SHOWWINDOW = 0x0040;

        #endregion

        public enum PanelCommandKind { Open, Close }

        public enum TrackedOpenOutcome
        {
            OpenPosted,
            PreExecutionRejected,
            PanelBusy,
            PostNotDelivered,
            PostAcceptedThenFailed,
            Failed
        }

        public enum VisualRetireOutcome
        {
            RetiredExact,
            VisualAlreadyAbsent,
            Superseded,
            HostUnavailable
        }

        public enum ExactReplaceOutcome
        {
            TargetCommitted,
            SourceMismatch,
            PreExecutionRejected,
            PostNotDelivered,
            HostUnavailable
        }

        private sealed class VisualRetireWaiter
        {
            public bool RetiredExact;
            public Action<VisualRetireOutcome> Completed;
        }

        public struct PanelCommand
        {
            public PanelCommandKind Kind;
            public string Name;
            public string InitDataJson;          // 可空；OpenPanel 序列化进 panel_cmd
            public string ReturnToName;          // 可空；非空 = 关闭本 panel 时自动 reopen 之
            public string ReturnInitDataJson;    // 可空；reopen returnTo 时用作 initData
            public bool IsTrackedOpen;
            public bool IsTrackedClose;
            public bool IsExactClose;
            public bool IsVisualRetire;
            public bool IsExactReplace;
            public bool DismissReturnStackOnExactClose;
            public string ReservedPanelInstanceId;
            public Func<bool> TrackedExecutionGate;
            public Action<TrackedOpenOutcome> TrackedOpenCompleted;
            public Action<bool> TrackedCloseCompleted;
            public Action<bool> ExactCloseCompleted;
            public Func<bool> ExactCloseExecutionGate;
            public Action ExactCloseCommitNoFail;
            public Action<VisualRetireOutcome> VisualRetireCompleted;
            public string ExpectedSourcePanel;
            public string ExpectedSourceInstanceId;
            public PreparedPanelReplace PreparedReplace;
            public Func<bool> ExactReplaceExecutionGate;
            public Action<ExactReplaceOutcome> ExactReplaceCompleted;
            public PanelCommand(PanelCommandKind kind, string name, string initDataJson)
                : this(kind, name, initDataJson, null, null)
            {
            }
            public PanelCommand(PanelCommandKind kind, string name, string initDataJson,
                string returnToName, string returnInitDataJson)
            {
                Kind = kind;
                Name = name;
                InitDataJson = initDataJson;
                ReturnToName = returnToName;
                ReturnInitDataJson = returnInitDataJson;
                IsTrackedOpen = false;
                IsTrackedClose = false;
                IsExactClose = false;
                IsVisualRetire = false;
                IsExactReplace = false;
                DismissReturnStackOnExactClose = false;
                ReservedPanelInstanceId = null;
                TrackedExecutionGate = null;
                TrackedOpenCompleted = null;
                TrackedCloseCompleted = null;
                ExactCloseCompleted = null;
                ExactCloseExecutionGate = null;
                ExactCloseCommitNoFail = null;
                VisualRetireCompleted = null;
                ExpectedSourcePanel = null;
                ExpectedSourceInstanceId = null;
                PreparedReplace = null;
                ExactReplaceExecutionGate = null;
                ExactReplaceCompleted = null;
            }
        }

        // ── Return Stack（B-ready 的 A 实现）─────────────────────────────────────
        // A 时代（当前）：调用方显式声明 returnTo。OpenPanel(name, init, returnTo, returnInit)
        //                  push 一个 entry；ClosePanel 时 pop 栈顶并自动 reopen。
        // B 时代（未来）：调用方不传 returnTo，OpenPanel 内部自动 push 当前 _activePanel。
        //                  栈数据结构本身不变；只改 OpenPanel 入口逻辑。
        // 栈深度当前最大 1（map → stage-select → arena 链路里只有 arena 用 returnTo）；
        // 设计成栈是为了未来扩展 0 修改。
        private struct ReturnStackEntry
        {
            public string Name;
            public string InitDataJson;
            public ReturnStackEntry(string name, string initDataJson)
            {
                Name = name;
                InitDataJson = initDataJson;
            }
        }
        private readonly List<ReturnStackEntry> _returnStack = new List<ReturnStackEntry>();

        private readonly Form _ownerForm;
        private readonly WebOverlayForm _web;
        private readonly NativeHudOverlay _hud;
        private readonly NativePanelBackdrop _backdrop;
        private readonly InputShieldForm _shield;
        private readonly HitNumberOverlay _hitNumber;
        private readonly INativeCursor _cursor;
        private readonly IPanelEscapeSource _escSource;
        private readonly Func<IntPtr> _flashHwndProvider; // 可空：null 时降级走 placeholder backdrop
        private readonly IPanelHudCompanion _hudCompanion;
        private bool _hudCompanionSuspended;

        private readonly Queue<PanelCommand> _queue = new Queue<PanelCommand>();
        private readonly List<VisualRetireWaiter> _visualRetireWaiters =
            new List<VisualRetireWaiter>();
        private readonly object _queueLock = new object();
        private long _openAdmissionEpoch;
        private Func<string, bool> _openGate;
        private Func<string, bool> _rebindGate;
        private Func<string, string, string, string> _securityInitDataEnricher;
        private Func<string, string, string, string> _initDataEnricher;
        private Action<string, string> _panelCloseObserver;
        public event Action<string, string> PanelClosed;
        internal event Action<string, string> PanelChanged;
        private PanelCommand? _deferredRebind;
        private PanelCommand? _deferredBarrierOpen;
        private bool _processing;
        private bool _delayedKickRegistered;

        private volatile string _activePanel; // null = closed
        private volatile string _activePanelInstanceId;
        // 仅在 settings 实例存活期间保留进入面板时的原分辨率裁切快照；不写磁盘、不进日志。
        private string _activeSettingsPreviewDataUrl;
        private int _activeSettingsPreviewWidth;
        private int _activeSettingsPreviewHeight;
        internal const int SettingsPreviewMaximumWidth = 4096;
        internal const int SettingsPreviewMaximumHeight = 2304;
        internal const int SettingsPreviewMaximumDataUriCharacters = 8 * 1024 * 1024;
        private bool _trackedOpenReserved;
        private bool _exactReplaceReserved;
        private volatile string _trackedLeasePanelName;
        private volatile string _trackedLeaseInstanceId;
        private string _idleFenceToken;
        private readonly Action<Action> _testPumpDispatcher;
        private readonly Action<Action> _testClosedEventDispatcher;
        private Func<string, bool> _testExactReplacePoster;
        private Action _testBeforeDoClose;
        private string _lastOpenPayloadForTest;
        /// <summary>测试线束（_testPumpDispatcher）路径下最后一次 DoOpen 的完整 open payload。</summary>
        internal string LastOpenPayloadForTest { get { return _lastOpenPayloadForTest; } }
        public bool IsPanelOpen { get { return _activePanel != null; } }
        public string ActivePanelName { get { return _activePanel; } }
        public string ActivePanelInstanceId { get { return _activePanelInstanceId; } }
        public bool HasTrackedPanelLease { get { return _trackedLeaseInstanceId != null; } }

        private int _consecutiveFailures;
        private const int FAILURE_CIRCUIT_BREAKER = 5;

        // owner 移动/大小变化时跟随：DoOpen 订阅，DoClose 与 ResetToClosedState 反订阅
        private bool _ownerLayoutSubscribed;
        // 节流：LocationChanged 拖窗时高频触发；用 BeginInvoke 合并到下一个消息泵循环
        private bool _ownerLayoutPending;
        private System.Windows.Forms.Timer _ownerLayoutSettleTimer;
        private Rectangle _lastOwnerAnchorRect = Rectangle.Empty;
        private Rectangle _lastOwnerPanelRect = Rectangle.Empty;
        private int _ownerHandleGeneration;
        private PanelGeometrySnapshot _committedGeometry;
        private readonly PanelRestoreRevalidationGate _restoreRevalidation =
            new PanelRestoreRevalidationGate();
        private bool _disposed;

        public PanelHostController(
            Form ownerForm,
            WebOverlayForm web,
            NativeHudOverlay hud,
            NativePanelBackdrop backdrop,
            InputShieldForm shield,
            HitNumberOverlay hitNumber,
            INativeCursor cursor,
            IPanelEscapeSource escSource,
            Func<IntPtr> flashHwndProvider)
            : this(
                ownerForm,
                web,
                hud,
                backdrop,
                shield,
                hitNumber,
                cursor,
                escSource,
                flashHwndProvider,
                null)
        {
        }

        internal PanelHostController(
            Form ownerForm,
            WebOverlayForm web,
            NativeHudOverlay hud,
            NativePanelBackdrop backdrop,
            InputShieldForm shield,
            HitNumberOverlay hitNumber,
            INativeCursor cursor,
            IPanelEscapeSource escSource,
            Func<IntPtr> flashHwndProvider,
            IPanelHudCompanion hudCompanion)
        {
            if (ownerForm == null) throw new ArgumentNullException("ownerForm");
            if (web == null) throw new ArgumentNullException("web");
            if (hud == null) throw new ArgumentNullException("hud");
            if (backdrop == null) throw new ArgumentNullException("backdrop");

            _ownerForm = ownerForm;
            _web = web;
            _hud = hud;
            _backdrop = backdrop;
            _shield = shield;     // 可空
            _hitNumber = hitNumber; // 可空
            _cursor = cursor;       // 可空（Program.cs 某些配置下不创建）
            _escSource = escSource; // 可空（fallback hotkey 模式下没有）
            _flashHwndProvider = flashHwndProvider; // 可空（snapshot 不可用时降级 placeholder）
            _hudCompanion = hudCompanion; // 可空；独立 split surface 仍由 Program 持有/释放
            _ownerHandleGeneration = ownerForm.IsHandleCreated ? 1 : 0;

            // Backdrop 点击外侧 → web panel_esc（等价 web 端 panels.js 的 backdrop click）
            _backdrop.BackdropClickedOutsidePanel += OnBackdropClickOutsidePanel;
        }

        /// <summary>
        /// Deterministic queue/surface harness for behavioral tests. Production always uses the
        /// WinForms constructor above; this constructor deliberately exercises the real command,
        /// identity, tracked-lease, waiter, and event code without creating native windows.
        /// </summary>
        internal PanelHostController(
            Action<Action> pumpDispatcher,
            Action<Action> closedEventDispatcher)
            : this(pumpDispatcher, closedEventDispatcher, null)
        {
        }

        internal PanelHostController(
            Action<Action> pumpDispatcher,
            Action<Action> closedEventDispatcher,
            IPanelHudCompanion hudCompanion)
        {
            if (pumpDispatcher == null)
                throw new ArgumentNullException("pumpDispatcher");
            _testPumpDispatcher = pumpDispatcher;
            _testClosedEventDispatcher =
                closedEventDispatcher ?? delegate(Action fire) { fire(); };
            _hudCompanion = hudCompanion;
        }

        private void OnBackdropClickOutsidePanel()
        {
            if (_disposed) return;
            // Native backdrop 与物理 Escape 共用 panel_esc transport，但 reason 必须
            // 保持可区分；材料档案只允许物理 Escape 消费本地搜索/树层级。
            // 不发 cmd:"request_close" —— panels.js 的 panel_cmd 仅 handle open/close/force_close
            try
            {
                _web.PostToWeb(
                    "{\"type\":\"panel_esc\",\"reason\":\"backdrop\"}");
            }
            catch (Exception ex) { LogManager.Log("[PanelHost] backdrop esc post failed: " + ex.Message); }
        }

        #region Public API

        public void OpenPanel(string name)
        {
            TryOpenPanel(name, null, null, null);
        }

        public void OpenPanel(string name, string initDataJson)
        {
            TryOpenPanel(name, initDataJson, null, null);
        }

        /// <summary>
        /// 完整 OpenPanel：returnToName 非空时，关闭本 panel 会自动 reopen returnTo
        /// （带 returnInitDataJson）。返回路径形成栈，支持嵌套（当前生产只用到 1 层）。
        /// </summary>
        public void OpenPanel(string name, string initDataJson, string returnToName, string returnInitDataJson)
        {
            TryOpenPanel(name, initDataJson, returnToName, returnInitDataJson);
        }

        /// <summary>
        /// 仅在 open 命令已进入 PanelHost 队列时返回 true。需要在上游回包中声称
        /// “已接受”时必须使用本入口，不能把 void OpenPanel 的调用完成当作接受凭据。
        /// </summary>
        public bool TryOpenPanel(string name, string initDataJson, string returnToName, string returnInitDataJson)
        {
            if (_disposed || string.IsNullOrEmpty(name)) return false;
            return EnqueueAndPump(new PanelCommand(
                PanelCommandKind.Open, name, initDataJson, returnToName, returnInitDataJson));
        }

        /// <summary>
        /// Captures a quiescent Host proof for a delayed, nonce-bound generic open.  The proof covers
        /// queued/processing commands, tracked reservations and leases, idle fences, deferred
        /// opens, visual-retire barriers, the return stack, and the exact active identity.  It is
        /// only useful with TryOpenPanelFromAdmission, which validates and consumes the proof
        /// atomically with enqueue.
        /// </summary>
        internal bool TryCaptureOpenAdmission(
            out long admissionEpoch,
            out string activePanel,
            out string activeInstance)
        {
            lock (_queueLock)
            {
                admissionEpoch = _openAdmissionEpoch;
                activePanel = _activePanel;
                activeInstance = _activePanelInstanceId;
                return IsStableOpenAdmissionLocked(
                    activePanel,
                    activeInstance);
            }
        }

        /// <summary>
        /// Captures only the exact active source tuple for a delayed replacement. A matching
        /// tracked lease is allowed because TryReplacePanelExact consumes it atomically; callers
        /// must still pass the captured tuple back to that exact replacement entry.
        /// </summary>
        internal bool TryCaptureExactReplaceBaseline(
            out string activePanel,
            out string activeInstance)
        {
            lock (_queueLock)
            {
                activePanel = _activePanel;
                activeInstance = _activePanelInstanceId;
                return IsStableExactReplaceAdmissionLocked(
                    activePanel,
                    activeInstance);
            }
        }

        /// <summary>
        /// Atomically admits a delayed generic open only if no Host lifecycle mutation has occurred
        /// since TryCaptureOpenAdmission and the Host still has the exact captured active identity.
        /// </summary>
        internal bool TryOpenPanelFromAdmission(
            long admissionEpoch,
            string expectedActivePanel,
            string expectedActiveInstance,
            string name,
            string initDataJson,
            string returnToName,
            string returnInitDataJson)
        {
            if (_disposed || string.IsNullOrEmpty(name)) return false;
            return EnqueueAndPump(
                new PanelCommand(
                    PanelCommandKind.Open,
                    name,
                    initDataJson,
                    returnToName,
                    returnInitDataJson),
                admissionEpoch,
                expectedActivePanel,
                expectedActiveInstance);
        }

        internal bool IsOpenAdmissionCurrent(
            long admissionEpoch,
            string expectedActivePanel,
            string expectedActiveInstance)
        {
            lock (_queueLock)
            {
                return admissionEpoch == _openAdmissionEpoch
                    && IsStableOpenAdmissionLocked(
                        expectedActivePanel,
                        expectedActiveInstance);
            }
        }

        /// <summary>
        /// Reserves a caller-supplied panel instance before enqueue, then rechecks the caller's
        /// authority on the UI thread immediately before any DOM/open side effect.  Tracked opens
        /// never rebind or evict another panel.
        /// </summary>
        public bool TryOpenTrackedPanel(string name, string initDataJson,
            string reservedPanelInstanceId, Func<bool> executionGate,
            Action<TrackedOpenOutcome> completed)
        {
            if (_disposed || string.IsNullOrEmpty(name)
                || string.IsNullOrEmpty(reservedPanelInstanceId)
                || executionGate == null) return false;
            PanelCommand command = new PanelCommand(PanelCommandKind.Open, name, initDataJson);
            command.IsTrackedOpen = true;
            command.ReservedPanelInstanceId = reservedPanelInstanceId;
            command.TrackedExecutionGate = executionGate;
            command.TrackedOpenCompleted = completed;
            return EnqueueAndPump(command);
        }

        /// <summary>Closes only the exact tracked instance; a stale instance can never close a replacement.</summary>
        public bool TryCloseTrackedPanelExact(string panelName, string panelInstanceId,
            Action<bool> completed)
        {
            if (_disposed || string.IsNullOrEmpty(panelName) || string.IsNullOrEmpty(panelInstanceId))
                return false;
            PanelCommand command = new PanelCommand(PanelCommandKind.Close, panelName, null);
            command.IsTrackedClose = true;
            command.ReservedPanelInstanceId = panelInstanceId;
            command.TrackedCloseCompleted = completed;
            return EnqueueAndPump(command);
        }

        /// <summary>
        /// Queues a generic close that remains bound to the exact visible instance at execution.
        /// A delayed workbench close can therefore never tear down a same-name replacement.
        /// </summary>
        public bool TryClosePanelExact(string panelName, string panelInstanceId,
            Action<bool> completed)
        {
            return TryClosePanelExact(
                panelName,
                panelInstanceId,
                false,
                completed);
        }

        /// <summary>
        /// Queues an exact close and optionally dismisses its return path. Deferred open/rebind
        /// intent and the optional return-stack dismissal are consumed only after the exact active
        /// instance still matches on execution; stale closes are side-effect free.
        /// </summary>
        public bool TryClosePanelExact(
            string panelName,
            string panelInstanceId,
            bool dismissReturnStack,
            Action<bool> completed)
        {
            if (_disposed || string.IsNullOrEmpty(panelName)
                || string.IsNullOrEmpty(panelInstanceId)) return false;
            PanelCommand command =
                new PanelCommand(PanelCommandKind.Close, panelName, null);
            command.IsExactClose = true;
            command.DismissReturnStackOnExactClose =
                dismissReturnStack;
            command.ReservedPanelInstanceId = panelInstanceId;
            command.ExactCloseCompleted = completed;
            return EnqueueAndPump(command);
        }

        /// <summary>
        /// Narrow exact-close settlement primitive. The execution gate runs on the UI thread before
        /// any close side effect; after it grants an irrevocable commit permit, the no-fail commit
        /// callback consumes the caller's private capability before PanelChanged retires the owner.
        /// </summary>
        internal bool TryClosePanelExact(
            string panelName,
            string panelInstanceId,
            bool dismissReturnStack,
            Func<bool> executionGate,
            Action commitNoFail,
            Action<bool> completed)
        {
            if (_disposed || string.IsNullOrEmpty(panelName)
                || string.IsNullOrEmpty(panelInstanceId)
                || executionGate == null
                || commitNoFail == null) return false;
            PanelCommand command =
                new PanelCommand(PanelCommandKind.Close, panelName, null);
            command.IsExactClose = true;
            command.DismissReturnStackOnExactClose =
                dismissReturnStack;
            command.ReservedPanelInstanceId = panelInstanceId;
            command.ExactCloseExecutionGate = executionGate;
            command.ExactCloseCommitNoFail = commitNoFail;
            command.ExactCloseCompleted = completed;
            return EnqueueAndPump(command);
        }

        /// <summary>
        /// Atomically replaces one exact active panel without closing/reopening the native panel
        /// surface.  The prepared plan is the sole source of target tuple, immutable initData and
        /// capability ownership.
        /// </summary>
        public bool TryReplacePanelExact(
            string expectedSourcePanel,
            string expectedSourceInstance,
            PreparedPanelReplace plan,
            Func<bool> executionGate,
            Action<ExactReplaceOutcome> completed)
        {
            if (_disposed
                || string.IsNullOrEmpty(expectedSourcePanel)
                || string.IsNullOrEmpty(expectedSourceInstance)
                || plan == null
                || executionGate == null)
            {
                if (plan != null) plan.AbortPrepared();
                return false;
            }
            PanelCommand command =
                new PanelCommand(
                    PanelCommandKind.Open,
                    plan.TargetPanel,
                    plan.ImmutableInitDataJson);
            command.IsExactReplace = true;
            command.ExpectedSourcePanel = expectedSourcePanel;
            command.ExpectedSourceInstanceId = expectedSourceInstance;
            command.PreparedReplace = plan;
            command.ExactReplaceExecutionGate = executionGate;
            command.ExactReplaceCompleted = completed;
            bool admitted = EnqueueAndPump(command);
            if (!admitted) plan.AbortPrepared();
            return admitted;
        }

        internal void SetExactReplacePosterForTests(
            Func<string, bool> poster)
        {
            _testExactReplacePoster = poster;
        }

        internal void SetBeforeDoCloseForTests(Action callback)
        {
            _testBeforeDoClose = callback;
        }

        /// <summary>
        /// Retires the requested visual without ever closing a different instance. Unlike a
        /// generic exact close, this request is admitted behind an already-reserved tracked open
        /// and through a matching tracked lease. Its completion is an authoritative Host-idle
        /// proof and does not depend on the best-effort PanelClosed notification.
        /// </summary>
        public bool TryRetirePanelVisualExact(
            string panelName,
            string panelInstanceId,
            Action<VisualRetireOutcome> completed)
        {
            if (_disposed || string.IsNullOrEmpty(panelName)
                || string.IsNullOrEmpty(panelInstanceId)
                || completed == null)
            {
                return false;
            }
            bool confirmedVisualIdle = false;
            lock (_queueLock)
            {
                confirmedVisualIdle =
                    IsStableOpenAdmissionLocked(
                        null,
                        null);
                if (_idleFenceToken != null
                    && !confirmedVisualIdle)
                {
                    return false;
                }
            }
            if (confirmedVisualIdle)
            {
                try
                {
                    completed(
                        VisualRetireOutcome.VisualAlreadyAbsent);
                }
                catch { }
                return true;
            }
            PanelCommand command =
                new PanelCommand(PanelCommandKind.Close, panelName, null);
            command.IsVisualRetire = true;
            command.ReservedPanelInstanceId = panelInstanceId;
            command.VisualRetireCompleted = completed;
            return EnqueueAndPump(command);
        }

        public bool IsIdleForTrackedOpen
        {
            get
            {
                lock (_queueLock)
                    return IsStableOpenAdmissionLocked(
                        null,
                        null);
            }
        }

        /// <summary>
        /// Reserves a proven-idle orchestration fence without invoking external code under the
        /// queue lock. While held, every generic/tracked enqueue fails closed. This is used around
        /// an unscoped pause release so no fresh panel can acquire the lease between idle proof and
        /// the socket write.
        /// </summary>
        public bool TryAcquireIdleFence(string token)
        {
            if (string.IsNullOrEmpty(token)) return false;
            lock (_queueLock)
            {
                if (!IsStableOpenAdmissionLocked(
                        null,
                        null)) return false;
                _idleFenceToken = token;
                _openAdmissionEpoch++;
                return true;
            }
        }

        public bool ReleaseIdleFenceExact(string token)
        {
            if (string.IsNullOrEmpty(token)) return false;
            lock (_queueLock)
            {
                if (!string.Equals(_idleFenceToken, token, StringComparison.Ordinal)) return false;
                _idleFenceToken = null;
                _openAdmissionEpoch++;
                return true;
            }
        }

        public void ClosePanel()
        {
            if (_disposed) return;
            lock (_queueLock)
            {
                _deferredRebind = null;
                _deferredBarrierOpen = null;
            }
            if (!EnqueueAndPump(new PanelCommand(PanelCommandKind.Close, null, null)))
                LogManager.Log("[PanelHost] generic close rejected while tracked open/lease is active");
        }

        public void SetOpenGate(Func<string, bool> gate) { _openGate = gate; }
        public void SetRebindGate(Func<string, bool> gate) { _rebindGate = gate; }
        internal void SetSecurityInitDataEnricher(
            Func<string, string, string, string> enricher)
        {
            _securityInitDataEnricher = enricher;
        }
        public void SetInitDataEnricher(Func<string, string, string, string> enricher) { _initDataEnricher = enricher; }
        public void SetPanelCloseObserver(Action<string, string> observer) { _panelCloseObserver = observer; }

        /// <summary>协调器回到可 rebind 状态后，只恢复最后一次同 panel 意图。</summary>
        public void FlushDeferredRebind(string panelName)
        {
            PanelCommand? deferred = null;
            lock (_queueLock)
            {
                if (_deferredRebind.HasValue
                    && string.Equals(_deferredRebind.Value.Name, panelName, StringComparison.Ordinal))
                {
                    deferred = _deferredRebind;
                    _deferredRebind = null;
                }
            }
            if (deferred.HasValue
                && !EnqueueAndPump(deferred.Value))
            {
                lock (_queueLock)
                {
                    if (!_disposed
                        && !_deferredRebind.HasValue)
                    {
                        _deferredRebind = deferred;
                    }
                }
            }
        }

        /// <summary>
        /// Resumes the last generic open stopped by a global authority barrier. The gate is checked
        /// again on execution, so an early callback cannot escape a still-retained binding.
        /// </summary>
        public void FlushDeferredBarrierOpen()
        {
            PanelCommand? deferred = null;
            lock (_queueLock)
            {
                if (_deferredBarrierOpen.HasValue)
                {
                    deferred = _deferredBarrierOpen;
                    _deferredBarrierOpen = null;
                }
            }
            if (deferred.HasValue
                && !EnqueueAndPump(deferred.Value))
            {
                lock (_queueLock)
                {
                    if (!_disposed
                        && !_deferredBarrierOpen.HasValue)
                    {
                        _deferredBarrierOpen = deferred;
                    }
                }
            }
        }

        /// <summary>
        /// Atomically drops the last generic open captured behind a global authority barrier.
        /// Character Build -> Skills consumes the old navigation edge instead of replaying a
        /// competing request that arrived while acknowledged detach recovery was still pending.
        /// </summary>
        public bool DiscardDeferredBarrierOpen()
        {
            lock (_queueLock)
            {
                bool discarded =
                    _deferredBarrierOpen.HasValue;
                _deferredBarrierOpen =
                    null;
                return discarded;
            }
        }

        private bool IsStableOpenAdmissionLocked(
            string expectedActivePanel,
            string expectedActiveInstance)
        {
            return !_disposed
                && string.Equals(
                    _activePanel,
                    expectedActivePanel,
                    StringComparison.Ordinal)
                && string.Equals(
                    _activePanelInstanceId,
                    expectedActiveInstance,
                    StringComparison.Ordinal)
                && _queue.Count == 0
                && !_processing
                && !_trackedOpenReserved
                && !_exactReplaceReserved
                && _trackedLeaseInstanceId == null
                && _idleFenceToken == null
                && !_deferredRebind.HasValue
                && !_deferredBarrierOpen.HasValue
                && _visualRetireWaiters.Count == 0
                && _returnStack.Count == 0;
        }

        private bool IsStableExactReplaceAdmissionLocked(
            string expectedActivePanel,
            string expectedActiveInstance)
        {
            bool trackedLeaseCompatible =
                _trackedLeaseInstanceId == null
                || string.Equals(
                    _trackedLeasePanelName,
                    expectedActivePanel,
                    StringComparison.Ordinal)
                    && string.Equals(
                        _trackedLeaseInstanceId,
                        expectedActiveInstance,
                        StringComparison.Ordinal);
            return !_disposed
                && string.Equals(
                    _activePanel,
                    expectedActivePanel,
                    StringComparison.Ordinal)
                && string.Equals(
                    _activePanelInstanceId,
                    expectedActiveInstance,
                    StringComparison.Ordinal)
                && trackedLeaseCompatible
                && _queue.Count == 0
                && !_processing
                && !_trackedOpenReserved
                && !_exactReplaceReserved
                && _idleFenceToken == null
                && !_deferredRebind.HasValue
                && !_deferredBarrierOpen.HasValue
                && _visualRetireWaiters.Count == 0
                && _returnStack.Count == 0;
        }

        /// <summary>
        /// 异常路径（断线 / force_close / 进程退出前）专用：清空 return stack，
        /// 让接下来的 ClosePanel 不要尝试 reopen 任何上层 panel。
        /// 正常 user-close 路径（点 ✕ / ESC / backdrop）不应该调本方法。
        /// </summary>
        public void ClearReturnStack()
        {
            if (_disposed) return;
            lock (_queueLock)
            {
                _returnStack.Clear();
                _deferredBarrierOpen = null;
            }
        }

        #endregion

        #region Queue

        private bool EnqueueAndPump(PanelCommand cmd)
        {
            return EnqueueAndPump(
                cmd,
                null,
                null,
                null);
        }

        private bool EnqueueAndPump(
            PanelCommand cmd,
            long? requiredOpenAdmission,
            string expectedActivePanel,
            string expectedActiveInstance)
        {
            if (_disposed) return false;
            lock (_queueLock)
            {
                if (_disposed) return false;
                if (requiredOpenAdmission.HasValue
                    && (requiredOpenAdmission.Value
                            != _openAdmissionEpoch
                        || !IsStableOpenAdmissionLocked(
                            expectedActivePanel,
                            expectedActiveInstance)))
                {
                    return false;
                }
                if (_idleFenceToken != null) return false;
                if (cmd.IsExactReplace)
                {
                    if (!IsStableExactReplaceAdmissionLocked(
                            cmd.ExpectedSourcePanel,
                            cmd.ExpectedSourceInstanceId))
                    {
                        return false;
                    }
                    _exactReplaceReserved = true;
                }
                else if (cmd.IsTrackedOpen)
                {
                    if (!IsStableOpenAdmissionLocked(
                            null,
                            null))
                        return false;
                    _trackedOpenReserved = true;
                }
                else if (cmd.IsTrackedClose)
                {
                    if (_trackedLeaseInstanceId == null
                        || !string.Equals(_trackedLeasePanelName, cmd.Name, StringComparison.Ordinal)
                        || !string.Equals(_trackedLeaseInstanceId, cmd.ReservedPanelInstanceId,
                            StringComparison.Ordinal))
                        return false;
                }
                else if (cmd.IsExactClose)
                {
                    // A tracked source may use the richer exact-close settlement
                    // primitive, but only for its own lease.  This is what permits a
                    // GameStage battle handoff to commit before DoClose without letting
                    // a generic close consume or bypass a different tracked owner.
                    if (_trackedOpenReserved || _exactReplaceReserved
                        || (_trackedLeaseInstanceId != null
                        && (!string.Equals(_trackedLeasePanelName, cmd.Name,
                                StringComparison.Ordinal)
                            || !string.Equals(_trackedLeaseInstanceId,
                                cmd.ReservedPanelInstanceId,
                                StringComparison.Ordinal))))
                    {
                        return false;
                    }
                }
                else if (!cmd.IsVisualRetire
                    && (_trackedOpenReserved
                        || _exactReplaceReserved
                        || _trackedLeaseInstanceId != null))
                {
                    return false;
                }
                _queue.Enqueue(cmd);
                _openAdmissionEpoch++;
                if (_processing) return true;
                _processing = true;
            }

            // guard: handle 未创建时 BeginInvoke 抛
            if (_testPumpDispatcher != null)
            {
                try
                {
                    _testPumpDispatcher(PumpQueue);
                    return true;
                }
                catch (Exception ex)
                {
                    LogManager.Log(
                        "[PanelHost] test pump dispatch failed: "
                        + ex.Message);
                    FailPendingPumpDispatch(false);
                    return false;
                }
            }

            if (!_ownerForm.IsHandleCreated)
            {
                if (!_delayedKickRegistered)
                {
                    _delayedKickRegistered = true;
                    _ownerForm.HandleCreated += DelayedKickOnHandleCreated;
                }
                return true;
            }
            try
            {
                _ownerForm.BeginInvoke(new Action(PumpQueue));
            }
            catch (Exception ex)
            {
                LogManager.Log("[PanelHost] BeginInvoke pump failed: " + ex.Message);
                if (cmd.IsVisualRetire
                    && !_ownerForm.InvokeRequired)
                {
                    // All production retire callers enter on the owner thread. If the handle is
                    // torn down between the precheck and BeginInvoke, finish the already-admitted
                    // queue directly instead of leaking the CharacterBuild authority barrier.
                    PumpQueue();
                    return true;
                }
                // 释放 _processing 让下次入队能重试
                FailPendingPumpDispatch(true);
                return false;
            }
            return true;
        }

        private void DelayedKickOnHandleCreated(object sender, EventArgs e)
        {
            _ownerForm.HandleCreated -= DelayedKickOnHandleCreated;
            _delayedKickRegistered = false;
            if (_disposed) return;
            try { _ownerForm.BeginInvoke(new Action(PumpQueue)); }
            catch (Exception ex)
            {
                LogManager.Log("[PanelHost] delayed pump kick failed: " + ex.Message);
                FailPendingPumpDispatch(false);
            }
        }

        private void FailPendingPumpDispatch(bool skipFirstCallback)
        {
            List<PanelCommand> failed = new List<PanelCommand>();
            lock (_queueLock)
            {
                while (_queue.Count != 0) failed.Add(_queue.Dequeue());
                _processing = false;
                _trackedOpenReserved = false;
                _exactReplaceReserved = false;
            }
            for (int i = 0; i < failed.Count; i++)
            {
                PanelCommand command = failed[i];
                if (skipFirstCallback && i == 0
                    && !command.IsVisualRetire
                    && !command.IsExactReplace) continue;
                if (command.IsExactReplace)
                {
                    if (command.PreparedReplace != null)
                        command.PreparedReplace.AbortPrepared();
                    if (command.ExactReplaceCompleted != null)
                    {
                        try
                        {
                            command.ExactReplaceCompleted(
                                ExactReplaceOutcome.HostUnavailable);
                        }
                        catch { }
                    }
                    continue;
                }
                if (command.IsTrackedOpen && command.TrackedOpenCompleted != null)
                {
                    try { command.TrackedOpenCompleted(TrackedOpenOutcome.PreExecutionRejected); }
                    catch { }
                }
                if (command.IsTrackedClose && command.TrackedCloseCompleted != null)
                {
                    try { command.TrackedCloseCompleted(false); }
                    catch { }
                }
                if (command.IsExactClose && command.ExactCloseCompleted != null)
                {
                    try { command.ExactCloseCompleted(false); }
                    catch { }
                }
                if (command.IsVisualRetire
                    && command.VisualRetireCompleted != null)
                {
                    try
                    {
                        command.VisualRetireCompleted(
                            VisualRetireOutcome.HostUnavailable);
                    }
                    catch { }
                }
            }
        }

        private void PumpQueue()
        {
            if (_disposed)
            {
                List<PanelCommand> abandoned = new List<PanelCommand>();
                lock (_queueLock)
                {
                    while (_queue.Count != 0)
                        abandoned.Add(_queue.Dequeue());
                    _processing = false;
                    _exactReplaceReserved = false;
                }
                foreach (PanelCommand command in abandoned)
                {
                    if (!command.IsExactReplace) continue;
                    if (command.PreparedReplace != null)
                        command.PreparedReplace.AbortPrepared();
                    if (command.ExactReplaceCompleted != null)
                    {
                        try
                        {
                            command.ExactReplaceCompleted(
                                ExactReplaceOutcome.HostUnavailable);
                        }
                        catch { }
                    }
                }
                return;
            }
            while (true)
            {
                PanelCommand cmd = default(PanelCommand);
                bool queueDrained;
                lock (_queueLock)
                {
                    queueDrained = _queue.Count == 0;
                    if (queueDrained)
                    {
                        _processing = false;
                    }
                    else
                    {
                        cmd = _queue.Dequeue();
                    }
                }
                if (queueDrained)
                {
                    CompleteVisualRetireWaitersIfIdle();
                    return;
                }
                try
                {
                    ExecuteCommand(cmd);
                }
                catch (Exception ex)
                {
                    LogManager.Log("[PanelHost] command failed: " + ex);
                    try { ResetToClosedState(); }
                    catch (Exception ex2) { LogManager.Log("[PanelHost] reset failed: " + ex2); }
                }
            }
        }

        private void ExecuteCommand(PanelCommand cmd)
        {
            if (cmd.IsExactReplace)
            {
                ExecuteExactReplace(cmd);
                return;
            }
            if (cmd.IsVisualRetire)
            {
                ExecuteVisualRetire(cmd);
                return;
            }
            if (cmd.IsTrackedOpen)
            {
                ExecuteTrackedOpen(cmd);
                return;
            }
            if (cmd.IsTrackedClose)
            {
                ExecuteTrackedClose(cmd);
                return;
            }
            if (cmd.IsExactClose)
            {
                ExecuteExactClose(cmd);
                return;
            }
            if (cmd.Kind == PanelCommandKind.Open)
            {
                if (HasVisualRetireBarrier())
                {
                    lock (_queueLock)
                    {
                        _deferredBarrierOpen = cmd;
                    }
                    LogManager.Log(
                        "[PanelHost] open deferred by visual-retire barrier: "
                        + cmd.Name);
                    _consecutiveFailures = 0;
                    return;
                }
                Func<string, bool> openGate = _openGate;
                if (openGate != null && !openGate(cmd.Name))
                {
                    lock (_queueLock)
                    {
                        _deferredBarrierOpen = cmd;
                    }
                    LogManager.Log(
                        "[PanelHost] open deferred by authority barrier: "
                        + cmd.Name);
                    _consecutiveFailures = 0;
                    return;
                }
                if (_activePanel == cmd.Name)
                {
                    Func<string, bool> gate = _rebindGate;
                    if (gate != null && !gate(cmd.Name))
                    {
                        lock (_queueLock) { _deferredRebind = cmd; }
                        LogManager.Log("[PanelHost] rebind deferred: " + cmd.Name);
                        _consecutiveFailures = 0;
                        return;
                    }
                    DoRebind(cmd);
                    _consecutiveFailures = 0;
                    return;
                }
                if (_activePanel != null) DoClose();
                if (!DoOpen(cmd.Name, cmd.InitDataJson))
                {
                    _consecutiveFailures = 0;
                    return;
                }
                // 只有成功发布窗口组后才建立 return edge；geometry/pause/presentation
                // admission 失败不能留下一个会在后续 close 中误触发的幽灵返回项。
                if (!string.IsNullOrEmpty(cmd.ReturnToName))
                {
                    _returnStack.Add(new ReturnStackEntry(cmd.ReturnToName, cmd.ReturnInitDataJson));
                }
            }
            else
            {
                if (_activePanel == null) { _consecutiveFailures = 0; return; }
                DoClose();
                // pop 栈顶：若有 returnTo，enqueue 一个 Open（不带新 returnTo，避免无限链）。
                // PumpQueue 是 while(true) 循环，enqueue 后下一轮自然处理。
                // 异常路径（断线 / force_close）应在 ClosePanel 之前调 ClearReturnStack 跳过 reopen。
                if (_returnStack.Count > 0)
                {
                    QueueReturnOpen();
                }
            }
            _consecutiveFailures = 0;
        }

        private void ExecuteTrackedOpen(PanelCommand cmd)
        {
            TrackedOpenOutcome outcome = TrackedOpenOutcome.Failed;
            bool executionStarted = false;
            bool webPostAccepted = false;
            try
            {
                if (HasVisualRetireBarrier())
                {
                    outcome =
                        TrackedOpenOutcome.PreExecutionRejected;
                    return;
                }
                if (_activePanel != null || _trackedLeaseInstanceId != null)
                {
                    outcome = TrackedOpenOutcome.PanelBusy;
                    return;
                }
                if (cmd.TrackedExecutionGate == null || !cmd.TrackedExecutionGate())
                {
                    outcome = TrackedOpenOutcome.PreExecutionRejected;
                    return;
                }
                executionStarted = true;
                if (!DoOpen(cmd.Name, cmd.InitDataJson, cmd.ReservedPanelInstanceId, true,
                    delegate { webPostAccepted = true; }))
                {
                    outcome = TrackedOpenOutcome.PostNotDelivered;
                    return;
                }
                _trackedLeasePanelName = cmd.Name;
                _trackedLeaseInstanceId = cmd.ReservedPanelInstanceId;
                outcome = TrackedOpenOutcome.OpenPosted;
                _consecutiveFailures = 0;
            }
            catch (Exception ex)
            {
                LogManager.Log("[PanelHost] tracked open failed: " + ex.Message);
                if (executionStarted)
                {
                    try { ResetToClosedState(); }
                    catch (Exception resetEx)
                    {
                        LogManager.Log("[PanelHost] tracked open reset failed: " + resetEx.Message);
                    }
                    outcome = webPostAccepted
                        ? TrackedOpenOutcome.PostAcceptedThenFailed
                        : TrackedOpenOutcome.PostNotDelivered;
                }
                else
                {
                    outcome = TrackedOpenOutcome.PreExecutionRejected;
                }
            }
            finally
            {
                lock (_queueLock) { _trackedOpenReserved = false; }
                Action<TrackedOpenOutcome> completed = cmd.TrackedOpenCompleted;
                if (completed != null)
                {
                    try { completed(outcome); }
                    catch (Exception ex)
                    {
                        LogManager.Log("[PanelHost] tracked open completion failed: " + ex.Message);
                    }
                }
            }
        }

        private void ExecuteExactReplace(PanelCommand command)
        {
            ExactReplaceOutcome outcome = ExactReplaceOutcome.HostUnavailable;
            bool committed = false;
            try
            {
                PreparedPanelReplace plan = command.PreparedReplace;
                if (plan == null)
                {
                    outcome = ExactReplaceOutcome.HostUnavailable;
                    return;
                }
                if (!string.Equals(
                        _activePanel,
                        command.ExpectedSourcePanel,
                        StringComparison.Ordinal)
                    || !string.Equals(
                        _activePanelInstanceId,
                        command.ExpectedSourceInstanceId,
                        StringComparison.Ordinal))
                {
                    outcome = ExactReplaceOutcome.SourceMismatch;
                    return;
                }
                bool sourceOwnsTrackedLease =
                    string.Equals(
                        _trackedLeasePanelName,
                        command.ExpectedSourcePanel,
                        StringComparison.Ordinal)
                    && string.Equals(
                        _trackedLeaseInstanceId,
                        command.ExpectedSourceInstanceId,
                        StringComparison.Ordinal);
                if (_trackedLeaseInstanceId != null
                    && !sourceOwnsTrackedLease)
                {
                    outcome = ExactReplaceOutcome.SourceMismatch;
                    return;
                }
                bool gateAccepted;
                try
                {
                    gateAccepted = command.ExactReplaceExecutionGate != null
                        && command.ExactReplaceExecutionGate();
                }
                catch (Exception ex)
                {
                    gateAccepted = false;
                    LogManager.Log(
                        "[PanelHost] exact replace execution gate threw: "
                        + ex.GetType().Name);
                }
                if (!gateAccepted)
                {
                    outcome = ExactReplaceOutcome.PreExecutionRejected;
                    return;
                }

                PanelGeometrySnapshot replaceGeometry = null;
                if (_testPumpDispatcher == null)
                {
                    PanelGeometryMeasurement replaceMeasurement;
                    if (!TryCreateProvisionalGeometry(
                            plan.TargetPanel,
                            plan.TargetInstanceId,
                            out replaceGeometry,
                            out replaceMeasurement))
                    {
                        LogManager.Log("[PanelGeometry] exact replace rejected"
                            + " kind=" + replaceMeasurement.Kind
                            + " source=" + replaceMeasurement.Source
                            + " reason=" + replaceMeasurement.Reason);
                        outcome = ExactReplaceOutcome.PreExecutionRejected;
                        return;
                    }
                }

                string payload = BuildPanelOpenPayload(
                    plan.TargetPanel,
                    plan.ImmutableInitDataJson,
                    plan.TargetInstanceId);
                bool delivered;
                try
                {
                    if (_testExactReplacePoster != null)
                        delivered = _testExactReplacePoster(payload);
                    else if (_testPumpDispatcher != null)
                        delivered = true;
                    else if (_web != null)
                        delivered = _web.TryPostToWeb(payload);
                    else
                    {
                        outcome = ExactReplaceOutcome.HostUnavailable;
                        return;
                    }
                }
                catch (Exception ex)
                {
                    delivered = false;
                    LogManager.Log(
                        "[PanelHost] exact replace post threw: "
                        + ex.GetType().Name);
                }
                if (!delivered)
                {
                    outcome = ExactReplaceOutcome.PostNotDelivered;
                    return;
                }

                if (!plan.CommitCapabilitiesNoFail())
                {
                    outcome = ExactReplaceOutcome.PreExecutionRejected;
                    return;
                }
                if (sourceOwnsTrackedLease)
                {
                    _trackedLeasePanelName = null;
                    _trackedLeaseInstanceId = null;
                }
                _activePanel = plan.TargetPanel;
                _activePanelInstanceId = plan.TargetInstanceId;
                if (replaceGeometry != null)
                {
                    RepositionBackdrop(replaceGeometry.AnchorRect, false);
                    _backdrop.SetPanelRect(replaceGeometry.PanelRect);
                    _web.RepositionForPanel(replaceGeometry.PanelRect, false);
                    if (_shield != null)
                    {
                        _shield.EnterTelemetryMode(
                            replaceGeometry.PanelRect,
                            _ownerForm.Handle,
                            replaceGeometry.AnchorRect,
                            _web.IsHandleCreated ? _web.Handle : IntPtr.Zero);
                    }
                    if (!CommitGeometry(
                            replaceGeometry,
                            _web.PanelSessionGeneration))
                    {
                        ClearCommittedGeometry(
                            "exact_replace_geometry_commit_rejected");
                    }
                }
                plan.NotifyTargetCommittedNoFail();
                PublishPanelChanged(
                    plan.TargetPanel,
                    plan.TargetInstanceId);
                committed = true;
                outcome = ExactReplaceOutcome.TargetCommitted;
                _consecutiveFailures = 0;
                LogManager.Log(
                    "[PanelHost] exact replace committed: "
                    + command.ExpectedSourcePanel + " -> "
                    + plan.TargetPanel + " instance="
                    + plan.TargetInstanceId);
            }
            finally
            {
                lock (_queueLock)
                {
                    _exactReplaceReserved = false;
                    _openAdmissionEpoch++;
                }
                if (!committed && command.PreparedReplace != null)
                    command.PreparedReplace.AbortPrepared();
                Action<ExactReplaceOutcome> completed =
                    command.ExactReplaceCompleted;
                if (completed != null)
                {
                    try { completed(outcome); }
                    catch (Exception ex)
                    {
                        LogManager.Log(
                            "[PanelHost] exact replace completion threw: "
                            + ex.GetType().Name);
                    }
                }
            }
        }

        private void ExecuteTrackedClose(PanelCommand cmd)
        {
            bool closed = false;
            try
            {
                if (!string.Equals(_trackedLeasePanelName, cmd.Name, StringComparison.Ordinal)
                    || !string.Equals(_trackedLeaseInstanceId, cmd.ReservedPanelInstanceId,
                        StringComparison.Ordinal)
                    || !string.Equals(_activePanel, cmd.Name, StringComparison.Ordinal)
                    || !string.Equals(_activePanelInstanceId, cmd.ReservedPanelInstanceId,
                        StringComparison.Ordinal))
                    return;
                _returnStack.Clear();
                DoClose();
                _trackedLeasePanelName = null;
                _trackedLeaseInstanceId = null;
                closed = true;
                _consecutiveFailures = 0;
            }
            finally
            {
                Action<bool> completed = cmd.TrackedCloseCompleted;
                if (completed != null)
                {
                    try { completed(closed); }
                    catch (Exception ex)
                    {
                        LogManager.Log("[PanelHost] tracked close completion failed: " + ex.Message);
                    }
                }
            }
        }

        private void ExecuteExactClose(PanelCommand cmd)
        {
            bool closed = false;
            try
            {
                if (!string.Equals(
                        _activePanel, cmd.Name, StringComparison.Ordinal)
                    || !string.Equals(
                        _activePanelInstanceId,
                        cmd.ReservedPanelInstanceId,
                        StringComparison.Ordinal))
                {
                    LogManager.Log(
                        "[PanelHost] stale exact close ignored: "
                        + (cmd.Name ?? "<null>") + " instance="
                        + (cmd.ReservedPanelInstanceId ?? "<null>"));
                    return;
                }
                if (cmd.ExactCloseExecutionGate != null)
                {
                    bool gateAccepted;
                    try
                    {
                        gateAccepted =
                            cmd.ExactCloseExecutionGate();
                    }
                    catch (Exception ex)
                    {
                        gateAccepted = false;
                        LogManager.Log(
                            "[PanelHost] exact close execution gate threw: "
                            + ex.GetType().Name);
                    }
                    if (!gateAccepted) return;
                }
                if (cmd.ExactCloseCommitNoFail != null)
                {
                    try { cmd.ExactCloseCommitNoFail(); }
                    catch (Exception ex)
                    {
                        // The callback contract is no-fail. Once the gate granted a commit permit,
                        // a caller bug cannot authorize rollback or resurrection of the source.
                        LogManager.Log(
                            "[PanelHost] exact close commit callback threw: "
                            + ex.GetType().Name);
                    }
                }
                lock (_queueLock)
                {
                    _deferredRebind = null;
                    _deferredBarrierOpen = null;
                    if (cmd.DismissReturnStackOnExactClose)
                        _returnStack.Clear();
                }
                DoClose();
                if (string.Equals(_trackedLeasePanelName, cmd.Name,
                        StringComparison.Ordinal)
                    && string.Equals(_trackedLeaseInstanceId,
                        cmd.ReservedPanelInstanceId,
                        StringComparison.Ordinal))
                {
                    _trackedLeasePanelName = null;
                    _trackedLeaseInstanceId = null;
                }
                closed = true;
                LogManager.Log(
                    AuthorityLogFormatter.FormatPanelExactCloseCompleted(
                        cmd.Name,
                        cmd.ReservedPanelInstanceId));
                if (!cmd.DismissReturnStackOnExactClose
                    && _returnStack.Count > 0)
                    QueueReturnOpen();
                _consecutiveFailures = 0;
            }
            finally
            {
                Action<bool> completed =
                    cmd.ExactCloseCompleted;
                if (completed != null)
                {
                    try { completed(closed); }
                    catch (Exception ex)
                    {
                        LogManager.Log(
                            "[PanelHost] exact close completion failed: "
                            + ex.Message);
                    }
                }
            }
        }

        private void ExecuteVisualRetire(
            PanelCommand cmd)
        {
            bool retiredExact = false;
            bool superseded = false;
            try
            {
                bool activeMatches =
                    string.Equals(
                        _activePanel,
                        cmd.Name,
                        StringComparison.Ordinal)
                    && string.Equals(
                        _activePanelInstanceId,
                        cmd.ReservedPanelInstanceId,
                        StringComparison.Ordinal);
                bool hasTrackedLease =
                    _trackedLeaseInstanceId != null;
                bool trackedLeaseMatches =
                    hasTrackedLease
                    && string.Equals(
                        _trackedLeasePanelName,
                        cmd.Name,
                        StringComparison.Ordinal)
                    && string.Equals(
                        _trackedLeaseInstanceId,
                        cmd.ReservedPanelInstanceId,
                        StringComparison.Ordinal);

                if (activeMatches
                    && (!hasTrackedLease
                        || trackedLeaseMatches))
                {
                    lock (_queueLock)
                    {
                        _returnStack.Clear();
                        _deferredRebind = null;
                        _deferredBarrierOpen = null;
                    }
                    DoClose();
                    if (trackedLeaseMatches)
                    {
                        _trackedLeasePanelName = null;
                        _trackedLeaseInstanceId = null;
                    }
                    retiredExact = true;
                    _consecutiveFailures = 0;
                }
                else if (_activePanel == null
                    && trackedLeaseMatches)
                {
                    // A reset may have removed the visual before the tracked close command could
                    // run. The exact lease no longer protects any visual and must not remain wedged.
                    _trackedLeasePanelName = null;
                    _trackedLeaseInstanceId = null;
                }
                else if (_activePanel != null
                    && !activeMatches)
                {
                    LogManager.Log(
                        "[PanelHost] stale visual retire superseded by replacement: "
                        + (_activePanel ?? "<null>") + " instance="
                        + (_activePanelInstanceId ?? "<null>")
                        + " requested=" + (cmd.Name ?? "<null>")
                        + " instance="
                        + (cmd.ReservedPanelInstanceId ?? "<null>"));
                    superseded = true;
                }

                if (!superseded
                    && _activePanel == null)
                {
                    lock (_queueLock)
                    {
                        superseded =
                            _deferredRebind.HasValue
                            || _deferredBarrierOpen.HasValue;
                    }
                    if (superseded)
                    {
                        LogManager.Log(
                            "[PanelHost] visual retire superseded by deferred panel intent: "
                            + (cmd.Name ?? "<null>") + " instance="
                            + (cmd.ReservedPanelInstanceId ?? "<null>"));
                    }
                }

                if (superseded)
                {
                    Action<VisualRetireOutcome> completed =
                        cmd.VisualRetireCompleted;
                    if (completed != null)
                    {
                        try
                        {
                            completed(
                                VisualRetireOutcome.Superseded);
                        }
                        catch (Exception ex)
                        {
                            LogManager.Log(
                                "[PanelHost] visual retire completion failed: "
                                + ex.Message);
                        }
                    }
                    return;
                }

                lock (_queueLock)
                {
                    _visualRetireWaiters.Add(
                        new VisualRetireWaiter
                        {
                            RetiredExact = retiredExact,
                            Completed =
                                cmd.VisualRetireCompleted
                        });
                }
            }
            catch (Exception ex)
            {
                LogManager.Log(
                    "[PanelHost] visual retire failed: "
                    + ex.Message);
                Action<VisualRetireOutcome> completed =
                    cmd.VisualRetireCompleted;
                if (completed != null)
                {
                    try
                    {
                        completed(
                            VisualRetireOutcome.HostUnavailable);
                    }
                    catch { }
                }
                throw;
            }
        }

        private bool HasVisualRetireBarrier()
        {
            lock (_queueLock)
            {
                // Only a retire command that has not executed yet orders before this open.
                // Once a retire has installed its completion waiter, later opens must be
                // allowed to run; the waiter will then complete as Superseded instead of
                // waiting on an open that is itself waiting on the waiter.
                foreach (PanelCommand queued in _queue)
                    if (queued.IsVisualRetire)
                        return true;
                return false;
            }
        }

        private void CompleteVisualRetireWaitersIfIdle()
        {
            List<VisualRetireWaiter> completed = null;
            bool superseded = false;
            lock (_queueLock)
            {
                if (_queue.Count != 0
                    || _processing
                    || _trackedOpenReserved)
                {
                    return;
                }
                if (_visualRetireWaiters.Count == 0)
                    return;
                superseded =
                    _activePanel != null
                    || _activePanelInstanceId != null
                    || _trackedLeaseInstanceId != null
                    || _idleFenceToken != null
                    || _deferredRebind.HasValue
                    || _deferredBarrierOpen.HasValue
                    || _returnStack.Count != 0;
                completed =
                    new List<VisualRetireWaiter>(
                        _visualRetireWaiters);
                _visualRetireWaiters.Clear();
            }

            foreach (VisualRetireWaiter waiter in completed)
            {
                Action<VisualRetireOutcome> callback =
                    waiter.Completed;
                if (callback == null) continue;
                try
                {
                    callback(
                        superseded
                            ? VisualRetireOutcome.Superseded
                            : (waiter.RetiredExact
                                ? VisualRetireOutcome.RetiredExact
                                : VisualRetireOutcome.VisualAlreadyAbsent));
                }
                catch (Exception ex)
                {
                    LogManager.Log(
                        "[PanelHost] visual retire completion failed: "
                        + ex.Message);
                }
            }
        }

        private void QueueReturnOpen()
        {
            var top = _returnStack[_returnStack.Count - 1];
            _returnStack.RemoveAt(_returnStack.Count - 1);
            lock (_queueLock)
            {
                _queue.Enqueue(new PanelCommand(
                    PanelCommandKind.Open,
                    top.Name,
                    top.InitDataJson));
                _openAdmissionEpoch++;
            }
        }

        #endregion

        #region DoOpen / DoClose

        /// <summary>
        /// 按来源顺序解析 anchor。只有 unavailable 允许尝试下一来源；explicit-invalid
        /// 保留因果身份并立即 fail closed，不能被 fallback 包装成合法矩形。
        /// </summary>
        internal static PanelGeometryMeasurement ResolveAnchorMeasurements(
            params Func<PanelGeometryMeasurement>[] sources)
        {
            PanelGeometryMeasurement lastUnavailable =
                PanelGeometryMeasurement.Unavailable("none", "no_source");
            if (sources == null) return lastUnavailable;
            foreach (Func<PanelGeometryMeasurement> source in sources)
            {
                if (source == null) continue;
                PanelGeometryMeasurement measurement;
                try { measurement = source(); }
                catch (Exception ex)
                {
                    measurement = PanelGeometryMeasurement.Unavailable(
                        "source_exception",
                        ex.GetType().Name);
                }
                if (measurement.Kind == PanelGeometryMeasurementKind.Valid
                    || measurement.Kind == PanelGeometryMeasurementKind.ExplicitInvalid)
                    return measurement;
                lastUnavailable = measurement;
            }
            return lastUnavailable;
        }

        private PanelGeometryMeasurement MeasureFlashPanelAnchor()
        {
            Control flashPanel = GetFlashPanelOrNull();
            if (flashPanel == null || flashPanel.IsDisposed)
                return PanelGeometryMeasurement.Unavailable(
                    "flash_panel",
                    "control_unavailable");
            if (!flashPanel.IsHandleCreated)
                return PanelGeometryMeasurement.Unavailable(
                    "flash_panel",
                    "handle_unavailable");
            Rectangle rect = new Rectangle(
                flashPanel.PointToScreen(Point.Empty),
                flashPanel.ClientSize);
            return PanelGeometryMeasurement.FromRectangle(
                rect,
                "flash_panel",
                "flash_panel_client");
        }

        private PanelGeometryMeasurement MeasureOwnerClientAnchor()
        {
            if (_ownerForm == null || _ownerForm.IsDisposed
                || !_ownerForm.IsHandleCreated)
            {
                return PanelGeometryMeasurement.Unavailable(
                    "owner_client",
                    "handle_unavailable");
            }
            Rectangle rect = new Rectangle(
                _ownerForm.PointToScreen(Point.Empty),
                _ownerForm.ClientSize);
            return PanelGeometryMeasurement.FromRectangle(
                rect,
                "owner_client",
                "owner_client");
        }

        private PanelGeometryMeasurement MeasureAnchorScreenRect()
        {
            if (_ownerForm.WindowState == FormWindowState.Minimized)
            {
                return PanelGeometryMeasurement.ExplicitInvalid(
                    "owner_state",
                    "minimized");
            }
            if (!_ownerForm.Visible)
            {
                return PanelGeometryMeasurement.ExplicitInvalid(
                    "owner_state",
                    "hidden");
            }
            return ResolveAnchorMeasurements(
                delegate { return _web.MeasureCurrentAnchorScreenRect(); },
                MeasureFlashPanelAnchor,
                MeasureOwnerClientAnchor);
        }

        private bool TryCreateProvisionalGeometry(
            string panelName,
            string localOpenIdentity,
            out PanelGeometrySnapshot provisional,
            out PanelGeometryMeasurement measurement)
        {
            provisional = null;
            measurement = MeasureAnchorScreenRect();
            if (measurement.Kind != PanelGeometryMeasurementKind.Valid)
                return false;
            if (string.IsNullOrEmpty(localOpenIdentity)
                || !_ownerForm.IsHandleCreated
                || _ownerForm.Handle == IntPtr.Zero)
            {
                measurement = PanelGeometryMeasurement.Unavailable(
                    "owner_identity",
                    "handle_unavailable");
                return false;
            }

            Rectangle panelRect = PanelLayoutCatalog.GetRect(
                panelName,
                measurement.Rect);
            PanelGeometryMeasurement panelMeasurement =
                PanelGeometryMeasurement.FromRectangle(
                    panelRect,
                    "panel_layout",
                    panelName ?? "unknown");
            if (panelMeasurement.Kind != PanelGeometryMeasurementKind.Valid)
            {
                measurement = panelMeasurement;
                return false;
            }

            Screen monitor;
            int dpi;
            try
            {
                monitor = Screen.FromRectangle(measurement.Rect);
                dpi = _ownerForm.DeviceDpi;
            }
            catch (Exception ex)
            {
                measurement = PanelGeometryMeasurement.Unavailable(
                    "display_identity",
                    ex.GetType().Name);
                return false;
            }
            if (monitor == null || string.IsNullOrEmpty(monitor.DeviceName)
                || dpi <= 0)
            {
                measurement = PanelGeometryMeasurement.Unavailable(
                    "display_identity",
                    "monitor_or_dpi_unavailable");
                return false;
            }

            provisional = new PanelGeometrySnapshot
            {
                PanelName = panelName,
                PanelInstanceId = localOpenIdentity,
                OwnerHwnd = _ownerForm.Handle,
                OwnerHandleGeneration = _ownerHandleGeneration,
                FocusGeneration = 0,
                AnchorRect = measurement.Rect,
                PanelRect = panelRect,
                Source = measurement.Source,
                ValidReason = measurement.Reason,
                MonitorDeviceName = monitor.DeviceName,
                Dpi = dpi
            };
            return true;
        }

        private bool CommitGeometry(
            PanelGeometrySnapshot provisional,
            int focusGeneration)
        {
            if (provisional == null || focusGeneration <= 0
                || !_ownerForm.IsHandleCreated
                || provisional.OwnerHwnd != _ownerForm.Handle
                || provisional.OwnerHandleGeneration != _ownerHandleGeneration
                || !string.Equals(provisional.PanelName, _activePanel,
                    StringComparison.Ordinal)
                || !string.Equals(provisional.PanelInstanceId,
                    _activePanelInstanceId, StringComparison.Ordinal)
                || _web.PanelSessionGeneration != focusGeneration)
            {
                return false;
            }
            try
            {
                Screen currentMonitor = Screen.FromRectangle(
                    provisional.AnchorRect);
                if (currentMonitor == null
                    || !string.Equals(
                        provisional.MonitorDeviceName,
                        currentMonitor.DeviceName,
                        StringComparison.Ordinal)
                    || provisional.Dpi != _ownerForm.DeviceDpi)
                    return false;
            }
            catch { return false; }
            provisional.FocusGeneration = focusGeneration;
            if (!_web.CommitPanelGeometry(
                    provisional.PanelRect,
                    focusGeneration))
                return false;
            _committedGeometry = provisional;
            _lastOwnerAnchorRect = provisional.AnchorRect;
            _lastOwnerPanelRect = provisional.PanelRect;
            _restoreRevalidation.Clear();
            LogManager.Log("[PanelGeometry] committed panel="
                + provisional.PanelName
                + " instance=" + provisional.PanelInstanceId
                + " focus_generation=" + focusGeneration
                + " owner_generation=" + provisional.OwnerHandleGeneration
                + " source=" + provisional.Source
                + " monitor=" + provisional.MonitorDeviceName
                + " dpi=" + provisional.Dpi
                + " rect=" + provisional.PanelRect);
            return true;
        }

        private void ClearCommittedGeometry(string reason)
        {
            _committedGeometry = null;
            _restoreRevalidation.Clear();
            if (_web != null)
                _web.ClearCommittedPanelGeometry(reason);
        }

        /// <summary>
        /// FlashSnapshot.Capture + ComposeBackdrop。失败/无 flashHwnd 时降级纯暗 dim 占位。
        /// 黑帧检测命中 → 提高 dim 强度兜底，避免玩家看到全黑无对比。
        /// </summary>
        private Bitmap CaptureBackdrop(
            Rectangle anchor,
            bool captureSettingsPreview,
            out string settingsPreviewDataUrl,
            out int settingsPreviewWidth,
            out int settingsPreviewHeight)
        {
            settingsPreviewDataUrl = null;
            settingsPreviewWidth = 0;
            settingsPreviewHeight = 0;
            IntPtr flashHwnd = (_flashHwndProvider != null) ? _flashHwndProvider() : IntPtr.Zero;
            if (flashHwnd == IntPtr.Zero)
            {
                if (captureSettingsPreview)
                    LogManager.Log("[PanelHost] settings entry preview rejected: flash_hwnd_unavailable");
                return ComposePlaceholderBackdrop(anchor);
            }
            FlashSnapshot.SnapshotResult snap = null;
            try
            {
                snap = FlashSnapshot.Capture(flashHwnd);
            }
            catch (Exception ex)
            {
                LogManager.Log("[PanelHost] FlashSnapshot.Capture failed: " + ex.Message);
                return ComposePlaceholderBackdrop(anchor);
            }
            try
            {
                FlashSnapshot.FrameSampleStats sample =
                    FlashSnapshot.AnalyzeFrame(snap.FullSnapshot, snap.ContentRect);
                bool isBlack = sample.IsLikelyBlack;
                if (captureSettingsPreview)
                {
                    LogManager.Log(
                        "[PanelHost] settings entry preview sample: accepted="
                        + (!isBlack)
                        + " mean=" + sample.AverageLuminance
                        + " range=" + sample.MinimumLuminance + "-" + sample.MaximumLuminance
                        + " variance=" + sample.Variance
                        + " highlights=" + sample.HighlightCount + "/" + sample.SampleCount);
                }
                if (captureSettingsPreview && !isBlack)
                {
                    try
                    {
                        settingsPreviewDataUrl = EncodePanelPreviewDataUri(
                            snap.FullSnapshot,
                            snap.ContentRect,
                            out settingsPreviewWidth,
                            out settingsPreviewHeight);
                        LogManager.Log(
                            "[PanelHost] settings entry preview encoded: size="
                            + settingsPreviewWidth + "x" + settingsPreviewHeight
                            + " chars=" + settingsPreviewDataUrl.Length);
                    }
                    catch (Exception ex)
                    {
                        // 快照预览是体验增强；失败不得阻断现役 backdrop/open 序列。
                        LogManager.Log("[PanelHost] settings entry preview encode failed: " + ex.Message);
                    }
                }
                byte dimAlpha = isBlack ? (byte)220 : (byte)160;
                return FlashSnapshot.ComposeBackdrop(snap.FullSnapshot, snap.ContentRect, dimAlpha);
            }
            finally
            {
                if (snap.FullSnapshot != null) snap.FullSnapshot.Dispose();
            }
        }

        internal static string EncodePanelPreviewDataUri(
            Bitmap fullSnapshot,
            Rectangle contentRect,
            out int previewWidth,
            out int previewHeight)
        {
            previewWidth = 0;
            previewHeight = 0;
            if (fullSnapshot == null) throw new ArgumentNullException("fullSnapshot");
            Rectangle bounds = new Rectangle(0, 0, fullSnapshot.Width, fullSnapshot.Height);
            Rectangle source = Rectangle.Intersect(contentRect, bounds);
            if (source.Width <= 0 || source.Height <= 0) source = bounds;
            if (!AreSettingsPreviewDimensionsValid(source.Width, source.Height))
                throw new InvalidOperationException(
                    "settings preview dimensions outside bounded 16:9 contract: "
                    + source.Width + "x" + source.Height);
            previewWidth = source.Width;
            previewHeight = source.Height;
            using (var preview = fullSnapshot.Clone(source, PixelFormat.Format24bppRgb))
            {
                using (var stream = new MemoryStream())
                {
                    ImageCodecInfo jpegCodec = null;
                    ImageCodecInfo[] encoders = ImageCodecInfo.GetImageEncoders();
                    for (int i = 0; i < encoders.Length; i++)
                    {
                        if (encoders[i].FormatID == ImageFormat.Jpeg.Guid)
                        {
                            jpegCodec = encoders[i];
                            break;
                        }
                    }
                    if (jpegCodec == null) throw new InvalidOperationException("JPEG encoder unavailable");
                    using (var parameters = new EncoderParameters(1))
                    {
                        parameters.Param[0] = new EncoderParameter(
                            System.Drawing.Imaging.Encoder.Quality,
                            90L);
                        preview.Save(stream, jpegCodec, parameters);
                    }
                    string dataUrl = "data:image/jpeg;base64," + Convert.ToBase64String(stream.ToArray());
                    if (dataUrl.Length > SettingsPreviewMaximumDataUriCharacters)
                        throw new InvalidOperationException(
                            "settings preview data URI exceeds bounded contract: " + dataUrl.Length);
                    return dataUrl;
                }
            }
        }

        internal static bool AreSettingsPreviewDimensionsValid(int width, int height)
        {
            if (width <= 0 || height <= 0
                || width > SettingsPreviewMaximumWidth
                || height > SettingsPreviewMaximumHeight)
                return false;
            long aspectError = Math.Abs((long)width * 9L - (long)height * 16L);
            return aspectError <= 16L;
        }

        internal static string AttachSettingsFlashPreview(
            string panelName,
            string initDataJson,
            string dataUrl,
            int width,
            int height)
        {
            if (!string.Equals(panelName, "settings", StringComparison.Ordinal)) return initDataJson;
            JObject initData;
            try
            {
                initData = string.IsNullOrEmpty(initDataJson)
                    ? new JObject()
                    : JObject.Parse(initDataJson);
            }
            catch (JsonException)
            {
                initData = new JObject();
            }
            // settings 的截图字段只允许 Host 生成；先移除任何调用方同名输入。
            initData.Remove("flashPreview");
            if (string.IsNullOrEmpty(dataUrl)
                || dataUrl.Length > SettingsPreviewMaximumDataUriCharacters
                || !AreSettingsPreviewDimensionsValid(width, height)
                || !dataUrl.StartsWith("data:image/jpeg;base64,", StringComparison.Ordinal))
                return initData.ToString(Formatting.None);
            initData["flashPreview"] = new JObject
            {
                ["v"] = 1,
                ["source"] = "entry_flash_snapshot",
                ["width"] = width,
                ["height"] = height,
                ["dataUrl"] = dataUrl
            };
            return initData.ToString(Formatting.None);
        }

        private void ClearActiveSettingsPreview()
        {
            _activeSettingsPreviewDataUrl = null;
            _activeSettingsPreviewWidth = 0;
            _activeSettingsPreviewHeight = 0;
        }

        private Bitmap ComposePlaceholderBackdrop(Rectangle anchor)
        {
            // 兜底：无 flashHwnd / snapshot 失败时用纯暗色（不黑透至游戏世界）
            Bitmap bmp = new Bitmap(Math.Max(1, anchor.Width), Math.Max(1, anchor.Height),
                System.Drawing.Imaging.PixelFormat.Format32bppArgb);
            using (Graphics g = Graphics.FromImage(bmp))
            using (SolidBrush b = new SolidBrush(Color.FromArgb(255, 8, 8, 12)))
            {
                g.FillRectangle(b, 0, 0, bmp.Width, bmp.Height);
            }
            return bmp;
        }

        private bool DoOpen(string name, string initDataJson)
        {
            return DoOpen(name, initDataJson, null, false, null);
        }

        private void SuspendHudCompanion()
        {
            if (_hudCompanion == null || _hudCompanionSuspended) return;
            try
            {
                _hudCompanion.Suspend();
                _hudCompanionSuspended = true;
            }
            catch (Exception ex)
            {
                LogManager.Log(
                    "[PanelHost] hud companion.Suspend failed: " +
                    ex.Message);
            }
        }

        private void ResumeHudCompanion()
        {
            if (_hudCompanion == null || !_hudCompanionSuspended) return;
            try
            {
                _hudCompanion.Resume();
                _hudCompanionSuspended = false;
            }
            catch (Exception ex)
            {
                LogManager.Log(
                    "[PanelHost] hud companion.Resume failed: " +
                    ex.Message);
            }
        }

        private bool DoOpen(string name, string initDataJson, string reservedPanelInstanceId,
            bool requireTrackedDelivery, Action trackedWebPostAccepted)
        {
            if (_testPumpDispatcher != null)
            {
                SuspendHudCompanion();
                string testInstance =
                    string.IsNullOrEmpty(
                        reservedPanelInstanceId)
                        ? NextPanelInstanceId()
                        : reservedPanelInstanceId;
                string testEnriched =
                    ApplyInitDataEnrichers(
                        name,
                        initDataJson,
                        testInstance);
                // 测试可观测 hook：记录与生产 DoOpen 同构的 open payload（enricher 链已应用），
                // 供单测断言 router/host 的 initData 造型，替代已拆除的 router fallback post。
                _lastOpenPayloadForTest =
                    BuildPanelOpenPayload(name, testEnriched, testInstance);
                _activePanel = name;
                _activePanelInstanceId =
                    testInstance;
                PublishPanelChanged(
                    name,
                    testInstance);
                if (requireTrackedDelivery
                    && trackedWebPostAccepted != null)
                {
                    trackedWebPostAccepted();
                }
                return true;
            }

            // local identity 必须先于 geometry，但不得建立 focus generation 或发布窗口事实。
            string instanceId = string.IsNullOrEmpty(reservedPanelInstanceId)
                ? NextPanelInstanceId()
                : reservedPanelInstanceId;
            ClearCommittedGeometry("open_attempt_begin");
            PanelGeometrySnapshot provisional;
            PanelGeometryMeasurement measurement;
            if (!TryCreateProvisionalGeometry(
                    name,
                    instanceId,
                    out provisional,
                    out measurement))
            {
                LogManager.Log("[PanelGeometry] open rejected before side effects"
                    + " panel=" + name
                    + " identity=" + instanceId
                    + " kind=" + measurement.Kind
                    + " source=" + measurement.Source
                    + " reason=" + measurement.Reason);
                return false;
            }

            bool pauseDelivered = false;
            try { pauseDelivered = _web.AssertWebPanelPause(); }
            catch (Exception ex)
            {
                LogManager.Log("[PanelHost] AssertWebPanelPause failed: " + ex.Message);
            }
            if (!pauseDelivered)
            {
                LogManager.Log("[PanelHost] open rejected after valid geometry: pause not delivered panel="
                    + name);
                return false;
            }

            long perfStart = System.Diagnostics.Stopwatch.GetTimestamp();
            PerfTrace.Mark("panel.open_start", name);
            try
            {
                Rectangle anchor = provisional.AnchorRect;
                Rectangle panelRect = provisional.PanelRect;

                // valid admission 后才能暂停独立 surface/HUD；这些调用不得早于 geometry。
                SuspendHudCompanion();
                _hud.Suspend();

                string settingsPreviewDataUrl;
                int settingsPreviewWidth;
                int settingsPreviewHeight;
                Bitmap composed = CaptureBackdrop(
                    anchor,
                    string.Equals(name, "settings", StringComparison.Ordinal),
                    out settingsPreviewDataUrl,
                    out settingsPreviewWidth,
                    out settingsPreviewHeight);
                if (string.Equals(name, "settings", StringComparison.Ordinal))
                {
                    _activeSettingsPreviewDataUrl = settingsPreviewDataUrl;
                    _activeSettingsPreviewWidth = settingsPreviewWidth;
                    _activeSettingsPreviewHeight = settingsPreviewHeight;
                }
                else
                {
                    ClearActiveSettingsPreview();
                }

                _backdrop.SetComposedAndShow(composed, anchor);
                _backdrop.SetPanelRect(panelRect);
                if (!_web.ResumeForPanel(panelRect))
                    throw new InvalidOperationException(
                        "WebOverlay rejected panel presentation");
                int focusGeneration = _web.PanelSessionGeneration;
                if (_shield != null)
                {
                    _shield.EnterTelemetryMode(
                        panelRect,
                        _ownerForm.Handle,
                        anchor,
                        _web.IsHandleCreated ? _web.Handle : IntPtr.Zero);
                }
                EnsurePanelZOrder();

                initDataJson = ApplyInitDataEnrichers(
                    name,
                    initDataJson,
                    instanceId);
                initDataJson = AttachSettingsFlashPreview(
                    name,
                    initDataJson,
                    _activeSettingsPreviewDataUrl,
                    _activeSettingsPreviewWidth,
                    _activeSettingsPreviewHeight);
                string payload = BuildPanelOpenPayload(
                    name,
                    initDataJson,
                    instanceId);
                bool delivered = false;
                try { delivered = _web.TryPostToWeb(payload); }
                catch (Exception ex)
                {
                    LogManager.Log("[PanelHost] TryPostToWeb open failed: "
                        + ex.Message);
                }
                if (!delivered)
                {
                    LogManager.Log("[PanelHost] open PostToWeb not delivered: " + name);
                    AbortOpenAttempt(pauseDelivered, "open_post_not_delivered");
                    return false;
                }

                ReTopOverlay(_hitNumber);
                ReTopOverlay(_cursor as Form);
                if (_escSource != null)
                    _escSource.SetPanelEscapeEnabled(true);
                SubscribeOwnerLayout();

                _activePanel = name;
                _activePanelInstanceId = instanceId;
                if (!CommitGeometry(provisional, focusGeneration))
                {
                    AbortOpenAttempt(pauseDelivered, "geometry_commit_rejected");
                    return false;
                }
                PublishPanelChanged(name, instanceId);
                if (requireTrackedDelivery && trackedWebPostAccepted != null)
                    trackedWebPostAccepted();

                LogManager.Log("[PanelHost] opened: " + name
                    + " rect=" + panelRect.Width + "x" + panelRect.Height);
                PerfTrace.Duration("panel.open", perfStart,
                    name + " rect=" + panelRect.Width + "x" + panelRect.Height);
                PerfTrace.FlushCounters("panel_open:" + name);
                if (DiagnosticsBootstrap.LayerAuditEnabled)
                    LayerAuditDump.DumpToLog("panel-open:" + name);
                return true;
            }
            catch (Exception ex)
            {
                AbortOpenAttempt(pauseDelivered, "open_exception");
                LogManager.Log("[PanelHost] open exception after geometry admission: "
                    + ex.Message);
                return false;
            }
        }

        private void AbortOpenAttempt(bool pauseDelivered, string reason)
        {
            ClearCommittedGeometry(reason);
            string abortClosePayload = BuildPanelClosePayload(
                _activePanel,
                _activePanelInstanceId);
            if (abortClosePayload != null)
            {
                try { _web.TryPostToWeb(abortClosePayload); }
                catch (Exception ex)
                {
                    LogManager.Log("[PanelHost] open abort exact close failed: "
                        + ex.Message);
                }
            }
            try { ResetToClosedState(); }
            catch (Exception ex)
            {
                LogManager.Log("[PanelHost] open abort reset failed: " + ex.Message);
            }
            if (!pauseDelivered) return;
            try
            {
                if (!_web.ReleaseWebPanelPauseAfterFailedOpen())
                {
                    LogManager.Log("[PanelHost] open abort pause release not delivered reason="
                        + reason);
                }
            }
            catch (Exception ex)
            {
                LogManager.Log("[PanelHost] open abort pause release failed: "
                    + ex.Message);
            }
        }

        /// <summary>同名 panel 的上下文切换不拆 backdrop/HUD，只换实例水位并让 Web 重建 session。</summary>
        private void DoRebind(string name, string initDataJson)
        {
            DoRebind(
                new PanelCommand(
                    PanelCommandKind.Open,
                    name,
                    initDataJson));
        }

        private void DoRebind(PanelCommand command)
        {
            string name = command.Name;
            string initDataJson = command.InitDataJson;
            string instanceId = NextPanelInstanceId();
            if (_testPumpDispatcher != null)
            {
                string rebindEnriched =
                    ApplyInitDataEnrichers(
                        name,
                        initDataJson,
                        instanceId);
                _lastOpenPayloadForTest =
                    BuildPanelOpenPayload(name, rebindEnriched, instanceId);
                _activePanelInstanceId =
                    instanceId;
                PublishPanelChanged(
                    name,
                    instanceId);
                ClearDeferredRebindAfterCommit(name);
                return;
            }
            PanelGeometrySnapshot provisional;
            PanelGeometryMeasurement measurement;
            if (!TryCreateProvisionalGeometry(
                    name,
                    instanceId,
                    out provisional,
                    out measurement))
            {
                lock (_queueLock) { _deferredRebind = command; }
                LogManager.Log("[PanelGeometry] rebind deferred"
                    + " kind=" + measurement.Kind
                    + " source=" + measurement.Source
                    + " reason=" + measurement.Reason);
                return;
            }
            initDataJson =
                ApplyInitDataEnrichers(
                    name,
                    initDataJson,
                    instanceId);
            initDataJson = AttachSettingsFlashPreview(
                name,
                initDataJson,
                _activeSettingsPreviewDataUrl,
                _activeSettingsPreviewWidth,
                _activeSettingsPreviewHeight);
            string payload = BuildPanelOpenPayload(name, initDataJson, instanceId);
            bool delivered = false;
            try { delivered = _web.TryPostToWeb(payload); }
            catch (Exception ex)
            {
                LogManager.Log(
                    "[PanelHost] TryPostToWeb rebind failed: "
                    + ex.Message);
            }
            if (!delivered)
            {
                lock (_queueLock)
                {
                    _deferredRebind = command;
                }
                LogManager.Log(
                    "[PanelHost] rebind post not delivered; deferred: "
                    + name);
                return;
            }
            _activePanelInstanceId = instanceId;
            int focusGeneration = _web.PanelSessionGeneration;
            RepositionBackdrop(provisional.AnchorRect, false);
            _backdrop.SetPanelRect(provisional.PanelRect);
            _web.RepositionForPanel(provisional.PanelRect, false);
            if (_shield != null)
            {
                _shield.EnterTelemetryMode(
                    provisional.PanelRect,
                    _ownerForm.Handle,
                    provisional.AnchorRect,
                    _web.IsHandleCreated ? _web.Handle : IntPtr.Zero);
            }
            if (!CommitGeometry(provisional, focusGeneration))
            {
                LogManager.Log("[PanelGeometry] rebind commit rejected: " + name);
                AbortOpenAttempt(true, "rebind_geometry_commit_rejected");
                return;
            }
            PublishPanelChanged(
                name,
                instanceId);
            ClearDeferredRebindAfterCommit(name);
            LogManager.Log("[PanelHost] rebound: " + name + " instance=" + instanceId);
        }

        private void ClearDeferredRebindAfterCommit(
            string panelName)
        {
            lock (_queueLock)
            {
                if (_deferredRebind.HasValue
                    && string.Equals(
                        _deferredRebind.Value.Name,
                        panelName,
                        StringComparison.Ordinal))
                {
                    _deferredRebind = null;
                }
            }
        }

        private string ApplyInitDataEnrichers(
            string panelName,
            string initDataJson,
            string panelInstanceId)
        {
            Func<string, string, string, string> securityEnricher =
                _securityInitDataEnricher;
            if (securityEnricher != null)
            {
                initDataJson =
                    securityEnricher(
                        panelName,
                        initDataJson,
                        panelInstanceId);
            }
            Func<string, string, string, string> enricher =
                _initDataEnricher;
            return enricher != null
                ? enricher(
                    panelName,
                    initDataJson,
                    panelInstanceId)
                : initDataJson;
        }

        private Control GetFlashPanelOrNull()
        {
            // _ownerForm 在生产环境总是 GuardianForm；做防御 cast 让单测注入纯 Form 不抛
            GuardianForm gf = _ownerForm as GuardianForm;
            return (gf != null) ? (Control)gf.FlashHostPanel : null;
        }

        private void SubscribeOwnerLayout()
        {
            if (_ownerLayoutSubscribed) return;
            try
            {
                _ownerForm.LocationChanged += OnOwnerLayoutChanged;
                _ownerForm.SizeChanged += OnOwnerLayoutSettleOnly;
                _ownerForm.ClientSizeChanged += OnOwnerLayoutSettleOnly;
                _ownerForm.VisibleChanged += OnOwnerVisibilityChanged;
                _ownerForm.HandleDestroyed += OnOwnerHandleDestroyed;
                _ownerForm.HandleCreated += OnOwnerHandleCreated;
                // FlashHostPanel.SizeChanged：viewport 变化的真实源头（全屏切换时 owner SizeChanged
                // 早于 ResizeFlashToPanel，订阅 owner.SizeChanged 会拿到旧 viewport；订阅 panel
                // 自身 SizeChanged 才能等到 layout settle 后的正确 size）
                Control fp = GetFlashPanelOrNull();
                if (fp != null) fp.SizeChanged += OnOwnerLayoutChanged;
                _ownerLayoutSubscribed = true;
            }
            catch (Exception ex) { LogManager.Log("[PanelHost] subscribe owner layout failed: " + ex.Message); }
        }

        private void UnsubscribeOwnerLayout()
        {
            if (!_ownerLayoutSubscribed) return;
            try
            {
                _ownerForm.LocationChanged -= OnOwnerLayoutChanged;
                _ownerForm.SizeChanged -= OnOwnerLayoutSettleOnly;
                _ownerForm.ClientSizeChanged -= OnOwnerLayoutSettleOnly;
                _ownerForm.VisibleChanged -= OnOwnerVisibilityChanged;
                _ownerForm.HandleDestroyed -= OnOwnerHandleDestroyed;
                _ownerForm.HandleCreated -= OnOwnerHandleCreated;
                Control fp = GetFlashPanelOrNull();
                if (fp != null) fp.SizeChanged -= OnOwnerLayoutChanged;
            }
            catch { }
            _ownerLayoutSubscribed = false;
            _ownerLayoutPending = false;
            _lastOwnerAnchorRect = Rectangle.Empty;
            _lastOwnerPanelRect = Rectangle.Empty;
            ClearCommittedGeometry("owner_layout_unsubscribe");
            if (_ownerLayoutSettleTimer != null)
            {
                try { _ownerLayoutSettleTimer.Stop(); } catch { }
            }
        }

        private void OnOwnerLayoutChanged(object sender, EventArgs e)
        {
            if (_disposed) return;
            if (_activePanel == null) return;
            ObserveOwnerPresentationWithdrawal("layout_changed");
            ScheduleOwnerLayoutSettle();
            // 节流：拖窗 LocationChanged 高频触发；BeginInvoke 合并到下一个消息泵循环只跑一次
            if (_ownerLayoutPending) return;
            _ownerLayoutPending = true;
            try
            {
                _ownerForm.BeginInvoke(new Action(ApplyOwnerLayoutChange));
            }
            catch (Exception ex)
            {
                _ownerLayoutPending = false;
                LogManager.Log("[PanelHost] owner layout BeginInvoke failed: " + ex.Message);
            }
        }

        private void OnOwnerLayoutSettleOnly(object sender, EventArgs e)
        {
            if (_disposed) return;
            if (_activePanel == null) return;
            ObserveOwnerPresentationWithdrawal("layout_settle");
            ScheduleOwnerLayoutSettle();
        }

        private void OnOwnerVisibilityChanged(object sender, EventArgs e)
        {
            if (_disposed || _activePanel == null) return;
            if (!_ownerForm.Visible)
            {
                MarkRestoreRevalidation("owner_hidden");
                return;
            }
            OnOwnerLayoutChanged(sender, e);
        }

        private void OnOwnerHandleDestroyed(object sender, EventArgs e)
        {
            _ownerHandleGeneration++;
            ClearCommittedGeometry("owner_handle_destroyed");
        }

        private void OnOwnerHandleCreated(object sender, EventArgs e)
        {
            _ownerHandleGeneration++;
            ClearCommittedGeometry("owner_handle_created");
            if (_disposed || _activePanel == null) return;
            OnOwnerLayoutChanged(sender, e);
        }

        private void ObserveOwnerPresentationWithdrawal(string reason)
        {
            if (_ownerForm.WindowState == FormWindowState.Minimized)
            {
                MarkRestoreRevalidation(reason + ":minimized");
                return;
            }
            if (!_ownerForm.Visible)
                MarkRestoreRevalidation(reason + ":hidden");
        }

        private bool HasCurrentCommittedGeometry(int focusGeneration)
        {
            PanelGeometrySnapshot committed = _committedGeometry;
            return committed != null
                && focusGeneration > 0
                && committed.FocusGeneration == focusGeneration
                && committed.OwnerHandleGeneration == _ownerHandleGeneration
                && _ownerForm.IsHandleCreated
                && committed.OwnerHwnd == _ownerForm.Handle
                && string.Equals(committed.PanelName, _activePanel,
                    StringComparison.Ordinal)
                && string.Equals(committed.PanelInstanceId,
                    _activePanelInstanceId, StringComparison.Ordinal);
        }

        private void MarkRestoreRevalidation(string reason)
        {
            int focusGeneration = _web.PanelSessionGeneration;
            if (_restoreRevalidation.Mark(
                    focusGeneration,
                    HasCurrentCommittedGeometry(focusGeneration)))
            {
                LogManager.Log("[PanelGeometry] restore revalidation marked"
                    + " generation=" + focusGeneration
                    + " reason=" + reason);
            }
        }

        private void ScheduleOwnerLayoutSettle()
        {
            if (_disposed) return;
            if (_ownerLayoutSettleTimer == null)
            {
                _ownerLayoutSettleTimer = new System.Windows.Forms.Timer();
                _ownerLayoutSettleTimer.Interval = 120;
                _ownerLayoutSettleTimer.Tick += delegate
                {
                    if (_ownerLayoutSettleTimer != null)
                        _ownerLayoutSettleTimer.Stop();
                    if (_disposed) return;
                    if (_activePanel == null) return;
                    ApplyOwnerLayoutChange();
                };
            }

            _ownerLayoutSettleTimer.Stop();
            _ownerLayoutSettleTimer.Start();
        }

        private void ApplyOwnerLayoutChange()
        {
            _ownerLayoutPending = false;
            if (_disposed) return;
            if (_activePanel == null) return;
            try
            {
                PanelGeometrySnapshot candidate;
                PanelGeometryMeasurement measurement;
                if (!TryCreateProvisionalGeometry(
                        _activePanel,
                        _activePanelInstanceId,
                        out candidate,
                        out measurement))
                {
                    if (measurement.Kind
                        == PanelGeometryMeasurementKind.ExplicitInvalid)
                        MarkRestoreRevalidation("layout_explicit_invalid:"
                            + measurement.Source + ":" + measurement.Reason);
                    LogManager.Log("[PanelGeometry] layout rejected"
                        + " kind=" + measurement.Kind
                        + " source=" + measurement.Source
                        + " reason=" + measurement.Reason);
                    return;
                }

                int focusGeneration = _web.PanelSessionGeneration;
                candidate.FocusGeneration = focusGeneration;
                PanelGeometrySnapshot committed = _committedGeometry;
                bool sameLifetime = HasCurrentCommittedGeometry(focusGeneration);
                bool sameOwnerAndDisplay = sameLifetime
                    && committed.HasSameOwnerAndDisplay(candidate);
                bool sameGeometry = sameOwnerAndDisplay
                    && committed.HasSameGeometry(candidate);
                PanelRestoreRevalidationDisposition restoreDisposition =
                    _restoreRevalidation.Consume(
                        focusGeneration,
                        sameGeometry);

                if (sameGeometry)
                {
                    if (restoreDisposition
                        == PanelRestoreRevalidationDisposition.ReplayCommitted)
                    {
                        ReplayCommittedPanelGroup(
                            committed,
                            "owner_restore_same_rect");
                    }
                    return;
                }

                bool ensureVisible = restoreDisposition
                        == PanelRestoreRevalidationDisposition.GeometryChanged
                    || !sameLifetime
                    || !sameOwnerAndDisplay;
                Rectangle newAnchor = candidate.AnchorRect;
                Rectangle newPanelRect = candidate.PanelRect;
                bool panelSizeChanged = committed == null
                    || committed.PanelRect.Width != newPanelRect.Width
                    || committed.PanelRect.Height != newPanelRect.Height;

                RepositionBackdrop(newAnchor, ensureVisible);
                _backdrop.SetPanelRect(newPanelRect);
                _web.RepositionForPanel(newPanelRect, ensureVisible);

                // PostToWeb 让 CSS var(--panel-w/-h) 自适应（仅在尺寸真变化时；拖窗只动位置时跳过）
                if (panelSizeChanged)
                {
                    try
                    {
                        _web.PostToWeb("{\"type\":\"panel_viewport_set\",\"w\":"
                            + newPanelRect.Width + ",\"h\":" + newPanelRect.Height + "}");
                    }
                    catch { }
                }

                if (_shield != null)
                {
                    try { _shield.EnterTelemetryMode(newPanelRect, _ownerForm.Handle, newAnchor,
                        _web.IsHandleCreated ? _web.Handle : IntPtr.Zero); }
                    catch (Exception ex) { LogManager.Log("[PanelHost] shield reposition failed: " + ex.Message); }
                }
                if (ensureVisible) EnsurePanelZOrder();
                if (!CommitGeometry(candidate, focusGeneration))
                {
                    ClearCommittedGeometry("layout_commit_rejected");
                    LogManager.Log("[PanelGeometry] layout commit rejected");
                }
                // ★ 拖动期间不 ReTopOverlay：backdrop/web 用 SWP_NOZORDER 不破坏 z-order，
                //   主动 ReTop 反而触发 z-order 重排导致闪烁 + 抢焦点
            }
            catch (Exception ex)
            {
                LogManager.Log("[PanelHost] ApplyOwnerLayoutChange failed: " + ex.Message);
            }
        }

        private void DoClose()
        {
            if (_testPumpDispatcher != null)
            {
                Action testBeforeClose = _testBeforeDoClose;
                _testBeforeDoClose = null;
                if (testBeforeClose != null) testBeforeClose();
                string testClosingName =
                    _activePanel;
                string testClosingInstance =
                    _activePanelInstanceId;
                Action<string, string> testObserver =
                    _panelCloseObserver;
                if (testObserver != null)
                {
                    try
                    {
                        testObserver(
                            testClosingName,
                            testClosingInstance);
                    }
                    catch { }
                }
                ResumeHudCompanion();
                ClearActiveSettingsPreview();
                _activePanel = null;
                _activePanelInstanceId = null;
                PublishPanelChanged(
                    null,
                    null);
                PostPanelClosed(
                    testClosingName,
                    testClosingInstance);
                return;
            }

            long perfStart = System.Diagnostics.Stopwatch.GetTimestamp();
            string closingName = _activePanel;
            string closingInstance = _activePanelInstanceId;
            PerfTrace.Mark("panel.close_start", closingName ?? "<null>");
            Action<string, string> closeObserver = _panelCloseObserver;
            if (closeObserver != null)
            {
                try { closeObserver(closingName, closingInstance); }
                catch (Exception ex) { LogManager.Log("[PanelHost] close observer failed: " + ex.Message); }
            }
            // Step 0: 取消 owner 跟随订阅（先于 SuspendAfterPanel，防止 SW_HIDE 触发的 LocationChanged 误触发 reposition）
            ClearCommittedGeometry("panel_close");
            UnsubscribeOwnerLayout();
            // Step 1: 先让 Web 精确卸载当前 owner，再隐藏 WebOverlay。
            // crafting 等 Host-owned panel 的 requestClose 只提交 intent，不会自行 Panels.close；
            // 若直接 SW_HIDE，最后一次全屏 interactiveRect 会留在 InputShield 中。
            string closePayload = BuildPanelClosePayload(
                closingName,
                closingInstance);
            if (closePayload != null)
            {
                try
                {
                    if (!_web.TryPostToWeb(closePayload))
                    {
                        LogManager.Log(
                            "[PanelHost] exact web close post not delivered: "
                            + closingName);
                    }
                }
                catch (Exception ex)
                {
                    LogManager.Log(
                        "[PanelHost] exact web close post failed: "
                        + ex.Message);
                }
            }
            // Step 2: WebOverlay 收尾（Phase 1 stub：SW_HIDE）
            // closingName 传给 SuspendAfterPanel 用于 [FocusRestore] 日志归因——
            // WebOverlay._activePanel 此时可能已被 HandlePanelMessage 置 null。
            try { _web.SuspendAfterPanel(closingName); }
            catch (Exception ex) { LogManager.Log("[PanelHost] SuspendAfterPanel failed: " + ex.Message); }
            // Step 3: Shield 退 telemetry
            if (_shield != null)
            {
                try { _shield.ExitTelemetryMode(); }
                catch (Exception ex) { LogManager.Log("[PanelHost] ExitTelemetryMode failed: " + ex.Message); }
            }
            // Step 4: backdrop 隐藏
            try { _backdrop.Hide(); }
            catch (Exception ex) { LogManager.Log("[PanelHost] backdrop.Hide failed: " + ex.Message); }
            // Step 5: HUD 复活（NativeHud 复显）
            try { _hud.Resume(); }
            catch (Exception ex) { LogManager.Log("[PanelHost] hud.Resume failed: " + ex.Message); }
            ResumeHudCompanion();
            // Step 6: ESC 禁用
            if (_escSource != null) _escSource.SetPanelEscapeEnabled(false);
            // Step 7: cursor 重新顶置 + 强制刷一次位置（HUD 复显的 HWND_TOP 会把 cursor 压下；
            //   且 cursor 上次坐标可能在 panel 矩形内，关闭后该区域无 mouse hook 触发更新——直到玩家动鼠标
            //   才刷新 → 视觉上 cursor "消失，移动后突然出现"。这里主动 ReTop + 用当前真实鼠标位置刷一次）
            ReTopOverlay(_cursor as Form);
            try { _web.UpdateCursorFromScreenPoint(System.Windows.Forms.Cursor.Position); }
            catch (Exception ex) { LogManager.Log("[PanelHost] cursor refresh failed: " + ex.Message); }

            _activePanel = null;
            _activePanelInstanceId = null;
            ClearActiveSettingsPreview();
            PublishPanelChanged(
                null,
                null);
            PostPanelClosed(closingName, closingInstance);
            // SuspendAfterPanel 中的首次归还早于 HUD/cursor 收尾。
            // 在所有 overlay 稳定后再确认一次 Flash 焦点，避免玩家看到
            // 面板已关闭却无法与游戏 UI 交互。
            try { _web.RestoreFlashInputFocusAfterPanelClose(closingName); }
            catch (Exception ex) { LogManager.Log("[PanelHost] settled focus restore failed: " + ex.Message); }
            LogManager.Log("[PanelHost] closed: " + (closingName ?? "<null>"));
            PerfTrace.Duration("panel.close", perfStart, closingName ?? "<null>");
            PerfTrace.FlushCounters("panel_close:" + (closingName ?? "<null>"));
            // B0 诊断: panel-close 后立即 dump, 对照 panel-open 看 layered_visible 是否真的回落
            if (DiagnosticsBootstrap.LayerAuditEnabled)
                LayerAuditDump.DumpToLog("panel-close:" + (closingName ?? "<null>"));
        }

        public void Dispose()
        {
            if (_disposed) return;
            _disposed = true;
            ClearActiveSettingsPreview();
            try
            {
                if (_ownerForm != null)
                    _ownerForm.HandleCreated -=
                        DelayedKickOnHandleCreated;
            }
            catch { }
            List<VisualRetireWaiter> failedRetires;
            List<PanelCommand> failedReplaces =
                new List<PanelCommand>();
            lock (_queueLock)
            {
                failedRetires =
                    new List<VisualRetireWaiter>(
                        _visualRetireWaiters);
                foreach (PanelCommand queued in _queue)
                {
                    if (queued.IsExactReplace)
                        failedReplaces.Add(queued);
                    if (queued.IsVisualRetire
                        && queued.VisualRetireCompleted
                            != null)
                    {
                        failedRetires.Add(
                            new VisualRetireWaiter
                            {
                                Completed =
                                    queued.VisualRetireCompleted
                            });
                    }
                }
                _queue.Clear();
                _processing = false;
                _returnStack.Clear();
                _deferredRebind = null;
                _deferredBarrierOpen = null;
                _trackedOpenReserved = false;
                _exactReplaceReserved = false;
                _trackedLeasePanelName = null;
                _trackedLeaseInstanceId = null;
                _idleFenceToken = null;
                _visualRetireWaiters.Clear();
            }
            foreach (PanelCommand failedReplace in failedReplaces)
            {
                if (failedReplace.PreparedReplace != null)
                    failedReplace.PreparedReplace.AbortPrepared();
                if (failedReplace.ExactReplaceCompleted != null)
                {
                    try
                    {
                        failedReplace.ExactReplaceCompleted(
                            ExactReplaceOutcome.HostUnavailable);
                    }
                    catch { }
                }
            }
            foreach (VisualRetireWaiter waiter in failedRetires)
            {
                if (waiter.Completed == null) continue;
                try
                {
                    waiter.Completed(
                        VisualRetireOutcome.HostUnavailable);
                }
                catch { }
            }
            try { UnsubscribeOwnerLayout(); } catch { }
            if (_ownerLayoutSettleTimer != null)
            {
                try { _ownerLayoutSettleTimer.Stop(); } catch { }
                try { _ownerLayoutSettleTimer.Dispose(); } catch { }
                _ownerLayoutSettleTimer = null;
            }
            try
            {
                if (_backdrop != null)
                    _backdrop.BackdropClickedOutsidePanel -=
                        OnBackdropClickOutsidePanel;
            }
            catch { }
        }

        private void PostPanelClosed(string panelName, string panelInstanceId)
        {
            Action<string, string> closed = PanelClosed;
            if (closed == null) return;
            Action fire = delegate
            {
                try { closed(panelName, panelInstanceId); }
                catch (Exception ex) { LogManager.Log("[PanelHost] closed event failed: " + ex.Message); }
            };
            try
            {
                if (_testClosedEventDispatcher != null)
                {
                    _testClosedEventDispatcher(fire);
                    return;
                }
                if (_ownerForm.IsHandleCreated) _ownerForm.BeginInvoke(fire);
                else fire();
            }
            catch (Exception ex)
            {
                LogManager.Log("[PanelHost] closed event dispatch failed: " + ex.Message);
            }
        }

        private void PublishPanelChanged(
            string panelName,
            string panelInstanceId)
        {
            Action<string, string> changed =
                PanelChanged;
            if (changed == null) return;
            foreach (Action<string, string> subscriber
                in changed.GetInvocationList())
            {
                try
                {
                    subscriber(
                        panelName,
                        panelInstanceId);
                }
                catch (Exception ex)
                {
                    LogManager.Log(
                        "[PanelHost] changed event failed: "
                        + ex.Message);
                }
            }
        }

        private void ReTopOverlay(Form f)
        {
            if (f == null) return;
            try
            {
                if (!f.IsHandleCreated || !f.Visible) return;
                SetWindowPos(f.Handle, HWND_TOP, 0, 0, 0, 0,
                    SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
            }
            catch { }
        }

        private void RepositionBackdrop(
            Rectangle anchorRect,
            bool ensureVisible)
        {
            if (!ensureVisible)
            {
                _backdrop.RepositionTo(anchorRect);
                return;
            }
            SetWindowPos(
                _backdrop.Handle,
                IntPtr.Zero,
                anchorRect.X,
                anchorRect.Y,
                anchorRect.Width,
                anchorRect.Height,
                SWP_NOACTIVATE | SWP_SHOWWINDOW);
            _backdrop.Invalidate();
        }

        private bool ReplayCommittedPanelGroup(
            PanelGeometrySnapshot committed,
            string reason)
        {
            if (committed == null
                || !HasCurrentCommittedGeometry(committed.FocusGeneration)
                || !ReferenceEquals(committed, _committedGeometry))
                return false;
            try
            {
                RepositionBackdrop(committed.AnchorRect, true);
                _backdrop.SetPanelRect(committed.PanelRect);
                bool webReplayed = _web.ReplayCommittedPanelPresentation(
                    committed.PanelRect,
                    committed.FocusGeneration,
                    reason);
                if (_shield != null)
                {
                    _shield.EnterTelemetryMode(
                        committed.PanelRect,
                        _ownerForm.Handle,
                        committed.AnchorRect,
                        _web.IsHandleCreated ? _web.Handle : IntPtr.Zero);
                }
                EnsurePanelZOrder();
                LogManager.Log("[PanelGeometry] panel-group replay"
                    + " generation=" + committed.FocusGeneration
                    + " reason=" + reason
                    + " web=" + webReplayed);
                return webReplayed;
            }
            catch (Exception ex)
            {
                LogManager.Log("[PanelGeometry] panel-group replay failed: "
                    + ex.Message);
                return false;
            }
        }

        private void EnsurePanelZOrder()
        {
            try
            {
                if (_backdrop == null || _web == null) return;
                if (!_backdrop.IsHandleCreated || !_web.IsHandleCreated) return;
                SetWindowPos(_backdrop.Handle, _web.Handle, 0, 0, 0, 0,
                    SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
                SetWindowPos(_web.Handle, HWND_TOP, 0, 0, 0, 0,
                    SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
                LogManager.Log("[PanelHost] z-order applied: backdrop below web");
            }
            catch (Exception ex)
            {
                LogManager.Log("[PanelHost] z-order apply failed: " + ex.Message);
            }
        }

        #endregion

        #region ResetToClosedState

        /// <summary>
        /// 异常恢复 primitive：把整个系统强制拨回 idle 不变量。
        /// 必须涵盖 SuspendAfterPanel 内每一步 + backdrop/hud/shield close 序列。
        /// 关键：调用 _web.ForceIdleState()（不查 _panelMode），不是 SuspendAfterPanel。
        /// 即便部分窗口已 dispose 也尽量推进；catch 后继续。
        /// </summary>
        private void ResetToClosedState()
        {
            ClearCommittedGeometry("reset_to_closed");
            UnsubscribeOwnerLayout();
            Action<string, string> closeObserver = _panelCloseObserver;
            if (closeObserver != null && _activePanel != null)
            {
                try { closeObserver(_activePanel, _activePanelInstanceId); }
                catch (Exception ex) { LogManager.Log("[PanelHost] reset close observer failed: " + ex.Message); }
            }
            // _activePanel 此时尚未置 null（line 613 才置），优先传它作为 closingPanelName；
            // ResetToClosedState 路径是异常恢复，reason 后缀 ":reset" 用于日志区分正常 close。
            string resetTag = (_activePanel != null) ? (_activePanel + ":reset") : "reset";
            try { _web.ForceIdleState(resetTag); }
            catch (Exception ex) { LogManager.Log("[PanelHost] Web ForceIdleState partial failure: " + ex.Message); }
            try { _backdrop.Hide(); } catch { }
            try { _hud.Resume(); } catch { }
            ResumeHudCompanion();
            if (_shield != null) { try { _shield.ExitTelemetryMode(); } catch { } }
            if (_escSource != null) { try { _escSource.SetPanelEscapeEnabled(false); } catch { } }
            string resetClosingName = _activePanel;
            string resetClosingInstance = _activePanelInstanceId;
            _activePanel = null;
            _activePanelInstanceId = null;
            ClearActiveSettingsPreview();
            _trackedLeasePanelName = null;
            _trackedLeaseInstanceId = null;
            if (resetClosingName != null
                || resetClosingInstance != null)
            {
                PublishPanelChanged(
                    null,
                    null);
            }
            Action<string, string> resetClosed = PanelClosed;
            if (resetClosed != null && resetClosingName != null)
            {
                try { resetClosed(resetClosingName, resetClosingInstance); }
                catch (Exception ex) { LogManager.Log("[PanelHost] reset closed event failed: " + ex.Message); }
            }

            // 异常路径不应触发 returnTo reopen：清栈避免在已经混乱的状态上叠加新 panel 命令。
            _returnStack.Clear();
            _deferredBarrierOpen = null;

            _consecutiveFailures++;
            if (_consecutiveFailures >= FAILURE_CIRCUIT_BREAKER)
            {
                lock (_queueLock) { _queue.Clear(); }
                LogManager.Log("[PanelHost] CIRCUIT BREAKER triggered after " + _consecutiveFailures
                    + " consecutive failures; queue cleared.");
                _consecutiveFailures = 0;
            }
        }

        #endregion

        private static string EscapeJson(string s)
        {
            if (string.IsNullOrEmpty(s)) return "";
            return s.Replace("\\", "\\\\").Replace("\"", "\\\"");
        }

        internal static string BuildPanelOpenPayload(string name, string initDataJson, string panelInstanceId)
        {
            JObject initData;
            try { initData = string.IsNullOrEmpty(initDataJson) ? new JObject() : JObject.Parse(initDataJson); }
            catch (JsonException) { initData = new JObject(); }
            initData["panelInstanceId"] = panelInstanceId;
            JObject payload = new JObject
            {
                ["type"] = "panel_cmd",
                ["cmd"] = "open",
                ["panel"] = name,
                ["panelInstanceId"] = panelInstanceId,
                ["initData"] = initData
            };
            return payload.ToString(Formatting.None);
        }

        internal static string BuildPanelClosePayload(
            string name,
            string panelInstanceId)
        {
            if (string.IsNullOrEmpty(name)
                || string.IsNullOrEmpty(panelInstanceId)) return null;
            return new JObject
            {
                ["type"] = "panel_cmd",
                ["cmd"] = "close",
                ["panel"] = name,
                ["panelInstanceId"] = panelInstanceId
            }.ToString(Formatting.None);
        }

        private static string NextPanelInstanceId()
        {
            return OpaqueIdGenerator.Create("panel");
        }
    }
}
