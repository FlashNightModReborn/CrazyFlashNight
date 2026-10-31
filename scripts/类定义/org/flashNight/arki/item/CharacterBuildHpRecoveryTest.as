import org.flashNight.arki.item.BaseItem;
import org.flashNight.arki.item.CharacterBuildService;

/** Focused HP/correction cases sharing the production-lifecycle suite's isolated domain ports. */
class org.flashNight.arki.item.CharacterBuildHpRecoveryTest {
    private static var suite:Object;
    private static var hero:Object;
    private static var coordinator:Object;
    private static var fixture:Object;
    private static var callbacks:Object;
    private static function check(value:Boolean,label:String):Boolean {return suite.check(value,label);}
    private static function diagnostic(label:String,result:Object):Void {suite.diagnostic(label,result);}
    public static function runCase(mode:String,owner:Object):Void {
        suite=owner;
        hero=suite.hero;coordinator=suite.coordinator;fixture=suite.fixture;callbacks=suite.callbacks;
        if(mode=="floor" || mode=="spawn_floor" || mode=="spawn_bad_seed") runBloodSwordHpCase(mode);else runNumericFailureCorrectionCase(mode);
    }
    /** Real XML values + BaseItem enhancement, real owner and full numeric lifecycle.
     * Item-specific animation/set scripts are outside this stat/persistence fixture. */
    private static function runBloodSwordHpCase(mode:String):Void {
        suite.phase="blood_sword_hp_floor";
        var items:Object=org.flashNight.arki.item.ItemUtil;
        var oldData:Object=items.itemDataDict;var oldEquipment:Object=items.equipmentDict;
        try {
            var rows:Object=org.flashNight.arki.unit.PlayerStatItemFixtures.read();
            items.itemDataDict={};items.equipmentDict={};
            var keys:Array=["huofengHead","huofengChest","huofengLegs","huofengHands","huofengFeet","bloodSword"];
            var slots:Array=[];var armorHp:Number=0;var swordHp:Number=0;
            for(var i:Number=0;i<keys.length;i++) {
                var row:Object=rows[keys[i]];slots[i]=row.use;
                items.itemDataDict[row.name]=row;items.equipmentDict[row.name]=true;
                fixture.setCatalogData(_root,row.name,row);
                var item:BaseItem=new BaseItem(row.name,{level:13,mods:[]},100+i);
                _root.物品栏.背包.items[String(i)]=item;
                if(i<5) armorHp+=Number(item.getData().data.hp);else swordHp=Number(item.getData().data.hp);
            }
            _root.等级=99;hero.等级=99;
            hero.hp基本满血值=_root.根据等级计算值(200,1000,99);
            check(hero.hp基本满血值==1542 && armorHp==1368 && swordHp==-3037
                && hero.hp基本满血值+armorHp+swordHp==-127,"real +13 XML equipment reproduces the field total of -127 HP");
            if(mode!="floor") {
                // Reproduce the missed entry: fresh resource seed, actual scene gate,
                // actual full template refresh including nested passive initialization.
                for(i=0;i<slots.length;i++) _root.物品栏.装备栏.items[slots[i]]=_root.物品栏.背包.items[String(i)];
                delete hero.hp;delete hero.mp;
                var lifecycle:Object=org.flashNight.arki.scene.PlayerSceneLifecycle;
                var gate:Object=lifecycle.beginStage(_root.gameworld,0,null);
                lifecycle.prepareSpawn("主角-男",hero._name,hero);
                if(mode=="spawn_bad_seed") hero.hp=-127;
                var failure:String="";
                try {_root.刷新人物装扮(hero._name);} catch(error) {failure=String(error.message);}
                if(mode=="spawn_bad_seed") {
                    check(failure=="spawn_seed_invalid" && gate.failed===true && hero.hp==-127,
                        "an explicitly invalid incoming seed still fails instead of being healed");
                } else {
                    diagnostic("fresh_scene_hp_floor",{failure:failure});
                    check(failure=="" && hero.hp==1 && hero.hp满血值==1,
                        "fresh scene with the real negative equipment total starts at 1 HP");
                    check(hero.__playerStatFullReady===hero.__playerStatBody && lifecycle.isReady(gate),
                        "nested passive initialization and actual scene resource gate both become ready");
                    check(callbacks.state.saveCalls==0,"fresh spawn regression never writes a save");
                }
                return;
            }
            _root.刷新人物装扮(hero._name);coordinator.flush("blood_sword_baseline");
            var panel:String="workbench.production.blood-sword";
            var current:Object=CharacterBuildService.execute("snapshot",fixture.wireParams(panel,panel+".open"));
            for(i=0;i<slots.length;i++) {
                current=CharacterBuildService.execute("equipEquipment",
                    fixture.equipmentMutationParams("equipEquipment",panel,current,slots[i],i));
                if(!check(current.success===true,"real +13 equipment mutation "+slots[i])) return;
            }
            var result:Object=CharacterBuildService.finalize(current.sessionGeneration,current.loadoutRevision,false);
            diagnostic("blood_sword_hp_floor",result);
            check(result.success===true && result.closed===true && result.liveRefreshDirty===false
                && callbacks.state.saveCalls==1,"negative raw HP completes the real lifecycle and persists once");
            check(hero.hp满血值==1 && hero.hp==1 && hero.mp==200,"ordinary current HP clamps to 1 without healing or changing MP");
            panel="workbench.production.blood-sword-remove";
            current=CharacterBuildService.execute("snapshot",fixture.wireParams(panel,panel+".open"));
            if(!check(current.success===true,"new panel instance opens after the saved floor build")) return;
            current=CharacterBuildService.execute("unequipEquipment",
                fixture.equipmentMutationParams("unequipEquipment",panel,current,"刀",undefined));
            if(!check(current.success===true,"blood sword removal commits its exact inventory transaction")) return;
            result=CharacterBuildService.finalize(current.sessionGeneration,current.loadoutRevision,false);
            diagnostic("blood_sword_removed",result);
            check(result.success===true && callbacks.state.saveCalls==2 && hero.hp满血值==2910 && hero.hp==1,
                "removing the sword restores the raw 2910 maximum without granting healing");
        } finally {items.itemDataDict=oldData;items.equipmentDict=oldEquipment;}
    }
    private static function runNumericFailureCorrectionCase(mode:String):Void {
        suite.phase="numeric_correction_"+mode;
        _root.刷新人物装扮(hero._name);coordinator.flush("numeric_failure_baseline");
        var oldHp:Number=Number(hero.hp);var oldMp:Number=Number(hero.mp);
        var bad:Object=fixture.equipment("无效数值测试刀",1,"",[],200);
        var good:Object=fixture.equipment("有效数值测试刀",1,"",[],201);
        _root.物品栏.背包.items["9"]=bad;_root.物品栏.背包.items["10"]=good;
        fixture.setCatalogData(_root,bad.name,{type:"武器",use:"刀",actiontype:"普通",data:{level:1,weight:1,power:30,mp:-9999}});
        fixture.setCatalogData(_root,good.name,{type:"武器",use:"刀",actiontype:"普通",data:{level:1,weight:1,power:30}});
        var panel:String="workbench.numeric-correction."+mode;
        var current:Object=CharacterBuildService.execute("snapshot",fixture.wireParams(panel,panel+".open"));
        current=CharacterBuildService.execute("equipEquipment",
            fixture.equipmentMutationParams("equipEquipment",panel,current,"刀",9));
        var result:Object=CharacterBuildService.finalize(current.sessionGeneration,current.loadoutRevision,false);
        var api:Object=org.flashNight.arki.item.CharacterBuildService;var ticket:Object=api._statTicket;
        diagnostic("numeric_failure_"+mode,result);
        if(!check(result.success===false && callbacks.state.saveCalls==0 && ticket.status=="started"
            && hero.__playerStatInitPlan.failed===true && hero.__playerStatInitPlan.stage=="prepare_numeric",
            mode+" known numeric failure keeps dirty state and does not persist")) return;
        var params:Object=fixture.equipmentMutationParams("unequipEquipment",panel,current,"刀",undefined);
        params.expectedLoadoutRevision=current.loadoutRevision-1;
        check(CharacterBuildService.execute("unequipEquipment",params).error=="stale_state"
            && coordinator.equipmentTransition()===ticket && ticket.status=="started",
            mode+" stale correction cannot abort the original ticket");
        params.expectedLoadoutRevision=current.loadoutRevision;
        if(mode=="resources") {
            hero.hp=oldHp-1;
            check(CharacterBuildService.execute("unequipEquipment",params).error=="write_busy"
                && coordinator.equipmentTransition()===ticket && _root.物品栏.装备栏.getItem("刀")===bad
                && callbacks.state.saveCalls==0,"new damage cannot be overwritten by correction recovery");
            return;
        }
        if(mode=="identity") {
            coordinator.resetContext(_root.存档系统,"replacement_numeric_context",_root._saveExt);
            check(CharacterBuildService.execute("unequipEquipment",params).success===false
                && _root.物品栏.装备栏.getItem("刀")===bad && callbacks.state.saveCalls==0,
                "replaced context cannot use the old correction authority");
            return;
        }
        var command:String=mode=="swap" ? "equipEquipment" : "unequipEquipment";
        params=fixture.equipmentMutationParams(command,panel,current,"刀",mode=="swap" ? 10 : undefined);
        current=CharacterBuildService.execute(command,params);
        if(!check(current.success===true && current.liveRefreshDirty===true && ticket.status=="aborted"
                && callbacks.state.saveCalls==0 && hero.hp==oldHp && hero.mp==oldMp,
                mode+" corrects canonical equipment without accepting the unfinished body")) return;
        if(mode=="corrected_resources") {
            hero.hp=oldHp-1;
            result=CharacterBuildService.finalize(current.sessionGeneration,current.loadoutRevision,false);
            check(result.success===false && callbacks.state.saveCalls==0 && hero.hp==oldHp-1,
                "damage after correction blocks rebuild instead of restoring the captured HP");
            params=fixture.equipmentMutationParams("equipEquipment",panel,current,"刀",10);
            check(CharacterBuildService.execute("equipEquipment",params).error=="write_busy"
                && _root.物品栏.装备栏.getItem("刀")==null,"stale carried resources cannot authorize another equipment mutation");
            return;
        }
        result=CharacterBuildService.finalize(current.sessionGeneration,current.loadoutRevision,false);
        diagnostic("numeric_correction_"+mode,result);
        check(result.success===true && result.closed===true && callbacks.state.saveCalls==1
            && hero.__playerStatFullReady===hero.__playerStatBody && hero.hp==oldHp && hero.mp==oldMp,
            mode+" new complete lifecycle uses the original HP/MP window and persists exactly once");
        check(_root.物品栏.背包.getItem(mode=="swap" ? "10" : String(current.affectedBackpackSlot))===bad,
            mode+" preserves the exact removed item without cloning or dropping it");
    }

}
