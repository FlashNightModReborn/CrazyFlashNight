import org.flashNight.arki.component.Buff.*;
import org.flashNight.arki.component.Buff.BuffHandle.*;
import org.flashNight.arki.component.Buff.BuffPropertyHandle.*;
import org.flashNight.naki.DataStructures.Dictionary;

class org.flashNight.arki.component.Buff.BuffPropertyHandle.BasicBuffPropertyTest {

    public static function runTests():Void {
        trace("Running BasicBuffProperty Tests...");

        var mockObj:Object = { testProperty: 100 };
        var buffProperty:BasicBuffProperty = new BasicBuffProperty(mockObj, "testProperty", 100, null);

        // 创建 Buff（不再传递未定义的参数给构造函数）
        var additionBuff1:IBuff = new AdditionBuff(50); // +50
        var additionBuff2:IBuff = new AdditionBuff(30); // +30
        var multiplierBuff1:IBuff = new MultiplierBuff(1.5); // *1.5
        var multiplierBuff2:IBuff = new MultiplierBuff(0.5); // *0.5

        // Test 1: Adding Buffs
        trace("Test 1: Adding Buffs");
        // 为 Buff 添加时传入上下限参数
        // additionBuff1 无上下限
        buffProperty.addBuff(additionBuff1, undefined, undefined);
        // additionBuff2 上限180，下限-20
        buffProperty.addBuff(additionBuff2, 180, -20);
        // multiplierBuff1 无上下限
        buffProperty.addBuff(multiplierBuff1, undefined, undefined);
        // multiplierBuff2 上限2，下限0.1
        buffProperty.addBuff(multiplierBuff2, 2, 0.1);

        trace("Expected: Addition = +80, Multiplier = *0.75 (clamped to [0.1,2])");
        // 计算预期值: (100 * 0.75) + 80 = 155，然后在[0.1,2]范围内裁剪为2
        trace("Computed Buffed Value: " + buffProperty.getBuffedValue()); // 应为2

        // Test 2: Removing Buffs
        trace("Test 2: Removing Buffs");
        buffProperty.removeBuff(additionBuff1);

        // 现在加成只有+30，乘算0.75
        // (100 * 0.75) + 30 = 105，再裁剪到[0.1,2]，结果依旧是2
        trace("Expected: Addition = +30, Multiplier = *0.75, Clamped to 2");
        trace("Computed Buffed Value: " + buffProperty.getBuffedValue()); // 2

        // Test 3: Upper/Lower Limits
        trace("Test 3: Testing Upper and Lower Limits");
        // 重新加回 additionBuff1，这样加成又变成+80，结果同Test1
        buffProperty.addBuff(additionBuff1, undefined, undefined);

        // 与Test1相同计算结果，再次是2
        trace("Expected: Value within combined limits -> 2");
        trace("Computed Buffed Value: " + buffProperty.getBuffedValue()); // 2

        // Test 4: No Buffs
        trace("Test 4: No Buffs Applied");
        buffProperty.clearAllBuffs();
        // 无buff时值为基础值100
        trace("Expected: 100 (base value)");
        trace("Computed Buffed Value: " + buffProperty.getBuffedValue()); // 100

        trace("BasicBuffProperty Tests Completed.");
    }
}
