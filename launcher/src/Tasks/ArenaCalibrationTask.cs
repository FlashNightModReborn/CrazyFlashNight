using System;
using System.Collections.Generic;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using CF7Launcher.Bus;
using CF7Launcher.Data;
using CF7Launcher.Guardian;
using CF7Launcher.ArenaWorker;

namespace CF7Launcher.Tasks
{
    public sealed class ArenaCalibrationTask
    {
        private const int DefaultSpawnDistance = 650;
        private const string DefaultFormation = "line";
        private const int DefaultFormationSpacing = 54;
        private static readonly HashSet<string> AllowedFormations = new HashSet<string>(StringComparer.Ordinal)
        {
            "column",
            "line",
            "wedge",
            "shield",
            "grid"
        };
        private static readonly HashSet<string> AllowedStrategicPetPromotions =
            new HashSet<string>(StringComparer.Ordinal)
            {
                "基础训练",
                "强化药剂",
                "超级血清"
            };

        private sealed class CalibrationCase
        {
            public string CaseId;
            public string CaseHash;
            public JArray BlueRoster;
            public JArray RedRoster;
            public int Repeat;
            public int TimeoutFrames;
            public int SpawnDistance;
            public string BlueFormation;
            public string RedFormation;
            public int FormationSpacing;
            public JObject AuthorityContext;
        }

        private sealed class BatchManifest
        {
            public string BatchId;
            public string ManifestHash;
            public JObject Frozen;
            public List<CalibrationCase> Cases;
            public int TotalRuns;
        }

        private sealed class PendingRun
        {
            public ManualResetEventSlim Done;
            public JObject Response;
            public CalibrationCase TestCase;
            public int RepeatIndex;
            public string RunId;
            public DateTime StartedAtUtc;
            public bool Aborted;
            public JObject Identity;
            public string TransportError;
            public int SocketGeneration;
        }

        private readonly string _projectRoot;
        private readonly Func<bool> _isClientReady;
        private readonly Action<string> _send;
        private readonly Func<int, int> _timeoutMsFromFrames;
        private readonly object _lock = new object();
        private readonly Dictionary<int, PendingRun> _pending = new Dictionary<int, PendingRun>();
        private static readonly Regex BatchIdPattern = new Regex("^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$", RegexOptions.Compiled);
        private static readonly Regex SourceIdPattern = new Regex("^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$", RegexOptions.Compiled);
        private Action<JObject> _batchCompleted;
        private readonly string _workerId;
        private string _sessionEpoch;
        private readonly bool _allowOwnedFlashRebind;
        private readonly bool _allowFaultInjection;
        private readonly Func<DateTime> _faultUtcNow;
        private JObject _faultReceipt;
        private XmlSocketPeerProcessIdentity _observedOwnedFlash;
        private XmlSocketPeerProcessIdentity _batchOwnedFlash;
        private string _assignmentId;
        private string _attemptId;
        private bool _transportPoisoned;
        private Func<int> _readyGeneration;
        private Func<int, string, bool> _sendForGeneration;
        private Action<int> _retireGeneration;
        public event Action<string> TransportPoisoned;

        private int _seq;
        private volatile bool _abortRequested;
        private string _state = "idle";
        private string _batchId;
        private string _manifestHash;
        private string _manifestPath;
        private string _frozenManifestPath;
        private string _resultPath;
        private string _currentCaseId;
        private string _currentRunId;
        private string _lastError;
        private JObject _lastResultRow;
        private int _totalRuns;
        private int _completedRuns;

        public ArenaCalibrationTask(XmlSocketServer socket, string projectRoot,
            string workerId = "guardian", string sessionEpoch = null, bool allowOwnedFlashRebind = true,
            bool allowFaultInjection = false)
            : this(
                projectRoot,
                delegate { return socket != null && socket.IsClientReady; },
                delegate(string payload) { if (socket != null) socket.Send(payload); },
                null, workerId, sessionEpoch, allowOwnedFlashRebind, allowFaultInjection)
        {
            _readyGeneration = delegate { return socket != null && socket.TryGetReadyGeneration(out int gen) ? gen : 0; };
            _sendForGeneration = delegate(int gen, string payload) { return socket != null && socket.TrySendIfGen(payload, gen); };
            _retireGeneration = delegate(int gen) { if (socket != null) socket.ForceCloseCurrentClientIfGen(gen); };
            if (socket != null) socket.OnClientDisconnectedForGeneration += HandleTransportDisconnected;
        }

        public ArenaCalibrationTask(
            string projectRoot,
            Func<bool> isClientReady,
            Action<string> send,
            Func<int, int> timeoutMsFromFrames,
            string workerId = "guardian", string sessionEpoch = null, bool allowOwnedFlashRebind = true,
            bool allowFaultInjection = false, Func<DateTime> faultUtcNow = null)
        {
            _projectRoot = string.IsNullOrEmpty(projectRoot)
                ? AppDomain.CurrentDomain.BaseDirectory
                : Path.GetFullPath(projectRoot);
            _isClientReady = isClientReady ?? delegate { return false; };
            _send = send ?? delegate { };
            _timeoutMsFromFrames = timeoutMsFromFrames ?? DefaultTransportTimeoutMsFromFrames;
            _workerId = ArenaRunIdentity.ReadId(new JObject { ["workerId"] = workerId }, "workerId");
            _sessionEpoch = ArenaRunIdentity.ReadId(new JObject { ["sessionEpoch"] = sessionEpoch ?? Guid.NewGuid().ToString("N") }, "sessionEpoch");
            _allowOwnedFlashRebind = allowOwnedFlashRebind;
            _allowFaultInjection = allowFaultInjection;
            _faultUtcNow = faultUtcNow ?? (() => DateTime.UtcNow);
            _readyGeneration = delegate { return _isClientReady() ? 1 : 0; };
            _sendForGeneration = delegate(int gen, string payload) { _send(payload); return true; };
        }

        public void SetBatchCompletedHandler(Action<JObject> handler)
        {
            _batchCompleted = handler;
        }

        // Supplied only by Program's existing successful exact-process authority
        // binding. Socket generations alone never provide recovery authority.
        internal void ObserveOwnedFlashIdentity(XmlSocketPeerProcessIdentity identity)
        {
            lock (_lock) _observedOwnedFlash = identity;
        }

        internal XmlSocketPeerProcessIdentity CaptureFaultProcessIdentity()
        {
            lock (_lock) return _allowFaultInjection ? _batchOwnedFlash : null;
        }

        internal JObject FaultStopFlash(JObject request, IArenaWorkerFaultProcess process)
        {
            string faultId = ArenaRunIdentity.ReadId(request, "faultId");
            bool killIssued = false;
            JObject receipt;
            lock (_lock)
            {
                if (!_allowFaultInjection) return BuildError("worker_fault_not_enabled", "Fault injection was not enabled for this launch.");
                if (_faultReceipt != null) return BuildError("fault_already_claimed", "This Worker has already consumed its fault ticket.");
                if (_state != "running" || _abortRequested || _transportPoisoned || _pending.Count != 1)
                    return BuildError("fault_run_not_pending", "There is no single authoritative outstanding run.");
                PendingRun pending = null;
                foreach (PendingRun value in _pending.Values) pending = value;
                if (pending.Done.IsSet || pending.Response != null || pending.TransportError != null || pending.Aborted
                    || !ArenaRunIdentity.Matches(pending.Identity, request))
                    return BuildError("fault_context_mismatch", "The preselected run is no longer the exact outstanding run.");
                if (pending.SocketGeneration <= 0 || pending.SocketGeneration != _readyGeneration())
                    return BuildError("fault_generation_mismatch", "The outstanding run no longer owns the ready transport generation.");
                if (process == null || !SameFaultProcess(_batchOwnedFlash, process.Identity)
                    || !SameFaultProcess(_observedOwnedFlash, process.Identity))
                    return BuildError("fault_process_mismatch", "The held process does not own this outstanding run.");
                try
                {
                    if (!process.IsAlive) return BuildError("fault_process_exited", "The held process has already exited.");
                }
                catch (Exception ex)
                {
                    return BuildError("fault_process_unavailable", ex.GetType().Name);
                }

                receipt = ArenaRunIdentity.Capture(pending.Identity);
                receipt["schema"] = "arena-worker.fault-receipt.v1";
                receipt["faultId"] = faultId;
                receipt["flashProcess"] = new JObject {
                    ["pid"] = process.Identity.ProcessId,
                    ["processStartUtcTicks"] = process.Identity.StartTimeUtc.UtcTicks.ToString(System.Globalization.CultureInfo.InvariantCulture),
                    ["processPath"] = process.Identity.ExecutablePath
                };
                receipt["socketGeneration"] = pending.SocketGeneration;
                // Store dates as dates so the first reply and later status parsing use
                // the same Json.NET wire representation, including fractional zeros.
                receipt["claimedAtUtc"] = _faultUtcNow();
                receipt["killAttempted"] = true;
                receipt["killIssued"] = JValue.CreateNull();
                receipt["processExitObserved"] = false;
                receipt["outcome"] = "claimed";
                _faultReceipt = receipt; // Every exception after this point consumes the one-shot ticket.
                receipt["killIssuedAtUtc"] = _faultUtcNow();
                try
                {
                    // Do not wait, dispatch UI, retire a socket or manufacture a result under this lock.
                    // Response completion and the next run cannot pass the same authority lock during Kill.
                    process.Kill();
                    killIssued = true;
                    receipt["killIssued"] = true;
                    receipt["killReturnedAtUtc"] = _faultUtcNow();
                    receipt["outcome"] = "kill_issued";
                }
                catch (Exception ex)
                {
                    receipt["outcome"] = "unknown";
                    receipt["error"] = ex.GetType().Name;
                }
            }

            bool exited = false;
            string observationError = null;
            if (killIssued)
            {
                try { exited = process.WaitForExit(5000); }
                catch (Exception ex) { observationError = ex.GetType().Name; }
            }
            lock (_lock)
            {
                if (killIssued && exited && observationError == null)
                {
                    receipt["processExitObserved"] = true;
                    receipt["exitObservedAtUtc"] = _faultUtcNow();
                    receipt["outcome"] = "killed";
                }
                else
                {
                    receipt["outcome"] = "unknown";
                    if (observationError != null) receipt["error"] = observationError;
                    else if (killIssued) receipt["error"] = "exit_observation_timeout";
                }
                LogManager.Log("event=arena_worker_fault worker=" + _workerId + " fault=" + faultId
                    + " run=" + receipt.Value<string>("runId") + " outcome=" + receipt.Value<string>("outcome"));
                return receipt.Value<string>("outcome") == "killed"
                    ? BuildStatus(true, "fault_killed")
                    : BuildError("fault_outcome_unknown", "The one-shot fault outcome is unknown; inspect this receipt and do not replay it.");
            }
        }

        private static bool SameFaultProcess(XmlSocketPeerProcessIdentity left, XmlSocketPeerProcessIdentity right)
            => left != null && right != null && left.ProcessId == right.ProcessId
                && left.StartTimeUtc.UtcTicks == right.StartTimeUtc.UtcTicks
                && string.Equals(left.ExecutablePath, right.ExecutablePath, StringComparison.OrdinalIgnoreCase);

        private bool CanRebindAfterTransportLoss()
        {
            return _allowOwnedFlashRebind && _pending.Count == 0
                && _batchOwnedFlash != null && _observedOwnedFlash != null
                && (_batchOwnedFlash.ProcessId != _observedOwnedFlash.ProcessId
                    || _batchOwnedFlash.StartTimeUtc.UtcTicks != _observedOwnedFlash.StartTimeUtc.UtcTicks
                    || !string.Equals(_batchOwnedFlash.ExecutablePath, _observedOwnedFlash.ExecutablePath,
                        StringComparison.OrdinalIgnoreCase));
        }

        public string HandleControl(JObject msg)
        {
            string action = msg.Value<string>("action") ?? "status";
            try
            {
                switch (action)
                {
                    case "startBatch":
                        return StartBatch(msg).ToString(Formatting.None);
                    case "startSingle":
                        return StartSingle(msg).ToString(Formatting.None);
                    case "status":
                        return BuildStatus(true, null).ToString(Formatting.None);
                    case "abort":
                        return AbortBatch(msg).ToString(Formatting.None);
                    default:
                        return BuildError("unsupported_action", "unsupported action: " + action).ToString(Formatting.None);
                }
            }
            catch (Exception ex)
            {
                LogManager.Log("[ArenaCalibrationTask] control exception: " + ex);
                return BuildError("exception", ex.Message).ToString(Formatting.None);
            }
        }

        public void HandleFlashResponse(JObject msg, Action<string> respond)
        {
            int fid = msg.Value<int?>("callId") ?? 0;
            PendingRun pending = null;
            lock (_lock)
            {
                if (_pending.TryGetValue(fid, out pending))
                {
                    JObject result = msg["result"] as JObject ?? msg;
                    if (!ArenaRunIdentity.Matches(pending.Identity, result)
                        || _readyGeneration() != pending.SocketGeneration)
                    {
                        LogManager.Log("[ArenaCalibrationTask] rejected non-matching run response callId=" + fid);
                        pending = null;
                    }
                    else
                    {
                        _pending.Remove(fid);
                        pending.Response = (JObject)msg.DeepClone();
                        pending.Done.Set();
                    }
                }
            }

            respond(null);
        }

        private JObject StartBatch(JObject msg)
        {
            if (!_isClientReady())
                return BuildError("disconnected", "Flash socket client is not ready");

            string manifestPath = ResolveManifestPath(msg.Value<string>("manifestPath"));
            BatchManifest manifest = LoadAndNormalizeManifest(manifestPath);
            if (msg["batchId"] != null && msg.Value<string>("batchId") != manifest.BatchId)
                return BuildError("batch_mismatch", "requested batchId does not match manifest");
            if (msg["manifestHash"] != null && msg.Value<string>("manifestHash") != manifest.ManifestHash)
                return BuildError("manifest_mismatch", "requested manifestHash does not match manifest");
            Action startWorker;
            JObject result = StartNormalizedBatch(manifest, manifestPath, msg, null, null, out startWorker);
            if (startWorker != null)
                startWorker();
            return result;
        }

        public JObject StartSingle(JObject msg)
        {
            Action startWorker;
            JObject result = StartSingleDeferred(msg, null, out startWorker);
            if (startWorker != null)
                startWorker();
            return result;
        }

        public JObject StartSingleDeferred(JObject msg, Action<JObject> beforeWorkerStart, out Action startWorker)
        {
            return StartSingleDeferred(msg, beforeWorkerStart, null, out startWorker);
        }

        public JObject StartSingleDeferred(
            JObject msg,
            Action<JObject> beforeWorkerStart,
            Action<JObject> batchCompleted,
            out Action startWorker)
        {
            try
            {
                startWorker = null;
                if (!_isClientReady())
                    return BuildError("disconnected", "Flash socket client is not ready");

                BatchManifest manifest = BuildInlineSingleManifest(msg);
                return StartNormalizedBatch(
                    manifest,
                    null,
                    msg,
                    beforeWorkerStart,
                    batchCompleted,
                    out startWorker);
            }
            catch (Exception ex)
            {
                startWorker = null;
                LogManager.Log("[ArenaCalibrationTask] startSingle exception: " + ex);
                return BuildError("exception", ex.Message);
            }
        }

        private JObject StartNormalizedBatch(
            BatchManifest manifest,
            string manifestPath,
            JObject request,
            Action<JObject> beforeWorkerStart,
            Action<JObject> batchCompleted,
            out Action startWorker)
        {
            startWorker = null;
            lock (_lock)
            {
                if (_state == "running")
                    return BuildError("batch_already_running", "arena calibration batch is already running");
                if (_transportPoisoned)
                {
                    if (!CanRebindAfterTransportLoss())
                        return BuildError("transport_poisoned", "a new exact owned Flash is required after transport loss; Workers must restart the Host");
                    _sessionEpoch = Guid.NewGuid().ToString("N");
                    _transportPoisoned = false;
                }
                if ((request["workerId"] != null && ArenaRunIdentity.ReadId(request, "workerId") != _workerId)
                    || (request["sessionEpoch"] != null && ArenaRunIdentity.ReadId(request, "sessionEpoch") != _sessionEpoch))
                    return BuildError("session_mismatch", "requested worker/session does not match this Host");
                string assignmentId = ArenaRunIdentity.ReadId(request, "assignmentId", Guid.NewGuid().ToString("N"));
                string attemptId = ArenaRunIdentity.ReadId(request, "attemptId", Guid.NewGuid().ToString("N"));

                string batchDir = Path.Combine(ResolveBatchDir(manifest.BatchId), "attempts", attemptId);
                RejectReparseAncestors(batchDir);
                Directory.CreateDirectory(batchDir);
                string frozenPath = Path.Combine(batchDir, "case_manifest.json");
                string resultPath = Path.Combine(batchDir, "results.jsonl");
                // Exclusive create is the attempt admission. Never overwrite an old receipt.
                using (var resultFile = new FileStream(resultPath, FileMode.CreateNew, FileAccess.Write, FileShare.Read)) { }
                using (var manifestFile = new FileStream(frozenPath, FileMode.CreateNew, FileAccess.Write, FileShare.Read))
                using (var writer = new StreamWriter(manifestFile, new UTF8Encoding(false)))
                    writer.WriteLine(manifest.Frozen.ToString(Formatting.Indented));
                _frozenManifestPath = frozenPath;
                _resultPath = resultPath;
                _assignmentId = assignmentId;
                _attemptId = attemptId;
                _batchOwnedFlash = _observedOwnedFlash;

                _abortRequested = false;
                _state = "running";
                _batchId = manifest.BatchId;
                _manifestHash = manifest.ManifestHash;
                _manifestPath = manifestPath ?? _frozenManifestPath;
                _currentCaseId = null;
                _currentRunId = null;
                _lastError = null;
                _lastResultRow = null;
                _totalRuns = manifest.TotalRuns;
                _completedRuns = 0;
            }

            JObject started = BuildStatus(true, "started");
            if (beforeWorkerStart != null)
            {
                try
                {
                    beforeWorkerStart(started);
                }
                catch (Exception ex)
                {
                    LogManager.Log("[ArenaCalibrationTask] beforeWorkerStart exception: " + ex);
                }
            }

            startWorker = delegate
            {
                ThreadPool.QueueUserWorkItem(delegate
                {
                    RunBatch(manifest, batchCompleted);
                });
            };
            return started;
        }

        private JObject AbortBatch(JObject msg)
        {
            string batchId = msg.Value<string>("batchId");
            string activeBatchId = null;
            bool shouldNotifyFlash = false;
            JObject abortIdentity = null;
            int abortGeneration = 0;
            lock (_lock)
            {
                if (!string.IsNullOrEmpty(batchId) && !string.IsNullOrEmpty(_batchId) && batchId != _batchId)
                    return BuildError("batch_mismatch", "requested batchId does not match active batch");
                foreach (string key in new[] { "workerId", "sessionEpoch", "assignmentId", "attemptId" })
                {
                    string expected = key == "workerId" ? _workerId : key == "sessionEpoch" ? _sessionEpoch
                        : key == "assignmentId" ? _assignmentId : _attemptId;
                    if (msg[key] != null && ArenaRunIdentity.ReadId(msg, key) != expected)
                        return BuildError("attempt_mismatch", "abort identity does not match active attempt");
                }

                if (_state == "idle" || _state == "completed" || _state == "failed" || _state == "aborted")
                    return BuildStatus(true, "not_running");

                _abortRequested = true;
                activeBatchId = _batchId;
                shouldNotifyFlash = true;
                foreach (PendingRun pending in _pending.Values)
                {
                    abortIdentity = pending.Identity;
                    abortGeneration = pending.SocketGeneration;
                    pending.Aborted = true;
                    pending.Done.Set();
                }
            }

            if (shouldNotifyFlash)
                DispatchAbortToFlash(activeBatchId, "batch abort requested", abortIdentity, abortGeneration);

            return BuildStatus(true, "abort_requested");
        }

        private void RunBatch(BatchManifest manifest, Action<JObject> batchCompleted)
        {
            try
            {
                foreach (CalibrationCase testCase in manifest.Cases)
                {
                    for (int repeatIndex = 1; repeatIndex <= testCase.Repeat; repeatIndex++)
                    {
                        if (_abortRequested || _transportPoisoned)
                            break;
                        RunSingleCase(manifest, testCase, repeatIndex);
                    }
                    if (_abortRequested || _transportPoisoned)
                        break;
                }

                lock (_lock)
                {
                    if (_transportPoisoned && _state == "running")
                        _state = "failed";
                    else if (_abortRequested && _state == "running")
                        _state = "aborted";
                    else if (_state == "running")
                        _state = "completed";
                    _currentCaseId = null;
                    _currentRunId = null;
                }
            }
            catch (Exception ex)
            {
                LogManager.Log("[ArenaCalibrationTask] batch exception: " + ex);
                lock (_lock)
                {
                    _state = "failed";
                    _lastError = ex.Message;
                    _currentCaseId = null;
                    _currentRunId = null;
                }
            }
            finally
            {
                NotifyBatchCompleted(batchCompleted);
            }
        }

        private void NotifyBatchCompleted(Action<JObject> batchCompleted)
        {
            JObject status = BuildStatus(true, "terminal");
            InvokeBatchCompleted(_batchCompleted, status, "shared");
            if (batchCompleted != null && batchCompleted != _batchCompleted)
                InvokeBatchCompleted(batchCompleted, status, "request");
        }

        private static void InvokeBatchCompleted(
            Action<JObject> handler,
            JObject status,
            string scope)
        {
            if (handler == null) return;
            try
            {
                handler((JObject)status.DeepClone());
            }
            catch (Exception ex)
            {
                LogManager.Log("[ArenaCalibrationTask] " + scope
                    + " batch completion handler exception: " + ex);
            }
        }

        private void RunSingleCase(BatchManifest manifest, CalibrationCase testCase, int repeatIndex)
        {
            string runId = testCase.CaseId + "-r" + repeatIndex.ToString("D3");
            DateTime startedAt = DateTime.UtcNow;
            PendingRun pending = new PendingRun
            {
                Done = new ManualResetEventSlim(false),
                TestCase = testCase,
                RepeatIndex = repeatIndex,
                RunId = runId,
                StartedAtUtc = startedAt
            };

            int fid;
            lock (_lock)
            {
                fid = ++_seq;
                pending.SocketGeneration = _readyGeneration();
                pending.Identity = ArenaRunIdentity.Capture(BuildFlashCommand(manifest, testCase, repeatIndex, runId, fid));
                _pending[fid] = pending;
                _currentCaseId = testCase.CaseId;
                _currentRunId = runId;
            }

            if (pending.SocketGeneration == 0)
            {
                RemovePending(fid);
                AppendResultRow(BuildSyntheticResult(manifest, testCase, repeatIndex, runId, startedAt,
                    "bridge_lost", "none", "Flash socket client disconnected before run dispatch"));
                MarkCompleted();
                PoisonTransport("Flash socket client disconnected before run dispatch", pending.SocketGeneration);
                return;
            }

            JObject command = BuildFlashCommand(manifest, testCase, repeatIndex, runId, fid);
            try
            {
                if (pending.TransportError == null
                    && !_sendForGeneration(pending.SocketGeneration, command.ToString(Formatting.None) + "\0"))
                    pending.TransportError = "Flash socket generation changed or run dispatch failed";
            }
            catch (Exception ex)
            {
                pending.TransportError = "Flash run dispatch failed: " + ex.GetType().Name;
            }

            int timeoutMs = _timeoutMsFromFrames(testCase.TimeoutFrames);
            bool completed = pending.TransportError == null && pending.Done.Wait(timeoutMs);
            RemovePending(fid);

            JObject row;
            if (pending.TransportError != null)
            {
                row = BuildSyntheticResult(manifest, testCase, repeatIndex, runId, startedAt,
                    "bridge_lost", "none", pending.TransportError);
            }
            else if (pending.Aborted || _abortRequested)
            {
                row = BuildSyntheticResult(manifest, testCase, repeatIndex, runId, startedAt,
                    "aborted", "none", "batch aborted");
            }
            else if (!completed || pending.Response == null)
            {
                row = BuildSyntheticResult(manifest, testCase, repeatIndex, runId, startedAt,
                    "bridge_lost", "none", "Host transport deadline elapsed before AS2 arena calibration response");
            }
            else
            {
                row = BuildResultFromFlash(manifest, testCase, repeatIndex, runId, startedAt, pending.Response);
            }

            AppendResultRow(row);
            MarkCompleted();
            if (row.Value<string>("status") == "bridge_lost")
                PoisonTransport(pending.TransportError ?? "Host transport deadline elapsed before AS2 arena calibration response", pending.SocketGeneration);
        }

        private void HandleTransportDisconnected(int generation)
        {
            lock (_lock)
            {
                foreach (PendingRun pending in _pending.Values)
                {
                    if (pending.SocketGeneration != generation) continue;
                    pending.TransportError = "Flash socket disconnected during this exact run";
                    pending.Done.Set();
                }
            }
        }

        private void PoisonTransport(string reason, int generation)
        {
            lock (_lock)
            {
                if (_transportPoisoned) return;
                _transportPoisoned = true;
                _lastError = reason;
            }
            // Retire only the connection captured by this run. A replacement
            // connection is never used to cancel or complete the old run.
            try { if (generation != 0) _retireGeneration?.Invoke(generation); } catch { }
            try { TransportPoisoned?.Invoke(reason); } catch { }
        }

        private JObject BuildFlashCommand(BatchManifest manifest, CalibrationCase testCase, int repeatIndex, string runId, int fid)
        {
            JObject command = new JObject();
            command["task"] = "cmd";
            command["action"] = "arenaCalibrationRun";
            command["callId"] = fid;
            command["workerId"] = _workerId;
            command["sessionEpoch"] = _sessionEpoch;
            command["assignmentId"] = _assignmentId;
            command["attemptId"] = _attemptId;
            command["batchId"] = manifest.BatchId;
            command["manifestHash"] = manifest.ManifestHash;
            command["caseId"] = testCase.CaseId;
            command["caseHash"] = testCase.CaseHash;
            command["runId"] = runId;
            command["repeatIndex"] = repeatIndex;
            command["timeoutFrames"] = testCase.TimeoutFrames;
            command["spawnDistance"] = testCase.SpawnDistance;
            command["blueFormation"] = testCase.BlueFormation;
            command["redFormation"] = testCase.RedFormation;
            command["formationSpacing"] = testCase.FormationSpacing;
            command["authorityContext"] = testCase.AuthorityContext != null
                ? testCase.AuthorityContext.DeepClone()
                : new JObject();
            command["blueRoster"] = ToFlashRoster(testCase.BlueRoster);
            command["redRoster"] = ToFlashRoster(testCase.RedRoster);
            return command;
        }

        private void DispatchAbortToFlash(string batchId, string reason, JObject capturedIdentity, int capturedGeneration)
        {
            if (!_isClientReady())
            {
                LogManager.Log("[ArenaCalibrationTask] abort requested while Flash socket is disconnected; local batch state will still abort");
                return;
            }

            int fid;
            int generation = capturedGeneration;
            JObject identity = capturedIdentity;
            lock (_lock)
            {
                fid = ++_seq;
                if (generation == 0) generation = _readyGeneration();
            }

            JObject command = new JObject();
            command["task"] = "cmd";
            command["action"] = "arenaCalibrationAbort";
            command["callId"] = fid;
            command["batchId"] = batchId ?? "";
            command["reason"] = reason ?? "abort";
            if (identity != null) ArenaRunIdentity.Copy(identity, command);

            try
            {
                _sendForGeneration(generation, command.ToString(Formatting.None) + "\0");
            }
            catch (Exception ex)
            {
                LogManager.Log("[ArenaCalibrationTask] failed to dispatch Flash abort cleanup command: " + ex.Message);
            }
        }

        private JObject BuildResultFromFlash(
            BatchManifest manifest,
            CalibrationCase testCase,
            int repeatIndex,
            string runId,
            DateTime startedAtUtc,
            JObject response)
        {
            JObject result = response.Value<JObject>("result") ?? response;
            string status = result.Value<string>("status");
            if (string.IsNullOrEmpty(status))
                status = result.Value<bool?>("success") == false ? "error" : "finished";

            string winner = result.Value<string>("winner");
            if (string.IsNullOrEmpty(winner))
                winner = status == "timeout" ? "timeout" : "none";

            JObject row = BuildResultEnvelope(manifest, testCase, repeatIndex, runId, startedAtUtc, status, winner);
            ArenaRunIdentity.Copy(ArenaRunIdentity.Capture(result), row);
            CopyOptionalNumber(result, row, "frames");
            CopyOptionalNumber(result, row, "durationMs");
            CopyOptionalNumber(result, row, "spawnDistance");
            CopyOptionalString(result, row, "blueFormation", testCase.BlueFormation);
            CopyOptionalString(result, row, "redFormation", testCase.RedFormation);
            if (result["formationSpacing"] != null && result["formationSpacing"].Type != JTokenType.Null)
                CopyOptionalNumber(result, row, "formationSpacing");
            if (result["phaseSpawnCount"] != null && result["phaseSpawnCount"].Type != JTokenType.Null)
                CopyOptionalNumber(result, row, "phaseSpawnCount");
            row["spawnedUnits"] = result["spawnedUnits"] != null && result["spawnedUnits"].Type == JTokenType.Array
                ? result["spawnedUnits"].DeepClone()
                : new JArray();
            CopyOptionalNumber(result, row, "blueX");
            CopyOptionalNumber(result, row, "redX");
            row["blueSpawnPositions"] = CloneArrayOrEmpty(result["blueSpawnPositions"]);
            row["redSpawnPositions"] = CloneArrayOrEmpty(result["redSpawnPositions"]);
            row["formationAudit"] = CloneObjectOrEmpty(result["formationAudit"]);
            if (result["skillStateAudit"] is JObject)
                row["skillStateAudit"] = result["skillStateAudit"].DeepClone();
            if (result["presentationAudit"] is JObject)
                row["presentationAudit"] = result["presentationAudit"].DeepClone();
            row["blue"] = NormalizeSideSummary(result.Value<JObject>("blue"));
            row["red"] = NormalizeSideSummary(result.Value<JObject>("red"));
            row["blueUnitResults"] = NormalizeUnitResults(result["blueUnitResults"]);
            row["redUnitResults"] = NormalizeUnitResults(result["redUnitResults"]);
            row["errors"] = NormalizeErrors(result["errors"]);
            return row;
        }

        private JObject BuildSyntheticResult(
            BatchManifest manifest,
            CalibrationCase testCase,
            int repeatIndex,
            string runId,
            DateTime startedAtUtc,
            string status,
            string winner,
            string message)
        {
            JObject row = BuildResultEnvelope(manifest, testCase, repeatIndex, runId, startedAtUtc, status, winner);
            row["frames"] = null;
            row["durationMs"] = null;
            row["blue"] = NormalizeSideSummary(null);
            row["red"] = NormalizeSideSummary(null);
            row["blueUnitResults"] = new JArray();
            row["redUnitResults"] = new JArray();
            JArray errors = new JArray();
            JObject error = new JObject();
            error["code"] = status;
            error["message"] = message;
            errors.Add(error);
            row["errors"] = errors;
            return row;
        }

        private JObject BuildResultEnvelope(
            BatchManifest manifest,
            CalibrationCase testCase,
            int repeatIndex,
            string runId,
            DateTime startedAtUtc,
            string status,
            string winner)
        {
            JObject row = new JObject();
            row["schema"] = "arena-calibration.result.v1";
            row["workerId"] = _workerId;
            row["sessionEpoch"] = _sessionEpoch;
            row["assignmentId"] = _assignmentId;
            row["attemptId"] = _attemptId;
            row["batchId"] = manifest.BatchId;
            row["manifestHash"] = manifest.ManifestHash;
            row["caseId"] = testCase.CaseId;
            row["caseHash"] = testCase.CaseHash;
            row["runId"] = runId;
            row["repeatIndex"] = repeatIndex;
            row["status"] = status;
            row["winner"] = winner;
            row["startedAt"] = startedAtUtc.ToString("o");
            row["completedAt"] = DateTime.UtcNow.ToString("o");
            row["requestedSpawnDistance"] = testCase.SpawnDistance;
            row["blueFormation"] = testCase.BlueFormation;
            row["redFormation"] = testCase.RedFormation;
            row["formationSpacing"] = testCase.FormationSpacing;
            row["phaseSpawnCount"] = 0;
            row["spawnedUnits"] = new JArray();
            row["blueSpawnPositions"] = new JArray();
            row["redSpawnPositions"] = new JArray();
            row["formationAudit"] = new JObject();
            row["authorityContext"] = testCase.AuthorityContext != null
                ? testCase.AuthorityContext.DeepClone()
                : new JObject();
            row["blueUnitResults"] = new JArray();
            row["redUnitResults"] = new JArray();
            return row;
        }

        private void AppendResultRow(JObject row)
        {
            string resultPath;
            lock (_lock)
            {
                resultPath = _resultPath;
                _lastResultRow = (JObject)row.DeepClone();
            }
            File.AppendAllText(resultPath, row.ToString(Formatting.None) + Environment.NewLine, new UTF8Encoding(false));
        }

        private void MarkCompleted()
        {
            lock (_lock)
            {
                _completedRuns++;
                _currentCaseId = null;
                _currentRunId = null;
            }
        }

        private void RemovePending(int fid)
        {
            lock (_lock)
            {
                _pending.Remove(fid);
            }
        }

        private JObject BuildStatus(bool success, string note)
        {
            lock (_lock)
            {
                JObject status = new JObject();
                status["success"] = success;
                status["ok"] = success;
                status["task"] = "arena_calibration";
                status["workerId"] = _workerId;
                status["sessionEpoch"] = _sessionEpoch;
                status["assignmentId"] = _assignmentId;
                status["attemptId"] = _attemptId;
                status["transportPoisoned"] = _transportPoisoned;
                status["state"] = _state;
                status["note"] = note;
                status["batchId"] = _batchId;
                status["manifestHash"] = _manifestHash;
                status["manifestPath"] = ToProjectRelative(_manifestPath);
                status["frozenManifestPath"] = ToProjectRelative(_frozenManifestPath);
                status["resultPath"] = ToProjectRelative(_resultPath);
                status["totalRuns"] = _totalRuns;
                status["completedRuns"] = _completedRuns;
                status["currentCaseId"] = _currentCaseId;
                status["currentRunId"] = _currentRunId;
                status["lastError"] = _lastError;
                status["lastResult"] = _lastResultRow != null ? _lastResultRow.DeepClone() : JValue.CreateNull();
                if (_allowFaultInjection)
                    status["faultReceipt"] = _faultReceipt != null ? _faultReceipt.DeepClone() : JValue.CreateNull();
                return status;
            }
        }

        private JObject BuildError(string code, string message)
        {
            JObject error = BuildStatus(false, null);
            error["error"] = code;
            error["message"] = message;
            return error;
        }

        private string ResolveManifestPath(string manifestPath)
        {
            if (string.IsNullOrEmpty(manifestPath))
                throw new InvalidOperationException("missing manifestPath");

            if (Path.IsPathRooted(manifestPath))
                throw new InvalidOperationException("manifestPath must be a project-relative path under tmp/arena-calibration");

            string full = Path.GetFullPath(Path.Combine(_projectRoot, manifestPath));
            string allowedRoot = Path.GetFullPath(Path.Combine(_projectRoot, "tmp", "arena-calibration"));
            string allowedPrefix = allowedRoot.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)
                + Path.DirectorySeparatorChar;

            if (!full.StartsWith(allowedPrefix, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("manifestPath must stay under tmp/arena-calibration");
            if (!File.Exists(full))
                throw new FileNotFoundException("manifestPath not found", full);
            RejectReparseAncestors(full);
            return full;
        }

        private BatchManifest LoadAndNormalizeManifest(string manifestPath)
        {
            JObject input = JObject.Parse(File.ReadAllText(manifestPath, Encoding.UTF8));
            return NormalizeManifest(input);
        }

        private BatchManifest BuildInlineSingleManifest(JObject msg)
        {
            JObject sourceCase = msg["case"] as JObject
                ?? msg["calibrationCase"] as JObject
                ?? msg.SelectToken("payload.calibrationCase") as JObject;
            if (sourceCase == null)
                throw new InvalidOperationException("missing calibrationCase");

            JObject normalizedCase = (JObject)sourceCase.DeepClone();
            if (string.IsNullOrEmpty(normalizedCase.Value<string>("caseId")))
                normalizedCase["caseId"] = "arena-custom-case";
            if (normalizedCase["repeat"] == null)
                normalizedCase["repeat"] = PositiveInt(msg["repeat"], "repeat", 1);
            if (normalizedCase["spawnDistance"] == null && msg["spawnDistance"] != null)
                normalizedCase["spawnDistance"] = PositiveInt(msg["spawnDistance"], "spawnDistance", 0);
            if (normalizedCase["blueFormation"] == null && msg["blueFormation"] != null)
                normalizedCase["blueFormation"] = NormalizeFormation(msg.Value<string>("blueFormation"), "blueFormation");
            if (normalizedCase["redFormation"] == null && msg["redFormation"] != null)
                normalizedCase["redFormation"] = NormalizeFormation(msg.Value<string>("redFormation"), "redFormation");
            if (normalizedCase["formationSpacing"] == null && msg["formationSpacing"] != null)
                normalizedCase["formationSpacing"] = PositiveInt(msg["formationSpacing"], "formationSpacing", 0);

            int timeoutFrames = PositiveInt(
                normalizedCase["timeoutFrames"] ?? msg["timeoutFrames"],
                "timeoutFrames",
                3600);
            normalizedCase["timeoutFrames"] = timeoutFrames;

            string batchId = msg.Value<string>("batchId");
            if (string.IsNullOrEmpty(batchId))
            {
                batchId = "custom-" + DateTime.UtcNow.ToString("yyyyMMdd-HHmmss") + "-"
                    + Guid.NewGuid().ToString("N").Substring(0, 8);
            }

            JObject manifest = new JObject();
            manifest["schema"] = "arena-calibration.case-manifest.v1";
            manifest["batchId"] = batchId;
            manifest["createdAt"] = msg.Value<string>("createdAt") ?? DateTime.UtcNow.ToString("o");
            manifest["buildCommit"] = msg.Value<string>("buildCommit") ?? "arena-custom-p2";
            manifest["planner"] = new JObject
            {
                ["name"] = "arena-custom-match",
                ["version"] = 2,
                ["matchCode"] = msg.Value<string>("matchCode") ?? ""
            };
            manifest["arenaMode"] = "calibration";
            manifest["repeat"] = PositiveInt(msg["repeat"], "repeat", 1);
            manifest["timeoutFrames"] = timeoutFrames;
            manifest["blueBench"] = JValue.CreateNull();
            manifest["cases"] = new JArray(normalizedCase);
            return NormalizeManifest(manifest);
        }

        private BatchManifest NormalizeManifest(JObject input)
        {
            RejectEconomyKeys(input, "$");

            string schema = input.Value<string>("schema");
            if (schema != "arena-calibration.case-manifest.v1")
                throw new InvalidOperationException("unsupported manifest schema: " + schema);

            string batchId = ValidateBatchId(RequiredString(input, "batchId"));
            int repeat = PositiveInt(input["repeat"], "repeat", 5);
            int timeoutFrames = PositiveInt(input["timeoutFrames"], "timeoutFrames", 5400);
            JArray cases = input.Value<JArray>("cases");
            if (cases == null || cases.Count == 0)
                throw new InvalidOperationException("manifest cases must be non-empty");

            JObject frozen = new JObject();
            frozen["schema"] = schema;
            frozen["batchId"] = batchId;
            frozen["createdAt"] = input.Value<string>("createdAt") ?? DateTime.UtcNow.ToString("o");
            frozen["buildCommit"] = input.Value<string>("buildCommit") ?? "unknown";
            frozen["planner"] = input["planner"] != null ? input["planner"].DeepClone() : new JObject();
            frozen["arenaMode"] = input.Value<string>("arenaMode") ?? "calibration";
            frozen["repeat"] = repeat;
            frozen["timeoutFrames"] = timeoutFrames;
            frozen["blueBench"] = input["blueBench"] != null ? input["blueBench"].DeepClone() : JValue.CreateNull();

            if ((string)frozen["arenaMode"] != "calibration")
                throw new InvalidOperationException("arenaMode must be calibration");

            JArray frozenCases = new JArray();
            List<CalibrationCase> normalizedCases = new List<CalibrationCase>();
            HashSet<string> caseIds = new HashSet<string>(StringComparer.Ordinal);

            for (int i = 0; i < cases.Count; i++)
            {
                JObject sourceCase = cases[i] as JObject;
                if (sourceCase == null)
                    throw new InvalidOperationException("case entry must be an object at index " + i);

                string caseId = RequiredString(sourceCase, "caseId");
                if (!caseIds.Add(caseId))
                    throw new InvalidOperationException("duplicate caseId: " + caseId);

                int caseRepeat = PositiveInt(sourceCase["repeat"], "cases[" + i + "].repeat", repeat);
                int caseTimeout = PositiveInt(sourceCase["timeoutFrames"], "cases[" + i + "].timeoutFrames", timeoutFrames);
                int caseSpawnDistance = PositiveInt(sourceCase["spawnDistance"], "cases[" + i + "].spawnDistance", DefaultSpawnDistance);
                string caseBlueFormation = NormalizeFormation(sourceCase.Value<string>("blueFormation"), "cases[" + i + "].blueFormation");
                string caseRedFormation = NormalizeFormation(sourceCase.Value<string>("redFormation"), "cases[" + i + "].redFormation");
                int caseFormationSpacing = PositiveInt(sourceCase["formationSpacing"], "cases[" + i + "].formationSpacing", DefaultFormationSpacing);
                JArray blueRoster = NormalizeRoster(sourceCase["blueRoster"] as JArray, "cases[" + i + "].blueRoster");
                JArray redRoster = NormalizeRoster(sourceCase["redRoster"] as JArray, "cases[" + i + "].redRoster");

                JObject frozenCase = new JObject();
                frozenCase["caseId"] = caseId;
                frozenCase["blueRoster"] = blueRoster.DeepClone();
                frozenCase["redRoster"] = redRoster.DeepClone();
                frozenCase["repeat"] = caseRepeat;
                frozenCase["timeoutFrames"] = caseTimeout;
                frozenCase["spawnDistance"] = caseSpawnDistance;
                frozenCase["blueFormation"] = caseBlueFormation;
                frozenCase["redFormation"] = caseRedFormation;
                frozenCase["formationSpacing"] = caseFormationSpacing;
                frozenCase["tags"] = sourceCase["tags"] != null ? sourceCase["tags"].DeepClone() : new JArray();
                frozenCase["plannerReason"] = sourceCase.Value<string>("plannerReason") ?? "";
                JToken authorityContextToken = sourceCase["authorityContext"];
                bool hasAuthorityContext = authorityContextToken != null
                    && authorityContextToken.Type != JTokenType.Null;
                JObject authorityContext = authorityContextToken as JObject;
                if (hasAuthorityContext && authorityContext == null)
                    throw new InvalidOperationException(
                        "cases[" + i + "].authorityContext must be an object");
                authorityContext = authorityContext != null
                    ? (JObject)authorityContext.DeepClone()
                    : new JObject();
                if (hasAuthorityContext)
                    frozenCase["authorityContext"] = authorityContext.DeepClone();

                JObject hashInput = new JObject();
                hashInput["caseId"] = caseId;
                hashInput["blueRoster"] = blueRoster.DeepClone();
                hashInput["redRoster"] = redRoster.DeepClone();
                hashInput["repeat"] = caseRepeat;
                hashInput["timeoutFrames"] = caseTimeout;
                hashInput["spawnDistance"] = caseSpawnDistance;
                hashInput["blueFormation"] = caseBlueFormation;
                hashInput["redFormation"] = caseRedFormation;
                hashInput["formationSpacing"] = caseFormationSpacing;
                if (hasAuthorityContext)
                    hashInput["authorityContext"] = authorityContext.DeepClone();
                string caseHash = Sha256OfToken(hashInput);
                frozenCase["caseHash"] = caseHash;

                string suppliedCaseHash = sourceCase.Value<string>("caseHash");
                if (!string.IsNullOrEmpty(suppliedCaseHash) && suppliedCaseHash != caseHash)
                    throw new InvalidOperationException("caseHash mismatch for " + caseId);

                frozenCases.Add(frozenCase);
                normalizedCases.Add(new CalibrationCase
                {
                    CaseId = caseId,
                    CaseHash = caseHash,
                    BlueRoster = blueRoster,
                    RedRoster = redRoster,
                    Repeat = caseRepeat,
                    TimeoutFrames = caseTimeout,
                    SpawnDistance = caseSpawnDistance,
                    BlueFormation = caseBlueFormation,
                    RedFormation = caseRedFormation,
                    FormationSpacing = caseFormationSpacing,
                    AuthorityContext = authorityContext
                });
            }

            frozen["cases"] = frozenCases;
            JObject manifestHashInput = new JObject();
            manifestHashInput["schema"] = frozen["schema"].DeepClone();
            manifestHashInput["batchId"] = frozen["batchId"].DeepClone();
            manifestHashInput["buildCommit"] = frozen["buildCommit"].DeepClone();
            manifestHashInput["planner"] = frozen["planner"].DeepClone();
            manifestHashInput["arenaMode"] = frozen["arenaMode"].DeepClone();
            manifestHashInput["repeat"] = frozen["repeat"].DeepClone();
            manifestHashInput["timeoutFrames"] = frozen["timeoutFrames"].DeepClone();
            manifestHashInput["blueBench"] = frozen["blueBench"].DeepClone();
            manifestHashInput["cases"] = frozenCases.DeepClone();
            string manifestHash = Sha256OfToken(manifestHashInput);
            frozen["manifestHash"] = manifestHash;

            string suppliedManifestHash = input.Value<string>("manifestHash");
            if (!string.IsNullOrEmpty(suppliedManifestHash) && suppliedManifestHash != manifestHash)
                throw new InvalidOperationException("manifestHash mismatch");

            int totalRuns = 0;
            foreach (CalibrationCase testCase in normalizedCases)
                totalRuns += testCase.Repeat;

            return new BatchManifest
            {
                BatchId = batchId,
                ManifestHash = manifestHash,
                Frozen = frozen,
                Cases = normalizedCases,
                TotalRuns = totalRuns
            };
        }

        private static JArray NormalizeRoster(JArray roster, string fieldName)
        {
            if (roster == null || roster.Count == 0)
                throw new InvalidOperationException(fieldName + " must be a non-empty array");

            JArray normalized = new JArray();
            for (int i = 0; i < roster.Count; i++)
            {
                JObject entry = roster[i] as JObject;
                if (entry == null)
                    throw new InvalidOperationException(fieldName + "[" + i + "] must be an object");

                JToken levelToken = entry["level"] ?? entry["等级"];
                int level = PositiveInt(levelToken, fieldName + "[" + i + "].level", 0);
                JObject normalizedEntry = new JObject();
                normalizedEntry["level"] = level;

                JToken petIdToken = entry["petId"];
                string type = entry.Value<string>("type") ?? entry.Value<string>("兵种");
                if (petIdToken != null && petIdToken.Type != JTokenType.Null)
                {
                    if (!string.IsNullOrEmpty(type))
                        throw new InvalidOperationException(fieldName + "[" + i + "] cannot mix petId with type");
                    int petId = BoundedInt(petIdToken, fieldName + "[" + i + "].petId", 0, 1000000);
                    string identifier = RequiredSafeString(
                        entry,
                        "identifier",
                        fieldName + "[" + i + "].identifier",
                        160);
                    string rosterType = entry.Value<string>("rosterType") ?? PetDef.DefaultRosterType;
                    if (!PetCatalogLoader.IsValidRosterType(rosterType))
                        throw new InvalidOperationException(fieldName + "[" + i + "].rosterType is invalid");
                    normalizedEntry["petId"] = petId;
                    normalizedEntry["identifier"] = identifier;
                    normalizedEntry["rosterType"] = rosterType;
                    normalizedEntry["strategicPromotions"] = NormalizeStrategicPetPromotions(
                        entry["strategicPromotions"],
                        fieldName + "[" + i + "].strategicPromotions");
                }
                else
                {
                    if (entry["strategicPromotions"] != null
                        && entry["strategicPromotions"].Type != JTokenType.Null)
                        throw new InvalidOperationException(
                            fieldName + "[" + i + "] strategicPromotions requires petId authority");
                    if (string.IsNullOrEmpty(type) || !Regex.IsMatch(type, "^兵种[0-9]+$"))
                        throw new InvalidOperationException(fieldName + "[" + i + "].type must use 兵种N");
                    normalizedEntry["type"] = type;
                }

                string sourceId = entry.Value<string>("sourceId") ?? entry.Value<string>("unitId");
                if (!string.IsNullOrEmpty(sourceId))
                {
                    if (!SourceIdPattern.IsMatch(sourceId))
                        throw new InvalidOperationException(fieldName + "[" + i + "].sourceId is invalid");
                    normalizedEntry["sourceId"] = sourceId;
                }
                if (entry["hpPermille"] != null && entry["hpPermille"].Type != JTokenType.Null)
                {
                    normalizedEntry["hpPermille"] = BoundedInt(
                        entry["hpPermille"],
                        fieldName + "[" + i + "].hpPermille",
                        1,
                        1000);
                }
                JToken parameters = entry["parameters"] ?? entry["Parameters"] ?? entry["参数"];
                if (parameters != null && parameters.Type != JTokenType.Null)
                    normalizedEntry["parameters"] = parameters.DeepClone();
                normalized.Add(normalizedEntry);
            }
            return normalized;
        }

        private static JArray ToFlashRoster(JArray roster)
        {
            JArray result = new JArray();
            foreach (JObject entry in roster)
            {
                JObject normalized = new JObject();
                normalized["等级"] = entry.Value<int>("level");
                if (entry["petId"] != null)
                {
                    normalized["petId"] = entry.Value<int>("petId");
                    normalized["identifier"] = entry.Value<string>("identifier");
                    normalized["rosterType"] = entry.Value<string>("rosterType");
                    normalized["strategicPromotions"] = entry["strategicPromotions"].DeepClone();
                }
                else
                {
                    normalized["兵种"] = entry.Value<string>("type");
                }
                if (entry["sourceId"] != null)
                    normalized["sourceId"] = entry.Value<string>("sourceId");
                if (entry["hpPermille"] != null)
                    normalized["hpPermille"] = entry.Value<int>("hpPermille");
                if (entry["parameters"] != null && entry["parameters"].Type != JTokenType.Null)
                    normalized["Parameters"] = entry["parameters"].DeepClone();
                result.Add(normalized);
            }
            return result;
        }

        private static JArray NormalizeUnitResults(JToken token)
        {
            JArray input = token as JArray;
            if (input == null) return new JArray();

            JArray output = new JArray();
            foreach (JToken item in input)
            {
                JObject source = item as JObject;
                if (source == null) continue;
                string sourceId = source.Value<string>("sourceId")
                    ?? source.Value<string>("unitId")
                    ?? "";
                if (!SourceIdPattern.IsMatch(sourceId)) continue;

                JObject row = new JObject();
                row["sourceId"] = sourceId;
                row["petId"] = BoundedIntOrDefault(source["petId"], 0, 1000000, -1);
                row["identifier"] = SafeStringOrEmpty(source.Value<string>("identifier"), 160);
                row["resolvedType"] = SafeStringOrEmpty(source.Value<string>("resolvedType"), 160);
                row["level"] = BoundedIntOrDefault(source["level"], 1, 1000000, 1);
                bool strategicPromotionsValid;
                row["strategicPromotions"] = NormalizeStrategicPetPromotionsOrEmpty(
                    source["strategicPromotions"],
                    out strategicPromotionsValid);
                row["strategicPromotionsValid"] = strategicPromotionsValid;
                row["startMaxHp"] = NonNegativeNumber(source["startMaxHp"]);
                row["remainHp"] = NonNegativeNumber(source["remainHp"]);
                row["hpPermille"] = BoundedIntOrDefault(source["hpPermille"], 0, 1000, 0);
                row["alive"] = source.Value<bool?>("alive") == true;
                output.Add(row);
            }
            return output;
        }

        private static JArray NormalizeStrategicPetPromotions(
            JToken token,
            string fieldName)
        {
            if (token == null || token.Type == JTokenType.Null) return new JArray();
            JArray input = token as JArray;
            if (input == null || input.Count > 3)
                throw new InvalidOperationException(fieldName + " must be an array with at most 3 entries");
            HashSet<string> seen = new HashSet<string>(StringComparer.Ordinal);
            JArray output = new JArray();
            foreach (JToken item in input)
            {
                string name = item.Type == JTokenType.String ? item.Value<string>() : null;
                if (name == null || !AllowedStrategicPetPromotions.Contains(name) || !seen.Add(name))
                    throw new InvalidOperationException(fieldName + " contains an invalid or duplicate promotion");
                output.Add(name);
            }
            return output;
        }

        private static JArray NormalizeStrategicPetPromotionsOrEmpty(
            JToken token,
            out bool valid)
        {
            try
            {
                valid = true;
                return NormalizeStrategicPetPromotions(token, "strategicPromotions");
            }
            catch
            {
                valid = false;
                return new JArray();
            }
        }

        private static JObject NormalizeSideSummary(JObject input)
        {
            JObject side = new JObject();
            side["maxHp"] = NonNegativeNumber(input != null ? input["maxHp"] : null);
            side["remainHp"] = NonNegativeNumber(input != null ? input["remainHp"] : null);
            side["aliveCount"] = NonNegativeNumber(input != null ? input["aliveCount"] : null);
            side["startMaxHp"] = NonNegativeNumber(input != null ? input["startMaxHp"] : side["maxHp"]);
            side["startCount"] = NonNegativeNumber(input != null ? input["startCount"] : side["aliveCount"]);
            return side;
        }

        private static JArray NormalizeErrors(JToken token)
        {
            if (token is JArray)
                return (JArray)token.DeepClone();
            return new JArray();
        }

        private static JArray CloneArrayOrEmpty(JToken token)
        {
            if (token is JArray)
                return (JArray)token.DeepClone();
            return new JArray();
        }

        private static JObject CloneObjectOrEmpty(JToken token)
        {
            if (token is JObject)
                return (JObject)token.DeepClone();
            return new JObject();
        }

        private static void CopyOptionalNumber(JObject source, JObject target, string fieldName)
        {
            if (source[fieldName] == null || source[fieldName].Type == JTokenType.Null)
                target[fieldName] = null;
            else
                target[fieldName] = NonNegativeNumber(source[fieldName]);
        }

        private static void CopyOptionalString(JObject source, JObject target, string fieldName, string defaultValue)
        {
            string value = source.Value<string>(fieldName);
            target[fieldName] = string.IsNullOrEmpty(value) ? (defaultValue ?? "") : value;
        }

        internal static int DefaultTransportTimeoutMsFromFrames(int frames)
        {
            // timeoutFrames 是 Flash 战斗的逻辑帧预算，不是 Host socket 的墙钟截止。
            // Host 从命令下发前开始计时，必须覆盖舞台切换、低帧率、清理和回包；
            // 否则 1800 帧在 AS2 产生 timeout 回包的同一时刻就会被 Host 抢先合成 timeout。
            double semanticBudgetMs = Math.Ceiling(frames * 1000.0 / 30.0);
            double transportDeadlineMs = semanticBudgetMs * 2.0 + 30000.0;
            if (transportDeadlineMs < 30000.0)
                transportDeadlineMs = 30000.0;
            if (transportDeadlineMs > 600000.0)
                transportDeadlineMs = 600000.0;
            return (int)transportDeadlineMs;
        }

        private static int PositiveInt(JToken token, string fieldName, int defaultValue)
        {
            if (token == null || token.Type == JTokenType.Null)
            {
                if (defaultValue > 0)
                    return defaultValue;
                throw new InvalidOperationException(fieldName + " must be a positive integer");
            }

            int value;
            if (!int.TryParse(token.ToString(), out value) || value <= 0)
                throw new InvalidOperationException(fieldName + " must be a positive integer");
            return value;
        }

        private static int BoundedInt(
            JToken token,
            string fieldName,
            int minimum,
            int maximum)
        {
            int value;
            if (token == null
                || token.Type == JTokenType.Null
                || !int.TryParse(token.ToString(), out value)
                || value < minimum
                || value > maximum)
            {
                throw new InvalidOperationException(fieldName + " must be an integer in ["
                    + minimum + "," + maximum + "]");
            }
            return value;
        }

        private static int BoundedIntOrDefault(
            JToken token,
            int minimum,
            int maximum,
            int defaultValue)
        {
            int value;
            if (token == null
                || token.Type == JTokenType.Null
                || !int.TryParse(token.ToString(), out value)
                || value < minimum
                || value > maximum)
                return defaultValue;
            return value;
        }

        private static string RequiredSafeString(
            JObject source,
            string propertyName,
            string fieldName,
            int maximumLength)
        {
            string value = source.Value<string>(propertyName);
            value = SafeStringOrEmpty(value, maximumLength);
            if (value.Length == 0)
                throw new InvalidOperationException(fieldName + " is required");
            return value;
        }

        private static string SafeStringOrEmpty(string value, int maximumLength)
        {
            if (string.IsNullOrEmpty(value) || value.Length > maximumLength)
                return "";
            for (int i = 0; i < value.Length; i++)
            {
                if (char.IsControl(value[i])) return "";
            }
            return value;
        }

        private static string NormalizeFormation(string value, string fieldName)
        {
            string formation = string.IsNullOrEmpty(value) ? DefaultFormation : value;
            if (!AllowedFormations.Contains(formation))
                throw new InvalidOperationException(fieldName + " must be one of column,line,wedge,shield,grid");
            return formation;
        }

        private static double NonNegativeNumber(JToken token)
        {
            if (token == null || token.Type == JTokenType.Null)
                return 0.0;
            double value;
            if (!double.TryParse(token.ToString(), out value) || value < 0.0)
                return 0.0;
            return value;
        }

        private static string RequiredString(JObject obj, string fieldName)
        {
            string value = obj.Value<string>(fieldName);
            if (string.IsNullOrEmpty(value))
                throw new InvalidOperationException(fieldName + " is required");
            return value;
        }

        private static string ValidateBatchId(string batchId)
        {
            if (!BatchIdPattern.IsMatch(batchId))
                throw new InvalidOperationException("batchId must match ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$");
            return batchId;
        }

        private string ResolveBatchDir(string batchId)
        {
            string root = Path.GetFullPath(Path.Combine(_projectRoot, "tmp", "arena-calibration", "batches"));
            string full = Path.GetFullPath(Path.Combine(root, batchId));
            EnsurePathUnderDirectory(full, root, "batchDir");
            return full;
        }

        private static void RejectReparseAncestors(string path)
        {
            string current = Path.GetFullPath(path);
            while (!string.IsNullOrEmpty(current))
            {
                if ((File.Exists(current) || Directory.Exists(current))
                    && (File.GetAttributes(current) & FileAttributes.ReparsePoint) != 0)
                    throw new InvalidOperationException("Arena paths cannot contain reparse points");
                current = Path.GetDirectoryName(current);
            }
        }

        private static void EnsurePathUnderDirectory(string fullPath, string directoryRoot, string fieldName)
        {
            string root = Path.GetFullPath(directoryRoot).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)
                + Path.DirectorySeparatorChar;
            string full = Path.GetFullPath(fullPath);
            if (!full.StartsWith(root, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException(fieldName + " must stay under " + directoryRoot);
        }

        private static void RejectEconomyKeys(JToken token, string path)
        {
            if (token is JObject)
            {
                JObject obj = (JObject)token;
                foreach (JProperty property in obj.Properties())
                {
                    string lower = property.Name.ToLowerInvariant();
                    if (lower == "money" || lower == "cash" || lower == "gold" || lower == "coin"
                        || lower == "coins" || lower == "reward" || lower == "rewards"
                        || lower == "drop" || lower == "drops" || lower == "loot"
                        || lower == "item" || lower == "items" || lower == "equipment"
                        || lower == "equip" || lower == "exp" || lower == "xp"
                        || lower == "kpoint" || lower == "kpoints")
                        throw new InvalidOperationException(path + "." + property.Name + " is not allowed in arena calibration manifest");
                    RejectEconomyKeys(property.Value, path + "." + property.Name);
                }
            }
            else if (token is JArray)
            {
                JArray array = (JArray)token;
                for (int i = 0; i < array.Count; i++)
                    RejectEconomyKeys(array[i], path + "[" + i + "]");
            }
        }

        private static string Sha256OfToken(JToken token)
        {
            string canonicalJson = Canonicalize(token).ToString(Formatting.None);
            byte[] bytes = Encoding.UTF8.GetBytes(canonicalJson);
            using (SHA256 sha = SHA256.Create())
            {
                byte[] hash = sha.ComputeHash(bytes);
                StringBuilder sb = new StringBuilder("sha256:");
                foreach (byte b in hash)
                    sb.Append(b.ToString("x2"));
                return sb.ToString();
            }
        }

        private static JToken Canonicalize(JToken token)
        {
            if (token is JObject)
            {
                JObject source = (JObject)token;
                JObject result = new JObject();
                List<JProperty> properties = new List<JProperty>(source.Properties());
                properties.Sort(delegate(JProperty a, JProperty b)
                {
                    return string.CompareOrdinal(a.Name, b.Name);
                });
                foreach (JProperty property in properties)
                    result[property.Name] = Canonicalize(property.Value);
                return result;
            }
            if (token is JArray)
            {
                JArray source = (JArray)token;
                JArray result = new JArray();
                foreach (JToken item in source)
                    result.Add(Canonicalize(item));
                return result;
            }
            return token.DeepClone();
        }

        private string ToProjectRelative(string fullPath)
        {
            if (string.IsNullOrEmpty(fullPath))
                return null;
            try
            {
                return Path.GetRelativePath(_projectRoot, fullPath).Replace('\\', '/');
            }
            catch
            {
                return fullPath;
            }
        }
    }
}
