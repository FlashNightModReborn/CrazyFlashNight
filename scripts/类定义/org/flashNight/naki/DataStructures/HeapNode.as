import org.flashNight.naki.DataStructures.*;

class org.flashNight.naki.DataStructures.HeapNode extends TaskNode {
    public var priority:Number;

    public function HeapNode(taskID:String, priority:Number) {
        super(taskID);
        this.priority = priority;
    }

    public function toString():String {
        return "HeapNode [taskID=" + this.taskID + ", priority=" + this.priority + "]";
    }
}