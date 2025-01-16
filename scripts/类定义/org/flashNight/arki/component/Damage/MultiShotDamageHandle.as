// File: org/flashNight/arki/component/Damage/MultiShotDamageHandle.as

import org.flashNight.arki.component.Damage.BaseDamageHandle;
import org.flashNight.arki.component.Damage.DamageResult;

class org.flashNight.arki.component.Damage.MultiShotDamageHandle extends BaseDamageHandle implements IDamageHandle {
    public static var instance:MultiShotDamageHandle = new MultiShotDamageHandle();

    public function MultiShotDamageHandle() {
        super();
    }

    // 判断是否有联弹检测并且不穿刺
    public function canHandle(bullet:Object):Boolean {
        return (bullet.联弹检测 && !bullet.穿刺检测);
    }

    public function handleBulletDamage(bullet:Object, shooter:Object, target:Object, manager:Object, result:DamageResult):Void {
        var overlapRatio:Number = manager.overlapRatio;
        var actualScatterUsed:Number = Math.min(
            bullet.霰弹值,
            Math.ceil(
                Math.min(
                    bullet.最小霰弹值 + overlapRatio * ((bullet.霰弹值 - bullet.最小霰弹值) + 1) * 1.2,
                    target.hp / (target.损伤值 > 0 ? target.损伤值 : 1)
                )
            )
        );
        result.actualScatterUsed = actualScatterUsed;

        bullet.霰弹值 -= actualScatterUsed;
        result.finalScatterValue = bullet.霰弹值;

        // 乘以实际消耗霰弹值
        target.损伤值 *= actualScatterUsed;
    }

    public function toString():Void
    {
        return "MultiShotDamageHandle";
    }
}
