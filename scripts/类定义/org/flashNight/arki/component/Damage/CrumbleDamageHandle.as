// File: org/flashNight/arki/component/Damage/CrumbleDamageHandle.as

import org.flashNight.arki.component.Damage.*;

class org.flashNight.arki.component.Damage.CrumbleDamageHandle extends BaseDamageHandle implements IDamageHandle {
    public static var instance:CrumbleDamageHandle = new CrumbleDamageHandle();

    public function CrumbleDamageHandle() {
        super();
    }

    // 判断子弹是否具有击溃属性
    public function canHandle(bullet:Object):Boolean {
        return (bullet.击溃 > 0);
    }

    public function handleBulletDamage(bullet:Object, shooter:Object, target:Object, manager:Object, result:DamageResult):Void {
        if (bullet.击溃 > 0 && target.损伤值 > 1) {
            var crumbleAmount:Number = (target.hp满血值 * bullet.击溃 / 100) >> 0;
            bullet.附加层伤害计算 += crumbleAmount;
            if (target.hp满血值 > 0) {
                target.hp满血值 -= crumbleAmount;
                target.损伤值 += crumbleAmount;
            }
            result.addDamageEffect('<font color="#FF3333" size="20"> 溃</font>');
        }
    }

    
    public function toString():String
    {
        return "CrumbleDamageHandle";
    }
}
