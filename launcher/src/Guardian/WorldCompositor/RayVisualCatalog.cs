using System;

namespace CF7Launcher.Guardian.WorldCompositor
{
    // The wire carries resolved TeslaRayConfig visual fields, never damage or collision state.
    // Keep FieldNames in the same order as RayVisualBridge.fields; a source-contract test checks it.
    internal static class RayVisualCatalog
    {
        // Paired ray budget: 1024 active channels, 4096 draw records, 1024
        // immutable configs. Per-packet events stay bounded by MaxEvents.
        internal const int Version = 1, ArcLimit = 1024, DrawLimit = 4096, Stride = 32, ConfigLimit = 1024;
        internal const int ChannelVersion = 1, LightingVersion = 1, MaxEvents = 4096;
        internal static readonly string[] Styles = {
            "tesla", "prism", "radiance", "spectrum", "resonance", "wave",
            "thermal", "vortex", "plasma", "convergence", "bagua_rod", "flame_stream"
        };
        internal static readonly string[] FieldNames = {
            "primaryColor", "secondaryColor", "thickness", "visualDuration", "fadeOutDuration",
            "flickerEnabled", "flickerMin", "flickerMax", "branchCount", "branchProbability",
            "segmentLength", "jitter", "shimmerAmp", "shimmerFreq", "forkThicknessMul",
            "paletteScrollSpeed", "stripeCount", "distortAmp", "distortWaveLen", "waveAmp",
            "waveLen", "waveSpeed", "pulseAmp", "pulseRate", "hitRippleSize", "hitRippleAlpha",
            "railSpread", "convergenceRatio", "railCount", "nodeCount", "nodeSpeed", "crosshairScale",
            "slicesCount", "sliceSpacing", "sliceRadius", "sliceCompressX", "angVelDeg", "counterRotate",
            "phaseOffsetDeg", "pulseWidth", "baseIdleAlpha", "mixedColor", "spineColor", "glowAlpha",
            "glowWidthMult", "nDiagonals", "linkerStride", "tongueCount", "tipBloomScale", "smokeColor",
            "flameReuseMaxOriginDist"
        };

        // GPU record: xyxy[0..3], primaryRGB/alpha[4..7], secondaryRGB/width[8..11],
        // phaseAge/totalLife/seed/style[12..15], intensity/kind/hitIndex/isHit[16..19], p[20..31].
        // Colours here are straight RGB (0..1); shader output applies coverage and premultiplication.
        // p slots are authored values, without silently flattening every style into one line:
        // 0: jitter, segmentLength, branchCount, branchProbability, shimmerAmp, shimmerFreq, forkThicknessMul,
        //    current emission age (ABI 12 p1.w); structural phase in slot 12 survives channel upserts.
        // 1,2: shimmerAmp, shimmerFreq, forkThicknessMul.
        // 3,4: stripeCount, paletteScrollSpeed, distortAmp, distortWaveLen, paletteCount, paletteRGB24[0..6].
        // 5..8: waveAmp, waveLen, waveSpeed, pulseAmp, pulseRate, hitRippleSize, hitRippleAlpha.
        // 9: railSpread, convergenceRatio, railCount, nodeCount, nodeSpeed, crosshairScale.
        // 10: slicesCount, sliceSpacing, sliceRadius, sliceCompressX, angVelDeg, counterRotate,
        //     phaseOffsetDeg, pulseAmp, pulseWidth, baseIdleAlpha, glowAlpha, glowWidthMult.
        //     Body-only metadata retained in ABI 12: [13]=visualDuration, [14]=spine RGB24,
        //     [17]=nDiagonals, [18]=linkerStride, [19]=mixed RGB24. Other styles retain
        //     the common clock/seed/event metadata above. All Bagua structure shares one record.
        // 11: waveAmp, waveLen, waveSpeed, pulseAmp, pulseRate, tongueCount, tipBloomScale,
        //     smokeColorRGB24, pulseProgress, hotPulse, damagePulse, isBlocked.
        // style +16: hit ornament, width=hitRippleSize and p0=hitRippleAlpha (percent).
        // 42 is a retired decoration id, accepted as transparent by the paired renderer.
        internal static readonly int[][] ParameterFields = {
            new[] {11,10,8,9,12,13,14}, new[] {12,13,14}, new[] {12,13,14},
            new[] {16,15,17,18}, new[] {16,15,17,18},
            new[] {19,20,21,22,23,24,25}, new[] {19,20,21,22,23,24,25},
            new[] {19,20,21,22,23,24,25}, new[] {19,20,21,22,23,24,25},
            new[] {26,27,28,29,30,31}, new[] {32,33,34,35,36,37,38,22,39,40,43,44},
            new[] {19,20,21,22,23,47,48,49}
        };

        internal static bool ValidField(int index, float value)
        {
            if (!float.IsFinite(value)) return false;
            if (index is 0 or 1 or 41 or 42 or 49) return value >= 0 && value <= 16777215 && value == MathF.Floor(value);
            if (index is 5 or 37) return value == 0 || value == 1;
            if (index is 3 or 4) return value >= 0 && value <= 600;
            if (index == 2) return value >= 0 && value <= 512;
            return value >= -1000000 && value <= 1000000;
        }
    }

    internal readonly struct RayLightOverrides : IEquatable<RayLightOverrides>
    {
        internal readonly string Profile;
        internal readonly float EnergyScale,WidthScale;
        internal readonly int Color,FadeTicks;
        internal static readonly RayLightOverrides Default = new("auto",1,1,-1,-1);

        internal RayLightOverrides(string profile,float energyScale,float widthScale,int color,int fadeTicks)
        { Profile=profile;EnergyScale=energyScale;WidthScale=widthScale;Color=color;FadeTicks=fadeTicks; }

        internal static bool IsKnownProfile(string profile) =>
            profile is "auto" or "none" or "flame" or "beam" or "heavy" or "arc" or "glyph";
        internal bool IsValid => IsKnownProfile(Profile)
            && float.IsFinite(EnergyScale) && EnergyScale>=0 && EnergyScale<=2
            && float.IsFinite(WidthScale) && WidthScale>=.25f && WidthScale<=4
            && Color>=-1 && Color<=0xFFFFFF && FadeTicks>=-1 && FadeTicks<=30;

        public bool Equals(RayLightOverrides other) => string.Equals(Profile,other.Profile,StringComparison.Ordinal)
            && EnergyScale==other.EnergyScale && WidthScale==other.WidthScale
            && Color==other.Color && FadeTicks==other.FadeTicks;
        public override bool Equals(object obj) => obj is RayLightOverrides other && Equals(other);
        public override int GetHashCode() => HashCode.Combine(Profile,EnergyScale,WidthScale,Color,FadeTicks);
        public static bool operator ==(RayLightOverrides left,RayLightOverrides right) => left.Equals(right);
        public static bool operator !=(RayLightOverrides left,RayLightOverrides right) => !left.Equals(right);
    }

    internal sealed class RayVisualConfig
    {
        internal readonly int Id, Style;
        internal readonly float[] Values;
        internal readonly int[] Palette;
        internal readonly RayLightOverrides Light;
        internal RayVisualConfig(int id, int style, float[] values, int[] palette,RayLightOverrides? light=null)
        {
            Id=id; Style=style; Values=values; Palette=palette;Light=light??RayLightOverrides.Default;
            if(!Light.IsValid) throw new ArgumentOutOfRangeException(nameof(light),"Invalid ray light override");
        }
        internal float this[int index] => Values[index];
    }

    internal sealed class RayVisualDrawFrame
    {
        internal readonly float[] Data;
        internal int Count;
        internal readonly WorldLightCandidate[] Lights=new WorldLightCandidate[RayVisualCatalog.ArcLimit];
        internal int LightCount;
        internal RayVisualDrawFrame(int capacity = RayVisualCatalog.DrawLimit)
        { Data = new float[capacity * RayVisualCatalog.Stride]; }
    }
}
