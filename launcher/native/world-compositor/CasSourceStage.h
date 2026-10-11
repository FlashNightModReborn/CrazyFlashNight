#pragma once

// L-quality CAS on captured source pixels, cached across duplicate presentations.
// Original capture stays intact for proof/readback and the true bypass path.
class CasSourceStage {
    winrt::com_ptr<ID3D11Texture2D> texture_;
    winrt::com_ptr<ID3D11RenderTargetView> target_;
    winrt::com_ptr<ID3D11ShaderResourceView> source_;
    winrt::com_ptr<ID3D11PixelShader> ps_;
    winrt::com_ptr<ID3D11Buffer> constants_;
    int width_=0,height_=0;
    bool valid_=false;
    float strength_=-1;
public:
    void Reset(ProbeCasStageStats& stats) {
        source_=nullptr;target_=nullptr;texture_=nullptr;
        width_=height_=0;valid_=false;
        stats.appliedStage=0;stats.textureBytes=0;
    }
    ID3D11ShaderResourceView* Apply(ID3D11Device* device,ID3D11DeviceContext* context,
            ID3D11VertexShader* vs,ID3D11ShaderResourceView* original,int width,int height,
            bool enabled,bool fresh,float strength,ProbeCasStageStats& stats) {
        if(!enabled) {Reset(stats);return original;}
        if(width!=width_ || height!=height_) {
            Reset(stats);width_=width;height_=height;
            D3D11_TEXTURE2D_DESC desc{};desc.Width=width;desc.Height=height;
            desc.MipLevels=1;desc.ArraySize=1;desc.SampleDesc.Count=1;
            desc.Format=DXGI_FORMAT_B8G8R8A8_UNORM;desc.Usage=D3D11_USAGE_DEFAULT;
            desc.BindFlags=D3D11_BIND_RENDER_TARGET|D3D11_BIND_SHADER_RESOURCE;
            winrt::check_hresult(device->CreateTexture2D(&desc,nullptr,texture_.put()));
            winrt::check_hresult(device->CreateRenderTargetView(texture_.get(),nullptr,target_.put()));
            winrt::check_hresult(device->CreateShaderResourceView(texture_.get(),nullptr,source_.put()));
            stats.textureBytes=static_cast<uint64_t>(width)*height*4;
        }
        if(!ps_) {
            auto p=CompositorShaders::SPS;
            winrt::check_hresult(device->CreatePixelShader(p.data,p.size,nullptr,ps_.put()));
            D3D11_BUFFER_DESC desc{};desc.ByteWidth=16;desc.Usage=D3D11_USAGE_DEFAULT;
            desc.BindFlags=D3D11_BIND_CONSTANT_BUFFER;
            winrt::check_hresult(device->CreateBuffer(&desc,nullptr,constants_.put()));
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
