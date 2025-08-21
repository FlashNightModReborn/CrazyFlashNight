import org.flashNight.neur.ScheduleTimer.CooldownWheel;

/**
 * @class org.flashNight.neur.ScheduleTimer.EnhancedCooldownWheel
 *
 * @description
 * 以高性能的 CooldownWheel 为“内核”的增强时间轮（AS2）。
 * 保持对既有 EnhancedCooldownWheel API 的 100% 向前兼容：
 *   - addTask(callback, intervalMs, repeatCount, ...args): Number
 *   - addDelayedTask(delay, callback, ...args): Number
 *   - removeTask(taskId): Void
 *   - add(delay, callback): Void              // 直通底层（帧为单位）
 *   - reset(): Void
 *   - getActiveTaskCount(): Number
 *
 * 说明：
 *   - 所有计时由 CooldownWheel.I() 驱动；本类仅做任务ID管理、重复次数控制与取消逻辑。
 *   - repeatCount <= 0 视为“无限重复”。repeatCount > 0 表示总执行次数（含本次）。
 *   - 所有回调以 apply(null, args) 形式调用，支持可变参数。
 */
class org.flashNight.neur.ScheduleTimer.EnhancedCooldownWheel {
    // =====================================================================
    // 单例
    // =====================================================================

    /**
     * 全局实例（保持字段名以兼容旧代码）。
     */
    public static var inst:EnhancedCooldownWheel;

    /**
     * 获取 EnhancedCooldownWheel 的全局单例。
     */
    public static function I():EnhancedCooldownWheel {
        return inst || (inst = new EnhancedCooldownWheel());
    }

    // =====================================================================
    // 配置与字段
    // =====================================================================

    /**
     * 每帧毫秒（用于把毫秒转帧）。默认 30FPS。
     */
    public var 每帧毫秒:Number = 1000 / 30;

    /**
     * 任务自增ID。
     */
    private var nextTaskId:Number = 1;

    /**
     * 活跃任务表：taskId -> TaskNode
     */
    private var activeTasks:Object;

    /**
     * 底层高性能时间轮（内核）。
     */
    private var fastWheel:CooldownWheel;

    // =====================================================================
    // 构造与内部结构
    // =====================================================================

    /**
     * 私有构造：请通过 I() 获取。
     */
    private function EnhancedCooldownWheel() {
        this.fastWheel = CooldownWheel.I();
        this.activeTasks = {};
    }

    /**
     * 任务节点结构体（Object 约定字段）：
     *   id:Number
     *   callback:Function
     *   args:Array
     *   interval:Number        // 帧
     *   isRepeating:Boolean
     *   remainingCount:Number  // <=0 表示无限
     *   isActive:Boolean
     */
    private function createTaskNode(id:Number, callback:Function, args:Array,
                                    interval:Number, isRepeating:Boolean):Object {
        var node:Object = {};
        node.id = id;
        node.callback = callback;
        node.args = args || [];
        node.interval = interval;
        node.isRepeating = isRepeating;
        node.remainingCount = 0; // 默认 0（由外部根据需要赋值）
        node.isActive = true;
        return node;
    }

    /**
     * 把任务在 N 帧后交给内核触发。
     * 通过闭包回到本类以执行真正的任务逻辑（取消/重复等）。
     */
    private function scheduleExecution(taskId:Number, delayFrames:Number):Void {
        var self:EnhancedCooldownWheel = this;
        var triggerCallback:Function = function():Void {
            self._executeTask(taskId);
        };
        fastWheel.add(delayFrames, triggerCallback);
    }

    /**
     * 由内核触发的实际执行逻辑。
     * - 若任务已被取消（或不存在），直接返回。
     * - 执行回调；根据是否重复与剩余次数决定是否二次调度或收尾。
     */
    private function _executeTask(taskId:Number):Void {
        var task:Object = activeTasks[taskId];
        if (!task || !task.isActive) return;

        // 执行用户回调
        try {
            task.callback.apply(null, task.args);
        } catch (e:Error) {
            // 兼容旧版写法：AS2 的 Error 类型在不同编译链上可能退化为 Object
            trace("EnhancedCooldownWheel: 任务 " + taskId + " 执行错误: " + e);
        }

        if (!task.isRepeating) {
            // 一次性任务：收尾并移除
            task.isActive = false;
            delete activeTasks[taskId];
            return;
        }

        // 重复任务：repeatCount <= 0 表示无限，否则为剩余总次数（含本次已执行）
        if (task.remainingCount > 0) {
            task.remainingCount -= 1;
            if (task.remainingCount <= 0) {
                task.isActive = false;
                delete activeTasks[taskId];
                return;
            }
        }

        // 继续下一次
        scheduleExecution(taskId, task.interval);
    }

    // =====================================================================
    // 对外 API（保持完全向前兼容）
    // =====================================================================

    /**
     * 添加重复任务（毫秒级 API，保持兼容）。
     * @param callback    回调函数
     * @param intervalMs  间隔毫秒（将换算为帧，至少 1 帧）
     * @param repeatCount 总执行次数；<=0 表示无限
     * @param ...args     透传给回调的参数
     * @return            任务ID
     */
    public function addTask(callback:Function, intervalMs:Number, repeatCount:Number):Number {
        var args:Array = [];
        for (var i:Number = 3; i < arguments.length; i++) args.push(arguments[i]);

        var intervalFrames:Number = Math.max(1, Math.round(intervalMs / 每帧毫秒));
        var taskId:Number = nextTaskId++;
        var task:Object = createTaskNode(taskId, callback, args, intervalFrames, true);
        task.remainingCount = repeatCount; // <=0 => 无限

        activeTasks[taskId] = task;
        scheduleExecution(taskId, intervalFrames);
        return taskId;
    }

    /**
     * 添加一次性延迟任务（毫秒级 API，保持兼容）。
     * @param delay     延迟毫秒（将换算为帧，至少 1 帧）
     * @param callback  回调函数
     * @param ...args   透传给回调的参数
     * @return          任务ID
     */
    public function addDelayedTask(delay:Number, callback:Function):Number {
        var args:Array = [];
        for (var i:Number = 2; i < arguments.length; i++) args.push(arguments[i]);

        var delayFrames:Number = Math.max(1, Math.round(delay / 每帧毫秒));
        var taskId:Number = nextTaskId++;
        var task:Object = createTaskNode(taskId, callback, args, 0, false);

        activeTasks[taskId] = task;
        scheduleExecution(taskId, delayFrames);
        return taskId;
    }

    /**
     * 取消任务（惰性删除，保持兼容）。
     */
    public function removeTask(taskId:Number):Void {
        var task:Object = activeTasks[taskId];
        if (task) {
            task.isActive = false;
            delete activeTasks[taskId];
        }
    }

    /**
     * 与旧版保持一致：直通内核（单位：帧）。
     * 常用于“在 N 帧后执行一次回调”的高性能场景。
     */
    public function add(delay:Number, callback:Function):Void {
        fastWheel.add(delay, callback);
    }

    /**
     * 重置：清空所有任务并复位内核。
     */
    public function reset():Void {
        fastWheel.reset();
        activeTasks = {};
        nextTaskId = 1;
    }

    /**
     * 当前活跃任务数量（测试/调试用）。
     */
    public function getActiveTaskCount():Number {
        var count:Number = 0;
        for (var k:String in activeTasks) count++;
        return count;
    }
}