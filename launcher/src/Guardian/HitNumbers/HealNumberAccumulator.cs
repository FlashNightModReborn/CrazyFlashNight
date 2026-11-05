using System;
using System.Collections.Generic;
using System.Drawing;

namespace CF7Launcher.Guardian.HitNumbers
{
    internal enum CombatNumberKind { Damage, HealHp }

    internal readonly record struct HealNumberEvent(
        string TargetId, double Amount, float WorldX, float WorldY);

    /// <summary>
    /// 固定150ms数值窗口与可见项的动画寿命分离。连续窗口复用同一条绿字，
    /// 不重置入场/抬升；小数在同一连续周期跨窗口结转，不进入伤害账本。
    /// </summary>
    internal sealed class HealNumberAccumulator
    {
        internal const double WindowSeconds = 0.15;
        internal const double LifetimeSeconds = HitNumberLayoutEngine.DefaultLifetimeSeconds;
        internal const int MaximumTargets = 512;
        private const double FadeSeconds = 0.25;
        private const double RecoverySeconds = 0.08;
        private readonly Dictionary<string, Window> _pending = new(StringComparer.Ordinal);
        private readonly Dictionary<string, VisibleNumber> _visible = new(StringComparer.Ordinal);
        private readonly List<string> _keys = new();
        private readonly List<VisibleNumber> _ordered = new();
        internal int PendingCount => _pending.Count;
        internal int VisibleCount => _visible.Count;
        internal bool HasState => _pending.Count != 0 || _visible.Count != 0;

        internal void Add(HealNumberEvent value, double now)
        {
            if (!(value.Amount > 0) || !double.IsFinite(value.Amount) ||
                string.IsNullOrEmpty(value.TargetId)) return;
            _pending.TryGetValue(value.TargetId, out Window window);
            if (window != null && now - window.LastInput >= LifetimeSeconds + WindowSeconds)
            {
                _pending.Remove(value.TargetId);
                window = null;
            }
            if (window != null && (now >= window.Due ||
                !double.IsFinite(window.Amount + value.Amount))) Publish(window, now);
            if (window == null)
            {
                if (_pending.Count >= MaximumTargets) FlushOldest(now);
                window = new Window { TargetId = value.TargetId };
                _pending.Add(value.TargetId, window);
            }
            if (double.IsPositiveInfinity(window.Due)) window.Due = now + WindowSeconds;
            window.Amount += value.Amount;
            window.WorldX = value.WorldX; window.WorldY = value.WorldY;
            window.LastInput = now;
            // 连续回复每帧给出坐标，不能等150ms数值窗口结束才移动锚点。
            if (_visible.TryGetValue(value.TargetId, out VisibleNumber visible))
            {
                visible.WorldX = value.WorldX; visible.WorldY = value.WorldY;
            }
        }

        internal void Advance(double now)
        {
            _keys.Clear();
            foreach (var pair in _pending)
                if (now >= pair.Value.Due ||
                    now - pair.Value.LastInput >= LifetimeSeconds + WindowSeconds) _keys.Add(pair.Key);
            foreach (string key in _keys)
            {
                Window window = _pending[key];
                if (now - window.LastInput >= LifetimeSeconds + WindowSeconds)
                    _pending.Remove(key);
                else
                {
                    Publish(window, now);
                    if (!(window.Amount > 0)) _pending.Remove(key);
                }
            }
            _keys.Clear();
            foreach (var pair in _visible)
                if (now - pair.Value.Published >= LifetimeSeconds) _keys.Add(pair.Key);
            foreach (string key in _keys) _visible.Remove(key);
            _keys.Clear();
        }

        internal void AppendFrame(HitNumberLayoutFrame frame, HitNumberCamera camera,
            double now, int rowLimit)
        {
            _ordered.Clear();
            foreach (VisibleNumber value in _visible.Values) _ordered.Add(value);
            _ordered.Sort((left, right) =>
            {
                int time = right.Published.CompareTo(left.Published);
                return time != 0 ? time : StringComparer.Ordinal.Compare(left.TargetId, right.TargetId);
            });
            int emitted = 0;
            for (int i = 0; i < _ordered.Count && (rowLimit == 0 || emitted < rowLimit); i++)
            {
                VisibleNumber value = _ordered[i];
                float x = camera.ToStageX(value.WorldX), y = camera.ToStageY(value.WorldY);
                if (x < -100 || x > HitNumberLayoutEngine.StageWidth + 100 ||
                    y < -100 || y > HitNumberLayoutEngine.StageHeight + 100) continue;
                double age = Math.Max(0, now - value.Born);
                var item = new HitNumberPaintItem
                {
                    Kind = CombatNumberKind.HealHp,
                    Value = value.Value,
                    StageX = Math.Clamp(x + 64, 65, HitNumberLayoutEngine.StageWidth - 65),
                    // 独立脚边通道：共享抬升曲线也不会顶进本目标的伤害栈。
                    StageY = y + 8 + HitNumberLayoutEngine.ImpactLift(age),
                    CombinedScale = HitNumberLayoutEngine.ImpactScale(age),
                    Packed = HitNumberPacking.Create(0, false, 20, 0),
                    Alpha = value.Opacity(now),
                    CombinedBlur = 2.8f,
                    MainColorOverride = Color.FromArgb(0x57, 0xE5, 0x90),
                    SourceSequence = -1,
                    SourceTargetId = value.TargetId,
                    SourceTargetX = x,
                    SourceTargetY = y
                };
                RectangleF bounds = HitNumberLayoutEngine.EstimateItemBounds(item);
                item.StageX += Math.Clamp(0, 4 - bounds.Left,
                    HitNumberLayoutEngine.StageWidth - 4 - bounds.Right);
                item.StageY += Math.Clamp(0, 4 - bounds.Top,
                    HitNumberLayoutEngine.StageHeight - 4 - bounds.Bottom);
                frame.Items.Add(item);
                emitted++;
            }
            _ordered.Clear();
        }

        internal void Clear()
        {
            _pending.Clear(); _visible.Clear(); _keys.Clear(); _ordered.Clear();
        }

        private void Publish(Window window, double now)
        {
            int amount = CombatNumberValue.ClampToInteger(window.Amount);
            // 只有不足1的尾数可以结转。已钳制的大数整批消费，不能凭空重复显示上限值。
            window.Amount = window.Amount >= int.MaxValue ? 0 : window.Amount - amount;
            double published = Math.Min(now, window.Due);
            window.Due = double.PositiveInfinity;
            if (amount <= 0) return;
            if (!_visible.TryGetValue(window.TargetId, out VisibleNumber value) ||
                now - value.Published >= LifetimeSeconds)
            {
                if (value == null && _visible.Count >= MaximumTargets) RetireOldest();
                value = new VisibleNumber { TargetId = window.TargetId, Born = published };
                _visible[window.TargetId] = value;
            }
            else value.RecoveryFrom = value.Opacity(now);
            // Born不随数值窗口重置；Published只续可见寿命与淡出，避免每150ms向下跳回。
            value.Value = amount;
            value.Published = published;
            value.RecoveryStarted = now;
            value.WorldX = window.WorldX; value.WorldY = window.WorldY;
        }

        private void RetireOldest()
        {
            string oldest = null; double time = double.PositiveInfinity;
            foreach (var pair in _visible)
                if (pair.Value.Published < time) { oldest = pair.Key; time = pair.Value.Published; }
            if (oldest != null) _visible.Remove(oldest);
        }

        private void FlushOldest(double now)
        {
            string oldest = null; double input = double.PositiveInfinity;
            foreach (var pair in _pending)
                if (pair.Value.LastInput < input) { oldest = pair.Key; input = pair.Value.LastInput; }
            if (oldest == null) return;
            Publish(_pending[oldest], now);
            _pending.Remove(oldest);
        }

        private sealed class Window
        {
            internal string TargetId;
            internal double Amount, LastInput, Due = double.PositiveInfinity;
            internal float WorldX, WorldY;
        }

        private sealed class VisibleNumber
        {
            internal string TargetId;
            internal int Value;
            internal double Born, Published, RecoveryStarted;
            internal float WorldX, WorldY, RecoveryFrom = 1;
            internal float Opacity(double now)
            {
                float fade = (float)Math.Clamp((LifetimeSeconds - (now - Published)) / FadeSeconds, 0, 1);
                float progress = (float)Math.Clamp((now - RecoveryStarted) / RecoverySeconds, 0, 1);
                return fade * (RecoveryFrom + (1 - RecoveryFrom) * progress);
            }
        }
    }
}
