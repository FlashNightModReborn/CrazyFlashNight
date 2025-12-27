/**
 * ShieldStackTestSuite - 护盾栈测试套件
 *
 * 集中管理 ShieldStack 类的所有测试用例
 * 覆盖护盾管理、伤害分发、缓存机制、排序、嵌套等功能
 *
 * @author Crazyfs
 * @version 1.0
 */
import org.flashNight.arki.component.Shield.*;

class org.flashNight.arki.component.Shield.ShieldStackTestSuite {

    // ==================== 公共入口 ====================

    /**
     * 运行完整测试套件
     * @return 测试报告字符串
     */
    public static function runAllTests():String {
        var report:String = "\n";
        report += "========================================\n";
        report += "    ShieldStack 测试套件 v1.0\n";
        report += "========================================\n\n";

        var startTime:Number = getTimer();

        // 1. 护盾管理测试
        report += "【1. 护盾管理测试】\n";
        report += testShieldManagement();
        report += "\n";

        // 2. 伤害吸收测试
        report += "【2. 伤害吸收测试】\n";
        report += testAbsorbDamage();
        report += "\n";

        // 3. 容量消耗测试
        report += "【3. 容量消耗测试】\n";
        report += testConsumeCapacity();
        report += "\n";

        // 4. 排序机制测试
        report += "【4. 排序机制测试】\n";
        report += testSorting();
        report += "\n";

        // 5. 缓存机制测试
        report += "【5. 缓存机制测试】\n";
        report += testCaching();
        report += "\n";

        // 6. 联弹机制测试
        report += "【6. 联弹机制测试】\n";
        report += testHitCount();
        report += "\n";

        // 7. 抵抗绕过测试
        report += "【7. 抵抗绕过测试】\n";
        report += testResistBypass();
        report += "\n";

        // 8. 更新与弹出测试
        report += "【8. 更新与弹出测试】\n";
        report += testUpdateAndEjection();
        report += "\n";

        // 9. 嵌套护盾栈测试
        report += "【9. 嵌套护盾栈测试】\n";
        report += testNestedStack();
        report += "\n";

        // 10. 回调测试
        report += "【10. 回调测试】\n";
        report += testCallbacks();
        report += "\n";

        // 11. 边界条件测试
        report += "【11. 边界条件测试】\n";
        report += testBoundaryConditions();
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
        for (var i:Number = 0; i < lines.length; i++) {
            if (lines[i].length > 0) {
                _root.服务器.发布服务器消息(lines[i]);
            }
        }
    }

    // ==================== 1. 护盾管理测试 ====================

    private static function testShieldManagement():String {
        var results:Array = [];

        results.push(testManagement_AddShield());
        results.push(testManagement_RemoveShield());
        results.push(testManagement_RemoveById());
        results.push(testManagement_GetShields());
        results.push(testManagement_Clear());
        results.push(testManagement_RejectInactive());

        return formatResults(results, "护盾管理");
    }

    /**
     * 添加护盾测试
     */
    private static function testManagement_AddShield():String {
        var stack:ShieldStack = new ShieldStack();
        var shield1:Shield = Shield.createTemporary(100, 50, -1, "盾1");
        var shield2:Shield = Shield.createTemporary(200, 80, -1, "盾2");

        var add1:Boolean = stack.addShield(shield1);
        var add2:Boolean = stack.addShield(shield2);

        var passed:Boolean = (add1 && add2 && stack.getShieldCount() == 2);

        return passed ? "✓ 添加护盾测试通过" : "✗ 添加护盾测试失败";
    }

    /**
     * 移除护盾测试
     */
    private static function testManagement_RemoveShield():String {
        var stack:ShieldStack = new ShieldStack();
        var shield1:Shield = Shield.createTemporary(100, 50, -1, "盾1");
        var shield2:Shield = Shield.createTemporary(200, 80, -1, "盾2");

        stack.addShield(shield1);
        stack.addShield(shield2);

        var removed:Boolean = stack.removeShield(shield1);

        var passed:Boolean = (removed && stack.getShieldCount() == 1);

        return passed ? "✓ 移除护盾测试通过" : "✗ 移除护盾测试失败";
    }

    /**
     * 按ID移除护盾测试
     */
    private static function testManagement_RemoveById():String {
        var stack:ShieldStack = new ShieldStack();
        var shield1:Shield = Shield.createTemporary(100, 50, -1, "盾1");
        var shield2:Shield = Shield.createTemporary(200, 80, -1, "盾2");

        stack.addShield(shield1);
        stack.addShield(shield2);

        var id:Number = shield1.getId();
        var removed:Boolean = stack.removeShieldById(id);

        var passed:Boolean = (removed && stack.getShieldCount() == 1);

        return passed ? "✓ 按ID移除护盾测试通过" : "✗ 按ID移除护盾测试失败";
    }

    /**
     * 获取护盾列表测试
     */
    private static function testManagement_GetShields():String {
        var stack:ShieldStack = new ShieldStack();
        var shield1:Shield = Shield.createTemporary(100, 50, -1, "盾1");
        var shield2:Shield = Shield.createTemporary(200, 80, -1, "盾2");

        stack.addShield(shield1);
        stack.addShield(shield2);

        var shields:Array = stack.getShields();

        // 返回的应该是副本
        shields.pop();

        var passed:Boolean = (stack.getShieldCount() == 2);

        return passed ? "✓ 获取护盾列表测试通过" : "✗ 获取护盾列表测试失败";
    }

    /**
     * 清空护盾测试
     */
    private static function testManagement_Clear():String {
        var stack:ShieldStack = new ShieldStack();
        stack.addShield(Shield.createTemporary(100, 50, -1, "盾1"));
        stack.addShield(Shield.createTemporary(200, 80, -1, "盾2"));

        stack.clear();

        var passed:Boolean = (stack.getShieldCount() == 0);

        return passed ? "✓ 清空护盾测试通过" : "✗ 清空护盾测试失败";
    }

    /**
     * 拒绝未激活护盾测试
     */
    private static function testManagement_RejectInactive():String {
        var stack:ShieldStack = new ShieldStack();
        var shield:Shield = Shield.createTemporary(100, 50, -1, "盾");
        shield.setActive(false);

        var added:Boolean = stack.addShield(shield);

        var passed:Boolean = (!added && stack.getShieldCount() == 0);

        return passed ? "✓ 拒绝未激活护盾测试通过" : "✗ 拒绝未激活护盾测试失败";
    }

    // ==================== 2. 伤害吸收测试 ====================

    private static function testAbsorbDamage():String {
        var results:Array = [];

        results.push(testAbsorb_SingleShield());
        results.push(testAbsorb_MultipleShields());
        results.push(testAbsorb_StrengthLimit());
        results.push(testAbsorb_CapacityLimit());
        results.push(testAbsorb_EmptyStack());
        results.push(testAbsorb_InactiveStack());

        return formatResults(results, "伤害吸收");
    }

    /**
     * 单护盾吸收测试
     */
    private static function testAbsorb_SingleShield():String {
        var stack:ShieldStack = new ShieldStack();
        stack.addShield(Shield.createTemporary(100, 50, -1, "盾"));

        var penetrating:Number = stack.absorbDamage(30, false, 1);

        var passed:Boolean = (penetrating == 0 && stack.getCapacity() == 70);

        return passed ? "✓ 单护盾吸收测试通过" :
            "✗ 单护盾吸收测试失败（穿透=" + penetrating + "）";
    }

    /**
     * 多护盾吸收测试
     */
    private static function testAbsorb_MultipleShields():String {
        var stack:ShieldStack = new ShieldStack();
        stack.addShield(Shield.createTemporary(50, 100, -1, "外层盾"));
        stack.addShield(Shield.createTemporary(100, 80, -1, "内层盾"));

        // 外层盾强度100，容量50
        // 伤害80，强度允许，但容量只有50 -> 外层消耗50
        // 剩余30继续分配给内层 -> 内层消耗30
        var penetrating:Number = stack.absorbDamage(80, false, 1);

        var passed:Boolean = (penetrating == 0 && stack.getCapacity() == 70);

        return passed ? "✓ 多护盾吸收测试通过" :
            "✗ 多护盾吸收测试失败（穿透=" + penetrating + "，容量=" + stack.getCapacity() + "）";
    }

    /**
     * 强度限制测试
     */
    private static function testAbsorb_StrengthLimit():String {
        var stack:ShieldStack = new ShieldStack();
        stack.addShield(Shield.createTemporary(1000, 50, -1, "盾"));

        // 伤害100，强度50 -> 吸收50，穿透50
        var penetrating:Number = stack.absorbDamage(100, false, 1);

        var passed:Boolean = (penetrating == 50 && stack.getCapacity() == 950);

        return passed ? "✓ 强度限制测试通过" :
            "✗ 强度限制测试失败（穿透=" + penetrating + "，期望50）";
    }

    /**
     * 容量限制测试
     */
    private static function testAbsorb_CapacityLimit():String {
        var stack:ShieldStack = new ShieldStack();
        stack.addShield(Shield.createTemporary(30, 100, -1, "盾"));

        // 伤害50，强度100，但容量只有30 -> 吸收30，穿透20
        var penetrating:Number = stack.absorbDamage(50, false, 1);

        var passed:Boolean = (penetrating == 20 && stack.getCapacity() == 0);

        return passed ? "✓ 容量限制测试通过" :
            "✗ 容量限制测试失败（穿透=" + penetrating + "，期望20）";
    }

    /**
     * 空栈吸收测试
     */
    private static function testAbsorb_EmptyStack():String {
        var stack:ShieldStack = new ShieldStack();

        var penetrating:Number = stack.absorbDamage(100, false, 1);

        var passed:Boolean = (penetrating == 100);

        return passed ? "✓ 空栈吸收测试通过" : "✗ 空栈吸收测试失败";
    }

    /**
     * 未激活栈吸收测试
     */
    private static function testAbsorb_InactiveStack():String {
        var stack:ShieldStack = new ShieldStack();
        stack.addShield(Shield.createTemporary(100, 50, -1, "盾"));
        stack.setActive(false);

        var penetrating:Number = stack.absorbDamage(30, false, 1);

        var passed:Boolean = (penetrating == 30);

        return passed ? "✓ 未激活栈吸收测试通过" : "✗ 未激活栈吸收测试失败";
    }

    // ==================== 3. 容量消耗测试 ====================

    private static function testConsumeCapacity():String {
        var results:Array = [];

        results.push(testConsume_Basic());
        results.push(testConsume_MultipleShields());
        results.push(testConsume_OverCapacity());

        return formatResults(results, "容量消耗");
    }

    /**
     * 基础容量消耗测试
     */
    private static function testConsume_Basic():String {
        var stack:ShieldStack = new ShieldStack();
        stack.addShield(Shield.createTemporary(100, 50, -1, "盾"));

        var consumed:Number = stack.consumeCapacity(30);

        var passed:Boolean = (consumed == 30 && stack.getCapacity() == 70);

        return passed ? "✓ 基础容量消耗测试通过" : "✗ 基础容量消耗测试失败";
    }

    /**
     * 多护盾容量消耗测试
     */
    private static function testConsume_MultipleShields():String {
        var stack:ShieldStack = new ShieldStack();
        stack.addShield(Shield.createTemporary(30, 100, -1, "外层"));
        stack.addShield(Shield.createTemporary(50, 80, -1, "内层"));

        // 消耗50：外层30 + 内层20
        var consumed:Number = stack.consumeCapacity(50);

        var passed:Boolean = (consumed == 50 && stack.getCapacity() == 30);

        return passed ? "✓ 多护盾容量消耗测试通过" :
            "✗ 多护盾容量消耗测试失败（consumed=" + consumed + "）";
    }

    /**
     * 超量消耗测试
     */
    private static function testConsume_OverCapacity():String {
        var stack:ShieldStack = new ShieldStack();
        stack.addShield(Shield.createTemporary(50, 100, -1, "盾"));

        var consumed:Number = stack.consumeCapacity(100);

        var passed:Boolean = (consumed == 50 && stack.getCapacity() == 0);

        return passed ? "✓ 超量消耗测试通过" : "✗ 超量消耗测试失败";
    }

    // ==================== 4. 排序机制测试 ====================

    private static function testSorting():String {
        var results:Array = [];

        results.push(testSort_ByStrength());
        results.push(testSort_ByRechargeRate());
        results.push(testSort_StableOrder());

        return formatResults(results, "排序机制");
    }

    /**
     * 按强度排序测试
     */
    private static function testSort_ByStrength():String {
        var stack:ShieldStack = new ShieldStack();

        // 先添加低强度，再添加高强度
        stack.addShield(Shield.createTemporary(100, 30, -1, "低强度"));
        stack.addShield(Shield.createTemporary(100, 100, -1, "高强度"));
        stack.addShield(Shield.createTemporary(100, 60, -1, "中强度"));

        // 表观强度应该是最高的
        var strength:Number = stack.getStrength();

        var passed:Boolean = (strength == 100);

        return passed ? "✓ 按强度排序测试通过" :
            "✗ 按强度排序测试失败（强度=" + strength + "，期望100）";
    }

    /**
     * 同强度按充能速度排序测试
     */
    private static function testSort_ByRechargeRate():String {
        var stack:ShieldStack = new ShieldStack();

        // 同强度，不同充能速度
        var shield1:Shield = Shield.createRechargeable(100, 50, 10, 0, "高充能");
        var shield2:Shield = Shield.createRechargeable(100, 50, 0, 0, "无充能");
        var shield3:Shield = Shield.createRechargeable(100, 50, 5, 0, "低充能");

        stack.addShield(shield1);
        stack.addShield(shield2);
        stack.addShield(shield3);

        // 优先消耗充能慢的（无充能优先）
        stack.consumeCapacity(50);

        // 无充能的应该被优先消耗
        var passed:Boolean = (shield2.getCapacity() == 50);

        return passed ? "✓ 同强度按充能速度排序测试通过" : "✗ 同强度按充能速度排序测试失败";
    }

    /**
     * 稳定排序测试
     */
    private static function testSort_StableOrder():String {
        var stack:ShieldStack = new ShieldStack();

        // 添加多个相同属性的护盾
        var shield1:Shield = Shield.createTemporary(100, 50, -1, "盾1");
        var shield2:Shield = Shield.createTemporary(100, 50, -1, "盾2");
        var shield3:Shield = Shield.createTemporary(100, 50, -1, "盾3");

        stack.addShield(shield1);
        stack.addShield(shield2);
        stack.addShield(shield3);

        // 消耗一些容量触发排序
        stack.consumeCapacity(50);

        // ID小的应该优先（稳定排序）
        var passed:Boolean = (shield1.getCapacity() == 50);

        return passed ? "✓ 稳定排序测试通过" : "✗ 稳定排序测试失败";
    }

    // ==================== 5. 缓存机制测试 ====================

    private static function testCaching():String {
        var results:Array = [];

        results.push(testCache_Invalidation());
        results.push(testCache_UpdateDirty());
        results.push(testCache_AggregatedValues());

        return formatResults(results, "缓存机制");
    }

    /**
     * 缓存失效测试
     */
    private static function testCache_Invalidation():String {
        var stack:ShieldStack = new ShieldStack();
        stack.addShield(Shield.createTemporary(100, 50, -1, "盾1"));

        var strength1:Number = stack.getStrength();

        // 添加更强的护盾，缓存应该失效
        stack.addShield(Shield.createTemporary(100, 80, -1, "盾2"));

        var strength2:Number = stack.getStrength();

        var passed:Boolean = (strength1 == 50 && strength2 == 80);

        return passed ? "✓ 缓存失效测试通过" : "✗ 缓存失效测试失败";
    }

    /**
     * update后缓存脏标记测试
     */
    private static function testCache_UpdateDirty():String {
        var stack:ShieldStack = new ShieldStack();
        stack.addShield(Shield.createDecaying(100, 50, 5, "衰减盾"));

        var cap1:Number = stack.getCapacity();

        // update导致容量变化
        stack.update(1);

        var cap2:Number = stack.getCapacity();

        var passed:Boolean = (cap1 == 100 && cap2 == 95);

        return passed ? "✓ update后缓存脏标记测试通过" : "✗ update后缓存脏标记测试失败";
    }

    /**
     * 聚合值缓存测试
     */
    private static function testCache_AggregatedValues():String {
        var stack:ShieldStack = new ShieldStack();
        stack.addShield(Shield.createTemporary(100, 50, -1, "盾1"));
        stack.addShield(Shield.createTemporary(200, 80, -1, "盾2"));

        var capacity:Number = stack.getCapacity();
        var maxCapacity:Number = stack.getMaxCapacity();
        var targetCapacity:Number = stack.getTargetCapacity();

        var passed:Boolean = (
            capacity == 300 &&
            maxCapacity == 300 &&
            targetCapacity == 300
        );

        return passed ? "✓ 聚合值缓存测试通过" : "✗ 聚合值缓存测试失败";
    }

    // ==================== 6. 联弹机制测试 ====================

    private static function testHitCount():String {
        var results:Array = [];

        results.push(testHitCount_Basic());
        results.push(testHitCount_StrengthMultiplier());
        results.push(testHitCount_MultipleShields());

        return formatResults(results, "联弹机制");
    }

    /**
     * 基础联弹测试
     */
    private static function testHitCount_Basic():String {
        var stack:ShieldStack = new ShieldStack();
        stack.addShield(Shield.createTemporary(1000, 50, -1, "盾"));

        // 10段联弹，总伤害600，有效强度500
        var penetrating:Number = stack.absorbDamage(600, false, 10);

        var passed:Boolean = (penetrating == 100 && stack.getCapacity() == 500);

        return passed ? "✓ 基础联弹测试通过" :
            "✗ 基础联弹测试失败（穿透=" + penetrating + "，期望100）";
    }

    /**
     * 联弹强度倍增测试
     */
    private static function testHitCount_StrengthMultiplier():String {
        var stack:ShieldStack = new ShieldStack();
        stack.addShield(Shield.createTemporary(1000, 100, -1, "盾"));

        // 5段联弹，有效强度500，伤害400 < 500 全部吸收
        var penetrating:Number = stack.absorbDamage(400, false, 5);

        var passed:Boolean = (penetrating == 0);

        return passed ? "✓ 联弹强度倍增测试通过" : "✗ 联弹强度倍增测试失败";
    }

    /**
     * 联弹多护盾分配测试
     */
    private static function testHitCount_MultipleShields():String {
        var stack:ShieldStack = new ShieldStack();
        stack.addShield(Shield.createTemporary(200, 100, -1, "外层"));
        stack.addShield(Shield.createTemporary(300, 80, -1, "内层"));

        // 10段联弹，表观强度100，有效强度1000
        // 伤害800，全部可吸收
        var penetrating:Number = stack.absorbDamage(800, false, 10);

        var passed:Boolean = (penetrating == 0 && stack.getCapacity() == 0);

        return passed ? "✓ 联弹多护盾分配测试通过" :
            "✗ 联弹多护盾分配测试失败（穿透=" + penetrating + "）";
    }

    // ==================== 7. 抵抗绕过测试 ====================

    private static function testResistBypass():String {
        var results:Array = [];

        results.push(testResist_NoResistant());
        results.push(testResist_HasResistant());
        results.push(testResist_CountAggregation());

        return formatResults(results, "抵抗绕过");
    }

    /**
     * 无抵抗护盾测试
     */
    private static function testResist_NoResistant():String {
        var stack:ShieldStack = new ShieldStack();
        stack.addShield(Shield.createTemporary(100, 50, -1, "普通盾"));

        // 绕过伤害应该直接穿透
        var penetrating:Number = stack.absorbDamage(30, true, 1);

        var passed:Boolean = (penetrating == 30 && !stack.hasResistantShield());

        return passed ? "✓ 无抵抗护盾测试通过" : "✗ 无抵抗护盾测试失败";
    }

    /**
     * 有抵抗护盾测试
     */
    private static function testResist_HasResistant():String {
        var stack:ShieldStack = new ShieldStack();
        stack.addShield(Shield.createTemporary(100, 50, -1, "普通盾"));
        stack.addShield(Shield.createResistant(100, 80, -1, "抗真伤盾"));

        // 绕过伤害应该被正常吸收
        var penetrating:Number = stack.absorbDamage(30, true, 1);

        var passed:Boolean = (penetrating == 0 && stack.hasResistantShield());

        return passed ? "✓ 有抵抗护盾测试通过" : "✗ 有抵抗护盾测试失败";
    }

    /**
     * 抵抗计数聚合测试
     */
    private static function testResist_CountAggregation():String {
        var stack:ShieldStack = new ShieldStack();
        stack.addShield(Shield.createResistant(100, 50, -1, "抗真伤1"));
        stack.addShield(Shield.createResistant(100, 50, -1, "抗真伤2"));
        stack.addShield(Shield.createTemporary(100, 50, -1, "普通盾"));

        var count:Number = stack.getResistantCount();

        var passed:Boolean = (count == 2);

        return passed ? "✓ 抵抗计数聚合测试通过" :
            "✗ 抵抗计数聚合测试失败（count=" + count + "，期望2）";
    }

    // ==================== 8. 更新与弹出测试 ====================

    private static function testUpdateAndEjection():String {
        var results:Array = [];

        results.push(testUpdate_Basic());
        results.push(testUpdate_EjectInactive());
        results.push(testUpdate_ReturnValue());
        results.push(testUpdate_AllDepleted());

        return formatResults(results, "更新与弹出");
    }

    /**
     * 基础更新测试
     */
    private static function testUpdate_Basic():String {
        var stack:ShieldStack = new ShieldStack();
        stack.addShield(Shield.createRechargeable(100, 50, 5, 0, "充能盾"));

        var shield:Shield = Shield(stack.getShields()[0]);
        shield.setCapacity(50);

        // 更新10帧
        for (var i:Number = 0; i < 10; i++) {
            stack.update(1);
        }

        var passed:Boolean = (shield.getCapacity() == 100);

        return passed ? "✓ 基础更新测试通过" : "✗ 基础更新测试失败";
    }

    /**
     * 弹出未激活护盾测试
     */
    private static function testUpdate_EjectInactive():String {
        var stack:ShieldStack = new ShieldStack();
        stack.addShield(Shield.createTemporary(100, 50, 10, "短期盾"));
        stack.addShield(Shield.createTemporary(100, 50, -1, "永久盾"));

        // 更新15帧，短期盾应该过期并被弹出
        for (var i:Number = 0; i < 15; i++) {
            stack.update(1);
        }

        var passed:Boolean = (stack.getShieldCount() == 1);

        return passed ? "✓ 弹出未激活护盾测试通过" :
            "✗ 弹出未激活护盾测试失败（count=" + stack.getShieldCount() + "）";
    }

    /**
     * update返回值测试
     */
    private static function testUpdate_ReturnValue():String {
        var stack:ShieldStack = new ShieldStack();
        stack.addShield(Shield.createDecaying(100, 50, 5, "衰减盾"));

        // 衰减中返回true
        var result1:Boolean = stack.update(1);

        // 空栈返回false
        stack.clear();
        var result2:Boolean = stack.update(1);

        var passed:Boolean = (result1 == true && result2 == false);

        return passed ? "✓ update返回值测试通过" : "✗ update返回值测试失败";
    }

    /**
     * 所有护盾耗尽测试
     */
    private static function testUpdate_AllDepleted():String {
        var stack:ShieldStack = new ShieldStack();
        var depletedCalled:Boolean = false;

        stack.onAllShieldsDepletedCallback = function(s:ShieldStack):Void {
            depletedCalled = true;
        };

        stack.addShield(Shield.createTemporary(50, 100, 10, "短期盾"));

        // 更新15帧，护盾过期
        for (var i:Number = 0; i < 15; i++) {
            stack.update(1);
        }

        var passed:Boolean = (depletedCalled && stack.getShieldCount() == 0);

        return passed ? "✓ 所有护盾耗尽测试通过" : "✗ 所有护盾耗尽测试失败";
    }

    // ==================== 9. 嵌套护盾栈测试 ====================

    private static function testNestedStack():String {
        var results:Array = [];

        results.push(testNested_AddStackAsShield());
        results.push(testNested_ConsumeCapacity());
        results.push(testNested_ResistantCount());
        results.push(testNested_Update());

        return formatResults(results, "嵌套护盾栈");
    }

    /**
     * 将护盾栈作为护盾添加测试
     */
    private static function testNested_AddStackAsShield():String {
        var outerStack:ShieldStack = new ShieldStack();
        var innerStack:ShieldStack = new ShieldStack();

        innerStack.addShield(Shield.createTemporary(100, 50, -1, "内部盾1"));
        innerStack.addShield(Shield.createTemporary(100, 50, -1, "内部盾2"));

        outerStack.addShield(innerStack);

        var capacity:Number = outerStack.getCapacity();

        var passed:Boolean = (capacity == 200);

        return passed ? "✓ 将护盾栈作为护盾添加测试通过" :
            "✗ 将护盾栈作为护盾添加测试失败（capacity=" + capacity + "）";
    }

    /**
     * 嵌套容量消耗测试
     */
    private static function testNested_ConsumeCapacity():String {
        var outerStack:ShieldStack = new ShieldStack();
        var innerStack:ShieldStack = new ShieldStack();

        innerStack.addShield(Shield.createTemporary(100, 50, -1, "内部盾"));
        outerStack.addShield(innerStack);

        var consumed:Number = outerStack.consumeCapacity(30);

        var passed:Boolean = (consumed == 30 && innerStack.getCapacity() == 70);

        return passed ? "✓ 嵌套容量消耗测试通过" : "✗ 嵌套容量消耗测试失败";
    }

    /**
     * 嵌套抵抗计数测试
     */
    private static function testNested_ResistantCount():String {
        var outerStack:ShieldStack = new ShieldStack();
        var innerStack:ShieldStack = new ShieldStack();

        innerStack.addShield(Shield.createResistant(100, 50, -1, "抗真伤"));
        outerStack.addShield(innerStack);
        outerStack.addShield(Shield.createResistant(100, 50, -1, "外部抗真伤"));

        var count:Number = outerStack.getResistantCount();

        var passed:Boolean = (count == 2);

        return passed ? "✓ 嵌套抵抗计数测试通过" :
            "✗ 嵌套抵抗计数测试失败（count=" + count + "）";
    }

    /**
     * 嵌套更新测试
     */
    private static function testNested_Update():String {
        var outerStack:ShieldStack = new ShieldStack();
        var innerStack:ShieldStack = new ShieldStack();

        innerStack.addShield(Shield.createDecaying(100, 50, 5, "衰减盾"));
        outerStack.addShield(innerStack);

        // 更新10帧
        for (var i:Number = 0; i < 10; i++) {
            outerStack.update(1);
        }

        var capacity:Number = innerStack.getCapacity();

        var passed:Boolean = (capacity == 50);

        return passed ? "✓ 嵌套更新测试通过" :
            "✗ 嵌套更新测试失败（capacity=" + capacity + "）";
    }

    // ==================== 10. 回调测试 ====================

    private static function testCallbacks():String {
        var results:Array = [];

        results.push(testCallbacks_OnShieldEjected());
        results.push(testCallbacks_OnAllShieldsDepleted());
        results.push(testCallbacks_SetCallbacks());

        return formatResults(results, "回调");
    }

    /**
     * 护盾弹出回调测试
     */
    private static function testCallbacks_OnShieldEjected():String {
        var stack:ShieldStack = new ShieldStack();
        var ejectedShield:IShield = null;

        stack.onShieldEjectedCallback = function(shield:IShield, s:ShieldStack):Void {
            ejectedShield = shield;
        };

        var shield:Shield = Shield.createTemporary(100, 50, 5, "短期盾");
        stack.addShield(shield);

        // 更新触发过期
        for (var i:Number = 0; i < 10; i++) {
            stack.update(1);
        }

        var passed:Boolean = (ejectedShield === shield);

        return passed ? "✓ 护盾弹出回调测试通过" : "✗ 护盾弹出回调测试失败";
    }

    /**
     * 所有护盾耗尽回调测试
     */
    private static function testCallbacks_OnAllShieldsDepleted():String {
        var stack:ShieldStack = new ShieldStack();
        var depletedCalled:Boolean = false;

        stack.onAllShieldsDepletedCallback = function(s:ShieldStack):Void {
            depletedCalled = true;
        };

        stack.addShield(Shield.createTemporary(50, 100, 5, "短期盾"));

        // 更新触发过期
        for (var i:Number = 0; i < 10; i++) {
            stack.update(1);
        }

        var passed:Boolean = depletedCalled;

        return passed ? "✓ 所有护盾耗尽回调测试通过" : "✗ 所有护盾耗尽回调测试失败";
    }

    /**
     * setCallbacks批量设置测试
     */
    private static function testCallbacks_SetCallbacks():String {
        var stack:ShieldStack = new ShieldStack();
        var ejectedCalled:Boolean = false;
        var depletedCalled:Boolean = false;

        var result:ShieldStack = stack.setCallbacks({
            onShieldEjected: function(shield, s) { ejectedCalled = true; },
            onAllShieldsDepleted: function(s) { depletedCalled = true; }
        });

        // 验证链式调用
        var chainPassed:Boolean = (result === stack);

        stack.addShield(Shield.createTemporary(50, 100, 5, "短期盾"));

        for (var i:Number = 0; i < 10; i++) {
            stack.update(1);
        }

        var passed:Boolean = (chainPassed && ejectedCalled && depletedCalled);

        return passed ? "✓ setCallbacks批量设置测试通过" : "✗ setCallbacks批量设置测试失败";
    }

    // ==================== 11. 边界条件测试 ====================

    private static function testBoundaryConditions():String {
        var results:Array = [];

        results.push(testBoundary_NullShield());
        results.push(testBoundary_ZeroDamage());
        results.push(testBoundary_LargeNumbers());
        results.push(testBoundary_EmptyUpdate());

        return formatResults(results, "边界条件");
    }

    /**
     * 添加null护盾测试
     */
    private static function testBoundary_NullShield():String {
        var stack:ShieldStack = new ShieldStack();

        var added:Boolean = stack.addShield(null);

        var passed:Boolean = (!added && stack.getShieldCount() == 0);

        return passed ? "✓ 添加null护盾测试通过" : "✗ 添加null护盾测试失败";
    }

    /**
     * 零伤害测试
     */
    private static function testBoundary_ZeroDamage():String {
        var stack:ShieldStack = new ShieldStack();
        stack.addShield(Shield.createTemporary(100, 50, -1, "盾"));

        var penetrating:Number = stack.absorbDamage(0, false, 1);

        var passed:Boolean = (penetrating == 0 && stack.getCapacity() == 100);

        return passed ? "✓ 零伤害测试通过" : "✗ 零伤害测试失败";
    }

    /**
     * 大数值测试
     */
    private static function testBoundary_LargeNumbers():String {
        var stack:ShieldStack = new ShieldStack();
        stack.addShield(Shield.createTemporary(1000000, 500000, -1, "大盾"));

        var penetrating:Number = stack.absorbDamage(800000, false, 1);

        var passed:Boolean = (penetrating == 300000 && stack.getCapacity() == 500000);

        return passed ? "✓ 大数值测试通过" : "✗ 大数值测试失败";
    }

    /**
     * 空栈更新测试
     */
    private static function testBoundary_EmptyUpdate():String {
        var stack:ShieldStack = new ShieldStack();

        var result:Boolean = stack.update(1);

        var passed:Boolean = (result == false);

        return passed ? "✓ 空栈更新测试通过" : "✗ 空栈更新测试失败";
    }

    // ==================== 12. 性能测试 ====================

    private static function testPerformance():String {
        var result:String = "";

        result += perfTest_AbsorbDamage();
        result += perfTest_UpdateManyShields();
        result += perfTest_NestedStacks();

        return result;
    }

    /**
     * 伤害吸收性能测试
     */
    private static function perfTest_AbsorbDamage():String {
        var stack:ShieldStack = new ShieldStack();
        stack.addShield(Shield.createTemporary(1000000, 100, -1, "盾"));

        var iterations:Number = 10000;
        var startTime:Number = getTimer();

        for (var i:Number = 0; i < iterations; i++) {
            stack.absorbDamage(50, false, 1);
        }

        var endTime:Number = getTimer();
        var duration:Number = endTime - startTime;
        var avgTime:Number = duration / iterations;

        return "absorbDamage: " + iterations + "次 " + duration + "ms, " +
               "平均" + avgTime + "ms/次\n";
    }

    /**
     * 多护盾更新性能测试
     */
    private static function perfTest_UpdateManyShields():String {
        var stack:ShieldStack = new ShieldStack();

        // 添加10个护盾
        for (var i:Number = 0; i < 10; i++) {
            stack.addShield(Shield.createRechargeable(100, 50, 1, 0, "盾" + i));
        }

        // 消耗一些容量
        stack.consumeCapacity(500);

        var iterations:Number = 10000;
        var startTime:Number = getTimer();

        for (var j:Number = 0; j < iterations; j++) {
            stack.update(1);
        }

        var endTime:Number = getTimer();
        var duration:Number = endTime - startTime;
        var avgTime:Number = duration / iterations;

        return "update(10护盾): " + iterations + "次 " + duration + "ms, " +
               "平均" + avgTime + "ms/次\n";
    }

    /**
     * 嵌套栈性能测试
     */
    private static function perfTest_NestedStacks():String {
        var outerStack:ShieldStack = new ShieldStack();

        // 创建3层嵌套
        for (var i:Number = 0; i < 3; i++) {
            var innerStack:ShieldStack = new ShieldStack();
            innerStack.addShield(Shield.createTemporary(100, 50, -1, "内部盾"));
            outerStack.addShield(innerStack);
        }

        var iterations:Number = 10000;
        var startTime:Number = getTimer();

        for (var j:Number = 0; j < iterations; j++) {
            outerStack.consumeCapacity(10);
        }

        var endTime:Number = getTimer();
        var duration:Number = endTime - startTime;
        var avgTime:Number = duration / iterations;

        return "嵌套栈消耗: " + iterations + "次 " + duration + "ms, " +
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
