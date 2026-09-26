#pragma once
#include <windows.h>
#include <unknwn.h>
#include <cstdint>

// Shared world-renderer / diagnostic harness C ABI. D3D/WinRT objects belong to the worker thread.
// lut-set-v1（2026-09-25）：新增 ProbeSetLut/ProbeClearLut——生产 3D LUT 光照路径
//（32^3 RGBA8 整块上传，PS 三线性采样；上传即启用，清除即回退矩阵/Gamma 路径）。
// bullet-v1（2026-09-26）：新增 ProbeSetBulletStyles/ProbeSetBulletFrame——首批子弹候选
// 的原生三角形叠加（世界视口内、天气/氛围之后、同一 grade/LUT；setter 只复制快照）。
// 当前配对 ABI 5 同时要求 LUT、天气/氛围与子弹导出，Host 严格拒绝未配对 DLL。
struct ProbeStats {
    uint32_t size, state;
    int32_t error;
    uint32_t vendor, device, featureLevel, width, height;
    uint64_t received, presented, superseded, resizes, cpuReadbacks;
    double ageMs, maxAgeMs, submitMs, presentMs, lastFrameQpcMs;
    uint32_t proofCount, proofMode, proofMaxError, proofDistinct;
    uint32_t inputPixels[3], outputPixels[3];
    wchar_t adapter[128];
    wchar_t message[256];
};
// Optional diagnostic extension; the stats/layout are unchanged in ABI 5.
struct ProbeContentStats {
    uint32_t size, count, proofCount, width, height, maxRgbError;
    uint64_t inputHash, outputHash;
};
static_assert(sizeof(ProbeContentStats)==40, "Diagnostic content layout");
extern "C" {
__declspec(dllexport) void* __cdecl ProbeStartWorld(HWND source, DWORD sourcePid, HWND output, uint32_t vendor, int borderless);
// Candidate-only unified scene. Caller owns the visual's device/Commit and must
// stop this capture before retiring its scene. This entry's signature is
// unchanged from ABI 3; new visual style exports require paired ABI 5 binaries.
__declspec(dllexport) void* __cdecl ProbeStartVisual(HWND source, DWORD sourcePid, HWND output, IUnknown* visual);
__declspec(dllexport) int __cdecl ProbeRequestBorderless();
__declspec(dllexport) int __cdecl ProbeSetMatrix(void* handle, const float* settings);
// lut-set-v1：上传 32^3 RGBA8
//（131072 字节，R 最快）并启用 LUT 采样路径；rgba=null 或长度语义不符返回 0。
// ProbeClearLut 关断 LUT 路径（回退矩阵/Gamma，缓冲保留）。配套 Host 严格 Export 拒绝旧 DLL。
__declspec(dllexport) int __cdecl ProbeSetLut(void* handle, const uint8_t* rgba);
__declspec(dllexport) void __cdecl ProbeClearLut(void* handle);
__declspec(dllexport) void __cdecl ProbeSetActive(void* handle, int active);
// Purely visual weather overlay, drawn by the
// capture worker over the same surface: type 0 none, 1 rain, 2 snow, 3 dust,
// 4 fog, 5 slash; intensity must be finite in [0,1]; quality 0..3
// (0 = full detail, 3 = suppressed). Seed reseeds the procedural layout.
__declspec(dllexport) int __cdecl ProbeSetWeather(void* handle, int type, float intensity, int quality, uint32_t seed);
// Required authored visual style. params[16] = primary RGB/size,
// secondary RGB/alpha, speed/wind/splash size/alpha, splash start/edge fade,
// two reserved zeros. Count is bounded by the native safety ceiling.
__declspec(dllexport) int __cdecl ProbeSetWeatherStyle(void* handle, int type, int count, const float* params);
// Camera from the existing AS2 F packet; world-space ground band from
// world_lighting. Coordinates are in the 1024x576 Flash stage/world units.
__declspec(dllexport) int __cdecl ProbeSetWeatherCamera(void* handle, float x, float y, float scale, float groundMin, float groundMax);
// Named atmosphere look 0 none, 1 alert, 2 medical, 3 industrial, 4 toxic,
// 5 corrosion, 6 cold iron, 7 ambush, 8 banquet, 9 blood moon, 10 incense,
// 11 custom. params[12] = custom RGB/alpha/radial/pulse/radians/s/min/max.
// Named looks require ProbeSetAtmosphereStyle before activation.
__declspec(dllexport) int __cdecl ProbeSetAtmosphere(void* handle, int preset, const float* params);
// Authored atmosphere catalog: primary RGB/base, secondary RGB/edge,
// motion/rate/frequency XY, focus XY/falloff/mix. Flash has no draw fallback.
__declspec(dllexport) int __cdecl ProbeSetAtmosphereStyle(void* handle, int family, const float* params);
// ABI 5 bullet candidates. styles[16*count]: triangle v0.xy,v1.xy,v2.xy,
// fill RGB, glow RGB, blur X/Y (style units), hasGlow 0/1, reserved 0.
// count<=16; styles==null only with count 0, which clears.
__declspec(dllexport) int __cdecl ProbeSetBulletStyles(void* handle, const float* styles, int count);
// items[8*count]: style index, world x/y, rotation deg, scale %, alpha %,
// reserved 0. count<=256; count 0 clears. stage = camera + world*cameraScale.
__declspec(dllexport) int __cdecl ProbeSetBulletFrame(void* handle, const float* items, int count, float cameraX, float cameraY, float cameraScale);
__declspec(dllexport) uint32_t __cdecl ProbeGetAbiVersion();
__declspec(dllexport) void* __cdecl ProbeStart(HWND source, DWORD sourcePid, HWND output, uint32_t vendor);
__declspec(dllexport) int __cdecl ProbeSetCrop(void* handle, int x, int y, int width, int height);
__declspec(dllexport) int __cdecl ProbeSetViewport(void* handle, int x, int y, int width, int height, double notBefore);
__declspec(dllexport) void __cdecl ProbeHoldViewport(void* handle);
__declspec(dllexport) int __cdecl ProbeSetSharpness(void* handle, float value);
__declspec(dllexport) void __cdecl ProbeSetMode(void* handle, int mode);
__declspec(dllexport) void __cdecl ProbeRequestProof(void* handle);
// Dev-only LUT lab readback: newest captured (pre-grade) frame into a caller BGRA8 buffer.
// 1 ok; 0 invalid argument; -1 no valid frame (inactive/occluded/minimized/pool not ready);
// -2 buffer too small or size query (buffer=null), out dims filled; -3 busy; -4 worker timeout; -5 GPU readback failed.
__declspec(dllexport) int __cdecl ProbeGrabLatestFrame(void* handle, uint8_t* buffer, uint32_t bufferSize, uint32_t* outWidth, uint32_t* outHeight);
__declspec(dllexport) void __cdecl ProbeRequestContentProof(void* handle);
__declspec(dllexport) int __cdecl ProbeGetContentStats(void* handle, ProbeContentStats* stats);
__declspec(dllexport) int __cdecl ProbeGetStats(void* handle, ProbeStats* stats);
// New paired hosts require actual WGC content size.
__declspec(dllexport) int __cdecl ProbeGetCaptureSize(void* handle, int32_t* width, int32_t* height, uint64_t* generation);
// Diagnostic scene geometry: dimensions of the last successfully presented output.
__declspec(dllexport) int __cdecl ProbeGetOutputSize(void* handle, int32_t* width, int32_t* height);
__declspec(dllexport) void __cdecl ProbeStop(void* handle);
}
