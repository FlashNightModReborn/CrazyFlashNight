using System;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Text;
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
            public JObject Source;
            public JObject SnapshotEquipment;
            public Dictionary<string, JObject> SnapshotMaterials;
            public JObject CandidateAuthority;
            public JObject ReplaceCandidateAuthority;
            public string ExpectedTuningToken;
            public PreviewBinding ConsumedPreviewBinding;
            public bool IsWrite;
            public bool IsReconcile;
            public bool IsDetach;
            public int WriteEpoch;
            public int ReconcileTargetEpoch;
        }

        private sealed class PreviewBinding
        {
            public string TuningToken;
            public string TokenRef;
            public string PreviewWebCallId;
            public string PanelInstanceId;
            public string ViewSessionId;
            public string Operation;
            public string CandidateKey;
            public string IntentKey;
            public string SourceKey;
            public JObject Source;
            public JObject Before;
            public JObject After;
            public JArray Materials;
            public JArray RemovedMods;
            public bool NoOp;
            public bool CanCommit;
            public LinkedListNode<PreviewBinding> OrderNode;
        }

        private sealed class SnapshotAuthority
        {
            public string SnapshotWebCallId;
            public string PanelInstanceId;
            public string ViewSessionId;
            public string SourceKey;
            public JObject Source;
            public JObject Equipment;
            public Dictionary<string, JObject> TierCandidates;
            public Dictionary<string, JObject> ModCandidates;
            public Dictionary<string, JObject> Materials;
        }

        private const int DefaultTimeoutMs = 10000;
        private const int RecentCallIdCapacity = 256;
        private const int PreviewBindingCapacity = 1;
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
            "invalid_transition", "tier_locked", "level_locked", "material_missing", "mod_unavailable",
            "mod_not_installed",
            "insufficient_material", "inventory_full", "slot_full", "duplicate_mod",
            "mod_conflict", "dependency_missing", "detach_blocked", "condition_failed", "busy");
        private static readonly HashSet<string> TierCandidateKeys = Set(
            "candidateKey", "itemName", "displayName", "icon", "tierName",
            "owned", "available", "reason");
        private static readonly HashSet<string> ModCandidateKeys = Set(
            "candidateKey", "itemName", "displayName", "icon", "owned",
            "installed", "available", "availabilityCode", "reason",
            "replaceableFrom", "grade", "gradeLabel", "gradeColor", "scope",
            "scopeLabel", "role", "roleLabel", "symbol");
        private static readonly HashSet<string> EquipmentProjectionKeys = Set(
            "name", "displayName", "icon", "type", "use", "level", "tier",
            "mods", "lastUpdate", "maxLevel", "hardMaxLevel");
        private static readonly HashSet<string> TuningSubjectKeys = Set(
            "source", "equipment");
        private static readonly HashSet<string> MaterialPlanKeys = Set(
            "itemName", "displayName", "icon", "before", "delta", "after");
        private static readonly HashSet<string> SnapshotMaterialKeys = Set(
            "itemName", "displayName", "icon", "count");
        private static readonly HashSet<string> SnapshotKeys = Set(
            "gender", "source", "equipment", "enhance", "tierCandidates",
            "modCandidates", "materials", "materialRevision", "inventoryRevision");
        private static readonly HashSet<string> EnhanceProjectionKeys = Set(
            "currentLevel", "maxLevel", "availableMaxLevel", "hardMaxLevel");
        private static readonly HashSet<string> StatRowKeys = Set(
            "key", "label", "value");

        private readonly Func<bool> _isClientReady;
        private readonly Func<string, bool> _trySend;
        private readonly int _timeoutMs;
        private readonly object _lock = new object();
        private readonly Dictionary<int, PendingRequest> _pending = new Dictionary<int, PendingRequest>();
        private readonly Dictionary<int, Timer> _timers = new Dictionary<int, Timer>();
        private readonly HashSet<string> _activeCallIds = new HashSet<string>(StringComparer.Ordinal);
        private readonly HashSet<string> _recentCallIds = new HashSet<string>(StringComparer.Ordinal);
        private readonly Queue<string> _recentCallIdOrder = new Queue<string>();
        private readonly Dictionary<string, PreviewBinding> _previewBindings =
            new Dictionary<string, PreviewBinding>(StringComparer.Ordinal);
        private readonly LinkedList<PreviewBinding> _previewBindingOrder =
            new LinkedList<PreviewBinding>();
        private SnapshotAuthority _snapshotAuthority;
        private string _latestSnapshotWebCallId;
        private string _latestPreviewWebCallId;

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
        internal int PreviewBindingCount { get { lock (_lock) return _previewBindings.Count; } }
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
                    ClearPreviewBindingsLocked();
                    ClearSnapshotAuthorityLocked();
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
                ClearPreviewBindingsLocked();
                ClearSnapshotAuthorityLocked();
                return true;
            }
        }

        public void HandleWebRequest(string cmd, JObject parsed)
        {
            string callId = ReadString(parsed != null ? parsed["callId"] : null);
            string requestedInstance = ReadString(
                parsed != null ? parsed["panelInstanceId"] : null);
            JObject requestedPayload = parsed != null
                ? parsed["payload"] as JObject
                : null;
            string requestedViewSessionId = ReadString(
                requestedPayload != null
                    ? requestedPayload["viewSessionId"]
                    : null);
            if (!IsCallId(callId))
            {
                RespondError(callId, cmd, "invalid_call_id", false,
                    requestedInstance, requestedViewSessionId,
                    CurrentEpoch());
                return;
            }

            string action;
            bool isWrite;
            if (!TryResolveCommand(cmd, out action, out isWrite))
            {
                RejectAndRemember(callId, cmd, "unsupported_cmd",
                    requestedInstance, requestedViewSessionId);
                return;
            }

            if (!IsExactObject(parsed, TopLevelKeys)
                || ReadString(parsed["type"]) != "panel"
                || ReadString(parsed["panel"]) != "workbench"
                || ReadString(parsed["domain"]) != "equipment_tuning"
                || ReadString(parsed["cmd"]) != cmd)
            {
                RejectAndRemember(callId, cmd, "invalid_payload",
                    requestedInstance, requestedViewSessionId);
                return;
            }

            string boundInstance = CurrentPanelInstance();
            if (!IsOpaque(requestedInstance) || !IsOpaque(boundInstance)
                || !string.Equals(requestedInstance, boundInstance, StringComparison.Ordinal))
            {
                RejectAndRemember(callId, cmd, "panel_instance_expired",
                    requestedInstance, requestedViewSessionId);
                return;
            }

            // A preview intent owned by the exact current panel/view session is a
            // generation boundary even when its business payload is rejected later.
            // Validate the owner envelope first so foreign/stale messages cannot revoke
            // a legitimate token, then revoke before payload/readiness/authority checks.
            if (cmd == "preview")
            {
                lock (_lock)
                {
                    if (_activeCallIds.Contains(callId)
                        || _recentCallIds.Contains(callId)) return;
                    if (IsOpaque(requestedViewSessionId)
                        && string.Equals(
                            _activeViewSessionId,
                            requestedViewSessionId,
                            StringComparison.Ordinal))
                    {
                        BeginPreviewAttemptLocked(callId);
                    }
                }
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
                RejectAndRemember(callId, cmd, "invalid_payload",
                    requestedInstance, requestedViewSessionId);
                return;
            }
            if (cmd == "detach"
                && TryCompleteDetachWithoutAuthority(
                    callId,
                    boundInstance,
                    viewSessionId))
            {
                return;
            }
            if (!_isClientReady())
            {
                RejectAndRemember(callId, cmd, "disconnected",
                    requestedInstance, viewSessionId);
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
                Source = normalized["source"] is JObject
                    ? (JObject)normalized["source"].DeepClone()
                    : null,
                ExpectedTuningToken =
                    ReadString(normalized["expectedTuningToken"]),
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
                            RotateViewSessionLocked(
                                viewSessionId);
                            BeginSnapshotAuthorityRefreshLocked(
                                callId);
                            entry.ReconcileTargetEpoch = _writeEpoch;
                            entry.WriteEpoch = _writeEpoch;
                        }
                    }
                    else if (_writeState != "idle")
                        reject = _writeState == "needs_reconcile" ? "reconcile_required" : "busy";
                    else
                    {
                        // A fresh snapshot is the only Web command that starts/rotates a view session.
                        RotateViewSessionLocked(
                            viewSessionId);
                        BeginSnapshotAuthorityRefreshLocked(
                            callId);
                        entry.WriteEpoch = _writeEpoch;
                    }
                }
                else if (cmd == "preview")
                {
                    if (!string.Equals(_activeViewSessionId, viewSessionId, StringComparison.Ordinal))
                        reject = "view_session_expired";
                    else if (_writeState != "idle")
                        reject = _writeState == "needs_reconcile" ? "reconcile_required" : "busy";
                    else if (!TryBindPreviewAuthorityLocked(entry))
                        reject = "invalid_payload";
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
                        PreviewBinding binding;
                        if (!TryConsumePreviewBindingLocked(
                                entry.ExpectedTuningToken,
                                boundInstance,
                                viewSessionId,
                                out binding))
                        {
                            reject = "invalid_payload";
                        }
                        else
                        {
                            entry.ConsumedPreviewBinding =
                                binding;
                            entry.Source = (JObject)
                                binding.Source.DeepClone();
                            entry.Operation =
                                binding.Operation;
                            _writeEpoch++;
                            entry.WriteEpoch = _writeEpoch;
                            _writeState = "write_pending";
                            _lastWriteCallId = callId;
                        }
                    }
                }
                else // tooltip
                {
                    if (string.IsNullOrEmpty(_activeViewSessionId)) reject = "view_session_expired";
                    else if (!string.Equals(_activeViewSessionId, viewSessionId, StringComparison.Ordinal))
                        reject = "view_session_expired";
                    else if (_writeState == "write_pending") reject = "busy";
                    else if (!TryBindTooltipAuthorityLocked(entry)) reject = "invalid_payload";
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
                    viewSessionId, CurrentEpoch(), reconcileHint);
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
            string previewOutcome = null;
            string previewTokenRef = null;
            string commitOutcome = null;
            string commitWriteState = null;
            bool commitSnapshotPresent = false;
            bool commitTransactionIdPresent = false;
            string commitStateRef = null;
            string snapshotStateRef = null;
            int remainingPending = -1;
            lock (_lock)
            {
                if (!_pending.TryGetValue(fid, out entry))
                {
                    if (respond != null) respond(null);
                    return;
                }

                bool valid = IsValidResponse(msg, entry);
                if (valid
                    && entry.WebCmd == "preview"
                    && msg.Value<bool?>("success") == true
                    && string.Equals(
                        _latestPreviewWebCallId,
                        entry.WebCallId,
                        StringComparison.Ordinal))
                {
                    valid = TryRememberPreviewBindingLocked(
                        new PreviewBinding
                        {
                            TuningToken =
                                ReadString(
                                    msg["tuningToken"]),
                            TokenRef = TokenReference(
                                ReadString(msg["tuningToken"])),
                            PreviewWebCallId =
                                entry.WebCallId,
                            PanelInstanceId =
                                entry.PanelInstanceId,
                            ViewSessionId =
                                entry.ViewSessionId,
                            Operation =
                                entry.Operation,
                            CandidateKey =
                                entry.CandidateKey,
                            IntentKey =
                                PreviewIntentKey(entry),
                            SourceKey =
                                PreviewSourceKey(entry.Source),
                            Source = entry.Source != null
                                ? (JObject)entry.Source
                                    .DeepClone()
                                : null,
                            Before = (JObject)msg["before"].DeepClone(),
                            After = (JObject)msg["after"].DeepClone(),
                            Materials = (JArray)msg["materials"].DeepClone(),
                            RemovedMods = (JArray)msg["removedMods"].DeepClone(),
                            NoOp = msg.Value<bool>("noOp"),
                            CanCommit = msg.Value<bool>("canCommit")
                        });
                }
                snapshotConfirmed = valid && entry.WebCmd == "snapshot"
                    && msg.Value<bool?>("success") == true
                    && string.Equals(
                        _latestSnapshotWebCallId,
                        entry.WebCallId,
                        StringComparison.Ordinal);
                if (snapshotConfirmed)
                {
                    valid = TryRememberSnapshotAuthorityLocked(
                        entry.WebCallId,
                        entry.PanelInstanceId,
                        entry.ViewSessionId,
                        msg["snapshot"] as JObject);
                    snapshotConfirmed = valid;
                }
                if (snapshotConfirmed)
                    snapshotStateRef = SnapshotStateReference(
                        msg["snapshot"] as JObject);
                if (entry.IsWrite)
                {
                    ClearSnapshotAuthorityLocked();
                    if (valid && msg.Value<bool?>("success") == true)
                    {
                        valid = TryRememberSnapshotAuthorityLocked(
                            entry.WebCallId,
                            entry.PanelInstanceId,
                            entry.ViewSessionId,
                            msg["snapshot"] as JObject);
                    }
                }
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
                if (entry.WebCmd == "preview")
                {
                    previewOutcome = PreviewResponseOutcome(valid, msg);
                    if (valid && msg.Value<bool?>("success") == true)
                        previewTokenRef = TokenReference(
                            ReadString(msg["tuningToken"]));
                    remainingPending = _pending.Count;
                }
                else if (entry.IsWrite)
                {
                    commitOutcome = PreviewResponseOutcome(valid, msg);
                    remainingPending = _pending.Count;
                    commitSnapshotPresent = valid && msg["snapshot"] is JObject;
                    commitTransactionIdPresent = valid
                        && IsOpaque(ReadString(msg["transactionId"]));
                    if (commitSnapshotPresent)
                        commitStateRef = SnapshotStateReference(
                            msg["snapshot"] as JObject);
                }
                web = valid ? SanitizeFlashResponse(msg) : new JObject
                {
                    ["success"] = false,
                    ["error"] = "malformed_response"
                };

                if (entry.IsWrite)
                {
                    _writeState = definitiveWrite ? "idle" : "needs_reconcile";
                    if (!definitiveWrite) web["requiresReconcile"] = true;
                    commitWriteState = _writeState;
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
                        ClearPreviewBindingsLocked();
                        ClearSnapshotAuthorityLocked();
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
                        ClearSnapshotAuthorityLocked();
                    }
                }
            }

            StampAndPost(web, entry);
            if (previewOutcome != null)
                LogPreviewSettled(entry, previewOutcome, remainingPending,
                    previewTokenRef);
            if (commitOutcome != null)
                LogCommitSettled(entry, commitOutcome, commitWriteState,
                    remainingPending, commitSnapshotPresent,
                    commitTransactionIdPresent, commitStateRef);
            if (snapshotConfirmed)
                LogManager.Log("event=equipment_tuning_snapshot_confirmed callId=" + entry.WebCallId
                    + " panelInstanceId=" + entry.PanelInstanceId
                    + " viewSessionId=" + entry.ViewSessionId
                    + " sourceKeyRef=" + SafeLogField(
                        AuthorityLogFormatter.CreateReference(
                            PreviewSourceKey(entry.Source)))
                    + " stateRef=" + SafeLogField(snapshotStateRef)
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
                ClearPreviewBindingsLocked();
                ClearSnapshotAuthorityLocked();
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
            LogManager.Log(AuthorityLogFormatter.FormatAuthorityFlashCallBound(
                "EquipmentTuningTask", entry.WebCallId, entry.FlashCallId,
                "workbench", entry.PanelInstanceId, entry.WebCmd,
                entry.FlashAction, entry.ViewSessionId));
            LogManager.Log("[EquipmentTuningTask] -> Flash: "
                + FormatFlashCommandForLog(flash));
            if (!_trySend(json + "\0")) HandleSendFailure(entry.FlashCallId);
        }

        private void HandleTimeout(int fid)
        {
            if (_disposed) return;
            PendingRequest entry;
            int remainingPending;
            lock (_lock)
            {
                if (!_pending.TryGetValue(fid, out entry)) return;
                CompletePendingLocked(entry);
                remainingPending = _pending.Count;
                if (entry.IsWrite)
                {
                    _writeState = "needs_reconcile";
                    ClearSnapshotAuthorityLocked();
                }
                if (entry.IsDetach)
                {
                    _activeViewSessionId = null;
                    _detachingViewSessionId = entry.ViewSessionId;
                }
            }
            RespondError(entry.WebCallId, entry.WebCmd, "timeout", entry.IsWrite || entry.IsReconcile,
                entry.PanelInstanceId, entry.ViewSessionId, entry.WriteEpoch);
            if (entry.WebCmd == "preview")
                LogPreviewSettled(entry, "timeout", remainingPending, null);
            else if (entry.IsWrite)
                LogCommitSettled(entry, "timeout", "needs_reconcile",
                    remainingPending, false, false, null);
            NotifyCoordinatorSettledIfReady();
        }

        private void HandleSendFailure(int fid)
        {
            PendingRequest entry;
            bool definitivelyNotSent;
            int remainingPending;
            lock (_lock)
            {
                if (!_pending.TryGetValue(fid, out entry)) return;
                CompletePendingLocked(entry);
                remainingPending = _pending.Count;
                definitivelyNotSent = entry.IsWrite || entry.IsDetach;
                if (entry.IsWrite)
                {
                    _writeState = "idle";
                    if (entry.ConsumedPreviewBinding
                        != null)
                    {
                        TryRememberPreviewBindingLocked(
                            entry.ConsumedPreviewBinding);
                    }
                }
                if (entry.IsDetach)
                {
                    _activeViewSessionId = entry.ViewSessionId;
                    _detachingViewSessionId = null;
                }
            }
            RespondError(entry.WebCallId, entry.WebCmd, definitivelyNotSent ? "not_sent" : "disconnected",
                entry.IsReconcile,
                entry.PanelInstanceId, entry.ViewSessionId, entry.WriteEpoch);
            if (entry.WebCmd == "preview")
                LogPreviewSettled(entry, "disconnected", remainingPending, null);
            else if (entry.IsWrite)
                LogCommitSettled(entry, "not_sent", "idle",
                    remainingPending, false, false, null);
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

        private void RotateViewSessionLocked(
            string viewSessionId)
        {
            if (!string.Equals(
                    _activeViewSessionId,
                    viewSessionId,
                    StringComparison.Ordinal))
            {
                ClearPreviewBindingsLocked();
                ClearSnapshotAuthorityLocked();
            }
            _activeViewSessionId =
                viewSessionId;
        }

        private void BeginSnapshotAuthorityRefreshLocked(
            string webCallId)
        {
            ClearSnapshotAuthorityLocked();
            _latestSnapshotWebCallId = webCallId;
        }

        private void BeginPreviewAttemptLocked(
            string webCallId)
        {
            ClearPreviewBindingsLocked();
            _latestPreviewWebCallId = webCallId;
        }

        private bool TryRememberSnapshotAuthorityLocked(
            string webCallId,
            string panelInstanceId,
            string viewSessionId,
            JObject snapshot)
        {
            JObject source;
            JObject equipment;
            JObject sanitizedSnapshot;
            Dictionary<string, JObject> tierCandidates;
            Dictionary<string, JObject> modCandidates;
            Dictionary<string, JObject> materials;
            if (!IsCallId(webCallId)
                || !IsOpaque(panelInstanceId)
                || !IsOpaque(viewSessionId)
                || !string.Equals(
                    _panelInstanceId,
                    panelInstanceId,
                    StringComparison.Ordinal)
                || !string.Equals(
                    _activeViewSessionId,
                    viewSessionId,
                    StringComparison.Ordinal)
                || snapshot == null
                || !TryNormalizeSourceRef(
                    snapshot["source"] as JObject,
                    out source)
                || !TrySanitizeTuningSnapshot(
                    snapshot,
                    source,
                    out sanitizedSnapshot)
                || !TrySanitizeEquipmentProjection(
                    sanitizedSnapshot["equipment"] as JObject,
                    out equipment)
                || !TryBuildCandidateAuthorityMap(
                    sanitizedSnapshot["tierCandidates"] as JArray,
                    out tierCandidates)
                || !TryBuildCandidateAuthorityMap(
                    sanitizedSnapshot["modCandidates"] as JArray,
                    out modCandidates)
                || !TryBuildMaterialAuthorityMap(
                    sanitizedSnapshot["materials"] as JArray,
                    out materials))
            {
                return false;
            }

            string sourceKey = PreviewSourceKey(source);
            if (string.IsNullOrEmpty(sourceKey)) return false;
            _snapshotAuthority = new SnapshotAuthority
            {
                SnapshotWebCallId = webCallId,
                PanelInstanceId = panelInstanceId,
                ViewSessionId = viewSessionId,
                SourceKey = sourceKey,
                Source = source,
                Equipment = equipment,
                TierCandidates = tierCandidates,
                ModCandidates = modCandidates,
                Materials = materials
            };
            _latestSnapshotWebCallId = null;
            return true;
        }

        private static bool TryBuildCandidateAuthorityMap(
            JArray candidates,
            out Dictionary<string, JObject> result)
        {
            result = null;
            if (candidates == null || candidates.Count > 512) return false;
            var map = new Dictionary<string, JObject>(StringComparer.Ordinal);
            foreach (JToken token in candidates)
            {
                JObject candidate = token as JObject;
                string candidateKey = ReadString(
                    candidate != null ? candidate["candidateKey"] : null);
                if (!IsOpaque(candidateKey)
                    || map.ContainsKey(candidateKey)) return false;
                map[candidateKey] = (JObject)candidate.DeepClone();
            }
            result = map;
            return true;
        }

        private static bool TryBuildMaterialAuthorityMap(
            JArray materials,
            out Dictionary<string, JObject> result)
        {
            result = null;
            if (materials == null || materials.Count > 512) return false;
            var map = new Dictionary<string, JObject>(StringComparer.Ordinal);
            foreach (JToken token in materials)
            {
                JObject material = token as JObject;
                string itemName = ReadString(
                    material != null ? material["itemName"] : null);
                if (!IsIdentityText(itemName, 256)
                    || map.ContainsKey(itemName)) return false;
                map[itemName] = (JObject)material.DeepClone();
            }
            result = map;
            return true;
        }

        private static Dictionary<string, JObject> CloneAuthorityMap(
            Dictionary<string, JObject> source)
        {
            if (source == null) return null;
            var result = new Dictionary<string, JObject>(StringComparer.Ordinal);
            foreach (KeyValuePair<string, JObject> pair in source)
                result[pair.Key] = (JObject)pair.Value.DeepClone();
            return result;
        }

        private bool TryBindPreviewAuthorityLocked(
            PendingRequest entry)
        {
            SnapshotAuthority authority = _snapshotAuthority;
            if (entry == null
                || authority == null
                || !string.Equals(
                    authority.PanelInstanceId,
                    entry.PanelInstanceId,
                    StringComparison.Ordinal)
                || !string.Equals(
                    authority.ViewSessionId,
                    entry.ViewSessionId,
                    StringComparison.Ordinal)
                || !string.Equals(
                    authority.SourceKey,
                    PreviewSourceKey(entry.Source),
                    StringComparison.Ordinal)
                || !JToken.DeepEquals(
                    authority.Source,
                    entry.Source))
            {
                return false;
            }

            entry.SnapshotEquipment =
                (JObject)authority.Equipment.DeepClone();
            entry.SnapshotMaterials =
                CloneAuthorityMap(authority.Materials);
            if (entry.SnapshotMaterials == null) return false;
            if (entry.Operation == "install_tier")
            {
                return TryFreezeCandidateAuthority(
                    authority.TierCandidates,
                    entry.CandidateKey,
                    out entry.CandidateAuthority);
            }
            if (entry.Operation == "install_mod"
                || entry.Operation == "detach_mod")
            {
                return TryFreezeCandidateAuthority(
                    authority.ModCandidates,
                    entry.CandidateKey,
                    out entry.CandidateAuthority);
            }
            if (entry.Operation == "replace_mod")
            {
                string replaceCandidateKey = ReadString(
                    entry.NormalizedPayload != null
                        ? entry.NormalizedPayload["replaceCandidateKey"]
                        : null);
                return TryFreezeCandidateAuthority(
                        authority.ModCandidates,
                        entry.CandidateKey,
                        out entry.CandidateAuthority)
                    && TryFreezeCandidateAuthority(
                        authority.ModCandidates,
                        replaceCandidateKey,
                        out entry.ReplaceCandidateAuthority);
            }
            return true;
        }

        private bool TryBindTooltipAuthorityLocked(
            PendingRequest entry)
        {
            if (entry == null) return false;
            // Legacy tooltip requests have no source and remain read-only compatible.
            if (entry.Source == null) return true;

            SnapshotAuthority authority = _snapshotAuthority;
            return authority != null
                && string.Equals(
                    authority.PanelInstanceId,
                    entry.PanelInstanceId,
                    StringComparison.Ordinal)
                && string.Equals(
                    authority.ViewSessionId,
                    entry.ViewSessionId,
                    StringComparison.Ordinal)
                && string.Equals(
                    authority.SourceKey,
                    PreviewSourceKey(entry.Source),
                    StringComparison.Ordinal)
                && JToken.DeepEquals(
                    authority.Source,
                    entry.Source)
                && ((authority.TierCandidates != null
                        && authority.TierCandidates.ContainsKey(entry.CandidateKey))
                    || (authority.ModCandidates != null
                        && authority.ModCandidates.ContainsKey(entry.CandidateKey)));
        }

        private static bool TryFreezeCandidateAuthority(
            Dictionary<string, JObject> candidates,
            string candidateKey,
            out JObject authority)
        {
            authority = null;
            JObject candidate;
            if (candidates == null
                || !IsOpaque(candidateKey)
                || !candidates.TryGetValue(
                    candidateKey,
                    out candidate)) return false;
            authority = (JObject)candidate.DeepClone();
            return true;
        }

        private void ClearSnapshotAuthorityLocked()
        {
            _snapshotAuthority = null;
            _latestSnapshotWebCallId = null;
        }

        private bool TryRememberPreviewBindingLocked(
            PreviewBinding binding)
        {
            JObject normalizedSource;
            if (binding == null
                || !IsOpaque(binding.TuningToken)
                || string.IsNullOrEmpty(binding.TokenRef)
                || !IsCallId(binding.PreviewWebCallId)
                || !IsOpaque(binding.PanelInstanceId)
                || !IsOpaque(binding.ViewSessionId)
                || !Operations.Contains(
                    binding.Operation)
                || string.IsNullOrEmpty(binding.SourceKey)
                || binding.Before == null
                || binding.After == null
                || binding.Materials == null
                || binding.RemovedMods == null
                || !binding.CanCommit
                || !TryNormalizeSourceRef(
                    binding.Source,
                    out normalizedSource))
            {
                return false;
            }
            binding.Source = normalizedSource;
            if (!string.Equals(
                    _latestPreviewWebCallId,
                    binding.PreviewWebCallId,
                    StringComparison.Ordinal)) return false;

            PreviewBinding existing;
            if (_previewBindings.TryGetValue(
                    binding.TuningToken,
                    out existing))
            {
                return string.Equals(
                        existing.PanelInstanceId,
                        binding.PanelInstanceId,
                        StringComparison.Ordinal)
                    && string.Equals(
                        existing.ViewSessionId,
                        binding.ViewSessionId,
                        StringComparison.Ordinal)
                    && string.Equals(
                        existing.Operation,
                        binding.Operation,
                        StringComparison.Ordinal)
                    && string.Equals(
                        existing.PreviewWebCallId,
                        binding.PreviewWebCallId,
                        StringComparison.Ordinal)
                    && string.Equals(
                        existing.CandidateKey,
                        binding.CandidateKey,
                        StringComparison.Ordinal)
                    && string.Equals(
                        existing.IntentKey,
                        binding.IntentKey,
                        StringComparison.Ordinal)
                    && string.Equals(
                        existing.SourceKey,
                        binding.SourceKey,
                        StringComparison.Ordinal)
                    && string.Equals(
                        existing.TokenRef,
                        binding.TokenRef,
                        StringComparison.Ordinal)
                    && JToken.DeepEquals(
                        existing.Source,
                        binding.Source)
                    && JToken.DeepEquals(
                        existing.Before,
                        binding.Before)
                    && JToken.DeepEquals(
                        existing.After,
                        binding.After)
                    && JToken.DeepEquals(
                        existing.Materials,
                        binding.Materials)
                    && JToken.DeepEquals(
                        existing.RemovedMods,
                        binding.RemovedMods)
                    && existing.NoOp == binding.NoOp
                    && existing.CanCommit == binding.CanCommit;
            }

            _previewBindings[
                binding.TuningToken] = binding;
            binding.OrderNode =
                _previewBindingOrder.AddLast(
                    binding);
            while (_previewBindings.Count
                > PreviewBindingCapacity)
            {
                PreviewBinding oldest =
                    _previewBindingOrder.First.Value;
                _previewBindingOrder.RemoveFirst();
                oldest.OrderNode = null;
                _previewBindings.Remove(
                    oldest.TuningToken);
            }
            return true;
        }

        private bool TryConsumePreviewBindingLocked(
            string tuningToken,
            string panelInstanceId,
            string viewSessionId,
            out PreviewBinding binding)
        {
            binding = null;
            PreviewBinding candidate;
            if (!IsOpaque(tuningToken)
                || !_previewBindings.TryGetValue(
                    tuningToken, out candidate)
                || !string.Equals(
                    candidate.PanelInstanceId,
                    panelInstanceId,
                    StringComparison.Ordinal)
                || !string.Equals(
                    candidate.ViewSessionId,
                    viewSessionId,
                    StringComparison.Ordinal))
            {
                return false;
            }
            _previewBindings.Remove(
                tuningToken);
            if (candidate.OrderNode != null)
            {
                _previewBindingOrder.Remove(
                    candidate.OrderNode);
                candidate.OrderNode = null;
            }
            binding = candidate;
            return true;
        }

        private void ClearPreviewBindingsLocked()
        {
            _previewBindings.Clear();
            _previewBindingOrder.Clear();
            _latestPreviewWebCallId = null;
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
                bool tooltipHasSource = payload["source"] != null;
                var tooltipKeys = tooltipHasSource
                    ? Set("v", "viewSessionId", "candidateKey", "source")
                    : Set("v", "viewSessionId", "candidateKey");
                if (!IsExactObject(payload, tooltipKeys)) return false;
                viewSessionId = ReadString(payload["viewSessionId"]);
                candidateKey = ReadString(payload["candidateKey"]);
                if (!IsOpaque(viewSessionId) || !IsSafeText(candidateKey, 1, 128)) return false;
                result["viewSessionId"] = viewSessionId;
                result["candidateKey"] = candidateKey;
                if (tooltipHasSource)
                {
                    // 可选 source 让 AS2 能试算候选装上当前装备的属性 diff；
                    // tooltip 零写，复用与 snapshot 相同的 lease 规范化
                    JObject tooltipSource;
                    if (!TryNormalizeSourceRef(
                            payload["source"] as JObject,
                            out tooltipSource))
                    {
                        return false;
                    }
                    result["source"] = tooltipSource;
                }
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
            if (hasReconcile && cmd != "snapshot")
                return false;
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
                if (!IsExactObject(payload, keys)
                    || !TryNormalizeSourceRef(
                        payload["source"] as JObject,
                        out source))
                    return false;
                result["source"] = source;
            }
            else if (cmd == "preview")
            {
                operation = ReadString(payload["operation"]);
                if (!Operations.Contains(operation)) return false;
                var keys = new HashSet<string>(StringComparer.Ordinal)
                    { "v", "viewSessionId", "operation", "source" };
                if (operation == "enhance") keys.Add("targetLevel");
                else if (operation == "convert") keys.Add("target");
                else if (operation != "detach_all_mods") keys.Add("candidateKey");
                if (operation == "replace_mod") keys.Add("replaceCandidateKey");
                if (!IsExactObject(payload, keys)) return false;

                JObject source;
                if (!TryNormalizeSourceRef(
                        payload["source"] as JObject,
                        out source))
                {
                    return false;
                }
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
                    if (!TryNormalizeInventorySourceRef(
                            payload["target"] as JObject,
                            out target))
                    {
                        return false;
                    }
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

        private static bool TryNormalizeSourceRef(
            JObject input,
            out JObject normalized)
        {
            normalized = null;
            string sourceKind =
                ReadString(
                    input != null
                        ? input["sourceKind"] : null);
            if (sourceKind == "inventory")
                return TryNormalizeInventorySourceRef(
                    input, out normalized);
            if (sourceKind != "loadout"
                || !IsExactObject(
                    input,
                    Set("sourceKind",
                        "sessionGeneration",
                        "slotKey",
                        "expectedLoadoutRevision")))
            {
                return false;
            }

            int sessionGeneration;
            int expectedLoadoutRevision;
            string slotKey =
                ReadString(input["slotKey"]);
            if (!TryReadInteger(
                    input["sessionGeneration"],
                    1,
                    int.MaxValue,
                    out sessionGeneration)
                || !CharacterBuildProtocol
                    .IsEquipmentSlotKey(slotKey)
                || !TryReadInteger(
                    input["expectedLoadoutRevision"],
                    0,
                    int.MaxValue,
                    out expectedLoadoutRevision))
            {
                return false;
            }
            normalized = new JObject
            {
                ["sourceKind"] = "loadout",
                ["sessionGeneration"] =
                    sessionGeneration,
                ["slotKey"] = slotKey,
                ["expectedLoadoutRevision"] =
                    expectedLoadoutRevision
            };
            return true;
        }

        private static bool TryNormalizeInventorySourceRef(
            JObject input,
            out JObject normalized)
        {
            normalized = null;
            if (!IsExactObject(
                    input,
                    Set("sourceKind", "containerId",
                        "slot", "expectedLease"))
                || ReadString(input["sourceKind"])
                    != "inventory"
                || ReadString(input["containerId"])
                    != "背包")
            {
                return false;
            }
            int slot;
            string lease = ReadString(input["expectedLease"]);
            if (!TryReadInteger(input["slot"], 0, 49, out slot) || !IsLease(lease)) return false;
            normalized = new JObject
            {
                ["sourceKind"] = "inventory",
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

            if (entry.WebCmd == "snapshot")
                return IsSnapshotResponse(
                    msg, entry.Source);
            if (entry.WebCmd == "preview")
                return IsPreviewResponse(
                    msg, entry);
            if (entry.WebCmd == "commit")
                return IsCommitResponse(
                    msg, entry);
            if (entry.WebCmd == "detach") return true;
            return ReadString(msg["candidateKey"]) == entry.CandidateKey
                && msg["introHTML"] != null && msg["introHTML"].Type == JTokenType.String
                && msg["descHTML"] != null && msg["descHTML"].Type == JTokenType.String
                && msg["itemType"] != null && msg["itemType"].Type == JTokenType.String
                && msg["itemUse"] != null && msg["itemUse"].Type == JTokenType.String
                && IsIdentityTextToken(msg["text"], 256)
                && TooltipStatPairsValid(msg);
        }

        // 候选试算 diff 是可选的成对字段；要么齐全且逐行合法，要么完全缺席
        private static bool TooltipStatPairsValid(JObject msg)
        {
            if (msg["statsBefore"] == null && msg["statsAfter"] == null) return true;
            JArray statsBefore;
            JArray statsAfter;
            return TrySanitizeStatRows(msg["statsBefore"] as JArray, out statsBefore)
                && TrySanitizeStatRows(msg["statsAfter"] as JArray, out statsAfter);
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
                    keys.Add("itemType"); keys.Add("itemUse"); keys.Add("text");
                    keys.Add("statsBefore"); keys.Add("statsAfter");
                }
            }
            foreach (JProperty property in msg.Properties())
                if (!keys.Contains(property.Name)) return false;
            return true;
        }

        private static bool IsSnapshotResponse(
            JObject msg,
            JObject expectedSource)
        {
            JObject snapshot = msg["snapshot"] as JObject;
            JObject sanitized;
            return TrySanitizeTuningSnapshot(
                snapshot, expectedSource, out sanitized);
        }

        private static bool TrySanitizeTuningSnapshot(
            JObject snapshot,
            JObject expectedSource,
            out JObject sanitized)
        {
            sanitized = null;
            string gender = snapshot != null ? ReadString(snapshot["gender"]) : null;
            JArray sanitizedTierCandidates;
            JArray sanitizedModCandidates;
            JObject equipment;
            JArray materials;
            int materialRevision;
            int inventoryRevision;
            if (!IsExactObject(snapshot, SnapshotKeys)
                || !IsExactSource(
                    expectedSource,
                    snapshot["source"] as JObject)
                || !TrySanitizeEquipmentProjection(
                    snapshot["equipment"] as JObject,
                    out equipment)
                || !IsEnhanceProjection(
                    snapshot["enhance"] as JObject,
                    equipment)
                || !TrySanitizeTuningCandidates(
                    snapshot,
                    out sanitizedTierCandidates,
                    out sanitizedModCandidates)
                || !TrySanitizeSnapshotMaterials(
                    snapshot["materials"] as JArray,
                    out materials)
                || !TryReadInteger(
                    snapshot["materialRevision"],
                    0,
                    int.MaxValue,
                    out materialRevision)
                || !TryReadInteger(
                    snapshot["inventoryRevision"],
                    0,
                    int.MaxValue,
                    out inventoryRevision)
                || !SnapshotCandidatesMatchEquipment(
                    sanitizedModCandidates,
                    equipment))
                return false;
            if (gender != "男" && gender != "女") return false;
            sanitized = (JObject)snapshot.DeepClone();
            sanitized["equipment"] = equipment;
            sanitized["tierCandidates"] = sanitizedTierCandidates;
            sanitized["modCandidates"] = sanitizedModCandidates;
            sanitized["materials"] = materials;
            return true;
        }

        private static bool IsEnhanceProjection(
            JObject enhance,
            JObject equipment)
        {
            int currentLevel;
            int maxLevel;
            int availableMaxLevel;
            int hardMaxLevel;
            return IsExactObject(enhance, EnhanceProjectionKeys)
                && TryReadInteger(
                    enhance["currentLevel"], 1, int.MaxValue,
                    out currentLevel)
                && TryReadInteger(
                    enhance["maxLevel"], 1, int.MaxValue,
                    out maxLevel)
                && TryReadInteger(
                    enhance["availableMaxLevel"], 1, int.MaxValue,
                    out availableMaxLevel)
                && TryReadInteger(
                    enhance["hardMaxLevel"], 1, int.MaxValue,
                    out hardMaxLevel)
                && currentLevel == equipment.Value<int>("level")
                && maxLevel == equipment.Value<int>("maxLevel")
                && availableMaxLevel == maxLevel
                && hardMaxLevel == equipment.Value<int>("hardMaxLevel");
        }

        private static bool TrySanitizeSnapshotMaterials(
            JArray input,
            out JArray sanitized)
        {
            sanitized = null;
            if (input == null || input.Count > 512) return false;
            var result = new JArray();
            var names = new HashSet<string>(StringComparer.Ordinal);
            foreach (JToken token in input)
            {
                JObject row = token as JObject;
                int count;
                string itemName = ReadString(
                    row != null ? row["itemName"] : null);
                if (!IsExactObject(row, SnapshotMaterialKeys)
                    || !IsIdentityText(itemName, 256)
                    || !IsIdentityTextToken(row["displayName"], 256)
                    || !IsIdentityTextToken(row["icon"], 256)
                    || !names.Add(itemName)
                    || !TryReadInteger(
                        row["count"], 0, int.MaxValue,
                        out count))
                {
                    return false;
                }
                result.Add(row.DeepClone());
            }
            sanitized = result;
            return true;
        }

        private static bool SnapshotCandidatesMatchEquipment(
            JArray candidates,
            JObject equipment)
        {
            JArray mods = equipment != null
                ? equipment["mods"] as JArray : null;
            if (candidates == null || mods == null) return false;
            var installed = new HashSet<string>(StringComparer.Ordinal);
            foreach (JToken token in candidates)
            {
                JObject candidate = token as JObject;
                if (candidate != null
                    && candidate.Value<bool?>("installed") == true)
                {
                    installed.Add(ReadString(candidate["itemName"]));
                }
            }
            if (installed.Count != mods.Count) return false;
            foreach (JToken token in mods)
            {
                if (!installed.Contains(ReadString(token))) return false;
            }
            return true;
        }

        private static bool TrySanitizeTuningCandidates(
            JObject snapshot,
            out JArray tierCandidates,
            out JArray modCandidates)
        {
            tierCandidates = null;
            modCandidates = null;
            return snapshot != null
                && TrySanitizeCandidateArray(
                    snapshot["tierCandidates"] as JArray,
                    false,
                    out tierCandidates)
                && TrySanitizeCandidateArray(
                    snapshot["modCandidates"] as JArray,
                    true,
                    out modCandidates);
        }

        private static bool TrySanitizeCandidateArray(
            JArray input,
            bool isMod,
            out JArray sanitized)
        {
            sanitized = null;
            if (input == null || input.Count > 512) return false;
            var result = new JArray();
            var candidateKeys = new HashSet<string>(StringComparer.Ordinal);
            foreach (JToken token in input)
            {
                JObject candidate;
                if (!TrySanitizeCandidate(token as JObject, isMod, out candidate))
                    return false;
                string candidateKey = ReadString(candidate["candidateKey"]);
                if (!candidateKeys.Add(candidateKey)) return false;
                result.Add(candidate);
            }
            sanitized = result;
            return true;
        }

        private static bool TrySanitizeCandidate(
            JObject input,
            bool isMod,
            out JObject sanitized)
        {
            sanitized = null;
            HashSet<string> allowed = isMod ? ModCandidateKeys : TierCandidateKeys;
            if (input == null) return false;
            foreach (JProperty property in input.Properties())
                if (!allowed.Contains(property.Name)) return false;

            string candidateKey = ReadString(input["candidateKey"]);
            string itemName = ReadString(input["itemName"]);
            string displayName = ReadString(input["displayName"]);
            string icon = ReadString(input["icon"]);
            int owned;
            if (!IsOpaque(candidateKey)
                || !IsIdentityText(itemName, 256)
                || !IsIdentityText(displayName, 256)
                || !IsIdentityText(icon, 256)
                || !TryReadInteger(input["owned"], 0, int.MaxValue, out owned)
                || input["available"] == null
                || input["available"].Type != JTokenType.Boolean
                || !IsTextToken(input["reason"], 0, 256))
            {
                return false;
            }

            if (isMod)
            {
                int availabilityCode;
                if (input["installed"] == null
                    || input["installed"].Type != JTokenType.Boolean
                    || !TryReadInteger(input["availabilityCode"], -100, 100,
                        out availabilityCode)
                    || !(input["replaceableFrom"] is JArray replaceableFrom)
                    || !IsOpaqueArray(replaceableFrom)
                    || !IsTextToken(input["grade"], 1, 64)
                    || !IsTextToken(input["scope"], 1, 64)
                    || !IsTextToken(input["role"], 1, 64))
                {
                    return false;
                }
                foreach (string optional in new[] {
                    "gradeLabel", "gradeColor", "scopeLabel", "roleLabel", "symbol" })
                {
                    if (input[optional] != null
                        && !IsTextToken(input[optional], 1, 128)) return false;
                }
            }
            else if (!IsTextToken(input["tierName"], 1, 64))
            {
                return false;
            }

            var result = new JObject();
            foreach (string key in allowed)
                if (input[key] != null) result[key] = input[key].DeepClone();
            sanitized = result;
            return true;
        }

        private static bool IsOpaqueArray(JArray values)
        {
            if (values == null || values.Count > 512) return false;
            var seen = new HashSet<string>(StringComparer.Ordinal);
            foreach (JToken token in values)
            {
                string value = ReadString(token);
                if (!IsOpaque(value) || !seen.Add(value)) return false;
            }
            return true;
        }

        private static bool IsTextToken(JToken token, int min, int max)
        {
            return token != null && token.Type == JTokenType.String
                && IsSafeText(token.Value<string>(), min, max);
        }

        private static bool IsIdentityTextToken(
            JToken token,
            int max)
        {
            return token != null
                && token.Type == JTokenType.String
                && IsIdentityText(token.Value<string>(), max);
        }

        private static bool IsIdentityText(
            string value,
            int max)
        {
            if (!IsSafeText(value, 1, max)
                || string.IsNullOrWhiteSpace(value)) return false;
            return !string.Equals(
                value.Trim(),
                "undefined",
                StringComparison.OrdinalIgnoreCase);
        }

        private static bool IsPreviewResponse(
            JObject msg,
            PendingRequest entry)
        {
            JObject before;
            JObject after;
            JArray materials;
            JArray removedMods;
            bool noOp;
            bool canCommit;
            return entry != null
                && entry.Source != null
                && TryReadTuningProjectionResponse(
                    msg,
                    entry.Operation,
                    true,
                    out before,
                    out after,
                    out materials,
                    out removedMods,
                    out noOp,
                    out canCommit)
                && ProjectionSourcesMatchPreview(
                    before, after, entry)
                && PreviewAuthorityMatches(
                    entry,
                    before,
                    after,
                    materials,
                    removedMods)
                && ValidatePreviewTransition(
                    entry,
                    before,
                    after,
                    materials,
                    removedMods,
                    noOp);
        }

        private static bool TryReadTuningProjectionResponse(
            JObject msg,
            string expectedOperation,
            bool expectedCanCommit,
            out JObject before,
            out JObject after,
            out JArray materials,
            out JArray removedMods,
            out bool noOp,
            out bool canCommit)
        {
            before = null;
            after = null;
            materials = null;
            removedMods = null;
            noOp = false;
            canCommit = false;
            string operation = ReadString(msg != null ? msg["operation"] : null);
            bool expectTarget = operation == "convert";
            if (!Operations.Contains(operation)
                || operation != expectedOperation
                || !IsOpaque(ReadString(msg["tuningToken"]))
                || msg["noOp"] == null
                || msg["noOp"].Type != JTokenType.Boolean
                || msg["canCommit"] == null
                || msg["canCommit"].Type != JTokenType.Boolean
                || msg.Value<bool>("canCommit") != expectedCanCommit
                || !TrySanitizeTuningProjection(
                    msg["before"] as JObject,
                    expectTarget,
                    out before)
                || !TrySanitizeTuningProjection(
                    msg["after"] as JObject,
                    expectTarget,
                    out after)
                || !TrySanitizeMaterialPlan(
                    msg["materials"] as JArray,
                    out materials)
                || !TrySanitizeStringArray(
                    msg["removedMods"] as JArray,
                    64,
                    out removedMods))
            {
                return false;
            }
            noOp = msg.Value<bool>("noOp");
            canCommit = msg.Value<bool>("canCommit");
            return true;
        }

        private static bool TrySanitizeTuningProjection(
            JObject input,
            bool expectTarget,
            out JObject sanitized)
        {
            sanitized = null;
            HashSet<string> keys = expectTarget
                ? Set("source", "target")
                : Set("source");
            JObject source;
            JObject target = null;
            if (!IsExactObject(input, keys)
                || !TrySanitizeTuningSubject(
                    input["source"] as JObject,
                    out source)
                || (expectTarget
                    && !TrySanitizeTuningSubject(
                        input["target"] as JObject,
                        out target)))
            {
                return false;
            }
            sanitized = new JObject { ["source"] = source };
            if (expectTarget) sanitized["target"] = target;
            return true;
        }

        private static bool TrySanitizeTuningSubject(
            JObject input,
            out JObject sanitized)
        {
            sanitized = null;
            JObject source;
            JObject equipment;
            if (!IsExactObject(input, TuningSubjectKeys)
                || !TryNormalizeSourceRef(
                    input["source"] as JObject,
                    out source)
                || !TrySanitizeEquipmentProjection(
                    input["equipment"] as JObject,
                    out equipment))
            {
                return false;
            }
            sanitized = new JObject
            {
                ["source"] = source,
                ["equipment"] = equipment
            };
            return true;
        }

        private static bool TrySanitizeEquipmentProjection(
            JObject input,
            out JObject sanitized)
        {
            sanitized = null;
            var keys = new HashSet<string>(
                EquipmentProjectionKeys,
                StringComparer.Ordinal);
            bool hasModSlotCapacity = input != null
                && input["modSlotCapacity"] != null;
            if (hasModSlotCapacity) keys.Add("modSlotCapacity");
            bool hasStats = input != null
                && input["stats"] != null;
            if (hasStats) keys.Add("stats");
            int level;
            int maxLevel;
            int hardMaxLevel;
            int modSlotCapacity = 0;
            double lastUpdate;
            JArray mods;
            JArray stats = null;
            string type = ReadString(input != null ? input["type"] : null);
            if (!IsExactObject(input, keys)
                || !IsIdentityTextToken(input["name"], 256)
                || !IsIdentityTextToken(input["displayName"], 256)
                || !IsIdentityTextToken(input["icon"], 256)
                || (type != "武器" && type != "防具")
                || !IsTextToken(input["use"], 1, 128)
                || !IsTextToken(input["tier"], 0, 128)
                || !TryReadInteger(
                    input["level"], 1, int.MaxValue,
                    out level)
                || !TryReadInteger(
                    input["maxLevel"], 1, int.MaxValue,
                    out maxLevel)
                || !TryReadInteger(
                    input["hardMaxLevel"], 1, int.MaxValue,
                    out hardMaxLevel)
                || maxLevel > hardMaxLevel
                || level > hardMaxLevel
                || !TryReadFiniteNumber(
                    input["lastUpdate"],
                    0,
                    9007199254740991d,
                    out lastUpdate)
                || (hasModSlotCapacity
                    && !TryReadInteger(
                        input["modSlotCapacity"],
                        0,
                        64,
                        out modSlotCapacity))
                || !TrySanitizeStringArray(
                    input["mods"] as JArray,
                    64,
                    out mods)
                || (hasStats
                    && !TrySanitizeStatRows(
                        input["stats"] as JArray,
                        out stats)))
            {
                return false;
            }
            sanitized = (JObject)input.DeepClone();
            sanitized["mods"] = mods;
            if (hasStats) sanitized["stats"] = stats;
            return true;
        }

        private static JObject StripStatRows(JObject equipment)
        {
            if (equipment == null || equipment["stats"] == null)
            {
                return equipment;
            }
            JObject clone = (JObject)equipment.DeepClone();
            clone.Remove("stats");
            return clone;
        }

        private static bool TrySanitizeStatRows(
            JArray input,
            out JArray sanitized)
        {
            sanitized = null;
            if (input == null || input.Count > 64) return false;
            var result = new JArray();
            var keys = new HashSet<string>(StringComparer.Ordinal);
            foreach (JToken token in input)
            {
                JObject row = token as JObject;
                string key = ReadString(row != null ? row["key"] : null);
                double value;
                if (!IsExactObject(row, StatRowKeys)
                    || !IsTextToken(row["key"], 1, 64)
                    || !keys.Add(key)
                    || !IsTextToken(row["label"], 1, 128)
                    || !TryReadFiniteNumber(
                        row["value"],
                        -1e9d,
                        1e9d,
                        out value))
                {
                    return false;
                }
                // 保留原始数值 token 类型（Integer/Float）：preview binding 以原文深克隆存储，
                // commit 经 sanitize 后与 binding 做 DeepEquals，统一成 double 会造成类型漂移
                result.Add(new JObject
                {
                    ["key"] = key,
                    ["label"] = ReadString(row["label"]),
                    ["value"] = row["value"].DeepClone()
                });
            }
            sanitized = result;
            return true;
        }

        private static bool TrySanitizeMaterialPlan(
            JArray input,
            out JArray sanitized)
        {
            sanitized = null;
            if (input == null || input.Count > 512) return false;
            var result = new JArray();
            var names = new HashSet<string>(StringComparer.Ordinal);
            foreach (JToken token in input)
            {
                JObject row = token as JObject;
                string itemName = ReadString(
                    row != null ? row["itemName"] : null);
                int before;
                int delta;
                int after;
                if (!IsExactObject(row, MaterialPlanKeys)
                    || !IsIdentityText(itemName, 256)
                    || !IsIdentityTextToken(row["displayName"], 256)
                    || !IsIdentityTextToken(row["icon"], 256)
                    || !names.Add(itemName)
                    || !TryReadInteger(
                        row["before"], 0, int.MaxValue,
                        out before)
                    || !TryReadInteger(
                        row["delta"], int.MinValue, int.MaxValue,
                        out delta)
                    || delta == 0
                    || !TryReadInteger(
                        row["after"], 0, int.MaxValue,
                        out after)
                    || (long)before + delta != after)
                {
                    return false;
                }
                result.Add(row.DeepClone());
            }
            sanitized = result;
            return true;
        }

        private static bool TrySanitizeStringArray(
            JArray input,
            int maximumCount,
            out JArray sanitized)
        {
            sanitized = null;
            if (input == null || input.Count > maximumCount) return false;
            var result = new JArray();
            var values = new HashSet<string>(StringComparer.Ordinal);
            foreach (JToken token in input)
            {
                string value = ReadString(token);
                if (!IsSafeText(value, 1, 256)
                    || !values.Add(value)) return false;
                result.Add(value);
            }
            sanitized = result;
            return true;
        }

        private static bool ProjectionSourcesMatchPreview(
            JObject before,
            JObject after,
            PendingRequest entry)
        {
            JObject expectedTarget = entry.NormalizedPayload != null
                ? entry.NormalizedPayload["target"] as JObject
                : null;
            return IsExactSource(
                    entry.Source,
                    (JObject)before["source"]["source"])
                && IsExactSource(
                    entry.Source,
                    (JObject)after["source"]["source"])
                && (entry.Operation != "convert"
                    || (IsExactSource(
                            expectedTarget,
                            (JObject)before["target"]["source"])
                        && IsExactSource(
                            expectedTarget,
                            (JObject)after["target"]["source"])));
        }

        private static bool PreviewAuthorityMatches(
            PendingRequest entry,
            JObject before,
            JObject after,
            JArray materials,
            JArray removedMods)
        {
            JObject beforeEquipment = before != null
                && before["source"] is JObject beforeSource
                ? beforeSource["equipment"] as JObject
                : null;
            if (entry == null
                || entry.SnapshotEquipment == null
                || entry.SnapshotMaterials == null
                || beforeEquipment == null
                // stats 是 preview 投影新增的派生展示数据，snapshot 不携带；
                // 比对前剥离，身份字段仍保持 DeepEquals 级权威绑定
                || !JToken.DeepEquals(
                    StripStatRows(entry.SnapshotEquipment),
                    StripStatRows(beforeEquipment))
                || !PreviewMaterialsMatchSnapshot(
                    materials,
                    entry.SnapshotMaterials))
            {
                return false;
            }

            string operation = entry.Operation;
            if (operation == "enhance"
                || operation == "convert"
                || operation == "detach_all_mods") return true;

            JObject candidate = entry.CandidateAuthority;
            if (candidate == null
                || ReadString(candidate["candidateKey"])
                    != entry.CandidateKey) return false;
            string candidateName = ReadString(candidate["itemName"]);
            JObject afterEquipment = after != null
                && after["source"] is JObject afterSource
                ? afterSource["equipment"] as JObject
                : null;
            JArray afterMods = afterEquipment != null
                ? afterEquipment["mods"] as JArray : null;
            if (string.IsNullOrEmpty(candidateName)
                || afterEquipment == null
                || afterMods == null) return false;

            if (operation == "install_tier")
            {
                return candidate.Value<bool?>("available") == true
                    && candidate.Value<int>("owned") > 0
                    && ReadString(candidate["tierName"])
                        == ReadString(afterEquipment["tier"])
                    && MaterialMatchesCandidate(
                        materials,
                        candidate,
                        -1);
            }
            if (operation == "install_mod")
            {
                return candidate.Value<bool?>("installed") == false
                    && candidate.Value<bool?>("available") == true
                    && candidate.Value<int>("owned") > 0
                    && ContainsString(afterMods, candidateName)
                    && MaterialMatchesCandidate(
                        materials,
                        candidate,
                        -1);
            }
            if (operation == "replace_mod")
            {
                JObject replaced = entry.ReplaceCandidateAuthority;
                string replaceCandidateKey = ReadString(
                    entry.NormalizedPayload != null
                        ? entry.NormalizedPayload["replaceCandidateKey"]
                        : null);
                string replacedName = ReadString(
                    replaced != null ? replaced["itemName"] : null);
                JArray replaceableFrom = candidate["replaceableFrom"] as JArray;
                return replaced != null
                    && ReadString(replaced["candidateKey"])
                        == replaceCandidateKey
                    && candidate.Value<bool?>("installed") == false
                    && candidate.Value<int>("owned") > 0
                    && replaced.Value<bool?>("installed") == true
                    && ContainsString(
                        replaceableFrom,
                        replaceCandidateKey)
                    && ContainsString(afterMods, candidateName)
                    && ContainsString(removedMods, replacedName)
                    && MaterialMatchesCandidate(
                        materials,
                        candidate,
                        -1)
                    && MaterialMatchesCandidate(
                        materials,
                        replaced,
                        1);
            }
            return operation == "detach_mod"
                && candidate.Value<bool?>("installed") == true
                && ContainsString(removedMods, candidateName)
                && MaterialMatchesCandidate(
                    materials,
                    candidate,
                    1);
        }

        private static bool PreviewMaterialsMatchSnapshot(
            JArray materials,
            Dictionary<string, JObject> snapshotMaterials)
        {
            if (materials == null || snapshotMaterials == null) return false;
            foreach (JToken token in materials)
            {
                JObject material = token as JObject;
                string itemName = ReadString(
                    material != null ? material["itemName"] : null);
                JObject snapshotMaterial;
                if (string.IsNullOrEmpty(itemName)
                    || !snapshotMaterials.TryGetValue(
                        itemName,
                        out snapshotMaterial)
                    || !JToken.DeepEquals(
                        material["displayName"],
                        snapshotMaterial["displayName"])
                    || !JToken.DeepEquals(
                        material["icon"],
                        snapshotMaterial["icon"])
                    || material.Value<int>("before")
                        != snapshotMaterial.Value<int>("count"))
                {
                    return false;
                }
            }
            return true;
        }

        private static bool MaterialMatchesCandidate(
            JArray materials,
            JObject candidate,
            int expectedDelta)
        {
            if (materials == null || candidate == null) return false;
            string itemName = ReadString(candidate["itemName"]);
            foreach (JToken token in materials)
            {
                JObject material = token as JObject;
                if (ReadString(
                        material != null
                            ? material["itemName"] : null)
                        != itemName) continue;
                int owned = candidate.Value<int>("owned");
                return JToken.DeepEquals(
                        material["displayName"],
                        candidate["displayName"])
                    && JToken.DeepEquals(
                        material["icon"],
                        candidate["icon"])
                    && material.Value<int>("before") == owned
                    && material.Value<int>("delta") == expectedDelta
                    && material.Value<int>("after")
                        == owned + expectedDelta;
            }
            return false;
        }

        private static bool ValidatePreviewTransition(
            PendingRequest entry,
            JObject before,
            JObject after,
            JArray materials,
            JArray removedMods,
            bool noOp)
        {
            JObject beforeEquipment =
                (JObject)before["source"]["equipment"];
            JObject afterEquipment =
                (JObject)after["source"]["equipment"];
            if (!SameEquipmentDefinition(
                    beforeEquipment,
                    afterEquipment)
                || !HasValidEffectiveModCapacity(afterEquipment)
                || beforeEquipment.Value<double>("lastUpdate")
                    != afterEquipment.Value<double>("lastUpdate"))
            {
                return false;
            }

            string operation = entry.Operation;
            if (operation == "convert")
            {
                JObject beforeTarget =
                    (JObject)before["target"]["equipment"];
                JObject afterTarget =
                    (JObject)after["target"]["equipment"];
                int sourceLevel = beforeEquipment.Value<int>("level");
                int targetLevel = beforeTarget.Value<int>("level");
                return SameEquipmentDefinition(beforeTarget, afterTarget)
                    && HasValidEffectiveModCapacity(afterTarget)
                    && beforeTarget.Value<double>("lastUpdate")
                        == afterTarget.Value<double>("lastUpdate")
                    && SameTierAndMods(beforeEquipment, afterEquipment)
                    && SameTierAndMods(beforeTarget, afterTarget)
                    && afterEquipment.Value<int>("level") == targetLevel
                    && afterTarget.Value<int>("level") == sourceLevel
                    && noOp == (sourceLevel == targetLevel)
                    && materials.Count == 0
                    && removedMods.Count == 0;
            }

            if (noOp) return false;
            int beforeLevel = beforeEquipment.Value<int>("level");
            int afterLevel = afterEquipment.Value<int>("level");
            string beforeTier = ReadString(beforeEquipment["tier"]);
            string afterTier = ReadString(afterEquipment["tier"]);
            JArray beforeMods = (JArray)beforeEquipment["mods"];
            JArray afterMods = (JArray)afterEquipment["mods"];
            if (operation == "enhance")
            {
                int targetLevel = entry.NormalizedPayload.Value<int>("targetLevel");
                return afterLevel == targetLevel
                    && targetLevel > beforeLevel
                    && beforeTier == afterTier
                    && JToken.DeepEquals(beforeMods, afterMods)
                    && removedMods.Count == 0
                    && materials.Count == 1
                    && ReadString(materials[0]["itemName"]) == "强化石"
                    && materials[0].Value<int>("delta") < 0;
            }
            if (beforeLevel != afterLevel) return false;
            if (operation == "install_tier")
            {
                return beforeTier != afterTier
                    && !string.IsNullOrEmpty(afterTier)
                    && JToken.DeepEquals(beforeMods, afterMods)
                    && removedMods.Count == 0
                    && materials.Count == 1
                    && materials[0].Value<int>("delta") == -1;
            }
            if (beforeTier != afterTier) return false;
            return ValidateModTransition(
                operation,
                beforeMods,
                afterMods,
                materials,
                removedMods);
        }

        private static bool SameEquipmentDefinition(
            JObject before,
            JObject after)
        {
            foreach (string key in new[] {
                "name", "displayName", "icon", "type", "use",
                "maxLevel", "hardMaxLevel" })
            {
                if (!JToken.DeepEquals(before[key], after[key])) return false;
            }
            return true;
        }

        private static bool HasValidEffectiveModCapacity(
            JObject equipment)
        {
            // Effective capacity is derived from the complete equipment value. A
            // legal mod transition may therefore change it (for example 1 -> 3),
            // but the authoritative after projection must still contain every
            // installed mod within that effective capacity.
            JArray mods = equipment != null
                ? equipment["mods"] as JArray : null;
            if (mods == null) return false;
            JToken capacity = equipment["modSlotCapacity"];
            return capacity == null
                || mods.Count <= equipment.Value<int>("modSlotCapacity");
        }

        private static bool SameTierAndMods(
            JObject before,
            JObject after)
        {
            return JToken.DeepEquals(before["tier"], after["tier"])
                && JToken.DeepEquals(before["mods"], after["mods"]);
        }

        private static bool ValidateModTransition(
            string operation,
            JArray beforeMods,
            JArray afterMods,
            JArray materials,
            JArray removedMods)
        {
            if (operation == "install_mod")
            {
                if (removedMods.Count != 0
                    || afterMods.Count != beforeMods.Count + 1
                    || materials.Count != 1) return false;
                for (int i = 0; i < beforeMods.Count; i++)
                    if (!JToken.DeepEquals(beforeMods[i], afterMods[i])) return false;
                string installed = ReadString(afterMods[afterMods.Count - 1]);
                return ReadString(materials[0]["itemName"]) == installed
                    && materials[0].Value<int>("delta") == -1;
            }

            JArray remaining;
            if (!TryRemoveMods(
                    beforeMods,
                    removedMods,
                    out remaining)) return false;
            if (operation == "replace_mod")
            {
                if (removedMods.Count == 0
                    || afterMods.Count != remaining.Count + 1) return false;
                for (int i = 0; i < remaining.Count; i++)
                    if (!JToken.DeepEquals(remaining[i], afterMods[i])) return false;
                string installed = ReadString(afterMods[afterMods.Count - 1]);
                if (ContainsString(beforeMods, installed)
                    || materials.Count != removedMods.Count + 1
                    || !MaterialDeltaEquals(materials, installed, -1)) return false;
                foreach (JToken removed in removedMods)
                    if (!MaterialDeltaEquals(
                            materials,
                            ReadString(removed),
                            1)) return false;
                return true;
            }
            if (operation == "detach_mod")
            {
                if (removedMods.Count == 0
                    || !JToken.DeepEquals(remaining, afterMods)
                    || materials.Count != removedMods.Count) return false;
                foreach (JToken removed in removedMods)
                    if (!MaterialDeltaEquals(
                            materials,
                            ReadString(removed),
                            1)) return false;
                return true;
            }
            if (operation == "detach_all_mods")
            {
                if (!JToken.DeepEquals(beforeMods, removedMods)
                    || afterMods.Count != 0
                    || materials.Count != removedMods.Count) return false;
                foreach (JToken removed in removedMods)
                    if (!MaterialDeltaEquals(
                            materials,
                            ReadString(removed),
                            1)) return false;
                return true;
            }
            return false;
        }

        private static bool TryRemoveMods(
            JArray before,
            JArray removed,
            out JArray remaining)
        {
            remaining = new JArray();
            var removedSet = new HashSet<string>(StringComparer.Ordinal);
            foreach (JToken token in removed)
                removedSet.Add(ReadString(token));
            foreach (JToken token in before)
            {
                string name = ReadString(token);
                if (!removedSet.Remove(name)) remaining.Add(name);
            }
            return removedSet.Count == 0;
        }

        private static bool ContainsString(
            JArray values,
            string expected)
        {
            foreach (JToken token in values)
                if (ReadString(token) == expected) return true;
            return false;
        }

        private static bool MaterialDeltaEquals(
            JArray materials,
            string itemName,
            int delta)
        {
            foreach (JToken token in materials)
            {
                JObject row = token as JObject;
                if (ReadString(row != null ? row["itemName"] : null)
                        == itemName)
                    return row.Value<int>("delta") == delta;
            }
            return false;
        }

        private static bool IsCommitResponse(
            JObject msg,
            PendingRequest entry)
        {
            PreviewBinding binding = entry != null
                ? entry.ConsumedPreviewBinding : null;
            JObject before;
            JObject after;
            JArray materials;
            JArray removedMods;
            bool noOp;
            bool canCommit;
            if (entry == null
                || entry.Source == null
                || binding == null
                || ReadString(msg["tuningToken"])
                    != entry.ExpectedTuningToken
                || !TryReadTuningProjectionResponse(
                    msg,
                    entry.Operation,
                    false,
                    out before,
                    out after,
                    out materials,
                    out removedMods,
                    out noOp,
                    out canCommit)
                || !IsOpaque(
                    ReadString(msg["transactionId"]))
                || !(msg["inventorySnapshots"]
                    is JArray inventorySnapshots))
            {
                return false;
            }

            JObject postSource;
            JObject postTarget;
            if (noOp != binding.NoOp
                || canCommit
                || !JToken.DeepEquals(
                    before,
                    binding.Before)
                || !JToken.DeepEquals(
                    materials,
                    binding.Materials)
                || !JToken.DeepEquals(
                    removedMods,
                    binding.RemovedMods)
                || !TryMatchCommittedAfter(
                    binding.After,
                    after,
                    noOp,
                    out postSource,
                    out postTarget))
            {
                return false;
            }

            JObject snapshot;
            if (!TrySanitizeTuningSnapshot(
                    msg["snapshot"] as JObject,
                    postSource,
                    out snapshot)
                || !JToken.DeepEquals(
                    snapshot["equipment"],
                    after["source"]["equipment"])
                || !SnapshotMaterialsMatchCommit(
                    snapshot["materials"] as JArray,
                    materials))
            {
                return false;
            }

            if (ReadString(
                    entry.Source["sourceKind"])
                == "loadout")
            {
                if (entry.Operation != "convert" || noOp)
                    return inventorySnapshots.Count == 0;
                return postTarget != null
                    && CharacterBuildProtocol
                        .IsFullBackpackSnapshots(
                            inventorySnapshots)
                    && BackpackSubjectMatches(
                        inventorySnapshots,
                        after["target"] as JObject);
            }
            return CharacterBuildProtocol
                    .IsFullBackpackSnapshots(
                        inventorySnapshots)
                && BackpackSubjectMatches(
                    inventorySnapshots,
                    after["source"] as JObject)
                && (postTarget == null
                    || BackpackSubjectMatches(
                        inventorySnapshots,
                        after["target"] as JObject));
        }

        private static bool TryMatchCommittedAfter(
            JObject expected,
            JObject actual,
            bool noOp,
            out JObject postSource,
            out JObject postTarget)
        {
            postSource = null;
            postTarget = null;
            bool hasTarget = expected != null
                && expected["target"] != null;
            JObject sanitizedActual;
            if (!TrySanitizeTuningProjection(
                    actual,
                    hasTarget,
                    out sanitizedActual)
                || !MatchCommittedSubject(
                    expected["source"] as JObject,
                    sanitizedActual["source"] as JObject,
                    noOp,
                    out postSource))
            {
                return false;
            }
            return !hasTarget
                || MatchCommittedSubject(
                    expected["target"] as JObject,
                    sanitizedActual["target"] as JObject,
                    noOp,
                    out postTarget);
        }

        private static bool MatchCommittedSubject(
            JObject expected,
            JObject actual,
            bool noOp,
            out JObject postSource)
        {
            postSource = null;
            if (expected == null || actual == null) return false;
            JObject expectedEquipment =
                expected["equipment"] as JObject;
            JObject actualEquipment =
                actual["equipment"] as JObject;
            JObject expectedBusiness =
                (JObject)expectedEquipment.DeepClone();
            JObject actualBusiness =
                (JObject)actualEquipment.DeepClone();
            expectedBusiness.Remove("lastUpdate");
            actualBusiness.Remove("lastUpdate");
            // stats 是 preview 阶段 before/after 的派生展示投影，commit after 由
            // 提交后权威状态重建、不携带 stats；比对业务身份时剥离，语义不变
            expectedBusiness.Remove("stats");
            actualBusiness.Remove("stats");
            double beforeLastUpdate =
                expectedEquipment.Value<double>("lastUpdate");
            double afterLastUpdate =
                actualEquipment.Value<double>("lastUpdate");
            JObject normalizedActualSource;
            return JToken.DeepEquals(
                    expectedBusiness,
                    actualBusiness)
                && (noOp
                    ? afterLastUpdate == beforeLastUpdate
                    : afterLastUpdate > beforeLastUpdate)
                && TryNormalizeSourceRef(
                    actual["source"] as JObject,
                    out normalizedActualSource)
                && TryResolveCommitPostSource(
                    expected["source"] as JObject,
                    normalizedActualSource,
                    noOp,
                    out postSource);
        }

        private static bool SnapshotMaterialsMatchCommit(
            JArray snapshotMaterials,
            JArray committedMaterials)
        {
            if (snapshotMaterials == null
                || committedMaterials == null) return false;
            foreach (JToken token in committedMaterials)
            {
                JObject committed = token as JObject;
                string itemName = ReadString(
                    committed != null
                        ? committed["itemName"] : null);
                bool found = false;
                foreach (JToken snapshotToken in snapshotMaterials)
                {
                    JObject current = snapshotToken as JObject;
                    if (ReadString(
                            current != null
                                ? current["itemName"] : null)
                            == itemName)
                    {
                        found = JToken.DeepEquals(
                                current["displayName"],
                                committed["displayName"])
                            && JToken.DeepEquals(
                                current["icon"],
                                committed["icon"])
                            && current.Value<int>("count")
                                == committed.Value<int>("after");
                        break;
                    }
                }
                if (!found) return false;
            }
            return true;
        }

        private static bool BackpackSubjectMatches(
            JArray snapshots,
            JObject subject)
        {
            JObject source = subject != null
                ? subject["source"] as JObject : null;
            JObject equipment = subject != null
                ? subject["equipment"] as JObject : null;
            if (snapshots == null
                || snapshots.Count != 1
                || source == null
                || equipment == null
                || ReadString(source["sourceKind"])
                    != "inventory") return false;
            JObject snapshot = snapshots[0] as JObject;
            JArray slots = snapshot != null
                ? snapshot["slots"] as JArray : null;
            int slot = source.Value<int>("slot");
            if (slots == null || slot < 0 || slot >= slots.Count) return false;
            JObject row = slots[slot] as JObject;
            JObject item = row != null ? row["item"] as JObject : null;
            JObject confirm = row != null
                ? row["confirmProjection"] as JObject : null;
            JArray mods = equipment["mods"] as JArray;
            return row != null
                && row.Value<bool?>("occupied") == true
                && ReadString(row["slotLease"])
                    == ReadString(source["expectedLease"])
                && item != null
                && confirm != null
                && ReadString(item["itemKind"]) == "equipment"
                && ReadString(item["name"])
                    == ReadString(equipment["name"])
                && ReadString(item["displayName"])
                    == ReadString(equipment["displayName"])
                && ReadString(item["icon"])
                    == ReadString(equipment["icon"])
                && ReadString(item["majorType"])
                    == ReadString(equipment["type"])
                && ReadString(item["use"])
                    == ReadString(equipment["use"])
                && item.Value<int>("enhancementLevel")
                    == equipment.Value<int>("level")
                && item.Value<int>("maxEnhancementLevel")
                    == equipment.Value<int>("hardMaxLevel")
                && item.Value<int>("modSlotUsed") == mods.Count
                && (equipment["modSlotCapacity"] == null
                    || item.Value<int>("modSlotCapacity")
                        == equipment.Value<int>("modSlotCapacity"))
                && ReadString(confirm["name"])
                    == ReadString(equipment["name"])
                && ReadString(confirm["displayName"])
                    == ReadString(equipment["displayName"])
                && confirm.Value<int>("enhancementLevel")
                    == equipment.Value<int>("level")
                && ReadString(confirm["tier"])
                    == ReadString(equipment["tier"])
                && ReadString(confirm["modSignature"])
                    == ModSignature(mods)
                && confirm.Value<double>("lastUpdate")
                    == equipment.Value<double>("lastUpdate");
        }

        private static string ModSignature(JArray mods)
        {
            var value = new StringBuilder();
            foreach (JToken token in mods)
            {
                string name = ReadString(token);
                value.Append(name.Length.ToString(
                    System.Globalization.CultureInfo.InvariantCulture));
                value.Append(':');
                value.Append(name);
                value.Append(';');
            }
            return value.ToString();
        }

        private static bool TryResolveCommitPostSource(
            JObject beforeSource,
            JObject afterSource,
            bool noOp,
            out JObject expectedPostSource)
        {
            expectedPostSource = null;
            JObject normalizedBefore;
            if (!TryNormalizeSourceRef(
                    beforeSource,
                    out normalizedBefore))
            {
                return false;
            }
            if (noOp)
            {
                if (!JToken.DeepEquals(
                        normalizedBefore,
                        afterSource))
                {
                    return false;
                }
                expectedPostSource = normalizedBefore;
                return true;
            }

            string sourceKind =
                ReadString(
                    normalizedBefore["sourceKind"]);
            if (sourceKind == "loadout")
            {
                int revision =
                    normalizedBefore.Value<int>(
                        "expectedLoadoutRevision");
                if (revision == int.MaxValue)
                    return false;
                expectedPostSource =
                    (JObject)normalizedBefore
                        .DeepClone();
                expectedPostSource[
                    "expectedLoadoutRevision"] =
                    revision + 1;
                return JToken.DeepEquals(
                    expectedPostSource,
                    afterSource);
            }

            if (sourceKind != "inventory"
                || ReadString(
                    normalizedBefore["containerId"])
                    != ReadString(
                        afterSource["containerId"])
                || normalizedBefore.Value<int>("slot")
                    != afterSource.Value<int>("slot")
                || ReadString(
                    normalizedBefore["expectedLease"])
                    == ReadString(
                        afterSource["expectedLease"]))
            {
                return false;
            }
            expectedPostSource =
                (JObject)afterSource.DeepClone();
            return true;
        }

        private static bool IsExactSource(
            JObject expected,
            JObject actual)
        {
            JObject normalizedExpected;
            JObject normalizedActual;
            return TryNormalizeSourceRef(
                    expected,
                    out normalizedExpected)
                && TryNormalizeSourceRef(
                    actual,
                    out normalizedActual)
                && JToken.DeepEquals(
                    normalizedExpected,
                    normalizedActual);
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
            JObject snapshot = result["snapshot"] as JObject;
            if (snapshot != null)
            {
                JArray tierCandidates;
                JArray modCandidates;
                if (TrySanitizeTuningCandidates(
                    snapshot,
                    out tierCandidates,
                    out modCandidates))
                {
                    snapshot["tierCandidates"] = tierCandidates;
                    snapshot["modCandidates"] = modCandidates;
                }
                else
                {
                    // IsValidResponse normally makes this unreachable. Never project an
                    // untrusted candidate leaf if validation and sanitization diverge.
                    snapshot["tierCandidates"] = new JArray();
                    snapshot["modCandidates"] = new JArray();
                }
            }
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

        private static string PreviewResponseOutcome(bool valid, JObject msg)
        {
            if (!valid) return "malformed_response";
            if (msg != null && msg.Value<bool?>("success") == true)
                return "success";
            string error = ReadString(msg != null ? msg["error"] : null);
            return "error:" + (string.IsNullOrEmpty(error) ? "unknown" : error);
        }

        private static string PreviewSourceKey(JObject source)
        {
            if (source == null) return "";
            string kind = ReadString(source["sourceKind"]);
            if (kind == "loadout")
            {
                return "loadout:"
                    + source.Value<int>("sessionGeneration").ToString(
                        System.Globalization.CultureInfo.InvariantCulture)
                    + ":" + (ReadString(source["slotKey"]) ?? "")
                    + ":" + source.Value<int>("expectedLoadoutRevision").ToString(
                        System.Globalization.CultureInfo.InvariantCulture);
            }
            if (kind == "inventory")
            {
                return "inventory:" + (ReadString(source["containerId"]) ?? "")
                    + ":" + source.Value<int>("slot").ToString(
                        System.Globalization.CultureInfo.InvariantCulture)
                    + ":" + (ReadString(source["expectedLease"]) ?? "");
            }
            return "";
        }

        private static string PreviewIntentKey(PendingRequest entry)
        {
            if (entry == null) return "";
            JObject payload = entry.NormalizedPayload;
            if (entry.Operation == "enhance")
            {
                return "enhance|" + (payload != null
                    ? payload.Value<int>("targetLevel").ToString(
                        System.Globalization.CultureInfo.InvariantCulture)
                    : "0");
            }
            if (entry.Operation == "convert")
            {
                JObject target = payload != null ? payload["target"] as JObject : null;
                return "convert|" + (target != null
                    ? (ReadString(target["containerId"]) ?? "") : "")
                    + "|" + (target != null
                        ? target.Value<int>("slot").ToString(
                            System.Globalization.CultureInfo.InvariantCulture)
                        : "0")
                    + "|" + (target != null
                        ? (ReadString(target["expectedLease"]) ?? "") : "");
            }
            return (entry.Operation ?? "") + "|" + (entry.CandidateKey ?? "")
                + "|" + (payload != null
                    ? (ReadString(payload["replaceCandidateKey"]) ?? "") : "");
        }

        private static string SafeLogField(string value)
        {
            if (string.IsNullOrEmpty(value)) return "-";
            try
            {
                return Uri.EscapeDataString(value);
            }
            catch (UriFormatException)
            {
                return "invalid";
            }
        }

        private static string TokenReference(string tuningToken)
        {
            return IsOpaque(tuningToken)
                ? AuthorityLogFormatter.CreateReference(tuningToken)
                : null;
        }

        private static string SnapshotStateReference(JObject snapshot)
        {
            if (snapshot == null
                || snapshot["equipment"] == null
                || snapshot["enhance"] == null
                || !(snapshot["tierCandidates"] is JArray)
                || !(snapshot["modCandidates"] is JArray)
                || !(snapshot["materials"] is JArray)) return null;
            var stable = new JObject
            {
                ["gender"] = snapshot["gender"] != null
                    ? snapshot["gender"].DeepClone() : JValue.CreateNull(),
                ["equipment"] = snapshot["equipment"].DeepClone(),
                ["enhance"] = snapshot["enhance"].DeepClone(),
                ["tierCandidates"] = snapshot["tierCandidates"].DeepClone(),
                ["modCandidates"] = snapshot["modCandidates"].DeepClone(),
                ["materials"] = snapshot["materials"].DeepClone()
            };
            string canonical = CanonicalizeStateToken(stable)
                .ToString(Formatting.None);
            using (SHA256 sha = SHA256.Create())
            {
                byte[] digest = sha.ComputeHash(
                    Encoding.UTF8.GetBytes(canonical));
                var value = new StringBuilder(31);
                value.Append("sha256_");
                for (int i = 0; i < 12; i++)
                    value.Append(digest[i].ToString("x2",
                        System.Globalization.CultureInfo.InvariantCulture));
                return value.ToString();
            }
        }

        private static JToken CanonicalizeStateToken(JToken value)
        {
            JObject obj = value as JObject;
            if (obj != null)
            {
                var properties = new List<JProperty>(obj.Properties());
                properties.Sort(delegate(JProperty left, JProperty right)
                {
                    return string.CompareOrdinal(left.Name, right.Name);
                });
                var canonical = new JObject();
                foreach (JProperty property in properties)
                    canonical[property.Name] = CanonicalizeStateToken(
                        property.Value);
                return canonical;
            }
            JArray array = value as JArray;
            if (array != null)
            {
                var canonical = new JArray();
                foreach (JToken item in array)
                    canonical.Add(CanonicalizeStateToken(item));
                return canonical;
            }
            return value != null ? value.DeepClone() : JValue.CreateNull();
        }

        private static string FormatFlashCommandForLog(JObject flash)
        {
            return AuthorityLogFormatter.SanitizeAuthorityEnvelope(flash)
                .ToString(Formatting.None);
        }

        private static void LogPreviewSettled(PendingRequest entry,
            string outcome, int remainingPending, string tokenRef)
        {
            LogManager.Log("event=equipment_tuning_preview_settled"
                + " webCallId=" + SafeLogField(entry.WebCallId)
                + " flashCallId=" + entry.FlashCallId.ToString(
                    System.Globalization.CultureInfo.InvariantCulture)
                + " requestCallId=" + SafeLogField(entry.WebCallId)
                + " tokenRef=" + SafeLogField(tokenRef)
                + " panelInstanceId=" + SafeLogField(entry.PanelInstanceId)
                + " viewSessionId=" + SafeLogField(entry.ViewSessionId)
                + " sourceKeyRef=" + SafeLogField(
                    AuthorityLogFormatter.CreateReference(
                        PreviewSourceKey(entry.Source)))
                + " operation=" + SafeLogField(entry.Operation)
                + " candidateKey=" + SafeLogField(entry.CandidateKey)
                + " intentKeyRef=" + SafeLogField(
                    AuthorityLogFormatter.CreateReference(
                        PreviewIntentKey(entry)))
                + " outcome=" + SafeLogField(outcome)
                + " remainingPending=" + remainingPending.ToString(
                    System.Globalization.CultureInfo.InvariantCulture));
        }

        private static void LogCommitSettled(PendingRequest entry,
            string outcome, string writeState, int remainingPending,
            bool snapshotPresent, bool transactionIdPresent,
            string stateRef)
        {
            PreviewBinding binding = entry != null
                ? entry.ConsumedPreviewBinding : null;
            LogManager.Log("event=equipment_tuning_commit_settled"
                + " webCallId=" + SafeLogField(entry != null ? entry.WebCallId : null)
                + " flashCallId=" + (entry != null ? entry.FlashCallId : 0).ToString(
                    System.Globalization.CultureInfo.InvariantCulture)
                + " requestCallId=" + SafeLogField(entry != null ? entry.WebCallId : null)
                + " previewWebCallId=" + SafeLogField(
                    binding != null ? binding.PreviewWebCallId : null)
                + " tokenRef=" + SafeLogField(
                    binding != null ? binding.TokenRef : null)
                + " panelInstanceId=" + SafeLogField(entry != null ? entry.PanelInstanceId : null)
                + " viewSessionId=" + SafeLogField(entry != null ? entry.ViewSessionId : null)
                + " sourceKeyRef=" + SafeLogField(
                    AuthorityLogFormatter.CreateReference(
                        binding != null ? binding.SourceKey : null))
                + " operation=" + SafeLogField(
                    binding != null ? binding.Operation : null)
                + " candidateKey=" + SafeLogField(
                    binding != null ? binding.CandidateKey : null)
                + " intentKeyRef=" + SafeLogField(
                    AuthorityLogFormatter.CreateReference(
                        binding != null ? binding.IntentKey : null))
                + " outcome=" + SafeLogField(outcome)
                + " writeEpoch=" + (entry != null ? entry.WriteEpoch : 0).ToString(
                    System.Globalization.CultureInfo.InvariantCulture)
                + " writeState=" + SafeLogField(writeState)
                + " remainingPending=" + remainingPending.ToString(
                    System.Globalization.CultureInfo.InvariantCulture)
                + " stateRef=" + SafeLogField(stateRef)
                + " snapshotPresent=" + (snapshotPresent ? "true" : "false")
                + " transactionIdPresent=" + (transactionIdPresent ? "true" : "false"));
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

        private void RejectAndRemember(string callId, string cmd, string error,
            string requestedInstance, string requestedViewSessionId)
        {
            int epoch;
            lock (_lock)
            {
                if (_activeCallIds.Contains(callId) || _recentCallIds.Contains(callId)) return;
                RememberRecentLocked(callId);
                epoch = _writeEpoch;
            }
            RespondError(callId, cmd, error, false, requestedInstance,
                requestedViewSessionId, epoch);
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

        private bool TryCompleteDetachWithoutAuthority(
            string callId,
            string panelInstanceId,
            string viewSessionId)
        {
            // Opening the tuning surface does not start Flash authority by itself;
            // the first accepted snapshot does. If there was no equipment source,
            // close is an authority-free no-op. Keep every active/pending/write
            // state on the strict Flash detach path.
            int writeEpoch;
            lock (_lock)
            {
                if (_activeCallIds.Contains(callId)
                    || _recentCallIds.Contains(callId)) return true;
                if (!string.Equals(
                        _panelInstanceId,
                        panelInstanceId,
                        StringComparison.Ordinal)
                    || !string.IsNullOrEmpty(_activeViewSessionId)
                    || !string.IsNullOrEmpty(_detachingViewSessionId)
                    || _pending.Count != 0
                    || _writeState != "idle")
                {
                    return false;
                }
                writeEpoch = _writeEpoch;
                RememberRecentLocked(callId);
            }

            var response = new JObject
            {
                ["type"] = "panel_resp",
                ["panel"] = "workbench",
                ["domain"] = "equipment_tuning",
                ["cmd"] = "detach",
                ["callId"] = callId,
                ["panelInstanceId"] = panelInstanceId,
                ["viewSessionId"] = viewSessionId,
                ["writeEpoch"] = writeEpoch,
                ["success"] = true
            };
            PostToWeb(response.ToString(Formatting.None));
            LogManager.Log("event=equipment_tuning_detach_local_noop"
                + " callId=" + SafeLogField(callId)
                + " panelInstanceId=" + SafeLogField(panelInstanceId)
                + " viewSessionId=" + SafeLogField(viewSessionId)
                + " writeEpoch=" + writeEpoch.ToString(
                    System.Globalization.CultureInfo.InvariantCulture));
            NotifyCoordinatorSettledIfReady();
            return true;
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

        private static bool TryReadFiniteNumber(
            JToken token,
            double min,
            double max,
            out double value)
        {
            value = 0;
            if (token == null
                || (token.Type != JTokenType.Integer
                    && token.Type != JTokenType.Float)) return false;
            try { value = token.Value<double>(); }
            catch { return false; }
            return !double.IsNaN(value)
                && !double.IsInfinity(value)
                && value >= min
                && value <= max;
        }
    }
}
