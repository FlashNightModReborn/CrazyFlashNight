import org.flashNight.arki.scene.*;
import org.flashNight.arki.item.*;
import org.flashNight.arki.item.itemCollection.*;
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
        if(parts.length!=4 || nonce.length!=16 || slot!=="cf7_env_cf6_loot_"+nonce
            || (kind!="longgun" && kind!="sidearm_pair" && kind!="none" && kind!="guarantee")
            || (phase!="decide" && phase!="admit" && phase!="claim" && phase!="read"))return;
        for(var h:Number=0;h<nonce.length;h++)if("0123456789abcdef".indexOf(nonce.charAt(h))<0)return;
        var outcome:String="ok";
        try {execute();}catch(error){outcome="failed:"+String(error);}
        // Halt the owned service before reporting, so this process cannot
        // silently cross from durable decision into admission after the probe.
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
        // No flush override: both decision and inventory admission must reach
        // the physical SharedObject backend in this independent process.
        sm._configureSaveFlowForTest({flushResult:undefined,saveInFlight:false});
        RewardInboxService.resetForTests();
    }
    private static function makeActor():MovieClip {
        var world:MovieClip=_root.createEmptyMovieClip("coldLootWorld",_root.getNextHighestDepth());_root.gameworld=world;
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
    private static function packet():Object {return _root._saveExt.bookRun.cf6SoldierLoot.records["u.CF6-M-XX"];}
    private static function exact():Void {
        var p:Object=packet(),ledger:Object=_root._saveExt.bookRun.cf6SoldierLoot;
        require(p.kind===(kind=="guarantee"?"longgun":kind) && Cf6SoldierLootRules.validLedger(ledger),"cold packet validity");
        require(ledger.packages===(kind=="none"?0:1) && ledger.pairs===(kind=="sidearm_pair"?1:0),"once-only quotas");
        if(kind=="longgun" || kind=="guarantee")require(p.items[0].value.shot===4 && p.items[0].value.isRocketMode===false
            && p.items[0].value.__future.kept===17 && p.items[0].value.ammoState.reserve===3,"G1111 full boolean/value snapshot");
        if(kind=="sidearm_pair")require(p.items.length===2 && p.items[0].value.shot===2 && p.items[1].value.shot===7
            && p.consumables.length===1 && p.consumables[0].value===2,"independent paired weapons and summed ammunition");
        require(kind=="none" || p.items[0].value.mods instanceof Array,"empty mods round trip");
        if(kind=="guarantee"){
            require(p.items[0].value.mods.join(",")=="战术鱼骨零件,战术握把,加长弹匣","complete three-mod weapon survives each cold phase");
            require(p.roll.reason=="first_weapon_guarantee" && p.roll.naturalHit===false && p.roll.eligibleOrdinal===8,"guard evidence cold read");
            for(var historical:Number=0;historical<7;historical++)require(ledger.records["u.old-miss-"+historical].roll.reason=="roll_miss"
                && ledger.records["u.old-miss-"+historical].roll.nominalPercent===3,"historical miss retained");
        }
    }
    private static function execute():Void {
        setup();
        if(phase=="decide"){
            for(var occupied:String in storage.data)throw new Error("nonce slot already exists");
            _root._saveExt={bookRun:{bookId:"cf6-sting",routeId:"type61",slot:slot,seed:101,startedAt:42,planSeed:42,outcome:"active"},
                retained:{__future:{kept:9}}};
            require(Cf6SoldierLoot.bind(config),"initial bind");
            var roller:Object=DropLuckRoller,original:Function=roller.rollDropWithContext;
            roller.coldOriginal=original;
            roller.rollDropWithContext=function(prefix:String,item:Object,luck:Number,prd:Object):Boolean {
                Cf6SoldierLootColdProbeTest.rolls++;
                LinearCongruentialEngine.instance.nextFloat=function():Number {return (Cf6SoldierLootColdProbeTest.kind=="none" || Cf6SoldierLootColdProbeTest.kind=="guarantee")?.999999:0;};
                var actualRoller:Object=DropLuckRoller;var passed:Boolean=actualRoller.coldOriginal(prefix,item,luck,prd);
                LinearCongruentialEngine.instance.nextFloat=function():Number {return Cf6SoldierLootColdProbeTest.kind=="sidearm_pair"?.6:0;};
                return passed;
            };
            if(kind=="guarantee"){
                var history:Object=Cf6SoldierLootRules.create(config.version,config.lootPolicy.version);
                _root._saveExt.bookRun.cf6SoldierLoot=history;
                for(var historical:Number=0;historical<7;historical++){
                    var hid:String="old-miss-"+historical;
                    var hh:Object={sourceKey:slot+"."+hid,unitIdentity:hid,spawnIdentity:hid,
                        rosterVersion:config.version,configurationFingerprint:config.version+"|old"};
                    var hr:Object={recorded:true,gateEvaluated:true,hit:false,nominalPercent:3,luckBonus:0,
                        prdPoolKey:"cf6.fixed158.ordinary|缴获包",reason:"roll_miss"};
                    require(Cf6SoldierLootRules.reserve(history,Cf6SoldierLootRules.packet(hh,{},"none",hr,[])),"old miss seed");
                }
            }
            if(kind=="guarantee")require(Cf6SoldierLootRules.validLedger(history) && Cf6SoldierLootRules.eligibleDeaths(history)===7,"seeded real historical ledger");
            var actor:MovieClip=makeActor();require(Cf6SoldierLoot.combatDeath(actor),"capture once");
            Cf6SoldierLoot.prepareForTransition();
            require(packet().state===(kind=="none"?"DECIDED_MISS":"DECIDED_HIT"),"real durable decision");
            require(RewardStashService.pendingOperationId()=="" && rolls===1,"decision exact flush ack");
            require(sm._getSavePhysicalStatsForTest().flushSuccess>0,"physical flush occurred");
            exact();return;
        }
        require(storage.data.test!=null,"saved image exists in fresh process");
        require(sm.loadFromMydata(storage.data.test,"cf6_owned_cold_probe"),"canonical fresh-process load");
        require(_root._saveExt.retained.__future.kept===9,"unrelated extension retained");
        var gate:Object=DropLuckRoller;
        gate.rollDropWithContext=function():Boolean {Cf6SoldierLootColdProbeTest.rolls++;throw new Error("cold resume rerolled");return false;};
        require(Cf6SoldierLoot.bind(config),"resume bind");exact();
        if(phase=="admit"){
            for(var attempt:Number=0;attempt<4;attempt++)Cf6SoldierLoot.prepareForTransition();
            require(Cf6SoldierLoot.prepareForTransition(),"atomic admission settles");
            require(packet().state===(kind=="none"?"DECIDED_MISS":"OWNED"),"admitted once");
            require(RewardStashService.peek().entries.length===(kind=="none"?0:(kind=="longgun" || kind=="guarantee")?2:3),"complete stash packet");
        }else if(phase=="claim" && kind!="none"){
            var store:Object=RewardStashService.peek(),refs:Array=[];
            for(var j:Number=0;j<store.entries.length;j++)refs.push({entryId:store.entries[j].entryId,revision:store.entries[j].revision,
                quantity:RewardStashStore.quantity(store.entries[j].item)});
            require(RewardStashService.take({storeId:store.storeId,expectedRevision:store.commitRevision,
                operationId:"cold.claim."+nonce,entries:refs}).success===true,"actual whole-packet claim");
        }
        if(phase=="claim" || phase=="read"){
            require(RewardStashService.peek().entries.length===0,"claimed stash empty");
            var bag:Object=_root.物品栏.背包.toObject(),guns:Number=0,ammo:Number=0,shots:Number=0;
            for(var index:String in bag){
                var item:Object=bag[index];
                if(item.name=="G1111" || item.name=="MP7"){
                    guns++;shots+=item.value.shot;
                    if(item.name=="G1111")require(item.value.isRocketMode===false && item.value.__future.kept===17
                        && item.value.ammoState.reserve===3,"claimed G1111 serialization");
                }else if(item.name=="步枪弹药" || item.name=="手枪弹药")ammo+=item.value;
            }
            require(guns===(kind=="none"?0:(kind=="longgun" || kind=="guarantee")?1:2) && ammo===(kind=="none"?0:(kind=="longgun" || kind=="guarantee")?1:2)
                && shots===(kind=="none"?0:(kind=="longgun" || kind=="guarantee")?4:9),"fresh owned inventory exact once");
        }
        exact();require(rolls===0,"no gate replay across process boundary");
    }
}
