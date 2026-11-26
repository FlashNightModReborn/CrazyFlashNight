import org.flashNight.arki.scene.*;
import org.flashNight.arki.unit.Action.PickUp.PickUpManager;
import org.flashNight.neur.Event.LifecycleEventDispatcher;
import org.flashNight.neur.Event.EventBus;
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
    private static var passed:Number,failed:Number,rolls:Number,caseIndex:Number;
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
        if(RewardStashService.pendingOperationId()!="")throw new Error("previous fixture still has an unknown write");
        _root._saveExt={bookRun:{bookId:"cf6-sting",routeId:"type61",slot:slot,
            seed:101,startedAt:++caseIndex,planSeed:42,outcome:"active"},retained:{__future:{kept:9}}};
        _root.物品栏={};
        var names:Array=["背包","装备栏","药剂栏","仓库","战备箱"];
        for(var i:Number=0;i<names.length;i++)_root.物品栏[names[i]]=new ArrayInventory(null,50);
        _root.物品栏.装备栏=new EquipmentInventory(null);
        _root.收集品栏={材料:new DictCollection(null),情报:new InformationCollection(null)};
        gateHit=true;choice=0;rolls=0;saveStates=[];
        RewardInboxService.resetForTests();
        check(Cf6SoldierLoot.bind(config),"bind nonce run "+caseIndex);
        if(world!=null)world.removeMovieClip();
        world=_root.createEmptyMovieClip("__cf6LootWorld"+caseIndex,_root.getNextHighestDepth());_root.gameworld=world;
        world.dispatcher=new LifecycleEventDispatcher(world);
        _root.pickupItemManager=new PickUpManager();
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
    private static function ledger():Object {return _root._saveExt.bookRun.cf6SoldierLoot;}

    private static function groundItems(name:String):Array {
        var dict:Object=_root.pickupItemManager.getPickupItemDict(),items:Array=[];
        for(var key:String in dict)if(dict[key].物品名===name)items.push(dict[key]);
        items.sortOn("index",Array.NUMERIC);
        return items;
    }

    private static function hero():MovieClip {
        var player:MovieClip=world.createEmptyMovieClip("__cf6GroundHero",world.getNextHighestDepth());
        player.hp=1000;player.是否为敌人=false;player._x=200;player._y=player.Z轴坐标=300;
        _root.控制目标=player._name;
        return player;
    }

    private static function bagQuantity(name:String):Number {
        var bag:Object=_root.物品栏.背包.toObject(),total:Number=0;
        for(var key:String in bag)if(bag[key].name===name)total+=typeof bag[key].value=="object"?1:Number(bag[key].value);
        return total;
    }

    private static function tickFrames(count:Number):Void {
        for(var i:Number=0;i<count;i++)Cf6SoldierLoot.tick();
    }

    private static function nativePickupCase():Void {
        cleanState();
        var player:MovieClip=hero(),unit:MovieClip=actor("rifle");
        unit.长枪.value.mods=["测试保留插件"];
        var receipts:Array=[],picked:Array=[];
        world.dispatcher.subscribe("Pickup",function(name:String):Void {picked.push(name);});
        PlayerAssetTransaction.setTestSink(function(receipt:Object):Void { receipts.push(receipt); });
        var physical:Number=sm._getSavePhysicalStatsForTest().flushAttempt;
        check(Cf6SoldierLoot.combatDeath(unit),"real actor death yields world loot");
        unit.长枪.value.shot=99;
        var gun:MovieClip=groundItems("G1111")[0],ammo:MovieClip=groundItems("步枪弹药")[0];
        check(gun!=null && gun._parent===world && gun.pickupItemData.value.shot===4
            && gun.pickupItemData.value.mods[0]==="测试保留插件" && ammo!=null,
            "real prefab receives distinct complete rifle and ammo payloads");
        check(ledger().v===3 && ledger().records["u.CF6-M-XX"].kind==="longgun"
            && ledger().records["u.CF6-M-XX"].items===undefined && ledger().eligibleDeaths===1,
            "v3 records only eligible identity and category");
        check(RewardStashService.peek()==null && bagQuantity("G1111")===0 && bagQuantity("步枪弹药")===0
            && receipts.length===0 && sm._getSavePhysicalStatsForTest().flushAttempt===physical,
            "death adds zero owned assets, gain receipts and dedicated saves");
        check(Cf6SoldierLoot.combatDeath(unit) && rolls===1 && groundItems("G1111").length===1,"duplicate death does not reroll");

        var manager:Object=_root.pickupItemManager,bag:Object=_root.物品栏.背包;
        var outsider:MovieClip=_root.createEmptyMovieClip("__otherCollector",_root.getNextHighestDepth());outsider.hp=100;
        manager.pickup(gun,outsider,false);outsider.removeMovieClip();
        check(gun.__pickupClaimed!==true && bagQuantity("G1111")===0,"another world cannot collect the payload");
        for(var i:Number=0;i<50;i++)bag.add(i,BaseItem.create("MP7",1));
        manager.pickup(gun,player,false);
        check(gun.__pickupClaimed!==true && groundItems("G1111").length===1 && RewardStashService.peek()==null,
            "full bag keeps the ordinary ground drop without redirect");
        bag.remove(13);bag.remove(14);
        manager.pickup(gun,player,false);manager.pickup(gun,player,false);
        manager.pickup(ammo,player,false);
        var value:Object=bag.getItem(13).value;
        check(bagQuantity("G1111")===1 && bagQuantity("步枪弹药")===1 && value.shot===4
            && value.mods[0]==="测试保留插件" && value.ammoState.reserve===3 && value.__future.kept===17
            && value.isRocketMode===false && groundItems("G1111").length===0,
            "real pickup records exact complete equipment and ordinary ammunition once");
        check(receipts.length===2 && receipts[0].effects[0].name==="G1111"
            && receipts[0].effects[0].count===1 && receipts[1].effects[0].name==="步枪弹药"
            && picked.join("|")==="G1111|步枪弹药",
            "only actual pickups publish one gain and one correctly named Pickup event per asset");
        check(sm._getSavePhysicalStatsForTest().flushAttempt===physical && sm.flushBeforeTransition("safe_exit"),
            "normal save and exit need no Soldier-specific reward commit");
        check(storage.data.test.ext.bookRun.cf6SoldierLoot.v===3 && sawSaveSuccess(),
            "ordinary save emits success and contains v3 summary");
        PlayerAssetTransaction.setTestSink(null);
    }

    private static function remainingWorldCases():Void {
        cleanState();var player:MovieClip=hero(),unit:MovieClip=actor("pair");
        choice=.6;unit.手枪.value.mods=["测试左手保留"];unit.手枪2.value.mods=["测试右手保留"];
        Cf6SoldierLoot.combatDeath(unit);
        var pair:Array=groundItems("MP7"),ammo:MovieClip=groundItems("手枪弹药")[0];
        check(pair.length===2 && pair[0]!==pair[1] && pair[1]._x>pair[0]._x && ammo.pickupItemData.value===2,
            "same-name twins are independent and the ammo amount sums both reloads");
        var manager:Object=_root.pickupItemManager;
        manager.pickup(pair[0],player,false);manager.pickup(pair[1],player,false);
        check(bagQuantity("MP7")===2 && bagQuantity("手枪弹药")===0
            && _root.物品栏.背包.getItem("0").value.shot===2 && _root.物品栏.背包.getItem("1").value.shot===7,
            "picking the two guns preserves distinct values and leaves ammo unowned");

        cleanState();player=hero();unit=actor("material");choice=.99;
        Cf6SoldierLoot.combatDeath(unit);
        var materialLoot:MovieClip=groundItems("透镜")[0];
        check(materialLoot!=null && _root.收集品栏.材料.getValue("透镜")===0 && RewardStashService.peek()==null,
            "material is an ordinary unowned drop");
        _root.pickupItemManager.pickup(materialLoot,player,false);
        check(_root.收集品栏.材料.getValue("透镜")===1 && groundItems("透镜").length===0,"material is credited only on pickup");

        cleanState();unit=actor("abandon");Cf6SoldierLoot.combatDeath(unit);
        var before:Number=rolls;
        world.removeMovieClip();world=_root.createEmptyMovieClip("__newGround",_root.getNextHighestDepth());
        _root.gameworld=world;world.dispatcher=new LifecycleEventDispatcher(world);_root.pickupItemManager=new PickUpManager();
        check(Cf6SoldierActions.bindWorld(world,StageReturnFlow.worldIdentity(world),config,"A19"),"rebind same map with a new world");
        tickFrames(60);
        check(bagQuantity("G1111")===0 && bagQuantity("步枪弹药")===0 && RewardStashService.peek()==null
            && groundItems("G1111").length===0 && rolls===before && ledger().packages===1,
            "unpicked loot vanishes on departure without refund, repopulation or assets");
    }

    private static function listenerFaultCase():Void {
        cleanState();var player:MovieClip=hero();Cf6SoldierLoot.combatDeath(actor("fault"));
        var gun:MovieClip=groundItems("G1111")[0],manager:Object=_root.pickupItemManager;
        var bag:Object=_root.物品栏.背包;
        var dispatcher:LifecycleEventDispatcher=new LifecycleEventDispatcher(world);
        bag.setDispatcher(dispatcher);
        var calls:Number=0,gains:Number=0;
        dispatcher.subscribe("ItemAdded",function(container:Object,key:String):Void {
            calls++;
            manager.pickup(gun,player,false);
            container.remove(key);
            throw "consumed_rifle_listener";
        });
        PlayerAssetTransaction.setTestSink(function(receipt:Object):Void {
            if(receipt.effects[0].name==="G1111")gains+=receipt.effects[0].count;
        });
        var failure:Object=null;
        try {manager.pickup(gun,player,false);}catch(error){failure=error;}
        finally {PlayerAssetTransaction.setTestSink(null);bag.setDispatcher(null);dispatcher.destroy();}
        manager.pickup(gun,player,false);
        check(failure==="consumed_rifle_listener" && calls===1 && gains===1 && gun.__pickupClaimed===true
            && bagQuantity("G1111")===0 && groundItems("G1111").length===0,
            "write then consume and throw finalizes exactly one pickup despite reentrant input");
        check(PlayerAssetTransaction.current()==null && Number(EventBus.getInstance()["_dispatchDepth"])===0,
            "write fault leaves transaction and EventBus ready");
    }

    private static function quickEquipmentCases():Void {
        cleanState();hero();Cf6SoldierLoot.combatDeath(actor("quick"));
        var payload:Object=groundItems("G1111")[0].pickupItemData;
        var coordinator:Object=org.flashNight.arki.unit.PlayerStatRefreshCoordinator.production();
        var oldFlush:Function=coordinator.flush,oldTransition:Function=coordinator.equipmentTransition;
        coordinator.flush=function():Object {return {status:"unchanged"};};
        coordinator.equipmentTransition=function():Object {return null;};
        try {
            var placement:Object={},manager:Object=_root.pickupItemManager,equipment:Object=_root.物品栏.装备栏;
            check(manager.拾取并装备("G1111",13,payload,placement) && placement.wrote===true
                && equipment.getItem("长枪").value.__future.kept===17,
                "quick equip into a vacant slot writes the complete payload");
            payload.value.shot=11;placement={};
            var bag:Object=_root.物品栏.背包, prior:Object=equipment.getItem("长枪");
            var listener:LifecycleEventDispatcher=new LifecycleEventDispatcher(world);
            var bothVisible:Boolean=false;
            bag.setDispatcher(listener);
            listener.subscribe("ItemAdded",function():Void {
                bothVisible=equipment.getItem("长枪")!==prior && bag.getItem("0")===prior;
                throw "quick_displacement_observer";
            });
            check(manager.拾取并装备("G1111",13,payload,placement) && placement.wrote===true && bothVisible
                && equipment.getItem("长枪").value.shot===11 && bag.getItem("0").value.shot===4,
                "quick replacement completes both slots before a throwing inventory listener");
            bag.setDispatcher(null);listener.destroy();
        }finally{coordinator.flush=oldFlush;coordinator.equipmentTransition=oldTransition;}
    }

    private static function legacyRecord(id:String,state:String,unit:MovieClip):Object {
        var header:Object={sourceKey:"legacy."+id,unitIdentity:id,spawnIdentity:id,
            rosterVersion:config.version,configurationFingerprint:config.version+"|legacy"};
        var miss:Boolean=state==="DECIDED_MISS";
        var roll:Object={recorded:true,gateEvaluated:true,hit:!miss,nominalPercent:5,luckBonus:0,
            prdPoolKey:"legacy|缴获包",reason:miss?"roll_miss":"roll_hit"};
        var snapshot:Object=miss?{}:{primary:unit.长枪.toObject(),ground:{mapId:"A19",x:200,z:300}};
        var packet:Object=Cf6SoldierLootRules.packet(header,snapshot,miss?"none":"longgun",roll,
            miss?[]:[{name:"步枪弹药",value:1,lastUpdate:1}]);
        packet.state=state;
        return packet;
    }

    private static function seedLegacy(state:String,unit:MovieClip):Object {
        var old:Object=Cf6SoldierLootRules.create(config.version,config.lootPolicy.version);
        check(Cf6SoldierLootRules.reserve(old,legacyRecord("fixed-old",state,unit)),"seed legal old state "+state);
        _root._saveExt.bookRun.cf6SoldierLoot=old;
        return old;
    }

    private static function rejectStaleSol(image:Object, version:Number):Void {
        var retained:Object=storage.data[SaveManager.SAVE_KEY], prior:Object=_root.mydata;
        var flushes:Number=sm._getSavePhysicalStatsForTest().flushAttempt;
        storage.data[SaveManager.SAVE_KEY]=image;
        try {
            check(!sm.loadAll() && ledger().v===version && _root.mydata===prior,
                "direct SOL reader protects the current book ledger v"+version);
            sm.preload();
            check(_root.mydata===prior && sm._getSavePhysicalStatsForTest().flushAttempt===flushes,
                "preload does not project or physically migrate the stale SOL");
            check(!sm.unpackGameState(image) && ledger().v===version,
                "direct public unpack cannot bypass the book ledger reader");
        }finally{
            if(retained===undefined)delete storage.data[SaveManager.SAVE_KEY];
            else storage.data[SaveManager.SAVE_KEY]=retained;
        }
    }

    private static function historicalCases():Void {
        cleanState();var unit:MovieClip=actor("legacy");
        var old:Object=seedLegacy("DECIDED_HIT",unit);
        var missing:Object=PersistedSnapshot.cloneData(sm.packGameState());
        missing.ext.bookRun.cf6SoldierLoot=Cf6SoldierLootRules.create(config.version,config.lootPolicy.version);
        rejectStaleSol(missing,2);
        sm._configureSaveFlowForTest({beforeRewardExposure:function():Void {throw new Error("legacy_exposure_fixture");}});
        var refusal:Object=sm.prepareNewCharacter(null,"fixture");
        check(!refusal.success && refusal.error==="reward_commit_pending" && ledger().v===2
            && ledger().records["u.fixed-old"].state==="DECIDED_HIT" && RewardStashService.pendingOperationId()=="",
            "replacement refuses to overwrite an old hit before its migration becomes durable");
        var stale:Object=PersistedSnapshot.cloneData(sm.packGameState());
        sm._configureSaveFlowForTest({beforeRewardExposure:null,flushResult:"pending"});
        tickFrames(90);
        var op:String=RewardStashService.pendingOperationId();
        check(op!="" && !Cf6SoldierLoot.settleLegacyBeforeReplacement() && ledger().v===3,
            "unknown migration keeps the same candidate and prevents destructive replacement");
        sm._configureSaveFlowForTest({flushResult:true});
        check(RewardStashService.resume(op).success && Cf6SoldierLoot.settleLegacyBeforeReplacement()
            && ledger().records["u.fixed-old"].kind==="longgun" && rolls===0,
            "legacy entitlement resolves exactly once before the compact state is usable");
        check(RewardStashStore.ownedQuantity(RewardStashService.peek(),"G1111")===1 && bagQuantity("步枪弹药")===1
            && groundItems("G1111").length===0 && storage.data.test.ext.bookRun.cf6SoldierLoot.v===3,
            "old weapon and ammo use their original asset destinations in the migration save");
        check(!sm.loadFromMydata(stale,"legacy_stale_fixture") && ledger().v===3
            && RewardStashStore.ownedQuantity(RewardStashService.peek(),"G1111")===1,
            "a captured v2 snapshot cannot revive a confirmed migration");
        rejectStaleSol(stale,3);

        cleanState();unit=actor("oldOwned");seedLegacy("OWNED",unit);gateHit=false;
        Cf6SoldierLoot.combatDeath(unit);
        check(ledger().v===3 && RewardStashService.peek()==null && bagQuantity("G1111")===0
            && ledger().records["u.fixed-old"].kind==="longgun","missing owned entry never grants a second historical item");

        cleanState();unit=actor("isolatedOld");seedLegacy("COMMIT_PENDING",unit);
        check(!Cf6SoldierLoot.settleLegacyBeforeReplacement() && ledger().v===2 && RewardStashService.peek()==null
            && RewardStashService.pendingOperationId()=="","serialized pending state retains evidence and starts no award");

        cleanState();unit=actor("guaranteed");gateHit=false;
        old=Cf6SoldierLootRules.create(config.version,config.lootPolicy.version);
        for(var i:Number=0;i<7;i++)Cf6SoldierLootRules.reserve(old,legacyRecord("miss."+i,"DECIDED_MISS",null));
        _root._saveExt.bookRun.cf6SoldierLoot=old;
        Cf6SoldierLoot.combatDeath(unit);
        check(rolls===1 && ledger().eligibleDeaths===8 && ledger().weaponInstances===1 && groundItems("G1111").length===1,
            "eighth actual eligible gate keeps the one-rifle guarantee after legacy misses");
    }

    public static function runAllTests():Boolean {
        passed=failed=rolls=caseIndex=0;
        var keys:Array=["savePath","允许存档","角色名","等级","基础身价值","身价","存档系统","mydata","_saveExt","暂停","UpdateTaskProgress",
            "物品栏","收集品栏","金钱","虚拟币","经验值","技能点数","gameworld","主角被动技能","商城已购买物品","UI系统","tasks_to_do","tasks_finished","task_chains_progress","等级限制","pickupItemManager","控制目标","getItemData","发布消息","soundEffectManager","刷新人物装扮"];
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
            _root.getItemData=function(name:String):Object {return ItemUtil.getRawItemData(name);};
            _root.发布消息=function(text:String):Void {};
            _root.soundEffectManager={playSound:function():Void {}};
            _root.刷新人物装扮=function():Object {return {status:"unchanged"};};
            _root.UpdateTaskProgress=function():Void {};_root.UI系统={};_root.tasks_to_do=[];_root.tasks_finished=[];_root.task_chains_progress={};_root.等级限制=100;
            ItemUtil.itemDataDict={};ItemUtil.equipmentDict={G1111:true,MP7:true};ItemUtil.materialDict={透镜:true};ItemUtil.informationMaxValueDict={};
            var items:Array=["G1111","MP7","步枪弹药","手枪弹药","透镜"];
            for(var i:Number=0;i<items.length;i++)ItemUtil.itemDataDict[items[i]]={name:items[i],displayname:items[i],icon:"a",
                type:i<2?"武器":i==4?"收集品":"消耗品",use:i<2?"长枪":i==4?"材料":"弹夹",data:{level:1,weight:0}};
            config=Cf6FixedActionsFixture.config();config.lootPolicy=Cf6SoldierLootFixture.policy();
            // No prior player run is bound in this isolated test process.
            loot.context=null;loot.queue=[];loot.captured={};loot.legacyOperation="";
            nativePickupCase();remainingWorldCases();listenerFaultCase();quickEquipmentCases();historicalCases();
            check(WeaponAmmoRuntime.quoteInventoryPacks(40,0,40)==1 && WeaponAmmoRuntime.quoteInventoryPacks(40,8,40)==1
                && WeaponAmmoRuntime.quoteInventoryPacks(40,80,40)==0,"ordinary paid reload quote is shared with real spend");
        }catch(error){check(false,"unexpected exception: "+error);}
        finally {
            sm._configureSaveFlowForTest({flushResult:true,beforeRewardExposure:null,beforeLocalCommit:null});
            if(RewardStashService.pendingOperationId()!="")RewardStashService.resume(RewardStashService.pendingOperationId());
            PlayerAssetTransaction.setTestSink(null);
            check(RewardStashService.pendingOperationId()=="","fixture leaves no unknown write lock");
            if(loot.watcher!=null)loot.watcher.removeMovieClip();loot.watcher=null;
            if(actions.watcher!=null)actions.watcher.removeMovieClip();actions.watcher=null;actions.room=oldRoom;
            if(world!=null)world.removeMovieClip();
            ui.pushUiState=sourceUi;
            roller.rollDropWithContext=sourceRoll;LinearCongruentialEngine.instance.nextFloat=sourceRandom;
            ItemUtil.itemDataDict=oldData;ItemUtil.equipmentDict=oldEquipment;ItemUtil.materialDict=oldMaterial;ItemUtil.informationMaxValueDict=oldInfo;
            sm._configureSaveFlowForTest({flushResult:undefined,saveInFlight:false});
            for(k=0;k<keys.length;k++)if(present[keys[k]])_root[keys[k]]=previous[keys[k]];else delete _root[keys[k]];
            loot.context=null;loot.queue=[];loot.captured={};loot.legacyOperation="";
            if(owns)storage.clear();RewardInboxService.resetForTests();
        }
        trace("Cf6SoldierLootTest: "+passed+" passed, "+failed+" failed; isolated real save boundary");
        if(failed>0)trace("[TEST_FAIL] Cf6SoldierLootTest failed");return failed==0;
    }
}
