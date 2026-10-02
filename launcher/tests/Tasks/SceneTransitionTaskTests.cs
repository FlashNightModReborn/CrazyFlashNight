using System;
using System.Collections.Generic;
using CF7Launcher.Guardian;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Tasks
{
    public sealed class SceneTransitionTaskTests
    {
        private sealed class Rig {
            internal readonly List<JObject> Presented=new();
            internal readonly List<string> Sent=new();
            internal int Hidden;
            internal bool Delivery=true;
            internal readonly SceneTransitionTask Task;
            internal Rig(Action<Action> dispatch=null) {
                Task=new SceneTransitionTask(dispatch??(a=>a()),Presented.Add,()=>Hidden++,wire=>{Sent.Add(wire);return Delivery;});
            }
        }
        private static JObject Snapshot(string phase="cover",int revision=1,string rid="tr:1",string image="Andy")=>new() {
            ["payload"]=new JObject { ["version"]=1,["requestId"]=rid,["revision"]=revision,["phase"]=phase,
                ["imageId"]=image,["tip"]="原提示\n<原样文本>",["targetScene"]=2,["actionPending"]=false }};
        private static JObject Receipt(string kind="covered",int revision=1,long generation=0)=>new() {
            ["type"]="scene_transition_presented",["requestId"]="tr:1",["revision"]=revision,["generation"]=generation,["kind"]=kind };
        private static JObject Action(string verb="retry",int revision=1,long generation=0)=>new() {
            ["type"]="scene_transition_action",["requestId"]="tr:1",["revision"]=revision,["generation"]=generation,["verb"]=verb };
        private static JObject Report()=>new() {
            ["v"]=1,["runId"]="run.1",["stageName"]="并行返回",["difficulty"]="简单",["outcome"]="victory",
            ["activeFrames"]=900,["totalKills"]=0,["omittedKillTypes"]=0,["totalItemGains"]=0,
            ["totalItemLosses"]=0,["omittedItemFlowTypes"]=0,["rewardRollOmissions"]=0,
            ["kills"]=new JArray(),["itemFlows"]=new JArray(),["rewardStashed"]=true };
        private static JObject Parallel(string phase="cover",int revision=1,bool visible=true,bool handoff=false) {
            var s=Snapshot(phase,revision);var p=(JObject)s["payload"];
            p["version"]=2;p["report"]=Report();p["reportVisible"]=visible;p["reportHandoff"]=handoff;
            return s;
        }
        private static JObject PanelReceipt()=>new() {
            ["type"]="scene_transition_report_presented",["version"]=1,["panelInstanceId"]="loot:1",
            ["chestSessionId"]="chest:1",["lootContainerId"]="container:1",["containerEpoch"]=1,["runId"]="run.1" };
        private static LootPanelCoordinator.Binding Binding()=>new(new LootPanelCoordinator.OpenRequest {
            ChestSessionId="chest:1",LootContainerId="container:1",ContainerEpoch=1,
            SourceKind=LootPanelCoordinator.StageSettlementSource,SettlementReport=Report()},"loot:1");
        [Theory]
        [InlineData("report","null")][InlineData("reportVisible","1")][InlineData("reportHandoff","\"false\"")]
        [InlineData("version","99999999999999999999999999999999")]
        public void InvalidParallelProjectionCannotAdmitReport(string field,string value) {
            var r=new Rig();var p=Parallel();p["payload"][field]=JToken.Parse(value);r.Task.Handle(p);
            Assert.Empty(r.Presented);
        }
        [Fact] public void ReportMustAlreadyHaveDurableOwnerAndClosedShape() {
            var r=new Rig();var s=Parallel();s["payload"]["report"]["rewardStashed"]=false;r.Task.Handle(s);
            s=Parallel();s["payload"]["report"]["save"]=true;r.Task.Handle(s);
            s=Parallel(visible:false,handoff:true);r.Task.Handle(s);Assert.Empty(r.Presented);
        }
        [Fact] public void FrozenReportAndDismissalAreImmutableWithinTheReturn() {
            var r=new Rig();r.Task.Handle(Parallel());
            var altered=Parallel(revision:2);altered["payload"]["report"]["runId"]="run:2";r.Task.Handle(altered);
            Assert.Single(r.Presented);r.Task.Handle(Parallel(revision:2,visible:false));
            r.Task.Handle(Parallel(revision:3));Assert.False(r.Task.Current.Value<bool>("reportVisible"));
            r.Task.Handle(Snapshot(revision:3));Assert.Equal(2,r.Task.Current.Value<int>("version"));
        }
        [Fact] public void CloseDuringLoadingIsVisualOnlyAndNotRepeated() {
            var r=new Rig();r.Task.Handle(Parallel("loading"));r.Task.Action(Action("closeReport"));
            r.Task.Action(Action("closeReport"));Assert.Single(r.Sent);Assert.Contains("closeReport",r.Sent[0]);
            Assert.Equal(0,r.Hidden);Assert.True(r.Task.Current.Value<bool>("reportVisible"));
        }
        [Fact] public void CoveredReportCanBindRewardsBeforeTheSceneIsPrepared() {
            var early=new Rig();early.Task.Handle(Parallel("loading"));
            early.Task.Action(Action("manageReport"));Assert.Empty(early.Sent);
            Assert.True(early.Task.Presented(Receipt("covered")));early.Sent.Clear();
            early.Task.Action(Action("manageReport"));Assert.Single(early.Sent);Assert.Contains("manageReport",early.Sent[0]);
            Assert.False(early.Task.CompleteReportHandoff());
            var r=new Rig();r.Task.Handle(Parallel("reveal"));r.Task.Action(Action("manageReport"));Assert.Empty(r.Sent);
            Assert.False(r.Task.Presented(Receipt("prepared")));Assert.False(r.Task.Presented(Receipt("revealed")));
            r.Task.ScenePrepared();Assert.True(r.Task.Presented(Receipt("covered")));
            r.Task.Action(Action("manageReport"));Assert.Contains("manageReport",r.Sent[^1]);
        }
        [Fact] public void ExactHostClosureReturnsAnEarlyReportToTheLoadingCurtain() {
            var r=new Rig();r.Task.Handle(Parallel("loading",1,handoff:true));r.Sent.Clear();
            r.Task.ReportClosed();Assert.Single(r.Sent);Assert.Contains("closeReport",r.Sent[0]);
            r.Task.HandleTransportDisconnected();r.Sent.Clear();r.Task.ReportClosed();Assert.Empty(r.Sent);
        }
        [Theory]
        [InlineData("loading","manageReport")][InlineData("reveal","manageReport")]
        [InlineData("loading","closeReport")][InlineData("reveal","closeReport")]
        public void SameReportIntentSurvivesDisplayAdvanceAndIsSentOnce(string phase,string verb) {
            var r=new Rig();r.Task.Handle(Parallel());
            Assert.True(r.Task.Presented(Receipt()));r.Sent.Clear();
            r.Task.Handle(Parallel(phase,2));
            var tip=Parallel(phase,3);tip["payload"]["tip"]="加载提示更新";r.Task.Handle(tip);
            Assert.True(r.Task.MatchesWebAction(Action(verb)));
            Assert.False(r.Task.MatchesWeb(Action(verb)));
            r.Task.Action(Action(verb));Assert.Single(r.Sent);
            r.Task.Action(Action(verb,3));
            Assert.Single(r.Sent);
            var wire=JObject.Parse(r.Sent[0].TrimEnd('\0'));
            Assert.Equal(verb,wire.Value<string>("verb"));Assert.Equal(3,wire.Value<int>("revision"));
            Assert.False(r.Task.CompleteReportHandoff());
        }
        [Fact] public void ReportIntentStillRejectsForeignFutureMalformedAndUncoveredMessages() {
            var r=new Rig();r.Task.Handle(Parallel("loading",3));
            r.Task.Action(Action("manageReport"));Assert.Empty(r.Sent);
            Assert.True(r.Task.Presented(Receipt(revision:3)));r.Sent.Clear();
            foreach(var revision in new[]{"0","1.5","\"1\"","4","99999999999999999999999999"}) {
                var p=Action("manageReport");p["revision"]=JToken.Parse(revision);r.Task.Action(p);
            }
            var foreign=Action("manageReport");foreign["requestId"]="tr:2";r.Task.Action(foreign);
            r.Task.Action(Action("manageReport",generation:1));
            var extra=Action("manageReport");extra["save"]=true;r.Task.Action(extra);
            Assert.Empty(r.Sent);
        }
        [Fact] public void ReportIntentCannotUseDisplayAdvanceToReplayUnknownDelivery() {
            var r=new Rig();r.Task.Handle(Parallel());r.Task.Presented(Receipt());r.Sent.Clear();r.Delivery=false;
            r.Task.Action(Action("manageReport"));r.Task.Handle(Parallel("loading",3));
            r.Task.Action(Action("manageReport",3));r.Task.Action(Action("closeReport",3));
            Assert.Single(r.Sent);
        }
        [Fact] public void RewardAdmissionDoesNotLockTheLaterLoadingFailureActions() {
            var r=new Rig();var opening=Parallel("loading",1,handoff:true);opening["payload"]["actionPending"]=true;r.Task.Handle(opening);
            r.Task.Handle(Parallel("error",2,handoff:true));r.Task.Action(Action("retry",2));r.Task.Action(Action("return",2));
            Assert.Single(r.Sent);Assert.Contains("retry",r.Sent[0]);
        }
        [Theory]
        [InlineData("loot.pending",true)] [InlineData("foreign",false)] [InlineData("",false)]
        public void CompositionRewardIngressRequiresExactInstanceAndNarrowDomain(string instance,bool accepted) {
            var p=new JObject{["type"]="task",["task"]="loot_request",["panelInstanceId"]=instance};
            Assert.Equal(accepted,CompositionHelpSurface.IsSettlementMessage(p,"loot.pending"));
            p["task"]="save";Assert.False(CompositionHelpSurface.IsSettlementMessage(p,"loot.pending"));
            p["type"]="panel";p["panel"]="settings";p["cmd"]="snapshot";p["domain"]="inventory";
            Assert.False(CompositionHelpSurface.IsSettlementMessage(p,"loot.pending"));
        }
        [Fact] public void PreparedProofDoesNotSurviveTargetSceneChange() {
            var r=new Rig();r.Task.Handle(Parallel("reveal"));r.Task.ScenePrepared();r.Sent.Clear();
            var next=Parallel("reveal",2);next["payload"]["targetScene"]=3;r.Task.Handle(next);
            r.Task.Action(Action("manageReport",2));Assert.Empty(r.Sent);
        }
        [Fact] public void UnknownOpenDeliveryKeepsBothPreviewActionsLocked() {
            var r=new Rig();r.Task.Handle(Parallel("reveal"));r.Task.ScenePrepared();r.Sent.Clear();r.Delivery=false;
            r.Task.Action(Action("manageReport"));r.Task.Handle(Parallel("reveal",2));
            r.Task.Action(Action("manageReport",2));r.Task.Action(Action("closeReport",2));Assert.Single(r.Sent);
        }
        [Fact] public void DefinitiveHandoffRejectionAllowsCloseButDoesNotAutomaticallyReopen() {
            var r=new Rig();r.Task.Handle(Parallel("reveal"));r.Task.ScenePrepared();
            r.Task.Action(Action("manageReport"));var opening=Parallel("reveal",2,handoff:true);
            opening["payload"]["actionPending"]=true;r.Task.Handle(opening);
            r.Task.Handle(Parallel("reveal",3));r.Task.Action(Action("manageReport",3));
            Assert.Single(r.Sent.FindAll(w=>w.Contains("sceneTransitionAction")));
            r.Task.Action(Action("closeReport",3));
            Assert.Equal(2,r.Sent.FindAll(w=>w.Contains("sceneTransitionAction")).Count);
            Assert.Contains("closeReport",r.Sent[^1]);
        }
        private static JObject ViewState()=>new(){["scrollTop"]=80,["density"]="full",["rightTab"]="materials",["materialSearch"]="金属"};
        private static JObject ViewReceipt()=>new(){["type"]="scene_transition_report_view",["requestId"]="tr:1",["revision"]=1,["generation"]=0,["viewState"]=ViewState()};
        [Fact] public void PresentationStateIsReadOnlyAndBoundToCurrentVisibleReport() {
            var r=new Rig();r.Task.Handle(Parallel("loading"));
            Assert.True(r.Task.TryReportPresentation(ViewReceipt(),out var normalized));
            Assert.True(JToken.DeepEquals(ViewState(),normalized));Assert.Empty(r.Sent);Assert.Equal(0,r.Hidden);
            var late=ViewReceipt();late["revision"]=2;Assert.False(r.Task.TryReportPresentation(late,out _));
            late=ViewReceipt();late["generation"]=1;Assert.False(r.Task.TryReportPresentation(late,out _));
            late=ViewReceipt();late["save"]=true;Assert.False(r.Task.TryReportPresentation(late,out _));
            r.Task.Handle(Parallel("loading",2,visible:false));
            Assert.False(r.Task.TryReportPresentation(ViewReceipt(),out _));
        }
        [Theory]
        [InlineData("scrollTop","-1")][InlineData("scrollTop","1000001")][InlineData("scrollTop","1.5")][InlineData("scrollTop","\"80\"")]
        [InlineData("density","\"other\"")][InlineData("rightTab","\"claim\"")][InlineData("materialSearch","[]")]
        [InlineData("materialSearch","\"line\\nnext\"")]
        public void MalformedPresentationStateCannotChangeTheView(string field,string value) {
            var state=ViewState();state[field]=JToken.Parse(value);
            Assert.False(SceneTransitionTask.TryNormalizeReportPresentation(state,out _));
        }
        [Fact] public void RestoredPanelPaintKeepsExactAuthorityAndClosedPresentationShape() {
            var p=PanelReceipt();p["version"]=2;p["viewState"]=ViewState();
            Assert.True(SceneTransitionTask.MatchesSettlementReceipt(p,Binding(),true,"loot","loot:1"));
            p["viewState"]["claim"]=true;
            Assert.False(SceneTransitionTask.MatchesSettlementReceipt(p,Binding(),true,"loot","loot:1"));
            p["viewState"]=ViewState();p["runId"]="run.old";
            Assert.False(SceneTransitionTask.MatchesSettlementReceipt(p,Binding(),true,"loot","loot:1"));
        }
        [Fact] public void DocumentOrTransportRecoveryCannotRepeatAutomaticRewardAdmission() {
            var r=new Rig();r.Task.Handle(Parallel("reveal"));r.Task.ScenePrepared();r.Task.Action(Action("manageReport"));
            r.Task.HandleTransportDisconnected();r.Task.Handle(Parallel("reveal",2));r.Task.ScenePrepared();
            r.Task.Action(Action("manageReport",2,1));
            Assert.Single(r.Sent.FindAll(w=>w.Contains("sceneTransitionAction")));
        }
        [Theory]
        [InlineData("scene_transition_presented",true)][InlineData("scene_transition_action",true)]
        [InlineData("scene_transition_report_view",true)][InlineData("panel",false)]
        [InlineData("task",false)][InlineData("scene_transition_report_restore",false)]
        public void IndependentEndpointForwardsOnlyTheClosedProjectionChannel(string type,bool allowed) {
            Assert.Equal(allowed,CompositionHelpSurface.IsTransitionMessageType(type));
        }
        [Fact] public void FullReportHandoffRequiresCurrentOpenAndSuccessfulVisualAckQueue() {
            var r=new Rig();r.Task.Handle(Parallel("reveal"));Assert.False(r.Task.CompleteReportHandoff());
            r.Task.Handle(Parallel("reveal",2,handoff:true));r.Delivery=false;Assert.False(r.Task.CompleteReportHandoff());
            r.Delivery=true;Assert.True(r.Task.CompleteReportHandoff());Assert.All(r.Sent,w=>Assert.Contains("handoff",w));
            r.Task.HandleTransportDisconnected();Assert.False(r.Task.CompleteReportHandoff());
        }
        [Theory]
        [InlineData("panelInstanceId","\"loot:old\"")][InlineData("chestSessionId","\"old\"")]
        [InlineData("lootContainerId","\"old\"")][InlineData("containerEpoch","2")]
        [InlineData("containerEpoch","999999999999999999999999999")][InlineData("runId","\"run:old\"")]
        [InlineData("version","\"1\"")][InlineData("type","[]")]
        public void LateOrMalformedFullPanelPaintNeverReleasesCurtain(string field,string value) {
            var p=PanelReceipt();p[field]=JToken.Parse(value);
            Assert.False(SceneTransitionTask.MatchesSettlementReceipt(p,Binding(),true,"loot","loot:1"));
        }
        [Fact] public void FullPanelPaintMatchesExactBoundDurableSettlementOnly() {
            var p=PanelReceipt();var b=Binding();
            Assert.True(SceneTransitionTask.MatchesSettlementReceipt(p,b,true,"loot","loot:1"));
            Assert.False(SceneTransitionTask.MatchesSettlementReceipt(p,b,false,"loot","loot:1"));
            Assert.False(SceneTransitionTask.MatchesSettlementReceipt(p,b,true,"inventory","loot:1"));
            Assert.False(SceneTransitionTask.MatchesSettlementReceipt(p,b,true,"loot","loot:old"));
            b.SettlementReport["rewardStashed"]=false;
            Assert.False(SceneTransitionTask.MatchesSettlementReceipt(p,b,true,"loot","loot:1"));
        }
        [Fact] public void PaintMessageCannotCarryExtraAuthority() {
            var p=PanelReceipt();p["save"]=true;
            Assert.False(SceneTransitionTask.MatchesSettlementReceipt(p,Binding(),true,"loot","loot:1"));
        }
        [Theory]
        [InlineData("version","\"1\"")][InlineData("version","2")]
        [InlineData("revision","0")][InlineData("revision","1.5")]
        [InlineData("revision","99999999999999999999999999")]
        [InlineData("requestId","\"tr:01\"")][InlineData("requestId","\"tr:9007199254740992\"")]
        [InlineData("requestId","[]")][InlineData("phase","\"ready\"")]
        [InlineData("imageId","\"../save.dat\"")][InlineData("imageId","\"BLue\"")]
        [InlineData("tip","{}")][InlineData("targetScene","-1")][InlineData("actionPending","1")]
        public void InvalidSourceNeverGrantsDisplay(string field,string json) {
            var r=new Rig();var s=Snapshot();s["payload"][field]=JToken.Parse(json);r.Task.Handle(s);
            Assert.Empty(r.Presented);Assert.Empty(r.Sent);
        }
        [Fact] public void UnknownFieldsAndLongTipsAreRejected() {
            var r=new Rig();var s=Snapshot();s["payload"]["timeout"]=5000;r.Task.Handle(s);
            s=Snapshot();s["payload"]["tip"]=new string('a',2049);r.Task.Handle(s);Assert.Empty(r.Presented);
        }
        [Fact] public void SelectionIsImmutableAndBackgroundAllowlistIsExact() {
            var r=new Rig();r.Task.Handle(Snapshot(revision:2));r.Task.Handle(Snapshot(revision:3,image:"Blue"));
            Assert.Single(r.Presented);Assert.Equal("Andy",r.Task.Current.Value<string>("imageId"));
            r.Task.Handle(Snapshot(rid:"tr:2",image:"黑铁众"));Assert.Equal("黑铁众",r.Task.Current.Value<string>("imageId"));
        }
        [Fact] public void LateRevisionAndRetiredIdentityCannotResurrect() {
            var r=new Rig();r.Task.Handle(Snapshot(revision:3));r.Task.Handle(Snapshot(revision:2));
            r.Task.Handle(Snapshot("hide",4));r.Task.Handle(Snapshot(revision:5));
            Assert.Null(r.Task.Current);Assert.Equal(1,r.Hidden);
            r.Task.Handle(Snapshot(rid:"tr:2"));r.Task.Handle(Snapshot(revision:100));
            Assert.Equal("tr:2",r.Task.Current.Value<string>("requestId"));
        }
        [Fact] public void LostShowStillAcceptsTombstone() {
            var r=new Rig();r.Task.Handle(Snapshot("hide",2));r.Task.Handle(Snapshot(revision:3));Assert.Null(r.Task.Current);
        }
        [Fact] public void SourceCannotRegressRevealedOrErrorPhase() {
            var r=new Rig();r.Task.Handle(Snapshot("reveal"));r.Task.Handle(Snapshot("loading",2));
            Assert.Equal("reveal",r.Task.Current.Value<string>("phase"));
            r.Task.Handle(Snapshot("error",3));r.Task.Handle(Snapshot("reveal",4));Assert.Equal("error",r.Task.Current.Value<string>("phase"));
        }
        [Fact] public void ReceiptRetriesOnlyVisualAckAndBindsIdentityRevision() {
            var r=new Rig();r.Delivery=false;r.Task.Handle(Snapshot());r.Task.Presented(Receipt(revision:2));Assert.Empty(r.Sent);
            r.Task.Presented(Receipt());r.Delivery=true;r.Task.Handle(Snapshot());Assert.Equal(2,r.Sent.Count);
            Assert.All(r.Sent,w=>Assert.Contains("sceneTransitionPresented",w));
        }
        [Fact] public void MalformedPageRepliesNeverThrowOrNavigate() {
            var r=new Rig();r.Task.Handle(Snapshot("error"));
            foreach(var token in new[]{"[]","{}","99999999999999999999999999999","\"1\""}) {
                var a=Action();a["revision"]=JToken.Parse(token);r.Task.Action(a);
                var p=Receipt();p["type"]=JToken.Parse(token);r.Task.Presented(p);
            }
            var extra=Action();extra["save"]=true;r.Task.Action(extra);r.Task.Action(Action("close"));Assert.Empty(r.Sent);
        }
        [Fact] public void UnknownActionDeliveryLocksAndNeverReplays() {
            var r=new Rig();r.Task.Handle(Snapshot("error"));r.Delivery=false;
            r.Task.Action(Action());r.Task.Action(Action("return"));r.Task.Handle(Snapshot("error"));r.Task.Action(Action());
            Assert.Single(r.Sent);Assert.Contains("sceneTransitionAction",r.Sent[0]);
        }
        [Fact] public void AuthoritativeActionLockSurvivesPageRecreation() {
            var r=new Rig();var s=Snapshot("error");s["payload"]["actionPending"]=true;r.Task.Handle(s);
            r.Task.Action(Action());Assert.Empty(r.Sent);
        }
        [Fact] public void DisconnectKeepsCurtainAndFencesOldPageGeneration() {
            var r=new Rig();r.Task.Handle(Snapshot("error"));r.Task.HandleTransportDisconnected();
            Assert.False(r.Task.Connected);Assert.Equal(0,r.Hidden);r.Task.Action(Action());Assert.Empty(r.Sent);
            r.Task.Handle(Snapshot("error"));r.Task.Action(Action());Assert.Empty(r.Sent);
            r.Task.Action(Action(generation:1));Assert.Single(r.Sent);
        }
        [Fact] public void QueuedOldTransportCannotAdoptAfterDisconnect() {
            var q=new Queue<System.Action>();var r=new Rig(q.Enqueue);r.Task.Handle(Snapshot());
            r.Task.HandleTransportDisconnected();while(q.TryDequeue(out var work))work();Assert.Empty(r.Presented);
        }
        [Fact] public void SourcePayloadIsFrozenBeforeUiDispatch() {
            var q=new Queue<System.Action>();var r=new Rig(q.Enqueue);var s=Snapshot();r.Task.Handle(s);
            s["payload"]["imageId"]="Blue";q.Dequeue()();Assert.Equal("Andy",r.Task.Current.Value<string>("imageId"));
        }
    }
}
