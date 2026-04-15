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

        // ==================== 状态字段（必须在 _stateLock 内读写，不变式 #19）====================
        private readonly object _stateLock = new object();
        private State _state = State.Idle;
        private string _currentAttemptId;
        private string _pendingSlot;
        private Process _currentFlashProcess;
        private int _timerGen;

        // per-attempt ready 缓存（attemptId → arrived？）不变式 #8
        private readonly Dictionary<string, bool> _cachedReady = new Dictionary<string, bool>();

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
            Action hotkeyGuardSpawn)
        {
            _socketServer = socketServer;
            _router = router;
            _processManager = processManager;
            _windowManager = windowManager;
            _form = form;
            _bootForm = bootForm;
            _readyWiring = readyWiring;
            _hotkeyGuardSpawn = hotkeyGuardSpawn;

            // Phase 1f：正常路径 bootstrap_handshake / bootstrap_ready 注册（plan §Phase 1f）
            _router.RegisterSync("bootstrap_handshake", HandleBootstrapHandshake);
            _router.RegisterSync("bootstrap_ready", HandleBootstrapReady);
            LogManager.Log("[LaunchFlow] bootstrap_handshake registered");
            LogManager.Log("[LaunchFlow] bootstrap_ready registered");

            _windowManager.OnEmbedResult += OnEmbedResult;
            _processManager.OnFlashExited += OnFlashExited;
            _socketServer.OnClientReady += OnSocketClientReady;
        }

        /// <summary>玩家选择 slot 后启动游戏。锁内快照 slot，后续使用局部变量。</summary>
        public void StartGame(string slot)
        {
            lock (_stateLock)
            {
                if (_state != State.Idle)
                {
                    LogManager.Log("[LaunchFlow] StartGame ignored: state=" + _state);
                    return;
                }
                _pendingSlot = slot;
                _currentAttemptId = Guid.NewGuid().ToString("N");
                _cachedReady.Clear();
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
        }

        /// <summary>socket OnClientReady: WaitingConnect → WaitingHandshake。</summary>
        private void OnSocketClientReady()
        {
            lock (_stateLock)
            {
                if (_state == State.WaitingConnect)
                    SetState(State.WaitingHandshake, "");
            }
        }

        /// <summary>HandleBootstrapHandshake 响应后调用（锁内）：触发异步 Embed。</summary>
        private void TransitionToEmbedding()
        {
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
            lock (_stateLock) { SetState(State.Error, msg); }
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
            }
        }

        private void OnFlashExited(Process exited)
        {
            LogManager.Log("[LaunchFlow] OnFlashExited pid=" + (exited != null ? exited.Id.ToString() : "null"));
            lock (_stateLock)
            {
                // 当前活跃状态下 Flash 突然退出 → Error；Idle/Error/Resetting 已处理过，忽略
                if (_state == State.Idle || _state == State.Error || _state == State.Resetting) return;
                TransitionToError("flash_exited");
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
