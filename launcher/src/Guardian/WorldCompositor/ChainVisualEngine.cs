using System;
using System.Collections.Generic;

namespace CF7Launcher.Guardian.WorldCompositor
{
    /// <summary>Owns presentation units only. Consume every ordered F8 packet before render coalescing.</summary>
    internal sealed class ChainVisualEngine
    {
        private sealed class Unit
        {
            internal double X, Y, Sin, Cos, Rotation;
            internal Unit(ChainVisualFrame.UnitEvent item)
            { X = item.X; Y = item.Y; Sin = item.Sin; Cos = item.Cos; Rotation = item.Rotation; }
        }
        private sealed class Group
        {
            internal ChainVisualFrame.GroupState State;
            internal readonly Dictionary<int, Unit> Units = new();
            internal Group(ChainVisualFrame.GroupState state) { State = state; }
        }

        private readonly object _sync = new();
        private readonly Dictionary<int, Group> _groups = new();
        // Reused per-consume scratch; cleared at point of use so stale entries can
        // never leak across rejects/epochs. The returned array stays freshly
        // allocated: callers may hold it after Consume returns.
        private readonly Dictionary<int, ChainVisualFrame.GroupState> _desired = new();
        private readonly Dictionary<int, int> _counts = new();
        private readonly HashSet<(int Group, int Unit)> _eventIds = new();
        private readonly List<int> _absent = new();
        private readonly List<BulletVisualInstance> _draws = new();
        private int _generation = -1, _epoch = -1, _sequence, _tick = -1;
        private bool _needsResync;
        internal bool NeedsResync { get { lock (_sync) return _needsResync; } }
        internal int Epoch { get { lock (_sync) return _epoch; } }

        internal BulletVisualInstance[] Consume(int generation, string payload, int styleCount)
        {
            lock (_sync)
            {
                if (generation < 0 || generation < _generation) return null;
                if (generation > _generation)
                {
                    Clear();
                    _generation = generation;
                }
                if (!ChainVisualFrame.TryReadHeader(payload, out int epoch, out int sequence, out int tick))
                    return Reject();
                if (epoch < _epoch || (epoch == _epoch && sequence <= _sequence)) return null;
                bool newEpoch = epoch > _epoch;
                if (!newEpoch && (_needsResync || sequence != _sequence + 1 || tick < _tick)) return Reject();
                if (!ChainVisualFrame.TryParse(payload, styleCount, out var frame)) return Reject();
                if (newEpoch)
                {
                    _groups.Clear();
                    _epoch = epoch;
                    _sequence = 0;
                    _tick = -1;
                    _needsResync = false;
                }

                // Validate against existing state first. Event identities are unique
                // per packet; the AS2 producer cancels unsent birth/death pairs.
                var desired = _desired;
                desired.Clear();
                var counts = _counts;
                counts.Clear();
                foreach (var state in frame.Groups)
                {
                    desired.Add(state.Id, state);
                    int count = 0;
                    if (_groups.TryGetValue(state.Id, out var previous))
                    {
                        if (state.Style != previous.State.Style
                            || (state.Step != previous.State.Step && state.Step != previous.State.Step + 1))
                            return Reject();
                        count = previous.Units.Count;
                    }
                    counts.Add(state.Id, count);
                }
                var eventIds = _eventIds;
                eventIds.Clear();
                foreach (var item in frame.Events)
                {
                    if (!eventIds.Add((item.Group, item.Id))) return Reject();
                    bool exists = _groups.TryGetValue(item.Group, out var group) && group.Units.ContainsKey(item.Id);
                    if (item.Birth ? exists : !exists) return Reject();
                    counts[item.Group] += item.Birth ? 1 : -1;
                }
                int total = 0;
                foreach (int count in counts.Values)
                {
                    // A live logical chain always retains at least one unit.
                    if (count < 1 || count > ChainVisualFrame.MaxUnits) return Reject();
                    total += count;
                    if (total > ChainVisualFrame.MaxUnits) return Reject();
                }

                var absent = _absent;
                absent.Clear();
                foreach (int id in _groups.Keys) if (!desired.ContainsKey(id)) absent.Add(id);
                foreach (int id in absent) _groups.Remove(id);
                foreach (var state in frame.Groups)
                {
                    if (!_groups.TryGetValue(state.Id, out var group))
                    {
                        group = new Group(state);
                        _groups.Add(state.Id, group);
                    }
                    else if (state.Step != group.State.Step)
                    {
                        foreach (var unit in group.Units.Values)
                        {
                            double dy = state.Advance * unit.Sin;
                            unit.Y += dy;
                            if (state.AdvanceX)
                            {
                                double dx = state.Advance * unit.Cos;
                                unit.X += dx;
                            }
                        }
                    }
                    group.State = state;
                }
                foreach (var item in frame.Events)
                {
                    var group = _groups[item.Group];
                    if (item.Birth) group.Units.Add(item.Id, new Unit(item));
                    else group.Units.Remove(item.Id);
                }
                _sequence = frame.Sequence;
                _tick = frame.Tick;
                var draws = _draws;
                draws.Clear();
                if (draws.Capacity < total) draws.Capacity = total;
                foreach (var state in frame.Groups)
                {
                    if (!state.Visible || state.Alpha <= 0) continue;
                    var group = _groups[state.Id];
                    double radians = state.Rotation * (Math.PI / 180);
                    double cos = Math.Cos(radians), sin = Math.Sin(radians);
                    double sx = state.ScaleX * .01, sy = state.ScaleY * .01;
                    double ma = sx * cos, mb = sx * sin, mc = -sy * sin, md = sy * cos;
                    bool mirrored = !(sx > 0 && sy > 0);
                    foreach (var unit in group.Units.Values)
                    {
                        double rotation = mirrored
                            ? Math.Atan2(mb * unit.Cos + md * unit.Sin, ma * unit.Cos + mc * unit.Sin) * (180 / Math.PI)
                            : state.Rotation + unit.Rotation;
                        draws.Add(new BulletVisualInstance(state.Style,
                            (float)(state.X + ma * unit.X + mc * unit.Y),
                            (float)(state.Y + mb * unit.X + md * unit.Y),
                            (float)rotation, (float)state.ScaleX, (float)state.ScaleY, (float)state.Alpha));
                    }
                }
                return draws.ToArray();
            }
        }

        private BulletVisualInstance[] Reject()
        {
            _groups.Clear();
            _needsResync = true;
            return Array.Empty<BulletVisualInstance>();
        }

        private void Clear()
        {
            _groups.Clear();
            _generation = -1;
            _epoch = -1;
            _sequence = 0;
            _tick = -1;
            _needsResync = false;
        }

        internal void Reset() { lock (_sync) Clear(); }
        internal void ResetIfGeneration(int generation)
        {
            lock (_sync)
            {
                if (generation != _generation) return;
                _groups.Clear();
                // Keep the last epoch and sequence as a stale-packet barrier.
                _needsResync = true;
            }
        }
    }
}