import org.flashNight.arki.component.Damage.*;

class org.flashNight.arki.component.Damage.HandleScatter extends BaseDamageHandle implements IDamageHandle {
    
    public function HandleScatter() {
        super();
    }

    public override function execute(context:DamageContext):Void {
        var bullet:Object = context.bullet;
        var target:Object = context.hitTarget;
        var overlapRatio:Number = context.overlapRatio;
        var result:DamageResult = context.damageResult;

        var damageNumber:Number = target.损伤值;

        // 计算实际消耗霰弹值
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

        // 更新子弹霰弹值
        if (bullet.联弹检测 && !bullet.穿刺检测) {
            bullet.霰弹值 -= actualScatterUsed;
            result.finalScatterValue = bullet.霰弹值;
        }

        // 乘以实际消耗
        target.损伤值 *= actualScatterUsed;
        damageNumber *= actualScatterUsed;
    }
}
