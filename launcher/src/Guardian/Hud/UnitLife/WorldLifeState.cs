using System;

namespace CF7Launcher.Guardian.Hud.UnitLife;

internal readonly record struct WorldLifeIdentity(long SceneEpoch, long StreamEpoch, long Handle, long Generation);

// These are resolved gameplay facts. In particular, the poise value is the existing
// nonlinear mapping, and Darkened is the result of the AS2 impact-state rules.
internal readonly record struct WorldLifeFacts(UnitHealth Health, UnitHealth? Shield = null,
    double Poise = 0, bool Airborne = false, bool Down = false, bool Rigid = false,
    bool TaggedRigid = false, bool Darkened = false, bool InformationVisible = true);

internal enum WorldLifeStart { Spawn, Resync }

/// <summary>Offline policy for a single bound world bar. Only accepted source frames
/// advance it. An owner creates a new instance on scene, stream or generation change.</summary>
internal sealed class WorldLifeState
{
    private const int WheelFrames = 4, TrailStart = 15, TrailEnd = 38, FadeStart = 53, FadeEnd = 75;
    private readonly double _barWidth;
    private readonly int _wheelPhase;
    private long _frame, _wheel, _lastHitId = -1;
    private int _age;
    private double _startResidual, _startActual, _lastObservedHp;

    internal WorldLifeIdentity Identity { get; }
    internal WorldLifeFacts Facts { get; private set; }
    internal double Actual { get; private set; }
    internal double Residual { get; private set; }
    internal double Alpha => Facts.InformationVisible
        ? 1 - Math.Clamp((_age - FadeStart) / (double)(FadeEnd - FadeStart), 0, 1) : 0;
    internal bool ShieldVisible => Facts.Shield is { IsValid: true };
    internal double ShieldRatio => ShieldVisible ? Facts.Shield.Value.Ratio : 0;
    internal double PoiseRatio => Facts.Airborne || Facts.Down || !double.IsFinite(Facts.Poise)
        ? 0 : Math.Clamp(Facts.Poise, 0, 1);
    internal bool Rigid => Facts.Rigid || Facts.TaggedRigid;
    internal int ColorOffset { get; private set; }
    internal double OffsetX { get; private set; }
    internal double OffsetY { get; private set; }

    internal WorldLifeState(WorldLifeIdentity identity, long frame, WorldLifeFacts facts,
        double logicalBarWidth, WorldLifeStart start, int wheelPhase = 0)
    {
        if (frame < 0 || !facts.Health.IsValid || !(logicalBarWidth > 0) || !double.IsFinite(logicalBarWidth)
            || wheelPhase is < 0 or >= WheelFrames) throw new ArgumentOutOfRangeException();
        Identity = identity;
        Facts = facts;
        _barWidth = logicalBarWidth;
        _wheelPhase = wheelPhase;
        _frame = frame;
        _wheel = WheelIndex(frame);
        _lastObservedHp = facts.Health.Current;
        Actual = _startActual = facts.Health.Ratio;
        // ParameterInitializer starts a newly spawned residual at full bar width.
        // A reconnect deliberately snaps to the current reading without an invented hit.
        Residual = _startResidual = start == WorldLifeStart.Spawn ? 1 : _startActual;
        ColorOffset = facts.Darkened ? -75 : 0;
    }

    private long WheelIndex(long frame) => frame / WheelFrames - (frame % WheelFrames < _wheelPhase ? 1 : 0);

    private void VisitThrough(long frame)
    {
        long wheel = WheelIndex(frame);
        long ticks = wheel - _wheel;
        if (ticks <= 0) return;
        _wheel = wheel;
        if (!Facts.InformationVisible) return;
        double actual = Facts.Health.Ratio;
        // The old updater compares absolute HP, and never observes it while hidden.
        // Only its first eligible wheel visit consumes a pending change.
        if (Facts.Health.Current != _lastObservedHp)
        {
            _lastObservedHp = Facts.Health.Current;
            _age = 0;
            Actual = _startActual = actual;
            _startResidual = Residual;
            OffsetX = OffsetY = 0;
            --ticks;
        }
        if (ticks > 0)
        {
            _age += (int)Math.Min(ticks, FadeEnd - _age);
            ColorOffset = Facts.Darkened ? -75 : 0;
        }
        // A rising actual bar covers the residual. Flash does not grow the residual on healing.
        if (Residual <= actual || _age < TrailStart) return;
        double t = Math.Clamp((_age - TrailStart) / (double)(TrailEnd - TrailStart), 0, 1);
        Residual = _startResidual - (_startResidual - _startActual) * (t * (2 - t));
        if (_age > TrailEnd || Math.Abs(Residual - actual) * _barWidth < 5) Residual = actual;
    }

    // Adopt a frame's facts first, then its hits. A duplicate or a snapshot arriving
    // after a hit for the same frame cannot rewind the wheel.
    internal bool Apply(WorldLifeIdentity id, long frame, WorldLifeFacts facts)
    {
        if (id != Identity || frame <= _frame || !facts.Health.IsValid) return false;
        VisitThrough(frame - 1);
        Facts = facts;
        VisitThrough(frame);
        _frame = frame;
        return true;
    }

    // Multiple hits may share a frame. The caller supplies already sampled cosmetic
    // choices in source order; this pure policy never advances a shared gameplay RNG.
    internal bool Hit(WorldLifeIdentity id, long frame, long eventId, uint jitterSeed, int? brightness = null)
    {
        if (id != Identity || frame < _frame || eventId <= _lastHitId || brightness is not (null or 25 or 50 or 75)) return false;
        VisitThrough(frame);
        _frame = frame;
        _lastHitId = eventId;
        Actual = Facts.Health.Ratio;
        if (_age != 0)
        {
            // Flash samples a lightening level only when its unchanged counter is nonzero.
            if (brightness.HasValue) ColorOffset = brightness.Value;
            _age = 0;
        }
        OffsetY += jitterSeed % 2 * .5 * Math.Sin(jitterSeed * .65);
        OffsetX += (((int)(jitterSeed * .5 % 3) << 1) * .15 + .3) * Math.Cos(jitterSeed * .35 + 1.6);
        return true;
    }
}
