using System;

namespace CF7Launcher.Guardian.WorldCompositor
{
    // One schedule-owned budget for decorative work. Projectile visibility,
    // muzzle/impact feedback and world lighting retain their existing limits.
    internal readonly struct NativeVisualBudget
    {
        internal int EffectLevel { get; }
        internal int WeatherQuality => EffectLevel;
        internal int CasingLimit => EffectLevel switch { 0 => 256, 1 => 128, _ => 64 };

        private NativeVisualBudget(int effectLevel) { EffectLevel=effectLevel; }

        internal static NativeVisualBudget FromEffectLevel(int effectLevel)
        {
            if (effectLevel<0 || effectLevel>2)
                throw new ArgumentOutOfRangeException(nameof(effectLevel));
            return new NativeVisualBudget(effectLevel);
        }
    }
}
