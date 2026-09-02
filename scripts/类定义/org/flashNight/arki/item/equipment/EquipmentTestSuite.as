import org.flashNight.arki.item.equipment.*;
import org.flashNight.arki.item.EquipmentUtil;
import org.flashNight.arki.item.BaseItem;
import org.flashNight.arki.unit.Action.Melee.SwitchStrikeCore;

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

        // 7. 性能测试（富属性计算开销评估）
        report += "【7. 性能测试】\n";
        report += runPerformanceTests();
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
        results.push(testPropertyOperators_ApplyCurve());
        results.push(testPropertyOperators_Override());
        results.push(testPropertyOperators_Merge());
        results.push(testPropertyOperators_ApplyCap());

        // P1: 边界精度测试
        results.push(testPropertyOperators_Add_Boundaries());
        results.push(testPropertyOperators_Multiply_DecimalProp());
        results.push(testPropertyOperators_Multiply_Boundaries());
        results.push(testPropertyOperators_Merge_NumberLogic());
        results.push(testPropertyOperators_Merge_StringLogic());
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

    private static function testPropertyOperators_ApplyCurve():String {
        var prop:Object = {
            d0: 0,
            d1: 1,
            d2: 2,
            d3: 3,
            d4: 4,
            d5: 5,
            d6: 6,
            d7: 7,
            d8: 8
        };
        var curve:Object = {
            d0: 1.414,
            d1: 1.414,
            d2: 1.414,
            d3: 1.414,
            d4: 1.414,
            d5: 1.414,
            d6: 1.414,
            d7: 1.414,
            d8: 1.414
        };

        PropertyOperators.applyCurve(prop, curve);

        var passed:Boolean = (
            prop.d0 == 0 &&
            prop.d1 == 1 &&
            prop.d2 == 2 &&
            prop.d3 == 2 &&
            prop.d4 == 3 &&
            prop.d5 == 3 &&
            prop.d6 == 3 &&
            prop.d7 == 4 &&
            prop.d8 == 4
        );

        if (!passed) {
            return "✗ applyCurve 测试失败（0..8=" + prop.d0 + "," + prop.d1 + "," + prop.d2 + "," +
                   prop.d3 + "," + prop.d4 + "," + prop.d5 + "," + prop.d6 + "," + prop.d7 + "," + prop.d8 + "）";
        }

        return "✓ applyCurve 测试通过";
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

        var allPassed:Boolean = positivePassed && negativePassed && mixedPassed;

        if (!allPassed) {
            return "✗ merge数字逻辑测试失败（正正=" + prop1.damage + "，负负=" + prop2.damage +
                   "，混合=" + prop3.damage + "）";
        }

        return "✓ merge数字逻辑测试通过";
    }

    /**
     * merge 字符串逻辑测试：前缀保留拼接（通用规则）
     *
     * 适用于所有字符串属性，支持任意 "{前缀}-{后缀}" 格式。
     * 合并规则：
     * - 新值有连接符：直接使用新值（视为完整格式）
     * - 原值有连接符：保留原值前缀，替换后缀
     * - 都无连接符：直接使用新值（等同于普通覆盖）
     */
    private static function testPropertyOperators_Merge_StringLogic():String {
        // 测试1：原值有连接符，新值无连接符 → 保留前缀，替换后缀
        // "横向联弹-普通子弹" + "次级穿刺子弹" → "横向联弹-次级穿刺子弹"
        var prop1:Object = {bullet: "横向联弹-普通子弹"};
        PropertyOperators.merge(prop1, {bullet: "次级穿刺子弹"});
        var case1Passed:Boolean = (prop1.bullet == "横向联弹-次级穿刺子弹");

        // 测试2：原值有连接符，新值也有连接符 → 完整覆盖
        // "横向联弹-普通子弹" + "纵向联弹-穿甲子弹" → "纵向联弹-穿甲子弹"
        var prop2:Object = {bullet: "横向联弹-普通子弹"};
        PropertyOperators.merge(prop2, {bullet: "纵向联弹-穿甲子弹"});
        var case2Passed:Boolean = (prop2.bullet == "纵向联弹-穿甲子弹");

        // 测试3：原值无连接符，新值无连接符 → 直接替换
        // "普通子弹" + "次级穿刺子弹" → "次级穿刺子弹"
        var prop3:Object = {bullet: "普通子弹"};
        PropertyOperators.merge(prop3, {bullet: "次级穿刺子弹"});
        var case3Passed:Boolean = (prop3.bullet == "次级穿刺子弹");

        // 测试4：原值无连接符，新值有连接符 → 直接使用新值
        // "普通子弹" + "横向联弹-穿甲子弹" → "横向联弹-穿甲子弹"
        var prop4:Object = {bullet: "普通子弹"};
        PropertyOperators.merge(prop4, {bullet: "横向联弹-穿甲子弹"});
        var case4Passed:Boolean = (prop4.bullet == "横向联弹-穿甲子弹");

        // 测试5：非联弹格式的普通字符串（无连接符）仍然正常工作
        var prop5:Object = {name: "旧名称"};
        PropertyOperators.merge(prop5, {name: "新名称"});
        var case5Passed:Boolean = (prop5.name == "新名称");

        var allPassed:Boolean = case1Passed && case2Passed && case3Passed && case4Passed && case5Passed;

        if (!allPassed) {
            return "✗ merge字符串逻辑测试失败（" +
                   "保留前缀=" + prop1.bullet + "，期望横向联弹-次级穿刺子弹；" +
                   "完整覆盖=" + prop2.bullet + "，期望纵向联弹-穿甲子弹；" +
                   "无前缀替换=" + prop3.bullet + "，期望次级穿刺子弹；" +
                   "新值有符号=" + prop4.bullet + "，期望横向联弹-穿甲子弹）";
        }

        return "✓ merge字符串逻辑测试通过";
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
        result += testModRegistry_QualifiedUseSwitchMatching();

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

    /**
     * useSwitch 限定字段匹配测试。
     * 保证旧的无前缀 name 继续匹配 use/weapontype 联合集合，同时允许精确区分两者。
     */
    private static function testModRegistry_QualifiedUseSwitchMatching():String {
        ModRegistry.loadModData([{
            name: "限定字段匹配测试",
            use: "手枪",
            stats: {
                useSwitch: {
                    use: [
                        {name: "手枪", flat: {legacyHit: 1}},
                        {name: "use:手枪", flat: {useHit: 1}},
                        {name: "weapontype:手枪", flat: {weaponTypeHit: 1}}
                    ]
                }
            }
        }]);

        var modData:Object = ModRegistry.getModData("限定字段匹配测试");
        var standardHandgun:Object = ModRegistry.buildItemUseLookup("手枪", "手枪", null);
        var machinePistol:Object = ModRegistry.buildItemUseLookup("手枪", "冲锋枪", null);
        var standardMatches:Array = ModRegistry.matchUseSwitchAll(modData, standardHandgun);
        var machinePistolMatches:Array = ModRegistry.matchUseSwitchAll(modData, machinePistol);

        var lookupPassed:Boolean = (
            standardHandgun["手枪"] == true &&
            standardHandgun["use:手枪"] == true &&
            standardHandgun["weapontype:手枪"] == true &&
            machinePistol["手枪"] == true &&
            machinePistol["use:手枪"] == true &&
            machinePistol["weapontype:冲锋枪"] == true &&
            machinePistol["weapontype:手枪"] != true
        );
        var matchPassed:Boolean = (standardMatches.length == 3 && machinePistolMatches.length == 2);

        if (!lookupPassed || !matchPassed) {
            return "✗ useSwitch限定字段匹配测试失败（普通手枪=" + standardMatches.length +
                   "，冲锋手枪=" + machinePistolMatches.length + "）\n";
        }

        return "✓ useSwitch限定字段匹配测试通过\n";
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
                name: "插件A备用",
                use: "头部装备",
                provideTags: "结构A"
            },
            {
                name: "插件B",
                use: "头部装备",
                requireTags: "结构A"
            },
            // useSwitch.requireTags 条件依赖测试用
            {
                name: "供电模块",
                use: "长枪",
                provideTags: "电力"
            },
            {
                name: "条件供电插件",
                use: "长枪",
                stats: {
                    useSwitch: {
                        use: {
                            name: "weapontype:机枪,weapontype:压制机枪",
                            requireTags: "电力"
                        }
                    }
                }
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
            },
            // installCondition 安装条件测试用
            {
                name: "条件插件_魔法高间隔",
                use: "头部装备,长枪",
                installCondition: {
                    cond: [
                        {op: "is", path: "data.damagetype", value: "魔法"},
                        {op: "above", path: "data.interval", value: 200}
                    ]
                }
            },
            {
                name: "条件插件_轻武器",
                use: "头部装备,长枪",
                installCondition: {
                    cond: {op: "atMost", path: "data.weight", value: 3}
                }
            },
            {
                name: "条件插件_OR模式",
                use: "头部装备,长枪",
                installCondition: {
                    mode: "any",
                    cond: [
                        {op: "is", path: "data.damagetype", value: "魔法"},
                        {op: "above", path: "data.interval", value: 500}
                    ]
                }
            },
            {
                name: "条件插件_嵌套路径",
                use: "头部装备,长枪",
                installCondition: {
                    cond: {op: "atLeast", path: "data.magicdefence.电", value: 10}
                }
            },
            {
                name: "条件插件_current作用域",
                use: "头部装备,长枪",
                installCondition: {
                    scope: "current",
                    cond: {op: "is", path: "data.damagetype", value: "破击"}
                }
            },
            // group 嵌套测试：(damagetype=="魔法" AND interval>200) OR (damagetype=="破击")
            {
                name: "条件插件_嵌套组",
                use: "头部装备,长枪",
                installCondition: {
                    mode: "any",
                    cond: [
                        {op: "is", path: "data.damagetype", value: "破击"}
                    ],
                    group: {
                        mode: "all",
                        cond: [
                            {op: "is", path: "data.damagetype", value: "魔法"},
                            {op: "above", path: "data.interval", value: 200}
                        ]
                    }
                }
            }
        ]);

        // 基础功能测试
        result += testTagManager_BasicDependency();
        result += testTagManager_TagExclusion();
        result += testTagManager_DependencyChain();
        result += testTagManager_ConditionalDependency();

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
        result += testTagManager_StatusCode_InstallCondition(); // -256

        // installCondition 详细测试
        result += testInstallCondition_Operators();
        result += testInstallCondition_DotPath();
        result += testInstallCondition_ModeAny();
        result += testInstallCondition_ScopeCurrent();
        result += testInstallCondition_GroupNesting();

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
        var redundantProviderItem = {
            name: "测试装备",
            value: {
                mods: ["插件A", "插件A备用", "插件B"]
            }
        };
        var redundantDependents:Array = TagManager.getDependentMods(
            redundantProviderItem, "插件A");
        var keepsSupportedMod:Boolean = redundantDependents.length == 0;

        return hasDependent && keepsSupportedMod
            ? "✓ 依赖链测试通过\n"
            : "✗ 依赖链测试失败（唯一提供者依赖数=" + dependents.length
                + "，冗余提供者依赖数=" + redundantDependents.length + "）\n";
    }

    /**
     * useSwitch.requireTags 只在指定武器类型上生效，并同时影响单项安装检查和候选过滤。
     */
    private static function testTagManager_ConditionalDependency():String {
        var machineItem = {
            name: "测试机枪",
            value: { mods: [] }
        };
        var poweredMachineItem = {
            name: "测试机枪",
            value: { mods: ["供电模块"] }
        };
        var machineData:Object = {
            use: "长枪",
            weapontype: "机枪",
            data: { modslot: 3 }
        };
        var rifleData:Object = {
            use: "长枪",
            weapontype: "突击步枪",
            data: { modslot: 3 }
        };

        var missingPower:Number = TagManager.checkModAvailability(machineItem, machineData, "条件供电插件");
        var hasPower:Number = TagManager.checkModAvailability(poweredMachineItem, machineData, "条件供电插件");
        var rifleBypass:Number = TagManager.checkModAvailability(machineItem, rifleData, "条件供电插件");
        var filteredWithoutPower:Array = TagManager.filterAvailableMods(["条件供电插件"], machineItem, machineData);
        var filteredWithPower:Array = TagManager.filterAvailableMods(["条件供电插件"], poweredMachineItem, machineData);

        var passed:Boolean = (
            missingPower == -16 &&
            hasPower == 1 &&
            rifleBypass == 1 &&
            filteredWithoutPower.length == 0 &&
            filteredWithPower.length == 1
        );

        return passed
            ? "✓ useSwitch 条件供电依赖测试通过\n"
            : "✗ useSwitch 条件供电依赖测试失败（无电=" + missingPower +
              "，有电=" + hasPower + "，非机枪=" + rifleBypass +
              "，过滤=" + filteredWithoutPower.length + "/" + filteredWithPower.length + "）\n";
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

    /**
     * 状态码 -256: 装备属性不满足安装条件
     */
    private static function testTagManager_StatusCode_InstallCondition():String {
        // 不满足条件的装备：damagetype="普通", interval=120
        var testItem1 = {
            name: "测试装备_条件不满足",
            value: { mods: [] }
        };
        var testItemData1 = {
            data: { modslot: 3, damagetype: "普通", interval: 120 }
        };

        var code1:Number = TagManager.checkModAvailability(testItem1, testItemData1, "条件插件_魔法高间隔");
        var fail1:Boolean = (code1 == -256);

        // 满足条件的装备：damagetype="魔法", interval=250
        var testItem2 = {
            name: "测试装备_条件满足",
            value: { mods: [] }
        };
        var testItemData2 = {
            data: { modslot: 3, damagetype: "魔法", interval: 250 }
        };

        var code2:Number = TagManager.checkModAvailability(testItem2, testItemData2, "条件插件_魔法高间隔");
        var pass2:Boolean = (code2 == 1);

        // 只满足一个条件：damagetype="魔法" 但 interval=100（不满足 above 200）
        var testItem3 = {
            name: "测试装备_部分满足",
            value: { mods: [] }
        };
        var testItemData3 = {
            data: { modslot: 3, damagetype: "魔法", interval: 100 }
        };

        var code3:Number = TagManager.checkModAvailability(testItem3, testItemData3, "条件插件_魔法高间隔");
        var fail3:Boolean = (code3 == -256);

        var passed:Boolean = fail1 && pass2 && fail3;

        if (!passed) {
            return "✗ 状态码-256(安装条件)测试失败（不满足=" + code1
                   + "，满足=" + code2 + "，部分满足=" + code3 + "）\n";
        }
        return "✓ 状态码-256(安装条件)测试通过\n";
    }

    /**
     * installCondition 运算符详细测试
     * 覆盖所有12种运算符
     */
    private static function testInstallCondition_Operators():String {
        var testData:Object = {
            data: {
                damagetype: "魔法",
                interval: 250,
                power: 150,
                weight: 2.5,
                bullet: "横向联弹-穿刺子弹",
                magictype: "电"
            }
        };

        var results:Array = [];
        var allPassed:Boolean = true;

        // is: 魔法 == 魔法 → true
        var r1:Boolean = ModRegistry.evaluateCondition({op: "is", path: "data.damagetype", value: "魔法"}, testData);
        if (!r1) { results.push("is应为true"); allPassed = false; }

        // is: 魔法 == 普通 → false
        var r2:Boolean = ModRegistry.evaluateCondition({op: "is", path: "data.damagetype", value: "普通"}, testData);
        if (r2) { results.push("is应为false"); allPassed = false; }

        // isNot: 魔法 != 普通 → true
        var r3:Boolean = ModRegistry.evaluateCondition({op: "isNot", path: "data.damagetype", value: "普通"}, testData);
        if (!r3) { results.push("isNot应为true"); allPassed = false; }

        // above: 250 > 200 → true
        var r4:Boolean = ModRegistry.evaluateCondition({op: "above", path: "data.interval", value: 200}, testData);
        if (!r4) { results.push("above应为true"); allPassed = false; }

        // above: 250 > 250 → false（严格大于）
        var r5:Boolean = ModRegistry.evaluateCondition({op: "above", path: "data.interval", value: 250}, testData);
        if (r5) { results.push("above边界应为false"); allPassed = false; }

        // atLeast: 250 >= 250 → true
        var r6:Boolean = ModRegistry.evaluateCondition({op: "atLeast", path: "data.interval", value: 250}, testData);
        if (!r6) { results.push("atLeast应为true"); allPassed = false; }

        // below: 2.5 < 3 → true
        var r7:Boolean = ModRegistry.evaluateCondition({op: "below", path: "data.weight", value: 3}, testData);
        if (!r7) { results.push("below应为true"); allPassed = false; }

        // atMost: 2.5 <= 3 → true
        var r8:Boolean = ModRegistry.evaluateCondition({op: "atMost", path: "data.weight", value: 3}, testData);
        if (!r8) { results.push("atMost应为true"); allPassed = false; }

        // atMost: 2.5 <= 2 → false
        var r9:Boolean = ModRegistry.evaluateCondition({op: "atMost", path: "data.weight", value: 2}, testData);
        if (r9) { results.push("atMost应为false"); allPassed = false; }

        // oneOf: 魔法 in {魔法,破击} → true
        var r10:Boolean = ModRegistry.evaluateCondition(
            {op: "oneOf", path: "data.damagetype", value: "魔法,破击", valueDict: {魔法: true, 破击: true}},
            testData
        );
        if (!r10) { results.push("oneOf应为true"); allPassed = false; }

        // noneOf: 魔法 not in {普通,破击} → true
        var r11:Boolean = ModRegistry.evaluateCondition(
            {op: "noneOf", path: "data.damagetype", value: "普通,破击", valueDict: {普通: true, 破击: true}},
            testData
        );
        if (!r11) { results.push("noneOf应为true"); allPassed = false; }

        // contains: "横向联弹-穿刺子弹" contains "穿刺" → true
        var r12:Boolean = ModRegistry.evaluateCondition({op: "contains", path: "data.bullet", value: "穿刺"}, testData);
        if (!r12) { results.push("contains应为true"); allPassed = false; }

        // range: 150 in [100, 300] → true
        var r13:Boolean = ModRegistry.evaluateCondition({op: "range", path: "data.power", min: 100, max: 300}, testData);
        if (!r13) { results.push("range应为true"); allPassed = false; }

        // range: 150 in [200, 300] → false
        var r14:Boolean = ModRegistry.evaluateCondition({op: "range", path: "data.power", min: 200, max: 300}, testData);
        if (r14) { results.push("range应为false"); allPassed = false; }

        // exists: data.magictype 存在 → true
        var r15:Boolean = ModRegistry.evaluateCondition({op: "exists", path: "data.magictype"}, testData);
        if (!r15) { results.push("exists应为true"); allPassed = false; }

        // missing: data.skill 不存在 → true
        var r16:Boolean = ModRegistry.evaluateCondition({op: "missing", path: "data.skill"}, testData);
        if (!r16) { results.push("missing应为true"); allPassed = false; }

        // 缺失字段: data.notexist is "X" → false
        var r17:Boolean = ModRegistry.evaluateCondition({op: "is", path: "data.notexist", value: "X"}, testData);
        if (r17) { results.push("缺失字段应为false"); allPassed = false; }

        if (!allPassed) {
            return "✗ installCondition运算符测试失败（" + results.join(", ") + "）\n";
        }
        return "✓ installCondition运算符测试通过（17项全通过）\n";
    }

    /**
     * installCondition 点路径嵌套访问测试
     */
    private static function testInstallCondition_DotPath():String {
        var testItem = {
            name: "测试装备_嵌套",
            value: { mods: [] }
        };
        var testItemData = {
            data: {
                modslot: 3,
                magicdefence: {
                    电: 15,
                    冷: 5,
                    热: 0
                }
            }
        };

        // resolvePathValue 直接测试
        var val1 = ModRegistry.resolvePathValue(testItemData, "data.magicdefence.电");
        var val2 = ModRegistry.resolvePathValue(testItemData, "data.magicdefence.冷");
        var val3 = ModRegistry.resolvePathValue(testItemData, "data.magicdefence.不存在");

        var pathOk:Boolean = (val1 == 15 && val2 == 5 && val3 == undefined);

        // 通过 checkModAvailability 测试嵌套路径（条件插件_嵌套路径 要求 data.magicdefence.电 >= 10）
        var code1:Number = TagManager.checkModAvailability(testItem, testItemData, "条件插件_嵌套路径");
        var condOk:Boolean = (code1 == 1); // 电=15 >= 10，应通过

        // 不满足时
        var testItemData2 = {
            data: {
                modslot: 3,
                magicdefence: {
                    电: 5
                }
            }
        };
        var code2:Number = TagManager.checkModAvailability(testItem, testItemData2, "条件插件_嵌套路径");
        var condFail:Boolean = (code2 == -256); // 电=5 < 10，应拒绝

        var passed:Boolean = pathOk && condOk && condFail;

        if (!passed) {
            return "✗ installCondition点路径测试失败（pathOk=" + pathOk
                   + "，condOk=" + code1 + "，condFail=" + code2 + "）\n";
        }
        return "✓ installCondition点路径测试通过\n";
    }

    /**
     * installCondition mode="any" (OR逻辑) 测试
     */
    private static function testInstallCondition_ModeAny():String {
        // 条件插件_OR模式: mode="any", damagetype is 魔法 OR interval above 500

        // 只满足第一个条件（魔法但间隔不够）→ 通过
        var testItem = {
            name: "测试装备_OR",
            value: { mods: [] }
        };
        var testItemData1 = {
            data: { modslot: 3, damagetype: "魔法", interval: 100 }
        };
        var code1:Number = TagManager.checkModAvailability(testItem, testItemData1, "条件插件_OR模式");
        var pass1:Boolean = (code1 == 1); // 魔法满足 → OR通过

        // 只满足第二个条件（不是魔法但间隔超高）→ 通过
        var testItemData2 = {
            data: { modslot: 3, damagetype: "普通", interval: 600 }
        };
        var code2:Number = TagManager.checkModAvailability(testItem, testItemData2, "条件插件_OR模式");
        var pass2:Boolean = (code2 == 1); // interval>500 满足 → OR通过

        // 两个都不满足 → 拒绝
        var testItemData3 = {
            data: { modslot: 3, damagetype: "普通", interval: 100 }
        };
        var code3:Number = TagManager.checkModAvailability(testItem, testItemData3, "条件插件_OR模式");
        var fail3:Boolean = (code3 == -256); // 都不满足 → 拒绝

        // 两个都满足 → 通过
        var testItemData4 = {
            data: { modslot: 3, damagetype: "魔法", interval: 600 }
        };
        var code4:Number = TagManager.checkModAvailability(testItem, testItemData4, "条件插件_OR模式");
        var pass4:Boolean = (code4 == 1); // 都满足 → 当然通过

        var passed:Boolean = pass1 && pass2 && fail3 && pass4;

        if (!passed) {
            return "✗ installCondition OR模式测试失败（满足一=" + code1
                   + "，满足二=" + code2 + "，都不满足=" + code3
                   + "，都满足=" + code4 + "）\n";
        }
        return "✓ installCondition OR模式测试通过\n";
    }

    /**
     * 测试 installCondition scope="current" 作用域
     * 验证条件基于传入的 itemData（含已安装配件效果）进行判断
     */
    private static function testInstallCondition_ScopeCurrent():String {
        var testItem = {
            name: "测试装备",
            value: { mods: [] }
        };

        // 传入的 itemData 模拟"计算后"的数据（含配件效果），damagetype 被配件改为"破击"
        var testItemData1 = {
            data: { modslot: 3, damagetype: "破击", interval: 300 }
        };
        var code1:Number = TagManager.checkModAvailability(testItem, testItemData1, "条件插件_current作用域");
        var pass1:Boolean = (code1 == 1); // 满足 damagetype=="破击"

        // 基础值是"魔法"，不满足 scope="current" 的条件
        var testItemData2 = {
            data: { modslot: 3, damagetype: "魔法", interval: 300 }
        };
        var code2:Number = TagManager.checkModAvailability(testItem, testItemData2, "条件插件_current作用域");
        var fail2:Boolean = (code2 == -256); // 不满足

        var passed:Boolean = pass1 && fail2;

        if (!passed) {
            return "✗ installCondition scope=current测试失败（满足=" + code1
                   + "，不满足=" + code2 + "）\n";
        }
        return "✓ installCondition scope=current测试通过\n";
    }

    /**
     * 测试 installCondition group 嵌套求值
     * 条件插件_嵌套组: (damagetype=="魔法" AND interval>200) OR (damagetype=="破击")
     */
    private static function testInstallCondition_GroupNesting():String {
        var testItem = {
            name: "测试装备",
            value: { mods: [] }
        };

        // 满足外层 cond: damagetype=="破击"（OR模式，只需一个分支满足）
        var testItemData1 = {
            data: { modslot: 3, damagetype: "破击", interval: 100 }
        };
        var code1:Number = TagManager.checkModAvailability(testItem, testItemData1, "条件插件_嵌套组");
        var pass1:Boolean = (code1 == 1);

        // 满足 group 分支: damagetype=="魔法" AND interval>200
        var testItemData2 = {
            data: { modslot: 3, damagetype: "魔法", interval: 300 }
        };
        var code2:Number = TagManager.checkModAvailability(testItem, testItemData2, "条件插件_嵌套组");
        var pass2:Boolean = (code2 == 1);

        // 不满足任何分支: damagetype=="普通"
        var testItemData3 = {
            data: { modslot: 3, damagetype: "普通", interval: 300 }
        };
        var code3:Number = TagManager.checkModAvailability(testItem, testItemData3, "条件插件_嵌套组");
        var fail3:Boolean = (code3 == -256);

        // group 分支部分满足（魔法但 interval 不够）→ 不通过，且外层 cond 也不满足
        var testItemData4 = {
            data: { modslot: 3, damagetype: "魔法", interval: 100 }
        };
        var code4:Number = TagManager.checkModAvailability(testItem, testItemData4, "条件插件_嵌套组");
        var fail4:Boolean = (code4 == -256);

        var passed:Boolean = pass1 && pass2 && fail3 && fail4;

        if (!passed) {
            return "✗ installCondition group嵌套测试失败（破击=" + code1
                   + "，魔法高间隔=" + code2 + "，普通=" + code3
                   + "，魔法低间隔=" + code4 + "）\n";
        }
        return "✓ installCondition group嵌套测试通过\n";
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
        result += testEquipmentCalculator_CurveOperator();
        result += testEquipmentCalculator_PureVsNormal();
        result += testEquipmentCalculator_UseSwitchMatching();
        result += testEquipmentCalculator_BaseSwitchAndOverridePrecedence();
        result += testSwitchStrikeCore_ProfileConfiguration();
        result += testEquipmentCalculator_QualifiedHandgunHitBehavior();
        result += testEquipmentCalculator_GunShieldProfile();

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
     * 验证顺序：percentage → multiplier → curve → flat → softOverride → override → merge → lockOverride → cap
     */
    private static function testEquipmentCalculator_ModifierOrder():String {
        EquipmentConfigManager.loadConfig({
            levelStatList: [1, 1.0],  // level=1不产生倍率
            decimalPropDict: {}
        });

        // 创建测试配件，验证修正项顺序
        // 基础值100，percentage=50(+50%)，multiplier=100(+100%即×2)，flat=10
        // loadModData 会对 percentage/multiplier 执行 ×0.01 归一化，所以传入原始百分比值
        // multiplier 语义：+100% = 归一化后 1.0 → factor = 1 + 1.0 = 2.0（×2）
        ModRegistry.loadModData([
            {
                name: "顺序测试配件",
                use: "头部装备",
                stats: {
                    percentage: { defence: 50 },     // 归一化后 0.5，+50% → 100×1.5 = 150
                    multiplier: { defence: 100 },    // 归一化后 1.0，+100% → 150×2 = 300
                    flat: { defence: 10 },           // +10 → 300+10 = 310
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
     * curve 运算符顺序测试
     * 验证顺序：percentage → multiplierZone → curve → flat。
     */
    private static function testEquipmentCalculator_CurveOperator():String {
        EquipmentConfigManager.loadConfig({
            levelStatList: [1, 1.0],
            decimalPropDict: {}
        });

        ModRegistry.loadModData([
            {
                name: "曲线测试配件",
                use: "长枪",
                stats: {
                    percentage: { diffusion: 100 },  // 7 → 14
                    curve: { diffusion: 1.414 },     // 14 → round(1.414*sqrt(14)) = 5
                    flat: { diffusion: 1 }           // 5 → 6
                }
            }
        ]);

        var itemData:Object = {
            name: "测试长枪",
            use: "长枪",
            weapontype: "突击步枪",
            data: { diffusion: 7 }
        };

        var value:Object = { level: 1, mods: ["曲线测试配件"] };
        var cfg:Object = EquipmentConfigManager.getFullConfig();
        var modRegistry:Object = {
            曲线测试配件: ModRegistry.getModData("曲线测试配件")
        };

        var result:Object = EquipmentCalculator.calculatePure(itemData, value, cfg, modRegistry);
        var passed:Boolean = (result.data.diffusion == 6);

        if (!passed) {
            return "✗ curve顺序测试失败（diffusion=" + result.data.diffusion + "，期望6）\n";
        }

        return "✓ curve顺序测试通过\n";
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

    /**
     * baseSwitch 必须读取配件应用前的伤害类型；soft/普通/lock 覆盖优先级不得受槽位顺序影响。
     */
    private static function testEquipmentCalculator_BaseSwitchAndOverridePrecedence():String {
        EquipmentConfigManager.loadConfig({levelStatList: [1, 1.0], decimalPropDict: {}});

        ModRegistry.loadModData([
            {
                name: "测试磨刀石", use: "长枪",
                stats: {
                    baseSwitch: {
                        path: "data.damagetype",
                        value: [
                            {name: "破击", percentage: {power: 24}},
                            {name: "魔法", percentage: {power: 50}},
                            {percentage: {power: 9}}
                        ]
                    },
                    lockOverride: {damagetype: "物理"}
                }
            },
            {name: "测试电柄", use: "长枪", stats: {override: {damagetype: "破击", magictype: "电"}}},
            {name: "测试矩锁", use: "长枪", stats: {softOverride: {criticalhit: 10}}},
            {name: "测试暴击镜", use: "长枪", stats: {override: {criticalhit: 20}}}
        ]);

        var registry:Object = {
            测试磨刀石: ModRegistry.getModData("测试磨刀石"),
            测试电柄: ModRegistry.getModData("测试电柄"),
            测试矩锁: ModRegistry.getModData("测试矩锁"),
            测试暴击镜: ModRegistry.getModData("测试暴击镜")
        };
        var cfg:Object = EquipmentConfigManager.getFullConfig();

        var physical:Object = EquipmentCalculator.calculatePure(
            {name: "物理枪", use: "长枪", data: {power: 100, damagetype: "物理"}},
            {level: 1, mods: ["测试磨刀石"]}, cfg, registry);
        var breakDamage:Object = EquipmentCalculator.calculatePure(
            {name: "破击枪", use: "长枪", data: {power: 100, damagetype: "破击"}},
            {level: 1, mods: ["测试电柄", "测试磨刀石"]}, cfg, registry);
        var magicDamage:Object = EquipmentCalculator.calculatePure(
            {name: "属性枪", use: "长枪", data: {power: 100, damagetype: "魔法"}},
            {level: 1, mods: ["测试磨刀石", "测试电柄"]}, cfg, registry);

        var matrixOnly:Object = EquipmentCalculator.calculatePure(
            {name: "原生暴击枪", use: "长枪", data: {criticalhit: 30}},
            {level: 1, mods: ["测试矩锁"]}, cfg, registry);
        var critOrderA:Object = EquipmentCalculator.calculatePure(
            {name: "暴击枪A", use: "长枪", data: {criticalhit: 30}},
            {level: 1, mods: ["测试矩锁", "测试暴击镜"]}, cfg, registry);
        var critOrderB:Object = EquipmentCalculator.calculatePure(
            {name: "暴击枪B", use: "长枪", data: {criticalhit: 30}},
            {level: 1, mods: ["测试暴击镜", "测试矩锁"]}, cfg, registry);

        var passed:Boolean = (
            physical.data.power == 109 && physical.data.damagetype == "物理" &&
            breakDamage.data.power == 124 && breakDamage.data.damagetype == "物理" &&
            magicDamage.data.power == 150 && magicDamage.data.damagetype == "物理" &&
            matrixOnly.data.criticalhit == 10 &&
            critOrderA.data.criticalhit == 20 && critOrderB.data.criticalhit == 20
        );

        return passed
            ? "✓ baseSwitch与覆盖优先级测试通过\n"
            : "✗ baseSwitch与覆盖优先级测试失败（威力=" + physical.data.power + "/" +
              breakDamage.data.power + "/" + magicDamage.data.power + "，类型=" +
              breakDamage.data.damagetype + "/" + magicDamage.data.damagetype + "，暴击=" +
              matrixOnly.data.criticalhit + "/" + critOrderA.data.criticalhit + "/" +
              critOrderB.data.criticalhit + "）\n";
    }

    /** 切手技默认公式与挂环的重量/冲击配置回归。 */
    private static function testSwitchStrikeCore_ProfileConfiguration():String {
        var baseUnit:Object = {
            空手攻击力: 100,
            mp攻击加成: 5,
            长枪属性: {weight: 10},
            刀属性: {power: 40},
            被动技能: {拳脚攻击: {启用: true, 等级: 2}}
        };
        var ringUnit:Object = {
            空手攻击力: 100,
            mp攻击加成: 5,
            长枪属性: {weight: 10, switchstrike: {weightCoefficient: 5, impactMultiplier: 5}},
            刀属性: {power: 40},
            被动技能: {拳脚攻击: {启用: true, 等级: 2}}
        };

        var baseLonggun:Object = SwitchStrikeCore.buildBulletProperties(baseUnit, "长枪", {});
        var ringLonggun:Object = SwitchStrikeCore.buildBulletProperties(ringUnit, "长枪", {});
        var blade:Object = SwitchStrikeCore.buildBulletProperties(baseUnit, "兵器", {});
        var kick:Object = SwitchStrikeCore.buildBulletProperties(baseUnit, "回旋踢", {});

        var passed:Boolean = (
            baseLonggun.子弹威力 == 55 && baseLonggun.击倒率 == 5 &&
            ringLonggun.子弹威力 == 75 && ringLonggun.击倒率 == 1 &&
            ringLonggun.伤害类型 == "物理" && blade.子弹威力 == 65 &&
            kick.子弹威力 == 125 && kick.霰弹值 == 1
        );

        return passed
            ? "✓ 切手技形态配置测试通过\n"
            : "✗ 切手技形态配置测试失败（长枪=" + baseLonggun.子弹威力 + "/" +
              baseLonggun.击倒率 + "，挂环=" + ringLonggun.子弹威力 + "/" +
              ringLonggun.击倒率 + "，刀/踢=" + blade.子弹威力 + "/" + kick.子弹威力 + "）\n";
    }

    /**
     * 枪盾数值档回归：霰弹防御、NOAH 生存资源与压制类额外惩罚可同时叠加。
     */
    private static function testEquipmentCalculator_GunShieldProfile():String {
        EquipmentConfigManager.loadConfig({
            levelStatList: [1, 1.0],
            decimalPropDict: {}
        });

        ModRegistry.loadModData([{
            name: "枪盾数值测试配件",
            use: "长枪,手枪",
            stats: {
                flat: {weight: 2, toughness: 50, accuracy: -10},
                useSwitch: {
                    use: [
                        {name: "weapontype:霰弹枪", flat: {defence: 20}},
                        {name: "weapontype:压制机枪,weapontype:压制近战", requireTags: "电力", flat: {accuracy: -10, reloadPenalty: 20}}
                    ]
                },
                tagSwitch: {
                    tag: {name: "NOAH", flat: {accuracy: 10, hp: 15, mp: 15}}
                }
            }
        }]);

        var modRegistry:Object = {
            枪盾数值测试配件: ModRegistry.getModData("枪盾数值测试配件")
        };
        var cfg:Object = EquipmentConfigManager.getFullConfig();
        var value:Object = {level: 1, mods: ["枪盾数值测试配件"]};

        var shotgun:Object = EquipmentCalculator.calculatePure({
            name: "测试霰弹枪",
            use: "长枪",
            weapontype: "霰弹枪",
            data: {accuracy: 100, defence: 0, toughness: 0, weight: 0}
        }, value, cfg, modRegistry);

        var noahSuppressor:Object = EquipmentCalculator.calculatePure({
            name: "测试NOAH压制机枪",
            use: "长枪",
            weapontype: "压制机枪",
            inherentTags: "电力,NOAH",
            data: {accuracy: 100, hp: 100, mp: 100, reloadPenalty: 0, toughness: 0, weight: 0}
        }, value, cfg, modRegistry);

        var passed:Boolean = (
            shotgun.data.accuracy == 90 &&
            shotgun.data.defence == 20 &&
            shotgun.data.toughness == 50 &&
            shotgun.data.weight == 2 &&
            noahSuppressor.data.accuracy == 90 &&
            noahSuppressor.data.hp == 115 &&
            noahSuppressor.data.mp == 115 &&
            noahSuppressor.data.reloadPenalty == 20 &&
            noahSuppressor.data.toughness == 50 &&
            noahSuppressor.data.weight == 2
        );

        return passed
            ? "✓ 枪盾数值分支回归测试通过\n"
            : "✗ 枪盾数值分支回归测试失败（霰弹枪=" + shotgun.data.accuracy + "/" + shotgun.data.defence +
              "，NOAH压制=" + noahSuppressor.data.accuracy + "/" + noahSuppressor.data.hp + "/" +
              noahSuppressor.data.mp + "/" + noahSuppressor.data.reloadPenalty + "）\n";
    }

    /**
     * 精确手枪分支与嵌套 hitBehavior 合并测试。
     * 普通手枪获得专属档位，冲锋手枪只保留插件基础档位。
     */
    private static function testEquipmentCalculator_QualifiedHandgunHitBehavior():String {
        EquipmentConfigManager.loadConfig({
            levelStatList: [1, 1.0],
            decimalPropDict: {}
        });

        ModRegistry.loadModData([{
            name: "手枪行为补弱测试配件",
            use: "手枪",
            stats: {
                merge: {
                    hitBehavior: {
                        type: "toughnessVulnerabilityPrimer",
                        stackGroup: "grayGooVulnerability",
                        profileId: "base",
                        duration: 180,
                        maxDuration: 300,
                        maxStacks: 3,
                        damagePerStack: 0.06
                    }
                },
                useSwitch: {
                    use: [{
                        name: "weapontype:手枪",
                        merge: {
                            hitBehavior: {
                                profileId: "handgun",
                                duration: 240,
                                maxDuration: 360,
                                damagePerStack: 0.07
                            }
                        }
                    }]
                }
            }
        }]);

        var modRegistry:Object = {
            手枪行为补弱测试配件: ModRegistry.getModData("手枪行为补弱测试配件")
        };
        var value:Object = {level: 1, mods: ["手枪行为补弱测试配件"]};
        var cfg:Object = EquipmentConfigManager.getFullConfig();

        var standardResult:Object = EquipmentCalculator.calculatePure(
            {name: "测试普通手枪", use: "手枪", weapontype: "手枪", data: {}},
            value,
            cfg,
            modRegistry
        );
        var machinePistolResult:Object = EquipmentCalculator.calculatePure(
            {name: "测试冲锋手枪", use: "手枪", weapontype: "冲锋枪", data: {}},
            value,
            cfg,
            modRegistry
        );

        var standardBehavior:Object = standardResult.data.hitBehavior;
        var machinePistolBehavior:Object = machinePistolResult.data.hitBehavior;
        var passed:Boolean = (
            standardBehavior.duration == 240 &&
            standardBehavior.stackGroup == "grayGooVulnerability" &&
            standardBehavior.profileId == "handgun" &&
            standardBehavior.maxDuration == 360 &&
            standardBehavior.maxStacks == 3 &&
            standardBehavior.damagePerStack == 0.07 &&
            machinePistolBehavior.duration == 180 &&
            machinePistolBehavior.stackGroup == "grayGooVulnerability" &&
            machinePistolBehavior.profileId == "base" &&
            machinePistolBehavior.maxDuration == 300 &&
            machinePistolBehavior.maxStacks == 3 &&
            machinePistolBehavior.damagePerStack == 0.06
        );

        if (!passed) {
            return "✗ 精确手枪hitBehavior合并测试失败（普通手枪=" +
                   standardBehavior.duration + "/" + standardBehavior.maxDuration + "/" + standardBehavior.damagePerStack +
                   "，冲锋手枪=" + machinePistolBehavior.duration + "/" +
                   machinePistolBehavior.maxDuration + "/" + machinePistolBehavior.damagePerStack + "）\n";
        }

        return "✓ 精确手枪hitBehavior合并测试通过\n";
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

    // ==================== 性能测试模块 ====================

    /**
     * 运行性能测试套件
     * 评估装备系统在各种复杂场景下的计算开销
     */
    private static function runPerformanceTests():String {
        var result:String = "";

        // 基准测试：无配件计算
        result += perfTest_BaseCalculation();

        // 单配件多修正项测试
        result += perfTest_SingleModRichStats();

        // 多配件叠加测试
        result += perfTest_MultipleModsStacking();

        // useSwitch 分支匹配性能
        result += perfTest_UseSwitchMatching();

        // 深度合并性能（嵌套对象）
        result += perfTest_DeepMerge();

        // 综合场景：模拟实际战斗装备
        result += perfTest_RealisticCombatGear();

        return result;
    }

    /**
     * 基准测试：无配件的基础计算
     * 测量纯强化等级计算的开销
     */
    private static function perfTest_BaseCalculation():String {
        EquipmentConfigManager.loadConfig({
            levelStatList: [1, 1.06, 1.14, 1.24, 1.36, 1.5, 1.66, 1.84, 2.04, 2.26, 2.5],
            decimalPropDict: {weight: 1}
        });

        var itemData:Object = {
            name: "基准测试装备",
            use: "头部装备",
            data: {
                defence: 100, hp: 500, mp: 200,
                power: 50, damage: 30
            }
        };

        var value:Object = { level: 5, mods: [] };
        var cfg:Object = EquipmentConfigManager.getFullConfig();

        var iterations:Number = 1000;
        var startTime:Number = getTimer();

        for (var i:Number = 0; i < iterations; i++) {
            EquipmentCalculator.calculatePure(itemData, value, cfg, {});
        }

        var endTime:Number = getTimer();
        var duration:Number = endTime - startTime;
        var avgTime:Number = duration / iterations;

        return "基准计算(无配件): " + iterations + "次 " + duration + "ms, " +
               "平均" + avgTime + "ms/次\n";
    }

    /**
     * 单配件多修正项测试
     * 测量复杂配件（包含所有修正类型）的计算开销
     */
    private static function perfTest_SingleModRichStats():String {
        EquipmentConfigManager.loadConfig({
            levelStatList: [1, 1.0],
            decimalPropDict: {weight: 1}
        });

        // 创建包含所有修正类型的复杂配件
        ModRegistry.loadModData([{
            name: "富属性测试配件",
            use: "头部装备",
            stats: {
                percentage: { defence: 30, hp: 20, mp: 15 },
                multiplier: { defence: 50, power: 40 },
                flat: { defence: 25, hp: 100, mp: 50, damage: 10 },
                override: { critrate: 15 },
                merge: {
                    magicdefence: { fire: 20, ice: 15, lightning: 10 },
                    skillmultipliers: { skill1: 1.2, skill2: 1.5 }
                },
                cap: { defence: 500, hp: 2000 }
            }
        }]);

        var itemData:Object = {
            name: "测试装备",
            use: "头部装备",
            data: {
                defence: 100, hp: 500, mp: 200, power: 50, damage: 30,
                magicdefence: { fire: 10, ice: 10 }
            }
        };

        var value:Object = { level: 1, mods: ["富属性测试配件"] };
        var cfg:Object = EquipmentConfigManager.getFullConfig();
        var modRegistry:Object = { 富属性测试配件: ModRegistry.getModData("富属性测试配件") };

        var iterations:Number = 1000;
        var startTime:Number = getTimer();

        for (var i:Number = 0; i < iterations; i++) {
            EquipmentCalculator.calculatePure(itemData, value, cfg, modRegistry);
        }

        var endTime:Number = getTimer();
        var duration:Number = endTime - startTime;
        var avgTime:Number = duration / iterations;

        return "单配件富属性: " + iterations + "次 " + duration + "ms, " +
               "平均" + avgTime + "ms/次\n";
    }

    /**
     * 多配件叠加测试
     * 测量多个配件同时生效时的计算开销
     */
    private static function perfTest_MultipleModsStacking():String {
        EquipmentConfigManager.loadConfig({
            levelStatList: [1, 1.0],
            decimalPropDict: {weight: 1}
        });

        // 创建5个不同的配件
        ModRegistry.loadModData([
            {
                name: "配件A", use: "头部装备",
                stats: { percentage: { defence: 10, hp: 5 }, flat: { defence: 5 } }
            },
            {
                name: "配件B", use: "头部装备",
                stats: { percentage: { defence: 8 }, multiplier: { hp: 20 } }
            },
            {
                name: "配件C", use: "头部装备",
                stats: { flat: { defence: 15, mp: 30 }, merge: { magicdefence: { fire: 10 } } }
            },
            {
                name: "配件D", use: "头部装备",
                stats: { percentage: { power: 15, damage: 12 } }
            },
            {
                name: "配件E", use: "头部装备",
                stats: { multiplier: { defence: 30 }, cap: { defence: 300 } }
            }
        ]);

        var itemData:Object = {
            name: "测试装备",
            use: "头部装备",
            data: { defence: 100, hp: 500, mp: 200, power: 50, damage: 30 }
        };

        var value:Object = { level: 1, mods: ["配件A", "配件B", "配件C", "配件D", "配件E"] };
        var cfg:Object = EquipmentConfigManager.getFullConfig();
        var modRegistry:Object = {
            配件A: ModRegistry.getModData("配件A"),
            配件B: ModRegistry.getModData("配件B"),
            配件C: ModRegistry.getModData("配件C"),
            配件D: ModRegistry.getModData("配件D"),
            配件E: ModRegistry.getModData("配件E")
        };

        var iterations:Number = 1000;
        var startTime:Number = getTimer();

        for (var i:Number = 0; i < iterations; i++) {
            EquipmentCalculator.calculatePure(itemData, value, cfg, modRegistry);
        }

        var endTime:Number = getTimer();
        var duration:Number = endTime - startTime;
        var avgTime:Number = duration / iterations;

        return "5配件叠加: " + iterations + "次 " + duration + "ms, " +
               "平均" + avgTime + "ms/次\n";
    }

    /**
     * useSwitch 分支匹配性能测试
     * 测量带条件分支的配件计算开销
     */
    private static function perfTest_UseSwitchMatching():String {
        EquipmentConfigManager.loadConfig({
            levelStatList: [1, 1.0],
            decimalPropDict: {}
        });

        // 创建带多条件分支的配件
        ModRegistry.loadModData([{
            name: "多分支性能测试",
            use: "头部装备,上装装备,下装装备,手部装备,脚部装备",
            stats: {
                flat: { defence: 5 },  // 基础属性
                useSwitch: {
                    use: [
                        { name: "头部装备", percentage: { defence: 15 }, flat: { hp: 50 } },
                        { name: "上装装备", percentage: { defence: 20 }, flat: { hp: 80 } },
                        { name: "下装装备", percentage: { defence: 12 }, flat: { hp: 60 } },
                        { name: "手部装备", percentage: { power: 10 }, flat: { damage: 5 } },
                        { name: "脚部装备", percentage: { hp: 8 }, flat: { mp: 30 } }
                    ]
                }
            }
        }]);

        var itemData:Object = {
            name: "测试头盔",
            use: "头部装备",
            data: { defence: 100, hp: 500, mp: 200, power: 50, damage: 30 }
        };

        var value:Object = { level: 1, mods: ["多分支性能测试"] };
        var cfg:Object = EquipmentConfigManager.getFullConfig();
        var modRegistry:Object = { 多分支性能测试: ModRegistry.getModData("多分支性能测试") };

        var iterations:Number = 1000;
        var startTime:Number = getTimer();

        for (var i:Number = 0; i < iterations; i++) {
            EquipmentCalculator.calculatePure(itemData, value, cfg, modRegistry);
        }

        var endTime:Number = getTimer();
        var duration:Number = endTime - startTime;
        var avgTime:Number = duration / iterations;

        return "useSwitch分支: " + iterations + "次 " + duration + "ms, " +
               "平均" + avgTime + "ms/次\n";
    }

    /**
     * 深度合并性能测试
     * 测量嵌套对象合并的开销
     */
    private static function perfTest_DeepMerge():String {
        EquipmentConfigManager.loadConfig({
            levelStatList: [1, 1.0],
            decimalPropDict: {}
        });

        // 创建包含深度嵌套合并的配件
        ModRegistry.loadModData([{
            name: "深度合并测试",
            use: "头部装备",
            stats: {
                merge: {
                    magicdefence: {
                        fire: 25, ice: 20, lightning: 15, poison: 10,
                        holy: 5, dark: 8, arcane: 12
                    },
                    skillmultipliers: {
                        attack1: 1.15, attack2: 1.2, attack3: 1.25,
                        special1: 1.5, special2: 1.8, ultimate: 2.0
                    },
                    resistances: {
                        physical: 10, magical: 8,
                        status: { stun: 15, poison: 20, burn: 12 }
                    }
                }
            }
        }]);

        var itemData:Object = {
            name: "测试装备",
            use: "头部装备",
            data: {
                defence: 100, hp: 500,
                magicdefence: { fire: 10, ice: 10, lightning: 10 },
                skillmultipliers: { attack1: 1.0, special1: 1.2 },
                resistances: { physical: 5, status: { stun: 5 } }
            }
        };

        var value:Object = { level: 1, mods: ["深度合并测试"] };
        var cfg:Object = EquipmentConfigManager.getFullConfig();
        var modRegistry:Object = { 深度合并测试: ModRegistry.getModData("深度合并测试") };

        var iterations:Number = 1000;
        var startTime:Number = getTimer();

        for (var i:Number = 0; i < iterations; i++) {
            EquipmentCalculator.calculatePure(itemData, value, cfg, modRegistry);
        }

        var endTime:Number = getTimer();
        var duration:Number = endTime - startTime;
        var avgTime:Number = duration / iterations;

        return "深度合并: " + iterations + "次 " + duration + "ms, " +
               "平均" + avgTime + "ms/次\n";
    }

    /**
     * 综合场景：模拟实际战斗装备
     * 使用接近真实游戏的配置测试整体性能
     */
    private static function perfTest_RealisticCombatGear():String {
        // 使用完整的游戏配置
        EquipmentConfigManager.loadConfig({
            levelStatList: [1, 1.06, 1.14, 1.24, 1.36, 1.5, 1.66, 1.84, 2.04, 2.26, 2.5],
            decimalPropDict: {weight: 1, rout: 1, vampirism: 1},
            tierNameToKeyDict: {二阶: "data_2", 三阶: "data_3", 四阶: "data_4"},
            tierToMaterialDict: {
                data_2: "二阶复合防御组件",
                data_3: "三阶复合防御组件",
                data_4: "四阶复合防御组件"
            },
            defaultTierDataDict: {
                二阶: {level: 12, defence: 80},
                三阶: {level: 15, defence: 120},
                四阶: {level: 18, defence: 160}
            }
        });

        // 模拟实际游戏中的配件配置
        ModRegistry.loadModData([
            {
                name: "强化护甲板",
                use: "头部装备,上装装备",
                stats: {
                    percentage: { defence: 25 },
                    flat: { defence: 20, hp: 50 },
                    useSwitch: {
                        use: [
                            { name: "头部装备", flat: { hp: 30 } },
                            { name: "上装装备", flat: { hp: 80 } }
                        ]
                    }
                }
            },
            {
                name: "生命强化核心",
                use: "头部装备",
                stats: {
                    percentage: { hp: 15 },
                    multiplier: { hp: 30 },
                    flat: { hp: 100 }
                }
            },
            {
                name: "元素抗性模块",
                use: "头部装备",
                stats: {
                    merge: {
                        magicdefence: { fire: 15, ice: 15, lightning: 15 }
                    },
                    cap: { magicdefence: 50 }
                }
            }
        ]);

        // 模拟实际装备数据
        var itemData:Object = {
            name: "精锐战士头盔",
            use: "头部装备",
            type: "防具",
            data: {
                level: 8,
                defence: 85,
                hp: 350,
                mp: 120,
                weight: 2.5,
                magicdefence: { fire: 5, ice: 5 }
            },
            data_2: {
                level: 12,
                defence: 120,
                hp: 500,
                displayname: "强化精锐战士头盔"
            }
        };

        var value:Object = {
            level: 8,
            tier: "二阶",
            mods: ["强化护甲板", "生命强化核心", "元素抗性模块"]
        };

        var cfg:Object = EquipmentConfigManager.getFullConfig();
        var modRegistry:Object = {
            强化护甲板: ModRegistry.getModData("强化护甲板"),
            生命强化核心: ModRegistry.getModData("生命强化核心"),
            元素抗性模块: ModRegistry.getModData("元素抗性模块")
        };

        var iterations:Number = 1000;
        var startTime:Number = getTimer();

        for (var i:Number = 0; i < iterations; i++) {
            EquipmentCalculator.calculatePure(itemData, value, cfg, modRegistry);
        }

        var endTime:Number = getTimer();
        var duration:Number = endTime - startTime;
        var avgTime:Number = duration / iterations;

        // 计算单次结果用于验证
        var sampleResult:Object = EquipmentCalculator.calculatePure(itemData, value, cfg, modRegistry);

        return "综合战斗装备: " + iterations + "次 " + duration + "ms, " +
               "平均" + avgTime + "ms/次\n" +
               "  (含进阶+强化+3配件+useSwitch+merge)\n" +
               "  样本结果: defence=" + sampleResult.data.defence +
               ", hp=" + sampleResult.data.hp + "\n";
    }
}
