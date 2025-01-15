import org.flashNight.arki.component.Damage.*;

class org.flashNight.arki.component.Damage.HandleFinalize extends BaseDamageHandle implements IDamageHandle {

    public function HandleFinalize() {
        super();
    }

    public override function execute(context:DamageContext):Void {
        var target:Object = context.hitTarget;
        var bullet:Object = context.bullet;
        var result:DamageResult = context.damageResult;

        // 分段伤害逻辑
        var damageNumber:Number = target.损伤值;
        var remainingDamage:Number = damageNumber;
        var scatterUsed:Number = result.actualScatterUsed;

        result.displayCount = scatterUsed;

        if (scatterUsed > 1) {
            for (var i:Number = 0; i < scatterUsed - 1; i++) {
                var fluctuatedDamage:Number = (remainingDamage / (scatterUsed - i)) 
                    * (100 + _root.随机偏移(50 / scatterUsed)) 
                    / 100;
                fluctuatedDamage = isNaN(fluctuatedDamage) ? 0 : fluctuatedDamage;
                result.addDamageValue(Math.floor(fluctuatedDamage));
                remainingDamage -= fluctuatedDamage;
            }
        }
        result.addDamageValue(isNaN(remainingDamage) ? 0 : Math.floor(remainingDamage));

        // 扣血
        target.hp = isNaN(target.损伤值) 
                  ? target.hp 
                  : Math.floor(target.hp - target.损伤值);
        target.hp = (target.hp < 0 || isNaN(target.hp)) ? 0 : target.hp;
    }
}
