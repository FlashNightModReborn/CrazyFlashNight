using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.Hud;
using CF7Launcher.Guardian.WorldCompositor;
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

    private static void Render(NativeHudOverlay hud)=>typeof(NativeHudOverlay)
        .GetMethod("RenderToBitmapAndCommit",BindingFlags.Instance|BindingFlags.NonPublic).Invoke(hud,null);
    private static void Check(NativeHudOverlay hud,Widget[] widgets)
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
        internal Hud(Form owner):base(owner,owner){}
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
