import org.flashNight.arki.scene.*;
import org.flashNight.arki.item.*;
import org.flashNight.arki.item.itemCollection.*;
import org.flashNight.arki.unit.Action.PickUp.PickUpManager;
import org.flashNight.neur.Event.LifecycleEventDispatcher;
import org.flashNight.gesh.object.PersistedSnapshot;
import org.flashNight.neur.Server.SaveManager;
import org.flashNight.naki.RandomNumberEngine.LinearCongruentialEngine;

/** Standalone fresh-process probe. Only nonce-owned cf7_env_cf6_loot slots.
 * Real SaveManager/RewardStash/SharedObject; controlled gate, equipment inputs. */
class org.flashNight.arki.scene.Cf6SoldierLootColdProbeTest {
    private static var socket:XMLSocket,slot:String,nonce:String,phase:String,kind:String;
    private static var storage:SharedObject,sm:SaveManager,config:Object,rolls:Number;
    private static function require(ok:Boolean,label:String):Void {if(!ok)throw new Error(label);}
    public static function runAllTests():Void {
        System.security.loadPolicyFile("xmlsocket://127.0.0.1:47184");
        socket=new XMLSocket();
        socket.onConnect=function(ok:Boolean):Void {if(ok)Cf6SoldierLootColdProbeTest.socket.send("hello");else trace("[FAIL] cold probe connection");};
        socket.onData=function(message:String):Void {Cf6SoldierLootColdProbeTest.accept(message);};
        socket.connect("127.0.0.1",47184);
    }
    private static function accept(message:String):Void {
        if(message=="ready"){
            trace("Cf6SoldierLootColdProbeTest ready");
            trace("FocusedTestRunId cf6-soldier-loot-cold Complete: "+_root.cf6LootColdRunId);return;
        }
        var parts:Array=message.split("|");phase=parts[0];nonce=parts[1];slot=parts[2];kind=parts[3];
        var validPhase:Boolean=kind==="legacy"
            ? phase==="seed_v2" || phase==="read_v2" || phase==="migrate_v2" || phase==="read_v3"
            : (kind==="longgun" || kind==="sidearm_pair" || kind==="none" || kind==="guarantee" || kind==="unpicked")
                && (phase==="pick_save" || phase==="read");
        if(parts.length!=4 || nonce.length!=16 || slot!=="cf7_env_cf6_loot_"+nonce || !validPhase)return;
        for(var h:Number=0;h<nonce.length;h++)if("0123456789abcdef".indexOf(nonce.charAt(h))<0)return;
        var outcome:String="ok";
        try {execute();}catch(error){outcome="failed:"+String(error);}
        // Freeze this process at the reported phase, including the read-only v2 phase.
        var service:Object=Cf6SoldierLoot;if(service.watcher!=null)delete service.watcher.onEnterFrame;
        socket.send(phase+"|"+nonce+"|"+slot+"|"+kind+"|"+outcome+"|"+rolls);
    }
    private static function setup():Void {
        rolls=0;sm=SaveManager.getInstance();storage=SharedObject.getLocal(slot);
        _root.savePath=slot;_root.允许存档=true;_root.角色名="FixedLootColdFixture";
        _root.性别="男";_root.等级=1;_root.身高=175;_root.基础身价值=1000;_root.身价=1000;
        _root.金钱=_root.虚拟币=_root.经验值=_root.技能点数=0;_root.玩家称号="";_root.difficultyMode=0;_root.easterEgg=false;
        _root.脸型="";_root.发型="";_root.键值设定=[];_root.佣兵是否出战信息=[];
        _root.同伴数据=[];_root.同伴数=0;_root.主角技能表=[[]];_root.主角被动技能={};_root.主线任务进度=0;
        _root.商城已购买物品=[];_root.商城购物车=[];_root.存档系统={dirtyMark:false};
        _root.全局健身HP加成=_root.全局健身MP加成=_root.全局健身空攻加成=_root.全局健身防御加成=_root.全局健身内力加成=0;
        _root.基建系统={infrastructure:{}};_root.宠物信息=[[],[],[],[],[]];_root.宠物领养限制=5;
        _root.UpdateTaskProgress=function():Void {};_root.发布消息=function():Void {};_root.更新主角被动技能=function():Void {};
        _root.getItemData=function(name:String):Object {return ItemUtil.getRawItemData(name);};
        _root.soundEffectManager={playSound:function():Void {}};
        _root.根据等级得升级所需经验=function(level:Number):Number {return 0;};
        _root.UI系统={};_root.tasks_to_do=[];_root.tasks_finished={};_root.task_chains_progress={};_root.等级限制=100;
        ItemUtil.itemDataDict={};ItemUtil.equipmentDict={G1111:true,MP7:true};ItemUtil.materialDict={透镜:true};ItemUtil.informationMaxValueDict={};
        var names:Array=["G1111","MP7","步枪弹药","手枪弹药","透镜"];
        for(var i:Number=0;i<names.length;i++)ItemUtil.itemDataDict[names[i]]={name:names[i],displayname:names[i],icon:"a",
            type:i<2?"武器":i==4?"收集品":"消耗品",use:i<2?"长枪":i==4?"材料":"弹夹",data:{level:1,weight:0}};
        _root.物品栏={};names=["背包","装备栏","药剂栏","仓库","战备箱"];
        for(i=0;i<names.length;i++)_root.物品栏[names[i]]=new ArrayInventory(null,50);
        _root.收集品栏={材料:new DictCollection(null),情报:new InformationCollection(null)};
        config=Cf6FixedActionsFixture.config();config.lootPolicy=Cf6SoldierLootFixture.policy();
        // No flush override: the ordinary save and each legacy migration must reach the physical SOL.
        sm._configureSaveFlowForTest({flushResult:undefined,saveInFlight:false});
        RewardInboxService.resetForTests();
    }
    private static function makeActor():MovieClip {
        var world:MovieClip=_root.createEmptyMovieClip("coldLootWorld",_root.getNextHighestDepth());_root.gameworld=world;
        world.dispatcher=new LifecycleEventDispatcher(world);
        require(Cf6SoldierActions.bindWorld(world,StageReturnFlow.worldIdentity(world),config,"A19"),"world bind");
        var unit:MovieClip=world.createEmptyMovieClip("exactColdActor",world.getNextHighestDepth());
        unit.cf6UnitIdentity="CF6-M-XX";unit.cf6RosterVersion=config.version;unit.cf6BirthIdentity={};unit.version=1;
        unit.cf6ProfileId=config.identities[unit.cf6UnitIdentity].profileId;unit.cf6SourceSeat=config.identities[unit.cf6UnitIdentity].sourceSeat;
        unit.cf6BirthX=unit._x=200;unit.cf6BirthZ=unit.Z轴坐标=unit._y=300;unit.方向="右";
        unit.soldierPhase=2;unit.hp=0;unit.soldierIsElite=true;unit.cf6LootProfile="major_rifle_xor_pair_xor_material";unit.cf6LootMaterial="透镜";
        unit.长枪=BaseItem.createFromObject({name:"G1111",lastUpdate:1,value:{level:13,mods:kind=="guarantee"?["战术鱼骨零件","战术握把","加长弹匣"]:[],shot:4,reloadCount:8,
            isRocketMode:false,ammoState:{v:1,capacity:15,reserve:3},__future:{kept:17}}});
        unit.手枪=BaseItem.createFromObject({name:"MP7",lastUpdate:2,value:{level:13,mods:[],shot:2}});
        unit.手枪2=BaseItem.createFromObject({name:"MP7",lastUpdate:3,value:{level:13,mods:[],shot:7}});
        unit.长枪属性={capacity:15,clipname:"步枪弹药"};unit.长枪弹匣容量=15;
        unit.手枪属性={capacity:40,clipname:"手枪弹药"};unit.手枪2属性={capacity:40,clipname:"手枪弹药"};
        require(Cf6SoldierActions.register(unit)!=null,"actor bind");return unit;
    }
    private static function newRun():Void {
        for(var occupied:String in storage.data)throw new Error("nonce slot already exists");
        _root._saveExt={bookRun:{bookId:"cf6-sting",routeId:"type61",slot:slot,seed:101,startedAt:42,planSeed:42,outcome:"active"},
            retained:{__future:{kept:9}}};
    }

    private static function currentLedger():Object {return _root._saveExt.bookRun.cf6SoldierLoot;}

    private static function seedV2(id:String,state:String,unit:MovieClip):Void {
        var history:Object=currentLedger();
        var miss:Boolean=state==="DECIDED_MISS";
        var header:Object={sourceKey:slot+"."+id,unitIdentity:id,spawnIdentity:id,
            rosterVersion:config.version,configurationFingerprint:"old"};
        var roll:Object={recorded:true,gateEvaluated:true,hit:!miss,nominalPercent:3,luckBonus:0,
            prdPoolKey:"legacy",reason:miss?"roll_miss":"roll_hit"};
        var snapshot:Object=miss?{}:{primary:unit.长枪.toObject(),ground:{mapId:"A19",x:200,z:300}};
        var packet:Object=Cf6SoldierLootRules.packet(header,snapshot,miss?"none":"longgun",roll,
            miss?[]:[{name:"步枪弹药",value:1,lastUpdate:1}]);
        packet.state=state;
        require(Cf6SoldierLootRules.reserve(history,packet),"old ledger seed");
    }

    private static function ordinaryWorld():Object {
        var world:MovieClip=_root.gameworld;
        var manager:PickUpManager=new PickUpManager();
        var creator:Object=manager;
        // The real prefab is covered by Cf6SoldierLootHost. This network-mode probe
        // gives the same Pickup manager a local MovieClip carrying its real spawn parameters.
        creator.createCollectible=function(name:String,quantity:Number,x:Number,z:Number,fly:Boolean,params:Object,out:Object):Void {
            var index:Number=world.getNextHighestDepth(),mc:MovieClip=world.createEmptyMovieClip("pickup"+index,index);
            mc.index=index;mc.物品名=name;mc.数量=quantity;mc._x=x;mc._y=z;mc.pickupItemData=params.pickupItemData;
            manager.getPickupItemDict()[index]=mc;
            out.state="created";
        };
        _root.pickupItemManager=manager;
        var player:MovieClip=world.createEmptyMovieClip("coldLootHero",world.getNextHighestDepth());
        player.hp=1000;player.是否为敌人=false;_root.控制目标=player._name;
        return {manager:manager,player:player};
    }

    private static function exactRifle(item:Object):Boolean {
        return item.name==="G1111" && item.value.level===13 && item.value.shot===4
            && item.value.reloadCount===8 && item.value.isRocketMode===false && item.value.__future.kept===17
            && item.value.ammoState.reserve===3 && item.value.mods instanceof Array;
    }

    private static function checkNewState():Void {
        var ledger:Object=currentLedger(),record:Object=ledger.records["u.CF6-M-XX"];
        var expected:String=kind==="none"?"none":kind==="sidearm_pair"?"sidearm_pair":"longgun";
        require(ledger.v===3 && Cf6SoldierLootRules.validLedger(ledger) && record.kind===expected
            && record.items===undefined && ledger.eligibleDeaths===(kind==="guarantee"?8:1),"v3 decision and quota, without saved payload");
        var bag:Object=_root.物品栏.背包.toObject(),guns:Number=0,ammo:Number=0,shots:Number=0;
        for(var index:String in bag){
            var item:Object=bag[index];
            if(item.name==="G1111" || item.name==="MP7"){
                guns++;shots+=item.value.shot;
                if(item.name==="G1111")require(exactRifle(item),"picked rifle value survives serialization");
                if(kind==="guarantee")require(item.value.mods.join(",")==="战术鱼骨零件,战术握把,加长弹匣","three picked mods survive");
            }else if(item.name==="步枪弹药" || item.name==="手枪弹药")ammo+=item.value;
        }
        var expectedCount:Number=(kind==="none" || kind==="unpicked")?0:kind==="sidearm_pair"?2:1;
        require(guns===expectedCount && ammo===expectedCount && shots===(expectedCount===2?9:expectedCount===1?4:0)
            && RewardStashStore.ownedQuantity(RewardStashService.peek(),"G1111")===0
            && RewardStashStore.ownedQuantity(RewardStashService.peek(),"MP7")===0,"owned inventory only contains actual pickups");
    }

    private static function executeNew():Void {
        if(phase==="pick_save"){
            newRun();
            if(kind==="guarantee"){
                _root._saveExt.bookRun.cf6SoldierLoot=Cf6SoldierLootRules.create(config.version,config.lootPolicy.version);
                for(var i:Number=0;i<7;i++)seedV2("old-miss-"+i,"DECIDED_MISS",null);
            }
            var roller:Object=DropLuckRoller,original:Function=roller.rollDropWithContext;
            roller.coldOriginal=original;
            roller.rollDropWithContext=function(prefix:String,item:Object,luck:Number,prd:Object):Boolean {
                Cf6SoldierLootColdProbeTest.rolls++;
                LinearCongruentialEngine.instance.nextFloat=function():Number {
                    return (Cf6SoldierLootColdProbeTest.kind==="none" || Cf6SoldierLootColdProbeTest.kind==="guarantee")?.999999:0;
                };
                var actualRoller:Object=DropLuckRoller;
                var hit:Boolean=actualRoller.coldOriginal(prefix,item,luck,prd);
                LinearCongruentialEngine.instance.nextFloat=function():Number {return Cf6SoldierLootColdProbeTest.kind==="sidearm_pair"?.6:0;};
                return hit;
            };
            require(Cf6SoldierLoot.bind(config),"initial v2/v3 binding");
            var actor:MovieClip=makeActor(),fixture:Object=ordinaryWorld();
            var flushBefore:Number=sm._getSavePhysicalStatsForTest().flushAttempt;
            require(Cf6SoldierLoot.combatDeath(actor) && rolls===1,"one death gate");
            require(sm._getSavePhysicalStatsForTest().flushAttempt===flushBefore,"death made no save attempt");
            require(_root.物品栏.背包.getIndexes().length===0 && RewardStashService.peek()==null,
                "death leaves the asset containers empty");
            if(kind!=="unpicked"){
                var dict:Object=fixture.manager.getPickupItemDict(),objects:Array=[];
                for(var key:String in dict)objects.push(dict[key]);
                for(i=0;i<objects.length;i++)fixture.manager.pickup(objects[i],fixture.player,false);
            }
            checkNewState();
            require(sm.flushBeforeTransition("safe_exit") && sm._getSavePhysicalStatsForTest().flushSuccess>0,
                "normal pickup saved to physical SOL without a Soldier reward operation");
        }else{
            readStorage();
            config.lootPolicy.groundDropsEnabled=false;
            require(Cf6SoldierLoot.bind(config),"generation-off reader accepts v3");
            checkNewState();
            require(rolls===0 && _root.pickupItemManager==null,"fresh process did not regenerate unpicked assets");
        }
    }

    private static function readStorage():Void {
        require(storage.data.test!=null,"saved image exists in a new process");
        require(sm.loadFromMydata(storage.data.test,"cf6_owned_cold_probe"),"canonical cold read");
        require(_root._saveExt.retained.__future.kept===9,"unrelated extension survived");
    }

    private static function executeLegacy():Void {
        if(phase==="seed_v2"){
            newRun();
            _root._saveExt.bookRun.cf6SoldierLoot=Cf6SoldierLootRules.create(config.version,config.lootPolicy.version);
            var unit:MovieClip=makeActor();
            seedV2("old-owned","OWNED",unit);
            seedV2("old-hit","DECIDED_HIT",unit);
            require(sm.flushBeforeTransition("safe_exit"),"save that preserves an unstarted v2 hit");
            return;
        }
        readStorage();
        config.lootPolicy.groundDropsEnabled=false;
        require(Cf6SoldierLoot.bind(config),"generation-off reader binds old and new history");
        if(phase==="read_v2"){
            require(currentLedger().v===2 && currentLedger().records["u.old-hit"].state==="DECIDED_HIT"
                && RewardStashService.peek()==null,"v2 still readable without applying its promise on read");
            return;
        }
        if(phase==="migrate_v2")require(Cf6SoldierLoot.settleLegacyBeforeReplacement(),"one confirmed old admission");
        var ledger:Object=currentLedger(),stash:Object=RewardStashService.peek();
        require(ledger.v===3 && ledger.records["u.old-owned"].kind==="longgun" && ledger.records["u.old-hit"].kind==="longgun"
            && ledger.packages===2 && stash.entries.length===1 && exactRifle(stash.entries[0].item),
            "v3 and one old weapon persist together without reviving the missing owned weapon");
        require(_root.物品栏.背包.getItem("0").name==="步枪弹药"
            && _root.物品栏.背包.getItem("0").value===1 && rolls===0,"old ammo was delivered only once with no reroll");
    }

    private static function execute():Void {
        setup();
        if(kind==="legacy")executeLegacy();
        else executeNew();
    }
}
