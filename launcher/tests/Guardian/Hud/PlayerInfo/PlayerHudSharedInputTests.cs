using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Threading;
using System.Windows.Forms;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.Hud;
using CF7Launcher.Guardian.Hud.PlayerInfo;
using CF7Launcher.Guardian.WorldCompositor;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian.Hud.PlayerInfo;

public sealed class PlayerHudSharedInputTests
{
    private sealed class Fixture : IDisposable
    {
        internal readonly Form Owner=new(){ClientSize=new Size(1024,576),AutoScaleMode=AutoScaleMode.None};
        internal readonly Panel Anchor=new(){Dock=DockStyle.Fill};
        internal readonly List<JObject> Sent=new();
        internal readonly Queue<Action> Jobs=new();
        internal readonly PlayerHudController Controller;
        internal readonly PlayerHudBottomWidget Widget;
        internal readonly WorldHudPointerRouter Router;
        internal bool Active=true;
        internal Fixture()
        {
            Owner.Controls.Add(Anchor);_=Owner.Handle;_=Anchor.Handle;
            Controller=new PlayerHudController(raw=>{Sent.Add(JObject.Parse(raw.TrimEnd('\0')));return true;},()=>true,a=>a());
            Controller.TakeUiData("pi:"+PlayerHudStateTests.Encode(PlayerHudStateTests.Full()));
            var root=new DirectoryInfo(AppContext.BaseDirectory);
            while(root!=null&&!Directory.Exists(Path.Combine(root.FullName,"launcher","web","icons")))root=root.Parent;
            Assert.NotNull(root);
            Widget=new PlayerHudBottomWidget(Anchor,Controller,Path.Combine(root.FullName,"launcher","web","icons"));
            Router=new WorldHudPointerRouter(Jobs.Enqueue);
            Router.SetInput(new PlayerHudPointerInput(Widget,()=>Active));Sent.Clear();
        }
        internal Point At(RectangleF rectangle)
        {
            var viewport=RightHudLayout.GetViewportRect(Anchor,new FlashCoordinateMapper(Anchor,1024,576));
            float scale=viewport.Height/576f;
            return new Point((int)(viewport.X+(rectangle.X+rectangle.Width/2)*scale),(int)(viewport.Y+(rectangle.Y+rectangle.Height/2)*scale));
        }
        internal void Pump() { while(Jobs.TryDequeue(out var job))job(); }
        internal void Click(Point point) { Assert.True(Router.TryRoute(0x201,point,0,false));Assert.True(Router.TryRoute(0x202,point,0,false));Pump(); }
        internal JObject[] Writes => Sent.Where(x=>(string)x["action"]=="playerHudAction").ToArray();
        public void Dispose() { Widget.Dispose();Controller.Dispose();Anchor.Dispose();Owner.Dispose(); }
    }
    private static void Sta(Action action)
    {
        Exception error=null;var thread=new Thread(()=>{try{action();}catch(Exception e){error=e;}});
        thread.SetApartmentState(ApartmentState.STA);thread.Start();Assert.True(thread.Join(30000));
        if(error!=null)System.Runtime.ExceptionServices.ExceptionDispatchInfo.Capture(error).Throw();
    }
    [Theory]
    [InlineData(0)]
    [InlineData(1)]
    public void PotionBodyIsReadOnlyAndCrossUsesTheActualBankSlot(int bank)
    {
        Sta(()=> {
            using var f=new Fixture();
            var packet=PlayerHudStateTests.Full(1,2);
            packet["groups"]["loadout"]["bank"]=bank;
            for(var lane=0;lane<4;lane++) packet["groups"]["loadout"]["drugs"][lane]["slot"]=bank*4+lane;
            f.Controller.TakeUiData("pi:"+PlayerHudStateTests.Encode(packet));
            f.Click(f.At(PlayerHudBottomWidget.DrugRect(2))); Assert.Empty(f.Writes);
            var body=f.At(PlayerHudBottomWidget.DrugRect(2));var cross=f.At(PlayerHudBottomWidget.DrugUnequipRect(2));
            f.Router.TryRoute(0x201,body,0,false);f.Router.TryRoute(0x202,cross,0,false);f.Pump();Assert.Empty(f.Writes);
            f.Click(cross); var write=Assert.Single(f.Writes);
            Assert.Equal(bank*4+2,(int)write["slot"]);Assert.Equal(bank,(int)write["bank"]);
        });
    }

    [Fact]
    public void BuffHoverUsesProductionSharedRouterAndRejectsRetiredTargets()
    {
        Sta(()=> {
            using var f=new Fixture();
            using var surface=new NativeHudOverlay(f.Owner,f.Anchor);
            using var buffs=new PlayerHudBuffWidget(f.Anchor,f.Controller);
            using var tooltip=new PlayerHudResourceTooltip(f.Anchor,f.Controller,true);
            surface.AddWidget(buffs);surface.AddWidget(tooltip.Widget);
            f.Router.SetInput(new WorldHudInputLayers(new PlayerHudPointerInput(f.Widget,()=>f.Active),
                new NativeHudOverlay.MainHudInput(surface,f.Anchor,()=>f.Active)));
            var packet=PlayerHudStateTests.Full(1,2);
            JObject Buff(string id)=>new(){["id"]=id,["timed"]=true,["total"]=300,["remaining"]=60,
                ["info"]=new JObject{["name"]="腕刃强化",["description"]="提高腕刃攻击力。",["polarity"]="benefit",["stacks"]=2}};
            packet["groups"]["buffs"]=new JArray(Buff("a"));
            f.Controller.TakeUiData("pi:"+PlayerHudStateTests.Encode(packet));f.Sent.Clear();f.Pump();
            var p=f.At(PlayerHudBuffWidget.SlotRect(0));
            Assert.True(f.Router.TryRoute(0x200,p,0,false));f.Pump();
            Assert.NotNull(tooltip.Widget.ActiveDocument);
            f.Click(p);Assert.Empty(f.Sent);
            f.Router.TryRoute(0x200,f.At(new RectangleF(400,250,5,5)),0,false);f.Pump();
            Assert.Null(tooltip.Widget.ActiveDocument);
            Assert.True(f.Router.TryRoute(0x200,p,0,false));
            packet["seq"]=3;packet["groups"]["buffs"]=new JArray(Buff("b"));
            f.Controller.TakeUiData("pi:"+PlayerHudStateTests.Encode(packet));f.Pump();
            Assert.Null(tooltip.Widget.ActiveDocument); // A queued hover cannot inspect a replacement in the same slot.
            Assert.True(f.Router.TryRoute(0x200,p,0,false));f.Pump();
            Assert.NotNull(tooltip.Widget.ActiveDocument);
            surface.CancelPointerGesture();f.Router.Cancel();f.Pump();
            Assert.Null(tooltip.Widget.ActiveDocument);Assert.Empty(f.Sent);
            surface.RemoveWidget(tooltip.Widget);surface.RemoveWidget(buffs);
        });
    }

    [Fact]
    public void CountHoverUsesUnifiedDrugTooltipAndCannotRemoveItem()
    {
        Sta(()=> {
            using var f=new Fixture();using var tooltip=new PlayerHudResourceTooltip(f.Anchor,f.Controller);
            var packet=PlayerHudStateTests.Full(1,2);
            packet["groups"]["loadout"]["drugs"][0]["count"]=41006;
            f.Controller.TakeUiData("pi:"+PlayerHudStateTests.Encode(packet));f.Sent.Clear();
            var p=f.At(PlayerHudBottomWidget.CountRect(PlayerHudBottomWidget.DrugRect(0)));
            Assert.True(f.Router.TryRoute(0x200,p,0,false));f.Pump();
            Assert.Null(tooltip.Widget.ActiveDocument);
            var show=Assert.Single(f.Sent);
            Assert.Equal("playerHudTooltip",(string)show["action"]);
            Assert.Equal("show",(string)show["op"]);
            Assert.Equal("drug",(string)show["kind"]);
            Assert.Equal(0,(int)show["slot"]);
            f.Click(p);Assert.Empty(f.Writes);
            var target=f.Widget.CapturePointerTarget(p);
            Assert.Equal("drug",target.Kind);
            Assert.Equal(PlayerHudBottomWidget.DrugRect(0),target.Anchor);
            // Moving onto the removal cross of the same slot keeps the unified item tooltip without flickering.
            var cross=f.At(PlayerHudBottomWidget.DrugUnequipRect(0));
            Assert.True(f.Router.TryRoute(0x200,cross,0,false));f.Pump();
            Assert.Single(f.Sent);
            packet["seq"]=3;packet["groups"]["loadout"]["drugRevision"]=5;
            packet["groups"]["loadout"]["drugs"][0]["count"]=41005;
            f.Controller.TakeUiData("pi:"+PlayerHudStateTests.Encode(packet));
            Assert.Contains(f.Sent,m=>(string)m["action"]=="playerHudTooltip" && (string)m["op"]=="hide");
            Assert.Empty(f.Writes);
        });
    }

    [Fact]
    public void OnlyTheAuthoredHeaderEntryOpensResourceDetails()
    {
        Sta(()=> {
            using var f=new Fixture();
            Assert.Null(f.Widget.CapturePointerTarget(f.At(new RectangleF(278,514,18,22))));
            Assert.Equal("resources",f.Widget.CapturePointerTarget(f.At(PlayerHudBottomWidget.DetailsRect)).Kind);
            f.Click(f.At(PlayerHudBottomWidget.DetailsRect));Assert.Empty(f.Writes);
        });
    }

    [Fact]
    public void EmptyPotionHasNoRemovalTarget()
    {
        Sta(()=> {
            using var f=new Fixture();var packet=PlayerHudStateTests.Full(1,2);
            packet["groups"]["loadout"]["drugs"][0]["count"]=0;
            f.Controller.TakeUiData("pi:"+PlayerHudStateTests.Encode(packet));
            Assert.Null(f.Widget.CapturePointerTarget(f.At(PlayerHudBottomWidget.DrugUnequipRect(0))));
        });
    }
    [Fact]
    public void RealDrugTargetSendsOnceAndUnknownWriteSurvivesInputAndConnectionRestart()
    {
        Sta(()=> {
            using var f=new Fixture();var point=f.At(PlayerHudBottomWidget.DrugUnequipRect(0));
            f.Click(point);var write=Assert.Single(f.Writes);
            Assert.Equal("drug",(string)write["kind"]);Assert.Equal(0,(int)write["slot"]);
            Assert.True(f.Controller.WritePending);
            f.Router.Cancel();f.Active=false;f.Pump();f.Active=true;
            f.Controller.Disconnected();f.Controller.TakeUiData("pi:"+PlayerHudStateTests.Encode(PlayerHudStateTests.Full(2,2)));
            f.Click(point);Assert.Single(f.Writes);Assert.True(f.Controller.WritePending);
            f.Controller.Tick(long.MaxValue/2);
            Assert.Contains(f.Sent,x=>(string)x["action"]=="playerHudQuery" && (string)x["actionId"]==(string)write["actionId"]);
        });
    }
    [Theory]
    [InlineData("epoch")]
    [InlineData("revision")]
    [InlineData("paused")]
    [InlineData("geometry")]
    [InlineData("suppressed")]
    public void QueuedPressCannotActOnAReplacementTarget(string change)
    {
        Sta(()=> {
            using var f=new Fixture();var point=f.At(PlayerHudBottomWidget.DrugUnequipRect(0));
            f.Router.TryRoute(0x201,point,0,false);f.Router.TryRoute(0x202,point,0,false);
            var packet=PlayerHudStateTests.Full(1,2);
            if(change=="epoch")packet["epoch"]=2;
            if(change=="revision")packet["groups"]["loadout"]["drugRevision"]=5;
            if(change=="paused")packet["groups"]["vitals"]["paused"]=true;
            if(change=="geometry")f.Owner.ClientSize=new Size(800,450);
            if(change=="suppressed")f.Active=false;
            f.Controller.TakeUiData("pi:"+PlayerHudStateTests.Encode(packet));f.Pump();
            Assert.Empty(f.Writes);
        });
    }
    [Fact]
    public void DragOutAndSwitchingDrugSlotsCancelWithoutLeakingAnAction()
    {
        Sta(()=> {
            using var f=new Fixture();var first=f.At(PlayerHudBottomWidget.DrugUnequipRect(0));var second=f.At(PlayerHudBottomWidget.DrugUnequipRect(1));
            f.Router.TryRoute(0x201,first,0,false);f.Pump();
            f.Router.TryRoute(0x202,second,0,false);f.Pump();Assert.Empty(f.Writes);
            f.Router.TryRoute(0x201,first,0,false);f.Pump();
            Assert.True(f.Router.TryRoute(0x202,new Point(-10000,-10000),0,false));f.Pump();Assert.Empty(f.Writes);
            f.Click(first);Assert.Single(f.Writes);
        });
    }
}
