import org.flashNight.arki.component.Damage.*;

class org.flashNight.arki.component.Damage.HandleNanoToxic extends BaseDamageHandle implements IDamageHandle {

    public function HandleNanoToxic() {
        super();
    }

    public override function execute(context:DamageContext):Void {
        var bullet:Object = context.bullet;
        var target:Object = context.hitTarget;
        var shooter:Object = context.shooter;
        var result:DamageResult = context.damageResult;

        var damageNumber:Number = target.损伤值;
        var poisonAmount:Number = 0;

        // 淬毒
        if (bullet.nanoToxic > 0) {
            poisonAmount = bullet.nanoToxic;
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

        // 吸血
        if (bullet.吸血 > 0 && target.损伤值 > 1) {
            var lifeStealAmount:Number = Math.floor(
                Math.max(
                    Math.min(target.损伤值 * bullet.吸血 / 100, target.hp), 
                    0
                )
            );
            shooter.hp += Math.min(lifeStealAmount, shooter.hp满血值 * 1.5 - shooter.hp);
            result.addDamageEffect(
                '<font color="#bb00aa" size="15"> 汲:' 
                + Math.floor(lifeStealAmount / result.actualScatterUsed).toString() 
                + "</font>"
            );
        }

        // 击溃
        if (bullet.击溃 > 0 && target.损伤值 > 1) {
            var crumbleAmount:Number = Math.floor(target.hp满血值 * bullet.击溃 / 100);
            bullet.附加层伤害计算 += crumbleAmount;
            if (target.hp满血值 > 0) {
                target.hp满血值 -= crumbleAmount;
                target.损伤值 += crumbleAmount;
            }
            result.addDamageEffect('<font color="#FF3333" size="20"> 溃</font>');
            damageNumber = Math.floor(target.损伤值);
        }

        // 斩杀
        if (bullet.斩杀) {
            if (target.hp < target.hp满血值 * bullet.斩杀 / 100) {
                target.损伤值 += target.hp; 
                target.hp = 0;
                var executeColor:String = bullet.子弹敌我属性值 ? '#4A0099' : '#660033';
                result.addDamageEffect('<font color="' + executeColor + '" size="20"> 斩</font>');
            }
            damageNumber = Math.floor(target.损伤值);
        }
    }
}
