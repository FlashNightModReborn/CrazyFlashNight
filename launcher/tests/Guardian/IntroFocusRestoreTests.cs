using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Windows.Forms;
using CF7Launcher.Guardian;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class IntroFocusRestoreTests
    {
        private static readonly IntPtr Flash=new(0x1001), FlashRoot=new(0x1000), Other=new(0x2001);
        private static JObject Projection(string phase="intro",string state="narrative",int revision=3,
            string request="tr:1",string intro="intro:1") => new() {
            ["version"]=3,["requestId"]=request,["revision"]=revision,["phase"]=phase,
            ["imageId"]="Andy",["tip"]="",["targetScene"]=2,["actionPending"]=false,
            ["introId"]=intro,["introState"]=state
        };
        private static JObject Data() => new() {
            ["v"]=2,["presentationId"]="bookcomic:1",["slot"]="bookrun_fixture",
            ["sceneId"]="scene:2",["pageId"]="prologue",["introId"]="intro:1"
        };
        private sealed class TestOwnerForm : Form
        {
            protected override bool ShowWithoutActivation => true;
        }
        private sealed class Rig : IDisposable
        {
            internal readonly TestOwnerForm Owner=new() { ShowInTaskbar=false,FormBorderStyle=FormBorderStyle.None,
                StartPosition=FormStartPosition.Manual,Location=new Point(-32000,-32000),Size=new Size(320,180) };
            internal readonly SceneTransitionController Controller;
            internal readonly List<JObject> Sent=new();
            internal readonly List<bool> Held=new();
            internal bool Admitted=true, Presented=true, Current=true, FocusAdmission=true, InputFocused, HandoffResult;
            internal Action Handoff, Tail;
            internal int FocusCalls, TailCalls;
            internal IntPtr Foreground;
            internal PanelHostController Host;
            internal Rig(SceneTransitionPresentationPolicy policy=null) {
                string root=Path.GetFullPath(Path.Combine(AppContext.BaseDirectory,"..","..","..",".."));
                Controller=new SceneTransitionController(Owner,Owner,root,a=>a(),wire=> {
                    Sent.Add(JObject.Parse(wire.TrimEnd('\0')));return true;
                },()=>Admitted,_=>Presented,foreground=> {
                    FocusCalls++;Handoff?.Invoke();return HandoffResult;
                },Array.Empty<OverlayBase>(),held=> {
                    Held.Add(held);Host?.SetTransitionInputHeld(held);
                },presentationPolicy:policy);
                Set(Controller,"_preparing",true);
                Controller.ConfigureSettlement(_=>true,s=>Current && s==2);
                Controller.ConfigureIntroPresentation(_=>true,_=>false,_=>FocusAdmission,()=>InputFocused);
                Controller.SettlementSurface.ForegroundReaderForRecheck=()=>Foreground;
                Owner.Show();Foreground=Owner.Handle;
            }
            internal IntroPresentationHandoff Intro => (IntroPresentationHandoff)Get(Controller,"_intro");
            internal bool CoverVisible => ((Form)Get(Controller,"_fallback")).Visible;
            internal IntroPresentationHandoff Show(string state="narrative") {
                Controller.Task.Handle(new JObject { ["payload"]=Projection(state:state) });
                return Intro;
            }
            internal IntroPresentationHandoff Ready(string instance="panel:1") {
                var h=Show();h.BindClosing(Data(),instance);
                Assert.True(h.BeginClose(instance));Assert.True(h.Closed(instance));
                Assert.True(Controller.DeferIntroResumeTail(instance,()=>{Tail?.Invoke();TailCalls++;}));
                return h;
            }
            internal PanelHostController AttachHost(FakeFocusApi api) {
                var manager=new WindowManager(api,Flash);
                Host=new PanelHostController(a=>a(),a=>a());
                Host.ConfigureCloseFocus(manager);Host.ConfigureTransitionSettlement(Controller);
                return Host;
            }
            internal void Tick()=>Call(Controller,"Tick");
            public void Dispose() { Host?.Dispose();Controller.Dispose();Owner.Dispose(); }
        }
        private static object Get(object target,string name)=>target.GetType()
            .GetField(name,BindingFlags.Instance|BindingFlags.NonPublic).GetValue(target);
        private static void Set(object target,string name,object value)=>target.GetType()
            .GetField(name,BindingFlags.Instance|BindingFlags.NonPublic).SetValue(target,value);
        private static void Call(object target,string name)=>target.GetType()
            .GetMethod(name,BindingFlags.Instance|BindingFlags.NonPublic).Invoke(target,null);

        [Fact] public void NaturalCloseHidesCoverBeforeTailAndSendsOnlyOneSurfaceReceipt() {
            using var r=new Rig();r.InputFocused=true;r.Tail=()=>Assert.False(r.CoverVisible);
            var h=r.Ready();Assert.True(r.CoverVisible);
            r.Tick();
            Assert.False(r.CoverVisible);Assert.Equal(1,r.TailCalls);Assert.True(h.SurfaceReady);
            Assert.False(r.Held[^1]);Assert.Equal(0,r.FocusCalls);
            Assert.Equal("intro_surface",Assert.Single(r.Sent).Value<string>("kind"));
            r.Tick();Assert.Single(r.Sent);Assert.Equal(1,r.TailCalls);
        }
        [Fact] public void SkipHideRetiresTailWithoutSendingSurfaceReceipt() {
            using var r=new Rig();r.InputFocused=true;var h=r.Ready();
            r.Controller.Task.Handle(new JObject { ["payload"]=Projection("hide","complete",4) });
            Assert.Equal(1,r.TailCalls);Assert.False(h.SurfaceReady);Assert.Empty(r.Sent);
        }
        [Theory]
        [InlineData(true)]
        [InlineData(false)]
        public void NativeCloseAndNarrativeCanArriveInEitherOrder(bool nativeFirst) {
            using var r=new Rig();r.InputFocused=true;var h=r.Show("opening");
            h.BindClosing(Data(),"panel:1");Assert.True(h.BeginClose("panel:1"));
            Assert.True(r.Controller.DeferIntroResumeTail("panel:1",()=>r.TailCalls++));
            if(nativeFirst) {
                Assert.True(h.Closed("panel:1"));r.Tick();Assert.Empty(r.Sent);
                r.Controller.Task.Handle(new JObject { ["payload"]=Projection(revision:4) });
            } else {
                r.Controller.Task.Handle(new JObject { ["payload"]=Projection(revision:4) });
                Assert.Empty(r.Sent);Assert.True(h.Closed("panel:1"));
            }
            r.Tick();Assert.True(h.SurfaceReady);Assert.Equal(1,r.TailCalls);
            Assert.Equal("intro_surface",Assert.Single(r.Sent).Value<string>("kind"));
        }
        [Fact] public void LateOldInstanceCannotResumeTheReplacementIntro() {
            using var r=new Rig();r.InputFocused=true;var old=r.Ready();
            r.Controller.Task.Handle(new JObject { ["payload"]=Projection(revision:4,request:"tr:2",intro:"intro:2") });
            Assert.Equal(1,r.TailCalls);Assert.False(old.SurfaceReady);Assert.Empty(r.Sent);
            r.Controller.IntroComicClosed("panel:1",true);r.Tick();
            Assert.Empty(r.Sent);Assert.False(r.Intro.SurfaceReady);
        }
        [Theory]
        [InlineData("alt-tab")]
        [InlineData("minimized")]
        public void BackgroundAdmissionNeverStealsFocus(string mode) {
            using var r=new Rig();var h=r.Ready();r.HandoffResult=false;
            if(mode=="alt-tab")r.Foreground=IntPtr.Zero;
            else r.Owner.WindowState=FormWindowState.Minimized;
            r.Tick();r.Tick();
            Assert.Equal(0,r.FocusCalls);Assert.Equal(0,r.TailCalls);Assert.False(h.SurfaceReady);Assert.Empty(r.Sent);
            if(mode=="minimized")r.Owner.WindowState=FormWindowState.Normal;
            r.Foreground=r.Owner.Handle;r.Handoff=()=>r.InputFocused=true;r.HandoffResult=true;
            r.Tick();r.Tick();Assert.Equal(1,r.FocusCalls);Assert.True(h.SurfaceReady);Assert.Single(r.Sent);
        }
        [Fact] public void FailedHandoffDoesNotRetryUntilANewActivation() {
            var logs=new List<string>();LogManager.SetSink(logs.Add);
            try {
                using var r=new Rig();var h=r.Ready();r.HandoffResult=false;
                r.Tick();r.Tick();
                Assert.Equal(1,r.FocusCalls);Assert.Equal(0,r.TailCalls);Assert.Empty(r.Sent);
                Assert.Equal(1,logs.Count(x=>x.Contains("event=stage_intro_focus_restore_failed")));
                r.Foreground=IntPtr.Zero;r.Tick();Assert.Equal(1,r.FocusCalls);
                r.Foreground=r.Owner.Handle;r.Handoff=()=>r.InputFocused=true;r.HandoffResult=true;
                r.Tick();r.Tick();
                Assert.Equal(2,r.FocusCalls);Assert.True(h.SurfaceReady);Assert.Single(r.Sent);
            } finally { LogManager.ResetSink(); }
        }
        [Fact] public void RootHandoffWithWrongInnerFocusWaitsForExistingActivationRecovery() {
            using var task=new CF7Launcher.Tasks.BookComicTask(()=>true,_=>true);task.IntroAdmission=_=>true;
            Assert.True(task.Reserve(Data()));
            using var r=new Rig();
            var api=new FakeFocusApi { Foreground=FlashRoot,Root=FlashRoot,Focused=Other };
            var host=r.AttachHost(api);
            host.SetBookComicTask(task);host.OpenPanel("book-comic",Data().ToString());
            string instance=host.ActivePanelInstanceId;
            var h=r.Show();h.BindClosing(Data(),instance);Assert.True(h.BeginClose(instance));
            Assert.True(host.TryClosePanelExact("book-comic",instance,_=>{}));
            Assert.True(r.Controller.DeferIntroResumeTail(instance,()=>r.TailCalls++));
            Assert.True(h.Closed(instance));r.HandoffResult=true;
            r.Tick();r.Tick();
            Assert.Equal(1,r.FocusCalls);Assert.Equal(1,r.TailCalls);Assert.False(r.CoverVisible);
            Assert.Equal(EffectiveInputOwnerKind.Transition,host.EffectiveInputOwner.Kind);Assert.False(host.GameOwnsInput);
            Assert.False(h.SurfaceReady);Assert.Empty(r.Sent);
            api.Focused=Flash;r.Tick();
            Assert.Equal(1,r.FocusCalls);Assert.Equal(1,r.TailCalls);Assert.True(h.SurfaceReady);Assert.Single(r.Sent);
            Assert.Equal(EffectiveInputOwnerKind.Game,host.EffectiveInputOwner.Kind);Assert.True(host.GameOwnsInput);
        }
        [Fact] public void TailCleanupFailureAfterHideCannotPublishSurfaceReadiness() {
            using var r=new Rig();r.InputFocused=true;r.Tail=()=>r.FocusAdmission=false;
            var h=r.Ready();r.Tick();
            Assert.Equal(1,r.TailCalls);Assert.False(h.SurfaceReady);Assert.Empty(r.Sent);Assert.True(r.Held[^1]);
        }
        [Fact] public void NonActivatingPolicyDoesNotRequireDesktopFocus() {
            using var r=new Rig(SceneTransitionPresentationPolicy.ArenaWorker);
            var h=r.Ready();r.Tick();
            Assert.Equal(0,r.FocusCalls);Assert.Equal(1,r.TailCalls);Assert.True(h.SurfaceReady);Assert.Single(r.Sent);
        }
        [Fact] public void TransitionHoldDoesNotRequireGameOwnsInputBeforeItsOwnRelease() {
            using var task=new CF7Launcher.Tasks.BookComicTask(()=>true,_=>true);task.IntroAdmission=_=>true;
            Assert.True(task.Reserve(Data()));
            using var r=new Rig();
            var host=r.AttachHost(new FakeFocusApi { Foreground=FlashRoot,Root=FlashRoot,Focused=Flash });
            host.SetBookComicTask(task);host.OpenPanel("book-comic",Data().ToString());
            Assert.Equal("book-comic",host.ActivePanelName);string instance=host.ActivePanelInstanceId;
            var h=r.Show();h.BindClosing(Data(),instance);Assert.True(h.BeginClose(instance));
            Assert.True(host.TryClosePanelExact("book-comic",instance,_=>{}));Assert.True(h.Closed(instance));
            Assert.Equal(EffectiveInputOwnerKind.Closing,host.EffectiveInputOwner.Kind);Assert.False(host.GameOwnsInput);
            r.Tick();
            Assert.True(h.SurfaceReady);Assert.Single(r.Sent);
            Assert.Equal(EffectiveInputOwnerKind.Game,host.EffectiveInputOwner.Kind);Assert.True(host.GameOwnsInput);
        }
        [Fact] public void SuccessorPanelKeepsFocusAndBlocksTheOldSurfaceReceipt() {
            using var task=new CF7Launcher.Tasks.BookComicTask(()=>true,_=>true);task.IntroAdmission=_=>true;
            Assert.True(task.Reserve(Data()));
            using var r=new Rig();
            var host=r.AttachHost(new FakeFocusApi { Foreground=FlashRoot,Root=FlashRoot,Focused=Other });
            host.SetBookComicTask(task);host.OpenPanel("book-comic",Data().ToString());
            Assert.Equal("book-comic",host.ActivePanelName);string instance=host.ActivePanelInstanceId;
            var h=r.Show();h.BindClosing(Data(),instance);Assert.True(h.BeginClose(instance));
            host.PanelChanged+=(panel,_)=> { if(panel==null)host.OpenPanel("intelligence","{}"); };
            Assert.True(host.TryClosePanelExact("book-comic",instance,_=>{}));Assert.True(h.Closed(instance));
            r.HandoffResult=true;r.Handoff=()=>r.InputFocused=true;r.Tick();r.Tick();
            Assert.Equal("intelligence",host.ActivePanelName);Assert.Equal(0,r.FocusCalls);
            Assert.Equal(0,r.TailCalls);Assert.False(h.SurfaceReady);Assert.Empty(r.Sent);
        }
        [Fact] public void CurrentFlashFocusCheckIsReadOnlyAndRejectsWrongInnerFocusOrEmbed() {
            var api=new FakeFocusApi { Foreground=FlashRoot,Root=FlashRoot,Focused=Other };
            var manager=new WindowManager(api,Flash);
            Assert.False(manager.IsCurrentFlashInputFocused());
            api.Focused=Flash;Assert.True(manager.IsCurrentFlashInputFocused());
            manager.ResetEmbedState();Assert.False(manager.IsCurrentFlashInputFocused());
            Assert.Equal(0,api.SetForegroundCallCount);Assert.Equal(0,api.SetFocusCallCount);Assert.Equal(0,api.AttachCallCount);
        }
        [Fact] public void DetachFailureRevokesTheCloseTailPermit() {
            var api=new FakeFocusApi { Foreground=FlashRoot,Root=FlashRoot,Focused=Other,DetachResult=false };
            var manager=CloseManager(api);var target=manager.CaptureFlashFocusTarget();
            var context=new HostCloseContext(new EndpointLease(null,null,null,"book-comic","panel:1","host",1,1,1,IntPtr.Zero),
                NativeCloseCause.PageClose,new JObject(),IntPtr.Zero);
            var permit=new FocusPermit(context,()=>true,target);Assert.True(permit.EnterLive());
            permit.RootVerified=true;Assert.True(permit.EnterTail());api.AfterSetFocus=()=>api.Focused=Flash;
            manager.RestoreFlashInnerFocusOnce("intro_detach",target,permit.Eligible,permit.Revoke);
            Assert.False(permit.Eligible());
            Assert.Equal(new[] {(42u,43u,true),(42u,43u,false)},api.AttachArguments);
        }
        private static WindowManager CloseManager(FakeFocusApi api) {
            api.ProcessId=(uint)Process.GetCurrentProcess().Id;
            var manager=new WindowManager(api,Flash);
            typeof(WindowManager).GetField("_registeredFocusProcess",BindingFlags.NonPublic|BindingFlags.Instance)
                .SetValue(manager,Process.GetCurrentProcess());
            return manager;
        }
        private sealed class FakeFocusApi : IFlashFocusWindowApi
        {
            internal IntPtr Foreground { get; set; }
            internal IntPtr Root { get; set; }
            internal IntPtr Focused { get; set; }
            internal uint ProcessId=200;
            internal bool DetachResult { get; set; }=true;
            internal Action AfterSetFocus { get; set; }
            internal int SetForegroundCallCount { get; private set; }
            internal int SetFocusCallCount { get; private set; }
            internal int AttachCallCount { get; private set; }
            internal readonly List<(uint from,uint to,bool attach)> AttachArguments=new();
            public IntPtr GetForegroundWindow()=>Foreground;
            public uint GetWindowThreadProcessId(IntPtr windowHandle,out uint processId) { processId=ProcessId;return 43; }
            public bool SetForegroundWindow(IntPtr windowHandle) { SetForegroundCallCount++;Foreground=windowHandle;return true; }
            public bool AttachThreadInput(uint from,uint to,bool attach) {
                AttachCallCount++;AttachArguments.Add((from,to,attach));return attach || DetachResult;
            }
            public IntPtr SetFocus(IntPtr windowHandle) { SetFocusCallCount++;AfterSetFocus?.Invoke();return windowHandle; }
            public uint GetCurrentThreadId()=>42;
            public bool IsWindow(IntPtr windowHandle)=>windowHandle!=IntPtr.Zero;
            public IntPtr GetRootWindow(IntPtr windowHandle)=>Root;
            public IntPtr GetFocusedWindow(IntPtr windowHandle)=>Focused;
            public bool IsChild(IntPtr parentWindow,IntPtr candidateChild)=>parentWindow==Flash && candidateChild!=Other;
        }
    }
}
