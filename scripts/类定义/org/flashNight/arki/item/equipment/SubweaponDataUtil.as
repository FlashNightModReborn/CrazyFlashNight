import org.flashNight.gesh.object.ObjectUtil;

/**
 * SubweaponDataUtil
 *
 * 规范化长枪副武器数据。
 * 该类只处理纯数据字段，不依赖单位运行态，供装备计算、tooltip 与射击核心共用。
 */
class org.flashNight.arki.item.equipment.SubweaponDataUtil {

    public static function hasSubweapon(itemData:Object):Boolean {
        return itemData && itemData.subweapon;
    }

    public static function getSubweaponData(itemData:Object):Object {
        if (!itemData) return null;
        if (itemData.subweapon) return normalizeSubweapon(itemData.subweapon);
        return null;
    }

    public static function normalizeItemSubweapon(itemData:Object):Object {
        if (!itemData) return null;
        if (itemData.subweapon) {
            itemData.subweapon = normalizeSubweapon(itemData.subweapon);
            return itemData.subweapon;
        }
        return null;
    }

    public static function normalizeSubweapon(source:Object):Object {
        if (!source) return null;
        var sub:Object = ObjectUtil.cloneFast(source);
        return normalizeInPlace(sub);
    }

    private static function normalizeInPlace(sub:Object):Object {
        if (!sub) return null;

        if (!sub.name || sub.name == "") sub.name = "长枪副武器";
        if (!sub.controlName || sub.controlName == "") sub.controlName = sub.name;

        sub.cd = positiveNumber(sub.cd, 500);
        sub.manualReloadCd = positiveNumber(sub.manualReloadCd != undefined ? sub.manualReloadCd : sub.reloadCd, sub.cd);
        if (!sub.manualReloadAnimation || sub.manualReloadAnimation == "") sub.manualReloadAnimation = "longGun";
        sub.manualReloadBurden = positiveNumber(sub.manualReloadBurden, 25);
        if (sub.manualReloadBurden < 20) sub.manualReloadBurden = 20;
        sub.hp = numberOrZero(sub.hp);
        sub.mp = numberOrZero(sub.mp);

        sub.power = positiveNumber(sub.power, 2500);
        sub.capacity = positiveNumber(sub.capacity != undefined ? sub.capacity : sub.bulletsize, 1);
        sub.bulletsize = sub.capacity;

        if (!sub.reserveName || sub.reserveName == "") sub.reserveName = sub.clipname ? sub.clipname : "榴弹弹药";
        sub.clipname = sub.reserveName;

        if (!sub.bullet || sub.bullet == "") sub.bullet = "榴弹";
        if (!sub.sound || sub.sound == "") sub.sound = "re_GL_under.wav";
        sub.split = positiveNumber(sub.split, 1);
        sub.diffusion = nonNegativeNumber(sub.diffusion, 0);
        sub.velocity = positiveNumber(sub.velocity, 25);
        sub.range = positiveNumber(sub.range, 50);
        sub.impact = nonNegativeNumber(sub.impact, 0.01);

        if (!sub.damagetype && sub.damageType) sub.damagetype = sub.damageType;
        if (!sub.damageType && sub.damagetype) sub.damageType = sub.damagetype;
        if (!sub.damageType || sub.damageType == "") sub.damageType = "物理";
        sub.damagetype = sub.damageType;

        if (!sub.magictype && sub.magicType) sub.magictype = sub.magicType;
        if (!sub.magicType && sub.magictype) sub.magicType = sub.magictype;

        sub.instantconsume = truthy(sub.instantconsume);
        if (!sub.consumeMode || sub.consumeMode == "") {
            sub.consumeMode = sub.instantconsume ? "onFire" : "onLoadGroup";
        }
        if (!sub.consumeTiming || sub.consumeTiming == "") {
            sub.consumeTiming = sub.consumeMode == "onLoadGroup" ? "linkedFirstFire" : "onFire";
        }

        sub.clipCostPerLoad = nonNegativeNumber(sub.clipCostPerLoad, 1);
        sub.fireCost = nonNegativeNumber(sub.fireCost, 1);
        sub.powerMultiplier = positiveNumber(sub.powerMultiplier, 1);
        return sub;
    }

    private static function numberOrZero(value:Object):Number {
        var n:Number = Number(value);
        return isNaN(n) ? 0 : n;
    }

    private static function positiveNumber(value:Object, fallback:Number):Number {
        var n:Number = Number(value);
        if (isNaN(n) || n <= 0) return fallback;
        return n;
    }

    private static function nonNegativeNumber(value:Object, fallback:Number):Number {
        var n:Number = Number(value);
        if (isNaN(n) || n < 0) return fallback;
        return n;
    }

    private static function truthy(value:Object):Boolean {
        return value === true || value == "true" || value == 1 || value == "1";
    }
}
