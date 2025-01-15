// File: org/flashNight/arki/component/Damage/ExecuteDamageHandle.as

import org.flashNight.arki.component.Damage.BaseDamageHandle;
import org.flashNight.arki.component.Damage.DamageResult;

class org.flashNight.arki.component.Damage.ExecuteDamageHandle extends BaseDamageHandle {

    public function ExecuteDamageHandle() {
        super();
    }

    public function handleBulletDamage(bullet:Object, shooter:Object, target:Object, manager:Object, result:DamageResult):Void {
        if (bullet.斩杀) {
            if (target.hp < target.hp满血值 * bullet.斩杀 / 100) {
                target.损伤值 += target.hp;
                target.hp = 0;
                var executeColor:String = bullet.子弹敌我属性值 ? '#4A0099' : '#660033';
                result.addDamageEffect('<font color="' + executeColor + '" size="20"> 斩</font>');
            }
        }
    }
}
