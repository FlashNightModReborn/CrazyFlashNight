#nullable enable
using System;

namespace CF7Launcher.Guardian.Hud.PlayerInfo;

internal static class PlayerHudMotionSettings
{
    internal static bool ReducedMotion { get; set; } =
        Environment.GetEnvironmentVariable("CF7_HUD_REDUCED_MOTION") == "1";
}

/// <summary>Presentation-only shield afterimages and presence envelope. Current fill always comes from the latest AS2 snapshot.</summary>
internal sealed class PlayerHudResourceMotion
{
    internal const int AttackMilliseconds = 120;
    internal const int GraceMilliseconds = 360;
    internal const int ReleaseMilliseconds = 480;
    internal const int AbsentTotalMilliseconds = GraceMilliseconds + ReleaseMilliseconds;
    internal const int ReadoutThrottleMilliseconds = 100;
    internal const int ResistantTransitionMilliseconds = 180;
    internal const int EmptyTransitionMilliseconds = 220;
    internal const int CumulativeLossWindowMilliseconds = 260;
    internal const int BreakDurationMilliseconds = 240;
    internal const float DiscreteLossThreshold = 0.025f;

    private static float SmoothStep(float t)
    {
        t = Math.Clamp(t, 0f, 1f);
        return t * t * (3f - 2f * t);
    }

    internal sealed class Channel
    {
        private bool _initialized;
        private bool _available;
        private double _maximum;
        private double _rawCurrent;
        private float _current;
        private float _heldFraction;
        private float _layerStartFraction;
        private int _layerReleaseAge = AbsentTotalMilliseconds;
        private int _lossAge = 1000;
        private int _gainAge = 1000;
        private int _breakAge = BreakDurationMilliseconds;
        private float _windowLossSum;
        private float _windowLossAnchor;
        private int _windowLossAge = CumulativeLossWindowMilliseconds;
        private float _trail;
        private float _presence;
        private float _releaseStartPresence = 1f;
        private int _absenceAge = AbsentTotalMilliseconds;
        private bool _attacking;

        internal float DisplayFraction => !_available && _presence > 0f
            ? _heldFraction
            : HoldingLayer
                ? _layerReleaseAge < GraceMilliseconds
                    ? _layerStartFraction
                    : _layerStartFraction + (_current - _layerStartFraction) * SmoothStep((_layerReleaseAge - GraceMilliseconds) / (float)ReleaseMilliseconds)
                : _current;
        internal float Trail => Loss > 0 ? _trail : DisplayFraction;
        internal float Loss => Math.Clamp(1 - _lossAge / 240f, 0, 1);
        internal float Gain => Math.Clamp(1 - _gainAge / 360f, 0, 1);
        internal float BreakPulse => Math.Clamp(1f - _breakAge / (float)BreakDurationMilliseconds, 0f, 1f);
        internal float Presence => _presence;
        internal bool InGraceOrRelease => !_available && _presence > 0f;
        internal bool HoldingLayer => _available && _layerReleaseAge < AbsentTotalMilliseconds;
        internal bool Active => Loss > 0 || Gain > 0 || BreakPulse > 0 || _attacking || InGraceOrRelease || HoldingLayer;

        internal void Observe(float current, double maximum, bool available, double rawCurrent = double.NaN, bool ready = true)
        {
            if (!ready) { Reset(); return; }
            if (!double.IsFinite(rawCurrent)) rawCurrent = current * maximum;
            if (!_initialized)
            {
                _initialized = true;
                _available = available;
                _maximum = available ? maximum : 0;
                _rawCurrent = available ? rawCurrent : 0;
                _current = available ? current : 0;
                _heldFraction = _current;
                _layerStartFraction = _current;
                _layerReleaseAge = AbsentTotalMilliseconds;
                _trail = _current;
                _presence = available ? 1f : 0f;
                _releaseStartPresence = _presence;
                _absenceAge = AbsentTotalMilliseconds;
                _attacking = false;
                return;
            }
            if (!available)
            {
                if (_available)
                {
                    _heldFraction = Math.Max(DisplayFraction, _current);
                    _available = false;
                    _layerReleaseAge = AbsentTotalMilliseconds;
                    _trail = _heldFraction;
                    _lossAge = _gainAge = 1000;
                    _windowLossSum = 0f;
                    _windowLossAge = CumulativeLossWindowMilliseconds;
                    _releaseStartPresence = Math.Max(0.25f, _presence);
                    _absenceAge = 0;
                    _attacking = false;
                }
                return;
            }
            if (!_available)
            {
                _available = true;
                _maximum = maximum;
                _rawCurrent = rawCurrent;
                _current = current;
                _heldFraction = current;
                _layerStartFraction = current;
                _layerReleaseAge = AbsentTotalMilliseconds;
                _trail = current;
                _lossAge = 1000;
                _breakAge = BreakDurationMilliseconds;
                _windowLossSum = 0f;
                _windowLossAge = CumulativeLossWindowMilliseconds;
                if (_absenceAge < GraceMilliseconds && _presence > 0f)
                {
                    _presence = 1f;
                    _attacking = false;
                    _absenceAge = AbsentTotalMilliseconds;
                    _gainAge = 1000;
                }
                else if (_presence > 0f)
                {
                    _presence = Math.Max(_presence, 0.45f);
                    _attacking = _presence < 1f;
                    _absenceAge = AbsentTotalMilliseconds;
                    _gainAge = 220;
                }
                else
                {
                    _presence = 0.35f;
                    _attacking = true;
                    _absenceAge = AbsentTotalMilliseconds;
                    _gainAge = 0;
                }
                return;
            }
            if (maximum != _maximum)
            {
                var prevMax = _maximum;
                var prevRaw = _rawCurrent;
                var prevDisplay = DisplayFraction;
                _maximum = maximum;
                _current = current;
                _rawCurrent = rawCurrent;
                _heldFraction = current;
                _windowLossSum = 0f;
                _windowLossAge = CumulativeLossWindowMilliseconds;

                var rawDrop = prevRaw - rawCurrent;
                var maxDrop = prevMax - maximum;
                var isLayerExpiration = maxDrop > 0.5 && rawDrop > 0.5 && rawDrop <= maxDrop + 0.5;
                if (isLayerExpiration && current < prevDisplay - 0.001f)
                {
                    _layerStartFraction = prevDisplay;
                    _layerReleaseAge = 0;
                    _trail = prevDisplay;
                    _lossAge = _gainAge = 1000;
                    return;
                }

                if (maximum > prevMax && current >= prevDisplay - 0.001f)
                {
                    _layerReleaseAge = AbsentTotalMilliseconds;
                }

                var droppedRaw = rawCurrent < prevRaw - 0.5 && !isLayerExpiration;
                if (droppedRaw && (current < prevDisplay - DiscreteLossThreshold || (current <= 0f && prevDisplay > 0.001f)))
                {
                    _layerReleaseAge = AbsentTotalMilliseconds;
                    _trail = Math.Max(prevDisplay, Trail);
                    _lossAge = 0;
                    _gainAge = 1000;
                    if (current <= 0f && prevDisplay > 0.001f) _breakAge = 0;
                }
                else if (Loss > 0)
                {
                    _trail = Math.Clamp(_trail, current, 1f);
                }
                return;
            }
            var drop = _current - current;
            if (drop > DiscreteLossThreshold || (current <= 0f && _current > 0.001f))
            {
                _layerReleaseAge = AbsentTotalMilliseconds;
                _trail = Math.Max(DisplayFraction, Trail);
                _windowLossAnchor = _trail;
                _windowLossSum = Math.Max(0f, _trail - current);
                _windowLossAge = 0;
                _lossAge = 0;
                _gainAge = 1000;
                if (current <= 0f && _current > 0.001f) _breakAge = 0;
            }
            else if (drop > 0.0005f)
            {
                if (_windowLossAge >= CumulativeLossWindowMilliseconds || _windowLossSum <= 0f)
                {
                    _windowLossAnchor = Math.Max(DisplayFraction, Trail);
                    _windowLossSum = drop;
                }
                else
                {
                    _windowLossSum += drop;
                }
                _windowLossAge = 0;
                if (_windowLossSum >= DiscreteLossThreshold || Loss > 0f)
                {
                    _layerReleaseAge = AbsentTotalMilliseconds;
                    _trail = Math.Max(_windowLossAnchor, Math.Max(DisplayFraction, Trail));
                    _lossAge = 0;
                    _gainAge = 1000;
                }
            }
            else if (current > _current + DiscreteLossThreshold)
            {
                if (current >= DisplayFraction) _layerReleaseAge = AbsentTotalMilliseconds;
                _gainAge = 0;
                _windowLossSum = 0f;
                _windowLossAge = CumulativeLossWindowMilliseconds;
            }
            else if (current > _current + 0.0005f)
            {
                _windowLossSum = 0f;
                _windowLossAge = CumulativeLossWindowMilliseconds;
            }
            _current = current;
            _heldFraction = current;
            _rawCurrent = rawCurrent;
        }

        internal void Advance(int milliseconds)
        {
            if (milliseconds <= 0) return;
            _lossAge = (int)Math.Min(1000L, _lossAge + (long)milliseconds);
            _gainAge = (int)Math.Min(1000L, _gainAge + (long)milliseconds);
            _breakAge = (int)Math.Min(BreakDurationMilliseconds, _breakAge + (long)milliseconds);
            _windowLossAge = (int)Math.Min(CumulativeLossWindowMilliseconds, _windowLossAge + (long)milliseconds);
            if (_windowLossAge >= CumulativeLossWindowMilliseconds) _windowLossSum = 0f;
            if (_attacking)
            {
                _presence = Math.Min(1f, _presence + milliseconds * 0.65f / AttackMilliseconds);
                if (_presence >= 1f) _attacking = false;
            }
            else if (!_available && _presence > 0f)
            {
                _absenceAge = (int)Math.Min(AbsentTotalMilliseconds, _absenceAge + (long)milliseconds);
                if (_absenceAge < GraceMilliseconds)
                {
                    _presence = _releaseStartPresence;
                }
                else if (_absenceAge < AbsentTotalMilliseconds)
                {
                    var t = (_absenceAge - GraceMilliseconds) / (float)ReleaseMilliseconds;
                    _presence = _releaseStartPresence * (1f - SmoothStep(t));
                }
                else
                {
                    _presence = 0f;
                    _current = 0f;
                    _heldFraction = 0f;
                    _rawCurrent = 0;
                    _trail = 0f;
                }
            }
            if (_available && _layerReleaseAge < AbsentTotalMilliseconds)
            {
                _layerReleaseAge = (int)Math.Min(AbsentTotalMilliseconds, _layerReleaseAge + (long)milliseconds);
            }
        }

        internal void Reset()
        {
            _initialized = false;
            _available = false;
            _maximum = 0;
            _rawCurrent = 0;
            _current = 0;
            _heldFraction = 0;
            _layerStartFraction = 0;
            _layerReleaseAge = AbsentTotalMilliseconds;
            _trail = 0;
            _presence = 0;
            _releaseStartPresence = 1f;
            _absenceAge = AbsentTotalMilliseconds;
            _attacking = false;
            _lossAge = _gainAge = 1000;
            _breakAge = BreakDurationMilliseconds;
            _windowLossSum = 0f;
            _windowLossAnchor = 0f;
            _windowLossAge = CumulativeLossWindowMilliseconds;
        }
    }

    private PlayerHudVitals? _lastPresentVitals;
    private bool _readoutInitialized;
    private double _displayShield;
    private double _latestShield;
    private double _readoutMax;
    private double _layerHeldShield;
    private double _layerHeldMax;
    private int _readoutAge;
    private bool _resistantInitialized;
    private bool _targetResistant;
    private float _resistantMix;
    private bool _emptyInitialized;
    private bool _targetEmpty;
    private float _emptyMix;

    internal Channel Shield { get; } = new();
    internal double DisplayShield => _displayShield;
    internal bool ResistantInitialized => _resistantInitialized;
    internal float ResistantMix => _resistantMix;
    internal bool EmptyInitialized => _emptyInitialized;
    internal float EmptyMix => _emptyMix;
    internal bool ReadoutPending => _readoutInitialized && Math.Abs(_displayShield - _latestShield) > 0.001;
    internal bool ResistantTransitionActive => _resistantInitialized && Math.Abs(_resistantMix - (_targetResistant ? 1f : 0f)) > 0.001f;
    internal bool EmptyTransitionActive => _emptyInitialized && Math.Abs(_emptyMix - (_targetEmpty ? 1f : 0f)) > 0.001f;
    internal bool Active => Shield.Active || ReadoutPending || ResistantTransitionActive || EmptyTransitionActive;

    internal static float ShieldFraction(PlayerHudVitals v) => v.ShieldReady && v.ShieldPresent && v.ShieldMax > 0
        ? (float)Math.Clamp(v.Shield / v.ShieldMax, 0, 1) : 0;
    internal static float OverflowFraction(PlayerHudVitals v) => v.HpMax > 0
        ? (float)Math.Clamp((v.Hp - v.HpMax) / v.HpMax, 0, 1) : 0;

    internal PlayerHudVitals ResolveShieldDisplay(PlayerHudVitals live)
    {
        if (!live.ShieldReady) return live;
        if (live.ShieldPresent && live.ShieldMax > 0)
        {
            if (Shield.HoldingLayer && _layerHeldMax > 0)
            {
                var mix = Math.Clamp(Shield.DisplayFraction, 0f, 1f);
                var currentFrac = ShieldFraction(live);
                var startFrac = _layerHeldMax > 0 ? (float)Math.Clamp(_layerHeldShield / _layerHeldMax, 0, 1) : 1f;
                var denom = Math.Abs(startFrac - currentFrac);
                var u = denom > 0.001f ? Math.Clamp((startFrac - mix) / denom, 0f, 1f) : 1f;
                var shieldVal = _layerHeldShield + (live.Shield - _layerHeldShield) * u;
                var maxVal = _layerHeldMax + (live.ShieldMax - _layerHeldMax) * u;
                return live with { Shield = shieldVal, ShieldMax = maxVal };
            }
            return _readoutInitialized ? live with { Shield = _displayShield } : live;
        }
        if (Shield.Presence > 0f && _lastPresentVitals is { } held)
        {
            var heldMax = _readoutInitialized && _readoutMax > 0 ? _readoutMax : held.ShieldMax;
            return held with { Shield = 0, ShieldMax = heldMax, ShieldReady = true, ShieldPresent = true };
        }
        return live;
    }

    internal void Observe(PlayerHudVitals? value)
    {
        if (value is not { } v) { Reset(); return; }
        var available = v.ShieldReady && v.ShieldPresent && v.ShieldMax > 0;
        var prevShield = _displayShield;
        var prevMax = _readoutMax;
        var wasInit = _readoutInitialized;
        var wasInGraceOrRelease = Shield.InGraceOrRelease;
        Shield.Observe(ShieldFraction(v), v.ShieldMax, available, v.Shield, v.ShieldReady);
        if (!v.ShieldReady)
        {
            _lastPresentVitals = null;
            _readoutInitialized = false;
            _resistantInitialized = false;
            _emptyInitialized = false;
            return;
        }
        if (available)
        {
            if (wasInit && Shield.HoldingLayer && v.ShieldMax < prevMax && prevShield > v.Shield)
            {
                _layerHeldShield = prevShield;
                _layerHeldMax = prevMax;
            }
            _lastPresentVitals = v;
            _latestShield = v.Shield;
            var discreteChange = !_readoutInitialized
                || wasInGraceOrRelease
                || v.Shield <= 0
                || v.Shield >= v.ShieldMax
                || v.ShieldMax != _readoutMax
                || Math.Abs(v.Shield - _displayShield) >= v.ShieldMax * DiscreteLossThreshold
                || _readoutAge >= ReadoutThrottleMilliseconds;
            if (discreteChange)
            {
                _displayShield = v.Shield;
                _readoutMax = v.ShieldMax;
                _readoutAge = 0;
                _readoutInitialized = true;
            }
            var resists = v.ShieldDetail?.ResistsBypass == true;
            _targetResistant = resists;
            if (!_resistantInitialized)
            {
                _resistantMix = resists ? 1f : 0f;
                _resistantInitialized = true;
            }
            var resolved = ResolveShieldDisplay(v);
            var isEmpty = resolved.Shield <= 0.001 && !Shield.HoldingLayer;
            _targetEmpty = isEmpty;
            if (!_emptyInitialized || wasInGraceOrRelease)
            {
                _emptyMix = isEmpty ? 1f : 0f;
                _emptyInitialized = true;
            }
        }
        else if (Shield.Presence > 0f)
        {
            _displayShield = 0;
            _latestShield = 0;
            _readoutAge = 0;
            _targetEmpty = true;
            _emptyMix = 1f;
            _emptyInitialized = true;
        }
        else
        {
            _lastPresentVitals = null;
            _readoutInitialized = false;
            _resistantInitialized = false;
            _emptyInitialized = false;
        }
    }

    internal void Advance(int milliseconds)
    {
        if (milliseconds <= 0) return;
        Shield.Advance(milliseconds);
        if (_readoutInitialized && Math.Abs(_displayShield - _latestShield) > 0.001)
        {
            _readoutAge += milliseconds;
            if (_readoutAge >= ReadoutThrottleMilliseconds)
            {
                _displayShield = _latestShield;
                _readoutAge = 0;
            }
        }
        if (_resistantInitialized)
        {
            var target = _targetResistant ? 1f : 0f;
            if (Math.Abs(_resistantMix - target) > 0.001f)
            {
                var step = milliseconds / (float)ResistantTransitionMilliseconds;
                _resistantMix = _resistantMix < target
                    ? Math.Min(target, _resistantMix + step)
                    : Math.Max(target, _resistantMix - step);
            }
        }
        if (_emptyInitialized)
        {
            if (_lastPresentVitals is { } live && live.ShieldPresent && !Shield.HoldingLayer && !Shield.InGraceOrRelease)
            {
                _targetEmpty = _displayShield <= 0.001;
            }
            var target = _targetEmpty ? 1f : 0f;
            if (Math.Abs(_emptyMix - target) > 0.001f)
            {
                var step = milliseconds / (float)EmptyTransitionMilliseconds;
                _emptyMix = _emptyMix < target
                    ? Math.Min(target, _emptyMix + step)
                    : Math.Max(target, _emptyMix - step);
            }
        }
        if (!Shield.InGraceOrRelease && Shield.Presence <= 0f)
        {
            _lastPresentVitals = null;
        }
    }

    internal void Reset()
    {
        Shield.Reset();
        _lastPresentVitals = null;
        _readoutInitialized = false;
        _displayShield = 0;
        _latestShield = 0;
        _readoutMax = 0;
        _layerHeldShield = 0;
        _layerHeldMax = 0;
        _readoutAge = 0;
        _resistantInitialized = false;
        _targetResistant = false;
        _resistantMix = 0;
        _emptyInitialized = false;
        _targetEmpty = false;
        _emptyMix = 0;
    }
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
