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
        report += "    装备系统测试套件 v3.0\n";
        report += "========================================\n\n";

        var startTime:Number = getTimer();

        // 初始化测试环境
        initTestEnvironment();

        // 1. PropertyOperators 测试（含边界精度）
        report += "【1. PropertyOperators 测试】\n";
        report += testPropertyOperators();
        report += "\n";

        // 2. ModRegistry 测试（性能+归一化）
        report += "【2. ModRegistry 测试】\n";
        report += testModRegistry();
        report += "\n";

        // 3. TagManager 状态码矩阵测试
        report += "【3. TagManager 状态码测试】\n";
        report += testTagManager();
        report += "\n";

        // 4. TierSystem 测试
        report += "【4. TierSystem 测试】\n";
        report += testTierSystem();
        report += "\n";

        // 5. EquipmentCalculator 测试（修正项顺序）
        report += "【5. EquipmentCalculator 测试】\n";
        report += testEquipmentCalculator();
        report += "\n";

        // 6. 集成测试
        report += "【6. 集成测试】\n";
        report += runIntegrationTest();
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

        // 基础功能测试
        results.push(testPropertyOperators_Add());
        results.push(testPropertyOperators_Multiply());
        results.push(testPropertyOperators_Override());
        results.push(testPropertyOperators_Merge());
        results.push(testPropertyOperators_ApplyCap());

        // P1: 边界精度测试
        results.push(testPropertyOperators_Add_Boundaries());
        results.push(testPropertyOperators_Multiply_DecimalProp());
        results.push(testPropertyOperators_Multiply_Boundaries());
        results.push(testPropertyOperators_Merge_NumberLogic());
        results.push(testPropertyOperators_ApplyCap_AllCases());

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

    // ---------- P1: 边界精度测试 ----------

    /**
     * add 边界测试：initValue 语义、NaN跳过、null/空对象早退
     */
    private static function testPropertyOperators_Add_Boundaries():String {
        // 测试 initValue：prop没有该键时用 initValue 起步
        var prop1:Object = {damage: 10};
        PropertyOperators.add(prop1, {hp: 50}, 100);  // hp不存在，用initValue=100起步
        var initValuePassed:Boolean = (prop1.hp == 150);  // 100 + 50 = 150

        // 测试 NaN 跳过
        var prop2:Object = {damage: 10};
        PropertyOperators.add(prop2, {damage: Number.NaN, defence: 20}, 0);
        var nanPassed:Boolean = (prop2.damage == 10 && prop2.defence == 20);

        // 测试 null/空对象早退
        var prop3:Object = {damage: 10};
        PropertyOperators.add(prop3, null, 0);
        PropertyOperators.add(prop3, {}, 0);
        var nullPassed:Boolean = (prop3.damage == 10);

        var allPassed:Boolean = initValuePassed && nanPassed && nullPassed;

        if (!allPassed) {
            return "✗ add边界测试失败（initValue=" + prop1.hp + "，期望150；NaN跳过=" + prop2.damage + "）";
        }

        return "✓ add边界测试通过";
    }

    /**
     * multiply decimalPropDict 测试：验证小数属性保留一位小数
     */
    private static function testPropertyOperators_Multiply_DecimalProp():String {
        // 设置小数精度字典
        PropertyOperators.setDecimalPropDict({weight: 1, rout: 1});

        // weight 在 decimalPropDict 中，应保留一位小数
        var prop1:Object = {weight: 1.23, damage: 100};
        PropertyOperators.multiply(prop1, {weight: 1.11, damage: 1.11});

        // weight: 1.23 * 1.11 = 1.3653，四舍五入到一位小数 = 1.4
        // damage: 100 * 1.11 = 111，整数
        // 使用容差比较避免浮点精度问题
        var weightPassed:Boolean = (Math.abs(prop1.weight - 1.4) < 0.001);
        var damagePassed:Boolean = (prop1.damage == 111);

        // 测试负数的一位小数舍入
        var prop2:Object = {weight: -1.23};
        PropertyOperators.multiply(prop2, {weight: 1.11});
        // -1.23 * 1.11 = -1.3653，远离0舍入 = -1.4
        var negWeightPassed:Boolean = (Math.abs(prop2.weight - (-1.4)) < 0.001);

        var allPassed:Boolean = weightPassed && damagePassed && negWeightPassed;

        if (!allPassed) {
            return "✗ multiply小数测试失败（weight=" + prop1.weight + "，期望1.4；damage=" + prop1.damage +
                   "，期望111；负weight=" + prop2.weight + "，期望-1.4）";
        }

        return "✓ multiply小数精度测试通过";
    }

    /**
     * multiply 边界测试：0/NaN 跳过
     */
    private static function testPropertyOperators_Multiply_Boundaries():String {
        // 测试 damage=0 时乘以任何数仍为0（被跳过不写回）
        var prop1:Object = {damage: 0};
        PropertyOperators.multiply(prop1, {damage: 2});
        var zeroPassed:Boolean = (prop1.damage == 0);

        // 测试 multiProp 的值为 NaN 时跳过
        var prop2:Object = {damage: 100};
        PropertyOperators.multiply(prop2, {damage: Number.NaN});
        var nanPassed:Boolean = (prop2.damage == 100);

        // 测试 null 早退
        var prop3:Object = {damage: 100};
        PropertyOperators.multiply(prop3, null);
        var nullPassed:Boolean = (prop3.damage == 100);

        var allPassed:Boolean = zeroPassed && nanPassed && nullPassed;

        if (!allPassed) {
            return "✗ multiply边界测试失败（zero=" + prop1.damage + "，NaN=" + prop2.damage + "）";
        }

        return "✓ multiply边界测试通过";
    }

    /**
     * merge 数字逻辑测试：正负数竞争规则
     */
    private static function testPropertyOperators_Merge_NumberLogic():String {
        // 两个正数取 max
        var prop1:Object = {damage: 100};
        PropertyOperators.merge(prop1, {damage: 150});
        var positivePassed:Boolean = (prop1.damage == 150);

        // 两个负数取 min（更负的）
        var prop2:Object = {damage: -10};
        PropertyOperators.merge(prop2, {damage: -20});
        var negativePassed:Boolean = (prop2.damage == -20);

        // 一正一负时取 min（负数优先作为debuff）
        var prop3:Object = {damage: 100};
        PropertyOperators.merge(prop3, {damage: -50});
        var mixedPassed:Boolean = (prop3.damage == -50);

        // 非 number 类型直接覆盖
        var prop4:Object = {name: "旧名称"};
        PropertyOperators.merge(prop4, {name: "新名称"});
        var stringPassed:Boolean = (prop4.name == "新名称");

        var allPassed:Boolean = positivePassed && negativePassed && mixedPassed && stringPassed;

        if (!allPassed) {
            return "✗ merge数字逻辑测试失败（正正=" + prop1.damage + "，负负=" + prop2.damage +
                   "，混合=" + prop3.damage + "）";
        }

        return "✓ merge数字逻辑测试通过";
    }

    /**
     * applyCap 全场景测试
     */
    private static function testPropertyOperators_ApplyCap_AllCases():String {
        // 有 baseProp 时：正 cap（上限）
        var prop1:Object = {damage: 180};
        var base1:Object = {damage: 100};
        PropertyOperators.applyCap(prop1, {damage: 50}, base1);  // 最多增加50
        var posCapPassed:Boolean = (prop1.damage == 150);  // 100 + 50

        // 有 baseProp 时：负 cap（下限）
        var prop2:Object = {damage: 40};
        var base2:Object = {damage: 100};
        PropertyOperators.applyCap(prop2, {damage: -30}, base2);  // 最多减少30
        var negCapPassed:Boolean = (prop2.damage == 70);  // 100 - 30

        // 无 baseProp 时：正 cap 限制绝对值上限
        var prop3:Object = {damage: 200};
        PropertyOperators.applyCap(prop3, {damage: 150}, null);
        var absMaxPassed:Boolean = (prop3.damage == 150);

        // 无 baseProp 时：负 cap 限制绝对值下限
        var prop4:Object = {damage: 30};
        PropertyOperators.applyCap(prop4, {damage: -50}, null);  // 最小值为50
        var absMinPassed:Boolean = (prop4.damage == 50);

        // cap 为 0 时跳过
        var prop5:Object = {damage: 200};
        PropertyOperators.applyCap(prop5, {damage: 0}, {damage: 100});
        var zeroCapPassed:Boolean = (prop5.damage == 200);

        // 属性不存在时跳过
        var prop6:Object = {};
        PropertyOperators.applyCap(prop6, {damage: 50}, {damage: 100});
        var missingPassed:Boolean = (prop6.damage == undefined);

        var allPassed:Boolean = posCapPassed && negCapPassed && absMaxPassed &&
                                absMinPassed && zeroCapPassed && missingPassed;

        if (!allPassed) {
            return "✗ applyCap全场景测试失败（正cap=" + prop1.damage + "，负cap=" + prop2.damage +
                   "，绝对上限=" + prop3.damage + "，绝对下限=" + prop4.damage + "）";
        }

        return "✓ applyCap全场景测试通过";
    }

    // ==================== ModRegistry 测试 ====================

    /**
     * 运行 ModRegistry 测试（性能 + 归一化回归）
     */
    private static function testModRegistry():String {
        var result:String = "";

        result += testModRegistry_Performance();
        result += testModRegistry_NormalizationOnce();
        result += testModRegistry_UseSwitchNormalization();

        return result;
    }

    /**
     * 运行 ModRegistry 性能测试
     */
    private static function testModRegistry_Performance():String {
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
        result += passed ? "✓ ModRegistry 性能测试通过\n" : "✗ ModRegistry 性能测试失败\n";

        return result;
    }

    /**
     * P0: 归一化只处理一次测试
     * 防止 percentage/multiplier 重复乘以 0.01
     * 注意：归一化只作用于 stats.percentage 和 stats.multiplier，不是顶层字段
     */
    private static function testModRegistry_NormalizationOnce():String {
        // 创建测试配件：stats.percentage/multiplier 内的值应被归一化
        // percentage: {defence: 50} 应归一化为 {defence: 0.5}
        var testMod:Object = {
            name: "归一化测试配件",
            use: "头部装备",
            stats: {
                percentage: {defence: 50},     // 期望归一化后为 0.5
                multiplier: {defence: 200}     // 期望归一化后为 2.0
            }
        };

        // 第一次加载
        ModRegistry.loadModData([testMod]);
        var modData1:Object = ModRegistry.getModData("归一化测试配件");
        var percentage1:Number = modData1.stats.percentage.defence;
        var multiplier1:Number = modData1.stats.multiplier.defence;

        // 验证第一次归一化结果
        var firstPassed:Boolean = (percentage1 == 0.5 && multiplier1 == 2.0);

        // 测试重复加载同一对象不会二次归一化
        // 注意：loadModData 每次传入新对象会重新处理，所以这里测试的是
        // 归一化后的值是否正确，而不是"同一对象多次调用"
        ModRegistry.loadModData([{
            name: "归一化测试配件2",
            use: "头部装备",
            stats: {
                percentage: {defence: 50},
                multiplier: {defence: 200}
            }
        }]);
        var modData2:Object = ModRegistry.getModData("归一化测试配件2");
        var percentage2:Number = modData2.stats.percentage.defence;
        var multiplier2:Number = modData2.stats.multiplier.defence;

        var secondPassed:Boolean = (percentage2 == 0.5 && multiplier2 == 2.0);

        var passed:Boolean = firstPassed && secondPassed;

        if (!passed) {
            return "✗ 归一化测试失败（第一次: p=" + percentage1 + ", m=" + multiplier1 +
                   "；第二次: p=" + percentage2 + ", m=" + multiplier2 + "）\n";
        }

        return "✓ 归一化只处理一次测试通过\n";
    }

    /**
     * P0: useSwitch 内的 percentage/multiplier 归一化测试
     */
    private static function testModRegistry_UseSwitchNormalization():String {
        var testMod:Object = {
            name: "useSwitch归一化测试",
            use: "头部装备",
            stats: {
                useSwitch: {
                    use: [
                        {name: "头部装备", percentage: {defence: 30}},  // 期望 0.3
                        {name: "上装装备", multiplier: {defence: 150}}  // 期望 1.5
                    ]
                }
            }
        };

        ModRegistry.loadModData([testMod]);
        var modData:Object = ModRegistry.getModData("useSwitch归一化测试");

        if (!modData || !modData.stats || !modData.stats.useSwitch || !modData.stats.useSwitch.useCases) {
            return "✗ useSwitch归一化测试失败（数据结构缺失）\n";
        }

        var useCases:Array = modData.stats.useSwitch.useCases;
        var case0:Object = useCases[0];
        var case1:Object = useCases[1];

        var passed:Boolean = (
            case0.percentage.defence == 0.3 &&
            case1.multiplier.defence == 1.5
        );

        if (!passed) {
            return "✗ useSwitch归一化测试失败（case0.percentage.defence=" +
                   case0.percentage.defence + "，期望0.3；case1.multiplier.defence=" +
                   case1.multiplier.defence + "，期望1.5）\n";
        }

        return "✓ useSwitch 归一化测试通过\n";
    }

    // ==================== TagManager 测试 ====================

    /**
     * 运行 TagManager 测试
     * P0: 状态码矩阵测试 - 覆盖所有9个返回码
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
            },
            // 状态码矩阵测试用
            {
                name: "普通插件",
                use: "头部装备"
            },
            {
                name: "战技插件",
                use: "头部装备",
                skill: {name: "测试战技", damage: 100}
            },
            {
                name: "缺tag插件",
                use: "头部装备",
                requireTags: "不存在的结构"
            },
            {
                name: "被禁止tag插件",
                use: "头部装备",
                tag: "被禁止的挂点"
            }
        ]);

        // 基础功能测试
        result += testTagManager_BasicDependency();
        result += testTagManager_TagExclusion();
        result += testTagManager_DependencyChain();

        // P0: 状态码矩阵测试
        result += testTagManager_StatusCode_Available();      // 1
        result += testTagManager_StatusCode_ModNotExist();    // 0
        result += testTagManager_StatusCode_SlotFull();       // -1
        result += testTagManager_StatusCode_AlreadyEquipped();// -2
        result += testTagManager_StatusCode_SkillConflict();  // -4
        result += testTagManager_StatusCode_SameTag();        // -8
        result += testTagManager_StatusCode_MissingTag();     // -16
        result += testTagManager_StatusCode_DependentMods();  // -32
        result += testTagManager_StatusCode_BlockedTag();     // -64

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

    // ---------- 状态码矩阵测试 ----------

    /**
     * 状态码 1: 允许装备
     */
    private static function testTagManager_StatusCode_Available():String {
        var testItem = {
            name: "测试装备",
            value: { mods: [] }
        };
        var testItemData = { data: { modslot: 3 } };

        var code:Number = TagManager.checkModAvailability(testItem, testItemData, "普通插件");
        var passed:Boolean = (code == 1);

        return passed ? "✓ 状态码1(可装备)测试通过\n" : "✗ 状态码1测试失败（返回" + code + "）\n";
    }

    /**
     * 状态码 0: 配件不存在 / itemData 为空
     */
    private static function testTagManager_StatusCode_ModNotExist():String {
        var testItem = {
            name: "测试装备",
            value: { mods: [] }
        };
        var testItemData = { data: { modslot: 3 } };

        // 测试不存在的配件
        var code1:Number = TagManager.checkModAvailability(testItem, testItemData, "不存在的配件");

        // 测试 itemData.data 为空
        var code2:Number = TagManager.checkModAvailability(testItem, {}, "普通插件");

        var passed:Boolean = (code1 == 0 && code2 == 0);

        return passed ? "✓ 状态码0(不存在)测试通过\n" :
               "✗ 状态码0测试失败（配件不存在=" + code1 + "，数据为空=" + code2 + "）\n";
    }

    /**
     * 状态码 -1: 槽位已满
     */
    private static function testTagManager_StatusCode_SlotFull():String {
        var testItem = {
            name: "测试装备",
            value: { mods: ["占位插件A"] }  // 已有1个配件
        };
        var testItemData = { data: { modslot: 1 } };  // 最多1个槽位

        var code:Number = TagManager.checkModAvailability(testItem, testItemData, "普通插件");
        var passed:Boolean = (code == -1);

        return passed ? "✓ 状态码-1(槽位满)测试通过\n" : "✗ 状态码-1测试失败（返回" + code + "）\n";
    }

    /**
     * 状态码 -2: 已装备同名配件
     */
    private static function testTagManager_StatusCode_AlreadyEquipped():String {
        var testItem = {
            name: "测试装备",
            value: { mods: ["普通插件"] }
        };
        var testItemData = { data: { modslot: 3 } };

        var code:Number = TagManager.checkModAvailability(testItem, testItemData, "普通插件");
        var passed:Boolean = (code == -2);

        return passed ? "✓ 状态码-2(已装备)测试通过\n" : "✗ 状态码-2测试失败（返回" + code + "）\n";
    }

    /**
     * 状态码 -4: 已有战技
     */
    private static function testTagManager_StatusCode_SkillConflict():String {
        var testItem = {
            name: "测试装备",
            value: { mods: [] }
        };
        var testItemData = {
            data: { modslot: 3 },
            skill: { name: "装备自带战技" }  // 装备已有战技
        };

        var code:Number = TagManager.checkModAvailability(testItem, testItemData, "战技插件");
        var passed:Boolean = (code == -4);

        return passed ? "✓ 状态码-4(战技冲突)测试通过\n" : "✗ 状态码-4测试失败（返回" + code + "）\n";
    }

    /**
     * 状态码 -8: 同tag插件已装备
     */
    private static function testTagManager_StatusCode_SameTag():String {
        var testItem = {
            name: "测试装备",
            value: { mods: ["占位插件A"] }  // tag为"槽位1"
        };
        var testItemData = { data: { modslot: 3 } };

        // 尝试装备同tag的占位插件B
        var code:Number = TagManager.checkModAvailability(testItem, testItemData, "占位插件B");
        var passed:Boolean = (code == -8);

        return passed ? "✓ 状态码-8(同tag)测试通过\n" : "✗ 状态码-8测试失败（返回" + code + "）\n";
    }

    /**
     * 状态码 -16: 缺少前置tag
     */
    private static function testTagManager_StatusCode_MissingTag():String {
        var testItem = {
            name: "测试装备",
            value: { mods: [] }  // 没有安装任何提供tag的插件
        };
        var testItemData = { data: { modslot: 3 } };

        var code:Number = TagManager.checkModAvailability(testItem, testItemData, "缺tag插件");
        var passed:Boolean = (code == -16);

        return passed ? "✓ 状态码-16(缺tag)测试通过\n" : "✗ 状态码-16测试失败（返回" + code + "）\n";
    }

    /**
     * 状态码 -32: 有其他插件依赖此插件（通过 canRemoveMod 测试）
     */
    private static function testTagManager_StatusCode_DependentMods():String {
        var testItem = {
            name: "测试装备",
            value: { mods: ["插件A", "插件B"] }  // 插件B依赖插件A提供的"结构A"
        };

        // canRemoveMod 检查是否可以安全移除
        var code:Number = TagManager.canRemoveMod(testItem, "插件A");
        var passed:Boolean = (code == -32);

        return passed ? "✓ 状态码-32(有依赖)测试通过\n" : "✗ 状态码-32测试失败（返回" + code + "）\n";
    }

    /**
     * 状态码 -64: 装备禁止该挂点类插件
     */
    private static function testTagManager_StatusCode_BlockedTag():String {
        var testItem = {
            name: "测试装备",
            value: { mods: [] }
        };
        var testItemData = {
            data: { modslot: 3 },
            blockedTags: "被禁止的挂点"  // 禁止该挂点类型
        };

        var code:Number = TagManager.checkModAvailability(testItem, testItemData, "被禁止tag插件");
        var passed:Boolean = (code == -64);

        return passed ? "✓ 状态码-64(被禁止)测试通过\n" : "✗ 状态码-64测试失败（返回" + code + "）\n";
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

    // ==================== EquipmentCalculator 测试 ====================

    /**
     * P1: EquipmentCalculator 测试
     * 验证修正项应用顺序和各种计算场景
     */
    private static function testEquipmentCalculator():String {
        var result:String = "";

        result += testEquipmentCalculator_LevelBounds();
        result += testEquipmentCalculator_ModifierOrder();
        result += testEquipmentCalculator_PureVsNormal();
        result += testEquipmentCalculator_UseSwitchMatching();

        return result;
    }

    /**
     * 等级边界测试
     * level=1不产生倍率，level>maxLevel被clamp
     */
    private static function testEquipmentCalculator_LevelBounds():String {
        // 重新加载配置以确保状态一致
        EquipmentConfigManager.loadConfig({
            levelStatList: [1, 1.06, 1.14, 1.24, 1.36],
            decimalPropDict: {weight: 1}
        });

        var itemData:Object = {
            name: "测试装备",
            use: "头部装备",
            data: { defence: 100 }
        };

        var cfg:Object = EquipmentConfigManager.getFullConfig();

        // level=1 时不应用倍率
        var result1:Object = EquipmentCalculator.calculatePure(itemData, {level: 1, mods: []}, cfg, {});

        // level 超出上限时被 clamp 到 maxLevel
        var result2:Object = EquipmentCalculator.calculatePure(itemData, {level: 100, mods: []}, cfg, {});

        // levelStatList[4] = 1.36，defence = 100 * 1.36 = 136
        var passed:Boolean = (result1.data.defence == 100 && result2.data.defence == 136);

        if (!passed) {
            return "✗ 等级边界测试失败（level=1: " + result1.data.defence + "，期望100；" +
                   "level=100: " + result2.data.defence + "，期望136）\n";
        }

        return "✓ 等级边界测试通过\n";
    }

    /**
     * P1: 修正项顺序测试
     * 验证顺序：multiply → multiplierZone → add → override → merge → cap
     */
    private static function testEquipmentCalculator_ModifierOrder():String {
        EquipmentConfigManager.loadConfig({
            levelStatList: [1, 1.0],  // level=1不产生倍率
            decimalPropDict: {}
        });

        // 创建测试配件，验证修正项顺序
        // 基础值100，percentage=0.5(+50%)，multiplier=2.0(×2)，flat=10，override=300，cap=50
        ModRegistry.loadModData([
            {
                name: "顺序测试配件",
                use: "头部装备",
                stats: {
                    percentage: { defence: 0.5 },    // +50% = 150
                    multiplier: { defence: 2.0 },    // ×2 = 300
                    flat: { defence: 10 },           // +10 = 310
                    override: { hp: 999 }            // hp强制设为999
                }
            }
        ]);

        var itemData:Object = {
            name: "测试装备",
            use: "头部装备",
            data: { defence: 100, hp: 50 }
        };

        var value:Object = {
            level: 1,
            mods: ["顺序测试配件"]
        };

        var cfg:Object = EquipmentConfigManager.getFullConfig();

        // 【修复】第4个参数应该是 modRegistry（modName -> modInfo 映射），不是 itemUseLookup
        var modRegistry:Object = {
            顺序测试配件: ModRegistry.getModData("顺序测试配件")
        };

        var result:Object = EquipmentCalculator.calculatePure(itemData, value, cfg, modRegistry);

        // 验证计算结果：
        // defence: 100 * 1.5 = 150 (percentage) → 150 * 2.0 = 300 (multiplier) → 300 + 10 = 310 (flat)
        // hp: override = 999
        var defencePassed:Boolean = (result.data.defence == 310);
        var hpPassed:Boolean = (result.data.hp == 999);

        if (!defencePassed || !hpPassed) {
            return "✗ 修正项顺序测试失败（defence=" + result.data.defence + "，期望310；" +
                   "hp=" + result.data.hp + "，期望999）\n";
        }

        return "✓ 修正项顺序测试通过\n";
    }

    /**
     * calculatePure vs calculate 测试
     * calculatePure不修改原对象，calculate会就地修改
     */
    private static function testEquipmentCalculator_PureVsNormal():String {
        EquipmentConfigManager.loadConfig({
            levelStatList: [1, 1.5],
            decimalPropDict: {}
        });

        var originalData:Object = {
            name: "测试装备",
            use: "头部装备",
            data: { defence: 100 }
        };

        var value:Object = { level: 1, mods: [] };
        var cfg:Object = EquipmentConfigManager.getFullConfig();

        // calculatePure 不应修改原对象
        var pureResult:Object = EquipmentCalculator.calculatePure(originalData, value, cfg, {});

        var pureNotModified:Boolean = (originalData.data.defence == 100);

        if (!pureNotModified) {
            return "✗ calculatePure测试失败（原对象被修改为" + originalData.data.defence + "）\n";
        }

        return "✓ calculatePure不修改原对象测试通过\n";
    }

    /**
     * useSwitch 多分支匹配测试
     */
    private static function testEquipmentCalculator_UseSwitchMatching():String {
        EquipmentConfigManager.loadConfig({
            levelStatList: [1, 1.0],
            decimalPropDict: {}
        });

        // 创建带 useSwitch 的配件
        ModRegistry.loadModData([
            {
                name: "多分支配件",
                use: "头部装备,上装装备",
                stats: {
                    useSwitch: {
                        use: [
                            {name: "头部装备", percentage: {defence: 10}},      // 归一化后 0.1
                            {name: "上装装备", percentage: {defence: 20}}       // 归一化后 0.2
                        ]
                    }
                }
            }
        ]);

        var itemData:Object = {
            name: "测试头盔",
            use: "头部装备",
            data: { defence: 100 }
        };

        var value:Object = { level: 1, mods: ["多分支配件"] };
        var cfg:Object = EquipmentConfigManager.getFullConfig();

        // 【修复】第4个参数应该是 modRegistry（modName -> modInfo 映射），不是 itemUseLookup
        var modRegistry:Object = {
            多分支配件: ModRegistry.getModData("多分支配件")
        };

        var result:Object = EquipmentCalculator.calculatePure(itemData, value, cfg, modRegistry);

        // 100 * (1 + 0.1) = 110
        var passed:Boolean = (result.data.defence == 110);

        if (!passed) {
            return "✗ useSwitch匹配测试失败（defence=" + result.data.defence + "，期望110）\n";
        }

        return "✓ useSwitch多分支匹配测试通过\n";
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
