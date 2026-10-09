using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Threading;
using System.Windows.Forms;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.Hud.PlayerInfo;
using CF7Launcher.Guardian.WorldCompositor;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian.Hud.PlayerInfo;

public sealed class PlayerHudSharedPresentationTests
{
    private sealed class Raster : IWorldRasterScene
    {
        internal bool HasContent;
        internal int Clears,Uploads;
        public void UploadHud(IntPtr pixels,int width,int height,int stride,int x,int y) { HasContent=true;Uploads++; }
        public void ClearHud(IntPtr transparent) { HasContent=false;Clears++; }
    }
    private sealed class Flash : IWorldPointerSink
    {
        public PointerPostStatus Send(in PointerPacket packet,Point point)=>PointerPostStatus.Posted;
        public bool RaiseMinEpoch(uint epoch)=>true;
        public long EndpointConsumedSeq=>0;
    }
    private sealed class PassiveWindow : Form { protected override bool ShowWithoutActivation=>true; }
    [Fact]
    public void CaptureHandoffKeepsWholeHudOwnedUntilOutputActuallyRetires()
    {
        Exception failure=null;
        var thread=new Thread(()=> {
            try
            {
                string root=Path.GetFullPath(Path.Combine(AppContext.BaseDirectory,"..","..","..",".."));
                using var owner=new PassiveWindow {ClientSize=new Size(1024,576),AutoScaleMode=AutoScaleMode.None,
                    StartPosition=FormStartPosition.Manual,Location=new Point(40,40)};
                owner.Show();
                using var commands=new PlayerHudController(_=>true,()=>true,a=>a());
                var state=PlayerHudStateTests.Full();state["groups"]["vitals"]["hp"]=new JArray(0,1000);
                state["groups"]["vitals"]["paused"]=true;
                commands.TakeUiData("pi:"+PlayerHudStateTests.Encode(state));
                using var resources=PlayerInfoSplitSurface.CreateLive(owner,owner,commands.State);
                using var main=new NativeHudOverlay(owner,owner);
                using var surface=new WorldCompositionSurface(()=>owner.Handle,()=>{},new Flash()) {Owner=owner};
                surface.Bounds=owner.RectangleToScreen(owner.ClientRectangle);surface.Show();
                using var world=new WorldCompositorController(owner,owner,()=>owner.Handle,()=>true,_=>{},root,()=>false,_=>{},()=>{});
                Set(world,"_surface",surface);Set(world,"_active",true);
                var scenes=new[]{new Raster(),new Raster(),new Raster(),new Raster()};
                string[] names={"_damageRasterScene","_resourceRasterScene","_bottomRasterScene","_buffRasterScene"};
                for(int i=0;i<names.Length;i++)Set(world,names[i],scenes[i]);
                var presentations=new[]{world.DamagePresentation,world.ResourcePresentation,world.BottomPresentation,world.BuffPresentation};
                using var runtime=new PlayerHudRuntime(owner,owner,resources,commands,Path.Combine(root,"launcher","web","icons"),main);
                runtime.SetSharedWorld(world);
                world.RefreshHudPresentations();
                Assert.All(presentations,p=>Assert.False(p.IsAvailable)); // never captured
                Set(world,"_everReady",true);world.RefreshHudPresentations();runtime.SetReady();
                Pump(()=>scenes.Skip(1).All(s=>s.HasContent));
                Assert.All(runtime.PresentationSurfaces,s=>Assert.False(s.Visible));
                long commits=resources.Counters.CommitCount;
                int clears=scenes.Sum(s=>s.Clears),withdrawals=0;
                foreach(var presentation in presentations)presentation.Changed+=()=>{if(!presentation.IsAvailable)withdrawals++;};
                // Recreate the state at the six observed DRS handoffs: retained
                // output, a smaller source crop, and a frame fence not yet met.
                foreach(double scale in new[]{.85,.75,.67})
                {
                    world.ApplyRenderSelection(new RenderSelection(0,(int)(576*scale),"MEDIUM",0),0);
                    Set(world,"_viewportHeld",true);Set(world,"_requiredFrameMs",double.MaxValue);
                    Set(world,"_crop",new Rectangle(0,0,(int)(1024*scale),(int)(576*scale)));
                    world.RefreshHudPresentations();
                    Assert.All(presentations,p=>Assert.True(p.IsAvailable));
                    Assert.False(world.SchedulingAllowed);
                }
                owner.Location=new Point(95,85); // invoke production move callback, no capture tick
                Assert.Equal(owner.RectangleToScreen(owner.ClientRectangle),surface.Bounds);
                Assert.All(presentations,p=>Assert.True(p.IsAvailable));
                Assert.Equal(0,withdrawals);Assert.Equal(clears,scenes.Sum(s=>s.Clears));
                Assert.Equal(commits,resources.Counters.CommitCount);
                Assert.All(runtime.PresentationSurfaces,s=>Assert.False(s.Visible));
                Set(world,"_active",false);surface.Hide();world.RefreshHudPresentations();
                Assert.All(presentations,p=>Assert.False(p.IsAvailable));
                Assert.All(scenes,s=>Assert.False(s.HasContent));
                Set(world,"_active",true);surface.Show();world.RefreshHudPresentations();
                Pump(()=>scenes.Skip(1).All(s=>s.HasContent));
                world.ResetSource();world.RefreshHudPresentations();
                Assert.All(presentations,p=>Assert.False(p.IsAvailable));
                Assert.All(scenes,s=>Assert.False(s.HasContent));
                resources.BeginShutdown().GetAwaiter().GetResult();
            }
            catch(Exception error) { failure=error; }
        });
        thread.SetApartmentState(ApartmentState.STA);thread.Start();Assert.True(thread.Join(20000));
        if(failure!=null)System.Runtime.ExceptionServices.ExceptionDispatchInfo.Capture(failure).Throw();
    }
    private static void Set(WorldCompositorController world,string name,object value)
        =>typeof(WorldCompositorController).GetField(name,BindingFlags.Instance|BindingFlags.NonPublic).SetValue(world,value);
    private static void Pump(Func<bool> condition)
    {
        var elapsed=Stopwatch.StartNew();
        while(!condition() && elapsed.ElapsedMilliseconds<3000) {Application.DoEvents();Thread.Sleep(2);}
        Assert.True(condition());
    }
    [Fact]
    public void EmptyBuffCannotBeResurrectedByItsQueuedRepaint()
    {
        Exception failure=null;
        var thread=new Thread(()=> {
            try
            {
                using var owner=new Form {ClientSize=new Size(1024,576),AutoScaleMode=AutoScaleMode.None};
                using var anchor=new Panel {Dock=DockStyle.Fill};owner.Controls.Add(anchor);_=owner.Handle;_=anchor.Handle;
                using var controller=new PlayerHudController(_=>true,()=>true,a=>a());
                controller.TakeUiData("pi:"+PlayerHudStateTests.Encode(PlayerHudStateTests.Full()));
                using var hud=new NativeHudOverlay(owner,anchor);
                using var presentation=new WorldRasterPresentation();var raster=new Raster();
                presentation.Adopt(raster,new Rectangle(anchor.PointToScreen(Point.Empty),anchor.ClientSize),true);
                hud.SetSharedPresentation(presentation);hud.AddWidget(new PlayerHudBuffWidget(anchor,controller));hud.SetReady();
                Assert.True(raster.HasContent);Assert.False(hud.Visible);
                var tick=PlayerHudStateTests.Full(1,2);tick["groups"]["buffs"][0]["remaining"]=900;
                controller.TakeUiData("pi:"+PlayerHudStateTests.Encode(tick));
                var empty=PlayerHudStateTests.Full(1,3);empty["groups"]["buffs"]=new JArray();
                controller.TakeUiData("pi:"+PlayerHudStateTests.Encode(empty));
                Assert.False(raster.HasContent);
                int uploads=raster.Uploads;
                var elapsed=Stopwatch.StartNew();
                while(elapsed.ElapsedMilliseconds<120) { Application.DoEvents();Thread.Sleep(2); }
                Assert.False(raster.HasContent);Assert.Equal(uploads,raster.Uploads);
                Assert.Equal(1,raster.Clears);Assert.False(hud.Visible);
            }
            catch(Exception error) { failure=error; }
        });
        thread.SetApartmentState(ApartmentState.STA);thread.Start();Assert.True(thread.Join(15000));
        if(failure!=null)System.Runtime.ExceptionServices.ExceptionDispatchInfo.Capture(failure).Throw();
    }
}
