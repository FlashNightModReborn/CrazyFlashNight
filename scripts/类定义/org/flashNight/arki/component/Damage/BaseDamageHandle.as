// File: org/flashNight/arki/component/Damage/BaseDamageHandle.as

import org.flashNight.arki.component.Damage.*;

/**
 * BaseDamageHandle 类是伤害处理器的基类。
 * 该类实现了 IDamageHandle 接口，提供了默认的伤害处理逻辑。
 * 子类可以通过重写方法来实现特定的伤害处理行为。
 */
class org.flashNight.arki.component.Damage.BaseDamageHandle implements IDamageHandle {

    /**
     * skipCheck 属性用于指示是否跳过伤害处理的检查。
     * 如果为 true，则始终处理伤害；如果为 false，则根据 canHandle 方法的返回值决定是否处理。
     */
    public var skipCheck:Boolean = false;
    public static var instance:BaseDamageHandle = new BaseDamageHandle();

    /**
     * 构造函数。
     * @param skipCheck 一个布尔值，指示是否跳过伤害处理的检查。如果没有传入参数，则默认为 true。
     */
    public function BaseDamageHandle(skipCheck:Boolean /*默认值为 true*/) {
        // 如果没有传入参数，则 skipCheck 默认为 true
        this.skipCheck = (skipCheck == undefined) ? false : skipCheck;
    }

    /**
     * 获取 BaseDamageHandle 的单例实例。
     * 
     * - 若实例不存在，则创建一个新的 BaseDamageHandle 实例并返回。
     * - 若实例已存在，则直接返回已创建的实例。
     * - 此方法通过闭包优化后续调用，避免多次判断，提升性能。
     * 
     * @return BaseDamageHandle 单例实例
     */
    public static function getInstance():BaseDamageHandle {
        if (instance == null) {
            instance = new BaseDamageHandle();
            getInstance = function():BaseDamageHandle {
                return instance;
            };
        }
        return instance;
    }

    /**
     * 判断是否能够处理指定的子弹。
     * 默认实现返回 false，表示不处理任何子弹。
     * 子类可以重写此方法以实现特定的处理逻辑。
     *
     * @param bullet 子弹对象
     * @return Boolean 如果能够处理子弹则返回 true，否则返回 false
     */
    public function canHandle(bullet:Object):Boolean {
        return false;
    }

    /**
     * 处理子弹伤害。
     * 默认实现为空，子类需重写此方法以实现具体的伤害处理逻辑。
     *
     * @param bullet 子弹对象
     * @param shooter 射击者对象
     * @param target 目标对象
     * @param manager 管理器对象
     * @param result 伤害结果对象
     */
    public function handleBulletDamage(bullet:Object, shooter:Object, target:Object, manager:Object, result:DamageResult):Void {
        // 默认空实现，子类需重写
    }

    /**
     * 返回类的字符串表示。
     *
     * @return String 类的名称
     */
    public function toString():String {
        return "BaseDamageHandle";
    }
}