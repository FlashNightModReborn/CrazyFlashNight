/** 稳定任务身份。队列直接持有本对象，取消或重排不复用其他任务的存储。 */
class org.flashNight.neur.ScheduleTimer.Task {
    public var id:String;
    public var intervalFrames:Number;
    public var repeatCount;
    public var pendingFrames:Number;
    public var parameters:Array;
    public var action:Function;
    public var scope:Object;
    public var due:Number;
    public var requestedDue:Number;
    public var order:Number;
    public var lane:Number;
    public var heapIndex:Number;
    public var timedPrev:Task;
    public var timedNext:Task;
    public var timedSlot:Number;
    public var state:Number; // 0 removed, 1 timed, 2 zero, 3 paused
    public var active:Boolean;
    public var generation:Number;
    public var nextChanged:Boolean;
    public var zeroPrev:Task;
    public var zeroNext:Task;
    public var ownerLabels:Object;
    public function Task(id:String, intervalFrames:Number, repeatCount) {
        this.id=id;this.intervalFrames=intervalFrames;
        this.repeatCount=(repeatCount==null)?1:repeatCount;
        pendingFrames=intervalFrames;heapIndex=-1;timedSlot=-1;timedPrev=null;timedNext=null;state=0;active=true;nextChanged=false;
        zeroPrev=null;zeroNext=null;ownerLabels=null;
    }
    public function toString():String {
        return "[Task id="+id+" interval="+intervalFrames+" repeat="+repeatCount+
            " pending="+pendingFrames+" due="+due+" state="+state+"]";
    }
}
