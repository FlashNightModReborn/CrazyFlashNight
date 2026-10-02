using System;
using System.Collections.Generic;
using System.Drawing;
using System.Windows.Forms;
using CF7Launcher.Guardian.Hud;
using CF7Launcher.Guardian.Hud.Guidance;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Tasks
{
    public sealed class NativeGuidanceTaskTests
    {
        private const string Content="{\"version\":1,\"guides\":[{\"id\":\"pickup\",\"title\":\"拾取\",\"kind\":\"scene\",\"pages\":[{\"title\":\"拾取\",\"text\":\"按 {interact} 拾取\"}]},{\"id\":\"start\",\"title\":\"开始\",\"kind\":\"tutorial\",\"pages\":[{\"title\":\"开始\",\"text\":\"操作\",\"image\":\"flashswf/images/example.png\"},{\"title\":\"下一页\",\"text\":\"奔跑\"}]}]}";
        private sealed class Rig : IDisposable
        {
            internal readonly Control Anchor=new Panel {Size=new Size(1024,576)};
            internal readonly NativeGuidanceWidget Widget;
            internal readonly NativeGuidanceTask Task;
            internal readonly List<string> Sent=new();
            internal bool Allowed=true;
            internal Rig(Action<Action> dispatch=null) {
                Widget=new NativeGuidanceWidget(Anchor,GuidanceCatalog.FromJson(Content));
                Task=new NativeGuidanceTask(Widget,dispatch??(a=>a()),wire=>{Sent.Add(wire);return true;},()=>Allowed);
            }
            public void Dispose(){Widget.Dispose();Anchor.Dispose();}
        }
        private static JObject Show(string id="ng:1",string scene="scene",int revision=1,string guide="pickup")=>new JObject {
            ["payload"]=new JObject { ["version"]=1,["op"]="show",["requestId"]=id,["sceneId"]=scene,["revision"]=revision,["guideId"]=guide,["opacity"]=0.75,
                ["keys"]=new JObject { ["left"]="A",["right"]="D",["up"]="W",["down"]="S",["attack"]="J",["jump"]="K",["interact"]="T" } } };
        private static JObject Hide(string id="ng:1",string scene="scene")=>new JObject { ["payload"]=new JObject { ["version"]=1,["op"]="hide",["requestId"]=id,["sceneId"]=scene } };
        [Fact] public void SceneIsPassiveAndBindsCurrentKeys() { using var r=new Rig();r.Task.Handle(Show());Assert.True(r.Widget.Visible);Assert.Contains("T",r.Widget.CurrentText);Assert.False(r.Widget.TryHitTest(r.Widget.ScreenBounds.Location));Assert.Empty(r.Sent); }
        [Theory]
        [InlineData("version","999999999999999999999")]
        [InlineData("version","\"1\"")]
        [InlineData("op","[]")]
        [InlineData("revision","0")]
        [InlineData("revision","1.2")]
        [InlineData("guideId","\"unknown\"")]
        [InlineData("opacity","1.1")]
        [InlineData("opacity","-0.1")]
        [InlineData("opacity","\"0.7\"")]
        [InlineData("opacity","999999999999999999999999999999999999999999")]
        [InlineData("requestId","\"ng:01\"")]
        [InlineData("requestId","\"ng:9007199254740992\"")]
        [InlineData("sceneId","null")]
        public void RejectsMalformedSnapshots(string field,string json) { using var r=new Rig();var message=Show();message["payload"][field]=JToken.Parse(json);r.Task.Handle(message);Assert.False(r.Widget.Visible); }
        [Fact] public void RejectsUnknownFieldsAndMalformedKeys() {using var r=new Rig();var m=Show();m["payload"]["extra"]=1;r.Task.Handle(m);Assert.False(r.Widget.Visible);m=Show();m["payload"]["keys"]["interact"]=new JArray();r.Task.Handle(m);Assert.False(r.Widget.Visible);}
        [Fact] public void RevisionSceneAndSequenceFencesPreventResurrection() {
            using var r=new Rig();r.Task.Handle(Show(revision:3));r.Task.Handle(Show(revision:2));Assert.Equal(3,r.Widget.CurrentRevision);
            r.Task.Handle(Show(scene:"other",revision:4));Assert.Equal("scene",r.Widget.CurrentScene);
            r.Task.Handle(Hide(scene:"foreign"));Assert.True(r.Widget.Visible);
            r.Task.Handle(Hide());r.Task.Handle(Show(revision:5));Assert.False(r.Widget.Visible);
            r.Task.Handle(Show(id:"ng:2"));r.Task.Handle(Show(revision:100));Assert.Equal("ng:2",r.Widget.CurrentRequest);
        }
        [Fact] public void QueuedOldTransportCannotAppearAfterDisconnect() {
            var queue=new Queue<Action>();using var r=new Rig(queue.Enqueue);
            r.Task.Handle(Show());r.Task.HandleTransportDisconnected();queue.Dequeue()();Assert.False(r.Widget.Visible);queue.Dequeue()();
            r.Task.Handle(Show());queue.Dequeue()();Assert.True(r.Widget.Visible);
        }
        [Fact] public void TutorialCloseIsExactGatedAndOneShot() {
            using var r=new Rig();r.Task.Handle(Show(guide:"start"));r.Allowed=false;r.Widget.CloseRequested("ng:1","scene",1);Assert.Empty(r.Sent);
            r.Allowed=true;r.Widget.CloseRequested("ng:1","scene",2);Assert.Empty(r.Sent);
            r.Widget.CloseRequested("ng:1","scene",1);r.Widget.CloseRequested("ng:1","scene",1);Assert.Single(r.Sent);
            var wire=JObject.Parse(r.Sent[0].TrimEnd('\0'));Assert.Equal("nativeGuidanceAction",wire.Value<string>("action"));Assert.Equal("close",wire.Value<string>("verb"));Assert.False(r.Widget.Visible);
        }
        [Fact] public void SuppressionAndZeroOpacityNeverOwnInput() {
            using var r=new Rig();r.Task.Handle(Show(guide:"start"));r.Widget.SetHostSuppressed(true);Assert.False(r.Widget.Visible);Assert.Equal("ng:1",r.Widget.CurrentRequest);
            r.Widget.SetHostSuppressed(false);Assert.True(r.Widget.Visible);
            var show=Show(guide:"start",revision:2);show["payload"]["opacity"]=0;r.Task.Handle(show);Assert.False(r.Widget.Visible);
        }
        [Fact] public void TutorialClickSurvivesFadeUpdatesButCannotCrossRequests() {
            using var r=new Rig();r.Task.Handle(Show(guide:"start"));var b=r.Widget.NextButtonBounds;
            var click=new MouseEventArgs(MouseButtons.Left,1,b.Left+b.Width/2,b.Top+b.Height/2,0);
            r.Widget.OnMouseEvent(click,MouseEventKind.Down);r.Task.Handle(Show(guide:"start",revision:2));
            r.Widget.OnMouseEvent(click,MouseEventKind.Up);Assert.Equal(1,r.Widget.CurrentPage);Assert.Empty(r.Sent);
            r.Widget.OnMouseEvent(click,MouseEventKind.Down);r.Task.Handle(Show(id:"ng:2",guide:"start"));
            r.Widget.OnMouseEvent(click,MouseEventKind.Up);Assert.Equal(0,r.Widget.CurrentPage);Assert.Empty(r.Sent);
        }
        [Fact] public void OldImageIsRejectedAndCurrentImageIsCloned() {
            using var r=new Rig();r.Task.Handle(Show(guide:"start"));int epoch=r.Widget.ImageEpoch;
            using var image=new Bitmap(10,10);Assert.False(r.Widget.SetImage("ng:0","scene",epoch,image));
            Assert.True(r.Widget.SetImage("ng:1","scene",epoch,image));r.Task.Handle(Hide());Assert.False(r.Widget.SetImage("ng:1","scene",epoch,image));
        }
        [Fact] public void DelayedImageSurvivesOpacityRevisionsButCannotCrossPagesOrDisconnect() {
            using var r=new Rig();Action<Bitmap> deliver=null;r.Task.LoadImage=(path,callback)=>deliver=callback;
            r.Task.Handle(Show(guide:"start"));r.Task.Handle(Show(guide:"start",revision:2));
            deliver(new Bitmap(10,10));Assert.True(r.Widget.HasImage);
            var b=r.Widget.NextButtonBounds;var click=new MouseEventArgs(MouseButtons.Left,1,b.Left+b.Width/2,b.Top+b.Height/2,0);
            r.Widget.OnMouseEvent(click,MouseEventKind.Down);r.Widget.OnMouseEvent(click,MouseEventKind.Up);
            Assert.Equal(1,r.Widget.CurrentPage);deliver(new Bitmap(10,10));Assert.False(r.Widget.HasImage);
            r.Task.Handle(Show(id:"ng:2",guide:"start"));var old=deliver;r.Task.HandleTransportDisconnected();
            r.Task.Handle(Show(guide:"start"));old(new Bitmap(10,10));Assert.False(r.Widget.HasImage);
            deliver(new Bitmap(10,10));Assert.True(r.Widget.HasImage);
        }
        [Theory][InlineData(1024,576)][InlineData(1600,900)][InlineData(2560,1440)]
        public void BoundsFollowLogicalCanvas(int width,int height) {
            using var r=new Rig();r.Anchor.Size=new Size(width,height);r.Task.Handle(Show(guide:"start"));Rectangle b=r.Widget.ScreenBounds;
            Assert.Equal((int)Math.Round(617*width/1024d),b.Width);Assert.Equal((int)Math.Round(328*height/576d),b.Height);
        }
        [Fact] public void CatalogRejectsDuplicatesAndTraversal() {
            var catalog=JObject.Parse(Content);((JArray)catalog["guides"]).Add(catalog["guides"][0].DeepClone());Assert.Throws<FormatException>(()=>GuidanceCatalog.FromJson(catalog.ToString()));
            catalog=JObject.Parse(Content);catalog["guides"][1]["pages"][0]["image"]="flashswf/images/../save.json";Assert.Throws<FormatException>(()=>GuidanceCatalog.FromJson(catalog.ToString()));
        }
        private static NativeGuidanceWidget HelpWidget(Control anchor)
        {
            var content=JObject.Parse(Content);content["guides"][1]["surface"]="help";
            return new NativeGuidanceWidget(anchor,GuidanceCatalog.FromJson(content.ToString()));
        }
        [Fact] public void HelpOpensOnceAfterDelayWithCurrentKeysAndExactClose()
        {
            using var anchor=new Panel {Size=new Size(1024,576)};using var widget=HelpWidget(anchor);
            var sent=new List<string>();var task=new NativeGuidanceTask(widget,a=>a(),s=>{sent.Add(s);return true;},()=>false);
            NativeGuidanceTask.HelpPresentation opened=null;int count=0;
            task.OpenHelp=(p,done)=>{opened=p;count++;done(true);};
            var first=Show(guide:"start");first["payload"]["opacity"]=0;task.Handle(first);
            Assert.Equal(0,count);task.Handle(Show(guide:"start",revision:2));Assert.Equal(1,count);
            Assert.Equal("T",opened.Keys["interact"]);Assert.False(widget.Visible);Assert.True(opened.IsCurrent());
            task.Handle(Show(guide:"start",revision:3));Assert.Equal(1,count);
            task.NotifyHelpClosed("help","foreign");Assert.Empty(sent);
            task.NotifyHelpClosed("help",opened.PanelInstanceId);task.NotifyHelpClosed("help",opened.PanelInstanceId);
            Assert.Single(sent);Assert.Equal(3,JObject.Parse(sent[0].TrimEnd('\0')).Value<int>("revision"));Assert.False(opened.IsCurrent());
            task.Handle(Show(guide:"start",revision:4));Assert.Equal(1,count);
        }
        [Fact] public void HelpNeverEvictsBusyPanelAndPendingGuideResumesAfterClose()
        {
            using var anchor=new Panel {Size=new Size(1024,576)};using var widget=HelpWidget(anchor);
            var task=new NativeGuidanceTask(widget,a=>a(),_=>true);bool free=false;int count=0;
            task.CanOpenHelp=()=>free;task.OpenHelp=(p,done)=>{count++;done(true);};
            task.Handle(Show(guide:"start"));Assert.Equal(0,count);
            free=true;task.NotifyHelpClosed("workbench","old");Assert.Equal(1,count);
        }
        [Fact] public void HelpTeardownRevokesQueuedOpenAndClosesOnlyItsExactInstance()
        {
            using var anchor=new Panel {Size=new Size(1024,576)};using var widget=HelpWidget(anchor);
            var task=new NativeGuidanceTask(widget,a=>a(),_=>true);var opened=new List<NativeGuidanceTask.HelpPresentation>();var closed=new List<string>();
            var callbacks=new List<Action<bool>>();task.OpenHelp=(p,done)=>{opened.Add(p);callbacks.Add(done);};task.CloseHelp=closed.Add;
            task.Handle(Show(guide:"start"));task.Handle(Show(id:"ng:2",guide:"start"));
            Assert.False(opened[0].IsCurrent());Assert.True(opened[1].IsCurrent());Assert.Equal(opened[0].PanelInstanceId,Assert.Single(closed));
            callbacks[0](false);Assert.True(opened[1].IsCurrent());
            task.HandleTransportDisconnected();Assert.False(opened[1].IsCurrent());Assert.Equal(opened[1].PanelInstanceId,closed[1]);
            callbacks[1](true);task.Handle(Show(guide:"start"));Assert.True(opened[2].IsCurrent());
        }
        [Fact] public void HelpOpenFailuresHaveBoundedRetriesAndNoNativeCardFallback()
        {
            using var anchor=new Panel {Size=new Size(1024,576)};using var widget=HelpWidget(anchor);
            var task=new NativeGuidanceTask(widget,a=>a(),_=>true);int count=0,notices=0;
            task.HelpUnavailable=()=>notices++;
            task.OpenHelp=(p,done)=>{count++;done(false);};
            for(int revision=1;revision<=6;revision++)task.Handle(Show(guide:"start",revision:revision));
            Assert.Equal(3,count);Assert.Equal(1,notices);Assert.False(widget.Visible);
        }
        [Fact] public void LootBindingMustSettleAfterPanelCloseBeforeDeferredHelpResumes()
        {
            using var anchor=new Panel {Size=new Size(1024,576)};using var widget=HelpWidget(anchor);
            var task=new NativeGuidanceTask(widget,a=>a(),_=>true);bool idle=false;int opened=0;
            task.CanOpenHelp=()=>idle;task.OpenHelp=(p,done)=>{opened++;done(true);};
            task.Handle(Show(guide:"start"));task.NotifyHelpClosed("loot","settlement");
            Assert.Equal(0,opened);
            idle=true;task.NotifyHelpAvailabilityChanged();task.NotifyHelpAvailabilityChanged();
            Assert.Equal(1,opened);
        }
        [Fact] public void QueuedHelpLosesAdmissionToLootWithoutConsumingFailureBudget()
        {
            using var anchor=new Panel {Size=new Size(1024,576)};using var widget=HelpWidget(anchor);
            var task=new NativeGuidanceTask(widget,a=>a(),_=>true);bool idle=true;int opened=0,notices=0;
            NativeGuidanceTask.HelpPresentation pending=null;Action<bool> complete=null;
            task.CanOpenHelp=()=>idle;task.HelpUnavailable=()=>notices++;
            task.OpenHelp=(p,done)=>{opened++;pending=p;complete=done;};
            task.Handle(Show(guide:"start"));
            for(int i=0;i<4;i++) {
                var old=pending;idle=false;Assert.False(old.IsCurrent());complete(false);
                task.NotifyHelpClosed("loot","settlement");Assert.Equal(i+1,opened);
                idle=true;task.NotifyHelpAvailabilityChanged();Assert.False(old.IsCurrent());
                Assert.True(pending.IsCurrent());
            }
            complete(false);
            task.OpenHelp=(p,done)=>{opened++;done(false);};
            task.NotifyHelpAvailabilityChanged();task.NotifyHelpAvailabilityChanged();task.NotifyHelpAvailabilityChanged();
            Assert.Equal(7,opened);Assert.Equal(1,notices);
        }
        [Fact] public void DisabledAutoHelpRetiresOnceWhilePassiveSceneGuidesRemainVisible()
        {
            using var anchor=new Panel {Size=new Size(1024,576)};using var widget=HelpWidget(anchor);
            var sent=new List<string>();var task=new NativeGuidanceTask(widget,a=>a(),s=>{sent.Add(s);return true;});
            int opened=0;var reminders=new List<string>();task.HelpReminder=reminders.Add;
            task.AutomaticHelpEnabled=()=>false;task.OpenHelp=(p,done)=>{opened++;done(true);};
            task.Handle(Show(guide:"start"));task.Handle(Show(guide:"start",revision:2));task.NotifyHelpAvailabilityChanged();
            Assert.Equal(0,opened);var close=JObject.Parse(Assert.Single(sent).TrimEnd('\0'));
            Assert.Equal("nativeGuidanceAction",close.Value<string>("action"));Assert.Equal("close",close.Value<string>("verb"));
            Assert.Equal("开始",Assert.Single(reminders));
            task.Handle(Show(id:"ng:2"));Assert.True(widget.Visible);Assert.Single(sent);
            task.Handle(Show(id:"ng:3",guide:"start"));Assert.Equal(2,reminders.Count);
        }
        [Fact] public void DisabledTutorialReminderWaitsForTriggerAndSettlementAdmission()
        {
            using var anchor=new Panel {Size=new Size(1024,576)};using var widget=HelpWidget(anchor);
            var sent=new List<string>();var task=new NativeGuidanceTask(widget,a=>a(),s=>{sent.Add(s);return true;});
            int notices=0;bool idle=false;task.AutomaticHelpEnabled=()=>false;
            task.CanOpenHelp=()=>idle;task.HelpReminder=_=>notices++;
            var first=Show(guide:"start");first["payload"]["opacity"]=0;task.Handle(first);
            idle=true;task.NotifyHelpAvailabilityChanged();Assert.Equal(0,notices);Assert.Empty(sent);
            idle=false;task.Handle(Show(guide:"start",revision:2));task.NotifyHelpClosed("loot","settlement");
            Assert.Equal(0,notices);Assert.Empty(sent);
            idle=true;task.NotifyHelpAvailabilityChanged();task.NotifyHelpAvailabilityChanged();
            Assert.Equal(1,notices);Assert.Single(sent);
        }
        [Fact] public void DeferredReminderCannotSurviveSceneHideOrTransportEpoch()
        {
            using var anchor=new Panel {Size=new Size(1024,576)};using var widget=HelpWidget(anchor);
            var queue=new Queue<Action>();var task=new NativeGuidanceTask(widget,queue.Enqueue,_=>true);
            int notices=0;bool idle=false;task.AutomaticHelpEnabled=()=>false;
            task.CanOpenHelp=()=>idle;task.HelpReminder=_=>notices++;
            task.Handle(Show(guide:"start"));queue.Dequeue()();
            task.Handle(Hide());queue.Dequeue()();idle=true;task.NotifyHelpAvailabilityChanged();queue.Dequeue()();
            Assert.Equal(0,notices);
            task.Handle(Show(id:"ng:2",guide:"start"));task.HandleTransportDisconnected();
            while(queue.Count>0)queue.Dequeue()();Assert.Equal(0,notices);
            task.Handle(Show(guide:"start"));queue.Dequeue()();Assert.Equal(1,notices);
        }
        [Fact] public void PreferenceChangeRevokesPendingExactTutorialWithoutClosingForeignHelp()
        {
            using var anchor=new Panel {Size=new Size(1024,576)};using var widget=HelpWidget(anchor);
            var task=new NativeGuidanceTask(widget,a=>a(),_=>true);bool enabled=true;
            NativeGuidanceTask.HelpPresentation pending=null;Action<bool> complete=null;var closed=new List<string>();
            task.AutomaticHelpEnabled=()=>enabled;task.OpenHelp=(p,done)=>{pending=p;complete=done;};task.CloseHelp=closed.Add;
            task.Handle(Show(guide:"start"));enabled=false;Assert.False(pending.IsCurrent());
            task.NotifyHelpAvailabilityChanged();Assert.Equal(pending.PanelInstanceId,Assert.Single(closed));
            complete(false);task.NotifyHelpClosed("help","manual-help-instance");Assert.Single(closed);
            enabled=true;task.NotifyHelpAvailabilityChanged();Assert.False(pending.IsCurrent());Assert.Single(closed);
        }
    }
}
