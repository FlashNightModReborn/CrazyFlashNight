import org.flashNight.arki.component.StatHandler.*;

class org.flashNight.arki.component.StatHandler.DamageResistanceHandlerTest {
    public function DamageResistanceHandlerTest() {
        // 定义断言函数
        function assert(condition:Boolean, message:String):Void {
            if (!condition) {
                trace("Assertion failed: " + message);
            } else {
                trace("Assertion passed: " + message);
            }
        }

        // 测试 defenseDamageRatio
        assert(DamageResistanceHandler.defenseDamageRatio(0) == 1, "defenseDamageRatio(0) should be 1");
        assert(DamageResistanceHandler.defenseDamageRatio(300) == 0.5, "defenseDamageRatio(300) should be 0.5");
        assert(DamageResistanceHandler.defenseDamageRatio(600) == 1/3, "defenseDamageRatio(600) should be 1/3");
        assert(DamageResistanceHandler.defenseDamageRatio(100) == 0.75, "defenseDamageRatio(100) should be 0.75");

        // 测试 bounceDamageCalculation
        assert(DamageResistanceHandler.bounceDamageCalculation(0, 0) == 1, "bounceDamageCalculation(0,0) should be 1");
        assert(DamageResistanceHandler.bounceDamageCalculation(1, 0) == 1, "bounceDamageCalculation(1,0) should be 1");
        assert(DamageResistanceHandler.bounceDamageCalculation(1, 5) == 1, "bounceDamageCalculation(1,5) should be 1");
        assert(DamageResistanceHandler.bounceDamageCalculation(10, 20) == 6, "bounceDamageCalculation(10,20) should be 6");
        assert(DamageResistanceHandler.bounceDamageCalculation(10, 50) == 1, "bounceDamageCalculation(10,50) should be 1");

        // 测试 penetrationDamageCalculation
        assert(DamageResistanceHandler.penetrationDamageCalculation(0, 0) == 1, "penetrationDamageCalculation(0,0) should be 1");
        assert(DamageResistanceHandler.penetrationDamageCalculation(1, 0) == 1, "penetrationDamageCalculation(1,0) should be 1");
        assert(DamageResistanceHandler.penetrationDamageCalculation(1, 300) == 1, "penetrationDamageCalculation(1,300) should be 1");
        assert(DamageResistanceHandler.penetrationDamageCalculation(10, 300) == 5, "penetrationDamageCalculation(10,300) should be 5");
        assert(DamageResistanceHandler.penetrationDamageCalculation(10, 600) == 3, "penetrationDamageCalculation(10,600) should be 3");

        // 性能测试
        performanceTest();
    }

    private function performanceTest():Void {
        var iterations:Number = 100000;
        var startTime:Number = getTimer();
        
        for (i = 0; i < iterations; i++) {
            DamageResistanceHandler.defenseDamageRatio(10, 5);
        }
        endTime = getTimer();
        trace("defenseDamageRatio executed " + iterations + " times in " + (endTime - startTime) + " ms");

        startTime = getTimer();
        for (var i:Number = 0; i < iterations; i++) {
            DamageResistanceHandler.bounceDamageCalculation(10, 5);
        }
        var endTime:Number = getTimer();
        trace("bounceDamageCalculation executed " + iterations + " times in " + (endTime - startTime) + " ms");

        startTime = getTimer();
        for (i = 0; i < iterations; i++) {
            DamageResistanceHandler.penetrationDamageCalculation(10, 5);
        }
        endTime = getTimer();
        trace("penetrationDamageCalculation executed " + iterations + " times in " + (endTime - startTime) + " ms");
    }
}