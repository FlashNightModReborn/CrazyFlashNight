// File: org/flashNight/arki/component/Damage/CritDamageHandle.as

import org.flashNight.arki.component.Damage.BaseDamageHandle;
import org.flashNight.arki.component.Damage.DamageResult;

class org.flashNight.arki.component.Damage.CritDamageHandle extends BaseDamageHandle implements IDamageHandle {

    public static var instance:CritDamageHandle = new CritDamageHandle();

    public function CritDamageHandle() {
        super();
    }

    // 判断子弹是否具有暴击属性
    public function canHandle(bullet:Object):Boolean {
        return (bullet.暴击 != null);
    }

    public function handleBulletDamage(bullet:Object, shooter:Object, target:Object, manager:Object, result:DamageResult):Void {
        bullet.破坏力 = bullet.破坏力 * bullet.暴击(bullet);
    }

    
    public function toString():Void
    {
        return "CritDamageHandle";
    }
}
