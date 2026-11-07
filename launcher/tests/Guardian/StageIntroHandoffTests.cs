using System;
using System.Collections.Generic;
using CF7Launcher.Guardian;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class StageIntroHandoffTests
    {
        private static JObject Projection(string phase="intro",string state="opening",int revision=3) => new() {
            ["version"]=3,["requestId"]="tr:1",["revision"]=revision,["phase"]=phase,
            ["imageId"]="Andy",["tip"]="",["targetScene"]=2,["actionPending"]=false,
            ["introId"]="intro:1",["introState"]=state
        };
        private static JObject Data() => new() {
            ["v"]=2,["presentationId"]="bookcomic:1",["slot"]="bookrun_fixture",
            ["sceneId"]="scene:2",["pageId"]="prologue",["introId"]="intro:1"
        };
        private static IntroPresentationHandoff Handoff(string state="opening") {
            var h=new IntroPresentationHandoff(Projection(state:state),0);
            h.Observe(state,true); return h;
        }
        [Fact] public void ContentReadinessCannotActivateBeforeExactNativeEndpointIsPresented() {
            var h=Handoff(); int activated=0;
            Assert.True(h.QueueActivation(Data(),"panel:1",()=>activated++));
            Assert.False(h.TryActivate(_=>false));
            Assert.True(h.CoverRequired); Assert.Equal(0,activated);
            Assert.True(h.TryActivate(i=>i=="panel:1"));
            Assert.False(h.CoverRequired); Assert.Equal(1,activated);
            Assert.False(h.TryActivate(_=>true)); Assert.Equal(1,activated);
        }
        [Fact] public void CoveredRetirementCanAdmitTheExactOpenBeforeItsNextProjectionIsPumped() {
            var h=new IntroPresentationHandoff(Projection("loading","loading",2),0);
            Assert.False(h.Admits(Data()));
            h.TimelineRetired=true;
            Assert.True(h.Admits(Data()));
            Assert.True(h.QueueActivation(Data(),"panel:1",()=>{}));
            h.Observe("opening",true);
            Assert.True(h.TryActivate(_=>true));
            var wrong=Data();wrong["introId"]="intro:2";
            Assert.False(h.Admits(wrong));
            h.Observe("failed",true);Assert.False(h.Admits(Data()));
        }
        [Fact] public void OldIdentityCannotTransferCoverOrBindReplacementEndpoint() {
            var h=Handoff(); var other=Data(); other["introId"]="intro:2";
            Assert.False(h.QueueActivation(other,"panel:2",()=>throw new Exception()));
            Assert.True(h.QueueActivation(Data(),"panel:1",()=>{}));
            Assert.False(h.QueueActivation(Data(),"panel:2",()=>throw new Exception()));
            Assert.False(h.BeginClose("panel:2"));
            var projection=Projection(); projection["targetScene"]=3;
            Assert.False(h.Matches(projection,0));
            Assert.False(h.Matches(Projection(),1));
        }
        [Fact] public void FailureRetiresQueuedActivationAndRetryCannotReviveOldCallback() {
            var h=Handoff(); int old=0, fresh=0;
            Assert.True(h.QueueActivation(Data(),"panel:1",()=>old++));
            h.Observe("failed",true);
            Assert.True(h.CoverRequired); Assert.False(h.TryActivate(_=>true));
            Assert.False(h.Admits(Data()));
            h.Observe("opening",true);
            Assert.True(h.Admits(Data()));
            Assert.True(h.QueueActivation(Data(),"panel:2",()=>fresh++));
            Assert.True(h.TryActivate(_=>true));
            Assert.Equal(0,old); Assert.Equal(1,fresh);
        }
        [Theory]
        [InlineData(false,true,true)]
        [InlineData(true,false,true)]
        [InlineData(true,true,false)]
        public void ResumeNeedsExactSceneFreshFrameAndForegroundAdmission(bool scene,bool frame,bool admission) {
            var h=Handoff("narrative"); h.BindClosing(Data(),"panel:1");
            Assert.True(h.BeginClose("panel:1"));
            Assert.False(h.CanResume(true,true,true));
            Assert.True(h.Closed("panel:1"));
            Assert.False(h.CanResume(scene,frame,admission));
            Assert.True(h.CoverRequired);
        }
        [Fact] public void CloseAndRecoveryConsumeOnlyTheirOwnFocusTailOnce() {
            var h=Handoff("narrative"); int tail=0;
            h.BindClosing(Data(),"panel:1"); h.BeginClose("panel:1");
            Assert.False(h.DeferTail("foreign",()=>tail+=100));
            Assert.True(h.DeferTail("panel:1",()=>tail++));
            Assert.False(h.Closed("foreign")); Assert.True(h.Closed("panel:1"));
            Assert.True(h.CanResume(true,true,true)); h.Resumed(); h.Retire();
            Assert.Equal(1,tail); Assert.False(h.CoverRequired);
            Assert.False(h.CanResume(true,true,true));
        }
        [Theory]
        [InlineData("failed")]
        [InlineData("opening")]
        public void FailedOrUnpreparedNarrativeNeverResumesCombatSurface(string state) {
            var h=Handoff(state); h.BindClosing(Data(),"panel:1"); h.BeginClose("panel:1"); h.Closed("panel:1");
            Assert.False(h.CanResume(true,true,true)); Assert.True(h.CoverRequired);
        }
        [Fact] public void TaskKeepsProtectedRetirementSeparateFromOrdinaryReveal() {
            var shown=new List<JObject>(); var sent=new List<JObject>(); int hidden=0;
            var task=new SceneTransitionTask(a=>a(),shown.Add,()=>hidden++,wire=>{sent.Add(JObject.Parse(wire.TrimEnd('\0')));return true;});
            var cover=Projection("cover","loading",1); cover["version"]=1; cover.Remove("introId");cover.Remove("introState");
            task.Handle(new JObject { ["payload"]=cover });
            task.Handle(new JObject { ["payload"]=Projection("loading","loading",2) });
            Assert.Equal(3,task.Current.Value<int>("version"));
            task.Handle(new JObject { ["payload"]=Projection("reveal","loading",3) });
            Assert.True(task.RetireIntroUnderCover());
            Assert.Equal("intro_covered",sent[^1].Value<string>("kind"));
            Assert.Equal("intro:1",sent[^1].Value<string>("introId"));
            task.Handle(new JObject { ["payload"]=Projection("intro","narrative",4) });
            Assert.Equal(0,hidden); Assert.True(task.IntroSurfaceReady());
            task.Handle(new JObject { ["payload"]=Projection("intro","narrative",4) });
            Assert.Equal("intro_surface",sent[^1].Value<string>("kind"));
            var wrong=Projection("intro","resume",5);wrong["introId"]="intro:2";
            task.Handle(new JObject { ["payload"]=wrong });
            Assert.Equal("intro:1",task.Current.Value<string>("introId"));
            task.Handle(new JObject { ["payload"]=Projection("hide","complete",5) });
            Assert.Equal(1,hidden); Assert.Null(task.Current);
        }
        [Fact] public void RetryCannotResendThePreviousComicSurfaceReceipt() {
            var sent=new List<JObject>();
            var task=new SceneTransitionTask(a=>a(),_=>{},()=>{},wire=>{sent.Add(JObject.Parse(wire.TrimEnd('\0')));return true;});
            void Observe(string state,int revision) => task.Handle(new JObject { ["payload"]=Projection("intro",state,revision) });
            Observe("narrative",4);Assert.True(task.IntroSurfaceReady());Assert.Single(sent);
            Observe("failed",5);Observe("failed",5);
            Observe("opening",6);Observe("narrative",7);Observe("narrative",7);
            Assert.Single(sent);
            Assert.True(task.IntroSurfaceReady());Assert.Equal(2,sent.Count);
            Observe("resume",8);Observe("resume",8);
            Assert.Equal(3,sent.Count);Assert.Equal(8,sent[^1].Value<int>("revision"));
        }
        [Fact] public void IntroOpenRejectsMissingHostContractAndCannotChangeItsBoundTuple() {
            var data=Data(); using var task=new BookComicTask(()=>true,_=>true);
            Assert.NotNull(BookComicTask.BuildOpenData("book_chapter",data.ToString()));
            Assert.False(task.Reserve(data));
            task.IntroAdmission=d=>d.Value<string>("introId")=="intro:1";
            Assert.True(task.Reserve(data)); Assert.True(task.Bind("panel:1",data.ToString()));
            data["introId"]="intro:2"; Assert.False(task.CanOpen(data.ToString()));
            data["pageId"]="boss"; Assert.NotNull(BookComicTask.BuildOpenData("book_chapter",data.ToString()));
            Assert.False(task.CanOpen(data.ToString()));
        }
        [Theory]
        [InlineData("prologue")][InlineData("boss")][InlineData("cf6-s1")][InlineData("cf6-s2")]
        [InlineData("cf6-s3")][InlineData("cf6-s4")][InlineData("cf6-s5")][InlineData("cf6-s6")]
        public void EveryOpeningUsesTheSameCoveredActivationAndResume(string page) {
            var h=Handoff();var data=Data();data["pageId"]=page;var count=0;
            Assert.True(h.Admits(data));Assert.True(h.QueueActivation(data,"panel:1",()=>count++));
            h.Observe("narrative",true);Assert.True(h.TryActivate(_=>true));Assert.Equal(1,count);
            Assert.True(h.BeginClose("panel:1"));Assert.True(h.Closed("panel:1"));
            Assert.True(h.CanResume(true,true,true));h.Resumed();Assert.False(h.CoverRequired);
        }
        [Theory]
        [InlineData("presentationId","bookcomic:2")][InlineData("slot","foreign")]
        [InlineData("sceneId","scene:3")][InlineData("pageId","boss")][InlineData("introId","intro:2")]
        public void ClosingBeforePreparedCannotRebindAnyPartOfTheComicTuple(string key,string value) {
            var h=Handoff();h.BindClosing(Data(),"panel:1");
            var wrong=Data();wrong[key]=value;h.BindClosing(wrong,"panel:2");
            Assert.Equal("panel:1",h.Instance);Assert.False(h.Admits(wrong));
            Assert.False(h.QueueActivation(wrong,"panel:1",()=>throw new Exception()));
        }
        [Fact] public void BusinessPreparedReplyWaitsForPresentationAndLateActivationCannotResurrectRetiredComic() {
            var sent=new List<JObject>();var posted=new List<string>(); Action activate=null;int closing=0;
            using var task=new BookComicTask(()=>true,wire=>{sent.Add(JObject.Parse(wire.TrimEnd('\0')));return true;});
            task.SetPostToWeb(posted.Add,null,_=>closing++);task.IntroAdmission=_=>true;
            task.IntroPrepared=(d,i,ready)=>{Assert.Equal("intro:1",d.Value<string>("introId"));Assert.Equal("panel:1",i);activate=ready;};
            var data=Data();Assert.True(task.Reserve(data));Assert.True(task.Bind("panel:1",data.ToString()));
            var payload=(JObject)data.DeepClone();payload["v"]=1;payload.Remove("introId");
            task.HandleWebRequest("prepared",new JObject {
                ["panel"]="book-comic",["domain"]="book-comic",["callId"]="web:1",["panelInstanceId"]="panel:1",["payload"]=payload });
            var response=(JObject)Assert.Single(sent).DeepClone();
            Assert.Equal(1,response.Value<int>("v")); Assert.Null(response["introId"]);
            response["operation"]="prepared";response["success"]=true;response["phase"]="presenting";response["error"]="";
            task.HandleFlashResponse(response,null);
            Assert.Empty(posted);Assert.NotNull(activate);
            task.OnDisconnected();activate();
            Assert.Empty(posted);Assert.Equal(1,closing);
        }
        [Fact] public void RendererLossRejectsLatePreparedAndUsesExistingFailureBusinessRpc() {
            var sent=new List<JObject>();var posted=new List<string>();int queued=0;
            using var task=new BookComicTask(()=>true,wire=>{sent.Add(JObject.Parse(wire.TrimEnd('\0')));return true;});
            task.SetPostToWeb(posted.Add,null,_=>{});task.IntroAdmission=_=>true;
            task.IntroPrepared=(_,_,_)=>queued++;
            var data=Data();Assert.True(task.Reserve(data));
            task.OnDocumentInvalidated();Assert.Empty(sent); // First document is not a bound presentation.
            Assert.True(task.Bind("panel:1",data.ToString()));
            var payload=(JObject)data.DeepClone();payload["v"]=1;payload.Remove("introId");
            task.HandleWebRequest("prepared",new JObject {
                ["panel"]="book-comic",["domain"]="book-comic",["callId"]="web:1",["panelInstanceId"]="panel:1",["payload"]=payload });
            var prepared=(JObject)Assert.Single(sent).DeepClone();
            task.OnDocumentInvalidated();task.OnDocumentInvalidated();
            Assert.Equal(2,sent.Count);Assert.Equal("failed",sent[1].Value<string>("reason"));
            Assert.Equal("bookComicFinish",sent[1].Value<string>("action"));
            prepared["operation"]="prepared";prepared["success"]=true;prepared["phase"]="presenting";prepared["error"]="";
            task.HandleFlashResponse(prepared,null);
            Assert.Empty(posted);Assert.Equal(0,queued);Assert.False(task.CanOpen(data.ToString()));
        }
        [Fact] public void NewSessionRollbackDisablesCapabilityWithoutAcceptingHalfAnUpgrade() {
            string previous=Environment.GetEnvironmentVariable("CF7_STAGE_INTRO_HANDOFF");
            Environment.SetEnvironmentVariable("CF7_STAGE_INTRO_HANDOFF","0");
            try {
                var sent=new List<JObject>();
                var task=new SceneTransitionTask(a=>a(),_=>{},()=>{},wire=>{sent.Add(JObject.Parse(wire.TrimEnd('\0')));return true;});
                var cover=Projection("cover","loading",1);cover["version"]=1;cover.Remove("introId");cover.Remove("introState");
                task.Handle(new JObject { ["payload"]=cover });
                Assert.True(task.Presented(new JObject { ["type"]="scene_transition_presented",["requestId"]="tr:1",["revision"]=1,["generation"]=0,["kind"]="covered" }));
                Assert.Null(Assert.Single(sent)["introVersion"]);
                task.Handle(new JObject { ["payload"]=Projection("loading","loading",2) });
                Assert.Equal(1,task.Current.Value<int>("version"));
                Assert.False(task.RetireIntroUnderCover());
            } finally { Environment.SetEnvironmentVariable("CF7_STAGE_INTRO_HANDOFF",previous); }
        }
        [Fact] public void FailedCloseFinishesItsFocusTransactionWithoutGrantingSurfaceReadiness() {
            var h=Handoff("failed");int tails=0;
            h.BindClosing(Data(),"panel:1");h.BeginClose("panel:1");h.DeferTail("panel:1",()=>tails++);
            h.FinishFailedClose();Assert.Equal(0,tails);
            h.Closed("panel:1");h.FinishFailedClose();h.FinishFailedClose();
            Assert.Equal(1,tails);Assert.False(h.SurfaceReady);Assert.True(h.CoverRequired);
        }
        [Fact] public void ReloadedProtectionDocumentCanConfirmItsOwnCoverWithoutRevealingTheWorld() {
            var sent=new List<JObject>();
            var task=new SceneTransitionTask(a=>a(),_=>{},()=>{},wire=>{sent.Add(JObject.Parse(wire.TrimEnd('\0')));return true;});
            task.Handle(new JObject { ["payload"]=Projection("intro","opening",4) });
            JObject receipt(string kind)=>new() { ["type"]="scene_transition_presented",["requestId"]="tr:1",["revision"]=4,["generation"]=0,["kind"]=kind };
            Assert.True(task.Presented(receipt("covered")));
            Assert.Equal("covered",Assert.Single(sent).Value<string>("kind"));
            Assert.False(task.Presented(receipt("revealed")));
            Assert.False(task.RetireIntroUnderCover());
        }
        [Theory]
        [InlineData("intro","loading")]
        [InlineData("loading","complete")]
        [InlineData("hide","opening")]
        public void PhaseAndResponsibilityCannotContradictEachOther(string phase,string state) {
            var task=new SceneTransitionTask(a=>a(),_=>throw new Exception("invalid projection admitted"),()=>{},_=>true);
            task.Handle(new JObject { ["payload"]=Projection(phase,state) });Assert.Null(task.Current);
        }
    }
}
