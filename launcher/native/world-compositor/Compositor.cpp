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
#include <vector>
#include <tuple>

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
Texture3D lutTexture : register(t1);
SamplerState pointSampler : register(s0);
SamplerState lutSampler : register(s1);
cbuffer Settings : register(b0) { float4 rowR; float4 rowG; float4 rowB; float4 offset; };
cbuffer Sampling : register(b1) { float2 texel; float sharpness; float lutMode; };
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
    if (lutMode > 0.5) {
        // lut-set-v1：LUT 已含全部调色语义（矩阵/gamma 内嵌），三线性采样直出。
        // UNORM 3D 纹理坐标映射：c*(N-1)/N + 0.5/N（texel 中心对齐）。
        return float4(lutTexture.Sample(lutSampler, c.rgb * (31.0/32.0) + (0.5/32.0)).rgb, 1);
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
    Capture(HWND source, DWORD pid, HWND output, uint32_t vendor, int fps = 0, bool borderless = false, IUnknown* target = nullptr)
        : source_(source), pid_(pid), output_(output), vendor_(vendor), fps_(fps), borderless_(borderless) {
        stats_.size = sizeof(ProbeStats);
        if (target) check_hresult(target->QueryInterface(__uuidof(IDCompositionVisual), externalVisual_.put_void()));
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
    // lut-set-v1（加性 ABI 3）：整块 32^3 RGBA8 拷贝入库（调用方拥有输入缓冲）；上传即启用 LUT 分支，
    // 工作线程按 lutVersion_ 惰性建/更 Texture3D。ClearLut 关断 LUT 分支（矩阵路径回退），缓冲保留。
    bool SetLut(const uint8_t* rgba) {
        if (!rgba) return false;
        { std::lock_guard guard(mutex_); std::memcpy(lutData_, rgba, LutBytes); ++lutVersion_; lutEnabled_ = true; }
        Signal(); return true;
    }
    void ClearLut() {
        { std::lock_guard guard(mutex_); lutEnabled_ = false; ++lutVersion_; }
        Signal();
    }
    void RequestProof() { proofRequested_ = true; }
    // Dev-only LUT lab grab. Blocks the caller until the capture worker services the
    // request (or a bounded timeout); the GPU copy stays on the worker thread.
    int GrabLatestFrame(uint8_t* buffer, uint32_t bufferSize, uint32_t* outWidth, uint32_t* outHeight) {
        if (!outWidth || !outHeight) return 0;
        if (!buffer && bufferSize != 0) return 0;
        *outWidth = 0; *outHeight = 0;
        std::unique_lock lock(grabMutex_);
        if (grabPending_) return -3;
        grabBuffer_ = buffer; grabBufferSize_ = bufferSize;
        grabWidth_ = grabHeight_ = 0; grabResult_ = 0;
        grabPending_ = true; grabRequested_ = true;
        Signal();
        grabDone_.wait_for(lock, std::chrono::seconds(2), [this] { return !grabPending_; });
        if (grabPending_) {
            // Worker gone or wedged: invalidate so a late service writes nothing.
            grabPending_ = false; grabBuffer_ = nullptr; grabBufferSize_ = 0;
            return -4;
        }
        *outWidth = grabWidth_; *outHeight = grabHeight_;
        return grabResult_;
    }
    void RequestContentProof() { contentRequested_=true; proofRequested_=true; }
    void ContentStats(ProbeContentStats& result) { std::lock_guard guard(mutex_); result=contentStats_; }
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
    void CaptureSize(int32_t& width,int32_t& height,uint64_t& generation) { std::lock_guard guard(mutex_); width=captureWidth_;height=captureHeight_;generation=captureGeneration_; }
    bool OutputSize(int32_t& width,int32_t& height) { std::lock_guard guard(mutex_); width=presentedOutputW_;height=presentedOutputH_;return stats_.state!=3 && width>0 && height>0; }

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
        { std::lock_guard guard(mutex_); captureWidth_=size.Width;captureHeight_=size.Height; }
        ValidateSize(size.Width, size.Height);
        auto pool = Direct3D11CaptureFramePool::CreateFreeThreaded(runtimeDevice,
            DirectXPixelFormat::B8G8R8A8UIntNormalized, 2, size);
        GraphicsCaptureSession session{nullptr};
        auto arrived = pool.FrameArrived(auto_revoke, [this](auto const&, auto const&) { Signal(); });
        auto frameSignature=[&] { return std::make_tuple(IsZoomed(source_)!=FALSE,
            GetWindowLongW(source_,GWL_STYLE)&(WS_CAPTION|WS_THICKFRAME),GetDpiForWindow(source_)); };
        auto sessionFrame=frameSignature();
        auto startSession = [&] {
            sessionFrame=frameSignature();
            session = pool.CreateCaptureSession(item);
            if (auto cursor = session.try_as<IGraphicsCaptureSession2>()) cursor.IsCursorCaptureEnabled(false);
            if (borderless_) if (auto border = session.try_as<IGraphicsCaptureSession3>()) border.IsBorderRequired(false);
            session.StartCapture();
            { std::lock_guard guard(mutex_); ++captureGeneration_; }
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
        if (externalVisual_) {
            swapDesc.SwapEffect = DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL;
            swapDesc.Scaling = DXGI_SCALING_STRETCH;
            check_hresult(factory2->CreateSwapChainForComposition(device.get(), &swapDesc, nullptr, swap.put()));
            check_hresult(externalVisual_->SetContent(swap.get()));
        } else if (GetWindowLongPtr(output_, GWL_EXSTYLE) & WS_EX_LAYERED) {
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
        // LUT 采样器独立：3D LUT 必须逐像素线性插值（源图采样器在游戏路径是 POINT；
        // 单 mip 链下 MIN_MAG_MIP_LINEAR 即三维线性采样，与既有枚举用法一致）。
        com_ptr<ID3D11SamplerState> lutSampler;
        D3D11_SAMPLER_DESC lsd{}; lsd.Filter = D3D11_FILTER_MIN_MAG_MIP_LINEAR;
        lsd.AddressU = lsd.AddressV = lsd.AddressW = D3D11_TEXTURE_ADDRESS_CLAMP;
        lsd.MaxLOD = 0;
        check_hresult(device->CreateSamplerState(&lsd, lutSampler.put()));
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
        // lut-set-v1 工作线程状态：纹理惰性创建，版本驱动的 UpdateSubresource（变更才上传）。
        com_ptr<ID3D11Texture3D> lutTexture;
        com_ptr<ID3D11ShaderResourceView> lutSrv;
        uint64_t appliedLut = 0, lutCopiedVersion = 0;
        bool lutActive = false;
        auto lutWork = std::make_unique<uint8_t[]>(LutBytes);
        auto nextPresent = std::chrono::steady_clock::now();
        State(1, S_OK, L"GPU display path; optional diagnostic readback");
        while (!stop_) {
            if (!active_) {
                if (session) { session.Close(); session=nullptr; }
                arrived.revoke();
                pool.Close();
                std::unique_lock lock(waitMutex_);
                wake_.wait(lock,[this] { return stop_.load() || active_.load() || grabRequested_.load(); });
                if (stop_) break;
                if (!active_) { ServiceGrab(nullptr,nullptr,nullptr,0,0); continue; }
                size=item.Size(); ValidateSize(size.Width,size.Height);
                pool=Direct3D11CaptureFramePool::CreateFreeThreaded(runtimeDevice,DirectXPixelFormat::B8G8R8A8UIntNormalized,2,size);
                arrived=pool.FrameArrived(auto_revoke,[this](auto const&, auto const&) { Signal(); });
                startSession();
            }
            if (fps_>0) {
                std::unique_lock lock(waitMutex_);
                wake_.wait_until(lock,nextPresent,[this] { return stop_.load() || !active_.load() || grabRequested_.load(); });
                if (stop_) break;
                if (!active_) continue;
            }
            if (grabRequested_.load()) { ServiceGrab(device.get(),context.get(),texture.get(),textureW,textureH); continue; }
            uint64_t observedWake=wakeVersion_.load();
            uint64_t settingsVersion; bool custom; Settings settings;
            uint64_t lutVersion; bool lutEnabled;
            { std::lock_guard guard(mutex_); settingsVersion=settingsVersion_; custom=custom_; settings=customSettings_;
                lutVersion=lutVersion_; lutEnabled=lutEnabled_;
                if (lutEnabled && lutVersion!=lutCopiedVersion) {
                    std::memcpy(lutWork.get(), lutData_, LutBytes); lutCopiedVersion=lutVersion;
                } }
            if (!ValidSource()) { State(2, S_OK, L"Source closed"); break; }
            if (!IsWindow(output_)) break;
            if(!IsIconic(source_) && frameSignature()!=sessionFrame) {
                // Recreate the WGC session, not just its buffers. On this path a
                // pool-only resize can retain the old non-client capture origin
                // even though ContentSize already reports the maximized size.
                // Output swapchain/texture and input HWNDs remain intact.
                session.Close();session=nullptr;arrived.revoke();pool.Close();
                size=item.Size();ValidateSize(size.Width,size.Height);
                pool=Direct3D11CaptureFramePool::CreateFreeThreaded(runtimeDevice,DirectXPixelFormat::B8G8R8A8UIntNormalized,2,size);
                arrived=pool.FrameArrived(auto_revoke,[this](auto const&,auto const&) {Signal();});
                startSession();continue;
            }
            std::unique_lock presentation(presentationMutex_);
            if (viewportHeld_) {
                // Geometry must remain observable while the host holds pixels
                // for a resize. Waiting for a released frame here would deadlock
                // the host's crop selection against Viewport() unholding us.
                auto heldSize=item.Size();
                { std::lock_guard guard(mutex_); captureWidth_=heldSize.Width;captureHeight_=heldSize.Height; }
                presentation.unlock();
                std::unique_lock lock(waitMutex_);
                wake_.wait_for(lock,std::chrono::milliseconds(100),[this,observedWake] { return stop_.load() || wakeVersion_.load()!=observedWake; });
                continue;
            }
            auto frame = pool.TryGetNextFrame();
            RECT client{}; GetClientRect(output_, &client);
            bool fresh = static_cast<bool>(frame);
            if (!frame && (!texture || (appliedMode == mode_.load() && !proofRequested_
                    && outputW == client.right && outputH == client.bottom && appliedSettings==settingsVersion
                    && appliedSharpness==sharpness_.load() && appliedLut==lutVersion))) {
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
                { std::lock_guard guard(mutex_); captureWidth_=content.Width;captureHeight_=content.Height; }
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
            // lut-set-v1：版本变化才触碰 GPU（建纹理一次性，之后 UpdateSubresource 整块覆盖）。
            if (lutVersion != appliedLut) {
                if (lutEnabled) {
                    if (!lutTexture) {
                        D3D11_TEXTURE3D_DESC ld{}; ld.Width=LutSize; ld.Height=LutSize; ld.Depth=LutSize;
                        ld.MipLevels=1; ld.Format=DXGI_FORMAT_R8G8B8A8_UNORM;
                        ld.Usage=D3D11_USAGE_DEFAULT; ld.BindFlags=D3D11_BIND_SHADER_RESOURCE;
                        check_hresult(device->CreateTexture3D(&ld, nullptr, lutTexture.put()));
                        check_hresult(device->CreateShaderResourceView(lutTexture.get(), nullptr, lutSrv.put()));
                    }
                    context->UpdateSubresource(lutTexture.get(), 0, nullptr, lutWork.get(),
                        LutSize*4, LutSize*LutSize*4);
                }
                lutActive = lutEnabled && lutSrv != nullptr;
                appliedLut = lutVersion;
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
            ID3D11ShaderResourceView* lutResource = lutActive ? lutSrv.get() : nullptr;
            context->PSSetShaderResources(1,1,&lutResource);
            auto lutSamp = lutSampler.get(); context->PSSetSamplers(1,1,&lutSamp);
            appliedSharpness=sharpness_.load();
            float samplingValues[]{1.f/textureW,1.f/textureH,appliedSharpness,lutActive?1.f:0.f};
            context->UpdateSubresource(samplingConstants.get(),0,nullptr,samplingValues,0,0);
            auto samplingBuffer=samplingConstants.get(); context->PSSetConstantBuffers(1,1,&samplingBuffer);
            context->Draw(3,0);
            ID3D11ShaderResourceView* empty[2]{}; context->PSSetShaderResources(0,2,empty);
            double submit = QpcMs();
            bool proof = proofRequested_.exchange(false);
            if (proof) {
                VerifyPixels(device.get(), context.get(), swap.get(), texture.get(), viewport, textureW, textureH, mode);
                if (contentRequested_.exchange(false))
                    VerifyContent(device.get(), context.get(), swap.get(), texture.get(), viewport, textureW, textureH, mode);
            }
            double presentStart = QpcMs();
            HRESULT present = swap->Present(1, 0);
            check_hresult(present);
            double end = QpcMs();
            if (fps_>0) nextPresent=std::max(nextPresent+std::chrono::microseconds(1000000/fps_),std::chrono::steady_clock::now());
            {
                std::lock_guard guard(mutex_);
                stats_.received += fresh ? 1 + drained : 0; stats_.superseded += drained;
                if (present == S_OK) { ++stats_.presented; presentedOutputW_=w; presentedOutputH_=h; }
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
    // Dev-only grab service, always on the worker thread. Answers the pending request once:
    // copies the newest cropped capture (pre-grade, BGRA8) into the caller buffer.
    void ServiceGrab(ID3D11Device* device, ID3D11DeviceContext* context, ID3D11Texture2D* texture, int width, int height) {
        std::unique_lock lock(grabMutex_);
        grabRequested_ = false;
        if (!grabPending_) return;
        int result = -1; uint32_t outW = 0, outH = 0;
        uint32_t state;
        { std::lock_guard guard(mutex_); state = stats_.state; }
        if (texture && device && context && width > 0 && height > 0
                && active_.load() && state == 1 && !IsIconic(output_)) {
            outW = static_cast<uint32_t>(width); outH = static_cast<uint32_t>(height);
            uint64_t needed = static_cast<uint64_t>(outW) * outH * 4;
            if (!grabBuffer_ || grabBufferSize_ < needed) {
                result = -2;
            } else {
                try {
                    D3D11_TEXTURE2D_DESC td{}; td.Width = outW; td.Height = outH;
                    td.MipLevels = 1; td.ArraySize = 1; td.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
                    td.SampleDesc.Count = 1; td.Usage = D3D11_USAGE_STAGING; td.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
                    com_ptr<ID3D11Texture2D> staging;
                    check_hresult(device->CreateTexture2D(&td, nullptr, staging.put()));
                    context->CopyResource(staging.get(), texture);
                    D3D11_MAPPED_SUBRESOURCE mapped{};
                    check_hresult(context->Map(staging.get(), 0, D3D11_MAP_READ, 0, &mapped));
                    for (uint32_t row = 0; row < outH; ++row)
                        std::memcpy(grabBuffer_ + static_cast<size_t>(row) * outW * 4,
                            static_cast<const uint8_t*>(mapped.pData) + static_cast<size_t>(row) * mapped.RowPitch,
                            static_cast<size_t>(outW) * 4);
                    context->Unmap(staging.get(), 0);
                    { std::lock_guard guard(mutex_); ++stats_.cpuReadbacks; }
                    result = 1;
                } catch (...) { result = -5; }
            }
        }
        grabWidth_ = outW; grabHeight_ = outH; grabResult_ = result;
        grabPending_ = false;
        lock.unlock();
        grabDone_.notify_all();
    }
    // Explicit G2 diagnostic only, raw 1:1 mode. Hash every RGB pixel in F and
    // compare that exact ROI to the pre-Present output, not S's chrome/frame rate.
    // Two full-ROI readbacks per request; never called by the game render loop
    // unless this separate diagnostic export is explicitly requested.
    void VerifyContent(ID3D11Device* device, ID3D11DeviceContext* context, IDXGISwapChain1* swap,
            ID3D11Texture2D* input, D3D11_VIEWPORT vp, int width, int height, int mode) {
        if(mode!=0 || static_cast<int>(vp.Width)!=width || static_cast<int>(vp.Height)!=height)
            throw hresult_error(E_INVALIDARG,L"Content proof requires raw 1:1 viewport");
        com_ptr<ID3D11Texture2D> output, staging;
        check_hresult(swap->GetBuffer(0,__uuidof(ID3D11Texture2D),output.put_void()));
        D3D11_TEXTURE2D_DESC td{}; td.Width=width; td.Height=height;
        td.MipLevels=td.ArraySize=td.SampleDesc.Count=1; td.Format=DXGI_FORMAT_B8G8R8A8_UNORM;
        td.Usage=D3D11_USAGE_STAGING; td.CPUAccessFlags=D3D11_CPU_ACCESS_READ;
        check_hresult(device->CreateTexture2D(&td,nullptr,staging.put()));
        auto read=[&](ID3D11Texture2D* tex,int x,int y) {
            D3D11_BOX box{static_cast<UINT>(x),static_cast<UINT>(x+width),static_cast<UINT>(y+height),1};
            context->CopySubresourceRegion(staging.get(),0,0,0,0,tex,0,&box);
            D3D11_MAPPED_SUBRESOURCE mapped{}; check_hresult(context->Map(staging.get(),0,D3D11_MAP_READ,0,&mapped));
            std::vector<uint32_t> pixels(static_cast<size_t>(width)*height);
            for(int row=0;row<height;++row)
                std::memcpy(pixels.data()+static_cast<size_t>(row)*width,
                    static_cast<const uint8_t*>(mapped.pData)+static_cast<size_t>(row)*mapped.RowPitch,static_cast<size_t>(width)*4);
            context->Unmap(staging.get(),0); return pixels;
        };
        auto in=read(input,0,0), out=read(output.get(),static_cast<int>(vp.TopLeftX),static_cast<int>(vp.TopLeftY));
        uint64_t ih=14695981039346656037ull, oh=ih; uint32_t error=0;
        for(size_t i=0;i<in.size();++i) for(int shift=0;shift<24;shift+=8) {
            uint32_t a=(in[i]>>shift)&255, b=(out[i]>>shift)&255;
            ih=(ih^a)*1099511628211ull; oh=(oh^b)*1099511628211ull;
            error=std::max(error,static_cast<uint32_t>(std::abs(static_cast<int>(a)-static_cast<int>(b))));
        }
        std::lock_guard guard(mutex_);
        contentStats_={sizeof(ProbeContentStats),contentStats_.count+1,stats_.proofCount,
            static_cast<uint32_t>(width),static_cast<uint32_t>(height),error,ih,oh};
        stats_.cpuReadbacks+=2;
    }
    static void ValidateSize(int width, int height) {
        if (width <= 0 || height <= 0 || width > 8192 || height > 8192)
            throw hresult_error(E_INVALIDARG, L"Capture/output dimensions outside prototype bounds");
    }
    HWND source_, output_; DWORD pid_; uint32_t vendor_;
    com_ptr<IDCompositionVisual> externalVisual_;
    std::atomic<bool> stop_{false}; std::atomic<int> mode_{0};
    std::atomic<bool> proofRequested_{false};
    std::atomic<bool> contentRequested_{false};
    ProbeContentStats contentStats_{sizeof(ProbeContentStats)};
    int32_t captureWidth_=0,captureHeight_=0;
    int32_t presentedOutputW_=0,presentedOutputH_=0;
    uint64_t captureGeneration_=0;
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
    // Dev-only LUT lab grab request state (grabMutex_ guards the whole struct).
    std::mutex grabMutex_; std::condition_variable grabDone_;
    std::atomic<bool> grabRequested_{false};
    bool grabPending_=false;
    uint8_t* grabBuffer_=nullptr; uint32_t grabBufferSize_=0;
    uint32_t grabWidth_=0, grabHeight_=0; int grabResult_=0;
    Settings customSettings_{}; bool custom_=false; uint64_t settingsVersion_=0;
    // lut-set-v1（加性 ABI 3）：宿主线程 SetLut/ClearLut 经 mutex_ 入库，工作线程按 lutVersion_
    // 惰性建/更 Texture3D（变更才上传，不逐帧）；ClearLut 只关断分支，GPU 纹理保留复用。
    static constexpr uint32_t LutSize = 32;
    static constexpr size_t LutBytes = static_cast<size_t>(LutSize)*LutSize*LutSize*4;
    uint8_t lutData_[LutBytes]{};
    bool lutEnabled_=false; uint64_t lutVersion_=0;
};
}

// 加性 ABI 3：新增 ProbeSetLut/ProbeClearLut（lut-set-v1 生产 LUT 路径），既有导出面不变。
uint32_t __cdecl ProbeGetAbiVersion() { return 3; }
int __cdecl ProbeGetOutputSize(void* handle, int32_t* width, int32_t* height) {
    return handle && width && height && static_cast<Capture*>(handle)->OutputSize(*width,*height) ? 1 : 0;
}
void* __cdecl ProbeStartVisual(HWND source, DWORD sourcePid, HWND output, IUnknown* visual) {
    if (!visual) return nullptr;
    try { return new Capture(source, sourcePid, output, 0, 30, false, visual); } catch (...) { return nullptr; }
}
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
int __cdecl ProbeGrabLatestFrame(void* handle, uint8_t* buffer, uint32_t bufferSize, uint32_t* outWidth, uint32_t* outHeight) {
    return handle ? static_cast<Capture*>(handle)->GrabLatestFrame(buffer, bufferSize, outWidth, outHeight) : 0;
}
void __cdecl ProbeRequestContentProof(void* handle) { if (handle) static_cast<Capture*>(handle)->RequestContentProof(); }
int __cdecl ProbeGetContentStats(void* handle, ProbeContentStats* stats) {
    if(!handle || !stats || stats->size!=sizeof(ProbeContentStats)) return 0;
    static_cast<Capture*>(handle)->ContentStats(*stats); return 1;
}
int __cdecl ProbeGetStats(void* handle, ProbeStats* stats) {
    if (!handle || !stats || stats->size != sizeof(ProbeStats)) return 0;
    static_cast<Capture*>(handle)->Stats(*stats); return 1;
}
int __cdecl ProbeGetCaptureSize(void* handle,int32_t* width,int32_t* height,uint64_t* generation) {
    if(!handle || !width || !height || !generation)return 0;
    static_cast<Capture*>(handle)->CaptureSize(*width,*height,*generation);return 1;
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
int __cdecl ProbeSetLut(void* handle, const uint8_t* rgba) {
    return handle && static_cast<Capture*>(handle)->SetLut(rgba) ? 1 : 0;
}
void __cdecl ProbeClearLut(void* handle) { if (handle) static_cast<Capture*>(handle)->ClearLut(); }
void __cdecl ProbeSetActive(void* handle, int active) { if (handle) static_cast<Capture*>(handle)->Active(active!=0); }
