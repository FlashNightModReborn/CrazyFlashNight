using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Windows.Forms;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.Hud;
using CF7Launcher.Guardian.Hud.Dialogue;
using CF7Launcher.Guardian.Hud.Guidance;
using CF7Launcher.Guardian.Hud.Loot;
using CF7Launcher.Guardian.Hud.PlayerInfo;
using CF7Launcher.Guardian.Hud.Tooltip;
using CF7Launcher.Guardian.WorldCompositor;
using CF7Launcher.Tests.Guardian.Hud.PlayerInfo;
using CF7Launcher.Fonts;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian;

public sealed partial class OpaqueHudGpuTests
{
    [SharedWorldGpuFact(requireDisplayOn:true)]
    public void CompleteMainHudSharesPixelsAndFallbackWithPlayerInfo()
    {
        Run((world,scene,output,source)=>
        {
            string root=Path.GetFullPath(Path.Combine(AppContext.BaseDirectory,"..","..","..",".."));
            RuntimeFontCatalog.Configure(root);
            using var icons=new LootIconCatalog(Path.Combine(root,"launcher","web","icons"));
            using var commands=new PlayerHudController(_=>true,()=>true,a=>a());
            var state=PlayerHudStateTests.Full();state["groups"]["vitals"]["hp"]=new JArray(0,1000);state["groups"]["vitals"]["paused"]=true;
            commands.TakeUiData("pi:"+PlayerHudStateTests.Encode(state));
            using var resources=PlayerInfoSplitSurface.CreateLive(output,output,commands.State);
            using var main=new NativeHudOverlay(output,output);
            var router=new LauncherCommandRouter(null,_=>{},()=>{},()=>{},()=>{},_=>{});
            var right=new RightContextWidget(output,router,MapHudDataCatalog.FromPayload(new MapHudPayload {ProtocolVersion=1,Hotspots=new()}));
            var safe=new SafeExitPanelWidget(output,router);
            var combo=new ComboWidget(output);combo.ForceGameReady(true);
            var toast=new ToastWidget(output);
            var loot=new LootFeedWidget(output,icons);
            var notch=new NotchWidget(output,new FpsRingBuffer(300),root,()=>{},()=>{},()=>{},_=>{});
            var tooltip=new NativeTooltipWidget(output,icons,()=>1f);
            var npc=new NpcMenuWidget(output);
            var guidance=new NativeGuidanceWidget(output,GuidanceCatalog.FromJson(File.ReadAllText(Path.Combine(root,"launcher","data","guidance-catalog.json"))));
            var dialogue=new NativeDialogueWidget(output);
            var widgets=new INativeHudWidget[]{right,safe,combo,toast,loot,notch,tooltip,npc,guidance,dialogue};
            foreach(var widget in widgets)main.AddWidget(widget);
            main.HandleUiData("s:1|g:1000|k:20");right.SetReady();notch.ForceGameReadyForTest(true);notch.BeginExpandForTest();notch.Tick(2000);
            combo.OnNotchNotice("combo","DFA 连击",Color.Orange);combo.Tick(100);
            main.AddMessage("完整主 HUD 像素夹具");
            loot.AddEvent("material","测试物资",2,"fixture","",direction:"gain");
            dialogue.ShowFrame(new NativeDialogueFrame {RequestId="fixture-dialogue",SceneId="fixture-scene",Revision=1,
                Name="角色",Text="原有绘制器与输入目标，合入同一世界输出。",LineIndex=0,LineCount=2,PortraitKey="",Expression="普通",ImageAction="clear"});
            dialogue.TypingIntervalMs=1;dialogue.Tick(5000);
            using var coordinator=new WorldCompositorController(output,output,()=>IntPtr.Zero,()=>false,_=>{},root,()=>false,_=>{},()=>{});
            using var runtime=new PlayerHudRuntime(output,output,resources,commands,Path.Combine(root,"launcher","web","icons"),main,shareMainHud:true);
            var observed=new CommitCount();main.SetCommitObserver(observed);
            foreach(var surface in runtime.PresentationSurfaces)surface.SetCommitObserver(observed);
            var bottom=new RecordedScene(new OpaqueHudRasterScene(world,2));
            var resource=new RecordedScene(new OpaqueHudRasterScene(world,1));
            var buff=new RecordedScene(new OpaqueHudRasterScene(world,3));
            var top=new RecordedScene(new OpaqueHudRasterScene(world,4));
            Rectangle bounds=output.RectangleToScreen(output.ClientRectangle);
            coordinator.BottomPresentation.Adopt(bottom,bounds,true);coordinator.ResourcePresentation.Adopt(resource,bounds,true);
            coordinator.BuffPresentation.Adopt(buff,bounds,true);coordinator.MainHudPresentation.Adopt(top,bounds,true);
            runtime.SetSharedWorld(coordinator);runtime.SetReady();main.SetReady();
            Pump(()=>bottom.Current!=null&&resource.Current!=null&&buff.Current!=null&&top.Current!=null,scene,"complete main HUD rasters");
            // Freeze fixture animation only after the actual painters submitted.
            // This is a pixel/submit oracle; gameplay animation has separate gates.
            FreezeHudTimers(main);Application.DoEvents();FreezeHudTimers(main);
            Raster[] layers={bottom.Current,resource.Current,buff.Current,top.Current};
            byte[] expected=ComposeRasters(1024,576,layers);
            var frame=PixelsUntil(world,scene,p=>SamePixels(p,expected),"complete HUD composition");
            Assert.False(SamePixels(frame,ComposeRasters(1024,576,top.Current,bottom.Current,resource.Current,buff.Current)),"Main dialogue must remain above resources and bottom.");
            Assert.Equal(4u,world.ReadHudRaster().VisibleLayers);Assert.False(main.Visible);
            Assert.All(runtime.PresentationSurfaces,p=>Assert.False(p.Visible));Assert.Equal(0,observed.Count);Assert.Equal(0,resources.Counters.CommitCount);
            var captured=Grab(world,false);Assert.True(Pixel(captured,50,50,140,80,30));
            string directory=Path.Combine(root,"tmp","hud-main-unit");Directory.CreateDirectory(directory);
            File.WriteAllText(Path.Combine(directory,"rasters.json"),JsonConvert.SerializeObject(new {
                candidate=Environment.GetEnvironmentVariable("CF7_TEST_SHARED_WORLD_CANDIDATE"),width=1024,height=576,layers,
                registeredWidgets=widgets.Select(w=>w.GetType().Name),frozenAnimation=true},Formatting.Indented));

            // A failed lower member cannot leave main HUD underneath legacy HWNDs.
            coordinator.ResourcePresentation.Adopt(null,Rectangle.Empty,false);
            Pump(()=>world.ReadHudRaster().VisibleLayers==0,scene,"all four displays retired before fallback");
            Assert.False(main.UsesSharedPresentation);
            coordinator.ResourcePresentation.Adopt(resource,bounds,true);
            Pump(()=>world.ReadHudRaster().VisibleLayers==4,scene,"complete unit recovery");FreezeHudTimers(main);
            Assert.True(main.UsesSharedPresentation);Assert.False(main.Visible);
            // Mirror the production panel-host suspension of both companions.
            main.Suspend();runtime.Suspend();
            Pump(()=>world.ReadHudRaster().VisibleLayers==0,scene,"panel suspension");
            main.Resume();runtime.Resume();
            Pump(()=>world.ReadHudRaster().VisibleLayers==4,scene,"panel recovery");FreezeHudTimers(main);
            Assert.False(main.Visible);Assert.All(runtime.PresentationSurfaces,p=>Assert.False(p.Visible));
            Console.WriteLine(JsonConvert.SerializeObject(new {phase="complete_main_hud",registeredWidgets=widgets.Length,visibleNativeLayers=4,
                allLegacyDisplaysHidden=true,exactRgbTolerance=2,sourceFeedback=false,physicalInputVerified=false,gameplayExecuted=false}));
            resources.BeginShutdown().GetAwaiter().GetResult();
        },new Size(1024,576));
    }
    private static void FreezeHudTimers(NativeHudOverlay hud)
    {
        foreach(string name in new[]{"_animTick","_renderCoalesceTimer"})
            (typeof(NativeHudOverlay).GetField(name,BindingFlags.Instance|BindingFlags.NonPublic)?.GetValue(hud) as System.Windows.Forms.Timer)?.Stop();
    }
}
