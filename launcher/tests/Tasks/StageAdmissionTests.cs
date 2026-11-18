using System;
using System.IO;
using System.Linq;
using CF7Launcher.Data;
using CF7Launcher.Save;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Tasks
{
    public sealed class StageAdmissionTests
    {
        private const string Bass = "压制摇滚公园", Target = "据点M", Objective = Bass + "#简单";
        private static readonly string Root = FindCheckout();
        private static readonly Lazy<MapRuntimeContent> Runtime = new(() => new MapRuntimeContent(Root));
        private static readonly Lazy<StageAdmissionCatalog> Catalog = new(() => StageAdmissionCatalog.Load(Root, Runtime.Value.Catalog));

        private static string FindCheckout()
        {
            for (var dir = new DirectoryInfo(AppContext.BaseDirectory); dir != null; dir = dir.Parent)
                if (File.Exists(Path.Combine(dir.FullName, "data/stages/list.xml"))) return dir.FullName;
            throw new DirectoryNotFoundException("Stage admission tests need the checked-out runtime data.");
        }

        private static JObject Facts(bool deliverable, int finished, JToken history, string objective = Objective) => new()
        {
            ["chains"] = new JObject(), ["clears"] = new JObject { [Bass] = history },
            ["tasks"] = new JObject { ["54"] = new JObject { ["objective"] = objective,
                ["deliverable"] = deliverable, ["finished"] = finished } }
        };

        [Theory]
        [InlineData(false, 0, null, Objective, false)]
        [InlineData(false, 0, "简单", Objective, true)]
        [InlineData(false, 0, "地狱", Objective, true)]
        [InlineData(true, 0, null, Objective, true)]
        [InlineData(false, 1, null, Objective, true)]
        [InlineData(true, 1, null, "其他#简单", false)]
        [InlineData(false, 0, "冒险", "其他#简单", true)]
        public void ActualGarageCatalogUsesVictoryAndCredibleLegacyEvidence(bool deliverable, int finished,
            string clear, string objective, bool expected)
        {
            var catalog = Catalog.Value;
            Assert.Equal(217, catalog.Execution.Count);
            var scope = catalog.Required(new[] { Target });
            Assert.Empty((JArray)scope["chains"]);
            Assert.Equal(new[] { "54" }, ((JObject)scope["tasks"]).Properties().Select(p => p.Name));
            Assert.Equal(new[] { Bass }, scope["clears"].Values<string>());
            var facts = Facts(deliverable, finished, clear == null ? JValue.CreateNull() : new JArray(clear), objective);
            Assert.Equal(expected, (bool)catalog.Decide(Target, facts, false)["unlocked"]);
            Assert.False((bool)catalog.Decide("突围", facts, true)["unlocked"]);
            Assert.True((bool)catalog.Decide(Target, facts, true)["unlocked"]);
        }

        [Theory]
        [InlineData("1", true)]
        [InlineData("1.0", true)]
        [InlineData("2.0", true)]
        [InlineData("1.3", false)]
        [InlineData("true", false)]
        [InlineData("'1'", false)]
        public void FinishedTaskPreservesExactAmfNumbersAndRejectsCoercedCounts(string raw, bool credible)
        {
            var save = JObject.Parse("{tasks:{tasks_finished:{'54':" + raw + "}}}");
            for (int pass = 0; pass < 2; pass++)
            {
                SaveMigrator.NormalizeResolvedSnapshot(save);
                Assert.True((int)save["tasks"]["tasks_finished"]["54"] > 0);
                Assert.Equal(!credible, (bool?)save["ext"]?["stageAdmissionUnknownFinished54"] == true);
            }
        }

        [Theory]
        [InlineData("{}", false)]
        [InlineData("{requirements:null}", false)]
        [InlineData("{requirements:false}", false)]
        [InlineData("{requirements:{}}", false)]
        [InlineData("{requirements:{stages:null}}", false)]
        [InlineData("{requirements:{stages:false}}", false)]
        [InlineData("{requirements:{stages:''}}", false)]
        [InlineData("{requirements:{stages:'broken'}}", false)]
        [InlineData("{requirements:{stages:{garbage:1}}}", false)]
        [InlineData("{requirements:{stages:{length:0}}}", false)]
        [InlineData("{requirements:{stages:{'9':{name:'压制摇滚公园',difficulty:'简单'}}}}", false)]
        [InlineData("{requirements:{stages:{'0':{},'00':{}}}}", false)]
        [InlineData("{requirements:{stages:[{name:'据点M',difficulty:'简单'}]}}", false)]
        [InlineData("{requirements:{stages:[{},{}]}}", false)]
        [InlineData("{requirements:{stages:[{name:'压制摇滚公园',difficulty:'简单'}]}}", true)]
        [InlineData("{requirements:{stages:[]}}", true)]
        [InlineData("{requirements:{stages:{}}}", true)]
        [InlineData("{requirements:{stages:{'0':{name:'压制摇滚公园',difficulty:'简单'}}}}", true)]
        [InlineData("{stages:[]}", true)]
        [InlineData("{stages:[{name:'压制摇滚公园',difficulty:'简单'}]}", true)]
        public void ActualMigrationPreservesUncertaintyBeforeNormalization(string json, bool credible)
        {
            var task = JObject.Parse(json); task["id"] = 54;
            var save = new JObject { ["tasks"] = new JObject { ["tasks_to_do"] = new JArray(task) } };
            for (int pass = 0; pass < 2; pass++) {
                SaveMigrator.NormalizeResolvedSnapshot(save);
                Assert.Equal(!credible, (bool?)save["tasks"]["tasks_to_do"][0]["admissionStageObjectivesUnknown"] == true);
            }
        }

        [Theory]
        [InlineData("<UnlockCondition/>")]
        [InlineData("<UnlockCondition>75</UnlockCondition>")]
        [InlineData("<AltUnlockCondition/>")]
        [InlineData("<AltUnlockCondition chain='大学' min='1'/>")]
        [InlineData("<UnlockCondition/><AltUnlockCondition/>")]
        [InlineData("<AltUnlockCondition chain='大学' min='1'/><AltUnlockCondition chain='大学' min='2'/>")]
        public void RejectsMixedFieldsFromRealXmlFiles(string extra)
        {
            var temp = Directory.CreateTempSubdirectory("cf7-admission-");
            try
            {
                string list = Path.Combine(temp.FullName, "data/stages/demo");
                Directory.CreateDirectory(list);
                File.WriteAllText(Path.Combine(temp.FullName,"data/stages/list.xml"), "<root><stages>demo</stages></root>");
                File.WriteAllText(Path.Combine(list, "__list__.xml"), "<Stages><StageInfo><Name>demo</Name><Type>无限过图</Type>"
                    + extra + "<UnlockRule version='1'><always/></UnlockRule></StageInfo></Stages>");
                Assert.Contains("mixed_unlock_fields", Assert.Throws<InvalidDataException>(
                    () => StageAdmissionCatalog.Load(temp.FullName, Runtime.Value.Catalog)).Message);
            }
            finally { temp.Delete(true); }
        }

        [Fact]
        public void DedicatedDoorsHaveTheirOwnPoliciesAndFixedDifficulty()
        {
            var catalog = Catalog.Value;
            var facts = new JObject { ["chains"] = new JObject { ["主线"] = 66, ["彩蛋"] = 4 } };
            Assert.False((bool)catalog.Decide("机器游荡区",facts,false,"egg")["unlocked"]);
            Assert.True((bool)catalog.Decide("密林深处",facts,false,"subway")["unlocked"]);
            facts["chains"]["主线"] = 67;
            Assert.True((bool)catalog.Decide("机器游荡区",facts,false,"egg")["unlocked"]);
            facts["chains"]["彩蛋"] = 0;
            Assert.False((bool)catalog.Decide("密林深处",facts,false,"subway")["unlocked"]);
            Assert.True((bool)catalog.Decide("密林深处",facts,false,"egg")["unlocked"]);
            Assert.True((bool)catalog.Decide("自由广场防守",facts,false,"subway")["nativeUnlocked"]);
            Assert.False((bool)catalog.Decide("自由广场防守",facts,false,"subway")["unlocked"]);
            Assert.False(catalog.SpecialTarget("egg","密林中央","地狱"));
            Assert.True(catalog.SpecialTarget("egg","密林中央","冒险"));
            Assert.False(catalog.SpecialTarget("subway",Target,"简单"));
        }

        [Fact]
        public void OrdinaryRuleCannotReplaceTaskBoardOrDungeonAdmission()
        {
            var dispatch = new StageTaskEntryPolicy("dispatch_board","新人救援","简单",
                JObject.Parse("{taskId:'70002',board:'first_defense'}"), Runtime.Value.Catalog);
            var facts = JObject.Parse("{tasks:{'70002':{active:false,finished:0}}}");
            Assert.Equal("task_not_active", dispatch.Rejection(facts));
            facts["tasks"]["70002"]["finished"]=1;
            Assert.Null(dispatch.Rejection(facts));
            Assert.Throws<InvalidDataException>(() => new StageTaskEntryPolicy("dispatch_board",Target,"简单",
                JObject.Parse("{taskId:'70002',board:'first_defense'}"), Runtime.Value.Catalog));
            var dungeon = new StageTaskEntryPolicy("dungeon_task","通缉任务之李小龙coser","地狱",
                JObject.Parse("{taskId:'20000',mode:'challenge'}"), Runtime.Value.Catalog);
            facts = JObject.Parse("{assets:{level:8,money:9999,kpoints:0}}");
            Assert.Equal("insufficient_money", dungeon.Rejection(facts));
            facts["assets"]["money"]=10000;
            Assert.Null(dungeon.Rejection(facts));
            facts["assets"]["level"]=null;
            Assert.Equal("insufficient_level", dungeon.Rejection(facts));
        }

        [Fact]
        public void GrantIsSingleUseScopedToSlotGenerationTaskDefinitionAndOperation()
        {
            long time = 1;
            var catalog = Catalog.Value;
            var host = new StageAdmissionTask(catalog, () => Runtime.Value, () => time);
            var bind = new JObject { ["version"]=1, ["op"]="bind", ["slot"]="fixture",
                ["taskDigest"]=Runtime.Value.ContentDigest, ["playerEpoch"]=0, ["projection"]=catalog.Execution };
            var tampered = (JObject)bind.DeepClone(); tampered["projection"][Target]["url"]="other";
            Assert.False((bool)host.Process(tampered, 1)["success"]);
            var identity = (JObject)host.Process(bind, 1)["result"];
            Assert.NotNull(identity);
            JObject Payload(string op) {
                var msg=(JObject)identity.DeepClone(); msg["version"]=1; msg["op"]=op; msg["slot"]="fixture"; msg["operation"]="reserve.1"; return msg;
            }
            var prepare=Payload("prepare"); prepare["intent"]="enter"; prepare["names"]=new JArray(Target);
            prepare["kind"]="difficulty"; prepare["difficulty"]="简单"; prepare["owner"]="panel.1"; prepare["scene"]=1;
            Assert.True((bool)host.Process(prepare,1)["success"]);
            var decide=Payload("decide"); decide["owner"]="panel.1"; decide["scene"]=1;
            decide["facts"]=Facts(true,0,JValue.CreateNull()); decide["challenge"]=false; decide["force"]=false;
            var excess=(JObject)decide.DeepClone(); excess["facts"]["chains"]["主线"]=999;
            Assert.False((bool)host.Process(excess,1)["success"]);
            Assert.Equal("granted",(string)host.Process(decide,1)["result"]["state"]);
            Assert.False((bool)host.Process(decide,1)["success"]);
            var outcome=Payload("outcome"); outcome["state"]="started"; Assert.False((bool)host.Process(outcome,1)["success"]);
            outcome["state"]="sealed"; Assert.False((bool)host.Process(outcome,1)["success"]);
            var loaded = Payload("confirm_load"); loaded["scene"]=2; loaded["owner"]="panel.1";
            Assert.False((bool)host.Process(loaded,1)["success"]);
            loaded["scene"]=1; loaded["owner"]="panel.2"; Assert.False((bool)host.Process(loaded,1)["success"]);
            loaded["owner"]="panel.1"; Assert.True((bool)host.Process(loaded,1)["success"]);
            foreach(var state in new[]{"sealed","committed","started"}) {
                outcome["state"]=state; Assert.True((bool)host.Process(outcome,1)["success"]);
            }
            var query=Payload("query"); Assert.Equal("started",(string)host.Process(query,1)["result"]["state"]);
            Assert.False((bool)host.Process(query,2)["success"]);
        }
    }
}
