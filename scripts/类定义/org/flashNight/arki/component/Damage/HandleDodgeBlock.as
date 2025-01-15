import org.flashNight.arki.component.Damage.*;

class org.flashNight.arki.component.Damage.HandleDodgeBlock extends BaseDamageHandle implements IDamageHandle {

    public function HandleDodgeBlock() {
        super();
    }

    public override function execute(context:DamageContext):Void {
        var bullet:Object = context.bullet;
        var target:Object = context.hitTarget;
        var dodge:String = context.dodgeState;
        var result:DamageResult = context.damageResult;

        var damageNumber:Number = target.损伤值;
        var damageSize:Number = result.damageSize;

        switch (dodge) {
            case "跳弹":
                damageNumber = _root.跳弹伤害计算(damageNumber, target.防御力);
                target.损伤值 = damageNumber;
                damageSize *= 0.3 + 0.7 * damageNumber / bullet.破坏力;
                var jumpDamageColor:String = bullet.子弹敌我属性值 ? "#7F6A00" : "#7F0000";
                result.setDamageColor(jumpDamageColor);
                break;
            case "过穿":
                damageNumber = _root.过穿伤害计算(damageNumber, target.防御力);
                target.损伤值 = damageNumber;
                damageSize *= 0.3 + 0.7 * damageNumber / bullet.破坏力;
                var pierceDamageColor:String = bullet.子弹敌我属性值 ? "#FFE770" : "#FF7F7F";
                result.setDamageColor(pierceDamageColor);
                break;
            case "躲闪":
            case "直感":
                damageNumber = NaN;
                target.损伤值 = 0;
                damageSize *= 0.5;
                result.dodgeStatus = "MISS";
                break;
            case "格挡":
                damageNumber = target.受击反制(damageNumber, bullet);
                if (damageNumber) {
                    target.损伤值 = damageNumber;
                    damageSize *= 0.3 + 0.7 * damageNumber / bullet.破坏力;
                } else if (damageNumber === 0) {
                    target.损伤值 = 0;
                    damageSize *= 1.2;
                } else {
                    damageNumber = NaN;
                    target.损伤值 = 0;
                    damageSize *= 0.5;
                    result.dodgeStatus = "MISS";
                }
                break;
            default:
                // 正常伤害
                damageNumber = Math.max(Math.floor(damageNumber), 1);
                target.损伤值 = damageNumber;
                _root.受击变红(120, target);
        }

        result.damageSize = damageSize;
    }
}
