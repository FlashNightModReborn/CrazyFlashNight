R"hlsl(
// ============================================================================
// flame.hlsl -- procedural flame-stream shading for the bullet-ray compositor.
//
// Shader Model 4.0 (ps_4_0) helper library only:
//   * no entry point, no cbuffers, no SV semantics, no textures, no discard
//   * root owns rasterization, camera transform and blending
//
// float4 ShadeFlame(q, lengthWorld, widthWorld, ageTicks, seed,
//                   primary, secondary, p0, p1, p2)
//   returns straight (non-premultiplied) RGB + alpha.
//   q.x    normalized axis progress (0 = muzzle, 1 = end; small margins ok)
//   q.y    signed transverse distance, world pixels
//   ageTicks 30 Hz game ticks (ageTicks / 30 = seconds)
//   seed   stable per-arc seed; all animation is positional, never frame-based
//   p0 = (waveAmp px, waveLen px, waveSpeed rad/tick, pulseAmp)
//   p1 = (pulseRate cyc/tick, tongueCount, tipBloomScale, smokeColorRGB24)
//   p2 = (pulseProgress 0..1, hotPulse, damagePulse, isBlocked)
// All scalar inputs may be zero; short/zero length is handled gracefully.
// ============================================================================

float FlameHash(float2 p)
{
    float3 h = frac(float3(p.xyx) * float3(0.1031, 0.1030, 0.0973));
    h += dot(h, h.yzx + 33.33);
    return frac((h.x + h.y) * h.z);
}

float FlameNoise(float2 p)
{
    float2 i = floor(p);
    float2 f = frac(p);
    float2 g = f * f * (3.0 - 2.0 * f);
    float a = FlameHash(i);
    float b = FlameHash(i + float2(1.0, 0.0));
    float c = FlameHash(i + float2(0.0, 1.0));
    float d = FlameHash(i + float2(1.0, 1.0));
    return lerp(lerp(a, b, g.x), lerp(c, d, g.x), g.y);
}

// Three octaves (the whole octave budget): the shared turbulence field that
// raggeds the silhouette and breaks the tip.
float FlameFbm(float2 p)
{
    float v = FlameNoise(p) * 0.56;
    v += FlameNoise(p * 2.17 + float2(17.3, -9.2)) * 0.28;
    v += FlameNoise(p * 4.63 + float2(-4.7, 11.9)) * 0.16;
    return v;
}

float3 FlameUnpackRGB(float packed)
{
    float c = max(packed, 0.0);
    float r = floor(c * (1.0 / 65536.0));
    float rem = c - r * 65536.0;
    float g = floor(rem * (1.0 / 256.0));
    return float3(r, g, rem - g * 256.0) * (1.0 / 255.0);
}

float4 ShadeFlame(float2 q, float lengthWorld, float widthWorld,
                  float ageTicks, float seed,
                  float3 primary, float3 secondary,
                  float4 p0, float4 p1, float4 p2)
{
    // Use one exit so FXC can prove initialization when it inlines this helper.
    float4 result = float4(0, 0, 0, 0);
    [unroll] do {
        float w    = max(widthWorld, 1.0e-3);
        float hw0  = w * 0.5;
        float len  = max(lengthWorld, 1.0);         // px
        float u    = q.x;
        float y    = q.y;
        float waveAmp = max(p0.x, 0.0);
        float rimEnd = w * 6.0 + waveAmp;
        [branch] if (abs(y) >= rimEnd) break;
        float tSec = ageTicks * (1.0 / 30.0);

        // Stable per-arc phase, independent of the rendered frame count.
        float s1 = FlameHash(float2(seed * 0.717 + 11.13, seed * 1.319 + 3.77));

        float waveLen   = (p0.y > 1.0) ? p0.y : 120.0;
        float waveSpeed = p0.z;
        float pulseAmp  = clamp(p0.w, -0.6, 0.6);
        float pulseRate = p1.x;
        float tongueK   = saturate(p1.y * 0.2);     // ~1.0 at the authored 5 tongues
        float blocked   = step(0.5, p2.w);

        // Axis meander, matching the AS2 axisOffset shape. It dies out toward the
        // muzzle (u^2) so the stream stays attached. waveFit caps the effective
        // amplitude in proportion to the width.
        float wfreq = clamp(len * 2.0 / waveLen, 4.0, 16.0);
        float waveFit = min(1.0, 2.8 * w / max(waveAmp, 1.0));
        float yAxis = (sin(u * wfreq - ageTicks * waveSpeed + s1 * 6.2832)
                     + 0.35 * sin(u * wfreq * 1.83 + ageTicks * waveSpeed * 0.72
                                  + s1 * 3.1416)) * waveAmp * u * u * 0.5 * waveFit;
        float yl = y - yAxis;

        // Envelope half-width: narrow attached nozzle -> widening cone ->
        // pinched tip, breathing with the authored pulse.
        float grow  = pow(saturate(u),0.72);
        float pinch = smoothstep(0.70, 1.03, u);
        float pulseFactor = max(1.0 + pulseAmp * sin(ageTicks * pulseRate * 6.2832),
                                0.25);
        // Match the authored widening flame cone, rather than treating thickness as a constant ribbon.
        float hw = w * (0.30 + 2.65 * grow) * (1.0 - 0.18 * pinch) * pulseFactor;
        hw = max(hw, hw0 * 0.12);
        float invHw = 1.0 / hw;
        float yN = yl * invHw;
        float e = abs(yl) * invHw;

        float pilePSq = 110.0, pileQSq = 110.0;
        [branch] if (blocked > 0.5) {
            float tipScale = max(p1.z, 0.0);
            float pileR = hw0 * (1.35 + 0.85 * min(tipScale, 2.0));
            float2 pileP = float2((u - 0.985) * len / pileR, yl / (pileR * 0.85));
            float2 pileQ = float2((u - 0.985) * len / (pileR * 0.75) + 0.35,
                                  (yl - (s1 - 0.5) * pileR * 0.8) / (pileR * 0.60));
            pilePSq = dot(pileP, pileP);
            pileQSq = dot(pileQ, pileQ);
        }
        bool nearPile = min(pilePSq, pileQSq) < 9.0;
        // FBM is a convex blend in [0,1]. Leave a small FP32 margin at the edge.
        float edgeWidth = 0.95 + 0.45 * tongueK;
        bool inBody = u > -0.005 && u < 1.0 && e < 1.04 + 0.5 * edgeWidth + 0.0001;
        [branch] if (!inBody && !nearPile) break;

        // Advection along +u: every moving structure travels muzzle -> tip,
        // so time progression keeps the same direction at any shot angle.
        float s2 = FlameHash(float2(seed * 1.913 + 37.71, seed * 0.579 + 7.31));
        float flow = tSec * 1.55 + ageTicks * waveSpeed * 0.06;
        float cells = max(5.0, len / 65.0);
        // Far pile coverage is at most 0.75 * 1.65 * exp(-9). Including that
        // tail, aMax <= 1.0584, primary alpha <= 1 and opacityScale <= 2 put
        // both cutoffs below .0005.
        float tinyBody = (blocked > 0.5) ? 0.00008 : 0.00023;
        float cov = 0.0;
        [branch] if (inBody) {
            float turb = FlameFbm(float2(u * cells - flow * 1.4, yN * 2.0 + s2 * 7.0));
            float edgeCoord = e - (turb - 0.5) * edgeWidth;
            cov = 1.0 - smoothstep(0.62, 1.04, edgeCoord);
            float fadeIn = smoothstep(-0.005, 0.008, u);
            float fadeOut = 1.0 - smoothstep(0.90, 1.0, u);
            [branch] if (!nearPile && cov * fadeIn * fadeOut <= tinyBody)
                break;

            // Breakup can only remove coverage, and tipK is zero through u=.45.
            [branch] if (u > 0.45 && cov > 0.0) {
                float brk = FlameNoise(float2(u * cells*1.5 - flow * 2.0, yN * 2.8 - s1 * 9.0));
                float tipK = smoothstep(0.45, 0.98, u) * (1.0 - blocked * 0.65);
                cov *= 1.0 - tipK * smoothstep(0.28, 0.67, brk);
            }
            cov *= fadeIn;
            cov *= fadeOut;
            [branch] if (!nearPile && cov <= tinyBody) break;
        }

        // Temperature field -> palette below. Coverage-weighted body baseline.
        float pulsePos = saturate(p2.x);
        float hot = saturate(p2.y);
        float damageK = saturate(p2.z);
        float inner = saturate(1.0 - e * 0.9);
        float T = (0.24 + 0.58 * inner) * (0.82 + 0.18 * damageK);

        // Two advected filament layers (the layer budget): slow broad tongues and
        // faster thin streaks sliding at different rates for parallax licking.
        float fil = 0.0;
        [branch] if (u > 0.06 && cov > 0.0) {
            float fa = FlameNoise(float2(u * cells - flow*1.8, yN * 2.2 + s2 * 5.0));
            float fb = FlameNoise(float2(u * cells*2.3 - flow * 3.1, yN * 4.2 - s1 * 6.0));
            float tongueMask = smoothstep(0.06, 0.30, u) * (1.0 - pinch * 0.35);
            fil = (smoothstep(0.42, 0.90, fa) * 0.55
                 + smoothstep(0.50, 0.95, fb) * 0.50)
                * tongueMask * (0.45 + 0.55 * tongueK);
        }
        T += (fil-0.35) * cov * 0.95;

        // Hot core hugging the nozzle, decaying along the axis; hotPulse widens
        // it slightly and raises its temperature.
        float coreAx = 1.0 - smoothstep(0.05, 0.62 - 0.10 * hot, u);
        T += pow(inner, 2.2) * coreAx * (0.55 + 0.45 * hot) * cov;

        // Authored damage pulse: a soft bright band parked at pulseProgress.
        float bandPos = 0.10 + 0.80 * pulsePos;
        float bd = (u - bandPos) * 9.0;
        T += exp(-bd * bd) * inner * (0.18 + 0.42 * hot) * (0.35 + 0.65 * damageK) * cov;

        // Narrow muzzle bloom anchoring the stream to the nozzle (~0.9*hw0 px).
        float2 nozzleP = float2((u + 0.015) * len / (0.90 * hw0),
                                yl / (0.62 * hw0));
        float nozzleSq = dot(nozzleP, nozzleP);
        // exp(-110) rounds to zero in FP32. Keep the smaller but representable
        // temperature and pile tails wherever the pixel can survive clipping.
        [branch] if (nozzleSq < 110.0)
            T += exp(-nozzleSq) * (0.90 + 0.50 * hot);

        // The two blocked-end lobes both contribute when either is in range.
        [branch] if (min(pilePSq, pileQSq) < 110.0) {
            float pile = exp(-pilePSq) + 0.65 * exp(-pileQSq);
            float pilePulse = 0.85 + 0.15 * sin(ageTicks * 0.9 + s2 * 6.2832);
            T += pile * pilePulse * 0.85;
            cov += pile * 0.75;
        }

        // Gentle ember specks riding the flow, kept inside the body and bounds.
        [branch] if (u > 0.25 && inner > 0.0) {
            float emb = FlameNoise(float2(u * 24.0 - flow * 3.6, yN * 3.4 + s2 * 11.0));
            T += smoothstep(0.80, 0.93, emb) * smoothstep(0.25, 0.70, u)
               * cov * inner * 0.45;
        }

        // Temperature -> authored palette: smoke fringe -> deep -> primary body
        // -> secondary -> near-white core.
        float3 smoke = FlameUnpackRGB(p1.w);
        float Tv = saturate(T);
        float3 col = lerp(smoke, primary * 0.45, smoothstep(0.02, 0.22, Tv));
        col = lerp(col, primary,   smoothstep(0.20, 0.50, Tv));
        col = lerp(col, secondary, smoothstep(0.48, 0.78, Tv));
        col = lerp(col, lerp(secondary, float3(1.0, 0.98, 0.88), 0.55),
                   smoothstep(0.78, 0.97, Tv));

        float aMax = 0.98 * lerp(0.88, 1.0, damageK) * (1.0 + 0.08 * hot);
        float alpha = saturate(cov * (0.68 + 0.32 * saturate(T)) * aMax);
        // Hard guarantee of the lateral bound: alpha reaches zero before the
        // quad rim, so nothing can clip into a straight silhouette edge.
        alpha *= 1.0 - smoothstep(w * 5.0 + waveAmp, rimEnd, abs(y));
        result = float4(col, alpha);
    } while (false);
    return result;
}

)hlsl"
