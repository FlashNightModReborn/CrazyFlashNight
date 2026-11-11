import org.flashNight.arki.unit.Action.Regeneration.HealApplier;
import org.flashNight.arki.unit.UnitComponent.Initializer.ElementComponent.BoxInteractionArbiter;

/** 三犬共享能力入口；军阀铁卫犬保持原控制器。死亡标记只在真实撕咬命中时分配。 */
class org.flashNight.arki.unit.UnitAI.Custom.DogBehavior {
    public static function kind(unit:Object):String {
        if (unit.兵种 == "敌人-僵尸1-狗") return "zombie";
        if (unit.兵种 == "敌人-盗贼撕咬犬") return "thief";
        if (unit.兵种 == "敌人-制式军警犬") return "military";
        return "";
    }
    public static function canPickup(unit:Object):Boolean {
        var form:String = kind(unit);
        return form != "" && (unit.是否为敌人 === false || form == "thief");
    }
    public static function configure(unit:Object):Void {
        var form:String = kind(unit);
        if (form == "") return;
        unit.__dogForm = form;
        unit.允许拾取 = canPickup(unit);
        // 与 dispatcher 生命周期一致；普通 Object 身份不会随同路径 MC 重建而复用。
        unit.__dogLife = {};
        if (_root.gameworld.__dogWorldIdentity == undefined) _root.gameworld.__dogWorldIdentity = {};
    }
    public static function decorateBullet(unit:Object, bullet:Object):Void {
        if (unit.__dogForm == "zombie" && unit.是否为敌人 === false)
            bullet.hitBehavior = {type:"zombieDogAssist",life:unit.__dogLife};
    }
    public static function mark(target:Object, unit:Object, behavior:Object):Boolean {
        if (!target || !unit || target.element || target.是否为敌人 !== true || unit.__dogForm != "zombie"
                || unit.是否为敌人 !== false || behavior.life !== unit.__dogLife
                || !(unit.hp > 0) || !target.dispatcher) return false;
        var now:Number = Number(_root.帧计时器.当前帧数);
        if (!isFinite(now)) return false;
        if (target.__zombieDogMarkDispatcher === target.dispatcher
                && target.__zombieDogDeathSettled === true) return false;
        var marks:Array = target.__zombieDogMarks;
        if (target.__zombieDogMarkDispatcher !== target.dispatcher) {
            marks = [];
            target.__zombieDogMarks = marks;
            target.__zombieDogMarkDispatcher = target.dispatcher;
            target.__zombieDogDeathSettled = false;
            target.dispatcher.subscribe("kill", DogBehavior.onMarkedDeath, target);
            target.dispatcher.subscribe("death", DogBehavior.onMarkedDeath, target);
        }
        for (var i:Number = marks.length - 1; i >= 0; i--) {
            var old:Object = marks[i];
            if (!old.claimed && old.life === unit.__dogLife) {
                old.hitFrame = now;
                return true;
            }
            if (old.claimed || !(now - old.hitFrame < 90)) marks.splice(i,1);
        }
        marks.push({unit:unit,life:unit.__dogLife,hitFrame:now,claimed:false,
            world:_root.gameworld.__dogWorldIdentity});
        return true;
    }
    private static function onMarkedDeath(target:Object):Void {
        target.__zombieDogDeathSettled = true;
        var marks:Array = target.__zombieDogMarks;
        var now:Number = Number(_root.帧计时器.当前帧数);
        for (var i:Number = 0; i < marks.length; i++) {
            var mark:Object = marks[i];
            if (mark.claimed) continue;
            mark.claimed = true;
            var unit:Object = mark.unit;
            if (!isFinite(now) || !(now - mark.hitFrame < 90) || now < mark.hitFrame
                    || !(unit.hp > 0) || unit.__dogLife !== mark.life
                    || unit._parent !== _root.gameworld
                    || mark.world !== _root.gameworld.__dogWorldIdentity
                    || unit.是否为敌人 !== false || unit.__dogForm != "zombie") continue;
            HealApplier.applyHpCapped(unit,unit.hp满血值 * 0.15,unit.hp满血值);
        }
    }
    public static function pickupAtTarget(unit:MovieClip, target:MovieClip):Void {
        if (!canPickup(unit) || !target || !target.area) return;
        if (BoxInteractionArbiter.isBoxPreset(target.presetName)) {
            BoxInteractionArbiter.openForCompanion(target,unit);
        } else if (typeof unit.尝试拾取 == "function") {
            unit.拾取目标 = target._name;
            unit.尝试拾取();
        }
    }
    public static function validCombatTarget(target:Object):Boolean {
        return target && target.hp > 0 && !protectedFromDog(target);
    }
    public static function protectedFromDog(target:Object):Boolean {
        if (!BoxInteractionArbiter.isBoxPreset(target.presetName)) return false;
        return target.companionBreakAllowed === false || target.unlockMode == "minigame"
            || target.presetName == "保险柜" || target.presetName == "装备箱"
            || target.presetName == "生存箱" || target.presetName == "隐藏资源点";
    }
}
