// File: org/flashNight/arki/component/Damage/PoisonDamageHandle.as

import org.flashNight.arki.component.Damage.BaseDamageHandle;
import org.flashNight.arki.component.Damage.DamageResult;

class org.flashNight.arki.component.Damage.nanoToxicDamageHandle extends BaseDamageHandle implements IDamageHandle {
    public static var instance:nanoToxicDamageHandle = new nanoToxicDamageHandle();
    
    public function nanoToxicDamageHandle() {
        super();
    }

    // 判断子弹是否具有毒属性
    public function canHandle(bullet:Object):Boolean {
        return (bullet.nanoToxic > 0);
    }

    public function handleBulletDamage(bullet:Object, shooter:Object, target:Object, manager:Object, result:DamageResult):Void {
        var damageNumber:Number = target.损伤值;
        var nanoToxicAmount:Number = 0;

        if (bullet.nanoToxic > 0) {
            nanoToxicAmount = bullet.nanoToxic;
            // 普通检测？
            if (bullet.普通检测) {
                nanoToxicAmount *= 1;
            } else {
                nanoToxicAmount *= 0.3;
            }
            bullet.附加层伤害计算 += nanoToxicAmount;
        }

        if (nanoToxicAmount > 0 && !isNaN(damageNumber) && damageNumber > 0) {
            target.损伤值 += nanoToxicAmount;
            damageNumber = target.损伤值;
            result.addDamageEffect('<font color="#66dd00" size="20"> 毒</font>');

            if (bullet.nanoToxicDecay && bullet.近战检测 && shooter.淬毒 > 10) {
                shooter.淬毒 -= bullet.nanoToxicDecay;
            }
            if (target.毒返 > 0) {
                var nanoToxicReturnAmount:Number = nanoToxicAmount * target.毒返;
                if (target.毒返函数) {
                    target.毒返函数(nanoToxicAmount, nanoToxicReturnAmount);
                }
                target.淬毒 = nanoToxicReturnAmount;
            }
        }
    }
}
