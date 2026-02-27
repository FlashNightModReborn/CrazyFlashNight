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
        result += testTagManager_StatusCode_InstallCondition(); // -256

        // installCondition 详细测试
        result += testInstallCondition_Operators();
        result += testInstallCondition_DotPath();
        result += testInstallCondition_ModeAny();

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
