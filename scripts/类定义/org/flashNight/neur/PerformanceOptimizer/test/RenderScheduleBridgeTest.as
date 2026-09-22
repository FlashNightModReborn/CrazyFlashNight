import org.flashNight.neur.PerformanceOptimizer.*;
class org.flashNight.neur.PerformanceOptimizer.test.RenderScheduleBridgeTest {
    private static var passed:Number;
    private static var failed:Number;
    private static function check(value:Boolean,name:String):Void {
        if(value) passed++; else { failed++; trace("FAIL RenderScheduleBridgeTest: "+name); }
    }
    public static function runAllTests():Void {
        passed=0; failed=0;
        var sampler:IntervalSampler=new IntervalSampler(30);
        sampler.resetInterval(0,1);
        check(!sampler.observe(100),"window not due before 500ms");
        sampler.observe(200); sampler.observe(300); sampler.observe(400);
        check(sampler.observe(500),"5fps-like pressure does not wait 60 frames");
        check(sampler.sampleFrames==5 && sampler.sampleDurationMs==500,"actual count and elapsed time");
        check(sampler.longFrames==0,"100ms is not greater than long-frame boundary");
        sampler.resetInterval(500,0);
        sampler.observe(650); sampler.observe(1000);
        check(sampler.longFrames==2 && sampler.maxFrameMs==350,"long frames aggregate without per-frame log");
        sampler.resetInterval(0,0);
        sampler.observe(40); sampler.observe(80);
        check(!sampler.observe(1) && sampler.sampleFrames==0,"clock rollback resets observation");
        var root:Object={_quality:"MEDIUM", 暂停:false};
        var scheduler:PerformanceScheduler=new PerformanceScheduler({},30,26,"MEDIUM",{root:root});
        var mock:Object={count:0,setPresetQuality:function(q:String):Void {},apply:function(t:Number,u:Number,q:String):Void {this.count++;this.lastTier=t;this.lastQuality=q;}};
        scheduler.setActuator(mock);
        scheduler.applyFromLauncher(1,0.5,"LOW",1,0);
        check(scheduler.isRemoteControlled() && scheduler.getPerformanceLevel()==1,"extended command applied");
        scheduler.applyFromLauncher(0,0,"MEDIUM",2,9);
        check(mock.count==1,"other scene rejected");
        scheduler.applyFromLauncher(0,0,"MEDIUM",0,0);
        check(mock.count==1,"invalid command identity rejected");
        scheduler.applyFromLauncher(0,0,"MEDIUM",2,0);
        check(mock.count==2 && scheduler.getPerformanceLevel()==0,"new command applies");
        scheduler.applyFromLauncher(1,1,"LOW",1,0);
        check(mock.count==2,"late command rejected");
        scheduler.applyFromLauncher(0,0,"MEDIUM",2,0);
        check(mock.count==2,"same command idempotent");
        scheduler.applyFromLauncher(1,1,"LOW",3,0);
        scheduler.onSceneChanged();
        check(scheduler.getPerformanceLevel()==1,"scene retains current performance level");
        scheduler.applyFromLauncher(0,0,"MEDIUM",4,0);
        check(scheduler.getPerformanceLevel()==1,"pre-scene command cannot restore quality");
        scheduler.applyFromLauncher(0,0,"MEDIUM",4,1);
        check(scheduler.getPerformanceLevel()==0,"current-scene command accepted");
        scheduler.applyFromLauncher(1,2,"LOW",5,1);
        check(scheduler.getPerformanceLevel()==0,"out of range soft budget rejected");
        var legacy:String = org.flashNight.neur.PerformanceOptimizer.test.PerformanceSchedulerTest.runAllTests();
        check(legacy.indexOf(String.fromCharCode(10007)) < 0, "legacy remote/fallback/hold compatibility");
        trace(legacy);
        trace("RenderScheduleBridgeTest Tests Passed: "+passed);
        trace("RenderScheduleBridgeTest Tests Failed: "+failed);
    }
}