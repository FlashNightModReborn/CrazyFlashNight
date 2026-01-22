import org.flashNight.neur.ScheduleTimer.CooldownWheel;

/**
 * @class org.flashNight.neur.ScheduleTimer.EnhancedCooldownWheel
 *
 * @description
 * 以高性能的 CooldownWheel 为"内核"的增强时间轮（AS2）。
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
 *   - repeatCount <= 0 视为"无限重复"。repeatCount > 0 表示总执行次数（含本次）。
 *   - 所有回调以 apply(null, args) 形式调用，支持可变参数。
 *
 * ========== 重要限制 ==========
 * 【最大延迟/间隔限制】: 由于底层使用 CooldownWheel（128槽位时间轮），
 * intervalMs 和 delay 转换为帧数后必须 ≤ 127 帧（约4.2秒@30FPS）。
 * 超过此限制的任务会因位运算回环而执行时间不可预测。
 *
 * 如果需要更长的延迟，请使用 TaskManager + CerberusScheduler。
 *
 * 【契约】: 回调函数不得抛出异常。AS2 本身对 null/undefined 已是静默失败；
 * 真正 throw 的回调应当被视为逻辑错误，由调用方保证。
 * ==============================
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
     * 每帧毫秒数（用于将毫秒转换为帧数）。默认 30FPS（约33.33毫秒/帧）。
     *
     * 【配置说明 - FIX v1.2 文档补充】
     * 此参数决定了 addTask/addDelayedTask 中毫秒到帧数的转换精度。
     * 必须与实际运行帧率保持一致，否则会导致任务执行时间偏差。
     *
     * 使用示例：
     * - 30 FPS 环境（默认）: 每帧毫秒 = 1000 / 30 ≈ 33.33
     * - 60 FPS 环境: EnhancedCooldownWheel.I().每帧毫秒 = 1000 / 60;
     *
     * 注意：底层 CooldownWheel 有 128 帧的硬限制，因此：
     * - 30 FPS 时最大延迟约 4233 毫秒（127 帧 × 33.33ms）
     * - 60 FPS 时最大延迟约 2117 毫秒（127 帧 × 16.67ms）
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
     * [FIX v1.2] 任务节点结构体（Object 约定字段）：
     *   id:Number
     *   callback:Function
     *   args:Array
     *   interval:Number        // 帧
     *   isRepeating:Boolean
     *   remainingCount:Number  // <=0 表示无限
     *   isActive:Boolean
     *   trigger:Function       // [NEW] 缓存的触发闭包，避免每次调度都创建新闭包
     *
     * [FIX v1.3.2] trigger 闭包直接持有 node 引用，检查 isActive 标志。
     * 解决 AS2 中 delete activeTasks[taskId] 后属性访问的边界行为问题。
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

        // [FIX v1.3.2] 闭包直接持有 node 引用，在触发时检查 isActive
        // 这比依赖 activeTasks[taskId] 查找更可靠
        var self:EnhancedCooldownWheel = this;
        var nodeRef:Object = node;
        node.trigger = function():Void {
            if (!nodeRef.isActive) return;
            self._executeTrigger(nodeRef);
        };

        return node;
    }

    /**
     * [FIX v1.2] 把任务在 N 帧后交给内核触发。
     * 使用缓存的闭包而非每次创建新闭包，实现零分配调度。
     */
    private function scheduleExecution(task:Object, delayFrames:Number):Void {
        // 直接使用缓存的 trigger，无需创建新闭包
        fastWheel.add(delayFrames, task.trigger);
    }

    /**
     * [FIX v1.3.2] 由闭包直接调用的执行逻辑（接收 node 引用）。
     *
     * 与旧版 _executeTask(taskId) 的核心区别：
     * - 闭包直接持有 node 引用，无需通过 activeTasks[taskId] 查找
     * - isActive 检查在闭包入口处完成，此处无需重复检查
     * - 解决了 AS2 中 delete 后属性访问的边界行为问题
     *
     * @param node 任务节点对象（由闭包直接传入）
     */
    private function _executeTrigger(node:Object):Void {
        // 执行回调
        node.callback.apply(null, node.args);

        // 检查任务是否在回调中被移除
        if (!node.isActive) return;

        if (!node.isRepeating) {
            // 一次性任务：收尾并移除
            cleanupTask(node, node.id);
            return;
        }

        // 重复任务：remainingCount <= 0 表示无限，否则为剩余总次数
        if (node.remainingCount > 0) {
            node.remainingCount -= 1;
            if (node.remainingCount <= 0) {
                cleanupTask(node, node.id);
                return;
            }
        }

        // 继续下一次调度
        scheduleExecution(node, node.interval);
    }

    /**
     * [v1.3] 清理任务（内部方法）。
     * 同时清理 activeTasks 和 taskLabel 映射。
     */
    private function cleanupTask(task:Object, taskId:Number):Void {
        task.isActive = false;
        delete activeTasks[taskId];

        // [v1.3] 清理 taskLabel 映射
        if (task.labelObj && task.labelName) {
            delete task.labelObj.taskLabel[task.labelName];
        }
    }

    // =====================================================================
    // 对外 API（保持完全向前兼容）
    // =====================================================================

    /**
     * 添加重复任务（毫秒级 API，保持兼容）。
     *
     * 【重要契约】:
     * - intervalMs 转换为帧后必须 ≤ 127，约4233ms@30FPS
     * - 回调不得抛出异常
     *
     * @param callback    回调函数
     * @param intervalMs  间隔毫秒（将换算为帧，至少 1 帧，最大约4233ms）
     * @param repeatCount 总执行次数；<=0 表示无限
     * @param ...args     透传给回调的参数
     * @return            任务ID
     */
    public function addTask(callback:Function, intervalMs:Number, repeatCount:Number):Number {
        var args:Array = [];
        for (var i:Number = 3; i < arguments.length; i++) args.push(arguments[i]);

        // 【契约】: intervalFrames 必须 ≤ 127，超出范围由调用方负责，详见类文档
        var intervalFrames:Number = Math.max(1, Math.round(intervalMs / 每帧毫秒));

        var taskId:Number = nextTaskId++;
        var task:Object = createTaskNode(taskId, callback, args, intervalFrames, true);
        task.remainingCount = repeatCount; // <=0 => 无限

        activeTasks[taskId] = task;
        scheduleExecution(task, intervalFrames);
        return taskId;
    }

    /**
     * 添加一次性延迟任务（毫秒级 API，保持兼容）。
     *
     * 【重要契约】:
     * - delay 转换为帧后必须 ≤ 127，约4233ms@30FPS
     * - 回调不得抛出异常
     *
     * @param delay     延迟毫秒（将换算为帧，至少 1 帧，最大约4233ms）
     * @param callback  回调函数
     * @param ...args   透传给回调的参数
     * @return          任务ID
     */
    public function addDelayedTask(delay:Number, callback:Function):Number {
        var args:Array = [];
        for (var i:Number = 2; i < arguments.length; i++) args.push(arguments[i]);

        // 【契约】: delayFrames 必须 ≤ 127，超出范围由调用方负责，详见类文档
        var delayFrames:Number = Math.max(1, Math.round(delay / 每帧毫秒));

        var taskId:Number = nextTaskId++;
        var task:Object = createTaskNode(taskId, callback, args, 0, false);

        activeTasks[taskId] = task;
        scheduleExecution(task, delayFrames);
        return taskId;
    }

    /**
     * 取消任务（惰性删除，保持兼容）。
     * [FIX v1.3.2] 闭包直接检查 node.isActive，无需清空回调。
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
     * 常用于"在 N 帧后执行一次回调"的高性能场景。
     *
     * 【注意】此方法不支持取消，直接透传到 CooldownWheel。
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

    // =====================================================================
    // [v1.3] 生命周期管理 API
    // =====================================================================

    /**
     * 添加或更新带标签的任务（生命周期管理 API）。
     *
     * 在目标对象上维护 taskLabel 映射表，自动处理旧任务的移除。
     * 适用于需要"同一标签只保留最新任务"的场景（如射击后摇）。
     *
     * 【使用场景】
     * - 射击系统：同一武器的后摇任务只需保留最新的
     * - 技能系统：同一技能的冷却任务只需保留最新的
     * - 动画系统：同一动画的延迟回调只需保留最新的
     *
     * 【自动行为】
     * - 若 obj.taskLabel 不存在，自动创建并隐藏（ASSetPropFlags）
     * - 若同标签已有任务，自动移除旧任务后添加新任务
     * - 任务完成/移除时自动清理 taskLabel 中的记录
     *
     * @param obj         目标对象（用于存储 taskLabel）
     * @param labelName   任务标签名（如 "结束射击后摇"）
     * @param callback    回调函数
     * @param delayOrInterval  延迟/间隔毫秒数（≤4233ms@30FPS）
     * @param isRepeating 是否为重复任务（false=一次性延迟任务）
     * @param repeatCount 重复次数（仅 isRepeating=true 时有效，≤0 表示无限）
     * @param args        透传给回调的参数数组（可选）
     * @return            新任务ID
     */
    public function addOrUpdateTask(obj:Object, labelName:String,
                                    callback:Function, delayOrInterval:Number,
                                    isRepeating:Boolean, repeatCount:Number,
                                    args:Array):Number {
        // 初始化 taskLabel 表（隐藏属性）
        if (!obj.taskLabel) {
            obj.taskLabel = {};
            _global.ASSetPropFlags(obj, ["taskLabel"], 1, false);
        }

        // 移除同标签的旧任务
        var existingId:Number = obj.taskLabel[labelName];
        if (existingId != undefined && existingId != null) {
            removeTask(existingId);
        }

        // 计算帧数
        var frames:Number = Math.max(1, Math.round(delayOrInterval / 每帧毫秒));

        // 创建任务
        var taskId:Number = nextTaskId++;
        var task:Object = createTaskNode(taskId, callback, args || [], frames, isRepeating);
        if (isRepeating) {
            task.remainingCount = repeatCount; // ≤0 => 无限
        }

        // 记录标签映射
        obj.taskLabel[labelName] = taskId;

        // 保存引用以便任务完成时清理 taskLabel
        task.labelObj = obj;
        task.labelName = labelName;

        activeTasks[taskId] = task;
        scheduleExecution(task, frames);
        return taskId;
    }

    /**
     * 通过标签移除任务（生命周期管理 API）。
     *
     * @param obj        目标对象
     * @param labelName  任务标签名
     * @return           是否成功移除（false 表示任务不存在或已完成）
     */
    public function removeTaskByLabel(obj:Object, labelName:String):Boolean {
        if (!obj || !obj.taskLabel) return false;

        var taskId:Number = obj.taskLabel[labelName];
        if (taskId == undefined || taskId == null) return false;

        // 清理标签映射
        delete obj.taskLabel[labelName];

        // 移除任务
        var task:Object = activeTasks[taskId];
        if (task) {
            // [FIX v1.3.2] 闭包直接检查 node.isActive，无需清空回调
            task.isActive = false;
            delete activeTasks[taskId];
            return true;
        }
        return false;
    }

    /**
     * 手动推进时间轮一帧（测试/调试用）。
     *
     * 【使用场景】
     * - 单元测试中需要精确控制时间推进
     * - 调试时需要逐帧验证任务执行
     *
     * 【注意】
     * 正常运行时 CooldownWheel 由 onEnterFrame 自动驱动，
     * 无需手动调用此方法。此方法主要用于测试环境。
     */
    public function tick():Void {
        fastWheel.tick();
    }
}
