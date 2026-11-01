#pragma once
#include "CasSourceStage.h"

// Worker-thread GPU history. Copy/blur happens before native FX and opaque HUD.
// No CPU readback, new gameplay frames, or motion estimation is introduced.
class FeedbackHistory {
    winrt::com_ptr<ID3D11Texture2D> pixels_[2];
    winrt::com_ptr<ID3D11ShaderResourceView> sources_[2];
    winrt::com_ptr<ID3D11VertexShader> vs_;
    winrt::com_ptr<ID3D11PixelShader> ps_;
    winrt::com_ptr<ID3D11Buffer> mix_;
    bool valid_=false;
    int index_=0;
    UINT width_=0,height_=0;
    StageAllocationGuard allocGuard_;
    uint64_t epoch_=0;
    double sourceMs_=0;
    D3D11_VIEWPORT viewport_{};
public:
    bool Pending() const { return valid_; }
    void InjectAllocationFaultForTests(int count=1,HRESULT hr=E_OUTOFMEMORY) noexcept {
        allocGuard_.InjectFault(count,hr);
    }
    void Reset(ProbePostprocessStats& stats,bool release=false,bool clearFailureLatch=true) noexcept {
        if(valid_)++stats.historyResets;
        valid_=false;stats.historyValid=0;stats.historyWeight=0;
        if(release) {
            for(auto& p:pixels_)p=nullptr;
            for(auto& s:sources_)s=nullptr;
            width_=height_=0;stats.historyBytes=0;
            if(clearFailureLatch)allocGuard_.ClearLatch();
        }
    }
    void Apply(ID3D11Device* device,ID3D11DeviceContext* context,ID3D11Texture2D* back,
            ID3D11RenderTargetView* target,const D3D11_VIEWPORT& viewport,bool enabled,
            bool fresh,double sourceMs,double now,uint64_t epoch,ProbePostprocessStats& stats) {
        stats.feedbackEnabled=enabled?1u:0u;
        if(!enabled) {Reset(stats,true,true);return;}
        D3D11_TEXTURE2D_DESC desc{};back->GetDesc(&desc);
        const int w=static_cast<int>(desc.Width),h=static_cast<int>(desc.Height);
        if(allocGuard_.IsLatched(w,h)) {
            stats.historyValid=0;stats.historyWeight=0;stats.historyBytes=0;
            return;
        }
        if(desc.Width!=width_ || desc.Height!=height_ || !vs_ || !ps_ || !mix_ || allocGuard_.HasPendingFault()) {
            if(!allocGuard_.TryAllocate(device,w,h,[&] {
                winrt::com_ptr<ID3D11VertexShader> newVs=vs_;
                winrt::com_ptr<ID3D11PixelShader> newPs=ps_;
                winrt::com_ptr<ID3D11Buffer> newMix=mix_;
                if(!newVs || !newPs || !newMix) {
                    auto v=CompositorShaders::PVS,p=CompositorShaders::PPS;
                    winrt::check_hresult(device->CreateVertexShader(v.data,v.size,nullptr,newVs.put()));
                    winrt::check_hresult(device->CreatePixelShader(p.data,p.size,nullptr,newPs.put()));
                    D3D11_BUFFER_DESC cb{};cb.ByteWidth=16;cb.Usage=D3D11_USAGE_DEFAULT;cb.BindFlags=D3D11_BIND_CONSTANT_BUFFER;
                    winrt::check_hresult(device->CreateBuffer(&cb,nullptr,newMix.put()));
                }
                if(desc.Width!=width_ || desc.Height!=height_) {
                    D3D11_TEXTURE2D_DESC texDesc=desc;
                    texDesc.BindFlags=D3D11_BIND_SHADER_RESOURCE;texDesc.MiscFlags=0;
                    winrt::com_ptr<ID3D11Texture2D> newPixels[2];
                    winrt::com_ptr<ID3D11ShaderResourceView> newSources[2];
                    for(int i=0;i<2;++i) {
                        winrt::check_hresult(device->CreateTexture2D(&texDesc,nullptr,newPixels[i].put()));
                        winrt::check_hresult(device->CreateShaderResourceView(newPixels[i].get(),nullptr,newSources[i].put()));
                    }
                    Reset(stats,true,true);
                    for(int i=0;i<2;++i) {
                        pixels_[i]=std::move(newPixels[i]);
                        sources_[i]=std::move(newSources[i]);
                    }
                    width_=desc.Width;height_=desc.Height;
                    stats.historyBytes=static_cast<uint64_t>(width_)*height_*8;
                }
                vs_=std::move(newVs);
                ps_=std::move(newPs);
                mix_=std::move(newMix);
            },[&] {
                Reset(stats,true,false);
                context->OMSetRenderTargets(1,&target,nullptr);
                context->RSSetViewports(1,&viewport);
            })) return;
        }
        if(epoch!=epoch_ || std::memcmp(&viewport_,&viewport,sizeof(viewport))!=0
                || (valid_ && (sourceMs-sourceMs_>120 || sourceMs<sourceMs_))) Reset(stats);
        epoch_=epoch;viewport_=viewport;
        // A stalled/held source converges to its current pixels and then stops
        // composing. Repeated Present calls never become new history samples.
        if(!fresh && valid_ && now-sourceMs_>120) {Reset(stats);return;}
        context->OMSetRenderTargets(0,nullptr,nullptr);
        if(!valid_) {
            if(fresh) {
                context->CopyResource(pixels_[index_].get(),back);
                valid_=true;sourceMs_=sourceMs;++stats.historyUpdates;
            }
            context->OMSetRenderTargets(1,&target,nullptr);
            stats.historyValid=valid_?1u:0u;return;
        }
        int next=1-index_;
        context->CopyResource(pixels_[next].get(),back);
        double elapsed=std::max(0.,(fresh?sourceMs:now)-sourceMs_);
        // 18 ms half-life, capped at 35% historical contribution on a new frame.
        // Duplicate presentations only decay the last accepted history sample.
        float weight=static_cast<float>(std::exp(-std::log(2.)*elapsed/18.));
        if(fresh)weight=std::min(.35f,weight);
        float values[]{weight,0,0,0};context->UpdateSubresource(mix_.get(),0,nullptr,values,0,0);
        auto cb=mix_.get();context->PSSetConstantBuffers(0,1,&cb);
        ID3D11ShaderResourceView* input[]{sources_[next].get(),sources_[index_].get()};
        context->PSSetShaderResources(0,2,input);
        context->OMSetRenderTargets(1,&target,nullptr);context->RSSetViewports(1,&viewport);
        context->VSSetShader(vs_.get(),nullptr,0);context->PSSetShader(ps_.get(),nullptr,0);
        context->OMSetBlendState(nullptr,nullptr,0xffffffff);context->Draw(3,0);
        ID3D11ShaderResourceView* empty[]{nullptr,nullptr};context->PSSetShaderResources(0,2,empty);
        if(fresh) {
            context->OMSetRenderTargets(0,nullptr,nullptr);
            context->CopyResource(pixels_[next].get(),back);
            context->OMSetRenderTargets(1,&target,nullptr);
            index_=next;sourceMs_=sourceMs;++stats.historyUpdates;
        }
        stats.historyValid=1;stats.historyWeight=weight;++stats.passes;
    }
};
