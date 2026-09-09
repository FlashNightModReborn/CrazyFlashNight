using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Threading;
using Newtonsoft.Json;

namespace CF7Launcher.Diagnostic
{
    // 输入探针的固定容量快速路径。锁内仅复制值，不查询窗口、不格式化、不调用原生链。
    internal sealed class FocusInputBuffer
    {
        internal const int Capacity = 2048;
        private readonly object _gate = new object();
        private readonly InputRow[] _rows = new InputRow[Capacity];
        private int _head, _count, _highWater;
        private long _dropped;

        internal void Add(InputRow row)
        {
            if (!Monitor.TryEnter(_gate)) { Interlocked.Increment(ref _dropped); return; }
            try
            {
                if (_count == Capacity) { Interlocked.Increment(ref _dropped); return; }
                _rows[(_head + _count) % Capacity] = row;
                _count++;
                _highWater = Math.Max(_highWater, _count);
            }
            finally { Monitor.Exit(_gate); }
        }

        internal List<string> Drain(string session)
        {
            InputRow[] rows;
            int highWater;
            lock (_gate)
            {
                rows = new InputRow[_count];
                for (int i = 0; i < rows.Length; i++)
                {
                    rows[i] = _rows[_head];
                    _rows[_head] = default;
                    _head = (_head + 1) % Capacity;
                }
                _count = 0;
                highWater = _highWater;
            }
            var lines = new List<string>(rows.Length + 1);
            long lost = Interlocked.Exchange(ref _dropped, 0);
            if (lost != 0) lines.Add("[FocusTrace] " + JsonConvert.SerializeObject(new {
                v = 2, session, @event = "input.dropped", count = lost, highWater, capacity = Capacity }));
            foreach (InputRow row in rows)
                lines.Add("[FocusTrace] " + JsonConvert.SerializeObject(new {
                    v = 2, session, seq = row.sequence, utc = row.utc.ToString("O"),
                    ticks = row.qpc, frequency = Stopwatch.Frequency, tid = row.managedTid,
                    nativeTid = row.nativeTid, @event = row.name, gesture = row.gesture,
                    data = row.data, flushedAtUtc = DateTime.UtcNow.ToString("O") }));
            return lines;
        }
    }

    internal struct InputRow
    {
        internal string name, gesture;
        internal long sequence, qpc;
        internal DateTime utc;
        internal int managedTid;
        internal uint nativeTid;
        internal InputData data;
    }

    // 此结构的字符串仅取固定标签或有界 ID。禁止放任意对象/委托/窗口快照。
    internal struct InputData
    {
        public string phase, mouseId, correlation, widget, coordinateSource;
        public long receiver, wParam, lParam, result, invocationId, generation, startedQpc;
        public int message, depth, candidateCount, panelGeneration, error;
        public uint messageTime, hookTime, flags, sendFlags, messagePos;
        public Point point;
        public bool injected, suppressed, targetEligible;
        public double elapsedMs, beforeNextMs, cacheAgeMs;
        public long nextHookResult;
    }

    internal sealed class FocusMouseHistory
    {
        internal const int Capacity = 128;
        internal const long RetentionMs = 10000;
        private struct Pair
        {
            internal string id;
            internal Point down, up;
            internal long at;
            internal bool hasUp;
        }
        private readonly Pair[] _pairs = new Pair[Capacity];
        private readonly object _gate = new object();
        private int _next, _active = -1;
        internal long Overwritten { get; private set; }
        internal string Edge(bool down, bool inTarget, Point point, string newId, long now)
        {
            lock (_gate)
            {
                if (down)
                {
                    _active = -1;
                    if (!inTarget) return null;
                    if (_pairs[_next].id != null && now - _pairs[_next].at <= RetentionMs) Overwritten++;
                    _active = _next;
                    _pairs[_next] = new Pair { id = newId, down = point, at = now };
                    _next = (_next + 1) % Capacity;
                    return newId;
                }
                if (_active < 0) return null;
                int index = _active;
                _active = -1;
                _pairs[index].up = point;
                _pairs[index].hasUp = true;
                return _pairs[index].id;
            }
        }
        internal string Candidate(Point point, long now, out int count)
        {
            lock (_gate)
            {
                count = 0;
                string id = null;
                foreach (Pair pair in _pairs)
                {
                    long age = now - pair.at;
                    if (pair.id == null || age < 0 || age > RetentionMs) continue;
                    if (pair.down != point && (!pair.hasUp || pair.up != point)) continue;
                    count++;
                    id = pair.id;
                }
                return count == 1 ? id : null;
            }
        }
    }
}
