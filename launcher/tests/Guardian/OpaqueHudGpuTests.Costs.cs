using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Security.Cryptography;
using System.Threading;
using System.Windows.Forms;
using CF7Launcher.Fonts;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.Hud;
using CF7Launcher.Guardian.Hud.Loot;
using CF7Launcher.Guardian.Hud.PlayerInfo;
using CF7Launcher.Guardian.WorldCompositor;
using CF7Launcher.Tests.Guardian.Hud.PlayerInfo;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian;

public sealed class SharedHudCostFactAttribute : FactAttribute
{
    public SharedHudCostFactAttribute()
    {
        if(string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("CF7_HUD_COST_REPORT")))
            Skip="Explicit unique shared HUD cost report required; ordinary tests do not run timing workloads.";
        else if(string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("CF7_TEST_SHARED_WORLD_CANDIDATE")))
            Skip="Explicit verified runtime candidate required.";
        else if(DisplayPowerObservation.ReadSessionState()!=1)
            Skip="Cost sampling requires an on session display; never wake it automatically.";
    }
}

public sealed partial class OpaqueHudGpuTests
{
    [SharedWorldGpuFact(requireDisplayOn:true)]
    public void HudPixelCacheKeepsPublishedFramesImmutableAndReleasesHiddenLayers()
    {
        Run((world,scene,output,source)=>
        {
            world.SetHudCostSampling(true);
            var work=Enumerable.Range(0,5).Select(layer=>System.Threading.Tasks.Task.Run(()=>
            {
                for(int step=0;step<120;step++)
                {
                    int width=step<60?67:new[]{19,43,67}[step%3],height=23,stride=width*4+16;
                    byte[] bytes=Tile(width,height,stride,(byte)(20+layer*30),80,140,255);
                    // WithPixels destroys the caller buffer as soon as the copy
                    // returns; five independent producers race the GPU reader.
                    WithPixels(bytes,p=>world.SetHudRaster(layer,p,width,height,stride,layer*72,16));
                }
            })).ToArray();
            Assert.True(System.Threading.Tasks.Task.WaitAll(work,TimeSpan.FromSeconds(10)));
            var final=PixelsUntil(world,scene,p=>Enumerable.Range(0,5).All(layer=>
                Pixel(p,layer*72+4,20,(byte)(20+layer*30),80,140)),"five immutable final frames");
            foreach(int layer in Enumerable.Range(0,5))Assert.True(Pixel(final,layer*72+64,35,(byte)(20+layer*30),80,140));
            var stats=world.ReadHudCost();
            Assert.Equal(600UL,stats.CopySamples);Assert.True(stats.PoolReuses>100);
            Assert.Equal(stats.CopySamples,stats.PoolAllocations+stats.PoolReuses);
            Assert.InRange(stats.CachedBytes,1UL,32UL*1024*1024);
            for(int layer=0;layer<5;layer++)world.SetHudRaster(layer,IntPtr.Zero,0,0,0,0,0);
            Assert.Equal(0UL,world.ReadHudCost().CachedBytes);
            PixelsUntil(world,scene,p=>Pixel(p,4,20,140,80,30),"cache hide leaves world pixels");

            // A valid image larger than the retention budget still presents;
            // oversized buffers must not be admitted into the cache.
            const int largeWidth=3072,largeHeight=3072;
            var large=Tile(largeWidth,largeHeight,largeWidth*4,50,70,90,255);
            WithPixels(large,p=>world.SetHudRaster(4,p,largeWidth,largeHeight,largeWidth*4,0,0));
            PixelsUntil(world,scene,p=>Pixel(p,50,50,50,70,90),"oversized uncached raster");
            Assert.Equal(0UL,world.ReadHudCost().CachedBytes);
            world.SetHudRaster(4,IntPtr.Zero,0,0,0,0,0);
            world.SetHudCostSampling(false);
        },new Size(384,256));
    }

    [SharedWorldGpuFact(requireDisplayOn:true)]
    public void HudCostSamplingPreservesPixelsAndSeparatesMeasurementEpochs()
    {
        Run((world,scene,output,source)=>
        {
            Assert.True(world.HudCostSamplingAvailable);
            var inactive=world.ReadHudCost();
            Assert.Equal(0u,inactive.Enabled);Assert.Equal(0u,inactive.Started);Assert.Equal(0UL,inactive.CopySamples);
            const int width=32,height=24,repeats=12;
            byte[] tile=Tile(width,height,width*4,10,40,80,255);
            world.SetHudCostSampling(true);
            WithPixels(tile,pixels=>
            {
                for(int i=0;i<repeats;i++)
                {
                    System.Runtime.InteropServices.Marshal.WriteInt32(pixels,unchecked((int)0xff50280a)+i);
                    ulong previous=world.Read().Presented;
                    world.SetHudRaster(4,pixels,width,height,width*4,40,40);
                    Pump(()=>world.Read().Presented>previous,scene,"sampled frame");
                }
            });
            world.SetHudCostSampling(false);
            var sampled=world.ReadHudCost();var deadline=Stopwatch.StartNew();
            while(sampled.Completed+sampled.Disjoint+sampled.Errors+sampled.Dropped<sampled.Started && deadline.ElapsedMilliseconds<1500)
            {
                Thread.Sleep(5);sampled=world.ReadHudCost();
            }
            Assert.Equal((ulong)repeats,sampled.CopySamples);
            Assert.True(sampled.PoolReuses>=repeats-3);
            Assert.InRange(sampled.PoolAllocations,1UL,3UL);
            Assert.Equal(sampled.CopySamples,sampled.PoolAllocations+sampled.PoolReuses);
            Assert.Equal((ulong)(width*height*4*repeats),sampled.CopyBytes);
            Assert.Equal((ulong)sampled.Started,sampled.Completed);
            Assert.Equal(0UL,sampled.Disjoint);Assert.Equal(0UL,sampled.Dropped);Assert.Equal(0UL,sampled.Errors);
            Assert.True(sampled.Completed>0);
            Assert.True(sampled.WorldP50Ms<=sampled.WorldP95Ms&&sampled.WorldP95Ms<=sampled.WorldP99Ms);
            Assert.True(sampled.HudP50Ms<=sampled.HudP95Ms&&sampled.HudP95Ms<=sampled.HudP99Ms);
            var enabledPixels=PixelsUntil(world,scene,p=>Pixel(p,40,40,21,40,80),"last immutable sampled raster");
            byte[] finalTile=Tile(width,height,width*4,10,40,80,255);finalTile[0]=21;
            WithPixels(finalTile,pixels=>world.SetHudRaster(4,pixels,width,height,width*4,40,40));
            var disabledPixels=PixelsUntil(world,scene,p=>SamePixels(p,enabledPixels.Pixels),"sampling does not alter pixels");
            Assert.True(SamePixels(disabledPixels,enabledPixels.Pixels));
            Assert.Equal(sampled.CopySamples,world.ReadHudCost().CopySamples);
            world.SetHudCostSampling(true);
            var reset=world.ReadHudCost();Assert.Equal(0UL,reset.CopySamples);Assert.Equal(0UL,reset.CopyBytes);
            world.SetHudCostSampling(false);
            world.SetHudRaster(4,IntPtr.Zero,0,0,0,0,0);
            PixelsUntil(world,scene,p=>Pixel(p,40,40,140,80,30),"clear after measurement epochs");
            Assert.Equal(0UL,world.ReadHudCost().CachedBytes);
        });
    }

    // Explicitly opted-in cost experiment. It uses the live painters and native
    // APIs on owned windows; it neither starts the game nor touches save data.
    [SharedHudCostFact]
    public void MeasureSharedHudPaintTransportAndMixedComposition()
    {
        string destination=Environment.GetEnvironmentVariable("CF7_HUD_COST_REPORT");
        Assert.False(string.IsNullOrWhiteSpace(destination),"A unique cost report path is required.");
        destination=Path.GetFullPath(destination);
        Assert.False(File.Exists(destination),"Cost reports are immutable per run.");
        string root=Path.GetFullPath(Environment.GetEnvironmentVariable("CF7_HUD_COST_PROJECT")
            ?? Path.Combine(AppContext.BaseDirectory,"..","..","..",".."));
        int repeats=int.TryParse(Environment.GetEnvironmentVariable("CF7_HUD_COST_REPEATS"),out int r)?r:3;
        int measuredFrames=int.TryParse(Environment.GetEnvironmentVariable("CF7_HUD_COST_FRAMES"),out int f)?f:240;
        Assert.InRange(repeats,1,5);Assert.InRange(measuredFrames,90,900);
        var rows=new List<object>();
        string candidate=Path.GetFullPath(Environment.GetEnvironmentVariable("CF7_TEST_SHARED_WORLD_CANDIDATE"));
        string core=typeof(NativeCompositorSession).Assembly.Location;
        string native=Path.Combine(candidate,"runtime",NativeCompositorSession.ModuleName);
        var identity=JObject.Parse(File.ReadAllText(Path.Combine(candidate,"runtime-build-metadata.v2.json")));
        Run((world,scene,output,source)=>
        {
            Assert.True(world.HudCostSamplingAvailable,"Paired GPU timestamp and CPU copy diagnostics are required.");
            Assert.Equal(168,System.Runtime.InteropServices.Marshal.SizeOf<NativeCompositorSession.HudCostStats>());
            RuntimeFontCatalog.Configure(root);
            using var icons=new LootIconCatalog(Path.Combine(root,"launcher","web","icons"));
            using var commands=new PlayerHudController(_=>true,()=>true,a=>a());
            var state=PlayerHudStateTests.Full();
            state["groups"]["vitals"]["hp"]=new JArray(800,1000);
            state["groups"]["vitals"]["paused"]=true;
            commands.TakeUiData("pi:"+PlayerHudStateTests.Encode(state));
            using var resources=PlayerInfoSplitSurface.CreateLive(output,output,commands.State);
            using var main=new NativeHudOverlay(output,output);
            var router=new LauncherCommandRouter(null,_=>{},()=>{},()=>{},()=>{},_=>{});
            var right=new RightContextWidget(output,router,MapHudDataCatalog.FromPayload(new MapHudPayload {ProtocolVersion=1,Hotspots=new()}));
            var combo=new ComboWidget(output);combo.ForceGameReady(true);
            var toast=new ToastWidget(output);
            var loot=new LootFeedWidget(output,icons);
            var notch=new NotchWidget(output,new FpsRingBuffer(300),root,()=>{},()=>{},()=>{},_=>{});
            var widgets=new INativeHudWidget[]{right,combo,toast,loot,notch};
            foreach(var widget in widgets)main.AddWidget(widget);
            main.HandleUiData("s:1|g:1000|k:20");right.SetReady();
            notch.ForceGameReadyForTest(true);notch.BeginExpandForTest();notch.Tick(2000);
            combo.OnNotchNotice("combo","DFA 连击",Color.Orange);combo.Tick(100);
            loot.AddEvent("material","测试物资",2,"hud-cost","",direction:"gain");
            using var coordinator=new WorldCompositorController(output,output,()=>IntPtr.Zero,()=>false,_=>{},root,()=>false,_=>{},()=>{});
            using var runtime=new PlayerHudRuntime(output,output,resources,commands,Path.Combine(root,"launcher","web","icons"),main,shareMainHud:true);
            Rectangle bounds=output.RectangleToScreen(output.ClientRectangle);
            coordinator.BottomPresentation.Adopt(new OpaqueHudRasterScene(world,2),bounds,true);
            coordinator.ResourcePresentation.Adopt(new OpaqueHudRasterScene(world,1),bounds,true);
            coordinator.BuffPresentation.Adopt(new OpaqueHudRasterScene(world,3),bounds,true);
            coordinator.MainHudPresentation.Adopt(new OpaqueHudRasterScene(world,4),bounds,true);
            runtime.SetSharedWorld(coordinator);runtime.SetReady();main.SetReady();
            Pump(()=>world.ReadHudRaster().VisibleLayers>=3,scene,"cost fixture production HUD");
            FreezeHudTimers(main);
            var render=(Action)Delegate.CreateDelegate(typeof(Action),main,typeof(NativeHudOverlay)
                .GetMethod("RenderToBitmapAndCommit",BindingFlags.Instance|BindingFlags.NonPublic));
            var pending=typeof(NativeHudOverlay).GetField("_renderPending",BindingFlags.Instance|BindingFlags.NonPublic);
            var mainPaint=new List<double>();var mainCommit=new List<double>();var rectangles=new List<long>();
            var damagedPixels=new List<long>();var paintedWidgets=new List<int>();
            var companionSamples=new List<(string Layer,double Paint,double Commit,int Width,int Height)>();
            bool sampling=false;
            main.RenderTimingObserver=(paint,commit,width,height)=>
            {
                if(!sampling)return;
                mainPaint.Add(paint);mainCommit.Add(commit);rectangles.Add((long)width*height);
                damagedPixels.Add(main.LastPaintedPixels);paintedWidgets.Add(main.LastPaintedWidgetCount);
            };
            var bottom=(NativeHudOverlay)typeof(PlayerHudRuntime).GetField("_bottom",BindingFlags.Instance|BindingFlags.NonPublic).GetValue(runtime);
            var buffs=(NativeHudOverlay)typeof(PlayerHudRuntime).GetField("_buffs",BindingFlags.Instance|BindingFlags.NonPublic).GetValue(runtime);
            resources.RenderTimingObserver=(paint,commit,width,height)=>{if(sampling)companionSamples.Add(("resources",paint,commit,width,height));};
            bottom.RenderTimingObserver=(paint,commit,width,height)=>{if(sampling)companionSamples.Add(("bottom",paint,commit,width,height));};
            buffs.RenderTimingObserver=(paint,commit,width,height)=>{if(sampling)companionSamples.Add(("buffs",paint,commit,width,height));};
            var resourceTimer=(System.Windows.Forms.Timer)typeof(PlayerInfoSplitSurface)
                .GetField("_animationTimer",BindingFlags.Instance|BindingFlags.NonPublic).GetValue(resources);
            var resumeResources=(Action)Delegate.CreateDelegate(typeof(Action),resources,typeof(PlayerInfoSplitSurface)
                .GetMethod("UpdateAnimationTimer",BindingFlags.Instance|BindingFlags.NonPublic));
            var bulletCatalog=BulletVisualCatalog.Load(root);
            world.BulletStyles(bulletCatalog);
            world.BulletAtlas(bulletCatalog.AtlasBgraPremultiplied,bulletCatalog.AtlasWidth,bulletCatalog.AtlasHeight);
            var effects=CombatFxCatalog.Load(root);world.CombatFxAtlas(effects);
            world.WeatherStyle(2,160,new float[]{1,1,1,1,1,1,1,1,.1f,0,1,1,.85f,1,0,0});
            Pump(()=>world.BulletResourcesReady&&world.CombatFxReady,scene,"cost fixture production atlases");
            var bulletFrames=BuildHudCostBullets(bulletCatalog,180);
            var fxFrames=BuildHudCostLights(180);
            int sequence=0;
            for(int repeat=0;repeat<repeats;repeat++)
            foreach(string workload in (repeat%2==0?new[]{"static","hud_only","mixed"}:new[]{"mixed","hud_only","static"}))
            {
                world.ClearBulletFrame();world.ClearCombatFxFrame();world.ClearRayFrame();world.Weather(0,0,0,413);
                source.BackColor=Color.FromArgb(30,80,140);
                bool animate=workload!="static",mixed=workload=="mixed";
                world.SetHudCostSampling(true);
                if(mixed)world.Weather(2,1,0,413);
                if(animate)resumeResources();else resourceTimer.Stop();
                FreezeHudTimers(bottom);FreezeHudTimers(buffs);
                combo.OnNotchNotice("combo","DFA 连击",Color.Orange);
                loot.AddEvent("material","测试物资",1,"hud-cost","",direction:"gain");
                foreach(var widget in widgets)if(widget.WantsAnimationTick)widget.Tick(80);
                render();pending.SetValue(main,false);FreezeHudTimers(main);
                mainPaint.Clear();mainCommit.Clear();rectangles.Clear();companionSamples.Clear();damagedPixels.Clear();paintedWidgets.Clear();sampling=false;
                using var process=Process.GetCurrentProcess();
                var clock=Stopwatch.StartNew();double nextFrame=0,measureStart=0;
                TimeSpan cpuStart=default;long allocationStart=0;
                NativeCompositorSession.Stats before=default;
                NativeCompositorSession.HudRasterStats rasterBefore=default;
                NativeCompositorSession.WorkStats workBefore=default;
                var submitSamples=new List<double>();var presentSamples=new List<double>();
                var frameDurations=new List<double>();
                ulong lastObservedPresent=0;
                for(int frame=0;frame<60+measuredFrames;frame++)
                {
                    if(frame==60)
                    {
                        Assert.Equal(1,DisplayPowerObservation.ReadSessionState());
                        world.SetHudCostSampling(true);
                        before=world.Read();rasterBefore=world.ReadHudRaster();workBefore=world.ReadWork().Value;
                        lastObservedPresent=before.Presented;
                        cpuStart=process.TotalProcessorTime;allocationStart=GC.GetAllocatedBytesForCurrentThread();
                        measureStart=clock.Elapsed.TotalSeconds;mainPaint.Clear();mainCommit.Clear();rectangles.Clear();companionSamples.Clear();damagedPixels.Clear();paintedWidgets.Clear();sampling=true;
                    }
                    long tickStart=Stopwatch.GetTimestamp();
                    if(animate)
                    {
                        if(frame%30==0)combo.OnNotchNotice("combo","DFA "+(++sequence),Color.Orange);
                        if(frame%15==0)loot.AddEvent("material","测试物资",1,"hud-cost","",direction:"gain");
                        foreach(var widget in widgets)if(widget.Visible&&widget.WantsAnimationTick)widget.Tick(33);
                        if((bool)pending.GetValue(main)){render();pending.SetValue(main,false);}
                        FreezeHudTimers(main);
                    }
                    if(mixed)
                    {
                        source.BackColor=Color.FromArgb(30+(frame&1),80,140);
                        world.BulletFrame(bulletFrames[frame%bulletFrames.Length],0,0,1);
                        world.CombatFxFrame(fxFrames[frame%fxFrames.Length],0,0,1);
                    }
                    Application.DoEvents();scene.Commit();FreezeHudTimers(main);
                    FreezeHudTimers(bottom);FreezeHudTimers(buffs);
                    if(!animate)resourceTimer.Stop();
                    if(sampling)
                    {
                        frameDurations.Add(Stopwatch.GetElapsedTime(tickStart).TotalMilliseconds);
                        var stats=world.Read();
                        if(stats.Presented>lastObservedPresent)
                        {
                            submitSamples.Add(stats.SubmitMs);presentSamples.Add(stats.PresentMs);
                            lastObservedPresent=stats.Presented;
                        }
                    }
                    nextFrame+=1000.0/30;
                    while(clock.Elapsed.TotalMilliseconds<nextFrame){Application.DoEvents();Thread.Sleep(1);}
                }
                sampling=false;
                resourceTimer.Stop();FreezeHudTimers(main);FreezeHudTimers(bottom);FreezeHudTimers(buffs);
                var after=world.Read();var rasterAfter=world.ReadHudRaster();var workAfter=world.ReadWork().Value;
                double seconds=clock.Elapsed.TotalSeconds-measureStart;
                double cpuSeconds=(process.TotalProcessorTime-cpuStart).TotalSeconds;
                long allocated=GC.GetAllocatedBytesForCurrentThread()-allocationStart;
                world.SetHudCostSampling(false);
                var gpu=world.ReadHudCost();var drain=Stopwatch.StartNew();
                while(gpu.Completed+gpu.Disjoint+gpu.Errors<gpu.Started && drain.ElapsedMilliseconds<1500)
                {
                    Thread.Sleep(5);gpu=world.ReadHudCost();
                }
                Assert.Equal(0UL,gpu.Errors);Assert.Equal(0UL,gpu.Disjoint);Assert.Equal(0UL,gpu.Dropped);
                Assert.Equal((ulong)gpu.Started,gpu.Completed);
                Assert.Equal(1,DisplayPowerObservation.ReadSessionState());
                if(animate)
                {
                    Assert.True(mainPaint.Count>10,"Animation did not exercise the production painter.");
                    Assert.True(gpu.Completed>10,"No completed GPU timing samples.");
                }
                else
                {
                    Assert.Empty(mainPaint);Assert.Empty(companionSamples);
                    Assert.Equal(rasterBefore.Accepted,rasterAfter.Accepted);
                }
                var row=new {repeat,workload,seconds,requestedFrames=measuredFrames,mainRenders=mainPaint.Count,
                    paint=CostDistribution(mainPaint),commit=CostDistribution(mainCommit),driverCpu=CostDistribution(frameDurations),
                    meanRasterPixels=rectangles.Count==0?0:rectangles.Average(),maxRasterPixels=rectangles.Count==0?0:rectangles.Max(),
                    meanPaintedPixels=damagedPixels.Count==0?0:damagedPixels.Average(),meanPaintedWidgets=paintedWidgets.Count==0?0:paintedWidgets.Average(),
                    mainPixelBytes=rectangles.Sum()*4,cpuCorePercent=cpuSeconds/seconds*100,
                    driverThreadAllocatedBytes=allocated,received=after.Received-before.Received,presented=after.Presented-before.Presented,
                    compositions=workAfter.Compositions-workBefore.Compositions,lightDraws=workAfter.LightDraws-workBefore.LightDraws,
                    lightCacheHits=workAfter.LightCacheHits-workBefore.LightCacheHits,fxUploads=workAfter.FxUploads-workBefore.FxUploads,
                    hudAccepted=rasterAfter.Accepted-rasterBefore.Accepted,copiedBytes=rasterAfter.CopiedBytes-rasterBefore.CopiedBytes,
                    uploads=rasterAfter.Uploads-rasterBefore.Uploads,uploadedBytes=rasterAfter.UploadedBytes-rasterBefore.UploadedBytes,
                    hudDraws=rasterAfter.Draws-rasterBefore.Draws,submitCpuMs=CostDistribution(submitSamples),presentCallMs=CostDistribution(presentSamples)};
                var result=JObject.FromObject(row);
                result["gpuAndCopyCosts"]=JObject.FromObject(gpu);
                result["companions"]=JArray.FromObject(companionSamples.GroupBy(x=>x.Layer).Select(g=>new {
                    layer=g.Key,renders=g.Count(),paint=CostDistribution(g.Select(x=>x.Paint).ToArray()),
                    commit=CostDistribution(g.Select(x=>x.Commit).ToArray()),pixelBytes=g.Sum(x=>(long)x.Width*x.Height*4)}));
                rows.Add(result);Console.WriteLine("HUD_COST "+result.ToString(Formatting.None));
            }
            main.RenderTimingObserver=null;resources.BeginShutdown().GetAwaiter().GetResult();
        },new Size(1024,576),TimeSpan.FromSeconds(repeats*3*(measuredFrames/30+4)+75));
        Directory.CreateDirectory(Path.GetDirectoryName(destination));
        File.WriteAllText(destination,JsonConvert.SerializeObject(new {
            schema="cf7-shared-hud-cost.v1",recordedUtc=DateTimeOffset.UtcNow,variant=Environment.GetEnvironmentVariable("CF7_HUD_COST_VARIANT"),
            candidate,buildIdentity=identity["buildIdentityHash"],payloadClosure=identity["payloadClosureHash"],
            core,coreSha256=Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(core))),
            candidateCoreSha256=Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(Path.Combine(candidate,"runtime","CRAZYFLASHER7MercenaryEmpire.Core.dll")))),
            native,nativeSha256=Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(native))),
            resolution=new[]{1024,576},sourceHz=30,hudTickHz=30,rows,
            boundary="Owned WGC/D3D windows and production HUD painters. Static holds all visual clocks. HUD-only animates main HUD at 30Hz and the real resource timer, with no fresh source frames. Mixed adds production bullet/effect atlases with deterministic visual snapshots, 160 snow particles, 192 bullets, 8 lights and a 30Hz source. GPU timestamps cover world/effect and HUD upload/draw spans, excluding WGC capture/Present/DWM; CPU submit samples are separate and may observe fewer events than the worker. No game FPS, physical input, weak-machine thermal qualification or game/save operations."
        },Formatting.Indented));
    }

    private static object CostDistribution(IReadOnlyCollection<double> source)
    {
        var values=source.OrderBy(x=>x).ToArray();
        double Quantile(double q)=>values.Length==0?0:values[(int)Math.Ceiling((values.Length-1)*q)];
        return new {count=values.Length,sumMs=values.Sum(),meanMs=values.Length==0?0:values.Average(),
            p50Ms=Quantile(.5),p95Ms=Quantile(.95),p99Ms=Quantile(.99),maxMs=Quantile(1)};
    }
    private static BulletVisualFrame[] BuildHudCostBullets(BulletVisualCatalog catalog,int count)
    {
        var frames=new BulletVisualFrame[count];
        for(int f=0;f<count;f++)
        {
            var bullets=new BulletVisualInstance[192];
            for(int i=0;i<bullets.Length;i++)bullets[i]=new BulletVisualInstance(i%catalog.Styles.Count,
                70+(i*37+f*9)%850,60+(i*17)%390,(i*13)%360,45,45,85);
            frames[f]=BulletVisualFrame.Compose(1,f,bullets,Array.Empty<BulletVisualInstance>());
        }
        return frames;
    }
    private static CombatFxDrawFrame[] BuildHudCostLights(int count)
    {
        var frames=new CombatFxDrawFrame[count];
        for(int f=0;f<count;f++)
        {
            var draw=new CombatFxDrawFrame(1){LightCount=8,MaximumLightResponse=.8f};
            for(int i=0;i<8;i++)
            {
                float[] lamp={120+i*100,160+(f+i*19)%230,90,.65f,1,.7f,.3f,0,0,0,0,0,0,0,0,0};
                Array.Copy(lamp,0,draw.Lights,i*16,16);
            }
            frames[f]=draw;
        }
        return frames;
    }
}
