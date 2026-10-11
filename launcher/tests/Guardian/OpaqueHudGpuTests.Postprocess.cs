using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading;
using CF7Launcher.Guardian.WorldCompositor;
using Newtonsoft.Json;
using Xunit;

namespace CF7Launcher.Tests.Guardian;

public sealed partial class OpaqueHudGpuTests
{
    [SharedWorldGpuFact(requireDisplayOn:true)]
    public void PostprocessGpuCostsAt1080p()
    {
        string root=Path.GetFullPath(Path.Combine(AppContext.BaseDirectory,"..","..","..",".."));
        string dir=Path.Combine(root,"tmp","world-postprocess","gpu");Directory.CreateDirectory(dir);
        var rows=new List<object>();
        Run((world,scene,output,source)=> {
            foreach(int mode in new[]{0,1,2,0}) {
                world.Postprocess(mode!=0,.25f,mode==2);world.SetHudCostSampling(true);
                var clock=Stopwatch.StartNew();
                for(int frame=0;frame<60;frame++) {
                    source.BackColor=Color.FromArgb(90+(frame%30),150,170);source.Refresh();ApplicationPump(scene);
                    while(clock.Elapsed.TotalMilliseconds<(frame+1)*1000.0/30.0) {ApplicationPump(scene);Thread.Sleep(1);}
                }
                world.SetHudCostSampling(false);ApplicationPump(scene);
                var costs=world.ReadHudCost();Assert.True(costs.Completed>0);
                rows.Add(new {mode,output=output.ClientSize,costs,postprocess=world.ReadPostprocess(),adapter=world.Read().Adapter});
            }
        },new Size(1920,1080),TimeSpan.FromSeconds(50));
        File.WriteAllText(Path.Combine(dir,"costs-1080p.json"),JsonConvert.SerializeObject(new {
            rows,source="owned-window",gameplayExecuted=false,physicalScanoutVerified=false},Formatting.Indented));
    }

    [SharedWorldGpuFact(requireDisplayOn:true)]
    public void PostprocessPixelsHistoryLifecycleAndGpuCosts()
    {
        string root=Path.GetFullPath(Path.Combine(AppContext.BaseDirectory,"..","..","..",".."));
        string dir=Path.Combine(root,"tmp","world-postprocess","gpu");Directory.CreateDirectory(dir);
        var rows=new List<object>();
        Run((world,scene,output,source)=> {
            int marker=0;
            ((Window)source).FixturePaint=g=> {
                g.ScaleTransform(source.ClientSize.Width/960f,source.ClientSize.Height/540f);
                using var gradient=new LinearGradientBrush(new Rectangle(0,0,960,540),Color.FromArgb(90,120,160),Color.FromArgb(180,210,140),20);
                g.FillRectangle(gradient,0,0,960,540);
                g.SmoothingMode=SmoothingMode.AntiAlias;
                using var pen=new Pen(Color.FromArgb(60,85,105),1.5f);
                for(int x=80;x<920;x+=67)g.DrawLine(pen,x,70,x+110,470);
                g.DrawEllipse(pen,405,195,150,150);
                using var font=new Font("Arial",16,FontStyle.Bold);
                g.DrawString("WORLD  H / M / L   0123456789",font,Brushes.White,80,20);
                g.FillRectangle(Brushes.OrangeRed,60+marker,460,24,30);
            };
            ulong received=world.Read().Received;
            source.Refresh();
            Pump(()=>world.Read().Received>received,scene,"fresh pattern capture");
            world.Postprocess(false,0,false);
            Pump(()=>world.ReadPostprocess().CasEnabled==0,scene,"CAS off");
            var baseline=Grab(world);SavePostprocessFrame(baseline,Path.Combine(dir,"off.png"));
            var input=Grab(world,false);
            Assert.Equal(input.Width,baseline.Width);Assert.Equal(input.Height,baseline.Height);
            foreach(string quality in new[]{"HIGH","MEDIUM","LOW"}) {
                float strength=WorldPostprocessPolicy.CasStrength(quality);
                world.Postprocess(true,strength,false);
                Pump(()=>world.ReadPostprocess().CasEnabled==1 && Math.Abs(world.ReadPostprocess().AppliedSharpness-strength)<.001,
                    scene,"CAS "+quality);
                var frame=Grab(world);SavePostprocessFrame(frame,Path.Combine(dir,"cas-"+quality.ToLowerInvariant()+".png"));
                var expected=CasReference(input,strength);
                int max=0;long squared=0;int changed=0;
                for(int p=0;p<frame.Pixels.Length;p+=4)for(int c=0;c<3;c++) {
                    max=Math.Max(max,Math.Abs(frame.Pixels[p+c]-expected[p+c]));
                    int delta=frame.Pixels[p+c]-baseline.Pixels[p+c];squared+=(long)delta*delta;if(delta!=0)changed++;
                }
                Assert.InRange(max,0,2);Assert.True(changed>0,"CAS must actually process pixels at 1:1.");
                rows.Add(new {kind="pixel-oracle",quality,strength,maxByteError=max,changed,
                    baselineMse=squared/(frame.Width*frame.Height*3.0),note="MSE is difference, not an artistic quality score"});
            }
            Assert.Throws<InvalidOperationException>(()=>world.Postprocess(true,float.NaN,false));
            world.Postprocess(false,0,false);
            PixelsUntil(world,scene,f=>f.Pixels.SequenceEqual(baseline.Pixels),"true CAS bypass");
            foreach(var target in new[]{(Quality:"HIGH",Size:new Size(960,540)),
                    (Quality:"MEDIUM",Size:new Size(720,405)),(Quality:"LOW",Size:new Size(480,270))}) {
                world.HoldViewport();source.ClientSize=target.Size;source.Refresh();
                world.Crop(new Rectangle(Point.Empty,target.Size));
                world.Viewport(new Rectangle(Point.Empty,target.Size),0);
                world.Postprocess(true,WorldPostprocessPolicy.CasStrength(target.Quality),false);
                Pump(()=> {source.Refresh();return world.Read().Width==(uint)target.Size.Width && world.ReadPostprocess().CasEnabled==1;},
                    scene,"actual scale "+target.Quality);
                SavePostprocessFrame(Grab(world),Path.Combine(dir,"scaled-"+target.Quality.ToLowerInvariant()+".png"));
                var applied=world.ReadPostprocess();
                Assert.InRange(applied.InputScale,output.Width/(float)target.Size.Width-.01f,output.Width/(float)target.Size.Width+.01f);
                rows.Add(new {kind="scaled-input",quality=target.Quality,input=target.Size,output=output.ClientSize,applied});
            }
            world.HoldViewport();source.ClientSize=output.ClientSize;source.Refresh();
            world.Crop(new Rectangle(Point.Empty,source.ClientSize));world.Viewport(new Rectangle(Point.Empty,output.ClientSize),0);
            world.Postprocess(false,0,true);
            marker=100;source.Refresh();
            Pump(()=>world.ReadPostprocess().HistoryValid==1,scene,"feedback history");
            Assert.True(world.ReadPostprocess().HistoryBytes>0);
            bool sawHistoryPixels=false;
            for(int frame=0;frame<18;frame++) {
                marker=frame%2==0?40:100;source.Refresh();
                var raw=Grab(world,false);var blended=Grab(world);
                int different=0;
                for(int p=0;p<raw.Pixels.Length;p+=4)
                    if(Math.Abs(raw.Pixels[p]-blended.Pixels[p])>2
                        || Math.Abs(raw.Pixels[p+1]-blended.Pixels[p+1])>2
                        || Math.Abs(raw.Pixels[p+2]-blended.Pixels[p+2])>2)different++;
                if(different>0)sawHistoryPixels=true;
                SavePostprocessFrame(blended,Path.Combine(dir,"feedback-"+frame.ToString("D3")+".png"));
            }
            Assert.True(sawHistoryPixels,"Feedback must change moving world pixels, not only allocate a buffer.");
            world.ResetFeedback();marker=200;source.Refresh();
            Pump(()=>world.ReadPostprocess().HistoryResets>0,scene,"explicit scene reset");
            world.Postprocess(false,0,false);
            Pump(()=>world.ReadPostprocess().HistoryBytes==0 && world.ReadPostprocess().FeedbackEnabled==0,scene,"history released");
            foreach(int mode in new[]{0,1,2,0}) {
                world.Postprocess(mode!=0,.25f,mode==2);
                world.SetHudCostSampling(true);
                var clock=Stopwatch.StartNew();
                for(int frame=0;frame<90;frame++) {
                    marker=frame%240;source.Refresh();ApplicationPump(scene);
                    while(clock.Elapsed.TotalMilliseconds<(frame+1)*1000.0/30.0) {ApplicationPump(scene);Thread.Sleep(1);}
                }
                world.SetHudCostSampling(false);ApplicationPump(scene);
                var costs=world.ReadHudCost();Assert.True(costs.Completed>0);
                rows.Add(new {kind="gpu-cost",mode,output=output.ClientSize,costs,
                    postprocess=world.ReadPostprocess(),timing=world.ReadTiming(),adapter=world.Read().Adapter,syntheticSource=true});
            }
            // Opaque native HUD stays outside both effects.
            var tile=Tile(16,16,64,20,250,120,255);
            WithPixels(tile,p=>world.SetHudRaster(0,p,16,16,64,10,10));
            world.Postprocess(true,.25f,true);marker=30;source.Refresh();
            PixelsUntil(world,scene,f=>Pixel(f,12,12,20,250,120),"HUD excluded from CAS and feedback");
            world.SetHudRaster(0,IntPtr.Zero,0,0,0,0,0);
            world.Postprocess(false,0,false);
            File.WriteAllText(Path.Combine(dir,"results.json"),JsonConvert.SerializeObject(new {
                fixture="owned-window-postprocess",rows,gameplayExecuted=false,physicalScanoutVerified=false,
                candidate=Environment.GetEnvironmentVariable("CF7_TEST_SHARED_WORLD_CANDIDATE")},Formatting.Indented));
        },new Size(960,540),TimeSpan.FromSeconds(90));
    }

    private static void ApplicationPump(CompositionSceneHost scene) {System.Windows.Forms.Application.DoEvents();scene.Commit();}
    private static byte[] CasReference(Frame frame,float strength)
    {
        var output=new byte[frame.Pixels.Length];float peak=-1/(8-3*strength);
        for(int y=0;y<frame.Height;y++)for(int x=0;x<frame.Width;x++) {
            int[] points={((Math.Max(0,y-1))*frame.Width+x)*4,
                (y*frame.Width+Math.Max(0,x-1))*4,(y*frame.Width+x)*4,
                (y*frame.Width+Math.Min(frame.Width-1,x+1))*4,
                (Math.Min(frame.Height-1,y+1)*frame.Width+x)*4};
            float mn=1,mx=0;
            foreach(int p in points) {float g=frame.Pixels[p+1]/255f;g*=g;mn=Math.Min(mn,g);mx=Math.Max(mx,g);}
            float w=(float)Math.Sqrt(Math.Clamp(Math.Min(mn,1-mx)/Math.Max(mx,1e-6f),0,1))*peak;
            int at=(y*frame.Width+x)*4;
            for(int c=0;c<3;c++) {
                float sum=0;for(int i=0;i<5;i++) {float v=frame.Pixels[points[i]+c]/255f;sum+=v*v*(i==2?1:w);}
                output[at+c]=(byte)Math.Clamp((int)Math.Round(Math.Sqrt(Math.Clamp(sum/(1+4*w),0,1))*255),0,255);
            }
            output[at+3]=255;
        }
        return output;
    }
    private static void SavePostprocessFrame(Frame frame,string path)
    {
        using var bitmap=new Bitmap(frame.Width,frame.Height,PixelFormat.Format32bppArgb);
        var data=bitmap.LockBits(new Rectangle(0,0,frame.Width,frame.Height),ImageLockMode.WriteOnly,PixelFormat.Format32bppArgb);
        try {for(int y=0;y<frame.Height;y++)Marshal.Copy(frame.Pixels,y*frame.Width*4,data.Scan0+y*data.Stride,frame.Width*4);}
        finally {bitmap.UnlockBits(data);}
        bitmap.Save(path,ImageFormat.Png);
    }
}
