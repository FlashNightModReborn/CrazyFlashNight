using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.Hud;
using CF7Launcher.Guardian.Hud.PlayerInfo;
using CF7Launcher.Guardian.WorldCompositor;
using CF7Launcher.Tests.Guardian.Hud.PlayerInfo;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian;

public sealed class NativeHudDirtyRegionTests
{
    [Fact]
    public void DamageMatchesFullPaintAcrossAlphaOverlapDisjointRegionsAndLifecycle()
    {
        using var owner=new Form();
        using var hud=new Hud(owner);
        using var presentation=new WorldRasterPresentation();
        presentation.Adopt(new Scene(),new Rectangle(0,0,1024,576),true);
        hud.SetSharedPresentation(presentation);hud.PartialRepaintEnabled=true;
        var first=new Widget(new Rectangle(20,20,80,50),Color.FromArgb(170,220,30,60));
        var overlap=new Widget(new Rectangle(65,35,100,65),Color.FromArgb(100,30,70,220));
        var distant=new Widget(new Rectangle(700,60,90,50),Color.FromArgb(140,20,220,60));
        var widgets=new[]{first,overlap,distant};
        foreach(var widget in widgets)hud.AddWidget(widget);
        hud.RenderTimingObserver=(_,_,_,_)=>{};hud.SetReady();
        Check(hud,widgets);
        int distantPaints=distant.Paints;
        first.Color=Color.FromArgb(45,255,80,80);first.Hole=24;first.Repaint();Render(hud);
        Assert.Equal(2,hud.LastPaintedWidgetCount);Assert.Equal(distantPaints,distant.Paints);
        Assert.True(hud.LastPaintedPixels<10000);Check(hud,widgets);

        // Two separate damage islands must not repaint/blend the untouched gap.
        first.Hole=0;first.Repaint();distant.Color=Color.FromArgb(80,240,180,20);distant.Repaint();Render(hud);
        Assert.Equal(3,hud.LastPaintedWidgetCount);Check(hud,widgets);
        overlap.Bounds=new Rectangle(210,140,135,90);overlap.Layout();Check(hud,widgets);
        first.Visible=false;first.Layout();Check(hud,widgets);
        first.Visible=true;first.Bounds=new Rectangle(5,5,120,70);first.Layout();Check(hud,widgets);
        hud.RemoveWidget(overlap);Check(hud,new[]{first,distant});
        hud.AddWidget(overlap);Check(hud,new[]{first,distant,overlap});
        first.Repaint(unknownSender:true);Render(hud);
        Assert.Equal(3,hud.LastPaintedWidgetCount);Check(hud,new[]{first,distant,overlap});
        hud.Suspend();first.Color=Color.FromArgb(70,20,30,220);first.Repaint();hud.Resume();
        Check(hud,new[]{first,distant,overlap});
        hud.SetSharedPresentation(null);hud.SetReady();
        first.Repaint();Render(hud);Assert.Equal(3,hud.LastPaintedWidgetCount);
        Check(hud,new[]{first,distant,overlap});
    }

    [Fact]
    public void RepaintRaisedDuringPaintIsRetainedForTheNextFrame()
    {
        using var owner=new Form();using var hud=new Hud(owner);
        using var presentation=new WorldRasterPresentation();
        presentation.Adopt(new Scene(),new Rectangle(0,0,1024,576),true);
        hud.SetSharedPresentation(presentation);hud.PartialRepaintEnabled=true;
        var first=new Widget(new Rectangle(10,10,30,30),Color.Red);
        var second=new Widget(new Rectangle(500,10,30,30),Color.Blue);
        hud.AddWidget(first);hud.AddWidget(second);hud.SetReady();
        first.DuringPaint=()=>{first.DuringPaint=null;second.Color=Color.Green;second.Repaint();};
        first.Repaint();Render(hud);Assert.Equal(1,hud.LastPaintedWidgetCount);
        Render(hud);Assert.Equal(1,hud.LastPaintedWidgetCount);Check(hud,new[]{first,second});
    }

    [Fact]
    public void ComboAnimationAndStableNotchRefreshMatchCompletePaint()
    {
        using var owner=new Form { AutoScaleMode=AutoScaleMode.None,FormBorderStyle=FormBorderStyle.None };
        using var anchor=new Panel { Size=new Size(1920,1080) };
        owner.Controls.Add(anchor);_=anchor.Handle;
        using var hud=new Hud(owner,anchor);
        using var presentation=new WorldRasterPresentation();
        presentation.Adopt(new Scene(),new Rectangle(anchor.PointToScreen(Point.Empty),anchor.Size),true);
        hud.SetSharedPresentation(presentation);hud.PartialRepaintEnabled=true;
        var fps=new FpsRingBuffer(60);fps.Push(30);
        var notch=new NotchWidget(anchor,fps,OpaqueHudGpuTests.HudRoot,()=>{},()=>{},()=>{},_=>{});
        notch.ForceGameReadyForTest(true);notch.ForceCurrenciesForTest(100,200);
        notch.SetStatusItem("wave","波次 3/3","残敌 12",NativeHudTheme.Cyan);notch.Tick(500);
        var combo=new ComboWidget(anchor);combo.ForceGameReady(true);combo.OnNotchNotice("combo","升龙斩",Color.Gold);
        hud.AddWidget(notch);hud.AddWidget(combo);hud.SetReady();
        var widgets=new INativeHudWidget[]{notch,combo};
        foreach(int elapsed in new[]{33,260,160,400,275})
        {
            combo.Tick(elapsed);notch.Tick(elapsed);Render(hud);Check(hud,widgets);
        }
    }

    [Theory]
    [InlineData(768, 4, false, false)]
    [InlineData(1024, 4, false, false)]
    [InlineData(1920, 4, false, false)]
    [InlineData(1920, 3, true, true)]
    [InlineData(1920, 4, false, true)]
    [InlineData(1920, 5, true, true)]
    [InlineData(1920, 8, true, true)]
    public void FocusHealthOnlyRepaintsTheChangedRowAndLeavesTheBuffRailUntouched(
        int width, int targetCount, bool protectFirst, bool paintEachPacket)
    {
        PlayerHudMotionSettings.Configure("full");
        using var owner = new Form { AutoScaleMode = AutoScaleMode.None,
            FormBorderStyle = FormBorderStyle.None, ClientSize = new Size(width,width*9/16) };
        using var anchor = new Panel { Size = new Size(width,width*9/16) };
        owner.Controls.Add(anchor);
        _ = anchor.Handle;
        using var hud = new Hud(owner,anchor);
        using var presentation = new WorldRasterPresentation();
        var origin = anchor.PointToScreen(Point.Empty);
        presentation.Adopt(new Scene(), new Rectangle(origin, anchor.ClientSize), true);
        hud.SetSharedPresentation(presentation);
        hud.PartialRepaintEnabled = true;
        hud.RenderTimingObserver = (_,_,_,_) => { };
        using var controller = new PlayerHudController(_ => true, () => true, action => action());
        var packet = PlayerHudStateTests.Full();
        packet["groups"]["buffs"] = new JArray(Enumerable.Range(0,10).Select(i => new JObject {
            ["id"] = "b"+i, ["timed"] = false, ["total"] = 0, ["remaining"] = 0 }));
        var rows = new JArray(Enumerable.Range(1,targetCount).Select(i => new JObject {
            ["id"] = i, ["role"] = protectFirst && i == 1 ? "protect" : "boss",
            ["name"] = new string('首',32), ["hp"] = new JArray(9999,10000) }));
        if (targetCount == 3) rows[2]["hits"] = 12;
        packet["groups"]["focusTarget"] = rows;
        controller.TakeUiData("pi:" + PlayerHudStateTests.Encode(packet));
        var buffs = new PlayerHudBuffWidget(anchor, controller);
        var focus = new PlayerHudFocusTargetWidget(anchor, controller);
        hud.AddWidget(buffs);
        hud.AddWidget(focus);
        hud.SetReady();
        Check(hud, new INativeHudWidget[]{buffs,focus});
        EventArgs damage = null;
        focus.RepaintRequested += (_, args) => damage = args;
        rows[0]["hp"][0] = 10000;
        packet["seq"] = 2;
        controller.TakeUiData("pi:" + PlayerHudStateTests.Encode(packet));
        var areas = Assert.IsType<HudRepaintRegions>(damage).Bounds;
        Assert.Equal(2, areas.Length);
        var nextRow = PlayerHudFocusTargetWidget.RowBounds(10,1,targetCount);
        Assert.All(areas, area => Assert.True(area.Bottom < origin.Y + nextRow.Top * width / 1024f));
        Assert.All(areas, area => Assert.False(Rectangle.Inflate(buffs.ScreenBounds,6,6).IntersectsWith(area)));
        void CheckFocusOnly([System.Runtime.CompilerServices.CallerLineNumber] int stageLine = 0)
        {
            Render(hud);
            Assert.Equal(1, hud.LastPaintedWidgetCount);
            try { Check(hud, new INativeHudWidget[]{buffs,focus}); }
            catch (Exception e) { throw new InvalidOperationException($"Focus paint at {width}, seq {packet["seq"]}, stage {stageLine}",e); }
        }
        void Submit()
        {
            packet["seq"] = (long)packet["seq"] + 1;
            controller.TakeUiData("pi:" + PlayerHudStateTests.Encode(packet));
        }
        CheckFocusOnly();
        rows[0]["hp"] = new JArray(200,1000);
        Submit(); CheckFocusOnly();
        Assert.Equal(protectFirst, focus.IsTargetCritical(1));
        focus.Tick(33); CheckFocusOnly(); // breathing
        rows[0]["hp"][0] = 0;
        Submit(); CheckFocusOnly(); // death
        rows[0]["hp"][0] = 770;
        rows[2]["hp"] = new JArray(223,1000);
        Submit(); CheckFocusOnly(); // revival and a compact card changing health together
        Assert.False(focus.IsTargetCritical(1));
        rows[0]["hits"] = 3;
        Submit(); CheckFocusOnly();
        focus.Tick(50); CheckFocusOnly(); // combo and critical pulse in a single frame
        foreach (int maximum in new[]{94,973,75748,123456,4343434,822222,888,9272,99999})
        {
            for (int i = 0; i < rows.Count; i++)
                rows[i]["hp"] = new JArray(maximum*(.38+i*.065),maximum);
            Submit();
            if (paintEachPacket) CheckFocusOnly();
        }
        if (!paintEachPacket) CheckFocusOnly(); // retained damage crosses the sixteen-rectangle upload budget
    }

    [Theory]
    [InlineData(1024,576)]
    [InlineData(1600,900)]
    [InlineData(1920,1080)]
    public void BuffDamageWithTwelveColdSkillsNeverEntersTheDeckPainter(int width,int height)
    {
        using var owner=new Form();
        using var anchor=new Panel{Size=new Size(width,height)};
        owner.Controls.Add(anchor);
        var origin=anchor.PointToScreen(Point.Empty);
        using var hud=new Hud(owner,anchor);
        using var presentation=new WorldRasterPresentation();
        presentation.Adopt(new Scene(),new Rectangle(origin,anchor.Size),true);
        hud.SetSharedPresentation(presentation);
        hud.PartialRepaintEnabled=true;
        using var controller=new PlayerHudController(_=>true,()=>true,a=>a());
        var packet=OpaqueHudGpuTests.HudPacket(4,84,4);
        Assert.True(controller.State.Receive(PlayerHudStateTests.Encode(packet),1));
        var deck=new PlayerHudBottomWidget(anchor,controller,System.IO.Path.Combine(OpaqueHudGpuTests.HudRoot,"launcher","web","icons"));
        var buffs=new PlayerHudBuffWidget(anchor,controller);
        hud.AddWidget(deck);
        hud.AddWidget(buffs);
        hud.SetReady();
        Assert.True(deck.HasColdRail);
        long entries=hud.DeckPaintEntries;
        for(int i=2;i<=4;i++)
        {
            packet["seq"]=i;
            packet["groups"]["buffs"][1]["remaining"]=600-i*30;
            if (i==4) packet["groups"]["buffs"][2]["remaining"]=30;
            Assert.True(controller.State.Receive(PlayerHudStateTests.Encode(packet),i));
            Render(hud);
            Assert.Equal(1,hud.LastPaintedWidgetCount);
            Assert.Equal(entries,hud.DeckPaintEntries);
            Check(hud,[deck,buffs]);
        }
    }

    private static void Render(NativeHudOverlay hud)=>typeof(NativeHudOverlay)
        .GetMethod("RenderToBitmapAndCommit",BindingFlags.Instance|BindingFlags.NonPublic).Invoke(hud,null);
    private static void Check(NativeHudOverlay hud,INativeHudWidget[] widgets)
    {
        var actual=(Bitmap)typeof(NativeHudOverlay).GetField("_composedBitmap",BindingFlags.Instance|BindingFlags.NonPublic).GetValue(hud);
        var origin=(Point)typeof(NativeHudOverlay).GetField("_hudOrigin",BindingFlags.Instance|BindingFlags.NonPublic).GetValue(hud);
        using var reference=new Bitmap(actual.Width,actual.Height,PixelFormat.Format32bppPArgb);
        using(var g=Graphics.FromImage(reference))
        {
            g.Clear(Color.Transparent);g.CompositingMode=CompositingMode.SourceOver;g.SmoothingMode=SmoothingMode.AntiAlias;
            g.TextRenderingHint=System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;
            foreach(var widget in widgets)if(widget.Visible)widget.Paint(g,1,origin);
        }
        Assert.Equal(Pixels(reference),Pixels(actual));
    }
    private static byte[] Pixels(Bitmap bitmap)
    {
        var data=bitmap.LockBits(new Rectangle(Point.Empty,bitmap.Size),ImageLockMode.ReadOnly,PixelFormat.Format32bppPArgb);
        try {var result=new byte[bitmap.Width*bitmap.Height*4];for(int y=0;y<bitmap.Height;y++)
            Marshal.Copy(data.Scan0+y*data.Stride,result,y*bitmap.Width*4,bitmap.Width*4);return result;}
        finally {bitmap.UnlockBits(data);}
    }
    private sealed class Hud : NativeHudOverlay
    {
        internal Hud(Form owner, Control anchor = null):base(owner,anchor ?? owner){}
        protected override bool IsOwnerSessionForeground()=>true;
    }
    private sealed class Scene:IWorldRasterScene
    {public void UploadHud(IntPtr pixels,int width,int height,int stride,int x,int y){}}
    private sealed class Widget:INativeHudWidget,INativeHudCompositeBoundsProvider
    {
        internal Rectangle Bounds;internal Color Color;internal int Hole,Paints;internal Action DuringPaint;
        internal Widget(Rectangle bounds,Color color){Bounds=bounds;Color=color;}
        public Rectangle ScreenBounds=>Bounds;
        public Rectangle CompositeBounds=>Rectangle.Inflate(Bounds,3,3);
        public bool Visible{get;set;}=true;
        public bool WantsAnimationTick=>false;
        public void Paint(Graphics g,float dpr,Point origin)
        {
            Paints++;DuringPaint?.Invoke();
            var rect=Bounds;rect.Offset(-origin.X,-origin.Y);
            using var path=new GraphicsPath(FillMode.Alternate);path.AddEllipse(rect);
            if(Hole>0)path.AddEllipse(rect.X+Hole,rect.Y+Hole/2,rect.Width-Hole*2,rect.Height-Hole);
            using var brush=new SolidBrush(Color);g.FillPath(brush,path);
            using var pen=new Pen(Color.FromArgb(100,255,255,255),4);g.DrawEllipse(pen,rect);
        }
        public bool TryHitTest(Point point)=>Bounds.Contains(point);
        public void OnMouseEvent(MouseEventArgs e,MouseEventKind kind){}
        public void Tick(int ms){}
        public event EventHandler BoundsOrVisibilityChanged;
        public event EventHandler RepaintRequested;
        public event EventHandler AnimationStateChanged{add{}remove{}}
        internal void Layout()=>BoundsOrVisibilityChanged?.Invoke(this,EventArgs.Empty);
        internal void Repaint(bool unknownSender=false)=>RepaintRequested?.Invoke(unknownSender?null:this,EventArgs.Empty);
    }
}
