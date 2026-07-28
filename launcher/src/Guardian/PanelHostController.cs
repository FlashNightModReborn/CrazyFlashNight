using System;
using System.Collections.Generic;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using CF7Launcher.Diagnostic;
using CF7Launcher.Guardian.Hud;

namespace CF7Launcher.Guardian
{
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
        #region Win32

        [DllImport("user32.dll")]
        private static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter,
            int X, int Y, int cx, int cy, uint uFlags);

        private static readonly IntPtr HWND_TOP = new IntPtr(0);
        private const uint SWP_NOMOVE = 0x0002;
        private const uint SWP_NOSIZE = 0x0001;
        private const uint SWP_NOACTIVATE = 0x0010;

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
            public string ReservedPanelInstanceId;
            public Func<bool> TrackedExecutionGate;
            public Action<TrackedOpenOutcome> TrackedOpenCompleted;
            public Action<bool> TrackedCloseCompleted;
            public Action<bool> ExactCloseCompleted;
            public Action<VisualRetireOutcome> VisualRetireCompleted;
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
                ReservedPanelInstanceId = null;
                TrackedExecutionGate = null;
                TrackedOpenCompleted = null;
                TrackedCloseCompleted = null;
                ExactCloseCompleted = null;
                VisualRetireCompleted = null;
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
        // Phase 3: NotchOverlay/ToastOverlay 作为常驻 HUD（web 端 #notch/#toast 已被 CSS 隐藏）
        // panel 打开时 Suspend 让 backdrop 干净遮住；panel 关闭时 SetReady 恢复
        private readonly NotchOverlay _notchOverlay;
        private readonly ToastOverlay _toastOverlay;

        private readonly Queue<PanelCommand> _queue = new Queue<PanelCommand>();
        private readonly List<VisualRetireWaiter> _visualRetireWaiters =
            new List<VisualRetireWaiter>();
        private readonly object _queueLock = new object();
        private long _openAdmissionEpoch;
        private Func<string, bool> _openGate;
        private Func<string, bool> _rebindGate;
        private Func<string, string, string, string> _initDataEnricher;
        private Action<string, string> _panelCloseObserver;
        public event Action<string, string> PanelClosed;
        private PanelCommand? _deferredRebind;
        private PanelCommand? _deferredBarrierOpen;
        private bool _processing;
        private bool _delayedKickRegistered;

        private volatile string _activePanel; // null = closed
        private volatile string _activePanelInstanceId;
        private bool _trackedOpenReserved;
        private volatile string _trackedLeasePanelName;
        private volatile string _trackedLeaseInstanceId;
        private string _idleFenceToken;
        private readonly Action<Action> _testPumpDispatcher;
        private readonly Action<Action> _testClosedEventDispatcher;
        private static long _panelInstanceSequence;
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
            Func<IntPtr> flashHwndProvider,
            NotchOverlay notchOverlay,
            ToastOverlay toastOverlay)
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
            _notchOverlay = notchOverlay; // 可空（Phase 3 引入）
            _toastOverlay = toastOverlay; // 可空（Phase 3 引入）

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
        {
            if (pumpDispatcher == null)
                throw new ArgumentNullException("pumpDispatcher");
            _testPumpDispatcher = pumpDispatcher;
            _testClosedEventDispatcher =
                closedEventDispatcher ?? delegate(Action fire) { fire(); };
        }

        private void OnBackdropClickOutsidePanel()
        {
            if (_disposed) return;
            // panels.js 的 panel_esc 等价于按 ESC：触发各 panel 的 onRequestClose
            // 不发 cmd:"request_close" —— panels.js 的 panel_cmd 仅 handle open/close/force_close
            try { _web.PostToWeb("{\"type\":\"panel_esc\"}"); }
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
            if (_disposed || string.IsNullOrEmpty(panelName)
                || string.IsNullOrEmpty(panelInstanceId)) return false;
            lock (_queueLock)
            {
                _deferredRebind = null;
                _deferredBarrierOpen = null;
            }
            PanelCommand command =
                new PanelCommand(PanelCommandKind.Close, panelName, null);
            command.IsExactClose = true;
            command.ReservedPanelInstanceId = panelInstanceId;
            command.ExactCloseCompleted = completed;
            return EnqueueAndPump(command);
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
                    _activePanel == null
                    && _queue.Count == 0
                    && !_processing
                    && !_trackedOpenReserved;
                if (_idleFenceToken != null
                    && !confirmedVisualIdle)
                {
                    return false;
                }
                if (confirmedVisualIdle
                    && string.Equals(
                        _trackedLeasePanelName,
                        panelName,
                        StringComparison.Ordinal)
                    && string.Equals(
                        _trackedLeaseInstanceId,
                        panelInstanceId,
                        StringComparison.Ordinal))
                {
                    _trackedLeasePanelName = null;
                    _trackedLeaseInstanceId = null;
                }
                _deferredRebind = null;
                _deferredBarrierOpen = null;
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
                    return !_disposed && _activePanel == null && _queue.Count == 0
                        && !_processing && !_trackedOpenReserved && _trackedLeaseInstanceId == null
                        && _idleFenceToken == null;
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
                if (_disposed || _idleFenceToken != null || _activePanel != null
                    || _queue.Count != 0 || _processing || _trackedOpenReserved
                    || _trackedLeaseInstanceId != null) return false;
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
            if (deferred.HasValue) EnqueueAndPump(deferred.Value);
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
            if (deferred.HasValue)
                EnqueueAndPump(deferred.Value);
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
                && _trackedLeaseInstanceId == null
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
                if (cmd.IsTrackedOpen)
                {
                    if (_trackedOpenReserved || _trackedLeaseInstanceId != null
                        || _activePanel != null || _queue.Count != 0 || _processing)
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
                else if (!cmd.IsVisualRetire
                    && (_trackedOpenReserved
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
            }
            for (int i = 0; i < failed.Count; i++)
            {
                PanelCommand command = failed[i];
                if (skipFirstCallback && i == 0
                    && !command.IsVisualRetire) continue;
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
                lock (_queueLock)
                {
                    _queue.Clear();
                    _processing = false;
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
                    DoRebind(cmd.Name, cmd.InitDataJson);
                    _consecutiveFailures = 0;
                    return;
                }
                if (_activePanel != null) DoClose();
                // 调用方显式带了 returnTo → push 进栈，关闭本 panel 时 pop 出来自动 reopen。
                // B 时代会改成：无 returnTo 参数时，open 自动 push 前一个 _activePanel。
                if (!string.IsNullOrEmpty(cmd.ReturnToName))
                {
                    _returnStack.Add(new ReturnStackEntry(cmd.ReturnToName, cmd.ReturnInitDataJson));
                }
                DoOpen(cmd.Name, cmd.InitDataJson);
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
                DoClose();
                closed = true;
                if (_returnStack.Count > 0)
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
                    _returnStack.Clear();
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
                else if (_activePanel != null)
                {
                    LogManager.Log(
                        "[PanelHost] visual retire waiting for replacement: "
                        + (_activePanel ?? "<null>") + " instance="
                        + (_activePanelInstanceId ?? "<null>")
                        + " requested=" + (cmd.Name ?? "<null>")
                        + " instance="
                        + (cmd.ReservedPanelInstanceId ?? "<null>"));
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
                if (_visualRetireWaiters.Count != 0)
                    return true;
                foreach (PanelCommand queued in _queue)
                    if (queued.IsVisualRetire)
                        return true;
                return false;
            }
        }

        private void CompleteVisualRetireWaitersIfIdle()
        {
            List<VisualRetireWaiter> completed = null;
            lock (_queueLock)
            {
                if (_activePanel != null
                    || _queue.Count != 0
                    || _processing
                    || _trackedOpenReserved)
                {
                    return;
                }
                if (_visualRetireWaiters.Count == 0)
                    return;
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
                        waiter.RetiredExact
                            ? VisualRetireOutcome.RetiredExact
                            : VisualRetireOutcome.VisualAlreadyAbsent);
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
        /// anchor 屏幕矩形 = mapper.CalcViewport 实时算的 Flash 可见区（扣除 letterbox）。
        /// **不能用 _web.Bounds**：DoFullIdleSuspend 只 SW_HIDE 不复位窗口位置/大小，
        /// 下一次 DoOpen 取到的会是上一次的 panelRect，导致新 panel 嵌在过时小矩形里。
        /// 退路：GetCurrentAnchorScreenRect 失败 → FlashHostPanel 屏幕矩形 → owner client。
        /// </summary>
        private Rectangle ComputeAnchorScreenRect()
        {
            try
            {
                Rectangle vp = _web.GetCurrentAnchorScreenRect();
                if (vp.Width > 0 && vp.Height > 0) return vp;
            }
            catch { }
            try
            {
                Control fp = GetFlashPanelOrNull();
                if (fp != null && fp.Width > 0 && fp.Height > 0)
                {
                    Point origin = fp.PointToScreen(Point.Empty);
                    return new Rectangle(origin.X, origin.Y, fp.Width, fp.Height);
                }
            }
            catch { }
            try
            {
                Point origin = _ownerForm.PointToScreen(Point.Empty);
                return new Rectangle(origin.X, origin.Y, _ownerForm.ClientSize.Width, _ownerForm.ClientSize.Height);
            }
            catch
            {
                return new Rectangle(0, 0, 1024, 576);
            }
        }

        /// <summary>
        /// FlashSnapshot.Capture + ComposeBackdrop。失败/无 flashHwnd 时降级纯暗 dim 占位。
        /// 黑帧检测命中 → 提高 dim 强度兜底，避免玩家看到全黑无对比。
        /// </summary>
        private Bitmap CaptureBackdrop(Rectangle anchor)
        {
            IntPtr flashHwnd = (_flashHwndProvider != null) ? _flashHwndProvider() : IntPtr.Zero;
            if (flashHwnd == IntPtr.Zero)
                return ComposePlaceholderBackdrop(anchor);
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
                bool isBlack = FlashSnapshot.IsLikelyBlackFrame(snap.FullSnapshot, snap.ContentRect);
                byte dimAlpha = isBlack ? (byte)220 : (byte)160;
                return FlashSnapshot.ComposeBackdrop(snap.FullSnapshot, snap.ContentRect, dimAlpha);
            }
            finally
            {
                if (snap.FullSnapshot != null) snap.FullSnapshot.Dispose();
            }
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

        private void DoOpen(string name, string initDataJson)
        {
            DoOpen(name, initDataJson, null, false, null);
        }

        private bool DoOpen(string name, string initDataJson, string reservedPanelInstanceId,
            bool requireTrackedDelivery, Action trackedWebPostAccepted)
        {
            if (_testPumpDispatcher != null)
            {
                string testInstance =
                    string.IsNullOrEmpty(
                        reservedPanelInstanceId)
                        ? NextPanelInstanceId()
                        : reservedPanelInstanceId;
                _activePanel = name;
                _activePanelInstanceId =
                    testInstance;
                if (requireTrackedDelivery
                    && trackedWebPostAccepted != null)
                {
                    trackedWebPostAccepted();
                }
                return true;
            }

            // Loot tracked open promises that the game is already under the global webpanel lease
            // before any native/Web visual side effect.  A socket write failure is therefore a
            // known pre-open failure, never an OpenPosted outcome.
            if (requireTrackedDelivery)
            {
                bool pauseDelivered = false;
                try { pauseDelivered = _web.AssertWebPanelPause(); }
                catch (Exception ex)
                {
                    LogManager.Log("[PanelHost] tracked AssertWebPanelPause failed: " + ex.Message);
                }
                if (!pauseDelivered)
                {
                    LogManager.Log("[PanelHost] tracked open rejected before visual side effects: pause not delivered");
                    return false;
                }
            }
            long perfStart = System.Diagnostics.Stopwatch.GetTimestamp();
            PerfTrace.Mark("panel.open_start", name);
            Rectangle anchor = ComputeAnchorScreenRect();
            Rectangle panelRect = PanelLayoutCatalog.GetRect(name, anchor);

            // Step 1-2: snapshot + compose（带 dim + letterbox 黑边保留 + 黑帧兜底）
            Bitmap composed = CaptureBackdrop(anchor);
            // Step 3: backdrop show + 设 panel rect（屏幕坐标，backdrop 内自转 client）
            _backdrop.SetComposedAndShow(composed, anchor);
            _backdrop.SetPanelRect(panelRect);
            // Step 4: HUD 暂停（NativeHud 容器 + Phase 3 NotchOverlay/ToastOverlay 一并隐藏，让 backdrop 干净遮住）
            _hud.Suspend();
            if (_notchOverlay != null) try { _notchOverlay.Suspend(); } catch (Exception ex) { LogManager.Log("[PanelHost] notch.Suspend failed: " + ex.Message); }
            if (_toastOverlay != null) try { _toastOverlay.Suspend(); } catch (Exception ex) { LogManager.Log("[PanelHost] toast.Suspend failed: " + ex.Message); }
            // Step 5: WebOverlay 切 panel-rect（去 LAYERED+TRANSPARENT、opaque、SetWindowPos HWND_TOP+SWP_FRAMECHANGED、PostToWeb panel_viewport_set）
            _web.ResumeForPanel(panelRect);
            // Step 6: InputShield 进 telemetry（仅记录 panelRect 外 click，不拦截）
            if (_shield != null) _shield.EnterTelemetryMode(panelRect, _ownerForm.Handle, anchor,
                _web.IsHandleCreated ? _web.Handle : IntPtr.Zero);
            EnsurePanelZOrder();
            // Step 7: 通知 web 打开 panel（panel_viewport_set 已在 ResumeForPanel 内 PostToWeb）
            string instanceId = string.IsNullOrEmpty(reservedPanelInstanceId)
                ? NextPanelInstanceId() : reservedPanelInstanceId;
            Func<string, string, string, string> enricher = _initDataEnricher;
            if (enricher != null) initDataJson = enricher(name, initDataJson, instanceId);
            string payload = BuildPanelOpenPayload(name, initDataJson, instanceId);
            bool delivered = true;
            try
            {
                if (requireTrackedDelivery)
                    delivered = _web.TryPostToWeb(payload);
                else
                    _web.PostToWeb(payload);
            }
            catch (Exception ex)
            {
                delivered = false;
                LogManager.Log("[PanelHost] PostToWeb open failed: " + ex.Message);
            }
            if (requireTrackedDelivery && !delivered)
            {
                LogManager.Log("[PanelHost] tracked open PostToWeb not delivered: " + name);
                ResetToClosedState();
                return false;
            }
            if (requireTrackedDelivery && trackedWebPostAccepted != null)
                trackedWebPostAccepted();
            // Step 8: 把 HitNumber/Cursor 重新顶置（Backdrop/WebOverlay 的 SetWindowPos HWND_TOP 把它们压下去了）
            ReTopOverlay(_hitNumber);
            // INativeCursor 抽象后 cursor 实现仍是 Form（CursorOverlayForm / DesktopCursorOverlay 都是）。
            // ReTopOverlay 需要 Handle，所以走 as Form 投影；非 Form 实现（不存在）会被静默跳过。
            ReTopOverlay(_cursor as Form);
            // Step 9: ESC 拦截启用
            if (_escSource != null) _escSource.SetPanelEscapeEnabled(true);
            // Step 10: 跟随 owner 拖窗/大小变化，重定位 backdrop+web 到新 anchor
            SubscribeOwnerLayout();
            _lastOwnerAnchorRect = anchor;
            _lastOwnerPanelRect = panelRect;

            _activePanel = name;
            _activePanelInstanceId = instanceId;
            // 任意真实打开 → 暂停游戏。覆盖 returnTo 自动重开（ExecuteCommand 从 _returnStack
            // enqueue 的 Open 不经 LauncherCommandRouter.OpenPanel，否则重开面板背后游戏已恢复运行）。
            // AS2 webPanelPause 幂等，首次打开与 router 路径重复发也安全。
            if (!requireTrackedDelivery)
            {
                try { _web.AssertWebPanelPause(); }
                catch (Exception ex) { LogManager.Log("[PanelHost] AssertWebPanelPause failed: " + ex.Message); }
            }
            LogManager.Log("[PanelHost] opened: " + name + " rect=" + panelRect.Width + "x" + panelRect.Height);
            PerfTrace.Duration("panel.open", perfStart,
                name + " rect=" + panelRect.Width + "x" + panelRect.Height);
            PerfTrace.FlushCounters("panel_open:" + name);
            // B0 诊断: panel-open 后立即 dump layered HWND 结构, 捕获 visible_layered 峰值时刻
            if (DiagnosticsBootstrap.LayerAuditEnabled)
                LayerAuditDump.DumpToLog("panel-open:" + name);
            return true;
        }

        /// <summary>同名 panel 的上下文切换不拆 backdrop/HUD，只换实例水位并让 Web 重建 session。</summary>
        private void DoRebind(string name, string initDataJson)
        {
            string instanceId = NextPanelInstanceId();
            Func<string, string, string, string> enricher = _initDataEnricher;
            if (enricher != null) initDataJson = enricher(name, initDataJson, instanceId);
            string payload = BuildPanelOpenPayload(name, initDataJson, instanceId);
            try { _web.PostToWeb(payload); }
            catch (Exception ex) { LogManager.Log("[PanelHost] PostToWeb rebind failed: " + ex.Message); throw; }
            _activePanelInstanceId = instanceId;
            try { _web.AssertWebPanelPause(); } catch { }
            LogManager.Log("[PanelHost] rebound: " + name + " instance=" + instanceId);
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
                Control fp = GetFlashPanelOrNull();
                if (fp != null) fp.SizeChanged -= OnOwnerLayoutChanged;
            }
            catch { }
            _ownerLayoutSubscribed = false;
            _ownerLayoutPending = false;
            _lastOwnerAnchorRect = Rectangle.Empty;
            _lastOwnerPanelRect = Rectangle.Empty;
            if (_ownerLayoutSettleTimer != null)
            {
                try { _ownerLayoutSettleTimer.Stop(); } catch { }
            }
        }

        private void OnOwnerLayoutChanged(object sender, EventArgs e)
        {
            if (_disposed) return;
            if (_activePanel == null) return;
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
            ScheduleOwnerLayoutSettle();
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
                Rectangle newAnchor = _web.GetCurrentAnchorScreenRect();
                if (newAnchor.Width <= 0 || newAnchor.Height <= 0) return;
                Rectangle newPanelRect = PanelLayoutCatalog.GetRect(_activePanel, newAnchor);
                bool geometryChanged = !_lastOwnerAnchorRect.Equals(newAnchor)
                    || !_lastOwnerPanelRect.Equals(newPanelRect);
                if (!geometryChanged) return;
                bool panelSizeChanged = _lastOwnerPanelRect.IsEmpty
                    || _lastOwnerPanelRect.Width != newPanelRect.Width
                    || _lastOwnerPanelRect.Height != newPanelRect.Height;

                _backdrop.RepositionTo(newAnchor);
                _backdrop.SetPanelRect(newPanelRect);
                _web.RepositionForPanel(newPanelRect);
                _lastOwnerAnchorRect = newAnchor;
                _lastOwnerPanelRect = newPanelRect;

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
                _activePanel = null;
                _activePanelInstanceId = null;
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
            UnsubscribeOwnerLayout();
            // Step 1: WebOverlay 收尾（Phase 1 stub：SW_HIDE）
            // closingName 传给 SuspendAfterPanel 用于 [FocusRestore] 日志归因——
            // WebOverlay._activePanel 此时可能已被 HandlePanelMessage 置 null。
            try { _web.SuspendAfterPanel(closingName); }
            catch (Exception ex) { LogManager.Log("[PanelHost] SuspendAfterPanel failed: " + ex.Message); }
            // Step 2: Shield 退 telemetry
            if (_shield != null)
            {
                try { _shield.ExitTelemetryMode(); }
                catch (Exception ex) { LogManager.Log("[PanelHost] ExitTelemetryMode failed: " + ex.Message); }
            }
            // Step 3: backdrop 隐藏
            try { _backdrop.Hide(); }
            catch (Exception ex) { LogManager.Log("[PanelHost] backdrop.Hide failed: " + ex.Message); }
            // Step 4: HUD 复活（NativeHud + Phase 3 NotchOverlay/ToastOverlay 一并复显）
            try { _hud.Resume(); }
            catch (Exception ex) { LogManager.Log("[PanelHost] hud.Resume failed: " + ex.Message); }
            if (_notchOverlay != null) try { _notchOverlay.SetReady(); } catch (Exception ex) { LogManager.Log("[PanelHost] notch.SetReady failed: " + ex.Message); }
            if (_toastOverlay != null) try { _toastOverlay.SetReady(); } catch (Exception ex) { LogManager.Log("[PanelHost] toast.SetReady failed: " + ex.Message); }
            // Step 5: ESC 禁用
            if (_escSource != null) _escSource.SetPanelEscapeEnabled(false);
            // Step 6: cursor 重新顶置 + 强制刷一次位置（Notch/Toast 的 SetReady HWND_TOP 会把 cursor 压下；
            //   且 cursor 上次坐标可能在 panel 矩形内，关闭后该区域无 mouse hook 触发更新——直到玩家动鼠标
            //   才刷新 → 视觉上 cursor "消失，移动后突然出现"。这里主动 ReTop + 用当前真实鼠标位置刷一次）
            ReTopOverlay(_cursor as Form);
            try { _web.UpdateCursorFromScreenPoint(System.Windows.Forms.Cursor.Position); }
            catch (Exception ex) { LogManager.Log("[PanelHost] cursor refresh failed: " + ex.Message); }

            _activePanel = null;
            _activePanelInstanceId = null;
            PostPanelClosed(closingName, closingInstance);
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
            try
            {
                if (_ownerForm != null)
                    _ownerForm.HandleCreated -=
                        DelayedKickOnHandleCreated;
            }
            catch { }
            List<VisualRetireWaiter> failedRetires;
            lock (_queueLock)
            {
                failedRetires =
                    new List<VisualRetireWaiter>(
                        _visualRetireWaiters);
                foreach (PanelCommand queued in _queue)
                {
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
                _trackedLeasePanelName = null;
                _trackedLeaseInstanceId = null;
                _idleFenceToken = null;
                _visualRetireWaiters.Clear();
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
            if (_notchOverlay != null) { try { _notchOverlay.SetReady(); } catch { } }
            if (_toastOverlay != null) { try { _toastOverlay.SetReady(); } catch { } }
            if (_shield != null) { try { _shield.ExitTelemetryMode(); } catch { } }
            if (_escSource != null) { try { _escSource.SetPanelEscapeEnabled(false); } catch { } }
            string resetClosingName = _activePanel;
            string resetClosingInstance = _activePanelInstanceId;
            _activePanel = null;
            _activePanelInstanceId = null;
            _trackedLeasePanelName = null;
            _trackedLeaseInstanceId = null;
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

        private static string NextPanelInstanceId()
        {
            long seq = System.Threading.Interlocked.Increment(ref _panelInstanceSequence);
            return "panel." + DateTime.UtcNow.Ticks.ToString("x") + "." + seq.ToString("x");
        }
    }
}
