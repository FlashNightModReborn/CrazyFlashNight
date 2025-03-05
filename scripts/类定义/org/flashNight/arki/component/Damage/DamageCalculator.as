import org.flashNight.arki.component.Damage.*;

class org.flashNight.arki.component.Damage.DamageCalculator {

    public static function calculateDamage(bullet, shooter, hitTarget, overlapRatio, dodgeState):DamageResult {
        var manager:DamageManager = bullet.damageManager;

        manager.overlapRatio = overlapRatio;
        manager.dodgeState = dodgeState;

        if (hitTarget.无敌 || hitTarget.man.无敌标签 || hitTarget.NPC) {
            return DamageResult.NULL; 
        }

        if (hitTarget.hp == 0) {
            return DamageResult.NULL;
        }

        var damageResult:DamageResult = DamageResult.getIMPACT();
        if(isNaN(hitTarget.防御力)) hitTarget.防御力 = 1;

        bullet.破坏力 = Number(bullet.子弹威力) + (isNaN(shooter.伤害加成) ? 0 : shooter.伤害加成);
        
        var damageVariance:Number = bullet.破坏力 * ((!_root.调试模式 || bullet.霰弹值 > 1) ? (0.85 + _root.basic_random() * 0.3) : 1);
        var percentageDamage:Number = isNaN(bullet.百分比伤害) ? 0 : hitTarget.hp * bullet.百分比伤害 / 100;
        bullet.破坏力 = damageVariance + bullet.固伤 + percentageDamage;

        manager.execute(bullet, shooter, hitTarget, damageResult);
        damageResult.calculateScatterDamage(hitTarget.损伤值);
        
        hitTarget.hp = isNaN(hitTarget.损伤值) ? hitTarget.hp : Math.floor(hitTarget.hp - hitTarget.损伤值);
        hitTarget.hp = (hitTarget.hp < 0 || isNaN(hitTarget.hp)) ? 0 : hitTarget.hp;

        return damageResult;
    }
}
