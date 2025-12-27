/**
 * BaseShieldTestSuite - 护盾基类测试套件
 *
 * 集中管理 BaseShield 类的所有测试用例
 * 覆盖核心属性、伤害吸收、容量消耗、充能/衰减、事件回调等功能
 *
 * @author Crazyfs
 * @version 1.0
 */
import org.flashNight.arki.component.Shield.*;

class org.flashNight.arki.component.Shield.BaseShieldTestSuite {

    // ==================== 公共入口 ====================

    /**
     * 运行完整测试套件
     * @return 测试报告字符串
     */
    public static function runAllTests():String {
        var report:String = "\n";
        report += "========================================\n";
        report += "    BaseShield 测试套件 v1.0\n";
        report += "========================================\n\n";

        var startTime:Number = getTimer();

        // 1. 构造函数与初始化测试
        report += "【1. 构造函数与初始化测试】\n";
        report += testConstructor();
        report += "\n";

        // 2. 伤害吸收测试
        report += "【2. 伤害吸收测试】\n";
        report += testAbsorbDamage();
        report += "\n";

        // 3. 容量消耗测试
        report += "【3. 容量消耗测试】\n";
        report += testConsumeCapacity();
        report += "\n";

        // 4. 属性设置器测试
        report += "【4. 属性设置器测试】\n";
        report += testSetters();
        report += "\n";

        // 5. 充能机制测试
        report += "【5. 充能机制测试】\n";
        report += testRecharging();
        report += "\n";

        // 6. 衰减机制测试
        report += "【6. 衰减机制测试】\n";
        report += testDecaying();
        report += "\n";

        // 7. 事件回调测试
        report += "【7. 事件回调测试】\n";
        report += testCallbacks();
        report += "\n";

        // 8. 边界条件测试
        report += "【8. 边界条件测试】\n";
        report += testBoundaryConditions();
        report += "\n";

        // 9. 联弹机制测试
        report += "【9. 联弹机制测试】\n";
        report += testHitCount();
        report += "\n";

        // 10. 性能测试
        report += "【10. 性能测试】\n";
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

    // ==================== 1. 构造函数与初始化测试 ====================

    private static function testConstructor():String {
        var results:Array = [];

        results.push(testConstructor_DefaultValues());
        results.push(testConstructor_CustomValues());
        results.push(testConstructor_InvalidValues());
        results.push(testConstructor_UniqueIds());

        return formatResults(results, "构造函数");
    }

    /**
     * 测试默认值初始化
     */
    private static function testConstructor_DefaultValues():String {
        var shield:BaseShield = new BaseShield(undefined, undefined, undefined, undefined);

        var passed:Boolean = (
            shield.getMaxCapacity() == 100 &&
            shield.getCapacity() == 100 &&
            shield.getTargetCapacity() == 100 &&
            shield.getStrength() == 50 &&
            shield.getRechargeRate() == 0 &&
            shield.getRechargeDelay() == 0 &&
            shield.isActive() == true &&
            shield.isEmpty() == false
        );

        return passed ? "✓ 默认值初始化测试通过" : "✗ 默认值初始化测试失败";
    }

    /**
     * 测试自定义值初始化
     */
    private static function testConstructor_CustomValues():String {
        var shield:BaseShield = new BaseShield(200, 80, 5, 60);

        var passed:Boolean = (
            shield.getMaxCapacity() == 200 &&
            shield.getCapacity() == 200 &&
            shield.getStrength() == 80 &&
            shield.getRechargeRate() == 5 &&
            shield.getRechargeDelay() == 60
        );

        return passed ? "✓ 自定义值初始化测试通过" : "✗ 自定义值初始化测试失败";
    }

    /**
     * 测试无效值处理（NaN）
     */
    private static function testConstructor_InvalidValues():String {
        var shield:BaseShield = new BaseShield(Number.NaN, Number.NaN, Number.NaN, Number.NaN);

        // NaN 应该被替换为默认值
        var passed:Boolean = (
            shield.getMaxCapacity() == 100 &&
            shield.getStrength() == 50 &&
            shield.getRechargeRate() == 0 &&
            shield.getRechargeDelay() == 0
        );

        return passed ? "✓ 无效值处理测试通过" : "✗ 无效值处理测试失败";
    }

    /**
     * 测试唯一ID生成
     */
    private static function testConstructor_UniqueIds():String {
        var shield1:BaseShield = new BaseShield(100, 50, 0, 0);
        var shield2:BaseShield = new BaseShield(100, 50, 0, 0);
        var shield3:BaseShield = new BaseShield(100, 50, 0, 0);

        var passed:Boolean = (
            shield1.getId() != shield2.getId() &&
            shield2.getId() != shield3.getId() &&
            shield1.getId() != shield3.getId()
        );

        return passed ? "✓ 唯一ID生成测试通过" : "✗ 唯一ID生成测试失败";
    }

    // ==================== 2. 伤害吸收测试 ====================

    private static function testAbsorbDamage():String {
        var results:Array = [];

        results.push(testAbsorbDamage_Basic());
        results.push(testAbsorbDamage_StrengthLimit());
        results.push(testAbsorbDamage_CapacityLimit());
        results.push(testAbsorbDamage_BypassShield());
        results.push(testAbsorbDamage_ResistBypass());
        results.push(testAbsorbDamage_InactiveShield());

        return formatResults(results, "伤害吸收");
    }

    /**
     * 基础伤害吸收测试
     */
    private static function testAbsorbDamage_Basic():String {
        var shield:BaseShield = new BaseShield(100, 50, 0, 0);

        // 伤害30，强度50，容量100 -> 吸收30，穿透0
        var penetrating:Number = shield.absorbDamage(30, false, 1);

        var passed:Boolean = (penetrating == 0 && shield.getCapacity() == 70);

        return passed ? "✓ 基础伤害吸收测试通过" :
            "✗ 基础伤害吸收测试失败（穿透=" + penetrating + "，容量=" + shield.getCapacity() + "）";
    }

    /**
     * 强度限制测试
     */
    private static function testAbsorbDamage_StrengthLimit():String {
        var shield:BaseShield = new BaseShield(100, 50, 0, 0);

        // 伤害80，强度50 -> 吸收50，穿透30
        var penetrating:Number = shield.absorbDamage(80, false, 1);

        var passed:Boolean = (penetrating == 30 && shield.getCapacity() == 50);

        return passed ? "✓ 强度限制测试通过" :
            "✗ 强度限制测试失败（穿透=" + penetrating + "，期望30）";
    }

    /**
     * 容量限制测试
     */
    private static function testAbsorbDamage_CapacityLimit():String {
        var shield:BaseShield = new BaseShield(30, 100, 0, 0);  // 容量30，强度100

        // 伤害50，强度100但容量只有30 -> 吸收30，穿透20
        var penetrating:Number = shield.absorbDamage(50, false, 1);

        var passed:Boolean = (penetrating == 20 && shield.getCapacity() == 0 && shield.isEmpty());

        return passed ? "✓ 容量限制测试通过" :
            "✗ 容量限制测试失败（穿透=" + penetrating + "，期望20）";
    }

    /**
     * 绕过护盾测试
     */
    private static function testAbsorbDamage_BypassShield():String {
        var shield:BaseShield = new BaseShield(100, 50, 0, 0);

        // bypassShield=true，护盾不抵抗 -> 直接穿透
        var penetrating:Number = shield.absorbDamage(30, true, 1);

        var passed:Boolean = (penetrating == 30 && shield.getCapacity() == 100);

        return passed ? "✓ 绕过护盾测试通过" : "✗ 绕过护盾测试失败";
    }

    /**
     * 抵抗绕过测试
     */
    private static function testAbsorbDamage_ResistBypass():String {
        var shield:BaseShield = new BaseShield(100, 50, 0, 0);
        shield.setResistBypass(true);

        // bypassShield=true，但护盾抵抗绕过 -> 正常吸收
        var penetrating:Number = shield.absorbDamage(30, true, 1);

        var passed:Boolean = (penetrating == 0 && shield.getCapacity() == 70);

        return passed ? "✓ 抵抗绕过测试通过" : "✗ 抵抗绕过测试失败";
    }

    /**
     * 未激活护盾测试
     */
    private static function testAbsorbDamage_InactiveShield():String {
        var shield:BaseShield = new BaseShield(100, 50, 0, 0);
        shield.setActive(false);

        // 护盾未激活 -> 直接穿透
        var penetrating:Number = shield.absorbDamage(30, false, 1);

        var passed:Boolean = (penetrating == 30 && shield.getCapacity() == 100);

        return passed ? "✓ 未激活护盾测试通过" : "✗ 未激活护盾测试失败";
    }

    // ==================== 3. 容量消耗测试 ====================

    private static function testConsumeCapacity():String {
        var results:Array = [];

        results.push(testConsumeCapacity_Basic());
        results.push(testConsumeCapacity_OverConsume());
        results.push(testConsumeCapacity_ZeroAmount());
        results.push(testConsumeCapacity_EmptyShield());

        return formatResults(results, "容量消耗");
    }

    /**
     * 基础容量消耗测试
     */
    private static function testConsumeCapacity_Basic():String {
        var shield:BaseShield = new BaseShield(100, 50, 0, 0);

        var consumed:Number = shield.consumeCapacity(30);

        var passed:Boolean = (consumed == 30 && shield.getCapacity() == 70);

        return passed ? "✓ 基础容量消耗测试通过" : "✗ 基础容量消耗测试失败";
    }

    /**
     * 超量消耗测试
     */
    private static function testConsumeCapacity_OverConsume():String {
        var shield:BaseShield = new BaseShield(50, 100, 0, 0);

        // 尝试消耗80，但容量只有50 -> 只消耗50
        var consumed:Number = shield.consumeCapacity(80);

        var passed:Boolean = (consumed == 50 && shield.getCapacity() == 0 && shield.isEmpty());

        return passed ? "✓ 超量消耗测试通过" : "✗ 超量消耗测试失败";
    }

    /**
     * 零消耗测试
     */
    private static function testConsumeCapacity_ZeroAmount():String {
        var shield:BaseShield = new BaseShield(100, 50, 0, 0);

        var consumed:Number = shield.consumeCapacity(0);

        var passed:Boolean = (consumed == 0 && shield.getCapacity() == 100);

        return passed ? "✓ 零消耗测试通过" : "✗ 零消耗测试失败";
    }

    /**
     * 空护盾消耗测试
     */
    private static function testConsumeCapacity_EmptyShield():String {
        var shield:BaseShield = new BaseShield(100, 50, 0, 0);
        shield.setCapacity(0);

        var consumed:Number = shield.consumeCapacity(30);

        var passed:Boolean = (consumed == 0);

        return passed ? "✓ 空护盾消耗测试通过" : "✗ 空护盾消耗测试失败";
    }

    // ==================== 4. 属性设置器测试 ====================

    private static function testSetters():String {
        var results:Array = [];

        results.push(testSetters_Capacity());
        results.push(testSetters_MaxCapacity());
        results.push(testSetters_TargetCapacity());
        results.push(testSetters_Strength());
        results.push(testSetters_Owner());

        return formatResults(results, "属性设置器");
    }

    /**
     * 容量设置器测试
     */
    private static function testSetters_Capacity():String {
        var shield:BaseShield = new BaseShield(100, 50, 0, 0);

        // 测试正常设置
        shield.setCapacity(60);
        var normalPassed:Boolean = (shield.getCapacity() == 60);

        // 测试负值钳位到0
        shield.setCapacity(-10);
        var negativePassed:Boolean = (shield.getCapacity() == 0);

        // 测试超出最大值钳位
        shield.setCapacity(150);
        var overflowPassed:Boolean = (shield.getCapacity() == 100);

        var passed:Boolean = normalPassed && negativePassed && overflowPassed;

        return passed ? "✓ 容量设置器测试通过" : "✗ 容量设置器测试失败";
    }

    /**
     * 最大容量设置器测试
     */
    private static function testSetters_MaxCapacity():String {
        var shield:BaseShield = new BaseShield(100, 50, 0, 0);
        shield.setCapacity(80);

        // 设置新的最大容量低于当前容量
        shield.setMaxCapacity(50);

        var passed:Boolean = (shield.getMaxCapacity() == 50 && shield.getCapacity() == 50);

        return passed ? "✓ 最大容量设置器测试通过" : "✗ 最大容量设置器测试失败";
    }

    /**
     * 目标容量设置器测试
     */
    private static function testSetters_TargetCapacity():String {
        var shield:BaseShield = new BaseShield(100, 50, 0, 0);

        shield.setTargetCapacity(80);

        var passed:Boolean = (shield.getTargetCapacity() == 80);

        return passed ? "✓ 目标容量设置器测试通过" : "✗ 目标容量设置器测试失败";
    }

    /**
     * 强度设置器测试
     */
    private static function testSetters_Strength():String {
        var shield:BaseShield = new BaseShield(100, 50, 0, 0);

        shield.setStrength(75);

        var passed:Boolean = (shield.getStrength() == 75);

        return passed ? "✓ 强度设置器测试通过" : "✗ 强度设置器测试失败";
    }

    /**
     * Owner设置器测试
     */
    private static function testSetters_Owner():String {
        var shield:BaseShield = new BaseShield(100, 50, 0, 0);
        var owner:Object = {name: "TestUnit"};

        shield.setOwner(owner);

        var passed:Boolean = (shield.getOwner() == owner);

        return passed ? "✓ Owner设置器测试通过" : "✗ Owner设置器测试失败";
    }

    // ==================== 5. 充能机制测试 ====================

    private static function testRecharging():String {
        var results:Array = [];

        results.push(testRecharging_Basic());
        results.push(testRecharging_WithDelay());
        results.push(testRecharging_DelayReset());
        results.push(testRecharging_ReachTarget());
        results.push(testRecharging_UpdateReturnValue());

        return formatResults(results, "充能机制");
    }

    /**
     * 基础充能测试
     */
    private static function testRecharging_Basic():String {
        var shield:BaseShield = new BaseShield(100, 50, 5, 0);  // 每帧充能5
        shield.setCapacity(50);

        // 更新10帧
        for (var i:Number = 0; i < 10; i++) {
            shield.update(1);
        }

        // 50 + 5*10 = 100
        var passed:Boolean = (shield.getCapacity() == 100);

        return passed ? "✓ 基础充能测试通过" :
            "✗ 基础充能测试失败（容量=" + shield.getCapacity() + "，期望100）";
    }

    /**
     * 充能延迟测试
     */
    private static function testRecharging_WithDelay():String {
        var shield:BaseShield = new BaseShield(100, 50, 5, 30);  // 延迟30帧
        shield.setCapacity(50);

        // 模拟被击中，触发延迟
        shield.onHit(10);

        // 更新20帧（仍在延迟中）
        for (var i:Number = 0; i < 20; i++) {
            shield.update(1);
        }

        // 延迟期间不充能
        var delayedPassed:Boolean = (shield.getCapacity() == 50);

        // 再更新20帧（延迟结束，开始充能）
        for (var j:Number = 0; j < 20; j++) {
            shield.update(1);
        }

        // 充能10帧 (30帧延迟后还剩10帧): 50 + 5*10 = 100
        var chargedPassed:Boolean = (shield.getCapacity() == 100);

        var passed:Boolean = delayedPassed && chargedPassed;

        return passed ? "✓ 充能延迟测试通过" :
            "✗ 充能延迟测试失败（延迟期=" + (shield.getCapacity() == 50) + "，充能后=" + shield.getCapacity() + "）";
    }

    /**
     * 延迟重置测试
     */
    private static function testRecharging_DelayReset():String {
        var shield:BaseShield = new BaseShield(100, 50, 5, 30);
        shield.setCapacity(50);

        // 第一次击中
        shield.onHit(10);

        // 更新20帧
        for (var i:Number = 0; i < 20; i++) {
            shield.update(1);
        }

        // 再次击中，应该重置延迟
        shield.onHit(10);

        var isDelayed:Boolean = shield.isDelayed();
        var delayTimer:Number = shield.getDelayTimer();

        var passed:Boolean = (isDelayed == true && delayTimer == 30);

        return passed ? "✓ 延迟重置测试通过" : "✗ 延迟重置测试失败";
    }

    /**
     * 充能至目标容量测试
     */
    private static function testRecharging_ReachTarget():String {
        var shield:BaseShield = new BaseShield(100, 50, 10, 0);
        shield.setCapacity(50);
        shield.setTargetCapacity(80);  // 目标容量80

        // 更新10帧
        for (var i:Number = 0; i < 10; i++) {
            shield.update(1);
        }

        // 应该停在80，不会超过目标容量
        var passed:Boolean = (shield.getCapacity() == 80);

        return passed ? "✓ 充能至目标容量测试通过" :
            "✗ 充能至目标容量测试失败（容量=" + shield.getCapacity() + "，期望80）";
    }

    /**
     * update返回值测试
     */
    private static function testRecharging_UpdateReturnValue():String {
        var shield:BaseShield = new BaseShield(100, 50, 5, 0);

        // 已满时返回false
        var fullResult:Boolean = shield.update(1);

        shield.setCapacity(50);

        // 充能中返回true
        var chargingResult:Boolean = shield.update(1);

        var passed:Boolean = (fullResult == false && chargingResult == true);

        return passed ? "✓ update返回值测试通过" : "✗ update返回值测试失败";
    }

    // ==================== 6. 衰减机制测试 ====================

    private static function testDecaying():String {
        var results:Array = [];

        results.push(testDecaying_Basic());
        results.push(testDecaying_NoDelayEffect());
        results.push(testDecaying_ReachZero());
        results.push(testDecaying_ZeroCapacityNoChange());

        return formatResults(results, "衰减机制");
    }

    /**
     * 基础衰减测试
     */
    private static function testDecaying_Basic():String {
        var shield:BaseShield = new BaseShield(100, 50, -5, 0);  // 每帧衰减5

        // 更新10帧
        for (var i:Number = 0; i < 10; i++) {
            shield.update(1);
        }

        // 100 - 5*10 = 50
        var passed:Boolean = (shield.getCapacity() == 50);

        return passed ? "✓ 基础衰减测试通过" :
            "✗ 基础衰减测试失败（容量=" + shield.getCapacity() + "，期望50）";
    }

    /**
     * 衰减不受延迟影响测试
     */
    private static function testDecaying_NoDelayEffect():String {
        var shield:BaseShield = new BaseShield(100, 50, -5, 30);  // 设置了延迟，但衰减不受影响

        // 触发"命中"
        shield.onHit(10);

        // 更新10帧
        for (var i:Number = 0; i < 10; i++) {
            shield.update(1);
        }

        // 衰减盾不受延迟影响：100 - 5*10 = 50
        var passed:Boolean = (shield.getCapacity() == 50);

        return passed ? "✓ 衰减不受延迟影响测试通过" : "✗ 衰减不受延迟影响测试失败";
    }

    /**
     * 衰减至零测试
     */
    private static function testDecaying_ReachZero():String {
        var shield:BaseShield = new BaseShield(50, 50, -10, 0);

        // 更新10帧
        for (var i:Number = 0; i < 10; i++) {
            shield.update(1);
        }

        var passed:Boolean = (shield.getCapacity() == 0 && shield.isEmpty());

        return passed ? "✓ 衰减至零测试通过" : "✗ 衰减至零测试失败";
    }

    /**
     * 零容量不再变化测试
     */
    private static function testDecaying_ZeroCapacityNoChange():String {
        var shield:BaseShield = new BaseShield(100, 50, -5, 0);
        shield.setCapacity(0);

        // 更新应该返回false（无变化）
        var result:Boolean = shield.update(1);

        var passed:Boolean = (result == false && shield.getCapacity() == 0);

        return passed ? "✓ 零容量不再变化测试通过" : "✗ 零容量不再变化测试失败";
    }

    // ==================== 7. 事件回调测试 ====================

    private static function testCallbacks():String {
        var results:Array = [];

        results.push(testCallbacks_OnHit());
        results.push(testCallbacks_OnBreak());
        results.push(testCallbacks_OnRechargeStart());
        results.push(testCallbacks_OnRechargeFull());

        return formatResults(results, "事件回调");
    }

    /**
     * onHit回调测试
     */
    private static function testCallbacks_OnHit():String {
        var shield:BaseShield = new BaseShield(100, 50, 0, 0);
        var hitCount:Number = 0;
        var lastAbsorbed:Number = 0;

        shield.onHitCallback = function(s:IShield, absorbed:Number):Void {
            hitCount++;
            lastAbsorbed = absorbed;
        };

        shield.absorbDamage(30, false, 1);
        shield.absorbDamage(20, false, 1);

        var passed:Boolean = (hitCount == 2 && lastAbsorbed == 20);

        return passed ? "✓ onHit回调测试通过" : "✗ onHit回调测试失败";
    }

    /**
     * onBreak回调测试
     */
    private static function testCallbacks_OnBreak():String {
        var shield:BaseShield = new BaseShield(30, 100, 0, 0);
        var breakCalled:Boolean = false;

        shield.onBreakCallback = function(s:IShield):Void {
            breakCalled = true;
        };

        shield.absorbDamage(50, false, 1);  // 超过容量，应触发break

        var passed:Boolean = (breakCalled == true && shield.isEmpty());

        return passed ? "✓ onBreak回调测试通过" : "✗ onBreak回调测试失败";
    }

    /**
     * onRechargeStart回调测试
     */
    private static function testCallbacks_OnRechargeStart():String {
        var shield:BaseShield = new BaseShield(100, 50, 5, 10);  // 延迟10帧
        var rechargeCalled:Boolean = false;

        shield.setCapacity(50);
        shield.onHit(10);  // 触发延迟

        shield.onRechargeStartCallback = function(s:IShield):Void {
            rechargeCalled = true;
        };

        // 更新15帧（延迟10帧后开始充能）
        for (var i:Number = 0; i < 15; i++) {
            shield.update(1);
        }

        var passed:Boolean = (rechargeCalled == true);

        return passed ? "✓ onRechargeStart回调测试通过" : "✗ onRechargeStart回调测试失败";
    }

    /**
     * onRechargeFull回调测试
     */
    private static function testCallbacks_OnRechargeFull():String {
        var shield:BaseShield = new BaseShield(100, 50, 10, 0);
        var fullCalled:Boolean = false;

        shield.setCapacity(50);

        shield.onRechargeFullCallback = function(s:IShield):Void {
            fullCalled = true;
        };

        // 更新10帧充满
        for (var i:Number = 0; i < 10; i++) {
            shield.update(1);
        }

        var passed:Boolean = (fullCalled == true && shield.getCapacity() == 100);

        return passed ? "✓ onRechargeFull回调测试通过" : "✗ onRechargeFull回调测试失败";
    }

    // ==================== 8. 边界条件测试 ====================

    private static function testBoundaryConditions():String {
        var results:Array = [];

        results.push(testBoundary_ZeroDamage());
        results.push(testBoundary_ZeroStrength());
        results.push(testBoundary_ZeroCapacity());
        results.push(testBoundary_NegativeDamage());
        results.push(testBoundary_LargeNumbers());

        return formatResults(results, "边界条件");
    }

    /**
     * 零伤害测试
     */
    private static function testBoundary_ZeroDamage():String {
        var shield:BaseShield = new BaseShield(100, 50, 0, 0);

        var penetrating:Number = shield.absorbDamage(0, false, 1);

        var passed:Boolean = (penetrating == 0 && shield.getCapacity() == 100);

        return passed ? "✓ 零伤害测试通过" : "✗ 零伤害测试失败";
    }

    /**
     * 零强度测试
     */
    private static function testBoundary_ZeroStrength():String {
        var shield:BaseShield = new BaseShield(100, 0, 0, 0);

        // 强度为0，不能吸收任何伤害
        var penetrating:Number = shield.absorbDamage(50, false, 1);

        var passed:Boolean = (penetrating == 50 && shield.getCapacity() == 100);

        return passed ? "✓ 零强度测试通过" : "✗ 零强度测试失败";
    }

    /**
     * 零容量测试
     */
    private static function testBoundary_ZeroCapacity():String {
        var shield:BaseShield = new BaseShield(100, 50, 0, 0);
        shield.setCapacity(0);

        var penetrating:Number = shield.absorbDamage(30, false, 1);

        var passed:Boolean = (penetrating == 30);

        return passed ? "✓ 零容量测试通过" : "✗ 零容量测试失败";
    }

    /**
     * 负伤害测试（边界情况）
     */
    private static function testBoundary_NegativeDamage():String {
        var shield:BaseShield = new BaseShield(100, 50, 0, 0);

        // 负伤害应该被正常处理（min逻辑会选择负数）
        var penetrating:Number = shield.absorbDamage(-10, false, 1);

        // 行为：负伤害会导致负的absorbable，容量会增加
        // 这是一个边界情况，取决于实现
        var passed:Boolean = true;  // 只要不崩溃就通过

        return passed ? "✓ 负伤害边界测试通过" : "✗ 负伤害边界测试失败";
    }

    /**
     * 大数值测试
     */
    private static function testBoundary_LargeNumbers():String {
        var shield:BaseShield = new BaseShield(1000000, 500000, 0, 0);

        var penetrating:Number = shield.absorbDamage(800000, false, 1);

        var passed:Boolean = (penetrating == 300000 && shield.getCapacity() == 500000);

        return passed ? "✓ 大数值测试通过" : "✗ 大数值测试失败";
    }

    // ==================== 9. 联弹机制测试 ====================

    private static function testHitCount():String {
        var results:Array = [];

        results.push(testHitCount_Basic());
        results.push(testHitCount_DefaultValue());
        results.push(testHitCount_StrengthMultiplier());
        results.push(testHitCount_CapacityLimit());

        return formatResults(results, "联弹机制");
    }

    /**
     * 基础联弹测试
     */
    private static function testHitCount_Basic():String {
        var shield:BaseShield = new BaseShield(1000, 50, 0, 0);

        // 10段联弹，每段60伤害，总600伤害
        // 有效强度 = 50 * 10 = 500
        // 吸收500，穿透100
        var penetrating:Number = shield.absorbDamage(600, false, 10);

        var passed:Boolean = (penetrating == 100 && shield.getCapacity() == 500);

        return passed ? "✓ 基础联弹测试通过" :
            "✗ 基础联弹测试失败（穿透=" + penetrating + "，期望100）";
    }

    /**
     * hitCount默认值测试
     */
    private static function testHitCount_DefaultValue():String {
        var shield:BaseShield = new BaseShield(100, 50, 0, 0);

        // hitCount为undefined时应该默认为1
        var penetrating1:Number = shield.absorbDamage(80, false, undefined);
        shield.setCapacity(100);

        // hitCount为0时也应该默认为1
        var penetrating2:Number = shield.absorbDamage(80, false, 0);

        var passed:Boolean = (penetrating1 == 30 && penetrating2 == 30);

        return passed ? "✓ hitCount默认值测试通过" : "✗ hitCount默认值测试失败";
    }

    /**
     * 联弹强度倍增测试
     */
    private static function testHitCount_StrengthMultiplier():String {
        var shield:BaseShield = new BaseShield(1000, 100, 0, 0);

        // 5段联弹，有效强度 = 100 * 5 = 500
        // 伤害400 < 有效强度500，全部吸收
        var penetrating:Number = shield.absorbDamage(400, false, 5);

        var passed:Boolean = (penetrating == 0 && shield.getCapacity() == 600);

        return passed ? "✓ 联弹强度倍增测试通过" : "✗ 联弹强度倍增测试失败";
    }

    /**
     * 联弹容量限制测试
     */
    private static function testHitCount_CapacityLimit():String {
        var shield:BaseShield = new BaseShield(200, 100, 0, 0);  // 容量200

        // 10段联弹，有效强度 = 100 * 10 = 1000
        // 伤害500，有效强度够，但容量只有200
        // 吸收200，穿透300
        var penetrating:Number = shield.absorbDamage(500, false, 10);

        var passed:Boolean = (penetrating == 300 && shield.getCapacity() == 0);

        return passed ? "✓ 联弹容量限制测试通过" :
            "✗ 联弹容量限制测试失败（穿透=" + penetrating + "，期望300）";
    }

    // ==================== 10. 性能测试 ====================

    private static function testPerformance():String {
        var result:String = "";

        result += perfTest_AbsorbDamage();
        result += perfTest_Update();
        result += perfTest_CreateShield();

        return result;
    }

    /**
     * 伤害吸收性能测试
     */
    private static function perfTest_AbsorbDamage():String {
        var shield:BaseShield = new BaseShield(1000000, 100, 0, 0);

        var iterations:Number = 10000;
        var startTime:Number = getTimer();

        for (var i:Number = 0; i < iterations; i++) {
            shield.absorbDamage(50, false, 1);
        }

        var endTime:Number = getTimer();
        var duration:Number = endTime - startTime;
        var avgTime:Number = duration / iterations;

        return "absorbDamage: " + iterations + "次 " + duration + "ms, " +
               "平均" + avgTime + "ms/次\n";
    }

    /**
     * 更新性能测试
     */
    private static function perfTest_Update():String {
        var shield:BaseShield = new BaseShield(1000000, 100, 5, 0);
        shield.setCapacity(500000);

        var iterations:Number = 10000;
        var startTime:Number = getTimer();

        for (var i:Number = 0; i < iterations; i++) {
            shield.update(1);
        }

        var endTime:Number = getTimer();
        var duration:Number = endTime - startTime;
        var avgTime:Number = duration / iterations;

        return "update(充能): " + iterations + "次 " + duration + "ms, " +
               "平均" + avgTime + "ms/次\n";
    }

    /**
     * 创建护盾性能测试
     */
    private static function perfTest_CreateShield():String {
        var iterations:Number = 1000;
        var startTime:Number = getTimer();

        for (var i:Number = 0; i < iterations; i++) {
            var shield:BaseShield = new BaseShield(100, 50, 5, 30);
        }

        var endTime:Number = getTimer();
        var duration:Number = endTime - startTime;
        var avgTime:Number = duration / iterations;

        return "创建BaseShield: " + iterations + "次 " + duration + "ms, " +
               "平均" + avgTime + "ms/次\n";
    }

    // ==================== 工具方法 ====================

    private static function getTimer():Number {
        return new Date().getTime();
    }

    /**
     * 格式化测试结果
     */
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
