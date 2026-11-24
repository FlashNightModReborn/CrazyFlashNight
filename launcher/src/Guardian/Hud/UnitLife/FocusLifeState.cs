using System;

namespace CF7Launcher.Guardian.Hud.UnitLife;

// One state per active focus lease, advanced by its owner's existing decoration clock.
internal struct FocusLifeState
{
    private const int LossHoldMs = 90;
    private const int LossDecayMs = 230;
    private const int LossTotalMs = LossHoldMs + LossDecayMs;
    private const int CumulativeLossWindowMs = 260;
    private const int GainDurationMs = 360;
    private const int HitFlashDurationMs = 85;
    private const double RatioEpsilon = 0.0005;
    private const double HealPreviewThreshold = 0.055;

    private UnitHealth _health;
    private double _previousRatio;
    private double _trailAnchorRatio;
    private int _lossAgeMs;
    private int _windowLossAgeMs;
    private int _gainAgeMs;
    private int _hitFlashAgeMs;
    private long _lastHitSeq;
    private double _shieldRatio;
    private double _poiseRatio;
    private bool _hasPoise;
    private bool _rigid;
    private bool _airborne;
    private bool _down;
    private bool _darkened;

    internal double Ratio => _health.Ratio;
    internal double TrailRatio { get; private set; }
    internal double HealStartRatio { get; private set; }
    internal bool Critical { get; private set; }
    internal float LossAlpha => _lossAgeMs <= LossHoldMs ? 1f
        : Math.Clamp(1f - (_lossAgeMs - LossHoldMs) / (float)LossDecayMs, 0f, 1f);
    internal float GainAlpha => Math.Clamp(1f - _gainAgeMs / (float)GainDurationMs, 0f, 1f);
    internal float HitFlash
    {
        get
        {
            if (_hitFlashAgeMs >= HitFlashDurationMs) return 0f;
            float remain = Math.Clamp(1f - _hitFlashAgeMs / (float)HitFlashDurationMs, 0f, 1f);
            return remain * remain;
        }
    }
    internal bool HasActiveTransition =>
        (_lossAgeMs < LossTotalMs && TrailRatio > _previousRatio + RatioEpsilon)
        || (_gainAgeMs < GainDurationMs && _previousRatio > HealStartRatio + RatioEpsilon)
        || _hitFlashAgeMs < HitFlashDurationMs;
    internal UnitLifeBarVisual Visual =>
        new(_health, TrailRatio, LossAlpha, _lossAgeMs < LossTotalMs, HealStartRatio, GainAlpha, Critical,
            _shieldRatio, _airborne || _down ? 0 : _poiseRatio, _hasPoise, _rigid, _airborne, _down, _darkened, HitFlash, 1f);

    internal FocusLifeState(UnitHealth initial, double shieldRatio = 0, double poiseRatio = 0,
        bool hasPoise = false, bool rigid = false, bool airborne = false, bool down = false,
        bool darkened = false, long hitSeq = 0)
    {
        _health = initial;
        _previousRatio = _trailAnchorRatio = TrailRatio = HealStartRatio = initial.Ratio;
        _lossAgeMs = LossTotalMs;
        _windowLossAgeMs = CumulativeLossWindowMs;
        _gainAgeMs = GainDurationMs;
        _hitFlashAgeMs = HitFlashDurationMs;
        _lastHitSeq = Math.Max(0, hitSeq);
        _shieldRatio = double.IsFinite(shieldRatio) ? Math.Clamp(shieldRatio, 0, 1) : 0;
        _poiseRatio = double.IsFinite(poiseRatio) ? Math.Clamp(poiseRatio, 0, 1) : 0;
        _hasPoise = hasPoise;
        _rigid = rigid;
        _airborne = airborne;
        _down = down;
        _darkened = darkened;
        Critical = initial.IsValid && initial.Current > 0 && initial.Ratio <= 0.25;
    }

    internal void Apply(UnitHealth health, bool staticFeedback = false) =>
        Apply(health, _shieldRatio, _poiseRatio, _hasPoise, _rigid, _airborne, _down, _darkened, _lastHitSeq, staticFeedback);

    internal void Apply(UnitHealth health, double shieldRatio, double poiseRatio,
        bool hasPoise, bool rigid, bool airborne, bool down, bool darkened, long hitSeq,
        bool staticFeedback = false)
    {
        bool hadReading = _health.IsValid;
        _health = health;
        _shieldRatio = double.IsFinite(shieldRatio) ? Math.Clamp(shieldRatio, 0, 1) : 0;
        _poiseRatio = double.IsFinite(poiseRatio) ? Math.Clamp(poiseRatio, 0, 1) : 0;
        _hasPoise = hasPoise;
        _rigid = rigid;
        _airborne = airborne;
        _down = down;
        _darkened = darkened;

        long normalizedHit = Math.Max(0, hitSeq);
        bool hitAdvanced = hadReading && normalizedHit > _lastHitSeq;
        _lastHitSeq = normalizedHit;

        double ratio = health.Ratio;
        Critical = health.IsValid && health.Current > 0 && ratio <= (Critical ? 0.30 : 0.25);
        if (staticFeedback || !hadReading || !health.IsValid)
        {
            _previousRatio = _trailAnchorRatio = TrailRatio = HealStartRatio = ratio;
            _lossAgeMs = LossTotalMs;
            _windowLossAgeMs = CumulativeLossWindowMs;
            _gainAgeMs = GainDurationMs;
            _hitFlashAgeMs = HitFlashDurationMs;
            return;
        }

        // Do not pin the flash at full intensity during rapid multi-hit bursts;
        // let each short glint settle before firing the next pulse.
        if (hitAdvanced && _hitFlashAgeMs >= HitFlashDurationMs)
            _hitFlashAgeMs = 0;

        if (ratio < _previousRatio - RatioEpsilon)
        {
            double anchor = Math.Max(TrailRatio, _previousRatio);
            if (_lossAgeMs < LossTotalMs || _windowLossAgeMs < CumulativeLossWindowMs)
                anchor = Math.Max(_trailAnchorRatio, anchor);
            _trailAnchorRatio = TrailRatio = anchor;
            _previousRatio = ratio;
            _lossAgeMs = _windowLossAgeMs = 0;
            _gainAgeMs = GainDurationMs;
        }
        else if (ratio > _previousRatio + RatioEpsilon)
        {
            if (ratio - _previousRatio >= HealPreviewThreshold)
            {
                HealStartRatio = _previousRatio;
                _gainAgeMs = 0;
            }
            _previousRatio = ratio;
            if (ratio >= TrailRatio)
            {
                TrailRatio = _trailAnchorRatio = ratio;
                _lossAgeMs = LossTotalMs;
            }
        }
    }

    // A true result asks the owner to invalidate the affected bounds on its shared surface.
    internal bool Tick(int deltaMs)
    {
        if (deltaMs <= 0) return false;
        bool changed = false;
        if (_windowLossAgeMs < CumulativeLossWindowMs)
            _windowLossAgeMs = (int)Math.Min(CumulativeLossWindowMs, (long)_windowLossAgeMs + deltaMs);
        if (_lossAgeMs < LossTotalMs)
        {
            _lossAgeMs = (int)Math.Min(LossTotalMs, (long)_lossAgeMs + deltaMs);
            if (_lossAgeMs == LossTotalMs)
                _trailAnchorRatio = TrailRatio = _previousRatio;
            else if (_lossAgeMs <= LossHoldMs)
                TrailRatio = _trailAnchorRatio;
            else
            {
                float t = (_lossAgeMs - LossHoldMs) / (float)LossDecayMs;
                float eased = t * t * (3f - 2f * t);
                TrailRatio = _trailAnchorRatio + (_previousRatio - _trailAnchorRatio) * eased;
            }
            changed = true;
        }
        if (_gainAgeMs < GainDurationMs)
        {
            int oldBucket = _gainAgeMs / 25;
            _gainAgeMs = (int)Math.Min(GainDurationMs, (long)_gainAgeMs + deltaMs);
            if (_gainAgeMs == GainDurationMs) HealStartRatio = _previousRatio;
            changed |= _gainAgeMs / 25 != oldBucket || _gainAgeMs == GainDurationMs;
        }
        if (_hitFlashAgeMs < HitFlashDurationMs)
        {
            int oldBucket = _hitFlashAgeMs / 25;
            _hitFlashAgeMs = (int)Math.Min(HitFlashDurationMs, (long)_hitFlashAgeMs + deltaMs);
            changed |= _hitFlashAgeMs / 25 != oldBucket || _hitFlashAgeMs == HitFlashDurationMs;
        }
        return changed;
    }
}
