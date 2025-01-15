// File: org/flashNight/arki/component/Damage/CritDamageHandle.as

import org.flashNight.arki.component.Damage.BaseDamageHandle;
import org.flashNight.arki.component.Damage.DamageResult;

class org.flashNight.arki.component.Damage.CritDamageHandle extends BaseDamageHandle {

    public function CritDamageHandle() {
        super();
    }

    public function handleBulletDamage(bullet:Object, shooter:Object, target:Object, manager:Object, result:DamageResult):Void {
        // 如果有暴击属性，就进行暴击计算
        if (bullet.暴击) {
            bullet.破坏力 = bullet.破坏力 * bullet.暴击(bullet);
        }
    }
}
