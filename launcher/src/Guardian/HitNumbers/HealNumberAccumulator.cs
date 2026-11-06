using System;
using System.Collections.Generic;

namespace CF7Launcher.Guardian.HitNumbers
{
    internal enum CombatNumberKind { Damage, HealHp }
    internal readonly record struct HealNumberEvent(string TargetId, double Amount, float WorldX, float WorldY);

    /// <summary>固定 150ms 数值窗口、小数结转与独立治疗周期。只输出类型化表现候选，不做布局。</summary>
    internal sealed class HealNumberAccumulator
    {
        internal const double WindowSeconds = 0.15;
        internal const double LifetimeSeconds = HitNumberLayoutEngine.DefaultLifetimeSeconds;
        internal const int MaximumTargets = 512;
        internal const int MaximumWindowEvents = MaximumTargets * 8;
        private readonly Dictionary<string, Window> _pending = new(StringComparer.Ordinal);
        private readonly Dictionary<string, CombatNumberVisualEvent> _visible = new(StringComparer.Ordinal);
        private readonly List<CombatNumberVisualEvent> _windows = new();
        private readonly List<CombatNumberVisualEvent> _ordered = new();
        private readonly List<string> _keys = new();
        private int _nextSequence;
        internal int PendingCount => _pending.Count;
        internal int VisibleCount => _visible.Count;
        internal int WindowEventCount => _windows.Count;
        internal bool HasState => _pending.Count != 0 || _visible.Count != 0 || _windows.Count != 0;

        internal void Add(HealNumberEvent value, double now)
        {
            if (!(value.Amount > 0) || !double.IsFinite(value.Amount) || string.IsNullOrEmpty(value.TargetId)) return;
            _pending.TryGetValue(value.TargetId, out Window window);
            if (window != null && now - window.LastInput >= LifetimeSeconds + WindowSeconds)
            {
                _pending.Remove(value.TargetId); window = null;
            }
            if (window != null && (now >= window.Due || !double.IsFinite(window.Amount + value.Amount))) Publish(window, now);
            if (window == null)
            {
                if (_pending.Count >= MaximumTargets) FlushOldest(now);
                CombatNumberTargetAnchor anchor = _visible.TryGetValue(value.TargetId, out var active) && now - active.Published < LifetimeSeconds
                    ? active.Anchor : new CombatNumberTargetAnchor(value.TargetId);
                window = new Window { TargetId = value.TargetId, Anchor = anchor };
                _pending.Add(value.TargetId, window);
            }
            if (double.IsPositiveInfinity(window.Due)) window.Due = now + WindowSeconds;
            window.Amount += value.Amount;
            window.LastInput = now;
            // 所有窗口共用实例锚点，逐帧跟随无需遍历历史窗口，也不分配伤害 Segment。
            window.Anchor.WorldX = value.WorldX; window.Anchor.WorldY = value.WorldY;
        }

        internal void Advance(double now)
        {
            _keys.Clear();
            foreach (var pair in _pending)
                if (now >= pair.Value.Due || now - pair.Value.LastInput >= LifetimeSeconds + WindowSeconds) _keys.Add(pair.Key);
            foreach (string key in _keys)
            {
                Window window = _pending[key];
                if (now - window.LastInput >= LifetimeSeconds + WindowSeconds) _pending.Remove(key);
                else { Publish(window, now); if (!(window.Amount > 0)) _pending.Remove(key); }
            }
            _keys.Clear();
            foreach (var pair in _visible)
                if (now - pair.Value.Published >= LifetimeSeconds) _keys.Add(pair.Key);
            foreach (string key in _keys) _visible.Remove(key);
            _keys.Clear();
            _windows.RemoveAll(value => now - value.Published >= LifetimeSeconds);
        }

        internal IReadOnlyList<CombatNumberVisualEvent> Snapshot(double now, bool individualWindows = false)
        {
            _ordered.Clear();
            if (individualWindows) _ordered.AddRange(_windows);
            else foreach (var value in _visible.Values) _ordered.Add(value);
            foreach (var value in _ordered) value.Alpha = value.Opacity(now);
            _ordered.Sort(CompareVisual);
            return _ordered;
        }

        private static int CompareVisual(CombatNumberVisualEvent left, CombatNumberVisualEvent right)
        {
            int time = left.Published.CompareTo(right.Published);
            return time != 0 ? time : left.Sequence.CompareTo(right.Sequence);
        }

        internal void Clear()
        {
            _pending.Clear(); _visible.Clear(); _windows.Clear(); _ordered.Clear(); _keys.Clear(); _nextSequence = 0;
        }

        private void Publish(Window window, double now)
        {
            int amount = CombatNumberValue.ClampToInteger(window.Amount);
            window.Amount = window.Amount >= int.MaxValue ? 0 : window.Amount - amount;
            double published = Math.Min(now, window.Due);
            window.Due = double.PositiveInfinity;
            if (amount <= 0) return;
            if (!_visible.TryGetValue(window.TargetId, out var value) || now - value.Published >= LifetimeSeconds)
            {
                if (value == null && _visible.Count >= MaximumTargets) RetireOldest();
                value = new CombatNumberVisualEvent { Anchor = window.Anchor, Born = published, Sequence = NextSequence() };
                _visible[window.TargetId] = value;
            }
            else value.RecoveryFrom = value.Opacity(now);
            value.Value = amount;
            value.TotalValue = (int)Math.Min(int.MaxValue, (long)value.TotalValue + amount);
            value.Published = published; value.RecoveryStarted = now;
            if (_windows.Count >= MaximumWindowEvents) _windows.RemoveAt(0);
            _windows.Add(new CombatNumberVisualEvent
            {
                Anchor = window.Anchor, Value = amount, TotalValue = amount,
                Born = published, Published = published, RecoveryStarted = now, Sequence = NextSequence()
            });
        }

        private int NextSequence() { if (_nextSequence == int.MaxValue) _nextSequence = 0; return _nextSequence++; }
        private void RetireOldest()
        {
            string oldest = null; double time = double.PositiveInfinity;
            foreach (var pair in _visible) if (pair.Value.Published < time) { oldest = pair.Key; time = pair.Value.Published; }
            if (oldest != null) _visible.Remove(oldest);
        }
        private void FlushOldest(double now)
        {
            string oldest = null; double time = double.PositiveInfinity;
            foreach (var pair in _pending) if (pair.Value.LastInput < time) { oldest = pair.Key; time = pair.Value.LastInput; }
            if (oldest == null) return;
            Publish(_pending[oldest], now); _pending.Remove(oldest);
        }
        private sealed class Window
        {
            internal string TargetId;
            internal CombatNumberTargetAnchor Anchor;
            internal double Amount, LastInput, Due = double.PositiveInfinity;
        }
    }
}
