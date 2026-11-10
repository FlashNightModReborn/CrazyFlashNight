using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Channels;
using System.Threading.Tasks;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Guardian
{
    // Opt-in qualification telemetry. Hot paths only update fixed counters or
    // bounded immutable identities; they never write logs or acquire the writer.
    internal enum Issue205Counter
    {
        Bytes, BytesCurrentAtRead, Nul, MessageCurrent, FPrefix, FNoConsumer, WorkerRejected,
        ConsumerEnter, ConsumerStopped, ConsumerGenerationRejected, ConsumerVisualDone,
        ConsumerDone, ConsumerException, FpsSection, FpsParsed, FpsInvalid,
        FpsSourceRejected, FpsPolicyRejected, FpsAccepted, F5Parsed, F5Accepted,
        F5Invalid, F5NegotiationRejected, F5LegacyRetired, F5OldGeneration, F5OldEpoch, F5OldSequence, F8Header, F8Cache,
        NativeBulletSubmit, Count
    }

    internal sealed class Issue205IncidentLatch
    {
        private readonly Dictionary<string, (long value, double at)> _progress = new();
        private string _context;
        private double _eligibleSince;
        private bool _wasEligible;
        internal JObject First { get; private set; }
        internal JObject Observe(double now, bool eligible, string context,
            double sourceAge, bool world, IReadOnlyDictionary<string, long> stages)
        {
            if (First != null) return First;
            if (!eligible) { _wasEligible = false; return null; }
            if (!_wasEligible || context != _context) {
                _context = context; _eligibleSince = now; _progress.Clear(); _wasEligible = true;
            }
            foreach (var stage in stages) {
                if (!_progress.TryGetValue(stage.Key, out var old) || old.value != stage.Value)
                    _progress[stage.Key] = (stage.Value, now);
            }
            if (now - _eligibleSince < 2000) return null;
            string reason = sourceAge > 2000 ? "root_http_pulse_silent" : !world ? "source_world_missing" : null;
            if (reason == null) foreach (var stage in stages) {
                if (now - _progress[stage.Key].at >= 2000) { reason = stage.Key + "_silent"; break; }
            }
            if (reason == null) return null;
            First = new JObject { ["monotonicMs"] = now, ["reason"] = reason,
                ["context"] = context, ["eligibleSinceMs"] = _eligibleSince,
                ["sourceAgeMs"] = sourceAge, ["diagnosis"] = "SUSPECT_ONLY" };
            return First;
        }
    }

    internal sealed class Issue205Probe
    {
        private static Issue205Probe _current;
        internal static Issue205Probe Current => Volatile.Read(ref _current);
        private readonly long[] _counters = new long[(int)Issue205Counter.Count];
        private readonly object _gate = new();
        private readonly Queue<JObject> _ring = new();
        private readonly Issue205IncidentLatch _latch = new();
        private readonly Func<JObject> _hostState;
        private readonly Channel<(string name, string body)> _writes = Channel.CreateBounded<(string, string)>(
            new BoundedChannelOptions(256) { FullMode = BoundedChannelFullMode.Wait, SingleReader = true });
        private readonly string _directory;
        private readonly Timer _timer;
        private readonly double _deadline;
        private JObject _source, _latest, _first;
        private BulletVisualFrameIdentity _f5;
        private BulletVisualFrameIdentity _f5Accepted;
        private Issue205ChainIdentity _f8;
        private Issue205ChainIdentity _f8Cache;
        private Issue205NativeIdentity _native;
        private Issue205ReadIdentity _read;
        private double _sourceAt;
        private long _sourceSequence, _samples, _dropped, _writerFaults;
        private int _sampling, _sealed;
        private static double Now => Stopwatch.GetTimestamp() * 1000.0 / Stopwatch.Frequency;

        internal static void Start(string root, Func<JObject> hostState)
        {
            if (Current != null) throw new InvalidOperationException("issue205_probe_already_started");
            var probe = new Issue205Probe(root, hostState);
            if (Interlocked.CompareExchange(ref _current, probe, null) != null)
                throw new InvalidOperationException("issue205_probe_already_started");
        }
        private Issue205Probe(string root, Func<JObject> hostState)
        {
            _hostState = hostState;
            _deadline = Now + TimeSpan.FromMinutes(80).TotalMilliseconds;
            _directory = Path.Combine(root, "tmp", "issue205-qualification",
                DateTime.UtcNow.ToString("yyyyMMddTHHmmssfffZ", CultureInfo.InvariantCulture) + "-" + Environment.ProcessId);
            Directory.CreateDirectory(_directory);
            _ = Task.Run(WriteLoop);
            _timer = new Timer(_ => Sample(), null, 1000, 1000);
        }
        internal bool Enabled => Now < _deadline && Volatile.Read(ref _sealed) == 0;
        internal void Hit(Issue205Counter counter, long amount = 1) => Interlocked.Add(ref _counters[(int)counter], amount);
        internal void Ordinary(BulletVisualFrameIdentity identity) => Volatile.Write(ref _f5, identity);
        internal void OrdinaryAccepted(BulletVisualFrameIdentity identity) => Volatile.Write(ref _f5Accepted, identity);
        internal void TransportRead(int generation, bool current, int bytes) {
            Hit(Issue205Counter.Bytes, bytes);
            if (current) Hit(Issue205Counter.BytesCurrentAtRead, bytes);
            Volatile.Write(ref _read, new Issue205ReadIdentity(generation,current,bytes,Now));
        }
        internal void Chain(int generation, int epoch, int sequence, int tick) {
            Hit(Issue205Counter.F8Header);
            Volatile.Write(ref _f8, new Issue205ChainIdentity(generation, epoch, sequence, tick));
        }
        internal void Native(int epoch, int frame, int chainEpoch, int chainTick) {
            Hit(Issue205Counter.NativeBulletSubmit);
            Volatile.Write(ref _native, new Issue205NativeIdentity(epoch, frame, chainEpoch, chainTick));
        }
        internal void ChainCache(int generation,int epoch,int sequence,int tick) {
            Hit(Issue205Counter.F8Cache);
            Volatile.Write(ref _f8Cache,new Issue205ChainIdentity(generation,epoch,sequence,tick));
        }

        // Each LoadVars request carries a newly sampled root clock and sequence.
        // This channel does not consume frameUpdate/frameEnd or XMLSocket.
        internal bool ReceiveSource(IReadOnlyDictionary<string, string> fields)
        {
            if (!Enabled || !fields.TryGetValue("seq", out string raw)
                || !long.TryParse(raw, NumberStyles.None, CultureInfo.InvariantCulture, out long seq) || seq < 1) return false;
            var source = new JObject();
            foreach (string name in SourceFields) {
                if (!fields.TryGetValue(name, out string value) || value == null || value.Length > 1024) return false;
                source[name] = value;
            }
            lock (_gate) {
                if (seq <= _sourceSequence) return false;
                _sourceSequence = seq; _source = source; _sourceAt = Now;
            }
            return true;
        }
        internal static readonly string[] SourceFields = { "seq", "timer", "world", "owner", "attach", "unload", "dispose",
            "gameFrame", "serverFrame", "battle", "paused", "transition", "scene", "counts", "order" };
        private void Sample()
        {
            if (!Enabled || Interlocked.Exchange(ref _sampling, 1) != 0) return;
            try {
                JObject host = _hostState();
                double now = Now;
                JObject row;
                lock (_gate) {
                    var counters = new JObject();
                    for (int i = 0; i < (int)Issue205Counter.Count; i++) counters[((Issue205Counter)i).ToString()] = Interlocked.Read(ref _counters[i]);
                    row = new JObject { ["schema"] = "cf7.issue205.probe.v1", ["utc"] = DateTime.UtcNow,
                        ["monotonicMs"] = now, ["sample"] = ++_samples, ["pid"] = Environment.ProcessId,
                        ["sourceAgeMs"] = _source == null ? null : now - _sourceAt,
                        ["source"] = _source?.DeepClone(), ["host"] = host,
                        ["counters"] = counters, ["f5"] = Volatile.Read(ref _f5)?.Json(), ["f8"] = Volatile.Read(ref _f8)?.Json(),
                        ["f5Accepted"] = Volatile.Read(ref _f5Accepted)?.Json(),
                        ["f8Cache"] = Volatile.Read(ref _f8Cache)?.Json(), ["lastByteRead"] = Volatile.Read(ref _read)?.Json(),
                        ["nativeSubmission"] = Volatile.Read(ref _native)?.Json(), ["droppedWrites"] = Interlocked.Read(ref _dropped),
                        ["writerFaults"] = Interlocked.Read(ref _writerFaults) };
                    if (_source != null) {
                        bool eligible = (string)_source["battle"] == "1" && (string)_source["paused"] == "0"
                            && (string)_source["transition"] == "0" && host.Value<bool?>("foreground") == true;
                        var stages = new Dictionary<string, long>();
                        string[] values = ((string)_source["counts"] ?? "").Split(',');
                        string[] names = { "frameUpdate_enter", "frameUpdate_exit", "frameEnd_enter", "frameEnd_exit", "broadcaster_enter", "F_build", "F_send_enter", "F_send_exit", "fps_generated" };
                        for (int i = 0; i < names.Length && i < values.Length; i++)
                            if (long.TryParse(values[i], NumberStyles.None, CultureInfo.InvariantCulture, out long value)) stages[names[i]] = value;
                        stages["host_F_prefix"] = Interlocked.Read(ref _counters[(int)Issue205Counter.FPrefix]);
                        stages["host_consumer_done"] = Interlocked.Read(ref _counters[(int)Issue205Counter.ConsumerDone]);
                        if (host.Value<long?>("sourceSampleSequence") is long fpsSeq) stages["host_fps_source"] = fpsSeq;
                        JObject suspect = _latch.Observe(now, eligible,
                            (string)_source["owner"] + ":" + host["connectionGeneration"], now - _sourceAt,
                            (string)_source["world"] == "1", stages);
                        if (suspect != null && _first == null) {
                            _first = new JObject { ["incident"] = suspect.DeepClone(), ["trigger"] = row.DeepClone(),
                                ["pretrigger"] = new JArray(_ring.Select(r => r.DeepClone())) };
                            QueueWrite("first-suspect.json", _first);
                        }
                    }
                    _latest = row; _ring.Enqueue(row); while (_ring.Count > 180) _ring.Dequeue();
                }
                QueueWrite("samples.jsonl", row);
            }
            catch (Exception e) { QueueWrite("sampler-faults.jsonl", new JObject { ["utc"] = DateTime.UtcNow, ["type"] = e.GetType().Name }); }
            finally { Volatile.Write(ref _sampling, 0); }
        }
        internal JObject Snapshot(bool includeEvidence = false)
        {
            lock (_gate) return new JObject { ["enabled"] = Enabled, ["directory"] = _directory,
                ["latest"] = _latest?.DeepClone(), ["firstSuspect"] = _first == null ? null : includeEvidence ? _first.DeepClone() :
                    new JObject { ["incident"] = _first["incident"].DeepClone(), ["trigger"] = _first["trigger"].DeepClone(),
                        ["pretriggerCount"] = ((JArray)_first["pretrigger"]).Count },
                ["sealed"] = Volatile.Read(ref _sealed) != 0 };
        }
        internal void PreserveShutdownAttempt() {
            JObject retained = Snapshot(); retained["attemptUtc"] = DateTime.UtcNow;
            QueueWrite("shutdown-attempts.jsonl", retained);
        }
        internal void Seal(string reason)
        {
            if (Interlocked.Exchange(ref _sealed, 1) != 0) return;
            _timer.Dispose();
            // Retained 1Hz facts are sealed before downstream cleanup. No UI
            // screenshot/native grab, ordinary log lock, or writer wait here.
            JObject seal = Snapshot(); seal["reason"] = reason; seal["sealedUtc"] = DateTime.UtcNow;
            QueueWrite("sealed.json", seal); _writes.Writer.TryComplete();
        }
        private void QueueWrite(string name, JObject row) {
            if (!_writes.Writer.TryWrite((name, row.ToString(Formatting.None)))) Interlocked.Increment(ref _dropped);
        }
        private async Task WriteLoop()
        {
            await foreach (var write in _writes.Reader.ReadAllAsync()) try {
                string file = Path.Combine(_directory, write.name);
                if (write.name.EndsWith(".jsonl", StringComparison.Ordinal)) await File.AppendAllTextAsync(file, write.body + "\n");
                else await File.WriteAllTextAsync(file, write.body + "\n");
            } catch { Interlocked.Increment(ref _writerFaults); }
        }
    }

    internal sealed record BulletVisualFrameIdentity(int Generation, int Epoch, int SourceFrame, int SnapshotSequence, bool Q1)
    {
        internal JObject Json() => new JObject { ["generation"] = Generation, ["epoch"] = Epoch,
            ["sourceFrame"] = SourceFrame, ["snapshotSequence"] = Q1 ? SnapshotSequence : null,
            ["wire"] = Q1 ? "Q1" : "legacy", ["legacySequenceMeaning"] = Q1 ? null : "NOT_RECORDED; legacy aliases its source frame" };
    }
    internal sealed record Issue205ChainIdentity(int Generation, int Epoch, int Sequence, int Tick)
    {
        internal JObject Json() => new JObject { ["generation"] = Generation, ["epoch"] = Epoch,
            ["sequence"] = Sequence, ["tick"] = Tick, ["meaning"] = "header_seen; cache and native submission are separate" };
    }
    internal sealed record Issue205NativeIdentity(int Epoch, int SourceFrame, int ChainEpoch, int ChainTick)
    {
        internal JObject Json() => new JObject { ["epoch"] = Epoch, ["sourceFrame"] = SourceFrame,
            ["chainEpoch"] = ChainEpoch, ["chainTick"] = ChainTick,
            ["meaning"] = "native call returned success; not a presentation acknowledgement" };
    }
    internal sealed record Issue205ReadIdentity(int Generation,bool CurrentAtRead,int Bytes,double MonotonicMs)
    {
        internal JObject Json() => new JObject { ["generation"] = Generation, ["currentAtRead"] = CurrentAtRead,
            ["bytes"] = Bytes, ["monotonicMs"] = MonotonicMs,
            ["meaning"] = "read completion; current message admission is counted separately" };
    }
}
