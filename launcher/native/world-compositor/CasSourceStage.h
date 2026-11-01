#pragma once
struct StageAllocationGuard {
    int failedWidth=0,failedHeight=0;
    int faultRemaining=0;
    HRESULT faultHr=E_OUTOFMEMORY;
    void InjectFault(int count=1,HRESULT hr=E_OUTOFMEMORY) noexcept {
        faultRemaining=count;
        faultHr=hr;
        failedWidth=failedHeight=0;
    }
    void ClearLatch() noexcept { failedWidth=failedHeight=0; }
    bool HasPendingFault() const noexcept { return faultRemaining>0; }
    bool IsLatched(int width,int height) const noexcept {
        return width>0 && height>0 && width==failedWidth && height==failedHeight;
    }
    void CheckInjectedFault() {
        if(faultRemaining>0) {
            --faultRemaining;
            winrt::check_hresult(faultHr);
        }
    }
    template<typename AllocFn,typename FallbackFn>
    bool TryAllocate(ID3D11Device* device,int width,int height,AllocFn&& alloc,FallbackFn&& onFallback) {
        auto degrade=[&]() -> bool {
            if(device && device->GetDeviceRemovedReason()!=S_OK)throw;
            onFallback();
            failedWidth=width;failedHeight=height;
            return false;
        };
        try {
            CheckInjectedFault();
            alloc();
            return true;
        } catch(std::bad_alloc const&) {
            return degrade();
        } catch(winrt::hresult_error const&) {
            return degrade();
        }
    }
};

// L-quality CAS on captured source pixels, cached across duplicate presentations.
// Original capture stays intact for proof/readback and the true bypass path.
class CasSourceStage {
    winrt::com_ptr<ID3D11Texture2D> texture_;
    winrt::com_ptr<ID3D11RenderTargetView> target_;
    winrt::com_ptr<ID3D11ShaderResourceView> source_;
    winrt::com_ptr<ID3D11PixelShader> ps_;
    winrt::com_ptr<ID3D11Buffer> constants_;
    int width_=0,height_=0;
    StageAllocationGuard allocGuard_;
    bool valid_=false;
    float strength_=-1;
public:
    void InjectAllocationFaultForTests(int count=1,HRESULT hr=E_OUTOFMEMORY) noexcept {
        allocGuard_.InjectFault(count,hr);
    }
    void Reset(ProbeCasStageStats& stats,bool clearFailureLatch=true) noexcept {
        source_=nullptr;target_=nullptr;texture_=nullptr;
        width_=height_=0;valid_=false;
        if(clearFailureLatch)allocGuard_.ClearLatch();
        stats.appliedStage=0;stats.textureBytes=0;
    }
    ID3D11ShaderResourceView* Apply(ID3D11Device* device,ID3D11DeviceContext* context,
            ID3D11VertexShader* vs,ID3D11ShaderResourceView* original,int width,int height,
            bool enabled,bool fresh,float strength,ProbeCasStageStats& stats) {
        if(!enabled) {Reset(stats,true);return original;}
        if(allocGuard_.IsLatched(width,height)) {
            stats.appliedStage=0;stats.textureBytes=0;
            return original;
        }
        if(width!=width_ || height!=height_ || !ps_ || !constants_ || allocGuard_.HasPendingFault()) {
            if(!allocGuard_.TryAllocate(device,width,height,[&] {
                winrt::com_ptr<ID3D11PixelShader> newPs=ps_;
                winrt::com_ptr<ID3D11Buffer> newConstants=constants_;
                if(!newPs || !newConstants) {
                    auto p=CompositorShaders::SPS;
                    winrt::check_hresult(device->CreatePixelShader(p.data,p.size,nullptr,newPs.put()));
                    D3D11_BUFFER_DESC cbDesc{};cbDesc.ByteWidth=16;cbDesc.Usage=D3D11_USAGE_DEFAULT;
                    cbDesc.BindFlags=D3D11_BIND_CONSTANT_BUFFER;
                    winrt::check_hresult(device->CreateBuffer(&cbDesc,nullptr,newConstants.put()));
                }
                if(width!=width_ || height!=height_) {
                    D3D11_TEXTURE2D_DESC desc{};desc.Width=width;desc.Height=height;
                    desc.MipLevels=1;desc.ArraySize=1;desc.SampleDesc.Count=1;
                    desc.Format=DXGI_FORMAT_B8G8R8A8_UNORM;desc.Usage=D3D11_USAGE_DEFAULT;
                    desc.BindFlags=D3D11_BIND_RENDER_TARGET|D3D11_BIND_SHADER_RESOURCE;
                    winrt::com_ptr<ID3D11Texture2D> newTexture;
                    winrt::com_ptr<ID3D11RenderTargetView> newTarget;
                    winrt::com_ptr<ID3D11ShaderResourceView> newSource;
                    winrt::check_hresult(device->CreateTexture2D(&desc,nullptr,newTexture.put()));
                    winrt::check_hresult(device->CreateRenderTargetView(newTexture.get(),nullptr,newTarget.put()));
                    winrt::check_hresult(device->CreateShaderResourceView(newTexture.get(),nullptr,newSource.put()));
                    Reset(stats,true);
                    texture_=std::move(newTexture);
                    target_=std::move(newTarget);
                    source_=std::move(newSource);
                    width_=width;height_=height;
                    stats.textureBytes=static_cast<uint64_t>(width)*height*4;
                }
                ps_=std::move(newPs);
                constants_=std::move(newConstants);
            },[&] {
                Reset(stats,false);
            })) return original;
        }
        if(fresh || !valid_ || strength!=strength_) {
            ID3D11ShaderResourceView* empty=nullptr;context->PSSetShaderResources(0,1,&empty);
            auto target=target_.get();context->OMSetRenderTargets(1,&target,nullptr);
            D3D11_VIEWPORT viewport{0,0,static_cast<float>(width),static_cast<float>(height),0,1};
            context->RSSetViewports(1,&viewport);
            float values[]{static_cast<float>(width),static_cast<float>(height),-1.f/(8.f-3.f*strength),0};
            context->UpdateSubresource(constants_.get(),0,nullptr,values,0,0);
            auto buffer=constants_.get();context->PSSetConstantBuffers(0,1,&buffer);
            context->PSSetShaderResources(0,1,&original);
            context->VSSetShader(vs,nullptr,0);context->PSSetShader(ps_.get(),nullptr,0);
            context->OMSetBlendState(nullptr,nullptr,0xffffffff);context->Draw(3,0);
            context->PSSetShaderResources(0,1,&empty);context->OMSetRenderTargets(0,nullptr,nullptr);
            valid_=true;strength_=strength;++stats.draws;
        } else ++stats.cacheHits;
        stats.appliedStage=1;
        return source_.get();
    }
};
