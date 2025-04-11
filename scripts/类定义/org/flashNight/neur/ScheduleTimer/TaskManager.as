import org.flashNight.neur.ScheduleTimer.*;
import org.flashNight.neur.Server.*; 
import org.flashNight.neur.Event.*;
import org.flashNight.naki.DataStructures.*;
import org.flashNight.aven.Coordinator.*;

/**
 * TaskManager.as
 * 任务调度管理器
 * 负责帧计时器中与任务调度相关的部分，提供添加、更新、删除、延迟任务等方法
 * 依赖外部的 ScheduleTimer 组件来完成任务调度（例如：evaluateAndInsertTask、rescheduleTaskByNode、removeTaskByNode 等）
 * 
 * 使用说明：
 *   由帧计时器在初始化时构建 TaskManager 实例，并传入 ScheduleTimer 实例与当前帧率（或每帧毫秒数）参数。
 *   TaskManager 的 updateFrame() 方法应在每帧更新时调用，以处理任务队列中到期任务的执行。
 */
class org.flashNight.neur.ScheduleTimer.TaskManager {
    // 私有属性
    private var scheduleTimer:CerberusScheduler; // 外部任务调度器实例
    private var taskTable:Object;    // 存放待调度任务（非零间隔任务），以 taskID 为键
    private var zeroFrameTasks:Object; // 存放零帧（立即执行）任务
    private var taskIdCounter:Number; // 任务ID计数器
    private var msPerFrame:Number;    // 每帧对应的毫秒数（或由帧率换算而来）

    /**
     * 构造函数
     * @param scheduleTimer 外部任务调度器实例（例如 CerberusScheduler）
     * @param frameRate 当前帧率，用于计算间隔帧数
     */
    public function TaskManager(scheduleTimer:CerberusScheduler, frameRate:Number) {
        this.scheduleTimer = scheduleTimer;
        // 计算每帧时间（原代码中用 帧率/1000 进行优化，可根据实际需要调整）
        this.msPerFrame = frameRate / 1000;
        this.taskTable = {};
        this.zeroFrameTasks = {};
        this.taskIdCounter = 0;
    }

    /**
     * 每帧更新时调用，负责检查任务队列与零帧任务并依次执行
     */
    public function updateFrame():Void {
        var tasks = this.scheduleTimer.tick();
        if (tasks != null) {
            var node:TaskIDNode = tasks.getFirst();
            while (node != null) {
                var nextNode:TaskIDNode = node.next;
                var taskID:String = node.taskID;
                var task:Task = this.taskTable[taskID];
                if (task) {
                    task.action();
                    // 处理任务重复逻辑
                    if (task.repeatCount === 1) {
                        delete this.taskTable[taskID];
                    } else if (task.repeatCount === true || task.repeatCount > 1) {
                        if (task.repeatCount !== true) {
                            task.repeatCount -= 1;
                        }
                        task.pendingFrames = task.intervalFrames;
                        task.node = this.scheduleTimer.evaluateAndInsertTask(taskID, task.pendingFrames);
                    } else {
                        delete this.taskTable[taskID];
                    }
                }
                node = nextNode;
            }
        }
        // 处理零帧任务
        for (var id in this.zeroFrameTasks) {
            var zTask:Task = this.zeroFrameTasks[id];
            zTask.action();
            if (zTask.repeatCount !== true) {
                zTask.repeatCount -= 1;
                if (zTask.repeatCount <= 0) {
                    delete this.zeroFrameTasks[id];
                }
            }
        }
    }

    /**
     * 添加任务（通用版本）
     * @param action 任务执行的回调函数
     * @param interval 任务间隔（单位：毫秒或其他与 msPerFrame 配合的单位）
     * @param repeatCount 重复次数，1 表示单次执行；true 表示无限循环；大于1表示重复次数
     * @param parameters 动态参数数组（可选）
     * @return 任务ID
     */
    public function addTask(action:Function, interval:Number, repeatCount, parameters:Array):String {
        var taskID:String = String(++this.taskIdCounter);
        var intervalFrames:Number = ((interval * this.msPerFrame) + 0.9999999999) | 0;
        var task:Task = new Task(taskID, intervalFrames, repeatCount);
        // 利用 Delegate 封装回调和参数（假设 Delegate.createWithParams 存在）
        task.action = Delegate.createWithParams(task, action, parameters);
        if (intervalFrames <= 0) {
            this.zeroFrameTasks[taskID] = task;
        } else {
            task.pendingFrames = intervalFrames;
            task.node = this.scheduleTimer.evaluateAndInsertTask(taskID, intervalFrames);
            this.taskTable[taskID] = task;
        }
        return taskID;
    }

    /**
     * 添加单次任务（执行一次，间隔小于等于0时直接执行）
     * @param action 回调函数
     * @param interval 任务间隔
     * @param parameters 动态参数数组（可选）
     * @return 任务ID；若直接执行则返回 null
     */
    public function addSingleTask(action:Function, interval:Number, parameters:Array):String {
        if (interval <= 0) {
            var boundAction:Function = Delegate.createWithParams(null, action, parameters);
            boundAction();
            return null;
        } else {
            var taskID:String = String(++this.taskIdCounter);
            var intervalFrames:Number = ((interval * this.msPerFrame) + 0.9999999999) | 0;
            var task:Task = new Task(taskID, intervalFrames, 1);
            task.action = Delegate.createWithParams(task, action, parameters);
            if (intervalFrames <= 0) {
                this.zeroFrameTasks[taskID] = task;
            } else {
                task.pendingFrames = intervalFrames;
                task.node = this.scheduleTimer.evaluateAndInsertTask(taskID, intervalFrames);
                this.taskTable[taskID] = task;
            }
            return taskID;
        }
    }

    /**
     * 添加循环任务（无限重复执行）
     * @param action 回调函数
     * @param interval 任务间隔
     * @param parameters 动态参数数组（可选）
     * @return 任务ID
     */
    public function addLoopTask(action:Function, interval:Number, parameters:Array):String {
        var taskID:String = String(++this.taskIdCounter);
        var intervalFrames:Number = ((interval * this.msPerFrame) + 0.9999999999) | 0;
        var task:Task = new Task(taskID, intervalFrames, true); // true 表示无限循环
        task.action = Delegate.createWithParams(task, action, parameters);
        if (intervalFrames <= 0) {
            this.zeroFrameTasks[taskID] = task;
        } else {
            task.pendingFrames = intervalFrames;
            task.node = this.scheduleTimer.evaluateAndInsertTask(taskID, intervalFrames);
            this.taskTable[taskID] = task;
        }
        return taskID;
    }

    /**
     * 添加或更新任务（若任务已存在则更新，否则创建新任务）
     * @param obj 任务所属对象（用于保存任务标识）
     * @param labelName 任务标签名称
     * @param action 回调函数
     * @param interval 任务间隔
     * @param parameters 动态参数数组（可选）
     * @return 任务ID
     */
    public function addOrUpdateTask(obj:Object, labelName:String, action:Function, interval:Number, parameters:Array):String {
        if (!obj) return null;
        if (!obj.taskLabel) obj.taskLabel = {};
        if (!obj.taskLabel[labelName]) {
            obj.taskLabel[labelName] = ++this.taskIdCounter;
        }
        var taskID:String = obj.taskLabel[labelName];
        var intervalFrames:Number = ((interval * this.msPerFrame) + 0.9999999999) | 0;
        var task:Task = this.taskTable[taskID] || this.zeroFrameTasks[taskID];
        if (task) {
            task.action = Delegate.createWithParams(obj, action, parameters);
            task.intervalFrames = intervalFrames;
            if (intervalFrames === 0) {
                if (this.taskTable[taskID]) {
                    this.scheduleTimer.removeTaskByNode(task.node);
                    delete task.node;
                    delete this.taskTable[taskID];
                }
                this.zeroFrameTasks[taskID] = task;
            } else {
                if (this.zeroFrameTasks[taskID]) {
                    delete this.zeroFrameTasks[taskID];
                    task.pendingFrames = intervalFrames;
                    task.node = this.scheduleTimer.evaluateAndInsertTask(taskID, intervalFrames);
                    this.taskTable[taskID] = task;
                } else {
                    task.pendingFrames = intervalFrames;
                    this.scheduleTimer.rescheduleTaskByNode(task.node, intervalFrames);
                }
            }
        } else {
            task = new Task(taskID, intervalFrames, 1);
            task.action = Delegate.createWithParams(obj, action, parameters);
            if (intervalFrames === 0) {
                this.zeroFrameTasks[taskID] = task;
            } else {
                task.pendingFrames = intervalFrames;
                task.node = this.scheduleTimer.evaluateAndInsertTask(taskID, intervalFrames);
                this.taskTable[taskID] = task;
            }
        }
        return taskID;
    }

    /**
     * 添加生命周期任务（类似于 addOrUpdateTask，但任务设置为无限循环）
     * @param obj 任务所属对象
     * @param labelName 任务标签
     * @param action 回调函数
     * @param interval 任务间隔
     * @param parameters 动态参数数组（可选）
     * @return 任务ID
     */
    public function addLifecycleTask(obj:Object, labelName:String, action:Function, interval:Number, parameters:Array):String {
        if (!obj) return null;
        if (!obj.taskLabel) obj.taskLabel = {};
        if (!obj.taskLabel[labelName]) {
            obj.taskLabel[labelName] = ++this.taskIdCounter;
        }
        var taskID:String = obj.taskLabel[labelName];
        var intervalFrames:Number = ((interval * this.msPerFrame) + 0.9999999999) | 0;
        var boundAction:Function = Delegate.createWithParams(obj, action, parameters);
        var task:Task = this.taskTable[taskID] || this.zeroFrameTasks[taskID];
        if (task) {
            task.action = boundAction;
            task.intervalFrames = intervalFrames;
            task.repeatCount = true; // 无限循环
            if (intervalFrames === 0) {
                if (this.taskTable[taskID]) {
                    this.scheduleTimer.removeTaskByNode(task.node);
                    delete task.node;
                    delete this.taskTable[taskID];
                }
                this.zeroFrameTasks[taskID] = task;
            } else {
                if (this.zeroFrameTasks[taskID]) {
                    delete this.zeroFrameTasks[taskID];
                    task.pendingFrames = intervalFrames;
                    task.node = this.scheduleTimer.evaluateAndInsertTask(taskID, intervalFrames);
                    this.taskTable[taskID] = task;
                } else {
                    task.pendingFrames = intervalFrames;
                    this.scheduleTimer.rescheduleTaskByNode(task.node, intervalFrames);
                }
            }
        } else {
            task = new Task(taskID, intervalFrames, true);
            task.action = boundAction;
            if (intervalFrames === 0) {
                this.zeroFrameTasks[taskID] = task;
            } else {
                task.pendingFrames = intervalFrames;
                task.node = this.scheduleTimer.evaluateAndInsertTask(taskID, intervalFrames);
                this.taskTable[taskID] = task;
            }
        }
        var self:TaskManager = this;
        EventCoordinator.addUnloadCallback(obj, function():Void {
            self.removeTask(taskID);
            delete obj.taskLabel[labelName];
        });
        return taskID;
    }

    /**
     * 移除任务
     * @param taskID 要移除的任务ID
     */
    public function removeTask(taskID:String):Void {
        var task:Task = this.taskTable[taskID];
        if (task) {
            this.scheduleTimer.removeTaskByNode(task.node);
            delete this.taskTable[taskID];
        } else if (this.zeroFrameTasks[taskID]) {
            delete this.zeroFrameTasks[taskID];
        }
    }

    /**
     * 定位任务
     * @param taskID 任务ID
     * @return 找到的 Task 实例或 null
     */
    public function locateTask(taskID:String):Task {
        return this.taskTable[taskID] || this.zeroFrameTasks[taskID] || null;
    }

    /**
     * 延迟执行任务
     * @param taskID 任务ID
     * @param delayTime 延迟时间（单位同 interval）
     * @return 延迟设置成功返回 true，否则 false
     */
    public function delayTask(taskID:String, delayTime):Boolean {
        var task:Task = this.taskTable[taskID] || this.zeroFrameTasks[taskID];
        if (task) {
            var delayFrames:Number;
            if (isNaN(delayTime)) {
                task.pendingFrames = (delayTime === true) ? Infinity : task.intervalFrames;
            } else {
                delayFrames = Math.ceil(delayTime * this.msPerFrame);
                task.pendingFrames += delayFrames;
            }
            if (task.pendingFrames <= 0) {
                if (this.taskTable[taskID]) {
                    this.scheduleTimer.removeTaskByNode(task.node);
                    delete task.node;
                    delete this.taskTable[taskID];
                    this.zeroFrameTasks[taskID] = task;
                }
            } else {
                if (this.zeroFrameTasks[taskID]) {
                    delete this.zeroFrameTasks[taskID];
                    task.node = this.scheduleTimer.evaluateAndInsertTask(taskID, task.pendingFrames);
                    this.taskTable[taskID] = task;
                } else {
                    this.scheduleTimer.rescheduleTaskByNode(task.node, task.pendingFrames);
                }
            }
            return true;
        }
        return false;
    }
}
