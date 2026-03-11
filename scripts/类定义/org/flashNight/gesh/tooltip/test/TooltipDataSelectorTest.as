import org.flashNight.gesh.tooltip.TooltipDataSelector;
import org.flashNight.gesh.tooltip.test.TestDataBootstrap;

/**
 * TooltipDataSelectorTest - 数据选择器纯函数测试
 * 需 TestDataBootstrap.init() 完成（tierNameToKeyDict 依赖）。
 */
class org.flashNight.gesh.tooltip.test.TooltipDataSelectorTest {

    private static var testsRun:Number = 0;
    private static var testsPassed:Number = 0;
    private static var testsFailed:Number = 0;

    private static function assert(cond:Boolean, msg:String):Void {
        testsRun++;
        if (cond) { testsPassed++; trace("[PASS] " + msg); }
        else { testsFailed++; trace("[FAIL] " + msg); }
    }

    private static function assertEq(expected, actual, msg:String):Void {
        testsRun++;
        if (expected === actual) { testsPassed++; trace("[PASS] " + msg); }
        else { testsFailed++; trace("[FAIL] " + msg + " expected=" + expected + " actual=" + actual); }
    }

    public static function runAllTests():Void {
        testsRun = testsPassed = testsFailed = 0;
        trace("--- TooltipDataSelectorTest ---");

        TestDataBootstrap.init();

        test_basicReturn();
        test_deepCopy();
        test_tierOverride();
        test_nullTier();

        trace("--- TooltipDataSelectorTest: " + testsPassed + "/" + testsRun + " passed, " + testsFailed + " failed ---");
    }

    private static function test_basicReturn():Void {
        var item:Object = {data: {power: 100, level: 5}};
        var result:Object = TooltipDataSelector.getEquipmentData(item, null);
        assertEq(100, result.power, "getEquipmentData basic power");
        assertEq(5, result.level, "getEquipmentData basic level");
    }

    private static function test_deepCopy():Void {
        var item:Object = {data: {power: 100}};
        var result:Object = TooltipDataSelector.getEquipmentData(item, null);
        result.power = 999;
        assertEq(100, item.data.power, "getEquipmentData deep copy - original unchanged");
    }

    private static function test_tierOverride():Void {
        // 测试军刀有 data_2 品阶数据：{level: 12, power: 150, force: 15}
        var item:Object = {
            data: {level: 9, power: 100, force: 10, weight: 3},
            data_2: {level: 12, power: 150, force: 15}
        };
        var result:Object = TooltipDataSelector.getEquipmentData(item, "二阶");
        assertEq(12, result.level, "getEquipmentData tier override level");
        assertEq(150, result.power, "getEquipmentData tier override power");
        assertEq(15, result.force, "getEquipmentData tier override force");
        assertEq(3, result.weight, "getEquipmentData tier inherits base weight");
    }

    private static function test_nullTier():Void {
        var item:Object = {data: {power: 50}};
        var result:Object = TooltipDataSelector.getEquipmentData(item, "不存在品阶");
        assertEq(50, result.power, "getEquipmentData unknown tier fallback to base");
    }
}
