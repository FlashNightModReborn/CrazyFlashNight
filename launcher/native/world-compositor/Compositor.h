#pragma once
#include <windows.h>
#include <cstdint>

// Shared world-renderer / diagnostic harness C ABI. D3D/WinRT objects belong to the worker thread.
// lut-set-v1（2026-09-25）：新增 ProbeSetLut/ProbeClearLut——生产 3D LUT 光照路径
//（32^3 RGBA8 整块上传，PS 三线性采样；上传即启用，清除即回退矩阵/Gamma 路径）。
// 加性 ABI 3 惯例：导出集合增长不升 ABI 号，配套 Host 以严格 Export 拒绝未配对旧 DLL。
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
extern "C" {
__declspec(dllexport) void* __cdecl ProbeStartWorld(HWND source, DWORD sourcePid, HWND output, uint32_t vendor, int borderless);
__declspec(dllexport) int __cdecl ProbeRequestBorderless();
__declspec(dllexport) int __cdecl ProbeSetMatrix(void* handle, const float* settings);
// lut-set-v1（加性 ABI 3，同上游 2026-09-25 统一输入底座惯例）：上传 32^3 RGBA8
//（131072 字节，R 最快）并启用 LUT 采样路径；rgba=null 或长度语义不符返回 0。
// ProbeClearLut 关断 LUT 路径（回退矩阵/Gamma，缓冲保留）。配套 Host 严格 Export 拒绝旧 DLL。
__declspec(dllexport) int __cdecl ProbeSetLut(void* handle, const uint8_t* rgba);
__declspec(dllexport) void __cdecl ProbeClearLut(void* handle);
__declspec(dllexport) void __cdecl ProbeSetActive(void* handle, int active);
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
__declspec(dllexport) int __cdecl ProbeGetStats(void* handle, ProbeStats* stats);
__declspec(dllexport) void __cdecl ProbeStop(void* handle);
}
