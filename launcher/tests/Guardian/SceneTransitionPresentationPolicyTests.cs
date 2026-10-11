using System.Collections.Generic;
using CF7Launcher.Guardian;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public class SceneTransitionPresentationPolicyTests
    {
        private static JObject Curtain() => new() {
            ["version"]=1,["requestId"]="tr:1",["revision"]=2,["phase"]="cover",
            ["imageId"]="TheGirl",["tip"]="正在准备场景",["targetScene"]=2,["actionPending"]=false
        };

        [Fact]
        public void OnlyExplicitWorkerAdmitsTheObservedReportFreeVersionOneCurtain()
        {
            var actual=Curtain();
            Assert.False(SceneTransitionPresentationPolicy.Interactive.AllowsBackgroundCurtain(actual,true,false,false,false));
            Assert.True(SceneTransitionPresentationPolicy.ArenaWorker.AllowsBackgroundCurtain(actual,true,false,false,false));
            foreach (var version in new JToken[] {new JValue(2),new JValue("1"),JValue.CreateNull()}) {
                var other=(JObject)actual.DeepClone(); other["version"]=version;
                Assert.False(SceneTransitionPresentationPolicy.ArenaWorker.AllowsBackgroundCurtain(other,true,false,false,false));
            }
            Assert.False(SceneTransitionPresentationPolicy.ArenaWorker.AllowsBackgroundCurtain(null,true,false,false,false));
        }

        [Theory]
        [InlineData("report")][InlineData("reportVisible")][InlineData("reportHandoff")]
        public void ReportFieldsCannotAcquireBackgroundPermissionEvenWhenNull(string field)
        {
            var projection=Curtain(); projection[field]=JValue.CreateNull();
            Assert.False(SceneTransitionPresentationPolicy.ArenaWorker.AllowsBackgroundCurtain(projection,true,false,false,false));
        }

        [Theory]
        [InlineData(false,false,false,false)]
        [InlineData(true,true,false,false)]
        [InlineData(true,false,true,false)]
        [InlineData(true,false,false,true)]
        public void DisconnectedSettlementBookshelfAndExclusivePresentationKeepTheirGuards(
            bool connected,bool retained,bool bookshelf,bool exclusive)
        {
            Assert.False(SceneTransitionPresentationPolicy.ArenaWorker.AllowsBackgroundCurtain(Curtain(),connected,retained,bookshelf,exclusive));
        }

        [Theory]
        [InlineData(false,true,false,true)]
        [InlineData(true,false,false,true)]
        [InlineData(true,true,true,true)]
        [InlineData(true,true,false,false)]
        public void WorkerStillRequiresReadyVisibleNonMinimizedAndConnected(
            bool admitted,bool visible,bool minimized,bool connected)
        {
            var policy=SceneTransitionPresentationPolicy.ArenaWorker;
            Assert.False(policy.CanPresentCurtain(admitted,visible,minimized,connected,false,true));
            Assert.False(policy.CanPresentCurtain(admitted,visible,minimized,connected,true,true));
        }

        [Fact]
        public void InteractiveSurfaceCannotBorrowBackgroundAdmissionAndWorkerNeverRequestsActivation()
        {
            var normal=SceneTransitionPresentationPolicy.Interactive;
            var worker=SceneTransitionPresentationPolicy.ArenaWorker;
            Assert.False(normal.NonActivating); Assert.True(worker.NonActivating);
            Assert.False(normal.CanPresentCurtain(true,true,false,true,false,true));
            Assert.False(normal.CanPresentSurface(true,false,false,true));
            Assert.True(normal.CanPresentCurtain(true,true,false,true,true,false));
            Assert.True(worker.CanPresentCurtain(true,true,false,true,false,true));
            Assert.True(worker.CanPresentSurface(true,false,false,true));
            Assert.False(worker.CanPresentSurface(false,false,false,true));
            Assert.False(worker.CanPresentSurface(true,true,false,true));
        }

        [Fact]
        public void BackgroundAdmissionDoesNotCreateOrLoosenPresentationReceipts()
        {
            var sent=new List<string>(); var displayed=new List<JObject>();
            var policy=SceneTransitionPresentationPolicy.ArenaWorker;
            var task=new SceneTransitionTask(action=>action(),projection=> {
                bool qualified=policy.AllowsBackgroundCurtain(projection,true,false,false,false);
                if(policy.CanPresentCurtain(true,true,false,true,false,qualified)) displayed.Add(projection);
            },()=>{},wire=>{sent.Add(wire);return true;});
            task.Handle(new JObject {["payload"]=Curtain()});
            Assert.Single(displayed); Assert.Empty(sent);
            var receipt=new JObject { ["type"]="scene_transition_presented",["requestId"]="tr:1",
                ["revision"]=2,["generation"]=0,["kind"]="covered" };
            var stale=(JObject)receipt.DeepClone(); stale["revision"]=1;
            Assert.False(task.Presented(stale)); Assert.Empty(sent);
            var foreign=(JObject)receipt.DeepClone(); foreign["requestId"]="tr:2";
            Assert.False(task.Presented(foreign)); Assert.Empty(sent);
            Assert.True(task.Presented(receipt)); Assert.Single(sent);
            task.HandleTransportDisconnected();
            Assert.False(task.Presented(receipt)); Assert.Single(sent);
        }
    }
}
