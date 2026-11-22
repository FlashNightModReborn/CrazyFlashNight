using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Linq;
using System.Reflection;
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

internal sealed class OrderOneEvidenceAttribute : FactAttribute
{
    public OrderOneEvidenceAttribute(string variable)
    {
        if (string.IsNullOrEmpty(Environment.GetEnvironmentVariable(variable))) Skip="Explicit Order 1 output path required.";
    }
}

public sealed partial class OpaqueHudGpuTests
{
    internal static string HudRoot => Path.GetFullPath(Path.Combine(AppContext.BaseDirectory,"..","..","..",".."));
    internal static JObject HudPacket(int focus,int buffs,int allies)
    {
        var packet=PlayerHudStateTests.Full();
        var groups=packet["groups"];
        string[] skills=["闪现","拔刀术","铁布衫","小跳","寸拳","迅斩","凶斩","龙斩","旋风腿","日字冲拳","空间斩","瞬步斩"];
        string[] keys=["Space","U","I","O","P","L","H","G","C","B","N","M"];
        string[] faces=["敌人-不明士兵","敌人-防护服士兵","敌人-军阀狙击兵","敌人-日本军官","敌人-高级防护服士兵"];
        string[] targets=["护送医护专家","行动研究员","重装机甲队长","机甲指挥官","前线交战员"];
        string[] names=["中毒","能抗","破甲","减速","神之","强韧","战体","电抗","坚甲","防御","暴刃","重力","回血","止血","过载","铁壁"];
        var v=groups["vitals"];
        v["name"]="审判日行刑官";v["level"]=99;v["hp"]=new JArray(7017,8000);v["mp"]=new JArray(2352,2352);
        v["sp"]=2515;v["shield"]=new JArray(960,1200);v["shieldDetail"]=PlayerHudResourceFactsTests.Shield("manual");v["shieldDetail"]["strength"]=80;
        v["poiseDetail"]=new JObject{["threshold"]=.5,["hasStaggerBand"]=true,["phase"]="buffer"};
        v["poise"]=.88;v["experience"]=new JArray(123456789,100000000,150000000);
        var combat=groups["combat"];combat["mode"]="长枪副武器";combat["ammo"]=new JArray("31","360","8","32");
        combat["deck"]=new JObject{["points"]=50,["initial"]=100,["equipment"]="高频太刀",["power"]=1490};
        groups["loadout"]["bank"]=1;
        for(int i=0;i<4;i++)
        {
            var drug=groups["loadout"]["drugs"][i];drug["slot"]=4+i;drug["count"]=6+i;
            drug["name"]=drug["icon"]=i%2==0?"普通hp药剂":"普通mp药剂";
        }
        for(int i=0;i<12;i++)
        {
            var skill=groups["loadout"]["skills"][i];skill["keyLabel"]=keys[i];skill["skillKey"]=skill["iconKey"]=skills[i];
        }
        groups["coldSkills"]=new JArray(skills.Select((s,i)=> new JObject {["name"]=s,["icon"]=s,["key"]=i%2==0?"↓→A":"↑→S",
            ["level"]=3,["ready"]=i%4!=0,["step"]=i%4==0?60:0,["total"]=300,["blocked"]=i==9}));
        groups["buffs"]=new JArray(Enumerable.Range(0,buffs).Select(i=>new JObject {["id"]="status"+i,["timed"]=i!=15,["total"]=1800,
            ["remaining"]=i==0?60:570+i*6,["info"]=new JObject {["name"]=names[i%names.Length],["description"]="持续状态",
                ["polarity"]=i%6==0?"harm":"benefit",["stacks"]=i==1?3:0}}));
        groups["buffs"][1]["source"]=new JObject{["kind"]="drug",["slot"]=0,["key"]="普通hp药剂"};
        groups["focusTarget"]=new JArray(Enumerable.Range(0,focus).Select(i=>new JObject{["id"]=i+1,["role"]=i==0?"protect":i==2?"boss":"combat",
            ["name"]=targets[i],["icon"]=faces[i],["hp"]=new JArray(696+i*25,1200)}));
        JObject Ally(int i)=>new(){["slot"]=i>=20?-1:i,["id"]=100+i,["generation"]=1,["role"]="merc",["name"]="援军"+(i+1),["icon"]=faces[i%5],
            ["hp"]=new JArray(840-i*17,1000),["shield"]=new JArray(0,0),["protected"]=false,["down"]=false};
        groups["allies"]=new JObject{["rows"]=new JArray(Enumerable.Range(0,Math.Min(20,allies)).Select(Ally)),
            ["overflow"]=new JArray(Enumerable.Range(20,Math.Max(0,allies-20)).Select(Ally))};
        return packet;
    }
    private static RightContextWidget Quest(Control anchor)
    {
        var router=new LauncherCommandRouter(null,_=>{},()=>{},()=>{},()=>{},_=>{});
        var widget=new RightContextWidget(anchor,router,MapHudDataCatalog.FromPayload(new MapHudPayload{ProtocolVersion=1,Hotspots=new()}),MapDisplayPreference.Off);
        widget.ForceGameReady(true);widget.ForceDeliverState(true,"base",true,"0");
        widget.ApplyDeliveryState("order1",new TaskDestinationChoices{Status="ready",Token="1",Choices=[
            new TaskDestinationChoices.Choice{Id="1",TaskName="斩杀大 boss 僵尸",LocationName="地下一层",NpcName="可交付"}]});
        NativeHudOverlay.ResolveAndProjectRightContextSlotOwner(widget,null);
        return widget;
    }

    [Theory]
    [InlineData(1f)] [InlineData(1.5625f)] [InlineData(1.875f)]
    public void LiveMotifsPreserveAuthoredCoverage(float scale)
    {
        using var motion=new PlayerHudHpMotion();
        using var direct=new SkiaSharp.SKBitmap(240,240);
        using var cached=new SkiaSharp.SKBitmap(240,240);
        using var expected=new SkiaSharp.SKCanvas(direct);
        using var actual=new SkiaSharp.SKCanvas(cached);
        foreach(var canvas in new[]{actual,expected}) {canvas.Translate(120.1875f,120.75f);canvas.Scale(scale,scale);}
        int worst=0;
        foreach(var background in new[]{SkiaSharp.SKColors.Transparent,new SkiaSharp.SKColor(180,62,46)})
        for(int phase=0;phase<100;phase++)
        {
            actual.Clear(background);expected.Clear(background);
            motion.DrawMotifs(actual,phase);motion.DrawMotifPaths(expected,phase);
            var a=direct.GetPixelSpan();var b=cached.GetPixelSpan();
            for(int i=0;i<a.Length;i++) worst=Math.Max(worst,Math.Abs(a[i]-b[i]));
        }
        Assert.InRange(motion.SilhouetteBytes,1L,4L*1024*1024);
        Assert.True(worst<=2,$"Maximum channel delta {worst} at scale {scale}");
    }

    [OrderOneEvidence("CF7_ORDER1_PROOFS")]
    public void RenderOrderOneHudProofs()
    {
        string dir=Environment.GetEnvironmentVariable("CF7_ORDER1_PROOFS");
        Directory.CreateDirectory(dir);
        RuntimeFontCatalog.Configure(HudRoot);
        using var owner=new Form {AutoScaleMode=AutoScaleMode.None,FormBorderStyle=FormBorderStyle.None};
        using var anchor=new Panel{Size=new Size(1920,1080)};owner.Controls.Add(anchor);_=anchor.Handle;
        using var controller=new PlayerHudController(_=>true,()=>true,a=>a());
        var root=Path.Combine(HudRoot,"launcher","web","icons");
        using var catalog=new LootIconCatalog(root,Path.Combine(HudRoot,"launcher","web","assets","enemy-portraits"));
        using var bottom=new PlayerHudBottomWidget(anchor,controller,root);
        using var buffs=new PlayerHudBuffWidget(anchor,controller);
        using var focus=new PlayerHudFocusTargetWidget(anchor,controller,catalog);
        using var allies=new PlayerHudAllyWidget(anchor,controller,catalog);
        using var right=Quest(anchor);
        var fps=new FpsRingBuffer(300);fps.Push(30);
        using var notch=new NotchWidget(anchor,fps,HudRoot,()=>{},()=>{},()=>{},_=>{});
        notch.ForceGameReadyForTest(true);notch.ForceCurrenciesForTest(1809207,1869577);
        
        notch.SetStatusItem("wave","波次 3/3 · 歼灭模式","残敌 12",NativeHudTheme.Cyan);
        notch.Tick(500);
        using var combo=new ComboWidget(anchor);
        combo.ForceGameReady(true);combo.OnNotchNotice("combo","↓↘→ A · 升龙斩",Color.Gold);combo.Tick(180);
        using var loot=new LootFeedWidget(anchor,catalog);
        foreach(var (name,count) in new[]{("高强度合金",3),("突击步枪通用弹药",36),("电感芯片",1),("能量电池",2),("金钱",450)})
            loot.AddEvent("material",name,count,"order1",name,direction:"gain");
        Application.DoEvents();loot.Tick(180);Assert.True(loot.Visible);
        var origin=anchor.PointToScreen(Point.Empty);
        var assets=PlayerInfoSvgAssetContract.LoadProductionEmbedded(false);
        var plan=PlayerInfoRasterPlanner.Create(assets,new Rectangle(0,0,1920,1080),1,liveReadouts:true);
        using var batch=new PlayerInfoSvgRasterizer().Bake(plan,CancellationToken.None);
        using var resourceBitmap=new Bitmap(plan.TightPhysicalBounds.Width,plan.TightPhysicalBounds.Height,PixelFormat.Format32bppPArgb);
        using var frame=new Bitmap(1920,1080,PixelFormat.Format32bppPArgb);
        var packet=HudPacket(4,16,4);int seq=0;
        void Send()
        {
            packet["seq"]=++seq;controller.TakeUiData("pi:"+PlayerHudStateTests.Encode(packet));Assert.Equal(seq,controller.State.Snapshot.Sequence);
        }
        void Paint()
        {
            var model=new PlayerInfoAnimationModel();model.ApplyProduction(controller.State.Snapshot.Vitals);
            using var resource=new PlayerInfoWidget(assets,model){LiveVitals=controller.State.Snapshot.Vitals};
            resource.Paint(resourceBitmap,batch,plan);
            using var g=Graphics.FromImage(frame);
            g.Clear(Color.FromArgb(37,42,44));
            using var grid=new Pen(Color.FromArgb(44,49,51));
            for(int x=0;x<1920;x+=32)g.DrawLine(grid,x,0,x,1080);
            for(int y=0;y<1080;y+=32)g.DrawLine(grid,0,y,1920,y);
            g.SmoothingMode=SmoothingMode.AntiAlias;
            bottom.Paint(g,1,origin);buffs.Paint(g,1,origin);g.DrawImageUnscaled(resourceBitmap,plan.TightPhysicalBounds.Location);
            focus.Paint(g,1,origin);allies.Paint(g,1,origin);notch.Paint(g,1,origin);combo.Paint(g,1,origin);loot.Paint(g,1,origin);right.Paint(g,1,origin);
        }
        Send();Paint();frame.Save(Path.Combine(dir,"full-load-1080p.png"),ImageFormat.Png);
        packet=HudPacket(5,84,23);Send();Paint();frame.Save(Path.Combine(dir,"allies-23-1080p.png"),ImageFormat.Png);
        var toggle=PlayerHudBuffLayout.Toggle(true);
        var click=anchor.PointToScreen(new Point((int)((toggle.X+10)*1.875),(int)((toggle.Y+10)*1.875)));
        foreach(var kind in new[]{MouseEventKind.Down,MouseEventKind.Up,MouseEventKind.Click})
            buffs.OnMouseEvent(new MouseEventArgs(MouseButtons.Left,1,click.X,click.Y,0),kind);
        Assert.True(buffs.ScreenBounds.Top<origin.Y+700);
        Paint();frame.Save(Path.Combine(dir,"drawer-56-1080p.png"),ImageFormat.Png);
        packet=HudPacket(4,16,4);
        const int stripHeight=125;
        using var strips=new Bitmap(1920,stripHeight*3);
        using var montage=Graphics.FromImage(strips);
        string[] modes=["空手","兵器","手雷"];
        for(int i=0;i<3;i++)
        {
            packet["groups"]["combat"]["mode"]=modes[i];packet["groups"]["combat"]["weapon"]["visible"]=i==1;
            packet["groups"]["combat"]["deck"]["points"]=i==0?0:50;
            packet["groups"]["combat"]["deck"]["equipment"]=new[]{"钢制手套","高频太刀","高爆破片雷"}[i];
            packet["groups"]["vitals"]["sp"]=i==0?0:2515;
            Send();Paint();
            montage.DrawImage(frame,new Rectangle(0,i*stripHeight,1920,stripHeight),new Rectangle(0,1080-stripHeight,1920,stripHeight),GraphicsUnit.Pixel);
        }
        strips.Save(Path.Combine(dir,"deck-variants-1080p.png"),ImageFormat.Png);
    }

    [OrderOneEvidence("CF7_ORDER1_READOUT")]
    public void MeasureWarmHpDigitBlits()
    {
        var layout=PlayerInfoCompositionRecipe.HpCurrent;
        var gauge=PlayerInfoSvgAssetContract.LoadProductionEmbedded(false).Gauges["hp"];
        float scale=(float)(1.875*gauge.StageMatrix.A);
        using var glyphs=new PlayerHudNumberGlyphs();
        using var pixels=new SkiaSharp.SKBitmap(160,80);
        using var canvas=new SkiaSharp.SKCanvas(pixels);
        canvas.Translate(80,40);
        canvas.Scale(scale);
        var times=new List<double>();
        for(int i=0;i<260;i++)
        {
            canvas.Clear(SkiaSharp.SKColors.Transparent);
            long start=Stopwatch.GetTimestamp();
            glyphs.DrawLive(canvas,layout.FontId,i%2==0?"7017":"6850",layout.FontPixels,layout.AnchorX,
                layout.BaselineY,layout.Alignment,SkiaSharp.SKColors.White,layout.GlowSigmaPixels,
                layout.GlowColor??SkiaSharp.SKColors.Transparent,1024*1024);
            if (i>=20) times.Add(Stopwatch.GetElapsedTime(start).TotalMilliseconds);
        }
        times.Sort();
        double P(double q)=>times[(int)Math.Ceiling(q*times.Count)-1];
        File.WriteAllText(Environment.GetEnvironmentVariable("CF7_ORDER1_READOUT"),
            JsonConvert.SerializeObject(new {count=times.Count,p50=P(.5),p95=P(.95),p99=P(.99),max=P(1)},Formatting.Indented));
    }

    [System.Runtime.InteropServices.DllImport("gdi32.dll",EntryPoint="GdiFlush")]
    private static extern bool GdiFlushForOrderOne();

    // Owned test windows may run on a session without a foreground game.
    private sealed class HudLayer(Form owner) : NativeHudOverlay(owner,owner)
    {
        protected override bool IsOwnerSessionForeground()=>true;
    }

    [OrderOneEvidence("CF7_ORDER1_BENCH")]
    public void MeasureOrderOneNativeFrames()
    {
        string report=Environment.GetEnvironmentVariable("CF7_ORDER1_BENCH");
        var results=new List<object>();
        foreach(var config in new[]{(4,16,4),(5,84,0),(5,84,23)})
        {
            Run((world,scene,output,source)=>
            {
                var size=new Size(1920,1080);
                Assert.Equal(size,output.ClientSize);
                RuntimeFontCatalog.Configure(HudRoot);
                using var controller=new PlayerHudController(_=>true,()=>true,a=>a());
                var packet=HudPacket(config.Item1,config.Item2,config.Item3);
                int seq=1;
                controller.TakeUiData("pi:"+PlayerHudStateTests.Encode(packet));Assert.Equal(seq,controller.State.Snapshot.Sequence);
                var bounds=output.RectangleToScreen(output.ClientRectangle);
                WorldRasterPresentation Presentation(int index)
                {
                    var result=new WorldRasterPresentation();
                    result.Adopt(new OpaqueHudRasterScene(world,index),bounds,true);
                    return result;
                }
                using var hpPresentation=Presentation(1);
                using var bottomPresentation=Presentation(2);
                using var buffPresentation=Presentation(3);
                using var mainPresentation=Presentation(4);
                var iconDir=Path.Combine(HudRoot,"launcher","web","icons");
                using var icons=new LootIconCatalog(iconDir,Path.Combine(HudRoot,"launcher","web","assets","enemy-portraits"));
                using var bottom=new HudLayer(output){PartialRepaintEnabled=true};
                using var buff=new HudLayer(output){PartialRepaintEnabled=true};
                using var main=new HudLayer(output){PartialRepaintEnabled=true};
                bottom.SetSharedPresentation(bottomPresentation);buff.SetSharedPresentation(buffPresentation);main.SetSharedPresentation(mainPresentation);
                var deck=new PlayerHudBottomWidget(output,controller,iconDir);
                var focus=new PlayerHudFocusTargetWidget(output,controller,icons);
                var allies=new PlayerHudAllyWidget(output,controller,icons);
                var combo=new ComboWidget(output);combo.ForceGameReady(true);
                var fps=new FpsRingBuffer(300);fps.Push(30);
                var notch=new NotchWidget(output,fps,HudRoot,()=>{},()=>{},()=>{},_=>{});
                notch.ForceGameReadyForTest(true);notch.ForceCurrenciesForTest(1809207,1869577);
                notch.SetStatusItem("wave","波次 3/3 · 歼灭模式","残敌 12",NativeHudTheme.Cyan);
                var loot=new LootFeedWidget(output,icons);
                foreach (var name in new[]{"高强度合金","突击步枪通用弹药","电感芯片","能量电池","金钱"})
                    loot.AddEvent("material",name,3,"order1",name,direction:"gain");
                Application.DoEvents();loot.Tick(180);Assert.True(loot.Visible);
                main.AddWidget(combo);main.AddWidget(loot);main.AddWidget(Quest(output));main.AddWidget(notch);
                bottom.AddWidget(deck);bottom.AddWidget(new PlayerHudBuffWidget(output,controller));
                buff.AddWidget(focus);buff.AddWidget(allies);
                bottom.SetReady();buff.SetReady();main.SetReady();
                var assets=PlayerInfoSvgAssetContract.LoadProductionEmbedded(false);
                var plan=PlayerInfoRasterPlanner.Create(assets,bounds,1,liveReadouts:true);
                using var batch=new PlayerInfoSvgRasterizer().Bake(plan,CancellationToken.None);
                var model=new PlayerInfoAnimationModel();model.ApplyProduction(controller.State.Snapshot.Vitals);
                using var resource=new PlayerInfoWidget(assets,model){LiveVitals=controller.State.Snapshot.Vitals};
                bool tracePasses=Environment.GetEnvironmentVariable("CF7_ORDER1_TRACE")=="1";
                var trace=tracePasses ? new PlayerInfoPaintTrace() : null;
                resource.PaintTrace=trace;
                using var dib=new PlayerInfoLayeredDibSurface(plan.TightPhysicalBounds.Width,plan.TightPhysicalBounds.Height);
                const BindingFlags flags=BindingFlags.Instance|BindingFlags.NonPublic;
                var total=new List<double>();var transitions=new List<double>();
                var costs=new Dictionary<string,List<double>>();
                void Cost(string key,double ms) {if(!costs.TryGetValue(key,out var list)) costs[key]=list=new();list.Add(ms);}
                var surfaces=new Dictionary<string,List<double>>();
                foreach(string name in new[]{"bottom","resources","buff","main"}) surfaces[name]=new();
                bool measure=false,transition=false;
                Action<double,double,int,int> Observe(string layer)=>(paint,submit,w,h)=>
                {
                    if (!measure) return;
                    surfaces[layer].Add(paint+submit);
                    Cost(layer+"Paint",paint);Cost(layer+"Submit",submit);
                    if (layer=="resources" && transition) transitions.Add(paint+submit);
                };
                main.RenderTimingObserver=Observe("main");bottom.RenderTimingObserver=Observe("bottom");
                buff.RenderTimingObserver=Observe("buff");
                var groups=packet["groups"];
                string Delta(string name)=>PlayerHudStateTests.Encode(new JObject {["v"]=1,["epoch"]=1,["seq"]=++seq,
                    ["full"]=false,["visible"]=true,["groups"]=new JObject{[name]=groups[name]}});
                // Flush dispatches in the current frame so boundaries include actual dirty paint and native upload.
                var pending=typeof(NativeHudOverlay).GetField("_renderPending",flags);
                var flush=typeof(NativeHudOverlay).GetMethod("RenderToBitmapAndCommit",flags);
                void Dispatch(NativeHudOverlay hud)
                {
                    if (!(bool)pending.GetValue(hud)) return;
                    pending.SetValue(hud,false);
                    flush.Invoke(hud,null);
                }
                var entryCounter=typeof(NativeHudOverlay).GetProperty("DeckPaintEntries",flags);
                long DeckEntries()=>entryCounter==null ? 0 : (long)entryCounter.GetValue(bottom);
                long wasted=0;int buffOnly=0;
                var clock=Stopwatch.StartNew();
                for(int i=0;i<420;i++)
                {
                    string wire;
                    int phase=i%30;
                    bool onlyBuff=phase%6==2;
                    if (phase==0)
                    {
                        groups["vitals"]["hp"][0]=((i/30)%4==0?5150:(i/30)%2==0?6850:7017)-i%7;
                        wire=Delta("vitals");
                    }
                    else if(onlyBuff)
                    {
                        groups["buffs"][1]["remaining"]=570+(i%17)*30;
                        wire=Delta("buffs");
                    }
                    else
                    {
                        int row=i%config.Item1;
                        wire=$"~1,1,{++seq};f,{row},{row+1},{680+i%330},1200,0";
                        if(config.Item3==23) wire+=$";a,{i%20},{100+i%20},1,{650+i%300},1000,0,0,0";
                    }
                    measure=i>=60;transition=phase<15;
                    long deckBefore=DeckEntries();
                    ulong submitsBefore=bottomPresentation.Uploads;
                    long start=Stopwatch.GetTimestamp();
                    controller.TakeUiData("pi:"+wire);Assert.Equal(seq,controller.State.Snapshot.Sequence);
                    if(measure) Cost("packet",Stopwatch.GetElapsedTime(start).TotalMilliseconds);
                    if(phase==0) combo.OnNotchNotice("combo","连击 "+i,Color.Orange);
                    combo.Tick(33);loot.Tick(33);notch.Tick(33);deck.Tick(33);focus.Tick(33);allies.Tick(33);
                    Dispatch(bottom);Dispatch(buff);Dispatch(main);
                    long resourceStart=Stopwatch.GetTimestamp();
                    var vitals=controller.State.Snapshot.Vitals;
                    if (resource.LiveVitals!=vitals) {model.ApplyProduction(vitals);resource.LiveVitals=vitals;}
                    transition=model.WantsAnimationTick || phase==0;
                    model.Tick(33);resource.AdvanceLiveDecoration(33);
                    var damage=resource.PaintRetained(dib.Bitmap,batch,plan);
                    GdiFlushForOrderOne();
                    Assert.True(hpPresentation.TryPresent(dib.Pixels,dib.Width,dib.Height,dib.Width*4,plan.TightPhysicalBounds.Location,
                        damage.HasValue?[damage.Value]:null));
                    double resourceMs=Stopwatch.GetElapsedTime(resourceStart).TotalMilliseconds;
                    if (trace!=null && measure && phase==0) Cost("hitReadouts",trace.WallTicks[(int)ResourcePass.Readouts]*1000d/Stopwatch.Frequency);
                    if (trace!=null && measure)
                        foreach (var pass in Enum.GetValues<ResourcePass>()) Cost("res"+pass,trace.WallTicks[(int)pass]*1000d/Stopwatch.Frequency);
                    if(measure) {surfaces["resources"].Add(resourceMs);if(transition) transitions.Add(resourceMs);}
                    scene.Commit();
                    if(measure)
                    {
                        var duration=Stopwatch.GetElapsedTime(start).TotalMilliseconds;
                        total.Add(duration);Cost(phase==0?"hitFrame":onlyBuff?"buffFrame":"focusFrame",duration);
                        if(onlyBuff) {buffOnly++;wasted+=entryCounter!=null ? DeckEntries()-deckBefore :
                            bottomPresentation.Uploads>submitsBefore ? bottom.LastPaintedWidgetCount-1 : 0;}
                    }
                    var wait=(int)((i+1)*1000d/30-clock.Elapsed.TotalMilliseconds);
                    if(wait>0) Thread.Sleep(wait);
                }
                object Stats(List<double> values)
                {
                    Assert.NotEmpty(values);values.Sort();
                    double P(double q)=>Math.Round(values[(int)Math.Ceiling(q*values.Count)-1],4);
                    return new {n=values.Count,p50=P(.5),p95=P(.95),p99=P(.99),max=P(1)};
                }
                Assert.True(bottomPresentation.Uploads>0 && buffPresentation.Uploads>0 && mainPresentation.Uploads>0 && hpPresentation.Uploads>0);
                results.Add(new {uploads=new {bottom=bottomPresentation.Uploads,buff=buffPresentation.Uploads,main=mainPresentation.Uploads,resources=hpPresentation.Uploads},focus=config.Item1,buffs=config.Item2,cold=12,allies=config.Item3,
                    total=Stats(total),parts=costs.ToDictionary(k=>k.Key,k=>Stats(k.Value)),surfaces=surfaces.ToDictionary(k=>k.Key,k=>Stats(k.Value)),
                    resourceHitWindow=Stats(transitions),buffOnlyFrames=buffOnly,buffOnlyDeckPaints=wasted});
                File.WriteAllText(report,JsonConvert.SerializeObject(results,Formatting.Indented));
            },new Size(1920,1080),TimeSpan.FromMinutes(2),requireWorldFrame:false);
        }
    }
}
