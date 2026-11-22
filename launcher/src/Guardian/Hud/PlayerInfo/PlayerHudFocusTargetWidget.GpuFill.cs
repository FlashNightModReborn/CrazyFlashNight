#nullable enable
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using CF7Launcher.Guardian.Hud.UnitLife;
using CF7Launcher.Guardian.WorldCompositor;

namespace CF7Launcher.Guardian.Hud.PlayerInfo;

internal sealed partial class PlayerHudFocusTargetWidget
{
    private sealed class FillAtlas
    {
        internal (float Scale,int Buffs,int Styles) Key;
        internal byte[] Pixels=Array.Empty<byte>();
        internal int Width,Height;
        internal readonly Rectangle[] Source=new Rectangle[4];
        internal readonly Rectangle[] Rectangles=new Rectangle[4]; // current CPU exclusion in bitmap pixels
        internal readonly int[] Items=new int[32]; // 4 packed destination/atlas rectangles
    }
    private FillAtlas? _cachedFill,_gpuFill;

    // A covered pixel never has to enter the raster texture until it becomes
    // visible again. Shrinking the HP fill invalidates the same track/row, so
    // those newly exposed pixels travel in this frame's residual rectangles.
    internal Rectangle[]? ResidualDamage(Rectangle[]? damage,Rectangle extent)
    {
        if(_gpuFill==null)return damage;
        var pending=new List<Rectangle>(damage ?? new[]{extent});
        var next=new List<Rectangle>(16);
        foreach(var cover in _gpuFill.Rectangles) {
            if(cover.IsEmpty)continue;
            foreach(var area in pending) {
                var hit=Rectangle.Intersect(area,cover);
                if(hit.Width<=0 || hit.Height<=0) {next.Add(area);continue;}
                if(area.Top<hit.Top) next.Add(Rectangle.FromLTRB(area.Left,area.Top,area.Right,hit.Top));
                if(area.Bottom>hit.Bottom) next.Add(Rectangle.FromLTRB(area.Left,hit.Bottom,area.Right,area.Bottom));
                if(area.Left<hit.Left) next.Add(Rectangle.FromLTRB(area.Left,hit.Top,hit.Left,hit.Bottom));
                if(area.Right>hit.Right) next.Add(Rectangle.FromLTRB(hit.Right,hit.Top,area.Right,hit.Bottom));
            }
            if(next.Count>16)return damage;
            (pending,next)=(next,pending);next.Clear();
        }
        return pending.Count>0 ? pending.ToArray() : damage;
    }

    // Only the opaque interior of the main fill is instanced. The fractional blade, trail,
    // gain, overflow and border remain in the original antialiased vector pass.
    internal void PrepareGpuFill(WorldRasterPresentation? presentation,Point bitmapOrigin,bool covered)
    {
        _gpuFill=null;
        if(presentation?.SupportsFocus!=true) { _cachedFill=null;return; }
        var s=Snapshot;
        if(covered || !Visible || s==null || s.TargetList.Length!=4)
        {
            _cachedFill=null;presentation.StageFocus(null,0,0,Array.Empty<int>(),0);return;
        }
        var viewport=Viewport;
        float scale=viewport.Height/576f;
        if(scale<=0 || scale>4) {presentation.StageFocus(null,0,0,Array.Empty<int>(),0);return;}
        int buffs=0, styles=0;
        for(int i=0;i<4;i++)
            styles|=(Band(s.TargetList[i]) == 2 ? 3 : (int)FillStyle(s.TargetList[i].Role))<<(2*i);
        var key=(scale,buffs,styles);
        if(_cachedFill?.Key!=key)_cachedFill=BuildFillAtlas(scale,buffs,styles);
        var a=_cachedFill;
        var output=presentation.FocusOrigin;
        int count=0;
        for(int i=0;i<4;i++) {
            a.Rectangles[i]=Rectangle.Empty;
            var t=s.TargetList[i];
            if(!_states.TryGetValue(t.Id,out var state))continue;
            var life=state.Life.Visual;
            var track=LifeTrack(RowBounds(buffs,i,4));
            float usable=track.Width-2;
            double end=life.GainAlpha>0 && PlayerHudMotionSettings.EventStrength>0
                ? Math.Min(life.Health.Ratio,life.HealStartRatio) : life.Health.Ratio;
            var interior=a.Source[i];
            int left=interior.Left;
            if(life.Health.OverflowRatio>0)
                left=Math.Max(left,(int)Math.Ceiling((track.X+5+usable*life.Health.OverflowRatio)*scale));
            int right=Math.Min(interior.Right,(int)Math.Floor((track.X+usable*end-3)*scale));
            if(right<=left || interior.Height<1)continue;
            var r=new Rectangle(left,interior.Y,right-left,interior.Height);
            var local=r;local.Offset(viewport.X-bitmapOrigin.X,viewport.Y-bitmapOrigin.Y);
            a.Rectangles[i]=local;
            int j=count++*8;
            a.Items[j]=r.X+viewport.X-output.X;a.Items[j+1]=r.Y+viewport.Y-output.Y;
            a.Items[j+2]=r.Width;a.Items[j+3]=r.Height;
            a.Items[j+4]=r.X-interior.Left;a.Items[j+5]=i*(a.Height/4);
        }
        if(presentation.StageFocus(a.Pixels,a.Width,a.Height,a.Items,count))_gpuFill=a;
        else throw new InvalidOperationException("GPU focus fill staging failed.");
    }

    private static UnitLifeBarStyle FillStyle(string role)=>role=="boss"?UnitLifeBarStyle.Boss:
        role=="combat"?UnitLifeBarStyle.Hostile:UnitLifeBarStyle.Friendly;

    private static FillAtlas BuildFillAtlas(float scale,int buffs,int styles)
    {
        var a=new FillAtlas {Key=(scale,buffs,styles)};
        for(int i=0;i<4;i++) {
            var r=LifeTrack(RowBounds(buffs,i,4));
            a.Source[i]=Rectangle.FromLTRB((int)Math.Ceiling((r.Left+5)*scale),
                (int)Math.Ceiling((r.Top+1.5f)*scale)+1,(int)Math.Floor((r.Right-5)*scale),
                (int)Math.Floor((r.Bottom-.6f)*scale));
            a.Width=Math.Max(a.Width,a.Source[i].Width);
            a.Height=Math.Max(a.Height,a.Source[i].Height);
        }
        a.Height=Math.Max(1,a.Height)*4;
        a.Pixels=new byte[a.Width*a.Height*4];
        // Rasterize a full-health primitive once at the original subpixel phase. Store
        // only the reusable interior material, without the moving blade or row art.
        for(int i=0;i<4;i++) {
            var rect=a.Source[i];if(rect.Height<1)continue;
            using var image=new Bitmap(rect.Right+12,rect.Bottom+12,PixelFormat.Format32bppPArgb);
            using(var g=Graphics.FromImage(image)) {
                g.SmoothingMode=SmoothingMode.AntiAlias;
                g.ScaleTransform(scale,scale);
                int style = (styles >> (2*i)) & 3;
                var visual = UnitLifeBarVisual.Resting(new UnitHealth(1,1)) with { Critical = style == 3 };
                UnitLifeBarPainter.Paint(g,LifeTrack(RowBounds(buffs,i,4)),visual,
                    style == 3 ? UnitLifeBarStyle.Friendly : (UnitLifeBarStyle)style,1,focusV38:true);
            }
            var bits=image.LockBits(rect,ImageLockMode.ReadOnly,PixelFormat.Format32bppPArgb);
            try {
                for(int y=0;y<rect.Height;y++)
                    Marshal.Copy(IntPtr.Add(bits.Scan0,y*bits.Stride),a.Pixels,(i*a.Height/4+y)*a.Width*4,rect.Width*4);
            } finally {image.UnlockBits(bits);}
        }
        return a;
    }
}
