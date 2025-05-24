import org.flashNight.arki.component.StatHandler.*;

/**
 * DamageResistanceHandlerTest
 * 用于测试 DamageResistanceHandler 类的功能正确性和性能表现
 */
class org.flashNight.arki.component.StatHandler.DamageResistanceHandlerTest {
    // 定义断言函数
    public function assert(condition:Boolean, message:String):Void {
        if (!condition) {
            trace("Assertion failed: " + message);
        } else {
            trace("Assertion passed: " + message);
        }
    }

    public function DamageResistanceHandlerTest() {
        // 测试 defenseDamageRatio
        testDefenseDamageRatio();

        // 测试 bounceDamageCalculation
        testBounceDamageCalculation();

        // 测试 penetrationDamageCalculation
        testPenetrationDamageCalculation();

        // 性能测试
        performanceTest();
    }

    /**
     * 测试 defenseDamageRatio 方法
     */
    private function testDefenseDamageRatio():Void {
        trace("=== Testing defenseDamageRatio ===");
        // 基本测试
        assert(DamageResistanceHandler.defenseDamageRatio(0) == 1, "defenseDamageRatio(0) 应该返回 1");
        assert(DamageResistanceHandler.defenseDamageRatio(300) == 0.5, "defenseDamageRatio(300) 应该返回 0.5");
        assert(DamageResistanceHandler.defenseDamageRatio(600) == 0.3333333333333333, "defenseDamageRatio(600) 应该返回 0.3333");
        assert(DamageResistanceHandler.defenseDamageRatio(100) == 0.75, "defenseDamageRatio(100) 应该返回 0.75");

        // 边界测试
        assert(DamageResistanceHandler.defenseDamageRatio(1) == 300 / 301, "defenseDamageRatio(1) 应该返回 300/301");
        assert(DamageResistanceHandler.defenseDamageRatio(299) == 300 / 599, "defenseDamageRatio(299) 应该返回 300/599");
        assert(DamageResistanceHandler.defenseDamageRatio(300) == 0.5, "defenseDamageRatio(300) 应该返回 0.5");

        // 大数值测试
        assert(DamageResistanceHandler.defenseDamageRatio(1000) == 300 / 1300, "defenseDamageRatio(1000) 应该返回 300/1300");
        assert(DamageResistanceHandler.defenseDamageRatio(1000000) == 300 / 1000300, "defenseDamageRatio(1000000) 应该返回 300/1000300");

        // 小数测试（虽然通常为整数，这里做健壮性验证）
        assert(DamageResistanceHandler.defenseDamageRatio(150.5) == 300 / (150.5 + 300), "defenseDamageRatio(150.5) 应该返回 300/(150.5+300)");

        trace("=== defenseDamageRatio 测试完成 ===\n");
    }

    /**
     * 测试 bounceDamageCalculation 方法
     */
    private function testBounceDamageCalculation():Void {
        trace("=== Testing bounceDamageCalculation ===");
        // 基本测试
        assert(DamageResistanceHandler.bounceDamageCalculation(0, 0) == 1, "bounceDamageCalculation(0,0) 应该返回 1");
        assert(DamageResistanceHandler.bounceDamageCalculation(1, 0) == 1, "bounceDamageCalculation(1,0) 应该返回 1");
        assert(DamageResistanceHandler.bounceDamageCalculation(1, 5) == 1, "bounceDamageCalculation(1,5) 应该返回 1");
        assert(DamageResistanceHandler.bounceDamageCalculation(10, 20) == 6, "bounceDamageCalculation(10,20) 应该返回 6");
        assert(DamageResistanceHandler.bounceDamageCalculation(10, 50) == 1, "bounceDamageCalculation(10,50) 应该返回 1");

        // 修正后：这两个测试根据公式实际结果应为 1
        assert(DamageResistanceHandler.bounceDamageCalculation(5, 25) == 1, "bounceDamageCalculation(5,25) 应该返回 1");
        assert(DamageResistanceHandler.bounceDamageCalculation(5, 24) == 1, "bounceDamageCalculation(5,24) 应该返回 1");

        // 大数值测试
        assert(DamageResistanceHandler.bounceDamageCalculation(1000, 500) == 900, "bounceDamageCalculation(1000,500) 应该返回 900");
        assert(DamageResistanceHandler.bounceDamageCalculation(100000, 25000) == 95000, "bounceDamageCalculation(100000,25000) 应该返回 95000");

        // 奇偶数测试
        assert(DamageResistanceHandler.bounceDamageCalculation(15, 10) == 13, "bounceDamageCalculation(15,10) 应该返回 13");
        assert(DamageResistanceHandler.bounceDamageCalculation(16, 10) == 14, "bounceDamageCalculation(16,10) 应该返回 14");

        trace("=== bounceDamageCalculation 测试完成 ===\n");
    }

    /**
     * 测试 penetrationDamageCalculation 方法
     */
    private function testPenetrationDamageCalculation():Void {
        trace("=== Testing penetrationDamageCalculation ===");
        // 基本测试
        assert(DamageResistanceHandler.penetrationDamageCalculation(0, 0) == 1, "penetrationDamageCalculation(0,0) 应该返回 1");
        assert(DamageResistanceHandler.penetrationDamageCalculation(1, 0) == 1, "penetrationDamageCalculation(1,0) 应该返回 1");
        assert(DamageResistanceHandler.penetrationDamageCalculation(1, 300) == 1, "penetrationDamageCalculation(1,300) 应该返回 1");

        // 修正后：根据公式实际结果
        // 10,300 => ratio=300/(300+300)=0.5 => 10*0.5=5 => floor=>5
        // 10,600 => ratio=300/(600+300)=300/900=1/3 => 10*(1/3)=3.333 => floor=>3
        assert(DamageResistanceHandler.penetrationDamageCalculation(10, 300) == 5, "penetrationDamageCalculation(10,300) 应该返回 5");
        assert(DamageResistanceHandler.penetrationDamageCalculation(10, 600) == 3, "penetrationDamageCalculation(10,600) 应该返回 3");

        // 边界测试
        //  5,150 => ratio=300/(150+300)=300/450=2/3 => 5*(2/3)=3.333 => floor=>3 => 与1取max =>3
        assert(DamageResistanceHandler.penetrationDamageCalculation(5, 150) == 3, "penetrationDamageCalculation(5,150) 应该返回 3");
        //  5,149 => ratio=300/(149+300)=300/449≈0.668 => 5*0.668=3.34 => floor=>3
        assert(DamageResistanceHandler.penetrationDamageCalculation(5, 149) == 3, "penetrationDamageCalculation(5,149) 应该返回 3");
        //  5,301 => ratio=300/(301+300)=300/601≈0.499 => 5*0.499≈2.49 => floor=>2
        assert(DamageResistanceHandler.penetrationDamageCalculation(5, 301) == 2, "penetrationDamageCalculation(5,301) 应该返回 2");

        // 大数值测试
        //  1000,500 => ratio=300/(500+300)=300/800=0.375 =>1000*0.375=375 => floor=>375
        assert(DamageResistanceHandler.penetrationDamageCalculation(1000, 500) == 375, "penetrationDamageCalculation(1000,500) 应该返回 375");
        //  100000,25000 => ratio=300/(25000+300)=300/25300≈0.0118577 => 100000*0.0118577≈1185.77 => floor=>1185
        assert(DamageResistanceHandler.penetrationDamageCalculation(100000, 25000) == 1185, "penetrationDamageCalculation(100000,25000) 应该返回 1185");

        // 奇偶数测试
        //  15,150 => ratio=300/(150+300)=300/450=2/3 =>15*(2/3)=10 => floor=>10
        assert(DamageResistanceHandler.penetrationDamageCalculation(15, 150) == 10, "penetrationDamageCalculation(15,150) 应该返回 10");
        //  16,150 => ratio=300/(150+300)=2/3 =>16*(2/3)=10.666 => floor=>10
        assert(DamageResistanceHandler.penetrationDamageCalculation(16, 150) == 10, "penetrationDamageCalculation(16,150) 应该返回 10");

        trace("=== penetrationDamageCalculation 测试完成 ===\n");
    }

    /**
     * 性能测试
     * 通过多种输入参数组合，评估各方法的执行效率
     */
    private function performanceTest():Void {
        trace("=== Starting Performance Test ===");
        var iterations:Number = 100000;
        var startTime:Number, endTime:Number;

        // 性能测试 defenseDamageRatio
        startTime = getTimer();
        for (var i:Number = 0; i < iterations; i++) {
            DamageResistanceHandler.defenseDamageRatio(i % 1000); // 0 到 999 循环
        }
        endTime = getTimer();
        trace("defenseDamageRatio 执行 " + iterations + " 次，耗时 " + (endTime - startTime) + " ms");

        // 性能测试 bounceDamageCalculation
        startTime = getTimer();
        for (i = 0; i < iterations; i++) {
            var damage:Number = i % 500;    // 0 到 499
            var defense:Number = (i * 3) % 100; // 0 到 99
            DamageResistanceHandler.bounceDamageCalculation(damage, defense);
        }
        endTime = getTimer();
        trace("bounceDamageCalculation 执行 " + iterations + " 次，耗时 " + (endTime - startTime) + " ms");

        // 性能测试 penetrationDamageCalculation
        startTime = getTimer();
        for (i = 0; i < iterations; i++) {
            damage = (i * 2) % 1000;   // 0 到 999
            defense = (i * 5) % 200;   // 0 到 199
            DamageResistanceHandler.penetrationDamageCalculation(damage, defense);
        }
        endTime = getTimer();
        trace("penetrationDamageCalculation 执行 " + iterations + " 次，耗时 " + (endTime - startTime) + " ms");

        trace("=== Performance Test Completed ===\n");
    }
}
