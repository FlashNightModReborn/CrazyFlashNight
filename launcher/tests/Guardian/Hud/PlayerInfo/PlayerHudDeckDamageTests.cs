using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using CF7Launcher.Guardian.Hud;
using CF7Launcher.Guardian.Hud.PlayerInfo;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian.Hud.PlayerInfo;

public sealed class PlayerHudDeckDamageTests
{
    private static JObject Full()
    {
        var full=PlayerHudStateTests.Full();
        full["groups"]["focusTarget"]=new JArray(new JObject { ["id"]=5,["role"]="boss",["name"]="焦点",["hp"]=new JArray(900,1000),["icon"]="",["doll"]=null });
        full["groups"]["buffs"]=new JArray(Enumerable.Range(0,84).Select(i=>new JObject {
            ["id"]="status"+i,["timed"]=true,["total"]=600,["remaining"]=311,
            ["info"]=new JObject{["name"]="抗性"+i,["description"]="效果",["polarity"]="benefit",["stacks"]=0} }));
        return full;
    }

    [Fact]
    public void CombinedBuffAndFocusPacketsOnlyWakeTheBottomWhenItsLightsChange()
    {
        using var anchor=new Panel{Size=new Size(1024,576)};
        using var controller=new PlayerHudController(_=>true,()=>true,a=>a());
        var root=new DirectoryInfo(AppContext.BaseDirectory);
        while(root!=null && !File.Exists(Path.Combine(root.FullName,"launcher","web","icons","manifest.json")))root=root.Parent;
        Assert.NotNull(root);
        using var bottom=new PlayerHudBottomWidget(anchor,controller,Path.Combine(root.FullName,"launcher","web","icons"));
        var packet=Full();var rows=(JArray)packet["groups"]["buffs"];int seq=0,paints=0;
        void Send(){packet["seq"]=++seq; packet["groups"]["focusTarget"][0]["hp"][0]=900-seq;
            Assert.True(controller.State.Receive(PlayerHudStateTests.Encode(packet),seq));}
        Send();bottom.RepaintRequested+=(_,_)=>paints++;
        for(int i=0;i<26;i++) {rows[0]["remaining"]=i%2==0?221:311;Send();}
        Assert.Equal(0,paints);
        rows[0]["source"]=new JObject{["kind"]="drug",["key"]="药剂0",["slot"]=0};Send();Assert.True(paints>0);
        int previous=paints;packet["groups"]["loadout"]["drugs"][0]["name"]="换药";Send();Assert.True(paints>previous);
        previous=paints;packet["groups"]["loadout"]["bank"]=1;
        for (int i=0;i<4;i++) packet["groups"]["loadout"]["drugs"][i]["slot"]=4+i;
        rows[0]["remaining"]=90;Send();Assert.True(paints>previous);
        previous=paints;bottom.SetHostSuppressed(true);bottom.SetHostSuppressed(false);Assert.True(paints>=previous+2);
        previous=paints;packet["epoch"]=2;Send();Assert.True(paints>previous);
    }

    [Theory][InlineData(1024,576)][InlineData(1600,900)][InlineData(1920,1080)]
    public void SingleCardDamageRebuildsExactPixelsAcrossDrawerPagesAndUrgency(int width,int height)
    {
        using var anchor=new Panel{Size=new Size(width,height)};
        using var controller=new PlayerHudController(_=>true,()=>true,a=>a());
        using var buff=new PlayerHudBuffWidget(anchor,controller);
        var packet=Full();var cards=(JArray)packet["groups"]["buffs"];int seq=0;
        void Send(){packet["seq"]=++seq;controller.TakeUiData("pi:"+PlayerHudStateTests.Encode(packet));Assert.Equal(seq,controller.State.Snapshot.Sequence);}
        Send();var origin=anchor.PointToScreen(Point.Empty);float scale=height/576f;
        using var retained=new Bitmap(width,height,PixelFormat.Format32bppPArgb);
        void Render(Bitmap bitmap,Rectangle[] rects)
        {
            using var dirty=new Region(); dirty.MakeEmpty();
            foreach(var rectangle in rects){var area=rectangle;area.Offset(-origin.X,-origin.Y);dirty.Union(area);}
            using var g=Graphics.FromImage(bitmap);g.SetClip(dirty,CombineMode.Intersect);g.CompositingMode=CompositingMode.SourceCopy;
            g.FillRectangle(Brushes.Transparent,0,0,width,height);g.CompositingMode=CompositingMode.SourceOver;
            g.SmoothingMode=SmoothingMode.AntiAlias;buff.Paint(g,1,origin);
        }
        var all=new[]{new Rectangle(origin,new Size(width,height))};Render(retained,all);
        EventArgs damage=null;buff.RepaintRequested+=(_,args)=>damage=args;
        void Verify(Action change,int expected)
        {
            damage=null;change();Send();
            if(expected<0){Assert.NotNull(damage);Assert.False(damage is HudRepaintRegions{Bounds.Length:>0});Render(retained,all);}
            else if(expected==0)Assert.Null(damage);
            else {var regions=Assert.IsType<HudRepaintRegions>(damage);Assert.False(regions.Authoritative);Assert.Equal(expected,regions.Bounds.Length);
                Assert.All(regions.Bounds,b=>Assert.True(b.Width<=32*scale+4 && b.Height<=32*scale+4));Render(retained,regions.Bounds);}
            using var reference=new Bitmap(width,height,PixelFormat.Format32bppPArgb);Render(reference,all);
            var a=Pixels(retained);var b=Pixels(reference);int diff=-1;
            for(int i=0;i<a.Length;i++)if(a[i]!=b[i]){diff=i;break;}
            Assert.True(diff<0,$"{width}×{height} packet {seq} differs at ({diff/4%width},{diff/4/width})");
        }
        void Click(RectangleF r)
        {
            var p=new Point(origin.X+(int)((r.Left+r.Width/2)*scale),origin.Y+(int)((r.Top+r.Height/2)*scale));
            Assert.True(buff.TryHitTest(p));var e=new MouseEventArgs(MouseButtons.Left,1,p.X,p.Y,0);
            foreach(var k in new[]{MouseEventKind.Down,MouseEventKind.Up,MouseEventKind.Click})buff.OnMouseEvent(e,k);
            Render(retained,all);
        }
        Verify(()=>cards[0]["remaining"]=221,1);
        Verify(()=>cards[70]["remaining"]=200,0);
        Click(PlayerHudBuffLayout.Toggle(false));
        Verify(()=>{cards[0]["remaining"]=83;cards[0]["info"]["stacks"]=3;cards[0]["role"]="eres";},2);
        Verify(()=>{cards[0]["source"]=new JObject{["kind"]="drug",["key"]="测试药",["slot"]=6};cards[0]["info"]["name"]="高抗";},2);
        Verify(()=>cards[40]["remaining"]=32,1);
        Verify(()=>{cards[1]["remaining"]=19;cards[2]["remaining"]=28;},-1);
        Click(PlayerHudBuffLayout.NextPageRect(84));Assert.Equal(1,buff.CurrentPage);
        Verify(()=>cards[60]["remaining"]=47,1);
        Verify(()=>cards[0]["remaining"]=5,1);
        Verify(()=>cards[40]["remaining"]=28,0);
        Verify(()=>cards[3]["role"]="poison",-1);
        buff.SetHostSuppressed(true);buff.SetHostSuppressed(false);Assert.Equal(0,buff.CurrentPage);
    }

    private static byte[] Pixels(Bitmap image)
    {
        var data=image.LockBits(new Rectangle(0,0,image.Width,image.Height),ImageLockMode.ReadOnly,PixelFormat.Format32bppPArgb);
        try {var bytes=new byte[data.Stride*data.Height];Marshal.Copy(data.Scan0,bytes,0,bytes.Length);return bytes;}
        finally {image.UnlockBits(data);}
    }
}
