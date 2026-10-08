import org.flashNight.arki.render.EquipmentLightBridge;
import org.flashNight.arki.item.equipment.TagManager;
import org.flashNight.arki.component.Buff.BuffManager;
import org.flashNight.arki.component.Buff.PodBuff;
import org.flashNight.arki.component.Buff.BuffCalculationType;

// AS2 gameplay ownership is independent of native capability, culling and lamp budget.
// A single per-actor pod applies the strongest active flashlight's additive evasion bonus.
class org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.EquipmentLightDefense {
    private static var nextGroup:Number = 0;

    public static function bind(ref:Object, param:Object):Void {
        release(ref);
        var amount:Number = Number(param.evasionBonus);
        var extra:Number = param.electricEvasionBonus == undefined ? 0 : Number(param.electricEvasionBonus);
        if (!(amount > 0) || !isFinite(amount + extra) || amount + extra > 100 || extra < 0
            || ref.equipmentLight.kind != 1 || (ref.来源插件 == undefined && param.builtinDefense !== true)) return;
        var actor:MovieClip = ref.自机;
        var item = actor[ref.装备类型];
        var tags:Object = TagManager.buildTagContext(item, actor[ref.装备类型 + "数据"]);
        ref.lightDefenseBonus = amount + (tags.presentTags["电力"] ? extra : 0);
        ref.lightDefenseOn = false;
        var group:Object = actor.__equipmentLightDefenseGroup;
        if (!group || group.identity !== actor.__equipmentLightIdentity) {
            group = {actor:actor, identity:actor.__equipmentLightIdentity, refs:[],
                id:"equipment-light-defense:" + (++nextGroup), manager:null, pod:null, value:0, bonus:0};
            actor.__equipmentLightDefenseGroup = group;
        }
        group.refs.push(ref); ref.lightDefenseGroup = group;
    }

    public static function setActive(ref:Object, enabled:Boolean):Void {
        if (!ref.lightDefenseGroup) return;
        ref.lightDefenseOn = enabled;
        refresh(ref.lightDefenseGroup);
    }

    private static function removePod(group:Object):Void {
        var manager:BuffManager = group.manager;
        if (manager && group.pod && manager.getBuffById(group.id) === group.pod) {
            group.pod.deactivate();
            // AVM1 can rebind an old MovieClip reference to a new same-path actor.
            // Do not ask that old manager to touch properties on the replacement.
            if (group.actor.__equipmentLightIdentity === group.identity && group.actor.buffManager === manager) {
                manager.removeBuff(group.id);
                manager.update(0);
            }
        }
        group.manager = null; group.pod = null; group.value = 0; group.bonus = 0;
    }

    private static function refresh(group:Object):Void {
        var actor:MovieClip = group.actor;
        if (!actor._parent || actor.__equipmentLightIdentity !== group.identity) { removePod(group); return; }
        var bonus:Number = 0;
        var refs:Array = group.refs;
        for (var i:Number = 0; i < refs.length; i++) {
            var ref:Object = refs[i];
            if (ref.lightDefenseOn && EquipmentLightBridge.isDrawn(ref)) bonus = Math.max(bonus, ref.lightDefenseBonus);
        }
        var manager:BuffManager = actor.buffManager;
        if (!(bonus > 0) || !manager) { removePod(group); return; }
        if (group.manager !== manager) removePod(group);
        var existing:Number = Number(actor.闪避加成);
        if (!isFinite(existing)) existing = 0;
        // DodgeRate is stored inversely. This ratio adds N to the same equipment
        // bonus pool while leaving other managed dodge modifiers and base writes intact.
        var base:Number = Math.max(1, 100 + existing);
        var value:Number = base / (base + bonus) - 1;
        if (!group.pod || manager.getBuffById(group.id) !== group.pod) {
            group.pod = new PodBuff("躲闪率", BuffCalculationType.PERCENT, value);
            group.manager = manager;
            manager.addBuffImmediate(group.pod, group.id);
        } else if (group.value != value) manager.setPodBuffValue(group.id, value);
        group.value = value; group.bonus = bonus;
    }

    public static function release(ref:Object):Void {
        var group:Object = ref.lightDefenseGroup;
        ref.lightDefenseOn = false;
        if (!group) return;
        ref.lightDefenseGroup = null;
        var refs:Array = group.refs;
        for (var i:Number = refs.length - 1; i >= 0; i--) if (refs[i] === ref) refs.splice(i, 1);
        refresh(group);
        if (refs.length == 0 && group.actor.__equipmentLightDefenseGroup === group
            && group.actor.__equipmentLightIdentity === group.identity) delete group.actor.__equipmentLightDefenseGroup;
    }

    public static function getActiveBonus(actor:MovieClip):Number {
        var group:Object = actor.__equipmentLightDefenseGroup;
        return group && group.identity === actor.__equipmentLightIdentity ? group.bonus : 0;
    }
}
