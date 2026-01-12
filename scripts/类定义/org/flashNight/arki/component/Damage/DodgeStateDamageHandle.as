import org.flashNight.arki.component.Damage.*;
import org.flashNight.arki.component.StatHandler.*;

/**
 * DodgeStateDamageHandle 类用于处理子弹伤害的躲闪状态。
 * 该类继承自 BaseDamageHandle 并实现了 IDamageHandle 接口。
 * 通过内联展开 Math.min、Math.max 和 Math.floor 等函数调用，提升性能。
 */
class org.flashNight.arki.component.Damage.DodgeStateDamageHandle extends BaseDamageHandle implements IDamageHandle {

    // 单例实例
    public static var instance:DodgeStateDamageHandle = new DodgeStateDamageHandle();

    /**
     * 构造函数。
     * 初始化时设置 skipCheck 为 true，表示始终处理躲闪状态。
     */
    public function DodgeStateDamageHandle() {
        this.skipCheck = true;
    }

    /**
     * 获取 DodgeStateDamageHandle 的单例实例。
     * 
     * - 若实例不存在，则创建一个新的 DodgeStateDamageHandle 实例并返回。
     * - 若实例已存在，则直接返回已创建的实例。
     * - 此方法通过闭包优化后续调用，避免多次判断，提升性能。
     * 
     * @return DodgeStateDamageHandle 单例实例
     */
    public static function getInstance():DodgeStateDamageHandle {
        if (instance == null) {
            instance = new DodgeStateDamageHandle();
            getInstance = function():DodgeStateDamageHandle {
                return instance;
            };
        }
        return instance;
    }

    /**
     * 判断是否有躲闪状态需要处理。
     * @param bullet 子弹对象
     * @return Boolean 始终返回 true，表示始终处理躲闪状态
     */
    public function canHandle(bullet:Object):Boolean {
        return true;
    }

    /**
     * 处理子弹伤害。
     * @param bullet 子弹对象
     * @param shooter 射击者对象
     * @param target 目标对象
     * @param manager 管理器对象
     * @param result 伤害结果对象
     */
    public function handleBulletDamage(bullet:Object, shooter:Object, target:Object, manager:Object, result:DamageResult):Void {
        var damageNumber:Number = target.损伤值;
        var damageSize:Number = result.damageSize;
        var dodgeState:String = manager.dodgeState;

        // 真伤无视闪避：直接执行取整和视觉效果，跳过闪避处理
        if (bullet.伤害类型 === "真伤") {
            damageNumber = (damageNumber > 1) ? (damageNumber | 0) : 1;
            target.损伤值 = damageNumber;
            _root.受击变红(120, target);
            if(target.受击反制){
                target.受击反制(damageNumber, bullet);
            }
            return;  // 早退，避免switch开销
        }

        // ==================== 联弹(霰弹值>0)的分段躲闪建模 ====================
        // 设计动机：联弹在物理上是一发子弹，但视觉/数值上需要接近"多发子弹命中"。
        // 旧实现：整串联弹共享一次 dodgeState（完全相关），会导致极端"全跳弹/全过穿"。
        // 新实现（方案B）：在 MultiShotDamageHandle 中按段抽样躲闪状态并汇总伤害，这里提前退出，避免重复处理。
        //
        // 注意：带受击反制(格挡)的单位依旧走旧逻辑，避免多次调用受击反制产生副作用与性能问题。
        #include "../macros/FLAG_CHAIN.as"
        // 躲闪系统已触发（包括懒闪避/直感）时做分段建模
        // INSTANT_FEEL（懒闪避）也需要参与分段建模，因为懒闪避本设计用于高伤害单发攻击，
        // 对于联弹应当将每段视为独立低伤害命中，而非整串高伤害命中
        // 使用查找表 O(1) 判断，替代 4 次字符串比较
        if (((bullet.flags & FLAG_CHAIN) != 0) && !target.受击反制
            && DodgeStatus.CHAIN_DODGE_MODEL[dodgeState]) {
            // 标记：本次命中将由联弹处理器执行分段躲闪建模
            result.deferChainDodgeState = true;
            return;
        }
        // ==================== 联弹分段建模结束 ====================

        switch (dodgeState) {
            case "跳弹":
                damageNumber = DamageResistanceHandler.bounceDamageCalculation(damageNumber, target.防御力);
                damageSize *= 0.5 + 0.5 * damageNumber / target.损伤值;
                target.损伤值 = damageNumber;
                var jumpDamageColor:String = bullet.是否为敌人 ? "#7F0000" : "#7F6A00";
                result.setDamageColor(jumpDamageColor);
                break;
            case "过穿":
                damageNumber = DamageResistanceHandler.penetrationDamageCalculation(damageNumber, target.防御力);
                damageSize *= 0.5 + 0.5 * damageNumber / target.损伤值;
                target.损伤值 = damageNumber;
                var pierceDamageColor:String = bullet.是否为敌人 ? "#FF7F7F" : "#FFE770";
                result.setDamageColor(pierceDamageColor);
                break;
            case "躲闪":
            case "直感":
                damageNumber = NaN;
                target.损伤值 = 0;
                damageSize *= 0.5;
                result.dodgeStatus = "MISS";
                break;
            case "格挡":
                damageNumber = target.受击反制(damageNumber, bullet);
                if (damageNumber) {
                    damageSize *= 0.5 + 0.5 * damageNumber / target.损伤值;
                    target.损伤值 = damageNumber;
                } else if (damageNumber === 0) {
                    target.损伤值 = 0;
                    damageSize *= 1.2;
                } else {
                    damageNumber = NaN;
                    target.损伤值 = 0;
                    damageSize *= 0.5;
                    result.dodgeStatus = "MISS";
                }
                break;
            default:
                // 内联展开 Math.max 和 Math.floor
                damageNumber = (damageNumber > 1) ? (damageNumber | 0) : 1; // 相当于 Math.max(Math.floor(damageNumber), 1)
                target.损伤值 = damageNumber;
                _root.受击变红(120, target);
                if(target.受击反制){
                    target.受击反制(damageNumber, bullet);
                }
        }

        result.damageSize = damageSize;
    }

    /**
     * 返回类的字符串表示。
     * @return String 类的名称
     */
    public function toString():String {
        return "DodgeStateDamageHandle";
    }
}
