using System;
using System.Linq;
using System.Text;
using System.Threading;
using CF7Launcher.Bus;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.ArenaWorker;

internal sealed class WorkerProjectionNegotiator : IDisposable
{
    private readonly object _gate = new();
    private readonly ArenaWorkerPolicy _worker;
    private readonly JObject _payload;
    private readonly Func<string, int, bool> _send;
    private readonly Action<string, int> _fault;
    private readonly Func<DateTime> _now;
    private readonly Func<bool> _clean;
    private readonly Func<bool> _startupReady;
    private readonly Timer _timer;
    private int _generation, _latestGeneration, _messages, _bytes;
    private string _contract, _state = "not_connected", _failure, _commit;
    private JObject _offer, _installed;
    private DateTime _deadline;
    internal WorkerProjectionNegotiator(ArenaWorkerPolicy worker, JObject bindings, Func<string, int, bool> send,
        Action<string, int> fault, Func<DateTime> now = null, bool startTimer = true, Func<bool> clean = null,
        Func<bool> startupReady = null)
    {
        if (worker.Projection == null) throw new ArgumentException("Projection requires a v2 Worker.");
        _worker = worker; _payload = worker.Projection.Payload(bindings); _send = send; _fault = fault;
        _now = now ?? (() => DateTime.UtcNow);
        _clean = clean ?? (() => true);
        _startupReady = startupReady ?? (() => true);
        if (startTimer) _timer = new Timer(_ => CheckTimeout(), null, 500, 500);
    }
    internal bool IsReady { get { lock (_gate) return _state == "committed"; } }
    internal bool IsNone(string consumer, int generation)
    { lock (_gate) return generation == _generation && _state == "committed" && _worker.Projection.IsNone(consumer); }
    internal JObject Status()
    {
        lock (_gate) return new JObject { ["state"] = _state, ["committed"] = _state == "committed",
            ["connectionGeneration"] = _generation, ["contractId"] = _contract, ["failure"] = _failure,
            ["policy"] = _payload.DeepClone(), ["installReceipt"] = _installed?.DeepClone() };
    }
    internal void Ready(int generation)
    {
        lock (_gate)
        {
            if (generation < 1 || generation <= _latestGeneration || _failure != null) return;
            _generation = _latestGeneration = generation; _contract = Guid.NewGuid().ToString("N");
            _messages = _bytes = 0; _state = "waiting_startup"; _commit = null; _installed = null;
            _deadline = _now().AddSeconds(120);
        }
        TryOffer();
    }
    private void TryOffer()
    {
        if (!_startupReady()) return;
        string wire = null; int generation;
        lock (_gate)
        {
            if (_state != "waiting_startup" || _failure != null || _generation < 1) return;
            generation = _generation;
            if (_now() < _deadline) {
                _state = "offered"; _deadline = _now().AddSeconds(10);
                _offer = Message("worker_projection_offer", 1); wire = _offer.ToString(Formatting.None);
            }
        }
        if (wire == null) { Fail("worker_projection_timeout", generation); return; }
        if (!_send(wire + "\0", generation)) Fail("worker_projection_offer_send_failed", generation);
    }
    internal void Disconnected(int generation)
    {
        lock (_gate)
        {
            if (generation != _generation) return;
            _state = "retired"; _generation = 0; _installed = null;
            // A policy change or unknown installation outcome requires a new Worker process.
            _failure ??= "worker_projection_transport_lost";
        }
    }
    internal string Prepared(JObject received, int generation)
    {
        if (!Current(received, generation)) return null;
        JObject expected; bool offered;
        lock (_gate)
        {
            if (_failure != null) return null;
            offered = _offer != null && (_state == "offered" || _state == "commit_sent" || _state == "committed");
            expected = Message("worker_projection_prepared", 1); expected["accepted"] = true; expected["clean"] = true;
        }
        if (!offered) { Fail("worker_projection_prepared_out_of_phase", generation); return null; }
        if (!ExactValues(received, expected)) { Fail("worker_projection_prepared_invalid", generation); return null; }
        lock (_gate) if (generation == _generation && _failure == null && _commit != null) return _commit;
        if (!_clean()) { Fail("worker_projection_host_not_clean", generation); return null; }
        lock (_gate)
        {
            if (generation != _generation || _failure != null) return null;
            if (_commit != null) return _commit;
            if (!Admit(received)) { /* fail outside this lock */ }
            else
            {
                JObject commit = Message("worker_projection_commit", 2);
                commit["policyDigest"] = WorkerProjectionPolicy.Digest(_payload);
                _commit = commit.ToString(Formatting.None); _state = "commit_sent";
                return _commit;
            }
        }
        Fail("worker_projection_control_budget", generation); return null;
    }
    internal string Committed(JObject received, int generation)
    {
        if (!Current(received, generation)) return null;
        bool installed;
        lock (_gate) installed = _installed != null;
        if (!installed && !_clean()) { Fail("worker_projection_host_not_clean", generation); return null; }
        bool valid;
        lock (_gate)
        {
            if (_failure != null) return null;
            JObject expected = Message("worker_projection_committed", 2);
            expected["policyDigest"] = WorkerProjectionPolicy.Digest(_payload);
            expected["installClockKind"] = "flashRootEnterFrame";
            JObject policy = (JObject)received.DeepClone();
            policy.Remove("installEpoch"); policy.Remove("installTick");
            valid = _commit != null && received.Count == expected.Count + 2 && ExactValues(policy, expected)
                && WorkerProjectionPolicy.Integer(received["installEpoch"], 1, 2147483647, out _)
                && WorkerProjectionPolicy.Integer(received["installTick"], 1, 2147483647, out _);
            if (valid && _installed != null)
                valid = JToken.DeepEquals(received, _installed);
            if (valid && _installed == null)
            {
                valid = Admit(received);
                if (valid) { _installed = (JObject)received.DeepClone(); _state = "committed"; }
            }
        }
        if (!valid) Fail("worker_projection_committed_invalid", generation);
        return null;
    }
    internal string Rejected(JObject received, int generation)
    {
        if (Current(received, generation)) Fail("worker_projection_rejected", generation);
        return null;
    }
    internal bool ObserveForbidden(string consumer, string payload, int generation)
    {
        if (payload == null || !IsNone(consumer, generation)) return false;
        Fail("unexpected_projection_after_none:" + consumer, generation); return true;
    }
    internal bool ObserveCombatDecorations(string payload, int generation)
    {
        if (payload == null || !IsNone("combatDecoration", generation)) return false;
        for (int separator = payload.IndexOf(';'); separator >= 0; separator = payload.IndexOf(';', separator + 1))
            if (separator + 2 >= payload.Length || payload[separator + 1] != 'l' || payload[separator + 2] != ',')
            { Fail("unexpected_projection_after_none:combatDecoration", generation); return true; }
        return false; // F6 source clock and resident equipment lights still require their normal parser.
    }
    internal void CheckTimeout()
    {
        TryOffer();
        int generation;
        lock (_gate)
        {
            if ((_state != "waiting_startup" && _state != "offered" && _state != "commit_sent") || _now() < _deadline) return;
            generation = _generation;
        }
        Fail("worker_projection_timeout", generation);
    }
    private bool Current(JObject value, int generation)
    {
        lock (_gate) return generation > 0 && generation == _generation
            && value?["workerId"]?.Type == JTokenType.String && (string)value["workerId"] == _worker.WorkerId
            && value["sessionEpoch"]?.Type == JTokenType.String && (string)value["sessionEpoch"] == _worker.SessionEpoch
            && WorkerProjectionPolicy.Integer(value["connectionGeneration"], generation, generation, out _)
            && value["contractId"]?.Type == JTokenType.String && (string)value["contractId"] == _contract;
    }
    private bool Admit(JObject value)
    {
        int bytes = Encoding.UTF8.GetByteCount(value.ToString(Formatting.None));
        if (++_messages > 32 || bytes > 32768 || _bytes + bytes > 65536) return false;
        _bytes += bytes; return true;
    }
    private JObject Message(string task, int sequence)
    {
        var result = new JObject { ["task"] = task, ["version"] = 1, ["workerId"] = _worker.WorkerId,
            ["sessionEpoch"] = _worker.SessionEpoch, ["connectionGeneration"] = _generation,
            ["contractId"] = _contract, ["sequence"] = sequence };
        foreach (JProperty property in _payload.Properties()) result[property.Name] = property.Value.DeepClone();
        return result;
    }
    private static bool ExactValues(JObject value, JObject expected)
        => value != null && value.Count == expected.Count && expected.Properties().All(p => JToken.DeepEquals(value[p.Name], p.Value));
    private void Fail(string reason, int generation)
    {
        lock (_gate)
        {
            if (generation != _generation || generation < 1 || _failure != null) return;
            _failure = reason; _state = "failed"; _installed = null;
        }
        _fault?.Invoke(reason, generation);
    }
    public void Dispose() => _timer?.Dispose();
}
