import org.flashNight.arki.item.EquipmentUtil;

/**
 * 测试配件可用性结果字典
 */
class org.flashNight.arki.item.equipment.TestModAvailability {

    public static function test():Void {
        trace("\n===== 测试 modAvailabilityResults =====");

        // 测试字典是否正确初始化
        var results:Object = EquipmentUtil.modAvailabilityResults;

        if (results == null || results == undefined) {
            trace("✗ 错误：modAvailabilityResults 未初始化");
            return;
        }

        trace("✓ modAvailabilityResults 已初始化");

        // 测试所有状态码
        var codes:Array = [1, 0, -1, -2, -4, -8, -16, -32, -64];
        var allPassed:Boolean = true;

        for (var i:Number = 0; i < codes.length; i++) {
            var code:Number = codes[i];
            var desc:String = results[code];

            if (desc == null || desc == undefined || desc == "undefined") {
                trace("✗ 状态码 " + code + " 返回 undefined");
                allPassed = false;
            } else {
                trace("✓ 状态码 " + code + ": " + desc);
            }
        }

        if (allPassed) {
            trace("\n✓✓✓ 所有测试通过！");
        } else {
            trace("\n✗✗✗ 有测试失败！");
        }

        // 测试实际调用
        trace("\n测试实际调用：");
        var testCode:Number = -1;
        var testResult:String = EquipmentUtil.modAvailabilityResults[testCode];
        trace("EquipmentUtil.modAvailabilityResults[" + testCode + "] = " + testResult);

        // 输出到服务器消息
        if (_root.服务器) {
            _root.服务器.发布服务器消息("modAvailabilityResults[-1] = " + testResult);
        }
    }
}