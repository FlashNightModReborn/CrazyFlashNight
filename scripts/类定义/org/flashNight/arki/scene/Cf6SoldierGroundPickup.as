import org.flashNight.arki.item.RewardStashService;
import org.flashNight.arki.item.RewardStashStore;
import org.flashNight.arki.pause.PauseManager;
import org.flashNight.arki.scene.Cf6SoldierActions;
import org.flashNight.arki.scene.Cf6SoldierLootRules;
import org.flashNight.arki.scene.StageReturnFlow;

/** Ground entities point at durable equipment entries. Picking them uses the
 * existing exact stash take/query transaction; no second reward is created. */
class org.flashNight.arki.scene.Cf6SoldierGroundPickup {
    private static var identity:Object;
    private static var shown:Object={};
    private static var world:MovieClip;
    private static var worldMark:Object;
    private static var pending:Object;
    private static var frames:Number=0;
    private static var resolvedSuccess:Boolean=false;
    private static var viewStore:String="";
    private static var viewRevision:Number=-1;
    private static var refreshAt:Number=0;
    public static var lastError:String="";

    private static function sameRun():Boolean {
        var run:Object=_root._saveExt.bookRun;
        return identity!=null && run.bookId==="cf6-sting" && run.routeId==="type61"
            && run.slot===identity.slot && run.slot===String(_root.savePath)
            && run.seed===identity.seed && run.startedAt===identity.startedAt && run.planSeed===identity.planSeed;
    }
    public static function busy():Boolean {return pending!=null;}
    private static function owns(d:Object):Boolean {
        return d!=null && d.identity===identity && sameRun() && d.world===_root.gameworld
            && d.mark===StageReturnFlow.worldIdentity(_root.gameworld)
            && d.mc._parent===d.world && d.mc.cf6GroundIdentity===d.token;
    }
    private static function removeDisplay(d:Object):Void {
        if(d==null)return;
        delete shown["$"+d.entryId];
        if(!owns(d))return;
        var dict:Object=d.manager.getPickupItemDict();
        if(dict[d.mc.index]===d.mc)delete dict[d.mc.index];
        d.mc.__pickupClaimed=true;
        d.mc.gotoAndPlay("消失");
    }
    private static function notify(text:String):Void {
        try {_root.发布消息(text);}catch(notificationError){}
    }
    private static function finish(committed:Boolean,result:Object):Void {
        var current:Object=pending;
        if(current==null)return;
        var accepted:Boolean=false;
        if(committed){
            if(result.success!==true || !(result.accepted instanceof Array) || !(result.blocked instanceof Array)
                || result.accepted.length!==1 || result.blocked.length!==0){
                lastError="pickup_receipt_invalid";return;
            }
            for(var i:Number=0;i<result.accepted.length;i++){
                var row:Object=result.accepted[i];
                if(row.entryId!==current.params.entries[0].entryId || row.quantity!==1){lastError="pickup_receipt_invalid";return;}
                accepted=true;
            }
        }
        pending=null;resolvedSuccess=accepted;
        if(current.lease!==undefined)PauseManager.releaseLease(current.lease);
        var d:Object=current.display;
        if(accepted){
            lastError="";
            notify("已拾取缴获武器："+d.displayName+"。原强化和插件已保留。");
            if(owns(d)){
                try {d.world.dispatcher.publish("Pickup",d.itemName);}catch(eventError){}
                if(current.animate && current.actor.__cf6GroundActor===current.actorMark
                    && current.actor._parent===d.world && current.actor.hp>0
                    && current.actor.__playerStatProjectionBlocked!==true && current.actor.__playerStatInitializing!==true){
                    try {current.actor.拾取();}catch(animationError){}
                }
            }
            removeDisplay(d);
        }else{
            lastError="pickup_not_committed";
            if(owns(d))d.mc.__pickupClaimed=false;
            notify(current.blocked?"物品栏空间不足，缴获武器仍保留在原处和奖励暂存。":"拾取未能保存，缴获武器仍保留在原处和奖励暂存。");
        }
    }
    public static function reconcile():Void {
        if(pending==null || !sameRun())return;
        var result:Object;
        try {result=RewardStashService.query(pending.params);}catch(queryError){lastError="pickup_outcome_unknown";return;}
        if(result.success===true && result.state=="committed")finish(true,result.result);
        else if(result.success===true && result.state=="not_committed")finish(false,null);
        else if(result.error!="commit_pending")lastError="pickup_outcome_unknown";
    }
    public static function claim(manager:Object,target:MovieClip,actor:Object,animate:Boolean):Boolean {
        if(!sameRun() || pending!=null || actor==null || !(actor.hp>0) || actor.是否为敌人===true)return false;
        var d:Object=shown["$"+target.cf6GroundEntryId];
        if(d==null || d.manager!==manager || d.mc!==target || !owns(d) || actor._parent!==d.world
            || actor.__playerStatProjectionBlocked===true || actor.__playerStatInitializing===true)return false;
        if(RewardStashService.pendingOperationId()!="")return false;
        var store:Object=RewardStashService.peek(),entry:Object=RewardStashStore.find(store,d.entryId);
        if(store==null || store.storeId!==d.storeId || !(store.entries instanceof Array))return false;
        if(entry==null){removeDisplay(d);return true;}
        if(typeof entry.item.value!="object" || entry.item.name!==d.itemName)return false;
        var params:Object={storeId:store.storeId,expectedRevision:store.commitRevision,
            operationId:RewardStashService.nextOperationId("cf6_ground"),
            entries:[{entryId:entry.entryId,revision:entry.revision,quantity:1}]};
        var actorMark:Object={};actor.__cf6GroundActor=actorMark;
        pending={params:params,display:d,actor:actor,actorMark:actorMark,animate:animate,lease:undefined,blocked:false};
        resolvedSuccess=false;lastError="";
        try {
            PauseManager.install();pending.lease=PauseManager.lease(true,"cf6_ground_pickup");
            var result:Object=RewardStashService.take(params);
            pending.blocked=result.success===true && result.accepted instanceof Array && result.accepted.length==0;
            if(result.error=="invalid_payload" || result.error=="stale_stash" || result.error=="stale_entry"){
                finish(false,null);return false;
            }
        }catch(takeError){lastError="pickup_outcome_unknown";}
        // Even synchronous success is reconciled against the exact durable operation.
        reconcile();
        return pending!=null || resolvedSuccess;
    }
    public static function tick(owner:Object):Void {
        frames++;
        if(identity!==owner){
            if(pending!=null)return;
            identity=owner;shown={};world=null;worldMark=null;viewRevision=-1;lastError="";
        }
        if(!sameRun())return;
        if(pending!=null){if(frames%30==0)reconcile();return;}
        if(RewardStashService.pendingOperationId()!="")return;
        var current:Object=Cf6SoldierActions.context();
        if(current==null)return;
        var mark:Object=StageReturnFlow.worldIdentity(_root.gameworld);
        if(world!==_root.gameworld || worldMark!==mark){world=_root.gameworld;worldMark=mark;shown={};viewRevision=-1;}
        var store:Object=RewardStashService.peek(),ledger:Object=_root._saveExt.bookRun.cf6SoldierLoot;
        if(store==null || store.storeId===viewStore && store.commitRevision===viewRevision && frames<refreshAt)return;
        viewStore=store.storeId;viewRevision=store.commitRevision;refreshAt=frames+30;
        if(!Cf6SoldierLootRules.validLedger(ledger))return;
        for(var displayed:String in shown){
            var old:Object=shown[displayed];
            if(RewardStashStore.find(store,old.entryId)==null)removeDisplay(old);
        }
        var manager:Object=_root.pickupItemManager;
        if(typeof manager.getPickupItemDict!="function" || typeof manager.createCollectible!="function")return;
        for(var key:String in ledger.records){
            var packet:Object=ledger.records[key];
            if(packet.state!="OWNED" || packet.ground.mapId!==current.mapId || !(packet.groundEntries instanceof Array))continue;
            for(var i:Number=0;i<packet.groundEntries.length;i++){
                var id:String=packet.groundEntries[i],entry:Object=RewardStashStore.find(store,id);
                var previous:Object=shown["$"+id];
                if(entry==null || typeof entry.item.value!="object" || entry.item.name!==packet.items[i].name || owns(previous))continue;
                var token:Object={},before:Number=manager.getCount();
                manager.createCollectible(entry.item.name,entry.item.value.level,
                    packet.ground.x+(packet.groundEntries.length==2?(i==0?-22:22):0),packet.ground.z,false,
                    {cf6GroundIdentity:token,cf6GroundEntryId:id});
                var mc:MovieClip=manager.getPickupItemDict()[before];
                if(manager.getCount()!=before+1 || mc._parent!==world || mc.cf6GroundIdentity!==token){lastError="ground_asset_unavailable";continue;}
                var tier:String=entry.item.value.tier;
                var title:String=String(mc.displayName || entry.item.name)
                    +(typeof tier=="string" && length(tier)>0?" · "+tier:"")+" +"+entry.item.value.level;
                var d:Object={identity:identity,world:world,mark:worldMark,mc:mc,token:token,manager:manager,
                    entryId:id,storeId:store.storeId,itemName:entry.item.name,displayName:title};
                shown["$"+id]=d;
                mc.createTextField("cf6CaptureLabel",mc.getNextHighestDepth(),-150,i==1?-130:-86,300,40);
                var label:TextField=mc.cf6CaptureLabel;
                label.multiline=true;label.wordWrap=true;label.selectable=false;label.autoSize="center";
                label.textColor=0x69E1FF;label.background=true;label.backgroundColor=0x07151B;
                label.text="缴获 · "+title+(entry.item.value.mods.length>0?"\n"+entry.item.value.mods.join(" / "):"");
                label.setTextFormat(new TextFormat("_sans",12,0x69E1FF,true));
            }
        }
    }
    public static function status():Object {
        var count:Number=0;for(var key:String in shown)if(owns(shown[key]))count++;
        return {displayed:count,pending:pending!=null,operationId:pending==null?"":pending.params.operationId,error:lastError};
    }
}
