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
        public void LegacyWorldAdapterCannotCertifyANewOrEditedOrUnreadyBoundPlacement()
        {
            var d = Definition(); var tasks = MapTaskCatalog.Load(root).Tasks;
            Assert.True(MapDomainService.Project(d, new JObject(), tasks)["taskEndpoints"]["1"]["finish"].Value<bool>("resolved"));
            Assert.True(MapDefinition.Edit(d, JArray.Parse("[{kind:'placement',id:'home_npc',values:{presenceWhen:{type:'always'}}}]"))["placements"]["home_npc"].Value<bool>("legacyWorldAdapter"));
            var edited = MapDefinition.Edit(d, JArray.Parse("[{kind:'placement',id:'home_npc',values:{presenceWhen:{type:'chain',key:'主线',min:0}}}]"));
            Assert.Null(edited["placements"]["home_npc"]["legacyWorldAdapter"]);
            Assert.False(MapDomainService.Project(edited, JObject.Parse("{chains:{'主线':0}}"), tasks)["taskEndpoints"]["1"]["finish"].Value<bool>("resolved"));
            d["placements"]["home_npc"]["worldBinding"] = JObject.Parse("{occurrenceId:'npc',sourceDigest:'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'}");
            Assert.False(MapDomainService.Project(d, new JObject(), tasks, JObject.Parse("{npc:{ready:false}}"))["taskEndpoints"]["1"]["finish"].Value<bool>("resolved"));
            Assert.Throws<InvalidDataException>(() => MapDefinition.Edit(Definition(), JArray.Parse("[{kind:'placement',id:'fake',action:'create',values:{npcId:'person',locationId:'home',legacyWorldAdapter:true}}]")));
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
        public void Dispose()
        {
            string expected = Path.Combine(Path.GetTempPath(), "cf7-map-content-test-");
            if (Path.GetFullPath(root).StartsWith(Path.GetFullPath(expected), StringComparison.OrdinalIgnoreCase) && Directory.Exists(root)) Directory.Delete(root, true);
        }
    }
}
