// File: org/flashNight/arki/component/Damage/BasicDamageHandle.as

import org.flashNight.arki.component.Damage.BaseDamageHandle;
import org.flashNight.arki.component.Damage.DamageResult;

class org.flashNight.arki.component.Damage.BasicDamageHandle extends BaseDamageHandle {

    public function BasicDamageHandle() {
        super();
    }

    public function handleBulletDamage(bullet:Object, shooter:Object, target:Object, manager:Object, result:DamageResult):Void {
        // 仅当伤害类型不是 真伤、魔法 时，视为普通物理
        if (bullet.伤害类型 !== "真伤" && bullet.伤害类型 !== "魔法") {
            target.损伤值 = bullet.破坏力 * _root.防御减伤比(target.防御力);
        }
    }
}
