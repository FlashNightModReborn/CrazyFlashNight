// File: org/flashNight/arki/component/Damage/CrumbleDamageHandle.as

import org.flashNight.arki.component.Damage.*;

/**
 * CrumbleDamageHandle 类是用于处理击溃伤害的处理器。
 * 该类继承自 BaseDamageHandle 并实现了 IDamageHandle 接口。
 * 当子弹具有击溃属性时，该类会根据击溃比例对目标造成额外伤害，并减少目标的满血值。
 */
class org.flashNight.arki.component.Damage.CrumbleDamageHandle extends BaseDamageHandle implements IDamageHandle {

    // 单例实例
    public static var instance:CrumbleDamageHandle = new CrumbleDamageHandle();

    /**
     * 构造函数。
     * 调用父类构造函数以初始化基类。
     */
    public function CrumbleDamageHandle() {
        super();
    }

    /**
     * 获取 CrumbleDamageHandle 的单例实例。
     * 
     * - 若实例不存在，则创建一个新的 CrumbleDamageHandle 实例并返回。
     * - 若实例已存在，则直接返回已创建的实例。
     * - 此方法通过闭包优化后续调用，避免多次判断，提升性能。
     * 
     * @return CrumbleDamageHandle 单例实例
     */
    public static function getInstance():CrumbleDamageHandle {
        if (instance == null) {
            instance = new CrumbleDamageHandle();
            getInstance = function():CrumbleDamageHandle {
                return instance;
            };
        }
        return instance;
    }

    /**
     * 判断子弹是否具有击溃属性。
     * 如果子弹的击溃属性值大于 0，则返回 true。
     *
     * @param bullet 子弹对象
     * @return Boolean 如果子弹具有击溃属性则返回 true，否则返回 false
     */
    public function canHandle(bullet:Object):Boolean {
        return (bullet.击溃 > 0);
    }

    /**
     * 处理击溃伤害。
     * 根据子弹的击溃属性对目标造成额外伤害，并减少目标的满血值。
     *
     * @param bullet 子弹对象
     * @param shooter 射击者对象
     * @param target 目标对象
     * @param manager 管理器对象
     * @param result 伤害结果对象
     */
    public function handleBulletDamage(bullet:Object, shooter:Object, target:Object, manager:Object, result:DamageResult):Void {
        // 检查子弹是否具有击溃属性且目标的损伤值大于 1
        if (bullet.击溃 > 0 && target.损伤值 > 1) {
            // 计算击溃伤害值（基于目标的满血值和子弹的击溃比例）
            var crumbleAmount:Number = (target.hp满血值 * bullet.击溃 / 100) >> 0; // 使用位运算取整

            // 将击溃伤害添加到子弹的额外效果伤害中
            bullet.additionalEffectDamage += crumbleAmount;

            // 如果目标的满血值大于 0，则减少满血值并增加损伤值
            if (target.hp满血值 > 0) {
                target.hp满血值 -= crumbleAmount;
                target.损伤值 += crumbleAmount;
            }

            // 在伤害结果中添加击溃效果的视觉提示
            result.addDamageEffect('<font color="#FF3333" size="20"> 溃</font>');
        }
    }

    /**
     * 返回类的字符串表示。
     *
     * @return String 类的名称
     */
    public function toString():String {
        return "CrumbleDamageHandle";
    }
}