/**
 * DodgeHandlerTest
 * 覆盖装备挡拆加成到躲闪率参数的换算。
 */
import org.flashNight.arki.component.StatHandler.DodgeHandler;

class org.flashNight.arki.component.StatHandler.DodgeHandlerTest
{
    private var total:Number = 0;
    private var failed:Number = 0;

    public function DodgeHandlerTest()
    {
        testApplyDodgeBonus();
        testDodgeBonusRaisesFinalRate();

        if (failed > 0)
        {
            trace("[TEST_FAIL] DodgeHandlerTest: " + failed + " / " + total + " failed");
        }
        else
        {
            trace("[TEST_PASS] DodgeHandlerTest: " + total + " / " + total + " passed");
        }
    }

    private function assertNear(actual:Number, expected:Number, tolerance:Number, message:String):Void
    {
        total++;
        if (Math.abs(actual - expected) > tolerance)
        {
            failed++;
            trace("[FAIL] " + message + ": expected=" + expected + ", actual=" + actual);
        }
        else
        {
            trace("[PASS] " + message);
        }
    }

    private function assertTrue(condition:Boolean, message:String):Void
    {
        total++;
        if (!condition)
        {
            failed++;
            trace("[FAIL] " + message);
        }
        else
        {
            trace("[PASS] " + message);
        }
    }

    private function testApplyDodgeBonus():Void
    {
        assertNear(DodgeHandler.applyDodgeBonus(5, 0), 5, 0.000001, "0% 加成保持基础躲闪率参数");
        assertNear(DodgeHandler.applyDodgeBonus(5, 10), 5 / 1.1, 0.000001, "10% 加成提升 10% 躲闪能力");
        assertNear(DodgeHandler.applyDodgeBonus(5, 100), 2.5, 0.000001, "100% 加成使躲闪能力翻倍");
        assertNear(DodgeHandler.applyDodgeBonus(5, -100), 100, 0.000001, "负向溢出受躲闪能力下限保护");
    }

    private function testDodgeBonusRaisesFinalRate():Void
    {
        var baseParameter:Number = 5;
        var bonusParameter:Number = DodgeHandler.applyDodgeBonus(baseParameter, 100);
        var baseRate:Number = DodgeHandler.calcDodgeRateByLevel(35, 35, baseParameter, 10);
        var bonusRate:Number = DodgeHandler.calcDodgeRateByLevel(35, 35, bonusParameter, 10);

        assertTrue(bonusParameter < baseParameter, "正挡拆加成降低等级公式使用的躲闪率参数");
        assertTrue(bonusRate > baseRate, "正挡拆加成提高最终躲闪触发概率");
    }
}
