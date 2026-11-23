using System;
using System.Diagnostics;
using System.Threading;
using CF7Launcher.Tasks;
using CF7Launcher.Save;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Guardian
{
    public sealed partial class CharacterBuildTask
    {
        private sealed class ExitOperation
        {
            public string Id, Panel, Slot, Role, Context;
            public SettingsSaveContext PhysicalContext;
            public int Sequence, Binding, Transport, Epoch, Call;
            public long Session, Loadout, Live, Drug;
            public bool PersistSent, Consumed;
            public JObject Reply;
        }

        private Func<Func<bool>, bool> _closeWithExitReceipt;
        private Func<bool> _exitOwnersSettled;
        private Func<SettingsSaveContext> _physicalExitContext;
        private SettingsSaveContext _originalExitContext;
        private ExitOperation _exitOperation;
        private int _exitSequence, _exitCall, _exitFailureTransport;

        internal void SetPersistedExit(Func<Func<bool>, bool> close, Func<bool> ownersSettled, Func<SettingsSaveContext> context)
        {
            _closeWithExitReceipt = close;
            _exitOwnersSettled = ownersSettled;
            _physicalExitContext = context;
        }

        private void RequestPersistedExit(JObject request, string panel, string callId)
        {
            var payload = request["payload"] as JObject;
            if (!IsExactObject(payload, Set("v", "sessionGeneration", "loadoutRevision", "drugRevision"))
                || !TryReadInteger(payload["v"], 1, 1, out int version)
                || !TryReadInteger(payload["sessionGeneration"], 1L, int.MaxValue, out long session)
                || !TryReadInteger(payload["loadoutRevision"], 0L, int.MaxValue, out long loadout)
                || !TryReadInteger(payload["drugRevision"], 0L, int.MaxValue, out long drug))
            {
                RejectAndRemember(callId, "persistAndExit", "invalid_payload");
                return;
            }
            if (!_pendingCalls.TryRememberRejected(callId)) return;
            string error = "exit_blocked";
            if (_closeWithExitReceipt != null && _isCurrentRetryPanel != null && _isCurrentRetryPanel(panel)
                && _closeWithExitReceipt(() => TryConsumePersistedExit(panel, session, loadout, drug, 5000, out error)))
                return;
            RespondError(callId, "persistAndExit", error, false, null);
        }

        private bool ExitBindingCurrent(ExitOperation op)
        {
            return !_disposed && !_bindingChanging && !_detachRecoveryRequired && _pendingCount == 0
                && !_initialSnapshotOutcomeUnknown && _unknownKind == UnknownKind.None
                && _panelInstanceId == op.Panel && _bindingEpoch == op.Binding && _sessionGeneration == op.Session
                && _writeEpoch == op.Epoch && _loadoutRevision == op.Loadout && _drugRevision == op.Drug
                && _liveRevision == op.Live && _liveRefreshDirty && _exitFailureTransport == op.Transport;
        }

        internal bool TryConsumePersistedExit(string panel, long session, long loadout, long drug,
            int timeoutMs, out string error)
        {
            error = "exit_blocked";
            if (_exitOwnersSettled == null || !_exitOwnersSettled() || _physicalExitContext == null) return false;
            var physical = _physicalExitContext();
            string slot = physical?.Slot;
            int transport = SafeReadyGeneration();
            if (physical == null || transport <= 0) return false;
            ExitOperation op;
            bool isNew;
            lock (_gate)
            {
                isNew = _exitOperation == null;
                if (physical != _originalExitContext || (isNew && _writeState != "flush_failed")) return false;
                op = _exitOperation ?? new ExitOperation {
                    Id = Guid.NewGuid().ToString("N"), Sequence = ++_exitSequence, Panel = panel, Slot = slot, PhysicalContext = physical,
                    Session = session, Loadout = loadout, Drug = drug, Live = _liveRevision,
                    Binding = _bindingEpoch, Transport = transport, Epoch = _writeEpoch
                };
                if (op.Consumed || panel != op.Panel || session != op.Session || loadout != op.Loadout
                    || drug != op.Drug || physical != op.PhysicalContext || transport != op.Transport || !ExitBindingCurrent(op))
                    return false;
                _exitOperation = op;
                _writeState = "exit_pending";
            }

            // A delivery timeout always queries the original operation. Only a prepared
            // operation for which Host has never sent persist may dispatch a physical write.
            string phase = isNew ? "prepare" : "query";
            for (int leg = 0; leg < 2; leg++)
            {
                JObject response = ExchangeExit(op, phase, timeoutMs);
                if (response == null) { error = "exit_query_required"; return false; }
                if (!_exitOwnersSettled() || _physicalExitContext() != op.PhysicalContext || SafeReadyGeneration() != op.Transport)
                    return false;
                lock (_gate)
                {
                    if (_exitOperation != op || !ExitBindingCurrent(op) || op.Consumed) return false;
                    string state = ReadString(response["state"]);
                    if (state == "blocked")
                    {
                        _exitOperation = null;
                        _writeState = "flush_failed";
                        error = "exit_not_settled";
                        return false;
                    }
                    if (state == "prepared" && !op.PersistSent)
                    {
                        op.Role = ReadString(response["role"]);
                        op.Context = ReadString(response["context"]);
                        if (string.IsNullOrWhiteSpace(op.Role) || string.IsNullOrWhiteSpace(op.Context)) return false;
                        phase = "persist";
                        continue;
                    }
                    if (state == "terminate" && op.PersistSent && ReadString(response["role"]) == op.Role
                        && ReadString(response["context"]) == op.Context
                        && TryReadInteger(response["saveSerial"], 1, int.MaxValue, out int serial))
                    {
                        op.Consumed = true;
                        LogManager.Log("event=character_build_exit_consumed operation=" + op.Id + " saveSerial=" + serial);
                        return true;
                    }
                    error = "exit_query_required";
                    return false;
                }
            }
            return false;
        }

        private JObject ExchangeExit(ExitOperation op, string phase, int timeoutMs)
        {
            int call;
            lock (_gate)
            {
                if (_exitOperation != op || !ExitBindingCurrent(op) || op.Consumed) return null;
                call = op.Call = ++_exitCall;
                op.Reply = null;
                if (phase == "persist")
                {
                    if (op.PersistSent) return null;
                    op.PersistSent = true;
                }
            }
            var args = new JObject {
                ["v"] = 1, ["phase"] = phase, ["operationId"] = op.Id, ["sequence"] = op.Sequence,
                ["panelInstanceId"] = op.Panel, ["sessionGeneration"] = op.Session, ["writeEpoch"] = op.Epoch,
                ["transportGeneration"] = op.Transport, ["loadoutRevision"] = op.Loadout, ["liveRevision"] = op.Live,
                ["drugRevision"] = op.Drug, ["slot"] = op.Slot, ["role"] = op.Role ?? "", ["context"] = op.Context ?? ""
            };
            string wire = PanelBridge.BuildFlashCommand("characterBuildPersistedExit", call, args).ToString(Formatting.None) + "\0";
            var elapsed = Stopwatch.StartNew();
            try { if (!_trySendIfGeneration(wire, op.Transport)) return null; }
            catch (Exception error)
            {
                LogManager.Log("event=character_build_exit_transport_failed type=" + error.GetType().Name);
                return null;
            }
            lock (_gate)
            {
                while (_exitOperation == op && op.Call == call && op.Reply == null && !_disposed)
                {
                    int remaining = timeoutMs - (int)elapsed.ElapsedMilliseconds;
                    if (remaining <= 0) return null;
                    Monitor.Wait(_gate, remaining);
                }
                return _exitOperation == op && op.Call == call ? op.Reply : null;
            }
        }

        internal void HandlePersistedExitResponse(JObject m, Action<string> respond)
        {
            lock (_gate)
            {
                var op = _exitOperation;
                if (op != null && !op.Consumed && op.Reply == null && m != null
                    && IsExactObject(m, Set("task", "v", "callId", "operationId", "sequence", "panelInstanceId",
                        "sessionGeneration", "transportGeneration", "writeEpoch", "loadoutRevision", "liveRevision",
                        "drugRevision", "slot", "role", "context", "state", "saveSerial"))
                    && ReadString(m["task"]) == "loadout_exit_response" && ReadString(m["operationId"]) == op.Id
                    && ReadString(m["panelInstanceId"]) == op.Panel && ReadString(m["slot"]) == op.Slot
                    && ExitNumber(m, "v", 1) && ExitNumber(m, "callId", op.Call) && ExitNumber(m, "sequence", op.Sequence)
                    && ExitNumber(m, "sessionGeneration", op.Session) && ExitNumber(m, "writeEpoch", op.Epoch)
                    && ExitNumber(m, "transportGeneration", op.Transport) && ExitNumber(m, "loadoutRevision", op.Loadout)
                    && ExitNumber(m, "liveRevision", op.Live) && ExitNumber(m, "drugRevision", op.Drug)
                    && (!op.PersistSent || (ReadString(m["role"]) == op.Role && ReadString(m["context"]) == op.Context))
                    && ExitBindingCurrent(op))
                {
                    op.Reply = (JObject)m.DeepClone();
                    Monitor.PulseAll(_gate);
                }
            }
            respond?.Invoke(null);
        }

        private static bool ExitNumber(JObject response, string key, long expected) =>
            TryReadInteger(response[key], expected, expected, out long value);
    }
}
