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

        // 基本 PID 输出测试
        var output:Number = pid.update(10, 5, 1);
        assertAlmostEqual(output, 12.6, 0.001, "Basic PID calculation"); // 预期输出：12.6
    }

    // 边界条件测试
    private function testBoundaryConditions():Void {
        trace("Testing boundary conditions...");
        resetPID();

        // 测试积分限幅
        pid.update(100, 0, 10); // 第一次更新
        pid.update(100, 0, 10); // 第二次更新，积分应被限制
        var integral:Number = pid.getIntegral();
        assertEqual(integral, 1000, "Integral windup prevention");

        // 测试 deltaTime <= 0 的情况
        var zeroDeltaTimeOutput:Number = pid.update(10, 5, 0);
        assertEqual(zeroDeltaTimeOutput, 0, "Zero deltaTime handling");

        // 测试负值 deltaTime
        var negativeDeltaTimeOutput:Number = pid.update(10, 5, -1);
        assertEqual(negativeDeltaTimeOutput, 0, "Negative deltaTime handling");
    }

    // 性能评估测试
    private function testPerformance():Void {
        trace("Testing performance...");

        var iterations:Number = 10000;
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
    }

    // 重置 PID 控制器状态
    private function resetPID():Void {
        pid.reset();
    }

    // 简单断言方法
    private function assertEqual(actual:Number, expected:Number, message:String):Void {
        if (actual != expected) {
            trace("[FAIL] " + message + " Expected: " + expected + ", Actual: " + actual);
        } else {
            trace("[PASS] " + message);
        }
    }

    // 近似相等断言方法，适用于浮点数比较
    private function assertAlmostEqual(actual:Number, expected:Number, epsilon:Number, message:String):Void {
        if (Math.abs(actual - expected) > epsilon) {
            trace("[FAIL] " + message + " Expected: " + expected + ", Actual: " + actual);
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
