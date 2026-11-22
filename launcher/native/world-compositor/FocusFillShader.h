#pragma once
constexpr char FocusFillShader[] = R"hlsl(
Texture2D focusAtlas : register(t0);
struct FillInstance { int4 destination; int4 source; };
cbuffer FocusParams : register(b0) { float4 outputSize; FillInstance fills[4]; };
struct FocusVertex { float4 position:SV_POSITION; nointerpolation int2 offset:TEXCOORD0; };
FocusVertex FocusVS(uint vertex:SV_VertexID, uint instance:SV_InstanceID) {
    FillInstance f=fills[instance];
    float2 q=float2(vertex==1 || vertex==2 || vertex==4,vertex==2 || vertex==4 || vertex==5);
    float2 p=f.destination.xy+q*f.destination.zw;
    FocusVertex v; v.position=float4(2*p.x/outputSize.x-1,1-2*p.y/outputSize.y,0,1);
    v.offset=f.source.xy-f.destination.xy; return v;
}
float4 FocusPS(FocusVertex v):SV_TARGET {
    return focusAtlas.Load(int3(int2(v.position.xy)+v.offset,0));
}
)hlsl";
