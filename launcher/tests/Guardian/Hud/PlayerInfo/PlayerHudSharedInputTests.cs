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
    [Fact]
    public void RealDrugTargetSendsOnceAndUnknownWriteSurvivesInputAndConnectionRestart()
    {
        Sta(()=> {
            using var f=new Fixture();var point=f.At(PlayerHudBottomWidget.DrugRect(0));
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
            using var f=new Fixture();var point=f.At(PlayerHudBottomWidget.DrugRect(0));
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
            using var f=new Fixture();var first=f.At(PlayerHudBottomWidget.DrugRect(0));var second=f.At(PlayerHudBottomWidget.DrugRect(1));
            f.Router.TryRoute(0x201,first,0,false);f.Pump();
            f.Router.TryRoute(0x202,second,0,false);f.Pump();Assert.Empty(f.Writes);
            f.Router.TryRoute(0x201,first,0,false);f.Pump();
            Assert.True(f.Router.TryRoute(0x202,new Point(-10000,-10000),0,false));f.Pump();Assert.Empty(f.Writes);
            f.Click(first);Assert.Single(f.Writes);
        });
    }
}
