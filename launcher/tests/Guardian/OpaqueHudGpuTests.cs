using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using System.Runtime.ExceptionServices;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Threading;
using System.Windows.Forms;
using CF7Launcher.Guardian.WorldCompositor;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.Hud;
using CF7Launcher.Guardian.Hud.PlayerInfo;
using CF7Launcher.Tests.Guardian.Hud.PlayerInfo;
using CF7Launcher.Fonts;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed partial class OpaqueHudGpuTests
    {
        private sealed class Window : Form
        {
            protected override bool ShowWithoutActivation => true;
            internal Size? PaintedViewport;
            protected override void OnPaint(PaintEventArgs e)
            {
                base.OnPaint(e);
                if(PaintedViewport is not { } size)return;
                e.Graphics.Clear(Color.Black);
                using var background=new SolidBrush(BackColor);
                e.Graphics.FillRectangle(background,0,0,size.Width,size.Height);
                e.Graphics.FillRectangle(Brushes.Red,size.Width*3/4,0,size.Width-size.Width*3/4,size.Height/2);
                e.Graphics.FillRectangle(Brushes.Lime,size.Width*3/4,size.Height/2,size.Width-size.Width*3/4,size.Height-size.Height/2);
            }
        }
        private sealed record Raster(byte[] Pixels,int Width,int Height,int X,int Y);
        private sealed class CommitCount : ILayeredWindowCommitObserver
        {
            internal int Count;
            public void OnCommit(LayeredWindowCommitResult result) { Count++; }
        }
        private sealed class RecordedScene : IWorldRasterScene
        {
            private readonly IWorldRasterScene _next;
            internal Raster Current;
            internal RecordedScene(IWorldRasterScene next) => _next=next;
            public void UploadHud(IntPtr pixels,int width,int height,int stride,int x,int y)
            {
                var copy=new byte[width*height*4];
                for(int row=0;row<height;row++)Marshal.Copy(IntPtr.Add(pixels,row*stride),copy,row*width*4,width*4);
                _next.UploadHud(pixels,width,height,stride,x,y);
                Current=new Raster(copy,width,height,x,y);
            }
            public void ClearHud(IntPtr transparent) { _next.ClearHud(transparent);Current=null; }
        }
        [SharedWorldGpuFact(requireDisplayOn:true)]
        public void RealPlayerInfoUnitPreservesMpAndBuffPixelsAndRetiresAllThreeLegacyDisplays()
        {
            Run((world,scene,output,source)=>
            {
                string root=Path.GetFullPath(Path.Combine(AppContext.BaseDirectory,"..","..","..",".."));
                RuntimeFontCatalog.Configure(root);
                Control anchor=output;
                using var commands=new PlayerHudController(_=>true,()=>true,a=>a());
                var state=PlayerHudStateTests.Full();
                // Frozen real state makes the CPU alpha oracle and GPU frame comparable.
                // This is not an animation/physical-input qualification.
                state["groups"]["vitals"]["hp"]=new JArray(0,1000);
                state["groups"]["vitals"]["paused"]=true;
                commands.TakeUiData("pi:"+PlayerHudStateTests.Encode(state));
                using var resources=PlayerInfoSplitSurface.CreateLive(output,anchor,commands.State);
                using var main=new NativeHudOverlay(output,anchor);
                using var coordinator=new WorldCompositorController(output,anchor,()=>IntPtr.Zero,()=>false,_=>{},root,()=>false,_=>{},()=>{});
                using var runtime=new PlayerHudRuntime(output,anchor,resources,commands,Path.Combine(root,"launcher","web","icons"),main);
                var legacyCommits=new CommitCount();
                foreach(var surface in runtime.PresentationSurfaces)surface.SetCommitObserver(legacyCommits);
                var bottom=new RecordedScene(new OpaqueHudRasterScene(world,2));
                var resource=new RecordedScene(new OpaqueHudRasterScene(world,1));
                var buffs=new RecordedScene(new OpaqueHudRasterScene(world,3));
                var bounds=new Rectangle(output.PointToScreen(Point.Empty),output.ClientSize);
                coordinator.ResourcePresentation.Adopt(resource,bounds,true);
                coordinator.BottomPresentation.Adopt(bottom,bounds,true);
                coordinator.BuffPresentation.Adopt(buffs,bounds,true);
                runtime.SetSharedWorld(coordinator);runtime.SetReady();
                Pump(()=>bottom.Current!=null && resource.Current!=null && buffs.Current!=null,scene,"real HUD rasters");
                var expected=ComposeRasters(1024,576,bottom.Current,resource.Current,buffs.Current);
                var frame=PixelsUntil(world,scene,p=>SamePixels(p,expected),"complete production HUD alpha/order");
                Assert.Equal(3u,world.ReadHudRaster().VisibleLayers);
                Assert.All(runtime.PresentationSurfaces,surface=>Assert.False(surface.Visible));
                Assert.Equal(0,resources.Counters.CommitCount);
                Assert.Equal(0,legacyCommits.Count);
                var noResources=ComposeRasters(1024,576,bottom.Current,buffs.Current);
                var mp=PlayerHudResourceLayout.MpBar;
                int mpPixels=0;
                for(int y=(int)Math.Floor(mp.Top);y<Math.Ceiling(mp.Bottom);y++)
                for(int x=(int)Math.Floor(mp.Left);x<Math.Ceiling(mp.Right);x++)
                {
                    int index=(y*1024+x)*4;
                    if(!expected.Skip(index).Take(3).SequenceEqual(noResources.Skip(index).Take(3)))mpPixels++;
                }
                // The exact centre can lie in a gap between MP cells. Check the
                // authored bar region and reject the actual reversed-order image.
                Console.WriteLine(JsonConvert.SerializeObject(new {mp,mpPixels,resourceBounds=new {resource.Current.X,resource.Current.Y,resource.Current.Width,resource.Current.Height}}));
                Assert.True(mpPixels>0,"MP ink must remain visible above the opaque bottom.");
                Assert.False(SamePixels(frame,ComposeRasters(1024,576,resource.Current,bottom.Current,buffs.Current)),"Reversing bottom/resources must fail the pixel oracle.");
                string evidence=Path.Combine(root,"tmp","hud-opaque-pilot","player-info-rasters");
                Directory.CreateDirectory(evidence);
                File.WriteAllText(Path.Combine(evidence,"rasters.json"),JsonConvert.SerializeObject(new {
                    candidate=Environment.GetEnvironmentVariable("CF7_TEST_SHARED_WORLD_CANDIDATE"),
                    width=1024,height=576,layers=new[]{bottom.Current,resource.Current,buffs.Current}},Formatting.Indented));
                ulong resourceUploads=coordinator.ResourcePresentation.Uploads;
                state["seq"]=2;state["groups"]["buffs"]=new JArray();
                commands.TakeUiData("pi:"+PlayerHudStateTests.Encode(state));
                Pump(()=>world.ReadHudRaster().VisibleLayers==2,scene,"empty Buff retirement");
                Assert.Null(buffs.Current);Assert.Equal(resourceUploads,coordinator.ResourcePresentation.Uploads);
                runtime.Suspend();
                Pump(()=>world.ReadHudRaster().VisibleLayers==0,scene,"whole HUD suspension");
                Assert.All(runtime.PresentationSurfaces,surface=>Assert.False(surface.Visible));
                runtime.Resume();
                Pump(()=>world.ReadHudRaster().VisibleLayers==2,scene,"whole HUD resume");
                expected=ComposeRasters(1024,576,bottom.Current,resource.Current);
                PixelsUntil(world,scene,p=>SamePixels(p,expected),"resumed MP and bottom");
                // One unavailable member retires the whole group, never resources alone.
                coordinator.BuffPresentation.Adopt(null,Rectangle.Empty,false);
                Pump(()=>world.ReadHudRaster().VisibleLayers==0 && resources.Counters.CommitCount>0,scene,"group fallback");
                coordinator.BuffPresentation.Adopt(buffs,bounds,true);
                Pump(()=>world.ReadHudRaster().VisibleLayers==2,scene,"group re-adoption");
                Assert.All(runtime.PresentationSurfaces,surface=>Assert.False(surface.Visible));
                Console.WriteLine(JsonConvert.SerializeObject(new {phase="player_hud_complete_unit",stats=world.ReadHudRaster(),
                    fullUnitLayers=3,afterBuffRemoval=2,afterSuspension=0,
                    exactRgbTolerance=2,mpAboveBottom=true,allThreeLegacyDisplaysHidden=true,gameplayExecuted=false,physicalInputVerified=false}));
                resources.BeginShutdown().GetAwaiter().GetResult();
            },new Size(1024,576));
        }
        private static byte[] ComposeRasters(int width,int height,params Raster[] rasters)
        {
            var pixels=Tile(width,height,width*4,140,80,30,255);
            foreach(var raster in rasters)
                for(int y=0;y<raster.Height;y++)for(int x=0;x<raster.Width;x++)
                {
                    int dx=x+raster.X,dy=y+raster.Y;if(dx<0||dy<0||dx>=width||dy>=height)continue;
                    int source=(y*raster.Width+x)*4,target=(dy*width+dx)*4,alpha=raster.Pixels[source+3];
                    for(int channel=0;channel<3;channel++)pixels[target+channel]=(byte)Math.Min(255,raster.Pixels[source+channel]+(pixels[target+channel]*(255-alpha)+127)/255);
                }
            return pixels;
        }
        private static bool SamePixels(Frame actual,byte[] expected)
        {
            if(actual.Pixels.Length!=expected.Length)return false;
            for(int i=0;i<expected.Length;i++)if(Math.Abs(actual.Pixels[i]-expected[i])>2)return false;
            return true;
        }
        [SharedWorldGpuFact(requireDisplayOn:true)]
        public void TwoLayersShareOpaqueBackbufferWithOwnedPixelsAndIndependentRetirement()
        {
            Run((world,scene,output,source) =>
            {
                Assert.Equal(48,Marshal.SizeOf<NativeCompositorSession.HudRasterStats>());
                byte[] red=Tile(24,16,128,0,0,128,128);
                byte[] green=Tile(10,6,48,0,220,0,255);
                using var damage=new WorldRasterPresentation();
                using var resources=new WorldRasterPresentation();
                damage.Faulted+=error=>throw new InvalidOperationException("damage upload",error);
                resources.Faulted+=error=>throw new InvalidOperationException("resources upload",error);
                var bounds=new Rectangle(100,200,192,128);
                damage.Adopt(new OpaqueHudRasterScene(world,0),bounds,true);
                resources.Adopt(new OpaqueHudRasterScene(world,1),bounds,true);
                WithPixels(red,p=>Assert.True(damage.TryPresent(p,24,16,128,new Point(120,220))));
                WithPixels(green,p=>Assert.True(resources.TryPresent(p,10,6,48,new Point(128,224))));
                // WithPixels destroys the caller's bytes immediately on return.
                var first=PixelsUntil(world,scene,p=>Pixel(p,30,26,0,220,0),"top layer");
                Assert.True(Pixel(first,22,22,70,40,143),"Premultiplied HUD alpha was not blended over the world.");
                Assert.True(Pixel(first,50,50,140,80,30),"World pixels changed outside the HUD.");
                var raw=Grab(world,false);
                Assert.True(Pixel(raw,30,26,140,80,30),"HUD fed back into the captured source.");
                ulong uploaded=world.ReadHudRaster().Uploads;
                world.Mode(1);
                PixelsUntil(world,scene,p=>Pixel(p,30,26,0,220,0) && !Pixel(p,50,50,140,80,30),"world grading");
                Assert.Equal(uploaded,world.ReadHudRaster().Uploads);
                resources.Hide();
                PixelsUntil(world,scene,p=>!Pixel(p,30,26,0,220,0),"independent resource removal");
                Assert.Equal(1u,world.ReadHudRaster().VisibleLayers);
                world.Mode(0);
                WithPixels(red,p=>Assert.True(damage.TryPresent(p,4,4,128,new Point(150,250))));
                var moved=PixelsUntil(world,scene,p=>Pixel(p,51,51,70,40,143),"move and shrink");
                Assert.True(Pixel(moved,22,22,140,80,30));
                Assert.True(Pixel(moved,35,30,140,80,30));
                damage.Hide();
                PixelsUntil(world,scene,p=>Pixel(p,51,51,140,80,30),"last layer clear");
                Assert.Equal(0u,world.ReadHudRaster().VisibleLayers);
                WithPixels(red,p=>
                {
                    Assert.Throws<ArgumentException>(()=>world.SetHudRaster(5,p,24,16,128,0,0));
                    Assert.Throws<ArgumentException>(()=>world.SetHudRaster(0,p,24,16,95,0,0));
                    Assert.Throws<ArgumentException>(()=>world.SetHudRaster(0,p,24,4097,128,0,0));
                });
                Console.WriteLine(JsonConvert.SerializeObject(new {phase="opaque_hud_pixels",stats=world.ReadHudRaster(),
                    sourceFeedback=false,backbufferIncludesBothLayers=true,physicalScanoutVerified=false}));
            });
        }

        [SharedWorldGpuFact(requireDisplayOn:true)]
        public void HudChangesWakeStaticWorldAndReusedTexturesDoNotUploadAgain()
        {
            Run((world,scene,output,source)=>
            {
                byte[] tile=Tile(96,48,384,32,64,128,255);
                for(int i=0;i<40;i++)
                {
                    ulong previous=world.Read().Presented;
                    WithPixels(tile,p=>world.SetHudRaster(i%2,p,96,48,384,10+i%2*80,20));
                    Pump(()=>world.Read().Presented>previous,scene,"HUD-only presentation");
                }
                var before=world.ReadHudRaster();
                world.Mode(1);
                Pump(()=>world.ReadHudRaster().Draws>before.Draws,scene,"cached layer redraw");
                var after=world.ReadHudRaster();
                Assert.Equal(before.Uploads,after.Uploads);
                Assert.Equal(before.UploadedBytes,after.UploadedBytes);
                Assert.Equal(2u,after.VisibleLayers);
                Console.WriteLine(JsonConvert.SerializeObject(new {phase="opaque_hud_wake",stats=after,timing=world.ReadTiming(),
                    source="owned_static_window",physicalScanoutVerified=false,gameplayExecuted=false}));
            });
        }

        [SharedWorldGpuFact(requireDisplayOn:true)]
        public void SmallerSourceViewportsPreserveWorldGeometryAndPhysicalHudPixels()
        {
            Run((world,scene,output,source)=>
            {
                var painted=(Window)source;
                byte[] tile=Tile(24,16,96,32,64,128,255);
                WithPixels(tile,p=>world.SetHudRaster(1,p,24,16,96,110,90));
                PixelsUntil(world,scene,p=>Pixel(p,120,98,32,64,128),"HUD before viewport handoff");
                ulong uploads=world.ReadHudRaster().Uploads;
                foreach(var size in new[]{new Size(192,128),new Size(163,109),new Size(144,96),new Size(129,86)})
                {
                    world.HoldViewport();
                    ulong held=world.Read().Presented;
                    double fence=Stopwatch.GetTimestamp()*1000.0/Stopwatch.Frequency;
                    painted.PaintedViewport=size;source.Refresh();Application.DoEvents();
                    Assert.Equal(held,world.Read().Presented);
                    world.Viewport(new Rectangle(Point.Empty,size),fence);
                    Pump(()=>{var stats=world.Read();return stats.Width==size.Width && stats.Height==size.Height
                        && stats.LastFrameQpcMs>=fence && stats.Presented>held;},scene,"fresh viewport "+size);
                    // The source renders its new geometry synchronously here.
                    // This checks crop/output math, not Flash's asynchronous paint fence.
                    var frame=PixelsUntil(world,scene,p=>p.Width==192 && p.Height==128
                        && Pixel(p,170,16,0,0,255) && Pixel(p,170,110,0,255,0)
                        && Pixel(p,50,50,140,80,30) && Pixel(p,120,98,32,64,128),"source extent "+size);
                    Assert.True(Pixel(frame,109,98,140,80,30));
                    Assert.True(Pixel(frame,134,98,140,80,30));
                    Assert.Equal(uploads,world.ReadHudRaster().Uploads);
                    Assert.Equal(1u,world.ReadHudRaster().VisibleLayers);
                    var raw=Grab(world,false);Assert.Equal(size.Width,raw.Width);Assert.Equal(size.Height,raw.Height);
                }
                Console.WriteLine(JsonConvert.SerializeObject(new {phase="hud_source_scale_handoff",sourceScales=new[]{1,.85,.75,.67},
                    unchangedOutput=new {width=192,height=128},hudPixelsRetained=true,flashPaintFenceVerified=false,physicalScanoutVerified=false}));
            });
        }

        private sealed class LegacyResource : Form
        {
            // Exercise the production ULW executor without the game's foreground-owner
            // lifecycle: these non-activating fixture windows never acquire game focus.
            internal LegacyResource(Form owner)
            {
                Owner=owner;FormBorderStyle=FormBorderStyle.None;ShowInTaskbar=false;
                AutoScaleMode=AutoScaleMode.None;StartPosition=FormStartPosition.Manual;
            }
            protected override bool ShowWithoutActivation => true;
            protected override CreateParams CreateParams
            {
                get {var value=base.CreateParams;value.ExStyle|=0x80000|0x80|0x08000000|0x20;return value;}
            }
            internal void Submit(PlayerInfoLayeredDibSurface dib,Point origin,bool bitmapPath=false)
            {
                Bounds=new Rectangle(origin,new Size(dib.Width,dib.Height));
                if(!Visible)Show();
                var result=bitmapPath
                    ? LayeredWindowCommitExecutor.Execute(Handle,dib.Bitmap,origin.X,origin.Y,255,Win32LayeredWindowCommitNativeApi.Instance)
                    : LayeredWindowCommitExecutor.ExecutePrepared(Handle,dib.MemoryDc,dib.Width,dib.Height,
                        origin.X,origin.Y,255,Win32LayeredWindowCommitNativeApi.Instance);
                Assert.True(result.Succeeded,"Legacy DIB submission: "+result.ErrorValue+" native="+result.NativeErrorCode);
            }
            internal void Clear() => Hide();
            internal object Describe() => new {Bounds,TopMost,IsHandleCreated,Visible};
        }

        [SharedWorldGpuFact(requireDisplayOn:true)]
        public void CompareLegacyAndOpaqueWithMatchedTwoTileWorkload()
        {
            string candidate=Path.GetFullPath(Environment.GetEnvironmentVariable("CF7_TEST_SHARED_WORLD_CANDIDATE"));
            var root=new DirectoryInfo(candidate);
            for(int i=0;i<4;i++)root=root.Parent ?? throw new InvalidOperationException("Candidate root is incomplete.");
            string directory=Path.Combine(root.FullName,"tmp","hud-opaque-pilot");
            Directory.CreateDirectory(directory);
            string phasePath=Path.Combine(directory,"perf-phase.json");
            var rows=new List<object>();
            try
            {
                Run((world,scene,output,source)=>
                {
                    using var legacy=new LegacyResource(output) {TopMost=true};
                    using var damage=new PlayerInfoLayeredDibSurface(300,100);
                    using var resource=new PlayerInfoLayeredDibSurface(260,140);
                    Marshal.Copy(Tile(300,100,1200,40,25,90,128),0,damage.Pixels,120000);
                    Marshal.Copy(Tile(260,140,1040,60,100,30,180),0,resource.Pixels,145600);
                    foreach(bool animate in new[] {false,true})
                    foreach(bool opaque in new[] {false,true,true,false})
                    {
                        world.SetHudRaster(0,IntPtr.Zero,0,0,0,0,0);
                        world.SetHudRaster(1,IntPtr.Zero,0,0,0,0,0);
                        WithPixels(new byte[4],p=>scene.UploadHud(p,1,1,4,0,0));
                        legacy.Clear();
                        int phase=rows.Count;
                        void Mark(string status) => File.WriteAllText(phasePath,JsonConvert.SerializeObject(new {
                            status,phase,opaque,animate,pid=Environment.ProcessId,utc=DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()}));
                        Mark("warming");
                        var clock=Stopwatch.StartNew();
                        using var process=Process.GetCurrentProcess();
                        TimeSpan cpuStart=default;
                        double measureStart=0;
                        ulong presentStart=0;
                        var submissions=new List<double>();var presents=new List<double>();
                        for(int frame=0;frame<240;frame++)
                        {
                            if(frame==60) {
                                // Validate the actual composed desktop before timing. A covered legacy
                                // window would otherwise create a falsely cheap baseline.
                                Point check=output.PointToScreen(new Point(410,345));
                                using var screen=new Bitmap(1,1);
                                using(var graphics=Graphics.FromImage(screen))
                                    graphics.CopyFromScreen(check,Point.Empty,new Size(1,1));
                                Color visible=screen.GetPixel(0,0);
                                Console.WriteLine(JsonConvert.SerializeObject(new {phase,opaque,check,visible,legacy=legacy.Describe(),
                                    output=output.Bounds,dpi=output.DeviceDpi}));
                                Assert.InRange((int)visible.B,98,104);
                                Assert.InRange((int)visible.G,121,127);
                                Assert.InRange((int)visible.R,36,42);
                                Mark("measuring");cpuStart=process.TotalProcessorTime;
                                measureStart=clock.Elapsed.TotalSeconds;presentStart=world.Read().Presented;}
                            source.BackColor=Color.FromArgb(30+(frame&1),80,140);
                            if(frame==0 || animate)
                            {
                                int dx=animate?frame%3:0;
                                if(opaque)
                                {
                                    world.SetHudRaster(0,damage.Pixels,300,100,1200,30+dx,40);
                                    world.SetHudRaster(1,resource.Pixels,260,140,1040,400,330+dx);
                                }
                                else
                                {
                                    scene.UploadHud(damage.Pixels,300,100,1200,30+dx,40);
                                    legacy.Submit(resource,output.PointToScreen(new Point(400,330+dx)));
                                }
                            }
                            Application.DoEvents();scene.Commit();
                            if(frame>=60) {var sample=world.Read();submissions.Add(sample.SubmitMs);presents.Add(sample.PresentMs);}
                            while(clock.Elapsed.TotalMilliseconds<(frame+1)*1000.0/30.0)
                            {Application.DoEvents();Thread.Sleep(1);}
                        }
                        double seconds=clock.Elapsed.TotalSeconds-measureStart;
                        var stats=world.Read();
                        Assert.True(stats.Presented>presentStart);
                        var row=new {phase,opaque,animate,seconds,
                            cpuCorePercent=(process.TotalProcessorTime-cpuStart).TotalSeconds/seconds*100,
                            nativePresents=stats.Presented-presentStart,
                            sampledSubmitP95Ms=Percentile(submissions),sampledPresentCallP95Ms=Percentile(presents),
                            hud=world.ReadHudRaster(),outputWidth=output.ClientSize.Width,outputHeight=output.ClientSize.Height};
                        rows.Add(row);Console.WriteLine(JsonConvert.SerializeObject(row));
                    }
                    Assert.Equal(1,DisplayPowerObservation.ReadSessionState());
                    File.WriteAllText(Path.Combine(directory,"perf-comparison.json"),JsonConvert.SerializeObject(new {
                        fixture="opaque-hud-two-tile-abba",candidate,rows,
                        stimulusHz=30,worldSource="owned-window",syntheticHudPixels=true,
                        physicalScanoutVerified=false,gameplayExecuted=false},Formatting.Indented));
                },new Size(960,540),TimeSpan.FromSeconds(110));
            }
            finally {File.WriteAllText(phasePath,JsonConvert.SerializeObject(new {status="finished",pid=Environment.ProcessId}));}
        }

        private static double Percentile(List<double> values) {values.Sort();return values[(int)Math.Ceiling(values.Count*.95)-1];}
        private static void Run(Action<NativeCompositorSession,CompositionSceneHost,Form,Form> action,Size? outputSize=null,TimeSpan? timeout=null)
        {
            Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);
            string candidate=Path.GetFullPath(Environment.GetEnvironmentVariable("CF7_TEST_SHARED_WORLD_CANDIDATE"));
            string module=Path.Combine(candidate,"runtime",NativeCompositorSession.ModuleName);
            var metadata=JObject.Parse(File.ReadAllText(Path.Combine(candidate,"runtime-build-metadata.v2.json")));
            string[] row=File.ReadLines(Path.Combine(candidate,"runtime","cf7-runtime-manifest.tsv"))
                .Select(line=>line.Split('\t')).Single(parts=>parts.Length==4 && parts[0]=="file"
                    && parts[1]=="runtime/"+NativeCompositorSession.ModuleName);
            string hash=Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(module)));
            Assert.Equal(row[3],hash,true);
            Exception failure=null;
            var thread=new Thread(()=>
            {
                try
                {
                    using var source=new Window {FormBorderStyle=FormBorderStyle.None,ShowInTaskbar=false,TopMost=true,
                        AutoScaleMode=AutoScaleMode.None,StartPosition=FormStartPosition.Manual,Location=new Point(70,70),
                        ClientSize=outputSize ?? new Size(192,128),BackColor=Color.FromArgb(30,80,140)};
                    using var output=new Window {FormBorderStyle=FormBorderStyle.None,ShowInTaskbar=false,TopMost=true,
                        AutoScaleMode=AutoScaleMode.None,StartPosition=FormStartPosition.Manual,Location=new Point(350,70),
                        ClientSize=outputSize ?? new Size(192,128)};
                    source.Show();output.Show();Application.DoEvents();
                    using var scene=CompositionSceneHost.Create(output.Handle,module);
                    IntPtr visual=scene.AcquireVisual(0);
                    NativeCompositorSession world;
                    try {world=new NativeCompositorSession(module,source.Handle,(uint)Environment.ProcessId,output.Handle,sharedWorldVisual:visual);}
                    finally {Marshal.Release(visual);}
                    using(world)
                    {
                        world.Mode(0);
                        Pump(()=>world.Read().Received>0,scene,"source capture");
                        PixelsUntil(world,scene,p=>Pixel(p,50,50,140,80,30),"baseline pixels");
                        action(world,scene,output,source);
                        Console.WriteLine(JsonConvert.SerializeObject(new {nativeModule=module,nativeSha256=hash,
                            buildIdentity=metadata.Value<string>("buildIdentityHash"),closure=metadata.Value<string>("payloadClosureHash"),
                            testCore=typeof(NativeCompositorSession).Assembly.Location,
                            testCoreSha256=Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(typeof(NativeCompositorSession).Assembly.Location))),
                            candidateCoreSha256=Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(Path.Combine(candidate,"runtime","CRAZYFLASHER7MercenaryEmpire.Core.dll")))),
                            display=DisplayPowerObservation.ReadSessionState()}));
                    }
                }
                catch(Exception error) {failure=error;}
            }) {IsBackground=true};
            thread.SetApartmentState(ApartmentState.STA);thread.Start();
            Assert.True(thread.Join(timeout ?? TimeSpan.FromSeconds(60)),"Opaque HUD fixture exceeded its execution budget.");
            if(failure!=null)ExceptionDispatchInfo.Capture(failure).Throw();
        }
        private static byte[] Tile(int width,int height,int stride,byte b,byte g,byte r,byte a)
        {
            var pixels=new byte[stride*height];
            for(int y=0;y<height;y++)for(int x=0;x<width;x++)
            {int p=y*stride+x*4;pixels[p]=b;pixels[p+1]=g;pixels[p+2]=r;pixels[p+3]=a;}
            return pixels;
        }
        private static void WithPixels(byte[] bytes,Action<IntPtr> action)
        {
            IntPtr pixels=Marshal.AllocHGlobal(bytes.Length);
            try {Marshal.Copy(bytes,0,pixels,bytes.Length);action(pixels);Marshal.Copy(new byte[bytes.Length],0,pixels,bytes.Length);}
            finally {Marshal.FreeHGlobal(pixels);}
        }
        private readonly record struct Frame(byte[] Pixels,int Width,int Height);
        private static Frame Grab(NativeCompositorSession world,bool composite=true)
        {
            int width,height;
            int status=composite?world.GrabCompositeFrame(null,out width,out height):world.GrabLatestFrame(null,out width,out height);
            Assert.Equal(NativeCompositorSession.GrabBufferTooSmall,status);
            var pixels=new byte[checked(width*height*4)];
            status=composite?world.GrabCompositeFrame(pixels,out width,out height):world.GrabLatestFrame(pixels,out width,out height);
            Assert.Equal(NativeCompositorSession.GrabOk,status);
            return new Frame(pixels,width,height);
        }
        private static Frame PixelsUntil(NativeCompositorSession world,CompositionSceneHost scene,Func<Frame,bool> condition,string phase)
        {
            Frame frame=default;
            Pump(()=>{frame=Grab(world);return condition(frame);},scene,phase);return frame;
        }
        private static bool Pixel(Frame frame,int x,int y,int b,int g,int r)
        {
            int p=(y*frame.Width+x)*4;
            return Math.Abs(frame.Pixels[p]-b)<=2 && Math.Abs(frame.Pixels[p+1]-g)<=2 && Math.Abs(frame.Pixels[p+2]-r)<=2;
        }
        private static void Pump(Func<bool> condition,CompositionSceneHost scene,string phase)
        {
            var watch=Stopwatch.StartNew();
            do {Application.DoEvents();scene.Commit();if(condition())return;Thread.Sleep(5);}
            while(watch.Elapsed<TimeSpan.FromSeconds(6));
            Assert.Fail("Opaque HUD fixture did not reach "+phase);
        }
    }
}
