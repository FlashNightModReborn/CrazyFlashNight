import org.flashNight.arki.unit.Action.Regeneration.HealApplier;

/**
 * HealApplierTest - HealApplier 单元测试
 *
 * 启动:
 *   import org.flashNight.arki.unit.Action.Regeneration.*;
 *   HealApplierTest.runTests();
 *
 * 覆盖：
 *   - applyHpCapped: 普通/超封顶/已达封顶/封顶以上/死亡守门/边界值/炼金抬升封顶
 *   - applyMpCapped: HP/MP 通道隔离 + 死亡用 HP 判
 *   - applyHpOverflow: 满血以下/跨满血/纯衰减/死亡守门/边界值
 *
 * applyHpOverflow 的衰减曲线在 DamageHandlersTest 的 LifeSteal 套件已通过
 * LifeStealDamageHandle → HealApplier 链路覆盖，本测试只复测核心契约。
 */
class org.flashNight.arki.unit.Action.Regeneration.HealApplierTest {

    private static var _total:Number = 0;
    private static var _pass:Number = 0;
    private static var _fail:Number = 0;

    private static function assertEq(expected, actual, msg:String):Void {
        _total++;
        if (expected != actual) {
            _fail++;
            trace("[FAIL] " + msg);
            trace("  expected: " + expected);
            trace("  actual  : " + actual);
        } else {
            _pass++;
            trace("[PASS] " + msg);
        }
    }

    private static function assertFloatEq(expected:Number, actual:Number, delta:Number, msg:String):Void {
        _total++;
        var diff:Number = expected - actual;
        if (diff < 0) diff = -diff;
        if (diff > delta) {
            _fail++;
            trace("[FAIL] " + msg);
            trace("  expected: " + expected + " +/-" + delta);
            trace("  actual  : " + actual + " (diff=" + diff + ")");
        } else {
            _pass++;
            trace("[PASS] " + msg);
        }
    }

    public static function runTests():Void {
        trace("===== HealApplier 测试套件 =====");
        _total = 0; _pass = 0; _fail = 0;

        // applyHpCapped / applyMpCapped
        test_Capped_普通治疗();
        test_Capped_超过封顶截断();
        test_Capped_已达封顶();
        test_Capped_封顶以上不退还();
        test_Capped_死亡守门();
        test_Capped_零amount();
        test_Capped_负amount();
        test_Capped_NaN_amount();
        test_Capped_零capValue();
        test_Capped_MP通道();
        test_Capped_炼金抬升封顶();

        // applyHpOverflow
        test_Overflow_满血以下退化为100效率();
        test_Overflow_跨满血段();
        test_Overflow_纯衰减段();
        test_Overflow_死亡守门();
        test_Overflow_零amount();

        trace("===== HealApplier 汇总: run=" + _total + " pass=" + _pass + " fail=" + _fail + " =====");
    }

    // ==================== applyHpCapped / applyMpCapped ====================

    private static function test_Capped_普通治疗():Void {
        var t:Object = {hp: 80};
        var r:Number = HealApplier.applyHpCapped(t, 10, 100);
        assertEq(10, r, "Capped 普通: 返回实际治疗10");
        assertEq(90, t.hp, "Capped 普通: hp 80→90");
    }

    private static function test_Capped_超过封顶截断():Void {
        var t:Object = {hp: 95};
        var r:Number = HealApplier.applyHpCapped(t, 10, 100);
        assertEq(5, r, "Capped 超封顶: 实际只回5");
        assertEq(100, t.hp, "Capped 超封顶: hp 截断到100");
    }

    private static function test_Capped_已达封顶():Void {
        var t:Object = {hp: 100};
        var r:Number = HealApplier.applyHpCapped(t, 10, 100);
        assertEq(0, r, "Capped 已达封顶: 返回0");
        assertEq(100, t.hp, "Capped 已达封顶: hp 不变");
    }

    // 炼金 buff 失效后玩家 hp 仍在旧封顶之上，下次普通治疗不应把他推回低封顶
    private static function test_Capped_封顶以上不退还():Void {
        var t:Object = {hp: 130};
        var r:Number = HealApplier.applyHpCapped(t, 10, 100);
        assertEq(0, r, "Capped 封顶以上: 返回0");
        assertEq(130, t.hp, "Capped 封顶以上: hp 不被向下拉");
    }

    private static function test_Capped_死亡守门():Void {
        var t:Object = {hp: 0};
        var r:Number = HealApplier.applyHpCapped(t, 50, 100);
        assertEq(0, r, "Capped 死亡: 返回0");
        assertEq(0, t.hp, "Capped 死亡: hp 不被复活");
    }

    private static function test_Capped_零amount():Void {
        var t:Object = {hp: 50};
        var r:Number = HealApplier.applyHpCapped(t, 0, 100);
        assertEq(0, r, "Capped amount=0: 返回0");
        assertEq(50, t.hp, "Capped amount=0: hp 不变");
    }

    private static function test_Capped_负amount():Void {
        var t:Object = {hp: 50};
        var r:Number = HealApplier.applyHpCapped(t, -10, 100);
        assertEq(0, r, "Capped amount<0: 返回0（HealApplier 不做扣血）");
        assertEq(50, t.hp, "Capped amount<0: hp 不变");
    }

    private static function test_Capped_NaN_amount():Void {
        var t:Object = {hp: 50};
        var r:Number = HealApplier.applyHpCapped(t, Number.NaN, 100);
        assertEq(0, r, "Capped amount=NaN: 返回0");
        assertEq(50, t.hp, "Capped amount=NaN: hp 不变");
    }

    private static function test_Capped_零capValue():Void {
        var t:Object = {hp: 50};
        var r:Number = HealApplier.applyHpCapped(t, 10, 0);
        assertEq(0, r, "Capped cap=0: 返回0");
        assertEq(50, t.hp, "Capped cap=0: hp 不变");
    }

    private static function test_Capped_MP通道():Void {
        var t:Object = {hp: 100, mp: 30};
        var r:Number = HealApplier.applyMpCapped(t, 20, 50);
        assertEq(20, r, "Capped MP: 返回20");
        assertEq(50, t.mp, "Capped MP: mp 30→50");
        assertEq(100, t.hp, "Capped MP: hp 不被误改");
    }

    // 模拟炼金把封顶从 M 抬升到 1.3M，玩家从 M 起回血 0.5M 应被截到 1.3M
    private static function test_Capped_炼金抬升封顶():Void {
        var t:Object = {hp: 10000};
        var r:Number = HealApplier.applyHpCapped(t, 5000, 13000);
        assertEq(3000, r, "Capped 炼金: hp 从M回到1.3M，实际回3000");
        assertEq(13000, t.hp, "Capped 炼金: hp 截断到13000");
    }

    // ==================== applyHpOverflow ====================

    private static function test_Overflow_满血以下退化为100效率():Void {
        var t:Object = {hp: 80};
        var r:Number = HealApplier.applyHpOverflow(t, 10, 100);
        assertEq(10, r, "Overflow 满血下: 100% 效率");
        assertEq(90, t.hp, "Overflow 满血下: hp 80→90");
    }

    // M=10000, 起 hp=8000, amount=4000: part1=2000, part2≈1648
    private static function test_Overflow_跨满血段():Void {
        var t:Object = {hp: 8000};
        var r:Number = HealApplier.applyHpOverflow(t, 4000, 10000);
        assertFloatEq(3648, r, 1, "Overflow 跨满血: 实际回 2000+1648");
        assertFloatEq(11648, t.hp, 1, "Overflow 跨满血: hp 8000→11648");
    }

    // M=10000, 起 hp=10000, amount=10000: part2 = 5000*(1-exp(-2)) ≈ 4323
    private static function test_Overflow_纯衰减段():Void {
        var t:Object = {hp: 10000};
        var r:Number = HealApplier.applyHpOverflow(t, 10000, 10000);
        assertFloatEq(4323, r, 1, "Overflow 纯衰减: 实际回 0.4323M");
        assertFloatEq(14323, t.hp, 1, "Overflow 纯衰减: hp 10000→14323");
    }

    private static function test_Overflow_死亡守门():Void {
        var t:Object = {hp: 0};
        var r:Number = HealApplier.applyHpOverflow(t, 100, 100);
        assertEq(0, r, "Overflow 死亡: 返回0");
        assertEq(0, t.hp, "Overflow 死亡: hp 不被复活");
    }

    private static function test_Overflow_零amount():Void {
        var t:Object = {hp: 50};
        var r:Number = HealApplier.applyHpOverflow(t, 0, 100);
        assertEq(0, r, "Overflow amount=0: 返回0");
        assertEq(50, t.hp, "Overflow amount=0: hp 不变");
    }
}
