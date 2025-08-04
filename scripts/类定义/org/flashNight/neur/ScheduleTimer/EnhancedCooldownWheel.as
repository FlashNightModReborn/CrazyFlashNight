/*
增强版 CooldownWheel - 支持重复任务、任务取消、参数传递
专为替换 VectorAfterimageRenderer 的帧计时器而设计
*/

class org.flashNight.neur.ScheduleTimer.EnhancedCooldownWheel {
    // ————————————————————————
    // 配置常量 & 私有字段
    // ————————————————————————
    private static var WHEEL_SIZE:Number = 120;
    private var slots:Array;                 // Array<TaskNode>[]
    private var pos:Number = WHEEL_SIZE - 1;
    private static var inst:EnhancedCooldownWheel;
    private var nextTaskId:Number = 1;       // 任务ID生成器
    private var activeTasks:Object;          // taskId -> TaskNode 映射
    
    // 每帧毫秒数（假设60FPS）
    public var 每帧毫秒:Number = 1000 / 60;
    
    // ————————————————————————
    // 任务节点类
    // ————————————————————————
    private function TaskNode(id:Number, callback:Function, args:Array, 
                             interval:Number, isRepeating:Boolean) {
        this.id = id;
        this.callback = callback;
        this.args = args || [];
        this.interval = interval;
        this.isRepeating = isRepeating;
        this.isActive = true;
    }
    
    // ————————————————————————
    // 单例获取
    // ————————————————————————
    public static function I():EnhancedCooldownWheel {
        return inst || (inst = new EnhancedCooldownWheel());
    }
    
    // ————————————————————————
    // 构造函数
    // ————————————————————————
    private function EnhancedCooldownWheel() {
        slots = new Array(WHEEL_SIZE);
        activeTasks = {};
        
        for (var i:Number = 0; i < WHEEL_SIZE; ++i) {
            slots[i] = [];
        }
        
        // 创建驱动器
        var depth:Number = _root.getNextHighestDepth();
        var clip:MovieClip = _root.createEmptyMovieClip("_enhancedCdWheel", depth);
        var self:EnhancedCooldownWheel = this;
        clip.onEnterFrame = function():Void {
            self.tick();
        };
    }
    
    // ————————————————————————
    // 公开方法 - 兼容原帧计时器接口
    // ————————————————————————
    
    /**
     * 添加重复任务（兼容原帧计时器接口）
     * @param callback 回调函数
     * @param intervalMs 间隔毫秒数
     * @param repeatCount 重复次数
     * @param args 传递给回调的参数（可变参数）
     * @return 任务ID，用于后续移除
     */
    public function 添加任务(callback:Function, intervalMs:Number, repeatCount:Number):Number {
        var args:Array = [];
        // 获取可变参数（从第4个参数开始）
        for (var i:Number = 3; i < arguments.length; i++) {
            args.push(arguments[i]);
        }
        
        var intervalFrames:Number = Math.max(1, Math.round(intervalMs / 每帧毫秒));
        var taskId:Number = nextTaskId++;
        
        var task:Object = new TaskNode(taskId, callback, args, intervalFrames, true);
        task.remainingCount = repeatCount;
        
        activeTasks[taskId] = task;
        scheduleTask(task, intervalFrames);
        
        return taskId;
    }
    
    /**
     * 移除任务
     * @param taskId 任务ID
     */
    public function 移除任务(taskId:Number):Void {
        var task:Object = activeTasks[taskId];
        if (task) {
            task.isActive = false;
            delete activeTasks[taskId];
        }
    }
    
    /**
     * 添加一次性延迟任务
     * @param delay 延迟毫秒数
     * @param callback 回调函数
     * @param args 传递给回调的参数
     * @return 任务ID
     */
    public function addDelayedTask(delay:Number, callback:Function):Number {
        var args:Array = [];
        for (var i:Number = 2; i < arguments.length; i++) {
            args.push(arguments[i]);
        }
        
        var delayFrames:Number = Math.max(1, Math.round(delay / 每帧毫秒));
        var taskId:Number = nextTaskId++;
        
        var task:Object = new TaskNode(taskId, callback, args, 0, false);
        activeTasks[taskId] = task;
        scheduleTask(task, delayFrames);
        
        return taskId;
    }
    
    /**
     * 兼容原CooldownWheel的add方法
     */
    public function add(delay:Number, callback:Function):Void {
        addDelayedTask(delay * 每帧毫秒, callback);
    }
    
    // ————————————————————————
    // 内部方法
    // ————————————————————————
    
    /**
     * 将任务安排到指定的时间槽
     */
    private function scheduleTask(task:Object, delayFrames:Number):Void {
        var slotIndex:Number = (pos + delayFrames) % WHEEL_SIZE;
        slots[slotIndex].push(task);
    }
    
    /**
     * 每帧执行
     */
    public function tick():Void {
        pos = (pos + 1) % WHEEL_SIZE;
        var list:Array = slots[pos];
        
        // 处理当前槽的所有任务
        while (list.length > 0) {
            var task:Object = list.pop();
            
            if (!task.isActive) {
                continue; // 跳过已取消的任务
            }
            
            // 执行回调
            try {
                if (task.args.length > 0) {
                    task.callback.apply(null, task.args);
                } else {
                    task.callback();
                }
            } catch (error:Error) {
                trace("任务执行错误: " + error.message);
            }
            
            // 处理重复任务
            if (task.isRepeating && task.isActive) {
                if (task.remainingCount > 0) {
                    task.remainingCount--;
                    
                    if (task.remainingCount > 0) {
                        // 重新安排下次执行
                        scheduleTask(task, task.interval);
                    } else {
                        // 任务完成，清理
                        task.isActive = false;
                        delete activeTasks[task.id];
                    }
                } else {
                    // 无限重复
                    scheduleTask(task, task.interval);
                }
            } else {
                // 一次性任务完成
                task.isActive = false;
                delete activeTasks[task.id];
            }
        }
    }
    
    /**
     * 重置时间轮
     */
    public function reset():Void {
        for (var i:Number = 0; i < WHEEL_SIZE; ++i) {
            slots[i] = [];
        }
        pos = WHEEL_SIZE - 1;
        activeTasks = {};
        nextTaskId = 1;
    }
    
    /**
     * 获取当前活跃任务数量（调试用）
     */
    public function getActiveTaskCount():Number {
        var count:Number = 0;
        for (var id:String in activeTasks) {
            count++;
        }
        return count;
    }
}