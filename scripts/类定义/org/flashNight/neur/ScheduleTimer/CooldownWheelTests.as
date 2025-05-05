import org.flashNight.neur.ScheduleTimer.*;

/**
CooldownWheelTests.as
——————————————————————————————————————————
冷却时间轮测试类，验证各种技能冷却场景

时间轮的实际行为：
- pos 初始化为 119
- tick() 先移动 pos，再执行当前槽
- delay=1 和 delay=0 的任务都在下一次 tick 时执行（均放入同一槽位）
- delay>1 的任务在第 delay 次 tick 时执行
*/
class org.flashNight.neur.ScheduleTimer.CooldownWheelTests {
    /** 断言工具 */
    private function assert(condition:Boolean, message:String):Void {
        if (!condition) {
            throw new Error("断言失败: " + message);
        }
    }
    
    /** 运行所有测试 */
    public function runAllTests():Void {
        trace("开始运行冷却时间轮测试...");
        
        try {
            testSingleSkillCooldown();
            testMultipleSkillsConcurrent();
            testImmediateExecution();
            testLongDelayWrapping();
            testNegativeDelay();
            testZeroFrameHandling();
            testPerformanceStress();
            testTimeWheelIntegrity();
            
            // 游戏场景测试
            testGameScenarios();
            
            trace("✅ 所有测试通过！");
        } catch (e:Error) {
            trace("❌ 测试失败: " + e.toString());
        }
    }
    
    /** 测试1: 单个技能冷却 */
    private function testSingleSkillCooldown():Void {
        trace("- 测试单个技能冷却...");
        var wheel:CooldownWheel = CooldownWheel.I();
        wheel.reset();
        
        var count:Number = 0;
        // delay=5 表示在第 5 次 tick 时执行
        wheel.add(5, function() {
            count++;
        });
        
        // 模拟 5 帧（不是 6 帧）
        for (var i:Number = 0; i < 5; i++) {
            wheel.tick();
        }
        
        assert(count == 1, "delay=5 的任务应在第 5 次 tick 时执行");
    }
    
    /** 测试2: 多个技能并发冷却 */
    private function testMultipleSkillsConcurrent():Void {
        trace("- 测试多个技能并发冷却...");
        var wheel:CooldownWheel = CooldownWheel.I();
        wheel.reset();
        
        var counts:Array = [0, 0, 0];
        // 同时添加3个不同延迟的任务
        wheel.add(2, function() { counts[0]++; });
        wheel.add(5, function() { counts[1]++; });
        wheel.add(10, function() { counts[2]++; });
        
        // 运行 10 帧
        for (var i:Number = 0; i < 10; i++) {
            wheel.tick();
        }
        
        assert(counts[0] == 1, "第1个技能应在第2次tick时执行");
        assert(counts[1] == 1, "第2个技能应在第5次tick时执行");
        assert(counts[2] == 1, "第3个技能应在第10次tick时执行");
    }
    
    /** 测试3: 立即执行 */
    private function testImmediateExecution():Void {
        trace("- 测试立即执行场景...");
        var wheel:CooldownWheel = CooldownWheel.I();
        wheel.reset();
        
        var executeCount:Number = 0;
        // 负延迟测试
        wheel.add(-5, function() { executeCount++; });
        
        // 0延迟测试
        wheel.add(0, function() { executeCount++; });
        
        // 模拟1帧执行
        wheel.tick();
        
        assert(executeCount == 2, "负延迟和0延迟应在第1次tick时立即执行");
    }
    
    /** 测试4: 超长延迟环绕 */
    private function testLongDelayWrapping():Void {
        trace("- 测试超长延迟环绕处理...");
        var wheel:CooldownWheel = CooldownWheel.I();
        wheel.reset();
        
        var executeCount:Number = 0;
        // 延迟130帧 = 120 + 10，应该在第10次tick时执行
        wheel.add(130, function() { executeCount++; });
        
        // 模拟 10 帧
        for (var i:Number = 0; i < 10; i++) {
            wheel.tick();
        }
        
        assert(executeCount == 1, "超长延迟应正确环绕，在第10次tick时执行");
    }
    
    /** 测试5: 负延迟处理 */
    private function testNegativeDelay():Void {
        trace("- 测试负延迟边界情况...");
        var wheel:CooldownWheel = CooldownWheel.I();
        wheel.reset();
        
        var results:Array = [];
        // 测试各种负延迟
        for (var i:Number = -10; i <= -1; i++) {
            wheel.add(i, function() { results.push(1); });
        }
        
        // 执行一帧
        wheel.tick();
        
        assert(results.length == 10, "所有负延迟任务应在第1次tick时执行");
    }
    
    /** 测试6: 零帧处理 */
    private function testZeroFrameHandling():Void {
        trace("- 测试零帧边界处理...");
        var wheel:CooldownWheel = CooldownWheel.I();
        wheel.reset();
        
        var order:Array = [];
        // 添加到同一槽位的多个任务
        wheel.add(0, function() { order.push("Task1"); });
        wheel.add(0, function() { order.push("Task2"); });
        wheel.add(0, function() { order.push("Task3"); });
        
        wheel.tick();
        
        // 验证LIFO执行顺序
        assert(order[0] == "Task3" && order[1] == "Task2" && order[2] == "Task1", 
               "零帧任务应以LIFO顺序执行");
    }
    
    /** 测试7: 性能压力测试 */
    private function testPerformanceStress():Void {
        trace("- 性能压力测试...");
        var wheel:CooldownWheel = CooldownWheel.I();
        wheel.reset();
        
        var startTime:Number = getTimer();
        var execCount:Number = 0;
        
        // 添加1000个任务
        for (var i:Number = 0; i < 1000; i++) {
            wheel.add(i % 60, function() { execCount++; });
        }
        
        // 运行120帧
        for (var frame:Number = 0; frame < 120; frame++) {
            wheel.tick();
        }
        
        var duration:Number = getTimer() - startTime;
        trace("  执行1000个任务耗时: " + duration + "ms");
        
        assert(execCount == 1000, "所有任务应成功执行");
        assert(duration < 200, "性能应足够高效 (耗时" + duration + "ms)");
    }
    
    /** 测试8: 时间轮完整性 */
    private function testTimeWheelIntegrity():Void {
        trace("- 时间轮完整性测试...");
        var wheel:CooldownWheel = CooldownWheel.I();
        wheel.reset();
        
        var executionCounts:Array = new Array(120);
        for (var i:Number = 0; i < 120; i++) {
            executionCounts[i] = 0;
        }
        
        // 测试每个延迟值是否在正确的时机执行
        for (var delay:Number = 0; delay < 120; delay++) {
            wheel.add(delay, createCallback(executionCounts, delay));
        }
        
        // 运行120帧
        for (var frame:Number = 0; frame < 120; frame++) {
            wheel.tick();
        }
        
        // 验证每个延迟值都执行了一次
        for (var d:Number = 0; d < 120; d++) {
            assert(executionCounts[d] == 1, "延迟" + d + "的任务应执行一次");
        }
    }
    
    /** 工具方法：创建带上下文的回调 */
    private function createCallback(storage:Array, value):Function {
        return function() {
            storage[value]++;
        };
    }
    
    /** 模拟游戏场景测试 */
    public function testGameScenarios():Void {
        trace("\n开始游戏场景测试...");
        // 模拟技能冷却场景
        testSkillCooldownScenario();
        
        // 模拟连续技能释放
        testRapidSkillUsage();
        
        // 模拟长时间战斗
        testLongBattleScenario();
    }
    
    /** 测试9: 技能冷却场景模拟 */
    private function testSkillCooldownScenario():Void {
        trace("- 模拟技能冷却场景...");
        var wheel:CooldownWheel = CooldownWheel.I();
        wheel.reset();
        
        // 模拟3个技能的冷却系统
        var skill1_ready:Boolean = true;
        var skill2_ready:Boolean = true;
        var skill3_ready:Boolean = true;
        
        // 使用技能1（30帧冷却）
        if (skill1_ready) {
            skill1_ready = false;
            wheel.add(30, function() { skill1_ready = true; });
        }
        
        // 使用技能2（60帧冷却）
        if (skill2_ready) {
            skill2_ready = false;
            wheel.add(60, function() { skill2_ready = true; });
        }
        
        // 模拟运行61帧
        for (var i:Number = 0; i < 61; i++) {
            wheel.tick();
        }
        
        assert(skill1_ready == true, "技能1应在第30次tick后可用");
        assert(skill2_ready == true, "技能2应在第60次tick后可用");
        assert(skill3_ready == true, "技能3未使用应始终可用");
    }
    
    /** 测试10: 连续技能释放 */
    private function testRapidSkillUsage():Void {
        trace("- 测试连续技能释放...");
        var wheel:CooldownWheel = CooldownWheel.I();
        wheel.reset();
        
        var castCount:Number = 0;
        var skillReady:Boolean = true;
        
        // 模拟每20帧释放一次技能（30帧冷却）
        for (var frame:Number = 0; frame < 100; frame++) {
            // 每20帧尝试施法
            if (frame % 20 == 0 && skillReady) {
                skillReady = false;
                castCount++;
                // 30帧后重新可用
                wheel.add(30, function() { skillReady = true; });
            }
            
            wheel.tick();
        }
        
        // 只能施放3次（分别在frame 0, 40, 80），总共3次
        assert(castCount == 3, "应该施放3次技能 (实际: " + castCount + ")");
    }
    
    /** 测试11: 长时间战斗场景 */
    private function testLongBattleScenario():Void {
        trace("- 模拟长时间战斗场景...");
        var wheel:CooldownWheel = CooldownWheel.I();
        wheel.reset();
        
        var totalSkillCasts:Number = 0;
        
        // 模拟1000帧的战斗（约33秒）
        var skills:Array = [
            {ready: true, cooldown: 30},  // 普通攻击
            {ready: true, cooldown: 60},  // 特殊技能
            {ready: true, cooldown: 180}  // 终极技能
        ];
        
        for (var frame:Number = 0; frame < 1000; frame++) {
            // 模拟AI决策使用技能
            if (frame % 10 == 0) { // 每10帧尝试使用技能
                for (var i:Number = 0; i < skills.length; i++) {
                    var skill:Object = skills[i];
                    if (skill.ready && Math.random() < 0.5) {
                        skill.ready = false;
                        totalSkillCasts++;
                        wheel.add(skill.cooldown, createSkillReadyCallback(skill));
                    }
                }
            }
            wheel.tick();
        }
        
        trace("  总计释放技能次数: " + totalSkillCasts);
        assert(totalSkillCasts > 0, "长时间战斗应释放技能");
    }
    
    /** 技能准备完成回调 */
    private function createSkillReadyCallback(skill:Object):Function {
        return function() {
            skill.ready = true;
        };
    }
}