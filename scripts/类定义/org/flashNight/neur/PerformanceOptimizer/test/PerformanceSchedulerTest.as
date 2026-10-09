import org.flashNight.neur.PerformanceOptimizer.PerformanceScheduler;

/** Host 唯一控制权、命令身份与执行确认的 AS2 行为测试。 */
class org.flashNight.neur.PerformanceOptimizer.test.PerformanceSchedulerTest {
    private static var passed:Number;
    private static var failed:Number;
    private static var report:String;

    private static function check(value:Boolean, name:String):Void {
        if (value) passed++; else failed++;
        report += (value ? "  ✓ " : "  ✗ ") + name + "\n";
    }
    public static function getPassedCount():Number { return passed; }
    public static function getFailedCount():Number { return failed; }

    public static function runAllTests():String {
        passed = 0; failed = 0; report = "=== PerformanceSchedulerTest ===\n";
        var root:Object = {_quality:"MEDIUM", 暂停:false};
        var host:Object = {性能等级上限:1, offsetTolerance:10};
        var scheduler:PerformanceScheduler = new PerformanceScheduler(host,30,26,"MEDIUM",{root:root});
        var actuator:Object = {
            root:root, scheduler:scheduler, count:0, fail:false, wrongQuality:false,
            apply:function(t:Number,u:Number,q:String):Boolean {
                this.count++;
                this.ackBefore = this.scheduler.getAppliedCommand();
                if (this.fail) return false;
                if (!this.wrongQuality) this.root._quality = q;
                return true;
            }
        };
        scheduler.setActuator(actuator);
        scheduler.applyFromLauncher(1,1,"LOW",1,0);
        check(actuator.count == 0,"连接之前不接收性能命令");
        scheduler.onTransportConnected();
        var epoch:Number = scheduler.getSceneEpoch();
        check(epoch == 1 && scheduler.getAppliedCommand() == 0,"连接建立新 epoch 且不虚构确认");
        scheduler.onTransportConnected();
        check(scheduler.getSceneEpoch() == epoch,"重复连接通知幂等");
        scheduler.applyFromLauncher(1,1);
        check(actuator.count == 0,"拒绝缺少身份的旧命令");
        scheduler.applyFromLauncher(0,0,"HIGH",7,epoch);
        check(root._quality == "HIGH" && scheduler.getPerformanceLevel() == 0,"显式 HIGH 不受旧 preset 或 cap 限制");
        check(actuator.ackBefore == 0 && scheduler.getAppliedCommand() == 7,"仅在执行后记录确认");
        var count:Number = actuator.count;
        scheduler.applyFromLauncher(0,0,"HIGH",7,epoch);
        check(actuator.count == count,"完全相同命令幂等");
        scheduler.applyFromLauncher(0,0.5,"HIGH",7,epoch);
        scheduler.applyFromLauncher(0,0,"BEST",7,epoch);
        check(actuator.count == count,"同一 command 不得改预算或画质");
        scheduler.applyFromLauncher(1,1,"LOW",6,epoch);
        check(actuator.count == count,"迟到命令不能覆盖新目标");
        scheduler.applyFromLauncher(0,0,"INVALID",8,epoch);
        scheduler.applyFromLauncher(2,0,"HIGH",8,epoch);
        scheduler.applyFromLauncher(0,0,"LOW",8,epoch);
        check(actuator.count == count,"拒绝非法画质或不一致 tier");
        scheduler.applyFromLauncher(0,0,"BEST",7.5,epoch);
        scheduler.applyFromLauncher(0,0,"BEST",Number("bad"),epoch);
        scheduler.applyFromLauncher(0,0,"BEST",Infinity,epoch);
        check(actuator.count == count,"命令编号必须是正有限整数");
        scheduler.applyFromLauncher(0,0,"BEST",8,epoch+1);
        check(actuator.count == count,"不同 epoch 的命令被拒绝");
        scheduler.applyFromLauncher(0,-0.1,"BEST",8,epoch);
        scheduler.applyFromLauncher(0,1.1,"BEST",8,epoch);
        scheduler.applyFromLauncher(0,Number("bad"),"BEST",8,epoch);
        scheduler.applyFromLauncher(0,Infinity,"BEST",8,epoch);
        check(actuator.count == count,"拒绝非法表现预算");
        scheduler.applyFromLauncher(1,1,"LOW",8,epoch);
        check(root._quality == "LOW" && scheduler.getLastAppliedSoftU() == 1,"完整降载目标执行");
        scheduler.onTransportDisconnected();
        count = actuator.count;
        check(!scheduler.isRemoteControlled() && root._quality == "LOW","断连保持最后有效画质");
        scheduler.applyFromLauncher(0,0,"BEST",9,epoch);
        check(actuator.count == count,"断连不接收命令");
        scheduler.getSampler().resetInterval(0,1);
        scheduler.evaluate(100000);
        check(actuator.count == count && scheduler.getPerformanceLevel() == 1,"极低 FPS 不触发 AS2 自主调档");
        scheduler.getSampler().resetInterval(0,1);
        for (var frame:Number=1; frame<100; frame++) scheduler.evaluate(frame*33);
        check(actuator.count == count && scheduler.getPerformanceLevel() == 1,"稳定高 FPS 不触发 AS2 自主恢复");
        check(scheduler.getActualFPS() > 29,"断连仍保留实测帧率采样");
        scheduler.onTransportConnected();
        check(scheduler.getSceneEpoch() == epoch+1 && scheduler.getAppliedCommand() == 0,"重连重置命令身份并推进 epoch");
        scheduler.applyFromLauncher(0,0,"HIGH",100,epoch);
        check(actuator.count == count,"重连后拒绝上个连接命令");
        epoch = scheduler.getSceneEpoch();
        scheduler.applyFromLauncher(0,0,"HIGH",1,epoch);
        check(scheduler.getAppliedCommand() == 1 && root._quality == "HIGH","新连接允许从 command 1 开始");
        scheduler.onSceneChanged();
        check(scheduler.getSceneEpoch() == epoch+1 && scheduler.getAppliedCommand() == 0,"换场隔离旧身份");
        check(scheduler.getPerformanceLevel() == 0 && root._quality == "HIGH","换场保留目标且不读旧 cap");
        count = actuator.count;
        scheduler.applyFromLauncher(1,1,"LOW",2,epoch);
        check(actuator.count == count,"换场后拒绝旧场景命令");
        epoch = scheduler.getSceneEpoch();
        scheduler.applyFromLauncher(0,0.5,"BEST",1,epoch);
        check(scheduler.getAppliedCommand() == 1 && root._quality == "BEST","当前场景完整目标可执行");
        actuator.fail = true;
        scheduler.applyFromLauncher(1,1,"LOW",2,epoch);
        check(scheduler.getAppliedCommand() == 1,"执行失败不确认新 command");
        count = actuator.count;
        actuator.fail = false;
        scheduler.applyFromLauncher(0,0,"HIGH",2,epoch);
        check(actuator.count == count,"失败身份也不能改成不同载荷");
        scheduler.applyFromLauncher(1,1,"LOW",2,epoch);
        check(scheduler.getAppliedCommand() == 2 && root._quality == "LOW","失败后只重试相同完整目标");
        actuator.wrongQuality = true;
        scheduler.applyFromLauncher(0,0,"HIGH",3,epoch);
        check(scheduler.getAppliedCommand() == 2,"执行器返回成功但真实画质不符时不确认");
        actuator.wrongQuality = false;
        scheduler.applyFromLauncher(0,0,"HIGH",3,epoch);
        check(scheduler.getAppliedCommand() == 3 && root._quality == "HIGH","真实画质就绪后确认");
        root._quality = "MEDIUM";
        scheduler.applyFromLauncher(0,0,"HIGH",3,epoch);
        check(root._quality == "HIGH","相同命令可修复执行后外部画质漂移");
        return report;
    }
}
