import org.flashNight.arki.item.BaseItem;
import org.flashNight.arki.unit.UnitComponent.Dressup.DressupReferenceManager;
import org.flashNight.arki.unit.UnitComponent.Initializer.DressupInitializer;
import org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.KeyEdgeTrigger;
import org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.EquipmentTick;

class org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.Dual870Controller {
    private static var TRANSITION_FRAMES:Number = 6;

    public static function init(ref:Object):Void {
        var actor:MovieClip = ref.自机;
        if (actor.__dual870) dispose(actor.__dual870);
        ref.item = actor.长枪;
        ref.remaining = 0;
        ref.held = _root.按键输入检测(actor, _root.武器变形键) ? true : false;
        actor.__dual870 = ref;
        ref.shot = function():Void {
            if (!owns(ref) || actor.攻击模式 != "长枪") return;
            // The shot can arrive before this frame's equipment tick.
            sampleKey(ref);
            if (ref.remaining > 0) {
                ref.remaining = 0;
                pose(ref);
            }
        };
        actor.dispatcher.subscribe("长枪射击", ref.shot, ref);
        ref.生命周期函数列表.push({动作:dispose, 额外参数:ref});
    }

    private static function owns(ref:Object):Boolean {
        return ref != undefined && ref.自机.__dual870 === ref &&
            ref.自机.长枪 === ref.item && ref.自机.version === ref.版本号;
    }

    public static function canSwitch(actor:MovieClip):Boolean {
        var ref:Object = actor.__dual870;
        return owns(ref) && actor.攻击模式 == "长枪" && actor.hp > 0 && !actor.倒地 &&
            !_root.暂停 && _root.gameworld.__combatAdmitted !== false && ref.remaining == 0;
    }

    private static function switchForm(actor:MovieClip):Boolean {
        if (!canSwitch(actor)) return false;
        var ref:Object = actor.__dual870;
        var item:BaseItem = ref.item;
        var previous = item.value.slugMode;
        item.value.slugMode = previous !== true;
        var next:Object = item.getData();
        if (!next || !next.slugForm) {
            if (previous === undefined) delete item.value.slugMode;
            else item.value.slugMode = previous;
            return false;
        }
        // The target owns the next shot immediately. The six-frame lift is presentation only.
        DressupInitializer.applyLongGunShellForm(actor, next);
        item.update();
        if (ref.是否为主角 && typeof _root.存档系统.markDirty == "function") _root.存档系统.markDirty();
        ref.remaining = TRANSITION_FRAMES;
        DressupReferenceManager.refreshAll(actor, "长枪_装扮");
        pose(ref);
        return true;
    }

    private static function sampleKey(ref:Object):Void {
        var actor:MovieClip = ref.自机;
        if (!ref.是否为主角 || !KeyEdgeTrigger.onRise(ref, actor, _root.武器变形键, "held")) return;
        switchForm(actor);
    }

    public static function tick(ref:Object):Void {
        if (!owns(ref) || !EquipmentTick.open(ref) || _root.暂停) return;
        if (ref.remaining > 0) {
            ref.remaining--;
            pose(ref);
        }
        sampleKey(ref);
    }

    private static function pose(ref:Object):Void {
        var skin:MovieClip = ref.自机.长枪_引用;
        if (skin && skin.枪口位置) skin._rotation = 12 * ref.remaining / TRANSITION_FRAMES;
    }

    public static function dispose(ref:Object):Void {
        var actor:MovieClip = ref.自机;
        actor.dispatcher.unsubscribe("长枪射击", ref.shot, ref);
        if (actor.__dual870 === ref) {
            if (actor.长枪 === ref.item && ref.remaining > 0) {
                ref.remaining = 0;
                pose(ref);
            }
            delete actor.__dual870;
        }
    }
}
