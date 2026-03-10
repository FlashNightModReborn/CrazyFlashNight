
import org.flashNight.arki.component.Damage.*;


class org.flashNight.arki.component.Damage.TrueDamageHandle extends BaseDamageHandle implements IDamageHandle {
    public static var instance:TrueDamageHandle = new TrueDamageHandle();

    public function TrueDamageHandle() {
        super();
    }

    /**
     * 获取 TrueDamageHandle 的单例实例。
     * 
     * - 若实例不存在，则创建一个新的 TrueDamageHandle 实例并返回。
     * - 若实例已存在，则直接返回已创建的实例。
     * - 此方法通过闭包优化后续调用，避免多次判断，提升性能。
     * 
     * @return TrueDamageHandle 单例实例
     */
    public static function getInstance():TrueDamageHandle {
        if (instance == null) {
            instance = new TrueDamageHandle();
            getInstance = function():TrueDamageHandle {
                return instance;
            };
        }
        return instance;
    }

    // 判断子弹是否为真伤类型
    public function canHandle(bullet:Object):Boolean {
        return (bullet.伤害类型 === "真伤");
    }

    public function handleBulletDamage(bullet:Object, shooter:Object, target:Object, manager:Object, result:DamageResult):Void {
        result._dmgColorId = bullet.是否为敌人 ? 3 : 4; // 真伤：#660033 / #4A0099
        result._efFlags |= (8 | (bullet.是否为敌人 ? 128 : 0)); // EF_DMG_TYPE_LABEL | isEnemy
        result._efText = "真";
        target.损伤值 = bullet.破坏力;
    }

    public function toString():String
    {
        return "TrueDamageHandle";
    }
}
