using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Threading;
using CF7Launcher.Guardian;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.ArenaWorker
{
    internal sealed class ArenaWorkerController
    {
        private readonly ArenaWorkerPolicy _policy;
        private readonly AgentControlTask _agent;
        private readonly Func<JObject, JObject> _arenaControl;
        private readonly ArenaCalibrationTask _arena;
        private readonly Func<CF7Launcher.Bus.XmlSocketPeerProcessIdentity, IArenaWorkerFaultProcess> _faultProcess;
        private readonly Func<Process> _flash;
        private readonly Action _shutdown;
        private readonly Action<Action> _queueShutdown;
        private readonly Func<JObject> _windowObservation;
        private readonly Func<JObject> _performanceObservation;
        private readonly object _gate = new object();
        private bool _startRequested;
        private bool _shutdownRequested;
        private JObject _shutdownResponse;
        private JObject _shutdownArena;
        private JObject _lastFlashIdentity;

        internal ArenaWorkerController(ArenaWorkerPolicy policy, AgentControlTask agent,
            ArenaCalibrationTask arena, Func<Process> flash, Action shutdown,
            Func<JObject, JObject> arenaControl = null, Func<JObject> windowObservation = null,
            Func<JObject> performanceObservation = null, Action<Action> queueShutdown = null,
            Func<CF7Launcher.Bus.XmlSocketPeerProcessIdentity, IArenaWorkerFaultProcess> faultProcess = null)
        {
            _policy = policy; _agent = agent; _flash = flash; _shutdown = shutdown;
            _arena = arena;
            _faultProcess = faultProcess ?? (identity => ArenaWorkerFaultProcess.Open(identity, _flash()));
            _arenaControl = arenaControl ?? (request => JObject.Parse(arena.HandleControl(request)));
            _windowObservation = windowObservation;
            _performanceObservation = performanceObservation;
            _queueShutdown = queueShutdown ?? (work => { ThreadPool.QueueUserWorkItem(_ => work()); });
        }

        internal JObject Handle(JObject request)
        {
            lock (_gate)
            {
                try
                {
                    if (ArenaRunIdentity.ReadId(request, "workerId") != _policy.WorkerId
                        || ArenaRunIdentity.ReadId(request, "sessionEpoch") != _policy.SessionEpoch)
                        return Error("worker_session_mismatch");
                    string action = request.Value<string>("action");
                    var allowed = new HashSet<string>(StringComparer.Ordinal) { "action", "workerId", "sessionEpoch" };
                    bool attemptAction = action == "startBatch" || action == "abort" || action == "result" || action == "faultStopFlash";
                    if (attemptAction) { allowed.Add("assignmentId"); allowed.Add("attemptId"); }
                    if (action == "startBatch") { allowed.Add("manifestPath"); allowed.Add("batchId"); allowed.Add("manifestHash"); }
                    if (action == "faultStopFlash")
                    {
                        foreach (string key in ArenaRunIdentity.Keys) allowed.Add(key);
                        allowed.Add("faultId");
                    }
                    foreach (JProperty property in request.Properties())
                        if (!allowed.Contains(property.Name)) return Error("worker_field_forbidden");
                    if (attemptAction)
                    {
                        ArenaRunIdentity.ReadId(request, "assignmentId");
                        ArenaRunIdentity.ReadId(request, "attemptId");
                    }
                    JObject arena = ArenaStatus();
                    if ((action == "abort" || action == "result")
                        && (request.Value<string>("assignmentId") != arena.Value<string>("assignmentId")
                            || request.Value<string>("attemptId") != arena.Value<string>("attemptId")))
                        return Error("worker_attempt_mismatch");
                    if (_shutdownRequested && action != "status" && action != "result")
                        return Error("worker_shutting_down");
                    switch (action)
                    {
                        case "start":
                            if (_startRequested) return Error("worker_start_already_requested");
                            _startRequested = true;
                            var started = JObject.Parse(_agent.Handle(new JObject {
                                ["action"] = "start", ["slot"] = _policy.Slot, ["fresh"] = false,
                                ["rememberSlot"] = false, ["deferReveal"] = false, ["requireFlashReveal"] = true
                            }));
                            return Wrap(started.Value<bool?>("success") == true, started, ArenaStatus());
                        case "startBatch":
                            JObject agent = AgentStatus();
                            if (agent.Value<bool?>("readyForRuntimeAutomation") != true
                                || agent.SelectToken("save.slot")?.Value<string>() != _policy.Slot
                                || agent.SelectToken("saveRuntime.savePath")?.Value<string>() != _policy.Slot)
                                return Error("worker_runtime_not_ready");
                            if (request["manifestPath"]?.Type != JTokenType.String
                                || request["batchId"]?.Type != JTokenType.String
                                || request["manifestHash"]?.Type != JTokenType.String)
                                return Error("worker_manifest_binding_required");
                            JObject start = (JObject)request.DeepClone();
                            start["action"] = "startBatch";
                            JObject accepted = _arenaControl(start);
                            return Wrap(accepted.Value<bool?>("success") == true, agent, accepted);
                        case "abort":
                            JObject aborted = _arenaControl(request);
                            return Wrap(aborted.Value<bool?>("success") == true, AgentStatus(), aborted);
                        case "status":
                        case "result":
                            return Wrap(true, AgentStatus(), arena);
                        case "faultStopFlash":
                            if (!_policy.AllowFaultInjection || _arena == null) return Error("worker_fault_not_enabled");
                            ArenaRunIdentity.ReadId(request, "faultId");
                            using (IArenaWorkerFaultProcess held = _faultProcess(_arena.CaptureFaultProcessIdentity()))
                            {
                                JObject fault = _arena.FaultStopFlash(request, held);
                                return Wrap(fault.Value<bool?>("success") == true, AgentStatus(), fault);
                            }
                        case "shutdown":
                            _shutdownRequested = true;
                            JObject response = Wrap(true, AgentStatus(), arena);
                            // Admission closes immediately, but only the HTTP writer can commit exit.
                            _shutdownResponse = response;
                            _shutdownArena = arena;
                            return response;
                        default: return Error("worker_action_forbidden");
                    }
                }
                catch (Exception ex)
                {
                    return Error("worker_request_invalid", ex.Message);
                }
            }
        }

        internal void ResponseWritten(JObject response)
        {
            JObject arena;
            lock (_gate)
            {
                // A copied or unrelated response is not this request's writer receipt.
                if (_shutdownResponse == null || !ReferenceEquals(_shutdownResponse, response)) return;
                arena = _shutdownArena;
                _shutdownResponse = null;
                _shutdownArena = null;
            }
            LogManager.Log("event=arena_worker_shutdown_response_written worker=" + _policy.WorkerId
                + " session=" + _policy.SessionEpoch);
            _queueShutdown(() => {
                _arenaControl(new JObject { ["action"] = "abort", ["workerId"] = _policy.WorkerId,
                    ["sessionEpoch"] = _policy.SessionEpoch, ["assignmentId"] = arena["assignmentId"],
                    ["attemptId"] = arena["attemptId"] });
                var drain = Stopwatch.StartNew();
                while (ArenaStatus().Value<string>("state") == "running" && drain.ElapsedMilliseconds < 2000) Thread.Sleep(10);
                LogManager.Log("event=arena_worker_shutdown_commit worker=" + _policy.WorkerId
                    + " session=" + _policy.SessionEpoch);
                _shutdown();
            });
        }

        private JObject AgentStatus() => JObject.Parse(_agent.Handle(new JObject { ["action"] = "status" }));
        private JObject ArenaStatus() => _arenaControl(new JObject { ["action"] = "status" });
        private JObject Wrap(bool success, JObject agent, JObject arena)
        {
            JObject flash = ArenaWorkerPolicy.DescribeProcess(_flash());
            if (flash["pid"] != null && flash["processStartUtcTicks"] != null && flash["processPath"] != null)
                _lastFlashIdentity = flash;
            using Process host = Process.GetCurrentProcess();
            var result = new JObject {
                ["success"] = success, ["ok"] = success, ["executionMode"] = "arena_worker",
                ["workerId"] = _policy.WorkerId, ["sessionEpoch"] = _policy.SessionEpoch,
                ["assignmentId"] = arena?["assignmentId"]?.DeepClone(), ["attemptId"] = arena?["attemptId"]?.DeepClone(),
                ["runtimeIdentity"] = _policy.RuntimeIdentity?.DeepClone(),
                ["performance"] = _policy.Performance.ToJson(),
                ["agentStatus"] = agent, ["arenaStatus"] = arena,
                ["resultPath"] = arena?["resultPath"]?.DeepClone(),
                ["frozenManifestPath"] = arena?["frozenManifestPath"]?.DeepClone(),
                ["flashProcess"] = _lastFlashIdentity?.DeepClone(), ["flashProcessObservation"] = flash,
                ["hostProcessObservation"] = ArenaWorkerPolicy.DescribeProcess(host),
                ["shutdownRequested"] = _shutdownRequested
            };
            result["faultReceipt"] = arena?["faultReceipt"]?.DeepClone() ?? JValue.CreateNull();
            result["windowObservation"] = _windowObservation?.Invoke()
                ?? new JObject { ["observed"] = false, ["reason"] = "window_probe_not_configured" };
            result["performanceObservation"] = _performanceObservation?.Invoke()
                ?? new JObject { ["observed"] = false, ["reason"] = "performance_probe_not_configured" };
            if (!success)
            {
                JObject failed = arena?.Value<bool?>("success") == false ? arena : agent;
                result["error"] = failed?["error"]?.DeepClone();
                result["message"] = failed?["message"]?.DeepClone();
            }
            return result;
        }
        private JObject Error(string code, string message = null)
        {
            JObject result = Wrap(false, null, null);
            result["error"] = code;
            if (message != null) result["message"] = message;
            return result;
        }
    }
}
