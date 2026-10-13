class org.flashNight.dev.schedulerLegacy.TaskNode {
    public var taskID:String;

    public function TaskNode(taskID:String) {
        this.taskID = taskID;
    }

    public function toString():String {
        return "TaskNode [taskID=" + this.taskID + "]";
    }
}
