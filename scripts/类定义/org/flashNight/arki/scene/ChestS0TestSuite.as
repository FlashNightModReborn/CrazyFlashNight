import org.flashNight.arki.unit.UnitComponent.Initializer.test.*;
import org.flashNight.arki.scene.*;

/**
 * 地图资源箱 S0 A01-A25 + A03F fail-closed 反向用例 + S01-S10 socket actual-wire +
 * P01-P04 supplemental preflight + F01-F04 聚合套件。
 * P 用例仍是局部模型；F 用例另外经过生产 Flash 接线，但不替代 XFL 视觉验收。
 */
class org.flashNight.arki.scene.ChestS0TestSuite {

    /**
     * 运行全部测试
     */
    public static function runAllTests():Void {
        trace("=== ChestS0TestSuite A01-A25/A03F/S01-S10/P01-P04 supplemental preflight/F01-F04 start ===");
        BoxInteractionArbiterTest.runAllTests();
        ChestSessionServiceTest.runAllTests();
        ChestS0SocketBridgeTest.runAllTests();
        ChestS0FlashWiringTest.runAllTests();
        ChestS0ProductionFlashWiringTest.runAllTests();
        trace("=== ChestS0TestSuite A01-A25/A03F/S01-S10/P01-P04 supplemental preflight/F01-F04 complete ===");
    }
}
