#pragma once
// Also projected into the generated laboratory renderer.
constexpr double NightVisionScanCycleSeconds=7.0;
// Bounded GPU camera stage. No readback, per-unit texture, or CPU color scan.
class NightVisionStage {
    struct Surface {
        winrt::com_ptr<ID3D11Texture2D> texture;
        winrt::com_ptr<ID3D11RenderTargetView> target;
        winrt::com_ptr<ID3D11ShaderResourceView> source;
    };
    Surface world_,edge_,blur_,gain_[2],guide_[2],features_;
    winrt::com_ptr<ID3D11PixelShader> edgeShader_,blurShader_,meterShader_,finalShader_;
    winrt::com_ptr<ID3D11PixelShader> featureShader_,horizontalShader_,verticalShader_,jointShader_;
    winrt::com_ptr<ID3D11VertexShader> vertex_;
    winrt::com_ptr<ID3D11Buffer> constants_;
    winrt::com_ptr<ID3D11SamplerState> sampler_;
    int width_=0,height_=0,maskWidth_=0,maskHeight_=0,gainIndex_=0;
    uint64_t version_=0,epoch_=0;
    double lastMs_=0;
    double scanSeconds_=0;
    bool exposureValid_=false;
    bool adaptive_=false,edgesEnabled_=false;
    static void Make(ID3D11Device* device,Surface& s,int w,int h,DXGI_FORMAT format) {
        D3D11_TEXTURE2D_DESC d{};d.Width=w;d.Height=h;d.MipLevels=1;d.ArraySize=1;
        d.Format=format;d.SampleDesc.Count=1;d.Usage=D3D11_USAGE_DEFAULT;
        d.BindFlags=D3D11_BIND_SHADER_RESOURCE|D3D11_BIND_RENDER_TARGET;
        winrt::check_hresult(device->CreateTexture2D(&d,nullptr,s.texture.put()));
        winrt::check_hresult(device->CreateRenderTargetView(s.texture.get(),nullptr,s.target.put()));
        winrt::check_hresult(device->CreateShaderResourceView(s.texture.get(),nullptr,s.source.put()));
    }
    void Initialize(ID3D11Device* device) {
        if(constants_)return;
        auto vs=CompositorShaders::NVS;
        winrt::check_hresult(device->CreateVertexShader(vs.data,vs.size,nullptr,vertex_.put()));
        auto make=[&](CompositorShaders::Bytecode code,winrt::com_ptr<ID3D11PixelShader>& p) {
            winrt::check_hresult(device->CreatePixelShader(code.data,code.size,nullptr,p.put()));
        };
        make(CompositorShaders::NEPS,edgeShader_);make(CompositorShaders::NBPS,blurShader_);
        make(CompositorShaders::NMPS,meterShader_);make(CompositorShaders::NFPS,finalShader_);
        make(CompositorShaders::NAPS,featureShader_);make(CompositorShaders::NHPS,horizontalShader_);
        make(CompositorShaders::NVPS,verticalShader_);make(CompositorShaders::NJPS,jointShader_);
        D3D11_BUFFER_DESC cb{};cb.ByteWidth=112;cb.Usage=D3D11_USAGE_DEFAULT;cb.BindFlags=D3D11_BIND_CONSTANT_BUFFER;
        winrt::check_hresult(device->CreateBuffer(&cb,nullptr,constants_.put()));
        D3D11_SAMPLER_DESC sd{};sd.Filter=D3D11_FILTER_MIN_MAG_MIP_LINEAR;
        sd.AddressU=sd.AddressV=sd.AddressW=D3D11_TEXTURE_ADDRESS_CLAMP;sd.MaxLOD=0;
        winrt::check_hresult(device->CreateSamplerState(&sd,sampler_.put()));
    }
public:
    static bool Valid(const float* p,int count) {
        if(!p || count!=16)return false;
        for(int i=0;i<16;i++)if(!std::isfinite(p[i]))return false;
        if(p[0]==0) {for(int i=1;i<16;i++)if(p[i]!=0)return false;return true;}
        return p[0]==1 && p[1]>=0 && p[1]<=2 && p[2]>=.5f && p[2]<=3 && p[3]>=0 && p[3]<=1
            && p[4]>=0 && p[4]<=1 && p[5]>=1 && p[5]<=6 && p[6]>=.15f && p[6]<=1 && p[7]>=0 && p[7]<=2
            && p[8]>=0 && p[8]<=1 && p[9]>=0 && p[9]<=1 && p[10]>=0 && p[10]<=1 && p[11]>=.25f && p[11]<=8
            && p[12]>=.15f && p[12]<=1 && p[13]>=.05f && p[13]<=2 && p[14]>=.01f && p[14]<=.5f && p[15]>=0 && p[15]<=.08f;
    }
    void Reset() {
        world_=Surface{};edge_=Surface{};blur_=Surface{};gain_[0]=Surface{};gain_[1]=Surface{};
        guide_[0]=Surface{};guide_[1]=Surface{};features_=Surface{};adaptive_=false;edgesEnabled_=false;
        width_=height_=maskWidth_=maskHeight_=0;exposureValid_=false;lastMs_=0;scanSeconds_=0;
    }
    uint64_t TextureBytes() const {return width_?static_cast<uint64_t>(width_)*height_*4+static_cast<uint64_t>(maskWidth_)*maskHeight_*((edgesEnabled_?2:0)+(adaptive_?8:0)+(features_.texture?8:0))+32:0;}
    ID3D11Texture2D* GainForDiagnostics() const {return gain_[gainIndex_].texture.get();}
    ID3D11Texture2D* EdgesForDiagnostics() const {return edge_.texture.get();}
    // Caller binds the selected grade at b0, LUT at t1/s1, HDR fields at t3/t6,
    // point/scene light uniforms at b4/b6, and a full-screen raster state.
    void Apply(ID3D11Device* device,ID3D11DeviceContext* context,ID3D11Texture2D* composed,
            ID3D11RenderTargetView* output,const D3D11_VIEWPORT& viewport,const float* settings,
            uint64_t version,uint64_t epoch,double nowMs,bool lutActive) {
        if(settings[0]!=1){Reset();return;}
        Initialize(device);
        D3D11_TEXTURE2D_DESC d{};composed->GetDesc(&d);
        bool edges=settings[1]>0;
        bool adaptive=settings[3]>0 && (settings[1]>0 || settings[6]<1);
        int mw=settings[1]>0 || adaptive?std::max(1,std::min(1024,static_cast<int>(viewport.Width))):1;
        int mh=settings[1]>0 || adaptive?std::max(1,std::min(576,static_cast<int>(viewport.Height))):1;
        if(width_!=static_cast<int>(d.Width) || height_!=static_cast<int>(d.Height) || maskWidth_!=mw || maskHeight_!=mh || adaptive_!=adaptive || edgesEnabled_!=edges) {
            Reset();width_=d.Width;height_=d.Height;
            maskWidth_=mw;maskHeight_=mh;
            Make(device,world_,width_,height_,d.Format);
            edgesEnabled_=edges;
            if(edgesEnabled_) {
                Make(device,edge_,maskWidth_,maskHeight_,DXGI_FORMAT_R8_UNORM);
                Make(device,blur_,maskWidth_,maskHeight_,DXGI_FORMAT_R8_UNORM);
            }
            Make(device,gain_[0],1,1,DXGI_FORMAT_R32G32B32A32_FLOAT);
            Make(device,gain_[1],1,1,DXGI_FORMAT_R32G32B32A32_FLOAT);
            adaptive_=adaptive;
            if(adaptive_) {
                Make(device,guide_[0],mw,mh,DXGI_FORMAT_R8G8B8A8_UNORM);
                Make(device,guide_[1],mw,mh,DXGI_FORMAT_R8G8B8A8_UNORM);
            }
        }
        if(adaptive_ && settings[1]>0 && !features_.texture)
            Make(device,features_,mw,mh,DXGI_FORMAT_R16G16B16A16_FLOAT);
        if(settings[1]<=0)features_=Surface{};
        bool reset=!exposureValid_ || version_!=version || epoch_!=epoch || nowMs-lastMs_>500;
        if(reset) {const float one[]{1,0,0,1};context->ClearRenderTargetView(gain_[0].target.get(),one);
            context->ClearRenderTargetView(gain_[1].target.get(),one);gainIndex_=0;}
        float p[28]{};std::memcpy(p,settings,64);
        p[16]=1.f/maskWidth_;p[17]=1.f/maskHeight_;
        p[18]=reset?1.f/30.f:std::clamp(static_cast<float>((nowMs-lastMs_)/1000),0.f,.1f);p[19]=lutActive?1.f:0.f;
        p[20]=viewport.TopLeftX/width_;p[21]=viewport.TopLeftY/height_;
        p[22]=viewport.Width/width_;p[23]=viewport.Height/height_;
        scanSeconds_=reset || settings[15]<=0?0:std::fmod(scanSeconds_+p[18],NightVisionScanCycleSeconds);
        p[24]=static_cast<float>(scanSeconds_/NightVisionScanCycleSeconds);
        lastMs_=nowMs;version_=version;epoch_=epoch;exposureValid_=true;
        ID3D11ShaderResourceView* empty=nullptr;
        context->PSSetShaderResources(0,1,&empty);context->PSSetShaderResources(2,1,&empty);
        context->PSSetShaderResources(4,1,&empty);context->PSSetShaderResources(5,1,&empty);
        context->PSSetShaderResources(7,1,&empty);context->PSSetShaderResources(8,1,&empty);
        context->OMSetRenderTargets(0,nullptr,nullptr);context->CopyResource(world_.texture.get(),composed);
        context->UpdateSubresource(constants_.get(),0,nullptr,p,0,0);
        auto cb=constants_.get();context->VSSetConstantBuffers(7,1,&cb);context->PSSetConstantBuffers(7,1,&cb);
        auto sampler=sampler_.get();context->PSSetSamplers(0,1,&sampler);
        context->VSSetShader(vertex_.get(),nullptr,0);context->OMSetBlendState(nullptr,nullptr,0xffffffff);
        auto draw=[&](ID3D11RenderTargetView* target,ID3D11PixelShader* shader,float w,float h) {
            context->OMSetRenderTargets(1,&target,nullptr);D3D11_VIEWPORT v{0,0,w,h,0,1};context->RSSetViewports(1,&v);
            context->PSSetShader(shader,nullptr,0);context->Draw(3,0);
        };
        auto previousGain=gain_[gainIndex_].source.get();context->PSSetShaderResources(4,1,&previousGain);
        int next=1-gainIndex_;draw(gain_[next].target.get(),meterShader_.get(),1,1);
        context->PSSetShaderResources(4,1,&empty);gainIndex_=next;
        auto world=world_.source.get();context->PSSetShaderResources(0,1,&world);
        if(adaptive_) {
            if(settings[1]>0)
                draw(features_.target.get(),featureShader_.get(),static_cast<float>(mw),static_cast<float>(mh));
                draw(guide_[0].target.get(),horizontalShader_.get(),static_cast<float>(mw),static_cast<float>(mh));
                auto guide=guide_[0].source.get();context->PSSetShaderResources(7,1,&guide);
                draw(guide_[1].target.get(),verticalShader_.get(),static_cast<float>(mw),static_cast<float>(mh));
                context->PSSetShaderResources(7,1,&empty);
                for(int iteration=0;iteration<2;iteration++) {
                    int source=iteration==0?1:0,target=1-source;
                    guide=guide_[source].source.get();context->PSSetShaderResources(7,1,&guide);
                    draw(guide_[target].target.get(),jointShader_.get(),static_cast<float>(mw),static_cast<float>(mh));
                    context->PSSetShaderResources(7,1,&empty);
                }
        }
        if(settings[1]>0) {
            if(adaptive_) {
                auto guide=guide_[1].source.get(),features=features_.source.get();
                context->PSSetShaderResources(7,1,&guide);context->PSSetShaderResources(8,1,&features);
            }
            draw(edge_.target.get(),edgeShader_.get(),static_cast<float>(maskWidth_),static_cast<float>(maskHeight_));
            context->PSSetShaderResources(7,1,&empty);context->PSSetShaderResources(8,1,&empty);
            auto edge=edge_.source.get();context->PSSetShaderResources(2,1,&edge);
            draw(blur_.target.get(),blurShader_.get(),static_cast<float>(maskWidth_),static_cast<float>(maskHeight_));
        } // Edge/halo textures are absent when no contour is drawn.
        context->OMSetRenderTargets(1,&output,nullptr);context->RSSetViewports(1,&viewport);
        auto edge=edge_.source.get(),blur=blur_.source.get(),gain=gain_[gainIndex_].source.get();
        auto guide=adaptive_?guide_[1].source.get():nullptr;context->PSSetShaderResources(7,1,&guide);
        context->PSSetShaderResources(2,1,&edge);context->PSSetShaderResources(5,1,&blur);context->PSSetShaderResources(4,1,&gain);
        context->PSSetShader(finalShader_.get(),nullptr,0);context->Draw(3,0);
        context->PSSetShaderResources(0,1,&empty);context->PSSetShaderResources(2,1,&empty);
        context->PSSetShaderResources(4,1,&empty);context->PSSetShaderResources(5,1,&empty);
        context->PSSetShaderResources(7,1,&empty);context->PSSetShaderResources(8,1,&empty);
    }
};
