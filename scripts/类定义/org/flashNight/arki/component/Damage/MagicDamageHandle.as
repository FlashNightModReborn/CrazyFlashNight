
import org.flashNight.arki.component.Damage.*;


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

        var enemyMagicResist:Number;

        if (bullet.魔法伤害属性) {
            if (target.魔法抗性 && (target.魔法抗性[bullet.魔法伤害属性] || target.魔法抗性[bullet.魔法伤害属性] === 0)) {
                enemyMagicResist = target.魔法抗性[bullet.魔法伤害属性];
            } else if (target.魔法抗性 && (target.魔法抗性["基础"] || target.魔法抗性["基础"] === 0)) {
                enemyMagicResist = target.魔法抗性["基础"];
            } else {
                enemyMagicResist = 10 + target.等级 / 2;
            }
        } else {
            if (target.魔法抗性 && (target.魔法抗性["基础"] || target.魔法抗性["基础"] === 0)) {
                enemyMagicResist = target.魔法抗性["基础"];
            } else {
                enemyMagicResist = 10 + target.等级 / 2;
            }
        }

        // 手动展开 isNaN 检查和 min/max 逻辑
        enemyMagicResist = (enemyMagicResist != enemyMagicResist) ? 20 : (enemyMagicResist < -1000 ? -1000 : (enemyMagicResist > 100 ? 100 : enemyMagicResist));

        // 手动展开 Math.floor
        var rawDamage:Number = bullet.破坏力 * (100 - enemyMagicResist) / 100;
        target.损伤值 = (rawDamage >= 0) ? (rawDamage | 0) : ((rawDamage == (rawDamage | 0)) ? rawDamage : ((rawDamage - 1) | 0));
    }


    public function toString():String
    {
        return "MagicDamageHandle";
    }
}
