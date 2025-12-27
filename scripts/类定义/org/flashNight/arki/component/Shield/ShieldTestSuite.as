/**
 * ShieldTestSuite - 具体护盾实现测试套件
 *
 * 集中管理 Shield 类的所有测试用例
 * 覆盖工厂方法、临时盾、持续时间、过期机制等扩展功能
 *
 * @author Crazyfs
 * @version 1.0
 */
import org.flashNight.arki.component.Shield.*;

class org.flashNight.arki.component.Shield.ShieldTestSuite {

    // ==================== 公共入口 ====================

    /**
     * 运行完整测试套件
     * @return 测试报告字符串
     */
    public static function runAllTests():String {
        var report:String = "\n";
        report += "========================================\n";
        report += "    Shield 测试套件 v1.0\n";
        report += "========================================\n\n";

        var startTime:Number = getTimer();

        // 1. 构造函数测试
        report += "【1. 构造函数测试】\n";
        report += testConstructor();
        report += "\n";

        // 2. 工厂方法测试
        report += "【2. 工厂方法测试】\n";
        report += testFactoryMethods();
        report += "\n";

        // 3. 临时盾机制测试
        report += "【3. 临时盾机制测试】\n";
        report += testTemporaryShield();
        report += "\n";

        // 4. 持续时间测试
        report += "【4. 持续时间测试】\n";
        report += testDuration();
        report += "\n";

        // 5. 过期机制测试
        report += "【5. 过期机制测试】\n";
        report += testExpiration();
        report += "\n";

        // 6. 回调注册测试
        report += "【6. 回调注册测试】\n";
        report += testCallbackRegistration();
        report += "\n";

        // 7. 继承行为测试
        report += "【7. 继承行为测试】\n";
        report += testInheritedBehavior();
        report += "\n";

        // 8. 衰减盾测试
        report += "【8. 衰减盾测试】\n";
        report += testDecayingShield();
        report += "\n";

        // 9. 抗真伤盾测试
        report += "【9. 抗真伤盾测试】\n";
        report += testResistantShield();
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
        for (var i:Number = 0; i < lines.length; i++) {
            if (lines[i].length > 0) {
                _root.服务器.发布服务器消息(lines[i]);
            }
        }
    }

    // ==================== 1. 构造函数测试 ====================

    private static function testConstructor():String {
        var results:Array = [];

        results.push(testConstructor_Basic());
        results.push(testConstructor_DefaultValues());
        results.push(testConstructor_NameAndType());

        return formatResults(results, "构造函数");
    }

    /**
     * 基础构造测试
     */
    private static function testConstructor_Basic():String {
        var shield:Shield = new Shield(100, 50, 5, 30, "测试盾", "能量盾");

        var passed:Boolean = (
            shield.getMaxCapacity() == 100 &&
            shield.getStrength() == 50 &&
            shield.getRechargeRate() == 5 &&
            shield.getRechargeDelay() == 30 &&
            shield.getName() == "测试盾" &&
            shield.getType() == "能量盾"
        );

        return passed ? "✓ 基础构造测试通过" : "✗ 基础构造测试失败";
    }

    /**
     * 默认值测试
     */
    private static function testConstructor_DefaultValues():String {
        var shield:Shield = new Shield(100, 50, 0, 0, undefined, undefined);

        var passed:Boolean = (
            shield.getName() == "Shield" &&
            shield.getType() == "default" &&
            shield.isTemporary() == false &&
            shield.getDuration() == -1
        );

        return passed ? "✓ 默认值测试通过" : "✗ 默认值测试失败";
    }

    /**
     * 名称和类型测试
     */
    private static function testConstructor_NameAndType():String {
        var shield:Shield = new Shield(100, 50, 0, 0, "我的护盾", "物理盾");

        shield.setName("新名称");
        shield.setType("魔法盾");

        var passed:Boolean = (
            shield.getName() == "新名称" &&
            shield.getType() == "魔法盾"
        );

        return passed ? "✓ 名称和类型测试通过" : "✗ 名称和类型测试失败";
    }

    // ==================== 2. 工厂方法测试 ====================

    private static function testFactoryMethods():String {
        var results:Array = [];

        results.push(testFactory_CreateTemporary());
        results.push(testFactory_CreateRechargeable());
        results.push(testFactory_CreateDecaying());
        results.push(testFactory_CreateResistant());

        return formatResults(results, "工厂方法");
    }

    /**
     * 创建临时护盾测试
     */
    private static function testFactory_CreateTemporary():String {
        var shield:Shield = Shield.createTemporary(100, 50, 300, "临时盾");

        var passed:Boolean = (
            shield.getMaxCapacity() == 100 &&
            shield.getStrength() == 50 &&
            shield.getDuration() == 300 &&
            shield.isTemporary() == true &&
            shield.getType() == "temporary" &&
            shield.getRechargeRate() == 0
        );

        return passed ? "✓ createTemporary测试通过" : "✗ createTemporary测试失败";
    }

    /**
     * 创建可充能护盾测试
     */
    private static function testFactory_CreateRechargeable():String {
        var shield:Shield = Shield.createRechargeable(200, 80, 5, 60, "充能盾");

        var passed:Boolean = (
            shield.getMaxCapacity() == 200 &&
            shield.getStrength() == 80 &&
            shield.getRechargeRate() == 5 &&
            shield.getRechargeDelay() == 60 &&
            shield.isTemporary() == false &&
            shield.getType() == "rechargeable"
        );

        return passed ? "✓ createRechargeable测试通过" : "✗ createRechargeable测试失败";
    }

    /**
     * 创建衰减护盾测试
     */
    private static function testFactory_CreateDecaying():String {
        var shield:Shield = Shield.createDecaying(150, 60, 3, "衰减盾");

        var passed:Boolean = (
            shield.getMaxCapacity() == 150 &&
            shield.getStrength() == 60 &&
            shield.getRechargeRate() == -3 &&  // 负值表示衰减
            shield.isTemporary() == true &&
            shield.getType() == "decaying"
        );

        return passed ? "✓ createDecaying测试通过" : "✗ createDecaying测试失败";
    }

    /**
     * 创建抗真伤护盾测试
     */
    private static function testFactory_CreateResistant():String {
        var shield:Shield = Shield.createResistant(100, 50, 200, "抗真伤盾");

        var passed:Boolean = (
            shield.getMaxCapacity() == 100 &&
            shield.getStrength() == 50 &&
            shield.getDuration() == 200 &&
            shield.getResistBypass() == true &&
            shield.isTemporary() == true &&
            shield.getType() == "resistant"
        );

        return passed ? "✓ createResistant测试通过" : "✗ createResistant测试失败";
    }

    // ==================== 3. 临时盾机制测试 ====================

    private static function testTemporaryShield():String {
        var results:Array = [];

        results.push(testTemporary_BreakDeactivates());
        results.push(testTemporary_PermanentShieldRemains());
        results.push(testTemporary_SetTemporary());

        return formatResults(results, "临时盾机制");
    }

    /**
     * 临时盾击碎后失活测试
     */
    private static function testTemporary_BreakDeactivates():String {
        var shield:Shield = Shield.createTemporary(50, 100, -1, "临时盾");

        // 造成超过容量的伤害
        shield.absorbDamage(100, false, 1);

        var passed:Boolean = (shield.isActive() == false && shield.isEmpty());

        return passed ? "✓ 临时盾击碎后失活测试通过" : "✗ 临时盾击碎后失活测试失败";
    }

    /**
     * 永久盾击碎后保持活跃测试
     */
    private static function testTemporary_PermanentShieldRemains():String {
        var shield:Shield = Shield.createRechargeable(50, 100, 5, 0, "永久盾");

        // 造成超过容量的伤害
        shield.absorbDamage(100, false, 1);

        // 永久盾击碎后仍然激活（可以继续充能）
        var passed:Boolean = (shield.isActive() == true && shield.isEmpty());

        return passed ? "✓ 永久盾击碎后保持活跃测试通过" : "✗ 永久盾击碎后保持活跃测试失败";
    }

    /**
     * 设置临时属性测试
     */
    private static function testTemporary_SetTemporary():String {
        var shield:Shield = new Shield(100, 50, 0, 0, "测试", "default");

        shield.setTemporary(true);
        var temp1:Boolean = shield.isTemporary();

        shield.setTemporary(false);
        var temp2:Boolean = shield.isTemporary();

        var passed:Boolean = (temp1 == true && temp2 == false);

        return passed ? "✓ 设置临时属性测试通过" : "✗ 设置临时属性测试失败";
    }

    // ==================== 4. 持续时间测试 ====================

    private static function testDuration():String {
        var results:Array = [];

        results.push(testDuration_Countdown());
        results.push(testDuration_PermanentNegativeOne());
        results.push(testDuration_SetDuration());

        return formatResults(results, "持续时间");
    }

    /**
     * 持续时间倒计时测试
     */
    private static function testDuration_Countdown():String {
        var shield:Shield = Shield.createTemporary(100, 50, 100, "倒计时盾");

        // 更新50帧
        for (var i:Number = 0; i < 50; i++) {
            shield.update(1);
        }

        var passed:Boolean = (shield.getDuration() == 50 && shield.isActive());

        return passed ? "✓ 持续时间倒计时测试通过" :
            "✗ 持续时间倒计时测试失败（duration=" + shield.getDuration() + "）";
    }

    /**
     * 永久盾duration=-1测试
     */
    private static function testDuration_PermanentNegativeOne():String {
        var shield:Shield = Shield.createTemporary(100, 50, -1, "永久临时盾");

        // 更新1000帧
        for (var i:Number = 0; i < 1000; i++) {
            shield.update(1);
        }

        // duration=-1 表示永久，不会过期
        var passed:Boolean = (shield.getDuration() == -1 && shield.isActive());

        return passed ? "✓ 永久盾duration=-1测试通过" : "✗ 永久盾duration=-1测试失败";
    }

    /**
     * 设置持续时间测试
     */
    private static function testDuration_SetDuration():String {
        var shield:Shield = Shield.createTemporary(100, 50, 100, "测试盾");

        shield.setDuration(200);

        var passed:Boolean = (shield.getDuration() == 200);

        return passed ? "✓ 设置持续时间测试通过" : "✗ 设置持续时间测试失败";
    }

    // ==================== 5. 过期机制测试 ====================

    private static function testExpiration():String {
        var results:Array = [];

        results.push(testExpiration_AutoDeactivate());
        results.push(testExpiration_Callback());
        results.push(testExpiration_UpdateReturnValue());

        return formatResults(results, "过期机制");
    }

    /**
     * 过期自动失活测试
     */
    private static function testExpiration_AutoDeactivate():String {
        var shield:Shield = Shield.createTemporary(100, 50, 30, "短期盾");

        // 更新40帧，超过持续时间
        for (var i:Number = 0; i < 40; i++) {
            shield.update(1);
        }

        var passed:Boolean = (shield.isActive() == false && shield.getDuration() == 0);

        return passed ? "✓ 过期自动失活测试通过" : "✗ 过期自动失活测试失败";
    }

    /**
     * 过期回调测试
     */
    private static function testExpiration_Callback():String {
        var shield:Shield = Shield.createTemporary(100, 50, 20, "回调测试盾");
        var expireCalled:Boolean = false;

        shield.onExpireCallback = function(s:IShield):Void {
            expireCalled = true;
        };

        // 更新25帧，触发过期
        for (var i:Number = 0; i < 25; i++) {
            shield.update(1);
        }

        var passed:Boolean = (expireCalled == true);

        return passed ? "✓ 过期回调测试通过" : "✗ 过期回调测试失败";
    }

    /**
     * 过期时update返回值测试
     */
    private static function testExpiration_UpdateReturnValue():String {
        var shield:Shield = Shield.createTemporary(100, 50, 5, "测试盾");

        var results:Array = [];
        for (var i:Number = 0; i < 10; i++) {
            results.push(shield.update(1));
        }

        // 第5帧应该返回true（过期导致状态变化）
        // 之后返回false（已失活）
        var passed:Boolean = (results[4] == true && results[5] == false);

        return passed ? "✓ 过期时update返回值测试通过" : "✗ 过期时update返回值测试失败";
    }

    // ==================== 6. 回调注册测试 ====================

    private static function testCallbackRegistration():String {
        var results:Array = [];

        results.push(testCallbacks_SetCallbacks());
        results.push(testCallbacks_ChainCall());
        results.push(testCallbacks_PartialSet());

        return formatResults(results, "回调注册");
    }

    /**
     * setCallbacks批量注册测试
     */
    private static function testCallbacks_SetCallbacks():String {
        var shield:Shield = new Shield(100, 50, 5, 10, "测试", "default");
        shield.setCapacity(50);

        var hitCalled:Boolean = false;
        var breakCalled:Boolean = false;
        var rechargeStartCalled:Boolean = false;
        var rechargeFullCalled:Boolean = false;
        var expireCalled:Boolean = false;

        shield.setCallbacks({
            onHit: function(s, a) { hitCalled = true; },
            onBreak: function(s) { breakCalled = true; },
            onRechargeStart: function(s) { rechargeStartCalled = true; },
            onRechargeFull: function(s) { rechargeFullCalled = true; },
            onExpire: function(s) { expireCalled = true; }
        });

        // 触发onHit
        shield.absorbDamage(10, false, 1);

        // 触发onRechargeStart
        shield.onHit(5);
        for (var i:Number = 0; i < 15; i++) {
            shield.update(1);
        }

        var passed:Boolean = (hitCalled && rechargeStartCalled);

        return passed ? "✓ setCallbacks批量注册测试通过" : "✗ setCallbacks批量注册测试失败";
    }

    /**
     * 链式调用测试
     */
    private static function testCallbacks_ChainCall():String {
        var shield:Shield = new Shield(100, 50, 0, 0, "测试", "default");

        var result:Shield = shield.setCallbacks({
            onHit: function(s, a) {}
        });

        var passed:Boolean = (result === shield);

        return passed ? "✓ 链式调用测试通过" : "✗ 链式调用测试失败";
    }

    /**
     * 部分设置测试
     */
    private static function testCallbacks_PartialSet():String {
        var shield:Shield = new Shield(100, 50, 0, 0, "测试", "default");
        var hitCalled:Boolean = false;

        // 只设置onHit
        shield.setCallbacks({
            onHit: function(s, a) { hitCalled = true; }
        });

        shield.absorbDamage(10, false, 1);

        // 其他回调应该是null
        var passed:Boolean = (
            hitCalled == true &&
            shield.onBreakCallback == null
        );

        return passed ? "✓ 部分设置测试通过" : "✗ 部分设置测试失败";
    }

    // ==================== 7. 继承行为测试 ====================

    private static function testInheritedBehavior():String {
        var results:Array = [];

        results.push(testInherited_AbsorbDamage());
        results.push(testInherited_ConsumeCapacity());
        results.push(testInherited_GettersSetters());
        results.push(testInherited_SortPriority());

        return formatResults(results, "继承行为");
    }

    /**
     * 继承的伤害吸收测试
     */
    private static function testInherited_AbsorbDamage():String {
        var shield:Shield = new Shield(100, 50, 0, 0, "测试", "default");

        var penetrating:Number = shield.absorbDamage(80, false, 1);

        var passed:Boolean = (penetrating == 30 && shield.getCapacity() == 50);

        return passed ? "✓ 继承的伤害吸收测试通过" : "✗ 继承的伤害吸收测试失败";
    }

    /**
     * 继承的容量消耗测试
     */
    private static function testInherited_ConsumeCapacity():String {
        var shield:Shield = new Shield(100, 50, 0, 0, "测试", "default");

        var consumed:Number = shield.consumeCapacity(30);

        var passed:Boolean = (consumed == 30 && shield.getCapacity() == 70);

        return passed ? "✓ 继承的容量消耗测试通过" : "✗ 继承的容量消耗测试失败";
    }

    /**
     * 继承的属性访问器测试
     */
    private static function testInherited_GettersSetters():String {
        var shield:Shield = new Shield(100, 50, 5, 30, "测试", "default");

        // 测试从BaseShield继承的方法
        shield.setCapacity(60);
        shield.setStrength(80);
        shield.setRechargeRate(10);

        var passed:Boolean = (
            shield.getCapacity() == 60 &&
            shield.getStrength() == 80 &&
            shield.getRechargeRate() == 10 &&
            shield.getId() >= 0
        );

        return passed ? "✓ 继承的属性访问器测试通过" : "✗ 继承的属性访问器测试失败";
    }

    /**
     * 继承的排序优先级测试
     */
    private static function testInherited_SortPriority():String {
        var shield1:Shield = new Shield(100, 100, 0, 0, "高强度", "default");
        var shield2:Shield = new Shield(100, 50, 0, 0, "低强度", "default");

        // 高强度应该有更高的优先级
        var passed:Boolean = (shield1.getSortPriority() > shield2.getSortPriority());

        return passed ? "✓ 继承的排序优先级测试通过" : "✗ 继承的排序优先级测试失败";
    }

    // ==================== 8. 衰减盾测试 ====================

    private static function testDecayingShield():String {
        var results:Array = [];

        results.push(testDecaying_BasicDecay());
        results.push(testDecaying_BreakOnZero());
        results.push(testDecaying_NoDelayEffect());

        return formatResults(results, "衰减盾");
    }

    /**
     * 基础衰减测试
     */
    private static function testDecaying_BasicDecay():String {
        var shield:Shield = Shield.createDecaying(100, 50, 5, "衰减盾");

        // 更新10帧
        for (var i:Number = 0; i < 10; i++) {
            shield.update(1);
        }

        // 100 - 5*10 = 50
        var passed:Boolean = (shield.getCapacity() == 50);

        return passed ? "✓ 基础衰减测试通过" :
            "✗ 基础衰减测试失败（容量=" + shield.getCapacity() + "）";
    }

    /**
     * 衰减至零后触发break测试
     */
    private static function testDecaying_BreakOnZero():String {
        var shield:Shield = Shield.createDecaying(50, 50, 10, "衰减盾");
        var breakCalled:Boolean = false;

        shield.onBreakCallback = function(s:IShield):Void {
            breakCalled = true;
        };

        // 更新10帧，应该衰减到0
        for (var i:Number = 0; i < 10; i++) {
            shield.update(1);
        }

        var passed:Boolean = (breakCalled && shield.isEmpty() && !shield.isActive());

        return passed ? "✓ 衰减至零后触发break测试通过" : "✗ 衰减至零后触发break测试失败";
    }

    /**
     * 衰减不受命中延迟影响测试
     */
    private static function testDecaying_NoDelayEffect():String {
        // 创建衰减盾（createDecaying内部会设置负的rechargeRate）
        var shield:Shield = Shield.createDecaying(100, 50, 5, "衰减盾");

        // 即使触发命中，衰减也不受影响
        shield.onHit(10);

        // 更新10帧
        for (var i:Number = 0; i < 10; i++) {
            shield.update(1);
        }

        // 衰减正常进行
        var passed:Boolean = (shield.getCapacity() == 50);

        return passed ? "✓ 衰减不受命中延迟影响测试通过" : "✗ 衰减不受命中延迟影响测试失败";
    }

    // ==================== 9. 抗真伤盾测试 ====================

    private static function testResistantShield():String {
        var results:Array = [];

        results.push(testResistant_BlocksBypass());
        results.push(testResistant_NormalDamage());
        results.push(testResistant_WithDuration());

        return formatResults(results, "抗真伤盾");
    }

    /**
     * 抵抗绕过测试
     */
    private static function testResistant_BlocksBypass():String {
        var shield:Shield = Shield.createResistant(100, 50, -1, "抗真伤盾");

        // 真伤（bypassShield=true）应该被正常吸收
        var penetrating:Number = shield.absorbDamage(30, true, 1);

        var passed:Boolean = (penetrating == 0 && shield.getCapacity() == 70);

        return passed ? "✓ 抵抗绕过测试通过" : "✗ 抵抗绕过测试失败";
    }

    /**
     * 普通伤害测试
     */
    private static function testResistant_NormalDamage():String {
        var shield:Shield = Shield.createResistant(100, 50, -1, "抗真伤盾");

        // 普通伤害也正常吸收
        var penetrating:Number = shield.absorbDamage(80, false, 1);

        var passed:Boolean = (penetrating == 30 && shield.getCapacity() == 50);

        return passed ? "✓ 普通伤害测试通过" : "✗ 普通伤害测试失败";
    }

    /**
     * 带持续时间的抗真伤盾测试
     */
    private static function testResistant_WithDuration():String {
        var shield:Shield = Shield.createResistant(100, 50, 50, "限时抗真伤盾");

        // 更新60帧，应该过期
        for (var i:Number = 0; i < 60; i++) {
            shield.update(1);
        }

        var passed:Boolean = (!shield.isActive() && shield.getDuration() == 0);

        return passed ? "✓ 带持续时间的抗真伤盾测试通过" : "✗ 带持续时间的抗真伤盾测试失败";
    }

    // ==================== 10. 性能测试 ====================

    private static function testPerformance():String {
        var result:String = "";

        result += perfTest_FactoryMethods();
        result += perfTest_UpdateWithDuration();
        result += perfTest_FullLifecycle();

        return result;
    }

    /**
     * 工厂方法性能测试
     */
    private static function perfTest_FactoryMethods():String {
        var iterations:Number = 1000;
        var startTime:Number = getTimer();

        for (var i:Number = 0; i < iterations; i++) {
            Shield.createTemporary(100, 50, 300, "临时盾");
            Shield.createRechargeable(200, 80, 5, 60, "充能盾");
            Shield.createDecaying(150, 60, 3, "衰减盾");
            Shield.createResistant(100, 50, 200, "抗真伤盾");
        }

        var endTime:Number = getTimer();
        var duration:Number = endTime - startTime;
        var avgTime:Number = duration / (iterations * 4);

        return "工厂方法创建: " + (iterations * 4) + "次 " + duration + "ms, " +
               "平均" + avgTime + "ms/次\n";
    }

    /**
     * 带持续时间的update性能测试
     */
    private static function perfTest_UpdateWithDuration():String {
        var shield:Shield = Shield.createTemporary(100, 50, 100000, "测试盾");

        var iterations:Number = 10000;
        var startTime:Number = getTimer();

        for (var i:Number = 0; i < iterations; i++) {
            shield.update(1);
        }

        var endTime:Number = getTimer();
        var duration:Number = endTime - startTime;
        var avgTime:Number = duration / iterations;

        return "update(带duration): " + iterations + "次 " + duration + "ms, " +
               "平均" + avgTime + "ms/次\n";
    }

    /**
     * 完整生命周期性能测试
     */
    private static function perfTest_FullLifecycle():String {
        var iterations:Number = 1000;
        var startTime:Number = getTimer();

        for (var i:Number = 0; i < iterations; i++) {
            var shield:Shield = Shield.createTemporary(100, 50, 50, "生命周期测试");

            // 模拟完整生命周期
            shield.absorbDamage(30, false, 1);
            shield.update(1);
            shield.absorbDamage(20, false, 1);

            for (var j:Number = 0; j < 50; j++) {
                shield.update(1);
            }
        }

        var endTime:Number = getTimer();
        var duration:Number = endTime - startTime;
        var avgTime:Number = duration / iterations;

        return "完整生命周期: " + iterations + "次 " + duration + "ms, " +
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
