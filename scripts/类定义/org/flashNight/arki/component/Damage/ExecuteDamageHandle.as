
import org.flashNight.arki.component.Damage.*;

class org.flashNight.arki.component.Damage.ExecuteDamageHandle extends BaseDamageHandle implements IDamageHandle {

    public static var instance:ExecuteDamageHandle = new ExecuteDamageHandle();

    public function ExecuteDamageHandle() {
        super();
    }

    // 判断子弹是否具有斩杀属性
    public function canHandle(bullet:Object):Boolean {
        return (bullet.斩杀 != null);
    }

    public function handleBulletDamage(bullet:Object, shooter:Object, target:Object, manager:Object, result:DamageResult):Void {
        if (target.hp < target.hp满血值 * bullet.斩杀 / 100) {
            target.损伤值 += target.hp;
            target.hp = 0;
            var executeColor:String = bullet.子弹敌我属性值 ? '#4A0099' : '#660033';
            result.addDamageEffect('<font color="' + executeColor + '" size="20"> 斩</font>');
        }
    }

    public function toString():String
    {
        return "ExecuteDamageHandle";
    }
}
