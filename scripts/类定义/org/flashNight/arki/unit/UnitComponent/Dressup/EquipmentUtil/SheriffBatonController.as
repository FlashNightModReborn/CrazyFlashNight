import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.equipment.EquipmentCalculator;
import org.flashNight.arki.item.equipment.EquipmentConfigManager;
import org.flashNight.arki.item.equipment.ModRegistry;
import org.flashNight.arki.component.Buff.BuffManager;
import org.flashNight.arki.component.Buff.PodBuff;
import org.flashNight.arki.component.Buff.BuffCalculationType;
import org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.EquipmentTick;
import org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.KeyEdgeTrigger;
import org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.PlacementVisual;

// One item and one existing transform key. Mode is local to this equipment lifecycle.
class org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.SheriffBatonController {
    private static var serial:Number = 0;

    public static function init(ref:Object, param:Object):Void {
        var actor:MovieClip = ref.自机;
        if (actor.__sheriffBatonOwner) dispose(actor.__sheriffBatonOwner);
        ref.disposed = false;
        ref.item = actor.刀;
        ref.properties = actor.刀属性;
        ref.fullPower = Number(ref.properties.power);
        ref.originalActionType = actor.兵器动作类型;
        ref.batonActionType = param.actionTypeA;
        ref.bladeActionType = param.actionTypeB;
        ref.frame = 1; ref.bladeTarget = false;
        ref.frameMax = Number(param.frameMax);
        var raw:Object = ItemUtil.getItemData(ref.item.name);
        var config:Object = EquipmentConfigManager.getFullConfig();
        var mods:Object = ModRegistry.getModDict();
        if (!raw || !(ref.frameMax > 1) || !isFinite(ref.fullPower + ref.frameMax)) return;
        // Calculate both bases through the same upgrade/modifier pipeline. Flat bonuses
        // and equipment sharpness remain intact; caps and overrides retain their order.
        var blade:Object = EquipmentCalculator.calculatePure(raw, ref.item.value, config, mods);
        raw.data.power = Number(param.batonPower);
        var baton:Object = EquipmentCalculator.calculatePure(raw, ref.item.value, config, mods);
        ref.batonPower = Math.max(0, ref.fullPower - (Number(blade.data.power) - Number(baton.data.power)));
        ref.defense = Math.floor(Number(param.batonDefence) * EquipmentConfigManager.getLevelMultiplier(ref.item.value.level));
        if (!isFinite(ref.batonPower + ref.defense) || ref.defense < 0) return;
        ref.buffId = "sheriff-baton:" + (++serial);
        actor.__sheriffBatonOwner = ref;
        ref.keyHeld = !!_root.按键输入检测(actor, _root.武器变形键);
        ref.cleanup = {动作:dispose, 额外参数:ref};
        ref.生命周期函数列表.push(ref.cleanup);
        ref.placement = PlacementVisual.hookVisualUpdate(actor, "刀_引用", ref, visual, ref);
        apply(ref);
        visual(ref);
    }

    private static function valid(ref:Object):Boolean {
        var actor:MovieClip = ref.自机;
        return !ref.disposed && actor._parent != undefined && actor.__sheriffBatonOwner === ref
            && actor.刀 === ref.item && actor.刀属性 === ref.properties && actor.version === ref.版本号;
    }

    private static function drawn(ref:Object):Boolean {
        var actor:MovieClip = ref.自机;
        if (!(actor.hp > 0) || actor.攻击模式 != "兵器" || !actor._visible) return false;
        var clip:MovieClip = actor.刀_引用;
        if (!clip._parent) return false;
        while (clip && clip !== actor) {
            if (!clip._visible) return false;
            clip = clip._parent;
        }
        return clip === actor;
    }

    public static function tick(ref:Object):Void {
        if (!valid(ref)) { dispose(ref); return; }
        if (!EquipmentTick.open(ref)) return;
        var edge:Boolean = KeyEdgeTrigger.onRise(ref, ref.自机, _root.武器变形键, "keyHeld");
        if (_root.暂停) return;
        if (edge && drawn(ref) && _root.兵器使用检测(ref.自机)
            && (ref.frame == 1 || ref.frame == ref.frameMax)) ref.bladeTarget = !ref.bladeTarget;
        if (drawn(ref)) {
            if (ref.bladeTarget && ref.frame < ref.frameMax) ref.frame++;
            else if (!ref.bladeTarget && ref.frame > 1) ref.frame--;
        }
        apply(ref);
        visual(ref);
    }

    private static function apply(ref:Object):Void {
        // Intermediate frames have baton power and no defense: the two benefits
        // never overlap. Hidden weapons cannot contribute a defensive bonus.
        var blade:Boolean = ref.bladeTarget && ref.frame == ref.frameMax;
        ref.appliedPower = blade ? ref.fullPower : ref.batonPower;
        ref.properties.power = ref.appliedPower;
        ref.appliedActionType = blade ? ref.bladeActionType : ref.batonActionType;
        ref.自机.兵器动作类型 = ref.appliedActionType;
        var active:Boolean = drawn(ref) && !ref.bladeTarget && ref.frame == 1;
        var manager:BuffManager = ref.自机.buffManager;
        if (!active || !manager || (ref.manager && ref.manager !== manager)) removeDefense(ref);
        if (active && manager && (!ref.pod || manager.getBuffById(ref.buffId) !== ref.pod)) {
            ref.manager = manager;
            ref.pod = new PodBuff("防御力", BuffCalculationType.ADD, ref.defense);
            manager.addBuffImmediate(ref.pod, ref.buffId);
        }
    }

    public static function visual(ref:Object):Void {
        if (!valid(ref)) return;
        var saber:MovieClip = ref.自机.刀_引用;
        if (saber._parent) saber.gotoAndStop(ref.frame);
    }

    private static function removeDefense(ref:Object):Void {
        var manager:BuffManager = ref.manager;
        if (manager && ref.pod && manager.getBuffById(ref.buffId) === ref.pod) {
            ref.pod.deactivate();
            // AVM1 may rebind an old MovieClip to a replacement at the same path.
            if (ref.自机.__sheriffBatonOwner === ref && ref.自机.buffManager === manager) {
                manager.removeBuff(ref.buffId);
                manager.update(0);
            }
        }
        ref.manager = null; ref.pod = null;
    }

    public static function dispose(ref:Object):Void {
        if (!ref || ref.disposed) return;
        removeDefense(ref);
        var actor:MovieClip = ref.自机;
        if (actor.__sheriffBatonOwner === ref) {
            _root.帧计时器.移除生命周期任务(actor, ref.标签名);
            if (actor.刀属性 === ref.properties && ref.properties.power === ref.appliedPower)
                ref.properties.power = ref.fullPower;
            if (actor.刀属性 === ref.properties && actor.兵器动作类型 === ref.appliedActionType)
                actor.兵器动作类型 = ref.originalActionType;
            if (ref.placement) actor.dispatcher.unsubscribe("刀_引用", ref.placement, ref);
            delete actor.__sheriffBatonOwner;
        }
        ref.placement = null; ref.disposed = true;
        // The production teardown owns iteration of the callback array.
    }
}
