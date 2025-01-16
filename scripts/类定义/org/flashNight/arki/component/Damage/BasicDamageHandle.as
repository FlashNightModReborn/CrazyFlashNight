// File: org/flashNight/arki/component/Damage/BasicDamageHandle.as

import org.flashNight.arki.component.Damage.*;
import org.flashNight.arki.component.StatHandler.*;

class org.flashNight.arki.component.Damage.BasicDamageHandle extends BaseDamageHandle implements IDamageHandle {

    public static var instance:BasicDamageHandle = new BasicDamageHandle();

    public function BasicDamageHandle() {
        super();
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
