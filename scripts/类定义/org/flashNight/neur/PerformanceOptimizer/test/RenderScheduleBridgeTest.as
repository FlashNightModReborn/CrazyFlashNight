import org.flashNight.neur.PerformanceOptimizer.*;
import org.flashNight.neur.PerformanceOptimizer.test.*;
import org.flashNight.arki.scene.StageEvent;

/** Host 性能桥 focused suite：实测采样、执行确认与旧关卡入口退休。 */
class org.flashNight.neur.PerformanceOptimizer.test.RenderScheduleBridgeTest {
    private static var passed:Number;
    private static var failed:Number;
    private static function check(value:Boolean,name:String):Void {
        if(value) passed++; else {failed++;trace("FAIL RenderScheduleBridgeTest: "+name);}
    }
    public static function runAllTests():Void {
        passed=0; failed=0;
        var sampler:IntervalSampler=new IntervalSampler(30);
        sampler.resetInterval(0,1);
        check(!sampler.observe(100),"window not due before 500ms");
        sampler.observe(200); sampler.observe(300); sampler.observe(400);
        check(sampler.observe(500),"low FPS does not wait 60 frames");
        check(sampler.sampleFrames==5 && sampler.sampleDurationMs==500,"actual count and elapsed time");
        check(sampler.longFrames==0,"100ms is not greater than long-frame boundary");
        sampler.resetInterval(500,0);
        sampler.observe(650); sampler.observe(1000);
        check(sampler.longFrames==2 && sampler.maxFrameMs==350,"long frames aggregate without per-frame log");
        sampler.resetInterval(0,0);
        sampler.observe(40); sampler.observe(80);
        check(!sampler.observe(1) && sampler.sampleFrames==0,"clock rollback resets observation");

        trace(PerformanceSchedulerTest.runAllTests());
        passed+=PerformanceSchedulerTest.getPassedCount(); failed+=PerformanceSchedulerTest.getFailedCount();
        trace(PerformanceActuatorTest.runAllTests());
        passed+=PerformanceActuatorTest.getPassedCount(); failed+=PerformanceActuatorTest.getFailedCount();
        testLegacyStageMessages();
        trace("RenderScheduleBridgeTest Tests Passed: "+passed);
        trace("RenderScheduleBridgeTest Tests Failed: "+failed);
    }

    private static function testLegacyStageMessages():Void {
        var previousTimer:Object=_root.帧计时器;
        var previousMessage:Function=_root.最上层发布文字提示;
        var previousTestMessage:Object=_root.__performanceTestMessage;
        var timer:Object={count:0,
            手动设置性能等级:function():Void {this.count++;},
            降低性能等级:function():Void {this.count++;},
            提升性能等级:function():Void {this.count++;}};
        _root.帧计时器=timer;
        _root.最上层发布文字提示=function(value:String):Void {this.__performanceTestMessage=value;};
        var actions:Array=["SetLevel","Decrease","Increase"];
        for(var i:Number=0;i<actions.length;i++) {
            var event:StageEvent=new StageEvent({EventName:"Start",PerformanceControl:{
                Action:actions[i],Level:1,Steps:1,Duration:10,Message:"保留关卡提示"}});
            _root.__performanceTestMessage=null;
            event.execute();
            check(timer.count==0 && _root.__performanceTestMessage=="保留关卡提示",
                "legacy "+actions[i]+" retains message without scheduling");
        }
        _root.帧计时器=previousTimer;
        _root.最上层发布文字提示=previousMessage;
        _root.__performanceTestMessage=previousTestMessage;
    }
}
