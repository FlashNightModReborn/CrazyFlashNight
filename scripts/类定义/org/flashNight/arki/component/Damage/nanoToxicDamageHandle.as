// File: org/flashNight/arki/component/Damage/PoisonDamageHandle.as

import org.flashNight.arki.component.Damage.BaseDamageHandle;
import org.flashNight.arki.component.Damage.DamageResult;

class org.flashNight.arki.component.Damage.nanoToxicDamageHandle extends BaseDamageHandle {

    public function nanoToxicDamageHandle() {
        super();
    }

    public function handleBulletDamage(bullet:Object, shooter:Object, target:Object, manager:Object, result:DamageResult):Void {
        var damageNumber:Number = target.损伤值;
        var poisonAmount:Number = 0;

        if (bullet.nanoToxic > 0) {
            poisonAmount = bullet.nanoToxic;
            // 普通检测？
            if (bullet.普通检测) {
                poisonAmount *= 1;
            } else {
                poisonAmount *= 0.3;
            }
            bullet.附加层伤害计算 += poisonAmount;
        }

        if (poisonAmount > 0 && !isNaN(damageNumber) && damageNumber > 0) {
            target.损伤值 += poisonAmount;
            damageNumber = target.损伤值;
            result.addDamageEffect('<font color="#66dd00" size="20"> 毒</font>');

            if (bullet.nanoToxicDecay && bullet.近战检测 && shooter.淬毒 > 10) {
                shooter.淬毒 -= bullet.nanoToxicDecay;
            }
            if (target.毒返 > 0) {
                var poisonReturnAmount:Number = poisonAmount * target.毒返;
                if (target.毒返函数) {
                    target.毒返函数(poisonAmount, poisonReturnAmount);
                }
                target.淬毒 = poisonReturnAmount;
            }
        }
    }
}
