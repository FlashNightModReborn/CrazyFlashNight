using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Runtime.InteropServices;
using System.Threading;
using CF7Launcher.Guardian.WorldCompositor;
using Newtonsoft.Json;
using Xunit;

namespace CF7Launcher.Tests.Guardian;

public sealed partial class OpaqueHudGpuTests
{
    [SharedWorldGpuFact(requireDisplayOn:true)]
    public void CasSourceCostAbbaAtLowResolution()
    {
        string dir=Path.GetFullPath(Environment.GetEnvironmentVariable("CF7_TEST_CAS_REPLAY_ROOT")
            ?? throw new InvalidOperationException("Explicit frozen replay root required."));
        var rows=new List<object>();
        Run((world,scene,output,source)=> {
            foreach(var target in new[]{(Name:"360L",Size:new Size(800,450)),(Name:"540L",Size:new Size(1200,675))}) {
                using var bitmap=new Bitmap(Path.Combine(dir,target.Name+"-source.png"));int marker=0;
                ((Window)source).FixturePaint=g=> {g.DrawImageUnscaled(bitmap,0,0);
                    if(marker!=0)g.FillRectangle(marker%2==0?Brushes.Red:Brushes.Lime,0,0,3,3);};
                world.HoldViewport();source.ClientSize=target.Size;
                world.Crop(new Rectangle(Point.Empty,target.Size));world.Viewport(new Rectangle(Point.Empty,target.Size),0);
                source.BringToFront();world.Postprocess(false,0,false);source.Refresh();
                Pump(()=> {source.Refresh();return world.Read().Width==(uint)target.Size.Width
                    && CapturedBitmapMatches(Grab(world,false),bitmap);},scene,"ABBA complete input");
                foreach(int stage in new[]{1,0,0,1}) {
                    world.Postprocess(true,stage==1?.27f:.05f,false,stage);
                    var warm=Stopwatch.StartNew();int i=0;
                    while(warm.ElapsedMilliseconds<600) {marker=++i;source.Refresh();ApplicationPump(scene);Thread.Sleep(17);}
                    world.SetHudCostSampling(true);var timer=Stopwatch.StartNew();
                    for(int frame=0;frame<120;frame++) {
                        marker=frame+1;source.Refresh();ApplicationPump(scene);
                        while(timer.Elapsed.TotalMilliseconds<(frame+1)*1000.0/30.0) {ApplicationPump(scene);Thread.Sleep(1);}
                    }
                    world.SetHudCostSampling(false);ApplicationPump(scene);var cost=world.ReadHudCost();
                    Assert.True(cost.Completed>=60);Assert.Equal(0ul,cost.Disjoint);Assert.Equal(0ul,cost.Errors);
                    rows.Add(new {target=target.Name,stage,cost,cas=world.ReadCasStage(),adapter=world.Read().Adapter});
                }
                world.Postprocess(false,0,false);((Window)source).FixturePaint=null;
            }
        },new Size(1600,900),TimeSpan.FromSeconds(100));
        File.WriteAllText(Path.Combine(dir,"gpu","costs-abba.json"),JsonConvert.SerializeObject(new {rows,
            source="frozen screenshot replay with 30 Hz marker",physicalScanoutVerified=false},Formatting.Indented));
    }

    [SharedWorldGpuFact(requireDisplayOn:true)]
    public void CasFrozenScreenshotComparisonAndGpuCosts()
    {
        string dir=Path.GetFullPath(Environment.GetEnvironmentVariable("CF7_TEST_CAS_REPLAY_ROOT")
            ?? throw new InvalidOperationException("Set CF7_TEST_CAS_REPLAY_ROOT to the frozen replay fixture directory."));
        string gpuDir=Path.Combine(dir,"gpu");Directory.CreateDirectory(gpuDir);
        var rows=new List<object>();
        Run((world,scene,output,source)=> {
            foreach(var target in new[]{(Name:"360L",Size:new Size(800,450)),(Name:"540L",Size:new Size(1200,675))}) {
                using var bitmap=new Bitmap(Path.Combine(dir,target.Name+"-source.png"));
                Assert.Equal(target.Size,bitmap.Size);
                int marker=0;
                ((Window)source).FixturePaint=g=> {
                    g.DrawImageUnscaled(bitmap,0,0);
                    if(marker!=0)g.FillRectangle(marker%2==0?Brushes.Red:Brushes.Lime,0,0,3,3);
                };
                world.HoldViewport();source.ClientSize=target.Size;
                world.Crop(new Rectangle(Point.Empty,target.Size));world.Viewport(new Rectangle(Point.Empty,target.Size),0);
                // GDI clips WM_PAINT against overlapping topmost windows. Keep
                // this owned source above our owned output before freezing it.
                source.BringToFront();world.Postprocess(false,0,false);source.Refresh();
                Pump(()=> {source.Refresh();return world.Read().Width==(uint)target.Size.Width
                    && world.Read().Height==(uint)target.Size.Height && world.ReadPostprocess().CasEnabled==0;},scene,"frozen source "+target.Name);
                var raw=Grab(world,false);
                Pump(()=> {source.Refresh();raw=Grab(world,false);
                    return CapturedBitmapMatches(raw,bitmap);},scene,"complete frozen bitmap "+target.Name);
                string frozenHash=Convert.ToHexString(SHA256.HashData(raw.Pixels));
                SavePostprocessFrame(raw,Path.Combine(gpuDir,target.Name+"-captured.png"));
                foreach(var mode in new[]{(Name:"off",Enabled:false,Strength:0f,Stage:0),
                        (Name:"previous",Enabled:true,Strength:.05f,Stage:0),
                        (Name:"strong-output",Enabled:true,Strength:.27f,Stage:0),
                        (Name:"source",Enabled:true,Strength:WorldPostprocessPolicy.CasStrength("LOW"),Stage:1),
                        (Name:"off-end",Enabled:false,Strength:0f,Stage:0)}) {
                    world.Postprocess(mode.Enabled,mode.Strength,false,mode.Stage);
                    uint expectedStage=mode.Enabled?(mode.Stage==1?(target.Name=="360L"?1u:2u):0u):0u;
                    Pump(()=>world.ReadPostprocess().CasEnabled==(mode.Enabled?1u:0u)
                        && world.ReadCasStage().AppliedStage==expectedStage,scene,"applied "+mode.Name);
                    var pixels=Grab(world);
                    string currentHash=Convert.ToHexString(SHA256.HashData(Grab(world,false).Pixels));
                    Assert.Equal(frozenHash,currentHash);
                    string file=target.Name+"-"+mode.Name+".png";
                    SavePostprocessFrame(pixels,Path.Combine(gpuDir,file));
                    int? maxReferenceError=null;
                    if(mode.Stage==1) {
                        float strength=world.ReadPostprocess().AppliedSharpness;
                        var sharpened=new Frame(CasReference(raw,strength),raw.Width,raw.Height);
                        byte[] expected=expectedStage==1?ResizeBilinearReference(sharpened,pixels.Width,pixels.Height)
                            :CasSourceNeighborhoodReference(raw,pixels.Width,pixels.Height,strength);
                        int max=0;
                        for(int p=0;p<pixels.Pixels.Length;p+=4)for(int c=0;c<3;c++)
                            max=Math.Max(max,Math.Abs(pixels.Pixels[p+c]-expected[p+c]));
                        Assert.InRange(max,0,2);maxReferenceError=max;
                        Assert.Equal(expectedStage==1?(ulong)(target.Size.Width*target.Size.Height*4):0ul,world.ReadCasStage().TextureBytes);
                    }
                    if(!mode.Enabled)Assert.Equal(0ul,world.ReadCasStage().TextureBytes);
                    Assert.Equal(0ul,world.ReadPostprocess().HistoryBytes);
                    Assert.Throws<InvalidOperationException>(()=>world.Postprocess(true,.27f,false,2));
                    var warm=Stopwatch.StartNew();int warmFrame=0;
                    while(warm.ElapsedMilliseconds<400) {marker=++warmFrame;source.Refresh();ApplicationPump(scene);Thread.Sleep(17);}
                    world.SetHudCostSampling(true);
                    var timer=Stopwatch.StartNew();
                    for(int frame=0;frame<75;frame++) {
                        marker=frame+1;source.Refresh();ApplicationPump(scene);
                        while(timer.Elapsed.TotalMilliseconds<(frame+1)*1000.0/30.0) {ApplicationPump(scene);Thread.Sleep(1);}
                    }
                    world.SetHudCostSampling(false);ApplicationPump(scene);
                    var cost=world.ReadHudCost();
                    Assert.True(cost.Completed>=25,"A cost comparison needs sustained completed GPU samples.");
                    Assert.Equal(0ul,cost.Disjoint);Assert.Equal(0ul,cost.Errors);
                    rows.Add(new {target=target.Name,mode=mode.Name,input=target.Size,output=output.ClientSize,file,
                        frozenHash,maxReferenceError,cost,postprocess=world.ReadPostprocess(),cas=world.ReadCasStage(),adapter=world.Read().Adapter});
                    marker=0;source.Refresh();
                    Pump(()=>Convert.ToHexString(SHA256.HashData(Grab(world,false).Pixels))==frozenHash,scene,"restore frozen input");
                }
                world.Postprocess(true,.27f,false,1);
                var tile=Tile(16,16,64,20,250,120,255);
                WithPixels(tile,p=>world.SetHudRaster(0,p,16,16,64,10,10));
                PixelsUntil(world,scene,f=>Pixel(f,12,12,20,250,120),"native HUD excluded from source CAS");
                for(int i=0;i<8;i++) {Grab(world);ApplicationPump(scene);}
                if(target.Name=="360L")Assert.True(world.ReadCasStage().CacheHits>0,"Duplicate presentations reuse source CAS.");
                world.SetHudRaster(0,IntPtr.Zero,0,0,0,0,0);
                world.Postprocess(false,0,false);
                Pump(()=>world.ReadCasStage().TextureBytes==0,scene,"source texture released");
                ((Window)source).FixturePaint=null;
            }
        },new Size(1600,900),TimeSpan.FromSeconds(140));
        File.WriteAllText(Path.Combine(gpuDir,"results.json"),JsonConvert.SerializeObject(new {
            source="frozen user screenshot resampled; not raw Flash capture",rows,
            gameplayExecuted=false,physicalScanoutVerified=false,
            candidate=Environment.GetEnvironmentVariable("CF7_TEST_SHARED_WORLD_CANDIDATE")},Formatting.Indented));
    }

    [SharedWorldGpuFact(requireDisplayOn:true)]
    public void CasHighAndMediumOutputPixelsStayCompatible()
    {
        string dir=Path.GetFullPath(Environment.GetEnvironmentVariable("CF7_TEST_CAS_REPLAY_ROOT")
            ?? throw new InvalidOperationException("Explicit replay root required."));
        Run((world,scene,output,source)=> {
            // H/M continue to use the existing output CAS at 1:1. Bind their
            // exact processed pixels to the independent arithmetic oracle.
            using var reference=new Bitmap(Path.Combine(dir,"360L-source.png"));
            ((Window)source).FixturePaint=g=>g.DrawImageUnscaled(reference,0,0);
            world.HoldViewport();output.ClientSize=reference.Size;source.ClientSize=reference.Size;source.BringToFront();
            world.Crop(new Rectangle(Point.Empty,source.ClientSize));world.Viewport(new Rectangle(Point.Empty,source.ClientSize),0);
            world.Postprocess(false,0,false);source.Refresh();
            Pump(()=> {source.Refresh();return world.Read().Width==(uint)reference.Width
                && CapturedBitmapMatches(Grab(world,false),reference);},scene,"H/M full input");
            var rawReference=Grab(world,false);
            foreach(string quality in new[]{"HIGH","MEDIUM"}) {
                world.Postprocess(true,WorldPostprocessPolicy.CasStrength(quality),false,WorldPostprocessPolicy.CasStage(quality));
                Pump(()=>world.ReadPostprocess().CasEnabled==1 && world.ReadCasStage().AppliedStage==0,scene,"H/M output CAS");
                byte[] expected=CasReference(rawReference,WorldPostprocessPolicy.CasStrength(quality));
                var processed=Grab(world);int max=0;
                for(int p=0;p<processed.Pixels.Length;p+=4)for(int c=0;c<3;c++)
                    max=Math.Max(max,Math.Abs(processed.Pixels[p+c]-expected[p+c]));
                Assert.InRange(max,0,2);Assert.Equal(0ul,world.ReadCasStage().TextureBytes);
            }
            world.Postprocess(false,0,false);((Window)source).FixturePaint=null;
        },new Size(800,450),TimeSpan.FromSeconds(30));
    }

    private static byte[] ResizeBilinearReference(Frame frame,int width,int height)
    {
        var output=new byte[width*height*4];
        for(int y=0;y<height;y++)for(int x=0;x<width;x++) {
            double sx=Math.Clamp((x+.5)*frame.Width/width-.5,0,frame.Width-1);
            double sy=Math.Clamp((y+.5)*frame.Height/height-.5,0,frame.Height-1);
            int ax=(int)sx,ay=(int)sy,bx=Math.Min(ax+1,frame.Width-1),by=Math.Min(ay+1,frame.Height-1);
            double tx=sx-ax,ty=sy-ay;int at=(y*width+x)*4;
            for(int c=0;c<3;c++) {
                double a=frame.Pixels[(ay*frame.Width+ax)*4+c]*(1-tx)+frame.Pixels[(ay*frame.Width+bx)*4+c]*tx;
                double b=frame.Pixels[(by*frame.Width+ax)*4+c]*(1-tx)+frame.Pixels[(by*frame.Width+bx)*4+c]*tx;
                output[at+c]=(byte)Math.Clamp((int)Math.Round(a*(1-ty)+b*ty),0,255);
            }
            output[at+3]=255;
        }
        return output;
    }

    private static byte[] CasSourceNeighborhoodReference(Frame frame,int width,int height,float strength)
    {
        var output=new byte[width*height*4];var samples=new float[15];
        int[] dx={0,-1,0,1,0},dy={-1,0,0,0,1};float peak=-1/(8-3*strength);
        for(int y=0;y<height;y++)for(int x=0;x<width;x++) {
            double sx=(x+.5)*frame.Width/width-.5,sy=(y+.5)*frame.Height/height-.5;
            float mn=1,mx=0;
            for(int n=0;n<5;n++) {
                double px=Math.Clamp(sx+dx[n],0,frame.Width-1),py=Math.Clamp(sy+dy[n],0,frame.Height-1);
                int ax=(int)px,ay=(int)py,bx=Math.Min(ax+1,frame.Width-1),by=Math.Min(ay+1,frame.Height-1);
                double tx=px-ax,ty=py-ay;
                for(int c=0;c<3;c++) {
                    double a=frame.Pixels[(ay*frame.Width+ax)*4+c]*(1-tx)+frame.Pixels[(ay*frame.Width+bx)*4+c]*tx;
                    double b=frame.Pixels[(by*frame.Width+ax)*4+c]*(1-tx)+frame.Pixels[(by*frame.Width+bx)*4+c]*tx;
                    float v=(float)((a*(1-ty)+b*ty)/255);samples[n*3+c]=v*v;
                }
                mn=Math.Min(mn,samples[n*3+1]);mx=Math.Max(mx,samples[n*3+1]);
            }
            float w=(float)Math.Sqrt(Math.Clamp(Math.Min(mn,1-mx)/Math.Max(mx,1e-6f),0,1))*peak;
            int at=(y*width+x)*4;
            for(int c=0;c<3;c++) {
                float sum=samples[6+c]+w*(samples[c]+samples[3+c]+samples[9+c]+samples[12+c]);
                output[at+c]=(byte)Math.Clamp((int)Math.Round(Math.Sqrt(Math.Clamp(sum/(1+4*w),0,1))*255),0,255);
            }
            output[at+3]=255;
        }
        return output;
    }

    private static bool CapturedBitmapMatches(Frame frame,Bitmap bitmap)
    {
        if(frame.Width!=bitmap.Width || frame.Height!=bitmap.Height)return false;
        foreach(var point in new[]{new Point(40,40),new Point(bitmap.Width/2,bitmap.Height/2),
                new Point(bitmap.Width-40,bitmap.Height-40),new Point(40,bitmap.Height-40)}) {
            Color color=bitmap.GetPixel(point.X,point.Y);int at=(point.Y*frame.Width+point.X)*4;
            if(Math.Abs(frame.Pixels[at]-color.B)>1 || Math.Abs(frame.Pixels[at+1]-color.G)>1
                    || Math.Abs(frame.Pixels[at+2]-color.R)>1)return false;
        }
        // A resize can expose only a narrow stale strip while all sampled
        // points already match. Require the entire RGB input before freezing.
        var data=bitmap.LockBits(new Rectangle(0,0,bitmap.Width,bitmap.Height),ImageLockMode.ReadOnly,PixelFormat.Format32bppArgb);
        try {
            var row=new byte[bitmap.Width*4];
            for(int y=0;y<bitmap.Height;y++) {
                Marshal.Copy(data.Scan0+y*data.Stride,row,0,row.Length);int offset=y*row.Length;
                for(int x=0;x<row.Length;x+=4)for(int c=0;c<3;c++)
                    if(frame.Pixels[offset+x+c]!=row[x+c])return false;
            }
        } finally {bitmap.UnlockBits(data);}
        return true;
    }
}
