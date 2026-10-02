import org.flashNight.arki.unit.UnitComponent.Initializer.RuntimeEquipmentProjection;
import org.flashNight.arki.component.StatHandler.DodgeHandler;

/** 打桩机两种形态共用的兵器词条投影；只转递已结算值，不重复应用配件或防护。 */
class org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.PileBunkerMeleeProjection {
    private var unit:MovieClip;
    private var equipment:Object;
    private var damageType:String;
    private var magicType:String;
    private var original:Object;
    private var owned:Object;
    private var active:Boolean;
    private static var FIELDS:Array = ["毒","吸血","击溃","命中加成","暴击","斩杀","伤害类型","魔法伤害属性"];
    private static var DATA_FIELDS:Array = ["poison","vampirism","rout","accuracy","criticalhit","slay"];
    private static var HIT_FIELDS:Array = ["毒","吸血","击溃","斩杀"];

    public function PileBunkerMeleeProjection(owner:MovieClip, weapon:Object, damage:String, magic:String) {
        unit = owner; equipment = weapon; damageType = damage; magicType = magic;
        original = null; owned = null; active = true;
    }
    private function ownsBlade():Boolean {
        return active && unit.长枪 === equipment && unit.刀 === equipment && RuntimeEquipmentProjection.hasActiveAlias(unit,"刀","长枪");
    }
    public function refresh():Void {
        if (!ownsBlade()) return;
        var owner:MovieClip = unit;
        var fields:Array = FIELDS;
        var initial:Boolean = original == null;
        if (initial) { original = {}; owned = {}; }
        var changed:Boolean = false;
        for (var i:Number = 0; i < fields.length; i++) {
            var field:String = fields[i];
            var key:String = "兵器" + field;
            if (initial) original[field] = owner[key];
            else if (owner[key] !== owned[field]) continue;
            var value = field == "伤害类型" ? damageType : (field == "魔法伤害属性" ? magicType : owner["长枪" + field]);
            if (owner[key] !== value) changed = true;
            owner[key] = value; owned[field] = value;
        }
        var dataKeys:Array = DATA_FIELDS;
        var bladeProperties:Object = owner.刀属性;
        var gunProperties:Object = owner.长枪属性;
        for (i = 0; i < dataKeys.length; i++) bladeProperties[dataKeys[i]] = gunProperties[dataKeys[i]];
        bladeProperties.damagetype = damageType; bladeProperties.magictype = magicType;
        if (changed) owner.根据模式重新读取武器加成(owner.攻击模式);
    }
    public function projectBullet(props:Object):Void {
        if (!ownsBlade()) return;
        var owner:MovieClip = unit;
        var fields:Array = HIT_FIELDS;
        for (var i:Number = 0; i < fields.length; i++) {
            var field:String = fields[i];
            var base:Number = Number(owner["基础" + field]);
            var weapon:Number = Number(owner["兵器" + field]);
            if (!isFinite(base)) base = 0;
            if (!isFinite(weapon)) weapon = 0;
            var key:String = field == "击溃" ? "血量上限击溃" : field;
            if (base + weapon > 0) props[key] = Math.max(props[key] > 0 ? props[key] : 0,base + weapon);
        }
        if (!props.暴击 && owner.兵器暴击) props.暴击 = owner.兵器暴击;
        var accuracy:Number = Number(owner.基础命中率);
        if (accuracy > 0 && isFinite(accuracy) && !props.命中率) {
            var bonus:Number = Number(owner.基础命中加成) + Number(owner.兵器命中加成);
            if (!isFinite(bonus)) bonus = 0;
            props.命中率 = Math.max(accuracy * (1 + bonus / 100),DodgeHandler.HIT_RATE_LIMIT);
        }
    }
    public function restore():Void {
        var owner:MovieClip = unit;
        var fields:Array = FIELDS;
        if (original != null && ownsBlade()) {
            for (var i:Number = 0; i < fields.length; i++) {
                var field:String = fields[i];
                var key:String = "兵器" + field;
                if (owner[key] === owned[field]) owner[key] = original[field];
            }
            owner.根据模式重新读取武器加成(owner.攻击模式);
        }
        original = null; owned = null; active = false;
    }
}
