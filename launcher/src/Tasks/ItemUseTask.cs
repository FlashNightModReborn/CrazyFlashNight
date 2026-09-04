using System;
using System.Collections.Generic;
using System.Text.RegularExpressions;
using CF7Launcher.Bus;
using CF7Launcher.Guardian;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Tasks
{
    /// <summary>
    /// Strict workbench item-use bridge. Web may request only reward-pack open, backpack potion
    /// consume, receipt query, reward-inbox snapshot, or shared cooldown snapshot. AS2 remains the
    /// inventory/save and frame-clock authority.
    /// </summary>
    public sealed class ItemUseTask : IDisposable
    {
        public sealed class RewardHandoff
        {
            internal RewardHandoff(
                string panelInstanceId,
                long sessionGeneration,
                JObject authority)
            {
                PanelInstanceId = panelInstanceId;
                SessionGeneration = sessionGeneration;
                Authority = authority != null
                    ? (JObject)authority.DeepClone() : null;
            }

            public string PanelInstanceId { get; private set; }
            public long SessionGeneration { get; private set; }
            public JObject Authority { get; private set; }
        }

        private sealed class PendingRequest
        {
            public string WebCommand;
            public string OperationId;
            public string PanelInstanceId;
            public long SessionGeneration;
            public bool IsWrite;
            public string ReconcileWriteCommand;
        }

        private const int DefaultTimeoutMs = 10000;
        private const int InboxCapacity = 64;
        private const long MaxSafeInteger = 9007199254740991L;

        private static readonly Regex ValidToken = new Regex(
            "^[A-Za-z0-9._~-]{1,128}$",
            RegexOptions.CultureInvariant | RegexOptions.Compiled);
        private static readonly Regex ValidCallId = new Regex(
            "^[A-Za-z0-9._-]{1,96}$",
            RegexOptions.CultureInvariant | RegexOptions.Compiled);
        private static readonly HashSet<string> DefinitiveWriteErrors =
            new HashSet<string>(StringComparer.Ordinal)
            {
                "unsupported_version",
                "unsupported_cmd",
                "invalid_payload",
                "invalid_operation_id",
                "stale_panel_instance",
                "stale_session",
                "stale_source",
                "unsupported_item",
                "invalid_reward_pack",
                "reward_inbox_full",
                "player_unavailable",
                "no_available_lane",
                "cooldown_unavailable",
                "insufficient_quantity",
                "operation_conflict",
                "service_not_ready"
            };

        private readonly object _gate = new object();
        private readonly PanelPendingCallTracker<PendingRequest> _pendingCalls;
        private readonly Func<string, long, bool> _isCurrentBinding;
        private Action<string> _postToWeb;
        private Action<Action> _invokeOnUI;
        private string _writeState = "idle";
        private string _unknownOperationId;
        private string _unknownWriteCommand;
        private RewardHandoff _rewardHandoff;
        private bool _handoffNavigationArmed;
        private bool _handoffPanelClosed;
        private bool _disposed;

        public ItemUseTask(
            XmlSocketServer socket,
            Func<string, long, bool> isCurrentBinding)
            : this(
                delegate { return socket != null && socket.IsClientReady; },
                delegate(string payload)
                {
                    return socket != null && socket.TrySend(payload);
                },
                isCurrentBinding,
                DefaultTimeoutMs)
        {
        }

        public ItemUseTask(
            Func<bool> isClientReady,
            Func<string, bool> trySend,
            Func<string, long, bool> isCurrentBinding,
            int timeoutMs = DefaultTimeoutMs)
        {
            _isCurrentBinding = isCurrentBinding ?? delegate { return false; };
            _pendingCalls = new PanelPendingCallTracker<PendingRequest>(
                isClientReady,
                trySend,
                Math.Max(1, timeoutMs),
                HandlePendingEnded);
        }

        public void SetPostToWeb(Action<string> post) { _postToWeb = post; }
        public void SetInvoker(Action<Action> invoker) { _invokeOnUI = invoker; }

        internal string WriteState
        {
            get { lock (_gate) return _writeState; }
        }

        internal string UnknownOperationId
        {
            get { lock (_gate) return _unknownOperationId; }
        }

        public void HandleWebRequest(string command, JObject request)
        {
            string callId = ReadString(request != null ? request["callId"] : null);
            if (!IsCallId(callId))
            {
                RespondError(request, command, callId, "invalid_call_id", false);
                return;
            }
            if (!IsExactObject(
                    request,
                    "type", "panel", "domain", "cmd", "callId",
                    "panelInstanceId", "payload")
                || ReadString(request["type"]) != "panel"
                || ReadString(request["panel"]) != "workbench"
                || ReadString(request["domain"]) != "item_use"
                || ReadString(request["cmd"]) != command)
            {
                RejectAndRemember(request, command, callId, "invalid_payload", false);
                return;
            }

            string action;
            bool isWrite;
            if (!TryResolveCommand(command, out action, out isWrite))
            {
                RejectAndRemember(request, command, callId, "unsupported_cmd", false);
                return;
            }

            JObject normalized;
            string operationId;
            string panelInstanceId;
            long sessionGeneration;
            if (!TryNormalizePayload(
                    command,
                    request.Value<string>("panelInstanceId"),
                    request["payload"] as JObject,
                    out normalized,
                    out operationId,
                    out panelInstanceId,
                    out sessionGeneration))
            {
                RejectAndRemember(request, command, callId, "invalid_payload", false);
                return;
            }
            if (!IsCurrentBinding(panelInstanceId, sessionGeneration))
            {
                RejectAndRemember(
                    request, command, callId, "panel_instance_expired", false);
                return;
            }
            bool transportReady = _pendingCalls.IsReady();

            int backendCallId;
            lock (_gate)
            {
                if (_disposed) return;
                if (_pendingCalls.IsKnownWebCallId(callId)) return;

                if (isWrite && _writeState != "idle")
                {
                    string error = _writeState == "needs_reconcile"
                        ? "reconcile_required" : "busy";
                    if (!_pendingCalls.TryRememberRejected(callId)) return;
                    RespondError(
                        request,
                        command,
                        callId,
                        error,
                        _writeState == "needs_reconcile");
                    return;
                }

                string reconcileWriteCommand = null;
                if (command == "query")
                {
                    if (_writeState != "needs_reconcile")
                    {
                        if (!_pendingCalls.TryRememberRejected(callId)) return;
                        RespondError(
                            request, command, callId,
                            "no_reconcile_pending", false);
                        return;
                    }
                    if (!string.Equals(
                            operationId,
                            _unknownOperationId,
                            StringComparison.Ordinal))
                    {
                        if (!_pendingCalls.TryRememberRejected(callId)) return;
                        RespondError(
                            request, command, callId,
                            "operation_mismatch", true);
                        return;
                    }
                    reconcileWriteCommand = _unknownWriteCommand;
                }

                if (!transportReady)
                {
                    if (!_pendingCalls.TryRememberRejected(callId)) return;
                    bool requiresReconcile = command == "query"
                        && _writeState == "needs_reconcile";
                    if (isWrite)
                    {
                        _writeState = "needs_reconcile";
                        _unknownOperationId = operationId;
                        _unknownWriteCommand = command;
                        requiresReconcile = true;
                    }
                    RespondError(
                        request,
                        command,
                        callId,
                        "disconnected",
                        requiresReconcile);
                    return;
                }

                if (!_pendingCalls.TryBegin(
                        callId,
                        new PendingRequest
                        {
                            WebCommand = command,
                            OperationId = operationId,
                            PanelInstanceId = panelInstanceId,
                            SessionGeneration = sessionGeneration,
                            IsWrite = isWrite,
                            ReconcileWriteCommand = reconcileWriteCommand
                        },
                        out backendCallId))
                {
                    return;
                }
                if (isWrite) _writeState = "write_pending";
            }

            JObject flash = PanelBridge.BuildFlashCommand(
                action, backendCallId, normalized);
            LogManager.Log(
                AuthorityLogFormatter.FormatFlashCommand(
                    "ItemUseTask", flash));
            _pendingCalls.Send(
                backendCallId,
                flash.ToString(Formatting.None) + "\0");
        }

        public void HandleFlashResponse(JObject message, Action<string> respond)
        {
            int backendCallId;
            if (!TryReadInteger(
                    message != null ? message["callId"] : null,
                    1,
                    int.MaxValue,
                    out backendCallId))
            {
                if (respond != null) respond(null);
                return;
            }

            PanelPendingCall<PendingRequest> pending;
            if (!_pendingCalls.TryComplete(backendCallId, out pending))
            {
                if (respond != null) respond(null);
                return;
            }

            PendingRequest entry = pending.Context;
            JObject sanitized;
            bool definitiveWrite;
            bool reconciled;
            bool valid = TrySanitizeResponse(
                message,
                entry,
                out sanitized,
                out definitiveWrite,
                out reconciled);

            bool requiresReconcile;
            lock (_gate)
            {
                if (entry.IsWrite)
                {
                    if (valid && definitiveWrite)
                    {
                        ClearUnknownLocked();
                    }
                    else
                    {
                        _writeState = "needs_reconcile";
                        _unknownOperationId = entry.OperationId;
                        _unknownWriteCommand = entry.WebCommand;
                    }
                }
                else if (entry.WebCommand == "query" && valid && reconciled)
                {
                    ClearUnknownLocked();
                }
                requiresReconcile = _writeState == "needs_reconcile"
                    && (entry.IsWrite || entry.WebCommand == "query");
            }

            bool current = IsCurrentBinding(
                entry.PanelInstanceId, entry.SessionGeneration);
            if (valid && current)
            {
                JObject authority = sanitized["rewardAuthority"] as JObject;
            if (authority != null
                    && (entry.WebCommand == "open"
                        || entry.WebCommand == "openMany"
                        || entry.WebCommand == "inboxSnapshot"))
                {
                    StageRewardHandoff(
                        entry.PanelInstanceId,
                        entry.SessionGeneration,
                        authority);
                }
                JObject web = BuildWebResponse(
                    pending.WebCallId,
                    entry,
                    sanitized,
                    requiresReconcile);
                PostToWeb(web.ToString(Formatting.None));
            }
            else if (current)
            {
                JObject error = BuildErrorResponse(
                    entry.PanelInstanceId,
                    entry.WebCommand,
                    pending.WebCallId,
                    "malformed_response",
                    entry.IsWrite || entry.WebCommand == "query");
                if (!string.IsNullOrEmpty(entry.OperationId))
                    error["operationId"] = entry.OperationId;
                PostToWeb(error.ToString(Formatting.None));
            }
            if (respond != null) respond(null);
        }

        /// <summary>
        /// Arms the cached authority only for the explicit navigate_reward_inbox close intent.
        /// Merely refreshing inboxSnapshot never changes panels.
        /// </summary>
        public bool TryArmRewardNavigation(
            string panelInstanceId,
            long sessionGeneration)
        {
            lock (_gate)
            {
                if (_disposed || _rewardHandoff == null
                    || _handoffPanelClosed
                    || !string.Equals(
                        _rewardHandoff.PanelInstanceId,
                        panelInstanceId,
                        StringComparison.Ordinal)
                    || _rewardHandoff.SessionGeneration != sessionGeneration)
                {
                    return false;
                }
            }
            if (!IsCurrentBinding(panelInstanceId, sessionGeneration))
                return false;
            lock (_gate)
            {
                if (_disposed || _rewardHandoff == null
                    || !string.Equals(
                        _rewardHandoff.PanelInstanceId,
                        panelInstanceId,
                        StringComparison.Ordinal)
                    || _rewardHandoff.SessionGeneration != sessionGeneration)
                {
                    return false;
                }
                _handoffNavigationArmed = true;
                return true;
            }
        }

        public void CancelRewardNavigation(string panelInstanceId)
        {
            lock (_gate)
            {
                if (_rewardHandoff == null
                    || !string.Equals(
                        _rewardHandoff.PanelInstanceId,
                        panelInstanceId,
                        StringComparison.Ordinal))
                {
                    return;
                }
                _handoffNavigationArmed = false;
                _handoffPanelClosed = false;
            }
        }

        /// <summary>Marks only the armed exact workbench visual as retired.</summary>
        public void OnWorkbenchPanelClosed(string panelInstanceId)
        {
            lock (_gate)
            {
                if (_rewardHandoff == null
                    || !string.Equals(
                        _rewardHandoff.PanelInstanceId,
                        panelInstanceId,
                        StringComparison.Ordinal))
                {
                    return;
                }
                // A normal workbench close must retire any cached, unarmed authority from
                // that exact instance. Re-entry obtains a fresh snapshot/authority instead
                // of retaining a stale Host handoff across panel lifetimes.
                if (!_handoffNavigationArmed)
                {
                    _rewardHandoff = null;
                    _handoffPanelClosed = false;
                    return;
                }
                _handoffPanelClosed = true;
            }
        }

        /// <summary>
        /// Consumes a reward handoff only after the exact workbench visual retired. Callers must
        /// separately prove CharacterBuild released its retained pause/binding before opening Loot.
        /// </summary>
        public bool TryTakeClosedRewardHandoff(out RewardHandoff handoff)
        {
            lock (_gate)
            {
                handoff = null;
                if (_disposed || _rewardHandoff == null || !_handoffPanelClosed)
                    return false;
                handoff = _rewardHandoff;
                _rewardHandoff = null;
                _handoffNavigationArmed = false;
                _handoffPanelClosed = false;
                return true;
            }
        }

        public void ClearPending()
        {
            _pendingCalls.Clear();
            lock (_gate)
            {
                if (!_disposed) ClearUnknownLocked();
            }
        }

        public void Dispose()
        {
            lock (_gate)
            {
                if (_disposed) return;
                _disposed = true;
                _rewardHandoff = null;
                _handoffNavigationArmed = false;
                _handoffPanelClosed = false;
            }
            _pendingCalls.Dispose();
        }

        private void StageRewardHandoff(
            string panelInstanceId,
            long sessionGeneration,
            JObject authority)
        {
            lock (_gate)
            {
                if (_disposed) return;
                _rewardHandoff = new RewardHandoff(
                    panelInstanceId,
                    sessionGeneration,
                    authority);
                _handoffNavigationArmed = false;
                _handoffPanelClosed = false;
            }
        }

        private void HandlePendingEnded(
            PanelPendingCall<PendingRequest> pending,
            PanelPendingCallEndReason reason)
        {
            if (pending == null || pending.Context == null) return;
            PendingRequest entry = pending.Context;
            bool requiresReconcile = false;
            bool shouldPost;
            lock (_gate)
            {
                if (entry.IsWrite)
                {
                    _writeState = "needs_reconcile";
                    _unknownOperationId = entry.OperationId;
                    _unknownWriteCommand = entry.WebCommand;
                    requiresReconcile = true;
                }
                else if (entry.WebCommand == "query"
                    && _writeState == "needs_reconcile")
                {
                    requiresReconcile = true;
                }
                shouldPost = reason != PanelPendingCallEndReason.Cleared
                    && !_disposed;
            }
            if (!shouldPost
                || !IsCurrentBinding(
                    entry.PanelInstanceId, entry.SessionGeneration))
            {
                return;
            }
            string error = reason == PanelPendingCallEndReason.Timeout
                ? "timeout" : "disconnected";
            JObject response = BuildErrorResponse(
                entry.PanelInstanceId,
                entry.WebCommand,
                pending.WebCallId,
                error,
                requiresReconcile);
            if (!string.IsNullOrEmpty(entry.OperationId))
                response["operationId"] = entry.OperationId;
            PostToWeb(response.ToString(Formatting.None));
        }

        private void ClearUnknownLocked()
        {
            _writeState = "idle";
            _unknownOperationId = null;
            _unknownWriteCommand = null;
        }

        private bool IsCurrentBinding(
            string panelInstanceId,
            long sessionGeneration)
        {
            try
            {
                return _isCurrentBinding(
                    panelInstanceId, sessionGeneration);
            }
            catch
            {
                return false;
            }
        }

        private void RejectAndRemember(
            JObject request,
            string command,
            string callId,
            string error,
            bool requiresReconcile)
        {
            if (!_pendingCalls.TryRememberRejected(callId)) return;
            RespondError(request, command, callId, error, requiresReconcile);
        }

        private void RespondError(
            JObject request,
            string command,
            string callId,
            string error,
            bool requiresReconcile)
        {
            string panelInstanceId = request != null
                ? ReadString(request["panelInstanceId"]) : null;
            JObject response = BuildErrorResponse(
                panelInstanceId,
                command,
                callId,
                error,
                requiresReconcile);
            string operationId = null;
            JObject payload = request != null
                ? request["payload"] as JObject : null;
            if (payload != null)
                operationId = ReadString(payload["operationId"]);
            lock (_gate)
            {
                if (requiresReconcile
                    && !string.IsNullOrEmpty(_unknownOperationId))
                {
                    operationId = _unknownOperationId;
                }
            }
            if (!string.IsNullOrEmpty(operationId))
                response["operationId"] = operationId;
            PostToWeb(response.ToString(Formatting.None));
        }

        private static JObject BuildErrorResponse(
            string panelInstanceId,
            string command,
            string callId,
            string error,
            bool requiresReconcile)
        {
            var response = new JObject
            {
                ["type"] = "panel_resp",
                ["panel"] = "workbench",
                ["domain"] = "item_use",
                ["cmd"] = command ?? "",
                ["callId"] = callId ?? "",
                ["panelInstanceId"] = panelInstanceId ?? "",
                ["success"] = false,
                ["error"] = error ?? "invalid_request"
            };
            if (requiresReconcile) response["requiresReconcile"] = true;
            return response;
        }

        private static JObject BuildWebResponse(
            string webCallId,
            PendingRequest entry,
            JObject sanitized,
            bool requiresReconcile)
        {
            var web = new JObject
            {
                ["type"] = "panel_resp",
                ["panel"] = "workbench",
                ["domain"] = "item_use",
                ["cmd"] = entry.WebCommand,
                ["callId"] = webCallId,
                ["panelInstanceId"] = entry.PanelInstanceId,
                ["v"] = 1,
                ["success"] = sanitized.Value<bool>("success"),
                ["sessionGeneration"] = entry.SessionGeneration
            };
            if (!string.IsNullOrEmpty(entry.OperationId))
                web["operationId"] = entry.OperationId;

            string[] projection =
            {
                "error", "consumed", "remaining", "selectedLane",
                "replayed", "requestedCount", "packages",
                "rewardReady", "rewardBatchId", "inboxSummary",
                "rewardAuthority", "found", "receipt", "cooldownLanes"
            };
            foreach (string name in projection)
            {
                if (sanitized.Property(name) != null)
                    web[name] = sanitized[name].DeepClone();
            }
            if (requiresReconcile) web["requiresReconcile"] = true;
            return web;
        }

        private static bool TryResolveCommand(
            string command,
            out string action,
            out bool isWrite)
        {
            isWrite = false;
            switch (command)
            {
                case "open":
                    action = "itemUseOpen";
                    isWrite = true;
                    return true;
                case "openMany":
                    action = "itemUseOpenMany";
                    isWrite = true;
                    return true;
                case "consume":
                    action = "itemUseConsume";
                    isWrite = true;
                    return true;
                case "query":
                    action = "itemUseQuery";
                    return true;
                case "inboxSnapshot":
                    action = "itemUseInboxSnapshot";
                    return true;
                case "cooldownSnapshot":
                    action = "itemUseCooldownSnapshot";
                    return true;
                default:
                    action = null;
                    return false;
            }
        }

        private static bool TryNormalizePayload(
            string command,
            string envelopePanelInstanceId,
            JObject payload,
            out JObject normalized,
            out string operationId,
            out string panelInstanceId,
            out long sessionGeneration)
        {
            normalized = null;
            operationId = null;
            panelInstanceId = null;
            sessionGeneration = 0;
            if (payload == null
                || !TryReadInteger(payload["v"], 1, 1, out int version)
                || !TryReadToken(
                    payload["panelInstanceId"], out panelInstanceId)
                || !string.Equals(
                    envelopePanelInstanceId,
                    panelInstanceId,
                    StringComparison.Ordinal)
                || !TryReadLongInteger(
                    payload["sessionGeneration"],
                    1,
                    int.MaxValue,
                    out sessionGeneration))
            {
                return false;
            }

            var result = new JObject
            {
                ["v"] = 1,
                ["panelInstanceId"] = panelInstanceId,
                ["sessionGeneration"] = sessionGeneration
            };
            if (command == "open" || command == "consume")
            {
                if (!IsExactObject(
                        payload,
                        "v", "operationId", "panelInstanceId",
                        "sessionGeneration", "source")
                    || !TryReadOperationId(
                        payload["operationId"], out operationId)
                    || !TryNormalizeSource(
                        payload["source"] as JObject,
                        out JObject source))
                {
                    return false;
                }
                result["operationId"] = operationId;
                result["source"] = source;
            }
            else if (command == "openMany")
            {
                // exact envelope：四键 source + count 整数 2..64（裁决 §5.2）
                if (!IsExactObject(
                        payload,
                        "v", "operationId", "panelInstanceId",
                        "sessionGeneration", "source", "count")
                    || !TryReadOperationId(
                        payload["operationId"], out operationId)
                    || !TryNormalizeSource(
                        payload["source"] as JObject,
                        out JObject source)
                    || !TryReadInteger(
                        payload["count"], 2, InboxCapacity, out int count))
                {
                    return false;
                }
                result["operationId"] = operationId;
                result["source"] = source;
                result["count"] = count;
            }
            else if (command == "query")
            {
                if (!IsExactObject(
                        payload,
                        "v", "operationId", "panelInstanceId",
                        "sessionGeneration")
                    || !TryReadOperationId(
                        payload["operationId"], out operationId))
                {
                    return false;
                }
                result["operationId"] = operationId;
            }
            else if (command == "inboxSnapshot"
                || command == "cooldownSnapshot")
            {
                if (!IsExactObject(
                        payload,
                        "v", "panelInstanceId", "sessionGeneration"))
                {
                    return false;
                }
            }
            else
            {
                return false;
            }
            normalized = result;
            return true;
        }

        private static bool TryNormalizeSource(
            JObject source,
            out JObject normalized)
        {
            normalized = null;
            if (!IsExactObject(
                    source,
                    "physicalSlot", "slotLease", "itemName", "backpackVersion")
                || !TryReadInteger(
                    source["physicalSlot"], 0, 49, out int physicalSlot)
                || !TryReadToken(source["slotLease"], out string slotLease)
                || !TryReadSafeText(
                    source["itemName"], 160, false, out string itemName)
                || !TryReadInteger(
                    source["backpackVersion"],
                    0,
                    int.MaxValue,
                    out int backpackVersion))
            {
                return false;
            }
            normalized = new JObject
            {
                ["physicalSlot"] = physicalSlot,
                ["slotLease"] = slotLease,
                ["itemName"] = itemName,
                ["backpackVersion"] = backpackVersion
            };
            return true;
        }

        private static bool TrySanitizeResponse(
            JObject message,
            PendingRequest entry,
            out JObject sanitized,
            out bool definitiveWrite,
            out bool reconciled)
        {
            sanitized = null;
            definitiveWrite = false;
            reconciled = false;
            if (message == null
                || entry == null
                || ReadString(message["task"]) != "item_use_response"
                || !TryReadInteger(message["v"], 1, 1, out int version)
                || message["success"] == null
                || message["success"].Type != JTokenType.Boolean
                || ReadString(message["command"]) != entry.WebCommand
                || ReadString(message["panelInstanceId"])
                    != entry.PanelInstanceId
                || !TryReadLongInteger(
                    message["sessionGeneration"],
                    1,
                    int.MaxValue,
                    out long responseGeneration)
                || responseGeneration != entry.SessionGeneration)
            {
                return false;
            }
            bool hasOperation = entry.WebCommand != "inboxSnapshot"
                && entry.WebCommand != "cooldownSnapshot";
            if (hasOperation
                && ReadString(message["operationId"]) != entry.OperationId)
            {
                return false;
            }
            if (!hasOperation && message.Property("operationId") != null)
                return false;

            bool success = message.Value<bool>("success");
            JObject result = new JObject
            {
                ["success"] = success
            };
            if (!success)
            {
                int expectedCount = hasOperation ? 9 : 8;
                if (message.Count != expectedCount
                    || !HasCommonResponseKeys(message, hasOperation)
                    || message.Property("error") == null
                    || !TryReadSafeText(
                        message["error"], 96, false, out string error))
                {
                    return false;
                }
                result["error"] = error;
                definitiveWrite = entry.IsWrite
                    && DefinitiveWriteErrors.Contains(error);
                sanitized = result;
                return true;
            }

            bool valid;
            switch (entry.WebCommand)
            {
                case "open":
                    valid = TrySanitizeOpenSuccess(message, result);
                    definitiveWrite = valid;
                    break;
                case "openMany":
                    valid = TrySanitizeOpenManySuccess(message, result);
                    definitiveWrite = valid;
                    break;
                case "consume":
                    valid = TrySanitizeConsumeSuccess(message, result);
                    definitiveWrite = valid;
                    break;
                case "query":
                    valid = TrySanitizeQuerySuccess(
                        message,
                        entry.ReconcileWriteCommand,
                        result);
                    reconciled = valid;
                    break;
                case "inboxSnapshot":
                    valid = TrySanitizeInboxSnapshotSuccess(message, result);
                    break;
                case "cooldownSnapshot":
                    valid = TrySanitizeCooldownSnapshotSuccess(message, result);
                    break;
                default:
                    valid = false;
                    break;
            }
            if (!valid) return false;
            sanitized = result;
            return true;
        }

        private static bool TrySanitizeOpenSuccess(
            JObject message,
            JObject result)
        {
            if (!HasExactResponseKeys(
                    message,
                    true,
                    "consumed", "remaining", "rewardReady", "rewardBatchId",
                    "inboxSummary", "rewardAuthority")
                || !TryReadInteger(message["consumed"], 1, 1, out int consumed)
                || !TryReadLongInteger(
                    message["remaining"], 0, MaxSafeInteger, out long remaining)
                || message["rewardReady"] == null
                || message["rewardReady"].Type != JTokenType.Boolean
                || !TryReadToken(
                    message["rewardBatchId"], out string rewardBatchId)
                || !TrySanitizeInboxSummary(
                    message["inboxSummary"] as JObject, out JObject summary)
                || !TrySanitizeRewardAuthority(
                    message["rewardAuthority"], summary, out JObject authority))
            {
                return false;
            }
            bool rewardReady = message.Value<bool>("rewardReady");
            if (rewardReady
                != (summary.Value<int>("remainingCount") > 0))
                return false;
            result["consumed"] = consumed;
            result["remaining"] = remaining;
            result["rewardReady"] = rewardReady;
            result["rewardBatchId"] = rewardBatchId;
            result["inboxSummary"] = summary;
            result["rewardAuthority"] = authority == null
                ? JValue.CreateNull() : (JToken)authority;
            return true;
        }

        /// <summary>
        /// openMany fresh/replay success（裁决 §5.5/§5.6）：exact keys；
        /// requestedCount==consumed==K；packages 长度 K、ordinal 连续 0..K-1、
        /// batchId 非空且互不重复、entryCount 0..64；summary/authority 走现有
        /// sanitizer；replayed 为布尔（fresh=false，receipt replay=true）。
        /// </summary>
        private static bool TrySanitizeOpenManySuccess(
            JObject message,
            JObject result)
        {
            if (!HasExactResponseKeys(
                    message,
                    true,
                    "replayed", "requestedCount", "consumed", "remaining",
                    "packages", "rewardReady", "inboxSummary", "rewardAuthority")
                || message["replayed"] == null
                || message["replayed"].Type != JTokenType.Boolean
                || !TryReadInteger(
                    message["requestedCount"], 2, InboxCapacity,
                    out int requestedCount)
                || !TryReadInteger(
                    message["consumed"], 2, InboxCapacity, out int consumed)
                || consumed != requestedCount
                || !TryReadLongInteger(
                    message["remaining"], 0, MaxSafeInteger,
                    out long remaining)
                || !(message["packages"] is JArray packages)
                || packages.Count != requestedCount
                || message["rewardReady"] == null
                || message["rewardReady"].Type != JTokenType.Boolean
                || !TrySanitizeInboxSummary(
                    message["inboxSummary"] as JObject, out JObject summary)
                || !TrySanitizeRewardAuthority(
                    message["rewardAuthority"], summary,
                    out JObject authority))
            {
                return false;
            }
            var batchIds = new HashSet<string>(StringComparer.Ordinal);
            var normalizedPackages = new JArray();
            for (int i = 0; i < packages.Count; i++)
            {
                JObject row = packages[i] as JObject;
                if (!IsExactObject(row, "ordinal", "batchId", "entryCount")
                    || !TryReadInteger(row["ordinal"], i, i, out int ordinal)
                    || !TryReadToken(row["batchId"], out string batchId)
                    || !batchIds.Add(batchId)
                    || !TryReadInteger(
                        row["entryCount"], 0, InboxCapacity,
                        out int entryCount))
                {
                    return false;
                }
                normalizedPackages.Add(new JObject
                {
                    ["ordinal"] = ordinal,
                    ["batchId"] = batchId,
                    ["entryCount"] = entryCount
                });
            }
            bool rewardReady = message.Value<bool>("rewardReady");
            if (rewardReady != (summary.Value<int>("remainingCount") > 0
                    || summary.Value<bool>("recoveryRequired")))
            {
                return false;
            }
            result["replayed"] = message.Value<bool>("replayed");
            result["requestedCount"] = requestedCount;
            result["consumed"] = consumed;
            result["remaining"] = remaining;
            result["packages"] = normalizedPackages;
            result["rewardReady"] = rewardReady;
            result["inboxSummary"] = summary;
            result["rewardAuthority"] = authority == null
                ? JValue.CreateNull() : (JToken)authority;
            return true;
        }

        private static bool TrySanitizeConsumeSuccess(
            JObject message,
            JObject result)
        {
            if (!HasExactResponseKeys(
                    message,
                    true,
                    "consumed", "remaining", "selectedLane")
                || !TryReadInteger(message["consumed"], 1, 1, out int consumed)
                || !TryReadLongInteger(
                    message["remaining"], 0, MaxSafeInteger, out long remaining)
                || !TryReadInteger(
                    message["selectedLane"], 0, 3, out int selectedLane))
            {
                return false;
            }
            result["consumed"] = consumed;
            result["remaining"] = remaining;
            result["selectedLane"] = selectedLane;
            return true;
        }

        private static bool TrySanitizeQuerySuccess(
            JObject message,
            string expectedWriteCommand,
            JObject result)
        {
            if (expectedWriteCommand != "open"
                && expectedWriteCommand != "openMany"
                && expectedWriteCommand != "consume")
            {
                return false;
            }
            if (message["found"] == null
                || message["found"].Type != JTokenType.Boolean
                || !TrySanitizeInboxSummary(
                    message["inboxSummary"] as JObject, out JObject summary))
            {
                return false;
            }
            bool found = message.Value<bool>("found");
            if (!found)
            {
                if (!HasExactResponseKeys(
                        message, true, "found", "inboxSummary"))
                {
                    return false;
                }
                result["found"] = false;
                result["inboxSummary"] = summary;
                return true;
            }
            if (!HasExactResponseKeys(
                    message, true, "found", "receipt", "inboxSummary")
                || !TrySanitizeReceipt(
                    message["receipt"] as JObject,
                    expectedWriteCommand,
                    out JObject receipt))
            {
                return false;
            }
            result["found"] = true;
            result["receipt"] = receipt;
            result["inboxSummary"] = summary;
            return true;
        }

        private static bool TrySanitizeInboxSnapshotSuccess(
            JObject message,
            JObject result)
        {
            if (!HasExactResponseKeys(
                    message,
                    false,
                    "inboxSummary", "rewardReady", "rewardAuthority")
                || !TrySanitizeInboxSummary(
                    message["inboxSummary"] as JObject, out JObject summary)
                || message["rewardReady"] == null
                || message["rewardReady"].Type != JTokenType.Boolean
                || !TrySanitizeRewardAuthority(
                    message["rewardAuthority"], summary, out JObject authority))
            {
                return false;
            }
            bool rewardReady = message.Value<bool>("rewardReady");
            if (rewardReady != (summary.Value<int>("remainingCount") > 0
                    || summary.Value<bool>("recoveryRequired")))
                return false;
            result["inboxSummary"] = summary;
            result["rewardReady"] = rewardReady;
            result["rewardAuthority"] = authority == null
                ? JValue.CreateNull() : (JToken)authority;
            return true;
        }

        private static bool TrySanitizeCooldownSnapshotSuccess(
            JObject message,
            JObject result)
        {
            if (!HasExactResponseKeys(
                    message, false, "cooldownLanes")
                || !(message["cooldownLanes"] is JArray lanes)
                || lanes.Count != 4)
            {
                return false;
            }
            var normalized = new JArray();
            for (int lane = 0; lane < lanes.Count; lane++)
            {
                JObject row = lanes[lane] as JObject;
                if (!IsExactObject(
                        row,
                        "lane", "ready", "totalSteps", "currentStep",
                        "progressPercent", "animationFrame", "remainingMs")
                    || !TryReadInteger(row["lane"], lane, lane, out int rowLane)
                    || row["ready"] == null
                    || row["ready"].Type != JTokenType.Boolean
                    || !TryReadInteger(
                        row["totalSteps"], 0, int.MaxValue, out int totalSteps)
                    || !TryReadInteger(
                        row["currentStep"], 0, totalSteps, out int currentStep)
                    || !TryReadInteger(
                        row["progressPercent"], 0, 100, out int progressPercent)
                    || !TryReadInteger(
                        row["animationFrame"], 0, 101, out int animationFrame)
                    || !TryReadLongInteger(
                        row["remainingMs"], 0, MaxSafeInteger, out long remainingMs))
                {
                    return false;
                }
                bool ready = row.Value<bool>("ready");
                if ((ready && remainingMs != 0)
                    || (!ready && (totalSteps < 1
                        || currentStep >= totalSteps
                        || remainingMs < 1))
                    || animationFrame != (ready ? 1 : 1 + progressPercent))
                {
                    return false;
                }
                normalized.Add(new JObject
                {
                    ["lane"] = rowLane,
                    ["ready"] = ready,
                    ["totalSteps"] = totalSteps,
                    ["currentStep"] = currentStep,
                    ["progressPercent"] = progressPercent,
                    ["animationFrame"] = animationFrame,
                    ["remainingMs"] = remainingMs
                });
            }
            result["cooldownLanes"] = normalized;
            return true;
        }

        private static bool TryReadReceiptConsumed(
            JObject receipt,
            string expectedKind,
            out int consumed)
        {
            return expectedKind == "openMany"
                ? TryReadInteger(
                    receipt["consumed"], 2, InboxCapacity, out consumed)
                : TryReadInteger(receipt["consumed"], 1, 1, out consumed);
        }

        private static bool TrySanitizeReceipt(
            JObject receipt,
            string expectedKind,
            out JObject sanitized)
        {
            sanitized = null;
            string[] specific = expectedKind == "open"
                ? new[] { "rewardBatchId", "rewardReady" }
                : expectedKind == "openMany"
                    ? new[] { "requestedCount", "packages" }
                    : new[] { "selectedLane" };
            var expected = new List<string>
            {
                "kind", "status", "consumed", "remaining"
            };
            expected.AddRange(specific);
            if (!IsExactObject(receipt, expected.ToArray())
                || ReadString(receipt["kind"]) != expectedKind
                || ReadString(receipt["status"]) != "committed"
                || !TryReadReceiptConsumed(receipt, expectedKind, out int consumed)
                || !TryReadLongInteger(
                    receipt["remaining"], 0, MaxSafeInteger, out long remaining))
            {
                return false;
            }
            var result = new JObject
            {
                ["kind"] = expectedKind,
                ["status"] = "committed",
                ["consumed"] = consumed,
                ["remaining"] = remaining
            };
            if (expectedKind == "open")
            {
                if (!TryReadToken(
                        receipt["rewardBatchId"], out string rewardBatchId)
                    || receipt["rewardReady"] == null
                    || receipt["rewardReady"].Type != JTokenType.Boolean)
                {
                    return false;
                }
                result["rewardBatchId"] = rewardBatchId;
                result["rewardReady"] = receipt.Value<bool>("rewardReady");
            }
            else if (expectedKind == "openMany")
            {
                // replay 投影必须与持久 receipt exact 同形（裁决 §5.6）
                if (!TryReadInteger(
                        receipt["requestedCount"], 2, InboxCapacity,
                        out int requestedCount)
                    || requestedCount != consumed
                    || !(receipt["packages"] is JArray packages)
                    || packages.Count != requestedCount)
                {
                    return false;
                }
                var batchIds = new HashSet<string>(StringComparer.Ordinal);
                var normalizedPackages = new JArray();
                for (int i = 0; i < packages.Count; i++)
                {
                    JObject row = packages[i] as JObject;
                    if (!IsExactObject(row, "ordinal", "batchId", "entryCount")
                        || !TryReadInteger(
                            row["ordinal"], i, i, out int ordinal)
                        || !TryReadToken(row["batchId"], out string batchId)
                        || !batchIds.Add(batchId)
                        || !TryReadInteger(
                            row["entryCount"], 0, InboxCapacity,
                            out int entryCount))
                    {
                        return false;
                    }
                    normalizedPackages.Add(new JObject
                    {
                        ["ordinal"] = ordinal,
                        ["batchId"] = batchId,
                        ["entryCount"] = entryCount
                    });
                }
                result["requestedCount"] = requestedCount;
                result["packages"] = normalizedPackages;
            }
            else
            {
                if (!TryReadInteger(
                        receipt["selectedLane"], 0, 3, out int selectedLane))
                {
                    return false;
                }
                result["selectedLane"] = selectedLane;
            }
            sanitized = result;
            return true;
        }

        private static bool TrySanitizeInboxSummary(
            JObject value,
            out JObject sanitized)
        {
            sanitized = null;
            if (!IsExactObject(
                     value,
                     "v", "batchCount", "remainingCount", "capacity",
                     "authorityRevision", "recoverableRootOperationId",
                     "recoverableRootStatus", "recoveryRequired")
                || !TryReadInteger(value["v"], 1, 1, out int version)
                || !TryReadInteger(
                    value["batchCount"], 0, InboxCapacity, out int batchCount)
                || !TryReadInteger(
                    value["remainingCount"],
                    0,
                    InboxCapacity,
                    out int remainingCount)
                || !TryReadInteger(
                    value["capacity"],
                    InboxCapacity,
                    InboxCapacity,
                    out int capacity)
                || !TryReadInteger(
                    value["authorityRevision"],
                    0,
                    int.MaxValue,
                    out int authorityRevision)
                 || batchCount > remainingCount
                 || !TryReadSafeText(value["recoverableRootOperationId"], 128, true,
                    out string recoverableRootOperationId)
                 || !TryReadSafeText(value["recoverableRootStatus"], 32, false,
                    out string recoverableRootStatus)
                 || value["recoveryRequired"] == null
                 || value["recoveryRequired"].Type != JTokenType.Boolean
                 || !IsRewardRootStatus(recoverableRootStatus)
                 || (!string.IsNullOrEmpty(recoverableRootOperationId)
                    && !LootPanelCoordinator.IsOpaque(recoverableRootOperationId))
                 || string.IsNullOrEmpty(recoverableRootOperationId)
                    != (recoverableRootStatus == "not_started")
                 || value.Value<bool>("recoveryRequired")
                    && string.IsNullOrEmpty(recoverableRootOperationId))
            {
                return false;
            }
            sanitized = new JObject
            {
                ["v"] = 1,
                ["batchCount"] = batchCount,
                ["remainingCount"] = remainingCount,
                ["capacity"] = capacity,
                 ["authorityRevision"] = authorityRevision,
                 ["recoverableRootOperationId"] = recoverableRootOperationId,
                 ["recoverableRootStatus"] = recoverableRootStatus,
                 ["recoveryRequired"] = value.Value<bool>("recoveryRequired")
            };
            return true;
        }

        private static bool TrySanitizeRewardAuthority(
            JToken token,
            JObject summary,
            out JObject sanitized)
        {
            sanitized = null;
            if (token == null || token.Type == JTokenType.Null)
                return true;
            JObject value = token as JObject;
            if (!IsExactObject(
                    value,
                    "sourceKind", "chestSessionId", "lootContainerId",
                     "containerEpoch", "openAttemptSeq", "displayName",
                     "authorityRevision", "state", "remainingCount",
                     "capacity", "columns", "recoverableRootOperationId",
                     "recoverableRootStatus", "recoveryRequired", "recoveryOnly")
                || ReadString(value["sourceKind"]) != "reward_inbox"
                || !TryReadToken(
                    value["chestSessionId"], out string chestSessionId)
                || !TryReadToken(
                    value["lootContainerId"], out string lootContainerId)
                || !TryReadInteger(
                    value["containerEpoch"], 1, int.MaxValue, out int epoch)
                || !TryReadInteger(
                    value["openAttemptSeq"], 1, int.MaxValue,
                    out int openAttemptSeq)
                || !TryReadSafeText(
                    value["displayName"], 80, false, out string displayName)
                || displayName != "待领取物品"
                || !TryReadInteger(
                    value["authorityRevision"],
                    0,
                    int.MaxValue,
                    out int authorityRevision)
                || ReadString(value["state"]) != "LOOT_ACTIVE"
                 || !TryReadInteger(
                     value["remainingCount"],
                     0,
                    InboxCapacity,
                    out int remainingCount)
                || !TryReadInteger(
                    value["capacity"],
                    1,
                    InboxCapacity,
                    out int capacity)
                || remainingCount > capacity
                || !TryReadInteger(
                    value["columns"], 1, 8, out int columns)
                || columns != Math.Min(8, capacity)
                 || !TryReadSafeText(value["recoverableRootOperationId"], 128, true,
                    out string recoverableRootOperationId)
                 || !TryReadSafeText(value["recoverableRootStatus"], 32, false,
                    out string recoverableRootStatus)
                 || value["recoveryRequired"] == null
                 || value["recoveryRequired"].Type != JTokenType.Boolean
                 || value["recoveryOnly"] == null
                 || value["recoveryOnly"].Type != JTokenType.Boolean
                 || !IsRewardRootStatus(recoverableRootStatus)
                 || (!string.IsNullOrEmpty(recoverableRootOperationId)
                    && !LootPanelCoordinator.IsOpaque(recoverableRootOperationId))
                 || summary == null
                 || remainingCount != summary.Value<int>("remainingCount")
                 || recoverableRootOperationId
                    != summary.Value<string>("recoverableRootOperationId")
                 || recoverableRootStatus
                    != summary.Value<string>("recoverableRootStatus")
                 || value.Value<bool>("recoveryRequired")
                    != summary.Value<bool>("recoveryRequired")
                 || value.Value<bool>("recoveryOnly") != (remainingCount == 0)
                 || value.Value<bool>("recoveryOnly")
                    && !value.Value<bool>("recoveryRequired"))
            {
                return false;
            }
            sanitized = new JObject
            {
                ["sourceKind"] = "reward_inbox",
                ["chestSessionId"] = chestSessionId,
                ["lootContainerId"] = lootContainerId,
                ["containerEpoch"] = epoch,
                ["openAttemptSeq"] = openAttemptSeq,
                ["displayName"] = displayName,
                ["authorityRevision"] = authorityRevision,
                ["state"] = "LOOT_ACTIVE",
                ["remainingCount"] = remainingCount,
                ["capacity"] = capacity,
                 ["columns"] = columns,
                 ["recoverableRootOperationId"] = recoverableRootOperationId,
                 ["recoverableRootStatus"] = recoverableRootStatus,
                 ["recoveryRequired"] = value.Value<bool>("recoveryRequired"),
                 ["recoveryOnly"] = value.Value<bool>("recoveryOnly")
            };
            return true;
        }

        private static bool IsRewardRootStatus(string value)
        {
            return value == "not_started" || value == "pending" || value == "committed"
                || value == "terminal_failure" || value == "quarantined";
        }

        private static bool HasCommonResponseKeys(
            JObject value,
            bool hasOperationId)
        {
            string[] common = hasOperationId
                ? new[]
                {
                    "task", "callId", "v", "success", "command",
                    "operationId", "panelInstanceId", "sessionGeneration"
                }
                : new[]
                {
                    "task", "callId", "v", "success", "command",
                    "panelInstanceId", "sessionGeneration"
                };
            foreach (string name in common)
            {
                if (value.Property(name) == null) return false;
            }
            return true;
        }

        private static bool HasExactResponseKeys(
            JObject value,
            bool hasOperationId,
            params string[] extra)
        {
            var names = new List<string>(
                hasOperationId
                    ? new[]
                    {
                        "task", "callId", "v", "success", "command",
                        "operationId", "panelInstanceId", "sessionGeneration"
                    }
                    : new[]
                    {
                        "task", "callId", "v", "success", "command",
                        "panelInstanceId", "sessionGeneration"
                    });
            names.AddRange(extra);
            return IsExactObject(value, names.ToArray());
        }

        private static bool IsExactObject(
            JObject value,
            params string[] names)
        {
            if (value == null || value.Count != names.Length) return false;
            foreach (string name in names)
            {
                if (value.Property(name) == null) return false;
            }
            return true;
        }

        private static string ReadString(JToken token)
        {
            return token != null && token.Type == JTokenType.String
                ? token.Value<string>() : null;
        }

        private static bool IsCallId(string value)
        {
            return !string.IsNullOrEmpty(value) && ValidCallId.IsMatch(value);
        }

        private static bool TryReadOperationId(
            JToken token,
            out string value)
        {
            return TryReadToken(token, out value) && value.Length <= 96;
        }

        private static bool TryReadToken(JToken token, out string value)
        {
            value = ReadString(token);
            return !string.IsNullOrEmpty(value) && ValidToken.IsMatch(value);
        }

        private static bool TryReadSafeText(
            JToken token,
            int maxLength,
            bool allowEmpty,
            out string value)
        {
            value = ReadString(token);
            if (value == null || value.Length > maxLength
                || (!allowEmpty && value.Length == 0))
            {
                return false;
            }
            foreach (char character in value)
            {
                if (character < 0x20 || character == 0x7f) return false;
            }
            return true;
        }

        private static bool TryReadInteger(
            JToken token,
            int minimum,
            int maximum,
            out int value)
        {
            value = 0;
            if (!TryReadLongInteger(
                    token, minimum, maximum, out long candidate))
            {
                return false;
            }
            value = (int)candidate;
            return true;
        }

        private static bool TryReadLongInteger(
            JToken token,
            long minimum,
            long maximum,
            out long value)
        {
            value = 0;
            if (token == null || token.Type != JTokenType.Integer) return false;
            try { value = token.Value<long>(); }
            catch { return false; }
            return value >= minimum && value <= maximum;
        }

        private void PostToWeb(string json)
        {
            if (_invokeOnUI != null)
            {
                _invokeOnUI(delegate
                {
                    lock (_gate)
                    {
                        if (_disposed) return;
                    }
                    Action<string> post = _postToWeb;
                    if (post != null) post(json);
                });
                return;
            }
            lock (_gate)
            {
                if (_disposed) return;
            }
            Action<string> direct = _postToWeb;
            if (direct != null) direct(json);
        }
    }
}
