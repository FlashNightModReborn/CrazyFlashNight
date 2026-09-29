#pragma once
// Ray pass bucketing must mirror the drawPass rejection in RayShader.h RVS:
// style 11 flame beams draw in passes 0 and 3, style 9 screen beams in pass 2,
// and every other style — including the >=16 decoration spots and 42 — in
// pass 1. Buckets hold source record indices in input order so each pass
// uploads only the records RVS would not reject; empty passes emit nothing.
constexpr int RayBucketFlame=0,RayBucketOther=1,RayBucketScreen=2;
inline int RayStyleBucket(int style) {
    if(style==11) return RayBucketFlame;
    if(style==9) return RayBucketScreen;
    return RayBucketOther;
}
