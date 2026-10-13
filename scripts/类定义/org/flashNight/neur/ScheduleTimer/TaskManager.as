import org.flashNight.neur.ScheduleTimer.*;
import org.flashNight.aven.Coordinator.EventCoordinator;

/** TaskManager：稳定身份、短期直接槽/长期索引堆与零阶段快照。
 * repeatCount 按真实调用递减；self-delay/upsert 只改变下一次调度。
 * coarse-deadline-v1 保留旧秒/分钟向上量化与 lane 顺序；不是精确截止期迁移。
 * 跨场景全局任务不自动清除。clear/destroy 才变更 generation 并中断旧分发栈。
 */
class org.flashNight.neur.ScheduleTimer.TaskManager {
    private var scheduleTimer:CerberusScheduler;
    private var taskTable:Object;
    private var zeroFrameTasks:Object;
    private var taskIdCounter:Number;
    private var framesPerMs:Number;
    private var zeroHead:Task;
    private var zeroTail:Task;
    private var zeroSnapshot:Array;
    private var dispatching:Boolean;
    private var currentTask:Task;
    private var generation:Number;
    private var alive:Boolean;
    private var lastFrameToken:Number;
    private var timedCount:Number;
    private var zeroCount:Number;
    private var pausedCount:Number;
    private var probe:Object;
    public function TaskManager(timer:CerberusScheduler, frameRate:Number) {
        if(timer==null||!isFinite(frameRate)||frameRate<=0) throw "Invalid TaskManager initialization";
        scheduleTimer=timer;framesPerMs=frameRate/1000;taskTable={};zeroFrameTasks={};
        taskIdCounter=0;zeroHead=null;zeroTail=null;zeroSnapshot=[];dispatching=false;currentTask=null;
        generation=1;alive=true;lastFrameToken=-Infinity;timedCount=0;zeroCount=0;pausedCount=0;probe=null;
    }
    private function toFrames(ms:Number):Number {
        if(ms==null) return 0;
        var value:Number=ms*framesPerMs;
        if(!isFinite(value)||value>9007199254740991-scheduleTimer.currentFrame) throw "Task interval must fit the exact Number deadline range";
        return Math.ceil(value);
    }
    private function invoke(action:Function, scope:Object, p:Array):Void {
        var n:Number=(p==null)?0:p.length;
        if(n==0) action.call(scope);
        else if(n==1) action.call(scope,p[0]);
        else if(n==2) action.call(scope,p[0],p[1]);
        else if(n==3) action.call(scope,p[0],p[1],p[2]);
        else if(n==4) action.call(scope,p[0],p[1],p[2],p[3]);
        else if(n==5) action.call(scope,p[0],p[1],p[2],p[3],p[4]);
        else action.apply(scope,p);
    }
    private function detach(task:Task):Void {
        if(task.state==1) {scheduleTimer.removeTask(task);timedCount--;delete taskTable[task.id];}
        else if(task.state==3) {pausedCount--;delete taskTable[task.id];}
        else if(task.state==2) {
            if(task.zeroPrev!=null) task.zeroPrev.zeroNext=task.zeroNext;else zeroHead=task.zeroNext;
            if(task.zeroNext!=null) task.zeroNext.zeroPrev=task.zeroPrev;else zeroTail=task.zeroPrev;
            task.zeroPrev=null;task.zeroNext=null;zeroCount--;delete zeroFrameTasks[task.id];
        }
        task.state=0;
    }
    private function route(task:Task):Void {
        var frames:Number=task.pendingFrames;
        if(frames<=0&&task.state==2) return; // 留表的 0→0 不换位
        detach(task);
        if(frames<=0) {
            task.state=2;zeroFrameTasks[task.id]=task;zeroCount++;
            task.zeroPrev=zeroTail;
            if(zeroTail!=null) zeroTail.zeroNext=task;else zeroHead=task;
            zeroTail=task;
        } else if(frames==Infinity) {task.state=3;taskTable[task.id]=task;pausedCount++;}
        else {task.state=1;taskTable[task.id]=task;timedCount++;scheduleTimer.scheduleTask(task,frames);}
    }
    private function requestRoute(task:Task):Void {
        if(task===currentTask) task.nextChanged=true;else route(task);
    }
    private function create(action:Function, interval:Number, repeatCount, parameters:Array, scope:Object):Task {
        if(!alive) throw "TaskManager is destroyed";
        var frames:Number=toFrames(interval);
        var task:Task=new Task(String(++taskIdCounter),frames,repeatCount);
        task.action=action;task.parameters=parameters;task.scope=scope;task.generation=generation;
        route(task);return task;
    }
    public function addTask(action:Function, interval:Number, repeatCount, parameters:Array):String {
        return create(action,interval,repeatCount,parameters,null).id;
    }
    public function addSingleTask(action:Function, interval:Number, parameters:Array):String {
        if(!alive) throw "TaskManager is destroyed";
        if(interval<=0) {invoke(action,null,parameters);return null;}
        return create(action,interval,1,parameters,null).id;
    }
    public function addLoopTask(action:Function, interval:Number, parameters:Array):String {
        return create(action,interval,true,parameters,null).id;
    }
    private function upsert(obj:Object, label:String, action:Function, interval:Number, parameters:Array, lifecycle:Boolean):Task {
        if(!obj) return null;
        if(!alive) throw "TaskManager is destroyed";
        var frames:Number=toFrames(interval);
        if(!obj.taskLabel) {obj.taskLabel={};_global.ASSetPropFlags(obj,["taskLabel"],1,false);}
        var task:Task=locateTask(String(obj.taskLabel[label]));
        // 陈旧 label 的 ID 不再复活；正常更新维持 Task 身份和 repeatCount。
        if(task==null||task.scope!==obj) {
            task=create(action,interval,lifecycle?true:1,parameters,obj);
            obj.taskLabel[label]=task.id;
        } else {
            task.action=action;task.parameters=parameters;task.scope=obj;task.intervalFrames=frames;
            if(lifecycle) task.repeatCount=true;
            task.pendingFrames=frames;requestRoute(task);
        }
        if(lifecycle) task.ownerLabels=obj.taskLabel;
        return task;
    }
    public function addOrUpdateTask(obj:Object, labelName:String, action:Function, interval:Number, parameters:Array):String {
        var task:Task=upsert(obj,labelName,action,interval,parameters,false);
        return (task==null)?null:task.id;
    }
    public function addLifecycleTask(obj:Object, labelName:String, action:Function, interval:Number, parameters:Array):String {
        var task:Task=upsert(obj,labelName,action,interval,parameters,true);if(task==null) return null;
        if(!obj._lifecycleRegistered) {obj._lifecycleRegistered={};_global.ASSetPropFlags(obj,["_lifecycleRegistered"],1,false);}
        var registrations:Object=obj._lifecycleRegistered;
        var old:Object=registrations[labelName];
        if(old==null||old.manager!==this||old.generation!=generation) {
            var self:TaskManager=this;
            var labels:Object=obj.taskLabel; // 捕获普通字典，绝不在旧回调里重新解析 MovieClip 路径
            var token:Object={manager:this,generation:generation};registrations[labelName]=token;
            EventCoordinator.addUnloadCallback(obj,function():Void {
                if(registrations[labelName]!==token) return;
                if(self.generation==token.generation) {
                    var id:String=labels[labelName];if(id!=undefined) self.removeTask(id);
                    delete labels[labelName];
                }
                delete registrations[labelName];
            });
        }
        return task.id;
    }
    public function locateTask(taskID:String):Task { return taskTable[taskID]||zeroFrameTasks[taskID]||null; }
    public function removeTask(taskID:String):Void {
        var task:Task=locateTask(taskID);if(task==null) return;
        detach(task);task.active=false;task.action=null;task.parameters=null;task.scope=null;task.ownerLabels=null;
    }
    public function removeLifecycleTask(obj:Object, labelName:String):Boolean {
        if(!obj||!obj.taskLabel||obj.taskLabel[labelName]==undefined) return false;
        removeTask(String(obj.taskLabel[labelName]));delete obj.taskLabel[labelName];return true;
    }
    public function delayTask(taskID:String, delayTime):Boolean {
        var task:Task=locateTask(taskID);if(task==null) return false;
        if(typeof delayTime!="number"||delayTime!==delayTime) task.pendingFrames=(delayTime===true)?Infinity:task.intervalFrames;
        else if(delayTime==Infinity) task.pendingFrames=Infinity;
        else {
            if(!isFinite(delayTime)) return false;
            var delta:Number=Math.ceil(delayTime*framesPerMs);
            if(!isFinite(delta)||delta>9007199254740991-scheduleTimer.currentFrame) return false;
            var next:Number=(task.pendingFrames||0)+delta;
            if(next!=Infinity&&(!isFinite(next)||next>9007199254740991-scheduleTimer.currentFrame)) return false;
            task.pendingFrames=next;
        }
        requestRoute(task);return true;
    }
    private function finish(task:Task, epoch:Number):Void {
        if(generation!=epoch||!task.active) return;
        if(task.repeatCount!==true) {
            task.repeatCount-=1;
            if(!(task.repeatCount>0)) {removeTask(task.id);return;}
        }
        if(!task.nextChanged) task.pendingFrames=task.intervalFrames;
        task.nextChanged=false;route(task);
    }
    private function execute(task:Task, epoch:Number):Boolean {
        if(!task.active||task.generation!=epoch) return false;
        if(task.ownerLabels!=null&&task.scope.taskLabel!==task.ownerLabels) {removeTask(task.id);return false;}
        currentTask=task;task.nextChanged=false;
        var action:Function=task.action;var scope:Object=task.scope;var params:Array=task.parameters;
        var length:Number=(params==null)?0:params.length;
        if(length==0) action.call(scope);
        else if(length==1) action.call(scope,params[0]);
        else if(length==2) action.call(scope,params[0],params[1]);
        else if(length==3) action.call(scope,params[0],params[1],params[2]);
        else if(length==4) action.call(scope,params[0],params[1],params[2],params[3]);
        else if(length==5) action.call(scope,params[0],params[1],params[2],params[3],params[4]);
        else action.apply(scope,params);
        currentTask=null;
        if(generation!=epoch||!task.active) return true;
        if(task.repeatCount!==true) {
            task.repeatCount-=1;
            if(!(task.repeatCount>0)) {removeTask(task.id);return true;}
        }
        if(!task.nextChanged) {
            task.pendingFrames=task.intervalFrames;
            // 普通循环不离开权威表；避免反复删表、计数、重建零链。
            if(task.state==1&&task.intervalFrames>0) {scheduleTimer.scheduleTask(task,task.intervalFrames);return true;}
            if(task.state==2&&task.intervalFrames<=0) return true;
        }
        task.nextChanged=false;route(task);return true;
    }
    public function updateFrame(frameToken:Number):Void {
        if(!alive||dispatching) return;
        if(frameToken!=undefined) {
            if(!isFinite(frameToken)||frameToken<=lastFrameToken) return;
            lastFrameToken=frameToken;
        }
        dispatching=true;var epoch:Number=generation;var calls:Number=0;
        var started:Number=(probe==null)?0:getTimer();
        try {
            var expired:Array=scheduleTimer.beginFrame();
            var expiredCount:Number=expired.length;
            var task:Task;
            for(var e:Number=0;e<expiredCount;e++) {
                task=expired[e];
                // 已取消、跨任务延迟或移入零阶段的同帧任务不再从旧快照执行。
                if(task.active&&task.state==1&&task.heapIndex<0&&task.timedSlot<0&&execute(task,epoch)) calls++;
                if(generation!=epoch||!alive) return;
            }
            // 时间任务创建的零任务进入本次快照；快照之后新增 ID 下一帧才运行。
            var n:Number=0;task=zeroHead;
            while(task!=null) {zeroSnapshot[n++]=task;task=task.zeroNext;}
            zeroSnapshot.length=n;
            for(var i:Number=0;i<n;i++) {
                task=zeroSnapshot[i];
                if(task.state==2&&task.active&&execute(task,epoch)) calls++;
                if(generation!=epoch||!alive) return;
            }
        } finally {
            // 回调异常仍向外传播；只收束已开始调用的 Task，避免脱堆后变成孤儿。
            if(currentTask!=null) finish(currentTask,epoch);
            scheduleTimer.endFrame();
            currentTask=null;dispatching=false;zeroSnapshot.length=0;
            if(probe!=null) {
                var index:Number=probe.next;
                probe.n[index]=timedCount+zeroCount+pausedCount;probe.z[index]=zeroCount;
                probe.paused[index]=pausedCount;probe.k[index]=calls;probe.ms[index]=getTimer()-started;
                probe.next=(index+1)%probe.capacity;probe.count=Math.min(probe.count+1,probe.capacity);
            }
        }
    }
    public function clear():Void {
        generation++;scheduleTimer.clear();taskTable={};zeroFrameTasks={};zeroHead=null;zeroTail=null;
        timedCount=0;zeroCount=0;pausedCount=0;
    }
    public function clearAllTasks():Void { clear(); }
    public function destroy():Void { clear();alive=false; }
    public function describeTask(taskID:String):String {
        var task:Task=locateTask(taskID);return (task==null)?("TaskID "+taskID+" not found"):task.toString();
    }
    public function getStats():Object {
        return {n:timedCount+zeroCount+pausedCount,z:zeroCount,paused:pausedCount,
            heap:scheduleTimer.getHeapSize(),short:scheduleTimer.getShortSize(),frame:scheduleTimer.currentFrame,generation:generation,alive:alive};
    }
    /** 默认关闭；开启时只写预分配数字数组，每帧一次，不序列化、不取堆栈。 */
    public function setProbeCapacity(capacity:Number):Void {
        if(capacity<=0||!isFinite(capacity)) {probe=null;return;}
        capacity=Math.min(3600,Math.floor(capacity));
        probe={capacity:capacity,next:0,count:0,n:new Array(capacity),z:new Array(capacity),
            paused:new Array(capacity),k:new Array(capacity),ms:new Array(capacity)};
    }
    public function getProbeSnapshot():Object {
        if(probe==null) return null;
        return {capacity:probe.capacity,next:probe.next,count:probe.count,n:probe.n.concat(),
            z:probe.z.concat(),paused:probe.paused.concat(),k:probe.k.concat(),ms:probe.ms.concat()};
    }
}
