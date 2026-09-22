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
SamplerState pointSampler : register(s0);
cbuffer Settings : register(b0) { float4 rowR; float4 rowG; float4 rowB; float4 offset; };
cbuffer Sampling : register(b1) { float2 texel; float sharpness; float padding; };
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
    float3 graded = saturate(float3(dot(c,rowR), dot(c,rowG), dot(c,rowB)) + offset.rgb);
    return float4(pow(graded, 1.0 / max(offset.w, 1.0e-3)), 1);
}
)hlsl";

struct Settings { float r[4], g[4], b[4], offset[4]; };
Settings ColorMode(int mode) {
    if (mode == 1) return {{.38f,0,0,0},{0,.48f,0,0},{0,0,.72f,0},{.015f,.025f,.06f,1}};
    if (mode == 2) return {{.04252f,.14304f,.01444f,0},{.2126f,.7152f,.0722f,0},{.02126f,.07152f,.00722f,0},{0,.035f,0,1}};
    return {{1,0,0,0},{0,1,0,0},{0,0,1,0},{0,0,0,1}};
}

class Capture {
public:
    Capture(HWND source, DWORD pid, HWND output, uint32_t vendor, int fps = 0, bool borderless = false)
        : source_(source), pid_(pid), output_(output), vendor_(vendor), fps_(fps), borderless_(borderless) {
        stats_.size = sizeof(ProbeStats);
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
    void RequestProof() { proofRequested_ = true; }
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
    void Stats(ProbeStats& result) { std::lock_guard guard(mutex_); result = stats_; }

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
        ValidateSize(size.Width, size.Height);
        auto pool = Direct3D11CaptureFramePool::CreateFreeThreaded(runtimeDevice,
            DirectXPixelFormat::B8G8R8A8UIntNormalized, 2, size);
        GraphicsCaptureSession session{nullptr};
        auto arrived = pool.FrameArrived(auto_revoke, [this](auto const&, auto const&) { Signal(); });
        auto startSession = [&] {
            session = pool.CreateCaptureSession(item);
            if (auto cursor = session.try_as<IGraphicsCaptureSession2>()) cursor.IsCursorCaptureEnabled(false);
            if (borderless_) if (auto border = session.try_as<IGraphicsCaptureSession3>()) border.IsBorderRequired(false);
            session.StartCapture();
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
        if (GetWindowLongPtr(output_, GWL_EXSTYLE) & WS_EX_LAYERED) {
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

        auto Compile = [](const char* entry, const char* profile) {
            com_ptr<ID3DBlob> blob, error;
            HRESULT hr = D3DCompile(Shader, sizeof(Shader) - 1, "compositor-probe", nullptr, nullptr,
                entry, profile, D3DCOMPILE_OPTIMIZATION_LEVEL3 | D3DCOMPILE_WARNINGS_ARE_ERRORS, 0, blob.put(), error.put());
            check_hresult(hr); return blob;
        };
        auto vsCode = Compile("VS", "vs_4_0"); auto psCode = Compile("PS", "ps_4_0");
        com_ptr<ID3D11VertexShader> vs; com_ptr<ID3D11PixelShader> ps;
        check_hresult(device->CreateVertexShader(vsCode->GetBufferPointer(), vsCode->GetBufferSize(), nullptr, vs.put()));
        check_hresult(device->CreatePixelShader(psCode->GetBufferPointer(), psCode->GetBufferSize(), nullptr, ps.put()));
        com_ptr<ID3D11Buffer> constants;
        D3D11_BUFFER_DESC cb{}; cb.ByteWidth = sizeof(Settings); cb.Usage = D3D11_USAGE_DEFAULT; cb.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
        check_hresult(device->CreateBuffer(&cb, nullptr, constants.put()));
        com_ptr<ID3D11Buffer> samplingConstants;
        cb.ByteWidth=16; check_hresult(device->CreateBuffer(&cb,nullptr,samplingConstants.put()));
        com_ptr<ID3D11SamplerState> sampler;
        D3D11_SAMPLER_DESC sd{}; sd.Filter = fps_>0 ? D3D11_FILTER_MIN_MAG_MIP_LINEAR : D3D11_FILTER_MIN_MAG_MIP_POINT;
        sd.AddressU = sd.AddressV = sd.AddressW = D3D11_TEXTURE_ADDRESS_CLAMP;
        sd.MaxLOD = D3D11_FLOAT32_MAX;
        check_hresult(device->CreateSamplerState(&sd, sampler.put()));
        com_ptr<ID3D11RasterizerState> raster;
        D3D11_RASTERIZER_DESC rd{}; rd.FillMode = D3D11_FILL_SOLID; rd.CullMode = D3D11_CULL_NONE; rd.DepthClipEnable = TRUE;
        check_hresult(device->CreateRasterizerState(&rd, raster.put()));

        com_ptr<ID3D11Texture2D> texture;
        com_ptr<ID3D11ShaderResourceView> srv;
        com_ptr<ID3D11RenderTargetView> rtv;
        int textureW = 0, textureH = 0, outputW = 0, outputH = 0;
        int appliedMode = -1;
        float appliedSharpness=-1;
        double frameQpcMs = 0;
        startSession();
        uint64_t appliedSettings = 0;
        auto nextPresent = std::chrono::steady_clock::now();
        State(1, S_OK, L"GPU display path; optional diagnostic readback");
        while (!stop_) {
            if (!active_) {
                if (session) { session.Close(); session=nullptr; }
                arrived.revoke();
                pool.Close();
                std::unique_lock lock(waitMutex_);
                wake_.wait(lock,[this] { return stop_.load() || active_.load(); });
                if (stop_) break;
                size=item.Size(); ValidateSize(size.Width,size.Height);
                pool=Direct3D11CaptureFramePool::CreateFreeThreaded(runtimeDevice,DirectXPixelFormat::B8G8R8A8UIntNormalized,2,size);
                arrived=pool.FrameArrived(auto_revoke,[this](auto const&, auto const&) { Signal(); });
                startSession();
            }
            if (fps_>0) {
                std::unique_lock lock(waitMutex_);
                wake_.wait_until(lock,nextPresent,[this] { return stop_.load() || !active_.load(); });
                if (stop_) break;
                if (!active_) continue;
            }
            uint64_t observedWake=wakeVersion_.load();
            uint64_t settingsVersion; bool custom; Settings settings;
            { std::lock_guard guard(mutex_); settingsVersion=settingsVersion_; custom=custom_; settings=customSettings_; }
            if (!ValidSource()) { State(2, S_OK, L"Source closed"); break; }
            if (!IsWindow(output_)) break;
            std::unique_lock presentation(presentationMutex_);
            if (viewportHeld_) {
                presentation.unlock();
                std::unique_lock lock(waitMutex_);
                wake_.wait_for(lock,std::chrono::milliseconds(100),[this,observedWake] { return stop_.load() || wakeVersion_.load()!=observedWake; });
                continue;
            }
            auto frame = pool.TryGetNextFrame();
            RECT client{}; GetClientRect(output_, &client);
            bool fresh = static_cast<bool>(frame);
            if (!frame && (!texture || (appliedMode == mode_.load() && !proofRequested_
                    && outputW == client.right && outputH == client.bottom && appliedSettings==settingsVersion && appliedSharpness==sharpness_.load()))) {
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
            auto target = rtv.get(); context->OMSetRenderTargets(1, &target, nullptr);
            const float black[]{0,0,0,1}; context->ClearRenderTargetView(target, black);
            float scale = std::min(static_cast<float>(w)/textureW, static_cast<float>(h)/textureH);
            D3D11_VIEWPORT viewport{(w-textureW*scale)/2, (h-textureH*scale)/2, textureW*scale, textureH*scale, 0, 1};
            context->RSSetViewports(1, &viewport); context->RSSetState(raster.get());
            context->IASetInputLayout(nullptr); context->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
            context->VSSetShader(vs.get(), nullptr, 0); context->PSSetShader(ps.get(), nullptr, 0);
            auto resource = srv.get(); auto sampling = sampler.get(); auto buffer = constants.get();
            context->PSSetShaderResources(0,1,&resource); context->PSSetSamplers(0,1,&sampling); context->PSSetConstantBuffers(0,1,&buffer);
            appliedSharpness=sharpness_.load();
            float samplingValues[]{1.f/textureW,1.f/textureH,appliedSharpness,0};
            context->UpdateSubresource(samplingConstants.get(),0,nullptr,samplingValues,0,0);
            auto samplingBuffer=samplingConstants.get(); context->PSSetConstantBuffers(1,1,&samplingBuffer);
            context->Draw(3,0);
            ID3D11ShaderResourceView* empty = nullptr; context->PSSetShaderResources(0,1,&empty);
            double submit = QpcMs();
            bool proof = proofRequested_.exchange(false);
            if (proof) VerifyPixels(device.get(), context.get(), swap.get(), texture.get(), viewport, textureW, textureH, mode);
            double presentStart = QpcMs();
            HRESULT present = swap->Present(1, 0);
            check_hresult(present);
            double end = QpcMs();
            if (fps_>0) nextPresent=std::max(nextPresent+std::chrono::microseconds(1000000/fps_),std::chrono::steady_clock::now());
            {
                std::lock_guard guard(mutex_);
                stats_.received += fresh ? 1 + drained : 0; stats_.superseded += drained;
                if (present == S_OK) ++stats_.presented;
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
            ID3D11Texture2D* input, D3D11_VIEWPORT vp, int width, int height, int mode) {
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
                float result = settings.offset[channel];
                for (int j = 0; j < 4; ++j) result += c[j]*rows[channel][j];
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
    static void ValidateSize(int width, int height) {
        if (width <= 0 || height <= 0 || width > 8192 || height > 8192)
            throw hresult_error(E_INVALIDARG, L"Capture/output dimensions outside prototype bounds");
    }
    HWND source_, output_; DWORD pid_; uint32_t vendor_;
    std::atomic<bool> stop_{false}; std::atomic<int> mode_{0};
    std::atomic<bool> proofRequested_{false};
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
    Settings customSettings_{}; bool custom_=false; uint64_t settingsVersion_=0;
};
}

uint32_t __cdecl ProbeGetAbiVersion() { return 3; }
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
int __cdecl ProbeGetStats(void* handle, ProbeStats* stats) {
    if (!handle || !stats || stats->size != sizeof(ProbeStats)) return 0;
    static_cast<Capture*>(handle)->Stats(*stats); return 1;
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
void __cdecl ProbeSetActive(void* handle, int active) { if (handle) static_cast<Capture*>(handle)->Active(active!=0); }
