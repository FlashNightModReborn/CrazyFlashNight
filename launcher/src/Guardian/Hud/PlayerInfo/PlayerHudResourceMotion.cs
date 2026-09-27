#nullable enable
using System;

namespace CF7Launcher.Guardian.Hud.PlayerInfo;

/// <summary>Presentation-only shield afterimages. Current fill always comes from the latest AS2 snapshot.</summary>
internal sealed class PlayerHudResourceMotion
{
    internal sealed class Channel
    {
        private bool _initialized;
        private double _maximum;
        private float _current;
        private int _lossAge = 1000;
        private int _gainAge = 1000;
        private float _trail;
        internal float Trail => Loss > 0 ? _trail : _current;
        internal float Loss => Math.Clamp(1 - _lossAge / 240f, 0, 1);
        internal float Gain => Math.Clamp(1 - _gainAge / 360f, 0, 1);
        internal bool Active => Loss > 0 || Gain > 0;

        internal void Observe(float current, double maximum, bool available)
        {
            if (!available) { Reset(); return; }
            if (!_initialized || maximum != _maximum)
            {
                Reset(); _initialized = true; _maximum = maximum; _current = current; return;
            }
            if (current < _current - 0.003f)
            {
                _trail = Math.Max(_current, Trail); _lossAge = 0; _gainAge = 1000;
            }
            else if (current > _current + 0.003f) _gainAge = 0;
            _current = current;
        }

        internal void Advance(int milliseconds)
        {
            _lossAge = (int)Math.Min(1000L, _lossAge + (long)milliseconds);
            _gainAge = (int)Math.Min(1000L, _gainAge + (long)milliseconds);
        }

        internal void Reset()
        {
            _initialized = false; _maximum = 0; _current = 0; _trail = 0;
            _lossAge = _gainAge = 1000;
        }
    }

    internal Channel Shield { get; } = new();
    internal bool Active => Shield.Active;
    internal static float ShieldFraction(PlayerHudVitals v) => v.ShieldReady && v.ShieldPresent && v.ShieldMax > 0
        ? (float)Math.Clamp(v.Shield / v.ShieldMax, 0, 1) : 0;
    internal static float OverflowFraction(PlayerHudVitals v) => v.HpMax > 0
        ? (float)Math.Clamp((v.Hp - v.HpMax) / v.HpMax, 0, 1) : 0;

    internal void Observe(PlayerHudVitals? value)
    {
        if (value is not { } v) { Reset(); return; }
        Shield.Observe(ShieldFraction(v), v.ShieldMax, v.ShieldReady && v.ShieldPresent && v.ShieldMax > 0);
    }
    internal void Advance(int milliseconds) => Shield.Advance(milliseconds);
    internal void Reset() => Shield.Reset();
}

/// <summary>Only decorative sampling degrades; authority updates and short event feedback bypass it.</summary>
internal sealed class PlayerHudDecorationBudget
{
    private int _warmup;
    private int _slow;
    private int _fast;
    internal int FrameStride { get; private set; } = 1;

    internal void Observe(double surfaceMilliseconds)
    {
        if (!double.IsFinite(surfaceMilliseconds) || surfaceMilliseconds < 0) return;
        if (_warmup++ < 15) return;
        _slow = surfaceMilliseconds > 8 ? _slow + 1 : 0;
        _fast = surfaceMilliseconds < 4 ? _fast + 1 : 0;
        if (_slow >= 30) { FrameStride = 2; _slow = 0; }
        if (_fast >= 120) { FrameStride = 1; _fast = 0; }
    }
    internal void Reset() { _warmup = _slow = _fast = 0; FrameStride = 1; }
}
