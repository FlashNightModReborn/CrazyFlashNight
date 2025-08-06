import org.flashNight.neur.ScheduleTimer.CooldownWheel;

/**
 * @class org.flashNight.neur.ScheduleTimer.EnhancedCooldownWheel
 *
 * @description
 * 一个增强型的时间轮调度器。
 * 
 * 该类构建于一个高性能的底层时间轮 (CooldownWheel) 之上，提供了更丰富和健壮的API，
 * 包括：
 * - **任务ID管理**: 添加的任务会返回一个唯一的ID，用于后续操作（如取消）。
 * - **可取消的任务**: 可以通过任务ID随时移除还未执行或正在重复的任何任务。
 * - **重复次数控制**: 可以精确指定一个任务需要重复执行的次数。
 * - **延迟执行**: 支持一次性的延迟任务。
 * - **可变参数**: 为回调函数传递任意数量的参数。
 * 
 * 它通过将实际的“计时”工作委托给底层的 `fastWheel`，而自身专注于任务的生命周期管理
 * （创建、调度、执行、重新调度、清理），从而实现了功能性和高性能的结合。
 *
 * @see org.flashNight.neur.ScheduleTimer.CooldownWheel
 */
class org.flashNight.neur.ScheduleTimer.EnhancedCooldownWheel {
    
    // ————————————————————————
    // 字段
    // ————————————————————————
    
    /**
     * @field {EnhancedCooldownWheel} inst
     * @static
     * @private
     * 单例模式的静态实例。
     */
    public static var inst:EnhancedCooldownWheel;
    
    /**
     * @field {Number} nextTaskId
     * @private
     * 用于生成下一个唯一任务ID的计数器。
     */
    private var nextTaskId:Number = 1;
    
    /**
     * @field {Object} activeTasks
     * @private
     * 存储所有当前活跃任务的映射表。
     * 键是任务ID (taskId)，值是任务节点对象 (TaskNode)。
     */
    private var activeTasks:Object;
    
    /**
     * @field {CooldownWheel} fastWheel
     * @private
     * 底层的高性能时间轮实例，作为本调度器的执行核心。
     * 所有计时和“滴答”事件都由它驱动。
     */
    private var fastWheel:CooldownWheel;
    
    /**
     * @field {Number} 每帧毫秒
     * @public
     * 定义了用于计算的单帧时长（以毫秒为单位）。
     * 默认为 1000 / 30 ≈ 33.33ms，对应于 30 FPS 的帧率。
     * 这个值用于将用户传入的毫秒时间转换为内部使用的帧数。
     */
    public var 每帧毫秒:Number = 1000 / 30; // 30FPS

    // ————————————————————————
    // 构造与单例
    // ————————————————————————
    
    /**
     * @constructor
     * @private
     * 构造函数是私有的，以强制使用 `I()` 方法获取实例（单例模式）。
     */
    private function EnhancedCooldownWheel() {
        // 获取高性能时间轮的实例作为底层执行引擎
        this.fastWheel = CooldownWheel.I();
        this.activeTasks = {};
        
        // 注意：不再需要创建自己的 onEnterFrame 驱动器和 slots 数组！
        // 所有的“滴答”都由 fastWheel 在内部处理。
    }

    /**
     * 获取 EnhancedCooldownWheel 的全局单例。
     * @static
     * @returns {EnhancedCooldownWheel} 全局唯一的实例。
     */
    public static function I():EnhancedCooldownWheel {
        return inst || (inst = new EnhancedCooldownWheel());
    }

    // ————————————————————————
    // 任务节点创建函数
    // ————————————————————————
    
    /**
     * @private
     * 创建并返回一个标准化的任务节点对象。
     * 
     * @param {Number} id 任务的唯一ID。
     * @param {Function} callback 到期时要执行的回调函数。
     * @param {Array} args 调用回调函数时需要传递的参数数组。
     * @param {Number} interval 对于重复任务，这是每次执行的间隔（以帧为单位）。
     * @param {Boolean} isRepeating 标记这是否是一个重复任务。
     * @returns {Object} 一个结构化的任务节点对象。
     */
    private function createTaskNode(id:Number, callback:Function, args:Array, 
                                interval:Number, isRepeating:Boolean):Object {
        var node:Object = {};
        node.id = id;
        node.callback = callback;
        node.args = args || [];
        node.interval = interval;
        node.isRepeating = isRepeating;
        node.isActive = true; // 任务默认是激活状态
        return node;
    }

    // ————————————————————————
    // 公开 API
    // ————————————————————————

    /**
     * 添加一个周期性执行的任务。
     * 
     * @param {Function} callback 每次间隔到达时要执行的函数。
     * @param {Number} intervalMs 任务执行的间隔时间（以毫秒为单位）。会被转换为帧数。
     * @param {Number} repeatCount 任务需要执行的总次数。如果小于等于0，则表示无限次重复。
     * @param {...*} [args] 传递给回调函数的可变参数。
     * @returns {Number} 分配给此任务的唯一ID，可用于 `removeTask`。
     */
    public function addTask(callback:Function, intervalMs:Number, repeatCount:Number):Number {
        var args:Array = [];
        // 从第四个参数开始，均为要传递给回调的参数
        for (var i:Number = 3; i < arguments.length; i++) {
            args.push(arguments[i]);
        }
        
        // 将毫秒间隔转换为帧间隔，最少为1帧
        var intervalFrames:Number = Math.max(1, Math.round(intervalMs / 每帧毫秒));
        var taskId:Number = nextTaskId++;
        var task:Object = createTaskNode(taskId, callback, args, intervalFrames, true);
        
        // 存储重复次数信息
        task.remainingCount = repeatCount;
        
        activeTasks[taskId] = task;
        
        // 首次调度
        scheduleExecution(taskId, intervalFrames);
        
        return taskId;
    }
    
    /**
     * 添加一个仅执行一次的延迟任务。
     * 
     * @param {Number} delay 任务执行前的延迟时间（以毫秒为单位）。
     * @param {Function} callback 延迟结束后要执行的函数。
     * @param {...*} [args] 传递给回调函数的可变参数。
     * @returns {Number} 分配给此任务的唯一ID，可用于 `removeTask`。
     */
    public function addDelayedTask(delay:Number, callback:Function):Number {
        var args:Array = [];
        // 从第三个参数开始，均为要传递给回调的参数
        for (var i:Number = 2; i < arguments.length; i++) {
            args.push(arguments[i]);
        }
        
        // 将毫秒延迟转换为帧延迟，最少为1帧
        var delayFrames:Number = Math.max(1, Math.round(delay / 每帧毫秒));
        var taskId:Number = nextTaskId++;
        var task:Object = createTaskNode(taskId, callback, args, 0, false);

        activeTasks[taskId] = task;
        
        // 调度执行
        scheduleExecution(taskId, delayFrames);
        
        return taskId;
    }

    /**
     * 根据任务ID移除一个已调度或正在运行的任务。
     * 
     * @note 这是一个“惰性删除”。它只是将任务标记为不活跃，
     * 当底层时间轮 (`fastWheel`) 触发该任务时，会检查此标志并跳过执行，
     * 然后任务的内存才会被最终清理。这种方式可以安全地处理正在等待执行的任务。
     * 
     * @param {Number} taskId 通过 `addTask` 或 `addDelayedTask` 返回的任务ID。
     */
    public function removeTask(taskId:Number):Void {
        var task:Object = activeTasks[taskId];
        if (task) {
            // 惰性删除：只标记为不活跃。
            task.isActive = false; 
            // 从活跃任务列表中删除，防止在任务触发前被重复移除。
            delete activeTasks[taskId];
        }
    }
    
    /**
     * 兼容原始 `CooldownWheel` 接口的便捷方法。
     * 直接将任务委托给底层的 `fastWheel`。
     * 
     * @note 使用此方法添加的任务是“即发即忘”的，它不会返回任务ID，因此也无法被取消。
     * 适用于不需要管理的、简单的临时回调。
     * 
     * @param {Number} delay 延迟的帧数。
     * @param {Function} callback 要执行的回调函数。
     */
    public function add(delay:Number, callback:Function):Void {
        fastWheel.add(delay, callback);
    }

    // ————————————————————————
    // 核心调度逻辑
    // ————————————————————————

    /**
     * @private
     * 核心调度函数，负责将任务的“执行信号”委托给底层的 `fastWheel`。
     * 
     * @description
     * 这是本增强型时间轮与底层时间轮解耦的关键。它不直接把用户的 `callback` 交给
     * `fastWheel`，而是创建一个封装了 `taskId` 的新函数 `triggerCallback`。
     * 当 `fastWheel` 执行 `triggerCallback` 时，会回头调用本类的 `_executeTask`
     * 方法，从而进入增强时间轮的管理逻辑中。
     * 
     * @param {Number} taskId 要调度的任务ID。
     * @param {Number} delayFrames 需要延迟多少帧来触发执行。
     */
    private function scheduleExecution(taskId:Number, delayFrames:Number):Void {
        var self:EnhancedCooldownWheel = this;
        
        // 创建一个简单的、闭包的、无参数的触发器回调
        var triggerCallback:Function = function():Void {
            self._executeTask(taskId);
        };
        
        // 使用 fastWheel 来调度这个“触发器”
        fastWheel.add(delayFrames, triggerCallback);
    }
    
    /**
     * @private
     * 任务的实际执行和后续处理逻辑。
     * 当 `fastWheel` 的计时到达并调用 `triggerCallback` 时，此方法被最终执行。
     * 
     * @param {Number} taskId 被触发的任务ID。
     */
    private function _executeTask(taskId:Number):Void {
        var task:Object = activeTasks[taskId];

        // 核心检查：如果任务在等待执行期间被 removeTask() 取消了，
        // 那么 task.isActive 会是 false，或者 activeTasks[taskId] 会是 undefined。
        // 此时应直接返回，不执行任何操作。
        if (!task || !task.isActive) {
            return;
        }

        // 执行用户提供的真实回调函数
        try {
            task.callback.apply(null, task.args);
        } catch (e:Error) {
            trace("任务 " + taskId + " 执行错误: " + e.message);
        }
        
        // 根据任务类型决定后续操作
        if (task.isRepeating) {
            // 对于有次数限制的重复任务
            if (task.remainingCount > 0) {
                task.remainingCount--;
                if (task.remainingCount > 0) {
                    // 次数未用尽，重新调度下一次执行
                    this.scheduleExecution(taskId, task.interval);
                } else {
                    // 次数已用尽，从活跃任务列表中清理
                    delete activeTasks[taskId];
                }
            } else {
                // 对于无限重复的任务，直接重新调度
                this.scheduleExecution(taskId, task.interval);
            }
        } else {
            // 对于一次性任务，执行完毕后直接清理
            delete activeTasks[taskId];
        }
    }
    
    /**
     * 重置整个调度器。
     * 这将会取消并清除所有已添加的任务，并将状态恢复到初始。
     * 
     * @note 此操作会同时重置自身的任务列表和底层的 `fastWheel`。
     */
    public function reset():Void {
        fastWheel.reset();
        activeTasks = {};
        nextTaskId = 1;
    }    
    
    // ————————————————————————
    // 调试用
    // ————————————————————————
    
    /**
     * 获取当前在调度器中管理的活跃任务的数量。
     * 主要用于测试和调试。
     * 
     * @returns {Number} 活跃任务的总数。
     */
    public function getActiveTaskCount():Number {
        var count:Number = 0;
        for (var taskId:String in activeTasks) {
            // 在AS2中，for..in 遍历对象属性是安全的，直接计数即可
            count++;
        }
        return count;
    }
}