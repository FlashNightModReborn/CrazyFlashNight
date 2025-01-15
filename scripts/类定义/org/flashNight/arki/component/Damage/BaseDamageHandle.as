import org.flashNight.arki.component.Damage.*;

class org.flashNight.arki.component.Damage.BaseDamageHandle implements IDamageHandle {

    public function BaseDamageHandle() {
        // 构造函数
    }

    // 默认空实现，如需则在子类中覆盖
    public function handleBulletDamage(bullet:Object, shooter:Object, target:Object, manager:Object, result:DamageResult):Void {
        // do nothing by default
    }
}
