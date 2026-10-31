/** Candidate adapter. Install via the existing equipment lifecycle, not a new timer. */
class org.flashNight.arki.unit.Action.Huofeng.HuofengHairEquipment {
    public static function initialize(ref:Object,param:Object):Void {
        if (!ref || !ref.自机) return;
        param=param || {};
        var profile:Object=org.flashNight.arki.unit.Action.Huofeng.HuofengHairProfile.hair();
        var ownerKey:String=param.ownerSkin ? param.ownerSkin : profile.helmet;
        var previous:Object=ref.自机.__hf8LifecycleLease;
        if (previous) org.flashNight.arki.unit.Action.Huofeng.HuofengHairEquipment.releaseLease(previous,ref.自机);
        var lease:Object={controller:null,expectedHelmet:ownerKey,disposed:false};
        ref.hf8Lease=lease;ref.hf8Hair=null;ref.自机.__hf8LifecycleLease=lease;
        var actor:MovieClip=ref.自机;
        if (actor.dispatcher) {
            var callback:Function=function():Void { org.flashNight.arki.unit.Action.Huofeng.HuofengHairEquipment.releaseLease(lease,actor); };
            if (actor.dispatcher.subscribe("UnitReInitialized",callback,lease)) lease.event={dispatcher:actor.dispatcher,callback:callback};
        }
        // Lifecycle teardown owns this resource; no actor onUnload callback is overwritten.
        ref.生命周期函数列表.push({动作:function(extra:Object):Void { org.flashNight.arki.unit.Action.Huofeng.HuofengHairEquipment.releaseLease(extra.lease,extra.unit); },额外参数:{lease:lease,unit:ref.自机}});
        org.flashNight.arki.unit.Action.Huofeng.HuofengHairEquipment.ensureController(ref);
    }
    public static function cycle(ref:Object,param:Object):Void {
        if (!ref || !ref.自机 || !ref.hf8Lease || ref.hf8Lease.disposed || ref.自机.__hf8LifecycleLease!==ref.hf8Lease) return;
        // Check the equipment item as well as its skin: two helmets may share art.
        // A weapon-only version increment must not stop this visual's timer.
        // Keep hair on visible death/revival poses; unload/reinit owns final cleanup.
        if (!org.flashNight.arki.unit.Action.Huofeng.HuofengHairEquipment.ownsEquipment(ref)) {
            org.flashNight.arki.unit.Action.Huofeng.HuofengHairEquipment.releaseLease(ref.hf8Lease,ref.自机);
            _root.装备生命周期函数.移除周期函数(ref);
            return;
        }
        if (ref.是否为主角 && ref.版本号!==ref.自机.version) ref.版本号=ref.自机.version;
        org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.EquipmentTick.cleanup(ref);
        org.flashNight.arki.unit.Action.Huofeng.HuofengHairEquipment.ensureController(ref);
        if (ref.hf8Hair) ref.hf8Hair.update();
    }
    private static function ensureController(ref:Object):Void {
        var lease:Object=ref.hf8Lease;
        if (ref.自机.dressupRefreshing || ref.自机.面具!==lease.expectedHelmet) return;
        // Initialization may precede the skin/reference placement. The existing
        // lifecycle retries without allocating a second timer or actor callback.
        if (!lease.controller || lease.controller.isDisposed()) {
            lease.controller=new org.flashNight.arki.unit.Action.Huofeng.HuofengHairRig(ref.自机,org.flashNight.arki.unit.Action.Huofeng.HuofengHairProfile.hair(),lease.expectedHelmet);
            ref.hf8Hair=lease.controller;
        }
    }
    public static function releaseLease(lease:Object,unit:MovieClip):Void {
        if (!lease || lease.disposed) return;
        lease.disposed=true;
        if (lease.controller) lease.controller.dispose();
        if (lease.event) lease.event.dispatcher.unsubscribe("UnitReInitialized",lease.event.callback,lease);
        lease.event=null;
        if (unit.__hf8LifecycleLease===lease) delete unit.__hf8LifecycleLease;
    }
    private static function ownsEquipment(ref:Object):Boolean {
        if (ref.是否为主角) return _root.物品栏.装备栏.getNameString(ref.装备类型)===ref.装备名称;
        var item:Object=ref.自机[ref.装备类型];
        return item && item.name===ref.装备名称;
    }
}
