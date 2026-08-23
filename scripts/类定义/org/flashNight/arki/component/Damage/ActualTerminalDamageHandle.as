
import org.flashNight.arki.component.Damage.*;

/**
 * 天使铳等显式终结弹的最后一个“分类后提交”处理器。
 *
 * 专用 factory 只在本处理器之前运行 Crit / Universal / Dodge / MultiShot，
 * 因而可以用统一 DamageResult 判定普通或分段 MISS；真实命中后直接提交旧有
 * 强制终结语义，并让 DamageCalculator 在护盾、毒、吸血、击溃、斩杀和普通扣血
 * 之前返回。普通子弹永远不会装入本处理器。
 */
class org.flashNight.arki.component.Damage.ActualTerminalDamageHandle
        extends BaseDamageHandle implements IDamageHandle {

    public static var instance:ActualTerminalDamageHandle = new ActualTerminalDamageHandle();

    public function ActualTerminalDamageHandle() {
        super();
        this.skipCheck = true;
    }

    public static function getInstance():ActualTerminalDamageHandle {
        return instance;
    }

    public function canHandle(bullet:Object):Boolean {
        return true;
    }

    public function handleBulletDamage(bullet:Object, shooter:Object, target:Object,
                                       manager:Object, result:DamageResult):Void {
        if (!DamageResult.hasActualHit(result)) return;

        bullet.伤害类型 = "死";
        target.hp = 0;
        target.损伤值 = 0;
    }

    public function toString():String {
        return "ActualTerminalDamageHandle";
    }
}
