using System;
using System.Collections.Generic;

namespace CF7Launcher.Guardian.WorldCompositor
{
    // Called under the controller's existing world lock. Inputs borrow engine
    // buffers, so setters copy synchronously. Output is composer-owned and is
    // borrowed until the next Set/Clear/Reset/Compose call; native copies it now.
    internal sealed class WorldLightComposer
    {
        private const int SpriteLimit = 512, FxCandidateLimit = 32;
        private const int RayLimit = RayVisualCatalog.ArcLimit;
        private const int Limit = CombatFxEngine.LightLimit, Stride = CombatFxEngine.LightStride;
        private const double Left = -2, Top = -2, Right = 1026, Bottom = 578;
        private readonly CombatFxDrawFrame _draw = new(SpriteLimit);
        private readonly float[] _fxLights = new float[Limit * Stride];
        private readonly long[] _fxIds = new long[Limit];
        private readonly WorldLightCandidate[] _fxCandidates = new WorldLightCandidate[FxCandidateLimit];
        private readonly WorldLightCandidate[] _rays = new WorldLightCandidate[RayLimit];
        private readonly Candidate[] _candidates = new Candidate[FxCandidateLimit + RayLimit];
        private readonly Dictionary<Identity, int> _seen = new(FxCandidateLimit + RayLimit);
        private readonly HashSet<Identity> _previous = new();
        private readonly float _maximumResponse;
        private int _fxCount, _casings, _impacts, _fxLightCount, _residentCount, _fxCandidateCount, _rayCount;

        private readonly record struct Identity(byte Source, long Key);
        private readonly record struct Point(double X, double Y);
        private struct Candidate
        {
            internal Identity Identity;
            internal WorldLightCandidate Light;
            internal double Score;
            internal int SourceOrder;
        }
        private static readonly IComparer<Candidate> Ranking = Comparer<Candidate>.Create((a, b) => {
            int result = b.Light.Priority.CompareTo(a.Light.Priority);
            if (result == 0) result = b.Score.CompareTo(a.Score);
            if (result == 0) result = a.Identity.Source.CompareTo(b.Identity.Source);
            return result != 0 ? result : a.Identity.Key.CompareTo(b.Identity.Key);
        });
        private static readonly IComparer<Candidate> OutputOrder = Comparer<Candidate>.Create((a, b) => {
            int result = a.Identity.Source.CompareTo(b.Identity.Source);
            if (result != 0) return result;
            // Retain equipment/muzzle order, and make ray order independent of
            // producer slot compaction. Order never overrides selection priority.
            return a.Identity.Source == 2 ? a.Identity.Key.CompareTo(b.Identity.Key)
                : a.SourceOrder.CompareTo(b.SourceOrder);
        });

        internal WorldLightComposer(float maximumResponse)
        {
            if (!Valid(maximumResponse, 0, .8f)) throw new ArgumentOutOfRangeException(nameof(maximumResponse));
            _maximumResponse = maximumResponse;
            _draw.MaximumLightResponse = maximumResponse;
        }

        internal void SetCombatFx(CombatFxDrawFrame frame)
        {
            if (frame == null) { ClearCombatFx(); return; }
            if (frame.Count < 0 || frame.Count > SpriteLimit || frame.Data.Length < frame.Count * 16
                || frame.CasingCount < 0 || frame.ImpactCount < 0 || frame.CasingCount > frame.Count
                || frame.ImpactCount > frame.Count || frame.CasingCount + frame.ImpactCount > frame.Count
                || frame.LightCount < 0 || frame.LightCount > Limit
                || frame.Lights.Length < frame.LightCount * Stride || frame.LightIds.Length < frame.LightCount
                || frame.ResidentLightCount < 0 || frame.ResidentLightCount > frame.LightCount
                || frame.CandidateLightCount < 0 || frame.CandidateLightCount > FxCandidateLimit
                || frame.CandidateLights.Length < frame.CandidateLightCount
                || (frame.CandidateLightCount > 0 && frame.CandidateLightCount < frame.ResidentLightCount))
                throw new ArgumentException("Invalid borrowed combat FX frame", nameof(frame));
            Array.Copy(frame.Data, _draw.Data, frame.Count * 16);
            Array.Copy(frame.Lights, _fxLights, frame.LightCount * Stride);
            Array.Copy(frame.LightIds, _fxIds, frame.LightCount);
            _fxCount = frame.Count; _casings = frame.CasingCount; _impacts = frame.ImpactCount;
            _fxLightCount = frame.LightCount; _residentCount = frame.ResidentLightCount;
            _fxCandidateCount = frame.CandidateLightCount;
            if (_fxCandidateCount > 0) Array.Copy(frame.CandidateLights, _fxCandidates, _fxCandidateCount);
            else
            {
                // Older fixture callers only populate the native-format array.
                _fxCandidateCount = frame.LightCount;
                for (int i = 0; i < _fxCandidateCount; i++)
                {
                    int at = i * Stride;
                    long key = _fxIds[i] != 0 ? _fxIds[i] : long.MinValue + i;
                    int kind = (int)_fxLights[at + 7];
                    _fxCandidates[i] = new WorldLightCandidate(key,
                        i < _residentCount ? (kind == 0 ? 70 : 100) : 75,
                        _fxLights[at], _fxLights[at + 1], _fxLights[at + 2], _fxLights[at + 3],
                        _fxLights[at + 4], _fxLights[at + 5], _fxLights[at + 6], kind,
                        _fxLights[at + 8], _fxLights[at + 9], _fxLights[at + 10],
                        _fxLights[at + 12], _fxLights[at + 13], _fxLights[at + 14], _fxLights[at + 15]);
                }
            }
        }

        internal void SetRays(RayVisualDrawFrame frame)
        {
            if (frame == null) { ClearRays(); return; }
            if (frame.LightCount < 0 || frame.LightCount > RayLimit || frame.Lights.Length < frame.LightCount)
                throw new ArgumentException("Invalid borrowed ray light frame", nameof(frame));
            Array.Copy(frame.Lights, _rays, frame.LightCount);
            _rayCount = frame.LightCount;
        }

        internal void ClearCombatFx()
        {
            _fxCount = _casings = _impacts = _fxLightCount = _residentCount = _fxCandidateCount = 0;
            _draw.Count = _draw.CasingCount = _draw.ImpactCount = 0;
            _previous.RemoveWhere(key => key.Source != 2);
        }

        internal void ClearRays()
        {
            _rayCount = 0;
            _previous.RemoveWhere(key => key.Source == 2);
        }

        internal void Reset()
        {
            ClearCombatFx(); ClearRays(); _previous.Clear(); _seen.Clear();
            _draw.LightCount = _draw.ResidentLightCount = _draw.CandidateLightCount = 0;
            _draw.MaximumLightResponse = _maximumResponse;
        }

        internal CombatFxDrawFrame Compose(float cameraX, float cameraY, float scale)
        {
            if (!float.IsFinite(cameraX) || !float.IsFinite(cameraY) || !float.IsFinite(scale)
                || Math.Abs(cameraX) > 1000000 || Math.Abs(cameraY) > 1000000
                || Math.Abs(scale) < .0001f || Math.Abs(scale) > 20)
                throw new ArgumentOutOfRangeException(nameof(scale), "Invalid world-light camera");
            _draw.Count = _fxCount; _draw.CasingCount = _casings; _draw.ImpactCount = _impacts;
            _draw.MaximumLightResponse = _maximumResponse;
            _seen.Clear();
            int count = 0;
            for (int i = 0; i < _rayCount; i++) Add(_rays[i], 2, i, cameraX, cameraY, scale, ref count);
            if (count == 0)
            {
                // No contributing ray lights: keep the exact original FX light
                // selection and bytes, including its stable resident-first order.
                Array.Copy(_fxLights, _draw.Lights, _fxLightCount * Stride);
                Array.Copy(_fxIds, _draw.LightIds, _fxLightCount);
                Array.Copy(_fxCandidates, _draw.CandidateLights, _fxCandidateCount);
                _draw.LightCount = _fxLightCount; _draw.ResidentLightCount = _residentCount;
                _draw.CandidateLightCount = _fxCandidateCount;
                _previous.Clear();
                for (int i = 0; i < _fxLightCount; i++)
                    _previous.Add(new Identity(i < _residentCount ? (byte)0 : (byte)1,
                        _fxIds[i] != 0 ? _fxIds[i] : long.MinValue + i));
                return _draw;
            }
            for (int i = 0; i < _fxCandidateCount; i++)
                Add(_fxCandidates[i], i < _residentCount ? (byte)0 : (byte)1, i, cameraX, cameraY, scale, ref count);
            Array.Sort(_candidates, 0, count, Ranking);
            int selected = Math.Min(Limit, count);
            Array.Sort(_candidates, 0, selected, OutputOrder);
            _previous.Clear();
            _draw.ResidentLightCount = 0;
            for (int i = 0; i < selected; i++)
            {
                Candidate candidate = _candidates[i];
                candidate.Light.WriteTo(_draw.Lights, i * Stride);
                _draw.LightIds[i] = candidate.Light.Key;
                _draw.CandidateLights[i] = candidate.Light;
                if (candidate.Identity.Source == 0) _draw.ResidentLightCount++;
                _previous.Add(candidate.Identity);
            }
            _draw.LightCount = _draw.CandidateLightCount = selected;
            return _draw;
        }

        private void Add(WorldLightCandidate light, byte source, int order,
            float cameraX, float cameraY, float scale, ref int count)
        {
            if (!ValidLight(light)) return;
            double area = VisibleFootprint(light, cameraX, cameraY, scale);
            if (!(area > 0)) return;
            var identity = new Identity(source, light.Key);
            // This is an approximate screen-contribution score, not a second
            // lighting model. Priority tiers always dominate the score.
            double score = area * Math.Max(light.Energy, light.NearEnergy)
                * (.3 + .7 * (.2126 * light.R + .7152 * light.G + .0722 * light.B));
            if (_previous.Contains(identity)) score *= 1.08;
            var candidate = new Candidate { Identity = identity, Light = light, Score = score, SourceOrder = order };
            if (_seen.TryGetValue(identity, out int existing))
            {
                if (Ranking.Compare(candidate, _candidates[existing]) < 0) _candidates[existing] = candidate;
                return;
            }
            _seen.Add(identity, count); _candidates[count++] = candidate;
        }

        private static bool Valid(float value, float min, float max) => float.IsFinite(value) && value >= min && value <= max;
        private static bool ValidLight(WorldLightCandidate p)
        {
            if (p.Kind < 0 || p.Kind > 2 || !Valid(p.X, -1000000, 1000000) || !Valid(p.Y, -1000000, 1000000)
                || !Valid(p.Length, 1, 1024) || !Valid(p.Energy, 0, 2)
                || !Valid(p.R, 0, 1) || !Valid(p.G, 0, 1) || !Valid(p.B, 0, 1)
                || !Valid(p.NearX, -1000000, 1000000) || !Valid(p.NearY, -1000000, 1000000)
                || !Valid(p.NearRadius, 0, 320) || !Valid(p.NearEnergy, 0, 2)
                || (p.NearRadius > 0) != (p.NearEnergy > 0)
                || (p.Energy == 0 && p.NearEnergy == 0)) return false;
            if (p.NearRadius == 0 && (p.NearX != 0 || p.NearY != 0)) return false;
            if (p.Kind != 1 && (p.NearX != 0 || p.NearY != 0 || p.NearRadius != 0 || p.NearEnergy != 0)) return false;
            if (p.Kind == 0) return p.Length <= 320 && p.DirectionX == 0 && p.DirectionY == 0 && p.HalfWidth == 0;
            return Valid(p.DirectionX, -1, 1) && Valid(p.DirectionY, -1, 1) && Valid(p.HalfWidth, .5f, 512)
                && Math.Abs(p.DirectionX * p.DirectionX + p.DirectionY * p.DirectionY - 1) <= .02f;
        }

        private static double VisibleFootprint(WorldLightCandidate p, float cameraX, float cameraY, float scale)
        {
            // Distinct vertices of two intersecting quads are bounded by eight,
            // but boundary intersections can transiently repeat an endpoint.
            Span<Point> polygon = stackalloc Point[16];
            Span<Point> scratch = stackalloc Point[16];
            if (p.Kind == 0)
            {
                double x = cameraX + (double)p.X * scale, y = cameraY + (double)p.Y * scale;
                double radius = p.Length * Math.Abs(scale);
                double dx = x - Math.Clamp(x, Left, Right), dy = y - Math.Clamp(y, Top, Bottom);
                if (dx * dx + dy * dy > radius * radius) return 0;
                polygon[0] = new(x - radius, y - radius); polygon[1] = new(x + radius, y - radius);
                polygon[2] = new(x + radius, y + radius); polygon[3] = new(x - radius, y + radius);
            }
            else
            {
                // Reproduce the native directional raster bound, including its
                // half-light-texel AA margin and kind-1 near-fill union.
                double margin = 2 / Math.Abs(scale), lo = 0, hi = p.Length, half = p.HalfWidth + margin;
                if (p.NearRadius > 0)
                {
                    double nx = p.NearX - p.X, ny = p.NearY - p.Y;
                    double along = nx * p.DirectionX + ny * p.DirectionY;
                    double side = -nx * p.DirectionY + ny * p.DirectionX;
                    lo = Math.Min(0, along - p.NearRadius - margin);
                    hi = Math.Max(p.Length, along + p.NearRadius + margin);
                    half = Math.Max(p.HalfWidth, Math.Abs(side) + p.NearRadius) + margin;
                }
                for (int i = 0; i < 4; i++)
                {
                    double along = i is 1 or 2 ? hi : lo, side = i < 2 ? -half : half;
                    double x = p.X + p.DirectionX * along - p.DirectionY * side;
                    double y = p.Y + p.DirectionY * along + p.DirectionX * side;
                    polygon[i] = new(cameraX + x * scale, cameraY + y * scale);
                }
            }
            int count = 4;
            for (int edge = 0; edge < 4 && count > 0; edge++)
            {
                int next = 0;
                Point previous = polygon[count - 1]; bool previousInside = Inside(previous, edge);
                for (int i = 0; i < count; i++)
                {
                    Point current = polygon[i]; bool currentInside = Inside(current, edge);
                    if (previousInside != currentInside && !Append(scratch, ref next, Intersection(previous, current, edge))) return 0;
                    if (currentInside && !Append(scratch, ref next, current)) return 0;
                    previous = current; previousInside = currentInside;
                }
                if (next > 1 && Same(scratch[0], scratch[next - 1])) next--;
                scratch[..next].CopyTo(polygon); count = next;
            }
            if (count < 3) return 0;
            double area = 0;
            for (int i = 0; i < count; i++)
            {
                Point a = polygon[i], b = polygon[(i + 1) % count];
                area += a.X * b.Y - b.X * a.Y;
            }
            return Math.Abs(area) * .5 * (p.Kind == 0 ? Math.PI / 4 : 1);
        }

        private static bool Inside(Point p, int edge) => edge switch {
            0 => p.X >= Left, 1 => p.X <= Right, 2 => p.Y >= Top, _ => p.Y <= Bottom
        };
        private static bool Same(Point a, Point b) => Math.Abs(a.X - b.X) <= .0000001 && Math.Abs(a.Y - b.Y) <= .0000001;
        private static bool Append(Span<Point> vertices, ref int count, Point value)
        {
            if (count > 0 && Same(vertices[count - 1], value)) return true;
            if (count == vertices.Length) return false;
            vertices[count++] = value; return true;
        }
        private static Point Intersection(Point a, Point b, int edge)
        {
            double bound = edge switch { 0 => Left, 1 => Right, 2 => Top, _ => Bottom };
            double t = edge < 2 ? (bound - a.X) / (b.X - a.X) : (bound - a.Y) / (b.Y - a.Y);
            return edge < 2 ? new(bound, a.Y + (b.Y - a.Y) * t) : new(a.X + (b.X - a.X) * t, bound);
        }
    }
}
