using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Diagnostic
{
    // 仅在后台 Flush 中使用；四个固定片段与滚动日志共 22 MiB。
    internal sealed class FocusIncidentRecorder : IDisposable
    {
        internal const int SlotBytes = 1024 * 1024;
        internal static string[] Names => Enumerable.Range(0, 4).Select(i => "focus-incident." + i + ".log").ToArray();
        private readonly string _directory, _session;
        private readonly Queue<(long qpc, string line, int bytes)> _history = new Queue<(long, string, int)>();
        private readonly Dictionary<string, (long at, bool seen)> _pending = new Dictionary<string, (long, bool)>();
        private readonly List<Slot> _active = new List<Slot>();
        private int _historyBytes, _abnormal;
        private bool _normal;
        private long _lastIncident;
        private readonly long _started;
        private readonly Func<long> _clock;
        private long _historyDropped, _historyExpired, _pendingDropped;
        private sealed class Slot
        {
            internal StreamWriter writer;
            internal int bytes;
            internal long end;
        }
        internal FocusIncidentRecorder(string directory, string session, Func<long> clock = null)
        {
            _directory = directory;
            _session = session;
            _clock = clock ?? Stopwatch.GetTimestamp;
            _started = _clock();
        }
        private static double Age(long from, long to) => (to - from) * 1000.0 / Stopwatch.Frequency;
        internal void Append(string batch)
        {
            long now = _clock();
            var rows = new List<(long qpc, string line, JObject row)>();
            foreach (string line in batch.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries))
            {
                if (!line.StartsWith("[FocusTrace] ", StringComparison.Ordinal)) continue;
                try
                {
                    JObject row = JObject.Parse(line.Substring(13));
                    if ((string)row["session"] != _session) continue;
                    rows.Add(((long?)row["ticks"] ?? now, line, row));
                }
                catch { _historyDropped++; }
            }
            foreach (var entry in rows.OrderBy(x => x.qpc))
            {
                foreach (Slot slot in _active.ToArray()) Write(slot, entry.line);
                int bytes = Encoding.UTF8.GetByteCount(entry.line) + 1;
                if (bytes <= SlotBytes / 2)
                {
                    _history.Enqueue((entry.qpc, entry.line, bytes)); _historyBytes += bytes;
                }
                else _historyDropped++;
                while (_history.Count > 0 && (_historyBytes > SlotBytes / 2 || Age(_history.Peek().qpc, now) > 10000))
                {
                    bool capacity = _historyBytes > SlotBytes / 2;
                    var old = _history.Dequeue(); _historyBytes -= old.bytes;
                    if (capacity) _historyDropped++; else _historyExpired++;
                }
                if (Age(_started, now) > 60 * 60 * 1000) continue;
                string name = (string)entry.row["event"];
                JObject data = entry.row["data"] as JObject;
                string id = (string)data?["mouseId"];
                if (name == "mouse.down" && (bool?)data?["injected"] == false && id != null
                    && (bool?)data?["targetEligible"] == true && (double?)data?["cacheAgeMs"] <= 1000)
                {
                    if (_pending.Count < 128) _pending[id] = (entry.qpc, false);
                    else _pendingDropped++;
                }
                else if (name == "hud.down" && (int?)data?["candidateCount"] == 1 && id != null && _pending.TryGetValue(id, out var pending))
                {
                    double age = Age(pending.at, entry.qpc);
                    if (age >= 0 && age < 250 && !_normal) { Open(3, now, "normal_position_time_candidate"); _normal = true; }
                    // 位置时间候选不等于身份；有多个候选时不取消缺口记录。
                    _pending.Remove(id);
                    if (age >= 250) Trigger(now, "late_hud_position_time_candidate");
                }
                else if (name == "input.heartbeat_wait" && (double?)data?["elapsedMs"] >= 250)
                    Trigger(now, "posted_heartbeat_wait");
            }
            foreach (var pair in _pending.ToArray())
                if (Age(pair.Value.at, now) >= 250)
                { Trigger(now, "target_cache_input_gap_identity_unconfirmed"); _pending.Remove(pair.Key); }
            foreach (Slot slot in _active.ToArray())
            {
                if (now >= slot.end) { Write(slot, "[FocusIncident] end=window_complete"); slot.writer.Dispose(); _active.Remove(slot); }
                else slot.writer.Flush();
            }
        }
        private void Trigger(long now, string reason)
        {
            if (_abnormal >= 3 || Age(_started, now) > 60 * 60 * 1000 || (_lastIncident != 0 && Age(_lastIncident, now) < 15000)) return;
            Open(_abnormal++, now, reason); _lastIncident = now;
        }
        private void Open(int index, long now, string reason)
        {
            var slot = new Slot { writer = new StreamWriter(new FileStream(Path.Combine(_directory, Names[index]),
                FileMode.Create, FileAccess.Write, FileShare.ReadWrite | FileShare.Delete), new UTF8Encoding(false)) { NewLine = "\n" },
                end = now + Stopwatch.Frequency * 5 };
            _active.Add(slot);
            Write(slot, "[FocusIncident] " + new JObject { ["session"] = _session, ["reason"] = reason,
                ["triggerQpc"] = now, ["frequency"] = Stopwatch.Frequency, ["thresholdMs"] = 250,
                ["historyDropped"] = _historyDropped, ["historyExpired"] = _historyExpired,
                ["pendingDropped"] = _pendingDropped, ["targetProof"] = "cached_not_atomic",
                ["identity"] = "candidate_only", ["bytesLimit"] = SlotBytes }.ToString(Newtonsoft.Json.Formatting.None));
            foreach (var row in _history) Write(slot, row.line);
        }
        private static void Write(Slot slot, string line)
        {
            int bytes = Encoding.UTF8.GetByteCount(line) + 1;
            if (slot.bytes + bytes + 128 > SlotBytes)
            {
                if (slot.bytes <= SlotBytes - 128) { slot.writer.WriteLine("[FocusIncident] truncated=byte_budget"); slot.bytes = SlotBytes; }
                return;
            }
            slot.writer.WriteLine(line); slot.bytes += bytes;
        }
        public void Dispose()
        {
            foreach (Slot slot in _active) { Write(slot, "[FocusIncident] end=recording_stopped_post_window_may_be_short"); slot.writer.Dispose(); }
            _active.Clear();
        }
    }
}
