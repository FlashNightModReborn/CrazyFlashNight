import org.flashNight.neur.Controller.*;

class org.flashNight.neur.Controller.TestPIDController {
    private var pid:org.flashNight.neur.Controller.PIDController;

    public function TestPIDController() {
        // 初始化 PIDController 实例
        pid = new org.flashNight.neur.Controller.PIDController(1.0, 0.1, 0.01, 1000, 0.1);
    }

    // 主测试方法
    public function runTests():Void {
        trace("Running PIDController Tests...");
        testFunctionality();
        testBoundaryConditions();
        testContinuousUpdates();
        testDifferentDeltaTime();
        testIntegralLimits();
        testDerivativeFilters();
        testPerformance();
    }

    // 功能测试
    private function testFunctionality():Void {
        trace("Testing functionality...");
        resetPID();

        // 测试比例增益
        pid.setKp(2.0);
        assertEqual(pid.getKp(), 2.0, "Kp getter/setter");

        // 测试积分增益
        pid.setKi(0.5);
        assertEqual(pid.getKi(), 0.5, "Ki getter/setter");

        // 测试微分增益
        pid.setKd(0.2);
        assertEqual(pid.getKd(), 0.2, "Kd getter/setter");

        // 测试积分限幅
        pid.setIntegralMax(500);
        assertEqual(pid.getIntegralMax(), 500, "IntegralMax getter/setter");

        // 测试微分滤波系数
        pid.setDerivativeFilter(0.3);
        assertEqual(pid.getDerivativeFilter(), 0.3, "DerivativeFilter getter/setter");

        // 基本 PID 输出测试
        var output:Number = pid.update(10, 5, 1);
        assertAlmostEqual(output, 12.8, 0.001, "Basic PID calculation"); // 预期输出为 12.8
    }

    // 边界条件测试
    private function testBoundaryConditions():Void {
        trace("Testing boundary conditions...");
        
        // 测试积分限幅
        resetPID();
        pid.update(100, 0, 10); // 大积分值
        pid.update(100, 0, 10); // 再次更新，积分应被限制
        var integral:Number = pid.getIntegral();
        assertEqual(integral, 500, "Integral windup prevention");

        // 测试 deltaTime <= 0 的情况
        var zeroDeltaTimeOutput:Number = pid.update(10, 5, 0);
        assertEqual(zeroDeltaTimeOutput, 0, "Zero deltaTime handling");

        var negativeDeltaTimeOutput:Number = pid.update(10, 5, -1);
        assertEqual(negativeDeltaTimeOutput, 0, "Negative deltaTime handling");

        // 测试微分滤波边界
        resetPID(); // 重置 PID 控制器状态，确保 errorPrev = 0, integral = 0, derivativePrev = 0
        pid.setDerivativeFilter(1.0); // 设置为最大值
        trace("Before derivative test: " + pid.toString()); // 添加日志

        var derivativeTestOutput:Number = pid.update(10, 5, 1);
        trace("After derivative test: " + pid.toString()); // 添加日志

        assertAlmostEqual(derivativeTestOutput, 13.5, 0.001, "Derivative filter boundary test"); // 预期输出为 13.5
    }

    // 连续多次更新测试
    private function testContinuousUpdates():Void {
        trace("Testing continuous updates...");
        resetPID();

        // 确保 derivativeFilter 设置为 0.2
        pid.setDerivativeFilter(0.2);
        trace("After reset and setting derivativeFilter to 0.2: " + pid.toString());

        var setPoint:Number = 20;
        var actualValue:Number = 15;
        var deltaTime:Number = 1;

        // 第一更新
        var output1:Number = pid.update(setPoint, actualValue, deltaTime);
        trace("After first update: " + pid.toString());
        assertAlmostEqual(output1, 12.8, 0.3, "Continuous update 1");

        // 第二更新 (actualValue remains same)
        var output2:Number = pid.update(setPoint, actualValue, deltaTime);
        trace("After second update: " + pid.toString());
        assertAlmostEqual(output2, 15.16, 0.3, "Continuous update 2");

        // 第三更新
        var output3:Number = pid.update(setPoint, actualValue, deltaTime);
        trace("After third update: " + pid.toString());
        assertAlmostEqual(output3, 17.6, 0.3, "Continuous update 3");
    }

    // 不同 deltaTime 测试
    private function testDifferentDeltaTime():Void {
        trace("Testing different deltaTime values...");
        resetPID();

        pid.setKp(1.0);
        pid.setKi(1.0);
        pid.setKd(1.0);
        pid.setIntegralMax(100);
        pid.setDerivativeFilter(0.5);

        // Test with deltaTime = 0.5
        var output1:Number = pid.update(10, 8, 0.5); // error=2, integral=1, errorDiff=(2-0)/0.5=4
        // derivativePrev = 0 *0.5 +4*0.5=2
        // output=1*2 +1*1 +1*2=2 +1 +2=5
        assertAlmostEqual(output1, 5, 0.001, "Different deltaTime 0.5");

        // Test with deltaTime = 2
        var output2:Number = pid.update(10, 8, 2); // error=2, integral=1 +4=5, errorDiff=(2-2)/2=0
        // derivativePrev =2 *0.5 +0*0.5=1
        // output=1*2 +1*5 +1*1=2 +5 +1=8
        assertAlmostEqual(output2, 8, 0.001, "Different deltaTime 2");

        // Test with deltaTime = 0.1
        var output3:Number = pid.update(10, 8, 0.1); // error=2, integral=5 +0.2=5.2, errorDiff=(2-2)/0.1=0
        // derivativePrev =1 *0.5 +0 *0.5=0.5
        // output=1*2 +1*5.2 +1*0.5=2 +5.2 +0.5=7.7
        assertAlmostEqual(output3, 7.7, 0.001, "Different deltaTime 0.1");
    }

    // 积分限幅边界测试
    private function testIntegralLimits():Void {
        trace("Testing integral limits...");
        resetPID();

        pid.setKp(1.0);
        pid.setKi(1.0);
        pid.setKd(0.0);
        pid.setIntegralMax(10);

        // Accumulate integral beyond max
        pid.update(10, 0, 5); // error=10, integral=50 -> limited to 10
        var integral:Number = pid.getIntegral();
        assertEqual(integral, 10, "Integral max limit");

        // Accumulate integral beyond negative max
        pid.update(0, 10, 5); // error=-10, integral=-50 -> limited to -10
        integral = pid.getIntegral();
        assertEqual(integral, -10, "Integral min limit");
    }

    // 微分滤波系数不同值的测试
    private function testDerivativeFilters():Void {
        trace("Testing different derivative filters...");
        resetPID();

        pid.setKp(1.0);
        pid.setKi(0.0);
        pid.setKd(1.0);
        pid.setIntegralMax(100);
        
        // Test with derivativeFilter = 0.0 (no filtering)
        pid.setDerivativeFilter(0.0);
        var output1:Number = pid.update(10, 5, 1); // error=5, derivative=(5-0)/1=5
        // derivativePrev =0*1 +5*0=0
        // output=1*5 +0*0 +1*0=5
        assertAlmostEqual(output1, 5, 0.001, "Derivative filter 0.0");

        // Next update with derivativeFilter=0.0
        var output2:Number = pid.update(10, 6, 1); // error=4, derivative=(4-5)/1=-1
        // derivativePrev =0*1 +(-1)*0=0
        // output=1*4 +0*0 +1*0=4
        assertAlmostEqual(output2, 4, 0.001, "Derivative filter 0.0 second update");

        // Test with derivativeFilter = 0.5
        resetPID();
        pid.setDerivativeFilter(0.5);
        var output3:Number = pid.update(10, 5, 1); // error=5, derivative=(5-0)/1=5
        // derivativePrev =0*0.5 +5*0.5=2.5
        // output=1*5 +0*0 +1*2.5=5 +0 +2.5=7.5
        assertAlmostEqual(output3, 7.5, 0.001, "Derivative filter 0.5 first update");

        var output4:Number = pid.update(10, 6, 1); // error=4, derivative=(4-5)/1=-1
        // derivativePrev =2.5*0.5 + (-1)*0.5=1.25 -0.5=0.75
        // output=1*4 +0*0 +1*0.75=4 +0 +0.75=4.75
        assertAlmostEqual(output4, 4.75, 0.001, "Derivative filter 0.5 second update");

        // Test with derivativeFilter = 1.0
        resetPID();
        pid.setDerivativeFilter(1.0);
        var output5:Number = pid.update(10, 5, 1); // error=5, derivative=(5-0)/1=5
        // derivativePrev =0*0 +5*1=5
        // output=1*5 +0*0 +1*5=5 +0 +5=10
        assertAlmostEqual(output5, 10, 0.001, "Derivative filter 1.0 first update");

        var output6:Number = pid.update(10, 6, 1); // error=4, derivative=(4-5)/1=-1
        // derivativePrev =5*0 + (-1)*1=-1
        // output=1*4 +0*0 +1*(-1)=4 +0 -1=3
        assertAlmostEqual(output6, 3, 0.001, "Derivative filter 1.0 second update");
    }

    // 性能评估测试
    private function testPerformance():Void {
        trace("Testing performance...");
    
        var iterations:Number = 50000;
        var setPoint:Number = 50;
        var actualValue:Number = 40;
        var deltaTime:Number = 0.1;
        var result:Number;
    
        // 开始计时
        var startTime:Number = getTimer();
    
        // 手动展开循环，减少循环本身的开销
        for (var i:Number = 0; i < iterations; i += 5) {
            result = pid.update(setPoint, actualValue, deltaTime);
            result = pid.update(setPoint, actualValue, deltaTime);
            result = pid.update(setPoint, actualValue, deltaTime);
            result = pid.update(setPoint, actualValue, deltaTime);
            result = pid.update(setPoint, actualValue, deltaTime);
        }
    
        // 结束计时
        var endTime:Number = getTimer();
        var duration:Number = endTime - startTime;
    
        trace("Performance Test Duration: " + duration + "ms for " + iterations + " iterations.");
    
        // 性能基准验证
        assertTrue(duration < 500, "Performance benchmark < 500ms");
    }

    // 重置 PID 控制器状态
    private function resetPID():Void {
        pid.reset();
    }

    // 简单断言方法
    private function assertEqual(actual:Number, expected:Number, message:String):Void {
        if (actual != expected) {
            trace("[FAIL] " + message + " | Expected: " + expected + ", Actual: " + actual);
        } else {
            trace("[PASS] " + message);
        }
    }

    // 近似相等断言方法，适用于浮点数比较
    private function assertAlmostEqual(actual:Number, expected:Number, epsilon:Number, message:String):Void {
        if (Math.abs(actual - expected) > epsilon) {
            trace("[FAIL] " + message + " | Expected: " + expected + ", Actual: " + actual);
        } else {
            trace("[PASS] " + message);
        }
    }

    private function assertTrue(condition:Boolean, message:String):Void {
        if (!condition) {
            trace("[FAIL] " + message);
        } else {
            trace("[PASS] " + message);
        }
    }
}
