#pragma once
// Camera pass runs after the lit world and all native world FX, before the HUD.
constexpr char NightVisionShader[] = R"hlsl(
Texture2D nvWorld : register(t0);
Texture3D nvLut : register(t1);
Texture2D nvEdges : register(t2);
Texture2D nvGain : register(t4);
Texture2D nvHalo : register(t5);
Texture2D nvGuide : register(t7);
Texture2D nvFeatures : register(t8);
SamplerState nvLinear : register(s0);
SamplerState nvLutLinear : register(s1);
cbuffer NvGrade : register(b0) { float4 nvRed; float4 nvGreen; float4 nvBlue; float4 nvOffset; };
cbuffer NvSettings : register(b7) {
    float4 nvA; // enabled, edge strength, width, fragment suppression
    float4 nvB; // halo strength, radius, underlay retention, glare strength
    float4 nvC; // edge RGB, glare threshold
    float4 nvD; // gain floor, recovery seconds, attack seconds, scan strength
    float4 nvE; // logical pixel UV step XY, delta seconds, LUT active
    float4 nvF; // world viewport origin XY and extent XY in backbuffer UV
    float4 nvG; // scan phase (0..1, shared seven-second cycle), padding
};
struct NvVertex {
    float4 pos:SV_POSITION; float2 uv:TEXCOORD0;
    nointerpolation float4 gaussian0:TEXCOORD1;
    nointerpolation float4 gaussian1:TEXCOORD2;
};
NvVertex NVS(uint id:SV_VertexID) {
    NvVertex v;
    v.uv=float2((id<<1u)&2u,id&2u);
    v.pos=float4(v.uv*float2(2,-2)+float2(-1,1),0,1);
    // BEGIN NV_KERNEL: shared with the generated laboratory vertex shader.
    // Uniform weights are evaluated for three vertices, not every pixel.
    // Keep raw coefficients and the original summation order for parity.
    float radius=1.8+2.2*nvA.w;
    float4 k0=exp(-.5*float4(0,1,4,9)/(radius*radius));
    float4 k1=float4(exp(-.5*float3(16,25,36)/(radius*radius)),0);
    float total=0.0;
    total+=k1.z;total+=k1.y;total+=k1.x;
    total+=k0.w;total+=k0.z;total+=k0.y;total+=k0.x;
    total+=k0.y;total+=k0.z;total+=k0.w;
    total+=k1.x;total+=k1.y;total+=k1.z;
    k1.w=total;
    // END NV_KERNEL
    v.gaussian0=k0;v.gaussian1=k1;
    return v;
}
float3 nvRaw(float2 uv) { return nvWorld.SampleLevel(nvLinear,nvF.xy+uv*nvF.zw,0).rgb; }
// BEGIN NV_STRUCTURE: shared with the generated LUT laboratory shaders.
float3 nvUnderlayBlend(float3 raw,float3 guide,float suppression) {
    // Smooth fine texture in the underlay itself. Strong material/actor
    // boundaries retain original coverage instead of becoming soft halos.
    float3 difference=abs(raw-guide);
    float protect=smoothstep(.18,.45,max(difference.r,max(difference.g,difference.b)));
    return lerp(raw,guide,smoothstep(0.0,.65,suppression)*(1.0-.75*protect));
}
float3 nvAt(float2 uv,bool structure) {
    return structure?nvGuide.SampleLevel(nvLinear,uv,0).rgb:nvRaw(uv);
}
float3 nvGradient(float2 uv,bool structure) {
    float2 d=nvE.xy;
    float3 a=nvAt(uv-d,structure),b=nvAt(uv+float2(0,-d.y),structure),c=nvAt(uv+float2(d.x,-d.y),structure);
    float3 f=nvAt(uv+float2(-d.x,0),structure),g=nvAt(uv+float2(d.x,0),structure);
    float3 h=nvAt(uv+float2(-d.x,d.y),structure),i=nvAt(uv+float2(0,d.y),structure),j=nvAt(uv+d,structure);
    float3 gx=(c+2.0*g+j-a-2.0*f-h)*.25,gy=(h+2.0*i+j-a-2.0*b-c)*.25;
    float3 power=gx*gx+gy*gy;
    // Keep chromatic boundaries as well as luminance boundaries. A single
    // winning channel provides a consistent direction for the local tensor.
    float2 slope=power.r>=power.g && power.r>=power.b?float2(gx.r,gy.r)
        :(power.g>=power.b?float2(gx.g,gy.g):float2(gx.b,gy.b));
    return float3(slope,length(slope));
}
float4 NAPS(NvVertex v):SV_TARGET {
    float3 g=nvGradient(v.uv,false);
    return float4(g.xy*.5+.5,min(g.z,1.0),1.0);
}
float3 nvGaussian(NvVertex v,float2 direction,bool horizontal) {
    float3 sum=float3(0,0,0);
    [unroll] for(int n=-6;n<=6;n++) {
        int index=abs(n);
        float weight=index==0?v.gaussian0.x:(index==1?v.gaussian0.y:(index==2?v.gaussian0.z
            :(index==3?v.gaussian0.w:(index==4?v.gaussian1.x:(index==5?v.gaussian1.y:v.gaussian1.z)))));
        float2 p=v.uv+direction*float(n);
        sum+=(horizontal?nvRaw(p):nvGuide.SampleLevel(nvLinear,p,0).rgb)*weight;
    }
    return sum/v.gaussian1.w;
}
float4 NHPS(NvVertex v):SV_TARGET {return float4(nvGaussian(v,float2(nvE.x,0),true),1.0);}
float4 NVPS(NvVertex v):SV_TARGET {return float4(nvGaussian(v,float2(0,nvE.y),false),1.0);}
float4 NJPS(NvVertex v):SV_TARGET {
    // Two rolling joint-bilateral iterations reconstruct large boundaries from
    // the original image using the smoothed guide, shared by edges and underlay.
    float3 center=nvGuide.SampleLevel(nvLinear,v.uv,0).rgb,sum=float3(0,0,0);
    float total=0.0,radius=1.8+2.2*nvA.w;
    [unroll] for(int y=-2;y<=2;y++) [unroll] for(int x=-2;x<=2;x++) {
        float2 offset=float2(x,y)*2.0;
        float2 p=v.uv+offset*nvE.xy;
        float3 delta=center-nvGuide.SampleLevel(nvLinear,p,0).rgb;
        float weight=exp(-dot(offset,offset)/(2.0*radius*radius)-dot(delta,delta)/(.16*.16*2.0));
        sum+=nvRaw(p)*weight;total+=weight;
    }
    return float4(sum/max(total,.00001),1.0);
}
float4 NEPS(NvVertex v):SV_TARGET {
    float edge;
    [branch] if(nvA.w<=0.0) {
        float magnitude=nvGradient(v.uv,false).z;
        edge=smoothstep(.018*.65,.018*2.2,magnitude);
    } else {
        float3 f=nvFeatures.SampleLevel(nvLinear,v.uv,0).rgb;
        float2 fine=f.xy*2.0-1.0;
        float3 structure=nvGradient(v.uv,true);
        float xx=0.0,yy=0.0,xy=0.0,density=0.0;
        [unroll] for(int y=-1;y<=1;y++) [unroll] for(int x=-1;x<=1;x++) {
            float weight=float((x==0?2:1)*(y==0?2:1))/16.;
            float3 feature=nvFeatures.SampleLevel(nvLinear,v.uv+float2(x,y)*nvE.xy*3.0,0).rgb;
            float2 slope=feature.xy*2.0-1.0;
            xx+=slope.x*slope.x*weight;yy+=slope.y*slope.y*weight;xy+=slope.x*slope.y*weight;
            float relativeDensity=smoothstep(max(.008,f.z*.25),max(.025,f.z*.8),feature.z);
            density+=max(smoothstep(.025,.085,feature.z),relativeDensity)*weight;
        }
        float coherence=sqrt((xx-yy)*(xx-yy)+4.0*xy*xy)/(xx+yy+.00001);
        // Sparse, coherent thin strokes survive even if the scale filter loses
        // them. Dense isotropic gravel/mesh does not get this detail bypass.
        float2 tangent=float2(-fine.y,fine.x)/max(length(fine),.00001);
        float along=0.0;
        [unroll] for(int n=0;n<4;n++) {
            float distance=n<2?1.5:3.0;
            float side=n==0 || n==2?1.0:-1.0;
            float3 neighbor=nvFeatures.SampleLevel(nvLinear,v.uv+tangent*nvE.xy*distance*side,0).rgb;
            float agreement=max(0.0,dot(fine,neighbor.xy*2.0-1.0))/(f.z*neighbor.z+.00001);
            along+=smoothstep(.35,.8,agreement)*smoothstep(.025,.085,neighbor.z)*.25;
        }
        float thin=max(smoothstep(.45,.85,coherence),smoothstep(.35,.8,along))
            *(1.0-smoothstep(.45,.82,density));
        float threshold=.018+.055*nvA.w;
        float raw=smoothstep(threshold*.65,threshold*2.2,f.z);
        float agreement=abs(dot(fine,structure.xy))/(f.z*structure.z+.00001);
        float persistence=smoothstep(.14,.50,structure.z/max(f.z,.04));
        // The structure scale decides eligibility, not stroke position or
        // brightness. Draw the original gradient so narrow real boundaries
        // are not dimmed or displaced by the low-frequency guide.
        // Only sustained structures and sparse coherent strokes receive strong
        // emphasis. Actor silhouettes are protected by the semantic Flash rim,
        // rather than by brightening every discarded environmental detail.
        float textureEvidence=smoothstep(.55,.9,density)*(1.0-smoothstep(.65,.95,coherence));
        float detailFloor=lerp(.025,.002,textureEvidence);
        float keep=raw*max(detailFloor,max((.6+.4*smoothstep(.2,.8,agreement))*persistence,thin*.95));
        // Do not restore contrast to low-confidence residual texture: the old
        // soft boost made dense ground shimmer even after successful filtering.
        edge=lerp(raw,keep,smoothstep(0.0,.65,nvA.w));
    }
    float2 d=nvE.xy;
    // Quiet the viewport border; clamped sampling must not invent a frame.
    float2 border=min(v.uv,1.0-v.uv)/d;
    edge*=saturate(min(border.x,border.y)-.5);
    return float4(edge,0,0,1);
}
// END NV_STRUCTURE
float nvBlur(float2 uv,float2 direction) {
    float value=nvEdges.SampleLevel(nvLinear,uv,0).r*.196482;
    [unroll] for(int n=1;n<=3;n++) {
        float weight=n==1?.176032:(n==2?.120981:.064759);
        value+=(nvEdges.SampleLevel(nvLinear,uv+direction*n,0).r
            +nvEdges.SampleLevel(nvLinear,uv-direction*n,0).r)*weight;
    }
    return value;
}
float4 NBPS(NvVertex v):SV_TARGET { return float4(nvBlur(v.uv,float2(nvE.x*nvB.y,0)),0,0,1); }
float nvLightWeight(float2 uv) {
    if(pointControl.x<.5 || pointControl.y<=0) return 0;
    float weight=0;
    if(pointControl.z>=.5) weight=pointField.SampleLevel(pointSamplerLinear,uv,0).a;
    if(sceneControl.x>=.5) {
        float2 world=(uv*float2(1024,576)-pointCamera.xy)/max(pointCamera.z,.001);
        float2 su=(world-sceneRegion.xy)*sceneRegion.zw;
        if(all(su>=0) && all(su<=1)) weight+=scenePointField.SampleLevel(pointSamplerLinear,su,0).a;
    }
    return max(weight,0)*pointControl.y;
}
float4 NMPS(NvVertex v):SV_TARGET {
    // Actual HDR illumination drives adaptation; a white painted wall or a
    // white inventory icon never qualifies as a lamp from its RGB alone.
    float total=0,peak=0;
    [loop] for(int y=0;y<9;y++) [loop] for(int x=0;x<16;x++) {
        float w=nvLightWeight((float2(x,y)+.5)/float2(16,9));
        total+=w;peak=max(peak,w);
    }
    float pressure=(total/144*3+peak*.06)/nvC.w;
    float target=max(nvD.x,1/(1+pressure*nvB.w));
    float old=nvGain.Load(int3(0,0,0)).r;
    float seconds=target<old?nvD.z:nvD.y;
    float gain=lerp(old,target,1-exp(-nvE.z/max(seconds,.01)));
    return float4(gain,0,0,1);
}
float3 nvGrade(float3 raw) {
    float3 graded=float3(0,0,0);
    [branch] if(nvE.w>=.5) graded=nvLut.SampleLevel(nvLutLinear,(saturate(raw)*31+.5)/32,0).rgb;
    else {
        float4 c=float4(raw,1);
        graded=pow(saturate(float3(dot(nvRed,c),dot(nvGreen,c),dot(nvBlue,c))+nvOffset.rgb),1/max(nvOffset.w,.001));
    }
    return graded;
}
// BEGIN NV_INSTRUMENT: shared with the generated LUT laboratory shader.
float3 nvInstrument(float3 color,float2 uv,float strength,float phase) {
    if(strength<=0.0)return color;
    // Eight-logical-pixel rows drift by one row per cycle, with analytic pixel
    // coverage. Never feed instrument texture back into structure detection.
    float y=uv.y*576.0;
    float footprint=max(fwidth(y),0.001);
    float aperture=3.14159265*footprint/8.0;
    float coverage=(sin(aperture)/aperture)*(1.0-smoothstep(2.0,4.0,footprint));
    float rows=sin(y*0.785398163-phase*6.28318531)*coverage;
    // A distinct descending front, followed by a longer fading trail. Both
    // enter/exit outside the viewport, so the cycle has no brightness jump.
    float offset=y-(phase*696.0-24.0);
    float frontWidth=max(1.5,footprint*0.5);
    float front=1.0-smoothstep(frontWidth,frontWidth+3.0,abs(offset));
    float trail=(1.0-smoothstep(0.0,96.0,max(-offset,0.0)))
        *(1.0-smoothstep(-2.0,4.0,offset));
    // Multiplicative modulation preserves ink and material colors. The stronger
    // front stays local; the rest of the camera retains the existing fine rows.
    return color*(1.0+strength*(0.5*rows+2.0*front+0.85*trail));
}
// END NV_INSTRUMENT
float4 NFPS(NvVertex v):SV_TARGET {
    float3 raw=nvRaw(v.uv);
    [branch] if(nvB.z<1.0 && nvA.w>0.0)
        raw=nvUnderlayBlend(raw,nvGuide.SampleLevel(nvLinear,v.uv,0).rgb,nvA.w);
    float3 color=nvGrade(raw)*nvB.z;
    float edge=0,halo=0;
    [branch] if(nvA.y>0) {
        // Fractional logical width and bilinear masks retain diagonal coverage.
        float2 width=nvE.xy*max(0,nvA.z-.5);
        edge=nvEdges.SampleLevel(nvLinear,v.uv,0).r;
        edge=max(edge,nvEdges.SampleLevel(nvLinear,v.uv+float2(width.x,0),0).r);
        edge=max(edge,nvEdges.SampleLevel(nvLinear,v.uv-float2(width.x,0),0).r);
        edge=max(edge,nvEdges.SampleLevel(nvLinear,v.uv+float2(0,width.y),0).r);
        edge=max(edge,nvEdges.SampleLevel(nvLinear,v.uv-float2(0,width.y),0).r);
        halo=nvHalo.SampleLevel(nvLinear,v.uv,0).r*.196482;
        [unroll] for(int n=1;n<=3;n++) {
            float weight=n==1?.176032:(n==2?.120981:.064759);
            float2 delta=float2(0,nvE.y*nvB.y*n);
            halo+=(nvHalo.SampleLevel(nvLinear,v.uv+delta,0).r
                +nvHalo.SampleLevel(nvLinear,v.uv-delta,0).r)*weight;
        }
    }
    // Horizontal blur is t5, vertical convolution finishes the halo here.
    color+=nvC.rgb*(edge+halo*nvB.x)*nvA.y;
    color=nvInstrument(color,v.uv,nvD.w,nvG.x);
    float gain=nvGain.Load(int3(0,0,0)).r;
    float glare=max(0,nvLightWeight(v.uv)/nvC.w-1);
    float wash=1-exp(-glare*.65*nvB.w);
    color=color*gain;
    color=lerp(color,lerp(float3(1,1,1),nvC.rgb,.22),wash);
    return float4(saturate(color),1);
}
)hlsl";
