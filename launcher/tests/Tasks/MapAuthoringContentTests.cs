using System;
using System.IO;
using System.Linq;
using System.Text;
using CF7Launcher.Data;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Tasks
{
    public sealed class MapAuthoringContentTests : IDisposable
    {
        private readonly string root = Path.Combine(Path.GetTempPath(), "cf7-map-content-test-" + Guid.NewGuid().ToString("N"));
        public MapAuthoringContentTests()
        {
            Put("data/infrastructure/infrastructure.xml", "<root><Infrastructure><Name>自行车</Name><Level/><Level/></Infrastructure></root>");
            Put("data/task/list.xml", "<root><task>task.json</task></root>");
            Put("data/task/text/list.xml", "<root><text>text.json</text></root>"); Put("data/task/text/text.json", "{}");
            Put("data/task/task.json", "{\r\n  \"tasks\": [\r\n    {\"id\":1,\"title\":\"甲任务\",\"chain\":\"主线#1\",\"get_npc\":\"甲\",\"finish_npc\":\"甲\",\"rewards\":[\"金币#1\"]},\r\n    {\"id\":2, \"title\":\"其他任务字节保留\", \"chain\":\"主线#2\", \"get_npc\":\"甲\"}\r\n  ]\r\n}\r\n");
            File.WriteAllBytes(PathFor(MapDefinition.RelativePath), MapDefinition.Bytes(Definition()));
        }
        private string PathFor(string relative)
        {
            string path = Path.Combine(root, relative.Replace('/', Path.DirectorySeparatorChar)); Directory.CreateDirectory(Path.GetDirectoryName(path)); return path;
        }
        private void Put(string relative, string text) => File.WriteAllText(PathFor(relative), text, new UTF8Encoding(false));
        private static JObject Definition()
        {
            var d = JObject.Parse(@"{version:2,pageOrder:['base'],pageAliases:{},sourceRefs:{},handTunedLayoutIds:{},xflSourceRects:{},avatarSources:{},assets:{},rules:{},
                locations:{home:{label:'家',sceneName:'房间',sceneKind:'base',enabled:true,enterWhen:{type:'always'},visibleWhen:{type:'always'}}},
                npcs:{person:{label:'甲',runtimeNames:['甲'],aliases:[],placementPolicy:'multiple'}},
                placements:{home_npc:{npcId:'person',locationId:'home',label:'家中驻点',enabled:true,presenceWhen:{type:'always'},worldBinding:null,legacyWorldAdapter:true}},
                pages:{base:{id:'base',title:'基地',tabLabel:'基地',width:1024,height:576,visibleWhen:{type:'always'},
                  hotspots:[{id:'home',label:'家',locationId:'home',rect:{x:0,y:0,w:100,h:100}}],
                  sceneVisuals:[{id:'home_visual',label:'家图块',assetUrl:'assets/map/home.webp',hotspotIds:['home'],filterIds:['all'],rect:{x:0,y:0,w:100,h:100}}],
                  filters:[{id:'all',label:'全部',hotspotIds:['home'],buttonRect:{x:0,y:0,w:60,h:28}}],
                  staticAvatars:[{id:'home_avatar',label:'甲',placementId:'home_npc',hotspotId:'home',assetUrl:'assets/map/person.webp',relX:10,relY:10,w:44,h:44,visibleWhen:{type:'always'}}]}}}");
            MapDefinition.Validate(d); return d;
        }
        [Fact]
        public void CopyPage_RekeysViewsButNotPhysicalLocationsOrPeople()
        {
            var source = Definition();
            var copy = MapDefinition.Edit(source, JArray.Parse("[{kind:'page',id:'base',action:'copy',values:{newId:'second',title:'第二页'}}]"));
            Assert.Equal(2, ((JArray)copy["pageOrder"]).Count);
            Assert.Single(((JObject)copy["locations"]).Properties()); Assert.Single(((JObject)copy["npcs"]).Properties());
            Assert.NotEqual("home", (string)copy["pages"]["second"]["hotspots"][0]["id"]);
            Assert.Equal("home", (string)copy["pages"]["second"]["hotspots"][0]["locationId"]);
            Assert.Equal("home_npc", (string)copy["pages"]["second"]["staticAvatars"][0]["placementId"]);
            Assert.Equal((string)copy["pages"]["second"]["hotspots"][0]["id"], (string)copy["pages"]["second"]["sceneVisuals"][0]["hotspotIds"][0]);
            Assert.Single((JArray)source["pageOrder"]);
        }
        [Fact]
        public void DeleteReferencedLocationFailsAndSceneDragUpdatesUnion()
        {
            Assert.Throws<InvalidDataException>(() => MapDefinition.Edit(Definition(), JArray.Parse("[{kind:'location',id:'home',action:'delete',values:{}}]")));
            var edited = MapDefinition.Edit(Definition(), JArray.Parse("[{kind:'scene',pageId:'base',id:'home_visual',values:{rect:{x:10,y:20,w:120,h:140}}}]"));
            Assert.Equal(10, (int)edited["pages"]["base"]["hotspots"][0]["rect"]["x"]);
            Assert.Equal(140, (int)edited["pages"]["base"]["hotspots"][0]["rect"]["h"]);
        }
        [Fact]
        public void TaskPatch_OnlyTargetObjectChangesAndOtherFieldsAreProtected()
        {
            var catalog = MapTaskCatalog.Load(root);
            var patch = MapTaskSourcePatch.Apply(catalog, JArray.Parse("[{kind:'task',id:'1',values:{finish_endpoint:{mode:'fixed',npcId:'person',placementId:'home_npc'}}}]"), Definition());
            byte[] before = catalog.SourceBytes["data/task/task.json"], after = patch.Files["data/task/task.json"];
            string originalOther = "{\"id\":2, \"title\":\"其他任务字节保留\", \"chain\":\"主线#2\", \"get_npc\":\"甲\"}";
            Assert.Contains(originalOther, Encoding.UTF8.GetString(after)); Assert.Contains("\r\n", Encoding.UTF8.GetString(after));
            Assert.Null(patch.Tasks["1"]["finish_npc"]); Assert.Equal("甲", (string)patch.Tasks["1"]["get_npc"]);
            MapTaskSourcePatch.ValidateOnlyEndpointsChanged(before, after);
            var corrupt = JObject.Parse(Encoding.UTF8.GetString(after)); corrupt["tasks"][0]["rewards"] = new JArray("金币#999");
            Assert.Throws<InvalidDataException>(() => MapTaskSourcePatch.ValidateOnlyEndpointsChanged(before, MapDefinition.Bytes(corrupt)));
        }
        private (MapChangeJournal Journal, JObject Record, byte[] MapBefore, byte[] MapAfter, byte[] TaskBefore, byte[] TaskAfter) Prepared()
        {
            var journal = new MapChangeJournal(root); var before = File.ReadAllBytes(PathFor(MapDefinition.RelativePath));
            var d = MapDefinition.Parse(before); d["pages"]["base"]["title"] = "候选标题"; var after = MapDefinition.Bytes(d);
            var tasks = MapTaskCatalog.Load(root); var taskChanges = JArray.Parse("[{kind:'task',id:'1',values:{finish_endpoint:{mode:'fixed',npcId:'person',placementId:'home_npc'}}}]");
            var patched = MapTaskSourcePatch.Apply(tasks, taskChanges, d); byte[] taskBefore = tasks.SourceBytes["data/task/task.json"], taskAfter = patched.Files["data/task/task.json"];
            var files = new JArray(MapChangeJournal.FileChange(MapDefinition.RelativePath, before, after), MapChangeJournal.FileChange("data/task/task.json", taskBefore, taskAfter));
            var record = journal.Prepare(Guid.NewGuid().ToString("N"), "test-binding", MapDefinition.Hash(before), MapDefinition.Hash(after), taskChanges, files);
            return (journal, record, before, after, taskBefore, taskAfter);
        }
        [Fact]
        public void PartialApply_RecoveryRestoresOriginalBytes()
        {
            var p = Prepared(); File.WriteAllBytes(PathFor(MapDefinition.RelativePath), p.MapAfter);
            Assert.Equal("partial", (string)p.Journal.State(p.Record)["state"]);
            p.Journal.RecoverPending();
            Assert.Equal(p.MapBefore, File.ReadAllBytes(PathFor(MapDefinition.RelativePath)));
            Assert.Equal(p.TaskBefore, File.ReadAllBytes(PathFor("data/task/task.json")));
            Assert.Empty(Directory.EnumerateFiles(Path.Combine(root, "tmp/map-workbench/pending")));
        }
        [Fact]
        public void CompleteWritesBeforeReceipt_RecoveryRecognizesAppliedAndUndoRestoresBoth()
        {
            var p = Prepared(); File.WriteAllBytes(PathFor(MapDefinition.RelativePath), p.MapAfter); File.WriteAllBytes(PathFor("data/task/task.json"), p.TaskAfter);
            p.Journal.RecoverPending(); var record = p.Journal.Read((string)p.Record["operationId"]);
            Assert.Equal("applied", (string)record["phase"]); p.Journal.Undo(record);
            Assert.Equal(p.MapBefore, File.ReadAllBytes(PathFor(MapDefinition.RelativePath))); Assert.Equal(p.TaskBefore, File.ReadAllBytes(PathFor("data/task/task.json")));
        }
        [Fact]
        public void PartialWithForeignEdit_RecoveryNeverOverwritesIt()
        {
            var p = Prepared(); File.WriteAllBytes(PathFor(MapDefinition.RelativePath), p.MapAfter); Put("data/task/task.json", "{\"tasks\":[]}");
            Assert.Throws<InvalidDataException>(() => p.Journal.RecoverPending());
            Assert.Equal("{\"tasks\":[]}", File.ReadAllText(PathFor("data/task/task.json")));
            Assert.Equal("recovery_required", (string)p.Journal.State(p.Record)["state"]);
        }
        [Fact]
        public void JournalRejectsTaskRewardWritesAndUnlistedFiles()
        {
            var p = Prepared(); var journal = new MapChangeJournal(root);
            var forbidden = new JArray(MapChangeJournal.FileChange("data/task/text/text.json", new byte[] { 123, 125 }, new byte[] { 123, 125 }));
            Assert.Throws<InvalidDataException>(() => journal.Prepare(Guid.NewGuid().ToString("N"), "x", "x", "y", new JArray(), forbidden));
            var changed = JObject.Parse(Encoding.UTF8.GetString(p.TaskAfter)); changed["tasks"][0]["rewards"] = new JArray("金币#999");
            Assert.Throws<InvalidDataException>(() => journal.Prepare(Guid.NewGuid().ToString("N"), "x", "x", "y", new JArray(),
                new JArray(MapChangeJournal.FileChange("data/task/task.json", p.TaskBefore, MapDefinition.Bytes(changed)))));
        }
        [Fact]
        public void DateLikeLabelsRemainStrings()
        {
            var d = Definition(); d["pages"]["base"]["title"] = "2026-09-06T08:00:00Z";
            Assert.Equal(JTokenType.String, MapDefinition.Parse(MapDefinition.Bytes(d))["pages"]["base"]["title"].Type);
        }
        [Fact]
        public void UndoCannotRemoveAnImageReferencedByIndependentWebContent()
        {
            string url = "assets/map/imported/" + new string('a', 64) + ".webp";
            MapAssetCandidates.RequireNoExternalReferences(root, new[] { url });
            Put("launcher/web/modules/independent.js", "var shared = '" + url + "';");
            var error = Assert.Throws<InvalidDataException>(() => MapAssetCandidates.RequireNoExternalReferences(root, new[] { url }));
            Assert.Contains("independent.js", error.Message);
        }
        [Fact]
        public void ReferenceValidationRejectsPrimitiveEndpointInsteadOfSilentlyTreatingItAsLegacy()
        {
            var tasks = MapTaskCatalog.Load(root).Tasks; tasks["1"]["finish_endpoint"] = "invalid";
            Assert.Throws<InvalidDataException>(() => MapAuthoringPlan.ValidateTaskReferences(Definition(), tasks));
        }
        [Fact]
        public void CopiedPageSharesPhysicalIdentityButProjectsBothMarkersAndHudViews()
        {
            var d = MapDefinition.Edit(Definition(), JArray.Parse("[{kind:'page',id:'base',action:'copy',values:{newId:'second',title:'第二页'}}]"));
            var tasks = MapTaskCatalog.Load(root).Tasks;
            var facts = JObject.Parse("{scene:{stageFlag:'房间'},tasks:{'1':{active:true,deliverable:true}},activeOrder:['1'],navigation:{reason:''}}");
            var p = MapDomainService.Project(d, facts, tasks);
            Assert.Equal("home", (string)p["currentLocationId"]); Assert.Equal("1", (string)p["hudMode"]);
            Assert.Equal(2, ((JArray)p["snapshot"]["markers"]).Count(m => (string)m["kind"] == "currentLocation"));
            Assert.Equal(2, ((JArray)p["snapshot"]["markers"]).Count(m => (string)m["kind"] == "taskNpc"));
            Assert.Equal(2, ((JObject)MapDefinition.Hud(d, (JObject)p["snapshot"])["hotspots"]).Count);
            Assert.Single((JArray)p["npcTasks"]["$甲"]["finish"]);
        }
        [Fact]
        public void UnknownEarlierAppearanceBranchHidesBothWebAndHudUntilFactsResolve()
        {
            var d = Definition();
            d["pages"]["base"]["sceneVisuals"][0]["variants"] = JArray.Parse("[{id:'late',when:{type:'chain',key:'主线',min:30},assetUrl:'assets/map/late.webp'},{id:'otherwise',when:{type:'always'},assetUrl:'assets/map/default.webp'}]");
            var unknown = MapDomainService.Project(d, new JObject(), new JObject());
            Assert.False((bool)unknown["snapshot"]["visualVisibility"]["base"]["home_visual"]);
            Assert.Empty((JArray)MapDefinition.Hud(d, (JObject)unknown["snapshot"])["hotspots"]["home"]["outline"]["visuals"]);
            var known = MapDomainService.Project(d, JObject.Parse("{chains:{'主线':30}}"), new JObject());
            Assert.True((bool)known["snapshot"]["visualVisibility"]["base"]["home_visual"]);
            Assert.Equal("assets/map/late.webp", (string)MapDefinition.Hud(d, (JObject)known["snapshot"])["hotspots"]["home"]["outline"]["visuals"][0]["assetUrl"]);
            var early = MapDomainService.Project(d, JObject.Parse("{chains:{'主线':0}}"), new JObject());
            Assert.Equal("assets/map/default.webp", (string)early["snapshot"]["visualAssetUrls"]["base"]["home_visual"]);
        }
        [Fact]
        public void CompletedCommitIsNotRolledBackWhenPendingMarkerCleanupFails()
        {
            var p = Prepared(); string id = (string)p.Record["operationId"];
            Put("tmp/map-workbench/pending/" + id + ".json", "{\"operationId\":\"" + id + "\",\"binding\":\"foreign\"}");
            Assert.Throws<InvalidDataException>(() => p.Journal.Commit(p.Record));
            Assert.Equal("applied", (string)p.Journal.Read(id)["phase"]);
            Assert.Equal(p.MapAfter, File.ReadAllBytes(PathFor(MapDefinition.RelativePath)));
            Assert.Equal(p.TaskAfter, File.ReadAllBytes(PathFor("data/task/task.json")));
        }
        [Fact]
        public void TrailingSeparatorCannotCreateASecondAuthoringMutex()
        {
            string name = "Local\\CF7MapAuthoring-" + MapDefinition.Hash(MapDefinition.Utf8.GetBytes(root.ToUpperInvariant()));
            using var mutex = new System.Threading.Mutex(false, name); Assert.True(mutex.WaitOne(0));
            try { Assert.Throws<IOException>(() => System.Threading.Tasks.Task.Run(() => new MapAuthoringStore(root + Path.DirectorySeparatorChar).Read()).GetAwaiter().GetResult()); }
            finally { mutex.ReleaseMutex(); }
        }
        [Fact]
        public void MissingAssetCatalogueRemainsInspectableButRuntimeAndApplyStayStrict()
        {
            var assets = new MapAssetCandidates(root); var d = Definition();
            var entries = assets.Existing(d); Assert.Equal(2, entries.Count);
            Assert.All(entries, entry => Assert.False(entry.Value<bool>("ready")));
            Assert.Throws<InvalidDataException>(() => assets.Resolve(d));
            Assert.ThrowsAny<IOException>(() => MapAssetCandidates.ValidatePublished(root, d));
        }
        [Fact]
        public void SceneBackedPlacementsSurviveEditsWhileUnbackedNewPlacementsRequireSceneNpc()
        {
            var d = Definition(); var tasks = MapTaskCatalog.Load(root).Tasks;
            Assert.True(MapDomainService.Project(d, new JObject(), tasks)["taskEndpoints"]["1"]["finish"].Value<bool>("resolved"));
            var edited = MapDefinition.Edit(d, JArray.Parse("[{kind:'placement',id:'home_npc',values:{presenceWhen:{type:'chain',key:'主线',min:0}}}]"));
            Assert.True(edited["placements"]["home_npc"].Value<bool>("legacyWorldAdapter"));
            Assert.True(MapDomainService.Project(edited, JObject.Parse("{chains:{'主线':0}}"), tasks)["taskEndpoints"]["1"]["finish"].Value<bool>("resolved"));
            // 新建尚未接入真实场景的驻点（无场景检出、无已核对标记）不得伪报就绪。
            var newlyCreated = MapDefinition.Edit(Definition(), JArray.Parse("[{kind:'npc',id:'bob',action:'create',values:{label:'乙',runtimeNames:['乙'],aliases:[],placementPolicy:'unique'}},{kind:'placement',id:'bob_home',action:'create',values:{npcId:'bob',locationId:'home',label:'乙驻点',presenceWhen:{type:'always'}}}]"));
            var bobTasks = JObject.Parse("{'99':{id:99,get_endpoint:{mode:'fixed',npcId:'bob',placementId:'bob_home'},finish_endpoint:{mode:'followCurrent',npcId:'bob'}}}");
            var unbackedProj = MapDomainService.Project(newlyCreated, new JObject(), bobTasks, new JObject());
            Assert.False(unbackedProj["placements"]["bob_home"].Value<bool>("worldReady"));
            Assert.False(unbackedProj["taskEndpoints"]["99"]["get"].Value<bool>("resolved"));
            Assert.Equal("world_binding_required", (string)unbackedProj["taskEndpoints"]["99"]["get"]["status"]);
            Assert.False(unbackedProj["taskEndpoints"]["99"]["finish"].Value<bool>("resolved"));
            // 一旦场景目录检出同名真实 NPC 实例（即便未显式绑 worldBinding），该驻点即就绪。
            var backedProj = MapDomainService.Project(newlyCreated, new JObject(), bobTasks, JObject.Parse("{occ_bob:{ready:false,sceneKey:'房间',runtimeName:'乙',taskName:'乙'}}"));
            Assert.True(backedProj["placements"]["bob_home"].Value<bool>("worldReady"));
            Assert.True(backedProj["taskEndpoints"]["99"]["get"].Value<bool>("resolved"));
            Assert.True(backedProj["taskEndpoints"]["99"]["finish"].Value<bool>("resolved"));
            // 显式 worldBinding 若场景导出不可用仍标记未就绪，但不再比较易变摘要。
            d["placements"]["home_npc"]["worldBinding"] = JObject.Parse("{occurrenceId:'npc',sourceDigest:'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'}");
            Assert.False(MapDomainService.Project(d, new JObject(), tasks, JObject.Parse("{npc:{ready:false}}"))["taskEndpoints"]["1"]["finish"].Value<bool>("resolved"));
            Assert.True(MapDomainService.Project(d, new JObject(), tasks, JObject.Parse("{npc:{ready:true,sourceDigest:'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB',sceneKey:'房间',taskName:'甲'}}"))["taskEndpoints"]["1"]["finish"].Value<bool>("resolved"));
            Assert.Throws<InvalidDataException>(() => MapDefinition.Edit(Definition(), JArray.Parse("[{kind:'placement',id:'fake',action:'create',values:{npcId:'person',locationId:'home',legacyWorldAdapter:true}}]")));
        }
        [Fact]
        public void RuntimeStartupRecoversPendingBatchDegradesMissingSwfPerLocationAndFiltersLegacySaveKeys()
        {
            // R2: 仅当存在未完成批次时自动恢复，拒绝把半截任务文件与旧地图定义混入运行态。
            var pending = Prepared();
            File.WriteAllBytes(PathFor("data/task/task.json"), pending.TaskAfter);
            Assert.Equal("partial", (string)pending.Journal.State(pending.Record)["state"]);
            var recoveredRuntime = new MapRuntimeContent(root, _ => { });
            Assert.Equal("original", (string)pending.Journal.State(pending.Record)["state"]);
            Assert.Null(recoveredRuntime.Catalog.Tasks["1"]["finish_endpoint"]);

            // R4 + 容错降级：单地点缺失关卡 SWF 时仅禁用该地点导航，不影响端点静态身份与健康地点。
            var d = Definition();
            d["locations"]["broken"] = JObject.Parse("{label:'坏下水道',sceneName:'地图-坏下水道',sceneKind:'outdoor',enabled:true,enterWhen:{type:'always'},visibleWhen:{type:'always'},sceneBinding:{sourceSwf:'flashswf/levels/missing.swf',linkage:'地图-坏下水道'}}");
            ((JArray)d["pages"]["base"]["hotspots"]).Add(JObject.Parse("{id:'broken',label:'坏下水道',locationId:'broken',rect:{x:200,y:0,w:100,h:100}}"));
            ((JArray)d["pages"]["base"]["filters"][0]["hotspotIds"]).Add("broken");
            File.WriteAllBytes(PathFor(MapDefinition.RelativePath), MapDefinition.Bytes(d));
            Put("data/task/task.json", "{\"tasks\":[{\"id\":1,\"title\":\"甲任务\",\"chain\":\"主线#1\",\"get_npc\":\"甲\",\"finish_npc\":\"甲\"},{\"id\":9,\"title\":\"未映射端点\",\"chain\":\"支线#1\",\"get_endpoint\":{\"mode\":\"followCurrent\",\"npcId\":\"missing_npc\"}}]}");
            var warnings = new System.Collections.Generic.List<string>();
            var runtime = new MapRuntimeContent(root, warnings.Add);
            Assert.NotEmpty(warnings);
            var rawFacts = JObject.Parse("{chains:{'主线':1,'已删旧链':5},infrastructure:{'自行车':1,'旧基建':2},flags:{},finished:{'1':1,'999999':2},activeOrder:[],deliverableIds:[],available:{},scene:{stageFlag:'房间',frameLabel:'基地地图',entrance:'',mapFrame:'',inCombat:false},navigation:{reason:''},dynamic:{roommateGender:''}}");
            var normalized = runtime.NormalizeFacts(rawFacts);
            Assert.Null(normalized["chains"]["已删旧链"]);
            Assert.Null(normalized["infrastructure"]["旧基建"]);
            var projected = runtime.Project(normalized);
            Assert.Equal("unmapped_endpoint", (string)projected["taskEndpoints"]["9"]["get"]["status"]);
            Assert.True(projected["taskEndpoints"]["1"]["get"].Value<bool>("resolved"));
            Assert.False(projected["locations"]["broken"].Value<bool>("enterable"));
            Assert.False(projected["snapshot"]["hotspotStates"]["broken"].Value<bool>("enabled"));
            Assert.Contains("场景资源", (string)projected["snapshot"]["hotspotStates"]["broken"]["lockedReason"]);
            // 健康地点（无错误项）仍保持可进入。
            var healthyOnly = MapDomainService.Project(d, normalized, runtime.Catalog.Tasks, runtime.WorldOccurrences, new JObject { ["broken"] = "缺失测试 SWF" });
            Assert.True(healthyOnly["locations"]["home"].Value<bool>("enterable"));
            Assert.True(healthyOnly["snapshot"]["hotspotStates"]["home"].Value<bool>("enabled"));
            Assert.False(healthyOnly["locations"]["broken"].Value<bool>("enterable"));
            Assert.False(healthyOnly["snapshot"]["hotspotStates"]["broken"].Value<bool>("enabled"));
        }
        [Fact]
        public void FilterReorderUpdatesTheProductionSortCoordinateAndSceneCopyUsesItsNewLabel()
        {
            var d = MapDefinition.Edit(Definition(), JArray.Parse("[{kind:'filter',pageId:'base',id:'second',action:'create',values:{label:'另一层'}}]"));
            var moved = MapDefinition.Edit(d, JArray.Parse("[{kind:'filter',pageId:'base',id:'second',action:'reorder',values:{index:0}},{kind:'scene',pageId:'base',id:'home_visual',action:'copy',values:{newId:'copy',title:'图块副本'}}]"));
            Assert.Equal("second", (string)moved["pages"]["base"]["filters"][0]["id"]);
            Assert.True((double)moved["pages"]["base"]["filters"][0]["buttonRect"]["y"] < (double)moved["pages"]["base"]["filters"][1]["buttonRect"]["y"]);
            Assert.Equal("图块副本", (string)moved["pages"]["base"]["sceneVisuals"][1]["label"]);
        }
        [Fact]
        public void ExtraSourcesMergeOverlayTasksAndTextsWithOverlayPriority()
        {
            var baseline = MapTaskCatalog.Load(root);
            Put("data/rag/agent_saves/slotA/agent_tasks.json",
                "{\"tasks\":[{\"id\":200001,\"title\":\"$AGENT_T1\",\"chain\":\"委托#1\",\"get_npc\":\"甲\",\"get_npc_hotspot\":\"home\"},{\"id\":1,\"title\":\"覆盖后的甲任务\",\"chain\":\"主线#1\",\"get_npc\":\"甲\"}]}");
            Put("data/rag/agent_saves/slotA/agent_text.json", "{\"$AGENT_T1\":\"终端委托\"}");
            var sources = new[] { MapTaskCatalog.AgentSaveTaskSource("slotA") };
            var texts = new[] { MapTaskCatalog.AgentSaveTextSource("slotA") };
            var catalog = MapTaskCatalog.Load(root, null, sources, texts);
            Assert.Equal("终端委托", catalog.Title((JObject)catalog.Tasks["200001"]));
            Assert.Equal("覆盖后的甲任务", (string)catalog.Tasks["1"]["title"]);
            Assert.Equal("data/rag/agent_saves/slotA/agent_tasks.json", catalog.TaskFiles["1"]);
            Assert.Contains("data/rag/agent_saves/slotA/agent_text.json", catalog.SourceBytes.Keys);
            Assert.Contains("委托", catalog.Chains);
            Assert.NotEqual(baseline.Digest, catalog.Digest);
            // ChangedSources 覆盖额外源：内容一致不列入，改动的文件才列入。
            Assert.Empty(MapTaskCatalog.ChangedSources(catalog, MapTaskCatalog.Load(root, null, sources, texts)));
            Put("data/rag/agent_saves/slotA/agent_text.json", "{\"$AGENT_T1\":\"终端委托·改\"}");
            Assert.Equal(new[] { "data/rag/agent_saves/slotA/agent_text.json" },
                MapTaskCatalog.ChangedSources(catalog, MapTaskCatalog.Load(root, null, sources, texts)));
        }
        [Fact]
        public void ExtraSourcesAreOptionalAndFailClosed()
        {
            var baseline = MapTaskCatalog.Load(root);
            Assert.Equal(baseline.Digest, MapTaskCatalog.Load(root, null,
                new[] { MapTaskCatalog.AgentSaveTaskSource("ghost") }, new[] { MapTaskCatalog.AgentSaveTextSource("ghost") }).Digest);
            Put("data/rag/agent_saves/slotA/agent_tasks.json", "{\"tasks\":[{\"id\":\"bad\"}]}");
            string source = MapTaskCatalog.AgentSaveTaskSource("slotA");
            Assert.Throws<InvalidDataException>(() => MapTaskCatalog.Load(root, null, new[] { source }, null));
            Put("data/rag/agent_saves/slotA/agent_tasks.json", "{\"tasks\":[]}");
            Assert.Throws<InvalidDataException>(() => MapTaskCatalog.Load(root, null, new[] { source, source }, null));
            Assert.Throws<InvalidDataException>(() => MapTaskCatalog.Load(root, null, new[] { "data/rag/agent_saves/../secret/agent_tasks.json" }, null));
        }
        [Fact]
        public void TextOverrideSourceLoadsAfterAgentTextAndFailsClosed()
        {
            var baseline = MapTaskCatalog.Load(root);
            string agentText = MapTaskCatalog.AgentSaveTextSource("slotA");
            string overrideText = MapTaskCatalog.AgentSaveTextOverrideSource("slotA");
            Assert.Equal("data/rag/agent_saves/slotA/task_text_overrides.json", overrideText);

            // 覆盖层文件缺失：与现状逐字一致（摘要不变，也不进 SourceBytes）。
            var missing = MapTaskCatalog.Load(root, null, null, new[] { agentText, overrideText });
            Assert.Equal(baseline.Digest, missing.Digest);
            Assert.DoesNotContain(overrideText, missing.SourceBytes.Keys);

            // 只有 agent_text.json：行为与现状一致。
            Put(agentText, "{\"$K\":\"终端文本\"}");
            var textOnly = MapTaskCatalog.Load(root, null, null, new[] { agentText, overrideText });
            Assert.Equal("终端文本", (string)textOnly.Texts["$K"]);

            // 只有 task_text_overrides.json：也能单独加载。
            File.Delete(PathFor(agentText));
            Put(overrideText, "{\"$K\":\"覆盖层文本\"}");
            var overrideOnly = MapTaskCatalog.Load(root, null, null, new[] { agentText, overrideText });
            Assert.Equal("覆盖层文本", (string)overrideOnly.Texts["$K"]);

            // 两个都在且同 key：排在后面的覆盖层整份赢；未被覆盖的 key 保留增量的值。
            Put(agentText, "{\"$K\":\"终端文本\",\"$ONLY\":\"仅在增量\"}");
            var both = MapTaskCatalog.Load(root, null, null, new[] { agentText, overrideText });
            Assert.Equal("覆盖层文本", (string)both.Texts["$K"]);
            Assert.Equal("仅在增量", (string)both.Texts["$ONLY"]);
            // 顺序反过来就失去覆盖语义——MapRuntimeContent 的固定顺序是唯一保证。
            var reversed = MapTaskCatalog.Load(root, null, null, new[] { overrideText, agentText });
            Assert.Equal("终端文本", (string)reversed.Texts["$K"]);

            // 变化清单覆盖新源：只改覆盖层就只列它。
            Put(overrideText, "{\"$K\":\"覆盖层文本·改\"}");
            Assert.Equal(new[] { overrideText },
                MapTaskCatalog.ChangedSources(both, MapTaskCatalog.Load(root, null, null, new[] { agentText, overrideText })));

            // 覆盖层损坏沿用既有 fail-closed：整次加载失败，不静默吞掉。
            Put(overrideText, "{\"$K\":");
            Assert.ThrowsAny<Newtonsoft.Json.JsonException>(
                () => MapTaskCatalog.Load(root, null, null, new[] { agentText, overrideText }));
        }
        public void Dispose()
        {
            string expected = Path.Combine(Path.GetTempPath(), "cf7-map-content-test-");
            if (Path.GetFullPath(root).StartsWith(Path.GetFullPath(expected), StringComparison.OrdinalIgnoreCase) && Directory.Exists(root)) Directory.Delete(root, true);
        }
    }
}
