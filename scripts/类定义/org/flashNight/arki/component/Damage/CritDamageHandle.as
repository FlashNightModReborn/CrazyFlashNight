// File: org/flashNight/arki/component/Damage/CritDamageHandle.as

import org.flashNight.arki.component.Damage.*;

/**
 * CritDamageHandle 类是用于处理暴击伤害的处理器。
 * 该类继承自 BaseDamageHandle 并实现了 IDamageHandle 接口。
 * 当子弹具有暴击属性时，该类会调整子弹的破坏力以反映暴击效果。
 */
class org.flashNight.arki.component.Damage.CritDamageHandle extends BaseDamageHandle implements IDamageHandle {

    // 单例实例
    public static var instance:CritDamageHandle = new CritDamageHandle();

    /**
     * 构造函数。
     * 调用父类构造函数以初始化基类。
     */
    public function CritDamageHandle() {
        super();
    }

    /**
     * 获取 CritDamageHandle 的单例实例。
     * 
     * - 若实例不存在，则创建一个新的 CritDamageHandle 实例并返回。
     * - 若实例已存在，则直接返回已创建的实例。
     * - 此方法通过闭包优化后续调用，避免多次判断，提升性能。
     * 
     * @return CritDamageHandle 单例实例
     */
    public static function getInstance():CritDamageHandle {
        if (instance == null) {
            instance = new CritDamageHandle();
            getInstance = function():CritDamageHandle {
                return instance;
            };
        }
        return instance;
    }


    /**
     * 判断子弹是否具有暴击属性。
     * 如果子弹对象包含暴击属性（bullet.暴击 != null），则返回 true。
     *
     * @param bullet 子弹对象
     * @return Boolean 如果子弹具有暴击属性则返回 true，否则返回 false
     */
    public function canHandle(bullet:Object):Boolean {
        return (bullet.暴击 != null);
    }

    /**
     * 处理暴击伤害。
     * 根据子弹的暴击属性调整子弹的破坏力。
     *
     * @param bullet 子弹对象
     * @param shooter 射击者对象
     * @param target 目标对象
     * @param manager 管理器对象
     * @param result 伤害结果对象
     */
    public function handleBulletDamage(bullet:Object, shooter:Object, target:Object, manager:Object, result:DamageResult):Void {
        // 调整子弹的破坏力以反映暴击效果
        bullet.破坏力 *= bullet.暴击(bullet);
    }

    /**
     * 返回类的字符串表示。
     *
     * @return String 类的名称
     */
    public function toString():String {
        return "CritDamageHandle";
    }
}