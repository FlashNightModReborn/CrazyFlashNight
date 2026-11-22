using System;

namespace CF7Launcher.Guardian.Hud.UnitLife;

// Raw numbers remain available to exact readouts. Only the drawable fractions saturate.
internal readonly record struct UnitHealth(double Current, double Maximum)
{
    internal bool IsValid => double.IsFinite(Current) && double.IsFinite(Maximum) && Maximum > 0;
    internal double Ratio => IsValid ? Math.Clamp(Current / Maximum, 0, 1) : 0;
    internal double OverflowRatio => IsValid && Current > Maximum
        ? Math.Clamp((Current - Maximum) / Maximum, 0, 1) : 0;
}

// Presentation output accepted by the bar painter independently of the owner, clock or layout.
internal readonly record struct UnitLifeBarVisual(UnitHealth Health, double TrailRatio,
    float LossAlpha, bool LossActive, double HealStartRatio, float GainAlpha, bool Critical)
{
    internal static UnitLifeBarVisual Resting(UnitHealth health) =>
        new(health, health.Ratio, 0, false, health.Ratio, 0, false);
}
