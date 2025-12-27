/**
 * AdaptiveShieldTestSuite - 自适应护盾测试套件 
 *
 * 集中管理 AdaptiveShield 类的所有测试用例
 * 覆盖单盾模式、栈模式、模式切换、性能对比等功能
 *
 * @author FlashNight
 * @version 1.0
 */
import org.flashNight.arki.component.Shield.*;

class org.flashNight.arki.component.Shield.AdaptiveShieldTestSuite {

    // ==================== 公共入口 ====================

    /**
     * 运行完整测试套件
     * @return 测试报告字符串
     */
    public static function runAllTests():String {
        var report:String = "\n";
        report += "========================================\n";
        report += "    AdaptiveShield 测试套件 v1.0\n";
        report += "========================================\n\n";

        var startTime:Number = getTimer();

        // 1. 构造函数测试
        report += "【1. 构造函数测试】\n";
        report += testConstructor();
        report += "\n";

        // 2. 单盾模式测试
        report += "【2. 单盾模式测试】\n";
        report += testSingleMode();
        report += "\n";

        // 3. 工厂方法测试
        report += "【3. 工厂方法测试】\n";
        report += testFactoryMethods();
        report += "\n";

        // 4. 模式升级测试
        report += "【4. 模式升级测试】\n";
        report += testModeUpgrade();
        report += "\n";

        // 5. 栈模式测试
        report += "【5. 栈模式测试】\n";
        report += testStackMode();
        report += "\n";

        // 6. 模式降级测试
        report += "【6. 模式降级测试】\n";
        report += testModeDowngrade();
        report += "\n";

        // 7. 联弹机制测试
        report += "【7. 联弹机制测试】\n";
        report += testHitCount();
        report += "\n";

        // 8. 抵抗绕过测试
        report += "【8. 抵抗绕过测试】\n";
        report += testResistBypass();
        report += "\n";

        // 9. 回调测试
        report += "【9. 回调测试】\n";
        report += testCallbacks();
        report += "\n";

        // 10. 边界条件测试
        report += "【10. 边界条件测试】\n";
        report += testBoundaryConditions();
        report += "\n";

        // 11. 一致性对比测试
        report += "【11. 一致性对比测试】\n";
        report += testConsistency();
        report += "\n";

        // 12. 性能测试
        report += "【12. 性能测试】\n";
        report += testPerformance();
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
        var hasServer:Boolean = (_root.服务器 != null && _root.服务器.发布服务器消息 != null);
        for (var i:Number = 0; i < lines.length; i++) {
            if (lines[i].length > 0) {
                if (hasServer) {
                    _root.服务器.发布服务器消息(lines[i]);
                } else {
                    trace(lines[i]);
                }
            }
        }
    }

    // ==================== 1. 构造函数测试 ====================

    private static function testConstructor():String {
        var results:Array = [];

        results.push(testConstructor_DefaultValues());
        results.push(testConstructor_CustomValues());
        results.push(testConstructor_InitialMode());

        return formatResults(results, "构造函数");
    }

    private static function testConstructor_DefaultValues():String {
        var shield:AdaptiveShield = new AdaptiveShield(undefined, undefined, undefined, undefined, undefined, undefined);

        var passed:Boolean = (
            shield.getMaxCapacity() == 100 &&
            shield.getCapacity() == 100 &&
            shield.getStrength() == 50 &&
            shield.getRechargeRate() == 0 &&
            shield.getName() == "AdaptiveShield" &&
            shield.getType() == "adaptive"
        );

        return passed ? "✓ 默认值测试通过" : "✗ 默认值测试失败";
    }

    private static function testConstructor_CustomValues():String {
        var shield:AdaptiveShield = new AdaptiveShield(200, 80, 5, 30, "测试盾", "能量盾");

        var passed:Boolean = (
            shield.getMaxCapacity() == 200 &&
            shield.getStrength() == 80 &&
            shield.getRechargeRate() == 5 &&
            shield.getRechargeDelay() == 30 &&
            shield.getName() == "测试盾" &&
            shield.getType() == "能量盾"
        );

        return passed ? "✓ 自定义值测试通过" : "✗ 自定义值测试失败";
    }

    private static function testConstructor_InitialMode():String {
        var shield:AdaptiveShield = new AdaptiveShield(100, 50, 0, 0, "测试", "default");

        var passed:Boolean = (
            shield.isSingleMode() == true &&
            shield.isStackMode() == false &&
            shield.getShieldCount() == 1
        );

        return passed ? "✓ 初始模式测试通过" : "✗ 初始模式测试失败";
    }

    // ==================== 2. 单盾模式测试 ====================

    private static function testSingleMode():String {
        var results:Array = [];

        results.push(testSingle_AbsorbDamage());
        results.push(testSingle_StrengthLimit());
        results.push(testSingle_Recharging());
        results.push(testSingle_Decaying());
        results.push(testSingle_Duration());

        return formatResults(results, "单盾模式");
    }

    private static function testSingle_AbsorbDamage():String {
        var shield:AdaptiveShield = new AdaptiveShield(100, 50, 0, 0, "测试", "default");

        var penetrating:Number = shield.absorbDamage(30, false, 1);

        var passed:Boolean = (penetrating == 0 && shield.getCapacity() == 70);

        return passed ? "✓ 单盾伤害吸收测试通过" : "✗ 单盾伤害吸收测试失败";
    }

    private static function testSingle_StrengthLimit():String {
        var shield:AdaptiveShield = new AdaptiveShield(100, 50, 0, 0, "测试", "default");

        var penetrating:Number = shield.absorbDamage(80, false, 1);

        var passed:Boolean = (penetrating == 30 && shield.getCapacity() == 50);

        return passed ? "✓ 单盾强度限制测试通过" : "✗ 单盾强度限制测试失败";
    }

    private static function testSingle_Recharging():String {
        var shield:AdaptiveShield = new AdaptiveShield(100, 50, 5, 0, "测试", "default");
        shield.setCapacity(50);

        for (var i:Number = 0; i < 10; i++) {
            shield.update(1);
        }

        var passed:Boolean = (shield.getCapacity() == 100);

        return passed ? "✓ 单盾充能测试通过" : "✗ 单盾充能测试失败";
    }

    private static function testSingle_Decaying():String {
        var shield:AdaptiveShield = AdaptiveShield.createDecaying(100, 50, 5, "衰减盾");

        for (var i:Number = 0; i < 10; i++) {
            shield.update(1);
        }

        var passed:Boolean = (shield.getCapacity() == 50);

        return passed ? "✓ 单盾衰减测试通过" : "✗ 单盾衰减测试失败";
    }

    private static function testSingle_Duration():String {
        var shield:AdaptiveShield = AdaptiveShield.createTemporary(100, 50, 30, "临时盾");

        for (var i:Number = 0; i < 40; i++) {
            shield.update(1);
        }

        var passed:Boolean = (!shield.isActive() && shield.getDuration() == 0);

        return passed ? "✓ 单盾持续时间测试通过" : "✗ 单盾持续时间测试失败";
    }

    // ==================== 3. 工厂方法测试 ====================

    private static function testFactoryMethods():String {
        var results:Array = [];

        results.push(testFactory_CreateTemporary());
        results.push(testFactory_CreateRechargeable());
        results.push(testFactory_CreateDecaying());
        results.push(testFactory_CreateResistant());

        return formatResults(results, "工厂方法");
    }

    private static function testFactory_CreateTemporary():String {
        var shield:AdaptiveShield = AdaptiveShield.createTemporary(100, 50, 300, "临时盾");

        var passed:Boolean = (
            shield.getMaxCapacity() == 100 &&
            shield.getStrength() == 50 &&
            shield.getDuration() == 300 &&
            shield.isTemporary() == true
        );

        return passed ? "✓ createTemporary测试通过" : "✗ createTemporary测试失败";
    }

    private static function testFactory_CreateRechargeable():String {
        var shield:AdaptiveShield = AdaptiveShield.createRechargeable(200, 80, 5, 60, "充能盾");

        var passed:Boolean = (
            shield.getMaxCapacity() == 200 &&
            shield.getStrength() == 80 &&
            shield.getRechargeRate() == 5 &&
            shield.getRechargeDelay() == 60 &&
            shield.isTemporary() == false
        );

        return passed ? "✓ createRechargeable测试通过" : "✗ createRechargeable测试失败";
    }

    private static function testFactory_CreateDecaying():String {
        var shield:AdaptiveShield = AdaptiveShield.createDecaying(150, 60, 3, "衰减盾");

        var passed:Boolean = (
            shield.getMaxCapacity() == 150 &&
            shield.getStrength() == 60 &&
            shield.getRechargeRate() == -3 &&
            shield.isTemporary() == true
        );

        return passed ? "✓ createDecaying测试通过" : "✗ createDecaying测试失败";
    }

    private static function testFactory_CreateResistant():String {
        var shield:AdaptiveShield = AdaptiveShield.createResistant(100, 50, 200, "抗真伤盾");

        var passed:Boolean = (
            shield.getMaxCapacity() == 100 &&
            shield.getResistBypass() == true &&
            shield.isTemporary() == true
        );

        return passed ? "✓ createResistant测试通过" : "✗ createResistant测试失败";
    }

    // ==================== 4. 模式升级测试 ====================

    private static function testModeUpgrade():String {
        var results:Array = [];

        results.push(testUpgrade_AddShieldTriggersUpgrade());
        results.push(testUpgrade_StatePreservation());
        results.push(testUpgrade_MultipleShields());
        results.push(testUpgrade_DelayStateMigration());

        return formatResults(results, "模式升级");
    }

    private static function testUpgrade_AddShieldTriggersUpgrade():String {
        var shield:AdaptiveShield = new AdaptiveShield(100, 50, 0, 0, "主盾", "default");

        var wasSingle:Boolean = shield.isSingleMode();

        shield.addShield(Shield.createTemporary(100, 80, -1, "附加盾"));

        var isStack:Boolean = shield.isStackMode();

        var passed:Boolean = (wasSingle && isStack && shield.getShieldCount() == 2);

        return passed ? "✓ 添加护盾触发升级测试通过" : "✗ 添加护盾触发升级测试失败";
    }

    private static function testUpgrade_StatePreservation():String {
        var shield:AdaptiveShield = new AdaptiveShield(100, 50, 0, 0, "主盾", "default");
        shield.setCapacity(70);

        var oldCapacity:Number = shield.getCapacity();

        shield.addShield(Shield.createTemporary(100, 80, -1, "附加盾"));

        // 升级后总容量 = 70 + 100 = 170
        var newCapacity:Number = shield.getCapacity();

        var passed:Boolean = (oldCapacity == 70 && newCapacity == 170);

        return passed ? "✓ 状态保持测试通过" : "✗ 状态保持测试失败（" + newCapacity + "）";
    }

    private static function testUpgrade_MultipleShields():String {
        var shield:AdaptiveShield = new AdaptiveShield(100, 50, 0, 0, "主盾", "default");

        shield.addShield(Shield.createTemporary(100, 80, -1, "盾2"));
        shield.addShield(Shield.createTemporary(100, 60, -1, "盾3"));
        shield.addShield(Shield.createTemporary(100, 40, -1, "盾4"));

        var passed:Boolean = (
            shield.isStackMode() &&
            shield.getShieldCount() == 4 &&
            shield.getCapacity() == 400
        );

        return passed ? "✓ 多层护盾测试通过" : "✗ 多层护盾测试失败";
    }

    /**
     * 延迟状态精确迁移测试
     * 验证升级时 delayTimer 被精确迁移而非重置
     */
    private static function testUpgrade_DelayStateMigration():String {
        // 创建充能盾并触发延迟
        var shield:AdaptiveShield = AdaptiveShield.createRechargeable(100, 50, 5, 60, "充能盾");
        shield.setCapacity(50);
        shield.absorbDamage(10, false, 1); // 触发延迟

        // 记录升级前的延迟状态
        var delayedBefore:Boolean = shield.isDelayed();
        var timerBefore:Number = shield.getDelayTimer();

        // 更新一些帧，消耗部分延迟时间
        for (var i:Number = 0; i < 20; i++) {
            shield.update(1);
        }

        var timerAfterUpdate:Number = shield.getDelayTimer();
        var expectedTimer:Number = 60 - 20; // 应该是40

        // 升级到栈模式
        shield.addShield(Shield.createTemporary(100, 80, -1, "附加盾"));

        // 获取内部护盾检查延迟状态
        var shields:Array = shield.getShields();
        var innerShield:Shield = Shield(shields[0]); // 原单盾状态

        var innerDelayed:Boolean = innerShield.isDelayed();
        var innerTimer:Number = innerShield.getDelayTimer();

        var passed:Boolean = (
            delayedBefore == true &&
            timerBefore == 60 &&
            timerAfterUpdate == expectedTimer &&
            innerDelayed == true &&
            innerTimer == expectedTimer
        );

        return passed ? "✓ 延迟状态精确迁移测试通过" :
            "✗ 延迟状态精确迁移测试失败（迁移后timer=" + innerTimer + "，期望=" + expectedTimer + "）";
    }

    // ==================== 5. 栈模式测试 ====================

    private static function testStackMode():String {
        var results:Array = [];

        results.push(testStack_AbsorbDamage());
        results.push(testStack_StrengthLimit());
        results.push(testStack_MultiShieldDistribution());
        results.push(testStack_Sorting());

        return formatResults(results, "栈模式");
    }

    private static function testStack_AbsorbDamage():String {
        var shield:AdaptiveShield = new AdaptiveShield(100, 50, 0, 0, "主盾", "default");
        shield.addShield(Shield.createTemporary(100, 80, -1, "附加盾"));

        var penetrating:Number = shield.absorbDamage(50, false, 1);

        var passed:Boolean = (penetrating == 0 && shield.getCapacity() == 150);

        return passed ? "✓ 栈模式伤害吸收测试通过" : "✗ 栈模式伤害吸收测试失败";
    }

    private static function testStack_StrengthLimit():String {
        var shield:AdaptiveShield = new AdaptiveShield(1000, 50, 0, 0, "主盾", "default");
        shield.addShield(Shield.createTemporary(1000, 80, -1, "附加盾"));

        // 表观强度应该是80（最高）
        var strength:Number = shield.getStrength();

        // 伤害100，强度80 -> 吸收80，穿透20
        var penetrating:Number = shield.absorbDamage(100, false, 1);

        var passed:Boolean = (strength == 80 && penetrating == 20);

        return passed ? "✓ 栈模式强度限制测试通过" : "✗ 栈模式强度限制测试失败";
    }

    private static function testStack_MultiShieldDistribution():String {
        var shield:AdaptiveShield = new AdaptiveShield(50, 100, 0, 0, "主盾", "default");
        shield.addShield(Shield.createTemporary(100, 80, -1, "附加盾"));

        // 主盾容量50，附加盾容量100，总150
        // 伤害80 -> 先从高优先级盾消耗
        var penetrating:Number = shield.absorbDamage(80, false, 1);

        var passed:Boolean = (penetrating == 0 && shield.getCapacity() == 70);

        return passed ? "✓ 多护盾分配测试通过" : "✗ 多护盾分配测试失败（容量=" + shield.getCapacity() + "）";
    }

    private static function testStack_Sorting():String {
        var shield:AdaptiveShield = new AdaptiveShield(100, 30, 0, 0, "低强度", "default");
        shield.addShield(Shield.createTemporary(100, 100, -1, "高强度"));
        shield.addShield(Shield.createTemporary(100, 60, -1, "中强度"));

        // 表观强度应该是最高的
        var strength:Number = shield.getStrength();

        var passed:Boolean = (strength == 100);

        return passed ? "✓ 排序测试通过" : "✗ 排序测试失败（强度=" + strength + "）";
    }

    // ==================== 6. 模式降级测试 ====================

    private static function testModeDowngrade():String {
        var results:Array = [];

        results.push(testDowngrade_HysteresisWorks());
        results.push(testDowngrade_StateRecovery());
        results.push(testDowngrade_AllShieldsDepleted());
        results.push(testDowngrade_NoDowngradeForShieldStack());
        results.push(testDowngrade_DelayStateRecovery());

        return formatResults(results, "模式降级");
    }

    private static function testDowngrade_HysteresisWorks():String {
        var shield:AdaptiveShield = new AdaptiveShield(100, 50, 0, 0, "主盾", "default");
        var tempShield:Shield = Shield.createTemporary(100, 80, 10, "短期盾");
        shield.addShield(tempShield);

        // 更新15帧让临时盾过期
        for (var i:Number = 0; i < 15; i++) {
            shield.update(1);
        }

        // 应该还在栈模式（迟滞）
        var stillStack:Boolean = shield.isStackMode();

        // 继续更新30帧触发降级
        for (var j:Number = 0; j < 30; j++) {
            shield.update(1);
        }

        var nowSingle:Boolean = shield.isSingleMode();

        var passed:Boolean = (stillStack && nowSingle);

        return passed ? "✓ 降级迟滞测试通过" : "✗ 降级迟滞测试失败";
    }

    private static function testDowngrade_StateRecovery():String {
        var shield:AdaptiveShield = new AdaptiveShield(100, 50, 0, 0, "主盾", "default");
        shield.setCapacity(70);
        var tempShield:Shield = Shield.createTemporary(100, 80, 5, "短期盾");
        shield.addShield(tempShield);

        // 消耗一些容量
        shield.absorbDamage(50, false, 1);

        // 更新足够帧数让临时盾过期并降级
        for (var i:Number = 0; i < 50; i++) {
            shield.update(1);
        }

        // 降级后应该恢复到单盾状态
        var passed:Boolean = shield.isSingleMode();

        return passed ? "✓ 状态恢复测试通过" : "✗ 状态恢复测试失败";
    }

    private static function testDowngrade_AllShieldsDepleted():String {
        var shield:AdaptiveShield = AdaptiveShield.createTemporary(50, 100, 10, "主盾");
        shield.addShield(Shield.createTemporary(50, 80, 10, "附加盾"));

        var depletedCalled:Boolean = false;
        shield.onAllShieldsDepletedCallback = function(s:AdaptiveShield):Void {
            depletedCalled = true;
        };

        // 更新足够帧数让所有护盾过期
        for (var i:Number = 0; i < 20; i++) {
            shield.update(1);
        }

        var passed:Boolean = (depletedCalled && !shield.isActive());

        return passed ? "✓ 所有护盾耗尽测试通过" : "✗ 所有护盾耗尽测试失败";
    }

    /**
     * 嵌套 ShieldStack 不降级测试
     * 当最后一层为 ShieldStack 时，应保持栈模式不降级
     */
    private static function testDowngrade_NoDowngradeForShieldStack():String {
        var shield:AdaptiveShield = new AdaptiveShield(100, 50, 0, 0, "主盾", "default");

        // 添加一个 ShieldStack 作为子护盾
        var nestedStack:ShieldStack = new ShieldStack();
        nestedStack.addShield(Shield.createTemporary(100, 80, -1, "嵌套盾1"));
        nestedStack.addShield(Shield.createResistant(100, 60, -1, "嵌套抗真伤"));

        // 添加一个临时盾
        var tempShield:Shield = Shield.createTemporary(100, 70, 5, "短期盾");
        shield.addShield(tempShield);
        shield.addShield(nestedStack);

        // 让临时盾过期，只剩下主盾和嵌套栈
        for (var i:Number = 0; i < 10; i++) {
            shield.update(1);
        }

        // 移除主盾（通过让它消耗光），只剩下嵌套栈
        // 首先消耗掉主盾的容量
        var shields:Array = shield.getShields();
        var mainShield:Shield = Shield(shields[0]);
        mainShield.setActive(false); // 模拟主盾失效

        // 触发弹出
        shield.update(1);

        // 继续更新很多帧
        for (var j:Number = 0; j < 50; j++) {
            shield.update(1);
        }

        // 因为最后一层是 ShieldStack，不应降级
        var passed:Boolean = shield.isStackMode();

        return passed ? "✓ 嵌套ShieldStack不降级测试通过" : "✗ 嵌套ShieldStack不降级测试失败";
    }

    /**
     * 降级时延迟状态精确回填测试
     */
    private static function testDowngrade_DelayStateRecovery():String {
        // 创建充能盾并升级
        var shield:AdaptiveShield = AdaptiveShield.createRechargeable(100, 50, 5, 60, "充能盾");
        shield.setCapacity(50);

        // 添加临时盾触发升级
        var tempShield:Shield = Shield.createTemporary(100, 80, 5, "短期盾");
        shield.addShield(tempShield);

        // 获取内部的原始护盾并触发延迟
        var shields:Array = shield.getShields();
        var innerShield:Shield = Shield(shields[0]);
        innerShield.absorbDamage(10, false, 1); // 触发延迟

        // 更新20帧，延迟从60减到40
        for (var i:Number = 0; i < 20; i++) {
            shield.update(1);
        }

        var timerBeforeDowngrade:Number = innerShield.getDelayTimer();

        // 让临时盾过期并等待降级迟滞
        for (var j:Number = 0; j < 40; j++) {
            shield.update(1);
        }

        // 检查是否已降级
        var isSingle:Boolean = shield.isSingleMode();

        // 验证延迟状态被正确回填
        var isDelayed:Boolean = shield.isDelayed();
        var timer:Number = shield.getDelayTimer();

        // 预期：延迟已在内部护盾中继续消耗
        var passed:Boolean = isSingle && isDelayed == innerShield.isDelayed();

        return passed ? "✓ 降级延迟状态回填测试通过" : "✗ 降级延迟状态回填测试失败";
    }

    // ==================== 7. 联弹机制测试 ====================

    private static function testHitCount():String {
        var results:Array = [];

        results.push(testHitCount_SingleMode());
        results.push(testHitCount_StackMode());

        return formatResults(results, "联弹机制");
    }

    private static function testHitCount_SingleMode():String {
        var shield:AdaptiveShield = new AdaptiveShield(1000, 50, 0, 0, "测试", "default");

        // 10段联弹，总伤害600，有效强度500
        var penetrating:Number = shield.absorbDamage(600, false, 10);

        var passed:Boolean = (penetrating == 100 && shield.getCapacity() == 500);

        return passed ? "✓ 单盾联弹测试通过" : "✗ 单盾联弹测试失败";
    }

    private static function testHitCount_StackMode():String {
        var shield:AdaptiveShield = new AdaptiveShield(500, 50, 0, 0, "主盾", "default");
        shield.addShield(Shield.createTemporary(500, 80, -1, "附加盾"));

        // 表观强度80，10段联弹有效强度800
        // 总容量1000，伤害900 -> 全部吸收
        var penetrating:Number = shield.absorbDamage(900, false, 10);

        var passed:Boolean = (penetrating == 100 && shield.getCapacity() == 200);

        return passed ? "✓ 栈模式联弹测试通过" : "✗ 栈模式联弹测试失败";
    }

    // ==================== 8. 抵抗绕过测试 ====================

    private static function testResistBypass():String {
        var results:Array = [];

        results.push(testResist_SingleModeNoResist());
        results.push(testResist_SingleModeWithResist());
        results.push(testResist_StackModeAnyLayerResists());

        return formatResults(results, "抵抗绕过");
    }

    private static function testResist_SingleModeNoResist():String {
        var shield:AdaptiveShield = new AdaptiveShield(100, 50, 0, 0, "测试", "default");

        var penetrating:Number = shield.absorbDamage(30, true, 1);

        var passed:Boolean = (penetrating == 30 && shield.getCapacity() == 100);

        return passed ? "✓ 单盾无抵抗测试通过" : "✗ 单盾无抵抗测试失败";
    }

    private static function testResist_SingleModeWithResist():String {
        var shield:AdaptiveShield = AdaptiveShield.createResistant(100, 50, -1, "抗真伤盾");

        var penetrating:Number = shield.absorbDamage(30, true, 1);

        var passed:Boolean = (penetrating == 0 && shield.getCapacity() == 70);

        return passed ? "✓ 单盾抵抗测试通过" : "✗ 单盾抵抗测试失败";
    }

    private static function testResist_StackModeAnyLayerResists():String {
        var shield:AdaptiveShield = new AdaptiveShield(100, 50, 0, 0, "普通盾", "default");
        shield.addShield(Shield.createResistant(100, 80, -1, "抗真伤盾"));

        // 任意一层抵抗即可生效
        var penetrating:Number = shield.absorbDamage(30, true, 1);

        var passed:Boolean = (penetrating == 0 && shield.getResistantCount() > 0);

        return passed ? "✓ 栈模式任意层抵抗测试通过" : "✗ 栈模式任意层抵抗测试失败";
    }

    // ==================== 9. 回调测试 ====================

    private static function testCallbacks():String {
        var results:Array = [];

        results.push(testCallbacks_OnHit());
        results.push(testCallbacks_OnBreak());
        results.push(testCallbacks_OnExpire());
        results.push(testCallbacks_SetCallbacks());

        return formatResults(results, "回调");
    }

    private static function testCallbacks_OnHit():String {
        var shield:AdaptiveShield = new AdaptiveShield(100, 50, 0, 0, "测试", "default");
        var hitCount:Number = 0;

        shield.onHitCallback = function(s:IShield, absorbed:Number):Void {
            hitCount++;
        };

        shield.absorbDamage(20, false, 1);
        shield.absorbDamage(20, false, 1);

        var passed:Boolean = (hitCount == 2);

        return passed ? "✓ onHit回调测试通过" : "✗ onHit回调测试失败";
    }

    private static function testCallbacks_OnBreak():String {
        var shield:AdaptiveShield = new AdaptiveShield(30, 100, 0, 0, "测试", "default");
        shield.setTemporary(true);
        var breakCalled:Boolean = false;

        shield.onBreakCallback = function(s:IShield):Void {
            breakCalled = true;
        };

        shield.absorbDamage(50, false, 1);

        var passed:Boolean = (breakCalled && !shield.isActive());

        return passed ? "✓ onBreak回调测试通过" : "✗ onBreak回调测试失败";
    }

    private static function testCallbacks_OnExpire():String {
        var shield:AdaptiveShield = AdaptiveShield.createTemporary(100, 50, 10, "临时盾");
        var expireCalled:Boolean = false;

        shield.onExpireCallback = function(s:IShield):Void {
            expireCalled = true;
        };

        for (var i:Number = 0; i < 15; i++) {
            shield.update(1);
        }

        var passed:Boolean = (expireCalled && !shield.isActive());

        return passed ? "✓ onExpire回调测试通过" : "✗ onExpire回调测试失败";
    }

    private static function testCallbacks_SetCallbacks():String {
        var shield:AdaptiveShield = new AdaptiveShield(100, 50, 0, 0, "测试", "default");
        var hitCalled:Boolean = false;

        var result:AdaptiveShield = shield.setCallbacks({
            onHit: function(s, a) { hitCalled = true; }
        });

        shield.absorbDamage(10, false, 1);

        var passed:Boolean = (result === shield && hitCalled);

        return passed ? "✓ setCallbacks测试通过" : "✗ setCallbacks测试失败";
    }

    // ==================== 10. 边界条件测试 ====================

    private static function testBoundaryConditions():String {
        var results:Array = [];

        results.push(testBoundary_AddNullShield());
        results.push(testBoundary_AddInactiveShield());
        results.push(testBoundary_ZeroDamage());
        results.push(testBoundary_Clear());

        return formatResults(results, "边界条件");
    }

    private static function testBoundary_AddNullShield():String {
        var shield:AdaptiveShield = new AdaptiveShield(100, 50, 0, 0, "测试", "default");

        var added:Boolean = shield.addShield(null);

        var passed:Boolean = (!added && shield.isSingleMode());

        return passed ? "✓ 添加null护盾测试通过" : "✗ 添加null护盾测试失败";
    }

    private static function testBoundary_AddInactiveShield():String {
        var shield:AdaptiveShield = new AdaptiveShield(100, 50, 0, 0, "测试", "default");
        var inactive:Shield = Shield.createTemporary(100, 50, -1, "未激活");
        inactive.setActive(false);

        var added:Boolean = shield.addShield(inactive);

        var passed:Boolean = (!added && shield.isSingleMode());

        return passed ? "✓ 添加未激活护盾测试通过" : "✗ 添加未激活护盾测试失败";
    }

    private static function testBoundary_ZeroDamage():String {
        var shield:AdaptiveShield = new AdaptiveShield(100, 50, 0, 0, "测试", "default");

        var penetrating:Number = shield.absorbDamage(0, false, 1);

        var passed:Boolean = (penetrating == 0 && shield.getCapacity() == 100);

        return passed ? "✓ 零伤害测试通过" : "✗ 零伤害测试失败";
    }

    private static function testBoundary_Clear():String {
        var shield:AdaptiveShield = new AdaptiveShield(100, 50, 0, 0, "测试", "default");
        shield.addShield(Shield.createTemporary(100, 80, -1, "附加盾"));
        shield.absorbDamage(50, false, 1);

        shield.clear();

        var passed:Boolean = (
            shield.isSingleMode() &&
            shield.getCapacity() == 100 &&
            shield.getShieldCount() == 1
        );

        return passed ? "✓ clear测试通过" : "✗ clear测试失败";
    }

    // ==================== 11. 一致性对比测试 ====================

    private static function testConsistency():String {
        var results:Array = [];

        results.push(testConsistency_SingleVsShield());
        results.push(testConsistency_StackVsShieldStack());

        return formatResults(results, "一致性对比");
    }

    /**
     * 对比 AdaptiveShield(单盾模式) 与 Shield 的行为
     */
    private static function testConsistency_SingleVsShield():String {
        var adaptive:AdaptiveShield = new AdaptiveShield(100, 50, 5, 30, "测试", "default");
        var shield:Shield = new Shield(100, 50, 5, 30, "测试", "default");

        // 测试伤害吸收
        var pen1:Number = adaptive.absorbDamage(80, false, 1);
        var pen2:Number = shield.absorbDamage(80, false, 1);

        if (pen1 != pen2) {
            return "✗ 单盾一致性测试失败（穿透不一致）";
        }

        if (adaptive.getCapacity() != shield.getCapacity()) {
            return "✗ 单盾一致性测试失败（容量不一致）";
        }

        // 测试延迟充能
        for (var i:Number = 0; i < 50; i++) {
            adaptive.update(1);
            shield.update(1);
        }

        if (adaptive.getCapacity() != shield.getCapacity()) {
            return "✗ 单盾一致性测试失败（充能后容量不一致）";
        }

        return "✓ 单盾一致性测试通过";
    }

    /**
     * 对比 AdaptiveShield(栈模式) 与 ShieldStack 的行为
     */
    private static function testConsistency_StackVsShieldStack():String {
        // 创建 AdaptiveShield 并升级到栈模式
        var adaptive:AdaptiveShield = new AdaptiveShield(100, 50, 0, 0, "主盾", "default");
        adaptive.addShield(Shield.createTemporary(100, 80, -1, "附加盾1"));
        adaptive.addShield(Shield.createTemporary(100, 60, -1, "附加盾2"));

        // 创建等效的 ShieldStack
        var stack:ShieldStack = new ShieldStack();
        stack.addShield(new Shield(100, 50, 0, 0, "主盾", "default"));
        stack.addShield(Shield.createTemporary(100, 80, -1, "附加盾1"));
        stack.addShield(Shield.createTemporary(100, 60, -1, "附加盾2"));

        // 测试表观强度
        if (adaptive.getStrength() != stack.getStrength()) {
            return "✗ 栈一致性测试失败（强度不一致：" + adaptive.getStrength() + " vs " + stack.getStrength() + "）";
        }

        // 测试总容量
        if (adaptive.getCapacity() != stack.getCapacity()) {
            return "✗ 栈一致性测试失败（容量不一致）";
        }

        // 测试伤害吸收
        var pen1:Number = adaptive.absorbDamage(100, false, 1);
        var pen2:Number = stack.absorbDamage(100, false, 1);

        if (pen1 != pen2) {
            return "✗ 栈一致性测试失败（穿透不一致：" + pen1 + " vs " + pen2 + "）";
        }

        return "✓ 栈一致性测试通过";
    }

    // ==================== 12. 性能测试 ====================

    private static function testPerformance():String {
        var result:String = "";

        result += perfTest_SingleModeVsShield();
        result += perfTest_StackModeVsShieldStack();
        result += perfTest_ModeSwitch();

        return result;
    }

    private static function perfTest_SingleModeVsShield():String {
        var iterations:Number = 10000;

        // 测试 AdaptiveShield (单盾模式)
        var adaptive:AdaptiveShield = new AdaptiveShield(1000000, 100, 0, 0, "测试", "default");
        var startTime1:Number = getTimer();
        for (var i:Number = 0; i < iterations; i++) {
            adaptive.absorbDamage(50, false, 1);
        }
        var time1:Number = getTimer() - startTime1;

        // 测试 Shield
        var shield:Shield = new Shield(1000000, 100, 0, 0, "测试", "default");
        var startTime2:Number = getTimer();
        for (var j:Number = 0; j < iterations; j++) {
            shield.absorbDamage(50, false, 1);
        }
        var time2:Number = getTimer() - startTime2;

        var ratio:Number = Math.round(time1 / time2 * 100) / 100;

        return "单盾模式 vs Shield: AdaptiveShield " + time1 + "ms, Shield " + time2 + "ms (比率:" + ratio + "x)\n";
    }

    private static function perfTest_StackModeVsShieldStack():String {
        var iterations:Number = 10000;

        // 创建 AdaptiveShield (栈模式)
        var adaptive:AdaptiveShield = new AdaptiveShield(100000, 100, 0, 0, "主盾", "default");
        adaptive.addShield(Shield.createTemporary(100000, 80, -1, "附加盾"));

        var startTime1:Number = getTimer();
        for (var i:Number = 0; i < iterations; i++) {
            adaptive.absorbDamage(50, false, 1);
        }
        var time1:Number = getTimer() - startTime1;

        // 创建 ShieldStack
        var stack:ShieldStack = new ShieldStack();
        stack.addShield(new Shield(100000, 100, 0, 0, "主盾", "default"));
        stack.addShield(Shield.createTemporary(100000, 80, -1, "附加盾"));

        var startTime2:Number = getTimer();
        for (var j:Number = 0; j < iterations; j++) {
            stack.absorbDamage(50, false, 1);
        }
        var time2:Number = getTimer() - startTime2;

        var ratio:Number = Math.round(time1 / time2 * 100) / 100;

        return "栈模式 vs ShieldStack: AdaptiveShield " + time1 + "ms, ShieldStack " + time2 + "ms (比率:" + ratio + "x)\n";
    }

    private static function perfTest_ModeSwitch():String {
        var iterations:Number = 1000;
        var startTime:Number = getTimer();

        for (var i:Number = 0; i < iterations; i++) {
            var shield:AdaptiveShield = new AdaptiveShield(100, 50, 0, 0, "测试", "default");

            // 升级
            shield.addShield(Shield.createTemporary(100, 80, 5, "短期盾"));

            // 让护盾过期触发降级
            for (var j:Number = 0; j < 40; j++) {
                shield.update(1);
            }
        }

        var duration:Number = getTimer() - startTime;
        var avgTime:Number = Math.round(duration / iterations * 100) / 100;

        return "模式切换(升级+降级): " + iterations + "次 " + duration + "ms, 平均" + avgTime + "ms/次\n";
    }

    // ==================== 工具方法 ====================

    private static function getTimer():Number {
        return new Date().getTime();
    }

    private static function formatResults(results:Array, category:String):String {
        var allPassed:Boolean = true;
        var summary:String = "";

        for (var i:Number = 0; i < results.length; i++) {
            summary += results[i] + "\n";
            if (results[i].indexOf("✗") != -1) {
                allPassed = false;
            }
        }

        summary += allPassed ? category + " 所有测试通过！" : category + " 有测试失败！";
        return summary;
    }
}
