/**
 * TaskScheduler.as

 * @description
 *     统一管理 0 帧任务 + 普通延迟/循环任务的调度。
 * 
 *     - 内部使用 CerberusScheduler 管理普通任务（>0帧）。
 *     - 对外提供添加/移除任务、每帧 tick 等接口。
 *     - 0 帧任务立即放进 zeroFrameTasks，每帧执行后根据重复次数处理。
 */
import org.flashNight.neur.ScheduleTimer.*;
import org.flashNight.naki.DataStructures.*;
import org.flashNight.neur.TimeWheel.*;

class org.flashNight.neur.ScheduleTimer.TaskScheduler
{
    // === 依赖调度器: CerberusScheduler ===
    private var scheduleTimer:CerberusScheduler;

    // === 维护任务字典 ===
    private var taskHash:Object;        // 普通任务（>0帧）
    private var zeroFrameTasks:Object;  // 0帧任务

    // === 自增 ID 计数器，用于分配任务ID ===
    private var taskIdCounter:Number;

    // === 帧率 & 毫秒/帧 ===
    private var frameRate:Number;
    private var msPerFrame:Number;

    /**
     * 构造函数
     * @param frameRate 帧率 (FPS)
     */
    public function TaskScheduler(frameRate:Number)
    {
        this.frameRate = frameRate;
        this.msPerFrame = 1000 / frameRate;

        // 实例化你的 CerberusScheduler
        this.scheduleTimer = new CerberusScheduler();

        // 初始化内部管理结构
        this.taskHash = {};
        this.zeroFrameTasks = {};
        this.taskIdCounter = 0;
    }

    /**
     * 每帧调用，用于推进调度器中的任务执行
     */
    public function tick():Void
    {
        // 1. 先取出本帧要执行的普通任务
        var tasks = this.scheduleTimer.tick();
        if (tasks != null)
        {
            var node = tasks.getFirst();
            while (node != null)
            {
                var nextNode = node.next;
                var taskID:Number = node.taskID;
                var t:Object = this.taskHash[taskID];

                if (t)
                {
                    // 执行动作
                    t.action();

                    // 处理重复次数 
                    if (t.repeatCount === true || t.repeatCount === Infinity)
                    {
                        // 无限循环任务，需要重新调度
                        t.pendingFrames = t.intervalFrames;
                        t.node = this.scheduleTimer.evaluateAndInsertTask(taskID, t.intervalFrames);
                    }
                    else if (typeof t.repeatCount == "number")
                    {
                        t.repeatCount--;
                        if (t.repeatCount > 0)
                        {
                            t.pendingFrames = t.intervalFrames;
                            t.node = this.scheduleTimer.evaluateAndInsertTask(taskID, t.intervalFrames);
                        }
                        else
                        {
                            // 不再重复，移除
                            delete this.taskHash[taskID];
                        }
                    }
                    else
                    {
                        // 默认一次性任务
                        delete this.taskHash[taskID];
                    }
                }
                node = nextNode;
            }
        }

        // 2. 再处理所有 0 帧任务
        for (var zTaskID in this.zeroFrameTasks)
        {
            var zt:Object = this.zeroFrameTasks[zTaskID];
            zt.action();

            // 处理重复次数
            if (zt.repeatCount === true || zt.repeatCount === Infinity)
            {
                // 无穷循环的 0 帧任务，每帧都执行，不动
                // 如果需要在此处限制执行次数，可自行添加
            }
            else if (typeof zt.repeatCount == "number")
            {
                zt.repeatCount--;
                if (zt.repeatCount <= 0)
                {
                    delete this.zeroFrameTasks[zTaskID];
                }
            }
            else
            {
                // 默认一次
                delete this.zeroFrameTasks[zTaskID];
            }
        }
    }

    /**
     * 添加任务
     * @param action        动作函数 (function)
     * @param delayTimeMS   延迟执行时间（毫秒），<=0 则视为 0 帧任务
     * @param repeatCount   重复次数，true 或 Infinity 表示无限；默认1次
     * @return taskID       返回分配的任务ID
     */
    public function addTask(action:Function,
                            delayTimeMS:Number,
                            repeatCount:Object):Number
    {
        if (repeatCount == undefined || repeatCount == null)
        {
            repeatCount = 1;
        }

        // 生成唯一任务ID
        var taskID:Number = ++this.taskIdCounter;

        // 计算转为帧数
        var frames:Number = Math.ceil(delayTimeMS / this.msPerFrame);

        // 构建任务对象
        var task:Object = {
            id: taskID,
            action: action,
            intervalFrames: frames,
            pendingFrames: frames,    // 当前剩余帧数(若需要)
            repeatCount: repeatCount,
            node: null
        };

        // 判断是否 0 帧任务
        if (frames <= 0)
        {
            // 放入 zeroFrameTasks
            this.zeroFrameTasks[taskID] = task;
        }
        else
        {
            // 正常帧任务
            task.node = this.scheduleTimer.evaluateAndInsertTask(taskID, frames);
            this.taskHash[taskID] = task;
        }

        return taskID;
    }

    /**
     * 移除任务 (普通或 0 帧)
     * @param taskID 要移除的任务ID
     */
    public function removeTask(taskID:Number):Void
    {
        // 先看普通任务
        var t:Object = this.taskHash[taskID];
        if (t)
        {
            // 如果已经在 CerberusScheduler 里调度，需要移除
            if (t.node)
            {
                this.scheduleTimer.removeTaskByNode(t.node);
            }
            delete this.taskHash[taskID];
        }
        else
        {
            // 再看 0 帧任务
            if (this.zeroFrameTasks[taskID] != undefined)
            {
                delete this.zeroFrameTasks[taskID];
            }
        }
    }

    /**
     * 根据 ID 获取任务信息
     * @param taskID
     * @return 任务对象或 null
     */
    public function getTask(taskID:Number):Object
    {
        if (this.taskHash[taskID])
        {
            return this.taskHash[taskID];
        }
        else if (this.zeroFrameTasks[taskID])
        {
            return this.zeroFrameTasks[taskID];
        }
        return null;
    }

    /**
     * 清空所有任务 (谨慎使用)
     */
    public function clearAllTasks():Void
    {
        // 清除普通任务
        for (var id in this.taskHash)
        {
            var t:Object = this.taskHash[id];
            if (t && t.node)
            {
                this.scheduleTimer.removeTaskByNode(t.node);
            }
        }
        this.taskHash = {};

        // 清空 0 帧任务
        this.zeroFrameTasks = {};
    }

    /**
     * [可选] 重新调度某个任务，例如延迟执行
     * @param taskID
     * @param extraDelayMS  额外延迟时间（毫秒），合并到任务的 pendingFrames 中
     */
    public function delayTask(taskID:Number, extraDelayMS:Number):Void
    {
        var t:Object = this.getTask(taskID);
        if (t == null) return;

        // 先移除调度
        if (t.node)
        {
            this.scheduleTimer.removeTaskByNode(t.node);
            t.node = null;
        }

        // 转为帧数
        var framesToAdd:Number = Math.ceil(extraDelayMS / this.msPerFrame);
        t.pendingFrames = (t.pendingFrames || 0) + framesToAdd;

        if (t.pendingFrames <= 0)
        {
            // 变成 0 帧任务
            delete this.taskHash[taskID];
            this.zeroFrameTasks[taskID] = t;
        }
        else
        {
            // 重新调度
            t.node = this.scheduleTimer.evaluateAndInsertTask(taskID, t.pendingFrames);
            this.taskHash[taskID] = t;
        }
    }
}
