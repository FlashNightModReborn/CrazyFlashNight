#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include "Compositor.h"
#include <d3d11.h>
#include <dxgi1_2.h>
#include <d3dcompiler.h>
#include <dcomp.h>
#include <windows.graphics.capture.interop.h>
#include <windows.graphics.directx.direct3d11.interop.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Security.Authorization.AppCapabilityAccess.h>
#include <winrt/Windows.Graphics.Capture.h>
#include <winrt/Windows.Graphics.DirectX.Direct3D11.h>
#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstring>
#include <cmath>
#include <mutex>
#include <thread>
#include <condition_variable>
#include <vector>
#include <tuple>

using namespace winrt;
using namespace winrt::Windows::Graphics::Capture;
using namespace winrt::Windows::Graphics::DirectX;
using namespace winrt::Windows::Graphics::DirectX::Direct3D11;

namespace {
double QpcMs() {
    LARGE_INTEGER now, frequency;
    QueryPerformanceCounter(&now); QueryPerformanceFrequency(&frequency);
    return 1000.0 * static_cast<double>(now.QuadPart) / frequency.QuadPart;
}

constexpr char Shader[] = R"hlsl(
Texture2D image : register(t0);
Texture3D lutTexture : register(t1);
SamplerState pointSampler : register(s0);
SamplerState lutSampler : register(s1);
cbuffer Settings : register(b0) { float4 rowR; float4 rowG; float4 rowB; float4 offset; };
cbuffer Sampling : register(b1) { float2 texel; float sharpness; float lutMode; };
// A=(authored RGB,alpha); B=(preset,time,radial,pulse);
// C=(pulse speed,min,max,camera scale); D=(camera x,y,unused,unused).
cbuffer Atmosphere : register(b2) { float4 aA; float4 aB; float4 aC; float4 aD; };
// Authored look: primary+base, secondary+edge, motion/rate/frequency,
// focus/falloff/mix. Names select a fixed shader family, never injected code.
cbuffer AtmosphereStyle : register(b3) { float4 lA; float4 lB; float4 lC; float4 lD; };
struct Vertex { float4 pos : SV_POSITION; float2 uv : TEXCOORD0; };
Vertex VS(uint id : SV_VertexID) {
    Vertex v;
    v.uv = float2((id << 1) & 2, id & 2);
    v.pos = float4(v.uv * float2(2, -2) + float2(-1, 1), 0, 1);
    return v;
}
float4 PS(Vertex v) : SV_TARGET {
    float4 c = float4(image.Sample(pointSampler, v.uv).rgb, 1);
    if (sharpness > 0) {
        float3 n = image.Sample(pointSampler, v.uv - float2(0,texel.y)).rgb;
        float3 s = image.Sample(pointSampler, v.uv + float2(0,texel.y)).rgb;
        float3 e = image.Sample(pointSampler, v.uv + float2(texel.x,0)).rgb;
        float3 w = image.Sample(pointSampler, v.uv - float2(texel.x,0)).rgb;
        float3 lo = min(c.rgb,min(min(n,s),min(e,w)));
        float3 hi = max(c.rgb,max(max(n,s),max(e,w)));
        // Bounded unsharp mask, not CAS: never extend beyond the local color range.
        c.rgb = clamp(c.rgb + sharpness * (c.rgb - (n+s+e+w)*.25),lo,hi);
    }
    float3 scene;
    if (lutMode > 0.5) {
        // LUT already contains the complete world grade. Atmosphere still
        // composes over that graded world in this same source pass.
        scene = lutTexture.Sample(lutSampler, c.rgb * (31.0/32.0) + (0.5/32.0)).rgb;
    } else {
        float3 graded = saturate(float3(dot(c,rowR), dot(c,rowG), dot(c,rowB)) + offset.rgb);
        scene = pow(graded, 1.0 / max(offset.w, 1.0e-3));
    }
    int look = (int)(aB.x + 0.5);
    if (look == 0) return float4(scene, 1);
    float2 uv = v.uv;
    float2 world = (uv * float2(1024.0,576.0) - aD.xy) / max(aC.w,0.01);
    float edge = smoothstep(0.28,0.95,length((uv-0.5)*float2(1.65,1.0)));
    float t = aB.y;
    float flicker = 0.5 + 0.5 * sin(t * lC.y);
    float3 tint = lA.rgb;
    float amount = lA.w;
    if (look == 1) {
        // Alarm: a restrained rotating red beacon, strongest at the border.
        amount=lA.w + (lB.w + lC.x*flicker)*edge;
    } else if (look == 2) {
        // Medical alarm: alternating sterile cyan and magenta emergency pools.
        float side=smoothstep(lD.x,lD.y,uv.x);
        tint=lerp(lA.rgb,lB.rgb,side);
        float beat=sin(t*lC.y+uv.x*lC.z);
        amount=lA.w + (lB.w + lC.x*beat*beat)*edge;
    } else if (look == 3) {
        // Industrial alarm: amber lamps and a slow diagonal hazard sweep.
        float sweep=pow(saturate(sin(world.x*lC.z+world.y*lC.w-t*lC.y)*0.5+0.5),4.0);
        amount=lA.w + lB.w*edge + lC.x*sweep;
    } else if (look == 4) {
        // Poison gas: low, drifting teal-green strata.
        float haze=smoothstep(lD.y,lD.z,uv.y+0.07*sin(world.x*lC.z+t*lC.y));
        amount=lA.w + lB.w*haze + lC.x*edge;
    } else if (look == 5) {
        // Corrosion: warmer, irregular acid glow near the floor.
        float stain=sin(world.x*lC.z+t*lC.y)*sin(world.y*lC.w-world.x*lC.z*0.3333);
        amount=lA.w + lB.w*smoothstep(lD.y,lD.z,uv.y)+lC.x*stain*stain;
    } else if (look == 6) {
        // Cold iron: steel-blue ambient with a narrow moving glint.
        float glint=pow(saturate(1.0-abs(frac((world.x+world.y*0.55)*lC.z-t*lC.y)-0.5)*8.0),3.0);
        amount=lA.w+lB.w*edge+lC.x*glint;
    } else if (look == 7) {
        // Ambush: a cold offset opening in a dim blue perimeter.
        float cone=smoothstep(lD.z,0.10,length((uv-lD.xy)*float2(1.2,1.0)));
        amount=lA.w+lB.w*edge-lC.x*cone;
    } else if (look == 8) {
        // Banquet: asymmetrical lantern warmth, with subdued red corners.
        float left=1.0-smoothstep(0.0,lD.z,length((uv-lD.xy)*float2(0.85,1.3)));
        float right=1.0-smoothstep(0.0,lD.z,length((uv-float2(1.0-lD.x,0.10))*float2(0.9,1.1)));
        amount=lA.w+(lB.w+lC.x*flicker)*max(left,right)+lD.w*edge;
    } else if (look == 9) {
        // Blood moon: overhead crimson wash, keeping the playfield readable.
        amount=lA.w+lB.w*(1.0-smoothstep(0.0,1.0,uv.y))+lC.x*edge;
    } else if (look == 10) {
        // Incense: copper glow and very slow drifting smoke bands.
        float smoke=sin(world.x*lC.z+world.y*lC.w+t*lC.y);
        amount=lA.w+lB.w*edge+lC.x*smoke*smoke;
    } else {
        // Direct <Overlay> entries retain their authored color/mode/pulse.
        tint=aA.rgb;
        amount=aA.w;
        float radial=1.0-smoothstep(0.04,0.95,length((uv-0.5)*float2(1.65,1.0)));
        float authored=aB.w>0.5 ? lerp(aC.y,aC.z,0.5+0.5*sin(t*aC.x)) : amount;
        amount=min(0.5,authored*(aB.z>0.5 ? radial : 1.0));
    }
    return float4(saturate(lerp(scene,tint,saturate(amount))),1);
}
)hlsl";

struct Settings { float r[4], g[4], b[4], offset[4]; };
Settings ColorMode(int mode) {
    if (mode == 1) return {{.38f,0,0,0},{0,.48f,0,0},{0,0,.72f,0},{.015f,.025f,.06f,1}};
    if (mode == 2) return {{.04252f,.14304f,.01444f,0},{.2126f,.7152f,.0722f,0},{.02126f,.07152f,.00722f,0},{0,.035f,0,1}};
    return {{1,0,0,0},{0,1,0,0},{0,0,1,0},{0,0,0,1}};
}

// Visual-only weather overlay. Particles are procedural: the vertex shader
// derives each quad from SV_VertexID, the weather clock and the seed, so a
// state change (including "none") needs no buffer upload or particle cleanup.
constexpr char WeatherShader[] = R"hlsl(
Texture3D lutTexture : register(t1);
SamplerState lutSampler : register(s1);
cbuffer Grade : register(b0) { float4 rowR; float4 rowG; float4 rowB; float4 offset; };
cbuffer WeatherParams : register(b1) { float4 wA; float4 wB; float4 wC; float4 wD; };
// Primary RGB/size, secondary RGB/alpha, speed/wind/splash size/alpha,
// splash start/edge fade. All authored in the external visual catalog.
cbuffer WeatherStyle : register(b2) { float4 sA; float4 sB; float4 sC; float4 sD; };
// wA=(time s,intensity,type,seed); wB=(viewport W,H,rain count,LUT enabled)
// wC=(camera x,y,scale,ground min); wD=(ground max,Flash stage height,-,-)
struct WVertex {
    float4 pos : SV_POSITION;
    float2 uv : TEXCOORD0;
    float4 color : TEXCOORD1;
    nointerpolation float shape : TEXCOORD2;
};
float whash(uint x) {
    x = x * 1664525u + 1013904223u; x ^= x >> 16;
    x = x * 2246822519u; x ^= x >> 13;
    return float(x & 0xFFFFFFu) * (1.0 / 16777216.0);
}
// The AS2 F packet uses stage = cameraOffset + world * cameraScale.
// A periodic world field keeps decorative weather populated across long maps;
// wrapping happens at the viewport edge, while every visible particle follows
// camera translation and zoom in the same direction as gameworld content.
float2 projectWeatherWorld(float2 world, float2 view) {
    float2 stage = (wC.xy + world * wC.z) / float2(1024.0, 576.0);
    return frac(stage) * view;
}
WVertex WVS(uint id : SV_VertexID) {
    WVertex o = (WVertex)0;
    uint p = id / 6u;
    uint c = id - p * 6u;
    float2 corner = float2((c == 1u || c == 2u || c == 4u) ? 1.0 : 0.0, (c == 2u || c == 4u || c == 5u) ? 1.0 : 0.0);
    uint seedU = (uint)wA.w;
    float h1 = whash(p * 4u + 11u + seedU * 3u);
    float h2 = whash(p * 5u + 23u + seedU * 5u);
    float h3 = whash(p * 7u + 41u + seedU * 7u);
    float h4 = whash(p * 9u + 67u + seedU * 11u);
    float time = wA.x * sC.x;
    float2 view = wB.xy;
    float pxPerStage = view.y / max(wD.y, 1.0);
    float worldPx = pxPerStage * wC.z * sA.w;
    // Two discrete depth bands: far is smaller/dimmer/slower, near is the reverse.
    float depth = lerp(0.15 + 0.30 * h3, 0.65 + 0.35 * h3, float(p & 1u));
    float scale = 0.5 + 0.7 * depth;
    // Density follows intensity through a stable per-particle threshold.
    float vis = saturate((wA.y - h4) * 40.0);
    float2 p0 = float2(0.0, 0.0), p1 = float2(0.0, 0.0), center = float2(0.0, 0.0);
    float radius = 1.0, width = 1.0, alpha = 0.0, shape = 0.0;
    float3 color = sA.rgb;
    int wtype = (int)(wA.z + 0.5);
    if (wtype == 1) {
        // The legacy visual uses a depth band between Ymin and Ymax, not
        // per-particle terrain collision. Draw rain and impact arcs in one batch.
        float vx = -(20.0 + 55.0 * depth) * (0.7 + 0.6 * h2) * sC.y;
        float ground = (wC.y + lerp(wC.w, wD.x, depth) * wC.z) * pxPerStage;
        float splashRate = 0.55 + 0.45 * depth;
        float splashCycle = floor(h1 + time * splashRate);
        float phase = frac(h1 + time * splashRate);
        if (p >= (uint)wB.z) {
            float progress = saturate((phase - sD.x) / (1.0-sD.x));
            // Freeze the impact's world X at its birth time. Using rainPos.x
            // here made an already-landed arc keep drifting with the falling
            // drop's wind velocity throughout its visible lifetime.
            float impactTime = (splashCycle + sD.x - h1) / splashRate;
            float impactWorldX = h2 * 4096.0 + impactTime * vx;
            center = float2(projectWeatherWorld(float2(impactWorldX,0.0),view).x, ground);
            radius = (4.0 + progress * 8.0) * scale * worldPx * sC.z;
            color = sB.rgb;
            alpha = (phase >= sD.x && ground >= 0.0 && ground <= view.y + 8.0)
                ? (0.68 + 0.18 * depth) * (1.0 - progress) * sC.w : 0.0;
            alpha *= saturate(min(center.x,view.x-center.x)/max(radius*sD.y,1.0));
            shape = 3.0;
        } else {
            float vy = 260.0 + 280.0 * depth;
            float2 rainPos = projectWeatherWorld(float2(h2 * 4096.0 + time * vx,
                h1 * 2304.0 + time * vy), view);
            p0 = rainPos;
            p1 = p0 + normalize(float2(vx,vy)) * (10.0 + 8.0 * h3) * scale * worldPx;
            if (p1.y > ground) p1 = lerp(p0,p1,saturate((ground-p0.y)/max(p1.y-p0.y,0.001)));
            width = (0.85 + 1.05 * depth) * worldPx;
            color = sA.rgb;
            alpha = p0.y < ground ? 0.34 + 0.38 * depth : 0.0;
            shape = 1.0;
        }
    } else if (wtype == 2) {
        // Snow: soft flakes with a slow sine sway.
        float sway = sin(time * (1.2 + 1.5 * h4) + h1 * 6.2832) * (6.0 + 8.0 * depth) * sC.y;
        center = projectWeatherWorld(float2(h3 * 4096.0 + time * (h2 - 0.5) * 25.0 + sway,
            h1 * 2304.0 + time * (35.0 + 90.0 * depth)), view);
        radius = (1.5 + 2.3 * h2) * scale * worldPx;
        alpha = 0.52 + 0.35 * depth;
    } else if (wtype == 3) {
        // Dust: small warm motes drifting slowly down-range.
        float sway = sin(time * (0.8 + h4) + h2 * 6.2832) * (4.0 + 5.0 * depth);
        center = projectWeatherWorld(float2(h3 * 4096.0 + time * (h2 - 0.5) * (35.0 + 65.0 * depth) * sC.y + sway,
            h1 * 2304.0 + time * (12.0 + 35.0 * depth)), view);
        radius = (0.9 + 1.4 * h2) * scale * worldPx;
        color = sA.rgb;
        alpha = 0.20 + 0.25 * depth;
    } else if (wtype == 4) {
        // Fog: a few large soft clouds that fade in, drift and fade out.
        float period = 7.0 + 6.0 * h2;
        float ph = frac(time / period + h4);
        float fade = smoothstep(0.0, 0.20, ph) * smoothstep(0.0, 0.30, 1.0 - ph);
        float2 sway = float2(sin(time * 0.35 + h3 * 6.2832), sin(time * 0.22 + h4 * 6.2832)) * (10.0 + 14.0 * depth);
        center = projectWeatherWorld(float2(h1 * 4096.0 + time * (h3 - 0.5) * 30.0 + sway.x,
            h2 * 2304.0 + time * (h1 - 0.5) * 20.0 + sway.y), view);
        radius = min((60.0 + 95.0 * h3) * scale * worldPx, 180.0);
        color = sA.rgb;
        alpha = (0.08 + 0.12 * depth) * fade;
        float fogEdge = min(min(center.x, view.x - center.x), min(center.y, view.y - center.y));
        alpha *= saturate(fogEdge / max(radius, 1.0));
        shape = 2.0;
    } else {
        // Slash: a cold-steel streak that tears open, slides, then heals.
        float period = 0.9 + 0.7 * h2;
        float u = time / period + h4 * 3.7;
        float ph = frac(u);
        uint cyc = (uint)floor(u);
        float s1 = whash(p * 131u + cyc * 17u + seedU);
        float s2 = whash(p * 137u + cyc * 29u + seedU * 3u);
        float s3 = whash(p * 149u + cyc * 43u + seedU * 7u);
        float ang = 0.35 + 1.05 * s3;
        float2 dir = float2(cos(ang) * (s1 > 0.5 ? 1.0 : -1.0), sin(ang) * (s2 > 0.35 ? 1.0 : -1.0));
        float2 anchor = projectWeatherWorld(float2(s1 * 4096.0, s2 * 2304.0), view);
        float fullLen = (40.0 + 65.0 * h3) * scale * worldPx;
        float headOff, tailOff;
        if (ph < 0.25) { headOff = ph * 4.0 * fullLen; tailOff = 0.0; }
        else if (ph < 0.55) { float sl = (ph - 0.25) / 0.3; headOff = fullLen + sl * fullLen * 0.5; tailOff = sl * fullLen * 0.5; }
        else { float hl = (ph - 0.55) / 0.45; headOff = fullLen * 1.5; tailOff = fullLen * 0.5 + hl * fullLen; }
        p0 = anchor + dir * tailOff;
        p1 = anchor + dir * headOff;
        float env = ph < 0.15 ? ph / 0.15 : (ph < 0.55 ? 1.0 : (1.0 - ph) / 0.45);
        width = (3.0 + 3.2 * depth) * worldPx * (ph < 0.15 ? 1.5 : (ph < 0.25 ? 1.2 : 1.0));
        color = lerp(sA.rgb,sB.rgb,depth);
        alpha = (0.72 + 0.20 * depth) * env;
        float slashEdge = min(min(anchor.x, view.x - anchor.x), min(anchor.y, view.y - anchor.y));
        alpha *= saturate(slashEdge / max(fullLen * 1.5, 1.0));
        shape = 1.0;
    }
    alpha *= vis * sB.w;
    o.uv = corner;
    o.color = float4(color, alpha);
    o.shape = shape;
    if (alpha <= 0.002) { o.pos = float4(-2.0, -2.0, -2.0, 1.0); return o; }
    float2 posPx;
    if (shape > 0.5 && shape < 1.5) {
        float2 seg = p1 - p0;
        float2 perp = float2(-seg.y, seg.x) / max(length(seg), 0.001);
        posPx = p0 + seg * corner.y + perp * (corner.x - 0.5) * width;
    } else if (shape > 2.5) {
        posPx = center + float2((corner.x - 0.5) * 2.0 * radius, (corner.y - 1.0) * radius);
    } else {
        posPx = center + (corner - 0.5) * (2.0 * radius);
    }
    o.pos = float4(posPx.x / view.x * 2.0 - 1.0, 1.0 - posPx.y / view.y * 2.0, 0.5, 1.0);
    return o;
}
float4 WPS(WVertex v) : SV_TARGET {
    float a = v.color.a;
    float2 d = v.uv - float2(0.5, 0.5);
    float3 weatherColor = v.color.rgb;
    if (v.shape < 0.5) {
        float r = length(d) * 2.0;
        a *= 1.0 - smoothstep(0.72, 1.0, r);
        if (wA.z > 1.5 && wA.z < 2.5)
            weatherColor = lerp(sA.rgb,sB.rgb,smoothstep(0.38,0.76,r));
    }
    else if (v.shape < 1.5) {
        float edge = saturate(1.0 - abs(d.x) * 2.0);
        float coverage = wA.z < 1.5 ? smoothstep(0.0, 0.5, edge) : smoothstep(0.05,0.65,edge);
        a *= coverage * smoothstep(0.0, 0.2, v.uv.y) * smoothstep(0.0, 0.25, 1.0 - v.uv.y);
    } else if (v.shape < 2.5) a *= 1.0 - smoothstep(0.25, 1.0, length(d) * 2.0);
    else {
        float u = v.uv.x * 2.0 - 1.0;
        float arc = 1.0 - 0.55 * (1.0 - u*u);
        float distance = abs(v.uv.y - arc);
        a *= 1.0 - smoothstep(0.12,0.23,distance);
        weatherColor = lerp(sB.rgb,sA.rgb,smoothstep(0.06,0.19,distance));
    }
    if (wA.z < 1.5) {
        float core = 1.0 - smoothstep(0.0, 0.3, abs(d.x));
        weatherColor = lerp(sA.rgb,sB.rgb,core);
    }
    if (wB.w > 0.5) {
        // Apply the same LUT as the captured world before alpha blending.
        // The slash core remains visible after the authored grade.
        if (wA.z > 4.5) {
            float core = 1.0 - smoothstep(0.0,0.25,abs(d.x));
            weatherColor = lerp(weatherColor,sB.rgb,0.55 + 0.25 * core);
        }
        float3 lookup = weatherColor * (31.0/32.0) + (0.5/32.0);
        return float4(lutTexture.Sample(lutSampler, lookup).rgb, a);
    }
    float4 c = float4(weatherColor, 1.0);
    float3 graded = saturate(float3(dot(c, rowR), dot(c, rowG), dot(c, rowB)) + offset.rgb);
    if (wA.z > 4.5) {
        float core = 1.0 - smoothstep(0.0,0.25,abs(d.x));
        graded = lerp(graded,sB.rgb,0.55 + 0.25 * core);
    }
    return float4(pow(abs(graded), 1.0 / max(offset.w, 1.0e-3)), a);
}
)hlsl";

// ABI 5 bullet candidates: authored triangle styles instanced per frame item.
// Same camera mapping as weather (stage = camera + world*scale) but without
// the decorative wrap; real objects clip at the viewport edge.
constexpr char BulletShader[] = R"hlsl(
Texture3D lutTexture : register(t1);
SamplerState lutSampler : register(s1);
cbuffer Grade : register(b0) { float4 rowR; float4 rowG; float4 rowB; float4 offset; };
// bB=(viewport W,H,LUT enabled,item count); bC=(camera x,y,scale,style count)
cbuffer BulletParams : register(b1) { float4 bB; float4 bC; };
// 16 styles x float4[4]: (v0.xy,v1.xy), (v2.xy,fill R,G), (fill B,glow RGB),
// (blur X,Y in style units,hasGlow 0/1,reserved)
cbuffer BulletStyles : register(b2) { float4 bS[64]; };
// 256 items x float4[2]: (style index,x,y,rotation deg), (scaleX %,scaleY %,alpha %,-)
cbuffer BulletItems : register(b3) { float4 bI[512]; };
struct BVertex {
    float4 pos : SV_POSITION;
    float2 local : TEXCOORD0;
    nointerpolation uint style : TEXCOORD1;
    nointerpolation float alpha : TEXCOORD2;
};
float cross2(float2 a,float2 b) { return a.x*b.y-a.y*b.x; }
float segmentDistance(float2 p,float2 a,float2 b) {
    float2 ab=b-a;
    float t=saturate(dot(p-a,ab)/max(dot(ab,ab),1.0e-6));
    return length(p-(a+t*ab));
}
// One bounded quad per item. Its pixel shader evaluates the authored triangle
// and a smooth halo around it, so blur does not become a larger hard triangle.
BVertex BVS(uint id : SV_VertexID) {
    BVertex o = (BVertex)0;
    uint item = id / 6u;
    uint corner = id - item * 6u;
    if (item >= (uint)bB.w) { o.pos = float4(-2.0, -2.0, -2.0, 1.0); return o; }
    float4 ia = bI[item * 2u];
    float4 ib = bI[item * 2u + 1u];
    uint si = (uint)(ia.x + 0.5);
    if (si >= (uint)bC.w) { o.pos = float4(-2.0, -2.0, -2.0, 1.0); return o; }
    float4 s0 = bS[si * 4u];
    float4 s1 = bS[si * 4u + 1u];
    float4 s3 = bS[si * 4u + 3u];
    float alpha = saturate(ib.z * 0.01);
    if (alpha <= 0.002) { o.pos = float4(-2.0, -2.0, -2.0, 1.0); return o; }
    float2 p0=s0.xy, p1=s0.zw, p2=s1.xy;
    float2 lo=min(p0,min(p1,p2)), hi=max(p0,max(p1,p2));
    // The current XFL GlowFilter has blurX=blurY=8. Half that value is the
    // candidate Gaussian sigma; a three-sigma bound fades to near zero.
    float2 sigma=max(s3.xy*0.5,float2(0.25,0.25));
    float2 margin=s3.z>0.5 ? sigma*3.0+1.0 : float2(1.0,1.0);
    float2 quadCorner=float2((corner==1u || corner==2u || corner==4u) ? 1.0 : 0.0,
        (corner==2u || corner==4u || corner==5u) ? 1.0 : 0.0);
    float2 local=lerp(lo-margin,hi+margin,quadCorner);
    float rad = ia.w * (3.14159265 / 180.0);
    float cs = cos(rad), sn = sin(rad);
    float2 sc = ib.xy * 0.01;
    float2 scaled = local * sc;
    // Positive degrees rotate clockwise, matching Flash in y-down stage space.
    float2 rotated = float2(scaled.x * cs - scaled.y * sn, scaled.x * sn + scaled.y * cs);
    float2 stage = (bC.xy + (ia.yz + rotated) * bC.z) / float2(1024.0, 576.0);
    o.pos = float4(stage.x * 2.0 - 1.0, 1.0 - stage.y * 2.0, 0.5, 1.0);
    o.local=local;
    o.style=si;
    o.alpha=alpha;
    return o;
}
float4 BPS(BVertex v) : SV_TARGET {
    float4 s0=bS[v.style*4u], s1=bS[v.style*4u+1u];
    float4 s2=bS[v.style*4u+2u], s3=bS[v.style*4u+3u];
    float2 p0=s0.xy, p1=s0.zw, p2=s1.xy, p=v.local;
    float e0=cross2(p1-p0,p-p0), e1=cross2(p2-p1,p-p1), e2=cross2(p0-p2,p-p2);
    bool inside=(e0>=0.0 && e1>=0.0 && e2>=0.0)
        || (e0<=0.0 && e1<=0.0 && e2<=0.0);
    float edgeDistance=min(segmentDistance(p,p0,p1),
        min(segmentDistance(p,p1,p2),segmentDistance(p,p2,p0)));
    float signedDistance=inside ? -edgeDistance : edgeDistance;
    float aa=max(fwidth(edgeDistance),0.5);
    float core=1.0-smoothstep(-aa,aa,signedDistance);
    float halo=0.0;
    if (s3.z>0.5) {
        float2 sigma=max(s3.xy*0.5,float2(0.25,0.25));
        float2 q=p/sigma, q0=p0/sigma, q1=p1/sigma, q2=p2/sigma;
        float d=min(segmentDistance(q,q0,q1),
            min(segmentDistance(q,q1,q2),segmentDistance(q,q2,q0)));
        halo=0.35*exp(-0.5*d*d);
    }
    float opacity=v.alpha*saturate(core+(1.0-core)*halo);
    clip(opacity-0.002);
    float3 color=lerp(s2.yzw,float3(s1.z,s1.w,s2.x),core);
    // Same grade/LUT contract as weather: authored colors are graded, not raw.
    if (bB.z > 0.5)
        return float4(lutTexture.Sample(lutSampler, color * (31.0 / 32.0) + (0.5 / 32.0)).rgb, opacity);
    float4 c = float4(color, 1.0);
    float3 graded = saturate(float3(dot(c, rowR), dot(c, rowG), dot(c, rowB)) + offset.rgb);
    return float4(pow(abs(graded), 1.0 / max(offset.w, 1.0e-3)), opacity);
}
)hlsl";

// This is a safety ceiling. Authored counts live in the external visual catalog.
constexpr int WeatherSafetyCap = 512;
struct WeatherState { int type = 0; float intensity = 0; int quality = 0; uint32_t seed = 0; };
struct WeatherCameraState { float x = 0, y = 0, scale = 1, groundMin = 360, groundMax = 520; };
struct AtmosphereState { int preset = 0; float params[12]{}; };
struct WeatherStyleState { int type = 0, count = 0; float params[16]{}; };
struct AtmosphereStyleState { int family = 0; float params[16]{}; };
// Bullet caps are safety ceilings; each item uses one procedural quad.
constexpr int BulletStyleCap = 16;
constexpr int BulletItemCap = 256;
struct BulletStylesState { int count = 0; float params[BulletStyleCap*16]{}; };
struct BulletFrameState { int count = 0; float cameraX = 0, cameraY = 0, cameraScale = 1; float params[BulletItemCap*8]{}; };

class Capture {
public:
    Capture(HWND source, DWORD pid, HWND output, uint32_t vendor, int fps = 0, bool borderless = false, IUnknown* target = nullptr)
        : source_(source), pid_(pid), output_(output), vendor_(vendor), fps_(fps), borderless_(borderless) {
        stats_.size = sizeof(ProbeStats);
        if (target) check_hresult(target->QueryInterface(__uuidof(IDCompositionVisual), externalVisual_.put_void()));
        worker_ = std::thread([this] { Run(); });
    }
    ~Capture() { stop_ = true; Signal(); if (worker_.joinable()) worker_.join(); }
    void Mode(int mode) { mode_ = std::clamp(mode, 0, 2); Signal(); }
    void Active(bool active) { active_ = active; Signal(); }
    bool Matrix(const float* values) {
        if (!values) return false;
        for (int i=0;i<16;i++) if (!std::isfinite(values[i]) || std::abs(values[i])>32) return false;
        if (values[15]<0.25f || values[15]>4.f) return false;
        { std::lock_guard guard(mutex_); std::memcpy(&customSettings_,values,sizeof(Settings)); ++settingsVersion_; custom_=true; }
        Signal(); return true;
    }
    // lut-set-v1：整块 32^3 RGBA8 拷贝入库（调用方拥有输入缓冲）；上传即启用 LUT 分支，
    // 工作线程按 lutVersion_ 惰性建/更 Texture3D。ClearLut 关断 LUT 分支（矩阵路径回退），缓冲保留。
    bool SetLut(const uint8_t* rgba) {
        if (!rgba) return false;
        { std::lock_guard guard(mutex_); std::memcpy(lutData_, rgba, LutBytes); ++lutVersion_; lutEnabled_ = true; }
        Signal(); return true;
    }
    void ClearLut() {
        { std::lock_guard guard(mutex_); lutEnabled_ = false; ++lutVersion_; }
        Signal();
    }
    void RequestProof() { proofRequested_ = true; }
    // Dev-only LUT lab grab. Blocks the caller until the capture worker services the
    // request (or a bounded timeout); the GPU copy stays on the worker thread.
    int GrabLatestFrame(uint8_t* buffer, uint32_t bufferSize, uint32_t* outWidth, uint32_t* outHeight) {
        if (!outWidth || !outHeight) return 0;
        if (!buffer && bufferSize != 0) return 0;
        *outWidth = 0; *outHeight = 0;
        std::unique_lock lock(grabMutex_);
        if (grabPending_) return -3;
        grabBuffer_ = buffer; grabBufferSize_ = bufferSize;
        grabWidth_ = grabHeight_ = 0; grabResult_ = 0;
        grabPending_ = true; grabRequested_ = true;
        Signal();
        grabDone_.wait_for(lock, std::chrono::seconds(2), [this] { return !grabPending_; });
        if (grabPending_) {
            // Worker gone or wedged: invalidate so a late service writes nothing.
            grabPending_ = false; grabBuffer_ = nullptr; grabBufferSize_ = 0;
            return -4;
        }
        *outWidth = grabWidth_; *outHeight = grabHeight_;
        return grabResult_;
    }
    void RequestContentProof() { contentRequested_=true; proofRequested_=true; }
    void ContentStats(ProbeContentStats& result) { std::lock_guard guard(mutex_); result=contentStats_; }
    bool Crop(int x, int y, int width, int height) {
        if (x < 0 || y < 0 || width < 1 || height < 1 || width > 8192 || height > 8192) return false;
        std::lock_guard guard(mutex_); crop_ = {x,y,x+width,y+height}; return true;
    }
    bool Viewport(int x, int y, int width, int height, double notBefore) {
        if (x<0 || y<0 || width<1 || height<1 || width>8192 || height>8192 || !std::isfinite(notBefore)) return false;
        std::lock_guard presentation(presentationMutex_);
        { std::lock_guard guard(mutex_); crop_={x,y,x+width,y+height}; cropNotBefore_=notBefore; }
        viewportHeld_=false;
        Signal(); return true;
    }
    void HoldViewport() {
        // Return only after any in-flight copy/Present has finished. The caller
        // can now resize its source without an old crop observing new geometry.
        std::lock_guard presentation(presentationMutex_);
        viewportHeld_=true; Signal();
    }
    bool Sharpness(float value) {
        if (!std::isfinite(value) || value<0 || value>.4f) return false;
        sharpness_=value; Signal(); return true;
    }
    // Publishes visual weather state only; all D3D work happens on the worker.
    // Type 0 or intensity 0 clears the overlay; quality 3 suppresses drawing.
    bool Weather(int type, float intensity, int quality, uint32_t seed) {
        if (type < 0 || type > 5 || quality < 0 || quality > 3
            || !std::isfinite(intensity) || intensity < 0.f || intensity > 1.f) return false;
        { std::lock_guard guard(mutex_);
            if (type!=0 && weatherStyle_.type!=type) return false;
            weather_ = {type,intensity,quality,seed}; ++weatherVersion_; }
        Signal(); return true;
    }
    bool WeatherStyle(int type,int count,const float* params) {
        if (type<1 || type>5 || count<0 || count>WeatherSafetyCap || !params) return false;
        for (int i=0;i<16;i++) if (!std::isfinite(params[i])) return false;
        for (int i=0;i<3;i++) if (params[i]<0.f || params[i]>1.f || params[i+4]<0.f || params[i+4]>1.f) return false;
        if (params[3]<0.25f || params[3]>4.f || params[7]<0.f || params[7]>2.f
            || params[8]<0.1f || params[8]>4.f || params[9]<0.f || params[9]>4.f
            || params[10]<0.25f || params[10]>4.f || params[11]<0.f || params[11]>2.f
            || params[12]<0.5f || params[12]>0.95f || params[13]<0.1f || params[13]>4.f
            || params[14]!=0.f || params[15]!=0.f) return false;
        WeatherStyleState state{};state.type=type;state.count=count;
        std::memcpy(state.params,params,sizeof(state.params));
        { std::lock_guard guard(mutex_);weatherStyle_=state;++weatherVersion_; }
        Signal();return true;
    }
    bool WeatherCamera(float x,float y,float scale,float groundMin,float groundMax) {
        if (!std::isfinite(x) || !std::isfinite(y) || !std::isfinite(scale)
            || !std::isfinite(groundMin) || !std::isfinite(groundMax)
            || scale<=0.f || scale>20.f || std::abs(x)>1000000.f || std::abs(y)>1000000.f
            || std::abs(groundMin)>1000000.f || std::abs(groundMax)>1000000.f || groundMax<=groundMin) return false;
        { std::lock_guard guard(mutex_); weatherCamera_={x,y,scale,groundMin,groundMax}; ++weatherVersion_; }
        Signal(); return true;
    }
    bool Atmosphere(int preset,const float* params) {
        if (preset<0 || preset>11 || !params) return false;
        for (int i=0;i<12;i++) if (!std::isfinite(params[i])) return false;
        for (int i=0;i<6;i++) if (params[i]<0.f || params[i]>1.f) return false;
        if (params[6]<0.f || params[6]>30.f || params[7]<0.f || params[7]>1.f
            || params[8]<params[7] || params[8]>1.f) return false;
        AtmosphereState state{}; state.preset=preset;
        std::memcpy(state.params,params,sizeof(state.params));
        { std::lock_guard guard(mutex_);
            if (preset>0 && preset<11 && atmosphereStyle_.family!=preset) return false;
            atmosphere_=state; ++atmosphereVersion_; }
        Signal(); return true;
    }
    bool AtmosphereStyle(int family,const float* params) {
        if (family<1 || family>10 || !params) return false;
        for (int i=0;i<16;i++) if (!std::isfinite(params[i])) return false;
        for (int i=0;i<3;i++) if (params[i]<0.f || params[i]>1.f || params[i+4]<0.f || params[i+4]>1.f) return false;
        if (params[3]<0.f || params[3]>0.5f || params[7]<0.f || params[7]>0.5f
            || params[8]<0.f || params[8]>0.5f || params[9]<0.f || params[9]>20.f
            || params[10]<0.f || params[10]>16.f || params[11]<0.f || params[11]>16.f
            || params[12]<0.f || params[12]>1.f || params[13]<0.f || params[13]>1.f
            || params[14]<0.05f || params[14]>2.f || params[15]<0.f || params[15]>0.5f) return false;
        AtmosphereStyleState state{};state.family=family;
        std::memcpy(state.params,params,sizeof(state.params));
        { std::lock_guard guard(mutex_);atmosphereStyle_=state;++atmosphereVersion_; }
        Signal();return true;
    }
    // Publishes bullet draw state only; all D3D work happens on the worker.
    // count==0 clears the respective snapshot (null params allowed then).
    bool BulletStyles(const float* styles,int count) {
        if (count<0 || count>BulletStyleCap || (count>0 && !styles)) return false;
        BulletStylesState state{};
        for (int s=0;s<count;s++) {
            const float* p=styles+s*16;
            for (int i=0;i<16;i++) if (!std::isfinite(p[i])) return false;
            for (int i=0;i<6;i++) if (std::abs(p[i])>4096.f) return false;
            for (int i=6;i<12;i++) if (p[i]<0.f || p[i]>1.f) return false;
            if (p[12]<0.f || p[12]>255.f || p[13]<0.f || p[13]>255.f
                || (p[14]!=0.f && p[14]!=1.f) || p[15]!=0.f) return false;
            std::memcpy(state.params+s*16,p,64);
        }
        state.count=count;
        { std::lock_guard guard(mutex_);bulletStyles_=state;++bulletVersion_; }
        Signal();return true;
    }
    bool BulletFrame(const float* items,int count,float cameraX,float cameraY,float cameraScale) {
        if (count<0 || count>BulletItemCap || (count>0 && !items)) return false;
        if (!std::isfinite(cameraX) || !std::isfinite(cameraY) || !std::isfinite(cameraScale)
            || cameraScale<=0.f || cameraScale>20.f
            || std::abs(cameraX)>1000000.f || std::abs(cameraY)>1000000.f) return false;
        BulletFrameState state{}; state.cameraX=cameraX; state.cameraY=cameraY; state.cameraScale=cameraScale;
        for (int b=0;b<count;b++) {
            const float* p=items+b*8;
            for (int i=0;i<8;i++) if (!std::isfinite(p[i])) return false;
            if (p[0]!=std::floor(p[0]) || p[0]<0.f || p[0]>=static_cast<float>(BulletStyleCap)
                || std::abs(p[1])>1000000.f || std::abs(p[2])>1000000.f || std::abs(p[3])>1000000.f
                || std::abs(p[4])>10000.f || std::abs(p[5])>10000.f
                || p[6]<0.f || p[6]>100.f || p[7]!=0.f) return false;
            std::memcpy(state.params+b*8,p,32);
        }
        state.count=count;
        { std::lock_guard guard(mutex_);
            for (int b=0;b<count;b++)
                if (static_cast<int>(state.params[b*8])>=bulletStyles_.count) return false;
            bulletFrame_=state; ++bulletVersion_; }
        Signal();return true;
    }
    void Stats(ProbeStats& result) { std::lock_guard guard(mutex_); result = stats_; }
    void CaptureSize(int32_t& width,int32_t& height,uint64_t& generation) { std::lock_guard guard(mutex_); width=captureWidth_;height=captureHeight_;generation=captureGeneration_; }
    bool OutputSize(int32_t& width,int32_t& height) { std::lock_guard guard(mutex_); width=presentedOutputW_;height=presentedOutputH_;return stats_.state!=3 && width>0 && height>0; }

private:
    void Signal() { ++wakeVersion_; wake_.notify_all(); }
    void State(uint32_t value, HRESULT error, const wchar_t* message) {
        std::lock_guard guard(mutex_);
        stats_.state = value; stats_.error = error;
        wcsncpy_s(stats_.message, message, _TRUNCATE);
    }
    bool ValidSource() const {
        DWORD actual = 0;
        GetWindowThreadProcessId(source_, &actual);
        return IsWindow(source_) && actual == pid_;
    }
    void Run() noexcept {
        try {
            init_apartment(apartment_type::multi_threaded);
            // Ensure projected objects are destroyed before apartment teardown.
            try { CaptureLoop(); }
            catch (hresult_error const& e) { State(3, e.code(), e.message().c_str()); }
            catch (std::exception const&) { State(3, E_FAIL, L"Native compositor exception"); }
            catch (...) { State(3, E_FAIL, L"Unknown native compositor failure"); }
            uninit_apartment();
        } catch (...) { State(3, E_FAIL, L"WinRT apartment initialization failed"); }
    }
    void CaptureLoop() {
        if (!ValidSource() || !IsWindow(output_)) throw hresult_error(E_INVALIDARG, L"Invalid source/output HWND or PID");
        if (!GraphicsCaptureSession::IsSupported()) throw hresult_error(E_NOTIMPL, L"WGC unsupported");

        com_ptr<IDXGIFactory1> factory;
        check_hresult(CreateDXGIFactory1(__uuidof(IDXGIFactory1), factory.put_void()));
        com_ptr<IDXGIAdapter1> adapter;
        for (UINT index = 0;; ++index) {
            com_ptr<IDXGIAdapter1> candidate;
            HRESULT hr = factory->EnumAdapters1(index, candidate.put());
            if (hr == DXGI_ERROR_NOT_FOUND) break;
            check_hresult(hr);
            DXGI_ADAPTER_DESC1 desc{}; check_hresult(candidate->GetDesc1(&desc));
            if (desc.Flags & DXGI_ADAPTER_FLAG_SOFTWARE) continue;
            if (vendor_ && desc.VendorId != vendor_) continue;
            adapter = candidate;
            std::lock_guard guard(mutex_);
            stats_.vendor = desc.VendorId; stats_.device = desc.DeviceId;
            wcsncpy_s(stats_.adapter, desc.Description, _TRUNCATE);
            break;
        }
        if (!adapter) throw hresult_error(DXGI_ERROR_NOT_FOUND, L"Requested hardware adapter unavailable; no silent fallback");
        com_ptr<ID3D11Device> device;
        com_ptr<ID3D11DeviceContext> context;
        D3D_FEATURE_LEVEL level;
        check_hresult(D3D11CreateDevice(adapter.get(), D3D_DRIVER_TYPE_UNKNOWN, nullptr,
            D3D11_CREATE_DEVICE_BGRA_SUPPORT, nullptr, 0, D3D11_SDK_VERSION, device.put(), &level, context.put()));
        { std::lock_guard guard(mutex_); stats_.featureLevel = level; }

        auto dxgiDevice = device.as<IDXGIDevice>();
        com_ptr<IInspectable> inspectable;
        check_hresult(CreateDirect3D11DeviceFromDXGIDevice(dxgiDevice.get(), inspectable.put()));
        auto runtimeDevice = inspectable.as<IDirect3DDevice>();
        auto interop = get_activation_factory<GraphicsCaptureItem, IGraphicsCaptureItemInterop>();
        GraphicsCaptureItem item{nullptr};
        check_hresult(interop->CreateForWindow(source_, guid_of<GraphicsCaptureItem>(), put_abi(item)));
        auto size = item.Size();
        { std::lock_guard guard(mutex_); captureWidth_=size.Width;captureHeight_=size.Height; }
        ValidateSize(size.Width, size.Height);
        auto pool = Direct3D11CaptureFramePool::CreateFreeThreaded(runtimeDevice,
            DirectXPixelFormat::B8G8R8A8UIntNormalized, 2, size);
        GraphicsCaptureSession session{nullptr};
        auto arrived = pool.FrameArrived(auto_revoke, [this](auto const&, auto const&) { Signal(); });
        auto frameSignature=[&] { return std::make_tuple(IsZoomed(source_)!=FALSE,
            GetWindowLongW(source_,GWL_STYLE)&(WS_CAPTION|WS_THICKFRAME),GetDpiForWindow(source_)); };
        auto sessionFrame=frameSignature();
        auto startSession = [&] {
            sessionFrame=frameSignature();
            session = pool.CreateCaptureSession(item);
            if (auto cursor = session.try_as<IGraphicsCaptureSession2>()) cursor.IsCursorCaptureEnabled(false);
            if (borderless_) if (auto border = session.try_as<IGraphicsCaptureSession3>()) border.IsBorderRequired(false);
            session.StartCapture();
            { std::lock_guard guard(mutex_); ++captureGeneration_; }
        };

        com_ptr<IDXGISwapChain1> swap;
        auto factory2 = factory.as<IDXGIFactory2>();
        DXGI_SWAP_CHAIN_DESC1 swapDesc{};
        swapDesc.Width = 1; swapDesc.Height = 1; swapDesc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
        swapDesc.SampleDesc.Count = 1; swapDesc.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
        swapDesc.BufferCount = 2; swapDesc.SwapEffect = DXGI_SWAP_EFFECT_FLIP_DISCARD;
        swapDesc.AlphaMode = DXGI_ALPHA_MODE_IGNORE;
        com_ptr<IDCompositionDevice> composition;
        com_ptr<IDCompositionTarget> compositionTarget;
        com_ptr<IDCompositionVisual> visual;
        if (externalVisual_) {
            swapDesc.SwapEffect = DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL;
            swapDesc.Scaling = DXGI_SCALING_STRETCH;
            check_hresult(factory2->CreateSwapChainForComposition(device.get(), &swapDesc, nullptr, swap.put()));
            check_hresult(externalVisual_->SetContent(swap.get()));
        } else if (GetWindowLongPtr(output_, GWL_EXSTYLE) & WS_EX_LAYERED) {
            swapDesc.SwapEffect = DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL;
            swapDesc.Scaling = DXGI_SCALING_STRETCH;
            check_hresult(factory2->CreateSwapChainForComposition(device.get(), &swapDesc, nullptr, swap.put()));
            check_hresult(DCompositionCreateDevice(dxgiDevice.get(), __uuidof(IDCompositionDevice), composition.put_void()));
            check_hresult(composition->CreateTargetForHwnd(output_, TRUE, compositionTarget.put()));
            check_hresult(composition->CreateVisual(visual.put()));
            check_hresult(visual->SetContent(swap.get()));
            check_hresult(compositionTarget->SetRoot(visual.get()));
            check_hresult(composition->Commit());
        } else {
            check_hresult(factory2->CreateSwapChainForHwnd(device.get(), output_, &swapDesc, nullptr, nullptr, swap.put()));
        }
        check_hresult(factory->MakeWindowAssociation(output_, DXGI_MWA_NO_ALT_ENTER));

        auto Compile = [](const char* source, const char* entry, const char* profile) {
            com_ptr<ID3DBlob> blob, error;
            HRESULT hr = D3DCompile(source, std::strlen(source), "compositor-probe", nullptr, nullptr,
                entry, profile, D3DCOMPILE_OPTIMIZATION_LEVEL3 | D3DCOMPILE_WARNINGS_ARE_ERRORS, 0, blob.put(), error.put());
            if (FAILED(hr)) {
                std::wstring detail=L"HLSL compilation failed";
                if (error) {
                    const char* start=static_cast<const char*>(error->GetBufferPointer());
                    detail.assign(start,start+error->GetBufferSize());
                }
                throw hresult_error(hr,detail.c_str());
            }
            return blob;
        };
        auto vsCode = Compile(Shader, "VS", "vs_4_0"); auto psCode = Compile(Shader, "PS", "ps_4_0");
        auto weatherVsCode = Compile(WeatherShader, "WVS", "vs_4_0");
        auto weatherPsCode = Compile(WeatherShader, "WPS", "ps_4_0");
        auto bulletVsCode = Compile(BulletShader, "BVS", "vs_4_0");
        auto bulletPsCode = Compile(BulletShader, "BPS", "ps_4_0");
        com_ptr<ID3D11VertexShader> vs; com_ptr<ID3D11PixelShader> ps;
        check_hresult(device->CreateVertexShader(vsCode->GetBufferPointer(), vsCode->GetBufferSize(), nullptr, vs.put()));
        check_hresult(device->CreatePixelShader(psCode->GetBufferPointer(), psCode->GetBufferSize(), nullptr, ps.put()));
        com_ptr<ID3D11Buffer> constants;
        D3D11_BUFFER_DESC cb{}; cb.ByteWidth = sizeof(Settings); cb.Usage = D3D11_USAGE_DEFAULT; cb.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
        check_hresult(device->CreateBuffer(&cb, nullptr, constants.put()));
        com_ptr<ID3D11Buffer> samplingConstants;
        cb.ByteWidth=16; check_hresult(device->CreateBuffer(&cb,nullptr,samplingConstants.put()));
        com_ptr<ID3D11Buffer> atmosphereConstants;
        cb.ByteWidth=64; check_hresult(device->CreateBuffer(&cb,nullptr,atmosphereConstants.put()));
        com_ptr<ID3D11Buffer> atmosphereStyleConstants;
        cb.ByteWidth=64; check_hresult(device->CreateBuffer(&cb,nullptr,atmosphereStyleConstants.put()));
        com_ptr<ID3D11SamplerState> sampler;
        D3D11_SAMPLER_DESC sd{}; sd.Filter = fps_>0 ? D3D11_FILTER_MIN_MAG_MIP_LINEAR : D3D11_FILTER_MIN_MAG_MIP_POINT;
        sd.AddressU = sd.AddressV = sd.AddressW = D3D11_TEXTURE_ADDRESS_CLAMP;
        sd.MaxLOD = D3D11_FLOAT32_MAX;
        check_hresult(device->CreateSamplerState(&sd, sampler.put()));
        // LUT 采样器独立：3D LUT 必须逐像素线性插值（源图采样器在游戏路径是 POINT；
        // 单 mip 链下 MIN_MAG_MIP_LINEAR 即三维线性采样，与既有枚举用法一致）。
        com_ptr<ID3D11SamplerState> lutSampler;
        D3D11_SAMPLER_DESC lsd{}; lsd.Filter = D3D11_FILTER_MIN_MAG_MIP_LINEAR;
        lsd.AddressU = lsd.AddressV = lsd.AddressW = D3D11_TEXTURE_ADDRESS_CLAMP;
        lsd.MaxLOD = 0;
        check_hresult(device->CreateSamplerState(&lsd, lutSampler.put()));
        com_ptr<ID3D11RasterizerState> raster;
        D3D11_RASTERIZER_DESC rd{}; rd.FillMode = D3D11_FILL_SOLID; rd.CullMode = D3D11_CULL_NONE; rd.DepthClipEnable = TRUE;
        check_hresult(device->CreateRasterizerState(&rd, raster.put()));
        com_ptr<ID3D11VertexShader> weatherVs; com_ptr<ID3D11PixelShader> weatherPs;
        check_hresult(device->CreateVertexShader(weatherVsCode->GetBufferPointer(), weatherVsCode->GetBufferSize(), nullptr, weatherVs.put()));
        check_hresult(device->CreatePixelShader(weatherPsCode->GetBufferPointer(), weatherPsCode->GetBufferSize(), nullptr, weatherPs.put()));
        com_ptr<ID3D11Buffer> weatherParams;
        cb.ByteWidth = 64; check_hresult(device->CreateBuffer(&cb, nullptr, weatherParams.put()));
        com_ptr<ID3D11Buffer> weatherStyleParams;
        cb.ByteWidth = 64; check_hresult(device->CreateBuffer(&cb, nullptr, weatherStyleParams.put()));
        com_ptr<ID3D11VertexShader> bulletVs; com_ptr<ID3D11PixelShader> bulletPs;
        check_hresult(device->CreateVertexShader(bulletVsCode->GetBufferPointer(), bulletVsCode->GetBufferSize(), nullptr, bulletVs.put()));
        check_hresult(device->CreatePixelShader(bulletPsCode->GetBufferPointer(), bulletPsCode->GetBufferSize(), nullptr, bulletPs.put()));
        com_ptr<ID3D11Buffer> bulletParams;
        cb.ByteWidth = 32; check_hresult(device->CreateBuffer(&cb, nullptr, bulletParams.put()));
        com_ptr<ID3D11Buffer> bulletStyleParams;
        cb.ByteWidth = BulletStyleCap*64; check_hresult(device->CreateBuffer(&cb, nullptr, bulletStyleParams.put()));
        com_ptr<ID3D11Buffer> bulletItemParams;
        cb.ByteWidth = BulletItemCap*32; check_hresult(device->CreateBuffer(&cb, nullptr, bulletItemParams.put()));
        com_ptr<ID3D11BlendState> alphaBlend;
        D3D11_BLEND_DESC bd{};
        bd.RenderTarget[0].BlendEnable = TRUE;
        bd.RenderTarget[0].SrcBlend = D3D11_BLEND_SRC_ALPHA;
        bd.RenderTarget[0].DestBlend = D3D11_BLEND_INV_SRC_ALPHA;
        bd.RenderTarget[0].BlendOp = D3D11_BLEND_OP_ADD;
        bd.RenderTarget[0].SrcBlendAlpha = D3D11_BLEND_ONE;
        bd.RenderTarget[0].DestBlendAlpha = D3D11_BLEND_INV_SRC_ALPHA;
        bd.RenderTarget[0].BlendOpAlpha = D3D11_BLEND_OP_ADD;
        bd.RenderTarget[0].RenderTargetWriteMask = D3D11_COLOR_WRITE_ENABLE_ALL;
        check_hresult(device->CreateBlendState(&bd, alphaBlend.put()));

        com_ptr<ID3D11Texture2D> texture;
        com_ptr<ID3D11ShaderResourceView> srv;
        com_ptr<ID3D11RenderTargetView> rtv;
        int textureW = 0, textureH = 0, outputW = 0, outputH = 0;
        int appliedMode = -1;
        float appliedSharpness=-1;
        double frameQpcMs = 0;
        startSession();
        uint64_t appliedSettings = 0;
        // lut-set-v1 工作线程状态：纹理惰性创建，版本驱动的 UpdateSubresource（变更才上传）。
        com_ptr<ID3D11Texture3D> lutTexture;
        com_ptr<ID3D11ShaderResourceView> lutSrv;
        uint64_t appliedLut = 0, lutCopiedVersion = 0;
        bool lutActive = false;
        auto lutWork = std::make_unique<uint8_t[]>(LutBytes);
        uint64_t appliedWeather = 0;
        uint64_t appliedAtmosphere = 0;
        uint64_t appliedBullet = 0;
        BulletStylesState bulletStyles; BulletFrameState bulletFrame;
        float weatherTime = 0;
        double lastWeatherDrawMs = 0;
        float atmosphereTime = 0;
        double lastAtmosphereDrawMs = 0;
        auto nextPresent = std::chrono::steady_clock::now();
        State(1, S_OK, L"GPU display path; optional diagnostic readback");
        while (!stop_) {
            if (!active_) {
                if (session) { session.Close(); session=nullptr; }
                arrived.revoke();
                pool.Close();
                std::unique_lock lock(waitMutex_);
                wake_.wait(lock,[this] { return stop_.load() || active_.load() || grabRequested_.load(); });
                if (stop_) break;
                if (!active_) { ServiceGrab(nullptr,nullptr,nullptr,0,0); continue; }
                size=item.Size(); ValidateSize(size.Width,size.Height);
                pool=Direct3D11CaptureFramePool::CreateFreeThreaded(runtimeDevice,DirectXPixelFormat::B8G8R8A8UIntNormalized,2,size);
                arrived=pool.FrameArrived(auto_revoke,[this](auto const&, auto const&) { Signal(); });
                startSession();
            }
            uint64_t observedWake=wakeVersion_.load();
            uint64_t settingsVersion; bool custom; Settings settings; WeatherState weather; WeatherCameraState weatherCamera; uint64_t weatherVersion;
            uint64_t lutVersion; bool lutEnabled;
            AtmosphereState atmosphere; AtmosphereStyleState atmosphereStyle; uint64_t atmosphereVersion;
            WeatherStyleState weatherStyle; uint64_t bulletVersion;
            { std::lock_guard guard(mutex_); settingsVersion=settingsVersion_; custom=custom_; settings=customSettings_;
                weather=weather_; weatherCamera=weatherCamera_; weatherVersion=weatherVersion_;
                weatherStyle=weatherStyle_; atmosphere=atmosphere_;
                atmosphereStyle=atmosphereStyle_; atmosphereVersion=atmosphereVersion_;
                bulletVersion=bulletVersion_; }
            bool weatherOn = weather.type!=0 && weather.intensity>0.f && weather.quality<3
                && weatherStyle.type==weather.type && weatherStyle.count>0 && texture;
            bool atmosphereOn = atmosphere.preset!=0 && (atmosphere.preset==11
                || atmosphereStyle.family==atmosphere.preset) && texture;
            bool bulletsOn = bulletFrame.count>0 && bulletStyles.count>0 && texture;
            // Weather animates per presented frame; keep a 30fps floor even on
            // unpaced probe sessions so motion stays at the worker cadence.
            int paceFps = fps_>0 ? fps_ : ((weatherOn || atmosphereOn || bulletsOn) ? 30 : 0);
            if (paceFps>0) {
                std::unique_lock lock(waitMutex_);
                wake_.wait_until(lock,nextPresent,[this] { return stop_.load() || !active_.load() || grabRequested_.load(); });
                if (stop_) break;
                if (!active_) continue;
            }
            if (grabRequested_.load()) { ServiceGrab(device.get(),context.get(),texture.get(),textureW,textureH); continue; }
            { std::lock_guard guard(mutex_);
                lutVersion=lutVersion_; lutEnabled=lutEnabled_;
                if (lutEnabled && lutVersion!=lutCopiedVersion) {
                    std::memcpy(lutWork.get(), lutData_, LutBytes); lutCopiedVersion=lutVersion;
                } }
            if (!ValidSource()) { State(2, S_OK, L"Source closed"); break; }
            if (!IsWindow(output_)) break;
            if(!IsIconic(source_) && frameSignature()!=sessionFrame) {
                // Recreate the WGC session, not just its buffers. On this path a
                // pool-only resize can retain the old non-client capture origin
                // even though ContentSize already reports the maximized size.
                // Output swapchain/texture and input HWNDs remain intact.
                session.Close();session=nullptr;arrived.revoke();pool.Close();
                size=item.Size();ValidateSize(size.Width,size.Height);
                pool=Direct3D11CaptureFramePool::CreateFreeThreaded(runtimeDevice,DirectXPixelFormat::B8G8R8A8UIntNormalized,2,size);
                arrived=pool.FrameArrived(auto_revoke,[this](auto const&,auto const&) {Signal();});
                startSession();continue;
            }
            std::unique_lock presentation(presentationMutex_);
            if (viewportHeld_) {
                // Geometry must remain observable while the host holds pixels
                // for a resize. Waiting for a released frame here would deadlock
                // the host's crop selection against Viewport() unholding us.
                auto heldSize=item.Size();
                { std::lock_guard guard(mutex_); captureWidth_=heldSize.Width;captureHeight_=heldSize.Height; }
                presentation.unlock();
                std::unique_lock lock(waitMutex_);
                wake_.wait_for(lock,std::chrono::milliseconds(100),[this,observedWake] { return stop_.load() || wakeVersion_.load()!=observedWake; });
                continue;
            }
            auto frame = pool.TryGetNextFrame();
            RECT client{}; GetClientRect(output_, &client);
            bool fresh = static_cast<bool>(frame);
            if (!frame && (!texture || (appliedMode == mode_.load() && !proofRequested_
                    && outputW == client.right && outputH == client.bottom && appliedSettings==settingsVersion
                    && appliedSharpness==sharpness_.load() && appliedLut==lutVersion
                    && appliedWeather==weatherVersion && !weatherOn
                    && appliedAtmosphere==atmosphereVersion && !atmosphereOn
                    && appliedBullet==bulletVersion && !bulletsOn))) {
                presentation.unlock();
                std::unique_lock lock(waitMutex_);
                wake_.wait_for(lock,std::chrono::milliseconds(100),[this,observedWake] { return stop_.load() || wakeVersion_.load()!=observedWake; });
                continue;
            }
            uint64_t drained = 0;
            double start = QpcMs();
            if (frame) {
                // Bounded drain: never let a continuously active producer starve presentation.
                for (int i = 0; i < 2; ++i) {
                    auto newer = pool.TryGetNextFrame();
                    if (!newer) break;
                    frame.Close(); frame = newer; ++drained;
                }
                auto content = frame.ContentSize();
                { std::lock_guard guard(mutex_); captureWidth_=content.Width;captureHeight_=content.Height; }
                ValidateSize(content.Width, content.Height);
                auto access = frame.Surface().as<::Windows::Graphics::DirectX::Direct3D11::IDirect3DDxgiInterfaceAccess>();
                com_ptr<ID3D11Texture2D> sourceTexture;
                check_hresult(access->GetInterface(__uuidof(ID3D11Texture2D), sourceTexture.put_void()));
                D3D11_TEXTURE2D_DESC sourceDesc{}; sourceTexture->GetDesc(&sourceDesc);
                bool changed = content.Width != size.Width || content.Height != size.Height;
                // Resize notifications may precede a full-size backing texture. Drop that frame.
                if (content.Width > static_cast<int>(sourceDesc.Width) || content.Height > static_cast<int>(sourceDesc.Height)) {
                    sourceTexture = nullptr; access = nullptr; frame.Close();
                    size = content; pool.Recreate(runtimeDevice, DirectXPixelFormat::B8G8R8A8UIntNormalized, 2, size);
                    { std::lock_guard guard(mutex_); ++stats_.resizes; }
                    continue;
                }
                if (sourceDesc.Format != DXGI_FORMAT_B8G8R8A8_UNORM || sourceDesc.SampleDesc.Count != 1)
                    throw hresult_error(E_INVALIDARG, L"Unexpected capture texture format");
                double incomingQpcMs = static_cast<double>(frame.SystemRelativeTime().count()) / 10000.0;
                RECT crop; double cropNotBefore;
                { std::lock_guard guard(mutex_); crop = crop_; cropNotBefore=cropNotBefore_; }
                // Keep the last swapchain image until a frame newer than the source
                // resize is available. Never crop a queued old frame with new geometry.
                if (incomingQpcMs<cropNotBefore) { sourceTexture=nullptr; access=nullptr; frame.Close(); continue; }
                frameQpcMs=incomingQpcMs;
                if (crop.right == 0) crop = {0,0,content.Width,content.Height};
                if (crop.right > content.Width || crop.bottom > content.Height) {
                    sourceTexture = nullptr; access = nullptr; frame.Close();
                    if (changed) { size=content; pool.Recreate(runtimeDevice,DirectXPixelFormat::B8G8R8A8UIntNormalized,2,size); }
                    continue;
                }
                int croppedWidth = crop.right-crop.left, croppedHeight = crop.bottom-crop.top;
                if (textureW != croppedWidth || textureH != croppedHeight) {
                    ID3D11ShaderResourceView* empty = nullptr; context->PSSetShaderResources(0, 1, &empty);
                    srv = nullptr; texture = nullptr;
                    D3D11_TEXTURE2D_DESC td{}; td.Width = croppedWidth; td.Height = croppedHeight;
                    td.MipLevels = 1; td.ArraySize = 1; td.Format = sourceDesc.Format; td.SampleDesc.Count = 1;
                    td.Usage = D3D11_USAGE_DEFAULT; td.BindFlags = D3D11_BIND_SHADER_RESOURCE;
                    check_hresult(device->CreateTexture2D(&td, nullptr, texture.put()));
                    check_hresult(device->CreateShaderResourceView(texture.get(), nullptr, srv.put()));
                    textureW = croppedWidth; textureH = croppedHeight;
                }
                D3D11_BOX box{static_cast<UINT>(crop.left),static_cast<UINT>(crop.top),0,static_cast<UINT>(crop.right),static_cast<UINT>(crop.bottom),1};
                context->CopySubresourceRegion(texture.get(), 0, 0, 0, 0, sourceTexture.get(), 0, &box);
                // Release WGC pool frame promptly. Commands on this one immediate context are ordered.
                sourceTexture = nullptr; access = nullptr; frame.Close();
                if (changed) {
                    size = content; pool.Recreate(runtimeDevice, DirectXPixelFormat::B8G8R8A8UIntNormalized, 2, size);
                    std::lock_guard guard(mutex_); ++stats_.resizes;
                }
            }
            int w = client.right, h = client.bottom;
            if (w <= 0 || h <= 0 || IsIconic(output_)) {
                std::this_thread::sleep_for(std::chrono::milliseconds(16)); continue;
            }
            ValidateSize(w, h);
            if (outputW != w || outputH != h) {
                context->OMSetRenderTargets(0, nullptr, nullptr); rtv = nullptr;
                check_hresult(swap->ResizeBuffers(2, w, h, DXGI_FORMAT_B8G8R8A8_UNORM, 0));
                com_ptr<ID3D11Texture2D> back;
                check_hresult(swap->GetBuffer(0, __uuidof(ID3D11Texture2D), back.put_void()));
                check_hresult(device->CreateRenderTargetView(back.get(), nullptr, rtv.put()));
                outputW = w; outputH = h;
            }
            int mode = mode_.load();
            if (mode != appliedMode || settingsVersion != appliedSettings) {
                if (!custom) settings = ColorMode(mode);
                context->UpdateSubresource(constants.get(), 0, nullptr, &settings, 0, 0);
                appliedMode = mode; appliedSettings=settingsVersion;
            }
            // lut-set-v1：版本变化才触碰 GPU（建纹理一次性，之后 UpdateSubresource 整块覆盖）。
            if (lutVersion != appliedLut) {
                if (lutEnabled) {
                    if (!lutTexture) {
                        D3D11_TEXTURE3D_DESC ld{}; ld.Width=LutSize; ld.Height=LutSize; ld.Depth=LutSize;
                        ld.MipLevels=1; ld.Format=DXGI_FORMAT_R8G8B8A8_UNORM;
                        ld.Usage=D3D11_USAGE_DEFAULT; ld.BindFlags=D3D11_BIND_SHADER_RESOURCE;
                        check_hresult(device->CreateTexture3D(&ld, nullptr, lutTexture.put()));
                        check_hresult(device->CreateShaderResourceView(lutTexture.get(), nullptr, lutSrv.put()));
                    }
                    context->UpdateSubresource(lutTexture.get(), 0, nullptr, lutWork.get(),
                        LutSize*4, LutSize*LutSize*4);
                }
                lutActive = lutEnabled && lutSrv != nullptr;
                appliedLut = lutVersion;
            }
            // The pacing wait and WGC dequeue may span an AS2 F packet. Sample
            // its camera and the newest bullet snapshot immediately before
            // drawing; the loop-head copy could be one presented frame behind.
            { std::lock_guard guard(mutex_);
                weatherCamera=weatherCamera_; weatherVersion=weatherVersion_;
                if (bulletVersion_!=appliedBullet) {
                    bulletStyles=bulletStyles_; bulletFrame=bulletFrame_; appliedBullet=bulletVersion_; } }
            auto target = rtv.get(); context->OMSetRenderTargets(1, &target, nullptr);
            const float black[]{0,0,0,1}; context->ClearRenderTargetView(target, black);
            float scale = std::min(static_cast<float>(w)/textureW, static_cast<float>(h)/textureH);
            D3D11_VIEWPORT viewport{(w-textureW*scale)/2, (h-textureH*scale)/2, textureW*scale, textureH*scale, 0, 1};
            context->RSSetViewports(1, &viewport); context->RSSetState(raster.get());
            context->IASetInputLayout(nullptr); context->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
            context->VSSetShader(vs.get(), nullptr, 0); context->PSSetShader(ps.get(), nullptr, 0);
            auto resource = srv.get(); auto sampling = sampler.get(); auto buffer = constants.get();
            context->PSSetShaderResources(0,1,&resource); context->PSSetSamplers(0,1,&sampling); context->PSSetConstantBuffers(0,1,&buffer);
            ID3D11ShaderResourceView* lutResource = lutActive ? lutSrv.get() : nullptr;
            context->PSSetShaderResources(1,1,&lutResource);
            auto lutSamp = lutSampler.get(); context->PSSetSamplers(1,1,&lutSamp);
            appliedSharpness=sharpness_.load();
            float samplingValues[]{1.f/textureW,1.f/textureH,appliedSharpness,lutActive?1.f:0.f};
            context->UpdateSubresource(samplingConstants.get(),0,nullptr,samplingValues,0,0);
            auto samplingBuffer=samplingConstants.get(); context->PSSetConstantBuffers(1,1,&samplingBuffer);
            bool proof = proofRequested_.exchange(false);
            if (atmosphereOn && !proof) {
                double nowAtmosphereMs=QpcMs();
                float delta=lastAtmosphereDrawMs>0
                    ? std::clamp(static_cast<float>((nowAtmosphereMs-lastAtmosphereDrawMs)/1000.0),0.f,0.10f)
                    : 1.f/30.f;
                lastAtmosphereDrawMs=nowAtmosphereMs;
                atmosphereTime+=delta;
                if (atmosphereTime>8192.f) atmosphereTime-=8192.f;
            } else if (!atmosphereOn) lastAtmosphereDrawMs=0;
            float ap[16]{
                atmosphere.params[0],atmosphere.params[1],atmosphere.params[2],atmosphere.params[3],
                proof ? 0.f : static_cast<float>(atmosphere.preset),atmosphereTime,
                atmosphere.params[4],atmosphere.params[5],
                atmosphere.params[6],atmosphere.params[7],atmosphere.params[8],weatherCamera.scale,
                weatherCamera.x,weatherCamera.y,0,0
            };
            context->UpdateSubresource(atmosphereConstants.get(),0,nullptr,ap,0,0);
            auto atmosphereBuffer=atmosphereConstants.get(); context->PSSetConstantBuffers(2,1,&atmosphereBuffer);
            context->UpdateSubresource(atmosphereStyleConstants.get(),0,nullptr,atmosphereStyle.params,0,0);
            auto lookBuffer=atmosphereStyleConstants.get(); context->PSSetConstantBuffers(3,1,&lookBuffer);
            context->Draw(3,0);
            ID3D11ShaderResourceView* empty = nullptr; context->PSSetShaderResources(0,1,&empty);
            // Weather overlays the graded world inside the same content viewport,
            // blended after the source pass (not pre-grade composited). The base
            // grade cbuffer and LUT resource stay bound for the weather grade.
            if (weatherOn && !proof) {
                double nowWeatherMs = QpcMs();
                float weatherDelta = lastWeatherDrawMs > 0
                    ? std::clamp(static_cast<float>((nowWeatherMs-lastWeatherDrawMs)/1000.0),0.f,0.10f)
                    : 1.f/30.f;
                lastWeatherDrawMs = nowWeatherMs;
                weatherTime += weatherDelta;
                if (weatherTime > 8192.f) weatherTime -= 8192.f;
                int rainCount=weatherStyle.count;
                if (weather.quality==1) rainCount=rainCount*5/8;
                else if (weather.quality==2) rainCount=rainCount*3/8;
                float wp[16]{weatherTime,weather.intensity,static_cast<float>(weather.type),
                    static_cast<float>(weather.seed & 0xFFFFFFu),viewport.Width,viewport.Height,static_cast<float>(rainCount),lutActive?1.f:0.f,
                    weatherCamera.x,weatherCamera.y,weatherCamera.scale,weatherCamera.groundMin,
                    weatherCamera.groundMax,576.f,0,0};
                context->UpdateSubresource(weatherParams.get(),0,nullptr,wp,0,0);
                context->UpdateSubresource(weatherStyleParams.get(),0,nullptr,weatherStyle.params,0,0);
                context->VSSetShader(weatherVs.get(),nullptr,0); context->PSSetShader(weatherPs.get(),nullptr,0);
                auto weatherBuffer = weatherParams.get();
                context->VSSetConstantBuffers(1,1,&weatherBuffer); context->PSSetConstantBuffers(1,1,&weatherBuffer);
                auto weatherLookBuffer=weatherStyleParams.get();
                context->VSSetConstantBuffers(2,1,&weatherLookBuffer);context->PSSetConstantBuffers(2,1,&weatherLookBuffer);
                context->OMSetBlendState(alphaBlend.get(),nullptr,0xffffffff);
                int splashCount=weather.type==1 ? std::max(8,rainCount/2) : 0;
                context->Draw((rainCount+splashCount)*6,0);
                context->OMSetBlendState(nullptr,nullptr,0xffffffff);
            } else if (!weatherOn) lastWeatherDrawMs = 0;
            // Bullet candidates draw last inside the same graded viewport,
            // alpha blended over world+weather+atmosphere. The base grade
            // cbuffer and LUT resource stay bound for the bullet grade.
            if (bulletFrame.count>0 && bulletStyles.count>0 && texture && !proof) {
                float bp[8]{viewport.Width,viewport.Height,lutActive?1.f:0.f,static_cast<float>(bulletFrame.count),
                    bulletFrame.cameraX,bulletFrame.cameraY,bulletFrame.cameraScale,static_cast<float>(bulletStyles.count)};
                context->UpdateSubresource(bulletParams.get(),0,nullptr,bp,0,0);
                context->UpdateSubresource(bulletStyleParams.get(),0,nullptr,bulletStyles.params,0,0);
                context->UpdateSubresource(bulletItemParams.get(),0,nullptr,bulletFrame.params,0,0);
                context->VSSetShader(bulletVs.get(),nullptr,0); context->PSSetShader(bulletPs.get(),nullptr,0);
                auto bulletBuffer=bulletParams.get();
                context->VSSetConstantBuffers(1,1,&bulletBuffer); context->PSSetConstantBuffers(1,1,&bulletBuffer);
                auto bulletStyleBuffer=bulletStyleParams.get(); auto bulletItemBuffer=bulletItemParams.get();
                context->VSSetConstantBuffers(2,1,&bulletStyleBuffer); context->PSSetConstantBuffers(2,1,&bulletStyleBuffer);
                context->VSSetConstantBuffers(3,1,&bulletItemBuffer);
                context->OMSetBlendState(alphaBlend.get(),nullptr,0xffffffff);
                context->Draw(bulletFrame.count*6,0);
                context->OMSetBlendState(nullptr,nullptr,0xffffffff);
            }
            appliedWeather = weatherVersion;
            appliedAtmosphere = atmosphereVersion;
            context->PSSetShaderResources(1,1,&empty);
            double submit = QpcMs();
            if (proof) {
                VerifyPixels(device.get(), context.get(), swap.get(), texture.get(), viewport, textureW, textureH, mode,
                    lutActive ? lutWork.get() : nullptr);
                if (contentRequested_.exchange(false))
                    VerifyContent(device.get(), context.get(), swap.get(), texture.get(), viewport, textureW, textureH, mode);
            }
            double presentStart = QpcMs();
            HRESULT present = swap->Present(1, 0);
            check_hresult(present);
            double end = QpcMs();
            if (paceFps>0) nextPresent=std::max(nextPresent+std::chrono::microseconds(1000000/paceFps),std::chrono::steady_clock::now());
            {
                std::lock_guard guard(mutex_);
                stats_.received += fresh ? 1 + drained : 0; stats_.superseded += drained;
                if (present == S_OK) { ++stats_.presented; presentedOutputW_=w; presentedOutputH_=h; }
                stats_.width = textureW; stats_.height = textureH;
                if (fresh) {
                    stats_.ageMs = start - frameQpcMs;
                    stats_.maxAgeMs = std::max(stats_.maxAgeMs, stats_.ageMs);
                }
                stats_.submitMs = submit - start; stats_.presentMs = end - presentStart;
                stats_.lastFrameQpcMs = frameQpcMs;
            }
            presentation.unlock();
            if (present == DXGI_STATUS_OCCLUDED) std::this_thread::sleep_for(std::chrono::milliseconds(40));
        }
        arrived.revoke();
        if (session) session.Close();
        pool.Close();
        context->ClearState(); context->Flush();
        { std::lock_guard guard(mutex_); if (stats_.state == 1) stats_.state = 2; }
    }
    // Explicit diagnostic only: six 1-pixel CPU readbacks per request, never a per-frame path.
    void VerifyPixels(ID3D11Device* device, ID3D11DeviceContext* context, IDXGISwapChain1* swap,
            ID3D11Texture2D* input, D3D11_VIEWPORT vp, int width, int height, int mode, const uint8_t* lut) {
        com_ptr<ID3D11Texture2D> output, staging;
        check_hresult(swap->GetBuffer(0, __uuidof(ID3D11Texture2D), output.put_void()));
        D3D11_TEXTURE2D_DESC td{}; td.Width = td.Height = td.MipLevels = td.ArraySize = td.SampleDesc.Count = 1;
        td.Format = DXGI_FORMAT_B8G8R8A8_UNORM; td.Usage = D3D11_USAGE_STAGING; td.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
        check_hresult(device->CreateTexture2D(&td,nullptr,staging.put()));
        auto read = [&](ID3D11Texture2D* tex, int x, int y) {
            D3D11_BOX box{static_cast<UINT>(x),static_cast<UINT>(y),0,static_cast<UINT>(x+1),static_cast<UINT>(y+1),1};
            context->CopySubresourceRegion(staging.get(),0,0,0,0,tex,0,&box);
            D3D11_MAPPED_SUBRESOURCE mapped{}; check_hresult(context->Map(staging.get(),0,D3D11_MAP_READ,0,&mapped));
            uint32_t value; std::memcpy(&value,mapped.pData,4); context->Unmap(staging.get(),0); return value;
        };
        uint32_t ins[3]{}, outs[3]{}, error = 0;
        auto settings = ColorMode(mode);
        for (int i = 0; i < 3; ++i) {
            int x = static_cast<int>(vp.TopLeftX + vp.Width * (.2f + .3f * i));
            int y = static_cast<int>(vp.TopLeftY + vp.Height * .3f);
            int sx = std::clamp(static_cast<int>((x+.5f-vp.TopLeftX)/vp.Width*width),0,width-1);
            int sy = std::clamp(static_cast<int>((y+.5f-vp.TopLeftY)/vp.Height*height),0,height-1);
            ins[i] = read(input,sx,sy); outs[i] = read(output.get(),x,y);
            float c[]{static_cast<float>((ins[i]>>16)&255)/255,static_cast<float>((ins[i]>>8)&255)/255,static_cast<float>(ins[i]&255)/255,1};
            const float* rows[]{settings.r,settings.g,settings.b};
            for (int channel = 0; channel < 3; ++channel) {
                float result = 0;
                if (lut) {
                    float fx=c[0]*31.f, fy=c[1]*31.f, fz=c[2]*31.f;
                    int x0=static_cast<int>(fx), y0=static_cast<int>(fy), z0=static_cast<int>(fz);
                    int x1=std::min(x0+1,31), y1=std::min(y0+1,31), z1=std::min(z0+1,31);
                    float wx=fx-x0, wy=fy-y0, wz=fz-z0;
                    for (int bz=0;bz<2;bz++) for (int gy=0;gy<2;gy++) for (int rx=0;rx<2;rx++) {
                        int r=rx?x1:x0, g=gy?y1:y0, b=bz?z1:z0;
                        float weight=(rx?wx:1-wx)*(gy?wy:1-wy)*(bz?wz:1-wz);
                        result += weight * (lut[((b*32+g)*32+r)*4+channel]/255.f);
                    }
                } else {
                    result = settings.offset[channel];
                    for (int j = 0; j < 4; ++j) result += c[j]*rows[channel][j];
                }
                int expected = static_cast<int>(std::round(std::clamp(result,0.f,1.f)*255));
                int actual = (outs[i] >> (16-8*channel)) & 255;
                error = std::max(error,static_cast<uint32_t>(std::abs(expected-actual)));
            }
        }
        std::lock_guard guard(mutex_);
        ++stats_.proofCount; stats_.proofMode = mode; stats_.proofMaxError = error;
        stats_.proofDistinct = ins[0] != ins[1] && ins[1] != ins[2] && ins[0] != ins[2];
        std::copy(std::begin(ins),std::end(ins),stats_.inputPixels);
        std::copy(std::begin(outs),std::end(outs),stats_.outputPixels);
        stats_.cpuReadbacks += 6;
    }
    // Dev-only grab service, always on the worker thread. Answers the pending request once:
    // copies the newest cropped capture (pre-grade, BGRA8) into the caller buffer.
    void ServiceGrab(ID3D11Device* device, ID3D11DeviceContext* context, ID3D11Texture2D* texture, int width, int height) {
        std::unique_lock lock(grabMutex_);
        grabRequested_ = false;
        if (!grabPending_) return;
        int result = -1; uint32_t outW = 0, outH = 0;
        uint32_t state;
        { std::lock_guard guard(mutex_); state = stats_.state; }
        if (texture && device && context && width > 0 && height > 0
                && active_.load() && state == 1 && !IsIconic(output_)) {
            outW = static_cast<uint32_t>(width); outH = static_cast<uint32_t>(height);
            uint64_t needed = static_cast<uint64_t>(outW) * outH * 4;
            if (!grabBuffer_ || grabBufferSize_ < needed) {
                result = -2;
            } else {
                try {
                    D3D11_TEXTURE2D_DESC td{}; td.Width = outW; td.Height = outH;
                    td.MipLevels = 1; td.ArraySize = 1; td.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
                    td.SampleDesc.Count = 1; td.Usage = D3D11_USAGE_STAGING; td.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
                    com_ptr<ID3D11Texture2D> staging;
                    check_hresult(device->CreateTexture2D(&td, nullptr, staging.put()));
                    context->CopyResource(staging.get(), texture);
                    D3D11_MAPPED_SUBRESOURCE mapped{};
                    check_hresult(context->Map(staging.get(), 0, D3D11_MAP_READ, 0, &mapped));
                    for (uint32_t row = 0; row < outH; ++row)
                        std::memcpy(grabBuffer_ + static_cast<size_t>(row) * outW * 4,
                            static_cast<const uint8_t*>(mapped.pData) + static_cast<size_t>(row) * mapped.RowPitch,
                            static_cast<size_t>(outW) * 4);
                    context->Unmap(staging.get(), 0);
                    { std::lock_guard guard(mutex_); ++stats_.cpuReadbacks; }
                    result = 1;
                } catch (...) { result = -5; }
            }
        }
        grabWidth_ = outW; grabHeight_ = outH; grabResult_ = result;
        grabPending_ = false;
        lock.unlock();
        grabDone_.notify_all();
    }
    // Explicit G2 diagnostic only, raw 1:1 mode. Hash every RGB pixel in F and
    // compare that exact ROI to the pre-Present output, not S's chrome/frame rate.
    // Two full-ROI readbacks per request; never called by the game render loop
    // unless this separate diagnostic export is explicitly requested.
    void VerifyContent(ID3D11Device* device, ID3D11DeviceContext* context, IDXGISwapChain1* swap,
            ID3D11Texture2D* input, D3D11_VIEWPORT vp, int width, int height, int mode) {
        if(mode!=0 || static_cast<int>(vp.Width)!=width || static_cast<int>(vp.Height)!=height)
            throw hresult_error(E_INVALIDARG,L"Content proof requires raw 1:1 viewport");
        com_ptr<ID3D11Texture2D> output, staging;
        check_hresult(swap->GetBuffer(0,__uuidof(ID3D11Texture2D),output.put_void()));
        D3D11_TEXTURE2D_DESC td{}; td.Width=width; td.Height=height;
        td.MipLevels=td.ArraySize=td.SampleDesc.Count=1; td.Format=DXGI_FORMAT_B8G8R8A8_UNORM;
        td.Usage=D3D11_USAGE_STAGING; td.CPUAccessFlags=D3D11_CPU_ACCESS_READ;
        check_hresult(device->CreateTexture2D(&td,nullptr,staging.put()));
        auto read=[&](ID3D11Texture2D* tex,int x,int y) {
            D3D11_BOX box{static_cast<UINT>(x),static_cast<UINT>(x+width),static_cast<UINT>(y+height),1};
            context->CopySubresourceRegion(staging.get(),0,0,0,0,tex,0,&box);
            D3D11_MAPPED_SUBRESOURCE mapped{}; check_hresult(context->Map(staging.get(),0,D3D11_MAP_READ,0,&mapped));
            std::vector<uint32_t> pixels(static_cast<size_t>(width)*height);
            for(int row=0;row<height;++row)
                std::memcpy(pixels.data()+static_cast<size_t>(row)*width,
                    static_cast<const uint8_t*>(mapped.pData)+static_cast<size_t>(row)*mapped.RowPitch,static_cast<size_t>(width)*4);
            context->Unmap(staging.get(),0); return pixels;
        };
        auto in=read(input,0,0), out=read(output.get(),static_cast<int>(vp.TopLeftX),static_cast<int>(vp.TopLeftY));
        uint64_t ih=14695981039346656037ull, oh=ih; uint32_t error=0;
        for(size_t i=0;i<in.size();++i) for(int shift=0;shift<24;shift+=8) {
            uint32_t a=(in[i]>>shift)&255, b=(out[i]>>shift)&255;
            ih=(ih^a)*1099511628211ull; oh=(oh^b)*1099511628211ull;
            error=std::max(error,static_cast<uint32_t>(std::abs(static_cast<int>(a)-static_cast<int>(b))));
        }
        std::lock_guard guard(mutex_);
        contentStats_={sizeof(ProbeContentStats),contentStats_.count+1,stats_.proofCount,
            static_cast<uint32_t>(width),static_cast<uint32_t>(height),error,ih,oh};
        stats_.cpuReadbacks+=2;
    }
    static void ValidateSize(int width, int height) {
        if (width <= 0 || height <= 0 || width > 8192 || height > 8192)
            throw hresult_error(E_INVALIDARG, L"Capture/output dimensions outside prototype bounds");
    }
    HWND source_, output_; DWORD pid_; uint32_t vendor_;
    com_ptr<IDCompositionVisual> externalVisual_;
    std::atomic<bool> stop_{false}; std::atomic<int> mode_{0};
    std::atomic<bool> proofRequested_{false};
    std::atomic<bool> contentRequested_{false};
    ProbeContentStats contentStats_{sizeof(ProbeContentStats)};
    int32_t captureWidth_=0,captureHeight_=0;
    int32_t presentedOutputW_=0,presentedOutputH_=0;
    uint64_t captureGeneration_=0;
    std::thread worker_; std::mutex mutex_; ProbeStats stats_{};
    RECT crop_{};
    double cropNotBefore_=0;
    std::mutex presentationMutex_;
    bool viewportHeld_=false;
    std::atomic<float> sharpness_{0};
    int fps_; bool borderless_;
    std::atomic<bool> active_{true};
    std::atomic<uint64_t> wakeVersion_{0};
    std::mutex waitMutex_; std::condition_variable wake_;
    // Dev-only LUT lab grab request state (grabMutex_ guards the whole struct).
    std::mutex grabMutex_; std::condition_variable grabDone_;
    std::atomic<bool> grabRequested_{false};
    bool grabPending_=false;
    uint8_t* grabBuffer_=nullptr; uint32_t grabBufferSize_=0;
    uint32_t grabWidth_=0, grabHeight_=0; int grabResult_=0;
    Settings customSettings_{}; bool custom_=false; uint64_t settingsVersion_=0;
    // lut-set-v1：宿主线程 SetLut/ClearLut 经 mutex_ 入库，工作线程按 lutVersion_
    // 惰性建/更 Texture3D（变更才上传，不逐帧）；ClearLut 只关断分支，GPU 纹理保留复用。
    static constexpr uint32_t LutSize = 32;
    static constexpr size_t LutBytes = static_cast<size_t>(LutSize)*LutSize*LutSize*4;
    uint8_t lutData_[LutBytes]{};
    bool lutEnabled_=false; uint64_t lutVersion_=0;
    WeatherState weather_{}; WeatherCameraState weatherCamera_{}; uint64_t weatherVersion_=0;
    AtmosphereState atmosphere_{}; uint64_t atmosphereVersion_=0;
    WeatherStyleState weatherStyle_{}; AtmosphereStyleState atmosphereStyle_{};
    BulletStylesState bulletStyles_{}; BulletFrameState bulletFrame_{}; uint64_t bulletVersion_=0;
};
}

uint32_t __cdecl ProbeGetAbiVersion() { return 5; }
int __cdecl ProbeGetOutputSize(void* handle, int32_t* width, int32_t* height) {
    return handle && width && height && static_cast<Capture*>(handle)->OutputSize(*width,*height) ? 1 : 0;
}
void* __cdecl ProbeStartVisual(HWND source, DWORD sourcePid, HWND output, IUnknown* visual) {
    if (!visual) return nullptr;
    try { return new Capture(source, sourcePid, output, 0, 30, false, visual); } catch (...) { return nullptr; }
}
void* __cdecl ProbeStart(HWND source, DWORD sourcePid, HWND output, uint32_t vendor) {
    try { return new Capture(source, sourcePid, output, vendor); } catch (...) { return nullptr; }
}
int __cdecl ProbeSetCrop(void* handle, int x, int y, int width, int height) {
    return handle && static_cast<Capture*>(handle)->Crop(x,y,width,height) ? 1 : 0;
}
int __cdecl ProbeSetViewport(void* handle, int x, int y, int width, int height, double notBefore) {
    return handle && static_cast<Capture*>(handle)->Viewport(x,y,width,height,notBefore) ? 1 : 0;
}
void __cdecl ProbeHoldViewport(void* handle) { if (handle) static_cast<Capture*>(handle)->HoldViewport(); }
int __cdecl ProbeSetSharpness(void* handle, float value) {
    return handle && static_cast<Capture*>(handle)->Sharpness(value) ? 1 : 0;
}
void __cdecl ProbeSetMode(void* handle, int mode) { if (handle) static_cast<Capture*>(handle)->Mode(mode); }
void __cdecl ProbeRequestProof(void* handle) { if (handle) static_cast<Capture*>(handle)->RequestProof(); }
int __cdecl ProbeGrabLatestFrame(void* handle, uint8_t* buffer, uint32_t bufferSize, uint32_t* outWidth, uint32_t* outHeight) {
    return handle ? static_cast<Capture*>(handle)->GrabLatestFrame(buffer, bufferSize, outWidth, outHeight) : 0;
}
void __cdecl ProbeRequestContentProof(void* handle) { if (handle) static_cast<Capture*>(handle)->RequestContentProof(); }
int __cdecl ProbeGetContentStats(void* handle, ProbeContentStats* stats) {
    if(!handle || !stats || stats->size!=sizeof(ProbeContentStats)) return 0;
    static_cast<Capture*>(handle)->ContentStats(*stats); return 1;
}
int __cdecl ProbeGetStats(void* handle, ProbeStats* stats) {
    if (!handle || !stats || stats->size != sizeof(ProbeStats)) return 0;
    static_cast<Capture*>(handle)->Stats(*stats); return 1;
}
int __cdecl ProbeGetCaptureSize(void* handle,int32_t* width,int32_t* height,uint64_t* generation) {
    if(!handle || !width || !height || !generation)return 0;
    static_cast<Capture*>(handle)->CaptureSize(*width,*height,*generation);return 1;
}
void __cdecl ProbeStop(void* handle) { delete static_cast<Capture*>(handle); }

void* __cdecl ProbeStartWorld(HWND source, DWORD sourcePid, HWND output, uint32_t vendor, int borderless) {
    try { return new Capture(source,sourcePid,output,vendor,30,borderless==1); } catch (...) { return nullptr; }
}
int __cdecl ProbeRequestBorderless() {
    try {
        init_apartment(apartment_type::multi_threaded);
        int result=0;
        try {
            auto access=GraphicsCaptureAccess::RequestAccessAsync(GraphicsCaptureAccessKind::Borderless).get();
            result=access==winrt::Windows::Security::Authorization::AppCapabilityAccess::AppCapabilityAccessStatus::Allowed ? 1 : 2;
        } catch (...) { result=-1; }
        uninit_apartment(); return result;
    } catch (...) { return -1; }
}
int __cdecl ProbeSetMatrix(void* handle, const float* settings) {
    return handle && static_cast<Capture*>(handle)->Matrix(settings) ? 1 : 0;
}
int __cdecl ProbeSetLut(void* handle, const uint8_t* rgba) {
    return handle && static_cast<Capture*>(handle)->SetLut(rgba) ? 1 : 0;
}
void __cdecl ProbeClearLut(void* handle) { if (handle) static_cast<Capture*>(handle)->ClearLut(); }
void __cdecl ProbeSetActive(void* handle, int active) { if (handle) static_cast<Capture*>(handle)->Active(active!=0); }
int __cdecl ProbeSetWeather(void* handle, int type, float intensity, int quality, uint32_t seed) {
    return handle && static_cast<Capture*>(handle)->Weather(type,intensity,quality,seed) ? 1 : 0;
}
int __cdecl ProbeSetWeatherCamera(void* handle,float x,float y,float scale,float groundMin,float groundMax) {
    return handle && static_cast<Capture*>(handle)->WeatherCamera(x,y,scale,groundMin,groundMax) ? 1 : 0;
}
int __cdecl ProbeSetAtmosphere(void* handle,int preset,const float* params) {
    return handle && static_cast<Capture*>(handle)->Atmosphere(preset,params) ? 1 : 0;
}
int __cdecl ProbeSetAtmosphereStyle(void* handle,int family,const float* params) {
    return handle && static_cast<Capture*>(handle)->AtmosphereStyle(family,params) ? 1 : 0;
}
int __cdecl ProbeSetWeatherStyle(void* handle,int type,int count,const float* params) {
    return handle && static_cast<Capture*>(handle)->WeatherStyle(type,count,params) ? 1 : 0;
}
int __cdecl ProbeSetBulletStyles(void* handle,const float* styles,int count) {
    return handle && static_cast<Capture*>(handle)->BulletStyles(styles,count) ? 1 : 0;
}
int __cdecl ProbeSetBulletFrame(void* handle,const float* items,int count,float cameraX,float cameraY,float cameraScale) {
    return handle && static_cast<Capture*>(handle)->BulletFrame(items,count,cameraX,cameraY,cameraScale) ? 1 : 0;
}
