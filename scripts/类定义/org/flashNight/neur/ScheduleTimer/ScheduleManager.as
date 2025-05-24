import org.flashNight.naki.DataStructures.TaskIDNode;
import org.flashNight.naki.DataStructures.TaskIDLinkedList;

class org.flashNight.neur.ScheduleTimer.ScheduleManager {
    private var scheduleTimer:CerberusScheduler;

    // 构造函数，初始化调度器
    public function ScheduleManager(singleWheelSize:Number, multiLevelSecondsSize:Number, multiLevelMinutesSize:Number, frameRate:Number, precisionThreshold:Number) {
        this.scheduleTimer = new CerberusScheduler();
        this.scheduleTimer.initialize(singleWheelSize, multiLevelSecondsSize, multiLevelMinutesSize, frameRate, precisionThreshold);
    }

    // 调度任务，插入调度器
    public function scheduleTask(taskID:Number, intervalFrames:Number):TaskIDNode {
        return this.scheduleTimer.evaluateAndInsertTask(taskID, intervalFrames);
    }

    // 重新调度任务
    public function rescheduleTask(taskID:Number, intervalFrames:Number):Void {
        var taskNode:TaskIDNode = this.scheduleTimer.getTaskNode(taskID);
        if (taskNode) {
            this.scheduleTimer.rescheduleTaskByNode(taskNode, intervalFrames);
        }
    }

    // 移除任务
    public function removeTask(taskID:Number):Void {
        var taskNode:TaskIDNode = this.scheduleTimer.getTaskNode(taskID);
        if (taskNode) {
            this.scheduleTimer.removeTaskByNode(taskNode);
        }
    }

    // 获取到期的任务
    public function tick():TaskIDLinkedList {
        return this.scheduleTimer.tick();
    }

    // 销毁调度管理器
    public function destroy():Void {
        this.scheduleTimer.destroy();
    }
}
