using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;
using System.Threading;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using CF7Launcher.Bus;
using CF7Launcher.Guardian;

namespace CF7Launcher.Tasks
{
    /// <summary>
    /// skills domain 的 Host 权威桥。Web callId 与 Flash 数字 callId 分层；写入接受、
    /// timeout/断线未知态和 reconcile 水位线均在这里收口，不能依赖 Web 页面生命周期保存。
    /// </summary>
    public sealed class SkillTask : IDisposable
    {
        private sealed class PendingRequest
        {
            public int FlashCallId;
            public string WebCallId;
            public string WebCmd;
            public string FlashAction;
            public string PanelInstanceId;
            public bool IsWrite;
            public bool IsReconcile;
            public int WriteEpoch;
            public int ReconcileTargetEpoch;
            public string ReconcileId;
            public string ReconcileAfterCallId;
            public JObject NormalizedPayload;
            public string ExpectedSkillKey;
            public int ExpectedDesiredLevel;
            public int ExpectedRevision = -1;
            public string ExpectedTrainerSession;
            public string ExpectedLearnToken;
            public string ExpectedView;
            public bool IsCleanup;
            public int CleanupGeneration;
            public bool IsBackgroundReconcile;
        }

        private sealed class LearnTokenBinding
        {
            public string Token;
            public string SkillKey;
            public int DesiredLevel;
            public int Revision;
            public string TrainerSession;
        }

        private sealed class RecentCall
        {
            public string CallId;
            public DateTime ExpiresUtc;
            public bool IsWrite;
            public int WriteEpoch;
        }

        private sealed class CleanupIntent
        {
            public int Generation;
            public string TrainerSession;
            public int AutoRetryCount;
        }

        private const int DefaultTimeoutMs = 10000;
        private const int MaxCleanupAutoRetries = 2;
        private const int MaxBackgroundReconcileAutoRetries = 2;
        private const int ReconcileStuckMs = 30000;
        private const int MaxPending = 4;
        private const int MaxTrackedCallIds = 256;
        private static readonly TimeSpan RecentLifetime = TimeSpan.FromSeconds(120);
        private static readonly Regex ValidCallId = new Regex("^[A-Za-z0-9._-]{1,96}$", RegexOptions.Compiled);
        private static readonly Regex ValidOpaque = new Regex("^[A-Za-z0-9._~-]{1,160}$", RegexOptions.Compiled);
        private static readonly HashSet<string> TopLevelKeys = Set(
            "type", "panel", "domain", "cmd", "callId", "panelInstanceId", "payload");
        private static readonly HashSet<string> HealthCodes = Set("ok", "invalid", "duplicate", "unknown");
        private static readonly HashSet<string> DiagnosticCodes = Set(
            "duplicate_skill_rows", "duplicate_trainer_entry", "invalid_skill_row", "invalid_boolean",
            "unknown_skill", "invalid_trainer_entry", "tail_data", "renderer_failed", "metadata_mismatch");
        private static readonly HashSet<string> DefinitiveWriteErrors = Set(
            "invalid_payload", "stale_state", "service_not_ready", "busy", "corrupt_skill_state",
            "skill_not_found", "not_learned", "already_equipped", "not_equippable", "slot_empty",
            "not_passive", "invalid_target", "equipped_skill_locked", "trainer_session_expired",
            "level_locked", "insufficient_sp", "max_level", "initial_level_must_be_one", "skill_table_full",
            "trainer_skill_forbidden", "invalid_level", "unknown_skill");

        private readonly Func<bool> _isClientReady;
        private readonly Func<string, bool> _trySend;
        private readonly int _timeoutMs;
        private readonly Dictionary<int, PendingRequest> _pending = new Dictionary<int, PendingRequest>();
        private readonly Dictionary<int, Timer> _timers = new Dictionary<int, Timer>();
        private readonly HashSet<string> _activeCallIds = new HashSet<string>(StringComparer.Ordinal);
        private readonly Dictionary<string, RecentCall> _recent = new Dictionary<string, RecentCall>(StringComparer.Ordinal);
        private readonly Queue<string> _recentOrder = new Queue<string>();
        private readonly Queue<CleanupIntent> _cleanupQueue = new Queue<CleanupIntent>();
        private readonly Dictionary<string, LearnTokenBinding> _learnTokens =
            new Dictionary<string, LearnTokenBinding>(StringComparer.Ordinal);
        private readonly object _lock = new object();
        private Action<string> _postToWeb;
        private Action<Action> _invokeOnUI;
        private Action _onCoordinatorSettled;
        private PendingRequest _queuedReconcile;
        private string _writeState = "idle";
        private string _activeWriteCallId;
        private string _lastWriteCallId;
        private string _lastWriteView = "manage";
        private string _lastWriteTrainerSession;
        private int _writeEpoch;
        private int _seq;
        private string _panelInstanceId;
        private string _panelView = "manage";
        private string _panelTrainerSession;
        // 教师页主动切到 manage 时，session 只在 Host 内暂存；Web manage initData
        // 仅得到 canReturnTrainer=true，不能读取或使用该 capability。关闭/断线会清理。
        private string _trainerReturnSession;
        private bool _preserveTrainerForNextManage;
        // Character Build -> Skills return is a Host-only, exact-instance capability. Web only
        // receives the display bit; a stale/rebound/notch/trainer instance can never exercise it.
        private bool _panelCanReturnCharacterBuild;
        private string _nextPanelInstanceId;
        private bool _nextPanelCanReturnCharacterBuild;
        private string _nextPanelView;
        private string _nextPanelTrainerSession;
        private string _lastClosedPanelInstanceId;
        private CleanupIntent _cleanupInFlight;
        private Timer _cleanupRetryTimer;
        private int _cleanupGeneration;
        private Timer _backgroundReconcileRetryTimer;
        private int _backgroundReconcileRetryCount;
        private bool _backgroundReconcileUseManage;
        private Timer _reconcileStuckTimer;
        private int _reconcileStuckEpoch = -1;
        private volatile bool _disposed;

        public SkillTask(XmlSocketServer socket)
            : this(delegate { return socket != null && socket.IsClientReady; },
                   delegate(string payload) { return socket != null && socket.TrySend(payload); }, DefaultTimeoutMs) { }

        public SkillTask(Func<bool> isClientReady, Func<string, bool> trySend, int timeoutMs = DefaultTimeoutMs)
        {
            _isClientReady = isClientReady ?? delegate { return false; };
            _trySend = trySend ?? delegate { return false; };
            _timeoutMs = Math.Max(1, timeoutMs);
        }

        public void SetPostToWeb(Action<string> post) { _postToWeb = post; }
        public void SetInvoker(Action<Action> invoker) { _invokeOnUI = invoker; }
        public void SetCoordinatorSettled(Action callback) { _onCoordinatorSettled = callback; }
        internal string WriteState { get { lock (_lock) return _writeState; } }
        internal int WriteEpoch { get { lock (_lock) return _writeEpoch; } }
        internal int PendingCount { get { lock (_lock) return _pending.Count + (_queuedReconcile != null ? 1 : 0); } }
        internal int CleanupBacklogCount { get { lock (_lock) return _cleanupQueue.Count + (_cleanupInFlight != null ? 1 : 0); } }
        public bool CanRebind { get { lock (_lock) return _writeState == "idle"; } }
        public bool CanSwitchTrainerToManage(string panelInstanceId)
        {
            lock (_lock)
                return IsOpaque(panelInstanceId)
                    && string.Equals(_panelInstanceId, panelInstanceId, StringComparison.Ordinal)
                    && _panelView == "trainer"
                    && IsOpaque(_panelTrainerSession)
                    && _writeState == "idle"
                    && !HasCleanupLocked();
        }
        public bool TrySuspendTrainerForManage(string panelInstanceId)
        {
            lock (_lock)
            {
                if (!IsOpaque(panelInstanceId)
                    || !string.Equals(_panelInstanceId, panelInstanceId, StringComparison.Ordinal)
                    || _panelView != "trainer" || !IsOpaque(_panelTrainerSession)
                    || _writeState != "idle" || HasCleanupLocked()) return false;
                _trainerReturnSession = _panelTrainerSession;
                _preserveTrainerForNextManage = true;
                // 预览 token 不能跨越 view/instance；返回教师页后必须重新预览。
                _learnTokens.Clear();
                return true;
            }
        }
        public bool TryGetTrainerReturnSession(string panelInstanceId, out string trainerSession)
        {
            lock (_lock)
            {
                trainerSession = null;
                if (!IsOpaque(panelInstanceId)
                    || !string.Equals(_panelInstanceId, panelInstanceId, StringComparison.Ordinal)
                    || _panelView != "manage" || !IsOpaque(_trainerReturnSession)
                    || _writeState != "idle" || HasCleanupLocked()) return false;
                trainerSession = _trainerReturnSession;
                return true;
            }
        }
        public bool CanOpenTrainer
        {
            get { lock (_lock) return _writeState == "idle" && !HasCleanupLocked() && !IsOpaque(_trainerReturnSession); }
        }

        public bool TryConsumeCharacterBuildReturnCapability(string panelInstanceId)
        {
            lock (_lock)
            {
                if (!IsOpaque(panelInstanceId)
                    || !string.Equals(_panelInstanceId, panelInstanceId, StringComparison.Ordinal)
                    || _panelView != "manage"
                    || !_panelCanReturnCharacterBuild
                    || IsOpaque(_trainerReturnSession)
                    || _writeState != "idle")
                {
                    return false;
                }
                _panelCanReturnCharacterBuild = false;
                return true;
            }
        }

        public bool IsClosedAndSettled
        {
            get
            {
                lock (_lock)
                {
                    return _panelInstanceId == null
                        && _writeState == "idle"
                        && _pending.Count == 0
                        && _queuedReconcile == null
                        && !HasCleanupLocked()
                        && _cleanupRetryTimer == null;
                }
            }
        }

        public void RequestTrainerCleanup(string trainerSession)
        {
            bool start;
            lock (_lock)
            {
                QueueTrainerCleanupLocked(IsOpaque(trainerSession) ? trainerSession : null, true);
                start = _writeState == "idle";
            }
            if (start) TryStartTrainerCleanup();
        }

        public void BindPanelInstance(string panelInstanceId)
        {
            if (!IsOpaque(panelInstanceId)) return;
            bool startCleanup = false;
            lock (_lock)
            {
                // Panel instance ids are one-shot capabilities.  An authoritative close may be
                // followed by a duplicate navigate/close envelope after Router cancellation or
                // timeout; never let that stale instance resurrect a closed SkillTask binding.
                if (string.Equals(
                        _lastClosedPanelInstanceId,
                        panelInstanceId,
                        StringComparison.Ordinal))
                {
                    return;
                }
                bool changed = !string.Equals(_panelInstanceId, panelInstanceId, StringComparison.Ordinal);
                if (!string.IsNullOrEmpty(_panelInstanceId) && changed && _writeState == "idle")
                {
                    CancelReadsForPanelLocked(_panelInstanceId);
                    _learnTokens.Clear();
                }
                if (changed)
                {
                    bool hasExactNextContext =
                        _nextPanelInstanceId == null
                        || string.Equals(
                            _nextPanelInstanceId,
                            panelInstanceId,
                            StringComparison.Ordinal);
                    string replacedTrainerSession = _panelView == "trainer" ? _panelTrainerSession : null;
                    string incomingTrainerSession = hasExactNextContext && _nextPanelView == "trainer"
                        ? _nextPanelTrainerSession : null;
                    if (IsOpaque(replacedTrainerSession) && IsOpaque(incomingTrainerSession)
                        && !string.Equals(replacedTrainerSession, incomingTrainerSession, StringComparison.Ordinal))
                    {
                        // AS2 keeps active A and candidate B until B's first domain request promotes it.
                        // Binding the new Web instance must therefore retain a scoped cleanup for A;
                        // an authoritative close before that first request will add B as the bounded latest intent.
                        QueueTrainerCleanupLocked(replacedTrainerSession, false);
                        startCleanup = _writeState == "idle";
                    }
                    _panelView = hasExactNextContext && _nextPanelView == "trainer"
                        ? "trainer" : "manage";
                    _panelTrainerSession = _panelView == "trainer" ? _nextPanelTrainerSession : null;
                    if (_panelView == "trainer" && IsOpaque(_trainerReturnSession)
                        && string.Equals(_panelTrainerSession, _trainerReturnSession, StringComparison.Ordinal))
                        _trainerReturnSession = null;
                    _preserveTrainerForNextManage = false;
                    _panelCanReturnCharacterBuild =
                        hasExactNextContext
                        && _nextPanelCanReturnCharacterBuild
                        && _panelView == "manage"
                        && !IsOpaque(_trainerReturnSession);
                    _nextPanelInstanceId = null;
                    _nextPanelCanReturnCharacterBuild = false;
                    _nextPanelView = null;
                    _nextPanelTrainerSession = null;
                }
                _panelInstanceId = panelInstanceId;
            }
            if (startCleanup) TryStartTrainerCleanup();
        }

        public string EnrichPanelInitData(string initDataJson)
        {
            // Compatibility helper for focused unit tests and non-PanelHost callers. Without an
            // exact generated instance no cross-panel return capability may be minted.
            return EnrichPanelInitData(initDataJson, null);
        }

        public string EnrichPanelInitData(string initDataJson, string panelInstanceId)
        {
            JObject init;
            try { init = string.IsNullOrEmpty(initDataJson) ? new JObject() : JObject.Parse(initDataJson); }
            catch { init = new JObject(); }
            bool startCleanup = false;
            lock (_lock)
            {
                string view = ReadString(init["view"]);
                string requestedTrainerSession = ReadString(init["trainerSession"]);
                bool requestedCharacterBuildReturn =
                    IsOpaque(panelInstanceId)
                    && init["canReturnCharacterBuild"] != null
                    && init["canReturnCharacterBuild"].Type == JTokenType.Boolean
                    && init.Value<bool>("canReturnCharacterBuild");
                if (view == "trainer" && (_writeState != "idle" || HasCleanupLocked()))
                {
                    // 断线/未知写之后 AS2 可能已经创建了一个新教师 session。此时不能把它展示给
                    // Web，再在对账完成后被迟到 cleanup 误杀；降级到 manage 让页面先完成恢复。
                    QueueTrainerCleanupLocked(IsOpaque(requestedTrainerSession) ? requestedTrainerSession : null, true);
                    init["view"] = "manage";
                    init["source"] = "nativehud";
                    init.Remove("trainerSession");
                    init.Remove("canReturnCharacterBuild");
                    requestedCharacterBuildReturn = false;
                    view = "manage";
                }
                if (view == "trainer")
                {
                    init.Remove("canReturnCharacterBuild");
                    requestedCharacterBuildReturn = false;
                }
                if (view == "manage")
                {
                    _learnTokens.Clear();
                    string currentSession = _panelView == "trainer" ? _panelTrainerSession : null;
                    bool preserveReturn = _preserveTrainerForNextManage
                        && IsOpaque(currentSession) && IsOpaque(_trainerReturnSession)
                        && string.Equals(currentSession, _trainerReturnSession, StringComparison.Ordinal);
                    _preserveTrainerForNextManage = false;
                    if (preserveReturn)
                    {
                        // 只下发无权限的展示布尔值；trainerSession 仍只存在于 Host。
                        init["canReturnTrainer"] = true;
                        init.Remove("canReturnCharacterBuild");
                        requestedCharacterBuildReturn = false;
                    }
                    else
                    {
                        string cleanupSession = IsOpaque(currentSession) ? currentSession : _trainerReturnSession;
                        QueueTrainerCleanupLocked(cleanupSession, false);
                        _trainerReturnSession = null;
                        startCleanup = _writeState == "idle";
                    }
                }
                if (requestedCharacterBuildReturn
                    && init.Value<string>("source") == "nativehud"
                    && init["canReturnTrainer"] == null)
                {
                    init["canReturnCharacterBuild"] = true;
                }
                else
                {
                    init.Remove("canReturnCharacterBuild");
                    requestedCharacterBuildReturn = false;
                }
                _nextPanelInstanceId = IsOpaque(panelInstanceId)
                    ? panelInstanceId : null;
                _nextPanelCanReturnCharacterBuild =
                    requestedCharacterBuildReturn;
                _nextPanelView = view == "trainer" ? "trainer" : "manage";
                _nextPanelTrainerSession = _nextPanelView == "trainer" ? ReadString(init["trainerSession"]) : null;
                init["writeEpoch"] = _writeEpoch;
                if (_writeState == "idle") init["writeState"] = "idle";
                else
                {
                    // 新 Web session 没有旧 write mux；即使 Host 仍 pending，也必须从显式 probe 接续。
                    init["writeState"] = "needs_reconcile";
                    if (IsCallId(_lastWriteCallId)) init["reconcileAfterCallId"] = _lastWriteCallId;
                }
            }
            if (startCleanup) TryStartTrainerCleanup();
            return init.ToString(Formatting.None);
        }

        public void DiscardUnboundPanelInitContext()
        {
            lock (_lock)
            {
                _nextPanelInstanceId = null;
                _nextPanelCanReturnCharacterBuild = false;
                _nextPanelView = null;
                _nextPanelTrainerSession = null;
            }
        }

        public void HandleWebRequest(string cmd, JObject parsed)
        {
            string callId = parsed != null && parsed["callId"] != null && parsed["callId"].Type == JTokenType.String
                ? parsed.Value<string>("callId") : null;
            if (!IsCallId(callId)) { RespondError(callId, cmd, "invalid_call_id", false, null, CurrentEpoch()); return; }

            string action;
            bool isWrite;
            if (!TryResolveCommand(cmd, out action, out isWrite))
            { RejectAndRemember(callId, cmd, "unsupported_cmd"); return; }
            if (!IsExactObject(parsed, TopLevelKeys)
                || !IsExactString(parsed["type"], "panel")
                || !IsExactString(parsed["panel"], "skills")
                || !IsExactString(parsed["domain"], "skills")
                || !IsExactString(parsed["cmd"], cmd))
            { RejectAndRemember(callId, cmd, "invalid_payload"); return; }

            string requestedInstance = ReadString(parsed["panelInstanceId"]);
            string instance;
            string activeView;
            string activeTrainerSession;
            lock (_lock)
            {
                instance = _panelInstanceId;
                activeView = _panelView;
                activeTrainerSession = _panelTrainerSession;
            }
            if (!IsOpaque(requestedInstance) || !IsOpaque(instance)
                || !string.Equals(requestedInstance, instance, StringComparison.Ordinal))
            { RejectAndRemember(callId, cmd, "panel_instance_expired"); return; }

            JObject normalized;
            bool isReconcile;
            if (!TryNormalizePayload(cmd, parsed["payload"] as JObject, out normalized, out isReconcile))
            { RejectAndRemember(callId, cmd, "invalid_payload"); return; }

            if (!_isClientReady()) { RejectAndRemember(callId, cmd, "disconnected"); return; }
            if (cmd == "snapshot"
                && (normalized.Value<string>("view") != activeView
                    || (activeView == "trainer"
                        && normalized.Value<string>("trainerSession") != activeTrainerSession)))
            { RejectAndRemember(callId, cmd, "panel_context_mismatch"); return; }
            if (cmd == "learnPreview"
                && (activeView != "trainer"
                    || normalized.Value<string>("trainerSession") != activeTrainerSession))
            { RejectAndRemember(callId, cmd, "panel_context_mismatch"); return; }
            if ((cmd == "learnCommit" && activeView != "trainer")
                || (isWrite && cmd != "learnCommit" && activeView != "manage"))
            { RejectAndRemember(callId, cmd, "panel_context_mismatch"); return; }

            PendingRequest entry = new PendingRequest
            {
                WebCallId = callId,
                WebCmd = cmd,
                FlashAction = action,
                PanelInstanceId = instance,
                IsWrite = isWrite,
                IsReconcile = isReconcile,
                NormalizedPayload = normalized,
                ExpectedView = activeView,
                ExpectedTrainerSession = activeTrainerSession
            };
            bool queueReconcile = false;
            string reject = null;
            PendingRequest supersededReconcile = null;
            lock (_lock)
            {
                PruneRecentLocked();
                if (_activeCallIds.Contains(callId) || _recent.ContainsKey(callId)) return;
                if (cmd == "learnPreview")
                {
                    foreach (PendingRequest oldPreview in _pending.Values
                        .Where(p => !p.IsCleanup && p.WebCmd == "learnPreview").ToArray())
                        CompletePendingLocked(oldPreview);
                    ClearLearnTokensForSessionLocked(normalized.Value<string>("trainerSession"));
                }
                if (_pending.Count + (_queuedReconcile != null ? 1 : 0) >= MaxPending) reject = "busy";
                else if (isReconcile)
                {
                    entry.ReconcileId = normalized.Value<string>("reconcileId");
                    entry.ReconcileAfterCallId = normalized.Value<string>("reconcileAfterCallId");
                    RecentCall target;
                    bool targetsActiveWrite = _writeState == "write_pending"
                        && string.Equals(_activeWriteCallId, entry.ReconcileAfterCallId, StringComparison.Ordinal);
                    bool targetsRecentWrite = _recent.TryGetValue(entry.ReconcileAfterCallId, out target) && target.IsWrite;
                    if (_writeState == "write_pending")
                    {
                        if (!targetsActiveWrite) reject = "invalid_payload";
                        else
                        {
                            entry.ReconcileTargetEpoch = _writeEpoch;
                            entry.WriteEpoch = _writeEpoch;
                            _activeCallIds.Add(callId);
                            if (_queuedReconcile != null)
                            {
                                supersededReconcile = _queuedReconcile;
                                CompleteQueuedReconcileLocked(_queuedReconcile);
                            }
                            _queuedReconcile = entry;
                            queueReconcile = true;
                        }
                    }
                    else if (_writeState == "needs_reconcile")
                    {
                        if (!IsCallId(_lastWriteCallId)
                            || !string.Equals(_lastWriteCallId, entry.ReconcileAfterCallId, StringComparison.Ordinal))
                            reject = "invalid_payload";
                        else
                        {
                            entry.ReconcileTargetEpoch = _writeEpoch;
                            entry.WriteEpoch = _writeEpoch;
                            _activeCallIds.Add(callId);
                        }
                    }
                    else
                    {
                        // idle 下允许 recent/unknown target：Host 重启、send=false 或 TTL 过期后仍有恢复入口。
                        entry.ReconcileTargetEpoch = targetsRecentWrite ? target.WriteEpoch : _writeEpoch;
                        entry.WriteEpoch = targetsRecentWrite ? Math.Max(_writeEpoch, target.WriteEpoch) : _writeEpoch;
                        _activeCallIds.Add(callId);
                    }
                }
                else if (isWrite)
                {
                    if (_writeState != "idle") reject = _writeState == "needs_reconcile" ? "reconcile_required" : "busy";
                    else if (cmd == "learnCommit")
                    {
                        string token = normalized.Value<string>("expectedLearnToken");
                        LearnTokenBinding binding;
                        if (!_learnTokens.TryGetValue(token, out binding)) reject = "invalid_payload";
                        else
                        {
                            _learnTokens.Remove(token);
                            entry.ExpectedLearnToken = token;
                            entry.ExpectedSkillKey = binding.SkillKey;
                            entry.ExpectedDesiredLevel = binding.DesiredLevel;
                            entry.ExpectedRevision = binding.Revision;
                            entry.ExpectedTrainerSession = binding.TrainerSession;
                        }
                    }
                    if (reject == null)
                    {
                        _writeEpoch++;
                        entry.WriteEpoch = _writeEpoch;
                        _writeState = "write_pending";
                        _activeWriteCallId = callId;
                        _lastWriteCallId = callId;
                        _lastWriteView = entry.ExpectedView == "trainer" ? "trainer" : "manage";
                        _lastWriteTrainerSession = _lastWriteView == "trainer" ? entry.ExpectedTrainerSession : null;
                        _backgroundReconcileUseManage = false;
                        _backgroundReconcileRetryCount = 0;
                        CancelBackgroundReconcileRetryLocked();
                        CancelReconcileWatchdogLocked();
                        _activeCallIds.Add(callId);
                    }
                }
                else
                {
                    if (_writeState == "write_pending") reject = "busy";
                    else if (_writeState == "needs_reconcile") reject = "reconcile_required";
                    else if (_pending.Values.Any(p => !p.IsWrite && !p.IsReconcile && p.WebCmd == cmd)) reject = "busy";
                    else
                    {
                        entry.WriteEpoch = _writeEpoch;
                        _activeCallIds.Add(callId);
                    }
                }
                if (reject != null)
                {
                    RememberRecentLocked(callId, false, _writeEpoch);
                }
            }

            if (reject != null) { RespondError(callId, cmd, reject, false, instance, CurrentEpoch()); return; }
            if (supersededReconcile != null)
                RespondError(supersededReconcile.WebCallId, supersededReconcile.WebCmd, "superseded", false,
                    supersededReconcile.PanelInstanceId, CurrentEpoch());
            if (queueReconcile) return;
            DispatchToFlash(entry);
        }

        public void HandleFlashResponse(JObject msg, Action<string> respond)
        {
            int fid;
            if (!TryReadInteger(msg != null ? msg["callId"] : null, 1, int.MaxValue, out fid))
            { if (respond != null) respond(null); return; }
            PendingRequest entry;
            lock (_lock)
            {
                if (!_pending.TryGetValue(fid, out entry)) { if (respond != null) respond(null); return; }
            }
            if (entry.IsCleanup)
            {
                HandleCleanupFlashResponse(entry, SanitizeFlashResponse(msg));
                if (respond != null) respond(null);
                return;
            }
            PendingRequest queued = null;
            JObject web;
            bool notifySettled = false;
            bool startBackgroundReconcile = false;
            bool retryBackgroundNow = false;
            bool scheduleBackgroundRetry = false;
            bool writeSettled = false;
            bool writeUnknown = false;
            bool reconcileCompleted = false;
            JObject sanitized = SanitizeFlashResponse(msg);
            lock (_lock)
            {
                if (!_pending.TryGetValue(fid, out entry)) { if (respond != null) respond(null); return; }
                bool valid = IsValidResponse(sanitized, entry);
                bool definitive = entry.IsWrite && valid && IsDefinitiveWriteResponse(sanitized);
                if (valid && entry.WebCmd == "learnPreview" && sanitized.Value<bool?>("success") == true)
                    RememberLearnPreviewLocked(sanitized);
                CompletePendingLocked(entry);

                web = valid ? (JObject)sanitized.DeepClone() : new JObject
                {
                    ["success"] = false,
                    ["error"] = "malformed_response"
                };

                if (entry.IsWrite)
                {
                    _activeWriteCallId = null;
                    _writeState = definitive ? "idle" : "needs_reconcile";
                    writeSettled = definitive;
                    writeUnknown = !definitive;
                    if (definitive)
                    {
                        CancelBackgroundReconcileRetryLocked();
                        CancelReconcileWatchdogLocked();
                    }
                    else
                    {
                        web["requiresReconcile"] = true;
                        EnsureReconcileWatchdogLocked();
                        startBackgroundReconcile = _panelInstanceId == null;
                    }
                    if (_queuedReconcile != null)
                    {
                        queued = _queuedReconcile;
                        _queuedReconcile = null;
                        queued.WriteEpoch = _writeEpoch;
                    }
                    notifySettled = definitive && queued == null;
                }
                else if (entry.IsReconcile)
                {
                    bool succeeded = valid && sanitized.Value<bool?>("success") == true;
                    bool currentWatermark = entry.WriteEpoch == _writeEpoch
                        && entry.WriteEpoch >= entry.ReconcileTargetEpoch
                        && (_writeState != "needs_reconcile"
                            || (IsCallId(entry.ReconcileAfterCallId)
                                && string.Equals(entry.ReconcileAfterCallId, _lastWriteCallId, StringComparison.Ordinal)));
                    bool clears = succeeded && currentWatermark && _writeState != "write_pending";
                    if (clears)
                    {
                        _writeState = "idle";
                        CancelBackgroundReconcileRetryLocked();
                        CancelReconcileWatchdogLocked();
                        _backgroundReconcileRetryCount = 0;
                        _backgroundReconcileUseManage = false;
                        if (!entry.IsBackgroundReconcile)
                        {
                            web["reconciled"] = true;
                            web["reconcileId"] = entry.ReconcileId;
                        }
                        reconcileCompleted = true;
                        notifySettled = true;
                    }
                    else if (entry.IsBackgroundReconcile && _writeState == "needs_reconcile")
                    {
                        bool trainerExpired = valid && sanitized.Value<bool?>("success") == false
                            && sanitized.Value<string>("error") == "trainer_session_expired"
                            && entry.ExpectedView == "trainer";
                        if (trainerExpired)
                        {
                            // Learning may have committed and invalidated the trainer capability before
                            // returning its post-write snapshot. Reconcile domain state through manage.
                            _backgroundReconcileUseManage = true;
                            _backgroundReconcileRetryCount = 0;
                            retryBackgroundNow = true;
                        }
                        else if (_backgroundReconcileRetryCount < MaxBackgroundReconcileAutoRetries)
                        {
                            _backgroundReconcileRetryCount++;
                            scheduleBackgroundRetry = true;
                        }
                        EnsureReconcileWatchdogLocked();
                    }
                }
            }

            if (!entry.IsBackgroundReconcile) StampAndPost(web, entry);
            if (writeSettled)
                LogManager.Log("event=skill_write_settled callId=" + entry.WebCallId + " epoch=" + entry.WriteEpoch);
            else if (writeUnknown)
                LogManager.Log("event=skill_write_unknown callId=" + entry.WebCallId + " epoch=" + entry.WriteEpoch);
            if (reconcileCompleted)
                LogManager.Log("event=skill_reconcile_completed epoch=" + entry.WriteEpoch
                    + " background=" + entry.IsBackgroundReconcile.ToString().ToLowerInvariant());
            if (queued != null) DispatchToFlash(queued);
            if (retryBackgroundNow) TryStartBackgroundReconcile();
            else if (scheduleBackgroundRetry) ScheduleBackgroundReconcileRetry();
            else if (startBackgroundReconcile && queued == null) TryStartBackgroundReconcile();
            if (notifySettled) NotifyCoordinatorSettled();
            if (respond != null) respond(null);
        }

        public bool HandlePanelClosed(string panelInstanceId)
        {
            bool startCleanup;
            bool startBackgroundReconcile;
            lock (_lock)
            {
                if (!IsOpaque(panelInstanceId) || !string.Equals(_panelInstanceId, panelInstanceId, StringComparison.Ordinal))
                    return false;
                string closingSession = _panelView == "trainer" ? _panelTrainerSession : null;
                string returnSession = _trainerReturnSession;
                QueueTrainerCleanupLocked(IsOpaque(closingSession) ? closingSession : returnSession, false);
                _panelInstanceId = null;
                _panelView = "manage";
                _panelTrainerSession = null;
                _trainerReturnSession = null;
                _preserveTrainerForNextManage = false;
                _panelCanReturnCharacterBuild = false;
                _nextPanelInstanceId = null;
                _nextPanelCanReturnCharacterBuild = false;
                _nextPanelView = null;
                _nextPanelTrainerSession = null;
                CancelReadsForPanelLocked(panelInstanceId);
                // 学习预览 token 只属于当前面板会话；关闭后不得跨会话复用。
                _learnTokens.Clear();
                _lastClosedPanelInstanceId = panelInstanceId;
                startCleanup = _writeState == "idle";
                startBackgroundReconcile = _writeState == "needs_reconcile";
            }
            if (startBackgroundReconcile) TryStartBackgroundReconcile();
            else if (startCleanup) TryStartTrainerCleanup();
            return true;
        }

        public bool HandleAuthoritativePanelClosed(string panelInstanceId)
        {
            lock (_lock)
                if (IsOpaque(panelInstanceId)
                    && string.Equals(_lastClosedPanelInstanceId, panelInstanceId, StringComparison.Ordinal)) return true;
            BindPanelInstance(panelInstanceId);
            return HandlePanelClosed(panelInstanceId);
        }

        public void OnSocketReconnected()
        {
            lock (_lock)
            {
                CancelCleanupRetryLocked();
                CancelBackgroundReconcileRetryLocked();
                if (_cleanupQueue.Count > 0) _cleanupQueue.Peek().AutoRetryCount = 0;
                _backgroundReconcileRetryCount = 0;
            }
            TryStartBackgroundReconcile();
            TryStartTrainerCleanup();
        }

        public void ClearPending()
        {
            lock (_lock)
            {
                bool lostWrite = false;
                string disconnectedSession = _panelView == "trainer" ? _panelTrainerSession : null;
                string pendingSession = _nextPanelView == "trainer" ? _nextPanelTrainerSession : null;
                string returnSession = _trainerReturnSession;
                CleanupIntent interruptedCleanup = _cleanupInFlight;
                _cleanupInFlight = null;
                foreach (PendingRequest entry in _pending.Values)
                {
                    lostWrite |= entry.IsWrite;
                    if (!entry.IsCleanup)
                    {
                        _activeCallIds.Remove(entry.WebCallId);
                        RememberRecentLocked(entry.WebCallId, entry.IsWrite, entry.WriteEpoch);
                    }
                }
                foreach (Timer timer in _timers.Values) timer.Dispose();
                _timers.Clear();
                CancelCleanupRetryLocked();
                CancelBackgroundReconcileRetryLocked();
                _pending.Clear();
                if (_queuedReconcile != null) CompleteQueuedReconcileLocked(_queuedReconcile);
                _queuedReconcile = null;
                _activeWriteCallId = null;
                if (lostWrite || _writeState == "write_pending")
                {
                    _writeState = "needs_reconcile";
                    EnsureReconcileWatchdogLocked();
                }
                if (interruptedCleanup != null)
                    RequeueCleanupIntentLocked(interruptedCleanup);
                MergeDisconnectedCleanupSessionLocked(disconnectedSession);
                MergeDisconnectedCleanupSessionLocked(pendingSession);
                MergeDisconnectedCleanupSessionLocked(returnSession);
                // No capability survived locally, but Flash may still retain one after the socket
                // break. A global cleanup is the only safe recovery in that fully unknown case.
                if (_cleanupQueue.Count == 0) QueueTrainerCleanupLocked(null, false);
                _panelInstanceId = null;
                _panelView = "manage";
                _panelTrainerSession = null;
                _trainerReturnSession = null;
                _preserveTrainerForNextManage = false;
                _panelCanReturnCharacterBuild = false;
                _nextPanelInstanceId = null;
                _nextPanelCanReturnCharacterBuild = false;
                _nextPanelView = null;
                _nextPanelTrainerSession = null;
                _learnTokens.Clear();
            }
        }

        public void Dispose()
        {
            _disposed = true;
            ClearPending();
            lock (_lock) CancelReconcileWatchdogLocked();
        }

        private void DispatchToFlash(PendingRequest entry)
        {
            lock (_lock)
            {
                entry.FlashCallId = ++_seq;
                _pending[entry.FlashCallId] = entry;
            }
            if (entry.IsWrite)
                LogManager.Log("event=skill_write_started callId=" + entry.WebCallId + " epoch=" + entry.WriteEpoch
                    + " cmd=" + entry.WebCmd);
            if (entry.IsReconcile)
                LogManager.Log("event=skill_reconcile_started epoch=" + entry.WriteEpoch
                    + " background=" + entry.IsBackgroundReconcile.ToString().ToLowerInvariant()
                    + " view=" + entry.ExpectedView);
            Timer timer = new Timer(delegate { HandleTimeout(entry.FlashCallId); }, null, _timeoutMs, Timeout.Infinite);
            lock (_lock)
            {
                if (_pending.ContainsKey(entry.FlashCallId)) _timers[entry.FlashCallId] = timer;
                else timer.Dispose();
            }
            JObject flash = PanelBridge.BuildFlashCommand(entry.FlashAction, entry.FlashCallId, entry.NormalizedPayload);
            flash["panelInstanceId"] = entry.PanelInstanceId;
            flash["writeEpoch"] = entry.WriteEpoch;
            flash["view"] = entry.ExpectedView;
            if (entry.ExpectedView == "trainer") flash["trainerSession"] = entry.ExpectedTrainerSession;
            string json = flash.ToString(Formatting.None);
            if (!entry.IsBackgroundReconcile && !entry.IsCleanup)
            {
                LogManager.Log(AuthorityLogFormatter.FormatAuthorityFlashCallBound(
                    "SkillTask", entry.WebCallId, entry.FlashCallId, "skills",
                    entry.PanelInstanceId, entry.WebCmd, entry.FlashAction));
            }
            LogManager.Log(AuthorityLogFormatter.FormatFlashCommand(
                "SkillTask", flash));
            if (!_trySend(json + "\0")) HandleTransportFailure(entry.FlashCallId, "disconnected");
        }

        private void HandleTimeout(int fid) { HandleTransportFailure(fid, "timeout"); }

        private void HandleTransportFailure(int fid, string error)
        {
            if (_disposed) return;
            PendingRequest entry;
            PendingRequest queued = null;
            bool notify = false;
            bool scheduleCleanupRetry = false;
            bool scheduleBackgroundRetry = false;
            bool startBackgroundReconcile = false;
            lock (_lock)
            {
                if (!_pending.TryGetValue(fid, out entry)) return;
                CompletePendingLocked(entry);
                if (entry.IsCleanup)
                {
                    CleanupIntent intent = _cleanupInFlight ?? new CleanupIntent
                    {
                        Generation = entry.CleanupGeneration,
                        TrainerSession = entry.ExpectedTrainerSession
                    };
                    _cleanupInFlight = null;
                    if (error == "timeout" && intent.AutoRetryCount < MaxCleanupAutoRetries)
                    {
                        intent.AutoRetryCount++;
                        scheduleCleanupRetry = true;
                    }
                    RequeueCleanupIntentLocked(intent);
                }
                else if (entry.IsWrite)
                {
                    _activeWriteCallId = null;
                    _writeState = "needs_reconcile";
                    EnsureReconcileWatchdogLocked();
                    if (_queuedReconcile != null)
                    {
                        queued = _queuedReconcile;
                        _queuedReconcile = null;
                        queued.WriteEpoch = _writeEpoch;
                    }
                    startBackgroundReconcile = _panelInstanceId == null && queued == null;
                }
                else if (entry.IsBackgroundReconcile)
                {
                    _writeState = "needs_reconcile";
                    EnsureReconcileWatchdogLocked();
                    if (error == "timeout" && _backgroundReconcileRetryCount < MaxBackgroundReconcileAutoRetries)
                    {
                        _backgroundReconcileRetryCount++;
                        scheduleBackgroundRetry = true;
                    }
                }
                else if (entry.IsReconcile)
                {
                    _writeState = "needs_reconcile";
                    EnsureReconcileWatchdogLocked();
                    startBackgroundReconcile = _panelInstanceId == null;
                }
                else notify = _writeState == "idle";
            }
            if (entry.IsCleanup)
            {
                if (scheduleCleanupRetry)
                {
                    LogManager.Log("[SkillTask] trainer cleanup retained after " + error
                        + "; delayed retry " + entry.CleanupGeneration);
                    ScheduleCleanupRetry();
                }
                else LogManager.Log("[SkillTask] trainer cleanup retry budget exhausted after " + error
                    + "; waiting for reconnect/coordinator event");
                return;
            }
            if (entry.IsBackgroundReconcile)
            {
                LogManager.Log("event=skill_reconcile_retry_wait epoch=" + entry.WriteEpoch + " reason=" + error);
                if (scheduleBackgroundRetry) ScheduleBackgroundReconcileRetry();
                return;
            }
            if (entry.IsWrite)
                LogManager.Log("event=skill_write_unknown callId=" + entry.WebCallId + " epoch=" + entry.WriteEpoch
                    + " reason=" + error);
            RespondError(entry.WebCallId, entry.WebCmd, error, entry.IsWrite || entry.IsReconcile,
                entry.PanelInstanceId, entry.WriteEpoch);
            if (queued != null) DispatchToFlash(queued);
            if (startBackgroundReconcile) TryStartBackgroundReconcile();
            if (notify) NotifyCoordinatorSettled();
        }

        private void CompletePendingLocked(PendingRequest entry)
        {
            _pending.Remove(entry.FlashCallId);
            Timer timer;
            if (_timers.TryGetValue(entry.FlashCallId, out timer))
            { timer.Dispose(); _timers.Remove(entry.FlashCallId); }
            if (entry.IsCleanup) return;
            _activeCallIds.Remove(entry.WebCallId);
            RememberRecentLocked(entry.WebCallId, entry.IsWrite, entry.WriteEpoch);
        }

        private void CompleteQueuedReconcileLocked(PendingRequest entry)
        {
            _activeCallIds.Remove(entry.WebCallId);
            RememberRecentLocked(entry.WebCallId, false, entry.WriteEpoch);
        }

        private void CancelReadsForPanelLocked(string panelInstanceId)
        {
            foreach (PendingRequest entry in _pending.Values.Where(p => !p.IsWrite
                && string.Equals(p.PanelInstanceId, panelInstanceId, StringComparison.Ordinal)).ToArray())
                CompletePendingLocked(entry);
            if (_queuedReconcile != null && string.Equals(_queuedReconcile.PanelInstanceId, panelInstanceId, StringComparison.Ordinal))
            {
                CompleteQueuedReconcileLocked(_queuedReconcile);
                _queuedReconcile = null;
            }
        }

        private bool HasCleanupLocked()
        {
            return _cleanupInFlight != null || _cleanupQueue.Count > 0;
        }

        private void QueueTrainerCleanupLocked(string trainerSession, bool replaceQueued)
        {
            if (_cleanupInFlight != null
                && string.Equals(_cleanupInFlight.TrainerSession, trainerSession, StringComparison.Ordinal)) return;
            if (_cleanupQueue.Count > 0)
            {
                CleanupIntent queued = _cleanupQueue.Peek();
                // A queued force cleanup subsumes every scoped cleanup. Never replace it with a
                // later candidate session, otherwise an active session whose ack was lost can leak.
                if (queued.TrainerSession == null) return;
                if (string.Equals(queued.TrainerSession, trainerSession, StringComparison.Ordinal)) return;
                if (_cleanupInFlight == null && trainerSession != null)
                {
                    // No scoped cleanup has reached Flash yet, so both distinct capabilities remain
                    // plausible (for example active A queued behind a write, then candidate B arrives).
                    // One global cleanup is the only bounded intent that revokes both without guessing.
                    _cleanupQueue.Clear();
                    _cleanupQueue.Enqueue(new CleanupIntent
                    {
                        Generation = ++_cleanupGeneration,
                        TrainerSession = null
                    });
                    return;
                }
                if (!replaceQueued) return;
                _cleanupQueue.Clear();
            }
            else if (!replaceQueued && trainerSession == null && _cleanupInFlight != null) return;
            _cleanupQueue.Enqueue(new CleanupIntent
            {
                Generation = ++_cleanupGeneration,
                TrainerSession = trainerSession
            });
        }

        private void RequeueCleanupIntentLocked(CleanupIntent intent)
        {
            if (intent == null) return;
            if (_cleanupQueue.Count > 0)
            {
                // AS2 可同时持 active A + candidate B。A 的 ack 丢失且 B 已排队时，不能丢 A；
                // 收敛为一次 force cleanup，容量仍为 1，并在 ack 前持续关闭 trainer gate。
                _cleanupQueue.Clear();
                _cleanupQueue.Enqueue(new CleanupIntent
                {
                    Generation = ++_cleanupGeneration,
                    TrainerSession = null,
                    AutoRetryCount = intent.AutoRetryCount
                });
                return;
            }
            _cleanupQueue.Enqueue(intent);
        }

        private void MergeDisconnectedCleanupSessionLocked(string trainerSession)
        {
            if (!IsOpaque(trainerSession)) return;
            if (_cleanupQueue.Count == 0)
            {
                _cleanupQueue.Enqueue(new CleanupIntent
                {
                    Generation = ++_cleanupGeneration,
                    TrainerSession = trainerSession
                });
                return;
            }

            CleanupIntent queued = _cleanupQueue.Peek();
            if (queued.TrainerSession == null
                || string.Equals(queued.TrainerSession, trainerSession, StringComparison.Ordinal)) return;

            // The broken connection leaves both distinct capabilities plausible. Collapse them to
            // one global cleanup instead of selecting either session and leaking the other.
            _cleanupQueue.Clear();
            _cleanupQueue.Enqueue(new CleanupIntent
            {
                Generation = ++_cleanupGeneration,
                TrainerSession = null
            });
        }

        private void TryStartBackgroundReconcile()
        {
            PendingRequest entry;
            lock (_lock)
            {
                if (_disposed || _writeState != "needs_reconcile" || _panelInstanceId != null
                    || _backgroundReconcileRetryTimer != null || !_isClientReady()
                    || _pending.Values.Any(p => p.IsBackgroundReconcile) || !IsCallId(_lastWriteCallId)) return;

                string view = _backgroundReconcileUseManage ? "manage" : _lastWriteView;
                string trainerSession = view == "trainer" ? _lastWriteTrainerSession : null;
                if (view != "trainer" || !IsOpaque(trainerSession))
                {
                    view = "manage";
                    trainerSession = null;
                }
                var payload = new JObject { ["v"] = 1, ["view"] = view };
                if (trainerSession != null) payload["trainerSession"] = trainerSession;
                entry = new PendingRequest
                {
                    WebCmd = "snapshot",
                    FlashAction = "skillSnapshot",
                    IsReconcile = true,
                    IsBackgroundReconcile = true,
                    WriteEpoch = _writeEpoch,
                    ReconcileTargetEpoch = _writeEpoch,
                    ReconcileAfterCallId = _lastWriteCallId,
                    ExpectedView = view,
                    ExpectedTrainerSession = trainerSession,
                    NormalizedPayload = payload
                };
            }
            DispatchToFlash(entry);
        }

        private void ScheduleBackgroundReconcileRetry()
        {
            lock (_lock)
            {
                if (_disposed || _backgroundReconcileRetryTimer != null || _writeState != "needs_reconcile") return;
                Timer timer = null;
                timer = new Timer(delegate
                {
                    lock (_lock)
                    {
                        if (!ReferenceEquals(_backgroundReconcileRetryTimer, timer)) return;
                        _backgroundReconcileRetryTimer = null;
                    }
                    timer.Dispose();
                    TryStartBackgroundReconcile();
                }, null, _timeoutMs, Timeout.Infinite);
                _backgroundReconcileRetryTimer = timer;
            }
        }

        private void CancelBackgroundReconcileRetryLocked()
        {
            if (_backgroundReconcileRetryTimer == null) return;
            _backgroundReconcileRetryTimer.Dispose();
            _backgroundReconcileRetryTimer = null;
        }

        private void EnsureReconcileWatchdogLocked()
        {
            if (_disposed || _writeState != "needs_reconcile" || _reconcileStuckEpoch == _writeEpoch
                || _reconcileStuckTimer != null) return;
            int epoch = _writeEpoch;
            string callId = _lastWriteCallId;
            Timer timer = null;
            timer = new Timer(delegate
            {
                bool stuck;
                lock (_lock)
                {
                    if (!ReferenceEquals(_reconcileStuckTimer, timer)) return;
                    _reconcileStuckTimer = null;
                    stuck = !_disposed && _writeState == "needs_reconcile" && _writeEpoch == epoch;
                    if (stuck) _reconcileStuckEpoch = epoch;
                }
                timer.Dispose();
                if (stuck) LogManager.Log("event=skill_reconcile_stuck epoch=" + epoch + " callId=" + callId);
            }, null, ReconcileStuckMs, Timeout.Infinite);
            _reconcileStuckTimer = timer;
        }

        private void CancelReconcileWatchdogLocked()
        {
            if (_reconcileStuckTimer == null) return;
            _reconcileStuckTimer.Dispose();
            _reconcileStuckTimer = null;
        }

        private void TryStartTrainerCleanup()
        {
            PendingRequest entry;
            lock (_lock)
            {
                if (_disposed || _writeState != "idle" || _cleanupInFlight != null || _cleanupRetryTimer != null
                    || _cleanupQueue.Count == 0 || !_isClientReady()) return;
                CleanupIntent intent = _cleanupQueue.Dequeue();
                _cleanupInFlight = intent;
                var payload = new JObject { ["v"] = 1 };
                if (intent.TrainerSession != null) payload["trainerSession"] = intent.TrainerSession;
                entry = new PendingRequest
                {
                    FlashCallId = ++_seq,
                    FlashAction = "skillPanelClose",
                    IsCleanup = true,
                    CleanupGeneration = intent.Generation,
                    ExpectedTrainerSession = intent.TrainerSession,
                    NormalizedPayload = payload
                };
                _pending[entry.FlashCallId] = entry;
            }
            Timer timer = new Timer(delegate { HandleTimeout(entry.FlashCallId); }, null, _timeoutMs, Timeout.Infinite);
            lock (_lock)
            {
                if (_pending.ContainsKey(entry.FlashCallId)) _timers[entry.FlashCallId] = timer;
                else timer.Dispose();
            }
            JObject cleanup = PanelBridge.BuildFlashCommand(entry.FlashAction, entry.FlashCallId, entry.NormalizedPayload);
            string json = cleanup.ToString(Formatting.None);
            LogManager.Log(AuthorityLogFormatter.FormatFlashCommand(
                "SkillTask", cleanup));
            try
            {
                if (!_trySend(json + "\0")) HandleTransportFailure(entry.FlashCallId, "disconnected");
            }
            catch { HandleTransportFailure(entry.FlashCallId, "disconnected"); }
        }

        private void HandleCleanupFlashResponse(PendingRequest entry, JObject msg)
        {
            bool valid = IsValidCleanupAck(msg);
            bool scheduleCleanupRetry = false;
            lock (_lock)
            {
                PendingRequest current;
                if (!_pending.TryGetValue(entry.FlashCallId, out current) || !current.IsCleanup) return;
                CompletePendingLocked(current);
                CleanupIntent intent = _cleanupInFlight;
                _cleanupInFlight = null;
                if (!valid)
                {
                    intent = intent ?? new CleanupIntent
                    {
                        Generation = entry.CleanupGeneration,
                        TrainerSession = entry.ExpectedTrainerSession
                    };
                    if (intent.AutoRetryCount < MaxCleanupAutoRetries)
                    {
                        intent.AutoRetryCount++;
                        scheduleCleanupRetry = true;
                    }
                    RequeueCleanupIntentLocked(intent);
                }
            }
            if (!valid)
            {
                if (scheduleCleanupRetry)
                {
                    LogManager.Log("[SkillTask] malformed trainer cleanup ack retained for delayed retry");
                    ScheduleCleanupRetry();
                }
                else LogManager.Log("[SkillTask] malformed trainer cleanup ack exhausted retry budget");
                return;
            }
            NotifyCoordinatorSettled();
        }

        private void ScheduleCleanupRetry()
        {
            lock (_lock)
            {
                if (_disposed || _cleanupRetryTimer != null || _cleanupQueue.Count == 0) return;
                Timer timer = null;
                timer = new Timer(delegate
                {
                    lock (_lock)
                    {
                        if (!ReferenceEquals(_cleanupRetryTimer, timer)) return;
                        _cleanupRetryTimer = null;
                    }
                    timer.Dispose();
                    TryStartTrainerCleanup();
                }, null, _timeoutMs, Timeout.Infinite);
                _cleanupRetryTimer = timer;
            }
        }

        private void CancelCleanupRetryLocked()
        {
            if (_cleanupRetryTimer == null) return;
            _cleanupRetryTimer.Dispose();
            _cleanupRetryTimer = null;
        }

        private static bool IsValidCleanupAck(JObject msg)
        {
            return IsExactObject(msg, Set("task", "callId", "success", "v", "changed", "revision"))
                && IsExactString(msg["task"], "skill_response") && msg.Value<bool?>("success") == true
                && HasVersion(msg) && msg.Value<bool?>("changed") == false
                && IsInteger(msg["revision"], 0, int.MaxValue);
        }

        private void RejectAndRemember(string callId, string cmd, string error)
        {
            string instance;
            int epoch;
            lock (_lock)
            {
                PruneRecentLocked();
                if (_activeCallIds.Contains(callId) || _recent.ContainsKey(callId)) return;
                RememberRecentLocked(callId, false, _writeEpoch);
                instance = _panelInstanceId;
                epoch = _writeEpoch;
            }
            RespondError(callId, cmd, error, false, instance, epoch);
        }

        private void StampAndPost(JObject web, PendingRequest entry)
        {
            web.Remove("task");
            web["type"] = "panel_resp";
            web["panel"] = "skills";
            web["domain"] = "skills";
            web["cmd"] = entry.WebCmd;
            web["callId"] = entry.WebCallId;
            web["panelInstanceId"] = entry.PanelInstanceId;
            web["writeEpoch"] = entry.WriteEpoch;
            PostToWeb(web.ToString(Formatting.None));
        }

        private void RespondError(string callId, string cmd, string error, bool requiresReconcile,
            string panelInstanceId, int writeEpoch)
        {
            JObject response = new JObject
            {
                ["type"] = "panel_resp", ["panel"] = "skills", ["domain"] = "skills",
                ["cmd"] = cmd ?? "", ["callId"] = callId ?? "", ["success"] = false,
                ["error"] = error, ["panelInstanceId"] = panelInstanceId, ["writeEpoch"] = writeEpoch
            };
            if (requiresReconcile) response["requiresReconcile"] = true;
            PostToWeb(response.ToString(Formatting.None));
        }

        private void PostToWeb(string json)
        {
            if (_invokeOnUI != null) _invokeOnUI(delegate { if (_postToWeb != null) _postToWeb(json); });
            else if (_postToWeb != null) _postToWeb(json);
        }

        private void NotifyCoordinatorSettled()
        {
            TryStartTrainerCleanup();
            lock (_lock) if (_writeState != "idle" || HasCleanupLocked()) return;
            Action callback = _onCoordinatorSettled;
            if (callback == null) return;
            if (_invokeOnUI != null) _invokeOnUI(callback); else callback();
        }

        private int CurrentEpoch() { lock (_lock) return _writeEpoch; }

        private void RememberRecentLocked(string callId, bool isWrite, int epoch)
        {
            if (string.IsNullOrEmpty(callId) || _recent.ContainsKey(callId)) return;
            _recent[callId] = new RecentCall
            {
                CallId = callId, IsWrite = isWrite, WriteEpoch = epoch,
                ExpiresUtc = DateTime.UtcNow.Add(RecentLifetime)
            };
            _recentOrder.Enqueue(callId);
            PruneRecentLocked();
        }

        private void PruneRecentLocked()
        {
            DateTime now = DateTime.UtcNow;
            while (_recentOrder.Count > 0)
            {
                string id = _recentOrder.Peek();
                RecentCall entry;
                if (!_recent.TryGetValue(id, out entry)) { _recentOrder.Dequeue(); continue; }
                if (_recent.Count + _activeCallIds.Count <= MaxTrackedCallIds && entry.ExpiresUtc > now) break;
                _recentOrder.Dequeue();
                _recent.Remove(id);
            }
        }

        private static bool TryResolveCommand(string cmd, out string action, out bool isWrite)
        {
            isWrite = false;
            switch (cmd)
            {
                case "snapshot": action = "skillSnapshot"; return true;
                case "learnPreview": action = "skillLearnPreview"; return true;
                case "learnCommit": action = "skillLearnCommit"; isWrite = true; return true;
                case "equip": action = "skillEquip"; isWrite = true; return true;
                case "unequip": action = "skillUnequip"; isWrite = true; return true;
                case "moveSlot": action = "skillMoveSlot"; isWrite = true; return true;
                case "setPassive": action = "skillSetPassive"; isWrite = true; return true;
                case "reorder": action = "skillReorder"; isWrite = true; return true;
                default: action = null; return false;
            }
        }

        private static JObject SanitizeFlashResponse(JObject value)
        {
            if (value == null) return null;
            JObject sanitized = (JObject)value.DeepClone();
            sanitized.Remove("type");
            sanitized.Remove("panel");
            sanitized.Remove("domain");
            sanitized.Remove("cmd");
            sanitized.Remove("panelInstanceId");
            sanitized.Remove("writeEpoch");
            return sanitized;
        }

        private static bool TryNormalizePayload(string cmd, JObject payload, out JObject normalized, out bool isReconcile)
        {
            normalized = null;
            isReconcile = false;
            if (payload == null || !HasVersion(payload)) return false;
            JObject result = new JObject { ["v"] = 1 };
            int number;
            string skillKey;
            if (cmd == "snapshot")
            {
                string view = ReadString(payload["view"]);
                if (view != "manage" && view != "trainer") return false;
                bool hasReconcile = payload["reconcileId"] != null || payload["reconcileAfterCallId"] != null;
                HashSet<string> keys = view == "trainer"
                    ? (hasReconcile ? Set("v", "view", "trainerSession", "reconcileId", "reconcileAfterCallId") : Set("v", "view", "trainerSession"))
                    : (hasReconcile ? Set("v", "view", "reconcileId", "reconcileAfterCallId") : Set("v", "view"));
                if (!IsExactObject(payload, keys)) return false;
                result["view"] = view;
                if (view == "trainer")
                {
                    string session = ReadString(payload["trainerSession"]);
                    if (!IsOpaque(session)) return false;
                    result["trainerSession"] = session;
                }
                if (hasReconcile)
                {
                    string reconcileId = ReadString(payload["reconcileId"]);
                    string after = ReadString(payload["reconcileAfterCallId"]);
                    if (!IsOpaque(reconcileId) || !IsCallId(after)) return false;
                    result["reconcileId"] = reconcileId;
                    result["reconcileAfterCallId"] = after;
                    isReconcile = true;
                }
            }
            else if (cmd == "learnPreview")
            {
                if (!IsExactObject(payload, Set("v", "skillKey", "desiredLevel", "trainerSession", "expectedRevision"))) return false;
                skillKey = ReadString(payload["skillKey"]);
                string session = ReadString(payload["trainerSession"]);
                if (!IsSkillKey(skillKey) || !IsOpaque(session)
                    || !TryReadInteger(payload["desiredLevel"], 1, 100, out number)) return false;
                result["skillKey"] = skillKey; result["desiredLevel"] = number; result["trainerSession"] = session;
                if (!CopyInteger(payload, result, "expectedRevision", 0, int.MaxValue)) return false;
            }
            else if (cmd == "learnCommit")
            {
                if (!IsExactObject(payload, Set("v", "expectedLearnToken"))) return false;
                string token = ReadString(payload["expectedLearnToken"]);
                if (!IsOpaque(token)) return false;
                result["expectedLearnToken"] = token;
            }
            else if (cmd == "equip")
            {
                if (!IsExactObject(payload, Set("v", "skillKey", "slot", "expectedRevision"))) return false;
                skillKey = ReadString(payload["skillKey"]);
                if (!IsSkillKey(skillKey) || !TryReadInteger(payload["slot"], 1, 12, out number)) return false;
                result["skillKey"] = skillKey; result["slot"] = number;
                if (!CopyInteger(payload, result, "expectedRevision", 0, int.MaxValue)) return false;
            }
            else if (cmd == "unequip")
            {
                if (!IsExactObject(payload, Set("v", "slot", "expectedRevision"))
                    || !CopyInteger(payload, result, "slot", 1, 12)
                    || !CopyInteger(payload, result, "expectedRevision", 0, int.MaxValue)) return false;
            }
            else if (cmd == "moveSlot")
            {
                if (!IsExactObject(payload, Set("v", "sourceSlot", "targetSlot", "expectedRevision"))
                    || !CopyInteger(payload, result, "sourceSlot", 1, 12)
                    || !CopyInteger(payload, result, "targetSlot", 1, 12)
                    || !CopyInteger(payload, result, "expectedRevision", 0, int.MaxValue)) return false;
            }
            else if (cmd == "setPassive")
            {
                if (!IsExactObject(payload, Set("v", "skillKey", "enabled", "expectedRevision"))) return false;
                skillKey = ReadString(payload["skillKey"]);
                if (!IsSkillKey(skillKey) || payload["enabled"] == null || payload["enabled"].Type != JTokenType.Boolean) return false;
                result["skillKey"] = skillKey; result["enabled"] = payload.Value<bool>("enabled");
                if (!CopyInteger(payload, result, "expectedRevision", 0, int.MaxValue)) return false;
            }
            else if (cmd == "reorder")
            {
                if (!IsExactObject(payload, Set("v", "skillKey", "targetIndex", "expectedRevision"))) return false;
                skillKey = ReadString(payload["skillKey"]);
                if (!IsSkillKey(skillKey)) return false;
                result["skillKey"] = skillKey;
                if (!CopyInteger(payload, result, "targetIndex", 0, 79)
                    || !CopyInteger(payload, result, "expectedRevision", 0, int.MaxValue)) return false;
            }
            else return false;
            normalized = result;
            return true;
        }

        private static bool IsValidResponse(JObject msg, PendingRequest entry)
        {
            if (msg == null || msg["task"] == null || msg["task"].Type != JTokenType.String
                || msg.Value<string>("task") != "skill_response"
                || msg["success"] == null || msg["success"].Type != JTokenType.Boolean) return false;
            if (!msg.Value<bool>("success"))
            {
                return IsExactObject(msg, Set("task", "callId", "success", "v", "error", "revision"))
                    && HasVersion(msg) && IsSafeText(ReadString(msg["error"]), 1, 64, false)
                    && IsInteger(msg["revision"], 0, int.MaxValue);
            }
            if (entry.WebCmd == "snapshot")
                return IsSnapshot(msg, true, entry.ExpectedView, entry.ExpectedTrainerSession);
            if (entry.WebCmd == "learnPreview") return IsPreview(msg, entry);
            return IsWriteSuccess(msg, entry);
        }

        private static bool IsDefinitiveWriteResponse(JObject msg)
        {
            if (msg == null || msg["success"] == null || msg["success"].Type != JTokenType.Boolean) return false;
            if (msg.Value<bool>("success")) return true;
            return DefinitiveWriteErrors.Contains(ReadString(msg["error"]));
        }

        private static bool IsPreview(JObject msg, PendingRequest entry)
        {
            if (!IsExactObject(msg, Set("task", "callId", "success", "v", "trainerSession", "skillKey",
                "currentLevel", "desiredLevel", "cost", "revision", "canCommit", "blockingError", "learnToken"))) return false;
            int current;
            int desired;
            int cost;
            int revision;
            if (!HasVersion(msg) || !IsOpaque(ReadString(msg["trainerSession"])) || !IsSkillKey(ReadString(msg["skillKey"]))
                || !TryReadInteger(msg["currentLevel"], 0, 100, out current)
                || !TryReadInteger(msg["desiredLevel"], 1, 100, out desired)
                || !TryReadInteger(msg["cost"], 0, int.MaxValue, out cost)
                || !TryReadInteger(msg["revision"], 0, int.MaxValue, out revision)
                || msg["canCommit"].Type != JTokenType.Boolean) return false;
            if (msg.Value<string>("trainerSession") != entry.NormalizedPayload.Value<string>("trainerSession")
                || msg.Value<string>("skillKey") != entry.NormalizedPayload.Value<string>("skillKey")
                || desired != entry.NormalizedPayload.Value<int>("desiredLevel")
                || revision != entry.NormalizedPayload.Value<int>("expectedRevision")) return false;
            bool canCommit = msg.Value<bool>("canCommit");
            string token = ReadString(msg["learnToken"]);
            string blocking = ReadString(msg["blockingError"]);
            return canCommit ? IsOpaque(token) && msg["blockingError"].Type == JTokenType.Null
                : msg["learnToken"].Type == JTokenType.Null && IsSafeText(blocking, 1, 64, false);
        }

        private static bool IsWriteSuccess(JObject msg, PendingRequest entry)
        {
            if (!IsExactObject(msg, Set("task", "callId", "success", "v", "changed", "revision", "snapshot"))
                || !HasVersion(msg) || msg["changed"].Type != JTokenType.Boolean
                || !IsInteger(msg["revision"], 0, int.MaxValue)
                || !IsSnapshot(msg["snapshot"] as JObject, false, entry.ExpectedView, entry.ExpectedTrainerSession)) return false;
            JObject snapshot = (JObject)msg["snapshot"];
            if (snapshot.Value<int>("revision") != msg.Value<int>("revision")) return false;
            int expectedRevision = entry.ExpectedRevision >= 0 ? entry.ExpectedRevision
                : (entry.NormalizedPayload["expectedRevision"] != null ? entry.NormalizedPayload.Value<int>("expectedRevision") : -1);
            if (!msg.Value<bool>("changed") && expectedRevision >= 0 && msg.Value<int>("revision") != expectedRevision) return false;
            if (msg.Value<bool>("changed") && expectedRevision >= 0 && msg.Value<int>("revision") != expectedRevision + 1) return false;
            return HasExpectedEffect(entry, snapshot, msg.Value<bool>("changed"));
        }

        private static bool HasExpectedEffect(PendingRequest entry, JObject snapshot, bool changed)
        {
            JArray loadout = (JArray)snapshot["loadout"];
            JArray learned = (JArray)snapshot["learned"];
            string key = entry.NormalizedPayload.Value<string>("skillKey");
            if (entry.WebCmd == "learnCommit")
            {
                if (!changed) return false;
                JObject learnedCommit = learned.OfType<JObject>().FirstOrDefault(x => x.Value<string>("skillKey") == entry.ExpectedSkillKey);
                return learnedCommit != null && learnedCommit.Value<int>("level") == entry.ExpectedDesiredLevel;
            }
            if (entry.WebCmd == "equip")
            {
                int slot = entry.NormalizedPayload.Value<int>("slot");
                JObject row = loadout.OfType<JObject>().FirstOrDefault(x => x.Value<int>("slot") == slot);
                return row != null && row.Value<string>("skillKey") == key;
            }
            if (entry.WebCmd == "unequip")
            {
                int slot = entry.NormalizedPayload.Value<int>("slot");
                JObject row = loadout.OfType<JObject>().FirstOrDefault(x => x.Value<int>("slot") == slot);
                return row != null && row["skillKey"].Type == JTokenType.Null;
            }
            JObject learnedRow = learned.OfType<JObject>().FirstOrDefault(x => x.Value<string>("skillKey") == key);
            if (entry.WebCmd == "setPassive")
                return learnedRow != null && learnedRow.Value<bool>("enabled") == entry.NormalizedPayload.Value<bool>("enabled");
            if (entry.WebCmd == "reorder")
                return learnedRow != null && learnedRow.Value<int>("orderIndex") == entry.NormalizedPayload.Value<int>("targetIndex");
            return true;
        }

        private static bool IsSnapshot(JObject value, bool routed, string expectedView, string expectedTrainerSession)
        {
            if (value == null) return false;
            HashSet<string> keys = routed
                ? Set("task", "callId", "success", "v", "revision", "view", "player", "learned", "loadout", "trainer", "diagnostics")
                : Set("success", "v", "revision", "view", "player", "learned", "loadout", "trainer", "diagnostics");
            if (!IsExactObject(value, keys) || value.Value<bool?>("success") != true || !HasVersion(value)
                || !IsInteger(value["revision"], 0, int.MaxValue)) return false;
            string view = ReadString(value["view"]);
            if (view != "manage" && view != "trainer") return false;
            if (!string.IsNullOrEmpty(expectedView) && view != expectedView) return false;
            JObject player = value["player"] as JObject;
            if (!IsExactObject(player, Set("level", "skillPoints", "easyMode"))
                || !IsInteger(player["level"], 0, 9999) || !IsInteger(player["skillPoints"], 0, int.MaxValue)
                || player["easyMode"].Type != JTokenType.Boolean) return false;
            JArray learned = value["learned"] as JArray;
            JArray loadout = value["loadout"] as JArray;
            JArray diagnostics = value["diagnostics"] as JArray;
            if (learned == null || learned.Count > 80 || loadout == null || loadout.Count != 12
                || diagnostics == null || diagnostics.Count > 32) return false;
            if (learned.Any(x => !IsLearnedEntry(x as JObject)) || loadout.Any(x => !IsLoadoutEntry(x as JObject))) return false;
            var learnedKeys = new HashSet<string>(StringComparer.Ordinal);
            foreach (JObject row in learned) if (!learnedKeys.Add(row.Value<string>("skillKey"))) return false;
            var slots = new HashSet<int>();
            foreach (JObject row in loadout) if (!slots.Add(row.Value<int>("slot"))) return false;
            if (slots.Count != 12 || slots.Min() != 1 || slots.Max() != 12) return false;
            if (diagnostics.Any(x => !IsDiagnostic(x as JObject))) return false;
            if (view == "manage") return value["trainer"].Type == JTokenType.Null;
            JObject trainer = value["trainer"] as JObject;
            return IsTrainer(trainer)
                && (string.IsNullOrEmpty(expectedTrainerSession)
                    || trainer.Value<string>("session") == expectedTrainerSession);
        }

        private static bool IsLearnedEntry(JObject row)
        {
            if (!IsExactObject(row, Set("skillKey", "orderIndex", "level", "maxLevel", "type", "passive", "equippable",
                "enabled", "equippedSlots", "unlockLevel", "unlockSP", "upgradeSP", "mp", "cooldownMs", "iconKey",
                "description", "stateHealth", "writeBlocked"))) return false;
            JArray slots = row["equippedSlots"] as JArray;
            if (slots == null || slots.Count > 12 || slots.Any(x => !IsInteger(x, 1, 12))) return false;
            var uniqueSlots = new HashSet<int>();
            foreach (JToken slot in slots) if (!uniqueSlots.Add(slot.Value<int>())) return false;
            return IsSkillKey(ReadString(row["skillKey"])) && IsInteger(row["orderIndex"], 0, 79)
                && IsInteger(row["level"], 0, 9999) && IsInteger(row["maxLevel"], 1, 100)
                && IsSafeText(ReadString(row["type"]), 1, 64, false)
                && IsBoolean(row["passive"]) && IsBoolean(row["equippable"]) && IsBoolean(row["enabled"])
                && IsInteger(row["unlockLevel"], 0, 9999) && IsInteger(row["unlockSP"], 0, int.MaxValue)
                && IsInteger(row["upgradeSP"], 0, int.MaxValue) && IsFiniteNumber(row["mp"], 0, 1000000)
                && IsInteger(row["cooldownMs"], 0, 86400000) && IsKeyText(row["iconKey"], 128)
                && IsSafeText(ReadString(row["description"]), 0, 4096, true)
                && HealthCodes.Contains(ReadString(row["stateHealth"])) && IsBoolean(row["writeBlocked"]);
        }

        private static bool IsLoadoutEntry(JObject row)
        {
            if (row == null || !IsInteger(row["slot"], 1, 12) || !IsSafeText(ReadString(row["keyLabel"]), 0, 32, false)
                || !HealthCodes.Contains(ReadString(row["stateHealth"])) || !IsBoolean(row["writeBlocked"])) return false;
            if (row["skillKey"] == null) return false;
            if (row["skillKey"].Type == JTokenType.Null)
                return IsExactObject(row, Set("slot", "skillKey", "keyLabel", "stateHealth", "writeBlocked"));
            return IsExactObject(row, Set("slot", "skillKey", "keyLabel", "level", "iconKey", "stateHealth", "writeBlocked"))
                && IsSkillKey(ReadString(row["skillKey"]))
                && (row["level"].Type == JTokenType.Null || IsInteger(row["level"], 0, 9999))
                && IsNullableKeyText(row["iconKey"], 128);
        }

        private static bool IsTrainer(JObject trainer)
        {
            if (!IsExactObject(trainer, Set("session", "entries")) || !IsOpaque(ReadString(trainer["session"]))) return false;
            JArray entries = trainer["entries"] as JArray;
            if (entries == null || entries.Count > 80 || entries.Any(x => !IsTrainerEntry(x as JObject))) return false;
            var keys = new HashSet<string>(StringComparer.Ordinal);
            foreach (JObject entry in entries) if (!keys.Add(entry.Value<string>("skillKey"))) return false;
            return true;
        }

        private static bool IsTrainerEntry(JObject row)
        {
            if (!IsExactObject(row, Set("skillKey", "currentLevel", "maxLevel", "type", "passive", "equippable",
                "unlockLevel", "unlockSP", "upgradeSP", "mp", "cooldownMs", "iconKey", "description", "stateHealth", "writeBlocked"))) return false;
            return IsSkillKey(ReadString(row["skillKey"])) && IsInteger(row["currentLevel"], 0, 100)
                && IsInteger(row["maxLevel"], 1, 100) && IsSafeText(ReadString(row["type"]), 1, 64, false)
                && IsBoolean(row["passive"]) && IsBoolean(row["equippable"])
                && IsInteger(row["unlockLevel"], 0, 9999) && IsInteger(row["unlockSP"], 0, int.MaxValue)
                && IsInteger(row["upgradeSP"], 0, int.MaxValue) && IsFiniteNumber(row["mp"], 0, 1000000)
                && IsInteger(row["cooldownMs"], 0, 86400000) && IsKeyText(row["iconKey"], 128)
                && IsSafeText(ReadString(row["description"]), 0, 4096, true)
                && HealthCodes.Contains(ReadString(row["stateHealth"])) && IsBoolean(row["writeBlocked"]);
        }

        private static bool IsDiagnostic(JObject value)
        {
            if (value == null || !DiagnosticCodes.Contains(ReadString(value["code"]))) return false;
            foreach (JProperty p in value.Properties())
            {
                if (p.Name == "code") continue;
                if (p.Name == "skillKey" && IsSkillKey(ReadString(p.Value))) continue;
                if (p.Name == "rowCount" && IsInteger(p.Value, 0, 9999)) continue;
                if (p.Name == "index" && (IsInteger(p.Value, 0, 9999)
                    || IsSafeText(ReadString(p.Value), 1, 64, false))) continue;
                if (p.Name == "message" && IsSafeText(ReadString(p.Value), 0, 512, true)) continue;
                return false;
            }
            return true;
        }

        private static bool CopyInteger(JObject source, JObject target, string name, int min, int max)
        {
            int value;
            if (!TryReadInteger(source[name], min, max, out value)) return false;
            target[name] = value;
            return true;
        }

        private void RememberLearnPreviewLocked(JObject preview)
        {
            string session = preview.Value<string>("trainerSession");
            ClearLearnTokensForSessionLocked(session);
            if (preview.Value<bool>("canCommit"))
            {
                string token = preview.Value<string>("learnToken");
                _learnTokens[token] = new LearnTokenBinding
                {
                    Token = token,
                    SkillKey = preview.Value<string>("skillKey"),
                    DesiredLevel = preview.Value<int>("desiredLevel"),
                    Revision = preview.Value<int>("revision"),
                    TrainerSession = session
                };
            }
        }

        private void ClearLearnTokensForSessionLocked(string session)
        {
            foreach (string token in _learnTokens.Where(x => x.Value.TrainerSession == session).Select(x => x.Key).ToArray())
                _learnTokens.Remove(token);
        }

        private static bool TryReadInteger(JToken token, int min, int max, out int value)
        {
            value = 0;
            if (token == null || token.Type != JTokenType.Integer) return false;
            long candidate = token.Value<long>();
            if (candidate < min || candidate > max) return false;
            value = (int)candidate;
            return true;
        }

        private static bool IsInteger(JToken token, int min, int max)
        { int ignored; return TryReadInteger(token, min, max, out ignored); }
        private static bool IsBoolean(JToken token) { return token != null && token.Type == JTokenType.Boolean; }

        private static bool IsFiniteNumber(JToken token, double min, double max)
        {
            if (token == null || (token.Type != JTokenType.Integer && token.Type != JTokenType.Float)) return false;
            double value = token.Value<double>();
            return !double.IsNaN(value) && !double.IsInfinity(value) && value >= min && value <= max;
        }

        private static bool HasVersion(JObject value) { return value != null && IsInteger(value["v"], 1, 1); }
        private static string ReadString(JToken value) { return value != null && value.Type == JTokenType.String ? value.Value<string>() : null; }
        private static bool IsCallId(string value) { return !string.IsNullOrEmpty(value) && ValidCallId.IsMatch(value); }
        private static bool IsOpaque(string value) { return !string.IsNullOrEmpty(value) && ValidOpaque.IsMatch(value); }
        private static bool IsSkillKey(string value)
        {
            return IsSafeText(value, 1, 64, false) && !char.IsWhiteSpace(value[0])
                && !char.IsWhiteSpace(value[value.Length - 1]);
        }
        private static bool IsExactString(JToken value, string expected) { return value != null && value.Type == JTokenType.String && value.Value<string>() == expected; }

        private static bool IsNullableKeyText(JToken token, int max)
        {
            if (token == null || token.Type == JTokenType.Null) return token != null;
            string value = ReadString(token);
            return IsSafeText(value, 1, max, false) && !char.IsWhiteSpace(value[0])
                && !char.IsWhiteSpace(value[value.Length - 1]);
        }

        private static bool IsKeyText(JToken token, int max)
        {
            string value = ReadString(token);
            return IsSafeText(value, 1, max, false) && !char.IsWhiteSpace(value[0])
                && !char.IsWhiteSpace(value[value.Length - 1]);
        }

        private static bool IsSafeText(string value, int min, int max, bool allowLayoutControls)
        {
            if (value == null || value.Length < min || value.Length > max) return false;
            for (int i = 0; i < value.Length; i++)
            {
                char c = value[i];
                if (c == '\0' || (c >= '\u007f' && c <= '\u009f')) return false;
                if (c < ' ' && !(allowLayoutControls && (c == '\r' || c == '\n' || c == '\t'))) return false;
            }
            return true;
        }

        private static bool IsExactObject(JObject value, HashSet<string> keys)
        {
            if (value == null || value.Count != keys.Count) return false;
            foreach (JProperty property in value.Properties()) if (!keys.Contains(property.Name)) return false;
            return true;
        }

        private static HashSet<string> Set(params string[] values)
        { return new HashSet<string>(values, StringComparer.Ordinal); }
    }
}
