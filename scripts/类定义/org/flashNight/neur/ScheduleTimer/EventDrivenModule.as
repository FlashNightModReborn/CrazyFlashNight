import org.flashNight.neur.EventBus.EventBus;
import org.flashNight.neur.ScheduleTimer.TaskManager;
import org.flashNight.neur.ScheduleTimer.ScheduleManager;
import org.flashNight.neur.ScheduleTimer.TaskExecutor;

class org.flashNight.neur.ScheduleTimer.EventDrivenModule {
    private var eventBus:EventBus;
    private var taskManager:TaskManager;
    private var scheduleManager:ScheduleManager;
    private var taskExecutor:TaskExecutor;

    // 构造函数，初始化模块间依赖
    public function EventDrivenModule(eventBus:EventBus, taskManager:TaskManager, scheduleManager:ScheduleManager, taskExecutor:TaskExecutor) {
        this.eventBus = eventBus;
        this.taskManager = taskManager;
        this.scheduleManager = scheduleManager;
        this.taskExecutor = taskExecutor;
        this.initialize();
    }

    // 初始化，订阅帧更新事件
    private function initialize():Void {
        this.eventBus.subscribe("FRAME_UPDATE", Delegate.create(this, this.onFrameUpdate));
    }

    // 帧更新事件处理
    private function onFrameUpdate():Void {
        var expiredTasks:TaskIDLinkedList = this.scheduleManager.tick();

        if (expiredTasks != null) {
            var node:TaskIDNode = expiredTasks.getFirst();
            while (node != null) {
                var taskID:Number = Number(node.taskID);
                var task:Task = this.taskManager.getTask(taskID);
                if (task) {
                    this.taskExecutor.executeTaskSafely(task);
                    this.taskExecutor.handleTaskCompletion(task, this.taskManager, this.scheduleManager);
                }
                node = node.next;
            }
        }

        // 处理零帧任务
        for (var taskID in this.taskManager.zeroFrameTasks) {
            var zeroFrameTask:Task = this.taskManager.zeroFrameTasks[taskID];
            this.taskExecutor.executeTaskSafely(zeroFrameTask);
            this.taskExecutor.handleTaskCompletion(zeroFrameTask, this.taskManager, this.scheduleManager);
        }
    }
}
