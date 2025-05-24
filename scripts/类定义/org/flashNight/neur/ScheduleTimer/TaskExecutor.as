class org.flashNight.neur.ScheduleTimer.TaskExecutor {
    // 执行任务的安全方法
    public function executeTaskSafely(task:Task):Void {
        try {
            task.execute();
        } catch (error:Error) {
            trace("Error executing task ID " + task.id + ": " + error.message);
            // 根据需求决定是否移除任务或记录错误
        }
    }

    // 处理任务完成状态
    public function handleTaskCompletion(task:Task, taskManager:TaskManager, scheduleManager:ScheduleManager):Void {
        if (task.remainingRepeats !== true) {
            task.remainingRepeats--;
        }

        if (task.isComplete()) {
            taskManager.removeTask(task.id);
        } else {
            scheduleManager.rescheduleTask(task.id, task.intervalFrames);
        }
    }
}
