// File: org/flashNight/arki/component/Damage/MagicDamageHandle.as

import org.flashNight.arki.component.Damage.BaseDamageHandle;
import org.flashNight.arki.component.Damage.DamageResult;

class org.flashNight.arki.component.Damage.MagicDamageHandle extends BaseDamageHandle implements IDamageHandle {

    public static var instance:MagicDamageHandle = new MagicDamageHandle();
    public function MagicDamageHandle() {
        super();
    }

    // 判断子弹是否为魔法伤害类型
    public function canHandle(bullet:Object):Boolean {
        return (bullet.伤害类型 === "魔法");
    }

    public function handleBulletDamage(bullet:Object, shooter:Object, target:Object, manager:Object, result:DamageResult):Void {
        var magicDamageColor:String = bullet.子弹敌我属性值 ? "#0099FF" : "#AC99FF";
        result.setDamageColor(magicDamageColor);
        var magicDamageAttr:String = bullet.魔法伤害属性 ? bullet.魔法伤害属性 : "能";
        result.addDamageEffect('<font color="' + magicDamageColor + '" size="20"> ' + magicDamageAttr + '</font>');

        var enemyMagicResist:Number = bullet.魔法伤害属性 
            ? (target.魔法抗性 && (target.魔法抗性[bullet.魔法伤害属性] || target.魔法抗性[bullet.魔法伤害属性] === 0) 
                ? target.魔法抗性[bullet.魔法伤害属性]
                : (target.魔法抗性 && (target.魔法抗性["基础"] || target.魔法抗性["基础"] === 0) 
                    ? target.魔法抗性["基础"]
                    : 10 + target.等级 / 2))
            : (target.魔法抗性 && (target.魔法抗性["基础"] || target.魔法抗性["基础"] === 0) 
                ? target.魔法抗性["基础"]
                : 10 + target.等级 / 2);

        enemyMagicResist = isNaN(enemyMagicResist) ? 20 : Math.min(Math.max(enemyMagicResist, -1000), 100);
        target.损伤值 = Math.floor(bullet.破坏力 * (100 - enemyMagicResist) / 100);
    }

    public function toString():Void
    {
        return "MagicDamageHandle";
    }
}
