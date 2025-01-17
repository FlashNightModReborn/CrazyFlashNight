import org.flashNight.arki.component.Damage.*;

class org.flashNight.arki.component.Damage.MagicDamageHandle extends BaseDamageHandle implements IDamageHandle {

    public static var instance:MagicDamageHandle = new MagicDamageHandle();

    public function MagicDamageHandle() {
        super();
    }

    // 判断子弹是否为魔法伤害类型
    public function canHandle(bullet:Object):Boolean {
        return bullet.伤害类型 === "魔法";
    }

    public function handleBulletDamage(bullet:Object, shooter:Object, target:Object, manager:Object, result:DamageResult):Void {
        // ======= 本地化对象属性，降低解引用开销 =======
        var bulletMagicAttr:String = bullet.魔法伤害属性;
        var bulletPower:Number = bullet.破坏力;
        var targetResist:Object = target.魔法抗性;
        var targetLevel:Number = target.等级;

        // ======= 优化颜色与特效处理 =======
        var magicDamageColor:String = bullet.子弹敌我属性值 ? "#0099FF" : "#AC99FF";
        result.setDamageColor(magicDamageColor);

        var magicDamageAttr:String = bulletMagicAttr ? bulletMagicAttr : "能";
        result.addDamageEffect('<font color="' + magicDamageColor + '" size="20"> ' + magicDamageAttr + '</font>');

        // ======= 优化抗性计算 =======
        var enemyMagicResist:Number;

        if (bulletMagicAttr) {
            enemyMagicResist = (targetResist && (targetResist[bulletMagicAttr] || targetResist[bulletMagicAttr] === 0)) 
                               ? targetResist[bulletMagicAttr]
                               : (targetResist && (targetResist["基础"] || targetResist["基础"] === 0)) 
                                 ? targetResist["基础"]
                                 : 10 + (targetLevel >> 1);  // 用位运算代替除法
        } else {
            enemyMagicResist = (targetResist && (targetResist["基础"] || targetResist["基础"] === 0)) 
                               ? targetResist["基础"]
                               : 10 + (targetLevel >> 1);
        }

        // ======= 优化 isNaN + min/max 处理 =======
        enemyMagicResist = (enemyMagicResist != enemyMagicResist) 
                           ? 20 
                           : (enemyMagicResist < -1000 ? -1000 : (enemyMagicResist > 100 ? 100 : enemyMagicResist));

        // ======= 优化伤害计算（手动展开 Math.floor） =======
        var rawDamage:Number = bulletPower * (100 - enemyMagicResist) * 0.01;
        target.损伤值 = (rawDamage >= 0) ? (rawDamage | 0) : ((rawDamage == (rawDamage | 0)) ? rawDamage : ((rawDamage - 1) | 0));
    }

    public function toString():String {
        return "MagicDamageHandle";
    }
}
