
import org.flashNight.arki.component.Damage.*;


class org.flashNight.arki.component.Damage.TrueDamageHandle extends BaseDamageHandle implements IDamageHandle {
    public static var instance:TrueDamageHandle = new TrueDamageHandle();

    public function TrueDamageHandle() {
        super();
    }

    // 判断子弹是否为真伤类型
    public function canHandle(bullet:Object):Boolean {
        return (bullet.伤害类型 === "真伤");
    }

    public function handleBulletDamage(bullet:Object, shooter:Object, target:Object, manager:Object, result:DamageResult):Void {
        var trueDamageColor:String = bullet.子弹敌我属性值 ? "#4A0099" : "#660033";
        result.setDamageColor(trueDamageColor);
        result.addDamageEffect('<font color="' + trueDamageColor + '" size="20"> 真</font>');
        target.损伤值 = bullet.破坏力;
    }

    public function toString():String
    {
        return "TrueDamageHandle";
    }
}
