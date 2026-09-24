#pragma once

#include <windows.h>
#include <unknwn.h>

// Shared composition scene ABI, version 1. Implemented by CompositionScene.cpp
// and linked into FlashCompositorNative.dll. All calls run on the creating UI
// thread; visual pointers come back AddRef'd and are released by the caller.
#ifdef __cplusplus
extern "C" {
#endif

__declspec(dllexport) int __cdecl CompositionSceneAbiVersion();
__declspec(dllexport) void* __cdecl CompositionSceneCreate(HWND output);
__declspec(dllexport) IUnknown* __cdecl CompositionSceneVisual(void* handle, int layer);
__declspec(dllexport) HRESULT __cdecl CompositionSceneUploadHud(void* handle, const void* pixels, int width, int height, int stride, int x, int y);
__declspec(dllexport) HRESULT __cdecl CompositionSceneSnapshot(void* handle, const void* pixels, int width, int height, int stride);
__declspec(dllexport) HRESULT __cdecl CompositionScenePresentation(void* handle, int modal, int frozen, int width, int height);
__declspec(dllexport) HRESULT __cdecl CompositionSceneCommit(void* handle);
__declspec(dllexport) HRESULT __cdecl CompositionSceneDestroy(void* handle);

#ifdef __cplusplus
}
#endif
