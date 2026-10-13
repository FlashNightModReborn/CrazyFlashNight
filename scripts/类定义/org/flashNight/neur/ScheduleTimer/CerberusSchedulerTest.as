/** 生产调度器的行为门入口；旧节点/时间轮专项保留在 dev.schedulerLegacy。 */
class org.flashNight.neur.ScheduleTimer.CerberusSchedulerTest {
    public static function runAllTests():Void { org.flashNight.dev.SchedulerDebtTest.runAllTests(); }
    public static function runOrderingContractTests():Void { org.flashNight.dev.SchedulerDebtTest.runOrderingTests(); }
}
