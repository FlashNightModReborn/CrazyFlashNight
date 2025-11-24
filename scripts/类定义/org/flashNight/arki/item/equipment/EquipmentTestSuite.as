import org.flashNight.arki.item.equipment.*;
import org.flashNight.arki.item.EquipmentUtil;

/**
 * EquipmentTestSuite - 装备系统重构测试套件
 *
 * 运行所有模块的测试，验证重构后的功能正确性
 *
 * @author 重构测试
 */
class org.flashNight.arki.item.equipment.EquipmentTestSuite {

    /**
     * 运行完整测试套件
     * @return 测试报告字符串
     */
    public static function runAllTests():String {
        var report:String = "\n";
        report += "========================================\n";
        report += "    装备系统重构测试套件 v1.0\n";
        report += "========================================\n\n";

        var startTime:Number = getTimer();

        // 1. PropertyOperators 测试
        report += "【1. PropertyOperators 测试】\n";
        report += PropertyOperators.runTests();
        report += "\n";

        // 2. ModRegistry 性能测试
        report += "【2. ModRegistry 性能测试】\n";
        report += ModRegistry.runPerformanceTest();
        report += "\n";

        // 3. TagManager 测试
        report += "【3. TagManager 测试】\n";
        report += TagManager.runTests();
        report += "\n";

        // 4. TierSystem 测试
        report += "【4. TierSystem 测试】\n";
        report += TierSystem.runTests();
        report += "\n";

        // 5. 集成测试
        report += "【5. 集成测试】\n";
        report += runIntegrationTest();
        report += "\n";

        // 6. modAvailabilityResults 测试
        report += "【6. modAvailabilityResults 兼容性测试】\n";
        report += testModAvailabilityResults();
        report += "\n";

        var endTime:Number = getTimer();
        var totalTime:Number = endTime - startTime;

        report += "========================================\n";
        report += "测试完成！总耗时: " + totalTime + "ms\n";
        report += "========================================\n";

        return report;
    }

    /**
     * 运行集成测试
     * @private
     */
    private static function runIntegrationTest():String {
        var result:String = "";

        // 测试配置加载
        result += testConfigLoading();

        // 测试计算流程
        result += testCalculationFlow();

        // 测试配件可用性
        result += testModAvailability();

        return result;
    }

    /**
     * 测试配置加载流程
     * @private
     */
    private static function testConfigLoading():String {
        // 准备测试数据
        var configData:Object = {
            levelStatList: [1, 1.06, 1.14, 1.24],
            decimalPropDict: {weight: 1},
            tierNameToKeyDict: {二阶: "data_2"},
            tierToMaterialDict: {data_2: "二阶复合防御组件"},
            defaultTierDataDict: {
                二阶: {level: 12, defence: 80}
            }
        };

        // 加载配置
        EquipmentConfigManager.loadConfig(configData);

        // 验证加载结果
        var maxLevel:Number = EquipmentConfigManager.getMaxLevel();
        var tierMaterial:String = EquipmentConfigManager.getMaterialByTierName("二阶");

        var passed:Boolean = (maxLevel == 3 && tierMaterial == "二阶复合防御组件");

        return passed ? "✓ 配置加载测试通过\n" : "✗ 配置加载测试失败\n";
    }

    /**
     * 测试计算流程
     * @private
     */
    private static function testCalculationFlow():String {
        // 准备测试数据
        var itemData:Object = {
            name: "测试装备",
            use: "头部装备",
            data: {
                defence: 100,
                hp: 50
            }
        };

        var value:Object = {
            level: 2,  // Lv2 = 1.06倍
            tier: null,
            mods: []
        };

        var cfg:Object = EquipmentConfigManager.getFullConfig();

        // 执行计算
        var result:Object = EquipmentCalculator.calculatePure(itemData, value, cfg, {});

        // 验证结果（100 * 1.06 = 106）
        var passed:Boolean = (result.data.defence == 106);

        return passed ? "✓ 计算流程测试通过\n" : "✗ 计算流程测试失败\n";
    }

    /**
     * 测试 modAvailabilityResults 字典
     * @private
     */
    private static function testModAvailabilityResults():String {
        var results:Object = EquipmentUtil.modAvailabilityResults;

        // 测试字典是否存在
        if(!results) {
            return "✗ modAvailabilityResults 未初始化\n";
        }

        // 测试关键状态码
        var testCases:Array = [
            {code: 1, expect: "可装备"},
            {code: -1, expect: "装备配件槽已满"},
            {code: -16, expect: "缺少前置结构支持"}
        ];

        for(var i:Number = 0; i < testCases.length; i++) {
            var test:Object = testCases[i];
            var actual:String = results[test.code];
            if(actual != test.expect) {
                return "✗ 状态码 " + test.code + " 返回错误: " + actual + "\n";
            }
        }

        return "✓ modAvailabilityResults 测试通过\n";
    }

    /**
     * 测试配件可用性检查
     * @private
     */
    private static function testModAvailability():String {
        // 准备测试数据
        var modData:Array = [
            {
                name: "基础插件",
                use: "头部装备",
                provideTags: "基础结构"
            },
            {
                name: "高级插件",
                use: "头部装备",
                requireTags: "基础结构"
            }
        ];

        // 加载配件数据
        ModRegistry.loadModData(modData);

        // 创建测试装备
        var testItem = {
            name: "测试头盔",
            value: {
                mods: ["基础插件"]
            }
        };

        var testItemData:Object = {
            use: "头部装备",
            data: { modslot: 3 }
        };

        // 检查高级插件是否可用
        var availability:Number = TagManager.checkModAvailability(testItem, testItemData, "高级插件");

        var passed:Boolean = (availability == 1); // 应该可用

        return passed ? "✓ 配件可用性测试通过\n" : "✗ 配件可用性测试失败\n";
    }

    /**
     * 获取当前时间戳（AS2兼容）
     * @private
     */
    private static function getTimer():Number {
        return new Date().getTime();
    }

    /**
     * 输出测试报告到服务器消息
     * @param report 测试报告
     */
    public static function printReport(report:String):Void {
        // 分行输出，避免消息过长
        var lines:Array = report.split("\n");
        for (var i:Number = 0; i < lines.length; i++) {
            if (lines[i].length > 0) {
                _root.服务器.发布服务器消息(lines[i]);
            }
        }
    }

    /**
     * 快速运行测试并输出结果
     */
    public static function quickTest():Void {
        var report:String = runAllTests();
        printReport(report);
    }
}