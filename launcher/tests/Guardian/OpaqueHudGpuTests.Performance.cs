using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Threading;
using System.Windows.Forms;
using CF7Launcher.Guardian.Hud;
using CF7Launcher.Guardian.Hud.PlayerInfo;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian;

public sealed partial class OpaqueHudGpuTests
{
    [SharedWorldGpuFact(requireDisplayOn:true)]
    public void CompareLegacyAndOpaqueWithCapturedPlayerInfoRasters()=>CompareCapturedRasters(false);
    [SharedWorldGpuFact(requireDisplayOn:true)]
    public void CompareLegacyAndOpaqueWithCapturedMainHudRasters()=>CompareCapturedRasters(true);
    private static void CompareCapturedRasters(bool mainHud)
    {
        string root=Path.GetFullPath(Path.Combine(AppContext.BaseDirectory,"..","..","..",".."));
        string directory=Path.Combine(root,"tmp",mainHud?"hud-main-unit":"hud-opaque-pilot");
        string fixture=mainHud?Path.Combine(directory,"rasters.json"):Path.Combine(directory,"player-info-rasters","rasters.json");
        Assert.True(File.Exists(fixture),"Run the complete-unit GPU pixel fixture first.");
        var document=JObject.Parse(File.ReadAllText(fixture));
        var layers=document["layers"].ToObject<Raster[]>();Assert.Equal(mainHud?4:3,layers.Length);
        int width=(int)document["width"],height=(int)document["height"];
        var expected=ComposeRasters(width,height,layers);
        var withoutResources=ComposeRasters(width,height,layers[0],layers[2]);
        Point check=mainHud?StrongestLayerPixel(expected,ComposeRasters(width,height,layers.Take(3).ToArray()),width):StrongestMpPixel(expected,withoutResources,width);
        string prefix=mainHud?"main-hud":"player-info";
        string phasePath=Path.Combine(directory,prefix+"-perf-phase.json");
        var rows=new List<object>();
        try
        {
            Run((world,scene,output,source)=>
            {
                var windows=layers.Select(_=>new LegacyResource(output){TopMost=true}).ToArray();
                var dibs=layers.Select(layer=>new PlayerInfoLayeredDibSurface(layer.Width,layer.Height)).ToArray();
                try
                {
                    for(int i=0;i<layers.Length;i++)Marshal.Copy(layers[i].Pixels,0,dibs[i].Pixels,layers[i].Pixels.Length);
                    int[] slots={2,1,3,4};
                    foreach(bool animate in new[]{false,true})
                    foreach(bool opaque in new[]{false,true,true,false})
                    {
                        for(int layer=0;layer<5;layer++)world.SetHudRaster(layer,IntPtr.Zero,0,0,0,0,0);
                        foreach(var window in windows)window.Clear();
                        // Hiding an owned topmost window can reorder its owner against
                        // the source window. Restore the passive output before sampling.
                        Assert.True(SetWindowPos(output.Handle,new IntPtr(-1),0,0,0,0,0x13));
                        int phase=rows.Count;
                        void Mark(string status)=>File.WriteAllText(phasePath,JsonConvert.SerializeObject(new {
                            status,phase,opaque,animate,pid=Environment.ProcessId,utc=DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()}));
                        Mark("warming");
                        using var process=Process.GetCurrentProcess();var clock=Stopwatch.StartNew();
                        TimeSpan cpuStart=default;double measureStart=0;ulong presentStart=0;
                        var submissions=new List<double>();var presents=new List<double>();
                        for(int frame=0;frame<240;frame++)
                        {
                            if(frame==60)
                            {
                                using var pixel=new Bitmap(1,1);
                                using(var graphics=Graphics.FromImage(pixel))graphics.CopyFromScreen(output.PointToScreen(check),Point.Empty,new Size(1,1));
                                var color=pixel.GetPixel(0,0);int p=(check.Y*width+check.X)*4;
                                var backbuffer=Grab(world);
                                Console.WriteLine(JsonConvert.SerializeObject(new {phase,opaque,check,color,
                                    screenWindow=WindowFromPoint(output.PointToScreen(check)).ToInt64(),sourceWindow=source.Handle.ToInt64(),outputWindow=output.Handle.ToInt64(),
                                    backbufferRgb=backbuffer.Pixels.Skip(p).Take(3),hud=world.ReadHudRaster()}));
                                Assert.InRange((int)color.B,expected[p]-2,expected[p]+2);
                                Assert.InRange((int)color.G,expected[p+1]-2,expected[p+1]+2);
                                Assert.InRange((int)color.R,expected[p+2]-2,expected[p+2]+2);
                                Mark("measuring");cpuStart=process.TotalProcessorTime;measureStart=clock.Elapsed.TotalSeconds;presentStart=world.Read().Presented;
                            }
                            source.BackColor=Color.FromArgb(30+(frame&1),80,140);
                            if(animate)
                            {
                                // A small visible change exercises dirty submission without
                                // adding a different painter workload to one backend.
                                int offset=(Math.Min(60,layers[0].Height-1)*layers[0].Width+Math.Min(900,layers[0].Width-1))*4;
                                Marshal.WriteInt32(dibs[0].Pixels,offset,unchecked((int)(0xFF1A1814u+(uint)(frame&1))));
                            }
                            for(int i=0;i<layers.Length;i++)
                            {
                                if(frame!=0 && (!animate || (i==2 && frame%6!=0)))continue;
                                var layer=layers[i];var dib=dibs[i];
                                // Main-HUD comparison keeps the already migrated PlayerInfo
                                // native in both branches: measure only the incremental move.
                                if(!opaque && (!mainHud || i==3))windows[i].Submit(dib,output.PointToScreen(new Point(layer.X,layer.Y)),bitmapPath:i!=1);
                                else if(i==1)world.SetHudRaster(slots[i],dib.Pixels,layer.Width,layer.Height,layer.Width*4,layer.X,layer.Y);
                                else
                                {
                                    var locked=dib.Bitmap.LockBits(new Rectangle(Point.Empty,dib.Bitmap.Size),ImageLockMode.ReadOnly,PixelFormat.Format32bppPArgb);
                                    try {world.SetHudRaster(slots[i],locked.Scan0,layer.Width,layer.Height,locked.Stride,layer.X,layer.Y);}
                                    finally {dib.Bitmap.UnlockBits(locked);}
                                }
                            }
                            Application.DoEvents();scene.Commit();
                            if(frame>=60) {var sample=world.Read();submissions.Add(sample.SubmitMs);presents.Add(sample.PresentMs);}
                            while(clock.Elapsed.TotalMilliseconds<(frame+1)*1000.0/30.0) {Application.DoEvents();Thread.Sleep(1);}
                        }
                        double seconds=clock.Elapsed.TotalSeconds-measureStart;
                        var stats=world.Read();Assert.True(stats.Presented>presentStart);
                        var row=new {phase,opaque,animate,seconds,cpuCorePercent=(process.TotalProcessorTime-cpuStart).TotalSeconds/seconds*100,
                            nativePresents=stats.Presented-presentStart,sampledSubmitP95Ms=Percentile(submissions),sampledPresentCallP95Ms=Percentile(presents),hud=world.ReadHudRaster()};
                        rows.Add(row);Console.WriteLine(JsonConvert.SerializeObject(row));
                    }
                    Assert.Equal(1,DisplayPowerObservation.ReadSessionState());
                }
                finally {foreach(var window in windows)window.Dispose();foreach(var dib in dibs)dib.Dispose();}
            },new Size(width,height),TimeSpan.FromSeconds(110));
            File.WriteAllText(Path.Combine(directory,prefix+"-perf-comparison.json"),JsonConvert.SerializeObject(new {
                fixture="captured-"+prefix+"-rasters-abba",candidate=Environment.GetEnvironmentVariable("CF7_TEST_SHARED_WORLD_CANDIDATE"),
                rasterSha256=Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(fixture))),rows,width,height,
                sourceHz=30,bottomAndResourceHz=30,buffHz=5,mainHudHz=mainHud?30:0,incrementalMainHudOnly=mainHud,
                includesLivePaintCost=false,gameplayExecuted=false},Formatting.Indented));
        }
        finally {File.WriteAllText(phasePath,JsonConvert.SerializeObject(new {status="finished",pid=Environment.ProcessId}));}
    }
    private static Point StrongestLayerPixel(byte[] complete,byte[] withoutLayer,int width)
    {
        int best=0,index=0;
        for(int p=0;p<complete.Length;p+=4)
        {
            int difference=0;for(int c=0;c<3;c++)difference+=Math.Abs(complete[p+c]-withoutLayer[p+c]);
            if(difference>best) {best=difference;index=p/4;}
        }
        Assert.True(best>0,"The checked pixel must distinguish the main HUD from PlayerInfo/world.");
        return new Point(index%width,index/width);
    }
    private static Point StrongestMpPixel(byte[] complete,byte[] noResources,int width)
    {
        var mp=PlayerHudResourceLayout.MpBar;int greatest=0;Point result=default;
        for(int y=(int)Math.Floor(mp.Top);y<Math.Ceiling(mp.Bottom);y++)
        for(int x=(int)Math.Floor(mp.Left);x<Math.Ceiling(mp.Right);x++)
        {
            int p=(y*width+x)*4,difference=0;
            for(int channel=0;channel<3;channel++)difference+=Math.Abs(complete[p+channel]-noResources[p+channel]);
            if(difference>greatest) {greatest=difference;result=new Point(x,y);}
        }
        Assert.True(greatest>0,"MP visibility probe must distinguish the resource layer from the bottom.");return result;
    }
    [DllImport("user32.dll",SetLastError=true)] private static extern bool SetWindowPos(IntPtr window,IntPtr after,int x,int y,int width,int height,uint flags);
    [DllImport("user32.dll")] private static extern IntPtr WindowFromPoint(Point point);
}
