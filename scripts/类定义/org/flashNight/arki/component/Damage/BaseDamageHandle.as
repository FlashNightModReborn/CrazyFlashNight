// File: org/flashNight/arki/component/Damage/BaseDamageHandle.as

import org.flashNight.arki.component.Damage.*;
class org.flashNight.arki.component.Damage.BaseDamageHandle implements IDamageHandle {

    public function BaseDamageHandle() {
        // 构造函数
    }

    // 默认实现：不处理任何子弹
    public function canHandle(bullet:Object):Boolean {
        return false;
    }

    // 默认空实现，子类需重写
    public function handleBulletDamage(bullet:Object, shooter:Object, target:Object, manager:Object, result:DamageResult):Void {
        // do nothing by default
    }

    public function toString():String
    {
        return "BaseDamageHandle";
    }
}
