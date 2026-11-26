import org.flashNight.arki.scene.Cf6SoldierLootRules;
import org.flashNight.arki.scene.Cf6SoldierActions;
import org.flashNight.arki.scene.Cf6Type61Service;
import org.flashNight.arki.scene.BookDefinition;
import org.flashNight.arki.scene.StageReturnFlow;
import org.flashNight.arki.item.RewardStashService;
import org.flashNight.arki.item.DropLuckRoller;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.PlayerAssetTransaction;
import org.flashNight.arki.unit.Action.Shoot.WeaponAmmoRuntime;
import org.flashNight.gesh.object.PersistedSnapshot;
import org.flashNight.naki.PseudoRandom.PseudoRandomDistribution;
import org.flashNight.naki.RandomNumberEngine.LinearCongruentialEngine;

/** Fixed-soldier deaths reserve world loot; the ordinary pickup is the asset write. */
class org.flashNight.arki.scene.Cf6SoldierLoot {
    private static var context:Object;
    private static var queue:Array=[];
    private static var captured:Object={};
    private static var processing:Boolean=false;
    private static var watcher:MovieClip;
    private static var clock:Number=0;
    private static var legacyOperation:String="";
    private static var legacyRetryAt:Number=0;
    public static var lastError:String="";

    private static function currentRun():Object {
        var run:Object=_root._saveExt.bookRun;
        return run!=null && run.bookId==="cf6-sting" && run.routeId==="type61"
            && run.slot===String(_root.savePath) ? run : null;
    }

    private static function sameRun(run:Object):Boolean {
        var id:Object=context.identity;
        return context!=null && run!=null && run.slot===id.slot && run.seed===id.seed
            && run.startedAt===id.startedAt && run.planSeed===id.planSeed;
    }

    public static function bind(config:Object):Boolean {
        var run:Object=currentRun();
        if(run==null || config.lootPolicy==null || typeof config.version!="string" || !validPolicy(config.lootPolicy))return false;
        if(sameRun(run))return true;
        if(!Cf6SoldierLootRules.normalizeLedger(run.cf6SoldierLoot).ok){lastError="invalid_saved_loot_ledger";return false;}
        context={identity:{slot:run.slot,seed:run.seed,startedAt:run.startedAt,planSeed:run.planSeed},
            config:config,policy:config.lootPolicy,gateCalls:0};
        queue=[];captured={};legacyRetryAt=clock;lastError="";
        installWatcher();
        return true;
    }

    private static function installWatcher():Void {
        if(watcher==null || watcher._name==undefined)watcher=_root.createEmptyMovieClip("__cf6SoldierLoot",_root.getNextHighestDepth());
        watcher.onEnterFrame=function():Void {org.flashNight.arki.scene.Cf6SoldierLoot.tick();};
    }
    public static function validPolicy(policy:Object):Boolean {
        if(policy.schema!=="cf6-fixed-loot-policy.v1" || typeof policy.version!="string" || policy.version==""
            || (policy.groundDropsEnabled!==undefined && typeof policy.groundDropsEnabled!="boolean")
            || policy.caps.packages!==6 || policy.caps.pairs!==2 || policy.caps.weaponInstances!==8 || policy.caps.materials!==2)return false;
        var names:Array=["ordinary_rifle_or_material","elite_rifle_xor_pair_xor_material","major_rifle_xor_pair_xor_material"];
        for(var i:Number=0;i<names.length;i++){
            var p:Object=policy.profiles[names[i]];
            if(!isFinite(p.nominalPercent) || !(p.nominalPercent>0) || !(p.nominalPercent<100)
                || !Cf6SoldierLootRules.whole(p.longgun,0,100) || !Cf6SoldierLootRules.whole(p.sidearm_pair,0,100)
                || !Cf6SoldierLootRules.whole(p.mod_material,0,100) || p.longgun+p.sidearm_pair+p.mod_material!==100)return false;
        }
        var guard:Object=policy.firstWeaponGuarantee;
        if(guard!=null && (guard.kind!=="longgun" || !Cf6SoldierLootRules.whole(guard.afterEligibleDeaths,1,158)))return false;
        return policy.profiles.ordinary_rifle_or_material.sidearm_pair===0;
    }

    private static function ensure(run:Object):Boolean {
        if(run==null)return false;
        if(sameRun(run))return true;
        if(!Cf6Type61Service.isActive())return false;
        return bind(BookDefinition.get("cf6-sting","type61").type61.soldiers);
    }

    private static function itemSnapshot(item:Object):Object {
        if(item==null)return null;
        var result:Object={name:item.name,value:PersistedSnapshot.cloneData(item.value),lastUpdate:item.lastUpdate};
        return Cf6SoldierLootRules.validWeapon(result)?result:null;
    }

    private static function ammoSnapshot(attrs:Object):Object {
        return {capacity:Number(attrs.capacity),clipname:attrs.clipname};
    }

    public static function combatDeath(actor:MovieClip):Boolean {
        var run:Object=currentRun();
        if(!ensure(run) || context.policy.groundDropsEnabled===false || run.outcome!=="active"
            || actor.soldierPhase!==2 || !(actor.hp<=0)
            || actor.cf6EncounterRetired===true || !Cf6SoldierActions.actorValid(actor.cf6ActionRecord))return false;
        var id:String=actor.cf6UnitIdentity,key:String="u."+id;
        var ledger:Object=run.cf6SoldierLoot;
        if(captured[key] || (ledger!=null && ledger.records[key]!=null))return true;
        if(context.policy.profiles[actor.cf6LootProfile]==null || id==undefined || id=="")return false;
        captured[key]=true;
        var worldMark:Object=StageReturnFlow.worldIdentity(_root.gameworld);
        var snapshot:Object,eligible:Boolean=true;
        try {
            snapshot={primary:itemSnapshot(actor.长枪),left:itemSnapshot(actor.手枪),right:itemSnapshot(actor.手枪2),
                primaryAmmo:ammoSnapshot(actor.长枪属性),leftAmmo:ammoSnapshot(actor.手枪属性),rightAmmo:ammoSnapshot(actor.手枪2属性),
                subAmmo:null,material:actor.cf6LootMaterial,lastUpdate:new Date().getTime()};
            var sub:Object=actor.长枪副武器配置;
            if(sub!=null)snapshot.subAmmo={capacity:sub.capacity,reserveName:sub.reserveName,
                consumeMode:sub.consumeMode,clipCostPerLoad:sub.clipCostPerLoad,fireCost:sub.fireCost};
            if(snapshot.material==null)snapshot.material="";
            var room:Object=Cf6SoldierActions.context();
            snapshot.ground={mapId:room.mapId,x:actor._x,z:actor.Z轴坐标};
            eligible=worldMark!=null && Cf6SoldierLootRules.validGround(snapshot.ground) && snapshot.primary!=null
                && (!actor.soldierIsElite || (snapshot.left!=null && snapshot.right!=null))
                && (snapshot.material==="" || ItemUtil.isItem(snapshot.material));
        }catch(snapshotError){
            eligible=false;snapshot={primary:null,left:null,right:null,material:""};
        }
        var luck:Number=Number(DropLuckRoller.getLuckBonus());
        if(!isFinite(luck) || luck<0 || luck>.5){lastError="invalid_loot_luck";return false;}
        queue.push({id:id,snapshot:snapshot,eligible:eligible,world:worldMark,profile:actor.cf6LootProfile,luck:luck,attemptAt:clock});
        if(!eligible)trace("[CF6_LOOT_INPUT] ineligible death: "+id);
        processWorld();
        return true;
    }

    private static function freeze(run:Object,request:Object):Array {
        var raw:Object=run.cf6SoldierLoot;
        var ledger:Object=raw==null ? Cf6SoldierLootRules.createGroundLedger(context.config.version,context.policy.version)
            : raw.v===2 ? Cf6SoldierLootRules.toGroundLedger(Cf6SoldierLootRules.normalizeLedger(raw).feature)
            : PersistedSnapshot.cloneData(raw);
        if(ledger==null || !Cf6SoldierLootRules.validLedger(ledger))throw new Error("invalid_ground_loot_ledger");
        if(ledger.records["u."+request.id]!=null)return [];

        var profile:Object=context.policy.profiles[request.profile],snapshot:Object=request.snapshot;
        var pool:Object=Cf6SoldierLootRules.available(ledger,snapshot,profile);
        if(pool==null)throw new Error("invalid_loot_weights");
        var rifleAmmo:Array=Cf6SoldierLootRules.ammoQuote(snapshot,"longgun",WeaponAmmoRuntime.quoteInventoryPacks);
        var pairAmmo:Array=Cf6SoldierLootRules.ammoQuote(snapshot,"sidearm_pair",WeaponAmmoRuntime.quoteInventoryPacks);
        if(rifleAmmo==null)pool.longgun=0;
        if(pairAmmo==null)pool.sidearm_pair=0;
        pool.total=pool.longgun+pool.sidearm_pair+pool.mod_material;
        var evaluated:Boolean=request.eligible && pool.total>0;
        var kind:String="none";
        if(evaluated){
            var prd:PseudoRandomDistribution=new PseudoRandomDistribution(ledger.prd);
            var guaranteed:Boolean=Cf6SoldierLootRules.firstWeaponDue(ledger,pool,context.policy,true);
            context.gateCalls++;
            var hit:Boolean=DropLuckRoller.rollDropWithContext("cf6.fixed158."+request.profile,
                {名字:"缴获包",概率:profile.nominalPercent},request.luck,prd);
            if(guaranteed)kind="longgun";
            else if(hit)kind=Cf6SoldierLootRules.choose(pool,LinearCongruentialEngine.instance.nextFloat());
        }
        if(!Cf6SoldierLootRules.reserveGround(ledger,request.id,evaluated,kind)
            || !Cf6SoldierLootRules.validLedger(ledger))throw new Error("ground_loot_reservation_conflict");

        var items:Array=[];
        if(kind=="longgun")items=[snapshot.primary].concat(rifleAmmo);
        else if(kind=="sidearm_pair")items=[snapshot.left,snapshot.right].concat(pairAmmo);
        else if(kind=="mod_material")items=[{name:snapshot.material,value:1,lastUpdate:snapshot.lastUpdate}];
        PlayerAssetTransaction.markDirtyRequired(_root.存档系统);
        run.cf6SoldierLoot=ledger;
        return items;
    }

    /** A missing manager or pre-attach refusal can be retried with the same frozen items.
     * A creation with an unknown result is never repeated, even if registration failed. */
    private static function placeWorldItems(request:Object):Boolean {
        var manager:Object=_root.pickupItemManager;
        if(typeof manager.createCollectible!="function")return request.items.length>0;
        var retry:Boolean=false,ground:Object=request.snapshot.ground;
        for(var i:Number=0;i<request.items.length;i++){
            var item:Object=request.items[i];
            if(item==null)continue;
            if(request.world!==StageReturnFlow.worldIdentity(_root.gameworld))return false;
            var creation:Object={state:"not_created"};
            try {
                var quantity:Number=typeof item.value=="object" ? Number(item.value.level) : Number(item.value);
                manager.createCollectible(item.name,quantity,ground.x+i*16,ground.z,false,{pickupItemData:item},creation);
            }catch(attachError){
                lastError="ground_loot_creation_error";
                trace("[CF6_LOOT_WORLD] item="+item.name+" state="+creation.state+" error="+attachError);
            }
            if(creation.state==="not_created")retry=true;
            else request.items[i]=null;
        }
        return retry;
    }

    private static function processWorld():Void {
        var run:Object=currentRun();
        if(processing || queue.length==0 || !sameRun(run)
            || RewardStashService.pendingOperationId()!="" || PlayerAssetTransaction.current()!=null)return;
        processing=true;
        try {
            if(!finishLegacy(run))return;
            run=currentRun();
            var count:Number=queue.length;
            for(var i:Number=0;i<count;i++){
                var request:Object=queue.shift();
                if(clock<request.attemptAt){queue.push(request);continue;}
                run=currentRun();
                if(!sameRun(run))break;
                try {
                    if(request.items==null)request.items=freeze(run,request);
                    if(run.outcome==="active" && request.world===StageReturnFlow.worldIdentity(_root.gameworld)
                        && placeWorldItems(request)){
                        request.attemptAt=clock+30;
                        queue.push(request);
                    }
                }catch(decisionError){
                    lastError="ground_loot_decision_error";
                    trace("[CF6_LOOT_WORLD] death="+request.id+" error="+decisionError);
                }
            }
        }finally{processing=false;}
    }

    /** Only guards operations that would replace or delete the old bookRun. */
    public static function settleLegacyBeforeReplacement():Boolean {
        var run:Object=currentRun();
        return run==null || finishLegacy(run);
    }

    private static function finishLegacy(run:Object):Boolean {
        if(legacyOperation!="" || RewardStashService.pendingOperationId()!="")return false;
        var raw:Object=run.cf6SoldierLoot;
        if(raw==null || raw.v===3)return true;
        var normalized:Object=Cf6SoldierLootRules.normalizeLedger(raw);
        if(!normalized.ok){lastError="invalid_saved_loot_ledger";return false;}
        var ledger:Object=normalized.feature,hits:Array=[];
        for(var key:String in ledger.records){
            var packet:Object=ledger.records[key];
            if(packet.state==="COMMIT_PENDING"){lastError="saved_admission_unresolved";return false;}
            if(packet.state==="DECIDED_HIT")hits.push(key);
        }
        if(hits.length==0)return true;
        installWatcher();
        if(clock<legacyRetryAt || PlayerAssetTransaction.current()!=null)return false;

        var operation:String="cf6.loot."+run.seed+"."+run.startedAt+".m"+ledger.sequence;
        var origin:Object={source:"cf6_type61",reason:"soldier_capture",operationId:operation};
        legacyOperation=operation;
        if(!RewardStashService.begin(operation,origin,legacyResolved,{operationId:operation})){
            legacyOperation="";legacyRetryAt=clock+60;lastError=RewardStashService.lastError;return false;
        }
        try {
            var working:Object=PersistedSnapshot.cloneData(ledger);
            for(var i:Number=0;i<hits.length;i++){
                packet=working.records[hits[i]];
                origin.sourceKey=packet.sourceKey;
                // Complete the frozen v2 entitlement using its original delivery preference.
                if(!RewardStashService.admit(packet.items,packet.ground==null,true,origin)
                    || !RewardStashService.admit(packet.consumables,true,true,origin))
                    throw new Error("legacy_capture_admission_failed");
                packet.state="OWNED";
                packet.admissionOperationId=operation;
            }
            var compact:Object=Cf6SoldierLootRules.toGroundLedger(working);
            if(compact==null)throw new Error("legacy_capture_summary_failed");
            _root._saveExt.bookRun.cf6SoldierLoot=compact;
            var result:Object=RewardStashService.end("cf6.loot.migrate|"+ledger.sequence,
                {success:true,kind:"legacy_soldier_admission",count:hits.length},"reward.cf6_type61");
            return result.success===true;
        }catch(error){
            lastError=String(error);
            RewardStashService.cancel("legacy_capture_failed");
            return false;
        }
    }

    private static function legacyResolved(committed:Boolean,domain:Object):Boolean {
        if(legacyOperation!==domain.operationId)return true;
        legacyOperation="";
        legacyRetryAt=clock+60;
        if(committed)lastError="";
        else if(lastError=="")lastError="legacy_capture_not_committed";
        return true;
    }

    public static function tick():Void {
        clock++;
        if(legacyOperation!=""){
            if(clock%60==0 && RewardStashService.pendingOperationId()===legacyOperation)
                RewardStashService.resume(legacyOperation);
            return;
        }
        if(clock%30!=0)return;
        var run:Object=currentRun();
        if(!sameRun(run))return;
        if(queue.length>0)processWorld();
        else if(run.cf6SoldierLoot!=null && run.cf6SoldierLoot.v===2)finishLegacy(run);
    }

    public static function status():Object {
        return {bound:sameRun(currentRun()),queued:queue.length,operationId:legacyOperation,
            gateCalls:context.gateCalls,error:lastError};
    }
}
