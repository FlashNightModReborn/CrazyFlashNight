#pragma once

class FrameSyncSurface {
    struct Surface {
        winrt::com_ptr<ID3D11Texture2D> texture;
        winrt::com_ptr<ID3D11RenderTargetView> target;
        winrt::com_ptr<ID3D11ShaderResourceView> source;
    };
    Surface candidate_, history_[2];
    winrt::com_ptr<ID3D11PixelShader> pixel_;
    winrt::com_ptr<ID3D11Buffer> params_;
    int width_=0, height_=0, index_=0;
    bool cleared_=true;

    Surface Make(ID3D11Device* device, int width, int height) {
        Surface result;
        D3D11_TEXTURE2D_DESC desc{};
        desc.Width=width;desc.Height=height;desc.MipLevels=1;desc.ArraySize=1;
        desc.Format=DXGI_FORMAT_B8G8R8A8_UNORM;desc.SampleDesc.Count=1;
        desc.Usage=D3D11_USAGE_DEFAULT;desc.BindFlags=D3D11_BIND_RENDER_TARGET|D3D11_BIND_SHADER_RESOURCE;
        winrt::check_hresult(device->CreateTexture2D(&desc,nullptr,result.texture.put()));
        winrt::check_hresult(device->CreateRenderTargetView(result.texture.get(),nullptr,result.target.put()));
        winrt::check_hresult(device->CreateShaderResourceView(result.texture.get(),nullptr,result.source.put()));
        return result;
    }
    void Prepare(ID3D11Device* device) {
        if(pixel_)return;
        auto code=CompositorShaders::SyncPS;
        winrt::check_hresult(device->CreatePixelShader(code.data,code.size,nullptr,pixel_.put()));
        D3D11_BUFFER_DESC desc{};desc.ByteWidth=48;desc.BindFlags=D3D11_BIND_CONSTANT_BUFFER;
        desc.Usage=D3D11_USAGE_DEFAULT;
        winrt::check_hresult(device->CreateBuffer(&desc,nullptr,params_.put()));
    }
public:
    ID3D11Texture2D* CandidateTexture() const { return candidate_.texture.get(); }
    ID3D11RenderTargetView* CandidateTarget() const { return candidate_.target.get(); }

    void Resize(ID3D11Device* device,ID3D11DeviceContext* context,int width,int height) {
        if(width==width_ && height==height_)return;
        Prepare(device);
        candidate_=Make(device,width,height);history_[0]=Make(device,width,height);history_[1]=Make(device,width,height);
        width_=width;height_=height;index_=0;cleared_=false;
        Reset(device,context);
    }
    void Reset(ID3D11Device* device,ID3D11DeviceContext* context) {
        if(width_==0 || cleared_)return;
        Prepare(device);
        context->OMSetRenderTargets(0,nullptr,nullptr);
        const float clear[]{0,0,0,0};
        context->ClearRenderTargetView(history_[0].target.get(),clear);
        context->ClearRenderTargetView(history_[1].target.get(),clear);
        index_=0;cleared_=true;
    }
    void UpdateParams(ID3D11DeviceContext* context,const int* identity,int sourceWidth,int sourceHeight,
            const D3D11_VIEWPORT& viewport,bool enabled) {
        float values[12]{
            static_cast<float>(identity[0]),static_cast<float>(identity[1]),static_cast<float>(identity[2]),static_cast<float>(identity[3]),
            static_cast<float>(sourceWidth),static_cast<float>(sourceHeight),viewport.Width,viewport.Height,
            viewport.TopLeftX,viewport.TopLeftY,enabled?1.f:0.f,0};
        context->UpdateSubresource(params_.get(),0,nullptr,values,0,0);
        auto buffer=params_.get();
        context->VSSetConstantBuffers(7,1,&buffer);context->PSSetConstantBuffers(7,1,&buffer);
    }
    void Final(ID3D11DeviceContext* context,ID3D11VertexShader* vertex,ID3D11RenderTargetView* output,
            ID3D11ShaderResourceView* source,const int* identity,int sourceWidth,int sourceHeight,
            const D3D11_VIEWPORT& contentViewport,int outputWidth,int outputHeight,ID3D11SamplerState* sampler) {
        UpdateParams(context,identity,sourceWidth,sourceHeight,contentViewport,true);
        context->OMSetRenderTargets(0,nullptr,nullptr);
        auto candidate=candidate_.source.get(),previous=history_[index_].source.get();
        context->PSSetShaderResources(0,1,&candidate);context->PSSetShaderResources(1,1,&previous);
        context->PSSetShaderResources(2,1,&source);context->PSSetSamplers(0,1,&sampler);
        int next=1-index_;
        ID3D11RenderTargetView* targets[]{output,history_[next].target.get()};
        context->OMSetRenderTargets(2,targets,nullptr);
        D3D11_VIEWPORT viewport{0,0,static_cast<float>(outputWidth),static_cast<float>(outputHeight),0,1};
        context->RSSetViewports(1,&viewport);
        context->VSSetShader(vertex,nullptr,0);context->PSSetShader(pixel_.get(),nullptr,0);
        context->OMSetBlendState(nullptr,nullptr,0xffffffff);context->Draw(3,0);
        ID3D11ShaderResourceView* empty=nullptr;
        context->PSSetShaderResources(0,1,&empty);context->PSSetShaderResources(1,1,&empty);context->PSSetShaderResources(2,1,&empty);
        index_=next;cleared_=false;
    }
};
