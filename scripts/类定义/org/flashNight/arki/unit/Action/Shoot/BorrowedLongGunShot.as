import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.PlayerAssetTransaction;

/** One synchronous borrowed shot. Inventory, ammo and input ownership follow the accepted shot. */
class org.flashNight.arki.unit.Action.Shoot.BorrowedLongGunShot {
    public static function hasAlternate(unit:Object):Boolean {
        if (ItemUtil.singleContain(unit.其他消耗物品, 1) != null) return true;
        var grenade:Object = _root.物品栏.装备栏.getItem("手雷");
        return _root.控制目标 === unit._name && grenade != null && grenade.name === unit.其他消耗物品;
    }

    public static function admit(unit:Object, kind:String):Boolean {
        if (kind == "stone") return ItemUtil.singleContain("强化石", 1) != null;
        if (kind == "alternate") return hasAlternate(unit);
        return true;
    }

    public static function commit(unit:Object, scope:Object):Boolean {
        if (scope.committed || scope.weapon !== unit.长枪) return false;
        var kind:String = scope.kind;
        var count:Number = kind == "alternate" ? unit.其他霰弹值 : kind == "eye" ? unit.突击者之眼数 : 1;
        if (!(count >= 1) || unit.长枪.value.shot + count > unit.长枪弹匣容量) return false;
        if (kind == "stone" && !ItemUtil.singleSubmit("强化石", 1, {source:"skill_cost", reason:"spear_edge"})) return false;
        if (kind == "alternate" && !ItemUtil.singleSubmit(unit.其他消耗物品, 1, {source:"weapon_cost", reason:"alternate_ammo"})) {
            var equipment:Object = _root.物品栏.装备栏;
            var grenade:Object = equipment.getItem("手雷");
            if (_root.控制目标 !== unit._name || grenade == null || grenade.name !== unit.其他消耗物品) return false;
            var name:String = grenade.name;
            var stacked:Boolean = !isNaN(grenade.value) && grenade.value > 1;
            if (stacked) grenade.value -= 1;
            else { equipment.remove("手雷"); scope.refreshDressup = true; }
            if (_root.存档系统) _root.存档系统.dirtyMark = true;
            PlayerAssetTransaction.recordEffect("loss", !stacked && ItemUtil.isEquipment(name) ? "equip" : "item",
                name, 1, {source:"weapon_cost", reason:"alternate_ammo"});
        }
        scope.committed = true;
        scope.extra = count - 1;
        return true;
    }

    public static function dispatched(unit:Object, scope:Object):Void {
        if (scope.kind == "cannon") scope.weapon.value.shot = unit.长枪弹匣容量;
        else if (scope.extra > 0) scope.weapon.value.shot += scope.extra;
        scope.fired = true;
        if (typeof scope.afterDispatch == "function") scope.afterDispatch(unit, scope);
    }

    public static function run(unit:Object, flag:String, kind:String):Boolean {
        if (_root.暂停 || unit.__borrowedLongGunShot != null) return false;
        var scope:Object = {kind:kind, weapon:unit.长枪, committed:false, fired:false};
        if (unit.攻击模式 != "长枪" || !scope.weapon || typeof unit.攻击 != "function") return false;
        var hadFlag:Boolean = unit.hasOwnProperty(flag);
        var oldFlag = unit[flag];
        var wasRunning = unit.强制奔跑;
        unit.__borrowedLongGunShot = scope;
        try {
            unit.强制奔跑 = false;
            unit[flag] = true;
            unit.攻击(scope);
        } finally {
            if (scope.projectile != null && scope.man.子弹属性 === scope.projectile) scope.man.子弹属性 = scope.template;
            if (hadFlag) unit[flag] = oldFlag; else delete unit[flag];
            if (!scope.fired) unit.强制奔跑 = wasRunning;
            delete unit.__borrowedLongGunShot;
            if (scope.refreshDressup) _root.刷新人物装扮(unit._name);
        }
        return scope.fired === true;
    }
}
