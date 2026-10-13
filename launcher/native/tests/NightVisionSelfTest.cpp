#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <d3d11.h>
#include <winrt/base.h>
#include <algorithm>
#include <cmath>
#include <cstring>
#include <vector>
#include <array>
#include <cstdio>
#include <chrono>
#include <fstream>
#include <CompositorShaders.g.h>
#include "../world-compositor/NightVisionStage.h"
using winrt::com_ptr;
using winrt::check_hresult;
namespace {
int passed=0,failed=0;
void Check(bool value,const char* label) {if(value)++passed;else{++failed;std::printf("FAIL %s\n",label);}}
com_ptr<ID3D11Buffer> Buffer(ID3D11Device* d,const float* p,UINT bytes) {
    D3D11_BUFFER_DESC b{};b.ByteWidth=bytes;b.Usage=D3D11_USAGE_DEFAULT;b.BindFlags=D3D11_BIND_CONSTANT_BUFFER;
    D3D11_SUBRESOURCE_DATA data{p,0,0};com_ptr<ID3D11Buffer> r;check_hresult(d->CreateBuffer(&b,&data,r.put()));return r;
}
std::vector<uint8_t> Read(ID3D11Device* d,ID3D11DeviceContext* c,ID3D11Texture2D* t) {
    D3D11_TEXTURE2D_DESC td{};t->GetDesc(&td);
    UINT bytes=td.Format==DXGI_FORMAT_R32G32B32A32_FLOAT?16:(td.Format==DXGI_FORMAT_R8_UNORM?1:4);
    td.Usage=D3D11_USAGE_STAGING;td.BindFlags=0;td.CPUAccessFlags=D3D11_CPU_ACCESS_READ;
    com_ptr<ID3D11Texture2D> staging;check_hresult(d->CreateTexture2D(&td,nullptr,staging.put()));c->CopyResource(staging.get(),t);
    D3D11_MAPPED_SUBRESOURCE m{};check_hresult(c->Map(staging.get(),0,D3D11_MAP_READ,0,&m));
    std::vector<uint8_t> result(static_cast<size_t>(td.Width)*td.Height*bytes);
    for(UINT y=0;y<td.Height;y++)std::memcpy(result.data()+static_cast<size_t>(y)*td.Width*bytes,
        static_cast<const uint8_t*>(m.pData)+static_cast<size_t>(y)*m.RowPitch,static_cast<size_t>(td.Width)*bytes);
    c->Unmap(staging.get(),0);return result;
}
struct Harness {
    com_ptr<ID3D11Device> device;com_ptr<ID3D11DeviceContext> context;
    com_ptr<ID3D11Texture2D> original,output,field;
    com_ptr<ID3D11Texture3D> lut;
    com_ptr<ID3D11ShaderResourceView> lutView;
    bool useLut=false;
    com_ptr<ID3D11RenderTargetView> target;com_ptr<ID3D11ShaderResourceView> fieldView;
    com_ptr<ID3D11SamplerState> sampler;
    com_ptr<ID3D11Buffer> grade,point,scene;
    NightVisionStage stage;
    std::vector<uint8_t> pixels;
    int width,height;D3D11_VIEWPORT viewport;
    std::array<float,16> profile{1,.62f,1.1f,.72f,.22f,1.8f,.70f,.95f,.46f,1,.49f,.85f,.4f,.8f,.045f,0};
    double now=0;uint64_t version=1,epoch=0;
    Harness(int w,int h):width(w),height(h),viewport{0,16.f,static_cast<float>(w),static_cast<float>(h-32),0,1} {
        D3D_FEATURE_LEVEL level{};
        check_hresult(D3D11CreateDevice(nullptr,D3D_DRIVER_TYPE_HARDWARE,nullptr,0,nullptr,0,D3D11_SDK_VERSION,device.put(),&level,context.put()));
        pixels.resize(static_cast<size_t>(w)*h*4,255);
        // White material panel, textured background, and a diagonal colored actor.
        // These are input pixels, not semantic target detection tests (covered in Flash).
        for(int y=16;y<h-16;y++)for(int x=0;x<w;x++) {
            auto at=(static_cast<size_t>(y)*w+x)*4;
            bool diagonal=std::abs(x-w/2-(y-h/2)/2)<w/32;
            uint8_t gray=x<w/4?220:static_cast<uint8_t>(30+((x/12+y/12)%2)*12);
            pixels[at]=diagonal?60:gray;pixels[at+1]=diagonal?130:gray;pixels[at+2]=diagonal?230:gray;
        }
        D3D11_TEXTURE2D_DESC t{};t.Width=w;t.Height=h;t.MipLevels=1;t.ArraySize=1;t.SampleDesc.Count=1;
        t.Format=DXGI_FORMAT_B8G8R8A8_UNORM;t.Usage=D3D11_USAGE_DEFAULT;t.BindFlags=D3D11_BIND_RENDER_TARGET|D3D11_BIND_SHADER_RESOURCE;
        D3D11_SUBRESOURCE_DATA data{pixels.data(),static_cast<UINT>(w*4),0};
        check_hresult(device->CreateTexture2D(&t,&data,original.put()));check_hresult(device->CreateTexture2D(&t,nullptr,output.put()));
        check_hresult(device->CreateRenderTargetView(output.get(),nullptr,target.put()));
        t.Width=16;t.Height=9;t.Format=DXGI_FORMAT_R32G32B32A32_FLOAT;t.BindFlags=D3D11_BIND_SHADER_RESOURCE;
        check_hresult(device->CreateTexture2D(&t,nullptr,field.put()));check_hresult(device->CreateShaderResourceView(field.get(),nullptr,fieldView.put()));
        const float g[]{1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1};grade=Buffer(device.get(),g,64);
        const float p[]{0,16.f,static_cast<float>(w),static_cast<float>(h-32),0,0,1,0,1,1,1,0,1,1,1,0};point=Buffer(device.get(),p,64);
        const float s[8]{};scene=Buffer(device.get(),s,32);
        D3D11_SAMPLER_DESC sd{};sd.Filter=D3D11_FILTER_MIN_MAG_MIP_LINEAR;sd.AddressU=sd.AddressV=sd.AddressW=D3D11_TEXTURE_ADDRESS_CLAMP;sd.MaxLOD=0;
        check_hresult(device->CreateSamplerState(&sd,sampler.put()));
        D3D11_RASTERIZER_DESC rd{};rd.FillMode=D3D11_FILL_SOLID;rd.CullMode=D3D11_CULL_NONE;rd.DepthClipEnable=TRUE;
        com_ptr<ID3D11RasterizerState> raster;check_hresult(device->CreateRasterizerState(&rd,raster.put()));context->RSSetState(raster.get());
        context->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
        Light(0);
    }
    void Light(float strength) {
        std::array<float,16*9*4> values{};
        for(size_t n=0;n<values.size();n+=4){values[n]=values[n+1]=values[n+2]=strength;values[n+3]=strength;}
        context->UpdateSubresource(field.get(),0,nullptr,values.data(),16*16,0);
    }
    void Upload() {context->UpdateSubresource(original.get(),0,nullptr,pixels.data(),static_cast<UINT>(width*4),0);}
    void GreenLut() {
        std::vector<uint8_t> bytes(32*32*32*4);
        for(int b=0;b<32;b++)for(int g=0;g<32;g++)for(int r=0;r<32;r++) {
            size_t at=static_cast<size_t>((b*32+g)*32+r)*4;
            bytes[at]=static_cast<uint8_t>(std::round(r/31.f*255*.15f));
            bytes[at+1]=static_cast<uint8_t>(std::round(g/31.f*255));
            bytes[at+2]=static_cast<uint8_t>(std::round(b/31.f*255*.15f));bytes[at+3]=255;
        }
        D3D11_TEXTURE3D_DESC t{};t.Width=t.Height=t.Depth=32;t.MipLevels=1;
        t.Format=DXGI_FORMAT_R8G8B8A8_UNORM;t.Usage=D3D11_USAGE_DEFAULT;t.BindFlags=D3D11_BIND_SHADER_RESOURCE;
        D3D11_SUBRESOURCE_DATA data{bytes.data(),32*4,32*32*4};
        check_hresult(device->CreateTexture3D(&t,&data,lut.put()));check_hresult(device->CreateShaderResourceView(lut.get(),nullptr,lutView.put()));useLut=true;
    }
    // Bake the replay matrix into the same 32-cube RGBA8 LUT layout as Host.
    // Full-camera fixtures exercise quantized trilinear sampling, not just the
    // diagnostic matrix branch. This adds no runtime code or readback.
    void MatrixLut(const std::array<float,16>& matrix) {
        std::vector<uint8_t> bytes(32*32*32*4);
        for(int b=0;b<32;b++)for(int g=0;g<32;g++)for(int r=0;r<32;r++) {
            size_t at=static_cast<size_t>((b*32+g)*32+r)*4;
            for(int channel=0;channel<3;channel++) {
                size_t row=static_cast<size_t>(channel)*4;
                float value=matrix[row]*r/31.f+matrix[row+1]*g/31.f+matrix[row+2]*b/31.f+matrix[row+3]+matrix[12+channel];
                value=std::pow(std::clamp(value,0.f,1.f),1.f/std::max(matrix[15],.001f));
                bytes[at+channel]=static_cast<uint8_t>(std::round(value*255));
            }
            bytes[at+3]=255;
        }
        RawLut(bytes);
    }
    // Replay exact managed baker output, including optional nonlinear tone curves.
    // Keep the diagnostic tool from becoming a second authored grading implementation.
    void RawLut(const std::vector<uint8_t>& bytes) {
        if(bytes.size()!=32*32*32*4)throw std::runtime_error("32-cube RGBA LUT required");
        D3D11_TEXTURE3D_DESC t{};t.Width=t.Height=t.Depth=32;t.MipLevels=1;
        t.Format=DXGI_FORMAT_R8G8B8A8_UNORM;t.Usage=D3D11_USAGE_DEFAULT;t.BindFlags=D3D11_BIND_SHADER_RESOURCE;
        D3D11_SUBRESOURCE_DATA data{bytes.data(),32*4,32*32*4};
        check_hresult(device->CreateTexture3D(&t,&data,lut.put()));check_hresult(device->CreateShaderResourceView(lut.get(),nullptr,lutView.put()));useLut=true;
    }
    void Frame() {
        context->OMSetRenderTargets(0,nullptr,nullptr);context->CopyResource(output.get(),original.get());
        auto g=grade.get(),p=point.get(),s=scene.get();context->PSSetConstantBuffers(0,1,&g);context->PSSetConstantBuffers(4,1,&p);context->PSSetConstantBuffers(6,1,&s);
        auto fieldResource=fieldView.get();context->PSSetShaderResources(3,1,&fieldResource);auto samp=sampler.get();context->PSSetSamplers(3,1,&samp);
        auto ls=lutView.get();context->PSSetShaderResources(1,1,&ls);context->PSSetSamplers(1,1,&samp);
        now+=1000.0/30;
        stage.Apply(device.get(),context.get(),output.get(),target.get(),viewport,profile.data(),version,epoch,now,useLut);
    }
    float Gain() {auto data=Read(device.get(),context.get(),stage.GainForDiagnostics());float value;std::memcpy(&value,data.data(),4);return value;}
};
double RegionMean(const std::vector<uint8_t>& data,int width,int x,int y,int w,int h) {
    double sum=0;
    for(int row=y;row<y+h;row++)for(int col=x;col<x+w;col++)sum+=data[static_cast<size_t>(row)*width+col];
    return sum/(w*h*255.);
}
void TextureTests() {
    Harness h(512,320);h.viewport={0,0,512,320,0,1};
    uint32_t seed=12345;
    for(int y=0;y<h.height;y++)for(int x=0;x<h.width;x++) {
        seed=1664525*seed+1013904223;
        uint8_t value;
        if(x<160)value=static_cast<uint8_t>(40+(seed>>24)%100); // irregular, high-contrast gravel
        else if(x<320)value=((x%8<2)||(y%8<2))?185:35; // connected regular mesh
        else value=x<416?35:150; // large structural step
        if(x>=336 && x<395 && std::abs(y-72-(x-336)/2)<2)value=210; // isolated thin diagonal
        size_t at=(static_cast<size_t>(y)*h.width+x)*4;
        h.pixels[at]=h.pixels[at+1]=h.pixels[at+2]=value;
    }
    h.Upload();h.profile[3]=0;h.Frame();
    auto raw=Read(h.device.get(),h.context.get(),h.stage.EdgesForDiagnostics());
    auto rawBytes=h.stage.TextureBytes();
    h.profile[3]=.72f;++h.version;h.Frame();
    auto structure=Read(h.device.get(),h.context.get(),h.stage.EdgesForDiagnostics());
    double gravel=RegionMean(structure,512,16,16,128,270)/RegionMean(raw,512,16,16,128,270);
    double mesh=RegionMean(structure,512,176,16,128,270)/RegionMean(raw,512,176,16,128,270);
    std::printf("Structure detail fixture: boundary=%.4f thin=%.4f\n",RegionMean(structure,512,414,20,4,270),RegionMean(structure,512,340,70,50,35));
    Check(gravel<.12,"dense irregular gravel is suppressed");
    Check(mesh<.20,"connected mesh is suppressed without short-component assumptions");
    int boundaryRows=0;
    for(int y=20;y<290;y++){
        uint8_t peak=0;for(int x=414;x<418;x++)peak=std::max(peak,structure[static_cast<size_t>(y)*512+x]);
        if(peak>=128)++boundaryRows;
    }
    Check(boundaryRows>=265,"large boundary stays above half intensity for every row");
    Check(RegionMean(structure,512,340,70,50,35)>.025,"isolated thin diagonal survives scale filtering");
    Check(RegionMean(structure,512,430,30,50,230)<.002,"flat material does not acquire artificial edges");
    Check(h.stage.TextureBytes()>rawBytes,"adaptive intermediates are accounted for");
    h.profile[3]=0;++h.version;h.Frame();
    Check(h.stage.TextureBytes()==rawBytes,"zero suppression releases adaptive intermediates");
    Check(Read(h.device.get(),h.context.get(),h.stage.EdgesForDiagnostics())==raw,"zero suppression restores exact raw detector");
    for(int y=0;y<h.height;y++)for(int x=0;x<h.width;x++){
        size_t at=(static_cast<size_t>(y)*h.width+x)*4;
        h.pixels[at]=0;h.pixels[at+1]=x<256?0:76;h.pixels[at+2]=x<256?255:0;
    }
    h.Upload();h.profile[3]=.72f;++h.version;h.Frame();
    auto chromatic=Read(h.device.get(),h.context.get(),h.stage.EdgesForDiagnostics());
    Check(RegionMean(chromatic,512,254,20,4,270)>.35,"equal-luminance color boundary is retained");
    std::printf("Texture fixture retained edge energy: gravel=%.3f mesh=%.3f\n",gravel,mesh);
}
double ColorStddev(const std::vector<uint8_t>& data,int width,int x,int y,int w,int h) {
    double sum=0,squares=0;
    for(int row=y;row<y+h;row++)for(int col=x;col<x+w;col++) {
        double value=data[(static_cast<size_t>(row)*width+col)*4];sum+=value;squares+=value*value;
    }
    double mean=sum/(w*h);return std::sqrt(std::max(0.0,squares/(w*h)-mean*mean));
}
void UnderlayTests() {
    Harness h(512,320);h.viewport={0,0,512,320,0,1};uint32_t seed=6789;
    for(int y=0;y<h.height;y++)for(int x=0;x<h.width;x++) {
        seed=1664525*seed+1013904223;
        uint8_t value=static_cast<uint8_t>(36+(seed>>24)%40);
        if(x>220 && x<300 && y>65 && y<270)value=235; // bright semantic-unit input fixture
        size_t at=(static_cast<size_t>(y)*h.width+x)*4;
        h.pixels[at]=h.pixels[at+1]=h.pixels[at+2]=value;
    }
    h.Upload();h.profile={1,0,1,.9f,0,1,1,0,1,1,1,1,.4f,.8f,.04f,0};h.Frame();
    auto raw=Read(h.device.get(),h.context.get(),h.output.get());
    h.profile[6]=.96f;++h.version;h.Frame();auto filtered=Read(h.device.get(),h.context.get(),h.output.get());
    double noise=ColorStddev(filtered,512,20,20,160,260)/ColorStddev(raw,512,20,20,160,260);
    size_t hot=(180*512+260)*4,cold=(180*512+80)*4;
    Check(noise<.30,"underlay removes grain even with environment edges disabled");
    Check(filtered[hot]>210 && filtered[hot]>filtered[cold]+140,"white-hot input remains distinct from cold background");
    Check(h.stage.EdgesForDiagnostics()==nullptr,"thermal underlay allocates no unused environment contour texture");
    Check(h.stage.TextureBytes()==512ull*320*(4+8)+32,"fill-only denoising skips edge, halo and float edge-feature textures");
    h.profile[3]=0;++h.version;h.Frame();auto restored=Read(h.device.get(),h.context.get(),h.output.get());
    Check(ColorStddev(restored,512,20,20,160,260)/ColorStddev(raw,512,20,20,160,260)>.90,"zero suppression restores underlay texture");
    h.profile[3]=1;h.profile[6]=1;++h.version;h.Frame();
    Check(Read(h.device.get(),h.context.get(),h.output.get())==raw,"full-retention true vision bypasses underlay smoothing");
    std::printf("Underlay fixture retained noise stddev=%.3f hot=%u cold=%u\n",noise,filtered[hot],filtered[cold]);
}
void InstrumentTests() {
    Harness h(512,576);
    std::fill(h.pixels.begin(),h.pixels.end(),static_cast<uint8_t>(128));
    for(size_t n=3;n<h.pixels.size();n+=4)h.pixels[n]=255;
    h.Upload();h.profile={1,0,1,0,0,1,1,0,1,1,1,1,.4f,.8f,.04f,.065f};
    Check(NightVisionStage::Valid(h.profile.data(),16),"bounded scan strength uses the existing 16-float camera contract");
    auto bad=h.profile;bad[15]=.081f;Check(!NightVisionStage::Valid(bad.data(),16),"excessive scan contrast rejected");
    bad[15]=-.001f;Check(!NightVisionStage::Valid(bad.data(),16),"negative scan contrast rejected");
    h.Frame();auto first=Read(h.device.get(),h.context.get(),h.output.get());auto memory=h.stage.TextureBytes();
    auto row=[](const std::vector<uint8_t>& image,int y){return image[static_cast<size_t>(y)*512*4];};
    int maximum=0,minimum=255;
    for(int y=32;y<544;y++){int value=row(first,y);maximum=std::max(maximum,value);minimum=std::min(minimum,value);}
    Check(maximum-minimum>=6 && minimum>=123 && maximum<=133,"fine scan rows keep the accepted contrast outside the sweeping front");
    Check(std::equal(first.begin(),first.begin()+512*16*4,h.pixels.begin()),"instrument processing excludes non-world margins");
    bool regularRows=true;
    for(int y=32;y<544;y++)for(int x=1;x<512;x++)
        regularRows&=first[(static_cast<size_t>(y)*512+x)*4]==row(first,y);
    Check(regularRows,"instrument rows are horizontal and regular, not random grain");
    for(int n=0;n<15;n++)h.Frame();auto drifted=Read(h.device.get(),h.context.get(),h.output.get());
    int drift=0;for(int y=400;y<450;y++)drift=std::max(drift,std::abs(int(row(drifted,y))-int(row(first,y))));
    Check(drift>=2,"fine rows drift even in a region outside the moving band");
    for(int n=0;n<45;n++)h.Frame();auto swept=Read(h.device.get(),h.context.get(),h.output.get());
    int peak=0,peakY=0;for(int y=16;y<560;y++)if(row(swept,y)>peak){peak=row(swept,y);peakY=y;}
    double trail=0,ahead=0;
    for(int y=peakY-65;y<peakY-25;y++)trail+=row(swept,y)/40.0;
    for(int y=peakY+25;y<peakY+65;y++)ahead+=row(swept,y)/40.0;
    Check(peak>=147 && peak<=163 && peakY>=172 && peakY<=195,"seven-second front descends to the expected screen location with bounded contrast");
    Check(trail>ahead+3 && trail<140 && ahead>=127 && ahead<=129,"scan front has a softer fading trail behind it, with the region ahead unaffected");
    Check(h.stage.TextureBytes()==memory,"instrument scan adds no textures or extra image passes");
    for(int n=0;n<150;n++)h.Frame();auto wrapped=Read(h.device.get(),h.context.get(),h.output.get());
    int wrapDifference=0;for(size_t n=0;n<first.size();n++)wrapDifference=std::max(wrapDifference,std::abs(int(first[n])-int(wrapped[n])));
    Check(wrapDifference<=1,"seven-second cycle wraps without a full-camera brightness jump");
    for(int n=0;n<35;n++)h.Frame();++h.epoch;h.Frame();
    Check(Read(h.device.get(),h.context.get(),h.output.get())==first,"new scene resets instrument phase without stale bands");
    h.profile[15]=0;++h.version;h.Frame();
    Check(Read(h.device.get(),h.context.get(),h.output.get())==h.pixels,"zero scan strength restores exact natural camera output");
    h.profile[1]=.5f;++h.version;h.Frame();auto rawEdges=Read(h.device.get(),h.context.get(),h.stage.EdgesForDiagnostics());
    h.profile[15]=.065f;++h.version;h.Frame();
    Check(Read(h.device.get(),h.context.get(),h.stage.EdgesForDiagnostics())==rawEdges,"instrument rows never enter edge detection");
    h.Light(8);h.profile[7]=2;h.profile[11]=.25f;h.profile[15]=0;++h.version;h.Frame();
    auto glare=Read(h.device.get(),h.context.get(),h.output.get());
    h.profile[15]=.065f;++h.version;h.Frame();auto scannedGlare=Read(h.device.get(),h.context.get(),h.output.get());
    int glareDifference=0;
    for(size_t n=0;n<glare.size();n++)glareDifference=std::max(glareDifference,std::abs(int(glare[n])-int(scannedGlare[n])));
    Check(glareDifference<=1,"strong actual illumination washes out the scan texture");
    Harness tinyView(256,144);tinyView.profile={1,0,1,0,0,1,1,0,1,1,1,1,.4f,.8f,.04f,0};
    tinyView.Frame();auto smallPlain=Read(tinyView.device.get(),tinyView.context.get(),tinyView.output.get());
    tinyView.profile[15]=.065f;++tinyView.version;tinyView.Frame();
    Check(Read(tinyView.device.get(),tinyView.context.get(),tinyView.output.get())==smallPlain,"fine rows fade below the sampling limit instead of aliasing");
    h.Light(0);h.profile[1]=0;h.profile[15]=.08f;
    std::fill(h.pixels.begin(),h.pixels.end(),static_cast<uint8_t>(0));
    for(size_t n=3;n<h.pixels.size();n+=4)h.pixels[n]=255;
    h.Upload();++h.epoch;h.Frame();for(int n=0;n<60;n++)h.Frame();
    Check(Read(h.device.get(),h.context.get(),h.output.get())==h.pixels,"even the stronger scan front preserves pure black ink");
    std::printf("Instrument fixture peak=%d y=%d trail=%.2f ahead=%.2f drift=%d wrap=%d\n",peak,peakY,trail,ahead,drift,wrapDifference);
}
void Replay(const char* inputPath,const char* outputPath,const char* cameraPath=nullptr,bool useCameraLut=false,const char* lutPath=nullptr,double seconds=0) {
    std::ifstream input(inputPath,std::ios::binary);uint32_t dimensions[2]{};
    input.read(reinterpret_cast<char*>(dimensions),8);
    if(!input || dimensions[0]<32 || dimensions[0]>1024 || dimensions[1]<32 || dimensions[1]>576)
        throw std::runtime_error("Replay expects logical-sized BGRA input");
    Harness h(static_cast<int>(dimensions[0]),static_cast<int>(dimensions[1]));
    h.viewport={0,0,static_cast<float>(h.width),static_cast<float>(h.height),0,1};
    input.read(reinterpret_cast<char*>(h.pixels.data()),static_cast<std::streamsize>(h.pixels.size()));
    if(!input)throw std::runtime_error("Incomplete replay pixels");
    if(cameraPath) {
        std::ifstream camera(cameraPath,std::ios::binary);std::array<float,16> settings{};
        camera.read(reinterpret_cast<char*>(h.profile.data()),64);
        camera.read(reinterpret_cast<char*>(settings.data()),64);
        if(!camera || !NightVisionStage::Valid(h.profile.data(),16))throw std::runtime_error("Invalid replay camera settings");
        h.context->UpdateSubresource(h.grade.get(),0,nullptr,settings.data(),0,0);
        if(lutPath) {
            std::ifstream lutInput(lutPath,std::ios::binary);std::vector<uint8_t> bytes(32*32*32*4);
            lutInput.read(reinterpret_cast<char*>(bytes.data()),static_cast<std::streamsize>(bytes.size()));
            if(!lutInput || lutInput.peek()!=std::char_traits<char>::eof())throw std::runtime_error("Invalid managed replay LUT");
            h.RawLut(bytes);
        } else if(useCameraLut)h.MatrixLut(settings);
    }
    if(!std::isfinite(seconds) || seconds<0 || seconds>20)throw std::runtime_error("Replay time must be within the scan cycle");
    h.Upload();h.Frame();for(int n=0;n<static_cast<int>(std::round(seconds*30));n++)h.Frame();
    auto pixels=Read(h.device.get(),h.context.get(),cameraPath?h.output.get():h.stage.EdgesForDiagnostics());
    std::ofstream output(outputPath,std::ios::binary);
    output.write(reinterpret_cast<const char*>(dimensions),8);
    output.write(reinterpret_cast<const char*>(pixels.data()),static_cast<std::streamsize>(pixels.size()));
    if(!output)throw std::runtime_error("Unable to write replay mask");
    std::printf("Replayed original frame on production GPU structure stage: %ux%u\n",dimensions[0],dimensions[1]);
}
}
int main(int argc,char** argv) {
    try {
        if(argc==3){Replay(argv[1],argv[2]);return 0;}
        if(argc==6 && std::strcmp(argv[1],"--camera-lut-file")==0){
            Replay(argv[2],argv[5],argv[3],false,argv[4]);return 0;
        }
        if(argc==7 && std::strcmp(argv[1],"--camera-lut-file-time")==0){
            Replay(argv[2],argv[5],argv[3],false,argv[4],std::stod(argv[6]));return 0;
        }
        if(argc==5 && (std::strcmp(argv[1],"--camera")==0 || std::strcmp(argv[1],"--camera-lut")==0)){
            Replay(argv[2],argv[4],argv[3],std::strcmp(argv[1],"--camera-lut")==0);return 0;
        }
        Harness h(512,320);auto bad=h.profile;bad[14]=NAN;
        Check(NightVisionStage::Valid(h.profile.data(),16),"valid authored settings");
        Check(!NightVisionStage::Valid(bad.data(),16),"nonfinite rejected");
        Check(!NightVisionStage::Valid(h.profile.data(),15),"wrong ABI count rejected");
        h.profile[0]=0;h.profile.fill(0);h.Frame();
        Check(Read(h.device.get(),h.context.get(),h.output.get())==h.pixels,"disabled is exact bypass");
        h.profile={1,0,1,1,0,1,1,0,1,1,1,1,.4f,.8f,.04f,0};++h.version;h.Frame();
        auto identity=Read(h.device.get(),h.context.get(),h.output.get());
        int maxError=0;for(size_t n=0;n<identity.size();n++)maxError=std::max(maxError,std::abs(static_cast<int>(identity[n])-h.pixels[n]));
        Check(maxError<=1,"true vision identity including letterbox");
        Check(h.Gain()>.999f,"white artwork does not trigger glare");
        h.profile={1,.62f,1.1f,.72f,.22f,1.8f,.70f,.95f,.46f,1,.49f,.85f,.4f,.8f,.045f,0};++h.version;h.Frame();
        auto edged=Read(h.device.get(),h.context.get(),h.output.get());size_t at=(static_cast<size_t>(h.height/2)*h.width+h.width/4)*4;
        Check(edged[at+1]>h.pixels[at+1],"outline raises boundary brightness");
        Check(std::equal(edged.begin(),edged.begin()+h.width*16*4,h.pixels.begin()),"camera excludes top margin and HUD domain");
        h.Light(8);h.Frame();float attacked=h.Gain();
        Check(attacked<.8f,"strong actual light attacks camera gain within a frame");
        for(int n=0;n<12;n++)h.Frame();float blinded=h.Gain();
        Check(blinded>=.399f && blinded<.45f,"gain reaches authored floor");
        auto glare=Read(h.device.get(),h.context.get(),h.output.get());
        Check(glare[at+1]>edged[at+1],"local strong light washes out assisted details");
        h.Light(0);h.Frame();float recoveryStart=h.Gain();
        Check(recoveryStart>blinded && recoveryStart<.55f,"recovery is slower than attack");
        for(int n=0;n<90;n++)h.Frame();Check(h.Gain()>.97f,"gain recovers after light leaves");
        h.Light(8);for(int n=0;n<12;n++)h.Frame();h.Light(0);++h.epoch;h.Frame();
        Check(h.Gain()>.999f,"pause or scene epoch resets old blindness");
        h.Light(8);for(int n=0;n<12;n++)h.Frame();h.Light(0);++h.version;h.Frame();
        Check(h.Gain()>.999f,"profile change resets exposure");
        h.GreenLut();h.profile[1]=0;h.profile[6]=1;h.profile[7]=0;++h.version;h.Frame();
        auto green=Read(h.device.get(),h.context.get(),h.output.get());size_t white=(static_cast<size_t>(h.height/2)*h.width+h.width/8)*4;
        Check(green[white+1]>210 && green[white]<40 && green[white+2]<40,"selected LUT grades the composed camera input");
        Check(std::equal(green.begin(),green.begin()+h.width*16*4,h.pixels.begin()),"LUT pass still excludes non-world margins");
        Harness large(2048,1184);large.Frame();
        Check(large.stage.TextureBytes()<24*1024*1024,"large output keeps bounded logical structure buffers");
        // Explicit fixture timing, not live WGC/E2E performance evidence.
        auto start=std::chrono::steady_clock::now();for(int n=0;n<60;n++)large.Frame();
        auto result=Read(large.device.get(),large.context.get(),large.output.get());(void)result;
        double ms=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count()/60;
        std::printf("NightVision GPU fixture 2048x1184 mean submission+drain ms=%.3f bytes=%llu\n",ms,static_cast<unsigned long long>(large.stage.TextureBytes()));
        TextureTests();
        UnderlayTests();
        InstrumentTests();
        std::printf("NightVision GPU Tests Passed: %d\nNightVision GPU Tests Failed: %d\n",passed,failed);
        return failed?1:0;
    } catch(const winrt::hresult_error& e) {std::printf("D3D failure 0x%08lx\n",static_cast<unsigned long>(e.code().value));return 2;}
    catch(const std::exception& e){std::printf("Replay failure: %s\n",e.what());return 2;}
}
