// File: org/flashNight/arki/component/Damage/BasicDamageHandle.as

import org.flashNight.arki.component.Damage.*;
import org.flashNight.arki.component.StatHandler.*;

class org.flashNight.arki.component.Damage.BasicDamageHandle extends BaseDamageHandle implements IDamageHandle {

    public static var instance:BasicDamageHandle = new BasicDamageHandle();

    public function BasicDamageHandle() {
        super();
    }

    /**
     * 获取 BasicDamageHandle 的单例实例。
     * 
     * - 若实例不存在，则创建一个新的 BasicDamageHandle 实例并返回。
     * - 若实例已存在，则直接返回已创建的实例。
     * - 此方法通过闭包优化后续调用，避免多次判断，提升性能。
     * 
     * @return BasicDamageHandle 单例实例
     */
    public static function getInstance():BasicDamageHandle {
        if (instance == null) {
            instance = new BasicDamageHandle();
            getInstance = function():BasicDamageHandle {
                return instance;
            };
        }
        return instance;
    }

    // 判断子弹是否为基础物理伤害类型
    public function canHandle(bullet:Object):Boolean {
        return (bullet.伤害类型 !== "真伤" && bullet.伤害类型 !== "魔法");
    }

    public function handleBulletDamage(bullet:Object, shooter:Object, target:Object, manager:Object, result:DamageResult):Void {
        target.损伤值 = bullet.破坏力 * DamageResistanceHandler.defenseDamageRatio(target.防御力);
    }

    
    public function toString():String
    {
        return "BasicDamageHandle";
    }
}
