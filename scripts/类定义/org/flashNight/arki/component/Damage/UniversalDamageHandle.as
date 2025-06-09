import org.flashNight.arki.component.Damage.*;
import org.flashNight.arki.component.StatHandler.*;

/**
 * UniversalDamageHandle 类用于处理通用伤害以及躲闪状态的处理器。
 * - 完全复制原有脚本的逻辑，确保功能一致。
 * - 后续可进行优化，如减少重复代码、提高性能等。
 */
class org.flashNight.arki.component.Damage.UniversalDamageHandle extends BaseDamageHandle implements IDamageHandle {

    // ========== 单例实例 ==========
    public static var instance:UniversalDamageHandle = new UniversalDamageHandle();

    /**
     * 构造函数。
     * 初始化时设置 skipCheck 为 true，表示始终处理伤害和躲闪状态。
     */
    public function UniversalDamageHandle() {
        this.skipCheck = true;
    }

    /**
     * 获取 UniversalDamageHandle 的单例实例 (闭包优化)。
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

    /**
     * 始终返回 true，表示可处理所有子弹。
     */
    public function canHandle(bullet:Object):Boolean {
        return true;
    }

    /**
     * 处理子弹伤害（含通用伤害）。
     *
     * @param bullet  子弹对象
     * @param shooter 射击者对象
     * @param target  目标对象
     * @param manager 管理器对象 (其中包含 dodgeState)
     * @param result  伤害结果对象 (其中包含 damageSize 等)
     */
    public function handleBulletDamage(bullet:Object, shooter:Object, target:Object, manager:Object, result:DamageResult):Void {

        var defaultDamageColor:String = bullet.是否为敌人 ? "#FF0000" : "#FFCC00";
        result.setDamageColor(defaultDamageColor);
        
        if (bullet.伤害类型 === "真伤") {
            var trueDamageColor:String = bullet.是否为敌人 ? "#660033" : "#4A0099";
            result.setDamageColor(trueDamageColor);
            result.addDamageEffect('<font color="' + trueDamageColor + '" size="20"> 真</font>');
            target.损伤值 = bullet.破坏力;
        } else if (bullet.伤害类型 === "魔法") {
            var magicDamageColor:String = bullet.是否为敌人 ? "#AC99FF" : "#0099FF";
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
        } else {
            target.损伤值 = bullet.破坏力 * DamageResistanceHandler.defenseDamageRatio(target.防御力);
        }
    }

    public function toString():String {
        return "UniversalDamageHandle";
    }
}
