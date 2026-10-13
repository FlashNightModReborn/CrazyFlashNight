import org.flashNight.neur.ScheduleTimer.Task;

/** 稳定 Task 调度：短期直接槽链，长期索引堆。
 * 纯堆 FP20 压测增加了高频重排成本，短期任务保留 O(1) 入槽，不再引入节点池。
 * 保留旧调度的 coarse-deadline-v1：短期精确、秒/分钟向上量化；同帧 single/heap/second/third 顺序。
 * 不持有 TaskIDNode，不分配或回收池节点，不维护第二份 ID 注册表。
 */
class org.flashNight.neur.ScheduleTimer.CerberusScheduler {
    private var heap:Array;
    private var expired:Array;
    private var longExpired:Array;
    private var heads:Array;
    private var tails:Array;
    private var batching:Boolean;
    private var sortKeys:Array;
    private var sortFlags:Array;
    public var currentFrame:Number;
    private var orderCounter:Number;
    private var singleLimit:Number;
    private var secondSize:Number;
    private var thirdSize:Number;
    private var fps:Number;
    private var thirdPeriod:Number;
    public function CerberusScheduler() { initialize(150,60,60,30,0.1); }
    public function initialize(singleWheelSize:Number, secondsSize:Number, minutesSize:Number, framesPerSecond:Number, precisionThreshold:Number):Void {
        singleLimit=(singleWheelSize==undefined)?150:singleWheelSize;
        secondSize=(secondsSize==undefined)?60:secondsSize;
        thirdSize=(minutesSize==undefined)?60:minutesSize;
        fps=(framesPerSecond==undefined)?30:framesPerSecond;
        if(!isFinite(singleLimit)||singleLimit<1||!isFinite(secondSize)||secondSize<1||
            !isFinite(thirdSize)||thirdSize<1||!isFinite(fps)||fps<1) throw "Invalid scheduler dimensions";
        thirdPeriod=secondSize*fps;heap=[];expired=[];longExpired=[];heads=new Array(singleLimit);tails=new Array(singleLimit);batching=false;sortKeys=["due","lane","order"];sortFlags=[Array.NUMERIC,Array.NUMERIC,Array.NUMERIC];currentFrame=0;orderCounter=0;
    }
    public function advance():Void { currentFrame++; }
    public function scheduleTask(task:Task, delay:Number):Void {
        if(delay!==delay||delay==Infinity||delay==-Infinity) throw "Non-finite scheduler deadline";
        if(delay<1) delay=1;
        var requested:Number=currentFrame+delay;
        if(requested>9007199254740991) throw "Scheduler deadline exceeds exact Number range";
        // 先验证后离队：非法输入不能使仍有效的 Task 脱离所有权。
        if(task.heapIndex>=0||task.timedSlot>=0) removeTask(task);
        task.requestedDue=requested;
        var lane:Number=0;
        var due:Number=task.requestedDue;
        if(delay>=singleLimit) {
            var offset:Number=currentFrame%fps;
            var slots:Number=Math.ceil((delay+offset)/fps);
            if(slots<=secondSize) { lane=2;due=currentFrame-offset+slots*fps; }
            else {
                offset=currentFrame%thirdPeriod;
                slots=Math.ceil((delay+offset)/thirdPeriod);
                if(slots<=thirdSize) { lane=3;due=currentFrame-offset+slots*thirdPeriod; }
                else lane=1;
            }
        }
        task.due=due;task.lane=lane;task.order=++orderCounter;
        if(lane==0) {
            var slot:Number=(due-1)%singleLimit;var tail:Task=tails[slot]||null;
            task.timedSlot=slot;task.timedPrev=tail;task.timedNext=null;
            if(tail!=null)tail.timedNext=task;else heads[slot]=task;
            tails[slot]=task;return;
        }
        var index:Number=heap.length;heap[index]=task;task.heapIndex=index;
        if(!batching) siftUp(index);
    }
    public function removeTask(task:Task):Void {
        var slot:Number=task.timedSlot;
        if(slot>=0) {
            if(task.timedPrev!=null)task.timedPrev.timedNext=task.timedNext;else heads[slot]=task.timedNext;
            if(task.timedNext!=null)task.timedNext.timedPrev=task.timedPrev;else tails[slot]=task.timedPrev;
            task.timedPrev=null;task.timedNext=null;task.timedSlot=-1;return;
        }
        var index:Number=task.heapIndex;
        if(index<0||heap[index]!==task) return;
        var last:Task=heap[heap.length-1];heap.pop();task.heapIndex=-1;
        if(index<heap.length) {
            heap[index]=last;last.heapIndex=index;
            if(!batching) {
                var after:Number=siftUp(index);
                if(after==index) siftDown(index);
            }
        }
    }
    public function popDue():Task {
        if(heap.length==0||heap[0].due>currentFrame) return null;
        var task:Task=heap[0];var last:Task=heap[heap.length-1];heap.pop();task.heapIndex=-1;
        if(heap.length>0) {heap[0]=last;last.heapIndex=0;siftDown(0);}
        return task;
    }
    /** 本帧快照直接持有稳定 Task；短期 FIFO 在长期 heap/second/third 之前。 */
    public function beginFrame():Array {
        currentFrame++;expired.length=0;longExpired.length=0;
        var slot:Number=(currentFrame-1)%singleLimit;
        var task:Task=heads[slot];heads[slot]=null;tails[slot]=null;
        while(task!=null) {
            var next:Task=task.timedNext;
            task.timedPrev=null;task.timedNext=null;task.timedSlot=-1;
            expired.push(task);task=next;
        }
        while(longExpired.length<4&&(task=popDue())!=null) longExpired.push(task);
        if(longExpired.length>=4) {
            var data:Array=heap;var length:Number=data.length;var writeIndex:Number=0;var count:Number=longExpired.length;
            for(var i:Number=0;i<length;i++) {
                task=data[i];
                if(task.due<=currentFrame) {longExpired[count++]=task;task.heapIndex=-1;}
                else {data[writeIndex]=task;task.heapIndex=writeIndex++;}
            }
            data.length=writeIndex;longExpired.sortOn(sortKeys,sortFlags);batching=true;
        }
        for(var j:Number=0;j<longExpired.length;j++)expired.push(longExpired[j]);
        return expired;
    }
    public function endFrame():Void {
        // 外层异常中断时，尚未调用的快照项返回队列；不伪造 EventBus 后续回调已执行。
        for(var e:Number=0;e<expired.length;e++) {
            var pending:Task=expired[e];
            if(pending.active&&pending.state==1&&pending.heapIndex<0&&pending.timedSlot<0) {
                if(pending.lane==0) {
                    var slot:Number=currentFrame%singleLimit;var tail:Task=tails[slot]||null;
                    pending.timedPrev=tail;pending.timedNext=null;pending.timedSlot=slot;
                    if(tail!=null)tail.timedNext=pending;else heads[slot]=pending;tails[slot]=pending;
                } else {
                    var idx:Number=heap.length;heap[idx]=pending;pending.heapIndex=idx;if(!batching)siftUp(idx);
                }
            }
        }
        if(!batching) {expired.length=0;return;}
        // 自底向上恢复一次堆序，内联 Floyd sift，避免每个父节点的脚本调用。
        var data:Array=heap;var length:Number=data.length;
        for(var parent:Number=(length>>1)-1;parent>=0;parent--) {
            var index:Number=parent;var task:Task=data[index];
            while(true) {
                var child:Number=index*2+1;if(child>=length) break;
                var best:Task=data[child];var right:Number=child+1;
                if(right<length) {
                    var b:Task=data[right];
                    if(b.due<best.due||(b.due==best.due&&(b.lane<best.lane||
                        (b.lane==best.lane&&b.order<best.order)))) {child=right;best=b;}
                }
                if(task.due<best.due||(task.due==best.due&&(task.lane<best.lane||
                    (task.lane==best.lane&&task.order<=best.order)))) break;
                data[index]=best;best.heapIndex=index;index=child;
            }
            data[index]=task;task.heapIndex=index;
        }
        batching=false;expired.length=0;
    }
    private function siftUp(index:Number):Number {
        var data:Array=heap;var task:Task=data[index];
        while(index>0) {
            var parent:Number=(index-1)>>1;
            var other:Task=data[parent];
            if(task.due>other.due||(task.due==other.due&&(task.lane>other.lane||
                (task.lane==other.lane&&task.order>=other.order)))) break;
            data[index]=other;other.heapIndex=index;index=parent;
        }
        data[index]=task;task.heapIndex=index;return index;
    }
    private function siftDown(index:Number):Void {
        var data:Array=heap;var length:Number=data.length;var task:Task=data[index];
        while(true) {
            var child:Number=index*2+1;if(child>=length) break;
            var best:Task=data[child];var right:Number=child+1;
            if(right<length) {
                var b:Task=data[right];
                if(b.due<best.due||(b.due==best.due&&(b.lane<best.lane||
                    (b.lane==best.lane&&b.order<best.order)))) {child=right;best=b;}
            }
            if(task.due<best.due||(task.due==best.due&&(task.lane<best.lane||
                (task.lane==best.lane&&task.order<=best.order)))) break;
            data[index]=best;best.heapIndex=index;index=child;
        }
        data[index]=task;task.heapIndex=index;
    }
    public function clear():Void {
        for(var i:Number=0;i<heap.length;i++) heap[i].heapIndex=-1;
        for(var slot:Number=0;slot<singleLimit;slot++) {
            var task:Task=heads[slot];
            while(task!=null) {var next:Task=task.timedNext;task.timedSlot=-1;task.timedPrev=null;task.timedNext=null;task=next;}
        }
        heap.length=0;expired.length=0;longExpired.length=0;heads=new Array(singleLimit);tails=new Array(singleLimit);batching=false;currentFrame=0;
    }
    public function getHeapSize():Number { return heap.length; }
    public function getShortSize():Number {
        var count:Number=0;
        for(var i:Number=0;i<singleLimit;i++) {var task:Task=heads[i];while(task!=null){count++;task=task.timedNext;}}
        return count;
    }
    /** 冷诊断：验证索引一致性和所有父子键序，不进入每帧热路径。 */
    public function validateHeap():Boolean {
        for(var i:Number=0;i<heap.length;i++) {
            var t:Task=heap[i];if(t.heapIndex!=i||!t.active) return false;
            if(i>0) {
                var p:Task=heap[(i-1)>>1];
                if(t.due<p.due||(t.due==p.due&&(t.lane<p.lane||(t.lane==p.lane&&t.order<p.order)))) return false;
            }
        }
        for(var slot:Number=0;slot<singleLimit;slot++) {
            var task:Task=heads[slot];var previous:Task=null;var visited:Number=0;
            while(task!=null) {
                if(task.timedSlot!=slot||task.timedPrev!==previous||task.heapIndex!=-1||!task.active||visited++>100000) return false;
                previous=task;task=task.timedNext;
            }
            if(previous!==tails[slot]&&!(previous==null&&tails[slot]==null))return false;
        }
        return true;
    }
}
