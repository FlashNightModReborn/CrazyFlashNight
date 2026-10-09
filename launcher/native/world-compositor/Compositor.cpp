#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include "Compositor.h"
#include "RayPassBuckets.h"
#include <d3d11.h>
#include <dxgi1_2.h>
#include <CompositorShaders.g.h>
#include <dcomp.h>
#include <windows.graphics.capture.interop.h>
#include <windows.graphics.directx.direct3d11.interop.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Security.Authorization.AppCapabilityAccess.h>
#include <winrt/Windows.Graphics.Capture.h>
#include <winrt/Windows.Graphics.DirectX.Direct3D11.h>
#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <cstring>
#include <cmath>
#include <mutex>
#include <thread>
#include <condition_variable>
#include <vector>
#include <tuple>
#include <memory>
#include <string>

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

struct Settings { float r[4], g[4], b[4], offset[4]; };
Settings ColorMode(int mode) {
    if (mode == 1) return {{.38f,0,0,0},{0,.48f,0,0},{0,0,.72f,0},{.015f,.025f,.06f,1}};
    if (mode == 2) return {{.04252f,.14304f,.01444f,0},{.2126f,.7152f,.0722f,0},{.02126f,.07152f,.00722f,0},{0,.035f,0,1}};
    return {{1,0,0,0},{0,1,0,0},{0,0,1,0},{0,0,0,1}};
}

// This is a safety ceiling. Authored counts live in the external visual catalog.
constexpr int WeatherSafetyCap = 512;
struct WeatherState { int type = 0; float intensity = 0; int quality = 0; uint32_t seed = 0; };
struct WeatherCameraState { float x = 0, y = 0, scale = 1, groundMin = 360, groundMax = 520; };
struct AtmosphereState { int preset = 0; float params[12]{}; };
struct WeatherStyleState { int type = 0, count = 0; float params[16]{}; };
struct AtmosphereStyleState { int family = 0; float params[16]{}; };
constexpr int RayItemCap=4096,RayBatchCap=256;
struct RayFrameState { int count=0;float cameraX=0,cameraY=0,cameraScale=1;float params[RayItemCap*32]{}; };
constexpr int BulletStyleCap = 16;
// Bullet caps are safety ceilings; each item uses one procedural quad.
constexpr int BulletItemCap = 16384;
constexpr int BulletBatchCap = 1024;
struct BulletStylesState { int count = 0; float params[BulletStyleCap*32]{}; };
struct BulletFrameState { int count = 0; float cameraX = 0, cameraY = 0, cameraScale = 1; float params[BulletItemCap*8]{}; };
constexpr int CombatFxCap=512;
constexpr int PointLightCap=16;
constexpr int SceneLightCap=128;
struct SceneLightState { int count=0;float maximumResponse=0;float lights[SceneLightCap*16]{}; };
// One bounded world-space cache. Camera/viewport changes only change sampling.
class SceneLightGpu {
public:
    SceneLightGpu(ID3D11Device* d,ID3D11DeviceContext* c,ID3D11Buffer* items,ID3D11Buffer* lightParams,
        ID3D11VertexShader* vs,ID3D11PixelShader* ps,ID3D11BlendState* blend,ID3D11RasterizerState* raster)
        :device(d),context(c),lightItems(items),lightSettings(lightParams),vertex(vs),pixel(ps),blending(blend),rasterizer(raster) {
        D3D11_BUFFER_DESC bd{};bd.ByteWidth=32;bd.BindFlags=D3D11_BIND_CONSTANT_BUFFER;bd.Usage=D3D11_USAGE_DEFAULT;
        check_hresult(device->CreateBuffer(&bd,nullptr,params.put()));
    }
    uint64_t version=UINT64_MAX;int width=0,height=0,count=0;float response=0;
    bool Prepare(const SceneLightState& state,uint64_t next) {
        if(version==next)return false;version=next;count=state.count;response=state.maximumResponse;
        if(count==0)return false;
        float minX=10000000,minY=10000000,maxX=-10000000,maxY=-10000000;
        for(int n=0;n<count;n++) {
            const float* p=state.lights+n*16;
            if(p[7]==0) {minX=std::min(minX,p[0]-p[2]);maxX=std::max(maxX,p[0]+p[2]);minY=std::min(minY,p[1]-p[2]);maxY=std::max(maxY,p[1]+p[2]);}
            else for(int end=0;end<2;end++)for(int side=-1;side<=1;side+=2) {
                float x=p[0]+p[8]*p[2]*end-p[9]*p[10]*side,y=p[1]+p[9]*p[2]*end+p[8]*p[10]*side;
                minX=std::min(minX,x);maxX=std::max(maxX,x);minY=std::min(minY,y);maxY=std::max(maxY,y);
            }
        }
        minX=std::floor(minX/4)*4-4;minY=std::floor(minY/4)*4-4;maxX=std::ceil(maxX/4)*4+4;maxY=std::ceil(maxY/4)*4+4;
        float worldW=maxX-minX,worldH=maxY-minY;
        double density=std::min(.25,std::min(4096.0/worldW,4096.0/worldH));
        density=std::min(density,std::sqrt(1048576.0/(static_cast<double>(worldW)*worldH)));
        int w=std::max(2,static_cast<int>(worldW*density)),h=std::max(2,static_cast<int>(worldH*density));
        ID3D11ShaderResourceView* none=nullptr;context->PSSetShaderResources(6,1,&none);
        if(!texture || w!=width || h!=height) {
            resource=nullptr;target=nullptr;texture=nullptr;
            D3D11_TEXTURE2D_DESC td{};td.Width=w;td.Height=h;td.MipLevels=1;td.ArraySize=1;td.Format=DXGI_FORMAT_R16G16B16A16_FLOAT;
            td.SampleDesc.Count=1;td.Usage=D3D11_USAGE_DEFAULT;td.BindFlags=D3D11_BIND_RENDER_TARGET|D3D11_BIND_SHADER_RESOURCE;
            check_hresult(device->CreateTexture2D(&td,nullptr,texture.put()));
            check_hresult(device->CreateRenderTargetView(texture.get(),nullptr,target.put()));
            check_hresult(device->CreateShaderResourceView(texture.get(),nullptr,resource.put()));width=w;height=h;
        }
        region[0]=minX;region[1]=minY;region[2]=1/worldW;region[3]=1/worldH;
        float sc[8]{minX,minY,1/worldW,1/worldH,0,1,worldW/w,worldH/h};SetParameters(sc);
        float lp[16]{0,0,static_cast<float>(w),static_cast<float>(h),0,0,1,0,1,response,0,0,1,1,1,0};
        context->UpdateSubresource(lightSettings,0,nullptr,lp,0,0);context->VSSetConstantBuffers(4,1,&lightSettings);
        auto rt=target.get();context->OMSetRenderTargets(1,&rt,nullptr);const float zero[]{0,0,0,0};context->ClearRenderTargetView(rt,zero);
        D3D11_VIEWPORT view{0,0,static_cast<float>(w),static_cast<float>(h),0,1};context->RSSetViewports(1,&view);
        context->RSSetState(rasterizer);context->IASetInputLayout(nullptr);context->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
        context->VSSetShader(vertex,nullptr,0);context->PSSetShader(pixel,nullptr,0);context->OMSetBlendState(blending,nullptr,0xffffffff);
        context->VSSetConstantBuffers(5,1,&lightItems);
        for(int first=0;first<count;first+=PointLightCap) {
            int amount=std::min(PointLightCap,count-first);float batch[PointLightCap*16]{};
            std::memcpy(batch,state.lights+first*16,static_cast<size_t>(amount)*64);
            context->UpdateSubresource(lightItems,0,nullptr,batch,0,0);context->Draw(amount*6,0);
        }
        context->OMSetBlendState(nullptr,nullptr,0xffffffff);return true;
    }
    bool Bind(bool allowed) {
        bool enabled=allowed && count>0 && response>0 && resource;
        float sc[8]{region[0],region[1],region[2],region[3],enabled?1.f:0.f,0,0,0};SetParameters(sc);
        ID3D11RenderTargetView* noTarget=nullptr;context->OMSetRenderTargets(1,&noTarget,nullptr);
        auto srv=enabled?resource.get():nullptr;context->PSSetShaderResources(6,1,&srv);return enabled;
    }
private:
    void SetParameters(const float* data) {context->UpdateSubresource(params.get(),0,nullptr,data,0,0);auto b=params.get();context->VSSetConstantBuffers(6,1,&b);context->PSSetConstantBuffers(6,1,&b);}
    ID3D11Device* device;ID3D11DeviceContext* context;ID3D11Buffer *lightItems,*lightSettings;
    ID3D11VertexShader* vertex;ID3D11PixelShader* pixel;ID3D11BlendState* blending;ID3D11RasterizerState* rasterizer;
    com_ptr<ID3D11Buffer> params;com_ptr<ID3D11Texture2D> texture;com_ptr<ID3D11RenderTargetView> target;com_ptr<ID3D11ShaderResourceView> resource;
    float region[4]{};
};
struct CombatFxState {
    int count=0,casings=0,lightCount=0;float maximumLightResponse=0;
    float cameraX=0,cameraY=0,cameraScale=1;float params[CombatFxCap*16]{},lights[PointLightCap*16]{};
};

struct HudRasterFrame {
    std::shared_ptr<std::vector<uint8_t>> pixels;
    int width=0,height=0,x=0,y=0;
    uint64_t version=0;
};
// Fixed slots: damage, resources, bottom, buffs. Keep raster/cache ownership split;
// only the final backbuffer is shared. No additional HWND or readback is created.
constexpr size_t HudRasterLayerCount=5;
class HudRasterGpu {
public:
    void Draw(ID3D11Device* device,ID3D11DeviceContext* context,
        const std::array<HudRasterFrame,HudRasterLayerCount>& frames,int outputWidth,int outputHeight,ProbeHudRasterStats& stats) {
        stats.visibleLayers=0;
        for(const auto& frame:frames)if(frame.pixels)++stats.visibleLayers;
        if(!stats.visibleLayers)return;
        if(!vertex) {
            check_hresult(device->CreateVertexShader(CompositorShaders::HVS.data,CompositorShaders::HVS.size,nullptr,vertex.put()));
            check_hresult(device->CreatePixelShader(CompositorShaders::HPS.data,CompositorShaders::HPS.size,nullptr,pixel.put()));
            D3D11_BUFFER_DESC buffer{};buffer.ByteWidth=32;buffer.BindFlags=D3D11_BIND_CONSTANT_BUFFER;
            check_hresult(device->CreateBuffer(&buffer,nullptr,parameters.put()));
            D3D11_BLEND_DESC blend{};auto& target=blend.RenderTarget[0];
            target.BlendEnable=TRUE;target.SrcBlend=D3D11_BLEND_ONE;target.DestBlend=D3D11_BLEND_INV_SRC_ALPHA;
            target.BlendOp=D3D11_BLEND_OP_ADD;target.SrcBlendAlpha=D3D11_BLEND_ONE;
            target.DestBlendAlpha=D3D11_BLEND_INV_SRC_ALPHA;target.BlendOpAlpha=D3D11_BLEND_OP_ADD;
            target.RenderTargetWriteMask=D3D11_COLOR_WRITE_ENABLE_ALL;
            check_hresult(device->CreateBlendState(&blend,blending.put()));
        }
        D3D11_VIEWPORT viewport{0,0,static_cast<float>(outputWidth),static_cast<float>(outputHeight),0,1};
        context->RSSetViewports(1,&viewport);
        context->VSSetShader(vertex.get(),nullptr,0);context->PSSetShader(pixel.get(),nullptr,0);
        auto constant=parameters.get();context->VSSetConstantBuffers(0,1,&constant);
        context->OMSetBlendState(blending.get(),nullptr,0xffffffff);
        // The opaque bottom chassis must stay behind the resource gauges.
        for(size_t i:std::array<size_t,HudRasterLayerCount>{0,2,1,3,4}) {
            const auto& frame=frames[i];if(!frame.pixels)continue;
            auto& layer=layers[i];
            if(!layer.texture || frame.width>layer.width || frame.height>layer.height) {
                layer.width=std::max(layer.width,(frame.width+63)&~63);
                layer.height=std::max(layer.height,(frame.height+63)&~63);
                D3D11_TEXTURE2D_DESC description{};description.Width=layer.width;description.Height=layer.height;
                description.MipLevels=1;description.ArraySize=1;description.Format=DXGI_FORMAT_B8G8R8A8_UNORM;
                description.SampleDesc.Count=1;description.BindFlags=D3D11_BIND_SHADER_RESOURCE;
                layer.resource=nullptr;layer.texture=nullptr;
                check_hresult(device->CreateTexture2D(&description,nullptr,layer.texture.put()));
                check_hresult(device->CreateShaderResourceView(layer.texture.get(),nullptr,layer.resource.put()));
                layer.version=0;
            }
            if(layer.version!=frame.version) {
                D3D11_BOX region{0,0,0,static_cast<UINT>(frame.width),static_cast<UINT>(frame.height),1};
                context->UpdateSubresource(layer.texture.get(),0,&region,frame.pixels->data(),frame.width*4,0);
                layer.version=frame.version;++stats.uploads;stats.uploadedBytes+=frame.pixels->size();
            }
            float values[8]{static_cast<float>(frame.x),static_cast<float>(frame.y),
                static_cast<float>(frame.width),static_cast<float>(frame.height),
                static_cast<float>(outputWidth),static_cast<float>(outputHeight),0,0};
            context->UpdateSubresource(parameters.get(),0,nullptr,values,0,0);
            auto resource=layer.resource.get();context->PSSetShaderResources(0,1,&resource);
            context->Draw(6,0);++stats.draws;
        }
        ID3D11ShaderResourceView* empty=nullptr;context->PSSetShaderResources(0,1,&empty);
        context->OMSetBlendState(nullptr,nullptr,0xffffffff);
    }
private:
    struct Layer { com_ptr<ID3D11Texture2D> texture;com_ptr<ID3D11ShaderResourceView> resource;
        int width=0,height=0;uint64_t version=0; };
    std::array<Layer,HudRasterLayerCount> layers;
    com_ptr<ID3D11VertexShader> vertex;com_ptr<ID3D11PixelShader> pixel;
    com_ptr<ID3D11Buffer> parameters;com_ptr<ID3D11BlendState> blending;
};

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
    // lut-set-v1：整块 32^3 RGBA8 拷贝入库（调用方拥有输入缓冲）；上传即启用 LUT 分支，
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
    int GrabLatestFrame(uint8_t* buffer, uint32_t bufferSize, uint32_t* outWidth, uint32_t* outHeight, bool composite=false) {
        if (!outWidth || !outHeight) return 0;
        if (!buffer && bufferSize != 0) return 0;
        *outWidth = 0; *outHeight = 0;
        std::unique_lock lock(grabMutex_);
        if (grabPending_) return -3;
        grabBuffer_ = buffer; grabBufferSize_ = bufferSize;
        grabWidth_ = grabHeight_ = 0; grabResult_ = 0;
        grabComposite_=composite;grabPending_ = true; grabRequested_ = true;
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
    void WorkStats(ProbeWorkStats& result) { std::lock_guard guard(mutex_); result=workStats_; }
    bool HudRaster(int layer,const void* pixels,int width,int height,int stride,int x,int y) {
        if(layer<0 || layer>=static_cast<int>(HudRasterLayerCount) || stop_)return false;
        HudRasterFrame frame;
        if(pixels) {
            if(width<1 || height<1 || width>4096 || height>4096 || stride<width*4 || stride>16384
                || stride%4!=0 || x<0 || y<0 || x>16384 || y>16384)return false;
            frame.width=width;frame.height=height;frame.x=x;frame.y=y;
            frame.pixels=std::make_shared<std::vector<uint8_t>>(static_cast<size_t>(width)*height*4);
            for(int row=0;row<height;++row)std::memcpy(frame.pixels->data()+static_cast<size_t>(row)*width*4,
                static_cast<const uint8_t*>(pixels)+static_cast<size_t>(row)*stride,static_cast<size_t>(width)*4);
        } else if(width || height || stride || x || y)return false;
        { std::lock_guard guard(mutex_);frame.version=++hudVersion_;hudFrames_[layer]=frame;
            ++hudStats_.accepted;if(frame.pixels)hudStats_.copiedBytes+=frame.pixels->size(); }
        Signal();return true;
    }
    void HudRasterStats(ProbeHudRasterStats& result) {std::lock_guard guard(mutex_);result=hudStats_;}
    void TimingStats(ProbeTimingStats& result) {
        std::array<TimingSample,256> samples;
        size_t count;
        {
            std::lock_guard guard(mutex_);
            samples=timingSamples_;count=timingCount_;
            result={sizeof(ProbeTimingStats)};
            result.count=static_cast<uint32_t>(count);result.presented=stats_.presented;
            result.lastPresentQpcMs=count ? samples[(timingNext_+255)%256].at : 0;
        }
        std::array<double,256> values;
        auto percentile=[&](double TimingSample::* field,double rank) {
            size_t size=0;
            for(size_t i=0;i<count;i++)if(samples[i].*field>=0)values[size++]=samples[i].*field;
            if(size==0)return 0.;
            std::sort(values.begin(),values.begin()+size);
            return values[static_cast<size_t>(std::ceil(rank*static_cast<double>(size)))-1];
        };
        for(size_t i=0;i<count;i++) {
            result.intervalCount+=samples[i].interval>=0?1:0;
            result.freshCount+=samples[i].age>=0?1:0;
        }
        result.intervalP50Ms=percentile(&TimingSample::interval,.5);
        result.intervalP95Ms=percentile(&TimingSample::interval,.95);
        result.intervalP99Ms=percentile(&TimingSample::interval,.99);
        result.intervalMaxMs=percentile(&TimingSample::interval,1.);
        result.submitP95Ms=percentile(&TimingSample::submit,.95);
        result.presentP95Ms=percentile(&TimingSample::present,.95);
        result.freshAgeP95Ms=percentile(&TimingSample::age,.95);
    }
    void SceneLightStats(ProbeSceneLightStats& result) { std::lock_guard guard(mutex_); result=sceneLightStats_; }
    bool SceneLights(const float* lights,int count,float response) {
        if(count<0 || count>SceneLightCap || (count>0 && !lights) || !std::isfinite(response) || response<0 || response>.8f)return false;
        for(int n=0;n<count;n++) {
            const float* p=lights+n*16;
            for(int i=0;i<16;i++)if(!std::isfinite(p[i]))return false;
            if(std::abs(p[0])>1000000 || std::abs(p[1])>1000000 || p[2]<1 || p[2]>1024 || p[3]<0 || p[3]>2
                || p[4]<0 || p[4]>1 || p[5]<0 || p[5]>1 || p[6]<0 || p[6]>1
                || (p[7]!=0 && p[7]!=1 && p[7]!=2) || p[11]!=0 || p[12]!=0 || p[13]!=0 || p[14]!=0 || p[15]!=0)return false;
            if(p[7]==0 ? (p[8]!=0 || p[9]!=0 || p[10]!=0) : (std::abs(p[8]*p[8]+p[9]*p[9]-1)>.01f || p[10]<.5f || p[10]>512))return false;
        }
        {std::lock_guard guard(mutex_);
            if(sceneLights_.count==count && sceneLights_.maximumResponse==response
                && (count==0 || std::memcmp(sceneLights_.lights,lights,static_cast<size_t>(count)*64)==0))return true;
            sceneLights_.count=count;sceneLights_.maximumResponse=response;
            if(count>0)std::memcpy(sceneLights_.lights,lights,static_cast<size_t>(count)*64);
            ++sceneLightVersion_;++sceneLightStats_.updates;sceneLightStats_.count=count;
        }
        Signal();return true;
    }
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
    // Publishes visual weather state only; all D3D work happens on the worker.
    // Type 0 or intensity 0 clears the overlay; quality 3 suppresses drawing.
    bool Weather(int type, float intensity, int quality, uint32_t seed) {
        if (type < 0 || type > 5 || quality < 0 || quality > 3
            || !std::isfinite(intensity) || intensity < 0.f || intensity > 1.f) return false;
        { std::lock_guard guard(mutex_);
            if (type!=0 && weatherStyle_.type!=type) return false;
            weather_ = {type,intensity,quality,seed}; ++weatherVersion_; }
        Signal(); return true;
    }
    bool WeatherStyle(int type,int count,const float* params) {
        if (type<1 || type>5 || count<0 || count>WeatherSafetyCap || !params) return false;
        for (int i=0;i<16;i++) if (!std::isfinite(params[i])) return false;
        for (int i=0;i<3;i++) if (params[i]<0.f || params[i]>1.f || params[i+4]<0.f || params[i+4]>1.f) return false;
        if (params[3]<0.25f || params[3]>4.f || params[7]<0.f || params[7]>2.f
            || params[8]<0.1f || params[8]>4.f || params[9]<0.f || params[9]>4.f
            || params[10]<0.25f || params[10]>4.f || params[11]<0.f || params[11]>2.f
            || params[12]<0.5f || params[12]>0.95f || params[13]<0.1f || params[13]>4.f
            || params[14]!=0.f || params[15]!=0.f) return false;
        WeatherStyleState state{};state.type=type;state.count=count;
        std::memcpy(state.params,params,sizeof(state.params));
        { std::lock_guard guard(mutex_);weatherStyle_=state;++weatherVersion_; }
        Signal();return true;
    }
    bool WeatherCamera(float x,float y,float scale,float groundMin,float groundMax) {
        if (!std::isfinite(x) || !std::isfinite(y) || !std::isfinite(scale)
            || !std::isfinite(groundMin) || !std::isfinite(groundMax)
            || scale<=0.f || scale>20.f || std::abs(x)>1000000.f || std::abs(y)>1000000.f
            || std::abs(groundMin)>1000000.f || std::abs(groundMax)>1000000.f || groundMax<=groundMin) return false;
        { std::lock_guard guard(mutex_); weatherCamera_={x,y,scale,groundMin,groundMax}; ++weatherVersion_; }
        Signal(); return true;
    }
    bool Atmosphere(int preset,const float* params) {
        if (preset<0 || preset>11 || !params) return false;
        for (int i=0;i<12;i++) if (!std::isfinite(params[i])) return false;
        for (int i=0;i<6;i++) if (params[i]<0.f || params[i]>1.f) return false;
        if (params[6]<0.f || params[6]>30.f || params[7]<0.f || params[7]>1.f
            || params[8]<params[7] || params[8]>1.f) return false;
        AtmosphereState state{}; state.preset=preset;
        std::memcpy(state.params,params,sizeof(state.params));
        { std::lock_guard guard(mutex_);
            if (preset>0 && preset<11 && atmosphereStyle_.family!=preset) return false;
            atmosphere_=state; ++atmosphereVersion_; }
        Signal(); return true;
    }
    bool AtmosphereStyle(int family,const float* params) {
        if (family<1 || family>10 || !params) return false;
        for (int i=0;i<16;i++) if (!std::isfinite(params[i])) return false;
        for (int i=0;i<3;i++) if (params[i]<0.f || params[i]>1.f || params[i+4]<0.f || params[i+4]>1.f) return false;
        if (params[3]<0.f || params[3]>0.5f || params[7]<0.f || params[7]>0.5f
            || params[8]<0.f || params[8]>0.5f || params[9]<0.f || params[9]>20.f
            || params[10]<0.f || params[10]>16.f || params[11]<0.f || params[11]>16.f
            || params[12]<0.f || params[12]>1.f || params[13]<0.f || params[13]>1.f
            || params[14]<0.05f || params[14]>2.f || params[15]<0.f || params[15]>0.5f) return false;
        AtmosphereStyleState state{};state.family=family;
        std::memcpy(state.params,params,sizeof(state.params));
        { std::lock_guard guard(mutex_);atmosphereStyle_=state;++atmosphereVersion_; }
        Signal();return true;
    }
    // Publishes bullet draw state only; all D3D work happens on the worker.
    // count==0 clears the respective snapshot (null params allowed then).
    bool BulletStyles(const float* styles,int count) {
        if (count<0 || count>BulletStyleCap || (count>0 && !styles)) return false;
        BulletStylesState state{};
        for (int s=0;s<count;s++) {
            const float* p=styles+s*32;
            for (int i=0;i<32;i++) if (!std::isfinite(p[i])) return false;
            for (int i=0;i<6;i++) if (std::abs(p[i])>4096.f) return false;
            for (int i=6;i<12;i++) if (p[i]<0.f || p[i]>1.f) return false;
            if (p[12]<0.f || p[12]>255.f || p[13]<0.f || p[13]>255.f
                || (p[14]!=0.f && p[14]!=1.f) || (p[15]!=0.f && p[15]!=1.f)) return false;
            if(p[15]>0.5f && (std::abs(p[16])>4096 || std::abs(p[17])>4096 || p[18]<=0 || p[19]<=0 || p[18]>4096 || p[19]>4096)) return false;
            for(int j=20;j<24;j++) if(p[j]<0 || p[j]>1)return false;
            if(p[15]>0.5f && (p[20]>=p[22] || p[21]>=p[23]))return false;
            for(int j=24;j<32;j++)if(p[j]!=0)return false;
            std::memcpy(state.params+s*32,p,128);
        }
        state.count=count;
        { std::lock_guard guard(mutex_);bulletStyles_=state;++bulletVersion_; }
        Signal();return true;
    }
    bool BulletFrame(const float* items,int count,float cameraX,float cameraY,float cameraScale) {
        if (count<0 || count>BulletItemCap || (count>0 && !items)) return false;
        if (!std::isfinite(cameraX) || !std::isfinite(cameraY) || !std::isfinite(cameraScale)
            || cameraScale<=0.f || cameraScale>20.f
            || std::abs(cameraX)>1000000.f || std::abs(cameraY)>1000000.f) return false;
        // The caller keeps items valid for this synchronous call: validate it in
        // place so a rejected frame leaves the published snapshot untouched.
        for (int b=0;b<count;b++) {
            const float* p=items+b*8;
            for (int i=0;i<8;i++) if (!std::isfinite(p[i])) return false;
            if (p[0]!=std::floor(p[0]) || p[0]<0.f || p[0]>=static_cast<float>(BulletStyleCap)
                || std::abs(p[1])>1000000.f || std::abs(p[2])>1000000.f || std::abs(p[3])>1000000.f
                || std::abs(p[4])>10000.f || std::abs(p[5])>10000.f
                || p[6]<0.f || p[6]>100.f || p[7]!=0.f) return false;
        }
        { std::lock_guard guard(mutex_);
            for (int b=0;b<count;b++)
                if (static_cast<int>(items[b*8])>=bulletStyles_.count) return false;
            bulletFrame_.cameraX=cameraX; bulletFrame_.cameraY=cameraY; bulletFrame_.cameraScale=cameraScale;
            if (count>0) std::memcpy(bulletFrame_.params,items,static_cast<size_t>(count)*32);
            bulletFrame_.count=count; ++bulletVersion_; }
        Signal();return true;
    }
    bool CombatFxAtlas(const uint8_t* pixels,int width,int height,int length) {
        if(!pixels || width<1 || height<1 || width>4096 || height>4096 || length!=width*height*4) return false;
        auto bytes=std::make_shared<std::vector<uint8_t>>(pixels,pixels+length);
        { std::lock_guard guard(mutex_);fxAtlas_=bytes;fxAtlasW_=width;fxAtlasH_=height;++fxAtlasVersion_;fxReadyVersion_=0; }
        Signal();return true;
    }
    bool BulletAtlas(const uint8_t* pixels,int width,int height,int length) {
        if(!pixels || width<1 || height<1 || width>4096 || height>4096 || length!=width*height*4) return false;
        auto bytes=std::make_shared<std::vector<uint8_t>>(pixels,pixels+length);
        { std::lock_guard guard(mutex_);bulletAtlas_=bytes;bulletAtlasW_=width;bulletAtlasH_=height;++bulletAtlasVersion_;bulletAtlasReady_=0; }
        Signal();return true;
    }
    bool BulletReady() {
        std::lock_guard guard(mutex_);
        for(int i=0;i<bulletStyles_.count;i++)if(bulletStyles_.params[i*32+15]>0.5f)
            return stats_.state==1 && bulletAtlas_ && bulletAtlasReady_.load()==bulletAtlasVersion_;
        return stats_.state==1;
    }
    bool RayFrame(const float* items,int count,float x,float y,float scale) {
        if(count<0 || count>RayItemCap || (count>0 && !items) || !std::isfinite(x) || !std::isfinite(y)
            || !std::isfinite(scale) || std::abs(x)>1000000 || std::abs(y)>1000000 || scale<=0 || scale>20)return false;
        // The caller keeps items valid for this synchronous call: validate it in
        // place so a rejected frame leaves the published snapshot untouched.
        for(int i=0;i<count;i++) {
            const float* p=items+i*32;
            for(int j=0;j<32;j++)if(!std::isfinite(p[j]))return false;
            for(int j=0;j<4;j++)if(std::abs(p[j])>1000000)return false;
            for(int j=4;j<11;j++)if(p[j]<0 || p[j]>1)return false;
            if(p[11]<=0 || p[11]>512 || p[12]<0 || p[12]>1000000000 || p[13]<0 || p[13]>1200
                || p[14]<0 || p[14]>2147483648.f || p[15]!=std::floor(p[15]))return false;
            int style=static_cast<int>(p[15]);if(!((style>=0&&style<12)||(style>=16&&style<28)||style==42))return false;
            for(int j=16;j<32;j++)if(std::abs(p[j])>16777216.f)return false;
        }
        {std::lock_guard guard(mutex_);
            rayFrame_.cameraX=x;rayFrame_.cameraY=y;rayFrame_.cameraScale=scale;
            if(count>0)std::memcpy(rayFrame_.params,items,static_cast<size_t>(count)*128);
            rayFrame_.count=count;++rayVersion_;}Signal();return true;
    }
    bool CombatFxReady() {
        std::lock_guard guard(mutex_);
        return stats_.state==1 && fxAtlas_ && fxReadyVersion_.load()==fxAtlasVersion_;
    }
    bool CombatFxFrame(const float* items,int count,int casings,const float* lights,int lightCount,float maximumResponse,
        float cameraX,float cameraY,float cameraScale) {
        if(count<0 || count>CombatFxCap || casings<0 || casings>count || (count>0 && !items)
            || !std::isfinite(cameraX) || !std::isfinite(cameraY) || !std::isfinite(cameraScale)
            || std::abs(cameraX)>1000000.f || std::abs(cameraY)>1000000.f || cameraScale<=0 || cameraScale>20
            || lightCount<0 || lightCount>PointLightCap || (lightCount>0 && !lights)
            || !std::isfinite(maximumResponse) || maximumResponse<0 || maximumResponse>.8f) return false;
        // The caller keeps items/lights valid for this synchronous call: validate
        // in place so a rejected frame leaves the published snapshot untouched.
        for(int n=0;n<lightCount;n++) {
            const float* p=lights+n*16;
            for(int j=0;j<16;j++) if(!std::isfinite(p[j]))return false;
            if(std::abs(p[0])>1000000 || std::abs(p[1])>1000000 || p[2]<1 || p[2]>1024
                || p[3]<0 || p[3]>2 || p[4]<0 || p[4]>1 || p[5]<0 || p[5]>1 || p[6]<0 || p[6]>1
                || p[7]!=std::floor(p[7]) || p[7]<0 || p[7]>2 || p[11]!=0)return false;
            if(p[7]>0.5f && (p[10]<0.5f || p[10]>512
                || std::abs(p[8]*p[8]+p[9]*p[9]-1)>0.02))return false;
            // ABI 9 near fill: world nearXY bounded like other coordinates,
            // radius 0..320, energy 0..2; radius/energy are both zero or both
            // positive, and only kind 1 may carry a nonzero near field.
            if(std::abs(p[12])>1000000 || std::abs(p[13])>1000000
                || p[14]<0 || p[14]>320 || p[15]<0 || p[15]>2
                || (p[14]==0)!=(p[15]==0))return false;
            if(p[14]==0 && (p[12]!=0 || p[13]!=0))return false;
            if((p[7]<0.5f || p[7]>1.5f)
                && (p[12]!=0 || p[13]!=0 || p[14]!=0 || p[15]!=0))return false;
        }
        for(int n=0;n<count;n++) {
            const float* p=items+n*16;
            for(int i=0;i<16;i++) if(!std::isfinite(p[i])) return false;
            if(std::abs(p[0])>1000000 || std::abs(p[1])>1000000 || std::abs(p[2])>1000000
                || p[3]<0 || p[3]>1 || std::abs(p[4])>10 || std::abs(p[5])>10
                || p[6]<0 || p[6]>1 || (p[7]!=0 && p[7]!=1)
                || std::abs(p[8])>10000 || std::abs(p[9])>10000 || p[10]<=0 || p[11]<=0 || p[10]>10000 || p[11]>10000
                || p[12]<0 || p[13]<0 || p[14]>1 || p[15]>1 || p[14]<=p[12] || p[15]<=p[13]) return false;
        }
        { std::lock_guard guard(mutex_);
            fxFrame_.cameraX=cameraX;fxFrame_.cameraY=cameraY;fxFrame_.cameraScale=cameraScale;
            if(lightCount>0)std::memcpy(fxFrame_.lights,lights,static_cast<size_t>(lightCount)*64);
            if(count>0)std::memcpy(fxFrame_.params,items,static_cast<size_t>(count)*64);
            fxFrame_.count=count;fxFrame_.casings=casings;fxFrame_.lightCount=lightCount;
            fxFrame_.maximumLightResponse=maximumResponse;++fxVersion_; }
        Signal();return true;
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
        State(0,S_OK,L"Creating capture device");
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

        State(0,S_OK,L"Creating shaders from embedded bytecode");
        auto vsCode = CompositorShaders::VS; auto psCode = CompositorShaders::PS;
        auto weatherVsCode = CompositorShaders::WVS;
        auto weatherPsCode = CompositorShaders::WPS;
        auto bulletVsCode = CompositorShaders::BVS;
        auto bulletPsCode = CompositorShaders::BPS;
        com_ptr<ID3D11VertexShader> vs; com_ptr<ID3D11PixelShader> ps;
        check_hresult(device->CreateVertexShader(vsCode.data, vsCode.size, nullptr, vs.put()));
        check_hresult(device->CreatePixelShader(psCode.data, psCode.size, nullptr, ps.put()));
        com_ptr<ID3D11Buffer> constants;
        D3D11_BUFFER_DESC cb{}; cb.ByteWidth = sizeof(Settings); cb.Usage = D3D11_USAGE_DEFAULT; cb.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
        check_hresult(device->CreateBuffer(&cb, nullptr, constants.put()));
        com_ptr<ID3D11Buffer> samplingConstants;
        cb.ByteWidth=16; check_hresult(device->CreateBuffer(&cb,nullptr,samplingConstants.put()));
        com_ptr<ID3D11Buffer> atmosphereConstants;
        cb.ByteWidth=64; check_hresult(device->CreateBuffer(&cb,nullptr,atmosphereConstants.put()));
        com_ptr<ID3D11Buffer> atmosphereStyleConstants;
        cb.ByteWidth=64; check_hresult(device->CreateBuffer(&cb,nullptr,atmosphereStyleConstants.put()));
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
        com_ptr<ID3D11VertexShader> weatherVs; com_ptr<ID3D11PixelShader> weatherPs;
        check_hresult(device->CreateVertexShader(weatherVsCode.data, weatherVsCode.size, nullptr, weatherVs.put()));
        check_hresult(device->CreatePixelShader(weatherPsCode.data, weatherPsCode.size, nullptr, weatherPs.put()));
        com_ptr<ID3D11Buffer> weatherParams;
        cb.ByteWidth = 64; check_hresult(device->CreateBuffer(&cb, nullptr, weatherParams.put()));
        com_ptr<ID3D11Buffer> weatherStyleParams;
        cb.ByteWidth = 64; check_hresult(device->CreateBuffer(&cb, nullptr, weatherStyleParams.put()));
        com_ptr<ID3D11VertexShader> bulletVs; com_ptr<ID3D11PixelShader> bulletPs;
        check_hresult(device->CreateVertexShader(bulletVsCode.data, bulletVsCode.size, nullptr, bulletVs.put()));
        check_hresult(device->CreatePixelShader(bulletPsCode.data, bulletPsCode.size, nullptr, bulletPs.put()));
        com_ptr<ID3D11Buffer> bulletParams;
        cb.ByteWidth = 32; check_hresult(device->CreateBuffer(&cb, nullptr, bulletParams.put()));
        com_ptr<ID3D11Buffer> bulletStyleParams;
        cb.ByteWidth = BulletStyleCap*128; check_hresult(device->CreateBuffer(&cb, nullptr, bulletStyleParams.put()));
        com_ptr<ID3D11Buffer> bulletItemParams;
        cb.ByteWidth = BulletBatchCap*32; check_hresult(device->CreateBuffer(&cb, nullptr, bulletItemParams.put()));
        auto fxVsCode=CompositorShaders::FVS,fxPsCode=CompositorShaders::FPS;
        com_ptr<ID3D11VertexShader> fxVs;com_ptr<ID3D11PixelShader> fxPs;
        check_hresult(device->CreateVertexShader(fxVsCode.data,fxVsCode.size,nullptr,fxVs.put()));
        check_hresult(device->CreatePixelShader(fxPsCode.data,fxPsCode.size,nullptr,fxPs.put()));
        com_ptr<ID3D11Buffer> fxParams,fxItems;
        cb.ByteWidth=32;check_hresult(device->CreateBuffer(&cb,nullptr,fxParams.put()));
        cb.ByteWidth=CombatFxCap*64;check_hresult(device->CreateBuffer(&cb,nullptr,fxItems.put()));
        D3D11_SAMPLER_DESC fxSamplerDesc{};fxSamplerDesc.Filter=D3D11_FILTER_MIN_MAG_MIP_LINEAR;
        fxSamplerDesc.AddressU=fxSamplerDesc.AddressV=fxSamplerDesc.AddressW=D3D11_TEXTURE_ADDRESS_CLAMP;
        fxSamplerDesc.MaxLOD=D3D11_FLOAT32_MAX;
        com_ptr<ID3D11SamplerState> fxSampler;check_hresult(device->CreateSamplerState(&fxSamplerDesc,fxSampler.put()));
        com_ptr<ID3D11BlendState> alphaBlend;
        D3D11_BLEND_DESC bd{};
        bd.RenderTarget[0].BlendEnable = TRUE;
        bd.RenderTarget[0].SrcBlend = D3D11_BLEND_SRC_ALPHA;
        bd.RenderTarget[0].DestBlend = D3D11_BLEND_INV_SRC_ALPHA;
        bd.RenderTarget[0].BlendOp = D3D11_BLEND_OP_ADD;
        bd.RenderTarget[0].SrcBlendAlpha = D3D11_BLEND_ONE;
        bd.RenderTarget[0].DestBlendAlpha = D3D11_BLEND_INV_SRC_ALPHA;
        bd.RenderTarget[0].BlendOpAlpha = D3D11_BLEND_OP_ADD;
        bd.RenderTarget[0].RenderTargetWriteMask = D3D11_COLOR_WRITE_ENABLE_ALL;
        check_hresult(device->CreateBlendState(&bd, alphaBlend.put()));
        com_ptr<ID3D11BlendState> fxBlend;bd.RenderTarget[0].SrcBlend=D3D11_BLEND_ONE;
        check_hresult(device->CreateBlendState(&bd,fxBlend.put()));
        com_ptr<ID3D11Texture2D> fxTexture;com_ptr<ID3D11ShaderResourceView> fxSrv;
        com_ptr<ID3D11Texture2D> bulletTexture;com_ptr<ID3D11ShaderResourceView> bulletSrv;
        auto rayVsCode=CompositorShaders::RVS,rayPsCode=CompositorShaders::RPS;
        com_ptr<ID3D11VertexShader> rayVs;com_ptr<ID3D11PixelShader> rayPs;
        check_hresult(device->CreateVertexShader(rayVsCode.data,rayVsCode.size,nullptr,rayVs.put()));
        check_hresult(device->CreatePixelShader(rayPsCode.data,rayPsCode.size,nullptr,rayPs.put()));
        com_ptr<ID3D11Buffer> rayParams,rayItems;
        cb.ByteWidth=32;check_hresult(device->CreateBuffer(&cb,nullptr,rayParams.put()));
        cb.ByteWidth=RayBatchCap*128;check_hresult(device->CreateBuffer(&cb,nullptr,rayItems.put()));
        com_ptr<ID3D11BlendState> rayScreenBlend;
        bd.RenderTarget[0].DestBlend=D3D11_BLEND_INV_SRC_COLOR;
        check_hresult(device->CreateBlendState(&bd,rayScreenBlend.put()));
        auto lightVsCode=CompositorShaders::LVS,lightPsCode=CompositorShaders::LPS;
        com_ptr<ID3D11VertexShader> lightVs;com_ptr<ID3D11PixelShader> lightPs;
        check_hresult(device->CreateVertexShader(lightVsCode.data,lightVsCode.size,nullptr,lightVs.put()));
        check_hresult(device->CreatePixelShader(lightPsCode.data,lightPsCode.size,nullptr,lightPs.put()));
        com_ptr<ID3D11Buffer> lightParams,lightItems;
        cb.ByteWidth=64;check_hresult(device->CreateBuffer(&cb,nullptr,lightParams.put()));
        cb.ByteWidth=PointLightCap*64;check_hresult(device->CreateBuffer(&cb,nullptr,lightItems.put()));
        com_ptr<ID3D11BlendState> lightBlend;
        bd.RenderTarget[0].DestBlend=bd.RenderTarget[0].DestBlendAlpha=D3D11_BLEND_ONE;
        check_hresult(device->CreateBlendState(&bd,lightBlend.put()));
        SceneLightGpu sceneGpu(device.get(),context.get(),lightItems.get(),lightParams.get(),lightVs.get(),lightPs.get(),lightBlend.get(),raster.get());
        SceneLightState sceneSnapshot;
        constexpr int LightFieldW=256,LightFieldH=144;
        D3D11_TEXTURE2D_DESC lightDesc{};lightDesc.Width=LightFieldW;lightDesc.Height=LightFieldH;
        lightDesc.MipLevels=1;lightDesc.ArraySize=1;lightDesc.Format=DXGI_FORMAT_R16G16B16A16_FLOAT;
        lightDesc.SampleDesc.Count=1;lightDesc.Usage=D3D11_USAGE_DEFAULT;
        lightDesc.BindFlags=D3D11_BIND_RENDER_TARGET|D3D11_BIND_SHADER_RESOURCE;
        com_ptr<ID3D11Texture2D> lightTexture;
        com_ptr<ID3D11RenderTargetView> lightTarget;com_ptr<ID3D11ShaderResourceView> lightResource;
        check_hresult(device->CreateTexture2D(&lightDesc,nullptr,lightTexture.put()));
        check_hresult(device->CreateRenderTargetView(lightTexture.get(),nullptr,lightTarget.put()));
        check_hresult(device->CreateShaderResourceView(lightTexture.get(),nullptr,lightResource.put()));

        com_ptr<ID3D11Texture2D> texture;
        com_ptr<ID3D11ShaderResourceView> srv;
        com_ptr<ID3D11RenderTargetView> rtv;
        int textureW = 0, textureH = 0, outputW = 0, outputH = 0;
        int appliedMode = -1;
        float appliedSharpness=-1;
        double frameQpcMs = 0;
        State(0,S_OK,L"Starting WGC capture");
        startSession();
        uint64_t appliedSettings = 0;
        // lut-set-v1 工作线程状态：纹理惰性创建，版本驱动的 UpdateSubresource（变更才上传）。
        com_ptr<ID3D11Texture3D> lutTexture;
        com_ptr<ID3D11ShaderResourceView> lutSrv;
        uint64_t appliedLut = 0, lutCopiedVersion = 0;
        bool lutActive = false;
        auto lutWork = std::make_unique<uint8_t[]>(LutBytes);
        uint64_t appliedWeather = 0;
        uint64_t appliedAtmosphere = 0;
        uint64_t appliedBullet = 0;
        uint64_t appliedBulletAtlas=0;
        // The ~512KB frame snapshots would overflow the worker's 1MB default
        // stack together; heap-allocate once and keep the draw code unchanged.
        BulletStylesState bulletStyles;
        auto bulletFrameStore=std::make_unique<BulletFrameState>();auto& bulletFrame=*bulletFrameStore;
        CombatFxState fxFrame;uint64_t appliedFx=0,appliedFxAtlas=0;
        auto rayFrameStore=std::make_unique<RayFrameState>();auto& rayFrame=*rayFrameStore;uint64_t appliedRay=0;
        // Per-frame pass buckets; capacity is reserved once and reused.
        std::vector<int> rayFlame,rayScreen,rayOther;
        rayFlame.reserve(RayItemCap);rayScreen.reserve(RayItemCap);rayOther.reserve(RayItemCap);
        float weatherTime = 0;
        double lastWeatherDrawMs = 0;
        float atmosphereTime = 0;
        double lastAtmosphereDrawMs = 0;
        auto nextPresent = std::chrono::steady_clock::now();
        double previousTimingPresent=0;
        HudRasterGpu hudGpu;
        uint64_t appliedHudVersion=0;
        bool lightCacheValid=false,fxItemsDirty=true;
        int cachedLightCount=0;
        uint64_t cachedLightGeneration=0;
        float cachedLightParams[16]{},cachedLights[PointLightCap*16]{};
        State(1, S_OK, L"GPU display path; optional diagnostic readback");
        while (!stop_) {
            if (!active_) {
                previousTimingPresent=0;
                lightCacheValid=false;
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
            uint64_t observedWake=wakeVersion_.load();
            uint64_t settingsVersion; bool custom; Settings settings; WeatherState weather; WeatherCameraState weatherCamera; uint64_t weatherVersion;
            uint64_t lutVersion; bool lutEnabled;
            AtmosphereState atmosphere; AtmosphereStyleState atmosphereStyle; uint64_t atmosphereVersion;
            WeatherStyleState weatherStyle; uint64_t bulletVersion,bulletAtlasObserved,fxVersion,fxAtlasVersion,rayVersion;
            { std::lock_guard guard(mutex_); settingsVersion=settingsVersion_; custom=custom_; settings=customSettings_;
                weather=weather_; weatherCamera=weatherCamera_; weatherVersion=weatherVersion_;
                weatherStyle=weatherStyle_; atmosphere=atmosphere_;
                atmosphereStyle=atmosphereStyle_; atmosphereVersion=atmosphereVersion_;
                bulletVersion=bulletVersion_;bulletAtlasObserved=bulletAtlasVersion_;
                fxVersion=fxVersion_;fxAtlasVersion=fxAtlasVersion_;rayVersion=rayVersion_; }
            bool weatherOn = weather.type!=0 && weather.intensity>0.f && weather.quality<3
                && weatherStyle.type==weather.type && weatherStyle.count>0 && texture;
            bool atmosphereOn = atmosphere.preset!=0 && (atmosphere.preset==11
                || atmosphereStyle.family==atmosphere.preset) && texture;
            bool bulletsOn = bulletFrame.count>0 && bulletStyles.count>0 && texture;
            bool fxOn=(fxFrame.count>0 || fxFrame.lightCount>0) && fxSrv && texture;
            uint64_t observedSceneLightVersion;{std::lock_guard guard(mutex_);observedSceneLightVersion=sceneLightVersion_;}
            // Weather animates per presented frame; keep a 30fps floor even on
            // unpaced probe sessions so motion stays at the worker cadence.
            uint64_t observedHudVersion;bool hudVisible;
            {std::lock_guard guard(mutex_);observedHudVersion=hudVersion_;
                hudVisible=std::any_of(hudFrames_.begin(),hudFrames_.end(),[](const auto& frame){return static_cast<bool>(frame.pixels);});}
            int paceFps = fps_>0 ? fps_ : ((weatherOn || atmosphereOn || bulletsOn || fxOn || rayFrame.count>0) ? 30 : 0);
            // Preserve independent HUD animation responsiveness; static HUD does not force redraw.
            if(hudVisible && observedHudVersion!=appliedHudVersion)paceFps=60;
            if (paceFps>0) {
                std::unique_lock lock(waitMutex_);
                wake_.wait_until(lock,nextPresent,[this] { return stop_.load() || !active_.load() || grabRequested_.load(); });
                if (stop_) break;
                if (!active_) continue;
            }
            if (grabRequested_.load() && (!grabComposite_.load() || !texture)) {
                ServiceGrab(device.get(),context.get(),texture.get(),textureW,textureH);continue;
            }
            { std::lock_guard guard(mutex_);
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
                previousTimingPresent=0;
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
            if (!frame && (!texture || (appliedMode == mode_.load() && !proofRequested_ && !grabRequested_
                    && outputW == client.right && outputH == client.bottom && appliedSettings==settingsVersion
                    && appliedSharpness==sharpness_.load() && appliedLut==lutVersion
                    && appliedWeather==weatherVersion && !weatherOn
                    && appliedAtmosphere==atmosphereVersion && !atmosphereOn
                    && appliedBullet==bulletVersion && appliedBulletAtlas==bulletAtlasObserved
                    && !bulletsOn && appliedRay==rayVersion && rayFrame.count==0
                    && appliedFx==fxVersion && appliedFxAtlas==fxAtlasVersion && !fxOn
                    && sceneGpu.version==observedSceneLightVersion && appliedHudVersion==observedHudVersion))) {
                previousTimingPresent=0;
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
            // The pacing wait and WGC dequeue may span an AS2 F packet. Sample
            // its camera and the newest bullet snapshot immediately before
            // drawing; the loop-head copy could be one presented frame behind.
            std::shared_ptr<std::vector<uint8_t>> atlasPixels;int atlasW=0,atlasH=0;
            std::shared_ptr<std::vector<uint8_t>> bulletPixels;int bulletW=0,bulletH=0;uint64_t bulletAtlasVersion=0;
            uint64_t lightCaptureGeneration=0;
            { std::lock_guard guard(mutex_);
                lightCaptureGeneration=captureGeneration_;
                weatherCamera=weatherCamera_; weatherVersion=weatherVersion_;
                // Snapshot copies move metadata + count live records only. Draws
                // index params[0..count) and uploads zero-pad the last cbuffer
                // batch, so stale tail bytes need no clearing.
                if (bulletVersion_!=appliedBullet) {
                    bulletStyles=bulletStyles_;
                    bulletFrame.cameraX=bulletFrame_.cameraX;bulletFrame.cameraY=bulletFrame_.cameraY;
                    bulletFrame.cameraScale=bulletFrame_.cameraScale;bulletFrame.count=bulletFrame_.count;
                    if(bulletFrame.count>0)std::memcpy(bulletFrame.params,bulletFrame_.params,static_cast<size_t>(bulletFrame.count)*32);
                    appliedBullet=bulletVersion_; }
                if(fxVersion_!=appliedFx) {
                    if(fxFrame.count!=fxFrame_.count || (fxFrame_.count>0
                        && std::memcmp(fxFrame.params,fxFrame_.params,static_cast<size_t>(fxFrame_.count)*64)!=0))
                        fxItemsDirty=true;
                    fxFrame.cameraX=fxFrame_.cameraX;fxFrame.cameraY=fxFrame_.cameraY;fxFrame.cameraScale=fxFrame_.cameraScale;
                    fxFrame.count=fxFrame_.count;fxFrame.casings=fxFrame_.casings;fxFrame.lightCount=fxFrame_.lightCount;
                    fxFrame.maximumLightResponse=fxFrame_.maximumLightResponse;
                    if(fxFrame.lightCount>0)std::memcpy(fxFrame.lights,fxFrame_.lights,static_cast<size_t>(fxFrame.lightCount)*64);
                    if(fxFrame.count>0)std::memcpy(fxFrame.params,fxFrame_.params,static_cast<size_t>(fxFrame.count)*64);
                    appliedFx=fxVersion_; }
                if(rayVersion_!=appliedRay) {
                    rayFrame.cameraX=rayFrame_.cameraX;rayFrame.cameraY=rayFrame_.cameraY;
                    rayFrame.cameraScale=rayFrame_.cameraScale;rayFrame.count=rayFrame_.count;
                    if(rayFrame.count>0)std::memcpy(rayFrame.params,rayFrame_.params,static_cast<size_t>(rayFrame.count)*128);
                    appliedRay=rayVersion_; }
                fxAtlasVersion=fxAtlasVersion_;
                if(fxAtlasVersion!=appliedFxAtlas) { atlasPixels=fxAtlas_;atlasW=fxAtlasW_;atlasH=fxAtlasH_; }
                bulletAtlasVersion=bulletAtlasVersion_;
                if(bulletAtlasVersion!=appliedBulletAtlas) { bulletPixels=bulletAtlas_;bulletW=bulletAtlasW_;bulletH=bulletAtlasH_; }
            }
            if(atlasPixels) {
                D3D11_TEXTURE2D_DESC desc{};desc.Width=atlasW;desc.Height=atlasH;desc.MipLevels=1;desc.ArraySize=1;
                desc.Format=DXGI_FORMAT_B8G8R8A8_UNORM;desc.SampleDesc.Count=1;desc.Usage=D3D11_USAGE_IMMUTABLE;
                desc.BindFlags=D3D11_BIND_SHADER_RESOURCE;
                D3D11_SUBRESOURCE_DATA pixels{atlasPixels->data(),static_cast<UINT>(atlasW*4),0};
                fxSrv=nullptr;fxTexture=nullptr;
                check_hresult(device->CreateTexture2D(&desc,&pixels,fxTexture.put()));
                check_hresult(device->CreateShaderResourceView(fxTexture.get(),nullptr,fxSrv.put()));
                appliedFxAtlas=fxAtlasVersion;fxReadyVersion_=appliedFxAtlas;
            }
            if(bulletPixels) {
                D3D11_TEXTURE2D_DESC desc{};desc.Width=bulletW;desc.Height=bulletH;desc.MipLevels=1;desc.ArraySize=1;
                desc.Format=DXGI_FORMAT_B8G8R8A8_UNORM;desc.SampleDesc.Count=1;desc.Usage=D3D11_USAGE_IMMUTABLE;
                desc.BindFlags=D3D11_BIND_SHADER_RESOURCE;
                D3D11_SUBRESOURCE_DATA pixels{bulletPixels->data(),static_cast<UINT>(bulletW*4),0};
                bulletSrv=nullptr;bulletTexture=nullptr;
                check_hresult(device->CreateTexture2D(&desc,&pixels,bulletTexture.put()));
                check_hresult(device->CreateShaderResourceView(bulletTexture.get(),nullptr,bulletSrv.put()));
                appliedBulletAtlas=bulletAtlasVersion;bulletAtlasReady_=appliedBulletAtlas;
            }
            float scale = std::min(static_cast<float>(w)/textureW, static_cast<float>(h)/textureH);
            D3D11_VIEWPORT viewport{(w-textureW*scale)/2, (h-textureH*scale)/2, textureW*scale, textureH*scale, 0, 1};
            bool proof = proofRequested_.exchange(false);
            bool lightsOn=!proof && fxFrame.lightCount>0 && fxFrame.maximumLightResponse>0;
            uint64_t sceneVersion;
            {std::lock_guard guard(mutex_);sceneVersion=sceneLightVersion_;if(sceneVersion!=sceneGpu.version)sceneSnapshot=sceneLights_;}
            bool sceneRebuilt=sceneGpu.Prepare(sceneSnapshot,sceneVersion),sceneOn=sceneGpu.Bind(!proof);
            {std::lock_guard guard(mutex_);sceneLightStats_.builds+=sceneRebuilt?1:0;sceneLightStats_.cacheHits+=sceneOn && !sceneRebuilt?1:0;
                sceneLightStats_.width=sceneGpu.width;sceneLightStats_.height=sceneGpu.height;}
            bool lightDrawn=false,lightCacheHit=false;
            uint64_t fxUploads=0;
            float palette[3]{1,1,1};
            // Production uses LUT only for ambient "光照". Direct gunfire must not
            // inherit its blue darkness; night vision uses the separate matrix path.
            if((lightsOn || sceneOn) && !lutActive) {
                Settings grade=custom?settings:ColorMode(mode);
                const float* rows[]{grade.r,grade.g,grade.b};
                for(int c=0;c<3;c++)palette[c]=std::pow(std::clamp(rows[c][0]+rows[c][1]+rows[c][2]+rows[c][3]+grade.offset[c],0.f,1.f),1.f/std::max(grade.offset[3],.001f));
                float peak=std::max(.001f,std::max(palette[0],std::max(palette[1],palette[2])));
                for(float& value:palette)value/=peak;
            }
            float lp[16]{viewport.TopLeftX,viewport.TopLeftY,viewport.Width,viewport.Height,
                fxFrame.cameraX,fxFrame.cameraY,fxFrame.cameraScale,0,
                lightsOn || sceneOn?1.f:0.f,std::max(fxFrame.maximumLightResponse,sceneOn?sceneGpu.response:0.f),lightsOn?1.f:0.f,0,palette[0],palette[1],palette[2],0};
            context->UpdateSubresource(lightParams.get(),0,nullptr,lp,0,0);
            auto lightBuffer=lightParams.get();context->VSSetConstantBuffers(4,1,&lightBuffer);context->PSSetConstantBuffers(4,1,&lightBuffer);
            ID3D11ShaderResourceView* noLight=nullptr;context->PSSetShaderResources(3,1,&noLight);
            context->RSSetState(raster.get());
            context->IASetInputLayout(nullptr); context->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
            bool rebuildLight=lightsOn && (!lightCacheValid || cachedLightCount!=fxFrame.lightCount
                || cachedLightGeneration!=lightCaptureGeneration
                || std::memcmp(cachedLightParams,lp,sizeof(lp))!=0
                || std::memcmp(cachedLights,fxFrame.lights,static_cast<size_t>(fxFrame.lightCount)*64)!=0);
            if(rebuildLight) {
                auto target=lightTarget.get();context->OMSetRenderTargets(1,&target,nullptr);
                const float transparent[]{0,0,0,0};context->ClearRenderTargetView(target,transparent);
                D3D11_VIEWPORT lv{0,0,static_cast<float>(LightFieldW),static_cast<float>(LightFieldH),0,1};
                context->RSSetViewports(1,&lv);
                context->UpdateSubresource(lightItems.get(),0,nullptr,fxFrame.lights,0,0);
                auto items=lightItems.get();context->VSSetConstantBuffers(5,1,&items);
                context->VSSetShader(lightVs.get(),nullptr,0);context->PSSetShader(lightPs.get(),nullptr,0);
                context->OMSetBlendState(lightBlend.get(),nullptr,0xffffffff);
                context->Draw(fxFrame.lightCount*6,0);context->OMSetBlendState(nullptr,nullptr,0xffffffff);
                std::memcpy(cachedLightParams,lp,sizeof(lp));
                std::memcpy(cachedLights,fxFrame.lights,static_cast<size_t>(fxFrame.lightCount)*64);
                cachedLightCount=fxFrame.lightCount;cachedLightGeneration=lightCaptureGeneration;
                lightCacheValid=true;lightDrawn=true;
            }
            else if(lightsOn) lightCacheHit=true;
            else lightCacheValid=false;
            auto target=rtv.get();context->OMSetRenderTargets(1,&target,nullptr);
            const float black[]{0,0,0,1};context->ClearRenderTargetView(target,black);
            context->RSSetViewports(1,&viewport);
            auto field=lightsOn?lightResource.get():nullptr;auto fieldSampler=fxSampler.get();
            context->PSSetShaderResources(3,1,&field);context->PSSetSamplers(3,1,&fieldSampler);
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
            if (atmosphereOn && !proof) {
                double nowAtmosphereMs=QpcMs();
                float delta=lastAtmosphereDrawMs>0
                    ? std::clamp(static_cast<float>((nowAtmosphereMs-lastAtmosphereDrawMs)/1000.0),0.f,0.10f)
                    : 1.f/30.f;
                lastAtmosphereDrawMs=nowAtmosphereMs;
                atmosphereTime+=delta;
                if (atmosphereTime>8192.f) atmosphereTime-=8192.f;
            } else if (!atmosphereOn) lastAtmosphereDrawMs=0;
            float ap[16]{
                atmosphere.params[0],atmosphere.params[1],atmosphere.params[2],atmosphere.params[3],
                proof ? 0.f : static_cast<float>(atmosphere.preset),atmosphereTime,
                atmosphere.params[4],atmosphere.params[5],
                atmosphere.params[6],atmosphere.params[7],atmosphere.params[8],weatherCamera.scale,
                weatherCamera.x,weatherCamera.y,0,0
            };
            context->UpdateSubresource(atmosphereConstants.get(),0,nullptr,ap,0,0);
            auto atmosphereBuffer=atmosphereConstants.get(); context->PSSetConstantBuffers(2,1,&atmosphereBuffer);
            context->UpdateSubresource(atmosphereStyleConstants.get(),0,nullptr,atmosphereStyle.params,0,0);
            auto lookBuffer=atmosphereStyleConstants.get(); context->PSSetConstantBuffers(3,1,&lookBuffer);
            context->Draw(3,0);
            ID3D11ShaderResourceView* empty = nullptr; context->PSSetShaderResources(0,1,&empty);
            // Weather overlays the graded world inside the same content viewport,
            // blended after the source pass (not pre-grade composited). The base
            // grade cbuffer and LUT resource stay bound for the weather grade.
            if (weatherOn && !proof) {
                double nowWeatherMs = QpcMs();
                float weatherDelta = lastWeatherDrawMs > 0
                    ? std::clamp(static_cast<float>((nowWeatherMs-lastWeatherDrawMs)/1000.0),0.f,0.10f)
                    : 1.f/30.f;
                lastWeatherDrawMs = nowWeatherMs;
                weatherTime += weatherDelta;
                if (weatherTime > 8192.f) weatherTime -= 8192.f;
                int rainCount=weatherStyle.count;
                if (weather.quality==1) rainCount=rainCount*5/8;
                else if (weather.quality==2) rainCount=rainCount*3/8;
                float wp[16]{weatherTime,weather.intensity,static_cast<float>(weather.type),
                    static_cast<float>(weather.seed & 0xFFFFFFu),viewport.Width,viewport.Height,static_cast<float>(rainCount),lutActive?1.f:0.f,
                    weatherCamera.x,weatherCamera.y,weatherCamera.scale,weatherCamera.groundMin,
                    weatherCamera.groundMax,576.f,0,0};
                context->UpdateSubresource(weatherParams.get(),0,nullptr,wp,0,0);
                context->UpdateSubresource(weatherStyleParams.get(),0,nullptr,weatherStyle.params,0,0);
                context->VSSetShader(weatherVs.get(),nullptr,0); context->PSSetShader(weatherPs.get(),nullptr,0);
                auto weatherBuffer = weatherParams.get();
                context->VSSetConstantBuffers(1,1,&weatherBuffer); context->PSSetConstantBuffers(1,1,&weatherBuffer);
                auto weatherLookBuffer=weatherStyleParams.get();
                context->VSSetConstantBuffers(2,1,&weatherLookBuffer);context->PSSetConstantBuffers(2,1,&weatherLookBuffer);
                context->OMSetBlendState(alphaBlend.get(),nullptr,0xffffffff);
                int splashCount=weather.type==1 ? std::max(8,rainCount/2) : 0;
                context->Draw((rainCount+splashCount)*6,0);
                context->OMSetBlendState(nullptr,nullptr,0xffffffff);
            } else if (!weatherOn) lastWeatherDrawMs = 0;
            auto drawFx=[&](int first,int count) {
                if(count<=0 || !fxSrv || proof) return;
                float fp[8]{fxFrame.cameraX,fxFrame.cameraY,fxFrame.cameraScale,lutActive?1.f:0.f,static_cast<float>(first),0,0,0};
                context->UpdateSubresource(fxParams.get(),0,nullptr,fp,0,0);
                if(fxItemsDirty) {
                    context->UpdateSubresource(fxItems.get(),0,nullptr,fxFrame.params,0,0);
                    fxItemsDirty=false;++fxUploads;
                }
                context->VSSetShader(fxVs.get(),nullptr,0);context->PSSetShader(fxPs.get(),nullptr,0);
                auto params=fxParams.get(),items=fxItems.get();auto sampler=fxSampler.get();auto resource=fxSrv.get();
                context->VSSetConstantBuffers(1,1,&params);context->PSSetConstantBuffers(1,1,&params);
                context->VSSetConstantBuffers(2,1,&items);context->PSSetShaderResources(2,1,&resource);
                context->PSSetSamplers(2,1,&sampler);context->OMSetBlendState(fxBlend.get(),nullptr,0xffffffff);
                context->Draw(count*6,0);context->OMSetBlendState(nullptr,nullptr,0xffffffff);
            };
            drawFx(0,fxFrame.casings);
            // Bullets stay above casings and below short muzzle flashes,
            // alpha blended over world+weather+atmosphere. The base grade
            // cbuffer and LUT resource stay bound for the bullet grade.
            if (bulletFrame.count>0 && bulletStyles.count>0 && texture && !proof) {
                float bp[8]{viewport.Width,viewport.Height,lutActive?1.f:0.f,static_cast<float>(bulletFrame.count),
                    bulletFrame.cameraX,bulletFrame.cameraY,bulletFrame.cameraScale,static_cast<float>(bulletStyles.count)};
                context->UpdateSubresource(bulletStyleParams.get(),0,nullptr,bulletStyles.params,0,0);
                context->VSSetShader(bulletVs.get(),nullptr,0); context->PSSetShader(bulletPs.get(),nullptr,0);
                auto bulletBuffer=bulletParams.get();
                context->VSSetConstantBuffers(1,1,&bulletBuffer); context->PSSetConstantBuffers(1,1,&bulletBuffer);
                auto bulletStyleBuffer=bulletStyleParams.get(); auto bulletItemBuffer=bulletItemParams.get();
                context->VSSetConstantBuffers(2,1,&bulletStyleBuffer); context->PSSetConstantBuffers(2,1,&bulletStyleBuffer);
                context->VSSetConstantBuffers(3,1,&bulletItemBuffer);
                context->OMSetBlendState(alphaBlend.get(),nullptr,0xffffffff);
                auto bulletResource=bulletSrv.get();auto bulletSampler=fxSampler.get();
                context->PSSetShaderResources(2,1,&bulletResource);context->PSSetSamplers(2,1,&bulletSampler);
                // The fixed cbuffer upload reads a full batch. The staging buffer is
                // filled per batch and only the tail of a partial batch is zero padded.
                float batch[BulletBatchCap*8];
                for(int offset=0;offset<bulletFrame.count;offset+=BulletBatchCap) {
                    int count=std::min(BulletBatchCap,bulletFrame.count-offset);bp[3]=static_cast<float>(count);
                    context->UpdateSubresource(bulletParams.get(),0,nullptr,bp,0,0);
                    std::memcpy(batch,bulletFrame.params+offset*8,static_cast<size_t>(count)*32);
                    if(count<BulletBatchCap)std::memset(batch+count*8,0,static_cast<size_t>(BulletBatchCap-count)*32);
                    context->UpdateSubresource(bulletItemParams.get(),0,nullptr,batch,0,0);
                    context->Draw(count*6,0);
                }
                context->OMSetBlendState(nullptr,nullptr,0xffffffff);
            }
            if(rayFrame.count>0 && texture && !proof) {
                context->VSSetShader(rayVs.get(),nullptr,0);context->PSSetShader(rayPs.get(),nullptr,0);
                auto rp=rayParams.get(),ri=rayItems.get();
                context->VSSetConstantBuffers(1,1,&rp);context->PSSetConstantBuffers(1,1,&rp);
                context->VSSetConstantBuffers(2,1,&ri);context->PSSetConstantBuffers(2,1,&ri);
                // Bucket source indices by the same style test RVS applies per
                // pass (RayPassBuckets.h). Each pass uploads only the batches it
                // actually draws; records keep their original order inside every
                // pass and an empty pass emits no upload or draw.
                rayFlame.clear();rayScreen.clear();rayOther.clear();
                for(int i=0;i<rayFrame.count;i++) {
                    int bucket=RayStyleBucket(static_cast<int>(rayFrame.params[i*32+15]));
                    if(bucket==RayBucketFlame) rayFlame.push_back(i);
                    else if(bucket==RayBucketScreen) rayScreen.push_back(i);
                    else rayOther.push_back(i);
                }
                auto drawRayPass=[&](int pass,const std::vector<int>& bucket,ID3D11BlendState* blend) {
                    if(bucket.empty()) return;
                    context->OMSetBlendState(blend,nullptr,0xffffffff);
                    // The fixed cbuffer upload always reads a full batch; the tail stays zeroed.
                    float batch[RayBatchCap*32];
                    for(size_t at=0;at<bucket.size();at+=RayBatchCap) {
                        int count=static_cast<int>(std::min(bucket.size()-at,static_cast<size_t>(RayBatchCap)));
                        float params[8]{viewport.Width,viewport.Height,lutActive?1.f:0.f,static_cast<float>(count),
                            rayFrame.cameraX,rayFrame.cameraY,rayFrame.cameraScale,static_cast<float>(pass)};
                        for(int k=0;k<count;k++) std::memcpy(batch+k*32,rayFrame.params+bucket[at+k]*32,128);
                        if(count<RayBatchCap)std::memset(batch+count*32,0,static_cast<size_t>(RayBatchCap-count)*128);
                        context->UpdateSubresource(rayParams.get(),0,nullptr,params,0,0);
                        context->UpdateSubresource(rayItems.get(),0,nullptr,batch,0,0);context->Draw(count*6,0);
                    }
                };
                // Pass/blend pairing is unchanged: 0 additive, 1 additive, 2 screen, 3 additive.
                drawRayPass(0,rayFlame,fxBlend.get());
                drawRayPass(1,rayOther,lightBlend.get());
                drawRayPass(2,rayScreen,rayScreenBlend.get());
                drawRayPass(3,rayFlame,lightBlend.get());
                context->OMSetBlendState(nullptr,nullptr,0xffffffff);
            }
            drawFx(fxFrame.casings,fxFrame.count-fxFrame.casings);
            ID3D11ShaderResourceView* emptyFx=nullptr;context->PSSetShaderResources(2,1,&emptyFx);
            appliedWeather = weatherVersion;
            appliedAtmosphere = atmosphereVersion;
            context->PSSetShaderResources(1,1,&empty);
            std::array<HudRasterFrame,HudRasterLayerCount> hudFrames;
            {std::lock_guard guard(mutex_);hudFrames=hudFrames_;appliedHudVersion=hudVersion_;}
            ProbeHudRasterStats hudDraw{sizeof(ProbeHudRasterStats)};
            if(!proof)hudGpu.Draw(device.get(),context.get(),hudFrames,w,h,hudDraw);
            {std::lock_guard guard(mutex_);hudStats_.visibleLayers=hudDraw.visibleLayers;
                hudStats_.uploads+=hudDraw.uploads;hudStats_.uploadedBytes+=hudDraw.uploadedBytes;hudStats_.draws+=hudDraw.draws;}
            double submit = QpcMs();
            if (proof) {
                VerifyPixels(device.get(), context.get(), swap.get(), texture.get(), viewport, textureW, textureH, mode,
                    lutActive ? lutWork.get() : nullptr);
                if (contentRequested_.exchange(false))
                    VerifyContent(device.get(), context.get(), swap.get(), texture.get(), viewport, textureW, textureH, mode);
            }
            // Explicit diagnostic only: read the fully composed backbuffer before Present.
            // Normal production frames never incur this GPU-to-CPU copy.
            if(grabRequested_.load() && grabComposite_.load()) {
                com_ptr<ID3D11Texture2D> composed;
                check_hresult(swap->GetBuffer(0,__uuidof(ID3D11Texture2D),composed.put_void()));
                ServiceGrab(device.get(),context.get(),composed.get(),w,h);
            }
            double presentStart = QpcMs();
            HRESULT present = swap->Present(1, 0);
            check_hresult(present);
            double end = QpcMs();
            if (paceFps>0) nextPresent=std::max(nextPresent+std::chrono::microseconds(1000000/paceFps),std::chrono::steady_clock::now());
            {
                std::lock_guard guard(mutex_);
                stats_.received += fresh ? 1 + drained : 0; stats_.superseded += drained;
                if (present == S_OK) {
                    ++stats_.presented; presentedOutputW_=w; presentedOutputH_=h;
                    timingSamples_[timingNext_]={previousTimingPresent>0 ? end-previousTimingPresent : -1,
                        submit-start,end-presentStart,fresh ? std::max(0.,start-frameQpcMs) : -1,end};
                    timingNext_=(timingNext_+1)%timingSamples_.size();
                    timingCount_=std::min(timingCount_+1,timingSamples_.size());
                    previousTimingPresent=end;
                } else previousTimingPresent=0;
                stats_.width = textureW; stats_.height = textureH;
                if (fresh) {
                    stats_.ageMs = start - frameQpcMs;
                    stats_.maxAgeMs = std::max(stats_.maxAgeMs, stats_.ageMs);
                }
                stats_.submitMs = submit - start; stats_.presentMs = end - presentStart;
                stats_.lastFrameQpcMs = frameQpcMs;
                ++workStats_.compositions;
                workStats_.lightDraws+=lightDrawn?1:0;
                workStats_.lightCacheHits+=lightCacheHit?1:0;
                workStats_.fxUploads+=fxUploads;
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
            ID3D11Texture2D* input, D3D11_VIEWPORT vp, int width, int height, int mode, const uint8_t* lut) {
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
                float result = 0;
                if (lut) {
                    float fx=c[0]*31.f, fy=c[1]*31.f, fz=c[2]*31.f;
                    int x0=static_cast<int>(fx), y0=static_cast<int>(fy), z0=static_cast<int>(fz);
                    int x1=std::min(x0+1,31), y1=std::min(y0+1,31), z1=std::min(z0+1,31);
                    float wx=fx-x0, wy=fy-y0, wz=fz-z0;
                    for (int bz=0;bz<2;bz++) for (int gy=0;gy<2;gy++) for (int rx=0;rx<2;rx++) {
                        int r=rx?x1:x0, g=gy?y1:y0, b=bz?z1:z0;
                        float weight=(rx?wx:1-wx)*(gy?wy:1-wy)*(bz?wz:1-wz);
                        result += weight * (lut[((b*32+g)*32+r)*4+channel]/255.f);
                    }
                } else {
                    result = settings.offset[channel];
                    for (int j = 0; j < 4; ++j) result += c[j]*rows[channel][j];
                }
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
    // copies the requested source capture or composed output (BGRA8) into the caller buffer.
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
    ProbeWorkStats workStats_{sizeof(ProbeWorkStats)};
    std::array<HudRasterFrame,HudRasterLayerCount> hudFrames_;
    uint64_t hudVersion_=0;
    ProbeHudRasterStats hudStats_{sizeof(ProbeHudRasterStats)};
    struct TimingSample { double interval,submit,present,age,at; };
    std::array<TimingSample,256> timingSamples_{};
    size_t timingNext_=0,timingCount_=0;
    SceneLightState sceneLights_{};uint64_t sceneLightVersion_=0;
    ProbeSceneLightStats sceneLightStats_{sizeof(ProbeSceneLightStats)};
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
    std::atomic<bool> grabRequested_{false},grabComposite_{false};
    bool grabPending_=false;
    uint8_t* grabBuffer_=nullptr; uint32_t grabBufferSize_=0;
    uint32_t grabWidth_=0, grabHeight_=0; int grabResult_=0;
    Settings customSettings_{}; bool custom_=false; uint64_t settingsVersion_=0;
    // lut-set-v1：宿主线程 SetLut/ClearLut 经 mutex_ 入库，工作线程按 lutVersion_
    // 惰性建/更 Texture3D（变更才上传，不逐帧）；ClearLut 只关断分支，GPU 纹理保留复用。
    static constexpr uint32_t LutSize = 32;
    static constexpr size_t LutBytes = static_cast<size_t>(LutSize)*LutSize*LutSize*4;
    uint8_t lutData_[LutBytes]{};
    bool lutEnabled_=false; uint64_t lutVersion_=0;
    WeatherState weather_{}; WeatherCameraState weatherCamera_{}; uint64_t weatherVersion_=0;
    AtmosphereState atmosphere_{}; uint64_t atmosphereVersion_=0;
    WeatherStyleState weatherStyle_{}; AtmosphereStyleState atmosphereStyle_{};
    BulletStylesState bulletStyles_{}; BulletFrameState bulletFrame_{}; uint64_t bulletVersion_=0;
    std::shared_ptr<std::vector<uint8_t>> bulletAtlas_;int bulletAtlasW_=0,bulletAtlasH_=0;
    uint64_t bulletAtlasVersion_=0;std::atomic<uint64_t> bulletAtlasReady_{0};
    RayFrameState rayFrame_{};uint64_t rayVersion_=0;
    CombatFxState fxFrame_{};uint64_t fxVersion_=0,fxAtlasVersion_=0;
    int fxAtlasW_=0,fxAtlasH_=0;std::shared_ptr<std::vector<uint8_t>> fxAtlas_;
    std::atomic<uint64_t> fxReadyVersion_{0};
};
}

uint32_t __cdecl ProbeGetAbiVersion() { return 12; }
int __cdecl ProbeGetOutputSize(void* handle, int32_t* width, int32_t* height) {
    return handle && width && height && static_cast<Capture*>(handle)->OutputSize(*width,*height) ? 1 : 0;
}
void* __cdecl ProbeStartVisual(HWND source, DWORD sourcePid, HWND output, IUnknown* visual) {
    if (!visual) return nullptr;
    try { return new Capture(source, sourcePid, output, 0, 30, false, visual); } catch (...) { return nullptr; }
}
void* __cdecl ProbeStartWorldVisual(HWND source, DWORD sourcePid, HWND output, uint32_t vendor, int borderless, IUnknown* visual) {
    if (!visual) return nullptr;
    try { return new Capture(source, sourcePid, output, vendor, 30, borderless != 0, visual); } catch (...) { return nullptr; }
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
int __cdecl ProbeGrabCompositeFrame(void* handle, uint8_t* buffer, uint32_t bufferSize, uint32_t* outWidth, uint32_t* outHeight) {
    return handle ? static_cast<Capture*>(handle)->GrabLatestFrame(buffer,bufferSize,outWidth,outHeight,true) : 0;
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
int __cdecl ProbeGetWorkStats(void* handle, ProbeWorkStats* stats) {
    if(!handle || !stats || stats->size!=sizeof(ProbeWorkStats)) return 0;
    static_cast<Capture*>(handle)->WorkStats(*stats);return 1;
}
int __cdecl ProbeGetTimingStats(void* handle, ProbeTimingStats* stats) {
    if(!handle || !stats || stats->size!=sizeof(ProbeTimingStats))return 0;
    static_cast<Capture*>(handle)->TimingStats(*stats);return 1;
}
int __cdecl ProbeSetHudRaster(void* handle,int layer,const void* pixels,int width,int height,int stride,int x,int y) {
    if(!handle)return 0;
    try {return static_cast<Capture*>(handle)->HudRaster(layer,pixels,width,height,stride,x,y)?1:0;}
    catch (...) {return 0;}
}
int __cdecl ProbeGetHudRasterStats(void* handle,ProbeHudRasterStats* stats) {
    if(!handle || !stats || stats->size!=sizeof(ProbeHudRasterStats))return 0;
    static_cast<Capture*>(handle)->HudRasterStats(*stats);return 1;
}
int __cdecl ProbeSetSceneLights(void* handle,const float* lights,int count,float response) {
    return handle && static_cast<Capture*>(handle)->SceneLights(lights,count,response)?1:0;
}
int __cdecl ProbeGetSceneLightStats(void* handle,ProbeSceneLightStats* stats) {
    if(!handle || !stats || stats->size!=sizeof(ProbeSceneLightStats))return 0;
    static_cast<Capture*>(handle)->SceneLightStats(*stats);return 1;
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
int __cdecl ProbeSetWeather(void* handle, int type, float intensity, int quality, uint32_t seed) {
    return handle && static_cast<Capture*>(handle)->Weather(type,intensity,quality,seed) ? 1 : 0;
}
int __cdecl ProbeSetWeatherCamera(void* handle,float x,float y,float scale,float groundMin,float groundMax) {
    return handle && static_cast<Capture*>(handle)->WeatherCamera(x,y,scale,groundMin,groundMax) ? 1 : 0;
}
int __cdecl ProbeSetAtmosphere(void* handle,int preset,const float* params) {
    return handle && static_cast<Capture*>(handle)->Atmosphere(preset,params) ? 1 : 0;
}
int __cdecl ProbeSetAtmosphereStyle(void* handle,int family,const float* params) {
    return handle && static_cast<Capture*>(handle)->AtmosphereStyle(family,params) ? 1 : 0;
}
int __cdecl ProbeSetWeatherStyle(void* handle,int type,int count,const float* params) {
    return handle && static_cast<Capture*>(handle)->WeatherStyle(type,count,params) ? 1 : 0;
}
int __cdecl ProbeSetBulletStyles(void* handle,const float* styles,int count) {
    return handle && static_cast<Capture*>(handle)->BulletStyles(styles,count) ? 1 : 0;
}
int __cdecl ProbeSetBulletAtlas(void* handle,const uint8_t* pixels,int width,int height,int length) {
    try { return handle && static_cast<Capture*>(handle)->BulletAtlas(pixels,width,height,length) ? 1 : 0; }
    catch(...) { return 0; }
}
int __cdecl ProbeBulletReady(void* handle) { return handle && static_cast<Capture*>(handle)->BulletReady() ? 1 : 0; }
int __cdecl ProbeSetRayFrame(void* handle,const float* items,int count,float x,float y,float scale) {
    return handle && static_cast<Capture*>(handle)->RayFrame(items,count,x,y,scale) ? 1 : 0;
}
int __cdecl ProbeSetBulletFrame(void* handle,const float* items,int count,float cameraX,float cameraY,float cameraScale) {
    return handle && static_cast<Capture*>(handle)->BulletFrame(items,count,cameraX,cameraY,cameraScale) ? 1 : 0;
}
int __cdecl ProbeSetCombatFxAtlas(void* handle,const uint8_t* pixels,int width,int height,int length) {
    try { return handle && static_cast<Capture*>(handle)->CombatFxAtlas(pixels,width,height,length) ? 1 : 0; }
    catch(...) { return 0; }
}
int __cdecl ProbeCombatFxReady(void* handle) { return handle && static_cast<Capture*>(handle)->CombatFxReady() ? 1 : 0; }
int __cdecl ProbeSetCombatFxFrame(void* handle,const float* items,int count,int casings,const float* lights,int lightCount,float maximumResponse,float cameraX,float cameraY,float cameraScale) {
    return handle && static_cast<Capture*>(handle)->CombatFxFrame(items,count,casings,lights,lightCount,maximumResponse,cameraX,cameraY,cameraScale) ? 1 : 0;
}
