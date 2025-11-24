import org.flashNight.arki.item.EquipmentUtil;
import org.flashNight.arki.item.equipment.EquipmentConfigManager;
import org.flashNight.arki.item.equipment.ModRegistry;

/**
 * 引用共享一致性测试
 *
 * 【方案A实施】
 * 验证EquipmentUtil和Manager层之间的引用共享是否正确实现
 * 确保数据只有一份，避免双份状态的维护成本
 */
class org.flashNight.arki.item.test.ReferenceConsistencyTest {

    /**
     * 执行所有测试
     * @return 测试结果字符串
     */
    public static function runAllTests():String {
        var results:String = "=== 引用共享一致性测试 ===\n\n";

        results += testConfigReferenceSharing() + "\n\n";
        results += testModDataReferenceSharing() + "\n\n";
        results += testDisplayNameIndex() + "\n\n";
        results += testUseSwitchUnification() + "\n\n";

        return results;
    }

    /**
     * 测试配置数据的引用共享
     */
    private static function testConfigReferenceSharing():String {
        var result:String = "【测试：配置数据引用共享】\n";

        // 准备测试数据
        var testConfig:Object = {
            levelStatList: [1, 1.06, 1.14, 1.24, 1.36],
            decimalPropDict: {weight: 1, speed: 1},
            tierNameToKeyDict: {测试阶: "data_test"},
            tierToMaterialDict: {data_test: "测试材料"},
            defaultTierDataDict: {测试阶: {level: 10, hp: 100}}
        };

        // 加载配置
        EquipmentUtil.loadEquipmentConfig(testConfig);

        // 验证引用是否相同（而非复制）
        var test1:Boolean = (EquipmentUtil.levelStatList === EquipmentConfigManager.getLevelStatList());
        result += "  levelStatList引用相同: " + (test1 ? "✓通过" : "✗失败") + "\n";

        var test2:Boolean = (EquipmentUtil.decimalPropDict === EquipmentConfigManager.getDecimalPropDict());
        result += "  decimalPropDict引用相同: " + (test2 ? "✓通过" : "✗失败") + "\n";

        var test3:Boolean = (EquipmentUtil.tierNameToKeyDict === EquipmentConfigManager.getTierNameToKeyDict());
        result += "  tierNameToKeyDict引用相同: " + (test3 ? "✓通过" : "✗失败") + "\n";

        var test4:Boolean = (EquipmentUtil.tierToMaterialDict === EquipmentConfigManager.getTierToMaterialDict());
        result += "  tierToMaterialDict引用相同: " + (test4 ? "✓通过" : "✗失败") + "\n";

        var test5:Boolean = (EquipmentUtil.defaultTierDataDict === EquipmentConfigManager.getDefaultTierDataDict());
        result += "  defaultTierDataDict引用相同: " + (test5 ? "✓通过" : "✗失败") + "\n";

        // 验证反向字典
        var test6:Boolean = (EquipmentUtil.tierKeyToNameDict === EquipmentConfigManager.getTierKeyToNameDict());
        result += "  tierKeyToNameDict引用相同: " + (test6 ? "✓通过" : "✗失败") + "\n";

        var allPassed:Boolean = test1 && test2 && test3 && test4 && test5 && test6;
        result += "\n  总体结果: " + (allPassed ? "✓ 所有配置引用共享测试通过" : "✗ 有测试失败");

        return result;
    }

    /**
     * 测试配件数据的引用共享
     */
    private static function testModDataReferenceSharing():String {
        var result:String = "【测试：配件数据引用共享】\n";

        // 准备测试数据
        var testMods:Array = [
            {
                name: "test_mod_1",
                displayname: "测试配件1",
                use: "长枪,手枪",
                stats: {
                    flat: {damage: 10},
                    percentage: {damage: 15}
                }
            },
            {
                name: "test_mod_2",
                displayname: "测试配件2",
                use: "头部装备",
                stats: {
                    flat: {hp: 50},
                    useSwitch: {
                        use: {
                            name: "长枪",
                            percentage: {damage: 20}
                        }
                    }
                }
            }
        ];

        // 加载配件数据
        EquipmentUtil.loadModData(testMods);

        // 验证引用是否相同
        var test1:Boolean = (EquipmentUtil.modDict === ModRegistry.getModDict());
        result += "  modDict引用相同: " + (test1 ? "✓通过" : "✗失败") + "\n";

        var test2:Boolean = (EquipmentUtil.modList === ModRegistry.getModList());
        result += "  modList引用相同: " + (test2 ? "✓通过" : "✗失败") + "\n";

        var test3:Boolean = (EquipmentUtil.modUseLists === ModRegistry.getModUseLists());
        result += "  modUseLists引用相同: " + (test3 ? "✓通过" : "✗失败") + "\n";

        // 验证数据内容
        var test4:Boolean = (EquipmentUtil.modDict["test_mod_1"] != null);
        result += "  test_mod_1存在: " + (test4 ? "✓通过" : "✗失败") + "\n";

        var test5:Boolean = (EquipmentUtil.modDict["test_mod_2"] != null);
        result += "  test_mod_2存在: " + (test5 ? "✓通过" : "✗失败") + "\n";

        // 验证归一化
        var mod1:Object = EquipmentUtil.modDict["test_mod_1"];
        var test6:Boolean = (mod1.stats.percentage.damage == 0.15); // 15% -> 0.15
        result += "  percentage归一化正确: " + (test6 ? "✓通过" : "✗失败") + "\n";

        var allPassed:Boolean = test1 && test2 && test3 && test4 && test5 && test6;
        result += "\n  总体结果: " + (allPassed ? "✓ 所有配件引用共享测试通过" : "✗ 有测试失败");

        return result;
    }

    /**
     * 测试displayname反向索引
     */
    private static function testDisplayNameIndex():String {
        var result:String = "【测试：displayname反向索引】\n";

        // 通过displayname查找配件
        var modByDisplay1:Object = ModRegistry.getModDataByDisplayName("测试配件1");
        var test1:Boolean = (modByDisplay1 != null && modByDisplay1.name == "test_mod_1");
        result += "  通过displayname找到test_mod_1: " + (test1 ? "✓通过" : "✗失败") + "\n";

        var modByDisplay2:Object = ModRegistry.getModDataByDisplayName("测试配件2");
        var test2:Boolean = (modByDisplay2 != null && modByDisplay2.name == "test_mod_2");
        result += "  通过displayname找到test_mod_2: " + (test2 ? "✓通过" : "✗失败") + "\n";

        // 测试索引表
        var displayIndex:Object = ModRegistry.getDisplayNameIndex();
        var test3:Boolean = (displayIndex["测试配件1"] == "test_mod_1");
        result += "  displayname索引正确: " + (test3 ? "✓通过" : "✗失败") + "\n";

        // 测试性能（简单对比）
        var startTime:Number = getTimer();
        for(var i:Number = 0; i < 1000; i++) {
            ModRegistry.getModDataByDisplayName("测试配件1");
        }
        var indexTime:Number = getTimer() - startTime;

        startTime = getTimer();
        for(var j:Number = 0; j < 1000; j++) {
            // 模拟O(n)遍历查找
            for(var modName:String in EquipmentUtil.modDict) {
                var mod:Object = EquipmentUtil.modDict[modName];
                if(mod.displayname == "测试配件1") break;
            }
        }
        var traverseTime:Number = getTimer() - startTime;

        result += "  索引查找耗时: " + indexTime + "ms (1000次)\n";
        result += "  遍历查找耗时: " + traverseTime + "ms (1000次)\n";
        result += "  性能提升: " + Math.round(traverseTime / indexTime) + "倍\n";

        var allPassed:Boolean = test1 && test2 && test3;
        result += "\n  总体结果: " + (allPassed ? "✓ displayname索引测试通过" : "✗ 有测试失败");

        return result;
    }

    /**
     * 测试useSwitch统一处理（包括多分支同时生效）
     */
    private static function testUseSwitchUnification():String {
        var result:String = "【测试：useSwitch统一处理】\n";

        // 构建测试查找表
        var lookup1:Object = ModRegistry.buildItemUseLookup("长枪", "狙击枪");
        var test1:Boolean = (lookup1["长枪"] == true && lookup1["狙击枪"] == true);
        result += "  buildItemUseLookup正确构建: " + (test1 ? "✓通过" : "✗失败") + "\n";

        // 测试单分支匹配（兼容性）
        var mod2:Object = EquipmentUtil.modDict["test_mod_2"];
        if(mod2 && mod2.stats && mod2.stats.useSwitch) {
            var matched:Object = ModRegistry.matchUseSwitch(mod2, lookup1);
            var test2:Boolean = (matched != null && matched.name == "长枪");
            result += "  matchUseSwitch正确匹配: " + (test2 ? "✓通过" : "✗失败") + "\n";

            // 验证返回的是正确的useCase
            var test3:Boolean = (matched && matched.percentage && matched.percentage.damage == 0.20);
            result += "  返回正确的useCase: " + (test3 ? "✓通过" : "✗失败") + "\n";
        } else {
            result += "  matchUseSwitch测试跳过（数据未准备好）\n";
            var test2:Boolean = false;
            var test3:Boolean = false;
        }

        result += "\n【测试：多分支同时生效】\n";

        // 准备多分支测试数据
        var multiMod:Object = {
            name: "test_multi_branch",
            displayname: "多分支测试配件",
            use: "长枪,手枪",
            stats: {
                flat: {damage: 10},  // 基础加成
                useSwitch: {
                    useCases: [
                        {
                            name: "长枪",
                            percentage: {damage: 20},  // 长枪+20%伤害
                            lookupDict: {"长枪": true}
                        },
                        {
                            name: "狙击枪",
                            percentage: {critRate: 15},  // 狙击枪+15%暴击
                            lookupDict: {"狙击枪": true}
                        },
                        {
                            name: "远程武器",
                            flat: {range: 100},  // 远程武器+100射程
                            lookupDict: {"远程武器": true}
                        }
                    ]
                }
            }
        };

        // 测试多分支匹配
        var multiLookup:Object = ModRegistry.buildItemUseLookup("长枪", "狙击枪,远程武器");
        var matchedAll:Array = ModRegistry.matchUseSwitchAll(multiMod, multiLookup);

        var test4:Boolean = (matchedAll.length == 3);  // 应该匹配3个分支
        result += "  匹配到" + matchedAll.length + "个分支: " + (test4 ? "✓通过" : "✗失败") + "\n";

        // 验证每个分支的内容
        if(matchedAll.length >= 3) {
            var test5:Boolean = (matchedAll[0].name == "长枪" && matchedAll[0].percentage.damage == 20);
            result += "  第1个分支(长枪)正确: " + (test5 ? "✓通过" : "✗失败") + "\n";

            var test6:Boolean = (matchedAll[1].name == "狙击枪" && matchedAll[1].percentage.critRate == 15);
            result += "  第2个分支(狙击枪)正确: " + (test6 ? "✓通过" : "✗失败") + "\n";

            var test7:Boolean = (matchedAll[2].name == "远程武器" && matchedAll[2].flat.range == 100);
            result += "  第3个分支(远程武器)正确: " + (test7 ? "✓通过" : "✗失败") + "\n";
        } else {
            var test5:Boolean = false;
            var test6:Boolean = false;
            var test7:Boolean = false;
            result += "  分支内容验证跳过（匹配数量不足）\n";
        }

        // 测试语义正确性：只有"手枪"装备时，不应该匹配任何分支
        var pistolLookup:Object = ModRegistry.buildItemUseLookup("手枪", null);
        var pistolMatched:Array = ModRegistry.matchUseSwitchAll(multiMod, pistolLookup);
        var test8:Boolean = (pistolMatched.length == 0);
        result += "  手枪装备不匹配任何分支: " + (test8 ? "✓通过" : "✗失败") + "\n";

        var allPassed:Boolean = test1 && test2 && test3 && test4 && test5 && test6 && test7 && test8;
        result += "\n  总体结果: " + (allPassed ? "✓ 所有useSwitch测试通过（含多分支）" : "✗ 有测试失败");

        return result;
    }
}