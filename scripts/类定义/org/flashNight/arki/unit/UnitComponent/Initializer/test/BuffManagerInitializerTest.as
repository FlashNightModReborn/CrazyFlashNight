import org.flashNight.arki.unit.UnitComponent.Initializer.BuffManagerInitializer;
import org.flashNight.arki.component.Buff.*;
import org.flashNight.arki.component.Buff.Component.*;

/**
 * BuffManagerInitializer 测试套件
 *
 * 使用方式：org.flashNight.arki.unit.UnitComponent.Initializer.test.BuffManagerInitializerTest.runAllTests();
 */
class org.flashNight.arki.unit.UnitComponent.Initializer.test.BuffManagerInitializerTest {

    /**
     * 运行全部测试
     */
    public static function runAllTests():Void {
        trace("=== BuffManagerInitializer Test Suite ===");
        test_reset_replacesManagerAndClearsBuffs();
        trace("BuffManagerInitializerTest: 所有测试完成");
    }

    /**
     * reset() 应该：
     * - 销毁旧实例并替换为新实例
     * - 清空旧 Buff 对属性的影响（finalize 后回到 base 值）
     */
    private static function test_reset_replacesManagerAndClearsBuffs():Void {
        var target:MovieClip = MovieClip({ attack: 100 });

        BuffManagerInitializer.initialize(target);
        target.buffManager.addBuff(new PodBuff("attack", BuffCalculationType.ADD, 30), "T_RESET_1");
        target.buffManager.update(1);

        if (Number(target.attack) != 130) {
            throw new Error("Expected attack=130 after buff, got " + target.attack);
        }

        var oldManager:Object = target.buffManager;

        BuffManagerInitializer.reset(target);
        if (target.buffManager === oldManager) {
            throw new Error("Expected buffManager instance replaced after reset()");
        }

        target.buffManager.update(0);
        if (Number(target.attack) != 100) {
            throw new Error("Expected attack=100 after reset, got " + target.attack);
        }

        target.buffManager.destroy();
    }
}

