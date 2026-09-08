/**
 * EquipmentFireIntent - 装备生命周期脚本的射击事件归属 helper
 *
 * 表达主长枪或指定手枪槽的事件归属，不封装订阅本身。
 * 装备行为仍保留在各自脚本中，避免把状态机和视觉逻辑塞进通用层。
 */
class org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.EquipmentFireIntent {

    /** processShot 的第五参绑定提交时武器；双枪两份装备引用不可重复领取同一发。 */
    public static function isPistolSlotProcessShot(target:Object, owner:Object, weaponType:String,
                                                  slot:String, weapon:Object, firedWeapon:Object):Boolean {
        if (!target || owner !== target || weaponType !== slot || (slot != "手枪" && slot != "手枪2")) return false;
        if (!weapon || target[slot] !== weapon || firedWeapon !== weapon) return false;
        return target.攻击模式 == slot || target.攻击模式 == "双枪";
    }

    public static function isMainLongGunProcessShot(target:Object, weaponType:String):Boolean {
        return weaponType == "长枪" && target.攻击模式 == "长枪";
    }

    public static function isMainLongGunUpdateBullet(target:Object, playerBulletField:String, weaponType:String):Boolean {
        if (weaponType != undefined) {
            if (weaponType != "长枪") return false;
        } else if (playerBulletField != "子弹数") {
            return false;
        }
        return target.攻击模式 == "长枪";
    }

    public static function publishMainLongGunUpdateBullet(dispatcher:Object, owner:Object, shootStateName:String, magazineRemaining:Number):Void {
        dispatcher.publish("updateBullet", owner, shootStateName, magazineRemaining, "子弹数", "长枪");
    }
}
