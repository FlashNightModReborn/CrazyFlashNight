class org.flashNight.neur.ScheduleTimer.Task {
    public var id:Number;               // 任务ID
    public var action:Function;        // 任务执行函数
    public var delayFrames:Number;     // 延迟帧数
    public var repeat:Object;           // 重复次数，Number 或 Boolean
    public var currentDelay:Number;    // 当前剩余延迟帧数

    /**
     * 构造函数
     * @param id 任务ID
     * @param action 执行函数
     * @param delayFrames 延迟帧数
     * @param repeat 重复次数
     */
    public function Task(id:Number, action:Function, delayFrames:Number, repeat:Object) {
        this.id = id;
        this.action = action;
        this.delayFrames = delayFrames;
        this.repeat = (repeat == undefined) ? 1 : repeat;
        this.currentDelay = delayFrames;
    }
}
