import org.flashNight.arki.unit.Action.Regeneration.HealApplier;
import org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.EquipmentFireIntent;

/** 武器固有发电。独立于套装事务，装备卸载时精确取消自身订阅。 */
class org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.P90EnergyGenerator {
    public static function initialize(ref:Object, params:Object):Void {
        var amount:Number = Number(params.extraMpPerShot);
        if (!(amount > 0) || !isFinite(amount) || !ref.生命周期函数列表) return;
        if (ref.__p90EnergyCleanup) ref.__p90EnergyCleanup();
        var target:MovieClip = ref.自机;
        var dispatcher:Object = target.dispatcher;
        if (!dispatcher || typeof dispatcher.subscribe != "function") return;
        var slot:String = ref.装备类型;
        if (slot != "手枪" && slot != "手枪2") return;
        var weapon:Object = target[slot];
        var version = ref.版本号;
        var active:Boolean = true;
        var handler:Function = function(owner:Object, weaponType:String, muzzle:Object, props:Object, firedWeapon:Object):Void {
            if (!active || !target._parent || target.version !== version || target.dispatcher !== dispatcher ||
                weapon.name !== ref.装备名称 || !(target.hp > 0)) return;
            if (!EquipmentFireIntent.isPistolSlotProcessShot(target, owner, weaponType, slot, weapon, firedWeapon)) return;
            if (!isFinite(target.mp) || target.mp < 0 || !isFinite(target.mp满血值) || !(target.mp满血值 > 0)) return;
            HealApplier.applyMpCapped(target, amount, target.mp满血值);
        };
        if (!dispatcher.subscribe("processShot", handler, ref)) return;
        var cleanup:Function = function():Void {
            if (!active) return;
            active = false;
            dispatcher.unsubscribe("processShot", handler, ref);
            if (ref.__p90EnergyCleanup === cleanup) delete ref.__p90EnergyCleanup;
        };
        ref.__p90EnergyCleanup = cleanup;
        ref.生命周期函数列表.push({动作:cleanup});
    }
}
