using System;

namespace CF7Launcher.Guardian.WorldCompositor
{
    // Source-local stable identity and priority remain CPU scheduling metadata.
    // The native record remains the existing sixteen-float world-light layout.
    internal readonly struct WorldLightCandidate
    {
        internal readonly long Key;
        internal readonly int Priority, Kind;
        internal readonly bool SceneReserved;
        internal readonly float X, Y, Length, Energy, R, G, B;
        internal readonly float DirectionX, DirectionY, HalfWidth, NearX, NearY, NearRadius, NearEnergy;

        internal WorldLightCandidate(long key, int priority, float x, float y, float length,
            float energy, float r, float g, float b, int kind, float directionX = 0,
            float directionY = 0, float halfWidth = 0, float nearX = 0, float nearY = 0,
            float nearRadius = 0, float nearEnergy = 0, bool sceneReserved = false)
        {
            Key = key; Priority = priority; X = x; Y = y; Length = length; Energy = energy;
            R = r; G = g; B = b; Kind = kind; DirectionX = directionX; DirectionY = directionY;
            HalfWidth = halfWidth; NearX = nearX; NearY = nearY;
            NearRadius = nearRadius; NearEnergy = nearEnergy;
            SceneReserved = sceneReserved;
        }

        internal void WriteTo(float[] target, int offset)
        {
            ArgumentNullException.ThrowIfNull(target);
            if (offset < 0 || offset > target.Length - 16) throw new ArgumentOutOfRangeException(nameof(offset));
            target[offset] = X; target[offset + 1] = Y;
            target[offset + 2] = Length; target[offset + 3] = Energy;
            target[offset + 4] = R; target[offset + 5] = G; target[offset + 6] = B;
            target[offset + 7] = Kind;
            target[offset + 8] = DirectionX; target[offset + 9] = DirectionY;
            target[offset + 10] = HalfWidth; target[offset + 11] = 0;
            target[offset + 12] = NearX; target[offset + 13] = NearY;
            target[offset + 14] = NearRadius; target[offset + 15] = NearEnergy;
        }
    }
}
