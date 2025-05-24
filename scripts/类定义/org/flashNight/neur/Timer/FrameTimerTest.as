import org.flashNight.neur.Timer.*;

class org.flashNight.neur.Timer.FrameTimerTest {
    public function FrameTimerTest() {
        trace("开始测试优化版FrameTimer...");
        this.testSingleton();
        this.taskLifecycle();
        this.performanceTest();
        trace("测试完成");
    }
    
    private function testSingleton():Void {
        var t1:FrameTimer = FrameTimer.getInstance();
        var t2:FrameTimer = FrameTimer.getInstance();
        trace("单例测试:" + (t1 === t2 ? "✅" : "❌"));
    }
    
    private function taskLifecycle():Void {
        var timer:FrameTimer = FrameTimer.getInstance();
        var log:Array = [];
        
        // 定义任务（通过单例直接获取counter）
        function taskA():Void { 
            log.push("A" + FrameTimer.getInstance().counter); 
        }
        function taskB():Void { 
            log.push("B" + FrameTimer.getInstance().counter); 
        }
        
        // 重置计数器
        timer.counter = 0;
        
        // 添加任务
        timer.addTask(taskA);
        timer.addTask(taskB);
        timer.update(); // 执行后counter=1
        
        // 移除任务
        timer.removeTask(taskA);
        timer.update(); // 执行后counter=2
        
        var expected = ["A1","B1","B2"];
        trace("任务生命周期:" + (compareArrays(log, expected) ? "✅" : "❌"));
    }
    
    private function performanceTest():Void {
        var timer:FrameTimer = FrameTimer.getInstance();
        var testCount:Number = 1000;
        
        // 性能测试
        var start:Number = getTimer();
        for(var i:Number = 0; i < testCount; i++){
            timer.addTask(function(){});
        }
        var addTime:Number = getTimer() - start;
        
        start = getTimer();
        timer.update();
        var updateTime:Number = getTimer() - start;
        
        trace("性能指标: 添加 " + testCount + " 任务耗时: " + addTime + "ms, 执行 " + testCount + " 任务耗时: " + updateTime + "ms");
    }
    
    private static function compareArrays(a:Array, b:Array):Boolean {
        if(a.length != b.length) return false;
        for(var i:Number = 0; i < a.length; i++){
            if(a[i] !== b[i]) return false;
        }
        return true;
    }
    
    public static function run():Void {
        new FrameTimerTest();
    }
}