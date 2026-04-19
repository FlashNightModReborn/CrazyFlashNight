// P3b Phase 1f: 启动状态机骨架
//
// 状态转换（详见 plan compressed-floating-nebula.md §Phase 1f）：
//   Idle → Spawning → WaitingConnect → WaitingHandshake → Embedding → WaitingGameReady → Ready
//                                                                                     → Error
// 其他：Resetting（Reset 流程）
//
// 骨架阶段：TransitionTo* 方法存在但主要为 SetState + log；具体触发 processManager.Start /
// windowManager.EmbedFlashWindow 等代码在 11b-α 迁入（Phase 1i 改动归属表）。

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Threading;
using System.Windows.Forms;
using CF7Launcher.Bus;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Guardian
{
    public class GameLaunchFlow
    {
        public enum State
        {
            Idle,
            Spawning,
            WaitingConnect,
            WaitingHandshake,
            // Phase D: prewarm 模式下 handshake 已到达但 user 未选槽, held callback 等 StartGame 消费.
            PrewarmHandshakeHeld,
            Embedding,
            WaitingGameReady,
            Ready,
            Error,
            Resetting
        }

        // ==================== 依赖注入 ====================
        private readonly XmlSocketServer _socketServer;
        private readonly MessageRouter _router;
        private readonly ProcessManager _processManager;
        private readonly WindowManager _windowManager;
        private readonly GuardianForm _form;
        // Phase A: BootstrapForm → BootstrapPanel (UserControl 嵌入 GuardianForm)
        private readonly BootstrapPanel _bootstrapPanel;
        private readonly Action _readyWiring;
        private readonly Action _hotkeyGuardSpawn;
        private readonly CF7Launcher.Save.SaveResolutionContext _saveCtx;

        // Phase A Step A3a: RunOnUi 稳定 dispatcher 的 pending action 队列。
        // 句柄未创建 → 入队等 HandleCreated 事件 flush；dispose → drop 队列。
        private readonly Queue<Action> _pendingUiActions = new Queue<Action>();
        private const int PENDING_UI_ACTIONS_MAX = 64;
        private bool _pendingUiHooked;

        // ==================== 状态字段（必须在 _stateLock 内读写，不变式 #19）====================
        private readonly object _stateLock = new object();
        private State _state = State.Idle;
        private string _currentAttemptId;
        private string _pendingSlot;
        private Process _currentFlashProcess;
        private int _timerGen;

        // per-attempt ready 缓存（attemptId → arrived？）不变式 #8
        private readonly Dictionary<string, bool> _cachedReady = new Dictionary<string, bool>();

        // Flash zombie 兜底 (socket 断开 10s 后进程仍存活 → ForceExit).
        // 三层防护 (Timer.Dispose 不保证已入队回调不执行, 必须在回调内自校验):
        //   1. _zombieGen: arm 时 ++, callback 快照; gen 错位 = 已被替换/取消, drop
        //   2. attempt 快照: retry 后 _currentAttemptId 变, drop
        //   3. socket HasClient 实时查: 重连成功后 socket 已重建, drop
        private System.Threading.Timer _zombieTimer;
        private int _zombieGen;

        // Waiting 状态超时 (不变式 #17: _timerGen + attempt 双保险).
        // 每次 arm 时快照 (gen, attempt); 触发时 gen 错位或 attempt 错位即 DROP.
        private System.Threading.Timer _waitTimer;
        private const int WAIT_CONNECT_MS = 10000;      // Flash 连 socket
        private const int WAIT_HANDSHAKE_MS = 8000;     // 连上后 bootstrap_handshake 到达
        private const int WAIT_GAME_READY_MS = 8000;    // embed 完后 bootstrap_ready 到达

        // 存档决议：Phase C protocol v2。StartGame 锁外解析后设置，HandleBootstrapHandshake 响应读取。
        // 每次 StartGame 重置；每次 attempt 一份。
        private CF7Launcher.Save.SolResolveResult _resolvedSave;

        // Phase C Step C2: dry-run smoke 模式.
        // PrewarmDryRun 置为 true，HandleBootstrapHandshake 命中时短路响应 error=dryrun_abort + ThreadPool Reset.
        // Phase E 收尾时连同 PrewarmDryRun 方法 + __debug_dry_run cmd 一并删除.
        private bool _dryRunMode;

        // ==================== Phase D: prewarm / Reset coalescing 字段 ====================
        // Held handshake callback: prewarm 模式下 handshake 已到达但 user 未选 slot 时 park 这里,
        // StartGame 消费 (normal_flush) 或 deadline/degrade/reset 错误终结 (其余路径) 时 invoke.
        // respond 本身 gen-bound (XmlSocketServer asyncRespond 闭包走 TrySendIfGen), 无需 GameLaunchFlow 管 gen.
        private Action<string> _heldHandshakeCallback;
        private int _heldHandshakeReceivedMs;

        // Prewarm deadline (45s 无 slot → 主动 Reset 让用户走 legacy 路径).
        // Timer guard token = _currentAttemptId snapshot (避免 _timerGen 被 SetState 误递增).
        private System.Threading.Timer _prewarmDeadlineTimer;
        private const int PREWARM_DEADLINE_MS = 45000;

        // Abort latch: deadline/flash_crash/socket_disconnect 任一触发后 → 锁内立即拉,
        // 阻止 "worker 尚未跑 Reset 前 user 点 play 走 held consume" 的竞态.
        // Reset 最终 SetState(Idle) 前的独立锁块里清除.
        private bool _prewarmAborting;

        // Session-level latch: 一次 launcher 生命周期最多 Prewarm 一次 (Decision #4 冷启动仅一次).
        // 任何路径 (Reset/Error/ForceExit) 都**不**清除; bootstrap.html reload 多发 ready 时靠它挡.
        private bool _prewarmTriggered;

        // ==================== Phase D Step D11-R: Reset in-flight guard + pending queue ====================
        // 并发 Reset 调用 (OnFormClosing user_close / cancel_launch / dryrun_abort / prewarm_deadline /
        // DegradePrewarmFailureLocked / Retry / user_edit_*) 走这条协议:
        //   - 第一个入场者拿 ownership, 置 _resetInFlight=true, SetState(Resetting), 起 worker
        //   - 后续入场者只追加 onIdle 到队列, 不重复 SetState/启 worker; 等第一个 worker 推到 Idle 时统一 flush
        //   - Idle 态直接入场 → 快路径 flush 队列立即返回 (幂等)
        private readonly List<Action> _pendingIdleCallbacks = new List<Action>();
        private bool _resetInFlight;

        // ==================== 公共 API ====================

        /// <summary>
        /// 状态变更事件。参数：(state, message, silentAtEmit)。
        /// Phase D Step D11: silentAtEmit 在 SetState 锁内快照, 避免 subscriber 延迟执行时
        /// re-read live 状态导致旧事件被错误判定 non-silent (silent teardown 窗口内).
        /// 订阅方 (Program.cs UI 广播) 按 silentAtEmit=true 过滤不 post 给 BootstrapUI.
        /// </summary>
        public event Action<string, string, bool> OnStateChanged;

        public string CurrentState
        {
            get { lock (_stateLock) { return _state.ToString(); } }
        }

        /// <summary>
        /// Phase D Step D11: silent prewarm 谓词. 用于 BMH.RequireIdleOrTearDown 判断
        /// 是否可 "同步 tear down prewarm 再继续 cmd" (而不是 reject 为 not_idle).
        /// 包含 _prewarmAborting=true 的 teardown 窗口, 避免 Resetting 态错误命中 reject.
        /// </summary>
        public bool IsInSilentPrewarm
        {
            get
            {
                lock (_stateLock)
                {
                    if (_pendingSlot != null) return false;   // 用户已点 play, 不静默
                    return _prewarmAborting
                        || _state == State.Spawning
                        || _state == State.WaitingConnect
                        || _state == State.WaitingHandshake
                        || _state == State.PrewarmHandshakeHeld;
                }
            }
        }

        public GameLaunchFlow(
            XmlSocketServer socketServer,
            MessageRouter router,
            ProcessManager processManager,
            WindowManager windowManager,
            GuardianForm form,
            BootstrapPanel bootstrapPanel,
            Action readyWiring,
            Action hotkeyGuardSpawn,
            CF7Launcher.Save.SaveResolutionContext saveCtx)
        {
            _socketServer = socketServer;
            _router = router;
            _processManager = processManager;
            _windowManager = windowManager;
            _form = form;
            _bootstrapPanel = bootstrapPanel;
            _readyWiring = readyWiring;
            _hotkeyGuardSpawn = hotkeyGuardSpawn;
            _saveCtx = saveCtx;

            // Phase D Step D4: bootstrap_handshake 改 RegisterAsync 以支持 prewarm 模式的 held callback.
            // Async handler: 锁内判 prewarm/legacy 分支 → 锁外 respond() 同步写 socket (respond 本身 gen-bound).
            _router.RegisterAsync("bootstrap_handshake", HandleBootstrapHandshakeAsync);
            _router.RegisterSync("bootstrap_ready", HandleBootstrapReady);
            LogManager.Log("[LaunchFlow] bootstrap_handshake registered (async)");
            LogManager.Log("[LaunchFlow] bootstrap_ready registered");

            _windowManager.OnEmbedResult += OnEmbedResult;
            _processManager.OnFlashExited += OnFlashExitedExternal;
            _socketServer.OnClientReady += OnSocketClientReady;
            _socketServer.OnClientDisconnected += OnSocketClientDisconnected;
        }

        /// <summary>玩家选择 slot 后启动游戏。锁内快照 slot，后续使用局部变量。
        /// Phase D Step D5: 扩展接 prewarm 三种情形:
        ///   - Idle → legacy path (TransitionToSpawning)
        ///   - WaitingConnect / WaitingHandshake (prewarm 中 handshake 未到) → 存 slot, 握手到达后走快路径
        ///   - PrewarmHandshakeHeld → flush held callback + TransitionToEmbedding
        ///   - 其他 state → reject (already launching)
        /// 门闩优先: _prewarmAborting=true (deadline/degrade 正在跑 Reset) → reject, 用户再点走 legacy;
        ///           _pendingSlot != null (重复点击) → reject.
        /// </summary>
        public void StartGame(string slot)
        {
            // Phase C protocol v2: 锁外解析存档决议。避免在握手状态锁里做文件 I/O。
            // SolResolver 自身线程安全（使用 ArchiveTask 的 _lock）。
            CF7Launcher.Save.SolResolveResult resolved = null;
            if (_saveCtx != null)
            {
                try
                {
                    resolved = _saveCtx.Resolver.Resolve(slot, _saveCtx.SwfPath);
                    LogManager.Log("[LaunchFlow] save resolved: wire=" + resolved.WireDecision
                        + " kind=" + resolved.Kind
                        + " source=" + (resolved.Source != null ? resolved.Source : "n/a"));
                }
                catch (Exception ex)
                {
                    LogManager.Log("[LaunchFlow] SolResolver EXCEPTION: " + ex);
                    resolved = CF7Launcher.Save.SolResolveResult.CorruptFromException(ex);
                }
            }

            Action<string> heldCbToInvoke = null;
            string heldJsonToSend = null;

            lock (_stateLock)
            {
                // Phase D: abort 门闩优先级最高 (deadline/degrade worker 已拉闸但 Reset 未跑完)
                if (_prewarmAborting)
                {
                    LogManager.Log("[LaunchFlow] StartGame rejected: prewarm aborting, retry after Idle");
                    return;
                }
                // 前端按钮失灵 / 快速双击兜底
                if (_pendingSlot != null)
                {
                    LogManager.Log("[LaunchFlow] StartGame duplicate ignored: pendingSlot=" + _pendingSlot + " incoming=" + slot);
                    return;
                }

                if (_state == State.Idle)
                {
                    _pendingSlot = slot;
                    _currentAttemptId = Guid.NewGuid().ToString("N");
                    _resolvedSave = resolved;
                    _cachedReady.Clear();
                    CancelWaitTimerLocked();
                    CancelZombieTimerLocked();
                    TransitionToSpawning();
                }
                else if (_state == State.WaitingConnect || _state == State.WaitingHandshake)
                {
                    // prewarm 进行中, 握手尚未到达: 只存 slot/resolved, 不改 state, 不 bump attemptId,
                    // 待 handshake 到达时 HandleBootstrapHandshakeAsync 走 _pendingSlot != null 快路径.
                    _pendingSlot = slot;
                    _resolvedSave = resolved;
                    CancelPrewarmDeadlineLocked();
                    LogManager.Log("[LaunchFlow] StartGame consumed into prewarm (pre-handshake) state=" + _state);
                }
                else if (_state == State.PrewarmHandshakeHeld)
                {
                    // prewarm held callback 已等着: flush now.
                    _pendingSlot = slot;
                    _resolvedSave = resolved;
                    CancelPrewarmDeadlineLocked();
                    heldCbToInvoke = _heldHandshakeCallback;
                    _heldHandshakeCallback = null;  // 单一 owner: 先 null 再发
                    heldJsonToSend = BuildHandshakeResponseJsonLocked();
                    int heldMs = Environment.TickCount - _heldHandshakeReceivedMs;
                    LogManager.Log("[Prewarm] normal_flush held_ms=" + heldMs);
                    TransitionToEmbedding();  // 锁内: cancel WAIT_HANDSHAKE + state→Embedding 原子发生
                }
                else
                {
                    LogManager.Log("[LaunchFlow] StartGame ignored: state=" + _state);
                    return;
                }
            }

            // 锁外 send: held consume 路径的 gen-bound respond() 网络写.
            // TransitionToEmbedding 已在 send 前发生 → WAIT_HANDSHAKE 无 stale fire 窗口.
            SendHeldCallback(heldCbToInvoke, heldJsonToSend, "normal_flush");
        }

        /// <summary>
        /// Phase D Step D3: 冷启动 prewarm 入口.
        /// Session-level latch (_prewarmTriggered) 保证一次 launcher 生命周期最多 prewarm 一次 —
        /// 即便 WebView2 engine reload / 强刷 bootstrap.html 导致 `ready` 消息重发, 此处 no-op 挡住.
        /// 45s deadline (PREWARM_DEADLINE_MS): 用户在 bootstrap 页停留过久 → 主动 Reset 让用户走 legacy 路径.
        /// Phase D Step D9 (Half-2) 才把 bootstrap.html `ready` 消息接到 Prewarm(); Half-1 只提供方法本体.
        /// </summary>
        public void Prewarm()
        {
            lock (_stateLock)
            {
                if (_state != State.Idle)
                {
                    LogManager.Log("[Prewarm] ignored: state=" + _state);
                    return;
                }
                if (_prewarmTriggered)
                {
                    LogManager.Log("[Prewarm] ignored: session latch already triggered");
                    return;
                }
                _prewarmTriggered = true;
                _prewarmAborting = false;
                _currentAttemptId = Guid.NewGuid().ToString("N");
                _pendingSlot = null;       // 明确标记 prewarm 模式
                _resolvedSave = null;
                _cachedReady.Clear();
                CancelWaitTimerLocked();
                CancelZombieTimerLocked();
                LogManager.Log("[Prewarm] triggered attemptId=" + _currentAttemptId);
                TransitionToSpawning();
                ArmPrewarmDeadlineLocked(_currentAttemptId);
            }
        }

        /// <summary>
        /// 锁内调用. attemptIdSnap 作为 timer callback 的 guard token —
        /// 不用 _timerGen 是因为 SetState 每次 bump 它, 健康 prewarm 流程多次 SetState 会误伤 token 匹配.
        /// </summary>
        private void ArmPrewarmDeadlineLocked(string attemptIdSnap)
        {
            CancelPrewarmDeadlineLocked();
            _prewarmDeadlineTimer = new System.Threading.Timer(
                OnPrewarmDeadlineFired, attemptIdSnap, PREWARM_DEADLINE_MS, System.Threading.Timeout.Infinite);
        }

        private void CancelPrewarmDeadlineLocked()
        {
            if (_prewarmDeadlineTimer != null)
            {
                try { _prewarmDeadlineTimer.Dispose(); } catch { }
                _prewarmDeadlineTimer = null;
            }
        }

        /// <summary>
        /// Phase D Step D6: 45s deadline 触发. 委托给 DegradePrewarmFailureLocked 做统一的
        /// 拆 held callback + 拉 abort 门闩 + ThreadPool 派发 Reset 流程.
        /// 竞态保护:
        ///   - attemptId 快照错位 → drop (旧 attempt 的 stale timer)
        ///   - _pendingSlot != null → drop (用户已点 play, StartGame 接管)
        ///   - state == Idle → drop (Reset 已完成)
        /// </summary>
        private void OnPrewarmDeadlineFired(object stateObj)
        {
            string attemptIdSnap = stateObj as string;
            lock (_stateLock)
            {
                if (_currentAttemptId != attemptIdSnap)
                {
                    LogManager.Log("[Prewarm] deadline stale attempt, drop (snap=" + attemptIdSnap
                        + " current=" + _currentAttemptId + ")");
                    return;
                }
                if (_pendingSlot != null)
                {
                    LogManager.Log("[Prewarm] deadline ignored: user already picked slot");
                    return;
                }
                if (_state == State.Idle)
                {
                    LogManager.Log("[Prewarm] deadline ignored: state=Idle");
                    return;
                }
                DegradePrewarmFailureLocked("deadline", true);
            }
        }

        /// <summary>
        /// Phase D Step D7: prewarm 失败统一降级通道 (5-path 收敛: deadline / transition_to_error /
        /// flash_crash / socket_disconnected / reset_dismantle).
        /// 必须在 _stateLock 内调用. 幂等 (_prewarmAborting=true 时 no-op).
        /// 锁内拉 abort 门闩 + 取走 held callback + 取消 deadline; ThreadPool 派发 invoke + Reset.
        /// invokeCallback 参数:
        ///   - true: deadline / TransitionToError / flash_crash — 发 error 响应给 AS2 (原 socket 若已断, gen-bound respond 自动 drop)
        ///   - false: socket_disconnected — socket 已明确断, 显式跳过 invoke 更干净
        /// </summary>
        /// <param name="reason">路径标签, 拼进 error 字符串 "prewarm_" + reason</param>
        /// <param name="invokeCallback">是否 invoke held callback (false 仅用于 socket_disconnected 路径)</param>
        private void DegradePrewarmFailureLocked(string reason, bool invokeCallback)
        {
            if (_prewarmAborting) return;  // 幂等
            _prewarmAborting = true;
            Action<string> cb = _heldHandshakeCallback;
            _heldHandshakeCallback = null;
            CancelWaitTimerLocked();
            CancelZombieTimerLocked();
            CancelPrewarmDeadlineLocked();

            string rsn = "prewarm_" + reason;
            LogManager.Log("[Prewarm] degrade reason=" + rsn + " hadHeldCb=" + (cb != null));
            ThreadPool.QueueUserWorkItem(delegate
            {
                try
                {
                    if (invokeCallback && cb != null)
                        SendHeldCallback(cb, "{\"task\":\"bootstrap_handshake\",\"success\":false,\"error\":\"" + rsn + "\"}", reason);
                    Reset(null, rsn);
                }
                catch (Exception ex) { LogManager.Log("[Prewarm] degrade worker error: " + ex.Message); }
            });
        }

        /// <summary>
        /// Phase D Step D10: 统一 send wrapper 打遥测 + invoke held callback.
        /// path tag: normal_flush / deadline / transition_to_error / flash_crash / reset_dismantle / socket_disconnected.
        /// 单一 owner 验证: grep "[Prewarm] handshake_send path=" 每条 prewarm 流最多一次.
        /// </summary>
        private void SendHeldCallback(Action<string> cb, string json, string path)
        {
            if (cb == null) return;
            LogManager.Log("[Prewarm] handshake_send path=" + path);
            try { cb(json); }
            catch (Exception ex) { LogManager.Log("[Prewarm] held cb invoke error path=" + path + ": " + ex.Message); }
        }

        /// <summary>
        /// Phase C Step C2: dry-run smoke 入口。
        /// 走完整 GameLaunchFlow 状态机：bump attemptId → TransitionToSpawning → ArmEarlyReparent →
        /// WaitingConnect → Flash 连 socket → handshake 到达 → 短路 error=dryrun_abort → ThreadPool Reset.
        /// Idle 态 guard；已 dryrun 运行中 → no-op.
        /// Phase E 收尾时删除.
        /// </summary>
        public void PrewarmDryRun()
        {
            lock (_stateLock)
            {
                if (_state != State.Idle)
                {
                    LogManager.Log("[DryRun] ignored: state=" + _state);
                    return;
                }
                _dryRunMode = true;
                _pendingSlot = null;  // 明确标记 prewarm 模式（不落真 slot 避免存档副作用）
                _currentAttemptId = Guid.NewGuid().ToString("N");
                _resolvedSave = null;
                _cachedReady.Clear();
                CancelWaitTimerLocked();
                CancelZombieTimerLocked();
                LogManager.Log("[DryRun] start attemptId=" + _currentAttemptId);
                TransitionToSpawning();
            }
        }

        /// <summary>
        /// 错误后重试：公共 API，收边界（不向外暴露 _pendingSlot / continuation 时序）。
        /// 内部 = 锁内快照 slot → 锁外 Reset(onIdle, reason) 驱动。
        /// Finding A fix: _pendingSlot == null 时 (例如 user_edit_* teardown 失败进 Error,
        /// 或 prewarm 路径残留的 Error) 不能走 Retry→StartGame(null)→握手回退 "default" —
        /// 会把用户误带到错误的默认槽启动。改为 Reset(null, "retry_no_slot") 清 Error 回 Idle,
        /// 让用户回到 slot picker 重新选择.
        /// </summary>
        public void Retry()
        {
            string slot;
            lock (_stateLock)
            {
                if (_state != State.Error)
                {
                    LogManager.Log("[LaunchFlow] Retry ignored: state=" + _state);
                    return;
                }
                slot = _pendingSlot;
            }
            if (slot == null)
            {
                LogManager.Log("[LaunchFlow] Retry with no pending slot → Reset to Idle, user must re-pick slot");
                Reset(null, "retry_no_slot");
                return;
            }
            Reset(delegate { StartGame(slot); }, "retry");
        }

        /// <summary>
        /// 重置到 Idle。Error/Ready/任意态都可调（幂等）。
        /// onIdle 在 Idle 到达后、锁外触发（continuation 契约，用于 Retry）。
        /// reason 写入日志，便于事后追踪（user_cancel / user_close / retry / prewarm_deadline / ...）。
        ///
        /// Phase D Step D11-R (Finding 2 fix): in-flight guard + pending queue.
        /// 并发入口 (OnFormClosing user_close / cancel_launch / dryrun_abort / prewarm_deadline /
        /// DegradePrewarmFailureLocked / Retry / user_edit_* ...) 走同一协议:
        ///   1. 第一个入场者拿 ownership: _resetInFlight=true, SetState(Resetting), 起 worker
        ///   2. 后续入场者只追加 onIdle 到 _pendingIdleCallbacks 并返回, 不重启 worker, 不重复 SetState
        ///   3. Worker 最终到 Idle 时锁内 snapshot+clear 队列, 锁外 flush 全部 callback
        ///   4. Idle 态直接入场 → 快路径 flush 立即返回
        /// 避免 "多路径同时 kill Flash / 关 socket / 走完整 teardown" 的重入灾难.
        /// </summary>
        public void Reset(Action onIdle, string reason)
        {
            LogManager.Log("[LaunchFlow] Reset requested reason=" + (reason ?? "(none)"));
            List<Action> idleFlushIfAlready = null;
            Process oldProcess = null;
            Action<string> heldCbForReset = null;   // prewarm 拆除时取走的 held callback
            bool enterWorker = false;

            lock (_stateLock)
            {
                if (onIdle != null) _pendingIdleCallbacks.Add(onIdle);

                if (_state == State.Idle && !_resetInFlight)
                {
                    // 快路径: 已是 Idle 且无 worker, snapshot+clear 队列 flush outside lock
                    idleFlushIfAlready = new List<Action>(_pendingIdleCallbacks);
                    _pendingIdleCallbacks.Clear();
                }
                else if (_resetInFlight || _state == State.Resetting)
                {
                    // 已有 worker 在跑 teardown, 我们的 callback 刚追加进队列等它 flush.
                    LogManager.Log("[LaunchFlow] Reset coalesced (in-flight), reason=" + (reason ?? "(none)")
                        + " queueDepth=" + _pendingIdleCallbacks.Count);
                }
                else
                {
                    // Phase D Step D8: 判 "是否正在拆 prewarm"
                    // (_pendingSlot == null) && state ∈ 活跃 prewarm 集合.
                    // 无条件拉 _prewarmAborting 门闩防止 Reset 自关 socket 触发 OnSocketClientDisconnected
                    // 被识别为 "prewarm 失败" 再走 DegradePrewarmFailureLocked (互踩).
                    bool dismantlingPrewarm = (_pendingSlot == null)
                        && (_state == State.Spawning
                            || _state == State.WaitingConnect
                            || _state == State.WaitingHandshake
                            || _state == State.PrewarmHandshakeHeld);
                    if (dismantlingPrewarm && !_prewarmAborting)
                    {
                        _prewarmAborting = true;
                        heldCbForReset = _heldHandshakeCallback;
                        _heldHandshakeCallback = null;
                    }

                    // 第一个入场者: 拿 ownership
                    _resetInFlight = true;
                    SetState(State.Resetting, "");
                    oldProcess = _currentFlashProcess;
                    CancelWaitTimerLocked();
                    CancelZombieTimerLocked();
                    CancelPrewarmDeadlineLocked();
                    enterWorker = true;
                }
            }

            if (idleFlushIfAlready != null)
            {
                foreach (Action cb in idleFlushIfAlready)
                {
                    try { cb(); }
                    catch (Exception ex) { LogManager.Log("[LaunchFlow] Reset flush cb error: " + ex.Message); }
                }
                return;
            }
            if (!enterWorker) return;

            // === Teardown worker (仅 ownership 持有者执行) ===
            ManualResetEventSlim dcGate = new ManualResetEventSlim(false);
            Action dcHandler = delegate { dcGate.Set(); };
            bool needWaitDc = _socketServer.TrySubscribeOnClientDisconnected(dcHandler);

            Process oldProc = oldProcess;  // closure clarity
            Action<string> heldCbSnap = heldCbForReset;  // closure
            ThreadPool.QueueUserWorkItem(delegate
            {
                // Phase D Step D8: 如果这次 Reset 在拆 prewarm 且有 held callback, 先 invoke error 给 AS2.
                // 用 ThreadPool 之内的线程 fire 保证 "worker 内部一次性" 次序,
                // send 完了才开始 kill Flash / close socket (held cb 应该先到达 AS2).
                if (heldCbSnap != null)
                {
                    SendHeldCallback(heldCbSnap,
                        "{\"task\":\"bootstrap_handshake\",\"success\":false,\"error\":\"prewarm_reset_dismantle\"}",
                        "reset_dismantle");
                }

                bool resetSucceeded = true;
                try
                {
                    if (oldProc != null)
                    {
                        try
                        {
                            if (!oldProc.HasExited)
                            {
                                _processManager.KillFlash();
                                oldProc.WaitForExit(3000);
                            }
                        }
                        catch { }
                    }
                    if (needWaitDc)
                    {
                        if (!dcGate.Wait(5000))
                        {
                            _socketServer.ForceCloseCurrentClient();
                            if (!dcGate.Wait(1000)) resetSucceeded = false;
                        }
                    }
                }
                catch { resetSucceeded = false; }
                finally
                {
                    try { if (needWaitDc) _socketServer.OnClientDisconnected -= dcHandler; } catch { }
                    try { dcGate.Dispose(); } catch { }
                }
                bool finalOk = resetSucceeded;

                RunOnUi(delegate
                {
                    List<Action> toFlush = null;
                    bool errorBranch = false;

                    lock (_stateLock)
                    {
                        if (_currentFlashProcess == oldProc) _currentFlashProcess = null;
                        // Phase C Step C2: 清 dry-run 门闩
                        _dryRunMode = false;
                        // Phase D Step D8: Reset 完成即清 abort latch (若因 prewarm 进来的)
                        _prewarmAborting = false;
                        // Phase D Step D11-R: 清 _pendingSlot / _resolvedSave, 让 onIdle 里的 StartGame
                        // 能通过 D5 的 "_pendingSlot != null 防重复点击" 门闩进入 legacy 路径.
                        // (Retry → Reset(StartGame, "retry") → Idle → flush StartGame(slot) 必须能跑)
                        _pendingSlot = null;
                        _resolvedSave = null;

                        if (finalOk)
                        {
                            SetState(State.Idle, "");
                            _resetInFlight = false;
                            // 原子 snapshot+clear 队列, 锁外 flush
                            toFlush = new List<Action>(_pendingIdleCallbacks);
                            _pendingIdleCallbacks.Clear();
                        }
                        else
                        {
                            // Error 分支: 清 _resetInFlight 让后续 Reset 可以重新进入 worker.
                            // Finding B fix: 同时丢弃 _pendingIdleCallbacks — 队列里的 callback
                            // 代表 "Reset 成功后要执行的请求" (user_edit_save onReady /
                            // Retry 的 StartGame / ...); Reset 既然失败, 这些请求已无上下文,
                            // 若保留到下一次 unrelated Reset 成功时 flush, 会串味跨请求 (例如
                            // 几分钟前的导入对话框/保存动作被今天的 retry 顺带重放). 调用方应
                            // 重新发起请求.
                            int dropped = _pendingIdleCallbacks.Count;
                            _pendingIdleCallbacks.Clear();
                            if (dropped > 0)
                                LogManager.Log("[LaunchFlow] Reset error branch dropped " + dropped + " pending callback(s)");
                            _resetInFlight = false;
                            errorBranch = true;
                        }
                    }

                    // Phase C: 清 WindowManager EmbedPhase (防下一 attempt 吃脏句柄)
                    if (_windowManager != null) _windowManager.ResetEmbedState();

                    if (errorBranch)
                    {
                        TransitionToError("reset_socket_force_close_failed");
                        return;
                    }

                    // flush 锁外执行: callback 内部可能回调 StartGame / save / 其他 launchFlow API,
                    // 需 re-acquire _stateLock; 锁外 invoke 避免 reentry deadlock.
                    if (toFlush != null)
                    {
                        foreach (Action cb in toFlush)
                        {
                            try { cb(); }
                            catch (Exception ex) { LogManager.Log("[LaunchFlow] Reset onIdle cb error: " + ex.Message); }
                        }
                    }
                });
            });
        }

        // ==================== 状态迁移（骨架，具体调用在 11b-α 落地）====================

        private void TransitionToSpawning()
        {
            // 锁内调用（StartGame 已持锁）
            // Phase C: 进入新 attempt 前先清 WindowManager 的 EmbedPhase 字段（防脏句柄被下一轮吃）
            if (_windowManager != null) _windowManager.ResetEmbedState();

            SetState(State.Spawning, "");
            bool ok;
            try { ok = _processManager.Start(); }
            catch (Exception ex)
            {
                LogManager.Log("[LaunchFlow] processManager.Start threw: " + ex.Message);
                ok = false;
            }
            if (!ok)
            {
                TransitionToError("flash_start_failed");
                return;
            }
            _currentFlashProcess = _processManager.FlashProcess;
            if (_windowManager != null)
            {
                _windowManager.TrackProcess(_currentFlashProcess);
                // Phase C Step C1d: early reparent — Flash spawn 后立即后台 poll + SW_HIDE + SetParent 到 hidden FlashHostPanel
                // 压缩 top-level 可见窗口时间到 100-200ms；不触发 FireEmbedResult（reveal 由 EmbedFlashWindow 终点负责）
                if (_form != null && _form.FlashHostPanel != null)
                    _windowManager.ArmEarlyReparent(_currentFlashProcess, _form.FlashHostPanel);
            }
            if (_form != null)
                _form.TrackFlashProcess(_currentFlashProcess);
            SetState(State.WaitingConnect, "");
            ArmWaitTimeoutLocked(WAIT_CONNECT_MS, "socket_connect_timeout");
        }

        /// <summary>
        /// socket OnClientReady:
        ///   WaitingConnect → WaitingHandshake (首次连上);
        ///   Ready 态重连 (socket 短暂抖动后恢复) → 清 zombie timer 防延迟自杀.
        /// </summary>
        private void OnSocketClientReady()
        {
            lock (_stateLock)
            {
                if (_state == State.WaitingConnect)
                {
                    SetState(State.WaitingHandshake, "");
                    ArmWaitTimeoutLocked(WAIT_HANDSHAKE_MS, "handshake_timeout");
                }
                else if (_state == State.Ready)
                {
                    // 正常重连: 取消先前 OnSocketClientDisconnected armed 的 zombie timer,
                    // 否则 10s 后仍会按旧 attempt 触发, 错误地 ForceExit 健康会话.
                    CancelZombieTimerLocked();
                }
            }
        }

        /// <summary>HandleBootstrapHandshake 响应后调用（锁内）：触发异步 Embed。</summary>
        private void TransitionToEmbedding()
        {
            CancelWaitTimerLocked();  // 清 handshake 超时; WindowManager.EmbedFlashWindow 自带 10s 内置超时
            SetState(State.Embedding, "");
            Process flash = _currentFlashProcess;
            GuardianForm form = _form;
            WindowManager wm = _windowManager;
            if (flash == null || form == null || wm == null)
            {
                // spike / 测试路径：跳过 embed 直接 WaitingGameReady
                SetState(State.WaitingGameReady, "");
                return;
            }
            ThreadPool.QueueUserWorkItem(delegate
            {
                try { wm.EmbedFlashWindow(flash, form.FlashHostPanel); }
                catch (Exception ex)
                {
                    LogManager.Log("[LaunchFlow] EmbedFlashWindow threw: " + ex.Message);
                    wm.NotifyEmbedFailure();
                }
            });
        }

        /// <summary>HandleBootstrapReady 命中 WaitingGameReady 时调用（锁内）。</summary>
        private void TransitionToReady()
        {
            CancelWaitTimerLocked();  // 清 game_ready 超时
            SetState(State.Ready, "");
            RunOnUi(delegate
            {
                try { if (_readyWiring != null) _readyWiring(); }
                catch (Exception ex) { LogManager.Log("[LaunchFlow] readyWiring error: " + ex.Message); }
                // Phase A Step A4: panel swap 替代原 Show/Hide 双 Form 切换
                // 单 Form 模型下 GuardianForm 始终可见，无需 Show()
                try
                {
                    if (_form != null)
                    {
                        if (_form.BootstrapPanel != null) _form.BootstrapPanel.SetPanelVisible(false);
                        if (_form.FlashHostPanel != null) _form.FlashHostPanel.Visible = true;
                        _form.Activate();
                    }
                }
                catch (Exception ex) { LogManager.Log("[LaunchFlow] panel swap error: " + ex.Message); }
                try { if (_hotkeyGuardSpawn != null) _hotkeyGuardSpawn(); }
                catch (Exception ex) { LogManager.Log("[LaunchFlow] hotkeyGuardSpawn error: " + ex.Message); }
            });
        }

        private void TransitionToError(string msg)
        {
            Process toKill = null;
            lock (_stateLock)
            {
                // Phase D Step D7: prewarm 路径走 silent degrade 不入 Error 态.
                // _pendingSlot == null 表示 user 未点 play (prewarm 上下文);
                // 当前 state ∈ prewarm 活跃集合 (PrewarmHandshakeHeld 也在内, 防 held 状态下 WAIT_* 超时误伤).
                if (_pendingSlot == null
                    && (_state == State.Spawning
                        || _state == State.WaitingConnect
                        || _state == State.WaitingHandshake
                        || _state == State.PrewarmHandshakeHeld))
                {
                    DegradePrewarmFailureLocked(msg, true);
                    return;
                }
                CancelWaitTimerLocked();
                CancelZombieTimerLocked();
                // Finding C fix: 进 Error 时同步 kill Flash, 关掉 "launcher 已报 Error 但 Flash 还在
                // 按自己的 60s timeout 等响应" 的 zombie 窗口. 原 Flash 侧 5s timeout 时这个窗口 3s 内
                // 自行收口, 抬到 60s 后不 kill 会留 Flash 持续运行到用户点 Retry 才关.
                // 直接对 snapshot Process.Kill 不用 _processManager.KillFlash,
                // 避免 retry 并发 spawn 新 Flash 时误杀新进程.
                toKill = _currentFlashProcess;
                SetState(State.Error, msg);
            }
            if (toKill != null)
            {
                Process snap = toKill;
                ThreadPool.QueueUserWorkItem(delegate
                {
                    try
                    {
                        if (!snap.HasExited)
                        {
                            snap.Kill();
                            LogManager.Log("[LaunchFlow] TransitionToError killed Flash pid=" + snap.Id + " (zombie close)");
                        }
                    }
                    catch (Exception ex) { LogManager.Log("[LaunchFlow] TransitionToError kill error: " + ex.Message); }
                });
            }
        }

        // ==================== Router handler（构造期注册）====================

        /// <summary>
        /// Phase D Step D4: async handler. 锁内分支决策 + 状态迁移; 锁外 respond() 同步写 socket.
        /// respond 是 MessageRouter 传入的 gen-bound 回调 (XmlSocketServer asyncRespond 闭包),
        /// 原 connection 已断则底层 TrySendIfGen 自动 drop, GameLaunchFlow 不管 gen.
        ///
        /// 锁边界约束: respond() 不可在 _stateLock 内调用 (它是同步网络写).
        /// TransitionToEmbedding() 必须锁内调 (原子 cancel WAIT_HANDSHAKE + 改 state), 要在 respond 之前发生.
        /// </summary>
        private void HandleBootstrapHandshakeAsync(JObject msg, Action<string> respond)
        {
            string syncJsonToSend = null;
            lock (_stateLock)
            {
                // Phase C Step C2: dry-run smoke 短路响应. ThreadPool 派发 Reset 保证在 handler 返回 + socket send 之后跑.
                if (_dryRunMode)
                {
                    CancelWaitTimerLocked();
                    LogManager.Log("[DryRun] handshake received, aborting attempt=" + _currentAttemptId);
                    ThreadPool.QueueUserWorkItem(delegate
                    {
                        try { Reset(null, "dryrun_abort"); }
                        catch (Exception ex) { LogManager.Log("[DryRun] reset worker error: " + ex.Message); }
                    });
                    syncJsonToSend = "{\"task\":\"bootstrap_handshake\",\"success\":false,\"error\":\"dryrun_abort\"}";
                }
                else if (_state != State.WaitingConnect && _state != State.WaitingHandshake)
                {
                    LogManager.Log("[LaunchFlow] bootstrap_handshake rejected: state=" + _state);
                    syncJsonToSend = "{\"task\":\"bootstrap_handshake\",\"success\":false,\"error\":\"invalid_state\"}";
                }
                else if (_pendingSlot != null)
                {
                    // legacy / prewarm-fast-path: StartGame 已发生 (或 slot 在 handshake 前到达).
                    // 锁内构造 JSON + TransitionToEmbedding, 锁外 respond.
                    syncJsonToSend = BuildHandshakeResponseJsonLocked();
                    TransitionToEmbedding();
                }
                else
                {
                    // prewarm hold path: _pendingSlot == null → park callback 等 StartGame 消费.
                    // 显式 cancel WAIT_HANDSHAKE (held 期间可能跑超时, 一直到 Prewarm deadline 接管).
                    _heldHandshakeCallback = respond;
                    _heldHandshakeReceivedMs = Environment.TickCount;
                    CancelWaitTimerLocked();
                    SetState(State.PrewarmHandshakeHeld, "");
                    LogManager.Log("[Prewarm] handshake held, awaiting slot attemptId=" + _currentAttemptId);
                    // syncJsonToSend 保持 null → 锁外不 invoke (callback 留 held, deadline / consume 时 fire)
                }
            }
            // 锁外 send: state 已经是 Embedding (同步快路径) 或 PrewarmHandshakeHeld (hold 路径),
            // 两种状态下 WAIT_HANDSHAKE timer 都已 cancel, 不会有 stale timer fire.
            if (syncJsonToSend != null && respond != null)
                respond(syncJsonToSend);
        }

        /// <summary>
        /// 必须在 _stateLock 内调用. 原 HandleBootstrapHandshake L374-L392 JSON 组装抽成 helper,
        /// 由同步快路径 (handshake + slot 都已到达) 和 prewarm consume 路径 (StartGame 消费 held) 复用.
        /// </summary>
        private string BuildHandshakeResponseJsonLocked()
        {
            JObject resp = new JObject();
            resp["task"] = "bootstrap_handshake";
            resp["success"] = true;
            resp["attemptId"] = _currentAttemptId;
            resp["savePath"] = _pendingSlot != null ? _pendingSlot : "default";

            // Phase C protocol v2: 携带存档决议 + snapshot 下传给 Flash 侧 preload
            resp["protocol"] = 2;
            if (_resolvedSave != null)
            {
                resp["saveDecision"] = _resolvedSave.WireDecision;
                if (_resolvedSave.Snapshot != null)
                    resp["snapshot"] = _resolvedSave.Snapshot;
                if (_resolvedSave.Source != null)
                    resp["snapshotSource"] = _resolvedSave.Source;
                if (_resolvedSave.CorruptDetail != null)
                    resp["corruptDetail"] = _resolvedSave.CorruptDetail;
            }
            return resp.ToString(Newtonsoft.Json.Formatting.None);
        }

        private string HandleBootstrapReady(JObject msg)
        {
            lock (_stateLock)
            {
                // Flash 消息结构: {task, payload:{attemptId,...}, callId}; 从 payload 读
                JObject payload = msg.Value<JObject>("payload");
                string attemptId = payload != null ? payload.Value<string>("attemptId") : null;
                if (attemptId == null) attemptId = msg.Value<string>("attemptId");  // 兼容顶层
                if (attemptId != _currentAttemptId)
                {
                    LogManager.Log("[LaunchFlow] bootstrap_ready stale attemptId="
                        + (attemptId ?? "null") + " expected=" + _currentAttemptId);
                    return null;
                }
                if (_state != State.WaitingGameReady)
                {
                    // 提前到达，按 attemptId 缓存（不变式 #8）
                    _cachedReady[attemptId] = true;
                    return null;
                }
                TransitionToReady();
                return null;
            }
        }

        // ==================== 事件源回调 ====================

        private void OnEmbedResult(bool success)
        {
            LogManager.Log("[LaunchFlow] OnEmbedResult=" + success);
            lock (_stateLock)
            {
                if (_state != State.Embedding) return;  // 旧事件 / 状态已变
                if (!success) { TransitionToError("embed_timeout"); return; }
                // embed 成功 → WaitingGameReady；若 bootstrap_ready 已提前缓存则立即进 Ready
                SetState(State.WaitingGameReady, "");
                bool cached;
                if (_cachedReady.TryGetValue(_currentAttemptId, out cached) && cached)
                {
                    TransitionToReady();
                }
                else
                {
                    ArmWaitTimeoutLocked(WAIT_GAME_READY_MS, "game_ready_timeout");
                }
            }
        }

        /// <summary>
        /// Phase B Step B1: 唯一 Flash 退出真源（原 GuardianForm.TrackFlashProcess watchdog 已去 ForceExit）.
        /// 进程身份校验：ProcessManager 已按 ReferenceEquals 过滤 stale 事件，此处再校验
        /// `exited == _currentFlashProcess` 作为 belt & suspenders——Reset 可能已 null 化 _currentFlashProcess
        /// 或 attempt 已翻篇，此时当前 attempt 不应被 stale Flash 退出信号驱动状态机.
        /// </summary>
        private void OnFlashExitedExternal(Process exited)
        {
            LogManager.Log("[LaunchFlow] OnFlashExitedExternal pid=" + (exited != null ? exited.Id.ToString() : "null"));
            State snapshot;
            lock (_stateLock)
            {
                // 进程身份校验：当前 attempt 没有活 Flash，或 exited 不是当前追踪的进程 → 忽略
                if (_currentFlashProcess == null)
                {
                    LogManager.Log("[LaunchFlow] OnFlashExitedExternal drop: _currentFlashProcess=null");
                    return;
                }
                if (exited != null && !object.ReferenceEquals(exited, _currentFlashProcess))
                {
                    LogManager.Log("[LaunchFlow] OnFlashExitedExternal drop: stale process (expected pid="
                        + _currentFlashProcess.Id + ")");
                    return;
                }
                snapshot = _state;
            }
            switch (snapshot)
            {
                case State.Idle:
                case State.Error:
                case State.Resetting:
                    return;  // 已处理或未启动, 忽略
                case State.Ready:
                    // 玩家正常关游戏 → launcher 也退出（legacy）
                    LogManager.Log("[LaunchFlow] Flash exited in Ready state → forcing launcher exit");
                    CancelZombieTimer();
                    if (_form != null) _form.ForceExit();
                    return;
                default:
                    // 活跃启动态 (Spawning/WaitingConnect/WaitingHandshake/Embedding/WaitingGameReady)
                    // → TransitionToError 让 BootstrapUI 保留 Error 态供 retry
                    CancelZombieTimer();
                    // Phase C: launcher 不死但 attempt 换一轮 → 清 WindowManager EmbedPhase（防下一轮吃脏句柄）
                    if (_windowManager != null) _windowManager.ResetEmbedState();
                    lock (_stateLock) { TransitionToError("flash_exited"); }
                    return;
            }
        }

        /// <summary>
        /// Flash socket 断开处理:
        ///   - Phase D Step D8: prewarm 活跃态 (_pendingSlot==null) → DegradePrewarmFailureLocked (invokeCallback=false)
        ///     • Reset 自己关 socket 引发的 DC 被 _prewarmAborting 门闩 + Resetting/Idle 守卫挡住, 不互踩
        ///   - Ready 态: 10s 兜底 zombie timer (Flash Player 20 SA 偶发退出卡死)
        ///   - 其他: 忽略
        /// 按 _currentAttemptId 快照隔离: retry 后快照失配即放弃判定, 防误杀新 attempt.
        /// </summary>
        private void OnSocketClientDisconnected()
        {
            string attemptSnapshot = null;
            int genSnapshot = 0;
            bool armedZombie = false;
            lock (_stateLock)
            {
                // Phase D Step D8: 守卫 prewarm 已在降级中 / Reset 中 / 空闲. Reset 关 socket 会进这里,
                // 需要显式挡住, 防止再触 DegradePrewarmFailureLocked 互踩.
                if (_prewarmAborting) return;
                if (_state == State.Resetting || _state == State.Idle) return;

                // 真正外部断线 + prewarm 活跃态 → silent degrade (invokeCallback=false)
                if (_pendingSlot == null
                    && (_state == State.Spawning
                        || _state == State.WaitingConnect
                        || _state == State.WaitingHandshake
                        || _state == State.PrewarmHandshakeHeld))
                {
                    DegradePrewarmFailureLocked("socket_disconnected", false);
                    return;
                }

                // Ready 态: 保留既有 10s zombie timer 兜底
                if (_state != State.Ready) return;
                attemptSnapshot = _currentAttemptId;
                CancelZombieTimerLocked();  // 防多次断连累积 + 让前一轮 callback 的 gen 校验失配
                _zombieGen++;
                genSnapshot = _zombieGen;
                object payload = new ZombiePayload(attemptSnapshot, genSnapshot);
                _zombieTimer = new System.Threading.Timer(ZombieTimerCallback, payload, 10000, System.Threading.Timeout.Infinite);
                armedZombie = true;
            }
            if (armedZombie)
            {
                LogManager.Log("[LaunchFlow] socket disconnected in Ready, armed zombie timer attempt="
                    + attemptSnapshot + " gen=" + genSnapshot);
            }
        }

        private class ZombiePayload
        {
            public readonly string Attempt;
            public readonly int Gen;
            public ZombiePayload(string a, int g) { Attempt = a; Gen = g; }
        }

        private void ZombieTimerCallback(object state)
        {
            ZombiePayload payload = state as ZombiePayload;
            if (payload == null) return;
            Process flashAtCheck;
            lock (_stateLock)
            {
                // 三层校验:
                if (payload.Gen != _zombieGen)
                {
                    LogManager.Log("[LaunchFlow] zombie timer stale gen (" + payload.Gen + " vs " + _zombieGen + "), drop");
                    return;
                }
                if (payload.Attempt != _currentAttemptId)
                {
                    LogManager.Log("[LaunchFlow] zombie timer stale attempt, drop");
                    return;
                }
                if (_state != State.Ready)
                {
                    LogManager.Log("[LaunchFlow] zombie timer state changed to " + _state + ", drop");
                    return;
                }
                // socket 已重连 → 非 zombie, 健康会话. 顺手清掉本轮 timer 引用.
                if (_socketServer != null && _socketServer.HasClient)
                {
                    LogManager.Log("[LaunchFlow] zombie timer fired but socket reconnected, drop");
                    if (_zombieTimer != null)
                    {
                        try { _zombieTimer.Dispose(); } catch { }
                        _zombieTimer = null;
                    }
                    return;
                }
                flashAtCheck = _currentFlashProcess;
            }
            bool shouldKill = false;
            try { if (flashAtCheck != null && !flashAtCheck.HasExited) shouldKill = true; }
            catch { }
            if (shouldKill)
            {
                LogManager.Log("[LaunchFlow] Flash zombie detected (socket disconnected 10s, process alive, no reconnect) → ForceExit");
                if (_form != null) _form.ForceExit();
            }
        }

        /// <summary>锁内或锁外均可调用; 锁内调用者用 CancelZombieTimerLocked 避免重入开销.</summary>
        private void CancelZombieTimer()
        {
            lock (_stateLock) { CancelZombieTimerLocked(); }
        }

        /// <summary>
        /// 锁内调用. 不改 _zombieGen (由 arm 专用); 递增 gen 会误废将来 arm 的 callback.
        /// Dispose 后 gen 仍当前值, 已入队的旧回调进 callback 时会看到 gen 不变但 _zombieTimer==null;
        /// 回调自身不用 _zombieTimer 做 gate, 它靠 payload.Gen vs _zombieGen 校验 — 所以
        /// 如果 Cancel 后没再 arm 新 timer, 旧回调 gen 等于当前 gen, 需要额外机制阻断.
        /// 实现: 让 Cancel 也递增 gen (即 invalidation token), 新的 arm 再 ++ 一次.
        /// </summary>
        private void CancelZombieTimerLocked()
        {
            if (_zombieTimer != null)
            {
                try { _zombieTimer.Dispose(); } catch { }
                _zombieTimer = null;
                _zombieGen++;  // invalidation: 已入队的旧 callback 看到 gen 错位即 drop
            }
        }

        // ==================== Wait state timeout (不变式 #17) ====================

        /// <summary>
        /// 锁内调用. 在进入 Waiting* 状态后 arm 一次性 timer; 超时触发 TransitionToError.
        /// 快照 (_timerGen, _currentAttemptId); 触发回调时双重校验, 错位即 DROP.
        /// </summary>
        private void ArmWaitTimeoutLocked(int timeoutMs, string reason)
        {
            CancelWaitTimerLocked();
            int genSnap = _timerGen;
            string attemptSnap = _currentAttemptId;
            _waitTimer = new System.Threading.Timer(delegate(object payload)
            {
                lock (_stateLock)
                {
                    if (_timerGen != genSnap) return;           // 状态已变, stale
                    if (_currentAttemptId != attemptSnap) return;  // attempt 已变
                    LogManager.Log("[LaunchFlow] wait timeout: " + reason + " (gen=" + genSnap + ")");
                    TransitionToError(reason);
                }
            }, null, timeoutMs, System.Threading.Timeout.Infinite);
        }

        private void CancelWaitTimerLocked()
        {
            if (_waitTimer != null)
            {
                try { _waitTimer.Dispose(); } catch { }
                _waitTimer = null;
            }
        }

        // ==================== 基础设施 ====================

        /// <summary>必须在 _stateLock 内调用。广播 OnStateChanged 在锁外触发（UI 线程）。
        /// Phase D Step D11: silentAtEmit 在此处 (仍持 _stateLock) 快照并随事件下发,
        /// 避免 subscriber 通过 BeginInvoke 延迟执行时 re-read live 状态 — 队列里的旧 Spawning
        /// 事件在 _pendingSlot 已翻非空时会被误判为 non-silent, 导致静默承诺破绽.
        ///
        /// silentAtEmit = (_pendingSlot == null) && (_prewarmAborting || next ∈ prewarm 活跃集).
        /// _prewarmAborting=true 的 teardown 窗口必须包含 (否则 Reset 入口立刻 SetState(Resetting)
        /// → silentAtEmit 会被算 false → UI 闪 running badge + 编辑器只读).
        /// </summary>
        private void SetState(State next, string msg)
        {
            State prev = _state;
            _state = next;
            _timerGen++;
            LogManager.Log("[LaunchFlow] " + prev + " -> " + next
                + (string.IsNullOrEmpty(msg) ? "" : " (" + msg + ")"));
            Action<string, string, bool> handler = OnStateChanged;
            if (handler != null)
            {
                string stateName = next.ToString();
                string msgCopy = msg;
                bool silentAtEmit = (_pendingSlot == null) && (
                       _prewarmAborting
                    || next == State.Spawning
                    || next == State.WaitingConnect
                    || next == State.WaitingHandshake
                    || next == State.PrewarmHandshakeHeld
                );
                RunOnUi(delegate
                {
                    try { handler(stateName, msgCopy, silentAtEmit); }
                    catch (Exception ex) { LogManager.Log("[LaunchFlow] OnStateChanged error: " + ex.Message); }
                });
            }
        }

        // ==================== Phase A Step A3a: 稳定 UI dispatcher ====================
        // 契约（strict）:
        //   - 永不在后台线程直跑 action（WinForms 严禁跨线程 UI 调用）
        //   - 无 target / target 已 dispose → drop + log
        //   - target 存在但句柄未创建 → 入 pending 队列，等 HandleCreated 事件 flush
        //   - BeginInvoke 失败 → drop + log（不 fallback 直跑）
        //
        // 为什么不保留原"直跑"兜底：单 Form + panel + async teardown / OnFormClosing 下，
        // "句柄未创建 / 已 dispose" 从边角变成正常路径；直跑会随机崩。
        private void RunOnUi(Action action)
        {
            if (action == null) return;
            Control target = _bootstrapPanel != null ? (Control)_bootstrapPanel : (Control)_form;
            if (target == null)
            {
                LogManager.Log("[LaunchFlow] RunOnUi drop: no target");
                return;
            }
            if (target.IsDisposed)
            {
                LogManager.Log("[LaunchFlow] RunOnUi drop: target disposed");
                return;
            }
            if (!target.IsHandleCreated)
            {
                EnqueuePendingUi(target, action);
                return;
            }
            if (target.InvokeRequired)
            {
                try { target.BeginInvoke(action); return; }
                catch (ObjectDisposedException) { LogManager.Log("[LaunchFlow] RunOnUi drop: disposed mid-invoke"); return; }
                catch (InvalidOperationException) { LogManager.Log("[LaunchFlow] RunOnUi drop: invalid invoke"); return; }
            }
            try { action(); }
            catch (Exception ex) { LogManager.Log("[LaunchFlow] RunOnUi error: " + ex.Message); }
        }

        /// <summary>
        /// 句柄未创建时的 action 进入 pending 队列，HandleCreated 事件 flush；HandleDestroyed drop。
        /// 容量上限 PENDING_UI_ACTIONS_MAX 防内存泄漏。
        /// </summary>
        private void EnqueuePendingUi(Control target, Action action)
        {
            lock (_pendingUiActions)
            {
                if (_pendingUiActions.Count >= PENDING_UI_ACTIONS_MAX)
                {
                    // 丢最早的；优先保留较新的状态广播
                    _pendingUiActions.Dequeue();
                    LogManager.Log("[LaunchFlow] RunOnUi pending queue full, dropped oldest");
                }
                _pendingUiActions.Enqueue(action);

                if (!_pendingUiHooked)
                {
                    _pendingUiHooked = true;
                    target.HandleCreated += OnTargetHandleCreated;
                    target.HandleDestroyed += OnTargetHandleDestroyed;
                }
            }
        }

        private void OnTargetHandleCreated(object sender, EventArgs e)
        {
            Control target = sender as Control;
            if (target == null) return;
            Action[] drain;
            lock (_pendingUiActions)
            {
                drain = _pendingUiActions.ToArray();
                _pendingUiActions.Clear();
            }
            foreach (Action a in drain)
            {
                try { target.BeginInvoke(a); }
                catch (Exception ex) { LogManager.Log("[LaunchFlow] pending flush error: " + ex.Message); }
            }
        }

        private void OnTargetHandleDestroyed(object sender, EventArgs e)
        {
            int dropped;
            lock (_pendingUiActions)
            {
                dropped = _pendingUiActions.Count;
                _pendingUiActions.Clear();
            }
            if (dropped > 0)
                LogManager.Log("[LaunchFlow] RunOnUi pending drop on HandleDestroyed count=" + dropped);
        }
    }
}
