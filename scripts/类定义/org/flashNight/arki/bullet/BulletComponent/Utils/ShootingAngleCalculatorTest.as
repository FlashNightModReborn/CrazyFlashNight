/**
 * 测试 ShootingAngleCalculator 的测试类
 */
class org.flashNight.arki.bullet.BulletComponent.Utils.ShootingAngleCalculatorTest {

    /**
     * 内部断言函数，判断实际结果与预期结果是否一致
     * @param actual 实际结果
     * @param expected 预期结果
     * @param message 测试说明
     */
    private static function assertEqual(actual:Number, expected:Number, message:String):Void {
        if (actual !== expected) {
            trace("Test FAILED: " + message + " | Expected: " + expected + ", Got: " + actual);
        } else {
            trace("Test PASSED: " + message);
        }
    }
    
    /**
     * 执行所有测试
     */
    public static function runTests():Void {
        var allPassed:Boolean = true;
        
        trace("---------- 开始单元测试 ----------");
        
        // 测试1：射手朝向左侧，子弹速度为正
        var obj:Object = { 角度偏移: 20, 子弹速度: 100 };
        var shooter:Object = { 方向: "左", _rotation: 10 };
        var result:Number = org.flashNight.arki.bullet.BulletComponent.Utils.ShootingAngleCalculator.calculate(obj, shooter);
        // 计算过程：返回值 = 180 + 10 + (-20) = 170
        if(result !== 170) { allPassed = false; }
        assertEqual(result, 170, "射手左侧，子弹速度正（角度偏移20 -> -20）");
        // 检查角度偏移的副作用
        if(obj["角度偏移"] !== -20) {
            trace("Test FAILED: Test1 角度偏移副作用错误，预期 -20，实际 " + obj["角度偏移"]);
            allPassed = false;
        } else {
            trace("Test PASSED: Test1 角度偏移副作用正确");
        }
        
        // 测试2：射手朝向左侧，子弹速度为负
        obj = { 角度偏移: 30, 子弹速度: -50 };
        shooter = { 方向: "左", _rotation: 15 };
        result = org.flashNight.arki.bullet.BulletComponent.Utils.ShootingAngleCalculator.calculate(obj, shooter);
        // 此时：(true ^ true) => false，返回值 = shooter._rotation + angleOffset = 15 + 30 = 45
        if(result !== 45) { allPassed = false; }
        assertEqual(result, 45, "射手左侧，子弹速度负（不反转角度偏移）");
        // 检查子弹速度反转副作用
        if(obj["子弹速度"] !== 50) {
            trace("Test FAILED: Test2 子弹速度副作用错误，预期 50，实际 " + obj["子弹速度"]);
            allPassed = false;
        } else {
            trace("Test PASSED: Test2 子弹速度副作用正确");
        }
        
        // 测试3：射手非左侧（例如右），子弹速度为正
        obj = { 角度偏移: 10, 子弹速度: 80 };
        shooter = { 方向: "右", _rotation: 5 };
        result = org.flashNight.arki.bullet.BulletComponent.Utils.ShootingAngleCalculator.calculate(obj, shooter);
        // 条件：(false ^ false) => false，返回值 = 5 + 10 = 15
        if(result !== 15) { allPassed = false; }
        assertEqual(result, 15, "射手右侧，子弹速度正");
        
        // 测试4：射手非左侧，子弹速度为负
        obj = { 角度偏移: -15, 子弹速度: -90 };
        shooter = { 方向: "右", _rotation: -20 };
        result = org.flashNight.arki.bullet.BulletComponent.Utils.ShootingAngleCalculator.calculate(obj, shooter);
        // 条件：(false ^ true) => true，返回值 = 180 + (-20) + ( -(-15) ) = 160 + 15 = 175
        if(result !== 175) { allPassed = false; }
        assertEqual(result, 175, "射手右侧，子弹速度负（角度偏移-15 -> 15）");
        // 检查角度偏移副作用
        if(obj["角度偏移"] !== 15) {
            trace("Test FAILED: Test4 角度偏移副作用错误，预期 15，实际 " + obj["角度偏移"]);
            allPassed = false;
        } else {
            trace("Test PASSED: Test4 角度偏移副作用正确");
        }
        
        // 测试5：角度偏移未定义时应默认为0（射手右侧，子弹速度正）
        obj = { 子弹速度: 50 };  // 未定义角度偏移，按位或后结果为 0
        shooter = { 方向: "右", _rotation: 30 };
        result = org.flashNight.arki.bullet.BulletComponent.Utils.ShootingAngleCalculator.calculate(obj, shooter);
        // 返回值 = 30 + 0 = 30
        if(result !== 30) { allPassed = false; }
        assertEqual(result, 30, "角度偏移未定义时，默认0（射手右侧，子弹速度正）");
        
        // 测试6：角度偏移未定义时，射手左侧且子弹速度负（子弹速度反转）
        obj = { 子弹速度: -70 };  // 未定义角度偏移 -> 0
        shooter = { 方向: "左", _rotation: 40 };
        result = org.flashNight.arki.bullet.BulletComponent.Utils.ShootingAngleCalculator.calculate(obj, shooter);
        // 条件：(true ^ true) => false，返回值 = 40 + 0 = 40
        if(result !== 40) { allPassed = false; }
        assertEqual(result, 40, "角度偏移未定义时（射手左侧，子弹速度负）");
        // 检查子弹速度反转副作用
        if(obj["子弹速度"] !== 70) {
            trace("Test FAILED: Test6 子弹速度副作用错误，预期 70，实际 " + obj["子弹速度"]);
            allPassed = false;
        } else {
            trace("Test PASSED: Test6 子弹速度副作用正确");
        }
        
        trace("---------- 单元测试结束 ----------");
        
        // 性能评测模块
        trace("---------- 开始性能测试 ----------");
        var iterations:Number = 100000;
        var dummyObj:Object;
        var dummyShooter:Object;
        var dummyResult:Number;
        // 预热循环
        for (var i:Number = 0; i < 1000; i++) {
            dummyObj = { 角度偏移: i % 50, 子弹速度: (i % 2 == 0 ? 100 : -100) };
            dummyShooter = { 方向: (i % 2 == 0 ? "左" : "右"), _rotation: i % 360 };
            dummyResult = org.flashNight.arki.bullet.BulletComponent.Utils.ShootingAngleCalculator.calculate(dummyObj, dummyShooter);
        }
        
        var startTime:Number = getTimer();
        // 使用循环展开减少循环体的开销
        var unrollFactor:Number = 10;
        var limit:Number = iterations - (iterations % unrollFactor);
        var j:Number = 0;
        while(j < limit) {
            // 共展开 unrollFactor 次调用
            dummyObj = { 角度偏移: 5, 子弹速度: -80 };
            dummyShooter = { 方向: "左", _rotation: 20 };
            dummyResult = org.flashNight.arki.bullet.BulletComponent.Utils.ShootingAngleCalculator.calculate(dummyObj, dummyShooter);
            
            dummyObj = { 角度偏移: 5, 子弹速度: 80 };
            dummyShooter = { 方向: "右", _rotation: 20 };
            dummyResult = org.flashNight.arki.bullet.BulletComponent.Utils.ShootingAngleCalculator.calculate(dummyObj, dummyShooter);
            
            dummyObj = { 角度偏移: 10, 子弹速度: -50 };
            dummyShooter = { 方向: "左", _rotation: 30 };
            dummyResult = org.flashNight.arki.bullet.BulletComponent.Utils.ShootingAngleCalculator.calculate(dummyObj, dummyShooter);
            
            dummyObj = { 角度偏移: 10, 子弹速度: 50 };
            dummyShooter = { 方向: "右", _rotation: 30 };
            dummyResult = org.flashNight.arki.bullet.BulletComponent.Utils.ShootingAngleCalculator.calculate(dummyObj, dummyShooter);
            
            dummyObj = { 角度偏移: 0, 子弹速度: -100 };
            dummyShooter = { 方向: "左", _rotation: 0 };
            dummyResult = org.flashNight.arki.bullet.BulletComponent.Utils.ShootingAngleCalculator.calculate(dummyObj, dummyShooter);
            
            dummyObj = { 角度偏移: 0, 子弹速度: 100 };
            dummyShooter = { 方向: "右", _rotation: 0 };
            dummyResult = org.flashNight.arki.bullet.BulletComponent.Utils.ShootingAngleCalculator.calculate(dummyObj, dummyShooter);
            
            dummyObj = { 角度偏移: -5, 子弹速度: -60 };
            dummyShooter = { 方向: "右", _rotation: -10 };
            dummyResult = org.flashNight.arki.bullet.BulletComponent.Utils.ShootingAngleCalculator.calculate(dummyObj, dummyShooter);
            
            dummyObj = { 角度偏移: -5, 子弹速度: 60 };
            dummyShooter = { 方向: "左", _rotation: -10 };
            dummyResult = org.flashNight.arki.bullet.BulletComponent.Utils.ShootingAngleCalculator.calculate(dummyObj, dummyShooter);
            
            dummyObj = { 角度偏移: 15, 子弹速度: -30 };
            dummyShooter = { 方向: "右", _rotation: 45 };
            dummyResult = org.flashNight.arki.bullet.BulletComponent.Utils.ShootingAngleCalculator.calculate(dummyObj, dummyShooter);
            
            dummyObj = { 角度偏移: 15, 子弹速度: 30 };
            dummyShooter = { 方向: "左", _rotation: 45 };
            dummyResult = org.flashNight.arki.bullet.BulletComponent.Utils.ShootingAngleCalculator.calculate(dummyObj, dummyShooter);
            
            j += unrollFactor;
        }
        var endTime:Number = getTimer();
        trace("性能测试：执行 " + iterations + " 次计算耗时 " + (endTime - startTime) + " 毫秒");
        trace("---------- 性能测试结束 ----------");
        
        if (allPassed) {
            trace("所有测试均通过！");
        } else {
            trace("存在测试未通过，请检查日志信息。");
        }
    }
}
