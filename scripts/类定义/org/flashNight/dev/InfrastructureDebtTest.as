/** 确定性 Flash 夹具：生产依赖收束与当前调度节点别名基线。 */
class org.flashNight.dev.InfrastructureDebtTest {
    private static var passed:Number;
    private static var failed:Number;
    private static function check(value:Boolean, name:String):Void {
        if (value) passed++; else { failed++; trace("[FAIL] InfrastructureDebt " + name); }
    }
    private static function schedulerProbe(mode:String):Void {
        var scheduler:org.flashNight.dev.schedulerLegacy.CerberusScheduler = new org.flashNight.dev.schedulerLegacy.CerberusScheduler();
        scheduler.initialize(150,60,60,30,0.1);
        var tm:Object = new org.flashNight.dev.schedulerLegacy.TaskManager(scheduler,30);
        var aid:String;
        var did:String;
        var aCalls:Number = 0;
        var dCalls:Number = 0;
        var dFrame:Number = 0;
        var frame:Number = 0;
        aid = tm.addTask(function():Void {
            aCalls++;
            if (mode == "cancel") tm.removeTask(aid);
            else if (mode == "delay") tm.delayTask(aid,300);
        },1,mode == "delay" ? true : 1,[]);
        var oldNode:Object = tm.taskTable[aid].node;
        tm.addTask(function():Void {
            did = tm.addTask(function():Void { dCalls++; dFrame=frame; },1000,1,[]);
        },1,1,[]);
        frame++; tm.updateFrame();
        var dTask:Object = tm.taskTable[did];
        if (mode == "cancel") {
            check(dTask != undefined && dTask.node === oldNode && dTask.node.list == null, "baseline self-cancel lost D queue");
        } else if (mode == "delay") {
            check(tm.taskTable[aid].node === dTask.node && dTask.node.taskID == did, "baseline self-delay aliases D");
        } else check(dTask.node.list != null, "control D remains queued");
        for (var i:Number=0;i<100;i++) { frame++; tm.updateFrame(); }
        if (mode == "cancel") check(dCalls==0 && tm.taskTable[did] != undefined, "baseline cancelled D stays orphaned");
        else if (mode == "delay") check(dCalls==1 && dFrame==11 && aCalls==1 && tm.taskTable[aid] != undefined, "baseline D moved early and A orphaned");
        else check(dCalls==1 && dFrame==31 && aCalls==1, "control exact single wheel");
        trace("InfrastructureSchedulerBaseline mode="+mode+" dCalls="+dCalls+" dFrame="+dFrame+" aCalls="+aCalls);
    }
    public static function runAllTests():Void {
        passed=0; failed=0;
        schedulerProbe("control"); schedulerProbe("cancel"); schedulerProbe("delay");
        var trees:org.flashNight.naki.DataStructures.TreeSetTest = new org.flashNight.naki.DataStructures.TreeSetTest();
        trees.runFunctionalTests();
        check(trees.getPassedCount()>0 && trees.getFailedCount()==0,"all five tree backend functional tests");
        var inventory:org.flashNight.arki.item.itemCollection.InventoryTest = new org.flashNight.arki.item.itemCollection.InventoryTest();
        inventory.runTests();
        check(inventory.getPassedCount()>0 && inventory.getFailedCount()==0,"inventory and injected AVL normalization");
        trace(org.flashNight.neur.PerformanceOptimizer.test.PerformanceActuatorTest.runAllTests());
        check(org.flashNight.neur.PerformanceOptimizer.test.PerformanceActuatorTest.getFailedCount()==0,"native performance budgets without display list");
        var report:String = org.flashNight.arki.item.equipment.EquipmentTestSuite.runAllTests();
        check(report.indexOf("✗")<0,"equipment tests remain independently callable");
        trace("InfrastructureDebtTest passed="+passed+" failed="+failed);
    }
}
