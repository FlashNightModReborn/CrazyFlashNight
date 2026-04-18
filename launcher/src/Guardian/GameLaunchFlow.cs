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

        // ==================== 公共 API ====================

        /// <summary>状态变更事件。参数：(state, message)。</summary>
        public event Action<string, string> OnStateChanged;

        public string CurrentState
        {
            get { lock (_stateLock) { return _state.ToString(); } }
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

            // Phase 1f：正常路径 bootstrap_handshake / bootstrap_ready 注册（plan §Phase 1f）
            _router.RegisterSync("bootstrap_handshake", HandleBootstrapHandshake);
            _router.RegisterSync("bootstrap_ready", HandleBootstrapReady);
            LogManager.Log("[LaunchFlow] bootstrap_handshake registered");
            LogManager.Log("[LaunchFlow] bootstrap_ready registered");

            _windowManager.OnEmbedResult += OnEmbedResult;
            _processManager.OnFlashExited += OnFlashExitedExternal;
            _socketServer.OnClientReady += OnSocketClientReady;
            _socketServer.OnClientDisconnected += OnSocketClientDisconnected;
        }

        /// <summary>玩家选择 slot 后启动游戏。锁内快照 slot，后续使用局部变量。</summary>
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

            lock (_stateLock)
            {
                if (_state != State.Idle)
                {
                    LogManager.Log("[LaunchFlow] StartGame ignored: state=" + _state);
                    return;
                }
                _pendingSlot = slot;
                _currentAttemptId = Guid.NewGuid().ToString("N");
                _resolvedSave = resolved;
                _cachedReady.Clear();
                CancelWaitTimerLocked();   // 新 attempt 前清旧 wait timer
                CancelZombieTimerLocked(); // 新 attempt 前清 zombie timer
                TransitionToSpawning();
            }
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
            Reset(delegate { StartGame(slot); }, "retry");
        }

        /// <summary>
        /// 重置到 Idle。Error/Ready/任意态都可调（幂等）。
        /// onIdle 在 Idle 到达后、锁外触发（continuation 契约，用于 Retry）。
        /// reason 写入日志，便于事后追踪（user_cancel / user_close / retry / prewarm_deadline / ...）。
        /// Phase B Step B3: reason 参数从 Phase D onwards 是门闩 / 信号路径的核心 token。
        /// </summary>
        public void Reset(Action onIdle, string reason)
        {
            LogManager.Log("[LaunchFlow] Reset requested reason=" + (reason ?? "(none)"));
            Process oldProcess;
            lock (_stateLock)
            {
                SetState(State.Resetting, "");
                oldProcess = _currentFlashProcess;  // 锁内快照（不变式 #19 + v21-r9）
                CancelWaitTimerLocked();    // 清 wait timer, 防 reset 期间误触
                CancelZombieTimerLocked();  // 清 zombie timer, 防 reset 期间误杀
            }

            ManualResetEventSlim dcGate = new ManualResetEventSlim(false);
            Action dcHandler = delegate { dcGate.Set(); };
            bool needWaitDc = _socketServer.TrySubscribeOnClientDisconnected(dcHandler);

            ThreadPool.QueueUserWorkItem(delegate
            {
                bool resetSucceeded = true;
                try
                {
                    if (oldProcess != null)
                    {
                        try
                        {
                            if (!oldProcess.HasExited)
                            {
                                _processManager.KillFlash();
                                oldProcess.WaitForExit(3000);
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
                    lock (_stateLock)
                    {
                        if (_currentFlashProcess == oldProcess) _currentFlashProcess = null;
                        // Phase C Step C2: 清 dry-run 门闩（Reset 完成 → 下次 StartGame 走正常路径）
                        _dryRunMode = false;
                    }
                    // Phase C: 清 WindowManager 的 EmbedPhase 字段（防下一 attempt 吃脏句柄）
                    if (_windowManager != null) _windowManager.ResetEmbedState();

                    if (finalOk)
                    {
                        SetState(State.Idle, "");
                        if (onIdle != null)
                        {
                            try { onIdle(); }
                            catch (Exception ex) { LogManager.Log("[LaunchFlow] Reset onIdle failed: " + ex.Message); }
                        }
                    }
                    else
                    {
                        TransitionToError("reset_socket_force_close_failed");
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
            lock (_stateLock)
            {
                CancelWaitTimerLocked();
                CancelZombieTimerLocked();
                SetState(State.Error, msg);
            }
        }

        // ==================== Router handler（构造期注册）====================

        private string HandleBootstrapHandshake(JObject msg)
        {
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
                    return "{\"task\":\"bootstrap_handshake\",\"success\":false,\"error\":\"dryrun_abort\"}";
                }

                if (_state != State.WaitingConnect && _state != State.WaitingHandshake)
                {
                    LogManager.Log("[LaunchFlow] bootstrap_handshake rejected: state=" + _state);
                    return "{\"task\":\"bootstrap_handshake\",\"success\":false,\"error\":\"invalid_state\"}";
                }
                // 响应 OK，推进到 Embedding（背景线程异步 embed）
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

                TransitionToEmbedding();
                return resp.ToString(Newtonsoft.Json.Formatting.None);
            }
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
        /// Flash socket 断开 10s 兜底: Flash Player 20 SA 偶发退出卡死, Process.Exited/HasExited 均不触发.
        /// 只在 Ready 状态生效 (活跃启动态由 OnFlashExited + state 机制接管).
        /// 按 _currentAttemptId 快照隔离: retry 后快照失配即放弃判定, 防误杀新 attempt.
        /// </summary>
        private void OnSocketClientDisconnected()
        {
            string attemptSnapshot;
            int genSnapshot;
            lock (_stateLock)
            {
                if (_state != State.Ready) return;  // 非 Ready 不启 zombie 兜底
                attemptSnapshot = _currentAttemptId;
                CancelZombieTimerLocked();  // 防多次断连累积 + 让前一轮 callback 的 gen 校验失配
                _zombieGen++;
                genSnapshot = _zombieGen;
                object payload = new ZombiePayload(attemptSnapshot, genSnapshot);
                _zombieTimer = new System.Threading.Timer(ZombieTimerCallback, payload, 10000, System.Threading.Timeout.Infinite);
            }
            LogManager.Log("[LaunchFlow] socket disconnected in Ready, armed zombie timer attempt="
                + attemptSnapshot + " gen=" + genSnapshot);
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

        /// <summary>必须在 _stateLock 内调用。广播 OnStateChanged 在锁外触发（UI 线程）。</summary>
        private void SetState(State next, string msg)
        {
            State prev = _state;
            _state = next;
            _timerGen++;
            LogManager.Log("[LaunchFlow] " + prev + " -> " + next
                + (string.IsNullOrEmpty(msg) ? "" : " (" + msg + ")"));
            Action<string, string> handler = OnStateChanged;
            if (handler != null)
            {
                string stateName = next.ToString();
                string msgCopy = msg;
                RunOnUi(delegate
                {
                    try { handler(stateName, msgCopy); }
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
