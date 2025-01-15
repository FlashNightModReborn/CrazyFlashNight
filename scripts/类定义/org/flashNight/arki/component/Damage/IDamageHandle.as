import org.flashNight.arki.component.Damage.*;

interface org.flashNight.arki.component.Damage.IDamageHandle {
    // 所有 Handle 都必须实现该方法
    function execute(context:DamageContext):Void;
}
