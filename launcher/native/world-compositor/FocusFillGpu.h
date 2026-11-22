// Included next to HudRasterFrame. The worker owns all D3D objects.
struct FocusFillAtlas {
    int width=0,height=0;
    std::vector<uint8_t> pixels;
};
struct FocusFillFrame {
    std::shared_ptr<const FocusFillAtlas> atlas;
    int count=0;
    std::array<int,32> items{};
};
using FocusCounts=std::array<std::atomic<uint64_t>,6>;

class FocusFillGpu {
    com_ptr<ID3D11VertexShader> vertex_;
    com_ptr<ID3D11PixelShader> pixel_;
    com_ptr<ID3D11Buffer> buffer_;
    com_ptr<ID3D11ShaderResourceView> resource_;
    std::shared_ptr<const FocusFillAtlas> atlas_;
    std::shared_ptr<const FocusFillFrame> last_;
    int lastWidth_=0,lastHeight_=0;
public:
    void ClearAtlas() {last_.reset();atlas_.reset();resource_=nullptr;}
    void Draw(ID3D11Device* d,ID3D11DeviceContext* ctx,const std::shared_ptr<const FocusFillFrame>& f,
        int width,int height,FocusCounts& stats) {
        if(!f || !f->count)return;
        struct Parameters { float output[4]; int items[32]; };
        if(!vertex_) {
            check_hresult(d->CreateVertexShader(CompositorShaders::FocusVS.data,CompositorShaders::FocusVS.size,nullptr,vertex_.put()));
            check_hresult(d->CreatePixelShader(CompositorShaders::FocusPS.data,CompositorShaders::FocusPS.size,nullptr,pixel_.put()));
            D3D11_BUFFER_DESC bd{};bd.ByteWidth=sizeof(Parameters);bd.BindFlags=D3D11_BIND_CONSTANT_BUFFER;
            check_hresult(d->CreateBuffer(&bd,nullptr,buffer_.put()));
        }
        if(atlas_!=f->atlas) {
            const auto& a=*f->atlas;
            D3D11_TEXTURE2D_DESC td{};td.Width=a.width;td.Height=a.height;td.MipLevels=td.ArraySize=1;
            td.SampleDesc.Count=1;td.Format=DXGI_FORMAT_B8G8R8A8_UNORM;td.Usage=D3D11_USAGE_IMMUTABLE;
            td.BindFlags=D3D11_BIND_SHADER_RESOURCE;
            D3D11_SUBRESOURCE_DATA data{a.pixels.data(),UINT(a.width*4),0};
            com_ptr<ID3D11Texture2D> tex;
            check_hresult(d->CreateTexture2D(&td,&data,tex.put()));
            resource_=nullptr;check_hresult(d->CreateShaderResourceView(tex.get(),nullptr,resource_.put()));
            atlas_=f->atlas;++stats[3];stats[4]+=a.pixels.size();
        }
        if(f!=last_ || lastWidth_!=width || lastHeight_!=height) {
            Parameters p{{float(width),float(height),0,0},{}};
            std::memcpy(p.items,f->items.data(),sizeof(p.items));
            ctx->UpdateSubresource(buffer_.get(),0,nullptr,&p,0,0);stats[5]+=sizeof(p);
            last_=f;lastWidth_=width;lastHeight_=height;
        }
        auto cb=buffer_.get();auto srv=resource_.get();ctx->VSSetConstantBuffers(0,1,&cb);
        ctx->PSSetShaderResources(0,1,&srv);ctx->VSSetShader(vertex_.get(),nullptr,0);ctx->PSSetShader(pixel_.get(),nullptr,0);
        ctx->DrawInstanced(6,UINT(f->count),0,0);++stats[1];stats[2]+=f->count;
    }
};
