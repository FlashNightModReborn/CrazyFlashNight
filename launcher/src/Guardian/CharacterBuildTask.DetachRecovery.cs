using System;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using CF7Launcher.Tasks;

namespace CF7Launcher.Guardian
{
    /// <summary>
    /// Character-build-specific orphan recovery. This is intentionally not a Web command and
    /// intentionally does not share Loot's authority coordinator: the only recoverable authority
    /// here is the exact CharacterBuild panel/session pair retained by this task.
    /// </summary>
    public sealed partial class CharacterBuildTask
    {
        private const string DetachRecoveryCommand = "recoverDetach";
        private const string DetachRecoveryAction = "characterBuildRecoverDetach";
        private const int MaxAutomaticDetachRecoveryRetires = 1;

        private bool _detachRecoveryRequired;
        private bool _detachRecoveryInFlight;
        private bool _detachRecoveryAwaitingVisualRetire;
        private int _detachRecoveryEpoch;
        private int _detachRecoveryBackendCallId;
        private int _detachRecoveryTransportGeneration;
        private int _detachRecoveryClosedGeneration;
        private int _detachRecoveryCallSequence;
        private string _detachRecoveryReason;
        private string _detachRecoveryStatus = "idle";
        private string _detachRecoveryFailure;
        private int _detachRecoveryAutomaticRetires;
        private int _detachRecoveryBlockedNotificationGeneration;

        /// <summary>
        /// A new Web document cannot retain the exact JS owner of the bound session. Freeze the
        /// Host binding before the old document disappears, then query/settle AS2 on the captured
        /// socket generation when one is available.
        /// </summary>
        internal bool BeginWebViewDetach(int readyGeneration)
        {
            int recoveryEpoch;
            lock (_bindingGate)
            {
                lock (_gate)
                {
                    if (_disposed
                        || string.IsNullOrEmpty(
                            _panelInstanceId))
                    {
                        return false;
                    }
                    recoveryEpoch = _detachRecoveryRequired
                        ? _detachRecoveryEpoch : 0;
                }
                if (recoveryEpoch == 0)
                {
                    return RequireDetachRecovery(
                        "web_navigation",
                        0,
                        readyGeneration,
                        false);
                }
            }

            // NavigationStarting can fire repeatedly for one redirect/reload chain. Preserve the
            // original epoch and pending proof; at most fill a genuinely new ready generation.
            if (readyGeneration > 0)
                DispatchDetachRecovery(
                    recoveryEpoch,
                    readyGeneration);
            int currentGeneration =
                SafeReadyGeneration();
            if (currentGeneration > 0)
                DispatchDetachRecovery(
                    recoveryEpoch,
                    currentGeneration);
            return true;
        }

        /// <summary>
        /// Installs the no-new-calls/no-rebind barrier without sending recoverDetach.  The caller
        /// must first retire the current Host visual and then call
        /// ContinueDetachRecoveryAfterVisualRetired.  This prevents AS2 from releasing the shared
        /// pause lease while a same-document replacement panel is still visible.
        /// </summary>
        internal bool BeginWebViewDetachBarrier()
        {
            lock (_gate)
            {
                if (_disposed
                    || string.IsNullOrEmpty(_panelInstanceId))
                {
                    return false;
                }
                if (_detachRecoveryRequired) return true;
            }
            return RequireDetachRecovery(
                "web_navigation", 0, 0, true);
        }

        /// <summary>
        /// A normal close also requires an acknowledged AS2 terminal proof. A successful socket
        /// write of generic webPanelUnpause is insufficient because the AS2 lease release can fail
        /// after delivery. The exact Host-only recovery response is the sole binding-consumption
        /// point for both normal and orphan close.
        /// </summary>
        internal bool BeginNormalClose(int readyGeneration)
        {
            return RequireDetachRecovery(
                "normal_close", 0, readyGeneration, false);
        }

        internal bool BeginNormalCloseBarrier(
            string panelInstanceId)
        {
            if (string.IsNullOrEmpty(panelInstanceId)) return false;
            lock (_bindingGate)
            {
                lock (_gate)
                {
                    if (_disposed
                        || !string.Equals(
                            _panelInstanceId,
                            panelInstanceId,
                            StringComparison.Ordinal))
                    {
                        return false;
                    }
                    if (_detachRecoveryRequired) return true;
                }
                return RequireDetachRecovery(
                    "normal_close", 0, 0, true);
            }
        }

        internal bool BeginSocketDetachBarrier(
            int closedGeneration)
        {
            return RequireDetachRecovery(
                "socket_detach",
                closedGeneration,
                0,
                true);
        }

        /// <summary>
        /// The Host calls this only after its native/Web visual is definitively idle.  Reconnects
        /// observed before this point remain fenced and cannot dispatch recovery.
        /// </summary>
        internal bool ContinueDetachRecoveryAfterVisualRetired(
            int readyGeneration)
        {
            int recoveryEpoch;
            lock (_gate)
            {
                if (_disposed || !_detachRecoveryRequired
                    || string.IsNullOrEmpty(_panelInstanceId))
                {
                    return false;
                }
                _detachRecoveryAwaitingVisualRetire = false;
                if (!_detachRecoveryInFlight)
                    _detachRecoveryStatus = "awaiting_transport";
                recoveryEpoch = _detachRecoveryEpoch;
            }

            if (readyGeneration > 0)
                DispatchDetachRecovery(
                    recoveryEpoch, readyGeneration);
            int currentGeneration = SafeReadyGeneration();
            if (currentGeneration > 0)
                DispatchDetachRecovery(
                    recoveryEpoch, currentGeneration);
            return true;
        }

        /// <summary>
        /// Idempotent exact-instance close entry for Host-owned visual transitions. PanelHost's
        /// close observer may run after the router or Web close path has already started recovery;
        /// in that case it must preserve the in-flight proof instead of restarting it or consuming
        /// the binding from a finalize receipt alone.
        /// </summary>
        internal bool EnsureNormalClose(string panelInstanceId)
        {
            if (string.IsNullOrEmpty(panelInstanceId)) return false;
            int readyGeneration = SafeReadyGeneration();
            lock (_bindingGate)
            {
                lock (_gate)
                {
                    if (_disposed
                        || !string.Equals(
                            _panelInstanceId,
                            panelInstanceId,
                            StringComparison.Ordinal))
                    {
                        return false;
                    }
                    if (_detachRecoveryRequired) return true;
                }
                return RequireDetachRecovery(
                    "normal_close", 0, readyGeneration, false);
            }
        }

        /// <summary>
        /// Typed socket-ready continuation. Recovery is always sent to the exact ready generation;
        /// a generic TrySend is never used for this authority transition.
        /// </summary>
        internal bool OnSocketReconnected(int readyGeneration)
        {
            if (readyGeneration <= 0
                || SafeReadyGeneration() != readyGeneration) return false;

            bool replaceStaleAttempt;
            lock (_gate)
            {
                if (_disposed || !_detachRecoveryRequired) return false;
                if (_detachRecoveryAwaitingVisualRetire) return true;
                if (_detachRecoveryTransportGeneration == readyGeneration)
                {
                    // Exactly one attempt is admitted for each ready transport generation.
                    // A known failure remains explicitly blocked until a later generation.
                    return true;
                }
                replaceStaleAttempt = _detachRecoveryInFlight
                    && _detachRecoveryTransportGeneration != readyGeneration;
                if (!replaceStaleAttempt && _detachRecoveryInFlight)
                    return true;
            }

            if (replaceStaleAttempt)
            {
                return RequireDetachRecovery(
                    "socket_reconnect", 0, readyGeneration, false);
            }
            return DispatchDetachRecovery(
                CurrentDetachRecoveryEpoch(), readyGeneration);
        }

        /// <summary>
        /// Controlled process exit must not dispose the task or kill Flash while an active build
        /// session may still own unpersisted authority. Reuse the existing exact-generation
        /// recoverDetach transaction: it synchronizes live state, finalizes, flushes persistence,
        /// and proves the captured pause release. This Host-only entry never posts to Web and
        /// never creates a second finalize wire format.
        /// </summary>
        internal bool TryCompleteHostShutdownPersistence(
            int timeoutMs,
            out string outcome)
        {
            timeoutMs = Math.Max(1, timeoutMs);
            int readyGeneration =
                SafeReadyGeneration();
            bool continueExisting = false;
            bool installRecovery = false;

            lock (_bindingGate)
            {
                lock (_gate)
                {
                    if (_disposed)
                        return LogHostShutdownFence(
                            false, "disposed", out outcome);
                    if (string.IsNullOrEmpty(
                            _panelInstanceId))
                    {
                        return LogHostShutdownFence(
                            true, "no_binding", out outcome);
                    }
                    if (!_sessionGeneration.HasValue)
                    {
                        return LogHostShutdownFence(
                            true, "no_session", out outcome);
                    }
                    if (HasFinalizeProofLocked())
                    {
                        return LogHostShutdownFence(
                            true,
                            "finalize_proven",
                            out outcome);
                    }

                    if (_detachRecoveryRequired)
                    {
                        if (_detachRecoveryStatus
                            == "fatal_blocked")
                        {
                            return LogHostShutdownFence(
                                false,
                                "recovery_"
                                    + (_detachRecoveryFailure
                                        ?? "fatal"),
                                out outcome);
                        }
                        continueExisting = true;
                    }
                    else
                    {
                        if (_pendingCount != 0)
                        {
                            return LogHostShutdownFence(
                                false,
                                "pending_calls",
                                out outcome);
                        }
                        if (_writeState != "idle"
                            && _writeState
                                != "flush_failed")
                        {
                            return LogHostShutdownFence(
                                false,
                                "write_state_"
                                    + (_writeState
                                        ?? "unknown"),
                                out outcome);
                        }
                        if (readyGeneration <= 0)
                        {
                            return LogHostShutdownFence(
                                false,
                                "transport_not_ready",
                                out outcome);
                        }

                        // Close the admission race before RequireDetachRecovery acquires its
                        // nested locks. TryBeginHostAcceptedCore rejects binding_in_progress.
                        _bindingChanging = true;
                        installRecovery = true;
                    }
                }

                if (installRecovery)
                {
                    bool installed = false;
                    try
                    {
                        installed = RequireDetachRecovery(
                            "host_shutdown",
                            0,
                            readyGeneration,
                            false);
                    }
                    finally
                    {
                        lock (_gate)
                        {
                            if (_bindingChanging)
                                _bindingChanging = false;
                        }
                    }
                    if (!installed)
                    {
                        return LogHostShutdownFence(
                            false,
                            "recovery_not_installed",
                            out outcome);
                    }
                }
                else if (continueExisting)
                {
                    string status;
                    lock (_gate)
                        status = _detachRecoveryStatus;
                    if (status
                        == "awaiting_visual_retire")
                    {
                        ContinueDetachRecoveryAfterVisualRetired(
                            readyGeneration);
                    }
                    else if (status
                        == "awaiting_transport")
                    {
                        OnSocketReconnected(
                            readyGeneration);
                    }
                }
            }

            var stopwatch =
                System.Diagnostics.Stopwatch.StartNew();
            lock (_gate)
            {
                while (true)
                {
                    if (_disposed)
                        return LogHostShutdownFence(
                            false, "disposed", out outcome);
                    if (string.IsNullOrEmpty(
                            _panelInstanceId))
                    {
                        return LogHostShutdownFence(
                            true,
                            "recovery_settled",
                            out outcome);
                    }
                    if (_detachRecoveryStatus
                        == "fatal_blocked")
                    {
                        return LogHostShutdownFence(
                            false,
                            "recovery_"
                                + (_detachRecoveryFailure
                                    ?? "fatal"),
                            out outcome);
                    }
                    if (_detachRecoveryStatus
                            == "awaiting_reconnect"
                        || _detachRecoveryStatus
                            == "awaiting_transport"
                        || _detachRecoveryStatus
                            == "awaiting_visual_retire")
                    {
                        return LogHostShutdownFence(
                            false,
                            "recovery_"
                                + _detachRecoveryStatus,
                            out outcome);
                    }

                    int remaining =
                        timeoutMs
                        - (int)stopwatch.ElapsedMilliseconds;
                    if (remaining <= 0
                        || !System.Threading.Monitor.Wait(
                            _gate,
                            remaining))
                    {
                        return LogHostShutdownFence(
                            false,
                            "timeout",
                            out outcome);
                    }
                }
            }
        }

        private static bool LogHostShutdownFence(
            bool passed,
            string reason,
            out string outcome)
        {
            outcome = reason ?? "unknown";
            LogManager.Log(
                "event=character_build_shutdown_fence result="
                + (passed ? "pass" : "blocked")
                + " reason=" + outcome);
            return passed;
        }

        private bool RequireDetachRecovery(
            string reason,
            int closedGeneration,
            int immediateTransportGeneration,
            bool awaitVisualRetire)
        {
            bool hasBinding;
            int recoveryEpoch = 0;
            bool continuingRecovery;
            lock (_bindingGate)
            {
                lock (_gate)
                {
                    if (_disposed) return false;
                    hasBinding = !string.IsNullOrEmpty(_panelInstanceId);
                    continuingRecovery =
                        hasBinding && _detachRecoveryRequired;
                    if (hasBinding)
                    {
                        _bindingChanging = true;
                        _detachRecoveryRequired = true;
                        _detachRecoveryInFlight = false;
                        _detachRecoveryBackendCallId = 0;
                        _detachRecoveryTransportGeneration = 0;
                        _detachRecoveryAwaitingVisualRetire =
                            awaitVisualRetire;
                        _detachRecoveryReason = reason ?? "detach";
                        _detachRecoveryStatus = awaitVisualRetire
                            ? "awaiting_visual_retire"
                            : "awaiting_transport";
                        _detachRecoveryFailure = null;
                        if (!continuingRecovery)
                        {
                            _detachRecoveryAutomaticRetires = 0;
                            _detachRecoveryBlockedNotificationGeneration = 0;
                        }
                        if (closedGeneration > _detachRecoveryClosedGeneration)
                            _detachRecoveryClosedGeneration = closedGeneration;
                        _detachRecoveryEpoch =
                            unchecked(_detachRecoveryEpoch + 1);
                        if (_detachRecoveryEpoch <= 0)
                            _detachRecoveryEpoch = 1;
                        recoveryEpoch = _detachRecoveryEpoch;
                    }
                }

                try
                {
                    // Clear every accepted browser call before recovery is dispatched. Writes are
                    // therefore classified unknown by the existing callback; their old call IDs
                    // remain recent and can never be replayed into the recovered binding.
                    _pendingCalls.Clear();
                }
                finally
                {
                    if (hasBinding)
                    {
                        lock (_gate) _bindingChanging = false;
                    }
                }
            }

            if (!hasBinding) return false;
            LogManager.Log("[CharacterBuildTask] detach recovery required epoch="
                + recoveryEpoch + " reason=" + _detachRecoveryReason
                + " closedGeneration=" + closedGeneration);
            if (awaitVisualRetire) return true;
            if (immediateTransportGeneration > 0)
                DispatchDetachRecovery(
                    recoveryEpoch, immediateTransportGeneration);
            // The ready generation can rotate between the caller's snapshot and the first
            // generation check above. Re-read once after the barrier is installed so an already
            // completed reconnect cannot leave recovery waiting for an event that already fired.
            int currentTransportGeneration =
                SafeReadyGeneration();
            if (currentTransportGeneration > 0
                && currentTransportGeneration
                    != closedGeneration)
                DispatchDetachRecovery(
                    recoveryEpoch,
                    currentTransportGeneration);
            return true;
        }

        private int CurrentDetachRecoveryEpoch()
        {
            lock (_gate) return _detachRecoveryEpoch;
        }

        private bool DispatchDetachRecovery(
            int recoveryEpoch,
            int transportGeneration)
        {
            if (transportGeneration <= 0
                || SafeReadyGeneration() != transportGeneration) return false;

            PendingRequest entry;
            int backendCallId;
            lock (_gate)
            {
                if (_disposed || !_detachRecoveryRequired
                    || _bindingChanging || _detachRecoveryInFlight
                    || _detachRecoveryAwaitingVisualRetire
                    || string.IsNullOrEmpty(_panelInstanceId)
                    || recoveryEpoch != _detachRecoveryEpoch
                    || _detachRecoveryTransportGeneration
                        == transportGeneration
                    || SafeReadyGeneration() != transportGeneration)
                {
                    return false;
                }

                int requestSequence =
                    unchecked(++_detachRecoveryCallSequence);
                if (requestSequence <= 0)
                {
                    _detachRecoveryCallSequence = 1;
                    requestSequence = 1;
                }
                string requestCallId = "host.recover."
                    + recoveryEpoch + "." + requestSequence;
                entry = new PendingRequest
                {
                    PanelInstanceId = _panelInstanceId,
                    BindingEpoch = _bindingEpoch,
                    SessionGeneration = _sessionGeneration,
                    WebCallId = requestCallId,
                    Command = DetachRecoveryCommand,
                    FlashAction = DetachRecoveryAction,
                    PostToWeb = false,
                    IsWrite = false,
                    WriteEpoch = _writeEpoch,
                    ExpectedLoadoutRevision = _loadoutRevision,
                    ExpectedLiveRevision = _liveRevision,
                    ExpectedDrugRevision = _drugRevision,
                    IsDetachRecovery = true,
                    RecoveryEpoch = recoveryEpoch,
                    TransportGeneration = transportGeneration
                };

                if (!_pendingCalls.TryBegin(
                    requestCallId, entry, out backendCallId))
                {
                    return false;
                }
                entry.BackendCallId = backendCallId;
                _productionPending[backendCallId] = entry;
                _detachRecoveryInFlight = true;
                _detachRecoveryBackendCallId = backendCallId;
                _detachRecoveryTransportGeneration =
                    transportGeneration;
                _detachRecoveryStatus = "in_flight";
                _detachRecoveryFailure = null;
            }

            string wirePayload = BuildDetachRecoveryWirePayload(entry);
            bool sent = false;
            try
            {
                sent = SafeReadyGeneration() == transportGeneration
                    && _trySendIfGeneration(
                        wirePayload, transportGeneration);
            }
            catch (Exception ex)
            {
                LogManager.Log(
                    "[CharacterBuildTask] detach recovery send threw "
                    + ex.GetType().Name);
            }

            if (!sent)
            {
                PanelPendingCall<PendingRequest> pending;
                if (_pendingCalls.TryComplete(
                    backendCallId, out pending))
                {
                    HandleDetachRecoveryPendingEnded(
                        pending.Context,
                        PanelPendingCallEndReason.DeliveryUnknown);
                }
                return false;
            }

            LogManager.Log("[CharacterBuildTask] -> Flash host-only recovery epoch="
                + recoveryEpoch + " generation=" + transportGeneration
                + " callId=" + backendCallId);
            return true;
        }

        private static string BuildDetachRecoveryWirePayload(
            PendingRequest entry)
        {
            var parameters = new JObject
            {
                ["v"] = 1,
                ["panelInstanceId"] = entry.PanelInstanceId,
                ["requestCallId"] = entry.WebCallId,
                ["writeEpoch"] = entry.WriteEpoch
            };
            if (entry.SessionGeneration.HasValue)
                parameters["knownGeneration"] =
                    entry.SessionGeneration.Value;
            JObject flash = PanelBridge.BuildFlashCommand(
                DetachRecoveryAction,
                entry.BackendCallId,
                parameters);
            return flash.ToString(Formatting.None) + "\0";
        }

        private void HandleDetachRecoveryResponse(
            JObject message,
            PendingRequest entry)
        {
            // Socket dispatch holds XmlSocketServer's connection-transition fence while invoking
            // this handler, so the current ready generation is also the actual inbound origin.
            // Web-origin task ingress rejects every *_response before MessageRouter dispatch.
            if (entry == null
                || SafeReadyGeneration() != entry.TransportGeneration)
            {
                LogManager.Log(
                    "[CharacterBuildTask] ignored detach recovery response from stale generation");
                return;
            }

            bool terminal;
            bool success;
            string failureCode;
            bool valid = TryValidateDetachRecoveryResponse(
                message,
                entry,
                out terminal,
                out success,
                out failureCode);

            PanelPendingCall<PendingRequest> pending;
            if (!_pendingCalls.TryComplete(
                entry.BackendCallId, out pending))
            {
                return;
            }

            bool forceCapturedTransport = false;
            bool notifyBlocked = false;
            bool notifySettled = false;
            lock (_bindingGate)
            {
                lock (_gate)
                {
                    _productionPending.Remove(
                        entry.BackendCallId);
                    if (!DetachRecoveryContextMatchesLocked(entry))
                        return;

                    _detachRecoveryInFlight = false;
                    _detachRecoveryBackendCallId = 0;
                    if (!valid)
                    {
                        forceCapturedTransport =
                            TryReserveAutomaticDetachRecoveryRetireLocked();
                        _detachRecoveryStatus = forceCapturedTransport
                            ? "awaiting_reconnect"
                            : "fatal_blocked";
                        _detachRecoveryFailure = "malformed_response";
                        notifyBlocked = !forceCapturedTransport;
                    }
                    else if (terminal && success)
                    {
                        // The AS2 proof includes persistence, clean revision equality, closed
                        // session, and exact pause release. Only now may Host consume the binding.
                        _bindingChanging = true;
                        _bindingEpoch++;
                        _panelInstanceId = null;
                        ResetSessionLocked();
                        _bindingChanging = false;
                        notifySettled = true;
                    }
                    else
                    {
                        forceCapturedTransport =
                            TryReserveAutomaticDetachRecoveryRetireLocked();
                        _detachRecoveryStatus = forceCapturedTransport
                            ? "awaiting_reconnect"
                            : "fatal_blocked";
                        _detachRecoveryFailure =
                            failureCode ?? "unknown";
                        notifyBlocked = !forceCapturedTransport;
                    }
                    System.Threading.Monitor.PulseAll(
                        _gate);
                }
            }

            if (forceCapturedTransport)
            {
                LogManager.Log(
                    "[CharacterBuildTask] detach recovery did not settle; "
                    + "closing captured generation="
                    + entry.TransportGeneration + " error="
                    + (_detachRecoveryFailure ?? "unknown"));
                ForceCloseCapturedGeneration(
                    entry.TransportGeneration);
            }
            else if (!success)
            {
                LogManager.Log(
                    "[CharacterBuildTask] detach recovery fatal-blocked error="
                    + (failureCode ?? "unknown")
                    + " generation=" + entry.TransportGeneration);
            }
            if (notifyBlocked)
                NotifyDetachRecoveryBlocked();

            if (notifySettled)
            {
                LogManager.Log(
                    "[CharacterBuildTask] detach recovery proof consumed binding epoch="
                    + entry.RecoveryEpoch);
                NotifyCoordinatorSettledIfReady();
            }
        }

        private static bool TryValidateDetachRecoveryResponse(
            JObject message,
            PendingRequest entry,
            out bool terminal,
            out bool success,
            out string failureCode)
        {
            terminal = false;
            success = false;
            failureCode = null;
            if (message == null || entry == null
                || ReadString(message["task"]) !=
                    "loadout_response"
                || ReadString(message["command"]) !=
                    DetachRecoveryCommand
                || ReadString(message["requestCallId"]) !=
                    entry.WebCallId
                || ReadString(message["panelInstanceId"]) !=
                    entry.PanelInstanceId
                || !HasVersion(message)
                || message["success"] == null
                || message["success"].Type != JTokenType.Boolean
                || message["active"] == null
                || message["active"].Type != JTokenType.Boolean
                || message["liveRefreshDirty"] == null
                || message["liveRefreshDirty"].Type
                    != JTokenType.Boolean
                || message["closed"] == null
                || message["closed"].Type != JTokenType.Boolean
                || message["pauseReleased"] == null
                || message["pauseReleased"].Type
                    != JTokenType.Boolean)
            {
                return false;
            }

            int backendCallId;
            int writeEpoch;
            long sessionGeneration;
            long loadoutRevision;
            long liveRevision;
            long drugRevision;
            if (!TryReadInteger(
                    message["callId"],
                    1,
                    int.MaxValue,
                    out backendCallId)
                || backendCallId != entry.BackendCallId
                || !TryReadInteger(
                    message["writeEpoch"],
                    0,
                    int.MaxValue,
                    out writeEpoch)
                || writeEpoch != entry.WriteEpoch
                || !TryReadInteger(
                    message["sessionGeneration"],
                    0,
                    int.MaxValue,
                    out sessionGeneration)
                || !TryReadInteger(
                    message["loadoutRevision"],
                    0,
                    int.MaxValue,
                    out loadoutRevision)
                || !TryReadInteger(
                    message["liveRevision"],
                    0,
                    int.MaxValue,
                    out liveRevision)
                || !TryReadInteger(
                    message["drugRevision"],
                    0,
                    int.MaxValue,
                    out drugRevision)
                || !IsSnapshotShapeValid(
                    loadoutRevision,
                    liveRevision,
                    drugRevision,
                    message.Value<bool>("liveRefreshDirty")))
            {
                return false;
            }

            JObject persistence =
                message["persistence"] as JObject;
            if (!IsPersistenceProof(persistence))
                return false;

            success = message.Value<bool>("success");
            var allowed = Set(
                "task", "callId", "v", "success", "command",
                "requestCallId", "panelInstanceId", "writeEpoch",
                "active", "sessionGeneration", "loadoutRevision",
                "liveRevision", "liveRefreshDirty", "drugRevision",
                "recoveryState", "closed", "pauseReleased",
                "persistence");
            if (!success) allowed.Add("error");
            if (!IsExactObject(message, allowed))
                return false;

            string recoveryState =
                ReadString(message["recoveryState"]);
            bool active = message.Value<bool>("active");
            bool closed = message.Value<bool>("closed");
            bool pauseReleased =
                message.Value<bool>("pauseReleased");
            bool persistenceSucceeded =
                persistence.Value<bool>("success");

            if (!success)
            {
                failureCode = ReadString(message["error"]);
                return recoveryState == "unsettled"
                    && !closed
                    && !pauseReleased
                    && !persistenceSucceeded
                    && IsKnownDetachRecoveryFailure(
                        failureCode);
            }

            if (active || !closed || !pauseReleased
                || !persistenceSucceeded
                || message.Value<bool>("liveRefreshDirty")
                || loadoutRevision != liveRevision)
            {
                return false;
            }

            if (recoveryState == "authority_absent")
            {
                if (entry.SessionGeneration.HasValue
                    || sessionGeneration != 0
                    || loadoutRevision != 0
                    || liveRevision != 0
                    || drugRevision != 0
                    || persistence.Value<bool>("changed"))
                {
                    return false;
                }
                terminal = true;
                return true;
            }

            if (recoveryState != "settled"
                || sessionGeneration <= 0)
            {
                return false;
            }
            if (entry.SessionGeneration.HasValue
                && sessionGeneration
                    != entry.SessionGeneration.Value)
            {
                return false;
            }
            if (loadoutRevision
                    < entry.ExpectedLoadoutRevision
                || liveRevision
                    < entry.ExpectedLiveRevision
                || drugRevision
                    < entry.ExpectedDrugRevision)
            {
                return false;
            }

            terminal = true;
            return true;
        }

        private static bool IsKnownDetachRecoveryFailure(
            string failureCode)
        {
            switch (failureCode)
            {
                case "flush_failed":
                case "needs_reconcile":
                case "pause_release_failed":
                case "stale_pause_lease":
                case "stale_session":
                case "stale_panel_instance":
                case "session_not_active":
                case "invalid_payload":
                case "service_not_ready":
                case "invalid_drug_revision":
                case "invalid_loadout":
                case "stale_container":
                case "stale_drug_revision":
                case "live_unavailable":
                case "finalize_failed":
                case "authority_conflict":
                case "internal_error":
                    return true;
                default:
                    return false;
            }
        }

        private void HandleDetachRecoveryPendingEnded(
            PendingRequest entry,
            PanelPendingCallEndReason reason)
        {
            if (entry == null) return;
            bool forceCapturedTransport = false;
            bool notifyBlocked = false;
            lock (_gate)
            {
                _productionPending.Remove(
                    entry.BackendCallId);
                if (_disposed
                    || !DetachRecoveryContextMatchesLocked(entry))
                {
                    return;
                }
                _detachRecoveryInFlight = false;
                _detachRecoveryBackendCallId = 0;
                bool transportUnknown =
                    reason == PanelPendingCallEndReason.Timeout
                    || reason
                        == PanelPendingCallEndReason.DeliveryUnknown;
                forceCapturedTransport = transportUnknown
                    && TryReserveAutomaticDetachRecoveryRetireLocked();
                _detachRecoveryStatus = forceCapturedTransport
                    ? "awaiting_reconnect"
                    : "fatal_blocked";
                _detachRecoveryFailure = reason.ToString();
                notifyBlocked = !forceCapturedTransport;
                System.Threading.Monitor.PulseAll(
                    _gate);
            }

            if (forceCapturedTransport)
            {
                LogManager.Log(
                    "[CharacterBuildTask] detach recovery transport ended reason="
                    + reason + " generation="
                    + entry.TransportGeneration);
                ForceCloseCapturedGeneration(
                    entry.TransportGeneration);
            }
            if (notifyBlocked)
                NotifyDetachRecoveryBlocked();
        }

        private bool DetachRecoveryContextMatchesLocked(
            PendingRequest entry)
        {
            return entry != null
                && entry.IsDetachRecovery
                && !_disposed
                && _detachRecoveryRequired
                && entry.RecoveryEpoch
                    == _detachRecoveryEpoch
                && entry.BindingEpoch == _bindingEpoch
                && entry.BackendCallId
                    == _detachRecoveryBackendCallId
                && entry.TransportGeneration
                    == _detachRecoveryTransportGeneration
                && string.Equals(
                    entry.PanelInstanceId,
                    _panelInstanceId,
                    StringComparison.Ordinal);
        }

        private void ForceCloseCapturedGeneration(
            int transportGeneration)
        {
            if (transportGeneration <= 0) return;
            try
            {
                _forceCloseIfGeneration(
                    transportGeneration);
            }
            catch (Exception ex)
            {
                LogManager.Log(
                    "[CharacterBuildTask] force-close recovery generation threw "
                    + ex.GetType().Name);
            }
        }

        private bool TryReserveAutomaticDetachRecoveryRetireLocked()
        {
            if (_detachRecoveryAutomaticRetires
                >= MaxAutomaticDetachRecoveryRetires)
            {
                return false;
            }
            _detachRecoveryAutomaticRetires++;
            return true;
        }

        private void NotifyDetachRecoveryBlocked()
        {
            Action<string, string> callback;
            string status;
            string failure;
            lock (_gate)
            {
                if (_disposed || !_detachRecoveryRequired
                    || _detachRecoveryStatus != "fatal_blocked"
                    || _detachRecoveryBlockedNotificationGeneration
                        == _detachRecoveryTransportGeneration)
                {
                    return;
                }
                _detachRecoveryBlockedNotificationGeneration =
                    _detachRecoveryTransportGeneration;
                callback = _onDetachRecoveryBlocked;
                status = _detachRecoveryStatus;
                failure = _detachRecoveryFailure ?? "unknown";
            }
            if (callback == null) return;
            try
            {
                Action invoke = delegate
                {
                    try { callback(status, failure); } catch { }
                };
                if (_invokeOnUI != null) _invokeOnUI(invoke);
                else invoke();
            }
            catch { }
        }

        private int SafeReadyGeneration()
        {
            try
            {
                return _getReadyGeneration == null
                    ? 0 : _getReadyGeneration();
            }
            catch
            {
                return 0;
            }
        }

        private void ResetDetachRecoveryLocked()
        {
            _detachRecoveryRequired = false;
            _detachRecoveryInFlight = false;
            _detachRecoveryAwaitingVisualRetire = false;
            _detachRecoveryBackendCallId = 0;
            _detachRecoveryTransportGeneration = 0;
            _detachRecoveryClosedGeneration = 0;
            _detachRecoveryReason = null;
            _detachRecoveryStatus = "idle";
            _detachRecoveryFailure = null;
            _detachRecoveryAutomaticRetires = 0;
            _detachRecoveryBlockedNotificationGeneration = 0;
        }
    }
}
