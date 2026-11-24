using System;

namespace CF7Launcher.Guardian.Hud.UnitLife;

internal readonly record struct WorldLifeIdentity(long SceneEpoch, long StreamEpoch, long Handle, long Generation);

// These are resolved gameplay facts. In particular, the poise value is the existing
// nonlinear mapping, and Darkened is the result of the AS2 impact-state rules.
internal readonly record struct WorldLifeFacts(UnitHealth Health, UnitHealth? Shield = null,
    double Poise = 0, bool Airborne = false, bool Down = false, bool Rigid = false,
    bool TaggedRigid = false, bool Darkened = false, bool InformationVisible = true,
    float WeatherOpacity = 1f);

internal enum WorldLifeStart { Spawn, Resync }

/// <summary>Frame-driven policy for a single bound world bar (#38). Advances strictly
/// by accepted source game frames (no AVM1 4-frame wheel quantization, no wall-clock drift).
/// An owner creates a new instance on scene, stream or generation change.</summary>
internal sealed class WorldLifeState
{
    // Exact 30fps durations inherited from AS2 (2.0s hold, 3.07s ease-out, 7.07s..10.0s fade, 4f flash)
    // without the legacy 4-frame wheel stair-step artifact.
    internal const int TrailStartFrames = 60;
    internal const int TrailEndFrames = 152;
    internal const int FadeStartFrames = 212;
    internal const int FadeEndFrames = 300;
    internal const int HitFlashFrames = 4;

    private readonly double _barWidth;
    private long _frame, _lastHitId = -1;
    private int _unchangedFrames;
    private int _flashFramesRemaining;
    private bool _revealed;
    private double _startResidual, _startActual, _lastObservedHp;

    internal WorldLifeIdentity Identity { get; }
    internal WorldLifeFacts Facts { get; private set; }
    internal double Actual { get; private set; }
    internal double Residual { get; private set; }
    internal bool Revealed => _revealed;
    internal double BarAlpha => !_revealed || !Facts.InformationVisible ? 0
        : 1 - Math.Clamp((_unchangedFrames - FadeStartFrames) / (double)(FadeEndFrames - FadeStartFrames), 0, 1);
    internal double Alpha => BarAlpha * Math.Clamp(Facts.WeatherOpacity, 0f, 1f);
    internal bool ShieldVisible => Facts.Shield is { IsValid: true } s && s.Current > 0;
    internal double ShieldRatio => ShieldVisible ? Facts.Shield!.Value.Ratio : 0;
    internal double PoiseRatio => Facts.Airborne || Facts.Down || !double.IsFinite(Facts.Poise)
        ? 0 : Math.Clamp(Facts.Poise, 0, 1);
    internal bool Rigid => Facts.Rigid || Facts.TaggedRigid;
    internal int ColorOffset { get; private set; }
    internal double OffsetX { get; private set; }
    internal double OffsetY { get; private set; }

    internal WorldLifeState(WorldLifeIdentity identity, long frame, WorldLifeFacts facts,
        double logicalBarWidth, WorldLifeStart start, bool revealedInitially = false)
    {
        if (frame < 0 || !facts.Health.IsValid || !(logicalBarWidth > 0) || !double.IsFinite(logicalBarWidth))
            throw new ArgumentOutOfRangeException();
        Identity = identity;
        Facts = facts;
        _barWidth = logicalBarWidth;
        _frame = frame;
        _lastObservedHp = facts.Health.Current;
        Actual = _startActual = facts.Health.Ratio;
        // Spawn starts residual at full width and hidden until first hit/damage (AS2 onClipEvent(load){ _visible=0 }).
        // Resync snaps residual to current HP and reveals only if damaged or explicitly visible.
        Residual = _startResidual = start == WorldLifeStart.Spawn ? 1 : _startActual;
        _revealed = revealedInitially || (start == WorldLifeStart.Resync && _startActual < 1);
        ColorOffset = facts.Darkened ? -75 : 0;
    }

    private void AdvanceFrames(long deltaFrames)
    {
        if (deltaFrames <= 0 || !Facts.InformationVisible) return;

        double actual = Facts.Health.Ratio;
        if (Facts.Health.Current != _lastObservedHp)
        {
            _lastObservedHp = Facts.Health.Current;
            _unchangedFrames = 0;
            _revealed = true;
            Actual = _startActual = actual;
            _startResidual = Residual;
            OffsetX = OffsetY = 0;
            deltaFrames--;
        }

        if (deltaFrames > 0)
        {
            _unchangedFrames += (int)Math.Min(deltaFrames, FadeEndFrames - _unchangedFrames);
            if (_flashFramesRemaining > 0)
            {
                _flashFramesRemaining = (int)Math.Max(0, _flashFramesRemaining - deltaFrames);
                if (_flashFramesRemaining == 0)
                    ColorOffset = Facts.Darkened ? -75 : 0;
            }
            else
            {
                ColorOffset = Facts.Darkened ? -75 : 0;
            }
        }

        if (Residual <= actual || _unchangedFrames < TrailStartFrames) return;
        double t = Math.Clamp((_unchangedFrames - TrailStartFrames) / (double)(TrailEndFrames - TrailStartFrames), 0, 1);
        Residual = _startResidual - (_startResidual - _startActual) * (t * (2 - t));
        if (_unchangedFrames >= TrailEndFrames || Math.Abs(Residual - actual) * _barWidth < 5)
            Residual = actual;
    }

    // Adopt a frame's facts first, then its hits. Duplicate or out-of-order frames are rejected.
    internal bool Apply(WorldLifeIdentity id, long frame, WorldLifeFacts facts)
    {
        if (id != Identity || frame <= _frame || !facts.Health.IsValid) return false;
        long beforeDelta = frame - 1 - _frame;
        if (beforeDelta > 0) AdvanceFrames(beforeDelta);
        Facts = facts;
        AdvanceFrames(1);
        _frame = frame;
        return true;
    }

    // Multiple hits may share a frame. The caller supplies already sampled cosmetic choices
    // in source order; this pure policy never advances a shared gameplay RNG.
    internal bool Hit(WorldLifeIdentity id, long frame, long eventId, uint jitterSeed, int? brightness = null)
    {
        if (id != Identity || frame < _frame || eventId <= _lastHitId || brightness is not (null or 25 or 50 or 75))
            return false;
        long delta = frame - _frame;
        if (delta > 0) AdvanceFrames(delta);
        _frame = frame;
        _lastHitId = eventId;
        _revealed = true;
        Actual = Facts.Health.Ratio;
        if (_unchangedFrames != 0 || _flashFramesRemaining == 0)
        {
            if (brightness.HasValue)
            {
                ColorOffset = brightness.Value;
                _flashFramesRemaining = HitFlashFrames;
            }
            _unchangedFrames = 0;
        }
        OffsetY += jitterSeed % 2 * .5 * Math.Sin(jitterSeed * .65);
        OffsetX += (((int)(jitterSeed * .5 % 3) << 1) * .15 + .3) * Math.Cos(jitterSeed * .35 + 1.6);
        return true;
    }

    internal UnitLifeBarVisual ToVisual()
    {
        float flash = ColorOffset > 0 ? Math.Clamp(ColorOffset / 75f, 0f, 1f) : 0f;
        bool darkened = ColorOffset < 0 || (ColorOffset == 0 && Facts.Darkened);
        return new UnitLifeBarVisual(
            Facts.Health,
            Residual,
            LossAlpha: 1f,
            LossActive: Residual > Actual + 0.001,
            HealStartRatio: Actual,
            GainAlpha: 0f,
            Critical: false,
            ShieldRatio: ShieldRatio,
            PoiseRatio: PoiseRatio,
            HasPoise: true,
            Rigid: Rigid,
            Airborne: Facts.Airborne,
            Down: Facts.Down,
            Darkened: darkened,
            HitFlash: flash,
            Alpha: (float)Alpha);
    }
}
