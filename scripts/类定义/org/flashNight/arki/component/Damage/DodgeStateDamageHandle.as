
import org.flashNight.arki.component.Damage.*;

class org.flashNight.arki.component.Damage.DodgeStateDamageHandle extends BaseDamageHandle implements IDamageHandle {

    public static var instance:DodgeStateDamageHandle = new DodgeStateDamageHandle();

    public function DodgeStateDamageHandle() {
        super();
    }

    // 判断是否有躲闪状态需要处理
    public function canHandle(bullet:Object):Boolean {
        return (true); // 始终处理躲闪状态
    }

    public function handleBulletDamage(bullet:Object, shooter:Object, target:Object, manager:Object, result:DamageResult):Void {
        var damageNumber:Number = target.损伤值;
        var damageSize:Number = result.damageSize;
        var dodgeState:String = manager.dodgeState;

        switch (dodgeState) {
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
                    damageSize *= 0.3 + 0.7 * target.损伤值 / bullet.破坏力;
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
                damageNumber = Math.max(Math.floor(damageNumber), 1);
                target.损伤值 = damageNumber;
                _root.受击变红(120, target);
        }

        result.damageSize = damageSize;
    }

    public function toString():String
    {
        return "DodgeStateDamageHandle";
    }
}
