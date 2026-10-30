#pragma once

// Identity gates only projectiles. Source metadata is removed while sampling
// the world, before any native effects or HUD; no final-screen rewrite exists.
class FrameSyncParameters {
    winrt::com_ptr<ID3D11Buffer> params_;
public:
    void Prepare(ID3D11Device* device) {
        if(params_)return;
        D3D11_BUFFER_DESC desc{};desc.ByteWidth=48;desc.BindFlags=D3D11_BIND_CONSTANT_BUFFER;
        desc.Usage=D3D11_USAGE_DEFAULT;
        winrt::check_hresult(device->CreateBuffer(&desc,nullptr,params_.put()));
    }
    void UpdateParams(ID3D11DeviceContext* context,const int* identity,int sourceWidth,int sourceHeight,
            const D3D11_VIEWPORT& viewport,bool enabled,bool hideSourceTag) {
        float values[12]{
            static_cast<float>(identity[0]),static_cast<float>(identity[1]),static_cast<float>(identity[2]),static_cast<float>(identity[3]),
            static_cast<float>(sourceWidth),static_cast<float>(sourceHeight),viewport.Width,viewport.Height,
            viewport.TopLeftX,viewport.TopLeftY,enabled?1.f:0.f,hideSourceTag?1.f:0.f};
        context->UpdateSubresource(params_.get(),0,nullptr,values,0,0);
        auto buffer=params_.get();
        // b7 belongs to night vision. b8 is shared by source sampling and bullets.
        context->VSSetConstantBuffers(8,1,&buffer);context->PSSetConstantBuffers(8,1,&buffer);
    }
};

struct FrameTagCandidate {
    int ordinaryEpoch,ordinaryFrame,chainEpoch,chainFrame;
    uint32_t items;
};

class FrameTagSampler {
    winrt::com_ptr<ID3D11Texture2D> targetTexture_,staging_;
    winrt::com_ptr<ID3D11RenderTargetView> target_;
    winrt::com_ptr<ID3D11PixelShader> pixel_;
    winrt::com_ptr<ID3D11Buffer> constants_;
    winrt::com_ptr<ID3D11Query> query_;
    std::vector<FrameTagCandidate> history_;
    ProbeBulletSourceStats metadata_{sizeof(ProbeBulletSourceStats)};
    bool pending_=false;
    uint64_t samples_=0;
    void Prepare(ID3D11Device* device) {
        if(pixel_)return;
        target_=nullptr;targetTexture_=nullptr;staging_=nullptr;constants_=nullptr;query_=nullptr;
        D3D11_TEXTURE2D_DESC td{};td.Width=td.Height=td.MipLevels=td.ArraySize=td.SampleDesc.Count=1;
        td.Format=DXGI_FORMAT_R32G32B32A32_UINT;td.Usage=D3D11_USAGE_DEFAULT;td.BindFlags=D3D11_BIND_RENDER_TARGET;
        winrt::check_hresult(device->CreateTexture2D(&td,nullptr,targetTexture_.put()));
        winrt::check_hresult(device->CreateRenderTargetView(targetTexture_.get(),nullptr,target_.put()));
        td.Usage=D3D11_USAGE_STAGING;td.BindFlags=0;td.CPUAccessFlags=D3D11_CPU_ACCESS_READ;
        winrt::check_hresult(device->CreateTexture2D(&td,nullptr,staging_.put()));
        D3D11_QUERY_DESC q{};q.Query=D3D11_QUERY_EVENT;
        winrt::check_hresult(device->CreateQuery(&q,query_.put()));
        D3D11_BUFFER_DESC cb{};cb.ByteWidth=16;cb.Usage=D3D11_USAGE_DEFAULT;cb.BindFlags=D3D11_BIND_CONSTANT_BUFFER;
        winrt::check_hresult(device->CreateBuffer(&cb,nullptr,constants_.put()));
        auto shader=CompositorShaders::TagPS;
        winrt::check_hresult(device->CreatePixelShader(shader.data,shader.size,nullptr,pixel_.put()));
    }
public:
    bool Pending() const{return pending_;}
    void Begin(ID3D11Device* device,ID3D11DeviceContext* context,ID3D11VertexShader* vertex,ID3D11RasterizerState* raster,
            ID3D11ShaderResourceView* source,int width,int height,double captureMs,
            std::vector<FrameTagCandidate> history) {
        Prepare(device);history_=std::move(history);
        metadata_=ProbeBulletSourceStats{sizeof(ProbeBulletSourceStats)};
        metadata_.historyCount=static_cast<uint32_t>(history_.size());
        metadata_.sourceWidth=width;metadata_.sourceHeight=height;metadata_.captureQpcMs=captureMs;
        metadata_.matchedOrdinaryEpoch=metadata_.matchedOrdinaryFrame=metadata_.matchedChainEpoch=metadata_.matchedChainFrame=-1;
        float size[]{static_cast<float>(width),static_cast<float>(height),0,0};
        context->UpdateSubresource(constants_.get(),0,nullptr,size,0,0);
        auto target=target_.get();auto buffer=constants_.get();
        context->OMSetRenderTargets(1,&target,nullptr);D3D11_VIEWPORT view{0,0,1,1,0,1};context->RSSetViewports(1,&view);
        context->RSSetState(raster);context->IASetInputLayout(nullptr);context->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
        context->VSSetShader(vertex,nullptr,0);context->PSSetShader(pixel_.get(),nullptr,0);
        context->PSSetConstantBuffers(0,1,&buffer);context->PSSetShaderResources(0,1,&source);
        context->OMSetBlendState(nullptr,nullptr,0xffffffff);context->Draw(3,0);
        ID3D11ShaderResourceView* empty=nullptr;context->PSSetShaderResources(0,1,&empty);
        context->OMSetRenderTargets(0,nullptr,nullptr);context->CopyResource(staging_.get(),targetTexture_.get());
        context->End(query_.get());pending_=true;
    }
    bool Poll(ID3D11DeviceContext* context,double now,ProbeBulletSourceStats& result) {
        if(!pending_)return false;
        BOOL complete=FALSE;
        HRESULT ready=context->GetData(query_.get(),&complete,sizeof(complete),D3D11_ASYNC_GETDATA_DONOTFLUSH);
        if(ready==S_FALSE || (ready==S_OK && !complete))return false;
        winrt::check_hresult(ready);
        D3D11_MAPPED_SUBRESOURCE mapped{};
        HRESULT hr=context->Map(staging_.get(),0,D3D11_MAP_READ,D3D11_MAP_FLAG_DO_NOT_WAIT,&mapped);
        if(hr==DXGI_ERROR_WAS_STILL_DRAWING)return false;
        winrt::check_hresult(hr);
        uint32_t values[4]{};std::memcpy(values,mapped.pData,sizeof(values));context->Unmap(staging_.get(),0);
        pending_=false;result=metadata_;result.sampleNumber=++samples_;result.sampleQpcMs=now;
        result.sourceEpoch=static_cast<int32_t>(values[0]);result.sourceFrame=static_cast<int32_t>(values[1]);result.tagValid=values[2];
        result.status=values[2]==0?2u:history_.empty()?3u:7u;
        int minimum=0x1000000,maximum=-1;
        if(values[2])for(const auto& candidate:history_) {
            if((static_cast<uint32_t>(candidate.ordinaryEpoch)&0xFFFFu)!=values[0])continue;
            int frame=candidate.ordinaryFrame&0xFFFFFF;minimum=std::min(minimum,frame);maximum=std::max(maximum,frame);
            result.status=4;
            if(static_cast<uint32_t>(frame)==values[1] && candidate.chainFrame==candidate.ordinaryFrame) {
                result.status=1;result.matchedOrdinaryEpoch=candidate.ordinaryEpoch;result.matchedOrdinaryFrame=candidate.ordinaryFrame;
                result.matchedChainEpoch=candidate.chainEpoch;result.matchedChainFrame=candidate.chainFrame;result.matchedItems=candidate.items;break;
            }
        }
        // A wrapping 24-bit interval is left as a generic mismatch rather than
        // misreporting expiry/ahead at the wrap boundary.
        if(result.status==4 && maximum-minimum<0x800000) {
            if(result.sourceFrame<minimum)result.status=5;
            else if(result.sourceFrame>maximum)result.status=6;
        }
        return true;
    }
    void Abandon(){pending_=false;}
};
