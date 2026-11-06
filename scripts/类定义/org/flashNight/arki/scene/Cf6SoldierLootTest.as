import org.flashNight.arki.scene.*;
import org.flashNight.arki.item.*;
import org.flashNight.arki.item.itemCollection.*;
import org.flashNight.arki.pause.PauseManager;
import org.flashNight.arki.render.FrameBroadcaster;
import org.flashNight.arki.unit.Action.Shoot.WeaponAmmoRuntime;
import org.flashNight.gesh.object.PersistedSnapshot;
import org.flashNight.neur.Server.SaveManager;
import org.flashNight.naki.RandomNumberEngine.LinearCongruentialEngine;

/** Real AVM1 actors, RewardStashService and SaveManager; nonce-owned storage.
 * Controlled random input and explicit save faults do not touch player saves. */
class org.flashNight.arki.scene.Cf6SoldierLootTest {
    private static var passed:Number,failed:Number,rolls:Number,caseIndex:Number,exitCalls:Number;
    private static var slot:String,config:Object,world:MovieClip,sm:SaveManager,storage:SharedObject;
    private static var sourceRoll:Function,sourceRandom:Function,sourceUi:Function,saveStates:Array,gateHit:Boolean,choice:Number;
    private static function check(ok:Boolean,label:String):Void {
        if(ok)passed++;else{failed++;trace("[FAIL] Cf6SoldierLootTest "+label);}
    }
    private static function sawSaveSuccess():Boolean {
        for(var i:Number=0;i<saveStates.length;i++)if(saveStates[i]=="sv:2")return true;
        return false;
    }
    private static function random():Number {return choice;}
    private static function gate(prefix:String,item:Object,luck:Number,prd:Object):Boolean {
        rolls++;
        var engine:Object=LinearCongruentialEngine.instance,previous:Function=engine.nextFloat;
        engine.nextFloat=function():Number {return Cf6SoldierLootTest.gateHit?0:.999999;};
        var result:Boolean=sourceRoll(prefix,item,luck,prd);engine.nextFloat=previous;return result;
    }
    private static function cleanState():Void {
        sm._configureSaveFlowForTest({saveInFlight:false,flushResult:true,beforeRewardExposure:null,beforeLocalCommit:null});
        for(var settle:Number=0;settle<5;settle++)Cf6SoldierLoot.prepareForTransition();
        check(RewardStashService.pendingOperationId()=="" && Cf6SoldierLoot.prepareForTransition(),"previous case durably settled");
        _root._saveExt={bookRun:{bookId:"cf6-sting",routeId:"type61",slot:slot,
            seed:101,startedAt:++caseIndex,planSeed:42,outcome:"active"},retained:{__future:{kept:9}}};
        _root.物品栏={};
        var names:Array=["背包","装备栏","药剂栏","仓库","战备箱"];
        for(var i:Number=0;i<names.length;i++)_root.物品栏[names[i]]=new ArrayInventory(null,50);
        _root.收集品栏={材料:new DictCollection(null),情报:new InformationCollection(null)};
        gateHit=true;choice=0;rolls=0;saveStates=[];
        RewardInboxService.resetForTests();
        check(Cf6SoldierLoot.bind(config),"bind nonce run "+caseIndex);
        if(world!=null)world.removeMovieClip();
        world=_root.createEmptyMovieClip("__cf6LootWorld"+caseIndex,_root.getNextHighestDepth());_root.gameworld=world;
        check(Cf6SoldierActions.bindWorld(world,StageReturnFlow.worldIdentity(world),config,"A19"),"bind native world "+caseIndex);
    }
    private static function actor(identity:String):MovieClip {
        var unit:MovieClip=world.createEmptyMovieClip(identity,world.getNextHighestDepth());
        unit.cf6UnitIdentity="CF6-M-XX";unit.cf6RosterVersion=config.version;unit.cf6BirthIdentity={};unit.version=caseIndex;
        // Native ownership uses the real registry; equipment materialization is
        // covered by the separate 158-actor RSL suite.
        unit.cf6ProfileId=config.identities[unit.cf6UnitIdentity].profileId;
        unit.cf6SourceSeat=config.identities[unit.cf6UnitIdentity].sourceSeat;
        unit.cf6BirthX=unit._x=200;unit.cf6BirthZ=unit.Z轴坐标=unit._y=300;unit.方向="右";
        unit.soldierPhase=2;unit.hp=0;unit.soldierIsElite=true;
        unit.cf6LootProfile="major_rifle_xor_pair_xor_material";unit.cf6LootMaterial="透镜";
        unit.长枪=BaseItem.createFromObject({name:"G1111",lastUpdate:1,
            value:{level:13,mods:[],shot:4,reloadCount:8,isRocketMode:false,ammoState:{v:1,capacity:15,reserve:3},__future:{kept:17}}});
        unit.手枪=BaseItem.createFromObject({name:"MP7",lastUpdate:2,value:{level:13,mods:[],shot:2}});
        unit.手枪2=BaseItem.createFromObject({name:"MP7",lastUpdate:3,value:{level:13,mods:[],shot:7}});
        unit.长枪属性={capacity:15,clipname:"步枪弹药"};unit.长枪弹匣容量=15;
        unit.手枪属性={capacity:40,clipname:"手枪弹药"};unit.手枪2属性={capacity:40,clipname:"手枪弹药"};
        check(Cf6SoldierActions.register(unit)!=null,"native actor registered "+identity);
        return unit;
    }
    private static function drain():Void {
        var done:Boolean=false;
        for(var i:Number=0;i<5 && !done;i++)done=Cf6SoldierLoot.prepareForTransition();
        check(done,"all saved decisions and admissions settled: "+Cf6SoldierLoot.status().error);
    }
    private static function packet(id:String):Object {return _root._saveExt.bookRun.cf6SoldierLoot.records["u.CF6-M-XX"];}
    private static function exactCase():Void {
        cleanState();var unit:MovieClip=actor("exact");
        check(Cf6SoldierLoot.combatDeath(unit),"capture native combat death");unit.长枪.value.shot=99;
        check(!Cf6SoldierLoot.prepareForTransition(),"durable decision alone blocks transition");
        check(!sawSaveSuccess() && Cf6SoldierLoot.blocksSaveSuccess(),"partial decision save cannot emit exit-authorizing sv2");
        check(packet("exact").state=="DECIDED_HIT" && RewardStashService.peek().entries.length==0,"decision precedes asset admission");
        check(storage.data.test.ext.bookRun.cf6SoldierLoot.records["u.CF6-M-XX"].items[0].value.shot==4,"first save contains frozen actual equipment");
        drain();check(sawSaveSuccess() && !Cf6SoldierLoot.blocksSaveSuccess(),"completed admission permits save-success projection");
        var stash:Object=RewardStashService.peek();
        check(stash.entries.length==2 && stash.entries[0].item.value.isRocketMode===false,"one weapon and actual ordinary ammo admitted");
        check(stash.entries[0].item.value.__future.kept==17 && stash.entries[0].item.value.ammoState.reserve==3,"full serialized value retained");
        check(packet("exact").state=="OWNED" && rolls==1,"one gate becomes owned");
        check(Cf6SoldierLoot.combatDeath(unit),"duplicate death is acknowledged");drain();check(rolls==1,"duplicate never rolls again");
        var refs:Array=[];
        for(var i:Number=0;i<stash.entries.length;i++)refs.push({entryId:stash.entries[i].entryId,revision:stash.entries[i].revision,quantity:RewardStashStore.quantity(stash.entries[i].item)});
        var result:Object=RewardStashService.take({storeId:stash.storeId,expectedRevision:stash.commitRevision,operationId:"cf6.fixture.take",entries:refs});
        check(result.success && result.accepted.length==2,"real stash claim transfers weapon plus ammunition");
        var bag:Object=_root.物品栏.背包.toObject(),savedBag:Object=storage.data.test.inventory.背包,found:Boolean=false;
        for(var index:String in bag)if(bag[index].name=="G1111"){
            found=true;check(bag[index].value.shot==4 && bag[index].value.isRocketMode===false && bag[index].value.__future.kept==17,"BaseItem serialization preserves exact claimed weapon");
            check(savedBag[index].value.__future.kept==17 && savedBag[index].value.ammoState.reserve==3,"claimed full value reaches save image");
        }
        check(found && RewardStashStore.ownedQuantity(RewardStashService.peek(),"G1111")==0,"weapon exists exactly once after claim");
    }
    private static function failureCases():Void {
        cleanState();var unit:MovieClip=actor("known");Cf6SoldierLoot.combatDeath(unit);
        sm._configureSaveFlowForTest({beforeRewardExposure:function():Void {throw new Error("owned_pre_exposure_fault");}});
        check(!Cf6SoldierLoot.prepareForTransition() && RewardStashService.pendingOperationId()=="","known before-exposure rollback stays retryable");
        check(rolls==1 && packet("known")==null,"rollback restores committed ledger");
        sm._configureSaveFlowForTest({beforeRewardExposure:null});drain();check(rolls==1 && packet("known").state=="OWNED","known rollback preserves random decision");
        cleanState();unit=actor("unknown");Cf6SoldierLoot.combatDeath(unit);
        sm._configureSaveFlowForTest({flushResult:false});check(!Cf6SoldierLoot.prepareForTransition(),"exposed false decision blocks transition");
        var op:String=RewardStashService.pendingOperationId();var packs:Number=sm._getSavePhysicalStatsForTest().packGameState;
        check(op!="" && rolls==1 && RewardStashService.committedFeature()==null,"unknown decision retains old committed projection");
        Cf6SoldierLoot.prepareForTransition();check(RewardStashService.pendingOperationId()==op && rolls==1
            && sm._getSavePhysicalStatsForTest().packGameState==packs,"query resumes original frozen image without repack/reroll");
        sm._configureSaveFlowForTest({flushResult:true});drain();check(rolls==1 && packet("unknown").state=="OWNED","unknown decision resolves once");
        cleanState();unit=actor("pendingAdmission");Cf6SoldierLoot.combatDeath(unit);Cf6SoldierLoot.prepareForTransition();
        sm._configureSaveFlowForTest({flushResult:"pending"});check(!Cf6SoldierLoot.prepareForTransition(),"pending admission blocks transition");
        op=RewardStashService.pendingOperationId();check(op!="" && RewardStashService.committedFeature().entries.length==0,"unconfirmed admission not projected as owned inventory");
        sm._configureSaveFlowForTest({flushResult:true});drain();check(rolls==1 && RewardStashService.peek().entries.length==2,"pending admission commits one complete packet");
        cleanState();unit=actor("restart");Cf6SoldierLoot.combatDeath(unit);Cf6SoldierLoot.prepareForTransition();
        var api:Object=Cf6SoldierLoot;api.context=null;api.captured={};
        check(Cf6SoldierLoot.bind(config),"rebind durable decision after service reconstruction");drain();
        check(rolls==1 && packet("restart").state=="OWNED","durable hit resumes without gate replay");
    }
    private static function edgeCases():Void {
        cleanState();choice=.6;var unit:MovieClip=actor("pair");Cf6SoldierLoot.combatDeath(unit);drain();
        var stash:Object=RewardStashService.peek();
        check(stash.entries.length==3 && stash.entries[0].item.value.shot==2 && stash.entries[1].item.value.shot==7,"both native sidearms keep independent spent rounds");
        check(stash.entries[2].item.value==2 && packet("pair").kind=="sidearm_pair","same ammo sums both hands in one packet");
        cleanState();gateHit=false;unit=actor("miss");Cf6SoldierLoot.combatDeath(unit);drain();
        check(packet("miss").state=="DECIDED_MISS" && RewardStashService.peek().entries.length==0,"real PRD miss has no consolation equipment/ammo");
        cleanState();unit=actor("break");unit.soldierPhase=1;
        check(!Cf6SoldierLoot.combatDeath(unit),"shield break cannot award");unit.soldierPhase=2;unit.cf6EncounterRetired=true;
        check(!Cf6SoldierLoot.combatDeath(unit),"support retirement cannot award");unit.cf6EncounterRetired=false;
        unit.长枪.value.isRocketMode="false";check(Cf6SoldierLoot.combatDeath(unit),"malformed equipment freezes an ineligible decision");drain();
        check(rolls==0 && packet("break").roll.reason=="ineligible","malformed G1111 never reaches random gate");
        cleanState();for(var i:Number=0;i<50;i++)_root.物品栏.背包.add(i,BaseItem.create("G1111",1));
        unit=actor("fullBag");Cf6SoldierLoot.combatDeath(unit);drain();
        check(RewardStashStore.ownedQuantity(RewardStashService.peek(),"G1111")==1 && _root.物品栏.背包.getIndexes().length==50,"full bag admits entire packet to stash");
        cleanState();unit=actor("exit");Cf6SoldierLoot.combatDeath(unit);exitCalls=0;
        _root.gameCommands={safeExit:function():Void {
            Cf6SoldierLootTest.exitCalls++;Cf6SoldierLootTest.sm.flushBeforeTransition("safe_exit");
        }};
        check(Cf6SoldierLoot.deferSafeExit(),"exit defers during the durable decision/admission gap");
        check(!sawSaveSuccess(),"deferred exit has no early sv2 before full admission");
        Cf6SoldierLoot.tick();Cf6SoldierLoot.tick();check(exitCalls==1 && sawSaveSuccess() && packet("exit").state=="OWNED","safe exit invoked once after atomic admission");
    }
    public static function runAllTests():Boolean {
        passed=failed=rolls=caseIndex=exitCalls=0;
        var keys:Array=["savePath","允许存档","角色名","等级","基础身价值","身价","存档系统","mydata","_saveExt","暂停","UpdateTaskProgress",
            "物品栏","收集品栏","金钱","虚拟币","经验值","技能点数","gameworld","主角被动技能","商城已购买物品","UI系统","tasks_to_do","tasks_finished","task_chains_progress","等级限制","gameCommands"];
        var previous:Object={},present:Object={};for(var k:Number=0;k<keys.length;k++){previous[keys[k]]=_root[keys[k]];present[keys[k]]=_root.hasOwnProperty(keys[k]);}
        var oldData:Object=ItemUtil.itemDataDict,oldEquipment:Object=ItemUtil.equipmentDict,oldMaterial:Object=ItemUtil.materialDict,oldInfo:Object=ItemUtil.informationMaxValueDict;
        var loot:Object=Cf6SoldierLoot,actions:Object=Cf6SoldierActions,oldRoom:Object=actions.room;
        sourceRoll=DropLuckRoller.rollDropWithContext;sourceRandom=LinearCongruentialEngine.instance.nextFloat;
        var ui:Object=FrameBroadcaster;sourceUi=ui.pushUiState;saveStates=[];
        ui.pushUiState=function(value:String):Void {Cf6SoldierLootTest.saveStates.push(value);};
        var roller:Object=DropLuckRoller;roller.rollDropWithContext=gate;LinearCongruentialEngine.instance.nextFloat=random;
        slot="cf7_env_cf6_fixed_loot_"+new Date().getTime()+"_"+Math.floor(Math.random()*1000000000);
        sm=SaveManager.getInstance();storage=SharedObject.getLocal(slot);var owns:Boolean=false;
        try {
            for(var occupied:String in storage.data)throw new Error("owned_fixture_collision");owns=true;
            trace("[CF6_LOOT_FIXTURE] nonceSlot="+slot+" playerSavesOpened=false");
            _root.savePath=slot;_root.允许存档=true;_root.角色名="FixedLootFixture";_root.等级=1;_root.基础身价值=1000;_root.身价=1000;
            _root.金钱=_root.虚拟币=_root.经验值=_root.技能点数=0;_root.商城已购买物品=[];_root.主角被动技能={};_root.存档系统={dirtyMark:false};
            _root.UpdateTaskProgress=function():Void {};_root.UI系统={};_root.tasks_to_do=[];_root.tasks_finished=[];_root.task_chains_progress={};_root.等级限制=100;
            ItemUtil.itemDataDict={};ItemUtil.equipmentDict={G1111:true,MP7:true};ItemUtil.materialDict={透镜:true};ItemUtil.informationMaxValueDict={};
            var items:Array=["G1111","MP7","步枪弹药","手枪弹药","透镜"];
            for(var i:Number=0;i<items.length;i++)ItemUtil.itemDataDict[items[i]]={name:items[i],displayname:items[i],icon:"a",
                type:i<2?"武器":i==4?"收集品":"消耗品",use:i<2?"长枪":i==4?"材料":"弹夹",data:{level:1,weight:0}};
            config=Cf6FixedActionsFixture.config();config.lootPolicy=Cf6SoldierLootFixture.policy();
            // No prior player run is bound in this isolated test process.
            loot.context=null;loot.queue=[];loot.captured={};loot.plan=null;loot.operation="";
            exactCase();failureCases();edgeCases();
            check(WeaponAmmoRuntime.quoteInventoryPacks(40,0,40)==1 && WeaponAmmoRuntime.quoteInventoryPacks(40,8,40)==1
                && WeaponAmmoRuntime.quoteInventoryPacks(40,80,40)==0,"ordinary paid reload quote is shared with real spend");
        }catch(error){check(false,"unexpected exception: "+error);}
        finally {
            sm._configureSaveFlowForTest({flushResult:true,beforeRewardExposure:null,beforeLocalCommit:null});
            if(RewardStashService.pendingOperationId()!="")RewardStashService.resume(RewardStashService.pendingOperationId());
            for(var attempt:Number=0;attempt<5;attempt++)Cf6SoldierLoot.prepareForTransition();
            check(RewardStashService.pendingOperationId()=="","fixture leaves no unknown write lock");
            if(loot.watcher!=null)loot.watcher.removeMovieClip();loot.watcher=null;
            if(actions.watcher!=null)actions.watcher.removeMovieClip();actions.watcher=null;actions.room=oldRoom;
            if(world!=null)world.removeMovieClip();
            ui.pushUiState=sourceUi;
            roller.rollDropWithContext=sourceRoll;LinearCongruentialEngine.instance.nextFloat=sourceRandom;
            ItemUtil.itemDataDict=oldData;ItemUtil.equipmentDict=oldEquipment;ItemUtil.materialDict=oldMaterial;ItemUtil.informationMaxValueDict=oldInfo;
            sm._configureSaveFlowForTest({flushResult:undefined,saveInFlight:false});
            for(k=0;k<keys.length;k++)if(present[keys[k]])_root[keys[k]]=previous[keys[k]];else delete _root[keys[k]];
            loot.context=null;loot.queue=[];loot.captured={};loot.plan=null;loot.operation="";
            if(owns)storage.clear();RewardInboxService.resetForTests();
        }
        trace("Cf6SoldierLootTest: "+passed+" passed, "+failed+" failed; isolated real save boundary");
        if(failed>0)trace("[TEST_FAIL] Cf6SoldierLootTest failed");return failed==0;
    }
}
