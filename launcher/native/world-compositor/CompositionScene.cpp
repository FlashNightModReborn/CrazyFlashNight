#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <d3d11.h>
#include <dxgi1_2.h>
#include <dcomp.h>
#include <winrt/base.h>

#ifndef CF7_C1_SCENE_COMPAT
#include "CompositionScene.h"
#endif

// Shared composition scene extracted from the C1 input-ownership fixture.
// Creates no input window and observes no keys. All calls on the creating UI
// thread. Visual references returned with AddRef. Building this file with
// CF7_C1_SCENE_COMPAT emits the legacy C1Scene* export names instead, so the
// isolated fixture DLL keeps its original surface without duplicating code.
namespace {
struct Scene {
    DWORD thread = GetCurrentThreadId();
    winrt::com_ptr<ID3D11Device> device;
    winrt::com_ptr<ID3D11DeviceContext> context;
    winrt::com_ptr<IDXGIFactory2> factory;
    winrt::com_ptr<IDCompositionDevice> composition;
    winrt::com_ptr<IDCompositionTarget> target;
    winrt::com_ptr<IDCompositionVisual> root, world, hud, backdrop, web, still;
    winrt::com_ptr<IDXGISwapChain1> backdropSwap, stillSwap;
    int stillWidth = 1, stillHeight = 1;
    winrt::com_ptr<IDXGISwapChain1> hudSwap;
    int hudWidth = 0, hudHeight = 0;
    explicit Scene(HWND output) {
        D3D_FEATURE_LEVEL feature;
        winrt::check_hresult(D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr,
            D3D11_CREATE_DEVICE_BGRA_SUPPORT, nullptr, 0, D3D11_SDK_VERSION, device.put(), &feature, context.put()));
        auto dxgi = device.as<IDXGIDevice>();
        winrt::com_ptr<IDXGIAdapter> adapter; winrt::check_hresult(dxgi->GetAdapter(adapter.put()));
        winrt::check_hresult(adapter->GetParent(__uuidof(IDXGIFactory2), factory.put_void()));
        winrt::check_hresult(DCompositionCreateDevice(dxgi.get(), __uuidof(IDCompositionDevice), composition.put_void()));
        winrt::check_hresult(composition->CreateTargetForHwnd(output, TRUE, target.put()));
        winrt::check_hresult(composition->CreateVisual(root.put()));
        winrt::check_hresult(composition->CreateVisual(world.put()));
        winrt::check_hresult(composition->CreateVisual(hud.put()));
        winrt::check_hresult(composition->CreateVisual(web.put()));
        winrt::check_hresult(composition->CreateVisual(backdrop.put()));
        winrt::check_hresult(composition->CreateVisual(still.put()));
        winrt::check_hresult(root->AddVisual(world.get(), FALSE, nullptr));
        winrt::check_hresult(root->AddVisual(hud.get(), TRUE, world.get()));
        winrt::check_hresult(root->AddVisual(backdrop.get(), TRUE, hud.get()));
        winrt::check_hresult(root->AddVisual(web.get(), TRUE, backdrop.get()));
        winrt::check_hresult(root->AddVisual(still.get(), TRUE, web.get()));
        const unsigned int background = 0xff101820;
        backdropSwap = Image(&background, 1, 1, 4);
        winrt::check_hresult(backdrop->SetContent(backdropSwap.get()));
        // Overscan the HWND; resizing cannot uncover strips while the UI thread
        // is inside the native move/size loop. HWND composition clips the result.
        D2D_MATRIX_3X2_F fill{16384, 0, 0, 16384, 0, 0};
        winrt::check_hresult(backdrop->SetTransform(fill));
        winrt::check_hresult(backdrop->SetContent(nullptr));
        winrt::check_hresult(still->SetContent(nullptr));
        winrt::check_hresult(target->SetRoot(root.get()));
        winrt::check_hresult(composition->Commit());
    }
    void VerifyThread() const { if (thread != GetCurrentThreadId()) throw winrt::hresult_error(RPC_E_WRONG_THREAD); }
    winrt::com_ptr<IDXGISwapChain1> Image(const void* pixels, int width, int height, int stride) {
        if (!pixels || width < 1 || height < 1 || width > 4096 || height > 4096 || stride != width * 4)
            throw winrt::hresult_invalid_argument();
        DXGI_SWAP_CHAIN_DESC1 description{};
        description.Width = width; description.Height = height; description.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
        description.SampleDesc.Count = 1; description.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
        description.BufferCount = 2; description.SwapEffect = DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL;
        description.Scaling = DXGI_SCALING_STRETCH; description.AlphaMode = DXGI_ALPHA_MODE_PREMULTIPLIED;
        winrt::com_ptr<IDXGISwapChain1> result;
        winrt::check_hresult(factory->CreateSwapChainForComposition(device.get(), &description, nullptr, result.put()));
        winrt::com_ptr<ID3D11Texture2D> buffer;
        winrt::check_hresult(result->GetBuffer(0, __uuidof(ID3D11Texture2D), buffer.put_void()));
        context->UpdateSubresource(buffer.get(), 0, nullptr, pixels, static_cast<UINT>(stride), 0);
        winrt::check_hresult(result->Present(0, 0));
        return result;
    }
    void Snapshot(const void* pixels, int width, int height, int stride) {
        VerifyThread();
        auto next = Image(pixels, width, height, stride);
        winrt::check_hresult(still->SetContent(next.get()));
        stillSwap = std::move(next); stillWidth = width; stillHeight = height;
    }
    void Presentation(bool modal, bool frozen, int width, int height) {
        VerifyThread();
        if (width < 1 || height < 1 || width > 16384 || height > 16384) throw winrt::hresult_invalid_argument();
        const float sx = static_cast<float>(width) / stillWidth, sy = static_cast<float>(height) / stillHeight;
        const float fit = sx < sy ? sx : sy;
        D2D_MATRIX_3X2_F scale{fit, 0, 0, fit, (width - stillWidth * fit) / 2, (height - stillHeight * fit) / 2};
        winrt::check_hresult(still->SetTransform(scale));
        winrt::check_hresult(backdrop->SetContent(modal ? backdropSwap.get() : nullptr));
        winrt::check_hresult(still->SetContent(modal && frozen ? stillSwap.get() : nullptr));
        if (!modal) { winrt::check_hresult(still->SetContent(nullptr)); stillSwap = nullptr; }
        winrt::check_hresult(composition->Commit());
        // Submission ordering only; this is NOT a physical frame receipt.
        winrt::check_hresult(composition->WaitForCommitCompletion());
    }
    void Upload(const void* pixels, int width, int height, int stride, int x, int y) {
        VerifyThread();
        if (!pixels || width < 1 || height < 1 || width > 4096 || height > 4096 || stride != width * 4
            || x < 0 || y < 0 || x > 16384 || y > 16384) throw winrt::hresult_invalid_argument();
        if (!hudSwap || width != hudWidth || height != hudHeight) {
            winrt::check_hresult(hud->SetContent(nullptr)); hudSwap = nullptr;
            DXGI_SWAP_CHAIN_DESC1 description{};
            description.Width = width; description.Height = height; description.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
            description.SampleDesc.Count = 1; description.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
            description.BufferCount = 2; description.SwapEffect = DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL;
            description.Scaling = DXGI_SCALING_STRETCH; description.AlphaMode = DXGI_ALPHA_MODE_PREMULTIPLIED;
            winrt::check_hresult(factory->CreateSwapChainForComposition(device.get(), &description, nullptr, hudSwap.put()));
            winrt::check_hresult(hud->SetContent(hudSwap.get())); hudWidth = width; hudHeight = height;
        }
        winrt::com_ptr<ID3D11Texture2D> buffer;
        winrt::check_hresult(hudSwap->GetBuffer(0, __uuidof(ID3D11Texture2D), buffer.put_void()));
        context->UpdateSubresource(buffer.get(), 0, nullptr, pixels, static_cast<UINT>(stride), 0);
        winrt::check_hresult(hudSwap->Present(0, 0));
        winrt::check_hresult(hud->SetOffsetX(static_cast<float>(x)));
        winrt::check_hresult(hud->SetOffsetY(static_cast<float>(y)));
        winrt::check_hresult(composition->Commit());
    }
};
}

#ifdef CF7_C1_SCENE_COMPAT
#define CF7_SCENE_EXPORT(name) C1Scene##name
#else
#define CF7_SCENE_EXPORT(name) CompositionScene##name
#endif

extern "C" {
#ifndef CF7_C1_SCENE_COMPAT
__declspec(dllexport) int __cdecl CompositionSceneAbiVersion() { return 1; }
#endif
__declspec(dllexport) void* __cdecl CF7_SCENE_EXPORT(Create)(HWND output) {
    if (!IsWindow(output)) return nullptr;
    try { return new Scene(output); } catch (...) { return nullptr; }
}
__declspec(dllexport) IUnknown* __cdecl CF7_SCENE_EXPORT(Visual)(void* handle, int layer) {
    if (!handle || layer < 0 || layer > 2) return nullptr;
    try {
        auto scene = static_cast<Scene*>(handle); scene->VerifyThread();
        auto visual = layer == 0 ? scene->world.get() : layer == 1 ? scene->hud.get() : scene->web.get();
        visual->AddRef(); return visual;
    } catch (...) { return nullptr; }
}
__declspec(dllexport) HRESULT __cdecl CF7_SCENE_EXPORT(UploadHud)(void* handle, const void* pixels, int width, int height, int stride, int x, int y) {
    if (!handle) return E_INVALIDARG;
    try { static_cast<Scene*>(handle)->Upload(pixels, width, height, stride, x, y); return S_OK; } catch (...) { return winrt::to_hresult(); }
}
__declspec(dllexport) HRESULT __cdecl CF7_SCENE_EXPORT(Commit)(void* handle) {
    if (!handle) return E_INVALIDARG;
    try { auto scene = static_cast<Scene*>(handle); scene->VerifyThread(); return scene->composition->Commit(); } catch (...) { return winrt::to_hresult(); }
}
__declspec(dllexport) HRESULT __cdecl CF7_SCENE_EXPORT(Snapshot)(void* handle, const void* pixels, int width, int height, int stride) {
    if (!handle) return E_INVALIDARG;
    try { static_cast<Scene*>(handle)->Snapshot(pixels, width, height, stride); return S_OK; } catch (...) { return winrt::to_hresult(); }
}
__declspec(dllexport) HRESULT __cdecl CF7_SCENE_EXPORT(Presentation)(void* handle, int modal, int frozen, int width, int height) {
    if (!handle) return E_INVALIDARG;
    try { static_cast<Scene*>(handle)->Presentation(modal != 0, frozen != 0, width, height); return S_OK; } catch (...) { return winrt::to_hresult(); }
}
__declspec(dllexport) HRESULT __cdecl CF7_SCENE_EXPORT(Destroy)(void* handle) {
    if (!handle) return S_OK;
    try { auto scene = static_cast<Scene*>(handle); scene->VerifyThread(); delete scene; return S_OK; } catch (...) { return winrt::to_hresult(); }
}
}
#undef CF7_SCENE_EXPORT
