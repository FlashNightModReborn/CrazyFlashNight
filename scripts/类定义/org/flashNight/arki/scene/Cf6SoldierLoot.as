import org.flashNight.arki.scene.Cf6SoldierLootRules;
import org.flashNight.arki.scene.Cf6SoldierActions;
import org.flashNight.arki.scene.Cf6Type61Service;
import org.flashNight.arki.scene.BookDefinition;
import org.flashNight.arki.item.RewardStashService;
import org.flashNight.arki.item.DropLuckRoller;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.unit.Action.Shoot.WeaponAmmoRuntime;
import org.flashNight.arki.pause.PauseManager;
import org.flashNight.gesh.object.PersistedSnapshot;
import org.flashNight.naki.PseudoRandom.PseudoRandomDistribution;
import org.flashNight.naki.RandomNumberEngine.LinearCongruentialEngine;

/** Freeze actual death equipment, durably decide once, then admit the same
 * packet. No actor reference or live ammunition mutation crosses into a save. */
class org.flashNight.arki.scene.Cf6SoldierLoot {
    private static var context:Object;
    private static var queue:Array=[];
    private static var captured:Object={};
    private static var plan:Object;
    private static var operation:String="";
    private static var watcher:MovieClip;
    private static var clock:Number=0;
    private static var retryAt:Number=0;
    private static var retries:Number=0;
    private static var lease:String;
    private static var exitRequested:Boolean=false;
    private static var processing:Boolean=false;
    public static var lastError:String="";

    private static function sameRun():Boolean {
        var run:Object=_root._saveExt.bookRun,id:Object=context.identity;
        return context!=null && run.bookId==="cf6-sting" && run.routeId==="type61"
            && run.slot===String(_root.savePath) && run.slot===id.slot && run.seed===id.seed
            && run.startedAt===id.startedAt && run.planSeed===id.planSeed;
    }
    public static function bind(config:Object):Boolean {
        var run:Object=_root._saveExt.bookRun;
        if(run.bookId!=="cf6-sting" || run.routeId!=="type61" || run.slot!==String(_root.savePath)
            || config.lootPolicy==null || typeof config.version!="string")return false;
        if(sameRun())return true;
        if(operation!="" || queue.length>0 || plan!=null){lastError="previous_loot_owner_unsettled";return false;}
        context={identity:{slot:run.slot,seed:run.seed,startedAt:run.startedAt,planSeed:run.planSeed},
            config:config,policy:config.lootPolicy,runKey:"cf6.loot."+run.seed+"."+run.startedAt,
            decisions:0,admissions:0,gateCalls:0};
        queue=[];captured={};plan=null;operation="";clock=retryAt=retries=0;exitRequested=false;lastError="";
        if(!validPolicy(context.policy)){lastError="invalid_loot_policy";return false;}
        var ledger:Object=run.cf6SoldierLoot;
        var normalized:Object=Cf6SoldierLootRules.normalizeLedger(ledger);
        if(!normalized.ok){lastError="invalid_saved_loot_ledger";return false;}
        if(normalized.changed)run.cf6SoldierLoot=normalized.feature;
        if(watcher==null || watcher._name==undefined)watcher=_root.createEmptyMovieClip("__cf6SoldierLoot",_root.getNextHighestDepth());
        watcher.onEnterFrame=function():Void {org.flashNight.arki.scene.Cf6SoldierLoot.tick();};
        return true;
    }
    public static function validPolicy(policy:Object):Boolean {
        if(policy.schema!=="cf6-fixed-loot-policy.v1" || typeof policy.version!="string" || policy.version==""
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
    private static function ensure():Boolean {
        if(sameRun())return lastError!="invalid_saved_loot_ledger" && lastError!="invalid_loot_policy";
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
        if(!ensure() || _root._saveExt.bookRun.outcome!=="active" || actor.soldierPhase!==2 || !(actor.hp<=0)
            || actor.cf6EncounterRetired===true || !Cf6SoldierActions.actorValid(actor.cf6ActionRecord))return false;
        var id:String=actor.cf6UnitIdentity,key:String="u."+id;
        var record:Object=actor.cf6ActionRecord;
        if(captured[key] || _root._saveExt.bookRun.cf6SoldierLoot.records[key]!=null)return true;
        var rule:Object=context.policy.profiles[actor.cf6LootProfile];
        if(rule==null){lastError="missing_loot_profile";return false;}
        var snapshot:Object,eligible:Boolean=true;
        try {
            snapshot={primary:itemSnapshot(actor.长枪),left:itemSnapshot(actor.手枪),right:itemSnapshot(actor.手枪2),
                primaryAmmo:ammoSnapshot(actor.长枪属性),leftAmmo:ammoSnapshot(actor.手枪属性),rightAmmo:ammoSnapshot(actor.手枪2属性),
                subAmmo:null,material:actor.cf6LootMaterial,lastUpdate:new Date().getTime()};
            var sub:Object=actor.长枪副武器配置;
            if(sub!=null)snapshot.subAmmo={capacity:sub.capacity,reserveName:sub.reserveName,
                consumeMode:sub.consumeMode,clipCostPerLoad:sub.clipCostPerLoad,fireCost:sub.fireCost};
            // A gun with no installed material still has its normal weapon category.
            // available() removes only the absent material weight before normalization.
            if(snapshot.material==null)snapshot.material="";
            if(snapshot.primary==null || actor.soldierIsElite && (snapshot.left==null || snapshot.right==null)
                || snapshot.material!=="" && !ItemUtil.isItem(snapshot.material))eligible=false;
        }catch(snapshotError){eligible=false;snapshot={primary:null,left:null,right:null,material:"",lastUpdate:new Date().getTime()};}
        var luck:Number=Number(DropLuckRoller.getLuckBonus());
        if(!isFinite(luck) || luck<0 || luck>.5){lastError="invalid_loot_luck";return false;}
        var header:Object={sourceKey:context.runKey+"."+id,unitIdentity:id,spawnIdentity:record.key,
            rosterVersion:actor.cf6RosterVersion,configurationFingerprint:actor.cf6RosterVersion+"|"+context.policy.version+"|"+actor.cf6ProfileId};
        captured[key]=true;
        queue.push({header:header,snapshot:snapshot,eligible:eligible,profile:actor.cf6LootProfile,luck:luck});
        if(!eligible){lastError="invalid_death_equipment";trace("[CF6_LOOT_INPUT] invalid equipment for "+id);}
        return true;
    }
    private static function storedLedger():Object {
        var ledger:Object=_root._saveExt.bookRun.cf6SoldierLoot;
        return ledger==null?Cf6SoldierLootRules.create(context.config.version,context.policy.version):ledger;
    }
    private static function decisionPlan(ledger:Object):Object {
        var candidate:Object=PersistedSnapshot.cloneData(ledger);candidate.sequence=ledger.sequence+1;
        return {kind:"decide",beforeSequence:ledger.sequence,ledger:candidate,ids:[],cursor:0,
            requests:PersistedSnapshot.cloneArrayData(queue),operationId:context.runKey+".d"+candidate.sequence,context:context};
    }
    private static function buildDecisions(active:Object):Void {
        var candidate:Object=active.ledger,prd:PseudoRandomDistribution=new PseudoRandomDistribution(candidate.prd);
        while(active.cursor<active.requests.length){
            var request:Object=active.requests[active.cursor],id:String=request.header.unitIdentity;
            if(candidate.records["u."+id]!=null){active.ids.push(id);active.cursor++;continue;}
            var p:Object=context.policy.profiles[request.profile],snapshot:Object=request.snapshot;
            var stage:Object=request.decision;
            if(stage==null){
                var pool:Object=Cf6SoldierLootRules.available(candidate,snapshot,p);
                if(pool==null)throw new Error("invalid_loot_weights");
                var rifleAmmo:Array=Cf6SoldierLootRules.ammoQuote(snapshot,"longgun",WeaponAmmoRuntime.quoteInventoryPacks);
                var pairAmmo:Array=Cf6SoldierLootRules.ammoQuote(snapshot,"sidearm_pair",WeaponAmmoRuntime.quoteInventoryPacks);
                if(rifleAmmo==null)pool.longgun=0;
                if(pairAmmo==null)pool.sidearm_pair=0;
                pool.total=pool.longgun+pool.sidearm_pair+pool.mod_material;
                stage={pool:pool,rifleAmmo:rifleAmmo,pairAmmo:pairAmmo,evaluate:request.eligible && pool.total>0,
                    nominalPercent:p.nominalPercent,poolKey:"cf6.fixed158."+request.profile,
                    guarantee:Cf6SoldierLootRules.firstWeaponDue(candidate,pool,context.policy,request.eligible),
                    eligibleOrdinal:Cf6SoldierLootRules.eligibleDeaths(candidate)+1};
                request.decision=stage;
            }
            if(stage.hit===undefined){
                if(stage.rollAttempted)throw new Error("loot_roll_outcome_unresolved");
                stage.rollAttempted=true;
                if(stage.evaluate){
                    context.gateCalls++;
                    stage.hit=DropLuckRoller.rollDropWithContext(stage.poolKey,
                        {名字:"缴获包",概率:stage.nominalPercent},request.luck,prd);
                }else stage.hit=false;
            }
            if(stage.kind===undefined){
                if(stage.choiceAttempted)throw new Error("loot_category_outcome_unresolved");
                stage.choiceAttempted=true;
                stage.kind=stage.guarantee?"longgun":stage.hit?Cf6SoldierLootRules.choose(stage.pool,LinearCongruentialEngine.instance.nextFloat()):"none";
            }
            if(stage.packet==null){
                var roll:Object={recorded:true,gateEvaluated:stage.evaluate,hit:stage.guarantee || stage.hit,nominalPercent:stage.nominalPercent,
                    luckBonus:request.luck,prdPoolKey:stage.poolKey+"|缴获包",
                    reason:!request.eligible?"ineligible":!stage.evaluate?"quota_exhausted":stage.guarantee?"first_weapon_guarantee":stage.hit?"roll_hit":"roll_miss"};
                if(stage.guarantee){
                    roll.naturalHit=stage.hit;roll.guaranteeAfter=context.policy.firstWeaponGuarantee.afterEligibleDeaths;
                    roll.eligibleOrdinal=stage.eligibleOrdinal;
                }
                var ammo:Array=stage.kind=="longgun"?stage.rifleAmmo:stage.kind=="sidearm_pair"?stage.pairAmmo:[];
                stage.packet=Cf6SoldierLootRules.packet(request.header,snapshot,stage.kind,roll,ammo);
            }
            if(!Cf6SoldierLootRules.reserve(candidate,stage.packet))throw new Error("loot_reservation_conflict");
            active.ids.push(id);active.cursor++;
        }
        if(!Cf6SoldierLootRules.validLedger(candidate))throw new Error("invalid_decided_ledger");
        active.ready=true;
    }
    private static function buildAdmission(ledger:Object):Object {
        var ids:Array=[];
        for(var key:String in ledger.records){
            var packet:Object=ledger.records[key];
            if(packet.state=="COMMIT_PENDING"){lastError="saved_admission_unresolved";return null;}
            if(packet.state=="DECIDED_HIT")ids.push(packet.unitIdentity);
        }
        if(ids.length==0)return null;
        var next:Object=PersistedSnapshot.cloneData(ledger);next.sequence=ledger.sequence+1;
        return {kind:"admit",beforeSequence:ledger.sequence,ledger:next,ids:ids,
            operationId:context.runKey+".a"+next.sequence,context:context};
    }
    private static function acquirePause():Void {
        if(lease===undefined){PauseManager.install();lease=PauseManager.lease(true,"cf6_soldier_loot");}
    }
    private static function releasePause():Void {
        if(lease!==undefined){PauseManager.releaseLease(lease);lease=undefined;}
    }
    private static function executePlan(active:Object):Void {
        var ledger:Object=storedLedger();
        if(ledger.sequence!==active.beforeSequence)throw new Error("stale_loot_plan");
        var candidate:Object=PersistedSnapshot.cloneData(active.ledger);
        if(active.kind=="admit"){
            for(var i:Number=0;i<active.ids.length;i++){
                var key:String="u."+active.ids[i],packet:Object=candidate.records[key];
                if(packet.state!=="DECIDED_HIT" || !Cf6SoldierLootRules.validPacket(packet))throw new Error("invalid_admission_packet");
                packet.state="COMMIT_PENDING";
                var items:Array=packet.items.concat(packet.consumables);
                var origin:Object={source:"cf6_type61",reason:"soldier_capture",operationId:active.operationId,
                    sourceKey:packet.sourceKey};
                if(!RewardStashService.admit(items,false,true,origin))throw new Error("capture_admission_failed");
                packet.state="OWNED";packet.admissionOperationId=active.operationId;
            }
        }
        _root._saveExt.bookRun.cf6SoldierLoot=candidate;
        if(!Cf6SoldierLootRules.validLedger(candidate))throw new Error("invalid_candidate_ledger");
        var result:Object=RewardStashService.end("cf6.loot.v2|"+active.kind+"|"+candidate.sequence,
            {success:true,kind:active.kind,count:active.ids.length},"reward.cf6_type61");
        if(result.success!==true && result.error!="commit_pending" && operation!="")lastError=String(result.error);
    }
    private static function process(force:Boolean):Void {
        if(processing || !ensure() || !sameRun())return;
        if(operation!=""){
            if(RewardStashService.pendingOperationId()===operation && (force || clock%60==0))RewardStashService.resume(operation);
            return;
        }
        if(RewardStashService.pendingOperationId()!="" || (!force && clock<retryAt))return;
        if(!force && queue.length>0 && plan==null && clock%30!=0)return;
        var ledger:Object=storedLedger();
        if(!Cf6SoldierLootRules.validLedger(ledger)){lastError="invalid_saved_loot_ledger";return;}
        if(plan==null && queue.length==0)plan=buildAdmission(ledger);
        if(plan==null && queue.length==0){releasePause();return;}
        processing=true;acquirePause();
        var domain:Object={context:context,plan:plan};
        var proposed:String=plan!=null?plan.operationId:context.runKey+".d"+(ledger.sequence+1);
        operation=proposed;
        var origin:Object={source:"cf6_type61",reason:"soldier_capture",operationId:proposed};
        if(!RewardStashService.begin(proposed,origin,resolved,domain)){
            operation="";processing=false;releasePause();lastError=RewardStashService.lastError;retryAt=clock+60;return;
        }
        try {
            if(plan==null){plan=decisionPlan(ledger);domain.plan=plan;}
            if(plan.kind=="decide" && !plan.ready)buildDecisions(plan);
            executePlan(plan);
        }catch(error){
            lastError=String(error);
            var result:Object=RewardStashService.cancel("fixed_loot_candidate_failed");
            if(result.error!="commit_pending")operation="";
        }
        processing=false;
    }
    private static function resolved(committed:Boolean,domain:Object):Boolean {
        var active:Object=domain.plan;
        if(domain.context!==context)return true;
        operation="";
        if(committed && active!=null){
            if(active.kind=="decide"){
                for(var i:Number=queue.length-1;i>=0;i--){
                    for(var j:Number=0;j<active.ids.length;j++)if(queue[i].header.unitIdentity===active.ids[j]){queue.splice(i,1);break;}
                }
                context.decisions+=active.ids.length;
            }else context.admissions+=active.ids.length;
            plan=null;retries=0;retryAt=clock;lastError="";
            if(active.kind=="admit"){
                try {_root.发布消息("缴获物资已存入奖励暂存，武器与配套弹药可一起领取。");}catch(noticeError){}
            }
        }else{
            // Known rollback keeps a frozen decision. An already durable hit
            // can instead be rebuilt exactly from its existing saved packet.
            if(active!=null && active.kind=="admit")plan=null;
            retries++;retryAt=clock+60*Math.min(5,retries);
            if(lastError=="")lastError="capture_save_not_committed";
        }
        releasePause();return true;
    }
    public static function tick():Void {
        clock++;
        process(false);
        if(exitRequested && settled() && sameRun()){
            exitRequested=false;
            if(typeof _root.gameCommands.safeExit=="function")_root.gameCommands.safeExit();
        }
    }
    private static function settled():Boolean {
        if(operation!="" || plan!=null || queue.length>0)return false;
        if(!sameRun())return true;
        if(lastError=="invalid_saved_loot_ledger" || lastError=="invalid_loot_policy")return false;
        var ledger:Object=storedLedger();
        if(!Cf6SoldierLootRules.validLedger(ledger))return false;
        // A successful decision save removes the volatile request. Its durable
        // hit still needs the second atomic admission before leaving this run.
        for(var key:String in ledger.records){
            var packet:Object=ledger.records[key];
            if(packet.state=="DECIDED_HIT" || packet.state=="COMMIT_PENDING")return false;
        }
        return true;
    }
    /** A partial loot save is durable, but must not authorize SafeExit. Read
     * only: SaveManager uses this while finalizing a shared reward candidate. */
    public static function blocksSaveSuccess():Boolean {
        return exitRequested || !settled();
    }
    public static function prepareForTransition():Boolean {
        if(!ensure())return settled();
        process(true);
        return settled();
    }
    public static function deferSafeExit():Boolean {
        if(prepareForTransition())return false;
        exitRequested=true;return true;
    }
    public static function status():Object {
        return {bound:sameRun(),queued:queue.length,operationId:operation,planned:plan!=null,
            decisions:context.decisions,admissions:context.admissions,gateCalls:context.gateCalls,error:lastError};
    }
}
