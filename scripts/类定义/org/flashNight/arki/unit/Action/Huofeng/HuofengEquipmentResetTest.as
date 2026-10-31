import org.flashNight.arki.item.BaseItem;
import org.flashNight.arki.item.CharacterBuildService;
import org.flashNight.arki.unit.Action.Huofeng.HuofengRunState;
import org.flashNight.arki.unit.Action.Huofeng.HuofengRules;

/** Real inventory commands -> full Dressup initialization -> Nirvana state.
 * Numeric rows come from the existing XML fixture; set membership is added here.
 * Item animation lifecycles are outside this blank-MovieClip stat fixture. */
class org.flashNight.arki.unit.Action.Huofeng.HuofengEquipmentResetTest {
    public static function runCase(suite:Object):Void {
        suite.phase="huofeng_equipment_reset";
        var hero:Object=suite.hero;var fixture:Object=suite.fixture;
        var items:Object=org.flashNight.arki.item.ItemUtil;
        var oldData:Object=items.itemDataDict;var oldEquipment:Object=items.equipmentDict;
        try {
            items.itemDataDict={};items.equipmentDict={};
            var rows:Object=org.flashNight.arki.unit.PlayerStatItemFixtures.read();
            var keys:Array=["huofengHead","huofengChest","huofengLegs","huofengHands","huofengFeet"];
            for(var i:Number=0;i<keys.length;i++) {
                var row:Object=rows[keys[i]];row.setId="huofeng";
                items.itemDataDict[row.name]=row;items.equipmentDict[row.name]=true;
                fixture.setCatalogData(_root,row.name,row);
                _root.物品栏.装备栏.items[row.use]=new BaseItem(row.name,{level:1,mods:[]},200+i);
            }
            _root.等级=99;hero.等级=99;
            _root.刷新人物装扮(hero._name);suite.coordinator.flush("huofeng_equipment_baseline");
            if(!suite.check(HuofengRules.hasFivePieces(hero) && hero.__playerStatFullReady===hero.__playerStatBody,
                "Huofeng armor resolves through actual canonical inventory loading")) return;
            var state:Object=HuofengRunState.forUnit(hero);
            state.tier=2;state.lastPaidSequence=7;state.pendingReviveSequence=7;state.pendingNirvanaTier=2;
            state.spinReadyFrame=5000;var epoch:Number=state.equipmentEpoch;
            var panel:String="workbench.huofeng.weapon";
            var current:Object=CharacterBuildService.execute("snapshot",fixture.wireParams(panel,panel+".open"));
            if(!suite.check(current.success===true,"Huofeng ready actor opens real CharacterBuild session")) return;
            current=CharacterBuildService.execute("equipEquipment",fixture.equipmentMutationParams("equipEquipment",panel,current,"长枪",0));
            if(!suite.check(current.success===true,"Huofeng actor commits a normal longgun replacement")) return;
            var result:Object=CharacterBuildService.finalize(current.sessionGeneration,current.loadoutRevision,false);
            if(!suite.check(result.success===true,"weapon replacement completes the entire player lifecycle")) return;
            suite.check(HuofengRunState.forUnit(hero)===state && state.tier==2 && state.equipmentEpoch==epoch,
                "full weapon rebuild preserves Nirvana tier and armor eligibility");
            suite.check(state.pendingNirvanaTier==2 && state.lastPaidSequence==7 && state.spinReadyFrame==5000,
                "weapon rebuild preserves pending presentation, paid receipt and cooldown");
            var chest:Object=_root.物品栏.装备栏.getItem("上装装备");
            panel="workbench.huofeng.roundtrip";
            current=CharacterBuildService.execute("snapshot",fixture.wireParams(panel,panel+".open"));
            current=CharacterBuildService.execute("unequipEquipment",fixture.equipmentMutationParams("unequipEquipment",panel,current,"上装装备",undefined));
            if(!suite.check(current.success===true && state.tier==0 && state.equipmentEpoch==epoch+1,
                "committed unequip resets immediately before deferred actor rebuild")) return;
            var roundtripIndex:Number=-1;
            for(i=0;i<_root.物品栏.背包.capacity;i++) if(_root.物品栏.背包.items[String(i)]===chest) roundtripIndex=i;
            current=CharacterBuildService.execute("equipEquipment",fixture.equipmentMutationParams("equipEquipment",panel,current,"上装装备",roundtripIndex));
            if(!suite.check(current.success===true,"same panel can re-equip the identical armor before refresh")) return;
            result=CharacterBuildService.finalize(current.sessionGeneration,current.loadoutRevision,false);
            suite.check(result.success===true && HuofengRules.hasFivePieces(hero) && state.tier==0,
                "A-empty-A in a single panel cannot preserve a paid Nirvana tier");
            state.tier=2;state.pendingNirvanaTier=2;state.pendingReviveSequence=7;epoch=state.equipmentEpoch;
            panel="workbench.huofeng.unequip";
            current=CharacterBuildService.execute("snapshot",fixture.wireParams(panel,panel+".open"));
            var backpack:Object=_root.物品栏.背包;var write:Function=backpack.transactionWrite;var failOnce:Boolean=true;
            backpack.transactionWrite=function(slot,item):Boolean {
                if(failOnce && item===chest) {failOnce=false;return false;}
                return write.apply(this,[slot,item]);
            };
            var rejected:Object=CharacterBuildService.execute("unequipEquipment",fixture.equipmentMutationParams("unequipEquipment",panel,current,"上装装备",undefined));
            backpack.transactionWrite=write;
            suite.check(rejected.success===false && rejected.error==="write_failed" && _root.物品栏.装备栏.getItem("上装装备")===chest,
                "failed destination write rolls the actual armor transaction back");
            suite.check(state.tier==2 && state.equipmentEpoch==epoch,"rolled-back removal cannot clear paid Nirvana");
            current=CharacterBuildService.execute("snapshot",fixture.wireParams(panel,panel+".after-rollback"));
            current=CharacterBuildService.execute("unequipEquipment",fixture.equipmentMutationParams("unequipEquipment",panel,current,"上装装备",undefined));
            if(!suite.check(current.success===true,"one armor removal commits through the real inventory owner")) return;
            result=CharacterBuildService.finalize(current.sessionGeneration,current.loadoutRevision,false);
            suite.diagnostic("huofeng_equipment_reset",result);
            if(!suite.check(result.success===true && hero.__playerStatFullReady===hero.__playerStatBody,
                "armor removal completes canonical and numeric readiness")) return;
            suite.check(!HuofengRules.hasFivePieces(hero) && state.tier==0 && state.equipmentEpoch==epoch+1,
                "actual armor removal clears Nirvana at complete equipment loading");
            suite.check(state.pendingNirvanaTier==0 && state.pendingReviveSequence==0 && state.lastPaidSequence==7 && state.spinReadyFrame==5000,
                "actual removal clears queued animation without resetting receipts or cooldown");
            var index:Number=-1;
            for(i=0;i<_root.物品栏.背包.capacity;i++) if(_root.物品栏.背包.items[String(i)]===chest) index=i;
            if(!suite.check(index>=0,"removed exact chest item is in the backpack")) return;
            panel="workbench.huofeng.reequip";
            current=CharacterBuildService.execute("snapshot",fixture.wireParams(panel,panel+".open"));
            current=CharacterBuildService.execute("equipEquipment",fixture.equipmentMutationParams("equipEquipment",panel,current,"上装装备",index));
            if(!suite.check(current.success===true,"exact chest can be re-equipped normally")) return;
            result=CharacterBuildService.finalize(current.sessionGeneration,current.loadoutRevision,false);
            suite.check(result.success===true && HuofengRules.hasFivePieces(hero) && HuofengRunState.forUnit(hero)===state && state.tier==0,
                "full re-equip keeps Nirvana empty until a new paid revival");
            suite.check(suite.callbacks.state.saveCalls==4,"four completed builds each persist once in the memory port");
        } finally {items.itemDataDict=oldData;items.equipmentDict=oldEquipment;}
    }
}
