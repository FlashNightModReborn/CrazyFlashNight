
import org.flashNight.arki.component.Damage.*;


class org.flashNight.arki.component.Damage.LifeStealDamageHandle extends BaseDamageHandle implements IDamageHandle {
    
    public static var instance:LifeStealDamageHandle = new LifeStealDamageHandle();

    public function LifeStealDamageHandle() {
        super();
    }

    // 判断子弹是否具有吸血属性
    public function canHandle(bullet:Object):Boolean {
        return (bullet.吸血 > 0);
    }

    public function handleBulletDamage(bullet:Object, shooter:Object, target:Object, manager:Object, result:DamageResult):Void {
        if (target.损伤值 > 1) {
            var actualScatterUsed:Number = result.actualScatterUsed;
            var lifeStealAmount:Number = Math.floor(
                Math.max(
                    Math.min(target.损伤值 * bullet.吸血 / 100, target.hp), 
                    0
                )
            );
            shooter.hp += Math.min(lifeStealAmount, shooter.hp满血值 * 1.5 - shooter.hp);
            result.addDamageEffect(
                '<font color="#bb00aa" size="15"> 汲:' + Math.floor(lifeStealAmount / actualScatterUsed).toString() + "</font>"
            );
        }
    }
    
    public function toString():String
    {
        return "LifeStealDamageHandle";
    }
}
