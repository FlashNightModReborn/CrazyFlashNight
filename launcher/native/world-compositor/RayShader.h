// RayVisualCatalog.cs owns the 32-float record and authored parameter slots.
// Helper literals are kept separate so styles can be developed without changing ABI/lifecycle.
constexpr char RayShader[] =
R"hlsl(
cbuffer Grade : register(b0) { float4 rowR; float4 rowG; float4 rowB; float4 offset; };
cbuffer RayParams : register(b1) { float4 rView; float4 rCamera; };
cbuffer RayItems : register(b2) { float4 rI[2048]; };
)hlsl"
#include "RayStyleShader.h"
#include "RayFlameShader.h"
R"hlsl(
struct RVertex { float4 pos:SV_POSITION;float2 q:TEXCOORD0;
    nointerpolation uint item:TEXCOORD1;nointerpolation float lengthWorld:TEXCOORD2;
    nointerpolation float paddingWorld:TEXCOORD3; };
RVertex RVS(uint id:SV_VertexID) {
    RVertex o=(RVertex)0;uint item=id/6u,corner=id%6u;o.item=item;
    if(item>=(uint)rView.w) { o.pos=float4(-2,-2,-2,1);return o; }
    float4 a=rI[item*8u],b=rI[item*8u+2u],c=rI[item*8u+3u];
    uint style=(uint)c.w;uint drawPass=(uint)rCamera.w;
    bool flame=style==11u,screen=style==9u;
    if((drawPass==0u && !flame) || (drawPass==1u && (flame||screen)) || (drawPass==2u && !screen) || (drawPass==3u && !flame)) {
        o.pos=float4(-2,-2,-2,1);return o;
    }
    float2 delta=a.zw-a.xy;float len=length(delta);float2 axis=len>0.001?delta/len:float2(1,0);
    // The AS2 Tesla renderer returns for coincident endpoints. A decorative
    // corona must not turn that empty segment into a phantom impact flash.
    if(style==0u && len<=0.0) {o.pos=float4(-2,-2,-2,1);return o;}
    bool spot=style>=16u && style<28u;float width=clamp(b.w,0.25,512.0);
    float padding=width*12.0;
    float4 meta=rI[item*8u+4u],p0=rI[item*8u+5u],p1=rI[item*8u+6u],p2=rI[item*8u+7u];
    float intensity=clamp(meta.x,0.0,2.0),stroke=max(width,.75)*intensity;
    float pixelWorld=max(1024.0/max(rView.x,1.0),576.0/max(rView.y,1.0))/max(abs(rCamera.z),.01);
    float aaGuard=2.0*pixelWorld;
    if(style==0u) padding=abs(p0.x)*2.0*intensity+stroke*10.0+aaGuard*2;
    if(style==3u||style==4u) padding=max(padding,min(abs(p0.z)+width*12,512.0));
    if(style==4u) padding=max(abs(p0.z)+stroke,stroke*5.0)+aaGuard*2;
    if(style>=5u&&style<=8u) padding=max(padding,min(abs(p0.x)+width*18,512.0));
    if(style==9u) padding=max(padding,min(abs(p0.x)+width*3,512.0));
    float baguaRadius=abs(p0.z)*intensity*(1.0+max(p1.w,0.0));
    float baguaStroke=max(stroke*max(p2.w,0.0)*.5,stroke)+aaGuard*2;
    if(style==10u) padding=baguaRadius+baguaStroke;
    if(style==42u) padding=max(padding,min(abs(p0.z)+width*3,512.0));
    if(flame) padding=max(width*6.0+abs(p0.x)*1.4,12.0);
    padding=min(padding,512.0);o.paddingWorld=padding;
    if(spot) { len=0; padding=width*2; }
    float edge=spot?padding:min(width*2,24.0);
    if(style==0u) edge=min(stroke*8.0+aaGuard*2,512.0);
    if(style==10u) edge=min(baguaRadius*abs(p0.w)+baguaStroke,512.0);
    float2 uv=float2(corner==1u||corner==2u||corner==4u?1:0,corner==2u||corner==4u||corner==5u?1:0);
    float x=lerp(-edge,len+edge,uv.x),y=lerp(-padding,padding,uv.y);
    o.q=float2(spot?x:x/max(len,.001),y);o.lengthWorld=max(len,.001);
    float2 world=a.xy+axis*x+float2(-axis.y,axis.x)*y;
    float2 stage=(rCamera.xy+world*rCamera.z)/float2(1024,576);
    o.pos=float4(stage.x*2-1,1-stage.y*2,.5,1);return o;
}
float4 RayFinish(RVertex v, uint style, float4 primary, float4 meta, float4 effect) {
    float rim=style==10u?1.0:1.0-smoothstep(v.paddingWorld*.82,v.paddingWorld,abs(v.q.y));
    // These authored renderers use intensity for geometry, not a second fade.
    float opacityScale=(style==0u||style==4u||style==10u)?1.0:clamp(meta.x,0.0,2.0);
    float alpha=saturate(effect.a*primary.a*opacityScale)*rim;clip(alpha-.002);
    float3 color=clamp(effect.rgb,0.0,4.0);
    // Emissive effects retain their palette under ordinary ambient LUT, while matrix night vision applies.
    if(rView.z<.5) {
        float4 c=float4(color,1);color=pow(abs(saturate(float3(dot(c,rowR),dot(c,rowG),dot(c,rowB))+offset.rgb)),1/max(offset.w,.001));
    }
    return float4(color*alpha,alpha);
}

struct RayPixelItem {
    float4 primary, secondary, clock, meta, p0, p1, p2;
};

RayPixelItem RayLoadPixelItem(uint index) {
    uint at = index * 8u;
    RayPixelItem item = {rI[at+1u], rI[at+2u], rI[at+3u], rI[at+4u],
                         rI[at+5u], rI[at+6u], rI[at+7u]};
    return item;
}

float4 RayShadeSpot(float2 q, RayPixelItem item) {
    float d = length(q) / max(item.secondary.w, .5);
    float ring = exp(-pow((d-.55)/.14, 2.0));
    float core = exp(-d*d*4.0);
    return float4(lerp(item.primary.rgb, float3(1,1,.9), core),
                  saturate((ring*.45+core*.7)*item.p0.x*.01));
}

float4 RayFlameEffect(RVertex v, RayPixelItem item) {
    float4 effect = ShadeFlame(v.q, v.lengthWorld, item.secondary.w, item.clock.x,
                               item.clock.z, item.primary.rgb, item.secondary.rgb,
                               item.p0, item.p1, item.p2);
    if (rCamera.w > 2.5) {
        effect.rgb = lerp(item.primary.rgb, float3(1,.55,.08), .65);
        effect.a *= .15;
    }
    return effect;
}

float4 RPSFlame(RVertex v):SV_TARGET {
    RayPixelItem item = RayLoadPixelItem(v.item);
    return RayFinish(v, 11u, item.primary, item.meta, RayFlameEffect(v, item));
}

float4 RPSScreen(RVertex v):SV_TARGET {
    RayPixelItem item = RayLoadPixelItem(v.item);
    RayCtx C = RayInitCtx(v.q, v.lengthWorld, item.primary, item.secondary, item.clock, item.meta);
    return RayFinish(v, 9u, item.primary, item.meta, RayShadeConvergence(C, item.p0, item.p1));
}

float4 RPSTesla(RVertex v):SV_TARGET {
    RayPixelItem item = RayLoadPixelItem(v.item);
    RayCtx C = RayInitCtx(v.q, v.lengthWorld, item.primary, item.secondary, item.clock, item.meta);
    return RayFinish(v, 0u, item.primary, item.meta, RayShadeTesla(C, item.p0, item.p1));
}

float4 RPSOther(RVertex v):SV_TARGET {
    RayPixelItem item = RayLoadPixelItem(v.item);
    RayCtx C = RayInitCtx(v.q, v.lengthWorld, item.primary, item.secondary, item.clock, item.meta);
    uint style = (uint)item.clock.w;
    float4 effect;
    [branch] if (style >= 16u && style < 28u)
        effect = RayShadeSpot(v.q, item);
    else
        effect = ShadeRayStyleOther(style, C, item.p0, item.p1, item.p2);
    return RayFinish(v, style, item.primary, item.meta, effect);
}

float4 RPS(RVertex v):SV_TARGET {
    RayPixelItem item = RayLoadPixelItem(v.item);
    RayCtx C = RayInitCtx(v.q, v.lengthWorld, item.primary, item.secondary, item.clock, item.meta);
    uint style = (uint)item.clock.w;
    float4 effect;
    [branch] if (style >= 16u && style < 28u)
        effect = RayShadeSpot(v.q, item);
    else [branch] if (style == 11u)
        effect = RayFlameEffect(v, item);
    else
        effect = ShadeRayStyle(style, C, item.p0, item.p1, item.p2);
    return RayFinish(v, style, item.primary, item.meta, effect);
}
)hlsl";
