R"hlsl(
// ============================================================================
// ray-styles.hlsl  --  CF7 ray VFX style library (SM4 / ps_4_0, textureless)
//
// Procedural re-authoring of the AS2 renderer suite
// (scripts/.../arki/render/renderer/*.as) as analytic beam-space SDF shading.
//
// Public entry:
//   float4 ShadeRayStyle(uint style, float2 q, float lengthWorld,
//                        float widthWorld, float ageTicks, float seed,
//                        float3 primary, float3 secondary,
//                        float4 p0, float4 p1, float4 p2,
//                        float4 meta, float life);
//
// Contract:
//   q.x        = normalized longitudinal progress [0,1] (small overshoot ok)
//   q.y        = signed transverse distance in world pixels
//   lengthWorld= authoritative segment length in world px (>0)
//   widthWorld = nominal FULL core width in world px (AS2 lineStyle thickness)
//   ageTicks   = game tick counter, 30 Hz == AS2 arc.age (frames)
//   seed       = stable per-ray seed; Bagua packs authored spine RGB24 instead
//   meta/life  = paired internal GPU style metadata; see RayVisualCatalog
//   return     = straight float4(rgb, a); rgb is accumulated emissive energy
//                (may exceed 1 near hot cores -- intended for additive/screen
//                blending by root); a is bounded coverage alpha [0,1].
//
// Notes:
//   * Beam paths meet their authoritative endpoints. Bagua's endpoint-centred
//     gates retain their complete authored outline beyond those endpoints;
//     this is decorative geometry and never adds a damaging region.
//   * Zero-valued params are guarded: scale/count/wavelength params fall back
//     to AS2 defaults (or safe floors), amplitudes/speeds/alphas stay literal.
//   * All per-pixel loops are bounded <= 8 iterations; heavy motifs are
//     analytic (rings, diamonds, capsules, octagons) not ray-marched.
//   * fwidth-based AA: assumes caller evaluates in pixel shader quads.
//   * No textures, no discard, no cbuffer/main/SV_* -- helpers only.
//   * Root owns bounding expansion (<=512 world px per side), blend state and
//     endpoint lens spots; helpers emit modest local glow only.
// ============================================================================

#ifndef RAY_STYLES_HLSL
#define RAY_STYLES_HLSL

static const float RAY_PI      = 3.141592653589793;
static const float RAY_TAU     = 6.283185307179586;
static const float RAY_DEG2RAD = 0.0174532925199433;
static const float RAY_EIGHTH  = 0.7853981633974483;  // PI/4

// ---------------------------------------------------------------------------
// small utilities
// ---------------------------------------------------------------------------

// scalar hash -> [0,1)  (David Hoskins style; stable for any seed magnitude)
float RayHash11(float p)
{
    p = frac(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return frac(p);
}

// kinked lightning polyline: LINEAR interp between hashed breakpoints -> sharp
// zigzag corners (Tesla arc look). Returns [-1,1).
float RayJag(float x, float s)
{
    float i = floor(x);
    float f = frac(x);
    float a = RayHash11(i + s * 61.7);
    float b = RayHash11(i + 1.0 + s * 61.7);
    return lerp(a, b, f) * 2.0 - 1.0;
}

// smooth value noise 1D -> [-1,1)
float RayNoise1(float x, float s)
{
    float i = floor(x);
    float f = frac(x);
    float a = RayHash11(i + s * 17.31);
    float b = RayHash11(i + 1.0 + s * 17.31);
    float uu = f * f * (3.0 - 2.0 * f);
    return lerp(a, b, uu) * 2.0 - 1.0;
}

// unpack RGB24 carried in a float channel -> float3 [0,1]
float3 RayRgb24(float c)
{
    // Every authored RGB24 integer is exactly representable by float32.
    // Adding 0.5 above 2^23 rounds odd values up (FF00FF -> FF0100), losing blue.
    uint packed = (uint)clamp(c, 0.0, 16777215.0);
    return float3((packed >> 16) & 255u, (packed >> 8) & 255u, packed & 255u) * (1.0 / 255.0);
}

// select palette entry i of 7 (i pre-clamped 0..6)
float3 RayPal7(int i, float3 c0, float3 c1, float3 c2, float3 c3,
               float3 c4, float3 c5, float3 c6)
{
    if (i <= 0) return c0;
    if (i == 1) return c1;
    if (i == 2) return c2;
    if (i == 3) return c3;
    if (i == 4) return c4;
    if (i == 5) return c5;
    return c6;
}

// AA'd hard stroke coverage: |d| <= hw -> 1, feathered over aa
float RayBand(float d, float hw, float aa)
{
    return 1.0 - smoothstep(hw - aa, hw + aa, abs(d));
}

// interval coverage in the same domain: v inside [lo,hi]
float RaySpan(float v, float lo, float hi, float aa)
{
    return smoothstep(lo - aa, lo + aa, v) * smoothstep(hi + aa, hi - aa, v);
}

// gaussian falloff
float RayGlow(float d, float sigma)
{
    float s = max(sigma, 1e-3);
    return exp(-(d * d) / (2.0 * s * s));
}

// smooth end taper in longitudinal px domain (kills rectangular seam)
float RayEnds(float x, float taperPx, float L)
{
    float tp = max(min(taperPx, L * 0.45), 1e-3);
    return smoothstep(0.0, tp, x) * smoothstep(0.0, tp, L - x);
}

// Tesla-style spindle envelope: 0 at both ends, 1 mid
float RaySpindle(float u)
{
    return sin(RAY_PI * saturate(u));
}

// RayVfxManager.generateSinePath envelope: smoothstep margins at 8%/92%
float RayEnv8(float u)
{
    float e = saturate(min(u * 12.5, (1.0 - u) * 12.5));
    return e * e * (3.0 - 2.0 * e);
}

// Spectrum flat-top envelope: 1 in the middle, sin(pi/2) rise within tr of ends
float RayEnvFlatTop(float u, float tr)
{
    float m = min(saturate(u), saturate(1.0 - u));
    if (m >= tr) return 1.0;
    return sin((m / max(tr, 1e-4)) * (RAY_PI * 0.5));
}

// distance from p to segment a-b (2D, beam-space px)
float RaySdSeg(float2 p, float2 a, float2 b)
{
    float2 pa = p - a;
    float2 ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-6));
    return length(pa - ba * h);
}

// regular-octagon boundary radius in unit space at local angle phi
// (vertices at phi = k*PI/4; circumradius 1, apothem cos(PI/8)=0.9239)
float RayOctRadius(float phi)
{
    float b = frac(phi / RAY_EIGHTH + 8.0) * RAY_EIGHTH - RAY_EIGHTH * 0.5;
    return 0.9238795325 / cos(b);
}

// positive-only frac (wraps negatives into [0,1))
float RayWrap(float v)
{
    float f = frac(v);
    return (f < 0.0) ? f + 1.0 : f;
}

// shared per-ray context
struct RayCtx
{
    float2 q;    // (u 0..1, v signed px)
    float  L;    // segment length px
    float  W;    // nominal full core width px
    float  x;    // = q.x * L  (longitudinal px)
    float  t;    // ageTicks (30 Hz)
    float  sd;   // hashed seed [0,1)
    float  aaU;  // longitudinal AA width in u units
    float  aaX;  // longitudinal AA width in px
    float  aaY;  // transverse AA width in px
    float3 cA;   // primary
    float3 cB;   // secondary
    float4 meta; // intensity and style-specific metadata; wire is unchanged
    float life;  // bagua burst duration (other styles do not consume it)
    float rawSeed; // bagua packs authored spine RGB24 here; others retain seed
};

// accumulate helper: rgb = emissive energy (additive-ready), a = coverage
void RayAcc(inout float3 rgb, inout float a, float3 col, float cov, float alpha)
{
    float w = cov * alpha;
    rgb += col * w;
    a += w;
}

)hlsl"
R"hlsl(
float4 RayOut(float3 rgb, float a, float endFade)
{
    float opacity=saturate(a*endFade);
    return float4(opacity>0.00001 ? rgb*endFade/opacity : float3(0,0,0),opacity);
}

// ===========================================================================
// style 0 -- tesla : coherent discharge channel, filaments and attached forks
//   p0 = (jitterPx, segmentLength, branchCount, branchProbability)
//   p1 = (shimmerAmp, shimmerFreq, forkThicknessMul, shotAge) -- ABI 12
// ===========================================================================
float RayTeslaFlow(float node, float seed, float time)
{
    // A channel keeps its identity between shots. Local noise evolves over four
    // game ticks; replacing every point every tick looked like unrelated wires.
    float beat = floor(time * 0.25);
    float f = frac(time * 0.25); f = f * f * (3.0 - 2.0 * f);
    float a = RayHash11(node * 7.13 + seed * 61.7 + beat * 19.31);
    float b = RayHash11(node * 7.13 + seed * 61.7 + (beat + 1.0) * 19.31);
    return lerp(a, b, f) * 2.0 - 1.0;
}

float2 RayTeslaNode(float node, float count, float L, float jitter, float seed, float time)
{
    float u = node / count;
    if (node > 0.0 && node < count)
        u += (RayHash11(node + seed * 43.7) - 0.5) * 0.8 / count;
    float wide = node * 0.25;
    float spine = lerp(RayTeslaFlow(floor(wide), seed + 5.7, time * 0.65),
                       RayTeslaFlow(floor(wide) + 1.0, seed + 5.7, time * 0.65), frac(wide));
    float fine = RayTeslaFlow(node, seed, time);
    float off = (spine * 1.05 + fine * 0.65) * jitter * sin(RAY_PI * saturate(u));
    if (node <= 0.0 || node >= count) off = 0.0;
    return float2(u * L, off);
}

// Only adjacent longitudinal segments can enter this local stroke footprint.
// Euclidean capsule distance keeps oblique lightning as thin as axial strokes;
// vertical distance to y(x) made steep pieces into bright, broad slabs.
float RayTeslaMainD(RayCtx C, float jitter, float count, float seed)
{
    float first = clamp(floor(C.q.x * count) - 1.0, 0.0, count - 1.0);
    float2 A = RayTeslaNode(first, count, C.L, jitter, seed, C.t);
    float d = 1e5;
    [unroll] for (int j = 0; j < 3; j++) {
        float next = min(first + (float)j + 1.0, count);
        float2 B = RayTeslaNode(next, count, C.L, jitter, seed, C.t);
        d = min(d, RaySdSeg(float2(C.x, C.q.y), A, B)); A = B;
    }
    return d;
}

float2 RayTeslaForkNode(float node, float count, float2 start, float endU,
                        float L, float jitter, float seed, float time)
{
    float localU = node / count;
    if (node > 0.0 && node < count)
        localU += (RayHash11(node + seed * 31.1) - 0.5) * 0.8 / count;
    float u = lerp(start.x / L, endU, localU);
    float off = RayTeslaFlow(node * 1.3, seed + 2.1, time) * jitter * sin(RAY_PI * u);
    float y = lerp(start.y, off, smoothstep(0.0, 0.65, localU));
    return node <= 0.0 ? start : float2(u * L, y);
}

float4 RayShadeTesla(RayCtx C, float4 p0, float4 p1)
{
    float intensity = clamp(C.meta.x, 0.0, 2.0);
    float strike = exp(-max(p1.w, 0.0) * 0.9);
    float widthEnvelope = 1.08 + 0.25 * sin(C.q.x * 27.0 - C.t * 0.6 + C.sd * 13.0);
    float W = C.W * intensity * widthEnvelope * (1.0 + strike * 0.35);
    float jitter = clamp(p0.x, 0.0, 160.0) * intensity;
    // Fine kinks ride the slower spine. Local segment lookup stays three taps,
    // so longer/more detailed channels do not add a whole-path pixel loop.
    float segL = max(p0.y * 0.55, 12.0);
    float count = max(2.0, ceil(C.L / segL));
    int branches = (int)clamp(floor(p0.z), 0.0, 8.0);
    float seed = C.sd * 37.7;
    float dMain = RayTeslaMainD(C, jitter, count, seed);
    float dSecond = 1e5;
    if (branches >= 2) dSecond = RayTeslaMainD(C, jitter * 1.15, count, seed + 19.71);
    float dFork = 1e5;
    // Keep the existing native density ceiling: two mains and up to two forks.
    [unroll] for (int f = 0; f < 2; f++) {
        float hs = seed + (float)f * 13.31 + floor((C.t + 1.5) * 0.125) * 17.1;
        if (f < branches - 2 && RayHash11(hs + 8.9) <= saturate(p0.w)) {
            bool second = RayHash11(hs + 2.3) > 0.5;
            float parentSeed = second ? seed + 19.71 : seed;
            float node = 1.0 + floor(RayHash11(hs + 3.1) * (count - 1.0));
            float2 start = RayTeslaNode(node, count, C.L, jitter * (second ? 1.15 : 1.0), parentSeed, C.t);
            float endU = min(start.x / C.L + 0.15 + 0.15 * RayHash11(hs + 5.7), 0.95);
            if (endU > start.x / C.L) {
                float span = endU * C.L - start.x;
                float forkCount = max(2.0, ceil(span / (max(segL * 0.8, 20.0) * 0.8)));
                float first = clamp(floor((C.x - start.x) / span * forkCount) - 1.0, 0.0, forkCount - 1.0);
                float2 A = RayTeslaForkNode(first, forkCount, start, endU, C.L, jitter, hs, C.t);
                [unroll] for (int j = 0; j < 3; j++) {
                    float2 B = RayTeslaForkNode(min(first + (float)j + 1.0, forkCount), forkCount,
                                               start, endU, C.L, jitter, hs, C.t);
                    dFork = min(dFork, RaySdSeg(float2(C.x, C.q.y), A, B)); A = B;
                }
            }
        }
    }
    float aa = max(C.aaX, C.aaY);
    float3 rgb = 0.0; float a = 0.0;
    float ends = RayEnds(C.x, aa, C.L);
    float haloWidth = max(W * 3.8, aa * 1.5);
    float halo = exp(-dMain * dMain / (haloWidth * haloWidth));
    float filament = 0.60 + 0.25 * sin(C.q.x * 41.0 + C.t * 0.8 + seed);
    // The cyan electrical palette gets a cooler corona, while non-electrical
    // custom warm palettes retain their authored hue. The hot core stays cB.
    float cool = saturate(min(C.cA.g, C.cA.b) - C.cA.r);
    float3 corona = lerp(C.cA, float3(0.18, 0.28, 1.0), cool * 0.72);
    RayAcc(rgb, a, corona, halo, 0.38 * ends);
    RayAcc(rgb, a, lerp(C.cA, corona, 0.5), RayBand(dMain, W * 1.65, aa * 1.2), 0.50 * ends);
    RayAcc(rgb, a, lerp(C.cA, C.cB, 0.30), RayBand(dMain, W * 0.82, aa), 0.90 * ends);
    RayAcc(rgb, a, C.cB, RayBand(dMain, W * 0.32, aa * 0.65), (1.05 + strike * 0.25) * ends);
    RayAcc(rgb, a, corona, RayBand(dSecond, W * 1.5, aa * 1.4), 0.32 * ends);
    RayAcc(rgb, a, lerp(C.cA, C.cB, 0.55), RayBand(dSecond, W * 0.27, aa * 0.7), filament * ends);
    float forkWidth = W * clamp(p1.z, 0.15, 1.5);
    float forkPulse = sin(RAY_PI * frac((C.t + 1.5) * 0.125));
    RayAcc(rgb, a, C.cA, RayBand(dFork, forkWidth, aa), 0.38 * forkPulse * ends);
    RayAcc(rgb, a, C.cB, RayBand(dFork, forkWidth * 0.23, aa * 0.65), 0.70 * forkPulse * ends);

    // Endpoint corona is decorative. It stays at the supplied muzzle/hit point;
    // no target search, impact placement or damaging reach is inferred here.
    float radius = max(C.W * intensity * (3.0 + strike), aa * 2.0);
    float muzzle = length(float2(C.x * 0.65, C.q.y)) / radius;
    float impact = length(float2((C.x - C.L) * 0.65, C.q.y)) / radius;
    float endGlow = exp(-muzzle * muzzle * 2.0) * 0.30;
    if (C.meta.w > 0.5) endGlow += exp(-impact * impact * 2.0) * 0.55;
    RayAcc(rgb, a, corona, endGlow, 0.75 + strike * 0.35);
    RayAcc(rgb, a, C.cB, exp(-muzzle * muzzle * 10.0), 0.65);
    if (C.meta.w > 0.5) RayAcc(rgb, a, C.cB, exp(-impact * impact * 10.0), 0.95);
    return RayOut(rgb, a, branches > 0 && intensity > 0.0 ? 1.0 : 0.0);
}

// ===========================================================================
// style 1 -- prism : absolutely straight optical beam, shimmer pulse,
//                   dispersion strands, endpoint flares
//   p0 = (shimmerAmp, shimmerFreq, forkThicknessMul, -)
// ===========================================================================
float4 RayShadePrism(RayCtx C, float4 p0)
{
    float shA  = (p0.x != 0.0) ? p0.x : 0.25;
    float tick = floor(C.t);
    float pulse = clamp(1.0 + shA * (RayHash11(tick * 1.71 + C.sd * 13.1)
                                     * 2.0 - 1.0), 0.3, 2.0);
    float wp = C.W * pulse;
    float v = C.q.y;
    float d = abs(v);

    float3 rgb = 0.0;
    float a = 0.0;
    // halo 4.5x a20 -> sheath 2x a60 -> white core 0.8x a100
    RayAcc(rgb, a, C.cA, RayGlow(d, wp * 2.2 + 1.0), 0.20 * pulse);
    RayAcc(rgb, a, C.cB, RayBand(d, wp * 1.0, C.aaY * 2.0), 0.55 * pulse);
    RayAcc(rgb, a, float3(1, 1, 1), RayBand(d, wp * 0.4, C.aaY), pulse);

    // prismatic dispersion strands: <=2 ultra-thin diverging lines (seed-stable)
    for (int i = 0; i < 2; i++) {
        float hs = C.sd * 57.1 + (float)i * 17.7;
        if (RayHash11(hs) < 0.4) continue;                  // ~60% presence
        float dst = (RayHash11(hs + 2.2) * 2.0 - 1.0) * wp * 1.5;
        float ds = RayBand(v - saturate(C.q.x) * dst, wp * 0.12 + 0.4, C.aaY);
        RayAcc(rgb, a, C.cB, ds, 0.45);
    }

    // endpoint flares: small at nozzle, larger at hit point
    float dx0 = C.x, dx1 = C.x - C.L;
    float r0 = wp * 2.7 + 1.0;
    float r1 = r0 * 1.3;
    RayAcc(rgb, a, C.cA, exp(-(dx0 * dx0 + v * v) / (r0 * r0)), 0.30 * pulse);
    RayAcc(rgb, a, C.cB, exp(-(dx1 * dx1 + v * v) / (r1 * r1)), 0.45 * pulse);

    float ef = RayEnds(C.x, max(2.5, C.aaX * 2.0), C.L);
    return RayOut(rgb, a, ef);
}

// ===========================================================================
// style 2 -- radiance : breathing golden beam, low-freq sinusoidal sway,
//                       flowing radiance ripple
//   p0 = (shimmerAmp, shimmerFreq, forkThicknessMul, -)
// ===========================================================================
float4 RayShadeRadiance(RayCtx C, float4 p0)
{
    float shA = (p0.x != 0.0) ? p0.x : 0.10;
    float shF = (p0.y != 0.0) ? p0.y : 0.08;
    float ph  = sin(C.t * shF * RAY_TAU + C.sd * RAY_TAU);
    float breath = 1.0 + shA * ph;
    // AS2 path sway: shimmerAmp*10 * spindle * same phase term
    float off = shA * 10.0 * RaySpindle(C.q.x) * ph;
    float d = abs(C.q.y - off);
    // slow brightness wave flowing along the beam
    float flow = 1.0 + 0.15 * sin(C.x * (RAY_TAU / 90.0) - C.t * 0.9
                                  + C.sd * 6.0);

    float3 rgb = 0.0;
    float a = 0.0;
    // halo 5x a20 -> main 1.5x a90 -> core 0.5x a100 (secondary)
    RayAcc(rgb, a, C.cA, RayGlow(d, C.W * 2.5 + 1.0), 0.20 * breath);
    RayAcc(rgb, a, C.cB, RayGlow(d, C.W * 1.0), 0.22 * breath);
    RayAcc(rgb, a, C.cA, RayBand(d, C.W * 0.75, C.aaY * 2.0),
           0.85 * breath * flow);
    RayAcc(rgb, a, C.cB, RayBand(d, C.W * 0.25, C.aaY), breath);
    float ef = RayEnds(C.x, max(3.0, C.aaX * 2.0), C.L);
    return RayOut(rgb, a, ef);
}

// ===========================================================================
// styles 3/4 -- spectrum & resonance : braided palette strands + white axis
//   p0 = (stripeCount, paletteScrollSpeed, distortAmp, distortWaveLen)
//   p1 = (paletteCount, pal0, pal1, pal2)  p2 = (pal3..pal6)  RGB24 packed
)hlsl"
R"hlsl(
//   spectrum : long-wave weave, flat-top envelope, per-strand white core
//   resonance: short-wave dense DNA weave, pow(spindle,0.8), thicker strands
// ===========================================================================
float4 RayShadeBraid(RayCtx C, float4 p0, float4 p1, float4 p2, int isReso)
{
    float nF    = (p0.x >= 1.0) ? p0.x : (isReso ? 5.0 : 3.0);
    int   n     = (int)clamp(floor(nF), 1.0, isReso ? 6.0 : 4.0);
    float spd   = p0.y;                                   // 0 = static ok
    float amp   = isReso ? ((p0.z > 0.0) ? p0.z : 8.0)
                         : ((p0.z < 6.0) ? 8.0 : p0.z);   // AS2 floor 6->8
    float wl    = isReso ? ((p0.w < 20.0) ? 80.0 : p0.w)
                         : ((p0.w < 150.0) ? 250.0 : p0.w);

    // palette: up to 7 packed RGB24, fallback = AS2 cold defaults
    int pc = (int)clamp(floor(p1.x + 0.5), 0.0, 7.0);
    float3 c0 = RayRgb24(p1.y), c1 = RayRgb24(p1.z), c2 = RayRgb24(p1.w);
    float3 c3 = RayRgb24(p2.x), c4 = RayRgb24(p2.y), c5 = RayRgb24(p2.z),
           c6 = RayRgb24(p2.w);
    if (pc < 1) {
        pc = 3;
        c0 = float3(1.0, 0.0, 1.0);                       // 0xFF00FF
        c1 = float3(0.0, 1.0, 1.0);                       // 0x00FFFF
        c2 = float3(0.0, 0.4, 1.0);                       // 0x0066FF
    }
    int scroll = (int)floor(C.t * spd * 0.1);

    float u = C.q.x, v = C.q.y;
    float env = isReso ? pow(max(RaySpindle(u), 0.0), 0.8)
                       : RayEnvFlatTop(u, min(30.0 / C.L, 0.45));
    float timeTerm = C.t * spd * (isReso ? 0.015 : 0.05);

    // nearest strand: distance + its palette color
    float bestD = 1e5;
    float3 strandC = C.cA;
    for (int i = 0; i < 8; i++) {
        if (i >= n) break;
        float fi = (float)i;
        float ampI = amp * (isReso ? (0.7 + 0.3 * sin(fi * 137.5))
                                   : (0.8 + 0.3 * sin(fi * 137.5)));
        float wlI  = wl * (isReso ? 1.0 : (0.8 + 0.3 * cos(fi * 42.1)));
        float ang  = (C.x / wlI) * RAY_TAU - timeTerm
                   + fi * (RAY_TAU / (float)n) + C.sd * RAY_TAU;
        float di = abs(v - ampI * env * sin(ang));
        if (di < bestD) {
            bestD = di;
            float paletteIndex = (float)(i + scroll);
            int idx = (int)clamp(paletteIndex - floor(paletteIndex / (float)pc) * (float)pc, 0.0, (float)(pc - 1));
            strandC = RayPal7(idx, c0, c1, c2, c3, c4, c5, c6);
        }
    }

    float W = C.W;
    float3 rgb = 0.0;
    float a = 0.0;
    // underglow: deep violet outer + cyan inner (LOD0 layers, kept modest)
    RayAcc(rgb, a, isReso ? float3(0.53, 0.0, 1.0) : float3(0.33, 0.0, 1.0),
           RayGlow(abs(v), W * 3.2), 0.12);
    RayAcc(rgb, a, float3(0.0, 1.0, 1.0), RayGlow(abs(v), W * 1.4), 0.16);
    // braided strands: colored glow + body (+ thin white core on spectrum)
    RayAcc(rgb, a, strandC, RayGlow(bestD, W * (isReso ? 0.9 : 0.75)), 0.35);
    RayAcc(rgb, a, strandC, RayBand(bestD, W * (isReso ? 0.40 : 0.30),
                                    C.aaY * 1.5), isReso ? 0.80 : 0.70);
    RayAcc(rgb, a, float3(1, 1, 1),
           RayBand(bestD, W * (isReso ? 0.16 : 0.10), C.aaY),
           isReso ? 0.55 : 0.80);
    // straight aurora axis: pale inner wash + white core
    RayAcc(rgb, a, float3(0.87, 0.93, 1.0),
           RayBand(abs(v), W * (isReso ? 0.75 : 0.60), C.aaY), 0.55);
    RayAcc(rgb, a, float3(1, 1, 1), RayBand(abs(v), W * 0.3, C.aaY), 0.9);
    float ef = RayEnds(C.x, max(3.0, C.aaX * 2.0), C.L);
    return RayOut(rgb, a, ef);
}

)hlsl"
R"hlsl(
// Resonance is a sum of independently coloured strands. Selecting just the
// nearest strand creates hard colour-cell boundaries at every crossing.
float4 RayShadeResonance(RayCtx C, float4 p0, float4 p1, float4 p2)
{
    int n = (int)clamp(floor(p0.x), 1.0, 6.0);
    float amp = max(p0.z, 0.0), wl = max(p0.w, 1.0);
    float W = C.W * clamp(C.meta.x, 0.0, 2.0);
    int pc = (int)clamp(floor(p1.x + 0.5), 1.0, 7.0);
    float3 c0 = RayRgb24(p1.y), c1 = RayRgb24(p1.z), c2 = RayRgb24(p1.w);
    float3 c3 = RayRgb24(p2.x), c4 = RayRgb24(p2.y), c5 = RayRgb24(p2.z), c6 = RayRgb24(p2.w);
    bool fork = C.meta.y > 1.5 && C.meta.y < 2.5;
    int scroll = (int)floor(C.t * p0.y * 0.1);
    float u = saturate(C.q.x);
    float spindle = max(sin(RAY_PI * u), 0.0001);
    float env = pow(spindle, 0.8);
    float envSlope = 0.8 * RAY_PI / C.L * cos(RAY_PI * u) * pow(spindle, -0.2);
    float aa = max(C.aaX, C.aaY);
    float3 rgb = 0.0; float a = 0.0;
    int hit = (int)max(C.meta.z, 0.0);
    int forkIndex = (int)((float)hit - floor((float)hit / (float)pc) * (float)pc);
    float3 forkColor = RayPal7(forkIndex, c0, c1, c2, c3, c4, c5, c6);
    RayAcc(rgb, a, fork ? forkColor : float3(0.5333333, 0.0, 1.0),
           RayGlow(abs(C.q.y), W * 2.0), 0.12);
    RayAcc(rgb, a, float3(0.0, 1.0, 1.0), RayGlow(abs(C.q.y), W), 0.20);
    [loop] for (int i = 0; i < 6; i++) {
        if (i < (fork ? 1 : n)) {
            float fi = (float)i;
            float strandAmp = amp * (fork ? 0.5 : (0.7 + 0.3 * sin(fi * 137.5)));
            float phase = C.x / wl * RAY_TAU - C.t * p0.y * 0.015
                        + (fork ? 0.0 : fi * RAY_TAU / (float)n);
            float sn, cs; sincos(phase, sn, cs);
            float off = strandAmp * env * sn;
            float slope = strandAmp * (envSlope * sn + env * cs * RAY_TAU / wl);
            float d = abs(C.q.y - off) * rsqrt(1.0 + slope * slope);
            int rawIndex = i + scroll;
            int paletteIndex = (int)((float)rawIndex - floor((float)rawIndex / (float)pc) * (float)pc);
            float3 color = fork ? forkColor : RayPal7(paletteIndex, c0, c1, c2, c3, c4, c5, c6);
            if (fork) RayAcc(rgb, a, color, RayBand(d, W * 0.75, aa), 0.60);
            else {
                RayAcc(rgb, a, color, RayBand(d, W * 0.8, aa * 1.25), 0.35);
                RayAcc(rgb, a, color, RayBand(d, W * 0.4, aa * 0.8), 0.80);
            }
        }
    }
    if (!fork) RayAcc(rgb, a, float3(0.8666667, 0.9333333, 1.0),
                     RayBand(C.q.y, W * 0.75, aa), 0.60);
    RayAcc(rgb, a, float3(1, 1, 1), RayBand(C.q.y, W * (fork ? 0.3 : 0.25), aa * 0.7), 1.0);
    return RayOut(rgb, a, C.meta.x > 0.0 ? RayEnds(C.x, aa, C.L) : 0.0);
}

)hlsl"
R"hlsl(
// ===========================================================================
// styles 5/7/8 -- wave / vortex / plasma : sine sheath strands around a beam
//   p0 = (waveAmp, waveLen, waveSpeed, pulseAmp)
//   p1 = (pulseRate, hitRippleSize, hitRippleAlpha, -)
// ===========================================================================

// shared sheath strand offset matching generateSinePath
float RaySineOff(float x, float L, float amp, float wl, float spd, float t,
                 float ph, float env, float noiseRatio)
{
    float w = sin((x / wl - t * spd) * RAY_TAU + ph);
    if (noiseRatio > 0.0) {
        w += sin((x / (wl * noiseRatio) - t * spd * 1.5) * RAY_TAU) * 0.25;
    }
    return amp * env * w;
}

// -- style 5 : wave -- RA3 energy beam: fat bloom, faint twin sheath,
//    traveling energy lances (motion-blur capsules), muzzle ball, tip ring
float4 RayShadeWave(RayCtx C, float4 p0, float4 p1)
{
    float amp  = (p0.x > 0.0) ? p0.x : 7.0;
    float wl   = (p0.y > 0.0) ? max(p0.y, 5.0) : 200.0;
    float spd  = p0.z;                                     // 0 = static ok
    float pAmp = (p0.w != 0.0) ? p0.w : 0.12;
    float pRt  = (p1.x != 0.0) ? p1.x : 0.35;
    float ripS = p1.y;
    float ripA = saturate(p1.z * 0.01);

    float u = C.q.x, v = C.q.y, x = C.x;
    float pulse = 1.0 + pAmp * sin(C.t * pRt * RAY_TAU);
    float T = C.W * pulse;
    float env = RayEnv8(u);
    float d = abs(v);

    float3 rgb = 0.0;
    float a = 0.0;
    // L0 triple atmospheric bloom 14x/9x/5x
    RayAcc(rgb, a, C.cA, RayGlow(d, T * 6.0), 0.06);
    RayAcc(rgb, a, C.cA, RayGlow(d, T * 4.0), 0.11);
    RayAcc(rgb, a, C.cB, RayGlow(d, T * 2.2), 0.18);
    // L1 tube fill 3x a25
    RayAcc(rgb, a, C.cA, RayBand(d, T * 1.5, C.aaY * 2.0), 0.22);
    // L2 twin plasma sheath (phase 0 / pi)
    float ang = (x / wl - C.t * spd) * RAY_TAU;
    float o1 = amp * env * sin(ang);
    float o2 = amp * env * sin(ang + RAY_PI);
    float dS = min(abs(v - o1), abs(v - o2));
    RayAcc(rgb, a, C.cA, RayBand(dS, T * 0.8, C.aaY * 2.0), 0.22);
    RayAcc(rgb, a, C.cB, RayBand(dS, T * 0.32, C.aaY), 0.45);
    // L3 core axis 2x a85 + 0.7x white
    RayAcc(rgb, a, C.cB, RayBand(d, T * 1.0, C.aaY), 0.80);
    RayAcc(rgb, a, float3(1, 1, 1), RayBand(d, T * 0.35, C.aaY), 0.95);

    // L4 energy lances: capsules sliding at nodes (k*0.5 + t*spd)*wl
    float space = wl * 0.5;
    float cyc = C.t * spd;
    float k0 = floor((x - cyc * wl) / space);
    for (int j = 0; j < 2; j++) {
        float xk = (k0 + (float)j) * space + cyc * wl;
        float tk = xk / C.L;
        if (tk <= 0.02 || tk >= 0.98) continue;
        float ek = RayEnv8(tk);
        if (ek <= 0.04) continue;
        float hl = wl * 0.45 * ek * 0.5;
        float dxL = max(abs(x - xk) - hl, 0.0);
        float dl = sqrt(dxL * dxL + v * v);
        float r = T * ek;
        RayAcc(rgb, a, C.cA, RayBand(dl, r * 1.5, C.aaY * 2.0), 0.20);
        RayAcc(rgb, a, C.cB, RayBand(dl, r * 0.75, C.aaY), 0.55);
        RayAcc(rgb, a, float3(1, 1, 1), RayBand(dl, r * 0.3, C.aaY), 0.85);
    }

    // muzzle glow ball 3x/1.4x/0.5x
    float md = sqrt(x * x + v * v);
    RayAcc(rgb, a, C.cA, RayBand(md, T * 3.0, C.aaY * 2.0), 0.20);
    RayAcc(rgb, a, C.cB, RayBand(md, T * 1.4, C.aaY), 0.50);
    RayAcc(rgb, a, float3(1, 1, 1), RayBand(md, T * 0.5, C.aaY), 0.90);
    // hit ripple ring at tip
)hlsl"
R"hlsl(
    if (ripS > 0.0 && ripA > 0.0) {
        float rd = sqrt((x - C.L) * (x - C.L) + v * v);
        RayAcc(rgb, a, C.cB,
               RayBand(rd - ripS * pulse * 0.5, 1.5, C.aaY * 2.0), ripA * 0.5);
    }
    float ef = RayEnds(C.x, max(3.0, C.aaX * 2.0), C.L);
    return RayOut(rgb, a, ef);
}

// -- style 6 : thermal -- single sine path, 4-layer heat ramp, width pulse
float4 RayShadeThermal(RayCtx C, float4 p0, float4 p1)
{
    float amp  = (p0.x > 0.0) ? p0.x : 8.0;
    float wl   = (p0.y > 0.0) ? max(p0.y, 5.0) : 40.0;
    float spd  = p0.z;
    float pAmp = (p0.w != 0.0) ? p0.w : 0.20;
    float pRt  = (p1.x != 0.0) ? p1.x : 0.30;
    float ripS = p1.y;
    float ripA = saturate(p1.z * 0.01);

    float u = C.q.x, v = C.q.y, x = C.x;
    float pulse = 1.0 + pAmp * sin(C.t * pRt * RAY_TAU);
    float T = C.W * pulse;
    float env = RaySpindle(u);
    // primary sine + fine turbulence shimmer ("heat ripple")
    float off = amp * env * sin((x / wl - C.t * spd) * RAY_TAU)
              + amp * 0.18 * env
              * sin((x / (wl * 0.37) - C.t * spd * 1.7) * RAY_TAU + 1.3);
    float d = abs(v - off);
    // subtle patchy heat lum
    float lum = 0.92 + 0.16 * RayNoise1(x * 0.05 - C.t * 2.2, C.sd * 9.1);

    float3 rgb = 0.0;
    float a = 0.0;
    // red underglow -> orange body -> secondary->white core
    RayAcc(rgb, a, float3(1.0, 0.05, 0.0), RayGlow(d, T * 3.5), 0.15 * lum);
    RayAcc(rgb, a, C.cA, RayGlow(d, T * 1.8), 0.30 * lum);
    RayAcc(rgb, a, C.cA, RayBand(d, T * 1.0, C.aaY * 1.5), 0.80 * lum);
    RayAcc(rgb, a, lerp(C.cB, float3(1, 1, 1), 0.4),
           RayBand(d, T * 0.25, C.aaY), 0.95 * lum);
    // tip ripple ring
    if (ripS > 0.0 && ripA > 0.0) {
        float rd = sqrt((x - C.L) * (x - C.L) + v * v);
        RayAcc(rgb, a, C.cB, RayBand(rd - ripS * 0.5, 1.5, C.aaY * 2.0),
               ripA * 0.5);
    }
    float ef = RayEnds(C.x, max(3.0, C.aaX * 2.0), C.L);
    return RayOut(rgb, a, ef);
}

// -- style 7 : vortex -- wide twin helix with z-depth shading, axis core
float4 RayShadeVortex(RayCtx C, float4 p0, float4 p1)
{
    float amp  = (p0.x > 0.0) ? p0.x : 12.0;
    float wl   = (p0.y > 0.0) ? max(p0.y, 5.0) : 90.0;
    float spd  = p0.z;
    float pAmp = (p0.w != 0.0) ? p0.w : 0.20;
    float pRt  = (p1.x != 0.0) ? p1.x : 0.30;
    float ripS = p1.y;
    float ripA = saturate(p1.z * 0.01);

    float u = C.q.x, v = C.q.y, x = C.x;
    float pulse = 1.0 + pAmp * sin(C.t * pRt * RAY_TAU);
    float T = C.W * pulse;
    float env = RayEnv8(u);
    float wT = T * 0.75;
    float d = abs(v);

    float3 rgb = 0.0;
    float a = 0.0;
    // straight ambient bloom
    RayAcc(rgb, a, C.cA, RayGlow(d, T * 2.8), 0.14);
    RayAcc(rgb, a, C.cB, RayBand(d, T * 1.25, C.aaY * 2.0), 0.25);
    // twin strands phase 0 / pi, each with z-depth luminance cue
    float ang = (x / wl - C.t * spd) * RAY_TAU;
    for (int i = 0; i < 2; i++) {
        float ph = (i == 0) ? 0.0 : RAY_PI;
        float oi = amp * env * sin(ang + ph);
        float zi = cos(ang + ph);                        // fake depth
        float lumi = 0.30 + 0.70 * (zi * 0.5 + 0.5);
        float di = abs(v - oi);
        RayAcc(rgb, a, C.cA, RayGlow(di, wT * 1.6), 0.30 * lumi);
        RayAcc(rgb, a, C.cB, RayBand(di, wT * 0.75, C.aaY * 1.5), 0.60 * lumi);
        RayAcc(rgb, a, float3(1, 1, 1), RayBand(di, wT * 0.2, C.aaY),
               0.65 * lumi);
    }
    // axis white core (dimmed so crossings stay brightest)
    RayAcc(rgb, a, float3(1, 1, 1), RayBand(d, T * 0.25, C.aaY), 0.70);
    // muzzle glow
    float md = sqrt(x * x + v * v);
    RayAcc(rgb, a, C.cA, RayBand(md, T * 3.5, C.aaY * 2.0), 0.30);
    RayAcc(rgb, a, C.cB, RayBand(md, T * 1.3, C.aaY), 0.60);
    RayAcc(rgb, a, float3(1, 1, 1), RayBand(md, T * 0.55, C.aaY), 0.90);
    if (ripS > 0.0 && ripA > 0.0) {
        float rd = sqrt((x - C.L) * (x - C.L) + v * v);
        RayAcc(rgb, a, C.cB, RayBand(rd - ripS * pulse * 0.5, 1.5, C.aaY * 2.0),
               ripA * 0.55);
    }
    float ef = RayEnds(C.x, max(3.0, C.aaX * 2.0), C.L);
    return RayOut(rgb, a, ef);
}

// -- style 8 : plasma -- tight asymmetric twin helix + 0.37 turbulence,
//    patchy energized ribbon luminance
float4 RayShadePlasma(RayCtx C, float4 p0, float4 p1)
{
    float amp  = (p0.x > 0.0) ? p0.x : 6.0;
    float wl   = (p0.y > 0.0) ? max(p0.y, 5.0) : 60.0;
    float spd  = p0.z;
    float pAmp = (p0.w != 0.0) ? p0.w : 0.15;
    float pRt  = (p1.x != 0.0) ? p1.x : 0.40;
    float ripS = p1.y;
    float ripA = saturate(p1.z * 0.01);

    float u = C.q.x, v = C.q.y, x = C.x;
    float pulse = 1.0 + pAmp * sin(C.t * pRt * RAY_TAU);
    float T = C.W * pulse;
    float env = RayEnv8(u);
    float wT = T * 0.8;
    float d = abs(v);

    float3 rgb = 0.0;
    float a = 0.0;
    // volumetric bloom ladder
    RayAcc(rgb, a, C.cA, RayGlow(d, T * 3.2), 0.10);
    RayAcc(rgb, a, C.cA, RayGlow(d, T * 1.5), 0.22);
    RayAcc(rgb, a, C.cB, RayBand(d, T * 0.75, C.aaY * 1.5), 0.45);
    // asymmetric twin strands + turbulence noise
    for (int i = 0; i < 2; i++) {
        float amI = amp * ((i == 0) ? 1.0 : 0.9);
        float wlI = wl * ((i == 0) ? 1.0 : 1.1);
        float spI = spd * ((i == 0) ? 1.0 : 1.05);
        float ph  = (i == 0) ? 0.0 : RAY_PI * 0.9;
        float oi = RaySineOff(x, C.L, amI, wlI, spI, C.t, ph, env, 0.37);
        // irregular energized ribbon: patchy luminance along u
        float lumi = 0.70 + 0.45 * RayNoise1(x * 0.045 + C.t * 1.8
                                             + (float)i * 7.3, C.sd * 5.7 + i);
        float di = abs(v - oi);
        RayAcc(rgb, a, C.cA, RayGlow(di, wT * 1.1), 0.30 * lumi);
        RayAcc(rgb, a, C.cB, RayBand(di, wT * 0.45, C.aaY), 0.60 * lumi);
    }
    // blinding white axis core with slight turbulence
    float coreLum = 0.9 + 0.15 * RayNoise1(x * 0.09 - C.t * 3.0, C.sd * 3.3);
    RayAcc(rgb, a, float3(1, 1, 1), RayBand(d, T * 0.25, C.aaY), coreLum);
    // muzzle glow
    float md = sqrt(x * x + v * v);
    RayAcc(rgb, a, C.cA, RayBand(md, T * 2.6, C.aaY * 2.0), 0.30);
    RayAcc(rgb, a, C.cB, RayBand(md, T * 1.1, C.aaY), 0.60);
    RayAcc(rgb, a, float3(1, 1, 1), RayBand(md, T * 0.55, C.aaY), 0.90);
    if (ripS > 0.0 && ripA > 0.0) {
        float rd = sqrt((x - C.L) * (x - C.L) + v * v);
        RayAcc(rgb, a, C.cB, RayBand(rd - ripS * pulse * 0.5, 1.5, C.aaY * 2.0),
               ripA * 0.55);
    }
    float ef = RayEnds(C.x, max(3.0, C.aaX * 2.0), C.L);
    return RayOut(rgb, a, ef);
}

// ===========================================================================
// style 9 -- convergence : bezier fin funnel -> pinched spindle beam,
//   cascade mini-sigils + scan cursor, mach pulses, tip sigil/crosshair
//   p0 = (railSpread, convergenceRatio, railCount, nodeCount)
//   p1 = (nodeSpeed, crosshairScale, -, -)
)hlsl"
R"hlsl(
// ===========================================================================
float4 RayShadeConvergence(RayCtx C, float4 p0, float4 p1)
{
    float spread = (p0.x > 0.0) ? min(p0.x, 120.0) : 10.0;
    float ratio  = (p0.y > 0.0) ? p0.y : 0.18;
    int   nR     = (p0.z >= 2.0) ? (int)min(floor(p0.z), 8.0) : 5;
    int   nN     = (p0.w >= 1.0) ? (int)min(floor(p0.w), 8.0) : 6;
    float nSpd   = p1.x;                                     // 0 ok
    float chS    = (p1.y > 0.0) ? p1.y : 0.9;

    float u = C.q.x, v = C.q.y, x = C.x, L = C.L;
    float uu = saturate(u);
    // AS2: focalDist = clamp(dist*ratio, 25, 80) <= dist*0.5
    float fPx = clamp(L * ratio, 25.0, 80.0);
    fPx = min(fPx, L * 0.5);
    float fT = fPx / L;
    float pulse = 1.0 + sin(C.t * 0.9) * 0.06;
    float T = C.W * pulse;

    float3 rgb = 0.0;
    float a = 0.0;
    float3 darkSh = float3(0.0, 0.106, 0.20);              // 0x001B33
    float3 ice    = float3(0.667, 1.0, 1.0);               // 0xAAFFFF

    // ---- nozzle fins: quadratic-bezier wedge petals -> focal point --------
    if (u < fT) {
        float s = u / fT;
        float bez = 2.0 * s * (1.0 - s);                   // B(s) curve factor
        for (int r = 0; r < 8; r++) {
            if (r >= nR) break;
            float oR = (nR > 1) ? (2.0 * (float)r / (float)(nR - 1) - 1.0)
                                : 0.0;
            if (abs(oR) < 0.12) continue;                  // degenerate mid fin
            float finP = 1.0 + sin(C.t * 0.85 + (float)r * 1.7) * 0.12;
            float hi = bez * spread * oR * 1.2 * finP;     // outer edge
            float lo = hi * 0.4;                           // inner edge
            float yl = min(lo, hi), yh = max(lo, hi);
            float cov = smoothstep(yl - C.aaY, yl + C.aaY, v)
                      * smoothstep(yh + C.aaY, yh - C.aaY, v);
            bool outerFin = abs(oR) > 0.6;
            RayAcc(rgb, a, outerFin ? C.cB : C.cA, cov,
                   outerFin ? 0.42 : 0.55);
            // white edge on outer curve
            RayAcc(rgb, a, float3(1, 1, 1),
                   RayBand(v - hi, 0.8, C.aaY), 0.35);
        }
    }

    // ---- spindle-chain beam (pinch at cascade nodes + focal) --------------
    float cascade = clamp(floor(L / 90.0), 1.0, (float)nN);
    float localT = frac(uu * (cascade + 1.0));
    float envS = sin(RAY_PI * localT);                     // pinch at nodes
    float fPinch = smoothstep(0.0, 0.035, abs(uu - fT));   // extra pinch @focal
    float envP = min(envS, fPinch);
    float post = (uu > fT && fT < 0.99) ? (uu - fT) / (1.0 - fT) : 0.0;
    float grow = 1.0 + 0.6 * post;                         // 1.0x -> 1.6x
    // 4-layer hyperbeam (dark sheath -> primary -> ice -> white)
    float wm[4]; float am[4]; float pm[4];
    wm[0] = 4.8; wm[1] = 2.4; wm[2] = 1.1; wm[3] = 0.4;
    am[0] = 0.35; am[1] = 0.60; am[2] = 0.75; am[3] = 0.90;
    pm[0] = 0.55; pm[1] = 0.62; pm[2] = 0.78; pm[3] = 0.88;
    for (int L4 = 0; L4 < 4; L4++) {
        float wL = T * lerp(1.0, 1.6, saturate(post)) * wm[L4]
                 * (pm[L4] + (1.0 - pm[L4]) * envP);
        float3 lc = (L4 == 0) ? darkSh : (L4 == 1) ? C.cA
                              : (L4 == 2) ? ice : float3(1, 1, 1);
        RayAcc(rgb, a, lc, RayBand(v, wL, C.aaY * 2.0), am[L4] * 0.7);
    }

    // ---- cascade mini-sigils + scanning cursor ---------------------------
    float scanSpd = max(0.06, nSpd * 0.8);
    float scanT = RayWrap(C.t * scanSpd);
    float sigma = clamp(0.55 / (cascade + 1.0), 0.035, 0.09);
    for (int j = 0; j < 8; j++) {
        if ((float)j >= cascade) break;
        float tj = ((float)j + 1.0) / (cascade + 1.0);
        float xj = tj * L;
        float dxj = x - xj;
        float envj = sin(RAY_PI * tj);
        float fBoost = exp(-((tj - fT) * (tj - fT)) / 0.03);
        float sz = T * 7.0 * (0.55 + 0.35 * envj + 0.25 * fBoost) * chS;
        if (sz < 2.0) continue;
        float dT = abs(tj - scanT);
        dT = min(dT, 1.0 - dT);
        float w = exp(-(dT * dT) / (sigma * sigma));
        float act = 0.35 + 0.55 * w;
        float rot = C.t * (0.10 + (float)j * 0.05) + (float)j * 2.094;
        float cs = cos(rot), sn = sin(rot);
        float rx = dxj * cs + v * sn;
        float ry = v * cs - dxj * sn;
        // rotating diamond frame
        float dd = abs(rx) + abs(ry) - sz;
        RayAcc(rgb, a, C.cA, RayBand(dd, sz * 0.10 + 0.5, C.aaY), 0.45 * act);
        // aim ring + center dot
        float len = sqrt(dxj * dxj + v * v);
        RayAcc(rgb, a, C.cA, RayBand(len - sz * 0.45, sz * 0.07 + 0.5, C.aaY),
               0.55 * act);
        RayAcc(rgb, a, C.cB, RayBand(len - sz * 0.62, sz * 0.03 + 0.5, C.aaY),
               0.30 * act);
        RayAcc(rgb, a, float3(1, 1, 1), RayBand(len, sz * 0.12, C.aaY), act);
        // axis-aligned split crosshair
        float lw = max(1.0, sz * 0.07);
        float chH = RayBand(v, lw, C.aaY)
                  * RaySpan(abs(dxj), sz * 0.18, sz * 0.6, C.aaX);
        float chV = RayBand(dxj, lw, C.aaX)
                  * RaySpan(abs(v), sz * 0.18, sz * 0.6, C.aaY);
        RayAcc(rgb, a, float3(1, 1, 1), chH + chV, 0.5 * act);
    }
    // scan cursor: bright comet sweeping the beam
    {
        float cx = RayWrap(scanT) * L;
        float cd = sqrt((x - cx) * (x - cx) + v * v);
        float cS = T * 3.2 * chS;
        RayAcc(rgb, a, C.cA, RayGlow(cd, cS), 0.55);
        RayAcc(rgb, a, float3(1, 1, 1), RayBand(cd, cS * 0.15, C.aaY), 0.75);
        // forward arrow streak
        float ax = x - (cx + cS * 0.5);
        RayAcc(rgb, a, C.cB,
               RayBand(v, cS * 0.12, C.aaY)
               * RaySpan(ax, 0.0, cS * 0.7, C.aaX), 0.45);
    }

    // ---- mach pulse cones + faint matrix zigzag (post-focal) --------------
    if (uu > fT && L - fPx > 10.0) {
        float post01 = saturate(post);
        // mach cones: elongated gaussian pulses drifting forward
        for (int m = 0; m < 3; m++) {
            float mT = RayWrap((float)m / 3.0 - C.t * nSpd * 0.8);
            if (mT < 0.05 || mT > 0.95) continue;
            float msc = sin(mT * RAY_PI);
            float mx = fPx + mT * (L - fPx);
            float ex = (x - mx) / (T * 8.0 * msc + 3.0);
            float ey = v / (T * 5.0 * msc + 1.0);
            RayAcc(rgb, a, lerp(C.cB, float3(1, 1, 1), 0.3),
                   exp(-(ex * ex + ey * ey)), 0.35 * msc);
        }
        // matrix circuit: stepped diagonal zigzag, bounded spindle envelope
        float zenv = sin(RAY_PI * post01);
        float step_ = max(L / ((float)nN * 2.0), 12.0);
        float z = frac((x - C.t * (1.25 + nSpd * 2.0) * 10.0) / step_);
        float zoff = T * 4.2 * zenv * (abs(z * 2.0 - 1.0) * 2.0 - 1.0);
        RayAcc(rgb, a, C.cA, RayBand(v - zoff, T * 0.9, C.aaY), 0.28);
)hlsl"
R"hlsl(
        RayAcc(rgb, a, float3(1, 1, 1), RayBand(v - zoff, T * 0.3, C.aaY),
               0.35);
    }

    // ---- focal holo-sigil: dark iris + rotating diamond + crosshair -------
    {
        float dxF = x - fPx;
        float sS = T * 5.5 * chS;
        float rotF = C.t * 0.15;
        float cs = cos(rotF), sn = sin(rotF);
        float rx = dxF * cs + v * sn;
        float ry = v * cs - dxF * sn;
        float lenF = sqrt(dxF * dxF + v * v);
        // iris disc (near-black -- occludes under normal blend, ~free under add)
        RayAcc(rgb, a, float3(0.0, 0.043, 0.10),
               1.0 - smoothstep(sS * 1.5 - C.aaY, sS * 1.5 + C.aaY, lenF), 0.5);
        // shattered diamond frame (two arcs feel)
        float dd = abs(rx) + abs(ry) - sS * 1.6;
        float frame = RayBand(dd, sS * 0.10 + 0.5, C.aaY);
        RayAcc(rgb, a, C.cA, frame, 0.65);
        RayAcc(rgb, a, C.cB, RayBand(lenF - sS * 0.62, sS * 0.05 + 0.5, C.aaY),
               0.4);
        RayAcc(rgb, a, C.cA, RayBand(lenF - sS * 0.45, sS * 0.07 + 0.5, C.aaY),
               0.6);
        float lw = max(1.0, sS * 0.07);
        float chH = RayBand(v, lw, C.aaY)
                  * RaySpan(abs(dxF), sS * 0.18, sS * 0.6, C.aaX);
        float chV = RayBand(dxF, lw, C.aaX)
                  * RaySpan(abs(v), sS * 0.18, sS * 0.6, C.aaY);
        RayAcc(rgb, a, float3(1, 1, 1), chH + chV, 0.75);
        RayAcc(rgb, a, float3(1, 1, 1), RayBand(lenF, sS * 0.12, C.aaY), 0.9);
    }

    // ---- tip shatter crosshair + directional diamond flare ----------------
    {
        float dxE = x - L;
        float sE = T * 5.0 * chS;
        float lenE = sqrt(dxE * dxE + v * v);
        RayAcc(rgb, a, C.cA, RayBand(lenE - sE * 1.8, 1.5, C.aaY), 0.4);
        // directional flares: anisotropic diamonds (|dx|/a + |v|/b = 1)
        float fl1 = RayBand(abs(dxE) / max(sE * 4.0, 1.0)
                            + abs(v) / max(sE * 0.35, 1.0) - 1.0,
                            0.12, C.aaY / max(sE, 1.0));
        float fl2 = RayBand(abs(dxE) / max(sE * 2.8, 1.0)
                            + abs(v) / max(sE * 0.25, 1.0) - 1.0,
                            0.12, C.aaY / max(sE, 1.0));
        RayAcc(rgb, a, C.cA, fl1, 0.65);
        RayAcc(rgb, a, C.cB, fl2, 0.55);
        RayAcc(rgb, a, float3(1, 1, 1), RayBand(lenE, sE * 0.2, C.aaY), 0.9);
        // split cross ticks
        float chH = RayBand(v, 1.2, C.aaY)
                  * RaySpan(abs(dxE), sE * 0.45, sE * 1.3, C.aaX);
        float chV = RayBand(dxE, 1.2, C.aaX)
                  * RaySpan(abs(v), sE * 0.45, sE * 1.3, C.aaY);
        RayAcc(rgb, a, C.cB, chH + chV, 0.7);
    }

    float ef = RayEnds(C.x, max(2.0, C.aaX), C.L);
    return RayOut(rgb, a, ef);
}

// ===========================================================================
// style 10 -- bagua_rod, one authored structure in one pass.
// p0=(count,spacing,radius,compressX), p1=(angVel,counter,phaseOffset,pulseAmp),
// p2=(pulseWidth,idleAlpha,glowAlpha,glowWidthMult).
// meta.yz=nDiagonals/linkerStride, meta.w=mixed RGB24, rawSeed=spine RGB24,
// life=visualDuration. Host lifecycle alpha supplies the one fade-out envelope.
// ===========================================================================
float2 RayBaguaUnit(int k)
{
    k = k & 7;
    if (k == 0) return float2(1,0);
    if (k == 1) return float2(0.7071067812,0.7071067812);
    if (k == 2) return float2(0,1);
    if (k == 3) return float2(-0.7071067812,0.7071067812);
    if (k == 4) return float2(-1,0);
    if (k == 5) return float2(-0.7071067812,-0.7071067812);
    if (k == 6) return float2(0,-1);
    return float2(0.7071067812,-0.7071067812);
}

float RayBaguaBump(float index, float pulseCenter, float pulseWidth)
{
    float d = abs(index - pulseCenter) / max(pulseWidth, 0.001);
    return d < 1.0 ? 0.5 * (1.0 + cos(RAY_PI * d)) : 0.0;
}

struct RayBaguaSlice {
    float x; float radius; float alpha; float bump; float2 rotation;
};
RayBaguaSlice RayBaguaAt(int index, float first, float stride, float radius,
                         float pulseCenter, float burst, float4 p1, float4 p2)
{
    RayBaguaSlice s = (RayBaguaSlice)0;
    s.x = first + (float)index * stride;
    s.bump = RayBaguaBump((float)index, pulseCenter, p2.x);
    s.radius = max(radius * (1.0 + p1.w * s.bump), 0.0);
    s.alpha = lerp(saturate(p2.y * 0.01), 1.0, s.bump);
    float direction = p1.y > 0.5 && (index & 1) == 1 ? -1.0 : 1.0;
    float rot = ((float)index * p1.z + direction * p1.x * burst) * RAY_DEG2RAD;
    sincos(rot, s.rotation.y, s.rotation.x);
    return s;
}
float2 RayBaguaVertex(RayBaguaSlice s, int k, float compressX)
{
    float2 unit = RayBaguaUnit(k);
    float2 rotated = float2(unit.x * s.rotation.x - unit.y * s.rotation.y,
                            unit.x * s.rotation.y + unit.y * s.rotation.x);
    return float2(s.x + rotated.x * s.radius * compressX, rotated.y * s.radius);
}

float4 RayShadeBagua(RayCtx C, float4 p0, float4 p1, float4 p2)
{
    int count = (int)clamp(floor(p0.x), 1.0, 8.0);
    float spacing = max(p0.y, 0.0);
    float intensity = clamp(C.meta.x, 0.0, 2.0);
    float radius = max(p0.z, 0.0) * intensity;
    float compressX = p0.w;
    float W = C.W * intensity;
    float aa = max(C.aaX, C.aaY);
    float stack = (float)(count - 1) * spacing;
    float stride = stack <= C.L ? spacing : C.L / max((float)(count - 1), 1.0);
    float first = stack <= C.L ? (C.L - stack) * 0.5 : 0.0;
    float last = first + (float)(count - 1) * stride;
    // AS2's pulse runs exactly once, then both rotation and pulse freeze while
    // lifecycle alpha fades. A modulo clock restarts the burst halfway through.
    float burst = min(C.t, max(C.life - 1.0, 0.0));
    float pulseCenter = -0.5 + burst / max(C.life - 1.0, 1.0) * (float)count;
    float maximumBump = RayBaguaBump(clamp(floor(pulseCenter + 0.5), 0.0, (float)(count - 1)),
                                    pulseCenter, p2.x);
    float maximumAlpha = lerp(saturate(p2.y * 0.01), 1.0, maximumBump);
    float3 mixed = RayRgb24(C.meta.w), spine = RayRgb24(C.rawSeed);
    float2 P = float2(C.x, C.q.y);
    float3 rgb = 0.0; float a = 0.0;
    RayAcc(rgb, a, spine, RayBand(RaySdSeg(P,float2(first,0),float2(last,0)), W * 0.7, aa),
           0.45 + 0.40 * maximumAlpha);

    float maxRadius = radius * (1.0 + max(p1.w, 0.0));
    float glowHalf = W * max(p2.w, 0.0) * 0.5;
    float reachX = maxRadius * abs(compressX) + max(glowHalf, W) + aa * 2.0;
    float reachY = maxRadius + max(glowHalf, W) + aa * 2.0;
    int linkerStride = (int)clamp(floor(C.meta.z), 1.0, 8.0);
    // Cheap per-pair bounds avoid evaluating all 56 links over the entire quad.
    // Include each pair's projected ring extent, not merely floor(x/stride):
    // rotating vertices cross their slice centres and overlap adjacent cells.
    [loop] for (int li = 0; li < 7; li++) {
        float left = first + (float)li * stride;
        if (li < count - 1 && P.x >= left - reachX && P.x <= left + stride + reachX && abs(P.y) <= reachY) {
            RayBaguaSlice A = RayBaguaAt(li,first,stride,radius,pulseCenter,burst,p1,p2);
            RayBaguaSlice B = RayBaguaAt(li+1,first,stride,radius,pulseCenter,burst,p1,p2);
            float linkAlpha = min(A.alpha, B.alpha) * 0.70;
            [loop] for (int k = 0; k < 8; k += linkerStride) {
                float d = RaySdSeg(P, RayBaguaVertex(A,k,compressX), RayBaguaVertex(B,k,compressX));
                // side=dot(uncompressedVertex,(-sin(rot),cos(rot))) >= 0;
                // rotation cancels, so corresponding vertices keep their pole.
                RayAcc(rgb, a, k <= 4 ? C.cA : C.cB, RayBand(d, W * 0.35, aa), linkAlpha);
            }
        }
    }

)hlsl"
R"hlsl(
    int diagonals = (int)clamp(floor(C.meta.y), 0.0, 4.0);
    int diagonalStride = diagonals > 0 ? max(1, (int)floor(4.0 / (float)diagonals)) : 4;
    [loop] for (int si = 0; si < 8; si++) {
        float center = first + (float)si * stride;
        if (si < count && abs(P.x - center) <= reachX && abs(P.y) <= reachY) {
            RayBaguaSlice S = RayBaguaAt(si,first,stride,radius,pulseCenter,burst,p1,p2);
            if (S.alpha >= 0.03) {
                // Distances are measured after horizontal compression. The old
                // normalized radial approximation made near-vertical edges half
                // as thick and hid the authored warm/dark edge boundaries.
                float3 edgeD = float3(1e5,1e5,1e5); // warm, dark, cross-pole
                [unroll] for (int k = 0; k < 8; k++) {
                    float d = RaySdSeg(P,RayBaguaVertex(S,k,compressX),RayBaguaVertex(S,k+1,compressX));
                    if (k < 4) edgeD.x = min(edgeD.x,d);
                    else if (k == 5 || k == 6) edgeD.y = min(edgeD.y,d);
                    else edgeD.z = min(edgeD.z,d);
                }
                float glowAlpha = max(p2.z,0.0) * 0.01 * (1.0 + p1.w * S.bump * 1.5) * S.alpha;
                RayAcc(rgb, a, C.cA, RayBand(edgeD.x,glowHalf,aa * 1.2), glowAlpha);
                RayAcc(rgb, a, C.cA, RayBand(edgeD.x,W * 0.5,aa), S.alpha);
                RayAcc(rgb, a, C.cB, RayBand(edgeD.y,W * 0.5,aa), S.alpha);
                RayAcc(rgb, a, mixed, RayBand(edgeD.z,W * 0.5,aa), S.alpha);
                [loop] for (int dk = 0; dk < 4; dk += diagonalStride) {
                    if (diagonals > 0) {
                        float d = RaySdSeg(P,RayBaguaVertex(S,dk,compressX),RayBaguaVertex(S,dk+4,compressX));
                        RayAcc(rgb, a, C.cA, RayBand(d,W * 0.375,aa), S.alpha * 0.90);
                    }
                }
            }
        }
    }
    // First/last complete gates are intentionally allowed beyond the beam's
    // endpoints, just like the authored AS2 geometry. They are not RayEnds-clipped.
    return RayOut(rgb, a, intensity > 0.0 ? 1.0 : 0.0);
}

// ===========================================================================
// generic fallback: soft straight beam (unknown style)
// ===========================================================================
float4 RayShadeFallback(RayCtx C)
{
    float d = abs(C.q.y);
    float3 rgb = 0.0;
    float a = 0.0;
    RayAcc(rgb, a, C.cA, RayGlow(d, C.W * 2.0), 0.25);
    RayAcc(rgb, a, C.cA, RayBand(d, C.W * 0.5, C.aaY), 0.85);
    RayAcc(rgb, a, C.cB, RayBand(d, C.W * 0.2, C.aaY), 0.95);
    float ef = RayEnds(C.x, max(2.0, C.aaX), C.L);
    return RayOut(rgb, a, ef);
}

// ===========================================================================
// public dispatch
// ===========================================================================
float4 ShadeRayStyle(uint style, float2 q, float lengthWorld, float widthWorld,
                     float ageTicks, float seed, float3 primary,
                     float3 secondary, float4 p0, float4 p1, float4 p2,
                     float4 meta, float life)
{
    RayCtx C = (RayCtx)0;
    C.q = q;
    C.L = max(lengthWorld, 1.0);
    C.W = max(widthWorld, 0.75);
    C.x = q.x * C.L;
    C.t = ageTicks;
    C.sd = RayHash11(seed * 0.977 + 0.31);
    C.aaU = max(fwidth(q.x), 1e-5);
    C.aaX = max(fwidth(C.x), 0.30);
    C.aaY = max(fwidth(q.y), 0.30);
    C.cA = primary;
    C.cB = secondary;
    C.meta = meta;
    C.life = life;
    C.rawSeed = seed;

    // Single exit avoids FXC's inlined-return initialization ambiguity under ps_4_0 /WX.
    float4 result=float4(0,0,0,0);
    if (style == 0u) result=RayShadeTesla(C, p0, p1);
    else if (style == 1u) result=RayShadePrism(C, p0);
    else if (style == 2u) result=RayShadeRadiance(C, p0);
    else if (style == 3u) result=RayShadeBraid(C, p0, p1, p2, 0);
    else if (style == 4u) result=RayShadeResonance(C, p0, p1, p2);
    else if (style == 5u) result=RayShadeWave(C, p0, p1);
    else if (style == 6u) result=RayShadeThermal(C, p0, p1);
    else if (style == 7u) result=RayShadeVortex(C, p0, p1);
    else if (style == 8u) result=RayShadePlasma(C, p0, p1);
    else if (style == 9u) result=RayShadeConvergence(C, p0, p1);
    else if (style == 10u) result=RayShadeBagua(C, p0, p1, p2);
    else if (style == 42u) result=float4(0,0,0,0); // retired duplicate Bagua pass
    else result=RayShadeFallback(C);
    return result;
}

#endif // RAY_STYLES_HLSL

)hlsl"
