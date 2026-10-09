#pragma once
// Physical output pixels; HUD is already premultiplied and never receives world grading.
constexpr char HudRasterShader[] = R"hlsl(
Texture2D hudPixels : register(t0);
cbuffer HudRasterParams : register(b0) { float4 hudRect; float4 hudOutput; };
struct HVertex { float4 pos:SV_POSITION; float2 pixel:TEXCOORD0; };
HVertex HVS(uint id:SV_VertexID) {
    float2 q=float2((id==1u || id==2u || id==4u)?1.0:0.0,
        (id==2u || id==4u || id==5u)?1.0:0.0);
    float2 position=hudRect.xy+q*hudRect.zw;
    HVertex v; v.pos=float4(position.x*2.0/hudOutput.x-1.0,
        1.0-position.y*2.0/hudOutput.y,0,1); v.pixel=q*hudRect.zw; return v;
}
float4 HPS(HVertex v):SV_TARGET { return hudPixels.Load(int3(int2(v.pixel),0)); }
)hlsl";
// HLSL authority, compiled by ShaderBake during the native build, never at game startup.

// World, weather, bullets and sprites sample one bounded 256x144 HDR light field.
constexpr char PointLightShared[] = R"hlsl(
Texture2D pointField : register(t3);
SamplerState pointSamplerLinear : register(s3);
Texture2D scenePointField : register(t6);
cbuffer SceneLightParams : register(b6) {
    float4 sceneRegion; // min world XY, inverse world extent XY
    float4 sceneControl; // enabled, baking, world texel XY
};
cbuffer PointLightParams : register(b4) {
    float4 pointView; float4 pointCamera; float4 pointControl; float4 pointPalette;
};
float2 pointUv(float2 pixel) { return (pixel-pointView.xy)/pointView.zw; }
float3 pointLit(float3 graded,float3 raw,float2 uv) {
    float3 result=graded;
    [branch] if(pointControl.x>=0.5) {
        float4 field=float4(0,0,0,0);
        if(pointControl.z>=0.5) field=pointField.SampleLevel(pointSamplerLinear,uv,0);
        if(sceneControl.x>=0.5) {
            float2 world=(uv*float2(1024.0,576.0)-pointCamera.xy)/pointCamera.z;
            float2 sceneUv=(world-sceneRegion.xy)*sceneRegion.zw;
            if(all(sceneUv>=0.0) && all(sceneUv<=1.0)) field+=scenePointField.SampleLevel(pointSamplerLinear,sceneUv,0);
        }
        float weight=max(field.a,0.0);
        [branch] if(weight>0.0001) {
            float response=pointControl.y*(1.0-exp(-weight));
            float3 tint=field.rgb/weight;
            // A short shot supplies direct light independently of dark ambient grading.
            // Exposure lifts texture detail with a soft highlight shoulder; black remains black.
            float3 local=(1.0-exp(-raw*1.8*(0.3+0.7*saturate(tint))))*pointPalette.rgb;
            result=lerp(graded,max(graded,local),response);
        }
    }
    return result;
}
)hlsl";

constexpr char PointLightShader[] = R"hlsl(
cbuffer PointLightItems : register(b5) { float4 pointItems[64]; };
// ABI 9 light record (16 floats): a=(world x,y,length|radius,energy),
// b=(R,G,B,kind 0 radial gunfire / 1 cone / 2 fixed-width beam),
// c=(unit dir x,y,halfWidth,reserved 0), d=(near x,y,radius,energy).
// Only kind 1 may carry a same-color near fill circle inside the same record
// and budget; kind 0/2 keep d all zero. AS2 already projects rotation and
// mirroring into the unit direction; nothing is flipped here.
struct LVertex {
    float4 pos:SV_POSITION;
    float2 local:TEXCOORD0;
    nointerpolation float4 color:TEXCOORD1;
    nointerpolation float4 shape:TEXCOORD2;
    nointerpolation float4 nearFill:TEXCOORD3;
};
LVertex LVS(uint id:SV_VertexID) {
    uint item=id/6u,corner=id%6u;
    float2 q=float2((corner==1u || corner==2u || corner==4u)?1.0:0.0,
        (corner==2u || corner==4u || corner==5u)?1.0:0.0);
    float4 a=pointItems[item*4u],b=pointItems[item*4u+1u],c=pointItems[item*4u+2u],e=pointItems[item*4u+3u];
    LVertex v;v.color=float4(b.rgb,a.w);v.shape=float4(b.w,a.z,c.z,0);v.nearFill=float4(0,0,0,0);
    float2 world;
    if(b.w<0.5) {
        v.local=q*2.0-1.0;
        world=a.xy+v.local*a.z;
    } else {
        // Directional kinds share one affine frame so interpolation stays
        // exact: local.x is world distance along the axis, local.y the signed
        // distance across it. The pixel shader derives each real footprint.
        float t=q.y,s=q.x*2.0-1.0;
        float2 d=c.xy,n=float2(-c.y,c.x);
        // Expand the raster quad by half a light-field texel; otherwise a thin
        // rotated beam can miss all samples even with a smooth pixel falloff.
        float margin=sceneControl.y>=0.5?0.5*max(sceneControl.z,sceneControl.w):2.0/max(pointCamera.z,0.0001);
        float lo=0.0,hi=a.z,latHalf=c.z+margin;
        // A kind-1 near circle shares this one quad and budget: project its
        // center into the light basis and union the along/lateral ranges.
        // Records without a near field keep the legacy cone/beam footprint.
        float radius=e.z;
        if(radius>0.0) {
            float2 rel=e.xy-a.xy;
            float nearAlong=dot(rel,d),nearSide=dot(rel,n);
            lo=min(0.0,nearAlong-radius-margin);
            hi=max(a.z,nearAlong+radius+margin);
            latHalf=max(c.z,abs(nearSide)+radius)+margin;
            v.nearFill=float4(nearAlong,nearSide,radius,e.w);
        }
        float along=lerp(lo,hi,t);
        v.local=float2(along,latHalf*s);
        world=a.xy+d*along+n*(latHalf*s);
    }
    float2 stage=(pointCamera.xy+world*pointCamera.z)/float2(1024.0,576.0);
    if(sceneControl.y>=0.5)stage=(world-sceneRegion.xy)*sceneRegion.zw;
    v.pos=float4(stage.x*2.0-1.0,1.0-stage.y*2.0,0.5,1.0);
    return v;
}
float4 LPS(LVertex v):SV_TARGET {
    float energy;
    if(v.shape.x<0.5) {
        float falloff=saturate(1.0-dot(v.local,v.local));
        energy=v.color.a*falloff*falloff;
    } else {
        float t=v.local.x/max(v.shape.y,0.001),lateral;
        float distance=abs(v.local.y);
        float aa=max(fwidth(v.local.y),0.001);
        if(v.shape.x<1.5) {
            // A reflected-light base blends into the forward lobe. Both lobes
            // roll off continuously; there is no constant-bright disk or cone.
            float forwardT=t,width=max(t,0.02)*v.shape.z;
            float centerSide=0,gate=step(0.0,t),disk=0;
            if(v.nearFill.z>0) {
                float fromBase=v.local.x-v.nearFill.x;
                forwardT=saturate(fromBase/max(v.shape.y-v.nearFill.x,1.0));
                width=lerp(v.nearFill.z*0.9,v.shape.z,sqrt(forwardT));
                centerSide=v.nearFill.y*(1.0-smoothstep(0.0,v.nearFill.z*1.2,fromBase));
                gate=smoothstep(-v.nearFill.z*0.35,v.nearFill.z*0.7,fromBase);
                float nearD=length(v.local-v.nearFill.xy);
                float radial=nearD/max(v.nearFill.z,0.001);
                float rim=1.0-smoothstep(0.60,1.0+fwidth(nearD)/max(v.nearFill.z,0.001),radial);
                disk=v.nearFill.w*exp(-2.0*radial*radial)*rim;
            }
            float lateralD=abs(v.local.y-centerSide);
            float crossSection=lateralD/max(width,aa);
            lateral=exp(-2.4*crossSection*crossSection)
                *(1.0-smoothstep(width*0.70,width+aa,lateralD));
            float cone=v.color.a*lateral*exp(-1.15*max(forwardT,0.0))
                *(1.0-smoothstep(0.72,1.0,forwardT))*gate;
            // Smooth bounded union: continuous derivatives without max()'s
            // joining contour or the hotspot of an additive overlap.
            float peak=max(max(v.color.a,v.nearFill.w),0.0001);
            energy=disk+cone-disk*cone/peak;
        } else {
            // Flash owns the thin red beam. This narrower colored halo has a
            // soft transverse core and long end fade, avoiding a bright panel.
            float along=v.local.x;
            float normalized=distance/max(v.shape.z,aa);
            lateral=exp(-3.5*normalized*normalized)
                *(1.0-smoothstep(v.shape.z*0.65,v.shape.z+aa,distance));
            energy=v.color.a*lateral*(1.0-0.35*saturate(t))
                *smoothstep(0.0,min(18.0,v.shape.y*0.1),along)
                *(1.0-smoothstep(0.72,1.0,t));
        }
    }
    return float4(v.color.rgb*energy,energy);
}
)hlsl";

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
    if (look == 0) return float4(pointLit(scene,c.rgb,v.uv), 1);
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
    return float4(pointLit(saturate(lerp(scene,tint,saturate(amount))),c.rgb,v.uv),1);
}
)hlsl";

// Premultiplied atlas: casings use world grading; muzzle sprites are emissive.
constexpr char CombatFxShader[] = R"hlsl(
Texture2D fxAtlas : register(t2);
Texture3D lutTexture : register(t1);
SamplerState fxSampler : register(s2);
SamplerState lutSampler : register(s1);
cbuffer Grade : register(b0) { float4 rowR; float4 rowG; float4 rowB; float4 offset; };
cbuffer FxParams : register(b1) { float4 fCamera; float4 fRange; };
cbuffer FxItems : register(b2) { float4 fI[2048]; };
struct FVertex { float4 pos:SV_POSITION; float2 uv:TEXCOORD0; nointerpolation float3 look:TEXCOORD1; };
FVertex FVS(uint id:SV_VertexID) {
    uint item=id/6u+(uint)fRange.x, corner=id%6u;
    float4 a=fI[item*4u], b=fI[item*4u+1u], c=fI[item*4u+2u], d=fI[item*4u+3u];
    float2 q=float2((corner==1u || corner==2u || corner==4u)?1.0:0.0,
        (corner==2u || corner==4u || corner==5u)?1.0:0.0);
    float2 local=(c.xy+q*c.zw)*b.xy;
    float r=a.z*(3.14159265/180.0), cs=cos(r), sn=sin(r);
    float2 world=a.xy+float2(local.x*cs-local.y*sn,local.x*sn+local.y*cs);
    float2 stage=(fCamera.xy+world*fCamera.z)/float2(1024.0,576.0);
    FVertex v;v.pos=float4(stage.x*2.0-1.0,1.0-stage.y*2.0,0.5,1.0);
    v.uv=lerp(d.xy,d.zw,q);v.look=float3(a.w,b.z,b.w);return v;
}
float4 FPS(FVertex v):SV_TARGET {
    float4 tex=fxAtlas.Sample(fxSampler,v.uv);
    if(tex.a<0.001) discard;
    float3 color=saturate(tex.rgb/tex.a*v.look.y);
    if(v.look.z>0.5) {
        float3 raw=color;
        if(fCamera.w>0.5) color=lutTexture.Sample(lutSampler,color*(31.0/32.0)+(0.5/32.0)).rgb;
        else {
            float4 c=float4(color,1.0);
            color=pow(saturate(float3(dot(c,rowR),dot(c,rowG),dot(c,rowB))+offset.rgb),1.0/max(offset.w,1.0e-3));
        }
        color=pointLit(color,raw,pointUv(v.pos.xy));
    }
    float alpha=tex.a*v.look.x;return float4(color*alpha,alpha);
}
)hlsl";

// Procedural quads derive from SV_VertexID, the weather clock and the seed.
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
        return float4(pointLit(lutTexture.Sample(lutSampler, lookup).rgb,weatherColor,pointUv(v.pos.xy)), a);
    }
    float4 c = float4(weatherColor, 1.0);
    float3 graded = saturate(float3(dot(c, rowR), dot(c, rowG), dot(c, rowB)) + offset.rgb);
    if (wA.z > 4.5) {
        float core = 1.0 - smoothstep(0.0,0.25,abs(d.x));
        graded = lerp(graded,sB.rgb,0.55 + 0.25 * core);
    }
    return float4(pointLit(pow(abs(graded), 1.0 / max(offset.w, 1.0e-3)),weatherColor,pointUv(v.pos.xy)), a);
}
)hlsl";

// Authored triangle/sprite styles use the same camera mapping as weather.
constexpr char BulletShader[] = R"hlsl(
Texture3D lutTexture : register(t1);
SamplerState lutSampler : register(s1);
Texture2D bulletAtlas : register(t2);
SamplerState bulletSampler : register(s2);
cbuffer Grade : register(b0) { float4 rowR; float4 rowG; float4 rowB; float4 offset; };
// bB=(viewport W,H,LUT enabled,item count); bC=(camera x,y,scale,style count)
cbuffer BulletParams : register(b1) { float4 bB; float4 bC; };
// 16 styles x float4[4]: (v0.xy,v1.xy), (v2.xy,fill R,G), (fill B,glow RGB),
// (blur X,Y in style units,hasGlow 0/1,reserved)
cbuffer BulletStyles : register(b2) { float4 bS[128]; };
// 256 items x float4[2]: (style index,x,y,rotation deg), (scaleX %,scaleY %,alpha %,-)
cbuffer BulletItems : register(b3) { float4 bI[2048]; };
struct BVertex {
    float4 pos : SV_POSITION;
    float2 local : TEXCOORD0;
    nointerpolation uint style : TEXCOORD1;
    nointerpolation float alpha : TEXCOORD2;
    float2 uv : TEXCOORD3;
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
    float4 s0 = bS[si * 8u];
    float4 s1 = bS[si * 8u + 1u];
    float4 s3 = bS[si * 8u + 3u];
    float alpha = saturate(ib.z * 0.01);
    if (alpha <= 0.002) { o.pos = float4(-2.0, -2.0, -2.0, 1.0); return o; }
    float2 p0=s0.xy, p1=s0.zw, p2=s1.xy;
    float2 lo=min(p0,min(p1,p2)), hi=max(p0,max(p1,p2));
    // The current XFL GlowFilter has blurX=blurY=8. Half that value is the
    // candidate Gaussian sigma; a three-sigma bound fades to near zero.
    float2 sigma=max(s3.xy*0.5,float2(0.25,0.25));
    float2 margin=s3.z>0.5 ? sigma*3.0+1.0 : float2(1.0,1.0);
    if(s3.w>0.5) {
        float4 rect=bS[si*8u+4u];lo=rect.xy;hi=rect.xy+rect.zw;margin=0.0;
    }
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
    float4 uvRect=bS[si*8u+5u];o.uv=lerp(uvRect.xy,uvRect.zw,quadCorner);
    return o;
}
float4 BPS(BVertex v) : SV_TARGET {
    float4 s0=bS[v.style*8u], s1=bS[v.style*8u+1u];
    float4 s2=bS[v.style*8u+2u], s3=bS[v.style*8u+3u];
    if(s3.w>0.5) {
        float4 tex=bulletAtlas.Sample(bulletSampler,v.uv);
        float opacity=tex.a*v.alpha;clip(opacity-0.002);
        float3 color=tex.rgb/max(tex.a,0.00001);
        if(bB.z>0.5) return float4(pointLit(lutTexture.Sample(lutSampler,color*(31.0/32.0)+(0.5/32.0)).rgb,color,pointUv(v.pos.xy)),opacity);
        float4 c=float4(color,1);float3 graded=saturate(float3(dot(c,rowR),dot(c,rowG),dot(c,rowB))+offset.rgb);
        return float4(pointLit(pow(abs(graded),1.0/max(offset.w,1.0e-3)),color,pointUv(v.pos.xy)),opacity);
    }
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
        return float4(pointLit(lutTexture.Sample(lutSampler, color * (31.0 / 32.0) + (0.5 / 32.0)).rgb,color,pointUv(v.pos.xy)), opacity);
    float4 c = float4(color, 1.0);
    float3 graded = saturate(float3(dot(c, rowR), dot(c, rowG), dot(c, rowB)) + offset.rgb);
    return float4(pointLit(pow(abs(graded), 1.0 / max(offset.w, 1.0e-3)),color,pointUv(v.pos.xy)), opacity);
}
)hlsl";

#include "RayShader.h"
