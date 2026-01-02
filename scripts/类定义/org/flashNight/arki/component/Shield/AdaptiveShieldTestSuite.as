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

        // 11. 空壳模式测试
        report += "【11. 空壳模式测试】\n";
        report += testDormantMode();
        report += "\n";

        // 12. 一致性对比测试
        report += "【12. 一致性对比测试】\n";
        report += testConsistency();
        report += "\n";

        // 13. 立场抗性测试
        report += "【13. 立场抗性测试】\n";
        report += testStanceResistance();
        report += "\n";

        // 14. 单盾模式ID稳定性测试
        report += "【14. 单盾模式ID稳定性测试】\n";
        report += testSingleModeIdStability();
        report += "\n";

        // 15. 回调重入修改结构测试
        report += "【15. 回调重入修改结构测试】\n";
        report += testCallbackReentry();
        report += "\n";

        // 16. 跨模式回调一致性契约测试
        report += "【16. 跨模式回调一致性契约测试】\n";
        report += testCallbackConsistency();
        report += "\n";

        // 17. bypass与抵抗层边界测试
        report += "【17. bypass与抵抗层边界测试】\n";
        report += testBypassResistBoundary();
        report += "\n";

        // 18. setter不变量测试
        report += "【18. setter不变量测试】\n";
        report += testSetterInvariants();
        report += "\n";

        // 19. 集成级战斗模拟测试
        report += "【19. 集成级战斗模拟测试】\n";
        report += testCombatSimulation();
        report += "\n";

        // 20. IShield 接口契约测试
        report += "【20. IShield 接口契约测试】\n";
        report += testIShieldInterface();
        report += "\n";

        // 21. ShieldSnapshot 测试
        report += "【21. ShieldSnapshot 测试】\n";
        report += testShieldSnapshot();
        report += "\n";

        // 22. 性能测试（放最后，避免影响功能测试结果判断）
        report += "【22. 性能测试】\n";
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
        // 无参数时进入空壳模式
        var dormant:AdaptiveShield = new AdaptiveShield();

        var dormantPassed:Boolean = (
            dormant.isDormantMode() &&
            dormant.getMaxCapacity() == 0 &&
            dormant.getCapacity() == 0 &&
            dormant.getStrength() == 0 &&
            dormant.getName() == "AdaptiveShield" &&
            dormant.getType() == "dormant"
        );

        // 传入有效参数时进入单盾模式
        var single:AdaptiveShield = new AdaptiveShield(100, 50, 0, 0, "测试", "default");

        var singlePassed:Boolean = (
            single.isSingleMode() &&
            single.getMaxCapacity() == 100 &&
            single.getCapacity() == 100 &&
            single.getStrength() == 50
        );

        var passed:Boolean = dormantPassed && singlePassed;

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

        // 临时盾过期后降级到空壳模式（保持激活，等待新护盾）
        var passed:Boolean = (shield.isDormantMode() && shield.isActive());

        return passed ? "✓ 单盾持续时间测试通过" : "✗ 单盾持续时间测试失败（isDormant=" + shield.isDormantMode() + ", isActive=" + shield.isActive() + "）";
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
        results.push(testStack_TopSwitchAfterDepletion());

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

    private static function testStack_TopSwitchAfterDepletion():String {
        var shield:AdaptiveShield = new AdaptiveShield(10, 100, 0, 0, "顶层", "default");
        shield.addShield(Shield.createTemporary(100, 50, -1, "内层"));

        // 第一次命中：顶层容量耗尽
        var pen1:Number = shield.absorbDamage(10, false, 1);
        var strengthAfter:Number = shield.getStrength();

        // 第二次命中：强度应切换到内层（50），60伤害应穿透10
        var pen2:Number = shield.absorbDamage(60, false, 1);

        var passed:Boolean = (pen1 == 0 && strengthAfter == 50 && pen2 == 10 && shield.getCapacity() == 50);

        return passed ? "✓ 栈顶耗尽后表观强度刷新测试通过" :
            "✗ 栈顶耗尽后表观强度刷新测试失败（pen1=" + pen1 + "，strength=" + strengthAfter +
            "，pen2=" + pen2 + "，cap=" + shield.getCapacity() + "）";
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
        var shield:AdaptiveShield = AdaptiveShield.createDormant("测试");
        shield.addShield(Shield.createTemporary(50, 100, 10, "主盾"));
        shield.addShield(Shield.createTemporary(50, 80, 10, "附加盾"));

        var depletedCalled:Boolean = false;
        shield.onAllShieldsDepletedCallback = function(s:AdaptiveShield):Void {
            depletedCalled = true;
        };

        // 更新足够帧数让所有护盾过期
        for (var i:Number = 0; i < 20; i++) {
            shield.update(1);
        }

        // 现在耗尽后降级到空壳模式，保持激活
        var passed:Boolean = (depletedCalled && shield.isDormantMode() && shield.isActive());

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
     *
     * 测试策略：
     * 1. 创建充能盾并升级到栈模式
     * 2. 在栈模式中触发延迟并消耗部分延迟时间
     * 3. 记录降级前内部护盾的延迟状态
     * 4. 让临时盾过期触发降级
     * 5. 验证降级后 AdaptiveShield 的延迟状态与降级前内部护盾一致
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
        innerShield.absorbDamage(10, false, 1); // 触发延迟，timer=60

        // 更新一些帧，延迟从60减少
        // 临时盾 duration=5，会在第5帧过期
        // 然后需要30帧迟滞才降级
        // 所以降级发生在第35帧左右
        for (var i:Number = 0; i < 4; i++) {
            shield.update(1);
        }

        // 记录降级前内部护盾的状态（此时 timer 应该是 60-4=56）
        var delayedBeforeDowngrade:Boolean = innerShield.isDelayed();
        var timerBeforeDowngrade:Number = innerShield.getDelayTimer();

        // 继续更新让临时盾过期并触发降级迟滞
        // 临时盾在下一帧过期，然后需要30帧迟滞
        for (var j:Number = 0; j < 35; j++) {
            shield.update(1);
        }

        // 检查是否已降级
        var isSingle:Boolean = shield.isSingleMode();

        // 降级后的延迟状态
        var delayedAfterDowngrade:Boolean = shield.isDelayed();
        var timerAfterDowngrade:Number = shield.getDelayTimer();

        // 计算预期值：
        // 降级发生时内部护盾已经更新了 4+35=39 帧
        // 延迟从60开始，消耗39帧后变为 60-39=21（如果仍在延迟中）
        // 由于延迟60帧，39帧后仍在延迟中
        var expectedTimer:Number = 60 - 39; // = 21

        // 验证：
        // 1. 必须已降级
        // 2. 降级后的延迟状态应该与预期一致
        var passed:Boolean = (
            isSingle &&
            delayedAfterDowngrade == true &&
            timerAfterDowngrade == expectedTimer
        );

        return passed ? "✓ 降级延迟状态回填测试通过" :
            "✗ 降级延迟状态回填测试失败（isSingle=" + isSingle +
            ", delayed=" + delayedAfterDowngrade +
            ", timer=" + timerAfterDowngrade + ", 期望=" + expectedTimer + "）";
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
        results.push(testCallbacks_InnerShieldCallbackPreserved());
        results.push(testCallbacks_FlattenedModeNoInnerCallback());
        results.push(testCallbacks_PreserveReferenceParameter());

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

        // 碎盾后降级到空壳模式（保持激活）
        var passed:Boolean = (breakCalled && shield.isDormantMode() && shield.isActive());

        return passed ? "✓ onBreak回调测试通过" : "✗ onBreak回调测试失败（breakCalled=" + breakCalled + ", isDormant=" + shield.isDormantMode() + "）";
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

        // 过期后降级到空壳模式（保持激活）
        var passed:Boolean = (expireCalled && shield.isDormantMode() && shield.isActive());

        return passed ? "✓ onExpire回调测试通过" : "✗ onExpire回调测试失败（expireCalled=" + expireCalled + ", isDormant=" + shield.isDormantMode() + "）";
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

    /**
     * 测试通过 addShield 推入护盾时，内部护盾的自定义回调是否被保留
     *
     * 【Option C 双策略说明】
     * - 有自定义回调的护盾会自动检测并使用委托模式（isDelegateMode=true）
     * - 这样可以保留内部护盾的回调逻辑
     */
    private static function testCallbacks_InnerShieldCallbackPreserved():String {
        // 创建一个空壳容器
        var container:AdaptiveShield = AdaptiveShield.createDormant("容器");

        // 创建一个带有自定义回调的 Shield
        // 使用强度100确保单次攻击能击碎（强度>=容量）
        var innerShield:Shield = Shield.createTemporary(100, 100, -1, "内部盾");
        var innerHitCalled:Boolean = false;
        var innerBreakCalled:Boolean = false;

        innerShield.onHitCallback = function(s:IShield, absorbed:Number):Void {
            innerHitCalled = true;
        };
        innerShield.onBreakCallback = function(s:IShield):Void {
            innerBreakCalled = true;
        };

        // 推入护盾（有回调会自动使用委托模式）
        container.addShield(innerShield);

        // 验证进入了单盾模式，且是委托模式
        var isSingle:Boolean = container.isSingleMode();
        var isDelegate:Boolean = container.isDelegateMode();

        // 吸收伤害，应该触发内部护盾的 onHit 回调
        container.absorbDamage(30, false, 1);

        // 击碎护盾：强度100，容量剩余70，打120伤害，吸收70，触发 onBreak
        container.absorbDamage(120, false, 1);

        var passed:Boolean = (isSingle && isDelegate && innerHitCalled && innerBreakCalled);

        return passed ? "✓ 内部护盾回调保留测试通过（委托模式）" :
            "✗ 内部护盾回调保留测试失败（isSingle=" + isSingle +
            ", isDelegate=" + isDelegate +
            ", innerHit=" + innerHitCalled +
            ", innerBreak=" + innerBreakCalled + "）";
    }

    /**
     * 测试无回调的护盾自动使用扁平化模式
     */
    private static function testCallbacks_FlattenedModeNoInnerCallback():String {
        // 创建一个空壳容器
        var container:AdaptiveShield = AdaptiveShield.createDormant("容器");

        // 创建一个没有自定义回调的 Shield
        var innerShield:Shield = Shield.createTemporary(100, 50, -1, "内部盾");
        // 不设置任何回调

        // 推入护盾（无回调应使用扁平化模式）
        container.addShield(innerShield);

        // 验证进入了单盾模式，且是扁平化模式
        var isSingle:Boolean = container.isSingleMode();
        var isFlattened:Boolean = container.isFlattenedMode();

        // 验证容器级回调仍然有效
        var containerHitCalled:Boolean = false;
        container.onHitCallback = function(s:IShield, absorbed:Number):Void {
            containerHitCalled = true;
        };

        container.absorbDamage(30, false, 1);

        var passed:Boolean = (isSingle && isFlattened && containerHitCalled);

        return passed ? "✓ 扁平化模式测试通过（无内部回调时自动扁平化）" :
            "✗ 扁平化模式测试失败（isSingle=" + isSingle +
            ", isFlattened=" + isFlattened +
            ", containerHit=" + containerHitCalled + "）";
    }

    /**
     * 测试 preserveReference 参数强制使用委托模式
     */
    private static function testCallbacks_PreserveReferenceParameter():String {
        // 创建一个空壳容器
        var container:AdaptiveShield = AdaptiveShield.createDormant("容器");

        // 创建一个没有自定义回调的 Shield
        var innerShield:Shield = Shield.createTemporary(100, 50, -1, "内部盾");

        // 使用 preserveReference=true 强制委托模式
        container.addShield(innerShield, true);

        // 验证进入了委托模式
        var isSingle:Boolean = container.isSingleMode();
        var isDelegate:Boolean = container.isDelegateMode();

        var passed:Boolean = (isSingle && isDelegate);

        return passed ? "✓ preserveReference参数测试通过（强制委托模式）" :
            "✗ preserveReference参数测试失败（isSingle=" + isSingle +
            ", isDelegate=" + isDelegate + "）";
    }

    // ==================== 10. 边界条件测试 ====================

    private static function testBoundaryConditions():String {
        var results:Array = [];

        results.push(testBoundary_AddNullShield());
        results.push(testBoundary_AddInactiveShield());
        results.push(testBoundary_AddSelfShield());
        results.push(testBoundary_PreventContainerCycle());
        results.push(testBoundary_AddDuplicateShield());
        results.push(testBoundary_AddDuplicateShieldInStackMode());
        results.push(testBoundary_ZeroDamage());
        results.push(testBoundary_Clear());
        results.push(testBoundary_NoRepeatBreakCallback());
        results.push(testBoundary_NoRepeatBreakCallback_ConsumeCapacity());
        results.push(testBoundary_SetCapacityClamping());
        results.push(testBoundary_SetMaxCapacityClamping());

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

    private static function testBoundary_AddSelfShield():String {
        var shield:AdaptiveShield = AdaptiveShield.createDormant("测试");
        var added:Boolean = shield.addShield(shield);
        var passed:Boolean = (!added && shield.isDormantMode() && shield.getShieldCount() == 0);
        return passed ? "✓ 添加自身护盾测试通过" : "✗ 添加自身护盾测试失败";
    }

    /**
     * P0：容器环(cycle)防护
     *
     * 【场景】
     * outer(AdaptiveShield) 已包含 inner(ShieldStack)，若允许 inner.addShield(outer) 将形成 A->B->A 的环，
     * 在递归聚合路径（如 getResistantCount）会导致无限递归/卡死。
     */
    private static function testBoundary_PreventContainerCycle():String {
        var outer:AdaptiveShield = AdaptiveShield.createDormant("outer");
        var inner:ShieldStack = new ShieldStack();

        var addedOuter:Boolean = outer.addShield(inner);
        var addedInner:Boolean = inner.addShield(outer); // 应拒绝形成环

        var passed:Boolean = (addedOuter == true && addedInner == false && inner.getShieldCount() == 0 && outer.getShieldCount() == 1);
        return passed ? "✓ 容器环防护测试通过" :
            "✗ 容器环防护测试失败（addedOuter=" + addedOuter + ", addedInner=" + addedInner +
            ", innerCount=" + inner.getShieldCount() + ", outerCount=" + outer.getShieldCount() + "）";
    }

    private static function testBoundary_AddDuplicateShield():String {
        var container:AdaptiveShield = AdaptiveShield.createDormant("测试");
        var inner:Shield = Shield.createTemporary(100, 50, -1, "重复盾");

        var first:Boolean = container.addShield(inner);
        var second:Boolean = container.addShield(inner); // 应拒绝重复引用

        var passed:Boolean = (first == true && second == false && container.getShieldCount() == 1);
        return passed ? "✓ 添加重复护盾测试通过" :
            "✗ 添加重复护盾测试失败（first=" + first + ", second=" + second + ", count=" + container.getShieldCount() + "）";
    }

    private static function testBoundary_AddDuplicateShieldInStackMode():String {
        var container:AdaptiveShield = AdaptiveShield.createDormant("测试");
        var shield1:Shield = Shield.createTemporary(100, 80, -1, "盾1");
        var shield2:Shield = Shield.createTemporary(100, 60, -1, "盾2");

        container.addShield(shield1);
        container.addShield(shield2);

        var addedAgain:Boolean = container.addShield(shield2);
        var passed:Boolean = (addedAgain == false && container.getShieldCount() == 2);

        return passed ? "✓ 栈模式重复引用防护测试通过" :
            "✗ 栈模式重复引用防护测试失败（addedAgain=" + addedAgain + ", count=" + container.getShieldCount() + "）";
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

        // clear() 现在会重置到空壳模式
        var passed:Boolean = (
            shield.isDormantMode() &&
            shield.getCapacity() == 0 &&
            shield.getShieldCount() == 0 &&
            shield.isActive()  // 保持激活以接收新护盾
        );

        return passed ? "✓ clear测试通过" : "✗ clear测试失败";
    }

    /**
     * 回归测试：容量为0时不应重复触发 onBreakCallback
     *
     * 【问题背景】
     * 扁平化模式的 _singleFlat_absorbDamage 原实现遗漏了 capacity <= 0 的提前返回检查，
     * 导致非临时可回充盾在容量耗尽后每次受击都会重复触发 onBreakCallback。
     */
    private static function testBoundary_NoRepeatBreakCallback():String {
        // 使用可回充盾（非临时盾，不会降级到空壳模式）
        // 注意：强度=Infinity 确保伤害不被强度限制，能一次打空
        var shield:AdaptiveShield = AdaptiveShield.createRechargeable(100, Infinity, 5, 30, "可回充盾");

        var breakCount:Number = 0;
        shield.onBreakCallback = function(s:IShield):Void {
            breakCount++;
        };

        // 第一次打空护盾（强度无限，100伤害直接打空100容量）
        shield.absorbDamage(100, false, 1);
        var afterFirstBreak:Number = breakCount;  // 应为 1

        // 容量为 0 时再次受击（不应触发 onBreakCallback）
        shield.absorbDamage(50, false, 1);
        shield.absorbDamage(50, false, 1);
        shield.absorbDamage(50, false, 1);
        var afterRepeatedHits:Number = breakCount;  // 应仍为 1

        var passed:Boolean = (afterFirstBreak == 1 && afterRepeatedHits == 1);

        return passed ? "✓ 容量为0不重复触发onBreak测试通过" :
            "✗ 容量为0不重复触发onBreak测试失败（首次=" + afterFirstBreak + ", 重复后=" + afterRepeatedHits + "）";
    }

    /**
     * 回归测试：consumeCapacity 在容量为0时不应重复触发 onBreakCallback
     */
    private static function testBoundary_NoRepeatBreakCallback_ConsumeCapacity():String {
        var shield:AdaptiveShield = AdaptiveShield.createRechargeable(100, 50, 5, 30, "可回充盾");

        var breakCount:Number = 0;
        shield.onBreakCallback = function(s:IShield):Void {
            breakCount++;
        };

        // 直接消耗容量打空护盾
        shield.consumeCapacity(100);
        var afterFirstBreak:Number = breakCount;  // 应为 1

        // 容量为 0 时再次消耗（不应触发 onBreakCallback）
        shield.consumeCapacity(50);
        shield.consumeCapacity(50);
        var afterRepeatedConsume:Number = breakCount;  // 应仍为 1

        var passed:Boolean = (afterFirstBreak == 1 && afterRepeatedConsume == 1);

        return passed ? "✓ consumeCapacity容量为0不重复触发onBreak测试通过" :
            "✗ consumeCapacity容量为0不重复触发onBreak测试失败（首次=" + afterFirstBreak + ", 重复后=" + afterRepeatedConsume + "）";
    }

    /**
     * 测试：扁平化模式 setCapacity 钳位行为
     *
     * 【问题背景】
     * 扁平化模式的 setCapacity 原实现直接赋值，没有像 BaseShield 那样做钳位：
     * - 负数应钳位到 0
     * - 超过 maxCapacity 应钳位到 maxCapacity
     */
    private static function testBoundary_SetCapacityClamping():String {
        // 使用扁平化模式的护盾
        var shield:AdaptiveShield = new AdaptiveShield(100, 50, 0, 0, "测试", "default");

        // 测试负数钳位
        shield.setCapacity(-50);
        var afterNegative:Number = shield.getCapacity();  // 应为 0

        // 测试超过最大值钳位
        shield.setCapacity(200);
        var afterOverMax:Number = shield.getCapacity();  // 应为 100（maxCapacity）

        // 测试正常值
        shield.setCapacity(50);
        var afterNormal:Number = shield.getCapacity();  // 应为 50

        var passed:Boolean = (afterNegative == 0 && afterOverMax == 100 && afterNormal == 50);

        return passed ? "✓ setCapacity钳位测试通过" :
            "✗ setCapacity钳位测试失败（负数后=" + afterNegative + ", 超限后=" + afterOverMax + ", 正常=" + afterNormal + "）";
    }

    /**
     * 测试：扁平化模式 setMaxCapacity 同步调整容量
     *
     * 【问题背景】
     * 扁平化模式的 setMaxCapacity 原实现直接赋值，没有像 BaseShield 那样：
     * - 如果当前容量超过新的最大容量，应同步调整容量
     */
    private static function testBoundary_SetMaxCapacityClamping():String {
        // 使用扁平化模式的护盾
        var shield:AdaptiveShield = new AdaptiveShield(100, 50, 0, 0, "测试", "default");

        // 当前容量为 100，降低最大容量到 50
        shield.setMaxCapacity(50);
        var capacityAfterReduce:Number = shield.getCapacity();  // 应为 50（被同步调整）
        var maxAfterReduce:Number = shield.getMaxCapacity();    // 应为 50

        // 提高最大容量到 80，容量不应自动增加
        shield.setMaxCapacity(80);
        var capacityAfterIncrease:Number = shield.getCapacity();  // 应仍为 50
        var maxAfterIncrease:Number = shield.getMaxCapacity();    // 应为 80

        var passed:Boolean = (
            capacityAfterReduce == 50 &&
            maxAfterReduce == 50 &&
            capacityAfterIncrease == 50 &&
            maxAfterIncrease == 80
        );

        return passed ? "✓ setMaxCapacity同步容量测试通过" :
            "✗ setMaxCapacity同步容量测试失败（降低后cap=" + capacityAfterReduce + "/max=" + maxAfterReduce +
            ", 提高后cap=" + capacityAfterIncrease + "/max=" + maxAfterIncrease + "）";
    }

    // ==================== 11. 空壳模式测试 ====================

    private static function testDormantMode():String {
        var results:Array = [];

        results.push(testDormant_DefaultConstructor());
        results.push(testDormant_CreateDormant());
        results.push(testDormant_AbsorbDamage());
        results.push(testDormant_Properties());
        results.push(testDormant_AddShieldUpgrade());
        results.push(testDormant_AddShieldStackUpgrade());
        results.push(testDormant_DepletionDowngrade());
        results.push(testDormant_FullLifecycle());
        results.push(testDormant_PersistAfterClear());

        return formatResults(results, "空壳模式");
    }

    /**
     * 测试无参数构造函数进入空壳模式
     */
    private static function testDormant_DefaultConstructor():String {
        var shield:AdaptiveShield = new AdaptiveShield();

        var passed:Boolean = (
            shield.isDormantMode() &&
            shield.getCapacity() == 0 &&
            shield.getStrength() == 0 &&
            shield.getShieldCount() == 0 &&
            shield.isActive() &&
            shield.isEmpty()
        );

        return passed ? "✓ 无参构造空壳模式测试通过" : "✗ 无参构造空壳模式测试失败";
    }

    /**
     * 测试 createDormant 工厂方法
     */
    private static function testDormant_CreateDormant():String {
        var shield:AdaptiveShield = AdaptiveShield.createDormant("测试空壳");

        var passed:Boolean = (
            shield.isDormantMode() &&
            shield.getName() == "测试空壳" &&
            shield.getType() == "dormant" &&
            shield.isActive()
        );

        return passed ? "✓ createDormant工厂方法测试通过" : "✗ createDormant工厂方法测试失败";
    }

    /**
     * 测试空壳模式下伤害直接穿透
     */
    private static function testDormant_AbsorbDamage():String {
        var shield:AdaptiveShield = AdaptiveShield.createDormant("测试");

        var penetrating:Number = shield.absorbDamage(100, false, 1);

        var passed:Boolean = (
            penetrating == 100 &&
            shield.getCapacity() == 0 &&
            shield.isDormantMode()  // 仍保持空壳模式
        );

        return passed ? "✓ 空壳模式伤害穿透测试通过" : "✗ 空壳模式伤害穿透测试失败";
    }

    /**
     * 测试空壳模式下所有属性返回值
     */
    private static function testDormant_Properties():String {
        var shield:AdaptiveShield = AdaptiveShield.createDormant("测试");

        var passed:Boolean = (
            shield.getCapacity() == 0 &&
            shield.getMaxCapacity() == 0 &&
            shield.getTargetCapacity() == 0 &&
            shield.getStrength() == 0 &&
            shield.getRechargeRate() == 0 &&
            shield.getRechargeDelay() == 0 &&
            shield.getResistantCount() == 0 &&
            shield.isEmpty() == true &&
            shield.isActive() == true &&
            shield.update(1) == false  // update 返回 false
        );

        return passed ? "✓ 空壳模式属性测试通过" : "✗ 空壳模式属性测试失败";
    }

    /**
     * 测试空壳模式添加单护盾后升级到单盾模式（最优热路径）
     */
    private static function testDormant_AddShieldUpgrade():String {
        var shield:AdaptiveShield = AdaptiveShield.createDormant("测试");

        var wasDormant:Boolean = shield.isDormantMode();

        shield.addShield(Shield.createTemporary(100, 50, -1, "护盾1"));

        // 添加单个 Shield 应进入单盾模式（最优热路径）
        var isSingle:Boolean = shield.isSingleMode();

        var passed:Boolean = (
            wasDormant &&
            isSingle &&
            shield.getCapacity() == 100 &&
            shield.getStrength() == 50
        );

        return passed ? "✓ 空壳升级到单盾模式测试通过" : "✗ 空壳升级到单盾模式测试失败（isSingle=" + isSingle + "）";
    }

    /**
     * 测试空壳模式添加 ShieldStack 后升级到栈模式
     */
    private static function testDormant_AddShieldStackUpgrade():String {
        var shield:AdaptiveShield = AdaptiveShield.createDormant("测试");

        var wasDormant:Boolean = shield.isDormantMode();

        // 添加 ShieldStack（嵌套栈）应进入栈模式
        var innerStack:ShieldStack = new ShieldStack();
        innerStack.addShield(Shield.createTemporary(100, 50, -1, "护盾1"));
        innerStack.addShield(Shield.createTemporary(80, 40, -1, "护盾2"));

        shield.addShield(innerStack);

        var isStack:Boolean = shield.isStackMode();

        var passed:Boolean = (
            wasDormant &&
            isStack &&
            shield.getShieldCount() == 1 &&  // 1个 ShieldStack
            shield.getCapacity() == 180 &&   // 100 + 80
            shield.getStrength() == 50       // 最高强度
        );

        return passed ? "✓ 空壳升级到栈模式(嵌套栈)测试通过" : "✗ 空壳升级到栈模式(嵌套栈)测试失败（isStack=" + isStack + "）";
    }

    /**
     * 测试护盾耗尽后降级回空壳模式
     */
    private static function testDormant_DepletionDowngrade():String {
        var shield:AdaptiveShield = AdaptiveShield.createDormant("测试");

        // 添加临时盾（单护盾进入单盾模式）
        shield.addShield(Shield.createTemporary(100, 50, 5, "短期盾"));

        var wasSingle:Boolean = shield.isSingleMode();

        // 让护盾过期
        for (var i:Number = 0; i < 10; i++) {
            shield.update(1);
        }

        var isDormant:Boolean = shield.isDormantMode();
        var isActive:Boolean = shield.isActive();

        var passed:Boolean = (
            wasSingle &&
            isDormant &&
            isActive  // 保持激活
        );

        return passed ? "✓ 耗尽降级回空壳模式测试通过" : "✗ 耗尽降级回空壳模式测试失败（wasSingle=" + wasSingle + ", isDormant=" + isDormant + ", isActive=" + isActive + "）";
    }

    /**
     * 测试完整生命周期：空壳 → 单盾 → 空壳 → 单盾
     */
    private static function testDormant_FullLifecycle():String {
        var shield:AdaptiveShield = AdaptiveShield.createDormant("生命周期测试");

        // 阶段1：空壳模式
        var phase1:Boolean = shield.isDormantMode();

        // 阶段2：添加单护盾，升级到单盾模式（最优热路径）
        shield.addShield(Shield.createTemporary(100, 50, 5, "临时盾"));
        var phase2:Boolean = shield.isSingleMode();

        // 阶段3：让护盾过期，降级回空壳
        for (var i:Number = 0; i < 10; i++) {
            shield.update(1);
        }
        var phase3:Boolean = shield.isDormantMode() && shield.isActive();

        // 阶段4：再次添加单护盾，升级到单盾模式
        shield.addShield(Shield.createRechargeable(200, 80, 5, 30, "充能盾"));
        var phase4:Boolean = shield.isSingleMode() && shield.getCapacity() == 200;

        var passed:Boolean = phase1 && phase2 && phase3 && phase4;

        return passed ? "✓ 完整生命周期测试通过" : "✗ 完整生命周期测试失败（" +
            "phase1=" + phase1 + ", phase2=" + phase2 + ", phase3=" + phase3 + ", phase4=" + phase4 + "）";
    }

    /**
     * 测试 clear() 后仍可接收新护盾
     */
    private static function testDormant_PersistAfterClear():String {
        var shield:AdaptiveShield = new AdaptiveShield(100, 50, 0, 0, "测试", "default");

        // 添加护盾并消耗
        shield.addShield(Shield.createTemporary(100, 80, -1, "附加盾"));
        shield.absorbDamage(50, false, 1);

        // 清空
        shield.clear();

        var afterClear:Boolean = shield.isDormantMode() && shield.isActive();

        // 再次添加单护盾（进入单盾模式）
        shield.addShield(Shield.createTemporary(150, 60, -1, "新护盾"));

        var afterAdd:Boolean = shield.isSingleMode() && shield.getCapacity() == 150;

        var passed:Boolean = afterClear && afterAdd;

        return passed ? "✓ clear后持久存在测试通过" : "✗ clear后持久存在测试失败（afterClear=" + afterClear + ", afterAdd=" + afterAdd + "）";
    }

    // ==================== 12. 一致性对比测试 ====================

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

    // ==================== 20. 性能测试 ====================

    private static function testPerformance():String {
        var result:String = "";

        result += perfTest_SingleModeVsShield();
        result += perfTest_FlattenedVsDelegate();
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

    /**
     * 扁平化模式 vs 委托模式性能对比
     */
    private static function perfTest_FlattenedVsDelegate():String {
        var iterations:Number = 10000;

        // 扁平化模式（通过 addShield 无回调的护盾）
        var flatContainer:AdaptiveShield = AdaptiveShield.createDormant("扁平化容器");
        var flatShield:Shield = new Shield(1000000, 100, 0, 0, "扁平盾", "default");
        flatContainer.addShield(flatShield); // 无回调自动扁平化

        var startTime1:Number = getTimer();
        for (var i:Number = 0; i < iterations; i++) {
            flatContainer.absorbDamage(50, false, 1);
        }
        var time1:Number = getTimer() - startTime1;

        // 委托模式（通过 preserveReference=true）
        var delegateContainer:AdaptiveShield = AdaptiveShield.createDormant("委托容器");
        var delegateShield:Shield = new Shield(1000000, 100, 0, 0, "委托盾", "default");
        delegateContainer.addShield(delegateShield, true); // 强制委托

        var startTime2:Number = getTimer();
        for (var j:Number = 0; j < iterations; j++) {
            delegateContainer.absorbDamage(50, false, 1);
        }
        var time2:Number = getTimer() - startTime2;

        var ratio:Number = Math.round(time2 / time1 * 100) / 100;

        return "扁平化 vs 委托: 扁平化 " + time1 + "ms, 委托 " + time2 + "ms (委托/扁平化:" + ratio + "x)\n";
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

    // ==================== 13. 立场抗性测试 ====================

    private static function testStanceResistance():String {
        var results:Array = [];

        results.push(testStance_DormantDeletesResistance());
        results.push(testStance_SingleModeWritesResistance());
        results.push(testStance_StackModeWritesResistance());
        results.push(testStance_ModeSwitchSyncsResistance());
        results.push(testStance_StrengthChangeSyncsResistance());
        results.push(testStance_RemoveShieldSyncsResistance());
        results.push(testStance_RemoveShieldByIdSyncsResistance());
        results.push(testStance_RemoveToZeroDowngradesToDormant());
        results.push(testStance_ClearSyncsResistance());
        results.push(testStance_OwnerBindingTriggersSync());
        results.push(testStance_NoOwnerSafeNoop());
        results.push(testStance_NoResistTableSafeNoop());
        results.push(testStance_RefreshForceSync());
        results.push(testStance_CachePreventsRedundantWrite());

        return formatResults(results, "立场抗性");
    }

    /**
     * 测试空壳模式下删除立场抗性字段
     *
     * 【业务规则】
     * 空壳模式表示护盾不参与逻辑，此时应删除 魔法抗性["立场"]
     * 以便破击逻辑正确识别为"无抗性"
     */
    private static function testStance_DormantDeletesResistance():String {
        // 创建模拟单位
        var owner:Object = {
            魔法抗性: {
                基础: 10,
                立场: 999  // 初始值，应被删除
            }
        };

        // 创建空壳护盾并绑定
        var shield:AdaptiveShield = AdaptiveShield.createDormant("测试空壳");
        shield.setOwner(owner);

        // 验证立场抗性被删除
        var passed:Boolean = (owner.魔法抗性["立场"] == undefined);

        return passed ? "✓ 空壳模式删除立场抗性测试通过" :
            "✗ 空壳模式删除立场抗性测试失败（立场=" + owner.魔法抗性["立场"] + "）";
    }

    /**
     * 测试单盾模式写入立场抗性
     *
     * 【业务规则】
     * 非空壳模式下，立场抗性 = 基础抗性 + 护盾强度加成
     * 加成公式：bonus = strength / (strength + 100) * 30
     */
    private static function testStance_SingleModeWritesResistance():String {
        var owner:Object = {
            魔法抗性: {
                基础: 10
            }
        };

        // 创建强度50的护盾
        var shield:AdaptiveShield = new AdaptiveShield(100, 50, 0, 0, "测试", "default");
        shield.setOwner(owner);

        // 计算期望值：强度50 -> bonus = 50/(50+100)*30 = 10
        var expectedBonus:Number = ShieldUtil.calcResistanceBonus(50);
        var expectedResist:Number = 10 + expectedBonus;

        var actualResist:Number = owner.魔法抗性["立场"];
        var passed:Boolean = (Math.abs(actualResist - expectedResist) < 0.001);

        return passed ? "✓ 单盾模式写入立场抗性测试通过" :
            "✗ 单盾模式写入立场抗性测试失败（期望=" + expectedResist + ", 实际=" + actualResist + "）";
    }

    /**
     * 测试栈模式写入立场抗性
     *
     * 【业务规则】
     * 栈模式下使用表观强度（最高优先级护盾的强度）计算加成
     */
    private static function testStance_StackModeWritesResistance():String {
        var owner:Object = {
            魔法抗性: {
                基础: 15
            }
        };

        // 创建护盾并升级到栈模式
        var shield:AdaptiveShield = new AdaptiveShield(100, 50, 0, 0, "主盾", "default");
        shield.addShield(Shield.createTemporary(100, 80, -1, "高强度盾"));
        shield.setOwner(owner);

        // 表观强度应该是80（最高）
        var stackStrength:Number = shield.getStrength();

        // 计算期望值
        var expectedBonus:Number = ShieldUtil.calcResistanceBonus(stackStrength);
        var expectedResist:Number = 15 + expectedBonus;

        var actualResist:Number = owner.魔法抗性["立场"];
        var passed:Boolean = (
            stackStrength == 80 &&
            Math.abs(actualResist - expectedResist) < 0.001
        );

        return passed ? "✓ 栈模式写入立场抗性测试通过" :
            "✗ 栈模式写入立场抗性测试失败（强度=" + stackStrength +
            ", 期望=" + expectedResist + ", 实际=" + actualResist + "）";
    }

    /**
     * 测试模式切换时立场抗性同步
     *
     * 【业务规则】
     * - 空壳 → 单盾：写入抗性
     * - 单盾 → 栈模式：addShield() 后立即同步（无需额外触发）
     * - 栈模式 → 空壳：删除抗性
     *
     * 【实现说明】
     * addShield() 在栈路径 push 后会立即调用 _syncStanceResistance()，
     * 确保 owner.魔法抗性["立场"] 与新的表观强度一致。
     */
    private static function testStance_ModeSwitchSyncsResistance():String {
        var owner:Object = {
            魔法抗性: {
                基础: 10
            }
        };

        // 创建空壳护盾
        var shield:AdaptiveShield = AdaptiveShield.createDormant("测试");
        shield.setOwner(owner);

        // 阶段1：空壳模式，立场应被删除
        var phase1:Boolean = (owner.魔法抗性["立场"] == undefined);

        // 阶段2：添加护盾升级到单盾模式
        shield.addShield(Shield.createTemporary(100, 50, 10, "临时盾"));
        var expectedBonus2:Number = ShieldUtil.calcResistanceBonus(50);
        var phase2:Boolean = (Math.abs(owner.魔法抗性["立场"] - (10 + expectedBonus2)) < 0.001);

        // 阶段3：添加更强护盾升级到栈模式
        // addShield() 会在 push 后立即同步立场抗性，无需额外触发
        shield.addShield(Shield.createTemporary(100, 100, 15, "高强度盾"));
        var expectedBonus3:Number = ShieldUtil.calcResistanceBonus(100);
        var phase3:Boolean = (Math.abs(owner.魔法抗性["立场"] - (10 + expectedBonus3)) < 0.001);

        // 阶段4：让所有护盾过期，降级回空壳
        // 临时盾1: duration=10, 临时盾2: duration=15
        // 需要足够帧数让两个盾都过期
        for (var i:Number = 0; i < 25; i++) {
            shield.update(1);
        }

        // 检查是否回到空壳模式并删除立场
        var phase4:Boolean = (shield.isDormantMode() && owner.魔法抗性["立场"] == undefined);

        var passed:Boolean = phase1 && phase2 && phase3 && phase4;

        return passed ? "✓ 模式切换立场抗性同步测试通过" :
            "✗ 模式切换立场抗性同步测试失败（phase1=" + phase1 +
            ", phase2=" + phase2 + ", phase3=" + phase3 + ", phase4=" + phase4 +
            ", isDormant=" + shield.isDormantMode() + ", 立场=" + owner.魔法抗性["立场"] + "）";
    }

    /**
     * 测试强度变化时立场抗性同步
     *
     * 【业务规则】
     * 栈模式下当表观强度变化时（如高强度盾过期），应更新立场抗性
     */
    private static function testStance_StrengthChangeSyncsResistance():String {
        var owner:Object = {
            魔法抗性: {
                基础: 10
            }
        };

        // 创建护盾并升级到栈模式
        var shield:AdaptiveShield = AdaptiveShield.createDormant("测试");
        shield.setOwner(owner);
        shield.addShield(Shield.createTemporary(100, 50, -1, "低强度盾"));
        shield.addShield(Shield.createTemporary(100, 100, 5, "高强度短期盾"));

        // 初始表观强度100
        var initialStrength:Number = shield.getStrength();
        var expectedBonus1:Number = ShieldUtil.calcResistanceBonus(100);
        var initialResist:Number = owner.魔法抗性["立场"];
        var phase1:Boolean = (
            initialStrength == 100 &&
            Math.abs(initialResist - (10 + expectedBonus1)) < 0.001
        );

        // 让高强度盾过期
        for (var i:Number = 0; i < 10; i++) {
            shield.update(1);
        }

        // 表观强度应降为50
        var finalStrength:Number = shield.getStrength();
        var expectedBonus2:Number = ShieldUtil.calcResistanceBonus(50);
        var finalResist:Number = owner.魔法抗性["立场"];
        var phase2:Boolean = (
            finalStrength == 50 &&
            Math.abs(finalResist - (10 + expectedBonus2)) < 0.001
        );

        var passed:Boolean = phase1 && phase2;

        return passed ? "✓ 强度变化立场抗性同步测试通过" :
            "✗ 强度变化立场抗性同步测试失败（phase1=" + phase1 +
            ", phase2=" + phase2 + ", 初始强度=" + initialStrength +
            ", 最终强度=" + finalStrength + "）";
    }

    /**
     * 测试 removeShield 后立场抗性同步
     *
     * 【业务规则】
     * 移除护盾后表观强度可能变化，应立即同步立场抗性
     *
     * 【测试严格性】
     * 断言立场抗性在 getStrength() 之前，避免 getStrength() 触发缓存刷新+同步
     * 这样可以严格证明"remove 后无需额外触发也会同步"
     */
    private static function testStance_RemoveShieldSyncsResistance():String {
        var owner:Object = {
            魔法抗性: {
                基础: 10
            }
        };

        // 创建护盾并升级到栈模式
        var shield:AdaptiveShield = AdaptiveShield.createDormant("测试");
        shield.setOwner(owner);
        var lowShield:Shield = Shield.createTemporary(100, 50, -1, "低强度盾");
        var highShield:Shield = Shield.createTemporary(100, 100, -1, "高强度盾");
        shield.addShield(lowShield);
        shield.addShield(highShield);

        // 初始表观强度100
        var initialStrength:Number = shield.getStrength();
        var expectedBonus1:Number = ShieldUtil.calcResistanceBonus(100);
        var phase1:Boolean = (
            initialStrength == 100 &&
            Math.abs(owner.魔法抗性["立场"] - (10 + expectedBonus1)) < 0.001
        );

        // 移除高强度盾，断言返回值
        var removeResult:Boolean = shield.removeShield(highShield);

        // 【严格验证】先断言立场抗性，再调用 getStrength()
        // 这样可证明 removeShield 本身会触发同步，而非 getStrength() 触发
        var expectedBonus2:Number = ShieldUtil.calcResistanceBonus(50);
        var resistBeforeGetStrength:Number = owner.魔法抗性["立场"];
        var resistCorrect:Boolean = (Math.abs(resistBeforeGetStrength - (10 + expectedBonus2)) < 0.001);

        // 再验证强度
        var finalStrength:Number = shield.getStrength();
        var phase2:Boolean = (
            removeResult == true &&
            resistCorrect &&
            finalStrength == 50
        );

        var passed:Boolean = phase1 && phase2;

        return passed ? "✓ removeShield立场抗性同步测试通过" :
            "✗ removeShield立场抗性同步测试失败（phase1=" + phase1 +
            ", phase2=" + phase2 + ", removeResult=" + removeResult +
            ", resistCorrect=" + resistCorrect + ", 最终强度=" + finalStrength +
            ", 立场=" + resistBeforeGetStrength + "）";
    }

    /**
     * 测试 removeShieldById 后立场抗性同步
     *
     * 【业务规则】
     * 通过ID移除护盾后表观强度可能变化，应立即同步立场抗性
     *
     * 【测试严格性】
     * 断言立场抗性在 getStrength() 之前，避免 getStrength() 触发缓存刷新+同步
     */
    private static function testStance_RemoveShieldByIdSyncsResistance():String {
        var owner:Object = {
            魔法抗性: {
                基础: 10
            }
        };

        // 创建护盾并升级到栈模式
        var shield:AdaptiveShield = AdaptiveShield.createDormant("测试");
        shield.setOwner(owner);
        var lowShield:Shield = Shield.createTemporary(100, 50, -1, "低强度盾");
        var highShield:Shield = Shield.createTemporary(100, 100, -1, "高强度盾");
        shield.addShield(lowShield);
        shield.addShield(highShield);

        // 记录高强度盾的ID
        var highShieldId:Number = highShield.getId();

        // 初始表观强度100
        var initialStrength:Number = shield.getStrength();
        var expectedBonus1:Number = ShieldUtil.calcResistanceBonus(100);
        var phase1:Boolean = (
            initialStrength == 100 &&
            Math.abs(owner.魔法抗性["立场"] - (10 + expectedBonus1)) < 0.001
        );

        // 通过ID移除高强度盾，断言返回值
        var removeResult:Boolean = shield.removeShieldById(highShieldId);

        // 【严格验证】先断言立场抗性，再调用 getStrength()
        var expectedBonus2:Number = ShieldUtil.calcResistanceBonus(50);
        var resistBeforeGetStrength:Number = owner.魔法抗性["立场"];
        var resistCorrect:Boolean = (Math.abs(resistBeforeGetStrength - (10 + expectedBonus2)) < 0.001);

        // 再验证强度
        var finalStrength:Number = shield.getStrength();
        var phase2:Boolean = (
            removeResult == true &&
            resistCorrect &&
            finalStrength == 50
        );

        var passed:Boolean = phase1 && phase2;

        return passed ? "✓ removeShieldById立场抗性同步测试通过" :
            "✗ removeShieldById立场抗性同步测试失败（phase1=" + phase1 +
            ", phase2=" + phase2 + ", removeResult=" + removeResult +
            ", resistCorrect=" + resistCorrect + ", 最终强度=" + finalStrength +
            ", 立场=" + resistBeforeGetStrength + "）";
    }

    /**
     * 测试 remove 清空栈到0层时切回空壳模式并删除立场
     *
     * 【业务规则】
     * 当 removeShield/removeShieldById 将栈清空到0层时：
     * 1. 应立即切回空壳模式（而非保持空栈模式）
     * 2. 应删除立场抗性（与空壳模式心智一致）
     *
     * 【设计约定】
     * 扁平化模式会抹除原始引用（性能优化代价），升级到栈模式时会新建
     * Shield 对象封装状态。即使原始引用丢失，也可通过 getShields()
     * 获取容器暴露的句柄完成移除操作。
     */
    private static function testStance_RemoveToZeroDowngradesToDormant():String {
        var owner:Object = {
            魔法抗性: {
                基础: 10
            }
        };

        // 创建护盾并升级到栈模式（默认扁平化，原始引用会丢失）
        var shield:AdaptiveShield = AdaptiveShield.createDormant("测试");
        shield.setOwner(owner);
        shield.addShield(Shield.createTemporary(100, 50, -1, "护盾1"));
        shield.addShield(Shield.createTemporary(100, 80, -1, "护盾2"));

        // 确认在栈模式且有立场抗性
        var isStack:Boolean = shield.isStackMode();
        var hasResist:Boolean = (owner.魔法抗性["立场"] != undefined);

        // 通过 getShields() 获取容器内实际对象（扁平化后的新对象）
        var innerShields:Array = shield.getShields();
        var innerShield1:IShield = innerShields[0];
        var innerShield2:IShield = innerShields[1];

        // 移除一个护盾（仍剩1个，保持栈模式）
        var result1:Boolean = shield.removeShield(innerShield2);
        var stillStack:Boolean = shield.isStackMode();

        // 移除最后一个护盾（清空到0层）
        var result2:Boolean = shield.removeShield(innerShield1);

        // 【关键验证】应切回空壳模式并删除立场
        var isDormant:Boolean = shield.isDormantMode();
        var resistDeleted:Boolean = (owner.魔法抗性["立场"] == undefined);
        var isActive:Boolean = shield.isActive();

        var passed:Boolean = (
            isStack && hasResist &&
            result1 && stillStack &&
            result2 && isDormant && resistDeleted && isActive
        );

        return passed ? "✓ remove清空到0层切回空壳模式测试通过" :
            "✗ remove清空到0层切回空壳模式测试失败（isStack=" + isStack +
            ", result1=" + result1 + ", stillStack=" + stillStack +
            ", result2=" + result2 + ", isDormant=" + isDormant +
            ", resistDeleted=" + resistDeleted + ", isActive=" + isActive + "）";
    }

    /**
     * 测试 clear 后立场抗性同步
     *
     * 【业务规则】
     * clear() 重置到空壳模式，应删除立场抗性
     */
    private static function testStance_ClearSyncsResistance():String {
        var owner:Object = {
            魔法抗性: {
                基础: 10
            }
        };

        // 创建护盾
        var shield:AdaptiveShield = new AdaptiveShield(100, 50, 0, 0, "测试", "default");
        shield.setOwner(owner);

        // 初始有立场抗性
        var expectedBonus:Number = ShieldUtil.calcResistanceBonus(50);
        var phase1:Boolean = (Math.abs(owner.魔法抗性["立场"] - (10 + expectedBonus)) < 0.001);

        // 清空护盾
        shield.clear();

        // 应回到空壳模式，立场抗性应被删除
        var phase2:Boolean = (shield.isDormantMode() && owner.魔法抗性["立场"] == undefined);

        var passed:Boolean = phase1 && phase2;

        return passed ? "✓ clear立场抗性同步测试通过" :
            "✗ clear立场抗性同步测试失败（phase1=" + phase1 +
            ", phase2=" + phase2 + ", isDormant=" + shield.isDormantMode() +
            ", 立场=" + owner.魔法抗性["立场"] + "）";
    }

    /**
     * 测试绑定 owner 时触发立场抗性同步
     *
     * 【业务规则】
     * setOwner 时应立即同步立场抗性
     */
    private static function testStance_OwnerBindingTriggersSync():String {
        var owner:Object = {
            魔法抗性: {
                基础: 20
            }
        };

        // 先创建护盾，后绑定 owner
        var shield:AdaptiveShield = new AdaptiveShield(100, 80, 0, 0, "测试", "default");

        // 绑定前立场应不存在
        var beforeBind:Boolean = (owner.魔法抗性["立场"] == undefined);

        // 绑定 owner
        shield.setOwner(owner);

        // 绑定后立场应存在
        var expectedBonus:Number = ShieldUtil.calcResistanceBonus(80);
        var afterBind:Boolean = (Math.abs(owner.魔法抗性["立场"] - (20 + expectedBonus)) < 0.001);

        var passed:Boolean = beforeBind && afterBind;

        return passed ? "✓ 绑定owner触发立场抗性同步测试通过" :
            "✗ 绑定owner触发立场抗性同步测试失败（beforeBind=" + beforeBind +
            ", afterBind=" + afterBind + "）";
    }

    /**
     * 测试无 owner 时安全无操作
     *
     * 【边界保护】
     * 未绑定 owner 时，立场抗性同步应安全跳过
     */
    private static function testStance_NoOwnerSafeNoop():String {
        // 创建护盾但不绑定 owner
        var shield:AdaptiveShield = new AdaptiveShield(100, 50, 0, 0, "测试", "default");

        // 各种操作不应抛出异常
        var noError:Boolean = true;
        try {
            shield.getStrength();
            shield.absorbDamage(10, false, 1);
            shield.update(1);
            shield.addShield(Shield.createTemporary(100, 80, -1, "附加盾"));
            shield.clear();
        } catch (e) {
            noError = false;
        }

        return noError ? "✓ 无owner安全无操作测试通过" : "✗ 无owner安全无操作测试失败";
    }

    /**
     * 测试无魔法抗性表时安全无操作
     *
     * 【边界保护】
     * owner.魔法抗性 不存在时，立场抗性同步应安全跳过
     */
    private static function testStance_NoResistTableSafeNoop():String {
        // 创建没有魔法抗性表的单位
        var owner:Object = {
            name: "测试单位"
        };

        var shield:AdaptiveShield = new AdaptiveShield(100, 50, 0, 0, "测试", "default");

        // 绑定 owner 不应抛出异常
        var noError:Boolean = true;
        try {
            shield.setOwner(owner);
            shield.absorbDamage(10, false, 1);
            shield.addShield(Shield.createTemporary(100, 80, -1, "附加盾"));
        } catch (e) {
            noError = false;
        }

        return noError ? "✓ 无魔法抗性表安全无操作测试通过" : "✗ 无魔法抗性表安全无操作测试失败";
    }

    /**
     * 测试 refreshStanceResistance 强制刷新
     *
     * 【业务规则】
     * 当外部代码重建魔法抗性表后，调用此方法强制重新计算立场抗性
     */
    private static function testStance_RefreshForceSync():String {
        var owner:Object = {
            魔法抗性: {
                基础: 10
            }
        };

        var shield:AdaptiveShield = new AdaptiveShield(100, 50, 0, 0, "测试", "default");
        shield.setOwner(owner);

        // 初始抗性
        var expectedBonus1:Number = ShieldUtil.calcResistanceBonus(50);
        var initialResist:Number = owner.魔法抗性["立场"];
        var phase1:Boolean = (Math.abs(initialResist - (10 + expectedBonus1)) < 0.001);

        // 模拟外部重建魔法抗性表（基础抗性变化）
        owner.魔法抗性 = {
            基础: 25
        };

        // 调用强制刷新
        shield.refreshStanceResistance();

        // 立场应使用新的基础抗性
        var expectedBonus2:Number = ShieldUtil.calcResistanceBonus(50);
        var refreshedResist:Number = owner.魔法抗性["立场"];
        var phase2:Boolean = (Math.abs(refreshedResist - (25 + expectedBonus2)) < 0.001);

        var passed:Boolean = phase1 && phase2;

        return passed ? "✓ refreshStanceResistance强制刷新测试通过" :
            "✗ refreshStanceResistance强制刷新测试失败（phase1=" + phase1 +
            ", phase2=" + phase2 + ", 刷新后=" + refreshedResist + "）";
    }

    /**
     * 测试缓存机制避免重复写入
     *
     * 【性能优化】
     * 当模式、强度、基础抗性均未变化时，不应重复写入立场抗性
     * 这里通过检查内部缓存字段来验证
     */
    private static function testStance_CachePreventsRedundantWrite():String {
        var owner:Object = {
            魔法抗性: {
                基础: 10
            }
        };

        var shield:AdaptiveShield = new AdaptiveShield(100, 50, 0, 0, "测试", "default");
        shield.setOwner(owner);

        // 记录初始立场值
        var initialResist:Number = owner.魔法抗性["立场"];

        // 多次调用 refreshStanceResistance（值未变化）
        shield.refreshStanceResistance();
        shield.refreshStanceResistance();
        shield.refreshStanceResistance();

        // 值应保持不变
        var finalResist:Number = owner.魔法抗性["立场"];
        var passed:Boolean = (Math.abs(initialResist - finalResist) < 0.001);

        return passed ? "✓ 缓存避免重复写入测试通过" :
            "✗ 缓存避免重复写入测试失败（初始=" + initialResist + ", 最终=" + finalResist + "）";
    }

    // ==================== 14. 单盾模式ID稳定性测试 ====================

    private static function testSingleModeIdStability():String {
        var results:Array = [];

        // 基础 removeShieldById/getShieldById 测试
        results.push(testSingleFlat_RemoveShieldById());
        results.push(testSingleDelegate_RemoveShieldById());
        results.push(testSingleFlat_GetShieldById());
        results.push(testCrossMode_IdStability());

        // 边界情况：状态同步和回写顺序
        results.push(testSingleFlat_GetShieldById_StateSync());
        results.push(testSingleFlat_GetShieldById_MetadataSync());
        results.push(testUpgrade_MaxCapacityOrder());

        return formatResults(results, "单盾模式ID稳定性");
    }

    /**
     * 测试扁平化模式下 removeShieldById 能正确按内部护盾ID移除
     */
    private static function testSingleFlat_RemoveShieldById():String {
        var container:AdaptiveShield = AdaptiveShield.createDormant("测试容器");
        var inner:Shield = Shield.createTemporary(100, 50, -1, "内部盾");
        var innerId:Number = inner.getId();

        container.addShield(inner, false);  // 扁平化模式

        // 确认进入扁平化单盾模式
        if (!container.isSingleMode() || !container.isFlattenedMode()) {
            return "✗ 扁平化removeShieldById测试失败（未进入扁平化模式）";
        }

        // 错误ID应该返回false
        var wrongRemove:Boolean = container.removeShieldById(innerId + 999);

        // 正确ID应该返回true
        var rightRemove:Boolean = container.removeShieldById(innerId);

        // 移除后应该是空壳模式
        var isDormant:Boolean = container.isDormantMode();

        var passed:Boolean = (!wrongRemove && rightRemove && isDormant);
        return passed ? "✓ 扁平化removeShieldById测试通过" :
            "✗ 扁平化removeShieldById测试失败（wrongRemove=" + wrongRemove +
            ", rightRemove=" + rightRemove + ", isDormant=" + isDormant + "）";
    }

    /**
     * 测试委托模式下 removeShieldById 能正确工作
     */
    private static function testSingleDelegate_RemoveShieldById():String {
        var container:AdaptiveShield = AdaptiveShield.createDormant("测试容器");
        var inner:Shield = Shield.createTemporary(100, 50, -1, "内部盾");

        // 添加回调强制进入委托模式
        inner.onBreakCallback = function(s:IShield):Void {};
        var innerId:Number = inner.getId();

        container.addShield(inner, true);  // 委托模式

        // 确认进入委托单盾模式
        if (!container.isSingleMode() || !container.isDelegateMode()) {
            return "✗ 委托模式removeShieldById测试失败（未进入委托模式）";
        }

        // 正确ID应该返回true
        var rightRemove:Boolean = container.removeShieldById(innerId);

        // 移除后应该是空壳模式
        var isDormant:Boolean = container.isDormantMode();

        var passed:Boolean = (rightRemove && isDormant);
        return passed ? "✓ 委托模式removeShieldById测试通过" :
            "✗ 委托模式removeShieldById测试失败（rightRemove=" + rightRemove +
            ", isDormant=" + isDormant + "）";
    }

    /**
     * 测试扁平化模式下 getShieldById 能正确匹配内部护盾ID
     */
    private static function testSingleFlat_GetShieldById():String {
        var container:AdaptiveShield = AdaptiveShield.createDormant("测试容器");
        var inner:Shield = Shield.createTemporary(100, 50, -1, "内部盾");
        var innerId:Number = inner.getId();

        container.addShield(inner, false);  // 扁平化

        // 应该能通过内部护盾ID找到
        var found:IShield = container.getShieldById(innerId);
        var notFound:IShield = container.getShieldById(innerId + 999);

        var passed:Boolean = (found != null && notFound == null);
        return passed ? "✓ 扁平化getShieldById测试通过" :
            "✗ 扁平化getShieldById测试失败（found=" + (found != null) +
            ", notFound=" + (notFound != null) + "）";
    }

    /**
     * 关键回归测试：扁平化单盾 + 再add第二层触发升级到栈后，
     * 用"第一层原始ID"仍能 removeShieldById 命中（验证"升级不换ID"）
     */
    private static function testCrossMode_IdStability():String {
        var container:AdaptiveShield = AdaptiveShield.createDormant("测试容器");

        // 第一层护盾
        var first:Shield = Shield.createTemporary(100, 50, -1, "第一层");
        var firstId:Number = first.getId();

        container.addShield(first, false);  // 扁平化

        // 确认是单盾模式
        if (!container.isSingleMode()) {
            return "✗ 跨模式ID稳定性测试失败（添加第一层后未进入单盾模式）";
        }

        // 添加第二层，触发升级到栈模式
        var second:Shield = Shield.createTemporary(80, 40, -1, "第二层");
        var secondId:Number = second.getId();
        container.addShield(second, false);

        // 确认是栈模式
        if (!container.isStackMode()) {
            return "✗ 跨模式ID稳定性测试失败（添加第二层后未进入栈模式）";
        }

        // 验证第一层的ID在栈模式下仍然有效
        var foundFirst:IShield = container.getShieldById(firstId);
        if (foundFirst == null) {
            return "✗ 跨模式ID稳定性测试失败（升级到栈后无法通过原ID找到第一层）";
        }

        // 用原始ID移除第一层
        var removeFirst:Boolean = container.removeShieldById(firstId);
        if (!removeFirst) {
            return "✗ 跨模式ID稳定性测试失败（无法用原ID移除第一层）";
        }

        // 现在应该只剩第二层
        var count:Number = container.getShieldCount();
        if (count != 1) {
            return "✗ 跨模式ID稳定性测试失败（移除后层数错误: " + count + "）";
        }

        // 第二层仍然可以找到
        var foundSecond:IShield = container.getShieldById(secondId);
        var passed:Boolean = (foundSecond != null);

        return passed ? "✓ 跨模式ID稳定性测试通过" :
            "✗ 跨模式ID稳定性测试失败（第二层丢失）";
    }

    /**
     * 测试扁平化模式下 getShieldById 返回的护盾状态是最新的
     * 验证 _syncStateToInnerShield 正确工作
     */
    private static function testSingleFlat_GetShieldById_StateSync():String {
        var container:AdaptiveShield = AdaptiveShield.createDormant("测试容器");
        var inner:Shield = Shield.createTemporary(100, 50, -1, "内部盾");
        var innerId:Number = inner.getId();

        container.addShield(inner, false);  // 扁平化

        // 扁平化后修改容器的容量（模拟受击消耗）
        container.absorbDamage(30, false, 1);  // 消耗30点

        // 通过 getShieldById 获取内部护盾
        var retrieved:IShield = container.getShieldById(innerId);
        if (retrieved == null) {
            return "✗ 扁平化getShieldById状态同步测试失败（未找到护盾）";
        }

        // 验证获取到的护盾容量是同步后的值（应该是70，而非原始的100）
        var retrievedCapacity:Number = retrieved.getCapacity();
        var containerCapacity:Number = container.getCapacity();

        var passed:Boolean = (Math.abs(retrievedCapacity - containerCapacity) < 0.001);
        return passed ? "✓ 扁平化getShieldById状态同步测试通过" :
            "✗ 扁平化getShieldById状态同步测试失败（retrieved=" + retrievedCapacity +
            ", container=" + containerCapacity + "）";
    }

    /**
     * 测试升级到栈模式时 maxCapacity 上调且 capacity 超过旧 max 不会被截断
     *
     * 【触发条件】
     * 1. 创建初始 maxCapacity=100 的护盾，扁平化
     * 2. 扁平化后通过容器上调 maxCapacity 到 200
     * 3. 设置 capacity=150（超过原 max=100）
     * 4. 触发升级到栈模式
     * 5. 验证升级后容量仍为 150（不被旧 max 截断）
     *
     * 【修复验证】
     * 修改前：回写顺序是 setCapacity(150) -> setMaxCapacity(200)
     *        此时 inner.maxCapacity 仍是 100，capacity 会被截断为 100
     * 修改后：回写顺序是 setMaxCapacity(200) -> setCapacity(150)
     *        先扩大 max，再设置 capacity，不会截断
     */
    private static function testUpgrade_MaxCapacityOrder():String {
        var container:AdaptiveShield = AdaptiveShield.createDormant("测试容器");

        // 创建一个初始 maxCapacity=100 的护盾
        var inner:Shield = new Shield(100, 50, 0, 0, "测试盾", "default");
        inner.setCapacity(100);  // 满容量
        var innerId:Number = inner.getId();

        container.addShield(inner, false);  // 扁平化

        // 【关键】扁平化后上调 maxCapacity 并设置 capacity 超过原 max
        // 此时 inner 对象的 maxCapacity 仍是 100（身份句柄未同步）
        // 但容器的 _maxCapacity 已是 200，_capacity 已是 150
        container.setMaxCapacity(200);
        container.setCapacity(150);  // 超过原 max=100

        var beforeUpgradeCapacity:Number = container.getCapacity();  // 应该是 150

        // 添加第二层触发升级
        var second:Shield = Shield.createTemporary(50, 30, -1, "第二层");
        container.addShield(second, false);

        // 升级后检查第一层的容量是否保持
        var foundFirst:IShield = container.getShieldById(innerId);
        if (foundFirst == null) {
            return "✗ 升级maxCapacity顺序测试失败（找不到第一层）";
        }

        var afterUpgradeCapacity:Number = foundFirst.getCapacity();

        // 容量应该保持 150（不被截断为 100）
        var passed:Boolean = (Math.abs(beforeUpgradeCapacity - afterUpgradeCapacity) < 0.001);
        return passed ? "✓ 升级maxCapacity顺序测试通过" :
            "✗ 升级maxCapacity顺序测试失败（升级前=" + beforeUpgradeCapacity +
            ", 升级后=" + afterUpgradeCapacity + "，若为100则是被旧max截断）";
    }

    /**
     * 测试 getShieldById 返回的护盾元数据（name/type/owner）是最新的
     */
    private static function testSingleFlat_GetShieldById_MetadataSync():String {
        var container:AdaptiveShield = AdaptiveShield.createDormant("测试容器");
        var inner:Shield = new Shield(100, 50, 0, 0, "原始名称", "原始类型");
        var innerId:Number = inner.getId();

        // 模拟 owner
        var mockOwner:Object = {name: "测试单位"};
        inner.setOwner(mockOwner);

        container.addShield(inner, false);  // 扁平化

        // 扁平化后修改容器的元数据
        container.setName("新名称");
        container.setType("新类型");
        var newOwner:Object = {name: "新单位"};
        container.setOwner(newOwner);

        // 通过 getShieldById 获取内部护盾
        var retrieved:IShield = container.getShieldById(innerId);
        if (retrieved == null) {
            return "✗ 扁平化getShieldById元数据同步测试失败（未找到护盾）";
        }

        // 验证元数据是同步后的值
        var retrievedName:String = "";
        var retrievedType:String = "";
        var retrievedOwner:Object = null;

        if (retrieved instanceof Shield) {
            var s:Shield = Shield(retrieved);
            retrievedName = s.getName();
            retrievedType = s.getType();
        }
        if (retrieved instanceof BaseShield) {
            retrievedOwner = BaseShield(retrieved).getOwner();
        }

        var nameMatch:Boolean = (retrievedName == "新名称");
        var typeMatch:Boolean = (retrievedType == "新类型");
        var ownerMatch:Boolean = (retrievedOwner === newOwner);

        var passed:Boolean = nameMatch && typeMatch && ownerMatch;
        return passed ? "✓ 扁平化getShieldById元数据同步测试通过" :
            "✗ 扁平化getShieldById元数据同步测试失败（name=" + retrievedName +
            ", type=" + retrievedType + ", ownerMatch=" + ownerMatch + "）";
    }

    // ==================== 15. 回调重入修改结构测试 ====================

    /**
     * 测试在回调中修改护盾栈结构的安全性
     *
     * 【契约说明】
     * 1. 容器侧回调（onHit/onBreak/onExpire/onRechargeStart/onRechargeFull/onShieldEjected/onAllShieldsDepleted）可安全修改结构
     * 2. 子盾回调中若修改容器结构，应保证“本次循环结束后生效”（避免在热路径中破坏迭代）
     */
    private static function testCallbackReentry():String {
        var results:Array = [];

        results.push(testReentry_OnEjectedAddShield());
        results.push(testReentry_OnEjectedRemoveOther());
        results.push(testReentry_OnEjectedClear());
        results.push(testReentry_OnAllDepletedAddShield());
        results.push(testReentry_StackModeEjectedChain());
        results.push(testReentry_CacheConsistencyInEjected());
        results.push(testReentry_OnHitAddShield());
        results.push(testReentry_OnHitRemoveShield());
        results.push(testReentry_OnHitClear());
        results.push(testReentry_OnBreakRemoveById());
        results.push(testReentry_SubCallbackNotification());
        results.push(testReentry_SubOnHitAddShield());
        results.push(testReentry_SubOnHitRemoveShield());
        results.push(testReentry_SubOnHitClear());
        results.push(testReentry_SubOnBreakRemoveById());

        return formatResults(results, "回调重入修改结构");
    }

    /**
     * 测试 onShieldEjected 回调中添加新护盾
     *
     * 【场景】
     * 护盾从栈中弹出时添加替代护盾（游戏中常见的"护盾自动补充"机制）
     */
    private static function testReentry_OnEjectedAddShield():String {
        var shield:AdaptiveShield = AdaptiveShield.createDormant("测试");
        var ejectedCount:Number = 0;

        // 设置弹出回调：弹出时添加替代盾
        shield.onShieldEjectedCallback = function(ejected:IShield, container:AdaptiveShield):Void {
            ejectedCount++;
            if (ejectedCount == 1) {
                // 第一次弹出时添加替代盾
                container.addShield(Shield.createRechargeable(100, 50, 5, 30, "替代盾"));
            }
        };

        // 添加临时盾
        shield.addShield(Shield.createTemporary(50, 100, 5, "临时盾"));

        // 更新让临时盾过期
        for (var i:Number = 0; i < 10; i++) {
            shield.update(1);
        }

        // 验证：弹出1次，替代盾已添加
        var hasReplacementShield:Boolean = (shield.getCapacity() == 100);
        var passed:Boolean = (ejectedCount == 1 && hasReplacementShield);

        return passed ? "✓ onEjected中addShield测试通过" :
            "✗ onEjected中addShield测试失败（ejected=" + ejectedCount + ", cap=" + shield.getCapacity() + "）";
    }

    /**
     * 测试 onShieldEjected 回调中移除其他护盾
     *
     * 【场景】
     * "连锁移除"机制：一个护盾弹出时移除另一个护盾
     */
    private static function testReentry_OnEjectedRemoveOther():String {
        var shield:AdaptiveShield = AdaptiveShield.createDormant("测试");
        var removedInCallback:Boolean = false;
        var persistentShield:Shield = Shield.createRechargeable(100, 50, 5, 30, "持久盾");

        // 弹出回调：移除持久盾
        shield.onShieldEjectedCallback = function(ejected:IShield, container:AdaptiveShield):Void {
            removedInCallback = container.removeShield(persistentShield);
        };

        // 添加两个护盾
        shield.addShield(Shield.createTemporary(50, 100, 3, "临时盾")); // 会过期
        shield.addShield(persistentShield); // 持久盾

        // 更新让临时盾过期
        for (var i:Number = 0; i < 10; i++) {
            shield.update(1);
        }

        // 验证：弹出临时盾时连带移除了持久盾
        var isEmpty:Boolean = shield.isEmpty();
        var passed:Boolean = (removedInCallback && isEmpty);

        return passed ? "✓ onEjected中removeShield测试通过" :
            "✗ onEjected中removeShield测试失败（removed=" + removedInCallback + ", isEmpty=" + isEmpty + "）";
    }

    /**
     * 测试 onShieldEjected 回调中调用 clear
     *
     * 【场景】
     * 护盾弹出时清空所有护盾（"护盾系统重置"机制）
     */
    private static function testReentry_OnEjectedClear():String {
        var shield:AdaptiveShield = AdaptiveShield.createDormant("测试");
        var clearedInCallback:Boolean = false;

        // 弹出回调：清空所有护盾
        shield.onShieldEjectedCallback = function(ejected:IShield, container:AdaptiveShield):Void {
            container.clear();
            clearedInCallback = true;
        };

        // 添加多个护盾
        shield.addShield(Shield.createTemporary(50, 100, 3, "临时盾"));
        shield.addShield(Shield.createRechargeable(100, 80, 5, 30, "持久盾1"));
        shield.addShield(Shield.createRechargeable(100, 60, 5, 30, "持久盾2"));

        // 更新让临时盾过期
        for (var i:Number = 0; i < 10; i++) {
            shield.update(1);
        }

        // 验证清空
        var isDormant:Boolean = shield.isDormantMode();
        var passed:Boolean = (clearedInCallback && isDormant);

        return passed ? "✓ onEjected中clear测试通过" :
            "✗ onEjected中clear测试失败（cleared=" + clearedInCallback + ", isDormant=" + isDormant + "）";
    }

    /**
     * 测试 onAllShieldsDepleted 回调中添加新护盾
     *
     * 【场景】
     * 所有护盾耗尽后自动补充（"护盾自动恢复"机制）
     */
    private static function testReentry_OnAllDepletedAddShield():String {
        var shield:AdaptiveShield = AdaptiveShield.createDormant("测试");
        var depletedCalled:Boolean = false;

        // 耗尽回调：添加新护盾
        shield.onAllShieldsDepletedCallback = function(container:AdaptiveShield):Void {
            depletedCalled = true;
            container.addShield(Shield.createRechargeable(200, 80, 5, 30, "恢复盾"));
        };

        // 添加临时盾
        shield.addShield(Shield.createTemporary(50, 100, 3, "临时盾"));

        // 更新让临时盾过期
        for (var i:Number = 0; i < 10; i++) {
            shield.update(1);
        }

        // 验证：耗尽后自动补充了新盾
        var hasNewShield:Boolean = (shield.getCapacity() == 200);
        var passed:Boolean = (depletedCalled && hasNewShield);

        return passed ? "✓ onAllDepleted中addShield测试通过" :
            "✗ onAllDepleted中addShield测试失败（depleted=" + depletedCalled + ", cap=" + shield.getCapacity() + "）";
    }

    /**
     * 测试栈模式下连续弹出时的回调链
     *
     * 【场景】
     * 多个护盾连续过期，每次弹出都添加新盾
     */
    private static function testReentry_StackModeEjectedChain():String {
        var shield:AdaptiveShield = AdaptiveShield.createDormant("测试");
        var ejectedNames:Array = [];

        // 弹出回调：记录弹出顺序，并在前两次弹出时添加新盾
        shield.onShieldEjectedCallback = function(ejected:IShield, container:AdaptiveShield):Void {
            if (ejected instanceof Shield) {
                ejectedNames.push(Shield(ejected).getName());
            }
            if (ejectedNames.length < 3) {
                container.addShield(Shield.createTemporary(50, 30, 2, "补充盾" + ejectedNames.length));
            }
        };

        // 添加两个短期临时盾
        shield.addShield(Shield.createTemporary(50, 100, 2, "初始盾1"));
        shield.addShield(Shield.createTemporary(50, 80, 3, "初始盾2"));

        // 更新足够帧数让所有盾过期
        for (var i:Number = 0; i < 20; i++) {
            shield.update(1);
        }

        // 验证：应该弹出多次，最终耗尽
        var passed:Boolean = (ejectedNames.length >= 2 && shield.isDormantMode());

        return passed ? "✓ 栈模式连续弹出链测试通过（弹出: " + ejectedNames.join("→") + "）" :
            "✗ 栈模式连续弹出链测试失败（弹出: " + ejectedNames.join("→") + ", isDormant=" + shield.isDormantMode() + "）";
    }

    /**
     * 测试容器侧回调中修改结构后缓存一致性
     *
     * 【场景】
     * 在 onShieldEjected 回调中修改护盾栈后，立即查询容量/强度等属性
     */
    private static function testReentry_CacheConsistencyInEjected():String {
        var shield:AdaptiveShield = AdaptiveShield.createDormant("测试");
        var capacityInCallback:Number = -1;
        var strengthInCallback:Number = -1;

        // 弹出回调：添加新盾后立即查询
        shield.onShieldEjectedCallback = function(ejected:IShield, container:AdaptiveShield):Void {
            container.addShield(Shield.createTemporary(200, 80, -1, "新盾"));
            capacityInCallback = container.getCapacity();
            strengthInCallback = container.getStrength();
        };

        // 添加临时盾
        shield.addShield(Shield.createTemporary(50, 100, 3, "临时盾"));

        // 更新让临时盾过期
        for (var i:Number = 0; i < 10; i++) {
            shield.update(1);
        }

        // 验证回调中查到的值是正确的
        var passed:Boolean = (capacityInCallback == 200 && strengthInCallback == 80);

        return passed ? "✓ 回调中缓存一致性测试通过" :
            "✗ 回调中缓存一致性测试失败（cap=" + capacityInCallback + ", str=" + strengthInCallback + "）";
    }

    /**
     * 测试容器级 onHitCallback 中修改结构：addShield
     *
     * 【场景】
     * Roguelike 常见的“受击补盾 / 触发型护盾生成”机制。
     */
    private static function testReentry_OnHitAddShield():String {
        var container:AdaptiveShield = AdaptiveShield.createDormant("测试");
        var shield1:Shield = Shield.createTemporary(100, 80, -1, "盾1");
        var shield2:Shield = Shield.createTemporary(100, 60, -1, "盾2");

        container.addShield(shield1);
        container.addShield(shield2);

        var hitCalled:Boolean = false;
        var added:Boolean = false;

        container.onHitCallback = function(s:IShield, absorbed:Number):Void {
            hitCalled = true;
            added = container.addShield(Shield.createTemporary(10, 999, -1, "补盾"));
        };

        var noError:Boolean = true;
        var penetrating:Number = -1;
        try {
            penetrating = container.absorbDamage(30, false, 1);
        } catch (e) {
            noError = false;
        }

        // 伤害应由原有高强度盾承担（不应因回调改结构导致分摊循环异常）
        var distributionOk:Boolean = (penetrating == 0 && shield1.getCapacity() == 70 && shield2.getCapacity() == 100);
        var passed:Boolean = (noError && hitCalled && added && container.getShieldCount() == 3 && distributionOk);

        return passed ? "✓ onHit中addShield测试通过" :
            "✗ onHit中addShield测试失败（noError=" + noError +
            ", hitCalled=" + hitCalled + ", added=" + added +
            ", count=" + container.getShieldCount() + ", distOk=" + distributionOk + "）";
    }

    /**
     * 测试容器级 onHitCallback 中修改结构：removeShield
     */
    private static function testReentry_OnHitRemoveShield():String {
        var container:AdaptiveShield = AdaptiveShield.createDormant("测试");
        var shield1:Shield = Shield.createTemporary(100, 80, -1, "盾1");
        var shield2:Shield = Shield.createTemporary(100, 60, -1, "盾2");

        container.addShield(shield1);
        container.addShield(shield2);

        var removed:Boolean = false;
        container.onHitCallback = function(s:IShield, absorbed:Number):Void {
            removed = container.removeShield(shield2);
        };

        var noError:Boolean = true;
        try {
            container.absorbDamage(10, false, 1);
        } catch (e) {
            noError = false;
        }

        var passed:Boolean = (noError && removed && container.getShieldCount() == 1);
        return passed ? "✓ onHit中removeShield测试通过" :
            "✗ onHit中removeShield测试失败（noError=" + noError +
            ", removed=" + removed + ", count=" + container.getShieldCount() + "）";
    }

    /**
     * 测试容器级 onHitCallback 中修改结构：clear
     */
    private static function testReentry_OnHitClear():String {
        var container:AdaptiveShield = AdaptiveShield.createDormant("测试");
        container.addShield(Shield.createTemporary(100, 80, -1, "盾1"));
        container.addShield(Shield.createTemporary(100, 60, -1, "盾2"));

        container.onHitCallback = function(s:IShield, absorbed:Number):Void {
            container.clear();
        };

        var noError:Boolean = true;
        try {
            container.absorbDamage(10, false, 1);
        } catch (e) {
            noError = false;
        }

        var passed:Boolean = (noError && container.isDormantMode() && container.getShieldCount() == 0);
        return passed ? "✓ onHit中clear测试通过" :
            "✗ onHit中clear测试失败（noError=" + noError +
            ", dormant=" + container.isDormantMode() + ", count=" + container.getShieldCount() + "）";
    }

    /**
     * 测试容器级 onBreakCallback 中修改结构：removeShieldById
     */
    private static function testReentry_OnBreakRemoveById():String {
        var container:AdaptiveShield = AdaptiveShield.createDormant("测试");
        var shield1:Shield = Shield.createTemporary(50, 100, -1, "盾1");
        var shield2:Shield = Shield.createTemporary(50, 80, -1, "盾2");

        container.addShield(shield1);
        container.addShield(shield2);

        var removed:Boolean = false;
        container.onBreakCallback = function(s:IShield):Void {
            removed = container.removeShieldById(shield2.getId());
        };

        var noError:Boolean = true;
        try {
            container.consumeCapacity(9999); // 直接消耗到总容量归零，触发 onBreak
        } catch (e) {
            noError = false;
        }

        var passed:Boolean = (noError && removed && container.getShieldCount() == 1);
        return passed ? "✓ onBreak中removeShieldById测试通过" :
            "✗ onBreak中removeShieldById测试失败（noError=" + noError +
            ", removed=" + removed + ", count=" + container.getShieldCount() + "）";
    }

    /**
     * 测试子盾回调作为通知机制（不修改结构）
     *
     * 【契约】
     * 子盾的 onBreak/onExpire 回调用于通知，不应直接修改容器结构
     * 本测试验证子盾回调正常触发且不影响容器状态
     */
    private static function testReentry_SubCallbackNotification():String {
        var shield:AdaptiveShield = AdaptiveShield.createDormant("测试");
        var breakNotified:Boolean = false;
        var expireNotified:Boolean = false;

        // 子盾回调仅作通知用
        var tempShield:Shield = Shield.createTemporary(50, 100, 5, "临时盾");
        tempShield.onBreakCallback = function(s:IShield):Void {
            breakNotified = true;
            // 注意：不在这里修改容器结构
        };
        tempShield.onExpireCallback = function(s:IShield):Void {
            expireNotified = true;
            // 注意：不在这里修改容器结构
        };

        shield.addShield(tempShield, true); // 委托模式以保留回调

        // 打碎护盾
        shield.absorbDamage(100, false, 1);

        // 如果没打碎则让其过期
        if (!breakNotified) {
            for (var i:Number = 0; i < 10; i++) {
                shield.update(1);
            }
        }

        // 验证：至少一个通知被触发，且容器进入空壳模式
        var passed:Boolean = ((breakNotified || expireNotified) && shield.isDormantMode());

        return passed ? "✓ 子盾回调通知测试通过（break=" + breakNotified + ", expire=" + expireNotified + "）" :
            "✗ 子盾回调通知测试失败（break=" + breakNotified + ", expire=" + expireNotified + "）";
    }

    /**
     * P0：子盾 onHitCallback 中修改容器结构：addShield
     *
     * 【预期】
     * - 不应抛异常/越界/跳层
     * - 结构修改应在本次分摊循环结束后生效（回调内计数仍为旧值）
     */
    private static function testReentry_SubOnHitAddShield():String {
        var container:AdaptiveShield = AdaptiveShield.createDormant("测试");

        var shield1:Shield = Shield.createRechargeable(100, 80, 0, 0, "盾1");
        var shield2:Shield = Shield.createRechargeable(100, 60, 0, 0, "盾2");

        var spawned:Shield = null;
        var addOk:Boolean = false;
        var countInCallback:Number = -1;

        shield1.onHitCallback = function(s:IShield, absorbed:Number):Void {
            spawned = Shield.createTemporary(10, 999, -1, "补盾");
            addOk = container.addShield(spawned);
            countInCallback = container.getShieldCount(); // 结构锁期间应保持旧值（2）
        };

        container.addShield(shield1); // 自动走委托以保留回调
        container.addShield(shield2); // 升级到栈模式

        var noError:Boolean = true;
        var penetrating:Number = -1;
        try {
            penetrating = container.absorbDamage(10, false, 1);
        } catch (e) {
            noError = false;
        }

        var distributionOk:Boolean = (penetrating == 0 && shield1.getCapacity() == 90 && shield2.getCapacity() == 100);
        var deferredOk:Boolean = (countInCallback == 2 && container.getShieldCount() == 3 && spawned != null && spawned.getCapacity() == 10);
        var passed:Boolean = (noError && addOk && distributionOk && deferredOk);

        return passed ? "✓ 子盾onHit中addShield重入测试通过" :
            "✗ 子盾onHit中addShield重入测试失败（noError=" + noError +
            ", addOk=" + addOk + ", inCbCount=" + countInCallback +
            ", finalCount=" + container.getShieldCount() + ", distOk=" + distributionOk + "）";
    }

    /**
     * P0：子盾 onHitCallback 中修改容器结构：removeShield
     */
    private static function testReentry_SubOnHitRemoveShield():String {
        var container:AdaptiveShield = AdaptiveShield.createDormant("测试");

        var shield1:Shield = Shield.createRechargeable(100, 80, 0, 0, "盾1");
        var shield2:Shield = Shield.createRechargeable(100, 60, 0, 0, "盾2");

        var removeOk:Boolean = false;
        var countInCallback:Number = -1;

        shield1.onHitCallback = function(s:IShield, absorbed:Number):Void {
            removeOk = container.removeShield(shield2);
            countInCallback = container.getShieldCount(); // 结构锁期间应保持旧值（2）
        };

        container.addShield(shield1);
        container.addShield(shield2);

        var noError:Boolean = true;
        try {
            container.absorbDamage(10, false, 1);
        } catch (e) {
            noError = false;
        }

        var passed:Boolean = (noError && removeOk && countInCallback == 2 && container.getShieldCount() == 1);
        return passed ? "✓ 子盾onHit中removeShield重入测试通过" :
            "✗ 子盾onHit中removeShield重入测试失败（noError=" + noError +
            ", removeOk=" + removeOk + ", inCbCount=" + countInCallback +
            ", finalCount=" + container.getShieldCount() + "）";
    }

    /**
     * P0：子盾 onHitCallback 中修改容器结构：clear
     */
    private static function testReentry_SubOnHitClear():String {
        var container:AdaptiveShield = AdaptiveShield.createDormant("测试");

        var shield1:Shield = Shield.createRechargeable(100, 80, 0, 0, "盾1");
        var shield2:Shield = Shield.createRechargeable(100, 60, 0, 0, "盾2");

        var countInCallback:Number = -1;
        shield1.onHitCallback = function(s:IShield, absorbed:Number):Void {
            container.clear();
            countInCallback = container.getShieldCount(); // 结构锁期间应保持旧值（2）
        };

        container.addShield(shield1);
        container.addShield(shield2);

        var noError:Boolean = true;
        try {
            container.absorbDamage(10, false, 1);
        } catch (e) {
            noError = false;
        }

        var passed:Boolean = (noError && countInCallback == 2 && container.isDormantMode() && container.getShieldCount() == 0);
        return passed ? "✓ 子盾onHit中clear重入测试通过" :
            "✗ 子盾onHit中clear重入测试失败（noError=" + noError +
            ", inCbCount=" + countInCallback + ", dormant=" + container.isDormantMode() +
            ", finalCount=" + container.getShieldCount() + "）";
    }

    /**
     * P0：子盾 onBreakCallback 中修改容器结构：removeShieldById
     */
    private static function testReentry_SubOnBreakRemoveById():String {
        var container:AdaptiveShield = AdaptiveShield.createDormant("测试");

        var shield1:Shield = Shield.createRechargeable(10, 80, 0, 0, "盾1");
        var shield2:Shield = Shield.createRechargeable(100, 60, 0, 0, "盾2");

        var removeOk:Boolean = false;
        var countInCallback:Number = -1;
        shield1.onBreakCallback = function(s:IShield):Void {
            removeOk = container.removeShieldById(shield2.getId());
            countInCallback = container.getShieldCount(); // 结构锁期间应保持旧值（2）
        };

        container.addShield(shield1);
        container.addShield(shield2);

        var noError:Boolean = true;
        try {
            container.absorbDamage(10, false, 1); // 打到盾1归零，触发子盾 onBreak
        } catch (e) {
            noError = false;
        }

        var passed:Boolean = (noError && removeOk && countInCallback == 2 && container.getShieldCount() == 1);
        return passed ? "✓ 子盾onBreak中removeShieldById重入测试通过" :
            "✗ 子盾onBreak中removeShieldById重入测试失败（noError=" + noError +
            ", removeOk=" + removeOk + ", inCbCount=" + countInCallback +
            ", finalCount=" + container.getShieldCount() + "）";
    }

    // ==================== 16. 跨模式回调一致性契约测试 ====================

    /**
     * 测试不同模式下回调行为的一致性
     *
     * 【契约定义】
     * 1. 容器级 onHitCallback：在任何模式下，容器受击都应触发
     * 2. 容器级 onBreakCallback：护盾耗尽（容量→0）时触发
     * 3. 容器级 onRechargeStart/onRechargeFull/onExpire：模式切换后应保持可用（含扁平化→栈）
     * 4. 内部护盾回调：仅在委托模式下保留（栈模式下由子盾自行管理）
     * 5. 回调参数 shield 应该是容器（而非内部护盾）
     */
    private static function testCallbackConsistency():String {
        var results:Array = [];

        results.push(testConsistency_OnHitAllModes());
        results.push(testConsistency_OnBreakAllModes());
        results.push(testConsistency_CallbackShieldParameter());
        results.push(testConsistency_InnerCallbackIsolation());
        results.push(testConsistency_StackModeInnerCallbacks());
        results.push(testConsistency_ShieldSubclassNotFlattened());
        results.push(testConsistency_UpgradeToStack_RechargeCallbacks());
        results.push(testConsistency_UpgradeToStack_ExpireCallback());

        return formatResults(results, "跨模式回调一致性契约");
    }

    /**
     * 测试 onHitCallback 在所有模式下都触发
     */
    private static function testConsistency_OnHitAllModes():String {
        var hitCounts:Object = {dormant: 0, flattened: 0, delegate: 0, stack: 0};

        // 空壳模式
        var dormant:AdaptiveShield = AdaptiveShield.createDormant("空壳");
        dormant.onHitCallback = function(s:IShield, absorbed:Number):Void {
            hitCounts.dormant++;
        };
        dormant.absorbDamage(50, false, 1); // 空壳模式不吸收，不应触发

        // 扁平化模式
        var flattened:AdaptiveShield = AdaptiveShield.createDormant("扁平化");
        flattened.addShield(Shield.createTemporary(100, 50, -1, "盾"), false);
        flattened.onHitCallback = function(s:IShield, absorbed:Number):Void {
            hitCounts.flattened++;
        };
        flattened.absorbDamage(30, false, 1);

        // 委托模式
        var delegate:AdaptiveShield = AdaptiveShield.createDormant("委托");
        delegate.addShield(Shield.createTemporary(100, 50, -1, "盾"), true);
        delegate.onHitCallback = function(s:IShield, absorbed:Number):Void {
            hitCounts.delegate++;
        };
        delegate.absorbDamage(30, false, 1);

        // 栈模式
        var stack:AdaptiveShield = AdaptiveShield.createDormant("栈");
        stack.addShield(Shield.createTemporary(100, 50, -1, "盾1"));
        stack.addShield(Shield.createTemporary(100, 80, -1, "盾2"));
        stack.onHitCallback = function(s:IShield, absorbed:Number):Void {
            hitCounts.stack++;
        };
        stack.absorbDamage(30, false, 1);

        // 契约：空壳模式不触发（无吸收），其他模式触发1次
        var passed:Boolean = (
            hitCounts.dormant == 0 &&
            hitCounts.flattened == 1 &&
            hitCounts.delegate == 1 &&
            hitCounts.stack == 1
        );

        return passed ? "✓ onHitCallback一致性测试通过" :
            "✗ onHitCallback一致性测试失败（dormant=" + hitCounts.dormant +
            ", flattened=" + hitCounts.flattened +
            ", delegate=" + hitCounts.delegate +
            ", stack=" + hitCounts.stack + "）";
    }

    /**
     * 测试 onBreakCallback 在所有模式下都触发
     */
    private static function testConsistency_OnBreakAllModes():String {
        var breakCounts:Object = {flattened: 0, delegate: 0, stack: 0};

        // 扁平化模式临时盾
        var flattened:AdaptiveShield = AdaptiveShield.createDormant("扁平化");
        flattened.addShield(Shield.createTemporary(50, 100, -1, "盾"), false);
        flattened.onBreakCallback = function(s:IShield):Void {
            breakCounts.flattened++;
        };
        flattened.absorbDamage(100, false, 1); // 打碎

        // 委托模式临时盾
        var delegate:AdaptiveShield = AdaptiveShield.createDormant("委托");
        delegate.addShield(Shield.createTemporary(50, 100, -1, "盾"), true);
        delegate.onBreakCallback = function(s:IShield):Void {
            breakCounts.delegate++;
        };
        delegate.absorbDamage(100, false, 1); // 打碎

        // 栈模式：总容量归零时触发
        var stack:AdaptiveShield = AdaptiveShield.createDormant("栈");
        stack.addShield(Shield.createTemporary(50, 100, -1, "盾1"));
        stack.addShield(Shield.createTemporary(50, 80, -1, "盾2"));
        stack.onBreakCallback = function(s:IShield):Void {
            breakCounts.stack++;
        };
        // 直接消耗总容量（绕开强度节流），应触发一次 onBreak
        stack.consumeCapacity(9999);

        // 契约：都应触发1次
        var passed:Boolean = (breakCounts.flattened == 1 && breakCounts.delegate == 1 && breakCounts.stack == 1);

        return passed ? "✓ onBreakCallback一致性测试通过" :
            "✗ onBreakCallback一致性测试失败（flattened=" + breakCounts.flattened +
            ", delegate=" + breakCounts.delegate + ", stack=" + breakCounts.stack + "）";
    }

    /**
     * 测试回调参数 shield 是容器而非内部护盾
     *
     * 【契约】
     * 调用方应该总是收到容器引用，以便正确操作
     */
    private static function testConsistency_CallbackShieldParameter():String {
        var receivedShield:IShield = null;

        var container:AdaptiveShield = AdaptiveShield.createDormant("容器");
        container.addShield(Shield.createTemporary(100, 50, -1, "盾"));
        container.onHitCallback = function(s:IShield, absorbed:Number):Void {
            receivedShield = s;
        };

        container.absorbDamage(30, false, 1);

        // 契约：参数应该是容器本身
        var passed:Boolean = (receivedShield === container);

        return passed ? "✓ 回调参数shield测试通过" :
            "✗ 回调参数shield测试失败（receivedShield !== container）";
    }

    /**
     * 测试扁平化模式的自动检测机制
     *
     * 【契约】
     * 1. 无回调的护盾 addShield(shield, false) 会进入扁平化模式
     * 2. 有回调的护盾 addShield(shield, false) 会自动检测并切换到委托模式
     * 3. 扁平化模式下容器级回调正常工作
     */
    private static function testConsistency_InnerCallbackIsolation():String {
        // 场景1：无回调护盾 → 扁平化模式
        var container1:AdaptiveShield = AdaptiveShield.createDormant("容器1");
        var noCallbackShield:Shield = Shield.createTemporary(100, 50, -1, "无回调盾");
        container1.addShield(noCallbackShield, false);
        var isFlattened:Boolean = container1.isFlattenedMode();

        // 场景2：有回调护盾 → 自动切换到委托模式
        var container2:AdaptiveShield = AdaptiveShield.createDormant("容器2");
        var withCallbackShield:Shield = Shield.createTemporary(100, 50, -1, "有回调盾");
        var innerHitCalled:Boolean = false;
        withCallbackShield.onHitCallback = function(s:IShield, absorbed:Number):Void {
            innerHitCalled = true;
        };
        container2.addShield(withCallbackShield, false); // 虽然传false，但会自动检测
        var isDelegate:Boolean = container2.isDelegateMode();

        container2.absorbDamage(30, false, 1);

        // 契约验证：
        // 1. 无回调 → 扁平化
        // 2. 有回调 → 自动委托，内部回调会触发
        var passed:Boolean = (isFlattened && isDelegate && innerHitCalled);

        return passed ? "✓ 扁平化自动检测机制测试通过" :
            "✗ 扁平化自动检测机制测试失败（isFlattened=" + isFlattened +
            ", isDelegate=" + isDelegate + ", innerHitCalled=" + innerHitCalled + "）";
    }

    /**
     * 测试栈模式下内部护盾回调的触发
     *
     * 【契约】
     * 栈模式下各子盾独立管理回调，容器不干预
     */
    private static function testConsistency_StackModeInnerCallbacks():String {
        var innerHitCount:Number = 0;

        var container:AdaptiveShield = AdaptiveShield.createDormant("容器");

        var shield1:Shield = Shield.createTemporary(100, 50, -1, "盾1");
        shield1.onHitCallback = function(s:IShield, absorbed:Number):Void {
            innerHitCount++;
        };

        var shield2:Shield = Shield.createTemporary(100, 80, -1, "盾2");
        shield2.onHitCallback = function(s:IShield, absorbed:Number):Void {
            innerHitCount++;
        };

        container.addShield(shield1, true);
        container.addShield(shield2, true);

        // 伤害40，强度80，只有最高优先级盾吸收
        container.absorbDamage(40, false, 1);

        // 契约：栈模式下通过 consumeCapacity 触发各盾的 onHit
        // 具体触发哪个盾取决于排序和分配逻辑
        var passed:Boolean = (innerHitCount >= 1);

        return passed ? "✓ 栈模式内部回调测试通过（触发次数=" + innerHitCount + "）" :
            "✗ 栈模式内部回调测试失败（触发次数=" + innerHitCount + "）";
    }

    /**
     * P1：Shield 子类 override 不应被扁平化吞掉
     */
    private static function testConsistency_ShieldSubclassNotFlattened():String {
        var container:AdaptiveShield = AdaptiveShield.createDormant("容器");
        var my:MyShield = new MyShield(100, 50, 0, 0, "子类盾", "sub");

        container.addShield(my, false); // preserveReference=false，但子类应强制委托

        var modeOk:Boolean = (container.isDelegateMode() && !container.isFlattenedMode());
        container.absorbDamage(10, false, 1);
        var calledOk:Boolean = (my.absorbCalled > 0);

        var passed:Boolean = (modeOk && calledOk);
        return passed ? "✓ Shield子类不被扁平化测试通过" :
            "✗ Shield子类不被扁平化测试失败（delegate=" + container.isDelegateMode() +
            ", flattened=" + container.isFlattenedMode() + ", absorbCalled=" + my.absorbCalled + "）";
    }

    /**
     * P1：扁平化 → 升级到栈后，容器级 rechargeStart/rechargeFull 回调应保持可用
     */
    private static function testConsistency_UpgradeToStack_RechargeCallbacks():String {
        var container:AdaptiveShield = AdaptiveShield.createDormant("容器");
        var startCount:Number = 0;
        var fullCount:Number = 0;

        container.onRechargeStartCallback = function(s:IShield):Void {
            startCount++;
        };
        container.onRechargeFullCallback = function(s:IShield):Void {
            fullCount++;
        };

        // 无子盾回调的原生 Shield → 扁平化
        container.addShield(Shield.createRechargeable(100, 50, 10, 5, "回充盾"), false);

        // 受击触发延迟
        container.absorbDamage(10, false, 1);

        // 加一层触发升级到栈
        container.addShield(Shield.createTemporary(10, 1, -1, "dummy"), false);

        // 更新足够帧数：先触发 rechargeStart，再触发 rechargeFull
        for (var i:Number = 0; i < 10; i++) {
            container.update(1);
        }

        var passed:Boolean = (startCount == 1 && fullCount == 1);
        return passed ? "✓ 升级到栈后充能回调一致性测试通过" :
            "✗ 升级到栈后充能回调一致性测试失败（start=" + startCount + ", full=" + fullCount + "）";
    }

    /**
     * P1：扁平化 → 升级到栈后，容器级 expire 回调应保持可用
     */
    private static function testConsistency_UpgradeToStack_ExpireCallback():String {
        var container:AdaptiveShield = AdaptiveShield.createDormant("容器");
        var expireCount:Number = 0;

        container.onExpireCallback = function(s:IShield):Void {
            expireCount++;
        };

        // 无子盾回调的原生 Shield → 扁平化
        container.addShield(Shield.createTemporary(100, 50, 3, "短期盾"), false);
        // 加一层触发升级到栈
        container.addShield(Shield.createTemporary(10, 1, -1, "dummy"), false);

        // 更新足够帧数让短期盾过期
        for (var i:Number = 0; i < 10; i++) {
            container.update(1);
        }

        var passed:Boolean = (expireCount == 1);
        return passed ? "✓ 升级到栈后expire回调一致性测试通过" :
            "✗ 升级到栈后expire回调一致性测试失败（expireCount=" + expireCount + "）";
    }

    // ==================== 17. bypass与抵抗层边界测试 ====================

    /**
     * 测试 bypassShield 与抵抗层的边界行为
     *
     * 【固化的规则】
     * 1. bypassShield=true 时，只有 resistBypass=true 的护盾才能吸收
     * 2. 栈中只要有任意一层 resistBypass=true，整栈就能抵抗
     * 3. 抗真伤盾耗尽后，resistantCount 应该减少
     */
    private static function testBypassResistBoundary():String {
        var results:Array = [];

        results.push(testBypass_ResistantShieldDepleted());
        results.push(testBypass_ResistantBehindNormal());
        results.push(testBypass_MixedStackBypass());
        results.push(testBypass_AllResistantDepleted());
        results.push(testBypass_ResistantCountAccuracy());

        return formatResults(results, "bypass与抵抗层边界");
    }

    /**
     * 测试抗真伤盾耗尽后的 bypass 行为
     *
     * 【规则】
     * 抗真伤盾耗尽后，后续 bypassShield=true 的伤害应该穿透
     */
    private static function testBypass_ResistantShieldDepleted():String {
        var shield:AdaptiveShield = AdaptiveShield.createDormant("测试");
        shield.addShield(Shield.createResistant(50, 100, -1, "抗真伤"));

        // 先用普通伤害打空
        shield.absorbDamage(50, false, 1);

        // 验证耗尽
        var isEmpty:Boolean = shield.isEmpty();

        // 再用真伤攻击（应该穿透）
        var penetrating:Number = shield.absorbDamage(30, true, 1);

        // 【契约】耗尽的抗真伤盾不应阻挡真伤
        var passed:Boolean = (isEmpty && penetrating == 30);

        return passed ? "✓ 抗真伤盾耗尽后bypass测试通过" :
            "✗ 抗真伤盾耗尽后bypass测试失败（isEmpty=" + isEmpty + ", penetrating=" + penetrating + "）";
    }

    /**
     * 测试抗真伤盾被普通盾遮挡时的 bypass 行为
     *
     * 【规则】
     * 栈中有抗真伤盾时，真伤应该被吸收（而非跳过普通盾直接打抗真伤盾）
     */
    private static function testBypass_ResistantBehindNormal():String {
        var shield:AdaptiveShield = AdaptiveShield.createDormant("测试");

        // 普通盾在前（高优先级），抗真伤盾在后
        var normal:Shield = Shield.createTemporary(100, 100, -1, "普通盾");
        var resistant:Shield = Shield.createResistant(50, 50, -1, "抗真伤");

        shield.addShield(normal);
        shield.addShield(resistant);

        // 【契约】栈中有抗真伤盾，整栈就能抵抗真伤
        var resistantCount:Number = shield.getResistantCount();
        var penetrating:Number = shield.absorbDamage(60, true, 1);

        // 真伤60，强度100（普通盾），应该吸收60
        var passed:Boolean = (resistantCount == 1 && penetrating == 0);

        return passed ? "✓ 抗真伤盾被遮挡时bypass测试通过" :
            "✗ 抗真伤盾被遮挡时bypass测试失败（resistantCount=" + resistantCount + ", penetrating=" + penetrating + "）";
    }

    /**
     * 测试混合栈中 bypass 只影响无抵抗的护盾
     */
    private static function testBypass_MixedStackBypass():String {
        var shield:AdaptiveShield = AdaptiveShield.createDormant("测试");

        // 只有普通盾，无抗真伤盾
        shield.addShield(Shield.createTemporary(100, 80, -1, "普通盾1"));
        shield.addShield(Shield.createTemporary(100, 60, -1, "普通盾2"));

        // 【契约】无抗真伤盾时，真伤应该穿透
        var resistantCount:Number = shield.getResistantCount();
        var penetrating:Number = shield.absorbDamage(50, true, 1);

        var passed:Boolean = (resistantCount == 0 && penetrating == 50);

        return passed ? "✓ 混合栈bypass测试通过" :
            "✗ 混合栈bypass测试失败（resistantCount=" + resistantCount + ", penetrating=" + penetrating + "）";
    }

    /**
     * 测试所有抗真伤盾耗尽后的状态
     */
    private static function testBypass_AllResistantDepleted():String {
        var shield:AdaptiveShield = AdaptiveShield.createDormant("测试");

        shield.addShield(Shield.createResistant(50, 100, 3, "抗真伤1"));
        shield.addShield(Shield.createResistant(50, 80, 3, "抗真伤2"));

        // 初始状态
        var initialCount:Number = shield.getResistantCount();

        // 打空所有盾
        shield.absorbDamage(150, false, 1);

        // 让护盾过期（或验证耗尽）
        for (var i:Number = 0; i < 10; i++) {
            shield.update(1);
        }

        // 【契约】所有抗真伤盾耗尽后，resistantCount 应为 0
        var finalCount:Number = shield.getResistantCount();
        var passed:Boolean = (initialCount == 2 && finalCount == 0);

        return passed ? "✓ 所有抗真伤盾耗尽测试通过" :
            "✗ 所有抗真伤盾耗尽测试失败（initial=" + initialCount + ", final=" + finalCount + "）";
    }

    /**
     * 测试 resistantCount 的准确性
     */
    private static function testBypass_ResistantCountAccuracy():String {
        var shield:AdaptiveShield = AdaptiveShield.createDormant("测试");

        shield.addShield(Shield.createTemporary(100, 80, -1, "普通盾"));
        var count1:Number = shield.getResistantCount(); // 应为 0

        shield.addShield(Shield.createResistant(50, 60, -1, "抗真伤1"));
        var count2:Number = shield.getResistantCount(); // 应为 1

        shield.addShield(Shield.createResistant(50, 40, -1, "抗真伤2"));
        var count3:Number = shield.getResistantCount(); // 应为 2

        var passed:Boolean = (count1 == 0 && count2 == 1 && count3 == 2);

        return passed ? "✓ resistantCount准确性测试通过" :
            "✗ resistantCount准确性测试失败（count1=" + count1 + ", count2=" + count2 + ", count3=" + count3 + "）";
    }

    // ==================== 18. setter不变量测试 ====================

    /**
     * 测试 setter 方法对异常输入的处理
     *
     * 【不变量】
     * 1. capacity 不能为负数或 NaN
     * 2. maxCapacity 调整时 capacity 应同步钳位
     * 3. strength/rechargeRate/rechargeDelay 应能处理异常值
     */
    private static function testSetterInvariants():String {
        var results:Array = [];

        results.push(testSetter_CapacityNaN());
        results.push(testSetter_CapacityNegative());
        results.push(testSetter_MaxCapacityZero());
        results.push(testSetter_TargetCapacityClamping());
        results.push(testSetter_StrengthNaN());
        results.push(testSetter_RechargeRateNaN());
        results.push(testSetter_DelayStateClamping());
        results.push(testSetter_ExtremeValues());
        results.push(testSetter_ChainedSetters());

        return formatResults(results, "setter不变量");
    }

    /**
     * 测试 setCapacity(NaN) 的处理
     */
    private static function testSetter_CapacityNaN():String {
        var shield:AdaptiveShield = new AdaptiveShield(100, 50, 0, 0, "测试", "default");
        var originalCapacity:Number = shield.getCapacity();

        shield.setCapacity(Number.NaN);

        var afterNaN:Number = shield.getCapacity();

        // 【不变量】NaN 应该被处理（不应污染状态）
        // 当前实现可能保持原值或设为0，都是可接受的
        var passed:Boolean = (!isNaN(afterNaN));

        return passed ? "✓ setCapacity(NaN)测试通过（结果=" + afterNaN + "）" :
            "✗ setCapacity(NaN)测试失败（NaN污染了状态）";
    }

    /**
     * 测试 setCapacity 负数钳位
     */
    private static function testSetter_CapacityNegative():String {
        var shield:AdaptiveShield = new AdaptiveShield(100, 50, 0, 0, "测试", "default");

        shield.setCapacity(-100);
        var afterNegative:Number = shield.getCapacity();

        // 【不变量】负数应钳位到 0
        var passed:Boolean = (afterNegative == 0);

        return passed ? "✓ setCapacity负数钳位测试通过" :
            "✗ setCapacity负数钳位测试失败（结果=" + afterNegative + "）";
    }

    /**
     * 测试 setMaxCapacity(0) 的处理
     */
    private static function testSetter_MaxCapacityZero():String {
        var shield:AdaptiveShield = new AdaptiveShield(100, 50, 0, 0, "测试", "default");
        shield.setCapacity(50);

        shield.setMaxCapacity(0);

        var maxCapacity:Number = shield.getMaxCapacity();
        var capacity:Number = shield.getCapacity();

        // 【不变量】capacity 应同步钳位到新的 maxCapacity
        var passed:Boolean = (maxCapacity == 0 && capacity == 0);

        return passed ? "✓ setMaxCapacity(0)测试通过" :
            "✗ setMaxCapacity(0)测试失败（max=" + maxCapacity + ", cap=" + capacity + "）";
    }

    /**
     * 测试 setTargetCapacity 的钳位行为
     */
    private static function testSetter_TargetCapacityClamping():String {
        var shield:AdaptiveShield = new AdaptiveShield(100, 50, 0, 0, "测试", "default");

        shield.setTargetCapacity(200);
        var overflowPassed:Boolean = (shield.getTargetCapacity() == 100);

        shield.setTargetCapacity(-10);
        var negativePassed:Boolean = (shield.getTargetCapacity() == 0);

        var passed:Boolean = (overflowPassed && negativePassed);
        return passed ? "✓ setTargetCapacity钳位测试通过" :
            "✗ setTargetCapacity钳位测试失败（target=" + shield.getTargetCapacity() + "）";
    }

    /**
     * 测试 setStrength(NaN) 的影响
     */
    private static function testSetter_StrengthNaN():String {
        var shield:AdaptiveShield = new AdaptiveShield(100, 50, 0, 0, "测试", "default");

        shield.setStrength(Number.NaN);

        // 尝试吸收伤害，验证不会崩溃
        var penetrating:Number = shield.absorbDamage(30, false, 1);

        // 【不变量】strength 为 NaN 时应该安全处理
        // 预期行为：要么拒绝设置，要么后续计算安全
        var passed:Boolean = (!isNaN(penetrating));

        return passed ? "✓ setStrength(NaN)测试通过" :
            "✗ setStrength(NaN)测试失败（penetrating=NaN）";
    }

    /**
     * 测试 setRechargeRate(NaN) 的影响
     */
    private static function testSetter_RechargeRateNaN():String {
        var shield:AdaptiveShield = new AdaptiveShield(100, 50, 5, 0, "测试", "default");
        shield.setCapacity(50);

        shield.setRechargeRate(Number.NaN);

        // 尝试更新，验证不会崩溃
        var noError:Boolean = true;
        try {
            for (var i:Number = 0; i < 10; i++) {
                shield.update(1);
            }
        } catch (e) {
            noError = false;
        }

        var capacity:Number = shield.getCapacity();

        // 【不变量】update 不应崩溃，容量不应变成 NaN
        var passed:Boolean = (noError && !isNaN(capacity));

        return passed ? "✓ setRechargeRate(NaN)测试通过" :
            "✗ setRechargeRate(NaN)测试失败";
    }

    /**
     * 测试 setDelayState 在扁平化分支与 BaseShield 语义一致（delayTimer 钳位到 [0, rechargeDelay]）
     */
    private static function testSetter_DelayStateClamping():String {
        var shield:AdaptiveShield = AdaptiveShield.createRechargeable(100, 50, 5, 30, "测试");

        shield.setDelayState(true, 999);
        var overflowPassed:Boolean = (shield.isDelayed() == true && shield.getDelayTimer() == 30);

        shield.setDelayState(true, -10);
        var negativePassed:Boolean = (shield.getDelayTimer() == 0);

        var passed:Boolean = (overflowPassed && negativePassed);
        return passed ? "✓ setDelayState钳位测试通过" :
            "✗ setDelayState钳位测试失败（delayTimer=" + shield.getDelayTimer() + "）";
    }

    /**
     * 测试极大值的处理
     */
    private static function testSetter_ExtremeValues():String {
        var shield:AdaptiveShield = new AdaptiveShield(100, 50, 0, 0, "测试", "default");

        // 设置极大 capacity
        shield.setMaxCapacity(Number.MAX_VALUE);
        shield.setCapacity(Number.MAX_VALUE);

        // 吸收小伤害
        var penetrating:Number = shield.absorbDamage(100, false, 1);

        // 【不变量】极大值不应导致溢出或异常
        var capacity:Number = shield.getCapacity();
        var passed:Boolean = (!isNaN(capacity) && penetrating == 50); // 强度限制

        return passed ? "✓ 极大值处理测试通过" :
            "✗ 极大值处理测试失败（cap=" + capacity + ", pen=" + penetrating + "）";
    }

    /**
     * 测试连续 setter 调用的一致性
     */
    private static function testSetter_ChainedSetters():String {
        var shield:AdaptiveShield = new AdaptiveShield(100, 50, 0, 0, "测试", "default");

        // 连续设置
        shield.setMaxCapacity(200);
        shield.setCapacity(150);
        shield.setTargetCapacity(180);
        shield.setStrength(80);
        shield.setRechargeRate(5);
        shield.setRechargeDelay(30);

        // 验证所有设置生效
        var passed:Boolean = (
            shield.getMaxCapacity() == 200 &&
            shield.getCapacity() == 150 &&
            shield.getTargetCapacity() == 180 &&
            shield.getStrength() == 80 &&
            shield.getRechargeRate() == 5 &&
            shield.getRechargeDelay() == 30
        );

        return passed ? "✓ 连续setter调用测试通过" :
            "✗ 连续setter调用测试失败";
    }

    // ==================== 19. 集成级战斗模拟测试 ====================

    /**
     * 模拟真实战斗场景的集成测试
     *
     * 【测试目的】
     * 验证护盾系统在高频、并发调用下的稳定性和一致性
     */
    private static function testCombatSimulation():String {
        var results:Array = [];

        results.push(testCombat_HighFrequencyDamage());
        results.push(testCombat_InterleavedUpdateDamage());
        results.push(testCombat_MultiSourceDamage());
        results.push(testCombat_RapidModeSwitch());
        results.push(testCombat_LongDuration());
        results.push(testCombat_StateConsistency());

        return formatResults(results, "集成级战斗模拟");
    }

    /**
     * 测试高频伤害（每帧多次）
     */
    private static function testCombat_HighFrequencyDamage():String {
        var shield:AdaptiveShield = AdaptiveShield.createRechargeable(1000, 50, 10, 30, "战斗盾");

        var totalDamage:Number = 0;
        var totalAbsorbed:Number = 0;

        // 模拟 60 帧，每帧 5 次伤害
        for (var frame:Number = 0; frame < 60; frame++) {
            for (var hit:Number = 0; hit < 5; hit++) {
                var damage:Number = 10 + (frame % 20);
                var penetrating:Number = shield.absorbDamage(damage, false, 1);
                totalDamage += damage;
                totalAbsorbed += (damage - penetrating);
            }

            // 每帧更新
            shield.update(1);
        }

        // 验证状态一致性
        var capacity:Number = shield.getCapacity();
        var maxCapacity:Number = shield.getMaxCapacity();

        var passed:Boolean = (
            !isNaN(capacity) &&
            capacity >= 0 &&
            capacity <= maxCapacity &&
            totalAbsorbed > 0
        );

        return passed ? "✓ 高频伤害测试通过（吸收" + totalAbsorbed + "/" + totalDamage + "）" :
            "✗ 高频伤害测试失败（cap=" + capacity + "）";
    }

    /**
     * 测试交替的 update 和 damage（模拟不同帧率更新）
     */
    private static function testCombat_InterleavedUpdateDamage():String {
        var shield:AdaptiveShield = AdaptiveShield.createRechargeable(500, 80, 5, 20, "战斗盾");

        // 模拟：每 4 帧一次 update(4)，期间多次伤害
        for (var frame:Number = 0; frame < 120; frame++) {
            // 每帧 0-2 次伤害
            var hits:Number = frame % 3;
            for (var h:Number = 0; h < hits; h++) {
                shield.absorbDamage(15, false, 1);
            }

            // 每 4 帧一次批量更新
            if (frame % 4 == 3) {
                shield.update(4);
            }
        }

        var capacity:Number = shield.getCapacity();
        var passed:Boolean = (!isNaN(capacity) && capacity >= 0);

        return passed ? "✓ 交替update/damage测试通过（cap=" + Math.round(capacity) + "）" :
            "✗ 交替update/damage测试失败（cap=" + capacity + "）";
    }

    /**
     * 测试多源伤害（普通+真伤+联弹）
     */
    private static function testCombat_MultiSourceDamage():String {
        var shield:AdaptiveShield = AdaptiveShield.createDormant("战斗盾");
        shield.addShield(Shield.createResistant(500, 50, -1, "抗真伤"));
        shield.addShield(Shield.createTemporary(500, 80, -1, "普通盾"));

        // 混合伤害
        for (var i:Number = 0; i < 50; i++) {
            // 普通伤害
            shield.absorbDamage(20, false, 1);
            // 真伤
            shield.absorbDamage(10, true, 1);
            // 联弹
            shield.absorbDamage(100, false, 5);

            shield.update(1);
        }

        var capacity:Number = shield.getCapacity();
        var passed:Boolean = (!isNaN(capacity) && capacity >= 0);

        return passed ? "✓ 多源伤害测试通过（cap=" + Math.round(capacity) + "）" :
            "✗ 多源伤害测试失败（cap=" + capacity + "）";
    }

    /**
     * 测试快速模式切换（频繁 add/remove）
     */
    private static function testCombat_RapidModeSwitch():String {
        var shield:AdaptiveShield = AdaptiveShield.createDormant("战斗盾");
        var switchCount:Number = 0;

        for (var i:Number = 0; i < 100; i++) {
            // 添加护盾
            var temp:Shield = Shield.createTemporary(50, 30, 3, "临时盾" + i);
            shield.addShield(temp);

            // 受伤
            shield.absorbDamage(20, false, 1);

            // 更新
            shield.update(1);

            // 每10帧清空一次
            if (i % 10 == 9) {
                shield.clear();
                switchCount++;
            }
        }

        var isDormant:Boolean = shield.isDormantMode();
        var isActive:Boolean = shield.isActive();

        var passed:Boolean = (isDormant && isActive);

        return passed ? "✓ 快速模式切换测试通过（切换" + switchCount + "次）" :
            "✗ 快速模式切换测试失败（isDormant=" + isDormant + ", isActive=" + isActive + "）";
    }

    /**
     * 测试长时间运行（模拟 10 分钟战斗）
     */
    private static function testCombat_LongDuration():String {
        var shield:AdaptiveShield = AdaptiveShield.createRechargeable(1000, 100, 20, 60, "持久盾");

        var frames:Number = 18000; // 10分钟 @ 30FPS
        var startTime:Number = getTimer();

        for (var i:Number = 0; i < frames; i++) {
            // 随机伤害
            if (i % 5 == 0) {
                shield.absorbDamage(30, false, 1);
            }

            // 周期性更新
            if (i % 3 == 0) {
                shield.update(3);
            }
        }

        var endTime:Number = getTimer();
        var duration:Number = endTime - startTime;

        var capacity:Number = shield.getCapacity();
        var passed:Boolean = (!isNaN(capacity) && capacity >= 0 && capacity <= 1000);

        return passed ? "✓ 长时间运行测试通过（" + frames + "帧/" + duration + "ms）" :
            "✗ 长时间运行测试失败（cap=" + capacity + "）";
    }

    /**
     * 测试最终状态一致性
     */
    private static function testCombat_StateConsistency():String {
        var shield:AdaptiveShield = AdaptiveShield.createRechargeable(500, 60, 5, 30, "测试盾");

        // 模拟随机战斗
        for (var i:Number = 0; i < 200; i++) {
            var action:Number = i % 7;
            switch (action) {
                case 0:
                case 1:
                    shield.absorbDamage(25, false, 1);
                    break;
                case 2:
                    shield.absorbDamage(50, false, 3);
                    break;
                case 3:
                    shield.consumeCapacity(15);
                    break;
                case 4:
                case 5:
                    shield.update(1);
                    break;
                case 6:
                    shield.update(2);
                    break;
            }
        }

        // 验证不变量
        var capacity:Number = shield.getCapacity();
        var maxCapacity:Number = shield.getMaxCapacity();
        var strength:Number = shield.getStrength();
        var isActive:Boolean = shield.isActive();

        var invariants:Boolean = (
            !isNaN(capacity) &&
            !isNaN(maxCapacity) &&
            !isNaN(strength) &&
            capacity >= 0 &&
            capacity <= maxCapacity &&
            strength >= 0 &&
            isActive
        );

        return invariants ? "✓ 状态一致性测试通过" :
            "✗ 状态一致性测试失败（cap=" + capacity + ", max=" + maxCapacity + ", str=" + strength + "）";
    }

    // ==================== 20. IShield 接口契约测试 ====================

    /**
     * 测试 IShield 接口新增的方法
     *
     * 【测试目的】
     * 验证 getId, getOwner, setOwner 方法在所有实现类中的一致性
     */
    private static function testIShieldInterface():String {
        var results:Array = [];

        results.push(testInterface_GetIdUniqueness());
        results.push(testInterface_OwnerPropagation());
        results.push(testInterface_OwnerStackPropagation());
        results.push(testInterface_GetIdAfterModeSwitch());
        results.push(testInterface_StackGetRemoveById());

        return formatResults(results, "IShield 接口契约");
    }

    /**
     * 测试 getId 返回全局唯一 ID
     *
     * 【覆盖范围】
     * - BaseShield
     * - Shield
     * - AdaptiveShield
     * - ShieldStack
     */
    private static function testInterface_GetIdUniqueness():String {
        var ids:Object = {};
        var uniqueCount:Number = 0;

        // 创建所有护盾类型，包括 ShieldStack
        var base:BaseShield = new BaseShield(100, 50, 0, 0);
        var shield:Shield = Shield.createTemporary(100, 50, -1, "临时盾");
        var adaptive:AdaptiveShield = new AdaptiveShield(100, 50, 0, 0, "自适应", "default");
        var stack:ShieldStack = new ShieldStack();

        var id1:Number = base.getId();
        var id2:Number = shield.getId();
        var id3:Number = adaptive.getId();
        var id4:Number = stack.getId();

        // 检查唯一性
        if (ids[id1] == undefined) { ids[id1] = true; uniqueCount++; }
        if (ids[id2] == undefined) { ids[id2] = true; uniqueCount++; }
        if (ids[id3] == undefined) { ids[id3] = true; uniqueCount++; }
        if (ids[id4] == undefined) { ids[id4] = true; uniqueCount++; }

        var passed:Boolean = (uniqueCount == 4 && id1 != id2 && id2 != id3 && id3 != id4);

        return passed ? "✓ getId唯一性测试通过（含ShieldStack）" :
            "✗ getId唯一性测试失败（id1=" + id1 + ", id2=" + id2 + ", id3=" + id3 + ", id4=" + id4 + "）";
    }

    /**
     * 测试 setOwner 在单盾模式下的传播
     */
    private static function testInterface_OwnerPropagation():String {
        var owner:Object = {name: "测试单位"};
        var container:AdaptiveShield = AdaptiveShield.createDormant("容器");
        var inner:Shield = Shield.createTemporary(100, 50, -1, "内部盾");

        // 先添加护盾再设置 owner
        container.addShield(inner, true);  // 委托模式
        container.setOwner(owner);

        // 验证 owner 传播到内部护盾
        var containerOwner:Object = container.getOwner();
        var innerOwner:Object = inner.getOwner();

        var passed:Boolean = (containerOwner === owner && innerOwner === owner);

        return passed ? "✓ Owner传播测试通过" :
            "✗ Owner传播测试失败（containerOwner=" + (containerOwner == owner) + ", innerOwner=" + (innerOwner == owner) + "）";
    }

    /**
     * 测试 setOwner 在栈模式下传播到所有子盾
     */
    private static function testInterface_OwnerStackPropagation():String {
        var owner:Object = {name: "测试单位"};
        var container:AdaptiveShield = AdaptiveShield.createDormant("容器");

        var shield1:Shield = Shield.createTemporary(100, 50, -1, "盾1");
        var shield2:Shield = Shield.createTemporary(100, 80, -1, "盾2");

        container.addShield(shield1);
        container.addShield(shield2);

        // 升级到栈模式后设置 owner
        container.setOwner(owner);

        // 验证所有子盾都有 owner
        var s1Owner:Object = shield1.getOwner();
        var s2Owner:Object = shield2.getOwner();

        var passed:Boolean = (s1Owner === owner && s2Owner === owner);

        return passed ? "✓ 栈模式Owner传播测试通过" :
            "✗ 栈模式Owner传播测试失败";
    }

    /**
     * 测试模式切换后 getId 保持稳定
     */
    private static function testInterface_GetIdAfterModeSwitch():String {
        var container:AdaptiveShield = AdaptiveShield.createDormant("容器");
        var containerId:Number = container.getId();

        // 添加护盾触发模式切换
        container.addShield(Shield.createTemporary(100, 50, -1, "盾1"));
        var idAfterSingle:Number = container.getId();

        container.addShield(Shield.createTemporary(100, 80, -1, "盾2"));
        var idAfterStack:Number = container.getId();

        // 消耗护盾触发降级
        for (var i:Number = 0; i < 200; i++) {
            container.update(1);
        }
        var idAfterDormant:Number = container.getId();

        // 容器 ID 应该始终保持不变
        var passed:Boolean = (
            containerId == idAfterSingle &&
            idAfterSingle == idAfterStack &&
            idAfterStack == idAfterDormant
        );

        return passed ? "✓ 模式切换后ID稳定性测试通过" :
            "✗ 模式切换后ID稳定性测试失败（" + containerId + "→" + idAfterSingle + "→" + idAfterStack + "→" + idAfterDormant + "）";
    }

    /**
     * 测试 ShieldStack.getShieldById/removeShieldById 支持所有 IShield 实现
     *
     * 【测试目的】
     * 验证按 ID 查询/移除不仅支持 BaseShield，还支持 ShieldStack、AdaptiveShield 等
     */
    private static function testInterface_StackGetRemoveById():String {
        var stack:ShieldStack = new ShieldStack();

        // 添加多种类型的护盾
        var shield1:Shield = Shield.createTemporary(100, 50, -1, "普通盾");
        var nestedStack:ShieldStack = new ShieldStack();
        nestedStack.addShield(Shield.createTemporary(80, 40, -1, "嵌套盾"));
        var adaptive:AdaptiveShield = new AdaptiveShield(60, 30, 0, 0, "自适应", "default");

        stack.addShield(shield1);
        stack.addShield(nestedStack);
        stack.addShield(adaptive);

        var id1:Number = shield1.getId();
        var id2:Number = nestedStack.getId();
        var id3:Number = adaptive.getId();

        // 测试 getShieldById 能找到所有类型
        var found1:IShield = stack.getShieldById(id1);
        var found2:IShield = stack.getShieldById(id2);
        var found3:IShield = stack.getShieldById(id3);

        var getByIdPassed:Boolean = (
            found1 === shield1 &&
            found2 === nestedStack &&
            found3 === adaptive
        );

        // 测试 removeShieldById 能移除非 BaseShield 类型（ShieldStack）
        var removeResult:Boolean = stack.removeShieldById(id2);
        var afterRemove:IShield = stack.getShieldById(id2);

        var removeByIdPassed:Boolean = (removeResult == true && afterRemove == null);

        var passed:Boolean = getByIdPassed && removeByIdPassed;

        return passed ? "✓ ShieldStack按ID查询/移除支持所有IShield实现" :
            "✗ ShieldStack按ID查询/移除测试失败（getById=" + getByIdPassed + ", removeById=" + removeByIdPassed + "）";
    }

    // ==================== 21. ShieldSnapshot 测试 ====================

    /**
     * 测试 ShieldSnapshot 的行为
     *
     * 【测试目的】
     * 验证快照在回调中正确保留被弹出护盾的元数据
     */
    private static function testShieldSnapshot():String {
        var results:Array = [];

        results.push(testSnapshot_EjectedMetadata());
        results.push(testSnapshot_OwnerPreserved());
        results.push(testSnapshot_IShieldInterface());
        results.push(testSnapshot_FromFlattenedContainer());

        return formatResults(results, "ShieldSnapshot");
    }

    /**
     * 测试 onShieldEjected 回调中快照保留元数据
     *
     * 【关键验证】
     * - 快照 ID 语义：getId() 返回层 ID（被弹出护盾的原始 ID）
     * - 可通过 getContainerId() 获取容器 ID
     */
    private static function testSnapshot_EjectedMetadata():String {
        var container:AdaptiveShield = AdaptiveShield.createDormant("容器");
        var containerId:Number = container.getId();
        var ejectedName:String = "";
        var ejectedStrength:Number = -1;
        var ejectedId:Number = -1;
        var ejectedContainerId:Number = -1;

        container.onShieldEjectedCallback = function(ejected:IShield, c:AdaptiveShield):Void {
            ejectedStrength = ejected.getStrength();
            ejectedId = ejected.getId();
            // 尝试获取名称和容器ID（如果是 ShieldSnapshot 应该有）
            if (ejected instanceof ShieldSnapshot) {
                ejectedName = ShieldSnapshot(ejected).getName();
                ejectedContainerId = ShieldSnapshot(ejected).getContainerId();
            } else if (ejected instanceof Shield) {
                ejectedName = Shield(ejected).getName();
            }
        };

        // 添加一个临时盾，记录原始 ID
        var tempShield:Shield = Shield.createTemporary(50, 100, 3, "测试临时盾");
        var originalShieldId:Number = tempShield.getId();
        container.addShield(tempShield, false);  // 扁平化

        // 等待过期
        for (var i:Number = 0; i < 10; i++) {
            container.update(1);
        }

        // 验证回调中收到了正确的元数据
        // 关键：快照的 getId() 应该返回层 ID（原始护盾 ID），而非容器 ID
        var passed:Boolean = (
            ejectedStrength == 100 &&
            ejectedName == "测试临时盾" &&
            ejectedId == originalShieldId &&    // 验证层 ID 语义
            ejectedContainerId == containerId   // 验证容器 ID
        );

        return passed ? "✓ 弹出快照元数据测试通过（含ID语义验证）" :
            "✗ 弹出快照元数据测试失败（strength=" + ejectedStrength + ", name=" + ejectedName +
            ", ejectedId=" + ejectedId + ", originalId=" + originalShieldId +
            ", containerId=" + ejectedContainerId + "）";
    }

    /**
     * 测试快照中保留 owner 引用
     */
    private static function testSnapshot_OwnerPreserved():String {
        var owner:Object = {name: "测试单位"};
        var container:AdaptiveShield = AdaptiveShield.createDormant("容器");
        container.setOwner(owner);

        var ejectedOwner:Object = null;

        container.onShieldEjectedCallback = function(ejected:IShield, c:AdaptiveShield):Void {
            ejectedOwner = ejected.getOwner();
        };

        container.addShield(Shield.createTemporary(50, 100, 2, "临时盾"), false);

        // 等待过期
        for (var i:Number = 0; i < 10; i++) {
            container.update(1);
        }

        var passed:Boolean = (ejectedOwner === owner);

        return passed ? "✓ 快照Owner保留测试通过" :
            "✗ 快照Owner保留测试失败";
    }

    /**
     * 测试 ShieldSnapshot 实现 IShield 接口
     *
     * 【isEmpty 语义】
     * isEmpty() 反映快照时的容量状态：
     * - capacity > 0：返回 false（护盾因过期弹出，仍有容量）
     * - capacity <= 0：返回 true（护盾因耗尽弹出）
     */
    private static function testSnapshot_IShieldInterface():String {
        // 创建快照（容量 > 0，模拟"过期但仍有容量"的场景）
        var snapshotWithCap:ShieldSnapshot = new ShieldSnapshot(
            1,      // layerId
            2,      // containerId
            "测试快照",
            "snapshot",
            50,     // capacity > 0
            100,    // maxCapacity
            80,     // targetCapacity
            60,     // strength
            5,      // rechargeRate
            30,     // rechargeDelay
            true,   // isTemporary
            false,  // resistBypass
            null    // owner
        );

        // 创建快照（容量 = 0，模拟"打空"的场景）
        var snapshotEmpty:ShieldSnapshot = new ShieldSnapshot(
            3, 4, "空快照", "snapshot",
            0,      // capacity = 0
            100, 80, 60, 5, 30, true, false, null
        );

        // 验证只读属性
        var id:Number = snapshotWithCap.getId();
        var capacity:Number = snapshotWithCap.getCapacity();
        var maxCapacity:Number = snapshotWithCap.getMaxCapacity();
        var strength:Number = snapshotWithCap.getStrength();
        var isEmptyWithCap:Boolean = snapshotWithCap.isEmpty();   // 有容量应返回 false
        var isEmptyNoCap:Boolean = snapshotEmpty.isEmpty();       // 无容量应返回 true
        var isActive:Boolean = snapshotWithCap.isActive();        // 快照始终不激活
        var sortPriority:Number = snapshotWithCap.getSortPriority();

        // 验证空操作
        var penetrating:Number = snapshotWithCap.absorbDamage(100, false, 1);  // 应返回100
        var consumed:Number = snapshotWithCap.consumeCapacity(50);             // 应返回0
        var updated:Boolean = snapshotWithCap.update(1);                       // 应返回false

        var passed:Boolean = (
            id == 1 &&
            capacity == 50 &&
            maxCapacity == 100 &&
            strength == 60 &&
            isEmptyWithCap == false &&   // 有容量的快照 isEmpty = false
            isEmptyNoCap == true &&      // 无容量的快照 isEmpty = true
            isActive == false &&
            penetrating == 100 &&
            consumed == 0 &&
            updated == false &&
            !isNaN(sortPriority)
        );

        return passed ? "✓ ShieldSnapshot IShield接口测试通过（含isEmpty语义）" :
            "✗ ShieldSnapshot IShield接口测试失败（isEmptyWithCap=" + isEmptyWithCap + ", isEmptyNoCap=" + isEmptyNoCap + "）";
    }

    /**
     * 测试从扁平化容器创建快照
     */
    private static function testSnapshot_FromFlattenedContainer():String {
        var owner:Object = {name: "测试单位"};
        var container:AdaptiveShield = new AdaptiveShield(100, 50, 5, 30, "容器名", "容器类型");
        container.setOwner(owner);

        // 使用工厂方法创建快照
        var snapshot:ShieldSnapshot = ShieldSnapshot.fromFlattenedContainer(container);

        // 验证快照正确捕获容器状态
        var passed:Boolean = (
            snapshot.getId() == container.getId() &&
            snapshot.getContainerId() == container.getId() &&
            snapshot.getName() == "容器名" &&
            snapshot.getType() == "容器类型" &&
            snapshot.getCapacity() == container.getCapacity() &&
            snapshot.getMaxCapacity() == 100 &&
            snapshot.getStrength() == 50 &&
            snapshot.getRechargeRate() == 5 &&
            snapshot.getOwner() === owner
        );

        return passed ? "✓ fromFlattenedContainer工厂方法测试通过" :
            "✗ fromFlattenedContainer工厂方法测试失败";
    }
}
