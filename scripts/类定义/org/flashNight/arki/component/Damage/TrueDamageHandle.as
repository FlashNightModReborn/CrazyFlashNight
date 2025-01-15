// File: org/flashNight/arki/component/Damage/TrueDamageHandle.as

import org.flashNight.arki.component.Damage.BaseDamageHandle;
import org.flashNight.arki.component.Damage.DamageResult;

class org.flashNight.arki.component.Damage.TrueDamageHandle extends BaseDamageHandle {

    public function TrueDamageHandle() {
        super();
    }

    public function handleBulletDamage(bullet:Object, shooter:Object, target:Object, manager:Object, result:DamageResult):Void {
        if (bullet.伤害类型 === "真伤") {
            var trueDamageColor:String = bullet.子弹敌我属性值 ? "#4A0099" : "#660033";
            result.setDamageColor(trueDamageColor);
            result.addDamageEffect('<font color="' + trueDamageColor + '" size="20"> 真</font>');
            target.损伤值 = bullet.破坏力;
        }
    }
}
