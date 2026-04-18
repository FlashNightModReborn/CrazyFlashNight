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
        private readonly BootstrapForm _bootForm;
        private readonly Action _readyWiring;
        private readonly Action _hotkeyGuardSpawn;
        private readonly CF7Launcher.Save.SaveResolutionContext _saveCtx;

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
            BootstrapForm bootForm,
            Action readyWiring,
            Action hotkeyGuardSpawn,
            CF7Launcher.Save.SaveResolutionContext saveCtx)
        {
            _socketServer = socketServer;
            _router = router;
            _processManager = processManager;
            _windowManager = windowManager;
            _form = form;
            _bootForm = bootForm;
            _readyWiring = readyWiring;
            _hotkeyGuardSpawn = hotkeyGuardSpawn;
            _saveCtx = saveCtx;

            // Phase 1f：正常路径 bootstrap_handshake / bootstrap_ready 注册（plan §Phase 1f）
            _router.RegisterSync("bootstrap_handshake", HandleBootstrapHandshake);
            _router.RegisterSync("bootstrap_ready", HandleBootstrapReady);
            LogManager.Log("[LaunchFlow] bootstrap_handshake registered");
            LogManager.Log("[LaunchFlow] bootstrap_ready registered");

            _windowManager.OnEmbedResult += OnEmbedResult;
            _processManager.OnFlashExited += OnFlashExited;
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
        /// 错误后重试：公共 API，收边界（不向外暴露 _pendingSlot / continuation 时序）。
        /// 内部 = 锁内快照 slot → 锁外 Reset(onIdle: () => StartGame(slot))。
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
            Reset(onIdle: delegate { StartGame(slot); });
        }

        /// <summary>
        /// 重置到 Idle。Error/Ready/任意态都可调（幂等）。
        /// onIdle 在 Idle 到达后、锁外触发（continuation 契约，用于 Retry）。
        /// </summary>
        public void Reset(Action onIdle)
        {
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
                    }
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
                _windowManager.TrackProcess(_currentFlashProcess);
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
                try
                {
                    if (_form != null)
                    {
                        _form.Show();
                        _form.Activate();
                    }
                }
                catch (Exception ex) { LogManager.Log("[LaunchFlow] form.Show error: " + ex.Message); }
                try { if (_bootForm != null) _bootForm.HideForReady(); }
                catch (Exception ex) { LogManager.Log("[LaunchFlow] bootForm.Hide error: " + ex.Message); }
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

        private void OnFlashExited(Process exited)
        {
            LogManager.Log("[LaunchFlow] OnFlashExited pid=" + (exited != null ? exited.Id.ToString() : "null"));
            State snapshot;
            lock (_stateLock) { snapshot = _state; }
            switch (snapshot)
            {
                case State.Idle:
                case State.Error:
                case State.Resetting:
                    return;  // 已处理或未启动, 忽略
                case State.Ready:
                    // 玩家正常关游戏 → launcher 也退出
                    LogManager.Log("[LaunchFlow] Flash exited in Ready state → forcing launcher exit");
                    CancelZombieTimer();
                    if (_form != null) _form.ForceExit();
                    return;
                default:
                    // 活跃启动态 (Spawning/WaitingConnect/WaitingHandshake/Embedding/WaitingGameReady)
                    // → TransitionToError 让 BootstrapForm 保留 Error 态供 retry
                    CancelZombieTimer();
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

        private void RunOnUi(Action action)
        {
            if (action == null) return;
            Control target = _bootForm != null ? (Control)_bootForm : (Control)_form;
            if (target != null && target.IsHandleCreated && target.InvokeRequired)
            {
                try { target.BeginInvoke(action); return; }
                catch { }
            }
            try { action(); }
            catch (Exception ex) { LogManager.Log("[LaunchFlow] RunOnUi error: " + ex.Message); }
        }
    }
}
