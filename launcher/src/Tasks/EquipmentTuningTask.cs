using System;
using System.Collections.Generic;
using System.Text.RegularExpressions;
using System.Threading;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using CF7Launcher.Bus;
using CF7Launcher.Guardian;

namespace CF7Launcher.Tasks
{
    /// <summary>
    /// equipment_tuning-domain WebView↔Flash bridge.
    ///
    /// The Web envelope and every command payload are rebuilt from strict allow-lists.
    /// Host-owned panel instance and write watermark fields are injected after validation;
    /// they are never accepted from payload. Unknown commit outcomes enter an explicit
    /// reconcile gate and are never replayed.
    /// </summary>
    public sealed class EquipmentTuningTask : IDisposable
    {
        private sealed class PendingRequest
        {
            public int FlashCallId;
            public string WebCallId;
            public string WebCmd;
            public string FlashAction;
            public string PanelInstanceId;
            public string ViewSessionId;
            public string Operation;
            public string CandidateKey;
            public string ReconcileAfterCallId;
            public JObject NormalizedPayload;
            public bool IsWrite;
            public bool IsReconcile;
            public bool IsDetach;
            public int WriteEpoch;
            public int ReconcileTargetEpoch;
        }

        private const int DefaultTimeoutMs = 10000;
        private const int RecentCallIdCapacity = 256;
        private const int MaxPending = 24;

        private static readonly Regex ValidCallId = new Regex(
            "^[A-Za-z0-9._-]{1,96}$", RegexOptions.CultureInvariant | RegexOptions.Compiled);
        private static readonly Regex ValidOpaque = new Regex(
            "^[A-Za-z0-9._~-]{1,128}$", RegexOptions.CultureInvariant | RegexOptions.Compiled);
        private static readonly Regex ValidLease = new Regex(
            "^[A-Za-z0-9._-]{1,128}$", RegexOptions.CultureInvariant | RegexOptions.Compiled);

        private static readonly HashSet<string> TopLevelKeys = Set(
            "type", "panel", "domain", "cmd", "callId", "panelInstanceId", "payload");
        private static readonly HashSet<string> Operations = Set(
            "enhance", "convert", "install_tier", "install_mod", "replace_mod", "detach_mod", "detach_all_mods");
        private static readonly HashSet<string> DefinitiveWriteErrors = Set(
            "invalid_payload", "unsupported_version", "unsupported_cmd", "unsupported_operation",
            "panel_instance_expired", "view_session_expired", "token_invalid", "token_expired",
            "token_consumed", "stale_state", "stale_lease", "same_slot", "different_use",
            "invalid_target", "target_invalid", "type_mismatch", "cap_reached", "level_cap",
            "invalid_transition", "tier_locked", "material_missing", "mod_unavailable",
            "mod_not_installed",
            "insufficient_material", "inventory_full", "slot_full", "duplicate_mod",
            "mod_conflict", "dependency_missing", "detach_blocked", "condition_failed", "busy");

        private readonly Func<bool> _isClientReady;
        private readonly Func<string, bool> _trySend;
        private readonly int _timeoutMs;
        private readonly object _lock = new object();
        private readonly Dictionary<int, PendingRequest> _pending = new Dictionary<int, PendingRequest>();
        private readonly Dictionary<int, Timer> _timers = new Dictionary<int, Timer>();
        private readonly HashSet<string> _activeCallIds = new HashSet<string>(StringComparer.Ordinal);
        private readonly HashSet<string> _recentCallIds = new HashSet<string>(StringComparer.Ordinal);
        private readonly Queue<string> _recentCallIdOrder = new Queue<string>();

        private Action<string> _postToWeb;
        private Action<Action> _invokeOnUI;
        private Action _onCoordinatorSettled;
        private string _panelInstanceId;
        private string _activeViewSessionId;
        private string _detachingViewSessionId;
        private string _writeState = "idle";
        private string _lastWriteCallId;
        private int _writeEpoch;
        private int _seq;
        private volatile bool _disposed;

        public EquipmentTuningTask(XmlSocketServer socket)
            : this(
                delegate { return socket != null && socket.IsClientReady; },
                delegate(string payload) { return socket != null && socket.TrySend(payload); },
                DefaultTimeoutMs)
        {
        }

        public EquipmentTuningTask(Func<bool> isClientReady, Func<string, bool> trySend,
            int timeoutMs = DefaultTimeoutMs)
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
        internal int PendingCount { get { lock (_lock) return _pending.Count; } }
        internal string PanelInstanceId { get { lock (_lock) return _panelInstanceId; } }
        internal string ActiveViewSessionId { get { lock (_lock) return _activeViewSessionId; } }
        public bool HasBoundPanel { get { lock (_lock) return !string.IsNullOrEmpty(_panelInstanceId); } }
        public bool CanRebind { get { lock (_lock) return CanRebindLocked(); } }
        public bool CanClose { get { lock (_lock) return CanRebindLocked(); } }

        /// <summary>Bind only after WebOverlayForm has verified the active Host panel instance.</summary>
        public bool BindPanelInstance(string panelInstanceId)
        {
            if (!IsOpaque(panelInstanceId)) return false;
            bool changed = false;
            lock (_lock)
            {
                if (!string.Equals(_panelInstanceId, panelInstanceId, StringComparison.Ordinal))
                {
                    if (!string.IsNullOrEmpty(_panelInstanceId) && !CanRebindLocked()) return false;
                    _panelInstanceId = panelInstanceId;
                    changed = true;
                    // A Host rebind creates a new authority boundary. The next snapshot starts
                    // a new tuning view session; old tokens remain bound to the old pair.
                    _activeViewSessionId = null;
                    _detachingViewSessionId = null;
                }
            }
            if (changed)
                LogManager.Log("event=equipment_tuning_panel_bound panelInstanceId=" + panelInstanceId);
            return true;
        }

        public bool HandlePanelClosed(string panelInstanceId)
        {
            lock (_lock)
            {
                if (!IsOpaque(panelInstanceId)
                    || !string.Equals(_panelInstanceId, panelInstanceId, StringComparison.Ordinal)
                    || !CanRebindLocked()) return false;
                _panelInstanceId = null;
                _activeViewSessionId = null;
                _detachingViewSessionId = null;
                return true;
            }
        }

        public void HandleWebRequest(string cmd, JObject parsed)
        {
            string callId = ReadString(parsed != null ? parsed["callId"] : null);
            if (!IsCallId(callId))
            {
                RespondError(callId, cmd, "invalid_call_id", false, CurrentPanelInstance(),
                    CurrentViewSession(), CurrentEpoch());
                return;
            }

            string action;
            bool isWrite;
            if (!TryResolveCommand(cmd, out action, out isWrite))
            {
                RejectAndRemember(callId, cmd, "unsupported_cmd");
                return;
            }
            if (!IsExactObject(parsed, TopLevelKeys)
                || ReadString(parsed["type"]) != "panel"
                || ReadString(parsed["panel"]) != "workbench"
                || ReadString(parsed["domain"]) != "equipment_tuning"
                || ReadString(parsed["cmd"]) != cmd)
            {
                RejectAndRemember(callId, cmd, "invalid_payload");
                return;
            }

            string requestedInstance = ReadString(parsed["panelInstanceId"]);
            string boundInstance = CurrentPanelInstance();
            if (!IsOpaque(requestedInstance) || !IsOpaque(boundInstance)
                || !string.Equals(requestedInstance, boundInstance, StringComparison.Ordinal))
            {
                RejectAndRemember(callId, cmd, "panel_instance_expired");
                return;
            }

            JObject normalized;
            string viewSessionId;
            string operation;
            string candidateKey;
            string reconcileAfterCallId;
            bool isReconcile;
            if (!TryNormalizePayload(cmd, parsed["payload"] as JObject, out normalized,
                    out viewSessionId, out operation, out candidateKey,
                    out reconcileAfterCallId, out isReconcile))
            {
                RejectAndRemember(callId, cmd, "invalid_payload");
                return;
            }
            if (!_isClientReady())
            {
                RejectAndRemember(callId, cmd, "disconnected");
                return;
            }

            var entry = new PendingRequest
            {
                WebCallId = callId,
                WebCmd = cmd,
                FlashAction = action,
                PanelInstanceId = boundInstance,
                ViewSessionId = viewSessionId,
                Operation = operation,
                CandidateKey = candidateKey,
                ReconcileAfterCallId = reconcileAfterCallId,
                NormalizedPayload = normalized,
                IsWrite = isWrite,
                IsReconcile = isReconcile,
                IsDetach = cmd == "detach"
            };

            string reject = null;
            lock (_lock)
            {
                if (_activeCallIds.Contains(callId) || _recentCallIds.Contains(callId)) return;
                if (_pending.Count >= MaxPending) reject = "busy";
                else if (!string.Equals(_panelInstanceId, boundInstance, StringComparison.Ordinal))
                    reject = "panel_instance_expired";
                else if (cmd == "detach")
                {
                    bool ownsActiveSession = string.Equals(_activeViewSessionId, viewSessionId,
                        StringComparison.Ordinal);
                    bool retriesUnknownDetach = string.Equals(_detachingViewSessionId, viewSessionId,
                        StringComparison.Ordinal);
                    if (!ownsActiveSession && !retriesUnknownDetach) reject = "view_session_expired";
                    else if (_pending.Count != 0 || _writeState != "idle") reject = "busy";
                    else
                    {
                        _detachingViewSessionId = viewSessionId;
                        entry.WriteEpoch = _writeEpoch;
                    }
                }
                else if (!string.IsNullOrEmpty(_detachingViewSessionId))
                    reject = "view_session_expired";
                else if (cmd == "snapshot")
                {
                    if (isReconcile)
                    {
                        if (!IsCallId(_lastWriteCallId)
                            || !string.Equals(_lastWriteCallId, reconcileAfterCallId, StringComparison.Ordinal))
                            reject = "invalid_payload";
                        else if (_writeState == "write_pending") reject = "busy";
                        else
                        {
                            _activeViewSessionId = viewSessionId;
                            entry.ReconcileTargetEpoch = _writeEpoch;
                            entry.WriteEpoch = _writeEpoch;
                        }
                    }
                    else if (_writeState != "idle")
                        reject = _writeState == "needs_reconcile" ? "reconcile_required" : "busy";
                    else
                    {
                        // A fresh snapshot is the only Web command that starts/rotates a view session.
                        _activeViewSessionId = viewSessionId;
                        entry.WriteEpoch = _writeEpoch;
                    }
                }
                else if (cmd == "preview")
                {
                    if (isReconcile)
                    {
                        if (!IsCallId(_lastWriteCallId)
                            || !string.Equals(_lastWriteCallId, reconcileAfterCallId, StringComparison.Ordinal))
                            reject = "invalid_payload";
                        else if (_writeState == "write_pending") reject = "busy";
                        else
                        {
                            if (string.IsNullOrEmpty(_activeViewSessionId)) _activeViewSessionId = viewSessionId;
                            if (!string.Equals(_activeViewSessionId, viewSessionId, StringComparison.Ordinal))
                                reject = "view_session_expired";
                            else
                            {
                                entry.ReconcileTargetEpoch = _writeEpoch;
                                entry.WriteEpoch = _writeEpoch;
                            }
                        }
                    }
                    else if (!string.Equals(_activeViewSessionId, viewSessionId, StringComparison.Ordinal))
                        reject = "view_session_expired";
                    else if (_writeState != "idle")
                        reject = _writeState == "needs_reconcile" ? "reconcile_required" : "busy";
                    else entry.WriteEpoch = _writeEpoch;
                }
                else if (isWrite)
                {
                    if (!string.Equals(_activeViewSessionId, viewSessionId, StringComparison.Ordinal))
                        reject = "view_session_expired";
                    else if (_writeState != "idle")
                        reject = _writeState == "needs_reconcile" ? "reconcile_required" : "busy";
                    else
                    {
                        _writeEpoch++;
                        entry.WriteEpoch = _writeEpoch;
                        _writeState = "write_pending";
                        _lastWriteCallId = callId;
                    }
                }
                else // tooltip
                {
                    if (string.IsNullOrEmpty(_activeViewSessionId)) reject = "view_session_expired";
                    else if (!string.Equals(_activeViewSessionId, viewSessionId, StringComparison.Ordinal))
                        reject = "view_session_expired";
                    else if (_writeState == "write_pending") reject = "busy";
                    else
                    {
                        entry.WriteEpoch = _writeEpoch;
                    }
                }

                if (reject == null)
                {
                    _activeCallIds.Add(callId);
                }
                else RememberRecentLocked(callId);
            }

            if (reject != null)
            {
                string reconcileHint = reject == "reconcile_required"
                    ? CurrentReconcileAfterCallId() : null;
                RespondError(callId, cmd, reject, reconcileHint != null, boundInstance,
                    viewSessionId ?? CurrentViewSession(), CurrentEpoch(), reconcileHint);
                return;
            }
            DispatchToFlash(entry);
        }

        public void HandleFlashResponse(JObject msg, Action<string> respond)
        {
            int fid;
            if (!TryReadInteger(msg != null ? msg["callId"] : null, 1, int.MaxValue, out fid))
            {
                if (respond != null) respond(null);
                return;
            }

            PendingRequest entry;
            JObject web;
            bool clearReconcile = false;
            bool snapshotConfirmed = false;
            lock (_lock)
            {
                if (!_pending.TryGetValue(fid, out entry))
                {
                    if (respond != null) respond(null);
                    return;
                }

                bool valid = IsValidResponse(msg, entry);
                snapshotConfirmed = valid && entry.WebCmd == "snapshot"
                    && msg.Value<bool?>("success") == true;
                bool definitiveWrite = entry.IsWrite && valid && IsDefinitiveWriteResponse(msg);
                if (entry.IsReconcile)
                {
                    clearReconcile = valid && IsReconcileAcknowledged(msg, entry)
                        && _writeState != "write_pending"
                        && entry.WriteEpoch == _writeEpoch
                        && entry.WriteEpoch >= entry.ReconcileTargetEpoch
                        && string.Equals(entry.ReconcileAfterCallId, _lastWriteCallId, StringComparison.Ordinal);
                }

                CompletePendingLocked(entry);
                web = valid ? SanitizeFlashResponse(msg) : new JObject
                {
                    ["success"] = false,
                    ["error"] = "malformed_response"
                };

                if (entry.IsWrite)
                {
                    _writeState = definitiveWrite ? "idle" : "needs_reconcile";
                    if (!definitiveWrite) web["requiresReconcile"] = true;
                }
                else if (entry.IsReconcile)
                {
                    if (clearReconcile)
                    {
                        _writeState = "idle";
                        web["reconciled"] = true;
                    }
                    else
                    {
                        web["requiresReconcile"] = true;
                    }
                }
                else if (entry.IsDetach)
                {
                    if (valid && msg.Value<bool?>("success") == true)
                    {
                        _activeViewSessionId = null;
                        _detachingViewSessionId = null;
                    }
                    else if (valid)
                    {
                        // A well-formed failure is definitive: AS2 did not invalidate the
                        // generation, so the view may retry or continue using this session.
                        _activeViewSessionId = entry.ViewSessionId;
                        _detachingViewSessionId = null;
                    }
                    else
                    {
                        // A malformed acknowledgement leaves AS2 outcome unknown. Fail closed
                        // for old commits while retaining an idempotent detach retry handle.
                        _activeViewSessionId = null;
                        _detachingViewSessionId = entry.ViewSessionId;
                    }
                }
            }

            StampAndPost(web, entry);
            if (snapshotConfirmed)
                LogManager.Log("event=equipment_tuning_snapshot_confirmed callId=" + entry.WebCallId
                    + " panelInstanceId=" + entry.PanelInstanceId
                    + " viewSessionId=" + entry.ViewSessionId
                    + " writeEpoch=" + entry.WriteEpoch);
            NotifyCoordinatorSettledIfReady();
            if (respond != null) respond(null);
        }

        public void ClearPending()
        {
            lock (_lock)
            {
                foreach (PendingRequest entry in _pending.Values)
                {
                    _activeCallIds.Remove(entry.WebCallId);
                    RememberRecentLocked(entry.WebCallId);
                    if (entry.IsWrite) _writeState = "needs_reconcile";
                }
                foreach (Timer timer in _timers.Values) timer.Dispose();
                _timers.Clear();
                _pending.Clear();
                _panelInstanceId = null;
                _activeViewSessionId = null;
                _detachingViewSessionId = null;
            }
        }

        public void Dispose()
        {
            _disposed = true;
            ClearPending();
        }

        private void DispatchToFlash(PendingRequest entry)
        {
            lock (_lock)
            {
                entry.FlashCallId = ++_seq;
                _pending[entry.FlashCallId] = entry;
            }
            var timer = new Timer(delegate { HandleTimeout(entry.FlashCallId); }, null,
                _timeoutMs, Timeout.Infinite);
            lock (_lock)
            {
                if (_pending.ContainsKey(entry.FlashCallId)) _timers[entry.FlashCallId] = timer;
                else timer.Dispose();
            }

            JObject payload = entry.NormalizedPayload != null
                ? (JObject)entry.NormalizedPayload.DeepClone() : new JObject();
            payload["panelInstanceId"] = entry.PanelInstanceId;
            payload["viewSessionId"] = entry.ViewSessionId;
            payload["writeEpoch"] = entry.WriteEpoch;
            payload["requestCallId"] = entry.WebCallId;
            JObject flash = PanelBridge.BuildFlashCommand(entry.FlashAction, entry.FlashCallId, payload);
            string json = flash.ToString(Formatting.None);
            LogManager.Log("[EquipmentTuningTask] -> Flash: " + json);
            if (!_trySend(json + "\0")) HandleSendFailure(entry.FlashCallId);
        }

        private void HandleTimeout(int fid)
        {
            if (_disposed) return;
            PendingRequest entry;
            lock (_lock)
            {
                if (!_pending.TryGetValue(fid, out entry)) return;
                CompletePendingLocked(entry);
                if (entry.IsWrite) _writeState = "needs_reconcile";
                if (entry.IsDetach)
                {
                    _activeViewSessionId = null;
                    _detachingViewSessionId = entry.ViewSessionId;
                }
            }
            RespondError(entry.WebCallId, entry.WebCmd, "timeout", entry.IsWrite || entry.IsReconcile,
                entry.PanelInstanceId, entry.ViewSessionId, entry.WriteEpoch);
            NotifyCoordinatorSettledIfReady();
        }

        private void HandleSendFailure(int fid)
        {
            PendingRequest entry;
            bool definitivelyNotSent;
            lock (_lock)
            {
                if (!_pending.TryGetValue(fid, out entry)) return;
                CompletePendingLocked(entry);
                definitivelyNotSent = entry.IsWrite || entry.IsDetach;
                if (entry.IsWrite) _writeState = "idle";
                if (entry.IsDetach)
                {
                    _activeViewSessionId = entry.ViewSessionId;
                    _detachingViewSessionId = null;
                }
            }
            RespondError(entry.WebCallId, entry.WebCmd, definitivelyNotSent ? "not_sent" : "disconnected",
                entry.IsReconcile,
                entry.PanelInstanceId, entry.ViewSessionId, entry.WriteEpoch);
            NotifyCoordinatorSettledIfReady();
        }

        private void CompletePendingLocked(PendingRequest entry)
        {
            _pending.Remove(entry.FlashCallId);
            Timer timer;
            if (_timers.TryGetValue(entry.FlashCallId, out timer))
            {
                timer.Dispose();
                _timers.Remove(entry.FlashCallId);
            }
            _activeCallIds.Remove(entry.WebCallId);
            RememberRecentLocked(entry.WebCallId);
        }

        private static bool TryResolveCommand(string cmd, out string action, out bool isWrite)
        {
            isWrite = false;
            switch (cmd)
            {
                case "snapshot": action = "equipmentTuningSnapshot"; return true;
                case "preview": action = "equipmentTuningPreview"; return true;
                case "commit": action = "equipmentTuningCommit"; isWrite = true; return true;
                case "tooltip": action = "equipmentTuningTooltip"; return true;
                case "detach": action = "equipmentTuningDetach"; return true;
                default: action = null; return false;
            }
        }

        private static bool TryNormalizePayload(string cmd, JObject payload, out JObject normalized,
            out string viewSessionId, out string operation, out string candidateKey,
            out string reconcileAfterCallId, out bool isReconcile)
        {
            normalized = null;
            viewSessionId = null;
            operation = null;
            candidateKey = null;
            reconcileAfterCallId = null;
            isReconcile = false;
            if (payload == null || !HasVersion(payload)) return false;

            var result = new JObject { ["v"] = 1 };
            if (cmd == "tooltip")
            {
                if (!IsExactObject(payload, Set("v", "viewSessionId", "candidateKey"))) return false;
                viewSessionId = ReadString(payload["viewSessionId"]);
                candidateKey = ReadString(payload["candidateKey"]);
                if (!IsOpaque(viewSessionId) || !IsSafeText(candidateKey, 1, 128)) return false;
                result["viewSessionId"] = viewSessionId;
                result["candidateKey"] = candidateKey;
                normalized = result;
                return true;
            }

            viewSessionId = ReadString(payload["viewSessionId"]);
            if (!IsOpaque(viewSessionId)) return false;
            result["viewSessionId"] = viewSessionId;

            if (cmd == "detach")
            {
                if (!IsExactObject(payload, Set("v", "viewSessionId"))) return false;
                normalized = result;
                return true;
            }

            bool hasReconcile = payload["reconcileAfterCallId"] != null;
            if (hasReconcile)
            {
                reconcileAfterCallId = ReadString(payload["reconcileAfterCallId"]);
                if (!IsCallId(reconcileAfterCallId)) return false;
                result["reconcileAfterCallId"] = reconcileAfterCallId;
                isReconcile = true;
            }

            if (cmd == "snapshot")
            {
                HashSet<string> keys = hasReconcile
                    ? Set("v", "viewSessionId", "source", "reconcileAfterCallId")
                    : Set("v", "viewSessionId", "source");
                JObject source;
                if (!IsExactObject(payload, keys) || !TryNormalizeSlotRef(payload["source"] as JObject, out source))
                    return false;
                result["source"] = source;
            }
            else if (cmd == "preview")
            {
                operation = ReadString(payload["operation"]);
                if (!Operations.Contains(operation)) return false;
                var keys = new HashSet<string>(StringComparer.Ordinal)
                    { "v", "viewSessionId", "operation", "source" };
                if (hasReconcile) keys.Add("reconcileAfterCallId");
                if (operation == "enhance") keys.Add("targetLevel");
                else if (operation == "convert") keys.Add("target");
                else if (operation != "detach_all_mods") keys.Add("candidateKey");
                if (operation == "replace_mod") keys.Add("replaceCandidateKey");
                if (!IsExactObject(payload, keys)) return false;

                JObject source;
                if (!TryNormalizeSlotRef(payload["source"] as JObject, out source)) return false;
                result["operation"] = operation;
                result["source"] = source;
                if (operation == "enhance")
                {
                    int targetLevel;
                    if (!TryReadInteger(payload["targetLevel"], 1, 13, out targetLevel)) return false;
                    result["targetLevel"] = targetLevel;
                }
                else if (operation == "convert")
                {
                    JObject target;
                    if (!TryNormalizeSlotRef(payload["target"] as JObject, out target)) return false;
                    result["target"] = target;
                }
                else if (operation != "detach_all_mods")
                {
                    candidateKey = ReadString(payload["candidateKey"]);
                    if (!IsSafeText(candidateKey, 1, 128)) return false;
                    result["candidateKey"] = candidateKey;
                    if (operation == "replace_mod")
                    {
                        string replaceCandidateKey = ReadString(payload["replaceCandidateKey"]);
                        if (!IsSafeText(replaceCandidateKey, 1, 128)
                                || replaceCandidateKey == candidateKey) return false;
                        result["replaceCandidateKey"] = replaceCandidateKey;
                    }
                }
            }
            else if (cmd == "commit")
            {
                if (hasReconcile || !IsExactObject(payload,
                        Set("v", "viewSessionId", "expectedTuningToken"))) return false;
                string token = ReadString(payload["expectedTuningToken"]);
                if (!IsOpaque(token)) return false;
                result["expectedTuningToken"] = token;
            }
            else return false;

            normalized = result;
            return true;
        }

        private static bool TryNormalizeSlotRef(JObject input, out JObject normalized)
        {
            normalized = null;
            if (!IsExactObject(input, Set("containerId", "slot", "expectedLease"))) return false;
            if (ReadString(input["containerId"]) != "背包") return false;
            int slot;
            string lease = ReadString(input["expectedLease"]);
            if (!TryReadInteger(input["slot"], 0, 49, out slot) || !IsLease(lease)) return false;
            normalized = new JObject
            {
                ["containerId"] = "背包",
                ["slot"] = slot,
                ["expectedLease"] = lease
            };
            return true;
        }

        private static bool IsValidResponse(JObject msg, PendingRequest entry)
        {
            if (msg == null
                || ReadString(msg["task"]) != "equipment_tuning_response"
                || ReadString(msg["command"]) != entry.WebCmd
                || ReadString(msg["panelInstanceId"]) != entry.PanelInstanceId
                || ReadString(msg["viewSessionId"]) != entry.ViewSessionId
                || !HasVersion(msg)
                || msg["success"] == null || msg["success"].Type != JTokenType.Boolean)
                return false;
            if (!HasOnlyResponseKeys(msg, entry.WebCmd, msg.Value<bool>("success"))) return false;
            if (msg["reconciled"] != null && msg["reconciled"].Type != JTokenType.Boolean) return false;
            if (msg["reconcileAfterCallId"] != null
                && !IsCallId(ReadString(msg["reconcileAfterCallId"]))) return false;
            int responseEpoch;
            if (!TryReadInteger(msg["writeEpoch"], 0, int.MaxValue, out responseEpoch)
                || responseEpoch != entry.WriteEpoch) return false;

            if (!msg.Value<bool>("success"))
            {
                if (entry.WebCmd == "commit" && msg["transactionId"] != null
                    && !IsOpaque(ReadString(msg["transactionId"]))) return false;
                return IsSafeText(ReadString(msg["error"]), 1, 64);
            }

            if (entry.WebCmd == "snapshot") return IsSnapshotResponse(msg);
            if (entry.WebCmd == "preview") return IsPreviewResponse(msg, entry.Operation);
            if (entry.WebCmd == "commit") return IsCommitResponse(msg);
            if (entry.WebCmd == "detach") return true;
            return ReadString(msg["candidateKey"]) == entry.CandidateKey
                && msg["introHTML"] != null && msg["introHTML"].Type == JTokenType.String
                && msg["descHTML"] != null && msg["descHTML"].Type == JTokenType.String
                && msg["itemType"] != null && msg["itemType"].Type == JTokenType.String
                && msg["itemUse"] != null && msg["itemUse"].Type == JTokenType.String
                && msg["html"] != null && msg["html"].Type == JTokenType.String
                && msg["text"] != null && msg["text"].Type == JTokenType.String;
        }

        private static bool HasOnlyResponseKeys(JObject msg, string cmd, bool success)
        {
            HashSet<string> keys = Set("task", "callId", "v", "success", "command",
                "panelInstanceId", "viewSessionId", "writeEpoch", "reconciled",
                "reconcileAfterCallId", "error");
            if (!success && cmd == "commit") keys.Add("transactionId");
            if (success)
            {
                if (cmd == "snapshot") keys.Add("snapshot");
                else if (cmd == "preview" || cmd == "commit")
                {
                    keys.Add("tuningToken"); keys.Add("operation"); keys.Add("before");
                    keys.Add("after"); keys.Add("materials"); keys.Add("noOp");
                    keys.Add("removedMods"); keys.Add("canCommit");
                    if (cmd == "commit")
                    {
                        keys.Add("snapshot"); keys.Add("inventorySnapshots");
                        keys.Add("transactionId");
                    }
                }
                else if (cmd == "tooltip")
                {
                    keys.Add("candidateKey"); keys.Add("introHTML"); keys.Add("descHTML");
                    keys.Add("itemType"); keys.Add("itemUse"); keys.Add("html"); keys.Add("text");
                }
            }
            foreach (JProperty property in msg.Properties())
                if (!keys.Contains(property.Name)) return false;
            return true;
        }

        private static bool IsSnapshotResponse(JObject msg)
        {
            JObject snapshot = msg["snapshot"] as JObject;
            string gender = snapshot != null ? ReadString(snapshot["gender"]) : null;
            if (snapshot == null || !(snapshot["source"] is JObject)
                || !(snapshot["equipment"] is JObject) || !(snapshot["enhance"] is JObject)
                || !(snapshot["tierCandidates"] is JArray) || !(snapshot["modCandidates"] is JArray))
                return false;
            return (gender == "男" || gender == "女") && IsContainer(snapshot["materials"]);
        }

        private static bool IsPreviewResponse(JObject msg, string expectedOperation)
        {
            string operation = ReadString(msg["operation"]);
            if (!Operations.Contains(operation)
                || (!string.IsNullOrEmpty(expectedOperation) && operation != expectedOperation)
                || !IsOpaque(ReadString(msg["tuningToken"]))
                || !(msg["before"] is JObject) || !(msg["after"] is JObject)
                || !IsContainer(msg["materials"])) return false;
            if (msg["noOp"] != null && msg["noOp"].Type != JTokenType.Boolean) return false;
            if (msg["removedMods"] != null && !(msg["removedMods"] is JArray)) return false;
            if (msg["canCommit"] != null && msg["canCommit"].Type != JTokenType.Boolean) return false;
            return true;
        }

        private static bool IsCommitResponse(JObject msg)
        {
            return IsPreviewResponse(msg, null)
                && IsOpaque(ReadString(msg["transactionId"]))
                && IsSnapshotResponse(msg)
                && msg["inventorySnapshots"] is JArray;
        }

        private static bool IsReconcileAcknowledged(JObject msg, PendingRequest entry)
        {
            return msg.Value<bool?>("success") == true
                && msg.Value<bool?>("reconciled") == true
                && ReadString(msg["reconcileAfterCallId"]) == entry.ReconcileAfterCallId;
        }

        private static bool IsDefinitiveWriteResponse(JObject msg)
        {
            if (msg.Value<bool?>("success") == true) return true;
            return DefinitiveWriteErrors.Contains(ReadString(msg["error"]));
        }

        private static JObject SanitizeFlashResponse(JObject msg)
        {
            JObject result = msg != null ? (JObject)msg.DeepClone() : new JObject();
            result.Remove("task");
            result.Remove("command");
            result.Remove("callId");
            result.Remove("panelInstanceId");
            result.Remove("viewSessionId");
            result.Remove("writeEpoch");
            result.Remove("reconciled");
            result.Remove("reconcileAfterCallId");
            return result;
        }

        private void StampAndPost(JObject web, PendingRequest entry)
        {
            web["type"] = "panel_resp";
            web["panel"] = "workbench";
            web["domain"] = "equipment_tuning";
            web["cmd"] = entry.WebCmd;
            web["callId"] = entry.WebCallId;
            web["panelInstanceId"] = entry.PanelInstanceId;
            web["viewSessionId"] = entry.ViewSessionId;
            web["writeEpoch"] = entry.WriteEpoch;
            if (entry.IsReconcile) web["reconcileAfterCallId"] = entry.ReconcileAfterCallId;
            PostToWeb(web.ToString(Formatting.None));
        }

        private void RejectAndRemember(string callId, string cmd, string error)
        {
            string instance;
            string session;
            int epoch;
            lock (_lock)
            {
                if (_activeCallIds.Contains(callId) || _recentCallIds.Contains(callId)) return;
                RememberRecentLocked(callId);
                instance = _panelInstanceId;
                session = _activeViewSessionId;
                epoch = _writeEpoch;
            }
            RespondError(callId, cmd, error, false, instance, session, epoch);
        }

        private void RememberRecentLocked(string callId)
        {
            if (string.IsNullOrEmpty(callId) || !_recentCallIds.Add(callId)) return;
            _recentCallIdOrder.Enqueue(callId);
            while (_recentCallIdOrder.Count > RecentCallIdCapacity)
                _recentCallIds.Remove(_recentCallIdOrder.Dequeue());
        }

        private void RespondError(string callId, string cmd, string error, bool requiresReconcile,
            string panelInstanceId, string viewSessionId, int writeEpoch,
            string reconcileAfterCallId = null)
        {
            var response = new JObject
            {
                ["type"] = "panel_resp",
                ["panel"] = "workbench",
                ["domain"] = "equipment_tuning",
                ["cmd"] = cmd ?? "",
                ["callId"] = callId ?? "",
                ["panelInstanceId"] = panelInstanceId,
                ["viewSessionId"] = viewSessionId,
                ["writeEpoch"] = writeEpoch,
                ["success"] = false,
                ["error"] = error
            };
            if (requiresReconcile) response["requiresReconcile"] = true;
            if (requiresReconcile && IsCallId(reconcileAfterCallId))
                response["reconcileAfterCallId"] = reconcileAfterCallId;
            PostToWeb(response.ToString(Formatting.None));
        }

        private void PostToWeb(string json)
        {
            if (_invokeOnUI != null) _invokeOnUI(delegate { if (_postToWeb != null) _postToWeb(json); });
            else if (_postToWeb != null) _postToWeb(json);
        }

        private string CurrentPanelInstance() { lock (_lock) return _panelInstanceId; }
        private string CurrentViewSession() { lock (_lock) return _activeViewSessionId; }
        private int CurrentEpoch() { lock (_lock) return _writeEpoch; }
        private string CurrentReconcileAfterCallId()
        {
            lock (_lock) return IsCallId(_lastWriteCallId) ? _lastWriteCallId : null;
        }

        private bool CanRebindLocked()
        {
            return _pending.Count == 0 && _writeState == "idle"
                && string.IsNullOrEmpty(_detachingViewSessionId);
        }

        private void NotifyCoordinatorSettledIfReady()
        {
            Action callback;
            lock (_lock) callback = CanRebindLocked() ? _onCoordinatorSettled : null;
            if (callback != null) callback();
        }

        private static bool HasVersion(JObject value)
        {
            return value != null && value["v"] != null && value["v"].Type == JTokenType.Integer
                && value.Value<int>("v") == 1;
        }

        private static bool IsContainer(JToken value)
        {
            return value is JObject || value is JArray;
        }

        private static bool IsExactObject(JObject value, HashSet<string> keys)
        {
            if (value == null || value.Count != keys.Count) return false;
            foreach (JProperty property in value.Properties())
                if (!keys.Contains(property.Name)) return false;
            return true;
        }

        private static HashSet<string> Set(params string[] values)
        {
            return new HashSet<string>(values, StringComparer.Ordinal);
        }

        private static string ReadString(JToken value)
        {
            return value != null && value.Type == JTokenType.String ? value.Value<string>() : null;
        }

        private static bool IsCallId(string value)
        {
            return !string.IsNullOrEmpty(value) && ValidCallId.IsMatch(value);
        }

        private static bool IsOpaque(string value)
        {
            return !string.IsNullOrEmpty(value) && ValidOpaque.IsMatch(value);
        }

        private static bool IsLease(string value)
        {
            return !string.IsNullOrEmpty(value) && ValidLease.IsMatch(value);
        }

        private static bool IsSafeText(string value, int min, int max)
        {
            if (value == null || value.Length < min || value.Length > max) return false;
            for (int i = 0; i < value.Length; i++) if (char.IsControl(value[i])) return false;
            return true;
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
    }
}
