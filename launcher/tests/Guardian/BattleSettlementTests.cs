using System;
using System.Linq;
using Newtonsoft.Json.Linq;
using Xunit;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.Hud.Loot;
using CF7Launcher.Tasks;
using CF7Launcher.Save;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class BattleSettlementTests
    {
        private static JObject Tuple(params string[] keys)
        {
            var value = new JObject(); foreach (var key in keys) value[key] = ""; return value;
        }
        private static JObject Unit(string id) => new JObject {
            ["key"]="主角-男",["displayName"]="同名斗士",["iconName"]="",["eliteLevel"]=0,["count"]=1,
            ["doll"]=Tuple("face","hair","mask","head","body","leg","hand","foot","neck","gender"),
            ["individual"]=true,["unitId"]=id,["level"]=24,
            ["loadout"]=Tuple("head","body","leg","hand","foot","neck","primary","secondary1","secondary2","melee","grenade") };
        private static JObject Report() => new JObject {
            ["v"]=2,["runId"]="run.battle.1",["stageName"]="人形战报",["difficulty"]="挑战",["outcome"]="victory",
            ["activeFrames"]=930,["totalKills"]=2,["omittedKillTypes"]=0,["totalItemGains"]=0,["totalItemLosses"]=0,
            ["omittedItemFlowTypes"]=0,["rewardRollOmissions"]=0,["kills"]=new JArray(Unit("unit.1"),Unit("unit.2")),
            ["itemFlows"]=new JArray(),["omittedIndividualKills"]=0,["totalAllyDowns"]=0,["totalAllyLosses"]=0,
            ["heroDowns"]=0,["omittedAllies"]=0,["allies"]=new JArray() };
        private static JObject Ally(string id, string status, bool hero=false)
        {
            var unit=Unit(id);unit.Remove("individual");unit.Remove("count");
            unit["status"]=status;unit["downs"]=1;unit["isHero"]=hero;return unit;
        }
        [Fact] public void V2PreservesIndependentUnitsAndFrozenLoadouts()
        {
            var report=Report();report["kills"][0]["loadout"]["primary"]="旧枪";
            Assert.True(LootPanelCoordinator.TryNormalizeSettlementReport(report,out var normalized));
            report["kills"][0]["loadout"]["primary"]="换装";
            Assert.Equal("旧枪",normalized["kills"][0]["loadout"].Value<string>("primary"));
            Assert.Equal(2,((JArray)normalized["kills"]).Count);
            Assert.NotEqual(normalized["kills"][0].Value<string>("unitId"),normalized["kills"][1].Value<string>("unitId"));
        }
        [Theory]
        [InlineData("duplicate")][InlineData("missing-slot")][InlineData("oversized-name")]
        [InlineData("unknown-field")][InlineData("missing-unit")][InlineData("wrong-total")]
        public void V2RejectsMalformedIndividualFacts(string defect)
        {
            var report=Report();
            if(defect=="duplicate")report["kills"][1]["unitId"]="unit.1";
            if(defect=="missing-slot")((JObject)report["kills"][0]["loadout"]).Remove("melee");
            if(defect=="oversized-name")report["kills"][0]["loadout"]["melee"]=new string('a',129);
            if(defect=="unknown-field")report["kills"][0]["save"]=true;
            if(defect=="missing-unit")report["kills"][0]["unitId"]="";
            if(defect=="wrong-total")report["totalKills"]=1;
            Assert.False(LootPanelCoordinator.TryNormalizeSettlementReport(report,out _));
        }
        [Fact] public void AllyStatesAndHeroDownsRemainSeparateFromAssets()
        {
            var report=Report();report["allies"]=new JArray(Ally("ally.1","dead"),Ally("ally.2","retreated"),
                Ally("ally.3","revived"),Ally("hero.1","dead",true));
            report["totalAllyDowns"]=3;report["totalAllyLosses"]=2;report["heroDowns"]=1;
            Assert.True(LootPanelCoordinator.TryNormalizeSettlementReport(report,out var normalized));
            Assert.Equal(2,normalized.Value<int>("totalAllyLosses"));Assert.Equal(0,normalized.Value<int>("totalItemLosses"));
            report["totalAllyLosses"]=3;
            Assert.False(LootPanelCoordinator.TryNormalizeSettlementReport(report,out _));
            report["totalAllyLosses"]=2;report["allies"][1]["status"]="dismissed";
            Assert.False(LootPanelCoordinator.TryNormalizeSettlementReport(report,out _));
        }
        [Fact] public void RecordCapsDoNotSilentlyAdmitCombinedHumanoids()
        {
            var report=Report();report["kills"]=new JArray(Enumerable.Range(0,128).Select(i=>Unit("unit."+i)));
            report["totalKills"]=130;report["omittedIndividualKills"]=2;
            Assert.True(LootPanelCoordinator.TryNormalizeSettlementReport(report,out _));
            ((JArray)report["kills"]).Add(Unit("unit.128"));
            Assert.False(LootPanelCoordinator.TryNormalizeSettlementReport(report,out _));
        }
        [Theory][InlineData(1)][InlineData(2)]
        public void EmptyArrayShapeRepairIsVersionedAndNarrow(int version)
        {
            var report=Report();report["v"]=version;report["kills"]=new JObject();report["itemFlows"]=new JObject();
            report["allies"]=new JObject();
            var pending=new JObject{["v"]=1,["report"]=report};
            var save=new JObject{["ext"]=new JObject{["stageSettlement"]=new JObject{["v"]=1,["pending"]=pending}}};
            SaveMigrator.NormalizeResolvedSnapshot(save);
            Assert.IsType<JArray>(report["kills"]);Assert.IsType<JArray>(report["itemFlows"]);
            if(version==2)Assert.IsType<JArray>(report["allies"]);else Assert.IsType<JObject>(report["allies"]);
        }
        [Fact] public void CasualtyHasHigherImmediatePriorityThanBoss()
        {
            var model=new LootFeedModel();
            for(int i=0;i<LootFeedModel.MaxVisibleCards;i++)model.Add("kill","首领"+i,"",1,"kill",2);
            model.Add("casualty","同名友军 倒地","",1,"ally_casualty",0,"loss",null,"unit.1.down.0");
            var loss=Assert.Single(model.Cards,c=>c.Kind=="casualty");
            Assert.Equal(4,loss.Priority);Assert.Equal(LootFeedModel.UrgencyClass.Immediate,loss.Urgency);
            Assert.Equal(1,model.PendingCount);
            var separate=new LootFeedModel();
            separate.Add("casualty","同名友军 倒地","",1,"ally_casualty",0,"loss",null,"unit.1.down.0");
            separate.Add("casualty","同名友军 倒地","",1,"ally_casualty",0,"loss",null,"unit.2.down.0");
            Assert.Equal(2,separate.ActiveCount);
        }
        [Theory][InlineData("loss","ally_casualty",true)][InlineData("gain","ally_casualty",false)]
        [InlineData("loss","pickup",false)][InlineData("neutral","ally_casualty",false)]
        public void CasualtyParserRequiresDedicatedLossFact(string direction,string source,bool expected)
        {
            var payload=new JObject{["v"]=1,["kind"]="casualty",["name"]="友军 倒地",["count"]=1,
                ["direction"]=direction,["source"]=source,["operationId"]="unit.1.down.0",["itemKey"]="unit.1.down.0"};
            Assert.Equal(expected,LootFeedTask.TryParsePayload(payload,out _,out _,out _,out _,out _));
        }
    }
}
