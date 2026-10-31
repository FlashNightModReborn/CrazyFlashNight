import org.flashNight.arki.scene.StageRunSession;
import org.flashNight.arki.scene.StageReturnFlow;
import org.flashNight.arki.unit.Action.Huofeng.HuofengRules;

/** 地图实例所有的契约与冷却；卸下火凤防具清契约，换武器/换 man 不清。 */
class org.flashNight.arki.unit.Action.Huofeng.HuofengRunState {
    public static function create(identity:Object):Object {
        return {identity:identity,tier:0,lastPaidSequence:0,spinReadyFrame:0,runReadyFrame:0,
            primaryReadyFrame:0,actionSequence:0,equipmentEpoch:0,setEquipped:false,armorRefs:null,
            pendingReviveSequence:0,presentedReviveSequence:0,pendingNirvanaTier:0};
    }
    private static function forMap(run:Object,world:Object):Object {
        var state:Object=run.huofeng;
        if (state==undefined || state.identity.world!==world) {
            var next:Object=create({runId:run.runId,world:world});
            // The tier resets per map; paid transaction deduplication does not.
            if (state.lastPaidSequence>0) next.lastPaidSequence=state.lastPaidSequence;
            run.huofeng=next;
        }
        return run.huofeng;
    }
    public static function forUnit(unit:Object):Object {
        var run:Object=StageRunSession.getReviveAuthority();
        var world:Object=StageReturnFlow.worldIdentity(_root.gameworld);
        if (unit._name === _root.控制目标 && run != null) {
            return forMap(run,world);
        }
        if (unit.__huofengLocalState == undefined || unit.__huofengLocalState.identity.world!==world)
            unit.__huofengLocalState=create({unitVersion:unit.version,world:world});
        return unit.__huofengLocalState;
    }
    private static function clearEquipmentContract(state:Object):Void {
        if (state.setEquipped===true || state.tier>0 || state.pendingNirvanaTier>0) {
            state.equipmentEpoch=Number(state.equipmentEpoch || 0)+1;
            state.tier=0;
            state.pendingReviveSequence=0;
            state.presentedReviveSequence=0;
            state.pendingNirvanaTier=0;
        }
        state.setEquipped=false;
        state.armorRefs=null;
        // 保留付费序号高水位和战技冷却；旧回执不能复活契约，卸装不能刷新冷却。
    }
    /** 完整装备装载后的兜底；普通重建保留，实际替换任一火凤件清零。 */
    public static function reconcileEquipment(unit:Object):Void {
        var state:Object=forUnit(unit);
        if (!HuofengRules.hasFivePieces(unit)) {clearEquipmentContract(state);return;}
        var refs:Array=[];
        for(var i:Number=0;i<HuofengRules.SLOTS.length;i++) {
            refs.push(unit[HuofengRules.SLOTS[i]]);
            if(state.armorRefs!=null && state.armorRefs[i]!==refs[i]) clearEquipmentContract(state);
        }
        state.armorRefs=refs;
        state.setEquipped=true;
    }
    /** 只在装备双槽事务已提交后调用，捕捉同面板卸下再穿回；回滚/预览不调用。 */
    public static function onEquipmentCommitted(context:Object,slot:String,beforeItem:Object):Void {
        if(context!==_root || beforeItem==null) return;
        var member:Boolean=false;
        for(var i:Number=0;i<HuofengRules.SLOTS.length;i++) if(slot===HuofengRules.SLOTS[i]) member=true;
        if(!member || beforeItem.getData().setId!==HuofengRules.SET_ID) return;
        var unit:Object=context.gameworld[context.控制目标];
        if(unit!=undefined) clearEquipmentContract(forUnit(unit));
    }
    /** 仅供成功付费复活通知调用；序号属于 StageRunSession 的真实成功事务。 */
    public static function commitPaidRevive(run:Object, unit:Object, paidEligible:Boolean, sequence:Number, paidWorld:Object, paidEquipmentEpoch:Number):Number {
        if (run == null || unit._name !== _root.控制目标 || !paidEligible
            || !(unit.hp>0) || !HuofengRules.hasFivePieces(unit)) return 0;
        if (!(sequence>0) || !isFinite(sequence) || sequence!=Math.floor(sequence)) return 0;
        var world:Object=StageReturnFlow.worldIdentity(_root.gameworld);
        var state:Object=forMap(run,world);
        // A payment belongs to the map where it was made. A delayed old-world
        // callback must not grant the new world a free tier or a pending blast.
        if (paidWorld!=undefined && paidWorld!==world) return 0;
        if (paidEquipmentEpoch!=undefined && paidEquipmentEpoch!=state.equipmentEpoch) return 0;
        if (!(sequence>state.lastPaidSequence)) return 0;
        state.setEquipped=true;
        state.lastPaidSequence=sequence;
        if (state.tier<2) state.tier++;
        // A new paid transaction still has a presentation after tier two.
        // Same-map actor replacement can consume this receipt; a new map cannot.
        state.pendingReviveSequence=sequence;
        state.pendingNirvanaTier=state.tier;
        return state.tier;
    }
    public static function notifyPaidRevive(run:Object, unit:MovieClip, paidEligible:Boolean, sequence:Number, paidWorld:Object, paidEquipmentEpoch:Number):Void {
        commitPaidRevive(run,unit,paidEligible,sequence,paidWorld,paidEquipmentEpoch);
        // The next ready maintenance tick consumes the presentation.
        // Immediate respawn callbacks can still be replacing the body/scene.
    }
}
