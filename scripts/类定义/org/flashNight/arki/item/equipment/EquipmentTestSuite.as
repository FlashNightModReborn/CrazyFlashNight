import org.flashNight.arki.item.equipment.*;
import org.flashNight.arki.item.EquipmentUtil;
import org.flashNight.arki.item.BaseItem;

/** 
 * EquipmentTestSuite - 装备系统测试套件
 *
 * 集中管理所有装备模块的测试用例，从各业务类中分离测试代码
 * 保持业务类的简洁，同时便于统一运行和维护测试
 *
 * @author 重构测试
 */
class org.flashNight.arki.item.equipment.EquipmentTestSuite {

    // ==================== 公共入口 ====================

    /**
     * 运行完整测试套件
     * @return 测试报告字符串
     */
    public static function runAllTests():String {
        var report:String = "\n";
        report += "========================================\n";
        report += "    装备系统测试套件 v2.0\n";
        report += "========================================\n\n";

        var startTime:Number = getTimer();

        // 初始化测试环境
        initTestEnvironment();

        // 1. PropertyOperators 测试
        report += "【1. PropertyOperators 测试】\n";
        report += testPropertyOperators();
        report += "\n";

        // 2. ModRegistry 性能测试
        report += "【2. ModRegistry 性能测试】\n";
        report += testModRegistryPerformance();
        report += "\n";

        // 3. TagManager 测试
        report += "【3. TagManager 测试】\n";
        report += testTagManager();
        report += "\n";

        // 4. TierSystem 测试
        report += "【4. TierSystem 测试】\n";
        report += testTierSystem();
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

        trace(report);

        return report;
    }

    /**
     * 快速运行测试并输出结果
     */
    public static function quickTest():Void {
        var report:String = runAllTests();
        printReport(report);
    }

    /**
     * 输出测试报告到服务器消息
     * @param report 测试报告
     */
    public static function printReport(report:String):Void {
        var lines:Array = report.split("\n");
        for (var i:Number = 0; i < lines.length; i++) {
            if (lines[i].length > 0) {
                _root.服务器.发布服务器消息(lines[i]);
            }
        }
    }

    // ==================== PropertyOperators 测试 ====================

    /**
     * 运行属性运算符的单元测试
     */
    private static function testPropertyOperators():String {
        var results:Array = [];

        results.push(testPropertyOperators_Add());
        results.push(testPropertyOperators_Multiply());
        results.push(testPropertyOperators_Override());
        results.push(testPropertyOperators_Merge());
        results.push(testPropertyOperators_ApplyCap());

        var allPassed:Boolean = true;
        var summary:String = "";

        for (var i:Number = 0; i < results.length; i++) {
            summary += results[i] + "\n";
            if (results[i].indexOf("✗") != -1) {
                allPassed = false;
            }
        }

        summary += allPassed ? "PropertyOperators 所有测试通过！" : "PropertyOperators 有测试失败！";
        return summary;
    }

    private static function testPropertyOperators_Add():String {
        var prop:Object = {damage: 10, defence: 20};
        var addProp:Object = {damage: 5, hp: 100};

        PropertyOperators.add(prop, addProp, 0);

        var passed:Boolean = (prop.damage == 15 && prop.defence == 20 && prop.hp == 100);
        return passed ? "✓ add 测试通过" : "✗ add 测试失败";
    }

    private static function testPropertyOperators_Multiply():String {
        var prop:Object = {damage: 100, weight: 1.5};
        var multiProp:Object = {damage: 1.5, weight: 2};

        PropertyOperators.multiply(prop, multiProp);

        var passed:Boolean = (prop.damage == 150 && prop.weight == 3);
        return passed ? "✓ multiply 测试通过" : "✗ multiply 测试失败";
    }

    private static function testPropertyOperators_Override():String {
        var prop:Object = {damage: 100, defence: 50};
        var overProp:Object = {damage: 200};

        PropertyOperators.override(prop, overProp);

        var passed:Boolean = (prop.damage == 200 && prop.defence == 50);
        return passed ? "✓ override 测试通过" : "✗ override 测试失败";
    }

    private static function testPropertyOperators_Merge():String {
        var prop:Object = {
            damage: 100,
            magicdefence: {fire: 10, ice: 20}
        };
        var mergeProp:Object = {
            damage: 150,
            magicdefence: {fire: 15, poison: 5}
        };

        PropertyOperators.merge(prop, mergeProp);

        var passed:Boolean = (
            prop.damage == 150 &&
            prop.magicdefence.fire == 15 &&
            prop.magicdefence.ice == 20 &&
            prop.magicdefence.poison == 5
        );
        return passed ? "✓ merge 测试通过" : "✗ merge 测试失败";
    }

    private static function testPropertyOperators_ApplyCap():String {
        var prop:Object = {damage: 150, defence: 30};
        var capProp:Object = {damage: 20, defence: -10};
        var baseProp:Object = {damage: 100, defence: 50};

        PropertyOperators.applyCap(prop, capProp, baseProp);

        var passed:Boolean = (prop.damage == 120 && prop.defence == 40);
        return passed ? "✓ applyCap 测试通过" : "✗ applyCap 测试失败";
    }

    // ==================== ModRegistry 测试 ====================

    /**
     * 运行 ModRegistry 性能测试
     */
    private static function testModRegistryPerformance():String {
        var result:String = "";

        // 创建测试数据
        var testMod:Object = {
            name: "测试配件",
            stats: {
                useSwitch: {
                    use: [
                        {name: "头部装备,上装装备", percentage: {defence: 10}},
                        {name: "手枪,长枪", percentage: {power: 15}},
                        {name: "刀", percentage: {damage: 20}}
                    ]
                }
            }
        };

        // 处理测试配件
        ModRegistry.loadModData([testMod]);

        // 获取处理后的配件数据
        var processedMod:Object = ModRegistry.getModData("测试配件");

        // 创建测试装备
        var itemUseLookup:Object = ModRegistry.buildItemUseLookup("长枪", "狙击枪");

        // 测试优化后的匹配
        var startTime:Number = getTimer();
        var matchCount:Number = 0;

        for (var i:Number = 0; i < 10000; i++) {
            var matched:Object = ModRegistry.matchUseSwitch(processedMod, itemUseLookup);
            if (matched) matchCount++;
        }

        var endTime:Number = getTimer();
        var duration:Number = endTime - startTime;

        result += "优化后算法测试（10000次匹配）:\n";
        result += "  耗时: " + duration + "ms\n";
        result += "  匹配成功: " + matchCount + " 次\n";
        result += "  平均每次: " + (duration / 10000) + "ms\n";

        var passed:Boolean = (matchCount == 10000 && duration < 1000);
        result += passed ? "✓ ModRegistry 性能测试通过" : "✗ ModRegistry 性能测试失败";

        return result;
    }

    // ==================== TagManager 测试 ====================

    /**
     * 运行 TagManager 测试
     * 注意：所有TagManager测试共用同一份配件数据，避免重复loadModData导致数据丢失
     */
    private static function testTagManager():String {
        var result:String = "";

        // 一次性加载所有测试需要的配件数据
        ModRegistry.loadModData([
            // 标签依赖测试用
            {
                name: "提供结构的插件",
                use: "头部装备",
                provideTags: "基础结构,高级结构"
            },
            {
                name: "需要结构的插件",
                use: "头部装备",
                requireTags: "基础结构"
            },
            // 标签互斥测试用
            {
                name: "占位插件A",
                use: "头部装备",
                tag: "槽位1"
            },
            {
                name: "占位插件B",
                use: "头部装备",
                tag: "槽位1"
            },
            // 依赖链测试用
            {
                name: "插件A",
                use: "头部装备",
                provideTags: "结构A"
            },
            {
                name: "插件B",
                use: "头部装备",
                requireTags: "结构A"
            }
        ]);

        result += testTagManager_BasicDependency();
        result += testTagManager_TagExclusion();
        result += testTagManager_DependencyChain();

        return result;
    }

    private static function testTagManager_BasicDependency():String {
        // 模拟装备对象，已安装"提供结构的插件"
        var testItem = {
            name: "测试装备",
            value: {
                mods: ["提供结构的插件"]
            }
        };

        var context:Object = TagManager.buildTagContext(testItem, {});
        var hasTags:Boolean = (context.presentTags["基础结构"] == true);

        return hasTags ? "✓ 标签依赖测试通过\n" : "✗ 标签依赖测试失败\n";
    }

    private static function testTagManager_TagExclusion():String {
        // 模拟装备对象，已安装"占位插件A"
        var testItem = {
            name: "测试装备",
            value: {
                mods: ["占位插件A"]
            }
        };

        var testItemData = {
            data: { modslot: 3 }
        };

        // 尝试安装同tag的"占位插件B"，应该返回-8（同位置插件已装备）
        var availability:Number = TagManager.checkModAvailability(testItem, testItemData, "占位插件B");
        var isExcluded:Boolean = (availability == -8);

        return isExcluded ? "✓ 标签互斥测试通过\n" : "✗ 标签互斥测试失败（返回码=" + availability + "，期望-8）\n";
    }

    private static function testTagManager_DependencyChain():String {
        // 模拟装备对象，已安装"插件A"和"插件B"
        var testItem = {
            name: "测试装备",
            value: {
                mods: ["插件A", "插件B"]
            }
        };

        // 查询哪些插件依赖"插件A"
        var dependents:Array = TagManager.getDependentMods(testItem, "插件A");
        var hasDependent:Boolean = (dependents.length == 1 && dependents[0] == "插件B");

        return hasDependent ? "✓ 依赖链测试通过\n" : "✗ 依赖链测试失败（依赖数=" + dependents.length + "）\n";
    }

    // ==================== TierSystem 测试 ====================

    /**
     * 运行 TierSystem 测试
     */
    private static function testTierSystem():String {
        var result:String = "";

        result += testTierSystem_MaterialQuery();
        result += testTierSystem_DefaultEligibility();
        result += testTierSystem_DataApplication();

        return result;
    }

    private static function testTierSystem_MaterialQuery():String {
        EquipmentConfigManager.loadConfig({
            tierNameToKeyDict: {二阶: "data_2"},
            tierToMaterialDict: {data_2: "二阶复合防御组件"}
        });

        var material:String = TierSystem.getTierItem("二阶");
        var passed:Boolean = (material == "二阶复合防御组件");

        return passed ? "✓ 进阶材料查询测试通过\n" : "✗ 进阶材料查询测试失败\n";
    }

    private static function testTierSystem_DefaultEligibility():String {
        var testData:Object = {
            type: "防具",
            use: "头部装备",
            data: { level: 5 }
        };

        var eligible:Boolean = TierSystem.isDefaultTierEligible(testData);

        return eligible ? "✓ 默认进阶条件测试通过\n" : "✗ 默认进阶条件测试失败\n";
    }

    private static function testTierSystem_DataApplication():String {
        var testItemData:Object = {
            data: {
                level: 10,
                defence: 50
            },
            data_2: {
                level: 15,
                defence: 100,
                displayname: "强化装备"
            }
        };

        EquipmentConfigManager.loadConfig({
            tierNameToKeyDict: {二阶: "data_2"}
        });

        TierSystem.applyTierData(testItemData, "二阶", null);

        var passed:Boolean = (
            testItemData.data.level == 15 &&
            testItemData.data.defence == 100 &&
            testItemData.displayname == "强化装备" &&
            testItemData.data_2 == null
        );

        return passed ? "✓ 进阶数据应用测试通过\n" : "✗ 进阶数据应用测试失败\n";
    }

    // ==================== 集成测试 ====================

    /**
     * 运行集成测试
     */
    private static function runIntegrationTest():String {
        var result:String = "";

        result += testConfigLoading();
        result += testCalculationFlow();
        result += testModAvailability();

        return result;
    }

    private static function testConfigLoading():String {
        var configData:Object = {
            levelStatList: [1, 1.06, 1.14, 1.24],
            decimalPropDict: {weight: 1},
            tierNameToKeyDict: {二阶: "data_2"},
            tierToMaterialDict: {data_2: "二阶复合防御组件"},
            defaultTierDataDict: {
                二阶: {level: 12, defence: 80}
            }
        };

        EquipmentConfigManager.loadConfig(configData);

        var maxLevel:Number = EquipmentConfigManager.getMaxLevel();
        var tierMaterial:String = EquipmentConfigManager.getMaterialByTierName("二阶");

        var passed:Boolean = (maxLevel == 3 && tierMaterial == "二阶复合防御组件");

        return passed ? "✓ 配置加载测试通过\n" : "✗ 配置加载测试失败\n";
    }

    private static function testCalculationFlow():String {
        var itemData:Object = {
            name: "测试装备",
            use: "头部装备",
            data: {
                defence: 100,
                hp: 50
            }
        };

        var value:Object = {
            level: 2,  // levelStatList[2] = 1.14
            tier: null,
            mods: []
        };

        var cfg:Object = EquipmentConfigManager.getFullConfig();

        var result:Object = EquipmentCalculator.calculatePure(itemData, value, cfg, {});

        // 100 * 1.14 = 114（levelStatList[2] = 1.14）
        var passed:Boolean = (result.data.defence == 114);

        return passed ? "✓ 计算流程测试通过\n" : "✗ 计算流程测试失败（defence=" + result.data.defence + "，期望114）\n";
    }

    private static function testModAvailability():String {
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

        ModRegistry.loadModData(modData);

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

        var availability:Number = TagManager.checkModAvailability(testItem, testItemData, "高级插件");

        var passed:Boolean = (availability == 1);

        return passed ? "✓ 配件可用性测试通过\n" : "✗ 配件可用性测试失败\n";
    }

    // ==================== 兼容性测试 ====================

    private static function testModAvailabilityResults():String {
        var results:Object = EquipmentUtil.modAvailabilityResults;

        if (!results) {
            return "✗ modAvailabilityResults 未初始化\n";
        }

        var testCases:Array = [
            {code: 1, expect: "可装备"},
            {code: -1, expect: "装备配件槽已满"},
            {code: -16, expect: "缺少前置结构支持"}
        ];

        for (var i:Number = 0; i < testCases.length; i++) {
            var test:Object = testCases[i];
            var actual:String = results[test.code];
            if (actual != test.expect) {
                return "✗ 状态码 " + test.code + " 返回错误: " + actual + "\n";
            }
        }

        return "✓ modAvailabilityResults 测试通过\n";
    }

    // ==================== 工具方法 ====================

    /**
     * 初始化测试环境
     * 确保所有必要的配置和数据在测试前正确加载
     */
    private static function initTestEnvironment():Void {
        // 加载基础配置
        var configData:Object = {
            levelStatList: [1, 1.06, 1.14, 1.24, 1.36, 1.5],
            decimalPropDict: {weight: 1, rout: 1, vampirism: 1},
            tierNameToKeyDict: {二阶: "data_2", 三阶: "data_3"},
            tierToMaterialDict: {data_2: "二阶复合防御组件", data_3: "三阶复合防御组件"},
            defaultTierDataDict: {
                二阶: {level: 12, defence: 80},
                三阶: {level: 15, defence: 120}
            }
        };
        EquipmentConfigManager.loadConfig(configData);

        // 初始化 modAvailabilityResults
        EquipmentUtil.initializeModAvailabilityResults();
    }

    private static function getTimer():Number {
        return new Date().getTime();
    }
}
