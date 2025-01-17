import org.flashNight.arki.component.Damage.*;
import org.flashNight.arki.component.StatHandler.*;

/**
 * UniversalDamageHandle 类是用于处理通用伤害的处理器。
 * - 支持多种伤害类型，包括真实伤害、魔法伤害和基础伤害。
 * - 根据伤害类型计算最终伤害，并设置伤害颜色和效果。
 * - 通过位运算和条件运算符优化性能。
 */
class org.flashNight.arki.component.Damage.UniversalDamageHandle extends BaseDamageHandle implements IDamageHandle {

    // ========== 单例实例 ==========

    /** 单例实例 */
    public static var instance:UniversalDamageHandle = new UniversalDamageHandle();

    // ========== 构造函数 ==========

    /**
     * 构造函数。
     * 初始化时设置 skipCheck 为 true，表示始终处理伤害。
     */
    public function UniversalDamageHandle() {
        this.skipCheck = true;
    }

    /**
     * 获取 UniversalDamageHandle 的单例实例。
     * 
     * - 若实例不存在，则创建一个新的 UniversalDamageHandle 实例并返回。
     * - 若实例已存在，则直接返回已创建的实例。
     * - 此方法通过闭包优化后续调用，避免多次判断，提升性能。
     * 
     * @return UniversalDamageHandle 单例实例
     */
    public static function getInstance():UniversalDamageHandle {
        if (instance == null) {
            instance = new UniversalDamageHandle();
            getInstance = function():UniversalDamageHandle {
                return instance;
            };
        }
        return instance;
    }

    // ========== 公共方法 ==========

    /**
     * 判断是否能够处理指定的子弹。
     * - 始终返回 true，表示该类可以处理所有子弹。
     *
     * @param bullet 子弹对象
     * @return Boolean 始终返回 true
     */
    public function canHandle(bullet:Object):Boolean {
        return true;
    }

    /**
     * 处理通用伤害。
     * - 根据子弹的伤害类型，计算最终伤害并设置伤害颜色和效果。
     * - 支持真实伤害、魔法伤害和基础伤害。
     *
     * @param bullet  子弹对象
     * @param shooter 射击者对象
     * @param target  目标对象
     * @param manager 管理器对象
     * @param result  伤害结果对象
     */
    public function handleBulletDamage(bullet:Object, shooter:Object, target:Object, manager:Object, result:DamageResult):Void {
        var damageType:String = bullet.伤害类型;  // 本地化伤害类型
        var bulletPower:Number = bullet.破坏力;  // 本地化破坏力
        var damageColor:String;
        var damageEffect:String;
        var finalDamage:Number;

        // 根据伤害类型分支处理
        switch (damageType) {
            case "真伤":  // 真实伤害，直接造成伤害
                damageColor = bullet.子弹敌我属性值 ? "#4A0099" : "#660033";
                damageEffect = '<font color="' + damageColor + '" size="20"> 真</font>';
                finalDamage = bulletPower;
                break;

            case "魔法":  // 魔法伤害，计算魔法抗性
                var bulletMagicAttr:String = bullet.魔法伤害属性;
                var targetResist:Object = target.魔法抗性;
                var targetLevel:Number = target.等级;

                damageColor = bullet.子弹敌我属性值 ? "#0099FF" : "#AC99FF";
                damageEffect = '<font color="' + damageColor + '" size="20"> ' + (bulletMagicAttr ? bulletMagicAttr : "能") + '</font>';

                // 计算魔法抗性
                var enemyMagicResist:Number = (bulletMagicAttr && targetResist && (targetResist[bulletMagicAttr] || targetResist[bulletMagicAttr] === 0))
                    ? targetResist[bulletMagicAttr]
                    : (targetResist && (targetResist["基础"] || targetResist["基础"] === 0))
                        ? targetResist["基础"]
                        : 10 + (targetLevel >> 1);  // 位运算优化除法

                // isNaN检查与范围限制
                enemyMagicResist = (enemyMagicResist != enemyMagicResist) 
                    ? 20 
                    : (enemyMagicResist < -1000 ? -1000 : (enemyMagicResist > 100 ? 100 : enemyMagicResist));

                finalDamage = bulletPower * (100 - enemyMagicResist) * 0.01;
                finalDamage = (finalDamage >= 0) ? (finalDamage | 0) : ((finalDamage == (finalDamage | 0)) ? finalDamage : ((finalDamage - 1) | 0));
                break;

            default:  // 基础伤害，计算防御减伤
                damageColor = bullet.子弹敌我属性值 ? "#FF9900" : "#FF6666";
                damageEffect = '<font color="' + damageColor + '" size="20"> 物</font>';
                finalDamage = bulletPower * DamageResistanceHandler.defenseDamageRatio(target.防御力);
                break;
        }

        // 设置伤害颜色和效果
        result.setDamageColor(damageColor);
        result.addDamageEffect(damageEffect);

        // 应用伤害
        target.损伤值 = finalDamage;
    }

    /**
     * 返回类的字符串表示。
     *
     * @return String 类的名称
     */
    public function toString():String {
        return "UniversalDamageHandle";
    }
}