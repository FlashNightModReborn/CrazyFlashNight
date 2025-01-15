import org.flashNight.arki.component.Damage.*;

class org.flashNight.arki.component.Damage.BaseDamageHandle implements IDamageHandle {
    
    public function BaseDamageHandle() {
        // 构造器可做一些通用初始化
    }

    // 默认什么也不做，子类可覆写
    public function execute(context:DamageContext):Void {
        // do nothing by default
    }
}
