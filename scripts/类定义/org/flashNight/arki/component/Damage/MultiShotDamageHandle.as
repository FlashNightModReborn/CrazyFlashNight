// File: org/flashNight/arki/component/Damage/MultiShotDamageHandle.as

import org.flashNight.arki.component.Damage.BaseDamageHandle;
import org.flashNight.arki.component.Damage.DamageResult;

class org.flashNight.arki.component.Damage.MultiShotDamageHandle extends BaseDamageHandle {

    public function MultiShotDamageHandle() {
        super();
    }

    public function handleBulletDamage(bullet:Object, shooter:Object, target:Object, manager:Object, result:DamageResult):Void {
        
        // 计算实际消耗霰弹值
        var actualScatterUsed:Number = Math.min(
            bullet.霰弹值,
            Math.ceil(
                Math.min(
                    bullet.最小霰弹值 + manager["overlapRatio"] * ((bullet.霰弹值 - bullet.最小霰弹值) + 1) * 1.2,
                    target.hp / (target.损伤值 > 0 ? target.损伤值 : 1)
                )
            )
        );
        result.actualScatterUsed = actualScatterUsed;

        if (bullet.联弹检测 && !bullet.穿刺检测) {
            bullet.霰弹值 -= actualScatterUsed;
            result.finalScatterValue = bullet.霰弹值;
        }

        // 对  target.损伤值 * actualScatterUsed
        target.损伤值 *= actualScatterUsed;
    }
}
