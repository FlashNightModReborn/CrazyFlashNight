using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Windows.Forms;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.InputOwnership;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class IntroFocusRestoreTests
    {
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
            internal bool Admitted=true, Presented=true, Current=true, FocusAdmission=true;
            internal Action Tail;
            internal int FocusCalls, TailCalls;
            internal readonly RootFocusApi FocusApi = new();
            private readonly WindowManager _windows;
            internal IntPtr Foreground { get => FocusApi.Foreground; set => FocusApi.Foreground = value; }
            internal PanelHostController Host;
            internal Rig(SceneTransitionPresentationPolicy policy=null) {
                string root=Path.GetFullPath(Path.Combine(AppContext.BaseDirectory,"..","..","..",".."));
                _windows = new WindowManager(FocusApi, IntPtr.Zero);
                _windows.ConfigurePassiveInput(new SessionInputAuthority(), Owner);
                Controller=new SceneTransitionController(Owner,Owner,root,a=>a(),wire=> {
                    Sent.Add(JObject.Parse(wire.TrimEnd('\0')));return true;
                },()=>Admitted,_=>Presented,foreground=> {
                    FocusCalls++;
                    return _windows.ActivateSessionRootBeforeHide(foreground);
                },Array.Empty<OverlayBase>(),held=> {
                    Held.Add(held);Host?.SetTransitionInputHeld(held);
                },presentationPolicy:policy);
                Set(Controller,"_preparing",true);
                Controller.ConfigureSettlement(_=>true,s=>Current && s==2);
                Controller.ConfigureIntroPresentation(_=>true,_=>false,_=>FocusAdmission,()=>Foreground == Owner.Handle);
                Controller.SettlementSurface.ForegroundReaderForRecheck=()=>Foreground;
                Owner.Show();Foreground=Owner.Handle;
            }
            internal IntroPresentationHandoff Intro => (IntroPresentationHandoff)Get(Controller,"_intro");
            internal Form Cover => (Form)Get(Controller,"_fallback");
            internal bool CoverVisible => Cover.Visible;
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
            internal PanelHostController AttachHost() {
                Host=new PanelHostController(a=>a(),a=>a());
                Host.ConfigureCloseFocus(_windows);Host.ConfigureTransitionSettlement(Controller);
                return Host;
            }
            internal void Tick()=>Call(Controller,"Tick");
            public void Dispose() { _windows.StopPassiveFocusAudit();Host?.Dispose();Controller.Dispose();Owner.Dispose(); }
        }
        private static object Get(object target,string name)=>target.GetType()
            .GetField(name,BindingFlags.Instance|BindingFlags.NonPublic).GetValue(target);
        private static void Set(object target,string name,object value)=>target.GetType()
            .GetField(name,BindingFlags.Instance|BindingFlags.NonPublic).SetValue(target,value);
        private static void Call(object target,string name,params object[] args)=>target.GetType()
            .GetMethod(name,BindingFlags.Instance|BindingFlags.NonPublic).Invoke(target,args);

        [Fact] public void NaturalCloseHidesCoverBeforeTailAndSendsOnlyOneSurfaceReceipt() {
            using var r=new Rig();r.Tail=()=>Assert.False(r.CoverVisible);
            var h=r.Ready();Assert.True(r.CoverVisible);
            r.Tick();
            Assert.False(r.CoverVisible);Assert.Equal(1,r.TailCalls);Assert.True(h.SurfaceReady);
            Assert.False(r.Held[^1]);Assert.Equal(0,r.FocusCalls);
            Assert.Equal("intro_surface",Assert.Single(r.Sent).Value<string>("kind"));
            r.Tick();Assert.Single(r.Sent);Assert.Equal(1,r.TailCalls);
        }
        [Fact] public void SkipHideRetiresTailWithoutSendingSurfaceReceipt() {
            using var r=new Rig();var h=r.Ready();
            r.Controller.Task.Handle(new JObject { ["payload"]=Projection("hide","complete",4) });
            Assert.Equal(1,r.TailCalls);Assert.False(h.SurfaceReady);Assert.Empty(r.Sent);
        }
        [Theory]
        [InlineData(true)]
        [InlineData(false)]
        public void NativeCloseAndNarrativeCanArriveInEitherOrder(bool nativeFirst) {
            using var r=new Rig();var h=r.Show("opening");
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
            using var r=new Rig();var old=r.Ready();
            r.Controller.Task.Handle(new JObject { ["payload"]=Projection(revision:4,request:"tr:2",intro:"intro:2") });
            Assert.Equal(1,r.TailCalls);Assert.False(old.SurfaceReady);Assert.Empty(r.Sent);
            r.Controller.IntroComicClosed("panel:1",true);r.Tick();
            Assert.Empty(r.Sent);Assert.False(r.Intro.SurfaceReady);
        }
        [Theory]
        [InlineData("alt-tab")]
        [InlineData("minimized")]
        public void BackgroundAdmissionNeverStealsFocus(string mode) {
            using var r=new Rig();var h=r.Ready();
            if(mode=="alt-tab")r.Foreground=IntPtr.Zero;
            else r.Owner.WindowState=FormWindowState.Minimized;
            r.Tick();r.Tick();
            Assert.Equal(0,r.FocusCalls);Assert.Equal(0,r.TailCalls);Assert.False(h.SurfaceReady);Assert.Empty(r.Sent);
            if(mode=="minimized")r.Owner.WindowState=FormWindowState.Normal;
            r.Foreground=r.Owner.Handle;
            r.Tick();r.Tick();Assert.Empty(r.FocusApi.ForegroundWrites);Assert.True(h.SurfaceReady);Assert.Single(r.Sent);
        }
        [Fact] public void ClosingComicReturnsTheForegroundToTheRootBeforeReleasingItsCover() {
            using var r = new Rig();
            r.Tail = () => {
                Assert.False(r.CoverVisible);
                Assert.Equal(r.Owner.Handle, r.Foreground);
            };
            var intro = r.Ready();
            Assert.True(r.CoverVisible);
            r.Foreground = r.Cover.Handle;

            r.Tick();
            r.Tick();

            Assert.Equal(r.Owner.Handle, Assert.Single(r.FocusApi.ForegroundWrites));
            Assert.Equal(1, r.TailCalls);
            Assert.True(intro.SurfaceReady);
            Assert.Equal("intro_surface", Assert.Single(r.Sent).Value<string>("kind"));
        }
        [Fact] public void FailedRootActivationKeepsTheIntroHeldUntilTheRootOwnsForeground() {
            using var r = new Rig();
            var intro = r.Ready();
            r.Foreground = r.Cover.Handle;
            r.FocusApi.ApplyForegroundWrite = false;
            r.Tick();
            r.Tick();
            Assert.Equal(r.Owner.Handle, Assert.Single(r.FocusApi.ForegroundWrites));
            Assert.Equal(0, r.TailCalls);
            Assert.False(intro.SurfaceReady);
            Assert.Empty(r.Sent);

            r.Foreground = IntPtr.Zero;
            r.Tick();
            r.Foreground = r.Owner.Handle;
            r.Tick();
            Assert.True(intro.SurfaceReady);
            Assert.Single(r.Sent);
            Assert.Single(r.FocusApi.ForegroundWrites);
        }
        [Theory]
        [InlineData(false)]
        [InlineData(true)]
        public void TransitionHideReturnsOnlyOwnedForeground(bool externalForeground) {
            using var r = new Rig();
            using var external = new Form();
            r.Show();
            Assert.True(r.CoverVisible);
            r.Foreground = externalForeground ? external.Handle : r.Cover.Handle;
            Call(r.Controller, "HidePresentation", true);

            Assert.False(r.CoverVisible);
            Assert.False(r.Held[^1]);
            if (externalForeground)
            {
                Assert.Equal(external.Handle, r.Foreground);
                Assert.Empty(r.FocusApi.ForegroundWrites);
            }
            else
            {
                Assert.Equal(r.Owner.Handle, r.Foreground);
                Assert.Equal(r.Owner.Handle, Assert.Single(r.FocusApi.ForegroundWrites));
            }
        }
        [Fact] public void TailCleanupFailureAfterHideCannotPublishSurfaceReadiness() {
            using var r=new Rig();r.Tail=()=>r.FocusAdmission=false;
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
            var host=r.AttachHost();
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
            var host=r.AttachHost();
            host.SetBookComicTask(task);host.OpenPanel("book-comic",Data().ToString());
            Assert.Equal("book-comic",host.ActivePanelName);string instance=host.ActivePanelInstanceId;
            var h=r.Show();h.BindClosing(Data(),instance);Assert.True(h.BeginClose(instance));
            host.PanelChanged+=(panel,_)=> { if(panel==null)host.OpenPanel("intelligence","{}"); };
            Assert.True(host.TryClosePanelExact("book-comic",instance,_=>{}));Assert.True(h.Closed(instance));
            r.Tick();r.Tick();
            Assert.Equal("intelligence",host.ActivePanelName);Assert.Equal(0,r.FocusCalls);
            Assert.Equal(0,r.TailCalls);Assert.False(h.SurfaceReady);Assert.Empty(r.Sent);
        }
    }
}
