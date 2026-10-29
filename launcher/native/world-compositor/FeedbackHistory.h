#pragma once

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
    uint64_t epoch_=0;
    double sourceMs_=0;
    D3D11_VIEWPORT viewport_{};
public:
    bool Pending() const { return valid_; }
    void Reset(ProbePostprocessStats& stats,bool release=false) {
        if(valid_)++stats.historyResets;
        valid_=false;stats.historyValid=0;stats.historyWeight=0;
        if(release) {
            for(auto& p:pixels_)p=nullptr;
            for(auto& s:sources_)s=nullptr;
            width_=height_=0;stats.historyBytes=0;
        }
    }
    void Apply(ID3D11Device* device,ID3D11DeviceContext* context,ID3D11Texture2D* back,
            ID3D11RenderTargetView* target,const D3D11_VIEWPORT& viewport,bool enabled,
            bool fresh,double sourceMs,double now,uint64_t epoch,ProbePostprocessStats& stats) {
        stats.feedbackEnabled=enabled?1u:0u;
        if(!enabled) {Reset(stats,true);return;}
        D3D11_TEXTURE2D_DESC desc{};back->GetDesc(&desc);
        if(desc.Width!=width_ || desc.Height!=height_) {
            Reset(stats,true);width_=desc.Width;height_=desc.Height;
            desc.BindFlags=D3D11_BIND_SHADER_RESOURCE;desc.MiscFlags=0;
            for(int i=0;i<2;++i) {
                winrt::check_hresult(device->CreateTexture2D(&desc,nullptr,pixels_[i].put()));
                winrt::check_hresult(device->CreateShaderResourceView(pixels_[i].get(),nullptr,sources_[i].put()));
            }
            stats.historyBytes=static_cast<uint64_t>(width_)*height_*8;
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
        if(!ps_) {
            auto v=CompositorShaders::PVS,p=CompositorShaders::PPS;
            winrt::check_hresult(device->CreateVertexShader(v.data,v.size,nullptr,vs_.put()));
            winrt::check_hresult(device->CreatePixelShader(p.data,p.size,nullptr,ps_.put()));
            D3D11_BUFFER_DESC cb{};cb.ByteWidth=16;cb.Usage=D3D11_USAGE_DEFAULT;cb.BindFlags=D3D11_BIND_CONSTANT_BUFFER;
            winrt::check_hresult(device->CreateBuffer(&cb,nullptr,mix_.put()));
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
