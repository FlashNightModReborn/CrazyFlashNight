using System;
using System.IO;
using System.Linq;
using CF7Launcher.Bus;
using CF7Launcher.Data;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Tasks
{
    public sealed class MapDomainSessionTests : IDisposable
    {
        private readonly string root = Path.Combine(Path.GetTempPath(), "cf7-map-session-" + Guid.NewGuid().ToString("N"));
        private readonly MapRuntimeContent content;
        public MapDomainSessionTests()
        {
            Directory.CreateDirectory(Path.Combine(root, "data/infrastructure"));
            File.WriteAllText(Path.Combine(root, "data/infrastructure/infrastructure.xml"), "<root><Infrastructure><Name>自行车</Name><Level/><Level/></Infrastructure><Infrastructure><Name>摩托车</Name><Level/><Level/></Infrastructure><Infrastructure><Name>越野车</Name><Level/><Level/></Infrastructure></root>");
            Directory.CreateDirectory(Path.Combine(root, "data/task/text"));
            File.WriteAllText(Path.Combine(root, "data/task/list.xml"), "<root><task>test.json</task></root>");
            File.WriteAllText(Path.Combine(root, "data/task/text/list.xml"), "<root><text>test.json</text></root>");
            File.WriteAllText(Path.Combine(root, "data/task/text/test.json"), "{}");
            File.WriteAllText(Path.Combine(root, "data/task/test.json"), "{tasks:[{id:1,title:'先交付',chain:'主线#1',get_npc:'甲',finish_npc:'甲',finish_npc_hotspot:'home'}," +
                "{id:2,title:'后交付',chain:'主线#2',get_npc:'甲',finish_npc:'甲',finish_npc_hotspot:'yard'}," +
                "{id:3,title:'跟随',chain:'支线#1',get_endpoint:{mode:'followCurrent',npcId:'person'},finish_endpoint:{mode:'followCurrent',npcId:'person'}}]}");
            content = new MapRuntimeContent(Definition(), MapTaskCatalog.Load(root), World());
        }
        internal static JObject Definition() => JObject.Parse(@"{version:2,pageOrder:['base'],pageAliases:{},sourceRefs:{},handTunedLayoutIds:{},xflSourceRects:{},avatarSources:{},assets:{},rules:{},
            locations:{home:{label:'家',sceneName:'房间',sceneKind:'base',enabled:true,enterWhen:{type:'always'},visibleWhen:{type:'always'}},yard:{label:'院子',sceneName:'院子',sceneKind:'base',enabled:true,enterWhen:{type:'always'},visibleWhen:{type:'always'}}},
            npcs:{person:{label:'人物甲',runtimeNames:['甲'],aliases:['老甲'],placementPolicy:'multiple'}},
            placements:{early:{npcId:'person',locationId:'home',label:'早期',enabled:true,presenceWhen:{type:'chain',key:'主线',min:0,max:9},worldBinding:{occurrenceId:'a',sourceDigest:'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'}},
              late:{npcId:'person',locationId:'yard',label:'后期',enabled:true,presenceWhen:{type:'chain',key:'主线',min:10},worldBinding:{occurrenceId:'b',sourceDigest:'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB'}}},
            pages:{base:{id:'base',title:'基地',tabLabel:'基地',width:1024,height:576,visibleWhen:{type:'always'},
              hotspots:[{id:'home',label:'家',locationId:'home',rect:{x:0,y:0,w:100,h:100}},{id:'yard',label:'院子',locationId:'yard',rect:{x:200,y:0,w:100,h:100}}],
              sceneVisuals:[],filters:[{id:'all',label:'全部',hotspotIds:['home','yard'],buttonRect:{x:0,y:0,w:60,h:28}}],staticAvatars:[]}}}");
        private static JObject World() => JObject.Parse(@"{a:{ready:true,sourceDigest:'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',sceneKey:'房间',taskName:'甲'},
            b:{ready:true,sourceDigest:'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB',sceneKey:'院子',taskName:'甲'}}");
        private static JObject Facts() => JObject.Parse(@"{chains:{'主线':0,'支线':0},finished:{},activeOrder:['1','2'],deliverableIds:['2'],available:{},
            infrastructure:{'自行车':false,'摩托车':false,'越野车':false},flags:{},scene:{stageFlag:'房间',frameLabel:'基地地图',entrance:'出生地',mapFrame:'',inCombat:false},navigation:{reason:''},dynamic:{roommateGender:'男'}}");
        private JObject Hello(MapDomainTask domain, int generation = 1) => domain.Process(JObject.Parse("{version:2,op:'hello'}"), generation, () => true)["result"] as JObject;
        private JObject Request(JObject hello, long revision = 1, long scene = 1) => new JObject { ["version"] = 2, ["op"] = "project", ["sessionToken"] = hello["sessionToken"], ["contentDigest"] = content.ContentDigest,
            ["revision"] = revision, ["sceneEpoch"] = scene, ["ready"] = true, ["facts"] = Facts(), ["interestTaskIds"] = new JArray(), ["captureIds"] = new JArray(), ["intent"] = null };
        [Fact]
        public void Session_ContentAndGenerationAreFenced()
        {
            using var domain = new MapDomainTask(content); var first = Hello(domain); var again = Hello(domain);
            Assert.Equal((string)first["sessionToken"], (string)again["sessionToken"]);
            var request = Request(first); Assert.True(domain.Process(request, 1, () => true).Value<bool>("success"));
            var second = Hello(domain, 2); Assert.NotEqual((string)first["sessionToken"], (string)second["sessionToken"]);
            Assert.Equal("invalid_session", (string)domain.Process(request, 1, () => true)["error"]);
            request = Request(second); request["contentDigest"] = new string('0', 64);
            Assert.Equal("invalid_session", (string)domain.Process(request, 2, () => true)["error"]);
            Assert.False(domain.Process(Request(second), 2, () => false).Value<bool>("success"));
            Assert.False(domain.Process(Request(second), 2, () => true, _ => false).Value<bool>("success"));
        }
        [Fact]
        public void RevisionRejectsOldOrReusedDifferentFactsAndReadyIsPartOfDigest()
        {
            using var domain = new MapDomainTask(content); var hello = Hello(domain); var request = Request(hello, 2, 3);
            Assert.True(domain.Process(request, 1, () => true).Value<bool>("success"));
            Assert.True(domain.Process(request, 1, () => true).Value<bool>("success"));
            request["ready"] = false; Assert.Equal("stale_facts", (string)domain.Process(request, 1, () => true)["error"]);
            request["revision"] = 3; Assert.Equal("game_not_ready", (string)domain.Process(request, 1, () => true)["error"]);
            Assert.Equal("stale_facts", (string)domain.Process(Request(hello, 2, 3), 1, () => true)["error"]);
            Assert.Equal("stale_facts", (string)domain.Process(Request(hello, 4, 2), 1, () => true)["error"]);
        }
        [Fact]
        public void RewardChangesPriorityAndLateOldDestinationCannotInstall()
        {
            // 同一人物允许同时两处驻点，保留武器大师类历史行为。
            var d = Definition(); d["placements"]["early"]["presenceWhen"] = MapDomainDefinition.Always(); d["placements"]["late"]["presenceWhen"] = MapDomainDefinition.Always();
            var runtime = new MapRuntimeContent(d, content.Catalog, World()); using var domain = new MapDomainTask(runtime);
            var hello = Hello(domain); var old = Request(hello); old["contentDigest"] = runtime.ContentDigest; old["intent"] = JObject.Parse("{kind:'deliverable'}");
            Assert.Equal("yard", (string)domain.Process(old, 1, () => true)["result"]["admission"]["locationId"]);
            var next = (JObject)old.DeepClone(); next["revision"] = 2; next["facts"]["deliverableIds"] = new JArray("1", "2");
            Assert.Equal("home", (string)domain.Process(next, 1, () => true)["result"]["admission"]["locationId"]);
            Assert.Equal("stale_facts", (string)domain.Process(old, 1, () => true)["error"]);
        }
        [Fact]
        public void LegacyAnySiteAndFixedPhysicalSiteSurviveCopiedPresentation()
        {
            var d = MapDefinition.Edit(Definition(), JArray.Parse("[{kind:'page',id:'base',action:'copy',values:{newId:'copy',title:'副本'}}]"));
            var facts = content.NormalizeFacts(Facts()); var projected = MapDomainService.Project(d, facts, content.Catalog.Tasks, World());
            Assert.Contains("1", ((JArray)projected["npcTasks"]["$甲"]["finish"]).Select(x => (string)x));
            Assert.DoesNotContain("2", ((JArray)projected["npcTasks"]["$甲"]["finish"]).Select(x => (string)x));
            Assert.Contains("3", ((JArray)projected["npcTasks"]["$老甲"]["get"]).Select(x => (string)x));
            Assert.True(projected["autoAccept"]["1"].Value<bool>("allowed"));
            Assert.Null(facts["tasks"]["3"]["available"]); // 未采样不冒充不可接/可接。
        }
        [Fact]
        public void FollowRequiresKnownUniquePresenceAndReadyMatchingWorld()
        {
            var d = Definition(); var facts = content.NormalizeFacts(Facts());
            d["placements"]["late"]["presenceWhen"] = JObject.Parse("{type:'task',key:'2',state:'available'}");
            var projected = MapDomainService.Project(d, facts, content.Catalog.Tasks, World());
            Assert.Equal("unknown_placement", (string)projected["taskEndpoints"]["3"]["get"]["status"]);
            d["placements"]["late"]["presenceWhen"] = MapDomainDefinition.Always();
            d["npcs"]["person"]["placementPolicy"] = "unique";
            projected = MapDomainService.Project(d, facts, content.Catalog.Tasks, World());
            Assert.Equal("ambiguous_placement", (string)projected["taskEndpoints"]["3"]["get"]["status"]);
            d = Definition(); var world = World(); world["a"]["sceneKey"] = "院子";
            projected = MapDomainService.Project(d, facts, content.Catalog.Tasks, world);
            Assert.Equal("world_binding_required", (string)projected["taskEndpoints"]["3"]["get"]["status"]);
            Assert.Null(projected["npcTasks"]["$老甲"]);
        }
        [Fact]
        public void FactsAreSocketOnlyAndRejectForgedTaskData()
        {
            TaskRegistry.ToStatusJson(false, 0, 0); Assert.False(TaskRegistry.IsHttpCallable("map_domain"));
            using var domain = new MapDomainTask(content); var request = Request(Hello(domain)); request["facts"]["playerSave"] = new JObject();
            Assert.False(domain.Process(request, 1, () => true).Value<bool>("success"));
            request = Request(Hello(domain)); request["facts"]["deliverableIds"] = new JArray("3");
            Assert.False(domain.Process(request, 1, () => true).Value<bool>("success"));
        }
        [Theory]
        [InlineData(true)]
        [InlineData(false)]
        public void SelectedDestinationKeepsTheChosenTaskWhenAnEarlierTaskIsDeliverable(bool returning)
        {
            var d = Definition(); d["placements"]["early"]["presenceWhen"] = MapDomainDefinition.Always(); d["placements"]["late"]["presenceWhen"] = MapDomainDefinition.Always();
            var runtime = new MapRuntimeContent(d, content.Catalog, World()); using var domain = new MapDomainTask(runtime);
            var request = Request(Hello(domain)); request["contentDigest"] = runtime.ContentDigest;
            request["facts"]["deliverableIds"] = new JArray("1", "2");
            request["facts"]["scene"]["inCombat"] = returning; request["facts"]["navigation"]["reason"] = returning ? "stage_run_active" : "";
            request["intent"] = JObject.Parse("{kind:'stage_return',taskId:'2',npcId:'person',placementId:'late',locationId:'yard'}");
            if (!returning) request["intent"]["kind"] = "task_delivery";
            var response = domain.Process(request, 1, () => true);
            Assert.True(response.Value<bool>("success"));
            Assert.Equal("home", (string)response["result"]["projection"]["delivery"]["hotspotId"]);
            Assert.True(response["result"]["admission"].Value<bool>("admitted"));
            Assert.Equal("yard", (string)response["result"]["admission"]["locationId"]);
            if (returning) Assert.Equal("2", (string)response["result"]["admission"]["taskId"]);
        }
        [Theory]
        [InlineData("incomplete", true)]
        [InlineData("inactive", true)]
        [InlineData("npc", true)]
        [InlineData("placement", true)]
        [InlineData("location", true)]
        [InlineData("pending", true)]
        [InlineData("combat", true)]
        [InlineData("absent", true)]
        [InlineData("incomplete", false)]
        [InlineData("inactive", false)]
        [InlineData("npc", false)]
        [InlineData("placement", false)]
        [InlineData("location", false)]
        [InlineData("pending", false)]
        [InlineData("combat", false)]
        [InlineData("absent", false)]
        public void SelectedDestinationRejectsChangedAuthorityWithoutChoosingAnotherTask(string change, bool returning)
        {
            using var domain = new MapDomainTask(content); var request = Request(Hello(domain));
            request["facts"]["deliverableIds"] = new JArray("1", "2");
            request["facts"]["scene"]["inCombat"] = returning; request["facts"]["navigation"]["reason"] = returning ? "stage_run_active" : "";
            request["intent"] = JObject.Parse("{kind:'stage_return',taskId:'1',npcId:'person',placementId:'early',locationId:'home'}");
            if (!returning) request["intent"]["kind"] = "task_delivery";
            switch (change) {
                case "incomplete": request["facts"]["deliverableIds"] = new JArray("2"); break;
                case "inactive": request["facts"]["activeOrder"] = new JArray("2"); request["facts"]["deliverableIds"] = new JArray("2"); break;
                case "npc": request["intent"]["npcId"] = "wrong"; break;
                case "placement": request["intent"]["placementId"] = "late"; break;
                case "location": request["intent"]["locationId"] = "yard"; break;
                case "pending": request["facts"]["navigation"]["reason"] = "pending_stage_settlement"; break;
                case "combat": request["facts"]["scene"]["inCombat"] = !returning; break;
                case "absent": request["facts"]["chains"]["主线"] = 10; break;
            }
            var response = domain.Process(request, 1, () => true);
            Assert.True(response.Value<bool>("success"));
            Assert.False(response["result"]["admission"].Value<bool>("admitted"));
            Assert.Null(response["result"]["admission"]["frame"]);
        }
        private static JObject PrivateYardDefinition()
        {
            var d = Definition();
            ((JArray)d["pages"]["base"]["hotspots"]).Last.Remove();
            ((JArray)d["pages"]["base"]["filters"][0]["hotspotIds"]).Last.Remove();
            d["placements"]["late"]["presenceWhen"] = MapDomainDefinition.Always();
            return d;
        }
        [Theory]
        [InlineData(true)]
        [InlineData(false)]
        public void PrivateCompletedTaskCanReturnOrDeliverWithoutPublicMapNavigation(bool returning)
        {
            var runtime = new MapRuntimeContent(PrivateYardDefinition(), content.Catalog, World());
            using var domain = new MapDomainTask(runtime);
            var request = Request(Hello(domain)); request["contentDigest"] = runtime.ContentDigest;
            request["facts"]["scene"]["inCombat"] = returning;
            request["facts"]["navigation"]["reason"] = returning ? "stage_run_active" : "";
            request["intent"] = JObject.Parse("{kind:'stage_return',taskId:'2',npcId:'person',placementId:'late',locationId:'yard'}");
            if (!returning) request["intent"]["kind"] = "task_delivery";
            var response = domain.Process(request, 1, () => true);
            Assert.True(response.Value<bool>("success"));
            Assert.True(response["result"]["admission"].Value<bool>("admitted"));
            Assert.Equal("院子", (string)response["result"]["admission"]["frame"]);
            Assert.Equal("", (string)response["result"]["admission"]["hotspotId"]);
            Assert.Null(response["result"]["projection"]["snapshot"]["hotspotStates"]["yard"]);
            // 即使地点和任务可交付，普通地图导航也不能借 locationId 绕开隐藏入口。
            request["revision"] = 2; request["facts"]["scene"]["inCombat"] = false;
            request["facts"]["navigation"]["reason"] = "";
            request["intent"] = JObject.Parse("{kind:'navigate',targetId:'yard'}");
            response = domain.Process(request, 1, () => true);
            Assert.True(response.Value<bool>("success"));
            Assert.False(response["result"]["admission"].Value<bool>("admitted"));
            request["intent"] = JObject.Parse("{kind:'task_finish',taskId:'2'}");
            response = domain.Process(request, 1, () => true);
            Assert.True(response["result"]["admission"].Value<bool>("admitted"));
        }
        [Theory]
        [InlineData("incomplete")]
        [InlineData("inactive")]
        [InlineData("locked")]
        [InlineData("absent")]
        [InlineData("pending")]
        [InlineData("npc")]
        public void PrivateTaskRoutesStillRequireCompletionSceneAccessAndExactSelection(string change)
        {
            foreach (bool returning in new[] { true, false })
            {
                var d = PrivateYardDefinition();
                if (change == "locked") d["locations"]["yard"]["enterWhen"] = JObject.Parse("{type:'chain',key:'主线',min:10}");
                if (change == "absent") d["placements"]["late"]["enabled"] = false;
                var runtime = new MapRuntimeContent(d, content.Catalog, World());
                using var domain = new MapDomainTask(runtime);
                var request = Request(Hello(domain)); request["contentDigest"] = runtime.ContentDigest;
                request["facts"]["scene"]["inCombat"] = returning;
                request["facts"]["navigation"]["reason"] = returning ? "stage_run_active" : "";
                request["intent"] = JObject.Parse("{kind:'stage_return',taskId:'2',npcId:'person',placementId:'late',locationId:'yard'}");
                if (!returning) request["intent"]["kind"] = "task_delivery";
                if (change == "incomplete") request["facts"]["deliverableIds"] = new JArray();
                if (change == "inactive") { request["facts"]["activeOrder"] = new JArray("1"); request["facts"]["deliverableIds"] = new JArray(); }
                if (change == "pending") request["facts"]["navigation"]["reason"] = "pending_stage_settlement";
                if (change == "npc") request["intent"]["npcId"] = "wrong";
                var response = domain.Process(request, 1, () => true);
                Assert.True(response.Value<bool>("success"));
                Assert.False(response["result"]["admission"].Value<bool>("admitted"));
                Assert.Null(response["result"]["admission"]["frame"]);
            }
        }
        public void Dispose() { Directory.Delete(root, true); }
    }
}
